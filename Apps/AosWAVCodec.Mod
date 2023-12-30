MODULE AosWAVCodec; (** AUTHOR "MVT, PL"; PURPOSE "WAV audio format Codec"; *)

IMPORT 
	AosCodecs, AosSound, AosFS, AosIO, AosOut;
	
CONST
	MAXBUF = 4096;
	
TYPE
	Chunk = ARRAY 5 OF CHAR; 								(* type of wave header part *)
	
	(* Header of a wave file *)
	WaveHeader* = RECORD
		chunkRIFF: Chunk; 									(* must be "RIFF" *)
		chunkWAVE: Chunk; 									(* must be "WAVE" *)
		chunkfmt: Chunk; 									(* must be "fmt " *)
		waveFormatSize: LONGINT; 							(* must be 16 for PCM wave *)
		formatTag: INTEGER; 								(* must be 1 for PCM wave *)
		nofCh: INTEGER; 									(* number of channels *)
		sRate: LONGINT; 									(* sampling rate *)
		bRate: LONGINT; 									(* byte rate *)
		blockAlign: INTEGER; 								(* bytes per sample *)
		bitsPerSample: INTEGER; 							(* sampling resolution = bits per sample for 1 channel *)
		chunkdata: Chunk; 									(* must be "data" *)
		fileSize: LONGINT;									(* size of the whole file minus 8 byte *)
		dataSize: LONGINT; 									(* size of PCM data in byte = file size minus header size *)
	END;

	(* Audio Wave PCM Encoder *) 
	WAVEncoder* = OBJECT(AosCodecs.AudioEncoder)
	VAR out: AosIO.Writer;
		h: WaveHeader;
		res: LONGINT;
				
		PROCEDURE Open*(out: AosIO.Writer; sRate, sRes, nofCh: LONGINT; VAR res : LONGINT);
		BEGIN
			res := -1;
			IF out = NIL THEN
				AosOut.String("WAVEncoder - Writer is NIL"); AosOut.Ln;
				RETURN;
			END;
			SELF.out := out;
			
			(* Write wave header *)			
			h.chunkRIFF[0] := "R"; h.chunkRIFF[1] := "I"; h.chunkRIFF[2] := "F"; h.chunkRIFF[3] := "F";
			out.Bytes(h.chunkRIFF, 0, 4);
			
			h.fileSize := SIZE(WaveHeader)-8; (* for wave file with zero-length sound - will be updated later *)
			WriteRawBELongInt(out, h.fileSize);
			
			h.chunkWAVE[0] := "W"; h.chunkWAVE[1] := "A"; h.chunkWAVE[2] := "V"; h.chunkWAVE[3] := "E";
			out.Bytes(h.chunkWAVE, 0, 4);

			h.chunkfmt[0] := "f"; h.chunkfmt[1] := "m"; h.chunkfmt[2] := "t"; h.chunkfmt[3] := " ";
			out.Bytes(h.chunkfmt, 0, 4);

			h.waveFormatSize := 16;
			WriteRawBELongInt(out, h.waveFormatSize);
			
			h.formatTag := 1;
			WriteRawBEInteger(out, h.formatTag);
			
			h.nofCh := SHORT(nofCh);
			WriteRawBEInteger(out, h.nofCh);
			
			h.sRate := sRate;
			WriteRawBELongInt(out, h.sRate);
			
			h.blockAlign := SHORT(nofCh * (sRes DIV 8));
			h.bRate := sRate * h.blockAlign;
			WriteRawBELongInt(out, h.bRate);
			WriteRawBEInteger(out, h.blockAlign);
			
			h.bitsPerSample := SHORT(sRes);
			WriteRawBEInteger(out, h.bitsPerSample);
			
			h.chunkdata[0] := "d"; h.chunkdata[1] := "a"; h.chunkdata[2] := "t"; h.chunkdata[3] := "a";
			out.Bytes(h.chunkdata, 0, 4);
			
			h.dataSize := 0; (* for wave file with zero-length sound - will be updated later *)
			WriteRawBELongInt(out, h.dataSize);
			
			out.Update;
			res := 0
		END Open;
		
		PROCEDURE Write*(buffer : AosSound.Buffer; VAR res : LONGINT);
		BEGIN
			out.Bytes(buffer.data^, 0, buffer.len);
			out.Update
		END Write;
	
	END WAVEncoder;
	
	(* Audio Wave PCM Decoder *)
	WAVDecoder* = OBJECT(AosCodecs.AudioDecoder)
	VAR in: AosIO.Reader;
		h: WaveHeader;		
		res: LONGINT;
		hasMoreBytes : BOOLEAN;
					
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		BEGIN
			res := -1;
			IF in = NIL THEN
				AosOut.String("WAVDecoder - InputStream is NIL"); AosOut.Ln;
				RETURN;			
			END;
			SELF.in := in;
			
			(* Read header and check for correctness *)		
			in.Bytes(h.chunkRIFF, 0, 4, res);
			IF (res # 4) OR (h.chunkRIFF # "RIFF") THEN
				AosOut.String("WAVDecoder - RIFF header ID not found"); AosOut.Ln;
				RETURN;
			END;
			
			ReadRawBELongInt(in, h.fileSize);
(*			IF (h.fileSize # file.Length() - 8) THEN
				AosOut.String("PlayWave.Constr - Warning: Wrong file size in header"); AosOut.Ln;
			END;
*)			
			in.Bytes(h.chunkWAVE, 0, 4, res);
			IF (res # 4) OR (h.chunkWAVE # "WAVE") THEN
				AosOut.String("WAVDecoder - WAVE header ID not found"); AosOut.Ln;
				RETURN;
			END;
			
			in.Bytes(h.chunkfmt, 0, 4, res);
			IF (res # 4) OR (h.chunkfmt # "fmt ") THEN
				AosOut.String("WAVDecoder - fmt header ID not found"); AosOut.Ln;
				RETURN;
			END;
			
			ReadRawBELongInt(in, h.waveFormatSize);
			IF (h.waveFormatSize # 16) THEN
				AosOut.String("WAVDecoder - Wrong header size"); AosOut.Ln;
				RETURN;
			END;
			
			in.RawInt(h.formatTag);
			IF (h.formatTag # 1) THEN
				AosOut.String("WAVDecoder - Wrong wave format (must be PCM)"); AosOut.Ln;
				RETURN;
			END;
			
			ReadRawBEInteger(in, h.nofCh);
			ReadRawBELongInt(in, h.sRate);
			ReadRawBELongInt(in, h.bRate);
			ReadRawBEInteger(in, h.blockAlign);
			ReadRawBEInteger(in, h.bitsPerSample);
			
			IF (h.blockAlign*h.sRate # h.bRate) OR (h.nofCh*(h.bitsPerSample DIV 8) # h.blockAlign) THEN
				AosOut.String("WAVDecoder - Inconsistent header info"); AosOut.Ln;
				RETURN;
			END;
			
			in.Bytes(h.chunkdata, 0, 4, res);
			IF (res # 4) OR (h.chunkdata # "data") THEN			
				AosOut.String("WAVDecoder - data header ID not found"); AosOut.Ln;
				AosOut.String("res= "); AosOut.Int(res, 0); 
				AosOut.String("h.chunkdata= "); AosOut.String(h.chunkdata); 
				RETURN;
			END;
			
			ReadRawBELongInt(in, h.dataSize);
(*			IF (h.dataSize # file.Length() - SIZE(WaveHeader)) THEN
				AosOut.String("PlayWave.Constr - Warning: Wrong PCM data size in header"); AosOut.Ln;
			END;
*)						
			hasMoreBytes := TRUE;
			res := 0
		END Open;
		
		PROCEDURE HasMoreData*():BOOLEAN;
		BEGIN	
			RETURN hasMoreBytes
		END HasMoreData;

		PROCEDURE GetAudioInfo*(VAR nofChannels, samplesPerSecond, bitsPerSample : LONGINT);
		BEGIN
			nofChannels := h.nofCh;
			bitsPerSample := h.bitsPerSample;
			samplesPerSecond := h.sRate
		END GetAudioInfo;
		
		(* Dumps part of the header *)
		PROCEDURE DumpHeader;
		BEGIN
			AosOut.String("-- WAV Header Data --"); AosOut.Ln;
			AosOut.String("h.nofCh= "); AosOut.Int(h.nofCh, 0); AosOut.Ln;					
			AosOut.String("h.sRate= "); AosOut.Int(h.sRate, 0); AosOut.Ln;						
			AosOut.String("h.bitsPerSample= "); AosOut.Int(h.bitsPerSample, 0); AosOut.Ln;
			AosOut.String("h.bRate= "); AosOut.Int(h.bRate, 0); AosOut.Ln;						
			AosOut.String("h.blockAlign= "); AosOut.Int(h.blockAlign, 0); AosOut.Ln;
			AosOut.String("h.fileSize= "); AosOut.Int(h.fileSize, 0); 
			AosOut.String("h.dataSize= "); AosOut.Int(h.dataSize, 0)
		END DumpHeader;

		PROCEDURE CanSeek*() : BOOLEAN;
		BEGIN
			AosOut.String("Not Implemented");
			RETURN FALSE;		
		END CanSeek;

		PROCEDURE GetCurrentSample*() : LONGINT;
		BEGIN 
			RETURN ENTIER((in.Pos() - (h.fileSize - h.dataSize)) / h.bRate * h.sRate)
		END GetCurrentSample;
		
		PROCEDURE GetTotalSamples*() : LONGINT;
		BEGIN 
			RETURN ENTIER(h.dataSize / h.bRate * h.sRate)
		END GetTotalSamples;	

		(* Returns the current time in 1/10 sec *)
		PROCEDURE GetCurrentTime*() : LONGINT;
		BEGIN		
			RETURN ENTIER((in.Pos() - (h.fileSize - h.dataSize)) / h.bRate * 10)
		END GetCurrentTime;
		
		PROCEDURE SetStreamLength*(length : LONGINT);
		BEGIN
			h.fileSize := length-8;
			h.dataSize := length-SIZE(WaveHeader);
		END SetStreamLength;	
		
		PROCEDURE SeekSample*(sample: LONGINT; goKeySample : BOOLEAN; VAR res : LONGINT);
		VAR seekType, itemSize: LONGINT;
		BEGIN
			seekType := AosCodecs.SeekByte;			
			(* in.Seek(seekType, h.fileSize - h.dataSize + ENTIER(sample / h.sRate * h.bRate), itemSize, res); *)
			in.SetPos(h.fileSize - h.dataSize + ENTIER(sample / h.sRate * h.bRate))			
		END SeekSample;

		PROCEDURE SeekMillisecond*(millisecond : LONGINT; goKeySample : BOOLEAN; VAR res : LONGINT);
		BEGIN
			SeekSample(ENTIER(millisecond / 1000 * h.sRate), goKeySample, res)
		END SeekMillisecond;
		
		(** Prepare the next audio bytes not yet filled into a buffer *)
		PROCEDURE Next*;
		BEGIN
		
		END Next;

		PROCEDURE FillBuffer*(buffer : AosSound.Buffer);
		VAR j : LONGINT;
		BEGIN
			in.Bytes(buffer.data^, 0, LEN(buffer.data^), buffer.len);		
			IF (in.res = AosIO.EOF) OR (buffer.len < LEN(buffer.data)) THEN
				hasMoreBytes := FALSE;
				RETURN;
			END;				
		END FillBuffer;	
	END WAVDecoder;
	
	(* Audio PCM Decoder (WAV without header) *)
	PCMDecoder* = OBJECT(AosCodecs.AudioDecoder)
	VAR in: AosIO.Reader;
		h : WaveHeader;
		res: LONGINT;
		hasMoreBytes : BOOLEAN;
					
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		BEGIN
			res := -1;
			IF in = NIL THEN
				AosOut.String("PCMDecoder - InputStream is NIL"); AosOut.Ln;
				RETURN;			
			END;
			SELF.in := in;
			
			hasMoreBytes := TRUE;
			res := 0
		END Open;
		
		PROCEDURE HasMoreData*():BOOLEAN;
		BEGIN	
			RETURN hasMoreBytes
		END HasMoreData;

		PROCEDURE GetAudioInfo*(VAR nofChannels, samplesPerSecond, bitsPerSample : LONGINT);
		BEGIN
			nofChannels := h.nofCh;
			bitsPerSample := h.bitsPerSample;
			samplesPerSecond := h.sRate
		END GetAudioInfo;
		
		PROCEDURE SetAudioInfo*(nofChannels, samplesPerSecond, bitsPerSample : LONGINT);
		BEGIN
			h.nofCh := SHORT(nofChannels);
			h.bitsPerSample := SHORT(bitsPerSample);
			h.sRate := samplesPerSecond;
			(* calc the others *)
			h.bRate := h.nofCh * h.sRate * h.bitsPerSample DIV 8;
			h.blockAlign := h.nofCh * h.bitsPerSample DIV 8
		END SetAudioInfo;

		PROCEDURE CanSeek*() : BOOLEAN;
		BEGIN
			AosOut.String("Not Implemented");
			RETURN FALSE;		
		END CanSeek;

		PROCEDURE GetCurrentSample*() : LONGINT;
		BEGIN 
			AosOut.String("pi= ");
			RETURN ENTIER(8 * in.Pos() / h.bitsPerSample / h.nofCh)
		END GetCurrentSample;
		
		PROCEDURE GetTotalSamples*() : LONGINT;
		BEGIN
			AosOut.String("pa= ");
			RETURN ENTIER(8 * h.dataSize / h.bitsPerSample / h.nofCh)
		END GetTotalSamples;	

		(* Returns the current time in 1/10 sec *)
		PROCEDURE GetCurrentTime*() : LONGINT;
		BEGIN
			AosOut.String("po= ");
			RETURN ENTIER(8 * in.Pos() / h.bitsPerSample / h.nofCh / h.sRate * 10)
		END GetCurrentTime;
		
		PROCEDURE SetStreamLength*(length : LONGINT);
		BEGIN
			h.fileSize := length+SIZE(WaveHeader)-8;
			h.dataSize := length
		END SetStreamLength;	
		
		PROCEDURE SeekSample*(sample: LONGINT; goKeySample : BOOLEAN; VAR res : LONGINT);
		VAR seekType, itemSize: LONGINT;
		BEGIN
			AosOut.String("pu= "); AosOut.Int(sample, 0);
			AosOut.String("bi= "); AosOut.Int(h.bitsPerSample, 0);
			seekType := AosCodecs.SeekByte;			
			(* in.Seek(seekType, ENTIER(sample * h.bitsPerSample / 8 * h.nofCh), itemSize, res); *)
			in.SetPos(ENTIER(sample * h.bitsPerSample / 8 * h.nofCh))		
		END SeekSample;

		PROCEDURE SeekMillisecond*(millisecond : LONGINT; goKeySample : BOOLEAN; VAR res : LONGINT);
		BEGIN
			SeekSample(ENTIER(millisecond / 1000 * h.sRate), goKeySample, res)
		END SeekMillisecond;
		
		(** Prepare the next audio bytes not yet filled into a buffer *)
		PROCEDURE Next*;
		BEGIN
		
		END Next;

		PROCEDURE FillBuffer*(buffer : AosSound.Buffer);
		VAR j : LONGINT;
		BEGIN
			in.Bytes(buffer.data^, 0, LEN(buffer.data^), buffer.len);
			IF (in.res = AosIO.EOF) OR (buffer.len < LEN(buffer.data)) THEN
				hasMoreBytes := FALSE; AosOut.String("BOOOOM!!");
				RETURN;
			END;				
		END FillBuffer;	
	END PCMDecoder;	

(* Routines for reading and writing numbers in Intel's big endian format *)
PROCEDURE ReadRawBEInteger(VAR r: AosIO.Reader; VAR value: INTEGER);
BEGIN
	value := ORD(r.Get()) + 100H *ORD(r.Get());
END ReadRawBEInteger;

PROCEDURE ReadRawBELongInt(VAR r: AosIO.Reader; VAR value: LONGINT);
BEGIN
	value := LONG(ORD(r.Get())) + 100H * LONG(ORD(r.Get()))
		+ 10000H * LONG(ORD(r.Get())) + 1000000H * LONG(ORD(r.Get()));
END ReadRawBELongInt;

PROCEDURE WriteRawBEInteger(VAR w: AosIO.Writer; value: INTEGER);
BEGIN
	w.Char(CHR(value MOD 100H));
	w.Char(CHR(value DIV 100H));
END WriteRawBEInteger;

PROCEDURE WriteRawBELongInt(VAR w: AosIO.Writer; value: LONGINT);
BEGIN
	w.Char(CHR(value MOD 100H));
	value := value DIV 100H;
	w.Char(CHR(value MOD 100H));
	value := value DIV 100H;
	w.Char(CHR(value MOD 100H));
	w.Char(CHR(value DIV 100H));
END WriteRawBELongInt;

(* -- Factories -- *)
PROCEDURE EncoderFactory*(par : ANY) : ANY;
VAR p : WAVEncoder;
BEGIN
	NEW(p);
	RETURN p
END EncoderFactory;	

PROCEDURE DecoderFactory*(par : ANY) : ANY;
VAR p : WAVDecoder;
BEGIN
	NEW(p);
	RETURN p
END DecoderFactory;

PROCEDURE PCMDecoderFactory*(par : ANY) : ANY;
VAR p : PCMDecoder;
BEGIN
	NEW(p);
	RETURN p
END PCMDecoderFactory

END AosWAVCodec.

------------------------------------------------------------------------------

S.Free AosWAVCodec;
