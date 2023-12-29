MODULE AosLocksStats;	(* pjm *)

IMPORT AosBoot, AosLocks, Fonts, Texts, Oberon, MathL;

VAR
	w: Texts.Writer;
	
PROCEDURE OutTime(t: HUGEINT; f: LONGINT);
BEGIN
	Texts.WriteLongRealFix(w, AosBoot.HIntToLReal(t), f, 0, 0)
END OutTime;

(*
PROCEDURE OutTime(t: HUGEINT; f: LONGINT);
VAR e, sign: LONGINT;
BEGIN
	sign := 1;
	IF t.high < 0 THEN
		IF (t.high = MIN(LONGINT)) & (t.low = 0) THEN INC(t.high) END;	(* approx *)
		AosFineTimer.Neg(t); sign := -1
	END;
	IF (t.high = 0) & (t.low >= 0) THEN	(* exact *)
		Texts.WriteInt(w, sign*t.low, f)
	ELSE	(* approx *)
		e := 0;
		REPEAT
			AosFineTimer.Div(t, AosFineTimer.ten); INC(e)	(* to do: rounding! *)
		UNTIL (t.high = 0) & (t.low >= 0);
		IF e > 9 THEN DEC(f) END;
		Texts.WriteInt(w, sign*t.low, f-3); Texts.WriteString(w, ".E"); Texts.WriteInt(w, e, 1)
	END
END OutTime;
*)

PROCEDURE Test(msg: ARRAY OF CHAR; high, low: LONGINT);
VAR t: HUGEINT;
BEGIN
	t := AosBoot.LInt2ToHInt(high, low);
	Texts.WriteHex(w, high); Texts.WriteHex(w, low);
	Texts.Write(w, " "); OutTime(t, 24);
	Texts.Write(w, " "); Texts.WriteString(w, msg); Texts.WriteLn(w)
END Test;

PROCEDURE TestOutTime*;
VAR t: Texts.Text;
BEGIN
	Test("0", 0, 0);
	Test("1", 0, 1);
	Test("2^31-1 = MAX(LONGINT)", 0, 7FFFFFFFH);
	Test("2^31", 0, 80000000H);
	Test("2^32-2", 0, -2);
	Test("2^32-1", 0, -1);
	Test("2^32", 1, 0);
	Test("2^32+1", 1, 1);
	Test("", 1, 7FFFFFFFH);
	Test("", 1, 80000000H);
	Test("", 1, -2);
	Test("", 1, -1);
	Test("", 7FFFFFFFH, 0);
	Test("", 7FFFFFFFH, 1);
	Test("", 7FFFFFFFH, 7FFFFFFFH);
	Test("", 7FFFFFFFH, 80000000H);
	Test("2^63-2", 7FFFFFFFH, -2);
	Test("2^63-1 = MAX(HUGEINT)", 7FFFFFFFH, -1);
	Test("-2^63 = MIN(HUGEINT)", 80000000H, 0);	(* rounding problem *)
	Test("", 80000000H, 1);
	Test("", 80000000H, 7FFFFFFFH);
	Test("", 80000000H, 80000000H);
	Test("", 80000000H, -2);
	Test("", 80000000H, -1);
	Test("", -1, 0);
	Test("", -1, 1);
	Test("", -1, 7FFFFFFFH);
	Test("", -1, 80000000H);
	Test("-2", -1, -2);
	Test("-1", -1, -1);
	NEW(t); Texts.Open(t, "");
	Texts.Append(t, w.buf);
	Oberon.OpenText("", t,  400, 400)
END TestOutTime;

PROCEDURE OutLock(i: LONGINT);
BEGIN
	CASE i OF
		AosLocks.AosOutLow: Texts.WriteString(w, "AosOutLow")
		|AosLocks.AosMemory: Texts.WriteString(w, "AosMemory")
		|AosLocks.AosHeap: Texts.WriteString(w, "AosHeap")
		|AosLocks.AosInterrupts: Texts.WriteString(w, "AosInterrupts")
		|AosLocks.AosModules: Texts.WriteString(w, "AosModules")
		|AosLocks.AosActive: Texts.WriteString(w, "AosActive")
		|AosLocks.AosProcessors: Texts.WriteString(w, "AosProcessors")
		|AosLocks.AosOutHigh: Texts.WriteString(w, "AosOutHigh")
		ELSE Texts.WriteString(w, "Level "); Texts.WriteInt(w, i, 1)
	END
END OutLock;

