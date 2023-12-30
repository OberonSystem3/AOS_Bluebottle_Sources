MODULE WMTransitions;

IMPORT
	SYSTEM, BIT, Raster, WMGraphics, WMGraphicUtilities, WMRectangles, WMWindowManager, AosBoot, AosOut;

CONST
	DEBUG = FALSE;

TYPE
	Transition* = OBJECT
	
		PROCEDURE Init*(w, h : LONGINT);
		BEGIN
		END Init;
		
		PROCEDURE CalcImage*(a, b, result : Raster.Image; per255 : LONGINT);
		BEGIN
		END CalcImage;
	
	END Transition;

TYPE 
	TransitionMask* = OBJECT(Transition)
	VAR
		mW, mH : LONGINT;
		mask : POINTER TO ARRAY OF CHAR;
		
		PROCEDURE Init*(w, h : LONGINT);
		BEGIN
			mW := w; mH := h;
		END Init;
		
		PROCEDURE SetMask*(mi : Raster.Image);
		VAR x, y, adr, col, i, tr, tg, tb, ta : LONGINT;
			ti : Raster.Image;
			mode : Raster.Mode;
			pix : Raster.Pixel;
			c : WMGraphics.BufferCanvas;
		BEGIN
			IF (mi.width # mW) OR (mi.height # mH) THEN
				NEW(ti); Raster.Create(ti, mW, mH, Raster.BGR888);
				NEW(c, ti);
				c.ScaleImage(mi, WMRectangles.MakeRect(0, 0, mi.width - 1, mi.height - 1), 
					WMRectangles.MakeRect(0, 0, ti.width - 1, ti.height - 1), WMGraphics.ModeCopy, WMGraphics.ScaleBilinear);
				mi := ti
			END;
			NEW(SELF.mask, mW * mH);

			i := 0;
			IF (mi.fmt.code = Raster.bgr565) THEN
				FOR y := 0 TO mi.height -1 DO
					adr := mi.adr + y * mi.bpr; 
					FOR x := 0 TO mi.width - 1 DO
						 col := SYSTEM.GET16(adr + x * 2);
						 mask[i] := CHR((col DIV 32 MOD 64) * 4);
						 INC(i)
					END
				END
			ELSIF (mi.fmt.code = Raster.bgr888) THEN
				FOR y := 0 TO mi.height -1 DO
					adr := mi.adr + y * mi.bpr; 
					FOR x := 0 TO mi.width - 1 DO
						 mask[i] := CHR(SYSTEM.GET8(adr + x * 3 + 1));
						 INC(i)
					END
				END
			ELSE 
				Raster.InitMode(mode, Raster.srcCopy);
				FOR y := 0 TO mi.height -1 DO
					FOR x := 0 TO mi.width - 1 DO
						Raster.Get(mi, x, y, pix, mode); 
						Raster.GetRGBA(pix, tr, tg, tb, ta);
						 mask[i] := CHR(tg);
						 INC(i)
					END
				END	
			END;			
		END SetMask;
		
		
		PROCEDURE DumpMask;
		VAR i, x, y : LONGINT;
			w : WMWindowManager.BufferWindow;
		BEGIN
			NEW(w, mW, mH, FALSE);
			i := 0;
			FOR y := 0 TO mH -1 DO
				FOR x := 0 TO mW - 1 DO
					w.canvas.SetPixel(x, y, WMGraphics.RGBAToColor(0, ORD(mask[i]), 0, 255), WMGraphics.ModeCopy);
					 INC(i)
				END
			END;
			WMWindowManager.DefaultAddWindow(w);
		END DumpMask;
		
		
		PROCEDURE CalcImage*(a, b, result : Raster.Image; per255 : LONGINT);
		VAR i, adra, adrb, adrr, x, y, col : LONGINT;
			mode : Raster.Mode;
			pix : Raster.Pixel;
			
		BEGIN
			IF (a = NIL) OR (b = NIL) OR (result = NIL) OR 
				(a.height # b.height) OR (a.width # b.width) OR (result.height # result.height) OR
				(a.fmt.code # b.fmt.code) OR (a.fmt.code # b.fmt.code) OR (result.fmt.code # result.fmt.code) 
			THEN 
				RETURN 
			END;
			i := 0;
			IF (a.fmt.code = Raster.bgr565) THEN
				FOR y := 0 TO a.height -1 DO
					adra := a.adr + y * a.bpr; 
					adrb := b.adr + y * b.bpr; 
					adrr := result.adr + y * result.bpr; 
					FOR x := 0 TO a.width - 1 DO
						IF ORD(mask[i]) <= per255 THEN col := SYSTEM.GET16(adra + x * 2)
						ELSE  col := SYSTEM.GET16(adrb + x * 2)
						END;
						SYSTEM.PUT16(adrr + x * 2, col);
						INC(i)
					END
				END
			ELSIF (a.fmt.code = Raster.bgr888) THEN
				FOR y := 0 TO a.height -1 DO
					adra := a.adr + y * a.bpr; 
					adrb := b.adr + y * b.bpr; 
					adrr := result.adr + y * result.bpr; 
					FOR x := 0 TO a.width - 1 DO
						IF ORD(mask[i]) <= per255 THEN SYSTEM.MOVE(adra + x * 3, adrr + x * 3, 3)
						ELSE SYSTEM.MOVE(adrb + x * 3, adrr + x * 3, 3)
						END;
						INC(i)
					END
				END
			ELSE 
				Raster.InitMode(mode, Raster.srcCopy);
				FOR y := 0 TO a.height -1 DO
					FOR x := 0 TO a.width - 1 DO
						IF ORD(mask[i]) <= per255 THEN Raster.Get(a, x, y, pix, mode)
						ELSE Raster.Get(b, x, y, pix, mode)
						END;
						Raster.Put(result, x, y, pix, mode); 
						INC(i)
					END
				END
				
			END;			 
		END CalcImage;
		
	END TransitionMask;
	
	TransitionFade* = OBJECT(Transition)
	VAR
		mW, mH : LONGINT;
		mode : Raster.Mode;
		
		PROCEDURE Init*(w, h : LONGINT);
		BEGIN
			mW := w; mH := h;
			Raster.InitMode(mode, Raster.srcCopy);
		END Init;	

		PROCEDURE CalcImage*(a, b, result : Raster.Image; per255 : LONGINT);
		BEGIN
			(* correct outofbound alpha values *)
			IF (per255 < 0) THEN per255 := 0; END;
			IF (per255 > 255) THEN per255 := 255; END;
	
			IF (a.fmt.code = Raster.bgr565) & (b.fmt.code = Raster.bgr565) THEN
				(****************************************************************
				 *
				 * 565-Format (16 Bit):  ( case1: MMX,  case2: optimized Aos code)
				 *
				 ****************************************************************)
				IF (MMXenabled) THEN
					Calc565MMX(a, b, result, per255);
				ELSE
					Calc565Opt(a, b, result, per255);
				END;
			ELSIF (a.fmt.code = Raster.bgr888) & (b.fmt.code = Raster.bgr888) THEN
				(****************************************************************
				 *
				 * 888-Format (24 Bit):  ( case1: MMX,  case2: optimized Aos code)
				 *
				 ****************************************************************)
				IF (MMXenabled) THEN
					Calc888MMX(a, b, result, per255);
				ELSE
					Calc888Opt(a, b, result, per255);
				END;
			ELSIF (a.fmt.code = b.fmt.code) THEN
				(****************************************************************
				 *
				 * Unknown-Format (16/24/32 Bit):  ( in slow generic system calls )
				 *
				 ****************************************************************)
	
				CalcGenUnknown(a, b, result, per255);
			ELSE
				IF (DEBUG) THEN AosOut.String("Error: source formats not equal!"); AosOut.Ln; END;
			END;
	
		END CalcImage;
	
	END TransitionFade;

VAR
	MMXenabled : BOOLEAN;	
	
(* ***
 *
 * Calculate a frame of the fade in 565-Mode (AOS optimized version, 2 pixels at once)
 *
 *** *)
PROCEDURE Calc565Opt(a, b : Raster.Image; VAR result : Raster.Image; per255 : LONGINT);
VAR
	x, y : LONGINT;
	adra, adrb, adrr : LONGINT;
	ar,ag,ab,   br,bg,bb,   cr,cg,cb : LONGINT;
	height, width : LONGINT;
	oddWidth : BOOLEAN; blocksOf4Bytes : LONGINT;
	add64, alphaOver2 : LONGINT;
	tmpA, tmpB : LONGINT;
BEGIN
	IF (DEBUG) THEN AosOut.String("Fade in 565-Format"); AosOut.Ln; END;
	height := a.height; width := a.width;
	IF ( (width MOD 2)=0 ) THEN
		oddWidth := FALSE;
		blocksOf4Bytes := width DIV 2;
	ELSE
		oddWidth := TRUE;
		blocksOf4Bytes := (width-1) DIV 2;
	END;
		add64 := BIT.LOR(64, ASH(64, 16));
		alphaOver2 := BIT.LOR( (per255 DIV 4), ASH((per255 DIV 4),16) );
		FOR y := 0 TO height -1 DO
			adra := a.adr + y * a.bpr; 
			adrb := b.adr + y * b.bpr;
			adrr := result.adr + y * result.bpr;
			FOR x := 0 TO blocksOf4Bytes DO
				(* read two source pixels = 32 bit *)
				tmpA := SYSTEM.GET32(adra + x * 4);
				tmpB := SYSTEM.GET32(adrb + x * 4);
		
				(* Extract the red channels. *)
				ar := BIT.LAND( ASH(tmpA, -11), 001F001FH );
				br := BIT.LAND( ASH(tmpB, -11), 001F001FH );
				(* Extract the green channels *)
				ag := BIT.LAND( ASH(tmpA, -5), 003F003FH );
				bg := BIT.LAND( ASH(tmpB, -5), 003F003FH );
				(* Extract the blue channel *)
				ab := BIT.LAND( tmpA, 001F001FH );
				bb := BIT.LAND( tmpB, 001F001FH );

				(* Calculate the alpha-blended red channel *)
				cr := ASH(    BIT.LAND( (ASH(per255*(br+add64-ar), -8) + ar-alphaOver2), 001F001FH)  ,   11   );			
				(* Calculate the alpha-blended green channel *)
				cg := ASH(    BIT.LAND( (ASH(per255*(bg+add64-ag), -8) + ag-alphaOver2), 003F003FH)  ,   5  );	
				(* Calculate the alpha-blended blue channel *)
				cb := BIT.LAND( (ASH(per255*(bb+add64-ab), -8) + ab-alphaOver2), 001F001FH);	
				(* write the two pixels back *)
				SYSTEM.PUT32(adrr + 4*x, BIT.LOR( BIT.LOR(cr,cg), cb) );
			END;
	
		(* check and deal with odd width *)
		IF (oddWidth) THEN
			(* Read just one pixel *)
			tmpA := SYSTEM.GET16(adra + x * 4);
			tmpB := SYSTEM.GET16(adrb + x * 4);

			(* Extract the red channels *)
			ar := BIT.LAND( ASH(tmpA, -11), 1FH);
			br := BIT.LAND( ASH(tmpB, -11), 1FH);		
			(* Extract the green channels *)
			ag := BIT.LAND( ASH(tmpA, -5), 3FH);
			bg := BIT.LAND( ASH(tmpB, -5), 3FH);		
			(* Extract the blue channels *)
			ab := BIT.LAND(tmpA, 1FH);
			bb := BIT.LAND(tmpB, 1FH);
	
			(* Calc and write the pixel back *)
			cr := ASH(ASH(per255*(br-ar),-8)+ar, 11);
			cg := ASH(ASH(per255*(bg-ag),-8)+ag, 5);
			cb := ASH(per255*(bb-ab),-8)+ab;
			SYSTEM.PUT16(adrr + 2*x, BIT.LOR( BIT.LOR(cr,cg), cb));
		END;
	END;
END Calc565Opt;



(* ***
 *
 * Calculate a frame of the fade in 565-Mode (MMX optimized version, 4 pixels at once)
 *
 *** *)
PROCEDURE Calc565MMX(a, b : Raster.Image; VAR result : Raster.Image; per255 : LONGINT);
VAR
	x, y : LONGINT; (* current image coordinates *)
	height, width : LONGINT;
	remainder : LONGINT;
	blocksOf8Bytes : LONGINT;
	adra, adrb, adrr : LONGINT;
	alpha64, maskRed64, maskGreen64, maskBlue64 : HUGEINT;
	alpha32 : LONGINT;
	tmpA, tmpB : LONGINT;
	ar, ag, ab, br, bg, bb, cr, cg, cb : LONGINT;
BEGIN
	IF (DEBUG) THEN AosOut.String("Fade in 565-Format (MMX)"); AosOut.Ln; END;
	height := a.height; width := a.width;

	remainder := width MOD 4;
	blocksOf8Bytes := (width-remainder) DIV 4;

	(* Set the bit masks for red, green and blue *)
	maskRed64		:= 0F800F800F800F800H;
	maskGreen64	:= 007E007E007E007E0H;
	maskBlue64		:= 0001F001F001F001FH;

	(* Compose the quadruple alpha value and pack it in a 64bit HUGEINT *)
	alpha64 := 0;
	alpha32 := BIT.LOR( per255, ASH(per255,16) );
	SYSTEM.PUT32( SYSTEM.ADR(alpha64), alpha32);
	SYSTEM.PUT32( SYSTEM.ADR(alpha64)+4, alpha32);

	FOR y := 0 TO height -1 DO
		adra := a.adr + y * a.bpr; 
		adrb := b.adr + y * b.bpr;
		adrr := result.adr + y * result.bpr;
		
		Calc565MMXLine(adra, adrb, adrr,    blocksOf8Bytes, per255,    alpha64, maskRed64, maskGreen64, maskBlue64);

		(* alpha-blend remaining pixels *)
		IF (remainder # 0) THEN
			FOR x := 0 TO remainder-1 DO
				(* Read just one pixel *)
				tmpA := SYSTEM.GET16(adra + blocksOf8Bytes*8 + 2*x); 
				tmpB := SYSTEM.GET16(adrb + blocksOf8Bytes*8 + 2*x);
	
				(* Extract the red channels *)
				ar := BIT.LAND( ASH(tmpA, -11), 1FH);
				br := BIT.LAND( ASH(tmpB, -11), 1FH);		
				(* Extract the green channels *)
				ag := BIT.LAND( ASH(tmpA, -5), 3FH);
				bg := BIT.LAND( ASH(tmpB, -5), 3FH);		
				(* Extract the blue channels *)
				ab := BIT.LAND(tmpA, 1FH);
				bb := BIT.LAND(tmpB, 1FH);
		
				(* Calc and write the pixel back *)
				cr := ASH(ASH(per255*(br-ar),-8)+ar, 11);
				cg := ASH(ASH(per255*(bg-ag),-8)+ag, 5);
				cb := ASH(per255*(bb-ab),-8)+ab;
				SYSTEM.PUT16(adrr + blocksOf8Bytes*8 + 2*x, BIT.LOR( BIT.LOR(cr,cg), cb));				
			END;
		END;
	
	END;
END Calc565MMX;



(* ***
 *
 * Helper Function for Calc565MMX: :Calculate fade for just one line using assembler code (MMX technology)
 *
 *** *)
PROCEDURE Calc565MMXLine (adra, adrb, adrr, i, alpha : LONGINT; a64, mr64, mg64, mb64 : HUGEINT);
CODE {SYSTEM.i386, SYSTEM.MMX}
	;
	; Initialize the counter and skip if the latter is equal to zero
	;
	PUSH		ECX		
	MOV		ECX, i[EBP]	
	CMP		ECX, 0
	JZ			skip565

	;
	; Load the frame buffer pointers into the registers
	;
	PUSH		EDI
	PUSH		ESI
	PUSH		EAX
	MOV		EDI, adra[EBP]			; source address of image A
	MOV		ESI, adrb[EBP]			; source address of image B
	MOV		EAX, adrr[EBP]			; destination address of image RESULT


doblend565:
	;
	;  Alpha blend four target and source pixels
	;

	;
	; The mmx registers will basically be used in the following way:
	;	MM0:	red source value A
	;	MM1:	red source value B
	;	MM2:	green source value A
	;	MM3:	green source value B
	;	MM4:	blue source value A
	;	MM5:	blue source value B
	;	MM6:	original source pixel A
	;	MM7:	original source pixel B
	;
	
	;
	;  Note: Two lines together are assumed to pair 
	;    		 in the processornd V-pipes
	;

	MOVQ		MM6, [EDI]				; Load the original source pixel A
	NOP

	MOVQ		MM7, [ESI]				; Load the original source pixel B
	MOVQ		MM0, MM6				; Load the register for the red source A

	PAND		MM0, mr64[EBP]		; Extract the red source A channel
	MOVQ		MM1, MM7				; Load the register for the red source B

	PAND		MM1, mr64[EBP]		; Extract the red source B channel
	PSRLW		MM0, 11				; Shift down the red source A channel

	MOVQ		MM2, MM6				; Load the register for the green source A
	PSRLW		MM1, 11				; Shift down the red source B channel

	MOVQ		MM3, MM7				; Load the register for the green source B
	PSUBW		MM1, MM0				; Calculate red source B minus red source A

	PMULLW	MM1, a64[EBP]			; Multiply the red result with alpha
	NOP

	PAND		MM2, mg64[EBP]		; Extract the green source A channel
	NOP

	PAND		MM3, mg64[EBP]		; Extract the green source B channel
	PSRAW		MM1, 8					; Divide the red result by 256

	PSRLW		MM2, 5					; Shift down the green source B channel
	PADDW		MM1, MM0				; Add the red source B to the red result

	PSLLW		MM1, 11				; Shift up the red source A again
	MOVQ		MM4, MM6				; Load the register for the blue source A

	PSRLW		MM3, 5					; Shift down the green source B channel
	MOVQ		MM5, MM7				; Load the register for the blue source B

	PAND		MM4, mb64[EBP]		; Extract the blue source A channel
	PSUBW		MM3, MM2				; Calculate green source B minus green source A

	PAND		MM5, mb64[EBP]		; Extract the blue source B channel
	PMULLW	MM3, a64[EBP]			; Multiply the green result with alpha

	PSUBW		MM5, MM4				; Calculate blue source B minus blue source A
	NOP

	PMULLW	MM5, a64[EBP]			; Multiply the blue result with alpha
	PSRAW		MM3, 8					; Divide the green result by 256

	PADDW		MM3, MM2				; Add the green source A to the green result
	NOP

	PSRAW		MM5, 8					; Divide the blue result by 256
	PSLLW		MM3, 5					; Shift up the green source B again
				
	PADDW		MM5, MM4				; Add the blue source A to the blue result
	POR		MM1, MM3				; Combine the new red and green values
									
	POR		MM1, MM5				; Combine new blue value with the others to RESULT pixel
	MOVQ		[EAX], MM1				; Write back RESULT  value	

	;
	; Advance to the next four pixels
	;
	ADD		EDI, 8
	ADD		ESI, 8
	ADD		EAX, 8

	;
	; Loop again or break
	;
	DEC		ECX
	JNZ			doblend565

	;
	; Clean up
	;
	POP		EAX
	POP		ESI		
	POP		EDI
	EMMS								; Declare FPU registers free

skip565:
	POP		ECX
END Calc565MMXLine;


(* ***
 *
 * Calculate a frame of the fade in 888-Mode (optimized AOS version, 1 by 1 pixel = 3 Bytes)
 *
 *** *)
PROCEDURE Calc888Opt(a, b : Raster.Image; VAR result : Raster.Image; per255 : LONGINT);
VAR
	x, y : LONGINT;  (* current image coordinates *)
	height, width : LONGINT;
	adra, adrb, adrr : LONGINT;  (* image start addresses *)
	ar,ag,ab,   br,bg,bb,   cr,cg,cb : LONGINT; (* red, green, blue part of the images *)
	tmpA, tmpB, tmpR : LONGINT; (* the two source pixels *)
BEGIN
	IF (DEBUG) THEN AosOut.String("Fade in 888-Format"); AosOut.Ln; END;
	height := a.height;  width := a.width;

	FOR y := 0 TO height -1 DO
		adra := a.adr + y * a.bpr; 
		adrb := b.adr + y * b.bpr;
		adrr := result.adr + y * result.bpr;

		FOR x := 0 TO width-1 DO
			(* read source pixels = 24 bit *)
			IF (x = width-1) THEN
				(* last pixel would create memory access fault when reading 4 bytes -> 3 bytes in 2 steps *)
				tmpA := BIT.LOR( SYSTEM.GET16(adra + x * 3),  ASH(SYSTEM.GET8(adra + x * 3 + 2),16)  );
				tmpB := BIT.LOR( SYSTEM.GET16(adrb + x * 3),  ASH(SYSTEM.GET8(adrb + x * 3 + 2),16)  );
			ELSE	
				(* normal read inside legal memory range -> 4 Bytes and cut off unneaded bits later *)
				tmpA := SYSTEM.GET32(adra + x * 3);
				tmpB := SYSTEM.GET32(adrb + x * 3);
			END;	
			(* Extract the red channels. *)
			ar := BIT.LAND( ASH(tmpA,-16), 0FFH );
			br := BIT.LAND( ASH(tmpB,-16), 0FFH );
			(* Extract the green channels *)
			ag := BIT.LAND( ASH(tmpA,-8), 0FFH );
			bg := BIT.LAND( ASH(tmpB,-8), 0FFH );			
			(* Extract the blue channel *)
			ab := BIT.LAND( tmpA, 0FFH );
			bb := BIT.LAND( tmpB, 0FFH );

			(* Calculate the alpha-blended red channel *)
			cr := ASH (  ASH( per255*(br-ar), -8) + ar  ,  16);
			(* Calculate the alpha-blended green channel *)
			cg := ASH (  ASH( per255*(bg-ag), -8) + ag , 8);
			(* Calculate the alpha-blended blue channel *)
			cb := ASH( per255*(bb-ab), -8) + ab;
			(* write back the new pixel (lower 16bits and then higher 8bits *)
			tmpR := BIT.LOR( BIT.LOR(cr,cg), cb );
			SYSTEM.PUT16(adrr + x * 3      , BIT.LAND(tmpR, 0FFFFH) );
			SYSTEM.PUT8  (adrr + x * 3 + 2, ASH(tmpR, -16)               );
		END;
	END;
END Calc888Opt;


(* ***
 *
 * Calculate a frame of the fade in 888-Mode (MMX optimized version)
 *
 *** *)
PROCEDURE Calc888MMX(a, b : Raster.Image; VAR result : Raster.Image; per255 : LONGINT);
VAR
	x, y : LONGINT; (* current image coordinates *)
	height, width : LONGINT;
	remainder : LONGINT;
	adra, adrb, adrr : LONGINT;
	alpha64, mask64 : HUGEINT;
BEGIN
	IF (DEBUG) THEN AosOut.String("Fade in 565-Format (MMX)"); AosOut.Ln; END;
	height := a.height; width := a.width;

	(* Set a general bit masks *)
	mask64 :=  0000000000FFFFFFH;

	(* Compose the triple alpha value and pack it in a 64bit HUGEINT *)
	alpha64 := 0;
	SYSTEM.PUT32( SYSTEM.ADR(alpha64), BIT.LOR( per255, ASH(per255,16)) );
	SYSTEM.PUT32( SYSTEM.ADR(alpha64)+4, per255);

	FOR y := 0 TO height -1 DO
		adra := a.adr + y * a.bpr; 
		adrb := b.adr + y * b.bpr;
		adrr := result.adr + y * result.bpr;
		Calc888MMXLine(adra, adrb, adrr,    width,    alpha64, mask64);
	END;
END Calc888MMX;


(* ***
 *
 * Helper Function for Calc888MMX: :Calculate fade for just one line using assembler code (MMX technology)
 *
 *** *)
PROCEDURE Calc888MMXLine (adra, adrb, adrr, i : LONGINT; a64, m64 : HUGEINT);
CODE {SYSTEM.i386, SYSTEM.MMX}

	; (re)load the width counter
	PUSH			ECX		
	MOV			ECX, i[EBP]		

	;
	; Load the frame buffer pointers into the registers
	;
	PUSH			EDI		
	PUSH			ESI
	PUSH			EBX
	
	MOV			EDI, adra[EBP]		; source address of image A	
	MOV			ESI, adrb[EBP]		; source address of image B
	MOV			EBX, adrr[EBP]		; destination address of image RESULT

							
	; Load the mask into an mmx register
	MOVQ			MM3, m64[EBP]

	; Load the alpha value into an mmx register
	MOVQ			MM5, a64[EBP]

	; Clear an mmx register to facilitate unpacking
	PXOR			MM6, MM6

doblend24:
	; The mmx registers will basically be used in the following way:
	;
	;	MM0:	source value A
	;	MM1:	source value B
	;	MM2:	working register
	;	MM3:	mask ( 0x00ffffff )
	;	MM4:	working register
	;	MM5:	alpha value
	;	MM6:	zero for unpacking
	;	MM7:	original result value
	;
	
	; Note: Two lines together are assumed to pair 
	;     	  	 in the processornd V-pipes

	MOVD			MM0, [EDI]			; Load the original source pixel A
	MOVQ			MM4, MM3			; Reload the mask ( 0x00ffffff )
					  
	MOVQ			MM1, [ESI]			; Load the original source pixel B
	MOVQ			MM7, MM0			; Save the original result pixel
				
	PUNPCKLBW	MM0, MM6			; Unpack the source pixel A
	PUNPCKLBW	MM1, MM6			; Unpack the source pixel B
	
	MOVQ			MM2, MM0			; Save the unpacked source A values
	NOP

	PMULLW		MM0, MM5			; Multiply the source A with the alpha value
	NOP

	PMULLW		MM1, MM5			; Multiply the source B with the alpha value
	NOP

	PSRLW			MM0, 8				; Divide the source A by 256
	NOP

	PSRLW			MM1, 8				; Divide the source B by 256
	NOP

	PSUBW			MM1, MM0			; Calculate the source B minus source A
	NOP

	PADDW			MM2, MM1			; Add former result value to the new result
	NOP

	PACKUSWB		MM2, MM2			; Pack the new result
	NOP

	PAND			MM2, MM4			; Mask of unwanted bytes
	NOP

	PANDN			MM4, MM7			; Get the high order byte we must keep
	NOP

	POR			MM2, MM4			; Assemble the value to write back
	NOP

	MOVD			[EBX], MM2			; Write back the new value to result image

	;
	; Advance to the next pixel
	;
	ADD			EDI, 3
	ADD			ESI, 3
	ADD			EBX, 3

	;
	; Loop again or break
	;
	DEC			ECX
	JNZ				doblend24

	;
	; Write back the frame buffer pointers and clean up
	;
	POP			EBX
	POP			ESI
	POP			EDI
	EMMS								; Declare FPU registers free

	POP			ECX
END Calc888MMXLine;

(* ***
 *
 * Calculate a frame of the fade in a Generic-Mode (Packs the result image in a generic buffered canvas object. Very slow!!!)
 *
 *** *)
PROCEDURE CalcGenUnknown(a, b : Raster.Image; VAR result : Raster.Image; perc : LONGINT);
VAR
	x, y : LONGINT; (* current image coordinates *)
	mode : Raster.Mode;
	canvas : WMGraphics.BufferCanvas;
	pix : Raster.Pixel; (* pixel read from a or b *)
	ca, cb : LONGINT; (* color of pixel in a and b *)
	red, green, blue, alpha : LONGINT; 
BEGIN
	IF (DEBUG) THEN
		AosOut.String("Fade in other Format ["); AosOut.String("a.fmt.code= "); AosOut.Int(a.fmt.code, 0); AosOut.String("b.fmt.code= "); AosOut.Int(b.fmt.code, 0);  AosOut.String("]");  AosOut.Ln; 		
	END;
	Raster.InitMode(mode, Raster.srcCopy);
	NEW(canvas, result);
	IF (canvas = NIL) & (DEBUG) THEN
		AosOut.String("Error during calculating fade: couldn't allocate buffer canvas!"); AosOut.Ln; 
		HALT(99);
	END;
	FOR y := 0 TO a.height -1 DO
		FOR x := 0 TO a.width - 1 DO
			Raster.Get(a, x, y, pix, mode);   Raster.GetRGBA(pix, red, green, blue, alpha);   ca := WMGraphics.RGBAToColor(red, green, blue, alpha);
			Raster.Get(b, x, y, pix, mode);   Raster.GetRGBA(pix, red, green, blue, alpha);   cb := WMGraphics.RGBAToColor(red, green, blue, alpha);
			canvas.SetPixel(x, y, WMGraphicUtilities.InterpolateColorLinear(ca, cb, perc), WMGraphics.ModeCopy);
		END
	END;
END CalcGenUnknown;

(* --------------------------------------------------------------------------- *)	

PROCEDURE LoadImage(fileName : ARRAY OF CHAR) : Raster.Image;
VAR t, img : Raster.Image;
	c : WMGraphics.BufferCanvas;
BEGIN
	t := WMGraphics.LoadImage(fileName, TRUE);
	IF t # NIL THEN
		NEW(img); 
		Raster.Create(img, t.width, t.height, Raster.BGR565);
		NEW(c, img);
		c.DrawImage(0, 0, t, WMGraphics.ModeCopy)
	END;	
	RETURN img
END LoadImage;

PROCEDURE Test*(par : ANY) : ANY;
VAR w : WMWindowManager.BufferWindow;
	t : TransitionMask;
	a, b, m : Raster.Image;
	i : LONGINT;
BEGIN
	NEW(t);
	a := LoadImage("Reto01.png");
	b := LoadImage("Reto02.png");
	m := WMGraphics.LoadImage("M_Art1.png", TRUE);
	t.Init(a.width, a.height);
	NEW(w, a.width, a.height, FALSE);
	WMWindowManager.DefaultAddWindow(w);
	t.SetMask(m);
	FOR i := 0 TO 256 DO
		t.CalcImage(a, b, w.img, i );
		w.Invalidate(WMRectangles.MakeRect(0, 0, a.width, a.height));
	END;
	
	RETURN NIL
END Test;

PROCEDURE Test2*(par : ANY) : ANY;
VAR w : WMWindowManager.BufferWindow;
	t : TransitionFade;
	a, b, m : Raster.Image;
	i : LONGINT;
BEGIN
	NEW(t);
	a := LoadImage("Reto01.png");
	b := LoadImage("Reto02.png");
	t.Init(a.width, a.height);
	NEW(w, a.width, a.height, FALSE);
	WMWindowManager.DefaultAddWindow(w);
	FOR i := 0 TO 256 DO
		t.CalcImage(a, b, w.img, i );
		w.Invalidate(WMRectangles.MakeRect(0, 0, a.width, a.height));
	END;
	
	RETURN NIL
END Test2;

BEGIN
	MMXenabled := 23 IN AosBoot.features;
END WMTransitions.

S.Free WMTransitions ~

WMTransitions.Test ~
WMTransitions.Test2 ~