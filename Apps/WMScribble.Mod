MODULE WMScribble;	(** AUTHOR "TF"; PURPOSE "Example program"; *)

IMPORT WMWindowManager, Utilities, WMGraphics, WMRectangles, AosModules, WMDialogs, Raster;
 
TYPE 
	ScribbleWindow = OBJECT (WMWindowManager.BufferWindow);
	VAR lx, ly : LONGINT; down : BOOLEAN;
				
	     PROCEDURE &New();
	     BEGIN
			Init(400, 400, FALSE);
			WMWindowManager.ExtAddWindow(SELF, 200, 200, {WMWindowManager.FlagFrame});
			SetTitle(Utilities.NewString("Scribble Example"));
			canvas.Fill(WMRectangles.MakeRect(0, 0, GetWidth(), GetHeight()), 0FFFFFFFFH, WMGraphics.ModeCopy);
			Invalidate(WMRectangles.MakeRect(0, 0, GetWidth(), GetHeight()))
	     END New;
	 
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET);
		BEGIN
			IF down THEN canvas.Line(lx, ly, x, y, 00000FFFFH, WMGraphics.ModeSrcOverDst);
				Invalidate(
					WMRectangles.MakeRect(Utilities.Min(lx, x), Utilities.Min(ly, y), Utilities.Max(lx, x) + 1, Utilities.Max(ly, y) + 1)
				)
			 END;
			lx := x; ly := y
		END PointerMove;
	      
		PROCEDURE PointerDown(x, y : LONGINT; keys : SET);
		BEGIN
			lx := x; ly := y; down := 0 IN keys;
			IF 2 IN keys THEN 
				canvas.Fill(WMRectangles.MakeRect(0, 0, GetWidth(), GetHeight()), 0FFFFFFFFH, WMGraphics.ModeCopy);
				Invalidate(WMRectangles.MakeRect(0, 0, GetWidth(), GetHeight()))
			END
		END PointerDown;
		
		PROCEDURE PointerUp(x, y : LONGINT; keys : SET);
		BEGIN down := 0 IN keys
		END PointerUp;
		
		PROCEDURE KeyEvent(ucs : LONGINT; flags : SET; keySym : LONGINT);
		VAR res: BOOLEAN; filename : ARRAY 128 OF CHAR;
		BEGIN
			IF ucs = ORD("s") THEN
				filename := "scribble.bmp";
				IF WMDialogs.QueryString("Save as :", filename) = WMDialogs.ResOk THEN
					Raster.Store(img, "scribble.bmp", res)
				END
			END
		END KeyEvent;
	END ScribbleWindow;
	
VAR s : ScribbleWindow;

PROCEDURE Open*(par : PTR): PTR;
BEGIN
	IF s # NIL THEN s.Close END; NEW(s); RETURN NIL
END Open;

PROCEDURE Cleanup;
BEGIN
	IF s # NIL THEN s.Close END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMScribble.

S.Free WMScribble ~
WMScribble.Open ~
WMPicView.Open scribble.bmp ~