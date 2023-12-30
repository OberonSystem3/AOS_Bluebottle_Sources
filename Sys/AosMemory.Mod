(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosMemory; (** AUTHOR "pjm"; PURPOSE "Virtual address space management"; *)

IMPORT SYSTEM, AosBoot, AosLocks, AosOut;

CONST
	Stats* = TRUE;	(* maintain statistical counters *)
	Trace = FALSE;	(* write out verbose trace info *)
	TraceStack = FALSE;	(* write out stack trace info *)
	
		(** error codes *)
	Ok* = 0;
	
		(* standard multipliers *)
	K = 1024;  M = 100000H;  G = 40000000H;	(* 1K, 1M, 1G *)
	
		(* paging sizes *)
	PS = 4096;	(* page size in bytes *)
	PSlog2 = 12;	(* ASH(1, PSlog2) = PS *)
	RS = 4*M;	(* region covered by a page table in bytes *)
	PTEs = RS DIV PS;	(* number of page table/directory entries *)
	
	ReservedPages = 8;	(* pages reserved on page heap (not for normal heap use) *)

	NilAdr* = -1;	(** nil value for addresses (not same as pointer NIL value) *)
	
		(* free page stack page node layout *)
	NodeSP = 0;
	NodeNext = 4;
	NodePrev = 8;
	MinSP = 12; MaxSP = PS;
	
(*
0	sp
4	nextAdr
8	prevAdr
12	first entry
4092	last entry
*)

		(* virtual memory layout.  no area will cross the 2G boundary, to avoid LONGINT sign problems. *)
	HeapAreaAdr = M;	(* heap: 1M..1G *)
	HeapAreaSize = G-M;	(* also see AosBoot.MaxMemTop *)
	PhysAreaAdr = G;	(* physical mapping: 1G..2G *)
	PhysAreaSize = G;
	MapAreaAdr = 80000000H;	(* dynamic mappings: bottom part of 2G..4G *)
	MapAreaSize = 64*M;
	IntelAreaAdr = 0FEE00000H;	(* reserved by Intel for APIC: 4G-18M..4G-18M+4K *)
	IntelAreaSize = 00001000H;
	StackAreaAdr = MapAreaAdr+MapAreaSize;	(* stacks: middle part of 2G..4G *)
	StackAreaSize = IntelAreaAdr-StackAreaAdr;
	
		(* stack sizes *)
	KernelStackSize = 2*PS;	(* multiple of PS *)
	MaxUserStackSize = 128*K;	(* multiple of PS *)
	InitUserStackSize = PS;	(* must be PS (or change NewStack) *)
	UserStackGuardSize = PS;	(* multiple of PS left unallocated at bottom of stack virtual area *)
	MaxUserStacks = StackAreaSize DIV MaxUserStackSize;
	
		(* physical memory layout *)
	LowAdr = PS;	(* lowest physical address used *)
	LinkAdr = M;	(* address where kernel is linked, also address where heap begins *)
	StaticBlockSize = 32;	(* static heap block size *)

		(* gdt indices *)
	TSSOfs = 6;	(* offset in GDT of TSSs *)
	StackOfs = TSSOfs + AosBoot.MaxCPU;	(* offset in GDT of stacks *)
	GDTSize = StackOfs + AosBoot.MaxCPU;
	
		(* gdt selectors *)
	KernelCodeSel = 1*8;	(* selector 1 in gdt, RPL 0 *)
	KernelStackSel = 2*8;	(* selector 2 in gdt, RPL 0 *)
	UserCodeSel = 3*8 + 3;	(* selector 3 in gdt, RPL 3 *)
	DataSel = 4*8;	(* selector 4 in gdt, RPL 0 *)
	UserStackSel = 5*8 + 3;	(* selector 5 in gdt, RPL 3 *)
	KernelTR = TSSOfs*8;	(* selector in gdt, RPL 0 *)
	
		(* paging flags *)
	PageNotPresent = 0;	(* not present page *)
	KernelPage = 3;	(* supervisor, present, r/w *)
	UserPage = 7;	(* user, present, r/w *)

	EndBlockOfs = 38H;	(* cf. AosLinker0 *)

TYPE
	Stack* = RECORD	(** values are read-only *)
		low: LONGINT;	(* lowest virtual address that may be allocated for stack *)
		adr*: LONGINT;	(* lowest address on allocated stack *)	(* exported for AosActive only *)
		high*: LONGINT;	(* next virtual address after stack *)	(* exported for AosActive only *)
	END;
	
		(* task state segment *)
	TSSDesc = RECORD	(* 1, p. 485 and p. 612 for required fields *)
		Link: LONGINT;	(* lower 16 bits significant *)
		ESP0: LONGINT;
		ESS0: LONGINT;	(* lower 16 bits significant *)
		ESP1: LONGINT;
		ESS1: LONGINT;	(* lower 16 bits significant *)
		ESP2: LONGINT;
		ESS2: LONGINT;	(* lower 16 bits significant *)
		CR3: LONGINT;
		EIP: LONGINT;
		EFLAGS: SET;
		EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI: LONGINT;
		ES, CS, SS, DS, FS, GS: LONGINT;	(* lower 16 bits significant *)
		LDT: LONGINT;	(* lower 16 bits significant *)
		TaskAttributes: INTEGER;
		IOBitmapOffset: INTEGER
	(* Implicit: IOBitmap: ARRAY 8192 DIV 4 OF SET *)
	END;

	Startup* = PROCEDURE;	(** can not be a method *)
	
		(* global descriptor table *)
	SegDesc = RECORD
		low, high: LONGINT
	END;
	GDT = ARRAY GDTSize OF SegDesc;

	Range* = RECORD
		adr*, size*: LONGINT
	END;

VAR
	GlobalFlushTLB*: PROCEDURE;
	
	gdt: GDT;	(* global descriptor table *)
	proc: ARRAY AosBoot.MaxCPU OF RECORD	(* indexed by AosBoot.ID() *)
		tss: TSSDesc;
		esp: LONGINT;	(* snapshot for GC *)
		stack: Stack
	END;
	kernelPD: LONGINT;	(* physical address of page directory *)
	
	freeLowPage: LONGINT;	(* free low page stack pointer (link at offset 0 in page).  All addresses physical.  NIL = -1 *)
	freeLowPages, freeHighPages, totalPages: LONGINT;	(* number of free pages and total number of pages *)
	
	mapTop: LONGINT;	(* virtual address of end of memory mapping area *)
	heapEndAdr: LONGINT;	(* virtual address of end of heap (page aligned) *)
	
	topPageNum: LONGINT;	(* page containing byte memTop-1 *)
	pageHeapAdr: LONGINT;	(* address (physical and virtual) of bottom of page heap area *)
	pageStackAdr: LONGINT;	(* virtual address of top page of free page stack *)
	
	freeStack: ARRAY (MaxUserStacks+31) DIV 32 OF SET;	(* free stack bitmap *)
	freeStackIndex: LONGINT;	(* current position in bitmap (rotates) *)
	
	Nbigskips-: LONGINT;	(* number of times a stack was extended leaving a hole *)
	Nfilled-: LONGINT;	(* number of times a "hole" in a stack was filled *)
	NnewStacks-, NnewStackLoops-, NnewStackInnerLoops-, NdisposeStacks-, 
	NlostPages-, NreservePagesUsed-, NmaxUserStacks-: LONGINT;
	
(* Load global descriptor table *)

PROCEDURE LoadGDT(base, size: LONGINT);
CODE {SYSTEM.i386, SYSTEM.Privileged}
	SHL size[EBP], 16
	MOV EBX, 2
	LGDT size[EBP][EBX]
END LoadGDT;

(* Load segment registers *)

PROCEDURE LoadSegRegs(data: LONGINT);
CODE {SYSTEM.i386}
	MOV EAX, data[EBP]
	MOV DS, AX
	MOV ES, AX
	XOR EAX, EAX
	MOV FS, AX
	MOV GS, AX
END LoadSegRegs;

(* Return CS. *)

PROCEDURE -CS(): LONGINT;
CODE {SYSTEM.i386}
	XOR EAX, EAX
	MOV AX, CS
END CS;

(** -- Memory management -- *)

(* Allocate a physical page below 1M.  Parameter adr returns physical and virtual address (or NilAdr).*)

PROCEDURE NewLowPage(VAR adr: LONGINT);
BEGIN
	adr := freeLowPage;
	IF freeLowPage # NilAdr THEN
		SYSTEM.GET(freeLowPage, freeLowPage);	(* freeLowPage := freeLowPage.next *)
		DEC(freeLowPages)
	END
END NewLowPage;

(* Allocate a directly-mapped page.  Parameter adr returns physical and virtual address (or NilAdr). *)

PROCEDURE NewDirectPage(VAR adr: LONGINT);
BEGIN
	IF pageHeapAdr # heapEndAdr THEN
		DEC(pageHeapAdr, PS); adr := pageHeapAdr;
		DEC(freeHighPages)
	ELSE
		adr := NilAdr
	END
END NewDirectPage;

(* Allocate a physical page. *)

PROCEDURE NewPage(VAR physAdr: LONGINT);
VAR sp: LONGINT;
BEGIN
	sp := SYSTEM.GET32(pageStackAdr+NodeSP);
	ASSERT((sp >= MinSP) & (sp <= MaxSP) & (sp MOD 4 = 0));	(* index check *)
	IF sp > MinSP THEN	(* stack not empty, pop entry *)
		DEC(sp, 4);
		physAdr := SYSTEM.GET32(pageStackAdr+sp);
		SYSTEM.PUT32(pageStackAdr+NodeSP, sp);
		IF (sp = MinSP) & (SYSTEM.GET32(pageStackAdr+NodePrev) # NilAdr) THEN
			pageStackAdr := SYSTEM.GET32(pageStackAdr+NodePrev)
		END;
		DEC(freeHighPages)
	ELSE
		NewDirectPage(physAdr)
	END
END NewPage;

(* Deallocate a physical page. *)

PROCEDURE DisposePage(physAdr: LONGINT);
VAR sp, newAdr: LONGINT;
BEGIN
	sp := SYSTEM.GET32(pageStackAdr+NodeSP);
	ASSERT((sp >= MinSP) & (sp <= MaxSP) & (sp MOD 4 = 0));	(* index check *)
	IF sp = MaxSP THEN	(* current stack full *)
		IF SYSTEM.GET32(pageStackAdr+NodeNext) # NilAdr THEN	(* next stack exists, make it current *)
			pageStackAdr := SYSTEM.GET32(pageStackAdr+NodeNext);
			sp := SYSTEM.GET32(pageStackAdr+NodeSP);
			ASSERT(sp = MinSP)	(* must be empty *)
		ELSE	(* allocate next stack *)
			NewDirectPage(newAdr);
			IF newAdr = NilAdr THEN
				NewLowPage(newAdr);	(* try again from reserve *)
				IF newAdr = NilAdr THEN
					IF Stats THEN INC(NlostPages) END;
					RETURN	(* give up (the disposed page is lost) *)
				ELSE
					IF Stats THEN INC(NreservePagesUsed) END
				END
			END;
			sp := MinSP;	(* will be written to NodeSP below *)
			SYSTEM.PUT32(newAdr+NodeNext, NilAdr);
			SYSTEM.PUT32(newAdr+NodePrev, pageStackAdr);
			pageStackAdr := newAdr
		END
	END;
		(* push entry on current stack *)
	SYSTEM.PUT32(pageStackAdr+sp, physAdr);
	SYSTEM.PUT32(pageStackAdr+NodeSP, sp+4);
	INC(freeHighPages)
END DisposePage;

(* Allocate virtual address space for mapping.  Parameter size must be multiple of page size.  Parameter virtAdr returns virtual address or NilAdr on failure. *)

PROCEDURE NewVirtual(VAR virtAdr: LONGINT; size: LONGINT);
BEGIN
	ASSERT(size MOD PS = 0);
	IF mapTop+size > MapAreaAdr+MapAreaSize THEN
		virtAdr := NilAdr	(* out of virtual space *)
	ELSE
		virtAdr := mapTop;
		INC(mapTop, size)
	END
END NewVirtual;

PROCEDURE DisposeVirtual(virtAdr, size: LONGINT);
BEGIN
	(* to do *)
END DisposeVirtual;

(* Map a physical page into the virtual address space.  Parameter virtAdr is mapped address and phys is mapping value.  Returns TRUE iff mapping successful. *)

PROCEDURE MapPage(virtAdr, phys: LONGINT): BOOLEAN;
VAR i, pt: LONGINT;
BEGIN
	i := virtAdr DIV RS MOD PTEs;
	SYSTEM.GET(kernelPD + 4*i, pt);
	IF ODD(pt) THEN	(* pt present *)
		DEC(pt, pt MOD PS)
	ELSE
		NewPage(pt);
		IF pt = NilAdr THEN RETURN FALSE END;
		SYSTEM.PUT(kernelPD + 4*i, pt + UserPage);
		AosBoot.Fill32(pt, PTEs*4, PageNotPresent)
	END;
	SYSTEM.PUT(pt + 4*(virtAdr DIV PS MOD PTEs), phys);
	RETURN TRUE
END MapPage;

(* Return mapped page address for a given virtual address (ODD if mapped) *)

PROCEDURE MappedPage(virtAdr: LONGINT): LONGINT;
VAR pt: LONGINT;
BEGIN
	SYSTEM.GET(kernelPD + 4*(virtAdr DIV RS MOD PTEs), pt);
	IF ODD(pt) THEN	(* pt present *)
		RETURN SYSTEM.GET32(pt - pt MOD PS + 4*(virtAdr DIV PS MOD PTEs))
	ELSE
		RETURN 0	(* ~ODD *)
	END
END MappedPage;

(* Unmap a page and return the previous mapping, like MappedPage().  Caller must flush TLB. *)

PROCEDURE UnmapPage(virtAdr: LONGINT): LONGINT;
VAR t, pt: LONGINT;
BEGIN
	SYSTEM.GET(kernelPD + 4*(virtAdr DIV RS MOD PTEs), pt);
	IF ODD(pt) THEN	(* pt present *)
		pt := pt - pt MOD PS + 4*(virtAdr DIV PS MOD PTEs);
		SYSTEM.GET(pt, t);
		SYSTEM.PUT(pt, NIL);	(* unmap *)
			(* could use INVLPG here, but it is not supported equally on all processors *)
		RETURN t
	ELSE
		RETURN 0	(* ~ODD *)
	END
END UnmapPage;

(* Map area [virtAdr..virtAdr+size) directly to area [Adr(phys)..Adr(phys)+size).  Returns TRUE iff successful. *)

PROCEDURE MapDirect(virtAdr, size, phys: LONGINT): BOOLEAN;
BEGIN
(*
	AosOut.String("MapDirect");  AosOut.Hex(virtAdr, 9);  AosOut.Hex(phys, 9);  AosOut.Hex(size, 9);  
	AosOut.Int(size DIV PS, 8);  AosOut.Ln;
*)
	ASSERT((virtAdr MOD PS = 0) & (size MOD PS = 0));
	WHILE size # 0 DO
		IF ~ODD(MappedPage(virtAdr)) THEN
			IF ~MapPage(virtAdr, phys) THEN RETURN FALSE END
		END;
		INC(virtAdr, PS); INC(phys, PS); DEC(size, PS)
	END;
	RETURN TRUE
END MapDirect;

(*
(** DEPRECATED, use heap memory and PhysicalAdr. Allocate a physical page. *)

PROCEDURE NewPhysicalPage*(VAR physAdr: LONGINT);
BEGIN
	AosLocks.Acquire(AosLocks.AosMemory);
	NewPage(physAdr); ASSERT(physAdr # NilAdr);
	AosLocks.Release(AosLocks.AosMemory)
END NewPhysicalPage;
*)

(** Attempt to set the heap end address to the specified address.  The returned value is the actual new end address (never smaller than previous value). *)

PROCEDURE SetHeapEndAdr*(VAR endAdr: LONGINT);
VAR n, m: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosMemory);
	n := SYSTEM.LSH(endAdr+(PS-1), -PSlog2) - SYSTEM.LSH(heapEndAdr, -PSlog2);	(* pages requested *)
	m := SYSTEM.LSH(pageHeapAdr, -PSlog2) - SYSTEM.LSH(heapEndAdr, -PSlog2) - ReservedPages;	(* max pages *)
	IF n > m THEN n := m END;
	IF n > 0 THEN INC(heapEndAdr, n*PS); DEC(freeHighPages, n) END;
	endAdr := heapEndAdr;
	AosLocks.Release(AosLocks.AosMemory)
END SetHeapEndAdr;

(** Map a physical memory area (physAdr..physAdr+size-1) into the virtual address space.  Parameter virtAdr returns the virtual address of mapped region, or NilAdr on failure. *)

PROCEDURE MapPhysical*(physAdr, size: LONGINT; VAR virtAdr: LONGINT);
VAR ofs: LONGINT;
BEGIN
	IF (SYSTEM.LSH(physAdr, -PSlog2) <= topPageNum) &
			(SYSTEM.LSH(physAdr+size-1, -PSlog2) <= topPageNum) &
			(SYSTEM.LSH(physAdr, -PSlog2) >= SYSTEM.LSH(LowAdr, -PSlog2)) THEN
		virtAdr := physAdr	(* directly mapped *)
	ELSE
		ofs := physAdr MOD PS;
		DEC(physAdr, ofs); INC(size, ofs);	(* align start to page boundary *)
		INC(size, (-size) MOD PS);	(* align end to page boundary *)
		AosLocks.Acquire(AosLocks.AosMemory);
		NewVirtual(virtAdr, size);
		IF virtAdr # NilAdr THEN
			IF ~MapDirect(virtAdr, size, physAdr + UserPage) THEN
				DisposeVirtual(virtAdr, size);
				virtAdr := NilAdr
			END
		END;
		AosLocks.Release(AosLocks.AosMemory);
		IF Trace THEN
			AosOut.Enter;
			AosOut.String("Mapping ");
			AosOut.IntSuffix(size, 1, "B"); AosOut.String(" at");
			AosOut.Hex(physAdr, 9); AosOut.Char("-"); AosOut.Hex(physAdr+size-1, 8);
			IF virtAdr = NilAdr THEN
				AosOut.String(" failed")
			ELSE
				AosOut.String(" to"); AosOut.Hex(virtAdr, 9);
				IF ofs # 0 THEN AosOut.String(", offset "); AosOut.Int(ofs, 1) END
			END;
			AosOut.Exit
		END;
		IF virtAdr # NilAdr THEN INC(virtAdr, ofs) END	(* adapt virtual address to correct offset *)
	END
END MapPhysical;

(** Unmap an area previously mapped with MapPhysical. *)

PROCEDURE UnmapPhysical*(virtAdr, size: LONGINT);
BEGIN
	(* to do *)
END UnmapPhysical;

(** Return the physical address of the specified range of memory, or NilAdr if the range is not contiguous.  It is the caller's responsibility to assure the range remains allocated during the time it is in use. *)

PROCEDURE PhysicalAdr*(adr, size: LONGINT): LONGINT;
VAR physAdr, mapped, expected: LONGINT;
BEGIN
	IF (SYSTEM.LSH(adr, -PSlog2) <= topPageNum) & (SYSTEM.LSH(adr+size-1, -PSlog2) <= topPageNum) THEN
		RETURN adr	(* directly mapped *)
	ELSE
		AosLocks.Acquire(AosLocks.AosMemory);
		mapped := MappedPage(adr);
		AosLocks.Release(AosLocks.AosMemory);
		IF ODD(mapped) & (size > 0) THEN	(* mapped, and range not empty or too big *)
			physAdr := mapped - mapped MOD PS + adr MOD PS;	(* strip paging bits and add page offset *)
				(* now check if whole range is physically contiguous *)
			DEC(size, PS - adr MOD PS);	(* subtract distance to current page end *)
			IF size > 0 THEN	(* range crosses current page end *)
				expected := SYSTEM.LSH(mapped, -PSlog2)+1;	(* expected physical page *)
				LOOP
					INC(adr, PS);	(* step to next page *)
					AosLocks.Acquire(AosLocks.AosMemory);
					mapped := MappedPage(adr);
					AosLocks.Release(AosLocks.AosMemory);
					IF ~ODD(mapped) OR (SYSTEM.LSH(mapped, -PSlog2) # expected) THEN
						physAdr := NilAdr; EXIT
					END;
					DEC(size, PS);
					IF size <= 0 THEN EXIT END;	(* ok *)
					INC(expected)
				END
			ELSE
				(* ok, skip *)
			END
		ELSE
			physAdr := NilAdr
		END;
		RETURN physAdr
	END
END PhysicalAdr;

(** Translate a virtual address range to num ranges of physical address.  num returns 0 on error. *)

PROCEDURE TranslateVirtual*(virtAdr, size: LONGINT;  VAR num: LONGINT; VAR physAdr: ARRAY OF Range);
VAR ofs, phys1, size1: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosMemory);
	num := 0;
	LOOP
		IF size = 0 THEN EXIT END;
		IF num = LEN(physAdr) THEN num := 0; EXIT END;	(* index check *)
		ofs := virtAdr MOD PS;	(* offset in page *)
		size1 := PS - ofs;	(* distance to next page boundary *)
		IF size1 > size THEN size1 := size END;
		phys1 := MappedPage(virtAdr);
		IF ~ODD(phys1) THEN num := 0; EXIT END;	(* page not present *)
		physAdr[num].adr := phys1 - phys1 MOD PS + ofs;
		physAdr[num].size := size1;  INC(num);
		INC(virtAdr, size1); DEC(size, size1)
	END;
	IF num = 0 THEN physAdr[0].adr := NilAdr; physAdr[0].size := 0 END;
	AosLocks.Release(AosLocks.AosMemory)
END TranslateVirtual;

(** Return information on free memory in Kbytes. *)

PROCEDURE GetFreeK*(VAR total, lowFree, highFree: LONGINT);
CONST KperPage = PS DIV 1024;
BEGIN
	AosLocks.Acquire(AosLocks.AosMemory);
	total := totalPages * KperPage;
	lowFree := freeLowPages * KperPage;
	highFree := freeHighPages * KperPage;
	AosLocks.Release(AosLocks.AosMemory)
END GetFreeK;

(** -- Stack -- *)

(** Extend the stack to include the specified address, if possible.  Returns TRUE iff ok. *)

PROCEDURE ExtendStack*(VAR s: Stack; virtAdr: LONGINT): BOOLEAN;
VAR phys: LONGINT; ok: BOOLEAN;
BEGIN
	AosLocks.Acquire(AosLocks.AosMemory);
	ok := FALSE;
	IF (virtAdr < s.high) & (virtAdr >= s.low) THEN
		DEC(virtAdr, virtAdr MOD PS);	(* round down to page boundary *)
		IF Stats & (virtAdr < s.adr-PS) THEN INC(Nbigskips) END;
		IF ODD(MappedPage(virtAdr)) THEN	(* already mapped *)
			ok := TRUE
		ELSE
			NewPage(phys);
			IF phys # NilAdr THEN
				IF MapPage(virtAdr, phys + UserPage) THEN
					IF virtAdr < s.adr THEN
						s.adr := virtAdr
					ELSE
						IF Stats THEN INC(Nfilled) END
					END;
					ok := TRUE
				ELSE
					DisposePage(phys)
				END
			END
		END
	END;
	AosLocks.Release(AosLocks.AosMemory);
	RETURN ok
END ExtendStack;

(** Allocate a stack.  Parameter initSP returns initial stack pointer value. *)

PROCEDURE NewStack*(VAR s: Stack; process: PTR; VAR initSP: LONGINT);
VAR adr, phys, old: LONGINT; free: SET;
BEGIN
	ASSERT(InitUserStackSize = PS);	(* for now *)
	AosLocks.Acquire(AosLocks.AosMemory);
	IF Stats THEN INC(NnewStacks) END;
	old := freeStackIndex;
	LOOP
		IF Stats THEN INC(NnewStackLoops) END;
		free := freeStack[freeStackIndex];
		IF free # {} THEN
			adr := 0; WHILE ~(adr IN free) DO INC(adr) END;	(* BTW: BSF instruction is not faster *)
			IF Stats THEN INC(NnewStackInnerLoops, adr+1) END;
			EXCL(freeStack[freeStackIndex], adr);
			adr := StackAreaAdr + (freeStackIndex*32 + adr)*MaxUserStackSize;
			EXIT
		END;
		INC(freeStackIndex);
		IF freeStackIndex = LEN(freeStack) THEN freeStackIndex := 0 END;
		IF freeStackIndex = old THEN HALT(1503) END	(* out of stack space *)
	END;
	NewPage(phys); ASSERT(phys # NilAdr);	(* allocate one physical page at first *)
	s.high := adr + MaxUserStackSize; s.low := adr + UserStackGuardSize;
	s.adr := s.high - InitUserStackSize;	(* at the top of the virtual area *)
	initSP := s.high-4;
	IF ~MapPage(s.adr, phys + UserPage) THEN HALT(99) END;
	SYSTEM.PUT(initSP, process);
	AosLocks.Release(AosLocks.AosMemory)
END NewStack;

(** Return the process pointer set when the current user stack was created (must be running on user stack). *)

PROCEDURE -GetProcessPtr*(): PTR;
CONST Mask = -MaxUserStackSize; Ofs = MaxUserStackSize-4;
CODE {SYSTEM.i386}
	POP EAX
	MOV EAX, Mask
	AND EAX, ESP
	MOV EAX, Ofs[EAX]
END GetProcessPtr;

(** True iff current process works on a kernel stack *)

PROCEDURE WorkingOnKernelStack*(): BOOLEAN;
VAR id, esp: LONGINT;
BEGIN
	ASSERT(KernelStackSize # MaxUserStackSize - UserStackGuardSize); (* detection does only work with this assumption *)
	SYSTEM.GETREG(SYSTEM.ESP, esp);
	id := AosBoot.ID(); 
	RETURN (esp >= proc[id].stack.low) & (esp <= proc[id].stack.high)
END WorkingOnKernelStack;

(** Deallocate a stack.  Current thread should not dispose its own stack.  Uses privileged instructions. *)

PROCEDURE DisposeStack*(VAR s: Stack);
VAR adr, phys: LONGINT;
BEGIN
		(* First make sure there are no references to virtual addresses of the old stack in the TLBs.  This is required because we are freeing the pages, and they could be remapped later at different virtual addresses.  DisposeStack will only be called from the thread finalizer, which ensures that the user will no longer be referencing this memory.  Therefore we can make this upcall from outside the locked region, avoiding potential deadlock. *)
	GlobalFlushTLB;	(* finalizers are only called after AosProcessors has initialized this upcall *)
	AosLocks.Acquire(AosLocks.AosMemory);
	IF Stats THEN INC(NdisposeStacks) END;
	adr := s.adr;	(* unmap and deallocate all pages of stack *)
	REPEAT
		phys := UnmapPage(adr);	(* TLB was flushed and no intermediate references possible to unreachable stack *)
		IF ODD(phys) THEN DisposePage(phys - phys MOD PS) END;
		INC(adr, PS)
	UNTIL adr = s.high;
	adr := (adr - MaxUserStackSize - StackAreaAdr) DIV MaxUserStackSize;
	INCL(freeStack[adr DIV 32], adr MOD 32);
	AosLocks.Release(AosLocks.AosMemory)
END DisposeStack;

(** Check if the specified stack is valid. *)

PROCEDURE ValidStack*(VAR s: Stack; sp: LONGINT): BOOLEAN;
VAR valid: BOOLEAN;
BEGIN
	AosLocks.Acquire(AosLocks.AosMemory);
	valid := (sp MOD 4 = 0) & (sp >= s.adr) & (sp <= s.high);
	WHILE valid & (sp < s.high) DO
		valid := ODD(MappedPage(sp));
		INC(sp, PS)
	END;
	AosLocks.Release(AosLocks.AosMemory);
	RETURN valid
END ValidStack;

(** Get user stack pointer. *)

(* ug: not used *)
(*
PROCEDURE GetUserStack*(VAR userSP: LONGINT);
VAR esp0, ss: LONGINT;
BEGIN
	ASSERT(CS() MOD 4 = 0);	(* to get user stack pointer *)
	esp0 := proc[AosBoot.ID()].tss.ESP0;
	SYSTEM.GET(esp0-4, ss);	(* cf. AosInterrupts.FieldInterrupt *)
	IF ss MOD 10000H = UserStackSel THEN	(* from user level *)
		SYSTEM.GET(esp0-8, userSP)
	ELSE	(* possibly from VM mode, or during init (processor still at level 0) *)
		userSP := 0;	(* user stack not found *)
		IF TraceStack THEN
			AosOut.Enter;
			AosOut.String("GetUserStack"); AosOut.Ln;
			AosOut.Memory(esp0-128, 128);
			AosOut.Exit
		END
	END
END GetUserStack;
*)

(** Update the stack snapshot of the current processor.  (for AosProcessors) *)

PROCEDURE UpdateState*;
VAR id: LONGINT;
BEGIN
	ASSERT(CS() MOD 4 = 0);	(* to get kernel stack pointer *)
	id := AosBoot.ID();
	ASSERT(proc[id].stack.high # 0);	(* current processor stack has been assigned *)
	SYSTEM.GETREG(SYSTEM.EBP, proc[id].esp)	(* instead of ESP, just fetch EBP of current procedure (does not contain pointers) *)
END UpdateState;

(** Get kernel stack regions for garbage collection.  (for AosHeap) *)

PROCEDURE GetKernelStacks*(VAR stack: ARRAY OF Stack);
VAR i: LONGINT;
BEGIN	(* {UpdateState has been called by each processor} *)
	FOR i := 0 TO AosBoot.MaxCPU-1 DO
		stack[i].adr := proc[i].esp;
		stack[i].high := proc[i].stack.high
	END
END GetKernelStacks;

(* Init page tables (paging still disabled until EnableMM is called). *)

PROCEDURE InitPages;
VAR i, j, phys, lowTop, memTop: LONGINT;
BEGIN
		(* get top of high and low memory *)
	memTop := AosBoot.memTop;
	DEC(memTop, memTop MOD PS);	(* memTop MOD PS = 0 *)
	topPageNum := SYSTEM.LSH(memTop-1, -PSlog2);
	lowTop := AosBoot.lowTop;
	DEC(lowTop, lowTop MOD PS);	(* lowTop MOD PS = 0 *)
		(* initialize NewDirectPage and SetHeapEndAdr (get kernel range) *)
	SYSTEM.GET(LinkAdr+EndBlockOfs, heapEndAdr);	(* new place *)
	IF heapEndAdr = 0 THEN SYSTEM.GET(LinkAdr+16H, heapEndAdr) END;	(* old place *)
	SYSTEM.PUT(heapEndAdr, NIL);	(* set tag to NIL *)
	INC(heapEndAdr, 4);	(* space for NIL *)
	INC(heapEndAdr, (-heapEndAdr) MOD PS);	(* round up to page size *)
	pageHeapAdr := memTop;
	freeHighPages := SYSTEM.LSH(pageHeapAdr, -PSlog2) - SYSTEM.LSH(heapEndAdr, -PSlog2);
	IF Trace THEN
		AosOut.String("Kernel:"); AosOut.Hex(LinkAdr, 9); AosOut.String("..");
		AosOut.Hex(heapEndAdr-1, 8); AosOut.Ln;
		AosOut.String("High:"); AosOut.Hex(heapEndAdr, 9); AosOut.String("..");
		AosOut.Hex(pageHeapAdr-1, 8); AosOut.String(" = "); AosOut.Int(freeHighPages, 1);
		AosOut.String(" free pages"); AosOut.Ln
	END;
		(* initialize empty free page stack *)
	NewDirectPage(pageStackAdr); ASSERT(pageStackAdr # NilAdr);
	SYSTEM.PUT32(pageStackAdr+NodeSP, MinSP);
	SYSTEM.PUT32(pageStackAdr+NodeNext, NilAdr);
	SYSTEM.PUT32(pageStackAdr+NodePrev, NilAdr);
		(* free low pages *)
	freeLowPage := NilAdr;  freeLowPages := 0;
	i := lowTop DIV PS; j := LowAdr DIV PS;
	IF Trace THEN
		AosOut.String("Low:");  AosOut.Hex(j*PS, 9);  AosOut.String("..");  AosOut.Hex(i*PS-1, 8)
	END;
	REPEAT
		DEC(i); phys := i*PS;
		SYSTEM.PUT(phys, freeLowPage);	(* phys.next := freeLowPage *)
		freeLowPage := phys; INC(freeLowPages)
	UNTIL i = j;
	IF Trace THEN
		AosOut.String(" = "); AosOut.Int(freeLowPages, 1); AosOut.String(" free pages"); AosOut.Ln
	END;
	totalPages := SYSTEM.LSH(AosBoot.memTop - M + AosBoot.lowTop + AosBoot.dmaSize + PS, -PSlog2);	(* what BIOS gave us *)
		(* stacks *)
	ASSERT((StackAreaAdr MOD MaxUserStackSize = 0) & (StackAreaSize MOD MaxUserStackSize = 0));
	FOR i := 0 TO LEN(freeStack)-1 DO freeStack[i] := {0..31} END;
	FOR i := MaxUserStacks TO LEN(freeStack)*32-1 DO EXCL(freeStack[i DIV 32], i MOD 32) END;
	freeStackIndex := 0;
		(* mappings *)
	mapTop := MapAreaAdr;
		(* create the address space *)
	NewPage(kernelPD); ASSERT(kernelPD # NilAdr);
	AosBoot.Fill32(kernelPD, PTEs*4, PageNotPresent);
	IF ~MapDirect(LowAdr, memTop-LowAdr, LowAdr + UserPage) THEN HALT(99) END	(* map heap direct *)
END InitPages;

(* Generate a memory segment descriptor.  type IN {0..7} & dpl IN {0..3}. 

type
0	data, expand-up, read-only
1	data, expand-up, read-write
2	data, expand-down, read-only
3	data, expand-down, read-write
4	code, non-conforming, execute-only
5	code, non-conforming, execute-read
6	code, conforming, execute-only
7	code, conforming, execute-read
*)

PROCEDURE GenMemSegDesc(type, base, limit, dpl: LONGINT;  page: BOOLEAN;  VAR sd: SegDesc);
VAR s: SET;
BEGIN
	sd.low := ASH(base MOD 10000H, 16) + limit MOD 10000H;
	s := SYSTEM.VAL(SET, ASH(ASH(base, -24), 24) + ASH(ASH(limit, -16), 16) + 
		ASH(dpl, 13) + ASH(type, 9) + ASH(base, -16) MOD 100H);
	s := s + {12, 15, 22};	(* code/data=1, present=1, 32-bit=1, A=0, AVL=0 *)
	IF page THEN INCL(s, 23) END;	(* page granularity *)
	sd.high := SYSTEM.VAL(LONGINT, s)
END GenMemSegDesc;

(* Generate a TSS descriptor. *)

PROCEDURE GenTSSDesc(base, limit, dpl: LONGINT;  VAR sd: SegDesc);
VAR s: SET;
BEGIN
	sd.low := ASH(base MOD 10000H, 16) + limit MOD 10000H;
	s := SYSTEM.VAL(SET, ASH(ASH(base, -24), 24) + ASH(ASH(limit, -16), 16) + 
		ASH(dpl, 13) + ASH(base, -16) MOD 100H);
	s := s + {8, 11, 15};	(* type=non-busy TSS, present=1, AVL=0, 32-bit=0 *)
	sd.high := SYSTEM.VAL(LONGINT, s)
END GenTSSDesc;

(* Initialize segmentation. *)

PROCEDURE InitSegments;
VAR i: LONGINT;
BEGIN
		(* GDT 0: Null segment *)
	gdt[0].low := 0;  gdt[0].high := 0;
		(* GDT 1: Kernel code: non-conforming, execute-read, base 0, limit 4G, PL 0 *)
	GenMemSegDesc(5, 0, M-1, 0, TRUE, gdt[1]);
		(* GDT 2: Kernel stack: expand-up, read-write, base 0, limit 4G, PL 0 *)
	GenMemSegDesc(1, 0, M-1, 0, TRUE, gdt[2]);
		(* GDT 3: User code: conforming, execute-read, base 0, limit 4G, PL 0 *)
	GenMemSegDesc(7, 0, M-1, 0, TRUE, gdt[3]);
		(* GDT 4: User/Kernel data: expand-up, read-write, base 0, limit 4G, PL 3 *)
	GenMemSegDesc(1, 0, M-1, 3, TRUE, gdt[4]);
		(* GDT 5: User stack: expand-down, read-write, base 0, limit 1M, PL 3 *)
	GenMemSegDesc(3, 0, M DIV PS, 3, TRUE, gdt[5]);
		(* GDT TSSOfs..n: Kernel TSS *)
	FOR i := 0 TO AosBoot.MaxCPU-1 DO
		GenTSSDesc(SYSTEM.ADR(proc[i].tss), SIZE(TSSDesc)-1, 0, gdt[TSSOfs+i]);
		proc[i].esp := 0;  proc[i].stack.high := 0
	END
END InitSegments;

(* Enable segmentation on the current processor. *)

PROCEDURE EnableSegments;
BEGIN
	LoadGDT(SYSTEM.ADR(gdt[0]), SIZE(GDT)-1);
	LoadSegRegs(DataSel)
END EnableSegments;

(* Allocate a kernel stack. *)

PROCEDURE NewKernelStack(VAR stack: Stack);
VAR phys, virt, size: LONGINT;
BEGIN
	size := KernelStackSize;
	NewVirtual(virt, size + PS);	(* add one page for overflow protection *)
	ASSERT(virt # NilAdr, 1502);
	INC(virt, PS);	(* leave page open at bottom *)
	stack.low := virt;
	stack.adr := virt;	(* return stack *)
	REPEAT
		NewPage(phys); ASSERT(phys # NilAdr);
		IF ~MapPage(virt, phys + KernelPage) THEN HALT(99) END;
		DEC(size, PS);  INC(virt, PS)
	UNTIL size = 0;
	stack.high := virt
END NewKernelStack;

(* Set task register *)

PROCEDURE -SetTR(tr: LONGINT);
CODE {SYSTEM.i386, SYSTEM.Privileged}
	POP EAX
	LTR AX
END SetTR;

(* Enable memory management and switch to new stack in virtual space.

	Stack layout:
			caller1 return
			caller1 EBP	<-- caller0 EBP
			[caller0 locals]
	04	caller0 return
	00	caller0 EBP	<-- EBP
			locals	<-- ESP
*)

PROCEDURE -EnableMM(pd, esp: LONGINT);
CODE {SYSTEM.i486, SYSTEM.Privileged}
	POP EBX	; esp
	POP EAX	; pd
	MOV CR3, EAX	; page directory ptr
	
	MOV ECX, 4[EBP]	; caller0 return
	MOV EDX, [EBP]	; caller0 EBP
	MOV EDX, 4[EDX]	; caller1 return
	
	MOV EAX, CR0
	OR EAX, 80000000H	; set PG bit
	MOV CR0, EAX	; enable virtual addressing (old stack no longer usable)
	JMP 0	; flush queue
	WBINVD
	
	MOV DWORD -4[EBX], 0	; not UserStackSel (cf. GetUserStack)
	MOV -8[EBX], EDX	; caller1 return on new stack
	MOV DWORD -12[EBX], 0	; caller1 EBP on new stack
	LEA EBP, -12[EBX]	; new stack top
	MOV ESP, EBP

	JMP ECX	; back to caller0 (whose locals are now inaccessible!)
END EnableMM;

(** -- Initialization -- *)

(** Initialize memory management. 
	o every processor calls this once during initialization
	o mutual exclusion with other processors must be guaranteed by the caller
	o interrupts must be off
	o segmentation and paging is enabled
	o return is on the new stack => caller must have no local variables
*)

PROCEDURE InitMemory*;
VAR id: LONGINT;
BEGIN
	EnableSegments;
		(* allocate stack *)
	id := AosBoot.ID();
	NewKernelStack(proc[id].stack);
	proc[id].esp := 0;
		(* initialize TSS *)
	AosBoot.Fill32(SYSTEM.ADR(proc[id].tss), SIZE(TSSDesc), 0);
	proc[id].tss.ESP0 := proc[id].stack.high;	(* kernel stack org *)
	proc[id].tss.ESS0 := KernelStackSel;
	proc[id].tss.IOBitmapOffset := -1;	(* no bitmap *)
		(* enable paging and switch stack *)
	SetTR(KernelTR + id*8);
	EnableMM(kernelPD, proc[id].tss.ESP0)
END InitMemory;

(** Initialize a boot page for MP booting.  Parameter physAdr returns the physical address of a low page. *)

PROCEDURE InitBootPage*(start: Startup; VAR physAdr: LONGINT);
CONST BootOfs = 800H;
VAR adr, a: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosMemory);
	NewLowPage(physAdr);
	AosLocks.Release(AosLocks.AosMemory);
	ASSERT((physAdr # NilAdr) & (physAdr >= 0) & (physAdr < M) & (physAdr MOD PS = 0));
	adr := physAdr + BootOfs;
	a := adr;	(* from SMP.Asm - generated with BinToCode.Kernel smp.bin 800H *)
	SYSTEM.PUT32(a, 0100012EBH);  INC(a, 4);  SYSTEM.PUT32(a, 000080000H);  INC(a, 4);
	SYSTEM.PUT32(a, 000000000H);  INC(a, 4);  SYSTEM.PUT32(a, 000170000H);  INC(a, 4);
	SYSTEM.PUT32(a, 000000000H);  INC(a, 4);  SYSTEM.PUT32(a, 0010F2EFAH);  INC(a, 4);
	SYSTEM.PUT32(a, 02E08081EH);  INC(a, 4);  SYSTEM.PUT32(a, 00E16010FH);  INC(a, 4);
	SYSTEM.PUT32(a, 0E0010F08H);  INC(a, 4);  SYSTEM.PUT32(a, 0010F010CH);  INC(a, 4);
	SYSTEM.PUT32(a, 0B800EBF0H);  INC(a, 4);  SYSTEM.PUT32(a, 0D08E0010H);  INC(a, 4);
	SYSTEM.PUT32(a, 0C08ED88EH);  INC(a, 4);  SYSTEM.PUT32(a, 00800BC66H);  INC(a, 4);
	SYSTEM.PUT32(a, 033660000H);  INC(a, 4);  SYSTEM.PUT32(a, 0FF2E66C0H);  INC(a, 4);
	SYSTEM.PUT32(a, 09008022EH);  INC(a, 4);
		(* these offsets are from the last two dwords in SMP.Asm *)
	SYSTEM.PUT32(adr+2, SYSTEM.VAL(LONGINT, start));	(* not a method *)
	SYSTEM.PUT32(adr+16, SYSTEM.ADR(gdt[0]));
		(* jump at start *)
	SYSTEM.PUT8(physAdr, 0EAX);	(* jmp far *)
	SYSTEM.PUT32(physAdr + 1, ASH(physAdr, 16-4) + BootOfs)	(* seg:ofs *)
END InitBootPage;

(** The BP in a MP system calls this to map the APIC physical address directly. *)

PROCEDURE InitAPICArea*(adr, size: LONGINT);
BEGIN
	ASSERT((size = PS) & (adr >= IntelAreaAdr) & (adr+size-1 < IntelAreaAdr+IntelAreaSize));
	IF ~MapDirect(adr, size, adr + UserPage) THEN HALT(99) END
END InitAPICArea;

(** Get page range (beginAdr..endAdr-1) and first and last block of static heap. *)

PROCEDURE GetStaticHeap*(VAR beginAdr, endAdr, firstBlockAdr, freeBlockAdr: LONGINT);
BEGIN
	beginAdr := LinkAdr;
	firstBlockAdr := LinkAdr+3CH;
	SYSTEM.GET(LinkAdr+EndBlockOfs, freeBlockAdr);	(* new place *)
	IF freeBlockAdr = 0 THEN SYSTEM.GET(LinkAdr+16H, freeBlockAdr) END;	(* old place *)
	ASSERT(freeBlockAdr MOD StaticBlockSize = StaticBlockSize-4);
	endAdr := heapEndAdr
END GetStaticHeap;

(** Jump from kernel to user mode.  Every processor calls this during initialization. *)

PROCEDURE JumpToUserLevel*(userEBP: LONGINT);
CODE {SYSTEM.i386}
	PUSH UserStackSel	; SS3
	PUSH userEBP[EBP]	; ESP3
	PUSHFD	; EFLAGS3
	PUSH UserCodeSel	; CS3
	CALL L1	; PUSH L1 (EIP3)
L1:
	ADD DWORD [ESP], 5	; adjust EIP3 to L2 (L2-L1 = 5)
	IRETD	; switch to level 3 and continue at following instruction
L2:
	POP EBP	; from level 3 stack (refer to AosActive.NewProcess)
	RET 8	; jump to body of first active object
END JumpToUserLevel;

BEGIN
	IF AosBoot.Trace THEN AosOut.Enter; AosOut.String("AosMemory"); AosOut.Exit END;
	NmaxUserStacks := MaxUserStacks;
	ASSERT(ASH(1, PSlog2) = PS);
	GlobalFlushTLB := NIL;	(* installed by AosProcessors *)
	InitSegments;	(* enable flat segments *)
	InitPages;	(* create page tables *)
	InitMemory	(* switch on segmentation, paging and switch stack *)
END AosMemory.

(*
Notes:
o Kernel stack overflows are not checked, and will probably cause a processor lockup or memory corruption.
o SYSTEM.LSH is used in cases where an unsigned divide is required.
o This module is hierarchically below AosHeap and should not use dynamic memory allocation (NEW).
o All processors share the same address space. 
o The bottom and top pages should be unmapped to catch NIL references.
o MapPhysical always returns a new virtual address, unless the region is directly mapped.
*)

(*
10.03.1998	pjm	First version
29.03.1998	pjm	GetUserStack->
31.03.1998	pjm	GetActiveStacks
30.04.1998	pjm	30023 HALT removed in GetActiveStacks (startup GC)
04.05.1998	pjm	EnableMM: clear top dword to avoid mistaken recognition as UserStackSel
06.05.1998	pjm	ExtendStack added, NewPage & DisposePage no longer exported
11.05.1998	pjm	Only map page in ExtendStack if not mapped already
18.08.1998	pjm	GetActiveStacks->GetUserStack
30.06.1999	pjm	Intel area added (we lose 144 of 16384 user stacks at 128K.  could do it more clever if needed.)
27.07.2000	pjm	Allow ExtendStack to create holes, making us less dependent on procedure entry code
19.09.2000	pjm	SetLocalCacheProperties added
06.12.2000	pjm	Use bitmap for free stack management
19.03.2001	pjm	New memory model
*)

(*
to do:
o handle 15MB hole
o check if works with 512K low memory
o Pentium 4MB pages for heap
o >2GB memory support
*)
