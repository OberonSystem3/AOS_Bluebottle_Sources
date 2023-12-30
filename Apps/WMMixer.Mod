MODULE WMMixer;	(** AUTHOR "TF"; PURPOSE "Control the mixer of the default AosSound device"; *)

IMPORT
	AosModules,
	AosSound, Utilities, AosPlugins, WMComponents, WMStandardComponents, WMMessages, WMWindowManager, WMProperties;

VAR
	device : AosSound.Driver;
	master : AosSound.MixerChannel;
	
TYPE
	String = Utilities.String;
	
	Mixer* = OBJECT(WMComponents.VisualComponent)
	VAR 
		deviceName-, channelName- : WMProperties.StringProperty;
		
		name : WMStandardComponents.Label;
		value : WMStandardComponents.Scrollbar;
		mute : WMStandardComponents.Checkbox;
		
		channel : AosSound.MixerChannel;
		device : AosSound.Driver;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(deviceName, PrototypedeviceName, NIL, NIL); properties.Add(deviceName);
			NEW(channelName, PrototypechannelName, NIL, NIL); properties.Add(channelName);
			NEW(name); name.alignment.Set(WMComponents.AlignTop); name.bounds.SetHeight(20);
			AddContent(name);
				
			NEW(mute); mute.alignment.Set(WMComponents.AlignBottom); mute.bounds.SetHeight(20);
			mute.caption.SetAOC("Mute");
			AddContent(mute);
			
			NEW(value); value.alignment.Set(WMComponents.AlignClient);
			value.bearing.SetLeft(20); value.bearing.SetRight(20);
			value.onPositionChanged.Add(VolChanged);
			value.max.Set(255);
			AddContent(value);
		END Init;
		
		PROCEDURE RecacheProperties;
		VAR s : String; dn, cn : ARRAY 128 OF CHAR;
		BEGIN
			RecacheProperties^;
			s := deviceName.Get(); IF s # NIL THEN COPY(s^, dn) END;
			s := channelName.Get(); IF s # NIL THEN COPY(s^, cn); name.caption.SetAOC(cn) END;
			IF device # NIL THEN device.UnregisterMixerChangeListener(MixerChangeListener) END;
			FindChannel(dn, cn, device, channel);
			IF channel # NIL THEN 
				 sequencer.ScheduleEvent(SELF.MixerChangeEvent, device, channel)
			END;
			IF device # NIL THEN device.RegisterMixerChangeListener(MixerChangeListener) END;		
		END RecacheProperties;
		
		PROCEDURE MixerChangeListener(channel : AosSound.MixerChannel);
		BEGIN
			 sequencer.ScheduleEvent(SELF.MixerChangeEvent, device, channel)
		END MixerChangeListener;
		
		PROCEDURE MixerChangeEvent(sender, data : ANY);
		VAR vol : LONGINT; m : BOOLEAN;
		BEGIN
			IF (data = channel) & (channel # NIL) THEN
				vol := channel.GetVolume();
				m := channel.GetIsMute();
				value.pos.Set(255 - vol);
				IF m THEN mute.state.Set(WMStandardComponents.Checked)
				ELSE mute.state.Set(WMStandardComponents.Unchecked)
				END;
			END;
		END MixerChangeEvent;
		
		PROCEDURE VolChanged(sender, data : ANY);
		BEGIN
			IF channel # NIL THEN
				channel.SetVolume(255 - value.pos.Get())
			END
		END VolChanged;
		
		PROCEDURE FindChannel(deviceName, channelName : ARRAY OF CHAR; VAR dev : AosSound.Driver; VAR channel : AosSound.MixerChannel);
		VAR i : LONGINT; ch : AosSound.MixerChannel; name : ARRAY 128 OF CHAR;
			p : AosPlugins.Plugin;
		BEGIN
			p := AosSound.devices.Get(deviceName);
			channel := NIL;
			IF (p # NIL) & (p IS AosSound.Driver) THEN dev := p(AosSound.Driver) ELSE dev := NIL END;
			IF dev # NIL THEN 
				FOR i := 0 TO dev.GetNofMixerChannels() - 1 DO
					dev.GetMixerChannel(i, ch);
					ch.GetName(name);
					IF name = channelName THEN channel := ch END;
				END;
			END	
		END FindChannel;
		
		PROCEDURE Finalize;
		BEGIN
			Finalize^;
			IF device # NIL THEN device.UnregisterMixerChangeListener(MixerChangeListener) END;
		END Finalize; 
	END Mixer;
	
	KillerMsg = OBJECT
	END KillerMsg; 	
	
	Window* = OBJECT (WMComponents.FormWindow)
	
		PROCEDURE &New();
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount;
			(* To create a multi language app, try loading the respective XML instead of CreateForm()
			if the XML was not found or does not contain all needed elements, use CreateForm as fallback *)
			vc := CreateForm();
			
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			
			 WMWindowManager.DefaultAddWindow(SELF);
			SetTitle(Utilities.NewString("Mixer"));
		END New;
		
		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR panel : WMStandardComponents.Panel;
			dev : AosSound.Driver;
			i : LONGINT;
			ch : AosSound.MixerChannel;
			name : ARRAY 128 OF CHAR;
			m : Mixer;
		CONST MWidth = 60; 
		BEGIN
			dev := AosSound.GetDefaultDevice();
			
			NEW(panel); panel.bounds.SetExtents(MWidth * dev.GetNofMixerChannels(), 200); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
			
			IF dev # NIL THEN 
				FOR i := 0 TO dev.GetNofMixerChannels() - 1 DO
					dev.GetMixerChannel(i, ch);
					ch.GetName(name);
					NEW(m);
					m.alignment.Set(WMComponents.AlignLeft); m.bounds.SetWidth(MWidth);
					m.channelName.SetAOC(name);
					panel.AddContent(m);
				END;
			END;
			RETURN panel
		END CreateForm;
		
		PROCEDURE Close;
		BEGIN
			DecCount;
			Close^;
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
			ELSE Handle^(x)
			END
		END Handle;			
	END Window;
	
VAR 
	PrototypedeviceName, PrototypechannelName: WMProperties.StringProperty;	
	nofWindows : LONGINT;

PROCEDURE Open*(par : ANY) : ANY;
VAR inst : Window;
BEGIN
	NEW(inst);
	RETURN NIL
END Open;

PROCEDURE IncCount;
BEGIN {EXCLUSIVE}
	INC(nofWindows);
END IncCount;		

PROCEDURE DecCount;
BEGIN {EXCLUSIVE}
	DEC(nofWindows);
END DecCount;	

PROCEDURE MasterIncVol*(par : PTR) : PTR;
BEGIN
	IF master = NIL THEN 
		device := AosSound.GetDefaultDevice();
		device.GetMixerChannel(0, master) 
	END;
	IF master # NIL THEN
		master.SetVolume(Utilities.Min(255, master.GetVolume() + 4))
	END;
	RETURN NIL;
END MasterIncVol;

PROCEDURE MasterDecVol*(par : PTR) : PTR;
BEGIN
	IF master = NIL THEN 
		device := AosSound.GetDefaultDevice();
		device.GetMixerChannel(0, master) 
	END;
	IF master # NIL THEN
		master.SetVolume(Utilities.Max(0, master.GetVolume() - 4))
	END;
	RETURN NIL;
END MasterDecVol;

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
	NEW(PrototypedeviceName, NIL, Utilities.NewString(""), Utilities.NewString("Name of the associated sound device"));
	NEW(PrototypechannelName, NIL, Utilities.NewString("MasterVol"), Utilities.NewString("Name of the associated sound channel"));
END WMMixer.

WMMixer.Open ~
S.Free WMMixer ~

WMMixer.MasterDecVol ~
