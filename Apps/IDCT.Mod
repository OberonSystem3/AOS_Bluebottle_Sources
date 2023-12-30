(** AUTHOR "Michael Szediwy"; 
	PURPOSE "Inverse Discrete CosineTransformation for Aos based on 
		- Intel's AP-945: Using Streaming SMID Extensions 2(SSE2) to Implement an Inverse Discrete Cosine Transform"; 
*)
MODULE IDCT;

IMPORT
	AosCommands, AosIO, AosBoot, SYSTEM, AosOut;

CONST
	NrBlocks=4;
	BITSINVACC = 4;
	SHIFTINVROW = 16 - BITSINVACC;
	SHIFTINVCOL = 1 + BITSINVACC;	
	
	(* Const for idct *)
	W1 = 2841;                (* 2048*sqrt(2)*cos(1*pi/16) *)
	W2 = 2676;                (* 2048*sqrt(2)*cos(2*pi/16) *)
	W3 = 2408;                 (* 2048*sqrt(2)*cos(3*pi/16) *)
	W5 = 1609;                 (* 2048*sqrt(2)*cos(5*pi/16) *)
	W6 = 1108;                 (* 2048*sqrt(2)*cos(6*pi/16) *)
	W7 = 565;                  (* 2048*sqrt(2)*cos(7*pi/16) *)
	
	INT* = 0;
	SSE* = 1;
	SSE2* = 2;

TYPE IdctBlock= ARRAY 64 OF INTEGER;

VAR
	RNDINVROW, RNDINVCOL, RNDINVCORR: INTEGER;
	M128onecorr, M128roundinvrow, M128roundinvcol, M128roundinvcorr, M128tg116, M128tg216, M128tg316, M128cos416: POINTER TO ARRAY OF INTEGER;
	M128tabi04, M128tabi17, M128tabi26, M128tabi35: POINTER TO ARRAY OF INTEGER;	
	tabi04adr, tabi17adr, tabi26adr, tabi35adr, onecorradr, roundinvrowadr, roundinvcoladr, roundinvcorradr, tg116adr, tg216adr, tg316adr, cos416adr: LONGINT;
	Transform*: PROCEDURE (src, dst: LONGINT);
	intTab: POINTER TO ARRAY OF INTEGER;
	status*: LONGINT;	


PROCEDURE -MOVDQA1;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX, SYSTEM.SSE2}
	MOVDQA	XMM0, [EAX]
	MOVDQA	XMM4, 32[EAX]
END MOVDQA1;

PROCEDURE -MOVDQA2;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX, SYSTEM.SSE2}
	MOVDQA	[EDX], XMM0
	MOVDQA	32[EDX], XMM4
	MOVDQA	XMM0, 64[EAX]
	MOVDQA	XMM4, 96[EAX]
END MOVDQA2;

PROCEDURE -MOVDQA3;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX, SYSTEM.SSE2}
	MOVDQA	64[EDX], XMM0
	MOVDQA	96[EDX], XMM4
	MOVDQA	XMM0, 48[EAX]
	MOVDQA	XMM4, 16[EAX]
END MOVDQA3;

PROCEDURE -MOVDQA4;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX, SYSTEM.SSE2}
	MOVDQA	48[EDX], XMM0
	MOVDQA	16[EDX], XMM4
	MOVDQA	XMM0, 80[EAX]
	MOVDQA	XMM4, 112[EAX]
END MOVDQA4;

PROCEDURE -MOVDQA5;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX, SYSTEM.SSE2}
	MOVDQA	80[EDX], XMM0
	MOVDQA	XMM0, 80[EDX] (* necessary ? *)
	MOVDQA	112[EDX], XMM4
	MOVDQA	XMM4, 112[EDX] (* necessary ? *)
END MOVDQA5;

(* Pay attention if you change local varss. In the inline procedures there are direct address variable *)
PROCEDURE TransformSSE2*(src, dst: LONGINT);
VAR tg116, tg216, tg316, cos416, onecorr, roundinvcol, roundinvcorr, i: LONGINT;
BEGIN	
	
	tg116 := tg116adr;
	tg216 := tg216adr;
	tg316 := tg316adr;
	cos416 := cos416adr;
	onecorr := onecorradr;
	roundinvcol := roundinvcoladr;
	roundinvcorr := roundinvcorradr;
	
	SYSTEM.PUTREG(SYSTEM.EAX, src);
	SYSTEM.PUTREG(SYSTEM.EDX, dst);
	SYSTEM.PUTREG(SYSTEM.EBX, roundinvrowadr);
	MOVDQA1;	
	SYSTEM.PUTREG(SYSTEM.ESI, tabi04adr);
	SYSTEM.PUTREG(SYSTEM.ECX, tabi26adr);
	DCT8INVROWSSE2;
	MOVDQA2;
(*	SYSTEM.PUTREG(SYSTEM.ESI, tabi04adr);
	SYSTEM.PUTREG(SYSTEM.ECX, tabi26adr);*)
	DCT8INVROWSSE2;	
	MOVDQA3;
	SYSTEM.PUTREG(SYSTEM.ESI, tabi35adr);
	SYSTEM.PUTREG(SYSTEM.ECX, tabi17adr);
	DCT8INVROWSSE2;	
	MOVDQA4;
(*	SYSTEM.PUTREG(SYSTEM.ESI, tabi35adr);
	SYSTEM.PUTREG(SYSTEM.ECX, tabi17adr); *)
	DCT8INVROWSSE2;	
	MOVDQA5;
	DCT8INVCOLSSE2
END TransformSSE2;



