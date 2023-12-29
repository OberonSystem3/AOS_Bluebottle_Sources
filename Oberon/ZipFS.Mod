MODULE ZipFS;	(** prk  **)

(*
	ZipFS - Mount a zipped file as a file-system, allow direct access of the compressed files
*)

IMPORT
		AosOut,
		AosModules, AosFS, AosIO,
		Zip := AosZip;

CONST
	BufSize = 4*1024;

	Trace = FALSE;
	
	
TYPE
	File = OBJECT (AosFS.File)
		(* this  is a wrapper for the data cached info in a temporary file *)
		VAR
			e: Zip.Entry;
			f: AosFS.File;
			
		PROCEDURE Set*(VAR r: AosFS.Rider; pos: LONGINT);
		BEGIN f.Set(r, pos); r.file := SELF END Set;

		PROCEDURE Pos*(VAR r: AosFS.Rider): LONGINT;
		BEGIN RETURN f.Pos(r) END Pos;

		PROCEDURE Read*(VAR r: AosFS.Rider; VAR x: CHAR);
		BEGIN f.Read(r, x) END Read;

		PROCEDURE ReadBytes*(VAR r: AosFS.Rider; VAR x: ARRAY OF CHAR; ofs, len: LONGINT);
		BEGIN f.ReadBytes(r, x, ofs, len) END ReadBytes;

		PROCEDURE Write*(VAR r: AosFS.Rider; x: CHAR);	(* read-only *)
		BEGIN HALT(99) END Write;

		PROCEDURE WriteBytes*(VAR r: AosFS.Rider; VAR x: ARRAY OF CHAR; ofs, len: LONGINT);	(* read-only *)
		BEGIN HALT(99) END WriteBytes;

		PROCEDURE Length*(): LONGINT;
		BEGIN RETURN f.Length() END Length;
		
		PROCEDURE GetDate*(VAR t, d: LONGINT);
		BEGIN f.GetDate(t, d) END GetDate;

		PROCEDURE SetDate*(t, d: LONGINT);	(* read-only *)
		BEGIN HALT(99) END SetDate;

		PROCEDURE GetName*(VAR name: ARRAY OF CHAR);
		BEGIN AosFS.JoinName(fs.prefix, e.name, name)
		END GetName;

		PROCEDURE Register0*(VAR res: LONGINT);	(* read-only *)
		BEGIN HALT(99) END Register0;
		
		PROCEDURE Update*();
		BEGIN f.Update END Update;
	END File;
	
	
	FileSystem = OBJECT (AosFS.FileSystem)
		VAR
			archive: Zip.Archive;
			
		PROCEDURE Old0*(name: ARRAY OF CHAR): AosFS.File;
			VAR e: Zip.Entry; c: LONGINT; f: File;
				len, len0, read: LONGINT; w: AosFS.Writer; r: Zip.Reader; buf: ARRAY BufSize OF CHAR;
		BEGIN
			IF Trace THEN AosOut.String("Old0 "); AosOut.String(name) END;
			FindEntry(archive, name, e, c);
			IF e # NIL THEN
				NEW(f);
				(* recursive locks are not allowed. Use a local filesystem that must be found before the Old0 call instead of AosFS.New("") *)
				f.f := localFS.New0("");
				len := e.uncompSize;
				r := Zip.OpenReader(archive, e);
				AosFS.OpenWriter(w, f.f, 0);
				WHILE len > 0 DO
					IF len > BufSize THEN len0 := BufSize ELSE len0 := len END;
					Zip.ReadBytes(r, buf, 0, len0, read); ASSERT(len0 = read);
					w.Bytes(buf, 0, len0);
					DEC(len, len0)
				END;
				w.Update;
				f.e := e;
				f.key := c;
				f.fs := SELF;
				IF Trace THEN AosOut.Int(e.uncompSize, 6); AosOut.Int(f.Length(), 6) END;
			END;
			IF Trace THEN AosOut.Ln END;
			RETURN f;
		END Old0;
		
		PROCEDURE Enumerate0*(mask: ARRAY OF CHAR; flags: SET; enum: AosFS.Enumerator);
			VAR e: Zip.Entry; name: ARRAY 256 OF CHAR;
		BEGIN
			IF Trace THEN AosOut.String(">Enumerate0 "); AosOut.Ln END;
			e := Zip.FirstEntry(archive);
			WHILE e # NIL DO
				IF Match(mask, e.name) THEN
					AosFS.JoinName(prefix, e.name, name);
					enum.PutEntry(name, {}, e.time, e.date, e.uncompSize)
				END;
				e := Zip.NextEntry(e)
			END;
			IF Trace THEN AosOut.String("<Enumerate0 "); AosOut.Ln END;
		END Enumerate0;
		
		PROCEDURE FileKey*(name: ARRAY OF CHAR): LONGINT;
			VAR e: Zip.Entry; c: LONGINT;
		BEGIN
			FindEntry(archive, name, e, c); RETURN c
		END FileKey;
		
		PROCEDURE Finalize*;
		BEGIN {EXCLUSIVE}
			IF Trace THEN AosOut.String("Finalize"); AosOut.Ln END;
			Finalize^
		END Finalize;
	END FileSystem;

