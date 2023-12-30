MODULE WMPerfMonTabSystem; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor system tab"; *)
(**
 * History:
 *
 *	06.03.2007	Moved SystemPanel from WMPerfMon.Mod into this module, added system information (staubesv)
 *
 *)
 
IMPORT
	Plugins := WMPerfMonPlugins, Perf := WMPerfMonComponents,
	AosBoot, AosHeap, AosActive, AosKernel, AosCommands, AosIO, Utilities,
	WMComponents, WMStandardComponents;
	
TYPE

	SystemTab* = OBJECT(WMComponents.VisualComponent)
	VAR 
		clockrate : LONGINT; (* MHz, -1 if invalid *)
		
		(* GC Statistics *)
		gcCurrentRun : WMStandardComponents.Label;
		line1, line2, line3 : WMStandardComponents.Label;
		
		(* CPU clock rate detection *)
		cpuClockrate : WMStandardComponents.Label;
		
		(* Timers *)
		lastTicks : LONGINT;
		lastTimestamp : HUGEINT;
		lastGcCyclesAllRuns : HUGEINT;
		lastNgc : LONGINT;
		started : BOOLEAN;
		startBtn : WMStandardComponents.Button;
		elapsed : WMStandardComponents.Label;
		
		(* System information *)
		format : ARRAY 32 OF CHAR;
		timeLabel : WMStandardComponents.Label;
		
		(* Performance Monitoring *)
		unloadBtn : WMStandardComponents.Button;
		
		timer : AosKernel.Timer;
		alive, dead : BOOLEAN;
		
		PROCEDURE EstimateClockRate() : LONGINT;
		CONST Tries = 10;
		VAR 
			try : LONGINT; done : BOOLEAN; clockrate : LONGINT;
			string, nbr : ARRAY 128 OF CHAR;
		BEGIN
			cpuClockrate.caption.SetAOC("   CPU clock rate estimation...");
			try := 1; done := FALSE; clockrate := -1;
			WHILE ~done & (try <= Tries) DO
				IF Plugins.EstimateCpuClockrate(clockrate) THEN
					done := TRUE;
				END;
				INC(try);
			END;
			IF done THEN
				string := "   CPU clock rate is ";
				Utilities.IntToStr(clockrate, nbr); Utilities.Append(string, nbr);
				Utilities.Append(string, "MHz (estimated)");
				cpuClockrate.caption.SetAOC(string);
			ELSE
				cpuClockrate.caption.SetAOC("   CPU clock rate estimation failed");
			END;
			RETURN clockrate;
		END EstimateClockRate;
		
		PROCEDURE HandleGcButton(sender, data : ANY);
		VAR 
			string, nbr : ARRAY 128 OF CHAR;
			lastGcCyclesTot : HUGEINT;
			w : AosIO.StringWriter;
		BEGIN
			IF clockrate = -1 THEN clockrate := EstimateClockRate(); END;
						
			lastGcCyclesTot := AosHeap.NgcCyclesAllRuns;
			AosKernel.GC;
			
			string := "   Last run: "; 
			IF clockrate # -1 THEN
				Plugins.MsToString(Plugins.CyclesToMs(AosHeap.NgcCyclesLastRun, clockrate), nbr);
			ELSE
				nbr := "Clockrate unkown";
			END;
			Utilities.Append(string, nbr);
			gcCurrentRun.caption.SetAOC(string);
			
			(* Number of GC runs & total GC time & max time*)
			NEW(w, 128);
			w.String("GC Runs: "); w.Int(AosHeap.Ngc, 0); w.String("   GC Total Time: "); 
			Plugins.MsToString(Plugins.CyclesToMs(AosHeap.NgcCyclesAllRuns, clockrate), nbr); w.String(nbr); 
			w.String("   GC longest run: ");
			Plugins.MsToString(Plugins.CyclesToMs(AosHeap.NgcCyclesMax, clockrate), nbr); w.String(nbr); 
			w.Get(string);
			line1.caption.SetAOC(string);
			
			(* Mark phase *)
			w.Reset;
			w.String("Mark phase: "); w.Int(AosHeap.Nmarked, 0); w.String(" blocks marked in ");
			Plugins.MsToString(Plugins.CyclesToMs(AosHeap.NgcCyclesMark, clockrate), nbr); w.String(nbr);
			w.String(" ("); w.Int(AosHeap.Nmark, 0); w.String(" calls to AosHeap.Mark)");
			w.Get(string);
			line2.caption.SetAOC(string);
			
			(* Sweep phase *)
			w.Reset;
			w.String("Sweep phase: "); w.Int(AosHeap.Nsweeped, 0); w.String(" blocks sweeped in ");
			Plugins.MsToString(Plugins.CyclesToMs(AosHeap.NgcCyclesSweep, clockrate), nbr);
			w.String(nbr); w.Get(string);
			line3.caption.SetAOC(string);			
		END HandleGcButton;
		
		PROCEDURE HandleDetectButton(sender, data : ANY);
		BEGIN
			clockrate := EstimateClockRate();
		END HandleDetectButton;
		
		PROCEDURE HandleTimerButton(sender, data : ANY);
		VAR string, nbr : ARRAY 128 OF CHAR; msTicks, msTimestamp, msGc, msDiff : LONGINT;
		BEGIN
			IF clockrate = -1 THEN clockrate := EstimateClockRate(); END;
			IF started THEN
				started := FALSE; startBtn.caption.SetAOC("Start");
				string := "   Time elapsed: ";
				msTicks := AosActive.ticks - lastTicks; 
				msTimestamp := Plugins.CyclesToMs(AosBoot.SubH(AosBoot.GetTimer(), lastTimestamp), clockrate);
				Plugins.MsToString(msTicks, nbr);
				Utilities.Append(string, nbr); Utilities.Append(string, " (Ticks),  ");
				Plugins.MsToString(msTimestamp ,nbr);
				Utilities.Append(string, nbr); Utilities.Append(string, " (Timestamps), ");
				Utilities.Append(string, "TimeDiff: "); 
				msDiff := msTimestamp - msTicks; IF msDiff < 0 THEN msDiff := -msDiff; END;
				Plugins.MsToString(msDiff, nbr);
				Utilities.Append(string, nbr);
				Utilities.Append(string, ", GC Time: ");
				msGc := Plugins.CyclesToMs(AosBoot.SubH(AosHeap.NgcCyclesAllRuns, lastGcCyclesAllRuns), clockrate);
				Plugins.MsToString(msGc, nbr); Utilities.Append(string, nbr); 
				Utilities.Append(string, ", GC Runs: "); 
				Utilities.IntToStr(AosHeap.Ngc - lastNgc, nbr); Utilities.Append(string, nbr);
				elapsed.caption.SetAOC(string);
			ELSE
				started := TRUE; startBtn.caption.SetAOC("Stop");
				lastTicks := AosActive.ticks;
				lastTimestamp := AosBoot.GetTimer();
				lastGcCyclesAllRuns := AosHeap.NgcCyclesAllRuns;
				lastNgc := AosHeap.Ngc;
				elapsed.caption.SetAOC("   Timer is running...");
			END;
		END HandleTimerButton;
		
		PROCEDURE HandleUnloadButton(sender, data : ANY);
		VAR msg : ARRAY 128 OF CHAR; res : LONGINT;
		BEGIN
			AosCommands.Call("S.FreeDownTo WMPerfMonPlugins", {}, res, msg);
		END HandleUnloadButton;

		PROCEDURE CreateSysinfoPanel() : WMStandardComponents.Panel;
		VAR 
			panel, line : WMStandardComponents.Panel; label : WMStandardComponents.Label;
			caption : ARRAY 128 OF CHAR;
			
			PROCEDURE AppendBoolean(VAR string : ARRAY OF CHAR; value : BOOLEAN);
			BEGIN
				IF value THEN
					Utilities.Append(string, "Yes");
				ELSE
					Utilities.Append(string, "No");
				END;
			END AppendBoolean;

		BEGIN
			panel := Perf.NewGroupPanel("System Information", WMComponents.AlignTop, 100);

			(* First Line: Version *)
			line := Perf.NewPanel(WMComponents.AlignTop, 0, Perf.LineHeight); panel.AddContent(line);
			label := Perf.NewLabel("Version:", WMComponents.AlignLeft, 100, 0); line.AddContent(label);
			label := Perf.NewLabel(AosBoot.version, WMComponents.AlignClient, 0, 0); line.AddContent(label);

			(* Second Line: System Time *)
			line := Perf.NewPanel(WMComponents.AlignTop, 0, Perf.LineHeight); panel.AddContent(line);
			label := Perf.NewLabel("System Time:", WMComponents.AlignLeft, 100, 0); line.AddContent(label);
			timeLabel := Perf.NewLabel("--", WMComponents.AlignClient, 0, 0); line.AddContent(timeLabel);

			(* Third Line: MMX/SSE/SSE2 capabilities *)
			line := Perf.NewPanel(WMComponents.AlignTop, 0, Perf.LineHeight); panel.AddContent(line);
			label := Perf.NewLabel("Capabilities:", WMComponents.AlignLeft, 100, 0); line.AddContent(label);

			caption := "MMX: "; AppendBoolean(caption, AosBoot.MMX IN AosBoot.features);
			Utilities.Append(caption, ", SSE: "); AppendBoolean(caption, AosBoot.SSESupport);
			Utilities.Append(caption, ", SSE2: "); AppendBoolean(caption, AosBoot.SSE2Support);	

			label := Perf.NewLabel(caption, WMComponents.AlignClient, 0, 0); line.AddContent(label);
	
			RETURN panel;
		END CreateSysinfoPanel;
		
		PROCEDURE CreateGcStatisticsPanel() : WMStandardComponents.Panel;
		VAR panel : WMStandardComponents.Panel; line : WMStandardComponents.Panel;
		BEGIN
			panel := Perf.NewGroupPanel("Garbage Collector", WMComponents.AlignTop, 100);
			
			line := Perf.NewPanel(WMComponents.AlignTop, 0, 20); panel.AddContent(line);
			line.AddContent(Perf.NewButton("Run GC", HandleGcButton));
						
			gcCurrentRun := Perf.NewLabel("", WMComponents.AlignClient, 0, 0);
			line.AddContent(gcCurrentRun);			
			
			line1 := Perf.NewLabel("", WMComponents.AlignTop, 0, 20); panel.AddContent(line1);
			line2 := Perf.NewLabel("", WMComponents.AlignTop, 0, 20); panel.AddContent(line2);
			line3 := Perf.NewLabel("", WMComponents.AlignTop, 0, 20); panel.AddContent(line3);
						
			RETURN panel;
		END CreateGcStatisticsPanel;
		
		PROCEDURE CreateCPUClockratePanel() : WMStandardComponents.Panel;
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			panel := Perf.NewGroupPanel("CPU Clockrate", WMComponents.AlignTop, 45);
			panel.AddContent(Perf.NewButton("Detect", HandleDetectButton));
			
			cpuClockrate := Perf.NewLabel("   Press button to detect CPU clockrate", WMComponents.AlignClient, 0, 0);
			panel.AddContent(cpuClockrate);
			
			RETURN panel;
		END CreateCPUClockratePanel;
		
		PROCEDURE CreateTimerPanel() : WMStandardComponents.Panel;
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			panel := Perf.NewGroupPanel("Timers", WMComponents.AlignTop, 45);
			startBtn := Perf.NewButton("Start", HandleTimerButton); panel.AddContent(startBtn);
			elapsed := Perf.NewLabel("   Press button to start time...", WMComponents.AlignClient, 0, 0); panel.AddContent(elapsed);
			RETURN panel;			
		END CreateTimerPanel;
		
		PROCEDURE CreateUnloadPanel() : WMStandardComponents.Panel;
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			panel := Perf.NewGroupPanel("Performance Monitoring", WMComponents.AlignTop, 45);
			unloadBtn := Perf.NewButton("Unload", HandleUnloadButton); panel.AddContent(unloadBtn);
			panel.AddContent(Perf.NewLabel("   Window close button just closes GUI. This closes all.", WMComponents.AlignClient, 0, 0));
			RETURN panel;	
		END CreateUnloadPanel;
		
		PROCEDURE UpdateTime;
		VAR caption : ARRAY 64 OF CHAR;
		BEGIN
			Utilities.FormatDateTime(format, Utilities.Now(), caption);			
			timeLabel.caption.SetAOC(caption);
		END UpdateTime;

		PROCEDURE Finalize*;
		BEGIN
			alive := FALSE;
			timer.Wakeup;
			BEGIN {EXCLUSIVE} AWAIT(dead); END;
			Finalize^;			
		END Finalize;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(timer); alive := TRUE; dead := FALSE;
			format := "hh:nn:ss, wwww, mmmm d, yyyy";
			clockrate := -1; (* invalid *)
			AddContent(CreateSysinfoPanel());
			AddContent(CreateCPUClockratePanel());
			AddContent(CreateGcStatisticsPanel());
			AddContent(CreateTimerPanel());								
			AddContent(CreateUnloadPanel());
		END Init;
		
	BEGIN {ACTIVE}
		WHILE alive DO
			IF visible.Get() THEN UpdateTime; END;
			timer.Sleep(500);
		END;
		BEGIN {EXCLUSIVE} dead := TRUE; END;
	END SystemTab;
	
END WMPerfMonTabSystem.