PROCEDURE -DCT8INVROWSSE2;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX, SYSTEM.SSE2}
	PSHUFLW	XMM0, XMM0, 0D8H	 
	PSHUFD		XMM1, XMM0, 0		 
	PMADDWD	XMM1, [ESI] 			 
	PSHUFD		XMM3, XMM0, 055H		 
	PSHUFHW	XMM0, XMM0, 0D8H	 
	PMADDWD	XMM3, 32[ESI]			 
	PSHUFD		XMM2, XMM0, 0AAH	 
	PSHUFD		XMM0, XMM0, 0FFH		 
	PMADDWD	XMM2, 16[ESI]			 
	PSHUFHW	XMM4, XMM4, 0D8H	 
	PADDD		XMM1, [EBX]			 
	PSHUFLW	XMM4, XMM4, 0D8H	 
	PMADDWD	XMM0, 48[ESI]			 
	PSHUFD		XMM5, XMM4, 0		 
	PSHUFD		XMM6, XMM4, 0AAH	 
	PMADDWD	XMM5, [ECX]			 
	PADDD		XMM1, XMM2			 
	MOVDQA	XMM2, XMM1			 
	PSHUFD		XMM7, XMM4, 055H		 
	PMADDWD	XMM6, 16[ECX]			 
	PADDD		XMM0, XMM3			 
	PSHUFD		XMM4, XMM4, 0FFH		 
	PSUBD		XMM2, XMM0			 
	PMADDWD	XMM7, 32[ECX]			 
	PADDD		XMM0, XMM1			 
	PSRAD		XMM2, 12				 
	PADDD		XMM5, [EBX]			 
	PMADDWD	XMM4, 48[ECX]			 
	PADDD		XMM5, XMM6			 
	MOVDQA	XMM6, XMM5			 
	PSRAD		XMM0, 12				 
	PSHUFD		XMM2, XMM2, 01BH	 
	PACKSSDW	XMM0, XMM2			 
	PADDD		XMM4, XMM7			 
	PSUBD		XMM6, XMM4			 
	PADDD		XMM4, XMM5			 
	PSRAD		XMM6, 12				 
	PSRAD		XMM4, 12				 
	PSHUFD		XMM6, XMM6, 01BH	 
	PACKSSDW	XMM4, XMM6			 
END DCT8INVROWSSE2;



PROCEDURE -DCT8INVCOLSSE2;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX, SYSTEM.SSE2}
	MOV		EDI, -12[EBP]				 
	MOVDQA	XMM1, [EDI]				 
	MOVDQA	XMM2, XMM0				 
	MOVDQA	XMM3, 48[EDX]				 
	PMULHW	XMM0, XMM1				 
	PMULHW	XMM1, XMM3				 
	MOV		EDI, -4[EBP]				 
	MOVDQA	XMM5, [EDI]				 
	MOVDQA	XMM6, XMM4				 
	PMULHW	XMM4, XMM5				 
	PADDSW	XMM0, XMM2				 
	PMULHW	XMM5, 16[EDX]				 
	PADDSW	XMM1, XMM3				 
	MOVDQA	XMM7, 96[EDX]				 
	PADDSW	XMM0, XMM3				 
	MOV		EDI, -8[EBP]				 
	MOVDQA	XMM3, [EDI]				 
	PSUBSW	XMM2, XMM1				 
	PMULHW	XMM7, XMM3				 
	MOVDQA	XMM1, XMM0				 
	PMULHW	XMM3, 32[EDX]				 
	PSUBSW	XMM5, XMM6				 
	PADDSW	XMM4, 16[EDX]				 
	PADDSW	XMM0, XMM4				 		 
	MOV		EDI, -20[EBP]			 
	PADDSW	XMM0, [EDI]				 
	PSUBSW	XMM4, XMM1				 
	MOVDQA	XMM6, XMM5				 
	PSUBSW	XMM5, XMM2				 
	MOV		EDI, -20[EBP]			 
	PADDSW	XMM5, [EDI]	 					
	PADDSW	XMM6, XMM2				 
	MOVDQA	112[EDX], XMM0			 
	MOVDQA	XMM1, XMM4				 
	MOV		EDI, -16[EBP]			 
	MOVDQA	XMM0, [EDI]				 
	PADDSW	XMM4, XMM5				 
	MOV		EDI, -16[EBP]			 
	MOVDQA	XMM2, [EDI]	 
	PMULHW	XMM2, XMM4				 
	MOVDQA	48[EDX], XMM6				 
	PSUBSW	XMM1, XMM5				 
	PADDSW	XMM7, 32[EDX]				 
	PSUBSW	XMM3, 96[EDX]				 
	MOVDQA	XMM6, [EDX]				 
	PMULHW	XMM0, XMM1				 
	MOVDQA	XMM5, 64[EDX]				 
	PADDSW	XMM5, XMM6				 
	PSUBSW	XMM6, 64[EDX]				
	PADDSW	XMM4, XMM2 
	MOV		EDI, -20[EBP]			 
	POR		XMM4, [EDI]				 
	PADDSW	XMM0, XMM1				 
	MOV		EDI, -20[EBP]			 
	POR		XMM0, [EDI]	 
	MOVDQA	XMM2, XMM5				 
	PADDSW	XMM5, XMM7				 
	MOVDQA	XMM1, XMM6				 					 
	MOV		EDI, -24[EBP]		 
	PADDSW	XMM5, [EDI]				 
	PSUBSW	XMM2, XMM7				 
	MOVDQA	XMM7, 112[EDX]			 
	PADDSW	XMM6, XMM3				 
	MOV		EDI, -24[EBP]		 
	PADDSW	XMM6, [EDI]	 
	PADDSW	XMM7, XMM5				 
	PSRAW		XMM7, SHIFTINVCOL		 
	PSUBSW	XMM1, XMM3				 
	MOV		EDI, -28[EBP]		 
	PADDSW	XMM1, [EDI]				  
	MOVDQA	XMM3, XMM6				 
	MOV		EDI, -28[EBP]
	PADDSW	XMM2, [EDI]				 
	PADDSW	XMM6, XMM4				 
	MOVDQA	[EDX], XMM7				 
	PSRAW		XMM6, SHIFTINVCOL		 
	MOVDQA	XMM7, XMM1				 
	PADDSW	XMM1, XMM0				 
	MOVDQA	16[EDX], XMM6				 
	PSRAW		XMM1, SHIFTINVCOL		 
	MOVDQA	XMM6, 48[EDX]				 
	PSUBSW	XMM7, XMM0				 
	PSRAW		XMM7, SHIFTINVCOL		 
	MOVDQA	32[EDX], XMM1				 
	PSUBSW	XMM5, 112[EDX]			 
	PSRAW		XMM5, SHIFTINVCOL		 
	MOVDQA	112[EDX], XMM5			 
	PSUBSW	XMM3, XMM4				 
	PADDSW	XMM6, XMM2				 
	PSUBSW	XMM2, 48[EDX]				 
	PSRAW		XMM6, SHIFTINVCOL		 
	PSRAW		XMM2, SHIFTINVCOL		 
	MOVDQA	48[EDX], XMM6				 
	PSRAW		XMM3, SHIFTINVCOL		 
	MOVDQA	64[EDX], XMM2				 
	MOVDQA	80[EDX], XMM7				 
	MOVDQA	96[EDX], XMM3				 
