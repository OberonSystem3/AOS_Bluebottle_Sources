(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosCommands; (** AUTHOR "pjm"; PURPOSE "Commands and parameters"; *)

IMPORT AosActive, AosIO, AosModules, AosOut;

CONST
		(** Activate flags. *)
	Wait* = 0;	(** Wait until the activated command returns. *)

	Ok* = 0;
	CommandNotFound* = 3901;
	CommandError* = 3902;

		(* Runner states *)
	Started = 0; Loaded = 1; Finished = 2;

TYPE
	String* = POINTER TO ARRAY OF CHAR;		(* Same meaning as String = Utilities.String;
													but Utilities.Obx must not become part of the kernel *)

	Context* = OBJECT
	VAR
		in- : AosIO.Reader;
		out-, err- : AosIO.Writer;

		PROCEDURE &Init*(in : AosIO.Reader; out, err : AosIO.Writer);
		BEGIN
			SELF.in := in; SELF.out := out; SELF.err := err;
		END Init;
	END Context;

	Parameters* = POINTER TO RECORD	(** parameters for communication between a command and its caller *)
		str* : String;	(** command line string *)
		restart* : BOOLEAN;	(** should the command be restarted when an exception occurs? *)
		context* : Context;
	END;

	Runner = OBJECT
	VAR
		par : Parameters; mod : AosModules.Module; cmdstr : String;
		proc : AosModules.CommandProc; parproc : AosModules.CommandParProc;
		i, j, state, res : LONGINT; ignore : PTR; exception : BOOLEAN;
		mname, cname : AosModules.Name;
		msg : ARRAY 256 OF CHAR;

		PROCEDURE &Init(VAR cmd : ARRAY OF CHAR; par : Parameters);
		VAR i : LONGINT;
		BEGIN
			IF par = NIL THEN NEW(par); par.str := empty; END;
			i := 0; WHILE cmd[i] # 0X DO INC(i); END;
			NEW(cmdstr, i+1); COPY(cmd, cmdstr^);
			SELF.par := par;
			par.restart := FALSE; exception := FALSE;
			state := Started;
			res := CommandError; COPY("Error starting command", msg);
		END Init;

		PROCEDURE Join(this : LONGINT; VAR res : LONGINT; VAR msg : ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			AWAIT(state >= this);
			res := SELF.res; COPY(SELF.msg, msg);
		END Join;

	BEGIN {ACTIVE, SAFE}
		IF ~exception THEN
			proc := NIL;
			exception := TRUE;	(* catch exceptions from now on *)
			i := 0; WHILE (cmdstr[i] # ".") & (cmdstr[i] # 0X) DO mname[i] := cmdstr[i]; INC(i); END;
			mname[i] := 0X; j := 0;
			IF cmdstr[i] = "." THEN INC(i); END;
			WHILE cmdstr[i] # 0X DO cname[j] := cmdstr[i]; INC(j); INC(i); END;
			cname[j] := 0X;
			mod := AosModules.ThisModule(mname, res, msg);	(* load the module *)
			IF (res = Ok) & (cname # "") THEN
		(*		proc := AosModules.ThisCommand(mod, cname);	(* look for the command *)
				IF proc # NIL THEN	(* old style command *)
					BEGIN {EXCLUSIVE} state := Loaded; END;
					AosOut.Enter; AosOut.String("Error: Old command "); AosOut.String(mname);
					AosOut.Char("."); AosOut.String(cname); AosOut.Exit;
					proc;	(* proc can call GetPar() and can modify restart flag *)
					par.restart := FALSE;	(* do not restart after normal exit, only on exception *)
					res := Ok; msg[0] := 0X;
				ELSE *)
					parproc := AosModules.ThisCommandPar(mod, cname);	(* look for the parameterized command *)
					IF parproc # NIL THEN	(* new style command *)
						BEGIN {EXCLUSIVE} state := Loaded; END;
						ignore := parproc(par);	(* parproc can modify restart flag *)
						par.restart := FALSE;	(* do not restart after normal exit, only on exception *)
						res := Ok; msg[0] := 0X;
					ELSE
						res := CommandNotFound; COPY("Command not found", msg);
					END;
			(*	END;*)
			END;
		ELSE
			AosOut.Enter; AosOut.String("AosCommands: Exception handled"); AosOut.Exit;
			res := CommandError; COPY("Error in command", msg);
		END;
		BEGIN {EXCLUSIVE} state := Finished; END;
		IF par.restart THEN
			IF proc # NIL THEN proc;
			ELSIF parproc # NIL THEN ignore := parproc(par);
			END;
		END;	(* handled exception *)
	END Runner;

VAR
	empty : String;

(** Can be called by a command to retrieve the parameters associated with its active object.
	Commands that want to be restarted on exception should set restart = TRUE in the returned Parameters record. *)

PROCEDURE GetPar*() : Parameters;
VAR r : PTR;
BEGIN
	r := AosActive.ActiveObject();
	IF (r # NIL) & (r IS Runner) THEN RETURN r(Runner).par;
	ELSE RETURN NIL;
	END;
END GetPar;

(** Activate a command in its own active object.
	Returns res = 0 if successful, otherwise msg contains error message.
	The command can call GetPar() to get its parameter, which is also passed directly. *)

PROCEDURE Activate*(cmd : ARRAY OF CHAR; par : Parameters; flags : SET; VAR res : LONGINT; VAR msg : ARRAY OF CHAR);
VAR run : Runner;
BEGIN
	NEW(run, cmd, par);
	run.Join(Loaded, res, msg);
	IF (res = Ok) & (Wait IN flags) THEN run.Join(Finished, res, msg); END
END Activate;

(** Activate a string of commands, including their parameters.
	The string is parsed from left to right and Activate is called for every command.
	Parsing stops at the end of the string, or when Activate returns an error.
	The flags are applied to every command, i.e., for sequential execution,
	use the Wait flag (the caller waits until all commands return).
	Syntax:
		cmds = [mode " " ] cmd {";" cmd} . 
		mode = "PAR" | "SEQ" .
		cmd = mod ["." proc] [" " params] .
		params = {<any character except ";">} .
*)

PROCEDURE Call*(cmds : ARRAY OF CHAR; flags : SET; VAR res : LONGINT; VAR msg : ARRAY OF CHAR);
VAR p : Parameters; i, j, k : LONGINT; mode : ARRAY 5 OF CHAR; par : ARRAY LEN(cmds) OF CHAR;
BEGIN
	i := 0; WHILE (i # 4) & (i # LEN(cmds)) DO mode[i] := cmds[i]; INC(i); END;
	mode[i] := 0X;	(* copy at most first 4 characters *)
	IF mode = "PAR " THEN EXCL(flags, Wait);
	ELSIF mode = "SEQ " THEN INCL(flags, Wait);
	ELSE i := 0;	(* reset to start *)
	END;
	LOOP
		k := 0;
		WHILE (cmds[i] # " ") & (cmds[i] # 09X) & (cmds[i] # 0DX) & (cmds[i] # 0AX) & (cmds[i] # 0X) & (cmds[i] # ";") DO cmds[k] := cmds[i]; INC(k); INC(i); END;
		IF k = 0 THEN EXIT; END;	(* end of string *)
		j := 0;
		IF (cmds[i] # ";") & (cmds[i] # 0X) THEN	(* parameters *)
			INC(i); WHILE (cmds[i] # 0X) & (cmds[i] # ";") DO par[j] := cmds[i]; INC(i); INC(j); END;
		END;
		IF cmds[i] = ";" THEN INC(i); END;
		par[j] := 0X; cmds[k] := 0X;
		NEW(p); NEW(p.str, j+1); COPY(par, p.str^);
		Activate(cmds, p, flags, res, msg);
		IF res # 0 THEN EXIT; END;
	END;
END Call;

(* Position a StringReader on the first meaningful character of the parameter(s) in the command line *)
PROCEDURE PosPar*(par : ANY; VAR sr : AosIO.StringReader);
VAR p : Parameters;
BEGIN
	p := par(Parameters);
	NEW(sr, LEN(p.str^));
	sr.Set(p.str^);
	sr.SkipWhitespace;
END PosPar;

(* Get the next INTEGER in the command parameter - h: TRUE for hex value, FALSE for integer *)
PROCEDURE GetInt*(VAR sr : AosIO.StringReader; VAR n : LONGINT; h : BOOLEAN);
BEGIN
	sr.Int(n, h);
	sr.SkipWhitespace;
END GetInt;

(* Get the next token in the command parameter *)
PROCEDURE GetTok*(VAR sr : AosIO.StringReader; VAR n : ARRAY OF CHAR);
BEGIN
	sr.Token(n);
	sr.SkipWhitespace;
END GetTok;

BEGIN
	NEW(empty, 1); empty[0] := 0X;
END AosCommands.

(*
to do:
o should Call allow more fine-grained control of concurrency, like the Unix shells? e.g. Call("(c1;c2;c3)&(c4;c5)")
*)
