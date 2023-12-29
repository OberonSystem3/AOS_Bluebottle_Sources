(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosDisplayLinear; (** AUTHOR "pjm"; PURPOSE "Linear framebuffer display driver"; *)

(*
Config strings:
	DWidth=1024	Display width
	DHeight=768	Display height
	DDepth=16	Display depth
	DMem=?	Display memory size in bytes
	Init=?	Init program.
	
The Init program is a 8086 machine code program in hexadecimal.  It has to initialize the specified display mode, possibly by making display BIOS calls, and leave the 32-bit physical address of the frame buffer in DX:CX.
*)

IMPORT SYSTEM, AosBoot, AosOut, AosMemory, AosMemCache, AosDisplays, Utilities;

VAR
	d: AosDisplays.Display;

PROCEDURE GetVal(name: ARRAY OF CHAR;  default: LONGINT): LONGINT;
VAR v: LONGINT;  s: ARRAY 10 OF CHAR;  p: LONGINT;
BEGIN
	AosBoot.GetConfig(name, s);
	IF s[0] = 0X THEN
		v := default
	ELSE
		p := 0;  v := AosBoot.StrToInt(p, s)
	END;
	RETURN v
END GetVal;

PROCEDURE Install*;
BEGIN
	(*IF d # NIL THEN AosDisplays.main := d END*)
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
VAR w, h, f, mem, padr, vadr, res: LONGINT; ts : ARRAY 16 OF CHAR;
BEGIN
	w := GetVal("DWidth", 1024); h := GetVal("DHeight", 768);
	CASE GetVal("DDepth", 16) DIV 8 OF
		1: f := AosDisplays.index8; InitPalette
		|2: f := AosDisplays.color565
		|3: f := AosDisplays.color888
		|4: f := AosDisplays.color8888
	END;
	mem := GetVal("DMem", 0)*1024;
	IF mem = 0 THEN	(* compute default *)
		mem := 512*1024;
		WHILE w*h*f >= mem DO mem := mem*2 END
	END;
	AosBoot.GetInit(1, padr);	(* DX:CX from Init code *)
	ASSERT((padr # 0) & (padr MOD 4096 = 0));
	IF GetVal("DCache", 1) = 1 THEN
		AosMemCache.GlobalSetCacheProperties(padr, mem, AosMemCache.WC, res);
		IF res # 0 THEN
			AosOut.Enter; AosOut.String("AosDisplayLinear: GlobalSetCacheProperties = ");
			AosOut.Int(res, 1); AosOut.Exit
		END
	END;
	AosOut.ScreenOff;
	AosMemory.MapPhysical(padr, mem, vadr);
	AosBoot.Fill32(vadr, mem, 0);	(* clear video memory *)
	NEW(d);
	d.width := w; d.height := h; d.offscreen := mem DIV (w*f) - h;
	d.format := f; d.unit := 10000;
	d.InitFrameBuffer(vadr, mem);
	d.desc := "Generic linear framebuffer driver (";
	Utilities.IntToStr(d.width, ts); Utilities.Append(d.desc, ts); 
	Utilities.Append(d.desc, "x");
	Utilities.IntToStr(d.height, ts);  Utilities.Append(d.desc, ts); 
	Utilities.Append(d.desc, "x");
	Utilities.IntToStr(d.format, ts);  Utilities.Append(d.desc, ts); 
	Utilities.Append(d.desc, ")");
	AosDisplays.registry.Add(d, res);
	ASSERT(res = 0)
END Init;

BEGIN
	Init; Install
END AosDisplayLinear.

