MODULE WMBackdrop;	(** AUTHOR "TF"; PURPOSE "Backdrop images"; *)

(* 03-04-03	RG: Context menu support added *)

IMPORT
	AosOut, AosIO, AosModules, AosCommands, Utilities, WMRectangles, Raster, WMMessages, 
	WMWindowManager, WMGraphics, TFClasses, WMPopups, WMComponents, WMRestorable, XML;
		
TYPE
	Window = OBJECT(WMWindowManager.Window)
	VAR img : WMGraphics.Image;
		picname : ARRAY 256 OF CHAR;
		
		PROCEDURE Draw*(canvas : WMGraphics.Canvas; w, h, q : LONGINT);
		BEGIN
			IF img # NIL THEN 
				canvas.ScaleImage(img, WMRectangles.MakeRect(0, 0, img.width, img.height), 
							WMRectangles.MakeRect(0, 0, w, h), WMGraphics.ModeCopy, q)
			END
		END Draw;
		
		PROCEDURE PointerDown*(x, y : LONGINT; keys : SET);
		VAR view : WMWindowManager.ViewPort; 
			w, h : REAL; originator : ANY; 
			manager : WMWindowManager.WindowManager; 
			contextMenu : WMPopups.Popup;
		BEGIN
			originator := sequencer.GetOriginator();
			IF (originator # NIL) & (originator IS WMWindowManager.ViewPort) THEN
				IF keys={0} THEN
					view := originator(WMWindowManager.ViewPort);
					w := bounds.r - bounds.l;
					h := bounds.b - bounds.t;
					view.SetRange(bounds.l, bounds.t, w, h, TRUE);
				ELSIF keys={2} THEN
					NEW(contextMenu);
					contextMenu.Add("Full screen", HandleFullScreen);
					contextMenu.Add("Remove", HandleRemove);
					contextMenu.Popup(bounds.l+x, bounds.t+y)
				END
			END
		END PointerDown;
		
		PROCEDURE HandleFullScreen(sender, par: PTR);
		VAR view : WMWindowManager.ViewPort; w, h : REAL; originator : PTR; 
		BEGIN
			manager.SetFocus(SELF);
			originator := sender(WMComponents.Component).sequencer.GetOriginator();
			manager.SetFocus(SELF);
			view := originator(WMWindowManager.ViewPort);
			w := bounds.r - bounds.l;
			h := bounds.b - bounds.t;
			view.SetRange(bounds.l, bounds.t, w, h, TRUE);
		END HandleFullScreen;
		
		PROCEDURE HandleRemove(sender, par: PTR);
		BEGIN
			manager.SetFocus(SELF);
			manager.Remove(SELF);
			windowList.Remove(SELF)
		END HandleRemove;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		VAR data : XML.Element; a : XML.Attribute; n : ARRAY 10 OF CHAR;
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS WMRestorable.Storage) THEN
					NEW(data);  n := "Data"; data.SetName(n);
					NEW(a); n := "file"; a.SetName(n); a.SetValue(picname); data.AddAttribute(a);
					x.ext(WMRestorable.Storage).Add("Backdrop", "WMBackdrop.Restore", SELF, data)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;

	END Window;
	
VAR windowList : TFClasses.List;
	followPointer : WMWindowManager.PointerInfo;
	
PROCEDURE DefaultPos(VAR x, y, w, h : LONGINT);
VAR manager : WMWindowManager.WindowManager;
	view : WMWindowManager.ViewPort;
	s : WMWindowManager.WindowStyle; dy : LONGINT;
BEGIN
	manager := WMWindowManager.GetDefaultManager();
	view := WMWindowManager.GetDefaultView();
	s := manager.GetStyle();
	x := ENTIER(view.range.l); y := ENTIER(view.range.t);
	w := ENTIER(view.range.r - view.range.l);
	h := ENTIER(view.range.b - view.range.t);
END DefaultPos;

PROCEDURE GetImage(name : ARRAY OF CHAR) : WMGraphics.Image;
VAR img : WMGraphics.Image;
	done : BOOLEAN;
	i, count : LONGINT; ptr : PTR;
BEGIN
	img := NIL;
	windowList.Lock;
	i := 0; count := windowList.GetCount();
	WHILE (img = NIL) & (i < count) DO 
		ptr := windowList.GetItem(i);
		IF ptr(Window).picname = name THEN img := ptr(Window).img END;
		INC(i)
	END;
	windowList.Unlock;
	IF img = NIL THEN NEW(img); Raster.Load(img, name, done); 
		IF ~done THEN img := NIL END;
	END;
	AosOut.Ln; 
	RETURN img	
