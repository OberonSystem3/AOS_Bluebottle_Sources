MODULE WMStandardComponents;	(** AUTHOR "TF"; PURPOSE "Standard components"; *)

IMPORT
	AosOut, AosModules, AosKernel, AosCommands, WMComponents, Utilities,
	WMGraphics, WMGraphicUtilities, WMRectangles,
	WMEvents, XMLObjects, XML, AosInputs, WMProperties, WMWindowManager;

TYPE
	(* Local type-alias for convenience *)
	String = Utilities.String;
	EventSource = WMEvents.EventSource;
	EventListener = WMEvents.EventListener ;
	EventListenerInfo = WMEvents.EventListenerInfo;
	Canvas = WMGraphics.Canvas;
	
	(** Timer *)
TYPE
	Timer* = OBJECT (WMComponents.Component)
	VAR
		alive: BOOLEAN;
		timer: AosKernel.Timer;
		onTimer*: EventSource;
		eStart*, eStop* : EventListenerInfo;
		interval* : WMProperties.Int32Property;
		internalEnabled : BOOLEAN;
			
		PROCEDURE &Init();
		BEGIN
			Init^();
			NEW(timer);
			alive := TRUE; 
			enabled.Set(FALSE); internalEnabled := FALSE;
			NEW(onTimer, SELF, GSonTimer, GSonTimerInfo, SELF.StringToCompCommand); events.Add(onTimer);
			NEW(interval, PrototypeInterval, NIL, NIL); properties.Add(interval);
			NEW(eStart, GSStart, GSStartTimerInfo, SELF.Start); eventListeners.Add(eStart);
			NEW(eStop, GSStop, GSStopTimerInfo, SELF.Stop); eventListeners.Add(eStop);
			SetNameAsString(StrTimer)
		END Init;
		
		PROCEDURE PropertyChanged*(sender, property : PTR);
		BEGIN
			IF property = enabled THEN
				IF internalEnabled # enabled.Get() THEN 
					IF enabled.Get() THEN Start(SELF, NIL) ELSE Stop(SELF, NIL) END
				END 
			ELSE PropertyChanged^(sender, property)
			END;
		END PropertyChanged;
		
		PROCEDURE Start*(sender, par : PTR); (** Eventhandler *)
		BEGIN
			enabled.Set(TRUE); BEGIN {EXCLUSIVE} internalEnabled := TRUE END;
		END Start;
		
		PROCEDURE Stop*(sender, par : PTR); (** Eventhandler *)
		BEGIN
			enabled.Set(FALSE); BEGIN {EXCLUSIVE} internalEnabled := FALSE END;
		END Stop;
		
		PROCEDURE Finalize*(); (** PROTECTED *)
		BEGIN
			timer.Wakeup; internalEnabled := FALSE; BEGIN {EXCLUSIVE} alive := FALSE END; Finalize^
		END Finalize;
		
	BEGIN {ACTIVE}
		WHILE alive DO
			BEGIN {EXCLUSIVE} AWAIT(internalEnabled OR ~alive) END;
			IF alive THEN
				timer.Sleep(interval.Get());
				IF internalEnabled & (onTimer # NIL) THEN onTimer.Call(NIL) END
			END
		END
	END Timer;
	
	(** SystemCommand executes an AosCommand string *)
	(** Example : <SystemCommand execute="Bunny.Insert BunnyLinear.gif 8 16" /> *)
	SystemCommand* = OBJECT(WMComponents.Component)
	VAR commandString* : WMProperties.StringProperty;
		eRun* : EventListenerInfo;
	
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(commandString, PrototypeCommandString, NIL, NIL); properties.Add(commandString);
			NEW(eRun, GSRun, GSRunSystemCommandInfo, SELF.Run); eventListeners.Add(eRun);
			SetNameAsString(StrSystemCommand)
		END Init;
	
		PROCEDURE Run*(sender, par : PTR); (** Eventhandler *) 
		VAR res : LONGINT; execute : String; msg : ARRAY 128 OF CHAR;
		BEGIN
			(* synchronize if not synchronized *)
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Run, sender, par)
			ELSE
				(* actual business logic *)
				execute := commandString.Get();
				IF execute # NIL THEN
					AosCommands.Call(execute^, {}, res, msg);
					IF res # 0 THEN AosOut.Enter; AosOut.String(msg); AosOut.Exit END
				 END
			END	
		END Run;
	END SystemCommand;
	
	(** Event executes a Component Event *)
	(** Example : <Event execute=%Timer1 Stop" /> *)
	Event* = OBJECT(WMComponents.Component)
	VAR commandString* : WMProperties.StringProperty;
		eRun* : EventListenerInfo;
	
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(commandString, PrototypeCommandString, NIL, NIL); properties.Add(commandString);
			NEW(eRun, GSRun, GSCallEventInfo, SELF.Run); eventListeners.Add(eRun);
			SetNameAsString(StrEvent)
		END Init;
	
		PROCEDURE Run*(sender, par : PTR); (** Eventhandler *) 
		VAR res : LONGINT; msg : ARRAY 128 OF CHAR;
			execute : String;
			event : EventListener;
		BEGIN
			(* synchronize if not synchronized *)
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Run, sender, par) 
			ELSE
				(* actual business logic *)
				execute := commandString.Get();
				IF execute # NIL THEN 
					event := StringToCompCommand(execute);
					IF event # NIL THEN event(sender, par) END;
				END
			END	
		END Run;
	END Event;
	
	(* Assign* = OBJECT(WMComponents.Component)
	VAR srcProp, dstProp, srcComp, dstComp : String;
		src, dst : WMComponents.Component;
		assignSilent : BOOLEAN;
	
		PROCEDURE SetPropertyValue*(name, value : String); (** OVERRIDE *)
		BEGIN 
			Acquire; 
			IF name^ = "srcComp" THEN srcComp := value
			ELSIF name^ = "srcProp" THEN srcProp := value
			ELSIF name^ = "dstComp" THEN dstComp := value
			ELSIF name^ = "dstProp" THEN dstProp := value
			ELSIF name^ = "assignSilent" THEN assignSilent := value^ = "true"
			ELSE SetPropertyValue^(name, value)
			END;
			ReleaseWrite
		END SetProperty;
		
		(** Return the number of event consumers that can be called *) 
		PROCEDURE GetNofCommands*() : LONGINT; (** OVERRIDE *)
		BEGIN RETURN GetNofCommands^() + 1;
		END GetNofCommands;
		
		(** Return the name of an event consumer *) 
		PROCEDURE GetCommandName*(i : LONGINT) : String;
		BEGIN 
			CASE i - GetNofCommands^() OF
			| 0: RETURN WMComponents.NewString("Execute")
			ELSE RETURN GetCommandName^(i)
			END
		END GetCommandName;
		
		(** Get the event consumer *)
		PROCEDURE GetCommand*(commandName : String) : CompCommand;
		BEGIN
			IF commandName^ = "Execute" THEN RETURN SELF.Execute
			ELSE RETURN GetCommand^(commandName)
			END
		END GetCommand;
	
		PROCEDURE Execute*(sender, par : PTR); (** Eventhandler *) 
		VAR contents : XMLObjects.Enumerator; c : PTR; result : WMComponents.Component;
			str : ARRAY 1024 OF CHAR; oldMode : BOOLEAN;
		BEGIN
			(* synchronize if not synchronized *)
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Execute, sender, par) 
			ELSE
				(* actual business logic *)
				IF src = NIL THEN src := StringToComponent(srcComp) END;
				IF dst = NIL THEN dst := StringToComponent(dstComp) END;
				IF (src # NIL) & (dst # NIL) THEN
					IF assignSilent THEN dst.AcquireWrite; oldMode := dst.GetSilent(); dst.SetSilent(TRUE) END;
					src.GetPropertyValue(srcProp, str); dst.SetPropertyValue(dstProp, WMComponents.NewString(str));
					IF assignSilent THEN dst.SetSilent(oldMode); dst.ReleaseWrite END;
				ELSE
					IF src = NIL THEN AosOut.String("Source component not found"); AosOut.Ln END;
					IF dst = NIL THEN AosOut.String("Destination Component not found"); AosOut.Ln END;
				END
			END	
		END Execute;
	END Assign;

	(** Sequentially executes a number of SystemCommand, Event and Batch *)	
	Batch* = OBJECT(WMComponents.Component)
		
		(** Return the number of event consumers that can be called *) 
		PROCEDURE GetNofCommands*() : LONGINT; (** OVERRIDE *)
		BEGIN RETURN GetNofCommands^() + 1;
		END GetNofCommands;
		
		(** Return the name of a command *) 
		PROCEDURE GetCommandName*(i : LONGINT) : String;
		BEGIN 
			CASE i - GetNofCommands^() OF
			| 0: RETURN WMComponents.NewString("Execute")
			ELSE RETURN GetCommandName^(i)
			END
		END GetCommandName;
		
		(** Get the event consumer *)
		PROCEDURE GetCommand*(commandName : String) : CompCommand;
		BEGIN
			IF commandName^ = "Execute" THEN RETURN SELF.Execute
			ELSE RETURN GetCommand^(commandName)
			END
		END GetCommand;
	
		PROCEDURE Execute*(sender, par : PTR); (** Eventhandler *) 
		VAR contents : XMLObjects.Enumerator; c : PTR; result : WMComponents.Component;
		BEGIN
			(* synchronize if not synchronized *)
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Execute, sender, par) 
			ELSE
				(* actual business logic *)
				contents := GetContents(); contents.Reset;
				WHILE (result = NIL) & contents.HasMoreElements() DO 
					c := contents.GetNext();
					IF (c IS SystemCommand) THEN c(SystemCommand).Execute(SELF, NIL)
					ELSIF (c IS Event) THEN c(Event).Execute(SELF, NIL) 
					ELSIF (c IS Assign) THEN c(Assign).Execute(SELF, NIL) 
					ELSIF (c IS Batch) THEN c(Batch).Execute(SELF, NIL) 
					END
				END;
			END	
		END Execute;
	END Batch;

	*)
