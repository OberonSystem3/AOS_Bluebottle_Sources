MODULE WMPlayer; (** AUTHOR "PL"; PURPOSE "MediaPlayer GUI"; *)
(*
 * History:
 *
 *	15.02.2006	Open WMPlayer window in current view, unified button handlers (staubesv)
 *)
 
IMPORT
	Utilities, AosModules, AosCommands, AosIO, AosOut, AosTexts, AosTextUtilities,
	WMGraphics, WMMessages, WMComponents, WMStandardComponents, WMWindowManager, WMTextView, WMDialogs,
	MediaPlayer;
	
CONST
	DefaultWidth = 800;
	DefaultHeight = 60;
	
	StyleRegular = {};
	StyleBold = {0};
	
	Tab = CHR(AosTexts.TabChar);
TYPE

	KillerMsg = OBJECT
	END KillerMsg; 
	
TYPE
	
	(* Small window showing information about the currently loaded content (framerate, etc. ) *)
	InfoWindow = OBJECT(WMComponents.FormWindow)
	VAR
		data : MediaPlayer.Setup;
		
		tv : WMTextView.TextView;
		text : AosTexts.Text;
		tw : AosTextUtilities.TextWriter;
		w : AosIO.Writer;
		
		next : InfoWindow;
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR 
			panel : WMStandardComponents.Panel; 
			tabPositions : WMTextView.TabPositions; tabStops : WMTextView.CustomTabStops;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(300, 100); panel.fillColor.Set(0FFFFFFFFH);
			
			NEW(tv);tv.alignment.Set(WMComponents.AlignClient);
			tv.isMultiLine.Set(TRUE); tv.showBorder.Set(TRUE); tv.alwaysShowCursor.Set(FALSE);
			panel.AddContent(tv);
			
			NEW(tabPositions, 2); tabPositions[0] := 70; tabPositions[1] := 150;
			NEW(tabStops, tabPositions);
			tv.SetTabStops(tabStops);
			RETURN panel;	
		END CreateForm;
		
		PROCEDURE CreateContent;
		VAR framerate : REAL; hours, minutes, seconds : LONGINT;
		BEGIN
			NEW(text); NEW(tw, text); w := tw.GetWriter();			
			tw.SetFontStyle(StyleBold); w.String("Content"); w.Char(Tab); tw.SetFontStyle(StyleRegular);
			w.String(data.uri); 
			w.Ln;
			w.String("________________________________________________");
			w.Ln;			
			tw.SetFontStyle(StyleBold); w.String("Duration"); w.Char(Tab); tw.SetFontStyle(StyleRegular);
			ConvertTime(data.maxTime*100, hours, minutes, seconds);
			IF hours # 0 THEN w.Int(hours, 0); w.String("h "); END;
			IF (hours # 0) OR (minutes # 0) THEN w.Int(minutes, 0); w.String("min "); END;
			w.Int(seconds, 0); w.String("s"); 
			w.Ln;
			tw.SetFontStyle(StyleBold); w.String("Video"); w.Char(Tab); tw.SetFontStyle(StyleRegular);
			IF data.hasVideo THEN
				w.Int(data.width, 0); w.String("x"); w.Int(data.height, 0); w.String(", ");
				IF data.mspf # 0 THEN
					framerate := 1000 / data.mspf;
					w.Int(ENTIER(framerate), 0);
					IF framerate - ENTIER(framerate) # 0 THEN
						w.Char("."); w.Int(ENTIER((framerate - ENTIER(framerate))*1000), 0);
					END;
					w.String(" frames per second");
				ELSE
					w.String("Unknown framerate");
				END;		
			ELSE
				w.String("n/a");
			END;
			w.Ln;
			tw.SetFontStyle(StyleBold); w.String("Audio"); w.Char(9X);tw.SetFontStyle(StyleRegular);
			IF data.hasAudio THEN 
				w.Int(data.channels, 0); w.String(" Channel(s), "); w.Int(data.rate, 0); w.String("Hz, "); 
				w.Int(data.bits, 0); w.String(" bits");
			ELSE
				w.String("n/a");
			END;
			w.Ln;
			w.Update;
			tv.SetText(text);
		END CreateContent;
	
		PROCEDURE &New(setupData : MediaPlayer.Setup);
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			ASSERT(setupData # NIL);
			data := setupData;
			vc := CreateForm(); CreateContent;
			Init^(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Content Info"));	
			WMWindowManager.ExtAddWindow (SELF, 100, 100, {WMWindowManager.FlagFrame});
			manager := WMWindowManager.GetDefaultManager ();
			manager.SetFocus(SELF);		
		END New;
		
	END InfoWindow;

TYPE

	Window* = OBJECT (WMComponents.FormWindow)
	VAR
		playBtn, stopBtn, pauseBtn, ffBtn, rewBtn, infoBtn : WMStandardComponents.Button;
		search: WMStandardComponents.Scrollbar;
		
		timeLbl, totTimeLbl: WMStandardComponents.Label;
		
		player : MediaPlayer.Player;
		stepSize : LONGINT;

		(* Info about currently loaded content *)
		filename : ARRAY 256 OF CHAR;
		setupData : MediaPlayer.Setup;		
		infos : InfoWindow;
			
		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel, toolbar : WMStandardComponents.Panel;
			label: WMStandardComponents.Label;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(DefaultWidth, DefaultHeight); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
			
			(* Search / position scrollbar *)
			NEW(toolbar); toolbar.fillColor.Set(0FFFFFFFFH); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar); 
		
			NEW(search); search.alignment.Set(WMComponents.AlignClient); 
			search.vertical.Set(FALSE); search.max.Set(1000); search.pos.Set(0);
			toolbar.AddContent(search);			
			
			(* Buttons *)
			NEW(toolbar); toolbar.fillColor.Set(0A0A0A0FFH); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);		
			
			NEW(playBtn); playBtn.alignment.Set(WMComponents.AlignLeft); playBtn.caption.SetAOC("Play"); 
			toolbar.AddContent(playBtn);
	
			NEW(pauseBtn); pauseBtn.alignment.Set(WMComponents.AlignLeft); pauseBtn.caption.SetAOC("Pause"); 
			toolbar.AddContent(pauseBtn);
	
			NEW(stopBtn); stopBtn.alignment.Set(WMComponents.AlignLeft); stopBtn.caption.SetAOC("Stop"); 
			toolbar.AddContent(stopBtn);

			NEW(rewBtn); rewBtn.alignment.Set(WMComponents.AlignLeft); rewBtn.caption.SetAOC("<<"); 
			toolbar.AddContent(rewBtn); rewBtn.isRepeating.Set(TRUE);

			NEW(ffBtn); ffBtn.alignment.Set(WMComponents.AlignLeft); ffBtn.caption.SetAOC(">>"); 
			toolbar.AddContent(ffBtn); ffBtn.isRepeating.Set(TRUE);
		
			NEW(infoBtn); infoBtn.alignment.Set(WMComponents.AlignRight); infoBtn.caption.SetAOC("Info");
			toolbar.AddContent(infoBtn); 
			
			(* Info Labels *)
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			panel.AddContent(label); label.caption.SetAOC(" Elapsed Time: ");
									
			NEW(timeLbl); timeLbl.bounds.SetWidth(100); timeLbl.alignment.Set(WMComponents.AlignLeft);
			panel.AddContent(timeLbl); timeLbl.caption.SetAOC("00:00:00");
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			panel.AddContent(label); label.caption.SetAOC("Total Time: ");
			
			NEW(totTimeLbl); totTimeLbl.bounds.SetWidth(100); totTimeLbl.alignment.Set(WMComponents.AlignLeft);
			panel.AddContent(totTimeLbl); timeLbl.caption.SetAOC("00:00:00");
			
			RETURN panel;
		END CreateForm;
		
		PROCEDURE &New;
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			NEW(player);
			player.setup := SetUpController;
			player.update := Update;
			player.console := FALSE;

			IncCount();
			vc := CreateForm();
			
			playBtn.onClick.Add(ButtonHandler);
			stopBtn.onClick.Add(ButtonHandler);
			pauseBtn.onClick.Add(ButtonHandler);
			ffBtn.onClick.Add(ButtonHandler);
			rewBtn.onClick.Add(ButtonHandler);
			infoBtn.onClick.Add(ButtonHandler);
			search.onPositionChanged.Add(SliderSearch);
			
			Init^(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Media Player"));
			
			WMWindowManager.ExtAddWindow(SELF, 100, 30, {WMWindowManager.FlagFrame, WMWindowManager.FlagStayOnTop});
			manager := WMWindowManager.GetDefaultManager();
			manager.SetFocus(SELF);
		END New;
		
		PROCEDURE Open*(fileName : ARRAY OF CHAR);
		VAR res, ignore : LONGINT; msg : ARRAY 256 OF CHAR;
		BEGIN
			COPY(fileName, filename);
			player.Open(filename, msg, res);
			IF res # MediaPlayer.Ok THEN
				ignore := WMDialogs.Message("Error", msg, {WMDialogs.ResOk}); 
				SetTitle(Utilities.NewString("Media Player"));		
			ELSE
				msg := "Media Player - "; Utilities.Append(msg, fileName);
				SetTitle(Utilities.NewString(msg));				
			END;
		END Open;
		
		PROCEDURE ButtonHandler(sender, data : ANY);
		VAR b : WMStandardComponents.Button; info : InfoWindow; ignore : LONGINT;
		BEGIN
			IF (sender # NIL) & (sender IS WMStandardComponents.Button) THEN
				b := sender (WMStandardComponents.Button);
				IF b = playBtn THEN player.Play;
				ELSIF b = stopBtn THEN player.Stop;
				ELSIF b = pauseBtn THEN player.Pause;
				ELSIF b = ffBtn THEN player.SetPos(player.GetPos() + stepSize);
				ELSIF b = rewBtn THEN player.SetPos(player.GetPos() - 2*stepSize);
				ELSIF b = infoBtn THEN
					IF setupData # NIL THEN
						NEW(info, setupData);
						BEGIN {EXCLUSIVE} info.next := infos; infos := info; END;
					ELSE
						ignore := WMDialogs.Message("Error", "No content loaded.", {WMDialogs.ResOk}); 
					END;
				END;
			END;
		END ButtonHandler;
				
		PROCEDURE Close;
		BEGIN
			player.Close;
			(* Close all open InfoWindow if any *)
			WHILE infos # NIL DO infos.Close; infos := infos.next; END;
			Close^;
			DecCount;
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
			ELSE Handle^(x)
			END;
		END Handle;		
		
		PROCEDURE SliderSearch(sender, data: ANY);
		VAR pos: LONGINT;
		BEGIN
			pos := search.pos.Get();
			player.SetPos(pos)
		END SliderSearch;
				
		(* Update the Info Labels *)
		PROCEDURE Update*(status, pos, maxpos, displayTime: LONGINT);
		VAR temp : ARRAY 16 OF CHAR;
		BEGIN	
			ConvertTimeToStr(displayTime * 100, temp);
			timeLbl.caption.SetAOC(temp);
			IF (setupData # NIL) & (setupData.hasVideo) THEN
				search.pos.Set(pos);
			ELSE
				search.pos.Set(displayTime);
			END;
			IF (pos # 0) & (displayTime # 0) THEN stepSize := 10* pos DIV displayTime END
		END Update;
		
		(* Init the GUI with infos from the Decoder *)
		PROCEDURE SetUpController*(setup : MediaPlayer.Setup);
		VAR temp : ARRAY 16 OF CHAR;
		BEGIN
			setupData := setup;
			IF setup.canSeek THEN
				search.visible.Set(TRUE);
				IF setup.hasVideo THEN
					search.max.Set(setup.maxFrames);
					search.pageSize.Set(setup.maxFrames DIV 25);
				ELSE
					search.max.Set(setup.maxTime);
					search.pageSize.Set(setup.maxTime DIV 100);
				END;
			ELSE
				search.visible.Set(FALSE)
			END;
			ConvertTimeToStr(setup.maxTime * 100, temp);
			totTimeLbl.caption.SetAOC(temp)
		END SetUpController;
		
	END Window;

VAR
	nofWindows : LONGINT;

(* Convert milliseconds to hours:minutes:seconds *)
PROCEDURE ConvertTime(ms : LONGINT; VAR hours, minutes, seconds : LONGINT);
CONST Hour = 60*60*1000; Minute = 60*1000; 
VAR rest : LONGINT;
BEGIN
	hours := ms DIV Hour; rest := ms MOD Hour;
	minutes := rest DIV Minute; rest := rest MOD Minute;
	seconds := rest DIV 1000; 
END ConvertTime;

(* Convert time in millisecond into string of the form "hh:mm:ss" *)
PROCEDURE ConvertTimeToStr(ms : LONGINT; VAR timeStr : ARRAY OF CHAR);
VAR hour, minute, second : LONGINT; nbr : ARRAY 4 OF CHAR;
	
	(* Append 'number' to 'string' using 2 or more digits *)
	PROCEDURE Append(VAR string : ARRAY OF CHAR; number : LONGINT);
	BEGIN
		Utilities.IntToStr(number, nbr);
		IF number >= 10 THEN Utilities.Append(string, nbr);
		ELSE Utilities.Append(string, "0"); Utilities.Append(string, nbr);
		END;
	END Append;
	
BEGIN
	ConvertTime(ms, hour, minute, second);
	timeStr := "";
	Append(timeStr, hour); Utilities.Append(timeStr, ":");
	Append(timeStr, minute); Utilities.Append(timeStr, ":");
	Append(timeStr, second);
END ConvertTimeToStr;

PROCEDURE Open*(par : PTR): PTR; (** filename ~ *)
VAR 
	inst : Window;
	sr: AosIO.StringReader;
	pr: AosCommands.Parameters;
	fileName: ARRAY 255 OF CHAR;
BEGIN
	pr := par(AosCommands.Parameters);
	NEW(sr, LEN(pr.str^)); sr.Set(pr.str^);	sr.String(fileName);
	NEW(inst);
	inst.Open(fileName);
	RETURN NIL;
END Open;

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
BEGIN {EXCLUSIVE}
	NEW(die); msg.ext := die; msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END WMPlayer.

------------------------------------------------------------------------------
S.Free WMPlayer ~
WMPlayer.Open track.mp3~
WMPlayer.Open test.wav~
WMPlayer.Open FAT:tndx.avi~
WMPlayer.Open flags.avi~

WMPlayer.Open Filme:/test.wav ~
WMPlayer.Open Filme:/test2.wav ~
WMPlayer.Open Filme:/test.mp3 ~

MediaPlayer.Open Filme:/test.mp3 ~

MediaPlayer.Close ~

