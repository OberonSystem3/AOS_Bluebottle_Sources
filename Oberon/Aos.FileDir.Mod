(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE FileDir;	(* pjm *)
(** AUTHOR "pjm"; PURPOSE "Oberon for Aos file directory"; *)

IMPORT AosFS, Kernel;

TYPE
	FileName* = AosFS.FileName;
	
	EntryHandler* = PROCEDURE (name: ARRAY OF CHAR; time, date, size: LONGINT; VAR continue: BOOLEAN);

VAR
	PathChar*: CHAR;

PROCEDURE Enumerate*(mask: ARRAY OF CHAR; detail: BOOLEAN; proc: EntryHandler);
VAR enum: AosFS.Enumerator; time, date, size: LONGINT; continue: BOOLEAN; name: FileName; flags: SET;
BEGIN
	NEW(enum);
	IF detail THEN enum.Open(mask, {AosFS.EnumSize, AosFS.EnumTime})
	ELSE enum.Open(mask, {})
	END;
	continue := TRUE;
	WHILE continue & enum.GetEntry(name, flags, time, date, size) DO
		proc(name, time, date, size, continue)
	END;
	enum.Close
END Enumerate;

BEGIN
	PathChar := "/"
END FileDir.
