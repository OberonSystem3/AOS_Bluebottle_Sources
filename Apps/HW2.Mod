MODULE HW2;

IMPORT
	AosOut, AosIO;
	
PROCEDURE HelloStream*(par : ANY) : ANY;
VAR w : AosIO.Writer;
	i : LONGINT;
BEGIN
	NEW(w, AosOut.Send, 128);
	
	w.String("Hello World"); 
	FOR i := 0 TO 9 DO
		w.Int(i, 0)
	END;
	w.Update;
	RETURN NIL
END HelloStream;


END HW2.
S.Free HW2~
HW2.HelloStream