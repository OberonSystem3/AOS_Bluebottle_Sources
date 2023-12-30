MODULE WMClock;
(** 
 * History:
 *
 *	08.01.2007	Store viewMode when saving desktop, adapted to WMRestorable (staubesv)
 *)
 
IMPORT 
	WM := WMWindowManager, WMGraphics, WMGraphicUtilities, WMRectangles, WMPopups,
	WMRestorable, WMMessages, WMComponents, WMProperties, WMStandardComponents, Utilities, AosKernel, AosModules, AosActive;

CONST
	ViewModeStandard* = 0;
	ViewModeDateTime* = 1;
	ViewModeAnalog* = 2;
	ToggleColor = 99;
	
TYPE
	ContextMenuPar = OBJECT
	VAR
		mode : LONGINT;
	PROCEDURE &New(m : LONGINT); BEGIN mode := m END New;
	END ContextMenuPar;

	ClockWindow = OBJECT(WMComponents.FormWindow);
	VAR
		dragging : BOOLEAN;
		lastX, lastY : LONGINT;
		clockComponent : ClockComponent;
		contextMenu : WMPopups.Popup;

		PROCEDURE &New(c : WMRestorable.Context);
		VAR configuration : WMRestorable.XmlElement; viewMode, color : LONGINT;
		BEGIN
			Init(120, 40, TRUE); 
			manager := WM.GetDefaultManager();
	          
			NEW(clockComponent);
			clockComponent.alignment.Set(WMComponents.AlignClient);
			SetContent(clockComponent);
			
			IF (c # NIL) THEN
				WMRestorable.AddByContext(SELF, c, {WM.FlagStayOnTop});
				configuration := WMRestorable.GetElement(c, "Configuration");
				IF configuration # NIL THEN
					WMRestorable.LoadLongint(configuration, "color", color); clockComponent.color.Set(color);
					WMRestorable.LoadLongint(configuration, "viewMode", viewMode); clockComponent.viewMode.Set(viewMode);
				END;
			ELSE  WM.ExtAddWindow(SELF, 50, 50, 	{WM.FlagStayOnTop})
			END;	
		END New;
		
		PROCEDURE PointerDown*(x, y:LONGINT; keys:SET);
		BEGIN
			lastX := bounds.l+x; lastY:=bounds.t+y;
			IF keys = {0} THEN
				dragging := TRUE
			ELSIF keys = {2} THEN
				NEW(contextMenu);
				contextMenu.Add("Close", HandleClose);
				contextMenu.AddParButton("Time", HandleToggleView, contextMenuParStandard);
				contextMenu.AddParButton("Date", HandleToggleView, contextMenuParDateTime);
				contextMenu.AddParButton("Day of Week", HandleToggleView, contextMenuParAnalog);
				contextMenu.AddParButton("Toggle Color", HandleToggleColor, contextToggleColor);
				contextMenu.Popup(bounds.l+x, bounds.t+y)
			END
		END PointerDown;
		
		PROCEDURE HandleClose(sender, par: PTR);
		VAR manager : WM.WindowManager;
		BEGIN
			manager := WM.GetDefaultManager();
			manager.SetFocus(SELF);
			Close;
		END HandleClose;
		
		PROCEDURE HandleToggleColor(sender, data: ANY);
		BEGIN
			IF (clockComponent.color.Get() = 0FFH) THEN clockComponent.color.Set(0FFFFFFFFH) ELSE clockComponent.color.Set(0FFH) END;
		END HandleToggleColor;
		
		PROCEDURE HandleToggleView(sender, par: PTR);
		VAR manager : WM.WindowManager;
		BEGIN
			manager := WM.GetDefaultManager();
			manager.SetFocus(SELF);
			IF (par # NIL) & (par IS ContextMenuPar) THEN
				clockComponent.viewMode.Set(par(ContextMenuPar).mode)
			ELSE
				clockComponent.viewMode.Set(ViewModeStandard)
			END
		END HandleToggleView;
		
		PROCEDURE PointerMove*(x,y:LONGINT; keys:SET);
		VAR dx, dy : LONGINT;
		BEGIN
			IF dragging THEN 
				x := bounds.l + x; y := bounds.t + y; dx := x - lastX; dy := y - lastY;
				lastX := lastX + dx; lastY := lastY + dy;
				IF (dx # 0) OR (dy # 0) THEN manager.SetWindowPos(SELF, bounds.l + dx, bounds.t + dy) END
			END
		END PointerMove;				
		
		PROCEDURE PointerUp*(x, y:LONGINT; Keys:SET);
		BEGIN
			dragging := FALSE
		END PointerUp;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		VAR configuration : WMRestorable.XmlElement;
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS WMRestorable.Storage) THEN
					NEW(configuration); configuration.SetName("Configuration");
					WMRestorable.StoreLongint(configuration, "color", clockComponent.color.Get());
					WMRestorable.StoreLongint(configuration, "viewMode", clockComponent.viewMode.Get());
					x.ext(WMRestorable.Storage).Add("WMClock", "WMClock.Open", SELF, configuration)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;	
		
	END ClockWindow;
	
	ClockComponent* = OBJECT(WMComponents.VisualComponent)
	VAR
		str, format : Utilities.String;
		t : AosKernel.Timer;
		running, terminated : BOOLEAN;
		viewMode*, color* : WMProperties.Int32Property;
			
		PROCEDURE Finalize;
		BEGIN
			running := FALSE;
			t.Wakeup;
			BEGIN {EXCLUSIVE}
				AWAIT(terminated)
			END
		END Finalize;
		
		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		BEGIN
			DrawBackground^(canvas);
			canvas.SetColor(color.Get());
			WMGraphicUtilities.DrawRect(canvas, GetClientRect(), color.Get(), WMGraphics.ModeCopy);
			WMGraphics.DrawStringInRect(canvas, GetClientRect(), FALSE, WMGraphics.AlignCenter, WMGraphics.AlignCenter, str^)
		END DrawBackground;
		
		PROCEDURE PropertyChanged*(sender, property: PTR);
		VAR vmValue : LONGINT;
		BEGIN
			IF property = viewMode THEN
				vmValue := viewMode.Get();
				IF vmValue = ViewModeStandard THEN COPY("hh:nn:ss", format^)
				ELSIF vmValue = ViewModeDateTime THEN COPY("dd.mm.yy", format^)
				ELSIF vmValue = ViewModeAnalog THEN COPY("www dd.", format^)
				END;
				t.Wakeup;
				Invalidate;
			ELSIF property = color THEN
				Invalidate;
			ELSE
				PropertyChanged^(sender, property);
			END
		END PropertyChanged;
		
		PROCEDURE Init;
		BEGIN
			Init^;
			NEW(viewMode, prototypeViewMode, NIL, NIL); properties.Add(viewMode);
			NEW(color, prototypeColor, NIL, NIL); properties.Add(color);
			color.Set(0FFH);
		END Init;
		
		PROCEDURE Initialize;
		BEGIN
			Initialize^;
			viewMode.Set(ViewModeStandard);
			BEGIN {EXCLUSIVE}
				running := TRUE
			END
		END Initialize;
		
	BEGIN {ACTIVE}
		NEW(str, 10); NEW(format, 10);
		NEW(t);
		SetFont(WMGraphics.GetFont("Oberon", 24, {WMGraphics.FontBold}));
		
		BEGIN {EXCLUSIVE}
			AWAIT(running)
		END;
		terminated := FALSE;
		WHILE running DO
			Utilities.FormatDateTime(format^, Utilities.Now(), str^);
			Invalidate;
			IF viewMode.Get() = ViewModeDateTime THEN t.Sleep(5000)
			ELSE t.Sleep(500)
			END
		END;
		BEGIN {EXCLUSIVE}
			terminated := TRUE
		END
	END ClockComponent;
	
	ClockWindowNode = OBJECT
		VAR
			clockWindow : ClockWindow;
			next : ClockWindowNode;
		PROCEDURE &New(cw : ClockWindow);
		BEGIN
			clockWindow := cw 
		END New;
	END ClockWindowNode;
	
VAR
	clockWindow : ClockWindow;
	firstNode, lastNode : ClockWindowNode;
	prototypeViewMode : WMProperties.Int32Property;
	prototypeColor : WMProperties.Int32Property;
	contextMenuParStandard, contextMenuParDateTime, contextMenuParAnalog, contextToggleColor : ContextMenuPar;

PROCEDURE Open*(par : ANY) : ANY;
VAR
	newNode : ClockWindowNode;
BEGIN {EXCLUSIVE}
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(clockWindow, par(WMRestorable.Context))
	ELSE NEW(clockWindow, NIL)
	END;
	NEW(newNode, clockWindow);
	IF firstNode = NIL THEN
		firstNode := newNode
	ELSE
		lastNode.next := newNode
	END;
	lastNode := newNode;
	RETURN NIL
END Open;

PROCEDURE CloseAll*;
VAR
	current : ClockWindowNode;
BEGIN
	AosActive.SetPriority(AosActive.Low); (* garantees that the active object terminates before the module is unloaded *)
	current := firstNode;
	WHILE current # NIL DO
		current.clockWindow.Close;
		current := current.next
	END;
	AosActive.SetPriority(AosActive.Normal)
END CloseAll;

BEGIN
	NEW(contextMenuParStandard, ViewModeStandard);
	NEW(contextMenuParDateTime, ViewModeDateTime);
	NEW(contextMenuParAnalog, ViewModeAnalog);
	NEW(contextToggleColor, ToggleColor);
	AosModules.InstallTermHandler(CloseAll);
	NEW(prototypeColor, NIL, WMStandardComponents.NewString("Color"),
		WMStandardComponents.NewString("toggle clock color"));
	NEW(prototypeViewMode, NIL, WMStandardComponents.NewString("ViewMode"),
		WMStandardComponents.NewString("select view mode"));
	prototypeViewMode.Set(-1)
END WMClock.

S.Free WMClock~
WMClock.Init ~