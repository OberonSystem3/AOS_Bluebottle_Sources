MODULE VNCTetrisServer; (** AUTHOR "TF"; PURPOSE "VNC Tetris server"; *)
(** old aged *)

IMPORT Raster, AosOut, AosKernel, AosRandom, AosVNCServer, WMRectangles,
	WMGraphics, AosInputs, AosModules, AosIO, AosFS, AosIP, AosClock, Utilities;

CONST
	Width = 10;
	Height = 30;
	BoxSize = 16;
	BlockSize = 5;
	NofBlocks = 7;
	ScoreHeight = 108;
	DataFile = "VNCTetris.dat";
	
VAR colors : ARRAY NofBlocks + 1 OF Raster.Pixel;

	gamesRunning, gamesTotal, maxConcurrent, highScore : LONGINT;
	shuttingDown : BOOLEAN;
	
	server: AosVNCServer.Server;
	
TYPE
	Block = ARRAY BlockSize, BlockSize OF CHAR;	
	TimeDate = RECORD h, m, s, day,month,year: LONGINT END;

	TT = OBJECT
	VAR
		alive, dropped : BOOLEAN;
		field : ARRAY Width OF ARRAY Height OF CHAR;
		block : Block;
		posX, posY : LONGINT;
		timer : AosKernel.Timer;
		mode : Raster.Mode;
		random : AosRandom.Generator;
		lines, blocks, delay, delayDec: LONGINT;
		img : Raster.Image;
		paused, run: BOOLEAN;
		cheated: LONGINT;
		
		time : TimeDate;
		adrStr, timeStr:ARRAY 32 OF CHAR;
		vncInfo : AosVNCServer.VNCInfo;
		canvas : WMGraphics.BufferCanvas;

		PROCEDURE &Create(vncInfo : AosVNCServer.VNCInfo);
		BEGIN
			NEW(img);
			Raster.Create(img, Width * BoxSize, Height * BoxSize + ScoreHeight, Raster.BGR565);
			Raster.InitMode(mode, Raster.srcCopy); NEW(timer); NEW(random); random.InitSeed(AosKernel.GetTimer()); lines := 0;
			NEW(canvas, img);
			SELF.vncInfo := vncInfo;
			run := FALSE
		END Create;
		
		PROCEDURE Run;
		BEGIN {EXCLUSIVE}
			run := TRUE
		END Run;
		
		PROCEDURE Bound(VAR x:LONGINT; min, max:LONGINT);
		BEGIN IF x<min THEN x:=min ELSE IF x>max THEN x:=max END END
		END Bound;
		
		PROCEDURE ClipAtImage(VAR x: WMRectangles.Rectangle; img:Raster.Image);
		BEGIN
			Bound(x.l, 0, img.width);Bound(x.r, 0, img.width);
			Bound(x.t, 0, img.height);Bound(x.b, 0, img.height)
		END ClipAtImage;

		PROCEDURE AddDirty(l, t, r, b:LONGINT);
		VAR x: WMRectangles.Rectangle;
		BEGIN
			WMRectangles.SetRect(x, l, t, r, b);
			ClipAtImage(x, img);
			IF vncInfo.agent # NIL THEN vncInfo.agent.AddDirty(x) END
		END AddDirty;
		
		PROCEDURE Close();
		BEGIN
			alive := FALSE
		END Close;
		
		PROCEDURE RotateBlock(VAR block:Block):Block;
		VAR i, j : INTEGER; temp : Block;
		BEGIN
			FOR i := 0 TO BlockSize - 1 DO FOR j := 0 TO BlockSize - 1 DO temp[j, i] := block[(BlockSize - 1) - i, j] END END;
			RETURN temp
		END RotateBlock;
		
		PROCEDURE DrawBox(x, y: LONGINT; color: CHAR);
		VAR pix : Raster.Pixel;
		BEGIN
			pix := colors [ORD(color)];
			IF (x >= 0) & (x < Width) & (y >= 0) & (y < Height) THEN
				Raster.Fill(img, x * BoxSize, y * BoxSize, x * BoxSize+ BoxSize, y * BoxSize + BoxSize, pix, mode)
			END; 
		END DrawBox;
		
		PROCEDURE SetBlock(x, y : LONGINT; clear : BOOLEAN);
		VAR i, j : LONGINT;
		BEGIN
			FOR i := 0 TO BlockSize - 1 DO FOR j := 0 TO BlockSize - 1 DO 
				IF block[i, j] # 0X THEN 
					IF (i + x < Width) & (j + y >= 0) & (j + y < Height) THEN
						IF clear THEN 
							field[i + x, j + y] := 0X;
							DrawBox(i + x, j + y, 0X)
						ELSE field[i + x, j + y] := block[i, j];
							DrawBox(i + x, j + y, block[i, j])
						END 
					END
				END
			END END
		END SetBlock;
		
		PROCEDURE HasDownCollision(x, y: LONGINT) : BOOLEAN;
		VAR i, j : LONGINT;
		BEGIN
			FOR i := 0 TO BlockSize - 1 DO FOR j := 0 TO BlockSize - 1 DO 
				IF block[i, j] # 0X THEN 
					IF (i + x < Width) & (j + y >= 0) THEN
						IF (j + y < Height) THEN
							IF (block[i, j] # 0X) & (field[i + x, j + y] # 0X) THEN RETURN TRUE END 
						ELSIF block[i, j] # 0X THEN RETURN TRUE
						END
					ELSE RETURN TRUE	
					END 
				END
			END END;
			RETURN FALSE
		END HasDownCollision;
		
		PROCEDURE HasCollision(VAR bl: Block; x, y: LONGINT) : BOOLEAN;
		VAR i, j : LONGINT;
		BEGIN
			FOR i := 0 TO BlockSize - 1 DO FOR j := 0 TO BlockSize - 1 DO 
				IF bl[i, j] # 0X THEN 
					IF (i + x >= Width) OR (i + x < 0) OR (j + y >= Height) OR (field[i + x, j + y] # 0X) THEN RETURN TRUE END
				END
			END END;
			RETURN FALSE
		END HasCollision;
		
		PROCEDURE Move(dir: LONGINT):BOOLEAN;
		VAR newX, newY: LONGINT; result : BOOLEAN;
		BEGIN
			newX := posX; newY := posY;
			IF dir = 0 THEN INC(newX) 
			ELSIF dir = 1 THEN DEC(newX)
			ELSIF dir = 2 THEN INC(newY)
			END;			
			
			SetBlock(posX, posY, TRUE);
			IF ~HasCollision(block, newX, newY) THEN posX := newX; posY := newY; result := TRUE
			ELSE result := FALSE
			END;
			SetBlock(posX, posY, FALSE);
			AddDirty(posX * BoxSize - BoxSize, posY * BoxSize - BoxSize, posX * BoxSize + BlockSize * BoxSize + BoxSize, 
				posY * BoxSize + BlockSize*BoxSize +BoxSize);
			RETURN result
		END Move;
		
		PROCEDURE KeyPressed(ucs : LONGINT; flags: SET; keysym: LONGINT);
		VAR ignore : BOOLEAN;
			rotBlock : Block;
		BEGIN {EXCLUSIVE}
			IF ~alive THEN RETURN END;
			IF AosInputs.Release IN flags THEN RETURN END;
			IF (ucs = ORD("p")) OR (ucs = ORD("P")) THEN paused := ~paused END; (* IF paused THEN RETURN END;feature*)
			IF (keysym = 0FF50H) OR (keysym = 0FF51H) THEN ignore := Move(1); IF paused THEN INC(cheated) END
			ELSIF (keysym = 0FF55H)OR (keysym = 0FF53H) THEN ignore := Move(0); IF paused THEN INC(cheated) END
			ELSIF (keysym = 0FF52H) OR (keysym = 0FF09H) THEN 
				SetBlock(posX, posY, TRUE);
				rotBlock := RotateBlock(block);
				IF ~HasCollision(rotBlock, posX, posY) THEN block := rotBlock END;
				SetBlock(posX, posY, FALSE); 
				AddDirty(posX * BoxSize - BoxSize, posY * BoxSize - BoxSize, posX * BoxSize + BlockSize * BoxSize, 
					posY * BoxSize + BlockSize * BoxSize);
				IF paused THEN INC(cheated) END	
			ELSIF (keysym = 0FF54H) OR (keysym = 0FF0DH) OR (keysym = 20H) THEN 
				dropped := TRUE; IF paused THEN INC(cheated) END
			END
		END KeyPressed;
		
		PROCEDURE NewBlock;
		VAR i, j: LONGINT; kind : LONGINT;
				color : CHAR;
				
			PROCEDURE Set(x, y: LONGINT);
			BEGIN block[x, y] := color
			END Set;
			
		BEGIN
			UpdateScore(FALSE);
			dropped := FALSE;
			posX := Width DIV 2 - 1; posY := 0;
			
			FOR i := 0 TO BlockSize - 1 DO FOR j := 0 TO BlockSize - 1 DO block [i, j] := 0X END END;
			kind := random.Integer() MOD NofBlocks;
			
			color := CHR(1 + kind);
			
			CASE kind OF
				0 : Set(0, 2); Set(1, 2); Set(2, 2); Set(3, 2)
				|1 : Set(1, 3); Set(2, 3); Set(3, 3); Set(2, 2)
				|2 : Set(1, 1); Set(1, 2); Set(2, 2); Set(2, 3)
				|3 : Set(2, 1); Set(1, 2); Set(2, 2); Set(1, 3)
				|4 : Set(2, 1); Set(2, 2); Set(2, 3); Set(3, 3)
				|5 : Set(2, 1); Set(2, 2); Set(2, 3); Set(1, 3)
				|6 : Set(1, 1); Set(1, 2); Set(2, 1); Set(2, 2)
			END;	
			INC(blocks);
			IF HasCollision(block, posX, posY) THEN alive := FALSE; END
		END NewBlock;
		
		PROCEDURE RemoveLine(y: LONGINT);
		VAR i, j: LONGINT;
		BEGIN
			FOR i := 0 TO Width - 1 DO
				FOR j := y TO 1 BY - 1 DO 
					field[i, j] := field[i, j - 1];
					DrawBox(i, j, field[i, j])
				END;
				field[i, 0] := 0X;
				DrawBox(i, 0, 0X)
			END;
			AddDirty(0, 0, Width * BoxSize, y * BoxSize + BoxSize);
			INC(lines);
			timer.Sleep(200);
			IF delay > 10 THEN DEC(delay, delayDec) END;
			IF delayDec >= 4 THEN delayDec := delayDec * 2 DIV 3 END
		END RemoveLine;
		
		PROCEDURE ClearLines;
		VAR y, x, c: LONGINT;
		BEGIN
			y := Height - 1;
			WHILE y > 0 DO 
				c := 0; FOR x := 0 TO Width - 1 DO IF field[x, y] # 0X THEN INC(c) END END;
				IF c = Width THEN RemoveLine(y) ELSE DEC(y) END
			END
		END ClearLines;
		
		PROCEDURE DropStep;
		VAR needNew: BOOLEAN;
		BEGIN {EXCLUSIVE}
			AWAIT(~paused);
			SetBlock(posX, posY, TRUE);
			IF ~HasDownCollision(posX, posY +1) THEN INC(posY); needNew := FALSE ELSE needNew := TRUE END;
			SetBlock(posX, posY, FALSE); 
			AddDirty(posX * BoxSize - BoxSize, posY * BoxSize - BoxSize, posX * BoxSize + BlockSize * BoxSize, 
							posY * BoxSize + BlockSize*BoxSize);
			IF needNew THEN 
				ClearLines;
				NewBlock 
			END
		END DropStep;
		
		PROCEDURE UpdateScore(eog: BOOLEAN);
		VAR pix : Raster.Pixel; str : ARRAY 16 OF CHAR; ypos : LONGINT;
		BEGIN
			Raster.SetRGB(pix, 255, 255, 255); 
			Raster.Fill(img, 0, Height * BoxSize, Width * BoxSize, Height * BoxSize + ScoreHeight, pix, mode);
			Utilities.IntToStr(lines*10+blocks, str);
			ypos := Height * BoxSize +13;
			canvas.DrawString(0, ypos, "Score:"); canvas.DrawString(100, ypos, str); INC(ypos, 13);
			
			Utilities.IntToStr(GetGamesRunning(), str);
			canvas.DrawString(0, ypos, "Games active:");  canvas.DrawString(100, ypos, str); INC(ypos, 13);
			
			Utilities.IntToStr(GetMaxConcurrent(), str);
			canvas.DrawString(0, ypos, "Max concurrent:");  canvas.DrawString(100, ypos, str); INC(ypos, 13);

			Utilities.IntToStr(GetGamesTotal(), str);
			canvas.DrawString(0, ypos, "Served total:");  canvas.DrawString(100, ypos, str);INC(ypos, 13);
			
			Utilities.IntToStr(GetHighscore(), str);
			canvas.DrawString(0, ypos, "High score:");  canvas.DrawString(100, ypos, str);INC(ypos, 13);
			canvas.DrawString(0, ypos, "Press p to toggle pause"); INC(ypos, 13);
			IF GetIsShuttingDown() THEN 
				canvas.DrawString(0, ypos, "THE SERVER IS SHUTTING DOWN"); INC(ypos, 13)
			END;
			IF (cheated >= 5) & eog THEN
				canvas.DrawString(0, ypos, "Phuking cheater !"); INC(ypos, 13)
			END;
			AddDirty(0, Height * BoxSize, Width * BoxSize, Height * BoxSize + ScoreHeight);
		END UpdateScore;
		
		PROCEDURE AwaitRun;
		BEGIN {EXCLUSIVE}
			AWAIT(run)
		END AwaitRun;
		
	BEGIN {ACTIVE}
		AwaitRun;
		AosIP.AdrToStr(vncInfo.connection.fip, adrStr);
		AosOut.Enter; 	
		Utilities.DateToStr(Utilities.Now(), timeStr); AosOut.String(timeStr); AosOut.String(" ");
		Utilities.TimeToStr(Utilities.Now(), timeStr); AosOut.String(timeStr);  
		AosOut.String(" IP: "); AosOut.String(adrStr);
		AosOut.String(":"); AosOut.Int(vncInfo.connection.fport, 5);
		AosOut.String(" started");
		AosOut.Exit;		
		
		AddGame;
		alive := ~GetIsShuttingDown(); delay :=300; delayDec := 20;
		NewBlock;
		WHILE alive DO 
			IF ~dropped THEN timer.Sleep(delay) END;
			DropStep
		END;
		
		AosOut.Enter;   
		Utilities.DateToStr(Utilities.Now(), timeStr); AosOut.String(timeStr); AosOut.String(" ");
		Utilities.TimeToStr(Utilities.Now(), timeStr); AosOut.String(timeStr);  
		AosOut.String(" IP: "); AosOut.String(adrStr);
		AosOut.String(":"); AosOut.Int(vncInfo.connection.fport, 5); 
		AosOut.String(" Score: "); AosOut.Int(lines * 10 + blocks, 1);
		IF (cheated > 0) THEN AosOut.String(" (cheated "); AosOut.Int(cheated, 0); AosOut.String(" times)") END;
		AosOut.Exit;
		SubGame;
		IF (cheated < 5) THEN ReportScore(lines * 10 + blocks) END;
		UpdateScore(TRUE)
	END TT;
	
PROCEDURE StartTT(vncInfo : AosVNCServer.VNCInfo);
VAR t: TT;
BEGIN
	NEW(t, vncInfo);
	vncInfo.img := t.img;
	vncInfo.kl := t.KeyPressed;
	t.Run
END StartTT;
	
PROCEDURE AddGame;
BEGIN {EXCLUSIVE}
	INC(gamesTotal);
	INC(gamesRunning);
	maxConcurrent := Max(gamesRunning, maxConcurrent)
END AddGame;

PROCEDURE ReportScore(score:LONGINT);
BEGIN {EXCLUSIVE}
	highScore := Max(score, highScore)
END ReportScore;

PROCEDURE GetGamesTotal():LONGINT;
BEGIN {EXCLUSIVE}
	RETURN gamesTotal
END GetGamesTotal;

PROCEDURE GetMaxConcurrent():LONGINT;
BEGIN {EXCLUSIVE}
	RETURN maxConcurrent
END GetMaxConcurrent;

PROCEDURE GetHighscore():LONGINT;
BEGIN {EXCLUSIVE}
	RETURN highScore
END GetHighscore;

PROCEDURE GetGamesRunning():LONGINT;
BEGIN {EXCLUSIVE}
	RETURN gamesRunning
END GetGamesRunning;

PROCEDURE GetIsShuttingDown():BOOLEAN;
BEGIN {EXCLUSIVE}
	RETURN shuttingDown
END GetIsShuttingDown;

PROCEDURE SubGame;
BEGIN {EXCLUSIVE}
	DEC(gamesRunning)
END SubGame;
	
(* Standard Procedures *)

PROCEDURE Max(x, y: LONGINT): LONGINT;
BEGIN
	IF x > y THEN RETURN x ELSE RETURN y END
END Max; 

PROCEDURE Run*(par: PTR): PTR;
BEGIN
	ReadData;
	server := AosVNCServer.OpenService(5999, StartTT);
	RETURN NIL
END Run;

PROCEDURE StopNew*(par: PTR): PTR;
BEGIN {EXCLUSIVE}
	shuttingDown := TRUE;
	RETURN NIL
END StopNew;

PROCEDURE Uninstall*(par: PTR): PTR;
VAR f: AosFS.File; w: AosFS.Writer;
BEGIN
	IF server # NIL THEN 
		f := AosFS.New(DataFile);
		IF f # NIL THEN
			AosFS.OpenWriter(w, f, 0);
			w.RawLInt(highScore);
			w.RawLInt(gamesTotal);
			w.RawLInt(maxConcurrent);
			w.Update();
			AosFS.Register(f)
		END;
		server.Close
	END;
	RETURN NIL
END Uninstall;

PROCEDURE Cleanup;
BEGIN
	IF Uninstall(NIL) = NIL THEN END
END Cleanup;

PROCEDURE ReadData;
VAR f: AosFS.File; r: AosFS.Reader;
BEGIN
	f := AosFS.Old(DataFile);
	IF f # NIL THEN
		AosFS.OpenReader(r, f, 0);
		r.RawLInt(highScore);
		r.RawLInt(gamesTotal);
		r.RawLInt(maxConcurrent)
	END	
END ReadData;

BEGIN
	Raster.SetRGBA(colors[0], 0, 0, 0, 255);
	Raster.SetRGBA(colors[1], 255, 0, 0, 255);
	Raster.SetRGBA(colors[2], 0, 255, 0, 255);
	Raster.SetRGBA(colors[3], 0, 0, 255, 255);
	Raster.SetRGBA(colors[4], 200, 200, 0, 255);
	Raster.SetRGBA(colors[5], 255, 0, 255, 255);
	Raster.SetRGBA(colors[6], 0, 255, 255, 255);
	Raster.SetRGBA(colors[7], 256, 128, 100, 255);	
	AosModules.InstallTermHandler(Cleanup)
END VNCTetrisServer.

Aos.Call VNCTetrisServer.Run
Aos.Call VNCTetrisServer.StopNew
Aos.Call VNCTetrisServer.Uninstall

System.Free VNCTetrisServer AosVNCServer~