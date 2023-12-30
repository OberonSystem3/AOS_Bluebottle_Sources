MODULE WMFingerPost;	(** AUTHOR "TF"; PURPOSE "Navigation in the Screenspace"; *)

IMPORT
	AosCommands, AosIO, AosModules,
	WMStandardComponents, WMComponents, WMGraphics, TFClasses,
	WM := WMWindowManager;

TYPE
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
VAR fp : FingerPost;
	fn : ARRAY 33 OF CHAR;
	sr : AosIO.StringReader;

	(* Assign an integer  value to a variable: extracted from the command parameter if present or
		else a default one *)
	PROCEDURE SetVal(def : LONGINT) : LONGINT;
	VAR int : LONGINT;
	BEGIN
		int := def;
		IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN
			AosCommands.GetInt(sr, int, TRUE);
		END;
		RETURN int;
	END SetVal;

BEGIN {EXCLUSIVE}
	AosCommands.PosPar(par, sr);
	AosCommands.GetTok(sr, fn);
	(* Enumeration of the integer values appearing in the command parameters: origin and destination *)
	(*                x		   y			w		   h			destx	    desty		 destw		desth		snap	*)
	NEW(fp, fn, SetVal(0), SetVal(0), SetVal(0), SetVal(0), SetVal(0), SetVal(0), SetVal(70), SetVal(20), (sr.Get() # "S"));
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
		manager.Remove(ptr(WM.Window));
	END;
	windowList.Unlock;
END Cleanup;

PROCEDURE RemoveAll*(par : PTR) : PTR;
BEGIN
	Cleanup;
	RETURN NIL;
END RemoveAll;

BEGIN
	WM.LoadCursor("traditional.arrow.png", 0, 0, followPointer);
	NEW(windowList);
	AosModules.InstallTermHandler(Cleanup);
END WMFingerPost.

S.Free WMFingerPost ~

WMBackdrop.AddBackdropImage BluebottlePic0.png 0 0 1280 1024~
WMBackdrop.AddBackdropImage AosBackdrop.png 1280 0 ~
WMBackdrop.AddBackdropImage paper.gif 0 1024 1280 1024 ~
WMFingerPost.Add Oberon 2480 1000 0 0 1280 1024 ~
WMFingerPost.Add "Windows" 1200 1000 1280 0 1280 1024 ~
WMFingerPost.Add 	"Home" 	1200 980 0 0 1280 1024 ~

WMFingerPost.RemoveAll ~
