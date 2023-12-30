MODULE MainMenu; (** AUTHOR "TF"; PURPOSE "Menu for Bluebottle"; *)

IMPORT
	AosOut, XML, AosModules, AosFS, AosInputs,
	WMMessages, WMStandardComponents, WMComponents, WMTabComponents,
	WMEditors, Utilities, AosTextUtilities, AosTexts, WMRectangles,
	WM := WMWindowManager;

CONST
	MenuFilePrefix = "MenuPage";

TYPE
	KillerMsg = OBJECT
	END KillerMsg;

	Window* = OBJECT (WMComponents.FormWindow)
	VAR
		tabs : WMTabComponents.Tabs;
		pages : ARRAY 100 OF WMComponents.VisualComponent;
		tabList : ARRAY 100 OF WMTabComponents.Tab;
		currentPage : WMComponents.VisualComponent;
		currentPageNr : LONGINT;
		page : WMStandardComponents.Panel;
		form : WMComponents.VisualComponent;

		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			toolbar, pagePanel : WMStandardComponents.Panel;
			tabs : WMTabComponents.Tabs;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(1024, 60); panel.fillColor.Set(0); panel.takesFocus.Set(TRUE);

		(*	NEW(toolbar); toolbar.bounds.SetWidth(60); toolbar.alignment.Set(WMComponents.AlignLeft); 
			panel.AddContent(toolbar);
			NEW(refresh); refresh.caption.SetAOC("reload"); refresh.bounds.SetHeight(20);
			refresh.alignment.Set(WMComponents.AlignBottom); toolbar.AddContent(refresh); *)
			
			NEW(tabs); tabs.fillColor.Set(000600080H); tabs.bounds.SetHeight(20); tabs.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(tabs);
			SELF.tabs := tabs;
			
			NEW(pagePanel); pagePanel.fillColor.Set(0H); pagePanel.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(pagePanel);
			page := pagePanel;
			
			RETURN panel
		END CreateForm;

		PROCEDURE &New();
		VAR vc : WMComponents.VisualComponent;
			view : WM.ViewPort;
		BEGIN
			vc := CreateForm();
			form := vc;
			currentPageNr := -1;
			tabs.onSelectTab.Add(TabSelected);
		(*	refresh.onClick.Add(Refresh); *)

			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), TRUE);
			SetContent(vc);
			pointerThreshold := 10;
			manager := WM.GetDefaultManager();
			view := WM.GetDefaultView();
			manager.Add(ENTIER(view.range.l), ENTIER(view.range.b) - GetHeight(), SELF, {});
		END New;

		PROCEDURE SetOriginator*(extView : ANY);
		VAR view : WM.ViewPort;
		BEGIN
			IF (extView # NIL) & (extView IS WM.ViewPort) THEN
				view := extView(WM.ViewPort)
			ELSE view := WM.GetDefaultView()
			END;
			Refresh(NIL, NIL);
			manager.SetWindowPos(SELF, ENTIER(view.range.l), ENTIER(view.range.b) - GetHeight());
			manager.ToFront(SELF)
		END SetOriginator;

		PROCEDURE UpdatePages;
		VAR i : LONGINT;
			tab : WMTabComponents.Tab;
			s : Utilities.String;
		BEGIN
			tabs.RemoveAllTabs;
			IF currentPage # NIL THEN page.RemoveContent(currentPage);
				currentPage := NIL
			END;
			IF currentPageNr >= 0 THEN currentPage := pages[currentPageNr] END;
			FOR i := 0 TO 99 DO
				tabList[i] := NIL;
				IF pages[i] # NIL THEN
					pages[i].alignment.Set(WMComponents.AlignClient);
					tab := tabs.NewTab();
					tabs.AddTab(tab);
					tabList[i] := tab;
					s := pages[i].GetAttributeValue("caption");
					IF s = NIL THEN s := Utilities.NewString("Untitled") END;
					tabs.SetTabCaption(tab, s);
					tabs.SetTabData(tab, pages[i])
				END
			END;
			IF currentPage = NIL THEN
				i := 0; 
				WHILE (i < 100) & (currentPage = NIL) DO
					IF pages[i] # NIL THEN currentPage := pages[i]; currentPageNr := i END;
					INC(i);
				END
			END;
			IF currentPage # NIL THEN
				IF ~currentPage.initialized THEN currentPage.Initialize END;
				page.AddContent(currentPage);
				currentPage.Reset(SELF, NIL);
				page.AlignSubComponents;
				page.Invalidate;
				IF tabList[currentPageNr] # NIL THEN tabs.Select(tabList[currentPageNr]) END
			END;
		END UpdatePages;

		PROCEDURE TryLoad(name : ARRAY OF CHAR; pos : LONGINT);
		VAR x : XML.Content;
		BEGIN
			IF (pos >= 0) & (pos < 99) THEN
				x := WMComponents.Load(name);
				IF x # NIL THEN
					IF x IS WMComponents.VisualComponent THEN
						pages[pos] := x(WMComponents.VisualComponent);
				 	END
				 END
			END
		END TryLoad;

		PROCEDURE LoadPages*;
		VAR mask : ARRAY 64 OF CHAR;
			name : ARRAY 256 OF CHAR; flags : SET;
			time, date, size : LONGINT;
			i, j : LONGINT;
			enumerator : AosFS.Enumerator;
			
			PROCEDURE IsNum(ch : CHAR) : BOOLEAN;
			BEGIN
				RETURN (ch >= '0') & (ch <= '9')
			END IsNum;
	
		BEGIN
			NEW(enumerator);
			FOR i := 0 TO 99 DO
				IF pages[i] = currentPage THEN currentPageNr := i END;
				pages[i] := NIL 
			END;
			mask := MenuFilePrefix;
			i := Utilities.Length(mask);
			Utilities.Append(mask, "*.XML");
			enumerator.Open(mask, {});
			WHILE enumerator.HasMoreEntries() DO
				IF enumerator.GetEntry(name, flags, time, date, size) THEN
					i := Utilities.Length(name);
					IF IsNum(name[i - 6]) & IsNum(name[i - 5]) (* & (Utilities.Length(name) = (i + 6)) *) THEN
						TryLoad(name, (ORD(name[i - 6]) - ORD('0')) * 10 + (ORD(name[i - 5]) - ORD('0')));
					END
				END
			END;
			enumerator.Close;
			UpdatePages
		END LoadPages;

		PROCEDURE Refresh(sender, data : ANY);
		BEGIN
			DisableUpdate;
			LoadPages;
			EnableUpdate;
			form.Invalidate
		END Refresh;

		PROCEDURE TabSelected(sender, data : ANY);
		VAR tab : WMTabComponents.Tab;
		BEGIN
			IF (data # NIL) & (data IS WMTabComponents.Tab) THEN
				DisableUpdate;
				page.RemoveContent(currentPage);
				tab := data(WMTabComponents.Tab);
				IF (tab.data # NIL) & (tab.data IS WMComponents.VisualComponent) THEN
					currentPage := tab.data(WMComponents.VisualComponent);
					page.AddContent(currentPage);
					IF ~currentPage.initialized THEN currentPage.Initialize END;
					currentPage.Reset(SELF, NIL);
					page.AlignSubComponents;
				END;
				EnableUpdate;
				page.Invalidate
			END	
		END TabSelected;

		PROCEDURE Close;
		BEGIN
			Close^;
			window := NIL
		END Close;

	END Window;
	
(* the starter decouples the sensitive callback from the WindowManager. *)
TYPE Starter = OBJECT
	VAR originator : ANY;
	
	PROCEDURE &Init(o : ANY);
	BEGIN
		originator := o
	END Init;
	
	BEGIN {ACTIVE}
		IF Open(originator) = NIL THEN END
	END Starter;

VAR
	window : Window;
	manager : WM.WindowManager;

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

PROCEDURE Open*(par : ANY) : ANY;
VAR w : Window;
BEGIN
	BEGIN {EXCLUSIVE}
		IF window = NIL THEN NEW(window); w := window; 
		ELSE window.SetOriginator(par)
		END;
	END;
	IF w # NIL THEN w.LoadPages END;
	RETURN NIL
END Open;

PROCEDURE Cleanup;
BEGIN {EXCLUSIVE}
	AosOut.String("Cleanup"); AosOut.Ln; 
	(* removal must be done in all cases to avoid system freeze *)
	manager.RemoveMessagePreview(MessagePreview);
	IF window # NIL THEN window.Close  END;
END Cleanup;

BEGIN
	manager := WM.GetDefaultManager();
	AosModules.InstallTermHandler(Cleanup)
END MainMenu.

S.Free MainMenu WMTabComponents ~
MainMenu.Open ~
