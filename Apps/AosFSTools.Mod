(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosFSTools; (** AUTHOR "be"; PURPOSE "AosFS Tools"; *)

IMPORT AosCommands, AosIO, AosFS, AosConfig, AosOut;

PROCEDURE ExpandAlias(VAR alias, genvol, genfs: ARRAY OF CHAR);
VAR t: ARRAY 64 OF CHAR; i, j: LONGINT;
BEGIN
	genvol[0] := 0X; genfs[0] := 0X;
	t := "AosFS.Alias.";
	i := 0; WHILE t[i] # 0X DO INC(i) END;
	j := 0; WHILE alias[j] # 0X DO t[i] := alias[j]; INC(i); INC(j) END;
	t[i] := 0X;

	AosConfig.Get(t, t);
	
	i := 0;
	WHILE (t[i] # 0X) & (t[i] # ";") DO genvol[i] := t[i]; INC(i) END;
	genvol[i] := 0X;
	
	IF (t[i] = ";") THEN
		j := 0; INC(i);
		WHILE (t[i] # 0X) DO genfs[j] := t[i]; INC(j); INC(i) END;
		genfs[j] := 0X
	END
END ExpandAlias;

PROCEDURE OutErrMsg(par: AosFS.Parameters; cmd: ARRAY OF CHAR);
BEGIN
	IF par.str[0] = 0X THEN AosOut.String(cmd); AosOut.String(" failed")
	ELSE AosOut.String(par.str^)
	END
END OutErrMsg;

PROCEDURE Mount*(param: PTR): PTR;	(** prefix [hashSize] [cachesize] alias [volpar] ["|" fspar] ~ *)
VAR 
	p: AosCommands.Parameters; r: AosIO.StringReader;
	parvol, parfs: AosFS.Parameters; hashSize, cacheSize, i, k, res: LONGINT;
	par, alias, genvol, genfs, msg: ARRAY 64 OF CHAR; prefix: AosFS.Prefix;
BEGIN
	p := param(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^);
	
	r.String(prefix); r.SkipWhitespace;
	r.Int(hashSize, FALSE); r.SkipWhitespace; 
	IF (r.res = AosIO.FormatError) THEN hashSize := 0; r.res := AosIO.Ok
	ELSE
		r.Int(cacheSize, FALSE); r.SkipWhitespace;
		IF (r.res = AosIO.FormatError) THEN cacheSize := 0; r.res := AosIO.Ok END
	END;
	r.String(alias); r.SkipWhitespace;
	r.Ln(par);
	IF (prefix # "") & (alias # "") THEN
		ExpandAlias(alias, genvol, genfs);
		IF (AosFS.This(prefix) # NIL) THEN AosOut.String(prefix); AosOut.String("; already used")
		ELSIF (genvol = "") OR (genfs = "") THEN AosOut.String(prefix); AosOut.String(": unknown alias "); AosOut.String(alias)
		ELSE
			NEW(parvol); parvol.vol := NIL; res := 0;
			IF genvol # "NIL" THEN
				NEW(parvol.str, LEN(par));
				i := 0; WHILE (par[i] # 0X) & (par[i] # "|") DO parvol.str[i] := par[i]; INC(i) END;
				parvol.str[i] := 0X;
				parvol.restart := FALSE;
				COPY(prefix, parvol.prefix);
				AosCommands.Activate(genvol, parvol, {AosCommands.Wait}, res, msg);
				IF res # 0 THEN
					AosOut.String(msg)
				ELSE
					IF parvol.vol = NIL THEN OutErrMsg(parvol, genvol); res := 1 END
				END
			ELSE
				i := 0
			END;
			IF res = 0 THEN
				NEW(parfs);
				NEW(parfs.str, LEN(par));
				IF par[i] = "|" THEN INC(i) END;
				k := 0; WHILE par[i] # 0X DO parfs.str[k] := par[i]; INC(i); INC(k) END;
				parfs.str[k] := 0X;
				parfs.restart := FALSE;
				parfs.vol := parvol.vol; COPY(prefix, parfs.prefix);
				AosCommands.Activate(genfs, parfs, {AosCommands.Wait}, res, msg);
				IF res # 0 THEN
					AosOut.String(msg)
				ELSIF AosFS.This(prefix) = NIL THEN
					OutErrMsg(parfs, genfs); res := 1
				ELSE
					AosOut.String(prefix); AosOut.String(": mounted")
				END;
				IF (res # 0) & (parvol.vol # NIL) THEN
					parvol.vol.Finalize()	(* unmount volume *)
				END
			ELSE
				(* skip *)
			END
		END;
	ELSE
		AosOut.String('Expected parameters: prefix [hashSize] [cachesize] alias ([volpar] ["|" fspar]')
	END;
	AosOut.Ln;
	RETURN NIL
END Mount;

PROCEDURE Unmount*(par: PTR): PTR;	(** prefix[\f] *)
VAR p: AosCommands.Parameters; prefix: AosFS.Prefix; fs: AosFS.FileSystem; 
	i: LONGINT; force: BOOLEAN;
BEGIN
	p := par(AosCommands.Parameters);
	IF (p.str # NIL) THEN
		COPY(p.str^, prefix);
		i := 0; WHILE (prefix[i] # 0X) & (prefix[i] # ":") & (prefix[i] # "\") DO INC(i) END;
		force := (prefix[i] = "\") & (CAP(prefix[i+1]) = "F");
		prefix[i] := 0X;
		AosOut.String(prefix); AosOut.Char(":");
		fs := AosFS.This(prefix);
		IF fs # NIL THEN
			IF (fs.vol = NIL) OR force OR ~(AosFS.Boot IN fs.vol.flags) THEN
				AosFS.Remove(fs);
				AosOut.String(" unmounted")
			ELSE
				AosOut.String(" can't unmount boot volume. Use \f parameter to force unmounting.")
			END
		ELSE
			AosOut.String(" not found")
		END
	ELSE
		AosOut.String('Expected parameters: prefix["\f"]')
	END;
	AosOut.Ln;
	RETURN NIL
END Unmount;

PROCEDURE SetDefault*(par: PTR): PTR;	(** prefix *)
VAR p: AosCommands.Parameters; prefix: AosFS.Prefix; fs: AosFS.FileSystem; i: LONGINT; ft: AosFS.FileSystemTable;
BEGIN
	p := par(AosCommands.Parameters);
	IF (p.str # NIL) THEN
		COPY(p.str^, prefix);
		i := 0; WHILE (prefix[i] # 0X) & (prefix[i] # ":") DO INC(i) END;
		prefix[i] := 0X;
		fs := AosFS.This(prefix);
		IF fs # NIL THEN
			AosFS.Promote(fs);
			AosFS.GetList(ft);
			IF ft # NIL THEN
				AosOut.String("Path: ");
				FOR i := 0 TO LEN(ft)-1 DO
					AosOut.String(ft[i].prefix);  AosOut.String(" ")
				END
			END
		ELSE
			AosOut.String(prefix);  AosOut.String(": not found")
		END;
		AosOut.Ln
	END;
	RETURN NIL
END SetDefault;

PROCEDURE ModifyName(in, prefix: ARRAY OF CHAR;  add: BOOLEAN;  VAR out: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	IF add THEN
		i := 0; WHILE prefix[i] # 0X DO out[i] := prefix[i]; INC(i) END;
		j := 0; WHILE in[j] # 0X DO out[i] := in[j]; INC(i); INC(j) END;
		out[i] := 0X
	ELSE
		i := 0; WHILE (prefix[i] # 0X) & (in[i] = prefix[i]) DO INC(i) END;
		IF prefix[i] # 0X THEN i := 0 END;
		j := 0; WHILE in[i] # 0X DO out[j] := in[i]; INC(i); INC(j) END;
		out[j] := 0X
	END
END ModifyName;

(* using the NIST standard for Kibi, Mebi & Gibi: http://physics.nist.gov/cuu/Units/binary.html *)
PROCEDURE WriteK(k: LONGINT);
VAR suffix: ARRAY 3 OF CHAR;
BEGIN
	IF k < 10*1024 THEN COPY("Ki", suffix)
	ELSIF k < 10*1024*1024 THEN COPY("Mi", suffix); k := k DIV 1024
	ELSE COPY("Gi", suffix); k := k DIV (1024*1024)
	END;
	AosOut.Int(k, 1);  AosOut.String(suffix);  AosOut.String("B")
END WriteK;

PROCEDURE Watch*(par: PTR): PTR;
VAR free, total, i: LONGINT; fs: AosFS.FileSystem; ft: AosFS.FileSystemTable;
BEGIN
	AosOut.String("AosFSTools.Watch"); AosOut.Ln;
	AosFS.GetList(ft);
	IF ft # NIL THEN
		FOR i := 0 TO LEN(ft)-1 DO
			fs := ft[i];
			AosOut.String(fs.prefix);  AosOut.String(": "); AosOut.String(fs.desc);
			IF fs.vol # NIL THEN
				AosOut.String(" on "); AosOut.String(fs.vol.name);
				IF AosFS.ReadOnly IN fs.vol.flags THEN AosOut.String(" (read-only)") END;
				IF AosFS.Removable IN fs.vol.flags THEN AosOut.String(" (removable)") END;
				IF AosFS.Boot IN fs.vol.flags THEN AosOut.String(" (boot)") END;
				AosOut.Ln; AosOut.String("   ");
				free := ENTIER(fs.vol.Available()/1024.0D0 * fs.vol.blockSize);
				total := ENTIER(fs.vol.size/1024.0D0 * fs.vol.blockSize);
				WriteK(free);  AosOut.String(" of ");
				WriteK(total);  AosOut.String(" free")
			END;
			AosOut.Ln
		END
	END;
	RETURN NIL
END Watch;

END AosFSTools.

System.Free AosFSTools ~

Aos.Call AosFSTools.Watch
Aos.Call AosFSTools.Mount FAT FatFS IDE0#4~
Aos.Call AosFSTools.Unmount FAT~