END DCT8INVCOLSSE2;

PROCEDURE -MOVQ1;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM0, [ECX]
	MOVQ		MM1, 8[ECX]	
END MOVQ1;

PROCEDURE -MOVQ2;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM0, 16[ECX]
	MOVQ		[EDX], MM3
	MOVQ		MM1, 24[ECX]	
	MOVQ		8[EDX], MM7	
END MOVQ2;

PROCEDURE -MOVQ3;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM0, 32[ECX]
	MOVQ		16[EDX], MM3
	MOVQ		MM1, 40[ECX]	
	MOVQ		24[EDX], MM7	
END MOVQ3;

PROCEDURE -MOVQ4;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM0, 48[ECX]
	MOVQ		32[EDX], MM3
	MOVQ		MM1, 56[ECX]	
	MOVQ		40[EDX], MM7	
END MOVQ4;

PROCEDURE -MOVQ5;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM0, 64[ECX]
	MOVQ		48[EDX], MM3
	MOVQ		MM1, 72[ECX]	
	MOVQ		56[EDX], MM7	
END MOVQ5;

PROCEDURE -MOVQ6;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM0, 80[ECX]
	MOVQ		64[EDX], MM3
	MOVQ		MM1, 88[ECX]	
	MOVQ		72[EDX], MM7	
END MOVQ6;

PROCEDURE -MOVQ7;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM0, 96[ECX]
	MOVQ		80[EDX], MM3
	MOVQ		MM1, 104[ECX]	
	MOVQ		88[EDX], MM7	
END MOVQ7;

PROCEDURE -MOVQ8;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM0, 112[ECX]
	MOVQ		96[EDX], MM3
	MOVQ		MM1, 120[ECX]	
	MOVQ		104[EDX], MM7	
END MOVQ8;

PROCEDURE -MOVQ9;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		112[EDX], MM3
	MOVQ		MM0, 80[EDX]
	MOVQ		120[EDX], MM7	
END MOVQ9;

PROCEDURE -MOVQ10;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM0, 88[EDX]
	ADD		EDX, 8
END MOVQ10;

(* Pay attention if you change local varss. In the inline procedures there are direct address variable *)
PROCEDURE TransformSSE*(src, dst: LONGINT);
VAR tg116, tg216, tg316, cos416, onecorr, roundinvcol, roundinvcorr, i: LONGINT;
BEGIN	
	
	tg116 := tg116adr;
	tg216 := tg216adr;
	tg316 := tg316adr;
	cos416 := cos416adr;
	onecorr := onecorradr;
	roundinvcol := roundinvcoladr;
	roundinvcorr := roundinvcorradr;
	
	SYSTEM.PUTREG(SYSTEM.ECX, src);	(* MOV ECX, src *)
	SYSTEM.PUTREG(SYSTEM.EDX, dst);	(* MOV EDX, dst *)
	SYSTEM.PUTREG(SYSTEM.EBX, roundinvrowadr);	
	MOVQ1;
	SYSTEM.PUTREG(SYSTEM.ESI, tabi04adr);
	DCT8INVROWSSE;
	MOVQ2;
	SYSTEM.PUTREG(SYSTEM.ESI, tabi17adr);
	DCT8INVROWSSE;
	MOVQ3;
	SYSTEM.PUTREG(SYSTEM.ESI, tabi26adr);
	DCT8INVROWSSE;
	MOVQ4;
	SYSTEM.PUTREG(SYSTEM.ESI, tabi35adr);
	DCT8INVROWSSE;
	MOVQ5;
	SYSTEM.PUTREG(SYSTEM.ESI, tabi04adr);
	DCT8INVROWSSE;
	MOVQ6;
	SYSTEM.PUTREG(SYSTEM.ESI, tabi35adr);
	DCT8INVROWSSE;
	MOVQ7;
	SYSTEM.PUTREG(SYSTEM.ESI, tabi26adr);
	DCT8INVROWSSE;
	MOVQ8;
	SYSTEM.PUTREG(SYSTEM.ESI, tabi17adr);
	DCT8INVROWSSE;
	MOVQ9;				
	DCT8INVCOLSSE;
	MOVQ10;
	DCT8INVCOLSSE;
	
END TransformSSE;

PROCEDURE -PUSHAD;
CODE{SYSTEM.i386}
	PUSHAD	
END PUSHAD;


PROCEDURE -POPAD;
CODE{SYSTEM.i386}
	POPAD
END POPAD;


PROCEDURE -DCT8INVROWSSE;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOVQ		MM2, MM0
	MOVQ		MM3, [ESI]
	PSHUFW	MM0, MM0, 88H	
	MOVQ		MM4, 8[ESI]
	MOVQ		MM5, MM1
	PMADDWD	MM3, MM0
	MOVQ		MM6, 32[ESI]
	PSHUFW	MM1, MM1,  88H
	PMADDWD	MM4, MM1	
	MOVQ		MM7, 40[ESI]
	PSHUFW	MM2, MM2,  0DDH
	PMADDWD	MM6, MM2	
	PSHUFW	MM5, MM5,  0DDH
	PMADDWD	MM7, MM5
	PADDD		MM3, [EBX]				; [EBX] = roundinvrowadr		
	PMADDWD	MM0, 16[ESI]
	PADDD		MM3, MM4
	PMADDWD	MM1, 24[ESI]	
	MOVQ		MM4, MM3
	PMADDWD	MM2, 48[ESI]
	PADDD		MM6, MM7	
	PMADDWD	MM5, 56[ESI]
	PADDD		MM3, MM6
	PADDD		MM0, [EBX]				; [EBX] = roundinvrowadr	
	PSRAD		MM3, SHIFTINVROW	
	PADDD		MM0, MM1
	PSUBD		MM4, MM6	
	MOVQ		MM7, MM0
	PADDD		MM2, MM5
	PADDD		MM0, MM2	
	PSRAD		MM4, SHIFTINVROW	
	PSUBD		MM7, MM2
	PSRAD		MM0, SHIFTINVROW		
	PSRAD		MM7, SHIFTINVROW	
	PACKSSDW	MM3, MM0	
	PACKSSDW	MM7, MM4	
	PSHUFW	MM7, MM7,  0B1H
