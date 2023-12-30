MODULE WAVRecorder; (** AUTHOR "TF,PL"; PURPOSE "WAV Recorder"; *)

IMPORT
	AosSound, AosCodecs, WMDialogs, AosOut, AosIO, AosFS, AosCommands, AosKernel;
	
TYPE 
	Recorder*= OBJECT
	VAR encoder : AosCodecs.AudioEncoder;
		soundDevice : AosSound.Driver;
		recChannel : AosSound.Channel;
		bufferPool : AosSound.BufferPool;
		buffer : AosSound.Buffer;
		out : AosIO.Writer;
		channels, rate, bits, recLength : LONGINT;
		t : AosKernel.Timer;
		
		ready, recording, paused, finished : BOOLEAN;
			
		(* Initialize Recorder with the given File *)
		PROCEDURE &Init(out : AosIO.Writer);
		VAR i, res : LONGINT;
		BEGIN
			ready := FALSE; recording := FALSE; paused := FALSE; finished := FALSE;
			SELF.out := out; recLength := 0;
			
			(* set channel properties *)
			channels := 2;
			rate := 44100;
			bits := 16;
			
			encoder := AosCodecs.GetAudioEncoder("WAV");
			IF encoder = NIL THEN
				res := WMDialogs.Message("Error", "WAV encoder not installed", {WMDialogs.ResOk});
				RETURN
			END;
			
			soundDevice := AosSound.GetDefaultDevice();
			NEW(bufferPool, 10);
			FOR i := 0 TO 9 DO
				NEW(buffer); buffer.len := 4096; NEW(buffer.data, 4096);
				bufferPool.Add(buffer)
			END;
			
			encoder.Open(out, rate, bits, channels, res);
			IF res # 0 THEN
				res := WMDialogs.Message("Error", "Header could not be written.", {WMDialogs.ResOk});
				RETURN
			END;
			
			soundDevice.OpenRecordChannel(recChannel, rate, bits, channels, AosSound.FormatPCM, res);		
			IF recChannel = NIL THEN
				res := WMDialogs.Message("Error", "Could not open record channel", {WMDialogs.ResOk});
				RETURN
			END;
			recChannel.RegisterBufferListener(WriteBuffer);
			recChannel.SetVolume(255);
			
			ready := TRUE
		END Init;
		
		PROCEDURE WriteBuffer(buf : AosSound.Buffer);
		VAR res : LONGINT;
		BEGIN
			encoder.Write(buf, res);
			INC(recLength, buf.len);
			bufferPool.Add(buf)
		END WriteBuffer;
		
		PROCEDURE Start*;
		BEGIN {EXCLUSIVE}
			IF ready THEN recChannel.Start; NEW(t); t.Sleep(100); recording := TRUE;  END
		END Start;
		
		PROCEDURE Stop*;
		VAR res : LONGINT;
		BEGIN {EXCLUSIVE}
			IF ready & recording THEN
				recording := FALSE;
				recChannel.Stop;
			END	
		END Stop;
		
		PROCEDURE Pause*;
		BEGIN {EXCLUSIVE}
			IF paused THEN recChannel.Start; paused := FALSE; recording := TRUE;
			ELSE recChannel.Pause; paused := TRUE; recording := FALSE END
		END Pause;
		
		PROCEDURE Close*;
		BEGIN {EXCLUSIVE}
			finished := TRUE;
			recording := TRUE
		END Close;
		
		PROCEDURE GetLength*() : LONGINT;
		BEGIN
			RETURN recLength;
		END GetLength;
					
	BEGIN {ACTIVE}
		IF ready THEN

			WHILE  ~finished DO
				BEGIN {EXCLUSIVE}			
					buffer := bufferPool.Remove();
					recChannel.QueueBuffer(buffer);				
					AWAIT(recording);
				END
			END;
			NEW(t); t.Sleep(1000);
			recChannel.Close;
			AosOut.String("finished recording..."); AosOut.Ln;
		END
	END Recorder;
	
	Bridge*= OBJECT
	VAR soundDevice : AosSound.Driver;
		recChannel : AosSound.Channel;
		playChannel : AosSound.Channel;
		bufferPool : AosSound.BufferPool;
		buffer : AosSound.Buffer;
		channels, rate, bits, resu : LONGINT;
		t : AosKernel.Timer;
		
		ready, recording, paused, finished : BOOLEAN;
			
		(* Initialize Recorder with the given File *)
		PROCEDURE &Init;
		VAR i, res : LONGINT;
		BEGIN
			ready := FALSE; recording := FALSE; paused := FALSE; finished := FALSE;
			
			(* set channel properties *)
			channels := 2;
			rate := 44100;
			bits := 16;
			
			(* get device *)
			soundDevice := AosSound.GetDefaultDevice();
			NEW(bufferPool, 10);
			FOR i := 0 TO 9 DO
				NEW(buffer); buffer.len := 4096; NEW(buffer.data, 4096);
				bufferPool.Add(buffer)
			END;
			
			(* open play channel *)
			soundDevice.OpenPlayChannel(playChannel, rate, bits, channels, AosSound.FormatPCM, res);		
			IF playChannel = NIL THEN
				res := WMDialogs.Message("Error", "Could not open play channel", {WMDialogs.ResOk});
				RETURN
			END;
			playChannel.RegisterBufferListener(bufferPool.Add);
			playChannel.SetVolume(255);	

			(* open record channel *)
			soundDevice.OpenRecordChannel(recChannel, rate, bits, channels, AosSound.FormatPCM, res);		
			IF recChannel = NIL THEN
				res := WMDialogs.Message("Error", "Could not open record channel", {WMDialogs.ResOk});
				RETURN
			END;
			recChannel.RegisterBufferListener(playChannel.QueueBuffer);
			recChannel.SetVolume(255);		
			
			ready := TRUE
		END Init;
		
		PROCEDURE Start*;
		BEGIN {EXCLUSIVE}
			IF ready THEN recChannel.Start; playChannel.Start; NEW(t); t.Sleep(100); recording := TRUE;  END
		END Start;
		
		PROCEDURE Stop*;
		VAR res : LONGINT;
		BEGIN {EXCLUSIVE}
			IF ready & recording THEN
				recording := FALSE;
				recChannel.Stop;
				playChannel.Stop
			END	
		END Stop;
		
		PROCEDURE Pause*;
		BEGIN {EXCLUSIVE}
			IF paused THEN recChannel.Start; playChannel.Start; paused := FALSE; recording := TRUE;
			ELSE recChannel.Pause; playChannel.Pause; paused := TRUE; recording := FALSE END
		END Pause;
		
		PROCEDURE Close*;
		BEGIN {EXCLUSIVE}
			finished := TRUE;
			recording := TRUE
		END Close;
					
	BEGIN {ACTIVE}
		IF ready THEN

			WHILE  ~finished DO
				BEGIN {EXCLUSIVE}			
					buffer := bufferPool.Remove();
					recChannel.QueueBuffer(buffer);
					AWAIT(recording);
				END
			END;
			NEW(t); t.Sleep(1000);
			recChannel.Close;
			playChannel.Close;
			AosOut.String("finished bridging..."); AosOut.Ln;
		END
	END Bridge;	

