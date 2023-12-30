MODULE WMStandardComponents;	(** AUTHOR "TF"; PURPOSE "Standard components"; *)
(**
 *
 * History:
 *
 *	20.06.2006	Button.Down always calls Click for toggle button, added Button.GetPressed, buttons don't take the keyboard focus per default (staubesv)
 *	20.07.2006	Added GroupPanel.textColor property (staubesv)
 *	12.03.2007	Invalidate Checkbox when state property changes (staubesv)
 *)

IMPORT
	AosOut, AosModules, AosKernel, AosCommands, WMComponents, Utilities,
	WMGraphics, WMGraphicUtilities, WMRectangles,
	WMEvents, XML, AosInputs, WMProperties, WMWindowManager;

TYPE
	(* Local type-alias for convenience *)
	String = Utilities.String;
	EventSource = WMEvents.EventSource;
	EventListener = WMEvents.EventListener ;
	EventListenerInfo = WMEvents.EventListenerInfo;
	Canvas = WMGraphics.Canvas;

	(** Timer *)	
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
		VAR execute : String;
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
		isRepeating-, isToggle-, isHorizontal-, repeatMiddleImg-, useBgBitmaps- : WMProperties.BooleanProperty;
		glassEffect- : WMProperties.Int32Property;
		caption-, onClickHandler-: WMProperties.StringProperty;
			(* single images *)
		imgDefaultName-, imgHoverName-, imgPressedName-, imageName- : WMProperties.StringProperty;
		imgDefault, imgHover, imgPressed : WMGraphics.Image;
		 	(* 3 x 3 background images for horizontal representation *)
	 	imgDefaultNameLeft*, imgDefaultNameRight*, imgDefaultNameMiddle*,
	 	imgHoverNameLeft*, imgHoverNameRight*, imgHoverNameMiddle*,
	 	imgPressedNameLeft*, imgPressedNameRight*, imgPressedNameMiddle* : WMProperties.StringProperty;
	 	imgDefaultLeft, imgDefaultRight, imgDefaultMiddle,
	 	imgHoverLeft, imgHoverRight, imgHoverMiddle,
	 	imgPressedLeft, imgPressedRight, imgPressedMiddle : WMGraphics.Image;
 		 	(* 3 x 2 background images for vertical representation *)
	 	imgDefaultNameTop*, imgDefaultNameBottom*,
	 	imgHoverNameTop*, imgHoverNameBottom*,
	 	imgPressedNameTop*, imgPressedNameBottom* : WMProperties.StringProperty;
	 	imgDefaultTop, imgDefaultBottom,
	 	imgHoverTop, imgHoverBottom,
	 	imgPressedTop, imgPressedBottom : WMGraphics.Image;
		 	(* foreground image *)
	 	image : WMGraphics.Image;
		pressed, keyboardPressed, mouseOver: BOOLEAN;
		onClick* : EventSource;
		handler : WMEvents.EventListener;
		invert3d : BOOLEAN;
		repeater : Timer;
		userData* : PTR;
		font : WMGraphics.Font;
	
		PROCEDURE &Init;
		BEGIN
			Init^;
			(* behavior *)
			NEW(isRepeating, PrototypeBisRepeating, NIL, NIL); properties.Add(isRepeating);	
			NEW(isToggle, PrototypeBisToggle, NIL, NIL); properties.Add(isToggle);	
			NEW(onClickHandler, PrototypeBonClickHandler, NIL, NIL); properties.Add(onClickHandler);
			(* look *)
			NEW(isHorizontal, PrototypeBIsHorizontal, NIL, NIL); properties.Add(isHorizontal);
			bounds.SetPrototype(PrototypeBBounds); (* override the defaults *)
			NEW(clDefault, PrototypeBclDefault, NIL, NIL); properties.Add(clDefault);
			NEW(clHover, PrototypeBclHover, NIL, NIL); properties.Add(clHover);
			NEW(clPressed, PrototypeBclPressed, NIL, NIL); properties.Add(clPressed);
			NEW(clTextDefault, PrototypeBclTextDefault, NIL, NIL); properties.Add(clTextDefault);
			NEW(clTextHover, PrototypeBclTextHover, NIL, NIL); properties.Add(clTextHover);
			NEW(clTextPressed, PrototypeBclTextPressed,  NIL, NIL); properties.Add(clTextPressed);
			NEW(fontHeight, PrototypeBfontHeight, NIL, NIL); properties.Add(fontHeight);	
			NEW(caption, PrototypeBcaption, NIL, NIL); properties.Add(caption);
			NEW(glassEffect, PrototypeBglassEffect, NIL, NIL); properties.Add(glassEffect);
				(* --- *)
			NEW(imgDefaultName, PrototypeBimgDefaultName, NIL, NIL); properties.Add(imgDefaultName);
			NEW(imgHoverName, PrototypeBimgHoverName, NIL, NIL); properties.Add(imgHoverName);
			NEW(imgPressedName, PrototypeBimgPressedName, NIL, NIL); properties.Add(imgPressedName);
			NEW(imageName, PrototypeBimageName, NIL, NIL); properties.Add(imageName);
				(* --- *)
			NEW(useBgBitmaps, PrototypeBUseBgImages, NIL, NIL); properties.Add(useBgBitmaps);
			NEW(repeatMiddleImg, PrototypeBRepeatMiddleImg, NIL, NIL); properties.Add(repeatMiddleImg);
				(* --- *)
			NEW(imgDefaultNameLeft, PrototypeImgDefaultNameLeft, NIL, NIL); properties.Add(imgDefaultNameLeft);
		 	NEW(imgDefaultNameRight, PrototypeImgDefaultNameRight, NIL, NIL); properties.Add(imgDefaultNameRight);
		 	NEW(imgDefaultNameMiddle, PrototypeImgDefaultNameMiddle, NIL, NIL); properties.Add(imgDefaultNameMiddle);
			NEW(imgHoverNameLeft, PrototypeImgHoverNameLeft, NIL, NIL); properties.Add(imgHoverNameLeft);
		 	NEW(imgHoverNameRight, PrototypeImgHoverNameRight, NIL, NIL); properties.Add(imgHoverNameRight);
		 	NEW(imgHoverNameMiddle, PrototypeImgHoverNameMiddle, NIL, NIL); properties.Add(imgHoverNameMiddle);
			NEW(imgPressedNameLeft, PrototypeImgPressedNameLeft, NIL, NIL); properties.Add(imgPressedNameLeft);
		 	NEW(imgPressedNameRight, PrototypeImgPressedNameRight, NIL, NIL); properties.Add(imgPressedNameRight);
		 	NEW(imgPressedNameMiddle, PrototypeImgPressedNameMiddle, NIL, NIL); properties.Add(imgPressedNameMiddle);
 				(* --- *)
			NEW(imgDefaultNameTop, NIL, NIL, NIL); properties.Add(imgDefaultNameTop);
		 	NEW(imgDefaultNameBottom, NIL, NIL, NIL); properties.Add(imgDefaultNameBottom);
			NEW(imgHoverNameTop, NIL, NIL, NIL); properties.Add(imgHoverNameTop);
		 	NEW(imgHoverNameBottom, NIL, NIL, NIL); properties.Add(imgHoverNameBottom);
			NEW(imgPressedNameTop, NIL, NIL, NIL); properties.Add(imgPressedNameTop);
		 	NEW(imgPressedNameBottom, NIL, NIL, NIL); properties.Add(imgPressedNameBottom);

			(* events *)
			NEW(onClick, SELF, GSonClick, GSonClickButtonInfo, SELF.StringToCompCommand); events.Add(onClick);
			SetNameAsString(StrButton);
			SELF.font := WMGraphics.GetDefaultFont();
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
			s := imageName.Get(); IF s # NIL THEN image := WMGraphics.LoadImage(s^, TRUE) END;
			(* --- *)
			s := imgDefaultNameLeft.Get();		IF s # NIL THEN imgDefaultLeft		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgDefaultNameRight.Get();		IF s # NIL THEN imgDefaultRight		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgDefaultNameMiddle.Get();	IF s # NIL THEN imgDefaultMiddle	:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgHoverNameLeft.Get();		IF s # NIL THEN imgHoverLeft		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgHoverNameRight.Get();		IF s # NIL THEN imgHoverRight		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgHoverNameMiddle.Get();		IF s # NIL THEN imgHoverMiddle		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgPressedNameLeft.Get();		IF s # NIL THEN imgPressedLeft		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgPressedNameRight.Get();		IF s # NIL THEN imgPressedRight		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgPressedNameMiddle.Get();	IF s # NIL THEN imgPressedMiddle	:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgDefaultNameTop.Get();		IF s # NIL THEN imgDefaultTop		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgDefaultNameBottom.Get();	IF s # NIL THEN imgDefaultBottom	:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgHoverNameTop.Get();		IF s # NIL THEN imgHoverTop			:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgHoverNameBottom.Get();	IF s # NIL THEN imgHoverBottom		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgPressedNameTop.Get();		IF s # NIL THEN imgPressedTop		:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgPressedNameBottom.Get();	IF s # NIL THEN imgPressedBottom	:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgHoverName.Get();			IF s # NIL THEN imgHover			:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgPressedName.Get();			IF s # NIL THEN imgPressed			:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgDefaultName.Get();			IF s # NIL THEN imgDefault			:= WMGraphics.LoadImage(s^, TRUE) END;			
			CheckClickHandler;
			Invalidate	
		END RecacheProperties;
		
		PROCEDURE PropertyChanged*(sender, data : PTR);
		BEGIN
			IF data = onClickHandler THEN CheckClickHandler