VAR
	localFS: AosFS.FileSystem;	(* temporary files are allocated on this FS *)
	

	(* Match - check if pattern matches file name; copied from AosDiskFS.Match and MatchPrefix *)

	PROCEDURE Match(pat, name: ARRAY OF CHAR): BOOLEAN;
	VAR pos, i0, i1, j0, j1: LONGINT; f: BOOLEAN;
	BEGIN
		f := TRUE;
		LOOP
			IF pat[pos] = 0X THEN
				pos := -1; EXIT
			ELSIF pat[pos] = "*" THEN
				IF pat[pos+1] = 0X THEN pos := -1 END;
				EXIT
			ELSIF pat[pos] # name[pos] THEN
				f := FALSE; EXIT
			END;
			INC(pos)
		END;
		IF pos # -1 THEN
			i0 := pos; j0 := pos;
			LOOP
				IF pat[i0] = "*" THEN
					INC(i0);
					IF pat[i0] = 0X THEN EXIT END
				ELSE
					IF name[j0] # 0X THEN f := FALSE END;
					EXIT
				END;
				f := FALSE;
				LOOP
					IF name[j0] = 0X THEN EXIT END;
					i1 := i0; j1 := j0;
					LOOP
						IF (pat[i1] = 0X) OR (pat[i1] = "*") THEN f := TRUE; EXIT END;
						IF pat[i1] # name[j1] THEN EXIT END;
						INC(i1); INC(j1)
					END;
					IF f THEN j0 := j1; i0 := i1; EXIT END;
					INC(j0)
				END;
				IF ~f THEN EXIT END
			END
		END;
		RETURN f & (name[0] # 0X)
	END Match;

	(* FindEntry - Find entry in zip archive and return the entry number starting from 1 *)
	
	PROCEDURE FindEntry(a: Zip.Archive;  VAR name: ARRAY OF CHAR; VAR e: Zip.Entry;  VAR c: LONGINT);
	BEGIN
		c := 1;
		e := Zip.FirstEntry(a);
		WHILE (e # NIL) & (e.name # name) DO
			INC(c);
			e := Zip.NextEntry(e)
		END;
		IF e = NIL THEN c := 0 END;
	END FindEntry;
	
	(** NewFS - Create a new filesystem based on a zipped file *)

	PROCEDURE NewFS*(par: PTR): PTR;
		VAR str: ARRAY 256 OF CHAR; a: Zip.Archive; i, j, res: LONGINT; fs: FileSystem; p: AosFS.Parameters;
	BEGIN
		IF localFS # NIL THEN
			p := par(AosFS.Parameters);
			AosOut.String("-> "); AosOut.String(p.str^); AosOut.Ln;
			i := 0; j := 0;
			WHILE p.str[i] = " " DO INC(i) END;
			WHILE (p.str[i] # 0X) & (p.str[i] # " ") DO
				str[j] := p.str[i]; INC(i); INC(j)
			END;
			str[j] := 0X;
			a := Zip.OpenArchive(str, res);
			IF a # NIL THEN
				NEW(fs);
				fs.archive := a;
				COPY(str, fs.desc);
				AosFS.Add(fs, p.prefix);
			END
		END;
		RETURN NIL
	END NewFS;

	(* Clean up when module unloaded. *)
	
	PROCEDURE Cleanup*;
		VAR ft: AosFS.FileSystemTable; i: LONGINT;
	BEGIN
		IF AosModules.shutdown = AosModules.None THEN
			AosFS.GetList(ft);
			IF ft # NIL THEN
				FOR i := 0 TO LEN(ft^)-1 DO
					IF ft[i] IS FileSystem THEN AosFS.Remove(ft[i]) END
				END
			END
		END
	END Cleanup;

	PROCEDURE Init;
		VAR fs: AosFS.FileSystemTable; i: LONGINT;
	BEGIN
		i := 0;
		AosFS.GetList(fs);
		WHILE (i < LEN(fs)) & ((fs[i].vol = NIL) OR (AosFS.ReadOnly IN fs[i].vol.flags)) DO
			INC(i)	(* find a writable file system *)
		END;
		IF (i < LEN(fs)) THEN localFS := fs[i] END
	END Init;

BEGIN
	Init;
	AosModules.InstallTermHandler(Cleanup)
END ZipFS.

OFSTools.Mount Classpath ZipFS glibj.zip ~
OFSTools.Mount Mauve ZipFS mauve.zip ~
OFSTools.Unmount ^
System.Free ZipFS ~

System.Watch
System.Collect
Partitions.Show
System.Directory * ~
System.Directory Mauve:* ~
System.Directory Mauve:gnu/testlet/T* ~
System.Directory Mauve:*\d ~

(**

Description:
	Mount a zipped file as a file-system, allow direct read-only access of the compressed files

Installation: add to AosFS.Alias in Oberon.Text
		ZipFS = { NIL ZipFS.NewFS }

Use:
	OFSTools.Mount prefix ZipFS zipfile ~

Log:
	29:08.01	prk	cleanup handler added
	22.08.01	prk	ported to Aos 21.08.01
	21.08.01	prk	seach for writeable local fs improved
	21.08.01	prk	file name and fs description fixed
	20.08.01	prk	First Version

ToDo:
	* improve Zip, base Writer on AosIO to better integrate into file system (will remove trap when reloading oberon)
	* Allow writing of files
	* Map rider to a writer, don't use temporary files

Limitations:
	* one real file-system is needed for the extraction of the archive entries to a temporary file
	* files are read-only

*)