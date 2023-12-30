MODULE WMBackdrop;	(** AUTHOR "TF"; PURPOSE "Backdrop images"; *)

(* 03-04-03	RG: Context menu support added *)

IMPORT
	AosKernel, AosFS, AosOut, AosIO, AosModules, AosCommands, Utilities, WMRectangles, Raster, WMMessages, 
	WMWindowManager, WMGraphics, TFClasses, WMPopups, WMComponents, WMRestorable, WMDialogs, XML;

CONST
	ImagesFile = "Wallpapers.txt";

TYPE

	ImageInfo = RECORD
		filename: AosFS.FileName;
		img: WMGraphics.Image;
	END;

	Window = OBJECT(WMWindowManager.Window)
	VAR 
		img : WMGraphics.Image;
		picname : ARRAY 256 OF CHAR;
		changeable, stop: BOOLEAN;
		interval: LONGINT; (* in seconds *)
		timer : AosKernel.Timer;
		currentImg: LONGINT;		
		
		PROCEDURE & New;
		BEGIN
			NEW(timer);
		END New;
		
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
					IF (imgList # NIL) & (LEN(imgList) > 0) THEN contextMenu.Add("Next", Change) END;
					IF changeable THEN						
						contextMenu.Add("Stop Change", HandleChangeable)
					ELSE
						contextMenu.Add("Change", HandleChangeable)
					END;
					contextMenu.Add("Remove", HandleRemove);
					contextMenu.Popup(bounds.l+x, bounds.t+y)
				END
			END
		END PointerDown;
		
		PROCEDURE SetChangeable(c: BOOLEAN);
		BEGIN{EXCLUSIVE}
			changeable := c
		END SetChangeable;
		
		
		PROCEDURE HandleChangeable(sender, data: PTR);
		VAR str: ARRAY 32 OF CHAR; dr: LONGINT;
		BEGIN
			IF changeable THEN
				SetChangeable(FALSE);
				timer.Wakeup();
			ELSE
				str := "1800";
				dr := WMDialogs.QueryString("Interval (in sec.)", str);
				IF dr = WMDialogs.ResOk THEN
					Utilities.StrToInt(str, dr);
					IF dr > 0 THEN
						interval := dr * 1000;
					ELSE
						interval := 30 * 1000;
					END
				ELSE
					interval := 30 * 1000;
				END;

				SetChangeable(TRUE);
			END
		END HandleChangeable;
		
		
		
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
			Stop();
			manager.SetFocus(SELF);
			manager.Remove(SELF);
			windowList.Remove(SELF)
		END HandleRemove;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		VAR data : XML.Element; a : XML.Attribute; n : ARRAY 32 OF CHAR;
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS WMRestorable.Storage) THEN
					NEW(data);  n := "Data"; data.SetName(n);
					NEW(a); n := "file"; a.SetName(n); a.SetValue(picname); data.AddAttribute(a);
					NEW(a); n := "changeable"; a.SetName(n); 
					IF changeable THEN Utilities.IntToStr(interval, n); ELSE n := "0" END;
					a.SetValue(n); data.AddAttribute(a);
					x.ext(WMRestorable.Storage).Add("Backdrop", "WMBackdrop.Restore", SELF, data)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;

		PROCEDURE Change(sender, data: ANY);
		VAR index, x, y, w, h: LONGINT; img : WMGraphics.Image;
		BEGIN
			IF imgList # NIL THEN
				
				REPEAT
					INC(currentImg);
					index := currentImg  MOD LEN(imgList);
				UNTIL (imgList[index].filename # "");
								
				AosOut.String("Changing to  "); AosOut.String(imgList[index].filename); AosOut.Ln; 

				IF imgList[index].img = NIL THEN					
					img := GetImage(imgList[index].filename, GetWidth(), GetHeight());
					IF img = NIL THEN 
						AosOut.String("Image could not be loaded."); AosOut.Ln; 
						RETURN 
					ELSE
						imgList[index].img := img;
					END
				END;
				BEGIN{EXCLUSIVE}
					COPY(imgList[index].filename, picname);				
					SELF.img := imgList[index].img;
					Invalidate(WMRectangles.MakeRect(0, 0, GetWidth(), GetHeight()))
				END
			END
		END Change;
		
		PROCEDURE Stop;
		BEGIN
			BEGIN{EXCLUSIVE}
				stop := TRUE;	
			END;
			timer.Wakeup();
			BEGIN {EXCLUSIVE}
				AWAIT(~stop)
			END
		END Stop;
				

	BEGIN {ACTIVE}
		LOOP		
			BEGIN {EXCLUSIVE} 
				AWAIT(changeable OR stop);		
			END;
			IF stop THEN EXIT END;
			Change(NIL, NIL);
			timer.Sleep(interval);					
			IF stop THEN EXIT END
		END;
		
		BEGIN{EXCLUSIVE}
			stop := FALSE;
		END
	END Window;
	
VAR 
	windowList : TFClasses.List;
	imgList: POINTER TO ARRAY OF ImageInfo;
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

PROCEDURE GetImage(name : ARRAY OF CHAR; w, h : LONGINT) : WMGraphics.Image;
VAR img, t : WMGraphics.Image;
	done : BOOLEAN;
	i, count : LONGINT; ptr : ANY;
	c : WMGraphics.BufferCanvas;
BEGIN
	img := NIL;
	windowList.Lock;
	i := 0; count := windowList.GetCount();
	WHILE (img = NIL) & (i < count) DO 
		ptr := windowList.GetItem(i);
		IF (ptr(Window).picname = name) & (
			(ptr(Window).img.width = w) & (ptr(Window).img.height = h) 
			OR ( (w = 0) OR (h = 0)))
		 THEN 
			img := ptr(Window).img 
		END;
		INC(i)
	END;
	windowList.Unlock;
	IF img = NIL THEN 
		t := WMGraphics.LoadImage(name, TRUE);
		IF t # NIL THEN 
			IF w = 0 THEN w := t.width END;
			IF h = 0 THEN h := t.height END;
			NEW(img); Raster.Create(img, w, h, Raster.BGR565);
			NEW(c, img);
			c.ScaleImage(t, WMRectangles.MakeRect(0, 0, t.width-1, t.height-1), WMRectangles.MakeRect(0, 0, w, h), 
				WMGraphics.ModeCopy, WMGraphics.ScaleBilinear);
		END	
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
	sr.String(name); sr.SkipWhitespace();
	(* search if img is already loaded... *)

	DefaultPos(tx, ty, tw, th);
	IF sr.Peek() = '?' THEN x := tx; sr.SkipBytes(1); sr.SkipWhitespace();
	ELSE x := 0;
		IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(x, TRUE) END; sr.SkipWhitespace();
	END;
	
	IF sr.Peek() = '?' THEN y := ty; sr.SkipBytes(1); sr.SkipWhitespace();
	ELSE y := 0;
		IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(y, TRUE) END; sr.SkipWhitespace();
	END;
	IF sr.Peek() = '?' THEN w := tw; sr.SkipBytes(1); sr.SkipWhitespace();
	ELSE w := 0;
		IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(w, TRUE) END; sr.SkipWhitespace();
	END;
	IF sr.Peek() = '?' THEN h := th; sr.SkipBytes(1); sr.SkipWhitespace();
	ELSE h := 0; 
		IF (sr.Peek() >= '0') & (sr.Peek() <= '9') OR (sr.Peek() = '-') THEN sr.Int(h, TRUE) END; sr.SkipWhitespace();
	END;
	img := GetImage(name, w, h);
	
	IF img = NIL THEN AosOut.String("Image could not be loaded."); AosOut.Ln; RETURN NIL END;
	
	NEW(bw);
	COPY(name, bw.picname);
	bw.bounds := WMRectangles.MakeRect(0, 0, w, h);
	bw.img := img;
	windowList.Add(bw);
(*		bw.SetPointerInfo(followPointer); *)
	manager := WMWindowManager.GetDefaultManager();
	manager.Add(x, y, bw, {WMWindowManager.FlagStayOnBottom});
	Rearrange;

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
				img := GetImage(s^, 0, 0);
				IF img # NIL THEN
					NEW(w);
					COPY(s^, w.picname);
					w.img := img;
					windowList.Add(w);
					WMRestorable.AddByContext(w, par(WMRestorable.Context) ,{});
					Rearrange
				END
			END;
			s := xml.GetAttributeValue("changeable");
			IF (s # NIL) & (w # NIL) THEN
				IF s^ # "0" THEN 
					Utilities.StrToInt(s^, w.interval);
					IF w.interval > 500 THEN
						w.SetChangeable(TRUE);
					END;
				END;
			END	
		END			
	END;
	RETURN NIL
END Restore;

PROCEDURE Cleanup;
VAR manager : WMWindowManager.WindowManager;
	ptr : PTR;
	w: Window;
	i : LONGINT;
BEGIN
	manager := WMWindowManager.GetDefaultManager();
	windowList.Lock;
	FOR i := 0 TO windowList.GetCount() - 1 DO 
		ptr := windowList.GetItem(i); 
		w := ptr(Window);
		w.Stop;
		manager.Remove(ptr(WMWindowManager.Window))
	END;
	windowList.Unlock;
END Cleanup;



PROCEDURE RemoveAll*(par : PTR) : PTR;
BEGIN
	Cleanup;
	RETURN NIL
END RemoveAll;

PROCEDURE ChangeList;
VAR
	f: AosFS.File; 
	r: AosFS.Reader; 
	i, nr: LONGINT;

	PROCEDURE NumberImg(): LONGINT;
	VAR line: AosFS.FileName; r: AosFS.Reader; nr: LONGINT;
	BEGIN
		AosFS.OpenReader(r, f, 0);						
		WHILE (r.res = AosIO.Ok) DO
			r.Ln(line); 
			INC(nr);			
		END;
		RETURN nr;											
	END NumberImg;
	
	
BEGIN
	f := AosFS.Old(ImagesFile);
	IF (f # NIL) THEN
		nr := NumberImg();
		AosOut.String("nr= "); AosOut.Int(nr, 0); AosOut.Ln; 
		NEW(imgList, nr);
		AosFS.OpenReader(r, f, 0);								
		i := 0;
		WHILE (r.res = AosIO.Ok) DO			
			r.Ln(imgList[i].filename);
			AosOut.String(imgList[i].filename); AosOut.Ln; 
			INC(i);
		END
	ELSE
		AosOut.String("No image list found");AosOut.Ln; 			
	END
END ChangeList;


BEGIN
(*	WMWindowManager.LoadCursor("traditional.arrow.png", 0, 0, followPointer); *)
	NEW(windowList);
	ChangeList();
	AosModules.InstallTermHandler(Cleanup)
END WMBackdrop.


S.Free WMBackdrop ~

(* install backdrop at current view position and size *)
WMBackdrop.AddBackdropImage "Desktop1_1024x768.png" ? ? ? ?
WMBackdrop.AddBackdropImage AosBackdrop.png ? ? ? ?

(* install backdrop at specified position with original size of the image *)
WMBackdrop.AddBackdropImage BluebottlePic0.png 0 0 ~
WMBackdrop.AddBackdropImage AosBackdrop.png 1280 0 ~


