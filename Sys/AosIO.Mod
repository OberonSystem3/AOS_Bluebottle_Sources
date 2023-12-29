 (* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosIO; (** AUTHOR "pjm/be"; PURPOSE "I/O buffering and formatted writing and reading"; *)

IMPORT SYSTEM;

CONST
	Ok* = 0;	(** zero result code means no error occurred *)
	EOF* = 4201;	(** error returned when Receive reads past end of file or stream *)
	
	EOT* = 1AX;	(** EOT character *)

	StringFull = 4202;
	FormatError* = 4203; (** error returned when ReadInt fails *)
	
CONST
	CR = 0DX; LF = 0AX; TAB = 9X; SP = 20X;
	
	DefaultWriterSize = 4096;
	DefaultReaderSize = 4096;

TYPE
		(** Any stream output procedure or method. *)
	Sender* = PROCEDURE {DELEGATE} (VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
	
		(** Any stream input procedure or method. *)
	Receiver* = PROCEDURE {DELEGATE} (VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
	
	Connection* = OBJECT
		PROCEDURE Send*(VAR data: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		BEGIN
		END Send;
		
		PROCEDURE Receive*(VAR data: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		BEGIN
		END Receive;
		
		PROCEDURE Close*;
		BEGIN
		END Close;
		
	END Connection;
	
		(** A writer buffers output before it is sent to a Sender.  Must not be shared between processes. *)
TYPE
	Writer* = OBJECT
		VAR
			tail: LONGINT;
			buf: POINTER TO ARRAY OF CHAR;
			res*: LONGINT;	(** result of last output operation. *)
			send: Sender;
			sent*: LONGINT;	(** count of sent bytes *)
			(* buf[0..tail-1] contains data to write. *)
			
		PROCEDURE &InitWriter(send: Sender; size: LONGINT);
		BEGIN
			ASSERT(send # NIL);
			tail := 0; res := Ok;
			NEW(buf, size);
			SELF.send := send; sent := 0
		END InitWriter;
		
		PROCEDURE Update*;
		BEGIN
			IF (res = Ok) THEN
				send(buf^, 0, tail, TRUE, res);
				IF res = Ok THEN INC(sent, tail); tail := 0 END
			END
		END Update;
		
		(** Current write position. *)
		PROCEDURE Pos*(): LONGINT;
		BEGIN 
			RETURN sent + tail
		END Pos;

		(** -- Write raw binary data -- *)
		
		(** Write one byte. *)
		PROCEDURE Char*(x: CHAR);
		BEGIN
			IF (tail = LEN(buf)) & (res = Ok) THEN
				send(buf^, 0, tail, FALSE, res);
				IF res = Ok THEN INC(sent, tail); tail := 0 END
			END;
			IF res = Ok THEN buf[tail] := x; INC(tail) END
		END Char;
		
		(** Write len bytes from x, starting at ofs. *)
		PROCEDURE Bytes*(VAR x: ARRAY OF CHAR; ofs, len: LONGINT);
		VAR n: LONGINT;
		BEGIN
			ASSERT(len >= 0);
			LOOP
				n := LEN(buf) - tail;	(* space available *)
				IF n = 0 THEN
					IF res = Ok THEN	(* send current buffer *)
						send(buf^, 0, tail, FALSE, res);
						IF res = Ok THEN INC(sent, tail); tail := 0 ELSE EXIT END
					ELSE
						EXIT	(* should not be writing on an erroneous rider *)
					END;
					n := LEN(buf)
				END;
				IF n > len THEN n := len END;
				ASSERT(tail+n <= LEN(buf));	(* index check *)
				SYSTEM.MOVE(SYSTEM.ADR(x[ofs]), SYSTEM.ADR(buf[tail]), n);
				INC(tail, n);
				IF len = n THEN EXIT END;	(* done *)
				INC(ofs, n); DEC(len, n)
			END
		END Bytes;

		(** Write a SHORTINT. *)
		PROCEDURE RawSInt*(x: SHORTINT);
		BEGIN
			Char(SYSTEM.VAL(CHAR, x))
		END RawSInt;
		
		(** Write an INTEGER. *)
		PROCEDURE RawInt*(x: INTEGER);
		BEGIN
			Bytes(SYSTEM.VAL(Bytes2, x), 0, 2)
		END RawInt;
		
		(** Write a LONGINT. *)
		PROCEDURE RawLInt*(x: LONGINT);
		BEGIN
			Bytes(SYSTEM.VAL(Bytes4, x), 0, 4)
		END RawLInt;
		
		(** Write a 32 bit value in network byte order (most significant byte first) *)
		PROCEDURE Net32*(x : LONGINT);
		BEGIN
			Char(CHR(x DIV 1000000H MOD 100H));
			Char(CHR(x DIV 10000H MOD 100H));
			Char(CHR(x DIV 100H MOD 100H));
			Char(CHR(x MOD 100H))
		END Net32;
		
		(** Read a 16 bit value in network byte order (most significant byte first) *)
		PROCEDURE Net16*(x : LONGINT);
		BEGIN
			Char(CHR(x DIV 100H MOD 100H));
			Char(CHR(x MOD 100H))
		END Net16;

		(** Write a SET. *)
		PROCEDURE RawSet*(x: SET);
		BEGIN
			Bytes(SYSTEM.VAL(Bytes4, x), 0, 4)
		END RawSet;
		
		(** Write a BOOLEAN. *)
		PROCEDURE RawBool*(x: BOOLEAN);
		BEGIN
			IF x THEN Char(1X) ELSE Char(0X) END
		END RawBool;
		
		(** Write a REAL. *)
		PROCEDURE RawReal*(x: REAL);
		BEGIN
			Bytes(SYSTEM.VAL(Bytes4, x), 0, 4)
		END RawReal;
		
		(** Write a LONGREAL. *)
		PROCEDURE RawLReal*(x: LONGREAL);
		BEGIN
			Bytes(SYSTEM.VAL(Bytes8, x), 0, 8)
		END RawLReal;
		
		(** Write a 0X-terminated string, including the 0X terminator. *)
		PROCEDURE RawString*(x: ARRAY OF CHAR);
		VAR i: LONGINT;
		BEGIN
			i := 0; WHILE x[i] # 0X DO Char(x[i]); INC(i) END;
			Char(0X)
		END RawString;
		
		(** Write a number in a compressed format. *)
		PROCEDURE RawNum*(x: LONGINT);
		BEGIN
			WHILE (x < - 64) OR (x > 63) DO Char(CHR(x MOD 128 + 128)); x := x DIV 128 END;
			Char(CHR(x MOD 128))
		END RawNum;
		
		(** -- Write formatted data -- *)
		
		(** Write an ASCII end-of-line (CR/LF). *)
		PROCEDURE Ln*;
		BEGIN
			Char(CR); Char(LF)
		END Ln;
		
		(** Write a 0X-terminated string, excluding the 0X terminator. *)
		PROCEDURE String*(x: ARRAY OF CHAR);
		VAR i: LONGINT;
		BEGIN
			i := 0; WHILE x[i] # 0X DO Char(x[i]); INC(i) END
		END String;
		
		(** Write an integer in decimal right-justified in a field of at least w characters. *)
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
		
		(** Write a SET in Oberon notation. *)
		PROCEDURE Set*(s: SET);	(* from P. Saladin *)
		VAR i, last: LONGINT; dots: BOOLEAN;
		BEGIN
			Char("{"); last := MIN(LONGINT); dots := FALSE;
			FOR i := MIN(SET) TO MAX(SET) DO
				IF i IN s THEN
					IF last = (i-1) THEN
						IF dots THEN String(".."); dots := FALSE END;
						IF (i = MAX(SET)) OR ~((i+1) IN s) THEN Int(i, 1) END
					ELSE
						IF last >= MIN(SET) THEN String(", ") END;
						Int(i, 1); dots := TRUE
					END;
					last := i
				END
			END;
			Char("}")
		END Set;
		
		(** Write an integer in hexadecimal right-justified in a field of at least ABS(w) characters.  
			If w is negative, (x MOD 100H) is printed as two hex digits, otherwise x is printed as 8 digits. *)
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

		PROCEDURE Pair(ch: CHAR; x: LONGINT);
		BEGIN
			IF ch # 0X THEN Char(ch) END;
			Char(CHR(ORD("0") + x DIV 10 MOD 10));
			Char(CHR(ORD("0") + x MOD 10))
		END Pair;
		
		(** Write the date and time in ISO format (yyyy-mm-dd hh:mm:ss).  The t and d parameters are in Oberon time and date format.
			If all parameters are within range, the output string is exactly 19 characters wide.  The t or d parameter can be -1, in which 
			case the time or date respectively are left out. *)
		PROCEDURE Date*(t, d: LONGINT);
		VAR ch: CHAR;
		BEGIN
			IF d # -1 THEN
		 	   Int(1900 + d DIV 512, 4);	(* year *)
				Pair("-", d DIV 32 MOD 16);	(* month *)
				Pair("-", d MOD 32);	(* day *)
				ch := " "	(* space between date and time *)
			ELSE
				ch := 0X	(* no space before time *)
			END;
			IF t # -1 THEN
		    	Pair(ch, t DIV 4096 MOD 32);	(* hour *)
		    	Pair(":", t DIV 64 MOD 64);	(* min *)
		    	Pair(":", t MOD 64)	(* sec *)
		    END
		END Date;

		(** Write the date and time in RFC 822/1123 format without the optional day of the week (dd mmm yyyy hh:mm:ss SZZZZ) .
			The t and d parameters are in Oberon time and date format.  The tz parameter specifies the time zone offset in minutes 
			(from -720 to 720 in steps of 30).  If all parameters are within range, the output string is exactly 26 characters wide.  
			The t, d or tz parameter can be -1, in which case the time, date or timezone respectively are left out. *)
		PROCEDURE Date822*(t, d, tz: LONGINT);
		VAR i, m: LONGINT; ch: CHAR;
		BEGIN
			IF d # -1 THEN
				Int(d MOD 32, 2);	(* day *)
				m := (d DIV 32 MOD 16 - 1)*4;	(* month *)
				FOR i := m TO m+3 DO Char(months[i]) END;
				Int(1900 + d DIV 512, 5);	(* year *)
				ch := " "	(* space *)
			ELSE
				ch := 0X	(* no space *)
			END;
			IF t # -1 THEN
				Pair(ch, t DIV 4096 MOD 32);	(* hour *)
				Pair(":", t DIV 64 MOD 64);	(* min *)
				Pair(":", t MOD 64);	(* sec *)
				ch := " "	(* space *)
			ELSE
				(* leave ch as before *)
			END;
			IF tz # -1 THEN
				IF ch # 0X THEN Char(ch) END;
				IF tz >= 0 THEN Pair("+", tz DIV 60)
				ELSE Pair("-", (-tz) DIV 60)
				END;
				Pair(0X, ABS(tz) MOD 60)
		    END
		END Date822;
	END Writer;

		(** A special writer that buffers output to be fetched by GetString or GetRawString. *)
	StringWriter* = OBJECT(Writer)
		PROCEDURE &InitStringWriter(size: LONGINT);
		BEGIN
			InitWriter(Send, size)
		END InitStringWriter;
		
		PROCEDURE Send(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		BEGIN
			res := StringFull
		END Send;
		
		PROCEDURE Update;
		BEGIN (* nothing to do *)
		END Update;

		(** Return the contents of the string writer (0X-terminated). *)
		PROCEDURE Get*(VAR s: ARRAY OF CHAR);
		VAR i, m: LONGINT;
		BEGIN
			m := LEN(s)-1; i := 0;
			WHILE (i # tail) & (i < m) DO
				s[i] := buf[i]; INC(i)
			END;
			s[i] := 0X;
			tail := 0; res := Ok
		END Get;

		(** Return the contents of the string writer (not 0X-terminated).  The len parameters returns the string length. *)
		PROCEDURE GetRaw*(VAR s: ARRAY OF CHAR; VAR len: LONGINT);
		VAR i, m: LONGINT;
		BEGIN
			m := LEN(s); i := 0;
			WHILE (i # tail) & (i < m) DO
				s[i] := buf[i]; INC(i)
			END;
			len := i;
			tail := 0; res := Ok
		END GetRaw;
	END StringWriter;
TYPE	
		(** A reader buffers input received from a Receiver.  Must not be shared between processes. *)
	Reader* = OBJECT
		VAR
			head, tail: LONGINT;
			buf: POINTER TO ARRAY OF CHAR;
			res*: LONGINT;	(** result of last input operation. *)
			receive: Receiver;
			received*: LONGINT;	(** count of received bytes *)
			(* buf[buf.head..buf.tail-1] contains data to read. *)
			
		PROCEDURE &InitReader(receive: Receiver; size: LONGINT);
		BEGIN
			ASSERT(receive # NIL);
			head := 0; tail := 0; res := Ok;
			NEW(buf, size);
			SELF.receive := receive; received := 0
		END InitReader;

		(** Return bytes currently available in input buffer. *)
		PROCEDURE Available*(): LONGINT;
		VAR n: LONGINT;
		BEGIN
			IF (res = 0) THEN
				IF (head = tail) THEN
					head := 0; receive(buf^, 0, LEN(buf), 0, tail, res); INC(received, tail);
				ELSIF (tail # LEN(buf)) THEN
					receive(buf^, tail, LEN(buf)-tail, 0, n, res);	(* poll *)
					INC(tail, n); INC(received, n)
				END;
				IF res = EOF THEN res := Ok END	(* ignore EOF here *)
			END;
			RETURN tail - head
		END Available;
			
		(** Current read position. *)
		PROCEDURE Pos*(): LONGINT;
		BEGIN
			RETURN received - (tail-head)
		END Pos;

		(** -- Read raw binary data -- *)
		
		(** Read one byte. *)
		PROCEDURE Char*(VAR x: CHAR);
		BEGIN
			IF (head = tail) & (res = Ok) THEN
				head := 0; receive(buf^, 0, LEN(buf), 1, tail, res); INC(received, tail)
			END;
			IF res = Ok THEN x := buf[head]; INC(head) ELSE x := 0X END
		END Char;
		
		(** Like Read, but return result. *)
		PROCEDURE Get*(): CHAR;
		BEGIN
			IF (head = tail) & (res = Ok) THEN
				head := 0; receive(buf^, 0, LEN(buf), 1, tail, res); INC(received, tail)
			END;
			IF res = Ok THEN INC(head); RETURN buf[head-1] ELSE RETURN 0X END
		END Get;
		
		(** Like Get, but leave the byte in the input buffer. *)
		PROCEDURE Peek*(): CHAR;
		BEGIN
			IF (head = tail) & (res = Ok) THEN
				head := 0; receive(buf^, 0, LEN(buf), 1, tail, res); INC(received, tail);
				IF res = EOF THEN	(* ignore EOF here *)
					res := Ok; buf[0] := 0X	(* Peek returns 0X at eof *)
				END
			END;
			IF res = Ok THEN RETURN buf[head] ELSE RETURN 0X END
		END Peek;
		
		(** Read size bytes into x, starting at ofs.  The len parameter returns the number of bytes that were actually read. *)
		PROCEDURE Bytes*(VAR x: ARRAY OF CHAR; ofs, size: LONGINT; VAR len: LONGINT);
		VAR n: LONGINT;
		BEGIN
			ASSERT(size >= 0);
			len := 0;
			LOOP
				n := tail - head;	(* bytes available *)
				IF n = 0 THEN	(* no data available *)
					head := 0;
					IF res = Ok THEN	(* fill buffer *)
						receive(buf^, 0, LEN(buf), 1, tail, res); INC(received, tail)
					END;
					IF res # Ok THEN	(* should not be reading from erroneous rider *)
						WHILE size # 0 DO x[ofs] := 0X; INC(ofs); DEC(size) END;	(* clear rest of buffer *)
						IF (res = EOF) & (len # 0) THEN res := Ok END;	(* ignore EOF if some data being returned *)
						EXIT
					END;
					n := tail
				END;
				IF n > size THEN n := size END;
				ASSERT(ofs+n <= LEN(x));	(* index check *)
				SYSTEM.MOVE(SYSTEM.ADR(buf[head]), SYSTEM.ADR(x[ofs]), n);
				INC(head, n); INC(len, n);
				IF size = n THEN EXIT END;	(* done *)
				INC(ofs, n); DEC(size, n)
			END
		END Bytes;

		(** Skip n bytes on the reader. *)
		PROCEDURE SkipBytes*(n: LONGINT);
		VAR ch: CHAR;
		BEGIN
			WHILE n > 0 DO ch := Get(); DEC(n) END
		END SkipBytes;
		
		(** Read a SHORTINT. *)
		PROCEDURE RawSInt*(VAR x: SHORTINT);
		BEGIN
			x := SYSTEM.VAL(SHORTINT, Get())
		END RawSInt;
		
		(** Read an INTEGER. *)
		PROCEDURE RawInt*(VAR x: INTEGER);
		VAR x0, x1: CHAR;
		BEGIN
			x0 := Get(); x1 := Get();	(* defined order *)
			x := ORD(x1) * 100H + ORD(x0)
		END RawInt;
		
		(** Read a LONGINT. *)
		PROCEDURE RawLInt*(VAR x: LONGINT);
		VAR ignore: LONGINT;
		BEGIN
			Bytes(SYSTEM.VAL(Bytes4, x), 0, 4, ignore)
		END RawLInt;
		
		(** Read a 32 bit value in network byte order (most significant byte first) *)
		PROCEDURE Net32*() : LONGINT;
		BEGIN
			RETURN 
				LONG(ORD(Get())) * 1000000H + LONG(ORD(Get()))*10000H + 
				LONG(ORD(Get()))*100H + LONG(ORD(Get()))
		END Net32;
		
		(** Read a 16 bit value in network byte order (most significant byte first) *)
		PROCEDURE Net16*() : LONGINT;
		BEGIN
			RETURN LONG(ORD(Get()))*100H + LONG(ORD(Get()))
		END Net16;
		
		(** Read a SET. *)
		PROCEDURE RawSet*(VAR x: SET);
		VAR ignore: LONGINT;
		BEGIN
			Bytes(SYSTEM.VAL(Bytes4, x), 0, 4, ignore)
		END RawSet;
		
		(** Read a BOOLEAN. *)
		PROCEDURE RawBool*(VAR x: BOOLEAN);
		BEGIN
			x := (Get() # 0X)
		END RawBool;
		
		(** Read a REAL. *)
		PROCEDURE RawReal*(VAR x: REAL);
		VAR ignore: LONGINT;
		BEGIN
			Bytes(SYSTEM.VAL(Bytes4, x), 0, 4, ignore)
		END RawReal;
		
		(** Read a LONGREAL. *)
		PROCEDURE RawLReal*(VAR x: LONGREAL);
		VAR ignore: LONGINT;
		BEGIN
			Bytes(SYSTEM.VAL(Bytes8, x), 0, 8, ignore)
		END RawLReal;
		
		(** Read a 0X-terminated string.  If the input string is larger than x, read the full string and assign the truncated 0X-terminated value to x. *)
		PROCEDURE RawString*(VAR x: ARRAY OF CHAR);
		VAR i, m: LONGINT; ch: CHAR;
		BEGIN
			i := 0; m := LEN(x)-1;
			LOOP
				ch := Get();	(* also returns 0X on error *)
				IF ch = 0X THEN EXIT END;
				IF i < m THEN x[i] := ch; INC(i) END
			END;
			x[i] := 0X
		END RawString;
		
		(** Read a number in a compressed format. *)
		PROCEDURE RawNum*(VAR x: LONGINT);
		VAR ch: CHAR; n, y: LONGINT;
		BEGIN
			n := 0; y := 0; ch := Get();
			WHILE ch >= 80X DO INC(y, SYSTEM.LSH(LONG(ORD(ch)) - 128, n)); INC(n, 7); ch := Get() END;
			x := ASH(SYSTEM.LSH(LONG(ORD(ch)), 25), n-25) + y
		END RawNum;
		
		(** -- Read formatted data (uses Peek for one character lookahead) -- *)
		
		(** Read an integer value in decimal or hexadecimal.  If hex = TRUE, recognize the "H" postfix for hexadecimal numbers. *)
		PROCEDURE Int*(VAR x: LONGINT; hex: BOOLEAN);
		VAR vd, vh, sgn, d: LONGINT; ch: CHAR; ok: BOOLEAN;
		BEGIN
			vd := 0; vh := 0; sgn := 1; ok := FALSE;
			IF Peek() = "-" THEN sgn := -1; ch := Get() END;
			LOOP
				ch := Peek();
				IF (ch >= "0") & (ch <= "9") THEN d := ORD(ch)-ORD("0")
				ELSIF hex & (CAP(ch) >= "A") & (CAP(ch) <= "F") THEN d := ORD(CAP(ch))-ORD("A")+10
				ELSE EXIT
				END;
				vd := 10*vd + d; vh := 16*vh + d;	(* ignore overflow *)
				ch := Get(); ok := TRUE
			END;
			IF hex & (CAP(ch) = "H") THEN	(* optional "H" present *)
				vd := vh;	(* use the hex value *)
				ch := Get()
			END;
			x := sgn * vd;
			IF (res = 0) & ~ok THEN res := FormatError END
		END Int;
		
		(** Return TRUE iff at the end of a line (or file). *)
		PROCEDURE EOLN*(): BOOLEAN;
		VAR ch: CHAR;
		BEGIN
			ch := Peek();
			RETURN (ch = CR) OR (ch = LF) OR (res # Ok)
		END EOLN;
		
		(** Read all characters until the end of the line (inclusive).  If the input string is larger than x, read the full string and assign 
			the truncated 0X-terminated value to x. *)
		PROCEDURE Ln*(VAR x: ARRAY OF CHAR);
		VAR i, m: LONGINT; ch: CHAR;
		BEGIN
			i := 0; m := LEN(x)-1;
			LOOP
				ch := Peek();
				IF (ch = CR) OR (ch = LF) OR (res # Ok) THEN EXIT END;
				IF i < m THEN x[i] := ch; INC(i) END;
				ch := Get()
			END;
			x[i] := 0X;
			IF ch = CR THEN ch := Get() END;
			IF Peek() = LF THEN ch := Get() END
		END Ln;
		
		(** Read all characters until the end of the line (inclusive) or an <EOT> character.  
			If the input string is larger than x, read the full string and assign the truncated 0X-terminated 
			value to x. *)
		PROCEDURE LnEOT*(VAR x: ARRAY OF CHAR);
		VAR i, m: LONGINT; ch: CHAR;
		BEGIN
			i := 0; m := LEN(x)-1;
			LOOP
				ch := Peek();
				IF (ch = CR) OR (ch = LF) OR (ch = EOT) OR (res # Ok) THEN EXIT END;
				IF i < m THEN x[i] := ch; INC(i) END;
				ch := Get()
			END;
			x[i] := 0X;
			IF ch = CR THEN ch := Get() END;
			IF Peek() = LF THEN ch := Get() END;
			IF ch = EOT THEN
				ch := Get()
			END
		END LnEOT;
		
		(** Skip over all characters until the end of the line (inclusive). *)
		PROCEDURE SkipLn*;
		VAR ch: CHAR;
		BEGIN
			LOOP
				ch := Peek();
				IF (ch = CR) OR (ch = LF) OR (res # Ok) THEN EXIT END;
				ch := Get()
			END;
			IF ch = CR THEN ch := Get() END;
			IF Peek() = LF THEN ch := Get() END
		END SkipLn;
		
		(** Skip over space and TAB characters. *)
		PROCEDURE SkipSpaces*;
		VAR ch: CHAR;
		BEGIN
			LOOP
				ch := Peek();
				IF (ch # TAB) & (ch # SP) THEN EXIT END;
				ch := Get()
			END
		END SkipSpaces;
		
		(** Skip over space, TAB and EOLN characters. *)
		PROCEDURE SkipWhitespace*;
		VAR ch: CHAR;
		BEGIN
			LOOP
				ch := Peek();
				IF (ch # SP) & (ch # CR) & (ch # LF) & (ch # TAB) THEN EXIT END;
				ch := Get()
			END
		END SkipWhitespace;
		
		(** Read a token, consisting of any string of characters terminated by space, TAB or EOLN. *)
		PROCEDURE Token*(VAR token: ARRAY OF CHAR);
		VAR j, max: LONGINT; ch: CHAR;
		BEGIN
			j := 0; max := LEN(token)-1;
			LOOP
				ch := Peek();
				IF (ch = SP) OR (ch = CR) OR (ch = LF) OR (ch = TAB) OR (res # Ok) THEN EXIT END;
				IF j < max THEN token[j] := ch; INC(j) END;
				ch := Get()
			END;
			token[j] := 0X
		END Token;
		
		(** Read an optionally "" or '' enquoted string.  Will not read past the end of a line. *)
		PROCEDURE String*(VAR string: ARRAY OF CHAR);
		VAR c, delimiter: CHAR; i, len: LONGINT;
		BEGIN
			c := Peek();
			IF (c # "'") & (c # '"') THEN Token( string)
			ELSE
				delimiter := Get(); c := Peek(); i := 0; len := LEN(string)-1;
				WHILE (i < len) & (c # delimiter) & (c # CR) & (c # LF) & (res = Ok) DO
					string[i] := Get(); INC(i);
					c := Peek()
				END;
				IF (c = delimiter) THEN c := Get() END; 
				string[i] := 0X
			END
		END String;
	END Reader;
TYPE	
		(** A special reader that buffers input set by SetString or SetRawString. *)
	StringReader* = OBJECT(Reader)
		PROCEDURE &InitStringReader(size: LONGINT);
		BEGIN
			InitReader(Receive, size)
		END InitStringReader;

		PROCEDURE Receive(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		BEGIN
			IF min = 0 THEN res := Ok ELSE res := EOF END;
			len := 0
		END Receive;
		
		(** Set the contents of the string buffer.  The s parameter is a 0X-terminated string. *)
		PROCEDURE Set*(s: ARRAY OF CHAR);
		VAR len: LONGINT;
		BEGIN
			len := 0; WHILE s[len] # 0X DO INC(len) END;
			IF len > LEN(buf) THEN len := LEN(buf) END;
			head := 0; tail := len; res := Ok;
			SYSTEM.MOVE(SYSTEM.ADR(s[0]), SYSTEM.ADR(buf[0]), len)
		END Set;

		(** Set the contents of the string buffer.  The len parameter specifies the size of the buffer s. *)
		PROCEDURE SetRaw*(VAR s: ARRAY OF CHAR; ofs, len: LONGINT);
		BEGIN
			IF len > LEN(buf) THEN len := LEN(buf) END;
			head := 0; tail := len; res := Ok;
			ASSERT((len >= 0) & (ofs+len <= LEN(s)));	(* index check *)
			SYSTEM.MOVE(SYSTEM.ADR(s[ofs]), SYSTEM.ADR(buf[0]), len)
		END SetRaw;
	END StringReader;
	
	Bytes2 = ARRAY 2 OF CHAR;
	Bytes4 = ARRAY 4 OF CHAR;
	Bytes8 = ARRAY 8 OF CHAR;

VAR
	months: ARRAY 12*4+1 OF CHAR;


(** Open a writer to the specified stream sender.  Update must be called after writing to ensure the buffer is written to the stream. *)

PROCEDURE OpenWriter*(VAR b: Writer; send: Sender);
BEGIN
	NEW(b, send, DefaultWriterSize)
END OpenWriter;


(** Open a reader from the specified stream receiver. *)

PROCEDURE OpenReader*(VAR b: Reader; receive: Receiver);
BEGIN
	NEW(b, receive, DefaultReaderSize)
END OpenReader;

BEGIN
	months := " Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"
END AosIO.

(**
Notes:
o Any single buffer instance must not be accessed by more than one process concurrently.
o The interface is blocking (synchronous).  If an output buffer is full, it is written with a synchronous write, which returns only when all the data has been written.   If an input buffer is empty, it is read with a synchronous read, which only returns once some data has been read.  The only exception is the Available() procedure, which "peeks" at the input stream and returns 0 if no data is currently available.
o All procedures set res to the error code reported by the lower-level I/O operation (non-zero indicates error).  E.g. closing an underlying TCP connection will result in the Read* procedures returning a non-zero error code.
o res is sticky.  Once it becomes non-zero, it remains non-zero.
o The only way to detect end of file is to attempt to read past the end of file, which returns a non-zero error code.
o All output written to an erroneous buffer is ignored.
o The value returned when reading from an erroneous buffer is undefined, except for the Read procedure, which returns 0X.
o ReadBytes sets the len parameter to the number of bytes that were actually read, e.g. if size = 10, and only 8 bytes are read, len is 8.
o Raw format is little-endian 2's complement integers, IEEE reals and 0X-terminated strings.
o Syntax for ReadInt with hex = FALSE: num = ["-"] digit {digit}. digit = "0".."9".
o Syntax for ReadInt with hex = TRUE: ["-"] hexdigit {hexdigit} ["H"|"h"]. hexdigit = digit | "A".."F" | "a".."f".
o ReadInt with hex = TRUE allows "A".."F" as digits, and looks for a "H" character after the number.  If present, the number is interpreted as hexadecimal.  If hexadecimal digits are present, but no "H" flag, the resulting decimal value is undefined.
o ReadInt ignores overflow.
o A Sender sends len bytes from buf at ofs to output and returns res non-zero on error.  It waits until all the data is written, or an error occurs.
o A Receiver receives up to size bytes from input into buf at ofs and returns the number of bytes read in len.  It returns res non-zero on error.  It waits until at least min bytes (possibly zero) are available, or an error occurs.
o EOLN and ReadLn recognize the following end-of-line characters: CR, LF and CR/LF.
o To read an unstructured file token-by-token: WHILE (r.res = 0) DO SkipWhitespace; ReadToken END
o To read a line structured file token-by-token: WHILE r.res = 0 DO SkipSpaces; WHILE ~EOLN DO ReadToken; SkipSpaces END END
o A string writer is not flushed when it becomes full, but res is set to a non-zero value.
o Update has no effect on a string writer.
o GetString can be called on a string writer to return the buffer contents and reset it to empty.
o GetString always appends a 0X character to the buffer, but returns the true length (excluding the added 0X) in the len parameter, so it can also be used for binary data that includes 0X characters.
o Receive procedure should set res to EOF when attempting to read past the end of file.
*)


(*
to do:
o stream byte count
o read formatted data
o reads for all formatted writes
o write reals
o low-level version that can be used in kernel (below AosOut)
*)
