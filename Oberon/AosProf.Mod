(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosProf;	(* pjm *)

(* Aos statistical profiler *)

IMPORT SYSTEM, AosOut, AosInterrupts, AosModules, AosProcessors, AosKernel;

CONST
	Divisor = 4;
	MaxRanges = 64;
	MaxModules = 256;
	MaxSpace = 65536;

	WaitTime = 100;	(* ms *)
	
TYPE
	Range = RECORD
		lowAdr, highAdr: LONGINT;
		count: POINTER TO ARRAY OF LONGINT
	END;

	Bytes = AosModules.Bytes;
	
VAR
	size, outside, total: LONGINT;
	range: ARRAY MaxRanges OF Range;
	running: BOOLEAN;
	
PROCEDURE HandleTimer(id: LONGINT; VAR state: AosInterrupts.State);
VAR low, high, i: LONGINT;
BEGIN
	AosKernel.AtomicInc(total);
	low := 0; high := size;
	LOOP
		IF low >= high THEN AosKernel.AtomicInc(outside); EXIT END;
		i := low + (high-low) DIV 2;
		IF state.EIP >= range[i].lowAdr THEN
			IF state.EIP <= range[i].highAdr THEN	(* found *)
				AosKernel.AtomicInc(range[i].count[(state.EIP-range[i].lowAdr) DIV Divisor]);
				EXIT
			ELSE
				low := i+1
			END
		ELSE
			high := i
		END
	END
END HandleTimer;

PROCEDURE GetRanges(VAR n: LONGINT; VAR range: ARRAY OF Range);
VAR m: AosModules.Module; i, j, lowAdr, highAdr: LONGINT; a: ARRAY MaxModules OF Range;
BEGIN
		(* get & sort - assume module list does not change during this loop *)
	m := AosModules.root; n := 0;
	WHILE m # NIL DO
		lowAdr := SYSTEM.ADR(m.code[0]);
		highAdr := lowAdr + LEN(m.code);
			(* insert sort *)
		i := 0; WHILE (i # n) & (lowAdr > a[i].lowAdr) DO INC(i) END;
		FOR j := n-1 TO i BY -1 DO a[j+1] := a[j] END;
		a[i].lowAdr := lowAdr; a[i].highAdr := highAdr; INC(n);
		m := m.next
	END;
		(* combine ranges that are close enough together *)
	i := 0;
	WHILE i < n-1 DO
		IF a[i+1].lowAdr - a[i].highAdr < MaxSpace THEN
			a[i].highAdr := a[i+1].highAdr;
			DEC(n);
			FOR j := i+1 TO n-1 DO a[j] := a[j+1] END
		ELSE
			INC(i)
		END
	END;
	IF n > LEN(range) THEN
		AosOut.Enter; AosOut.String("Warning: Only using first ");
		AosOut.Int(LEN(range), 1); AosOut.String(" of ");
		AosOut.Int(n, 1); AosOut.String(" ranges"); AosOut.Exit;
		n := LEN(range)
	END;
	FOR i := 0 TO n-1 DO
		NEW(a[i].count, (a[i].highAdr-a[i].lowAdr) DIV Divisor);
		range[i] := a[i]
	END
END GetRanges;

PROCEDURE Start*(par: PTR): PTR;
	VAR r: PTR;
BEGIN
	IF running THEN r := Stop(par) END;
	GetRanges(size, range);
	outside := 0; total := 0;
	AosProcessors.InstallHandler(HandleTimer);
	running := TRUE;
	RETURN NIL
END Start;

PROCEDURE Stop*(par: PTR): PTR;
BEGIN
	IF running THEN
		AosProcessors.InstallHandler(NIL);
		running := FALSE
	END;
	RETURN NIL
END Stop;

PROCEDURE Continue*(par: PTR): PTR;
BEGIN
	IF ~running & (size # 0) THEN
		AosProcessors.InstallHandler(HandleTimer);
		running := TRUE
	END;
	RETURN NIL
END Continue;

PROCEDURE GetNum(refs: Bytes;  VAR i, num: LONGINT);
VAR n, s: LONGINT;  x: CHAR;
BEGIN
	s := 0;  n := 0;  x := refs[i];  INC(i);
	WHILE ORD(x) >= 128 DO
		INC(n, ASH(ORD(x) - 128, s));  INC(s, 7);  x := refs[i];  INC(i)
	END;
	num := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64 * 64, s)
END GetNum;

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

(* FindProc - Find a procedure in the reference block.  Return index of name, or -1 if not found. *)

PROCEDURE FindProc(refs: Bytes;  ofs: LONGINT): LONGINT;
VAR i, m, t, proc: LONGINT;  ch: CHAR;
BEGIN
	proc := -1;  i := 0;  m := LEN(refs^);
	ch := refs[i];  INC(i);
	WHILE (i < m) & ((ch = 0F8X) OR (ch = 0F9X)) DO	(* proc *)
		GetNum(refs, i, t);	(* pofs *)
		IF t > ofs THEN	(* previous procedure was the one *)
			ch := 0X	(* stop search *)
		ELSE	(* ~found *)
			IF ch = 0F9X THEN
				GetNum(refs, i, t);	(* nofPars *)
				INC(i, 3)	(* RetType, procLev, slFlag *)
			END;
			proc := i;	(* remember this position, just before the name *)
			REPEAT ch := refs[i];  INC(i) UNTIL ch = 0X;	(* pname *)
			IF i < m THEN
				ch := refs[i];  INC(i);	(* 1X | 3X | 0F8X | 0F9X *)
				WHILE (i < m) & (ch >= 1X) & (ch <= 3X) DO	(* var *)
					ch := refs[i];  INC(i);	(* type *)
					IF (ch >= 81X) OR (ch = 16X) OR (ch = 1DX) THEN
						GetNum(refs, i, t)	(* dim/tdadr *)
					END;
					GetNum(refs, i, t);	(* vofs *)
					REPEAT ch := refs[i];  INC(i) UNTIL ch = 0X;	(* vname *)
					IF i < m THEN ch := refs[i];  INC(i) END	(* 1X | 3X | 0F8X | 0F9X *)
				END
			END
		END
	END;
	IF (proc = -1) & (i # 0) THEN proc := i END;	(* first procedure *)
	RETURN proc
END FindProc;

PROCEDURE GetProc(mod: AosModules.Module;  VAR pc: LONGINT;  VAR procname: ARRAY OF CHAR);
VAR refpos, i: LONGINT; refs: Bytes; ch: CHAR;
BEGIN
	refpos := -1;
	DEC(pc, SYSTEM.ADR(mod.code[0]));
	refs := SYSTEM.VAL(Bytes, mod.refs);
	IF (refs # NIL) & (LEN(mod.refs) # 0) THEN
		refpos := FindProc(refs, pc);
		IF refpos # -1 THEN
			ch := refs[refpos];  INC(refpos);  i := 0;
			WHILE ch # 0X DO
				procname[i] := ch;  ch := refs[refpos];  INC(refpos);  INC(i)
			END;
			procname[i] := 0X
		END
	END
END GetProc;

PROCEDURE ShowStats;
VAR sum, i: LONGINT;
BEGIN
	sum := 0;
	FOR i := 0 TO size-1 DO
		INC(sum, LEN(range[i].count)*SIZE(LONGINT))
	END;
	AosOut.Int(total, 1); AosOut.String(" samples, ");
	AosOut.Int(outside, 1); AosOut.String(" unknown, ");
	AosOut.Int(size, 1); AosOut.String(" ranges, ");
	AosOut.Int(sum DIV 1024, 1); AosOut.String("KB,");
	IF ~running THEN AosOut.String(" not") END;
	AosOut.String(" running");
	AosOut.Ln(); AosOut.Ln()
END ShowStats;

PROCEDURE ShowDetail*(par: PTR): PTR;
VAR i, j, pc, per: LONGINT; m: AosModules.Module; procname: ARRAY 64 OF CHAR;
BEGIN
	ShowStats;
	FOR i := 0 TO size-1 DO
		FOR j := 0 TO LEN(range[i].count)-1 DO
			IF range[i].count[j] # 0 THEN
				pc := range[i].lowAdr + j*Divisor;
				m := AosModules.ThisModuleByAdr(pc);
				IF m # NIL THEN
					GetProc(m, pc, procname);
					AosOut.String(m.name); AosOut.Char("."); AosOut.String(procname);
					AosOut.String(" PC="); AosOut.Int(pc, 1)
				ELSE
					AosOut.String("EIP ="); AosOut.Hex(pc, 0)
				END;
				AosOut.Char(" "); AosOut.Int(range[i].count[j], 1);
				IF ~running & (total # 0) THEN
					per := ENTIER(range[i].count[j]/total*100 + 0.5);
					IF per # 0 THEN
						AosOut.Char(" "); AosOut.Int(per, 1); AosOut.Char("%")
					END
				END;
				AosOut.Ln()
			END
		END
	END;
	RETURN NIL
END ShowDetail;

PROCEDURE Hex(x: LONGINT; VAR buf: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	j := 8;
	FOR i := j-1 TO 0 BY -1 DO
		buf[i] := CHR(x MOD 10H + 48);
		IF buf[i] > "9" THEN
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
		END;
		x := x DIV 10H
	END;
	buf[j] := 0X
END Hex;

PROCEDURE ShowProcs*(par: PTR): PTR;
TYPE
	List = POINTER TO RECORD
		next: List;
		m: AosModules.Module;
		procname: ARRAY 64 OF CHAR;
		count: LONGINT
	END;
	
VAR
	i, j, pc, sum, per: LONGINT; m, prev: AosModules.Module; root: List;
	procname, prevname: ARRAY 64 OF CHAR;

	PROCEDURE Output;
	VAR n, p: List;
	BEGIN
		IF prevname # "" THEN
			NEW(n); n.m := prev; COPY(prevname, n.procname); n.count := sum;
			p := root;
			WHILE (p.next # NIL) & (p.next.count >= n.count) DO p := p.next END;
			n.next := p.next; p.next := n;
			sum := 0
		END;
		prevname := procname; prev := m
	END Output;
	
BEGIN
	ShowStats;
	prev := NIL; prevname := ""; sum := 0; NEW(root); root.next := NIL;
	FOR i := 0 TO size-1 DO
		FOR j := 0 TO LEN(range[i].count)-1 DO
			IF range[i].count[j] # 0 THEN
				pc := range[i].lowAdr + j*Divisor;
				m := AosModules.ThisModuleByAdr(pc);
				IF m # NIL THEN GetProc(m, pc, procname) ELSE Hex(pc, procname) END;
				IF (m # prev) OR (procname # prevname) THEN Output END;
				INC(sum, range[i].count[j])
			END
		END
	END;
	Output;
	LOOP
		root := root.next;
		IF root = NIL THEN EXIT END;
		AosOut.Int(root.count, 1); AosOut.Char(" ");
		IF root.m # NIL THEN AosOut.String(root.m.name) ELSE AosOut.String("Unknown") END;
		AosOut.Char("."); AosOut.String(root.procname);
		IF ~running & (total # 0) THEN
			per := ENTIER(root.count/total*100 + 0.5);
			IF per # 0 THEN
				AosOut.Char(" "); AosOut.Int(per, 1); AosOut.Char("%")
			END
		END;
		AosOut.Ln()
	END;
	RETURN NIL
END ShowProcs;

PROCEDURE Cleanup;
VAR t: AosKernel.MilliTimer; r: PTR;
BEGIN
	IF running THEN
		r := Stop(NIL);
		AosKernel.SetTimer(t, WaitTime);
		REPEAT UNTIL AosKernel.Expired(t)	(* wait for all handlers to terminate *)
	END
END Cleanup;

BEGIN
	running := FALSE;
	AosModules.InstallTermHandler(Cleanup)
END AosProf.

AosProf.Oba
AosProf.Start
AosProf.Stop
AosProf.Continue
AosProf.ShowProcs
AosProf.ShowDetail

Configuration.DoCommands
AosProf.Delay 1000
Attributes.Echo Start ~
AosProf.Start
AosProf.Delay 5000
AosProf.Stop
Attributes.Echo Stop ~
AosProf.ShowProcs
~

System.State AosProf ~

System.Free AosProf ~
