MODULE StartMenu;

IMPORT
	Utilities, XML, AosOut, AosModules, AosInputs, UTF8Strings, XMLObjects,
	MainMenu, WM := WMWindowManager, WMComponents, WMStandardComponents, WMProperties, WMMessages, WMEvents,
	WMRectangles;
	
CONST
	DefaultPlugin = "BlockStartMenu";
	FancyMenuDesc = "Dummy.XML";
	MaxMenus = 16;
	MaxMenuButtons = 10;
	
TYPE 
	String = Utilities.String;
	EventListenerInfo = WMEvents.EventListenerInfo;
	Message = WMMessages.Message;
	
	Popup = OBJECT (WMComponents.FormWindow)
		
		PROCEDURE FocusLost;
		BEGIN manager.Remove(SELF) END FocusLost;
		
		PROCEDURE FocusGot;
		BEGIN manager.SetFocus(SELF) END FocusGot;
		
		PROCEDURE Handle*(VAR msg : Message); 
		BEGIN
			Handle^(msg);
			IF (msg.msgType = WMMessages.MsgExt) & (msg.ext = closePopupMsg) THEN FocusLost END; 
		END Handle;

	END Popup;
	
	ClosePopupMsg = OBJECT
	END ClosePopupMsg;

	Window = OBJECT(WMComponents.FormWindow)
	VAR plugin : Plugin;
		panel : WMComponents.VisualComponent;
		factory : PluginFactory;
		view : WM.ViewPort;
		startIndex : LONGINT;

		PROCEDURE & New;
		BEGIN
			NEW(panel);
			NEW(factory);
			manager := WM.GetDefaultManager();
			SetPlugin(Utilities.NewString(DefaultPlugin));
			view := WM.GetDefaultView();
			pointerThreshold:= 50;
(*			manager.Add(ENTIER(view.range.l), ENTIER(view.range.b) - GetHeight(), SELF, {});  *)  (* old code *)
			manager.Add(ENTIER(view.range.l), ENTIER(view.range.b) - 255, SELF, {}); 
			startIndex := 0;
		END New;
		
		PROCEDURE SetOriginator*(extView : ANY);
		BEGIN {EXCLUSIVE}
			IF (extView # NIL) & (extView IS WM.ViewPort) THEN
				view := extView(WM.ViewPort)
			ELSE view := WM.GetDefaultView()
			END;
			IF manager = NIL THEN manager := WM.GetDefaultManager() END; 
			manager.SetWindowPos(SELF, ENTIER(view.range.l), ENTIER(view.range.b) - 255);
			manager.ToFront(SELF);
			IF plugin # NIL THEN plugin.Close END;
			plugin.Open
		END SetOriginator;
		
		PROCEDURE CSChanged*;
		BEGIN
			SetPlugin(pluginName.Get())
		END CSChanged;
		
		PROCEDURE PropertyChanged*(sender, prop : ANY);
		BEGIN
			IF prop = pluginName THEN 
				SetPlugin(pluginName.Get()) 
			END
		END PropertyChanged;
		
		PROCEDURE SetPlugin(name : String);
		VAR w, h : LONGINT;
		BEGIN
			IF plugin # NIL THEN
				plugin.Close;
				panel.RemoveContent(plugin)
			END;
			plugin := factory.Get(name);
			startIndex := 0;
			plugin.Open;
			panel.AddContent(plugin);
			w := plugin.bounds.GetWidth();
			h := plugin.bounds.GetHeight();
			manager.SetWindowSize(SELF, w, h);
		END SetPlugin;
		
		PROCEDURE Close;
		BEGIN
			IF plugin # NIL THEN plugin.Close END
		END Close;
		
		PROCEDURE ShiftMenuItems(upwards : BOOLEAN);
		BEGIN
			plugin.ReopenMenuItemsShifted(upwards)
		END ShiftMenuItems;

	END Window;

	PluginFactory = OBJECT
		
		PROCEDURE Get(type : String) : Plugin;
		VAR a : ANY;
		BEGIN
			IF type^ = "FancyStartMenu" THEN
				a := GenFancyStartMenu(NIL); RETURN a(Plugin)
			ELSIF type^ = "BlockStartMenu" THEN
				a := GenBlockStartMenu(NIL); RETURN a(Plugin)
			ELSE (* return default *)
				a := GenBlockStartMenu(NIL); RETURN a(Plugin)
			END
		END Get;
		
	END PluginFactory;
	
	Plugin = OBJECT(WMComponents.VisualComponent)
	
		PROCEDURE Open;
		BEGIN HALT(311) END Open;
		
		PROCEDURE Close;
		BEGIN HALT(311) END Close;
		
		PROCEDURE Refresh(originator : ANY);
		BEGIN HALT(311) END Refresh;
		
		PROCEDURE ReopenMenuItemsShifted(upwards : BOOLEAN);
		BEGIN HALT(311) END ReopenMenuItemsShifted;
		
	END Plugin;
	
	SubMenuOpener* = OBJECT(WMComponents.Component)
	VAR filename : WMProperties.StringProperty;
		eRun* : EventListenerInfo;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(filename, NIL, Utilities.NewString("Filename"), Utilities.NewString("")); properties.Add(filename);
			NEW(eRun, Utilities.NewString("Run"), Utilities.NewString(""), SELF.Run); eventListeners.Add(eRun);
		END Init;
	
		PROCEDURE Run*(sender, par : ANY); (** Eventhandler *) 
		VAR x, y, res : LONGINT; filename : String; msg : ARRAY 128 OF CHAR;
			rect : WMRectangles.Rectangle;
		BEGIN
			(* synchronize if not synchronized *)
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Run, sender, par)
			ELSE
				(* actual business logic *)
				filename := SELF.filename.Get();
				IF filename # NIL THEN
					rect := sender(WMComponents.VisualComponent).bounds.Get();
					x := w.bounds.l + rect.l; 
					y := w.bounds.t + rect.t ; 
