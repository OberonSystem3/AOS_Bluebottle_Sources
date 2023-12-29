(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE AosZip;	(** Stefan Walthert   **)

IMPORT
	AosIO, AosFS, Zlib, ZlibReaders := AosZlibReaders, ZlibWriters := AosZlibWriters;

CONST
	
	(** result codes **)
	Ok* = 0;	(** operation on zip-file was successful **)
	FileError* = -1;	(** file not found **)
	NotZipArchiveError* = -2;	(** file is not in zip format **)
	EntryNotFound* = -3;	(** specified file was not found in zip-file **)
	EntryAlreadyExists* = -4;	(** file is already stored in zip-file -> can not add specified file to zip-file **)
	NotSupportedError* = -5;	(** can not extract specified file (compression method not supported/file is encrypted) **)
	DataError* = -6;	(** file is corrupted **)
	BadName* = -7;	(** bad file name *)
	ReaderError* = -8;	(** e.g. Reader not opened before Read **)

	(** compression levels **)
	DefaultCompression* = ZlibWriters.DefaultCompression;
	NoCompression* = ZlibWriters.NoCompression;
	BestSpeed* = ZlibWriters.BestSpeed;
	BestCompression* = ZlibWriters.BestCompression;

	(** compression strategies **)
	DefaultStrategy* = ZlibWriters.DefaultStrategy;
	Filtered* = ZlibWriters.Filtered;
	HuffmanOnly* = ZlibWriters.HuffmanOnly;

	(* support *)
	Supported = 0;	(* can extract file *)
	IncompatibleVersion = 1;	(* version needed to extract < PKZIP 1.00 *)
	Encrypted = 2;	(* file is encrypted *)
	UnsupCompMethod = 3;	(* file not stored or deflated *)

	Stored = 0;	(* file is stored (no compression) *)
	Deflated = 8;	(* file is deflated *)

	SupportedCompMethods = {Stored, Deflated};
	CompatibleVersions = 1;	(* versions >= CompatibleVersions are supported *)

	(* headers *)
	LocalFileHeaderSignature = 04034B50H;
	CentralFileHeaderSignature = 02014B50H;
	EndOfCentralDirSignature = 06054B50H;

TYPE
	Entry* = POINTER TO EntryDesc;	(** description of a file stored in the zip-archive **)
	EntryDesc* = RECORD
		name-: ARRAY 256 OF CHAR;	(** name of file stored in the zip-archive **)
		method: INTEGER;	(* compression method *)
		time-, date-: LONGINT;	(** (Oberon) time and date when file was last modified **)
		crc32: LONGINT;	(* checksum of uncompressed file data *)
		compSize-, uncompSize-: LONGINT;	(** size of compressed / uncompressed file **)
		intFileAttr: INTEGER;	(* internal file attributes, not used in this implementation *)
		extFileAttr: LONGINT;	(* external file attributes, not used in this implementation *)
		extraField (* for future expansions *), comment-: POINTER TO ARRAY OF CHAR;	(** comment for this file **)
		genPurpBitFlag: INTEGER;
		support: SHORTINT;
		dataDescriptor: BOOLEAN;	(* if set, data descriptor after (compressed) file data *)
		offsetLocal: LONGINT;	(* offset of file header in central directory *)
		offsetFileData: LONGINT;	(* offset of (compressed) file data *)
		offsetCentralDir: LONGINT;	(* offset of local file header *)
		next: Entry
	END;

	Archive* = POINTER TO ArchiveDesc;	(** description of a zipfile **)
	ArchiveDesc* = RECORD
		nofEntries-: INTEGER;	(** total number of files stored in the zipfile **)
		comment-: POINTER TO ARRAY OF CHAR;	(** comment for zipfile **)
		file: AosFS.File;	(* pointer to the according zip-file *)
		offset: LONGINT;	(* offset of end of central dir record *)
		firstEntry, lastEntry: Entry	(* first and last Entry of Archive *)
	END;
	
	Reader* = POINTER TO ReaderDesc;
	ReaderDesc* = RECORD	(** structure for reading from a zip-file into a buffer **)
		res-: LONGINT;	(** result of last operation **)
		open: BOOLEAN;
		ent: Entry
	END;
	
	UncompReader = POINTER TO UncompReaderDesc;
	UncompReaderDesc = RECORD (ReaderDesc)	(* structur for reading from a uncompressed entry *)
		fr: AosFS.Reader;
		crc32: LONGINT;	(* crc32 of uncomressed data *)
	END;
	
	DefReader = POINTER TO DefReaderDesc;
	DefReaderDesc = RECORD (ReaderDesc)	(* structure for reading from a deflated entry *)
		zr: ZlibReaders.Reader
	END;

(* length of str *)
PROCEDURE StringLength(VAR str(* in *): ARRAY OF CHAR): LONGINT;
	VAR i, l: LONGINT;
BEGIN
	l := LEN(str); i := 0;
	WHILE (i < l) & (str[i] # 0X) DO
		INC(i)
	END;
	RETURN i
END StringLength;

(* Converts Oberon time into MS-DOS time *)
PROCEDURE OberonToDosTime(t: LONGINT): INTEGER;
BEGIN
	RETURN SHORT(t DIV 1000H MOD 20H * 800H + t DIV 40H MOD 40H * 20H + t MOD 40H DIV 2)
END OberonToDosTime;

(* Converts Oberon date into MS-DOS time *)
PROCEDURE OberonToDosDate(d: LONGINT): INTEGER;
BEGIN
	RETURN SHORT((d DIV 200H + 1900 - 1980) * 200H + d MOD 200H)
END OberonToDosDate;

(* Converts MS-DOS time into Oberon time *)
PROCEDURE DosToOberonTime(t: INTEGER): LONGINT;
BEGIN
	RETURN LONG(t) DIV 800H MOD 20H * 1000H + t DIV 20H MOD 40H * 40H + t MOD 20H * 2
END DosToOberonTime;

(* Converts MS-DOS date into Oberon date *)
PROCEDURE DosToOberonDate(d: INTEGER): LONGINT;
BEGIN
	RETURN (LONG(d) DIV 200H MOD 80H + 1980 - 1900) * 200H + d MOD 200H
END DosToOberonDate;
(*
(* Copy len bytes from src to dst; if compCRC32 is set, then the crc 32-checksum is computed *)
PROCEDURE Copy(VAR src: AosIO.Reader; dst: AosIO.Writer; len: LONGINT; compCRC32: BOOLEAN; VAR crc32: LONGINT);
CONST
	BufSize = 4000H;
VAR
	n: LONGINT;
	buf: ARRAY BufSize OF CHAR;
BEGIN
	IF compCRC32 THEN crc32 := Zlib.CRC32(0, buf, -1, -1) END;
	REPEAT
		IF len < BufSize THEN n := len
		ELSE n := BufSize
		END;
		AosIO.ReadBytes(src, buf, 0, n);
		IF compCRC32 THEN crc32 := Zlib.CRC32(crc32, buf, 0, n - src.res) END;
		AosIO.WriteBytes(dst, buf, 0, n - src.res);
		DEC(len, n)
	UNTIL len = 0
END Copy;
*)
(* Reads an Entry, r must be at the start of a file header; returns NIL if read was not successful *)
PROCEDURE ReadEntry(VAR r: AosFS.Reader; f: AosFS.File): Entry;
VAR
	ent: Entry;
	intDummy, nameLen, extraLen, commentLen: INTEGER;
	longDummy, read: LONGINT;
	bufDummy: ARRAY 256 OF CHAR;
	t: AosFS.Reader;
BEGIN
	r.RawLInt(longDummy);
	IF longDummy = CentralFileHeaderSignature THEN
		NEW(ent);
		(*ent.offsetCentralDir := Files.Pos(r) - 4;*)
		ent.support := 0;
		r.RawInt(intDummy);	(* version made by *)
		r.RawInt(intDummy);	(* version needed to extract *)
		IF (intDummy MOD 100H) / 10 < CompatibleVersions THEN
			ent.support := IncompatibleVersion
		END;
		r.RawInt(ent.genPurpBitFlag);	(* general purpose bit flag *)
		IF ODD(intDummy) THEN
			ent.support := Encrypted	(* bit 0: if set, file encrypted *)
		END;
		ent.dataDescriptor := ODD(intDummy DIV 8);	(* bit 3: data descriptor after (compressed) file data *)
		r.RawInt(ent.method);	(* compression method *)
		IF (ent.support = Supported) & ~(ent.method IN SupportedCompMethods) THEN
			ent.support := UnsupCompMethod
		END;
		r.RawInt(intDummy); ent.time := DosToOberonTime(intDummy);	(* last mod file time *)
		r.RawInt(intDummy); ent.date := DosToOberonDate(intDummy);	(* last mod file date *)
		r.RawLInt(ent.crc32);	(* crc-32 *)
		r.RawLInt(ent.compSize);	(* compressed size *)
		r.RawLInt(ent.uncompSize);	(* uncompressed size *)
		r.RawInt(nameLen);	(* filename length *)
		r.RawInt(extraLen);	(* extra field length *)
		r.RawInt(commentLen);	(* file comment length *)
		r.RawInt(intDummy);	(* disk number start *)
		r.RawInt(ent.intFileAttr);	(* internal file attributes *)
		r.RawLInt(ent.extFileAttr);	(* external file attributes *)
		r.RawLInt(ent.offsetLocal);	(* relative offset of local header *)
		r.Bytes(ent.name, 0, nameLen, read);	(* filename *)
		IF extraLen # 0 THEN
			NEW(ent.extraField, extraLen);
			r.Bytes(ent.extraField^, 0, extraLen, read)	(* extra field *)
		END;
		IF commentLen > 0 THEN
			NEW(ent.comment, commentLen);
			r.Bytes(ent.comment^, 0, commentLen, read)	(* file comment *)
		END;
		(* read extra field length in the local file header (can be different from extra field length stored in the file header...) *)
		AosFS.OpenReader(t, f, ent.offsetLocal + 28);	(* set r to position of extra field length in local file header *)
		r.RawInt(extraLen);	(* extra field length *)
		ent.offsetFileData := ent.offsetLocal + 30 + nameLen + extraLen;	(* compute offset of file data *)
(*
		longDummy := Files.Pos(r);	(* store actual position of file reader *)
		Files.Set(r, Files.Base(r), ent.offsetLocal + 28);	(* set r to position of extra field length in local file header *)
		r.RawInt(extraLen);	(* extra field length *)
		ent.offsetFileData := ent.offsetLocal + 30 + nameLen + extraLen;	(* compute offset of file data *)
		Files.Set(r, Files.Base(r), longDummy);	(* set position of file reader to previous position *)
*)
(*
		IF r.eof THEN	(* if file is a zip-archive, r is not at end of file *)
			ent := NIL
		END
*)
	END;
	RETURN ent;
END ReadEntry;

PROCEDURE EntrySize(ent: Entry): LONGINT;
	VAR size: LONGINT;
BEGIN
	size := 22 + 24 + StringLength(ent.name);
	IF ent.extraField # NIL THEN INC(size, LEN(ent.extraField)) END;
	IF ent.comment # NIL THEN INC(size, LEN(ent.comment)) END;
	RETURN size
END EntrySize;
(*
(* Writes a local file header *)
PROCEDURE WriteLocalFileHeader(ent: Entry; VAR r: Files.Rider);
BEGIN
	AosIO.WriteRawLInt(r, LocalFileHeaderSignature);	(* local file header signature *)
	AosIO.WriteRawInt(r, CompatibleVersions * 10);	(* version needed to extract *)
	AosIO.WriteRawInt(r, ent.genPurpBitFlag);	(* general purpose bit flag *)
	AosIO.WriteRawInt(r, ent.method);	(* compression method *)
	AosIO.WriteRawInt(r, OberonToDosTime(ent.time));	(* last mod file time *)
	AosIO.WriteRawInt(r, OberonToDosDate(ent.date));	(* last mod file date *)
	AosIO.WriteRawLInt(r, ent.crc32);	(* crc-32 *)
	AosIO.WriteRawLInt(r, ent.compSize);	(* compressed size *)
	AosIO.WriteRawLInt(r, ent.uncompSize);	(* uncompressed size *)
	AosIO.WriteRawInt(r, SHORT(StringLength(ent.name)));	(* filename length *)
	IF ent.extraField # NIL THEN
		AosIO.WriteRawInt(r, SHORT(LEN(ent.extraField^)))	(* extra field length *)
	ELSE
		AosIO.WriteRawInt(r, 0)
	END;
	AosIO.WriteBytes(r, ent.name, 0, StringLength(ent.name));	(* filename *)
	IF ent.extraField # NIL THEN
		AosIO.WriteBytes(r, ent.extraField^, 0, LEN(ent.extraField^))	(* extra field *)
	END
END WriteLocalFileHeader;

(* Writes file header in central directory, updates ent.offsetCentralDir *)
PROCEDURE WriteFileHeader(ent: Entry; VAR r: Files.Rider);
BEGIN
	ent.offsetCentralDir := Files.Pos(r);
	AosIO.WriteRawLInt(r, CentralFileHeaderSignature);	(* central file header signature *)
	AosIO.WriteRawInt(r, CompatibleVersions * 10);	(* version made by *)
	AosIO.WriteRawInt(r, CompatibleVersions * 10);	(* version needed to extract *)
	AosIO.WriteRawInt(r, ent.genPurpBitFlag);	(* general purpose bit flag *)
	AosIO.WriteRawInt(r, ent.method);	(* compression method *)
	AosIO.WriteRawInt(r, OberonToDosTime(ent.time));	(* last mod file time *)
	AosIO.WriteRawInt(r, OberonToDosDate(ent.date));	(* last mod file date *)
	AosIO.WriteRawLInt(r, ent.crc32);	(* crc-32 *)
	AosIO.WriteRawLInt(r, ent.compSize);	(* compressed size *)
	AosIO.WriteRawLInt(r, ent.uncompSize);	(* uncompressed size *)
	AosIO.WriteRawInt(r, SHORT(StringLength(ent.name)));	(* filename length *)
	IF ent.extraField = NIL THEN
		AosIO.WriteRawInt(r, 0)
	ELSE
		AosIO.WriteRawInt(r, SHORT(LEN(ent.extraField^)));	(* extra field length *)
	END;
	IF ent.comment = NIL THEN
		AosIO.WriteRawInt(r, 0)
	ELSE
		AosIO.WriteRawInt(r, SHORT(LEN(ent.comment^)));	(* file comment length *)
	END;
	AosIO.WriteRawInt(r, 0);	(* disk number start *)
	AosIO.WriteRawInt(r, ent.intFileAttr);	(* internal file attributes *)
	AosIO.WriteRawLInt(r, ent.extFileAttr);	(* external file attributes *)
	AosIO.WriteRawLInt(r, ent.offsetLocal);	(* relative offset of local header *)
	AosIO.WriteBytes(r, ent.name, 0, StringLength(ent.name));	(* filename *)
	IF ent.extraField # NIL THEN
		AosIO.WriteBytes(r, ent.extraField^, 0, LEN(ent.extraField^))	(* extra field *)
	END;
	IF ent.comment # NIL THEN
		AosIO.WriteBytes(r, ent.comment^, 0, LEN(ent.comment^))	(* file comment *)
	END
END WriteFileHeader;

(* Writes end of central directory record *)
PROCEDURE WriteEndOfCentDir(arc: Archive; VAR r: Files.Rider);
VAR
	size: LONGINT;
BEGIN
	AosIO.WriteRawLInt(r, EndOfCentralDirSignature);	(* end of central dir signature *)
	AosIO.WriteRawInt(r, 0);	(* number of this disk *)
	AosIO.WriteRawInt(r, 0);	(* number of the disk with the start of the central directory *)
	AosIO.WriteRawInt(r, arc.nofEntries);	(* total number of entries in the central dir on this disk *)
	AosIO.WriteRawInt(r, arc.nofEntries);	(* total number of entries in the central dir *)
	IF arc.firstEntry # NIL THEN
		AosIO.WriteRawLInt(r, arc.offset - arc.firstEntry.offsetCentralDir)	(* size of the central directory (without end of central dir record) *)
	ELSE
		AosIO.WriteRawLInt(r, 0)
	END;
	IF arc.firstEntry = NIL THEN
		AosIO.WriteRawLInt(r, arc.offset)	(* offset of start of central directory with respect to the starting disk number *)
	ELSE
		AosIO.WriteRawLInt(r, arc.firstEntry.offsetCentralDir)	(* offset of start of central directory with respect to the starting disk number *)
	END;
	IF arc.comment = NIL THEN
		AosIO.WriteRawInt(r, 0)	(* zipfile comment length *)
	ELSE
		AosIO.WriteRawInt(r, SHORT(LEN(arc.comment^)));	(* zipfile comment length *)
		AosIO.WriteBytes(r, arc.comment^, 0, LEN(arc.comment^))	(* zipfile comment *)
	END
END WriteEndOfCentDir;

(* Writes central directory + end of central directory record, updates arc.offset and offsetCentralDir of entries *)
PROCEDURE WriteCentralDirectory(arc: Archive; VAR r: Files.Rider);
VAR
	ent: Entry;
BEGIN
	ent := arc.firstEntry;
	WHILE ent # NIL DO
		WriteFileHeader(ent, r);
		ent := ent.next
	END;
	arc.offset := Files.Pos(r);
	WriteEndOfCentDir(arc, r)
END WriteCentralDirectory;
*)
(** Returns an Archive data structure corresponding to the specified zipfile;
	possible results: 
	- Ok: operation was successful
	- FileError: file with specified name does not exist
	- NotZipArchiveError: file is not a correct zipfile **) 
PROCEDURE OpenArchive*(name: ARRAY OF CHAR; VAR res: LONGINT): Archive;
VAR
	arc: Archive;
	ent: Entry;
	f: AosFS.File;
	r: AosFS.Reader;
	longDummy, pos, read: LONGINT;
	intDummy: INTEGER;
BEGIN
	res := Ok;
	f := AosFS.Old(name);
	IF f = NIL THEN
		res := FileError
	ELSIF f.Length() < 22 THEN
		res := NotZipArchiveError
	ELSE
		longDummy := 0;
		pos := f.Length() - 21;
		WHILE (longDummy # EndOfCentralDirSignature) & (pos > 0) DO
			DEC(pos);
			AosFS.OpenReader(r, f, pos);
			r.RawLInt(longDummy)
		END;
		IF longDummy # EndOfCentralDirSignature THEN
			res := NotZipArchiveError
		ELSE
			NEW(arc);
			arc.file := f;
			arc.offset := pos(*Files.Pos(r) - 4*);
			r.RawInt(intDummy);	(* number of this disk *)
			r.RawInt(intDummy);	(* number of the disk with the start of the central directory *)
			r.RawInt(intDummy);	(* total number of entries in the central dir on this disk *)
			r.RawInt(arc.nofEntries);	(* total number of entries in the central dir *)
			r.RawLInt(longDummy);	(* size of the central directory *)
			r.RawLInt(longDummy);	(* offset of start of central directory with respect to the starting disk number *)
			r.RawInt(intDummy);	(* zipfile comment length *)
			IF intDummy # 0 THEN
				NEW(arc.comment, intDummy);
				r.Bytes(arc.comment^, 0, intDummy, read)	(* zipfile comment *)
			END;
			IF (*Files.Pos(r)*)(pos + 22 + intDummy) # f.Length() THEN
				res := NotZipArchiveError;
				arc := NIL
			ELSE
				AosFS.OpenReader(r, f, longDummy);	(* set r on position of first file header in central dir *)
				arc.firstEntry := ReadEntry(r, f); arc.lastEntry := arc.firstEntry;
				ent := arc.firstEntry; intDummy := 0;
				WHILE ent # NIL DO
					ent.offsetCentralDir := longDummy;
					INC(longDummy, EntrySize(ent));
					arc.lastEntry := ent; INC(intDummy); (* count number of entries *)
					ent.next := ReadEntry(r, f);
					ent := ent.next
				END;
				IF intDummy # arc.nofEntries THEN
					res := NotZipArchiveError;
					arc := NIL
				END
			END;
			(*Files.Close(f)*)
		END
	END;
	RETURN arc
END OpenArchive;
(*
(** Returns an Archive that corresponds to a file with specified name;
	if there is already a zip-file with the same name, this already existing archive is returned;
	possible results: cf. OpenArchive **)
PROCEDURE CreateArchive*(VAR name: ARRAY OF CHAR; VAR res: LONGINT): Archive;
VAR
	f: AosFS.File;
	r: Files.Rider;
	arc: Archive;
BEGIN
	f := AosFS.Old(name);
	IF f # NIL THEN
		RETURN OpenArchive(name, res)
	ELSE
		f := Files.New(name);
		NEW(arc);
		arc.file := f;
		arc.nofEntries := 0;
		arc.offset := 0;
		Files.Set(r, f, 0);
		WriteEndOfCentDir(arc, r);
		Files.Register(f);
		res := Ok;
		RETURN arc
	END		
END CreateArchive;
*)
(** Returns the first entry of the Archive arc (NIL if there is no Entry) **)
PROCEDURE FirstEntry*(arc: Archive): Entry;
BEGIN
	IF arc = NIL THEN
		RETURN NIL
	ELSE
		RETURN arc.firstEntry
	END
END FirstEntry;

(** Returns the next Entry after ent **)
PROCEDURE NextEntry*(ent: Entry): Entry;
BEGIN
	RETURN ent.next
END NextEntry;
(*
(** Returns the Entry that corresponds to the file with the specified name and that is stored in the Archive arc;
	possible results:
	- Ok: Operation was successful
	- NotZipArchiveError: arc is not a valid Archive
	- EntryNotFound: no Entry corresponding to name was found **)
PROCEDURE GetEntry*(arc: Archive; VAR name: ARRAY OF CHAR; VAR res: LONGINT): Entry;
VAR
	ent: Entry;
BEGIN
	IF arc = NIL THEN
		res := NotZipArchiveError
	ELSE
		ent := arc.firstEntry;
		WHILE (ent # NIL) & (ent.name # name) DO
			ent := ent.next
		END;
		IF ent = NIL THEN
			res := EntryNotFound
		ELSE
			res := Ok
		END
	END;
	RETURN ent
END GetEntry;

(** Uncompresses and writes the data of Entry ent to Files.Rider dst;
	possible results:
	- Ok: Data extracted
	- NotZipArchiveError: arc is not a valid zip-archive
	- EntryNotFound: ent is not an Entry of arc
	- NotSupportedError: data of ent are encrypted or compression method is not supported
	- DataError: zipfile is corrupted
	- BadName: entry has a bad file name **)
PROCEDURE ExtractEntry*(arc: Archive; ent: Entry; VAR dst: Files.Rider; VAR res: LONGINT);
VAR
	src: Files.Rider; crc32: LONGINT;
BEGIN
	IF arc = NIL THEN
		res := NotZipArchiveError
	ELSIF Files.Base(dst) = NIL THEN
		res := BadName
	ELSIF (ent = NIL) OR (ent # GetEntry(arc, ent.name, res)) THEN
		res := EntryNotFound
	ELSIF ~(ent.method IN SupportedCompMethods) OR (ent.support > Supported) THEN
		res := NotSupportedError
	ELSE
		CASE ent.method OF
		| Stored:
			Files.Set(src, arc.file, ent.offsetFileData);
			Copy(src, dst, ent.uncompSize, TRUE, crc32);
			IF crc32 = ent.crc32 THEN
				res := Ok
			ELSE
				res := DataError
			END
		| Deflated:		
			Files.Set(src, arc.file, ent.offsetFileData);
			ZlibReaders.Uncompress(src, dst, crc32, res);
			IF (res = ZlibReaders.Ok) & (crc32 = ent.crc32) THEN
				res := Ok
			ELSE
				res := DataError
			END
		END;
		IF res = Ok THEN
			Files.Close(Files.Base(dst));
		END
	END
END ExtractEntry;

(** Reads and compresses len bytes from Files.Rider src with specified level and strategy 
	and writes them to a new Entry in the Archive arc;
	possible results:
	- Ok: file was added to arc
	- NotZipArchiveError: arc is not a valid zip-archive
	- EntryAlreadyExists: there is already an Entry in arc with the same name
	- DataError: error during compression
	- BadName: src is not based on a valid file **)
PROCEDURE AddEntry*(arc: Archive; VAR name: ARRAY OF CHAR; VAR src: Files.Rider; len: LONGINT; level, strategy: SHORTINT; VAR res: LONGINT);
VAR
	dst: Files.Rider; ent: Entry; start: LONGINT;
BEGIN
	IF arc = NIL THEN
		res := NotZipArchiveError
	ELSIF Files.Base(src) = NIL THEN
		res := BadName
	ELSIF (GetEntry(arc, name, res) # NIL) & (res = Ok) THEN
		res := EntryAlreadyExists
	ELSE		
		NEW(ent);
		COPY(name, ent.name);
		ent.genPurpBitFlag := 0;
		IF level = NoCompression THEN
			ent.method := Stored
		ELSE
			ent.method := Deflated
		END;			
		Files.GetDate(Files.Base(src), ent.time, ent.date);
		ent.uncompSize := len;
		ent.intFileAttr := 0;
		ent.extFileAttr := 0;
		ent.comment := NIL;
		ent.support := Supported;
		ent.dataDescriptor := FALSE;
		IF arc.firstEntry # NIL THEN
			ent.offsetLocal := arc.firstEntry.offsetCentralDir
		ELSE
			ent.offsetLocal := 0
		END;
		Files.Set(dst, arc.file, ent.offsetLocal);
		WriteLocalFileHeader(ent, dst);
		ent.offsetFileData := Files.Pos(dst);
		Files.Close(arc.file);
		start := Files.Pos(src);
		IF level = 0 THEN
			Copy(src, dst, len, TRUE, ent.crc32);
			ent.compSize := len;
			res := Ok
		ELSE
			ZlibWriters.Compress(src, dst, len, ent.compSize, level, strategy, ent.crc32, res);
			IF res # ZlibWriters.Ok THEN
				res := DataError
			ELSE
				res := Ok
			END
		END;
		IF res = Ok THEN
			ent.uncompSize := Files.Pos(src) - start;
			Files.Close(arc.file);
			Files.Set(dst, arc.file, ent.offsetLocal + 14);
			AosIO.WriteRawLInt(dst, ent.crc32);
			AosIO.WriteRawLInt(dst, ent.compSize);
			Files.Close(arc.file);
			IF arc.lastEntry # NIL THEN
				arc.lastEntry.next := ent
			ELSE	(* archive has no entries *)
				arc.firstEntry := ent
			END;
			arc.lastEntry := ent;
			INC(arc.nofEntries);
			Files.Set(dst, arc.file, ent.offsetFileData + ent.compSize);
			WriteCentralDirectory(arc, dst);
			Files.Close(arc.file);
			res := Ok
		END;
	END
END AddEntry;

(** Deletes Entry ent from Archive arc;
	Possible results:
	- Ok: ent was deleted, ent is set to NIL
	- NotZipArchiveError: arc is not a valid zip-archive
	- EntryNotFound: ent is not an Entry of Archive arc **)
PROCEDURE DeleteEntry*(arc: Archive; VAR ent: Entry; VAR res: LONGINT);
CONST
	BufSize = 4000H;
VAR
	f: AosFS.File; r1, r2: Files.Rider;
	ent2: Entry;
	arcname: ARRAY 256 OF CHAR;
	buf: ARRAY BufSize OF CHAR;
	offset, diff: LONGINT;
BEGIN
	IF arc = NIL THEN
		res := NotZipArchiveError
	ELSIF arc.firstEntry = NIL THEN
		res := EntryNotFound
	ELSIF arc.firstEntry = ent THEN
		offset := arc.firstEntry.offsetLocal;	(* arc.firstEntry.offsetLocal = 0 *)
		IF arc.lastEntry = arc.firstEntry THEN
			arc.lastEntry := arc.firstEntry.next	(* = NIL *)
		END;
		arc.firstEntry := arc.firstEntry.next;
		ent2 := arc.firstEntry;
		res := Ok
	ELSE
		ent2 := arc.firstEntry;
		WHILE (ent2.next # NIL) & (ent2.next # ent) DO
			ent2 := ent2.next
		END;
		IF ent2.next = NIL THEN
			res := EntryNotFound
		ELSE
			IF arc.lastEntry = ent2.next THEN
				arc.lastEntry := ent2
			END;
			offset := ent2.next.offsetLocal;
			ent2.next := ent2.next.next;
			ent2 := ent2.next;
			res := Ok
		END
	END;
	IF res = Ok THEN
		Files.GetName(arc.file, arcname);
		f := Files.New(arcname);
		Files.Set(r2, f, 0);
		Files.Set(r1, arc.file, 0);
		Copy(r1, r2, offset, FALSE, diff);	(* no crc 32-checksum is computed -> diff used as dummy *)
		Files.Close(f);
		ASSERT(ent2 = ent.next);
		IF ent2 # NIL THEN
			Files.Set(r1, arc.file, ent2.offsetLocal);
			Copy(r1, r2, arc.firstEntry.offsetCentralDir - ent2.offsetLocal, FALSE, diff);	(* arc.firstEntry can not be NIL because ent # NIL *)
			Files.Close(f);
			diff := ent2.offsetLocal - offset
		ELSE
			diff := arc.offset - offset
		END;
		WHILE (ent2 # NIL) DO	(* update offsets of entries *)
			DEC(ent2.offsetLocal, diff); DEC(ent2.offsetFileData, diff); DEC(ent2.offsetCentralDir, diff);
			ent2 := ent2.next
		END;
		DEC(arc.offset, diff);
		DEC(arc.nofEntries);
		WriteCentralDirectory(arc, r2);
		Files.Register(f); arc.file := f; ent := NIL
	END
END DeleteEntry;
*)
(** open a Reader to read uncompressed data from a zip entry directly to memory **)
PROCEDURE OpenReader*(arc: Archive; ent: Entry): Reader;
VAR
	dummyBuf: ARRAY 1 OF CHAR;
	fr: AosFS.Rider;
	r: Reader;
	ur: UncompReader;
	dr: DefReader;
BEGIN
	IF ent.support = Supported THEN
		IF ent.method = Stored THEN
			NEW(ur);
			ur.crc32 := Zlib.CRC32(0, dummyBuf, -1, -1);
			AosFS.OpenReader(ur.fr, arc.file, ent.offsetFileData);
			r := ur;
			r.open := TRUE;
			r.res := Ok
		ELSIF ent.method = Deflated THEN
			arc.file.Set(fr, ent.offsetFileData);
			NEW(dr); 
			ZlibReaders.Open(dr.zr, FALSE, fr);
			dr.res := dr.zr.res;
			r := dr;
			r.open := TRUE
		ELSE
			NEW(r);
			r.open := FALSE;
			r.res := NotSupportedError
		END;			
	ELSE
		NEW(r);
		r.open := FALSE;
		r.res := NotSupportedError
	END;
	r.ent := ent;
	RETURN r;
END OpenReader;

(** read len bytes of uncompressed data into buf[offset] and return number of bytes actually read; Reader must be opened **)
PROCEDURE ReadBytes*(r: Reader; VAR buf: ARRAY OF CHAR; offset, len: LONGINT; VAR read: LONGINT);
(*
VAR
	bufp: POINTER TO ARRAY OF CHAR; i: LONGINT;
*)
BEGIN
	IF r.open THEN
		IF r IS UncompReader THEN
			r(UncompReader).fr.Bytes(buf, offset, len, read);
(*
			IF offset = 0 THEN
				AosIO.ReadBytes(r(UncompReader).fr, buf, 0, len);
			ELSE
				NEW(bufp, len);
				AosIO.ReadBytes(r(UncompReader).fr, bufp^, 0, len);
				FOR i := 0 TO len - 1 DO
					buf[offset + i] := bufp[i]
				END
			END;
			read := len - r(UncompReader).fr.res;
*)
			r(UncompReader).crc32 := Zlib.CRC32(r(UncompReader).crc32, buf, offset, read)
		ELSIF r IS DefReader THEN
			ZlibReaders.ReadBytes(r(DefReader).zr, buf, offset, len, read);
			r.res := r(DefReader).zr.res
		END
	ELSE
		r.res := ReaderError
	END
END ReadBytes;

(** read decompressed byte **)
PROCEDURE Read*(r: Reader; VAR ch: CHAR);
VAR
	buf: ARRAY 1 OF CHAR; read: LONGINT;
BEGIN
	ReadBytes(r, buf, 0, 1, read);
	ch := buf[0];
END Read;

(** close Reader **)
PROCEDURE Close*(r: Reader);
BEGIN
	IF r.open THEN
		IF r IS UncompReader THEN
			IF r(UncompReader).crc32 # r.ent.crc32 THEN
				r.res := DataError
			ELSE
				r.res := Ok
			END
		ELSIF r IS DefReader THEN
			ZlibReaders.Close(r(DefReader).zr);
			IF r(DefReader).zr.crc32 # r.ent.crc32 THEN
				r.res := DataError
			ELSE
				r.res := r(DefReader).zr.res
			END
		ELSE
			r.res := ReaderError
		END;
		r.open := FALSE
	ELSE
		r.res := ReaderError
	END
END Close;

END AosZip.