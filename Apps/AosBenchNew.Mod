MODULE AosBenchNew;	(* pjm *)

(* Test memory allocation performance. *)

IMPORT AosOut, AosKernel, AosCommands;

PROCEDURE TestNew*(par: PTR): PTR;
VAR s: AosCommands.Parameters; i, n, t: LONGINT;
BEGIN
	s := par(AosCommands.Parameters);
	i := AosKernel.GetTimer();
	REPEAT t := AosKernel.GetTimer() UNTIL t # i;
	t := AosKernel.GetTimer() - t;
	AosOut.Enter;
	AosOut.Int(n, 1); AosOut.String(" loops, ");
	AosOut.Int(t*1000 DIV AosKernel.second, 1); AosOut.String(" ms");
	AosOut.Exit;
	RETURN NIL
END TestNew;

END AosBenchNew.
