(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE Aos; (** AUTHOR "pjm"; PURPOSE "Aos toolbox for Oberon"; *)

IMPORT AosActive, AosCommands, Texts, Oberon, Kernel;

VAR
	w: Texts.Writer;

PROCEDURE Call*;	(** [\w] ( cmd {parms} | ^ ) ~ *)
VAR
	s: Texts.Scanner; par: AosCommands.Parameters; i, len, pos, res, beg, end, time: LONGINT;
	flags: SET; text: Texts.Text; msg: ARRAY 128 OF CHAR; ch: CHAR;
BEGIN
	flags := {};
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	WHILE (s.class = Texts.Char) & (s.c = "\") DO
		Texts.Scan(s);
		IF s.class = Texts.Name THEN
			IF s.s = "w" THEN INCL(flags, AosCommands.Wait) END;
			Texts.Scan(s)
		END
	END;
	IF (s.class = Texts.Char) & (s.c = "^") THEN
		Oberon.GetSelection(text, beg, end, time);
		IF time # -1 THEN
			Texts.OpenScanner(s, text, beg);
			Texts.Scan(s);
		ELSE
			s.class := Texts.Inval
		END
	ELSE
		text := Oberon.Par.text
	END;
	IF s.class = Texts.Name THEN
		pos := Texts.Pos(s);
		Texts.Read(s, ch); len := 0;
		WHILE ~s.eot & (* (ch # 0DX) & *) (ch # "~") DO INC(len); Texts.Read(s, ch) END;
		NEW(par); NEW(par.str, len+1);
		Texts.OpenReader(s, text, pos);
		FOR i := 0 TO len-1 DO Texts.Read(s, par.str[i]) END;
		par.str[len] := 0X;
(*
		IF s.s = "Compiler.Compile" THEN
			Oberon.Par.text := text; Oberon.Par.pos := pos;
			Kernel.UnlockOberon
		END;
*)
		AosCommands.Activate(s.s, par, flags, res, msg);
(*
		IF s.s = "Compiler.Compile" THEN Kernel.LockOberon END;
*)
		IF res # 0 THEN
			Texts.WriteString(w, msg); Texts.WriteLn(w);
			Texts.Append(Oberon.Log, w.buf)
		END
	END
END Call;

PROCEDURE SetPriority*;	(** Low | Normal | High | priority *)
VAR s: Texts.Scanner;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF (s.class = Texts.Name) THEN
		s.class := Texts.Int;
		IF s.s = "Low" THEN s.i := AosActive.Low
		ELSIF s.s = "Normal" THEN s.i := AosActive.Normal
		ELSIF s.s = "High" THEN s.i := AosActive.High
		ELSE s.class := Texts.Inval
		END
	END;
	IF (s.class = Texts.Int) & (s.i >= AosActive.Low) & (s.i <= AosActive.High) THEN
		AosActive.SetPriority(s.i)
	END
END SetPriority;

BEGIN
	Texts.OpenWriter(w)
END Aos.

Aos.Call ^

Aos.SetPriority Low
Aos.SetPriority Normal
Aos.SetPriority High
