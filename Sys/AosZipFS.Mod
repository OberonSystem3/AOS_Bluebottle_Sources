MODULE AosZipFS; (** AUTHOR "ejz"; PURPOSE "mount a zipped file as a file-system"; *)
	IMPORT AosModules, AosIO, AosFS, AosUnzip, Utilities, AosOut;

	TYPE
		FileSystem = OBJECT (AosFS.FileSystem)
			VAR zip: AosUnzip.ZipFile;

			PROCEDURE &Init(zip: AosUnzip.ZipFile);
			BEGIN
				SELF.zip := zip
			END Init;

			PROCEDURE Old0(name: ARRAY OF CHAR): AosFS.File;
				VAR E: AosUnzip.Entry; key, res: LONGINT; F: File; F0: AosFS.File; W: AosFS.Writer;
			BEGIN {EXCLUSIVE}
				key := 0;
				E := zip.GetFirst();
				WHILE E # NIL DO
					INC(key);
					IF E.name^ = name THEN
						F0 := localFS.New0("");
						AosFS.OpenWriter(W, F0, 0);
						zip.Extract(E, W, res);
						W.Update();
						NEW(F);
						F.fs := SELF; F.key := key; F.E := E; F.F := F0;
						RETURN F
					END;
					E := zip.GetNext(E)
				END;
				RETURN NIL
			END Old0;

			PROCEDURE Enumerate0(mask: ARRAY OF CHAR; flags: SET; enum: AosFS.Enumerator);
				VAR E: AosUnzip.Entry; name: AosFS.FileName; d, t: LONGINT;
			BEGIN {EXCLUSIVE}
				E := zip.GetFirst();
				WHILE E # NIL DO
					IF Match(mask, E.name^) THEN
						AosFS.JoinName(prefix, E.name^, name);
						IF AosFS.EnumTime IN flags THEN
							Utilities.DateTimeToOberon(E.td, d, t)
						END;
						enum.PutEntry(name, {}, t, d, E.size)
					END;
					E := zip.GetNext(E)
				END
			END Enumerate0;

			PROCEDURE FileKey(name: ARRAY OF CHAR): LONGINT;
				VAR E: AosUnzip.Entry; key: LONGINT;
			BEGIN {EXCLUSIVE}
				key := 0;
				E := zip.GetFirst();
				WHILE E # NIL DO
					INC(key);
					IF E.name^ = name THEN RETURN key END;
					E := zip.GetNext(E)
				END;
				RETURN 0
			END FileKey;

			PROCEDURE Finalize();
			BEGIN {EXCLUSIVE}
				Finalize^()
			END Finalize;

		END FileSystem;

		File = OBJECT (AosFS.File)
			VAR F: AosFS.File; E: AosUnzip.Entry;

			PROCEDURE Set(VAR r: AosFS.Rider; pos: LONGINT);
			BEGIN
				F.Set(r, pos); r.file := SELF
			END Set;

			PROCEDURE Pos(VAR r: AosFS.Rider): LONGINT;
			BEGIN
				RETURN F.Pos(r)
			END Pos;

			PROCEDURE Read(VAR r: AosFS.Rider; VAR x: CHAR);
			BEGIN
				F.Read(r, x)
			END Read;

			PROCEDURE ReadBytes(VAR r: AosFS.Rider; VAR x: ARRAY OF CHAR; ofs, len: LONGINT);
			BEGIN
				F.ReadBytes(r, x, ofs, len)
			END ReadBytes;

			PROCEDURE Length(): LONGINT;
			BEGIN
				RETURN F.Length()
			END Length;

			PROCEDURE GetDate(VAR t, d: LONGINT);
			BEGIN
				Utilities.DateTimeToOberon(E.td, d, t)
			END GetDate;

			PROCEDURE GetName(VAR name: ARRAY OF CHAR);
			BEGIN
				AosFS.JoinName(fs.prefix, E.name^, name)
			END GetName;

			PROCEDURE Update();
			BEGIN
				F.Update END
			Update;

		END File;

	VAR
		localFS: AosFS.FileSystem;

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

	PROCEDURE NewFS*(par: PTR): PTR;
		VAR
			p: AosFS.Parameters; R: AosIO.StringReader; name: AosFS.FileName;
			F: AosFS.File; zip: AosUnzip.ZipFile; fs: FileSystem; res: LONGINT;
	BEGIN
		p := par(AosFS.Parameters);
		IF (AosFS.This(p.prefix) = NIL) THEN
			NEW(R, LEN(p.str)); R.Set(p.str^);
			R.SkipWhitespace(); R.String(name);
			F := AosFS.Old(name);
			IF F # NIL THEN
				NEW(zip, F, res);
				IF res = AosIO.Ok THEN
					NEW(fs, zip);
					AosFS.Add(fs, p.prefix)
				ELSE
					AosOut.Enter();
					AosOut.String("AosZipFS: "); AosOut.String(name); AosOut.String(" not a valid zip file");
					AosOut.Exit()
				END
			ELSE
				AosOut.Enter();
				AosOut.String("AosZipFS: "); AosOut.String(name); AosOut.String(" not found");
				AosOut.Exit()
			END
		ELSE
			AosOut.Enter();
			AosOut.String("AosZipFS: "); AosOut.String(p.prefix); AosOut.String(" already in use");
			AosOut.Exit()
		END;
		RETURN NIL
	END NewFS;

	PROCEDURE Finalization();
		VAR ft: AosFS.FileSystemTable; i: LONGINT;
	BEGIN {}
		IF AosModules.shutdown = AosModules.None THEN
			AosFS.GetList(ft);
			IF ft # NIL THEN
				FOR i := 0 TO LEN(ft^)-1 DO
					IF ft[i] IS FileSystem THEN AosFS.Remove(ft[i]) END
				END
			END
		END
	END Finalization;

	PROCEDURE Init();
		VAR fs: AosFS.FileSystemTable; i: LONGINT;
	BEGIN
		i := 0;
		AosFS.GetList(fs);
		WHILE (i < LEN(fs)) & ((fs[i].vol = NIL) OR (AosFS.ReadOnly IN fs[i].vol.flags)) DO
			INC(i)	(* find a writable file system *)
		END;
		IF (i < LEN(fs)) THEN localFS := fs[i] END;
		AosModules.InstallTermHandler(Finalization)
	END Init;

BEGIN
	Init()
END AosZipFS.

System.Free AosZipFS ~

OFSTools.Mount Test AosZipFS ARM.Backup.zip ~
OFSTools.Unmount Test

System.Directory Test:*\d