END GetImage;

PROCEDURE Rearrange;
VAR ptr : PTR; i : LONGINT; manager : WMWindowManager.WindowManager;
BEGIN
	(* rearrange backrops so the latest added is on top to avoid confusion in the user *)
	manager := WMWindowManager.GetDefaultManager();
	windowList.Lock;
	FOR i := windowList.GetCount() - 1 TO 0 BY -1 DO 
		ptr := windowList.GetItem(i);
		manager.ToBack(ptr(WMWindowManager.Window))
	END;
	windowList.Unlock;	
END Rearrange;
	
(**
	parameters x y w h
	defaults : x = 0 y = 0 w = img.width h = img.height
	any parameter can be replaced by ? to use the respective position or size of the current viewport *)
PROCEDURE AddBackdropImage*(par : PTR) : PTR;
VAR manager : WMWindowManager.WindowManager;
	bw : Window;
	img : WMGraphics.Image;
	x, y, w, h, tx, ty, tw, th : LONGINT;
	name : ARRAY 256 OF CHAR;
	s : AosCommands.Parameters;
	sr : AosIO.StringReader;
BEGIN {EXCLUSIVE}
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.Token(name); sr.SkipWhitespace();
	(* search if img is already loaded... *)
	
	img := GetImage(name);

	IF img # NIL THEN sr.SkipWhitespace();
		DefaultPos(tx, ty, tw, th);
		IF sr.Peek() = '?' THEN x := tx 
		ELSE x := 0;
			IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(x, TRUE) END; sr.SkipWhitespace()
		END;
		
		IF sr.Peek() = '?' THEN y := ty
		ELSE y := 0;
			IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(y, TRUE) END; sr.SkipWhitespace()
		END;
		IF sr.Peek() = '?' THEN w := tw
		ELSE w := img.width;
			IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(w, TRUE) END; sr.SkipWhitespace()
		END;
		IF sr.Peek() = '?' THEN h := th
		ELSE h := img.height; 
			IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(h, TRUE) END; sr.SkipWhitespace()
		END;
		NEW(bw);
		COPY(name, bw.picname);
		bw.bounds := WMRectangles.MakeRect(0, 0, w, h);
		bw.img := img;
		windowList.Add(bw);
		bw.SetPointerInfo(followPointer);
		manager := WMWindowManager.GetDefaultManager();
		manager.Add(x, y, bw, {});
		Rearrange
	END;
	RETURN NIL
END AddBackdropImage;

PROCEDURE Restore*(par : ANY) : ANY;
VAR w : Window;
	 xml : XML.Element;
	 s : Utilities.String; img : WMGraphics.Image;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		(* restore the desktop *)
		IF par(WMRestorable.Context).appData # NIL THEN
			xml := par(WMRestorable.Context).appData(XML.Element);
			s := xml.GetAttributeValue("file"); 
			IF s # NIL THEN
				img := GetImage(s^);
				IF img # NIL THEN
					NEW(w);
					COPY(s^, w.picname);
					w.img := img;
					windowList.Add(w);
					WMRestorable.AddByContext(w, par(WMRestorable.Context) ,{});
					Rearrange
				END
			END	
		END			
	END;
	RETURN NIL
END Restore;

PROCEDURE Cleanup;
VAR manager : WMWindowManager.WindowManager;
	ptr : PTR;
	i : LONGINT;
BEGIN
	manager := WMWindowManager.GetDefaultManager();
	windowList.Lock;
	FOR i := 0 TO windowList.GetCount() - 1 DO 
		ptr := windowList.GetItem(i); 
		manager.Remove(ptr(WMWindowManager.Window))
	END;
	windowList.Unlock;
END Cleanup;

PROCEDURE RemoveAll*(par : PTR) : PTR;
BEGIN
	Cleanup;
	RETURN NIL
END RemoveAll;

BEGIN
	WMWindowManager.LoadCursor("traditional.arrow.png", 0, 0, followPointer);
	NEW(windowList);
	AosModules.InstallTermHandler(Cleanup)
END WMBackdrop.


S.Free WMBackdrop ~

(* install backdrop at current view position and size *)
WMBackdrop.AddBackdropImage BluebottlePic0.png ? ? ? ?
WMBackdrop.AddBackdropImage AosBackdrop.png ? ? ? ?

(* install backdrop at specified position with original size of the image *)
WMBackdrop.AddBackdropImage BluebottlePic0.png 0 0 ~
WMBackdrop.AddBackdropImage AosBackdrop.png 1280 0 ~


