(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosBenchClockDrift;	(* pjm *)

(* Test clock drift on different processors. *)

IMPORT AosBoot, AosOut, AosKernel;

PROCEDURE Run*;
VAR t: HUGEINT; i: LONGINT; m: AosKernel.MilliTimer;
BEGIN
	FOR i := 1 TO 10 DO
		AosKernel.SetTimer(m, 1);
		REPEAT UNTIL AosKernel.Expired(m);
		t := AosBoot.GetTimer();
		AosKernel.SetTimer(m, 1000);
		REPEAT UNTIL AosKernel.Expired(m);
		t := AosBoot.SubH(AosBoot.GetTimer(), t);
		AosOut.Enter;
		AosOut.Int(AosBoot.HIntToLInt(t), 1);
		AosOut.Exit
	END
END Run;

END AosBenchClockDrift.

AosBenchClockDrift.Run