(** Visual components *)
TYPE
	Panel* = OBJECT (WMComponents.VisualComponent)
		PROCEDURE &Init;
		BEGIN
			Init^;
			SetNameAsString(StrPanel)
		END Init;
		
		PROCEDURE PropertyChanged*(sender, property : PTR);
		BEGIN
			IF property = fillColor THEN Invalidate 
			ELSE PropertyChanged^(sender, property)
			END;
		END PropertyChanged;
		
		PROCEDURE RecacheProperties;
		BEGIN
			RecacheProperties^;
			Invalidate
		END RecacheProperties;
	END Panel;

TYPE	
	Label* = OBJECT(Panel)
	VAR
		caption* : WMProperties.StringProperty;
		textColor* : WMProperties.ColorProperty;
		alignH* : WMProperties.Int32Property;
		alignV* : WMProperties.Int32Property;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(caption, PrototypeCaption, NIL, NIL); properties.Add(caption);
			NEW(textColor, PrototypeTextColor, NIL, NIL); properties.Add(textColor);
			NEW(alignH, PrototypeAlignH, NIL, NIL); properties.Add(alignH);
			NEW(alignV, PrototypeAlignV, NIL, NIL); properties.Add(alignV);
			SetNameAsString(StrLabel)
		END Init;
		
		PROCEDURE RecachProperties;
		BEGIN
			RecacheProperties^;
			Invalidate
		END RecachProperties;
		
		PROCEDURE PropertyChanged*(sender, property : PTR);
		BEGIN
			IF (property = caption) OR (property = textColor) THEN Invalidate 
			ELSE PropertyChanged^(sender, property)
			END;
		END PropertyChanged;
			
		PROCEDURE SetCaption*(x : ARRAY OF CHAR);
		BEGIN
			caption.SetAOC(x) 
		END SetCaption;

		PROCEDURE DrawBackground*(canvas : Canvas);
		VAR str : String;
		BEGIN
			DrawBackground^(canvas); str := caption.Get();
			IF str # NIL THEN
				canvas.SetColor(textColor.Get());
				WMGraphics.DrawStringInRect(canvas, GetClientRect(), FALSE, alignH.Get(), alignV.Get(), str^)
			END;
		END DrawBackground;
	END Label;
		
CONST BtnStyleSimple* = 0; BtnStyleRoundH* = 1; BtnStyleRoundV* = 2; BtnStyleGlass* = 3;
		 BtnStyleElevator* = 4;

