MODULE PlayRecWave; (** AUTHOR "MVT"; PURPOSE "PCM-Wave-Player and -Recorder"; *)

IMPORT
	AosSound, AosFS, AosIO, AosOut, AosCommands;
	
CONST
	NofBuffers = 3; (* number of sound buffers *)
	SizeOfBuffer = 20000H; (* size of one sound buffer, 128KB *)

	(** Player/Recorder states *)
	StateStopped* = 0;
	StatePausing* = 1;
	StateRunning* = 2;
	StateClosed* = 3;
	
TYPE
	Chunk = ARRAY 4 OF CHAR; (* type of wave header part *)
	
	(* Header of a wave file *)
	WaveHeader = RECORD
		chunkRIFF: Chunk; (* must be "RIFF" *)
		fileSize: LONGINT; (* size of the whole file minus 8 byte *)
		chunkWAVE: Chunk; (* must be "WAVE" *)
		chunkfmt: Chunk; (* must be "fmt " *)
		waveFormatSize: LONGINT; (* must be 16 for PCM wave *)
		formatTag: INTEGER; (* must be 1 for PCM wave *)
		nofCh: INTEGER; (* number of channels *)
		sRate: LONGINT; (* sampling rate *)
		bRate: LONGINT; (* byte rate *)
		blockAlign: INTEGER; (* bytes per sample *)
		bitsPerSample: INTEGER; (* sampling resolution = bits per sample for 1 channel *)
		chunkdata: Chunk; (* must be "data" *)
		dataSize: LONGINT; (* size of PCM data in byte = file size minus header size *)
	END;

	(* First-In-Firt-Out Buffer for AosSound.Buffer objects *)
	FifoBuffer = OBJECT
		VAR
			buffer: POINTER TO ARRAY OF AosSound.Buffer; (* buffer array *)
			maxLen: LONGINT; (* size of fifo buffer *)
			first: LONGINT; (* array position of first buffer item *)
			items: LONGINT; (* number of items currently in buffer *)
			isEmpty: BOOLEAN; (* is buffer empty? *)
			isFull: BOOLEAN; (* is buffer full? *)
			
		(* Contructor *)
		PROCEDURE &Constr(maxLen: LONGINT);
		BEGIN
			NEW(buffer, maxLen);
			SELF.maxLen := maxLen;
			first := 0;
			items := 0;
			isEmpty := TRUE;
			isFull := FALSE;
		END Constr;
		
		(* Put an item into buffer - if full, nothing happens *)
		PROCEDURE Put(buff: AosSound.Buffer);
		BEGIN {EXCLUSIVE}
			IF items = maxLen THEN
				RETURN;
			END;
			buffer^[(first+items) MOD maxLen] := buff;
			INC(items);
			isEmpty := FALSE;
			isFull := (items = maxLen);
		END Put;
		
		(* Get next item from buffer - if empty, NIL is returned *)
		PROCEDURE Get(): AosSound.Buffer;
		VAR actual: LONGINT;
		BEGIN {EXCLUSIVE}
			IF items = 0 THEN
				RETURN NIL;
			END;
			actual := first;
			first := (first + 1) MOD maxLen;
			DEC(items);
			isFull := FALSE;
			isEmpty := (items = 0);
			RETURN buffer^[actual];
		END Get;
		
	END FifoBuffer;
	
	(** Abstract object for playing and recording wave files *)
	PlayRecWave = OBJECT
		VAR
			state*: LONGINT; (** current state of player/recorder (see constants) *)
			newState: LONGINT; (* desired new state (see constants) *)
			channel: AosSound.Channel; (* player or record channel *)
			fifo: FifoBuffer; (* FIFO buffer for sound buffers *)
			file: AosFS.File; (* the wave file *)
			buffer: AosSound.Buffer; (* temporarily used in Constr and ACTIVE part *)
			drv: AosSound.Driver; (* sound driver *)
			
		(* Constructor *)
		PROCEDURE &Constr;
		BEGIN
			state := StateClosed;
			NEW(fifo, NofBuffers);
			
			(* Get driver of default sound device *)
			drv := AosSound.GetDefaultDevice(); 
			ASSERT(drv # NIL);
			
			(* Create buffers *)
			WHILE ~fifo.isFull DO
				NEW(buffer);
				NEW(buffer.data, SizeOfBuffer);
				buffer.len := SizeOfBuffer;
				fifo.Put(buffer);
			END;
			
		END Constr;
		
		(** Start playing/recording *)
		PROCEDURE Start*;
		BEGIN {EXCLUSIVE}
			ASSERT(state # StateClosed);
			newState := StateRunning;
		END Start;
		
		(** Pause playing/recording *)
		PROCEDURE Pause*;
		BEGIN {EXCLUSIVE}
			ASSERT(state # StateClosed);
			newState := StatePausing;
		END Pause;
		
		(** Stop playing/recording *)
		PROCEDURE Stop*;
		BEGIN {EXCLUSIVE}
			ASSERT(state # StateClosed);
			newState := StateStopped;
		END Stop;
		
		(** Close wave file and playing/recording channel *)
		PROCEDURE Close*;
		BEGIN {EXCLUSIVE}
			ASSERT(state # StateClosed);
			newState := StateClosed;
		END Close;
		
		(** Wait until channel is stopped *)
		PROCEDURE AwaitStop*;
		BEGIN {EXCLUSIVE}
			AWAIT((newState = state) & ((state = StateStopped) OR (state = StateClosed)));
		END AwaitStop;
		
		(* BufferListener *)
		PROCEDURE BufferListener*(buffer: AosSound.Buffer);
		BEGIN {EXCLUSIVE}
			fifo.Put(buffer);
		END BufferListener;

	END PlayRecWave;	

	(** Object for playing wave files *)
	PlayWave* = OBJECT(PlayRecWave)
		VAR
			reader: AosFS.Reader; (* reader for wave file *)
			(* In waitingForStop state, the last buffer is queued and the player
				is waiting for it to be outputted by the driver in order to stop playing *)
			waitingForStop: BOOLEAN;

		(* Constructor *)
		PROCEDURE &ConstrPlay(fname: ARRAY OF CHAR);
		VAR
			h: WaveHeader;
			res: LONGINT;
		BEGIN
			Constr; (* call old constructor *)
			waitingForStop := FALSE;
			
			(* Open file *)
			file := AosFS.Old(fname);
			IF file = NIL THEN
				AosOut.String("PlayWave.Constr - Couldn't open file"); AosOut.Ln;
				RETURN;
			END;
			AosFS.OpenReader(reader, file, 0);
			
			(* Read header and check for correctness *)
			
			reader.Bytes(h.chunkRIFF, 0, 4, res);
			IF (res # 4) OR (h.chunkRIFF # "RIFF") THEN
				AosOut.String("PlayWave.Constr - RIFF header ID not found"); AosOut.Ln;
				RETURN;
			END;
			
			ReadRawBELongInt(reader, h.fileSize);
			IF (h.fileSize # file.Length() - 8) THEN
				AosOut.String("PlayWave.Constr - Wrong file size in header"); AosOut.Ln;
				RETURN;
			END;
			
			reader.Bytes(h.chunkWAVE, 0, 4, res);
			IF (res # 4) OR (h.chunkWAVE # "WAVE") THEN
				AosOut.String("PlayWave.Constr - WAVE header ID not found"); AosOut.Ln;
				RETURN;
			END;
			
			reader.Bytes(h.chunkfmt, 0, 4, res);
			IF (res # 4) OR (h.chunkfmt # "fmt ") THEN
				AosOut.String("PlayWave.Constr - fmt header ID not found"); AosOut.Ln;
				RETURN;
			END;
			
			ReadRawBELongInt(reader, h.waveFormatSize);
			IF (h.waveFormatSize # 16) THEN
				AosOut.String("PlayWave.Constr - Wrong header size"); AosOut.Ln;
				RETURN;
			END;
			
			reader.RawInt(h.formatTag);
			IF (h.formatTag # 1) THEN
				AosOut.String("PlayWave.Constr - Wrong wave format (must be PCM)"); AosOut.Ln;
				RETURN;
			END;
			
			ReadRawBEInteger(reader, h.nofCh);
			ReadRawBELongInt(reader, h.sRate);
			ReadRawBELongInt(reader, h.bRate);
			ReadRawBEInteger(reader, h.blockAlign);
			ReadRawBEInteger(reader, h.bitsPerSample);
			
			IF (h.blockAlign*h.sRate # h.bRate) OR (h.nofCh*(h.bitsPerSample DIV 8) # h.blockAlign) THEN
				AosOut.String("PlayWave.Constr - Inconsistent header info"); AosOut.Ln;
				RETURN;
			END;
			
			reader.Bytes(h.chunkdata, 0, 4, res);
			IF (res # 4) OR (h.chunkdata # "data") THEN
				AosOut.String("PlayWave.Constr - data header ID not found"); AosOut.Ln;
				RETURN;
			END;
			
			ReadRawBELongInt(reader, h.dataSize);
			IF (h.dataSize # file.Length() - SIZE(WaveHeader)) THEN
				AosOut.String("PlayWave.Constr - Wrong PCM data size in header"); AosOut.Ln;
				RETURN;
			END;
			
			(* Open PlayerChannel *)
			drv.OpenPlayChannel(channel, h.sRate, h.bitsPerSample, h.nofCh, AosSound.FormatPCM, res);
			IF channel = NIL THEN
				AosOut.String("PlayWave.Constr - OpenPlayChannel - Error result code (see AosSound.Mod): ");
				AosOut.Int(res, 0);
				AosOut.Ln;
				RETURN;
			END;
			
			channel.RegisterBufferListener(BufferListener);
			state := StateStopped;
			newState := state;

		END ConstrPlay;
		
	(* Active object part *)
	BEGIN {ACTIVE}
		WHILE state # StateClosed DO
			(* Wait for an event *)
			BEGIN {EXCLUSIVE}
				AWAIT((newState # state) OR (waitingForStop & fifo.isFull) OR (~waitingForStop & ~fifo.isEmpty));
			END;
			
			(* Fill and queue buffer which has been returned *)
			IF (~waitingForStop) & (~fifo.isEmpty) THEN
				buffer := fifo.Get();
				reader.Bytes(buffer.data^, 0, SizeOfBuffer, buffer.len);
				channel.QueueBuffer(buffer);
				waitingForStop := (buffer.len < SizeOfBuffer);
			END;
			
			IF waitingForStop & fifo.isFull THEN
				(* All buffers are played - stop player *)
				newState := StateStopped;
			END;
			
			(* Handle state switches *)
			IF newState # state THEN
				IF newState = StateRunning THEN
					channel.Start;
				ELSIF newState = StatePausing THEN
					channel.Pause;
				ELSIF newState = StateStopped THEN
					AosFS.OpenReader(reader, file, 0);
					channel.Stop;
					waitingForStop := FALSE;
				ELSIF newState = StateClosed THEN
					channel.RegisterBufferListener(NIL);
					channel.Stop;
					channel.Close;
				END;
				BEGIN {EXCLUSIVE}
					state := newState;
				END;
			END;
		END;
	END PlayWave;
	
	(** Object for recording wave files *)
	RecWave* = OBJECT(PlayRecWave)
		VAR
			writer: AosFS.Writer; (* writer for wave file *)
			samplePosition: LONGINT; (* data already recorded in bytes *)
			bytesPerSample: LONGINT; (* bytes per sample of this channel *)
			
		(* Constructor *)
		PROCEDURE &ConstrRec(fname: ARRAY OF CHAR; sRate, sRes, nofCh: LONGINT);
		VAR
			h: WaveHeader;
			res: LONGINT;
		BEGIN
			Constr; (* call old constructor *)
			
			(* Open file *)
			file := AosFS.New(fname);
			IF file = NIL THEN
				AosOut.String("RecWave.Constr - Couldn't create file"); AosOut.Ln;
				RETURN;
			END;
			AosFS.OpenWriter(writer, file, 0);
			
			(* Write wave header *)
			
			h.chunkRIFF[0] := "R"; h.chunkRIFF[1] := "I"; h.chunkRIFF[2] := "F"; h.chunkRIFF[3] := "F";
			writer.Bytes(h.chunkRIFF, 0, 4);
			
			h.fileSize := SIZE(WaveHeader)-8; (* for wave file with zero-length sound - will be updated later *)
			WriteRawBELongInt(writer, h.fileSize);
			
			h.chunkWAVE[0] := "W"; h.chunkWAVE[1] := "A"; h.chunkWAVE[2] := "V"; h.chunkWAVE[3] := "E";
			writer.Bytes(h.chunkWAVE, 0, 4);

			h.chunkfmt[0] := "f"; h.chunkfmt[1] := "m"; h.chunkfmt[2] := "t"; h.chunkfmt[3] := " ";
			writer.Bytes(h.chunkfmt, 0, 4);

			h.waveFormatSize := 16;
			WriteRawBELongInt(writer, h.waveFormatSize);
			
			h.formatTag := 1;
			WriteRawBEInteger(writer, h.formatTag);
			
			h.nofCh := SHORT(nofCh);
			WriteRawBEInteger(writer, h.nofCh);
			
			h.sRate := sRate;
			WriteRawBELongInt(writer, h.sRate);
			
			h.blockAlign := SHORT(nofCh * (sRes DIV 8));
			h.bRate := sRate * h.blockAlign;
			WriteRawBELongInt(writer, h.bRate);
			WriteRawBEInteger(writer, h.blockAlign);
			
			h.bitsPerSample := SHORT(sRes);
			WriteRawBEInteger(writer, h.bitsPerSample);
			
			h.chunkdata[0] := "d"; h.chunkdata[1] := "a"; h.chunkdata[2] := "t"; h.chunkdata[3] := "a";
			writer.Bytes(h.chunkdata, 0, 4);
			
			h.dataSize := 0; (* for wave file with zero-length sound - will be updated later *)
			WriteRawBELongInt(writer, h.dataSize);
			
			writer.Update;
			
			(* Open RecordChannel *)
			drv.OpenRecordChannel(channel, sRate, sRes, nofCh, AosSound.FormatPCM, res);
			IF channel = NIL THEN
				AosOut.String("RecWave.Constr - OpenRecordChannel - Error result code (see AosSound.Mod): ");
				AosOut.Int(res, 0);
				AosOut.Ln;
				RETURN;
			END;
			
			channel.RegisterBufferListener(BufferListener);
			samplePosition := 0;
			bytesPerSample := h.blockAlign;
			state := StateStopped;
			newState := state;
			
			(* Queue buffers *)
			WHILE ~fifo.isEmpty DO
				channel.QueueBuffer(fifo.Get());
			END;
			
		END ConstrRec;
		
		PROCEDURE HaltRecording;
		BEGIN
			(* Wait for all buffers to be returned *)
			BEGIN {EXCLUSIVE}
				AWAIT(fifo.isFull);
			END;
			
			(* Write remaining data to file *)
			WHILE (samplePosition > 0) & (~fifo.isEmpty) DO
				buffer := fifo.Get();
				IF samplePosition > buffer.len THEN
					writer.Bytes(buffer.data^, 0, buffer.len);
					samplePosition := samplePosition - buffer.len;
				ELSE
					writer.Bytes(buffer.data^, 0, samplePosition);
					samplePosition := 0;
				END;
				channel.QueueBuffer(buffer);
			END;
			(* Requeue remaining buffers - if any *)
			WHILE ~fifo.isEmpty DO
				channel.QueueBuffer(fifo.Get());
			END;
			writer.Update;
			
			(* Update header info *)
			AosFS.OpenWriter(writer, file, 4);
			WriteRawBELongInt(writer, file.Length()-8);
			writer.Update;
			AosFS.OpenWriter(writer, file, SIZE(WaveHeader)-4);
			WriteRawBELongInt(writer, file.Length()-SIZE(WaveHeader));
			writer.Update;
		
		END HaltRecording;
		
	(* Active object part *)
	BEGIN {ACTIVE}
		WHILE state # StateClosed DO
			(* Wait for an event *)
			BEGIN {EXCLUSIVE}
				AWAIT((newState # state) OR (~fifo.isEmpty));
			END;
			
			IF ~fifo.isEmpty THEN
				(* Write buffer to file and requeue it *)
				buffer := fifo.Get();
				writer.Bytes(buffer.data^, 0, buffer.len);
				channel.QueueBuffer(buffer);
				samplePosition := samplePosition + buffer.len;
			END;
			
			(* Handle state changes *)
			IF newState # state THEN
				IF newState = StateRunning THEN
					channel.Start;
				ELSIF newState = StatePausing THEN
					channel.Pause;
				ELSIF newState = StateStopped THEN
					samplePosition := channel.GetPosition() * bytesPerSample - samplePosition;
					channel.Stop;
					HaltRecording;
				ELSIF newState = StateClosed THEN
					samplePosition := channel.GetPosition() * bytesPerSample - samplePosition;
					channel.Stop;
					HaltRecording;
					channel.RegisterBufferListener(NIL);
					channel.Close;
					AosFS.Register(file);
				END;
				BEGIN {EXCLUSIVE}
					state := newState;
				END;
			END;		
		END;			
		
	END RecWave;

(* Module variables *)

VAR
	Rec: RecWave; (* RecWave object when recording, else NIL *)

(* Routines for reading and writing numbers in Intel's big endian format *)

PROCEDURE ReadRawBEInteger(VAR r: AosFS.Reader; VAR value: INTEGER);
BEGIN
	value := ORD(r.Get()) + 100H *ORD(r.Get());
END ReadRawBEInteger;

PROCEDURE ReadRawBELongInt(VAR r: AosFS.Reader; VAR value: LONGINT);
BEGIN
	value := LONG(ORD(r.Get())) + 100H * LONG(ORD(r.Get()))
		+ 10000H * LONG(ORD(r.Get())) + 1000000H * LONG(ORD(r.Get()));
END ReadRawBELongInt;

PROCEDURE WriteRawBEInteger(VAR w: AosFS.Writer; value: INTEGER);
BEGIN
	w.Char(CHR(value MOD 100H));
	w.Char(CHR(value DIV 100H));
END WriteRawBEInteger;

PROCEDURE WriteRawBELongInt(VAR w: AosFS.Writer; value: LONGINT);
BEGIN
	w.Char(CHR(value MOD 100H));
	value := value DIV 100H;
	w.Char(CHR(value MOD 100H));
	value := value DIV 100H;
	w.Char(CHR(value MOD 100H));
	w.Char(CHR(value DIV 100H));
END WriteRawBELongInt;

(** Public modules routines for Bluebottle calls *)

(** Play a wave file - Parameter: WaveFileName
	Note: Procedure is busy until the whole file is played *)
PROCEDURE Play*(param: PTR): PTR;
VAR
	p: AosCommands.Parameters;
	sr: AosIO.StringReader;
	fname: ARRAY 100 OF CHAR;
	play: PlayWave;
BEGIN
	(* Read parameter *)
	p := param(AosCommands.Parameters);
	NEW(sr, LEN(p.str^)); sr.Set(p.str^);
	sr.Token(fname);
	(* Create object *)	
	NEW(play, fname);
	IF play.state # StateClosed THEN
		(* Play the file *)
		play.Start;
		play.AwaitStop; 
		play.Close;
	END;
	RETURN NIL;
END Play;

(** Record a wave file - Parameters: WaveFileName SamplingRate SamplingResolution NumberOfSubChannels
	Note: Procedure returns after having started the recording! Use RecStop() for stopping it. *)
PROCEDURE RecStart*(param: PTR): PTR;
VAR
	p: AosCommands.Parameters;
	sr: AosIO.StringReader;
	fname: ARRAY 100 OF CHAR;
	sRate, sRes, nofCh: LONGINT;
BEGIN
	IF Rec = NIL THEN
		(* Read parameters *)
		p := param(AosCommands.Parameters);
		NEW(sr, LEN(p.str^)); sr.Set(p.str^);	
		sr.Token(fname); sr.SkipWhitespace;
		sr.Int(sRate, FALSE); sr.SkipWhitespace;
		sr.Int(sRes, FALSE); sr.SkipWhitespace;
		sr.Int(nofCh, FALSE);
		(* Create object *)
		NEW(Rec, fname, sRate, sRes, nofCh);
		IF Rec.state # StateClosed THEN
			(* Start recording *)
			Rec.Start;
		ELSE
			Rec := NIL;
		END;
	ELSE
		AosOut.String("PlayRecWave.RecStart - Already recording"); AosOut.Ln;
	END;
	RETURN NIL;
END RecStart;

(** Stop recording which was started before by RecStart() *)
PROCEDURE RecStop*(param: PTR): PTR;
BEGIN
	IF Rec # NIL THEN
		(* Stop recording *)
		Rec.Close;
		Rec := NIL;
	ELSE
		AosOut.String("PlayRecWave.RecStop - No recording was started before"); AosOut.Ln;
	END;
	RETURN NIL;
END RecStop;

BEGIN
	Rec := NIL; (* Init record state of module *)
END PlayRecWave.

(* EXAMPLES FOR USAGE *)

(* Usage by Aos.Call *)
(* Play - Parameter: FileName *)
Aos.Call PlayRecWave.Play FAT:/SA/Parasite.wav~
Aos.Call PlayRecWave.Play FAT:/SA/New.wav~

(* Record - Parameter: SamplingRate SamplingResolution NumberOfSubChannels *)
Aos.Call PlayRecWave.RecStart FAT:/SA/New.wav 44100 16 2~
Aos.Call PlayRecWave.RecStop

(* Usage by another program *)

VAR Play: PlayRecWave.PlayWave;
[...]
NEW(Play, "Test.wav");
Play.Start; (* start/restart playing *)
Play.Pause; (* pause playing - restart is at current position *)
Play.Stop; (* stop playing - will restart at the beginning *)
Play.Close; (* close wave file and playing channel - object can't be used anymore after this *)
Play.state (* current state of player - see constants *)

VAR Rec: PlayRecWave.RecWave;
[...]
NEW(Rec, "New.wav", samplingRate, sampingResolution, numberOfChannels);
Rec.Start; (* start/restart recording *)
Rec.Pause; (* pause recording - restart is at current position *)
Rec.Stop; (* stop recording - will restart at the beginning - existing record data will be lost *)
Rec.Close; (* close wave file and record channel - object can't be used anymore after this *)
Rec.state (* current state of recorder - see constants *)

System.Free PlayRecWave~
