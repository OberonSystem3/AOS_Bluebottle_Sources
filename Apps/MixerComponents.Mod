MODULE MixerComponents;	(** AUTHOR "TF"; PURPOSE "Set the volumes of the default AosSound device"; *)

IMPORT
	AosModules, AosOut, 
	AosSound, Utilities, AosPlugins, WMComponents, WMEvents;

CONST
	Pdevice = "device";
	Pchannel = "channel";
	Pvolume = "volume";
	EonVolumeChanged = "onVolumeChanged";

VAR
	device : AosSound.Driver;
	master : AosSound.MixerChannel;
	
TYPE
	String = Utilities.String;
	AudioChannel* = OBJECT(WMComponents.Component)
	VAR channelName, deviceName : String;
		volume : LONGINT;
		device : AosSound.Driver;
		channel : AosSound.MixerChannel;
		onVolumeChanged* : WMEvents.EventSource; 
		
		PROCEDURE &Init;
		VAR p : AosPlugins.Plugin;
		BEGIN
(*			Init^;
			NEW(onVolumeChanged, SELF, Utilities.NewString("onVolumeChanged"), SELF.StringToCompCommand);
			p := AosSound.devices.Get(""); IF p # NIL THEN device := p(AosSound.Driver) ELSE device := NIL END;
			IF device # NIL THEN device.RegisterMixerChangeListener(MixerChangeListener) END; *)
		END Init;

		PROCEDURE FindChannel(channel : ARRAY OF CHAR) : AosSound.MixerChannel;
		VAR i : LONGINT; ch : AosSound.MixerChannel; name : ARRAY 128 OF CHAR;
		BEGIN
			IF device # NIL THEN 
				FOR i := 0 TO device.GetNofMixerChannels() - 1 DO
					device.GetMixerChannel(i, ch);
					ch.GetName(name);
					IF name = channel THEN RETURN ch END;
				END;
				RETURN NIL
			ELSE
				AosOut.String("MixerComponents.AudioChannel.FindChannel: no device found"); AosOut.Ln;
				RETURN NIL
			END	
		END FindChannel;
		
(*		PROCEDURE DetectChanges(sender, data : PTR);
		VAR v : LONGINT;
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.DetectChanges, sender, data) 
			ELSE
				IF channel # NIL THEN 
					v := channel.GetVolume();
					IF v # volume THEN volume := v; IF ~silent THEN onVolumeChanged.Call(channel) END END
				END	
			END	
		END DetectChanges; 
		
		PROCEDURE MixerChangeListener(channel : AosSound.MixerChannel);
		BEGIN
			IF channel # SELF.channel THEN RETURN END;
			(* call asynchronous as not to block the driver *)
			sequencer.ScheduleEvent(SELF.DetectChanges, SELF, channel)
		END MixerChangeListener;
	
		PROCEDURE SetPropertyValue*(name, value : String); (** OVERRIDE *)
		VAR p : AosPlugins.Plugin;
		BEGIN 
			AcquireWrite;
			IF name^ = Pchannel THEN channelName := value; channel := FindChannel(channelName^);
	(*			IF initialized & (channel # NIL) THEN DetectChanges(SELF, channel) END; *)
			ELSIF name^ = Pdevice THEN 
				deviceName := value; p := AosSound.devices.Get(value^);
				IF device # NIL THEN device.UnregisterMixerChangeListener(MixerChangeListener) END;
				IF p # NIL THEN device := p(AosSound.Driver) ELSE device := NIL END;
				IF device # NIL THEN device.RegisterMixerChangeListener(MixerChangeListener) END;
				IF channelName # NIL THEN channel := FindChannel(channelName^) ELSE channel := NIL END;
			(*	IF initialized & (channel # NIL) THEN DetectChanges(SELF, channel) END; *)
			ELSIF name^ = Pvolume THEN Utilities.StrToInt(value^, volume); 
				IF channel # NIL THEN channel.SetVolume(volume) ELSE AosOut.String("Channel is nil"); AosOut.Ln END;
			ELSIF name^ = EonVolumeChanged THEN onVolumeChanged.AddByString(value)
			ELSE SetPropertyValue^(name, value)
			END;
			ReleaseWrite
		END SetPropertyValue; *)
		
(*		PROCEDURE GetVolume(): LONGINT;
		BEGIN
			RETURN volume
		END GetVolume;
		
		PROCEDURE GetPropertyValue*(name : String; VAR value : ARRAY OF CHAR); (** OVERRIDE *)
		BEGIN 
			AcquireRead;
			IF name^ = Pvolume THEN Utilities.IntToStr(GetVolume(), value)	
			ELSE GetPropertyValue^(name, value)
			END;
			ReleaseRead
		END GetPropertyValue;
		
		PROCEDURE Initialize;
		BEGIN
			Initialize^;
	(*		IF initialized & (channel # NIL) THEN DetectChanges(SELF, channel) END; *)
		END Initialize;
		
		PROCEDURE Finalize;
		BEGIN
			Finalize^;
			IF device # NIL THEN device.UnregisterMixerChangeListener(MixerChangeListener) END;
		END Finalize; *)
	END AudioChannel;

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

(**  Generators  *********************************************************************************)
PROCEDURE GenAudioChannel*(par : PTR) : PTR;
VAR audioChannel : AudioChannel;
BEGIN NEW(audioChannel); RETURN audioChannel
END GenAudioChannel;
(**********************************************************************************************)


(* Register generator procedures *)
PROCEDURE Register;
BEGIN
	WMComponents.registry.RegisterElement("AudioChannel", GenAudioChannel);
END Register;

(* Cleanup on module free *)
PROCEDURE Cleanup;
BEGIN
	WMComponents.registry.UnregisterElement("AudioChannel");
END Cleanup;

BEGIN
	Register;
	AosModules.InstallTermHandler(Cleanup);
END MixerComponents.
 
System.Free MixerComponents ~
