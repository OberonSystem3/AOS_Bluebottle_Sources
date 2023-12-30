(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosInfo; (** AUTHOR "pjm"; PURPOSE "System information"; *)

(**
Aos system information commands.  All commands output to the Aos log.
	In Oberon, execute System.OpenKernelLog to see  the log, or use LogWindow.Open to open a log window.
*)

IMPORT AosCommands, AosIO, AosPlugins,
	SYSTEM, AosLocks, AosOut, AosMemory, AosHeap, AosModules, AosTrap, AosActive,
	Utilities;

CONST
	ArrayBit = 1; FreeBit = 2; SubObjBit = 3;
	BlockSize = AosHeap.BlockSize;
	Tab = 9X;

(** List all loaded modules. *)

PROCEDURE Modules*(par : PTR) : PTR;
VAR m : AosModules.Module;
BEGIN
	m := AosModules.root;
	WHILE m # NIL DO
		AosOut.String(m.name); (*AosOut.Int(m.refcnt, 4); AosOut.Ln;*)
		m := m.next;
		IF m # NIL THEN
			AosOut.String(", ")
		ELSE
			AosOut.Ln
		END;
		IF AosOut.column > 80 THEN AosOut.Ln END
	END;
	RETURN NIL
END Modules;

PROCEDURE WriteB(b : LONGINT);
VAR shift : LONGINT; suffix : ARRAY 2 OF CHAR;
BEGIN
	IF b < 100*1024 THEN suffix := ""; shift := 0
	ELSIF b < 100*1024*1024 THEN suffix := "K"; shift := -10
	ELSE suffix := "M"; shift := -20
	END;
	IF b # ASH(ASH(b, shift), -shift) THEN AosOut.Char("~") END;
	AosOut.Int(ASH(b, shift), 1);
	IF TRUE THEN
		AosOut.String(suffix); AosOut.Char("B")
	ELSE
		AosOut.Char(" ");
		AosOut.String(suffix);  AosOut.String("byte");
		IF b # 1 THEN AosOut.Char("s") END
	END
END WriteB;

(** List all loaded modules, with their sizes. *)

PROCEDURE ModuleSizes*(par : PTR) : PTR;
VAR m : AosModules.Module; tag, size, total, data, const, code, desc, mdescsize : LONGINT;
BEGIN
	mdescsize := SYSTEM.GET32(SYSTEM.TYPECODE(AosModules.Module));	(* get size of module descriptor *)
	AosOut.String("MODULE"); AosOut.Char(Tab);
	AosOut.String("SIZE"); AosOut.Char(Tab);
	AosOut.String("CODE"); AosOut.Char(Tab);
	AosOut.String("DATA"); AosOut.Char(Tab);
	AosOut.String("CONST"); AosOut.Char(Tab);
	AosOut.String("DESC"); AosOut.Ln; AosOut.Ln;
	m := AosModules.root;
	WHILE m # NIL DO
		AosOut.String(m.name);
			(* check if module descriptor has correct size (esp. statically linked modules) *)
		SYSTEM.GET(SYSTEM.VAL(LONGINT, m)-4, tag);
		SYSTEM.GET(tag, size);
		ASSERT(size = mdescsize);
			(* get module size *)
		SYSTEM.GET(SYSTEM.VAL(LONGINT, m.code)-4, tag);	(* indirect tag *)
		SYSTEM.GET(tag, size);
		AosOut.Char(Tab); AosOut.Int(size, 1);
		AosOut.Char(Tab); AosOut.Int(m.codeSize, 1);
		AosOut.Char(Tab); AosOut.Int(m.dataSize, 1);
		AosOut.Char(Tab); AosOut.Int(m.constSize, 1);
		AosOut.Char(Tab); AosOut.Int(size-(m.dataSize+m.constSize+m.codeSize), 1);
		INC(total, size);
		INC(data, m.dataSize); INC(const, m.constSize); INC(code, m.codeSize);
		INC(desc, size-(m.dataSize+m.constSize+m.codeSize));
		AosOut.Ln;
		m := m.next
	END;
	AosOut.Ln; AosOut.String("TOTAL");
	AosOut.Char(Tab); WriteB(total);
	AosOut.Char(Tab); WriteB(code);
	AosOut.Char(Tab); WriteB(data);
	AosOut.Char(Tab); WriteB(const);
	AosOut.Char(Tab); WriteB(desc);
	AosOut.Ln;
	RETURN NIL
END ModuleSizes;

(** Show the details of the specified module. *)

PROCEDURE ModuleDetails*(par : PTR) : PTR;	(** module *)
VAR
	m, n : AosModules.Module; i, j, p, k : LONGINT;
	t : AosModules.TypeDesc; writer : AosIO.Writer;
	modn : ARRAY 33 OF CHAR;
	sr : AosIO.StringReader;
BEGIN
	AosCommands.PosPar(par, sr);
	AosCommands.GetTok(sr, modn);
	m := AosModules.root;
	WHILE (m # NIL) & (m.name # modn) DO m := m.next END;
	IF m # NIL THEN
		AosIO.OpenWriter(writer, AosOut.Send);
		AosOut.String(m.name);
		AosOut.String(" refcnt = "); AosOut.Int(m.refcnt, 1);
		AosOut.String(" sb ="); AosOut.Hex(m.sb, 9);
		AosOut.String(" dataSize = "); AosOut.Int(m.dataSize, 1);
		AosOut.String(" constSize = "); AosOut.Int(m.constSize, 1);
		AosOut.String(" codeSize = "); AosOut.Int(m.codeSize, 1);
		AosOut.String(" refSize = "); AosOut.Int(m.refSize, 1);
		AosOut.String(" entries = "); AosOut.Int(m.entries, 1);
		AosOut.String(" commands = "); AosOut.Int(m.commands, 1);
		AosOut.String(" modules = "); AosOut.Int(m.modules, 1);
		AosOut.String(" types = "); AosOut.Int(m.types, 1);
		AosOut.String(" pointers = "); AosOut.Int(m.pointers, 1);
		AosOut.Ln; AosOut.String("  ptrAdr:");
		FOR i := 0 TO LEN(m.ptrAdr)-1 DO
			AosOut.Char(" "); AosOut.Int(m.ptrAdr[i]-m.sb, 1)
		END;
		AosOut.Ln; AosOut.String("  const:"); AosOut.Ln;
		AosOut.Memory(m.sb, m.constSize);
		FOR i := 0 TO LEN(m.type)-1 DO
			AosOut.Ln; AosOut.String("  type:");
			AosOut.Hex(SYSTEM.VAL(LONGINT, m.type[i]), 9);
			SYSTEM.GET(SYSTEM.VAL(LONGINT, m.type[i])-4, t);
			AosOut.Char(" "); AosOut.String(t.name);
			AosOut.Hex(SYSTEM.VAL(LONGINT, t.flags), 9);
				(* type descriptor info *)
			AosOut.Ln; AosOut.String("  typedesc1:");
			p := SYSTEM.VAL(LONGINT, t.tag);
			REPEAT
				SYSTEM.GET(p, k);
				IF ABS(k) <= 4096 THEN AosOut.Char(" "); AosOut.Int(k, 1)
				ELSE AosOut.Hex(k, 9)
				END;
				INC(p, 4)
			UNTIL k < -40000000H;
				(* methods *)
			AosOut.Ln; AosOut.String("  typedescmths:");
			p := SYSTEM.VAL(LONGINT, t.tag)-72; j := 0;
			REPEAT
				SYSTEM.GET(p, k);
				AosOut.Ln; AosOut.Int(j, 3); AosOut.Char(" ");
				n := AosModules.ThisModuleByAdr(k);
				IF n # NIL THEN
					AosTrap.WriteProc(writer, k); writer.Update
				ELSE
					AosOut.Hex(k, 8)
				END;
				DEC(p, 4); INC(j)
			UNTIL (j >= 8) & (n = NIL)
		END;
		AosOut.Ln
	END;
	RETURN NIL
END ModuleDetails;

(** Find a procedure, given the absolute PC address. *)

PROCEDURE ModulePC*(par : PTR) : PTR;	(** pc *)
VAR pc : LONGINT; writer : AosIO.Writer;
	sr : AosIO.StringReader;
BEGIN
	AosCommands.PosPar(par, sr);
	AosCommands.GetInt(sr, pc, FALSE);
	IF AosModules.ThisModuleByAdr(pc) # NIL THEN
		AosIO.OpenWriter(writer, AosOut.Send);
		AosTrap.WriteProc(writer, pc); writer.Update
	ELSE
		AosOut.Hex(pc, 8); AosOut.String(" not found")
	END;
	AosOut.Ln;
	RETURN NIL
END ModulePC;

PROCEDURE WriteType(adr : LONGINT);
VAR m : AosModules.Module;  t : AosModules.TypeDesc;
BEGIN
	AosModules.ThisTypeByAdr(adr - adr MOD 8, m, t);
	IF m # NIL THEN
		AosOut.String(m.name);  AosOut.Char(".");
		IF t.name = "" THEN AosOut.String("TYPE") ELSE AosOut.String(t.name) END
	ELSE
		AosOut.String("NIL")
	END
END WriteType;

(** List all loaded plugins. *)

PROCEDURE Plugins*(par : PTR) : PTR;
VAR r, p : AosPlugins.Table; i, j : LONGINT;
BEGIN
	AosPlugins.main.GetAll(r);
	IF r # NIL THEN
		FOR i := 0 TO LEN(r^)-1 DO
			AosOut.Int(i, 1); AosOut.Char(" ");
			AosOut.String(r[i].name); AosOut.Char(" ");
			AosOut.String(r[i].desc); AosOut.Ln;
			r[i](AosPlugins.Registry).GetAll(p);
			IF p # NIL THEN
				FOR j := 0 TO LEN(p^)-1 DO
					AosOut.Char(Tab); AosOut.Int(j, 1); AosOut.Char(" ");
					AosOut.String(p[j].name); AosOut.Char(" ");
					AosOut.String(p[j].desc); AosOut.Ln
				END
			END
		END
	END;
	RETURN NIL
END Plugins;

(** Show memory details. *)

PROCEDURE Memory*(par : PTR) : PTR;
VAR
	p, tag, size, t, blocks, low, high, total : LONGINT;
	recblks, sysblks, arrblks, typedescs, protrecblks, freeblks, unknowns : LONGINT;
	recblksize, sysblksize, arrblksize, typedescsize, protrecblksize, freeblksize, unknownsize, heapsize : LONGINT;
	flag : INTEGER;
BEGIN
	blocks := 0; recblks := 0; sysblks := 0; arrblks := 0;
	typedescs := 0; protrecblks := 0; freeblks := 0; unknowns := 0;
	recblksize := 0; sysblksize := 0; arrblksize := 0;
	typedescsize := 0; protrecblksize := 0; freeblksize := 0; unknownsize := 0;
	AosLocks.Acquire(AosLocks.AosHeap);
	p := AosHeap.beginBlockAdr;
	WHILE p # AosHeap.endBlockAdr DO
		INC(blocks);
		SYSTEM.GET(p, tag);
		SYSTEM.GET(tag - tag MOD 8, size);	(* record size, excluding tag *)
		IF FreeBit IN SYSTEM.VAL(SET, tag) THEN
			INC(freeblks); INC(freeblksize, size)
		ELSIF ArrayBit IN SYSTEM.VAL(SET, tag) THEN
			INC(arrblks); INC(arrblksize, size)
		ELSIF SubObjBit IN SYSTEM.VAL(SET, tag) THEN
			INC(recblks); INC(recblksize, size)
		ELSIF tag = p+4 THEN
			SYSTEM.GET(p+4+10, flag);
			IF flag = -1 THEN
				INC(protrecblks); INC(protrecblksize, size)
			ELSIF flag = 0 THEN
				INC(sysblks); INC(sysblksize, size)	(* or arrsysblks, or typedescs *)
			ELSE
				INC(typedescs); INC(typedescsize, size)
			END
		ELSE
			INC(unknowns); INC(unknownsize, size)
		END;
		IF ArrayBit IN SYSTEM.VAL(SET, tag) THEN
			SYSTEM.GET(p+4, t);	(* lastElemToMark *)
			size := t + size - p	(* size of array, including tag *)
		ELSE
			INC(size, 4)	(* include tag *)
		END;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));	(* round up *)
		INC(p, size)
	END;
	heapsize := AosHeap.endBlockAdr-AosHeap.beginBlockAdr;
	AosLocks.Release(AosLocks.AosHeap);
	AosMemory.GetFreeK(total, low, high);
	AosOut.Int(blocks, 1); AosOut.String(" blocks (");
	WriteB(heapsize); AosOut.String("), ");
	AosOut.Int(recblks, 1); AosOut.String(" recblks (");
	WriteB(recblksize); AosOut.String("), ");
	AosOut.Int(sysblks, 1); AosOut.String(" sysblks (");
	WriteB(sysblksize); AosOut.String("), ");
	AosOut.Ln;
	AosOut.Int(arrblks, 1); AosOut.String(" arrblks (");
	WriteB(arrblksize); AosOut.String("), ");
	AosOut.Int(protrecblks, 1); AosOut.String(" protrecblks (");
	WriteB(protrecblksize); AosOut.String("), ");
	AosOut.Int(typedescs, 1); AosOut.String(" typedescs (");
	WriteB(typedescsize); AosOut.String("), ");
	AosOut.Ln;
	AosOut.Int(freeblks, 1); AosOut.String(" freeblks (");
	WriteB(freeblksize); AosOut.String("), ");
	AosOut.Int(unknowns, 1); AosOut.String(" unknowns (");
	WriteB(unknownsize); AosOut.String("), ");
	WriteB(heapsize - (recblksize+sysblksize+arrblksize+protrecblksize+typedescsize+freeblksize+unknownsize));
	AosOut.String(" overhead, ");
	AosOut.Ln;
	WriteB(low*1024); AosOut.String(" low free, ");
	WriteB(high*1024); AosOut.String(" high free, ");
	WriteB(total*1024); AosOut.String(" total");
	AosOut.Ln;
	RETURN NIL