END DCT8INVROWSSE;

PROCEDURE -DCT8INVCOLSSE;
CODE{SYSTEM.i386, SYSTEM.SSE, SYSTEM.MMX}
	MOV		EDI, -12[EBP]
	MOVQ		MM1, [EDI]
	MOVQ		MM2, MM0
	MOVQ		MM3, 48[EDX]
	PMULHW	MM0, MM1
	MOVQ		MM4, 112[EDX]
	PMULHW	MM1, MM3
	MOV		EDI, -4[EBP]
	MOVQ		MM5, [EDI]
	MOVQ		MM6, MM4
	PMULHW	MM4, MM5
	PADDSW	MM0, MM2
	PMULHW	MM5, 16[EDX]
	PADDSW	MM1, MM3
	MOVQ		MM7, 96[EDX]
	PADDSW	MM0, MM3
	MOV		EDI, -8[EBP]
	MOVQ		MM3, [EDI]
	PSUBSW	MM2, MM1
	PMULHW	MM7, MM3
	MOVQ		MM1, MM0
	PMULHW	MM3, 32[EDX]
	PSUBSW	MM5, MM6
	PADDSW	MM4, 16[EDX]	
	PADDSW	MM0, MM4
	MOV		EDI, -20[EBP]
	PADDSW	MM0, [EDI]
	PSUBSW	MM4, MM1
	PADDSW	MM7, 32[EDX]
	MOVQ		MM6, MM5
	PSUBSW	MM3, 96[EDX]
	PSUBSW	MM5, MM2
	MOV		EDI, -20[EBP]
	PADDSW	MM5, [EDI]
	PADDSW	MM6, MM2
	MOVQ		112[EDX], MM0
	MOVQ		MM1, MM4
	MOV		EDI, -16[EBP]
	MOVQ		MM2, [EDI]
	PADDSW	MM4, MM5
	MOV		EDI, 0[EBP]	
	MOVQ		MM0, -16[EDI]
	PMULHW	MM2, MM4
	MOVQ		48[EDX], MM6
	PSUBSW	MM1, MM5
	MOVQ		MM6, [EDX]
	PMULHW	MM0, MM1
	MOVQ		MM5, 64[EDX]
	PADDSW	MM4, MM2	
	MOV		EDI, -20[EBP]
	POR		MM4, [EDI]
	PADDSW	MM5, MM6
	PSUBSW	MM6, 64[EDX]
	PADDSW	MM0, MM1
	MOV		EDI, -20[EBP]
	POR		MM0, [EDI]
	MOVQ		MM2, MM5
	PADDSW	MM5, MM7
	MOVQ		MM1, MM6
	MOV		EDI, -24[EBP]
	PADDSW	MM5, [EDI]
	PSUBSW	MM2, MM7
	MOVQ		MM7, 112[EDX]
	PADDSW	MM6, MM3
	MOV		EDI, -24[EBP]
	PADDSW	MM6, [EDI]
	PADDSW	MM7, MM5
	PSRAW		MM7, SHIFTINVCOL
	PSUBSW	MM1, MM3
	MOV		EDI, -28[EBP]
	PADDSW	MM2, [EDI]
	MOVQ		MM3, MM6
	MOV		EDI, -28[EBP]
	PADDSW	MM1, [EDI]
	PADDSW	MM6, MM4
	MOVQ		[EDX], MM7
	PSRAW		MM6, SHIFTINVCOL
	MOVQ		MM7, MM1
	PADDSW	MM1, MM0
	MOVQ		16[EDX], MM6
	PSRAW		MM1, SHIFTINVCOL
	MOVQ		MM6, 48[EDX]
	PSUBSW	MM7, MM0
	PADDSW	MM6, MM2
	PSUBSW	MM2, 48[EDX]
	PSRAW		MM7, SHIFTINVCOL
	MOVQ		32[EDX], MM1
	PSRAW		MM6, SHIFTINVCOL
	PSUBSW	MM5, 112[EDX]
	PSRAW		MM2, SHIFTINVCOL
	MOVQ		48[EDX], MM6
	PSUBSW	MM3, MM4
	MOVQ		64[EDX], MM2
	PSRAW		MM3, SHIFTINVCOL
	MOVQ		80[EDX], MM7
	PSRAW		MM5, SHIFTINVCOL
	MOVQ		96[EDX], MM3
	MOVQ		112[EDX], MM5
END DCT8INVCOLSSE;

PROCEDURE TransformINT*(src, dst: LONGINT);
VAR i: LONGINT;
BEGIN		
			
	Row(src + 0);
	Row(src + 16);
	Row(src + 32);
	Row(src + 48);
	Row(src + 64);
	Row(src + 80);
	Row(src + 96);
	Row(src + 112);	

	Col( src +  0);
	Col( src +  2);
	Col( src +  4);
	Col( src +  6);
	Col( src +  8);
	Col( src +  10);
	Col( src +  12);
	Col( src +  14);
			
	FOR i := 0 TO 63 DO
		SYSTEM.PUT16(dst + SIZE(INTEGER) * i, SYSTEM.GET16(src + SIZE(INTEGER) * i) )
	END
	
END TransformINT;



	
(* row (horizontal) IDCT
  
  7                       pi         1 dst[k] = sum c[l] * src[l] * cos( -- *
  	( k + - ) * l ) l=0                      8          2
  
  		where: c[0]    = 128 c[1..7] = 128*sqrt(2) 
*)


PROCEDURE Row( src: LONGINT);
VAR
	x0, x1, x2, x3, x4, x5, x6, x7, x8: LONGINT;
	adr, tempAdr: LONGINT;
