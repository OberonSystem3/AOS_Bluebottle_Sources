MODULE WindowManager;	(** AUTHOR "TF"; PURPOSE "Window manager implementation"; *)
(**
 * History:
 *
 *	1012.2006	Added WindowManager.GetFocusOwner, cleanups (staubesv)
 *)
 
IMPORT
		AosOut, AosKernel, Utilities, AosPlugins, AosInputs, AosModules, AosDisplays, Graphics := WMGraphics, 
		Messages := WMMessages, DW := WMDefaultWindows, 
		WM := WMWindowManager, Rect := WMRectangles, Raster,  WMFontManager (*Load*);

CONST
	DirtyBufSize = 128;
	CombineLookahead = 64;
	XYResizeHandleSize = 15;
	ZF = 0.90; ZD = 0.1;
	
TYPE
	Window = WM.Window;
	Rectangle = Rect.Rectangle;
	Message = Messages.Message;
	String = Utilities.String;
	
	ViewPort* = OBJECT (WM.ViewPort);
		VAR
			backbuffer* : Graphics.Image;
			deviceRect : Rect.Rectangle;
			c : Graphics.BufferCanvas;
			state : Graphics.CanvasState;
			display : AosDisplays.Display;
			internnavig, navig : BOOLEAN;
			lastx, lasty : LONGINT;
			lastKeys : SET;
			modifierKeys : SET;
			meta : BOOLEAN;
			fx, fy, inffx, inffy, factor, intfactor : REAL;
			
		PROCEDURE &New(disp : AosDisplays.Display);
		BEGIN
			display := disp;
			NEW(backbuffer);
			AosOut.String("WindowManager: Disp.format = "); AosOut.Int(disp.format, 5); AosOut.Ln;
			Raster.Create(backbuffer, disp.width, disp.height, Raster.DisplayFormat(disp.format));
			range.r := range.l + disp.width; range.b := range.t + disp.height;
			deviceRect.r := disp.width; deviceRect.b := disp.height;
			desc := "Graphics adapter view";
			NEW(c, backbuffer);
			c.SetFont(Graphics.GetDefaultFont());
			c.SaveState(state);
			factor := 1; intfactor := 1;
			fx := factor; fy := factor; inffx := 1 ; inffy := inffx;
			internnavig := FALSE;
			modifierKeys := {};
		END New;
		
		(**  Return the modifier keys that are pressed in the view *)
		PROCEDURE GetKeyState*(VAR state : SET);
		BEGIN
			state := modifierKeys
		END GetKeyState;			
		
		PROCEDURE KeyEvent(ucs : LONGINT; flags : SET; keysym : LONGINT);
		VAR msg : Messages.Message; done : BOOLEAN; r : Rectangle; originX, originY : LONGINT; w, h : REAL;
		BEGIN
			manager.lock.AcquireWrite;
			modifierKeys := flags;
			msg.originator := SELF;
			IF (flags * AosInputs.Ctrl # {}) & (flags * AosInputs.Alt # {}) & (keysym = AosInputs.KsDelete) THEN
				manager.lock.ReleaseWrite; AosModules.Shutdown(AosModules.Reboot); LOOP END
			END;
			meta := (flags * AosInputs.Meta # {}) OR ((flags * AosInputs.Alt # {}) & (flags * AosInputs.Shift # {}));
			msg.msgType := Messages.MsgKey;
			msg.x := ucs;
			msg.y := keysym;
			msg.flags := flags;
			done := FALSE;
			IF meta THEN 
				IF keysym = 0FF50H THEN (* Home key *)
					manager.GetPopulatedArea(r);
					SetRange(r.l, r.t, r.r - r.l, r.b - r.t, TRUE);
					done := TRUE
				ELSIF keysym = 0FF57H THEN (* End key *)
					originX := ENTIER((range.l + range.r - display.width) / 2);
					originY := ENTIER((range.t + range.b - display.height) / 2);
					SetRange(originX, originY, display.width, display.height, TRUE);
					done := TRUE
				ELSIF keysym = 0FF53H THEN (* right *)
					w :=  range.r - range.l; SetRange(range.l + w, range.t,  w, range.b - range.t, TRUE); done := TRUE
				ELSIF keysym = 0FF51H THEN (* left *)
					w :=  range.r - range.l; SetRange(range.l - w, range.t,  w, range.b - range.t, TRUE); done := TRUE
				ELSIF keysym = 0FF54H THEN (* bottom *)
					h :=  range.b - range.t; SetRange(range.l, range.t + h,  range.r - range.l, h, TRUE); done := TRUE
				ELSIF keysym = 0FF52H THEN (* top *)
					h :=  range.b - range.t; SetRange(range.l, range.t - h,  range.r - range.l, h, TRUE); done := TRUE
				ELSIF keysym = 0FF55H THEN (* pgup *)
					w :=  range.r - range.l; h :=  range.b - range.t; SetRange(range.l + w /4, range.t + h / 4,  w / 2, h / 2, TRUE); done := TRUE
				ELSIF keysym = 0FF56H THEN (* pgdn *)
					w :=  range.r - range.l; h :=  range.b - range.t; SetRange(range.l - w /2, range.t - h / 2,  w * 2, h * 2, TRUE); done := TRUE
				END
			END;	
			IF ~done THEN manager.Handle(msg) END;
			manager.lock.ReleaseWrite
		END KeyEvent;
		
		PROCEDURE PointerEvent(x, y, z, dx, dy, dz : LONGINT; keys : SET);
		VAR msg : Messages.Message; of : REAL; i : LONGINT; ignore : BOOLEAN;
			centerX, centerY : REAL; w : Window;
		BEGIN
			ignore := FALSE;
			msg.originator := SELF;
			msg.msgType := Messages.MsgPointer;

			IF meta THEN
				manager.lock.AcquireWrite;
				IF ((0 IN lastKeys) # (0 IN keys)) & (0 IN keys) THEN
					w := manager.GetPositionOwner(ENTIER(range.l + x * inffx), ENTIER(range.t + y * inffy));
					ZoomToWindow(w);
					ignore := TRUE
				ELSIF ((2 IN lastKeys) # (2 IN keys)) & (2 IN keys) THEN
					w := manager.GetPositionOwner(ENTIER(range.l + x * inffx), ENTIER(range.t + y * inffy));
					SetInitialWindowBounds(w);
					ignore := TRUE
				END;
				IF (dz # 0) THEN
					navig := TRUE;
					of := factor;
					IF (dz < 0) THEN
						FOR i := 0 TO ABS(dz) - 1 DO intfactor := (intfactor * ZF); 
							IF intfactor < 0.001 * 0.001 THEN intfactor := 0.001 * 0.001 END 
						END
					ELSE	
						FOR i := 0 TO ABS(dz) - 1 DO intfactor := (intfactor * 1 / ZF);
							IF intfactor > 50 THEN factor := 50 END
						END
					END;
					IF ABS(intfactor - 1) < ZD THEN factor := 1
					ELSIF ABS(intfactor - 0.5) < ZD THEN factor := 0.5
					ELSIF ABS(intfactor - ENTIER(intfactor)) < 1/10 * (intfactor) THEN factor := ENTIER(intfactor) 
					ELSE factor := intfactor
					END;
	
					IF of # factor THEN
						centerX := range.l + x * inffx; (*fof*) (** fof: lastx -> x *) 
						centerY := range.t + y * inffy; (** fof: lasty -> y *)
						fx := factor; fy := factor; inffx := 1 / factor; inffy := inffx;
						centerX := centerX - ((x - 0.5 * backbuffer.width) * inffx); 
						centerY := centerY - ((y - 0.5 * backbuffer.height) * inffy);
						
						range.l := centerX - inffx * 0.5 * backbuffer.width; 
						range.t := centerY - inffy * 0.5 * backbuffer.height; 
						range.r := centerX + inffx * 0.5 * backbuffer.width; 
						range.b := centerY + inffy * 0.5 * backbuffer.height;
						manager.RefreshView(SELF)
					END;
					lastx := x; lasty := y; ignore := TRUE
				ELSIF ((x = 0) OR (y = 0) OR (x = backbuffer.width - 1) OR (y = backbuffer.height - 1))
					(* & ((ABS(dx) >1) OR (ABS(dy) > 1)) *) THEN 
					IF (x = 0) OR (x = backbuffer.width - 1) THEN range.l := range.l + (inffx * dx); range.r := range.r  + (inffx * dx) END;
					IF (y = 0) OR (y = backbuffer.height - 1) THEN range.t := range.t + (inffy * dy); range.b := range.b  + (inffy * dy) END;
					lastx := x; lasty := y;
					navig := TRUE; manager.RefreshView(SELF)
				END;
				manager.lock.ReleaseWrite
			ELSE 
				IF ~internnavig THEN IF navig THEN navig := FALSE; manager.RefreshView(SELF) END END;
				lastx := x; lasty := y
			END;

			lastKeys := keys;
			msg.x := ENTIER(range.l + x * inffx); msg.y := ENTIER(range.t + y * inffy); msg.z := z; 
			msg.dx := ENTIER(dx * inffx); msg.dy := ENTIER(dy * inffy); msg.dz := dz;
			msg.flags := keys;
			IF ~ignore THEN
				IF manager # NIL THEN manager.Handle(msg) END;
			END;	
		END PointerEvent;
			
		PROCEDURE ZoomToWindow(w : Window);
		VAR cur : WM.DecorList; r : Rectangle;
		BEGIN
			IF (manager IS WindowManager)  & (w = manager(WindowManager).bottom) THEN RETURN END;
			r := w.bounds;
			IF w.master # NIL THEN
				w := w.master;
				r := w.bounds;
				cur := w.decor;
				(* consider decoration *)
				WHILE cur # NIL DO Rect.ExtendRect(r, cur.w.bounds); cur := cur.next END;
			END;
			IF (r.r - r.l <  backbuffer.width) & (r.b - r.t < backbuffer.height) THEN
				SetRange(r.l, r.t, backbuffer.width, backbuffer.height, TRUE)
			ELSE
				SetRange(r.l, r.t, r.r - r.l, r.b - r.t, TRUE)
			END
		END ZoomToWindow;

		PROCEDURE SetInitialWindowBounds(w : Window);
		VAR width, height : LONGINT;
		BEGIN
			IF w.master # NIL THEN w := w.master END;
			width := w.initialBounds.r - w.initialBounds.l;
			height := w.initialBounds.b - w.initialBounds.t;						
			(* set original bounds of the window *)
			manager.SetWindowSize(w, width, height);
		END SetInitialWindowBounds;
					
		(** Set the observed range. *)
		PROCEDURE SetRange*(x, y, w, h : REAL; showTransition : BOOLEAN);
		VAR sx, sy, sx2, sy2, dx, dy, dx2, dy2, x2, y2  : REAL;
			i, steps : LONGINT;
		CONST Steps = 16;
		
			PROCEDURE Set(x, y, w, h : REAL);
			VAR tf : REAL;
			BEGIN
				range.l := x;
				range.t := y;
				factor := (display.width) / w;
				tf := (display.height) / h;
				IF factor > tf THEN factor := tf END;
				fx := factor; fy := factor; inffx := 1 / factor; inffy := inffx;
				range.r := x + display.width * inffx;
				range.b := y + display.height * inffy;
				intfactor := factor;
				manager.RefreshView(SELF);
			END Set;
		
		BEGIN
			IF w = 0 THEN w := 0.001 END;
			IF h = 0 THEN h := 0.001 END;
			IF showTransition THEN
				sx := range.l; sy := range.t; 
				sx2 := range.r; sy2 := range.b; 
				x2 := x + w; y2 := y + h; 
				steps := Steps;
				IF (sx = x) & (sy = y) & (sx2 - sx = w) & (sy2- sy = h) THEN steps := 1 END;
				dx := (x - sx) / steps;
				dy := (y - sy) / steps;
				dx2 := (x2 - sx2) / steps;
				dy2 := (y2 - sy2) / steps;
			
				internnavig := TRUE; navig := TRUE;
				FOR i := 1 TO steps-1 DO
					Set(sx + dx * i, sy + dy * i, (sx2 + dx2 * i) - (sx + dx * i), (sy2 + dy2 * i) - (sy + dy * i)) 
				END;
				internnavig := FALSE; navig := FALSE
			END;	
			Set(x, y, w, h)	
		END SetRange;
			
		(** r in wm coordinates *)
		PROCEDURE Update*(r : Rectangle; top : Window);
		BEGIN
			Draw(Rect.ResizeRect(r, 1), top.prev) (* assuming the src-domain is only 1 *)
		END Update;
		
		PROCEDURE Refresh*(top : Window);
		BEGIN
			Update(Rect.MakeRect(ENTIER(range.l)-1, ENTIER(range.t)-1, ENTIER(range.r) + 1, ENTIER(range.b) + 1), top)
		END Refresh;
		
		(* in wm coordinates *)
		PROCEDURE Draw(r : Rectangle; top : Window);
		VAR cur : Window;
			wr, nr : Rectangle;
			
			PROCEDURE InternalDraw(r : Rectangle; cur : Window);
			VAR nr, cb, tnr, dsr : Rectangle;
			BEGIN
				IF cur.useAlpha & (cur.prev # NIL)  THEN Draw(r, cur.prev)
				ELSE
					WHILE cur # NIL DO (* draw r in wm coordinates in all the windows from cur to top *)
						nr := r; cb := cur.bounds; Rect.ClipRect(nr, cb);
						dsr.l := ENTIER((nr.l - range.l) * fx) ; dsr.t := ENTIER((nr.t - range.t) * fy); 
						dsr.r := ENTIER((nr.r - range.l) * fx + 0.5); dsr.b := ENTIER((nr.b - range.t) * fy + 0.5); 
						IF (~Rect.RectEmpty(dsr)) & (Rect.Intersect(dsr, deviceRect)) THEN 
							c.SetClipRect(dsr);  (* Set clip rect to dsr, clipped at current window *)
							c.ClipRectAsNewLimits(ENTIER((cur.bounds.l - range.l) * fx), ENTIER((cur.bounds.t - range.t) * fy));
							(* range can not be factored out because of rounding *)
							IF navig THEN
								cur.Draw(c, ENTIER((cb.r - range.l)* fx) - ENTIER((cb.l - range.l) * fx), 
													ENTIER((cb.b - range.t) * fy) - ENTIER((cb.t - range.t) * fy), 0);
							ELSE
								cur.Draw(c, ENTIER((cb.r - range.l)* fx) - ENTIER((cb.l - range.l) * fx), 
													ENTIER((cb.b - range.t) * fy) - ENTIER((cb.t - range.t) * fy), 1);
							END;						
							c.RestoreState(state);
						END;	
						cur := cur.next	
					END;
					tnr.l := ENTIER((r.l - range.l) * fx); tnr.t := ENTIER((r.t - range.t) * fy); 
					tnr.r := ENTIER((r.r - range.l) * fx + 0.5); tnr.b := ENTIER((r.b - range.t) * fy + 0.5); 
					ClipAtImage(tnr, backbuffer);
					IF ((tnr.l < tnr.r) & (tnr.t < tnr.b))  THEN 
						display.Transfer(backbuffer.mem^, (tnr.l * backbuffer.fmt.bpp DIV 8) + tnr.t * backbuffer.bpr, 
						backbuffer.bpr, tnr.l, tnr.t, tnr.r - tnr.l, tnr.b -  tnr.t, AosDisplays.set)
					END
				END	
			END InternalDraw;
			
		BEGIN
			cur := top;
			IF (cur # NIL) & (~Rect.RectEmpty(r)) THEN 
				wr := cur.bounds; 
				IF ~Rect.IsContained(wr, r) THEN
					IF Rect.Intersect(r, wr) THEN
						(* r contains wr calculate r -  wr and recursively call for resulting rectangles*)
						(* calculate top rectangle *)
						IF wr.t > r.t THEN Rect.SetRect(nr, r.l, r.t, r.r, wr.t); Draw(nr, cur.prev) END;
						(* calculate bottom rectangle *)
						IF wr.b < r.b THEN Rect.SetRect(nr, r.l, wr.b, r.r, r.b); Draw(nr, cur.prev) END;
						(* calculate left rectangle *)
						IF wr.l > r.l THEN Rect.SetRect(nr, r.l, Max(r.t, wr.t), wr.l, Min(r.b, wr.b)); Draw(nr, cur.prev) END;
						(* calculate left rectangle *)
						IF wr.r < r.r THEN Rect.SetRect(nr, wr.r, Max(r.t, wr.t), r.r, Min(r.b, wr.b)); Draw(nr, cur.prev) END;
						(* calculate overlapping *)
						nr := r; Rect.ClipRect(nr, wr); 
						IF ~Rect.RectEmpty(nr) THEN InternalDraw(nr, cur) END
					ELSE Draw(r, cur.prev)
					END
				ELSE InternalDraw(r, cur)
				END
			END	
		END Draw;
		
	END ViewPort;
	
	DirtyQ = OBJECT
	VAR	
		dirtyHead, dirtyTail : LONGINT;
		dirtyBuf : ARRAY DirtyBufSize OF Rectangle;
		overflow : BOOLEAN;
		
		(* Between a call to Has and a call to Get no other process may do a Get *)
		PROCEDURE Has():BOOLEAN;
		BEGIN
			RETURN (dirtyHead # dirtyTail)
		END Has;
		
		PROCEDURE Get(VAR r : Rectangle);
		BEGIN {EXCLUSIVE}
			AWAIT((dirtyHead # dirtyTail));
			r := dirtyBuf[dirtyHead];
			dirtyHead := (dirtyHead + 1) MOD DirtyBufSize
		END Get;
		
		PROCEDURE Add(VAR r : Rectangle);
		VAR t : Rectangle; i: LONGINT;
		BEGIN {EXCLUSIVE}
			IF (dirtyTail + 1) MOD DirtyBufSize = dirtyHead THEN 
				AosOut.Enter; AosOut.String("WindowManager: Buffer Full"); AosOut.Exit;
				overflow := TRUE; t := r; i := dirtyHead;
				WHILE i # dirtyTail DO Rect.ExtendRect(t, dirtyBuf[i]); 
					i := (i + 1) MOD DirtyBufSize 
				END;
				dirtyHead := 0; dirtyBuf[0] := t; dirtyTail := 1;
			ELSE 
				dirtyBuf[dirtyTail] := r; 
				dirtyTail := (dirtyTail + 1) MOD DirtyBufSize
			END	
		END Add;
		
	END DirtyQ;
	
	UnhitableWindow = OBJECT(WM.BufferWindow);
		PROCEDURE IsHit(x, y : LONGINT) : BOOLEAN;
		BEGIN
			RETURN FALSE
		END IsHit;
	END UnhitableWindow;
	
	WindowManager* = OBJECT (WM.WindowManager)
	VAR 
		top, bottom : Window; (* top is always present and is the pointer, bottom is always present and is the background *)
		dirtyQ : DirtyQ;
		patches : ARRAY CombineLookahead OF Rectangle;
		
		running : BOOLEAN;
		views : WM.ViewPort;
		
	(* pointer handling *)
		kdprev : LONGINT;
		pointerKeys : SET;
	(* used by CheckPointerImg *)
		pointerOwner : Window;
		pointerX, pointerY : LONGINT;
		pointerInfo : WM.PointerInfo;
		
	(* focus *)
		focusOwner : Window;
		fifi : Fifi;
		
	(* drag & drop *)
		dragging : BOOLEAN;
		dragImage : Graphics.Image;	
		dragCursor : UnhitableWindow;
		dragInfo : WM.DragInfo;
		dragSender : Window;
		
		PROCEDURE &New;
		VAR pointer  : WM.BufferWindow;
			bg : DW.BackWindow;
		BEGIN
			Init;
			NEW(fifi, 4000);
			NEW(dirtyQ);
			NEW(pointer, 30, 30, TRUE); pointer.useAlpha := TRUE; 
			top := pointer; top.flags := { WM.FlagStayOnTop, WM.FlagNonDispatched };
			NEW(bg); bg.manager := SELF;
			bottom := bg; bottom.next := top; top.prev := bottom;
			SetWindowTitle(top, WM.NewString("Mouse Cursor"));
			SetWindowTitle(bottom, WM.NewString("Old background"));
			decorate := DefaultDecorator;
			AosOut.String("WindowManager: Manager.New finished"); AosOut.Ln;
		END New;
		
		PROCEDURE ShutDown*;
		VAR rect: Rectangle;
		BEGIN
			lock.AcquireWrite;
			ShutDown^; fifi.Cleanup;
			
			WHILE bottom.next # top DO Remove(bottom.next) END; 
			running := FALSE;
			dirtyQ.Add(rect); (* wake up and die *)
			lock.ReleaseWrite
		END ShutDown;
		
		PROCEDURE CheckChain*;
		VAR cur : Window; title : String;
		BEGIN
			AosOut.Enter;
			AosOut.String("Bottom up...");
			cur := bottom;
			WHILE cur # NIL DO 
				title := GetWindowTitle(cur); IF title # NIL THEN AosOut.String(title^) ELSE AosOut.String("[NIL]") END;
				AosOut.String("-->"); 
	(*			IF cur IS XMLComponents.FormWindow THEN 
					AosOut.String(" is FormWindow ");
					IF cur(XMLComponents.FormWindow).treeLock # NIL THEN cur(XMLComponents.FormWindow).treeLock.Huga 
					ELSE AosOut.String(" the lock is NIL !!! ");
					END
				END;	*)
				cur := cur.next 
			END;
			AosOut.String("NIL"); AosOut.Ln;
			AosOut.Exit;
			
(*			AosOut.String("Top down...");
			cur := top;
			WHILE cur # NIL DO 				
				title := GetWindowTitle(cur); IF title # NIL THEN AosOut.String(title^) ELSE AosOut.String("[NIL]") END;
				AosOut.String("-->"); cur := cur.prev 
			END;
			AosOut.String("NIL"); AosOut.Ln; *)
		END CheckChain;
		
		PROCEDURE InsertAfter(old, new : Window);
		BEGIN
			new.next := old.next; 
			new.prev := old;
			old.next := new;
			new.next.prev := new
		END InsertAfter;

	(* below mouse *)
		PROCEDURE FindTopWindow(stayontop : BOOLEAN) : Window;
		VAR cur : Window;
		BEGIN
			IF stayontop THEN RETURN top.prev 
			ELSE cur := top.prev; WHILE (cur.prev # NIL) & (WM.FlagStayOnTop IN cur.flags) DO cur := cur.prev END
			END;
			RETURN cur
		END FindTopWindow;
		
		PROCEDURE Broadcast*(VAR m : Message);
		VAR cur : Window;
		BEGIN 
			lock.AcquireWrite;
			cur := bottom; WHILE cur # NIL DO 
				IF ~SendMessage(cur, m) THEN AosOut.String("WindowManager: Broadcast did not reach all windows "); AosOut.Ln END;
				cur := cur.next 
			END;
			lock.ReleaseWrite
		END Broadcast;
						
		PROCEDURE Add*(left, top : LONGINT; w : Window; flags : SET);
		BEGIN
			ASSERT((w.next = NIL) & (w.prev = NIL)); (* window can not be inserted twice *)
			lock.AcquireWrite;
			w.flags := w.flags + flags;
			IF flags * { WM.FlagNonDispatched } = { } THEN NEW(w.sequencer, w.Handle) END;
			Rect.MoveRel(w.bounds, left - w.bounds.l, top - w.bounds.t);
			InsertAfter(FindTopWindow(WM.FlagStayOnTop IN flags), w);
			w.manager := SELF;
			IF (flags * { WM.FlagFrame } # { }) & (decorate # NIL) THEN decorate(w) END;
			AddVisibleDirty(w, w.bounds);
			pointerOwner := GetPositionOwner(pointerX, pointerY);
			CheckPointerImage; (* maybe some other window got below the cursor *)
			lock.ReleaseWrite
		END Add;
		
		PROCEDURE InternalRemove(w : Window);
		BEGIN
			ASSERT(lock.HasWriteLock());
			IF w.prev # NIL THEN w.prev.next := w.next END;
			IF w.next # NIL THEN w.next.prev := w.prev END;
			w.prev := NIL; w.next := NIL; (* some application programmers tend to remove a window more than once *)
			dirtyQ.Add(w.bounds)
		END InternalRemove;
		
		PROCEDURE Remove*(w : Window);
		VAR dl : WM.DecorList; p : Window;
		BEGIN
			lock.AcquireWrite;
			p := GetPrev(w);
			InternalRemove(w);  
			dl := w.decor; WHILE dl # NIL DO InternalRemove(dl.w); dl.w.manager := NIL; dl := dl.next END;
			w.decor := NIL;
			IF w.sequencer # NIL THEN w.sequencer.Stop END;
			w.manager := NIL;
			w.next := NIL; w.prev := NIL;
			IF (w = focusOwner) & (p # NIL) THEN SetFocus(p) END;
			IF pointerKeys = {} THEN (* otherwise the pointerOwner must remain *)
				pointerOwner := GetPositionOwner(pointerX, pointerY);
			END;	
			CheckPointerImage; (* maybe some other window got below the cursor *)
			lock.ReleaseWrite
		END Remove;
		
		PROCEDURE ToFront*(x : Window);
		VAR dl : WM.DecorList; 
		BEGIN
			IF x = bottom THEN RETURN END;
			IF x.flags * { WM.FlagStayOnBottom } # { } THEN RETURN END; 
			lock.AcquireWrite;
			IF x.flags * { WM.FlagDecorWindow } # { } THEN IF x.master # NIL THEN ToFront(x.master) END
			ELSE
				InternalRemove(x);
				InsertAfter(FindTopWindow(WM.FlagStayOnTop IN x.flags), x); AddVisibleDirty(x, x.bounds);
				dl := x.decor; WHILE dl # NIL DO InternalRemove(dl.w); InsertAfter(x, dl.w); AddVisibleDirty(dl.w, dl.w.bounds); dl := dl.next END
			END;
			CheckPointerImage; (* maybe some other window got below the cursor *)
			lock.ReleaseWrite
		END ToFront;
		
		PROCEDURE ToBack*(x : Window);
		VAR dl : WM.DecorList; t : Window;
		BEGIN
			lock.AcquireWrite;
			IF x.flags * { WM.FlagDecorWindow } # { } THEN IF x.master # NIL THEN ToBack(x.master) END
			ELSE
				InternalRemove(x);
				IF (WM.FlagStayOnTop IN x.flags) THEN t := FindTopWindow(FALSE) ELSE t := bottom END;
				InsertAfter(t, x); AddVisibleDirty(x, x.bounds);
				dl := x.decor; WHILE dl # NIL DO InternalRemove(dl.w); InsertAfter(x, dl.w); AddVisibleDirty(dl.w, dl.w.bounds); dl := dl.next END
			END;
			CheckPointerImage; (* maybe some other window got below the cursor *)
			lock.ReleaseWrite
		END ToBack;
	
		PROCEDURE SetWindowPos*(w : Window; x, y : LONGINT);			
		VAR rect : Rectangle;
				dx, dy : LONGINT;
				cur : WM.DecorList;
		BEGIN
			IF w = NIL THEN RETURN END;
			lock.AcquireWrite;
			dx := x - w.bounds.l; dy := y - w.bounds.t;
			IF (w.master # NIL) THEN w := w.master END;
			rect := w.bounds; Rect.MoveRel(w.bounds, dx, dy); Rect.ExtendRect(rect, w.bounds);
			cur := w.decor;
			WHILE cur # NIL DO
				Rect.ExtendRect(rect, cur.w.bounds);Rect.MoveRel(cur.w.bounds, dx, dy); Rect.ExtendRect(rect, cur.w.bounds);
				cur := cur.next
			END;
			CheckPointerImage; (* maybe some other window got below the cursor *)
			AddVisibleDirty(w, rect); (* assuming decor windows USE alpha *) 
			lock.ReleaseWrite
		END SetWindowPos;
		
		PROCEDURE SetWindowSize*(w : Window; VAR width, height : LONGINT);
		VAR rect : Rectangle;
			cw, ch, t, nw : LONGINT;
			
			PROCEDURE Set(win : Window; w, h  : LONGINT);
			BEGIN
				Rect.ExtendRect(rect, win.bounds);
				win.Resizing(w, h); win.bounds.r := win.bounds.l + w; win.bounds.b := win.bounds.t + h;
				Rect.ExtendRect(rect, win.bounds)
			END Set;
			
		BEGIN
			lock.AcquireWrite;
			rect := w.bounds;
			cw := w.GetWidth(); ch := w.GetHeight();
			w.Resizing(width, height);
			IF (cw # width) OR (ch # height) THEN
				w.bounds.r := w.bounds.l + width;
				w.bounds.b := w.bounds.t + height;
				IF cw # width THEN
					IF w.topW # NIL THEN 
						nw := width + (w.topW.GetWidth() - cw);
						t := w.topW.GetHeight(); Set(w.topW, nw, t); 
					END;
					IF w.bottomW # NIL THEN 
						nw := width + (w.bottomW.GetWidth() - cw);
						t := w.bottomW.GetHeight(); Set(w.bottomW, nw, t) 
					END;
					IF w.rightW # NIL THEN 
						Rect.ExtendRect(rect, w.rightW.bounds);
						Rect.MoveRel(w.rightW.bounds, width - cw, 0);
						Rect.ExtendRect(rect, w.rightW.bounds)
					END
				END;	
				IF ch # height THEN
					IF w.leftW # NIL THEN 
						nw := height + (w.leftW.GetHeight() - ch);
						t := w.leftW.GetWidth(); Set(w.leftW, t, nw) 
					END;
					IF w.rightW # NIL THEN
						nw := height + (w.rightW.GetHeight() - ch);
						t := w.rightW.GetWidth(); Set(w.rightW, t, nw) 
					END;
					IF w.bottomW # NIL THEN 
						Rect.ExtendRect(rect, w.bottomW.bounds);
						Rect.MoveRel(w.bottomW.bounds, 0, height - ch);
						Rect.ExtendRect(rect, w.bottomW.bounds)
					END
				END;
				Rect.ExtendRect(rect, w.bounds);
				dirtyQ.Add(rect);
				CheckPointerImage
			END;
			lock.ReleaseWrite
		END SetWindowSize;
		
(** View management *)		
		(** Add a view *)
		PROCEDURE AddView*(v : WM.ViewPort);
		VAR res : LONGINT;
		BEGIN
			lock.AcquireWrite;
			v.manager := SELF;
			v.next := views; views := v;
			lock.ReleaseWrite;
			viewRegistry.Add(v, res)
		END AddView;
		
		(** Add the whole View.range as dirty and cause a redraw *)
		PROCEDURE RefreshView*(v : WM.ViewPort);
		BEGIN
			lock.AcquireWrite;
			v.Refresh(top);
			lock.ReleaseWrite
		END RefreshView;
		
		(** RemoveView from windowmanager *)
		PROCEDURE RemoveView*(v : WM.ViewPort);
		VAR cur : WM.ViewPort;
		BEGIN
			IF v = NIL THEN RETURN END;
			lock.AcquireWrite;
			IF v = views THEN views := views.next 
			ELSE
				IF views # NIL THEN
					cur := views; WHILE (cur.next # NIL) & (cur.next # v) DO cur := cur.next END;
					IF cur.next = v THEN cur.next := cur.next.next END
				END
			END;
			viewRegistry.Remove(v);
			lock.ReleaseWrite
		END RemoveView;

		PROCEDURE ReplaceBackground*(w : Window) : Window;
		VAR old : Window;
		BEGIN
			lock.AcquireWrite;
			w.manager := SELF;
			old := bottom; bottom := w; bottom.next := old.next; bottom.next.prev := bottom;
			old.next := NIL;
			lock.ReleaseWrite;
			RETURN old
		END ReplaceBackground;
		
		(** Return the area that is actually occupied *)
		PROCEDURE GetPopulatedArea*(VAR r : Rectangle);
		VAR first: BOOLEAN; cur : Window;
		BEGIN
			lock.AcquireWrite;
			first := TRUE;
			cur := bottom.next;
			WHILE (cur # NIL) & (cur # top) DO 
				IF first THEN r := cur.bounds; first := FALSE 
				ELSE Rect.ExtendRect(r, cur.bounds)
				END;
				cur := cur.next
			END;
			lock.ReleaseWrite;
		END GetPopulatedArea;
		
(** Enumeration *)
		(** Get the first "user" window --> May return NIL if only background and pointer window are installed *)
		(** Must hold lock *)
		PROCEDURE GetFirst*() : Window;
		VAR cur : Window;
		BEGIN
			ASSERT(lock.HasWriteLock());
			cur := bottom; WHILE (cur # NIL) & ~(WM.FlagFrame IN cur.flags) DO cur := cur.next END;
			RETURN cur
		END GetFirst;
		
		(** Get the window next "user" window on top of cur *)
		PROCEDURE GetNext*(cur : Window) : Window; 
		BEGIN
			ASSERT(lock.HasWriteLock());
			IF cur # NIL THEN cur := cur.next END;
			WHILE (cur # NIL) & (cur.master # NIL) DO cur := cur.next END;
			RETURN cur
		END GetNext;
		
		(** Get the "user" window below cur *)
		PROCEDURE GetPrev*(cur : Window) : Window;
		BEGIN
			ASSERT(lock.HasWriteLock());
			IF cur # NIL THEN cur := cur.prev END;
			WHILE (cur # NIL) & (cur.master # NIL) DO cur := cur.prev END;
			RETURN cur
		END GetPrev;
		
		(** Set the keyboard focus to the window w *)
		PROCEDURE SetFocus*(w : Window);
		VAR dl : WM.DecorList;
			PROCEDURE SendFocusMessage(dst : Window; has : BOOLEAN);
			VAR m : Messages.Message;
			BEGIN
				m.msgType := Messages.MsgFocus;
				IF ~has THEN m.msgSubType := Messages.MsgSubFocusLost ELSE m.msgSubType := Messages.MsgSubFocusGot END;
				IF ~SendMessage(dst, m) THEN AosOut.String("Focus message not sent"); AosOut.Ln END;
				
				IF ~has THEN m.msgSubType := Messages.MsgSubMasterFocusLost 
				ELSE m.msgSubType := Messages.MsgSubMasterFocusGot 
				END;
				dl := dst.decor; WHILE dl # NIL DO IF SendMessage(dl.w, m) THEN (* ignore *) END; dl := dl.next END
			END SendFocusMessage;
			
		BEGIN
			lock.AcquireWrite;
			IF w = focusOwner THEN lock.ReleaseWrite; RETURN END;
			IF w.flags * { WM.FlagNoFocus } = { } THEN 
				IF focusOwner # NIL THEN SendFocusMessage(focusOwner, FALSE) END;
				focusOwner := w;
				SendFocusMessage(focusOwner, TRUE)
			ELSE
				IF w.master # NIL THEN SetFocus(w.master) END
			END;
			lock.ReleaseWrite
		END SetFocus;
		
		(** Return the window at postition x, y in global space. *)
		(** Must hold WM lock *)
		PROCEDURE GetPositionOwner*(x, y : LONGINT) : Window;
		VAR cur : Window;
		BEGIN
			lock.AcquireWrite;
			cur := top.prev; (* not the mouse *)
			WHILE cur # NIL DO 
				IF Rect.PointInRect(x, y, cur.bounds) THEN
					IF cur.IsHit(x - cur.bounds.l, y - cur.bounds.t) THEN 
						lock.ReleaseWrite;
						RETURN cur
					END
				END;
				cur := cur.prev
			END;		
			lock.ReleaseWrite;
			RETURN NIL
		END GetPositionOwner;
		
		(** Adjust pointer to new position / check picture *)
		(** MUST hold wm lock *)
		PROCEDURE CheckPointerImage;
		VAR rect : Rectangle; pi : WM.PointerInfo;
		BEGIN
			lock.AcquireWrite;
			ASSERT(top # NIL);

			IF pointerOwner # NIL THEN pi := pointerOwner.pointerInfo
			ELSE pi := NIL
			END;
			
			IF pi = NIL THEN pi := pointerStandard END; IF pointerInfo = NIL THEN pointerInfo := pointerStandard END; 
			
			IF (pi # pointerInfo) OR ((pointerX # top.bounds.l - pointerInfo.hotX) OR (pointerY # top.bounds.t - pointerInfo.hotY)) THEN
				rect := top.bounds;
				
				IF (pi.img # NIL) & (top IS WM.BufferWindow) THEN
					top(WM.BufferWindow).img := pi.img;
					top.bounds.l := pointerX - pi.hotX;
					top.bounds.t := pointerY - pi.hotY;
					top.bounds.r := top.bounds.l + top(WM.BufferWindow).img.width;
					top.bounds.b := top.bounds.t + top(WM.BufferWindow).img.height
				ELSE
					top.bounds.l := pointerX;
					top.bounds.t := pointerY;
					top.bounds.r := top.bounds.l;
					top.bounds.b := top.bounds.t	
				END;
				
				Rect.ExtendRect(rect, top.bounds);
				dirtyQ.Add(rect);
				pointerInfo := pi
			END;
			lock.ReleaseWrite
		END CheckPointerImage;
		
		PROCEDURE GetFocusOwner*() : Window;
		BEGIN
			RETURN focusOwner;
		END GetFocusOwner;
		
		PROCEDURE PointerEvent(VAR msg : Message);
		VAR newOwner : Window;
			kd, i : LONGINT;
			m : Message;
			keys : SET;

				PROCEDURE MouseMessage(sub:LONGINT);
				BEGIN
					IF (pointerOwner # NIL)  THEN
						m.msgType := Messages.MsgPointer;
						m.msgSubType := sub;
						m.x := msg.x - pointerOwner.bounds.l; m.y := msg.y - pointerOwner.bounds.t;
						m.flags := keys;
						IF pointerOwner.sequencer # NIL THEN IF ~pointerOwner.sequencer.Add(m) THEN END (* ignore missed mouse messages *)
						ELSE pointerOwner.Handle(m)
						END
					END	
				END MouseMessage;
				
				PROCEDURE DragMessage(sub : LONGINT; dst : Window);
				BEGIN
					IF (dst # NIL)  THEN
						m.msgType := Messages.MsgDrag;
						m.msgSubType := sub;
						m.sender := dragSender;
						m.ext := dragInfo;
						m.x := msg.x - dst.bounds.l; m.y := msg.y - dst.bounds.t;
						IF dst.sequencer # NIL THEN IF ~dst.sequencer.Add(m) THEN END (* ignore missed drag messages *)
						END
					END	
				END DragMessage;
				
				PROCEDURE DragAbortMessage;
				BEGIN
					IF (dragInfo # NIL) & (dragInfo.onReject # NIL) THEN dragInfo.onReject(SELF, dragInfo) END
				END DragAbortMessage;
				
		BEGIN
			ASSERT(sequencer.IsCallFromSequencer());
			IF ~running THEN RETURN END;
			m.originator := sequencer.GetOriginator();
			m := msg; keys := msg.flags;
			IF dragging THEN
				IF keys = {} THEN DragMessage(Messages.MsgDragDropped, GetPositionOwner(msg.x, msg.y)); dragging := FALSE 
				ELSIF keys * {0, 1, 2} = {0, 1, 2} THEN dragging := FALSE; (* abort drag *)
					(* fixup key state *)
					kd := 0; FOR i := 0 TO 31 DO IF i IN keys THEN INC(kd) END END;
					kdprev := kd; pointerKeys := keys;
					DragAbortMessage
				ELSE DragMessage(Messages.MsgDragOver, GetPositionOwner(msg.x, msg.y))
				END;
				IF dragging THEN SetWindowPos(dragCursor, msg.x, msg.y)
				ELSE RemoveDragCursor 
				END;
				pointerX := msg.x; pointerY := msg.y; CheckPointerImage;
				IF dragging THEN RETURN END
			END;
			
			(* if no keys are pressed, the new pointer owner is the position owner *)
			IF (keys = { }) OR (pointerOwner = NIL) THEN newOwner := GetPositionOwner(msg.x, msg.y)
			ELSE newOwner := pointerOwner
			END;

			(* keys changed *)
			IF keys # pointerKeys THEN
				kd := 0; FOR i := 0 TO 31 DO IF i IN keys THEN INC(kd) END END;
				(* the number of pressed keys is less --> one is up *)
				IF kd < kdprev THEN MouseMessage(Messages.MsgSubPointerUp)
				ELSE MouseMessage(Messages.MsgSubPointerDown); SetFocus(newOwner) (* no check --> keys did change *)
				END;
				kdprev := kd; pointerKeys := keys
			END;

			IF newOwner # pointerOwner THEN MouseMessage(Messages.MsgSubPointerLeave); pointerOwner := newOwner END;
			pointerX := msg.x; pointerY := msg.y;
			IF pointerOwner # NIL THEN CheckPointerImage; MouseMessage(Messages.MsgSubPointerMove) END
		END PointerEvent;
		
		PROCEDURE KeyEvent*(VAR m : Messages.Message);
		VAR p : Window;
		BEGIN
			ASSERT(sequencer.IsCallFromSequencer());
			IF ~running THEN RETURN END;
			IF (focusOwner # NIL) THEN 
				IF (m.flags * AosInputs.Alt # {}) & (m.y = 0FF09H) THEN
					p := GetPrev(focusOwner);
					IF p # NIL THEN ToFront(p); SetFocus(p) END
				ELSE
		 			IF focusOwner.sequencer # NIL THEN IF ~focusOwner.sequencer.Add(m) THEN END (* ignore keyboard message *)
			 		ELSE focusOwner.Handle(m)
			 		END	
			 	END	
		 	END
		END KeyEvent;
		
		PROCEDURE HandleInternal*(VAR msg : Messages.Message);
		BEGIN
			HandleInternal^(msg);
			IF msg.msgType = Messages.MsgKey THEN KeyEvent(msg)
			ELSIF msg.msgType = Messages.MsgPointer THEN PointerEvent(msg)
			END
		END HandleInternal;
		
		PROCEDURE AddDragCursor;
		VAR w, h : LONGINT;
		BEGIN
			NEW(dragCursor, 1, 1, TRUE); w := 1; h := 1;
			IF dragImage # NIL THEN 
				dragCursor.img := dragImage; w:= dragImage.width; h := dragImage.height
			END;
			Add(pointerX, pointerY, dragCursor, { WM.FlagStayOnTop, WM.FlagNonDispatched });
			SetWindowSize(dragCursor, w, h)
		END AddDragCursor;
		
		PROCEDURE RemoveDragCursor;
		BEGIN
			IF dragCursor # NIL THEN Remove(dragCursor) END;
		END RemoveDragCursor;
		
		PROCEDURE StartDrag*(w : Window; sender, data : PTR; img : Graphics.Image; onAccept, onReject : Messages.CompCommand) : BOOLEAN;
		VAR result : BOOLEAN;
		BEGIN
			result := FALSE;
			lock.AcquireWrite;
			IF (w = pointerOwner) & ~dragging THEN
				result := TRUE;
				dragging := TRUE;
				dragImage := img; dragSender := w; 
				NEW(dragInfo); 
				dragInfo.sender := sender; dragInfo.data := data;
				dragInfo.onAccept := onAccept; dragInfo.onReject := onReject;
				AddDragCursor
			END;
			lock.ReleaseWrite;
			RETURN result
		END StartDrag;
		
		(** a pointer button must be pressed *)
		PROCEDURE TransferPointer*(to : Window) : BOOLEAN;
		VAR ok : BOOLEAN;
		BEGIN
			lock.AcquireWrite;
			ok := FALSE;
			IF pointerKeys # {}  THEN  
				ok := TRUE; 
				pointerOwner := to; CheckPointerImage;
			END; 
			lock.ReleaseWrite;
			RETURN ok
		END TransferPointer;
		
		(** Add a region to be refreshed *)			
		PROCEDURE AddDirty*(VAR rect:Rectangle);
		BEGIN
			dirtyQ.Add(rect)
		END AddDirty;

		(** Add a region to be refreshed, if visible through windows w and above *)			
		PROCEDURE AddVisibleDirty*(w : Window; rect : Rectangle);
			
			(* Subtract hidden regions --> i.e. pass on non hidden parts *)
			PROCEDURE Sub(x : Window; VAR r : Rectangle);
			VAR nr : Rectangle;
			BEGIN
				IF Rect.RectEmpty(r) THEN RETURN END;
				
				IF (x = NIL) OR (x = top) THEN 
					(* there is nothing in front of this rectangle part --> must draw *)
					dirtyQ.Add(r);
					RETURN 
				END;
				
				IF ~x.useAlpha THEN 
					IF Rect.IsContained(x.bounds, r) THEN 
						(* the remaining rect is completely covered by non alpha window *)
						RETURN
					ELSIF Rect.Intersect(x.bounds, r) THEN  (* the rectangle intersects with the window x in front *)
						(* calculate top rectangle *)
						IF x.bounds.t > r.t THEN Rect.SetRect(nr, r.l, r.t, r.r, x.bounds.t); Sub(x.next, nr) END;
						(* calculate bottom rectangle *)
						IF x.bounds.b < r.b THEN Rect.SetRect(nr, r.l, x.bounds.b, r.r, r.b);Sub(x.next, nr) END;
						(* calculate left rectangle *)
						IF x.bounds.l > r.l THEN Rect.SetRect(nr, r.l, Max(r.t, x.bounds.t), x.bounds.l, Min(r.b, x.bounds.b)); Sub(x.next, nr) END;
						(* calculate right rectangle *)
						IF x.bounds.r < r.r THEN Rect.SetRect(nr, x.bounds.r, Max(r.t, x.bounds.t), r.r, Min(r.b, x.bounds.b)); Sub(x.next, nr) END
					ELSE (* the window x is not in front *)
						Sub(x.next, r)
					END
				ELSE (* the window x uses alpha *)
					Sub(x.next, r)
				END
			END Sub;
			
		BEGIN
			lock.AcquireWrite;
			Sub(w.next, rect);
			lock.ReleaseWrite
		END AddVisibleDirty;
		
		PROCEDURE RedrawDirty;
		VAR r, m:Rectangle;
			i, na, oa, nofPatches:LONGINT;
			found : BOOLEAN; cv : WM.ViewPort;
		BEGIN
			dirtyQ.Get(patches[0]);
			nofPatches := 1;
			lock.AcquireWrite;
			WHILE dirtyQ.Has() DO
				dirtyQ.Get(r);
				na := Rect.Area(r);
				found := FALSE;
				i := 0; WHILE (i < nofPatches) & ~found DO 
					m := patches[i]; oa := Rect.Area(m);
					Rect.ExtendRect(m, r);
					IF Rect.Area(m) <= 2 * (oa+na) THEN
						patches[i] := m; found := TRUE
					END;
					INC(i)
				END;
				IF ~found THEN patches[nofPatches] := r; INC(nofPatches) END;
				IF nofPatches =  CombineLookahead THEN
					(* update Viewports *)
					cv := views; 
					WHILE cv # NIL DO 
						FOR i := 0 TO nofPatches - 1 DO cv.Update(patches[i], top) END;
						cv := cv.next
					END;
					nofPatches := 0
				END;
			END;
			
			(* update Viewports *)
			cv := views; 
			WHILE cv # NIL DO
				FOR i := 0 TO nofPatches - 1 DO
					cv.Update(patches[i], top);  (* tester.DrawRect(patches[i], 0FF10H); *)
				END;
				cv := cv.next
			END;
			lock.ReleaseWrite
		END RedrawDirty;
		
		PROCEDURE DefaultDecorator(w : Window);
		VAR top : DW.TopWindow;
			left : DW.LeftWindow;
			right : DW.RightWindow;
			bottom : DW.BottomWindow; 
			l, t, r, b : LONGINT;
			th, lw, rw, bh : LONGINT;
			
			PROCEDURE InitW(n : Window);
			BEGIN
				n.manager := SELF; n.flags := n.flags + {WM.FlagNoFocus};
				IF WM.FlagStayOnTop IN w.flags THEN INCL(n.flags, WM.FlagStayOnTop) END;
				InsertAfter(w, n); AddDecorWindow(w, n);
				AddVisibleDirty(n, n.bounds);
				n.StyleChanged
			END InitW;
			
		BEGIN
			ASSERT(lock.HasWriteLock());

			NEW(top);NEW(left); NEW(right); NEW(bottom); 
			th := 10; lw := 2; rw := 2; bh := 2;
			l := w.bounds.l; t := w.bounds.t; r := w.bounds.r; b := w.bounds.b;
			
			top.useBitmaps := FALSE; left.useBitmaps := FALSE; 
			right.useBitmaps := FALSE; bottom.useBitmaps := FALSE;
			(* Top *);
			top.bounds := Graphics.MakeRectangle(l - lw, t - th, r + rw, t); 
			top.mode := 0; top.SetPointerInfo(pointerMove); top.vertical := FALSE; 
			top.threshold := 110; top.focusthreshold := 200;
			
			(* Left *)
			left.bounds := Graphics.MakeRectangle(l - lw, t, l, b); 
			left.mode := 3; left.SetPointerInfo(pointerLeftRight); left.vertical := TRUE; 
			left.threshold := 110; left.focusthreshold := 200;
			
			(* Right *)
			right.bounds := Graphics.MakeRectangle(r + 1, t, r + 1 + rw, b); 
			right.mode := 1; right.distXY := XYResizeHandleSize; right.vertical := TRUE; 
			right.threshold := 110; right.focusthreshold := 200;
			
			(* Bottom *)
			bottom.bounds := Graphics.MakeRectangle(l - lw, b + 1, r + rw, b + 1 + bh); 
			bottom.mode := 2; bottom.distXY :=   lw + XYResizeHandleSize; bottom.vertical := FALSE; 
			bottom.threshold := 110; bottom.focusthreshold := 200;
			
			(* Init decor windows *)
			InitW(top); w.topW := top; top.useAlpha := TRUE;
			InitW(left); w.leftW := left; left.useAlpha := TRUE;
			InitW(right); w.rightW := right; right.useAlpha := TRUE;
			InitW(bottom); w.bottomW := bottom; bottom.useAlpha := TRUE;
		END DefaultDecorator;
		
		(** Load a decoration style *)
		PROCEDURE LoadDecoration*(filename : ARRAY OF CHAR);
		BEGIN
		END LoadDecoration;
		
		PROCEDURE Touch;
		BEGIN 
			lock.AcquireWrite;
			fifi.Reset;
			lock.ReleaseWrite
		END Touch;
		
	BEGIN  {ACTIVE, SAFE}
		IF running THEN AosOut.String("WindowManager: RESTARTED"); lock.Reset; CheckChain END;
		running := TRUE;
		WHILE running DO RedrawDirty END;
		AosOut.String("WindowManager: Window manager closed"); AosOut.Ln;
	END WindowManager;
		
	MouseObj* = OBJECT (AosInputs.Sink)		
	VAR view : ViewPort;
		x, y, z : LONGINT;
		threshold, speedup: LONGINT;
					
		PROCEDURE &Init(t, s:LONGINT);
		BEGIN
			AosInputs.mouse.Register(SELF);
			threshold := t; speedup := s
		END Init;
		
		PROCEDURE Handle(VAR msg: AosInputs.Message);
		VAR dx, dy: LONGINT;
		BEGIN {EXCLUSIVE}
			WITH msg: AosInputs.MouseMsg DO
				dx := msg.dx; dy := msg.dy;
				IF (ABS(dx) > threshold) OR (ABS(dy) > threshold) THEN
					dx := dx*speedup DIV 10; dy := dy*speedup DIV 10
				END;
				INC(x, dx); INC(y, dy); INC(z, msg.dz);
				IF view = NIL THEN RETURN END;
				Bound(x, 0, view.backbuffer.width - 1); Bound(y, 0, view.backbuffer.height - 1);
				view.PointerEvent(x, y, z, msg.dx, msg.dy, msg.dz, msg.keys)
			END
		END Handle;
	END MouseObj; 
	
	(** The keyboard handler *)
	KeyboardObj = OBJECT (AosInputs.Sink)
	VAR view : ViewPort; ch : LONGINT;

		PROCEDURE Handle(VAR msg: AosInputs.Message);
		BEGIN {EXCLUSIVE}
			IF view = NIL THEN RETURN END;
			ch := ORD(msg(AosInputs.KeyboardMsg).ch);
			IF (ch >= 128) &(ch <= 155) THEN MapChars(ch) END;			
			view.KeyEvent(ch, msg(AosInputs.KeyboardMsg).flags, msg(AosInputs.KeyboardMsg).keysym)
		END Handle;
		
		PROCEDURE MapChars(VAR ch : LONGINT);
		BEGIN
			ch := CharToUnicode[ch];
		END MapChars;
	
		PROCEDURE &Init();
		BEGIN
			AosInputs.keyboard.Register(SELF)
		END Init; 
		
	END KeyboardObj;
	
	Toucher* = OBJECT
	VAR timer: AosKernel.Timer;
			alive : BOOLEAN;
	BEGIN {ACTIVE}
		alive := TRUE;
		NEW(timer);
		WHILE alive DO
			timer.Sleep(500);
			session.Touch()
		END
	END Toucher;
	
	Fifi* = OBJECT
	VAR
		timer: AosKernel.Timer; delay: LONGINT; time: AosKernel.MilliTimer; alive, done: BOOLEAN;
		
		PROCEDURE Cleanup;
		BEGIN {EXCLUSIVE}
			timer.Wakeup;
			alive := FALSE;
			AWAIT(done)
		END Cleanup;
		
		PROCEDURE Done;
		BEGIN {EXCLUSIVE}
			done := TRUE
		END Done;
		
		PROCEDURE Reset*;
		BEGIN {}
			AosKernel.SetTimer(time, delay)
		END Reset;
		
		PROCEDURE &Init(delay: LONGINT);
		BEGIN
			SELF.delay := delay;
			alive := TRUE; done := FALSE;
			NEW(timer)
		END Init;
		
	BEGIN {ACTIVE}
		LOOP
			timer.Sleep(delay);
			IF ~alive THEN EXIT END;
			IF AosKernel.Expired(time) THEN
				AosOut.String("Fifi --> "); AosOut.Ln;
				(* session.DumpLock;*) session.CheckChain;
				alive := FALSE
			END
		END;
		Done
	END Fifi;

VAR session : WindowManager;
	toucher :Toucher;
	defaultKeyboard* : KeyboardObj;
	defaultMouse* : MouseObj;
	CharToUnicode: ARRAY 256 OF LONGINT;				(** mapping from Oberon character codes to Unicodes **)

PROCEDURE FillSession(wm : WindowManager);
VAR r : Rectangle; bg : DW.BackWindow; t : Window;
BEGIN
	NEW(bg);
	wm.SetWindowTitle(bg, WM.NewString("New background"));
	Rect.SetRect(bg.bounds, MIN(LONGINT), MIN(LONGINT), MAX(LONGINT), MAX(LONGINT)); 
	wm.lock.AcquireWrite; t := wm.ReplaceBackground(bg); wm.lock.ReleaseWrite; 
	wm.CheckChain;
	r := Graphics.MakeRectangle(0, 0, 1280, 1024);
	wm.AddDirty(r)
END FillSession;

PROCEDURE Min(a, b:LONGINT):LONGINT;
BEGIN
	IF a < b THEN RETURN a ELSE RETURN b END;
END Min;

PROCEDURE Max(a, b:LONGINT):LONGINT;
BEGIN
	IF a > b THEN RETURN a ELSE RETURN b END;
END Max;	

	PROCEDURE Bound(VAR x:LONGINT; min, max:LONGINT);
	BEGIN
		IF x < min THEN x := min ELSE IF x > max THEN x := max END END
	END  Bound;
	
	PROCEDURE ClipAtImage(VAR x: Rectangle; img:Raster.Image);
	BEGIN
		Bound(x.l, 0, img.width); Bound(x.r, 0, img.width);
		Bound(x.t, 0, img.height); Bound(x.b, 0, img.height)
	END ClipAtImage;
	
PROCEDURE Replace*(par : PTR): PTR;
VAR disp : AosPlugins.Plugin;
	view : ViewPort; res : LONGINT;
BEGIN
	disp := AosDisplays.registry.Await("");
	NEW (session);  NEW(toucher);
	NEW(view, disp(AosDisplays.Display));
	session.lock.AcquireWrite; session.AddView(view); session.lock.ReleaseWrite;
	FillSession(session); 
	WM.registry.Add(session, res);
	NEW(defaultMouse, 5, 15); defaultMouse.view := view;
	NEW(defaultKeyboard); defaultKeyboard.view := view;
	RETURN NIL
END Replace;

PROCEDURE InitCharMaps;
	VAR i: LONGINT;
BEGIN
	FOR i := 0 TO 127 DO CharToUnicode[i] := i END;
	CharToUnicode[128] := 0C4H;
	CharToUnicode[129] := 0D6H;
	CharToUnicode[130] := 0DCH;
	CharToUnicode[131] := 0E4H;
	CharToUnicode[132] := 0F6H;
	CharToUnicode[133] := 0FCH;
	CharToUnicode[134] := 0E2H;
	CharToUnicode[135] := 0EAH;
	CharToUnicode[136] := 0EEH;
	CharToUnicode[137] := 0F4H;
	CharToUnicode[138] := 0FBH;
	CharToUnicode[139] := 0E0H;
	CharToUnicode[140] := 0E8H;
	CharToUnicode[141] := 0ECH;
	CharToUnicode[142] := 0F2H;
	CharToUnicode[143] := 0F9H;
	CharToUnicode[144] := 0E9H;
	CharToUnicode[145] := 0EBH;
	CharToUnicode[146] := 0EFH;
	CharToUnicode[147] := 0E7H;
	CharToUnicode[148] := 0E1H;
	CharToUnicode[149] := 0F1H;
	CharToUnicode[150] := 0DFH;
	CharToUnicode[151] := 0A3H;
	CharToUnicode[152] := 0B6H;
	CharToUnicode[153] := 0C7H;
	CharToUnicode[154] := 2030H;
	CharToUnicode[155] := 2013H;
	FOR i := 156 TO 255 DO CharToUnicode[i] := i END
END InitCharMaps;

PROCEDURE CleanUp;
VAR t : AosKernel.Timer;
BEGIN
	IF session # NIL THEN
		IF toucher # NIL THEN toucher.alive := FALSE; toucher.timer.Wakeup END; 
		session.ShutDown;
		NEW(t); t.Sleep(100)
	 END
END CleanUp;

PROCEDURE Install*(par : PTR) : PTR;
BEGIN
	RETURN NIL
END Install;

BEGIN
	IF Replace(NIL) = NIL THEN END;  
	InitCharMaps;
	AosModules.InstallTermHandler(CleanUp)
END WindowManager.


