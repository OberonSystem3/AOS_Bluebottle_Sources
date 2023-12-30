(* DRAFT Date: 2005.04.01 *)
MODULE AosCodecs; (** AUTHOR "TF"; PURPOSE "CODEC repository"; *)

IMPORT
	AosIO, AosFS, AosSound, Raster, AosModules, Utilities, AosConfig, AosUnzip, AosInflate, AosTexts, AosOut, AosArchives;
	
CONST
	ResFailed* = -1;
	ResOk* = 0;	
	ResSeekInexact* = 1;
	
	ImgFmtBW* = 0;
	ImgFmtGrey* = 1;
	ImgFmtRGB* = 2;
	ImgFmtRGBA* = 3;
	
	STError* = -1;		(* e.g. when requested stream does not exist *)
	STUnknown* = 0;
	STAudio* = 1;
	STVideo* = 2;
	STImage* = 3;
	
	SeekByte* = 0;
	SeekSample* = 1;
	SeekKeySample* = 2;
	SeekFrame* = 3;
	SeekKeyFrame* = 4;
	
TYPE
	AVStreamInfo* = RECORD
		streamType* : LONGINT;
		seekability* : SET;
		contentType* : ARRAY 16 OF CHAR;
		
		length* : LONGINT;
		frames* : LONGINT;
		rate*: LONGINT; 
	END;
	
	FileInputStream* = OBJECT(AosIO.Reader)
	VAR 
		r : AosFS.Rider;
		f* : AosFS.File;
		streamInfo*: AVStreamInfo;
		
		PROCEDURE Receive(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		BEGIN
			f.ReadBytes(r, buf, ofs, size);
			len := size - r.res;
			IF len >= min THEN res := AosIO.Ok ELSE res := AosIO.EOF (* end of file *) END
		END Receive;
			
		PROCEDURE &InitFileReader(f : AosFS.File; pos: LONGINT);
		BEGIN
			InitReader(SELF.Receive, 4096);
			SELF.f := f; 
			f.Set(r, pos);
			streamInfo.seekability := {SeekByte};
		END InitFileReader;
		
		PROCEDURE CanSetPos*(): BOOLEAN;
		BEGIN
			RETURN TRUE;
		END CanSetPos;
		
		PROCEDURE SetPos*(pos : LONGINT);
		BEGIN
			f.Set(r, pos);
			Reset;
			received := pos;
		END SetPos;
	END FileInputStream;

	AVDemultiplexer* = OBJECT
	
		(** open the demultiplexer on an input stream *)
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		BEGIN
		END Open;
		
		PROCEDURE GetNumberOfStreams*() : LONGINT;
		BEGIN
			RETURN 0
		END GetNumberOfStreams;
		
		PROCEDURE GetStreamType*(streamNr : LONGINT): LONGINT;
		BEGIN
			RETURN -1;
		END GetStreamType;
		
		PROCEDURE GetStreamInfo*(streamNr : LONGINT): AVStreamInfo;
		BEGIN		
		END GetStreamInfo;		
		
		(* get stream streamNr *)
		PROCEDURE GetStream*(streamNr: LONGINT): DemuxStream;
		BEGIN
		END GetStream;
		
		(* read data from streamNr, store it into buffer buf starting at offset ofs, store size bytes if possible, block if not read min bytes at least. Return number of read bytes in len and return code res *)
		(* this procedure should not be directly called - it is called by the DemuxStream object! *)
		PROCEDURE GetData*(streamNr : LONGINT; VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		BEGIN
		END GetData;
		
		(* seek the streamNr to position pos (defined bz seekType), res = 0 if Ok, otherwise an error number *)
		(* this procedure should not be directly called - it is called by the DemuxStream object! *)
		PROCEDURE SetStreamPos*(streamNr : LONGINT; seekType : LONGINT; pos : LONGINT; VAR itemSize : LONGINT; VAR res : LONGINT);
		BEGIN
		END SetStreamPos;

	END AVDemultiplexer;
	
	DemuxStream* = OBJECT(AosIO.Reader)
	VAR 
		demultiplexer* : AVDemultiplexer;
		streamNr* : LONGINT;
		streamInfo* : AVStreamInfo;
		
		PROCEDURE& Open(demultiplexer : AVDemultiplexer; streamNr : LONGINT);
		BEGIN
			SELF.demultiplexer := demultiplexer; 
			SELF.streamNr := streamNr;
			InitReader(Receive, 4096)
		END Open;
	
		PROCEDURE Receive(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		BEGIN
			demultiplexer.GetData(streamNr, buf, ofs, size, min, len, res)
		END Receive;

		PROCEDURE SetPos*(pos : LONGINT);
		VAR  seekType, itemSize, res: LONGINT;
		BEGIN
			seekType := SeekByte;
			demultiplexer.SetStreamPos(streamNr, seekType, pos, itemSize, res);
			Reset
		END SetPos;

		(* seek the streamNr to position pos with seekType. itemSize contains the size of the element seeked to, if known and applicable; res = 0 if Ok, otherwise an error number *)
		PROCEDURE SetPosX*(seekType : LONGINT; pos : LONGINT; VAR itemSize : LONGINT; VAR res : LONGINT);
		BEGIN
			demultiplexer.SetStreamPos(streamNr, seekType, pos, itemSize, res);
			Reset
		END SetPosX;
	END DemuxStream;

	AudioDecoder* = OBJECT
		(* open the decoder on a file *)
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		BEGIN
		END Open;
		
		PROCEDURE HasMoreData*():BOOLEAN;
		END HasMoreData;

		PROCEDURE GetAudioInfo*(VAR nofChannels, samplesPerSecond, bitsPerSample : LONGINT);
		BEGIN
		END GetAudioInfo;
		
		PROCEDURE SetAudioInfo*(nofChannels, samplesPerSecond, bitsPerSample : LONGINT);
		BEGIN
		END SetAudioInfo;

		PROCEDURE CanSeek*() : BOOLEAN;
		BEGIN RETURN FALSE
		END CanSeek;

		PROCEDURE GetCurrentSample*() : LONGINT;
		BEGIN HALT(301); RETURN 0
		END GetCurrentSample;
		
		PROCEDURE GetTotalSamples*() : LONGINT;
		BEGIN HALT(301); RETURN 0
		END GetTotalSamples;	

		PROCEDURE GetCurrentTime*() : LONGINT;
		BEGIN HALT(301); RETURN 0
		END GetCurrentTime;
		
		PROCEDURE SetStreamLength*(length : LONGINT);
		BEGIN
		END SetStreamLength;	
		
		PROCEDURE SeekSample*(sample: LONGINT; goKeySample : BOOLEAN; VAR res : LONGINT);
		BEGIN
		END SeekSample;

		PROCEDURE SeekMillisecond*(millisecond : LONGINT; goKeySample : BOOLEAN; VAR res : LONGINT);
		BEGIN
		END SeekMillisecond;
		
		(** Prepare the next audio bytes not yet filled into a buffer *)
		PROCEDURE Next*;
		BEGIN
		END Next;

		PROCEDURE FillBuffer*(buffer : AosSound.Buffer);
		BEGIN
		END FillBuffer;
		
	END AudioDecoder;
	
	AudioEncoder* = OBJECT
		(* open the encoder *)
		PROCEDURE Open*(out : AosIO.Writer; sRate, sRes, nofCh: LONGINT; VAR res : LONGINT);
		BEGIN
		END Open;
		
		PROCEDURE Write*(buffer : AosSound.Buffer; VAR res : LONGINT);
		BEGIN
		END Write;
	
		PROCEDURE Close*(VAR res : LONGINT);
		BEGIN
		END Close;
	
	END  AudioEncoder;	

	VideoDecoder* = OBJECT
		(* open the decoder on a file *)
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		BEGIN
		END Open;
		
		PROCEDURE HasMoreData*():BOOLEAN;
		BEGIN
		END HasMoreData;

		PROCEDURE GetVideoInfo*(VAR width, height, millisecondsPerFrame : LONGINT);
		BEGIN
		END GetVideoInfo;
		
		PROCEDURE CanSeek*() : BOOLEAN;
		BEGIN RETURN FALSE
		END CanSeek;
		
		PROCEDURE GetCurrentFrame*() : LONGINT;
		BEGIN
		END GetCurrentFrame;

		PROCEDURE GetCurrentTime*() : LONGINT;
		BEGIN
		END GetCurrentTime;
		
		PROCEDURE SeekFrame*(frame : LONGINT; goKeyFrame : BOOLEAN; VAR res : LONGINT);
		BEGIN
		END SeekFrame;	

		PROCEDURE SeekMillisecond*(millisecond : LONGINT; goKeyFrame : BOOLEAN; VAR res : LONGINT);
		BEGIN
		END SeekMillisecond;
		
		(** Prepare the next frame *)
		PROCEDURE Next*;
		BEGIN
		END Next;
		
		PROCEDURE Render*(img : Raster.Image);
		BEGIN
		END Render;
		
	END VideoDecoder;
	
	ImageDecoder* = OBJECT
		(* open the decoder on an InputStream *)
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		BEGIN
		END Open;
		
		PROCEDURE GetImageInfo*(VAR width, height, format, maxProgressionLevel : LONGINT);
		BEGIN
		END GetImageInfo;
		
		(** Render will read and decode the image data up to progrssionLevel.
			If the progressionLevel is lower than a previously rendered progressionLevel, 
			the new level can be ignored by the decoder. If no progressionLevel is set with
			SetProgressionLevel, the level is assumed to be maxProgressionLevel of the image, 
			which corresponds to best image quality.
		 *)
		PROCEDURE SetProgressionLevel*(progressionLevel: LONGINT);
		BEGIN
		END SetProgressionLevel;
		
		(* return the image in Raster format that best matches the format *)
		PROCEDURE GetNativeImage*(VAR img : Raster.Image);
		BEGIN
		END GetNativeImage;

		(* renders the image into the given Raster.Image at the given progressionLevel *)
		PROCEDURE Render*(img : Raster.Image);
		BEGIN
		END Render;
		
	END ImageDecoder;
	
	
	ImageEncoder* = OBJECT
		(* open the encoder on a stream*)
		PROCEDURE Open*(out : AosIO.Writer);
		BEGIN
		END Open;
		
		PROCEDURE SetQuality*(quality : LONGINT);
		BEGIN
		END SetQuality;
		
		PROCEDURE WriteImage*(img : Raster.Image; VAR res : LONGINT);
		BEGIN
		END WriteImage;
		
	END ImageEncoder;


	TextDecoder* = OBJECT
		(* open the decoder on an InputStream *)
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		BEGIN
		END Open;
		
		PROCEDURE GetText*() : AosTexts.Text;
		BEGIN
			HALT(301); RETURN NIL
		END GetText;
	END TextDecoder;

	TextEncoder* = OBJECT
		(* open the encoder on a stream*)
		PROCEDURE Open*(out : AosIO.Writer);
		BEGIN
		END Open;
		
		PROCEDURE WriteText*(text : AosTexts.Text; VAR res : LONGINT);
		BEGIN
		END WriteText;
	END TextEncoder;
	
	CryptoDecoder* = OBJECT
		PROCEDURE Open*(in: AosIO.Reader; VAR res: LONGINT);
		BEGIN
		END Open;
		
		PROCEDURE GetReader*(): AosIO.Reader;
		BEGIN
		END GetReader;
	END CryptoDecoder;
	
	CryptoEncoder* = OBJECT
		PROCEDURE Open*(out: AosIO.Writer);
		BEGIN
		END Open;
		
		PROCEDURE GetWriter*(): AosIO.Writer;
		BEGIN
		END GetWriter;
	END CryptoEncoder;
	
PROCEDURE GetDemuxFactory(name : ARRAY OF CHAR) : AosModules.CommandParProc;
VAR config, factoryName : ARRAY 128 OF CHAR;
BEGIN
	config := "Codecs.Demultiplexer."; Utilities.Append(config, name);
	AosConfig.Get(config, factoryName);
	IF factoryName # "" THEN RETURN AosModules.GetCommandByString(factoryName) 
	ELSE RETURN NIL
	END
END GetDemuxFactory;
	
PROCEDURE GetDecoderFactory(type, name : ARRAY OF CHAR) : AosModules.CommandParProc;
VAR config, factoryName : ARRAY 128 OF CHAR;
BEGIN
	config := "Codecs.Decoder."; Utilities.Append(config, type); Utilities.Append(config, ".");
	Utilities.Append(config, name);
	AosConfig.Get(config, factoryName);
	IF factoryName # "" THEN RETURN AosModules.GetCommandByString(factoryName) 
	ELSE RETURN NIL
	END
END GetDecoderFactory;

PROCEDURE GetEncoderFactory(type, name : ARRAY OF CHAR) : AosModules.CommandParProc;
VAR config, factoryName : ARRAY 128 OF CHAR;
BEGIN
	config := "Codecs.Encoder."; Utilities.Append(config, type); Utilities.Append(config, ".");
	Utilities.Append(config, name);
	AosConfig.Get(config, factoryName);
	IF factoryName # "" THEN RETURN AosModules.GetCommandByString(factoryName) 
	ELSE RETURN NIL
	END
END GetEncoderFactory;


(** Return a registered demultiplexer e.g. "AVI" *)
PROCEDURE GetDemultiplexer*(name : ARRAY OF CHAR) : AVDemultiplexer;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetDemuxFactory(name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS AVDemultiplexer) THEN RETURN p(AVDemultiplexer)
		ELSE RETURN NIL
		END
	ELSE RETURN NIL	
	END
END GetDemultiplexer;

(** Return a registered image decoder e.g. "JP2", "BMP", "PNG" *)
PROCEDURE GetImageDecoder*(name : ARRAY OF CHAR) : ImageDecoder;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetDecoderFactory("Image", name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS ImageDecoder) THEN RETURN p(ImageDecoder)
		ELSE RETURN NIL
		END	
	ELSE RETURN NIL	
	END
END GetImageDecoder;

(** Return a registered image decoder e.g. "BMP" *)
PROCEDURE GetImageEncoder*(name : ARRAY OF CHAR) : ImageEncoder;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetEncoderFactory("Image", name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS ImageEncoder) THEN RETURN p(ImageEncoder)
		ELSE RETURN NIL
		END	
	ELSE 
		RETURN NIL	
	END
END GetImageEncoder;

(** Return a registered video decoder. The decoder name is typically a FourCC code  e.g. "DivX" *)
PROCEDURE GetVideoDecoder*(name : ARRAY OF CHAR) : VideoDecoder;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetDecoderFactory("Video", name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS VideoDecoder) THEN RETURN p(VideoDecoder)
		ELSE RETURN NIL
		END
	ELSE RETURN NIL	
	END
END GetVideoDecoder;

(** Return a registered audio decoder e.g. "MP3" *)
PROCEDURE GetAudioDecoder*(name : ARRAY OF CHAR) : AudioDecoder;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetDecoderFactory("Audio", name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS AudioDecoder) THEN RETURN p(AudioDecoder)
		ELSE RETURN NIL
		END
	ELSE RETURN NIL	
	END
END GetAudioDecoder;

(** Return a registered audio encoder e.g. "WAV" *)
PROCEDURE GetAudioEncoder*(name : ARRAY OF CHAR) : AudioEncoder;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetEncoderFactory("Audio", name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS AudioEncoder) THEN RETURN p(AudioEncoder)
		ELSE RETURN NIL
		END
	ELSE RETURN NIL	
	END
END GetAudioEncoder;

PROCEDURE GetTextDecoder*(name : ARRAY OF CHAR) : TextDecoder;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetDecoderFactory("Text", name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS TextDecoder) THEN RETURN p(TextDecoder)
		ELSE RETURN NIL
		END	
	ELSE RETURN NIL	
	END
END GetTextDecoder;

(** Return a registered image decoder e.g. "BMP" *)
PROCEDURE GetTextEncoder*(name : ARRAY OF CHAR) : TextEncoder;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetEncoderFactory("Text", name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS TextEncoder) THEN RETURN p(TextEncoder)
		ELSE RETURN NIL
		END	
	ELSE 
		RETURN NIL	
	END
END GetTextEncoder;

(** Return a registered crypto decoder *)
PROCEDURE GetCryptoDecoder*(name : ARRAY OF CHAR) : CryptoDecoder;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetDecoderFactory("Crypto", name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS CryptoDecoder) THEN RETURN p(CryptoDecoder)
		ELSE RETURN NIL
		END	
	ELSE
		RETURN NIL	
	END
END GetCryptoDecoder;

(** Return a registered crypto encoder *)
PROCEDURE GetCryptoEncoder*(name : ARRAY OF CHAR) : CryptoEncoder;
VAR p : ANY;
	factory : AosModules.CommandParProc;
BEGIN
	factory := GetEncoderFactory("Crypto", name);
	IF factory # NIL THEN 
		p := factory(NIL);
		IF (p # NIL) & (p IS CryptoEncoder) THEN RETURN p(CryptoEncoder)
		ELSE RETURN NIL
		END	
	ELSE 
		RETURN NIL	
	END
END GetCryptoEncoder;

PROCEDURE SplitName(VAR name : ARRAY OF CHAR; VAR protocol, filename : ARRAY OF CHAR);
VAR pos, i : LONGINT;
BEGIN
	pos := Utilities.Pos("://", name);
	IF pos >= 0 THEN
		FOR i := 0 TO pos - 1 DO protocol[i] := name[i] END;
		protocol[pos] := 0X;
		INC(pos, 3);	i := 0; WHILE name[pos] # 0X DO filename[i] := name[pos]; INC(pos); INC(i) END;
		filename[i] := 0X
	ELSE COPY(name, filename)
	END
END SplitName;

PROCEDURE OpenInputStream*(name : ARRAY OF CHAR) : AosIO.Reader;
VAR f : AosFS.File;
	is : FileInputStream;
	inpStream : AosIO.Reader;
	r : AosIO.Receiver;
	tp, protocol, filename : ARRAY 1024 OF CHAR;
	zf : AosUnzip.ZipFile;
	entry : AosUnzip.Entry;
	archive : AosArchives.Archive;
	res : LONGINT;
BEGIN
	SplitName(name, protocol, filename); 
	COPY(protocol, tp); Utilities.LowerCase(tp);
	IF protocol = "" THEN 
		f := AosFS.Old(filename);
		IF f = NIL THEN RETURN NIL END;
		NEW(is, f, 0);
		RETURN is
	ELSIF Utilities.Match("*.zip", protocol) THEN
		f := AosFS.Old(protocol);
		IF f = NIL THEN RETURN NIL END;
		NEW(zf, f, res);
		IF res = 0 THEN 
			entry := zf.FindEntry(filename);
			IF entry # NIL THEN 
				zf.OpenReceiver(r, entry, res);
				IF res = 0 THEN 
					NEW(inpStream, r, 1024);
					RETURN inpStream
				ELSE RETURN NIL
				END
			ELSE RETURN NIL
			END	
		ELSE RETURN NIL
		END
	ELSIF Utilities.Match("*.skin", protocol) THEN
		archive := AosArchives.Old(protocol, "skin");
		IF archive = NIL THEN 
			RETURN NIL
		ELSE
			archive.Acquire; r := archive.OpenReceiver(filename); archive.Release;
			IF r = NIL THEN
				RETURN NIL
			ELSE
				NEW(inpStream, r, 1024);
				RETURN inpStream
			END
		END
	ELSIF Utilities.Match("*.tar", protocol) THEN
		archive := AosArchives.Old(protocol, "tar");
		IF archive = NIL THEN 
			RETURN NIL
		ELSE
			archive.Acquire; r := archive.OpenReceiver(filename); archive.Release;
			IF r = NIL THEN
				RETURN NIL
			ELSE
				NEW(inpStream, r, 1024);
				RETURN inpStream
			END
		END
	END;
	RETURN NIL
END OpenInputStream;

END AosCodecs.

--------------------------
S.Free AosCodecs~