BEGIN
	adr := src;
			
	(* shortcut *)
	x1 := LONG(SYSTEM.GET16( adr + 4*SIZE(INTEGER))) * 2048; 
	x2 := LONG(SYSTEM.GET16( adr + 6*SIZE(INTEGER)));
	x3 := LONG(SYSTEM.GET16( adr + 2*SIZE(INTEGER)));
	x4 := LONG(SYSTEM.GET16( adr + 1*SIZE(INTEGER)));
	x5 := LONG(SYSTEM.GET16( adr + 7*SIZE(INTEGER)));
	x6 := LONG(SYSTEM.GET16( adr + 5*SIZE(INTEGER)));
	x7 := LONG(SYSTEM.GET16( adr + 3*SIZE(INTEGER)));
	
	IF ( x1 = 0 ) & ( x2 = 0 ) & ( x3 = 0 ) & ( x4 = 0 ) & ( x5 = 0 ) & ( x6 = 0 ) & ( x7 = 0 )  THEN
		x0 := SYSTEM.GET16( adr ) * 8;
		SYSTEM.PUT16( adr , x0 );
		tempAdr := adr + SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr, SHORT(x0));
		tempAdr := tempAdr + SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr, SHORT(x0));
		tempAdr := tempAdr + SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr, SHORT(x0));
		tempAdr := tempAdr + SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr, SHORT(x0));
		tempAdr := tempAdr + SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr, SHORT(x0));
		tempAdr := tempAdr + SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr, SHORT(x0));
		tempAdr := tempAdr + SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr, SHORT(x0));		
		RETURN
	END;
	x0 := ( LONG(SYSTEM.GET16( adr )) * 2048 ) + 128;    (* for proper rounding in the fourth stage *)

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
	SYSTEM.PUT16( adr, SHORT(( x7 + x1 ) DIV 256));
	tempAdr := adr + SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SHORT(( x3 + x2 ) DIV 256));
	tempAdr := tempAdr + SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SHORT(( x0 + x4 ) DIV 256));
	tempAdr := tempAdr + SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SHORT(( x8 + x6 ) DIV 256));
	tempAdr := tempAdr + SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SHORT(( x8 - x6 ) DIV 256));
	tempAdr := tempAdr + SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SHORT(( x0 - x4 ) DIV 256));
	tempAdr := tempAdr + SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SHORT(( x3 - x2 ) DIV 256));
	tempAdr := tempAdr + SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SHORT(( x7 - x1 ) DIV 256))
END Row;

(* column (vertical) IDCT
 	 
 	 7                         pi         1 dst[8*k] = sum c[l] * src[8*l] *
 	 cos( -- * ( k + - ) * l ) l=0                        8          2
 	 
 	 where: c[0]    = 1/1024 c[1..7] = (1/1024)*sqrt(2) 
*)
PROCEDURE Col( src: LONGINT);
VAR
	x0, x1, x2, x3, x4, x5, x6, x7, x8: LONGINT;
	adr, tempAdr, sourceAdr: LONGINT;
	idx: LONGINT;
BEGIN
	adr := src;
			
	(* shortcut *)
	x1 := LONG(SYSTEM.GET16( adr + 32*SIZE(INTEGER))) * 256; 
	x2 := LONG(SYSTEM.GET16( adr + 48*SIZE(INTEGER)));
	x3 := LONG(SYSTEM.GET16( adr + 16*SIZE(INTEGER)));
	x4 := LONG(SYSTEM.GET16( adr + 8*SIZE(INTEGER)));
	x5 := LONG(SYSTEM.GET16( adr + 56*SIZE(INTEGER)));
	x6 := LONG(SYSTEM.GET16( adr + 40*SIZE(INTEGER)));
	x7 := LONG(SYSTEM.GET16( adr + 24*SIZE(INTEGER)));

	IF ( x1 = 0 ) & ( x2 = 0 ) & ( x3 = 0 ) & ( x4 = 0 ) & ( x5 = 0 ) & ( x6 = 0 ) & ( x7 = 0 )  THEN
		x0 := LONG(intTab[(( SYSTEM.GET16(adr) + 32 ) DIV 64 ) + 512]);
		SYSTEM.PUT16( adr , SHORT(x0));
		tempAdr := adr + 8*SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr , SHORT(x0));
		tempAdr := tempAdr + 8*SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr , SHORT(x0));
		tempAdr := tempAdr + 8*SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr , SHORT(x0));
		tempAdr := tempAdr + 8*SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr , SHORT(x0));
		tempAdr := tempAdr + 8*SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr , SHORT(x0));
		tempAdr := tempAdr + 8*SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr , SHORT(x0));
		tempAdr := tempAdr + 8*SIZE( INTEGER );
		SYSTEM.PUT16( tempAdr , SHORT(x0));
		RETURN
	END;		
	
	 x0 := (LONG(SYSTEM.GET16( adr))* 256) + 8192;
	
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
	sourceAdr := SYSTEM.ADR( intTab[512] );
	SYSTEM.PUT16( tempAdr, SYSTEM.GET16( ( ( ( x7 + x1 ) DIV 16384 )*SIZE(INTEGER) ) + sourceAdr ));
	tempAdr := tempAdr + 8*SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SYSTEM.GET16( ( ( ( x3 + x2 ) DIV 16384 )*SIZE(INTEGER) ) + sourceAdr ));
	tempAdr := tempAdr + 8*SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SYSTEM.GET16( ( ( ( x0 + x4 ) DIV 16384 )*SIZE(INTEGER) ) + sourceAdr ));
	tempAdr := tempAdr + 8*SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SYSTEM.GET16( ( ( ( x8 + x6 ) DIV 16384 )*SIZE(INTEGER) ) + sourceAdr ));
	tempAdr := tempAdr + 8*SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SYSTEM.GET16( ( ( ( x8 - x6 ) DIV 16384 )*SIZE(INTEGER) ) + sourceAdr ));				
	tempAdr := tempAdr + 8*SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SYSTEM.GET16( ( ( ( x0 - x4 ) DIV 16384 )*SIZE(INTEGER) ) + sourceAdr ));
	tempAdr := tempAdr + 8*SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SYSTEM.GET16( ( ( ( x3 - x2 ) DIV 16384 )*SIZE(INTEGER) ) + sourceAdr ));				
	tempAdr := tempAdr + 8*SIZE( INTEGER );
	SYSTEM.PUT16( tempAdr, SYSTEM.GET16( ( ( ( x7 - x1 ) DIV 16384 )*SIZE(INTEGER) ) + sourceAdr ))
