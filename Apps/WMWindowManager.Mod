MODULE WMWindowManager;	(** AUTHOR "TF"; PURPOSE "Generic window manager"; *)

(* 03-04-03: RG: Added initialbounds *)

IMPORT
	AosOut, Utilities,  
	AosActive, AosModules, AosPlugins, 
	Locks := WMLocks,
	Messages := WMMessages, 
	Graphics := WMGraphics, Raster, Rectangles := WMRectangles;

CONST
	FlagFrame* = 0; (** The window has a frame *)
	FlagClose* = 1; (** The window offers a close button; only frame windows *)
	FlagMinimize* = 2; (** The window offers a minimize button *)
	FlagStayOnTop* = 3; (** The window will always stay above all non stay on top windows *)
	FlagNonDispatched* = 4; (** The window has no message queue --> BE CAREFUL *)
	FlagNoFocus* = 5; (** The window can never get the keyboard focus *)
	FlagDecorWindow* = 6; (** The window is a decor window, associated to a master window *)
	
	SizeMinHeight = 3; (* Minimum height of a window *)
	SizeMinWidth = 3; (* Minimum width of a window *)

TYPE
	Rectangle = Rectangles.Rectangle;
	String = Utilities.String;
	Message = Messages.Message;
	MsgSequencer = Messages.MsgSequencer;
	RealRect* = RECORD l*, t*, r*, b* : REAL END;
	
	PointerInfo* = OBJECT
	VAR hotX*, hotY* : LONGINT; img* : Graphics.Image;
	END PointerInfo;
	
	WindowStyle* = OBJECT
	VAR taa*, tab*, tac*, tia*, tib*, tic*,
		laa*, lab*, lac*, lia*, lib*, lic*,
		raa*, rab*, rac*, ria*, rib*, ric*,
		baa*, bab*, bac*, bia*, bib*, bic*,
		ca*, ci*, cs* : Graphics.Image;
		th*, bh*, lw*, rw* : LONGINT;
		atextX*, atextY*, itextX*, itextY* : LONGINT;
		atextColor*, itextColor* : LONGINT;
		bgColor*, fgColor*, selectCol*, desktopColor* : Graphics.Color;
		style* : LONGINT; (* 0 = simple; 2 = bitmap *)
		baCol*, biCol*, basw*, bisw* : LONGINT;
	END WindowStyle;

	DragInfo* = OBJECT
	VAR
		data*, sender* : PTR;
		onAccept*, onReject* : Messages.CompCommand;
	END DragInfo;
	
	(** List of decoration - windows to a master window *)
	DecorList* = OBJECT
	VAR next* : DecorList;
		w* : Window;
	END DecorList;
	
	(** A message preview procedure can set discard to TRUE to discard the message *)
	MessagePreviewProc* = PROCEDURE (VAR msg : Message; VAR discard : BOOLEAN);
	MessagePreviewList* = OBJECT
	VAR proc*: MessagePreviewProc;
			next*:MessagePreviewList;
	END MessagePreviewList;
	
	Window* = OBJECT
	VAR
		width, height : LONGINT; (* user coordinate space from 0..width-1, 0..height-1 *)
		bounds* : Rectangle; (** Range in global coordinates *)
		initialBounds* : Rectangle; (** Range in global coordinates at window creation *)
		
		manager* : WindowManager;
		sequencer* : MsgSequencer;
		
		(** window state that may only be accessed by the window manager *)
		prev*, next* : Window; (** previous and next  window in z order *)
		title : String; (* window title *)
		master* : Window; (** is only set if the window is a decor window *)
		decor* : DecorList;
		flags* : SET;
		icon* : Graphics.Image; (** Optional icon for Window *)
		topW*, bottomW*, leftW*, rightW* : Window; (** Optional decor windows *)
			useAlpha* : BOOLEAN;
		pointerInfo- : PointerInfo;
		acceptDrag : BOOLEAN;
		reduceQuality- : BOOLEAN;
		
		PROCEDURE IsCallFromSequencer*() : BOOLEAN;
		BEGIN
			RETURN (sequencer # NIL) & (sequencer.IsCallFromSequencer())
		END IsCallFromSequencer;
		
		(** Return the window manager that handles the window *)
		PROCEDURE GetManager*() : WindowManager;
		BEGIN
			RETURN manager
		END GetManager;
		
		(** Set the window title as UTF8 string. *)
		PROCEDURE SetTitle*(title : String);
		BEGIN
			IF manager # NIL THEN manager.SetWindowTitle(SELF, title) ELSE SELF.title := title END
		END SetTitle;
		
		(** Return the title as UTF8 string. Returns NIL if no title is set *)
		PROCEDURE GetTitle*() : String;
		BEGIN
			IF manager # NIL THEN RETURN manager.GetWindowTitle(SELF) ELSE RETURN title END
		END GetTitle;
		
		(** Return the height in client space *) (* go via manager *)
		PROCEDURE GetHeight*() : LONGINT;
		BEGIN
			RETURN bounds.b - bounds.t
		END GetHeight;
		
		(** Return the width in client space *) (* go via manager *)
		PROCEDURE GetWidth*() : LONGINT;
		BEGIN
			RETURN bounds.r - bounds.l
		END GetWidth;
		
		(** Resize is called by the WM if it wants to resize the window. 
			width and height contain the desired new size. The Window should set width and height to acceptable 
			values or return the current size, if resize is not supported *)
		PROCEDURE Resizing*(VAR width, height : LONGINT);
			BEGIN
			IF width < SizeMinWidth THEN width := GetWidth() END;
			IF height < SizeMinHeight THEN height := GetHeight() END
		END Resizing;
		
		(** May replace the back-image, if needed. MUST check if requested size is reasonable (0 < x * y < memory) *)
		PROCEDURE Resized*(width, height : LONGINT);
		BEGIN
		END Resized;
		
		(** Invalidate a rectangle in window coordinates*)
		PROCEDURE Invalidate*(rect : Rectangle);
		BEGIN
			Rectangles.MoveRel(rect, bounds.l, bounds.t);
			Rectangles.ClipRect(rect, bounds);
			IF manager # NIL THEN manager.AddVisibleDirty(SELF, rect) END
		END Invalidate;
		
(** Message procedures *)
	(** Pointer Messages *)
		(** PointerDown is called via the generic message handler if the pointer (or a mouse button) is pressed down and
			a) the pointer is in the bounding box of the window AND IsHit returns TRUE for this position
			or
			b) another mouse button was pressed down on a position where a) was met and has not yet been released.
			  
			x and y are in window coordinates but may lie out of the window boundaries in case b) 
			keys is the set of buttons that are down 
		*)
		PROCEDURE PointerDown*(x, y : LONGINT; keys : SET);
		BEGIN
		END PointerDown;
		
		(** PointerMove is called via the generic message handler if the pointer (mouse) is moved and
			a) the pointer is in the bounding box of the window AND IsHit returns TRUE for this position
			or
			b) the pointer was pressed down on a position where a) was met and has not yet been released.
			  
			x and y are in window coordinates but may lie out of the window boundaries. 
			keys is the set of buttons that are down
		*)
		PROCEDURE PointerMove*(x, y : LONGINT; keys : SET);
		BEGIN
		END PointerMove;
		
		PROCEDURE WheelMove*(dz : LONGINT);
		BEGIN
		END WheelMove;
		
		(** PointerUp is called via the generic message handler if the pointer (or a mouse button) went up. 
			x and y are in window coordinates but may lie out of the window boundaries. 
			keys is the set of buttons that are STILL DOWN
		*)
		PROCEDURE PointerUp*(x, y : LONGINT; keys : SET);
		BEGIN
		END PointerUp;
		
		(** PointerLeave is called via the generic message handler if the pointer has left the window with no button pressed. *)		
		PROCEDURE PointerLeave*;
		BEGIN
		END PointerLeave;
		
		(** DragOver is called via the message handler. *)
		PROCEDURE DragOver*(x, y: LONGINT; dragInfo : DragInfo);
		BEGIN
		END DragOver;
		
		(** Dropped is called via the message handler to indicate an item has been dropped. *)
		PROCEDURE DragDropped*(x, y: LONGINT; dragInfo : DragInfo);
		BEGIN
		END DragDropped;
		
		(** send the srcWindow a confirmation for the completed drag operation *)
		PROCEDURE ConfirmDrag*(accept : BOOLEAN; dragInfo : DragInfo);
		BEGIN
			IF dragInfo # NIL THEN
				IF accept THEN
					IF dragInfo.onAccept # NIL THEN dragInfo.onAccept(SELF, dragInfo) END
				ELSE
					IF dragInfo.onReject # NIL THEN dragInfo.onReject(SELF, dragInfo) END
				END
			END
		END ConfirmDrag;
		
		(** Start a drag operation. *)
		PROCEDURE StartDrag*(sender, data : PTR; img : Graphics.Image; onAccept, onReject : Messages.CompCommand) : BOOLEAN;
		BEGIN
			RETURN manager.StartDrag(SELF, sender, data, img, onAccept, onReject)
		END StartDrag;
		
	(** Keyboard message *)	
		(** KeyEvent is called via the generic message handler to signal a keyboard event.
			The window can determine wheter the key was pressed or released by examining the
			AosInputs.Release flag in flags. ucs contains the unicode equivalent of the key. Special input editors
			send the generated unicode characters via KeyEvent.  *)
		PROCEDURE KeyEvent*(ucs : LONGINT; flags : SET; keysym : LONGINT);
		BEGIN
		END KeyEvent;
		
