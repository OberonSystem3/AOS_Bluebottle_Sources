(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosHeap; (** AUTHOR "pjm"; PURPOSE "Heap management and garbage collector"; *)

(* This module contains lots of low-level memory manipulations, which are best read together with the memory management data structure documentation. *)

IMPORT SYSTEM, AosBoot, AosLocks, AosOut, AosMemory;

CONST
	DebugValue = 0DEADDEADH;	(* set non-0 to clear free storage to this value *)
	Trace = TRUE;	(* include trace code *)
	Stats = TRUE;	(* maintain statistical counters *)
	
	HeapMin = 50;	(* "minimum" heap size as percentage of total memory size *)
	HeapMax = 95;	(* maximum heap size as percentage of total memory size *)
	ExpandRate = 1;	(* always extend heap with at least this percentage of total memory size *)
	Threshold = 10;	(* periodic GC initiated when this percentage of total memory size bytes has "passed through" NewBlock *)
	
	MaxTries = 16;	(* max number of times to try and allocate memory, before trapping *)
	InitialHeapIncrement = 4096;
	
	BlockSize* = 32;	(* power of two, <= 32 for RegisterCandidates *)
	
	FreeLists = 9;
	MaxCandidates = 1024;
	
	MarkBit = 0;  ArrayBit = 1;  FreeBit = 2;	(* in tag *)
	SubObjBit = 3;	(* in tag or ptr => indirect tag present *)
	ProtObjBit* = 4;	(* in ptr => direct tag and ProtOfs sized header present *)
	ProtOfs* = BlockSize+16;	(* protected object offset (32n+16) (MOD 8=0, ~SubObjBit IN ProtOfs, MOD 32#0) *)
	
	ProtTypeBit* = 31;	(** flags in TypeDesc, RoundUp(log2(MaxTags)) low bits reserved for extLevel *)
	
	ModOfs* = 16;	(* moduleAdr offset in TypeDesc *)
	TypeNameOfs = 20;	(* type name offset in TypeDesc *)
	ModNameOfs = 8;	(* module name offset in ModuleDesc *)
	
	FlagBits* = {MarkBit, ArrayBit, FreeBit, SubObjBit, ProtObjBit};

	MinPtrOfs = -40000000H;	(* sentinel offset for ptrOfs *)
	
	NilVal = 0;
	
TYPE
	PtrElemRec = RECORD	(* has same type descriptor as element of ARRAY OF POINTER *)
		placeholder: PTR	(* field not used directly, but must be declared as pointer *)
	END;

	RootObject* = OBJECT	(* ref. AosLinker0 *)
		VAR placeholder: LONGINT;	(* for linking root objects during GC (used implicitly in Mark) *)
		PROCEDURE FindRoots*;	(** abstract *)
		BEGIN HALT(301) END FindRoots;
	END RootObject;
	
	Finalizer* = PROCEDURE {DELEGATE} (obj: PTR);
	
	FinalizerNode* = POINTER TO RECORD
		objWeak* [UNTRACED]: PTR;	(* weak reference to checked object *)
		markAdr: LONGINT;	(* address of type tag of object *)
		nextFin: FinalizerNode;	(* in finalization list *)
		objStrong*: PTR;	(* strong reference to object to be finalized *)
		finalizer*: Finalizer	(* finalizer, if any *)
	END;

VAR
	GC*: PROCEDURE;	(** activate the garbage collector *)
	beginAdr, endAdr: LONGINT;	(* page boundaries of heap *)
	beginBlockAdr-, endBlockAdr-: LONGINT;	(** block boundaries of heap, exported for AosInfo. *)
	initBlock: PTR;	(* anchor for init calls *)
	freeList: ARRAY FreeLists+1 OF LONGINT;	(* array of freelists *)
	lastFreeListAdr: LONGINT;
	candidates: ARRAY MaxCandidates OF LONGINT;	(* stack pointer candidates *)
	numCandidates: LONGINT;
	rootList: LONGINT;	(* list of root objects during GC *)
	newSum, gcThreshold, expandMin, heapMinKB, heapMaxKB: LONGINT;
	checkRoot: FinalizerNode;	(* list of checked objects (contains weak references to the checked objects) *)
	finalizeRoot: FinalizerNode;	(* objects scheduled for finalization (contains references to scheduled objects) *)
	traceHeap*: SET;	(* exported for testing *)
	Nmark, Nmarked, Nsweeped, Nnew, NnewBytes, Ngc, NfinalizeAlive, NfinalizeDead: LONGINT;

(*
PROCEDURE Largest(): LONGINT;
VAR i, max, ptr, size: LONGINT;
BEGIN
	i := FreeLists;  max := 0;
	WHILE (i >= 0) & (max = 0) DO
		ptr := freeList[i];
		WHILE ptr # NilVal DO
			SYSTEM.GET(ptr+4, size);	(* size *)
			IF size > max THEN max := size END;
			SYSTEM.GET(ptr+8, ptr)	(* next *)
		END;
		DEC(i)
	END;
	RETURN max
END Largest;
*)

(** Mark - Mark an object and its decendents.  Used by findRoots. *)
(* Mark is best read together with the heap data structures diagram. *)

PROCEDURE Mark*(p: PTR);
VAR t, block, tag, pTagAdr, tdTag, currElem, father, ptrOfs, field, downTag: LONGINT;  s, arrayBit: SET;
BEGIN	(* {p is RecBlk, ArrayBlk or SubObj} *)
	IF Stats THEN INC(Nmark) END;
	block := SYSTEM.VAL(LONGINT, p);
	IF (block < beginBlockAdr) OR (block >= endBlockAdr) THEN	(* UNSIGNED *)
		AosOut.String("OutPtr");  AosOut.Hex(block, 9);  AosOut.Ln;	(* remove *)
		RETURN	(* temporary (buffers?) *)
	END;
	IF ~(SubObjBit IN SYSTEM.VAL(SET, block)) THEN	(* block is not a SubObj pointer *)
		IF ~(ProtObjBit IN SYSTEM.VAL(SET, block)) THEN	(* not protected object pointer *)
			pTagAdr := block-4;
			SYSTEM.GET(pTagAdr, s)	(* tag & bits *)
(*
			;IF (SYSTEM.VAL(LONGINT, s) = block) & (SYSTEM.GET16(block+10) = -1) THEN
				AosOut.String("!P"); AosOut.Hex(block, 8); AosOut.Char(" ")
			END
*)
		ELSE	(* protected object pointer (~SubObj) *)
			pTagAdr := block-(ProtOfs+4);
			SYSTEM.GET(pTagAdr, s)	(* tag & bits *)
		END;
		IF ~(MarkBit IN s) THEN	(* not marked *)
			SYSTEM.GET(block-4, tag);
			SYSTEM.PUT(pTagAdr, s + {MarkBit});	(* mark it *)
			arrayBit := SYSTEM.VAL(SET, tag) * {ArrayBit};
			EXCL(SYSTEM.VAL(SET, tag), ArrayBit);	(* tag = ADR(recsize) or ADR(tdsize) *)
				(* now mark tdesc *)
			SYSTEM.GET(tag-4, tdTag);	(* tdTag = ADR(tdsize) & bits *)
				(* mask out MarkBit, because block may be a TypeDesc start pointer *)
			tdTag := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tdTag) - {MarkBit}) - 4;	(* tdTag = ADR(tdesctag) *)
			SYSTEM.GET(tdTag, s);  SYSTEM.PUT(tdTag, s + {MarkBit});	(* mark tdesc *)
			IF (SubObjBit IN SYSTEM.VAL(SET, tag)) & (SYSTEM.GET32(tag-8) = SYSTEM.TYPECODE(RootObject)) THEN
				SYSTEM.PUT(block, rootList);  (* link *)
				rootList := block
			END;
				(* move into element *)
			IF arrayBit # {} THEN SYSTEM.GET(block+8, currElem)	(* firstElem *)
			ELSE currElem := block
			END;
			father := NilVal;
			LOOP	(* subgraph traversal *)
				INC(tag, 4);	(* tag = ADR(ptrOfs[0]) *)
				SYSTEM.GET(tag, ptrOfs);
				ASSERT(ptrOfs MOD 4 = 0);	(* temporary sanity check (no deep copy flag) *)
				IF ptrOfs < MinPtrOfs THEN	(* end of element *)
					INC(tag, ptrOfs-MinPtrOfs);	(* tag = ADR(recsize) *)
					IF (arrayBit # {}) & (currElem # SYSTEM.GET32(block)) THEN	(* array & (currElem # lastElemToMark) *)
						INC(currElem, SYSTEM.GET32(tag))	(* skip to next element using recSize *)
					ELSE	(* end of array or record => move up in graph *)
							(* restore the original tag *)
						IF SYSTEM.VAL(SET, block) * {ProtObjBit, SubObjBit} # {ProtObjBit} THEN	(* not protected object *)
							SYSTEM.PUT(block-4, SYSTEM.VAL(SET, tag) + arrayBit + {MarkBit})
						ELSE	(* protected object *)
							ASSERT(arrayBit = {});	(* protected object can not be array element *)
							SYSTEM.PUT(block-4, tag)
						END;
						IF father = NilVal THEN EXIT END;	(* end of subgraph traversal *)
							(* restore values of father *)
						SYSTEM.GET(father-4, tag);
						arrayBit := SYSTEM.VAL(SET, tag) * {ArrayBit};
						tag := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tag) - {ArrayBit, MarkBit});
						IF arrayBit # {} THEN SYSTEM.GET(father+4, currElem)	(* currElem *)
						ELSE currElem := father
						END;
						ptrOfs := currElem + SYSTEM.GET32(tag);	(* last field of father *)
							(* pointer rotation *)
						SYSTEM.GET(ptrOfs, field);  SYSTEM.PUT(ptrOfs, block);
						block := father;  father := field
					END
				ELSE	(* next field of element *)
					INC(ptrOfs, currElem);	(* ptrOfs = ADR(field) *)
					SYSTEM.GET(ptrOfs, field);
					ASSERT(ptrOfs MOD 4 = 0);	(* temporary sanity check (no deep copy flag) *)
					IF field = NilVal THEN
						(* skip *)
					ELSIF (field < beginBlockAdr) OR (field >= endBlockAdr) THEN	(* UNSIGNED *)
						(*AosOut.String("OutPtr");  AosOut.Hex(field, 9);  AosOut.Hex(ptrOfs, 9);  AosOut.Ln*)
					ELSE
						IF ~(SubObjBit IN SYSTEM.VAL(SET, field)) THEN	(* field is not a SubObj *)
							IF ~(ProtObjBit IN SYSTEM.VAL(SET, field)) THEN	(* normal record *)
								pTagAdr := field-4;
								SYSTEM.GET(pTagAdr, s)	(* tag & bits *)
