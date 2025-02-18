(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosLinker;	(* pjm *)

(* BootLinker for Aos - cf. AosLoader *)

IMPORT
	SYSTEM, AosOut := AosLinker0, AosHeap := AosLinker0, AosModules := AosLinker0, Files, 
	AosLinker0, Kernel, Texts, Oberon;

CONST
	Ok = 0;
	FileNotFound = 1;
	TagInvalid = 2;
	FileCorrupt = 3;
	FileTooShort = 4;
	IncompatibleImport = 5;
	
	MaxStructs = 1024;	(* maximum number of structures in export block *)

		(* object model exports *)
	EUEnd = 0;  EURecord = 1;  EUobjScope = 0;  EUrecScope = 1;  EUerrScope = -1;
	EUProcFlagBit = 31;
	
TYPE
	ObjHeader = RECORD (* data from object file header *)
		entries, commands, pointers, types, modules, links, dataLinks: LONGINT;
		codeSize, dataSize, refSize, constSize: LONGINT;
		name: AosModules.Name
	END;

	DataLinkRec = RECORD
		mod: LONGINT;
		entry: LONGINT;
		fixups: LONGINT;
		ofs: POINTER TO ARRAY OF LONGINT
	END;
	
	LinkRec = RECORD
		mod: LONGINT;
		entry: LONGINT;
		link: LONGINT
	END;
	
	TypeRec = RECORD
		init: BOOLEAN;
		desc[UNTRACED]: AosModules.TypeDesc;	(* .desc will point to pseudo-heap, and should not be traced *)
		entry, methods, inhMethods, baseMod, baseEntry: LONGINT
	END;
	
VAR
	trace: BOOLEAN;
	
(* ReadHeader - Read object file header. *)

PROCEDURE ReadHeader(VAR r: Files.Rider;  VAR h: ObjHeader;  VAR res: LONGINT);
VAR symSize: LONGINT;  int: INTEGER;  tag: CHAR;
BEGIN
	Files.Read(r, tag);
	IF tag = 0BBX THEN
		Files.Read(r, tag);
		IF tag = 0ADX THEN Files.Read(r, tag) END;	(* no zero compression in symbol file *)
		IF (tag = 0AFX) OR (tag = 0B0X) THEN
			Files.ReadNum(r, symSize);
			Files.Set(r, Files.Base(r), Files.Pos(r) + symSize);	(* skip symbols *)
			Files.ReadLInt(r, h.refSize);
			Files.ReadInt(r, int);  h.entries := int;
			Files.ReadInt(r, int);  h.commands := int;
			Files.ReadInt(r, int);  h.pointers := int;
			Files.ReadInt(r, int);  h.types := int;
			Files.ReadInt(r, int);  h.modules := int;
			Files.ReadInt(r, int);  h.dataLinks := int;
			Files.ReadInt(r, int);  h.links := int;
			Files.ReadLInt(r, h.dataSize);
			Files.ReadInt(r, int);  h.constSize := LONG(int) MOD 10000H;
			Files.ReadInt(r, int);  h.codeSize := LONG(int) MOD 10000H;
			Files.ReadString(r, h.name);
			IF trace THEN
				AosOut.String("  name: ");  AosOut.String(h.name);
				AosOut.String("  symSize: ");  AosOut.Int(symSize, 1);
				AosOut.String("  refSize: ");  AosOut.Int(h.refSize, 1);
				AosOut.String("  dataSize: ");  AosOut.Int(h.dataSize, 1);
				AosOut.String("  constSize: ");  AosOut.Int(h.constSize, 1);
				AosOut.String("  codeSize: ");  AosOut.Int(h.codeSize, 1);   AosOut.Ln;
				AosOut.String("  entries: ");  AosOut.Int(h.entries, 1);
				AosOut.String("  commands: ");  AosOut.Int(h.commands, 1);
				AosOut.String("  pointers: ");  AosOut.Int(h.pointers, 1);
				AosOut.String("  types: ");  AosOut.Int(h.types, 1);
				AosOut.String("  modules: ");  AosOut.Int(h.modules, 1);
				AosOut.String("  dataLinks: ");  AosOut.Int(h.dataLinks, 1);
				AosOut.String("  links: ");  AosOut.Int(h.links, 1);  AosOut.Ln
			END;
			IF r.eof THEN res := FileTooShort END
		ELSE
			res := TagInvalid
		END
	ELSE
		res := TagInvalid
	END
END ReadHeader;

(* ReadString7 - Read 7-bit encoded string. *)

PROCEDURE ReadString7(VAR r: Files.Rider;  VAR str: ARRAY OF CHAR);
VAR i: LONGINT;  ch: CHAR;
BEGIN
	i := 0;  Files.Read(r, ch);
	WHILE ch # 0X DO
		IF ch > 7FX THEN str[i] := CHR(ORD(ch)-80H);  INC(i);  ch := 0X
		ELSE str[i] := ch;  INC(i);  Files.Read(r, ch)
		END
	END;
	str[i] := 0X
END ReadString7;

(* zero compressed strings don't like UTF-8 encoding *)

PROCEDURE ReadString8(VAR r: Files.Rider;  VAR str: ARRAY OF CHAR);
VAR i: LONGINT;  ch: CHAR;
BEGIN
	i := 0;
	Files.Read(r, ch);
	WHILE ch # 0X DO
		str[i] := ch; INC(i);
		Files.Read(r, ch);
	END;
	str[i] := 0X;
END ReadString8;

(* AllocateModule - Allocate module data. *)

PROCEDURE AllocateModule(m: AosModules.Module);
CONST
	ArrHdrSize = 16;	(* {MOD 8 = 0} *)
	LenOfs = 12;	(* offset of dimension 0 in array header *)
	Align = ArrHdrSize + 4 + 15;	(* 4 for tag of next block, 15 for rounding up to 16 *)
	
VAR
	adr, size, tag, dataSize: LONGINT;  block: SYSTEM.PTR;
	
	PROCEDURE ArrSize(elements, elemSize: LONGINT): LONGINT;
	BEGIN
		RETURN (elements*elemSize + Align) DIV 16 * 16	(* size rounded up for header and alignment *)
	END ArrSize;
	
	PROCEDURE NewArr(VAR ptr: SYSTEM.PTR;  elements, elemSize: LONGINT);
	VAR a, s: LONGINT;
	BEGIN
		ASSERT(adr MOD 16 = 8);	(* => adr MOD 8 = 0 *)
		a := adr;  s := ArrSize(elements, elemSize);
		INC(adr, s);  DEC(size, s);	(* allocate *)
			(* array header *)
		SYSTEM.PUT(a-4, tag);	(* indirect tag *)
		SYSTEM.PUT(a+LenOfs, elements);	(* dimension *)
		ptr := SYSTEM.VAL(SYSTEM.PTR, a)
	END NewArr;
	
BEGIN
	dataSize := m.dataSize + (-m.dataSize) MOD 8;	(* round up to 8 to align constant block *)
	
	size := ArrSize(m.entries, SIZE(LONGINT)) + ArrSize(m.commands, SIZE(AosModules.Command)) + 
		ArrSize(m.pointers, SIZE(LONGINT)) + ArrSize(m.types, SIZE(LONGINT)) + 
		ArrSize(m.modules, SIZE(AosModules.Module)) + ArrSize(dataSize + m.constSize, 1) + 
		ArrSize(m.codeSize, 1) + ArrSize(m.refSize, 1);

	AosHeap.NewSys(block, size);
	adr := SYSTEM.VAL(LONGINT, block);
	SYSTEM.GET(adr-4, tag);
	
	NewArr(SYSTEM.VAL(PTR, m.entry), m.entries, SIZE(LONGINT));
	NewArr(SYSTEM.VAL(PTR, m.command), m.commands, SIZE(AosModules.Command));
	NewArr(SYSTEM.VAL(PTR, m.ptrAdr), m.pointers, SIZE(LONGINT));
	NewArr(SYSTEM.VAL(PTR, m.type), m.types, SIZE(LONGINT));
	NewArr(SYSTEM.VAL(PTR, m.module), m.modules, SIZE(AosModules.Module));
	NewArr(SYSTEM.VAL(PTR, m.data), dataSize + m.constSize, 1);
	NewArr(SYSTEM.VAL(PTR, m.code), m.codeSize, 1);
	NewArr(SYSTEM.VAL(PTR, m.refs), m.refSize, 1);
	
	ASSERT(size = 0);	(* account for every byte *)
	
	m.sb := SYSTEM.ADR(m.data[0]) + dataSize	(* constants positive, data negative *)
END AllocateModule;

(* ReadEntryBlock - Read the entry block. *)

PROCEDURE ReadEntryBlock(VAR r: Files.Rider;  m: AosModules.Module): BOOLEAN;
VAR tag: CHAR;  i: LONGINT;  int: INTEGER;
BEGIN
	Files.Read(r, tag);
	IF tag = 82X THEN	(* entry tag *)
		FOR i := 0 TO m.entries-1 DO
			Files.ReadInt(r, int);
			m.entry[i] := LONG(int) MOD 10000H + SYSTEM.ADR(m.code[0])
		END;
		(*ASSERT((m.entries > 0) & (m.entry[0] = SYSTEM.ADR(m.code[0])));*)	(* entry[0] is beginning of code (cf. OPL.Init) *)
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadEntryBlock;

(* ReadCommandBlock - Read the command block. *)

PROCEDURE ReadCommandBlock(VAR r: Files.Rider;  m: AosModules.Module): BOOLEAN;
VAR tag: CHAR; i, j, adr: LONGINT; int: INTEGER; name: AosModules.Name;
BEGIN
	Files.Read(r, tag);
	IF tag = 83X THEN	(* command tag *)
		FOR i := 0 TO m.commands-1 DO
			Files.ReadString(r, name);
			Files.ReadInt(r, int);
			adr := LONG(int) MOD 10000H + SYSTEM.ADR(m.code[0]);
			IF name[0] # "$" THEN	(* old-style command without parameter *)
				m.command[i].name := name;
				m.command[i].proc := SYSTEM.VAL(AosModules.CommandProc, adr);
				m.command[i].parproc := NIL
			ELSE	(* new-style command with parameter and return value *)
				j := 0; REPEAT INC(j); m.command[i].name[j-1] := name[j] UNTIL name[j] = 0X;	(* strip "$" *)
				m.command[i].proc := NIL;
				m.command[i].parproc := SYSTEM.VAL(AosModules.CommandParProc, adr)
			END
		END;
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadCommandBlock;

(* ReadPointerBlock - Read the pointer block. *)

PROCEDURE ReadPointerBlock(VAR r: Files.Rider;  m: AosModules.Module): BOOLEAN;
VAR tag: CHAR;  i, p: LONGINT;
BEGIN
	Files.Read(r, tag);
	IF tag = 84X THEN	(* pointer tag *)
		FOR i := 0 TO m.pointers-1 DO
			Files.ReadLInt(r, p);
			ASSERT(p MOD 4 = 0);	(* no deep copy flag *)
			m.ptrAdr[i] := m.sb + p
		END;
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadPointerBlock;

(* ReadImportBlock - Read the import block. *)

PROCEDURE ReadImportBlock(VAR r: Files.Rider;  m: AosModules.Module;  VAR res: LONGINT;  
		VAR msg: ARRAY OF CHAR): BOOLEAN;
VAR tag: CHAR;  i: LONGINT;  name: AosModules.Name;
BEGIN
	Files.Read(r, tag);
	IF tag = 85X THEN	(* import tag *)
		i := 0;
		WHILE (i # m.modules) & (res = Ok) DO
			ReadString8(r, name);
			m.module[i] := AosModules.ThisModule(name, res, msg);	(* recursively load the imported module *)
			INC(i)
		END
	ELSE
		res := FileCorrupt
	END;
	RETURN res = Ok
END ReadImportBlock;

(* ReadDataLinkBlock - Read the data links block. *)

PROCEDURE ReadDataLinkBlock(VAR r: Files.Rider;  dataLinks: LONGINT;  VAR d: ARRAY OF DataLinkRec): BOOLEAN;
VAR tag: CHAR;  i, j: LONGINT;  int: INTEGER;
BEGIN
	Files.Read(r, tag);
	IF tag = 8DX THEN	(* data links tag *)
		FOR i := 0 TO dataLinks-1 DO
			Files.Read(r, tag);  d[i].mod := ORD(tag);
			Files.ReadInt(r, int);  d[i].entry := int;
			Files.ReadInt(r, int);  d[i].fixups := int;
			IF d[i].fixups > 0 THEN
				NEW(d[i].ofs, d[i].fixups);
				FOR j := 0 TO d[i].fixups-1 DO
					Files.ReadInt(r, int);  d[i].ofs[j] := LONG(int) MOD 10000H
				END
			ELSE
				d[i].ofs := NIL
			END
		END;
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadDataLinkBlock;

(* ReadLinkBlock - Read the link block. *)

PROCEDURE ReadLinkBlock(VAR r: Files.Rider;  links: LONGINT;  VAR l: ARRAY OF LinkRec): BOOLEAN;
VAR tag: CHAR;  i: LONGINT;  int: INTEGER;
BEGIN
	Files.Read(r, tag);
	IF tag = 86X THEN	(* links tag *)
		FOR i := 0 TO links-1 DO
			Files.Read(r, tag);  l[i].mod := ORD(tag);
			Files.Read(r, tag);  l[i].entry := ORD(tag);
			Files.ReadInt(r, int);  l[i].link := LONG(int) MOD 10000H
		END;
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadLinkBlock;

(* ReadConstBlock - Read the constant block. *)

PROCEDURE ReadConstBlock(VAR r: Files.Rider;  m: AosModules.Module): BOOLEAN;
VAR tag: CHAR;  i, t: LONGINT;
BEGIN
	Files.Read(r, tag);
	IF tag = 87X THEN	(* constant tag *)
		t := m.sb;
		FOR i := 0 TO m.constSize-1 DO
			Files.Read(r, tag);  SYSTEM.PUT(t, tag);  INC(t)
		END;
		SYSTEM.GET(m.sb, t);  ASSERT(t = 0);
		SYSTEM.PUT(m.sb, m);	(* SELF *)
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadConstBlock;

(* ReadExportBlock - Read the export block. *)

PROCEDURE ReadExportBlock(VAR r: Files.Rider;  m: AosModules.Module): BOOLEAN;
TYPE ExportPtr = POINTER TO AosModules.ExportDesc;
VAR tag: CHAR;  structs: LONGINT;  struct: ARRAY MaxStructs OF ExportPtr;	(* rewrite struct without ptr *)

	PROCEDURE LoadScope(VAR scope: AosModules.ExportDesc;  level, adr: LONGINT);
	VAR no1, no2, fp, off: LONGINT;  int: INTEGER;
	BEGIN
		Files.ReadInt(r, int);  scope.exports := int;
		no1 := 0;  no2 := 0;
		IF scope.exports # 0 THEN
			(*NEW(scope.dsc, scope.exports);*)
			AosLinker0.NewExportDesc(scope.dsc, scope.exports);
			scope.dsc[0].adr := adr
		END;
		IF level = EUrecScope THEN
			INC(structs);  struct[structs] := SYSTEM.VAL(ExportPtr, SYSTEM.ADR(scope))
		END;
		Files.ReadNum(r, fp);
		WHILE fp # EUEnd DO
			IF fp = EURecord THEN
				Files.ReadNum(r, off);
				IF off < 0 THEN
					scope.dsc[no2].exports := struct[-off].exports;
					scope.dsc[no2].dsc := struct[-off].dsc	(* old type *)
				ELSE
					LoadScope(scope.dsc[no2], EUrecScope, off)
				END
			ELSE 
				IF level = EUobjScope THEN Files.ReadNum(r, scope.dsc[no1].adr) END;
				scope.dsc[no1].fp := fp;  no2 := no1;  INC(no1)
			END;
			Files.ReadNum(r, fp)
		END
	END LoadScope;

BEGIN
	Files.Read(r, tag);
	IF tag = 88X THEN	(* export tag *)
		structs := 0;
		LoadScope(m.export, EUobjScope, 0);
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadExportBlock;

(* ReadCodeBlock - Read the code block. *)

PROCEDURE ReadCodeBlock(VAR r: Files.Rider;  m: AosModules.Module): BOOLEAN;
VAR tag: CHAR;
BEGIN
	Files.Read(r, tag);
	IF tag = 89X THEN	(* code tag *)
		Files.ReadBytes(r, m.code^, m.codeSize);
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadCodeBlock;

(* ReadUseBlock - Read and check the use block. *)

PROCEDURE ReadUseBlock(VAR r: Files.Rider;  m: AosModules.Module;  VAR dataLink: ARRAY OF DataLinkRec;  
		VAR res: LONGINT;  VAR msg: ARRAY OF CHAR): BOOLEAN;
VAR tag: CHAR;  i: LONGINT;  name, prevname: AosModules.Name;  mod: AosModules.Module;

	PROCEDURE Err;
	BEGIN	
		IF res = Ok THEN
			res := IncompatibleImport;
			COPY(m.name, msg);  AosModules.Append(" incompatible with ", msg);  AosModules.Append(mod.name, msg);
		END
	END Err;

	PROCEDURE FixupCall(code, link, fixval: LONGINT);
	VAR instr, nextlink: LONGINT;  opcode: CHAR;
	BEGIN
		REPEAT
			SYSTEM.GET(code + link, instr);
			nextlink := SYSTEM.LSH(instr, -16);
			SYSTEM.GET(code + link - 1, opcode);	(* backward disassembly safe? *)
			IF opcode = 0E8X THEN	(* call instruction relative *)
				SYSTEM.PUT(code + link, fixval - (code + link + 4)) (* + 4: to next instruction *)
				(* relative, no further fixup required *)
			ELSE	(* move instruction absolute *)
				SYSTEM.PUT(code + link, fixval);
				AosLinker0.Relocate(code + link)
			END;
			link := nextlink
		UNTIL link = 0FFFFH
	END FixupCall;
	
	PROCEDURE FixupVar(code, link, fixval: LONGINT);
	VAR i, val, adr: LONGINT;
	BEGIN
		ASSERT(dataLink[link].mod # 0);	(* this must be non-local module (?) *)
		FOR i := 0 TO dataLink[link].fixups-1 DO
			adr := code + dataLink[link].ofs[i];
			SYSTEM.GET(adr, val);	(* non-zero for example with constant index into imported array *)
			SYSTEM.PUT(adr, val + fixval);
			AosLinker0.Relocate(adr)
		END
	END FixupVar;
	
	PROCEDURE CheckScope(scope: AosModules.ExportDesc;  level: LONGINT);
	VAR fp, link, i, adr, tdadr: LONGINT;  tmpErr: BOOLEAN;
	BEGIN
		tmpErr := (level = EUerrScope);
		i := 0;  link := 0;
		Files.ReadNum(r, fp);
		WHILE fp # EUEnd DO
			IF fp = EURecord THEN
				Files.ReadNum(r, link);
				IF tmpErr THEN
					CheckScope(scope.dsc[i], EUerrScope)
				ELSE
					IF scope.dsc[i].dsc # NIL THEN
						IF link # 0 THEN
							adr := scope.dsc[i].dsc[0].adr;
							SYSTEM.GET(mod.sb + adr, tdadr);
							SYSTEM.PUT(m.sb-link, tdadr);	(* tdadr at tadr[0] *)
							AosLinker0.Relocate(m.sb-link)
						END
					END;
					CheckScope(scope.dsc[i], EUrecScope)
				END
			ELSE
				prevname := name; ReadString8(r, name);
				IF level >= EUobjScope THEN
					tmpErr := FALSE;
					IF level = EUobjScope THEN Files.ReadNum(r, link) END;
					i := 0;  WHILE (i < scope.exports) & (scope.dsc[i].fp # fp) DO INC(i) END;
					IF i >= scope.exports THEN
						Err;  tmpErr := TRUE;  AosModules.Append("/", msg);
						IF name = "@" THEN AosModules.Append(prevname, msg)
						ELSE AosModules.Append(name, msg)
						END;
						DEC(i)
					ELSIF (level = EUobjScope) & (link # 0) THEN
						IF ~(EUProcFlagBit IN SYSTEM.VAL(SET, link)) THEN
							FixupVar(SYSTEM.ADR(m.code[0]), link, mod.sb + scope.dsc[i].adr)
						ELSE
							FixupCall(SYSTEM.ADR(m.code[0]), SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, link) - {EUProcFlagBit}), 
								scope.dsc[i].adr + SYSTEM.ADR(mod.code[0]))
						END
					END
				END
			END;
			Files.ReadNum(r, fp)
		END
	END CheckScope;

BEGIN
	Files.Read(r, tag);
	IF tag = 8AX THEN	(* use tag *)
		i := 0;
		ReadString8(r, name);
		WHILE (name # "") & (res = Ok) DO
			mod := AosModules.ThisModule(name, res, msg);
			IF res = Ok THEN
				CheckScope(mod.export, EUobjScope)
			END;
			ReadString8(r, name);
		END
	ELSE
		res := FileCorrupt
	END;
	RETURN res = Ok
END ReadUseBlock;

(* ReadTypeBlock - Read the type block. *)

PROCEDURE ReadTypeBlock(VAR r: Files.Rider;  m: AosModules.Module;  VAR type: ARRAY OF TypeRec): BOOLEAN;
VAR
	tag: CHAR;  i, j, recSize, newMethods, pointers, method, entry, ofs, base: LONGINT;
	int: INTEGER;  name: AosModules.Name;  flags: SET;
BEGIN
	Files.Read(r, tag);
	IF tag = 8BX THEN	(* type tag *)
		FOR i := 0 TO m.types-1 DO
			type[i].init := FALSE;
			Files.ReadLInt(r, recSize);
			Files.ReadInt(r, int);  type[i].entry := int;
			Files.ReadInt(r, int);  type[i].baseMod := int;
			Files.ReadLInt(r, type[i].baseEntry);
			Files.ReadInt(r, int);  type[i].methods := int;
			IF int = 0 THEN flags := {}	(* unprotected type *)
			ELSE flags := {AosHeap.ProtTypeBit}	(* protected type *)
			END;
			Files.ReadInt(r, int);  type[i].inhMethods := int;
			Files.ReadInt(r, int);  newMethods := int;
			Files.ReadInt(r, int);  pointers := int;
			Files.ReadString(r, name);
			AosHeap.NewType(SYSTEM.VAL(PTR, type[i].desc), recSize, pointers, 
					AosModules.MaxTags + type[i].methods, name, m, flags);
			ASSERT(SYSTEM.VAL(LONGINT, type[i].desc) MOD 32 = 0);
			base := SYSTEM.VAL(LONGINT, type[i].desc.tag) + AosModules.Mth0Ofs;	(* read new methods *)
			FOR j := 0 TO newMethods-1 DO
				Files.ReadInt(r, int);  method := int;
				Files.ReadInt(r, int);  entry := int;
				SYSTEM.PUT(base - 4*method, m.entry[entry]);
				AosLinker0.Relocate(base - 4*method)
			END;
			(* other methods are left NIL *)
			base := SYSTEM.VAL(LONGINT, type[i].desc.tag) + AosModules.Ptr0Ofs;	(* read pointers *)
			FOR j := 0 TO pointers-1 DO
				Files.ReadLInt(r, ofs);
				ASSERT(ofs MOD 4 = 0);	(* no deep copy flag *);
				SYSTEM.PUT(base, ofs);  INC(base, 4)
			END;
			SYSTEM.PUT(m.sb + type[i].entry, type[i].desc.tag);	(* patch in constant area *)
			AosLinker0.Relocate(m.sb + type[i].entry);
			m.type[i] := type[i].desc.tag	(* enter type descriptor in module *)
		END;
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadTypeBlock;

(* ReadRefBlock - Read the reference block. *)

PROCEDURE ReadRefBlock(VAR r: Files.Rider;  m: AosModules.Module): BOOLEAN;
VAR tag: CHAR;
BEGIN
	Files.Read(r, tag);
	IF tag = 8CX THEN	(* ref tag *)
		Files.ReadBytes(r, m.refs^, m.refSize);
		RETURN TRUE
	ELSE
		RETURN FALSE
	END
END ReadRefBlock;

(* FixupGlobals - Fix up references to global variables. *)

PROCEDURE FixupGlobals(m: AosModules.Module;  VAR dataLink: ARRAY OF DataLinkRec);
VAR i, t, adr: LONGINT;
BEGIN
	IF dataLink[0].mod = 0 THEN	(* local module has globals *)
		FOR i := 0 TO dataLink[0].fixups-1 DO
			adr := SYSTEM.ADR(m.code[0]) + dataLink[0].ofs[i];
			SYSTEM.GET(adr, t);  SYSTEM.PUT(adr, t + m.sb);
			AosLinker0.Relocate(adr)
		END
	END
END FixupGlobals;

(* FixupLinks - Fix up other references. *)

PROCEDURE FixupLinks(m: AosModules.Module;  VAR link: ARRAY OF LinkRec;  VAR res: LONGINT);
VAR i, entry: LONGINT;

	PROCEDURE FixRelative(ofs, val: LONGINT);
	VAR t, adr: LONGINT;
	BEGIN
		ASSERT(val # 0);
		WHILE ofs # 0FFFFH DO
			adr := SYSTEM.ADR(m.code[0])+ofs;
			SYSTEM.GET(adr, t);
			SYSTEM.PUT(adr, val - (adr+4));	(* relative => no relocation required *)
			(*AosOut.String("FixRelative"); AosOut.Hex(ofs, 9); AosOut.Hex(val, 9); AosOut.Ln;*)
			ofs := SYSTEM.LSH(t, -16)
		END
	END FixRelative;
	
	PROCEDURE FixEntry(ofs: LONGINT);
	VAR t, adr: LONGINT;
	BEGIN
		WHILE ofs # 0FFFFH DO
			adr := SYSTEM.ADR(m.code[0])+ofs;
			SYSTEM.GET(adr, t);
			SYSTEM.PUT(adr, m.entry[t MOD 10000H]);
			AosLinker0.Relocate(adr);
			ofs := SYSTEM.LSH(t, -16)
		END
	END FixEntry;
	
	PROCEDURE FixCase(ofs: LONGINT);
	VAR t, adr: LONGINT;
	BEGIN
		WHILE ofs # 0FFFFH DO
			adr := m.sb+ofs;
			SYSTEM.GET(adr, t);
			SYSTEM.PUT(adr, SYSTEM.ADR(m.code[0]) + t MOD 10000H);
			AosLinker0.Relocate(adr);
			ofs := SYSTEM.LSH(t, -16)
		END
	END FixCase;

BEGIN
	FOR i := 0 TO LEN(link)-1 DO
		ASSERT(link[i].mod = 0);	(* only fix local things *)
		(*AosOut.Int(link[i].entry, 1); AosOut.Char(" ");*)
		CASE link[i].entry OF
			244..253: FixRelative(link[i].link, AosModules.GetKernelProc(m, link[i].entry))
			|254: FixEntry(link[i].link)	(* local procedure address *)
			|255: FixCase(link[i].link)	(* case table *)
			ELSE res := 3406; RETURN	(* unknown fixup type *)
		END
	END
END FixupLinks;

(* InitType - Initialize a type. *)

PROCEDURE InitType(m: AosModules.Module;  VAR type: ARRAY OF TypeRec;  i: LONGINT);
VAR j, t, root, baseMod, baseTag, baseMth, extLevel, baseRoot: LONGINT;  baseM: AosModules.Module;
BEGIN
	IF ~type[i].init THEN
		root := SYSTEM.VAL(LONGINT, type[i].desc.tag);
		baseTag := root + AosModules.Tag0Ofs;
		baseMth := root + AosModules.Mth0Ofs;
		baseMod := type[i].baseMod;  extLevel := 0;
		ASSERT(baseMod >= -1);
		IF baseMod # -1 THEN	(* extended type *)
			IF baseMod = 0 THEN	(* base type local *)
				j := 0;  WHILE type[j].entry # type[i].baseEntry DO INC(j) END;	(* find base type *)
				InitType(m, type, j);	(* and initialize it first *)
				baseM := m
			ELSE	(* base type imported *)
				baseM := m.module[baseMod-1];
				t := type[i].baseEntry;	(* fingerprint *)
				j := 0;  WHILE baseM.export.dsc[j].fp # t DO INC(j) END;	(* find base type *)
				type[i].baseEntry := baseM.export.dsc[j].dsc[0].adr
			END;
				(* copy base tags *)
			SYSTEM.GET(baseM.sb + type[i].baseEntry, baseRoot);
			SYSTEM.GET(baseRoot + AosModules.Tag0Ofs, t);
			WHILE t # 0 DO
				SYSTEM.PUT(baseTag - 4*extLevel, t);
				AosLinker0.Relocate(baseTag - 4*extLevel);
				INC(extLevel);
				SYSTEM.GET(baseRoot + AosModules.Tag0Ofs - 4*extLevel, t)
			END;
				(* copy non-overwritten base methods *)
			FOR j := 0 TO type[i].inhMethods-1 DO
				SYSTEM.GET(baseMth - 4*j, t);	(* existing method *)
				IF t = 0 THEN
					SYSTEM.GET(baseRoot + AosModules.Mth0Ofs - 4*j, t);	(* base method *)
					SYSTEM.PUT(baseMth - 4*j, t);
					AosLinker0.Relocate(baseMth - 4*j)
				END
			END
		END;
		type[i].desc.flags := type[i].desc.flags + SYSTEM.VAL(SET, extLevel);
		ASSERT(extLevel < AosModules.MaxTags);
(*
		IF AosModules.ProtTypeBit IN type[i].desc.flags THEN
			AosOut.String("Protected: ");  AosOut.String(type[i].desc.mod.name);
			AosOut.Char(".");  AosOut.String(type[i].desc.name);  AosOut.Ln
		END;
*)
		SYSTEM.PUT(baseTag - 4*extLevel, type[i].desc.tag);	(* self *)
		AosLinker0.Relocate(baseTag - 4*extLevel);
(*
		;
		AosOut.String(type[i].desc.name);  AosOut.Ln;
		j := SYSTEM.VAL(LONGINT, type[i].desc.tag)+4;
		REPEAT
			SYSTEM.GET(j, t);
			INC(j, 4);
		UNTIL t < 0;
		AosOut.Memory(SYSTEM.VAL(LONGINT, type[i].desc), j - SYSTEM.VAL(LONGINT, type[i].desc));
*)
		type[i].init := TRUE
	END
END InitType;

(** LoadObj - Load an Active Oberon object file. *)

PROCEDURE LoadObj*(name, fileName: ARRAY OF CHAR;  VAR res: LONGINT;  VAR msg: ARRAY OF CHAR): AosModules.Module;
VAR
	f: Files.File;  r: Files.Rider;  h: ObjHeader;  m: AosModules.Module;  i: LONGINT;
	dataLink: POINTER TO ARRAY OF DataLinkRec;
	link: POINTER TO ARRAY OF LinkRec;
	type: POINTER TO ARRAY OF TypeRec;
BEGIN
	f := Files.Old(fileName);
	IF f # NIL THEN
		IF trace THEN AosOut.String("Loading ");  AosOut.String(fileName);  AosOut.Ln END;
		Files.Set(r, f, 0);  res := Ok;  msg[0] := 0X;
		ReadHeader(r, h, res);
		IF res = Ok THEN
			ASSERT(h.name = name);
			(*NEW(m);*)
			AosLinker0.NewModule(m);
			i := 0;  WHILE h.name[i] # 0X DO m.name[i] := h.name[i];  INC(i) END;
			m.name[i] := 0X;
			m.refSize := h.refSize;  m.entries := h.entries;  m.commands := h.commands;
			m.pointers := h.pointers;  m.types := h.types;  m.modules := h.modules;
			m.dataSize := h.dataSize;  m.constSize := h.constSize;  m.codeSize := h.codeSize;
			AllocateModule(m);
			IF trace THEN
				AosOut.Hex(SYSTEM.ADR(m.code[0]), 8);  AosOut.Char(" ");
				AosOut.String(m.name);  AosOut.Hex(m.sb, 9);  AosOut.Ln
			END;
			NEW(dataLink, h.dataLinks);  NEW(link, h.links);  NEW(type, m.types);
			IF ReadEntryBlock(r, m) & ReadCommandBlock(r, m) & ReadPointerBlock(r, m) & 
					ReadImportBlock(r, m, res, msg) & ReadDataLinkBlock(r, h.dataLinks, dataLink^) & 
					ReadLinkBlock(r, h.links, link^) & ReadConstBlock(r, m) & ReadExportBlock(r, m) & 
					ReadCodeBlock(r, m) & ReadUseBlock(r, m, dataLink^, res, msg) & 
					ReadTypeBlock(r, m, type^) & ReadRefBlock(r, m) THEN
				IF h.dataLinks # 0 THEN FixupGlobals(m, dataLink^) END;
				IF h.links # 0 THEN FixupLinks(m, link^, res) END;
				IF res = Ok THEN
					FOR i := 0 TO LEN(type^)-1 DO InitType(m, type^, i) END
				END
			ELSE
				IF res = Ok THEN res := FileCorrupt END
			END;
			dataLink := NIL;  link := NIL;  type := NIL
		END;
		IF (res # Ok) & (msg[0] = 0X) THEN COPY(fileName, msg);  AosModules.Append(" corrupt", msg) END
	ELSE
		res := FileNotFound;  COPY(fileName, msg);  AosModules.Append(" not found", msg)
	END;
	IF res # Ok THEN m := NIL END;
	RETURN m
END LoadObj;

PROCEDURE Link*;	(** outFile [inPrefix] baseAdr [loadAdr] { module } *)
VAR
	s: Texts.Scanner;  m: AosModules.Module;  res, base, load: LONGINT;
	out, prefix: ARRAY 64 OF CHAR;  msg: ARRAY 256 OF CHAR;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF s.class = Texts.Name THEN
		COPY(s.s, out);  Texts.Scan(s);
		IF s.class IN {Texts.Name, Texts.String} THEN
			COPY(s.s, prefix); Texts.Scan(s)
		ELSE
			prefix := ""
		END;
		IF s.class = Texts.Int THEN
			base := s.i;  Texts.Scan(s);
			IF s.class = Texts.Int THEN load := s.i; Texts.Scan(s) ELSE load := base END;
			AosLinker0.Open(prefix, base);
			res := Ok;
			WHILE (s.class = Texts.Name) & (res = Ok) DO
				m := AosModules.ThisModule(s.s, res, msg);
				Texts.Scan(s)
			END;
			AosLinker0.Close(out, base, load, res, msg)
		END
	END
END Link;

BEGIN
	AosModules.loadObj := LoadObj;
	trace := TRUE
END AosLinker.

(*
20.05.98	pjm	Started
*)

System.Free AosLinker AosLinker0 ~
