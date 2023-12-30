MODULE AosShellCommands; (* ejz,   *)
	IMPORT AosBoot, AosIO, AosPipes, AosModules, AosFS, Utilities, AosCommands;

	CONST
		MaxString = 256;

	TYPE
		String = ARRAY MaxString OF CHAR;

		CmdAlias = POINTER TO RECORD
			alias, cmd, help: String;
			next: CmdAlias
		END;

		AliasList = OBJECT
			VAR alias: CmdAlias;
			
			PROCEDURE Alias(alias, cmd, help: ARRAY OF CHAR);
				VAR a: CmdAlias;
			BEGIN {EXCLUSIVE}
				a := SELF.alias;
				WHILE (a # NIL) & (a.alias # alias) DO
					a := a.next
				END;
				IF a = NIL THEN
					NEW(a); a.next := SELF.alias; SELF.alias := a; COPY(alias, a.alias)
				END;
				COPY(cmd, a.cmd); COPY(help, a.help)
			END Alias;

			PROCEDURE Find(alias: ARRAY OF CHAR): CmdAlias;
				VAR a: CmdAlias;
			BEGIN {EXCLUSIVE}
				a := SELF.alias;
				WHILE (a # NIL) & (a.alias # alias) DO
					a := a.next
				END;
				RETURN a
			END Find;

			PROCEDURE List(out: AosIO.Writer);
				VAR a: CmdAlias;
			BEGIN {EXCLUSIVE}
				a := alias;
				WHILE a # NIL DO
					out.String(a.alias); out.Char(09X); out.String(a.cmd); out.Ln();
					IF a.help # "" THEN
						out.Char(09X); out.String(a.help); out.Ln()
					END;
					a := a.next
				END
			END List;

			PROCEDURE &Init();
			BEGIN
				alias := NIL;
				Alias("alias", "AosShellCommands.Alias", "alias [ [ alias cmd ] help ]");
				Alias("del", "AosShellCommands.Delete", "del { file }");
				Alias("dir", "AosShellCommands.Directory", "dir [ pattern ]");
				Alias("echo", "AosShellCommands.Echo", "echo { par }");
				Alias("exit", "AosShellCommands.Exit", "exit");
				Alias("free", "AosShellCommands.Free", "free mod");
				Alias("help", "AosShellCommands.Help", "help [ alias ]");
				Alias("mods", "AosShellCommands.Modules", "mods");
				Alias("start", "AosShellCommands.Start", "start cmd { pars }");
				Alias("ver", "AosShellCommands.Version", "ver")
			END Init;
		END AliasList;

		Context* = OBJECT (AosCommands.Context)
			VAR C: PTR; alias: AliasList;

			PROCEDURE &New*(C: PTR; in: AosIO.Reader; out, err: AosIO.Writer);
			BEGIN
				(*Init^(in, out, err);*)
				SELF.in := in; SELF.out := out; SELF.err := err;
				SELF.C := C; alias := NIL
			END New;
		END Context;

		Command = OBJECT
			VAR
				par: AosCommands.Parameters;
				ctx: Context;
				cmd: String;
				next: Command;

			PROCEDURE SetContext(C: PTR; in: AosIO.Reader; out, err: AosIO.Writer);
				VAR a: AliasList;
			BEGIN
				IF (C # ctx.C) OR (in # ctx.in) OR (out # ctx.out) OR (err # ctx.err) THEN
					a := ctx.alias;
					NEW(ctx, C, in, out, err); par.context := ctx;
					ctx.alias := a
				END
			END SetContext;

			PROCEDURE &Init(ctx: Context);
			BEGIN
				NEW(par); par.context := ctx; par.str := NIL; par.restart := FALSE;
				SELF.ctx := ctx; cmd := ""; next := NIL
			END Init;		
		END Command;

	PROCEDURE GetPar(par: PTR; VAR p: AosCommands.Parameters; VAR W: AosIO.Writer);
	BEGIN
		p := NIL; W := NIL;
		IF (par # NIL) & (par IS AosCommands.Parameters) THEN
			p := par(AosCommands.Parameters); W := p.context.out
		END
	END GetPar;

	PROCEDURE GetAliasList(p: AosCommands.Parameters): AliasList;
	BEGIN
		IF (p.context # NIL) & (p.context IS Context) THEN
			RETURN p.context(Context).alias
		END;
		RETURN NIL	
	END GetAliasList;

	PROCEDURE Close(p: AosCommands.Parameters);
		VAR ctx: Context;
	BEGIN
		IF (p.context # NIL) & (p.context IS Context) THEN
			ctx := p.context(Context);
			IF ctx.C IS AosPipes.Pipe THEN
				ctx.out.Update(); ctx.C(AosPipes.Pipe).Close()
			END
		END
	END Close;

	PROCEDURE Alias*(par: PTR): PTR;
		VAR
			p: AosCommands.Parameters; W: AosIO.Writer; al: AliasList;
			R: AosIO.StringReader; alias, cmd, help: String;
	BEGIN
		GetPar(par, p, W); al := GetAliasList(p);
		IF p.str # NIL THEN
			NEW(R, LEN(p.str)); R.Set(p.str^);
			R.SkipWhitespace(); R.String(alias);
			R.SkipWhitespace(); R.String(cmd);
			R.SkipWhitespace(); R.String(help);
			IF (alias # "") & (cmd # "") THEN
				W.String(alias); W.Char(09X); W.String(cmd); W.Ln();
				IF help # "" THEN
					W.Char(09X); W.String(help); W.Ln()
				END;
				al.Alias(alias, cmd, help);
				Close(p);
				RETURN NIL
			END
		END;
		al.List(W); Close(p);
		RETURN NIL	
	END Alias;

	PROCEDURE Delete*(par: PTR): PTR;
		VAR
			p: AosCommands.Parameters; W: AosIO.Writer;
			R: AosIO.StringReader; file: AosFS.FileName; res: LONGINT;
	BEGIN
		GetPar(par, p, W);
		IF p.str # NIL THEN
			NEW(R, LEN(p.str)); R.Set(p.str^);
			R.SkipWhitespace(); R.String(file);
			WHILE (R.res = AosIO.Ok) & (file # "") DO
				W.String(file); W.Char(09X);
				AosFS.Delete(file, res);
				IF res = AosIO.Ok THEN
					W.String("done")
				ELSE
					W.String("error: "); W.Int(res, 0)
				END;
				W.Ln();
				R.SkipWhitespace(); R.String(file)
			END
		END;
		Close(p);
		RETURN NIL	
	END Delete;

	PROCEDURE Directory*(par: PTR): PTR;
		VAR
			p: AosCommands.Parameters; W: AosIO.Writer; R: AosIO.StringReader; enum: AosFS.Enumerator;
			name: AosFS.FileName; flags: SET; time, date, size: LONGINT; tdrec: Utilities.TDateTime; str: ARRAY 32 OF CHAR;
	BEGIN
		GetPar(par, p, W);
		IF p.str # NIL THEN
			NEW(R, LEN(p.str)); R.Set(p.str^);
			R.SkipWhitespace(); R.String(str);
			IF str = "" THEN str := "*" END
		ELSE
			str := "*"
		END;
		NEW(enum);
		enum.Open(str, {AosFS.EnumSize, AosFS.EnumTime});
		WHILE enum.GetEntry(name, flags, time, date, size) DO
			W.String(name); W.Char(09X); W.Int(size, 0); W.Char(09X);
			tdrec := Utilities.OberonToDateTime(date, time);
			Utilities.TimeToStr(tdrec, str);
			W.String(str); W.Ln()
		END;
		Close(p);
		RETURN NIL	
	END Directory;

	PROCEDURE Echo*(par: PTR): PTR;
		VAR p: AosCommands.Parameters; W: AosIO.Writer; R: AosIO.Reader; ch: CHAR;
	BEGIN
		GetPar(par, p, W);
		IF p.str # NIL THEN
			W.String(p.str^); W.Ln()
		ELSE
			R := p.context.in; R.Char(ch);
			WHILE R.res = AosIO.Ok DO
				W.Char(ch); R.Char(ch)
			END
		END;
		Close(p);
		RETURN NIL	
	END Echo;

	PROCEDURE Exit*(par: PTR): PTR;
		VAR p: AosCommands.Parameters; W: AosIO.Writer; ctx: Context;
	BEGIN
		GetPar(par, p, W);
		IF (p.context # NIL) & (p.context IS Context) THEN
			W.Ln(); W.String("logout"); W.Ln();
			ctx := p.context(Context);
			IF ctx.C IS AosIO.Connection THEN
				ctx.C(AosIO.Connection).Close()
			END
		END;
		Close(p);
		RETURN NIL
	END Exit;

	PROCEDURE Free*(par: PTR): PTR;
		VAR
			p: AosCommands.Parameters; W: AosIO.Writer; R: AosIO.StringReader;
			name: AosModules.Name; msg: String; res: LONGINT;
	BEGIN
		GetPar(par, p, W);
		IF p.str # NIL THEN
			NEW(R, LEN(p.str)); R.Set(p.str^);
			R.SkipWhitespace(); R.String(name);
			IF name # "" THEN
				W.String(name); W.Char(09X);
				AosModules.FreeModule(name, res, msg);
				IF res = 0 THEN
					W.String("done")
				ELSE
					W.Int(res, 0); W.String(": "); W.String(msg)
				END;
				W.Ln()
			END
		END;
		Close(p);
		RETURN NIL
	END Free;

	PROCEDURE Help*(par: PTR): PTR;
		VAR
			p: AosCommands.Parameters; W: AosIO.Writer;
			R: AosIO.StringReader; name: String; al: AliasList; a: CmdAlias;
	BEGIN
		GetPar(par, p, W);
		IF p.str # NIL THEN
			NEW(R, LEN(p.str)); R.Set(p.str^);
			R.SkipWhitespace(); R.String(name);
			IF name = "" THEN name := "help" END;
			al := GetAliasList(p);
			a := al.Find(name);
			IF a # NIL THEN
				W.String(a.help)
			ELSE
				W.String(name); W.Char(09X); W.String("no such alias")
			END;
			W.Ln()
		END;
		Close(p);
		RETURN NIL
	END Help;

	PROCEDURE Modules*(par: PTR): PTR;
		VAR p: AosCommands.Parameters; W: AosIO.Writer; mod: AosModules.Module;
	BEGIN
		GetPar(par, p, W);
		mod := AosModules.root;
		WHILE mod # NIL DO
			W.String(mod.name); W.Char(09X);
			W.Int(mod.refcnt, 0); W.Ln();
			mod := mod.next
		END;
		Close(p);
		RETURN NIL
	END Modules;

	(*
		cmdline = cmdpar { "|" cmdpar } [ ( ">" | ">>" ) file ] .
		cmdpar = cmd { par } [ "<" file ] .
	*)
	PROCEDURE execute(par: AosCommands.Parameters; VAR cmdline: ARRAY OF CHAR; flags: SET; VAR res: LONGINT; VAR msg: ARRAY OF CHAR);
		VAR
			ctx: Context; R: AosIO.StringReader; cmd, prev, cmds: Command; i, j, p, ofs, len: LONGINT; ch, filter: CHAR;
			in, pR: AosIO.Reader; out, err, pW: AosIO.Writer; file: AosFS.FileName; F, newF: AosFS.File; fR: AosFS.Reader;
			fW: AosFS.Writer; pipe: AosPipes.Pipe; a: CmdAlias;
	BEGIN
		ctx := par.context(Context);		
		len := LEN(cmdline); newF := NIL; cmds := NIL; prev := NIL;
		IF ctx.alias = NIL THEN NEW(ctx.alias) END; ofs := 0;
		in := ctx.in; out := ctx.out; err := ctx.err; pipe := NIL;
		NEW(R, len); R.Set(cmdline); R.SkipWhitespace(); 
		LOOP
			NEW(cmd, ctx); R.String(cmd.cmd);
			IF prev # NIL THEN
				prev.next := cmd;
				AosIO.OpenReader(pR, pipe.Receive)
			ELSE
				cmds := cmd; pR := in
			END;
			prev := cmd;
			R.SkipWhitespace(); p := ofs + R.Pos();
			IF p < len THEN
				i := p; ch := cmdline[i];
				WHILE (ch # 0X) & (ch # "|") & (ch # "<") & (ch # ">") DO
					INC(i); ch := cmdline[i]
				END;
				filter := ch
			ELSE
				i := len; filter := 0X
			END;
			IF p < i THEN
				NEW(cmd.par.str, i-p+2); j := 0;
				ch := cmdline[p]; j := 0;
				WHILE (ch # 0X) & (p < i) DO
					cmd.par.str[j] := ch; INC(j);
					INC(p); ch := cmdline[p]
				END;
				cmd.par.str[j] := " "; INC(j);
				cmd.par.str[j] := 0X
			ELSE
				cmd.par.str := NIL
			END;
			CASE filter OF
			"|": ofs := i+1; R.SetRaw(cmdline, ofs, len-ofs);
					NEW(pipe, 1024);
					AosIO.OpenWriter(pW, pipe.Send);
					cmd.SetContext(pipe, pR, pW, err)
			|"<": ofs := i+1; R.SetRaw(cmdline, ofs, len-ofs);
					R.SkipWhitespace(); R.String(file);
					R.SkipWhitespace(); R.Char(ch);
					IF ch = "|" THEN
						NEW(pipe, 1024);
						AosIO.OpenWriter(pW, pipe.Send)
					ELSE
						pipe := NIL
					END;
					F := AosFS.Old(file);
					IF F # NIL THEN
						AosFS.OpenReader(fR, F, 0);
						IF pR # in THEN
							res := -1; COPY("invalid command syntax", msg); RETURN
						END;
						IF pipe # NIL THEN
							cmd.SetContext(pipe, fR, pW, err)
						ELSE
							cmd.SetContext(ctx.C, fR, out, err)
						END
					ELSE
						res := -1; COPY("input file not found", msg); RETURN
					END;
					IF pipe = NIL THEN
						R.SkipWhitespace();
						IF R.res # AosIO.EOF THEN
							res := -1; COPY("invalid command syntax", msg); RETURN
						END;
						EXIT
					END
			|">": IF cmdline[i+1] = ">" THEN
						ofs := i+2; R.SetRaw(cmdline, ofs, len-ofs);
						R.SkipWhitespace(); R.String(file);
						F := AosFS.Old(file);
						IF F # NIL THEN
							AosFS.OpenWriter(fW, F, F.Length());
							cmd.SetContext(ctx.C, pR, fW, err)
						ELSE
							res := -1; COPY("ouput file not found", msg); RETURN
						END
					ELSE
						ofs := i+1; R.SetRaw(cmdline, ofs, len-ofs);
						R.SkipWhitespace(); R.String(file);
						F := AosFS.New(file);
						IF F # NIL THEN
							AosFS.OpenWriter(fW, F, 0);
							cmd.SetContext(ctx.C, pR, fW, err);
							newF := F
						ELSE
							res := -1; COPY("ouput file not created", msg); RETURN
						END
					END;
					R.SkipWhitespace();
					IF R.res # AosIO.EOF THEN
						res := -1; COPY("invalid command syntax", msg); RETURN
					END;
					EXIT
			ELSE
				cmd.SetContext(ctx.C, pR, out, err); EXIT
			END;
			R.SkipWhitespace();
			IF R.res # AosIO.Ok THEN
				res := -1; COPY("invalid command syntax", msg); RETURN
			END
		END;
		prev := NIL; cmd := cmds;
		WHILE cmd # NIL DO
			a := ctx.alias.Find(cmd.cmd);
			IF a # NIL THEN COPY(a.cmd, cmd.cmd) END;
			IF cmd.next = NIL THEN
				AosCommands.Activate(cmd.cmd, cmd.par, flags, res, msg)
			ELSE
				AosCommands.Activate(cmd.cmd, cmd.par, {}, res, msg)
			END;
			IF res # 0 THEN RETURN END;
			prev := cmd; cmd := cmd.next
		END;
		IF newF # NIL THEN
			prev.ctx.out.Update();
			AosFS.Register(newF)
		END
	END execute;

	PROCEDURE Start*(par: PTR): PTR;
		VAR p: AosCommands.Parameters; W: AosIO.Writer; msg: String; res: LONGINT;
	BEGIN
		GetPar(par, p, W);
		IF p.str # NIL THEN
			execute(p, p.str^, {}, res, msg);
			IF res # 0 THEN
				W.Int(res, 0); W.String(": "); W.String(msg); W.Ln()
			END
		END;
		Close(p);
		RETURN NIL	
	END Start;

	PROCEDURE Version*(par: PTR): PTR;
		VAR p: AosCommands.Parameters; W: AosIO.Writer;
	BEGIN
		GetPar(par, p, W);
		W.String(AosBoot.version); W.Ln();
		Close(p);
		RETURN NIL	
	END Version;

	PROCEDURE Execute*(par: AosCommands.Parameters; VAR cmdline: ARRAY OF CHAR; VAR res: LONGINT; VAR msg: ARRAY OF CHAR);
	BEGIN
		execute(par, cmdline, {AosCommands.Wait}, res, msg)
	END Execute;

END AosShellCommands.
