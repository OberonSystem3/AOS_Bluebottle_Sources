(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE Utilities;	(** AUTHOR "be"; PURPOSE "Basic utility functions" *)

(** Oberon date & time format:
		time: bits 16-12: hours
					11-6: minutes
					5-0: seconds
					
		date: 30-9: count of years from 1900
					8-5: month of year
					4-0: day of month
*)

IMPORT AosClock, Reals;

CONST
	Ok* = 0;

TYPE
	String* = POINTER TO ARRAY OF CHAR;
	TDateTime* = RECORD
		Year*, Month*, Day*,
		Hour*, Minute*, Second*: LONGINT
	END;

VAR
	Months-: ARRAY 12 OF ARRAY 10 OF CHAR;	(** month's names (January = 0....December=11) *)
	Days-: ARRAY 7 OF ARRAY 10 OF CHAR;	(** day's names (Moday = 0, .... Sunday = 6) *)
	NoDays: ARRAY 12 OF INTEGER;
	DateFormat*, TimeFormat*: ARRAY 32 OF CHAR;	(** date and time format strings used by DateToStr/TimeToStr *)
	
(** Date and Time functions *)

(** returns TRUE if 'year' is a leap year *)
PROCEDURE LeapYear*(year: LONGINT): BOOLEAN;
BEGIN
	RETURN (year > 0) & (year MOD 4 = 0) & (~(year MOD 100 = 0) OR (year MOD 400 = 0))
END LeapYear;

(** returns the number of days in that month *)
PROCEDURE NofDays*(year, month: LONGINT): LONGINT;
BEGIN
	DEC(month);
	ASSERT((month >= 0) & (month < 12));
	IF (month = 1) & LeapYear(year) THEN RETURN NoDays[1]+1
	ELSE RETURN NoDays[month]
	END	
END NofDays;

(** checks if the values of a TDateTime structure are valid *)
PROCEDURE ValidDateTime*(dt: TDateTime): BOOLEAN;
BEGIN
	RETURN (dt.Year > 0) & (dt.Month > 0) & (dt.Month <= 12) & (dt.Day > 0) & (dt.Day <= NofDays(dt.Year, dt.Month)) &
		(dt.Hour >= 0) & (dt.Hour < 24) & (dt.Minute >= 0) & (dt.Minute < 60) & (dt.Second >= 0) & (dt.Second < 60)		
END ValidDateTime;

PROCEDURE Check(dt: TDateTime);
BEGIN
	IF ~ValidDateTime(dt) THEN HALT(1000) END
END Check;

(** convert an Oberon date/time to a TDateTime structure *)
PROCEDURE OberonToDateTime*(Date, Time: LONGINT): TDateTime;
VAR dt: TDateTime;
BEGIN
	dt.Second := Time MOD 64; Time := Time DIV 64;
	dt.Minute := Time MOD 64; Time := Time DIV 64;
	dt.Hour := Time MOD 24;
	dt.Day := Date MOD 32; Date := Date DIV 32;
	dt.Month := Date MOD 16; Date := Date DIV 16;
	dt.Year := 1900 + Date;
	RETURN dt
END OberonToDateTime;

(** convert a TDateTime structure to an Oberon date/time *)
PROCEDURE DateTimeToOberon*(dt: TDateTime; VAR date, time: LONGINT);
BEGIN
	Check(dt);
	date := (dt.Year-1900)*512 + dt.Month*32 + dt.Day;
	time := dt.Hour*4096 + dt.Minute*64 + dt.Second
END DateTimeToOberon;

(** returns the current date and time *)
PROCEDURE Now*(): TDateTime;
VAR d, t: LONGINT;
BEGIN
	AosClock.Get(t, d);
	RETURN OberonToDateTime(d, t)
END Now;

(** returns the ISO 8601 year number, week number & week day (Monday=1, ....Sunday=7) *)
(* algorithm by Rick McCarty, http://personal.ecu.edu/mccartyr/ISOwdALG.txt *)
PROCEDURE WeekDate*(Date: TDateTime; VAR year, week, weekday: LONGINT);
VAR doy, i, yy, c, g, jan1: LONGINT; leap: BOOLEAN;
BEGIN
	IF ValidDateTime(Date) THEN
		leap := LeapYear(Date.Year);
		doy := Date.Day; i := 0;
		WHILE (i < Date.Month-1) DO doy := doy + NoDays[i]; INC(i) END;
		IF leap & (Date.Month > 2) THEN INC(doy) END;
		yy := (Date.Year-1) MOD 100; c := (Date.Year-1) - yy; g := yy + yy DIV 4;
		jan1 := 1 + (((((c DIV 100) MOD 4) * 5) + g) MOD 7);

		weekday := 1 + (((doy + (jan1-1))-1) MOD 7);
		
		IF (doy <= (8-jan1)) & (jan1 > 4) THEN			(* falls in year-1 ? *)
			year := Date.Year-1;
			IF (jan1 = 5) OR ((jan1 = 6) & LeapYear(year)) THEN week := 53
			ELSE week := 52
			END
		ELSE
			IF leap THEN i := 366 ELSE i := 365 END;
			IF ((i - doy) < (4 - weekday)) THEN
				year := Date.Year + 1;
				week := 1
			ELSE
				year := Date.Year;
				i := doy + (7-weekday) + (jan1-1);
				week := i DIV 7;
				IF (jan1 > 4) THEN DEC(week) END
			END
		END
	ELSE
		year := -1; week := -1; weekday := -1
	END	
END WeekDate;

(** useful functions *)

(** Min - guess what ? *)
PROCEDURE Min*(a,b: LONGINT): LONGINT;
BEGIN IF (a < b) THEN RETURN a ELSE RETURN b END
END Min;

(** Max - guess what ? *)
PROCEDURE Max*(a,b: LONGINT): LONGINT;
BEGIN IF (a > b) THEN RETURN a ELSE RETURN b END
END Max;

(** string handling *)

(** returns the length of a string *)
PROCEDURE Length*(string: ARRAY OF CHAR): LONGINT;
VAR len: LONGINT;
BEGIN
	len := 0; WHILE (string[len] # 0X) DO INC(len) END;
	RETURN len
END Length;

(** returns the position of the first occurrence of pattern in the string or -1 if no occurrence is found *)
(* Rabin-Karp algorithm, adopted from Sedgewick *)
PROCEDURE Pos*(pattern: ARRAY OF CHAR; VAR string: ARRAY OF CHAR): LONGINT;
CONST q=33554393; d = 32;
VAR h1, h2, dM, i, j, m, n: LONGINT; check: BOOLEAN;
BEGIN
	m := Length(pattern); n := Length(string);
	IF (m > n) THEN RETURN -1 END;

	dM := 1; FOR i := 0 TO m-2 DO dM := (d*dM) MOD q END;
	h1 := 0; FOR i := 0 TO m-1 DO h1 := (h1*d + ORD(pattern[i])) MOD q END;
	h2 := 0; FOR i := 0 TO m-1 DO h2 := (h2*d + ORD(string[i])) MOD q END;
	i := 0;
	WHILE (h1 # h2) & (i < n-m) DO
		h2 := (h2 + d*q - ORD(string[i])*dM) MOD q;
		h2 := (h2*d + ORD(string[i+m])) MOD q;
		INC(i);
		
		IF (h1 = h2) THEN	(* verify *)
			check := TRUE; j := 0;
			WHILE (j < m) & check DO
				IF (string[i+j] # pattern[j]) THEN INC(h2); j := m END;	(* hash values are equal, but strings are not *)
				INC(j)
			END
		END
	END;
	
	IF (h1 = h2) THEN
		RETURN i
	ELSE RETURN -1
	END	
END Pos;

(** Simple pattern matching with support for "*" and "?" wildcards  - returns TRUE if name matches mask. Patent pending ;-) *)
PROCEDURE Match*(mask, name: ARRAY OF CHAR): BOOLEAN;
VAR m,n, om, on: LONGINT; f: BOOLEAN;
BEGIN
	m := 0; n := 0; om := -1;
	f := TRUE;
	LOOP
		IF (mask[m] = "*") THEN
			om := m; INC(m);
			WHILE (name[n] # 0X) & (name[n] # mask[m]) DO INC(n) END;
			on := n
		ELSIF (mask[m] = "?") THEN
			IF (name[n] = 0X) THEN f := FALSE; EXIT END;
			INC(m); INC(n)
		ELSE
			IF (mask[m] # name[n]) THEN
				IF (om = -1) THEN f := FALSE; EXIT
				ELSIF (name[n] # 0X) THEN (* try the next position *)
					m := om; n := on + 1;
					IF (name[n] = 0X) THEN f := FALSE; EXIT END
				ELSE
					f := FALSE; EXIT
				END
			ELSE INC(m); INC(n)
			END
		END;
		IF (mask[m] = 0X) & ((name[n] = 0X) OR (om=-1)) THEN EXIT END
	END;
	RETURN f & (name[n] = 0X)
END Match;

(** appends appendix to s: s := s || appendix *)
PROCEDURE Append*(VAR s: ARRAY OF CHAR; appendix: ARRAY OF CHAR);
VAR i, j, l: LONGINT;
BEGIN
	l := LEN(s)-1;
	i := 0; WHILE (i < l) & (s[i] # 0X) DO INC(i) END;
	j := 0; WHILE (i < l) & (appendix[j] # 0X) DO s[i] := appendix[j]; INC(i); INC(j) END;
	s[i] := 0X
END Append;

(** concatenates s1 and s2: s := s1 || s2 *)
PROCEDURE Concat*(s1, s2: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
VAR i, j, l: LONGINT;
BEGIN
	l := LEN(s)-1;
	i := 0; WHILE (i < l) & (s1[i] # 0X) DO s[i] := s1[i]; INC(i) END;
	j := 0; WHILE (i < l) & (s2[j] # 0X) DO s[i] := s2[j]; INC(i); INC(j) END;
	s[i] := 0X
END Concat;

(** copies s[index...index+count-1] to result *)
PROCEDURE Copy*(s: ARRAY OF CHAR; index, count: LONGINT; VAR result: ARRAY OF CHAR);
VAR i, l: LONGINT;
BEGIN
	i := 0; l := LEN(result)-1;
	WHILE (i < count) & (i < l) DO
		result[i] := s[index+i];
		INC(i)
	END;
	result[i] := 0X
END Copy;

(** deletes positions index...index+count-1 from 's' *)
PROCEDURE Delete*(VAR s: ARRAY OF CHAR; index, count: LONGINT);
VAR i: LONGINT;
BEGIN
	i := index+count;
	WHILE (s[i] # 0X) DO
		s[i-count] := s[i];
		INC(i)
	END;
	s[i-count] := 0X
END Delete;

(** inserts 'source' at position 'index' into 's' *)
PROCEDURE Insert*(source: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; index: LONGINT);
VAR i, j, len: LONGINT;
BEGIN
	len := Length(source);
	i := index;
	WHILE (s[i] # 0X) DO
		s[i+len] := s[i];
		INC(i);
	END;
	s[i] := 0X;
	i := index; j := 0;
	WHILE (i < len) DO
		s[i] := source[j];
		INC(i); INC(j)
	END
END Insert;

(** removes all occurrences of 'c' at the head of 'string' *)
PROCEDURE TrimLeft*(VAR string: ARRAY OF CHAR; c: CHAR);
VAR i,j: LONGINT;
BEGIN
	j := 0; WHILE (string[j] = c) DO INC(j) END;
	IF (j > 0) THEN
		i := 0;
		WHILE (string[j] # 0X) DO
			string[i] := string[j];
			INC(i); INC(j)
		END;
		string[i] := 0X
	END	
END TrimLeft;

(** removes all occurrences of 'c' at the end of 'string' *)
PROCEDURE TrimRight*(VAR string: ARRAY OF CHAR; c: CHAR);
VAR i: LONGINT;
BEGIN
	i := Length(string)-1;
	WHILE (i > 0) & (string[i] = c) DO DEC(i) END;
	string[i+1] := 0X
END TrimRight;

(** removes all occurrences of 'c' at both ends of 'string' *)
PROCEDURE Trim*(VAR string: ARRAY OF CHAR; c: CHAR);
BEGIN
	TrimLeft(string, c);
	TrimRight(string, c)
END Trim;


(** returns the corresponding lower-case letter for "A" <= ch <= "Z" *)
PROCEDURE LOW*(ch: CHAR): CHAR;
BEGIN
	IF (ch >= "A") & (ch <= "Z") THEN RETURN CHR(ORD(ch) - ORD("A") + ORD("a"))
	ELSE RETURN ch
	END
END LOW;
	
(** converts s to lower-case letters *)
PROCEDURE LowerCase*(VAR s: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
	i := 0;
	WHILE (s[i] # 0X) DO
		s[i] := LOW(s[i]);
		INC(i)
	END	
END LowerCase;

(** converts s to upper-case letters *)
PROCEDURE UpperCase*(VAR s: ARRAY OF CHAR);
VAR i: LONGINT; c : CHAR;
BEGIN
	i := 0;
	WHILE (s[i] # 0X) DO
		c := s[i];
		IF ('a' <= c) & (c <= 'z') THEN s[i] := CAP(c) END;
		INC(i)
	END
END UpperCase;

(** conversion functions *)

(** converts a boolean value to a string *)
PROCEDURE BoolToStr*(b: BOOLEAN; VAR s: ARRAY OF CHAR);
CONST True = "True"; False = "False";
BEGIN
	IF b THEN COPY(True, s)
	ELSE COPY(False, s)
	END	
END BoolToStr;

(** converts a string to a boolean value: b := CAP(s[0]) = "T" *)
PROCEDURE StrToBool*(s: ARRAY OF CHAR; VAR b: BOOLEAN);
BEGIN b := CAP(s[0]) = "T"
END StrToBool;

(** converts an integer value to a string *)
PROCEDURE IntToStr*(i: LONGINT; VAR s: ARRAY OF CHAR);
VAR j,k: LONGINT; digits: ARRAY 10 OF LONGINT;
BEGIN
	IF (i = MIN(LONGINT)) THEN COPY("-2147483648", s)
	ELSE
		IF (i < 0) THEN i := -i; s[0] := "-"; j := 1
		ELSE j := 0
		END;
		
		k := 0; digits[k] := 0;
		WHILE (i > 0) DO
			digits[k] := i MOD 10; i := i DIV 10;
			INC(k)
		END;
		IF (k > 0) THEN DEC(k) END; (* no leading "0" *)
		
		WHILE (k >= 0) DO
			s[j] := CHR(digits[k] + ORD("0"));
			INC(j); DEC(k)
		END;
		s[j] := 0X
	END
END IntToStr;

(** converts a string to an integer. Leading whitespace is ignored *)
(* adopted from Strings.Mod *)
PROCEDURE StrToInt*(str: ARRAY OF CHAR; VAR val: LONGINT);
VAR i, d: LONGINT; neg: BOOLEAN;
BEGIN
	i := 0; WHILE (str[i] # 0X) & (str[i] <= " ") DO INC(i) END;
	neg := FALSE; 
	IF (str[i] = "+") THEN INC(i)
	ELSIF (str[i] = "-") THEN neg := TRUE; INC(i)
	END;
	
	val := 0;
	WHILE (str[i] >= "0") & (str[i] <= "9") DO
		d := ORD(str[i])-ORD("0");
		IF (val <= ((MAX(LONGINT)-d) DIV 10)) THEN val := 10*val+d
		ELSIF neg & (val = 214748364) & (d = 8) & ((str[i] < "0") OR (str[i] > "9")) THEN
			val := MIN(LONGINT); neg := FALSE
		ELSE
			HALT(99)
		END;
		INC(i)
	END;
	IF neg THEN val := -val END
END StrToInt;

(** Convert the substring beginning at position i in str into an integer. Leading whitespace is ignored.
	After the conversion i points to the first character after the integer. *)
(* adopted from Strings.Mod *)
PROCEDURE StrToIntPos*(VAR str: ARRAY OF CHAR; VAR val, i: LONGINT);
VAR noStr: ARRAY 16 OF CHAR;
BEGIN
	WHILE (str[i] # 0X) & (str[i] <= " ") DO INC(i) END;
	val := 0;
	IF str[i] = "-" THEN
		noStr[val] := str[i]; INC(val); INC(i);
		WHILE (str[i] # 0X) & (str[i] <= " ") DO INC(i) END
	END;
	WHILE (str[i] >= "0") & (str[i] <= "9") DO noStr[val] := str[i]; INC(val); INC(i) END;
	noStr[val] := 0X;
	StrToInt(noStr, val)
END StrToIntPos;

(** converts an integer value to a hex string *)
PROCEDURE IntToHexStr*(h, width: LONGINT; VAR s: ARRAY OF CHAR);
VAR c: CHAR;
BEGIN
	IF (width <= 0) THEN width := 8 END;
	
	s[width+1] := 0X;
	WHILE (width >= 0) DO
		c := CHR(h MOD 10H + ORD("0"));
		IF (c > "9") THEN c := CHR((h MOD 10H - 10) + ORD("A")) END;
		s[width] := c; h := h DIV 10H; DEC(width)
	END
END IntToHexStr;

(** converts a hex string to an integer. Leading whitespace is ignored. res=Ok indicates success, val=0 on failure. *)
PROCEDURE HexStrToInt*(str: ARRAY OF CHAR; VAR val, res: LONGINT);
VAR i, len: LONGINT; c: CHAR;
BEGIN
	res := 0; len := LEN(str); val := 0;
	i := 0; WHILE (i < len) & (str[i] # 0X) & (str[i] <= " ") DO INC(i) END;
	WHILE (i < len) & (str[i] # 0X) DO 
		c := str[i];
		IF (c >= "0") & (c <= "9") THEN 
			val := val * 16 + (ORD(c)-ORD("0")) 
		ELSIF (CAP(c) >= "A") & (CAP(c) <= "F") THEN 
			val := val * 16 + (ORD(CAP(c))-ORD("A") + 10)
		ELSE 
			res := -1; val := 0; RETURN
		END;
		INC(i)
	END
END HexStrToInt;

(** converts a real value to a string *)
(* adopted from Strings.Mod *)
PROCEDURE FloatToStr*(x: LONGREAL; n, f, D: LONGINT; VAR str: ARRAY OF CHAR);
VAR pos, len, e, i, h, l: LONGINT; r, z: LONGREAL; d: ARRAY 16 OF CHAR; s: CHAR;

	PROCEDURE Wr(ch: CHAR);
	BEGIN IF pos < len THEN str[pos] := ch; INC(pos) END;
	END Wr;
	
BEGIN
	len := LEN(str)-1; pos := 0;
	e := Reals.ExpoL(x);
	IF (e = 2047) OR (ABS(D) > 308) THEN
		Wr("N"); Wr("a"); Wr("N")
	ELSE
		IF D = 0 THEN DEC(n, 2) ELSE DEC(n, 7) END;
		IF n < 2 THEN n := 2 END;
		IF f < 0 THEN f := 0 END;
		IF n < f + 2 THEN n := f + 2 END;
		DEC(n, f);
		IF (e # 0) & (x < 0) THEN s := "-"; x := - x ELSE s := " " END;
		IF e = 0 THEN
			h := 0; l := 0; DEC(e, D-1) (* no denormals *)
		ELSE
			e := (e - 1023) * 301029 DIV 1000000; (* ln(2)/ln(10) = 0.301029996 *)
			z := Reals.Ten(e+1);
			IF x >= z THEN x := x/z; INC(e) ELSE x:= x * Reals.Ten(-e) END;
			DEC(e, D-1); i := -(e+f);
			IF i <= 0 THEN r := 5 * Reals.Ten(i) ELSE r := 0 END;
			IF x >= 10 THEN
				x := x * Reals.Ten(-1) + r; INC(e)
			ELSE
				x := x + r;
				IF x >= 10 THEN x := x * Reals.Ten(-1); INC(e) END
			END;
			x := x * Reals.Ten(7); h:= ENTIER(x); x := (x-h) * Reals.Ten(8); l := ENTIER(x)
		END;
		i := 15;
		WHILE i > 7 DO d[i] := CHR(l MOD 10 + ORD("0")); l := l DIV 10; DEC(i) END;
		WHILE i >= 0 DO d[i] := CHR(h MOD 10 + ORD("0")); h := h DIV 10; DEC(i) END;
		IF n <= e THEN n := e + 1 END;
		IF e > 0 THEN
			WHILE n > e DO Wr(" "); DEC(n) END;
			Wr(s); e:= 0;
			WHILE n > 0 DO
				DEC(n);
				IF e < 16 THEN Wr(d[e]); INC(e) ELSE Wr("0") END
			END;
			Wr(".")
		ELSE
			WHILE n > 1 DO Wr(" "); DEC(n) END;
			Wr(s); Wr("0"); Wr(".");
			WHILE (0 < f) & (e < 0) DO Wr("0"); DEC(f); INC(e) END
		END;
		WHILE f > 0 DO
			DEC(f);
			IF e < 16 THEN Wr(d[e]); INC(e) ELSE Wr("0") END
		END;
		IF D # 0 THEN
			IF D < 0 THEN Wr("D"); Wr("-"); D := - D
			ELSE Wr("D"); Wr("+")
			END;
			Wr(CHR(D DIV 100 + ORD("0"))); D := D MOD 100;
			Wr(CHR(D DIV 10 + ORD("0"))); Wr(CHR(D MOD 10 + ORD("0")))
		END
	END;
	str[pos] := 0X
END FloatToStr;

(** converts a string to a real value *)
(* adopted from Strings.Mod *)
PROCEDURE StrToFloat*(s: ARRAY OF CHAR; VAR r: LONGREAL);
VAR p, e: INTEGER; y, g: LONGREAL; neg, negE: BOOLEAN;
BEGIN
	p := 0;
	WHILE (s[p] = " ") OR (s[p] = "0") DO INC(p) END;
	IF s[p] = "-" THEN neg := TRUE; INC(p) ELSE neg := FALSE END;
	WHILE (s[p] = " ") OR (s[p] = "0") DO INC(p) END;
	
	y := 0;
	WHILE ("0" <= s[p]) & (s[p] <= "9") DO
		y := y * 10 + (ORD(s[p]) - 30H);
		INC(p);
	END;
	IF s[p] = "." THEN
		INC(p); g := 1; 
		WHILE ("0" <= s[p]) & (s[p] <= "9") DO
			g := g / 10; y := y + g * (ORD(s[p]) - 30H);
			INC(p);
		END;
	END;
	IF (s[p] = "D") OR (s[p] = "E") THEN
		INC(p); e := 0;
		IF s[p] = "-" THEN negE := TRUE; INC(p) ELSE negE := FALSE END;
		WHILE (s[p] = "0") DO INC(p) END;
		WHILE ("0" <= s[p]) & (s[p] <= "9") DO
			e := e * 10 + (ORD(s[p]) - 30H);
			INC(p);
		END;
		IF negE THEN y := y / Reals.Ten(e)
		ELSE y := y * Reals.Ten(e) END;
	END;
	IF neg THEN y := -y END;
	r := y
END StrToFloat;

(** converts a set to a string *)
(* adopted from Strings.Mod *)
PROCEDURE SetToStr*(set: SET; VAR s: ARRAY OF CHAR);
VAR i, j, k: INTEGER; noFirst: BOOLEAN;
BEGIN
	s[0] := "{"; i := 0; k := 1; noFirst := FALSE;
	WHILE i <= MAX(SET) DO
		IF i IN set THEN
			IF noFirst THEN s[k] := ","; INC(k) ELSE noFirst := TRUE END;
			IF i >= 10 THEN s[k] := CHR(i DIV 10 + 30H); INC(k) END;
			s[k] := CHR(i MOD 10 + 30H); INC(k);
			j := i; INC(i);
			WHILE (i <= MAX(SET)) & (i IN set) DO INC(i) END;
			IF i-2 > j THEN
				s[k] := "."; s[k+1] := "."; INC(k, 2); j := i - 1;
				IF j >= 10 THEN s[k] := CHR(j DIV 10 + 30H); INC(k) END;
				s[k] := CHR(j MOD 10 + 30H); INC(k)
			ELSE i := j
			END
		END;
		INC(i)
	END;
	s[k] := "}"; s[k+1] := 0X
END SetToStr;

(** converts a string to a set *)
(* adopted from Strings.Mod *)
PROCEDURE StrToSet*(str: ARRAY OF CHAR; VAR set: SET);
VAR i, d, d1: INTEGER; dot: BOOLEAN;
BEGIN
	set := {}; dot := FALSE;
	i := 0; 
	WHILE (str[i] # 0X) & (str[i] # "}") DO
		WHILE (str[i] # 0X) & ((str[i] < "0") OR (str[i] > "9")) DO INC(i) END;
		d := 0; WHILE (str[i] >= "0") & (str[i] <= "9") DO d := d*10 + ORD(str[i]) - 30H; INC(i) END;
		IF d <= MAX(SET) THEN INCL(set, d) END;
		IF dot THEN
			d1 := 0;
			WHILE (d1 <= MAX(SET)) & (d1 < d) DO INCL(set, d1); INC(d1) END;
			dot := FALSE
		END;
		WHILE (str[i] = " ") DO INC(i) END;
		IF (str[i] = ".") THEN d1 := d + 1; dot := TRUE END
	END
END StrToSet;

(** converts a time to a string, using the 'TimeFormat' format. C.f. FormatDateTime *)
PROCEDURE TimeToStr*(time: TDateTime; VAR s: ARRAY OF CHAR);
BEGIN FormatDateTime(TimeFormat, time, s)
END TimeToStr;

(** converts a string to a time *)
(* adopted from Strings.Mod *)
PROCEDURE StrToTime*(str: ARRAY OF CHAR; VAR dt: TDateTime);
VAR i: LONGINT;
BEGIN
	i := 0;
	WHILE (str[i] # 0X) & ((str[i] < "0") OR (str[i] > "9")) DO INC(i) END;
	StrToIntPos(str, dt.Hour, i);
	WHILE (str[i] # 0X) & ((str[i] < "0") OR (str[i] > "9")) DO INC(i) END;
	StrToIntPos(str, dt.Minute, i);
	WHILE (str[i] # 0X) & ((str[i] < "0") OR (str[i] > "9")) DO INC(i) END;
	StrToIntPos(str, dt.Second, i);
	Check(dt)
END StrToTime;

(** converts a date to a string, using the 'DateFormat' format. C.f. FormatDateTime *)
PROCEDURE DateToStr*(date: TDateTime; VAR s: ARRAY OF CHAR);
BEGIN FormatDateTime(DateFormat, date, s)
END DateToStr;

(** Convert a string of the form 'day month year' into an date value. Leading whitespace is ignored. *)
PROCEDURE StrToDate*(str: ARRAY OF CHAR; VAR dt: TDateTime);
VAR i: LONGINT;
BEGIN
	i := 0;
	WHILE (str[i] # 0X) & ((str[i] < "0") OR (str[i] > "9")) DO INC(i) END;
	StrToIntPos(str, dt.Day, i);
	WHILE (str[i] # 0X) & ((str[i] < "0") OR (str[i] > "9")) DO INC(i) END;
	StrToIntPos(str, dt.Month, i);
	WHILE (str[i] # 0X) & ((str[i] < "0") OR (str[i] > "9")) DO INC(i) END;
	StrToIntPos(str, dt.Year, i);
	Check(dt)
END StrToDate;

(** converts a TDateTime into a string. 
	Format rules:
	yyyy	->	four-digit year, e.g. 2001
	yy		->	two-digit year, e.g. 01
	mmmm ->	clear-text month, e.g. May
	mmm  ->  clear-text month, abbreviated, e.g. Sep
	mm	->	two-digit month, e.g. 05
	m		->	month, e.g. 5
	dd		->	two-digit day, e.g. 02
	d		->	day, e.g. 2 or 15
	wwww	-> clear-text week-day, e.g. Monday
	www	->  clear-text week-day, e.g. Mon
	
	hh		->	two-digit hour, e.g. 08
	h		-> 	hour, e.g. 8
	nn		-> two-digit minute, e.g. 03
	n		-> minute, e.g. 3
	ss		-> two-digit second, e.g. 00
	s		-> second, e.g. 0
	any other characters will be copied 1:1 to the result string
	
	Examples:
	"yyyy.mm.dd hh:nn:ss"	-> "2002.01.01 17:08:00"
	"yyyyyy.m.ddd"				-> "002002.1.001"
	"wwww, mmmm d, yyyy"			-> "Tuesday, September 11, 2001"
*)
PROCEDURE FormatDateTime*(format: ARRAY OF CHAR; dt: TDateTime; VAR result: ARRAY OF CHAR);
VAR i,k,l,len,n,m,y,w,dw: LONGINT;

	PROCEDURE IntToStr(v, len: LONGINT; VAR s: ARRAY OF CHAR; VAR pos: LONGINT);
	VAR i: LONGINT;
	BEGIN
		FOR i := 1 TO len DO s[pos+len-i] := CHR(ORD("0") + v MOD 10); v := v DIV 10 END;
		INC(pos, len)
	END IntToStr;
	
BEGIN
	k := 0;
	IF ValidDateTime(dt) THEN
		i := 0;
		WHILE (format[i] # 0X) DO
			n := 1; WHILE (format[i+n] = format[i]) DO INC(n) END;
			len := n;
			CASE format[i] OF
			|"w": WeekDate(dt, y, w, dw); DEC(dw);
					IF (len >= 4) THEN len := 10 END;
					l := 0; WHILE (l < len) & (Days[dw,l] # 0X) DO result[k] := Days[dw,l]; INC(k); INC(l) END;
			|"y": IntToStr(dt.Year, n, result, k);
			|"m": IF (n >= 3) THEN
						m := dt.Month-1; ASSERT((m>=0) & (m<12));
						IF (len > 3) THEN len := 12 END;
						l := 0; WHILE (l < len) & (Months[m,l] # 0X) DO result[k] := Months[m, l]; INC(k); INC(l) END
					ELSE IntToStr(dt.Month, n, result, k)
					END;
			|"d": IF (len=1) & (dt.Day > 9) THEN len := 2 END;
					IntToStr(dt.Day, len, result, k);
			|"h": IF (len=1) & (dt.Hour > 9) THEN len := 2 END;
					IntToStr(dt.Hour, len, result, k);
			|"n": IF (len=1) & (dt.Minute > 9) THEN len := 2 END;
					IntToStr(dt.Minute, len, result, k);
			|"s": IF (len=1) & (dt.Second > 9) THEN len := 2 END; 
					IntToStr(dt.Second, len, result, k);
			ELSE result[k] := format[i]; INC(k); n := 1
			END;
			INC(i, n)
		END
	END;
	result[k] := 0X
END FormatDateTime;

PROCEDURE NewString*(str : ARRAY OF CHAR) : String;
VAR l : LONGINT; s : String;
BEGIN
	l := Length(str) + 1;
	NEW(s, l);
	COPY(str, s^);
	RETURN s
END NewString;

BEGIN
	Months[0] := "January"; Months[1] := "February"; Months[2] := "March"; Months[3] := "April"; Months[4] := "May";
	Months[5] := "June"; Months[6] := "July"; Months[7] := "August"; Months[8] := "September";
	Months[9] := "October"; Months[10] := "November"; Months[11] := "December";
	Days[0] := "Monday"; Days[1] := "Tuesday"; Days[2] := "Wednesday"; Days[3] := "Thursday"; 
	Days[4] := "Friday"; Days[5] := "Saturday"; Days[6] := "Sunday"; 
	NoDays[0] := 31; NoDays[1] := 28; NoDays[2] := 31; NoDays[3] := 30; NoDays[4] := 31; NoDays[5] := 30; 
	NoDays[6] := 31; NoDays[7] := 31; NoDays[8] := 30; NoDays[9] := 31; NoDays[10] := 30; NoDays[11] := 31;
	DateFormat := "dd.mmm.yyyy";
	TimeFormat := "hh:nn:ss"
END Utilities.

System.Free Utilities ~

