(* Copyright 2005-2006, Markus Heule, ETH Zurich *)

MODULE AosOSCUtilities;  (** AUTHOR "heulemar"; PURPOSE "OpenSoundControl: Basic utility functions"; *)

(* copied *mostly* from Utilities.Mod
	This module prevented me from recompiling the whole system, due to a chanchge of the function's definition.
	Probably if the changes, which are marked with comments, doesn't affect other parts of the system, this module
	can be deleted after integrating the changes to Utilities.Mod
*)

TYPE
	String* = POINTER TO ARRAY OF CHAR;
	
(* Old definiton:
PROCEDURE Length*(string: ARRAY OF CHAR): LONGINT;
*)
PROCEDURE Length*(VAR string: ARRAY OF CHAR): LONGINT;
VAR len: LONGINT;
BEGIN
	len := 0; WHILE (string[len] # 0X) DO INC(len) END;
	RETURN len
END Length;

(* Old definition:
PROCEDURE StartsWith*(prefix : ARRAY OF CHAR; toffset : LONGINT; VAR s : ARRAY OF CHAR) : BOOLEAN;
*)
PROCEDURE StartsWith*(VAR prefix : ARRAY OF CHAR; toffset : LONGINT; VAR s : ARRAY OF CHAR) : BOOLEAN;
VAR
	lenString, lenPrefix, i : LONGINT;
BEGIN
	lenString := Length(s);
	lenPrefix := Length(prefix);
	IF (toffset < 0) OR (toffset > lenString - lenPrefix) THEN
		RETURN FALSE;
	END;
	FOR i := 0 TO lenPrefix-1 DO
		IF prefix[i] # s[toffset + i] THEN RETURN FALSE; END;
	END;
	RETURN TRUE;
END StartsWith;	


(** copies s[index...index+count-1] to result *)
(* Old definition:
PROCEDURE Copy*(s: ARRAY OF CHAR; index, count: LONGINT; VAR result: ARRAY OF CHAR);
*)
PROCEDURE Copy*(VAR s: ARRAY OF CHAR; index, count: LONGINT; VAR result: ARRAY OF CHAR);
VAR i, l: LONGINT;
BEGIN
	i := 0; l := LEN(result)-1;
	WHILE (i < count) & (i < l) DO
		result[i] := s[index+i];
		INC(i)
	END;
	result[i] := 0X
END Copy;

PROCEDURE NewString*(str : ARRAY OF CHAR) : String;
VAR l : LONGINT; s : String;
BEGIN
	l := Length(str) + 1;
	NEW(s, l);
	COPY(str, s^);
	RETURN s
END NewString;

(* Tests if two strings are equal *)
(* This procedure makes sense, because "proc(..)^ = proc(..)^" is not supported by the compiler! *)
PROCEDURE Equal*(s1, s2 : String) : BOOLEAN;
BEGIN
	ASSERT(s1 # NIL);
	ASSERT(s2 # NIL);
	RETURN s1^ = s2^;
END Equal;

(* Returns a new string that is a substring of string s *)
(* s[endIndex-1] is the last character of the new string *)
PROCEDURE Substring*(beginIndex : LONGINT; endIndex : LONGINT; VAR s : ARRAY OF CHAR) : String;
VAR
	lenString, lenNewString : LONGINT;
	st : String;
BEGIN
	ASSERT(beginIndex >= 0);
	lenString := Length(s);
	ASSERT(endIndex <= lenString);
	lenNewString := endIndex - beginIndex;
	ASSERT(lenNewString >= 0);
	NEW(st, lenNewString + 1);
	Copy(s, beginIndex, lenNewString, st^);
	RETURN st;
END Substring;

(** returns TRUE if 'year' is a leap year *)
PROCEDURE LeapYear*(year: LONGINT): BOOLEAN;
BEGIN
	RETURN (year > 0) & (year MOD 4 = 0) & (~(year MOD 100 = 0) OR (year MOD 400 = 0))
END LeapYear;

END AosOSCUtilities.

	

	