TYPE
	(** Button *)	
	Button* = OBJECT (WMComponents.VisualComponent)
		VAR 
			clDefault-, clHover-, clPressed-, 
			clTextDefault-, clTextHover-, clTextPressed- : WMProperties.ColorProperty;
			fontHeight- : WMProperties.Int32Property;
			isRepeating-, isToggle-, isFlat- : WMProperties.BooleanProperty;
			style-, glassEffect- : WMProperties.Int32Property;
			caption-, onClickHandler-: WMProperties.StringProperty;
			imgDefaultName-, imgHoverName-, imgPressedName-, imageName- : WMProperties.StringProperty;
			imgDefault, imgHover, imgPressed, image : WMGraphics.Image;
			pressed, keyboardPressed, mouseOver , allowUp: BOOLEAN;
			onClick* : EventSource;
			handler : WMEvents.EventListener;
			invert3d : BOOLEAN;
			repeater : Timer;
			userData* : PTR;
	
		PROCEDURE &Init;
		BEGIN
			Init^;
			bounds.SetPrototype(ButtonBoundsProto); (* override the defaults *)
			NEW(clDefault, PrototypeBclDefault, NIL, NIL); properties.Add(clDefault);
			NEW(clHover, PrototypeBclHover, NIL, NIL); properties.Add(clHover);
			NEW(clPressed, PrototypeBclPressed, NIL, NIL); properties.Add(clPressed);
			NEW(clTextDefault, PrototypeBclTextDefault, NIL, NIL); properties.Add(clTextDefault);
			NEW(clTextHover, PrototypeBclTextHover, NIL, NIL); properties.Add(clTextHover);
			NEW(clTextPressed, PrototypeBclTextPressed,  NIL, NIL); properties.Add(clTextPressed);
			NEW(fontHeight, PrototypeBfontHeight, NIL, NIL); properties.Add(fontHeight);	
			NEW(isRepeating, PrototypeBisRepeating, NIL, NIL); properties.Add(isRepeating);	
			NEW(isToggle, PrototypeBisToggle, NIL, NIL); properties.Add(isToggle);	
			NEW(isFlat, PrototypeBisFlat, NIL, NIL); properties.Add(isFlat);
			NEW(caption, PrototypeBcaption, NIL, NIL); properties.Add(caption);
			NEW(style, PrototypeBstyle, NIL, NIL); properties.Add(style);
			NEW(glassEffect, PrototypeBglassEffect, NIL, NIL); properties.Add(glassEffect);
			NEW(onClickHandler, PrototypeBonClickHandler, NIL, NIL); properties.Add(onClickHandler);
			(*---*)
			NEW(imgDefaultName, PrototypeBimgDefaultName, NIL, NIL); properties.Add(imgDefaultName);
			NEW(imgHoverName, PrototypeBimgHoverName, NIL, NIL); properties.Add(imgHoverName);
			NEW(imgPressedName, PrototypeBimgPressedName, NIL, NIL); properties.Add(imgPressedName);
			NEW(imageName, PrototypeBimageName, NIL, NIL); properties.Add(imageName);
			(* events *)
			NEW(onClick, SELF, GSonClick, GSonClickButtonInfo, SELF.StringToCompCommand); events.Add(onClick);
			SetNameAsString(StrButton);
			takesFocus.Set(TRUE)
		END Init;
		
		PROCEDURE CheckClickHandler;
		VAR th : WMEvents.EventListener;
			s : String;
		BEGIN
			s := onClickHandler.Get();
			IF s # NIL THEN
				th := StringToCompCommand(s);
				IF (handler # NIL) THEN onClick.Remove(handler) END;
				IF th # NIL THEN onClick.Add(th); handler := th END
			END
		END CheckClickHandler;
			
		PROCEDURE RecacheProperties;
		VAR s : String;
		BEGIN
			RecacheProperties^;
			s := imgDefaultName.Get(); IF s # NIL THEN imgDefault := WMGraphics.LoadImage(s^, TRUE) END;
			s := imgHoverName.Get(); IF s # NIL THEN imgHover := WMGraphics.LoadImage(s^, TRUE) END;
			s := imgPressedName.Get(); IF s # NIL THEN imgPressed := WMGraphics.LoadImage(s^, TRUE) END;
			s := imageName.Get(); IF s # NIL THEN image := WMGraphics.LoadImage(s^, TRUE) END;
			CheckClickHandler;
			Invalidate	
		END RecacheProperties;
		
		PROCEDURE PropertyChanged*(sender, data : PTR);
		BEGIN
			IF data = onClickHandler THEN CheckClickHandler
			ELSIF (data = imgDefaultName) OR (data = imgHoverName) 
				OR (data = imgPressedName) OR (data = imageName) THEN
				RecacheProperties; Invalidate;
			ELSIF (data = caption) THEN Invalidate	
			ELSE PropertyChanged^(sender, data)
			END;
		END PropertyChanged;
		
		PROCEDURE CheckRepeating(start : BOOLEAN);
		BEGIN
			IF isRepeating.Get() THEN
				IF start THEN 
					IF repeater = NIL THEN NEW(repeater); AddContent(repeater); repeater.onTimer.Add(Click) END;
					repeater.Start(SELF, NIL)
				ELSE
					IF repeater # NIL THEN repeater.Stop(SELF, NIL) END
				END	
			END
		END CheckRepeating;
		
		PROCEDURE SetInvert3d*(invert : BOOLEAN);
		BEGIN
			Acquire;
			IF invert # invert3d THEN invert3d := invert; Invalidate END;
			Release
		END SetInvert3d;

		PROCEDURE SetPressed*(down : BOOLEAN);
		BEGIN
			Acquire;
			IF pressed # down THEN
				pressed := down;
				Invalidate
			END;
			Release;
		END SetPressed;
		
		PROCEDURE FocusReceived*;
		BEGIN
			FocusReceived^;
			Invalidate
		END FocusReceived;
		
		PROCEDURE FocusLost*;
		BEGIN
			FocusLost^;
			Invalidate
		END FocusLost;
		
		PROCEDURE Down;
		BEGIN
			IF ~isToggle.Get() THEN IF ~pressed THEN pressed := TRUE; Invalidate; CheckRepeating(TRUE) END;
			ELSE pressed := (~pressed OR ~allowUp); IF pressed THEN Click(SELF, userData) END; Invalidate
			END;	
		END Down;
		
		PROCEDURE Up;
		BEGIN
			IF isToggle.Get() THEN RETURN END;
			IF pressed & (mouseOver OR keyboardPressed) THEN
				CheckRepeating(FALSE);  Click(SELF, userData);
				pressed := FALSE;
				Invalidate
			END; 
			pressed := FALSE;
		END Up;
				
		PROCEDURE PointerDown(x, y: LONGINT; keys : SET); (** PROTECTED *)
		BEGIN
			Down;
			PointerDown^(x, y, keys)
		END PointerDown;
		
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET); (** PROTECTED *)
		BEGIN
			IF IsHit(x, y) THEN 
				IF ~mouseOver THEN mouseOver := TRUE; IF pressed THEN CheckRepeating(TRUE) END; Invalidate END
			ELSE 	
				IF mouseOver THEN mouseOver := FALSE; IF pressed THEN CheckRepeating(FALSE) END; Invalidate END
			END;	
			PointerMove^(x, y, keys)
		END PointerMove;
		
		PROCEDURE PointerUp(x, y : LONGINT; keys : SET); (** PROTECTED *)
		BEGIN
			Up;
			PointerUp^(x, y, keys)
		END PointerUp;
		
		PROCEDURE PointerLeave*; (** PROTECTED *)
		BEGIN
			 mouseOver := FALSE; Invalidate
		END PointerLeave;
		
		PROCEDURE SetCaption*(x : ARRAY OF CHAR);
		BEGIN
			caption.Set(WMComponents.NewString(x))
		END SetCaption;
		
		PROCEDURE IsHit(x, y: LONGINT):BOOLEAN;
		 VAR img : WMGraphics.Image; t : BOOLEAN;
		 BEGIN
			Acquire;	
			IF pressed & mouseOver THEN img := imgPressed
			ELSIF mouseOver THEN img := imgHover
			ELSE img := imgDefault
			END;
			IF (img # NIL) THEN t := WMGraphics.IsBitmapHit(x, y, 64, img)
			ELSE t := IsHit^(x, y)
			END;
			Release;
			RETURN t
		END IsHit;
		
		PROCEDURE Draw(canvas : WMGraphics.Canvas);
		VAR mode, ul, mid, borderWidth, lr, xpos, ypos : LONGINT;
			 tc : WMGraphics.Color; img : WMGraphics.Image; r, rect : WMGraphics.Rectangle; down : BOOLEAN;
			 str : String;
		BEGIN
			IF ~visible.Get() THEN RETURN END;
			Acquire;
			down := pressed & (mouseOver OR isToggle.Get() OR keyboardPressed);
			IF down THEN mid := clPressed.Get(); tc := clTextPressed.Get(); img := imgPressed
			ELSIF mouseOver THEN 	mid := clHover.Get(); tc := clTextHover.Get();	img := imgHover
			ELSE mid := clDefault.Get();	tc := clTextDefault.Get(); img := imgDefault
			END;
			IF img = NIL THEN 
				IF invert3d THEN down := ~down END;
				rect := GetClientRect();
				mode := WMGraphics.ModeSrcOverDst;
				borderWidth := 1;
				CASE style.Get() OF
					|BtnStyleRoundH : WMGraphicUtilities.FillRoundHorizontalBar(canvas, rect, down, mid, mode);
						IF ~isFlat.Get() THEN WMGraphicUtilities.DrawBevel(canvas, WMRectangles.ResizeRect(rect, 0), borderWidth, down, mid, mode) END
					|BtnStyleRoundV : WMGraphicUtilities.FillRoundVerticalBar(canvas, rect, down, mid, mode);
						IF ~isFlat.Get() THEN WMGraphicUtilities.DrawBevel(canvas, WMRectangles.ResizeRect(rect, 0), borderWidth, down, mid, mode) END
					|BtnStyleGlass : IF mid # 0 THEN canvas.Fill(rect, mid, mode) END
					|BtnStyleElevator :
						 IF clDefault.Get() # 0 THEN
						 	WMGraphicUtilities.DrawRect(canvas, WMRectangles.ResizeRect(rect, 0), clDefault.Get(), mode);
(*						 	WMGraphicUtilities.DrawRect(canvas, WMRectangles.ResizeRect(rect, -1), clDefault.Get(), mode);
*)						 	canvas.Fill(WMRectangles.ResizeRect(rect, -3), clDefault.Get(), mode); 
						 END;
						 IF mid # 0 THEN
						 	WMGraphicUtilities.DrawRect(canvas, WMRectangles.ResizeRect(rect, -1), mid, mode);
						 	WMGraphicUtilities.DrawRect(canvas, WMRectangles.ResizeRect(rect, -2), mid, mode)
						 END
					ELSE canvas.Fill(rect, mid, mode);
						IF ~isFlat.Get() THEN WMGraphicUtilities.DrawBevel(canvas, WMRectangles.ResizeRect(rect, 0), borderWidth, down, mid, mode) END
				END;
			ELSE	
				canvas.DrawImage(0, 0, img, WMGraphics.ModeSrcOverDst)
			END;
			IF hasFocus THEN WMGraphicUtilities.DrawRect(canvas, WMRectangles.ResizeRect(rect, -1), 0FF000080H, mode) END;
			IF image # NIL THEN canvas.DrawImage(0, 0, image, WMGraphics.ModeSrcOverDst) END;
			str := caption.Get();
			IF str # NIL THEN
				r := GetClientRect(); 
				IF down THEN 
					IF style.Get() IN {BtnStyleRoundH, BtnStyleRoundV, BtnStyleGlass} THEN 
						WMRectangles.MoveRel(r, 1, 1)
					END
				END;
				canvas.SetColor(tc);
				WMGraphics.DrawStringInRect(canvas, r, FALSE, 1, 1, str^)
			END;
			IF style.Get() = BtnStyleGlass THEN
				IF glassEffect.Get() > 0 THEN
					WMGraphicUtilities.RectGlassShade(canvas, rect, glassEffect.Get(), down)
				END	
			ELSIF style.Get() = BtnStyleElevator THEN
				 (* WMGraphicUtilities.RectGlassShade(canvas, WMRectangles.ResizeRect(rect, - 3), 1, down)	*)
			END;
			Release
		END Draw;
		
		PROCEDURE KeyEvent(ucs : LONGINT; flags : SET; VAR keyCode : LONGINT);
		BEGIN
			IF ~ (AosInputs.Release IN flags) THEN
				IF keyCode = 20H THEN keyboardPressed := TRUE; Down
				(*	pressed := TRUE; keyboardPressed := TRUE; Invalidate *)
				ELSE keyboardPressed := FALSE; Invalidate (* abort *)
				END
			ELSE
				IF pressed THEN
					 Up;keyboardPressed := FALSE 
			(*		pressed := FALSE; keyboardPressed := FALSE; Invalidate *)
				END
			END
		END KeyEvent;
		
		PROCEDURE Click*(sender, par : PTR); (** Eventhandler *) 
		BEGIN
			(* synchronize if not synchronized *)
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Click, sender, par) 
			ELSE
				(* actual business logic *)
				onClick.Call(par)
			END	
		END Click;

	END Button;
	
	(** Scrollbar *)
	Scrollbar* = OBJECT (WMComponents.VisualComponent)
	VAR
		minus, plus, minusPage, plusPage, tracker: Button;
		vertical* : WMProperties.BooleanProperty;
		min*, max*, pos*, pageSize* : WMProperties.Int32Property;
		ts, tp, lx, ly : LONGINT;
		isOverTracker : BOOLEAN;
		onPositionChanged* : EventSource;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(min, PrototypeSmin, NIL, NIL); properties.Add(min);	
			NEW(max, PrototypeSmax,  NIL, NIL); properties.Add(max);	
			NEW(pos, PrototypeSpos, NIL, NIL); properties.Add(pos);	
			NEW(pageSize, PrototypeSpageSize, NIL, NIL); properties.Add(pageSize);	
			NEW(vertical, PrototypeSvertical, NIL, NIL); properties.Add(vertical);	
			NEW(onPositionChanged, SELF, GSonPositionChanged, GSonPositionChangedInfo, SELF.StringToCompCommand);
			events.Add(onPositionChanged);
			pos.SetBounds(min.Get(), max.Get());
			SetNameAsString(StrScrollbar);
			
									
			NEW(minus); NEW(plus); NEW(minusPage); NEW(plusPage); NEW(tracker); 
			minus.takesFocus.Set(FALSE);
			plus.takesFocus.Set(FALSE);
			minusPage.takesFocus.Set(FALSE);
			plusPage.takesFocus.Set(FALSE);
			tracker.takesFocus.Set(FALSE);
			
			SetDirection;
			minus.onClick.Add(DecPos); minus.isRepeating.Set(TRUE); AddContent(minus); 
			plus.onClick.Add(IncPos); plus.isRepeating.Set(TRUE); AddContent(plus); 
			
			AddContent(minusPage); minusPage.onClick.Add(PageUp); 
			minusPage.isFlat.Set(TRUE);
			minusPage.isRepeating.Set(TRUE);
			
			AddContent(plusPage); plusPage.onClick.Add(PageDown); 
			plusPage.isFlat.Set(TRUE);
			plusPage.isRepeating.Set(TRUE);
			
			AddContent(tracker); 
			tracker.SetExtPointerDownHandler(TrackerPointerDown);
			tracker.SetExtPointerMoveHandler(TrackerPointerMove);
			
			isOverTracker := FALSE;
			bounds.SetExtents(16, 16); (* default *)
			takesFocus.Set(FALSE)
		END Init;
		
		PROCEDURE TrackerPointerDown(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		BEGIN
			lx := x; ly := y; handled := TRUE
		END TrackerPointerDown;
		
		PROCEDURE TrackerPointerMove(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		VAR dx, dy, dp, d : LONGINT; f : REAL; tmax, tmin : LONGINT;
		BEGIN
			tmax := max.Get();
			tmin := min.Get();
			IF 0 IN keys THEN 
				dy := y - ly;
				IF vertical.Get() THEN
					d := (bounds.GetHeight() - 2 * bounds.GetWidth());
					IF d > 0 THEN 
						 f := tmax; f := (f - tmin); f := f * dy / d; dp := ENTIER(f);
					ELSE dp := 0
					END;
				ELSE
					dx := x - lx;
					d := (bounds.GetWidth() - 2 * bounds.GetHeight());
					IF d > 0 THEN 
						 f := tmax; f := (f - tmin); f := f * dx / d; dp := ENTIER(f);
					ELSE dp := 0
					END;
				END;
				IF dp # 0 THEN pos.Set(pos.Get() + dp) END
			END;
			handled := TRUE
		END TrackerPointerMove;
				
		PROCEDURE RecacheProperties;
		BEGIN
			RecacheProperties^;
			pos.SetBounds(min.Get(), max.Get()); SetDirection; AlignSubComponents; 
			Invalidate
		END RecacheProperties;
		
		PROCEDURE PropertyChanged*(sender, property : PTR);
		BEGIN
			IF (property = pos) THEN
				AlignSubComponents; Invalidate;
				onPositionChanged.Call(property)	
			ELSIF (property = vertical) THEN SetDirection
			ELSIF (property = min) OR (property = max) OR (property = pageSize) THEN 
				AlignSubComponents; 
				pos.SetBounds(min.Get(), max.Get());
				Invalidate
			ELSE PropertyChanged^(sender, property)
			END;
		END PropertyChanged;
		
		PROCEDURE DecPos*(sender, par : PTR);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.DecPos, sender, par) 
			ELSE pos.Set(pos.Get() - 1)
			END	
		END DecPos;
		
		PROCEDURE IncPos*(sender, par : PTR);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.IncPos, sender, par) 
			ELSE pos.Set(pos.Get() + 1)
			END
		END IncPos;
		
		PROCEDURE PageUp*(sender, par : PTR);
		VAR tpos : LONGINT;
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.PageUp, sender, par) 
			ELSE pos.Set(pos.Get() - pageSize.Get())
			END	
		END PageUp;
		
		PROCEDURE PageDown*(sender, par : PTR);
		VAR tpos : LONGINT;
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.PageDown, sender, par) 
			ELSE pos.Set(pos.Get() + pageSize.Get())
			END
		END PageDown;
		
		PROCEDURE AlignSubComponents*;
		VAR h, w, ps, tmin, tmax : LONGINT;
			f : REAL;
		BEGIN
			Acquire; DisableUpdate;
			(* break a possible endless realignment  *)
			IF aligning THEN EnableUpdate; Release; RETURN END;
			aligning := TRUE; 
			tmin := min.Get(); tmax := max.Get();
			ps := Utilities.Min(tmax - tmin, pageSize.Get());
			IF vertical.Get() THEN
				IF tmax > tmin THEN
					h := (bounds.GetHeight() - 2 * bounds.GetWidth());
					f := ps / (tmax - tmin);
					ts := Utilities.Min(h, Utilities.Max(ENTIER(f * h), 5));
					tp := (pos.Get() - tmin) * (h - ts) DIV (tmax - tmin); 
				ELSE ts := 5; tp := 0;	
				END;
				minus.bounds.SetHeight(bounds.GetWidth()); minusPage.bounds.SetHeight(tp); 
				tracker.bounds.SetHeight(ts); 
				plusPage.bounds.SetHeight(h - tp - ts); plus.bounds.SetHeight(bounds.GetWidth())
			ELSE
				IF tmax > tmin THEN
					w := (bounds.GetWidth() - 2 * bounds.GetHeight());
					f := ps / (tmax - tmin);
					ts := Utilities.Min(w, Utilities.Max(ENTIER(f * w), 5));

					tp := (pos.Get() - tmin) * (w - ts) DIV (tmax - tmin); 
				ELSE ts := 5; tp := 0;	
				END;
				minus.bounds.SetWidth(bounds.GetHeight()); minusPage.bounds.SetWidth(tp); 
				tracker.bounds.SetWidth(ts); 
				plusPage.bounds.SetWidth(w - tp - ts); plus.bounds.SetWidth(bounds.GetHeight())
			END;
			aligning := FALSE; (* must set to false before super call *)
			AlignSubComponents^;
			EnableUpdate;
			Invalidate;
			Release
		END AlignSubComponents;	
	
		PROCEDURE SetDirection;
		BEGIN
			Acquire;
			properties.AcquireWrite; 
			IF vertical.Get() THEN
				minus.alignment.Set(WMComponents.AlignTop); (* minus.style.Set(BtnStyleRoundH); *)
				(*minus.imageName.SetAOC("arrow1ud.bmp"); *)
				minusPage.alignment.Set(WMComponents.AlignTop); minusPage.style.Set(BtnStyleRoundV);
				tracker.alignment.Set(WMComponents.AlignClient); tracker.style.Set(BtnStyleGlass);
				plusPage.alignment.Set(WMComponents.AlignBottom); plusPage.style.Set(BtnStyleRoundV);
				plus.alignment.Set(WMComponents.AlignBottom); (* plus.style.Set(BtnStyleRoundH)*)
