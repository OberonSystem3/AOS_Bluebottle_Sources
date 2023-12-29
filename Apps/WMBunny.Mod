MODULE WMBunny;	(** AUTHOR "TF"; PURPOSE "Visual active objects"; *)

IMPORT WM := WMWindowManager, Messages := WMMessages, Graphics := WMGraphics, AosCommands,  AosActive, AosModules,
				Raster, AosRandom, AosKernel, AosOut, AosIO, Rectangles := WMRectangles;

CONST
	Width = 1024; Height = 768;	(* temp hack *)

TYPE
	BunnyKillerMsg = OBJECT
	END BunnyKillerMsg; 
	
	Bunny = OBJECT (WM.Window)
	VAR
		posX, posY:LONGINT;
		alive:BOOLEAN;
		timer:AosKernel.Timer;
		random:AosRandom.Generator;
		nofFrames, frame, step:LONGINT;
		movie:Raster.Image;
		mode:Raster.Mode;
		keyPressed:SET;
		nextb:Bunny;
			
			PROCEDURE &New(movie : Raster.Image; frames, step : LONGINT);
			BEGIN
				bounds := Graphics.MakeRectangle(0, 0, movie.width DIV frames, movie.height);
				useAlpha := TRUE;
				NEW(random);
				nofFrames := frames; frame := 0; SELF.movie := movie; SELF.step := step;
				NEW(timer);			
				posX := (posX+ step) MOD (Width * 2 + movie.width);
				posY := random.Dice((Height - movie.height) DIV 2);
				manager := WM.GetDefaultManager();
				manager.Add(posX, posY, SELF, {});
				Raster.InitMode(mode, Raster.srcCopy)
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
					keyPressed:={}
				END		
			END PointerUp;
			
			PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
			BEGIN
				IF movie # NIL THEN
					IF (w = GetWidth()) & (h = GetHeight()) THEN
						canvas.ScaleImage(movie, Rectangles.MakeRect(frame * GetWidth(), 0, (frame + 1) * GetWidth(), GetHeight()),  
							Rectangles.MakeRect(0, 0, w, h), Graphics.ModeSrcOverDst, 0);
					ELSE
						canvas.ScaleImage(movie, Rectangles.MakeRect(frame * GetWidth(), 0, (frame + 1) * GetWidth(), GetHeight()),  
							Rectangles.MakeRect(0, 0, w, h), Graphics.ModeSrcOverDst, q)
					END	
				END
			END Draw;
			
			PROCEDURE IsHit(x, y  : LONGINT) : BOOLEAN;
			BEGIN
				RETURN Graphics.IsBitmapHit(frame * GetWidth() + x, y, 128, movie)
			END IsHit;
			
			PROCEDURE Close;
			BEGIN alive := FALSE
			END Close;
			
			PROCEDURE Handle(VAR x: Messages.Message);
			BEGIN
				IF (x.msgType = Messages.MsgExt) & (x.ext # NIL) & (x.ext IS BunnyKillerMsg) THEN Close
				ELSE Handle^(x)
				END
			END Handle;
			
		BEGIN {ACTIVE}
			alive:=TRUE;		
			WHILE alive DO timer.Sleep(100); Move END;				
			manager.Remove(SELF);
			DecBunnyCount;
		END Bunny;

VAR nofBunnies : LONGINT;
				
PROCEDURE IncBunnyCount;
BEGIN {EXCLUSIVE}
	INC(nofBunnies);
END IncBunnyCount;		

PROCEDURE DecBunnyCount;
BEGIN {EXCLUSIVE}
	DEC(nofBunnies);
END DecBunnyCount;		
		
PROCEDURE Free*(par: PTR): PTR;
VAR die : BunnyKillerMsg;
	 msg : Messages.Message;
	 m : WM.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die); msg.ext := die; msg.msgType := Messages.MsgExt;
	m := WM.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofBunnies = 0);
	RETURN NIL
END Free;

PROCEDURE InternalInsert(name : ARRAY OF CHAR; frames, step:LONGINT);
VAR b:Bunny;
		img:Raster.Image;
		done:BOOLEAN;
BEGIN {EXCLUSIVE}	
	(* AosActive.SetPriority(AosActive.Low); *)
	img := Graphics.LoadImage(name, TRUE); 
	IF img # NIL THEN
		NEW(b, img, frames, step)
	ELSE
		AosOut.Enter; AosOut.String(name);AosOut.String(" not found."); AosOut.Exit
	END
END InternalInsert;

PROCEDURE Insert*(par: PTR): PTR;
VAR s: AosCommands.Parameters;
		name:ARRAY 100 OF CHAR;
		i, step, deltaX:LONGINT;
		sr : AosIO.StringReader;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.Token(name); sr.SkipWhitespace();
	
	step := 8; IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(step, TRUE) END; sr.SkipWhitespace();
	deltaX := 32; IF (sr.Peek() >= '0') & (sr.Peek() <= '9')OR (sr.Peek() = '-') THEN sr.Int(deltaX, TRUE) END;
	
	IncBunnyCount;
	InternalInsert(name, step, deltaX);
	RETURN NIL
END Insert;

PROCEDURE Cleanup;
BEGIN
	IF Free(NIL) = NIL THEN END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMBunny.		

WMBunny.Insert BunnyLinear.gif 8 32~
WMBunny.Insert bones.gif 25 10~
WMBunny.Insert phantom.png 25 10~
WMBunny.Insert SisiphusLinear.gif 5 8~
WMBunny.Insert frog.gif 17 -4~

WMBunny.Free~
S.Free WMBunny 