END Memory;

(** Show active and protected objects. *)

PROCEDURE Objects*(par : PTR) : PTR;
VAR
	p, tag, size, t, i, n, ptag : LONGINT;
	type : ARRAY 800 OF RECORD ptag, count, size : LONGINT END;
	flag : INTEGER;
BEGIN
	AosLocks.Acquire(AosLocks.AosHeap);
	p := AosHeap.beginBlockAdr; n := 0;
	WHILE p # AosHeap.endBlockAdr DO
		i := -1;
		SYSTEM.GET(p, tag);
		SYSTEM.GET(tag - tag MOD 8, size);	(* record size, excluding tag *)
		IF tag = p+4 THEN
			SYSTEM.GET(p+4+10, flag);
			IF flag = -1 THEN
				SYSTEM.GET(p+AosHeap.ProtOfs, ptag);
				i := 0; WHILE (i # n) & (type[i].ptag # ptag) DO INC(i) END;
				IF i = n THEN type[i].ptag := ptag; type[i].count := 1; INC(n) ELSE INC(type[i].count) END
			END
		END;
		IF ArrayBit IN SYSTEM.VAL(SET, tag) THEN
			SYSTEM.GET(p+4, t);	(* lastElemToMark *)
			size := t + size - p	(* size of array, including tag *)
		ELSE
			INC(size, 4)	(* include tag *)
		END;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));	(* round up *)
		IF i >= 0 THEN type[i].size := size END;
		INC(p, size)
	END;
	AosLocks.Release(AosLocks.AosHeap);
	t := 0;
	FOR i := 0 TO n-1 DO
		INC(t, type[i].count);
		AosOut.Int(type[i].count, 5); AosOut.Char(" ");
		WriteType(type[i].ptag); AosOut.String(" ("); WriteB(type[i].size); AosOut.String(" total ");
		WriteB(type[i].size * type[i].count); AosOut.String(")"); AosOut.Ln
	END;
	AosOut.Int(t, 1); AosOut.String(" objects of ");
	AosOut.Int(n, 1); AosOut.String(" unique types found");
	AosOut.Ln;
	RETURN NIL
