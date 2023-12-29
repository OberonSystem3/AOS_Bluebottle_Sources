MODULE DbgOut;	(** TF **)

IMPORT
	MultiLogger, AosIO, Utilities;

VAR
	lw : MultiLogger.LogWindow;
	w : AosIO.Writer;
	
PROCEDURE LongReal*(l : LONGREAL; x : LONGINT);
VAR str : ARRAY 32 OF CHAR;
BEGIN {EXCLUSIVE}
	Utilities.FloatToStr(l, x, x - 1, 0, str);
	w.String(str);
	w.Update
END LongReal;

PROCEDURE LongRealFix*(l : LONGREAL; x, y : LONGINT);
VAR str : ARRAY 32 OF CHAR;
BEGIN {EXCLUSIVE}
	Utilities.FloatToStr(l, x, y, 0, str);
	w.String(str);
	w.Update
END LongRealFix;

PROCEDURE String*(str : ARRAY OF CHAR);
BEGIN
	w.String(str); w.Update
END String;

PROCEDURE Int*(i, s : LONGINT);
BEGIN
	w.Int(i, s); w.Update
END Int;

PROCEDURE Ln*;
BEGIN
	w.Ln;
	w.Update
END Ln;

PROCEDURE Open*;
BEGIN {EXCLUSIVE}
	NEW(lw, "CAPO Log", w);
END Open;

BEGIN
	Open
END DbgOut.
 