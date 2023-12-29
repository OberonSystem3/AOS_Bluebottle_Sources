MODULE WMFingerPost;	(** AUTHOR "TF"; PURPOSE "Navigation in the Screenspace"; *)

IMPORT
		AosOut, AosModules, AosCommands, AosIO, WM := WMWindowManager, WMStandardComponents, 
		Utilities,  WMComponents, WMGraphics, TFClasses;

TYPE
	String = Utilities.String;
	FingerPost = OBJECT(WMComponents.FormWindow)
	VAR 
		panel : WMStandardComponents.Panel;
		goButton : WMStandardComponents.Button;
		destx, desty, destw, desth : LONGINT;
		doTransition : BOOLEAN;
		
		PROCEDURE &New(destName : ARRAY OF CHAR; x, y, w, h, destx, desty, destw, desth : LONGINT; transition : BOOLEAN);
		BEGIN
			(* add a panel *)
			NEW(panel); panel.bounds.SetExtents(70, 20); panel.fillColor.Set(WMGraphics.RGBAToColor(0, 0, 0, 0));
			SELF.destx := destx; SELF.desty := desty;
			SELF.destw := destw; SELF.desth := desth;
			NEW(goButton); goButton.caption.SetAOC(destName);
			goButton.alignment.Set(WMComponents.AlignClient); goButton.onClick.Add(Go);
			goButton.clHover.Set(0FFFF00FFH);
			goButton.clDefault.Set(0FFFF0088H);

			panel.AddContent(goButton);
			(* create the form window with panel size *)
			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), TRUE);
			SetContent(panel);
			manager := WM.GetDefaultManager();
			doTransition := transition;
			(* open the window *)
			SetPointerInfo(followPointer);
			manager.Add(x, y, SELF, {WM.FlagStayOnTop});
			manager.SetWindowSize(SELF, w, h)
		END New;
	
		PROCEDURE Go(sender, data : PTR);
		VAR view : WM.ViewPort; w, h : REAL; originator : PTR;
		BEGIN
			originator := panel.sequencer.GetOriginator();
			IF (originator # NIL) & (originator IS WM.ViewPort) THEN
				view := originator(WM.ViewPort);
				IF destw = 0 THEN w := view.range.r - view.range.l ELSE w := destw END;
				IF desth = 0 THEN h := view.range.b - view.range.t ELSE h := desth END;
				view.SetRange(destx, desty, w, h, doTransition);
			END
		END Go;
	END FingerPost;
	
VAR windowList : TFClasses.List;
	followPointer : WM.PointerInfo;

PROCEDURE Add*(par : PTR) : PTR;
VAR manager : WM.WindowManager;
	fp : FingerPost;
	img : WMGraphics.Image;
	x, y, w, h, destx, desty, destw, desth : LONGINT;
	name : ARRAY 256 OF CHAR;
	s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	done : BOOLEAN;
	ptr : PTR;
	i, count : LONGINT;
	snap : BOOLEAN;
BEGIN {EXCLUSIVE}
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.String(name); sr.SkipWhitespace();
	x := 0; IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(x, TRUE) END; sr.SkipWhitespace();
	y := 0; IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(y, TRUE) END; sr.SkipWhitespace();
	w := 0; IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(w, TRUE) END; sr.SkipWhitespace();
	h := 0; IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(h, TRUE) END; sr.SkipWhitespace();
	destx := 0; IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(destx, TRUE) END; sr.SkipWhitespace();
	desty := 0; IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(desty, TRUE) END; sr.SkipWhitespace();
	destw := 70; IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(destw, TRUE) END; sr.SkipWhitespace();
	desth := 20; IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(desth, TRUE) END; sr.SkipWhitespace();
	snap := sr.Get() = "S";
	NEW(fp, name, x, y, w, h, destx, desty, destw, desth, ~snap);
	windowList.Add(fp);
	RETURN NIL
END Add;		

PROCEDURE Cleanup;
VAR manager : WM.WindowManager;
	ptr : PTR;
	i : LONGINT;
BEGIN
	manager := WM.GetDefaultManager();
	windowList.Lock;
	FOR i := 0 TO windowList.GetCount() - 1 DO 
		ptr := windowList.GetItem(i); 
		manager.Remove(ptr(WM.Window))
	END;
	windowList.Unlock;
END Cleanup;

PROCEDURE RemoveAll*(par : PTR) : PTR;
BEGIN
	Cleanup;
	RETURN NIL
END RemoveAll;

BEGIN
	WM.LoadCursor("traditional.arrow.png", 0, 0, followPointer);
	
	NEW(windowList);
	AosModules.InstallTermHandler(Cleanup)
END WMFingerPost.

System.Free WMFingerPost ~
Configuration.DoCommands
Aos.Call WMBackdrop.AddBackdropImage BluebottlePic0.png 0 0 1280 1024~
Aos.Call WMBackdrop.AddBackdropImage AosBackdrop.png 1280 0 ~
	üAos.Call WMBackdrop.AddBackdropImage paper.gif 0 1024 1280 1024 ~
Aos.Call WMFingerPost.Add Oberon 2480 1000 0 0 1280 1024
Aos.Call WMFingerPost.Add "Windows" 1200 1000 1280 0 1280 1024
Aos.Call WMFingerPost.Add "Home" 1200 980 0 0 1280 1024
~
System.Free WMBackdrop ~
