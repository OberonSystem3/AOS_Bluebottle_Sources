MODULE WMInputModes;	(** AUTHOR "TF"; PURPOSE "Abstract input method editor"; *)

IMPORT
	AosModules, Utilities, AosTexts, WMTextView;

TYPE
	IME* = OBJECT
	VAR text- : AosTexts.Text; (* protected *)
		tv- : WMTextView.TextView; (* protected *)
		
		PROCEDURE GetName*() : Utilities.String;
		BEGIN
			RETURN NIL
		END GetName;	
		
		PROCEDURE Hide*;
		BEGIN
		END Hide;
		
		PROCEDURE SetCurrentText*(text : AosTexts.Text; tv : WMTextView.TextView);
		BEGIN
			SELF.text := text;
			SELF.tv := tv
		END SetCurrentText;
		
		PROCEDURE KeyEvent*(ucs : LONGINT; flags : SET; keysym : LONGINT);
		BEGIN
		END KeyEvent;
		
		PROCEDURE Finalize;
		BEGIN
		
		END Finalize;
		
		
	END IME;
	
VAR 
	defaultIME* : IME;
	
PROCEDURE GetIME*(name : ARRAY OF CHAR) : IME;
BEGIN
	RETURN defaultIME
END GetIME;

END WMInputModes.
