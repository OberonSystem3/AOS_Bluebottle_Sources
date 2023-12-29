MODULE WMDefaultWindows;	(** AUTHOR "TF"; PURPOSE "Decoration windows, background window for WM"; *)

IMPORT
	Utilities, WM := WMWindowManager, WMRectangles, Raster, Graphics := WMGraphics, Math,
	Messages := WMMessages, AosOut, WMGraphicUtilities;

CONST
	DraggingSnapRangeBase = 40;

TYPE
	Window = WM.Window;
	Rectangle =  WMRectangles.Rectangle;
	Message = Messages.Message;
	String = Utilities.String;
	DecorWindow* = OBJECT(Window)
	VAR
		lastX, lastY : LONGINT;
		dragging : BOOLEAN;
		resized : BOOLEAN;
		mode* : LONGINT;
		hasFocus : BOOLEAN;
		picAa*, picBa*, picCa*,
		picAb*, picBb*, picCb* : Graphics.Image;
		style*, distXY* : LONGINT; (* style : 0 simple 2 pictures *)
		inXYResizeHandle, vertical* : BOOLEAN;
		focusthreshold*, threshold* : LONGINT;
		draggingWidth, draggingHeight : LONGINT;
		draggingSnapRange : LONGINT;
		sac, sic, basw, bisw : LONGINT;

		PROCEDURE SetMasterFocus*(hasFocus : BOOLEAN);
		BEGIN
			SELF.hasFocus := hasFocus; Invalidate(WMRectangles.MakeRect(0, 0, GetWidth(), GetHeight()))
		END SetMasterFocus;
		
		PROCEDURE GetActivePics*(VAR a, b, c : Graphics.Image);
		BEGIN
			IF hasFocus THEN a := picAa; b := picBa; c := picCa 
			ELSE 
				IF picAb # NIL THEN a := picAb ELSE a := picAa END;
				IF picBb # NIL THEN b := picBb ELSE b := picBa END;
				IF picCb # NIL THEN c := picCb ELSE c := picCa END;
			END
		END GetActivePics;
		
		PROCEDURE CheckHorizontal*(x, y : LONGINT) : BOOLEAN;
		VAR t, th : LONGINT; a, b, c: Graphics.Image;
		BEGIN
			GetActivePics(a, b, c);
			IF hasFocus THEN th := focusthreshold ELSE th := threshold END;
			IF (c # NIL) & (x >= GetWidth() - c.width) THEN
				RETURN Graphics.IsBitmapHit(x - (GetWidth() - c.width), y, th, c)
			ELSIF (a # NIL) & (x < a.width) THEN 	
				RETURN Graphics.IsBitmapHit(x, y, th, a)
			ELSIF (b # NIL) THEN
				IF a # NIL THEN t := a.width ELSE t := 0 END;
				RETURN Graphics.IsBitmapHit((x - t) MOD b.width, y, th, b)
			ELSE RETURN FALSE
			END	
		END CheckHorizontal;
		
		PROCEDURE CheckVertical*(x, y : LONGINT) : BOOLEAN;
		VAR t, th : LONGINT; a, b, c: Graphics.Image;
		BEGIN
			GetActivePics(a, b, c);
			IF hasFocus THEN th := focusthreshold ELSE th := threshold END;
			IF (c # NIL) & (y >= GetHeight() - c.height) THEN
				RETURN Graphics.IsBitmapHit(x, y - (GetHeight() - c.height), th, c)
			ELSIF (a # NIL) & (y < a.height) THEN 	
				RETURN Graphics.IsBitmapHit(x, y, th, a)
			ELSIF (b # NIL) THEN
				IF a # NIL THEN t := a.height ELSE t := 0 END;
				RETURN Graphics.IsBitmapHit(x, (y - t) MOD b.height, th, b)
			ELSE RETURN FALSE
			END	
		END CheckVertical;
		
		PROCEDURE IsHit*(x, y : LONGINT) : BOOLEAN;	
		BEGIN
			IF style IN {0, 1} THEN RETURN TRUE
			ELSE 
				IF vertical THEN RETURN CheckVertical(x, y)
				ELSE RETURN CheckHorizontal(x, y)
				END	
			END
		END IsHit;
				
		PROCEDURE PointerDown*(x, y : LONGINT; keys : SET);
		BEGIN
			IF ~hasFocus OR (ABS(lastX - (bounds.l + x)) < 10) & (ABS(lastY - (bounds.t + y)) < 10) THEN manager.ToFront(master) END;
			lastX := bounds.l + x; lastY := bounds.t + y;
			inXYResizeHandle := ((mode = 1) & (y > GetHeight() - distXY)) OR ((mode = 2) & (x > GetWidth() - distXY));
			draggingWidth := master.GetWidth();
			draggingHeight := master.GetHeight();
			draggingSnapRange := DraggingSnapRangeBase;
			dragging := TRUE;
			IF master # NIL THEN master.HintReduceQuality(TRUE) END
		END PointerDown;
		
		PROCEDURE PointerMove*(x, y : LONGINT; keys : SET);
		VAR dx, dy, nw, nh, ow, oh : LONGINT;
		BEGIN
			IF dragging THEN 
				x := bounds.l + x; y := bounds.t + y; dx := x - lastX; dy := y - lastY;
				lastX := lastX + dx; lastY := lastY + dy;
				IF (dx # 0) OR (dy # 0) THEN
					IF mode = 0 THEN
						manager.SetWindowPos(SELF, bounds.l + dx, bounds.t + dy);
					ELSIF (mode = 1) & (master # NIL) THEN
						draggingWidth := draggingWidth + dx;
						IF inXYResizeHandle THEN draggingHeight := draggingHeight + dy END;
					ELSIF (mode = 2) & (master # NIL) THEN
						draggingHeight := draggingHeight + dy;
						IF inXYResizeHandle THEN draggingWidth := draggingWidth + dx END; 
					END;
					IF mode # 0 THEN
						nw := Utilities.Max(1, draggingWidth);
						nh := Utilities.Max(1, draggingHeight);
				(*		manager.SetWindowSize(master, nw, nh); (* this avoids nw, nh to be smaller thant the minimum size *) *)
						SnapDraggingSize(nw, nh);
						manager.SetWindowSize(master, nw, nh);
						resized := TRUE
					END
				END	
			END
		END PointerMove;				
		
		PROCEDURE SnapDraggingSize(VAR width, height : LONGINT);
		VAR
			ow, oh, snapWidth, snapHeight : LONGINT;
			
			PROCEDURE Pow2(x : INTEGER) : LONGINT;
			VAR
				r : LONGINT;
				i : INTEGER;
			BEGIN
				r := 1;
				FOR i := 1 TO x DO
					r := r * 2
				END;
				RETURN r;
			END Pow2;
			
		BEGIN
			ow := master.initialBounds.r - master.initialBounds.l;
			oh := master.initialBounds.b - master.initialBounds.t;
			(* find multiple nearest to current size *)
			IF width > ow THEN
				snapWidth := ENTIER(width / ow + 0.5) * ow
			ELSE
				snapWidth := ENTIER((1 / Pow2(SHORT(ENTIER((Math.ln(ow / width) / Math.ln(2)) + 0.5)))) * ow)
			END;
			IF height > oh THEN
				snapHeight := ENTIER(height / oh + 0.5) * oh
			ELSE
				snapHeight := ENTIER((1 / Pow2(SHORT(ENTIER((Math.ln(oh / height) / Math.ln(2)) + 0.5)))) * oh)
			END;
			IF (height > snapHeight - draggingSnapRange) & (height < snapHeight + draggingSnapRange) THEN height := snapHeight END;
			IF (width > snapWidth - draggingSnapRange) & (width < snapWidth + draggingSnapRange) THEN width := snapWidth END;
		END SnapDraggingSize;		
		
		PROCEDURE PointerUp*(x, y : LONGINT; keys:SET);
		VAR m : Messages.Message;
		BEGIN
			IF master # NIL THEN master.HintReduceQuality(FALSE) END;
			IF resized & (master # NIL)  THEN 
				m.msgType := Messages.MsgResized;
				m.x := master.bounds.r - master.bounds.l;
				m.y := master.bounds.b - master.bounds.t;
				IF ~master.sequencer.Add(m) THEN AosOut.String(" resized message was not queued") END; 
			END;
			dragging := FALSE
		END PointerUp;
		
		PROCEDURE Handle(VAR m : Messages.Message);
		BEGIN
			IF m.msgType = Messages.MsgFocus THEN
				IF m.msgSubType = Messages.MsgSubMasterFocusGot THEN hasFocus := TRUE
				ELSIF m.msgSubType = Messages.MsgSubMasterFocusLost THEN hasFocus := FALSE
				END;
				Invalidate(WMRectangles.MakeRect(0, 0, GetWidth(), GetHeight()))
			ELSE Handle^(m)	
			END
		END Handle;
	
	END DecorWindow;
	
	TopWindow* = OBJECT(DecorWindow)
	VAR closeInactive*, closeActive*, closeSelected*, titleImg : Graphics.Image;
		titleCanvas : Graphics.BufferCanvas;
		down : BOOLEAN;
		tac, tic, tax, tix, tay, tiy : LONGINT;
		
		PROCEDURE CheckXButton(x, y : LONGINT) : BOOLEAN;
			VAR img : Graphics.Image; 
		BEGIN
			IF hasFocus THEN img := closeActive ELSE img := closeInactive END;
			IF img # NIL THEN 
				RETURN Graphics.IsBitmapHit(x - (GetWidth() - img.width), y, 64, img)
			ELSE
				IF (x > GetWidth() - 20) & (y > 2) THEN RETURN TRUE ELSE RETURN FALSE END;
			END;	
		END CheckXButton;

		PROCEDURE PointerDown(x, y : LONGINT; keys : SET);
			VAR img : Graphics.Image; w : LONGINT;
		BEGIN
			IF CheckXButton(x, y) THEN down:=TRUE
			ELSE PointerDown^(x, y, keys)
			END
		END PointerDown;
		
		PROCEDURE PointerUp*(x, y:LONGINT; keys:SET);
		VAR msg : Message;
		BEGIN
			IF down & CheckXButton(x, y) THEN CloseDispatch(SELF, NIL)
			ELSE PointerUp^(x, y, keys)
			END;
			down:=FALSE
		END PointerUp;
		
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		VAR color, sw, tc, tx, ty, dx, dy : LONGINT; fw, fh : REAL; a, b, c, img : Graphics.Image; title : String;
			f : Graphics.Font;
		BEGIN
			fw := w / GetWidth(); fh := h / GetHeight();
			IF hasFocus THEN 
				tc := tac; color := sac; sw := basw; tx := tax; ty := tay
			ELSE 
				tc := tic; color := sic; sw := bisw; tx := tix; ty := tiy
			END;
			IF style = 0 THEN 
				(* content *)
				canvas.Fill(WMRectangles.MakeRect(0, 0, w, h), color, Graphics.ModeSrcOverDst);
			ELSIF style = 2 THEN 
				GetActivePics(a, b, c);
				RepeatMiddleHorizontal(canvas, GetWidth(), GetHeight(), w, h, q, a, b, c);
			END;
			IF hasFocus THEN img := closeActive ELSE img := closeInactive END;
			IF img # NIL THEN 
				canvas.ScaleImage(img, WMRectangles.MakeRect(0, 0, img.width, img.height), 
					WMRectangles.MakeRect(w - ENTIER(img.width * fw), 0, w, ENTIER(img.height * fh)), Graphics.ModeSrcOverDst, q)
			ELSE
				canvas.Fill(WMRectangles.MakeRect(w - ENTIER(20 * fw), ENTIER(2 * fh), w, h), 0FF0000C0H, Graphics.ModeSrcOverDst);
			END;
			IF master # NIL THEN
				title := master.GetTitle();
				IF title # NIL THEN 
					IF (w = GetWidth()) & (h = GetHeight()) THEN
						canvas.SetColor(tc);
						canvas.DrawString(tx, ty, title^)
					ELSE
						f := Graphics.GetDefaultFont();
						
						f.GetStringSize(title^, dx, dy);
						IF (titleImg = NIL) OR (tx + dx > titleImg.width) OR (GetHeight() > titleImg.height)  THEN NEW(titleImg);
							Raster.Create(titleImg, tx + dx + 10, GetHeight(), Raster.BGRA8888);
							NEW(titleCanvas, titleImg);
						END;
						titleCanvas.Fill(WMRectangles.MakeRect(0, 0, titleImg.width, titleImg.height), 0, Graphics.ModeCopy);
						titleCanvas.SetColor(tc);
						titleCanvas.DrawString(tx, ty, title^);
						canvas.ScaleImage(titleImg, WMRectangles.MakeRect(0, 0, titleImg.width, titleImg.height), 
							WMRectangles.MakeRect(0, 0, ENTIER(titleImg.width * fw), ENTIER(titleImg.height * fh)), Graphics.ModeSrcOverDst, q)						
					END
				END	
			END;
			IF style = 0 THEN
				WMGraphicUtilities.ExtRectGlassShade(canvas, WMRectangles.MakeRect(0, 0, w, h), {2}, sw, FALSE)
			END
		END Draw;
		
		PROCEDURE CloseDispatch*(sender, data : PTR);
		VAR m : Message;
		BEGIN
			IF master = NIL THEN RETURN END;
			m.msgType := Messages.MsgClose;
			IF master.sequencer # NIL THEN 
				IF ~master.sequencer.Add(m) THEN AosOut.String("Close message could not be queued."); AosOut.Ln END
			ELSE master.Handle(m)
			END;
		END CloseDispatch;
		
		PROCEDURE StyleChanged;
		VAR s : WM.WindowStyle; r : WMRectangles.Rectangle;
		BEGIN
			s := manager.GetStyle();
			style := s.style; sac := s.baCol; sic := s.biCol; basw := s.basw; bisw := s.bisw;
			
			picAa := s.taa; picBa := s.tab; picCa := s.tac;
			picAb := s.tia; picBb := s.tib; picCb := s.tic;
			tac := s.atextColor; tic := s.itextColor;
			tax := s.atextX; tix := s.itextX;
			tay := s.atextY; tiy := s.itextY;
			
			closeActive := s.ca; closeInactive := s.ci;
			manager.lock.AcquireWrite;
			r := bounds;
			bounds := Graphics.MakeRectangle(master.bounds.l - s.lw, master.bounds.t - s.th, master.bounds.r + s.rw, master.bounds.t);
			WMRectangles.ExtendRect(r, bounds);
			manager.lock.ReleaseWrite;
			manager.AddDirty(r)
		END StyleChanged;
		
	END TopWindow;
	
	LeftWindow* = OBJECT(DecorWindow)
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		VAR color, sw : LONGINT; a, b, c : Graphics.Image;
		BEGIN
			IF hasFocus THEN color := sac; sw := basw ELSE color := sic; sw := bisw END;
			IF style = 0 THEN
				canvas.Fill(Graphics.MakeRectangle(0, 0, w, h), color, Graphics.ModeSrcOverDst);
				WMGraphicUtilities.ExtRectGlassShade(canvas, WMRectangles.MakeRect(0, 0, w, h),
					{0, 2, 3}, sw, FALSE);
			ELSIF style = 2 THEN 
				GetActivePics(a, b, c);
				RepeatMiddleVertical(canvas, GetWidth(), GetHeight(), w, h, q, a, b, c)
			END	
		END Draw;
		
		PROCEDURE StyleChanged;
		VAR s : WM.WindowStyle; r : WMRectangles.Rectangle;
		BEGIN
			s := manager.GetStyle();
			style := s.style; sac := s.baCol; sic := s.biCol; basw := s.basw; bisw := s.bisw;

			picAa := s.laa; picBa := s.lab; picCa := s.lac;
			picAb := s.lia; picBb := s.lib; picCb := s.lic;
			manager.lock.AcquireWrite;
			r :=bounds;
			bounds := Graphics.MakeRectangle(master.bounds.l - s.lw, master.bounds.t, master.bounds.l, master.bounds.b); 
			WMRectangles.ExtendRect(r, bounds);
			manager.lock.ReleaseWrite;
			manager.AddDirty(r)
		END StyleChanged;
	END LeftWindow;
	
	RightWindow* = OBJECT(DecorWindow)
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		VAR color, sw : LONGINT; a, b, c : Graphics.Image;
		BEGIN
			IF hasFocus THEN color := sac; sw := basw ELSE color := sic; sw := bisw END;
			IF style = 0 THEN
				canvas.Fill(Graphics.MakeRectangle(0, 0, w, h), color, Graphics.ModeSrcOverDst);
				WMGraphicUtilities.ExtRectGlassShade(canvas, WMRectangles.MakeRect(0, 0, w, h),
					{0, 1, 2}, sw, FALSE);
			ELSIF style = 2 THEN
				GetActivePics(a, b, c);
				RepeatMiddleVertical(canvas, GetWidth(), GetHeight(), w, h, q, a, b, c)
			END
		END Draw;
		
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET);
		BEGIN
			IF y > GetHeight() - distXY THEN SetPointerInfo(manager.pointerULDR)
			ELSE SetPointerInfo(manager.pointerLeftRight)
			END;
			PointerMove^(x, y, keys)
		END PointerMove;
		
		PROCEDURE StyleChanged;
		VAR s : WM.WindowStyle; r : WMRectangles.Rectangle;
		BEGIN
			s := manager.GetStyle();
			style := s.style; sac := s.baCol; sic := s.biCol; basw := s.basw; bisw := s.bisw;

			picAa := s.raa; picBa := s.rab; picCa := s.rac;
			picAb := s.ria; picBb := s.rib; picCb := s.ric;
			manager.lock.AcquireWrite;
			r :=bounds;
			bounds := Graphics.MakeRectangle(master.bounds.r, master.bounds.t, master.bounds.r + s.rw, master.bounds.b); 
			WMRectangles.ExtendRect(r, bounds);
			manager.lock.ReleaseWrite;
			manager.AddDirty(r)
		END StyleChanged;
	END RightWindow;
	
	BottomWindow* = OBJECT(DecorWindow)
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		VAR color, sw : LONGINT; a, b, c : Graphics.Image;
		BEGIN
			IF hasFocus THEN color := sac; sw := basw ELSE color := sic; sw := bisw END;
			IF style = 0 THEN 
				canvas.Fill(WMRectangles.MakeRect(0, 0, w, h), color, Graphics.ModeSrcOverDst);
				WMGraphicUtilities.ExtRectGlassShade(canvas, WMRectangles.MakeRect(0, 0, w, h),
					{0}, sw, FALSE);
			ELSIF style = 2 THEN 
				GetActivePics(a, b, c);
				RepeatMiddleHorizontal(canvas, GetWidth(), GetHeight(), w, h, q, a, b, c)
			END	
		END Draw;
		
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET);
		BEGIN
			IF x > GetWidth() - distXY THEN SetPointerInfo(manager.pointerULDR)
			ELSE SetPointerInfo(manager.pointerUpDown)
			END;
			PointerMove^(x, y, keys)
		END PointerMove;
		
		PROCEDURE StyleChanged;
		VAR s : WM.WindowStyle; r : WMRectangles.Rectangle;
		BEGIN
			s := manager.GetStyle();
			style := s.style; sac := s.baCol; sic := s.biCol; basw := s.basw; bisw := s.bisw;

			picAa := s.baa; picBa := s.bab; picCa := s.bac;
			picAb := s.bia; picBb := s.bib; picCb := s.bic;
			manager.lock.AcquireWrite;
			r :=bounds;
			bounds := Graphics.MakeRectangle(master.bounds.l - s.lw, master.bounds.b, master.bounds.r + s.rw, master.bounds.b + s.bh); 
			WMRectangles.ExtendRect(r, bounds);
			manager.lock.ReleaseWrite;
			manager.AddDirty(r)
		END StyleChanged;

	END BottomWindow;
	
	BackWindow* = OBJECT(WM.Window)
	VAR color : LONGINT;
	
		PROCEDURE &Init;
		BEGIN
			color := 08080FFFFH;
		END Init;
		
		PROCEDURE StyleChanged;
		VAR s : WM.WindowStyle; r : WMRectangles.Rectangle;
		BEGIN
			s := manager.GetStyle();
			IF s # NIL THEN
				IF s.desktopColor # color THEN
					color := s.desktopColor; 
					r := WMRectangles.MakeRect(-10000, -10000, 10000, 10000);
					manager.AddDirty(r)
				END	
			END;	
		END StyleChanged;
			
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		VAR rect : WMRectangles.Rectangle;
		BEGIN
			canvas.GetClipRect(rect);
			canvas.Fill(rect, color, Graphics.ModeCopy);
		END Draw;
	END BackWindow;
	
(** GRAPHIC TOOLS *)
(** Fill a rectangle vertically with images, repeating the middle if needed *)
PROCEDURE RepeatMiddleVertical*(canvas : Graphics.Canvas; csw, csh, w, h, q : LONGINT; top, middle, bottom : Graphics.Image);
VAR fh : REAL; y, t : LONGINT;
BEGIN
	IF (csw = 0) OR (csh = 0) OR (w = 0) OR (h = 0) THEN RETURN END;
	fh := h / csh;
	y := 0; 
	(* left border *)
	IF top # NIL THEN 
		canvas.ScaleImage(top, WMRectangles.MakeRect(0, 0, top.width, top.height), 
		WMRectangles.MakeRect(0, 0, w, ENTIER(top.height * fh)), Graphics.ModeSrcOverDst, q);
		y := top.height; DEC(csh, top.height)
	END;
	IF bottom # NIL THEN t := bottom.height ELSE t := 0 END;
	IF middle # NIL THEN
		WHILE csh - t > middle.height DO
			canvas.ScaleImage(middle, WMRectangles.MakeRect(0, 0, middle.width, middle.height), 
				WMRectangles.MakeRect(0, ENTIER(y * fh), w, ENTIER((y + middle.height) * fh)), Graphics.ModeSrcOverDst, q);
			INC(y, middle.height); DEC(csh, middle.height)
		END;
		IF (csh - t) > 0 THEN 
			canvas.ScaleImage(middle, WMRectangles.MakeRect(0, 0, middle.width, (csh - t)), 
				WMRectangles.MakeRect(0, ENTIER(y * fh), w, ENTIER((y + (csh - t)) * fh+ 0.5)), Graphics.ModeSrcOverDst, q);
			INC(y, (csh - t));
		END;
	END;
	IF bottom # NIL THEN 
		canvas.ScaleImage(bottom, WMRectangles.MakeRect(0, 0, bottom.width, bottom.height), 
			WMRectangles.MakeRect(0, ENTIER(y * fh + 0.5), w, h), Graphics.ModeSrcOverDst, q)
	END;	
END RepeatMiddleVertical;

(** Fill a rectangle vertically with images, repeating the middle if needed *)
PROCEDURE RepeatMiddleHorizontal*(canvas : Graphics.Canvas; csw, csh, w, h, q : LONGINT; left, middle, right : Graphics.Image);
VAR fw : REAL; x, t : LONGINT;
BEGIN
	IF (csw = 0) OR (csh = 0) OR (w = 0) OR (h = 0) THEN RETURN END;
	fw := w / csw;
	x := 0; 
	(* left border *)
	IF left # NIL THEN 
		canvas.ScaleImage(left, WMRectangles.MakeRect(0, 0, left.width, left.height), 
			WMRectangles.MakeRect(0, 0, ENTIER(left.width * fw), h), Graphics.ModeSrcOverDst, q);
		x := left.width; DEC(csw, left.width)
	END;
	IF right # NIL THEN t := right.width ELSE t := 0 END;
	IF middle # NIL THEN
		WHILE csw - t > middle.width DO
			canvas.ScaleImage(middle, WMRectangles.MakeRect(0, 0, middle.width, middle.height), 
				WMRectangles.MakeRect(ENTIER(x * fw), 0, ENTIER((x + middle.width) * fw), h), Graphics.ModeSrcOverDst, q);
			INC(x, middle.width); DEC(csw, middle.width)
		END;
		IF (csw - t) > 0 THEN 
			canvas.ScaleImage(middle, WMRectangles.MakeRect(0, 0, (csw - t), middle.height), 
				WMRectangles.MakeRect(ENTIER(x * fw), 0, ENTIER((x + (csw - t)) * fw + 0.5), h), Graphics.ModeSrcOverDst, q);
			INC(x, (csw - t));
		END;
	END;
	IF right # NIL THEN 
		canvas.ScaleImage(right, WMRectangles.MakeRect(0, 0, right.width, right.height), 
			WMRectangles.MakeRect(ENTIER(x * fw + 0.5), 0, w, h), Graphics.ModeSrcOverDst, q)
	END;	
END RepeatMiddleHorizontal;

END WMDefaultWindows.