END Objects;

(** Show active and protected objects. *)

(*
AosInfo.AllObjects PET.Window* ~
AosInfo.AllObjects * ~

*)

PROCEDURE AllObjects*(par : PTR) : PTR;
VAR
	p, tag, size, t, i, n, ptag : LONGINT;
	type : ARRAY 800 OF RECORD ptag, count, size : LONGINT END;
	flag : INTEGER;
	module : AosModules.Module;
	typedesc : AosModules.TypeDesc;
	mask, string : ARRAY 256 OF CHAR;
	sr : AosIO.StringReader;
BEGIN
	AosCommands.PosPar(par, sr);
	AosCommands.GetTok(sr, mask);

	AosLocks.Acquire(AosLocks.AosHeap);
	p := AosHeap.beginBlockAdr; n := 0;
	WHILE p # AosHeap.endBlockAdr DO
		i := -1;
		SYSTEM.GET(p, tag);
		SYSTEM.GET(tag - tag MOD 8, size);	(* record size, excluding tag *)
		IF n # LEN(type) THEN	(* space left *)
			IF tag = p+4 THEN	(* protrecblk, sysblk or typedesc *)
				SYSTEM.GET(p+4+10, flag);
				IF flag = -1 THEN
					SYSTEM.GET(p+AosHeap.ProtOfs, ptag);
					i := 0; WHILE (i # n) & (type[i].ptag # ptag) DO INC(i) END;
					IF i = n THEN type[i].ptag := ptag; type[i].count := 1; INC(n) ELSE INC(type[i].count) END
				END
			ELSIF tag MOD 16 IN {2, 8} THEN	(* recblk or arrblk *)
				i := 0; WHILE (i # n) & (type[i].ptag # tag) DO INC(i) END;
				IF i = n THEN type[i].ptag := tag; type[i].count := 1; INC(n) ELSE INC(type[i].count) END
			END
		END;
		IF ArrayBit IN SYSTEM.VAL(SET, tag) THEN
			SYSTEM.GET(p+4, t);	(* lastElemToMark *)
			size := t + size - p	(* size of array, including tag *)
		ELSE
			INC(size, 4)	(* include tag *)
		END;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));	(* round up *)
		IF i >= 0 THEN type[i].size := size END;
		INC(p, size)
	END;
	AosLocks.Release(AosLocks.AosHeap);
	AosOut.Char(0EX); (* non-proportional font *)

	FOR i := 0 TO n-1 DO
		INC(t, type[i].count);

		AosModules.ThisTypeByAdr(type[i].ptag - type[i].ptag MOD 8, module, typedesc);
		IF module # NIL THEN
			string := ""; Utilities.Append(string,  module.name); Utilities.Append(string, "."); Utilities.Append(string, typedesc.name);

			IF Utilities.Match(mask, string) THEN
				AosOut.Int(type[i].count, 8); AosOut.Char(" ");
				AosOut.Int(type[i].size, 6); AosOut.String("B ");
				AosOut.Int(type[i].size * type[i].count, 10); AosOut.String("B ");
				WriteType(type[i].ptag);
				AosOut.String(" (total ");
				WriteB(type[i].size * type[i].count); AosOut.String(")"); AosOut.Ln
			END;
		END;
	END;
	AosOut.Int(t, 1); AosOut.String(" dynamic records of ");
	AosOut.Int(n, 1); AosOut.String(" unique types found");
	AosOut.Ln;
	AosOut.Char(0FX); (* proportional font *)
	RETURN NIL
