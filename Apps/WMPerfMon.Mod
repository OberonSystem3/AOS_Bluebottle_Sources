MODULE WMPerfMon; (** AUTHOR "TF/staubesv"; PURPOSE "Performance Monitor"; *)
(**
 * Usage: WMPerfMon.Open ~	S.Free WMPerfMon ~
 *
 * History:
 *
 *	16.02.2006	Use WMPerfMonPlugins.Plugin objects  (staubesv)
 *	23.06.2006	Adapted to WMDiagramComponents (staubesv)
 *	20.07.2006	Added MiscPanel (staubesv)
 *	28.07.2006	Adapted to WMPerfMonPlugins & WMPerfMonComponents (staubesv)
 *	06.03.2007	Moved MiscPanel to WMPerfMonTabSystem.SystemTab (staubesv)
 *	23.03.2007	Remove hidden plugins when closing the window (staubesv)
 *)
 
IMPORT
	WMPerfMonPlugins, WMPerfMonComponents, WMPerfMonTabAlerts, WMPerfMonTabSystem,
	WMPerfMonPluginMemory, WMPerfMonPluginCpu, WMPerfMonPluginNetwork, 
	AosNet, AosPlugins,
	AosOut, AosModules, Utilities,
	WMMessages, WMWindowManager, WMRestorable, WMComponents, WMStandardComponents, WMTabComponents, WMRectangles, WMGraphics;

CONST 

	(* Startup width and height of Performance Monitor window *)
	DefaultWidth = 750; DefaultHeight = 400;
	
	(* Scale window if its smaller than this size *)
	MinWidth = 150; MinHeight = 150;
					
	NbrOfTabs = 5;

TYPE
	
	(* Container containing CpuLoad plugins for each CPU and the memory statistics plugin *)
	CpuMemoryComponent =  OBJECT(WMPerfMonComponents.PluginContainer)

		PROCEDURE LocatePlugins*() : BOOLEAN;
		VAR 
			par : WMPerfMonPlugins.Parameter; ml : WMPerfMonPluginMemory.MemoryLoad; 
			cpar : WMPerfMonPluginCpu.CpuParameter; c : WMPerfMonPluginCpu.CpuLoad;
			i : LONGINT;
		BEGIN
			FOR i := 0 TO WMPerfMonPluginCpu.nbrOfCpus-1 DO
				NEW(cpar); cpar.processorID := i; cpar.hide := TRUE; NEW(c, cpar);
				AddPlugin(c, WMPerfMonComponents.GraphView);
			END;
			NEW(par); par.hide := TRUE; NEW(ml, par); AddPlugin(ml, WMPerfMonComponents.GraphView); 	
			RETURN TRUE;
		END LocatePlugins;

	END CpuMemoryComponent;

	(* Container containing NetSend/NetReceive plugins for each link device *)
	NetworkComponent = OBJECT(WMPerfMonComponents.PluginContainer)
		
		PROCEDURE LocatePlugins*() : BOOLEAN;
		VAR 
			npar : WMPerfMonPluginNetwork.NetParameter; ns : WMPerfMonPluginNetwork.NetSend; nr : WMPerfMonPluginNetwork.NetReceive;
			table : AosPlugins.Table; dev : AosNet.LinkDevice; 
			i : LONGINT;
		BEGIN
			AosNet.registry.GetAll(table);
			IF table # NIL THEN
				FOR i := 0 TO LEN(table)-1 DO
					dev := table[i] (AosNet.LinkDevice);
					NEW(npar); npar.hide := TRUE; npar.device := dev; NEW(nr, npar); AddPlugin(nr, WMPerfMonComponents.GraphView);
					NEW(npar); npar.hide := TRUE; npar.device := dev; NEW(ns, npar); AddPlugin(ns, WMPerfMonComponents.GraphView);
				END;
				RETURN TRUE;
			END;
			RETURN FALSE;
		END LocatePlugins;
	
	END NetworkComponent;
	
