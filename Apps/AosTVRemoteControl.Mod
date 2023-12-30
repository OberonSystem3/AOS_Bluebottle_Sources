MODULE AosTVRemoteControl;	(** AUTHOR "oljeger@student.ethz.ch"; PURPOSE "Graphical channel switcher for AosTV"; *)

IMPORT
	AosTVDriver, AosTV, AosTVChannels, Standard := WMStandardComponents, Base := WMComponents, AosCommands,
	AosIO, WM := WMWindowManager, Graphics := WMGraphics, AosModules, AosOut, AosTeletextViewer, WMDialogs,
	Messages := WMMessages, WMRestorable, XML, Utilities, WMGrids, WMStringGrids;

CONST
	Width = 200;
	ButtonWidth = 100;
	ButtonHeight = 30;
	ButtonsPerRow = 3;
	
	ButtonCol = 0FF00008FH;

TYPE
	(** Remote control window *)
	Window = OBJECT (Base.FormWindow)
	VAR
		vcd: AosTVDriver.VideoCaptureDevice;
		devNr: LONGINT;
		tuner: AosTVDriver.TVTuner;
		audio: AosTVDriver.Audio;
		tvWnd: AosTV.TvWindow;
		nofChannels: LONGINT;
		buttons: POINTER TO ARRAY OF Standard.Button;
		isMute: BOOLEAN;
		muteButton: Standard.Button;
		next: Window;

		PROCEDURE &New (vcd: AosTVDriver.VideoCaptureDevice; devNr: LONGINT; openTV: BOOLEAN);
		VAR
			i: LONGINT;
			fix, panel: Standard.Panel;
			panels: POINTER TO ARRAY OF Standard.Panel;
			channel: AosTVChannels.TVChannel;
			openButton: Standard.Button;
			txtButton: Standard.Button;
			channelList : WMStringGrids.StringGrid;
		BEGIN
			nofChannels := AosTVChannels.channels.GetCount();
			IF vcd = NIL THEN
				AosOut.String("{AosTVRemoteControl} ERROR: Fail to locate video capture device.");
				AosOut.Ln;
				RETURN;
			END;
			SELF.vcd := vcd;
			tuner := vcd.GetTuner();
			audio := vcd.GetAudio();
			SELF.devNr := devNr;
			NEW(panel);
			panel.alignment.Set(Base.AlignClient);
			
			(* add a panel *)
			panel.fillColor.Set(0FFH);
			
			(* add 'fix' panel *)
			NEW (fix);
			fix.alignment.Set (Base.AlignTop);
			fix.bounds.SetHeight (ButtonHeight);

			NEW (channelList);
		
			channelList.model.Acquire;
			channelList.model.SetNofCols(1);
			channelList.model.SetNofRows(1);
			channelList.SetSelectionMode(WMGrids.GridSelectRows);
			channelList.model.Release;
	
			
			(* add 'Open TV Window' button *)
			NEW (openButton);
			openButton.caption.SetAOC ("Open TV");
			openButton.bounds.SetWidth (Width DIV 3);
			openButton.onClick.Add (OnOpen);
			openButton.clDefault.Set (ButtonCol);
			openButton.alignment.Set (Base.AlignLeft);
			openButton.bounds.SetHeight (ButtonHeight);
			fix.AddContent (openButton);
			
			(* add 'Mute' button *)
			NEW(muteButton);
			muteButton.caption.SetAOC ("Mute");
			muteButton.bounds.SetWidth (Width DIV 3);
			muteButton.onClick.Add (OnMuteToggle);
			muteButton.clDefault.Set (ButtonCol);
			muteButton.alignment.Set (Base.AlignLeft);
			muteButton.bounds.SetHeight (ButtonHeight);
			fix.AddContent (muteButton);
			isMute := FALSE;
			
			(* add 'TXT' button *)
			NEW (txtButton);
			txtButton.caption.SetAOC ("TXT");
			txtButton.bounds.SetWidth (Width DIV 3);
			txtButton.clDefault.Set (ButtonCol);
			txtButton.onClick.Add (OnTXT);
			txtButton.alignment.Set (Base.AlignLeft);
			txtButton.bounds.SetHeight (ButtonHeight);
			fix.AddContent (txtButton);
			
			panel.AddContent (fix);
			
			panel.AddContent (channelList);
			channelList.alignment.Set(Base.AlignClient);
		
			
	(*		(* add channel buttons *)
			IF nofChannels > 0 THEN
				NEW (buttons, nofChannels);
				FOR i := 0 TO nofChannels-1 DO
					NEW (buttons[i]);
					buttons[i].bounds.SetHeight (ButtonHeight);
					buttons[i].alignment.Set (Base.AlignTop);
					channel := AosTVChannels.channels.GetItem(i);
					buttons[i].caption.SetAOC (channel.name);
					buttons[i].onClick.Add (OnPush);
					panels[i MOD ButtonsPerRow].AddContent (buttons[i])
				END
			END; *)
			
			(* create the form window with panel size *)
			Init(Width, 300, TRUE);
			SetContent(panel);
			
			(* open the window *)
			manager := WM.GetDefaultManager();
			SetTitle(WM.NewString("TV Remote Control"));
			manager.Add(770, 100, SELF, {WM.FlagFrame});
			next := window;
			window := SELF;

			channelList.model.Acquire;
			channelList.model.SetNofRows(nofChannels);
			FOR i := 0 TO nofChannels-1 DO
				channel := AosTVChannels.channels.GetItem(i);
				channelList.model.SetCellText(0, i,Utilities.NewString(channel.name));
				channelList.model.SetCellData(0, i, channel);
			END;
			channelList.model.Release;
			channelList.Invalidate;
			channelList.onClick.Add(OnPush);

			
			(* open the TV window (there will be only one single instance) *)
			IF openTV THEN
				OnOpen (NIL, NIL)
			END
		END New;

		(** Find a button for correct action *)
		PROCEDURE FindButton (button: Standard.Button): LONGINT;
		VAR i: LONGINT;
		BEGIN
			i := 0;
			WHILE (i < LEN(buttons)) & (buttons[i] # button) DO
				INC(i)
			END;
			RETURN i
		END FindButton;

		(** Switch to the appropriate TV channel *)
		PROCEDURE OnPush (sender, data: PTR);
		VAR
			button: Standard.Button;
			buttonNo: LONGINT;
			channel: AosTVChannels.TVChannel;
		BEGIN
			IF (data # NIL) & (data IS AosTVChannels.TVChannel) THEN
				channel := data(AosTVChannels.TVChannel);
				IF tuner # NIL THEN
					tuner.SetTVFrequency (channel.freq)
				END	
			END
		END OnPush;

		(** Toggle audio mute state *)
		PROCEDURE OnMuteToggle (sender, data: PTR);
		BEGIN
			IF isMute THEN
				muteButton.caption.SetAOC ("Mute");
				audio.SetAudioUnmute
			ELSE
				muteButton.caption.SetAOC ("Unmute");
				audio.SetAudioMute
			END;
			isMute := ~isMute
		END OnMuteToggle;

		(** Open a TV window. Do nothing if already open *)
		PROCEDURE OnOpen (sender, data: PTR);
		BEGIN
			IF ~ vcd.IsVideoOpen() THEN
				NEW(tvWnd, vcd);
				(* Set the device number for non-default devices *)
				IF devNr # -1 THEN
					tvWnd.vcdNr := devNr
				END
			END
		END OnOpen;

		(** Open a teletext viewer window *)
		PROCEDURE OnTXT (sender, data: PTR);
		VAR
			viewer: AosTeletextViewer.TeletextViewer;
		BEGIN
			NEW(viewer);
			IF (tvWnd # NIL) & tvWnd.alive THEN
				viewer.Switch(tvWnd.GetTVFreq());
				tvWnd.StartTeletextCapture
			ELSE
				tvWnd := NIL
			END
		END OnTXT;

		(** Select another VideoCaptureDevice *)
		PROCEDURE SetDevice* (dev: LONGINT);
		BEGIN
			vcd := AosTVDriver.GetVideoDevice (dev);
			tuner := vcd.GetTuner();
			audio := vcd.GetAudio();
			devNr := dev
		END SetDevice;
		
		(** Close the remote control window *)
		PROCEDURE Close();
		BEGIN
			FreeWindow(SELF);
			Close^
		END Close;
		
		(** Handle window messages *)
		PROCEDURE Handle(VAR m : Messages.Message);
		VAR
			data: XML.Element;
			str: ARRAY 10 OF CHAR;
		BEGIN
			IF (m.msgType = Messages.MsgExt) & (m.ext # NIL) THEN
				IF (m.ext IS WMRestorable.Storage) THEN
					NEW(data);  data.SetName("AosTVRemoteControlData");
					Utilities.IntToStr(devNr, str);
					data.SetAttributeValue("device", str);
					m.ext(WMRestorable.Storage).Add("AosTVRemoteControl",
							"AosTVRemoteControl.Restore", SELF, data)
				ELSE Handle^(m)
				END
			ELSE Handle^(m)
			END
		END Handle;
		
	END Window;

VAR
	window: Window;

(** Open a remote control window *)
PROCEDURE Open* (par: PTR): PTR;
VAR
	vcd : AosTVDriver.VideoCaptureDevice;
	s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	res, devNr: LONGINT;
	wnd: Window;
BEGIN {EXCLUSIVE}
	IF par # NIL THEN
		s := par(AosCommands.Parameters);
		NEW(sr, LEN(s.str^)); sr.Set(s.str^);
		(* Read VideoCaptureDevice number *)
		sr.SkipWhitespace; sr.Int(devNr, FALSE);
		IF sr.res = 0 THEN
			vcd := AosTVDriver.GetVideoDevice(devNr)
		ELSE
			devNr := -1;
			vcd := AosTVDriver.GetDefaultDevice()
		END
	ELSE
		devNr := -1;
		vcd := AosTVDriver.GetDefaultDevice()
	END;
	(* Display error message if no VideoCaptureDevice has been found *)
	IF vcd = NIL THEN
		IF (par # NIL) & (sr.res = 0) THEN
			AosOut.String("{AosTV} Parameter is not a valid video device number."); AosOut.Ln;
			res := WMDialogs.Message("AosTV - Error",
									    "Parameter is not a valid video device number. Make sure that all TV card drivers are loaded.",
									    {WMDialogs.ResOk});
			RETURN NIL
		ELSE
			AosOut.String("{AosTV} Cannot open TV window: Fail to locate video capture device.");
			AosOut.Ln;
			res := WMDialogs.Message("AosTVRemoteControl - Error",
				"Cannot open TV window: Fail to locate video capture device. Install device before opening the TV window. Example: AosBT848.Install",
				{WMDialogs.ResOk});
			RETURN NIL
		END
	END;
	NEW (wnd, vcd, devNr, TRUE);
	RETURN NIL
END Open;

(** Restore stored windows *)
PROCEDURE Restore*(par: ANY) : ANY;
VAR
	manager: WM.WindowManager;
	c: WMRestorable.Context;
	xml: XML.Element;
	s: Utilities.String;
	devNr: LONGINT;
	vcd: AosTVDriver.VideoCaptureDevice;
	wnd: Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		c := par(WMRestorable.Context);
		IF c # NIL THEN 
			(* restore the desktop *)
			IF c.appData # NIL THEN
				xml := c.appData(XML.Element);
				s := xml.GetAttributeValue("device");
				IF s # NIL THEN
					(* Read device number *)
					Utilities.StrToInt(s^, devNr);
					IF devNr = -1 THEN
						vcd := AosTVDriver.GetDefaultDevice()
					ELSE
						vcd := AosTVDriver.GetVideoDevice(devNr)
					END;
					IF vcd # NIL THEN
						NEW(wnd, vcd, devNr, FALSE);
						manager := WM.GetDefaultManager();
						manager.Remove(wnd);
						WMRestorable.AddByContext(wnd, c, {WM.FlagFrame})
					ELSE
						AosOut.String("{AosTVRemoteControl} Could not restore the RemoteControl window."); AosOut.Ln;
						AosOut.String("{AosTVRemoteControl} Install the device driver first, e.g. AosBT848.Install"); AosOut.Ln
					END
				END
			END
		END
	END;
	RETURN NIL
END Restore;

(** Remove the window from the internal channelList *)
PROCEDURE FreeWindow(wnd: Window);
VAR
	w: Window;
BEGIN
	IF wnd = NIL THEN
		RETURN
	ELSIF wnd = window THEN
		(* wnd is first channelList element *)
		window := window.next
	ELSE
		w := window;
		WHILE (w # NIL) & (w.next # wnd) DO
			w := w.next
		END;
		IF w # NIL THEN
			(* wnd found: remove it from the channelList *)
			w.next := wnd.next
		END
	END;
END FreeWindow;

(** Term hander *)
PROCEDURE Cleanup;
VAR
	w: Window;
BEGIN
	w := window;
	WHILE w # NIL DO
		w.Close;
		w := w.next
	END;
	window := NIL
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END AosTVRemoteControl.


S.Free AosTVRemoteControl ~
AosTVRemoteControl.Open ~