END AllObjects;

(*
info = "[" id mode process obj [ ":" type ] time eip [ optional ] "]" .
id = <process id> .
mode = "rdy" | "run" | "awl" | "awc" | "awe" | "rip" | "idl" .
process = <adr of process record> .
obj = <adr of object record> .
type = <type of object record> .
time = <time of last run> .
eip = <EIP hint> .
optional = awlinfo | awcinfo .
awlinfo = waitobj ("-" modulename | ":" typename ) .
awcinfo = conditionEIP condFP .
*)

PROCEDURE TraceProcess(p : AosActive.Process);
VAR adr : LONGINT; m : AosModules.Module;
BEGIN
	AosOut.Char(0EX); AosOut.Char("[");
	AosOut.Int(p.id, 3); AosOut.Char(" ");
	CASE p.mode OF
		| AosActive.Ready : AosOut.String("rdy")
		| AosActive.Running : AosOut.String("run")
		| AosActive.AwaitingLock : AosOut.String("awl")
		| AosActive.AwaitingCond : AosOut.String("awc")
		| AosActive.AwaitingEvent : AosOut.String("awe")
		| AosActive.Terminated : AosOut.String("rip")
		ELSE AosOut.Int(p.mode, 1)
	END;
	AosOut.Int(p.procID, 2); AosOut.Int(p.priority, 2);
	(*AosOut.Hex(SYSTEM.VAL(LONGINT, p), 9);*)
	AosOut.Hex(SYSTEM.VAL(LONGINT, p.obj), 9);
	IF p.obj # NIL THEN
		SYSTEM.GET(SYSTEM.VAL(LONGINT, p.obj)-4, adr);
		AosOut.Char(":"); AosHeap.WriteType(adr-adr MOD 8)
	END;
	AosOut.Hex(p.state.EIP, 9);	(* EIP hint *)
	IF p.mode = AosActive.AwaitingLock THEN
		adr := SYSTEM.VAL(LONGINT, p.waitingOn);
		AosOut.Hex(adr, 9);
		IF adr # 0 THEN	(* can be 0 when snapshot is taken *)
			SYSTEM.GET(adr-4, adr); DEC(adr, adr MOD 8);
			IF adr = SYSTEM.TYPECODE(AosModules.Module) THEN
				AosOut.Char("-");
				m := SYSTEM.VAL(AosModules.Module, adr);
				AosOut.String(m.name)
			ELSE
				AosOut.Char(":"); AosHeap.WriteType(adr)
			END
		END
	ELSIF p.mode = AosActive.AwaitingCond THEN
		AosOut.Hex(SYSTEM.VAL(LONGINT, p.condition), 9);
		AosOut.Hex(p.condFP, 9)
	END;
	AosOut.Char("]"); AosOut.Char(0FX); AosOut.Ln