(*
								;IF (SYSTEM.VAL(LONGINT, s) = field) & (SYSTEM.GET16(field+10) = -1) THEN
									AosOut.String("!F"); AosOut.Hex(field, 8); AosOut.Char(" ")
								END
*)
							ELSE	(* protected object (~SubObj) *)
								pTagAdr := field-(ProtOfs+4);
								SYSTEM.GET(pTagAdr, s)	(* tag & bits *)
							END;
							IF ~(MarkBit IN s) THEN	(* not marked => move down in graph *)
								SYSTEM.GET(field-4, downTag);
								IF (SubObjBit IN SYSTEM.VAL(SET, downTag)) & (SYSTEM.GET32(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, downTag)-{ArrayBit})-8) = SYSTEM.TYPECODE(RootObject)) THEN
									SYSTEM.PUT(field, rootList);  (* link *)
									rootList := field
								END;
								SYSTEM.PUT(pTagAdr, s + {MarkBit});	(* mark it *)
									(* modify block tag to point to father's last traversed ptrOfs, set mark bit & leave array bit *)
								IF SYSTEM.VAL(SET, block) * {ProtObjBit, SubObjBit} # {ProtObjBit} THEN	(* not protected object *)
									SYSTEM.PUT(block-4, SYSTEM.VAL(SET, tag) + arrayBit + {MarkBit})
								ELSE	(* protected object *)
									ASSERT(arrayBit = {});	(* protected object can not be array element *)
									SYSTEM.PUT(block-4, tag)
								END;
									(* for arrays, also update the father's currElem ptr *)
								IF arrayBit # {} THEN SYSTEM.PUT(block+4, currElem) END;
									(* now mark tdesc *)
								SYSTEM.GET(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, downTag) - {ArrayBit})-4, tdTag);
									(* mask out MarkBit, because block may be a TypeDesc start pointer *)
								tdTag := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tdTag) - {MarkBit}) - 4;	(* tdTag = ADR(tdesctag) *)
								SYSTEM.GET(tdTag, s);  SYSTEM.PUT(tdTag, s + {MarkBit});	(* mark tdesc *)
									(* move into element *)
								arrayBit := SYSTEM.VAL(SET, downTag) * {ArrayBit};
								IF arrayBit # {} THEN SYSTEM.GET(field+8, currElem)	(* firstElem *)
								ELSE currElem := field
								END;
									(* pointer rotation *)
								SYSTEM.PUT(ptrOfs, father);  father := block;  block := field;
								tag := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, downTag) - arrayBit)	(* tag = new block tag *)
							ELSE	(* marked - skip *)
							END
						ELSE	(* field is a SubObj *)
							SYSTEM.GET(field-4, downTag);	(* indirect tag *)
							t := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, downTag) - {ArrayBit}) - 4;
								(* remove array bit because of array SubObjs in module block *)
							SYSTEM.GET(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, downTag) - {ArrayBit}) - 4, downTag);	(* indirect tag *)
								(* remove mark bit because it may already be marked *)
							downTag := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, downTag) - {MarkBit}) - 4;	(* ADR(tag) *)
							ASSERT(t = downTag);	(* temporary sanity check, always true => can remove indirection here *)
							SYSTEM.GET(downTag, s);  SYSTEM.PUT(downTag, s + {MarkBit})	(* mark it *)
						END
					END
				END
			END	(* LOOP *)
		ELSE	(* marked - skip *)
		END
	ELSE	(* p is a SubObj *)
		SYSTEM.GET(block-4, tag);	(* indirect tag *)
		t := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tag) - {ArrayBit}) - 4;
			(* remove array bit because of array SubObjs in module block *)
		SYSTEM.GET(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tag) - {ArrayBit}) - 4, tag);	(* indirect tag *)
			(* remove mark bit because it may already be marked *)
		tag := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tag) - {MarkBit}) - 4;	(* ADR(tag) *)
		ASSERT(t = tag);	(* temporary sanity check, always true => can remove indirection here *)
		SYSTEM.GET(tag, s);
		IF (SubObjBit IN s) & (SYSTEM.GET32(SYSTEM.VAL(LONGINT, s - {ArrayBit,FreeBit,MarkBit})-8) =  SYSTEM.TYPECODE(RootObject)) THEN
			HALT(99)	(* untraced rootObj! *)
		END;
		SYSTEM.PUT(tag, s + {MarkBit})	(* mark it *)
	END