(**  Focus messages *)
		(** FocusGot is called via the generic message handler if the keyboard focus is transfered to this window *)
		PROCEDURE FocusGot*;
		BEGIN
		END FocusGot;
		
		(** FocusList is called via the generic message handler if the keyboard focus is transfered to some other window *)
		PROCEDURE FocusLost*;
		BEGIN
		END FocusLost;
		
(** Style *)
		(** StyleChanged is called via the generic message handler if a change in the global style occurs. The
			Window should read all the style information it relies on and redraw itself *)
		PROCEDURE StyleChanged*();
		BEGIN
		END StyleChanged;

(** Closing *)
		PROCEDURE CanClose*() : BOOLEAN;
		BEGIN
			RETURN TRUE
		END CanClose;
		
		(** Close is called via the generic message handler. *)
		PROCEDURE Close*;
		BEGIN
			IF manager # NIL THEN manager.Remove(SELF) END
		END Close;
		
		(** Return true if the window is hit at the coordinates x and y (in window coordinates). Use
			this to generate non-rectangular windows.
			This Method will be called directly by the window manager. __> Don't block, don't crash !!
			*)
		PROCEDURE IsHit*(x, y : LONGINT) : BOOLEAN;
		BEGIN
			RETURN TRUE
		END IsHit;
		
		PROCEDURE SetPointerInfo*(pi : PointerInfo);
		BEGIN
			IF pi # pointerInfo THEN 
				pointerInfo := pi;
				IF manager # NIL THEN manager.CheckPointerImage END
			END
		END SetPointerInfo;
		
		(** Generic message handler distributes messages to the different msg-handler methods *)
		PROCEDURE Handle*(VAR m : Message);
		BEGIN 
			IF m.msgType = Messages.MsgKey THEN 
				KeyEvent(m.x, m.flags, m.y)
			ELSIF m.msgType = Messages.MsgPointer THEN 
				IF m.msgSubType = Messages.MsgSubPointerMove THEN 
					IF (m.dz # 0) THEN WheelMove(m.dy) END;
(*					IF (m.dx # 0) OR (m.dy # 0) OR TRUE THEN PointerMove(m.x, m.y, m.flags) END; *)
					PointerMove(m.x, m.y, m.flags)
				ELSIF m.msgSubType = Messages.MsgSubPointerDown THEN PointerDown(m.x, m.y, m.flags)
				ELSIF m.msgSubType = Messages.MsgSubPointerUp THEN PointerUp(m.x, m.y, m.flags)
				ELSIF m.msgSubType = Messages.MsgSubPointerLeave THEN PointerLeave
				END
			ELSIF m.msgType = Messages.MsgDrag THEN 
				IF m.msgSubType = Messages.MsgDragOver THEN 
					IF (m.ext # NIL) THEN 
						DragOver(m.x, m.y, m.ext(DragInfo)) 
					END
				ELSIF m.msgSubType = Messages.MsgDragDropped THEN 
					IF (m.ext # NIL) THEN 
						DragDropped(m.x, m.y, m.ext(DragInfo))
					END
				END
			ELSIF m.msgType = Messages.MsgClose THEN Close
			ELSIF m.msgType = Messages.MsgFocus THEN
				IF m.msgSubType = Messages.MsgSubFocusGot THEN FocusGot
				ELSIF m.msgSubType = Messages.MsgSubFocusLost THEN FocusLost
				END
			ELSIF m.msgType = Messages.MsgStyleChanged THEN StyleChanged
			ELSIF m.msgType = Messages.MsgResized THEN Resized(m.x, m.y)
			END;
		END Handle;
		
		(** Draw request form the window manager. The canvas becomes invalid when the method ends. The
		draw method may not modify window or WindowManager properties.
		w, h is the area in view coordinates, q is the Quality 0 lowest 1 mid 2 high. A window may ignore q  *)
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		BEGIN
		END Draw;
		
		(** Is called by the windowmanager with reduce set, if the window is resized or moved on slow machines *)
		PROCEDURE HintReduceQuality*(reduce : BOOLEAN);
		BEGIN
			IF reduce # reduceQuality THEN
				reduceQuality := reduce;
				IF ~reduceQuality THEN 
					IF manager # NIL THEN manager.AddVisibleDirty(SELF, bounds) END
				END
			END
		END HintReduceQuality;
	
	END Window;

	(** assumes the window is size agnostic, handles all the zooming issues directly *)
	BufferWindow* = OBJECT(Window)
	VAR
		img* : Graphics.Image;
		canvas* : Graphics.BufferCanvas;
		pointerThreshold* : LONGINT;
		fx, fy : REAL;
		
		PROCEDURE &Init*(w, h : LONGINT; alpha : BOOLEAN);
		BEGIN
			bounds := Graphics.MakeRectangle(0, 0, w, h);
			initialBounds := bounds;
			useAlpha := alpha;
			NEW(img);
			IF alpha THEN Raster.Create(img, w, h, Raster.BGRA8888) ELSE Raster.Create(img, w, h, Raster.BGR565) END; 
			NEW(canvas, img);
		END Init;
		
		PROCEDURE IsHit(x, y  : LONGINT) : BOOLEAN;
		VAR w, h : LONGINT; fx, fy : REAL;
		BEGIN
			w := GetWidth(); h := GetHeight();
			IF (w > 0) & (h > 0) & ((w # img.width) OR (h # img.height)) THEN
				fx := img.width / w; fy := img.height / h;
				RETURN Graphics.IsBitmapHit(ENTIER(x * fx), ENTIER(y * fy), pointerThreshold, img)
			ELSE RETURN Graphics.IsBitmapHit(x, y, pointerThreshold, img)
			END	
		END IsHit;
		
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		BEGIN
			IF reduceQuality THEN q := 0 END;
			IF img # NIL THEN
				IF (w = img.width) & (h = img.height) THEN
					IF useAlpha THEN canvas.DrawImage(0, 0, img, Graphics.ModeSrcOverDst) 
					ELSE canvas.DrawImage(0, 0, img, Graphics.ModeCopy)
					END 
				ELSE  
					IF useAlpha THEN 
						canvas.ScaleImage(img, Rectangles.MakeRect(0, 0, img.width, img.height), 
							Rectangles.MakeRect(0, 0, w, h), Graphics.ModeSrcOverDst, q)
					ELSE
						canvas.ScaleImage(img, Rectangles.MakeRect(0, 0, img.width, img.height), 
							Rectangles.MakeRect(0, 0, w, h), Graphics.ModeCopy, q)
					END	
				END	
			END
		END Draw;
		
		PROCEDURE Invalidate*(rect : Rectangle);
		VAR w, h : LONGINT; fx, fy : REAL;
		BEGIN
			w := GetWidth(); h := GetHeight();
			IF (w > 0) & (h > 0) & ((w # img.width) OR (h # img.height))  THEN
				fx := w / img.width; fy := h / img.height; 
				rect.l := ENTIER(rect.l * fx); rect.t := ENTIER(rect.t * fy);
				rect.r := ENTIER(rect.r * fx + 0.5); rect.b := ENTIER(rect.b * fy + 0.5)
			END;
			Invalidate^(rect)
		END Invalidate;
		
		PROCEDURE Handle*(VAR m : Message);
		VAR w, h : LONGINT; fx, fy : REAL;
		BEGIN 
			w := GetWidth(); h := GetHeight();
			IF (w > 0) & (h > 0) & ((w # img.width) OR (h # img.height)) & (m.msgType = Messages.MsgPointer) THEN
				fx := img.width / w; fy := img.height / h; m.x := ENTIER(m.x * fx); m.y := ENTIER(m.y * fy)
			END;
			Handle^(m)
		END Handle;
		
	END BufferWindow;
	
	DoubleBufferWindow* = OBJECT(BufferWindow)
	VAR
		visibleCanvas : Graphics.BufferCanvas;
		backImg* : Graphics.Image;
		swapping, drawing : BOOLEAN;
		
		PROCEDURE &Init*(w, h: LONGINT; alpha : BOOLEAN);
		BEGIN
			Init^(w, h, alpha);
			NEW(backImg); Raster.Create(backImg, w, h, img.fmt); 
			visibleCanvas := canvas; NEW(canvas, backImg);
		END Init;
		
		PROCEDURE ReInit*(w, h : LONGINT);
		BEGIN {EXCLUSIVE}
			AWAIT(~drawing);
		(*	 NEW(backImg); (* because the old can still bedrawn to by the unaware app *) *)
			IF useAlpha THEN
				 Raster.Create(img, w, h, Raster.BGRA8888);
				 Raster.Create(backImg, w, h, Raster.BGRA8888) 
			ELSE 
				Raster.Create(img, w, h, Raster.BGR565);
				Raster.Create(backImg, w, h, Raster.BGR565) 
			END; 
			NEW(visibleCanvas, img); NEW(canvas, backImg)
		END ReInit;
		
		
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		BEGIN
			BEGIN{EXCLUSIVE}
				AWAIT(~swapping); drawing := TRUE;
			END;
			IF reduceQuality THEN q := 0 END;
			IF img # NIL THEN 
				IF (w = img.width) & (h = img.height) THEN
					IF useAlpha THEN canvas.DrawImage(0, 0, img, Graphics.ModeSrcOverDst) 
					ELSE canvas.DrawImage(0, 0, img, Graphics.ModeCopy)
					END 
				ELSE  
					IF useAlpha THEN 
						canvas.ScaleImage(img, Rectangles.MakeRect(0, 0, img.width, img.height),  
							Rectangles.MakeRect(0, 0, w, h), Graphics.ModeSrcOverDst, q)
					ELSE
						canvas.ScaleImage(img, Rectangles.MakeRect(0, 0, img.width, img.height),  
							Rectangles.MakeRect(0, 0, w, h), Graphics.ModeCopy, q)
					END
				END	
			END;
			BEGIN{EXCLUSIVE}
				drawing := FALSE;
			END;
		END Draw;
		
		PROCEDURE CopyRect*(rect : Rectangle);
		BEGIN {EXCLUSIVE}
			swapping := TRUE;
			AWAIT(~drawing);
			visibleCanvas.SetClipRect(rect);
			visibleCanvas.DrawImage(0, 0, backImg, Graphics.ModeCopy);
			visibleCanvas.SetClipRect(visibleCanvas.limits);
			swapping := FALSE
		END CopyRect;
		
		PROCEDURE Swap*;
		VAR tmp : Graphics.Image; tmpc : Graphics.BufferCanvas;
		BEGIN {EXCLUSIVE}
			swapping := TRUE;
			AWAIT(~drawing);
			tmp := img; img := backImg; backImg := tmp;
			tmpc := canvas; canvas := visibleCanvas; visibleCanvas := tmpc;
			swapping := FALSE
		END Swap;
	
	END DoubleBufferWindow;
	
	
	(** A ViewPort observes the global coordinate space. The WindowManager calls the view on all changes that occur
		in the observed range. *)
	ViewPort* = OBJECT (AosPlugins.Plugin)
		VAR next* : ViewPort;
			manager* : WindowManager;
			range* : RealRect;
	
		(** The WindowManager calls the Update Procedure in locked state. *)
		PROCEDURE Update*(r : Rectangle; top : Window);
		BEGIN
		END Update;
		
		(** The WindowManager calls the Update Procedure in locked state. *)
		PROCEDURE Refresh*(top : Window);
		BEGIN
		END Refresh;
		
		(** Set the observed range *)
		PROCEDURE SetRange*(x, y, w, h : REAL; showTransition : BOOLEAN);
		BEGIN
		END SetRange;
		
	END ViewPort;
	
	Decorator* = PROCEDURE {DELEGATE} (w : Window);
	
	WindowManager* = OBJECT(AosPlugins.Plugin)
	VAR
		pointerNull*, pointerStandard*, pointerMove*, pointerText*, pointerCrosshair*,
		pointerLeftRight*, pointerUpDown*, pointerULDR*, pointerURDL* : PointerInfo;
		decorate* : Decorator;
		viewRegistry* : AosPlugins.Registry;
		me* : PTR; (** the window manager thread for assertions *)
		lock* : Locks.RWLock; (** PROTECTED *)
		sequencer* : Messages.MsgSequencer; (** PROTECTED *)
		messagePreviewList* : MessagePreviewList;
		style : WindowStyle;
			
		PROCEDURE &Init;
		BEGIN
			LoadCursor("S2004.arrow.png", 0, 0, pointerStandard);
			LoadCursor("S2004.move.png", 15, 15, pointerMove);
			LoadCursor("S2004.text.png", 13, 12, pointerText);
			LoadCursor("S2004.crosshair.png", 13, 12, pointerCrosshair);
			LoadCursor("S2004.uldr.png", 13, 12, pointerULDR);
			LoadCursor("S2004.updown.png", 13, 12, pointerUpDown);
			LoadCursor("S2004.leftright.png", 13, 12, pointerLeftRight);
			NEW(pointerNull);
			NEW(viewRegistry, "EXPView#", "Views in the Experimental Window Manager");
			NEW(sequencer, Handle); lock := sequencer.lock;
			NEW(style); InitStyle;
		END Init;
		
		PROCEDURE InitStyle;
		VAR s : WindowStyle;
				PROCEDURE Load(VAR img : Graphics.Image; name : ARRAY OF CHAR);
				BEGIN
					img := Graphics.LoadImage(name, TRUE);
				END Load;
		BEGIN
			s := style;
	(*		(* Top *)
			Load(s.taa, "blueplastic.atl.png"); Load(s.tab, "blueplastic.atm.png"); Load(s.tac, "blueplastic.atr.png");
			Load(s.tia, "blueplastic.itl.png"); Load(s.tib, "blueplastic.itm.png"); Load(s.tic, "blueplastic.itr.png");
			Load(s.ci, "blueplastic.iclose.png"); Load(s.ca, "blueplastic.aclose.png");
			
			(* Left *)
			Load(s.laa, "blueplastic.alt.png"); Load(s.lab, "blueplastic.alm.png"); Load(s.lac, "blueplastic.alb.png");
			Load(s.lia, "blueplastic.ilt.png"); Load(s.lib, "blueplastic.ilm.png"); Load(s.lic, "blueplastic.ilb.png");
			(* Right *)
			Load(s.raa, "blueplastic.art.png"); Load(s.rab, "blueplastic.arm.png"); Load(s.rac, "blueplastic.arb.png");
			Load(s.ria, "blueplastic.irt.png"); Load(s.rib, "blueplastic.irm.png"); Load(s.ric, "blueplastic.irb.png");
			
			(* Bottom *)
			Load(s.baa, "blueplastic.abl.png"); Load(s.bab, "blueplastic.abm.png"); Load(s.bac, "blueplastic.abr.png");
			Load(s.bia, "blueplastic.ibl.png"); Load(s.bib, "blueplastic.ibm.png"); Load(s.bic, "blueplastic.ibr.png");
			*)
			s.style := 0; s.baCol := 0FFFFH; s.biCol := 0FF40H; s.basw := 4; s.bisw := 3;
			s.th := 20; s.lw := 3; s.rw := 3; s.bh := 3; s.atextX := 5; s.atextY := 15; s.itextX := 5; s.itextY := 15;
			s.atextColor := 0FFFF00FFH; s.itextColor := 04444FFH;
			Load(s.ci, "traditional.iclose.png"); Load(s.ca, "traditional.aclose.png");
			
			InitializeStyle(s)
		END InitStyle;
		
		PROCEDURE ShutDown*;
		BEGIN
			AosPlugins.main.Remove(viewRegistry)
		END ShutDown;
		
(** Window management *)
		(** Add adds a window at pos l, t with flags *)
		PROCEDURE Add*(l, t : LONGINT; item : Window; flags:SET);
		BEGIN
		END Add;
		
		(** Remove removes a window *)
		PROCEDURE Remove*(item : Window);
		BEGIN
		END Remove;
		
		(** Set the position of a window *)
		PROCEDURE SetWindowPos*(vs : Window; x, y : LONGINT);
		BEGIN
		END SetWindowPos;
		
		(** Set the size of a window. Return the new size in width and height *)
		(** If the window contains left, top, right or bottom, SetWindowSize is called 
			appropriately *)
		PROCEDURE SetWindowSize*(vs : Window; VAR width, height : LONGINT);
		BEGIN
		END SetWindowSize;
		
		(** Add a region to be refreshed *)			
		PROCEDURE AddDirty*(VAR rect:Rectangle);
		BEGIN
		END AddDirty;

		(** Add a dirty region. The region is in window coordinates and will be clipped against non transparent
			windows above *)
		PROCEDURE AddVisibleDirty*(w : Window; rect : Rectangle);
		BEGIN
		END AddVisibleDirty;
		
		(** Set the keyboard focus to the window w *)
		PROCEDURE SetFocus*(w : Window);
		BEGIN
		END SetFocus;
		
		(** Add a decoration window w to window to. The window w must separately be added to the wm *)
		(** A window MUST NOT be added more than once *)
		(** MUST hold lock *)
		PROCEDURE AddDecorWindow*(to, decor : Window);
		VAR dl : DecorList;
		BEGIN
			lock.AcquireWrite;
			INCL(decor.flags, FlagDecorWindow);
			decor.master := to;
			NEW(dl); dl.w := decor; dl.next := to.decor; to.decor := dl;
			lock.ReleaseWrite
		END AddDecorWindow;
		
		(** Remove a decoration window w from window from. The window w must separately be removed from the wm *)
		(** MUST hold lock *)
		PROCEDURE RemoveDecorWindow*(w, from : Window);
		VAR dl : DecorList;
		BEGIN
			lock.AcquireWrite;
			IF (from.decor # NIL) & (from.decor.w = w) THEN from.decor := from.decor.next 
			ELSE
				dl := from.decor;
				WHILE (dl.next # NIL) & (dl.next.w # w) DO dl := dl.next END;
				IF dl.next # NIL THEN dl.next := dl.next.next END
			END;
			lock.ReleaseWrite
		END RemoveDecorWindow;
		
		PROCEDURE SetStyle*(x : WindowStyle);
		VAR m : Message;
		BEGIN
			style := x; m.msgType := Messages.MsgStyleChanged; m.ext := style;
			Broadcast(m)
		END SetStyle;
		
		PROCEDURE GetStyle*() : WindowStyle;
		BEGIN
			RETURN style
		END GetStyle;
		
		(** Move Window w to front. If FlagStayOnTop is not set in w.flags, w will stay behind all windows with this flag set *)  
		PROCEDURE ToFront*(w : Window);
		BEGIN
		END ToFront;
		
		(** Move Window w to the background. If FlagStayOnTop is not set in w.flags, w will stay behind all windows *)  
		PROCEDURE ToBack*(w : Window);
		BEGIN
		END ToBack;
		
		(** Return the window at postition x, y in global space. *)
		(** Must hold WM lock *)
		PROCEDURE GetPositionOwner*(x, y : LONGINT) : Window;
		BEGIN
		END GetPositionOwner;
		
		(** Set the title of a window as UTF-8 string *)
		PROCEDURE SetWindowTitle*(w : Window; title : String);
		VAR tw : Window;
		BEGIN
			lock.AcquireWrite;
			w.title := title; 
			tw := w.topW;
			IF tw # NIL THEN AddVisibleDirty(tw, tw.bounds) END;
			lock.ReleaseWrite
		END SetWindowTitle;
		
		(** Get the title of a window as UTF-8 string *)
		PROCEDURE GetWindowTitle*(w : Window) : String;
		BEGIN
			RETURN w.title
		END GetWindowTitle;
		
		(** Set if the window is willing to accept a dropped item *)
		PROCEDURE SetAcceptDrag*(w : Window; accept : BOOLEAN);
		BEGIN
			lock.AcquireWrite;
			w.acceptDrag := accept;
			lock.ReleaseWrite
		END SetAcceptDrag;
		
		PROCEDURE StartDrag*(w : Window; sender, data : PTR; img : Graphics.Image; onAccept, onReject : Messages.CompCommand) : BOOLEAN;
		BEGIN
		END StartDrag;
		
		(** Adjust pointer to new position / check picture *)
		PROCEDURE CheckPointerImage*;
		BEGIN
		END CheckPointerImage;
		
		
(** View management *)		
		(** Add a view *)
		PROCEDURE AddView*(v : ViewPort);
		BEGIN
		END AddView;
		
		(** Add the whole View.range as dirty and cause a redraw *)
		PROCEDURE RefreshView*(v : ViewPort);
		BEGIN
		END RefreshView;
		
		(** RemoveView from windowmanager *)
		PROCEDURE RemoveView*(v : ViewPort);
		BEGIN 
		END RemoveView;
		
(** Messages *)
		PROCEDURE Broadcast*(VAR m : Message);
		BEGIN 
		END Broadcast;
		
		PROCEDURE SendMessage*(dest : Window; VAR m : Message) : BOOLEAN;
		BEGIN
			IF dest.sequencer # NIL THEN RETURN dest.sequencer.Add(m)
			ELSE dest.Handle(m); RETURN TRUE
			END
		END SendMessage;
		
		(** Install a message preview procedure. The window manager calls the MessagePreviewProc for
		all external messages so that they can be recorded, changed or discarded *)				
		PROCEDURE InstallMessagePreview*(x : MessagePreviewProc);
		VAR mpl : MessagePreviewList;
		BEGIN
			lock.AcquireWrite;
			NEW(mpl); mpl.next := messagePreviewList; mpl.proc := x; messagePreviewList := mpl;
			lock.ReleaseWrite
		END InstallMessagePreview;
		
		(** Remove a MessagePreviewProc *)
		PROCEDURE RemoveMessagePreview*(x : MessagePreviewProc);
		VAR cur : MessagePreviewList;
		BEGIN
			lock.AcquireWrite;
			IF (messagePreviewList # NIL) & (messagePreviewList.proc = x) THEN messagePreviewList := messagePreviewList.next
			ELSE
				cur := messagePreviewList;
				WHILE cur # NIL DO
					IF (cur.next # NIL) & (cur.next.proc = x) THEN cur.next := cur.next.next; lock.ReleaseWrite; RETURN 
					ELSE cur := cur.next END
				END
			END;	
			lock.ReleaseWrite
		END RemoveMessagePreview;
		
(** Enumeration *)
	(** Get the first "user" window --> May return NIL if only background and pointer window are installed *)
	(** Must hold lock *)
		PROCEDURE GetFirst*() : Window;
		BEGIN
		END GetFirst;
		
		(** Get the window next "user" window on top of x *)
		PROCEDURE GetNext*(x : Window) : Window; 
		BEGIN
		END GetNext;
		
		(** Get the "user" window below x *)
		PROCEDURE GetPrev*(x : Window) : Window;
		BEGIN
		END GetPrev;
		
		(** Replace the background window with w. Return the current background window *)
		PROCEDURE ReplaceBackground*(w : Window) : Window;
		BEGIN
		END ReplaceBackground;
		
		(** Return the area that is actually occupied *)
		PROCEDURE GetPopulatedArea*(VAR r : Rectangle);
		BEGIN
		END GetPopulatedArea;
		
		(** Internal handler for message that are directed to the window manager never call directly ! *) 
		PROCEDURE HandleInternal*(VAR msg : Messages.Message); (** PROTECTED *)
		BEGIN
			ASSERT(sequencer.IsCallFromSequencer())
		END HandleInternal;
		
		(** All external events of the window manager are inserted here *)
		PROCEDURE Handle*(VAR msg : Messages.Message);
		VAR discard : BOOLEAN;
				mpl : MessagePreviewList;
		BEGIN
			IF sequencer.IsCallFromSequencer() THEN 			
				(* check message preview handlers *)
				mpl := messagePreviewList; discard := FALSE;
				WHILE (mpl # NIL) & ~discard DO mpl.proc(msg, discard); mpl := mpl.next END;
				IF ~discard THEN HandleInternal(msg) END
			ELSE
				IF ~sequencer.Add(msg) THEN
					AosOut.String("A message sent to the WM could not be handled "); AosOut.Ln
				END
			END	
		END Handle;
		
	END WindowManager;
	
VAR registry* : AosPlugins.Registry;
	
(** calculate distances from images *)
PROCEDURE InitializeStyle*(s : WindowStyle);
BEGIN
	IF s.style = 2 THEN
		IF s.tab # NIL THEN s.th := s.tab.height END;
		IF s.bab # NIL THEN s.bh := s.bab.height END;
		IF s.lab # NIL THEN s.lw := s.lab.width END;
		IF s.rab # NIL THEN s.rw := s.rab.width END;
	END	
END InitializeStyle;
	
PROCEDURE NewString*(x : ARRAY OF CHAR) : String;
VAR t : String;
BEGIN
	NEW(t, LEN(x)); COPY(x, t^); RETURN t
END NewString;
	
PROCEDURE LoadCursor*(name : ARRAY OF CHAR; hx, hy : LONGINT; VAR pi : PointerInfo);
VAR done : BOOLEAN;
BEGIN
	IF pi = NIL THEN NEW(pi) END;
	pi.img := Graphics.LoadImage(name, TRUE); pi.hotX := hx; pi.hotY := hy;
	IF pi.img = NIL THEN AosOut.String("Picture not loaded"); AosOut.String(name); AosOut.Ln END
END LoadCursor;

PROCEDURE GetDefaultManager*() : WindowManager;
VAR p : AosPlugins.Plugin;
BEGIN
	p := registry.Await("");
	RETURN p(WindowManager)
END GetDefaultManager;

PROCEDURE GetDefaultView*() : ViewPort;
VAR p : AosPlugins.Plugin; m : WindowManager;
BEGIN
	m := GetDefaultManager();
	p := m.viewRegistry.Await("");
	RETURN p(ViewPort)
END GetDefaultView;

PROCEDURE DefaultAddWindow*(w : Window);
VAR manager : WindowManager;
	view : ViewPort;
	s : WindowStyle; dy, dx : LONGINT;
BEGIN
	manager := GetDefaultManager();
	view := GetDefaultView();
	s := manager.GetStyle();
	IF s # NIL THEN dy := s.th; dx := s.lw ELSE dy := 0; dx := 0;  END;
	manager.Add(ENTIER(view.range.l) + dx, ENTIER(view.range.t) + dy, w, {FlagFrame});
	manager.SetFocus(w)
END DefaultAddWindow;

PROCEDURE ExtAddWindow*(w : Window; dx, dy : LONGINT; flags : SET);
VAR manager : WindowManager;
	view : ViewPort;
BEGIN
	manager := GetDefaultManager();
	view := GetDefaultView();
	manager.Add(ENTIER(view.range.l) + dx, ENTIER(view.range.t) + dy, w, flags)
END ExtAddWindow;

(** move a window to the default view *)
PROCEDURE DefaultBringToView*(w : Window; toFront : BOOLEAN);
VAR manager : WindowManager;
	view : ViewPort;
	s : WindowStyle; dy, dx : LONGINT;
BEGIN
	manager := GetDefaultManager();
	view := GetDefaultView();
	s := manager.GetStyle();
	IF s # NIL THEN dy := s.th; dx := s.lw ELSE dy := 0; dx := 0;  END;
	manager.SetWindowPos(w, ENTIER(view.range.l) + dx, ENTIER(view.range.t) + dy);
	manager.SetFocus(w);
	IF toFront THEN manager.ToFront(w) END	
END DefaultBringToView;

PROCEDURE CleanUp;
BEGIN
	AosPlugins.main.Remove(registry)
END CleanUp;

BEGIN
	AosModules.InstallTermHandler(CleanUp);
	NEW(registry, "WM#", "Window Managers")
END WMWindowManager.


Color Codes
 Highlight
Types and Procedures
Lock Acquire / Lock Release
Preferred notation (comment)
Unsafe / Temporary / Stupid / requires attention
Permanent Comment 
Assertion
Debug
