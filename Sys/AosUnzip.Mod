MODULE AosUnzip; (** AUTHOR "ejz"; PURPOSE "Aos unzip program"; *)
	IMPORT AosIO, AosInflate, CRC, AosFS, Utilities, AosOut, AosCommands;

	CONST
		EndOfCentralDirSig = 006054B50H;
		CentralFileHeadSig = 002014B50H;
		LocalFileHeadSig = 004034B50H;

	TYPE
		Entry* = POINTER TO RECORD
			method, pos: LONGINT;
			crc*, csize*, size*: LONGINT;
			td*: Utilities.TDateTime;
			name*: Utilities.String;
			next: Entry
		END;

		SizeReader = OBJECT
			VAR input: AosIO.Reader; max: LONGINT;

			PROCEDURE Receive(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
			BEGIN
				IF min > max THEN min := max END;
				input.Bytes(buf, ofs, min, len);
				DEC(max, len); res := input.res;
				IF (max = 0) & (res = AosIO.Ok) THEN
					res := AosIO.EOF
				END
			END Receive;

			PROCEDURE &Init(input: AosIO.Reader; size: LONGINT);
			BEGIN
				SELF.input := input; SELF.max := size
			END Init;

		END SizeReader;

		ZipFile* = OBJECT
			VAR
				F: AosFS.File;
				root: Entry; entries: LONGINT;

			PROCEDURE FindEntry*(name: ARRAY OF CHAR): Entry;
				VAR e: Entry; i: LONGINT;
			BEGIN
				e := root; i := 0;
				WHILE (e # NIL) & (e.name^ # name) DO
					e := e.next
				END;
				RETURN e
			END FindEntry;

			PROCEDURE GetFirst*(): Entry;
			BEGIN
				RETURN root
			END GetFirst;

			PROCEDURE GetNext*(e: Entry): Entry;
			BEGIN
				RETURN e.next
			END GetNext;

			PROCEDURE NoOfEntries*(): LONGINT;
			BEGIN
				RETURN entries
			END NoOfEntries;

			PROCEDURE OpenReceiver*(VAR R: AosIO.Receiver; entry: Entry; VAR res: LONGINT);
				VAR fR: AosFS.Reader; sig: LONGINT; e: Entry; I: AosInflate.Reader; S: SizeReader;
			BEGIN
				R := NIL; res := AosIO.FormatError;
				AosFS.OpenReader(fR, F, entry.pos); fR.RawLInt(sig);
				IF sig # LocalFileHeadSig THEN RETURN END;
				NEW(e); ReadEntry(fR, e, TRUE);
				IF e.crc = entry.crc THEN
					IF e.method = 8 THEN (* Deflate *)
						NEW(I, fR); R := I.Receive; res := AosIO.Ok
					ELSIF (e.method = 0) & (e.size = e.csize) THEN (* Stored *)
						NEW(S, fR, e.size); R := S.Receive; res := AosIO.Ok
					END
				END
			END OpenReceiver;

			PROCEDURE Extract*(entry: Entry; dest: AosIO.Writer; VAR res: LONGINT);
				VAR receiver : AosIO.Receiver; R: AosIO.Reader; buf: ARRAY 1024 OF CHAR; l: LONGINT; crc: CRC.CRC32Stream;
			BEGIN
				OpenReceiver(receiver, entry, res);
				NEW(R, receiver, 1024);
				IF res # AosIO.Ok THEN RETURN END;
				NEW(crc);
				R.Bytes(buf, 0, 1024, l);
				WHILE l > 0 DO
					dest.Bytes(buf, 0, l); crc.Bytes(buf, 0, l);
					R.Bytes(buf, 0, 1024, l)
				END;
				crc.Update();
				IF R.res = AosIO.EOF THEN
					IF entry.crc = crc.GetCRC() THEN
						res := AosIO.Ok
					END
				ELSE
					res := R.res
				END
			END Extract;

			PROCEDURE &New*(F: AosFS.File; VAR res: LONGINT);
				VAR R: AosFS.Reader; r, e: Entry; pos, sig, l, j: LONGINT; i: INTEGER;
			BEGIN
				res := AosIO.Ok; SELF.F := NIL; root := NIL; entries := 0;
				pos := F.Length()-20; sig := 0;
				WHILE (sig # EndOfCentralDirSig) & (pos > 0) DO
					DEC(pos);
					AosFS.OpenReader(R, F, pos);
					R.RawLInt(sig)
				END;
				IF sig # EndOfCentralDirSig THEN res := AosIO.FormatError; RETURN END;
				R.RawInt(i); R.RawInt(i);
				R.RawInt(i); entries := i;
				R.RawInt(i); R.RawLInt(l);
				R.RawLInt(pos);
				IF R.res # AosIO.Ok THEN res := R.res END;
				IF (pos < 0) OR (pos >= F.Length()) THEN res := AosIO.FormatError; RETURN END;
				AosFS.OpenReader(R, F, pos);
				NEW(r); r.next := NIL; e := r;
				j := 0;
				WHILE j < entries DO
					NEW(e.next); e := e.next; e.next := NIL;
					R.RawLInt(sig);
					IF sig = CentralFileHeadSig THEN
						ReadEntry(R, e, FALSE)
					ELSE
						res := AosIO.FormatError; RETURN
					END;
					INC(j)
				END;
				R.RawLInt(sig);
				IF sig # EndOfCentralDirSig THEN res := AosIO.FormatError; RETURN END;
				IF res = AosIO.Ok THEN
					SELF.F := F; root := r.next
				ELSE
					SELF.F := NIL; root := NIL; entries := 0
				END
			END New;

		END ZipFile;

	PROCEDURE DosToOberonTime(t: LONGINT): LONGINT;
	BEGIN
		RETURN t DIV 800H MOD 20H * 1000H + t DIV 20H MOD 40H * 40H + t MOD 20H * 2
	END DosToOberonTime;

	PROCEDURE DosToOberonDate(d: LONGINT): LONGINT;
	BEGIN
		RETURN (d DIV 200H MOD 80H + 1980 - 1900) * 200H + d MOD 200H
	END DosToOberonDate;

	PROCEDURE ReadEntry(R: AosIO.Reader; entry: Entry; local: BOOLEAN);
		VAR l, nl, xl, t, d: LONGINT; i: INTEGER;
	BEGIN
		IF local THEN
			R.RawInt(i);
			R.RawInt(i); R.RawInt(i); entry.method := i;
			R.RawInt(i); t := DosToOberonTime(i);
			R.RawInt(i); d := DosToOberonDate(i);
			entry.td := Utilities.OberonToDateTime(d, t);
			R.RawLInt(entry.crc);
			R.RawLInt(entry.csize);
			R.RawLInt(entry.size);
			R.RawInt(i); nl := i;
			R.RawInt(i); xl := i;
			NEW(entry.name, nl+1);
			l := 0;
			WHILE l < nl DO
				R.Char(entry.name[l]); INC(l)
			END;
			entry.name[l] := 0X;
			R.SkipBytes(xl)
		ELSE
			R.RawInt(i); R.RawInt(i);
			R.RawInt(i); R.RawInt(i); entry.method := i;
			R.RawInt(i); t := DosToOberonTime(i);
			R.RawInt(i); d := DosToOberonDate(i);
			entry.td := Utilities.OberonToDateTime(d, t);
			R.RawLInt(entry.crc);
			R.RawLInt(entry.csize);
			R.RawLInt(entry.size);
			R.RawInt(i); nl := i;
			R.RawInt(i); xl := i;
			R.RawInt(i); xl := xl + i;
			R.RawInt(i); R.RawInt(i);
			R.RawLInt(l); R.RawLInt(entry.pos);
			NEW(entry.name, nl+1);
			l := 0;
			WHILE l < nl DO
				R.Char(entry.name[l]); INC(l)
			END;
			entry.name[l] := 0X;
			R.SkipBytes(xl)
		END
	END ReadEntry;

	PROCEDURE StripPrefix(long: ARRAY OF CHAR; VAR short: ARRAY OF CHAR);
		VAR i, j: LONGINT; ch: CHAR;
	BEGIN
		i := 0; j := 0; ch := long[0];
		WHILE ch # 0X DO
			IF (ch = "/") OR (ch = "\") THEN
				j := 0
			ELSE
				short[j] := ch; INC(j)
			END;
			INC(i); ch := long[i]
		END;
		short[j] := 0X
	END StripPrefix;

	PROCEDURE ExtractEntry(zip: ZipFile; entry: Entry; name: ARRAY OF CHAR; backup, path: BOOLEAN);
		VAR F: AosFS.File; W: AosFS.Writer; res: LONGINT; bak: AosFS.FileName;
	BEGIN
		IF ~path THEN StripPrefix(name, name) END;
		AosOut.String(name);
		F := AosFS.New(name);
		IF F = NIL THEN
			AosOut.String(" failed"); AosOut.Ln(); RETURN
		END;
		AosFS.OpenWriter(W, F, 0);
		zip.Extract(entry, W, res);
		IF res = AosIO.Ok THEN
			IF backup THEN
				COPY(name, bak); Utilities.Append(bak, ".Bak");
				AosFS.Rename(name, bak, res);
				(* ASSERT(res = 0) what if it did not exist before ? *)
				IF (res # 0) & (res # 2) THEN AosOut.String("Backup failed on "); AosOut.String(name); AosOut.Ln END
			END;
			W.Update(); AosFS.Register(F)
		ELSE
			AosOut.String(" failed")
		END;
		AosOut.Ln()
	END ExtractEntry;

	(* Extract [ \o ] [ \d ] [ \p prefix ] zip { entry } ~ *)
	PROCEDURE Extract*(par: PTR): PTR;
		VAR
			p: AosCommands.Parameters; R: AosIO.StringReader;
			F: AosFS.File; zip: ZipFile; name, fs: AosFS.FileName; res, i: LONGINT;
			e: Entry; opt: ARRAY 32 OF CHAR; ch: CHAR; backup, path, prefix: BOOLEAN;
	BEGIN
		p := par(AosCommands.Parameters);
		NEW(R, LEN(p.str)); R.Set(p.str^); R.SkipWhitespace();
		backup := TRUE; prefix := FALSE; path := FALSE;
		WHILE R.Peek() = "\" DO
			R.Char(ch); R.SkipWhitespace(); R.String(opt);
			IF opt = "o" THEN
				backup := FALSE
			ELSIF opt = "d" THEN
				path := TRUE
			ELSIF opt = "p" THEN
				prefix := TRUE;
				R.SkipWhitespace(); R.String(fs)
			ELSE
				AosOut.String("unknown option "); AosOut.String(opt); AosOut.Ln();
				RETURN NIL
			END;
			R.SkipWhitespace()
		END;
		R.String(name); R.SkipWhitespace();
		IF name = "" THEN RETURN NIL END;
		F := AosFS.Old(name);
		IF F = NIL THEN RETURN NIL END;
		NEW(zip, F, res);
		IF res = AosIO.Ok THEN
			R.String(name);
			WHILE name # "" DO
				e := zip.FindEntry(name);
				IF e # NIL THEN
					IF prefix THEN
						COPY(fs, name); Utilities.Append(name, e.name^)
					END;
					ExtractEntry(zip, e, name, backup, path)
				ELSE
					AosOut.String(name); AosOut.String(" not found"); AosOut.Ln()
				END;
				R.SkipWhitespace(); R.String(name)
			END;
			AosOut.Ln()
		ELSE
			AosOut.String(name); AosOut.String(" is not a valid zip file"); AosOut.Ln()
		END;
		RETURN NIL	
	END Extract;

	(* ExtractAll [ \o ] [ \d ] [ \p prefix ] zip ~ *)
	PROCEDURE ExtractAll*(par: PTR): PTR;
		VAR
			p: AosCommands.Parameters; R: AosIO.StringReader;
			F: AosFS.File; zip: ZipFile; name, fs: AosFS.FileName; res, i: LONGINT;
			e: Entry; opt: ARRAY 32 OF CHAR; ch: CHAR; backup, path, prefix: BOOLEAN;
	BEGIN
		p := par(AosCommands.Parameters);
		NEW(R, LEN(p.str)); R.Set(p.str^); R.SkipWhitespace();
		backup := TRUE; prefix := FALSE; path := FALSE;
		WHILE R.Peek() = "\" DO
			R.Char(ch); R.SkipWhitespace(); R.String(opt);
			IF opt = "o" THEN
				backup := FALSE
			ELSIF opt = "d" THEN
				path := TRUE
			ELSIF opt = "p" THEN
				prefix := TRUE;
				R.SkipWhitespace(); R.String(fs)
			ELSE
				AosOut.String("unknown option "); AosOut.String(opt); AosOut.Ln();
				RETURN NIL
			END;
			R.SkipWhitespace()
		END;
		R.String(name);
		WHILE name # "" DO
			F := AosFS.Old(name);
			IF F # NIL THEN
				NEW(zip, F, res);
				IF res = AosIO.Ok THEN
					e := zip.GetFirst();
					WHILE e # NIL DO
						IF prefix THEN
							COPY(fs, name); Utilities.Append(name, e.name^)
						ELSE
							COPY(e.name^, name)
						END;
						ExtractEntry(zip, e, name, backup, path);
						e := zip.GetNext(e)
					END;
					AosOut.Ln()
				ELSE
					AosOut.String(name); AosOut.String(" is not a valid zip file"); AosOut.Ln()
				END
			ELSE
				AosOut.String(name); AosOut.String(" not found"); AosOut.Ln()
			END;
			R.SkipWhitespace(); R.String(name)
		END;
		RETURN NIL	
	END ExtractAll;

	(* Directory [ \d ] zip ~ *)
	PROCEDURE Directory*(par: PTR): PTR;
		VAR
			p: AosCommands.Parameters; R: AosIO.StringReader;
			F: AosFS.File; zip: ZipFile; name: AosFS.FileName; res, i: LONGINT;
			e: Entry; opt: ARRAY 32 OF CHAR; ch: CHAR; detail: BOOLEAN;
	BEGIN
		p := par(AosCommands.Parameters);
		NEW(R, LEN(p.str)); R.Set(p.str^);
		R.SkipWhitespace();
		detail := FALSE;
		WHILE R.Peek() = "\" DO
			R.Char(ch); R.SkipWhitespace(); R.String(opt);
			IF opt = "d" THEN
				detail := TRUE
			ELSE
				AosOut.String("unknown option "); AosOut.String(opt); AosOut.Ln();
				RETURN NIL
			END;
			R.SkipWhitespace()
		END;
		R.String(name);
		IF name = "" THEN RETURN NIL END;
		F := AosFS.Old(name);
		IF F = NIL THEN RETURN NIL END;
		NEW(zip, F, res);
		IF res = AosIO.Ok THEN
			AosOut.String("Directory of "); AosOut.String(name);
			AosOut.Ln(); AosOut.Ln();
			e := zip.GetFirst(); i := 0;
			WHILE e # NIL DO
				INC(i);
				AosOut.String(e.name^);
				IF detail THEN
					AosOut.Char(09X); Utilities.DateToStr(e.td, opt); AosOut.String(opt);
					AosOut.String(" "); Utilities.TimeToStr(e.td, opt); AosOut.String(opt);
					AosOut.Char(09X); AosOut.Int(e.size, 0);
					AosOut.Char(09X); AosOut.Int(e.csize, 0);
					AosOut.Ln()
				ELSE
					IF (i MOD 2) = 0 THEN
						AosOut.Ln()
					ELSE
						AosOut.Char(09X)
					END
				END;
				e := zip.GetNext(e)
			END;
			AosOut.Ln()
		ELSE
			AosOut.String(name); AosOut.String(" is not a valid zip file"); AosOut.Ln()
		END;
		RETURN NIL	
	END Directory;

END AosUnzip.

S.Free AosUnzip AosInflate ~

AosInflate.Mod	AosUnzip.Mod

Aos.Call AosUnzip.ExtractAll \p AOS: \o
	AosSys.zip AosApps.zip AosOberon.zip AosGad.zip AosDocu.zip AosOberonApps1.zip 
	AosOberonApps2.zip AosBuild.zip Pr3Fonts.zip Pr6Fonts.zip
	AosSysSrc.zip AosAppsSrc.zip AosOberonSrc.zip AosGadSrc.zip AosOberonAppsSrc.zip AosBuildSrc.zip
	AosContributions.zip AosContributionsSrc.zip
	AosSrcP.zip ~