END Mark;

(** WriteType - Write a type name (for tracing only). *)

PROCEDURE WriteType*(t: LONGINT);	(* t is tdesc *)
VAR m, i: LONGINT;  ch: CHAR;  name: ARRAY 32 OF CHAR;
BEGIN
	SYSTEM.GET(t-4, t);
	SYSTEM.GET(t+ModOfs, m);	(* m is only a hint *)
	IF m # 0 THEN	(* could be a type without module, e.g. a Java class *)
		i := 0;  SYSTEM.GET(m+ModNameOfs+i, ch);
		WHILE (ch >= "0") & (ch <= "z") & (i # 32) DO
			AosOut.Char(ch);
			INC(i);  SYSTEM.GET(m+ModNameOfs+i, ch)
		END
	ELSE
		AosOut.String("NIL")
	END;
	AosOut.Char(".");
	SYSTEM.MOVE(t+TypeNameOfs, SYSTEM.ADR(name[0]), 32);
	IF name[0] = 0X THEN AosOut.String("-")
	ELSE AosOut.String(name)
	END
END WriteType;

(* Sweep phase. *)

PROCEDURE Sweep;
VAR p, tag, size, t, i, lastP, lastSize, live, dead: LONGINT;  lastA: ARRAY FreeLists+1 OF LONGINT;
BEGIN
	i := 0;
	WHILE i <= FreeLists DO
		freeList[i] := NilVal;  lastA[i] := SYSTEM.ADR(freeList[i]);  INC(i)
	END;
	p := beginBlockAdr;  lastSize := 0;  live := 0;  dead := 0;
	WHILE p # endBlockAdr DO
		SYSTEM.GET(p, tag);
		SYSTEM.GET(tag - tag MOD 8, size);	(* record size, excluding tag *)
		IF ArrayBit IN SYSTEM.VAL(SET, tag) THEN
			SYSTEM.GET(p+4, t);	(* lastElemToMark *)
			size := t + size - p	(* size of array, including tag *)
		ELSE
			INC(size, 4)	(* include tag *)
		END;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));	(* round up *)
		IF MarkBit IN SYSTEM.VAL(SET, tag) THEN	(* don't collect *)
			IF Stats THEN INC(Nmarked) END;
			SYSTEM.PUT(p, SYSTEM.VAL(SET, tag) - {MarkBit});	(* unmark *)
			IF lastSize > 0 THEN	(* enter last free block in free list *)
				i := lastSize DIV BlockSize;
				IF i > FreeLists THEN i := FreeLists END;
					(* freeblk *)
				SYSTEM.PUT(lastP, lastP + (4 + ASH(1, FreeBit)));	(* tag *)
				SYSTEM.PUT(lastP+4, lastSize-4);	(* size *)
				SYSTEM.PUT(lastP+8, NIL);	(* next *)
				SYSTEM.PUT(lastA[i], lastP);
				lastA[i] := lastP+8;	(* ADR(next) *)
				lastSize := 0
			END;
			INC(live)
		ELSE	(* collect *)
			IF Stats THEN INC(Nsweeped) END;
				(* append to free block *)
			IF lastSize = 0 THEN lastP := p END;
			INC(lastSize, size);
				(* tracing *)
			IF Trace & (traceHeap * {3..5, 8..9, 11} # {}) THEN
				INC(dead);
				IF ArrayBit IN SYSTEM.VAL(SET, tag) THEN	(* array *)
					IF 4 IN traceHeap THEN
						AosOut.String("[DA");  AosOut.Hex(p+4, 9);
						SYSTEM.GET(p+16, t);	(* dim0 *)
						AosOut.Char(" ");  AosOut.Int(t, 1);  AosOut.Char(" ");
						WriteType(tag - tag MOD 8);  AosOut.Char("]")
					END
				ELSIF tag - tag MOD 8 = p+4 THEN	(* sysblk or freeblk or protblk *)
					IF FreeBit IN SYSTEM.VAL(SET, tag) THEN	(* freeblk *)
						IF 8 IN traceHeap THEN
							AosOut.String("[FB");  AosOut.Hex(p+4, 9);
							SYSTEM.GET(p+4, t);	(* size *)
							AosOut.Char(" ");  AosOut.Int(t, 1);  AosOut.Char("]")
						END
					ELSE	(* sysblk or protblk *)
						SYSTEM.GET(p+(4+20), t);	(* tag or awaitingCond.head *)
						IF t = p+4 THEN	(* sysblk *)
							IF 5 IN traceHeap THEN
								SYSTEM.GET(p+4, t);	(* size *)
								AosOut.String("[DS");  AosOut.Hex(p+(4+24), 9);  AosOut.Char(" ");  AosOut.Int(t, 1);  AosOut.Char("]")
							END
						ELSE	(* protblk *)
							IF 9 IN traceHeap THEN
								SYSTEM.GET(p+(4+44), t);	(* tag *)
								AosOut.String("[DP");  AosOut.Hex(p+(4+48), 9);  AosOut.Char(" ");  WriteType(t);  AosOut.Char("]")
							END
						END
					END
				ELSE	(* recblk *)
					IF 3 IN traceHeap THEN
						AosOut.String("[DR");  AosOut.Hex(p+4, 9);  AosOut.Char(" ");  WriteType(tag);  AosOut.Char("]")
					END
				END
			END
		END;
		INC(p, size)
	END;
	IF lastSize > 0 THEN	(* enter last free block in free list *)
		i := lastSize DIV BlockSize;
		IF i > FreeLists THEN i := FreeLists END;
			(* freeblk *)
		SYSTEM.PUT(lastP, lastP + (4 + ASH(1, FreeBit)));	(* tag *)
		SYSTEM.PUT(lastP+4, lastSize-4);	(* size *)
		SYSTEM.PUT(lastP+8, NIL);	(* next *)
		SYSTEM.PUT(lastA[i], lastP)
	END;
	IF Trace & (11 IN traceHeap) THEN
		AosOut.String("[");  AosOut.Int(live, 1);  AosOut.String(" live, ");
		AosOut.Int(dead, 1);  AosOut.String(" dead, ");
		AosOut.Int(live+dead, 1);  AosOut.String(" total]")
	END
END Sweep;

(* Clear free blocks for debugging purposes. *)

PROCEDURE DebugClear;
VAR i, size, ptr: LONGINT;
BEGIN
	IF DebugValue # 0 THEN
		i := 0;
		WHILE i <= FreeLists DO
			ptr := freeList[i];
			WHILE ptr # NilVal DO
				IF SYSTEM.GET32(ptr+12) # DebugValue THEN
					SYSTEM.GET(ptr+4, size);	(* size of free block, excluding tag *)
					AosBoot.Fill32(ptr+12, size-8, DebugValue)	(* content of free block *)
				ELSE
					(* assume block is already cleared, to save time *)
				END;
				SYSTEM.GET(ptr+8, ptr)	(* next *)
			END;
			INC(i)
		END
	END
END DebugClear;

(* CheckCandidates - Check which candidates could be pointers, and mark them. *)

PROCEDURE CheckCandidates;
VAR i, j, h, p, block, t, size: LONGINT;
BEGIN	(* {numCandidates > 0} *)
		(* first sort them in increasing order using shellsort *)
	h := 1;  REPEAT h := h*3 + 1 UNTIL h > numCandidates;
	REPEAT
		h := h DIV 3;  i := h;
		WHILE i < numCandidates DO
			p := candidates[i];  j := i;
			WHILE (j >= h) & (candidates[j-h] > p) DO
				candidates[j] := candidates[j-h];  j := j-h;
			END;
			candidates[j] := p;  INC(i)
		END
	UNTIL h = 1;
		(* sweep phase *)
	block := beginBlockAdr;  i := 0;
	p := candidates[i];	(* p is candidate, with lower 2 bits signalling candidate type *)
	LOOP
		IF p <= block + (4 + 3) THEN	(* next candidate *)
			IF p - p MOD 4 = block + 4 THEN	(* candidate passed *)
				CASE p MOD 4 OF
					0:	(* type 0 - RecBlk *)
						Mark(SYSTEM.VAL(PTR, p))
					|2:	(* type 2 - ProtRecBlk *)
						Mark(SYSTEM.VAL(PTR, p + (ProtOfs - 2)))
					|3:	(* type 3 - SysBlk *)
						Mark(SYSTEM.VAL(PTR, p + (24-3)))
				END
			ELSE (* candidate failed, skip *)
			END;
			INC(i);
			IF i = numCandidates THEN EXIT END;
			p := candidates[i]
		ELSE	(* next block *)
			SYSTEM.GET(block, t);	(* tag *)
			SYSTEM.GET(t - t MOD 8, size);	(* record size, excluding tag *)
			IF ArrayBit IN SYSTEM.VAL(SET, t) THEN
				SYSTEM.GET(block+4, t);	(* lastElemToMark *)
				size := t + size - block	(* size of array, including tag *)
			ELSE
				INC(size, 4)	(* include tag *)
			END;
				(* round up, and step to next block  *)
			INC(block, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1)));
			IF block = endBlockAdr THEN EXIT END
		END
	END;
	numCandidates := 0
