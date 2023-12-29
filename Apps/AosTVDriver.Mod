MODULE AosTVDriver;	(** AUTHOR "oljeger@student.ethz.ch"; PURPOSE "Abstract TV driver"; *)

IMPORT
	AosPlugins, AosModules, AosTexts, AosOut;

VAR
	devices*:AosPlugins.Registry;

CONST
	WesternEuropeanChnlSet * = 0;
	VbiMaxLines* = 16;
	VbiLineSize* = 2048;
	VbiBufferItems = 20;
	VbiDataSize* = VbiLineSize * VbiMaxLines * 2;
	VbiBufferSize* = VbiDataSize *  VbiBufferItems;

TYPE
	VbiBuffer* = OBJECT
	VAR
		data	*: ARRAY VbiBufferSize
 OF CHAR;
		readPos*: LONGINT;
		insertPos*: LONGINT;
		vbiSize
*: LONGINT;
	END VbiBuffer;

	ChannelSwitchHandler* = PROCEDURE {DELEGATE} (freq: LONGINT);

	ChannelSwitchObserver = OBJECT
	VAR
		next: ChannelSwitchObserver;
		handler: ChannelSwitchHandler;
	END ChannelSwitchObserver;
	
VAR
	channelSwitchObservers: ChannelSwitchObserver;

