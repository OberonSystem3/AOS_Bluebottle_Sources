(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE FATDocs; (** AUTHOR "be"; PURPOSE "FAT file system user interface" *)	

IMPORT Objects, Fonts, Display, Strings, Texts, Display3, Oberon, Gadgets, Attributes, 
	BasicGadgets, TextGadgets, Documents, TextDocs, Desktops, 
	AosFS, AosFATFiles, Utilities;

(** 
	The FATDocs-modul implements a simple explorer for FAT file systems. The following line should be added to the DocumentServices section:
			explore = FATDocs.NewDoc
			
	A mounted FAT file system with prefix FAT can be browsed by executing explore:FAT
*)

CONST
	MeasureTime = FALSE;
	
	SizeWidth = 10;
	FixedFont = "Courier10.Scn.Fnt";
	Menu = "FATDocs.CopyFrom[FAT->]FATDocs.CopyTo[->FAT]FATDocs.RenameFile[Ren]FATDocs.DeleteFiles[Delete]FATDocs.CreateDirectory[MkDir]FATDocs.RemoveDirectories[RmDir]";

TYPE
	EnumProc* = PROCEDURE (entry: ARRAY OF CHAR);
	Frame = POINTER TO FrameDesc;
	FrameDesc = RECORD (TextGadgets.FrameDesc) (* check 'CopyFrame' when modifying this record ! *)
		fs: AosFATFiles.FileSystem;
		(*currentDir: AosFATFiles.Directory;*)
		currentDir: AosFATFiles.Filename;
		rmdirName: AosFATFiles.Filename;
	END;

	Parameter = POINTER TO RECORD END;
	CopyFilePar = POINTER TO RECORD(Parameter)
		srcFS, dstFS: AosFS.FileSystem;
		srcDirectory, dstDirectory: AosFATFiles.Filename;
	END;
	DeletePar = POINTER TO RECORD(Parameter)
		F: Frame;
		fs: AosFS.FileSystem;
		directory: AosFATFiles.Filename
	END;
	ScanCallback = PROCEDURE(name: ARRAY OF CHAR; par: Parameter): BOOLEAN;
	
VAR
	W, dirW: Texts.Writer;
	
PROCEDURE WriteLn(s: ARRAY OF CHAR);
BEGIN
	Texts.WriteString(W, s); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END WriteLn;

(* GetSelFrame - get most recent selection and remove it *)
PROCEDURE GetSelFrame(VAR F: Display.Frame; VAR T: Texts.Text; VAR beg, end: LONGINT);
VAR M: Oberon.SelectMsg;
BEGIN
	M.id := Oberon.get; M.F := NIL; M.time := -1; M.text := NIL; M.sel := NIL; Display.Broadcast(M);
	IF (M.time # -1) & (M.text # NIL) & (M.sel # NIL) THEN
		F := M.sel; T := M.text; beg := M.beg; end := M.end;
		(* remove selection (M.sel, M.text already set) *)
		M.F := F; M.id := Oberon.reset; Display.Broadcast(M)
	ELSE F := NIL
	END
END GetSelFrame;

(* Copy - copies 'src' to 'dst' *)
PROCEDURE Copy(src, dst: ARRAY OF CHAR): BOOLEAN;
CONST BufLen = 8192;
VAR s, d: AosFS.File; rS, rD: AosFS.Rider; i, size, ts: LONGINT; buf: ARRAY BufLen OF CHAR;
	res: BOOLEAN;
BEGIN
	res := FALSE;
	Texts.WriteString(W, "Copying "); Texts.WriteString(W, dst); Texts.WriteString(W, " ..."); Texts.Append(Oberon.Log, W.buf);
	IF MeasureTime THEN ts := Oberon.Time() END;
	s := AosFS.Old(src); 
	d := AosFS.New(dst); 
	IF (s # NIL) & (d # NIL) THEN
		s.Set(rS, 0); d.Set(rD, 0);
		i := 0; size := s.Length();
		WHILE (i < size DIV BufLen) & (rD.res = 0) DO
			s.ReadBytes(rS, buf, 0, BufLen); d.WriteBytes(rD, buf, 0, BufLen); INC(i)
		END;
		IF (rD.res = 0) THEN
			s.ReadBytes(rS, buf, 0, size MOD BufLen); d.WriteBytes(rD, buf, 0, size MOD BufLen);
		END;
		
		IF (rD.res = 0) THEN
			AosFS.Register(d);
			Texts.WriteString(W, "done");
			IF MeasureTime THEN
				Texts.WriteString(W, ": "); Texts.WriteInt(W, size, 0); Texts.WriteString(W, " bytes copied");
				Texts.WriteString(W, ": "); Texts.WriteInt(W, Oberon.Time()-ts,0); Texts.WriteString(W, " ticks")
			END;
			res := TRUE
		ELSE
			Texts.WriteString(W, "can't write to file")
		END				
	ELSE
		IF (s = NIL) THEN Texts.WriteString(W, "file not found")
		ELSE Texts.WriteString(W, "can't create file")
		END
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	RETURN res
END Copy;

(* CopyFile - callback for CopyFrom *)
PROCEDURE CopyFile(name: ARRAY OF CHAR; par: Parameter): BOOLEAN;
VAR src, dst: AosFATFiles.Filename; 
BEGIN
	WITH par: CopyFilePar DO
		GetFullName(par.srcFS.prefix, par.srcDirectory, name, src);
		GetFullName(par.dstFS.prefix, par.dstDirectory, name, dst);
		RETURN Copy(src, dst)
	END
END CopyFile;

(** CopyFrom - used by interactive interface to copy the selected files to another file system *)
PROCEDURE CopyFrom*;
VAR F: Frame; F1, F2, dstF: Display.Frame; 
	T1, T2: Texts.Text; Src, Dst: Texts.Scanner; beg1, beg2, end1, end2, end: LONGINT; 
	par: CopyFilePar; prefix: AosFS.Prefix; path: AosFATFiles.Filename;
BEGIN
	IF Desktops.IsInMenu(Gadgets.context) THEN
		GetContext(F);
		IF (F # NIL) THEN
			GetSelFrame(F1, T1, beg1, end1);
			GetSelFrame(F2, T2, beg2, end2);
			
			IF (F1 # NIL) & (F2 # NIL) THEN
				IF (F1 = F) & (F2 # F) THEN
					Texts.OpenScanner(Src, T1, beg1); end := end1;
					Texts.OpenScanner(Dst, T2, beg2); dstF := F2;
				ELSIF (F1 # F) & (F2 = F) THEN
					Texts.OpenScanner(Src, T2, beg2); end := end2;
					Texts.OpenScanner(Dst, T1, beg1); dstF := F1
				ELSE
					WriteLn("Invalid selection");
					RETURN
				END;
				
				NEW(par); par.srcFS := F.fs; COPY(F.currentDir, par.srcDirectory);
				
				Texts.Scan(Dst);
				IF (Dst.class IN {Texts.Name, Texts.String}) THEN
					AosFS.SplitName(Dst.s, prefix, path);
					par.dstFS := AosFS.This(prefix);
					IF (par.dstFS = NIL) THEN 
						WriteLn("Destination file system not found");
						RETURN 
					END;
					
					IF (par.dstFS IS AosFATFiles.FileSystem) & (dstF IS Frame) & (path = "") THEN	(* also a FAT file system *)
						IF (dstF(Frame).fs = F.fs) & (dstF(Frame).currentDir = F.currentDir) THEN
							WriteLn("Source and target directory are identical");
							RETURN
						ELSE
							COPY(dstF(Frame).currentDir, par.dstDirectory)
						END
					ELSE
						COPY(path, par.dstDirectory)
					END
				END;
					
				ScanNames(Src, end, CopyFile, par);
				IF (dstF IS Frame) THEN EnumerateDirectory(dstF(Frame)) END
			ELSE WriteLn("Invalid selection")
			END
		END
	END
END CopyFrom;

(** CopyTo - used by interactive interface to copy the selected files into the active directory *)
PROCEDURE CopyTo*;
VAR F: Frame; srcF: Display.Frame; T: Texts.Text; S: Texts.Scanner; beg, end: LONGINT; 
	dst, name: AosFATFiles.Filename; prefix: AosFS.Prefix; ok: BOOLEAN;
BEGIN
	IF Desktops.IsInMenu(Gadgets.context) THEN
		GetContext(F);
		IF (F # NIL) THEN
			GetSelFrame(srcF, T, beg, end);
			
			IF (srcF # NIL) THEN
				Texts.OpenScanner(S, T, beg);
				
				IF (srcF IS Frame) THEN
					WriteLn("Can't copy from FAT explorer. Use 'FAT->' instead");
					RETURN
				END;

				Texts.Scan(S); ok := TRUE;
				WHILE ok & (S.class IN {Texts.Name, Texts.String}) & (Texts.Pos(S) <= end) DO
					AosFS.SplitName(S.s, prefix, name);
					GetFullName(F.fs.prefix, F.currentDir, name, dst);
					ok := Copy(S.s, dst);
					Texts.Scan(S)
				END;
				EnumerateDirectory(F)
			END
		END
	END
END CopyTo;

(** RenameFile - used by interactive interface to rename the marked file *)
PROCEDURE RenameFile*;
VAR F: Frame; F1, F2, dstF: Display.Frame; 
	T1, T2: Texts.Text; Src, Dst: Texts.Scanner; beg1, beg2, end1, end2, end, res: LONGINT; 
	path, name, newname: AosFATFiles.Filename;
BEGIN
	IF Desktops.IsInMenu(Gadgets.context) THEN
		GetContext(F);
		IF (F # NIL) THEN
			GetSelFrame(F1, T1, beg1, end1);
			GetSelFrame(F2, T2, beg2, end2);
			
			IF (F1 # NIL) & (F2 # NIL) THEN
				IF (F1 = F) & (F2 # F) THEN
					Texts.OpenScanner(Src, T1, beg1); end := end1;
					Texts.OpenScanner(Dst, T2, beg2); dstF := F2;
				ELSIF (F1 # F) & (F2 = F) THEN
					Texts.OpenScanner(Src, T2, beg2); end := end2;
					Texts.OpenScanner(Dst, T1, beg1); dstF := F1
				ELSE
					WriteLn("Invalid selection");
					RETURN
				END;
				
				(* Src: file that should be renamed; Dst: new filename *)
				REPEAT
					Texts.Scan(Src)
				UNTIL ((Src.class = Texts.Object) & (Src.obj IS TextGadgets.Control)) OR (Texts.Pos(Src) > end);
				
				IF (Src.class = Texts.Object) & (Src.obj IS TextGadgets.Control) THEN
					Attributes.GetString(Src.obj, "File", name);
					Unquote(name, name);
					AosFS.JoinName(F.fs.prefix, F.currentDir, path);
					
					Texts.Scan(Dst);
					IF (Dst.class IN {Texts.String, Texts.Name}) THEN
						Texts.WriteString(W, "Renaming "); Texts.WriteString(W, name); Texts.WriteString(W, " to ");
						Texts.WriteString(W, Dst.s); Texts.WriteString(W, " ..."); Texts.Append(Oberon.Log, W.buf);
						AosFS.JoinPath(path, name, name);
						AosFS.JoinPath(path, Dst.s, newname);
						AosFS.Rename(name, newname, res);
						IF (res = 0) THEN Texts.WriteString(W, "done"); EnumerateDirectory(F)
						ELSIF (res = 2905) THEN Texts.WriteString(W, "read-only volume")
						ELSIF (res = AosFATFiles.ErrInvalidFilename) THEN Texts.WriteString(W, "invalid filename")
						ELSIF (res = AosFATFiles.ErrFileNotFound) THEN Texts.WriteString(W, "file not found")
						ELSIF (res = AosFATFiles.ErrDirectoryProtection) THEN Texts.WriteString(W, "delete directory with same name first")
						ELSE Texts.WriteString(W, "failed: "); Texts.WriteInt(W, res, 0)
						END;
						Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
					ELSE
						WriteLn("Invalid new name")
					END						
				ELSE
					WriteLn("No file selected")
				END
			ELSE
				WriteLn("Select the file to rename and the new filename")
			END			
		END
	END
END RenameFile;

(* DeleteFile - deletes the file 'name' in the current directory of F. *)
PROCEDURE DeleteFile(name: ARRAY OF CHAR; par: Parameter): BOOLEAN;
VAR res: LONGINT;
BEGIN
	WITH par: DeletePar DO
		IF (name # "") THEN
			GetFullName(par.fs.prefix, par.directory, name, name);
			Texts.WriteString(W, "Deleting "); Texts.WriteString(W, name); Texts.WriteString(W, "..."); 
			Texts.Append(Oberon.Log, W.buf);
			AosFS.Delete(name, res);
			IF (res = 0) THEN Texts.WriteString(W, "ok")
			ELSE
				Texts.WriteString(W, "failed: ");
				IF (res = AosFATFiles.ErrFileReadOnly) THEN Texts.WriteString(W, "file is read-only")
				ELSIF (res = AosFATFiles.ErrDirectoryProtection) THEN Texts.WriteString(W, "it's a directory")
				ELSE Texts.WriteString(W, "unknown error: "); Texts.WriteInt(W, res, 0)
				END
			END;
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)			
		END
	END;
	RETURN TRUE
END DeleteFile;

(** DeleteFiles - used by interactive interface to delete the marked files *)
PROCEDURE DeleteFiles*;
VAR F: Frame; S: Texts.Scanner; T: Texts.Text; beg, end, time: LONGINT; par: DeletePar;
BEGIN
	IF Desktops.IsInMenu(Gadgets.context) THEN
		GetContext(F);
		IF (F # NIL) THEN
			IF ~(AosFS.ReadOnly IN F.fs.vol.flags) THEN
				T := NIL; time := -1;
				Oberon.GetSelection(T, beg, end, time);
				IF (time >= 0) & (T # NIL) THEN
					Texts.OpenScanner(S, T, beg);
					NEW(par); par.fs := F.fs; COPY(F.currentDir, par.directory);
					ScanNames(S, end, DeleteFile, par);
					EnumerateDirectory(F)
				END
			ELSE
				Texts.WriteString(W, "read-only file system"); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			END
		END
	END
END DeleteFiles;

(** Create a new directory. *)
PROCEDURE CreateDirectory*;
VAR F: Frame; T: Texts.Text; S: Texts.Scanner; 
	beg, end, res, time: LONGINT; name: AosFATFiles.Filename;
BEGIN
	GetContext(F);
	IF (F # NIL) THEN
		T := NIL; time := -1;
		Oberon.GetSelection(T, beg, end, time);
		IF (time >= 0) & (T # NIL) THEN
			Texts.OpenScanner(S, T, beg); Texts.Scan(S);
			IF (S.class IN {Texts.Name, Texts.String}) THEN
				Texts.WriteString(W, "Creating directory '"); Texts.WriteString(W, S.s); 
				Texts.WriteString(W, "'..."); Texts.Append(Oberon.Log, W.buf);
				AosFS.JoinName(F.fs.prefix, F.currentDir, name);
				Utilities.Concat(name, S.s, name);
				AosFS.CreateDirectory(name, res);
				IF (res = 0)THEN
					Texts.WriteString(W, "ok");
					EnumerateDirectory(F)
				ELSIF (res = AosFATFiles.ErrReadOnly) THEN Texts.WriteString(W, "read-only file system")
				ELSIF (res = AosFATFiles.ErrFileExists) THEN Texts.WriteString(W, "name already taken")
				ELSIF (res = AosFATFiles.ErrInvalidFilename) THEN Texts.WriteString(W, "invalid name")
				ELSIF (res = -1) THEN Texts.WriteString(W, "not supported")
				ELSE Texts.WriteString(W, "unknown error: "); Texts.WriteInt(W, res, 0)
				END;
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END
END CreateDirectory;

(* RemoveDirectory - removes the directory 'name' in the current directory of F. *)
PROCEDURE RemoveDirectory(name: ARRAY OF CHAR; par: Parameter): BOOLEAN;
VAR res: LONGINT;
BEGIN
	WITH par: DeletePar DO
		IF (name # "") THEN
			GetFullName(par.fs.prefix, par.directory, name, name);
			Texts.WriteString(W, "Deleting "); Texts.WriteString(W, name); Texts.WriteString(W, "..."); 
			Texts.Append(Oberon.Log, W.buf);
			AosFS.RemoveDirectory(name, (par.F.rmdirName = name), res); COPY(name, par.F.rmdirName);
			IF (res = 0) THEN Texts.WriteString(W, "ok")
			ELSE
				IF (res = AosFATFiles.ErrDirectoryNotEmpty) THEN Texts.WriteString(W, "not empty. Try again to force deletion.")
				ELSIF (res = AosFATFiles.ErrHasOpenFiles) THEN Texts.WriteString(W, "contains open files. Try System.Collect first")
				ELSIF (res = AosFATFiles.ErrDirectoryOpen) THEN Texts.WriteString(W, "directory is open. Try System.Collect first")
				ELSE Texts.WriteString(W, "unknown error "); Texts.WriteInt(W, res, 0)
				END
			END;
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)			
		END
	END;
	RETURN TRUE
END RemoveDirectory;

(** Remove existing directories. *)
PROCEDURE RemoveDirectories*;
VAR F: Frame; S: Texts.Scanner; T: Texts.Text; beg, end, time: LONGINT; par: DeletePar;
BEGIN
	IF Desktops.IsInMenu(Gadgets.context) THEN
		GetContext(F);
		IF (F # NIL) THEN
			IF ~(AosFS.ReadOnly IN F.fs.vol.flags) THEN
				T := NIL; time := -1;
				Oberon.GetSelection(T, beg, end, time);
				IF (time >= 0) & (T # NIL) THEN
					Texts.OpenScanner(S, T, beg);
					NEW(par); par.F := F; par.fs := F.fs; COPY(F.currentDir, par.directory);
					ScanNames(S, end, RemoveDirectory, par);
					EnumerateDirectory(F)
				END
			ELSE
				Texts.WriteString(W, "read-only file system"); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			END
		END			
	END
END RemoveDirectories;

PROCEDURE *DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN
					M.class := Objects.String; M.s := "FATDocs.NewDoc"; M.res := 0
				ELSE
					TextDocs.DocHandler(D, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF M.id = Objects.get THEN
					IF (M.name = "DeskMenu") OR (M.name = "SystemMenu") OR (M.name = "UserMenu") THEN
						M.obj := Desktops.NewMenu(Menu);
						M.res := 0
					ELSE
						TextDocs.DocHandler(D, M)
					END
				ELSE
					TextDocs.DocHandler(D, M)
				END
			END
		ELSE
			TextDocs.DocHandler(D, M)
		END
	END
END DocHandler;

(* Parsing of an "fat url". *)
PROCEDURE SplitFATAdr(VAR url, prefix, path: ARRAY OF CHAR): BOOLEAN;
VAR i,k: LONGINT;
BEGIN
	prefix[0] := 0X; COPY(AosFS.PathDelimiter, path);
	
	(* skip 'fat://' *)
	i := 0;
	WHILE (url[i] # 0X) & (url[i] # ':') DO INC(i) END;
	IF (url[i] = 0X) THEN RETURN FALSE END;	(* invalid url *)
	INC(i);
	WHILE (url[i] # 0X) & (url[i] = '/') DO INC(i) END;
	
	(* read prefix *)
	k := 0;
	WHILE (url[i] # 0X) & (url[i] # AosFS.PathDelimiter) DO
		prefix[k] := url[i];
		INC(k); INC(i)
	END;
	prefix[k] := 0X;
	
	(* read optional path *)
	IF (url[i] = AosFS.PathDelimiter) THEN 
		INC(i);
		k := 0;
		WHILE (url[i] # 0X) DO
			path[k] := url[i];
			INC(k); INC(i)
		END;
		path[k] := 0X
	END;
	RETURN TRUE
END SplitFATAdr;

PROCEDURE DirectoryUp*;
VAR F: Frame; dummy: AosFS.FileName;
BEGIN
	GetContext(F);
	IF (F # NIL) THEN
		Utilities.TrimRight(F.currentDir, AosFS.PathDelimiter);
		AosFS.SplitPath(F.currentDir, F.currentDir, dummy);
		AosFS.ForceTrailingDelimiter(F.currentDir);
		(*IF (F.currentDir = "") THEN COPY(AosFS.PathDelimiter, F.currentDir) END;*)
		EnumerateDirectory(F)
	END;
END DirectoryUp;

PROCEDURE DirectoryRefresh*;
VAR F: Frame;
BEGIN
	GetContext(F);
	IF (F # NIL) THEN
		EnumerateDirectory(F)
	END
END DirectoryRefresh;

PROCEDURE Quote(str: ARRAY OF CHAR; VAR result: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
	result[0] := '"'; i := 0;
	WHILE (str[i] # 0X) & (i < LEN(result)-3) DO result[i+1] := str[i]; INC(i) END;
	result[i+1] := '"';
	result[i+2] := 0X
END Quote;

PROCEDURE Unquote(str: ARRAY OF CHAR; VAR result: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
	IF (str[0] = '"') THEN
		i := 1;
		WHILE (str[i] # '"') & (str[i] # 0X) DO result[i-1] := str[i]; INC(i) END;
		result[i-1] := 0X
	ELSE result[0] := 0X
	END
END Unquote;

PROCEDURE ListEntry(VAR name: ARRAY OF CHAR; flags: SET; time, date, size: LONGINT);
VAR str: ARRAY 32 OF CHAR; i: LONGINT; c: CHAR;
BEGIN
	Texts.SetColor(dirW, SHORT(Display3.textC));
		(* write date & time *)
	Utilities.FormatDateTime("yyyy.mm.dd hh:nn:ss ", Utilities.OberonToDateTime(date, time), str);
	Texts.WriteString(dirW, str);
		(* write size *)
	IF ~(AosFS.Directory IN flags) THEN
		FOR i := 1 TO SizeWidth DO
			IF (size > 0) THEN c :=  CHR(ORD("0") + size MOD 10); size := size DIV 10
			ELSE c := " "
			END;
			str[SizeWidth-i] := c
		END;
		str[SizeWidth] := 0X;
		Texts.WriteString(dirW, str)
	ELSE
		FOR i := 1 TO SizeWidth-1 DO Texts.Write(dirW, " ") END;
		Texts.Write(dirW, "-")
	END;
	Texts.Write(dirW, " ");
		(* write name *)
	Texts.SetColor(dirW, SHORT(Display3.blue));
	Texts.WriteString(dirW, name);
	IF (AosFS.Directory IN flags) THEN Texts.Write(dirW, AosFS.PathDelimiter) END;
	
	TextGadgets.NewControl();
	Attributes.SetString(Objects.NewObj, "Cmd", "FATDocs.LinkHandler #File");
	Quote(name, name);
	Attributes.SetString(Objects.NewObj, "File",  name);
	Texts.WriteObj(dirW, Objects.NewObj);
	
	Texts.SetColor(dirW, SHORT(Display3.textC));
	Texts.WriteLn(dirW)
END ListEntry;

PROCEDURE OpenDoc(name: ARRAY OF CHAR);
VAR d: Documents.Document;
BEGIN
	d := Documents.Open(name);
	IF d # NIL THEN Desktops.ShowDoc(d) END
END OpenDoc;

PROCEDURE GetFullName(prefix, path, name: ARRAY OF CHAR; VAR result: ARRAY OF CHAR);
BEGIN
	result[0] := 0X;
	Strings.Append(result, path);
	Strings.Append(result, name);
	AosFS.JoinName(prefix, result, result)
END GetFullName;

PROCEDURE ScanNames(VAR S: Texts.Scanner; end: LONGINT; callback: ScanCallback; par: Parameter);
VAR name: AosFATFiles.Filename; continue: BOOLEAN;
BEGIN
	REPEAT
		REPEAT
			Texts.Scan(S)
		UNTIL ((S.class = Texts.Object) & (S.obj IS TextGadgets.Control)) OR (Texts.Pos(S) > end);
		
		IF (S.class = Texts.Object) & (S.obj IS TextGadgets.Control) & (Texts.Pos(S) <= end) THEN
			Attributes.GetString(S.obj, "File", name);
			Unquote(name, name);
			continue := callback(name, par)
		END
	UNTIL  (Texts.Pos(S) > end) OR ~continue
END ScanNames;

PROCEDURE LinkHandler*;
VAR S: Attributes.Scanner; F: Frame; fn: AosFATFiles.Filename; f: AosFS.File; prefix: AosFS.Prefix;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF (S.class IN {Attributes.Name, Attributes.String}) THEN
		GetContext(F);
		IF (F # NIL) THEN
			GetFullName(F.fs.prefix, F.currentDir, S.s, fn);
			f := AosFS.Old(fn);
			IF (f # NIL) & (f IS AosFATFiles.File) THEN
				IF (f IS AosFATFiles.Directory) THEN
					AosFS.SplitName(fn, prefix, F.currentDir);
					Utilities.Concat(F.currentDir, AosFS.PathDelimiter, F.currentDir);
					EnumerateDirectory(F)
				ELSE
					OpenDoc(fn)
				END
			END
		END
	END
END LinkHandler;

PROCEDURE HorzRule(): Objects.Object;
VAR obj: Objects.Object;
BEGIN
	obj := Gadgets.CreateObject("BasicFigures.NewRect3D");
	Attributes.SetBool(obj, "Filled", TRUE);
	Attributes.SetInt(obj, "Color", Display3.textbackC);
	Gadgets.ModifySize(obj(Display.Frame), Display.Width, 4);
	RETURN obj
END HorzRule;

PROCEDURE EnumerateDirectory(F: Frame);
VAR f: Objects.Object; pos: LONGINT; e: AosFS.Enumerator;
	name, dummy: AosFATFiles.Filename; flags: SET; time, date, size: LONGINT;
BEGIN
	Texts.Delete(F.text, 0, F.text.len);
	Texts.WriteString(dirW, F.fs.prefix); Texts.Write(dirW, ":");
	f := Gadgets.CreateObject("TextFields.NewTextField");
	Attributes.SetString(f, "Value", F.currentDir);	(* directory *)
	Attributes.SetString(f, "Cmd", "FATDocs.ChangeDocDirectory '#Value '");
	WITH f: Display.Frame DO
		f.W := 5*f.W
	END;
	Texts.WriteObj(dirW, f); Texts.Write(dirW, " ");
	(* 'up' button *)
	BasicGadgets.NewButton; f := Objects.NewObj;
	COPY("Up", f(BasicGadgets.Button).caption);
	Attributes.SetString(f, "Cmd", "FATDocs.DirectoryUp");
	Texts.WriteObj(dirW, f); Texts.Write(dirW, " ");
	(* 'refresh' button *)
	BasicGadgets.NewButton; f := Objects.NewObj;
	COPY("Refresh", f(BasicGadgets.Button).caption);
	Attributes.SetString(f, "Cmd", "FATDocs.DirectoryRefresh");
	Texts.WriteObj(dirW, f); Texts.Write(dirW, " ");
	
	Texts.WriteLn(dirW); 
	(* horizontal line *)
	Texts.WriteObj(dirW, HorzRule()); 
	Texts.WriteLn(dirW);
	Texts.Append(F.text, dirW.buf);
	
	pos := F.text.len-1;
	AosFS.JoinName(F.fs.prefix, F.currentDir, name);
	NEW(e); e.Open(name, {AosFS.EnumSize, AosFS.EnumTime});
	WHILE e.GetEntry(name, flags, time, date, size) DO
		AosFS.SplitPath(name, dummy, name);
		ListEntry(name, flags, time, date, size)
	END;
	e.Close;
	Texts.Append(F.text, dirW.buf)
END EnumerateDirectory;

PROCEDURE GetContext(VAR F: Frame);
VAR D: Documents.Document;
BEGIN
	D := Desktops.CurDoc(Gadgets.context);
	IF (D.dsc # NIL) & (D.dsc IS Frame) & (D.dsc(Frame).fs # NIL) THEN
		F := D.dsc(Frame)
	ELSE
		F := NIL
	END
END GetContext;

(** Used by the interactive interface to change to directory pointed at *)
PROCEDURE ChangeDocDirectory*;
VAR F: Frame; S: Attributes.Scanner; dir: AosFS.File; fn: AosFS.FileName;
BEGIN
	GetContext(F);
	IF F # NIL THEN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			COPY(S.s, fn); Utilities.Trim(fn, AosFS.PathDelimiter);
			dir := F.fs.Old0(fn);
			IF (dir # NIL) & (dir IS AosFATFiles.Directory) THEN
				COPY(fn, F.currentDir); AosFS.ForceTrailingDelimiter(F.currentDir);
				EnumerateDirectory(F)
			ELSE
				Texts.WriteString(W, "Directory '"); Texts.WriteString(W, S.s); 
				Texts.WriteString(W, "' not found"); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			END
		END
	END
END ChangeDocDirectory;

(** Extension of TextGadgets used by the interactive FTPDocs. *)
PROCEDURE CopyFrame(VAR C: Objects.CopyMsg; from, to: Frame);
BEGIN
	TextGadgets.CopyFrame(C, from, to);
	to.fs := from.fs;
	to.currentDir := from.currentDir;
	COPY(from.currentDir, to.currentDir)
END CopyFrame;

PROCEDURE *FrameHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F1: Frame;
BEGIN
	WITH F: Frame DO
		IF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN
					M.obj := F.dlink
				ELSE
					NEW(F1);
					F.stamp := M.stamp;
					F.dlink := F1;
					CopyFrame(M, F, F1);
					M.obj := F1
				END
			END
		ELSE
			TextGadgets.FrameHandler(F, M)
		END
	END
END FrameHandler;

PROCEDURE *LoadDoc(D: Documents.Document);
VAR F: Frame; T: Texts.Text; fs: AosFS.FileSystem; f: AosFS.File;
	prefix: AosFS.Prefix; path: AosFATFiles.Filename;
BEGIN
	IF SplitFATAdr(D.name, prefix, path) THEN
		NEW(F);
		fs := AosFS.This(prefix);
		IF (fs = NIL) OR ~(fs IS AosFATFiles.FileSystem) THEN RETURN
		ELSE F.fs := fs(AosFATFiles.FileSystem)
		END;
		f := F.fs.Old0(path);
		
		IF (f = NIL) OR ~(f IS AosFATFiles.Directory) THEN COPY(AosFS.PathDelimiter, F.currentDir)
		ELSE 
			COPY(path, F.currentDir);
			AosFS.ForceTrailingDelimiter(F.currentDir)
		END;
		
		TextDocs.InitDoc(D);
		NEW(T); Texts.Open(T, "");
		TextGadgets.Init(F, T, FALSE);
		EnumerateDirectory(F);

		D.W := Display.Width*5 DIV 8; D.H := Display.Height*7 DIV 8;
		D.dsc := F; D.handle := DocHandler;
		F.handle := FrameHandler
	ELSE
		D.dsc := NIL
	END
END LoadDoc;

PROCEDURE NewDoc*;
	VAR D: Documents.Document;
BEGIN
	NEW(D);
	D.Load := LoadDoc; D.Store := NIL;
	D.handle := DocHandler;
	Objects.NewObj := D
END NewDoc;

BEGIN
	Texts.OpenWriter(W);
	Texts.OpenWriter(dirW);
	Texts.SetFont(dirW, Fonts.This(FixedFont))
END FATDocs.

System.Free FATDocs FATTool AosFATFiles AosFATVolumes ~
System.Free FATDocs  ~
OFSTools.Mount FAT FatFS IDE0#6 ~ (FAT 12)
FATTool.QuickFormat "FAT:" "AOSFORMAT" ~
explore:FAT
Test
Aos