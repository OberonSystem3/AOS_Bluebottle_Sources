MODULE Snow; (** AUTHOR "TF"; PURPOSE "Let it snow"; *)

IMPORT
	WMWindowManager, WMGraphics, AosKernel, AosRandom;
	
CONST
	NofFlakes = 20;

PROCEDURE Snow*(par : ANY) : ANY;
VAR flakes : ARRAY NofFlakes OF WMWindowManager.BufferWindow;
	flakePos : ARRAY NofFlakes OF RECORD x, y : LONGINT END;
	i, j : LONGINT;
	f, f1, f2 : WMGraphics.Image;
	timer : AosKernel.Timer;
	random : AosRandom.Generator;
BEGIN
	NEW(random); random.InitSeed(AosKernel.GetTimer());
	NEW(timer);
	f1 := WMGraphics.LoadImage("xmas04.tar://Flake1.png", TRUE);
	f2 := WMGraphics.LoadImage("xmas04.tar://Flake2.png", TRUE);
	FOR i := 0 TO NofFlakes - 1 DO
		flakePos[i].x := random.Dice(1280);
		flakePos[i].y := -random.Dice(1000);
		IF random.Dice(2) = 1 THEN f := f1 ELSE f := f2 END;
		NEW(flakes[i], f.width, f.height, TRUE);
		flakes[i].pointerThreshold := 255;
		flakes[i].canvas.DrawImage(0, 0, f, WMGraphics.ModeCopy)
	END;
	
	FOR i := 0 TO NofFlakes - 1 DO
		WMWindowManager.ExtAddWindow(flakes[i], flakePos[i].x, flakePos[i].y, {WMWindowManager.FlagStayOnTop});
	END;

	FOR j := 0 TO 12000 DO
		FOR i := 0 TO NofFlakes - 1 DO
			flakePos[i].x := flakePos[i].x + random.Dice(5)-2;
			INC(flakePos[i].y);
			IF random.Dice(2) = 1 THEN INC(flakePos[i].y) END;
			IF (flakePos[i].y > 1024) & (j < 10000) THEN flakePos[i].y := -64 - random.Dice(10) END;
			flakes[i].manager.SetWindowPos(flakes[i], flakePos[i].x, flakePos[i].y);
		END;
		timer.Sleep(10)
	END;	
	
	FOR i := 0 TO NofFlakes - 1 DO
		flakes[i].manager.Remove(flakes[i]);
	END;
	
	RETURN NIL
END Snow;


END Snow.Snow

S.Free Snow ~