END CheckCandidates;

(** RegisterCandidates - Register a block of pointer candidates.  {(adr,size) MOD 4 = 0} *)

PROCEDURE RegisterCandidates*(adr, size: LONGINT);
VAR end, p, tag, tag0: LONGINT; s: SET;
BEGIN
	(* current processor must hold AosHeap lock *)
	end := adr + size;
	WHILE adr # end DO
		SYSTEM.GET(adr, p);
		IF (p > beginBlockAdr) & (p < endBlockAdr) THEN
			CASE p MOD BlockSize OF
				0:	(* RecBlk or ArrBlk candidate *)
					SYSTEM.GET(p-4, s);
					IF s * {MarkBit, FreeBit, SubObjBit} = {SubObjBit} THEN
						candidates[numCandidates] := p;	(* 00000 - type 0 *)
						INC(numCandidates);
						IF numCandidates = LEN(candidates) THEN CheckCandidates END
					END
				|16:	(* ProtRecBlk candidate *)
					SYSTEM.GET(p-4, s);
					IF s * {MarkBit, ArrayBit, FreeBit, SubObjBit} = {SubObjBit} THEN
						SYSTEM.GET(p-(ProtOfs+4), tag);
						IF tag = p-ProtOfs THEN
							candidates[numCandidates] := p - ProtOfs + 2;	(* 00010 - type 2 *)
							INC(numCandidates);
							IF numCandidates = LEN(candidates) THEN CheckCandidates END
						END
					END
				|24:	(* SysBlk candidate *)
					SYSTEM.GET(p-4, tag);
					IF (tag MOD BlockSize = 0) & (tag > beginBlockAdr) & (tag < endBlockAdr) THEN
						SYSTEM.GET(tag-4, tag0);
						IF tag0 = tag THEN
							IF tag0+24 = p THEN
								candidates[numCandidates] := p - 24 + 3;	(* 00011 - type 3 *)
								INC(numCandidates);
								IF numCandidates = LEN(candidates) THEN CheckCandidates END
							END
						END
					END
				ELSE (* skip - all other live heap block types (SubObj, TypeDesc) must be rooted  *)
			END	(* CASE *)
		END;
		INC(adr, 4)
	END
END RegisterCandidates;

(* Check reachability of finalized objects. *)

PROCEDURE CheckFinalizedObjects;
VAR n, p, t: FinalizerNode;
BEGIN
	n := checkRoot;
	WHILE n # NIL DO	(* move unmarked checked objects to finalize list *)
		IF ~(MarkBit IN SYSTEM.VAL(SET, SYSTEM.GET32(n.markAdr))) THEN
			IF n = checkRoot THEN checkRoot := n.nextFin ELSE p.nextFin := n.nextFin END;
			n.objStrong := n.objWeak;	(* anchor the object for finalization *)
			t := n.nextFin; n.nextFin := finalizeRoot; finalizeRoot := n; n := t;
			IF Stats THEN DEC(NfinalizeAlive); INC(NfinalizeDead) END
		ELSE
			p := n; n := n.nextFin
		END
	END;
		(* now trace the weak references to keep finalized objects alive during this collection *)
	n := finalizeRoot;
	WHILE n # NIL DO
		Mark(n.objStrong); n := n.nextFin
	END
END CheckFinalizedObjects;

(** Return the next scheduled finalizer or NIL if none available.  Called by finalizer object in AosKernel. *)

PROCEDURE GetFinalizer*(): FinalizerNode;
VAR n: FinalizerNode;
BEGIN
	n := NIL;
	IF finalizeRoot # NIL THEN
		AosLocks.Acquire(AosLocks.AosHeap);
		n := finalizeRoot;	(* take one finalizer *)
		IF n # NIL THEN
			finalizeRoot := n.nextFin; (* to do: n.nextFin := NIL *);
			IF Stats THEN DEC(NfinalizeDead) END;
			IF Trace & (10 IN traceHeap) THEN
				AosOut.Enter; AosOut.String("Finalize ");
				WriteType(SYSTEM.GET32(SYSTEM.VAL(LONGINT, n.objWeak)-4));
				AosOut.Hex(SYSTEM.VAL(LONGINT, n.objWeak), 9); AosOut.Exit
			END
		END;
		AosLocks.Release(AosLocks.AosHeap);
	END;
	RETURN n
END GetFinalizer;