TYPE 

	KillerMsg = OBJECT 
	END KillerMsg;

	Window = OBJECT (WMComponents.FormWindow)
	VAR 
		tabs : WMTabComponents.Tabs;
		tabList : ARRAY NbrOfTabs OF WMTabComponents.Tab;
		tabPanels : ARRAY NbrOfTabs OF WMComponents.VisualComponent;
		
		tabPanel : WMStandardComponents.Panel;
		curTabPanel : WMComponents.VisualComponent;
		curTab : WMTabComponents.Tab;
	
		cpuMemory : CpuMemoryComponent;
		network : NetworkComponent;
		selection : WMPerfMonComponents.SelectionComponent;
		
		width, height : LONGINT;
		
		PROCEDURE Resized(width, height : LONGINT);
		BEGIN
			IF (width >= MinWidth) & (height >= MinHeight) THEN 
				scaling := FALSE; 
				SELF.width := width; SELF.height := height;
			ELSE
				scaling := TRUE; 
			END; 
			Resized^(width, height);
		END Resized;
						
		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR 
			panel : WMStandardComponents.Panel; 
			alerts : WMPerfMonTabAlerts.AlertsTab; systemPanel : WMPerfMonTabSystem.SystemTab;
			caption : Utilities.String; i : LONGINT;
		BEGIN
			panel := WMPerfMonComponents.NewPanel(WMComponents.AlignClient, 0, 0);
			
			NEW(tabs);  tabs.bounds.SetHeight(20); tabs.alignment.Set(WMComponents.AlignTop);
			tabs.onSelectTab.Add(TabSelected); 
			IF ~WMPerfMonComponents.UseSkinColors THEN
				tabs.clTextDefault.Set(WMGraphics.White);
				tabs.clTextHover.Set(WMGraphics.Black);
				tabs.clTextSelected.Set(WMGraphics.Black);
				tabs.clHover.Set(WMGraphics.White);
				tabs.clSelected.Set(WMGraphics.White);
			END;
			panel.AddContent(tabs);

			NEW(tabPanel); tabPanel.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(tabPanel);
			
			NEW(cpuMemory); tabPanels[0] := cpuMemory; cpuMemory.bearing.Set(WMRectangles.MakeRect(2,5,2,2));
			NEW(network); tabPanels[1] := network; network.bearing.Set(WMRectangles.MakeRect(2,5,2,2));
			NEW(systemPanel); tabPanels[2] := systemPanel;
			NEW(selection); tabPanels[3] := selection;
			NEW(alerts); tabPanels[4] := alerts;

			FOR i := 0 TO NbrOfTabs-1 DO
				tabPanels[i].alignment.Set(WMComponents.AlignClient);
				tabPanels[i].visible.Set(FALSE);
				tabList[i] := tabs.NewTab(); tabs.AddTab(tabList[i]);
				IF ~WMPerfMonComponents.UseSkinColors THEN tabs.SetTabColor(tabList[i], WMGraphics.Black); END;
				CASE i OF
					(* Note: Characters used for caption must be allowed in XML attributes *)
					|0: caption := Utilities.NewString("CPU/Memory");
					|1: caption := Utilities.NewString("Network");
					|2: caption := Utilities.NewString("System");
					|3: caption := Utilities.NewString("Plugins");
					|4: caption := Utilities.NewString("Alerts");
				ELSE
					caption := Utilities.NewString("Unnamed");
				END;
				tabs.SetTabCaption(tabList[i], caption);
				tabs.SetTabData(tabList[i], tabPanels[i]);
			END;
			
			tabPanel.AddContent(cpuMemory); curTabPanel := cpuMemory; curTab := tabList[0]; curTabPanel.visible.Set(TRUE); 
			RETURN panel
		END CreateForm;
		
		PROCEDURE TabSelected(sender, data : ANY);
		VAR tab : WMTabComponents.Tab;
		BEGIN
			IF (data # NIL) & (data IS WMTabComponents.Tab) THEN
				DisableUpdate;
				tab := data(WMTabComponents.Tab);
				IF (tab.data # NIL) & (tab.data IS WMComponents.VisualComponent) THEN
					curTabPanel.visible.Set(FALSE);
					tabPanel.RemoveContent(curTabPanel);
					curTab := tab;
					curTabPanel := tab.data(WMComponents.VisualComponent);
					curTabPanel.visible.Set(TRUE);
					tabPanel.AddContent(curTabPanel);
					tabPanel.Reset(SELF, NIL);
					tabPanel.AlignSubComponents;
				END;
				EnableUpdate;
				tabPanel.Invalidate;
				curTabPanel.Invalidate;
			END;
		END TabSelected; 
				
		PROCEDURE SelectTabByName(name : ARRAY OF CHAR);
		VAR i : LONGINT;
		BEGIN
			LOOP
				IF i >= LEN(tabList) THEN EXIT; END;
				IF (tabList[i] # NIL) & (Utilities.Match(name, tabList[i].caption^)) THEN EXIT; END;
				INC(i);
			END;
			IF i < LEN(tabList) THEN tabs.Select(tabList[i]); TabSelected(SELF, tabList[i]); END;
		END SelectTabByName;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		VAR elem, data : WMRestorable.XmlElement;
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF x.ext IS WMRestorable.Storage THEN
					NEW(data); data.SetName("Data");
					NEW(elem); elem.SetName("Configuration"); data.AddContent(elem);
					WMRestorable.StoreLongint(elem, "SampleInterval", WMPerfMonPlugins.updater.sampleInterval);
					WMRestorable.StoreLongint(elem, "SampleBufferSize", WMPerfMonPlugins.updater.sampleBufferSize);
					WMRestorable.StoreLongint(elem, "ScreenInterval", WMPerfMonPlugins.updater.screenInterval);
					WMRestorable.StoreString(elem, "CurrentTab", curTab.caption^);
					NEW(elem); elem.SetName("Size"); data.AddContent(elem);
					WMRestorable.StoreLongint(elem, "Width", width);
					WMRestorable.StoreLongint(elem, "Height", height);
					x.ext(WMRestorable.Storage).Add("WMPerfMon", "WMPerfMon.Restore", SELF, data);
				ELSIF x.ext IS KillerMsg THEN
					Close;
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;		
		
		PROCEDURE Close;
		VAR i : LONGINT;
		BEGIN
			FOR i := 0 TO LEN(tabPanels)-1 DO 
				IF tabPanels[i] # curTabPanel THEN tabPanels[i].Finalize; END;
			END;
			WMPerfMonPlugins.updater.RemoveAllHidden;
			Close^; 
			DecCount;
		END Close;
		
		PROCEDURE &New(c : WMRestorable.Context);
		VAR 
			vc : WMComponents.VisualComponent; 
			configuration, size : WMRestorable.XmlElement;
			curTabName : ARRAY 32 OF CHAR;
			si, sbs, scri : LONGINT;
			scale : BOOLEAN;
		BEGIN
			vc := CreateForm(); scaling := FALSE; scale := FALSE;
			IF c # NIL THEN
				width := c.r - c.l; height :=  c.b - c.t;
				size := WMRestorable.GetElement(c, "Data\Size");
				IF size # NIL THEN
					WMRestorable.LoadLongint(size, "Width", width);
					WMRestorable.LoadLongint(size, "Height", height);
					IF (width < MinWidth) OR (height < MinHeight) THEN
						scale := TRUE;
					END;
				END;
			ELSE
				width := DefaultWidth; height := DefaultHeight;
			END;

			Init(width, height, FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Performance Monitor 2.0"));
	
			IF c # NIL THEN 
				WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame});
				configuration := WMRestorable.GetElement(c, "Data\Configuration");
				IF configuration # NIL THEN
					WMRestorable.LoadLongint(configuration, "SampleInterval", si);
					WMRestorable.LoadLongint(configuration, "SampleBufferSize", sbs);
					WMRestorable.LoadLongint(configuration, "ScreenInterval", scri);
					WMRestorable.LoadString(configuration, "CurrentTab", curTabName);
				END;
				IF (si # 0) & (sbs # 0) & (scri # 0) THEN 
					WMPerfMonPlugins.updater.SetIntervals(si, sbs, scri); 
				ELSE 
					AosOut.String("WMPerfMon: Could not restore config data."); AosOut.Ln;
				END;
				IF curTabName # "" THEN SelectTabByName(curTabName); END;
				IF scale THEN Resized(c.r - c.l, c.b - c.t); END;
			ELSE 
				WMWindowManager.DefaultAddWindow(SELF);
				SelectTabByName("CPU/Memory");
			END; 
			IncCount;
		END New;
								
	END Window;
		
VAR
	nofWindows : LONGINT;

PROCEDURE Open*(par : ANY) : ANY;
VAR w : Window;
BEGIN
	NEW(w, NIL);
	RETURN NIL; 
END Open;

PROCEDURE Restore*(par : ANY) : ANY;
VAR w : Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(w, par (WMRestorable.Context)); 
	END; 
	RETURN NIL 
END Restore;

PROCEDURE IncCount;
BEGIN {EXCLUSIVE}
	INC(nofWindows);
END IncCount;		

PROCEDURE DecCount;
BEGIN {EXCLUSIVE}
	DEC(nofWindows);
END DecCount;		

PROCEDURE Cleanup;
VAR die : KillerMsg; msg : WMMessages.Message; m : WMWindowManager.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die); msg.ext := die; msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END WMPerfMon.

WMPerfMon.Open ~ 	S.Free WMPerfMon ~

PC0.Compile \s
WMPerfMonPlugins.Mod
WMPerfMonPluginMemory.Mod WMPerfMonPluginCpu.Mod WMPerfMonPluginNetwork.Mod
WMPerfMonPluginHeap.Mod
WMPerfMonPluginUsb.Mod WMPerfMonPluginDisks.Mod
WMPerfMonPluginMessages.Mod
WMPerfMonPluginNetStats.Mod
WMPerfMonPluginLocks.Mod
WMPerfMonPluginActive.Mod
WMPerfMonPluginSerials.Mod
WMPerfMonPluginHTTPServer.Mod WMPerfMonPluginFTPServer.Mod WMPerfMonPluginQuoteServer.Mod WMPerfMonPluginVNCServer.Mod
WMPerfMonPluginExample.Mod
WMPerfMonPluginPerfMon.Mod
WMPerfMonPluginEvents.Mod
WMPerfMonPluginModVars.Mod
WMPerfMonAlerts.Mod
WMPerfMonTabAlerts.Mod
WMPerfMonTabSystem.Mod
WMPerfMonComponents.Mod
WMPerfMon.Mod
~

S.Free
	WMPerfMon WMPerfMonTabSystem WMPerfMonTabAlerts
	WMPerfMonAlerts
	WMPerfMonComponents
	WMPerfMonPluginMessages WMPerfMonPluginExample WMPerfMonPluginHeap WMPerfMonPluginModVars
	WMPerfMonPluginUsb WMPerfMonPluginDisks
	WMPerfMonPluginPerfMon WMPerfMonPluginEvents
	WMPerfMonPluginCpu WMPerfMonPluginMemory WMPerfMonPluginNetwork WMPerfMonPluginNetStats WMPerfMonPluginLocks
	WMPerfMonPluginSerials WMPerfMonPluginActive
	WMPerfMonPluginHTTPServer WMPerfMonPluginFTPServer
	WMPerfMonPluginPerfMon
	WMPerfMonPlugins
	WMDiagramComponents
~

PET.Open 
	WMPerfMonPlugins.Mod WMPerfMonComponents.Mod WMPerfMon.Mod WMPerfMonAlerts.Mod WMPerfMonTabAlerts.Mod WMPerfMonTabSystem.Mod
	WMPerfMonPluginCpu.Mod WMPerfMonPluginMemory.Mod WMPerfMonPluginNetwork.Mod WMPerfMonPluginNetStats.Mod WMPerfMonPluginLocks.Mod
	WMPerfMonPluginUsb.Mod WMPerfMonPluginDisks.Mod WMPerfMonPluginSerials.Mod WMPerfMonPluginActive.Mod
	WMPerfMonPluginHTTPServer.Mod WMPerfMonPluginFTPServer.Mod WMPerfMonPluginHeap.Mod
	WMPerfMonPluginMessages.Mod WMPerfMonPluginExample.Mod WMPerfMonPluginPerfMon.Mod WMPerfMonPluginEvets.Mod WMPerfMonPluginModVars.Mod
~

AosTar.Create WMPerfMon.Tar
WMPerfMonPlugins.Mod WMPerfMonComponents.Mod
WMPerfMonPluginMessages.Mod
WMPerfMonPluginUsb.Mod WMPerfMonPluginDisks.Mod WMPerfMonPluginSerials.Mod
WMPerfMonPluginCpu.Mod WMPerfMonPluginMemory.Mod WMPerfMonPluginNetwork.Mod WMPerfMonPluginNetStats.Mod WMPerfMonPluginLocks.Mod
WMPerfMonPluginActive.Mod WMPerfMonPluginHeap.Mod
WMPerfMonPluginHTTPServer.Mod WMPerfMonPluginFTPServer.Mod
WMPerfMonPluginExample.Mod WMPerfMonPluginPerfMon.Mod WMPerfMonPluginEvents.Mod WMPerfMonPluginModVars.Mod
WMPerfMonAlerts.Mod WMPerfMonTabAlerts.Mod 
WMPerfMonTabSystem.Mod
WMPerfMon.Mod
~