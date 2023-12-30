(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosConsole; (** AUTHOR "pjm"; PURPOSE "Boot console"; *)

(*
Config strings:
	BootVol# = prefix [hash] [cache] alias [volpar] ["|" fspar].	(* # is "1".."9" *)
	alias = gen gen .	(* defines a volume and file system generator *)
	gen = mod "." cmd .
	
Examples:
	BootVol1="AOS AosFS IDE0#2"
	BootVol2="RAM RamFS 2000 4096"
	
	AosFS="AosDiskVolumes.New AosDiskFS.NewFS"
	RamFS="AosRAMVolumes.New AosDiskFS.NewFS"
	RFS="RfsClientProxy.New RfsFS.NewFS"
*)

IMPORT
	AosBoot, AosOut, AosModules, AosFS, AosLoader, AosCommands;

CONST
	Trace = FALSE;

PROCEDURE BootCommand(config: ARRAY OF CHAR; flags: SET);
VAR i, j, res: LONGINT; par: ARRAY 32 OF CHAR; s: ARRAY 256 OF CHAR;
BEGIN
	COPY(config, par);
	i := 0; j := 0; WHILE par[j] # 0X DO INC(j) END;
	LOOP
		AosBoot.GetConfig(par, s);
		IF s # "" THEN
			AosCommands.Call(s, flags, res, s);
			IF res # 0 THEN AosOut.Enter; AosOut.String(s); AosOut.Exit END
		END;
		INC(i);
		IF i = 10 THEN EXIT END;
		par[j] := CHR(ORD("0") + i); par[j+1] := 0X
	END
END BootCommand;

(*
PROCEDURE OpenVolume(vol: ARRAY OF CHAR);
VAR sysfs: AosFS.FileSystem; parvol, parfs: AosFS.Parameters; ignore: PTR;
BEGIN
	NEW(parvol); parvol.vol := NIL;
	NEW(parvol.str, LEN(vol)); COPY(vol, parvol.str^); parvol.restart := FALSE;
	COPY(SysPrefix, parvol.prefix);
	ignore := AosDiskVolumes.New(parvol);
	IF parvol.vol # NIL THEN
		INCL(parvol.vol.flags, AosFS.Boot);
		NEW(parfs);
		NEW(parfs.str, LEN(vol)); COPY(vol, parfs.str^); parfs.restart := FALSE;
		parfs.vol := parvol.vol; COPY(SysPrefix, parfs.prefix);
		ignore := AosDiskFS.NewFS(parfs);
		sysfs := AosFS.This(SysPrefix);
		IF sysfs # NIL THEN
			(* ok *)
		ELSE
			AosOut.String("AosConsole: Mount failed on "); AosOut.String(vol); AosOut.Ln
		END
	ELSE
		AosOut.String("AosConsole: Open failed on "); AosOut.String(vol); AosOut.Ln
	END
END OpenVolume;
*)

PROCEDURE GetString(VAR i: LONGINT; VAR r, s: ARRAY OF CHAR): BOOLEAN;
VAR j: LONGINT;
BEGIN
	WHILE r[i] = " " DO INC(i) END;
	j := 0; WHILE r[i] > " " DO s[j] := r[i]; INC(j); INC(i) END;
	s[j] := 0X;
	IF Trace THEN AosOut.String("GetString: "); AosOut.String(s); AosOut.Ln END;
	RETURN j # 0
END GetString;

PROCEDURE Error(VAR config, val: ARRAY OF CHAR; i: LONGINT);
VAR j: LONGINT; s: ARRAY 32 OF CHAR;
BEGIN
	s := "AosConsole: Bad ";
	AosOut.String(s);
	j := 0; WHILE s[j] # 0X DO INC(j) END; INC(i, j);
	AosOut.String(config);
	j := 0; WHILE config[j] # 0X DO INC(j) END; INC(i, j);
	AosOut.Char("="); AosOut.Char(22X); INC(i, 2);
	AosOut.String(val); AosOut.Char(22X); AosOut.Ln;
	WHILE i > 0 DO AosOut.Char(" "); DEC(i) END;
	AosOut.Char("^"); AosOut.Ln
END Error;

PROCEDURE Call(cmd: ARRAY OF CHAR; par: AosCommands.Parameters): BOOLEAN;
VAR res: LONGINT; msg: ARRAY 256 OF CHAR;
BEGIN
	AosCommands.Activate(cmd, par, {AosCommands.Wait}, res, msg);
	IF Trace THEN AosOut.String("Call: "); AosOut.String(cmd); AosOut.Int(res, 5); AosOut.Ln END;
	IF res # 0 THEN
		AosOut.String("AosConsole: "); AosOut.String(msg); AosOut.Ln
	END;
	RETURN res = 0
END Call;

PROCEDURE OpenVolume(config: ARRAY OF CHAR);
VAR
	i, j, k: LONGINT; parvol, parfs: AosFS.Parameters;
	volReady : BOOLEAN;
	prefix, alias: AosFS.Prefix; gen: ARRAY 64 OF CHAR; s: ARRAY 256 OF CHAR;
BEGIN
	AosBoot.GetConfig(config, s);	(* s = prefix alias [volpar] ["|" fspar] . *)
	IF s = "" THEN RETURN END;
	i := 0;
	IF ~GetString(i, s, prefix) THEN Error(config, s, i); RETURN END;
	IF ~GetString(i, s, alias) THEN Error(config, s, i); RETURN END;
		(* set parameter string *)
	IF s[i] = " " THEN INC(i) END;
	j := 0; WHILE (s[i] # 0X) & (s[i] # "|") DO s[j] := s[i]; INC(i); INC(j) END;
	IF s[i] = "|" THEN INC(i) END;
	s[j] := 0X;
	NEW(parvol); NEW(parvol.str, j+1); COPY(s, parvol.str^); parvol.restart := FALSE;
	j := 0; WHILE s[i] # 0X DO s[j] := s[i]; INC(i); INC(j) END;
	s[j] := 0X;
	NEW(parfs); NEW(parfs.str, j+1); COPY(s, parfs.str^); parfs.restart := FALSE;
		(* call volume generator *)
	AosBoot.GetConfig(alias, s);	(* s = gen gen . ; gen = mod "." cmd . *)
	k := 0;
	IF ~GetString(k, s, gen) THEN Error(alias, s, k); RETURN END;
		(* call volume generator *)
	volReady := FALSE;
	IF gen = "NIL" THEN volReady := TRUE
	ELSE
		IF Call(gen, parvol) & (parvol.vol # NIL) THEN
			INCL(parvol.vol.flags, AosFS.Boot); parfs.vol := parvol.vol;
			volReady := TRUE
		END
	END;
	IF volReady THEN
		COPY(prefix, parfs.prefix);
		(* call file system generator *)
		IF GetString(k, s, gen) THEN
			IF Call(gen, parfs) THEN parvol.vol := NIL END
		ELSE
			Error(alias, s, k)
		END
	END;	
	IF AosFS.This(prefix) = NIL THEN
		AosOut.String("AosConsole: Mount failed on "); AosOut.String(config); AosOut.Ln;
		IF parvol.vol # NIL THEN
			parvol.vol.Finalize()	(* unmount volume *)
		END
	END
END OpenVolume;

PROCEDURE OpenVolumes;
VAR config: ARRAY 16 OF CHAR; i: LONGINT;
BEGIN
	config := "BootVol#";
	FOR i := 1 TO 9 DO
		config[7] := CHR(ORD("0") + i); config[8] := 0X;
		OpenVolume(config)
	END
END OpenVolumes;

BEGIN
	AosModules.AddLoader(".Obx", AosLoader.LoadObj);
	OpenVolumes;
	BootCommand("Boot", {AosCommands.Wait});
	BootCommand("BootSystem", {})
END AosConsole.
