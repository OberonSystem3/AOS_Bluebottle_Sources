MODULE DynamicStrings;	(** Stefan Walthert   *)
(** AUTHOR "swalthert"; PURPOSE "Dynamic strings"; *)

IMPORT
	Utilities;

CONST
	Step = 1024;
	CR* = 0DX; (** the Oberon end of line character *)
	Tab* = 09X; (** the horizontal tab character *)
	LF* = 0AX; (** the UNIX end of line character *) 
	

TYPE
	String* = Utilities.String;

	DynamicString* = OBJECT
		VAR
			str: String;
			len: LONGINT;
		
		PROCEDURE & Init*();
		BEGIN
			NEW(str, Step);
			str[0] := 0X;
			len := Step;
		END Init;
		
		PROCEDURE AdjustLen(newlen: LONGINT);
		VAR tmp: String;
		BEGIN
			IF newlen >= len THEN
				IF newlen >= len + Step THEN
					len := newlen
				ELSE
					len := len + Step
				END;
				NEW(tmp, len);
				COPY(str^, tmp^);
				str := tmp
			END
		END AdjustLen;
		
		PROCEDURE Put*(ch: CHAR; at: LONGINT);
		VAR tmp: String;
		BEGIN
			AdjustLen(at + 1);
			str[at] := ch
		END Put;
		
		PROCEDURE Get*(at: LONGINT): CHAR;
		BEGIN
			IF at + 1 > len THEN
				RETURN 0X
			ELSE
				RETURN str[at]
			END
		END Get;
		
		PROCEDURE Append*(VAR this: ARRAY OF CHAR);
		VAR tmp: String;
		BEGIN
			AdjustLen(StringLength(str^) + StringLength(this) + 1);
			StringAppend(str^, this)
		END Append;
		
		PROCEDURE Extract*(offset, len: LONGINT): String;
		VAR s: String; i: LONGINT;
		BEGIN
			i := StringLength(str^);
			IF offset < i THEN
				IF offset + len > i THEN len := i - offset END;
				NEW(s, len + 1);
				FOR i := 0 TO len - 1 DO
					s[i] := str[i + offset]
				END;
			ELSE
				NEW(s, 1); i := 0
			END;
			s[i] := 0X;
			RETURN s
		END Extract;
		
		PROCEDURE Length*(): LONGINT;
		BEGIN
			RETURN StringLength(str^)
		END Length;
		
		PROCEDURE ToArrOfChar*(): String;
		VAR s: String;
		BEGIN
			NEW(s, StringLength(str^) + 1);
			COPY(str^, s^);
			RETURN s
		END ToArrOfChar;
		
		PROCEDURE FromArrOfChar*(s: String);
		BEGIN
			len := StringLength(s^) + 1;
			NEW(str, len);
			COPY(s^, str^);
		END FromArrOfChar;
		
	END DynamicString;

	PROCEDURE StringLength*(VAR str: ARRAY OF CHAR): LONGINT;
		VAR i, l: LONGINT;
	BEGIN
		l := LEN(str); i := 0;
		WHILE (i < l) & (str[i] # 0X) DO
			INC(i)
		END;
		RETURN i
	END StringLength;

	PROCEDURE StringAppend*(VAR to: ARRAY OF CHAR; this: ARRAY OF CHAR);
		VAR i, j, l: LONGINT;
	BEGIN
		i := 0;
		WHILE to[i] # 0X DO
			INC(i)
		END;
		l := LEN(to)-1; j := 0;
		WHILE (i < l) & (this[j] # 0X) DO
			to[i] := this[j]; INC(i); INC(j)
		END;
		to[i] := 0X
	END StringAppend;

	PROCEDURE Lower*(VAR str, lstr: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE str[i] # 0X DO
			lstr[i] := LowerCh(str[i]); INC(i)
		END;
		lstr[i] := 0X
	END Lower;

	PROCEDURE LowerCh*(ch: CHAR): CHAR;
	BEGIN
		CASE ch OF
			"A" .. "Z": ch := CHR(ORD(ch)-ORD("A")+ORD("a"))
	(*		|"Ä": ch := "ä"
			|"Ö": ch := "ö"
			|"Ü": ch := "ü" *)
		ELSE
		END;
		RETURN ch
	END LowerCh;

	PROCEDURE IntToStr*(val: LONGINT; VAR str: ARRAY OF CHAR);
		VAR
			i, j: LONGINT;
			digits: ARRAY 16 OF LONGINT;
	BEGIN
		IF val = MIN(LONGINT) THEN
			COPY("-2147483648", str);
			RETURN
		END;
		IF val < 0 THEN
			val := -val; str[0] := "-"; j := 1
		ELSE
			j := 0
		END;
		i := 0;
		REPEAT
			digits[i] := val MOD 10; INC(i); val := val DIV 10
		UNTIL val = 0;
		DEC(i);
		WHILE i >= 0 DO
			str[j] := CHR(digits[i]+ORD("0")); INC(j); DEC(i)
		END;
		str[j] := 0X
	END IntToStr;

	PROCEDURE StrToInt*(VAR str: ARRAY OF CHAR): LONGINT;
		VAR val, i, d: LONGINT; ch: CHAR; neg: BOOLEAN;
	BEGIN
		val := 0; i := 0; ch := str[0];
		WHILE (ch # 0X) & (ch <= " ") DO
			INC(i); ch := str[i]
		END;
		neg := FALSE; IF ch = "+" THEN INC(i); ch := str[i] END;
		IF ch = "-" THEN neg := TRUE; INC(i); ch := str[i] END;
		WHILE (ch # 0X) & (ch <= " ") DO
			INC(i); ch := str[i]
		END;
		val := 0;
		WHILE (ch >= "0") & (ch <= "9") DO
			d := ORD(ch)-ORD("0");
			INC(i); ch := str[i];
			IF val <= ((MAX(LONGINT)-d) DIV 10) THEN
				val := 10*val+d
			ELSIF neg & (val = 214748364) & (d = 8) & ((ch < "0") OR (ch > "9")) THEN
				val := MIN(LONGINT); neg := FALSE
			ELSE
				HALT(99)
			END
		END;
		IF neg THEN val := -val END;
		RETURN val
	END StrToInt;

	PROCEDURE HexStrToInt*(VAR str: ARRAY OF CHAR): LONGINT;
	VAR val, i, d: LONGINT; ch: CHAR;
	BEGIN
		i := 0; ch := str[0];
		WHILE (ch # 0X) & (ch <= " ") DO
			INC(i); ch := str[i]
		END;
		val := 0;
		WHILE (("0" <= ch) & (ch <= "9")) OR (("A" <= ch) & (ch <= "F")) DO
			IF (("0" <= ch) & (ch <= "9")) THEN d := ORD(ch)-ORD("0")
			ELSE d := ORD(ch) - ORD("A") + 10
			END;
			INC(i); ch := str[i];
			IF val <= ((MAX(LONGINT)-d) DIV 10H) THEN
				val := 10H*val+d
			ELSE
				HALT(99)
			END
		END
	END HexStrToInt;

	PROCEDURE Search*(pat: ARRAY OF CHAR; VAR src: ARRAY OF CHAR; VAR pos: LONGINT);
		CONST MaxPat = 128;
		VAR
			buf: ARRAY MaxPat OF CHAR;
			len, i, srclen: LONGINT;
			
		PROCEDURE Find(beg: LONGINT);
			VAR
				i, j, b, e: LONGINT;
				ch: CHAR;
				ref: ARRAY MaxPat OF CHAR;
		BEGIN
			ch := src[pos]; INC(pos);
			ref[0] := ch;
			i := 0; j := 0; b := 0; e := 1;
			WHILE (pos <= srclen) & (i < len) DO
				IF buf[i] = ch THEN
					INC(i); j := (j + 1) MOD MaxPat
				ELSE
					i := 0; b := (b + 1) MOD MaxPat; j := b
				END;
				IF j # e THEN
					ch := ref[j]
				ELSE
					IF pos >= srclen THEN
						ch := 0X
					ELSE
						ch := src[pos]
					END;
					INC(pos); ref[j] := ch; e := (e + 1) MOD MaxPat; INC(beg);
				END
			END;
			IF i = len THEN
				pos := beg-len
			ELSE
				pos := -1
			END
		END Find;
		
	BEGIN
		len := StringLength(pat);
		IF MaxPat < len THEN
			len := MaxPat
		END;
		IF len <= 0 THEN
			pos := -1;
			RETURN
		END;
		i := 0;
		REPEAT
			buf[i] := pat[i]; INC(i)
		UNTIL i >= len;
		srclen := StringLength(src);
		IF pos < 0 THEN
			pos := 0
		ELSIF pos >= srclen THEN
			pos := -1;
			RETURN
		END;
		Find(pos)
	END Search;

END DynamicStrings.