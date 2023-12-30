MODULE BeepTest; (** AUTHOR "afi"; PURPOSE "Hearing test using PC speaker"; *)

IMPORT AosBeep, AosKernel, AosOut;

VAR busy : BOOLEAN; timer : AosKernel.Timer;

PROCEDURE Go*(par : ANY) : ANY;
VAR i : LONGINT;
BEGIN
	IF ~busy THEN
		busy := TRUE;
		FOR i := 1 TO 20 DO	(* in 250Hz steps of 1 second *)
			AosOut.Int(i * 250, 5);
			AosBeep.Beep(i * 250);
			timer.Sleep(1000);
			AosBeep.Beep(0);
		END;
		AosOut.Ln;
		AosOut.String("Done");
		AosOut.Ln;
		busy := FALSE;
	END;
	RETURN NIL;
END Go;

BEGIN
	NEW(timer);
END BeepTest.

BeepTest.Go ~
S.Free BeepTest ~
