(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosFSTools; (** AUTHOR "be"; PURPOSE "AosFS Tools"; *)
(**
 * Usage:
 *
 *	AosFSTools.Mount prefix alias [volpar] ["|" fspar] ~		Mount the specified volume. 
 *	AosFSTools.Unmount prefix [\f] ~							Unmount the specified volume. Use /f to force unmounting.
 *
 *	AosFSTools.SetDefault prefix ~							Set the specified volume as default volume.
 *	AosFSTools.Watch ~										Diplays a list of all mounted file systems 
 *
 *	AosFSTools.CopyFiles [/io] {sourcefile " => " destfile} ~	Copy the specified files to 
 *	AosFSTools.RenameFiles {oldname " => " newname} ~	Rename files
 *	AosFSTools.DeleteFiles [/i] {file} ~						Delete the specified files
 * 	AosFSTools.Directory [/ts] ~								Show Directory (t: show creation times, s: show file sizes)
 *
 *	AosFSTools.Safe ~ 										disallow pattern matching 
 *	AosFSTools.Unsafe ~ 										allow pattern matching 
 *
 *	Parameters i and o:
 *
 *	i: 	ignore errors, e.g. continue with deletion of files if a file could not be deleted
 *	o:	force overwriting existing files
 *
 * Examples:
 * 
 *	AosFSTools.Mount FAT FatFS IDE0#4~
 * 	AosFSTools.Unmount FAT~
 *
 *	AosFSTools.CopyFiles AOS:AosConfig.XML => FAT:AosConfig.XML AOS:Test.Mod => FAT:Test.Mod ~
 *	AosFSTools.RenameFiles AosConfig.XML => AosConfig.Bak ~
 *	AosFSTools.DeleteFiles Test.Mod Bimbo.Mod ~
 *	AosFSTools.Directory /s ~
 *
 * Pattern matching:
 *
 *	Supported by: CopyFiles, RenameFiles, DeleteFiles and Directory
 *
 *	WARNING: If no prefix is specified, the source mask if checked against all files on all mounted volumes, i.e. the command
 *				AosFSTools.DeleteFiles * ~ would DELETE ALL FILES ON ALL MOUNTED partitions.
 *
 *	The source mask may contain an arbitrary number of '*' (matches any string) and '?' (matches any character) characters.
 *	For operations that have a target, the target mask semantics is the following:
 *
 *		- '?' characters are not allowed in the target mask
 *		- '*' characters are not allowed in the prefix and path
 *		- every occurence of the character '*' is replaced by ...
 *				... the source file name if there is no '.' character on the left side of the '*' character
 *				... the source file extension if there is at least one '.' character on the left side of the '*' character
 *
 *	Notes:
 *		- AosFS treats the right-most '.*' as file extension, e.g. the file extension of 'AosBimbo.Test.00.Bak.Mod' is '.Mod'
 *
 * History:
 *
 *	26.08.2005	Added CopyFiles, DeleteFiles, RenameFiles and Directory (staubesv)
 *	29.11.2006	Corrected EOF handling in GetFileLists, added Ignore and Overwrite parameters, arbitrary filelist size support, pattern matching  (staubesv)
 *)

IMPORT AosCommands, AosIO, AosFS, AosConfig, AosOut, Utilities, AosKernel;

CONST
	MaxNameLen = 512; (* Maximum file name length including path and 0X-termination *)

	InitialFilelistSize = 1024;	
	
	(* Special purpose characters (when used with AosOut.Char) *)
	FixedFont = 0EX; (* set fixed-width font *)
	ProportionalFont =0FX;  (* set proportial font (default) *)

	(* Layout for Directory operation *)
	Column1 = 30;
	FormatDateTime = "dd.mm.yyyy hh:nn:ss";

	Error = -1;
	
	FlagOverwrite = "O";	(* Overwrite file if it already exists *)
	FlagIgnoreErrors = "I";	(* Continue in case an error occurs *)
	FlagSize = "S";			(* Show file sizes *)
	FlagTime = "T";			(* Show file creation time *)

TYPE
	String = Utilities.String;

	FileList = POINTER TO ARRAY OF String;
	
VAR
	unsafeMode : BOOLEAN;
	
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

PROCEDURE Mount*(param: PTR): PTR; (** prefix alias [volpar] ["|" fspar] ~ *)
VAR 
	p: AosCommands.Parameters; r: AosIO.StringReader;
	parvol, parfs: AosFS.Parameters; i, k, res: LONGINT;
	par, alias, genvol, genfs, msg: ARRAY 64 OF CHAR; prefix: AosFS.Prefix;
BEGIN
	p := param(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^);
	
	r.String(prefix); r.SkipWhitespace;
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
		AosOut.String('Expected parameters: prefix alias ([volpar] ["|" fspar]')
	END;
	AosOut.Ln;
	RETURN NIL
END Mount;

PROCEDURE Unmount*(par: PTR): PTR; (** prefix[\f] *)
VAR p: AosCommands.Parameters; prefix: AosFS.Prefix; fs: AosFS.FileSystem; 
	i: LONGINT; force: BOOLEAN;
BEGIN
	p := par(AosCommands.Parameters);
	IF (p.str # NIL) THEN
		COPY(p.str^, prefix);
		i := 0; WHILE (prefix[i] # 0X) & (prefix[i] # ":") & (prefix[i] # " ")  & (prefix[i] # "\") DO INC(i) END;
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

(* using the NIST standard for Kibi, Mebi & Gibi: http://physics.nist.gov/cuu/Units/binary.html *)
PROCEDURE WriteK( k: LONGINT);
VAR suffix: ARRAY 3 OF CHAR;
BEGIN
	IF k < 10*1024 THEN COPY("Ki", suffix)
	ELSIF k < 10*1024*1024 THEN COPY("Mi", suffix); k := k DIV 1024
	ELSE COPY("Gi", suffix); k := k DIV (1024*1024)
	END;
	AosOut.Int(k, 1);  AosOut.String(suffix);  AosOut.String("B");
END WriteK;

PROCEDURE Watch*(par: PTR): PTR; (** ~ *)
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

(** File operations *)

(* Returns TRUE when the specified character is contained in the string, FALSE otherwise *)
PROCEDURE StringContains(string: ARRAY OF CHAR; ch : CHAR) : BOOLEAN;
VAR i : LONGINT;
BEGIN
	Utilities.UpperCase(string);
	IF ("a" <= ch) & (ch <= "z") THEN ch := CAP(ch); END;
	i := 0; 
	LOOP
		IF string[i] = ch THEN RETURN TRUE; END;
		IF string[i] = 0X THEN EXIT; END;
		INC(i);
		IF (i > LEN(string)-1) THEN EXIT; END;
	END;
	RETURN FALSE;
END StringContains;

(* Simple text formatting (assuming the use of fixed fonts) *)
PROCEDURE Align(string : ARRAY OF CHAR);
VAR spaces, i : LONGINT; 
BEGIN
	spaces := Column1 - Utilities.Length(string); IF spaces < 0 THEN spaces := 0; END;
	FOR i := 0 TO spaces-1 DO AosOut.Char(" "); END;
END Align;

PROCEDURE Directory*(par : ANY) : ANY; (** [/ST] [pattern] *)
VAR 
	r : AosIO.StringReader; 
	string, pattern : ARRAY 256 OF CHAR;
	enum : AosFS.Enumerator; 
	flags, fileflags : SET;
	count, total : LONGINT;
	time, date, size : LONGINT;
	name : ARRAY MaxNameLen OF CHAR;
	dt : Utilities.TDateTime;
	timer : AosKernel.Timer;
	parameters : ARRAY 32 OF CHAR;
BEGIN
	GetParameters(par, r, parameters);
	IF StringContains(parameters, FlagSize) THEN INCL(flags, AosFS.EnumSize); END;
	IF StringContains(parameters, FlagTime) THEN INCL(flags, AosFS.EnumTime); END;
	
	r.SkipWhitespace; r.String(pattern);
	IF (r.res # AosIO.Ok) OR ((r.res = AosIO.EOF) & (pattern = "")) THEN
		pattern := "";
	END;
	NEW(timer);
	AosOut.Char(FixedFont);		
	NEW(enum); enum.Open(pattern, flags);
	count := 0; total := 0;
	WHILE enum.GetEntry(name, fileflags, time, date, size) DO
		INC(count);
		AosOut.String(name); 

		IF AosFS.EnumSize IN flags THEN
			Align(name);  AosOut.Int(size, 10); AosOut.Char("B");
			INC(total, size)
		END;

		IF AosFS.EnumTime IN flags THEN
			IF AosFS.EnumSize IN flags THEN AosOut.String("    "); ELSE Align(name); END;
			dt := Utilities.OberonToDateTime(date, time);
			Utilities.FormatDateTime(FormatDateTime, dt, string);
			AosOut.String(string);
		END;
		AosOut.Ln;
		(* Otherwise we would send data too fast to the logger. Really ugly... *)
		timer.Sleep(10); 
	END;
	enum.Close;
	IF count > 1 THEN
		AosOut.Int(count, 0); AosOut.String(" files ");
		IF AosFS.EnumSize IN flags THEN
			AosOut.String("use "); WriteK((total+1023) DIV 1024);
		END
	END;
	AosOut.Char(ProportionalFont);
	AosOut.Ln; 
	RETURN NIL;
END Directory;

(** Copy files *)
PROCEDURE CopyFiles*(par : ANY) : ANY; (** [/oi] {source  => destination} ~ *)
VAR
	 r : AosIO.StringReader; 
	 source, destination : FileList;
	 overwrite, overwritten, error, ignoreErrors : BOOLEAN;
	 nofFiles, res, n : LONGINT;
	 parameters : ARRAY 32 OF CHAR;
BEGIN
	GetParameters(par, r, parameters);
	IF StringContains(parameters, FlagIgnoreErrors) THEN ignoreErrors := TRUE; ELSE ignoreErrors := FALSE; END;
	IF StringContains(parameters, FlagOverwrite) THEN overwrite := TRUE; ELSE overwrite := FALSE; END;
	nofFiles := GetFileLists(r, source, destination);
	IF nofFiles # Error THEN
		AosOut.String("Copying files..."); AosOut.Ln;
		n := 0;
		WHILE(source[n] # NIL) & (destination[n] # NIL) & (ignoreErrors OR ~error) DO
			AosOut.String("   Copy "); AosOut.String(source[n]^); AosOut.String(" => "); AosOut.String(destination[n]^); AosOut.String(" ... ");
			overwritten := overwrite;
			AosFS.CopyFile(source[n]^, destination[n]^, overwritten, res);
			IF res = AosFS.Ok THEN
				AosOut.String("done"); 
				IF overwritten THEN AosOut.String(" (overwritten)"); END;
				AosOut.Char("."); AosOut.Ln;
				INC(n);
			ELSE
				AosOut.String("failed "); ShowRes(res); AosOut.Ln;
				error := TRUE; 				
			END;	
		END;
	END;	
	IF nofFiles # Error THEN
		AosOut.Int(n, 0); AosOut.String(" of "); AosOut.Int(nofFiles, 0);  AosOut.String(" files copied."); AosOut.Ln;
	ELSE
		AosOut.String("No files copied."); AosOut.Ln;
	END;
	RETURN NIL;
END CopyFiles;

(** Delete files *)
PROCEDURE DeleteFiles*(par : ANY) : ANY; (** [/i] {file} ~ *)
VAR 
	r : AosIO.StringReader; 
	filelist : FileList;
	error, ignoreErrors : BOOLEAN;
	nofFiles, res, n : LONGINT;
	parameters : ARRAY 32 OF CHAR;
BEGIN
	GetParameters(par, r, parameters);
	IF StringContains(parameters, FlagIgnoreErrors) THEN ignoreErrors := TRUE; ELSE ignoreErrors := FALSE; END;
	nofFiles := GetFileList(r, filelist);
	IF (nofFiles > 0) THEN
		AosOut.String("Deleting files..."); AosOut.Ln;
		n := 0;
		WHILE(filelist[n] # NIL) & (ignoreErrors OR ~error) DO
			res := 0;
			AosOut.String("   Delete "); AosOut.String(filelist[n]^); AosOut.String(" ... ");
			AosFS.Delete(filelist[n]^, res);
			IF res = AosFS.Ok THEN
				AosOut.String("done."); AosOut.Ln;
				INC(n);
			ELSE
				AosOut.String("failed "); ShowRes(res); AosOut.Ln;
				error := TRUE;
			END;
		END;
		AosOut.Int(n, 0); AosOut.String(" of "); AosOut.Int(nofFiles, 0); AosOut.String(" files deleted."); AosOut.Ln;		
	ELSIF (nofFiles = 0) THEN
		AosOut.String("No files matching the mask found."); AosOut.Ln;
	ELSE
		AosOut.String("Syntax Error: No files deleted"); AosOut.Ln;
	END;
	RETURN NIL;
END DeleteFiles;

(** Rename files. *)
PROCEDURE RenameFiles*(par : ANY) : ANY; (** [/i] {source => destination} ~ *)
VAR 
	r : AosIO.StringReader; 
	source, target : FileList;
	error, ignoreErrors : BOOLEAN;
	nofFiles, res, n : LONGINT;
	parameters : ARRAY 32 OF CHAR;
BEGIN
	GetParameters(par, r, parameters);
	IF StringContains(parameters, FlagIgnoreErrors) THEN ignoreErrors := TRUE; ELSE ignoreErrors := FALSE; END;
	nofFiles := GetFileLists(r, source, target);
	IF nofFiles # Error THEN
		AosOut.String("Renaming files..."); AosOut.Ln;
		n := 0;
		WHILE(source[n] # NIL) & (target[n] # NIL) & (ignoreErrors OR ~error) DO
			res := 0;
			AosOut.String("   Rename "); AosOut.String(source[n]^); AosOut.String(" => "); AosOut.String(target[n]^); AosOut.String(" ... ");
			AosFS.Rename(source[n]^, target[n]^, res);
			IF res # AosFS.Ok THEN
				AosOut.String("failed "); ShowRes(res); AosOut.Ln;
				error := TRUE;
			ELSE
				AosOut.String("done."); AosOut.Ln;			
				INC(n);
			END;
		END;
	END;
	IF nofFiles # Error THEN 
		AosOut.Int(n, 0); AosOut.String(" of "); AosOut.Int(nofFiles, 0); AosOut.String(" files renamed."); AosOut.Ln;
	ELSE
		AosOut.String("No files renamed."); AosOut.Ln;
	END;
	RETURN NIL
END RenameFiles;

PROCEDURE ResizeFilelist(VAR filelist : FileList);
VAR temp : FileList; i : LONGINT;
BEGIN
	NEW(temp, 2 * LEN(filelist));
	FOR i := 0 TO LEN(filelist)-1 DO
		temp[i] := filelist[i];
	END;
	filelist := temp;
END ResizeFilelist;

(* Checks whether a file list entry contains mask characters and adds the corresponding files if it does *)
PROCEDURE InsertFiles(mask : ARRAY OF CHAR; VAR filelist : FileList; VAR index : LONGINT);
VAR 
	enum : AosFS.Enumerator;
	fileflags : SET;
	time, date, size : LONGINT;
	name : ARRAY MaxNameLen OF CHAR;
BEGIN
	NEW(enum); enum.Open(mask, {});
	WHILE enum.GetEntry(name, fileflags, time, date, size) DO
		filelist[index] := Utilities.NewString(name);
		IF index >= LEN(filelist) THEN ResizeFilelist(filelist); END;
		INC(index);
	END;
	enum.Close;
END InsertFiles;

(* Count the number of occurences of the character 'ch' in the string 'string'. Case-Sensitiv! *)
PROCEDURE CountCharacters(string : ARRAY OF CHAR; ch : CHAR) : LONGINT;
VAR count, i : LONGINT;
BEGIN
	count := 0;
	FOR i := 0 TO LEN(string)-1 DO
		IF string[i] = ch THEN INC(count); END;
	END;	
	RETURN count;
END CountCharacters;

(* Split full name into prefix, path, filename and file extension *)
PROCEDURE SplitFullName(fullname : ARRAY OF CHAR; VAR prefix, path, filename, extension : ARRAY OF CHAR);
VAR pathname, name : ARRAY 1024 OF CHAR;
BEGIN
	AosFS.SplitName(fullname, prefix, pathname);
	AosFS.SplitPath(pathname, path, name);
	AosFS.SplitExtension(name, filename, extension);
END SplitFullName;

PROCEDURE IsValidTargetMask(mask : ARRAY OF CHAR) : BOOLEAN;
VAR 
	prefix : ARRAY AosFS.PrefixLength OF CHAR; 
	filename, extension : ARRAY AosFS.NameLength OF CHAR;
	path : ARRAY 512 OF CHAR;
BEGIN
	SplitFullName(mask, prefix, path, filename, extension);
	
	IF (CountCharacters(mask, "?") > 0) THEN 
		AosOut.String("Syntax Error in "); AosOut.String(mask); AosOut.String(": '?' matching characters not implemented for target mask"); AosOut.Ln;
		RETURN FALSE;
	END;
	
	IF (CountCharacters(prefix, "*") # 0) OR (CountCharacters(path, "*") # 0) THEN
		AosOut.String("Syntax Error in "); AosOut.String(mask); AosOut.String(": Target prefix/path may not contain '*' characters"); AosOut.Ln;
		RETURN FALSE;
	END;
		
	RETURN TRUE;
END IsValidTargetMask;

PROCEDURE GetTargetName(sourceMask, targetMask, sourceName : ARRAY OF CHAR) : String;
VAR 
	targetName : ARRAY 1024 OF CHAR;
	srcPrefix, srcPath, srcFilename, srcExtension : ARRAY 512 OF CHAR;
	isExtension : BOOLEAN;
	i, j, index : LONGINT;
BEGIN
	SplitFullName(sourceName, srcPrefix, srcPath, srcFilename, srcExtension);
	index := 0;
	FOR i := 0 TO LEN(targetMask)-1 DO	
		IF targetMask[i] = "." THEN
			isExtension := TRUE;
			targetName[index] := targetMask[i];
			INC(index);
		ELSIF targetMask[i] = "*" THEN
			IF isExtension THEN
				j := 0; WHILE (j < LEN(srcExtension)) & (srcExtension[j] # 0X) DO targetName[index] := srcExtension[j]; INC(index); INC(j); END;
			ELSE
				j := 0; WHILE (j < LEN(srcFilename)) & (srcFilename[j] # 0X) DO targetName[index] := srcFilename[j]; INC(index); INC(j); END;
			END;
		ELSE
			targetName[index] := targetMask[i];
			INC(index);
		END;
	END;
	IF index < LEN(targetName) THEN targetName[index] := 0X; END;
	RETURN Utilities.NewString(targetName);
END GetTargetName;

PROCEDURE InsertFilesAndFixDestination(sourceMask, targetMask : ARRAY OF CHAR; VAR source, target : FileList; VAR index : LONGINT) : BOOLEAN;
VAR 
	enum : AosFS.Enumerator;
	fileflags : SET;
	time, date, size : LONGINT;
	name : ARRAY MaxNameLen OF CHAR;
BEGIN
	IF ~IsValidTargetMask(targetMask) THEN RETURN FALSE; END;
	NEW(enum); enum.Open(sourceMask, {});
	WHILE enum.GetEntry(name, fileflags, time, date, size) DO
		IF index >= LEN(source) THEN ResizeFilelist(source); ResizeFilelist(target); END;
		source[index] := Utilities.NewString(name);
		target[index] := GetTargetName(sourceMask, targetMask, name);
		INC(index);
	END;
	enum.Close;
	RETURN TRUE;
END InsertFilesAndFixDestination;

PROCEDURE IsMask(string : ARRAY OF CHAR) : BOOLEAN;
BEGIN
	RETURN StringContains(string, "*") OR StringContains(string, "?");
END IsMask;

PROCEDURE GetFileList(r : AosIO.Reader; VAR filelist : FileList) : LONGINT;
VAR filename : ARRAY MaxNameLen OF CHAR; done, error : BOOLEAN; count : LONGINT;
BEGIN
	NEW(filelist, InitialFilelistSize);
	WHILE ~done & ~error DO
		r.SkipWhitespace; r.String(filename);
		IF (r.res = AosIO.Ok) OR ((r.res = AosIO.EOF) & (filename # "")) THEN 
			IF IsMask(filename) THEN
				IF ~unsafeMode THEN 
					ShowUnsafeMessage; RETURN 0;
				END;
				InsertFiles(filename, filelist, count);
			ELSE
				IF count >= LEN(filelist) THEN ResizeFilelist(filelist); END;
				filelist[count] := Utilities.NewString(filename);
				INC(count);
			END;
		ELSIF r.res = AosIO.EOF THEN
			done := TRUE;
		ELSE
			AosOut.Enter; AosOut.String("Command parsing error (res: "); AosOut.Int(r.res, 0); AosOut.String(")"); AosOut.Exit;
			error := TRUE;
		END;
	END;
	IF error THEN count := Error; END;
	RETURN count;
END GetFileList;

PROCEDURE GetFileLists(r : AosIO.Reader; VAR source, target : FileList) : LONGINT;
VAR 
	filename : ARRAY MaxNameLen OF CHAR; done, error : BOOLEAN; count : LONGINT;
	sourceString, targetString : String;
BEGIN
	NEW(source, InitialFilelistSize); NEW(target, InitialFilelistSize);
	WHILE ~done & ~error DO
		r.SkipWhitespace; r.String(filename);
		IF r.res = AosIO.Ok THEN 
			sourceString := Utilities.NewString(filename);
			r.SkipWhitespace;
			r.String(filename);
			IF Utilities.Match(filename, "=>") THEN
				r.SkipWhitespace;
				r.String(filename);
				IF (r.res = AosIO.Ok) OR ((r.res = AosIO.EOF) & (filename # ""))  THEN
					targetString := Utilities.NewString(filename);
					IF IsMask(sourceString^) OR IsMask(targetString^) THEN
						IF ~unsafeMode THEN ShowUnsafeMessage; RETURN 0; END;
						IF ~InsertFilesAndFixDestination(sourceString^, targetString^, source, target, count) THEN END;
					ELSE
						IF count >= LEN(source) THEN ResizeFilelist(source); ResizeFilelist(target); END;
						source[count] := sourceString;
						target[count] := targetString;
						INC(count);
					END;
				ELSE
					AosOut.Enter; AosOut.String("Command parsing error (res: "); AosOut.Int(r.res, 0); AosOut.String(")");	AosOut.Exit;
					error := TRUE;
				END;
			ELSE
				AosOut.Enter; AosOut.String("Command parsing error: Exspected => token after "); AosOut.String(source[count]^); AosOut.Exit;
				error := TRUE;
			END;
		ELSIF r.res = AosIO.EOF THEN
			done := TRUE;
		ELSE 
			AosOut.Enter; AosOut.String("Command parsing error (res: "); AosOut.Int(r.res, 0); AosOut.String(")"); AosOut.Exit;
			error := TRUE;
		END;
	END;
	IF error THEN count := Error; END;
	RETURN count;
END GetFileLists;

PROCEDURE GetParameters(par : ANY; VAR r : AosIO.StringReader; VAR parameters : ARRAY OF CHAR);
VAR ch : CHAR; i : LONGINT;
BEGIN
	FOR i := 0 TO LEN(parameters)-1 DO parameters[i] := 0X; END;
	AosCommands.PosPar(par, r);
	r.SkipWhitespace;
	ch := r.Peek();
	IF ch = "/" THEN
		r.String(parameters);
		r.SkipWhitespace;
	END;
END GetParameters;

PROCEDURE Safe*(par : ANY) : ANY;
BEGIN
	unsafeMode := FALSE;
	AosOut.String("AosFSTools: SAFE mode."); AosOut.Ln;
	RETURN NIL
END Safe;

PROCEDURE Unsafe*(par : ANY) : ANY;
BEGIN
	unsafeMode := TRUE;
	AosOut.String("AosFSTools: UNSAFE mode now. BE CAREFUL!"); AosOut.Ln;
	RETURN NIL
END Unsafe;

PROCEDURE ShowUnsafeMessage;
BEGIN
	AosOut.String("AosFSTools: Pattern matching is disabled in SAFE mode. Press AosFSTools.Unsafe ~ to enable pattern matching."); AosOut.Ln;
END ShowUnsafeMessage;

PROCEDURE ShowRes(res : LONGINT);
BEGIN
	AosOut.String("(");
	CASE res OF
		AosFS.VolumeReadOnly: AosOut.String("Target volume is read-only"); 
		|AosFS.FsNotFound: AosOut.String("File system not found");
		|AosFS.FileAlreadyExists: AosOut.String("File already exists");
		|AosFS.BadFileName: AosOut.String("Bad file name"); 
		|AosFS.FileNotFound: AosOut.String("File not found");
	ELSE
		AosOut.String("res: "); AosOut.Int(res, 0); 
	END;
	AosOut.String(")");
END ShowRes;

END AosFSTools.

S.Free AosFSTools ~

AosFSTools.DeleteFiles X:*.Bak ~