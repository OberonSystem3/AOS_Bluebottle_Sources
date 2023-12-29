MODULE AosS3Aurora64; (** AUTHOR "rlaich"; PURPOSE "S3 Aurora64 bank-switching display driver"; *)

IMPORT SYSTEM, AosBoot, AosOut, AosMemory,  AosDisplays;

CONST WinSize = 10000H; BankAdr = 0A0000H;

TYPE Display = OBJECT (AosDisplays.Display)
							VAR curBank, base, vbstride : LONGINT;
							
							PROCEDURE Transfer*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, op: LONGINT);
							VAR bufadr, dispadr, vofs, bank, h0, left : LONGINT;
							BEGIN{EXCLUSIVE}
								IF w > 0 THEN
									bufadr := SYSTEM.ADR(buf[ofs]);
									dispadr :=  ((y*width)+x)*format;
									vofs := dispadr MOD WinSize;
									w:= w*format;
									REPEAT
										bank := dispadr DIV WinSize; vofs := dispadr MOD WinSize;
										IF bank # curBank THEN switch( bank ); curBank := bank END;
										left := WinSize - vofs;
										h0 := left DIV vbstride;	(* h0 = lines that will fit in window *)
										IF h0 > h THEN h0 := h
										ELSIF (h0 = 0) & (left >= w) THEN h0 := 1
										END;
										INC( vofs, base );
										IF h0#0 THEN
											INC( dispadr, h0*vbstride); DEC( h, h0 );
											REPEAT
												IF op = AosDisplays.get THEN CopyAlignSrc(vofs, bufadr, w)
												ELSE CopyAlignDst(bufadr, vofs, w) END;
												DEC(h0);  INC(vofs, vbstride);  INC(bufadr, stride )
											UNTIL h0 = 0
										ELSE (* h0=0 *)
											INC( dispadr, vbstride ); DEC( h );
											IF op = AosDisplays.get THEN CopyAlignSrc(vofs, bufadr, left)
											ELSE CopyAlignDst(bufadr, vofs, left) END;
											switch(bank+1);											
											IF op = AosDisplays.get THEN CopyAlignSrc( base, bufadr+left, w-left )
											ELSE CopyAlignDst(bufadr+left, base, w-left) END;
											INC( bufadr, stride )											
										END
									UNTIL h = 0							
								END
							END Transfer;
							
							PROCEDURE switch(bank: LONGINT);
								VAR b: SET;  p: LONGINT;
							BEGIN
								curBank := bank;
								SYSTEM.PORTOUT(3C4H, 4X);
								SYSTEM.PORTIN(3C5H, SYSTEM.VAL(CHAR, b));
								IF ~(3 IN b) THEN bank := bank*4 END;
								
								SYSTEM.PORTIN(3CCH, SYSTEM.VAL(CHAR, b));
								IF 0 IN b THEN p := 3D4H ELSE p := 3B4H END;
								
								SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 4838H));
								SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 0A539H));
							
								SYSTEM.PORTIN(3CCH, SYSTEM.VAL(CHAR, b));
								IF 0 IN b THEN p := 3D4H ELSE p := 3B4H END;
							
								SYSTEM.PORTOUT(p, 6AX);
								SYSTEM.PORTIN(p+1, SYSTEM.VAL(CHAR, b));
								b := SYSTEM.LSH((b * {6,7}) + SYSTEM.VAL(SET, bank), 8) + SYSTEM.VAL(SET, 6AH);
								SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, b))
							END switch;
	
							
						END Display;
		
VAR single : Display;


(* CopyAlignDst - Like SYSTEM.MOVE, but aligns destination 4-byte values in inner loop. 
	this is taken from SVGA.Display.Mod
*)

PROCEDURE CopyAlignDst(src, dst, size: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, src[EBP]
	MOV EDI, dst[EBP]
	MOV ECX, size[EBP]
	CLD
	TEST ECX, ECX
	JZ exit
	
	TEST EDI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
	TEST EDI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
	TEST EDI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
ok:
	MOV EAX, ECX
	SHR ECX, 2	; size DIV 4
	AND EAX, 3	; size MOD 4
	REP MOVSD
	
	MOV ECX, EAX
	REP MOVSB
exit:
END CopyAlignDst;

(* CopyAlignSrc - Like SYSTEM.MOVE, but aligns source to 4-byte values in inner loop. 
	this is taken form SVGA.Display.Mod
*)

PROCEDURE CopyAlignSrc(src, dst, size: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, src[EBP]
	MOV EDI, dst[EBP]
	MOV ECX, size[EBP]
	CLD
	TEST ECX, ECX
	JZ exit
	
	TEST ESI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
	TEST ESI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
	TEST ESI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
ok:
	MOV EAX, ECX
	SHR ECX, 2	; size DIV 4
	AND EAX, 3	; size MOD 4
	REP MOVSD
	
	MOV ECX, EAX
	REP MOVSB
exit:
END CopyAlignSrc;

PROCEDURE Install*;
BEGIN
	(*IF single # NIL THEN AosDisplays.main := single END*)
END Install;


PROCEDURE InitPalette;
VAR col: LONGINT; ch: CHAR;
BEGIN
	SYSTEM.PORTIN(3DAH, ch);
	SYSTEM.PORTOUT(3C0H, 11X);
	SYSTEM.PORTOUT(3C0H, 0X);	(* palette entry 0 is black *)
	SYSTEM.PORTOUT(3C0H, 20X);
	FOR col := 0 TO 255 DO
		SYSTEM.PORTOUT(3C8H, CHR(col));
		SYSTEM.PORTOUT(3C9H, CHR(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, col) * {5..7}) DIV 4));
		SYSTEM.PORTOUT(3C9H, CHR(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, ASH(col, 7-4)) * {5..7}) DIV 4));
		SYSTEM.PORTOUT(3C9H, CHR(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, ASH(col, 7-1)) * {6..7}) DIV 4))
	END
END InitPalette;


PROCEDURE Init;
VAR dmem, p, res: LONGINT;
	buffer : ARRAY 32 OF CHAR;
BEGIN
	AosOut.String("S3 Aurora:"); 
	NEW( single ); single.curBank := -1;	 
	AosMemory.MapPhysical( BankAdr, WinSize, single.base );
	single.format := AosDisplays.index8; single.unit := 10000;
	single.width := 800; single.height :=600;
	(* init??, offscreen ??, fbsize ??, fbstride?? *)
	AosBoot.GetConfig("DMem", buffer );
	IF buffer[0] = 0X THEN dmem := 800*600*single.format;
	ELSE p := 0; dmem := AosBoot.StrToInt( p, buffer ) END;
	single.offscreen := dmem DIV single.format DIV single.width - single.height;
	single.vbstride := single.width*single.format;
	InitPalette;
	single.desc := "S3 Aurora64 display driver";
	AosDisplays.registry.Add(single, res);
	ASSERT(res = 0)
END Init;

BEGIN
	Init;
END AosS3Aurora64.

Compiler.Compile AosS3Aurora64.Mod \.Obx