END Col;

PROCEDURE FillTablesSSE2;
VAR i: LONGINT;
BEGIN
	NEW(M128onecorr, 12);
	FOR i := 4 TO 11 DO M128onecorr[i] := 1 END;
	onecorradr := SYSTEM.ADR(M128onecorr[4]);
	
	NEW(M128roundinvrow, 12);
	M128roundinvrow[4] := RNDINVROW; M128roundinvrow[5] := 0; M128roundinvrow[6] := RNDINVROW; M128roundinvrow[7] := 0;
	M128roundinvrow[8] := RNDINVROW; M128roundinvrow[9] := 0; M128roundinvrow[10] := RNDINVROW; M128roundinvrow[11] := 0;
	roundinvrowadr := SYSTEM.ADR(M128roundinvrow[4]);

	NEW(M128roundinvcol, 12);
	FOR i := 4 TO 11 DO M128roundinvcol[i] := RNDINVCOL END;
	roundinvcoladr := SYSTEM.ADR(M128roundinvcol[4]);

	NEW(M128roundinvcorr, 12);
	FOR i := 4 TO 11 DO M128roundinvcorr[i] := RNDINVCORR END;
	roundinvcorradr := SYSTEM.ADR(M128roundinvcorr[4]);

	NEW(M128tg116, 12);
	FOR i := 4 TO 11 DO M128tg116[i] := 13036 END;
	tg116adr := SYSTEM.ADR(M128tg116[4]);

	NEW(M128tg216, 12);
	FOR i := 4 TO 11 DO M128tg216[i] := 21746 END;
	tg216adr := SYSTEM.ADR(M128tg216[4]);
	
	NEW(M128tg316, 12);
	FOR i := 4 TO 11 DO M128tg316[i] := -21746 END;
	tg316adr := SYSTEM.ADR(M128tg316[4]);
		
	NEW(M128cos416, 12);
	FOR i := 4 TO 11 DO M128cos416[i] := -19195 END;
	cos416adr := SYSTEM.ADR(M128cos416[4]);
	
	NEW(M128tabi04, 36);
	M128tabi04[4] 	:= 16384; 	M128tabi04[5] 	:= 21407; 	M128tabi04[6] 	:= 16384; 	M128tabi04[7] := 8867;	
	M128tabi04[8] 	:= 16384; 	M128tabi04[9] 	:= -8867; 	M128tabi04[10]	:= 16384; 	M128tabi04[11] := -21407;	
	M128tabi04[12] := 16384; 	M128tabi04[13]	:= 8867; 	M128tabi04[14] := -16384; 	M128tabi04[15] := -21407;	
	M128tabi04[16] := -16384; 	M128tabi04[17] := 21407; 	M128tabi04[18] := 16384; 	M128tabi04[19] := -8867;	
	M128tabi04[20] := 22725; 	M128tabi04[21]	:= 19266; 	M128tabi04[22]	:= 19266; 	M128tabi04[23] := -4520;	
	M128tabi04[24] := 12873; 	M128tabi04[25]	:= -22725; 	M128tabi04[26]	:= 4520; 	M128tabi04[27] := -12873;	
	M128tabi04[28] := 12873; 	M128tabi04[29]	:= 4520; 	M128tabi04[30] := -22725; 	M128tabi04[31] := -12873;	
	M128tabi04[32] := 4520; 	M128tabi04[33] := 19266; 	M128tabi04[34] := 19266; 	M128tabi04[35] := -22725;	
	tabi04adr := SYSTEM.ADR(M128tabi04[4]);
		
	NEW(M128tabi17, 36);
	M128tabi17[4] 	:= 22725; 	M128tabi17[5] 	:= 29692; 	M128tabi17[6] 	:= 22725; 	M128tabi17[7] := 12299;	
	M128tabi17[8] 	:= 22725; 	M128tabi17[9] 	:= -12299; 	M128tabi17[10] := 22725; 	M128tabi17[11] := -29692;	
	M128tabi17[12] := 22725; 	M128tabi17[13] := 12299; 	M128tabi17[14] := -22725; 	M128tabi17[15] := -29692;	
	M128tabi17[16] := -22725; 	M128tabi17[17] := 29692; 	M128tabi17[18] := 22725; 	M128tabi17[19] := -12299;	
	M128tabi17[20] := 31521; 	M128tabi17[21]	:= 26722; 	M128tabi17[22]	:= 26722; 	M128tabi17[23] := -6270;	
	M128tabi17[24] := 17855; 	M128tabi17[25]	:= -31521; 	M128tabi17[26]	:= 6270; 	M128tabi17[27] := -17855;	
	M128tabi17[28] := 17855; 	M128tabi17[29]	:= 6270; 	M128tabi17[30] := -31521; 	M128tabi17[31] := -17855;	
	M128tabi17[32] := 6270; 	M128tabi17[33] := 26722; 	M128tabi17[34] := 26722; 	M128tabi17[35] := -31521;		
	tabi17adr := SYSTEM.ADR(M128tabi17[4]);
	
	NEW(M128tabi26, 36);
	M128tabi26[4] 	:= 21407; 	M128tabi26[5] 	:= 27969; 	M128tabi26[6] 	:= 21407; 	M128tabi26[7] := 11585;	
	M128tabi26[8] 	:= 21407; 	M128tabi26[9] 	:= -11585; 	M128tabi26[10] := 21407; 	M128tabi26[11] := -27969;	
	M128tabi26[12] := 21407; 	M128tabi26[13] := 11585; 	M128tabi26[14] := -21407; 	M128tabi26[15] := -27969;	
	M128tabi26[16] := -21407; 	M128tabi26[17] := 27969; 	M128tabi26[18] := 21407; 	M128tabi26[19] := -11585;	
	M128tabi26[20] := 29692; 	M128tabi26[21]	:= 25172; 	M128tabi26[22]	:= 25172; 	M128tabi26[23] := -5906;	
	M128tabi26[24] := 16819; 	M128tabi26[25]	:= -29692; 	M128tabi26[26]	:= 5906; 	M128tabi26[27] := -16819;	
	M128tabi26[28] := 16819; 	M128tabi26[29]	:= 5906; 	M128tabi26[30] := -29692; 	M128tabi26[31] := -16819;	
	M128tabi26[32] := 5906; 	M128tabi26[33] := 25172; 	M128tabi26[34] := 25172; 	M128tabi26[35] := -29692;	
	tabi26adr := SYSTEM.ADR(M128tabi26[4]);

	NEW(M128tabi35, 36);
	M128tabi35[4] 	:= 19266; 	M128tabi35[5] 	:= 25172; 	M128tabi35[6] 	:= 19266; 	M128tabi35[7] := 10426;	
	M128tabi35[8] 	:= 19266; 	M128tabi35[9] 	:= -10426; 	M128tabi35[10] := 19266; 	M128tabi35[11] := -25172;	
	M128tabi35[12] := 19266; 	M128tabi35[13]	:= 10426; 	M128tabi35[14] := -19266; 	M128tabi35[15] := -25172;	
	M128tabi35[16] := -19266; 	M128tabi35[17] := 25172; 	M128tabi35[18] := 19266; 	M128tabi35[19] := -10426;	
	M128tabi35[20] := 26722; 	M128tabi35[21]	:= 22654; 	M128tabi35[22]	:= 22654; 	M128tabi35[23] := -5315;	
	M128tabi35[24] := 15137; 	M128tabi35[25]	:= -26722; 	M128tabi35[26]	:= 5315; 	M128tabi35[27] := -15137;	
	M128tabi35[28] := 15137; 	M128tabi35[29]	:= 5315; 	M128tabi35[30] := -26722; 	M128tabi35[31] := -15137;	
	M128tabi35[32] := 5315; 	M128tabi35[33] := 22654; 	M128tabi35[34] := 22654; 	M128tabi35[35] := -26722;	
	tabi35adr := SYSTEM.ADR(M128tabi35[4]);