END TraceProcess;

(** Show active object threads. *)

PROCEDURE Active*(par : PTR) : PTR;
VAR old : AosActive.TraceProcess;
BEGIN
	old := AosActive.traceProcess;
	AosActive.traceProcess := TraceProcess;	(* ignore race *)
	AosHeap.GC;
	AosActive.traceProcess := old;
	RETURN NIL
END Active;

(** Show commands of specified module. *)

PROCEDURE Commands*(par : PTR) : PTR;	(** module *)
VAR p : AosCommands.Parameters; m : AosModules.Module; i : LONGINT; msg : ARRAY 128 OF CHAR;
BEGIN
	p := par(AosCommands.Parameters);
	i := 0; WHILE (p.str[i] # 0X) & (p.str[i] # ".") DO INC(i); END; p.str[i] := 0X;
	m := AosModules.ModuleByName(p.str^);
	IF m # NIL THEN
		FOR i := 0 TO LEN(m.command)-1 DO
			AosOut.String(m.name); AosOut.Char(".");
			AosOut.String(m.command[i].name);
			AosOut.Ln
		END
	ELSE
		AosOut.String(msg); AosOut.Ln
	END;
	RETURN NIL
END Commands;

(*
(** Toggle the garbage collector on and off. *)

PROCEDURE ToggleGC*(par : PTR) : PTR;	(** for testing only *)
TYPE Node = POINTER TO RECORD next : Node; filler : ARRAY 1024 OF CHAR END;
VAR p, q : Node; i : LONGINT;
BEGIN
	IF AosHeap.gcEnabled THEN	(* make sure enough space is available *)
		q := NIL;
		FOR i := 1 TO 1024 DO NEW(p); p.next := q; q := p END;
		WHILE q # NIL DO
			p := q; q := q.next; p.next := NIL
		END;
		p := NIL; AosHeap.GC
	END;
	AosHeap.gcEnabled := ~AosHeap.gcEnabled;
	AosOut.Enter; AosOut.String("GC now ");
	IF AosHeap.gcEnabled THEN AosOut.String("on")
	ELSE AosOut.String("off")
	END;
	AosOut.Exit;
	RETURN NIL
END ToggleGC;
*)

(** Toggle thread tracing during garbage collection on and off. *)

PROCEDURE ToggleTrace*(par : PTR) : PTR;	(** for testing only *)
BEGIN
	IF AosActive.traceProcess = NIL THEN	(* ignore race *)
		AosActive.traceProcess := TraceProcess
	ELSE
		AosActive.traceProcess := NIL
	END;
	AosOut.Enter;
	AosOut.String("Process tracing now ");
	IF AosActive.traceProcess # NIL THEN AosOut.String("on")
	ELSE AosOut.String("off")
	END;
	AosOut.Exit;
	RETURN NIL
END ToggleTrace;

(*
(** Toggle HLT during idle on and off (for single-processor laptops). - No doHLT in AosActive.Mod *)

PROCEDURE SetHLT*(par : PTR) : PTR;	(** for testing only *)
VAR p : AosCommands.Parameters;
BEGIN
	p := par(AosCommands.Parameters);
	IF p.str[0] = "1" THEN
		AosActive.doHLT := TRUE
	ELSIF p.str[0] = "0" THEN
		AosActive.doHLT := FALSE
	ELSE
		AosActive.doHLT := ~AosActive.doHLT
	END;
	AosOut.Enter;
	AosOut.String("Idle HLT now ");
	IF AosActive.doHLT THEN AosOut.String("on")
	ELSE AosOut.String("off")
	END;
	AosOut.Exit;
	RETURN NIL
END SetHLT;
*)

END AosInfo.

(*
to do:
o module state
*)

S.Free AosInfo ~

AosInfo.Modules ~						(* List all loaded modules *)
AosInfo.ModuleDetails AosModules ~
AosInfo.ModuleSizes ~
AosInfo.Memory ~
AosInfo.Active ~							(* List active objects threads *)
AosInfo.Commands AosInfo.Mod ~		(* List commands of specified module - suffix .Obx or .Mod *)
AosInfo.Plugins ~
AosInfo.Objects ~						(* List active and protected objects *)
AosInfo.AllObjects AosInfo.Module* ~

WMModuleState.Open AosActive ~

AosInfo.ToggleGC ~
AosInfo.ToggleTrace ~