VAR recorder : Recorder;
	bridge : Bridge;
	file : AosFS.File;
	filename : ARRAY 256 OF CHAR;
	
PROCEDURE WriteRawBELongInt(VAR w: AosFS.Writer; value: LONGINT);
BEGIN
	w.Char(CHR(value MOD 100H));
	value := value DIV 100H;
	w.Char(CHR(value MOD 100H));
	value := value DIV 100H;
	w.Char(CHR(value MOD 100H));
	w.Char(CHR(value DIV 100H));
END WriteRawBELongInt;	
	
PROCEDURE Open*(par : ANY) : ANY;
VAR s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	out : AosFS.Writer;
	res : LONGINT;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	
	sr.String(filename);

	file := AosFS.New(filename);
	IF file = NIL THEN
		res := WMDialogs.Message("Error", "Could not create file", {WMDialogs.ResOk});
		RETURN NIL
	END;
	AosFS.OpenWriter(out, file, 0);

	NEW(recorder, out);
	recorder.Start;
	
	RETURN NIL
END Open;

PROCEDURE Stop*(par : ANY): ANY;
VAR writer : AosFS.Writer;
	length : LONGINT;
BEGIN
	IF recorder = NIL THEN RETURN NIL END;
	length := recorder.GetLength() + 44;
	recorder.Close;
	AosFS.Register(file);
	file.Update;
	
	file := AosFS.Old(filename);
	(* Update header info *)
	AosFS.OpenWriter(writer, file, 4);
	WriteRawBELongInt(writer, length-8);
	writer.Update;
	AosFS.OpenWriter(writer, file, 40);
	WriteRawBELongInt(writer, length-44);
	writer.Update;
	AosFS.Register(file);
	file.Update;	
	
	RETURN NIL
END Stop;

PROCEDURE StartBridge*(par : ANY): ANY;
BEGIN
	NEW(bridge);
	bridge.Start;
	
	RETURN NIL
END StartBridge;

PROCEDURE StopBridge*(par : ANY) : ANY;
BEGIN
	IF bridge = NIL THEN RETURN NIL END;
	bridge.Close;
	
	RETURN NIL
END StopBridge;


END WAVRecorder.


------------------------------------------------------------
Aosi810Sound.Install ~
S.Free WAVRecorder ~

WAVRecorder.Open test.wav~
WAVRecorder.Stop~

WAVRecorder.StartBridge~
WAVRecorder.StopBridge~