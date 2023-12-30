(** AUTHOR "Yves Weber"; 
	PURPOSE "Some utilities used by the MPEGVideoDecoder module"; 
*)
MODULE MPEGUtilities;

IMPORT
	MPEGTables, AosIO, AosOut, SYSTEM, Raster, AosCodecs;

CONST
	(* required for iDCT (copied from DivXHelper.Mod) *)
	W1 = 2841;				(* 2048*sqrt(2)*cos(1*pi/16) *)
	W2 = 2676;				(* 2048*sqrt(2)*cos(2*pi/16) *)
	W3 = 2408;				(* 2048*sqrt(2)*cos(3*pi/16) *)
	W5 = 1609;				(* 2048*sqrt(2)*cos(5*pi/16) *)
	W6 = 1108;				(* 2048*sqrt(2)*cos(6*pi/16) *)
	W7 = 565;				(* 2048*sqrt(2)*cos(7*pi/16) *)

	EnableMMX = TRUE;

VAR
	IdctBorder*: POINTER TO ARRAY OF LONGINT;
	ii: LONGINT;

TYPE
	(* Helper Types *)
	PointerToArrayOfCHAR* = POINTER TO ARRAY OF CHAR;	
	PointerToArrayOfLONGINT* = POINTER TO ARRAY OF LONGINT;
	
	Dequantizer* = OBJECT
		PROCEDURE DequantizeNonintraCoeffs*(
			coeffs: PointerToArrayOfLONGINT; 
			nonintraQM: PointerToArrayOfLONGINT;
			qScale: LONGINT): BOOLEAN;
		VAR
			i: LONGINT;
			sign: LONGINT;
			
		BEGIN
			FOR i := 0 TO 63 DO
				IF coeffs[i] > 0 THEN
					sign := 1;
				ELSIF coeffs[i] = 0 THEN
					sign := 0;
				ELSE
					sign := -1;
				END;
				coeffs[i] := ((2*coeffs[i] + sign) * qScale * nonintraQM[i]) DIV 16;
				
				(* oddify towards zero *)
				IF (coeffs[i] MOD 2) = 0 THEN
					coeffs[i] := coeffs[i] - sign;
				END;
				
				(* ensure limits *)
				IF coeffs[i] > 2047 THEN
					coeffs[i] := 2047;
				END;
				
				IF coeffs[i] < -2048 THEN
					coeffs[i] := -2048;
				END;
			END;

			RETURN TRUE;
		END DequantizeNonintraCoeffs;
		
		(* Dequantizes the coefficients *)
		PROCEDURE DequantizeIntraCoeffs*(
			coeffs: PointerToArrayOfLONGINT; 
			intraQM: PointerToArrayOfLONGINT;
			qScale: LONGINT;
			VAR prediction: LONGINT;
			first: BOOLEAN;
			mbSkipped: BOOLEAN): BOOLEAN;
		VAR
			i: LONGINT;
			
		BEGIN
			(* dequantize all coefficients *)
			FOR i := 1 TO 63 DO
				coeffs[i] := (2*coeffs[i]*qScale*intraQM[i]) DIV 16;
				
				IF ((coeffs[i] MOD 2) = 0) & (coeffs[i] # 0) THEN
					IF coeffs[i] > 0 THEN
						DEC(coeffs[i]);
					ELSE
						INC(coeffs[i]);
					END;
				END;
				
				(* ensure limits *)
				IF coeffs[i] > 2047 THEN
					coeffs[i] := 2047;
				END;
				
				IF coeffs[i] < -2048 THEN
					coeffs[i] := -2048;
				END;
			END;
			
			(* special handling of DC *)
			coeffs[0] := coeffs[0] * 8;
			
			(* calculate DC = DCold + difference for all type of blocks *)
			IF first & mbSkipped THEN
				prediction := 8*128;
			END;
			INC(prediction, coeffs[0]);
			coeffs[0] := prediction;
		
			RETURN TRUE;
		END DequantizeIntraCoeffs;

		(* Dequantizes the coefficients - MPEG2 version *)
		PROCEDURE DequantizeNonintraCoeffs2*(
			coeffs: PointerToArrayOfLONGINT;
			nonintraQM: PointerToArrayOfLONGINT;
			qScale: LONGINT);
		VAR
			i: LONGINT;
			sum: LONGINT;
			
		BEGIN
			FOR i := 0 TO 63 DO
				IF coeffs[i] # 0 THEN
					IF coeffs[i] > 0 THEN
						coeffs[i] := ((2 * coeffs[i] + 1) * nonintraQM[i] * qScale) DIV 32;
					ELSE
						coeffs[i] := ((2 * coeffs[i] - 1) * nonintraQM[i] * qScale) DIV 32;
					END;
					
					(* ensure limits *)
					IF coeffs[i] > 2047 THEN
						coeffs[i] := 2047;
					ELSIF coeffs[i] < -2048 THEN
						coeffs[i] := -2048;
					END;
				
					INC(sum, coeffs[i]);
				END;
			END;
			
			MismatchControl(coeffs[63], sum);
		END DequantizeNonintraCoeffs2;

		
		(* Dequantizes the coefficients - MPEG-2 version *)
		PROCEDURE DequantizeIntraCoeffs2*(
			coeffs: PointerToArrayOfLONGINT; 
			intraQM: PointerToArrayOfLONGINT;
			qScale: LONGINT;
			dcPrecision: LONGINT);
		VAR
			i: LONGINT;
			sum: LONGINT;
			resetValue, intraDcMult: LONGINT;
			
		BEGIN
			(* special treatment of DC *)
			coeffs[0] := MPEGTables.DCM[dcPrecision] * coeffs[0];
			sum := coeffs[0];
		
			FOR i := 1 TO 63 DO
				coeffs[i] := ((2 * coeffs[i]) * intraQM[i] * qScale) DIV 32;
					
				(* ensure limits *)
				IF coeffs[i] > 2047 THEN
					coeffs[i] := 2047;
				END;
				
				IF coeffs[i] < -2048 THEN
					coeffs[i] := -2048;
				END;
				
				INC(sum, coeffs[i]);
			END;
			
			MismatchControl(coeffs[63], sum);
		END DequantizeIntraCoeffs2;
		
		
		(* Performs the mismatch contros - used for intra and non-intra - MPEG2 only *)
		PROCEDURE MismatchControl(VAR coeffs63: LONGINT; sum: LONGINT);
		BEGIN
			IF (sum MOD 2) = 0 THEN
				(* sum is even *)
				IF (coeffs63 MOD 2) = 1 THEN
					(* odd *)
					DEC(coeffs63);
				ELSE
					(* even *)
					INC(coeffs63);
				END;
			END;			
		END MismatchControl;
	END Dequantizer;


	(* Object to store one decoded picture *)
	(* Color information is in one big array of char:
	     yyyyyyyyyyyyyyyyyyyycbcbcbcbcbcbcrcrcrcrcrcrcr
	     |                               |                     |
	     0                        cbOffset          crOffset
	     
	     for rgb, use the convention y->r, cb->g, cr->b
	*)
	Frame* = OBJECT
		VAR
			buffer*: PointerToArrayOfCHAR;
			cbOffset*, crOffset*: LONGINT;
			frameNr*: LONGINT;
			picType*: LONGINT;			(* I, P or B-Frame -> 1, 2 or 3 *)
	END Frame;
	
	(* MPEG-2 Picture Coding Extension *)
	PicCodingExt* = OBJECT
		VAR
			dcPrecision*: LONGINT;								(* DC precision *)
			picStructure*: LONGINT;								(* picture structure *)
			topFieldFirst*: BOOLEAN;	
			framePredFrameDct*: BOOLEAN;
			concealmentMV*: BOOLEAN;						(* concealment motion vectors used *)
			qScaleType*: BOOLEAN;
			intraVlcFormat*: BOOLEAN;
			alternateScan*: BOOLEAN;
			repeatFirstField*: BOOLEAN;
			chroma420Type*: BOOLEAN;
			progressiveFrame*: BOOLEAN;
			
		
		PROCEDURE Dump*;
		BEGIN
			AosOut.String("dc Precision: "); AosOut.Int(dcPrecision, 0); AosOut.Ln; 
			AosOut.String("picture structure: ");
			CASE picStructure OF
				0: AosOut.String("Reserved");
			|	1: AosOut.String("Top Field");
			|	2: AosOut.String("Bottom Field");
			|	3: AosOut.String("Frame");
			END;
			AosOut.Ln; 
			AosOut.String("top field first: "); IF topFieldFirst THEN AosOut.String("TRUE") ELSE AosOut.String("FALSE") END; AosOut.Ln; 
			AosOut.String("frame pred frame dct: "); IF framePredFrameDct THEN AosOut.String("TRUE") ELSE AosOut.String("FALSE") END; AosOut.Ln; 
			AosOut.String("concealment MV: "); IF concealmentMV THEN AosOut.String("TRUE") ELSE AosOut.String("FALSE") END; AosOut.Ln; 
			AosOut.String("qScaleType: "); IF qScaleType THEN AosOut.String("TRUE") ELSE AosOut.String("FALSE") END; AosOut.Ln; 
			AosOut.String("intraVlcFormat: "); IF intraVlcFormat THEN AosOut.String("TRUE") ELSE AosOut.String("FALSE") END; AosOut.Ln; 
			AosOut.String("alternate scan: "); IF alternateScan THEN AosOut.String("TRUE") ELSE AosOut.String("FALSE") END; AosOut.Ln; 
			AosOut.String("repeat first field: "); IF repeatFirstField THEN AosOut.String("TRUE") ELSE AosOut.String("FALSE") END; AosOut.Ln; 
			AosOut.String("chroma 4:2:0 type: "); IF chroma420Type THEN AosOut.String("TRUE") ELSE AosOut.String("FALSE") END; AosOut.Ln; 
			AosOut.String("progressiveFrame: "); IF progressiveFrame THEN AosOut.String("TRUE") ELSE AosOut.String("FALSE") END; AosOut.Ln; 
		END Dump;
	END PicCodingExt;
	
	(* everything about motion vectors *)
	(* MPEG-1 does not use all variables *)
	MotionVectorInfos* = OBJECT
		VAR
			fullPel*: ARRAY 2 OF ARRAY 2 OF BOOLEAN;						(* full Pel or half Pel *)
			fCode*: ARRAY 2 OF ARRAY 2 OF LONGINT;							(* MPEG-2 version of forw/back f code *)
			f*: ARRAY 2 OF ARRAY 2 OF LONGINT;
			rSize*: ARRAY 2 OF ARRAY 2 OF LONGINT;
			motionVerticalFieldSelect*: ARRAY 2 OF ARRAY 2 OF BOOLEAN;		(* flag to choose reference field for prediction *)
			motionCode*: ARRAY 2 OF ARRAY 2 OF ARRAY 2 OF LONGINT;
			motionResidual*: ARRAY 2 OF ARRAY 2 OF ARRAY 2 OF LONGINT;
			dmVector*: ARRAY 2 OF LONGINT;
			
			mv*: ARRAY 2 OF ARRAY 2 OF ARRAY 2 OF LONGINT;				(* calculated motion vectors *)
			pmv*: ARRAY 2 OF ARRAY 2 OF ARRAY 2 OF LONGINT;				(* predictions *)
			
			PROCEDURE Dump*(r, s, t: LONGINT);
			BEGIN
				AosOut.String("Motion Vector Type: ");
				IF s = 0 THEN
					AosOut.String("Forward "); 
				ELSE
					AosOut.String("Backward ");
				END;
				IF t = 0 THEN
					AosOut.String("Horizontal");
				ELSE
					AosOut.String("Vertical");
				END;
				AosOut.Ln; 
				AosOut.String("fCode: "); AosOut.Int(fCode[s][t], 0); AosOut.Ln; 
				AosOut.String("fullPel: "); IF fullPel[r][s] THEN AosOut.String("TRUE"); ELSE AosOut.String("FALSE"); END; AosOut.Ln; 
				AosOut.String("f: "); AosOut.Int(f[r][s], 0); AosOut.Ln; 
				AosOut.String("rSize: "); AosOut.Int(rSize[r][s], 0); AosOut.Ln;
				AosOut.String("motionVerticalFieldSelect: "); IF motionVerticalFieldSelect[r][s] THEN AosOut.String("TRUE"); ELSE AosOut.String("FALSE"); END; AosOut.Ln; 
				AosOut.String("motionCode: "); AosOut.Int(motionCode[r][s][t], 0); AosOut.Ln; 
				AosOut.String("motionResidual: "); AosOut.Int(motionResidual[r][s][t], 0); AosOut.Ln; 
				AosOut.String("dmVector: "); AosOut.Int(dmVector[t], 0); AosOut.Ln; 
			END Dump;
			
	END MotionVectorInfos;
	
	(* Inverse Discrete Cosine Transformation - copied (and slightly modified) from DivXHelper.Mod *)
	IDCT* = OBJECT
		PROCEDURE PerformIDCT*(block: PointerToArrayOfLONGINT );
		VAR
			i: LONGINT;
			
		BEGIN
			FOR i:= 0 TO 7 DO
				IDCTRow( block, i * 8)
			END;
			
			FOR i:= 0 TO 7 DO
				IDCTCol( block, i )
			END;
		END PerformIDCT;
		
		PROCEDURE IDCTRow( blk: PointerToArrayOfLONGINT; baseIndex: LONGINT);
		VAR
			x0, x1, x2, x3, x4, x5, x6, x7, x8: LONGINT;
			adr, tempAdr: LONGINT;
			
		BEGIN
			adr := SYSTEM.ADR( blk[baseIndex] );
					
			(* shortcut *)
			x1 := SYSTEM.GET32( adr + 4*SIZE(LONGINT) ) * 2048; 
			x2 := SYSTEM.GET32( adr + 6*SIZE(LONGINT) );
			x3 := SYSTEM.GET32( adr + 2*SIZE(LONGINT) );
			x4 := SYSTEM.GET32( adr + SIZE(LONGINT) );
			x5 := SYSTEM.GET32( adr + 7*SIZE(LONGINT) );
			x6 := SYSTEM.GET32( adr + 5*SIZE(LONGINT) );
			x7 := SYSTEM.GET32( adr + 3*SIZE(LONGINT) );
			
			IF ( x1 = 0 ) & ( x2 = 0 ) & ( x3 = 0 ) & ( x4 = 0 ) & ( x5 = 0 ) & ( x6 = 0 ) & ( x7 = 0 )  THEN
				x0 := SYSTEM.GET32( adr ) * 8;
				SYSTEM.PUT32( adr , x0 );
				tempAdr := adr + SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				RETURN
			END;
			x0 := ( SYSTEM.GET32( adr ) * 2048 ) + 128;    (* for proper rounding in the fourth stage *)
	
			(* first stage *)
			x8 := W7 * ( x4 + x5 );
			x4 := x8 + ( W1 - W7 ) * x4;
			x5 := x8 - ( W1 + W7 ) * x5;
			x8 := W3 * ( x6 + x7 );
			x6 := x8 - ( W3 - W5 ) * x6;
			x7 := x8 - ( W3 + W5 ) * x7;
			
			(* second stage *)
			x8 := x0 + x1;	
			x0 := x0 - x1;
			x1 := W6 * ( x3 + x2 );
			x2 := x1 - ( W2 + W6 ) * x2;
			x3 := x1 + ( W2 - W6 ) * x3;
			x1 := x4 + x6;
			x4 := x4 - x6;
			x6 := x5 + x7;
			x5 := x5 - x7;
	
			(* third stage *)
			x7 := x8 + x3;
			x8 := x8 - x3;
			x3 := x0 + x2;
			x0 := x0 - x2;
			x2 := ( 181 * ( x4 + x5 ) + 128 ) DIV 256;
			x4 := ( 181 * ( x4 - x5 ) + 128 ) DIV 256;
	
			(* fourth stage *)
			SYSTEM.PUT32( adr, ( x7 + x1 ) DIV 256 );
			tempAdr := adr + SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, ( x3 + x2 ) DIV 256 );
			tempAdr := tempAdr + SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, ( x0 + x4 ) DIV 256 );
			tempAdr := tempAdr + SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, ( x8 + x6 ) DIV 256 );
			tempAdr := tempAdr + SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, ( x8 - x6 ) DIV 256 );
			tempAdr := tempAdr + SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, ( x0 - x4 ) DIV 256 );
			tempAdr := tempAdr + SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, ( x3 - x2 ) DIV 256 );
			tempAdr := tempAdr + SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, ( x7 - x1 ) DIV 256 )
		END IDCTRow;
		
		PROCEDURE IDCTCol( blk: PointerToArrayOfLONGINT; baseIndex: LONGINT );
		VAR
			x0, x1, x2, x3, x4, x5, x6, x7, x8: LONGINT;
			adr, tempAdr, sourceAdr: LONGINT;
			
		BEGIN
			adr := SYSTEM.ADR( blk[baseIndex] );
					
			(* shortcut *)
			x1 := SYSTEM.GET32( adr + 32*SIZE(LONGINT) ) * 256; 
			x2 := SYSTEM.GET32( adr + 48*SIZE(LONGINT) );
			x3 := SYSTEM.GET32( adr + 16*SIZE(LONGINT) );
			x4 := SYSTEM.GET32( adr + 8*SIZE(LONGINT) );
			x5 := SYSTEM.GET32( adr + 56*SIZE(LONGINT) );
			x6 := SYSTEM.GET32( adr + 40*SIZE(LONGINT) );
			x7 := SYSTEM.GET32( adr + 24*SIZE(LONGINT) );
	
			IF ( x1 = 0 ) & ( x2 = 0 ) & ( x3 = 0 ) & ( x4 = 0 ) & ( x5 = 0 ) & ( x6 = 0 ) & ( x7 = 0 )  THEN
				x0 := IdctBorder[( ( SYSTEM.GET32( adr ) + 32 ) DIV 64 ) + 512];	(* +512 is the base offset in the array *)
				SYSTEM.PUT32( adr , x0 );
				tempAdr := adr + 8*SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + 8*SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + 8*SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + 8*SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + 8*SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + 8*SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				tempAdr := tempAdr + 8*SIZE( LONGINT );
				SYSTEM.PUT32( tempAdr, x0 );
				RETURN
			END;
			
			 x0 := (SYSTEM.GET32( adr )* 256) + 8192;
			
			(* first stage *)
			x8 := W7 * ( x4 + x5 ) + 4;
			x4 := ( x8 + ( W1 - W7 ) * x4 ) DIV 8;
			x5 := ( x8 - ( W1 + W7) * x5 ) DIV 8;
			x8 := W3 * ( x6 + x7 ) + 4;
			x6 := ( x8 - ( W3 - W5 ) * x6 )DIV 8;
			x7 := ( x8 - ( W3 + W5 ) * x7 ) DIV 8;
	
			(* second stage *)
			x8 := x0 + x1;
			x0 := x0 - x1;
			x1 := W6 * ( x3 + x2 ) + 4;
			x2 := ( x1 - ( W2 + W6 ) * x2 ) DIV 8;
			x3 := ( x1 + ( W2 - W6 ) * x3 ) DIV 8;
			x1 := x4 + x6;
			x4 := x4 - x6;
			x6 := x5 + x7;
			x5 := x5 - x7;
	
			(* third stage *)
			x7 := x8 + x3;
			x8 := x8 - x3;
			x3 := x0 + x2;
			x0 := x0 - x2;
			x2 := ( 181 * ( x4 + x5 ) + 128 ) DIV 256;
			x4 := ( 181 * ( x4 - x5 ) + 128 ) DIV 256;
			
			(* fourth stage *)
			tempAdr := adr;
			sourceAdr := SYSTEM.ADR(IdctBorder[512] );
			SYSTEM.PUT32( tempAdr, SYSTEM.GET32( ( ( ( x7 + x1 ) DIV 16384 )*SIZE(LONGINT) ) + sourceAdr ) );
			tempAdr := tempAdr + 8*SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, SYSTEM.GET32( ( ( ( x3 + x2 ) DIV 16384 )*SIZE(LONGINT) ) + sourceAdr ) );
			tempAdr := tempAdr + 8*SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, SYSTEM.GET32( ( ( ( x0 + x4 ) DIV 16384 )*SIZE(LONGINT) ) + sourceAdr ) );
			tempAdr := tempAdr + 8*SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, SYSTEM.GET32( ( ( ( x8 + x6 ) DIV 16384 )*SIZE(LONGINT) ) + sourceAdr ) );
			tempAdr := tempAdr + 8*SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, SYSTEM.GET32( ( ( ( x8 - x6 ) DIV 16384 )*SIZE(LONGINT) ) + sourceAdr ) );				
			tempAdr := tempAdr + 8*SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, SYSTEM.GET32( ( ( ( x0 - x4 ) DIV 16384 )*SIZE(LONGINT) ) + sourceAdr ) );
			tempAdr := tempAdr + 8*SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, SYSTEM.GET32( ( ( ( x3 - x2 ) DIV 16384 )*SIZE(LONGINT) ) + sourceAdr ) );				
			tempAdr := tempAdr + 8*SIZE( LONGINT );
			SYSTEM.PUT32( tempAdr, SYSTEM.GET32( ( ( ( x7 - x1 ) DIV 16384 )*SIZE(LONGINT) ) + sourceAdr ) )
		END IDCTCol;
	END IDCT;
	
	(* A demultiplexed (i.e. video or audio only) MPEG stream where single bits can be read *)
	(* Partially based on AVI.AVIStream *)
	BitStream* = OBJECT
		VAR
			first: LONGINT;						(* First element in the ringbuffer *)
			last: LONGINT;						(* Last element in the ringbuffer (only used until input reports EOF) *)
			bitIndex: LONGINT;					(* Position (Bit) in the current LONGINT (buffer[0..3] or [4..7]) *)
			buffer: ARRAY 8 OF CHAR;			(* Local buffer (two LONGINTs) *)
			bufAdr: LONGINT;					(* Address of buffer[0] *)
			input: AosCodecs.DemuxStream;		(* The underlying Reader *)
			eof: BOOLEAN;						(* End of File *)
			bitsLeft: LONGINT;					(* only used when eof is TRUE *)
			
			len: LONGINT;
			i: LONGINT;
			
		(* Constructor *)
		PROCEDURE & Init( r: AosCodecs.DemuxStream );
		BEGIN
			ASSERT(r # NIL);
			first := 0;
			last := -1;
			bitIndex := 0;
			bufAdr := SYSTEM.ADR(buffer[0]);
			input := r;
			eof := FALSE;
			
			(* fill the buffer with the first bytes *)
			ReadLongintFromStream();
			ReadLongintFromStream();
		END Init;
		
		PROCEDURE Reset*;
		VAR
			dummy, result: LONGINT;
			
		BEGIN
			input.SetPosX(AosCodecs.SeekByte, 0, dummy, result);
			first := 0;
			last := -1;
			bitIndex := 0;
			bufAdr := SYSTEM.ADR(buffer[0]);
			eof := FALSE;
			
			(* fill the buffer with the first bytes *)
			ReadLongintFromStream();
			ReadLongintFromStream();
		END Reset;
		
		
		(* Read four bytes from the stream and write it to the buffer *)
		PROCEDURE ReadLongintFromStream;
		VAR
			read: LONGINT;
			
		BEGIN
			IF eof THEN RETURN END;
			
			input.Bytes(buffer, first, 4, read);
			
			IF (input.res = AosIO.EOF) OR (read < 4) THEN
				eof := TRUE;
				bitsLeft := 32 + read*8;
			END;
			first := 4 - first;
		END ReadLongintFromStream;

		(* Align stream to next byte *)
		PROCEDURE ByteAlign*( );
		BEGIN
			IF (bitIndex MOD 8) # 0 THEN
				SkipBits(8 - (bitIndex MOD 8));
			END;
		END ByteAlign;

		(* True if actual position is on byte boundary *)
		PROCEDURE IsAligned*(): BOOLEAN;
		BEGIN
			RETURN ((bitIndex MOD 8) = 0);
		END IsAligned;
		
	 	(* Fast function for changing byte order, but only for  >= i486 *)
	 	PROCEDURE ChangeByteOrder( n: LONGINT ): LONGINT;
		CODE { SYSTEM.i486 }
			MOV EAX, n[EBP]				; load n in eax
			BSWAP EAX			 ; swap byte order
		END ChangeByteOrder;

		(* Read next n bits without advancing in stream. At least one, at most 32 Bits are allowed (this is not checked!) *)
		(* Returns -1 if eof *)
		PROCEDURE ShowBits*(n: LONGINT): LONGINT;
		VAR
			nbit: LONGINT; 
			bufa, bufb: LONGINT;
			temp: LONGINT;
			
		BEGIN
			IF eof & (bitsLeft < n) THEN
				(* there are not enough bits -> return -1 *)
				RETURN -1;
			END;
			
			nbit := (bitIndex + n) - 32;
			
			IF nbit > 0 THEN
				(* we have to read both 32 bit values *)
				bufa := ChangeByteOrder(SYSTEM.GET32(bufAdr + first));
				bufb := ChangeByteOrder(SYSTEM.GET32(bufAdr + 4 - first));
				
				 temp := SYSTEM.LSH(SYSTEM.LSH(bufa, bitIndex), nbit - bitIndex );
				RETURN SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.LSH(bufb, nbit - 32)) + SYSTEM.VAL(SET, temp));
			ELSE
				(* the n bits are completely in the first 32 bits *)
				bufa := ChangeByteOrder(SYSTEM.GET32(bufAdr + first));
				
				RETURN SYSTEM.LSH(SYSTEM.LSH(bufa, bitIndex), n - 32);
			END;
		END ShowBits;

		(* Displays the content of the ringbuffer. Mainly used for debugging *)
		PROCEDURE ShowBuffer*;
		BEGIN
			AosOut.Hex(ORD(buffer[0]), -1); AosOut.String(" "); 
			AosOut.Hex(ORD(buffer[1]), -1); AosOut.String(" "); 
			AosOut.Hex(ORD(buffer[2]), -1); AosOut.String(" "); 
			AosOut.Hex(ORD(buffer[3]), -1); AosOut.String(" "); 
			AosOut.Hex(ORD(buffer[4]), -1); AosOut.String(" "); 
			AosOut.Hex(ORD(buffer[5]), -1); AosOut.String(" "); 
			AosOut.Hex(ORD(buffer[6]), -1); AosOut.String(" "); 
			AosOut.Hex(ORD(buffer[7]), -1); AosOut.String(" "); 
			AosOut.String("first = "); AosOut.Int(first, 0); 
		END ShowBuffer;

		(* Read next n bits and advance bit stream. At most 32 bits are allowed *)
		PROCEDURE GetBits*( n: LONGINT): LONGINT;
		VAR
			ret: LONGINT;
		BEGIN
			ret := ShowBits( n );
			SkipBits( n );
			RETURN ret
		END GetBits;

		(* Skip next n bits. At most 32 bits are allowed *)
		PROCEDURE SkipBits*(n: LONGINT);
		BEGIN
			IF eof & (bitsLeft <= 0) THEN
				RETURN;
			END;
		
			IF eof THEN
				(* adjust bitsLeft *)
				DEC(bitsLeft, n);
			END;
			
			INC(bitIndex, n);
			
			IF bitIndex > 31 THEN
				ReadLongintFromStream();
				DEC(bitIndex, 32);
			END;
		END SkipBits;
		
		PROCEDURE Pos*(): LONGINT;
		BEGIN
			RETURN input.Pos() - 8;
		END Pos;
		
		PROCEDURE SetPos*(pos: LONGINT);
		VAR
			dummy, result: LONGINT;
			
		BEGIN
			input.SetPosX(AosCodecs.SeekByte, pos, dummy, result);
			first := 0;
			last := -1;
			bitIndex := 0;
			bufAdr := SYSTEM.ADR(buffer[0]);
			eof := FALSE;
			
			(* fill the buffer with the first bytes *)
			ReadLongintFromStream();
			ReadLongintFromStream();
		END SetPos;
		
		PROCEDURE HasMoreData*(): BOOLEAN;
		BEGIN
			RETURN ~(eof & (bitsLeft <= 0));
		END HasMoreData;
		
	END BitStream;
	
	
	(* Provides procedures to read multiple information from an MPEGBitStream *)
	StreamReader* = OBJECT
		VAR
			stream: BitStream;
			eof*: BOOLEAN;
		
		(* constructor *)
		PROCEDURE &init(s: BitStream);
		BEGIN
			stream := s;
			eof := FALSE;
		END init;
		
		(* Read the next motion code from the stream *)
		PROCEDURE ReadMotionCode*(): LONGINT;
		VAR
			bits: LONGINT;
			res: LONGINT;
			
		BEGIN
			IF eof THEN RETURN 0 END;
			
			bits := stream.GetBits(1);
			IF bits = 1 THEN
				RETURN 0;
			ELSIF bits < 0 THEN
				eof := TRUE;
				RETURN 0;
			ELSE
				bits := stream.ShowBits(3);
				IF bits < 0 THEN eof := TRUE; RETURN 0 END;
				IF bits # 0 THEN
					res := MPEGTables.MC4[bits][0];
					stream.SkipBits(MPEGTables.MC4[bits][1]);
					bits := stream.GetBits(1);
					IF bits = 1 THEN
						RETURN -res;
					ELSIF bits < 0 THEN
						eof := TRUE;
						RETURN 0;
					ELSE
						RETURN res;
					END;
				ELSE
					stream.SkipBits(3);
					bits := stream.ShowBits(3);
					IF bits < 0 THEN eof := TRUE; RETURN 0 END;
					IF bits >= 3 THEN
						res := MPEGTables.MC7[bits][0];
						stream.SkipBits(MPEGTables.MC7[bits][1]);
						bits := stream.GetBits(1);
						IF bits = 1 THEN
							RETURN -res;
						ELSIF bits < 0 THEN
							eof := TRUE;
							RETURN 0;
						ELSE
							RETURN res;
						END;
					ELSE
						stream.SkipBits(1);
						bits := stream.ShowBits(5) - 12;
						IF bits <= -12 THEN eof := TRUE; RETURN 0 END;
						res := MPEGTables.MC10[bits][0];
						stream.SkipBits(MPEGTables.MC10[bits][1]);
						bits := stream.GetBits(1);
						IF bits = 1 THEN
							RETURN -res;
						ELSIF bits < 0 THEN
							eof := TRUE;
							RETURN 0;
						ELSE
							RETURN res;
						END;
					END;
				END;
			END;
		END ReadMotionCode;
		
		
		(* Read the next run/level code from the stream. Assumption: 10 = end of block (not 0/1) *)
		(* Returns EndOfBlock *)
		PROCEDURE ReadRunLevelCode*(c: PointerToArrayOfLONGINT; VAR cur: LONGINT; MPEG2: BOOLEAN): BOOLEAN;
		VAR
			run, length: LONGINT;
			level: LONGINT;
			index: LONGINT;
			
		BEGIN
			IF eof THEN RETURN TRUE END;
			
			length := 0;
			
			CASE stream.ShowBits(6) OF
				0:	
					(* 0000 00 -> CASE for the next 6 bits *)
					CASE stream.ShowBits(12) OF
						1:
							(* 0000 0000 0001 -> RLC17*)
							stream.SkipBits(12);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := MPEGTables.RLC17[index][0];
							level := MPEGTables.RLC17[index][1];
							length := 4;
							
					|	2..3:
							(* 0000 0000 0010 .. 0000 0000 0011 -> RLC16*)
							stream.SkipBits(11);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := MPEGTables.RLC16[index][0];
							level := MPEGTables.RLC16[index][1];
							length := 4;

					|	4..7:
							(* 0000 0000 0100 .. 0000 0000 0111 -> no table (trivial) *)
							stream.SkipBits(10);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := 0;
							level := 31-index;
							length := 4;

					|	8..15:
							(* 0000 0000 1000 .. 0000 0000 1111 -> RLC14*)
							stream.SkipBits(9);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := MPEGTables.RLC14[index][0];
							level := MPEGTables.RLC14[index][1];
							length := 4;

					|	16..31:
							(* 0000 0001 0000 .. 0000 0001 1111 -> RLC13*)
							stream.SkipBits(8);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := MPEGTables.RLC13[index][0];
							level := MPEGTables.RLC13[index][1];
							length := 4;

					|	32..63:
							(* 0000 0010 0000 .. 0000 0011 1111 -> RLC11*)
							stream.SkipBits(7);
							index := stream.ShowBits(3);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := MPEGTables.RLC11[index][0];
							level := MPEGTables.RLC11[index][1];
							length := 3;
							
					ELSE
						(* must be negative *)
						eof := TRUE;
						RETURN TRUE;
					END;

			|	1:	
					(* 0000 01 -> Escape *)
					stream.SkipBits(6);
					run := stream.GetBits(6);
					IF run < 0 THEN eof := TRUE; RETURN TRUE END;
					IF ~MPEG2 THEN
						index := stream.GetBits(8);
						IF index = 0 THEN
							level := stream.GetBits(8);
							IF level < 0 THEN eof := TRUE; RETURN TRUE END;
						ELSIF index = 128 THEN
							level := -stream.GetBits(8);
							IF level > 0 THEN eof := TRUE; RETURN TRUE END;
						ELSIF index < 0 THEN
							eof := TRUE;
							RETURN TRUE;
						ELSE
							IF index > 127 THEN
								level := -256+index;
							ELSE
								level := index;
							END;
						END;
					ELSE
						(* MPEG-2 *)
						level := stream.GetBits(12);
						ASSERT(level # 0);
						IF level > 2047 THEN
							level := level - 4095;	(* level + 1 - 2*2048 *)
						ELSIF level < 0 THEN
							eof := TRUE;
							RETURN TRUE;
						END;
					END;
					INC(cur, run);
					c[MPEGTables.ZZN[cur]] := level;
					INC(cur);
					RETURN FALSE;
					
			|	2..7:
					(* 0000 10 .. 0001 11 -> RLC8 *)
					index := stream.ShowBits(7) - 4;
					IF index < 0 THEN eof := TRUE; RETURN TRUE END;
					run := MPEGTables.RLC8[index][0];
					level := MPEGTables.RLC8[index][1];
					length := MPEGTables.RLC8[index][2];

			|	8..9:
					(* 0010 00 .. 0010 01 -> RLC9 *)
					index := stream.ShowBits(8) - 32;
					IF index < 0 THEN eof := TRUE; RETURN TRUE END;
					run := MPEGTables.RLC9[index][0];
					level := MPEGTables.RLC9[index][1];
					length := 8;
					
			|	10..31:
					(* 0010 10 .. 0111 11 -> RLC6 *)
					index := stream.ShowBits(5) - 5;
					IF index < 0 THEN eof := TRUE; RETURN TRUE END;
					run := MPEGTables.RLC6[index][0];
					level := MPEGTables.RLC6[index][1];
					length := MPEGTables.RLC6[index][2];

			|	32..47:
					(* 1000 00 .. 1011 11 -> End of Block *)
					stream.SkipBits(2);
					RETURN TRUE;
					
			|	48..63:
					(* 1100 00 .. 1111 11 -> 0/1 *)
					run := 0;
					level := 1;
					length := 2;
					
			ELSE
				eof := TRUE;
				RETURN TRUE;
			END;
			
			stream.SkipBits(length);
			index := stream.GetBits(1);
			IF index = 1 THEN
				level := -level;
			ELSIF index < 0 THEN
				eof := TRUE;
				RETURN TRUE;
			END;
			
			INC(cur, run);
			c[MPEGTables.ZZN[cur]] := level;
			INC(cur);
			
			RETURN FALSE;
		END ReadRunLevelCode;
		
		
		(* Read the next run/level code from the stream (second table, MPEG2 only) *)
		(* Returns EndOfBlock *)
		PROCEDURE ReadRunLevelCode2*(c: PointerToArrayOfLONGINT; VAR cur: LONGINT): BOOLEAN;
		VAR
			run, length: LONGINT;
			level: LONGINT;
			index: LONGINT;

		BEGIN
			IF eof THEN RETURN TRUE END;
			
			length := 0;
			
			CASE stream.ShowBits(6) OF
				0:	
					(* 0000 00 -> CASE for the next 6 bits *)
					CASE stream.ShowBits(12) OF
						1:
							(* 0000 0000 0001 -> RLC17*)
							stream.SkipBits(12);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := MPEGTables.RLC17[index][0];
							level := MPEGTables.RLC17[index][1];
							length := 4;
							
					|	2..3:
							(* 0000 0000 0010 .. 0000 0000 0011 -> RLC16*)
							stream.SkipBits(11);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := MPEGTables.RLC16[index][0];
							level := MPEGTables.RLC16[index][1];
							length := 4;

					|	4..7:
							(* 0000 0000 0100 .. 0000 0000 0111 -> no table (trivial) *)
							stream.SkipBits(10);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := 0;
							level := 31-index;
							length := 4;

					|	8..15:
							(* 0000 0000 1000 .. 0000 0000 1111 -> RLC14*)
							stream.SkipBits(9);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := MPEGTables.RLC14[index][0];
							level := MPEGTables.RLC14[index][1];
							length := 4;

					|	16..31:
							(* 0000 0001 0000 .. 0000 0001 1111 -> RLC13*)
							stream.SkipBits(8);
							index := stream.ShowBits(4);
							IF index < 0 THEN eof := TRUE; RETURN TRUE END;
							run := MPEGTables.RLC13[index][0];
							level := MPEGTables.RLC13[index][1];
							length := 4;

					|	32..39:
							(* 0000 0010 0 -> 5/2*)
							run := 5;
							level := 2;
							length := 9;
							
					|	40..47:
							(* 0000 0010 1 -> 14/1*)
							run := 14;
							level := 1;
							length := 9;
							
					|	48..51:
							(* 0000 0011 00 -> 2/4*)
							run := 2;
							level := 4;
							length := 10;
							
					|	52..55:
							(* 0000 0011 01 -> 16/1*)
							run := 16;
							level := 1;
							length := 10;
							
					|	56..63:
							(* 0000 0011 1 -> 15/1*)
							run := 15;
							level := 1;
							length := 9;
							
					ELSE
						(* must be negative *)
						eof := TRUE;
						RETURN TRUE;
					END;

			|	1:	
					(* 0000 01 -> Escape *)
					stream.SkipBits(6);
					run := stream.GetBits(6);
					IF run < 0 THEN eof := TRUE; RETURN TRUE END;
					level := stream.GetBits(12);
					ASSERT(level # 0);
					IF level > 2047 THEN
						level := level - 4095;	(* level + 1 - 2*2048 *)
					ELSIF level < 0 THEN
						eof := TRUE;
						RETURN TRUE;
					END;
					INC(cur, run);
					c[MPEGTables.ZZN[cur]] := level;
					INC(cur);
					RETURN FALSE;
					
			|	2..7:
					(* 0000 10 .. 0001 11 -> RLC8_2 *)
					index := stream.ShowBits(7) - 4;
					IF index < 0 THEN eof := TRUE; RETURN TRUE END;
					run := MPEGTables.RLC8_2[index][0];
					level := MPEGTables.RLC8_2[index][1];
					length := MPEGTables.RLC8_2[index][2];

			|	8..9:
					(* 0010 00 .. 0010 01 -> RLC9_2 *)
					index := stream.ShowBits(8) - 32;
					IF index < 0 THEN eof := TRUE; RETURN TRUE END;
					run := MPEGTables.RLC9_2[index][0];
					level := MPEGTables.RLC9_2[index][1];
					length := 8;
					
			|	10..11:
					(* 0010 1 -> 2/1 *)
					run := 2;
					level := 1;
					length := 5;

			|	12..13:
					(* 0011 0 -> 1/2 *)
					run := 1;
					level := 2;
					length := 5;

			|	14..15:
					(* 0011 1 -> 3/1 *)
					run := 3;
					level := 1;
					length := 5;

			|	16..23:
					(* 010 -> 1/1 *)
					run := 1;
					level := 1;
					length := 3;

			|	24..27:
					(* 0110 -> End of Block *)
					stream.SkipBits(4);
					RETURN TRUE;
					
			|	28..31:
					(* 0111 -> 0/3 *)
					run := 0;
					level := 3;
					length := 4;
					
			|	32..47:
					(* 10 -> 0/1 *)
					run := 0;
					level := 1;
					length := 2;
					
			|	48..55:
					(* 110 -> 0/23 *)
					run := 0;
					level := 2;
					length := 3;
					
			|	56..57:
					(* 1110 0 -> 0/4 *)
					run := 0;
					level := 4;
					length := 5;
					
			|	58..59:
					(* 1110 1 -> 0/6 *)
					run := 0;
					level := 6;
					length := 5;
					
			|	60..63:
					(* 1111 00 .. 1111 11 -> RLC9_2_2 *)
					index := stream.ShowBits(8) - 240;
					IF index < 0 THEN eof := TRUE; RETURN TRUE END;
					run := MPEGTables.RLC9_2_2[index][0];
					level := MPEGTables.RLC9_2_2[index][1];
					length := MPEGTables.RLC9_2_2[index][2];
			
			ELSE
				eof := TRUE;
				RETURN TRUE;
			END;
			
			stream.SkipBits(length);
			index := stream.GetBits(1);
			IF index = 1 THEN
				level := -level;
			ELSIF index < 0 THEN
				eof := TRUE;
				RETURN TRUE;
			END;
			
			INC(cur, run);
			c[MPEGTables.ZZN[cur]] := level;
			INC(cur);
			
			RETURN FALSE;
		END ReadRunLevelCode2;
		
		
		(* Read the macroblock address increment *)
		(* Return value: > 0 -> increment; -1 -> error; -2 -> escape; -3 -> stuffing *)
		PROCEDURE ReadAddressIncrement*():LONGINT;
		VAR
			tmp: LONGINT;
			
		BEGIN
			IF eof THEN RETURN 0 END;
			
			CASE stream.ShowBits(4) OF
				0:	
					(* code length 7..11 *)
					stream.SkipBits(4);
					
					CASE stream.ShowBits(4) OF
						0:
							(* illegal value *)
							RETURN -1;
							
					|	1:	
							(* escape or stuffing *)
							stream.SkipBits(4);
							tmp := stream.GetBits(3);
							IF tmp = 0 THEN
								RETURN -2;
							ELSIF tmp = 7 THEN
								RETURN -3;
							ELSIF tmp < 0 THEN
								eof := TRUE;
								RETURN 0;
							ELSE
								RETURN -1;
							END;
							
					|	2:
							(* illegal value *)
							RETURN -1;
							
					|	3..5:
							(* code length 10 or 11 *)
							IF stream.ShowBits(6) >= 18 THEN
								tmp := stream.GetBits(6);
								RETURN (39-tmp);
							ELSIF stream.ShowBits(6) < 0 THEN
								eof := TRUE;
								RETURN 0;
							ELSE
								tmp := stream.GetBits(7);
								RETURN (57-tmp);
							END;
							
					|	6..11:
							(* code length 8 *)
							tmp := stream.GetBits(4);
							IF tmp < 0 THEN eof := TRUE; RETURN 0 END;
							RETURN (21-tmp);
					
					|	12..15:
							(* code length 7 *)
							tmp := stream.GetBits(3);
							IF tmp < 0 THEN eof := TRUE; RETURN 0 END;
							RETURN (15-tmp);
					
					ELSE
						eof := TRUE;
						RETURN 0;
					END;
				
			|	1:	
					(* code length 5 *)
					tmp := stream.GetBits(5);
					IF tmp < 0 THEN eof := TRUE; RETURN 0 END;
					RETURN (9-tmp);
			
			|	2:	
					(* code 0010 *)
					stream.SkipBits(4);
					RETURN 5;
			
			|	3:	
					(* code 0011 *)
					stream.SkipBits(4);
					RETURN 4;
					
			|	4,5:	
					(* code 010 *)
					stream.SkipBits(3);
					RETURN 3;
					
			|	6,7:	
					(* code 011 *)
					stream.SkipBits(3);
					RETURN 2;
					
			|	8..15:
					(* code 1 *)
					stream.SkipBits(1);
					RETURN 1;
			
			ELSE
				eof := TRUE;
				RETURN 0;
			END;
		END ReadAddressIncrement;
		
		
		PROCEDURE ReadMacroBlockType*(type: LONGINT; VAR intra, pattern, back, forw, quant: BOOLEAN): BOOLEAN;
		VAR
			tmp: LONGINT;
			
		BEGIN
			IF eof THEN RETURN FALSE END;
			
			intra := FALSE;
			pattern := FALSE;
			back := FALSE;
			forw := FALSE;
			quant := FALSE;
			
			CASE type OF
				1:	(* I-Picture *)
					intra := TRUE;
					tmp := stream.GetBits(1);
					IF tmp = 1 THEN
						RETURN TRUE;
					ELSIF tmp < 0 THEN
						eof := TRUE;
						RETURN FALSE;
					ELSE
						tmp := stream.GetBits(1);
						IF tmp = 1 THEN
							quant := TRUE;
							RETURN TRUE;
						ELSIF tmp < 0 THEN
							eof := TRUE;
							RETURN FALSE;
						ELSE
							RETURN FALSE;
						END;
					END;
					
			|	2:	(* P-Picture *)
					CASE stream.ShowBits(3) OF
						0:
							stream.SkipBits(3);
							CASE stream.ShowBits(3) OF
								0: 
									(* illegal value *)
									RETURN FALSE;
									
							|	1:
									(* 0000 01 *)
									stream.SkipBits(3);
									intra := TRUE;
									quant := TRUE;
									RETURN TRUE;
									
							|	2,3:
									(* 0000 1 *)
									stream.SkipBits(2);
									pattern := TRUE;
									quant := TRUE;
									RETURN TRUE;
									
							|	4,5:
									(* 0001 0 *)
									stream.SkipBits(2);
									pattern := TRUE;
									forw := TRUE;
									quant := TRUE;
									RETURN TRUE;
									
							|	6,7:
									(* 0001 1 *)
									stream.SkipBits(2);
									intra := TRUE;
									RETURN TRUE;
							
							ELSE
								eof := TRUE;
								RETURN FALSE;
							END;
							
					|	1:	
							(* 001 *)
							stream.SkipBits(3);
							forw := TRUE;
							RETURN TRUE;
							
					|	2,3:
							(* 01 *)
							stream.SkipBits(2);
							pattern := TRUE;
							RETURN TRUE;
							
					|	4..7:
							(* 1 *)
							stream.SkipBits(1);
							pattern := TRUE;
							forw := TRUE;
							RETURN TRUE;
							
					ELSE
						eof := TRUE;
						RETURN FALSE;
					END;
		
			|	3:	(* B-Picture *)
					CASE stream.ShowBits(4) OF
						0:
							stream.SkipBits(4);
							tmp := stream.GetBits(2);
							CASE tmp OF
								0:
									(* illegal value *)
									RETURN FALSE;
									
							|	1:
									(* 0000 01 *)
									intra := TRUE;
									quant := TRUE;
									RETURN TRUE;
									
							|	2:
									(* 0000 10 *)
									pattern := TRUE;
									back := TRUE;
									quant := TRUE;
									RETURN TRUE;
									
							|	3:
									(* 0000 11 *)
									pattern := TRUE;
									forw := TRUE;
									quant := TRUE;
									RETURN TRUE;
							ELSE
								eof := TRUE;
								RETURN FALSE;
							END;
							
					|	1:
							stream.SkipBits(4);
							tmp := stream.GetBits(1);
							IF tmp = 0 THEN
								(* 0001 0 *)
								pattern := TRUE;
								forw := TRUE;
								back := TRUE;
								quant := TRUE;
								RETURN TRUE;
							ELSIF tmp < 0 THEN
								eof := TRUE;
								RETURN FALSE;
							ELSE
								(* 0001 1 *)
								intra := TRUE;
								RETURN TRUE;
							END;
							
					|	2:
							(* 0010 *)
							stream.SkipBits(4);
							forw := TRUE;
							RETURN TRUE;
							
					|	3:
							(* 0011 *)
							stream.SkipBits(4);
							pattern := TRUE;
							forw := TRUE;
							RETURN TRUE;
							
					|	4,5:
							(* 010 *)
							stream.SkipBits(3);
							back := TRUE;
							RETURN TRUE;
							
					|	6,7:
							(* 011 *)
							stream.SkipBits(3);
							pattern := TRUE;
							back := TRUE;
							RETURN TRUE;
							
					|	8..11:
							(* 10 *)
							stream.SkipBits(2);
							forw := TRUE;
							back := TRUE;
							RETURN TRUE;
							
					|	12..15:
							(* 11 *)
							stream.SkipBits(2);
							pattern := TRUE;
							forw := TRUE;
							back := TRUE;
							RETURN TRUE;
					
					ELSE
						eof := TRUE;
						RETURN FALSE;
					END;
			
			|	4:	(* D-Picture *)
					tmp := stream.GetBits(1);
					IF tmp = 1 THEN
						intra := TRUE;
						RETURN TRUE;
					ELSIF tmp < 0 THEN
						eof := TRUE;
						RETURN FALSE;
					ELSE
						RETURN FALSE;
					END;
					
			ELSE
				RETURN FALSE;		(* illegal picture type *)
			END;
			
			(* we should not reach this point *)
		END ReadMacroBlockType;
		
		PROCEDURE ReadSequenceExtension*(
			VAR MainProfile: BOOLEAN;
			 VAR LevelID: LONGINT;
			 VAR ChromaFormat: LONGINT;
			 VAR videoWidth, videoHeight: LONGINT): BOOLEAN;
		VAR
			tmp: LONGINT;
			
		BEGIN
			IF eof THEN RETURN FALSE END;
			
			(* escape bit, must be 0 for all currently defined profiles and levels *)
			IF stream.ShowBits(1) # 0 THEN
				IF stream.ShowBits(1) < 0 THEN
					eof := TRUE;
					RETURN FALSE;
				ELSE
					AosOut.String("Profile/Level not supported"); AosOut.Ln; 
					RETURN FALSE;
				END;
			ELSE
				stream.SkipBits(1);
			END;
			
			(* Profile *)
			CASE stream.ShowBits(3) OF
				0..3, 6, 7:
					AosOut.String("Profile not supported"); AosOut.Ln; 
					RETURN FALSE;
				
			|	4:	(* Main Profile *)
					MainProfile := TRUE;
					
			|	5:	(* Simple Profile *)
					MainProfile := FALSE;
			ELSE
				eof := TRUE;
				RETURN FALSE;
			END;
			stream.SkipBits(3);
			
			(* Level *)
			CASE stream.ShowBits(4) OF
				0..3, 5, 7, 9, 11..16:
					AosOut.String("Level not supported"); AosOut.Ln; 
					RETURN FALSE;
				
			|	4:	(* High *)
					IF MainProfile THEN
						LevelID := 4;
					ELSE
						AosOut.String("Level not supported"); AosOut.Ln;
						RETURN FALSE;
					END;
					
			|	6:	(* High 1440 *)
					IF MainProfile THEN
						LevelID := 3;
					ELSE
						AosOut.String("Level not supported"); AosOut.Ln;
						RETURN FALSE;
					END;
					
			|	8: 	(* Main *)
					LevelID := 2;
					
			|	10:	(* Low *)
					LevelID := 1;
			ELSE
				eof := TRUE;
				RETURN FALSE;
			END;
			stream.SkipBits(4);
			
			(* Progressive Bit *)
			(* We ignore this bit because it is rarely used (even if the whole movie IS progressive) and therefore does not help that much *)
			stream.SkipBits(1);
			
			(* Chroma format *)
			CASE stream.ShowBits(2) OF
				0:	(* reserved *)
					AosOut.String("Illegal chroma format"); AosOut.Ln; 
					
			| 	1:	(* 4:2:0, the only format required to be supported by MP@ML *)
					ChromaFormat := 1;
					
			|	2:	(* 4:2:2, currently not supported - not sure if it will ever be... *)
					AosOut.String("4:2:2 chroma format is not supported"); AosOut.Ln; 
					RETURN FALSE;
					
			|	3:	(* 4:4:4, currently not supported - not sure if it will ever be... *)
					AosOut.String("4:4:4: chroma format is not supported"); AosOut.Ln; 
					RETURN FALSE;
			ELSE
				eof := TRUE;
				RETURN FALSE;
			END;
			stream.SkipBits(2);
			
			(* horizontal size extension *)
			tmp := stream.GetBits(2);
			IF tmp < 0 THEN RETURN FALSE END;
			videoWidth := tmp * 4096 + videoWidth;
			
			(* vertical size extension *)
			tmp := stream.GetBits(2);
			IF tmp < 0 THEN RETURN FALSE END;
			videoHeight := tmp * 4096 + videoHeight;
			
			(* ignore all the rest: bitrate (12), marker (1), vbv buffer (8), low delay (1), framerate (7) *)
			stream.SkipBits(29);
			
			RETURN TRUE;
		END ReadSequenceExtension;

		PROCEDURE ReadSequenceDisplayExtension*(): BOOLEAN;
		BEGIN
			IF eof THEN RETURN FALSE END;

			(* Contains information about the source video format -> not important for the decoder *)
			stream.SkipBits(7);
			IF stream.ShowBits(1) = 1 THEN
				stream.SkipBits(24);
			END;
			stream.SkipBits(30);
			RETURN TRUE;
		END ReadSequenceDisplayExtension;

		PROCEDURE ReadQuantMatrixExtension*(): BOOLEAN;
		BEGIN
			IF eof THEN RETURN FALSE END;
		END ReadQuantMatrixExtension;

		PROCEDURE ReadCopyrightExtension*(): BOOLEAN;
		BEGIN
			IF eof THEN RETURN FALSE END;
		END ReadCopyrightExtension;

		PROCEDURE ReadPictureDisplayExtension*(): BOOLEAN;
		BEGIN
			IF eof THEN RETURN FALSE END;
		END ReadPictureDisplayExtension;
		
		PROCEDURE ReadPictureCodingExtension*(VAR pce: PicCodingExt; VAR mvi: MotionVectorInfos): BOOLEAN;
		BEGIN
			IF eof THEN RETURN FALSE END;

			mvi.fCode[0][0] := stream.GetBits(4);
			mvi.fCode[0][1] := stream.GetBits(4);
			mvi.fCode[1][0] := stream.GetBits(4);
			mvi.fCode[1][1] := stream.GetBits(4);
			pce.dcPrecision := stream.GetBits(2);
			pce.picStructure := stream.GetBits(2);
			pce.topFieldFirst := stream.ShowBits(1) = 1; stream.SkipBits(1);
			pce.framePredFrameDct := stream.ShowBits(1) = 1; stream.SkipBits(1);
			pce.concealmentMV := stream.ShowBits(1) = 1; stream.SkipBits(1);
			pce.qScaleType := stream.ShowBits(1) = 1; stream.SkipBits(1);
			pce.intraVlcFormat := stream.ShowBits(1) = 1; stream.SkipBits(1);
			pce.alternateScan := stream.ShowBits(1) = 1; stream.SkipBits(1);
			pce.repeatFirstField := stream.ShowBits(1) = 1; stream.SkipBits(1);
			pce.chroma420Type := stream.ShowBits(1) = 1; stream.SkipBits(1);
			pce.progressiveFrame := stream.ShowBits(1) = 1; stream.SkipBits(1);
			IF stream.ShowBits(1) = 1 THEN
				stream.SkipBits(21);
			ELSE
				stream.SkipBits(1);
			END;
			IF stream.ShowBits(1) < 0 THEN
				eof := TRUE;
				RETURN FALSE;
			END;
			RETURN TRUE;
		END ReadPictureCodingExtension;
		
		PROCEDURE ReadQuantizerMatrix*(matrix: PointerToArrayOfLONGINT);
		VAR
			i, j: LONGINT;
			tmp: LONGINT;
			zzQM: ARRAY 64 OF LONGINT;
			
		BEGIN
			IF eof THEN RETURN END;

			FOR i := 0 TO 63 DO
				tmp := stream.GetBits(8);
				IF tmp < 0 THEN
					eof := TRUE;
					RETURN;
				ELSE
					zzQM[i] := tmp;
				END;
			END;
			
			FOR i := 0 TO 7 DO
				FOR j := 0 TO 7 DO
					matrix[i*8+j] := zzQM[MPEGTables.ZZ[i][j]];;
				END;
			END;
		END ReadQuantizerMatrix;
	

		PROCEDURE ReadMotionVectors*(s: LONGINT; VAR mvi: MotionVectorInfos; frameMotionType: LONGINT);
		BEGIN
			IF eof THEN RETURN END;

			IF frameMotionType # 1 THEN
				IF frameMotionType # 2 THEN
					mvi.motionVerticalFieldSelect[0][s] := (stream.GetBits(1) = 1);
				END;
				ReadMotionVectorsHelper(0, s, mvi);
			ELSE
				(* motionVectorCount = 2 *)
				mvi.motionVerticalFieldSelect[0][s] := (stream.GetBits(1) = 1);
				ReadMotionVectorsHelper(0, s, mvi);
				mvi.motionVerticalFieldSelect[1][s] := (stream.GetBits(1) = 1);
				ReadMotionVectorsHelper(1, s, mvi);
			END;
			IF stream.ShowBits(1) < 0 THEN
				eof := TRUE;
			END;
		END ReadMotionVectors;
		

		PROCEDURE ReadMotionVectorsHelper(r, s: LONGINT; VAR mvi: MotionVectorInfos);
		BEGIN
			IF eof THEN RETURN END;

			mvi.motionCode[r][s][0] := ReadMotionCode();
			IF (mvi.fCode[s][0] # 1) & (mvi.motionCode[r][s][0] # 0) THEN
				mvi.motionResidual[r][s][0] := stream.GetBits(mvi.fCode[s][0] - 1);
			END;
			IF FALSE THEN
				CASE stream.ShowBits(2) OF
					0,1:	mvi.dmVector[0] := 0;
						stream.SkipBits(1);
				|	2:	mvi.dmVector[0] := 1;
						stream.SkipBits(2);
				|	3:	mvi.dmVector[0] := -1;
						stream.SkipBits(2);
				END;
			END;
			mvi.motionCode[r][s][1] := ReadMotionCode();
			IF (mvi.fCode[s][1] # 1) & (mvi.motionCode[r][s][1] # 0) THEN
				mvi.motionResidual[r][s][1] :=  stream.GetBits(mvi.fCode[s][1] - 1);
			END;
			IF FALSE THEN		(* interlaced videos only *)
				CASE stream.ShowBits(2) OF
					0,1:	mvi.dmVector[1] := 0;
						stream.SkipBits(1);
				|	2:	mvi.dmVector[1] := 1;
						stream.SkipBits(2);
				|	3:	mvi.dmVector[1] := -1;
						stream.SkipBits(2);
				END;
			END;
			IF stream.ShowBits(1) < 0 THEN
				eof := TRUE;
			END;
		END ReadMotionVectorsHelper;
	END StreamReader;
	
	TYPE MMXConsts = POINTER TO MMXConstsDesc;
	TYPE MMXConstsDesc = RECORD
		mmwMultY, mmwMultUG, mmwMultUB, mmwMultVR, mmwMultVG: HUGEINT;

		(* various masks and other constants *)
		mmb10, mmw0080, mmw00ff, mmwCutRed, mmwCutGreen, mmwCutBlue: HUGEINT;

		mask5, mask6, maskBlue: HUGEINT;
	END;

	(* Convert colorspace (copied and slightly edited from the DivXPlayer) *)	
	TYPE ColorSpace* = OBJECT
		VAR
			mmxConsts: MMXConsts;
		
		(* initialize rgb lookup tables *)
		PROCEDURE &Init( );
		BEGIN
			NEW( mmxConsts );
			mmxConsts.mmwMultY := 2568256825682568H;
			mmxConsts.mmwMultUG := 0F36EF36EF36EF36EH;
			mmxConsts.mmwMultUB := 40CF40CF40CF40CFH;
			mmxConsts.mmwMultVR := 3343334333433343H;
			mmxConsts.mmwMultVG := 0E5E2E5E2E5E2E5E2H;
	
			(* various masks and other constants *)
			mmxConsts.mmb10 := 1010101010101010H;
			mmxConsts.mmw0080 := 0080008000800080H;
			mmxConsts.mmw00ff := 00FF00FF00FF00FFH;
			mmxConsts.mmwCutRed := 7C007C007C007C00H;
			mmxConsts.mmwCutGreen := 03E003E003E003E0H;
			mmxConsts.mmwCutBlue := 001F001F001F001FH;

			mmxConsts.mask5 := 0F8F8F8F8F8F8F8F8H;
			mmxConsts.mask6 := 0FCFCFCFCFCFCFCFCH;
			mmxConsts.maskBlue :=  1F1F1F1F1F1F1F1FH;	
		END Init;

		(* Convert picture from one colorspace to an another *)
		PROCEDURE Convert*(
			src: PointerToArrayOfCHAR; 
			srcYBaseOffset: LONGINT; 
			yStride: LONGINT; 
			srcUBaseOffset, srcVBaseOffset,uvStride: LONGINT; 
			img: Raster.Image;
			 width, height, dstStride: LONGINT );
		BEGIN
			IF img.fmt.code = Raster.BGR888.code THEN
				ConvertYUVToRGB888( src, srcYBaseOffset,  yStride, srcUBaseOffset, srcVBaseOffset, uvStride, img, width, height, 
					dstStride );
			ELSIF img.fmt.code = Raster.BGR565.code THEN
				IF EnableMMX THEN
					ConvertYUVToRGB565MMX( src, srcYBaseOffset,  yStride, srcUBaseOffset, srcVBaseOffset, uvStride, img, width, height, 
						dstStride );
				ELSE
					ConvertYUVToRGB565( src, srcYBaseOffset,  yStride, srcUBaseOffset, srcVBaseOffset, uvStride, img, width, height, 
						dstStride );
				END;
			END;
		END Convert;
		
		(* Convert picture from YUV -> RGB 565, mmx version *)
		PROCEDURE ConvertYUVToRGB565MMX(
			puc: PointerToArrayOfCHAR; 
			pucYBaseOffset: LONGINT; 
			strideY: LONGINT; 
			pucUBaseOffset, pucVBaseOffset, strideUV: LONGINT; 
			pucOut: Raster.Image; 
			widthY, heightY, strideOut: LONGINT );
		VAR
			y, horizCount: LONGINT;
			pusOut: LONGINT;
			
		BEGIN			
			 strideOut := widthY*2;
			 
			 IF heightY < 0 THEN
				(* we are flipping our output upside-down *)
				heightY  := -heightY;
				pucYBaseOffset := pucYBaseOffset + ( heightY - 1 ) * strideY ;
				pucUBaseOffset := pucUBaseOffset + ( heightY DIV 2 - 1 ) * strideUV;
				pucVBaseOffset := pucVBaseOffset + ( heightY DIV 2 - 1 ) * strideUV;
				strideY  := -strideY;
				strideUV := -strideUV;
			END;
			
			pusOut := pucOut.adr;
			pucYBaseOffset := SYSTEM.ADR( puc[0] )+ pucYBaseOffset;
			pucUBaseOffset := SYSTEM.ADR ( puc[0] ) + pucUBaseOffset;
			pucVBaseOffset := SYSTEM.ADR( puc[0] ) + pucVBaseOffset;
			
			horizCount := -(widthY DIV 8);

			FOR y := 0 TO heightY-1 DO 
				ScanLine565MMX(horizCount, pucVBaseOffset, pucUBaseOffset, pucYBaseOffset, pusOut, 
					SYSTEM.ADR( mmxConsts.mmwMultY ) );
					
					pucYBaseOffset := pucYBaseOffset + strideY;
					IF ( y MOD 2 ) > 0 THEN
						pucUBaseOffset := pucUBaseOffset + strideUV;
						pucVBaseOffset := pucVBaseOffset + strideUV
				END;
					pusOut := pusOut + strideOut;
			END;
		END ConvertYUVToRGB565MMX;
	
		PROCEDURE ScanLine565MMX(horizCount, pucV, pucU, pucY, pucOut: LONGINT; mmxConsts: LONGINT);
		CODE { SYSTEM.MMX, SYSTEM.PentiumPro }

			MOV EAX, pucOut[EBP]
			MOV EBX, pucY[EBP]
			MOV ECX, pucU[EBP]  
			MOV EDX, pucV[EBP]
			MOV EDI, horizCount[EBP]
			MOV ESI, mmxConsts[EBP]
			
		horizLoop:
			; load data
			MOVD MM2, [ECX]						; mm2 = ________u3u2u1u0
			MOVD MM3, [EDX]						; mm3 = ________v3v2v1v0
			MOVQ MM0, [EBX]						; mm0 = y7y6y5y4y3y2y1y0  
			
			PXOR MM7, MM7							; zero mm7

			; convert chroma part
			PUNPCKLBW MM2, MM7       		; MM2 = __U3__U2__U1__U0
			PUNPCKLBW MM3, MM7       		; MM3 = __V3__V2__V1__V0
;			PSUBW MM2, mmw0080			; MM2 -= 128
			PSUBW MM2, 48[ESI]				; MM2 -= 128
;			PSUBW MM3, mmw0080			; MM3 -= 128
			PSUBW MM3, 48[ESI]				; MM3 -= 128
			PSLLW MM2, 3								; MM2 *= 8
			PSLLW MM3, 3								; MM3 *= 8
			MOVQ MM4, MM2						; MM4 = MM2 = U
			MOVQ MM5, MM3						; MM5 = MM3 = V
;			PMULHW MM2, mmwMultUG		; MM2 *= U GREEN COEFF 
;			PMULHW MM3, mmwMultVG		; MM3 *= V GREEN COEFF  
;			PMULHW MM4, mmwMultUB		; MM4 = BLUE CHROMA
;			PMULHW MM5, mmwMultVR		; MM5 = RED CHROMA
			PMULHW MM2, 8[ESI] 				; MM2 *= U GREEN COEFF 
			PMULHW MM3, 32[ESI] 			; MM3 *= V GREEN COEFF  
			PMULHW MM4, 16[ESI] 			; MM4 = BLUE CHROMA
			PMULHW MM5, 24[ESI]				; MM5 = RED CHROMA

			PADDSW MM2, MM3					 ; MM2 = GREEN CHROMA

			; convert luma part
;			PSUBUSB MM0, mmb10				; MM0 -= 16
;			MOVQ MM1, mmw00ff 
			PSUBUSB MM0, 40[ESI]				; MM0 -= 16
			MOVQ MM6, 56[ESI]					; 
			MOVQ MM1, MM0
			PSRLW MM0, 8							; MM0 = __Y7__Y5__Y3__Y1 LUMA ODD
			PAND MM1, MM6						; MM1 = __Y6__Y4__Y2__Y0 LUMA EVEN
			PSLLW MM0, 3								; MM0 *= 8
			PSLLW MM1, 3								; MM1 *= 8
;			PMULHW MM0, mmwMultY		; MM0 LUMA ODD *= LUMA COEFF 
;			PMULHW MM1, mmwMultY			; MM1 LUMA EVEN *= LUMA COEFF 
			PMULHW MM0, [ESI]					; MM0 LUMA ODD *= LUMA COEFF 
			PMULHW MM1, [ESI]					; MM1 LUMA EVEN *= LUMA COEFF 
			; complete the matrix calc with the additions
			MOVQ MM3, MM4						 ; COPY BLUE CHROMA
			MOVQ MM6, MM5						 ; COPY RED CHROMA
			MOVQ MM7, MM2						 ; COPY GREEN CHROMA
			PADDSW MM3, MM0					 ; MM3 = LUMA ODD + BLUE CHROMA
			PADDSW MM4, MM1					 ; MM4 = LUMA EVEN + BLUE CHROMA
			PADDSW MM6, MM0					 ; MM6 = LUMA ODD + RED CHROMA
			PADDSW MM5, MM1					 ; MM5 = LUMA EVEN + RED CHROMA
			PADDSW MM7, MM0					 ; MM7 = LUMA ODD + GREEN CHROMA
			PADDSW MM2, MM1					 ; MM2 = LUMA EVEN + GREEN CHROMA
			; clipping
			PACKUSWB MM3, MM3
			PACKUSWB MM4, MM4
			PACKUSWB MM6, MM6
			PACKUSWB MM5, MM5
			PACKUSWB MM7, MM7
			PACKUSWB MM2, MM2
			; interleave odd and even parts
			PUNPCKLBW MM4, MM3			 ; MM4 = B7B6B5B4B3B2B1B0 BLUE
			PUNPCKLBW MM5, MM6			 ; MM5 = R7R6R5R4R3R2R1R0 RED
			PUNPCKLBW MM2, MM7			 ; MM2 = G7G6G5G4G3G2G1G0 GREEN

			; mask not needed bits (using 555)
;			PAND MM4, mask5
;			PAND MM5, mask5
;			PAND MM2, mask5
			PAND MM4, 88[ESI]
			PAND MM5, 88[ESI]
			PAND MM2, 96[ESI]

			; mix colors and write

			PSRLW MM4, 3						 	; MM4 = RED SHIFTED
;			PAND MM4, maskBlue			 	; MASK THE BLUE AGAIN
			PAND MM4, 104[ESI]			 	; MASK THE BLUE AGAIN
			PXOR MM7, MM7						 ; ZERO MM7
			MOVQ MM1, MM5						 ; MM1 = COPY BLUE
			MOVQ MM3, MM4						 ; MM3 = COPY RED
			MOVQ MM6, MM2						 ; MM6 = COPY GREEN

			PUNPCKHBW MM1, MM7
			PUNPCKHBW MM3, MM7
			PUNPCKHBW MM6, MM7
			PSLLW MM6, 3						 	; SHIFT GREEN
			PSLLW MM1, 8						 	; SHIFT BLUE
			POR MM6, MM3
			POR MM6, MM1
			MOVQ 8[EAX], MM6

			PUNPCKLBW MM2, MM7			 ; MM2 = __G3__G2__G1__G0 ALREADY MASKED
			PUNPCKLBW MM4, MM7
			PUNPCKLBW MM5, MM7
			PSLLW MM2, 3						 	; SHIFT GREEN
			PSLLW MM5, 8						 	; SHIFT BLUE
			POR MM2, MM4
			POR MM2, MM5
			MOVQ [EAX], MM2
			ADD EBX, 8               				; PUCY   += 8;
			ADD ECX, 4               				; PUCU   += 4;
			ADD EDX, 4               				; PUCV   += 4;
			ADD EAX, 16              				; PUCOUT += 16 // WROTE 16 BYTES

			INC EDI
			JNE horizLoop

			EMMS	
		END ScanLine565MMX;

		(* Convert picture from YUV -> RGB 565 *)
		PROCEDURE ConvertYUVToRGB565(
			puc: PointerToArrayOfCHAR; 
			pucYBaseOffset: LONGINT; 
			strideY: LONGINT; 
			pucUBaseOffset, pucVBaseOffset, strideUV: LONGINT; 
			pucOut: Raster.Image; 
			widthY, heightY, strideOut: LONGINT );
		VAR
			xCount, yCount, strideDiff: LONGINT;
			pusOut: LONGINT;
			r, g, b: LONGINT;
			y, u, v: LONGINT;
			
		BEGIN
			strideDiff := (strideOut - widthY)*SIZE(INTEGER); (* expressed in bytes *)

			IF heightY < 0 THEN
				(* we are flipping our output upside-down *)
				heightY  := -heightY;
				pucYBaseOffset := pucYBaseOffset + ( heightY - 1 ) * strideY ;
				pucUBaseOffset := pucUBaseOffset + ( heightY DIV 2 - 1 ) * strideUV;
				pucVBaseOffset := pucVBaseOffset + ( heightY DIV 2 - 1 ) * strideUV;
				strideY  := -strideY;
				strideUV := -strideUV;
			END;

			pusOut := pucOut.adr;
			pucYBaseOffset := SYSTEM.ADR( puc[0] )+ pucYBaseOffset;
			pucUBaseOffset := SYSTEM.ADR ( puc[0] ) + pucUBaseOffset;
			pucVBaseOffset := SYSTEM.ADR( puc[0] ) + pucVBaseOffset;


			FOR yCount := 0 TO heightY - 1 DO  
				FOR xCount := 0 TO  widthY - 1 DO

					y := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( pucYBaseOffset + xCount ) ) ) - 16;
					u := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( pucUBaseOffset + ( xCount DIV 2 ) ) ) ) - 128;
					v := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( pucVBaseOffset + ( xCount DIV 2 ) ) ) ) - 128;
					
					r := ( 2568H*y + 3343H*u ) DIV 2000H;
					g := ( 2568H*y - 0C92H*v - 1A1EH*u ) DIV 2000H;
					b := ( 2568H*y + 40CFH*v ) DIV 2000H;
					
					IF r > 255 THEN r := 255; ELSIF r < 0 THEN r := 0 END;
					IF g > 255 THEN g := 255; ELSIF g < 0 THEN g := 0 END;
					IF b > 255 THEN b := 255; ELSIF b < 0 THEN b := 0 END;
					
					SYSTEM.PUT16( pusOut,  SYSTEM.VAL( INTEGER, SYSTEM.VAL( SET, r DIV 8 ) + SYSTEM.VAL( SET, ( g DIV 4 ) * 32 ) + 
																SYSTEM.VAL( SET, (b DIV 8 ) * 2048 ) ) );

					pusOut := pusOut + SIZE( INTEGER );
				END;
				
				pucYBaseOffset := pucYBaseOffset + strideY;
				IF yCount MOD 2 > 0 THEN 
					pucUBaseOffset := pucUBaseOffset + strideUV;
					pucVBaseOffset := pucVBaseOffset + strideUV
				END;
				pusOut := pusOut + strideDiff;
			END;
		END ConvertYUVToRGB565;
	
		(* Convert YUV -> RGB 888 *)
		PROCEDURE ConvertYUVToRGB888(
			puc: PointerToArrayOfCHAR; 
			pucYBaseOffset: LONGINT; 
			strideY: LONGINT; 
			pucUBaseOffset, pucVBaseOffset, strideUV: LONGINT; 
			pucOut: Raster.Image; 
			widthY, heightY, strideOut: LONGINT );
		VAR
			xCount, yCount, strideDiff: LONGINT;
			pusOut: LONGINT;
			r, g, b: LONGINT;
			y, u, v: LONGINT;
		BEGIN
			strideDiff := (strideOut - widthY)*3; (* expressed in bytes *)

			IF heightY < 0 THEN
				(* we are flipping our output upside-down *)
				heightY  := -heightY;
				pucYBaseOffset := pucYBaseOffset + ( heightY - 1 ) * strideY ;
				pucUBaseOffset := pucUBaseOffset + ( heightY DIV 2 - 1 ) * strideUV;
				pucVBaseOffset := pucVBaseOffset + ( heightY DIV 2 - 1 ) * strideUV;
				strideY  := -strideY;
				strideUV := -strideUV;
			END;
			
			pusOut := pucOut.adr;
			pucYBaseOffset := SYSTEM.ADR( puc[0] )+ pucYBaseOffset;
			pucUBaseOffset := SYSTEM.ADR ( puc[0] ) + pucUBaseOffset;
			pucVBaseOffset := SYSTEM.ADR( puc[0] ) + pucVBaseOffset;

			FOR yCount := 0 TO heightY - 1 DO  
				FOR xCount := 0 TO  widthY - 1 DO

					y := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( pucYBaseOffset + xCount ) ) ) - 16;
					u := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( pucUBaseOffset + ( xCount DIV 2 ) ) ) ) - 128;
					v := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( pucVBaseOffset + ( xCount DIV 2 ) ) ) ) - 128;
					
					r := ( 2568H*y + 3343H*u ) DIV 2000H;
					g := ( 2568H*y - 0C92H*v - 1A1EH*u ) DIV 2000H;
					b := ( 2568H*y + 40CFH*v ) DIV 2000H;
					
					IF r > 255 THEN r := 255; ELSIF r < 0 THEN r := 0 END;
					IF g > 255 THEN g := 255; ELSIF g < 0 THEN g := 0 END;
					IF b > 255 THEN b := 255; ELSIF b < 0 THEN b := 0 END;
					
					SYSTEM.PUT8( pusOut, r );
					INC( pusOut );
					SYSTEM.PUT8( pusOut, g );
					INC( pusOut );
					SYSTEM.PUT8( pusOut, b );
					INC( pusOut );
				END;
				
				pucYBaseOffset := pucYBaseOffset + strideY;
				IF yCount MOD 2 > 0 THEN 
					pucUBaseOffset := pucUBaseOffset + strideUV;
					pucVBaseOffset := pucVBaseOffset + strideUV;
				END;
				pusOut := pusOut + strideDiff;
			END;
		END ConvertYUVToRGB888;		
	END ColorSpace;

	
	(* Procedures to clear, copy and interpolate blocks *)
	(* TransferIDCT* is copied from the DivXPlayer *)
	BlockActions* = OBJECT
		(* clear an 8x8 CHAR block *)
		PROCEDURE ClearBlock*(dest: PointerToArrayOfCHAR; destOffs, incr: LONGINT);
		VAR
			d: LONGINT;		(* current address *)
			i: LONGINT;			(* loop var *)

		BEGIN
			d := SYSTEM.ADR(dest[destOffs]);
			
			FOR i := 0 TO 7 DO
				SYSTEM.PUT32(d, 0);			(* wipes 4 CHARs each time *)
				SYSTEM.PUT32(d + 4, 0);		(* wipes 4 CHARs each time *)
				INC(d, incr);
			END;
		END ClearBlock;
		
		(* clear an 8x8 LONGINT array *)
		PROCEDURE ClearBlockLongint*(block: PointerToArrayOfLONGINT);
		BEGIN
			IF EnableMMX THEN
				ClearBlockMMX(SYSTEM.ADR(block[0]));
			ELSE
				ClearBlockGeneric(block);
			END;
		END ClearBlockLongint;
		
		(* Reset block to 0 *)
		PROCEDURE ClearBlockGeneric(block: PointerToArrayOfLONGINT );
		VAR
			i: LONGINT;
			adr: LONGINT;
		BEGIN
			adr := SYSTEM.ADR( block[0] );
	
			FOR i := 0 TO 63 DO
				SYSTEM.PUT32( adr, 0 );
				INC(adr, SIZE(LONGINT));
			END;
		END ClearBlockGeneric;
	
		PROCEDURE ClearBlockMMX(dst: LONGINT);
		CODE{ SYSTEM.MMX, SYSTEM.PentiumPro }
			MOV		EDX, -32			; clear loop counter
			MOV		ESI, dst[EBP]		; capture block address
	
			PXOR  MM0, MM0				; mm0 = 0
		loop:
			MOVQ	[ESI], MM0				; clear memory location
			ADD		ESI, 8
			INC		EDX
			JNZ		loop
			EMMS
		END ClearBlockMMX;
		
		PROCEDURE CopyBlock*(src, dest: PointerToArrayOfCHAR; srcOffs, destOffs, srcIncr, destIncr, lines: LONGINT);
		VAR
			s, d: LONGINT;		(* current addresses *)
			i: LONGINT;			(* loop var *)
			
		BEGIN
			s := SYSTEM.ADR(src[srcOffs]);
			d := SYSTEM.ADR(dest[destOffs]);
			
			FOR i := 0 TO (lines-1) DO
				SYSTEM.MOVE(s, d, 8);
				INC(s, srcIncr);
				INC(d, destIncr);
			END;
		END CopyBlock;
		
		(* move a block by overwriting the destination, motion vectors in half pel precision *)
		PROCEDURE MoveBlockOverwrite*(src, dest: PointerToArrayOfCHAR; destOffs, mvX, mvY, srcIncr, destIncr, lines: LONGINT);
		VAR
			buffer: ARRAY 16 OF CHAR;		(* temporary buffer *)
			bufadr: LONGINT;				(* address of buffer *)
			index: LONGINT;				(* position in buffer *)
			i, j: LONGINT;					(* loop vars *)
			s, d: LONGINT;					(* addresses of src and dest *)
			tmp1, tmp2: LONGINT;			(* temporary var *)
			
		BEGIN
			s := SYSTEM.ADR(src[destOffs])+ (mvY DIV 2)*destIncr + (mvX DIV 2);
			d := SYSTEM.ADR(dest[destOffs]);

			IF (mvX MOD 2) = 0 THEN
				IF (mvY MOD 2) = 0 THEN
					(* simple copy, no interpolation *)
					CopyBlock(src, dest, destOffs + (mvY DIV 2)*destIncr + (mvX DIV 2), destOffs, srcIncr, destIncr, lines);
				ELSE
					(* vertical interpolation only *)
					bufadr := SYSTEM.ADR(buffer[0]);
					
					SYSTEM.MOVE(s, bufadr, 8);
					INC(s, srcIncr);
					
					FOR i := 0 TO (lines-1) DO
						SYSTEM.MOVE(s, bufadr+8-index, 8);
						FOR j := 0 TO 7 DO
							SYSTEM.PUT8(d+j,
								(ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr + index + j))) + 
								ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr + 8 - index + j)))) DIV 2);
						END;
						index := 8 - index;
						INC(s, srcIncr);
						INC(d, destIncr);
					END;
				END;
			ELSE
				IF (mvY MOD 2) = 0 THEN
					(* horizontal interpolation only *)
					bufadr := SYSTEM.ADR(buffer[0]);
					
					FOR i := 0 TO (lines-1) DO
						SYSTEM.MOVE(s+1, bufadr, 8);
						tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(s)));
						FOR j := 0 TO 7 DO
							tmp1 := tmp2;
							tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr+j)));
							SYSTEM.PUT8(d+j, (tmp1 + tmp2) DIV 2);
						END;
						INC(s, srcIncr);
						INC(d, destIncr);
					END;
				ELSE
					(* vertical and horizontal interpolation *)
					bufadr := SYSTEM.ADR(buffer[0]);
					
					(* setup *)
					SYSTEM.MOVE(s+1, bufadr, 8);
					tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(s)));
					FOR j := 0 TO 7 DO
						tmp1 := tmp2;
						tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr+j)));
						SYSTEM.PUT8(bufadr+j, (tmp1 + tmp2) DIV 2);
					END;
					INC(s, srcIncr);
					
					FOR i := 0 TO (lines-1) DO
						(* part 1: horizontal interpolation *)
						SYSTEM.MOVE(s+1, bufadr+8-index, 8);
						tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(s)));
						FOR j := 0 TO 7 DO
							tmp1 := tmp2;
							tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr+8-index+j)));
							SYSTEM.PUT8(bufadr+8-index+j, (tmp1 + tmp2) DIV 2);
						END;
						
						(* part 2: vertical interpolation *)
						FOR j := 0 TO 7 DO
							SYSTEM.PUT8(bufadr+index+j,
								(ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr + index + j))) + 
								ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr + 8 - index + j)))) DIV 2);
						END;
						SYSTEM.MOVE(bufadr+index, d, 8);
						index := 8 - index;						
						
						INC(s, srcIncr);
						INC(d, destIncr);
					END;
				END;
			END;
		END MoveBlockOverwrite;
		
		(* move a block by interpolating (sum DIV 2) with the destination, motion vectors in half pel precision *)
		PROCEDURE MoveBlockInterp*(src, dest: PointerToArrayOfCHAR; destOffs, mvX, mvY, srcIncr, destIncr, lines: LONGINT);
		VAR
			buffer: ARRAY 16 OF CHAR;		(* temporary buffer *)
			bufadr: LONGINT;				(* address of buffer *)
			index: LONGINT;				(* position in buffer *)
			i, j: LONGINT;					(* loop vars *)
			s, d: LONGINT;					(* addresses of src and dest *)
			tmp1, tmp2: LONGINT;			(* temporary var *)
			
		BEGIN
			s := SYSTEM.ADR(src[destOffs])+ (mvY DIV 2)*destIncr + (mvX DIV 2);
			d := SYSTEM.ADR(dest[destOffs]);

			IF (mvX MOD 2) = 0 THEN
				IF (mvY MOD 2) = 0 THEN
					(* simple copy, no interpolation *)
					FOR i := 0 TO (lines-1) DO
						FOR j := 0 TO 7 DO
							SYSTEM.PUT8(d+j,
								(ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(s+j))) +
								ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(d+j)))) DIV 2);
						END;
						
						INC(s, srcIncr);
						INC(d, destIncr);
					END;
				ELSE
					(* vertical interpolation only *)
					bufadr := SYSTEM.ADR(buffer[0]);
					
					SYSTEM.MOVE(s, bufadr, 8);
					INC(s, srcIncr);
					
					FOR i := 0 TO (lines-1) DO
						SYSTEM.MOVE(s, bufadr+8-index, 8);
						FOR j := 0 TO 7 DO
							tmp1 :=
								(ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr + index + j))) + 
								ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr + 8 - index + j)))) DIV 2;
								
							SYSTEM.PUT8(d+j, (tmp1 + ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(d + j)))) DIV 2);
						END;
						index := 8 - index;
						INC(s, srcIncr);
						INC(d, destIncr);
					END;
				END;
			ELSE
				IF (mvY MOD 2) = 0 THEN
					(* horizontal interpolation only *)
					bufadr := SYSTEM.ADR(buffer[0]);
					
					FOR i := 0 TO (lines-1) DO
						SYSTEM.MOVE(s+1, bufadr, 8);
						tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(s)));
						FOR j := 0 TO 7 DO
							tmp1 := tmp2;
							tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr+j)));
							tmp1 := (tmp1 + tmp2) DIV 2;
							SYSTEM.PUT8(d+j, (tmp1 + ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(d+j)))) DIV 2);
						END;
						INC(s, srcIncr);
						INC(d, destIncr);
					END;
				ELSE
					(* vertical and horizontal interpolation *)
					bufadr := SYSTEM.ADR(buffer[0]);
					
					(* setup *)
					SYSTEM.MOVE(s+1, bufadr, 8);
					tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(s)));
					FOR j := 0 TO 7 DO
						tmp1 := tmp2;
						tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr+j)));
						SYSTEM.PUT8(bufadr+j, (tmp1 + tmp2) DIV 2);
					END;
					INC(s, srcIncr);
						
					FOR i := 0 TO (lines-1) DO
						(* part 1: horizontal interpolation *)
						SYSTEM.MOVE(s+1, bufadr+8-index, 8);
						tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(s)));
						FOR j := 0 TO 7 DO
							tmp1 := tmp2;
							tmp2 := ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr+8-index+j)));
							SYSTEM.PUT8(bufadr+8-index+j, (tmp1 + tmp2) DIV 2);
						END;
						
						(* part 2: vertical interpolation *)
						FOR j := 0 TO 7 DO
							tmp1 :=
								(ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr + index + j))) + 
								ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(bufadr + 8 - index + j)))) DIV 2;
							
							SYSTEM.PUT8(d+j, (tmp1 + ORD(SYSTEM.VAL(CHAR, SYSTEM.GET8(d + j)))) DIV 2);
						END;
						index := 8 - index;						
						
						INC(s, srcIncr);
						INC(d, destIncr);
					END;
				END;
			END;
		END MoveBlockInterp;
		
		PROCEDURE TransferIDCTAdd*( source: PointerToArrayOfLONGINT; dest: PointerToArrayOfCHAR; destOffset, stride: LONGINT );
		BEGIN
			IF EnableMMX THEN
				TransferIDCTAddMMX( SYSTEM.ADR( source[0] ), SYSTEM.ADR( dest[destOffset] ), stride );
			ELSE
				TransferIDCTAddGeneric( source, dest, destOffset, stride );
			END;
		END TransferIDCTAdd;
	
		PROCEDURE TransferIDCTCopy*( source: PointerToArrayOfLONGINT; dest: PointerToArrayOfCHAR; destOffset, stride: LONGINT );
		BEGIN
			IF EnableMMX THEN
				TransferIDCTCopyMMX( SYSTEM.ADR( source[0] ), SYSTEM.ADR( dest[destOffset] ), stride );
			ELSE
				TransferIDCTCopyGeneric( source, dest, destOffset, stride );
			END;
		END TransferIDCTCopy;
	
		(* Add macroblock to a block in the actual picture *)
		PROCEDURE TransferIDCTAddGeneric( source: PointerToArrayOfLONGINT; dest: PointerToArrayOfCHAR; destOffset, stride: LONGINT );
		VAR
			x, y, s, d, sum: LONGINT;
		BEGIN
			stride := stride -  8;
			s := SYSTEM.ADR( source[0] );
			d := SYSTEM.ADR( dest[destOffset] ); 
			
			FOR y := 0 TO 7 DO
				FOR x := 0 TO 7 DO
	
					sum := ORD( SYSTEM.VAL(CHAR, SYSTEM.GET8( d ) ) ) + SYSTEM.GET32( s );
					IF sum > 255 THEN
						SYSTEM.PUT8( d, 255 )
					ELSIF sum < 0 THEN
						SYSTEM.PUT8( d, 0 )
					ELSE
						SYSTEM.PUT8( d, sum )
					END;
					s := s + SIZE( LONGINT );
					d := d + SIZE( CHAR );
					
				END;
				d := d + stride
			END;
		END TransferIDCTAddGeneric;
	
		PROCEDURE TransferIDCTAddMMX( source, dest, stride: LONGINT );
		CODE{ SYSTEM.MMX, SYSTEM.PentiumPro }
			MOV EAX, source[EBP]			;  PARAMETER 1, *SOURCES32
			MOV EBX, dest[EBP]			;  PARAMETER 2, *DESTU8
			MOV EDI, stride[EBP]			;  PARAMETER 3, STRIDE
			MOV EDX, -8					;  loop counter
			PXOR MM7, MM7				;  SET MM7 = 0
			
		loop:
			MOVQ MM0,  [EBX]				;  eight bytes of destination into mm0
			MOVQ MM1,  MM0				;  eight bytes of destination into mm1
			PUNPCKLBW MM0, MM7			;  unpack first 4 bytes from dest into mm0, no saturation
			PUNPCKHBW MM1, MM7		;  unpack next 4 bytes from dest into mm1, no saturation
			MOVQ MM2, [EAX]				;  two source Doublewords into mm2
			PACKSSDW MM2, 8[EAX]		;  pack mm2 with next two source double words into mm2 
			MOVQ MM3, 16[EAX]
			PACKSSDW MM3, 24[EAX]
			PADDSW MM0, MM2			; add source and destination
			PADDSW MM1, MM3			; add source and destination
			PACKUSWB MM0, MM1			; pack mm0 and mm1 into mm0
			MOVQ [EBX], MM0				; copy output to destination
			ADD EBX, EDI					; add +stride to dest ptr
			ADD EAX, 32
			INC EDX
			JNZ loop
			EMMS
		END TransferIDCTAddMMX;

		(* Copy a macroblock to the actual picture *)
		PROCEDURE TransferIDCTCopyGeneric( source: PointerToArrayOfLONGINT; dest: PointerToArrayOfCHAR; destOffset, stride: LONGINT );
		VAR
			x, y, s, d, val: LONGINT;
		BEGIN
			stride := stride - 8;	
			s := SYSTEM.ADR( source[0] );
			d := SYSTEM.ADR( dest[destOffset] ); 
			
			FOR y := 0 TO 7 DO
				FOR x:= 0 TO 7 DO
					val := SYSTEM.GET32( s );
					IF val  > 255 THEN
						SYSTEM.PUT8( d, 255 )
					ELSIF val <  0 THEN
						SYSTEM.PUT8( d, 0 )
					ELSE
						SYSTEM.PUT8( d, val )
					END;
					s := s + SIZE(LONGINT);
					d := d + SIZE( CHAR );
				END;
				d := d + stride
			END;
		END TransferIDCTCopyGeneric;
	
		PROCEDURE TransferIDCTCopyMMX( source, dest, stride: LONGINT );
		CODE{ SYSTEM.MMX, SYSTEM.PentiumPro }
			MOV EAX, source[EBP]			;  PARAMETER 1, *SOURCES32
			MOV EBX, dest[EBP]			;  PARAMETER 2, *DESTU8
			MOV EDI, stride[EBP]			;  PARAMETER 3, STRIDE
			MOV EDX, -8
			
		loop:
			MOVQ MM0,  [EAX]				;  eight bytes (two LONGINT) of source into mm0
			PACKSSDW MM0, 8[EAX]		; Pack next 8 bytes (two LONGINT) together with mm0
			MOVQ MM1, 16[EAX]			
			PACKSSDW MM1, 24[EAX]
			PACKUSWB MM0, MM1			; Pack 4 INTEGER with another 4 INTEGER into mm0
			MOVQ [EBX], MM0				; Write mm0 to dest
			ADD EBX, EDI					; Add stride to dest
			ADD EAX, 32					; next source
			INC EDX
			JNZ loop
			EMMS
		END TransferIDCTCopyMMX;
	END BlockActions;
		
BEGIN
	NEW(IdctBorder, 1024 );
	FOR ii := -512 TO 511 DO
		IF ii < -256 THEN
			IdctBorder[ii + 512] := -256
		ELSIF ii > 255 THEN
			IdctBorder[ii + 512] := 255
		ELSE
			IdctBorder[ii + 512] := ii;
		END;
	END;
END MPEGUtilities.