(*				plus.imageName.SetAOC("arrow1dd.bmp"); *)
			ELSE
				minus.alignment.Set(WMComponents.AlignLeft); (* minus.style.Set(BtnStyleRoundV); *)
		(*		minus.imageName.SetAOC("arrow1ld.bmp");*)
				minusPage.alignment.Set(WMComponents.AlignLeft); minusPage.style.Set(BtnStyleRoundH);
				tracker.alignment.Set(WMComponents.AlignClient); tracker.style.Set(BtnStyleGlass);
				plusPage.alignment.Set(WMComponents.AlignRight); plusPage.style.Set(BtnStyleRoundH);
				plus.alignment.Set(WMComponents.AlignRight); (* plus.style.Set(BtnStyleRoundV) *)
			(*	plus.imageName.SetAOC("arrow1rd.bmp");*)
			END;
			properties.ReleaseWrite; 
			Release
		END SetDirection;
	
	END Scrollbar;
	Resizer* = OBJECT(WMComponents.VisualComponent)
		VAR dnx, dny : LONGINT;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			SetNameAsString(StrResizer)
		END Init;
		
		PROCEDURE RecacheProperties;
		VAR align: LONGINT;
		BEGIN
			RecacheProperties^;
			align := alignment.Get();
			IF (align = WMComponents.AlignRight) OR (align = WMComponents.AlignLeft) THEN
				SetPointerInfo(manager.pointerLeftRight)
			ELSIF (align = WMComponents.AlignBottom) OR (align = WMComponents.AlignTop) THEN
				SetPointerInfo(manager.pointerUpDown)
			END;
		END RecacheProperties;
		
		PROCEDURE PropertyChanged*(sender, data : PTR);
		BEGIN
			IF (data = properties) OR (data = alignment) THEN RecacheProperties
			ELSE PropertyChanged^(sender, data)
			END;
		END PropertyChanged;
		
		PROCEDURE PointerDown*(x, y: LONGINT; keys: SET); (** PROTECTED *)
		BEGIN 
			dnx := x; dny := y
		END PointerDown;
		
		PROCEDURE PointerMove*(x, y: LONGINT; keys: SET); (** PROTECTED *)
		VAR dx, dy, align, myWidth, myHeight, newL, newR, newT, newB: LONGINT;
			p, pp : WMComponents.VisualComponent;
			parent : XML.Element;
			pRect, ppRect: WMRectangles.Rectangle;
		BEGIN
			RecacheProperties;
			IF 0 IN keys THEN 
				dx := x - dnx; dy := y - dny;
				parent := GetParent();
				IF (parent # NIL) & (parent IS WMComponents.VisualComponent) THEN
					p := parent(WMComponents.VisualComponent);
					parent := p.GetParent();
					IF (parent # NIL) & (parent IS WMComponents.VisualComponent) THEN
						pp := parent(WMComponents.VisualComponent); 
						align := alignment.Get();
						pRect := p.bounds.Get();
						ppRect := pp.bounds.Get();
						myWidth := bounds.GetWidth();
						myHeight := bounds.GetHeight();
						IF align = WMComponents.AlignRight THEN
							newR := pRect.r + dx;
							IF newR > ppRect.r - myWidth THEN
								newR := ppRect.r - myWidth;
							ELSIF newR < pRect.l + myWidth + 1 THEN
								newR := pRect.l + myWidth + 1;
							END;
							pRect.r := newR;
						ELSIF align = WMComponents.AlignLeft THEN
							newL := pRect.l + dx;
							IF newL < ppRect.l + myWidth THEN
								newL := ppRect.l + myWidth;
							ELSIF newL > pRect.r - myWidth THEN
								newL := pRect.r - myWidth;
							END;
							pRect.l := newL;
						ELSIF align = WMComponents.AlignBottom THEN
							newB := pRect.b + dy;
							IF newB > ppRect.b - myHeight THEN
								newB := ppRect.b - myHeight
							ELSIF newB < pRect.t + myHeight THEN
								newB := pRect.t + myHeight
							END;
							pRect.b := newB;
						ELSIF align = WMComponents.AlignTop THEN
							newT := pRect.t + dy;
							IF newT > pRect.b - myHeight THEN
								newT := pRect.b - myHeight
							ELSIF newT < ppRect.t + myHeight THEN
								newT := ppRect.t + myHeight
							END;
							pRect.t := newT;
						END;
						p.bounds.Set(pRect);
					END
				END
			END
		END PointerMove;
		
		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		BEGIN
			DrawBackground^(canvas);
			WMGraphicUtilities.RectGlassShade(canvas, GetClientRect(), 2, FALSE)
		END DrawBackground;
		
	END Resizer;
		
VAR manager : WMWindowManager.WindowManager;

VAR (* global strings *)
	GSonTimer, GSonTimerInfo, GSStart, GSStartTimerInfo, GSStop, GSStopTimerInfo : String;
	GSRun, GSRunSystemCommandInfo, GSCallEventInfo : String;
	GSonClick, GSonClickButtonInfo : String;
	GSonPositionChanged, GSonPositionChangedInfo : String;
	
VAR
	 PrototypeInterval* : WMProperties.Int32Property;
	 PrototypeCommandString*, PrototypeCaption* : WMProperties.StringProperty;
	 PrototypeTextColor*: WMProperties.ColorProperty;
	 PrototypeAlignH*: WMProperties.Int32Property;
	 PrototypeAlignV*: WMProperties.Int32Property;
	 ButtonBoundsProto : WMProperties.RectangleProperty;
	 PrototypeBclDefault*, PrototypeBclHover*, PrototypeBclPressed*, PrototypeBclTextDefault*, 
	 PrototypeBclTextHover*, PrototypeBclTextPressed* : WMProperties.ColorProperty; 
	 PrototypeBisRepeating*, PrototypeBisToggle*, PrototypeBisFlat* : WMProperties.BooleanProperty;
	 PrototypeBcaption*, PrototypeBonClickHandler* : WMProperties.StringProperty;
	 PrototypeBimgDefaultName*, PrototypeBimgHoverName*, PrototypeBimgPressedName*, PrototypeBimageName* : WMProperties.StringProperty;
	 PrototypeBfontHeight*, PrototypeBstyle*, PrototypeBglassEffect : WMProperties.Int32Property;
	 PrototypeSvertical* : WMProperties.BooleanProperty; 
	 PrototypeSmin*, PrototypeSmax*, PrototypeSpos*, PrototypeSpageSize* : WMProperties.Int32Property;
	 
	 StrTimer*, StrSystemCommand*, StrEvent*, StrPanel*, StrLabel*, StrButton*, StrScrollbar*, StrResizer* : String;
	 
PROCEDURE InitStrings;
BEGIN
	GSonTimer := NewString("onTimer"); GSonTimerInfo := NewString("generates an event if the timer runs out");
	GSStart := NewString("Start"); GSStartTimerInfo := NewString("start the timer");
	GSStop := NewString("Stop"); GSStopTimerInfo := NewString("stop the timer");
	GSRun := NewString("Run");
	
	GSRunSystemCommandInfo := NewString("run the system command specified in commandString");
	GSCallEventInfo := NewString("call the event listener specified in commandString");
	
	GSonClick := NewString("onClick"); GSonClickButtonInfo := NewString("generates an event if the button is clicked"); 
	GSonPositionChanged := NewString("onPositionChanged"); 
	GSonPositionChangedInfo := NewString("generates an event if the position is changed");
	
	StrTimer := NewString("Timer");
	StrSystemCommand := NewString("SystemCommand"); 
	StrEvent := NewString("Event"); 
	StrPanel := NewString("Panel"); 
	StrLabel := NewString("Label"); 
	StrButton := NewString("Button"); 
	StrScrollbar := NewString("Scrollbar");
	StrResizer := NewString("Resizer");

END InitStrings;
	 
PROCEDURE InitPrototypes;
VAR plTimer, plLabel, plButton : WMProperties.PropertyList;
BEGIN
	(* Timer properties *)
	NEW(plTimer);
	NEW(PrototypeInterval, NIL, NewString("interval"),  NewString("time between two timer ticks in ms"));
	PrototypeInterval.Set(100);
	plTimer.Add(PrototypeInterval);
	WMComponents.propertyListList.Add("Timer", plTimer);
	(* SystemCommand properties *)
	NEW(PrototypeCommandString, NIL, NewString("CommandString"), 
		NewString("command to be executed uppon call to Run"));
	(* Label properties *)
	NEW(plLabel);
	NEW(PrototypeCaption, NIL, NewString("Caption"), NewString("caption text"));
	plLabel.Add(PrototypeCaption);
	NEW(PrototypeTextColor, NIL, NewString("TextColor"), NewString("text color"));
	plLabel.Add(PrototypeTextColor);
	NEW(PrototypeAlignH, NIL, NewString("AlignH"), NewString("horizontal alignment"));
	PrototypeAlignH.Set(WMGraphics.AlignLeft);
	plLabel.Add(PrototypeAlignH);
	NEW(PrototypeAlignV, NIL, NewString("AlignV"), NewString("vertical alignment"));
	PrototypeAlignV.Set(WMGraphics.AlignCenter);
	plLabel.Add(PrototypeAlignV);	
	WMComponents.propertyListList.Add("Label", plLabel);
	(* Button properties *)
	NEW(plButton);
	NEW(ButtonBoundsProto, WMComponents.PrototypeBounds, NIL, NIL); 
	ButtonBoundsProto.Set(WMRectangles.MakeRect(0,0, 50, 20));
	plButton.Add(ButtonBoundsProto);
	NEW(PrototypeBonClickHandler, NIL, NewString("OnClickHandler"), NewString("handler"));
	plButton.Add(PrototypeBonClickHandler);
	NEW(PrototypeBclDefault, NIL, NewString("ClDefault"), NewString("default color of the button"));
	plButton.Add(PrototypeBclDefault);
	NEW(PrototypeBclHover, NIL, NewString("ClHover"), NewString("color of the button if the mouse is over it"));
	plButton.Add(PrototypeBclHover);
	NEW(PrototypeBclPressed, NIL, NewString("ClPressed"), NewString("color of the button if it is pressed"));
	plButton.Add(PrototypeBclPressed);
	NEW(PrototypeBclTextDefault, NIL, NewString("ClTextDefault"), NewString("default text color of the button"));
	plButton.Add(PrototypeBclTextDefault);
	NEW(PrototypeBclTextHover, NIL, NewString("ClTextHover"), NewString("text color of the button if the mouse is over it"));
	plButton.Add(PrototypeBclTextHover);
	NEW(PrototypeBclTextPressed, NIL, NewString("ClTextPressed"), NewString("text color of the button if it is pressed"));
	plButton.Add(PrototypeBclTextPressed);
	NEW(PrototypeBfontHeight, NIL, NewString("FontHeight"), NewString("height of the button text"));
	plButton.Add(PrototypeBfontHeight);
	NEW(PrototypeBisRepeating, NIL, NewString("IsRepeating"), NewString("defines if the button repeats sending click events while being pressed down"));
	plButton.Add(PrototypeBisRepeating);
	NEW(PrototypeBisToggle, NIL, NewString("IsToggle"), NewString("defines if the button is a toggle button"));
	plButton.Add(PrototypeBisToggle);
	NEW(PrototypeBisFlat, NIL, NewString("IsFlat"), NewString("defines if the button has a flat look"));
	plButton.Add(PrototypeBisFlat);
	NEW(PrototypeBcaption, NIL, NewString("Caption"), NewString("defines the button text"));
	plButton.Add(PrototypeBcaption);
	WMComponents.propertyListList.Add("Button", plButton);

	NEW(PrototypeBstyle, NIL, NewString("Style"), NewString("style number"));
	plButton.Add(PrototypeBstyle);
	NEW(PrototypeBglassEffect, NIL, NewString("GlassEffect"), NewString("size of glass effect"));
	plButton.Add(PrototypeBglassEffect); PrototypeBglassEffect.Set(5);
		
	PrototypeBclDefault.Set(0F0F0FF50H);
	PrototypeBclHover.Set(0EEEE0050H);
	PrototypeBclPressed.Set(0F0F0FF50H);
	PrototypeBclTextDefault.Set(0EEEEEEFFH);
	PrototypeBclTextHover.Set(0EEEEEEFFH);
	PrototypeBclTextPressed.Set(00FFFFH);
	PrototypeBfontHeight.Set(12);	
	PrototypeBstyle.Set(BtnStyleElevator);
	(* Scrollbar properties *)
	NEW(PrototypeSvertical, NIL, NewString("Vertical"), 
		NewString("defines if the scrollbar is vertical"));
	NEW(PrototypeSmin, NIL, NewString("Min"), 
		NewString("defines the scrollbar min position"));
	NEW(PrototypeSmax, NIL, NewString("Max"), 
		NewString("defines the scrollbar max position"));
	NEW(PrototypeSpos, NIL, NewString("Pos"), 
		NewString("defines the scrollbar position"));
	NEW(PrototypeSpageSize, NIL, NewString("PageSize"), 
		NewString("defines the scrollbar page size"));
	PrototypeSvertical.Set(TRUE);
	PrototypeSmax.Set(100);
	PrototypeSpageSize.Set(20);
	WMComponents.propertyListList.UpdateStyle
END InitPrototypes;

PROCEDURE HexToIntDef(str : ARRAY OF CHAR; default : LONGINT) : LONGINT;
VAR value, res : LONGINT;
BEGIN
	Utilities.HexStrToInt(str, value, res); IF res # Utilities.Ok THEN value := default END; RETURN value
END HexToIntDef;
	
(**  Generators  *********************************************************************************)
PROCEDURE GenTimer*(par : PTR) : PTR;
VAR timer : Timer;
BEGIN NEW(timer); RETURN timer
END GenTimer;

PROCEDURE GenSystemCommand*(par : PTR) : PTR;
VAR systemCommand : SystemCommand;
BEGIN NEW(systemCommand); RETURN systemCommand
END GenSystemCommand;

PROCEDURE GenEvent*(par : PTR) : PTR;
VAR event : Event;
BEGIN NEW(event); RETURN event
END GenEvent;

(*PROCEDURE GenAssign*(par : PTR) : PTR;
VAR assign : Assign;
BEGIN NEW(assign); RETURN assign
END GenAssign;

PROCEDURE GenBatch*(par : PTR) : PTR;
VAR batch : Batch;
BEGIN NEW(batch); RETURN batch
END GenBatch;

PROCEDURE GenPiepser*(par : PTR) : PTR;
VAR piepser : Piepser;
BEGIN NEW(piepser); RETURN piepser
END GenPiepser;
*)
PROCEDURE GenPanel*(par : PTR) : PTR;
VAR panel : Panel;
BEGIN NEW(panel); RETURN panel
END GenPanel;

PROCEDURE GenLabel*(par : PTR) : PTR;
VAR label : Label;
BEGIN NEW(label); RETURN label
END GenLabel;

PROCEDURE GenButton*(par : PTR) : PTR;
VAR button : Button;
BEGIN NEW(button); RETURN button
END GenButton;

PROCEDURE GenScrollbar*(par : PTR) : PTR;
VAR scrollbar : Scrollbar;
BEGIN NEW(scrollbar); RETURN scrollbar
END GenScrollbar;

PROCEDURE GenResizer*(par : PTR) : PTR;
VAR resizer : Resizer;
BEGIN NEW(resizer); RETURN resizer
END GenResizer;
(**********************************************************************************************)

(* Register generator procedures *)
PROCEDURE Register;
BEGIN
	WMComponents.registry.RegisterElement("Timer", GenTimer);
	WMComponents.registry.RegisterElement("SystemCommand", GenSystemCommand);
	WMComponents.registry.RegisterElement("Event", GenEvent);
(*	WMComponents.registry.RegisterElement("Assign", GenAssign);
	WMComponents.registry.RegisterElement("Batch", GenBatch);
	WMComponents.registry.RegisterElement("Piepser", GenPiepser);*)
	WMComponents.registry.RegisterElement("Panel", GenPanel);
	WMComponents.registry.RegisterElement("Label", GenLabel);
	WMComponents.registry.RegisterElement("Button", GenButton);
	WMComponents.registry.RegisterElement("Scrollbar", GenScrollbar);
	WMComponents.registry.RegisterElement("Resizer", GenResizer)
END Register;

(* Cleanup on module free *)
PROCEDURE Cleanup;
BEGIN
	WMComponents.registry.UnregisterElement("Timer");
	WMComponents.registry.UnregisterElement("SystemCommand");
	WMComponents.registry.UnregisterElement("Event");
	WMComponents.registry.UnregisterElement("Assign");
	WMComponents.registry.UnregisterElement("Batch");
	WMComponents.registry.UnregisterElement("Piepser");
	WMComponents.registry.UnregisterElement("Panel");
	WMComponents.registry.UnregisterElement("Label");
	WMComponents.registry.UnregisterElement("Button");
	WMComponents.registry.UnregisterElement("Scrollbar");
	WMComponents.registry.UnregisterElement("Resizer")
END Cleanup;

PROCEDURE NewString*(x : ARRAY OF CHAR) : String;
VAR t : String;
BEGIN
	NEW(t, LEN(x)); COPY(x, t^); RETURN t
END NewString;

BEGIN
	manager := WMWindowManager.GetDefaultManager();
	InitStrings;
	InitPrototypes;
	Register;
	AosModules.InstallTermHandler(Cleanup)
END WMStandardComponents.

