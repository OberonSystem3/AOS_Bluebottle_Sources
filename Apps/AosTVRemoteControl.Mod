MODULE AosTVRemoteControl;	(** OJ **)

IMPORT
	AosTVDriver, AosTV, Standard := WMStandardComponents, Base := WMComponents, WM := WMWindowManager, Graphics := WMGraphics, AosModules, 
	TeletextViewer;

CONST
	Width = 300;
	ButtonWidth = 100;
	ButtonHeight = 30;
	ButtonsPerRow = 3;

TYPE
	Window = OBJECT (Base.FormWindow)
	VAR
		vcd: AosTVDriver.VideoCaptureDevice;
		tuner: AosTVDriver.TVTuner;
		audio: AosTVDriver.Audio;
		nofChannels: LONGINT;
		buttons: POINTER TO ARRAY OF Standard.Button;
		isMute: BOOLEAN;
		muteButton: Standard.Button;

		PROCEDURE &New;
		VAR
			i: LONGINT;
			fix, chPanel, panel: Standard.Panel;
			panels: POINTER TO ARRAY OF Standard.Panel;
			channel: AosTV.TVChannel;
			openButton: Standard.Button;
			txtButton: Standard.Button;
		BEGIN
			nofChannels := AosTV.channels.GetCount();
			
			vcd := AosTVDriver.GetDefaultDevice();
			tuner := vcd.GetTuner();
			audio := vcd.GetAudio();
			
			(* add a panel *)
			NEW (panel);
			IF nofChannels MOD ButtonsPerRow = 0 THEN
				panel.bounds.SetHeight ((nofChannels DIV ButtonsPerRow+1) * ButtonHeight)
			ELSE
				panel.bounds.SetHeight ((nofChannels DIV ButtonsPerRow+2) * ButtonHeight);
			END;
			
			(* add 'fix' panel *)
			NEW (fix);
			fix.alignment.Set (Base.AlignTop);
			fix.bounds.SetHeight (ButtonHeight);

			NEW (chPanel);
			chPanel.alignment.Set (Base.AlignTop);
			chPanel.bounds.SetHeight ((nofChannels DIV ButtonsPerRow+1) * ButtonHeight);
			chPanel.bounds.SetWidth (Width);
			
			NEW (panels, ButtonsPerRow);
			
			FOR i := 0 TO ButtonsPerRow-1 DO
				NEW(panels[i]);
				panels[i].alignment.Set (Base.AlignLeft);
				panels[i].bounds.SetWidth (ButtonWidth);
				chPanel.AddContent (panels[i]);
			END;

			IF ButtonsPerRow < 3 THEN
				panel.bounds.SetWidth (Width)
			ELSE
				panel.bounds.SetWidth (LEN(panels) * ButtonWidth)
			END;

			(* add 'Open TV Window' button *)
			NEW (openButton);
			openButton.caption.SetAOC ("Open TV Window");
			openButton.bounds.SetWidth (Width DIV 2);
			openButton.onClick.Add (OnOpen);
			openButton.alignment.Set (Base.AlignLeft);
			openButton.bounds.SetHeight (ButtonHeight);
			fix.AddContent (openButton);
			
			(* add 'Mute' button *)
			NEW(muteButton);
			muteButton.caption.SetAOC ("Mute");
			muteButton.bounds.SetWidth (Width DIV 3);
			muteButton.onClick.Add (OnMuteToggle);
			muteButton.alignment.Set (Base.AlignLeft);
			muteButton.bounds.SetHeight (ButtonHeight);
			fix.AddContent (muteButton);
			isMute := FALSE;
			
			(* add 'TXT' button *)
			NEW (txtButton);
			txtButton.caption.SetAOC ("TXT");
			txtButton.bounds.SetWidth (Width DIV 6-1);
			txtButton.fillColor.Set (0FF0000FFH);
			txtButton.onClick.Add (OnTXT);
			txtButton.alignment.Set (Base.AlignLeft);
			txtButton.bounds.SetHeight (ButtonHeight);
			fix.AddContent (txtButton);
			
			panel.AddContent (fix);
			panel.AddContent (chPanel);
			
			(* add channel buttons *)
			IF nofChannels > 0 THEN
				NEW (buttons, nofChannels);
				FOR i := 0 TO nofChannels-1 DO
					NEW (buttons[i]);
					buttons[i].bounds.SetHeight (ButtonHeight);
					buttons[i].alignment.Set (Base.AlignTop);
					buttons[i].clDefault.Set(0FF20H);
					channel := AosTV.channels.GetItem(i);
					buttons[i].caption.SetAOC (channel.name);
					buttons[i].onClick.Add (OnPush);
					panels[i MOD ButtonsPerRow].AddContent (buttons[i])
				END
			END;
			
			(* create the form window with panel size *)
			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), TRUE);;
			SetContent(panel);
			
			(* open the window *)
			manager := WM.GetDefaultManager();
			SetTitle(WM.NewString("TV Remote Control"));
			manager.Add(770, 100, SELF, {WM.FlagFrame});
		END New;

		PROCEDURE FindButton (button: Standard.Button): LONGINT;
		VAR i: LONGINT;
		BEGIN
			i := 0;
			WHILE (i < LEN(buttons)) & (buttons[i] # button) DO
				INC(i)
			END;
			RETURN i
		END FindButton;

		PROCEDURE OnPush (sender, data: PTR);
		VAR
			button: Standard.Button;
			buttonNo: LONGINT;
			channel: AosTV.TVChannel;
		BEGIN
			button := sender(Standard.Button);
			buttonNo := FindButton(button);
			channel := AosTV.channels.GetItem(buttonNo);
			tuner.SetTVFrequency (channel.freq);
(*		Out.String(channel.name); Out.String(" : "); Out.Int(channel.freq, 0); Out.Ln;*)
		END OnPush;

		PROCEDURE OnMuteToggle (sender, data: PTR);
		BEGIN
			IF isMute THEN
				muteButton.caption.SetAOC ("Mute");
				audio.SetAudioUnmute
			ELSE
				muteButton.caption.SetAOC ("Unmute");
				audio.SetAudioMute
			END;
			isMute := ~isMute;
		END OnMuteToggle;

		PROCEDURE OnOpen (sender, data: PTR);
		VAR
			tmp: PTR;
		BEGIN
			tmp := AosTV.Open (tmp);
		END OnOpen;

		PROCEDURE OnTXT (sender, data: PTR);
		VAR
			tmp: PTR;
		BEGIN
			tmp := TeletextViewer.Open (tmp);
		END OnTXT;

		PROCEDURE SetDevice* (dev: LONGINT);
		BEGIN
			vcd := AosTVDriver.GetVideoDevice (dev);
			tuner := vcd.GetTuner();
			audio := vcd.GetAudio();
		END SetDevice;	
	END Window;

VAR
	window: Window;

PROCEDURE Open* (par: PTR): PTR;
BEGIN {EXCLUSIVE}
	NEW (window);
	RETURN NIL
END Open;

PROCEDURE Cleanup;
BEGIN
	IF window # NIL THEN window.Close END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END AosTVRemoteControl.


S.Free AosTVRemoteControl ~
AosTVRemoteControl.Open ~