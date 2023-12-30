(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosOut; (** AUTHOR "pjm"; PURPOSE "Trace output for booting and debugging"; *)

(* AFI 12.03.2003 - procedure Init modified to obtain trace port info from Aos.Par i.o. being hardcoded. *)

IMPORT SYSTEM, AosBoot, AosLocks;

CONST
	Screen = 0; V24 = 2;	(* TraceMode options *)
	
	BufSize = 8000;	(* default trace buffer size (usually overriden by System.StartLog or LogWindow.Open *)
	
VAR
	tbase: LONGINT;	(* trace base port, 3F8H=com1, 2F8H=com2, etc. *)
	wbase, wsize, wpos, wlen: LONGINT;
	traceBufDef: ARRAY BufSize OF CHAR;	(* default trace buffer *)
	traceBufAdr, traceBufSize: LONGINT;	(* current trace buffer virtual addresses *)
	traceHead, traceTail: LONGINT;
	tmode: SET;	(* {V24, Screen, ...} *)
	crlf: ARRAY 2 OF CHAR;
	column*: LONGINT;	(** hint for AosTrap *)
	
(* Set com port speed. *)

PROCEDURE Setup(speed: LONGINT);
BEGIN
	SYSTEM.PORTOUT(tbase+3, 80X);	(* Set the Divisor Latch Bit - DLAB = 1 *)
	speed := 115200 DIV speed;	(* compiler DIV/PORTOUT bug workaround *)
	SYSTEM.PORTOUT(tbase+1, CHR(ASH(speed, -8)));	(* Set the Divisor Latch MSB *)
	SYSTEM.PORTOUT(tbase, CHR(speed));	(* Set the Divisor Latch LSB *)
	SYSTEM.PORTOUT(tbase+3, 3X);	(* 8N1 *)
	SYSTEM.PORTOUT(tbase+4, 3X);	(* Set DTR, RTS on in the MCR *)
	SYSTEM.PORTOUT(tbase+1, 0X)	(* Disable receive interrupts *)
END Setup;

(* Initialise tracing. *)

PROCEDURE Init;
VAR i, p, width, height, tspeed, noOfPorts, dummy: LONGINT; s, name: ARRAY 32 OF CHAR;
		tbaselist: ARRAY 8 OF LONGINT;
BEGIN
	crlf[0] := 0DX; crlf[1] := 0AX;
	traceBufAdr := SYSTEM.ADR(traceBufDef[0]);
	traceBufSize := LEN(traceBufDef);
	traceHead := 0; traceTail := 0; column := 0;
	AosBoot.GetConfig("TraceMode", s);
	p := 0; tmode := SYSTEM.VAL(SET, AosBoot.StrToInt(p, s));
	AosBoot.GetConfig("TraceMem", s);
	width := 0; height := 25;
	p := 0; wbase := AosBoot.StrToInt(p, s);
	IF s[p] = "," THEN
		INC(p); width := AosBoot.StrToInt(p, s);
		IF s[p] = "," THEN
			INC(p); height := AosBoot.StrToInt(p, s)
		END
	END;
	IF width < 10 THEN width := 80; height := 25 END;	(* also catches old syntax base,windows,width,height *)
	IF wbase = 0 THEN wbase := 0B8000H END;
	wlen := width*2;	(* line length in bytes *)
	wsize := wlen*height;
	wpos := 0;	(* start position *)
	IF Screen IN tmode THEN	(* init screen *)
		FOR i := 0 TO wsize-2 BY 2 DO SYSTEM.PUT16(wbase + i, 256*7H+32) END;
			(* init cursor *)
		SYSTEM.PORTOUT(3D4H, 0EX);
		SYSTEM.PORTOUT(3D5H, CHR((width*height) DIV 100H));
		SYSTEM.PORTOUT(3D4H, 0FX);
		SYSTEM.PORTOUT(3D5H, CHR((width*height) MOD 100H))
	END;
		(* configure V24 *)
	noOfPorts := 0;
	FOR i := 0 TO 7 DO
		COPY("COM ", name);
		name[3] := CHR(ORD("1") + i);
		AosBoot.GetConfig(name, s);
		p := 0;
		tbaselist[i] := AosBoot.StrToInt(p, s);
		IF s[p] = "," THEN
			INC(p); dummy := AosBoot.StrToInt(p, s)
		END;
		IF tbaselist[i] # 0 THEN
			INC(noOfPorts)
		END
	END;
	IF tbaselist[0] = 0 THEN tbaselist[0] := 3F8H END;	(* COM1 port default values *)
	IF tbaselist[1] = 0 THEN tbaselist[1] := 2F8H END;	(* COM2 port default values *)
	AosBoot.GetConfig("TracePort", s);
	p := 0; p := AosBoot.StrToInt(p, s); DEC(p);
	IF (p < noOfPorts) & (p >= 0) THEN tbase := tbaselist[p]
	ELSE tbase := tbaselist[0]
	END;
	AosBoot.GetConfig("TraceBPS", s);
	p := 0; tspeed := AosBoot.StrToInt(p, s);
	IF tspeed <= 0 THEN tspeed := 38400 END;
	IF V24 IN tmode THEN
		ASSERT((tbase > 0) & (tspeed > 0));
		Setup(tspeed)
	END
END Init;

(* Write a character to the serial port. *)

PROCEDURE Write(c: CHAR);
VAR status: SET;
BEGIN
	REPEAT	(* wait until port is ready to accept a character *)
		SYSTEM.PORTIN(tbase+5, SYSTEM.VAL(CHAR, status))
	UNTIL 5 IN status;	(* THR empty *)
	SYSTEM.PORTOUT(tbase, c)
END Write;

(* Scroll the display up. *)

PROCEDURE ScrollUp;
VAR y, adr: LONGINT;
BEGIN
	adr := wbase + wlen;
	SYSTEM.MOVE(adr, adr-wlen, wsize-wlen);
	adr := wbase + wsize - wlen;
	FOR y := 0 TO wlen-2 BY 2 DO SYSTEM.PUT16(adr + y, 256*7H+32) END
END ScrollUp;

(** Send the specified characters to the trace output (cf. AosIO.Sender). *)

PROCEDURE Send*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
VAR next: LONGINT; c: CHAR;
BEGIN
	INC(len, ofs);	(* len is now end position *)
	AosLocks.Acquire(AosLocks.AosOutLow);
	LOOP
		IF ofs >= len THEN EXIT END;
		c := buf[ofs];
		IF c = 0X THEN EXIT END;
		IF c = 0AX THEN column := 0 ELSE INC(column) END;
		next := (traceTail+1) MOD traceBufSize;
		IF next # traceHead THEN
			SYSTEM.PUT8(traceBufAdr+traceTail, c);
			traceTail := next
		ELSE	(* overwrite previous character with overflow signal *)
			SYSTEM.PUT8(traceBufAdr + (traceTail-1) MOD traceBufSize, 3X)
		END;
		IF Screen IN tmode THEN	(* memory tracing on *)
			IF c = 9X THEN c := 20X END;
			IF c = 0DX THEN	(* CR *)
				DEC(wpos, wpos MOD wlen)
			ELSIF c = 0AX THEN	(* LF *)
				IF wpos < wsize THEN
					INC(wpos, wlen)	(* down to next line *)
				ELSE
					ScrollUp
				END
			ELSE
				IF wpos >= wsize THEN
					ScrollUp;
					DEC(wpos, wlen)
				END;
				SYSTEM.PUT16(wbase + wpos, 256*7H + ORD(c));
				INC(wpos, 2)
			END
		END;
		IF V24 IN tmode THEN	(* V24 tracing on *)
			Write(c)
		END;
		INC(ofs)
	END;
	AosLocks.Release(AosLocks.AosOutLow)
END Send;

(** Write a string to the trace output. *)

PROCEDURE String*(s: ARRAY OF CHAR);
VAR len, n: LONGINT;
BEGIN
	len := 0; n := LEN(s);
	WHILE (len # n) & (s[len] # 0X) DO INC(len) END;
	Send(s, 0, len, FALSE, n)	(* ignore res *)
END String;

(** Skip to the next line on trace output. *)

PROCEDURE Ln*;
BEGIN
	String(crlf)
END Ln;

(** Write a character. *)

PROCEDURE Char*(c: CHAR);
TYPE Str = ARRAY 1 OF CHAR;
BEGIN
	String(SYSTEM.VAL(Str, c))
END Char;

(** Write "x" as a decimal number. "w" is the field width. *)

PROCEDURE Int*(x, w: LONGINT);
VAR i, x0: LONGINT; a: ARRAY 12 OF CHAR;
BEGIN
	IF x < 0 THEN
		IF x = MIN(LONGINT) THEN
			DEC(w, 11);
			WHILE w > 0 DO Char(" "); DEC(w) END;
			String("-2147483648");
			RETURN
		ELSE
			DEC(w); x0 := -x
		END
	ELSE
		x0 := x
	END;
	i := 0;
	REPEAT
		a[i] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(i)
	UNTIL x0 = 0;
	WHILE w > i DO Char(" "); DEC(w) END;
	IF x < 0 THEN Char("-") END;
	REPEAT DEC(i); Char(a[i]) UNTIL i = 0
END Int;

PROCEDURE Boolean*(x : BOOLEAN);
BEGIN
	IF x THEN String("TRUE") ELSE String("FALSE") END
END Boolean;

(** Write "x" as a decimal number with a power-of-two multiplier (K, M or G), followed by "suffix". "w" is the field width, excluding "suffix". *)

PROCEDURE IntSuffix*(x, w: LONGINT; suffix: ARRAY OF CHAR);
CONST K = 1024; M = K*K; G = K*M;
VAR mult: CHAR;
BEGIN
	IF x MOD K # 0 THEN
		Int(x, w)
	ELSE
		IF x MOD M # 0 THEN mult := "K"; x := x DIV K
		ELSIF x MOD G # 0 THEN mult := "M"; x := x DIV M
		ELSE mult := "G"; x := x DIV G
		END;
		Int(x, w-1); Char(mult)
	END;
	String(suffix)
END IntSuffix;

(** Write "x" as a hexadecimal number. The absolute value of "w" is the field width. If "w" is negative, two hex digits are printed (x MOD 100H), otherwise 8 digits are printed. *)

PROCEDURE Hex*(x, w: LONGINT);
VAR i, j: LONGINT; buf: ARRAY 10 OF CHAR;
BEGIN
	IF w >= 0 THEN j := 8 ELSE j := 2; w := -w END;
	FOR i := j+1 TO w DO Char(" ") END;
	FOR i := j-1 TO 0 BY -1 DO
		buf[i] := CHR(x MOD 10H + 48);
		IF buf[i] > "9" THEN
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
		END;
		x := x DIV 10H
	END;
	buf[j] := 0X;
	String(buf)
END Hex;

(** Write "x" as a hexadecimal number.  "w" is the field width.  Always prints 16 digits. *)

PROCEDURE HIntHex*(x: HUGEINT; w: LONGINT);
BEGIN
	Hex(AosBoot.HIntToLInt(AosBoot.ASHH(x, -32)), w-8);
	Hex(AosBoot.HIntToLInt(x), 8)
END HIntHex;

(** Write a block of memory in hex. *)

PROCEDURE Memory*(adr, size: LONGINT);
VAR i, j: LONGINT; ch: CHAR;
BEGIN
	Char(0EX);	(* "fixed font" *)
	size := adr+size-1;
	FOR i := adr TO size BY 16 DO
		Hex(i, 9);
		FOR j := i TO i+15 DO
			IF j <= size THEN
				SYSTEM.GET(j, ch);
				Hex(ORD(ch), -3)
			ELSE
				String("   ")
			END
		END;
		String(" ");
		FOR j := i TO i+15 DO
			IF j <= size THEN
				SYSTEM.GET(j, ch);
				IF (ch < " ") OR (ch >= CHR(127)) THEN ch := "." END;
				Char(ch)
			END
		END;
		Ln
	END;
	Char(0FX)	(* "proportional font" *)
END Memory;

(** Write a buffer in hex. *)

PROCEDURE Buffer*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT);
BEGIN
	Memory(SYSTEM.ADR(buf[ofs]), len)
END Buffer;

(** Write bits (ofs..ofs+n-1) of x in binary. *)

PROCEDURE Bits*(x: SET; ofs, n: LONGINT);
BEGIN
	REPEAT
		DEC(n);
		IF (ofs+n) IN x THEN Char("1") ELSE Char("0") END
	UNTIL n = 0
END Bits;

(** Enter mutually exclusive region for writing, using a fine-grained lock.  This region should be kept as short as possible, and only procedures from AosOut should be called inside it. *)

PROCEDURE Enter*;
BEGIN
	AosLocks.Acquire(AosLocks.AosOutHigh);
	String("{P"); Int(AosBoot.ID(), 1); Char(" ")
END Enter;

(** Exit mutually exclusive region for writing. *)

PROCEDURE Exit*;
BEGIN
	Char("}"); Ln;
	AosLocks.Release(AosLocks.AosOutHigh)
END Exit;

(* Switch to a new tracing buffer, copying the existing data. *)

PROCEDURE SwitchToBuffer(adr, size: LONGINT);
VAR tail: LONGINT;
BEGIN
	tail := 0; ASSERT(size > 0);
	WHILE (traceHead # traceTail) & (tail+1 # size) DO	(* source not empty, destination not full *)
		SYSTEM.PUT8(adr+tail, SYSTEM.GET8(traceBufAdr+traceHead));
		traceHead := (traceHead+1) MOD traceBufSize;
		INC(tail)
	END;
	traceBufAdr := adr; traceBufSize := size;
	traceHead := 0; traceTail := tail
END SwitchToBuffer;

(** Assign a new trace buffer.  Used by a display process. *)

PROCEDURE OpenBuffer*(adr, size: LONGINT): BOOLEAN;
VAR ok: BOOLEAN;
BEGIN
	AosLocks.Acquire(AosLocks.AosOutLow);
	IF traceBufAdr = SYSTEM.ADR(traceBufDef[0]) THEN
		SwitchToBuffer(adr, size); ok := TRUE
	ELSE
		ok := FALSE
	END;
	AosLocks.Release(AosLocks.AosOutLow);
	RETURN ok
END OpenBuffer;

(** Return output buffer contents.  Used by a display process. *)

PROCEDURE GetBuffer*(VAR val: ARRAY OF CHAR);
VAR i, m: LONGINT;
BEGIN
	i := 0; m := LEN(val)-1;
	AosLocks.Acquire(AosLocks.AosOutLow);
	WHILE (i < m) & (traceHead # traceTail) DO
		val[i] := CHR(SYSTEM.GET8(traceBufAdr + traceHead));
		traceHead := (traceHead+1) MOD traceBufSize;
		INC(i)
	END;
	AosLocks.Release(AosLocks.AosOutLow);
	val[i] := 0X
END GetBuffer;

(** Close the trace buffer and revert to the default.  Used by a display process. *)

PROCEDURE CloseBuffer*;
BEGIN
	AosLocks.Acquire(AosLocks.AosOutLow);
	IF traceBufAdr # SYSTEM.ADR(traceBufDef[0]) THEN
		SwitchToBuffer(SYSTEM.ADR(traceBufDef[0]), LEN(traceBufDef))
	END;
	AosLocks.Release(AosLocks.AosOutLow)
END CloseBuffer;

(** Switch off tracing to screen.  Display device drivers should call this before changing to graphics mode. *)

PROCEDURE ScreenOff*;
BEGIN
	EXCL(tmode, Screen)
END ScreenOff;

BEGIN
	Init;
	String(AosBoot.version); Ln;
	(*IF AosBoot.Trace THEN Enter; String("AosOut"); Exit END*)
END AosOut.

(**
Notes

This module provides low-level output facilities for Aos.  It is similar to the Out module of Oberon, but it can be called from anywhere, even from active object bodies and interrupt handlers.  It can write to the text display (when not using a graphics mode), a serial port, a memory buffer, or all of the above.  This is controlled by the TraceMode and related config strings (see Aos.Par).

Typically, a memory buffer is used.  The buffer is installed by the LogWindow.Open, or with the System.StartLog command when using Oberon.  The latter is recommended, as it also interprets traps specially and opens a new viewer for them.  The displaying of the buffer is done off-line by the LogWindow or Oberon threads, thereby allowing the procedures here to be called from anywhere.

Control characters:
0X	end of string (can not be printed)
1X	start of trap (if System.StartLog active then trap viewer will be opened and output redirected)
2X	end of trap (if System.StartLog active then it will revert output to the kernel log text)
3X	signal log overflow
9X	TAB (or single space)
0DX	CR (or NL and LF ignored)
0AX	LF (ignored if CR is NL)
0EX	set fixed-width font
0FX	set proportial font (default)
*)

(*
TraceMode:
0	1	Screen
2	4	V24
*)

(*
03.03.1998	pjm	First version
16.06.2000	pjm	Cleaned up
29.11.2000	pjm	buffering
12.06.2001	pjm	moved Flags to AosTrap, moved SegDesc and TSS to AosFragments
*)
