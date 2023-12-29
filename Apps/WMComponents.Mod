MODULE WMComponents;	(** AUTHOR "TF"; PURPOSE "Experiments with component concepts"; *)

IMPORT
	AosOut, AosInputs, AosIO, AosKernel, AosModules, AosActive, AosFS, Locks := WMLocks, 
	XML, XMLScanner, XMLParser, XMLObjects, 
	Messages := WMMessages, Rectangles := WMRectangles,
	WMEvents, WMProperties, WMGraphics, Utilities, WM := WMWindowManager, Raster,
	AosCommands;
	
CONST
	TraceFocus = 0;
	TraceFinalize = 1;
	Trace = {  };
	MaxComponentNameSize* = 64; (* including 0X *)
	AlignNone* = 0; AlignLeft* = 1; AlignTop* = 2; AlignRight* = 3; AlignBottom* = 4; AlignClient* = 5;
	Pid* = "id"; Puid* = "uid";
	Pleft* = "left"; Ptop* = "top"; Pwidth* = "width"; Pheight* = "height"; Palign* = "align"; Pcolor* = "color";
TYPE
	(* Local type-alias for convenience *)
	Rectangle = Rectangles.Rectangle;
	String = Utilities.String;
	EventSource = WMEvents.EventSource;
	EventListener = WMEvents.EventListener;
	CompCommand = Messages.CompCommand;
	MsgSequencer = Messages.MsgSequencer;
	Message = Messages.Message;
	DragInfo = WM.DragInfo;
	
	(** Installable event preview handlers. Are called by the components sequencer thread *)
	PointerHandler*  = PROCEDURE {DELEGATE} (x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
	PointerLeaveHandler* = PROCEDURE {DELEGATE} (VAR handled : BOOLEAN);
	DragDropHandler* = PROCEDURE {DELEGATE} (x, y : LONGINT; dragInfo : DragInfo; VAR handled : BOOLEAN);
	DragResultHandler* = PROCEDURE {DELEGATE} (accepted : BOOLEAN; recipient : ANY; dragInfo : DragInfo; VAR handled : BOOLEAN);
	DragAutoStartHandler* = PROCEDURE {DELEGATE} (VAR handled : BOOLEAN);
	FocusHandler* = PROCEDURE {DELEGATE} (hasFocus : BOOLEAN);
	ContextMenuHandler* = PROCEDURE {DELEGATE} (sender : ANY; x, y: LONGINT);
	KeyEventHandler* = PROCEDURE {DELEGATE} (ucs : LONGINT; flags : SET; VAR keySym : LONGINT; VAR handled : BOOLEAN);
	DrawHandler* = PROCEDURE {DELEGATE} (canvas : WMGraphics.Canvas);
		
	(** Basic component *)
TYPE
	ComponentStyleChanged = OBJECT
	END ComponentStyleChanged;
	
	Properties* = OBJECT(XML.Element)
	END Properties;

	Component* = OBJECT(XML.Element)
	VAR sequencer* : MsgSequencer;
			initialized* : BOOLEAN;
			properties* : WMProperties.PropertyList;
			events* : WMEvents.EventSourceList;
			eventListeners* : WMEvents.EventListenerList;
			
			id*, uid* : WMProperties.StringProperty;
			enabled* : WMProperties.BooleanProperty;
			inPropertyUpdate : BOOLEAN; (* discard property changes that come from a property change 
																	within the same component*)
			
		PROCEDURE &Init;
		BEGIN
			Init^;
			inPropertyUpdate := FALSE;
			NEW(properties); properties.onPropertyChanged.Add(SELF.InternalPropertyChanged);
			NEW(id, PrototypeID, NIL, NIL); properties.Add(id);
			NEW(uid, PrototypeUID, NIL, NIL); properties.Add(uid);
			NEW(enabled, PrototypeEnabled, NIL, NIL); properties.Add(enabled);
			
			NEW(events); 
			
			NEW(eventListeners);
			
			SetNameAsString(StrComponent)
		END Init;
			
		PROCEDURE IsCallFromSequencer*():BOOLEAN;
		BEGIN RETURN sequencer.IsCallFromSequencer()
		END IsCallFromSequencer;
		
		PROCEDURE AssertLock*;
		BEGIN
			ASSERT((sequencer = NIL) OR sequencer.IsCallFromSequencer() OR sequencer.lock.HasReadLock())
		END AssertLock;
		
		(** Atomically set the components sequencer *)
		PROCEDURE SetSequencer*(s : MsgSequencer);
		VAR old : MsgSequencer;
			contents : XMLObjects.Enumerator; c : PTR; result : Component;
		BEGIN 
			old := sequencer;
			IF old # NIL THEN old.lock.AcquireWrite() END;
			sequencer := s;
			contents := GetContents(); contents.Reset;
			WHILE (result = NIL) & contents.HasMoreElements() DO 
				c := contents.GetNext(); IF c IS Component THEN c(Component).SetSequencer(s) END
			END;
			IF old # NIL THEN old.lock.ReleaseWrite() END
		END SetSequencer;
		
		PROCEDURE Acquire*;
		BEGIN 
			IF sequencer # NIL THEN sequencer.lock.AcquireWrite END
		END Acquire;
		
		PROCEDURE Release*;
		BEGIN 
			IF sequencer # NIL THEN sequencer.lock.ReleaseWrite END
		END Release;
		
		PROCEDURE CheckReadLock*;
		BEGIN
			IF (sequencer # NIL) & (~sequencer.lock.HasReadLock()) THEN 
					AosOut.String("Boom");
					sequencer.lock.WriteLock 
				END;	

			IF sequencer # NIL THEN ASSERT(sequencer.lock.HasReadLock()) END
		END CheckReadLock;
		
		(** AddContent adds a content (element or subtree) to the element. Called mainly by the XMLParser *)
		PROCEDURE AddContent*(c : XML.Content);
		BEGIN
			IF c = NIL THEN RETURN END;
			IF c IS Properties THEN properties.SetXML(c(Properties))
			ELSIF c IS Component THEN
				IF (sequencer # c(Component).sequencer) THEN c(Component).SetSequencer(sequencer) END;
			END;
			AddContent^(c)
		END AddContent;
		
		(** Return the root element of the component hierarchy. This is not necessarily the same as the 
			root element of XML since it is possible to have multiple component hierarchies in an XML file *)
		PROCEDURE GetComponentRoot*(): Component;
		VAR p, c : XML.Element;
		BEGIN
			c := SELF;
			LOOP
				p := c.GetParent();
				IF (p # NIL) & (p IS Component) THEN c := p ELSE RETURN c(Component) END
			END	
		END GetComponentRoot; 
	
		(** Find a sub component by its uid *)	
		PROCEDURE FindByUID*(uid : String) : Component;
		VAR contents : XMLObjects.Enumerator; c : PTR; result : Component; s : String;
		BEGIN
			IF uid = NIL THEN RETURN NIL END;
			s := SELF.uid.Get();
			IF (s # NIL) & (s^ = uid^) THEN RETURN SELF ELSE
				result := NIL;
				contents := GetContents(); contents.Reset;
				WHILE (result = NIL) & contents.HasMoreElements() DO 
					c := contents.GetNext();
					IF (c IS Component) THEN result := c(Component).FindByUID(uid) END
				END;
				RETURN result
			END
		END FindByUID;
		
		(** find a component by relative path *)
		PROCEDURE FindByPath*(VAR path : ARRAY OF CHAR; pos : LONGINT) : Component;
		BEGIN
			RETURN FindRelativePath(SELF, path, pos)
		END FindByPath;
		
		PROCEDURE StringToComponent*(str : String) : Component;
		VAR id, name : ARRAY 100 OF CHAR;
			isUID : BOOLEAN;
			ch : CHAR;
			sr : AosIO.StringReader;
			r, target : Component;
		BEGIN
			NEW(sr, LEN(str)); sr.Set(str^);
			isUID := FALSE; IF sr.Peek() = "%" THEN isUID := TRUE; ch := sr.Get() END;
			sr.Token(id);
			IF isUID THEN r := GetComponentRoot(); target := r.FindByUID(NewString(id))
				;IF target  = NIL THEN AosOut.String("StringToComponent : UID target not found"); AosOut.String(id); END
			ELSE target := FindByPath(id, 0)
				;IF target  = NIL THEN AosOut.String("StringToComponent : Path target not found"); AosOut.String(id); END
			END;
			RETURN target
		END StringToComponent;
		
		(** Search a CompCommand by string *)
		PROCEDURE StringToCompCommand*(eventstr : String) : EventListener;
		VAR id, name : ARRAY 100 OF CHAR;
			isUID : BOOLEAN;
			ch : CHAR;
			sr : AosIO.StringReader;
			r, target : Component;
		BEGIN
			NEW(sr, LEN(eventstr)); sr.Set(eventstr^);
			isUID := FALSE; IF sr.Peek() = "%" THEN isUID := TRUE; ch := sr.Get() END;
			sr.Token(id); sr.SkipWhitespace; sr.Token(name); 
			
			IF isUID THEN r := GetComponentRoot(); target := r.FindByUID(NewString(id))
				;IF target  = NIL THEN AosOut.String("StringToEvent : UID target not found"); AosOut.String(id); END
			ELSE target := FindByPath(id, 0)
				;IF target  = NIL THEN AosOut.String("StringToEvent : Path target not found"); AosOut.String(id); END
			END;
			IF target # NIL THEN RETURN target.eventListeners.GetHandlerByName(NewString(name))
			ELSE RETURN NIL
			END
		END StringToCompCommand;
		
		(** The Finalize Method is asynchronous since queuing could result in modules being freed before finalize is 
			propagated.. 
			Active components should terminate, external resources should be released *)
		PROCEDURE Finalize*; (** PROTECTED *)
		VAR contents : XMLObjects.Enumerator; c : PTR;
		BEGIN
			IF TraceFinalize IN Trace THEN IF uid # NIL THEN AosOut.String(uid^); AosOut.String(".Finalize") END END;
			Acquire;
			contents := GetContents(); contents.Reset;
			WHILE contents.HasMoreElements() DO 
				c := contents.GetNext();
				IF c IS Component THEN c(Component).Finalize END
			END;
			Release;
		END Finalize;
		
		PROCEDURE Reset*(sender, data : ANY); (** PROTECTED *)
		VAR contents : XMLObjects.Enumerator; c : PTR;
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Reset, sender, data)
			ELSE
				IF ~initialized THEN Initialize END;
				RecacheProperties;
				contents := GetContents(); contents.Reset;
				WHILE contents.HasMoreElements() DO 
					c := contents.GetNext();
					IF c IS Component THEN c(Component).Reset(sender, data) END
				END
			END
		END Reset;
		
		PROCEDURE Initialize*; (** PROTECTED *)
		BEGIN
			initialized := TRUE
		END Initialize;

		(** Internal interface of the message handler. This method may only be called via the Handle method. 
		Components that need to handle messages should implement HandleInternal. *)
		PROCEDURE HandleInternal*(VAR msg : Message); (** PROTECTED *)
		VAR result : PTR;
		BEGIN
			ASSERT(IsCallFromSequencer());
		END HandleInternal;
		
		(** External interface to the message handler. Asynchronous messages are synchronized by
		the sequencer of the Container *)
		PROCEDURE Handle*(VAR msg : Message); (** FINAL *)
		VAR s : String;
		BEGIN
			(* if asynchronous call --> synchronize *)
			IF ~IsCallFromSequencer() THEN
				IF ~sequencer.Add(msg) THEN
					s := uid.Get();
					AosOut.String("A message sent to "); 
					IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String(" <uid = NIL>") END;
					AosOut.String(" was discarded")
				END	
			ELSE HandleInternal(msg) END
		END Handle;
		
		(** Broadcast a message to all direct subcomponents. The subcomponent can then decide
		whether to further propagate the message to its children or not *)
		PROCEDURE BroadcastSubcomponents*(VAR msg : Message); (** FINAL *)
		VAR contents : XMLObjects.Enumerator; c : PTR;
		BEGIN
			Acquire;
			contents := GetContents(); contents.Reset;
			WHILE contents.HasMoreElements() DO 
				c := contents.GetNext();
				IF c IS Component THEN c(Component).Handle(msg) END
			END;
			Release
		END BroadcastSubcomponents;
		
		(* will be called synchronously if a property of the component changes. May not be called directly.
			No such messages are sent until the component is initialized *)
		PROCEDURE PropertyChanged*(sender, property : PTR);(** PROTECTED *)
		BEGIN ASSERT(IsCallFromSequencer());
		END PropertyChanged;
		
		(** called by the internal property changed handler via the sequencer, either if multiple properties have 
			changed or a Reset occured. The PropertyChanged method is called, too in case of multi-property changes
		 The component should call the inherited RecacheProperties method *)
		PROCEDURE RecacheProperties*;
		BEGIN
		END RecacheProperties;
		
		
		PROCEDURE InternalPropertyChanged(sender, property : PTR);
		VAR debugPUpdate : BOOLEAN;
		BEGIN
			IF ~initialized THEN RETURN END;
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.InternalPropertyChanged, sender, property)
			ELSE
				debugPUpdate := inPropertyUpdate;
				IF ~inPropertyUpdate THEN
					inPropertyUpdate := TRUE;
					IF property = properties THEN RecacheProperties END;
					PropertyChanged(sender, property);
					inPropertyUpdate := FALSE
				END;
			END
		END InternalPropertyChanged;
		
		(*PROCEDURE WriteAttributes(w : AosIO.Writer; level : LONGINT);
		VAR pa : WMProperties.PropertyArray; name : String; i : LONGINT;
		BEGIN
			(* write all known attributes unless they are set to the default value *)
			pa := properties.Enumerate();
			FOR i := 0 TO LEN(pa) - 1 DO
				IF ~pa[i].GetIsDefault() THEN
					w.Char(" ");
					name := pa[i].GetName(); IF name # NIL THEN w.String(name^) ELSE w.String("_NILNAME_") END;
					w.String('="'); pa[i].ToStream(w); w.Char('"')
				END
			END;
			(* write all unknown attributes *)
			WriteAttributes^(w, level)
		END WriteAttributes; *)
		
		(** Add a permanent XML attribute *)
		PROCEDURE AddAttribute*(attribute: XML.Attribute);
		BEGIN
			IF ~properties.SetPropertyValue(attribute.GetName(), attribute.GetValue()) THEN
				AddAttribute^(attribute) (* save the attribute literally if it is not a known property of the component *)
			END
		END AddAttribute;
	END Component;
	
	(** Basic visual component *)
TYPE
	VisualComponent* = OBJECT(Component)
	VAR
		bounds- : WMProperties.RectangleProperty;
		alignment- : WMProperties.Int32Property;
		fillColor- : WMProperties.ColorProperty;
		visible-, takesFocus-, needsTab- : WMProperties.BooleanProperty;
		onStartDrag- : WMEvents.EventSource;
		canvasState- : WMGraphics.CanvasState; (** PROTECTED *)
		fPointerOwner* : VisualComponent;
		hasFocus* : BOOLEAN;
		focusComponent* : VisualComponent; (** Subcomponent that has the keyboard focus, if any *)
		font : WMGraphics.Font;
		extPointerDown, extPointerUp, extPointerMove : PointerHandler;
		extPointerLeave : PointerLeaveHandler;
		extDragOver, extDragDropped : DragDropHandler;
		extDragResult : DragResultHandler;
		extKeyEvent : KeyEventHandler;
		extDraw : DrawHandler;
		extFocus : FocusHandler;
		extContextMenu : ContextMenuHandler;
		aligning* : BOOLEAN;
	
		hasOldPointer : BOOLEAN;
		pointerInfo, prevPointerInfo : WM.PointerInfo;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(bounds, PrototypeBounds, NIL, NIL); properties.Add(bounds);
			NEW(fillColor, PrototypeFillColor, NIL, NIL); properties.Add(fillColor);
			NEW(visible, PrototypeVisible, NIL, NIL); properties.Add(visible);
			NEW(takesFocus, PrototypeTakesFocus, NIL, NIL); properties.Add(takesFocus);
			NEW(needsTab, PrototypeNeedsTab, NIL, NIL); properties.Add(needsTab);
			NEW(alignment, PrototypeAlignment, NIL, NIL); properties.Add(alignment);
			
			NEW(onStartDrag, SELF, GSonStartDrag,GSonStartDragInfo, SELF.StringToCompCommand); 
			events.Add(onStartDrag);

			aligning := FALSE; fPointerOwner := SELF; focusComponent := SELF;
			SetNameAsString(StrVisualComponent)
		END Init;
		
	(** Focus handling *)
		PROCEDURE TraceFocusChain*;
		VAR s : String;
		BEGIN
			s := uid.Get();
			AosOut.String("I am in the focus chain : "); 
			IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String("NIL") END;
			AosOut.Ln;
			IF focusComponent = SELF THEN AosOut.String("I am the end")
			ELSIF focusComponent = NIL THEN AosOut.String("ERROR focusComponent is NIL")
			ELSE 	AosOut.Ln;
				focusComponent.TraceFocusChain
			END;
		END TraceFocusChain;
	
		(* internal helper function *)
			PROCEDURE IsInStaticChain(search : VisualComponent) : BOOLEAN;
			VAR x : VisualComponent;
				p : XML.Element; s : String;
			BEGIN
				x := SELF;
				WHILE x # NIL DO
					IF x = search THEN 			
						IF TraceFocus IN Trace THEN
							s := search.uid.Get();
							AosOut.String("In new focus chain : "); 
							IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String("NIL") END;
							AosOut.Ln
						END;	
						RETURN TRUE 
					END;
					p := x.GetParent();
					IF (p # NIL) & (p IS VisualComponent) THEN x := p(VisualComponent) ELSE x := NIL END
				END;
				RETURN FALSE
			END IsInStaticChain;
		
		(** Set the keyboard focus chain to this component its takesFocus field is set and unset the old chain *)
		PROCEDURE SetFocus*;
		VAR r, x : VisualComponent;
			p : XML.Element;
			tuid : String;
		BEGIN
			Acquire;
			IF ~takesFocus.Get() THEN 
				IF TraceFocus IN Trace THEN tuid := uid.Get();
					IF tuid # NIL THEN
						AosOut.String(tuid^); AosOut.String("does not take focus."); AosOut.Ln
					END;	
				END;
				Release;
				RETURN 
			END;
			(* unset the old focus chain *)
			r := GetVisualComponentRoot(); (* find the leaf component that has the focus *)
			WHILE (r # NIL) & (r.focusComponent # NIL) & (r.focusComponent # r) DO r := r.focusComponent END;
			p := r; (* clear the focus chain until the root or this component *)
			WHILE (p # SELF) & (p # NIL) & (p IS VisualComponent) DO 
				p(VisualComponent).focusComponent := p(VisualComponent);
				p(VisualComponent).FocusLost ;p := p.GetParent()
			END;
			
(*			WHILE (x # NIL) & (~IsInStaticChain(x)) DO
				IF TraceFocus IN Trace THEN tuid := x.uid.Get();
					IF tuid # NIL THEN
						AosOut.String("Unsetting : "); AosOut.String(tuid^); AosOut.Ln;
					END
				END;	
				x.FocusLost; IF x.extFocus # NIL THEN x.extFocus(FALSE) END; x.focusComponent := x;
				p := x.GetParent();
				IF (p # NIL) & (p IS VisualComponent) THEN x := p(VisualComponent) ELSE x := NIL END
			END; *)
			
			(* set the new chain *)
			x := SELF; x.focusComponent := SELF;
			WHILE x # NIL DO
				IF ~x.hasFocus THEN x.FocusReceived; IF x.extFocus # NIL THEN x.extFocus(TRUE) END END;
				IF TraceFocus IN Trace THEN tuid := x.uid.Get();
					IF tuid # NIL THEN
						AosOut.String("Set : "); AosOut.String(tuid^); AosOut.Ln;
					END
				END;	
				p := x.GetParent();
				IF (p # NIL) & (p IS VisualComponent) THEN 
					p(VisualComponent).focusComponent := x; x := p(VisualComponent) 
				ELSE x := NIL 
				END
			END;
			Release
		END SetFocus;
		
		PROCEDURE FocusReceived*;
		BEGIN hasFocus := TRUE
		END FocusReceived;
		
		PROCEDURE FocusLost*;
		BEGIN hasFocus := FALSE
		END FocusLost;
		
		PROCEDURE FocusNext*;
		VAR pe : XML.Element; e, n : OBJECT;
				enum: XMLObjects.Enumerator;
				found : BOOLEAN;
		BEGIN
			Acquire;
			pe := GetParent();
			IF pe # NIL THEN
				enum := pe.GetContents(); enum.Reset;
				found := FALSE;
				WHILE ~found & enum.HasMoreElements() DO
					e := enum.GetNext();
					IF e = SELF THEN 
						WHILE ~found & enum.HasMoreElements() DO
							n := enum.GetNext();
							IF n IS VisualComponent THEN 
								IF n(VisualComponent).takesFocus.Get() THEN found := TRUE END
							END
						END;
						IF found THEN n(VisualComponent).SetFocus
						ELSIF pe IS VisualComponent THEN pe(VisualComponent).FocusNext
						END
					END
				END;
				IF ~ found THEN 
					enum.Reset; 
					WHILE ~found & enum.HasMoreElements() DO
						 e := enum.GetNext();
						IF (e IS VisualComponent) & e(VisualComponent).takesFocus.Get() THEN
							e(VisualComponent).SetFocus(); 
							found := TRUE
						END
					END
				END	
			ELSE (* if there is no parent then set it to the first focusable element, if any *)
				enum := GetContents(); enum.Reset;
				found := FALSE;
				WHILE ~found & enum.HasMoreElements() DO
					e := enum.GetNext();
					IF (e IS VisualComponent) & e(VisualComponent).takesFocus.Get() THEN
						e(VisualComponent).SetFocus(); 
						found := TRUE
					END
				END
			END;
			Release
		END FocusNext;
		
		PROCEDURE FocusPrev*;
		BEGIN
		END FocusPrev;
		
		PROCEDURE PropertyChanged*(sender, property : PTR);
		BEGIN
			IF property = bounds THEN Resized
			ELSIF property = visible THEN Resized
			ELSIF property = alignment THEN AlignmentChanged
			ELSE PropertyChanged^(sender, property)
			END;
		END PropertyChanged;
		
		(** Get the root of visible components. Not neccessarily the same as GetComponentRoot() OR GetRoot() *)
		PROCEDURE GetVisualComponentRoot*(): VisualComponent;
		VAR p, c : XML.Element;
		BEGIN
			c := SELF;
			LOOP
				p := c.GetParent();
				IF (p # NIL) & (p IS VisualComponent) THEN c := p 
				ELSE RETURN c(VisualComponent)
				END
			END	
		END GetVisualComponentRoot; 
		
		(** Position handling *)
		PROCEDURE AlignmentChanged;
		VAR p : XML.Element;
		BEGIN
			Acquire; 
			p := SELF.GetParent();
			IF (p # NIL) & (p IS VisualComponent) THEN p(VisualComponent).AlignSubComponents END;
			Release
		END AlignmentChanged;
		
		(** Get the bounds of the component *)
		PROCEDURE GetClientRect*() : Rectangle;
		VAR r, t : Rectangle;
		BEGIN
			r := bounds.Get();
			t := Rectangles.MakeRect(0, 0, r.r - r.l, r.b - r.t);
			RETURN t
		END GetClientRect;
		
	(*	(** Set the bounds of the component in parent coordinates.  *)
		PROCEDURE SetBounds*(rect : Rectangle);
		BEGIN
			bounds.Set(rect)
		END SetBounds;
		
		(** Get the width of the component *)
		PROCEDURE GetWidth*() : LONGINT;
		BEGIN
			RETURN bounds.GetWidth()
		END GetWidth;

		(** Set the width of the component *)
		PROCEDURE SetWidth*(width : LONGINT);
		BEGIN
			bounds.SetWidth(width) 
		END SetWidth;
		
		(** Get the height of the component *)
		PROCEDURE GetHeight*() : LONGINT;
		BEGIN
			RETURN bounds.GetHeight()
		END GetHeight;
		
		(** Set the height of the component *)
		PROCEDURE SetHeight*(height : LONGINT);
		BEGIN 
			bounds.SetHeight(height)
		END SetHeight;
		
		(** Set the width and height of the component atomic *)
		PROCEDURE SetExtents*(width, height : LONGINT);
		BEGIN
			bounds.SetExtents(width, height)
		END SetExtents;
		
		(** Set the left position of the component, moving it (not resizing) *)
		PROCEDURE SetLeft*(left : LONGINT);
		BEGIN
			bounds.SetLeft(left)
		END SetLeft;
		
		(** Set the top position of the component, moving it (not resizing) *)
		PROCEDURE SetTop*(top : LONGINT);
		BEGIN
			bounds.SetTop(top)
		END SetTop; *)
		
		PROCEDURE AlignSubComponents*;
		VAR enum: XMLObjects.Enumerator; p: PTR; result, vc : VisualComponent;
			r : Rectangle;
		BEGIN
			Acquire;
			IF aligning THEN Release; RETURN END;
			aligning := TRUE;
			r := GetClientRect();
			enum := GetContents(); enum.Reset;
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS VisualComponent THEN
					vc := p(VisualComponent);
					IF vc.visible.Get() THEN 
						CASE vc.alignment.Get() OF
						| AlignTop : vc.bounds.Set(Rectangles.MakeRect(r.l, r.t, r.r, r.t + vc.bounds.GetHeight())); INC(r.t, vc.bounds.GetHeight())
						| AlignLeft : vc.bounds.Set(Rectangles.MakeRect(r.l, r.t, r.l + vc.bounds.GetWidth(), r.b)); INC(r.l, vc.bounds.GetWidth())
						| AlignBottom : vc.bounds.Set(Rectangles.MakeRect(r.l, r.b - vc.bounds.GetHeight(), r.r, r.b)); DEC(r.b, vc.bounds.GetHeight())
						| AlignRight : vc.bounds.Set(Rectangles.MakeRect(r.r - vc.bounds.GetWidth(), r.t, r.r, r.b)); DEC(r.r, vc.bounds.GetWidth());
						| AlignClient : IF ~Rectangles.RectEmpty(r) THEN vc.bounds.Set(r) END
						ELSE (* nothing *)
						END
					END	
				END
			END;
			aligning := FALSE;
			Release;
		END AlignSubComponents;
		
		PROCEDURE Initialize*;
		BEGIN
			Initialize^;
			AlignSubComponents
		END Initialize;
		
	(** Locating *)
		(** transform the local component coordinates into global window manager coordinates *)
		PROCEDURE ToWMCoordinates*(x, y : LONGINT; VAR gx, gy : LONGINT);
		VAR cr : Component; tc : XML.Element; r : Rectangle;
		BEGIN
			gx := x; gy := y; tc := SELF;
			REPEAT
				IF (tc # NIL) & (tc IS VisualComponent) THEN
					r := tc(VisualComponent).bounds.Get();
					INC(gx, r.l); INC(gy, r.t)
				END;
				tc := tc.GetParent()
			UNTIL (tc = NIL) OR ~(tc IS VisualComponent);
			cr := GetComponentRoot();
			IF (cr # NIL) & (cr IS Form) THEN
				INC(gx, cr(Form).window.bounds.l);
				INC(gy, cr(Form).window.bounds.t)
			END
		END ToWMCoordinates;
	
		(** Return if the component is hit at (x, y) in component coordinates *)
		PROCEDURE IsHit*(x, y: LONGINT): BOOLEAN;
		BEGIN
			RETURN visible.Get() & Rectangles.PointInRect(x, y, GetClientRect())
		END IsHit;
		
		(** Return the topmost first child component at (x, y) *)
		PROCEDURE GetPositionOwner*(x, y: LONGINT): VisualComponent;
		VAR enum: XMLObjects.Enumerator; p: PTR; result, vc : VisualComponent; r : Rectangle;
		BEGIN
			Acquire;
			enum := GetContents(); enum.Reset;
			result := SELF;
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS VisualComponent THEN
					vc := p(VisualComponent);
					r := vc.bounds.Get();
					IF Rectangles.PointInRect(x, y, r) & vc.IsHit(x - r.l, y - r.t) THEN 
						result := vc
					END;
				END
			END;
			Release;
			RETURN result
		END GetPositionOwner;
		
		(** DragOver is called via the message handler. The should call manager.SetDragAccept(SELF, .... *)
		PROCEDURE DragOver*(x, y: LONGINT; dragInfo : DragInfo);
		BEGIN
		END DragOver;
		
		(** Dropped is called via the message handler to indicate an item has been dropped. *)
		PROCEDURE DragDropped*(x, y: LONGINT; dragInfo : DragInfo);
		BEGIN
		END DragDropped;
		
		(** Is called via the message handler to inform about the result of a recent drag operation *)
		PROCEDURE DragResult*(accepted : BOOLEAN; recipient : PTR; dragInfo : DragInfo);
		BEGIN
		END DragResult;
		
		(** Start a drag operation. *)
		PROCEDURE StartDrag*(data : PTR; img : WMGraphics.Image; onAccept, onReject : Messages.CompCommand) : BOOLEAN;
		VAR rc : Component;
		BEGIN
			rc := GetVisualComponentRoot();
			IF (rc # NIL) & (rc IS Form) THEN 
				RETURN rc(Form).window.StartDrag(SELF, data, img, onAccept, onReject)
			ELSE 
				RETURN FALSE
			END
		END StartDrag;
		
		(** confirm a drag operation. *)
		PROCEDURE ConfirmDrag*(accept : BOOLEAN; dragInfo : DragInfo);
		VAR rc : Component;
		BEGIN
			rc := GetVisualComponentRoot();
			IF (rc # NIL) & (rc IS Form) THEN rc(Form).window.ConfirmDrag(accept, dragInfo)
			END
		END ConfirmDrag;
		
		(** Is called by the component if it detects a default drag action. The subclass should then call StartDrag with
			the respective coordinates. If it wants to start the drag operation *)
		PROCEDURE AutoStartDrag*;
		BEGIN
			onStartDrag.Call(NIL)
		END AutoStartDrag;
		
		(** Is called by the component if it detects a request for a context menu. The subclass should open the
		context menu if applicable *)
		PROCEDURE ShowContextMenu*(x, y : LONGINT);
		BEGIN
			IF extContextMenu # NIL THEN extContextMenu(SELF, x, y) END;
		END ShowContextMenu;
		
	(** Special methods *)
		PROCEDURE Resized*;
		VAR p : XML.Element;
		BEGIN
			IF sequencer # NIL THEN ASSERT(sequencer.lock.HasWriteLock()) END;
			
			DisableUpdate;
			p := SELF.GetParent();
			IF (p # NIL) & (p IS VisualComponent) THEN p(VisualComponent).AlignSubComponents END;
			AlignSubComponents;
			EnableUpdate;
			IF (p # NIL) & (p IS VisualComponent) THEN p(VisualComponent).Invalidate 
			ELSE Invalidate()
			END
		END Resized;
		
		(** Is called before any sub-components are drawn *)
		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		VAR color : LONGINT;
		BEGIN
			CheckReadLock;
			color := fillColor.Get();
			IF color # 0 THEN canvas.Fill(GetClientRect(), color, WMGraphics.ModeSrcOverDst) END;
		END DrawBackground;
		
		(** Is called after all sub-components are drawn *)
		PROCEDURE DrawForeground*(canvas : WMGraphics.Canvas);
		BEGIN
			CheckReadLock;
		END DrawForeground;
		
		PROCEDURE DrawSubComponents*(canvas : WMGraphics.Canvas);
		VAR enum: XMLObjects.Enumerator; p: PTR; vc : VisualComponent; cr, r : Rectangle; 
			BEGIN
			CheckReadLock;
			canvas.GetClipRect(cr);
			canvas.SaveState(canvasState);
			(* draw all sub-components *)
			enum := GetContents(); enum.Reset;
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS VisualComponent THEN
					vc := p(VisualComponent); r := vc.bounds.Get();
					IF Rectangles.Intersect(r, cr) THEN (* only draw if the component has a chance to be visible *) 
						canvas.SetClipRect(r); canvas.SetClipMode({WMGraphics.ClipRect});
						canvas.ClipRectAsNewLimits(r.l,  r.t);
						vc.Draw(canvas);
						canvas.RestoreState(canvasState)
					END
				END
			END;
		END DrawSubComponents;
		
		PROCEDURE GetFont*() : WMGraphics.Font;
		BEGIN
			IF font = NIL THEN RETURN WMGraphics.GetDefaultFont()
			ELSE RETURN font
			END
		END GetFont;
		
		PROCEDURE SetFont*(font : WMGraphics.Font);
		BEGIN
			Acquire;
			IF SELF.font # font THEN
				SELF.font := font;
				Invalidate()
			END;
			Release
		END SetFont;
		
		(** Called by to component owner whenever a redraw to a canvas is needed. Caller must hold hierarchy lock *)
		PROCEDURE Draw*(canvas : WMGraphics.Canvas);
		BEGIN

			CheckReadLock;
			IF ~visible.Get() THEN RETURN END;
			canvas.SaveState(canvasState);
			IF font # NIL THEN canvas.SetFont(font) END;
			DrawBackground(canvas);
			IF extDraw # NIL THEN extDraw(canvas) END;
			DrawSubComponents(canvas);
			DrawForeground(canvas);
			canvas.RestoreState(canvasState)
		END Draw;
		
		(** declare a rectangle area as dirty *)
		PROCEDURE InvalidateRect*(r: Rectangle); 
		VAR parent : XML.Element;
			m : Messages.Message; b : Rectangle;
		BEGIN 
			IF ~initialized THEN RETURN END;
			IF ~visible.Get() THEN RETURN END;
			IF ~IsCallFromSequencer() THEN
				m.msgType := Messages.MsgExt;
				m.ext := invalidateRectMsg; m.x := r.l; m.y := r.t; m.dx := r.r; m.dy := r.b;
				IF ~sequencer.Add(m) THEN END;
			ELSE
				parent := GetParent();
				IF (parent # NIL) & (parent IS VisualComponent) THEN 
					b := bounds.Get();
					Rectangles.MoveRel(r, b.l, b.t);
					parent(VisualComponent).InvalidateRect(r)
				END
			END
		END InvalidateRect;
		
		PROCEDURE InvalidateCommand*(sender, par : PTR);
		VAR dummy : Messages.AsyncToken;
		BEGIN
			IF ~initialized THEN RETURN END;
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.InvalidateCommand, sender, par)
			ELSIF visible.Get() THEN InvalidateRect(GetClientRect()) 
			END
		END InvalidateCommand;
		
		PROCEDURE Invalidate*; (* For convenience in component internal use *)
		BEGIN
			InvalidateCommand(SELF, NIL)
		END Invalidate;
		
		(** recursively disable the redrawing of any components in the hierarchy *)
		(** dont forget to re-enable it ;-). Use with care to optimize sub-component operations *)
		PROCEDURE DisableUpdate*() ;
		VAR vc: VisualComponent;
		BEGIN
			ASSERT(IsCallFromSequencer());
			vc := GetVisualComponentRoot();
			IF (vc # NIL) & (vc IS Form) THEN  vc(Form).DisableUpdate() END
		END DisableUpdate;

		(** recursively enable the redrawing of any components in the hierarchy *)
		(** Only enable drawing if it was disabled before, but dont forget it, then ! *)
		PROCEDURE EnableUpdate*() ;
		VAR vc: VisualComponent;
		BEGIN
			ASSERT(IsCallFromSequencer());
			vc := GetVisualComponentRoot();
			IF (vc # NIL) & (vc IS Form) THEN  vc(Form).EnableUpdate() END
		END EnableUpdate;
		
		PROCEDURE GetInternalPointerInfo*() : WM.PointerInfo;
		VAR vc: VisualComponent;
		BEGIN
			ASSERT(IsCallFromSequencer());
			vc := GetVisualComponentRoot();
			IF (vc # NIL) & (vc IS Form) THEN 
				RETURN vc(Form).GetPointerInfo()
			ELSE
				RETURN NIL	
			END
		END GetInternalPointerInfo;
		
		PROCEDURE SetInternalPointerInfo*(pi : WM.PointerInfo);
		VAR vc: VisualComponent;
		BEGIN
			AssertLock;
			vc := GetVisualComponentRoot();
			IF (vc # NIL) & (vc IS Form) THEN vc(Form).SetPointerInfo(pi) END
		END SetInternalPointerInfo;
		
		PROCEDURE SetPointerInfo*(pi : WM.PointerInfo);
		BEGIN
			Acquire;
			(*IF initialized THEN
			(*	IF ~hasOldPointer THEN prevPointerInfo := GetInternalPointerInfo(); hasOldPointer := TRUE END; *)
				SetInternalPointerInfo(pi);
			END;*)	
			pointerInfo := pi;
			Release
		END SetPointerInfo;
		
		PROCEDURE GetPointerInfo*() : WM.PointerInfo;
		BEGIN
			RETURN pointerInfo
		END GetPointerInfo;
	
	(**  User interaction messages *)
		PROCEDURE SetExtPointerLeaveHandler*(handler : PointerLeaveHandler);
		BEGIN
			Acquire; extPointerLeave := handler; Release
		END SetExtPointerLeaveHandler;
		
		PROCEDURE SetExtPointerDownHandler*(handler : PointerHandler);
		BEGIN
			Acquire; extPointerDown := handler; Release
		END SetExtPointerDownHandler;
		
		PROCEDURE SetExtPointerMoveHandler*(handler : PointerHandler);
		BEGIN
			Acquire; extPointerMove := handler; Release
		END SetExtPointerMoveHandler;
		
		PROCEDURE SetExtPointerUpHandler*(handler : PointerHandler);
		BEGIN
			Acquire; extPointerUp := handler; Release
		END SetExtPointerUpHandler;
		
		PROCEDURE SetExtDragOverHandler*(handler : DragDropHandler);
		BEGIN
			Acquire; extDragOver := handler; Release
		END SetExtDragOverHandler;

		PROCEDURE SetExtDragDroppedHandler*(handler : DragDropHandler);
		BEGIN
			Acquire; extDragDropped := handler; Release
		END SetExtDragDroppedHandler;

		PROCEDURE SetExtDragResultHandler*(handler : DragResultHandler);
		BEGIN
			Acquire; extDragResult := handler; Release
		END SetExtDragResultHandler;
		
		PROCEDURE SetExtKeyEventHandler*(handler : KeyEventHandler);
		BEGIN
			Acquire; extKeyEvent := handler; Release
		END SetExtKeyEventHandler;
		
		PROCEDURE SetExtDrawHandler*(handler : DrawHandler);
		BEGIN
			Acquire; extDraw := handler; Release
		END SetExtDrawHandler;
		
		PROCEDURE SetExtFocusHandler*(handler : FocusHandler);
		BEGIN
			Acquire; extFocus := handler; Release
		END SetExtFocusHandler;
		
		PROCEDURE SetExtContextMenuHandler*(handler : ContextMenuHandler);
		BEGIN
			Acquire; extContextMenu := handler; Release
		END SetExtContextMenuHandler;
	
		(** Indicates the pointing device has left the component without a key pressed down. 
			May only be called from the sequencer thread. 
			Components interested in this message can override this method instead of searching for the message in HandleInternal. *)
		PROCEDURE PointerLeave*(); (** PROTECTED *)
		BEGIN ASSERT(IsCallFromSequencer());
		END PointerLeave;
		
	(** Indicates one of the pointer keys went down. keys is the set of buttons currently pressed. x, y is the position in component
		coordinates.
		May only be called from the sequencer thread. 
		Components interested in this message can override this method instead of searching for the message in HandleInternal. *)
		PROCEDURE PointerDown*(x, y: LONGINT; keys: SET); (** PROTECTED *)
		BEGIN ASSERT(IsCallFromSequencer());
			IF keys = {2} THEN ShowContextMenu(x, y) END;
		END PointerDown;
		
	(** Indicates the pointer was moved. keys is the set of buttons currently pressed. x, y is the position in component
		coordinates.
		May only be called from the sequencer thread. 
		Components interested in this message can override this method instead of searching for the message in HandleInternal. *)
		PROCEDURE PointerMove*(x, y: LONGINT; keys: SET); (** PROTECTED *)
		BEGIN ASSERT(IsCallFromSequencer());
		END PointerMove;
		
		PROCEDURE WheelMove*(dz: LONGINT); (** PROTECTED *)
		BEGIN ASSERT(IsCallFromSequencer());
		END WheelMove;
		
	(** Indicates one of the pointer keys went up. keys is the set of buttons currently pressed. x, y is the position in component
		coordinates.
		May only be called from the sequencer thread. 
		Components interested in this message can override this method instead of searching for the message in HandleInternal. *)
		PROCEDURE PointerUp*(x, y: LONGINT; keys: SET); (** PROTECTED *)
		BEGIN ASSERT(IsCallFromSequencer());
		END PointerUp;
		
	(** The component can determine wheter the key was pressed or released by examining the
		AosInputs.Release flag in flags. ucs contains the unicode equivalent of the key. Special input editors
		send the generated unicode characters via KeyEvent.	
		May only be called from the sequencer thread. 
		Components interested in this message can override this method instead of searching for the message in HandleInternal. *)
		PROCEDURE KeyEvent*(ucs : LONGINT; flags: SET; VAR keySym: LONGINT); (** PROTECTED *) 		
		BEGIN ASSERT(IsCallFromSequencer());
		END KeyEvent;
		
		PROCEDURE HandleInternal*(VAR msg : Message); (** PROTECTED *)
		VAR po : VisualComponent; nm : Message; handled : BOOLEAN; b : Rectangle;
		BEGIN
			ASSERT(IsCallFromSequencer());
			handled := FALSE;
			IF msg.msgType = Messages.MsgPointer THEN 

				IF msg.msgSubType = Messages.MsgSubPointerMove THEN
					IF msg.flags * {0, 1, 2} = {} THEN
						po := GetPositionOwner(msg.x, msg.y); 
						IF po # fPointerOwner THEN
							nm.msgType := Messages.MsgPointer;
							nm.msgSubType := Messages.MsgSubPointerLeave;
							HandleInternal(nm)
						END;
						fPointerOwner := po
					END
				END;
				IF (fPointerOwner = SELF) THEN  
					IF msg.msgSubType = Messages.MsgSubPointerMove THEN 
						IF extPointerMove # NIL THEN extPointerMove(msg.x, msg.y, msg.flags, handled) END;
						IF ~hasOldPointer & (pointerInfo # NIL) THEN 
							prevPointerInfo := GetInternalPointerInfo();
							hasOldPointer := TRUE;
							SetInternalPointerInfo(pointerInfo)
						END;
						IF ~handled THEN PointerMove(msg.x, msg.y, msg.flags) END;
						IF msg.dz # 0 THEN WheelMove(msg.dz) END
					ELSIF msg.msgSubType = Messages.MsgSubPointerDown THEN 
						IF extPointerDown # NIL THEN extPointerDown(msg.x, msg.y, msg.flags, handled) END;
						IF ~handled THEN PointerDown(msg.x, msg.y, msg.flags) END;
						SetFocus
					ELSIF msg.msgSubType = Messages.MsgSubPointerUp THEN
						IF extPointerUp # NIL THEN extPointerUp(msg.x, msg.y, msg.flags, handled) END;
						IF ~handled THEN PointerUp(msg.x, msg.y, msg.flags) END
					ELSIF msg.msgSubType = Messages.MsgSubPointerLeave THEN
						IF extPointerLeave # NIL THEN extPointerLeave(handled) END;
						IF hasOldPointer THEN SetInternalPointerInfo(prevPointerInfo); hasOldPointer := FALSE END;
						IF ~handled THEN PointerLeave END
					END
				ELSE 
					b := fPointerOwner.bounds.Get();
					msg.x := msg.x - b.l; msg.y := msg.y - b.t;
					 fPointerOwner.Handle(msg)
				END
			ELSIF msg.msgType = Messages.MsgKey THEN
				IF focusComponent # SELF THEN focusComponent.Handle(msg)
				ELSIF (visible.Get()) THEN
					IF ~needsTab.Get() & (msg.y = 0FF09H) THEN
						IF AosInputs.SHIFT IN msg.flags THEN FocusPrev ELSE FocusNext END
					ELSIF msg.y = 0FF67H THEN ShowContextMenu(0, 0)
					ELSE
						IF extKeyEvent # NIL THEN extKeyEvent(msg.x, msg.flags, msg.y, handled) END;
						IF ~handled THEN KeyEvent(msg.x, msg.flags, msg.y) END	
					END	
				END;
			ELSIF msg.msgType = Messages.MsgDrag THEN
				po := GetPositionOwner(msg.x, msg.y);
				IF po # SELF THEN (* Let child handle the drag and drop message *)
					b := po.bounds.Get();
					msg.x := msg.x - b.l; msg.y := msg.y - b.t;
					po.Handle(msg)
				ELSE (* handle the drag and drop message *)
					IF msg.msgSubType = Messages.MsgDragOver THEN 
						IF (msg.ext # NIL) THEN
							IF extDragOver # NIL THEN extDragOver(msg.x, msg.y, msg.ext(DragInfo), handled) END;
							IF ~handled THEN po.DragOver(msg.x, msg.y, msg.ext(DragInfo)) END
						END
					ELSIF msg.msgSubType = Messages.MsgDragDropped THEN 
						IF (msg.ext # NIL) THEN
							IF extDragDropped # NIL THEN extDragDropped(msg.x, msg.y, msg.ext(DragInfo), handled) END;
							IF ~handled THEN  
								po.DragDropped(msg.x, msg.y, msg.ext(DragInfo))
							END
						END
					END
				END
			ELSIF msg.msgType = Messages.MsgExt THEN
				IF msg.ext = invalidateRectMsg THEN InvalidateRect(Rectangles.MakeRect(msg.x, msg.y, msg.dx, msg.dx)) END;
			ELSE HandleInternal^(msg)	
			END;
		END HandleInternal;
	END VisualComponent;
	
	FormWindow* = OBJECT(WM.DoubleBufferWindow)
	VAR form : Form; locked : BOOLEAN;
			cs : WMGraphics.CanvasState;
			disableUpdate : LONGINT;
			content : VisualComponent;
			scaling* : BOOLEAN;
			
		PROCEDURE SetContent*(x : XML.Content);
		VAR seq : Messages.MsgSequencer;
		BEGIN locked := TRUE;
			DisableUpdate;
			IF form # NIL THEN form.Finalize; form.sequencer.Stop END;
			NEW(form, SELF); form.uid.Set(NewString("form"));
			NEW(seq, form.Handle); seq.SetTrapHandler(Trap); form.SetSequencer(seq);
			content := x(VisualComponent);
			form.AddContent(x);
			IF (x # NIL) & (x IS VisualComponent) THEN 
				form.focusComponent := x(VisualComponent);
			END;	
			form.Reset(SELF, NIL);
			EnableUpdate;
			form.InvalidateRect(form.GetClientRect());
			locked := FALSE;
		END SetContent;
		
		PROCEDURE DisableUpdate*;
		BEGIN {EXCLUSIVE}
			INC(disableUpdate);
			ASSERT(disableUpdate # -1);	(* overflow *)			
		END DisableUpdate;
		
		PROCEDURE EnableUpdate*;
		BEGIN {EXCLUSIVE}
			DEC(disableUpdate);
			ASSERT(disableUpdate # -1);	(* underflow *)			
		END EnableUpdate;
		
		PROCEDURE Resized( width, height: LONGINT);
		BEGIN
			IF ~scaling THEN
				DisableUpdate;
				ReInit(width, height);
				form.bounds.Set(Rectangles.MakeRect(0, 0, GetWidth(), GetHeight()));
				content.bounds.Set(Rectangles.MakeRect(0, 0, GetWidth(), GetHeight()));
				EnableUpdate;
				form.Invalidate()
			END	
		END Resized;
				
		PROCEDURE Trap():BOOLEAN;
		BEGIN
			AosOut.String("TRAP !!! --> Resetting Locks "); AosOut.Ln;
			form.sequencer.lock.Reset;
			RETURN TRUE
		END Trap;
		
		PROCEDURE Update(rect : Rectangle);
		BEGIN
			IF disableUpdate > 0 THEN RETURN END; 
			form.Acquire;
			form.sequencer.lock.HUGA:=TRUE;
			canvas.SaveState(cs);
			canvas.SetClipRect(rect);
			canvas.ClipRectAsNewLimits(0, 0);
			IF Raster.alpha IN img.fmt.components THEN 
				canvas.Fill(rect, 0H, WMGraphics.ModeCopy)
			ELSE
				canvas.Fill(rect, 0FFH, WMGraphics.ModeCopy)
			END;
			form.Draw(canvas);
			canvas.RestoreState(cs);
			form.sequencer.lock.HUGA:=FALSE;
			form.Release;
			CopyRect(rect);
			Invalidate(rect)
		END Update;
		
		PROCEDURE Handle*(VAR m : Message); 
		BEGIN
			Handle^(m);
			IF (m.msgType = Messages.MsgExt) & (m.ext = componentStyleMsg) THEN CSChanged END;
			IF TraceFocus IN Trace THEN IF m.msgType = Messages.MsgKey THEN form.TraceFocusChain END END;
			IF form # NIL THEN form.Handle(m) END
		END Handle;
		
		PROCEDURE CSChanged*;
		BEGIN
			DisableUpdate; (* the components are going to redraw like crazy *)
			form.Reset(SELF, NIL);
			EnableUpdate;
			form.InvalidateRect(form.GetClientRect())
		END CSChanged;
		
		PROCEDURE Close*();
		BEGIN
			Close^; (* remove the form to avoid further messages *)
			form.Acquire;			
			IF form # NIL THEN form.Finalize END;
			form.Release			
		END Close;
	END FormWindow;
	
	Form* = OBJECT(VisualComponent)
	VAR window : FormWindow;	
			state : WMGraphics.CanvasState;
		
		PROCEDURE &New(window : FormWindow);
		BEGIN
			Init; SELF.window := window; window.form := SELF;
			bounds.Set(Rectangles.MakeRect(0, 0, window.GetWidth(), window.GetHeight()));
		END New;
		
		PROCEDURE GetPointerInfo*() : WM.PointerInfo;
		BEGIN
			ASSERT(IsCallFromSequencer());
			RETURN window.pointerInfo
		END GetPointerInfo;

		PROCEDURE SetPointerInfo*(pi : WM.PointerInfo);
		BEGIN
			ASSERT(IsCallFromSequencer());
			window.SetPointerInfo(pi)
		END SetPointerInfo;
		
		PROCEDURE DisableUpdate*;
		BEGIN
			ASSERT(IsCallFromSequencer());
			window.DisableUpdate;			
		END DisableUpdate;
		
		PROCEDURE EnableUpdate*;
		BEGIN
			ASSERT(IsCallFromSequencer());
			window.EnableUpdate;			
		END EnableUpdate;
		
		PROCEDURE InvalidateRect*(rect : Rectangle);
		BEGIN
			IF window # NIL THEN window.Update(rect) END
		END InvalidateRect;
	END Form;
	
TYPE
	(** PropertyLists for style support *)
	PropertyListEntry = POINTER TO RECORD 
		next : PropertyListEntry; 
		name : String; 
		list : WMProperties.PropertyList; 
	END;
	
	PropertyListList* = OBJECT
	VAR first : PropertyListEntry;
		PROCEDURE Find*(name : ARRAY OF CHAR) : WMProperties.PropertyList;
		VAR cur : PropertyListEntry;
		BEGIN {EXCLUSIVE}
			cur := first;
			WHILE (cur # NIL) & (cur.name^ # name) DO cur := cur.next END;
			IF cur # NIL THEN RETURN cur.list
			ELSE RETURN NIL
			END
		END Find;
		
		PROCEDURE RemoveInternal(name : ARRAY OF CHAR);
		VAR cur : PropertyListEntry;
		BEGIN
			IF first = NIL THEN RETURN END;
			IF (first # NIL) & (first.name^ = name) THEN first := first.next 
			ELSE
				cur := first;
				WHILE (cur.next # NIL) DO
					IF (cur.next.name^ = name) THEN cur.next := cur.next.next END;
					cur := cur.next
				END
			END
		END RemoveInternal;
		
		PROCEDURE Remove*(name : ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			RemoveInternal(name)
		END Remove;
		
		PROCEDURE Add*(name : ARRAY OF CHAR; pl : WMProperties.PropertyList);
		VAR new : PropertyListEntry;
		BEGIN {EXCLUSIVE}
			RemoveInternal(name);
			NEW(new); new.name := NewString(name); new.list := pl; new.next := first; first := new;
		END Add;
		
		PROCEDURE UpdateStyle*;
		VAR
			en : XMLObjects.Enumerator;
			p : PTR; s, n : String; i : LONGINT;
			pl : WMProperties.PropertyList;
		BEGIN
			IF currentStyle = NIL THEN RETURN END;
			en := currentStyle.GetContents(); 
			WHILE en.HasMoreElements() DO
				p := en.GetNext();
				IF p IS XML.Element THEN
					s := p(XML.Element).GetName();
					pl := propertyListList.Find(s^);
					IF pl # NIL THEN pl.SetXML(p(XML.Element)) END
				END
			END
		END UpdateStyle;
		
	END PropertyListList;
	
VAR hasErrors : BOOLEAN; (* accessed only from Load (EXCLUSIVE) *)
	registry* : XML.ElementRegistry;
	invalidateRectMsg* : Messages.MessageExtension; (* used as unique ID *)
	 
	PrototypeID*, PrototypeUID* : WMProperties.StringProperty;
	PrototypeBounds* : WMProperties.RectangleProperty;
	PrototypeEnabled* : WMProperties.BooleanProperty;
	PrototypeFillColor* : WMProperties.ColorProperty;
	PrototypeAlignment* : WMProperties.Int32Property;
	PrototypeVisible*, PrototypeTakesFocus*, PrototypeNeedsTab* : WMProperties.BooleanProperty;
	StrComponent, StrVisualComponent : String;
	GSonStartDrag, GSonStartDragInfo : String;
	 
	propertyListList- : PropertyListList;
	currentStyle- : XML.Element;
	componentStyleMsg : ComponentStyleChanged;

PROCEDURE SetStyle*(style : XML.Element);
BEGIN
	SetStyleInternal(style)
END SetStyle;

PROCEDURE SetStyleInternal(style : XML.Element);
VAR  msg : Messages.Message;
	 m : WM.WindowManager;
BEGIN
	currentStyle := style;
	IF propertyListList # NIL THEN propertyListList.UpdateStyle END;
	
	msg.msgType := Messages.MsgExt; msg.ext := componentStyleMsg;
	m := WM.GetDefaultManager();
	m.Broadcast(msg)
END SetStyleInternal;
	 
PROCEDURE FindRelativePath(x : Component; VAR path : ARRAY OF CHAR; pos : LONGINT) : Component;
VAR p : PTR;
	contents: XMLObjects.Enumerator; 
	sn : ARRAY MaxComponentNameSize OF CHAR;
	i : LONGINT; id : String;
BEGIN
	IF x = NIL THEN RETURN NIL 
	ELSIF path[pos] = 0X THEN RETURN x 
	ELSIF (pos = 0) & (path[0] = "/") THEN RETURN FindRelativePath(x.GetComponentRoot(), path, pos + 1)
	ELSIF (path[pos] = ".") & (path[pos + 1] = ".") THEN
		INC(pos, 2); IF path[pos]="/" THEN INC(pos) END;
		p := x.GetParent();
		IF (p # NIL) & (p IS Component) THEN 
			
		RETURN FindRelativePath(p(Component), path, pos) 
		ELSE RETURN NIL 
		END
	ELSE
		i := 0; WHILE (i < MaxComponentNameSize - 1) & (path[pos] # 0X) & (path[pos] # "/") DO
			sn[i] := path[pos]; INC(i); INC(pos)
		END;
		IF (path[pos] = "/") THEN INC(pos) END;
		sn[i] := 0X;
		contents := x.GetContents(); contents.Reset;
		WHILE contents.HasMoreElements() DO 
			p := contents.GetNext();
			 			
			IF (p IS Component) THEN
				id := p(Component).id.Get();
		(*		IF (id # NIL) THEN AosOut.String("check "); AosOut.String(id^); AosOut.String("="); AosOut.String(sn) END; *)
				IF (id # NIL) & (id^ = sn) THEN (* AosOut.String("got it"); *) RETURN FindRelativePath(p(Component), path, pos) END
			END
		END;
		RETURN NIL
	END	
END FindRelativePath;

(* Report errors while parsing *)
PROCEDURE Error(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	AosOut.String("Parse error at pos "); AosOut.Int(pos, 5); AosOut.String(" in line "); AosOut.Int(line, 5); 
	AosOut.String(" row "); AosOut.Int(row, 5); AosOut.String(" - "); AosOut.String(msg); AosOut.Ln;
	hasErrors := TRUE
END Error;

(** Load an XML file. Return NIL if errors occured *)
PROCEDURE Load*(filename : ARRAY OF CHAR) : XML.Content;
VAR f : AosFS.File;
	scanner : XMLScanner.Scanner;
	parser : XMLParser.Parser;
	doc : XML.Document;
BEGIN {EXCLUSIVE}
	hasErrors := FALSE;
	f := AosFS.Old(filename);
	IF f # NIL THEN
		NEW(scanner, f); scanner.reportError := Error;
		NEW(parser, scanner); parser.reportError := Error;
		parser.elemReg := registry; doc := parser.Parse();
		IF hasErrors THEN RETURN NIL END;
		RETURN doc.GetRoot()
	END;
	RETURN NIL
END Load;

(** Load Component registry file. Return NIL if errors occured *)
PROCEDURE LoadRegistry*(filename : ARRAY OF CHAR) : XML.Content;
VAR f : AosFS.File;
	scanner : XMLScanner.Scanner;
	parser : XMLParser.Parser;
	doc : XML.Document;
BEGIN {EXCLUSIVE}
	hasErrors := FALSE;
	f := AosFS.Old(filename);
	IF f # NIL THEN
		NEW(scanner, f); scanner.reportError := Error;
		NEW(parser, scanner); parser.reportError := Error;
		parser.elemReg := registry; doc := parser.Parse();
		IF hasErrors THEN RETURN NIL END;
		RETURN doc.GetRoot()
	END;
	RETURN NIL
END LoadRegistry;

PROCEDURE LoadStyleInternal(filename : ARRAY OF CHAR);
VAR f : AosFS.File;
	scanner : XMLScanner.Scanner;
	parser : XMLParser.Parser;
	doc : XML.Document;
	manager : WM.WindowManager;
BEGIN
	hasErrors := FALSE;
	f := AosFS.Old(filename);
	IF f # NIL THEN
		NEW(scanner, f); scanner.reportError := Error;
		NEW(parser, scanner); parser.reportError := Error;
		parser.elemReg := registry; doc := parser.Parse();
		IF hasErrors THEN AosOut.String("Stylefile not ok"); AosOut.Ln 
		ELSE
			SetStyleInternal(doc.GetRoot())
		END	
	END;
END LoadStyleInternal;

(** Load Component registry file. Return NIL if errors occured *)
PROCEDURE LoadStyle*(par : PTR) : PTR;
VAR  filename : ARRAY 64 OF CHAR;	
	s: AosCommands.Parameters;
	sr : AosIO.StringReader;
BEGIN {EXCLUSIVE}
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.String(filename); 
	LoadStyleInternal(filename);
	RETURN NIL
END LoadStyle;

PROCEDURE NewString*(x : ARRAY OF CHAR) : String;
VAR t : String;
BEGIN
	NEW(t, LEN(x)); COPY(x, t^); RETURN t
END NewString;

PROCEDURE InitPrototypes;
BEGIN
	(* General component properties *)
	NEW(PrototypeID, NIL, NewString("ID"), 
		NewString("identifier of the component"));
	NEW(PrototypeUID, NIL, NewString("UID"), 
		NewString("unique identifier of the component"));
	NEW(PrototypeEnabled, NIL, NewString("enabled"), 
		NewString("defines if the component is enabled"));
	(* Visual component properties *)
	NEW(PrototypeBounds, NIL, NewString("Bounds"), 
		NewString("the bounding box of the component in parent coordinates"));
	NEW(PrototypeFillColor, NIL, NewString("FillColor"), 
		NewString("the main fill color of the component. i.e. background"));
	NEW(PrototypeAlignment, NIL, NewString("Alignment"), 
		NewString("defines the alignment none, left, right, top, bottom or client"));
	PrototypeAlignment.Set(0);
	
	NEW(PrototypeVisible, NIL, NewString("Visible"), 
		NewString("defines if the component is visible"));
	PrototypeVisible.Set(TRUE);
	
	NEW(PrototypeTakesFocus, NIL, NewString("TakesFocus"), 
		NewString("defines if the component takes the keyboard focus"));
	NEW(PrototypeNeedsTab, NIL, NewString("NeedsTab"), 
		NewString("defines if the component handles the tabulator key"));
		
	StrComponent := NewString("Component");
	StrVisualComponent := NewString("VisualComponent");
END InitPrototypes;

PROCEDURE DumpComponent*(obj : PTR);

	PROCEDURE DumpProperties(pl : WMProperties.PropertyList);
	VAR i : LONGINT; pa : WMProperties.PropertyArray; p :WMProperties.Property; s : String;
		st : AosIO.StringWriter;
		value : ARRAY 100 OF CHAR;
	BEGIN
		pa := pl.Enumerate();
		FOR i := 0 TO LEN(pa) - 1 DO
			p := pa[i];
			IF p = NIL THEN AosOut.String("<property is nil>"); AosOut.Ln;
			ELSE
				AosOut.String("Name : "); s := p.GetName(); IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String("<NIL>") END;
				NEW(st, 100); p.ToStream(st); st.Get(value);
				AosOut.String(" Value : "); AosOut.String(value); IF p.GetIsDefault() THEN AosOut.String("(default)") END;
				AosOut.String(" Info : "); s := p.GetInfo(); IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String("<NIL>") END;
				AosOut.Ln
			END
		END
	END DumpProperties;

	PROCEDURE DumpEvents(el : WMEvents.EventSourceList);
	VAR i : LONGINT; ea : WMEvents.EventSourceArray; e : WMEvents.EventSource; s : String;
	BEGIN
		ea := el.Enumerate();
		FOR i := 0 TO LEN(ea) - 1 DO
			e := ea[i];
			IF e # NIL THEN 
				AosOut.String("Name : "); s := e.GetName(); IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String("<NIL>") END;
				AosOut.String("  ");
				AosOut.String(" Info : "); s := e.GetInfo(); IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String("<NIL>") END;
				AosOut.Ln
			END;
		END;
	END DumpEvents;	
	
	PROCEDURE DumpListeners(el : WMEvents.EventListenerList);
	VAR i : LONGINT; ea : WMEvents.EventListenerArray; e : WMEvents.EventListenerInfo; s : String;
	BEGIN
		ea := el.Enumerate();
		FOR i := 0 TO LEN(ea)- 1 DO
			e := ea[i];
			IF e # NIL THEN 
				AosOut.String("Name : "); s := e.GetName(); IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String("<NIL>") END;
				AosOut.String("  ");
				AosOut.String(" Info : "); s := e.GetInfo(); IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String("<NIL>") END;
				AosOut.Ln
			END;
		END;
	END DumpListeners;
	
BEGIN
	IF obj = NIL THEN AosOut.String("NIL"); AosOut.Ln
	ELSE
		IF obj IS Component THEN
			AosOut.String("Properties : "); AosOut.Ln;
			DumpProperties(obj(Component).properties);
			AosOut.String("Events : "); AosOut.Ln;
			DumpEvents(obj(Component).events);
			AosOut.String("Listeners : "); AosOut.Ln;
			DumpListeners(obj(Component).eventListeners);
		ELSE AosOut.String("is not a component"); AosOut.Ln
		END
	END
END DumpComponent;

PROCEDURE PropertyGenerator(par : PTR) : PTR;
VAR x : Properties;
BEGIN
	NEW(x);
	RETURN x
END PropertyGenerator;

BEGIN
	NEW(propertyListList);
	InitPrototypes;
	NEW(registry);
	registry.RegisterElement("Properties", PropertyGenerator);
	NEW(invalidateRectMsg);
	LoadStyleInternal("ComponentStyle.XML")
END WMComponents.


The message sequencer contains a reader writer lock that can be used to block the hierarchy.
Each message-call from the sequencer posesses the writer lock.

WMComponents.LoadStyle ComponentStyle.XML  ~

If a focusComponent is set in an non-focus container-component, the focus can not escape the "isolated" component group

Color Codes
 Highlight
Types and Procedures
Lock Acquire / Lock Release
Preferred notation (comment)
Unsafe / Temporary / Stupid / requires attention
Permanent Comment 
Assertion
Debug