END FillTablesSSE2;

PROCEDURE FillTablesSSE;
VAR i: LONGINT;
BEGIN	
	NEW(M128onecorr, 4);
	FOR i := 0 TO 3 DO M128onecorr[i] := 1 END;
	onecorradr := SYSTEM.ADR(M128onecorr[0]);
	
	NEW(M128roundinvrow, 4);
	M128roundinvrow[0] := RNDINVROW; M128roundinvrow[1] := 0; M128roundinvrow[2] := RNDINVROW; M128roundinvrow[3] := 0;
	roundinvrowadr := SYSTEM.ADR(M128roundinvrow[0]);

	NEW(M128roundinvcol, 4);
	FOR i := 0 TO 3 DO M128roundinvcol[i] := RNDINVCOL END;
	roundinvcoladr := SYSTEM.ADR(M128roundinvcol[0]);

	NEW(M128roundinvcorr, 4);
	FOR i := 0 TO 3 DO M128roundinvcorr[i] := RNDINVCORR END;
	roundinvcorradr := SYSTEM.ADR(M128roundinvcorr[0]);

	NEW(M128tg116, 4);
	FOR i := 0 TO 3 DO M128tg116[i] := 13036 END;
	tg116adr := SYSTEM.ADR(M128tg116[0]);

	NEW(M128tg216, 4);
	FOR i := 0 TO 3 DO M128tg216[i] := 21746 END;
	tg216adr := SYSTEM.ADR(M128tg216[0]);
	
	NEW(M128tg316, 4);
	FOR i := 0 TO 3 DO M128tg316[i] := -21746 END;
	tg316adr := SYSTEM.ADR(M128tg316[0]);
		
	NEW(M128cos416, 4);
	FOR i := 0 TO 3 DO M128cos416[i] := -19195 END;
	cos416adr := SYSTEM.ADR(M128cos416[0]);
	
	NEW(M128tabi04, 32);
	M128tabi04[0] 	:= 16384; 	M128tabi04[1] 	:= 21407; 	M128tabi04[2] 	:= 16384; 	M128tabi04[3] 	:= 8867;	
	M128tabi04[4] 	:= 16384; 	M128tabi04[5] 	:= 8867; 	M128tabi04[6]	:= -16384; 	M128tabi04[7] 	:= -21407;	
	M128tabi04[8] 	:= 16384; 	M128tabi04[9]	:= -8867; 	M128tabi04[10] := 16384; 	M128tabi04[11] := -21407;	
	M128tabi04[12] := -16384; 	M128tabi04[13] := 21407; 	M128tabi04[14] := 16384; 	M128tabi04[15] := -8867;	
	M128tabi04[16] := 22725; 	M128tabi04[17]	:= 19266; 	M128tabi04[18]	:= 19266; 	M128tabi04[19] := -4520;	
	M128tabi04[20] := 12873; 	M128tabi04[21]	:= 4520; 	M128tabi04[22]	:= -22725; 	M128tabi04[23] := -12873;	
	M128tabi04[24] := 12873; 	M128tabi04[25]	:= -22725; 	M128tabi04[26] := 4520; 	M128tabi04[27] := -12873;	
	M128tabi04[28] := 4520; 	M128tabi04[29] := 19266; 	M128tabi04[30] := 19266; 	M128tabi04[31] := -22725;	
	tabi04adr := SYSTEM.ADR(M128tabi04[0]);
		
	NEW(M128tabi17, 32);
	M128tabi17[0] 	:= 22725; 	M128tabi17[1] 	:= 29692; 	M128tabi17[2] 	:= 22725; 	M128tabi17[3] 	:= 12299;	
	M128tabi17[4] 	:= 22725; 	M128tabi17[5] 	:= 12299; 	M128tabi17[6] := -22725; 	M128tabi17[7] 	:= -29692;	
	M128tabi17[8] 	:= 22725; 	M128tabi17[9] 	:= -12299; 	M128tabi17[10] := 22725; 	M128tabi17[11] := -29692;	
	M128tabi17[12] := -22725; 	M128tabi17[13] := 29692; 	M128tabi17[14] := 22725; 	M128tabi17[15] := -12299;	
	M128tabi17[16] := 31521; 	M128tabi17[17]	:= 26722; 	M128tabi17[18]	:= 26722; 	M128tabi17[19] := -6270;	
	M128tabi17[20] := 17855; 	M128tabi17[21]	:= 6270; 	M128tabi17[22]	:= -31521; 	M128tabi17[23] := -17855;	
	M128tabi17[24] := 17855; 	M128tabi17[25]	:= -31521; 	M128tabi17[26] := 6270; 	M128tabi17[27] := -17855;	
	M128tabi17[28] := 6270; 	M128tabi17[29] := 26722; 	M128tabi17[30] := 26722; 	M128tabi17[31] := -31521;		
	tabi17adr := SYSTEM.ADR(M128tabi17[0]);
	
	NEW(M128tabi26, 32);
	M128tabi26[0] 	:= 21407; 	M128tabi26[1] 	:= 27969; 	M128tabi26[2] 	:= 21407; 	M128tabi26[3] 	:= 11585;	
	M128tabi26[4] 	:= 21407; 	M128tabi26[5] 	:= 11585; 	M128tabi26[6] := -21407; 	M128tabi26[7] 	:= -27969;	
	M128tabi26[8] 	:= 21407; 	M128tabi26[9] 	:= -11585; 	M128tabi26[10] := 21407; 	M128tabi26[11] := -27969;	
	M128tabi26[12] := -21407; 	M128tabi26[13] := 27969; 	M128tabi26[14] := 21407; 	M128tabi26[15] := -11585;	
	M128tabi26[16] := 29692; 	M128tabi26[17]	:= 25172; 	M128tabi26[18]	:= 25172; 	M128tabi26[19] := -5906;	
	M128tabi26[20] := 16819; 	M128tabi26[21]	:= 5906; 	M128tabi26[22]	:= -29692; 	M128tabi26[23] := -16819;	
	M128tabi26[24] := 16819; 	M128tabi26[25]	:= -29692; 	M128tabi26[26] := 5906; 	M128tabi26[27] := -16819;	
	M128tabi26[28] := 5906; 	M128tabi26[29] := 25172; 	M128tabi26[30] := 25172; 	M128tabi26[31] := -29692;	
	tabi26adr := SYSTEM.ADR(M128tabi26[0]);

	NEW(M128tabi35, 32);
	M128tabi35[0] 	:= 19266; 	M128tabi35[1] 	:= 25172; 	M128tabi35[2] 	:= 19266; 	M128tabi35[3] 	:= 10426;	
	M128tabi35[4] 	:= 19266; 	M128tabi35[5] 	:= 10426; 	M128tabi35[6] 	:= -19266; 	M128tabi35[7] 	:= -25172;	
	M128tabi35[8] 	:= 19266; 	M128tabi35[9]	:= -10426; 	M128tabi35[10] := 19266; 	M128tabi35[11] := -25172;	
	M128tabi35[12] := -19266; 	M128tabi35[13] := 25172; 	M128tabi35[14] := 19266; 	M128tabi35[15] := -10426;	
	M128tabi35[16] := 26722; 	M128tabi35[17]	:= 22654; 	M128tabi35[18]	:= 22654; 	M128tabi35[19] := -5315;	
	M128tabi35[20] := 15137; 	M128tabi35[21]	:= 5315; 	M128tabi35[22]	:= -26722; 	M128tabi35[23] := -15137;	
	M128tabi35[24] := 15137; 	M128tabi35[25]	:= -26722; 	M128tabi35[26] := 5315; 	M128tabi35[27] := -15137;	
	M128tabi35[28] := 5315; 	M128tabi35[29] := 22654; 	M128tabi35[30] := 22654; 	M128tabi35[31] := -26722;	
	tabi35adr := SYSTEM.ADR(M128tabi35[0]);
