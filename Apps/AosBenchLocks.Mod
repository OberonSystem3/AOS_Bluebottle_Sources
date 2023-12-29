MODULE AosBenchLocks;	(* pjm *)

(* Test lock performance *)

IMPORT AosIO, AosLocks, AosOut, AosKernel, AosCommands;

CONST
	Level = AosLocks.AosOutHigh;
	
PROCEDURE TestAcquire*(par: PTR): PTR;	(* num *)
VAR s: AosIO.StringReader; i, n, t: LONGINT;
BEGIN
	NEW(s, LEN(par(AosCommands.Parameters).str^));
	s.Set(par(AosCommands.Parameters).str^);
	s.SkipSpaces; s.Int(n, FALSE);
	IF n > 0 THEN
		i := AosKernel.GetTimer();
		REPEAT t := AosKernel.GetTimer() UNTIL t # i;
		FOR i := 1 TO n DO
			AosLocks.Acquire(Level);
			AosLocks.Release(Level)
		END;
		t := AosKernel.GetTimer() - t;
		AosOut.Enter;
		AosOut.Int(n, 1); AosOut.String(" loops, ");
		AosOut.Int(t*1000 DIV AosKernel.second, 1); AosOut.String(" ms");
		AosOut.Exit
	END;
	RETURN NIL
END TestAcquire;

END AosBenchLocks.

System.Free AosBenchLocks ~

System.OpenKernelLog

Configuration.DoCommands
System.Time start
Aos.Call \w AosBenchLocks.TestAcquire 1000000 ~
System.Time lap
~

{P1 1000000 loops, 6105 ms} with Stats and nestCount
{P1 1000000 loops, 6005 ms} removed nestCount
{P1 1000000 loops, 2270 ms} disabled Stats
{P1 1000000 loops, 2201 ms} added quick acquire