TYPE
	(** The TVTuner objects represents the tuning facilities of a video capture card. *)
	TVTuner* = OBJECT
	VAR 
		frequency*: LONGINT;

	(** Initialize the tuner object. *)
		PROCEDURE & Init* (vcd: VideoCaptureDevice);
		BEGIN HALT(99)	(** abstract *)
		END Init;

	(** Open the VBI device. *)
	(** return value: -1 if the device is already open, otherwise 0 *)
		PROCEDURE OpenVbi* (): LONGINT;
		BEGIN HALT(99)	(** abstract *)
		END OpenVbi;

	(** Close the VBI device. *)
		PROCEDURE CloseVbi*;
		BEGIN HALT(99)	(** abstract *)
		END CloseVbi;

	(** Open the tuner. *)
		PROCEDURE Open*;
		BEGIN HALT(99)	(** abstract *)
		END Open;

	(** Close the tuner. *)
		PROCEDURE Close*;
		BEGIN HALT(99)	(** abstract *)
		END Close;

	(** Set the channel set. *)
		PROCEDURE SetChannelSet* (chnlSet: LONGINT);
		BEGIN HALT(99)	(** abstract *)
		END SetChannelSet;
		
	(** Get the channel set. *)
		PROCEDURE GetChannelSet* (): LONGINT;
		BEGIN HALT(99)	(** abstract *)
		END GetChannelSet;

	(** Set a channel. *)
	(** chnl:	channel to set (see range of channel set). *)
		PROCEDURE SetChannel* (chnl: LONGINT);
		BEGIN HALT(99)	(** abstract *)
		END SetChannel;

	(** Get channel. *)
	(** return value:	channel *)
		PROCEDURE GetChannel* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetChannel;
		
		PROCEDURE GetMaxChannel* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetMaxChannel;

	(** Set TV frequency. *)
		PROCEDURE SetTVFrequency* (freq: LONGINT);
		BEGIN
			NotifyChannelSwitchObservers (freq);
			SetTVFrequencyImpl (freq);
		END SetTVFrequency;

		PROCEDURE SetTVFrequencyImpl* (freq: LONGINT);
		BEGIN
		HALT(99);	(** abstract *)
		END SetTVFrequencyImpl;

	(** Get tuner frequency. *)
	(** return value:	tuner frequency *)
		PROCEDURE GetFrequency* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetFrequency;

	(** Set radio frequency. *)
	(** freq:	frequency expressed as frequency * 100. *)
		PROCEDURE SetRadioFrequency* (freq: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetRadioFrequency;

		PROCEDURE InstallChannelSwitchHandler* (handler: ChannelSwitchHandler);
		VAR
			chObs: ChannelSwitchObserver;
		BEGIN
			NEW (chObs);
			chObs.handler := handler;
			(* insert new observer in front of the list (AT THE END???) *)
			chObs.next := channelSwitchObservers;
			channelSwitchObservers := chObs;
		END InstallChannelSwitchHandler;

		PROCEDURE NotifyChannelSwitchObservers (freq: LONGINT);
		VAR
			chObs: ChannelSwitchObserver;
		BEGIN
			chObs := channelSwitchObservers;
			WHILE chObs # NIL DO
				chObs.handler (freq);
				chObs := chObs.next;
			END;
		END NotifyChannelSwitchObservers;

	(** Get the tuner status. *)
	(** return value:	tuner status *)
		PROCEDURE GetTunerStatus* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetTunerStatus;

	(** Calculates the field strength of the radio signal. *)
		PROCEDURE CalcFieldStrength* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END CalcFieldStrength;

	(** Returns wether tuner is locked to a stable video signal or not. *)
	(** return value:	TRUE if tuner is locked to a stable video signal, otherwise FALSE *)
		PROCEDURE IsLocked * (): BOOLEAN;
		BEGIN HALT(99);	(** abstract *)
		END IsLocked;

	(** Returns wether the sound is received in stereo or mono. *)
	(** return value:	TRUE if stereo is enabled, otherwise FALSE *)
		PROCEDURE IsStereo!* (): BOOLEAN;
		BEGIN HALT(99);	(** abstract *)
		END IsStereo;

	(** Set the hue. *)
		PROCEDURE SetHue"* (hue: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetHue;

	(** Get the hue *)
	(** return value:	the hue offset *)
		PROCEDURE GetHue#* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetHue;

	(** Set the brightness. *)
		PROCEDURE SetBrightness$* (brightness: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetBrightness;

	(** Get the brightness. *)
	(** return value:	the brightness offset *)
		PROCEDURE GetBrightness%* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetBrightness;

	(** Set the chroma saturation. *)
	(** Adds a gain adjustment to the U- and V-component of the video signal. *)
		PROCEDURE SetChromaSaturation&* (saturation: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetChromaSaturation;

	(** Get chroma saturation. *)
	(** return value:	the chroma saturation *)
		PROCEDURE GetChromaSaturation'* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetChromaSaturation;

	(** Set chroma V saturation *)
	(** Adds a gain adjustment to the V-component of the video signal. *)
		PROCEDURE SetChromaVSaturation*( (saturation: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetChromaVSaturation;

	(** Get the chroma V saturation. *)
	(** return value:	the chroma V saturation *)
		PROCEDURE GetChromaVSaturation)* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetChromaVSaturation;

	(** Set the chroma U saturation. *)
	(** Adds a gain adjustment to the U-component of the video signal. *)
		PROCEDURE SetChromaUSaturation** (saturation: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetChromaUSaturation;

	(** Get the chroma U saturation. *)
	(** return value:	the chroma U saturation *)
		PROCEDURE GetChromaUSaturation+* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetChromaUSaturation;

	(** Set the luma notch filters. *)
	(** Sets the 3 high bits of EControl/OControl *)
	(** The luma decimation filter is used to reduce the high-frequency component of the luma signal. *)
	(** Useful when scaling to CIF resolution or lower. *)
	(** For monochrome video, the luma notch filter should not be used. This will output full bandwidth luminance. *)
	(** notch:	3 bits of EControl/OControl *)
	(**				[0] 0 enables luma decimation using selectable H filter, 1 disables luma decimation *)
	(**				[1] 0 composite video, 1 Y/C component video *)
	(**				[2] 0 enables the luma notch filter, 1 disables the luma notch filter *)
		PROCEDURE SetLumaNotch,* (notch: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetLumaNotch;

	(** Get status of luma notch filters. *)
	(** return value:	3 bits of EControl/OControl *)
		PROCEDURE GetLumaNotch-* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetLumaNotch;

	(** Set the contrast. *)
	(** This value ist multiplied by the luminance value to provide contrast adjustment. *)
		PROCEDURE SetContrast.* (contrast: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetContrast/;

	(** Get contrast value. *)
	(** return value:	value of contrast multiplication factor *)
		PROCEDURE GetContrast0* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetContrast;

	(** Enable or disable color bars. *)
	(** enable:	TRUE to enable color bars, FALSE for disabling color bars *)
		PROCEDURE SetColorBars1* (enable: BOOLEAN);
		BEGIN HALT(99);	(** abstract *)
		END SetColorBars;
		
	END TVTuner;

	NotificationHandler2* = PROCEDURE {DELEGATE};

	(** The VideoCaptureDevice represents a video capture card with its tuning and audio components. *)
	VideoCaptureDevice*3 = OBJECT (AosPlugins.Plugin)
	(** Each VideoCaptureDevice must have a tuner, an audio and a vbiBuffer object. These can be accessed
			via the appropriate GetXXX procedures *)

		PROCEDURE & Init4* (base, irq, product, rev: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END Init;
	
	(** Get the ringbuffer that contains the raw VBI data *)
		PROCEDURE GetVbiData5* (): VbiBuffer6;
		BEGIN HALT(99);	(** abstract *)
		END GetVbiData;

	(** Get the TVTuner object of this VideoCaptureDevice object. *)
	(** return value:	TVTuner object of this card *)
		PROCEDURE GetTuner7* (): TVTuner8;
		BEGIN HALT(99);	(** abstract *)
		END GetTuner;

	(** Get the Audio object of this VideoCaptureDevice object. *)
	(** return value:	Audio object of this card *)
		PROCEDURE GetAudio9* (): Audio:;
		BEGIN HALT(99);	(** abstract *)
		END GetAudio;

	(** Install a notification handler for RISC events. *)
	(** handler:	procedure of type NotificationHandler *)
		PROCEDURE InstallNotificationHandler;* (handler: NotificationHandler<);
		BEGIN HALT(99);	(** abstract *)
		END InstallNotificationHandler;

	(** Opens the VideoCaptureDevice object. *)
		PROCEDURE VideoOpen=*;
		BEGIN HALT(99);	(** abstract *)
		END VideoOpen;

	(** Closes the VideoCaptureDevice object. *)
		PROCEDURE VideoClose>*;
		BEGIN HALT(99);	(** abstract *)
		END VideoClose;
		
	(** Is the VideoCaptureDevice opened? *)
		PROCEDURE IsVideoOpen?* (): BOOLEAN;
		BEGIN HALT(99);	(** abstract *)
		END IsVideoOpen;

	(** Set a list of clipping region. *)
		PROCEDURE SetClipRegion@*;
		BEGIN HALT(99);	(** abstract *)
		END SetClipRegion;

	(** Get the device status. *)
	(** return value:	device status *)
		PROCEDURE GetStatusA* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetStatus;

	(** Set the video input format *)
	(** format:	format of video signal (Bt848IFormPalBDGHI etc.) *)
		PROCEDURE SetInputFormatB* (format: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetInputFormatC;

	(** Get the video input format. *)
		PROCEDURE GetInputFormatD* (): LONGINT;
		BEGIN HALT(99);	(** abstract *)
		END GetInputFormat;
		
		PROCEDURE SetPixelFormatE* (format: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetPixelFormat;

	(** Select RCA as input. *)
		PROCEDURE SetInputDev0F*;
		BEGIN HALT(99);	(** abstract *)
		END SetInputDev0;

	(** Select the tuner as input. *)
		PROCEDURE SetInputDev1G*;
		BEGIN HALT(99);	(** abstract *)
		END SetInputDev1;

	(** Select S-VHS (composite camera) as input. *)
		PROCEDURE SetInputDev2H*;
		BEGIN HALT(99);	(** abstract *)
		END SetInputDev2;

	(** Select S-VHS as input. *)
		PROCEDURE SetInputDevSVideoI*;
		BEGIN HALT(99);	(** abstract *)
		END SetInputDevSVideoJ;

	(** Select MUX 3 as input. *)
		PROCEDURE SetInputDev3K*;
		BEGIN HALT(99);	(** abstract *)
		END SetInputDev3L;

	(** Set the video data buffer. *)
	(** addr:	physical address of target buffer for video data. *)
	(** width:	line length of video frame buffer *)
		PROCEDURE SetVideoM* (addr: LONGINT; width: LONGINT);
		BEGIN HALT(99);	(** abstract *)
		END SetVideo;

	(** Capture a single frame. *)
		PROCEDURE CaptureSingleN*;
		BEGIN HALT(99);	(** abstract *)
		END CaptureSingle;

	(** Start continuous frame capture. *)
		PROCEDURE CaptureContinuousO*;
		BEGIN HALT(99);	(** abstract *)
		END CaptureContinuous;

	(** Stop continuous video data capture. *)
		PROCEDURE StopCaptureContinuousP*;
		BEGIN HALT(99);	(** abstract *)
		END StopCaptureContinuous;

	(** Set the frame geometry. *)
	(** columns:	number of columns of a frame *)
	(** rows:	number of rows of a frame *)
	(** frames:	number of frames allocated *)
	(** format:	AosEvenOnly, AosOddOnly, none (interlaced) *)
		PROCEDURE SetGeometryQ* (columns, rows, frames: LONGINT; format: SET);
		BEGIN HALT(99);	(** abstract *)
		END SetGeometry;
		
	END VideoCaptureDevice;

	(** The Audio object represents the audio facilities of the video capture card. *)
	AudioR* = OBJECT
		PROCEDURE & InitS* (vcd: VideoCaptureDeviceT);
		BEGIN HALT(99);	(** abstract *)
		END Init;

	(** Select the tuner for audio input. *)
		PROCEDURE SetAudioTunerU*;
		BEGIN HALT(99);	(** abstract *)
		END SetAudioTuner;
	
	(** Select external input for audio input. *)
		PROCEDURE SetAudioExternV*;
		BEGIN HALT(99);	(** abstract *)
		END SetAudioExtern;
	
	(** Select internal input for audio input. *)
		PROCEDURE SetAudioInternW*;
		BEGIN HALT(99);	(** abstract *)
		END SetAudioIntern;
	
	(** Set audio to mute. *)
		PROCEDURE SetAudioMuteX*;
		BEGIN HALT(99);	(** abstract *)
		END SetAudioMute;
	
	(** Unmute audio. *)
		PROCEDURE SetAudioUnmuteY*;
		BEGIN HALT(99);	(** abstract *)
		END SetAudioUnmute;
	
	(** Returns the mute state. *)
	(** return value:	TRUE if audio is mute, otherwise FALSE *)
		PROCEDURE IsAudioMuteZ* (): BOOLEAN;
		BEGIN HALT(99);	(** abstract *)
		END IsAudioMute;
		
	END Audio;
	
(** Get a video device. *)
(** idx:	index of video card. *)
(** return value:	a VideoCaptureDevice object *)
(** return value:	a VideoCaptureDevice object *)
PROCEDURE GetVideoDevice[* (idx: LONGINT): VideoCaptureDevice\;
	BEGIN HALT(99);	(** abstract *)
	END GetVideoDevice;

PROCEDURE GetDefaultDevice*() : VideoCaptureDevice;
VAR p : AosPlugins.Plugin;
BEGIN
	p := devices.Get ("");
	IF p = NIL THEN
		AosOut.String ("{AosTVDriver} Error: No video capture device installed.");
		AosOut.Ln;
		RETURN NIL
	END;
	ASSERT (p IS VideoCaptureDevice);
	RETURN p(VideoCaptureDevice);
END GetDefaultDevice;

PROCEDURE Cleanup;
BEGIN
	AosPlugins.main.Remove (devices)
END Cleanup;

BEGIN
	NEW(devices, "AosTVDriver", "TV drivers");
	AosModules.InstallTermHandler (Cleanup);
END AosTVDriver.

]