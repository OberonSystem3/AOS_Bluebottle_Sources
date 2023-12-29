MODULE DivXPlayer;

(* Part of the DivXPlayer *)
(* Written by Thomas Trachsel, ttrachsel@web.de, 18.9.2003 *)
(* Heavily based on the OpenDivX Decoder: www.projectmayo.com *)

IMPORT
	AosFS,AosIO, AosCommands, Raster, WM := WMWindowManager, List := TFClasses, 
	Messages := WMMessages, Rectangles := WMRectangles, AosModules, AosOut, Util := Utilities, SYSTEM,
	Math, Reals, DivXHelper, AVI, DT := DivXTypes, AosKernel, Graphics := WMGraphics;

	TYPE  Done = RECORD
		done: BOOLEAN;
	END;
	
	TYPE PW* =  OBJECT(WM.DoubleBufferWindow)
	VAR
		done*: POINTER TO Done;
		
	PROCEDURE & InitNew(w, h:LONGINT; alpha:BOOLEAN; doneNew: POINTER TO Done);
		BEGIN
			Init^(w, h, alpha);
			manager := WM.GetDefaultManager();
			manager.Add(100, 100, SELF, {WM.FlagFrame});
			openList.Add(SELF);
			done := doneNew;
			ASSERT( done # NIL )
		END InitNew;
		
		(* Overwrite draw procedure because we do not want any interpolation *)
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		BEGIN
			Draw^(canvas, w, h, 0)
		END Draw;

		PROCEDURE Close();
		BEGIN
			Close^;
			openList.Remove(SELF);
			done.done := TRUE
		END Close;
	END PW;

	TYPE MacroBlock *= OBJECT
	VAR
		mp4State: DT.MP4State;
		s: AVI.AVIStream;
		mv: MotionCompensation;
		
		(* Macroblock ModeMap *)
		mbWidth*, mbHeight*: LONGINT;	
		
		DQTab: ARRAY 4 OF LONGINT;
		MCBPCTabIntra: ARRAY 32 OF DT.TabType;
		MCBPCTabInter: ARRAY 256 OF DT.TabType;
		CBPYTab: ARRAY 48 OF DT.TabType;
		
		log:AosIO.Writer;
		texture: DivXHelper.TextureDecoding;
						
	PROCEDURE &init( state: DT.MP4State;  reader: AVI.AVIStream; logWriter: AosIO.Writer  );
	VAR
		i: LONGINT;
	BEGIN
		log := logWriter;
		mp4State := state;
		s := reader;
		NEW( mv, state, s, log );
		NEW( texture, mp4State, s, log );
		
		mbWidth := mp4State.horizontalSize DIV 16;
		mbHeight := mp4State.verticalSize DIV 16;
		
		DQTab[0] := -1; DQTab[1] := -2; DQTab[2] := 1; DQTab[3] := 2;
		
		MCBPCTabIntra[0].val := -1; MCBPCTabIntra[0].len := 0; 	MCBPCTabIntra[1].val := 20; MCBPCTabIntra[1].len := 6;
		MCBPCTabIntra[2].val := 36; MCBPCTabIntra[2].len := 6; 	MCBPCTabIntra[3].val := 52; MCBPCTabIntra[3].len := 6;
		MCBPCTabIntra[4].val := 4; MCBPCTabIntra[4].len := 4; 	MCBPCTabIntra[5].val := 4; MCBPCTabIntra[5].len := 4;
		MCBPCTabIntra[6].val := 4; MCBPCTabIntra[6].len := 4; 	MCBPCTabIntra[7].val := 4; MCBPCTabIntra[7].len := 4;
		MCBPCTabIntra[8].val := 19; MCBPCTabIntra[8].len := 3; 	MCBPCTabIntra[9].val := 19; MCBPCTabIntra[9].len := 3;
		MCBPCTabIntra[10].val := 19; MCBPCTabIntra[10].len := 3; 	MCBPCTabIntra[11].val := 19; MCBPCTabIntra[11].len := 3;
		MCBPCTabIntra[12].val := 19; MCBPCTabIntra[12].len := 3; 	MCBPCTabIntra[13].val := 19; MCBPCTabIntra[13].len := 3;
		MCBPCTabIntra[14].val := 19; MCBPCTabIntra[14].len := 3; 	MCBPCTabIntra[15].val := 19; MCBPCTabIntra[15].len := 3;
		MCBPCTabIntra[16].val := 35; MCBPCTabIntra[16].len := 3; 	MCBPCTabIntra[17].val := 35; MCBPCTabIntra[17].len := 3; 
		MCBPCTabIntra[18].val := 35; MCBPCTabIntra[18].len := 3; 	MCBPCTabIntra[19].val := 35; MCBPCTabIntra[19].len := 3; 
		MCBPCTabIntra[20].val := 35; MCBPCTabIntra[20].len := 3; 	MCBPCTabIntra[21].val := 35; MCBPCTabIntra[21].len := 3; 
		MCBPCTabIntra[22].val := 35; MCBPCTabIntra[22].len := 3; 	MCBPCTabIntra[23].val := 35; MCBPCTabIntra[23].len := 3; 
		MCBPCTabIntra[24].val := 51; MCBPCTabIntra[24].len := 3; 	MCBPCTabIntra[25].val := 51; MCBPCTabIntra[25].len := 3; 
		MCBPCTabIntra[26].val := 51; MCBPCTabIntra[26].len := 3; 	MCBPCTabIntra[27].val := 51; MCBPCTabIntra[27].len := 3; 
		MCBPCTabIntra[28].val := 51; MCBPCTabIntra[28].len := 3; 	MCBPCTabIntra[29].val := 51; MCBPCTabIntra[29].len := 3; 
		MCBPCTabIntra[30].val := 51; MCBPCTabIntra[30].len := 3; 	MCBPCTabIntra[31].val := 51; MCBPCTabIntra[31].len := 3; 

		MCBPCTabInter[0].val := -1; MCBPCTabInter[0].len := 0;
		
		MCBPCTabInter[1].val := 255; MCBPCTabInter[1].len := 9;
		MCBPCTabInter[2].val := 52; MCBPCTabInter[2].len := 9;
		MCBPCTabInter[3].val := 36; MCBPCTabInter[3].len := 9;
		MCBPCTabInter[4].val := 20; MCBPCTabInter[4].len := 9;
		MCBPCTabInter[5].val := 49; MCBPCTabInter[5].len := 9;
		MCBPCTabInter[6].val := 35; MCBPCTabInter[6].len := 8;
		MCBPCTabInter[7].val := 35; MCBPCTabInter[7].len := 8;
		MCBPCTabInter[8].val := 19; MCBPCTabInter[8].len := 8;
		MCBPCTabInter[9].val := 19; MCBPCTabInter[9].len := 8;

		MCBPCTabInter[10].val := 50; MCBPCTabInter[10].len := 8;
		MCBPCTabInter[11].val := 50; MCBPCTabInter[11].len := 8;
		MCBPCTabInter[12].val := 51; MCBPCTabInter[12].len := 7;
		MCBPCTabInter[13].val := 51; MCBPCTabInter[13].len := 7;
		MCBPCTabInter[14].val := 51; MCBPCTabInter[14].len := 7;
		MCBPCTabInter[15].val := 51; MCBPCTabInter[15].len := 7;
		MCBPCTabInter[16].val := 34; MCBPCTabInter[16].len := 7;
		MCBPCTabInter[17].val := 34; MCBPCTabInter[17].len := 7;
		MCBPCTabInter[18].val := 34; MCBPCTabInter[18].len := 7;
		
		MCBPCTabInter[19].val := 34; MCBPCTabInter[19].len := 7;
		MCBPCTabInter[20].val := 18; MCBPCTabInter[20].len := 7;
		MCBPCTabInter[21].val := 18; MCBPCTabInter[21].len := 7;
		MCBPCTabInter[22].val := 18; MCBPCTabInter[22].len := 7;
		MCBPCTabInter[23].val := 18; MCBPCTabInter[23].len := 7;
		MCBPCTabInter[24].val := 33; MCBPCTabInter[24].len := 7;
		MCBPCTabInter[25].val := 33; MCBPCTabInter[25].len := 7;
		MCBPCTabInter[26].val := 33; MCBPCTabInter[26].len := 7;
		MCBPCTabInter[27].val := 33; MCBPCTabInter[27].len := 7;
		
		MCBPCTabInter[28].val := 17; MCBPCTabInter[28].len := 7;
		MCBPCTabInter[29].val := 17; MCBPCTabInter[29].len := 7;
		MCBPCTabInter[30].val := 17; MCBPCTabInter[30].len := 7;
		MCBPCTabInter[31].val := 17; MCBPCTabInter[31].len := 7;
		MCBPCTabInter[32].val := 4; MCBPCTabInter[32].len := 6;
		MCBPCTabInter[33].val := 4; MCBPCTabInter[33].len := 6;
		MCBPCTabInter[34].val := 4; MCBPCTabInter[34].len := 6;
		MCBPCTabInter[35].val := 4; MCBPCTabInter[35].len := 6;
		MCBPCTabInter[36].val := 4; MCBPCTabInter[36].len := 6;
		
		MCBPCTabInter[37].val := 4; MCBPCTabInter[37].len := 6;
		MCBPCTabInter[38].val := 4; MCBPCTabInter[38].len := 6;
		MCBPCTabInter[39].val := 4; MCBPCTabInter[39].len := 6;
		MCBPCTabInter[40].val := 48; MCBPCTabInter[40].len := 6;
		MCBPCTabInter[41].val := 48; MCBPCTabInter[41].len := 6;
		MCBPCTabInter[42].val := 48; MCBPCTabInter[42].len := 6;
		MCBPCTabInter[43].val := 48; MCBPCTabInter[43].len := 6;
		MCBPCTabInter[44].val := 48; MCBPCTabInter[44].len := 6;
		MCBPCTabInter[45].val := 48; MCBPCTabInter[45].len := 6;

		MCBPCTabInter[46].val := 48; MCBPCTabInter[46].len := 6;
		MCBPCTabInter[47].val := 48; MCBPCTabInter[47].len := 6;

		FOR i := 48 TO 63 DO MCBPCTabInter[i].val := 3; MCBPCTabInter[i].len := 5 END;
		FOR i := 64 TO 95 DO MCBPCTabInter[i].val := 32; MCBPCTabInter[i].len := 4 END;
		FOR i := 96 TO 127 DO MCBPCTabInter[i].val := 16; MCBPCTabInter[i].len := 4 END;
		FOR i := 128 TO 191 DO MCBPCTabInter[i].val := 2; MCBPCTabInter[i].len := 3 END;
		FOR i := 192 TO 255 DO MCBPCTabInter[i].val := 1; MCBPCTabInter[i].len := 3 END;
		
		CBPYTab[0].val := -1; CBPYTab[0].len := 0; 
		CBPYTab[1].val := -1; CBPYTab[1].len := 0; 
		CBPYTab[2].val := 6; CBPYTab[2].len := 6; 
		CBPYTab[3].val := 9; CBPYTab[3].len := 6; 
		CBPYTab[4].val := 8; CBPYTab[4].len := 5; 
		CBPYTab[5].val := 8; CBPYTab[5].len := 5; 
		CBPYTab[6].val := 4; CBPYTab[6].len := 5; 
		CBPYTab[7].val := 4; CBPYTab[7].len := 5;
		
		CBPYTab[8].val := 2; CBPYTab[8].len := 5; 
		CBPYTab[9].val := 2; CBPYTab[9].len := 5; 
		CBPYTab[10].val := 1; CBPYTab[10].len := 5; 
		CBPYTab[11].val := 1; CBPYTab[11].len := 5; 
		CBPYTab[12].val := 0; CBPYTab[12].len := 4; 
		CBPYTab[13].val := 0; CBPYTab[13].len := 4; 
		CBPYTab[14].val := 0; CBPYTab[14].len := 4; 
		CBPYTab[15].val := 0; CBPYTab[15].len := 4; 
		
		CBPYTab[16].val := 12; CBPYTab[16].len := 4; 
		CBPYTab[17].val := 12; CBPYTab[17].len := 4; 
		CBPYTab[18].val := 12; CBPYTab[18].len := 4; 
		CBPYTab[19].val := 12; CBPYTab[19].len := 4; 
		CBPYTab[20].val := 10; CBPYTab[20].len := 4; 
		CBPYTab[21].val := 10; CBPYTab[21].len := 4; 
		CBPYTab[22].val := 10; CBPYTab[22].len := 4; 
		CBPYTab[23].val := 10; CBPYTab[23].len := 4; 
	
		CBPYTab[24].val := 14; CBPYTab[24].len := 4; 
		CBPYTab[25].val := 14; CBPYTab[25].len := 4; 
		CBPYTab[26].val := 14; CBPYTab[26].len := 4; 
		CBPYTab[27].val := 14; CBPYTab[27].len := 4; 
		CBPYTab[28].val := 5; CBPYTab[28].len := 4; 
		CBPYTab[29].val := 5; CBPYTab[29].len := 4; 
		CBPYTab[30].val := 5; CBPYTab[30].len := 4; 
		CBPYTab[31].val := 5; CBPYTab[31].len := 4; 
		
		CBPYTab[32].val := 13; CBPYTab[32].len := 4; 
		CBPYTab[33].val := 13; CBPYTab[33].len := 4; 
		CBPYTab[34].val := 13; CBPYTab[34].len := 4; 
		CBPYTab[35].val := 13; CBPYTab[35].len := 4; 
		CBPYTab[36].val := 3; CBPYTab[36].len := 4; 
		CBPYTab[37].val := 3; CBPYTab[37].len := 4; 
		CBPYTab[38].val := 3; CBPYTab[38].len := 4; 
		CBPYTab[39].val := 3; CBPYTab[39].len := 4;
		
		CBPYTab[40].val := 11; CBPYTab[40].len := 4; 
		CBPYTab[41].val := 11; CBPYTab[41].len := 4; 
		CBPYTab[42].val := 11; CBPYTab[42].len := 4; 
		CBPYTab[43].val := 11; CBPYTab[43].len := 4; 
		CBPYTab[44].val := 7; CBPYTab[44].len := 4; 
		CBPYTab[45].val := 7; CBPYTab[45].len := 4; 
		CBPYTab[46].val := 7; CBPYTab[46].len := 4; 
		CBPYTab[47].val := 7; CBPYTab[47].len := 4
	END init;
	
	(* Decode next macroblock *)
	PROCEDURE Decode(): BOOLEAN;
	VAR
		j, temp: LONGINT;
		intraFlag,interFlag, res, coded: BOOLEAN;
	BEGIN
		IF mp4State.hdr.predictionType # DT.IVOP THEN
			mp4State.hdr.notCoded := s.GetBits(1)
		END;
		
		IF DT.Debug THEN
			log.String("Macroblock: "); log.Int( mp4State.hdr.mba, 0 ); log.Ln();
		END;
		
		(* coded macroblock or I-VOP *)
		IF ( mp4State.hdr.notCoded = 0 ) OR ( mp4State.hdr.predictionType = DT.IVOP ) THEN
			mp4State.hdr.mcbpc := GetMCBPC(); 	(* mcbpc *)
			mp4State.hdr.derivedMbType := mp4State.hdr.mcbpc MOD 8;
			mp4State.hdr.cbpc := ( mp4State.hdr.mcbpc DIV 16 ) MOD 4;

			(* Used only in P-VOP *)
			mp4State.modeMap[mp4State.hdr.mbYPos + 1][mp4State.hdr.mbXPos + 1] := mp4State.hdr.derivedMbType;
			IF ( mp4State.hdr.derivedMbType = DT.Intra ) OR ( mp4State.hdr.derivedMbType = DT.IntraQ ) THEN
				intraFlag := TRUE
			ELSE
				intraFlag := FALSE
			END;
			
			interFlag := ~intraFlag;

			IF intraFlag THEN
				mp4State.hdr.acPredFlag := s.GetBits( 1 )
			END;
			
			 IF mp4State.hdr.derivedMbType # DT.Stuffing THEN
				mp4State.hdr.cbpy := GetCBPY(); (* cbpy *)
				mp4State.hdr.cbp := SYSTEM.VAL( LONGINT, SYSTEM.VAL( SET, ( mp4State.hdr.cbpy * 4 ) ) + 
					SYSTEM.VAL( SET, mp4State.hdr.cbpc ) );
			ELSE
				RETURN FALSE
			END;
			
			IF DT.Debug THEN
				log.String( "Mb type: " ); log.Int( mp4State.hdr.derivedMbType, 0 ); log.Ln();	
				log.String( "Pattern Chr: " ); log.Int( mp4State.hdr.cbpc, 0 ); log.Ln();
				log.String( "Pattern Luma: " ); log.Int( mp4State.hdr.cbpy, 0 ); log.Ln()
			END;
			
			IF ( mp4State.hdr.derivedMbType = DT.InterQ ) OR ( mp4State.hdr.derivedMbType = DT.IntraQ ) THEN
				mp4State.hdr.dQuant := s.GetBits(2);
				mp4State.hdr.quantizer := mp4State.hdr.quantizer + DQTab[mp4State.hdr.dQuant];
				IF ( mp4State.hdr.quantizer > 31 ) THEN
					mp4State.hdr.quantizer := 31
				ELSIF mp4State.hdr.quantizer < 1 THEN
					mp4State.hdr.quantizer := 1
				END;
			END;
			
			(* Set MotionVector *)
			IF ( mp4State.hdr.derivedMbType = DT.Inter ) OR ( mp4State.hdr.derivedMbType = DT.InterQ ) THEN 
				res := mv.SetMV( -1 )
			ELSIF mp4State.hdr.derivedMbType = DT.Inter4V THEN
				FOR j := 0 TO 3 DO
					res := mv.SetMV( j )
				END;
			ELSE	(* Intra *)
				IF mp4State.hdr.predictionType = DT.PVOP THEN
					mv.ResetIntraMV(mp4State.hdr.mbYPos + 1, mp4State.hdr.mbXPos + 1 )
				END;
			END;
			
			(* motion compensation *)
			IF interFlag THEN 
				IF DT.Debug THEN
					log.String( "Reconstruct: " ); log.Int( mp4State.hdr.mbXPos, 0 ); log.Char( ' ' ); log.Int( mp4State.hdr.mbYPos, 0 ); 
					log.Char( ' ' ); log.Int( mp4State.hdr.derivedMbType, 0 ); log.Ln()
				END;
				mv.Reconstruct(mp4State.hdr.mbXPos, mp4State.hdr.mbYPos, mp4State.hdr.derivedMbType);

				(* texture decoding add *)
				FOR j := 0 TO 5 DO
					coded := 5 - j IN SYSTEM.VAL(SET, mp4State.hdr.cbp );
					IF coded THEN
						temp := texture.BlockInter( j, coded );
						AddBlockInter(j, mp4State.hdr.mbXPos, mp4State.hdr.mbYPos)
					END;
				END;
			ELSE
				(* texture decoding add *)
				FOR j := 0 TO 5 DO
					coded := 5 - j IN SYSTEM.VAL(SET, mp4State.hdr.cbp );
					temp := texture.BlockIntra( j, coded );
					AddBlockIntra(j, mp4State.hdr.mbXPos, mp4State.hdr.mbYPos)
				END;
			END;
		ELSE (* not coded macroblock *)
			mv.ResetNotCodedMV( mp4State.hdr.mbYPos + 1, mp4State.hdr.mbXPos + 1);
			mp4State.modeMap[mp4State.hdr.mbYPos + 1][mp4State.hdr.mbXPos + 1] := DT.NotCoded;

			IF DT.Debug THEN
				log.String( "Reconstruct: " ); log.Int( mp4State.hdr.mbXPos, 0 ); log.Char( ' ' ); log.Int( mp4State.hdr.mbYPos, 0 ); 
				log.Char( ' ' ); log.Int( mp4State.hdr.derivedMbType, 0 ); log.Ln()
			END;

			mv.Reconstruct(mp4State.hdr.mbXPos, mp4State.hdr.mbYPos, mp4State.hdr.derivedMbType)
		END;

		mp4State.quantStore[mp4State.hdr.mbYPos + 1][mp4State.hdr.mbXPos + 1] := mp4State.hdr.quantizer;

		IF mp4State.hdr.mbXPos < ( mbWidth - 1 ) THEN 
			INC( mp4State.hdr.mbXPos );
		ELSE
			INC( mp4State.hdr.mbYPos );
			mp4State.hdr.mbXPos := 0
		END;
		
	RETURN TRUE;
	END Decode;
	
	(* Add an IntraBlock to the Picture *)
	PROCEDURE AddBlockIntra( comp, bx, by: LONGINT );
	VAR 
		cc, iincr, offset: LONGINT;
	BEGIN
		(* color component index *)
		IF comp < 4 THEN
			cc := 0
		ELSE
			cc := ( comp MOD 2 ) + 1
		END;

		IF ( cc = 0 ) THEN (* luminance *)
			(* pixel coordinates *)
			bx := bx * 16;
			by := by * 16;
	    	
	    	(* frame DCT coding; *) 
			offset := mp4State.frameRefBaseOffset[cc] + 
				( mp4State.codedPictureWidth * ( by + ( ( ( comp MOD 4 ) DIV 2 ) * 8 ) ) + bx + ( ( comp MOD 2 ) * 8 ) );
		    iincr := mp4State.codedPictureWidth
		ELSE	(* chrominance *)
	    	(* pixel coordinates *)
			bx := bx * 8;
			by := by * 8;
			(* frame DCT coding *)
			offset :=  mp4State.frameRefBaseOffset[cc] + mp4State.chromWidth * by + bx;
			iincr := mp4State.chromWidth
		END;
		
	 	IF DT.Debug THEN
 			log.String( "TransferIDCTCopy: "); log.Int( offset - mp4State.frameRefBaseOffset[cc], 0 ); log.Char( ' ' );
 			log.Int( iincr, 0 ); log.Ln()
	 	END;

		TransferIDCTCopy( texture.block, mp4State.frameRef, offset, iincr );
	END AddBlockIntra;
	
	(* Add an interblock to the current picture *)
	PROCEDURE AddBlockInter( comp, bx, by: LONGINT );
	VAR 
		cc, iincr, offset: LONGINT;
		rfp: DT.PointerToArrayOfCHAR;
	BEGIN
		IF comp < 4 THEN 
			cc := 0
		ELSE
			cc := ( comp MOD 2 ) + 1
		END;
		
		IF cc = 0 THEN (* luminance *)
			(* pixel coordinates *)
			bx := bx * 16;
			by := by * 16;
			
			(* frame DCT coding *)
			offset := mp4State.frameRefBaseOffset[cc] 
				+ mp4State.codedPictureWidth * ( by + ( ( ( comp MOD 4 ) DIV 2 ) * 8 ) ) + bx + ( ( comp MOD 2 ) * 8 );
			iincr := mp4State.codedPictureWidth
		ELSE	(* chrominance *)
			(* pixel coordinates *)
			bx := bx * 8;
			by := by * 8;
			(* frame DCT coding *)
			offset := mp4State.frameRefBaseOffset[cc] + mp4State.chromWidth * by + bx;
    		iincr := mp4State.chromWidth
		END;
		
 	IF DT.Debug THEN
 		log.String( "TransferIDCTAdd: "); log.Int( offset - mp4State.frameRefBaseOffset[cc], 0 ); log.Char( ' ' );
 		log.Int( iincr, 0 ); log.Ln()
 	END;
 	TransferIDCTAdd( texture.block, mp4State.frameRef, offset, iincr );
	END AddBlockInter;
	
	PROCEDURE TransferIDCTAdd( source: DT.PointerToArrayOfLONGINT; dest: DT.PointerToArrayOfCHAR; destOffset, stride: LONGINT );
	BEGIN
		IF DT.EnableMMX THEN
			TransferIDCTAddMMX( SYSTEM.ADR( source[0] ), SYSTEM.ADR( dest[destOffset] ), stride );
(*			TransferIDCTAddGeneric( source, dest, destOffset, stride ); *)
		ELSE
			TransferIDCTAddGeneric( source, dest, destOffset, stride );
		END;
	END TransferIDCTAdd;
	
	PROCEDURE TransferIDCTCopy( source: DT.PointerToArrayOfLONGINT; dest: DT.PointerToArrayOfCHAR; 
		destOffset, stride: LONGINT );
	BEGIN
		IF DT.EnableMMX THEN
			TransferIDCTCopyMMX( SYSTEM.ADR( source[0] ), SYSTEM.ADR( dest[destOffset] ), stride );
		ELSE
			TransferIDCTCopyGeneric( source, dest, destOffset, stride );
		END;
	END TransferIDCTCopy;

	(* Add macroblock to a block in the actual picture *)
	PROCEDURE TransferIDCTAddGeneric( source: DT.PointerToArrayOfLONGINT; dest: DT.PointerToArrayOfCHAR;  
		destOffset, stride: LONGINT );
	VAR
		x, y, s, d, sum: LONGINT;
	BEGIN
		stride := stride -  8;
		s := SYSTEM.ADR( source[0] );
		d := SYSTEM.ADR( dest[destOffset] ); 
		
		IF DT.Debug THEN
			log.String( "TransferIDCTAdd: " )
		END;
		
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
				
				IF DT.Debug THEN
					log.Int( ORD( SYSTEM.VAL(CHAR, SYSTEM.GET8( d-1 ) ) ), 0 ); log.Char( ' ' )
				END;

			END;
			d := d + stride
		END;
		
		IF DT.Debug THEN
			log.Ln()
		END;
	END TransferIDCTAddGeneric;
	
	PROCEDURE TransferIDCTAddMMX( source, dest, stride: LONGINT );
	CODE{ SYSTEM.MMX, SYSTEM.PentiumPro }
		MOV EAX, source[EBP]           ;  PARAMETER 1, *SOURCES32
		MOV EBX, dest[EBP]              ;  PARAMETER 2, *DESTU8
		MOV EDI, stride[EBP]              ;  PARAMETER 3, STRIDE
		MOV EDX, -8						; loop counter
		PXOR MM7, MM7                ;  SET MM7 = 0
		
	loop:
		MOVQ MM0,  [EBX]				;  eight bytes of destination into mm0
		MOVQ MM1,  MM0					;  eight bytes of destination into mm1
		PUNPCKLBW MM0, MM7			;  unpack first 4 bytes from dest into mm0, no saturation
		PUNPCKHBW MM1, MM7			;  unpack next 4 bytes from dest into mm1, no saturation
		MOVQ MM2, [EAX]					; two source Doublewords into mm2
		PACKSSDW MM2, 8[EAX]		; pack mm2 with next two source double words into mm2 
		MOVQ MM3, 16[EAX]
		PACKSSDW MM3, 24[EAX]
		PADDSW MM0, MM2				; add source and destination
		PADDSW MM1, MM3				; add source and destination
		PACKUSWB MM0, MM1            ; pack mm0 and mm1 into mm0
		MOVQ [EBX], MM0				; copy output to destination
		ADD EBX, EDI						; add +stride to dest ptr
		ADD EAX, 32
		INC EDX
		JNZ loop
		EMMS
	END TransferIDCTAddMMX;

	(* Copy a macroblock to the actual picture *)
	PROCEDURE TransferIDCTCopyGeneric( source: DT.PointerToArrayOfLONGINT; dest: DT.PointerToArrayOfCHAR; destOffset, stride: LONGINT );
	VAR
		x, y, s, d, val: LONGINT;
	BEGIN
		stride := stride - 8;	
		s := SYSTEM.ADR( source[0] );
		d := SYSTEM.ADR( dest[destOffset] ); 
		
		IF DT.Debug THEN
			log.String( "Transferp: " )
		END;
		
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
			
				IF DT.Debug THEN
					log.Int( ORD( SYSTEM.VAL(CHAR, SYSTEM.GET8( d -1) ) ), 0 ); log.Char( ' ' )
				END;

			END;
			d := d + stride
		END;

		IF DT.Debug THEN
			log.Ln()
		END;
	END TransferIDCTCopyGeneric;
	
	PROCEDURE TransferIDCTCopyMMX( source, dest, stride: LONGINT );
	CODE{ SYSTEM.MMX, SYSTEM.PentiumPro }
		MOV EAX, source[EBP]           ;  PARAMETER 1, *SOURCES32
		MOV EBX, dest[EBP]              ;  PARAMETER 2, *DESTU8
		MOV EDI, stride[EBP]              ;  PARAMETER 3, STRIDE
		MOV EDX, -8
		
	loop:
		MOVQ MM0,  [EAX]				;  eight bytes (two LONGINT) of source into mm0
		PACKSSDW MM0, 8[EAX]		; Pack next 8 bytes (two LONGINT) together with mm0
		MOVQ MM1, 16[EAX]			
		PACKSSDW MM1, 24[EAX]
		PACKUSWB MM0, MM1			; Pack 4 INTEGER with another 4 INTEGER into mm0
		MOVQ [EBX], MM0				; Write mm0 to dest
		ADD EBX, EDI						; Add stride to dest
		ADD EAX, 32						; next source
		INC EDX
		JNZ loop
		EMMS
	END TransferIDCTCopyMMX;

	
	(* Used to derive macroblock type and pattern for luminance  *)
	PROCEDURE GetCBPY(): LONGINT;
	VAR
		cbpy: LONGINT;
		code: LONGINT;
	BEGIN
		code := s.ShowBits( 6 );	

		IF  code < 2 THEN
			RETURN -1
		END;
			  
		IF code >= 48 THEN
			s.SkipBits( 2 );
			cbpy := 15
		ELSE
			s.SkipBits( CBPYTab[code].len );
			cbpy := CBPYTab[code].val
		END;

		IF ( ~( (mp4State.hdr.derivedMbType = 3 ) OR ( mp4State.hdr.derivedMbType = 4 ) ) ) THEN
			  cbpy := 15 - cbpy
		END;

  	RETURN cbpy;
	END GetCBPY;
	
	(* Used to derive macroblock type and pattern for chrominance *)
	PROCEDURE GetMCBPC(): LONGINT;
	VAR
		code: LONGINT;
	BEGIN
		IF mp4State.hdr.predictionType = DT.IVOP THEN
			code := s.ShowBits( 9 );

			IF code = 1 THEN
				s.SkipBits( 9 );  (* stuffing *)
				RETURN 0
			ELSIF code < 8 THEN
				RETURN -1
			END;

			code := code DIV 8;
			IF code >= 32 THEN
				s.SkipBits( 1 );
				RETURN 3
			END;
		
			s.SkipBits( MCBPCTabIntra[code].len );
			RETURN MCBPCTabIntra[code].val
		ELSE
			code := s.ShowBits( 9 );

			IF code = 1 THEN
				s.SkipBits( 9 ); (* stuffing *)
				RETURN 0
			ELSIF code = 0 THEN 
				RETURN -1
			END;
		
			IF code >= 256 THEN
				s.SkipBits( 1 );
				RETURN 0;
			END;
		
			s.SkipBits( MCBPCTabInter[code].len );
			RETURN MCBPCTabInter[code].val
		END;
	END GetMCBPC;
	
	END MacroBlock;

	TYPE MotionCompensation = OBJECT
	VAR
		MVTab0: ARRAY 14 OF DT.TabType;
		MVTab1: ARRAY 96 OF DT.TabType;
		MVTab2: ARRAY 124 OF DT.TabType;
		s: AVI.AVIStream;
		MV: ARRAY 2 OF ARRAY 6 OF ARRAY ( DT.DecMbr+1 ) OF ARRAY ( DT.DecMbc+2 ) OF LONGINT;
		RoundTab: ARRAY 16 OF LONGINT;
		mp4State: DT.MP4State;
		log: AosIO.Writer;
		
	PROCEDURE &init( state: DT.MP4State; stream:AVI. AVIStream; logWriter: AosIO.Writer);
	VAR
		i, j, index: LONGINT;
	BEGIN
		log := logWriter;
		s := stream;
		mp4State := state;
		
		RoundTab[0] := 0; RoundTab[1] := 0; RoundTab[2] := 0; RoundTab[3] := 1;  RoundTab[4] := 1; RoundTab[5] := 1;
		RoundTab[6] := 1; RoundTab[7] := 1; RoundTab[8] := 1; RoundTab[9] := 1; RoundTab[10] := 1; RoundTab[11] := 1;
		RoundTab[12] := 1; RoundTab[13] := 1; RoundTab[14] := 2; RoundTab[15] :=  2;
		
		MVTab0[0].val := 3; MVTab0[0].len := 4;
		MVTab0[1].val := -3; MVTab0[1].len := 4;
		MVTab0[2].val := 2; MVTab0[2].len := 3;
		MVTab0[3].val := 2; MVTab0[3].len := 3;
		MVTab0[4].val := -2; MVTab0[4].len := 3;
		MVTab0[5].val := -2; MVTab0[5].len := 3;
		MVTab0[6].val := 1; MVTab0[6].len := 2;
		MVTab0[7].val := 1; MVTab0[7].len := 2;
		MVTab0[8].val := 1; MVTab0[8].len := 2;
		MVTab0[9].val := 1; MVTab0[9].len := 2;
		MVTab0[10].val := -1; MVTab0[10].len := 2;
		MVTab0[11].val := -1; MVTab0[11].len := 2;
		MVTab0[12].val := -1; MVTab0[12].len := 2;
		MVTab0[13].val := -1; MVTab0[13].len := 2;

		MVTab1[0].val := 12; MVTab1[0].len := 10;
		MVTab1[1].val := -12; MVTab1[1].len := 10;
		MVTab1[2].val := 11; MVTab1[2].len := 10;
		MVTab1[3].val := -11; MVTab1[3].len := 10;
		MVTab1[4].val := 10; MVTab1[4].len := 9;
		MVTab1[5].val := 10; MVTab1[5].len := 9;
		MVTab1[6].val := -10; MVTab1[6].len := 9;
		MVTab1[7].val := -10; MVTab1[7].len := 9;
		MVTab1[8].val := 9; MVTab1[8].len := 9;
		MVTab1[9].val := 9; MVTab1[9].len := 9;
		MVTab1[10].val := -9; MVTab1[10].len := 9;
		MVTab1[11].val := -9; MVTab1[11].len := 9;
		MVTab1[12].val := 8; MVTab1[12].len := 9;
		MVTab1[13].val := 8; MVTab1[13].len := 9;
		MVTab1[14].val := -8; MVTab1[14].len := 9;
		MVTab1[15].val := -8; MVTab1[15].len := 9;
		FOR i := 16 TO 23 DO MVTab1[i].val := 7; MVTab1[i].len := 7 END;
		FOR i := 24 TO 31 DO MVTab1[i].val := -7; MVTab1[i].len := 7 END;
		FOR i := 32 TO 39 DO MVTab1[i].val := 6; MVTab1[i].len := 7 END;
		FOR i := 40 TO 47 DO MVTab1[i].val := -6; MVTab1[i].len := 7 END;
		FOR i := 48 TO 56 DO MVTab1[i].val := 5; MVTab1[i].len := 7 END;
		FOR i := 56 TO 63 DO MVTab1[i].val := -5; MVTab1[i].len := 7 END;
		FOR i := 64 TO 79 DO MVTab1[i].val := 4; MVTab1[i].len := 6 END;
		FOR i := 80 TO 95 DO MVTab1[i].val := -4; MVTab1[i].len := 6 END;
		
		MVTab2[0].val := 32; MVTab2[0].len := 12;
		MVTab2[1].val := -32; MVTab2[1].len := 12;
		MVTab2[2].val := 31; MVTab2[2].len := 12;
		MVTab2[3].val := -31; MVTab2[3].len := 12;
		MVTab2[4].val := 30; MVTab2[4].len := 11;
		MVTab2[5].val := 30; MVTab2[5].len := 11;
		MVTab2[6].val := -30; MVTab2[6].len := 11;
		MVTab2[7].val := -30; MVTab2[7].len := 11;
		MVTab2[8].val := 29; MVTab2[8].len := 11;
		MVTab2[9].val := 29; MVTab2[9].len := 11;
		MVTab2[10].val := -29; MVTab2[10].len := 11;
		MVTab2[11].val := -29; MVTab2[11].len := 11;
		MVTab2[12].val := 28; MVTab2[12].len := 11;
		MVTab2[13].val := 28; MVTab2[13].len := 11;
		MVTab2[14].val := -28; MVTab2[14].len := 11;
		MVTab2[15].val := -28; MVTab2[15].len := 11;
		MVTab2[16].val := 27; MVTab2[16].len := 11;
		MVTab2[17].val := 27; MVTab2[17].len := 11;
		MVTab2[18].val := -27; MVTab2[18].len := 11;
		MVTab2[19].val := -27; MVTab2[19].len := 11;
		MVTab2[20].val := 26; MVTab2[20].len := 11;
		MVTab2[21].val := 26; MVTab2[21].len := 11;
		MVTab2[22].val := -26; MVTab2[22].len := 11;
		MVTab2[23].val := -26; MVTab2[23].len := 11;
		MVTab2[24].val := 25; MVTab2[24].len := 11;
		MVTab2[25].val := 25; MVTab2[25].len := 11;
		MVTab2[26].val := -25; MVTab2[26].len := 11;
		MVTab2[27].val := -25; MVTab2[27].len := 11;
		
		index := 28;
		FOR i:= 24 TO 13 BY -1 DO  
			FOR j := 0 TO 3 DO
				MVTab2[index].val := i; MVTab2[index].len := 10;
				INC( index )
			END;
			FOR j := 0 TO 3 DO
				MVTab2[index].val := -i; MVTab2[index].len := 10;
				INC( index )
			END;
		END;
	END init;
	
	(* compute motion vector prediction *)
	PROCEDURE FindPMV ( block, comp: LONGINT ): LONGINT;
	VAR
	  p1, p2, p3, xin1, xin2, xin3, yin1, yin2, yin3, vec1, vec2, vec3, x, y: LONGINT;
	BEGIN
		x := mp4State.hdr.mbXPos;
		y := mp4State.hdr.mbYPos;
	
		IF ( y = 0 ) & ( ( block = 0 ) OR ( block = 1 ) ) THEN 
			IF (x = 0 ) & (block = 0 ) THEN
				RETURN 0;
			ELSIF ( block = 1 ) THEN
				RETURN MV[comp][0][y + 1][x + 1]
			ELSE (* block == 0 *)
				RETURN MV[comp][1][y + 1][x]
			END;
		ELSE
			(* considerate border (avoid increment inside each single array index) *)
			INC( x );
			INC( y );

			CASE block OF
				0: 
				vec1 := 1;	yin1 := y;		xin1 := x - 1;
				vec2 := 2;	yin2 := y - 1;  xin2 := x;
				vec3 := 2;	yin3 := y - 1;  xin3 := x + 1;
			| 1:
				vec1 := 0;	yin1 := y;		xin1 := x;
				vec2 := 3;	yin2 := y - 1;  xin2 := x;
				vec3 := 2;	yin3 := y - 1;  xin3 := x + 1;
			| 2:
				vec1 := 3;	yin1 := y;		xin1 := x - 1;
				vec2 := 0;	yin2 := y;	    xin2 := x;
				vec3 := 1;	yin3 := y;		xin3 := x;
			ELSE
				vec1 := 2;	yin1 := y;		xin1 := x;
				vec2 := 0;	yin2 := y;		xin2 := x;
				vec3 := 1;	yin3 := y;		xin3 := x;
			END;
			
			p1 := MV[comp][vec1][yin1][xin1];
			p2 := MV[comp][vec2][yin2][xin2];
			p3 := MV[comp][vec3][yin3][xin3];
	
			RETURN Mmin( Mmax( p1, p2 ), Mmin( Mmax( p2, p3 ),Mmax( p1, p3 ) ) )
		END;
	END FindPMV;
	
	PROCEDURE Mmin( a, b: LONGINT ): LONGINT;
	BEGIN
		IF a < b THEN RETURN a ELSE RETURN b END;
	END Mmin;
	
	PROCEDURE Mmax( a, b: LONGINT ): LONGINT;
	BEGIN
		IF a > b THEN RETURN a ELSE RETURN b END;
	END Mmax;
	
	(* Set current motion vector *)
	PROCEDURE SetMV( blockNum: LONGINT ): BOOLEAN;
	VAR
		tempSet: SET;
		horMvData, verMvData, horMvRes, verMvRes, i: LONGINT;
		scaleFac, high, low, range: LONGINT;
		mvdx, mvdy, pmvx, pmvy, mvx, mvy: LONGINT;
		
	BEGIN
		tempSet := { mp4State.hdr.fCodeFor - 1 };
		scaleFac := SYSTEM.VAL( LONGINT, tempSet );
		high := ( 32 * scaleFac ) - 1;
		low := ( ( -32 ) * scaleFac );
		range := ( 64 * scaleFac );
		
		horMvData := GetMVData(); (* mv data *)

		IF ( scaleFac = 1 ) OR ( horMvData = 0 ) THEN
			mvdx := horMvData
		ELSE
			horMvRes := s.GetBits( mp4State.hdr.fCodeFor - 1 ); (* mv residual *)
			mvdx := ( ( ABS( horMvData ) - 1 ) * scaleFac ) + horMvRes + 1;
			IF ( horMvData < 0 ) THEN
				mvdx := -mvdx
			END;
		END;

  	verMvData := GetMVData(); 

		IF ( scaleFac = 1 ) OR ( verMvData = 0 ) THEN
			mvdy := verMvData
		ELSE
			verMvRes := s.GetBits( mp4State.hdr.fCodeFor - 1 );
			mvdy := ( ( ABS( verMvData) - 1 ) * scaleFac ) + verMvRes + 1;
			IF ( verMvData < 0 ) THEN
				mvdy := -mvdy
			END;
		END;

		IF blockNum = -1 THEN
			pmvx := FindPMV( 0, 0 );
			pmvy := FindPMV( 0, 1 );
		ELSE
			pmvx := FindPMV( blockNum, 0 );
			pmvy := FindPMV( blockNum, 1 );
		END;
		
		IF DT.Debug THEN
			log.String("Hor MotV Pred: "); log.Int( pmvx, 0 ); log.Ln();
			log.String("Ver MotV Pred: "); log.Int( pmvy, 0 ); log.Ln();
			log.String("MVD Hor: "); log.Int( mvdx, 0 ); log.Ln();
			log.String("MVD Ver: "); log.Int( mvdy, 0 ); log.Ln()
		END;
		
		mvx := pmvx + mvdx;

		IF mvx < low THEN
			mvx := mvx + range
		END;
		IF  mvx > high THEN
			mvx := mvx - range
		END;

		mvy := pmvy + mvdy;

		IF mvy < low THEN
			mvy := mvy + range
		END;
		IF mvy > high THEN
			mvy := mvy - range
		END;

		(* put [mv_x, mv_y] in MV struct *)
		IF blockNum = -1 THEN
			FOR i := 0 TO 3 DO
				MV[0][i][mp4State.hdr.mbYPos + 1][mp4State.hdr.mbXPos + 1] := mvx;
				MV[1][i][mp4State.hdr.mbYPos + 1][mp4State.hdr.mbXPos + 1] := mvy
			END;
		ELSE
			MV[0][blockNum][mp4State.hdr.mbYPos + 1][mp4State.hdr.mbXPos + 1] := mvx;
			MV[1][blockNum][mp4State.hdr.mbYPos + 1][mp4State.hdr.mbXPos + 1] := mvy
		END;
		
		IF DT.Debug THEN
			log.String("Hor MotV: "); log.Int( mvx, 0 ); log.Ln();
			log.String("Ver MotV: "); log.Int( mvy, 0 ); log.Ln()
		END;	
		
  	RETURN TRUE;
	END SetMV;	
	
	PROCEDURE GetMVData(): LONGINT;
	VAR
		code: LONGINT;
	BEGIN
		IF s.GetBits( 1 ) > 0 THEN 
			RETURN 0; 	(*  hor_mv_data = 0 *)
		END;
	
		code := s.ShowBits( 12 );

		IF code >= 512 THEN
			code := ( code DIV 256 ) - 2;
			s.SkipBits( MVTab0[code].len );
			RETURN MVTab0[code].val;
		END;
	
		IF  code >= 128 THEN
			code := ( code DIV 4 ) - 32;
			s.SkipBits( MVTab1[code].len );
			RETURN MVTab1[code].val;
		END;

		code := code - 4; 
		ASSERT( code >= 0 );

		s.SkipBits( MVTab2[code].len );
		RETURN MVTab2[code].val;	
	END GetMVData;
	
	(* Reset Intra motion vectors *)
	PROCEDURE ResetIntraMV( yPos, xPos: LONGINT );
	VAR
		j: LONGINT;
	BEGIN
		FOR j := 0 TO 3 DO
			MV[0][j][yPos][xPos] := 0;
			MV[1][j][yPos][xPos] := 0
		END;
	END ResetIntraMV;
	
	(* Reset single MV *)
	PROCEDURE ResetNotCodedMV( yPos, xPos: LONGINT );
	BEGIN
				MV[0][0][yPos][xPos] := 0;
			MV[0][1][yPos][xPos] := 0;
			MV[0][2][yPos][xPos] := 0;
			MV[0][3][yPos][xPos] := 0;
			
			MV[1][0][yPos][xPos] := 0;
			MV[1][1][yPos][xPos] := 0;
			MV[1][2][yPos][xPos] := 0;
			MV[1][3][yPos][xPos] := 0
	END ResetNotCodedMV;
	
	(* Reconstruct the current picture ( apply prediction ) *)
	PROCEDURE Reconstruct( bx, by, mode: LONGINT );
	VAR
		w, h, lx, dx, dy, xp, yp, comp, sum, x, y, px, py: LONGINT;
		src: DT.PointerToArrayOfCHAR;
		srcBaseOffset: ARRAY 3 OF LONGINT;
	BEGIN
		x := bx + 1;
		y := by + 1;

		lx := mp4State.codedPictureWidth;

		src := mp4State.frameFor;
		srcBaseOffset[0] := mp4State.frameForBaseOffset[0];
		srcBaseOffset[1] := mp4State.frameForBaseOffset[1];
		srcBaseOffset[2] := mp4State.frameForBaseOffset[2];

		w := 8;
		h := 8;

		(* Luma *)
		px :=  bx * 16;
		py := by * 16;
		IF mode = DT.Inter4V THEN
			FOR comp := 0 TO 3 DO
				dx := MV[0][comp][y][x];
				dy := MV[1][comp][y][x];
				
				xp := px + ( comp MOD 2 ) * 8;
				yp := py + ( ( comp MOD 4 ) DIV 2 ) * 8;
				
				IF DT.Debug THEN
					log.String( "reconComp: src[0] "); log.Int( lx, 0 ); log.Char( ' ' ); log.Int( w, 0 ); log.Char( ' ' ); log.Int( h, 0 ); 
					log.Char( ' ' ); log.Int( xp, 0 ); log.Char( ' ' ); log.Int( yp, 0 ); log.Char( ' ' ); log.Int( dx, 0 ); log.Char( ' ' ); log.Int( dy, 0 ); 
					log.Char( ' ' ); log.Int( 0, 0 ); log.Ln()
				END;
				
				ReconComp (src, srcBaseOffset[0],  mp4State.frameRef, mp4State.frameRefBaseOffset[0], lx, w, h, xp, yp, dx, dy, 0);
			END;
		ELSE
			dx := MV[0][0][y][x];
			dy := MV[1][0][y][x];

			IF DT.Debug THEN
				log.String( "reconComp: src[0] "); log.Int( lx, 0 ); log.Char( ' ' ); log.Int( w, 0 ); log.Char( ' ' ); log.Int( h, 0 ); 
				log.Char( ' ' ); log.Int( px, 0 ); log.Char( ' ' ); log.Int( py, 0 ); log.Char( ' ' ); log.Int( dx, 0 ); log.Char( ' ' ); log.Int( dy, 0 ); 
				log.Char( ' ' ); log.Int( 0, 0 ); log.Ln()
			END;
			
			ReconComp (src, srcBaseOffset[0], mp4State.frameRef, mp4State.frameRefBaseOffset[0], lx, w*2, h*2, px, py, dx, dy, 0);
		END;
	
		(* Chr *)
		px := bx*8;
		py := by*8;
		IF mode = DT.Inter4V THEN
			sum := MV[0][0][y][x] + MV[0][1][y][x] + MV[0][2][y][x] + MV[0][3][y][x];
			IF sum = 0 THEN
				dx := 0
			ELSE
				IF sum >= 0 THEN
					dx := RoundTab[ABS( sum ) MOD 16] + (ABS( sum ) DIV 16) * 2
				ELSE
					dx :=  -(RoundTab[ ABS( sum ) MOD 16] + ( ABS( sum ) DIV 16 ) * 2)
				END;
			END;
			
			sum := MV[1][0][y][x] + MV[1][1][y][x] +  MV[1][2][y][x] + MV[1][3][y][x];
			IF sum = 0 THEN
				dy := 0
			ELSE
				IF sum >= 0 THEN
					dy := RoundTab[ABS( sum ) MOD 16] + (ABS(sum) DIV 16) * 2
				ELSE
					dy := -(RoundTab[ABS( sum ) MOD 16] + (ABS(sum) DIV 16) * 2)
				END;
			END;
		ELSE
			dx := MV[0][0][y][x];
			dy := MV[1][0][y][x];

			(* chroma rounding *)
			IF dx MOD 4 = 0 THEN
				dx := dx DIV 2;
			ELSE 
				dx := SYSTEM.VAL( LONGINT, SYSTEM.VAL( SET, dx DIV 2 ) + {0} )
			END;
			IF dy MOD 4 = 0 THEN
				dy := dy DIV 2;
			ELSE
				dy := SYSTEM.VAL( LONGINT, SYSTEM.VAL( SET, dy DIV 2 ) + {0} )
			END;
		END;
		
		lx :=  lx DIV 2;
		
		IF DT.Debug THEN
			log.String( "reconComp: src[1] "); log.Int( lx, 0 ); log.Char( ' ' ); log.Int( w, 0 ); log.Char( ' ' ); log.Int( h, 0 ); 
			log.Char( ' ' ); log.Int( px, 0 ); log.Char( ' ' ); log.Int( py, 0 ); log.Char( ' ' ); log.Int( dx, 0 ); log.Char( ' ' ); log.Int( dy, 0 ); 
			log.Char( ' ' ); log.Int( 1, 0 ); log.Ln()
		END;

		ReconComp ( src, srcBaseOffset[1], mp4State.frameRef, mp4State.frameRefBaseOffset[1], lx, w, h, px, py, dx, dy, 1 );
		
		IF DT.Debug THEN
			log.String( "reconComp: src[2] "); log.Int( lx, 0 ); log.Char( ' ' ); log.Int( w, 0 ); log.Char( ' ' ); log.Int( h, 0 ); 
			log.Char( ' ' ); log.Int( px, 0 ); log.Char( ' ' ); log.Int( py, 0 ); log.Char( ' ' ); log.Int( dx, 0 ); log.Char( ' ' ); log.Int( dy, 0 ); 
			log.Char( ' ' ); log.Int( 2, 0 ); log.Ln()
		END;

		ReconComp ( src, srcBaseOffset[2], mp4State.frameRef, mp4State.frameRefBaseOffset[2], lx, w, h, px, py, dx, dy, 2 );
	END Reconstruct;
	
	(* Copy block in old picture to actual picture *)
	PROCEDURE ReconComp( s: DT.PointerToArrayOfCHAR; sBaseOffset: LONGINT; d: DT.PointerToArrayOfCHAR; 
			dBaseOffset, lx, w, h, x, y, dx, dy, chroma: LONGINT );
	VAR
	  xint, xh, yint, yh: LONGINT;
	  sIndex, dIndex: LONGINT;
	  mcDriver, i: LONGINT;
	BEGIN
		xint := dx DIV 2;
		xh := dx MOD 2;
		yint := dy DIV 2;
		yh := dy MOD 2;
		
		IF w # 8 THEN
			i := 8;
		ELSE
			i := 0;
		END;
		
		(* origins *)
		sIndex := sBaseOffset + lx * (y + yint) + x + xint;
		dIndex := dBaseOffset + lx * y + x;

		(* mcDriver := ( ( w != 8 ) << 3 ) | ( mp4State.hdr.roundingType <<2 ) | ( yh << 1) | ( xh ); *)
		mcDriver := SYSTEM.VAL( LONGINT, SYSTEM.VAL( SET, i )+ SYSTEM.VAL( SET, mp4State.hdr.roundingType*4 ) 
			+ SYSTEM.VAL( SET, yh*2 ) + SYSTEM.VAL( SET, xh ) );
		
		IF DT.Debug THEN
			log.String("mcDriver: "); log.Int( mcDriver, 0 ); log.Ln();
		END;
		
		CASE mcDriver OF
			(* block *)
			(* no round *)
				 0: CopyBlock(s, d, sIndex, dIndex, lx);
			|	1: CopyBlockHor(s, d, sIndex, dIndex, lx);
			|	2: CopyBlockVer(s, d, sIndex, dIndex, lx);
			|	3: CopyBlockHorVer(s, d, sIndex, dIndex, lx);
			|	4: CopyBlock(s, d, sIndex, dIndex, lx);
			(* round *)
			|	5: CopyBlockHorRound(s, d, sIndex, dIndex,  lx);
			|	6: CopyBlockVerRound(s, d, sIndex, dIndex, lx);
			|	7: CopyBlockHorVerRound(s, d, sIndex, dIndex, lx);
			(*  macroblock *)
			(* no round *)
			|	8: CopyMBlock(s, d, sIndex, dIndex, lx);
			|	9: CopyMBlockHor(s, d, sIndex, dIndex, lx);
			|	10: CopyMBlockVer(s, d, sIndex, dIndex, lx);
			|	11: CopyMBlockHorVer(s, d, sIndex, dIndex, lx);
			|	12: CopyMBlock(s, d, sIndex, dIndex, lx);
			(* round *)
			|	13: CopyMBlockHorRound(s, d, sIndex, dIndex, lx);
			|	14: CopyMBlockVerRound(s, d, sIndex, dIndex, lx);
			|	15: CopyMBlockHorVerRound(s, d, sIndex, dIndex, lx)
		END;
	END ReconComp;	
	
	(* specialized basic motion compensation routines *)
	PROCEDURE CopyBlock( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR
		dy,d,s : LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );
		
		FOR dy := 0 TO 7 DO
			SYSTEM.MOVE( s, d, 8 );
			s := s + stride;
			d := d + stride;
		END;
	END CopyBlock;

	PROCEDURE CopyBlockHor( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR
		dx, dy, d, s, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );
				
		FOR dy := 0 TO 7 DO
			FOR dx := 0 TO 7 DO
				(* Dst[dx] = (Src[dx] + Src[dx+1]+1) >> 1;  hor interpolation with rounding  *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + 1 ) ) );
				SYSTEM.PUT8( d + dx, ( temp + 1 ) DIV 2 );
			END;
			s := s + stride;
			d := d + stride
		END;
	END CopyBlockHor;
	

	PROCEDURE CopyBlockVer( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT  );
	VAR
		dy, dx, d, s, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );

		FOR dy := 0 TO 7 DO
			FOR dx := 0 TO 7 DO
				(*	Dst[dx] = (Src[dx] + Src[dx+Stride] +1) >> 1; // ver interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride ) ) );
				SYSTEM.PUT8( d + dx, ( temp + 1 ) DIV 2 )
			END;
			s := s + stride;
			d := d + stride
		END;
	END CopyBlockVer;

	PROCEDURE CopyBlockHorVer( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR
		dy, dx, d, s, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );

		FOR dy := 0 TO 7 DO
			FOR dx := 0 TO 7 DO
				(* Dst[dx] = (Src[dx] + Src[dx+1] + Src[dx+Stride] + Src[dx+Stride+1] +2) >> 2; // horver interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + 1) ) );
				temp := temp + ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride + 1 ) ) );
				SYSTEM.PUT8( d + dx, ( temp + 2 ) DIV 4 )
			END;
			s := s + stride;
			d := d + stride;
		END;
	END CopyBlockHorVer;

	PROCEDURE CopyBlockHorRound( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR
		dy, dx, d, s, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );

		FOR dy := 0 TO 7 DO
			FOR dx := 0 TO 7 DO
			(*	Dst[dx] = (Src[dx] + Src[dx+1]) >> 1; // hor interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + 1 ) ) );
				SYSTEM.PUT8( d + dx, temp DIV 2 )
			END;
			s := s + stride;
			d := d + stride
		END;
	END CopyBlockHorRound;
	
	PROCEDURE CopyBlockVerRound( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR
		dy, dx, d, s, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );

		FOR dy := 0 TO 7 DO
			FOR dx := 0 TO 7 DO
			(*	Dst[dx] = (Src[dx] + Src[dx+Stride]) >> 1; // ver interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride ) ) );
				SYSTEM.PUT8( d+ dx, temp DIV 2 );
			END;
			s := s + stride;
			d := d + stride
		END;
	END CopyBlockVerRound;

	PROCEDURE CopyBlockHorVerRound( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR
		dy, dx, d, s, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );

		FOR dy := 0 TO 7 DO
			FOR dx := 0 TO 7 DO 
			(* Dst[dx] = (Src[dx] + Src[dx+1] + Src[dx+Stride] + Src[dx+Stride+1] +1) >> 2; // horver interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) ) + ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + 1 ) ) ) ;
				temp := temp + ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride + 1 ) ) );
				SYSTEM.PUT8( d + dx, ( temp + 1 ) DIV 4 );
			END;
			s := s + stride;
			d := d + stride
		END;
	END CopyBlockHorVerRound;

	PROCEDURE CopyMBlock( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR 
		dy, s, d: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );
		
		FOR dy := 0 TO 15 DO
			SYSTEM.MOVE( s, d, 16 );
			s := s + stride;
			d := d + stride;
		END;
	END CopyMBlock;

	PROCEDURE CopyMBlockHor(src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT);
	VAR
		dy, dx, s, d, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );
	
		FOR dy := 0 TO 15 DO 
			FOR dx := 0 TO 15 DO
				(* Dst[dx] = (Src[dx] + Src[dx+1]+1) >> 1; // hor interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) );
				temp := temp + ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + 1) ) );
				SYSTEM.PUT8( d + dx, ( temp + 1 ) DIV 2 )
			END;
			s := s + stride;
			d := d + stride
		END;
	END CopyMBlockHor;

	PROCEDURE CopyMBlockVer(src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT);
	VAR
		dy, dx, s, d, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );
		
		FOR dy := 0 TO 15 DO 
			FOR dx := 0 TO 15 DO
				(* Dst[dx] = (Src[dx] + Src[dx+Stride] +1) >> 1; // ver interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) );
				temp := temp + ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride ) ) );
				SYSTEM.PUT8( d + dx, ( temp  + 1 ) DIV 2 );
			END;
			s := s + stride;
			d := d + stride;
		END;
	END CopyMBlockVer;

	PROCEDURE CopyMBlockHorVer(src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT);
	VAR
		dy, dx, s, d, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );
			FOR dy := 0 TO 15 DO 
			FOR dx := 0 TO 15 DO
			(* Dst[dx] = (Src[dx] + Src[dx+1] + Src[dx+Stride] + Src[dx+Stride+1] +2) >> 2; // horver interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) ) + ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx +1 ) ) );
				temp := temp + ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride + 1 ) ) );
				SYSTEM.PUT8( d + dx, ( temp  + 2 ) DIV 4 );
			END;
			s := s + stride;
			d := d + stride;
		END;
	END CopyMBlockHorVer;

	PROCEDURE CopyMBlockHorRound( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR
		dy, dx, d, s, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );

		FOR dy := 0 TO 15 DO
			FOR dx := 0 TO 15 DO
			(*	Dst[dx] = (Src[dx] + Src[dx+1]) >> 1; // hor interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + 1 ) ) );
				SYSTEM.PUT8( d + dx, temp DIV 2 )
			END;
			s := s + stride;
			d := d + stride
		END;
	END CopyMBlockHorRound;

	PROCEDURE CopyMBlockVerRound( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR
		dy, dx, d, s, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[sIndex] );
		d := SYSTEM.ADR( dst[dIndex] );

		FOR dy := 0 TO 15 DO
			FOR dx := 0 TO 15 DO
			(*	Dst[dx] = (Src[dx] + Src[dx+Stride]) >> 1; // ver interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) );
				temp := temp + ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride ) ) );
				SYSTEM.PUT8( d+ dx, temp DIV 2 );
			END;
			s := s + stride;
			d := d + stride
		END;
	END CopyMBlockVerRound;

	PROCEDURE CopyMBlockHorVerRound( src, dst: DT.PointerToArrayOfCHAR; sIndex, dIndex, stride: LONGINT );
	VAR
		dy, dx, d, s, temp: LONGINT;
	BEGIN
		s := SYSTEM.ADR( src[0] ) + sIndex;
		d := SYSTEM.ADR( dst[0] ) + dIndex;

		FOR dy := 0 TO 15 DO
			FOR dx := 0 TO 15 DO 
			(* Dst[dx] = (Src[dx] + Src[dx+1] + Src[dx+Stride] + Src[dx+Stride+1] +1) >> 2; // horver interpolation with rounding *)
				temp := ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + 1) ) );
				temp := temp + ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride ) ) ) + 
					ORD( SYSTEM.VAL( CHAR, SYSTEM.GET8( s + dx + stride + 1 ) ) );
				SYSTEM.PUT8( d + dx, ( temp + 1 ) DIV 4 );
			END;
			s := s + stride;
			d := d + stride
		END;
	END CopyMBlockHorVerRound;
	END MotionCompensation;
	
	TYPE MMXConsts = POINTER TO MMXConstsDesc;
	TYPE MMXConstsDesc = RECORD
		mmwMultY, mmwMultUG, mmwMultUB, mmwMultVR, mmwMultVG: HUGEINT;

		(* various masks and other constants *)
		mmb10, mmw0080, mmw00ff, mmwCutRed, mmwCutGreen, mmwCutBlue: HUGEINT;

		mask5, mask6, maskBlue: HUGEINT;
	END;

	(* Convert colorspace *)	
	TYPE ColorSpace = OBJECT
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
	PROCEDURE Convert(src: DT.PointerToArrayOfCHAR; srcYBaseOffset: LONGINT; yStride: LONGINT; 
				srcUBaseOffset, srcVBaseOffset,uvStride: LONGINT; img: Raster.Image; width, height, dstStride: LONGINT );
		BEGIN
			IF img.fmt.code = Raster.BGR888.code THEN
				ConvertYUVToRGB888( src, srcYBaseOffset,  yStride, srcUBaseOffset, srcVBaseOffset, uvStride, img, width, height, 
					dstStride );
			ELSIF img.fmt.code = Raster.BGR565.code THEN
				IF DT.EnableMMX THEN
					ConvertYUVToRGB565MMX( src, srcYBaseOffset,  yStride, srcUBaseOffset, srcVBaseOffset, uvStride, img, width, height, 
						dstStride );
				ELSE
					ConvertYUVToRGB565( src, srcYBaseOffset,  yStride, srcUBaseOffset, srcVBaseOffset, uvStride, img, width, height, 
						dstStride );
				END;
			END;
		END Convert;
		
		(* Convert picture from YUV -> RGB 565, mmx version *)
		PROCEDURE ConvertYUVToRGB565MMX(puc: DT.PointerToArrayOfCHAR; pucYBaseOffset: LONGINT; strideY: LONGINT; 
			pucUBaseOffset, pucVBaseOffset, strideUV: LONGINT; pucOut: Raster.Image; 
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
	
		PROCEDURE ScanLine565MMX( horizCount, pucV, pucU, pucY, pucOut: LONGINT; mmxConsts: LONGINT);
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
		PROCEDURE ConvertYUVToRGB565(puc: DT.PointerToArrayOfCHAR; pucYBaseOffset: LONGINT; strideY: LONGINT; 
			pucUBaseOffset, pucVBaseOffset, strideUV: LONGINT; pucOut: Raster.Image; 
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
					
(*					SYSTEM.PUT16( pusOut, SYSTEM.VAL( INTEGER, 
						( SYSTEM.VAL( SET, SYSTEM.LSH( b, 8 ) ) * SYSTEM.VAL( SET, 0F800H ) ) +
						( SYSTEM.VAL( SET, SYSTEM.LSH( g, 3 ) ) * SYSTEM.VAL( SET, 07E0H ) ) + 
						( SYSTEM.VAL( SET, SYSTEM.LSH( r, -3 ) ) * SYSTEM.VAL( SET, 001FH ) ) ) );
*)					
					
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
		PROCEDURE ConvertYUVToRGB888(puc: DT.PointerToArrayOfCHAR; pucYBaseOffset: LONGINT; strideY: LONGINT; 
			pucUBaseOffset, pucVBaseOffset, strideUV: LONGINT; pucOut: Raster.Image; 
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
	

	(* The DivXDecoder *)
	TYPE DivXDecoder* = OBJECT
	VAR
		s: AVI.AVIStream;
		mp4State: DT.MP4State;
		mp4Buffers: DT.MP4Buffers;
		macroBlock: MacroBlock;
		col: ColorSpace;
		opt: DT.DecoderOptions;	(* Between 0 and 10 *)
		frame: POINTER TO ARRAY OF CHAR;
		stride: LONGINT;
		util: DT.MyUtils;
		log: AosFS.Writer;
		debugFile: AosFS.File;
		img: Raster.Image;
						
		(* Read Headers of the next frame and decode it *)	
		PROCEDURE DecodeNextFrame*( renderFrame: BOOLEAN ): BOOLEAN;
		VAR
			ret: BOOLEAN;			
			done: BOOLEAN;
			temp: LONGINT;
		BEGIN
			IF DT.Debug THEN
				log.String( "Decoding picture number: "); log.Int( mp4State.hdr.picNum, 0 ); log.Ln()
			END;	

			IF s.Resynch() = FALSE THEN
				RETURN FALSE
			END;
			
			REPEAT 
				NextStartCode();
				
				IF s.ShowBits( 27 ) = DT.VideoObjectStartCode THEN
					ret := GetVisualObjectHeader()
				ELSIF s.ShowBits( 32 ) = DT.GroupOfVopStartCode THEN
					ret := GetGOPHeader()
				ELSIF s.ShowBits( 32 ) = DT.VideoObjectPlaneStartCode THEN
					IF GetVideoObjectPlaneHeader() = FALSE THEN
						AosOut.String( "DivXPlayer: Reading VideoObjectPlane Header failed, Pos in Stream: "); 
						AosOut.Int( s.FilePos(), 0 ); AosOut.String(" Next 32 Bits: "); AosOut.Hex( s.ShowBits(32), 0 ); AosOut.Ln();
						RETURN FALSE
					END;
					
					DecodeVOP( renderFrame );
					done := TRUE;
					
				ELSIF s.ShowBits( 32 ) = DT.UserDataStartCode THEN
					temp := s.GetBits( 32 );
					WHILE s.ShowBits( 24 ) # 1 DO
						s.SkipBits( 8 )
					END;
				ELSE
					(* Nothing useful found, so search the next header *)
					s.SkipBits( 8 )
				END;
			
			UNTIL ( done OR ( ( s.index DIV 32 ) >= s.chunkSize - 4 ) );
			
			IF ~done THEN RETURN FALSE END;
			
			INC( mp4State.hdr.picNum );
			
			IF DT.Debug THEN
				debugFile.Update()
			END;
			
			RETURN TRUE;
	END DecodeNextFrame;
		
		(* Decodes a Frame *)
		PROCEDURE DecodeVOP( renderFrame: BOOLEAN );
		VAR
			i: LONGINT;
			tmp: LONGINT;
			tmpPtr: DT.PointerToArrayOfCHAR;
			res: BOOLEAN;
		BEGIN
			mp4State.hdr.mba := 0;
			mp4State.hdr.mbXPos := 0;
			mp4State.hdr.mbYPos := 0;
			
			REPEAT
				res := macroBlock.Decode();
				INC( mp4State.hdr.mba  )
			UNTIL ( mp4State.hdr.mba >= mp4State.hdr.mbASize ) OR ( s.ShowBitsByteAligned( 23 ) =  0 );
			
			(* add edge to decoded frame *)
			MakeEdge( mp4State.frameRef, mp4State.frameRefBaseOffset[0], 
				mp4State.codedPictureWidth, mp4State.codedPictureHeight, 32 );
			MakeEdge( mp4State.frameRef, mp4State.frameRefBaseOffset[1], mp4State.chromWidth, mp4State.chromHeight, 16 );
			MakeEdge( mp4State.frameRef, mp4State.frameRefBaseOffset[2], mp4State.chromWidth, mp4State.chromHeight, 16 );
			
			PictureDisplay( stride, renderFrame );
			
			(* exchange ref and for frames *)
			FOR i := 0 TO 2 DO
				tmp := mp4State.frameRefBaseOffset[i];
				mp4State.frameRefBaseOffset[i] := mp4State.frameForBaseOffset[i];
				mp4State.frameForBaseOffset[i] := tmp
			END;
			tmpPtr := mp4State.frameRef;
			mp4State.frameRef := mp4State.frameFor;
			mp4State.frameFor := tmpPtr
		END DecodeVOP;

				
		(* copy the actual picture to the destinatin buffer in correct format *)
		PROCEDURE PictureDisplay( stride: LONGINT; renderFlag: BOOLEAN );
		BEGIN
			IF ( renderFlag ) & ( img # NIL ) THEN
				(* Postprocessing could be added here *)
					col.Convert( mp4State.frameRef, mp4State.frameRefBaseOffset[0], mp4State.codedPictureWidth,
						mp4State.frameRefBaseOffset[1], mp4State.frameRefBaseOffset[2], ( mp4State.codedPictureWidth DIV 2 ),
						img, mp4State.hdr.width, mp4State.hdr.height, stride );
			END;
		END PictureDisplay;
		
		(* Constructor to init tables *)
		PROCEDURE &init( stream: AVI.AVIStream; header: AVI.AVIStreamHeaderPtr );
		BEGIN
			IF DT.Debug THEN
				(* Register empty file *)
				debugFile := AosFS.New( "DivXDebug.Log" );
				AosFS.Register( debugFile );
				(* And open empty file for writing *)
				debugFile := AosFS.Old("DivXDebug.Log" );
				AosFS.OpenWriter(log, debugFile, 0);
			END;
			
			s := stream;
			NEW( opt, header );
			NEW( mp4Buffers, opt );
			NEW( mp4State, opt, mp4Buffers );
			NEW( macroBlock, mp4State, s, log );
			NEW( util );
			NEW( col );
			
			stride := opt.xDim
		END init;
		
		(* Add edges to the picture *)
		PROCEDURE MakeEdge( framePic: DT.PointerToArrayOfCHAR; framePicBaseOffset, edgedWidth, edgedHeight, edge: LONGINT );
		VAR
			j, width, height: LONGINT;		
			pBorder, pBorderTop, pBorderBottom, pBorderTopRef, pBorderBottomRef: LONGINT;
			borderLeft, borderRight: CHAR;
			pLeftCornerTop, pRightCornerTop, pLeftCornerBottom, pRightCornerBottom: LONGINT;
			leftCornerTop, rightCornerTop, leftCornerBottom, rightCornerBottom: CHAR;
		BEGIN
			width := edgedWidth - ( 2*edge );
			height := edgedHeight - ( 2*edge );
	
			(* left and right edges *)
			pBorder := framePicBaseOffset;

			FOR j := 1 TO height DO
				borderLeft := framePic[pBorder];
				borderRight := framePic[pBorder + (width-1)];
	
				util.MemSet( framePic, pBorder - edge, borderLeft, edge );
				util.MemSet( framePic, pBorder + width, borderRight, edge );

				pBorder := pBorder + edgedWidth
			END;

			(* top and bottom edges *)
			pBorderTopRef := framePicBaseOffset;
			pBorderBottomRef := framePicBaseOffset + ( edgedWidth*( height -1 ) );
			pBorderTop := pBorderTopRef - ( edge*edgedWidth );
			pBorderBottom := pBorderBottomRef + edgedWidth;

			FOR j := 1 TO edge DO
				SYSTEM.MOVE( SYSTEM.ADR( framePic[pBorderTopRef] ), SYSTEM.ADR( framePic[pBorderTop] ), width );
				SYSTEM.MOVE( SYSTEM.ADR( framePic[pBorderBottomRef] ), SYSTEM.ADR( framePic[pBorderBottom] ), width );

				pBorderTop := pBorderTop + edgedWidth;
				pBorderBottom := pBorderBottom + edgedWidth
			END;
  
			(* corners *)
			pLeftCornerTop := framePicBaseOffset - edge - ( edge * edgedWidth );
			pRightCornerTop := pLeftCornerTop + edge + width;
			pLeftCornerBottom := framePicBaseOffset + (edgedWidth * height) - edge;
			pRightCornerBottom := pLeftCornerBottom + edge + width;

			leftCornerTop := framePic[framePicBaseOffset];
			rightCornerTop := framePic[ framePicBaseOffset + width - 1];
			leftCornerBottom := framePic[framePicBaseOffset + ( edgedWidth * ( height - 1 ) )];
			rightCornerBottom := framePic[ framePicBaseOffset + (edgedWidth * ( height - 1 ) ) + ( width - 1 )];

			FOR j := 1 TO edge DO
				util.MemSet( framePic, pLeftCornerTop, leftCornerTop, edge );
				util.MemSet( framePic, pRightCornerTop, rightCornerTop, edge );
				util.MemSet( framePic, pLeftCornerBottom, leftCornerBottom, edge );
				util.MemSet( framePic, pRightCornerBottom, rightCornerBottom, edge );

				pLeftCornerTop := pLeftCornerTop + edgedWidth;
				pRightCornerTop := pRightCornerTop + edgedWidth;
				pLeftCornerBottom := pLeftCornerBottom + edgedWidth;
				pRightCornerBottom := pRightCornerBottom + edgedWidth
			END;
		END MakeEdge;

		(* Read Headers *)
		PROCEDURE GetVisualObjectHeader(): BOOLEAN;
		VAR
				temp, i, k: LONGINT;
				tempReal: REAL;
		BEGIN
			
			IF s.ShowBits( 27 ) = DT.VideoObjectStartCode THEN
				temp := s.GetBits( 27 );
				temp := s.GetBits( 5 );	(* VideoObject ID *)
				
				temp := s.GetBits( 28 );
				IF temp # DT.VisualObjectLayerStartCode THEN
					IF DT.Debug THEN 
						log.String( "VideoObjectLayerStartCode expected but found: " ); log.Int( temp, 0 ); log.Ln()
					END;
					RETURN FALSE
				END;
				
				mp4State.hdr.ident := s.GetBits( 4 ); (* vol_id *)
				mp4State.hdr.randomAccessibleVol := s.GetBits( 1 );
				mp4State.hdr.typeIndication := s.GetBits( 8 ); 
				mp4State.hdr.isObjectLayerIdentifier := s.GetBits( 1 );

				IF mp4State.hdr.isObjectLayerIdentifier > 0 THEN
					mp4State.hdr.visualObjectLayerVerId := s.GetBits( 4 );
					mp4State.hdr.visualObjectLayerPriority := s.GetBits( 3 )
				ELSE				
					mp4State.hdr.visualObjectLayerVerId := 1;
					mp4State.hdr.visualObjectLayerPriority := 1
				END;

				mp4State.hdr.aspectRatioInfo := s.GetBits( 4 );
					ASSERT( mp4State.hdr.aspectRatioInfo # 0FH );
				(*	IF mp4State.hdr.aspectRatioInfo = 0FH THEN
					mp4State.hdr.parWidth := s.GetBits( 8 );
					mp4State.hdr.parHeight := s.GetBits( 8 )
				END; *)

				mp4State.hdr.volControlParameters := s.GetBits( 1 );
				IF mp4State.hdr.volControlParameters > 0 THEN
					mp4State.hdr.chromaFormat := s.GetBits( 2 );
					mp4State.hdr.lowDelay := s.GetBits( 1 );
					
					mp4State.hdr.vbvParameters := s.GetBits( 1 );
					IF mp4State.hdr.vbvParameters > 0 THEN
						mp4State.hdr.firstHalfBitRate := s.GetBits( 15 );
						temp := s.GetBits( 1 ); 	(* marker *)
						mp4State.hdr.latterHalfBitRate := s.GetBits( 15 );
						temp := s.GetBits( 1 ); 	(* marker *)
						mp4State.hdr.firstHalfvbvBufferSize := s.GetBits( 15 );
						temp := s.GetBits( 1 ); 	(* marker *)
						mp4State.hdr.latterHalfvbvBufferSize := s.GetBits( 3 );
						mp4State.hdr.firstHalfvbvOccupancy := s.GetBits( 11 );
						temp := s.GetBits( 1 ); 	(* marker *)
						mp4State.hdr.latterHalfvbvOccupancy := s.GetBits( 15 );
						temp := s.GetBits( 1 ) 	(* marker *)
					END;
				END;
			
				mp4State.hdr.shape := s.GetBits( 2 );
				temp := s.GetBits( 1 ); (* Marker *)
				mp4State.hdr.timeIncrementResolution := s.GetBits( 16 );
				temp := s.GetBits( 1 ); (* Marker *)
				mp4State.hdr.fixedVopRate := s.GetBits( 1 );

				IF mp4State.hdr.fixedVopRate > 0 THEN
					tempReal := Math.ln( mp4State.hdr.timeIncrementResolution) / Math.ln( 2.0 );
					temp :=  ENTIER( tempReal );
					IF  tempReal / Reals.Real( temp ) > 1.0 THEN
						INC( temp )
					END;
					IF temp < 1 THEN
						temp := 1
					END;
					mp4State.hdr.fixedVopTimeIncrement := s.GetBits( temp )
				END;
			
				IF mp4State.hdr.shape # DT.BinaryShapeOnly THEN
					IF mp4State.hdr.shape = 0 THEN
						temp := s.GetBits( 1 );	(* Marker *)
						mp4State.hdr.width := s.GetBits( 13 );
						temp := s.GetBits( 1 );	(* Marker *)
						mp4State.hdr.height := s.GetBits( 13 );
						temp := s.GetBits( 1 )	(* Marker *)
					END;

					mp4State.hdr.interlaced := s.GetBits( 1 );
					mp4State.hdr.obmcDisable := s.GetBits( 1 );

					IF mp4State.hdr.visualObjectLayerVerId = 1 THEN
						mp4State.hdr.spriteUsage := s.GetBits( 1 )
					ELSE
						mp4State.hdr.spriteUsage := s.GetBits( 2 )
					END;

					mp4State.hdr.not8Bit := s.GetBits( 1 );
					IF mp4State.hdr.not8Bit > 0THEN
						mp4State.hdr.quantPrecision := s.GetBits( 4 );
						mp4State.hdr.bitsPerPixel := s.GetBits( 4 )
					ELSE
						mp4State.hdr.quantPrecision := 5;
						mp4State.hdr.bitsPerPixel := 8
					END;
					
					IF mp4State.hdr.shape = DT.GrayScaleOnly THEN 
						AosOut.String("GreyScale not supported"); log.Ln();
						RETURN FALSE
					END;

					mp4State.hdr.quantType := s.GetBits( 1 ); 
					IF mp4State.hdr.quantType > 0 THEN 
						
						mp4State.hdr.loadIntraQuantMatrix := s.GetBits( 1 );
						IF mp4State.hdr.loadIntraQuantMatrix > 0 THEN
							(* load intra quant matrix *)
							k := 0;
							REPEAT
								INC( k );
								temp := s.GetBits( 8 );
								mp4State.mp4Tables.intraQuantMatrix[mp4State.mp4Tables.zigZagScan[k]] := temp
							UNTIL ( ( k >=  64 ) OR ( temp = 0 ) );
							
							FOR i := k TO 63 DO 
								mp4State.mp4Tables.intraQuantMatrix[mp4State.mp4Tables.zigZagScan[i]] :=
									mp4State.mp4Tables.intraQuantMatrix[mp4State.mp4Tables.zigZagScan[k-1]]
							END;
						END;
						
						mp4State.hdr.loadNonIntraQuantMatrix := s.GetBits( 1 );
						IF mp4State.hdr.loadNonIntraQuantMatrix > 0 THEN
							(* load nonintra quant matrix *)
							k := 0;
							REPEAT
								INC(k);
								temp := s.GetBits( 8 );
								mp4State.mp4Tables.nonIntraQuantMatrix[mp4State.mp4Tables.zigZagScan[k]] := temp
							UNTIL ( ( k >= 64 ) OR ( temp = 0 ) );
							
							FOR i := k TO 63 DO
								mp4State.mp4Tables.nonIntraQuantMatrix[mp4State.mp4Tables.zigZagScan[i]] :=
									mp4State.mp4Tables.nonIntraQuantMatrix[mp4State.mp4Tables.zigZagScan[k-1]]
							END;
						END;
					END;
					
					IF mp4State.hdr.visualObjectLayerVerId # 1 THEN (* ident *)
						mp4State.hdr.quarterPixel := s.GetBits( 1 )
					ELSE
						mp4State.hdr.quarterPixel := 0
					END;

					mp4State.hdr.complexityEstimationDisable := s.GetBits( 1 );
					mp4State.hdr.errorResDisable := s.GetBits( 1 );
					mp4State.hdr.dataPartitioning := s.GetBits( 1 );
					IF mp4State.hdr.dataPartitioning > 0 THEN
						AosOut.String( "Data partitioning not supported" ); AosOut.Ln();
						RETURN FALSE
					ELSE
						mp4State.hdr.errorResDisable := 1
					END;
			
					mp4State.hdr.intraacdcPredDisable := 0;
					mp4State.hdr.scalability := s.GetBits( 1 );

					IF mp4State.hdr.scalability > 0 THEN
						AosOut.String( "Scalability not supported" ); AosOut.Ln();
						RETURN FALSE
					END;
				
					IF  s.ShowBits( 32 ) = DT.UserDataStartCode THEN 
						AosOut.String("No user data in video object Layer supported")
					END;
    			END;
				
				RETURN TRUE
			ELSE;
			END;
			RETURN FALSE
		END GetVisualObjectHeader;
		
		PROCEDURE GetGOPHeader(): BOOLEAN;
		VAR 
			temp: LONGINT;
		BEGIN
			IF s.ShowBits( 32 ) = DT.GroupOfVopStartCode THEN 
				temp := s.GetBits( 32 ); 

				mp4State.hdr.timeCode := s.GetBits( 18 );
				mp4State.hdr.closedGov := s.GetBits( 1 );
				mp4State.hdr.brokenLink := s.GetBits( 1 )
			ELSE
			END;
			RETURN TRUE
		END GetGOPHeader;
		
		PROCEDURE NextStartCode();
		VAR
			temp: LONGINT;
		BEGIN
			IF s.IsAligned() = FALSE THEN 
				temp := s.GetBits( 1 );
				WHILE s.IsAligned() = FALSE DO
					s.SkipBits( 1 )
				END;
			END; 
		END NextStartCode;
		
		PROCEDURE GetVideoObjectPlaneHeader(): BOOLEAN;
		VAR
			temp: LONGINT;
			tempReal: REAL;
		BEGIN
				
			IF s.GetBits( 32 ) # DT.VideoObjectPlaneStartCode THEN
(*  			log.String("Vop start code not found"); log.Ln();  *)
				RETURN FALSE
			END;

			mp4State.hdr.predictionType := s.GetBits( 2 );

			mp4State.hdr.timeBase := 0;
			WHILE s.GetBits( 1 ) # 0 DO (* temporal time base *)
				INC( mp4State.hdr.timeBase )
			END;
	
			temp := s.GetBits( 1 );	(* marker bit *)
			
			tempReal := Math.ln( mp4State.hdr.timeIncrementResolution )/Math.ln( 2.0 );
			temp := ENTIER( tempReal );
			IF ( tempReal / Reals.Real( temp ) ) > 1.0 THEN
				INC( temp )
			END;
			IF temp < 1 THEN
				temp := 1
			END;
			mp4State.hdr.timeInc := s.GetBits(temp);  (* vop_time_increment (1-16 bits) *)
					
			temp := s.GetBits( 1 );	(* marker bit *)
			mp4State.hdr.vopCoded := s.GetBits( 1 );
			IF mp4State.hdr.vopCoded = 0 THEN 
				NextStartCode();
				RETURN TRUE
			END;
			
			IF ( mp4State.hdr.shape # DT.BinaryShapeOnly ) & ( mp4State.hdr.predictionType = DT.PVOP ) THEN 
				mp4State.hdr.roundingType := s.GetBits( 1 )
			ELSE
				mp4State.hdr.roundingType := 0
			END;
	
			IF mp4State.hdr.shape # DT.Rectangular THEN
				IF ~( (mp4State.hdr.spriteUsage = DT.StaticSprite) & (mp4State.hdr.predictionType = DT.IVOP) ) THEN 
					mp4State.hdr.width := s.GetBits( 13 );
					temp := s.GetBits( 1 ); (* Marker *)
					mp4State.hdr.height := s.GetBits( 13 );
					temp := s.GetBits( 1 ); (* Marker *)
					mp4State.hdr.horSpatRef := s.GetBits( 13 );
					temp := s.GetBits( 1 ); (* Marker *)
					mp4State.hdr.verSpatRef := s.GetBits( 13 );
					temp := s.GetBits( 1 ) (* Marker *)
				END;
		
				mp4State.hdr.changeCRDisable := s.GetBits( 1 );
				mp4State.hdr.constantAlpha := s.GetBits( 1 );
				IF mp4State.hdr.constantAlpha > 0THEN
					mp4State.hdr.constantAlphaValue := s.GetBits( 8 )
				END;
			END;
			
			IF  mp4State.hdr.complexityEstimationDisable = 0 THEN
				AosOut.String("ComplexityEstimationDisable must be enabled"); AosOut.Ln(); 
				RETURN FALSE
			END;
			
			IF mp4State.hdr.shape # DT.BinaryShapeOnly THEN  
				mp4State.hdr.intradcvlcthr := s.GetBits( 3 );
				IF mp4State.hdr.interlaced > 0 THEN
					AosOut.String("Interlaced movies not supported"); AosOut.Ln();
					RETURN FALSE
				END;
			END;
	
			IF mp4State.hdr.shape # DT.BinaryShapeOnly THEN 
				mp4State.hdr.quantizer := s.GetBits( mp4State.hdr.quantPrecision );
				IF mp4State.hdr.predictionType # DT.IVOP THEN
					mp4State.hdr.fCodeFor := s.GetBits( 3 )
				END;
				
				IF mp4State.hdr.scalability = 0 THEN
					IF ( mp4State.hdr.shape > 0 ) & ( mp4State.hdr.predictionType # DT.IVOP ) THEN
						mp4State.hdr.shapeCodingType := s.GetBits( 1 )
					END;
				END;
			END; 
			
			RETURN TRUE
		END GetVideoObjectPlaneHeader;
	
	(* The decoder renders the picture into this Raster.Image *)	
		PROCEDURE RegisterRenderImage*( imgNew: Raster.Image );
		BEGIN
			img := imgNew;
		END RegisterRenderImage;
	
	END DivXDecoder;
	
	VAR openList : List.List; myUtils: DT.MyUtils;	
	
	(* Do we have enough time to render the next frame? *)
	PROCEDURE CheckTime( VAR refTime: HUGEINT; VAR usedTime: HUGEINT; VAR ticks: LONGINT; 
		timePerFrame: LONGINT ): BOOLEAN;
	VAR
		newTicks: LONGINT;
		timer: AosKernel.Timer;
	BEGIN
		newTicks := AosKernel.GetTimer();

		IF newTicks > ticks THEN
			ticks := newTicks - ticks;
		ELSE
			ticks := MAX( LONGINT ) - ticks + newTicks;
		END;
		
		(* time is in microseconds *)
		usedTime := usedTime + ( ( ticks*1000000 ) DIV AosKernel.second );
		
		refTime := refTime + timePerFrame;
		ticks := newTicks;	
				
		IF refTime > usedTime THEN
			NEW( timer );
			timer.Sleep( SYSTEM.VAL( LONGINT,  refTime - usedTime ) DIV 1000 ); (* millisecs *)
			timer := NIL;
			RETURN TRUE;
		END;
		RETURN FALSE
	END CheckTime;
	
	PROCEDURE InitTime( VAR refTime: HUGEINT; VAR usedTime: HUGEINT; VAR ticks: LONGINT );
	VAR
	BEGIN
		ticks := AosKernel.GetTimer();
		refTime := 0;
		usedTime := 0;
	END InitTime;

	(* Cleanup Procedure of frame*)
	PROCEDURE Cleanup;
	VAR p : PTR; m : Messages.Message; has : BOOLEAN; i: LONGINT;
		timer: AosKernel.Timer;
	BEGIN
		m.msgType := Messages.MsgClose;
		REPEAT
			has := openList.GetCount() > 0;
			IF has THEN 
				p := openList.GetItem(0); 
				
				(* Signal to Player that he should finish playing *)
				p(PW).done.done := TRUE;
				i := 0;
				NEW(timer);
				
				(* Wait max 300 msec for Player to finsh playing *)
				REPEAT
					INC( i );
					timer.Sleep( 10 );
				UNTIL ( p(PW).done.done = FALSE ) OR ( i > 30 );
				
				timer := NIL;
				p(WM.Window).manager.Remove(p(WM.Window)); openList.Remove(p)
			END	
		UNTIL ~has;
	END Cleanup;
	
	PROCEDURE Stop*(par:PTR):PTR;
	BEGIN	
		Cleanup();
		RETURN NIL
	END Stop;
	
	PROCEDURE Play*(par:PTR):PTR;
	VAR 
		sr: AosIO.StringReader;
		pr: AosCommands.Parameters;
		file: AosFS.File;
		mode: Raster.Mode ;
		pw: PW;
		done: BOOLEAN;
		close: POINTER TO Done;
		FileName: ARRAY 255 OF CHAR;
		aviDemux: AVI.AVIDemux;
		videoHeader: AVI.AVIStreamHeaderPtr;
		mainAVIHeader: AVI.MainAVIHeaderPtr;
		divXDecoder: DivXDecoder;
		display: BOOLEAN;
		refTime, usedTime: HUGEINT;
		ticks: LONGINT;
	BEGIN
		NEW(myUtils);
		NEW( close );
		display := TRUE;
		
		(* Read command line *)
		pr := par(AosCommands.Parameters);
		NEW(sr, LEN(pr.str^)); sr.Set(pr.str^);	
		sr.String(FileName);
		
		file := AosFS.Old(FileName);	(* open an existing file *)
		IF file = NIL THEN
			AosOut.String("Couldn't open File ");
			AosOut.String(FileName);
			AosOut.Ln();
			RETURN NIL
		END;
			
		AosOut.String("Opened File "); AosOut.String(FileName); AosOut.Ln;
		NEW(aviDemux,file);
		IF aviDemux.ReadHeader() # TRUE THEN
			RETURN NIL
		END;
		videoHeader := aviDemux.GetVideoStreamHeader();
		mainAVIHeader := aviDemux.GetAVIHeader();
		
		NEW( divXDecoder, aviDemux.GetVideoStream(), aviDemux.GetVideoStreamHeader() );  
		
		(* Open Window *)
		NEW( pw, videoHeader.bitMapInfo.width, videoHeader.bitMapInfo.height, FALSE, close );
		pw.SetTitle( WM.NewString( "DivXPlayer" ) );
		divXDecoder.RegisterRenderImage( pw.backImg );
		
		InitTime( refTime, usedTime, ticks );
		
		REPEAT
			done := ~divXDecoder.DecodeNextFrame( display );
			
			IF display THEN
				pw.Swap();
				pw.Invalidate( Rectangles.MakeRect( 0, 0, pw.backImg.width, pw.backImg.height ) );
				divXDecoder.RegisterRenderImage( pw.backImg );
			END;
			display := CheckTime( refTime, usedTime, ticks, mainAVIHeader.microSecsPerFrame ); 
		UNTIL done OR close.done;
		
		(* Signal to cleanup handler that we are finished *)
		close.done := FALSE;
		
		RETURN NIL
	END Play;

BEGIN
		NEW(openList);
		AosModules.InstallTermHandler(Cleanup)
END DivXPlayer.


Aos.Call DivXPlayer.Play movie.AVI ~
 Aos.Call DivXPlayer.Stop ~