MODULE HW3;

IMPORT
	WMDialogs;
	
PROCEDURE Hello*(par : ANY) : ANY;
VAR name : ARRAY 32 OF CHAR;
BEGIN
	IF WMDialogs.QueryString("What is your name ?", name) = WMDialogs.ResOk THEN
		IF WMDialogs.Message("Hello", name, {WMDialogs.ResOk}) = WMDialogs.ResOk THEN
		
		END;
	ELSE
		IF WMDialogs.Message("Arrgh", "You need to press Ok otherwise it is aborted", {WMDialogs.ResOk}) = WMDialogs.ResOk THEN
		
		END;	
	END;
	RETURN NIL
END Hello;


END HW3.
S.Free HW3~
HW3.Hello l