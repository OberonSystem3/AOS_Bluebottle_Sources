MODULE WMTT;	(** AUTHOR "TF"; PURPOSE "Tetris with semitransparent blocks"; *)

IMPORT WMWindowManager, Utilities, Raster, Graphics := WMGraphics, WMRectangles, AosOut, AosKernel, AosRandom;

CONST
	Width = 10;
	Height = 30;
	BoxSize = 16;
	BlockSize = 5;
	NofBlocks = 7;
	InfoHeight = 0;
	RandomDrop = FALSE;
	
VAR colors : ARRAY NofBlocks + 1 OF Raster.Pixel;

TYPE
	Block = ARRAY BlockSize, BlockSize OF CHAR;
	TT = OBJECT (WMWindowManager.BufferWindow)
	VAR
		alive, dropped : BOOLEAN;
		field : ARRAY Width OF ARRAY Height OF CHAR;
		rotBlock, block : Block;
		posX, posY : LONGINT;
		timer : AosKernel.Timer;
		mode : Raster.Mode;
		random : AosRandom.Generator;
		lines, blocks, delay, delayDec: LONGINT;

		PROCEDURE &Create(alpha:BOOLEAN);
		BEGIN
			Init(Width * BoxSize, Height * BoxSize + InfoHeight, alpha);
			Raster.InitMode(mode, Raster.srcCopy); NEW(timer); NEW(random); random.InitSeed(AosKernel.GetTimer()); 
			lines := 0;
			pointerThreshold := 10;
			WMWindowManager.DefaultAddWindow(SELF);
			SetTitle(Utilities.NewString("WM Transparent Tetris"))
		END Create;
		
		PROCEDURE DrawInfo;
		BEGIN
			canvas.Fill(WMRectangles.MakeRect(0, Height * BoxSize, Width * BoxSize, Height * BoxSize + InfoHeight), 
			0FFFFH, Graphics.ModeCopy);
