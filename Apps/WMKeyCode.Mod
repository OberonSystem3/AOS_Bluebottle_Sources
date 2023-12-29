MODULE WMKeyCode;	(** AUTHOR "TF"; PURPOSE "Display key code of a pressed key"; *)
(* TF 28.09.2000 *)
(* 12.12.2002 rewritten for new WM *)

IMPORT AosCommands, WMWindowManager, WMRestorable, WMMessages,  WMGraphics, AosInputs, 
	AosModules, WMRectangles, Utilities;

TYPE 
	Window = OBJECT(WMWindowManager.BufferWindow)
	
		PROCEDURE &New(c : WMRestorable.Context);
		BEGIN				
			Init(300, 32, FALSE);
			canvas.Fill(WMRectangles.MakeRect(0,0, img.width, img.height), 0FFFFFFFFH, WMGraphics.ModeCopy);
			SetTitle(Utilities.NewString("Key Code Display"));
			IF c # NIL THEN WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame})				
			ELSE WMWindowManager.DefaultAddWindow(SELF)
			END;
		END New;
		
		PROCEDURE KeyEvent(ucs : LONGINT; flags : SET; keysym : LONGINT);
		VAR t : ARRAY 10 OF CHAR;
			font : WMGraphics.Font;
			x, y : LONGINT;
			
			PROCEDURE WriteString(s : ARRAY OF CHAR);
			VAR dx, dy : LONGINT;
			BEGIN
				font.GetStringSize(s, dx, dy);
				canvas.DrawString(x, y, s); INC(x, dx)
			END WriteString;
		BEGIN
			font := canvas.GetFont();			
			x := 3; y := 14;
			canvas.Fill(WMRectangles.MakeRect(0,0, img.width, img.height), 0FFFFFFFFH, WMGraphics.ModeCopy);
			IF keysym # 0 THEN 	
				WriteString("Key:");
				IF flags * {AosInputs.LeftShift} # {} THEN WriteString("LeftShift ") END;
				IF flags * {AosInputs.RightShift} # {} THEN WriteString("RightShift ") END;
				IF flags * {AosInputs.LeftCtrl} # {} THEN WriteString("LeftCtrl ") END;
				IF flags * {AosInputs.RightCtrl} # {} THEN WriteString("RightCtrl ") END;
				IF flags * {AosInputs.LeftAlt} # {} THEN WriteString("LeftAlt ") END;
				IF flags * {AosInputs.RightAlt} # {} THEN WriteString("RightAlt ") END;
				IF flags * {AosInputs.LeftMeta} # {} THEN WriteString("LeftMeta ") END;
				IF flags * {AosInputs.RightMeta} # {} THEN WriteString("RightMeta ") END;
				WriteString("'"); t[0] := CHR(ucs); t[1] := 0X; WriteString(t); WriteString("' (");
				Utilities.IntToHexStr(ucs, 0, t); WriteString(t); WriteString(")");
				
				x := 3; y := 14 + 14;
				WriteString("keysym:");
				Utilities.IntToHexStr(keysym, 0, t);
				WriteString(t)
			END;
			Invalidate(WMRectangles.MakeRect(0,0, img.width, img.height))
		END KeyEvent;

		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("WMKeyCode", "WMKeyCode.Open", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;			
		
		PROCEDURE Close();
		BEGIN
			w := NIL; 
			Close^
		END Close;
		
	END Window;

VAR w : Window;
	
PROCEDURE Close*(par : PTR) : PTR;
BEGIN {EXCLUSIVE}
	IF w # NIL THEN w.Close END;
	RETURN NIL
END Close;

PROCEDURE Open*(par: PTR): PTR;
BEGIN{EXCLUSIVE}
	IF w # NIL THEN RETURN NIL END;
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(w, par(WMRestorable.Context)) 
	ELSE NEW(w, NIL)		
	END;
	RETURN NIL
END Open;
	
PROCEDURE Cleanup;
BEGIN
	IF Close(NIL) = NIL THEN END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMKeyCode.

WMKeyCode.Open ~

S.Free WMKeyCode ~