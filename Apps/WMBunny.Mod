MODULE WMBunny;	(** AUTHOR "TF"; PURPOSE "Visual active objects"; *)

IMPORT
	AosCommands, AosIO, WMMessages, WMGraphics, AosModules,
	Raster, AosRandom, AosKernel, AosOut, Rectangles := WMRectangles,
	WM := WMWindowManager;

CONST
	Width = 1024; Height = 768;	(* temp hack *)

TYPE
	KillerMsg = OBJECT
	END KillerMsg; 
	
	Bunny = OBJECT (WM.Window)
	VAR
		posX, posY : LONGINT;
		alive : BOOLEAN;
		timer : AosKernel.Timer;
		random : AosRandom.Generator;
		nofFrames, frame, step : LONGINT;
		movie : Raster.Image;
		keyPressed : SET;

			PROCEDURE &New(movie : Raster.Image; frames, step : LONGINT);
			BEGIN
				bounds :=WMGraphics.MakeRectangle(0, 0, movie.width DIV frames, movie.height);
				useAlpha := TRUE;
				NEW(random);
				nofFrames := frames; frame := 0; SELF.movie := movie; SELF.step := step;
				NEW(timer);			
				posX := (posX+ step) MOD (Width * 2 + movie.width);
				posY := random.Dice((Height - movie.height) DIV 2);
				manager := WM.GetDefaultManager();
				manager.Add(posX, posY, SELF, {});
			END New;

			PROCEDURE Move;
			VAR opx : LONGINT;
			BEGIN
				opx := posX;
				posX := (posX+ step) MOD (Width * 2 + movie.width);
				IF ((step < 0) & (posX > opx)) OR ((step > 0) & (posX < opx)) THEN 
					posY := random.Dice(Height - movie.height) 
				END;
				frame := (frame + 1) MOD nofFrames;
				manager.SetWindowPos(SELF, posX - movie.width, posY)
			END Move;
			
			PROCEDURE PointerDown(x, y : LONGINT; keys : SET);
			BEGIN
				keyPressed := keyPressed + (keys * {0, 1, 2})			
			END PointerDown;
			
			PROCEDURE PointerUp(x, y : LONGINT; keys : SET);
			BEGIN
				IF keys={} THEN 
					IF keyPressed#{0, 1, 2} THEN 
						IF keyPressed={0} THEN manager.ToFront(SELF) 
						ELSIF keyPressed={0, 2} THEN Close END
					END;
					keyPressed := {}
				END		
			END PointerUp;
			
			PROCEDURE Draw*(canvas : WMGraphics.Canvas; w, h, q : LONGINT);
			BEGIN
				IF movie # NIL THEN
					IF (w = GetWidth()) & (h = GetHeight()) THEN
						canvas.ScaleImage(movie, Rectangles.MakeRect(frame * GetWidth(), 0, (frame + 1) * GetWidth(), GetHeight()),  
							Rectangles.MakeRect(0, 0, w, h), WMGraphics.ModeSrcOverDst, 0);
					ELSE
						canvas.ScaleImage(movie, Rectangles.MakeRect(frame * GetWidth(), 0, (frame + 1) * GetWidth(), GetHeight()),  
							Rectangles.MakeRect(0, 0, w, h), WMGraphics.ModeSrcOverDst, q)
					END	
				END
			END Draw;
			
			PROCEDURE IsHit(x, y  : LONGINT) : BOOLEAN;
			BEGIN
				RETURN WMGraphics.IsBitmapHit(frame * GetWidth() + x, y, 128, movie)
			END IsHit;
			
			PROCEDURE Close;
			BEGIN alive := FALSE
			END Close;
			
			PROCEDURE Handle(VAR x : WMMessages.Message);
			BEGIN
				IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
				ELSE Handle^(x)
				END
			END Handle;
			
		BEGIN {ACTIVE}
			alive := TRUE;		
			WHILE alive DO timer.Sleep(100); Move END;
		FINALLY			
			manager.Remove(SELF);				
			DecCount;
		END Bunny;

VAR
	nofWindows : LONGINT;
				
PROCEDURE IncCount;
BEGIN {EXCLUSIVE}
	INC(nofWindows)
END IncCount;		

PROCEDURE DecCount;
BEGIN {EXCLUSIVE}
	DEC(nofWindows)
END DecCount;		
		
PROCEDURE Free*(par : PTR) : PTR;
VAR die : KillerMsg;
	 msg : WMMessages.Message;
	 m : WM.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die);
	msg.ext := die;
	msg.msgType := WMMessages.MsgExt;
	m := WM.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0);
	RETURN NIL
END Free;

PROCEDURE InternalInsert(fname : ARRAY OF CHAR; frames, step : LONGINT);
VAR b : Bunny;
	img : Raster.Image;
BEGIN {EXCLUSIVE}	
	(* AosActive.SetPriority(AosActive.Low); *)
	img := WMGraphics.LoadImage(fname, TRUE); 
	IF img # NIL THEN
		NEW(b, img, frames, step)
	ELSE
		AosOut.Enter; AosOut.String(fname); AosOut.String(" not found."); AosOut.Exit
	END
END InternalInsert;

PROCEDURE Insert*(par : PTR) : PTR;
VAR fn : ARRAY 65 OF CHAR;	(* a filename equivalent to AosFS.FileName - do not import AosFS *)
	sr : AosIO.StringReader;

	(* Assign an integer value to a variable: extracted from the command parameter if present or
		else a default one *)
	PROCEDURE SetVal(def : LONGINT) : LONGINT;
	VAR int : LONGINT;
	BEGIN
		int := def;
		IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN
			AosCommands.GetInt(sr, int, FALSE);
		END;
		RETURN int;
	END SetVal;

BEGIN
	AosCommands.PosPar(par, sr);
	AosCommands.GetTok(sr, fn);
	IncCount;
	InternalInsert(fn, SetVal(8), SetVal(32));
	RETURN NIL
END Insert;

PROCEDURE Cleanup;
BEGIN
	IF Free(NIL) = NIL THEN END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMBunny.		

WMBunny.Insert BunnyLinear.gif 8 40 ~
WMBunny.Insert bones.gif 25 10 ~
WMBunny.Insert phantom.png 25 10 ~
WMBunny.Insert SisiphusLinear.gif 5 8 ~
WMBunny.Insert frog.gif 17 -4 ~

WMBunny.Free~
S.Free WMBunny 