(*					AosOut.String("w.bounds.l = ");	AosOut.Int(w.bounds.l, 6); 	AosOut.Ln;
					AosOut.String("rect.l = ");		AosOut.Int(rect.l, 6);		AosOut.Ln;
					AosOut.String("w.bounds.t = ");	AosOut.Int(w.bounds.t, 6);	AosOut.Ln;
					AosOut.String("rect.t = ");		AosOut.Int(rect.t, 6);		AosOut.Ln;
					AosOut.String("x = ");			AosOut.Int(x, 6);			AosOut.Ln;
					AosOut.String("y = ");			AosOut.Int(y, 6);			AosOut.Ln; *)
					OpenPopup(x, y, filename^);
					IF res # 0 THEN AosOut.Enter; AosOut.String(msg); AosOut.Exit END
				 END
			END	
		END Run;
	END SubMenuOpener;	

	MenuButtons =  ARRAY MaxMenuButtons  OF WMStandardComponents.Button;
	SMOArr  =  ARRAY MaxMenuButtons  OF SubMenuOpener;

	FancyStartMenu = OBJECT(Plugin)
	VAR startMenu : WMComponents.FormWindow;
		nofLayouts, nofButtons, nofSMOs : LONGINT;
		menuButtons : MenuButtons;
		smos : SMOArr;
	
		PROCEDURE CountLayouts() : LONGINT;
		VAR i, n : LONGINT; done : BOOLEAN; s : Utilities.String;
		BEGIN
			n := 0; done := FALSE;
			WHILE (i < LEN(layoutNames) - 1) & ~done DO
				s := layoutNames[i].Get();
				IF UTF8Strings.Compare(s^, FancyMenuDesc) # UTF8Strings.CmpEqual THEN
					INC(n)
				ELSE 
					done := TRUE
				END;
				INC(i)
			END;
			RETURN n
		END CountLayouts;
		
		PROCEDURE FindSMO(c : XML.Content; VAR smo : SubMenuOpener);
		VAR enum : XMLObjects.Enumerator; found : BOOLEAN; ptr : PTR;
		BEGIN
			smo := NIL;
			IF c IS WMComponents.VisualComponent THEN
				enum := c(WMComponents.VisualComponent).GetContents();
				found := FALSE;
				WHILE enum.HasMoreElements() & ~found DO
					ptr := enum.GetNext();
					IF ptr IS SubMenuOpener THEN 
						smo := ptr(SubMenuOpener); 
						found := TRUE 
					END
				END
			END;
		END FindSMO;
		
		PROCEDURE FindMenuButtonsSMO(c : XML.Content; VAR menuButtons : MenuButtons; VAR smos: SMOArr; VAR n, m : LONGINT);
		VAR enum : XMLObjects.Enumerator; i, j : LONGINT; ptr : PTR; s : Utilities.String;
			b : WMStandardComponents.Button; smo : SubMenuOpener; 
		BEGIN
			IF c IS WMComponents.VisualComponent THEN
				enum := c(WMComponents.VisualComponent).GetContents();
				i := 0; j := 0; 
				WHILE enum.HasMoreElements() DO
					ptr := enum.GetNext();
					IF ptr IS WMStandardComponents.Button THEN
						b := ptr(WMStandardComponents.Button);
						s := b.caption.Get();
 						IF (s # NIL) & (UTF8Strings.Compare(s^, "") # UTF8Strings.CmpEqual) THEN
							menuButtons[i] := b; INC(i);
							FindSMO(b, smo);
							IF smo # NIL THEN smos[j] := smo; INC(j) END;
						END;
					END;
				END;
				n := i; m := j
			ELSE
				n := 0; m := 0;
			END;
		END FindMenuButtonsSMO;
		
		PROCEDURE Open;
		VAR c : XML.Content; width, height : LONGINT; view : WM.ViewPort; s : String;
			i : LONGINT;
		BEGIN
			nofLayouts := CountLayouts();
			s := layoutNames[w.startIndex].Get();
			AosOut.String("loading "); AosOut.String(s^); AosOut.Ln; 
			c := WMComponents.Load(s^);
			IF (c # NIL) & (c IS WMComponents.VisualComponent) THEN
				FindMenuButtonsSMO(c, menuButtons, smos, nofButtons, nofSMOs);
				width := c(WMComponents.VisualComponent).bounds.GetWidth(); 
				height := c(WMComponents.VisualComponent).bounds.GetHeight();
				NEW(startMenu, width, height, TRUE); 
				startMenu.DisableUpdate;
				startMenu.SetContent(c);
				startMenu.EnableUpdate;
				startMenu.Invalidate(startMenu.bounds);
				view := WM.GetDefaultView();
				manager := WM.GetDefaultManager();
				manager.Add(ENTIER(view.range.l), ENTIER(view.range.b) - height + 1, startMenu, {}); 
			ELSE
				AosOut.String("XML-file not correctly loaded"); AosOut.Ln
			END
		END Open;
		
		PROCEDURE Close;
		BEGIN {EXCLUSIVE}
			IF startMenu # NIL THEN startMenu.Close END
		END Close;
		
		PROCEDURE Refresh(extView: ANY);
		VAR view : WM.ViewPort;
		BEGIN
			IF (extView # NIL) & (extView IS WM.ViewPort) THEN
				view := extView(WM.ViewPort)
			ELSE 
				view := WM.GetDefaultView()
			END;
			manager.SetWindowPos(startMenu, ENTIER(view.range.l), ENTIER(view.range.b) - 255);
		END Refresh;
		
		PROCEDURE ReplaceMenuButtonsSMO(VAR mb, newmb : MenuButtons; VAR smos, newsmos : SMOArr);
		VAR i : LONGINT; s : Utilities.String;
		BEGIN
			FOR i := 0 TO nofButtons - 1 DO
				s := newmb[i].caption.Get();
				mb[i].caption.Set(s);
				s := newsmos[i].filename.Get();
				smos[i].filename.Set(s);
			END;
		END ReplaceMenuButtonsSMO;
		
		PROCEDURE ReopenMenuItemsShifted(upwards : BOOLEAN);
		VAR old, i : LONGINT; s : String; c : XML.Content;
			newMButtons : MenuButtons;
			newsmos : SMOArr;
			n, m : LONGINT;
		BEGIN
			old := w.startIndex;
			IF upwards THEN
				w.startIndex := (w.startIndex + 1) MOD nofLayouts
			ELSE
				w.startIndex := (w.startIndex - 1) MOD nofLayouts
			END;
			IF old # w.startIndex THEN
				s := layoutNames[w.startIndex].Get();
				c := WMComponents.Load(s^);	
				IF (c # NIL) & (c IS WMComponents.VisualComponent) THEN
					FindMenuButtonsSMO(c, newMButtons, newsmos, n, m);
					IF (nofButtons = nofSMOs) & (nofButtons = n) & (nofSMOs = m) THEN
						ReplaceMenuButtonsSMO(menuButtons, newMButtons, smos, newsmos);
						FOR i := 0 TO nofButtons - 1 DO
							menuButtons[i].Invalidate;
						END;
					ELSE
						AosOut.String("layout "); AosOut.String(s^); AosOut.String(" does not match."); AosOut.Ln
					END
				ELSE
					AosOut.String("XML-file not correctly loaded"); AosOut.Ln
				END
			END
		END ReopenMenuItemsShifted;

	END FancyStartMenu;
	
	BlockStartMenu = OBJECT(Plugin)
	VAR startMenu : MainMenu.Window;
	
		PROCEDURE Open;
		BEGIN
			NEW(startMenu);
			startMenu.SetOriginator(NIL);
			startMenu.LoadPages
		END Open;
		
		PROCEDURE Close;
		BEGIN
			IF startMenu # NIL THEN startMenu.Close END
		END Close;
		
		PROCEDURE Refresh(extView: ANY);
		BEGIN
			startMenu.SetOriginator(extView);
			startMenu.LoadPages
		END Refresh;
		
		PROCEDURE ReopenMenuItemsShifted(upwards : BOOLEAN);
		BEGIN
		END ReopenMenuItemsShifted;

	END BlockStartMenu;
	
	(* the starter decouples the sensitive callback from the WindowManager. *) 	
	Starter = OBJECT
	VAR originator : ANY;
	
		PROCEDURE &Init(o : ANY);
		BEGIN
			originator := o
		END Init;
	
	BEGIN {ACTIVE}
		w.SetOriginator(originator)
	END Starter;
	

VAR stringPrototype, pluginName : WMProperties.StringProperty;
	layoutNames : ARRAY MaxMenus OF WMProperties.StringProperty;
	manager : WM.WindowManager;
	w : Window;
	p : Popup;
	closePopupMsg- : ClosePopupMsg;
	
	PROCEDURE OpenPopup*(x, y : LONGINT; filename : ARRAY OF CHAR);
	VAR m : WM.WindowManager;
		 c : XML.Content;
		width, height : LONGINT;
	BEGIN
		c := WMComponents.Load(filename);
		IF (c # NIL) & (c IS WMComponents.VisualComponent) THEN
			width := c(WMComponents.VisualComponent).bounds.GetWidth(); 
			height := c(WMComponents.VisualComponent).bounds.GetHeight();
			IF width <= 0 THEN width := 10 END; IF height <= 0 THEN height := 10 END;
			NEW(p, width, height, TRUE); 
			p.SetContent(c);
			m := WM.GetDefaultManager(); m.Add(x, y-height, p, {}); m.SetFocus(p)
		ELSE
			AosOut.String(filename); AosOut.String(" not correctly loaded"); AosOut.Ln
		END
	END OpenPopup;
	
	PROCEDURE ClosePopup*(par : ANY) : ANY;
	VAR msg : WMMessages.Message; manager : WM.WindowManager;
	BEGIN
		msg.msgType := WMMessages.MsgExt; msg.ext := closePopupMsg;
		manager := WM.GetDefaultManager();		
		manager.Broadcast(msg);		
		RETURN NIL
	END ClosePopup;
	
	PROCEDURE GenSubMenuOpener*(par : ANY) : ANY;
	VAR smo : SubMenuOpener;
	BEGIN
		NEW(smo); RETURN smo
	END GenSubMenuOpener;
	
	PROCEDURE Open*(par : ANY) : ANY;
	BEGIN
		w.SetPlugin(pluginName.Get());
		RETURN NIL
	END Open;

	(* load start menu with buttons shifted to the right *)
	PROCEDURE ShiftMenuItemsRight*(par : ANY) : ANY;
	BEGIN
		w.ShiftMenuItems(TRUE);
		RETURN NIL
	END ShiftMenuItemsRight;

	(* load start menu with buttons shifted to the left *)
	PROCEDURE ShiftMenuItemsLeft*(par : ANY) : ANY;
	BEGIN
		w.ShiftMenuItems(FALSE);
		RETURN NIL
	END ShiftMenuItemsLeft;

	(* This procedure is directly called by the window manager. It must be safe. *)
	PROCEDURE MessagePreview(VAR m : WMMessages.Message; VAR discard : BOOLEAN);
	VAR starter : Starter;
	BEGIN
		IF m.msgType = WMMessages.MsgKey THEN
			IF (m.y = 0FF1BH) & ((m.flags * AosInputs.Ctrl # {}) OR (m.flags * AosInputs.Meta # {})) THEN
				NEW(starter, m.originator); discard := TRUE
			END
		END
	END MessagePreview;

	PROCEDURE GenFancyStartMenu(par : ANY) : ANY;
	VAR menu : FancyStartMenu;
	BEGIN NEW(menu); RETURN menu
	END GenFancyStartMenu;
	
	PROCEDURE GenBlockStartMenu(par : ANY) : ANY;
	VAR menu : BlockStartMenu;
	BEGIN NEW(menu); RETURN menu
	END GenBlockStartMenu;
	
	PROCEDURE InitPrototypes;
	VAR plStartMenu : WMProperties.PropertyList;
		s0, s1 : ARRAY 128 OF CHAR;
		i : LONGINT;
	BEGIN
		NEW(plStartMenu); 	WMComponents.propertyListList.Add("StartMenu", plStartMenu);
		plStartMenu.onPropertyChanged.Add(w.PropertyChanged);
		
		NEW(stringPrototype, NIL, Utilities.NewString("Plugin"), Utilities.NewString("Plug-in-object that creates start-menu and determines its properties")); 
		stringPrototype.Set(Utilities.NewString(DefaultPlugin));	
		NEW(pluginName, stringPrototype, NIL, NIL); plStartMenu.Add(pluginName);

		FOR i := 0 TO LEN(layoutNames) - 1 DO
			Utilities.IntToStr(i, s0);
			COPY("Layout", s1);
			Utilities.Append(s1, s0);
			NEW(stringPrototype, NIL, Utilities.NewString(s1), Utilities.NewString("XML-file that determins content and layout of the fancy start-menu")); 
			stringPrototype.Set(Utilities.NewString(FancyMenuDesc));
			NEW(layoutNames[i], stringPrototype, NIL, NIL); plStartMenu.Add(layoutNames[i]);	
		END;
	END InitPrototypes;
	
	PROCEDURE Cleanup;
	BEGIN
		IF w # NIL THEN w.Close END;
		manager.RemoveMessagePreview(MessagePreview)
	END Cleanup;
	
	PROCEDURE Fancy*(par : ANY) : ANY;
	BEGIN
		pluginName.Set(Utilities.NewString("FancyStartMenu"));
		RETURN NIL
	END Fancy;
	
	PROCEDURE Block*(par : ANY) : ANY;
	BEGIN
		pluginName.Set(Utilities.NewString("BlockStartMenu"));
		RETURN NIL
	END Block;

BEGIN
	NEW(w);
	InitPrototypes;
	AosModules.InstallTermHandler(Cleanup);
	manager := WM.GetDefaultManager();
	manager.InstallMessagePreview(MessagePreview);
	WMComponents.registry.RegisterElement("SubMenuOpener", GenSubMenuOpener)
END StartMenu.
