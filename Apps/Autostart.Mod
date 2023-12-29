(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE Autostart; (** AUTHOR "be"; PURPOSE "Execute the commands in the Autostart section of AosConfig.XML"; *)

IMPORT XML, XMLObjects, AosCommands, AosConfig, AosOut;

CONST
	Trace = TRUE;

PROCEDURE Run*(par: PTR): PTR;
VAR enum: XMLObjects.Enumerator; p: PTR; e: XML.Element; value: XML.String;
	autostart : XML.Element; 
	msg: ARRAY 128 OF CHAR; res: LONGINT;
BEGIN
	autostart := AosConfig.GetNamedElement(AosConfig.config.GetRoot(), "Section", "Autostart");
	IF autostart # NIL THEN
		enum := autostart.GetContents();
		WHILE enum.HasMoreElements() DO
			p := enum.GetNext();
			IF p IS XML.Element THEN
				e := p(XML.Element); value := e.GetAttributeValue("value");
				IF (value^ # "") THEN
					IF Trace THEN AosOut.String("Autostart: executing "); AosOut.String(value^); AosOut.Ln END;
					AosCommands.Call(value^, {AosCommands.Wait}, res, msg);
					IF (res # 0) THEN	
						AosOut.String("Autostart: error executing "); AosOut.String(value^); AosOut.String(": ");
						IF (msg # "") THEN AosOut.String(msg)
						ELSE AosOut.String("res = "); AosOut.Int(res, 0)
						END;
						AosOut.Ln
					END	
				END		
			END	
		END
	END;	
	RETURN NIL
END Run;

END Autostart.

System.Free Autostart ~

EditTools.OpenAscii AosConfig.XML~
AosConfig.Init

Aos.Call Autostart.Run ~