(*			ELSIF (data = imageName) OR (data = useBgBitmaps) 
				OR (data = imgDefaultNameLeft) OR (data = imgDefaultNameMiddle) OR (data = imgDefaultNameRight)
				OR (data = imgHoverNameLeft) OR (data = imgHoverNameMiddle) OR (data = imgHoverNameRight)
				OR (data = imgPressedNameLeft) OR (data = imgPressedNameMiddle) OR (data = imgPressedNameRight) 
				OR (data = imgDefaultNameTop) OR (data = imgDefaultNameBottom)
				OR (data = imgHoverNameTop) OR (data = imgHoverNameBottom)
				OR (data = imgPressedNameTop) OR (data = imgPressedNameBottom)
				OR (data = imgDefaultName) OR (data = imgPressedName)
				OR (data = imgHoverName) THEN
					RecacheProperties; Invalidate*)
			ELSIF (data = caption) THEN Invalidate
			ELSIF data = fontHeight THEN SELF.font.size := SELF.fontHeight.Get(); Invalidate
			ELSE PropertyChanged^(sender, data); RecacheProperties; Invalidate
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
		
		PROCEDURE GetPressed*() : BOOLEAN;
		BEGIN
			RETURN pressed;
		END GetPressed;
		
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
			IF ~isToggle.Get() THEN 
				IF ~pressed THEN pressed := TRUE; Invalidate; CheckRepeating(TRUE) END;
			ELSE 
				pressed := ~pressed; Click(SELF, userData); Invalidate;
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
			IF enabled.Get() THEN Down END;
			PointerDown^(x, y, keys)
		END PointerDown;
		
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET); (** PROTECTED *)
		BEGIN
			IF enabled.Get() THEN
				IF IsHit(x, y) THEN 
					IF ~mouseOver THEN mouseOver := TRUE; IF pressed THEN CheckRepeating(TRUE) END; Invalidate END
				ELSE 	
					IF mouseOver THEN mouseOver := FALSE; IF pressed THEN CheckRepeating(FALSE) END; Invalidate END
				END
			ELSE mouseOver := FALSE
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

		PROCEDURE IsHit(x, y: LONGINT) : BOOLEAN;
		VAR t : BOOLEAN;
		BEGIN
			IF ~visible.Get() THEN RETURN FALSE END;
			Acquire;
			t := WMRectangles.PointInRect(x, y, GetClientRect());
			IF useBgBitmaps.Get() THEN
				IF isHorizontal.Get() THEN
					t := t & IsHitHorizontal(x, y)
				ELSE
					t := t & IsHitVertical(x, y)
				END
			END;
			Release;
			RETURN t
		END IsHit;

 		PROCEDURE IsHitHorizontal(x, y: LONGINT) : BOOLEAN;
 		VAR a, b, c : WMGraphics.Image; aw, bw, cw : LONGINT;
 		BEGIN
			IF imgDefault # NIL THEN
				RETURN WMGraphics.IsBitmapHit(x, y, 64, imgDefault)
			ELSE
	 			GetHorizontalImages(a, b, c);
		 		IF a # NIL THEN aw := a.width ELSE aw := 0 END;
		 		IF c # NIL THEN cw := c.width ELSE cw := 0 END;
		 		bw := bounds.GetWidth() - aw - cw;
		 		IF x < aw THEN
		 			y := y * a.height DIV bounds.GetHeight();
	 				RETURN WMGraphics.IsBitmapHit(x, y, 64, a)
		 		ELSIF x > bounds.GetWidth() - cw THEN
		 			y := y * c.height DIV bounds.GetHeight();
	 				RETURN WMGraphics.IsBitmapHit(x-aw-bw, y, 64, c)
		 		ELSE (* middle image *)
		 			IF b = NIL THEN RETURN FALSE END; (* no image loaded, so the button cannot be hit *)
		 			y := y * b.height DIV bounds.GetHeight();
		 			IF repeatMiddleImg.Get() THEN
		 				RETURN WMGraphics.IsBitmapHit((x-aw) MOD b.width, y, 64, b)
		 			ELSE
			 			RETURN WMGraphics.IsBitmapHit((x-aw) * b.width DIV bw, y, 64, b)
		 			END
				END
			END
 		END IsHitHorizontal;
 		
 		PROCEDURE IsHitVertical(x, y: LONGINT) : BOOLEAN;
 		VAR a, b, c : WMGraphics.Image; ah, bh, ch : LONGINT;
 		BEGIN
 			GetVerticalImages(a, b, c);
	 		IF a # NIL THEN ah := a.height ELSE ah := 0 END;
	 		IF c # NIL THEN ch := c.height ELSE ch := 0 END;
	 		bh := bounds.GetHeight() - ah - ch;
	 		IF y < ah THEN
	 			x := x * a.width DIV bounds.GetWidth();
 				RETURN WMGraphics.IsBitmapHit(x, y, 64, a)
	 		ELSIF y > bounds.GetHeight() - ch THEN
	 			x := x * c.width DIV bounds.GetWidth();
 				RETURN WMGraphics.IsBitmapHit(x, y-ah-bh, 64, c)
	 		ELSE (* middle image *)
	 			IF b = NIL THEN RETURN FALSE END; (* no image loaded, so the button cannot be hit *)
	 			x := x * b.width DIV bounds.GetWidth();
	 			IF repeatMiddleImg.Get() THEN
	 				RETURN WMGraphics.IsBitmapHit(x, (y-ah) MOD b.height, 64, b)
	 			ELSE
		 			RETURN WMGraphics.IsBitmapHit(x, (y-ah) * b.height DIV bh, 64, b)
	 			END
			END
 		END IsHitVertical; 
 			
 		(* load images appropriate to the actual state of the button. a: left, b: middle, c: right *)
 		PROCEDURE GetHorizontalImages(VAR a, b, c : WMGraphics.Image);
 		VAR down : BOOLEAN;
 		BEGIN
 			down := pressed & (mouseOver OR isToggle.Get() OR keyboardPressed);
			IF down THEN
				IF imgPressedMiddle # NIL THEN
					a := imgPressedLeft; b := imgPressedMiddle; c := imgPressedRight; RETURN
				ELSIF imgHoverMiddle # NIL THEN
					a := imgHoverLeft; b := imgHoverMiddle; c := imgHoverRight; RETURN
				ELSE
					a := imgDefaultLeft; b := imgDefaultMiddle; c := imgDefaultRight; RETURN
				END
			ELSIF mouseOver THEN
				IF imgHoverMiddle # NIL THEN
					a := imgHoverLeft; b := imgHoverMiddle; c := imgHoverRight; RETURN
				ELSE
					a := imgDefaultLeft; b := imgDefaultMiddle; c := imgDefaultRight; RETURN
				END
			ELSE
				a := imgDefaultLeft; b := imgDefaultMiddle; c := imgDefaultRight; RETURN
			END
 		END GetHorizontalImages;
 		
 		(* load images appropriate to the actual state of the button. a: top, b: middle, c: bottom *)
 		PROCEDURE GetVerticalImages(VAR a, b, c : WMGraphics.Image);
 		VAR down : BOOLEAN;
 		BEGIN
 			down := pressed & (mouseOver OR isToggle.Get() OR keyboardPressed);
			IF down THEN
				IF imgPressedMiddle # NIL THEN
					a := imgPressedTop; b := imgPressedMiddle; c := imgPressedBottom; RETURN
				ELSIF imgHoverMiddle # NIL THEN
					a := imgHoverTop; b := imgHoverMiddle; c := imgHoverBottom; RETURN
				ELSE
					a := imgDefaultTop; b := imgDefaultMiddle; c := imgDefaultBottom; RETURN
				END
			ELSIF mouseOver THEN
				IF imgHoverMiddle # NIL THEN
					a := imgHoverTop; b := imgHoverMiddle; c := imgHoverBottom; RETURN
				ELSE
					a := imgDefaultTop; b := imgDefaultMiddle; c := imgDefaultBottom; RETURN
				END
			ELSE
				a := imgDefaultTop; b := imgDefaultMiddle; c:= imgDefaultBottom; RETURN
			END
 		END GetVerticalImages;
		
		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR mode, mid, borderWidth : LONGINT;
			 tc : WMGraphics.Color; r, rect : WMGraphics.Rectangle; down : BOOLEAN;
			 str : String;
		BEGIN
			IF ~visible.Get() THEN RETURN END;
			Acquire;
			down := pressed & (mouseOver OR isToggle.Get() OR keyboardPressed);
			IF down THEN mid := clPressed.Get(); tc := clTextPressed.Get()
			ELSIF mouseOver THEN 	mid := clHover.Get(); tc := clTextHover.Get()
			ELSE mid := clDefault.Get();	tc := clTextDefault.Get()	END;
			IF useBgBitmaps.Get() THEN
				IF isHorizontal.Get() THEN
					DrawHorizontalBackground(canvas)
				ELSE
					DrawVerticalBackground(canvas)
				END
			ELSE
				IF invert3d THEN down := ~down END;
				rect := GetClientRect();
				mode := WMGraphics.ModeSrcOverDst;
				borderWidth := 1;
				IF mid # 0 THEN canvas.Fill(rect, mid, mode) END;
				IF SELF.glassEffect.Get() > 0 THEN WMGraphicUtilities.RectGlassShade(canvas, rect, SELF.glassEffect.Get(), down) END
			END;
			(* focus *)
			IF hasFocus THEN WMGraphicUtilities.DrawRect(canvas, WMRectangles.ResizeRect(rect, -1), 0FF000080H, mode) END;
			(* foreground *)
			IF image # NIL THEN canvas.DrawImage(0, 0, image, WMGraphics.ModeSrcOverDst) END;
			str := caption.Get();
			IF str # NIL THEN
				r := GetClientRect(); 
				canvas.SetColor(tc);
				canvas.SetFont(SELF.font);
				WMGraphics.DrawStringInRect(canvas, r, FALSE, 1, 1, str^)
			END;
			Release
		END DrawBackground;
		
		PROCEDURE DrawHorizontalBackground(canvas : WMGraphics.Canvas);
		VAR imgLeft, imgMiddle, imgRight, img : WMGraphics.Image;
			 wLeft, wRight : LONGINT;
			 down : BOOLEAN;
		BEGIN
			IF imgDefault # NIL THEN
				down := pressed & (mouseOver OR isToggle.Get() OR keyboardPressed);
				IF down & (imgPressed # NIL) THEN
					img := imgPressed
				ELSIF mouseOver & (imgHover # NIL) THEN
					img := imgHover
				ELSE		
					img := imgDefault
				END;
				canvas.ScaleImage(	img,
				 	WMRectangles.MakeRect(0, 0, img.width, img.height),
					WMRectangles.MakeRect(0, 0, bounds.GetWidth(), bounds.GetHeight()), 
					WMGraphics.ModeSrcOverDst, 10)				
			ELSE
				GetHorizontalImages(imgLeft, imgMiddle, imgRight);
		 		(* left *)
		 		IF imgLeft # NIL THEN
					wLeft := imgLeft.width;
					canvas.ScaleImage(	imgLeft,
					 	WMRectangles.MakeRect(0, 0, imgLeft.width, imgLeft.height),
						WMRectangles.MakeRect(0, 0, imgLeft.width, bounds.GetHeight()), 
						WMGraphics.ModeSrcOverDst, 10)
				ELSE
					wLeft := 0
				END;
				(* right *)
				IF imgRight # NIL THEN
					wRight := imgRight.width;
					canvas.ScaleImage(	imgRight,
					 	WMRectangles.MakeRect(0, 0, imgRight.width, imgRight.height),
						WMRectangles.MakeRect(bounds.GetWidth()-wRight, 0, bounds.GetWidth(), bounds.GetHeight()), 
						WMGraphics.ModeSrcOverDst, 10) 
				ELSE
					wRight := 0
				END;
				(* middle *)
				IF imgMiddle # NIL THEN
					IF SELF.repeatMiddleImg.Get() THEN (* repeat image *)
						WMGraphicUtilities.RepeatImageHorizontal(canvas, wLeft , 0, bounds.GetWidth()-wLeft-wRight, bounds.GetHeight(), imgMiddle)
					ELSE (* scale image *) 
						canvas.ScaleImage(	imgMiddle,
								 	WMRectangles.MakeRect(0, 0, imgMiddle.width, imgMiddle.height),
									WMRectangles.MakeRect(wLeft, 0, bounds.GetWidth()-wRight, bounds.GetHeight()), WMGraphics.ModeSrcOverDst, 10) 
					END
				END
			END	
		END DrawHorizontalBackground;
		
		PROCEDURE DrawVerticalBackground(canvas : WMGraphics.Canvas);
		VAR imgMiddle, imgTop, imgBottom : WMGraphics.Image;
			 hTop, hBottom : LONGINT;
		BEGIN
			GetVerticalImages(imgTop, imgMiddle, imgBottom);
	 		(* top*)
			IF imgTop # NIL THEN
				hTop := imgTop.height;
				canvas.ScaleImage(	imgTop,
				 	WMRectangles.MakeRect(0, 0, imgTop.width, imgTop.height),
					WMRectangles.MakeRect(0, 0, bounds.GetWidth(), imgTop.height), 
					WMGraphics.ModeSrcOverDst, 10)
			ELSE
				hTop := 0
			END;
			(* bottom*)
			IF imgBottom # NIL THEN
				hBottom := imgBottom.height;
				canvas.ScaleImage(	imgBottom,
				 	WMRectangles.MakeRect(0, 0, imgBottom.width, imgBottom.height),
					WMRectangles.MakeRect(0, bounds.GetHeight()-hBottom, bounds.GetWidth(), bounds.GetHeight()), 
					WMGraphics.ModeSrcOverDst, 10) 
			ELSE
				hBottom := 0
			END;
			(* middle *)
			IF imgMiddle # NIL THEN
				IF SELF.repeatMiddleImg.Get() THEN (* repeat image *)
					WMGraphicUtilities.RepeatImageVertical(canvas, 0, hTop, bounds.GetWidth(), bounds.GetHeight()-hTop-hBottom, imgMiddle)
				ELSE (* scale image *) 
					canvas.ScaleImage(	imgMiddle,
							 	WMRectangles.MakeRect(0, 0, imgMiddle.width, imgMiddle.height),
								WMRectangles.MakeRect(0, hTop, bounds.GetWidth(), bounds.GetHeight()-hBottom), WMGraphics.ModeSrcOverDst, 10) 
				END
			END
		END DrawVerticalBackground;
		
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
		minusPage, plusPage, tracker, arrowLeft, arrowRight, arrowUp, arrowDown: Button;
		vertical*, useArrowImages*, useTrackerImages*, repeatMiddleBitmap* : WMProperties.BooleanProperty;
		min*, max*, pos*, pageSize*, width*, minTrackerSize* : WMProperties.Int32Property;
		ts, tp, lx, ly : LONGINT;
		onPositionChanged* : EventSource;
		arrowLeftDefaultName*, arrowLeftHoverName*, arrowLeftPressedName*,
		arrowUpDefaultName*, arrowUpHoverName*, arrowUpPressedName*,
		arrowRightDefaultName*, arrowRightHoverName*, arrowRightPressedName*,
		arrowDownDefaultName*, arrowDownHoverName*, arrowDownPressedName* : WMProperties.StringProperty;
		(* background *)
		useBgBitmaps*, repeatBgBitmap* : WMProperties.BooleanProperty;		
		clDefault*, clHover*, clPressed* : WMProperties.ColorProperty;
		hBgDefaultName*, hBgHoverName*, hBgPressedName*,
		vBgDefaultName*, vBgHoverName*, vBgPressedName* : WMProperties.StringProperty;
		(* horizontal thumb *)		
		hTrackerDefaultNameLeft*, hTrackerHoverNameLeft*, hTrackerPressedNameLeft*,
		hTrackerDefaultNameMiddle*, hTrackerHoverNameMiddle*, hTrackerPressedNameMiddle*,
		hTrackerDefaultNameRight*, hTrackerHoverNameRight*, hTrackerPressedNameRight*,
		(* vertical thumb *)
		vTrackerDefaultNameTop*, vTrackerHoverNameTop*, vTrackerPressedNameTop*,
		vTrackerDefaultNameMiddle*, vTrackerHoverNameMiddle*, vTrackerPressedNameMiddle*,
		vTrackerDefaultNameBottom*, vTrackerHoverNameBottom*, vTrackerPressedNameBottom* : WMProperties.StringProperty;
		
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
			NEW(width, PrototypeSWidth, NIL, NIL);
			NEW(minTrackerSize, PrototypeSMinTrackerSize, NIL, NIL); properties.Add(minTrackerSize);

			(* --- tracker --- *)
			
			NEW(useTrackerImages, PrototypeSUseTrackerImages, NIL, NIL); properties.Add(useTrackerImages);
			NEW(repeatMiddleBitmap, PrototypeSRepeatMiddleBitmap, NIL, NIL); properties.Add(repeatMiddleBitmap);

			NEW(tracker); tracker.takesFocus.Set(FALSE); 
			tracker.repeatMiddleImg := SELF.repeatMiddleBitmap; 
			tracker.useBgBitmaps := SELF.useTrackerImages;
			tracker.alignment.Set(WMComponents.AlignClient);
				(* horizontal decoration bitmaps *)
			NEW(hTrackerDefaultNameLeft, PrototypeShTrackerDefaultLeft, NIL, NIL); properties.Add(hTrackerDefaultNameLeft);
			NEW(hTrackerHoverNameLeft, PrototypeShTrackerHoverLeft, NIL, NIL); properties.Add(hTrackerHoverNameLeft);
			NEW(hTrackerPressedNameLeft, PrototypeShTrackerPressedLeft, NIL, NIL); properties.Add(hTrackerPressedNameLeft);
			NEW(hTrackerDefaultNameMiddle, PrototypeShTrackerDefaultMiddle, NIL, NIL); properties.Add(hTrackerDefaultNameMiddle);
			NEW(hTrackerHoverNameMiddle, PrototypeShTrackerHoverMiddle, NIL, NIL); properties.Add(hTrackerHoverNameMiddle);
			NEW(hTrackerPressedNameMiddle, PrototypeShTrackerPressedMiddle, NIL, NIL); properties.Add(hTrackerPressedNameMiddle);
			NEW(hTrackerDefaultNameRight, PrototypeShTrackerDefaultRight, NIL, NIL); properties.Add(hTrackerDefaultNameRight);
			NEW(hTrackerHoverNameRight, PrototypeShTrackerHoverRight, NIL, NIL); properties.Add(hTrackerHoverNameRight);
			NEW(hTrackerPressedNameRight, PrototypeShTrackerPressedRight, NIL, NIL); properties.Add(hTrackerPressedNameRight);
				(* vertical decoration bitmaps *)
			NEW(vTrackerDefaultNameTop, PrototypeSvTrackerDefaultTop, NIL, NIL); properties.Add(vTrackerDefaultNameTop);
			NEW(vTrackerHoverNameTop, PrototypeSvTrackerHoverTop, NIL, NIL); properties.Add(vTrackerHoverNameTop);
			NEW(vTrackerPressedNameTop, PrototypeSvTrackerPressedTop, NIL, NIL); properties.Add(vTrackerPressedNameTop);
			NEW(vTrackerDefaultNameMiddle, PrototypeSvTrackerDefaultMiddle, NIL, NIL); properties.Add(vTrackerDefaultNameMiddle);
			NEW(vTrackerHoverNameMiddle, PrototypeSvTrackerHoverMiddle, NIL, NIL); properties.Add(vTrackerHoverNameMiddle);
			NEW(vTrackerPressedNameMiddle, PrototypeSvTrackerPressedMiddle, NIL, NIL); properties.Add(vTrackerPressedNameMiddle);
			NEW(vTrackerDefaultNameBottom, PrototypeSvTrackerDefaultBottom, NIL, NIL); properties.Add(vTrackerDefaultNameBottom);
			NEW(vTrackerHoverNameBottom, PrototypeSvTrackerHoverBottom, NIL, NIL); properties.Add(vTrackerHoverNameBottom);
			NEW(vTrackerPressedNameBottom, PrototypeSvTrackerPressedBottom, NIL, NIL); properties.Add(vTrackerPressedNameBottom);

			(* --- background of scrollbar --- *)
			
			NEW(useBgBitmaps, PrototypeSUseBgBitmaps, NIL, NIL); properties.Add(useBgBitmaps);
			NEW(repeatBgBitmap, PrototypeSRepeateBgBitmap, NIL, NIL); properties.Add(repeatBgBitmap);
				(* simple representation *)
			NEW(clDefault, PrototypeSClDefault, NIL, NIL); properties.Add(clDefault);
			NEW(clHover, PrototypeSClHover, NIL, NIL); properties.Add(clHover);
			NEW(clPressed, PrototypeSClPressed, NIL, NIL); properties.Add(clPressed);
				(* bitmap representation *)
			NEW(hBgDefaultName, PrototypeShBgDefault, NIL, NIL); properties.Add(hBgDefaultName);
			NEW(hBgHoverName, PrototypeShBgHover, NIL, NIL); properties.Add(hBgHoverName);
			NEW(hBgPressedName, PrototypeShBgPressed, NIL, NIL); properties.Add(hBgPressedName);
			NEW(vBgDefaultName, PrototypeSvBgDefault, NIL, NIL); properties.Add(vBgDefaultName);
			NEW(vBgHoverName, PrototypeSvBgHover, NIL, NIL); properties.Add(vBgHoverName);
			NEW(vBgPressedName, PrototypeSvBgPressed, NIL, NIL); properties.Add(vBgPressedName);
				(* minus page *)
			NEW(minusPage); minusPage.takesFocus.Set(FALSE); minusPage.onClick.Add(PageUp); minusPage.isRepeating.Set(TRUE);
			minusPage.useBgBitmaps := SELF.useBgBitmaps;
					(* simple representation *)
			minusPage.glassEffect.Set(0);
			minusPage.clDefault := SELF.clDefault; minusPage.clHover := SELF.clHover; minusPage.clPressed := SELF.clPressed;
					(* bitmap representation *)
			minusPage.repeatMiddleImg := SELF.repeatBgBitmap;
				(* plus page *)
			NEW(plusPage); plusPage.takesFocus.Set(FALSE);  plusPage.onClick.Add(PageDown); plusPage.isRepeating.Set(TRUE); 
			plusPage.useBgBitmaps := SELF.useBgBitmaps;
					(* simple representation *)
			plusPage.glassEffect.Set(0);
			plusPage.clDefault := SELF.clDefault; plusPage.clHover := SELF.clHover; plusPage.clPressed := SELF.clPressed;
					(* bitmap representation *)
			plusPage.repeatMiddleImg := SELF.repeatBgBitmap;

			(* --- arrow buttons --- *)
			
			NEW(useArrowImages, PrototypeSUseArrowImages, NIL, NIL); properties.Add(useArrowImages);
				(* left *)
			NEW(arrowLeftDefaultName, PrototypeSArrowLeftDefault, NIL, NIL); properties.Add(arrowLeftDefaultName);
			NEW(arrowLeftHoverName, PrototypeSArrowLeftHover, NIL, NIL); properties.Add(arrowLeftHoverName);
			NEW(arrowLeftPressedName, PrototypeSArrowLeftPressed, NIL, NIL); properties.Add(arrowLeftPressedName);
			NEW(arrowLeft); AddContent(arrowLeft); arrowLeft.alignment.Set(WMComponents.AlignLeft);
			arrowLeft.useBgBitmaps := SELF.useArrowImages;
			arrowLeft.imgDefaultNameLeft.Set(NIL); arrowLeft.imgDefaultNameRight.Set(NIL); 
			arrowLeft.imgDefaultNameMiddle := SELF.arrowLeftDefaultName;
			arrowLeft.imgHoverNameLeft.Set(NIL); arrowLeft.imgHoverNameRight.Set(NIL); 
			arrowLeft.imgHoverNameMiddle := SELF.arrowLeftHoverName;
			arrowLeft.imgPressedNameLeft.Set(NIL);	arrowLeft.imgPressedNameRight.Set(NIL); 
			arrowLeft.imgPressedNameMiddle := SELF.arrowLeftPressedName;
				(* right *)
			NEW(arrowRightDefaultName, PrototypeSArrowRightDefault, NIL, NIL); properties.Add(arrowRightDefaultName);
			NEW(arrowRightHoverName, PrototypeSArrowRightHover, NIL, NIL); properties.Add(arrowRightHoverName);
			NEW(arrowRightPressedName, PrototypeSArrowRightPressed, NIL, NIL); properties.Add(arrowRightPressedName);
			NEW(arrowRight); AddContent(arrowRight); arrowRight.alignment.Set(WMComponents.AlignRight);
			arrowRight.useBgBitmaps := SELF.useArrowImages;
			arrowRight.imgDefaultNameLeft.Set(NIL); arrowRight.imgDefaultNameRight.Set(NIL); 
			arrowRight.imgDefaultNameMiddle := SELF.arrowRightDefaultName;
			arrowRight.imgHoverNameLeft.Set(NIL); arrowRight.imgHoverNameRight.Set(NIL); 
			arrowRight.imgHoverNameMiddle := SELF.arrowRightHoverName;
			arrowRight.imgPressedNameLeft.Set(NIL);	arrowRight.imgPressedNameRight.Set(NIL); 
			arrowRight.imgPressedNameMiddle := SELF.arrowRightPressedName;
				(* up *)
			NEW(arrowUpDefaultName, PrototypeSArrowUpDefault, NIL, NIL); properties.Add(arrowUpDefaultName);
			NEW(arrowUpHoverName, PrototypeSArrowUpHover, NIL, NIL); properties.Add(arrowUpHoverName);
			NEW(arrowUpPressedName, PrototypeSArrowUpPressed, NIL, NIL); properties.Add(arrowUpPressedName);
			NEW(arrowUp); AddContent(arrowUp); arrowUp.alignment.Set(WMComponents.AlignTop);
			arrowUp.useBgBitmaps := SELF.useArrowImages;
			arrowUp.imgDefaultNameLeft.Set(NIL); arrowUp.imgDefaultNameRight.Set(NIL); 
			arrowUp.imgDefaultNameMiddle := SELF.arrowUpDefaultName;
			arrowUp.imgHoverNameLeft.Set(NIL); arrowUp.imgHoverNameRight.Set(NIL); 
			arrowUp.imgHoverNameMiddle := SELF.arrowUpHoverName;
			arrowUp.imgPressedNameLeft.Set(NIL);	arrowUp.imgPressedNameRight.Set(NIL); 
			arrowUp.imgPressedNameMiddle := SELF.arrowUpPressedName;
				(* down *)
			NEW(arrowDownDefaultName, PrototypeSArrowDownDefault, NIL, NIL); properties.Add(arrowDownDefaultName);
			NEW(arrowDownHoverName, PrototypeSArrowDownHover, NIL, NIL); properties.Add(arrowDownHoverName);
			NEW(arrowDownPressedName, PrototypeSArrowDownPressed, NIL, NIL); properties.Add(arrowDownPressedName);
			NEW(arrowDown); AddContent(arrowDown); arrowDown.alignment.Set(WMComponents.AlignBottom);
			arrowDown.useBgBitmaps := SELF.useArrowImages;
			arrowDown.imgDefaultNameLeft.Set(NIL); arrowDown.imgDefaultNameRight.Set(NIL); 
			arrowDown.imgDefaultNameMiddle := SELF.arrowDownDefaultName;
			arrowDown.imgHoverNameLeft.Set(NIL); arrowDown.imgHoverNameRight.Set(NIL); 
			arrowDown.imgHoverNameMiddle := SELF.arrowDownHoverName;
			arrowDown.imgPressedNameLeft.Set(NIL);	arrowDown.imgPressedNameRight.Set(NIL); 
			arrowDown.imgPressedNameMiddle := SELF.arrowDownPressedName;

				(* behaviour *)
			arrowLeft.onClick.Add(DecPos); arrowLeft.isRepeating.Set(TRUE); arrowLeft.takesFocus.Set(FALSE);
			arrowRight.onClick.Add(IncPos); arrowRight.isRepeating.Set(TRUE); arrowRight.takesFocus.Set(FALSE);
			arrowUp.onClick.Add(DecPos); arrowUp.isRepeating.Set(TRUE); arrowUp.takesFocus.Set(FALSE);
			arrowDown.onClick.Add(IncPos); arrowDown.isRepeating.Set(TRUE); arrowDown.takesFocus.Set(FALSE);

			SetDirection;
			
			AddContent(minusPage); 
			AddContent(plusPage);
			AddContent(tracker); 
			tracker.SetExtPointerDownHandler(TrackerPointerDown);
			tracker.SetExtPointerMoveHandler(TrackerPointerMove);
			
			bounds.SetExtents(SELF.width.Get(), SELF.width.Get());
			takesFocus.Set(FALSE)
		END Init;
		
		PROCEDURE TrackerPointerDown(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		BEGIN
			lx := x; ly := y; handled := FALSE
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
				IF dp # 0 THEN pos.Set(pos.Get() + dp); onPositionChanged.Call(pos) END
			END;
			handled := FALSE
		END TrackerPointerMove;
				
		PROCEDURE RecacheProperties;
		BEGIN
			RecacheProperties^;
			pos.SetBounds(min.Get(), max.Get()); 
			SetDirection; 
			AlignSubComponents;
			IF SELF.vertical.Get() THEN 
				bounds.SetWidth(SELF.width.Get())
			ELSE 
				bounds.SetHeight(SELF.width.Get()) 
			END;
			Invalidate
		END RecacheProperties;
		
		PROCEDURE PropertyChanged*(sender, property : ANY);
		BEGIN
			IF (property = pos) THEN
				AlignSubComponents; Invalidate;
				(* onPositionChanged.Call(property) *)
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
			ELSE pos.Set(pos.Get() - 1); onPositionChanged.Call(pos)
			END	
		END DecPos;
		
		PROCEDURE IncPos*(sender, par : PTR);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.IncPos, sender, par) 
			ELSE pos.Set(pos.Get() + 1); onPositionChanged.Call(pos)
			END
		END IncPos;
		
		PROCEDURE PageUp*(sender, par : PTR);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.PageUp, sender, par) 
			ELSE pos.Set(pos.Get() - pageSize.Get()); onPositionChanged.Call(pos)
			END	
		END PageUp;
		
		PROCEDURE PageDown*(sender, par : PTR);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.PageDown, sender, par) 
			ELSE pos.Set(pos.Get() + pageSize.Get()); onPositionChanged.Call(pos)
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
					ts := Utilities.Min(h, Utilities.Max(ENTIER(f * h), SELF.minTrackerSize.Get()));
					tp := (pos.Get() - tmin) * (h - ts) DIV (tmax - tmin); 
				ELSE ts := 0; tp := 0;	
				END;
				minusPage.bounds.SetHeight(tp); 
				plusPage.bounds.SetHeight(h - tp - ts);
				tracker.bounds.SetWidth(ts)
			ELSE
				IF tmax > tmin THEN
					w := (bounds.GetWidth() - 2 * bounds.GetHeight());
					f := ps / (tmax - tmin);
					ts := Utilities.Min(w, Utilities.Max(ENTIER(f * w), SELF.minTrackerSize.Get()));
					tp := (pos.Get() - tmin) * (w - ts) DIV (tmax - tmin); 
				ELSE ts := 0; tp := 0;	
				END;
				minusPage.bounds.SetWidth(tp); 
				plusPage.bounds.SetWidth(w - tp - ts);
				tracker.bounds.SetWidth(ts)
			END;
			arrowLeft.bounds.SetWidth(bounds.GetHeight());
			arrowRight.bounds.SetWidth(bounds.GetHeight());
			arrowUp.bounds.SetHeight(bounds.GetWidth());
			arrowDown.bounds.SetHeight(bounds.GetWidth());
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
			SetBackgroundDirection();
			SetTrackerDirection();
			properties.ReleaseWrite; 
			Release
		END SetDirection;
		
		(* set direction of tracker (thumb) *)
		PROCEDURE SetTrackerDirection;
		BEGIN
			tracker.isHorizontal.Set(~SELF.vertical.Get());
			IF vertical.Get() THEN
				arrowLeft.visible.Set(FALSE); arrowRight.visible.Set(FALSE);
				arrowUp.visible.Set(TRUE); arrowDown.visible.Set(TRUE);
				tracker.imgDefaultNameTop := SELF.vTrackerDefaultNameTop; tracker.imgHoverNameTop := SELF.vTrackerHoverNameTop;
				tracker.imgPressedNameTop := SELF.vTrackerPressedNameTop; tracker.imgDefaultNameMiddle := SELF.vTrackerDefaultNameMiddle;
				tracker.imgHoverNameMiddle := SELF.vTrackerHoverNameMiddle; tracker.imgPressedNameMiddle := SELF.vTrackerPressedNameMiddle;
				tracker.imgDefaultNameBottom := SELF.vTrackerDefaultNameBottom; tracker.imgHoverNameBottom := SELF.vTrackerHoverNameBottom;
				tracker.imgPressedNameBottom := SELF.vTrackerPressedNameBottom
			ELSE
				arrowLeft.visible.Set(TRUE); arrowRight.visible.Set(TRUE);
				arrowUp.visible.Set(FALSE); arrowDown.visible.Set(FALSE);
				tracker.imgDefaultNameLeft := SELF.hTrackerDefaultNameLeft; tracker.imgHoverNameLeft := SELF.hTrackerHoverNameLeft;
				tracker.imgPressedNameLeft := SELF.hTrackerPressedNameLeft; tracker.imgDefaultNameMiddle := SELF.hTrackerDefaultNameMiddle;
				tracker.imgHoverNameMiddle := SELF.hTrackerHoverNameMiddle; tracker.imgPressedNameMiddle := SELF.hTrackerPressedNameMiddle;
				tracker.imgDefaultNameRight := SELF.hTrackerDefaultNameRight; tracker.imgHoverNameRight := SELF.hTrackerHoverNameRight;
				tracker.imgPressedNameRight := SELF.hTrackerPressedNameRight
			END
		END SetTrackerDirection;
		
		(* set direction of background (minusPage, plusPage *)
		PROCEDURE SetBackgroundDirection;
		BEGIN
			minusPage.isHorizontal.Set(~SELF.vertical.Get());
			plusPage.isHorizontal.Set(~SELF.vertical.Get());
			IF vertical.Get() THEN
				minusPage.alignment.Set(WMComponents.AlignTop);
				minusPage.imgDefaultNameMiddle := SELF.vBgDefaultName;
				minusPage.imgHoverNameMiddle := SELF.vBgHoverName;
				minusPage.imgPressedNameMiddle := SELF.vBgPressedName;
				plusPage.alignment.Set(WMComponents.AlignBottom);
				plusPage.imgDefaultNameMiddle := SELF.vBgDefaultName;
				plusPage.imgHoverNameMiddle := SELF.vBgHoverName;
				plusPage.imgPressedNameMiddle := SELF.vBgPressedName
			ELSE
				minusPage.alignment.Set(WMComponents.AlignLeft);
				minusPage.imgDefaultNameMiddle := SELF.hBgDefaultName;
				minusPage.imgHoverNameMiddle := SELF.hBgHoverName;
				minusPage.imgPressedNameMiddle := SELF.hBgPressedName;
				plusPage.alignment.Set(WMComponents.AlignRight);
				plusPage.imgDefaultNameMiddle := SELF.hBgDefaultName;
				plusPage.imgHoverNameMiddle := SELF.hBgHoverName;
				plusPage.imgPressedNameMiddle := SELF.hBgPressedName
			END
		END SetBackgroundDirection;
	
	END Scrollbar;
		
	Resizer* = OBJECT(WMComponents.VisualComponent)
		VAR dnx, dny : LONGINT;
			clDefault- : WMProperties.ColorProperty;
			isFlat- : WMProperties.BooleanProperty;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			SetNameAsString(StrResizer);
			NEW(clDefault, PrototypeRclDefault, NIL, NIL); properties.Add(clDefault);
			NEW(isFlat, PrototypeRisFlat, NIL, NIL); properties.Add(isFlat);
			bounds.SetPrototype(PrototypeRBounds)
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
			canvas.Fill(GetClientRect(), SELF.clDefault.Get(), WMGraphics.ModeSrcOverDst);
			IF ~SELF.isFlat.Get() THEN WMGraphicUtilities.RectGlassShade(canvas, GetClientRect(), 2, FALSE) END
		END DrawBackground;
		
	END Resizer;
	(* Group Panel *)
	GroupPanel* = OBJECT(Panel)
	VAR 
		caption*: WMProperties.StringProperty;
		textColor* : WMProperties.ColorProperty;
		border : WMRectangles.Rectangle;
		captionFont : WMGraphics.Font;
		centerContent, panel: Panel;
	
		PROCEDURE &Init*;
		BEGIN
			Init^;
			border := WMRectangles.MakeRect(10,14,10,10);
			NEW(caption, ProtGPCaption, NIL, NIL); properties.Add(caption);
			captionFont := WMGraphics.GetFont("Oberon", 8, {});	
			NEW(textColor, ProtGPTextColor, NIL, NIL); properties.Add(textColor);
			CreateComponent;
			SetNameAsString(StrGroupPanel);
		END Init;
		
		PROCEDURE CreateComponent;
		BEGIN
			(* build form with bearing *)
			NEW(panel); panel.alignment.Set(WMComponents.AlignClient);
			NEW(centerContent); centerContent.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(centerContent);
			AddContent^(panel);
			centerContent.bearing.Set(border);
		END CreateComponent;

		PROCEDURE PropertyChanged*(sender, property : PTR);
		BEGIN
			IF (property = caption) OR (property = textColor) THEN Invalidate 
			ELSE PropertyChanged^(sender, property)
			END;
		END PropertyChanged;

		PROCEDURE DrawBackground(canvas: WMGraphics.Canvas);
		VAR rect: WMRectangles.Rectangle;
			highlight, shadow, w, h : LONGINT;
			tempString : Utilities.String;
		BEGIN
			highlight := 0FFFFFF80H;
			shadow := 000000080H;
			rect := GetClientRect();
			tempString := caption.Get();
			(* group line *)
			IF (tempString = NIL) OR (tempString^ = "") THEN
				canvas.Line(rect.l+3, rect.t+5, rect.r-4, rect.t+5, shadow, WMGraphics.ModeSrcOverDst);
				canvas.Line(rect.l+4, rect.t+6, rect.r-5, rect.t+6, highlight, WMGraphics.ModeSrcOverDst);
			ELSE
				captionFont.GetStringSize(tempString^, w, h);
				canvas.Line(rect.l+3, rect.t+5, rect.l+12, rect.t+5, shadow, WMGraphics.ModeSrcOverDst);
				canvas.Line(rect.l+4, rect.t+6, rect.l+12, rect.t+6, highlight, WMGraphics.ModeSrcOverDst);
				canvas.Line(rect.l+w+17, rect.t+5, rect.r-4, rect.t+5, shadow, WMGraphics.ModeSrcOverDst);
				canvas.Line(rect.l+w+17, rect.t+6, rect.r-5, rect.t+6, highlight, WMGraphics.ModeSrcOverDst);		
			END;
			canvas.Line(rect.l+3, rect.b-4, rect.r-4, rect.b-4, shadow, WMGraphics.ModeSrcOverDst);
			canvas.Line(rect.l+3, rect.t+5, rect.l+3, rect.b-4, shadow, WMGraphics.ModeSrcOverDst);
			canvas.Line(rect.r-4, rect.t+5, rect.r-4, rect.b-4, shadow, WMGraphics.ModeSrcOverDst);
			
			canvas.Line(rect.l+3, rect.b-3, rect.r-3, rect.b-3, highlight, WMGraphics.ModeSrcOverDst);
			canvas.Line(rect.l+4, rect.t+6, rect.l+4, rect.b-5, highlight, WMGraphics.ModeSrcOverDst);
			canvas.Line(rect.r-3, rect.t+5, rect.r-3, rect.b-3, highlight, WMGraphics.ModeSrcOverDst);
			(* caption *)
			IF (tempString # NIL) & (tempString^ # "") THEN
				canvas.SetColor(textColor.Get());
				captionFont.RenderString(canvas, rect.l+15, rect.t+9, tempString^);
			END;
		END DrawBackground;
		
		PROCEDURE AddContent*(content: XML.Content);
		BEGIN
			centerContent.AddContent(content);
		END AddContent;		
				
	END GroupPanel;	

CONST
	Default* = -1;			(* checkbox states *)
	Unchecked* = 0;
	Checked* = 1;
	
	Left* = 0;					(* checkbox caption position *) 
	Right* = 1;
	
TYPE	
	(* Checkbox component *)
	Checkbox* = OBJECT(WMComponents.VisualComponent)
	VAR 
		caption- , onClickHandler-: WMProperties.StringProperty;
		hasThreeStates-, useImages-, scaleImages- : WMProperties.BooleanProperty;
		state- : WMProperties.Int32Property;					(* 0 = unchecked, 1 = checked, -1 = use default *)
		clBack-, clCheck-, clDefault-, clInactive- : WMProperties.ColorProperty;  
		imgCheckedName-, imgUncheckedName-, imgDefaultName-, imgCheckedInactiveName-, imgUncheckedInactiveName-, imgDefaultInactiveName-: WMProperties.StringProperty;
		imgChecked, imgUnchecked, imgDefault, imgCheckedInactive, imgUncheckedInactive, imgDefaultInactive: WMGraphics.Image;
		mouseOver: BOOLEAN;
		onClick- : EventSource;
		handler : WMEvents.EventListener;
		
		PROCEDURE &Init*;
		BEGIN
			Init^;
			NEW(caption, ProtCBCaption, NIL, NIL); properties.Add(caption);
			NEW(hasThreeStates, ProtCBHasThreeStates, NIL, NIL); properties.Add(hasThreeStates);	
			NEW(state, ProtCBState, NIL, NIL); properties.Add(state);
			NEW(onClickHandler, PrototypeCBonClickHandler, NIL, NIL); properties.Add(onClickHandler);
			
			bounds.SetPrototype(ProtCBBounds); (* override the defaults *)
			
			(* colors *)
			NEW(clBack, ProtCBclBack, NIL, NIL); properties.Add(clBack);
			NEW(clCheck, ProtCBclCheck, NIL, NIL); properties.Add(clCheck);
			NEW(clDefault, ProtCBclDefault, NIL, NIL); properties.Add(clDefault);
			NEW(clInactive, ProtCBclInactive, NIL, NIL); properties.Add(clInactive);
			
			(* images *)
			NEW(useImages, ProtCBUseImages, NIL, NIL); properties.Add(useImages);
			NEW(scaleImages, ProtCBScaleImages, NIL, NIL); properties.Add(scaleImages);

			NEW(imgCheckedName, ProtCBImgCheckedN, NIL, NIL); properties.Add(imgCheckedName);
			NEW(imgUncheckedName, ProtCBImgUncheckedN, NIL, NIL); properties.Add(imgUncheckedName);
			NEW(imgDefaultName, ProtCBImgDefaultN, NIL, NIL); properties.Add(imgDefaultName);
			NEW(imgCheckedInactiveName, ProtCBImgCheckedInactiveN, NIL, NIL); properties.Add(imgCheckedInactiveName);
			NEW(imgUncheckedInactiveName, ProtCBImgUncheckedInactiveN, NIL, NIL); properties.Add(imgUncheckedInactiveName);
			NEW(imgDefaultInactiveName, ProtCBImgDefaultInactiveN, NIL, NIL); properties.Add(imgDefaultInactiveName);

			(* events *)
			NEW(onClick, SELF, GSonClick, GSonClickCheckboxInfo, SELF.StringToCompCommand); events.Add(onClick);
			SetNameAsString(StrCheckbox);
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
		
		PROCEDURE PropertyChanged*(sender, data : PTR);
		BEGIN
			IF data = onClickHandler THEN CheckClickHandler;
			ELSIF data = fillColor THEN Invalidate;
			ELSIF data = state THEN Invalidate;
			ELSIF (data = useImages)
				OR (data = imgCheckedName) OR (data = imgUncheckedName) OR (data = imgDefaultName)
				OR (data = imgCheckedInactiveName) OR (data = imgUncheckedInactiveName) OR (data = imgDefaultInactiveName)  THEN
				RecacheProperties; Invalidate
			ELSIF (data = caption) THEN Invalidate
			ELSE PropertyChanged^(sender, data)
			END;
		END PropertyChanged;
		
		PROCEDURE RecacheProperties;
		VAR s : String;
		BEGIN
			RecacheProperties^;
			s := imgCheckedName.Get(); IF s # NIL THEN imgChecked := WMGraphics.LoadImage(s^, TRUE) END;
			s := imgUncheckedName.Get(); IF s # NIL THEN imgUnchecked := WMGraphics.LoadImage(s^, TRUE) END;
			s := imgDefaultName.Get(); IF s # NIL THEN imgDefault	:= WMGraphics.LoadImage(s^, TRUE) END;
			s := imgCheckedInactiveName.Get(); IF s # NIL THEN imgCheckedInactive := WMGraphics.LoadImage(s^, TRUE) END;
			s := imgUncheckedInactiveName.Get(); IF s # NIL THEN imgUncheckedInactive := WMGraphics.LoadImage(s^, TRUE) END;
			s := imgDefaultInactiveName.Get(); IF s # NIL THEN imgDefaultInactive := WMGraphics.LoadImage(s^, TRUE) END;			
			CheckClickHandler;
			Invalidate
		END RecacheProperties;	
		
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

		PROCEDURE PointerDown(x, y: LONGINT; keys: SET);
		VAR value : LONGINT;
		BEGIN
			IF enabled.Get() THEN
				value := state.Get();
				IF value = -1 THEN state.Set(0);
				ELSIF value = 0 THEN state.Set(1);
				ELSIF (value = 1) THEN
					IF hasThreeStates.Get() THEN
						state.Set(-1);					
					ELSE
						state.Set(0);
					END;		
				END;			
				Click(SELF, NIL);	
			END;	
			Invalidate;
			PointerDown^(x, y, keys)
		END PointerDown;
		
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET); (** PROTECTED *)
		BEGIN
			IF IsHit(x, y) THEN
				IF ~mouseOver THEN mouseOver := TRUE; Invalidate END
			ELSE
				IF mouseOver THEN mouseOver := FALSE; Invalidate END
			END;	
			PointerMove^(x, y, keys)
		END PointerMove;
		
		PROCEDURE PointerLeave*; (** PROTECTED *)
		BEGIN
			 mouseOver := FALSE; Invalidate
		END PointerLeave;
		
		PROCEDURE Click*(sender, par : PTR); (** Eventhandler *) 
		BEGIN
			(* synchronize if not synchronized *)
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Click, sender, par) 
			ELSE
				(* actual business logic *)
				onClick.Call(par)
			END	
		END Click;		

		PROCEDURE DrawBackground(canvas: WMGraphics.Canvas);
		VAR rect: WMRectangles.Rectangle;
			string : Utilities.String;
			font : WMGraphics.Font;
			img : WMGraphics.Image;
		BEGIN
			IF ~visible.Get() THEN RETURN END;
			Acquire;
			rect := GetClientRect();
			font := GetFont();
			
			DrawBackground^(canvas);
			(* checkbox *)
			IF ~SELF.useImages.Get() THEN
				IF enabled.Get() THEN
					canvas.Fill(WMRectangles.MakeRect(0, 0, rect.b-rect.t, rect.b-rect.t), clBack.Get(), WMGraphics.ModeSrcOverDst);
				ELSE
					canvas.Fill(WMRectangles.MakeRect(0, 0, rect.b-rect.t, rect.b-rect.t), clInactive.Get(), WMGraphics.ModeSrcOverDst);		
				END;
				WMGraphicUtilities.RectGlassShade(canvas, WMRectangles.MakeRect(0, 0, rect.b-rect.t, rect.b-rect.t), 2, TRUE);
				IF state.Get() = 1 THEN
					canvas.Line(0, 0, rect.b-rect.t-1, rect.b-rect.t-1, clCheck.Get(), WMGraphics.ModeSrcOverDst);
					canvas.Line(0, rect.b-rect.t-1, rect.b-rect.t-1, 0, clCheck.Get(), WMGraphics.ModeSrcOverDst);			
				ELSIF state.Get() = -1 THEN
					canvas.Line(0, 0, rect.b-rect.t-1, rect.b-rect.t-1, clDefault.Get(), WMGraphics.ModeSrcOverDst);
					canvas.Line(0, rect.b-rect.t-1, rect.b-rect.t-1, 0, clDefault.Get(), WMGraphics.ModeSrcOverDst);	
				END;
			ELSE  (* the checkbox is decorated by images *)
				IF enabled.Get() THEN
					IF state.Get() = -1 THEN
						img := imgDefault;
					ELSIF state.Get() = 0 THEN
						img := imgUnchecked;
					ELSIF state.Get() = 1 THEN
						img := imgChecked;
					END;
				ELSE
					IF state.Get() = -1 THEN
						img := imgDefaultInactive;
					ELSIF state.Get() = 0 THEN
						img := imgUncheckedInactive;
					ELSIF state.Get() = 1 THEN
						img := imgCheckedInactive;
					END;			
				END;
				 
				IF img # NIL THEN
					IF scaleImages.Get() THEN
						canvas.ScaleImage(	img,
					 		WMRectangles.MakeRect(0, 0, img.width, img.height),
							WMRectangles.MakeRect(0, 0, ENTIER(bounds.GetHeight()/img.height*img.width), bounds.GetHeight()), 
							WMGraphics.ModeSrcOverDst, WMGraphics.ScaleBilinear);
					ELSE
						canvas.DrawImage(0, ((rect.b-rect.t)-img.height) DIV 2, img, WMGraphics.ModeSrcOverDst);
					END;
				END;				
			END;			
			(* checkbox hover *)
			IF mouseOver THEN
				IF useImages.Get() THEN
					IF scaleImages.Get() THEN 
						canvas.Fill(WMRectangles.MakeRect(0, 0, ENTIER(bounds.GetHeight()/img.height*img.width), bounds.GetHeight()), 0FFFF0040H, WMGraphics.ModeSrcOverDst)
					ELSE
						canvas.Fill(WMRectangles.MakeRect(0, ((rect.b-rect.t)-img.height) DIV 2, img.width, img.height), 0FFFF0040H, WMGraphics.ModeSrcOverDst)
					END
				ELSE
					canvas.Fill(WMRectangles.MakeRect(0, 0, rect.b-rect.t, rect.b-rect.t), 0FFFF0040H, WMGraphics.ModeSrcOverDst)
				END
			END;
			(* caption *)
			string := caption.Get();
			canvas.DrawString(rect.b-rect.t+5, (((rect.b-rect.t)- font.GetHeight()) DIV 2) + font.ascent+1, string^);									
			Release
		END DrawBackground;
		
	END Checkbox;	
	
		(** just shows an image, showing scrollbars if necessairy *)
	ImagePanel* = OBJECT(Panel)
	VAR img : WMGraphics.Image;
		imgName* : WMProperties.StringProperty;
		vScrollbar, hScrollbar : Scrollbar;
		dx, dy : LONGINT;

		PROCEDURE & Init;
		BEGIN
			Init^;
			(* properties *) 
			NEW(imgName, ProtoIpImgName, NIL, NIL); properties.Add(imgName);
			(* scrollbars *)
			NEW(vScrollbar); vScrollbar.alignment.Set(WMComponents.AlignRight); AddContent(vScrollbar);
			vScrollbar.onPositionChanged.Add(ScrollbarsChanged); vScrollbar.visible.Set(FALSE);
			NEW(hScrollbar); hScrollbar.alignment.Set(WMComponents.AlignBottom); AddContent(hScrollbar);
			hScrollbar.vertical.Set(FALSE); hScrollbar.onPositionChanged.Add(ScrollbarsChanged);
			hScrollbar.visible.Set(FALSE);
			SetNameAsString(StrImagePanel);
			dx := 0;  dy := 0 
		END Init;
		
		PROCEDURE PropertyChanged*(sender, prop : ANY);
		BEGIN
			IF prop = imgName THEN
				RecacheProperties
			ELSE
				PropertyChanged^(sender, prop)
			END
		END PropertyChanged;
		
		PROCEDURE RecacheProperties;
		VAR s : String;
		BEGIN
			s := imgName.Get(); IF s # NIL THEN SetImage(SELF, WMGraphics.LoadImage(s^, FALSE)) END	
		END RecacheProperties;
		
		PROCEDURE ScrollbarsChanged(sender, data : ANY);
		BEGIN
			Invalidate
		END ScrollbarsChanged;
		
		(** Iff data IS WMGraphics.Image, it is set as background. Else the background is set to white *)
		(* Note: Only use for anonymous Images without a specific Name *)
		PROCEDURE SetImage*(sender, data : ANY);
		BEGIN
			IF (data # NIL) & (data IS WMGraphics.Image) THEN
				img := data(WMGraphics.Image);
				IF img.width > bounds.GetWidth() THEN 
					dx := img.width - bounds.GetWidth();
					hScrollbar.visible.Set(TRUE)
				ELSE 
					dx := 0;
					hScrollbar.visible.Set(FALSE)
				END;
				IF img.height > bounds.GetHeight() THEN 
					dy := img.height - bounds.GetHeight();
					vScrollbar.visible.Set(TRUE)
				ELSE 
					dx := 0;
					vScrollbar.visible.Set(FALSE)
				END;
				Invalidate
			ELSE
				img := NIL; Invalidate
			END
		END SetImage;

		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR x, y : LONGINT;
		BEGIN
			DrawBackground^(canvas);
			IF img # NIL THEN
				x := dx * hScrollbar.pos.Get() DIV 100;
				y := dy * vScrollbar.pos.Get() DIV 100;
				canvas.DrawImage(-x, -y, img, WMGraphics.ModeSrcOverDst)
			END
		END DrawBackground;
			
	END ImagePanel;
		
VAR manager : WMWindowManager.WindowManager;

VAR (* global strings *)
	GSonTimer, GSonTimerInfo, GSStart, GSStartTimerInfo, GSStop, GSStopTimerInfo : String;
	GSRun, GSRunSystemCommandInfo, GSCallEventInfo : String;
	GSonClick, GSonClickButtonInfo, GSonClickCheckboxInfo : String;
	GSonPositionChanged, GSonPositionChangedInfo : String;
	
VAR
	 PrototypeInterval* : WMProperties.Int32Property;
	 PrototypeCommandString*, PrototypeCaption* : WMProperties.StringProperty;
	 PrototypeTextColor*: WMProperties.ColorProperty;
	 PrototypeAlignH*: WMProperties.Int32Property;
	 PrototypeAlignV*: WMProperties.Int32Property;
	 
	 (* temporary prototype-prototypes *)
	 ColorPrototype : WMProperties.ColorProperty; 
	 BooleanPrototype : WMProperties.BooleanProperty;
	 StringPrototype : WMProperties.StringProperty;
	 Int32Prototype : WMProperties.Int32Property;
	 RectanglePrototype : WMProperties.RectangleProperty;
	 
 	 (* Button prototypes *)
	 PrototypeBBounds* : WMProperties.RectangleProperty;
	 PrototypeBUseBgImages* : WMProperties.BooleanProperty;
	 PrototypeBclDefault*, PrototypeBclHover*, PrototypeBclPressed*,
	 PrototypeBclTextDefault*, PrototypeBclTextHover*, PrototypeBclTextPressed* : WMProperties.ColorProperty;
	 PrototypeBRepeatMiddleImg*, PrototypeBisRepeating*, PrototypeBisToggle*, PrototypeBIsHorizontal* : WMProperties.BooleanProperty;
	 PrototypeBcaption*, PrototypeBonClickHandler* : WMProperties.StringProperty;
	 PrototypeBimgDefaultName*, PrototypeBimgHoverName*, PrototypeBimgPressedName*, PrototypeBimageName* : WMProperties.StringProperty;
 	 PrototypeImgDefaultNameLeft*, PrototypeImgDefaultNameRight*, PrototypeImgDefaultNameMiddle*,
 	 PrototypeImgHoverNameLeft*, PrototypeImgHoverNameRight*, PrototypeImgHoverNameMiddle*,
 	 PrototypeImgPressedNameLeft*, PrototypeImgPressedNameRight*, PrototypeImgPressedNameMiddle* : WMProperties.StringProperty;
	 PrototypeBfontHeight*,  PrototypeBglassEffect : WMProperties.Int32Property;

	 (* Scrollbar prototypes *)
	 PrototypeSvertical* : WMProperties.BooleanProperty; 
	 PrototypeSmin*, PrototypeSmax*, PrototypeSpos*, PrototypeSpageSize*, PrototypeSWidth*,
	 PrototypeSMinTrackerSize* : WMProperties.Int32Property;
		 (* presentation : colors / images *)
 	 PrototypeSUseArrowImages*, PrototypeSUseTrackerImages*, PrototypeSRepeatMiddleBitmap* : WMProperties.BooleanProperty;
	 	(* background *)
	 PrototypeSUseBgBitmaps*, PrototypeSRepeateBgBitmap* : WMProperties.BooleanProperty;
 	 PrototypeSClDefault*, PrototypeSClHover*, PrototypeSClPressed* : WMProperties.ColorProperty;
 	 PrototypeSvBgDefault*, PrototypeSvBgHover*, PrototypeSvBgPressed*, 
 	 PrototypeShBgDefault*, PrototypeShBgHover*, PrototypeShBgPressed* : WMProperties.StringProperty;
 	 	(* arrow images *)
 	 PrototypeSArrowLeftDefault*, PrototypeSArrowLeftHover*, PrototypeSArrowLeftPressed*,
 	 PrototypeSArrowUpDefault*, PrototypeSArrowUpHover*, PrototypeSArrowUpPressed*,
 	 PrototypeSArrowRightDefault*, PrototypeSArrowRightHover*, PrototypeSArrowRightPressed*,
 	 PrototypeSArrowDownDefault*, PrototypeSArrowDownHover*, PrototypeSArrowDownPressed*  : WMProperties.StringProperty;
 	 	(* horizontal tracker *)
 	 PrototypeShTrackerDefaultLeft*, PrototypeShTrackerHoverLeft*, PrototypeShTrackerPressedLeft*,
 	 PrototypeShTrackerDefaultMiddle*, PrototypeShTrackerHoverMiddle*, PrototypeShTrackerPressedMiddle*, 
 	 PrototypeShTrackerDefaultRight*, PrototypeShTrackerHoverRight*, PrototypeShTrackerPressedRight*, 
 	 	(* vertical tracker *)
 	 PrototypeSvTrackerDefaultTop*, PrototypeSvTrackerHoverTop*, PrototypeSvTrackerPressedTop*,
 	 PrototypeSvTrackerDefaultMiddle*, PrototypeSvTrackerHoverMiddle*, PrototypeSvTrackerPressedMiddle*,
 	 PrototypeSvTrackerDefaultBottom*, PrototypeSvTrackerHoverBottom*, PrototypeSvTrackerPressedBottom* : WMProperties.StringProperty;
 	 
 	 (* Resizer prototypes *)
	 PrototypeRclDefault* : WMProperties.ColorProperty;
	 PrototypeRisFlat* : WMProperties.BooleanProperty;
	 PrototypeRBounds* : WMProperties.RectangleProperty;
	 
	(* Checkbox Prototypes *)
	ProtCBBounds* : WMProperties.RectangleProperty;
	ProtCBCaption*, PrototypeCBonClickHandler* : WMProperties.StringProperty;
	ProtCBCaptionPos* : WMProperties.Int32Property;
	ProtCBHasThreeStates* : WMProperties.BooleanProperty;
	ProtCBState* : WMProperties.Int32Property;
	ProtCBclBack*, ProtCBclCheck*, ProtCBclDefault*, ProtCBclInactive* : WMProperties.ColorProperty;
	ProtCBUseImages* : WMProperties.BooleanProperty;
	ProtCBScaleImages* : WMProperties.BooleanProperty;
	ProtCBImgCheckedN*, ProtCBImgUncheckedN*, ProtCBImgDefaultN*, 
	ProtCBImgCheckedInactiveN*, ProtCBImgUncheckedInactiveN*, ProtCBImgDefaultInactiveN* : WMProperties.StringProperty;

	(* Group Panel *)
	ProtGPCaption* : WMProperties.StringProperty;
	ProtGPTextColor* : WMProperties.ColorProperty;
	
	(* Image Panel *)
	ProtoIpImgName* : WMProperties.StringProperty;

	 
	StrTimer*, StrSystemCommand*, StrEvent*, StrPanel*, StrLabel*, StrButton*, StrScrollbar*, StrResizer* , StrCheckbox, StrGroupPanel, StrImagePanel : String;
	 	 
PROCEDURE InitStrings;
BEGIN
	GSonTimer := NewString("onTimer"); GSonTimerInfo := NewString("generates an event if the timer runs out");
	GSStart := NewString("Start"); GSStartTimerInfo := NewString("start the timer");
	GSStop := NewString("Stop"); GSStopTimerInfo := NewString("stop the timer");
	GSRun := NewString("Run");
	
	GSRunSystemCommandInfo := NewString("run the system command specified in commandString");
	GSCallEventInfo := NewString("call the event listener specified in commandString");
	
	GSonClick := NewString("onClick"); GSonClickButtonInfo := NewString("generates an event if the button is clicked"); 
	GSonClickCheckboxInfo := NewString("generates an event if the checkbox is clicked"); 
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
	StrCheckbox := NewString("Checkbox");
	StrGroupPanel := NewString("GroupPanel");
	StrImagePanel := NewString("ImagePanel");

END InitStrings;
	 
PROCEDURE InitPrototypes;
VAR 
	plTimer, plLabel, plButton, plScrollbar, plResizer, plCheckbox, plGroupPanel, plImagePanel : WMProperties.PropertyList;
BEGIN
	(* Timer properties *)
	NEW(plTimer);
	NEW(PrototypeInterval, NIL, NewString("interval"),  NewString("time between two timer ticks in ms"));
	PrototypeInterval.Set(100);
	plTimer.Add(PrototypeInterval);
	WMComponents.propertyListList.Add("Timer", plTimer);

	(* SystemCommand properties *)
	NEW(PrototypeCommandString, NIL, NewString("CommandString"), NewString("command to be executed uppon call to Run"));
		
	(* Label properties *)
	NEW(plLabel); WMComponents.propertyListList.Add("Label", plLabel);
	NEW(PrototypeCaption, NIL, NewString("Caption"), NewString("caption text"));
	NEW(PrototypeTextColor, NIL, NewString("TextColor"), NewString("text color")); plLabel.Add(PrototypeTextColor);
	NEW(PrototypeAlignH, NIL, NewString("AlignH"), NewString("horizontal alignment")); plLabel.Add(PrototypeAlignH);
	PrototypeAlignH.Set(WMGraphics.AlignLeft);
	NEW(PrototypeAlignV, NIL, NewString("AlignV"), NewString("vertical alignment")); plLabel.Add(PrototypeAlignV);	
	PrototypeAlignV.Set(WMGraphics.AlignCenter);
	
	(* Button properties *)
	NEW(plButton);	WMComponents.propertyListList.Add("Button", plButton);
	NEW(PrototypeBIsHorizontal, NIL, NewString("IsHorizontal"), NewString("Specifies if the button is horizontal or vertical")); PrototypeBIsHorizontal.Set(TRUE);
		(* button size *)
	NEW(RectanglePrototype, WMComponents.PrototypeBounds, NewString("Bounds"), NIL); RectanglePrototype.Set(WMRectangles.MakeRect(0, 0, 50, 20));
	NEW(PrototypeBBounds, RectanglePrototype, NewString("Bounds"), NIL); plButton.Add(PrototypeBBounds);
		(* presentation *)
	NEW(BooleanPrototype, NIL, NewString("UseBgBitmaps"), NewString("Is the button decorated by bitmaps or simple colors?")); BooleanPrototype.Set(FALSE);
	NEW(PrototypeBUseBgImages, BooleanPrototype, NIL, NIL); plButton.Add(PrototypeBUseBgImages);
		(* background color *)
	NEW(ColorPrototype, NIL, NewString("ClDefault"), NewString("Default background color")); ColorPrototype.Set(1010C080H);
	NEW(PrototypeBclDefault, ColorPrototype, NIL, NIL); plButton.Add(PrototypeBclDefault);
	NEW(ColorPrototype, NIL, NewString("ClHover"), NewString("Mouseover background color")); ColorPrototype.Set(0EEEE00FFH);
	NEW(PrototypeBclHover, ColorPrototype, NIL, NIL); plButton.Add(PrototypeBclHover);
	NEW(ColorPrototype, NIL, NewString("ClPressed"), NewString("Pressed background color")); ColorPrototype.Set(0EEEE00FFH);
	NEW(PrototypeBclPressed, ColorPrototype, NIL, NIL); plButton.Add(PrototypeBclPressed);
		(* font color *)
	NEW(ColorPrototype, NIL, NewString("ClTextDefault"), NewString("Default text color")); ColorPrototype.Set(0FFFF00FFH);
	NEW(PrototypeBclTextDefault, ColorPrototype, NIL, NIL); plButton.Add(PrototypeBclTextDefault);
	NEW(ColorPrototype, NIL, NewString("ClTextHover"), NewString("Mouseover text color")); ColorPrototype.Set(00000FFFFH);
	NEW(PrototypeBclTextHover, ColorPrototype, NIL, NIL); plButton.Add(PrototypeBclTextHover);
	NEW(ColorPrototype, NIL, NewString("ClTextPressed"), NewString("Pressed text color")); ColorPrototype.Set(00000FFFFH);
	NEW(PrototypeBclTextPressed, ColorPrototype, NIL, NIL); plButton.Add(PrototypeBclTextPressed);
		(* font size *)	
	NEW(Int32Prototype, NIL, NewString("FontHeight"), NewString("height of the button text")); Int32Prototype.Set(12);
	NEW(PrototypeBfontHeight, Int32Prototype, NIL, NIL); plButton.Add(PrototypeBfontHeight);
		(* glass effect *)
	NEW(Int32Prototype, NIL, NewString("Effect3d"), NewString("Degree of 3d-effect. Zero for flat presentation")); Int32Prototype.Set(2);
	NEW(PrototypeBglassEffect, Int32Prototype, NIL, NIL); plButton.Add(PrototypeBglassEffect);
		(* behaviour *)	
	NEW(PrototypeBonClickHandler, NIL, NewString("OnClickHandler"), NewString("handler"));
	NEW(PrototypeBisRepeating, NIL, NewString("IsRepeating"), NewString("defines if the button repeats sending click events while being pressed down"));
	NEW(PrototypeBisToggle, NIL, NewString("IsToggle"), NewString("defines if the button is a toggle button"));
		(* caption *)
	NEW(PrototypeBcaption, NIL, NewString("Caption"), NewString("defines the button text"));
		(* bitmaps *)
	NEW(BooleanPrototype, NIL, NewString("RepeatMiddleImage"), NewString("If TRUE, the middle image of the button representation will be repeated, scaled if FALSE"));
	BooleanPrototype.Set(FALSE);
	NEW(PrototypeBRepeatMiddleImg, BooleanPrototype, NIL, NIL); plButton.Add(PrototypeBRepeatMiddleImg);
		(* single images *)
	NEW(StringPrototype, NIL, NewString("BgDefault"), NewString("Default background bitmap")); StringPrototype.Set(NewString(""));
	NEW(PrototypeBimgDefaultName, StringPrototype, NIL, NIL); plButton.Add(PrototypeBimgDefaultName);
	NEW(StringPrototype, NIL, NewString("BgHover"), NewString("Mouseover background bitmap")); StringPrototype.Set(NewString(""));
	NEW(PrototypeBimgHoverName, StringPrototype, NIL, NIL); plButton.Add(PrototypeBimgHoverName);
	NEW(StringPrototype, NIL, NewString("BgPressed"), NewString("Pressed background bitmap")); StringPrototype.Set(NewString(""));
	NEW(PrototypeBimgPressedName, StringPrototype, NIL, NIL); plButton.Add(PrototypeBimgPressedName);		
		(* 3 x 3 background images *)
	NEW(StringPrototype, NIL, NewString("BgLeftDefault"), NewString("Default background bitmap left")); StringPrototype.Set(NewString(""));
	NEW(PrototypeImgDefaultNameLeft, StringPrototype, NIL, NIL); plButton.Add(PrototypeImgDefaultNameLeft);
	NEW(StringPrototype, NIL, NewString("BgRightDefault"), NewString("Default background bitmap right")); StringPrototype.Set(NewString(""));
	NEW(PrototypeImgDefaultNameRight, StringPrototype, NIL, NIL); plButton.Add(PrototypeImgDefaultNameRight);
	NEW(StringPrototype, NIL, NewString("BgMiddleDefault"), NewString("Default background bitmap middle")); StringPrototype.Set(NewString(""));
	NEW(PrototypeImgDefaultNameMiddle, StringPrototype, NIL, NIL); plButton.Add(PrototypeImgDefaultNameMiddle);
	NEW(StringPrototype, NIL, NewString("BgLeftHover"), NewString("Mouseover background bitmap left")); StringPrototype.Set(NewString(""));
	NEW(PrototypeImgHoverNameLeft, StringPrototype, NIL, NIL); plButton.Add(PrototypeImgHoverNameLeft);
	NEW(StringPrototype, NIL, NewString("BgRightHover"), NewString("Mouseover background bitmap right")); StringPrototype.Set(NewString(""));
	NEW(PrototypeImgHoverNameRight, StringPrototype, NIL, NIL); plButton.Add(PrototypeImgHoverNameRight);
	NEW(StringPrototype, NIL, NewString("BgMiddleHover"), NewString("Mouseover background bitmap middle")); StringPrototype.Set(NewString(""));
	NEW(PrototypeImgHoverNameMiddle, StringPrototype, NIL, NIL); plButton.Add(PrototypeImgHoverNameMiddle);
	NEW(StringPrototype, NIL, NewString("BgLeftPressed"), NewString("Pressed background bitmap left")); StringPrototype.Set(NewString(""));
	NEW(PrototypeImgPressedNameLeft, StringPrototype, NIL, NIL); plButton.Add(PrototypeImgPressedNameLeft);
	NEW(StringPrototype, NIL, NewString("BgRightPressed"), NewString("Pressed background bitmap right")); StringPrototype.Set(NewString(""));
	NEW(PrototypeImgPressedNameRight, StringPrototype, NIL, NIL); plButton.Add(PrototypeImgPressedNameRight);
	NEW(StringPrototype, NIL, NewString("BgMiddlePressed"), NewString("Pressed background bitmap middle")); StringPrototype.Set(NewString(""));
	NEW(PrototypeImgPressedNameMiddle, StringPrototype, NIL, NIL); plButton.Add(PrototypeImgPressedNameMiddle);

	(* Scrollbar prototypes *)
	NEW(plScrollbar); WMComponents.propertyListList.Add("Scrollbar", plScrollbar);
	NEW(PrototypeSvertical, NIL, 	NewString("Vertical"),	NewString("defines if the scrollbar is vertical"));
	NEW(PrototypeSmin, NIL, 		NewString("Min"), 		NewString("defines the scrollbar min position"));
	NEW(PrototypeSmax, NIL, 		NewString("Max"), 		NewString("defines the scrollbar max position"));
	NEW(PrototypeSpos, NIL, 		NewString("Pos"), 		NewString("defines the scrollbar position"));
	NEW(PrototypeSpageSize, NIL, 	NewString("PageSize"),	NewString("defines the scrollbar page size"));
	NEW(Int32Prototype, NIL, NewString("MinTrackerSize"), NewString("")); Int32Prototype.Set(5);
	NEW(PrototypeSMinTrackerSize, Int32Prototype, NIL, NIL); plScrollbar.Add(PrototypeSMinTrackerSize);
	
	PrototypeSvertical.Set(TRUE);
	PrototypeSmax.Set(100);
	PrototypeSpageSize.Set(20);
		(* scrollbar width *)	
	NEW(Int32Prototype, NIL, NewString("Width"), NewString("defines the scrollbar width")); Int32Prototype.Set(14);
	NEW(PrototypeSWidth, Int32Prototype, NIL, NIL); plScrollbar.Add(PrototypeSWidth);
		(* background *)
	NEW(BooleanPrototype, NIL, NewString("UseBackgroundBitmaps"), NewString("Should background be decorated by bitmaps or simple color?")); BooleanPrototype.Set(FALSE);
	NEW(PrototypeSUseBgBitmaps, BooleanPrototype, NIL, NIL);  plScrollbar.Add(PrototypeSUseBgBitmaps);
	NEW(BooleanPrototype, NIL, NewString("RepeatBgBitmaps"), NewString("Should background bitmap be repeated or streched?")); BooleanPrototype.Set(TRUE);
	NEW(PrototypeSRepeateBgBitmap, BooleanPrototype, NIL, NIL);  plScrollbar.Add(PrototypeSRepeateBgBitmap);
			(* color *)
	NEW(ColorPrototype, NIL, NewString("ClDefault"), NewString("Default background color")); ColorPrototype.Set(000000077H);
 	NEW(PrototypeSClDefault, ColorPrototype, NIL, NIL); plScrollbar.Add(PrototypeSClDefault);
	NEW(ColorPrototype, NIL, NewString("ClHover"), NewString("Mouseover background color")); ColorPrototype.Set(WMGraphics.Yellow);
 	NEW(PrototypeSClHover, ColorPrototype, NIL, NIL); plScrollbar.Add(PrototypeSClHover);
	NEW(ColorPrototype, NIL, NewString("ClPressed"), NewString("Pressed background color")); ColorPrototype.Set(WMGraphics.Yellow);
 	NEW(PrototypeSClPressed, ColorPrototype, NIL, NIL); plScrollbar.Add(PrototypeSClPressed);
			(* bitmaps *)
	NEW(StringPrototype, NIL, NewString("HorizontalBgDefault"), NewString("Default background bitmap for the horizontal scrollbar")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShBgDefault, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShBgDefault);
	NEW(StringPrototype, NIL, NewString("HorizontalBgHover"), NewString("Hover background bitmap for the horizontal scrollbar")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShBgHover, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShBgHover);
	NEW(StringPrototype, NIL, NewString("HorizontalBgPressed"), NewString("Pressed background bitmap for the horizontal scrollbar")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShBgPressed, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShBgPressed);
	NEW(StringPrototype, NIL, NewString("VerticalBgDefault"), NewString("Default background bitmap for the vertical scrollbar")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvBgDefault, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvBgDefault);
	NEW(StringPrototype, NIL, NewString("VerticalBgHover"), NewString("Hover background bitmap for the vertical scrollbar")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvBgHover, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvBgHover);
	NEW(StringPrototype, NIL, NewString("VerticalBgPressed"), NewString("Pressed background bitmap for the vertical scrollbar")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvBgPressed, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvBgPressed);
		(* trackers *)
	NEW(BooleanPrototype, NIL, NewString("UseTrackerBitmaps"), NewString("Should thumbs be decorated by bitmaps or simple color?")); BooleanPrototype.Set(FALSE);
	NEW(PrototypeSUseTrackerImages, BooleanPrototype, NIL, NIL);  plScrollbar.Add(PrototypeSUseTrackerImages);
	NEW(BooleanPrototype, NIL, NewString("RepeatMiddleBitmaps"), NewString("Has the middle thumb bitmap to be repeated or streched?")); BooleanPrototype.Set(TRUE);
	NEW(PrototypeSRepeatMiddleBitmap, BooleanPrototype, NIL, NIL);  plScrollbar.Add(PrototypeSRepeatMiddleBitmap);
			(* horizontal*)
	NEW(StringPrototype, NIL, NewString("HorizontalTrackerDefaultLeft"), NewString("Default background bitmap left of the horizontal thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShTrackerDefaultLeft, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShTrackerDefaultLeft);
	NEW(StringPrototype, NIL, NewString("HorizontalTrackerHoverLeft"), NewString("Mouseover background bitmap left of the horizontal thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShTrackerHoverLeft, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShTrackerHoverLeft);
	NEW(StringPrototype, NIL, NewString("HorizontalTrackerPressedLeft"), NewString("Pressed background bitmap left of the horizontal thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShTrackerPressedLeft, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShTrackerPressedLeft);
	NEW(StringPrototype, NIL, NewString("HorizontalTrackerDefaultMiddle"), NewString("Default background bitmap middle of the horizontal thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShTrackerDefaultMiddle, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShTrackerDefaultMiddle);
	NEW(StringPrototype, NIL, NewString("HorizontalTrackerHoverMiddle"), NewString("Mouseover background bitmap middle of the horizontal thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShTrackerHoverMiddle, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShTrackerHoverMiddle);
	NEW(StringPrototype, NIL, NewString("HorizontalTrackerPressedMiddle"), NewString("Pressed background bitmap middle of the horizontal thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShTrackerPressedMiddle, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShTrackerPressedMiddle);
	NEW(StringPrototype, NIL, NewString("HorizontalTrackerDefaultRight"), NewString("Default background bitmap right of the horizontal thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShTrackerDefaultRight, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShTrackerDefaultRight);
	NEW(StringPrototype, NIL, NewString("HorizontalTrackerHoverRight"), NewString("Mouseover background bitmap right of the horizontal thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShTrackerHoverRight, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShTrackerHoverRight);
	NEW(StringPrototype, NIL, NewString("HorizontalTrackerPressedRight"), NewString("Pressed background bitmap right of the horizontal thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeShTrackerPressedRight, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeShTrackerPressedRight);
			(* vertical *)
	NEW(StringPrototype, NIL, NewString("VerticalTrackerDefaultTop"), NewString("Default background bitmap top of the vertical thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvTrackerDefaultTop, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvTrackerDefaultTop);
	NEW(StringPrototype, NIL, NewString("VerticalTrackerHoverTop"), NewString("Mouseover background bitmap top of the vertical thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvTrackerHoverTop, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvTrackerHoverTop);
	NEW(StringPrototype, NIL, NewString("VerticalTrackerPressedTop"), NewString("Pressed background bitmap top of the vertical thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvTrackerPressedTop, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvTrackerPressedTop);
	NEW(StringPrototype, NIL, NewString("VerticalTrackerDefaultMiddle"), NewString("Default background bitmap middle of the vertical thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvTrackerDefaultMiddle, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvTrackerDefaultMiddle);
	NEW(StringPrototype, NIL, NewString("VerticalTrackerHoverMiddle"), NewString("Mouseover background bitmap middle of the vertical thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvTrackerHoverMiddle, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvTrackerHoverMiddle);
	NEW(StringPrototype, NIL, NewString("VerticalTrackerPressedMiddle"), NewString("Pressed background bitmap middle of the vertical thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvTrackerPressedMiddle, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvTrackerPressedMiddle);
	NEW(StringPrototype, NIL, NewString("VerticalTrackerDefaultBottom"), NewString("Default background bitmap bottom of the vertical thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvTrackerDefaultBottom, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvTrackerDefaultBottom);
	NEW(StringPrototype, NIL, NewString("VerticalTrackerHoverBottom"), NewString("Mouseover background bitmap bottom of the vertical thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvTrackerHoverBottom, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvTrackerHoverBottom);
	NEW(StringPrototype, NIL, NewString("VerticalTrackerPressedBottom"), NewString("Pressed background bitmap bottom of the vertical thumb")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSvTrackerPressedBottom, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSvTrackerPressedBottom);
		(* arrows *)
	NEW(BooleanPrototype, NIL, NewString("UseArrowBitmaps"), NewString("Have the arrow-buttons to be decorated by bitmaps or simple colors")); BooleanPrototype.Set(FALSE);
	NEW(PrototypeSUseArrowImages, BooleanPrototype, NIL, NIL);  plScrollbar.Add(PrototypeSUseArrowImages);
 			(* left *)
 	NEW(StringPrototype, NIL, NewString("ArrowLeftDefault"), NewString("Default bitmap for the left-arrow")); StringPrototype.Set(NewString(""));
 	NEW(PrototypeSArrowLeftDefault, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowLeftDefault);
 	NEW(StringPrototype, NIL, NewString("ArrowLeftHover"), NewString("Mouseover bitmap for the left-arrow")); StringPrototype.Set(NewString(""));
 	NEW(PrototypeSArrowLeftHover, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowLeftHover); 
 	NEW(StringPrototype, NIL, NewString("ArrowLeftPressed"), NewString("Pressed bitmap for the left-arrow")); StringPrototype.Set(NewString(""));
 	NEW(PrototypeSArrowLeftPressed, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowLeftPressed);
			(* right *)
	NEW(StringPrototype, NIL, NewString("ArrowRightDefault"), NewString("Default bitmap for the right-arrow")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSArrowRightDefault, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowRightDefault);
	NEW(StringPrototype, NIL, NewString("ArrowRightHover"), NewString("Mouseover bitmap for the right-arrow")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSArrowRightHover, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowRightHover);
	NEW(StringPrototype, NIL, NewString("ArrowRightPressed"), NewString("Pressed bitmap for the right-arrow")); StringPrototype.Set(NewString(""));
	NEW(PrototypeSArrowRightPressed, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowRightPressed);
			(* up *)
 	NEW(StringPrototype, NIL, NewString("ArrowUpDefault"), NewString("Default bitmap for the up-arrow"));StringPrototype.Set(NewString(""));
 	NEW(PrototypeSArrowUpDefault, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowUpDefault);
 	NEW(StringPrototype, NIL, NewString("ArrowUpHover"), NewString("Mouseover bitmap for the up-arrow")); StringPrototype.Set(NewString(""));
 	NEW(PrototypeSArrowUpHover, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowUpHover);
	NEW(StringPrototype, NIL, NewString("ArrowUpPressed"), NewString("Pressed bitmap for the up-arrow")); StringPrototype.Set(NewString(""));
 	NEW(PrototypeSArrowUpPressed, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowUpPressed);
			(* down *)
	NEW(StringPrototype, NIL, NewString("ArrowDownDefault"), NewString("Default bitmap for the down-arrow"));StringPrototype.Set(NewString(""));
	NEW(PrototypeSArrowDownDefault, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowDownDefault);
	NEW(StringPrototype, NIL, NewString("ArrowDownHover"), NewString("Mouseover bitmap for the down-arrow")); StringPrototype.Set(NewString(""));
 	NEW(PrototypeSArrowDownHover, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowDownHover);
	NEW(StringPrototype, NIL, NewString("ArrowDownPressed"), NewString("Pressed bitmap for the down-arrow")); StringPrototype.Set(NewString(""));
 	NEW(PrototypeSArrowDownPressed, StringPrototype, NIL, NIL); plScrollbar.Add(PrototypeSArrowDownPressed);
		
 	(* Resizer *)
 	NEW(plResizer);	WMComponents.propertyListList.Add("Resizer", plResizer);
 	NEW(ColorPrototype, NIL, NewString("ClDefault"), NewString("Default Color")); ColorPrototype.Set(WMGraphics.White);
 	NEW(PrototypeRclDefault, ColorPrototype, NIL, NIL); plResizer.Add(PrototypeRclDefault);
	NEW(BooleanPrototype, NIL, NewString("IsFlat"), NewString("Is the resizer flat or 3d?")); BooleanPrototype.Set(FALSE);
 	NEW(PrototypeRisFlat, BooleanPrototype, NIL, NIL); plResizer.Add(PrototypeRisFlat);
 	NEW(RectanglePrototype, NIL, NewString("Bounds"), NewString("Default width and height")); RectanglePrototype.SetWidth(5); RectanglePrototype.SetHeight(5);
 	NEW(PrototypeRBounds, RectanglePrototype, NIL, NIL); plResizer.Add(PrototypeRBounds);
 	(* Checkbox *)
	NEW(plCheckbox); WMComponents.propertyListList.Add("Checkbox", plCheckbox);
	
	NEW(ProtCBCaption, NIL, NewString("Caption"), NewString("caption text")); plCheckbox.Add(ProtCBCaption);
	ProtCBCaption.SetAOC("");
	NEW(ProtCBCaptionPos, NIL, NewString("CaptionPos"), NewString("caption position"));  plCheckbox.Add(ProtCBCaptionPos);
	ProtCBCaptionPos.Set(Right);
		(* Checkbox size *)
	NEW(RectanglePrototype, WMComponents.PrototypeBounds, NewString("Bounds"), NIL); RectanglePrototype.Set(WMRectangles.MakeRect(0, 0, 100, 20));
	NEW(ProtCBBounds, RectanglePrototype, NewString("Bounds"), NIL); plCheckbox.Add(ProtCBBounds);
		(* Checkbox state *)	
	NEW(ProtCBHasThreeStates, NIL, NewString("HasThreeStates"), NewString("enables three state checkbox")); plCheckbox.Add(ProtCBHasThreeStates);
	ProtCBHasThreeStates.Set(FALSE);
	NEW(ProtCBState, NIL, NewString("State"), NewString("current state")); plCheckbox.Add(ProtCBState);
	ProtCBState.Set(Unchecked);

			(* background color *)
	NEW(ColorPrototype, NIL, NewString("ClBack"), NewString("Checkbox Background Color")); ColorPrototype.Set(0FFFFFF80H);
	NEW(ProtCBclBack, ColorPrototype, NIL, NIL); plCheckbox.Add(ProtCBclBack);
	NEW(ColorPrototype, NIL, NewString("ClCheck"), NewString("Checkbox Check Color")); ColorPrototype.Set(0000000FFH);
	NEW(ProtCBclCheck, ColorPrototype, NIL, NIL); plCheckbox.Add(ProtCBclCheck);
	NEW(ColorPrototype, NIL, NewString("ClDefault"), NewString("Checkbox 3rd state Check Color")); ColorPrototype.Set(0555555FFH);
	NEW(ProtCBclDefault, ColorPrototype, NIL, NIL); plCheckbox.Add(ProtCBclDefault);
	NEW(ColorPrototype, NIL, NewString("ClInactive"), NewString("Checkbox Inactive Color")); ColorPrototype.Set(088888880H);
	NEW(ProtCBclInactive, ColorPrototype, NIL, NIL); plCheckbox.Add(ProtCBclInactive);
		(* presentation *)
	NEW(BooleanPrototype, NIL, NewString("UseBitmaps"), NewString("Have the Checkbox decorated by Images")); BooleanPrototype.Set(FALSE);
	NEW(ProtCBUseImages, BooleanPrototype, NIL, NIL); plCheckbox.Add(ProtCBUseImages);
	NEW(BooleanPrototype, NIL, NewString("ScaleBitmaps"), NewString("Have the Images scaled with the component siye")); BooleanPrototype.Set(FALSE);
	NEW(ProtCBScaleImages, BooleanPrototype, NIL, NIL); plCheckbox.Add(ProtCBScaleImages);	
		(* Checkbox images *)
	NEW(StringPrototype, NIL, NewString("ImgUnchecked"), NewString("Unchecked Image")); StringPrototype.SetAOC("");
	NEW(ProtCBImgUncheckedN, StringPrototype, NIL, NIL); plCheckbox.Add(ProtCBImgUncheckedN);
	NEW(StringPrototype, NIL, NewString("ImgChecked"), NewString("Checked Image")); StringPrototype.SetAOC("");
	NEW(ProtCBImgCheckedN, StringPrototype, NIL, NIL); plCheckbox.Add(ProtCBImgCheckedN);	
	NEW(StringPrototype, NIL, NewString("ImgDefault"), NewString("3rd state Image")); StringPrototype.SetAOC("");
	NEW(ProtCBImgDefaultN, StringPrototype, NIL, NIL); plCheckbox.Add(ProtCBImgDefaultN);	
	NEW(StringPrototype, NIL, NewString("ImgUncheckedInactive"), NewString("Unchecked Inactive Image")); StringPrototype.SetAOC("");
	NEW(ProtCBImgUncheckedInactiveN, StringPrototype, NIL, NIL); plCheckbox.Add(ProtCBImgUncheckedInactiveN);	
	NEW(StringPrototype, NIL, NewString("ImgCheckedInactive"), NewString("Checked Inactive Image")); StringPrototype.SetAOC("");
	NEW(ProtCBImgCheckedInactiveN, StringPrototype, NIL, NIL); plCheckbox.Add(ProtCBImgCheckedInactiveN);	
	NEW(StringPrototype, NIL, NewString("ImgDefaultInactive"), NewString("3rd state Inactive Image")); StringPrototype.SetAOC("");
	NEW(ProtCBImgDefaultInactiveN, StringPrototype, NIL, NIL); plCheckbox.Add(ProtCBImgDefaultInactiveN);	
	(* Group Panel *)
	NEW(plGroupPanel); WMComponents.propertyListList.Add("GroupPanel", plGroupPanel);
	NEW(ProtGPCaption, NIL, NewString("Caption"), NewString("caption text")); plGroupPanel.Add(ProtGPCaption);	
	NEW(ProtGPTextColor, NIL, NewString("TextColor"), NewString("Text color of group panel caption")); plGroupPanel.Add(ProtGPTextColor);
	(* Image Panel *)
	NEW(plImagePanel); WMComponents.propertyListList.Add("ImagePanel", plImagePanel);
	NEW(ProtoIpImgName, NIL, NewString("Image"), NewString("Name of image to be displayed")); plImagePanel.Add(ProtoIpImgName);	
	WMComponents.propertyListList.UpdateStyle
END InitPrototypes;

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

PROCEDURE GenCheckbox*(par : PTR) : PTR;
VAR checkbox : Checkbox;
BEGIN NEW(checkbox); RETURN checkbox
END GenCheckbox;

PROCEDURE GenGroupPanel*(par : PTR) : PTR;
VAR groupPanel : GroupPanel;
BEGIN NEW(groupPanel); RETURN groupPanel
END GenGroupPanel;

PROCEDURE GenImagePanel*(par : ANY) : ANY;
VAR ip : ImagePanel;
BEGIN NEW(ip); RETURN ip
END GenImagePanel;

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
	WMComponents.registry.RegisterElement("Resizer", GenResizer);
	WMComponents.registry.RegisterElement("Checkbox", GenCheckbox);
	WMComponents.registry.RegisterElement("GroupPanel", GenGroupPanel);
	WMComponents.registry.RegisterElement("ImagePanel", GenImagePanel)
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
	WMComponents.registry.UnregisterElement("Resizer");
	WMComponents.registry.UnregisterElement("Checkbox");
	WMComponents.registry.UnregisterElement("GroupPanel");
	WMComponents.registry.UnregisterElement("ImagePanel")	
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