(** Check finalizers registered in the specified module, which is about to be freed or shut down.  Remove all finalizer procedures in this module from the finalizer lists so they won't be called any more. *)

PROCEDURE CleanupModuleFinalizers*(codeAdr, codeLen: LONGINT; name: ARRAY OF CHAR);
VAR n, p, t: FinalizerNode; codeEnd: LONGINT; N1, N2: LONGINT;
BEGIN
	codeEnd := codeAdr + codeLen; N1 := 0; N2 := 0;
	AosLocks.Acquire(AosLocks.AosHeap);
	n := checkRoot;
	WHILE n # NIL DO	(* iterate over checked list *)
			(* to do: unsigned! *)
		t := n; n := n.nextFin;
		IF (codeAdr <= SYSTEM.VAL(LONGINT, t.finalizer)) & (SYSTEM.VAL(LONGINT, t.finalizer) <= codeEnd) THEN
			IF t = checkRoot THEN checkRoot := t.nextFin ELSE p.nextFin := t.nextFin END;	(* remove from list *)
			IF Stats THEN DEC(NfinalizeAlive) END;
			IF FALSE (* call *) THEN	(* finalize the object *)
				t.objStrong := t.objWeak;	(* anchor the object for finalization *)
				t.nextFin := finalizeRoot; finalizeRoot := t;
				IF Stats THEN INC(NfinalizeDead) END
			END;
			INC(N1)
		ELSE
			p := t
		END
	END;
	IF TRUE (* ~call*) THEN	(* also remove finalizers from list, so they won't be called *)
		n := finalizeRoot;
		WHILE n # NIL DO	(* iterate over finalized list *)
				(* to do: unsigned! *)
			t := n; n := n.nextFin;
			IF (codeAdr <= SYSTEM.VAL(LONGINT, t.finalizer)) & (SYSTEM.VAL(LONGINT, t.finalizer) <= codeEnd) THEN
				IF t = finalizeRoot THEN finalizeRoot := t.nextFin ELSE p.nextFin := t.nextFin END;	(* remove from list *)
				IF Stats THEN DEC(NfinalizeDead) END;
				INC(N2)
			ELSE
				p := t
			END
		END
	END;
	AosLocks.Release(AosLocks.AosHeap);
	IF (N1 # 0) OR (N2 # 0) THEN
		AosOut.Enter; AosOut.String(name); AosOut.Char(" ");
		AosOut.Int(N1, 1); AosOut.String(" discarded finalizers, ");
		AosOut.Int(N2, 1); AosOut.String(" pending finalizers"); AosOut.Exit
	END
END CleanupModuleFinalizers;

PROCEDURE ShowInt(i: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	IF Trace THEN
		AosOut.Char(" "); AosOut.String(msg); AosOut.Char("="); AosOut.Int(i, 1)
	END
END ShowInt;

PROCEDURE ShowTimeDiff(time1, time2: HUGEINT; msg: ARRAY OF CHAR);
BEGIN
	IF Trace THEN
		IF AosBoot.HIntToLInt(AosBoot.mhz) # 0 THEN
			time1 := AosBoot.DivH(AosBoot.SubH(time2, time1), AosBoot.mhz)
		ELSE
			time1 := AosBoot.SubH(time2, time1)
		END;
		ShowInt(AosBoot.HIntToLInt(time1), msg)
	END
END ShowTimeDiff;

(** Garbage collector.  Caller MUST run in single-processor mode.  Lock level AosHeap. *)

PROCEDURE CollectGarbage*(root: PTR);
VAR
	tagAdr, i: LONGINT; tag: SET; obj: RootObject;
	stack: ARRAY AosBoot.MaxCPU OF AosMemory.Stack;
	time1, time2, time3, time4, time5, time6: HUGEINT; first: BOOLEAN;
BEGIN
	AosLocks.Acquire(AosLocks.AosHeap);	(* protect from interrupts *)
	IF Stats THEN INC(Ngc) END;
	IF Trace & (traceHeap - {0,1,2,6} # {}) THEN
		AosOut.String("[P"); AosOut.Int(AosBoot.ID(), 1);
		AosOut.Char("@"); AosOut.Int(AosBoot.HIntToLInt(AosBoot.mhz), 1); AosOut.String("MHz ");
		AosOut.String(" GC");
		time1 := AosBoot.GetTimer()
	END;
	numCandidates := 0; rootList := NilVal;
	IF Stats THEN Nmark := 0; Nmarked := 0; Nsweeped := 0 END;
	Mark(root);
	IF Trace THEN time2 := AosBoot.GetTimer(); first := TRUE END;
		(* check kernel stacks *)
	AosMemory.GetKernelStacks(stack);
	FOR i := 0 TO AosBoot.MaxCPU-1 DO
		RegisterCandidates(stack[i].adr, stack[i].high - stack[i].adr)
	END;
	REPEAT
		REPEAT
			IF rootList # NilVal THEN	(* check root objects *)
				REPEAT
						(* get head object *)
					obj := SYSTEM.VAL(RootObject, rootList);
					tagAdr := rootList-4;
					SYSTEM.GET(rootList, rootList);	(* link to next *)
						(* find roots in object *)
					SYSTEM.GET(tagAdr, tag);	(* save *)
					ASSERT(tag * {ArrayBit, FreeBit, SubObjBit} = {SubObjBit});	(* sanity check *)
					SYSTEM.PUT(tagAdr, tag - {MarkBit});	(* allow type guards & method calls (only as long as not marked again) *)
					obj.FindRoots;	(* will call Mark & RegisterCandidates *)
					SYSTEM.PUT(tagAdr, tag)	(* restore *)
				UNTIL rootList = NilVal
			END;
			IF numCandidates # 0 THEN CheckCandidates END
		UNTIL (numCandidates = 0) & (rootList = NilVal);
		IF Trace THEN
			IF first THEN first := FALSE; time3 := AosBoot.GetTimer() END	(* total time for finalized objects, with other roots *)
		END;
		CheckFinalizedObjects
	UNTIL rootList = NilVal;
	(*IF rootList # NilVal THEN
		SYSTEM.GET(rootList-4, tagAdr);
		AosOut.String("rootList # NIL "); WriteType(tagAdr); AosOut.Ln
	END;*)
	IF Trace THEN time4 := AosBoot.GetTimer() END;
	Sweep;
	IF Trace THEN time5 := AosBoot.GetTimer() END;
	IF DebugValue # 0 THEN DebugClear END;
	IF Trace & (traceHeap - {0,1,2,6} # {}) THEN
		time6 := AosBoot.GetTimer();
		ShowTimeDiff(time1, time6, "tot");
		ShowTimeDiff(time1, time2, "mod");
		ShowTimeDiff(time2, time3, "obj");
		ShowTimeDiff(time3, time4, "fin");
		ShowTimeDiff(time4, time5, "swp");
		ShowTimeDiff(time5, time6, "clr");
		IF Stats THEN
			ShowInt(Nmark, "rts");
			ShowInt(Nmarked, "rch");
			ShowInt(Nsweeped, "fre");
			ShowInt(NfinalizeAlive, "fina");
			ShowInt(NfinalizeDead, "find")
		END;
		IF traceHeap * {3..5, 8..9, 11} # {} THEN AosOut.String(" (with tracing)") END;
		AosOut.String(" CG]");  AosOut.Ln
	END;
	AosLocks.Release(AosLocks.AosHeap)
END CollectGarbage;

(* Try to expand the heap by at least "size" bytes. *)

PROCEDURE ExpandHeap(size: LONGINT);
VAR p: LONGINT; s: SET;
BEGIN
	IF size < expandMin THEN size := expandMin END;
	INC(endAdr, size);
	AosMemory.SetHeapEndAdr(endAdr);	(* in/out parameter *)
	IF endBlockAdr+4 # endAdr THEN	(* heap has grown, init free block *)
		p := endBlockAdr+4; s := SYSTEM.VAL(SET, p) + {FreeBit};
		endBlockAdr := endAdr-4;
		SYSTEM.PUT(p-4, s);	(* tag *)
		SYSTEM.PUT(p, endBlockAdr-p);	(* size *)
		SYSTEM.PUT(p+4, NIL)	(* next *)
	END
END ExpandHeap;

(* Policy decision for heap expansion.  NewBlock for the same block has failed try times. *)

PROCEDURE ExpandNow(try: LONGINT): BOOLEAN;
VAR size: LONGINT;
BEGIN
	size := SYSTEM.LSH(endAdr - beginAdr, -10);	(* heap size in KB *)
	RETURN (~ODD(try) OR (size < heapMinKB)) & (size < heapMaxKB)
END ExpandNow;

(* NewBlock - Allocate a heap block.  {(size MOD BlockSize = 0) & (ret MOD BlockSize = BlockSize-4)}.  Caller must hold Heap lock. *)

PROCEDURE NewBlock(size: LONGINT): LONGINT;
VAR idx, rest, free, ptr, restPtr, try: LONGINT;
BEGIN
	INC(newSum, size);
	IF newSum > gcThreshold THEN	(* call GC every so often to avoid fragmentation *)
		newSum := 0;
		AosLocks.Release(AosLocks.AosHeap);	(* give up control *)
		GC;	(* try to free memory (other processes may also steal memory now) *)
		AosLocks.Acquire(AosLocks.AosHeap)
	END;
	IF Stats THEN INC(Nnew); INC(NnewBytes, size) END;
	try := 1;
	LOOP
		idx := size DIV BlockSize;	(* idx negative if size negative *)
		IF idx > FreeLists THEN idx := FreeLists END;
		free := SYSTEM.ADR(freeList[idx])-4;	(* before start freelist *)
		REPEAT
			INC(free, 4); SYSTEM.GET(free, ptr)
		UNTIL (ptr # NilVal) OR (free = lastFreeListAdr);
		IF free = lastFreeListAdr THEN	(* search last list, which has variable-sized entries *)
			LOOP	(* find big enough block *)
				IF ptr = NilVal THEN EXIT END;	(* end of last list *)
				SYSTEM.GET(ptr + 4, rest);	(* free block size *)
				IF rest + 4 >= size THEN EXIT END;	(* block found *)
				free := ptr + 8;	(* prev link *)
				SYSTEM.GET(free, ptr)	(* next free block *)
			END
		END;
		IF ptr # NilVal THEN	(* found a block, remove and split it *)
			SYSTEM.GET(ptr + 8, rest);	(* next free block *)
			SYSTEM.PUT(free, rest);	(* update free list head or previous node in list *)
			SYSTEM.GET(ptr + 4, rest);	(* size *)
			rest := rest + 4 - size;	(* size of remainder *)
			IF rest > 0 THEN	(* add free block *)
				idx := rest DIV BlockSize;
				IF idx > FreeLists THEN idx := FreeLists END;
				restPtr := ptr + size;
				SYSTEM.PUT(restPtr, restPtr + (4 + ASH(1, FreeBit)));	(* tag *)
				SYSTEM.PUT(restPtr + 4, rest - 4);	(* size *)
				SYSTEM.PUT(restPtr + 8, freeList[idx]);	(* next *)
				freeList[idx] := restPtr
			END;
			RETURN ptr
		END;
			(* failed *)
		(*AosOut.String("NBT "); AosOut.Int(try, 1); AosOut.Char(" "); AosOut.Int(size, 1); AosOut.Ln;*)
		IF try = MaxTries THEN SYSTEM.HALT(14) END;	(* out of memory *)
		IF ExpandNow(try) THEN ExpandHeap(size) END;	(* try to extend the heap *)
		AosLocks.Release(AosLocks.AosHeap);	(* give up control *)
		GC;	(* try to free memory (other processes may also steal memory now) *)
		AosLocks.Acquire(AosLocks.AosHeap);
		INC(try)
	END
END NewBlock;

(** NewSys - Implementation of SYSTEM.NEW. *)

PROCEDURE NewSys*(VAR p: PTR;  size: LONGINT);
VAR ptr: LONGINT;
BEGIN
	IF Trace & (2 IN traceHeap) THEN
		AosOut.Enter;  AosOut.String("NS ");  AosOut.Int(size, 1);  AosOut.Exit
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
		(* add space for tag & fake type descriptor and round up to BlockSize *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (4 + 24 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	ptr := NewBlock(size);
	SYSTEM.PUT(ptr, ptr+4);	(* tag *)
	SYSTEM.PUT(ptr+4, size-4);
	SYSTEM.PUT(ptr+8, SYSTEM.VAL(LONGINT, MinPtrOfs-4));
	SYSTEM.PUT(ptr+12, NIL);	(* flag = 0 for AosInfo.Objects *)
	SYSTEM.PUT(ptr+16, NIL);	(* not used *)
	SYSTEM.PUT(ptr+20, {});	(* bit 1 must be 0 to distinguish from array SysBlk *)
	SYSTEM.PUT(ptr+24, ptr+4);	(* SysBlk tag *)
	p := SYSTEM.VAL(PTR, ptr+28);
	AosLocks.Release(AosLocks.AosHeap);
		(* clear can be done outside lock because SysBlks are not traced *)
	AosBoot.Fill32(SYSTEM.VAL(LONGINT, p), size-28, 0)	(* clear everything except header *)
END NewSys;

PROCEDURE -CallerEIP(): LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 4[EBP]
END CallerEIP;

(** NewRec - Implementation of NEW with a record. *)

PROCEDURE NewRec*(VAR p: PTR;  tag: LONGINT);
VAR size, ptr: LONGINT;
BEGIN
	IF tag = 0 THEN
		tag := SYSTEM.TYPECODE(PtrElemRec);
			(* should not occur any more after compiler update 03.07.01, but old obj files... *)
		AosOut.String("NewRec tag=NIL"); AosOut.Hex(CallerEIP(), 9); AosOut.Ln
	END;
	SYSTEM.GET(tag-4, ptr);	(* will be replaced by direct compiler call of NewProtObj *)
	SYSTEM.GET(ptr+12, ptr);	(* flags *)
	IF ODD(ASH(ptr, -ProtTypeBit)) THEN	(* protected record *)
		NewProtRec(p, tag);
		RETURN
	END;
	SYSTEM.GET(tag, size);
		(* add space for tag and round up to BlockSize *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (4 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	IF Trace & (0 IN traceHeap) THEN
		AosOut.Enter;  AosOut.String("NR ");  WriteType(tag);  AosOut.Exit
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
	ptr := NewBlock(size);
	SYSTEM.PUT(ptr, tag);	(* set the block tag *)
	p := SYSTEM.VAL(PTR, ptr+4);	(* anchor the block *)
		(* clear must be done inside lock to ensure all traced pointer fields are initialized to NIL *)
	AosBoot.Fill32(SYSTEM.VAL(LONGINT, p), size-4, 0);	(* clear everything except tag *)
	AosLocks.Release(AosLocks.AosHeap)
END NewRec;

(** NewProtRec - Implementation of NEW with a protected record. *)

PROCEDURE NewProtRec*(VAR p: PTR;  tag: LONGINT);
VAR size, ptr: LONGINT;
BEGIN
	SYSTEM.GET(tag, size);
		(* add space for tag and header and round up to BlockSize *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (4 + ProtOfs + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	IF Trace & (0 IN traceHeap) THEN
		AosOut.Enter;  AosOut.String("NP ");  WriteType(tag);  AosOut.Exit
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
	ptr := NewBlock(size)+4;
	SYSTEM.PUT(ptr-4, ptr);	(* set the main tag *)
	SYSTEM.PUT(ptr, size-4);	(* size *)
	SYSTEM.PUT(ptr+4, SYSTEM.VAL(LONGINT, MinPtrOfs-4));
	AosBoot.Fill32(ptr+8, ProtOfs-12, 0);	(* clear header *)
	SYSTEM.PUT16(ptr+10, -1);	(* flag = -1 *)
	SYSTEM.PUT(ptr+(ProtOfs-4), tag);	(* set the tag *)
	p := SYSTEM.VAL(PTR, ptr+ProtOfs);
		(* clear must be done inside lock to ensure all traced pointer fields are initialized to NIL *)
	AosBoot.Fill32(SYSTEM.VAL(LONGINT, p), size-(4+ProtOfs), 0);	(* clear everything except tag & header *)
	AosLocks.Release(AosLocks.AosHeap)
END NewProtRec;

(** NewArr - Implementation of NEW with an array containing pointers. *)

PROCEDURE NewArr*(VAR p: PTR;  elemTag, numElems, numDims: LONGINT);
VAR ptr, size, firstElem, elemSize, arrSize, vectSize, ptrOfs: LONGINT;
BEGIN
	IF elemTag = 0 THEN
		elemTag := SYSTEM.TYPECODE(PtrElemRec);
			(* should not occur any more after compiler update 03.07.01, but old obj files... *)
		AosOut.String("NewArr tag=NIL"); AosOut.Hex(CallerEIP(), 9); AosOut.Ln
	END;
	SYSTEM.GET(elemTag, elemSize);
	arrSize := numElems * elemSize;
	IF arrSize = 0 THEN
		IF Trace & (1 IN traceHeap) THEN
			AosOut.Enter;  AosOut.String("NA ");  AosOut.Int(numElems, 1);  AosOut.Char(" ");
			AosOut.Int(numDims, 1);  AosOut.String("->");  AosOut.Exit
		END;
		NewSys(p, numDims * 4 + 12)
	ELSE
		ASSERT(arrSize >= 0);
		vectSize := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, 4 * numDims) + SYSTEM.VAL(SET, 4));	(* => firstElem MOD 8 = 0 *)
		SYSTEM.GET(elemTag+4, ptrOfs);
		IF ptrOfs = MinPtrOfs-4 THEN	(* no pointers in element type *)
			IF Trace & (1 IN traceHeap) THEN
				AosOut.Enter;  AosOut.String("NA ");  AosOut.Int(numElems, 1);  AosOut.Char(" ");
				AosOut.Int(numDims, 1);  AosOut.String("->");  AosOut.Exit
			END;
			size := arrSize + vectSize + 12;
			NewSys(p, size);
			ptr := SYSTEM.VAL(LONGINT, p);
				(* no need to hold Heap lock here, because SysBlk already allocated *)
			SYSTEM.PUT(ptr, SYSTEM.VAL(SET, size + 3) - SYSTEM.VAL(SET, 3));
			SYSTEM.PUT(ptr-8, {ArrayBit});	(* distinguish from normal SysBlk *)
		ELSE	(* allocate a real ArrayBlk *)
			size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, arrSize + vectSize + (16 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
			IF Trace & (1 IN traceHeap) THEN
				AosOut.Enter;  AosOut.String("NA ");  WriteType(elemTag);  AosOut.Char(" ");
				AosOut.Int(numElems, 1);  AosOut.Char(" ");
				AosOut.Int(numDims, 1);  AosOut.Exit
			END;
			AosLocks.Acquire(AosLocks.AosHeap);
			ptr := NewBlock(size);
			firstElem := ptr + 16 + vectSize;
			SYSTEM.PUT(ptr, SYSTEM.VAL(SET, elemTag) + {ArrayBit});	(* tag *)
			SYSTEM.PUT(ptr+4, firstElem + arrSize - elemSize);	(* lastElemToMark *)
			SYSTEM.PUT(ptr+8, NIL);	(* reserved for Mark *)
			SYSTEM.PUT(ptr+12, firstElem);	(* firstElem *)
			p := SYSTEM.VAL(PTR, ptr+4);
			(* clear must be done inside lock to ensure all traced pointer fields are initialized to NIL *)
			AosBoot.Fill32(ptr+16, size-16, 0);
			(* ptr+16..ptr+16 + vectSize-1 initialized by compiler-generated code *)
			AosLocks.Release(AosLocks.AosHeap)
		END
	END
END NewArr;

(** NewType - Allocate a new type descriptor.  Returns pointer to "start" of type desc (AosModules.TypeDesc) *)

PROCEDURE NewType*(VAR p: PTR; recSize, numPtrs, numSlots: LONGINT; name: ARRAY OF CHAR; mod: PTR; flags: SET);
VAR ptr, rootOfs, tdSize, size, i, dst: LONGINT;  flag: INTEGER;  ch: CHAR;
BEGIN
	IF Trace & (6 IN traceHeap) THEN
		AosOut.Enter;  AosOut.String("NT ");  AosOut.Int(recSize, 1);  AosOut.Char(" ");
		AosOut.String(name);  AosOut.Exit
	END;
	IF ProtTypeBit IN flags THEN INC(numPtrs, 5) END;	(* hidden pointers for protected object *)
	AosLocks.Acquire(AosLocks.AosHeap);
	rootOfs := 4*(4+1+numSlots+1) + 32;	(* all fields in TDesc up to recSize, excluding tag *)
	INC(rootOfs, (-rootOfs+8) MOD 16);	(* align as SubObj *)
	tdSize := rootOfs + 4*(1+numPtrs+1);	(* recSize, ptrs & sentinel *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tdSize + (4 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	ptr := NewBlock(size)+4;
	SYSTEM.PUT(ptr-4, ptr);	(* tag *)
	AosBoot.Fill32(ptr+16, size-(4+16), 0);	(* clear everything except first 4 fields & tag *)
	SYSTEM.PUT(ptr, tdSize);	(* tdSize *)
	SYSTEM.PUT(ptr+4, SYSTEM.VAL(LONGINT, MinPtrOfs-4));	(* sentinel *)
	SYSTEM.PUT(ptr+8, ptr + rootOfs);	(* self *)
	SYSTEM.GET(ptr+10, flag); ASSERT(flag # -1);	(* protected object "flag" for AosInfo.Objects *)
	SYSTEM.PUT(ptr+12, flags);
	SYSTEM.PUT(ptr+16, mod);	(* module hint only, because not traced *)
	i := 0; dst := ptr+20;	(* name *)
	REPEAT ch := name[i];  SYSTEM.PUT(dst, ch);  INC(dst);  INC(i) UNTIL (ch = 0X) OR (i = 31);
	SYSTEM.PUT(dst, 0X);
	(* methods & tags filled in later *)
	SYSTEM.PUT(ptr+rootOfs-4, ptr);	(* indirect tag *)
	SYSTEM.PUT(ptr+rootOfs, recSize);	(* recSize *)
	(* ptrOfs filled in later *)
	IF ProtTypeBit IN flags THEN	(* add ptrOfs for protected object header - cf. AosActive.ObjectHeader *)
		dst := ptr+rootOfs+(numPtrs-5+1)*4;	(* skip over recSize and user's ptrOfs *)
		SYSTEM.PUT32(dst, -36);	(* awaitingLock.head *)
		SYSTEM.PUT32(dst+4, -32);	(* awaitingLock.tail *)
		SYSTEM.PUT32(dst+8, -28);	(* awaitingCond.head *)
		SYSTEM.PUT32(dst+12, -24);	(* awaitingCond.tail *)
		SYSTEM.PUT32(dst+16, -20)	(* lockedBy *)
	END;
	SYSTEM.PUT(ptr+tdSize-4, MinPtrOfs-4*(numPtrs+1));	(* sentinel *)
	p := SYSTEM.VAL(PTR, ptr);
	AosLocks.Release(AosLocks.AosHeap)
END NewType;

(*
replaced by AddFinalizer

(** Register an object for finalization.  For use by system-level modules only.  A finalized object may not be resurrected.  The finalizers will be called by a separate process in AosProcessors.  Oberon finalizers must be installed with Kernel.RegisterObject, which will synchronize the finalizer with the Oberon lock.  When a module is freed or shut down, none of its finalizers are called any more. *)

PROCEDURE RegisterFinalizer*(obj: PTR; fin: Finalizer);
VAR n: FinalizerNode; adr: LONGINT;
BEGIN
	ASSERT(obj # NIL);
	NEW(n);
	n.objWeak := obj; n.finalizer := fin; n.objStrong := NIL;
	adr := SYSTEM.VAL(LONGINT, obj);
	IF SubObjBit IN SYSTEM.VAL(SET, obj) THEN	(* indirect tag *)
		n.markAdr := SYSTEM.GET32(adr-4) - 4
	ELSIF ProtObjBit IN SYSTEM.VAL(SET, obj) THEN	(* protected object *)
		n.markAdr := adr - (ProtOfs + 4)
	ELSE
		n.markAdr := adr - 4
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
	n.nextFin := checkRoot; checkRoot := n;
	IF Stats THEN INC(NfinalizeAlive) END;
	AosLocks.Release(AosLocks.AosHeap)
END RegisterFinalizer;
*)

PROCEDURE AddFinalizer*(obj: PTR; n: FinalizerNode);
VAR adr: LONGINT;
BEGIN
	n.objWeak := obj; n.objStrong := NIL;
	adr := SYSTEM.VAL(LONGINT, obj);
	IF SubObjBit IN SYSTEM.VAL(SET, obj) THEN	(* indirect tag *)
		n.markAdr := SYSTEM.GET32(adr-4) - 4
	ELSIF ProtObjBit IN SYSTEM.VAL(SET, obj) THEN	(* protected object *)
		n.markAdr := adr - (ProtOfs + 4)
	ELSE
		n.markAdr := adr - 4
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
	n.nextFin := checkRoot; checkRoot := n;
	IF Stats THEN INC(NfinalizeAlive) END;
	AosLocks.Release(AosLocks.AosHeap)
END AddFinalizer;

(** Compute total heap size, free space and largest free block size in bytes.  This is a slow operation. *)

PROCEDURE GetHeapInfo*(VAR total, free, largest: LONGINT);
VAR i, size, ptr: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosHeap);
	total := endBlockAdr-beginBlockAdr;
	free := 0; largest := 0; i := 0;
	WHILE i <= FreeLists DO
		ptr := freeList[i];
		WHILE ptr # NilVal DO
			SYSTEM.GET(ptr+4, size); INC(free, size);
			IF size > largest THEN largest := size END;
			SYSTEM.GET(ptr+8, ptr)	(* next *)
		END;
		INC(i)
	END;
	AosLocks.Release(AosLocks.AosHeap)
END GetHeapInfo;

(*
(** Call this periodically (e.g. a few times a second) to perform cleanup tasks. *)

PROCEDURE PeriodicCleanup*;
BEGIN
	IF newSum > gcThreshold THEN	(* call GC every so often to avoid fragmentation *)
		AosLocks.Acquire(AosLocks.AosHeap);
		newSum := 0;
		AosLocks.Release(AosLocks.AosHeap);
		GC
	END
END PeriodicCleanup;
*)

(* NilGC - Default garbage collector. *)

PROCEDURE NilGC;
BEGIN
	HALT(301)	(* garbage collector not available yet *)
END NilGC;

(* Init - Initialize the heap. *)

PROCEDURE Init;
VAR p, t, size, freeBlockAdr: LONGINT; s: SET; ch: CHAR; u: ARRAY 32 OF CHAR;
BEGIN
	AosMemory.GetFreeK(size, t, t);	(* size is total memory size in KB *)
	heapMinKB := size*HeapMin DIV 100;
	heapMaxKB := size*HeapMax DIV 100;
	expandMin := size*ExpandRate DIV 100 * 1024;
	IF expandMin < 0 THEN expandMin := MAX(LONGINT) END;
	gcThreshold := size*Threshold DIV 100 * 1024;
	IF gcThreshold < 0 THEN gcThreshold := MAX(LONGINT) END;
	newSum := 0;
		(* initialize globals *)
	GC := NilGC;
	IF Trace THEN
		AosBoot.GetConfig("TraceHeap", u);
		t := 0;  traceHeap := SYSTEM.VAL(SET, AosBoot.StrToInt(t, u))
	END;
	checkRoot := NIL; finalizeRoot := NIL;
		(* dimension heap *)
	AosMemory.GetStaticHeap(beginAdr, endAdr, beginBlockAdr, freeBlockAdr);
	ASSERT(beginBlockAdr MOD BlockSize = BlockSize-4);
	ASSERT(freeBlockAdr MOD BlockSize = BlockSize-4);
	INC(endAdr, InitialHeapIncrement);
	AosMemory.SetHeapEndAdr(endAdr);	(* in/out parameter *)
	endBlockAdr := endAdr-4;
	ASSERT((endBlockAdr - beginBlockAdr) MOD BlockSize = 0);
		(* find last block in static heap (last tag will be NIL - set in AosMemory) *)
	p := beginBlockAdr;  SYSTEM.GET(p, t);	(* get first tag *)
	WHILE t # 0 DO
		SYSTEM.GET(t - t MOD 8, size);
		SYSTEM.GET(p, s);	(* get tag again *)
		IF ArrayBit IN s THEN
			SYSTEM.GET(p+4, t);	(* get lastElemToMark *)
			size := t + size - p	(* size of array, including tag *)
		ELSE
			INC(size, 4)	(* include tag *)
		END;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));	(* round up *)
		initBlock := SYSTEM.VAL(PTR, p+(4+24));	(* last block so far, as SysBlk *)
		INC(p, size);  SYSTEM.GET(p, t)	(* get next tag *)
	END;
	SYSTEM.GET(initBlock, ch);  ASSERT(ch = 0E8X);	(* call to first module body *)
		(* now initBlock points to last block, i.e. the init calls => they won't be GC'ed *)
	
		(* initial free block *)
	p := freeBlockAdr+4;  s := SYSTEM.VAL(SET, p) + {FreeBit};
	SYSTEM.PUT(p-4, s);	(* tag *)
	SYSTEM.PUT(p, endBlockAdr-p);	(* size *)
	SYSTEM.PUT(p+4, NIL);	(* next *)
		(* the first garbage collect will be done in AosActive, after trap handling installed *)
	lastFreeListAdr := SYSTEM.ADR(freeList[FreeLists])
END Init;

BEGIN
	IF AosBoot.Trace THEN AosOut.Enter; AosOut.String("AosHeap"); AosOut.Exit END;
	Init
END AosHeap.

(*
TraceHeap:
0	1	NR NEW record
1	2	NA/NV NEW array
2	4	NS SYSTEM.NEW
3	8	DR deallocate record #
4	16	DA deallocate array #
5	32	DS deallocate sysblk #
6	64	NT NewType
7	128	
8	256	FB show free blocks #
9	512	DP deallocate protrec #
10	1024	finalizers
11	2048	live/dead #

# influences timing
*)

(*
20.03.1998	pjm	Started
17.08.1998	pjm	FindRoots method
18.08.1998	pjm	findPossibleRoots removed, use FindRoots method
09.10.1998	pjm	NewRec with page alignment
21.01.1999	pjm	Mark adapted for AosBuffers
26.01.1999	pjm	Incorporated changes for new compiler
10.11.2000	pjm	Finalizers
26.01.2001	pjm	Removed trapReserve, reimplemented NewBlock
*)