PROCEDURE ShowStats*;	(** [MHz] *)
CONST W = 12;
VAR i, j: LONGINT; mhz: HUGEINT; s: Texts.Scanner; t: Texts.Text;

	PROCEDURE WriteLabel(s: ARRAY OF CHAR);
	VAR i: LONGINT;
	BEGIN
		i := 0; WHILE s[i] # 0X DO INC(i) END;
		WHILE i < W DO Texts.Write(w, " "); INC(i) END;
		Texts.WriteString(w, s)
	END WriteLabel;
	
	PROCEDURE WriteTime(x: LONGREAL; n: LONGINT);
	BEGIN
		Texts.Write(w, " "); DEC(n);
		IF AosBoot.HIntToLInt(mhz) # 0 THEN
			Texts.WriteLongRealFix(w, x/AosBoot.HIntToLReal(mhz), n, 1, 0)
		ELSE
			Texts.WriteLongRealFix(w, x, n, 0, 0)
		END
	END WriteTime;

	PROCEDURE WriteMMV(n: LONGINT; sum, sum2, max: HUGEINT);
	VAR num, tmp1: HUGEINT; var: LONGREAL;
	BEGIN
		num := AosBoot.LIntToHInt(n);
		WriteTime(AosBoot.HIntToLReal(AosBoot.DivH(sum, num)), W);	(* mean *)
		WriteTime(AosBoot.HIntToLReal(max), W);	(* max *)
		IF n > 1 THEN
			tmp1 := AosBoot.DivH(sum, num);
			tmp1 := AosBoot.MulH(num, AosBoot.MulH(tmp1, tmp1));
				(* tmp1 := num*mean^2 *)
			tmp1 := AosBoot.SubH(sum2, tmp1);
				(* tmp1 := sumsqr - num*mean^2 *)
			tmp1 := AosBoot.DivH(tmp1, AosBoot.SubH(num, AosBoot.LIntToHInt(1)));
				(* tmp1 := (sumsqr - num*mean^2)/(num-1) *)
			var := AosBoot.HIntToLReal(tmp1);
			IF var >= 0 THEN var := MathL.sqrt(var) ELSE var := 0 END
		ELSE
			var := 0
		END;
		WriteTime(var, W)	(* variance *)
	END WriteMMV;
	
	PROCEDURE WriteStats(stats: AosLocks.LockStats; proc, lock: LONGINT);
	VAR n: LONGINT;
	BEGIN
		n := stats.numReleases;
		IF n # 0 THEN
(*			WriteMMV(n, stats.sumHeldTime, stats.sumSqrHeldTime, stats.maxHeldTime); *)
			WriteMMV(n, stats.sumWaitTime, stats.sumSqrWaitTime, stats.maxWaitTime);
			Texts.Write(w, " "); Texts.WriteInt(w, n, W-1);	(* num *)
			Texts.Write(w, " "); Texts.WriteInt(w, proc, 1);	(* processor *)
			Texts.Write(w, " "); OutLock(lock);	(* lock *)
			Texts.WriteLn(w)
		END
	END WriteStats;
	
BEGIN
	t := Oberon.Par.text;	(* check if command was executed in "our" text *)
	Texts.OpenScanner(s, t, 0); Texts.Scan(s);
	IF (s.class # Texts.Name) OR (s.s # "MeanHeld") THEN t := NIL END;
		(* get parameter *)
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(s);
	IF s.class # Texts.Int THEN s.i := 0 END;
	mhz := AosBoot.LIntToHInt(s.i);
		(* write stats *)
	WriteLabel("MeanHeld"); WriteLabel("MaxHeld"); WriteLabel("VarHeld");
	WriteLabel("MeanWait"); WriteLabel("MaxWait"); WriteLabel("VarWait");
	WriteLabel("Count"); Texts.WriteString(w, " P Lock"); Texts.WriteLn(w);
	FOR i := 0 TO LEN(AosLocks.lock)-1 DO
		FOR j := 0 TO LEN(AosLocks.lock[i].stats)-1 DO
			WriteStats(AosLocks.lock[i].stats[j], j, i)
		END
	END;
	Texts.WriteLn(w);
	IF AosBoot.HIntToLInt(mhz) # 0 THEN
		Texts.WriteString(w, "Times in microseconds calculated at clock rate ");
		Texts.WriteInt(w, AosBoot.HIntToLInt(mhz), 1); Texts.WriteString(w, "MHz")
	ELSE
		Texts.WriteString(w, "Times in clock cycles")
	END;
	Texts.WriteLn(w); Texts.WriteLn(w); Texts.WriteString(w, "AosLocksStats.ShowStats ");
	Texts.WriteInt(w, AosBoot.HIntToLInt(mhz), 1);
		(* open or update text *)
	IF t = NIL THEN
		NEW(t); Texts.Open(t, "");
		Texts.Append(t, w.buf);
		Oberon.OpenText("", t,  400, 400)
	ELSE
		Texts.Delete(t, 0, t.len);
		Texts.Append(t, w.buf)
	END
END ShowStats;

BEGIN
	Texts.OpenWriter(w); Texts.SetFont(w, Fonts.This("Courier8.Scn.Fnt"))
END AosLocksStats.

AosLocksStats.TestOutTime

AosLocks.ClearLockStats

AosLocksStats.ShowStats
AosLocksStats.ShowStats 180
AosLocksStats.ShowStats 700

Configuration.DoCommands
AosActive.ClearCounters
System.State AosActive
~
