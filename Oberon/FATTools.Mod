(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE FATTools;	(* AUTHOR "be"; PURPOSE "Oberon user-interface to the extended FAT fs interface" *)

IMPORT AosFS, AosFATVolumes, AosFATFiles, Utilities, Texts, Oberon;

CONST
	Ok = AosFATFiles.Ok;

TYPE
	Path = RECORD
		prefix: AosFS.Prefix;
		fullname: AosFATFiles.Filename;
		directories: DirList;
	END;
	
	DirList = POINTER TO RECORD
		name: AosFATFiles.Filename;
		next: DirList
	END;
	
PROCEDURE OpenScanner(VAR S: Texts.Scanner);
VAR beg, end, time: LONGINT; T: Texts.Text; BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN
		Oberon.GetSelection(T, beg, end, time);
		IF (time # -1) THEN
			Texts.OpenScanner(S, T, beg); Texts.Scan(S)
		END
	END
END OpenScanner;

PROCEDURE GetString(VAR S: Texts.Scanner; VAR p: ARRAY OF CHAR): BOOLEAN;
BEGIN
	IF (S.class IN {Texts.Name, Texts.String}) THEN COPY(S.s, p); Texts.Scan(S); RETURN TRUE
	ELSE p[0] := 0X; RETURN FALSE
	END
END GetString;

PROCEDURE GetInteger(VAR S: Texts.Scanner; VAR v: LONGINT): BOOLEAN;
BEGIN
	IF (S.class = Texts.Int) THEN v := S.i; Texts.Scan(S); RETURN TRUE
	ELSE v := 0; RETURN FALSE
	END
END GetInteger;

PROCEDURE GetOption(VAR S: Texts.Scanner; VAR optionChar: CHAR): BOOLEAN;
BEGIN
	IF (S.class = Texts.Char) & (S.c = "\") THEN
		optionChar := S.nextCh; Texts.Scan(S); RETURN TRUE
	ELSE optionChar := 0X; RETURN FALSE
	END
END GetOption;

PROCEDURE Split(p: ARRAY OF CHAR; VAR path: Path): BOOLEAN;
VAR len, pos, i, k: LONGINT; directory, last: DirList;
BEGIN
	len := LEN(p);
	pos := 0;
	WHILE (pos < len) & (pos < SIZE(AosFS.Prefix)-1) & (p[pos] # ":") & (p[pos] # 0X) DO
		path.prefix[pos] := p[pos]; INC(pos)
	END;
	IF (pos < len) & (p[pos] = ":") THEN
		INC(pos);
		NEW(directory); path.directories := directory; last := NIL;
		
		IF (pos < len) & (p[pos] = "/") THEN 
			(*directory.name := "/"; last := directory; NEW(directory); last.next := directory;*)
			INC(pos)
		END;
		
		WHILE (pos < len) & (p[pos] # 0X) DO
			i := 0;
			WHILE (pos < len) & (p[pos] # "/") & (p[pos] # 0X) & (i < AosFATFiles.MaxFilenameLen-1) DO
				directory.name[i] := p[pos]; INC(pos); INC(i)
			END;
			directory.name[i] := 0X;
			IF (pos < len) & (p[pos] = "/") THEN INC(pos) END;
			last := directory; NEW(directory); last.next := directory
		END;
		
		IF (directory.name = "") THEN 
			IF (last = NIL) THEN path.directories := NIL
			ELSE last.next := NIL 
			END
		END;
		
		directory := path.directories;
		i := 0;
		WHILE (directory # NIL) DO
			IF (directory.name = "") THEN RETURN FALSE END;
			IF (path.fullname # "") THEN path.fullname[i] := "/"; INC(i) END;
			k := 0;
			WHILE (directory.name[k] # 0X) & (i < AosFATFiles.MaxFilenameLen-1) DO 
				path.fullname[i] := directory.name[k]; 
				INC(i); INC(k) 
			END;
			path.fullname[i] := 0X;
			directory  := directory.next;
		END;
		RETURN TRUE	
	ELSE RETURN FALSE	(* prefix not found/invalid *)
	END
END Split;

PROCEDURE GetErrorMsg(res: LONGINT; VAR s: ARRAY OF CHAR);
BEGIN
	CASE res OF
	| AosFATFiles.ErrReadOnly: COPY("read-only file system", s)
	| AosFATFiles.ErrInvalidParams: COPY("invalid parameters", s)
	| AosFATFiles.ErrIOError: COPY("I/O error", s)
	| AosFATFiles.ErrFileReadOnly: COPY("file is read-only", s)
	| AosFATFiles.ErrParentNotFound: COPY("parent directory not found", s)
	| AosFATFiles.ErrInvalidFilename: COPY("invalid filename", s)
	| AosFATFiles.ErrTooManySimilarFiles: COPY("too many similar filenames", s)
	| AosFATFiles.ErrRootDirFull: COPY("root directory overflow", s)
	| AosFATFiles.ErrFileNotFound: COPY("file not found", s)
	| AosFATFiles.ErrFileExists: COPY("file exists", s)
	| AosFATFiles.ErrHasOpenFiles: COPY("has open files. Try System.Collect first", s)
	| AosFATFiles.ErrNoRelativePaths: COPY("relative path names not supported", s)
	| AosFATFiles.ErrDirectoryProtection: COPY("directory is write-protected", s)
	| AosFATFiles.ErrDirectoryNotEmpty: COPY("directory not empty", s)
	| AosFATFiles.ErrNotADirectory: COPY("not a directory", s)
	| AosFATFiles.ErrDirectoryOpen: COPY("directory is still open", s)
	ELSE Utilities.IntToStr(res, s); Utilities.Concat("unknown error: ", s, s)
	END
END GetErrorMsg;

PROCEDURE SetRootDirectory*; (** path (including prefix, e.g. "FAT:/Program Files") *)
VAR W: Texts.Writer; S: Texts.Scanner; path: Path; fs: AosFS.FileSystem; p: ARRAY 1024 OF CHAR;
BEGIN
	Texts.OpenWriter(W); OpenScanner(S);
	Texts.WriteString(W, "Setting new root: "); Texts.Append(Oberon.Log, W.buf);
	IF GetString(S, p) THEN
		Texts.WriteString(W, p); Texts.WriteString(W, ": "); Texts.Append(Oberon.Log, W.buf);
		IF Split(p, path) THEN
			fs := AosFS.This(path.prefix);
			IF (fs IS AosFATFiles.FileSystem) THEN
				IF fs(AosFATFiles.FileSystem).SetRootDirectory(path.fullname) THEN
					Texts.WriteString(W, "ok")
				ELSE
					Texts.WriteString(W, "failed")
				END
			ELSE
				Texts.WriteString(W, path.prefix); Texts.WriteString(W, ": not a FAT file system")
			END
		ELSE
			Texts.WriteString(W, "invalid parameter"); Texts.WriteLn(W)
		END		
	ELSE
		Texts.WriteString(W, "invalid syntax")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END SetRootDirectory;

PROCEDURE CreateDirectory*; (** path (including prefix, e.g. "FAT:/New Folder/A/B/C") *)
VAR p: ARRAY 1024 OF CHAR; W: Texts.Writer; S: Texts.Scanner;
	res: LONGINT; msg: ARRAY 256 OF CHAR;
BEGIN
	Texts.OpenWriter(W);
	Texts.WriteString(W, "Creating directory: "); Texts.Append(Oberon.Log, W.buf);
	OpenScanner(S);
	IF GetString(S, p) THEN
		Texts.WriteString(W, p); Texts.WriteString(W, ": "); Texts.Append(Oberon.Log, W.buf);
		AosFS.CreateDirectory(p, res);
		IF (res = 0) THEN Texts.WriteString(W, "created")
		ELSE
			IF (res = -1) THEN COPY("directories not supported by file system", msg)
			ELSE GetErrorMsg(res, msg);
			END;
			Texts.WriteString(W, msg)
		END
	ELSE
		Texts.WriteString(W, "invalid syntax"); Texts.WriteLn(W)
	END;
	Texts.Append(Oberon.Log, W.buf)
END CreateDirectory;

PROCEDURE RemoveDirectory*; (** path ["\F"]. Path includes prefix, e.g. "FAT:/A/B/C". Use "\F" option to force deletion of non-empty directories. *)
VAR p: ARRAY 1024 OF CHAR; W: Texts.Writer; S: Texts.Scanner;
	res: LONGINT; msg: ARRAY 256 OF CHAR; force: BOOLEAN; o: CHAR;
BEGIN
	Texts.OpenWriter(W);
	Texts.WriteString(W, "Deleting directory: "); Texts.Append(Oberon.Log, W.buf);
	OpenScanner(S);
	IF GetString(S, p) THEN
		force := GetOption(S, o) & (CAP(o) = "F");
		Texts.WriteString(W, p); Texts.WriteString(W, ": "); Texts.Append(Oberon.Log, W.buf);
		AosFS.RemoveDirectory(p, force, res);
		IF (res = 0) THEN Texts.WriteString(W, "deleted")
		ELSE
			IF (res = -1) THEN COPY("directories not supported by file system", msg)
			ELSE GetErrorMsg(res, msg);
			END;
			Texts.WriteString(W, msg)
		END
	ELSE
		Texts.WriteString(W, "invalid syntax"); Texts.WriteLn(W)
	END;
	Texts.Append(Oberon.Log, W.buf)
END RemoveDirectory;

PROCEDURE SetCache*; (** prefix cacheSize *)
VAR W: Texts.Writer; S: Texts.Scanner; path: Path; fs: AosFS.FileSystem; p: ARRAY 1024 OF CHAR;
	cacheSize: LONGINT; writeback: BOOLEAN;
BEGIN
	Texts.OpenWriter(W); OpenScanner(S);
	IF GetString(S, p) & GetInteger(S, cacheSize) THEN
		IF (cacheSize < 0) THEN writeback := TRUE; cacheSize := -cacheSize
		ELSE writeback := FALSE
		END;
		
		Utilities.TrimRight(p, ":");
		fs := AosFS.This(p);
		Texts.WriteString(W, path.prefix);
		IF (fs # NIL) & (fs IS AosFATFiles.FileSystem) THEN
			fs.vol(AosFATVolumes.Volume).SetCache(AosFATVolumes.Data, cacheSize, writeback);
			
			IF (cacheSize > 0) THEN
				Texts.WriteString(W, ": "); Texts.WriteInt(W, cacheSize, 0); Texts.WriteString(W, " buffers à ");
				Texts.WriteInt(W, fs.vol(AosFATVolumes.Volume).clusterSize, 0); Texts.WriteString(W, " bytes")
			ELSE
				Texts.WriteString(W, ": cache disabled")
			END
		ELSIF (fs # NIL) THEN
			Texts.WriteString(W, " ("); Texts.WriteString(W, fs.vol.name); 
			Texts.WriteString(W, "): not a FAT file system")
		ELSE
			Texts.WriteString(W, ": not found")
		END
	ELSE
		Texts.WriteString(W, "invalid syntax")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END SetCache;

PROCEDURE Statistics*;
VAR W: Texts.Writer; S: Texts.Scanner; path: Path; fs: AosFS.FileSystem; vol: AosFATVolumes.Volume; p: ARRAY 1024 OF CHAR;
BEGIN
	Texts.OpenWriter(W); OpenScanner(S);
	IF GetString(S, p) THEN
		Utilities.TrimRight(p, ":");
		fs := AosFS.This(p);
		IF (fs # NIL) & (fs IS AosFATFiles.FileSystem) THEN
			vol := fs.vol(AosFATVolumes.Volume);
			Texts.WriteString(W, "Statistics for "); Texts.WriteString(W, p); Texts.WriteLn(W);
			Texts.WriteString(W, "  # ReadSector: "); Texts.WriteInt(W, vol.NreadSector, 0); Texts.WriteLn(W);
			Texts.WriteString(W, "  # WriteSector: "); Texts.WriteInt(W, vol.NwriteSector, 0); Texts.WriteLn(W);
			Texts.WriteString(W, "  # ReadCluster: "); Texts.WriteInt(W, vol.NreadCluster, 0); Texts.WriteLn(W);
			Texts.WriteString(W, "  # WriteCluster: "); Texts.WriteInt(W, vol.NwriteCluster, 0); Texts.WriteLn(W);
			Texts.WriteString(W, "  # AllocCluster: "); Texts.WriteInt(W, vol.NallocCluster, 0); Texts.WriteLn(W);
			Texts.WriteString(W, "  # ReadFAT: "); Texts.WriteInt(W, vol.NreadFAT, 0); Texts.WriteLn(W);
			Texts.WriteString(W, "  # WriteFAT: "); Texts.WriteInt(W, vol.NwriteFAT, 0); Texts.WriteLn(W);
		ELSIF (fs # NIL) THEN
			Texts.WriteString(W, path.prefix); Texts.WriteString(W, " ("); Texts.WriteString(W, fs.vol.name); 
			Texts.WriteString(W, "): not a FAT file system")
		ELSE
			Texts.WriteString(W, p); Texts.WriteString(W, ": not found")
		END
	ELSE
		Texts.WriteString(W, "invalid syntax")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Statistics;

(*
PROCEDURE Template;
VAR W: Texts.Writer; S: Texts.Scanner; path: Path; fs: AosFS.FileSystem; p: ARRAY 1024 OF CHAR;
BEGIN
	Texts.OpenWriter(W); OpenScanner(S);
	IF GetString(S, p) THEN
	ELSE
		Texts.WriteString(W, "invalid syntax")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Template;
*)

PROCEDURE QuickFormat*; (** prefix [label] *)
VAR p: ARRAY 128 OF CHAR; path: Path; fs: AosFS.FileSystem;
	W: Texts.Writer; S: Texts.Scanner; res: LONGINT; msg: ARRAY 256 OF CHAR;
BEGIN
	Texts.OpenWriter(W);
	OpenScanner(S);
	IF GetString(S, p) & Split(p, path) THEN
		IF ~GetString(S, p) OR (p = "") THEN COPY("NO NAME", p) END;
	
		fs := AosFS.This(path.prefix);
		IF (fs # NIL) & (fs IS AosFATFiles.FileSystem) THEN
			Texts.WriteString(W, "Formatting "); Texts.WriteString(W, path.prefix); 
			Texts.WriteString(W, " ("); Texts.WriteString(W, fs.vol.name); Texts.WriteString(W, "), label '");
			Texts.WriteString(W, p); Texts.WriteString(W, "'..."); Texts.Append(Oberon.Log, W.buf);
			fs(AosFATFiles.FileSystem).QuickFormat(p, res);
			IF (res = Ok) THEN Texts.WriteString(W, "ok")
			ELSE
				GetErrorMsg(res, msg);
				Texts.WriteString(W, msg)
			END
		ELSIF (fs # NIL) THEN
			Texts.WriteString(W, path.prefix); Texts.WriteString(W, " ("); Texts.WriteString(W, fs.vol.name); 
			Texts.WriteString(W, "): not a FAT file system")
		ELSIF (path.prefix # "") THEN			
			Texts.WriteString(W, path.prefix); Texts.WriteString(W, ": not found")
		ELSE
			Texts.WriteString(W, "invalid syntax (no prefix)")
		END
	ELSE
		Texts.WriteString(W, "invalid syntax")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END QuickFormat;

END FATTools.
 

System.Free FATTools ~
FATTools.CreateDirectory "FAT:/Ahuga/A/B/C/D/E/F/G" ~

FATTools.SetRootDirectory "FAT:/Ahuga/" ~

FATTools.QuickFormat "FAT:" "BIMBO" ~

FATTools.SetCache "FAT" -4096 ~

FATTools.Statistics "FAT" ~

System.CopyFiles AOS:Pr6Fonts.zip => RAM:Pr6Fonts.zip ~

Configuration.DoCommands
System.Time
AosProfiler.Profile System.CopyFiles RAM:Pr6Fonts.zip => FAT:Pr6Fonts.zip ~
System.Time
~
Configuration.DoCommands
System.Time
AosProfiler.Profile System.CopyFiles FAT:AosSys.zip => RAM:AosSys.zip ~
System.Time
~

Configuration.DoCommands
System.Time
AosProf.Start
System.CopyFiles AOS:BE.New.II.AosFATFiles.Mod => FAT:BE.New.II.AosFATFiles.Mod ~
AosProf.Stop
System.Time
AosProf.ShowProcs
~

AosProfiler.Profile System.CopyFiles FAT:Test => RAM:Test ~
AosProfiler.Profile OFSFATDebug.SpeedTest FAT:Oberon.Dsk 1024 ~