(*			canvas.SetColor(style.fgColor);*)
			Graphics.DrawStringInRect(canvas, 
				WMRectangles.MakeRect(0, Height * BoxSize + 5, Width * BoxSize, Height * BoxSize + InfoHeight), FALSE,
				Graphics.AlignCenter, Graphics.AlignTop, "Use [left]/[right] to move");
			Graphics.DrawStringInRect(canvas, 
				WMRectangles.MakeRect(0, Height * BoxSize + 25, Width * BoxSize, Height * BoxSize + InfoHeight), FALSE,
				Graphics.AlignCenter, Graphics.AlignTop, "[Enter]:drop, [up]:rotate");
			
			
			Invalidate(WMRectangles.MakeRect(0, Height * BoxSize, Width * BoxSize, Height * BoxSize + InfoHeight));
		END DrawInfo;
		
		PROCEDURE StyleChanged;
		BEGIN
			DrawInfo
		END StyleChanged;
		
		PROCEDURE Close();
		BEGIN
			alive := FALSE;
			Close^
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
			Invalidate(WMRectangles.MakeRect(posX * BoxSize - BoxSize, posY * BoxSize - BoxSize, posX * BoxSize + BlockSize * BoxSize + BoxSize, 
				posY * BoxSize + BlockSize*BoxSize +BoxSize));
			RETURN result
		END Move;
		
		PROCEDURE KeyEvent(ucs : LONGINT; flags: SET; keysym: LONGINT);
		VAR ignore : BOOLEAN;
			rotBlock : Block;
		BEGIN {EXCLUSIVE}
			IF ~alive THEN RETURN END;
			IF (keysym = 0FF50H) OR (keysym = 0FF51H) THEN ignore := Move(1)
			ELSIF (keysym = 0FF55H)OR (keysym = 0FF53H) THEN ignore := Move(0)
			ELSIF (keysym = 0FF52H) THEN 
				SetBlock(posX, posY, TRUE);
				rotBlock := RotateBlock(block);
				IF ~HasCollision(rotBlock, posX, posY) THEN block := rotBlock END;
				SetBlock(posX, posY, FALSE); 
				Invalidate(WMRectangles.MakeRect(posX * BoxSize - BoxSize, posY * BoxSize - BoxSize, posX * BoxSize + BlockSize * BoxSize, 
					posY * BoxSize + BlockSize * BoxSize));
			ELSIF (keysym = 0FF54H) OR (keysym = 0FF0DH) OR (keysym = 20H) THEN dropped := TRUE
			END
		END KeyEvent;
		
		PROCEDURE NewBlock;
		VAR i, j: LONGINT; kind : LONGINT;
				color : CHAR;
				
			PROCEDURE Set(x, y: LONGINT);
			BEGIN block[x, y] := color
			END Set;
			
		BEGIN
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
			IF HasCollision(block, posX, posY) THEN alive := FALSE; AosOut.Enter; AosOut.String("Game Over"); AosOut.Exit END
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
			Invalidate(WMRectangles.MakeRect(0, 0, Width * BoxSize, y * BoxSize + BoxSize));
			INC(lines);
			timer.Sleep(200);
			IF delay > 10 THEN DEC(delay, delayDec) END;
			IF delayDec >= 10 THEN delayDec := delayDec DIV 2 END
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
			SetBlock(posX, posY, TRUE);
			IF ~HasDownCollision(posX, posY +1) THEN INC(posY); needNew := FALSE ELSE needNew := TRUE END;
			SetBlock(posX, posY, FALSE); 
			Invalidate(WMRectangles.MakeRect(posX * BoxSize - BoxSize, posY * BoxSize - BoxSize, posX * BoxSize + BlockSize * BoxSize, 
							posY * BoxSize + BlockSize*BoxSize));
			IF needNew THEN 
				ClearLines;
				NewBlock 
			END
		END DropStep;
		
		PROCEDURE Restart;
		VAR x,y: LONGINT;
		BEGIN
			FOR x := 0 TO Width-1 DO
				FOR y := 0 TO Height-1 DO
					field[x,y] := 0X
				END
			END;
			lines := 0
		END Restart;
			
	BEGIN {ACTIVE}
		alive := TRUE; delay :=150; delayDec := 30;
		Restart;
		NewBlock;
		WHILE alive DO 
			IF ~dropped THEN timer.Sleep(delay) END;
			IF RandomDrop THEN
				CASE random.Dice(3) OF
					0 : IF Move(0) THEN END;
					|1 : IF Move(1) THEN END;
					|2 : 
						SetBlock(posX, posY, TRUE);
						rotBlock := RotateBlock(block);
						IF ~HasCollision(rotBlock, posX, posY) THEN block := rotBlock END;
						SetBlock(posX, posY, FALSE); 
						Invalidate(WMRectangles.MakeRect(posX * BoxSize - BoxSize, posY * BoxSize - BoxSize, posX * BoxSize + BlockSize * BoxSize, 
						posY * BoxSize + BlockSize * BoxSize));
				END;
			END;
			DropStep
		END;
		Close;
		AosOut.Enter; AosOut.String("TT: Number Of Lines:"); AosOut.Int(lines, 5); 
		AosOut.String("Number Of Blocks:"); AosOut.Int(blocks, 5); AosOut.Exit
	END TT;
	
(* Standard Procedures *)

PROCEDURE Min(x, y: LONGINT): LONGINT;
BEGIN
	IF x < y THEN RETURN x ELSE RETURN y END
END Min; 

PROCEDURE Open*(par: PTR): PTR;
VAR t: TT;
BEGIN
	NEW(t, TRUE);
	RETURN NIL
END Open;

BEGIN
	Raster.SetRGBA(colors[0], 0, 0, 0, 0);
	Raster.SetRGBA(colors[1], 255, 0, 0, 128);
	Raster.SetRGBA(colors[2], 0, 255, 0, 128);
	Raster.SetRGBA(colors[3], 0, 0, 255, 128);
	Raster.SetRGBA(colors[4], 200, 200, 0, 200);
	Raster.SetRGBA(colors[5], 255, 0, 255, 128);
	Raster.SetRGBA(colors[6], 0, 255, 255, 200);
	Raster.SetRGBA(colors[7], 256, 128, 100, 200)
END WMTT.

S.Free WMTT ~

WMTT.Open