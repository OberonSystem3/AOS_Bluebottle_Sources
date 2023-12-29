MODULE AosBenchPingPong;	(* pjm *)

(* Test process ping-pong. *)

IMPORT AosOut, AosActive, AosIO, AosCommands, AosKernel;

CONST
	MaxProcs = 1024;

TYPE
	Yielder = OBJECT
		VAR count: LONGINT; done: BOOLEAN;
		
		PROCEDURE &Init;
		BEGIN
			done := FALSE
		END Init;
		
		PROCEDURE Join;
		BEGIN {EXCLUSIVE}
			AWAIT(done)
		END Join;
	
	BEGIN {ACTIVE, PRIORITY(AosActive.Low)}
		WHILE wait DO AosActive.Yield END;
		WHILE run DO INC(count); AosActive.Yield END;
		BEGIN {EXCLUSIVE} done := TRUE END
	END Yielder;

VAR
	wait, run: BOOLEAN;

PROCEDURE Test1*(par: PTR): PTR;	(* procs ms *)
VAR r: AosIO.StringReader; n, t, i, total: LONGINT; timer: AosKernel.Timer; p: ARRAY MaxProcs OF Yielder;
BEGIN
	NEW(r, 1024);
	r.Set(par(AosCommands.Parameters).str^);
	r.SkipSpaces; r.Int(n, FALSE);
	r.SkipSpaces; r.Int(t, FALSE);
	(*AosOut.Int(n, 5); AosOut.Int(t, 5); AosOut.Int(r.res, 5); AosOut.Ln;*)
	IF (r.res = 0) & (n >= 1) & (n <= LEN(p)) & (t > 0) THEN
		AosOut.String("Test1 "); AosOut.Int(n, 1); AosOut.Char(" "); AosOut.Int(t, 1);
		wait := TRUE; run := TRUE;
		FOR i := 0 TO n-1 DO NEW(p[i]) END;
		NEW(timer);
		wait := FALSE; timer.Sleep(t); run := FALSE;
		FOR i := 0 TO n-1 DO p[i].Join END;
		total := 0;
		FOR i := 0 TO n-1 DO INC(total, p[i].count) END;
		AosOut.Char(" "); AosOut.Int(total, 1);
		FOR i := 0 TO n-1 DO
			AosOut.Char(" "); AosOut.Int(p[i].count, 1)
		END;
		AosOut.Ln
	END;
	RETURN NIL
END Test1;

END AosBenchPingPong.

System.Free AosBenchPingPong ~

Aos.Call AosBenchPingPong.Test1 2 1000
Aos.Call AosBenchPingPong.Test1 3 1000
Aos.Call AosBenchPingPong.Test1 4 1000
Aos.Call AosBenchPingPong.Test1 5 1000
Aos.Call AosBenchPingPong.Test1 6 1000
Aos.Call AosBenchPingPong.Test1 7 1000
Aos.Call AosBenchPingPong.Test1 8 1000
Aos.Call AosBenchPingPong.Test1 64 1000
Aos.Call AosBenchPingPong.Test1 1024 1000

Aos.Call AosBenchPingPong.Test1 2 10000
Aos.Call AosBenchPingPong.Test1 4 10000
