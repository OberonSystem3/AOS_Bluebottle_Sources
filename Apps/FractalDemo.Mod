MODULE FractalDemo;	(** AUTHOR "TF"; PURPOSE "Draw Mandelbrot-Set using n - processors (otherwise not optimized)"; *)

IMPORT
	AosIO, AosModules, AosActive,  WMComponents,  WMGraphics, WMGraphicUtilities, Raster, AosOut, 
	AosKernel, Utilities, Math, WMProperties, Classes := TFClasses, WMRectangles;

CONST MaxIter = 2048;

TYPE 
	String = Utilities.String;
	WorkUnit = POINTER TO RECORD
		terminate : BOOLEAN;
		x0, y0, x1, y1: LONGREAL;
		w, h, maxIter, ys, ye : LONGINT;
		result : POINTER TO ARRAY OF LONGINT;
		next : WorkUnit;
	END;
	
	WorkUnitQ = OBJECT
		VAR work: WorkUnit;
		
		PROCEDURE Add*(wu : WorkUnit);
		BEGIN {EXCLUSIVE}
			wu.next := work; work := wu
		END Add;
		
		PROCEDURE Get() : WorkUnit;
		VAR result:WorkUnit;
		BEGIN {EXCLUSIVE}
			AWAIT(work # NIL);
			result := work; work := work.next;
			RETURN result
		END Get;
	END WorkUnitQ; 
	
	CalcThread = OBJECT
		VAR
			alive : BOOLEAN;
			i, j : LONGINT;
			dx, dy : LONGREAL;
			wu : WorkUnit;
			workQ, resultQ : WorkUnitQ;
			x, y : LONGREAL;
	
		PROCEDURE &Init(workQ, resultQ:WorkUnitQ);
		BEGIN
			alive := TRUE; SELF.workQ := workQ; SELF.resultQ := resultQ
		END Init;
		
		PROCEDURE StartWork;
		BEGIN
			NEW(wu.result, wu.w * wu.h);
			dx := (wu.x1 - wu.x0) / wu.w; dy := (wu.y1 - wu.y0) / wu.h
		END StartWork;
		
		PROCEDURE Finished;
		BEGIN {EXCLUSIVE}
			alive := FALSE 
		END Finished;
		
		PROCEDURE AwaitFinished;
		BEGIN {EXCLUSIVE}
			AWAIT(~alive)
		END AwaitFinished;
		
		PROCEDURE Calc(x, y : LONGREAL) : LONGINT;
		VAR re, im, re2, im2 : LONGREAL; i : LONGINT;
		BEGIN
			re := x; im := y; i := 1; 
			WHILE i < wu.maxIter DO
				re2 := re * re; im2 := im * im;
				IF re2 + im2 > 4 (* out *) THEN RETURN i END;
				im := 2 * re * im + y;
				re := re2 - im2 + x;
				INC(i)
			END;
			RETURN 0
		END Calc;
	
	BEGIN {ACTIVE, PRIORITY(AosActive.Low)}
		WHILE alive DO
			wu := workQ.Get();
			IF wu.terminate THEN alive := FALSE 
			ELSE
				StartWork;
				y := wu.y0; i := 0;
				WHILE (i < wu.h) DO
					j := 0;
					x := wu.x0;
					WHILE (j < wu.w) DO
						wu.result[i * wu.w + j] := Calc(x, y); 
						x := x + dx;
						INC(j)
					END;
					y := y + dy;
					INC(i)
				END;
				wu.next := NIL;
				resultQ.Add(wu)
			END	
		END;
		Finished
	END CalcThread;
	
	List = POINTER TO RECORD
		next: List;
		x0,x1,y0,y1: LONGREAL;
		depth: LONGINT;
	END;
	
	MandelbrotSetViewer = OBJECT (WMComponents.VisualComponent)
	VAR
		ct : Classes.List;
		nofProcesses : WMProperties.Int32Property;
		backBmp : Raster.Image;
		bc : WMGraphics.BufferCanvas;
		dy : LONGREAL;
		list, l : List;
		
		selecting : BOOLEAN;
		x0, y0, x1, y1 : LONGINT;
		
		palette : ARRAY MaxIter OF WMGraphics.Color;
	
		workQ, resultQ : WorkUnitQ;
		recalcNeeded, alive, calculating : BOOLEAN;
		
		PROCEDURE &Init;
		VAR i:LONGINT;
			x: INTEGER;
		BEGIN
			Init^;
			NEW(backBmp);
			NEW(nofProcesses, PrototypeNofProcesses, NIL, NIL); properties.Add(nofProcesses);

			NEW(list);
			list.x0 := -2; list.y0 := -2; list.x1 := 2; list.y1 := 2;
			list.depth := MaxIter;
			(* calculate a "nice" palette *)
			FOR i := 0 TO MaxIter-1 DO
				x := SHORT(ENTIER(200 * Math.sqrt(Math.sqrt(Math.sin(i / MaxIter*Math.pi / 2))))) + 55;
				palette[i] := WMGraphics.RGBAToColor(x, x*2 MOD 255, x*4 MOD 255, 255)
			END;
			alive := TRUE; calculating := FALSE
		END Init;
		
		PROCEDURE Recalc;
		VAR w, dh, h, th, p, i, j, y, c, maxIter : LONGINT;
			str : ARRAY 32 OF CHAR;
			t : AosKernel.MilliTimer;
			t2 : LONGINT;
			processes : POINTER TO ARRAY OF CalcThread;
			wu : WorkUnit;
		BEGIN
			IF bc = NIL THEN recalcNeeded := FALSE; RETURN END;
			calculating := TRUE;
			Invalidate;
			w := bounds.GetWidth(); h := bounds.GetHeight();
			IF w <= 0 THEN w := 1 END; IF h <= 0 THEN h := 1 END;
			
			NEW(workQ); NEW(resultQ);
			NEW(processes, nofProcesses.Get());
			AosKernel.SetTimer(t, 0);

			(* initialize processes *)
			FOR p := 0 TO nofProcesses.Get() - 1 DO NEW(processes[p], workQ, resultQ) END;
			
			dy := (list.y1 - list.y0) / h; 
			(* fill workQ *)
			FOR i := 0 TO h - 1 DO 
				NEW(wu);
				wu.x0 := list.x0; wu.y0 := list.y0 + dy * i; wu.x1 := list.x1; wu.y1 := wu.y0 + dy; 
				wu.h := 1; wu.w := w; wu.ys := i; wu.ye := i;
				wu.maxIter := list.depth;
				workQ.Add(wu)
			END;
		
			(* empty resultQ *)
			FOR i := 0 TO h - 1 DO
				wu := resultQ.Get();
				FOR j := 0 TO wu.w - 1 DO  
					bc.SetPixel(j, wu.ys, palette[wu.result[j] MOD MaxIter], WMGraphics.ModeCopy)
				END
			END;
			
			(* send killer workunits *)
			FOR i := 0 TO nofProcesses.Get() - 1 DO 
				NEW(wu); wu.terminate := TRUE;
				workQ.Add(wu)
			END;
			t2 := AosKernel.Elapsed(t);
			AosOut.Enter;
			AosOut.String(" #CPU="); AosOut.Int(nofProcesses.Get(), 2); 
			AosOut.String(" ms="); AosOut.Int(t2, 0); AosOut.Ln;
			AosOut.String(" co-ordinates:"); AosOut.Ln;
			AosOut.String("  "); Utilities.FloatToStr(list.x0, 20, 19, 0, str); AosOut.String(str); AosOut.String(" / ");
			Utilities.FloatToStr(list.y0, 20, 19, 0, str);  AosOut.String(str); AosOut.Ln;
			AosOut.String("  "); Utilities.FloatToStr(list.x1, 20, 19, 0, str); AosOut.String(str); AosOut.String(" / ");
			Utilities.FloatToStr(list.y1, 20, 19, 0, str); AosOut.String(str); AosOut.Ln;
			AosOut.String(" depth = "); AosOut.Int(list.depth,0); AosOut.Ln;
			AosOut.Exit;
			recalcNeeded := FALSE;
			Invalidate;
			calculating := FALSE
		END Recalc;
		
		PROCEDURE PointerDown(x,y : LONGINT; keys : SET);
		BEGIN
			IF calculating THEN RETURN END;
			IF (keys*{0}#{}) THEN	
				NEW(l);
				l.x0 := list.x0 + x/bounds.GetWidth()*(list.x1-list.x0);
				l.y0 := list.y0 + y/bounds.GetHeight()*(list.y1-list.y0);
				selecting := TRUE; x0 := x; y0 := y; x1 := x; y1 := y
			ELSIF (list.next # NIL) THEN
				list := list.next; l := NIL
			END
		END PointerDown;
		
		PROCEDURE PointerMove(x,y : LONGINT; keys : SET);
		BEGIN
			IF calculating THEN RETURN END;
			x1 := x; y1 := y;
			IF selecting THEN Invalidate END
		END PointerMove;
		
		
		PROCEDURE PointerUp(x,y : LONGINT; keys : SET);
		VAR t: LONGREAL;
		BEGIN
			IF calculating THEN RETURN END;
			selecting := FALSE; 
			IF (l # NIL) THEN
				l.x1 := list.x0 + x/bounds.GetWidth()*(list.x1-list.x0);
				l.y1 := l.y0 + (l.x1 - l.x0); (*list.y0 + y/GetHeight()*(list.y1-list.y0);*)
				IF (l.x1 < l.x0) THEN t := l.x1; l.x1 := l.x0; l.x0 := t END;
				IF (l.y1 < l.y0) THEN t := l.y1; l.y1 := l.y0; l.y0 := t END;
				l.depth := list.depth * 2;
				l.next := list;
				list := l;
				l := NIL
			END;
			NeedRecalc
		END PointerUp;
		
		PROCEDURE NeedRecalc;
		BEGIN {EXCLUSIVE}
			recalcNeeded := TRUE;
		END NeedRecalc;
		
		PROCEDURE PrepareBuffer;
		VAR w, h:LONGINT;
		BEGIN
			w := bounds.GetWidth(); h := bounds.GetHeight();
			IF w <= 0 THEN w := 1 END; IF h <= 0 THEN h := 1 END;
			Raster.Create(backBmp, w, h, Raster.BGR888);
			NEW(bc, backBmp);
			IF (w > 1) & (h > 1) THEN NeedRecalc END
		END PrepareBuffer;
		
		
		PROCEDURE Resized*;
		BEGIN
			Resized^;
			PrepareBuffer;
		END Resized;
		
		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR str, t : ARRAY 32 OF CHAR;
		BEGIN
			canvas.DrawImage(0, 0, backBmp, WMGraphics.ModeCopy);
			IF selecting THEN
				WMGraphicUtilities.RectGlassShade(canvas, 
					WMRectangles.MakeRect(
						Utilities.Min(x0, x1),
						Utilities.Min(y0, y1),
						Utilities.Max(x1, x0),
						Utilities.Max(y1, y0)), 5, FALSE)
			END;
			IF recalcNeeded THEN 
				canvas.SetColor(0FFFF00FFH);
				canvas.DrawString(20, 20, "Calculating...");
				str := "Processes : "; Utilities.IntToStr( nofProcesses.Get(), t);
				Utilities.Append(str, t);
				canvas.DrawString(20, 40, str);
			END;
		END DrawBackground;
		
		PROCEDURE Finalize;
		BEGIN
			Finalize^;
			BEGIN {EXCLUSIVE} alive := FALSE END
		END Finalize;
		
		PROCEDURE Initialize*;
		BEGIN 
			Initialize^;
			PrepareBuffer;
			BEGIN {EXCLUSIVE} initialized := TRUE END;
		END Initialize;
		
	BEGIN {ACTIVE}
		BEGIN {EXCLUSIVE}
			AWAIT(initialized OR ~alive)
		END;	
		WHILE alive DO
			BEGIN {EXCLUSIVE}
				AWAIT(~alive OR recalcNeeded)
			END;	
			IF alive THEN Recalc END
		END
	END MandelbrotSetViewer;

VAR PrototypeNofProcesses : WMProperties.Int32Property;
	
PROCEDURE MandelbrotSetViewerGen*(ptr : PTR) : PTR;
VAR x : MandelbrotSetViewer;
BEGIN
	NEW(x); RETURN x
END MandelbrotSetViewerGen;

PROCEDURE Install;
BEGIN
	NEW(PrototypeNofProcesses, NIL, Utilities.NewString("NofProcesses"), Utilities.NewString("number of processes to use"));
	WMComponents.registry.RegisterElement("MandelbrotSetViewer", MandelbrotSetViewerGen);
END Install;
		
PROCEDURE Register*(par : PTR): PTR;
BEGIN
	RETURN NIL
END Register;

PROCEDURE Finalize;
BEGIN
	WMComponents.registry.UnregisterElement("MandelbrotSetViewer")
END Finalize;

BEGIN
	Install;
	AosModules.InstallTermHandler(Finalize)
END FractalDemo.


S.Free FractalDemo~
FractalDemo.Register ~

ComponentViewer.Open FractalDemo.XML ~