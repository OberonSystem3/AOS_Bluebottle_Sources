MODULE WMPerfMon;

IMPORT
	AosBoot, AosActive, AosOut, AosKernel, AosModules, AosPlugins, AosNet, 
	Utilities, WMMessages, 
	WMWindowManager, WMRestorable, WMComponents, WMStandardComponents,
	WMDiagramComponents;

CONST 
	InfoPanelHeight = 165;
	Buckets = 10;

TYPE
	NetStatistics = OBJECT
	VAR
		bucket : LONGINT;
		sendBuckets, recvBuckets: ARRAY Buckets  OF LONGINT;

		l : AosNet.LinkDevice;
		 m0, m1 : WMDiagramComponents.PerfMonModel;
		lastSend, lastRecv : HUGEINT;

		avgSend, avgRecv : LONGINT;
		next : NetStatistics;
		
		PROCEDURE &New(l : AosNet.LinkDevice; m0, m1 : WMDiagramComponents.PerfMonModel);
		BEGIN
			SELF.l := l;
			SELF.m0 := m0;
			SELF.m1 := m1;
			lastSend := l.sendCount; lastRecv := l.recvCount
		END New;
		
		PROCEDURE Update;
		VAR ts, tr : HUGEINT;
		BEGIN 
			ts := l.sendCount; tr := l.recvCount;
			
			sendBuckets[bucket] := AosBoot.HIntToLInt(ts - lastSend); lastSend := ts;
			recvBuckets[bucket] := AosBoot.HIntToLInt(tr - lastRecv); lastRecv := tr;
			
			avgSend := avgSend + sendBuckets[bucket];
			avgRecv := avgRecv + recvBuckets[bucket];
			bucket := (bucket + 1) MOD Buckets ;
			avgSend := avgSend - sendBuckets[bucket];
			avgRecv := avgRecv - recvBuckets[bucket];

			m0.Acquire; m0.Put(avgSend / Buckets / 1024); m0.Release;
			m1.Acquire;m1.Put(avgRecv / Buckets / 1024); m1.Release
		END Update;
	
	END NetStatistics;
	
	KernelStatistics = OBJECT
	VAR
		bucket : LONGINT;
		load : ARRAY Buckets OF LONGINT;
		mload : WMDiagramComponents.PerfMonModel;
		sumload: LONGINT;
		
		PROCEDURE &New( mload: WMDiagramComponents.PerfMonModel);
		VAR i : LONGINT;
		BEGIN
			SELF.mload := mload; 
		END New;
		
		PROCEDURE Update;
		BEGIN 
			load[bucket] := AosActive.NumReady() - 1;
			
			sumload := sumload+ load[bucket];
			bucket := (bucket + 1) MOD Buckets ;
			sumload := sumload - load[bucket];

			mload.Acquire; mload.Put(sumload / Buckets); mload.Release;
		END Update;

	END KernelStatistics;

	KillerMsg = OBJECT
	END KillerMsg;
	
	Window* = OBJECT (WMComponents.FormWindow)
	VAR 
		panel : WMStandardComponents.Panel;
		wh : LONGINT;
		cur, statistics : NetStatistics; 
		kernelStats : KernelStatistics;

		timer : AosKernel.Timer;
		alive : BOOLEAN;


		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR load : WMDiagramComponents.PerfViewPanel;
			l : WMStandardComponents.Label;
			p : WMStandardComponents.Panel;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(400, 400); panel.fillColor.Set(0); panel.takesFocus.Set(TRUE);

			NEW(p); p.bounds.SetHeight(75); p.alignment.Set(WMComponents.AlignTop); 
			
			NEW(l); l.alignment.Set(WMComponents.AlignTop); l.bounds.SetHeight(20);
			l.caption.SetAOC("CPU Load (10s sliding avg)");
			l.fillColor.Set(00000AA50H);

			p.AddContent(l);
			
			NEW(load); load.alignment.Set(WMComponents.AlignTop); load.bounds.SetHeight(50);
			load.fillColor.Set(0444444FFH); load.autoMin.Set(FALSE); load.showValues.Set(TRUE);
			load.color.Set(0FF0000FFH);
			p.AddContent(load); 
			INC(wh, 75);
			
			panel.AddContent(p);

			NEW(l); l.alignment.Set(WMComponents.AlignTop); l.bounds.SetHeight(20);
			l.caption.SetAOC("Network devices");
			l.fillColor.Set(00000AA50H);
			panel.AddContent(l); INC(wh, 20);
			
			NEW(kernelStats, load.model);
			RETURN panel
		END CreateForm;
		
		PROCEDURE CreateInfoPanel(ld : AosNet.LinkDevice);
		VAR p : WMStandardComponents.Panel;
			l : WMStandardComponents.Label;
			sperf, rperf : WMDiagramComponents.PerfViewPanel;
			s : NetStatistics;
		BEGIN
			NEW(p); p.bounds.SetExtents(135, InfoPanelHeight); panel.fillColor.Set(0CCCCCCFFH);
			p.alignment.Set(WMComponents.AlignTop);
			
			NEW(l); l.alignment.Set(WMComponents.AlignTop); l.bounds.SetHeight(20);
			l.fillColor.Set(0AAAA0050H);
			l.caption.SetAOC(ld.name);
			p.AddContent(l);
			
			NEW(l); l.alignment.Set(WMComponents.AlignTop); l.bounds.SetHeight(20);
			l.caption.SetAOC("Send (10s sliding avg)");
			p.AddContent(l);

			NEW(sperf); sperf.alignment.Set(WMComponents.AlignTop); sperf.bounds.SetHeight(50);
			sperf.fillColor.Set(0444444FFH); sperf.autoMin.Set(FALSE);
			sperf.showValues.Set(TRUE); sperf.unit.SetAOC("KiB/s");
			p.AddContent(sperf);


			NEW(l); l.alignment.Set(WMComponents.AlignTop); l.bounds.SetHeight(20);
			l.caption.SetAOC("Receive (10s sliding avg)");
			p.AddContent(l);

			NEW(rperf); rperf.alignment.Set(WMComponents.AlignTop); rperf.bounds.SetHeight(50);
			rperf.fillColor.Set(0444444FFH); rperf.autoMin.Set(FALSE);
			rperf.showValues.Set(TRUE); rperf.unit.SetAOC("KiB/s");
			p.AddContent(rperf);
			NEW(s, ld, sperf.model, rperf.model);
			s.next := statistics; statistics := s;
		
			INC(wh, InfoPanelHeight);
			panel.AddContent(p)
		END CreateInfoPanel;

		PROCEDURE Enumerate(p : AosPlugins.Plugin);
		VAR l : AosNet.LinkDevice;
		BEGIN
			IF (p # NIL) & (p IS AosNet.LinkDevice) THEN
				CreateInfoPanel(p(AosNet.LinkDevice))
			END
		END Enumerate;

		PROCEDURE &New(c : WMRestorable.Context);
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			wh := 0;
			IncCount;
			(* To create a multi language app, try loading the respective XML instead of CreateForm()
			if the XML was not found or does not contain all needed elements, use CreateForm as fallback *)
			vc := CreateForm();

			AosNet.registry.Enumerate(Enumerate);
			vc.bounds.SetHeight(Utilities.Max(wh, 10));
						
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), TRUE);
			SetContent(vc);
			
			IF c # NIL THEN WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame})				
			ELSE WMWindowManager.DefaultAddWindow(SELF)
			END;
			SetTitle(Utilities.NewString("Performance Monitor"));
		END New;
		
		PROCEDURE Close;
		BEGIN
			alive := FALSE;
			timer.Wakeup;
			AosActive.Yield;
			DecCount;
			Close^;
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS KillerMsg) THEN Close
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("WMPerfMon", "WMPerfMon.Restore", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;		
		
	BEGIN {ACTIVE}
		AosActive.SetPriority(AosActive.High);
		NEW(timer); alive := TRUE;
		WHILE alive DO 
			timer.Sleep(1000);
			IF alive THEN
				kernelStats.Update;
				cur := statistics;
				WHILE cur # NIL DO cur.Update; cur := cur.next END;
			END	
		END
	END Window;

VAR
	nofWindows : LONGINT;
	
PROCEDURE Open*(par : ANY) : ANY;
VAR w : Window;
BEGIN
	NEW(w, NIL);
	RETURN NIL
END Open;

PROCEDURE Restore*(par : ANY) : ANY;
VAR w : Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(w, par(WMRestorable.Context))
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
VAR die : KillerMsg;
	 msg : WMMessages.Message;
	 m : WMWindowManager.WindowManager;
	 t, i : LONGINT;
BEGIN {EXCLUSIVE}
	t := nofWindows;
	NEW(die); msg.ext := die; msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0);
	FOR i := 0 TO t * 16 DO AosActive.Yield END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMPerfMon.

WMPerfMon.Open  
S.Free  WMPerfMon 
S.Free WMDiagramComponents 

