(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosLinker0;	(* pjm *)

(* Aos Bootlinker auxiliary module *)

IMPORT SYSTEM, Files, Fonts, Texts, Oberon;

CONST
	HeapSize = 512*1024;	(* linker heap size *)
	
		(* fixup identifiers - also see GetKernelProc *)
	ModDescModule = "AosModules";  ModDescType = "Module";
	ExportDescModule = "AosModules";  ExportDescType = "ExportDesc";
	InitPtrModule = "AosModules";  InitPtrName = "initBlock";
	ModRootModule = "AosModules";  ModRootName = "root";
	StartModule = "AosActive";  StartCommand = "Terminate";
	MainModule = "AosConsole";
	
	ProtectedModule = TRUE;	(* is module descriptor protected? *)
	RelocateSelf = TRUE;	(* should the image relocate itself? *)
	
	TraceDump = FALSE;	(* should full dump be displayed? *)
	TraceAlloc = FALSE;	(* should allocations be traced? *)
	TraceRefs = TRUE & TraceDump;	(* conservatively look for "missed" internal references? *)
	TraceDuplicates = FALSE & TraceDump;	(* should duplicate relocates be allowed and highlighted? *)
	TraceLog = FALSE;	(* show log on screen *)

	LogName = "AosLinker.Log";
	
	HeaderSize = 3CH;	(* {28-HeaderSize MOD 16 = 0} *)
	EndBlockOfs = 38H;	(* 16H or 38H - cf. AosMemory.GetStaticHeap *)
	
TYPE
	AdrTable = POINTER TO ARRAY OF LONGINT;
	
(** --- MODULE AosHeap --- *)

CONST
	MaxTags* = 16;	(* in type descriptor *)
	
		(** type descriptor field offsets relative to root (middle) *)
	Tag0Ofs* = -8;	(** first tag *)
	Mth0Ofs* = Tag0Ofs - 4*MaxTags;	(** first method *)
	Ptr0Ofs* = 4;	(** first pointer offset *)

		(** flags in TypeDesc, RoundUp(log2(MaxTags)) low bits reserved for extLevel *)
	ProtTypeBit* = 31;

	BlockSize = 32;	(* power of two, <= 32 for RegisterCandidates *)
	
	MarkBit = 0;  ArrayBit = 1;  FreeBit = 2;	(* in tag *)
	SubObjBit = 3;	(* in tag or ptr => indirect tag present *)
	ProtObjBit = 4;	(* in ptr => direct tag and ProtOfs sized header present *)
	ProtOfs = BlockSize+16;	(* protected object offset (32n+16) (MOD 8=0, ~SubObjBit IN ProtOfs, MOD 32#0) *)

	MinPtrOfs = -40000000H;	(* sentinel offset for ptrOfs *)
	
TYPE
	RootObject* = OBJECT
		VAR link: LONGINT;	(* for linking root objects during GC *)
		PROCEDURE FindRoots*;	(** abstract *)
		BEGIN
			HALT(30101)
		END FindRoots;
	END RootObject;
	
(** --- MODULE AosModules --- *)

TYPE
		(* definitions for object-model loader support *)
	Name* = ARRAY 32 OF CHAR;
	
	CommandProc* = PROCEDURE;
	CommandParProc* = PROCEDURE(par: PTR): PTR;
	
	Command* = RECORD
		name*: Name;
		proc*: CommandProc;
		parproc*: CommandParProc
	END;
	
	ExportDesc* = RECORD
		fp*: LONGINT;
		adr*: LONGINT;
		exports*: LONGINT;
		dsc*: ExportArray
	END;
	ExportArray* = POINTER TO ARRAY OF ExportDesc;
	
	Bytes* = POINTER TO ARRAY OF CHAR;
	
	TerminationHandler* = PROCEDURE;
	
	TypeTag* = POINTER TO RECORD	(** pointer to "middle" of type descriptor *)
			(* compiler error: must be declared before ModuleDesc *)
		(* type: Type *)
		recSize*: LONGINT;
		ptrOfs0*: LONGINT
		(* ptrOfs1: LONGINT *)
		(* ... N ptrOfs values *)
		(* sentinel: LONGINT *)	(* = MPO-4*(N+1) *)
	END;
	
	Module* = OBJECT (RootObject)	(* cf. AosLinker0 & AosHeap.WriteType *)
		VAR
			next*: Module;
			name*: Name;
			init, published: BOOLEAN;
			refcnt*, sb*: LONGINT;
			dataSize*, constSize*, codeSize*, refSize*: LONGINT;
			entries*, commands*, modules*, types*, pointers*: LONGINT;
			entry*: POINTER TO ARRAY OF LONGINT;
			command*: POINTER TO ARRAY OF Command;
			ptrAdr*: POINTER TO ARRAY OF LONGINT;
			type*: POINTER TO ARRAY OF TypeTag;	(* traced explicitly in FindRoots *)
			module*: POINTER TO ARRAY OF Module;
			data*, code*, refs*: Bytes;
				(* slim binary support *)
			publics*, privates*: LONGINT;	(* should also be marked (slim binaries?) *)
			imports*: LONGINT;
			import*: POINTER TO ARRAY OF LONGINT;
			nofstrc*: LONGINT;
			struct*: POINTER TO ARRAY OF LONGINT;
			nofreimp*: LONGINT;
			reimp*: POINTER TO ARRAY OF LONGINT;
			export*: ExportDesc;
				(* termination handler *)
			term*: TerminationHandler;
	END Module;

		(* type descriptors *)
	TypeDesc* = POINTER TO RECORD	(** pointer to "start" of type descriptor *)	(* cf. AosHeap.NewType/WriteType *)
		(* tag0: LONGINT *)	(* = SYSTEM.ADR(descSize) *)
		descSize: LONGINT;
		sentinel: LONGINT;	(* = MPO-4 *)
		tag*: TypeTag;	(* = SYSTEM.ADR(recSize) *)
		flags*: SET;
		mod*: Module;	(* hint only, because module may have been freed (at AosHeap.ModOfs) *)
		name*: Name;
		(* method: ARRAY M OF PROCEDURE(...) *)
		(* baseTag: ARRAY 16 OF TypeTag *)
		(* typeDesc: TypeDesc *)	(* = SYSTEM.ADR(descSize) *)
		(* recSize: LONGINT *)
		(* ptrOfs: ARRAY N OF LONGINT *)
		(* sentinel: LONGINT *)	(* = MPO-4*(N+1) *)
	END;

VAR
	writer: Texts.Writer;
	log: Texts.Text;
	root: LONGINT;
	heap: SYSTEM.PTR;
	beginBlockAdr, endBlockAdr: LONGINT;	(* block boundaries of heap *)
	beginAdr, freeAdr, heapOfs: LONGINT;
	exportTags, relocates: LONGINT;
	exportTagAdr: AdrTable;
	relocateAdr: AdrTable;
	curRelocate: LONGINT;
	refsMissed: LONGINT;
	append: BOOLEAN;
	extension: ARRAY 8 OF CHAR;
	prefix: ARRAY 32 OF CHAR;
	loadObj*: PROCEDURE (name, fileName: ARRAY OF CHAR;  VAR res: LONGINT;  
			VAR msg: ARRAY OF CHAR): Module;
	getProcs: ARRAY 8 OF BOOLEAN;

(** --- MODULE AosMemory --- *)

(** Fill4 - Fill "size" dwords at "destAdr" with "filler". *)

PROCEDURE Fill4*(destAdr, size, filler: LONGINT);
CODE {SYSTEM.i386}
	MOV EDI, destAdr[EBP]
	MOV ECX, size[EBP]
	MOV EAX, filler[EBP]
	CLD
	REP STOSD
END Fill4;

(** --- MODULE AosOut --- *)

(** Char - Write a character to the trace output. *)

PROCEDURE Char*(c: CHAR);
BEGIN
	Texts.Write(writer, c)
END Char;

(** String - Write a string. *)

PROCEDURE String*(s: ARRAY OF CHAR);
BEGIN
	Texts.WriteString(writer, s)
END String;

(** Ln - Skip to the next line on trace output. *)

PROCEDURE Ln*;
BEGIN
	Texts.WriteLn(writer);
	IF append THEN Texts.Append(log, writer.buf) END
END Ln;

(** Int - Write "x" as a decimal number.  "w" is the field width. *)

PROCEDURE Int*(x, w: LONGINT);
BEGIN
	Texts.WriteInt(writer, x, w)
END Int;

(** Hex - Write "x" as a hexadecimal number.
	The absolute value of "w" is the field width.  If "w" is negative, two hex digits are printed (x MOD 100H), 
	otherwise 8 digits are printed. *)

PROCEDURE Hex*(x, w: LONGINT);
VAR
	buf: ARRAY 10 OF CHAR;
	i, j: LONGINT;
BEGIN
	IF w >= 0 THEN j := 8 ELSE j := 2; w := -w END;
	FOR i := j+1 TO w DO Char(" ") END;
	FOR i := j-1 TO 0 BY -1 DO
		buf[i] := CHR(x MOD 10H + 48);
		IF buf[i] > "9" THEN
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
		END;
		x := x DIV 10H
	END;
	buf[j] := 0X;
	String(buf)
END Hex;

(** Memory - Write a block of memory. *)

PROCEDURE Memory*(adr, size: LONGINT);
VAR i, j, t: LONGINT;  buf: ARRAY 4 OF CHAR;  reset, missed, save: BOOLEAN;
BEGIN
	save := append;  append := FALSE;
	Texts.SetFont(writer, Fonts.This("Courier10.Scn.Fnt"));
	buf[1] := 0X;  size := adr+size-1;
	reset := FALSE;
	FOR i := adr TO size BY 16 DO
		Hex(i, 9);  missed := FALSE;
		FOR j := i TO i+15 DO
			IF j <= size THEN
				IF curRelocate >= 0 THEN	(* highlighting enabled *)
					IF (j >= relocateAdr[curRelocate]) & (j <= relocateAdr[curRelocate]+3) THEN
						Texts.SetColor(writer, 3);  reset := TRUE
					ELSIF j = relocateAdr[curRelocate]+4 THEN
						INC(curRelocate);
						IF curRelocate # relocates THEN
							IF j = relocateAdr[curRelocate] THEN
								Texts.SetColor(writer, 3);  reset := TRUE
							ELSIF TraceDuplicates & (j = relocateAdr[curRelocate]+4) THEN	(* duplicate! *)
								Texts.SetColor(writer, 1);  reset := TRUE;
								REPEAT
									INC(curRelocate)
								UNTIL (curRelocate = relocates) OR (j # relocateAdr[curRelocate]+4)
							END
						ELSE
							curRelocate := -1
						END
					ELSIF TraceRefs THEN
						IF j <= adr+size-4 THEN	(* heuristic to check if all pointers were seen *)
							SYSTEM.GET(j, t);
							IF (t > beginBlockAdr) & (t < freeAdr) THEN
								INC(refsMissed);  missed := TRUE;
								Texts.SetColor(writer, 4);  reset := TRUE
							END
						END
					END
				END;
				SYSTEM.GET(j, buf[0]);
				Hex(SYSTEM.VAL(SHORTINT, buf[0]), -3);
				IF reset THEN Texts.SetColor(writer, 15) END
			ELSE
				buf := "   ";  String(buf);  buf[1] := 0X
			END
		END;
		buf[0] := " ";	String(buf);
		FOR j := i TO i+15 DO
			IF j <= size THEN
				SYSTEM.GET(j, buf[0]);
				IF (buf[0] < " ") OR (buf[0] >= CHR(127)) THEN
					buf[0] := "."
				END;
				String(buf)
			END
		END;
		IF missed THEN String(" <--missed?") END;
		Ln
	END;
	Texts.SetFont(writer, Fonts.Default);
	append := save
END Memory;

(** Bits - Write bits (ofs..ofs+n-1) of x in binary. *)

PROCEDURE Bits*(x: SET;  ofs, n: LONGINT);
BEGIN
	REPEAT
		DEC(n);
		IF (ofs+n) IN x THEN Char("1") ELSE Char("0") END
	UNTIL n = 0
END Bits;

(** Enter - Enter mutually exclusive region for writing. *)

PROCEDURE Enter*;
BEGIN
	Char("{")
END Enter;

(** Exit - Exit mutually exclusive region for writing. *)

PROCEDURE Exit*;
BEGIN
	Char("}");  Ln
END Exit;

(** --- MODULE AosHeap --- *)

(* NewBlock - Allocate a heap block.  {(size MOD BlockSize = 0) & (ret MOD BlockSize = BlockSize-4)} *)

PROCEDURE NewBlock(size: LONGINT): LONGINT;
VAR p: LONGINT;
BEGIN
	ASSERT(size MOD BlockSize = 0);
	p := freeAdr;  INC(freeAdr, size);
	ASSERT(freeAdr <= endBlockAdr);	(* still enough memory *)
	ASSERT(p MOD BlockSize = BlockSize-4);
	RETURN p
END NewBlock;

(** NewSys - Implementation of SYSTEM.NEW. *)

PROCEDURE NewSys*(VAR p: SYSTEM.PTR;  size: LONGINT);
VAR ptr: LONGINT;
BEGIN
		(* add space for tag & fake type descriptor and round up to BlockSize *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (4 + 24 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	ptr := NewBlock(size);
	IF TraceAlloc THEN
		Hex(heapOfs+ptr+4, 8);  String(" SysBlk ");  Int(size, 1);  Ln
	END;
	SYSTEM.PUT(ptr, ptr+4);	(* tag *)
	Relocate(ptr);
	SYSTEM.PUT(ptr+4, size-4);
	SYSTEM.PUT(ptr+8, SYSTEM.VAL(LONGINT, MinPtrOfs-4));
	SYSTEM.PUT(ptr+12, NIL);	(* could be used for tracing caller of SYSTEM.NEW *)
	SYSTEM.PUT(ptr+16, NIL);	(* not used *)
	SYSTEM.PUT(ptr+20, {});	(* bit 1 must be 0 to distinguish from array SysBlk *)
	SYSTEM.PUT(ptr+24, ptr+4);	(* SysBlk tag *)
	Relocate(ptr+24);
	p := SYSTEM.VAL(SYSTEM.PTR, ptr+28);
	Fill4(SYSTEM.VAL(LONGINT, p), (size-28) DIV 4, 0)	(* clear everything except header *)
END NewSys;

(** NewType - Allocate a new type descriptor. *)

PROCEDURE NewType*(VAR p: SYSTEM.PTR; recSize, numPtrs, numSlots: LONGINT; name: ARRAY OF CHAR;  mod: SYSTEM.PTR; flags: SET);
VAR ptr, rootOfs, tdSize, size, i, dst: LONGINT;  flag: INTEGER;  ch: CHAR;
BEGIN
	IF ProtTypeBit IN flags THEN INC(numPtrs, 5) END;	(* hidden pointers for protected object *)
	rootOfs := 4*(4+1+numSlots+1) + 32;	(* all fields in TDesc up to recSize, excluding tag *)
	INC(rootOfs, (-rootOfs+8) MOD 16);	(* align as SubObj *)
	tdSize := rootOfs + 4*(1+numPtrs+1);	(* recSize, ptrs & sentinel *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tdSize + (4 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	ptr := NewBlock(size)+4;
	IF TraceAlloc THEN
		Hex(heapOfs+ptr, 8);  String(" TypeDesc ");  Int(size, 1);  Ln
	END;
	SYSTEM.PUT(ptr-4, ptr);	(* tag *)
	Relocate(ptr-4);
	Fill4(ptr+16, (size-(4+16)) DIV 4, 0);	(* clear everything except first 4 fields & tag *)
	SYSTEM.PUT(ptr, tdSize);	(* tdSize *)
	SYSTEM.PUT(ptr+4, SYSTEM.VAL(LONGINT, MinPtrOfs-4));	(* sentinel *)
	SYSTEM.PUT(ptr+8, ptr + rootOfs);	(* self *)
	Relocate(ptr+8);
	SYSTEM.GET(ptr+10, flag); ASSERT(flag # -1);	(* protected object "flag" for AosInfo.Objects *)
	SYSTEM.PUT(ptr+12, flags);
	SYSTEM.PUT(ptr+16, mod);	(* module hint only, because not traced *)
	Relocate(ptr+16);
	i := 0;  dst := ptr+20;	(* name *)
	REPEAT ch := name[i];  SYSTEM.PUT(dst, ch);  INC(dst);  INC(i) UNTIL (ch = 0X) OR (i = 31);
	SYSTEM.PUT(dst, 0X);
	(* methods & tags filled in later *)
	SYSTEM.PUT(ptr+rootOfs-4, ptr);	(* indirect tag *)
	Relocate(ptr+rootOfs-4);
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
	p := SYSTEM.VAL(SYSTEM.PTR, ptr)
END NewType;

(** --- MODULE AosModules --- *)

(** Append - Append from to to, truncating on overflow. *)

PROCEDURE Append*(from: ARRAY OF CHAR;  VAR to: ARRAY OF CHAR);
VAR i, j, m: LONGINT;
BEGIN
	j := 0;  WHILE to[j] # 0X DO INC(j) END;
	m := LEN(to)-1;
	i := 0;  WHILE (from[i] # 0X) & (j # m) DO to[j] := from[i];  INC(i);  INC(j) END;
	to[j] := 0X
END Append;

(* Publish - Add a module to the pool of accessible modules, or return named module. *)

PROCEDURE Publish(VAR m: Module;  VAR new: BOOLEAN);
VAR n: Module;  i: LONGINT;
BEGIN
	n := SYSTEM.VAL(Module, root);
	WHILE (n # NIL) & (n.name # m.name) DO n := n.next END;
	IF n # NIL THEN	(* module with same name exists, return it and ignore new m *)
		m := n;  new := FALSE
	ELSE
		m.published := TRUE;
		m.next := SYSTEM.VAL(Module, root);
		root := SYSTEM.VAL(LONGINT, m);
		m.refcnt := 0;
		FOR i := 0 TO m.modules-1 DO INC(m.module[i].refcnt) END;
		new := TRUE
	END
END Publish;

(* ModuleByName - Return the named module. *)

PROCEDURE ModuleByName(name: ARRAY OF CHAR): Module;
VAR m: Module;
BEGIN
	m := SYSTEM.VAL(Module, root);
	WHILE (m # NIL) & (m.name # name) DO m := m.next END;
	RETURN m
END ModuleByName;

(* GetFileName - Generate a module file name. *)

PROCEDURE GetFileName(name: ARRAY OF CHAR;  VAR fileName: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	i := 0;  WHILE prefix[i] # 0X DO fileName[i] := prefix[i];  INC(i) END;
	j := 0;  WHILE name[j] # 0X DO fileName[i] := name[j];  INC(i);  INC(j) END;
	j := 0;  WHILE extension[j] # 0X DO fileName[i] := extension[j];  INC(i);  INC(j) END;
	fileName[i] := 0X
END GetFileName;

(** ThisModule - Import a module. *)	(* Algorithm J. Templ, ETHZ, 1994 *)

PROCEDURE ThisModule*(name: ARRAY OF CHAR;  VAR res: LONGINT;  VAR msg: ARRAY OF CHAR): Module;
TYPE Body = PROCEDURE;
VAR m, p: Module;  fileName: ARRAY 64 OF CHAR;  (*body: Body;*)  new: BOOLEAN;
BEGIN
	res := 0;  msg[0] := 0X;  m := ModuleByName(name);
	IF m = NIL THEN
		GetFileName(name, fileName);
		m := loadObj(name, fileName, res, msg);
		IF (m # NIL) & ~m.published THEN
			p := m;  Publish(m, new);
			IF new THEN	(* m was successfully published *)
				(*body := SYSTEM.VAL(Body, SYSTEM.ADR(m.code[0]));
				body;  res := 0;  msg[0] := 0X;*)
				m.init := TRUE	(* allow ThisCommand *)
			ELSE
				(* m was part of cycle, replaced by existing module *)
				HALT(99)
			END
		END
	END;
	RETURN m
END ThisModule;

(** ThisType - Return the named type. *)

PROCEDURE ThisType*(m: Module;  name: ARRAY OF CHAR): TypeDesc;
VAR i, k, t: LONGINT;  type: TypeDesc;
BEGIN
	i := 0;  k := LEN(m.type^);
	WHILE i # k DO
		t := SYSTEM.VAL(LONGINT, m.type[i]);
		SYSTEM.GET(t-4, type);
		IF type.name = name THEN k := i ELSE INC(i) END
	END;
	IF k = LEN(m.type) THEN type := NIL END;	(* not found *)
	RETURN type
END ThisType;

(** --- MODULE AosLinker0 --- *)

(* GrowTable - Grow an address table. *)

PROCEDURE GrowTable(VAR table: AdrTable);
VAR new: AdrTable;  i: LONGINT;
BEGIN
	NEW(new, 2*LEN(table));
	FOR i := 0 TO LEN(table)-1 DO new[i] := table[i] END;
	table := new
END GrowTable;

(** Relocate - Record a relocate location. *)

PROCEDURE Relocate*(adr: LONGINT);
BEGIN
	IF relocates = LEN(relocateAdr) THEN GrowTable(relocateAdr) END;
	relocateAdr[relocates] := adr;  INC(relocates);
	SYSTEM.GET(adr, adr);
	ASSERT((adr = 0) OR (adr > beginBlockAdr) & (adr <= freeAdr))
END Relocate;

(** Open - Initialize the log file etc. *)

PROCEDURE Open*(pre: ARRAY OF CHAR; base: LONGINT);
VAR i: LONGINT;
BEGIN
	COPY(pre, prefix);
	root := 0;  freeAdr := beginBlockAdr;  heapOfs := base - beginAdr;
	exportTags := 0;  relocates := 0;  refsMissed := 0;
	curRelocate := -1;  append := TraceLog;
	IF writer.buf.len # 0 THEN Texts.OpenWriter(writer) END;	(* new writer *)
	NEW(log);  Texts.Open(log, "");
	IF TraceLog THEN
		Oberon.OpenText(LogName, log, 400, 200)
	END;
	FOR i := 0 TO 7 DO getProcs[i] := FALSE END
END Open;

(* RelocateModules - Relocate the module records. *)

PROCEDURE RelocateModules;
VAR adr, i: LONGINT;  type: TypeDesc;  m: Module;
BEGIN
	type := ThisType(ModuleByName(ModDescModule), ModDescType);
	ASSERT(type # NIL);
	IF ProtectedModule THEN
		INCL(type.flags, ProtTypeBit)	(* flag for dynamic loader *)
	END;
	m := SYSTEM.VAL(Module, root);
	WHILE m # NIL DO
		adr := SYSTEM.VAL(LONGINT, m);
		SYSTEM.PUT(adr-4, type.tag);  Relocate(adr-4);	(* module descriptor tag *)
		Relocate(SYSTEM.ADR(m.next));
		Relocate(m.sb);	(* SELF in const area *)
		Relocate(SYSTEM.ADR(m.sb));
			(* m.entry in module block *)
		(* m.entry indirect tag already relocated (same as SysBlk) *)
		FOR i := 0 TO LEN(m.entry)-1 DO Relocate(SYSTEM.ADR(m.entry[i])) END;
		Relocate(SYSTEM.ADR(m.entry));
			(* m.command in module block *)
		Relocate(SYSTEM.VAL(LONGINT, m.command)-4);	(* indirect tag *)
		FOR i := 0 TO LEN(m.command)-1 DO
			Relocate(SYSTEM.ADR(m.command[i].proc));
			Relocate(SYSTEM.ADR(m.command[i].parproc))
		END;
		Relocate(SYSTEM.ADR(m.command));
			(* m.ptrAdr in module block *)
		Relocate(SYSTEM.VAL(LONGINT, m.ptrAdr)-4);	(* indirect tag *)
		FOR i := 0 TO LEN(m.ptrAdr)-1 DO Relocate(SYSTEM.ADR(m.ptrAdr[i])) END;
		Relocate(SYSTEM.ADR(m.ptrAdr));
			(* m.type in module block *)
		Relocate(SYSTEM.VAL(LONGINT, m.type)-4);	(* indirect tag *)
		FOR i := 0 TO LEN(m.type)-1 DO Relocate(SYSTEM.ADR(m.type[i])) END;
		Relocate(SYSTEM.ADR(m.type));
			(* m.module in module block *)
		Relocate(SYSTEM.VAL(LONGINT, m.module)-4);	(* indirect tag *)
		FOR i := 0 TO LEN(m.module)-1 DO Relocate(SYSTEM.ADR(m.module[i])) END;
		Relocate(SYSTEM.ADR(m.module));
			(* m.data in module block *)
		Relocate(SYSTEM.VAL(LONGINT, m.data)-4);	(* indirect tag *)
		Relocate(SYSTEM.ADR(m.data));
			(* m.code in module block *)
		Relocate(SYSTEM.VAL(LONGINT, m.code)-4);	(* indirect tag *)
		Relocate(SYSTEM.ADR(m.code));
			(* m.refs in module block *)
		Relocate(SYSTEM.VAL(LONGINT, m.refs)-4);	(* indirect tag *)
		Relocate(SYSTEM.ADR(m.refs));
			(* object model support *)
		ASSERT((m.publics = 0) & (m.privates = 0));	(* not marked *)
		ASSERT(m.import = NIL);	(* not marked *)
		ASSERT(m.struct = NIL);	(* not marked *)
		ASSERT(m.reimp = NIL);	(* not marked *)
		Relocate(SYSTEM.ADR(m.export.dsc));	(* descendants relocated via RelocateArray *)
		m := m.next
	END
END RelocateModules;

(* RelocateArray - Fix up a dynamic array. *)

PROCEDURE RelocateArray(tagAdr: LONGINT);
VAR adr, ofs, p, lastElem, recSize: LONGINT;
BEGIN
	SYSTEM.GET(tagAdr+4, lastElem);
	SYSTEM.GET(tagAdr+12, p);	(* firstElem *)
	SYSTEM.GET(tagAdr, adr);
	adr := adr - adr MOD 8;	(* ADR(recSize) *)
	SYSTEM.GET(adr, recSize);
	Relocate(tagAdr);	(* tag *)
	Relocate(tagAdr+4);	(* lastElemToMark *)
	Relocate(tagAdr+12);	(* firstElem *)
	INC(adr, 4);	(* ADR(ptrOfs0) *)
	LOOP
		SYSTEM.GET(adr, ofs);
		WHILE ofs >= MinPtrOfs+0 DO
			Relocate(p+ofs);
			INC(adr, 4);
			SYSTEM.GET(adr, ofs)
		END;
		IF p = lastElem THEN EXIT END;
		INC(adr, ofs-MinPtrOfs+4);	(* step back to ADR(ptrOfs0) *)
		INC(p, recSize)	(* step to next array element *)
	END
END RelocateArray;

(* RelocateExports - Relocate export arrays. *)

PROCEDURE RelocateExports;
VAR type: TypeDesc;  i: LONGINT;
BEGIN
		(* fix the export record tags *)
	type := ThisType(ModuleByName(ExportDescModule), ExportDescType);
	ASSERT(type # NIL);
	FOR i := 0 TO exportTags-1 DO
		SYSTEM.PUT(exportTagAdr[i], SYSTEM.VAL(SET, type.tag) + {ArrayBit});
		RelocateArray(exportTagAdr[i])
	END
END RelocateExports;

(* SortRelocates - Sort the relocates. *)

PROCEDURE SortRelocates;
VAR h, i, j, p: LONGINT;
BEGIN
	h := 1;  REPEAT h := h*3 + 1 UNTIL h > relocates;
	REPEAT
		h := h DIV 3;  i := h;
		WHILE i < relocates DO
			p := relocateAdr[i];  j := i;
			WHILE (j >= h) & (relocateAdr[j-h] > p) DO
				relocateAdr[j] := relocateAdr[j-h];  j := j-h;
			END;
			relocateAdr[j] := p;  INC(i)
		END
	UNTIL h = 1;
	IF ~TraceDuplicates THEN
		FOR i := 1 TO relocates-1 DO ASSERT(relocateAdr[i-1] < relocateAdr[i]) END	(* sorted, without dups *)
	END
END SortRelocates;

(* GetNum - Get a compressed refblk number. *)

PROCEDURE GetNum(refs: Bytes;  VAR i, num: LONGINT);
VAR n, s: LONGINT;  x: CHAR;
BEGIN
	s := 0;  n := 0;
	x := refs[i];  INC(i);
	WHILE ORD(x) >= 128 DO
		INC(n, ASH(ORD(x) - 128, s));
		INC(s, 7);
		x := refs[i];  INC(i)
	END;
	num := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64 * 64, s)
END GetNum;

(* VarByName - Find a global variable in the reference block. *)

PROCEDURE VarByName(refs: Bytes;  i: LONGINT;  name: ARRAY OF CHAR): LONGINT;
VAR mode: CHAR;  j, m, adr, type, t: LONGINT;  s: Name;  found: BOOLEAN;
BEGIN
	m := LEN(refs^);  found := FALSE;
	mode := refs[i];  INC(i);
	WHILE (i < m) & ((mode = 1X) OR (mode = 3X)) & ~found DO	(* var *)
		type := ORD(refs[i]);  INC(i);
		IF (type >= 81H) OR (type = 16H) OR (type = 1DH) THEN
			GetNum(refs, i, t)	(* dim/tdadr *)
		END;
		GetNum(refs, i, adr);
		j := 0;  REPEAT s[j] := refs[i];  INC(i);  INC(j) UNTIL s[j-1] = 0X;
		IF s = name THEN found := TRUE
		ELSIF i < m THEN mode := refs[i];  INC(i)
		END
	END;
	IF found THEN
		ASSERT((mode = 1X) & ((type = 0DH) OR (type = 1DH)))	(* pointer VAR *)
	ELSE
		adr := 0
	END;
	RETURN adr
END VarByName;

(* InitTable - Generate init code for module bodies. *)

PROCEDURE InitTable(diff, baseAdr, loadAdr: LONGINT);
VAR i, n, adr: LONGINT;  init: SYSTEM.PTR;  m: Module;

	PROCEDURE InitBody(m: Module);
	BEGIN
		IF m = NIL THEN
			NewSys(init, 5*n + (5+3));  adr := SYSTEM.VAL(LONGINT, init)
		ELSE
			INC(n);  InitBody(m.next);
			Hex(SYSTEM.ADR(m.code[0])+diff, 10);  Char("H");  Char(" ");  String(m.name);  Ln;
			SYSTEM.PUT(adr, 0E8X);	(* CALL *)
			SYSTEM.PUT(adr+1, SYSTEM.ADR(m.code[0]) - (adr+5));
			INC(adr, 5)
		END
	END InitBody;

BEGIN
	String("BEGIN");  Ln;
	n := 0;  InitBody(SYSTEM.VAL(Module, root));
	String("END");  Ln;
		(* startup command *)
	m := ModuleByName(StartModule);
	i := 0;  WHILE m.command[i].name # StartCommand DO INC(i) END;
	Hex(SYSTEM.VAL(LONGINT, m.command[i].proc)+diff, 8);  Char(" ");
	String(m.name);  Char(".");  String(StartCommand);  Ln;
	SYSTEM.PUT(adr, 0E8X);	(* CALL *)
	SYSTEM.PUT(adr+1, SYSTEM.VAL(LONGINT, m.command[i].proc) - (adr+5));
	INC(adr, 5);
		(* HALT *)
	SYSTEM.PUT(adr, 6AX);	(* PUSH imm8 *)
	SYSTEM.PUT(adr+1, 0FFX);
	SYSTEM.PUT(adr+2, 0CCX);	(* INT 3 *)
		(* root init block pointer *)
	m := ModuleByName(InitPtrModule);
	ASSERT((m.refs[0] = 0F8X) & (m.refs[1] = 0X) & (m.refs[2] = "$") & (m.refs[3] = "$") & (m.refs[4] = 0X));
	i := 5;  adr := VarByName(m.refs, i, InitPtrName);
	ASSERT(adr # 0);
	SYSTEM.PUT(m.sb + adr, init);  Relocate(m.sb + adr);
		(* module root pointer *)
	m := ModuleByName(ModRootModule);
	ASSERT((m.refs[0] = 0F8X) & (m.refs[1] = 0X) & (m.refs[2] = "$") & (m.refs[3] = "$") & (m.refs[4] = 0X));
	i := 5;  adr := VarByName(m.refs, i, ModRootName);
	ASSERT(adr # 0);
	SYSTEM.PUT(m.sb + adr, root);  Relocate(m.sb + adr);
		(* init table *)
	FOR adr := beginAdr TO beginAdr+HeaderSize-1 DO
		SYSTEM.PUT(adr, 0X)
	END;
	IF baseAdr = loadAdr THEN
		SYSTEM.PUT(beginAdr, 0E8X);	(* CALL *)
		SYSTEM.PUT(beginAdr+1, SYSTEM.VAL(LONGINT, init) - (beginAdr+5))
	ELSE	(* image will relocate itself *)
		adr := beginAdr;
		SYSTEM.PUT(adr, 60X);	(* PUSHAD *)
		INC(adr);
		SYSTEM.PUT(adr, 0BEX);	(* MOV ESI, X *)
		SYSTEM.PUT(adr+1, loadAdr);
		INC(adr, 5);
		SYSTEM.PUT(adr, 0BFX);	(* MOV EDI, X *)
		SYSTEM.PUT(adr+1, baseAdr);
		INC(adr, 5);
		SYSTEM.PUT(adr, 0B9X);	(* MOV ECX, X *)
		SYSTEM.PUT(adr+1, (freeAdr-beginAdr+3) DIV 4);	(* length of image in dwords *)
		INC(adr, 5);
		SYSTEM.PUT(adr, 0FCX);	(* CLD *)
		SYSTEM.PUT(adr+1, 0F3X);	(* REP *)
		SYSTEM.PUT(adr+2, 0A5X);	(* MOVSD *)
		INC(adr, 3);
		SYSTEM.PUT(adr, 61X);	(* POPAD *)
		INC(adr);
		SYSTEM.PUT(adr, 0E8X);	(* CALL *)
		SYSTEM.PUT(adr+1, SYSTEM.VAL(LONGINT, init) - (adr+5) + (baseAdr-loadAdr));
		INC(adr, 5);
		ASSERT(adr-beginAdr <= EndBlockOfs)	(* not too much code *)
	END;
	SYSTEM.PUT(beginAdr + EndBlockOfs, freeAdr);  Relocate(beginAdr + EndBlockOfs);
END InitTable;

(* ScopeInfo - Write information for debugger. *)

PROCEDURE ScopeInfo(diff, baseAdr: LONGINT;  root: Module);
VAR main: LONGINT;  m: Module;  i: LONGINT;
BEGIN
	m := root;  WHILE (m # NIL) & (m.name # MainModule) DO m := m.next END;
	IF m = NIL THEN main := -1 ELSE main := SYSTEM.ADR(m.code[0])+diff END;
	IF main = -1 THEN String(MainModule);  String(" not found");  Ln END;
	String("SCOPE.BEGIN 0");  Hex(baseAdr, 8);  String("H 0");  Hex(main, 8);  Char("H");  Ln;
	m := root;
	WHILE m # NIL DO
		String("  ");  String(m.name);  String(" 0");
		Hex(SYSTEM.ADR(m.code[0])+diff, 8);  String("H 0");
		Hex(m.codeSize, 8);  String("H 0");
		Hex(m.sb, 8);  String("H ");  Int(m.types, 1);  Ln;
		FOR i := 0 TO m.types-1 DO
			String("    0");  Hex(-1, 8);  String("H 0");
			Hex(SYSTEM.VAL(LONGINT, m.type[i])+diff, 8);  Char("H");  Ln
		END;
		m := m.next
	END;
	String("SCOPE.END");  Ln
END ScopeInfo;

(** Close - Finalize the log file etc. *)

PROCEDURE Close*(out: ARRAY OF CHAR;  baseAdr, loadAdr, res: LONGINT;  msg: ARRAY OF CHAR);
VAR i, adr, diff: LONGINT;  r: Files.Rider;  ch: CHAR;
BEGIN
	IF res = 0 THEN
		IF baseAdr = -1 THEN diff := 0 ELSE diff := baseAdr - beginAdr END;
		InitTable(diff, baseAdr, loadAdr);
		ScopeInfo(diff, baseAdr, SYSTEM.VAL(Module, root));
		RelocateModules;
		RelocateExports;
			(* relocate addresses *)
		FOR i := 0 TO relocates-1 DO
			SYSTEM.GET(relocateAdr[i], adr);
			IF adr # 0 THEN
				ASSERT((adr > beginBlockAdr) & (adr <= freeAdr));
				SYSTEM.PUT(relocateAdr[i], adr + diff)
			END
		END;
			(* output *)
		IF TraceDump THEN
			SortRelocates;  curRelocate := 0;	(* for highlighting of relocations *)
			Memory(beginAdr, freeAdr-beginAdr);
			ASSERT(curRelocate = -1)	(* all relocations highlighted *)
		END;
		String("  exports: ");  Int(exportTags, 1);  String("  relocates: ");  Int(relocates, 1);
		IF TraceRefs THEN String("  possible missed references: ");  Int(refsMissed, 1) END;
		Ln;
		Files.Set(r, Files.New(out), 0);
		FOR adr := beginAdr TO freeAdr-1 DO
			SYSTEM.GET(adr, ch);
			Files.Write(r, ch)
		END;
		Files.Register(Files.Base(r));
		String(out);  Char(" ");  Int(freeAdr-beginAdr, 1);  Ln
	END;
	String("Result = ");  Int(res, 1);  Char(" ");  String(msg);  Ln;
	Texts.Append(log, writer.buf);
	IF res = 0 THEN
		Texts.WriteString(writer, out);  Texts.Write(writer, " ");
		Texts.WriteInt(writer, freeAdr-beginAdr, 1);  Texts.Write(writer, " ");
		Texts.WriteString(writer, LogName)
	ELSE
		Texts.WriteString(writer, "Error report in ");  Texts.WriteString(writer, LogName)
	END;
	Files.Set(r, Files.New(LogName), 0);
	Texts.Store(log, Files.Base(r), 0, i);
	Files.Register(Files.Base(r));
	Texts.WriteLn(writer);  Texts.Append(Oberon.Log, writer.buf);
	log := NIL
END Close;

(* NewModule - Allocate a module descriptor. *)

PROCEDURE NewModule*(VAR m: Module);
VAR size, ptr, tag: LONGINT;
BEGIN
	size := SYSTEM.GET32(SYSTEM.TYPECODE(Module));	(* get size of module descriptor *)
	tag := 0;
		(* add space for tag and round up to BlockSize *)
	IF ProtectedModule THEN
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (4 + ProtOfs + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1))
	ELSE
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (4 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1))
	END;
	ptr := NewBlock(size);
	IF TraceAlloc THEN
		IF ProtectedModule THEN
			Hex(heapOfs+ptr+(4+ProtOfs), 8)
		ELSE
			Hex(heapOfs+ptr+4, 8)
		END;
		String(" ModuleDesc ");  Int(size, 1);  Ln
	END;
	IF ProtectedModule THEN
		SYSTEM.PUT(ptr, ptr+4);	(* set the main tag *)
		Relocate(ptr);
		SYSTEM.PUT(ptr+4, size-4);	(* size *)
		SYSTEM.PUT(ptr+8, SYSTEM.VAL(LONGINT, MinPtrOfs-4));
		Fill4(ptr+12, (ProtOfs-12) DIV 4, 0);	(* clear header *)
		SYSTEM.PUT(ptr+(4+10), SYSTEM.VAL(INTEGER, -1));	(* flag = -1 *)
		SYSTEM.PUT(ptr+(4+ProtOfs-4), tag);	(* set the tag *)
		m := SYSTEM.VAL(Module, ptr+(4+ProtOfs));
		Fill4(SYSTEM.VAL(LONGINT, m), (size-(4+ProtOfs)) DIV 4, 0)	(* clear everything except tag & header *)
	ELSE
		SYSTEM.PUT(ptr, tag);	(* set the tag *)
		m := SYSTEM.VAL(Module, ptr+4);
		Fill4(ptr+4, (size-4) DIV 4, 0)	(* clear everything except tag *)
	END
END NewModule;

(* NewExportDesc - Allocate an export array. *)

PROCEDURE NewExportDesc*(VAR p: ExportArray;  numElems: LONGINT);
VAR elemTag, numDims, ptr, size, firstElem, elemSize, arrSize, vectSize: LONGINT;
BEGIN
	elemTag := 0;  numDims := 1;  elemSize := SIZE(ExportDesc);
	arrSize := numElems * elemSize;
	ASSERT(arrSize > 0);
	vectSize := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, 4*numDims) + SYSTEM.VAL(SET, 4));	(* => firstElem MOD 8 = 0 *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, arrSize + vectSize + (16 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	ptr := NewBlock(size);
	IF TraceAlloc THEN
		Hex(heapOfs+ptr+4, 8);  String(" ExportDesc ");  Int(size, 1);  Ln
	END;
	firstElem := ptr + 16 + vectSize;
	SYSTEM.PUT(ptr, SYSTEM.VAL(SET, elemTag) + {ArrayBit});	(* tag *)
	IF exportTags = LEN(exportTagAdr) THEN GrowTable(exportTagAdr) END;
	exportTagAdr[exportTags] := ptr;  INC(exportTags);
	SYSTEM.PUT(ptr+4, firstElem + arrSize - elemSize);	(* lastElemToMark *)
	SYSTEM.PUT(ptr+8, NIL);	(* reserved for Mark *)
	SYSTEM.PUT(ptr+12, firstElem);	(* firstElem *)
	p := SYSTEM.VAL(ExportArray, ptr+4);
	Fill4(ptr+16, (size-16) DIV 4, 0);
	(* ptr+16..ptr+16 + vectSize-1 initialized by compiler-generated code *)
	(* [ptr+16] = 0 (lower bound) *)
	SYSTEM.PUT(ptr+16, numElems)	(* dim 0 *)
END NewExportDesc;

(* InitHeap - Initialize the virtual heap. *)

PROCEDURE InitHeap;
BEGIN
	SYSTEM.NEW(heap, HeapSize);
	beginBlockAdr := SYSTEM.VAL(LONGINT, heap) + HeaderSize;
	endBlockAdr := beginBlockAdr + HeapSize - HeaderSize;
	INC(beginBlockAdr, (-beginBlockAdr-4) MOD BlockSize);	(* align *)
	beginAdr := beginBlockAdr-HeaderSize;
	DEC(endBlockAdr, (endBlockAdr+4) MOD BlockSize);	(* align *)
	ASSERT(beginBlockAdr < endBlockAdr);
	ASSERT(beginBlockAdr MOD BlockSize = BlockSize-4);
	ASSERT(endBlockAdr MOD BlockSize = BlockSize-4)
END InitHeap;

(*
	Reference = {OldRef | ProcRef} .
	OldRef = 0F8X offset/n name/s {Variable} .
	ProcRef = 0F9X offset/n nofPars/n RetType procLev/1 slFlag/1 name/s {Variable} .
	RetType = 0X | Var | ArrayType | Record .
	ArrayType = 12X | 14X | 15X .	(* static array, dynamic array, open array *)
	Record = 16X .
	Variable = VarMode (Var | ArrayVar | RecordVar ) offset/n name/s .
	VarMode = 1X | 3X .	(* direct, indirect *)
	Var = 1X .. 0FX .	(* byte, boolean, char, shortint, integer, longint, real, longreal, set, ptr, proc, string *)
	ArrayVar = (81X .. 8EX) dim/n .	(* byte, boolean, char, shortint, integer, longint, real, longreal, set, ptr, proc *)
	RecordVar = (16X | 1DX) tdadr/n .	(* record, recordpointer *)
*)

(* ProcByName - Find a procedure in the reference block.  Return procedure offset, or -1 if not found. *)

PROCEDURE ProcByName(refs: Bytes;  name: ARRAY OF CHAR): LONGINT;
VAR i, j, m, t, pofs: LONGINT;  ch: CHAR;  found: BOOLEAN;
BEGIN
	i := 0;  m := LEN(refs^);  found := FALSE;
	ch := refs[i];  INC(i);
	WHILE (i < m) & ((ch = 0F8X) OR (ch = 0F9X)) & ~found DO	(* proc *)
		GetNum(refs, i, pofs);
		IF ch = 0F9X THEN
			GetNum(refs, i, t);	(* nofPars *)
			INC(i, 3)	(* RetType, procLev, slFlag *)
		END;
		j := 0;  WHILE (name[j] = refs[i]) & (name[j] # 0X) DO INC(i);  INC(j) END;
		IF (name[j] = 0X) & (refs[i] = 0X) THEN
			found := TRUE
		ELSE
			WHILE refs[i] # 0X DO INC(i) END;
			INC(i);
			IF i < m THEN
				ch := refs[i];  INC(i);	(* 1X | 3X | 0F8X | 0F9X *)
				WHILE (i < m) & ((ch = 1X) OR (ch = 3X)) DO	(* var *)
					ch := refs[i];  INC(i);	(* type *)
					IF (ch >= 81X) OR (ch = 16X) OR (ch = 1DX) THEN
						GetNum(refs, i, t)	(* dim/tdadr *)
					END;
					GetNum(refs, i, t);	(* vofs *)
					REPEAT ch := refs[i];  INC(i) UNTIL ch = 0X;	(* vname *)
					ch := refs[i];  INC(i)	(* 1X | 3X | 0F8X | 0F9X *)
				END
			END
		END
	END;
	IF ~found THEN pofs := -1 END;
	RETURN pofs
END ProcByName;

(* GetProc - Return procedure address. *)

PROCEDURE GetProc(m: Module; i: LONGINT; mod, proc: ARRAY OF CHAR): LONGINT;
VAR adr: LONGINT;
BEGIN
	IF m.name # mod THEN	(* fixup not in current module *)
		m := ModuleByName(mod)	(* must have been loaded already *)
	END;
	adr := ProcByName(m.refs, proc);
	IF ~getProcs[i] THEN
		String("GetProc "); String(mod); Char("."); String(proc); Hex(adr, 9); Ln;
		getProcs[i] := TRUE
	END;
	ASSERT(adr # -1);
	RETURN SYSTEM.ADR(m.code[0]) + adr
END GetProc;

(* GetKernelProc - Return the specified kernel procedure. *)

PROCEDURE GetKernelProc*(m: Module; num: LONGINT): LONGINT;
VAR adr: LONGINT;
BEGIN
	CASE num OF
		246: adr := GetProc(m, 1, "AosActive", "Unlock")
		|247: adr := GetProc(m, 2, "AosActive", "Lock")
		|249: adr := GetProc(m, 3, "AosActive", "Await")
		|250: adr := GetProc(m, 4, "AosActive", "CreateProcess")
		|251: adr := GetProc(m, 5, "AosHeap", "NewArr")
		|252: adr := GetProc(m, 6, "AosHeap", "NewSys")
		|253: adr := GetProc(m, 7, "AosHeap", "NewRec")
	END;
	RETURN adr
END GetKernelProc;

(** AosLinker0.Find adr. *)

PROCEDURE Find*;
VAR s: Texts.Scanner;  adr, min, ofs: LONGINT;  t: Texts.Text;  name: ARRAY 64 OF CHAR;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF s.class = Texts.Int THEN
		adr := s.i;  name := "";  min := MAX(LONGINT);
		NEW(t);  Texts.Open(t, LogName);
		IF t.len # 0 THEN
			Texts.OpenScanner(s, t, 0);
			REPEAT Texts.Scan(s) UNTIL s.eot OR ((s.class = Texts.Name) & (s.s = "BEGIN"));
			IF ~s.eot THEN
				LOOP
					Texts.Scan(s);
					IF (s.class = Texts.Name) & (s.s = "END") THEN EXIT END;
					ASSERT(s.class = Texts.Int);
					ofs := adr - s.i;
					Texts.Scan(s);  ASSERT(s.class = Texts.Name);
					IF (ofs >= 0) & (ofs < min) THEN
						min := ofs;  COPY(s.s, name)
					END
				END;
				IF min = MAX(LONGINT) THEN
					Texts.WriteString(writer, "not found")
				ELSE
					Texts.WriteString(writer, name);  Texts.WriteString(writer, ".Mod  PC = ");
					Texts.WriteInt(writer, min, 1)
				END;
				Texts.WriteLn(writer);  Texts.Append(Oberon.Log, writer.buf)
			END
		END
	END
END Find;

(** Dump the log text to the System log.  Use in case of trap. *)

PROCEDURE WriteLog*;
BEGIN
	Texts.Append(Oberon.Log, writer.buf)
END WriteLog;

BEGIN
	extension := ".Obx";
	Texts.OpenWriter(writer);
	NEW(relocateAdr, 2048);  NEW(exportTagAdr, 32);
	InitHeap
END AosLinker0.

(*
19.05.98	pjm	Started
23.05.99	pjm	Fixed Find for non-sorted tables
*)

AosLinker0.Find 10A3C4H

AosLinker0.WriteLog

System.Free AosLinker AosLinker0 ~
