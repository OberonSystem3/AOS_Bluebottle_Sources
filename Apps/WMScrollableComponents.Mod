MODULE WMScrollableComponents; (** AUTHOR "Ingmar Nebel"; PURPOSE "Scrollable Container"; *)

IMPORT
	WMComponents, WMStandardComponents, WMMessages, Utilities,
	WMGraphics, AosModules, WMRectangles, WMProperties, XML, XMLObjects;

TYPE
	(* Local type-alias for convenience *)
	String = Utilities.String;
	Panel = WMStandardComponents.Panel;
	
	(* special component to adapt to scroll target, in total conrol by ScrollablePanel, never use otherwise *)
	ScrollPanel*= OBJECT(WMComponents.VisualComponent)
	VAR 
		left, top, dx, dy: LONGINT;
		CheckScrollbars: WMMessages.CompCommand;
		resizing: BOOLEAN; (* distinguish whether AlignSubComponents is called from children or from Resized *)
						
		PROCEDURE &New(CheckScrollbars: WMMessages.CompCommand);
		BEGIN
			Init^;
			SELF.CheckScrollbars := CheckScrollbars;
			left := 0; top := 0;
		END New;

		(* store total width and height of subcomponents, check it *)
		PROCEDURE AlignSubComponents;
		VAR enum: XMLObjects.Enumerator; p: ANY; vc : WMComponents.VisualComponent;
			r, rCopy, rEnclosing, vcBounds, b : WMRectangles.Rectangle;
		BEGIN
			Acquire;
			IF aligning THEN Release; RETURN END;
			aligning := TRUE;
			r := GetClientRect(); rCopy := r; rEnclosing := r;
			enum := GetContents(); enum.Reset;
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS WMComponents.VisualComponent THEN
					vc := p(WMComponents.VisualComponent);
					IF vc.visible.Get() THEN
						b := vc.bearing.Get(); 
						CASE vc.alignment.Get() OF
						| WMComponents.AlignTop : vc.bounds.Set(WMRectangles.MakeRect(r.l + b.l , r.t + b.t, r.r - b.r, r.t + b.t + vc.bounds.GetHeight())); INC(r.t, vc.bounds.GetHeight() + b.t + b.b);
						| WMComponents.AlignLeft : vc.bounds.Set(WMRectangles.MakeRect(r.l + b.l, r.t + b.t, r.l + b.l + vc.bounds.GetWidth(), r.b - b.b)); INC(r.l, vc.bounds.GetWidth() + b.l + b.r)
						| WMComponents.AlignBottom : vc.bounds.Set(WMRectangles.MakeRect(r.l + b.l, r.b - vc.bounds.GetHeight() - b.b, r.r - b.r, r.b - b.b)); DEC(r.b, vc.bounds.GetHeight() + b.t + b.b)
						| WMComponents.AlignRight : vc.bounds.Set(WMRectangles.MakeRect(r.r - vc.bounds.GetWidth() - b.r , r.t + b.t, r.r - b.r, r.b - b.b)); DEC(r.r, vc.bounds.GetWidth() + b.l + b.r);
						| WMComponents.AlignClient : IF ~WMRectangles.RectEmpty(r) THEN vc.bounds.Set(WMRectangles.MakeRect(r.l + b.l , r.t + b.t, r.r - b.r, r.b  - b.b)) END
						ELSE (* nothing *)
						END;
						vcBounds := vc.bounds.Get();
						WMRectangles.ExtendRect(rEnclosing, vcBounds);
					END	
				END
			END;
			dx :=  Utilities.Max(0, (rEnclosing.r-rEnclosing.l)-(rCopy.r-rCopy.l));
			dy := Utilities.Max(0, (rEnclosing.b-rEnclosing.t)-(rCopy.b-rCopy.t));
			CheckLeftTop;
			aligning := FALSE;	
			Release;
			IF ~resizing THEN CheckScrollbars(NIL, NIL) END;
		END AlignSubComponents;

		PROCEDURE CheckLeftTop;
		BEGIN
			left := Utilities.Min(left, dx);	
			top := Utilities.Min(top, dy);
		END CheckLeftTop;
		
		PROCEDURE SetLeftTop(dxf, dyf: REAL);
		BEGIN
			SELF.left := ENTIER(dx * dxf); SELF.top := ENTIER(dy * dyf); CheckLeftTop;
		END SetLeftTop;

		(** Special methods *)
		PROCEDURE Resized;
		BEGIN
			IF sequencer # NIL THEN ASSERT(sequencer.lock.HasWriteLock()) END;
			resizing := TRUE;
			DisableUpdate;
			(* don't need to adjust parent, because bounds are always changed by parent, not third party
			p := SELF.GetParent();
			IF (p # NIL) & (p IS VisualComponent) THEN p(VisualComponent).AlignSubComponents END;
			*)
			AlignSubComponents;
			EnableUpdate;
			(*IF (p # NIL) & (p IS VisualComponent) THEN p(VisualComponent).Invalidate 
			ELSE Invalidate()
			END*)
			resizing := FALSE;
			Invalidate;
		END Resized;

		(** declare a rectangle area as dirty *)
		PROCEDURE InvalidateRect(r: WMRectangles.Rectangle); 
		VAR parent : XML.Element;
			m : WMMessages.Message; b, cr : WMRectangles.Rectangle;
		BEGIN 
			IF ~initialized THEN RETURN END;
			IF ~visible.Get() THEN RETURN END;
			IF ~IsCallFromSequencer() THEN
				m.msgType := WMMessages.MsgExt;
				m.ext := WMComponents.invalidateRectMsg; m.x := r.l; m.y := r.t; m.dx := r.r; m.dy := r.b; m.sender := SELF;
				IF ~sequencer.Add(m) THEN END;
			ELSE
				parent := GetParent();
				IF (parent # NIL) & (parent IS WMComponents.VisualComponent) THEN 
					cr := GetClientRect();
					WMRectangles.MoveRel(r, -left, -top); 
					WMRectangles.ClipRect(r, cr);
					IF ~WMRectangles.RectEmpty(r) THEN
						b := bounds.Get();
						WMRectangles.MoveRel(r, b.l, b.t);
						parent(WMComponents.VisualComponent).InvalidateRect(r)
					END
				END
			END
		END InvalidateRect;
		
		PROCEDURE InvalidateCommand(sender, par : ANY);
		VAR cr: WMRectangles.Rectangle;
		BEGIN
			IF ~initialized THEN RETURN END;
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.InvalidateCommand, sender, par)
			ELSIF visible.Get() THEN 
				cr := GetClientRect(); WMRectangles.MoveRel(cr, left, top);
				InvalidateRect(cr)
			END
		END InvalidateCommand;
					
		PROCEDURE HandleInternal(VAR msg : WMMessages.Message); (** PROTECTED *)
		BEGIN
			ASSERT(IsCallFromSequencer());
			IF (msg.msgType = WMMessages.MsgPointer) OR (msg.msgType = WMMessages.MsgDrag) THEN
				msg.x := msg.x + left; msg.y := msg.y + top;
			END;
			HandleInternal^(msg);
		END HandleInternal;			

		PROCEDURE Draw(canvas : WMGraphics.Canvas);
		VAR canvasState: WMGraphics.CanvasState;
		BEGIN
				canvas.SaveState(canvasState);
				canvas.SetDelta(canvas.dx - left, canvas.dy - top);
				DrawSubComponents(canvas);
				canvas.RestoreState(canvasState)
		END Draw;

	END ScrollPanel;
	
TYPE

	(** just shows an image, showing scrollbars if necessairy *)
	ScrollableContainer* = OBJECT(Panel)
	VAR
		vScrollbar, hScrollbar : WMStandardComponents.Scrollbar;
		scrollPanel: ScrollPanel;
		dx, dy : LONGINT;
		minNofLevels*, nofLevelsPerPage* : WMProperties.Int32Property;

		PROCEDURE & Init;
		BEGIN
			Init^;
			(* scrollbars *)
			NEW(vScrollbar); vScrollbar.alignment.Set(WMComponents.AlignRight); AddContent^(vScrollbar);
			vScrollbar.onPositionChanged.Add(ScrollbarsChanged); vScrollbar.visible.Set(FALSE);
			NEW(hScrollbar); hScrollbar.alignment.Set(WMComponents.AlignBottom); AddContent^(hScrollbar);
			hScrollbar.vertical.Set(FALSE); hScrollbar.onPositionChanged.Add(ScrollbarsChanged);
			hScrollbar.visible.Set(FALSE);
			NEW(scrollPanel, FitScrollTarget); scrollPanel.alignment.Set(WMComponents.AlignClient); AddContent^(scrollPanel);
			SetNameAsString(StrScrollableContainer);
			dx := 0;  dy := 0 ;
			NEW(minNofLevels, PrototypeSCMinNofLevels, NIL, NIL); properties.Add(minNofLevels);
			NEW(nofLevelsPerPage, PrototypeSCNofLevelsPerPage, NIL, NIL); properties.Add(nofLevelsPerPage);
		END Init;
 
		PROCEDURE AlignSubComponents;
		BEGIN
			(* align scrollbars and scrollPanel first *)
			Acquire;
			IF aligning THEN Release; RETURN END;
			AlignSubComponents^;
			(* the own bounds or client bounds may have changed *)
			aligning := TRUE;
			FitScrollTarget(NIL, NIL);
			aligning := FALSE;
			Release;
		END AlignSubComponents;
	
		PROCEDURE FitScrollTarget(sender, par: ANY);
		VAR spw, sph, tw, th, sw, sh, w, h, rw, rh, nofLevels: LONGINT;
		BEGIN
			IF (sequencer # NIL) & ~sequencer.IsCallFromSequencer() THEN
				sequencer.ScheduleEvent(FitScrollTarget, NIL, NIL)
			END;
			ASSERT(nofLevelsPerPage.Get() > 0);
			IF (scrollPanel # NIL) THEN		
				spw := scrollPanel.bounds.GetWidth(); sph := scrollPanel.bounds.GetHeight();
				tw := spw + scrollPanel.dx; th := sph + scrollPanel.dy;
				sw := vScrollbar.width.Get(); sh := hScrollbar.width.Get();
				w := bounds.GetWidth(); h := bounds.GetHeight();
				(* is hScrollbar visible ? *)
				IF (tw > w) OR ((th>h) & (tw>(w-sw))) THEN 
					(* is vScrollbar visible ? *)
					IF (th > (h-sh)) OR (tw<=w) THEN rw := w - sw ELSE rw := w END;
					dx := tw- rw;
					hScrollbar.visible.Set(TRUE);
					nofLevels := Utilities.Max(minNofLevels.Get(), nofLevelsPerPage.Get() * dx DIV rw);
					hScrollbar.max.Set(nofLevels);
					(* hScrollbar.pageSize.Set(Utilities.Max(1, (rw * nofLevels) DIV dx)); *)
					hScrollbar.pageSize.Set(Utilities.Max(1, (rw * nofLevels) DIV th) + 1);
					IF (sequencer # NIL) & sequencer.IsCallFromSequencer() THEN 
						hScrollbar.RecacheProperties; (* workaround because, InternalPropertyChanged is InUpdate *)
					END;
				ELSE 
					dx := 0;
					hScrollbar.visible.Set(FALSE);		
				END;
				(* is vScrollbar visible ? *)
				IF (th > h) OR ((tw>w) & (th>(h-sh))) THEN 
					(* is hScrollbar visible ? *)
					IF (tw > (w-sw)) OR (th<=h)  THEN rh := h - sh ELSE rh := h END;
					dy := th - rh;
					vScrollbar.visible.Set(TRUE); 
					nofLevels := Utilities.Max(minNofLevels.Get(), nofLevelsPerPage.Get() * dy DIV rh);
					vScrollbar.max.Set(nofLevels);
					(* vScrollbar.pageSize.Set(Utilities.Max(1, (rh * nofLevels) DIV dy)); *)
					vScrollbar.pageSize.Set(Utilities.Max(1, (rh * nofLevels) DIV th) + 1);
					vScrollbar.RecacheProperties; (* workaround because, InternalPropertyChanged is InUpdate *)
				ELSE 
					dy := 0;
					vScrollbar.visible.Set(FALSE);
				END
			END;
			IF ~aligning THEN AlignSubComponents END;
			Invalidate;	
		END FitScrollTarget;
		
		PROCEDURE ScrollbarsChanged(sender, data : ANY);
		BEGIN
			scrollPanel.SetLeftTop(hScrollbar.pos.Get() / (hScrollbar.max.Get() - hScrollbar.min.Get()),
				vScrollbar.pos.Get() / (vScrollbar.max.Get() - vScrollbar.min.Get()));
			Invalidate
		END ScrollbarsChanged;
		
		(** Iff data IS WMGraphics.Image, it is set as background. Else the background is set to white *)
		(* Note: Only use for anonymous Images without a specific Name *)
		PROCEDURE AddContent(c : XML.Content);
		BEGIN
			scrollPanel.AddContent(c);
		END AddContent;
			
	END ScrollableContainer;
	
VAR

	Int32Prototype : WMProperties.Int32Property;

	(* Scrollable Container prototypes *)
	PrototypeSCMinNofLevels*, PrototypeSCNofLevelsPerPage*: WMProperties.Int32Property;
	StrScrollableContainer : String;

PROCEDURE InitStrings;
BEGIN
	StrScrollableContainer := Utilities.NewString("ScrollableContainer");
END InitStrings;

PROCEDURE InitPrototypes;
VAR 
	plScrollableContainer : WMProperties.PropertyList;
BEGIN
	(* ScrollablePanel prototypes *)
	NEW(plScrollableContainer); WMComponents.propertyListList.Add("Scrollable Container", plScrollableContainer);
	NEW(Int32Prototype, NIL, NewString("MinNofLevels"), NewString("")); Int32Prototype.Set(8);
	NEW(PrototypeSCMinNofLevels, Int32Prototype, NIL, NIL); plScrollableContainer.Add(PrototypeSCMinNofLevels);
	NEW(Int32Prototype, NIL, NewString("NofLevelsPerPage"), NewString("")); Int32Prototype.Set(8);
	NEW(PrototypeSCNofLevelsPerPage, Int32Prototype, NIL, NIL); plScrollableContainer.Add(PrototypeSCNofLevelsPerPage);
	WMComponents.propertyListList.UpdateStyle
END InitPrototypes;

PROCEDURE GenScrollableContainer*(par : PTR) : PTR;
VAR scrollCont: ScrollableContainer;
BEGIN NEW(scrollCont); RETURN scrollCont
END GenScrollableContainer;

PROCEDURE NewString(x : ARRAY OF CHAR) : String;
VAR t : String;
BEGIN
	NEW(t, LEN(x)); COPY(x, t^); RETURN t
END NewString;

(* Register generator procedures *)
PROCEDURE Register;
BEGIN
	WMComponents.registry.RegisterElement("Scrollable Container", GenScrollableContainer);
END Register;

PROCEDURE Cleanup;
BEGIN {EXCLUSIVE}
	WMComponents.registry.UnregisterElement("ScrollablePanel");	
END Cleanup;

BEGIN	
	InitStrings;
	InitPrototypes;
	Register;
	AosModules.InstallTermHandler(Cleanup)
END WMScrollableComponents.

S.Free WMScrollableComponents~
