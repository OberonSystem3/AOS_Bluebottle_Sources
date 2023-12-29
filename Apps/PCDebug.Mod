(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE PCDebug; (** AUTHOR "prk"; PURPOSE "Parallel Compiler: low-level trace functions"; *)

	IMPORT
		AosOut, AosModules, SYSTEM;
	
	CONST
			(*ToDo classes*)
		NotImplemented* = 0;
		NotOptimized* = 1;
		
	TYPE
		List = POINTER TO RECORD	(* list of PC positions *)
			pc: LONGINT;
			next: List
		END;
		
	VAR
		pclist: List;			(* todo list *)
		Hex: ARRAY 17 OF CHAR;
		
	(* Read a compressed integer from memory *)

	PROCEDURE ReadNum (VAR pos: LONGINT; VAR i: LONGINT);
		VAR n: LONGINT; s: SHORTINT; x: CHAR;
	BEGIN
		s := 0; n := 0; SYSTEM.GET(pos, x); INC(pos);
		WHILE ORD(x) >= 128 DO INC(n, ASH(ORD(x) - 128, s)); INC(s, 7); SYSTEM.GET(pos, x); INC(pos) END;
		i := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64 * 64, s)
	END ReadNum;
	
	PROCEDURE WriteString*(str: ARRAY OF CHAR; VAR name: ARRAY OF CHAR; VAR pos: LONGINT);
	VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE (str[i] # 0X) & (pos < LEN(name)-1) DO
			name[pos] := str[i]; INC(i); INC(pos)
		END;
		name[pos] := 0X
	END WriteString;
	
	PROCEDURE WriteHex*(val: LONGINT; VAR name: ARRAY OF CHAR; VAR pos: LONGINT);
	VAR i: LONGINT;
	BEGIN
		INC(pos, 8); i := 1;
		WHILE i <= 8 DO
			IF (pos-i < LEN(name)-1) THEN name[pos-i] := Hex[val MOD 16] END;
			val := val DIV 16; INC(i)
		END;
		name[pos] := 0X
	END WriteHex;
	

	PROCEDURE GetProcedure*(pc: LONGINT; VAR name: ARRAY OF CHAR);
		VAR mod: AosModules.Module; refpos, limit: LONGINT; ch, ch0: CHAR; i, procstart, refstart: LONGINT;
	BEGIN
		i := 0;
		mod := AosModules.ThisModuleByAdr(pc);
		IF mod = NIL THEN
			WriteString("NIL  PC = ", name, i); WriteHex(pc, name, i)
		ELSE
			WriteString(mod.name, name, i); WriteString(".", name, i);
			IF (SYSTEM.VAL(LONGINT, mod.refs) # 0) & (LEN(mod.refs) # 0) THEN
				refstart := 0;  refpos := SYSTEM.ADR(mod.refs[0]);
				limit := refpos + LEN(mod.refs);
				LOOP
					SYSTEM.GET(refpos, ch); INC(refpos);
					IF refpos >= limit THEN EXIT END;
					IF ch = 0F8X THEN (* start proc *)
						ReadNum(refpos, procstart);
						IF pc < SYSTEM.ADR(mod.code[0]) + procstart THEN EXIT END;
						refstart := refpos;
						REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
					ELSIF ch = 0F9X THEN (*proc, new format*)
						ReadNum(refpos, procstart);
						IF pc < SYSTEM.ADR(mod.code[0]) + procstart THEN EXIT END;
						INC(refpos, 1+1+1+1);
						refstart := refpos;
						REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
					ELSIF ch < 0F8X THEN (* skip object *)
						INC(refpos);	(* skip typeform *)
						ReadNum(refpos, procstart);	(* skip offset *)
						REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
					END
				END;
				refpos := refstart;
				IF refpos # 0 THEN
					SYSTEM.GET(refpos, ch); INC(refpos); ch0 := ch;
					WHILE ch # 0X DO name[i] := ch; INC(i); SYSTEM.GET(refpos, ch); INC(refpos) END;
					name[i] := 0X
				END
			END;
			WriteString("  PC = ", name, i); WriteHex(pc-SYSTEM.ADR(mod.code[0]), name, i); WriteString("H", name, i)
		END
	END GetProcedure;
	
	
	PROCEDURE GetTypeName*(p: SYSTEM.PTR; VAR name: ARRAY OF CHAR);
	VAR ch: CHAR; i, tag: LONGINT;
	BEGIN
		IF p = NIL THEN COPY("NIL", name)
		ELSE
			SYSTEM.GET(SYSTEM.VAL(LONGINT, p)-4, tag);
			IF (tag # 0) & (tag MOD 16 = 8) THEN
				SYSTEM.GET(tag-4, tag);
				INC(tag, 16);
				SYSTEM.GET(tag, ch); i := 0;
				WHILE (ch # 0X) & (i < LEN(name)-1) DO
					name[i] := ch; INC(i); SYSTEM.GET(tag+i, ch)
				END;
				name[i] := 0X
			ELSE
				COPY("wrong tag", name)
			END
		END
	END GetTypeName;

	(*
	PROCEDURE -GetInfo (off, ebp: LONGINT): LONGINT;
	CODE {SYSTEM.i386}
		POP	EBX
		POP	EAX
		MOV EAX, 0[EBX][EAX]
	END GetInfo;
	*)
	PROCEDURE GetInfo(off, ebp: LONGINT): LONGINT;
	BEGIN
		RETURN SYSTEM.GET32(ebp+off)
	END GetInfo;
	
	PROCEDURE ToDo*(class: LONGINT);
		VAR pc, ebp: LONGINT; p, q: List; name: ARRAY 64 OF CHAR;
	BEGIN {EXCLUSIVE}
		SYSTEM.GETREG(5, ebp);
		pc := GetInfo(4, ebp);
		p := pclist;
		WHILE (p.next # NIL) & (p.next.pc < pc) DO p := p.next END;
		IF (p.next = NIL) OR (p.next.pc # pc) THEN
			NEW(q); q.pc := pc;  q.next := p.next; p.next := q;
			AosOut.Ln;
			CASE class OF
			|	NotImplemented:	AosOut.String("    unimplemented at ")
			|	NotOptimized:	AosOut.String("    not optimized at ")
			END;
			GetProcedure(pc, name); AosOut.String(name);
		END;
		IF class = NotImplemented THEN
			HALT(MAX(INTEGER))
		END
	END ToDo;
	
	PROCEDURE ResetToDo*;
	BEGIN
		NEW(pclist); pclist.next := NIL;
	END ResetToDo;
	

BEGIN
	Hex := "0123456789ABCDEF"
END PCDebug.

(*
	08.02.02	prk	use Aos instead of Oberon modules
	22.01.02	prk	ToDo list moved to PCDebug
	25.03.01	prk	renamed, was Debug.Mod
*)