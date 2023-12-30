MODULE JString;	(** AUTHOR "Simon L. Keel"; PURPOSE "Additional string-functions" *)

IMPORT
	Utilities;

TYPE
	String = Utilities.String;

(* Returns a new string that is a concatenation of s1 and s2: s := s1 || s2 *)
PROCEDURE ConcatToNew*(s1 : ARRAY OF CHAR; s2 : ARRAY OF CHAR) : String;
VAR
	s : String;
BEGIN
	NEW(s, Utilities.Length(s1) + Utilities.Length(s2) + 1);
	Utilities.Concat(s1, s2, s^);
	RETURN s;
END ConcatToNew;

(* Test if string s ends with the specified suffix *)
PROCEDURE EndsWith*(suffix : ARRAY OF CHAR; VAR s : ARRAY OF CHAR) : BOOLEAN;
BEGIN
	RETURN StartsWith(suffix, Utilities.Length(s)-Utilities.Length(suffix), s);
END EndsWith;

(* Tests if two strings are equal *)
(* This procedure makes sense, because "proc(..)^ = proc(..)^" is not supported by the compiler! *)
PROCEDURE Equal*(s1, s2 : String) : BOOLEAN;
BEGIN
	ASSERT(s1 # NIL);
	ASSERT(s2 # NIL);
	RETURN s1^ = s2^;
END Equal;

(* Returns the index within string s of the first occurrence of the specified character *)
PROCEDURE IndexOfChar2*(ch : CHAR; VAR s : ARRAY OF CHAR) : LONGINT;
BEGIN
	RETURN IndexOfChar(ch, 0, s);
END IndexOfChar2;

(* Returns the index within string s of the first occurrence of the specified character, starting the search at the specified index *)
PROCEDURE IndexOfChar*(ch : CHAR; fromIndex : LONGINT; VAR s : ARRAY OF CHAR) : LONGINT;
VAR
	lenString, i : LONGINT;
BEGIN
	lenString := Utilities.Length(s);
	IF fromIndex < 0 THEN
		fromIndex := 0;
	ELSIF fromIndex >= lenString THEN
		RETURN -1;
	END;
	FOR i := fromIndex TO lenString-1 DO
		IF s[i] = ch THEN RETURN i; END;
	END;
	RETURN -1;
END IndexOfChar;

(* Returns the index within string s of the last occurrence of the specified character *)
PROCEDURE LastIndexOfChar2*(ch : CHAR; VAR s : ARRAY OF CHAR) : LONGINT;
BEGIN
	RETURN LastIndexOfChar(ch, Utilities.Length(s)-1, s);
END LastIndexOfChar2;

(* Returns the index within string s of the last occurrence of the specified character, searching backward starting at the specified index *)
PROCEDURE LastIndexOfChar*(ch : CHAR; fromIndex : LONGINT; VAR s : ARRAY OF CHAR) : LONGINT;
VAR
	lenString, i : LONGINT;
BEGIN
	lenString := Utilities.Length(s);
	IF fromIndex >= lenString THEN
		fromIndex := lenString - 1;
	END;
	FOR i := fromIndex TO 0 BY -1 DO
		IF s[i] = ch THEN RETURN i; END;
	END;
	RETURN -1;
END LastIndexOfChar;

(* Returns a new string that is a copy of s in lower-case letters *)
PROCEDURE LowerCaseInNew*(VAR s : ARRAY OF CHAR) : String;
VAR
	n : String;
BEGIN
	n := Utilities.NewString(s);
	Utilities.LowerCase(n^);
	RETURN n;
END LowerCaseInNew;

(* Tests if string s starts with the specified prefix *)
PROCEDURE StartsWith2*(prefix : ARRAY OF CHAR; VAR s : ARRAY OF CHAR) : BOOLEAN;
BEGIN
	RETURN StartsWith(prefix, 0, s);
END StartsWith2;

(* Tests if string s starts with the specified prefix beginning a specified index *)
PROCEDURE StartsWith*(prefix : ARRAY OF CHAR; toffset : LONGINT; VAR s : ARRAY OF CHAR) : BOOLEAN;
VAR
	lenString, lenPrefix, i : LONGINT;
BEGIN
	lenString := Utilities.Length(s);
	lenPrefix := Utilities.Length(prefix);
	IF (toffset < 0) OR (toffset > lenString - lenPrefix) THEN
		RETURN FALSE;
	END;
	FOR i := 0 TO lenPrefix-1 DO
		IF prefix[i] # s[toffset + i] THEN RETURN FALSE; END;
	END;
	RETURN TRUE;
END StartsWith;

(* Returns a new string that is a substring of string s *)
PROCEDURE Substring2*(beginIndex : LONGINT; VAR s : ARRAY OF CHAR) : String;
BEGIN
	RETURN Substring(beginIndex, Utilities.Length(s), s);
END Substring2;

(* Returns a new string that is a substring of string s *)
(* s[endIndex-1] is the last character of the new string *)
PROCEDURE Substring*(beginIndex : LONGINT; endIndex : LONGINT; VAR s : ARRAY OF CHAR) : String;
VAR
	lenString, lenNewString : LONGINT;
	st : String;
BEGIN
	ASSERT(beginIndex >= 0);
	lenString := Utilities.Length(s);
	ASSERT(endIndex <= lenString);
	lenNewString := endIndex - beginIndex;
	ASSERT(lenNewString >= 0);
	NEW(st, lenNewString + 1);
	Utilities.Copy(s, beginIndex, lenNewString, st^);
	RETURN st;
END Substring;

(* Omitts leading and trailing whitespace of string s *)
PROCEDURE TrimWS*(VAR s : ARRAY OF CHAR);
VAR
	len, start, i : LONGINT;
BEGIN
	len := Utilities.Length(s);
	start := 0;
	WHILE (start < len) & (ORD(s[start]) < 33) DO
		INC(start);
	END;
	WHILE (start < len) & (ORD(s[len-1]) < 33) DO
		DEC(len);
	END;
	IF start > 0 THEN
		FOR i := 0 TO len - start - 1 DO
			s[i] := s[start + i];
		END;
		s[i] := 0X;
	ELSE
		s[len] := 0X;
	END;
END TrimWS;

(* Returns a new string that is a copy of s in upper-case letters *)
PROCEDURE UpperCaseInNew*(VAR s : ARRAY OF CHAR) : String;
VAR
	n : String;
BEGIN
	n := Utilities.NewString(s);
	Utilities.UpperCase(n^);
	RETURN n;
END UpperCaseInNew;

END JString.