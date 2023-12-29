(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE PC; (** AUTHOR "prk / be"; PURPOSE "Parallel Compiler: main module"; *)
	
IMPORT
		AosCommands, AosModules, AosKernel, AosIO, AosFS,
		AosTexts, AosTextUtilities, 
		PCM, PCS, PCT, PC0, AosOut,
		Display, Oberon, Fonts, Texts, Out;

	CONST
		Trace = FALSE;
		Debug = FALSE;
		
		NoBreakPC = -1;
		
	VAR
		Nrep0, Nrep1: LONGINT;

		
	TYPE
		StringBuf = ARRAY 256 OF CHAR;
		
		TextReader = OBJECT
			VAR
				r: Texts.Reader;
				pos: LONGINT;

			PROCEDURE Receive(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
				VAR ch: CHAR;
			BEGIN
				len := 0;
				IF r.eot THEN
					res := AosIO.EOF
				ELSE
					(* I'm not sure if this possible *)
					IF (pos < Texts.Pos(r)-1) THEN INC(Nrep0) END;
					WHILE ~r.eot & (len < size) & (pos < Texts.Pos(r)) DO
						buf[ofs+len] := 20X;
						INC(len); INC(pos)
					END;
					
					WHILE ~r.eot & (len < size) DO
						Texts.Read(r, ch);
						IF ((r.lib = NIL) OR ~(r.lib IS Fonts.Font)) THEN
							(* I'm not sure if this possible *)
							IF (pos < Texts.Pos(r)-1) THEN INC(Nrep1) END;
							WHILE (len < size) & (pos < Texts.Pos(r)) DO
								buf[ofs+len] := 20X;
								INC(len); INC(pos)
							END
						ELSE
							buf[ofs+len] := ch;
							INC(len); INC(pos);
						END;
					END;
					res := 0
				END
			END Receive;
		END TextReader;

	VAR
		log: AosIO.Writer;
		W: Texts.Writer;
	
	PROCEDURE SignOn;
	BEGIN
		Texts.WriteString(W, "Parallel Compiler / prk"); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END SignOn;
	
	PROCEDURE ReportError(pos, err: LONGINT; msg: ARRAY OF CHAR);
	BEGIN
		Texts.WriteLn(W);
		Texts.Write(W, 9X);
		IF (err <= 400) OR (err >= 404) THEN
			Texts.WriteString(W, "pos"); Texts.WriteInt(W, pos, 7);
			Texts.WriteString(W, "  err"); Texts.WriteInt(W, err, 4)
		END;
		Texts.Write(W, 9X);
		Texts.WriteString(W, msg)
	END ReportError;
	
	PROCEDURE GetOptions(VAR S: Texts.Scanner; VAR opts: ARRAY OF CHAR);
		VAR i: LONGINT; ch: CHAR;
	BEGIN
		i := 0;
		WHILE opts[i] # 0X DO  INC(i)  END;
		WHILE (S.class = Texts.Char) & (S.c = Oberon.OptionChar) DO
			ch := S.nextCh;
			WHILE ch > " " DO
				opts[i] := ch;  INC(i);  Texts.Read(S, ch)
			END;
			opts[i] := " "; INC(i);
			S.nextCh := ch; Texts.Scan(S)
		END;
		opts[i] := 0X
	END GetOptions;
	
	PROCEDURE InOptions(VAR opt: ARRAY OF CHAR; ch: CHAR): BOOLEAN;
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE (opt[i] # 0X) & (opt[i] # ch) DO
			IF (opt[i] = ".") OR (opt[i] = "P") OR (opt[i] = "d") THEN
				REPEAT  INC(i)   UNTIL (opt[i] = 0X) OR (opt[i] = " ")
			ELSE INC(i) END
		END;
		RETURN opt[i] # 0X
	END InOptions;
	
	PROCEDURE Locate(F: Display.Frame;  T: Texts.Text;  pos: LONGINT);
	VAR M: Oberon.CaretMsg;  N: Oberon.ControlMsg;
	BEGIN
		IF pos < 0 THEN pos := 0
		ELSIF pos > T.len THEN pos := T.len
		END;
		N.F := NIL; N.id := Oberon.neutralize; Display.Broadcast(N);
		Oberon.FadeCursor(Oberon.Pointer);
		M.id := Oberon.set; M.F := F; M.car := F; M.text := T; M.pos := pos; Display.Broadcast(M)
	END Locate;

	PROCEDURE GetBreakPC(): LONGINT;
		VAR S: Texts.Scanner; t: Texts.Text;  beg, end, time: LONGINT;
	BEGIN
		Oberon.GetSelection(t, beg, end, time);
		IF time >= 0 THEN
			Texts.OpenScanner(S, t, beg); Texts.Scan(S);
			end := S.line;
			WHILE (S.class # Texts.Int) & (S.line = end) DO  Texts.Scan(S)  END;
		END;
		IF (time < 0) OR (S.class # Texts.Int) THEN
			Texts.WriteString(W, "  pc not selected"); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf);
			RETURN NoBreakPC
		ELSE
			RETURN S.i
		END
	END GetBreakPC;
	
	(** Compile an Oberon text
		opt:
			\s	allow symbol-file change
			\e	allow symbol-file extension
			\n	do not generate file ("dry run")
			\f	locate breakpoint
			\N	generate explicit NIL checks
			\x	disable array checks
			\a	disable asserts
			\z	full stack init (default = pointers only
			\.Suf	generate files with ".Suf" suffix
			\Ppre	prefix input files with "pre"
			\dpre	prefix output files with "pre"
			\Dproc	dump LIR code of "proc" (debug)
	*)
	PROCEDURE CompileText*(t: Texts.Text; pos: LONGINT; frame: Display.Frame; opt: ARRAY OF CHAR; VAR error: BOOLEAN);
		VAR f: BOOLEAN; pc: LONGINT; r: TextReader; b: AosIO.Reader;
	BEGIN
		IF t = NIL THEN
			Texts.WriteString(W, "No text marked"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			error := TRUE; RETURN
		END;
		f := InOptions(opt, "f");
		IF f THEN
			pc := GetBreakPC();
			IF pc = NoBreakPC THEN RETURN END
		END;
		NEW(r);
		Texts.OpenReader(r.r, t, pos);
		AosIO.OpenReader(b, r.Receive);
		PC0.Module(PCS.InitWithReader(b, t.len - pos), opt, pc, log, NIL, error);
		IF f THEN
			Locate(frame, t, PCM.breakpos)
		END
	END CompileText;

	(** Compile a file *)
	
	PROCEDURE CompileFile*(name, opt: ARRAY OF CHAR; VAR error: BOOLEAN);
		VAR pc: LONGINT;
	BEGIN
		IF InOptions(opt, "f") THEN
			pc := GetBreakPC();
			IF pc = NoBreakPC THEN RETURN END
		END;
		PC0.CompileFile(name, opt, pc, log, NIL, error);
	END CompileFile;
	
	(** CompileAsciiFile - this file is read using AosFS *)

	PROCEDURE CompileAsciiFile*(name, opt: ARRAY OF CHAR; VAR error: BOOLEAN);
		VAR pc: LONGINT;
	BEGIN
		IF InOptions(opt, "f") THEN
			pc := GetBreakPC();
			IF pc = NoBreakPC THEN RETURN END
		END;
		PC0.CompileAsciiFile(name, opt, pc, log, NIL, error)
	END CompileAsciiFile;

	PROCEDURE Compile*;
		VAR S: Texts.Scanner;  globalOpt, localOpt: ARRAY 32 OF CHAR;
			t: Texts.Text; pos, end, time, count: LONGINT;  frame: Display.Frame;
			name: ARRAY 64 OF CHAR; error: BOOLEAN;
	BEGIN
		PCT.InitDB(PCT.database);
		error := FALSE;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(S);
		globalOpt := "";  GetOptions(S, globalOpt);
		IF (S.class = Texts.Char) & ((S.c = "*") OR (S.c = "@")) THEN
			IF S.c = "*" THEN
				t := Oberon.MarkedText();  pos := 0;  frame := Oberon.MarkedFrame();
			ELSE (* S.c = "@" *)
				Oberon.GetSelection(t, pos, end, time);  frame := NIL;
				IF time < 0 THEN RETURN END
			END;
			Texts.Scan(S);
			GetOptions(S, globalOpt);
			CompileText(t, pos, frame, globalOpt, error);
		ELSIF ((S.class = Texts.Char) & (S.c = "^")) OR (S.class = Texts.Name) THEN
			IF (S.c = "^") THEN
				Oberon.GetSelection(t, pos, end, time);
				Texts.OpenScanner(S, t, pos); Texts.Scan(S)
			ELSE
				end := MAX(LONGINT)
			END;
			count := 0;
			WHILE (S.class = Texts.Name) & (Texts.Pos(S) - S.len <= end) & ~error DO
				INC(count);
				COPY(S.s, name);  COPY(globalOpt, localOpt);
				Texts.Scan(S);  GetOptions(S, localOpt);
				CompileFile(name, localOpt, error);
				IF count MOD 32 = 0 THEN PCT.InitDB(PCT.database) END
			END;
		END;
		PCT.InitDB(PCT.database);
	END Compile;
	
	PROCEDURE InitErrMsg;
		VAR s: Texts.Scanner; ch: CHAR;  e: ARRAY 128 OF CHAR; i, n: LONGINT;
	BEGIN
		Oberon.OpenScanner(s, "OP2.Errors"); Texts.Scan(s);
		IF s.class # Texts.Inval THEN
			REPEAT Texts.Scan(s) UNTIL s.eot OR (s.class = Texts.Int) & (s.i = 0);	(*errors: 0 .. *)
			WHILE ~s.eot & (s.class = Texts.Int) DO
				n := s.i;
				Texts.Read(s, ch); i := 0;
				WHILE ~s.eot & (ch # 0DX) DO  e[i] := ch; INC(i); Texts.Read(s, ch)  END;
				e[i] := 0X;
				PCM.SetErrorMsg(n, e);
				Texts.Scan(s);
			END;
			REPEAT Texts.Scan(s) UNTIL s.eot OR (s.class = Texts.Int) & (s.i = 200);	(*limitations: 200 .. *)
			WHILE ~s.eot & (s.class = Texts.Int) DO
				n := s.i;
				Texts.Read(s, ch); i := 0;
				WHILE ~s.eot & (ch # 0DX) DO  e[i] := ch; INC(i); Texts.Read(s, ch)  END;
				e[i] := 0X;
				PCM.SetErrorMsg(n, e);
				Texts.Scan(s);
			END
		END
	END InitErrMsg;
	
	PROCEDURE SenderToLog(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		VAR i: LONGINT; ch: CHAR;
	BEGIN
		FOR i := 0 TO len-1 DO
			ch := buf[ofs+i];
			IF ch # 0AX THEN Texts.Write(W, ch) END;
		END;
		Texts.Append(Oberon.Log, W.buf)
	END SenderToLog;

	
BEGIN
	Out.String("Parallel Compiler / prk"); Out.Ln;
	AosIO.OpenWriter(log, SenderToLog);
	(* InitErrMsg; *)
	Texts.OpenWriter(W); SignOn;
	IF Trace THEN PCM.LogWLn; PCM.LogWStr("PCCompiler.Trace on") END;
END PC.

(*
	25.11.03	mb	InitErrMsg moved to PC0
	20.09.03	prk	"/Dcode" compiler option added
	25.02.03	prk	PC split into PC0 (Aos pure) and PC (Oberon dependent)
	28.12.02	prk	CompileAsciiFile added (compiles from AosFS.File instead of Oberon.Text)
	11.06.02	prk	emit modified symbol file message to main log (not kernel log)
	12.04.02	prk	FullStackInit disabling compiler option
	08.03.02	prk	explicit garbage collection after each module removed
	08.02.02	prk	use Aos instead of Oberon modules
	05.02.02	prk	PCS takes AosIO.Reader as parameter, let PC handle the Oberon Text format
	18.01.02	prk	AosFS used instead of Files
	03.12.01	prk	AosTicks removed
	28.11.01	prk	explicitly install PCV, avoid depending on the import list sequence
	22.11.01	prk	improved flag handling
	01.11.01	prk	unlink untraced pointers explicitly
	21.08.01	prk	adapted for Aos 21.08.01, PC.Wrapper removed
	05.07.01	prk	optional explicit NIL checks
	04.07.01	prk	scope flags added, remove imported
	27.06.01	prk	StringPool cleaned up
	06.06.01	prk	use string pool for object names
	30.05.01	prk	destination (\d) compiler-option to install the back-end
	07.05.01	prk	Installable code generators moved to PCLIR; debug function added
	03.05.01	be	Installable code generators
	05.04.01	prk	PC.CompileFile exported for Hostess
	30.03.01	prk	object file version changed to 01X
	29.03.01	prk	Attributes.StrToTxt inlined
	25.03.01	prk	renamed, was PCCompiler
*)