END FillTablesSSE;

PROCEDURE FillTablesINT;
VAR i: INTEGER;
BEGIN
	NEW(intTab, 1024);
	FOR i := -512 TO 511 DO
		IF i < -256 THEN
			intTab[i + 512] := -256
		ELSIF i > 255 THEN
			intTab[i + 512] := 255
		ELSE
			intTab[i + 512] := i
		END;
	END;
END FillTablesINT;



PROCEDURE CheckFeatures;
BEGIN
	IF AosBoot.SSE2Support THEN
		FillTablesSSE2;
		Transform := TransformSSE2;
		status := SSE2;		
		AosOut.String("IDCT: SSE2 method"); AosOut.Ln; 
	ELSIF AosBoot.SSESupport THEN
		FillTablesSSE;
		Transform := TransformSSE;
		status := SSE;
		AosOut.String("IDCT: SSE method"); AosOut.Ln; 
	ELSE
		FillTablesINT;
		Transform := TransformINT;
		status := INT;
		AosOut.String("IDCT: INT method"); AosOut.Ln; 
	END	
END CheckFeatures;

(* !!! Unsafe *)
PROCEDURE Change*(par : ANY) : ANY;
VAR  s: AosIO.StringReader; 	interval, i: LONGINT; name: ARRAY 12 OF CHAR;
BEGIN			
	WITH par: AosCommands.Parameters DO
		NEW(s, LEN(par.str^)); s.Set(par.str^)
	END;
	
	s.SkipSpaces; s.String(name);			
	
	IF name = "SSE2" THEN
		FillTablesSSE2;
		Transform := TransformSSE2;
		status := SSE2;
		AosOut.String("IDCT: SSE2 method"); AosOut.Ln; 
	ELSIF name = "SSE" THEN
		FillTablesSSE;	
		Transform := TransformSSE;
		status := SSE;
		AosOut.String("IDCT: SSE method"); AosOut.Ln; 
	ELSIF name = "INT" THEN
		FillTablesINT;	
		Transform := TransformINT;
		status := INT;	
		AosOut.String("IDCT: INT method"); AosOut.Ln; 
	ELSE
		CheckFeatures;
	END;
	
	RETURN NIL
END Change;


BEGIN
	RNDINVROW := 1024 * (6 - BITSINVACC);
	RNDINVCOL := 16 * (BITSINVACC - 3);
	RNDINVCORR := RNDINVCOL - 1;
	CheckFeatures;
END IDCT.

IDCT.Change INT ~
IDCT.Change SSE ~
IDCT.Change SSE2 ~

IDCT.Obx ~
S.Free IDCT ~