MODULE AVI;

(* Prozedures to read an .avi file *)
(* Written by Thomas Trachsel, ttrachsel@web.de, 18.9.2003 *)

IMPORT
	AosFS, AosIO, AosOut, SYSTEM;
	
	CONST
		Debug =FALSE;

	TYPE
		(* Structure that contains the main informations of the .avi file *)
		MainAVIHeaderPtr* = POINTER TO MainAVIHeaderDesc;
		MainAVIHeaderDesc* = RECORD
			microSecsPerFrame*: LONGINT;
			maxBytesPerSec*: LONGINT;
			reserved1*: LONGINT;
			flags*: LONGINT;
			totalFrames*: LONGINT;
			initialFrames*: LONGINT;
			streams*: LONGINT;
			suggestedBufferSize*: LONGINT;
			width*: LONGINT;
			height*: LONGINT;
			reserved*: ARRAY 4 OF LONGINT;
		END;
		
		(* Structure that contains the main Info of a stream in a .avi file *)
		AVIStreamHeaderPtr* = POINTER TO AVIStreamHeader;
		AVIStreamHeader* = RECORD
			fccType: ARRAY 4 OF CHAR;
			fccHandler*: ARRAY 4 OF CHAR;
			flags*: LONGINT;
			priority*: LONGINT;
			initialFrames*: LONGINT;
			scale*: LONGINT;
			rate*: LONGINT;
			start*: LONGINT;
			length*: LONGINT;
			suggestedBufferSize*: LONGINT;
			quality*: LONGINT;
			sampleSize*: LONGINT;
			left*: LONGINT;
			top*: LONGINT;
			right*: LONGINT;
			bottom*: LONGINT;
			streamIdentifier*: ARRAY 4 OF CHAR;
			bitMapInfo*: BitMapInfoPtr;
			waveFormatEx*: WAVEFormatExPtr;
		END;

		(* video stream specific infos *)
		BitMapInfoPtr* = POINTER TO BitMapInfo;
		BitMapInfo = RECORD
			size*: LONGINT;
			width*: LONGINT;
			height*: LONGINT;
			planes*: LONGINT;
			bitCount*: LONGINT;
			compression*: LONGINT;
			sizeImage*: LONGINT;
			xPelsPerMeter*: LONGINT;
			yPelsPerMeter*: LONGINT;
			clrUsed*: LONGINT;
			clrImportant*: LONGINT;
		END;
		
		(* audio stream specific infos *)
		WAVEFormatExPtr* = POINTER TO WAVEFormatEx;
		WAVEFormatEx* = RECORD
			formatTag*: LONGINT;
			channels*: LONGINT;
			samplesPerSec*: LONGINT;
			avgBytesPerSec*: LONGINT;
			blockAlign*: LONGINT;
			bitsPerSample*: LONGINT;
			cbSize*: LONGINT;
		END;

	(* Stream for reading a Stream of an .avi file *)
	TYPE AVIStream* = OBJECT
		VAR
			index*: LONGINT;	(* Position (Bit) in buf *)
			bufAdr: LONGINT;
			buf: POINTER  TO ARRAY OF CHAR;	(* Local buffer, contains the data for decoding one frame *)
			r: AVIReader;
			chunkSize*: LONGINT;	(* Bytes in actual AVI Chunk *)
			streamHeader: AVIStreamHeaderPtr;
			aviHeader: MainAVIHeaderPtr;
			stuffByte: LONGINT;
			eof*: BOOLEAN;	(* End of File *)
			
		(* Constructor *)
		PROCEDURE & Init( r: AVIReader; aviHdr: MainAVIHeaderPtr; streamHdr: AVIStreamHeaderPtr );
		BEGIN
			index :=  -1; (* index is in the beginning not valid  *)
			bufAdr := 0;
			chunkSize := 0;
			streamHeader := streamHdr;
			aviHeader := aviHdr;
			SELF.r := r;
			ASSERT(SELF.r # NIL);
			stuffByte := 0;
			eof := FALSE;
			buf := NIL
		END Init;

		(* Align stream to next Byte *)
		PROCEDURE Align*( );
		BEGIN
			IF ( index MOD 8 ) # 0 THEN
				index :=  index - ( index MOD 8 ) + 8
			END;
		END Align;

		(* True if actual position is on byte boundary *)
		PROCEDURE IsAligned*(): BOOLEAN;
		BEGIN
			IF ( index MOD 8 ) = 0 THEN
				RETURN TRUE
			ELSE
				RETURN FALSE
			END;
		END IsAligned;
		
	(* Read next n Bits (max 32), without advancing in stream. Max 32 Bits are allowed *)
	(* Very slow but portable *)
		PROCEDURE ShowBitsSlow*( n: LONGINT ): LONGINT;
		VAR
			ret: LONGINT;
			count: LONGINT;
		BEGIN
			ret := 0;
			count := 0;
			
			WHILE count < n DO
				ret := ret * 2;
				IF ( 7 - ( index MOD 8 ) ) IN SYSTEM.VAL( SET, buf[index DIV 8] ) THEN
					INC(ret)
				END;
				INC( index );
				INC( count )
			END;
			
			index := index - count;

			RETURN ret
		END ShowBitsSlow;

	 	(* Fast function for changing byte order, but only for  >= i486 *)
	 	PROCEDURE ChangeByteOrder( n: LONGINT ): LONGINT;
		CODE { SYSTEM.i486 }
			MOV EAX, n[EBP]				; load n in eax
			BSWAP EAX			 ; swap byte order
		END ChangeByteOrder;
	 	
		(* Read next n Bits (max 32), without advancing in stream. Max 32 Bits are allowed *)
		(* Fast, but im not sure if it's portable *)
		PROCEDURE ShowBits*( n: LONGINT ): LONGINT;
		VAR
			nbit: LONGINT; 
			posInLONGINT: LONGINT;
			bufa, bufb: LONGINT;
			temp: LONGINT;
		BEGIN
			posInLONGINT := index MOD 32;
			nbit := ( posInLONGINT+ n ) - 32;
			
			IF nbit > 0 THEN
				(* We have to read two 32 bit values *)
				temp := SYSTEM.LSH( index - posInLONGINT , -3 ) + bufAdr;
				bufa := ChangeByteOrder( SYSTEM.GET32( temp ) );
				bufb := ChangeByteOrder( SYSTEM.GET32( temp + 4 ) );
				
				 temp := SYSTEM.LSH( SYSTEM.LSH( bufa, posInLONGINT ),  nbit - posInLONGINT );
				RETURN SYSTEM.VAL( LONGINT, SYSTEM.VAL( SET, SYSTEM.LSH( bufb, nbit - 32 ) ) + SYSTEM.VAL( SET, temp ) )
			ELSE
				(* Reading one 32 value is sufficient *)
				bufa := ChangeByteOrder( SYSTEM.GET32( SYSTEM.LSH( index - posInLONGINT, -3 ) + bufAdr ) );
				
				RETURN SYSTEM.LSH( SYSTEM.LSH( bufa, posInLONGINT ),  n - 32 )
			END;
		END ShowBits;
	 	 	 
	 (* Show n bits, byte aligned without advancing in bit stream *)
		PROCEDURE ShowBitsByteAligned*(n: LONGINT): LONGINT;
		VAR
			count: LONGINT;
			ret: LONGINT;
		BEGIN
			count := 8 - ( index MOD 8 );
			
			IF count = 8 THEN
				IF ShowBits( 8 ) = 7FH THEN (* Spezial case: see iso spec *)
					count := 8
				ELSE
					count := 0
				END;
			END;
			
			index := index + count;
			ret := ShowBits( n );
			index := index - count;
			RETURN ret
		END ShowBitsByteAligned;

		(* Compare two array up to len bytes *)
		PROCEDURE CompareCharArrays(ar1,ar2 : ARRAY OF CHAR; len: LONGINT ): BOOLEAN;
		VAR
			i: LONGINT;
		BEGIN
			IF ( len > LEN( ar1 ) ) OR ( len > LEN( ar2 ) ) THEN
				RETURN FALSE
			END;
			
			FOR i := 0 TO len-1 DO
				IF ar1[i] # ar2[i] THEN 
					RETURN FALSE
				END;
			END;
			RETURN TRUE
		END CompareCharArrays;
												
		(* Read next n Bits and advance in Bit Stream. Max 32 Bits are allowed *)
		PROCEDURE GetBits*( n: LONGINT ): LONGINT;
		VAR
			ret: LONGINT;
		BEGIN
			ret := ShowBits( n );
			SkipBits( n );
			RETURN ret
		END GetBits;

		(* Skip Next n Bits *)
		PROCEDURE SkipBits*(n: LONGINT );
		BEGIN
			index := index + n
		END SkipBits;

		(* Seek the next chunk of our stream in the avi fileand read it *)
		PROCEDURE  ReadNextChunk();
		VAR 
			tempBuf: ARRAY 4 OF CHAR;
			len: LONGINT;
			done: BOOLEAN;
		BEGIN
			done := FALSE;
			eof := FALSE;
			
			(* Undocument in .avi docu; if the size of a chunk is odd, we have to skip one byte *)
			IF stuffByte > 0 THEN
				r.SkipBytes( 1 );
				stuffByte := 0
			END;
			
			REPEAT
				r.Bytes(tempBuf, 0, 4, len );
				IF r.res = AosIO.Ok THEN
					r.ReadLONGINT( len );
					stuffByte := len MOD 2;
					IF r.res = AosIO.Ok THEN 
						IF Debug THEN
							AosOut.String( "AVIStream: Found Chunk : " );
							AosOut.Hex( ORD( tempBuf[0] ), 0 ); AosOut.Hex( ORD( tempBuf[1] ), 0 ); 
							AosOut.Hex( ORD( tempBuf[2] ), 0 ); AosOut.Hex( ORD( tempBuf[3] ), 0 ); AosOut.String(" ");
							AosOut.Char( tempBuf[0] ); AosOut.Char( tempBuf[1] ); AosOut.Char( tempBuf[2] ); 
							AosOut.Char( tempBuf[3] ); AosOut.String( "@Pos: "); AosOut.Int( r.Pos() - 8, 0 ); 
							AosOut.String( " SkipBytes: " ); AosOut.Int( len, 0 ); AosOut.Ln()
						END;
						IF CompareCharArrays( tempBuf, streamHeader.streamIdentifier, 4 ) THEN
							(* We found the correct chunk *)
							IF len > 0 THEN
								done := TRUE;
								NEW( buf, len + 4 );
								bufAdr := SYSTEM.ADR( buf[0] );
								r.Bytes( buf^, 0, len, chunkSize );
								buf[len] := CHR( 0 ); buf[len+1] := CHR( 0 ); buf[len+2] := CHR( 0 ); buf[len+3] := CHR( 0 );
								ASSERT( len = chunkSize );
								index := 0
							END;
						ELSE
							r.SkipBytes( len + stuffByte )
						END;
					ELSE 
						eof := TRUE
					END;
				ELSE
					eof := TRUE
				END; 
			UNTIL ( done OR eof );
		END ReadNextChunk;
		
		(* Go to the beginnig of the next frame -> Read next chunk *)
		PROCEDURE Resynch*(): BOOLEAN;
		BEGIN
			ReadNextChunk();
			RETURN ~eof
		END Resynch;
		
		(* Return Pos in Avi File, relativ to the beginning of the stream data *)
		PROCEDURE FilePos*(): LONGINT;
		BEGIN
			RETURN r.Pos()
		END FilePos;
		
		(* Get Header of the avi File *)
		PROCEDURE GetAVIHeader*(): MainAVIHeaderPtr;
		BEGIN
			RETURN aviHeader
		END  GetAVIHeader;
		
		(* Get Header of our Stream *)
		PROCEDURE GetAVIStreamHeader*(): AVIStreamHeaderPtr;
		BEGIN
			RETURN streamHeader
		END GetAVIStreamHeader;
	
	END AVIStream;
	
	(* Reader that provides platform independence *)
	TYPE AVIReader* = OBJECT(AosFS.Reader)
	VAR
	
		PROCEDURE ReadLONGINT*( VAR n: LONGINT );
		BEGIN
			n := LONG( ORD( Get() ) ) + LONG( ORD( Get() ) )*100H + LONG( ORD( Get() ) )*10000H 
			+ LONG( ORD( Get() ) )*1000000H;
		END ReadLONGINT;
		
		PROCEDURE ReadINTEGER*( VAR n: INTEGER );
		BEGIN
			n := SHORT( ORD( Get() ) ) + SHORT( ORD( Get() ) )*100H;
		END ReadINTEGER;
	END AVIReader;
	
	(* The .avi File Demultiplexer *)
	TYPE AVIDemux* = OBJECT 
		VAR 
			file: AosFS.File;
			fileName: ARRAY 255 OF CHAR;
			(* We need just these 3 Headers *)
			aviHeader: MainAVIHeaderPtr;
			audioStreamHeader: AVIStreamHeaderPtr;
			videoStreamHeader: AVIStreamHeaderPtr;
			riffLength: LONGINT;
			r: AVIReader;

		PROCEDURE &Init( fileID: AosFS.File );
		BEGIN
			file := fileID
		END Init;
		
		PROCEDURE GetAVIHeader*(): MainAVIHeaderPtr;
		BEGIN
			RETURN aviHeader
		END  GetAVIHeader;
		
		(* Compare two arrays up to len bytes *)
		PROCEDURE CompareCharArrays( ar1,ar2 : ARRAY OF CHAR; len: LONGINT ): BOOLEAN;
		VAR
			i: LONGINT;
		BEGIN
			IF ( len > LEN( ar1 ) ) OR ( len > LEN( ar2 ) ) THEN
				RETURN FALSE
			END;
			
			FOR i := 0 TO len-1 DO
				IF ar1[i] # ar2[i] THEN 
					RETURN FALSE
				END;
			END;
			RETURN TRUE
		END CompareCharArrays;
		
		(* Read .avi FIle Header *) 
		PROCEDURE ReadHeader*(): BOOLEAN;
		VAR 
			buf : ARRAY 8 OF CHAR;
			len: LONGINT;
			done: BOOLEAN;
			headerLength: LONGINT;
			headerBeginPos: LONGINT;
			tempHeader: AVIStreamHeaderPtr;
			temp: LONGINT;
			streamNumber: SHORTINT;
		BEGIN
			done := FALSE;
			streamNumber := 0;
			riffLength := 0;
			aviHeader := NIL;
			audioStreamHeader := NIL;
			videoStreamHeader := NIL;

			(* Open File *)
			NEW( r, file, 0 );
			ASSERT(r # NIL);
			
			(* Check, if we have a valid avi file *)
			r.Bytes( buf,0,4,len );
			IF CompareCharArrays( buf, "RIFF" ,4 ) # TRUE THEN
				AosOut.String( "Not a valid .avi File!" ); AosOut.Ln;
				RETURN FALSE
			END;
			r.ReadLONGINT( riffLength );
			
			r.Bytes( buf,0,4, len );
			IF CompareCharArrays( buf, "AVI ",4 ) # TRUE THEN
				AosOut.String( "Only .avi Files that contain a video stream are allowed" ); AosOut.Ln();
				RETURN FALSE
			END;
	
			(* Read AVI Headers *)
			REPEAT 
				r.Bytes( buf,0,4, len );
				IF CompareCharArrays( buf, "LIST",4 ) THEN
					(* We found an additional Header *)
					(* Store Infos about header *)
					r.ReadLONGINT( headerLength );
					headerLength := headerLength + headerLength MOD 2;
					headerBeginPos := r.Pos();
					r.Bytes( buf,0,4, len );
					
					(* Main AVI Header *)
					IF CompareCharArrays(buf, "hdrl",4) THEN
						r.Bytes( buf,0,4, len );
						IF CompareCharArrays(buf, "avih",4) THEN
								aviHeader := ReadMainAVIHeader()
						ELSE
							SkipHeader()
						END;
					(* Stream Header *)
					ELSIF CompareCharArrays( buf, "strl",4 ) THEN 
						r.Bytes( buf,0,4, len );
						IF CompareCharArrays( buf, "strh",4 ) THEN
							tempHeader := ReadAVIStreamHeader();
						
							IF CompareCharArrays(tempHeader.fccType, "vids",4) THEN
								r.SkipBytes(4); (* Skip "strf" *)
	
								IF videoStreamHeader = NIL THEN
									videoStreamHeader := tempHeader;
									videoStreamHeader.streamIdentifier[0] := "0";
									videoStreamHeader.streamIdentifier[1] := CHR( ORD( '0' ) + streamNumber );
									videoStreamHeader.streamIdentifier[2] := "d";
									videoStreamHeader.streamIdentifier[3] := "c";
									INC(streamNumber)
								END;
								tempHeader := NIL;
								
								IF videoStreamHeader.bitMapInfo = NIL THEN
									videoStreamHeader.bitMapInfo := ReadBitMapInfo();
									videoStreamHeader.waveFormatEx := NIL
								ELSE
									SkipHeader()
								END;
							ELSIF CompareCharArrays(tempHeader.fccType, "auds",4) THEN
								r.SkipBytes(4);
							
								IF audioStreamHeader = NIL THEN
									audioStreamHeader := tempHeader;
									audioStreamHeader.streamIdentifier[0] := "0";
									audioStreamHeader.streamIdentifier[1] := CHR( ORD('0') + streamNumber );
									audioStreamHeader.streamIdentifier[2] := "w";
									audioStreamHeader.streamIdentifier[3] := "b";
									INC(streamNumber)
								END;
								tempHeader := NIL;
							
								IF audioStreamHeader.waveFormatEx = NIL THEN
									audioStreamHeader.waveFormatEx := ReadWaveFormatEx();
									audioStreamHeader.bitMapInfo := NIL
								ELSE
									SkipHeader()
								END;
							ELSE
								IF Debug THEN
									AosOut.String( "AVIDemux: Unknown AviStream found; " ); AosOut.String(tempHeader.fccType); 
									AosOut.Ln()
								END;
							END;
						END;
					ELSIF CompareCharArrays(buf, "movi",4) THEN
						(* movie data begin *)
						IF Debug THEN 
							AosOut.String("AVIDemux: Start of movie stream found " ); AosOut.Ln()
						END;
						done := TRUE
					ELSE
						IF Debug THEN
							AosOut.String("AVIDemux: Unknown StreamHeader found: " ); AosOut.String(buf); AosOut.Ln()
						END;
						r.SkipBytes( headerLength - ( r.Pos() - headerBeginPos ) )
					END;
				ELSE
					(* Unknown Header -> Skip *)
					IF Debug THEN
						AosOut.String("AVIDemux: Unknown Header found: " ); AosOut.Buffer(buf,0,4); AosOut.Ln()
					END;
					SkipHeader()
				END;
			UNTIL done;
			
			IF Debug THEN
				DumpHeaders()
			END;
			
			RETURN TRUE
		END ReadHeader;

		(* Skip chunk *)
		PROCEDURE SkipHeader*();
		VAR
			length: LONGINT;
		BEGIN
			r.ReadLONGINT( length );
			r.SkipBytes( length + length MOD 2)
		END SkipHeader;
		
		(* Read Main AVI Header *)
		PROCEDURE ReadMainAVIHeader(): MainAVIHeaderPtr;
		VAR 
			aviHeader: MainAVIHeaderPtr;
			headerLength: LONGINT;
			startPos: LONGINT;
		BEGIN
			NEW( aviHeader );
							
			r.ReadLONGINT( headerLength );
			startPos := r.Pos();
			
			r.ReadLONGINT( aviHeader.microSecsPerFrame );
			r.ReadLONGINT( aviHeader.maxBytesPerSec );
			r.ReadLONGINT( aviHeader.reserved1 );
			r.ReadLONGINT( aviHeader.flags );
			r.ReadLONGINT( aviHeader.totalFrames );
			r.ReadLONGINT( aviHeader.initialFrames );
			r.ReadLONGINT( aviHeader.streams );
			r.ReadLONGINT( aviHeader.suggestedBufferSize );
			r.ReadLONGINT( aviHeader.width );
			r.ReadLONGINT( aviHeader.height );
			r.ReadLONGINT( aviHeader.reserved[0] );
			r.ReadLONGINT( aviHeader.reserved[1] );
			r.ReadLONGINT( aviHeader.reserved[2] );
			r.ReadLONGINT( aviHeader.reserved[3] );
			
			(* Skip Bytes if we have still available *)
			IF r.Pos() - startPos < headerLength THEN
				r.SkipBytes( headerLength - ( r.Pos() - startPos ) )
			END;
			
			RETURN aviHeader;
		END ReadMainAVIHeader;

		(* Read Header of this avi Stream *)
		PROCEDURE ReadAVIStreamHeader(): AVIStreamHeaderPtr;
		VAR
			header: AVIStreamHeaderPtr;
			headerLength: LONGINT;
			startPos: LONGINT;
			len: LONGINT;
			temp: INTEGER;
		BEGIN
			NEW(header);
			
			r.ReadLONGINT( headerLength );
			startPos := r.Pos();
			
			r.Bytes( header.fccType,0,4, len );
			r.Bytes( header.fccHandler,0,4, len ); 
			r.ReadLONGINT( header.flags );
			r.ReadLONGINT( header.priority );
			r.ReadLONGINT( header.initialFrames );
			r.ReadLONGINT( header.scale );
			r.ReadLONGINT( header.rate );
			r.ReadLONGINT( header.start );
			r.ReadLONGINT( header.length );
			r.ReadLONGINT( header.suggestedBufferSize );
			r.ReadLONGINT( header.quality );
			r.ReadLONGINT( header.sampleSize );
			r.ReadINTEGER( temp ); header.left := temp;
			r.ReadINTEGER( temp ); header.top := temp;
			r.ReadINTEGER( temp ); header.right := temp;
			r.ReadINTEGER( temp ); header.bottom := temp;

			(* Skio Bytes if we have still available *)
			IF r.Pos() - startPos < headerLength THEN
				r.SkipBytes( headerLength - ( r.Pos() - startPos ) )
			END;
			
			RETURN header
		END ReadAVIStreamHeader;

		(* Read BitMapInfo Structure *)
		PROCEDURE ReadBitMapInfo(): BitMapInfoPtr;
		VAR
			header: BitMapInfoPtr;
			headerLength: LONGINT;
			startPos: LONGINT;
			temp: INTEGER;
		BEGIN
			NEW(header);
					
			r.ReadLONGINT( headerLength );
			startPos := r.Pos();
		
			r.ReadLONGINT( header.size );
			r.ReadLONGINT( header.width );
			r.ReadLONGINT( header.height );
			r.ReadINTEGER( temp ); header.planes := temp;
			r.ReadINTEGER( temp ); header.bitCount := temp;
			r.ReadLONGINT( header.compression );
			r.ReadLONGINT( header.sizeImage );
			r.ReadLONGINT( header.xPelsPerMeter );
			r.ReadLONGINT( header.yPelsPerMeter );
			r.ReadLONGINT( header.clrUsed );
			r.ReadLONGINT( header.clrImportant );
			
			IF r.Pos() - startPos < headerLength THEN
				r.SkipBytes( headerLength - ( r.Pos() - startPos ) )
			END;

			RETURN header
		END  ReadBitMapInfo;
			
		(* Read WaveFormatEX Structure *)
		PROCEDURE ReadWaveFormatEx(): WAVEFormatExPtr;
		VAR
			header: WAVEFormatExPtr;
			headerLength: LONGINT;
			startPos: LONGINT;
			temp: INTEGER;
		BEGIN
			NEW(header);
					
			r.ReadLONGINT( headerLength );
			startPos := r.Pos();
			
			r.ReadINTEGER( temp ); header.formatTag := temp;
			r.ReadINTEGER( temp ); header.channels := temp;
			r.ReadLONGINT( header.samplesPerSec );
			r.ReadLONGINT( header.avgBytesPerSec );
			r.ReadINTEGER( temp ); header.blockAlign := temp;
			r.ReadINTEGER( temp ); header.bitsPerSample := temp;
			r.ReadINTEGER( temp ); header.cbSize := temp;
			
			IF r.Pos() - startPos < headerLength THEN
				r.SkipBytes( headerLength - ( r.Pos() - startPos ) )
			END;
			
			RETURN header
		END ReadWaveFormatEx;

		(* Write Avi Headers to KernelLog *)
		PROCEDURE DumpHeaders();
		BEGIN
			AosOut.String("AviDemux: Dump of Avi Headers: "); AosOut.Ln();
			
			IF aviHeader # NIL THEN
				AosOut.String( "aviHeader.microSecsPerFrame =  " ); AosOut.Int( aviHeader.microSecsPerFrame, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.maxBytesPerSec =  " ); AosOut.Int( aviHeader.maxBytesPerSec, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.reserved1 =  " ); AosOut.Int( aviHeader.reserved1, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.flags =  " ); AosOut.Int( aviHeader.flags, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.totalFrames =  " ); AosOut.Int( aviHeader.totalFrames, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.initialFrames =  " ); AosOut.Int( aviHeader.initialFrames, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.streams =  " ); AosOut.Int( aviHeader.streams, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.suggestedBufferSize =  " ); AosOut.Int( aviHeader.suggestedBufferSize, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.width =  " ); AosOut.Int( aviHeader.width, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.height =  " ); AosOut.Int( aviHeader.height, 0 ); AosOut.Ln();
				AosOut.String( "aviHeader.reserved[0] =  " ); AosOut.Int( aviHeader.reserved[0],0 ); AosOut.Ln();
				AosOut.String( "aviHeader.reserved[1] =  " ); AosOut.Int( aviHeader.reserved[1],0 ); AosOut.Ln();
				AosOut.String( "aviHeader.reserved[2] =  " ); AosOut.Int( aviHeader.reserved[2],0 ); AosOut.Ln();
				AosOut.String( "aviHeader.reserved[3] =  " ); AosOut.Int( aviHeader.reserved[3],0 ); AosOut.Ln()
			ELSE
				AosOut.String("AVIDemux.aviHeader = NIL"); AosOut.Ln()
			END;
			
			IF audioStreamHeader # NIL THEN
				AosOut.String( "audioStreamHeader.fccType =  " ); AosOut.String( audioStreamHeader.fccType ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.fccHandler =  " ); AosOut.String( audioStreamHeader.fccHandler ); 
					AosOut.Ln();
				AosOut.String( "audioStreamHeader.flags =  " ); AosOut.Int( audioStreamHeader.flags, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.priority =  " ); AosOut.Int( audioStreamHeader.priority, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.initialFrames =  " ); AosOut.Int( audioStreamHeader.initialFrames, 0 ); 
					AosOut.Ln();
				AosOut.String( "audioStreamHeader.scale =  " ); AosOut.Int( audioStreamHeader.scale, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.rate =  " ); AosOut.Int( audioStreamHeader.rate, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.start =  " ); AosOut.Int( audioStreamHeader.start, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.length =  " ); AosOut.Int( audioStreamHeader.length, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.suggestedBufferSize =  " ); 
					AosOut.Int( audioStreamHeader.suggestedBufferSize, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.quality =  " ); AosOut.Int( audioStreamHeader.quality, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.sampleSize =  " ); AosOut.Int( audioStreamHeader.sampleSize, 0 );
					AosOut.Ln();
				AosOut.String( "audioStreamHeader.left =  " ); AosOut.Int( audioStreamHeader.left, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.top =  " ); AosOut.Int( audioStreamHeader.top, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.right =  " ); AosOut.Int( audioStreamHeader.right, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.bottom =  " ); AosOut.Int( audioStreamHeader.bottom, 0 ); AosOut.Ln();
				AosOut.String( "audioStreamHeader.streamIdentifier =  " ); 
				AosOut.Buffer( audioStreamHeader.streamIdentifier, 0, 4 ); AosOut.Ln()
			ELSE
				AosOut.String("AVIDemux.audioStreamHeader = NIL"); AosOut.Ln()
			END;
			
			IF videoStreamHeader # NIL THEN
				AosOut.String( "videoStreamHeader.fccType =  " ); AosOut.String( videoStreamHeader.fccType ); AosOut.Ln();
				AosOut.String( "videoStreamHeader.fccHandler =  " ); AosOut.String( videoStreamHeader.fccHandler ); 
					AosOut.Ln();
				AosOut.String( "videoStreamHeader.flags =  " ); AosOut.Int( videoStreamHeader.flags, 0 ); AosOut.Ln();
				AosOut.String( "videoStreamHeader.priority =  " ); AosOut.Int( videoStreamHeader.priority, 0 ); AosOut.Ln();
				AosOut.String( "videoStreamHeader.initialFrames =  " ); AosOut.Int( videoStreamHeader.initialFrames, 0 ); 
					AosOut.Ln();
				AosOut.String( "videoStreamHeader.scale =  " ); AosOut.Int( videoStreamHeader.scale, 0 ); AosOut.Ln();
				AosOut.String( "videoStreamHeader.rate =  " ); AosOut.Int( videoStreamHeader.rate, 0 ); AosOut.Ln();
				AosOut.String( "videoStreamHeader.start =  " ); AosOut.Int( videoStreamHeader.start, 0 ); AosOut.Ln();
				AosOut.String( "videoStreamHeader.length =  " ); AosOut.Int( videoStreamHeader.length, 0 ); AosOut.Ln();
				AosOut.String( "videoStreamHeader.suggestedBufferSize =  " ); 
					AosOut.Int( videoStreamHeader.suggestedBufferSize, 0 ); AosOut.Ln();
				AosOut.String( "videoStreamHeader.quality =  " ); AosOut.Int( videoStreamHeader.quality, 0 ); AosOut.Ln();
				AosOut.String( "videoStreamHeader.sampleSize =  " ); AosOut.Int( videoStreamHeader.sampleSize, 0 );
					AosOut.Ln();
				AosOut.String( "videoStreamHeader.streamIdentifier =  " );
				AosOut.Buffer( videoStreamHeader.streamIdentifier, 0, 4 ); AosOut.Ln()
			ELSE
				AosOut.String("AVIDemux.videoStreamHeader = NIL"); AosOut.Ln()
			END;

			IF videoStreamHeader.bitMapInfo # NIL THEN
				AosOut.String( "bitMapInfo.size =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.size ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.width =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.width ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.height =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.height ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.planes =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.planes ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.bitCount =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.bitCount ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.compression =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.compression ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.sizeImage =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.sizeImage ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.xPelsPerMeter =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.xPelsPerMeter ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.yelsPerMeter =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.yPelsPerMeter ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.clrUsed =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.clrUsed ,0 ); AosOut.Ln();
				AosOut.String( "bitMapInfo.clrImportant =  " ); AosOut.Int( videoStreamHeader.bitMapInfo.clrImportant ,0 ); AosOut.Ln()
			ELSE
				AosOut.String("AVIDemux.bitMapInfo = NIL"); AosOut.Ln()
			END;

			IF audioStreamHeader.waveFormatEx # NIL THEN
				AosOut.String( "waveFormat.formatTag =  " ); AosOut.Int( audioStreamHeader.waveFormatEx.formatTag ,0 ); AosOut.Ln();
				AosOut.String( "waveFormat.channel =  " ); AosOut.Int( audioStreamHeader.waveFormatEx.channels ,0 ); AosOut.Ln();
				AosOut.String( "waveFormat.samplesPerSec =  " ); AosOut.Int( audioStreamHeader.waveFormatEx.samplesPerSec ,0 ); AosOut.Ln();
				AosOut.String( "waveFormat.avgBytesPerSec =  " ); AosOut.Int( audioStreamHeader.waveFormatEx.avgBytesPerSec ,0 ); AosOut.Ln();
				AosOut.String( "waveFormat.blockAlign =  " ); AosOut.Int( audioStreamHeader.waveFormatEx.blockAlign ,0 ); AosOut.Ln();
				AosOut.String( "waveFormat.bitsPerSample =  " ); AosOut.Int( audioStreamHeader.waveFormatEx.bitsPerSample ,0 ); AosOut.Ln();
				AosOut.String( "waveFormat.cbSize =  " ); AosOut.Int( audioStreamHeader.waveFormatEx.cbSize ,0 ); AosOut.Ln()
			ELSE
				AosOut.String("AVIDemux.waveFormat = NIL"); AosOut.Ln()
			END;

			AosOut.Ln()			
		END DumpHeaders;
		
		(* Returns the audioStream *)
		PROCEDURE GetAudioStream*(): AVIStream;
		VAR
			stream: AVIStream;
			reader: AVIReader;
		BEGIN
			(* Create AVIReader *)
			
			NEW( reader, file, r.Pos() );
			NEW(stream, reader , aviHeader, audioStreamHeader );
			reader := NIL;
			RETURN stream
		END GetAudioStream;
		
		(* Return AudioStreamHeader *)
		PROCEDURE GetAudioStreamHeader*(): AVIStreamHeaderPtr;
		BEGIN
			RETURN audioStreamHeader
		END GetAudioStreamHeader;
	
		(* Return VideoStreamHeader *)	
		PROCEDURE GetVideoStreamHeader*(): AVIStreamHeaderPtr;
		BEGIN
			RETURN videoStreamHeader
		END GetVideoStreamHeader;
	
		(* Get VideoStream *)	
		PROCEDURE GetVideoStream*(): AVIStream;
		VAR
			stream: AVIStream;
			reader: AVIReader;
		BEGIN
			NEW( reader, file, r.Pos() );
			NEW(stream, reader, aviHeader, videoStreamHeader );
			RETURN stream
		END GetVideoStream;
	END AVIDemux;
END AVI.