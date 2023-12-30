MODULE WMGraphicsDemo;	(** AUTHOR "TF"; PURPOSE "Example program"; *)

IMPORT WMWindowManager, Utilities, WMGraphics, WMRectangles, AosModules, WMDialogs, Math, AosKernel;

CONST
	ShortFrameDelay = 10; (* ms *)
	LongFrameDelay = 20; (* ms *)
 
TYPE 
	TestWindow = OBJECT (WMWindowManager.DoubleBufferWindow);
	VAR lx, ly : LONGINT; 
		bild : WMGraphics.Image;
		timer : AosKernel.Timer;
					
		PROCEDURE &New();
		BEGIN
			bild := WMGraphics.LoadImage("BluebottlePic0.png", TRUE);
			Init(bild.width, bild.height, FALSE);
			WMWindowManager.ExtAddWindow(SELF, 200, 200, {WMWindowManager.FlagFrame});
			SetTitle(Utilities.NewString("WMGraphics Demo"));
			canvas.Fill(WMRectangles.MakeRect(0, 0, bild.width, bild.height), WMGraphics.White, WMGraphics.ModeCopy);
			Invalidate(WMRectangles.MakeRect(0, 0, bild.width, bild.height));
			SetPointerInfo(manager.pointerCrosshair);
			NEW(timer);
		END New;
		
		(* Calculate a polygon in form of a circle *)
		PROCEDURE MakeCircle(x, y, r, nofPoints: LONGINT; VAR p : ARRAY OF WMGraphics.Point2d);
		VAR i : LONGINT;
			inv : REAL;
		BEGIN
			inv := 2 * Math.pi / nofPoints;
			FOR i := 0 TO nofPoints - 1 DO 
				p[i].x := x + ENTIER(r * Math.cos(i * inv));
				p[i].y := y + ENTIER(r * Math.sin(i * inv));
			END
		END MakeCircle;
		
		PROCEDURE Filler(canvas : WMGraphics.Canvas; y, x0, x1 : LONGINT);
		BEGIN
			canvas.ScaleImage(bild, WMRectangles.MakeRect(x0, y, x1 + 1, y + 1), 
				WMRectangles.MakeRect(x0, y, x1 + 1, y + 1), WMGraphics.ModeCopy, WMGraphics.ScaleBox);
		END Filler;
		
		PROCEDURE Clear;
		BEGIN
			canvas.Fill(WMRectangles.MakeRect(0, 0, bild.width, bild.height), WMGraphics.White, WMGraphics.ModeCopy);
		END Clear;

		PROCEDURE FillDemo;
		VAR circle : ARRAY  64 OF WMGraphics.Point2d;
			x , y, r, i : LONGINT;
		BEGIN
			x := bild.width DIV 2;
			y := bild.height DIV 2;
			r := bild.height DIV 2 - 1;;
			FOR i := 3 TO 63 DO
				MakeCircle(x, y, r, i, circle);
				Clear;
				canvas.FillPolygonFlat(circle, i, WMGraphics.Red, WMGraphics.ModeCopy);
				Swap;
				Invalidate(WMRectangles.MakeRect(0, 0, bild.width, bild.height));
				timer.Sleep(LongFrameDelay)
			END;

			FOR i := r TO 0 BY -1 DO
				MakeCircle(x, y, i, 63, circle);
				Clear;
				canvas.FillPolygonFlat(circle, 63, WMGraphics.Red, WMGraphics.ModeCopy);
				Swap;
				Invalidate(WMRectangles.MakeRect(0, 0, bild.width, bild.height));
				timer.Sleep(ShortFrameDelay);
			END;
			
			FOR i := 0 TO r DO
				MakeCircle(x, y, i, 63, circle);
				Clear;
				canvas.FillPolygonCB(circle, 63, Filler);
				Swap;
				Invalidate(WMRectangles.MakeRect(0, 0, bild.width, bild.height));
				timer.Sleep(ShortFrameDelay);
			END;

			FOR i := r TO r DIV 2 BY -1 DO
				MakeCircle(x, y, i, 63, circle);
				Clear;
				canvas.FillPolygonCB(circle, 63, Filler);
				Swap;
				Invalidate(WMRectangles.MakeRect(0, 0, bild.width, bild.height));
				timer.Sleep(ShortFrameDelay);
			END;

			FOR i := x TO bild.width - r DIV 2 - 1 DO
				MakeCircle(i, y, r DIV 2, 63, circle);
				Clear;
				canvas.FillPolygonCB(circle, 63, Filler);
				Swap;
				Invalidate(WMRectangles.MakeRect(0, 0, bild.width, bild.height));
				timer.Sleep(ShortFrameDelay);
			END;

			FOR i := bild.width - r DIV 2- 1 TO x BY -1 DO
				MakeCircle(i, y, r DIV 2, 63, circle);
				Clear;
				canvas.FillPolygonCB(circle, 63, Filler);
				Swap;
				Invalidate(WMRectangles.MakeRect(0, 0, bild.width, bild.height));
				timer.Sleep(ShortFrameDelay);
			END;

			FOR i := r DIV 2 TO 0 BY -1 DO
				MakeCircle(x, y, i, 63, circle);
				Clear;
				canvas.FillPolygonCB(circle, 63, Filler);
				Swap;
				Invalidate(WMRectangles.MakeRect(0, 0, bild.width, bild.height));
				timer.Sleep(ShortFrameDelay);
			END;
			
		END FillDemo;
		
		PROCEDURE TheEnd;
		BEGIN
			canvas.DrawImage(0, 0, bild, WMGraphics.ModeCopy);
			canvas.Fill(WMRectangles.MakeRect(100, bild.height DIV 2 - 20, bild.width - 100, bild.height DIV 2 + 20), 0FFFFFF80H, WMGraphics.ModeSrcOverDst);
			canvas.SetFont(WMGraphics.GetFont("Oberon", 20, {WMGraphics.FontBold}));
			canvas.DrawString(bild.width DIV 2 - 40, bild.height DIV 2 + 5 ,  "The End");
			Swap;
			Invalidate(WMRectangles.MakeRect(0, 0, bild.width, bild.height))
		END TheEnd;
		
	
	BEGIN
		FillDemo;
		TheEnd
	END TestWindow;
	
VAR s : TestWindow;

PROCEDURE Open*(par : ANY): ANY;
BEGIN {EXCLUSIVE}
	IF s # NIL THEN s.Close END; NEW(s); RETURN NIL
END Open;

PROCEDURE Cleanup;
BEGIN
	IF s # NIL THEN s.Close END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMGraphicsDemo.

S.Free WMGraphicsDemo ~
WMGraphicsDemo.Open ~
