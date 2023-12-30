(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosTrap; (** AUTHOR "pjm"; PURPOSE "Trap handling and symbolic debugging"; *)

IMPORT SYSTEM, AosBoot, AosLocks, AosOut, AosIO, AosMemory, AosInterrupts, AosModules, 
	AosKernel, AosActive;

CONST
	MaxFrames = 16;	(* number of stack frames to trace back *)
	MaxString = 64;
	MaxArray = 8;
	MaxCols = 70;
	ShowAllProcs = TRUE;	(* trace back stack even if unknown procedures are encountered *)
	RecursiveLimit = 2;	(* normally 1 or 2 - how many recursive traps to display before stopping *)
	Trace = FALSE;
	TestTrap = TRUE;

	Sep = "  "; SepLen = 2;		
	
	(* Process termination halt codes *)	
	halt* = AosActive.halt;
	haltUnbreakable* = AosActive.haltUnbreakable;	

TYPE
	Variable* = RECORD adr-, type-, size-, n-, tdadr-: LONGINT END;	(** variable descriptor *)

VAR
	trapState: ARRAY AosBoot.MaxCPU OF LONGINT;	(* indexed by AosBoot.ID() *)
	w: AosIO.Writer;	(* protected by AosOutHigh lock in Show *)
	modes: ARRAY 25 OF CHAR;
	flags: ARRAY 13 OF CHAR;

(* Get a compressed refblk number. *)

PROCEDURE GetNum(refs: AosModules.Bytes; VAR i, num: LONGINT);
VAR n, s: LONGINT; x: CHAR;
BEGIN
	s := 0; n := 0;
	x := refs[i]; INC(i);
	WHILE ORD(x) >= 128 DO
		INC(n, ASH(ORD(x) - 128, s));
		INC(s, 7);
		x := refs[i]; INC(i)
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

(* Find a procedure in the reference block.  Return index of name, or -1 if not found. *)

PROCEDURE FindProc(refs: AosModules.Bytes; modpc: LONGINT): LONGINT;
VAR i, m, t, proc: LONGINT; ch: CHAR;
BEGIN
	proc := -1; i := 0; m := LEN(refs^);
	ch := refs[i]; INC(i);
	WHILE (i < m) & ((ch = 0F8X) OR (ch = 0F9X)) DO	(* proc *)
		GetNum(refs, i, t);	(* pofs *)
		IF t > modpc THEN	(* previous procedure was the one *)
			ch := 0X	(* stop search *)
		ELSE	(* ~found *)
			IF ch = 0F9X THEN
				GetNum(refs, i, t);	(* nofPars *)
				INC(i, 3)	(* RetType, procLev, slFlag *)
			END;
			proc := i;	(* remember this position, just before the name *)
			REPEAT ch := refs[i]; INC(i) UNTIL ch = 0X;	(* pname *)
			IF i < m THEN
				ch := refs[i]; INC(i);	(* 1X | 3X | 0F8X | 0F9X *)
				WHILE (i < m) & (ch >= 1X) & (ch <= 3X) DO	(* var *)
					ch := refs[i]; INC(i);	(* type *)
					IF (ch >= 81X) OR (ch = 16X) OR (ch = 1DX) THEN
						GetNum(refs, i, t)	(* dim/tdadr *)
					END;
					GetNum(refs, i, t);	(* vofs *)
					REPEAT ch := refs[i]; INC(i) UNTIL ch = 0X;	(* vname *)
					IF i < m THEN ch := refs[i]; INC(i) END	(* 1X | 3X | 0F8X | 0F9X *)
				END
			END
		END
	END;
	IF (proc = -1) & (i # 0) THEN proc := i END;	(* first procedure *)
	RETURN proc
END FindProc;


(* Write the specified procedure name and returns parameters for use with NextVar and Variables. *)

PROCEDURE WriteProc0(w: AosIO.Writer; mod: AosModules.Module; pc, fp: LONGINT; VAR refs: AosModules.Bytes;
		VAR refpos, base: LONGINT);
VAR ch: CHAR;
BEGIN
	refpos := -1;
	IF mod = NIL THEN
		IF pc = 0 THEN w.String("NIL")
		ELSE
			w.String("Unknown PC="); w.Hex(pc, 8); w.Char("H")
		END;
		IF fp # -1 THEN
			w.String(" FP="); w.Hex(fp, 8); w.Char("H")
		END
	ELSE
		w.String(mod.name);
		DEC(pc, SYSTEM.ADR(mod.code[0]));
		refs := mod.refs;
		IF (refs # NIL) & (LEN(refs) # 0) THEN
			refpos := FindProc(refs, pc);
			IF refpos # -1 THEN
				w.Char(".");
				ch := refs[refpos]; INC(refpos);
				IF ch = "$" THEN base := mod.sb ELSE base := fp END;	(* for variables *)
				WHILE ch # 0X DO w.Char(ch); ch := refs[refpos]; INC(refpos) END
			END
		END;
		w.String(" pc="); w.Int(pc, 1);
	END
END WriteProc0;

(** Find procedure name and write it. *)

PROCEDURE WriteProc*(w: AosIO.Writer; pc: LONGINT);
VAR refs: AosModules.Bytes; refpos, base: LONGINT;
BEGIN
	WriteProc0(w, AosModules.ThisModuleByAdr(pc), pc, -1, refs, refpos, base)
END WriteProc;

(* Write a simple variable value. *)

PROCEDURE WriteSimpleVar(w: AosIO.Writer; adr, type, tdadr: LONGINT; VAR col: LONGINT);
VAR ch: CHAR; sval: SHORTINT; ival: INTEGER; lval: LONGINT;
BEGIN
	CASE type OF
		1,3:	(* BYTE, CHAR *)
			SYSTEM.GET(adr, ch);
			IF (ch > " ") & (ch <= "~") THEN w.Char(ch); INC(col)
			ELSE w.Hex(ORD(ch), -2); w.Char("X"); INC(col, 3)
			END
		|2:	(* BOOLEAN *)
			SYSTEM.GET(adr, ch);
			IF ch = 0X THEN w.String("FALSE")
			ELSIF ch = 1X THEN w.String("TRUE")
			ELSE w.Int(ORD(ch), 1)
			END;
			INC(col, 5)
		|4:	(* SHORTINT *)
			SYSTEM.GET(adr, sval); w.Int(sval, 1); INC(col, 4)
			(*w.String(" ("); w.Hex(sval, -3); w.String("H)")*)
		|5:	(* INTEGER *)
			SYSTEM.GET(adr, ival); w.Int(ival, 1); INC(col, 5)
			(*w.String(" ("); w.Hex(ival, 8); w.String("H)")*)
		|6:	(* LONGINT *)
			SYSTEM.GET(adr, lval); w.Int(lval, 1); INC(col, 5);
			IF ABS(lval) >= 10000H THEN
				w.String(" ("); w.Hex(lval, 8); w.String("H)"); INC(col, 12)
			END
		|7,8,13,16,29:	(* REAL, LONGREAL, POINTER *)
			INC(col, 9);
			IF (type = 8) OR (type = 16) THEN SYSTEM.GET(adr+4, lval); w.Hex(lval, 8); INC(col, 8) END;
			SYSTEM.GET(adr, lval); w.Hex(lval, 8); w.Char("H")
		|9:	(* SET *)
			SYSTEM.GET(adr, lval); w.Set(SYSTEM.VAL(SET, lval)); INC(col, 8)	(* col is guess *)
		|22:	(* RECORD *)
			w.String("Rec."); w.Hex(tdadr, 8); w.Char("H");
			INC(col, 13)
		|14:	(* PROC *)
			SYSTEM.GET(adr, lval); WriteProc(w, lval); INC(col, 25)
	END
END WriteSimpleVar;

(** Write a variable value.  The v parameter is a variable descriptor obtained with NextVar.  Parameter col is incremented with the (approximate) number of characters written. *)

PROCEDURE WriteVar*(w: AosIO.Writer; v: Variable; VAR col: LONGINT);
VAR ch: CHAR;
BEGIN
	IF v.type = 15 THEN
		w.Char(22X);
		LOOP
			IF v.n = 0 THEN EXIT END;
			SYSTEM.GET(v.adr, ch); INC(v.adr);
			IF (ch < " ") OR (ch > "~") THEN EXIT END;
			w.Char(ch); INC(col); DEC(v.n)
		END;
		w.Char(22X); INC(col, 2);
		IF ch # 0X THEN w.Char("!") END
	ELSE
		WHILE v.n > 0 DO
			WriteSimpleVar(w, v.adr, v.type, v.tdadr, col);
			DEC(v.n); INC(v.adr, v.size);
			IF v.n > 0 THEN
				w.String(", "); INC(col, 2)
			END
		END
	END
END WriteVar;

(** Find global variables of mod (which may be NIL) and return it in the refs, refpos and base parameters for use by NextVar.  If not found, refpos returns -1. *)

PROCEDURE InitVar*(mod: AosModules.Module; VAR refs: AosModules.Bytes; VAR refpos, base: LONGINT);
VAR ch: CHAR;
BEGIN
	refpos := -1;
	IF mod # NIL THEN
		refs := mod.refs; base := mod.sb;
		IF (refs # NIL) & (LEN(refs) # 0) THEN
			refpos := FindProc(refs, 0);
			IF refpos # -1 THEN
				ch := refs[refpos]; INC(refpos);
				WHILE ch # 0X DO ch := refs[refpos]; INC(refpos) END
			END
		END
	END
END InitVar;

(** Step to the next variable in the refs block.  The name parameter returns empty if no more variables are found.  The attributes are returned in v.  Parameter refpos is modified.  *)

PROCEDURE NextVar*(refs: AosModules.Bytes; VAR refpos: LONGINT; base: LONGINT; VAR name: ARRAY OF CHAR; VAR v: Variable);
VAR x: Variable; j: LONGINT; ch, mode: CHAR;
BEGIN
	name[0] := 0X;	(* empty name signals end or error *)
	IF refpos < LEN(refs^)-1 THEN
		mode := refs[refpos]; INC(refpos);
		IF (mode >= 1X) & (mode <= 3X) THEN	(* var *)
			x.type := ORD(refs[refpos]); INC(refpos);
			IF x.type > 80H THEN
				IF x.type = 83H THEN x.type := 15 ELSE DEC(x.type, 80H) END;
				GetNum(refs, refpos, x.n)
			ELSIF (x.type = 16H) OR (x.type = 1DH) THEN
				GetNum(refs, refpos, x.tdadr); x.n := 1
			ELSE
				IF x.type = 15 THEN x.n := MaxString (* best guess *) ELSE x.n := 1 END
			END;
				(* get address *)
			GetNum(refs, refpos, x.adr);
			INC(x.adr, base);	(* convert to absolute address *)
			IF x.n = 0 THEN	(* open array (only on stack, not global variable) *)
				SYSTEM.GET(x.adr+4, x.n)	(* real LEN from stack *)
			END;
			IF mode # 1X THEN SYSTEM.GET(x.adr, x.adr) END;	(* indirect *)
				(* get size *)
			CASE x.type OF
				1..4,15: x.size := 1
				|5: x.size := 2
				|6..7,9,13,14,29: x.size := 4
				|8, 16: x.size := 8
				|22: x.size := 0; ASSERT(x.n <= 1)
			ELSE x.size := -1
			END;
			IF x.size >= 0 THEN	(* ok, get name *)
				ch := refs[refpos]; INC(refpos); j := 0;
				WHILE ch # 0X DO
					IF j < LEN(name)-1 THEN name[j] := ch; INC(j) END;	(* truncate long names *)
					ch := refs[refpos]; INC(refpos)
				END;
				name[j] := 0X; v := x	(* non-empty name *)
			END
		END
	END
END NextVar;

(** Find the specified global variable and return its descriptor.  Returns TRUE iff the variable is found. *)

PROCEDURE FindVar*(mod: AosModules.Module; name: ARRAY OF CHAR; VAR v: Variable): BOOLEAN;
VAR refs: AosModules.Bytes; refpos, base: LONGINT; n: ARRAY 64 OF CHAR;
BEGIN
	InitVar(mod, refs, refpos, base);
	IF refpos # -1 THEN
		LOOP
			NextVar(refs, refpos, base, n, v);
			IF n = "" THEN EXIT END;
			IF n = name THEN RETURN TRUE END
		END
	END;
	RETURN FALSE
END FindVar;

(* Display variables. *)

PROCEDURE Variables(w: AosIO.Writer; refs: AosModules.Bytes; refpos, base: LONGINT);
VAR v: Variable; j, col: LONGINT; name: ARRAY 64 OF CHAR; etc: BOOLEAN;
BEGIN
	LOOP
		NextVar(refs, refpos, base, name, v);
		IF name[0] = 0X THEN EXIT END;
			(* write name *)
		IF (col # 0 ) & (v.n > 1) & (v.type # 15) THEN	(* Ln before array (except string) *)
			w.Ln; col := 0
		END;
		w.String(Sep); w.String(name); w.Char("=");
		j := 0; WHILE name[j] # 0X DO INC(j) END;
		INC(col, SepLen+1+j);
			(* write variable *)
		IF (v.adr >= -4) & (v.adr < 4096) THEN	(* must be NIL VAR parameter *)
			w.String("NIL ("); w.Hex(v.adr, 8); 
			w.Char(")"); INC(col, 14)
		ELSE
			etc := FALSE;
			IF v.type = 15 THEN
				IF v.n > MaxString THEN etc := TRUE; v.n := MaxString END
			ELSE
				IF v.n > MaxArray THEN etc := TRUE; v.n := MaxArray END
			END;
			WriteVar(w, v, col);	(* write value *)
			IF etc THEN w.String("..."); INC(col, 3) END
		END;
		IF col > MaxCols THEN w.Ln; col := 0 END
	END;
	IF col # 0 THEN w.Ln END
END Variables;

(** Write the state of the specified module. *)

PROCEDURE ModuleState*(w: AosIO.Writer; mod: AosModules.Module);
VAR refpos, base: LONGINT; refs: AosModules.Bytes; 
BEGIN
	InitVar(mod, refs, refpos, base);
	IF refpos # -1 THEN
		w.String("State "); w.String(mod.name); w.Char(":"); w.Ln;
		Variables(w, refs, refpos, base)
	END
END ModuleState;

(* Display call trackback. *)

PROCEDURE StackTraceBack*(w: AosIO.Writer; eip, ebp: LONGINT; long, overflow: BOOLEAN);
VAR count, refpos, base: LONGINT; m: AosModules.Module; refs: AosModules.Bytes;
BEGIN
	count := 0;	(* frame count *)
	REPEAT
		m := AosModules.ThisModuleByAdr(eip);
		IF ShowAllProcs OR (m # NIL) OR (count = 0) THEN
			WriteProc0(w, m, eip, ebp, refs, refpos, base); w.Ln;
			IF long & (~overflow OR (count > 0)) THEN	(* show variables *)
				IF refpos # -1 THEN Variables(w, refs, refpos, base) END;
				IF (m # NIL) & (base # m.sb) & (count = 0) THEN ModuleState(w, m) END
			END;			
			IF ebp # 0 THEN (* if ebp is 0 in first frame *)
				SYSTEM.GET(ebp+4, eip);	(* return addr from stack *)
				SYSTEM.GET(ebp, ebp);	(* follow dynamic link *)
			END;	
			INC(count)
		ELSE
			ebp := 0
		END
	UNTIL (ebp = 0) OR (count = MaxFrames);
	IF ebp # 0 THEN w.String("...") END
END StackTraceBack;

(* Write flag values. *)

PROCEDURE Flags(w: AosIO.Writer; s: SET);
VAR i: SHORTINT; ch: CHAR;
BEGIN
	FOR i := 0 TO 11 DO
		ch := flags[i];
		IF ch # "!" THEN
			IF i IN s THEN ch := CAP(ch) END;
			w.Char(ch)
		END
	END;
	w.String(" iopl"); w.Int(ASH(SYSTEM.VAL(LONGINT, s * {12,13}), -12), 1)
END Flags;

(** Write a type name, given its tag value. *)

PROCEDURE WriteType*(w: AosIO.Writer; adr: LONGINT);
VAR m: AosModules.Module; t: AosModules.TypeDesc;
BEGIN
	AosModules.ThisTypeByAdr(adr - adr MOD 8, m, t);
	IF m # NIL THEN
		w.String(m.name); w.Char(".");
		IF t.name = "" THEN w.String("TYPE") ELSE w.String(t.name) END
	ELSE
		w.String("NIL")
	END
END WriteType;

(** Write a process's state in one line. *)

PROCEDURE WriteProcess*(w: AosIO.Writer; p: AosActive.Process);
VAR adr, mode: LONGINT; m: AosModules.Module;
BEGIN
	IF p # NIL THEN
		w.Int(p.id, 5);
		mode := p.mode;
		IF (mode >= AosActive.Ready) & (mode <= AosActive.Terminated) THEN
			adr := (mode-AosActive.Ready)*4;
			FOR adr := adr TO adr+3 DO w.Char(modes[adr]) END
		ELSE
			w.Char(" "); w.Int(mode, 1)
		END;
		w.Int(p.procID, 2);
		w.Int(p.priority, 2);
		w.Hex(SYSTEM.VAL(LONGINT, p.obj), 9);
		IF p.obj # NIL THEN
			SYSTEM.GET(SYSTEM.VAL(LONGINT, p.obj)-4, adr);
			w.Char(":"); WriteType(w, adr-adr MOD 8)
		END;
		w.Char(" "); WriteProc(w, p.state.EIP);
		IF p.mode = AosActive.AwaitingLock THEN
			adr := SYSTEM.VAL(LONGINT, p.waitingOn);
			w.Hex(adr, 9);
			IF adr # 0 THEN	(* can be 0 when snapshot is taken *)
				SYSTEM.GET(adr-4, adr); DEC(adr, adr MOD 8);
				IF adr = SYSTEM.TYPECODE(AosModules.Module) THEN
					w.Char("-");
					m := SYSTEM.VAL(AosModules.Module, adr);
					w.String(m.name)
				ELSE
					w.Char(":"); WriteType(w, adr)
				END
			END
		ELSIF p.mode = AosActive.AwaitingCond THEN
			w.Char(" "); WriteProc(w, SYSTEM.VAL(LONGINT, p.condition));
			w.Hex(p.condFP, 9)
		END;
		w.Char(" "); w.Set(p.flags)
	END
END WriteProcess;

(** Display trap state. *)

PROCEDURE Show*(p: AosActive.Process; VAR int: AosInterrupts.State; VAR exc: AosInterrupts.ExceptionState; long: BOOLEAN);
VAR id: LONGINT; overflow: BOOLEAN;
	
	PROCEDURE Val(s: ARRAY OF CHAR; val: LONGINT);
	BEGIN
		w.Char(" "); w.String(s); w.Char("="); w.Hex(val, 8)
	END Val;

BEGIN
	overflow := FALSE;
	AosLocks.Acquire(AosLocks.AosOutHigh);	(* like AosOut.Enter, but without output *)
	w.Update;	(* flush previous output stuck in global writer w *)
	w.Char(1X);	(* "start of trap" *)
	id := AosBoot.ID();
	INC(trapState[id]);
	IF trapState[id] > RecursiveLimit THEN
		w.String(" [Recursive TRAP]")
	ELSE
			(* output first line *)
		w.String("["); w.Int(trapState[id], 1); w.String("] ");
		w.String("TRAP "); w.Int(exc.halt, 1);
		w.String(" PL"); w.Int(int.CS MOD 4, 2); w.Char(" ");
		CASE exc.halt OF
			-14:	(* page fault *)
				IF (int.CS MOD 4 > AosInterrupts.KernelLevel) & (exc.pf+4 = int.ESP) THEN
					w.String("stack overflow"); overflow := TRUE
				END
			|0: w.String("division error")
			|1: w.String("WITH guard failed")
			|2: w.String("CASE invalid")
			|3: w.String("RETURN missing")
			|4: w.String("integer overflow")
			|5: w.String("implicit type guard failed")
			|6: w.String("type guard failed")
			|7: w.String("index out of range")
			|8: w.String("ASSERT failed")
			|9: w.String("array dimension error")
			|14: w.String("out of memory")
			ELSE
				IF (exc.halt > MAX(INTEGER)+1) OR (exc.halt < MIN(INTEGER)) THEN
					w.String("module freed?")
				END
		END;
		IF exc.locks # {} THEN
			w.String(", Locks: "); w.Set(exc.locks)
		END;
		w.Char(" "); w.String(AosBoot.version);
		IF long THEN
			w.Char(0EX);	(* "fixed font" *)
			w.Ln;
				(* output values *)
			Val("CS:", int.CS); Val("DS:", exc.DS); Val("ES:", exc.ES); Val("SS:", exc.SS); Val("CR0", exc.CR[0]);
			Val("FPU", SYSTEM.VAL(LONGINT, exc.FPU[1] * {0..15} + SYSTEM.LSH(exc.FPU[2], 16))); w.Ln;
			Val("EIP", int.EIP); Val("ESI", int.ESI); Val("EDI", int.EDI); Val("ESP", exc.ESP); Val("CR2", exc.CR[2]); 
			Val("PID", id); w.Ln;
			Val("EAX", int.EAX); Val("EBX", int.EBX); Val("ECX", int.ECX); Val("EDX", int.EDX); Val("CR3", exc.CR[3]); 
			Val("LCK", SYSTEM.VAL(LONGINT, exc.locks)); w.Ln;
			Val("EBP", int.EBP); Val("FS:", exc.FS); Val("GS:", exc.GS); Val("ERR", int.ERR); Val("CR4", exc.CR[4]); 
			Val("TMR", AosKernel.GetTimer()); w.Ln;
			IF SYSTEM.VAL(CHAR, exc.DR[7]) # 0X THEN	(* some breakpoints enabled *)
				Val("DR0", exc.DR[0]); Val("DR1", exc.DR[1]); Val("DR2", exc.DR[2]); Val("DR3", exc.DR[3]);
				Val("DR6", exc.DR[6]); Val("DR7", exc.DR[7]); w.Ln
			END;
			w.String(" EFLAGS: "); Flags(w, int.EFLAGS);
			w.Char(0FX);	(* "proportional font" *)
			w.Char(" "); w.Set(int.EFLAGS); w.Ln;
			(*IF int.INT = AosInterrupts.UD THEN AosOut.Memory(int.EIP, 16) END*)	(* show bad instruction *)
		ELSE
			w.Ln
		END;
		w.String("Process:"); WriteProcess(w, p); w.Ln;
		(*IF exc.halt = 1301 THEN	(* lock timeout - see AosLocks *)
			AosOut.Memory(SYSTEM.ADR(AosLocks.trapState[0]), LEN(AosLocks.trapState) * 
				(SYSTEM.ADR(AosLocks.trapState[1]) - SYSTEM.ADR(AosLocks.trapState[0])));
			w.Hex(SYSTEM.VAL(LONGINT, AosLocks.trapLocksBusy), 8); w.Ln
		END;
		IF (int.INT = AosInterrupts.PF) & (ABS(int.EIP-exc.CR[2]) < 100H) THEN	(* PF close to EIP *)
			AosOut.Memory(int.ESP-16, 64)	(* show stack *)
		END;*)
		IF MaxFrames # 0 THEN StackTraceBack(w, int.EIP, int.EBP, long, overflow) END
	END;
	w.Char(02X);	(* "end of trap" *)
	w.Update;
	AosLocks.Release(AosLocks.AosOutHigh);	(* like AosOut.Exit, but without output *)
	trapState[id] := 0
END Show;

PROCEDURE SetLastExceptionState(ex: AosInterrupts.ExceptionState);
VAR id: LONGINT;
BEGIN
	id := AosLocks.AcquirePreemption();
	AosActive.running[id].exp := ex;
	AosLocks.ReleasePreemption();
END SetLastExceptionState;

PROCEDURE GetLastExceptionState*(): AosInterrupts.ExceptionState;
VAR 
	id: LONGINT;
	ex: AosInterrupts.ExceptionState;
BEGIN
	id := AosLocks.AcquirePreemption();
	ex := AosActive.running[id].exp;
	AosLocks.ReleasePreemption();
	RETURN ex;
END GetLastExceptionState;

(**  Handles an exception. Interrupts are on during this procedure. *)
PROCEDURE HandleException(VAR int: AosInterrupts.State; VAR exc: AosInterrupts.ExceptionState; VAR handled: BOOLEAN);
VAR
	fp, sp, pc, handler: LONGINT;
BEGIN	
	fp := int.EBP; sp := int.ESP; pc := int.EIP;		
	handler := AosModules.GetExceptionHandler(pc);
 	IF handler # -1 THEN (* Handler in the current PAF *)
		int.EIP := handler; handled := TRUE;
		SetTrapVariable(pc, fp); SetLastExceptionState(exc)
	ELSE			
		WHILE (fp # 0) & (handler = -1) DO				
			SYSTEM.GET(fp + 4, pc);
			pc := pc - 1; (*  CALL instruction, machine dependant!!! *)			
			handler := AosModules.GetExceptionHandler(pc);				
			sp :=  fp; (* Save the old framepointer into the stack pointer *)
			SYSTEM.GET(fp, fp) (* Unwind PAF *)
		END;	
		IF handler = -1 THEN 
			handled := FALSE;
		ELSE		
			int.EIP := handler; int.EBP := fp; int.ESP := sp;	
			SetTrapVariable(pc, fp); SetLastExceptionState(exc);
			handled := TRUE
		END
	END
END HandleException;

(* 	A simple introspection method, must be adapted if there are any changes to the
	refs section in a module. *)
PROCEDURE GetVariableAdr*(pc, fp: LONGINT;  varname: ARRAY OF CHAR ): LONGINT;
VAR 
	m: AosModules.Module;
	v: Variable;
	adr, pos, base: LONGINT;	
	name: ARRAY 256 OF CHAR;
	ch: CHAR;
BEGIN
	pos := -1;
	m := AosModules.ThisModuleByAdr(pc);
	IF m # NIL THEN			
		pos := FindProc(m.refs, pc - SYSTEM.ADR(m.code[0]));			
	
		IF pos # -1 THEN
					
			ch := m.refs[pos]; INC(pos);
			(* for variables *)	
			IF ch = "$" THEN 
				base := m.sb;
			ELSE 
				base := fp;
			END;	

			 (* Read the name *)			
			WHILE ch # 0X DO ch := m.refs[pos]; INC(pos) END;
						
			NextVar(m.refs, pos, base, name, v);		

			WHILE name[0] # 0X DO
				IF name = varname THEN
					RETURN v.adr;
				ELSE
					NextVar(m.refs, pos, base, name, v);		
				END							
			END	
		END
	END;		
	
	RETURN -1;

END GetVariableAdr;

(* Returns the name of the procedure the pc is in. Searchs in m.refs *)
TYPE Str128 = ARRAY 128 OF CHAR;
PROCEDURE GetProcedureName*(pc: LONGINT): Str128;
VAR
	methadr, i: LONGINT;
	ch: CHAR;
	name: Str128;
	m: AosModules.Module;
BEGIN
	m := AosModules.ThisModuleByAdr(pc);

	IF m # NIL THEN

		DEC(pc, SYSTEM.ADR(m.code[0]));

		methadr := FindProc(m.refs, pc);
		IF methadr # -1 THEN
			i := 0;
			ch := m.refs[methadr]; INC(methadr);				
			WHILE ch # 0X DO 
				name[i] := ch; 
				ch := m.refs[methadr]; 
				INC(methadr);
				INC(i);
			END;			
		END;		
		name[i] := 0X;	
	ELSE
		name := "Unkown"; (* Better: name := "" *)
	END;
	
	RETURN name;
END GetProcedureName;

PROCEDURE SetTrapVariable(pc, fp: LONGINT);
VAR
	varadr: LONGINT;
BEGIN
	varadr := GetVariableAdr(pc, fp, "trap"); 
	IF varadr # -1 THEN	
		SYSTEM.PUT8(varadr, 1)
	END
END SetTrapVariable;

(* Unbreakable stack trace back with regard to every FINALLY on the way *)
PROCEDURE Unbreakable(p: AosActive.Process; VAR int: AosInterrupts.State; VAR exc: AosInterrupts.ExceptionState; VAR handled: BOOLEAN);
VAR
	ebp, ebpSave, pc, handler, varoff, ebpBottom: LONGINT;
	hasFinally : BOOLEAN;	
BEGIN			
	ebp := int.EBP;
	pc := int.EIP;		
	hasFinally := FALSE;	
	
	handler := AosModules.GetExceptionHandler(pc);
	
	(* Handler in the current PAF *)
 	IF handler # -1 THEN
		int.EIP := handler;		
		hasFinally := TRUE;
		SetTrapVariable(pc, ebp);
	END;
	
	(* The first waypoint is the ebp of the top PAF *)
	ebpSave := ebp;
	
	WHILE (ebp # 0) DO
		(* Did we reach the last PAF? *)
		SYSTEM.GET(ebp, pc);
		IF (pc = 0) THEN			
			ebpBottom := ebp; (* Save the FP of the last PAF *)		
		END;

		(* Get the return pc *)
		SYSTEM.GET(ebp + 4, pc);

		handler := AosModules.GetExceptionHandler(pc);
		
		(* Save the last framepointer as stackpointer *)
		IF ~hasFinally THEN 
			int.ESP :=  ebp;
		END;		

		SYSTEM.GET(ebp, ebp);
		
		(* Here ebp may be 0. *)
		
		IF (handler # -1) & (ebp # 0)  THEN (* If AosActive.Terminate has a FINALLY this doesn't work !!! *)
			IF hasFinally THEN
				(* Connect Finally to Finally *)
				SYSTEM.PUT(ebpSave + 4, handler); (* Adapt the return pc *)
				SYSTEM.PUT(ebpSave, ebp); (* Adapt the dynamic link *)
				ebpSave := ebp;
			ELSE
				int.EIP := handler;
				int.EBP := ebp;
				ebpSave := ebp;				
				hasFinally := TRUE;
			END;					
			SetTrapVariable(pc, ebp)
		END
	END;
	
	(* Now ebp =  0, bottom of the stack, so link the last known return PC to the Termination *)
	IF ~hasFinally THEN
		SYSTEM.GET(ebpBottom + 4, pc); (* PC of the Terminate *)
		int.EIP := pc;	
		int.EBP := ebpBottom;	
	ELSIF ebpSave # ebpBottom THEN
		SYSTEM.GET(ebpBottom + 4, pc); (* PC of the Terminate *)
		SYSTEM.PUT(ebpSave + 4, pc);
		SetLastExceptionState(exc)
	END;		
	
	handled := TRUE; (* If FALSE the process could be restarted, may be this is the meaning? *)	
	
END Unbreakable;

(* General exception handler. *)
PROCEDURE Exception(VAR int: AosInterrupts.State);
VAR t: AosActive.Process; exc: AosInterrupts.ExceptionState; user, traceTrap, handled: BOOLEAN; sp: LONGINT;
BEGIN	(* interrupts off *)	
	t := AosActive.running[AosBoot.ID()];	(* t is running process *)
	handled := FALSE; 	
	AosInterrupts.GetExceptionState(int, exc);
	user := (int.CS MOD 4 > AosInterrupts.KernelLevel);
	traceTrap := (exc.locks = {}) & (exc.halt >= MAX(INTEGER)) & (exc.halt <= MAX(INTEGER)+1);

	Show(t, int, exc, exc.halt # MAX(INTEGER)+1);	(* Always show the trap info!*)
		
	IF exc.halt = haltUnbreakable THEN 
		Unbreakable(t, int, exc, handled)
	ELSIF ~ traceTrap THEN 
		HandleException( int, exc, handled) 
	END;				
			
	IF ~handled THEN 
		(* Taken from AosInterrupts to allow the FINALLY in the kernel *)
		exc.locks := AosLocks.BreakAll();
		SYSTEM.STI();
		IF ~traceTrap THEN	(* trap *)
			IF user THEN	(* return to outer level *)
				IF Trace THEN
					AosOut.Enter;
					AosOut.String("Jump");  AosOut.Hex(t.restartPC, 9);
					AosOut.Hex(t.restartSP, 9);  AosOut.Hex(t.stack.high, 9);
					AosOut.Exit
				END;
				INCL(int.EFLAGS, AosInterrupts.IFBit);	(* enable interrupts *)
				int.EBP := 0; int.ESP := t.restartSP;	(* reset stack *)
				int.EIP := t.restartPC;	(* restart object body or terminate *)
			ELSE	(* trap was in kernel (interrupt handler) *)	(* fixme: recover from trap in stack traceback *)
				AosOut.Enter;  AosOut.String("Kernel halt");  AosOut.Exit;
				AosBoot.Shutdown(FALSE)
			END		
		END			
	END;
	
	IF AosActive.PleaseHalt IN t.flags THEN 
		EXCL(t.flags, AosActive.PleaseHalt);
		IF AosActive.Unbreakable IN t.flags THEN EXCL(t.flags, AosActive.Unbreakable) END;
		IF AosActive.SelfTermination IN t.flags THEN EXCL(t.flags, AosActive.SelfTermination) END
	END
END Exception;

(* Get page fault address. *)

PROCEDURE -CR2(): LONGINT;
CODE {SYSTEM.i386, SYSTEM.Privileged}
	MOV EAX, CR2
END CR2;

(* Page fault handler. *)

PROCEDURE PageFault(VAR state: AosInterrupts.State);
VAR t: AosActive.Process;
BEGIN
	t := AosActive.running[AosBoot.ID()];
	IF AosInterrupts.IFBit IN state.EFLAGS THEN	(* enable interrupts again if they were enabled *)
		SYSTEM.STI()	(* avoid AosProcessors.StopAll deadlock when waiting for locks below (fixme: remove) *)
	END;
	IF (t = NIL) OR ~AosMemory.ExtendStack(t.stack, CR2()) THEN
		IF Trace THEN
			IF t = NIL THEN
				AosOut.Enter;  AosOut.String("GrowStack running=NIL");
				AosOut.Hex(state.EIP, 9);  AosOut.Exit
			ELSE
				AosOut.Enter;
				AosOut.String("GrowStack failed, pf="); AosOut.Hex(CR2(), 8);
				AosOut.String(" adr="); AosOut.Hex(t.stack.adr, 8);
				AosOut.String(" high="); AosOut.Hex(t.stack.high, 8);
				(*AosOut.Ln; AosOut.Memory(t.stack.adr, 256);*)
				AosOut.Exit
			END
		END;
		Exception(state)
	ELSE
		IF Trace THEN
			AosOut.Enter;  AosOut.String("GrowStack");
			AosOut.Hex(t.stack.adr, 9);  AosOut.Hex(t.stack.high, 9);  AosOut.Exit
		END
	END
END PageFault;

PROCEDURE Init;
VAR i: LONGINT; s: ARRAY 8 OF CHAR;
BEGIN
	IF TestTrap THEN
		AosBoot.GetConfig("TestTrap", s);
		IF s[0] = "1" THEN HALT(98) END
	END;
	AosIO.OpenWriter(w, AosOut.Send);
	FOR i := 0 TO AosBoot.MaxCPU-1 DO trapState[i] := 0 END;
	AosInterrupts.InstallHandler(PageFault, AosInterrupts.PF);
	FOR i := 0 TO 31 DO
		IF ~(i IN {AosInterrupts.PF}) THEN	(* PF handler above *)
			AosInterrupts.InstallHandler(Exception, i)
		END
	END;
	IF TestTrap & (s[0] = "2") THEN HALT(99) END
END Init;

BEGIN
	IF AosBoot.Trace THEN
		AosOut.Enter; AosOut.String("AosTrap"); AosOut.Exit
	END;
	modes := " rdy run awl awc awe rip";	(* 4 characters per mode from AosActive.Ready to AosActive.Terminated *)
	flags := "c!p!a!zstido";	(* bottom flags, !=reserved *)
	Init
END AosTrap.

(*
12.03.1998	pjm	Started
06.08.1998	pjm	Exported Show and removed AosException upcall installation & Modules lock
10.12.1998	pjm	New refblk
23.06.1999	pjm	State added
*)

(*
to do:
o stack overflow message is not correctly displayed in case of dynamic arrays (EDI = CR2, ESP # CR2)
o fix AosOut.Memory calls removed when switching to AosIO
o fix use of AosOutHigh lock in Show
o if allowing modification of variables using their descriptors, it should also have reference to module to avoid gc after free.
*)
