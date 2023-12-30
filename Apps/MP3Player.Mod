MODULE MP3Player; (** AUTHOR "TF,PL"; PURPOSE "MP3 Player"; *)

IMPORT
	AosSound, AosCodecs, WMDialogs, AosOut, AosIO, AosFS, AosCommands;
	
TYPE 
	Player*= OBJECT
	VAR decoder : AosCodecs.AudioDecoder;
		soundDevice : AosSound.Driver;
		playChannel : AosSound.Channel;
		bufferPool : AosSound.BufferPool;
		buffer : AosSound.Buffer;
		in : AosIO.Reader;
		channels, rate, bits : LONGINT;
		
		ready, paused, finished : BOOLEAN;
		pos, oldPos : LONGINT;
		
		setup* : PROCEDURE {DELEGATE} (canSeek: BOOLEAN; totTime, totSamp : LONGINT);
		update* : PROCEDURE {DELEGATE} (status: BOOLEAN; pos, displayTime: LONGINT);
		eof* : PROCEDURE {DELEGATE} (sender, data: ANY);
		
		(* Initialize Player with the given File *)
		PROCEDURE &Init(in : AosIO.Reader; length: LONGINT);
		VAR i, res : LONGINT;
		BEGIN
			ready := FALSE; finished := FALSE; paused := FALSE; oldPos := 0;
			SELF.in := in;
			
			decoder := AosCodecs.GetAudioDecoder("MP3");
			IF decoder = NIL THEN
				res := WMDialogs.Message("Error", "MP3 decoder not installed", {WMDialogs.ResOk});
				RETURN
			END;
			
			soundDevice := AosSound.GetDefaultDevice();
			NEW(bufferPool, 10);
			FOR i := 0 TO 9 DO
				NEW(buffer); buffer.len := 4096; NEW(buffer.data, 4096);
				bufferPool.Add(buffer)
			END;
			
			decoder.Open(in, res);
			IF res # 0 THEN
				res := WMDialogs.Message("Error", "File not compatible.", {WMDialogs.ResOk});
				RETURN
			END;
			
			(* Pass the length Information to the Decoder... *)
			decoder.SetStreamLength(length);
			
			decoder.GetAudioInfo(channels, rate, bits);
			soundDevice.OpenPlayChannel(playChannel, rate, bits, channels, AosSound.FormatPCM, res);
			IF playChannel = NIL THEN
				res := WMDialogs.Message("Error", "Could not open play channel", {WMDialogs.ResOk});
				RETURN
			END;
			playChannel.RegisterBufferListener(bufferPool.Add);
			playChannel.SetVolume(255);
			
			ready := TRUE
		END Init;
		
		PROCEDURE Play*;
		BEGIN {EXCLUSIVE}
			playChannel.Start
		END Play;
		
		PROCEDURE Stop*;
		VAR res : LONGINT;
		BEGIN {EXCLUSIVE}
			(* playChannel.Stop *)
			playChannel.Pause;
			decoder.SeekSample(0, FALSE, res);
			pos := decoder.GetCurrentTime();
			IF update # NIL THEN update(paused, pos, pos) END			
		END Stop;
		
		PROCEDURE Pause*;
		BEGIN {EXCLUSIVE}
			IF paused THEN playChannel.Start; paused := FALSE
			ELSE playChannel.Pause; paused := TRUE END
		END Pause;
		
		(* set in 1/10 sec *)
		PROCEDURE SetPos*(pos: LONGINT);
		VAR res : LONGINT;
		BEGIN {EXCLUSIVE}
			pos := ENTIER(pos / 10 * rate);
			decoder.SeekSample(pos, FALSE, res);
			pos := decoder.GetCurrentTime();
			IF update # NIL THEN update(paused, pos, pos) END
		END SetPos;
		
		(* get in  1/10 sec *)
		PROCEDURE GetPos*(): LONGINT;
		BEGIN {EXCLUSIVE}
			RETURN decoder.GetCurrentTime()
		END GetPos;
		
		PROCEDURE Close*;
		BEGIN {EXCLUSIVE}
			finished := TRUE;
		END Close;
					
	BEGIN	{ACTIVE}
		IF ready THEN
			IF setup # NIL THEN setup(TRUE, ENTIER(decoder.GetTotalSamples()/rate*10), ENTIER(decoder.GetTotalSamples()/rate*10)) END;

			WHILE decoder.HasMoreData() & ~finished DO
				buffer := bufferPool.Remove();
				decoder.FillBuffer(buffer);
				playChannel.QueueBuffer(buffer);
				pos := decoder.GetCurrentTime();
				IF (update # NIL) & (pos # oldPos) THEN update(paused, pos, pos) END;
				oldPos := pos
			END;
			playChannel.Close;
			AosOut.String("finished playing..."); AosOut.Ln;
			IF eof # NIL THEN eof(SELF, NIL) END
		END
	END Player;

VAR player : Player;
	
PROCEDURE Open*(par : ANY) : ANY;
VAR s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	filename : ARRAY 256 OF CHAR;
	file : AosFS.File;
	in : AosIO.Reader;
	res : LONGINT;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	
	sr.String(filename);

	in := AosCodecs.OpenInputStream(filename);
	IF in = NIL THEN
		res := WMDialogs.Message("Error", "File not found", {WMDialogs.ResOk});
		RETURN NIL
	END;

	file := AosFS.Old(filename);
	NEW(player, in, file.Length());
	player.Play;
	
	RETURN NIL
END Open;

PROCEDURE Stop*(par : ANY): ANY;
BEGIN
	player.Stop;
	RETURN NIL
END Stop;

END MP3Player.


------------------------------------------------------------
Aosi810Sound.Install ~
S.Free MP3Player ~

MP3Player.Open htf_44_128.mp3~
MP3Player.Open track.mp3~
MP3Player.Stop~

MP3Player.Open "FAT:/Audio/MP3/MVP/H01 Kopie.mp3"~
MP3Player.Open "FAT:/Audio/MP3/Mpegger/H01 Kopie 1.mp3"~
MP3Player.Open "FAT:/Audio/MP3/AMAZING/H01 Kopie 1.mp3"~
