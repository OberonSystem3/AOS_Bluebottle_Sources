MODULE AosTar; (** AUTHOR "ejz/FN"; PURPOSE "Aos tar program"; *)

IMPORT
	AosCommands, AosIO, AosFS, AosOut, Utilities, AosArchives, WMLocks;

CONST
	RecordSize = 512;
	NamSiz = 100; TuNmLen = 32; TgNmLen = 32;
	EntryNameSize = 128;

	SegmentSize = 1024;

	StreamClosed* = 10; (** error *)

TYPE
	Header = POINTER TO RECORD
		name: ARRAY NamSiz OF CHAR;
		mode: ARRAY 8 OF CHAR;
		uid: ARRAY 8 OF CHAR;
		gid: ARRAY 8 OF CHAR;
		size: ARRAY 12 OF CHAR;
		mtime: ARRAY 12 OF CHAR;
		chksum: ARRAY 8 OF CHAR;
		linkflag: ARRAY 1 OF CHAR;
		linkname: ARRAY NamSiz OF CHAR;
		magic: ARRAY 8 OF CHAR;
		uname: ARRAY TuNmLen OF CHAR;
		gname: ARRAY TgNmLen OF CHAR;
		devmajor: ARRAY 8 OF CHAR;
		devminor: ARRAY 8 OF CHAR;
	END;

	(** contains info about an archive entry *)
	EntryInfo*= OBJECT(AosArchives.EntryInfo)
	VAR
		name : ARRAY EntryNameSize OF CHAR;
		size : LONGINT;

		PROCEDURE & Init(name : ARRAY OF CHAR; size : LONGINT);
		BEGIN
			COPY(name, SELF.name); SELF.size := size
		END Init;

		PROCEDURE GetName*() : Utilities.String;
		VAR n : Utilities.String;
		BEGIN
			NEW(n, EntryNameSize); COPY(name, n^);
			RETURN n
		END GetName;

		PROCEDURE GetSize*() : LONGINT;
		BEGIN
			RETURN size
		END GetSize;

		PROCEDURE GetInfoString*() : Utilities.String;
		VAR s : Utilities.String;
			temp : ARRAY 10 OF CHAR;
		BEGIN
			NEW(s, 128);
			Utilities.Append(s^, "Name : ");
			Utilities.Append(s^, name);
			Utilities.Append(s^, "; Size : ");
			Utilities.IntToStr(size, temp);
			Utilities.Append(s^, temp);
			Utilities.Append(s^, ";");
			RETURN s
		END GetInfoString;

	END EntryInfo;

	(* for internal use only. represent an archive entry *)
	Entry = OBJECT
	VAR
		next : Entry;
		pos : LONGINT; (* pointer to beginning of entry header in tar file *)
		header : Header;

		PROCEDURE & Init;
		BEGIN
			NEW(header)
		END Init;

		PROCEDURE SetName(name : ARRAY OF CHAR);
		VAR i : LONGINT;
		BEGIN
			ASSERT(LEN(name) <= NamSiz);
			FOR i := 0 TO LEN(name)-1 DO header.name[i] := name[i] END
		END SetName;

		PROCEDURE GetName() : ARRAY OF CHAR;
		VAR a : ARRAY EntryNameSize OF CHAR;
		BEGIN
			COPY(header.name, a);
			RETURN a
		END GetName;

		PROCEDURE SetSize(size : LONGINT);
		BEGIN
			IntToOctStr(size, SELF.header.size)
		END SetSize;

		PROCEDURE GetSize() : LONGINT;
		VAR i : LONGINT;
		BEGIN
			OctStrToInt(header.size, i); RETURN i
		END GetSize;

		PROCEDURE Add(e : Entry);
		BEGIN
			IF next # NIL THEN next.Add(e) ELSE next := e END
		END Add;

		PROCEDURE CalculateCheckSum;
		BEGIN
			CalcCheckSum(header)
		END CalculateCheckSum;

	END Entry;

	(* for internal use only. lets read a specified amount of data *)
	SizeReader = OBJECT
	VAR input : AosIO.Reader;
		max : LONGINT;
		archive : Archive;

		PROCEDURE &Init(input: AosIO.Reader; size: LONGINT; archive : Archive);
		BEGIN
			SELF.input := input; SELF.max := size; SELF.archive := archive
		END Init;

		PROCEDURE Receive(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		BEGIN
			IF max = 0 THEN
				res := -1;
				RETURN
			END;
			IF min > max THEN min := max END;
			input.Bytes(buf, ofs, min, len);
			DEC(max, len);
			res := input.res
		END Receive;

	END SizeReader;

	(* for internal use only. abstract buffer class *)
	Buffer = OBJECT

		PROCEDURE Send(VAR data : ARRAY OF CHAR; ofs, len : LONGINT; propagate : BOOLEAN; VAR res : LONGINT);
		BEGIN HALT(301)
		END Send;

	END Buffer;

	(* used by MemoryBuffer *)
	BufferSegment = OBJECT
	VAR buf : POINTER TO ARRAY SegmentSize OF CHAR;
		next : BufferSegment;

		PROCEDURE & Init;
		BEGIN
			NEW(buf)
		END Init;

	END BufferSegment;

	(* infinite memory-data-buffer. Buffers any data sent to 'Send' until propagate is TRUE, then all data is written to 'archive' *)
	MemoryBuffer = OBJECT(Buffer)
	VAR
		first, current : BufferSegment;
		segmentCount, currentIndex : LONGINT;
		archive : Archive;
		name : ARRAY NamSiz OF CHAR;
		closed : BOOLEAN;

		(* parameters :  a: Archive; name: archive entry that will be written to *)
		PROCEDURE & Init(a : Archive; name : ARRAY OF CHAR);
		BEGIN
			archive := a;
			CopyArchiveName(name, SELF.name);
			NEW(first);
			current := first;
			segmentCount := 1;
			currentIndex := 0;
			closed := FALSE
		END Init;

		(* buffer any data until propagate is TRUE *)
		PROCEDURE Send(VAR data : ARRAY OF CHAR; ofs, len : LONGINT; propagate : BOOLEAN; VAR res : LONGINT);
		VAR i : LONGINT;
		BEGIN
			IF closed THEN res := StreamClosed; RETURN END;
			res := AosIO.Ok;
			FOR i := 0 TO len-1 DO
				IF currentIndex = SegmentSize THEN NewSegment() END;
				current.buf[currentIndex] := data[ofs+i];
				INC(currentIndex)
			END;
			IF propagate THEN WriteBuffer(); closed := TRUE END
		END Send;

		(* extend buffer *)
		PROCEDURE NewSegment;
		VAR b : BufferSegment;
		BEGIN
			NEW(b);
			current.next := b;
			current := b;
			INC(segmentCount);
			currentIndex := 0
		END NewSegment;

		(* lock archive for exclusive access and append header::buffer at the end *)
		PROCEDURE WriteBuffer;
		VAR w : AosFS.Writer;
			size : LONGINT;
			e : Entry;
			c : BufferSegment;
		BEGIN
			archive.Acquire;
			size := (segmentCount-1)*SegmentSize + currentIndex;
			archive.RemoveEntry(name);
			NEW(e);
			e.SetName(name);
			e.SetSize(size);
			e.pos := archive.file.Length();
			e.CalculateCheckSum();
			archive.AddEntryNode(e);
			AosFS.OpenWriter(w, archive.file, e.pos);
			(* write header *)
			WriteHeader(w, e.header);
			(* write data *)
			c := first;
			WHILE c # current DO
				w.Bytes(c.buf^, 0, SegmentSize);
				c := c.next
			END;
			w.Bytes(c.buf^, 0, currentIndex);
			(* padding *)
			size := (-size) MOD RecordSize;
			WHILE size > 0 DO w.Char(0X); DEC(size) END;
			w.Update;
			archive.Release
		END WriteBuffer;

	END MemoryBuffer;

	(** tar archive; store a number of files in one archive *)
	Archive* = OBJECT(AosArchives.Archive)
	VAR index : Entry;
		file : AosFS.File;
		lock : WMLocks.RecursiveLock;

		PROCEDURE & Init(f : AosFS.File);
		BEGIN
			f.GetName(name);
			file := f;
			BuildIndex();
			NEW(lock)
		END Init;

		PROCEDURE Acquire*;
		BEGIN {EXCLUSIVE}
			lock.Acquire
		END Acquire;

		PROCEDURE Release*;
		BEGIN {EXCLUSIVE}
			lock.Release
		END Release;

		(** return list of archive entries *)
		PROCEDURE GetIndex*() : AosArchives.Index;
		VAR i : LONGINT;
			e : Entry;
			result : AosArchives.Index;
			ei : EntryInfo;
		BEGIN
			lock.Check;
			i := 0;
			e := index;
			WHILE e # NIL DO INC(i); e := e.next END;
			NEW(result, i);
			i := 0;
			e := index;
			WHILE e # NIL DO
				NEW(ei, e.GetName(), e.GetSize());
				result[i] := ei;
				e := e.next;
				INC(i)
			END;
			RETURN result
		END GetIndex;

		(** get info for a specific entry. return NIL if no such entry exists *)
		PROCEDURE GetEntryInfo*(name : ARRAY OF CHAR) : AosArchives.EntryInfo;
		VAR e : Entry;
			ei : EntryInfo;
		BEGIN
			e := FindEntry(name);
			IF e = NIL THEN RETURN NIL END;
			NEW(ei, e.GetName(), e.GetSize());
			RETURN ei
		END GetEntryInfo;

		(** remove named entry *)
		PROCEDURE RemoveEntry*(name : ARRAY OF CHAR);
		VAR newFile : AosFS.File;
			in : AosFS.Reader;
			out : AosFS.Writer;
			hdr : Header;
			pos, size: LONGINT;
		BEGIN
			lock.Check;
			newFile := AosFS.New(SELF.name);
			AosFS.Register(newFile);
			AosFS.OpenWriter(out, newFile, 0);
			NEW(hdr);
			pos := 0; AosFS.OpenReader(in, file, 0);
			WHILE (in.res = AosIO.Ok) & ReadHeader(in, hdr) DO
				OctStrToInt(hdr.size, size);
				size := size + ((-size) MOD RecordSize); (* entry + padding *)
				IF hdr.name # name THEN
					WriteHeader(out, hdr);
					AosFS.OpenReader(in, file, pos + RecordSize);
					TransferBytes(in, out, size)
				END;
				pos := pos + RecordSize + size;
				AosFS.OpenReader(in, file, pos);
				NEW(hdr)
			END;
			out.Update;
			file := newFile;
			BuildIndex()
		END RemoveEntry;

		(** rename an archive entry. return new EntryInfo or NIL if failed. *)
		PROCEDURE RenameEntry*(from, to : ARRAY OF CHAR) : AosArchives.EntryInfo;
		VAR e : Entry;
			w : AosFS.Writer;
			ei : EntryInfo;
		BEGIN
			lock.Check;
			e := FindEntry(from);
			IF e = NIL THEN RETURN NIL END;
			COPY(to, e.header.name);
			CalcCheckSum(e.header);
			AosFS.OpenWriter(w, file, e.pos);
			WriteHeader(w, e.header);
			w.Update();
			NEW(ei, to, e.GetSize());
			RETURN ei
		END RenameEntry;

		(** open a sender to write an entry with name to archive. the data will be written when Update is called *)
		PROCEDURE OpenSender*(name : ARRAY OF CHAR) : AosIO.Sender;
		VAR buffer : MemoryBuffer;
		BEGIN
			lock.Check;
			ASSERT(name  # "");
			NEW(buffer, SELF, name);
			RETURN buffer.Send
		END OpenSender;

		(** read entry from archive *)
		PROCEDURE OpenReceiver*(name : ARRAY OF CHAR) : AosIO.Receiver;
		VAR r : AosFS.Reader;
			s : SizeReader;
			size : LONGINT;
			entry : Entry;
		BEGIN
			lock.Check;
			entry := FindEntry(name);
			IF entry = NIL THEN RETURN NIL END;
			AosFS.OpenReader(r, file, entry.pos+RecordSize);
			OctStrToInt(entry.header.size, size);
			NEW(s, r, size, SELF);
			RETURN s.Receive
		END OpenReceiver;

		(** save a clone of the archive under a different name *)
		PROCEDURE Copy*(name : ARRAY OF CHAR) : AosArchives.Archive;
		VAR copy : Archive;
			new : AosFS.File;
		BEGIN
			lock.Check;
			new := AosFS.New(name);
			CopyFiles(file, new);
			AosFS.Register(new);
			NEW(copy, new);
			RETURN copy
		END Copy;

		(* ----- internal functions ------------------------------------------------*)

		(* build internal index structure  *)
		PROCEDURE BuildIndex;
		VAR in : AosFS.Reader;
			hdr : Header;
			pos, size : LONGINT;
			e : Entry;
		BEGIN
			index := NIL;
			NEW(hdr);
			pos := 0; AosFS.OpenReader(in, file, 0);
			WHILE (in.res = AosIO.Ok) & ReadHeader(in, hdr) DO
				NEW(e); e.header := hdr;
				AddEntryNode(e);
				OctStrToInt(hdr.size, size);
				e.pos := pos;
				pos := pos + RecordSize + size + ((-size) MOD RecordSize);
				AosFS.OpenReader(in, file, pos);
				NEW(hdr)
			END;
			IF (in.res = AosIO.Ok) & (hdr.chksum # "") THEN
				AosOut.String(hdr.name); AosOut.String("  checksum error"); AosOut.Ln
			END
		END BuildIndex;

		(* return Entry with name, return NIL if not found *)
		PROCEDURE FindEntry(name : ARRAY OF CHAR) : Entry;
		VAR e : Entry;
		BEGIN
			e := index;
			WHILE e # NIL DO
				IF e.header.name = name THEN RETURN e END;
				e := e.next
			END;
			RETURN NIL
		END FindEntry;

		(* for internal use only. add an entry to the archive *)
		PROCEDURE AddEntryNode(e : Entry);
		BEGIN
			IF index = NIL THEN index := e ELSE index.Add(e) END
		END AddEntryNode;

	END Archive;

	(* ----- helpers ---------------------------------------------------------------------- *)

	PROCEDURE ReadHeaderBytes(R: AosIO.Reader; VAR buf: ARRAY OF CHAR; len: LONGINT; VAR chksum: LONGINT);
	VAR i: LONGINT; ch: CHAR;
	BEGIN
		i := 0;
		WHILE i < len DO
			R.Char(ch); buf[i] := ch;
			INC(chksum, ORD(ch)); INC(i)
		END
	END ReadHeaderBytes;

	PROCEDURE ReadHeader(R: AosIO.Reader; VAR hdr: Header): BOOLEAN;
	VAR chksum, chksum2, len: LONGINT;
	BEGIN
		ASSERT(hdr # NIL);
		chksum := 0;
		ReadHeaderBytes(R, hdr.name, NamSiz, chksum);
		ReadHeaderBytes(R, hdr.mode, 8, chksum);
		ReadHeaderBytes(R, hdr.uid, 8, chksum);
		ReadHeaderBytes(R, hdr.gid, 8, chksum);
		ReadHeaderBytes(R, hdr.size, 12, chksum);
		ReadHeaderBytes(R, hdr.mtime, 12, chksum);
		R.Bytes(hdr.chksum, 0, 8, len);
		ReadHeaderBytes(R, hdr.linkflag, 1, chksum);
		ReadHeaderBytes(R, hdr.linkname, NamSiz, chksum);
		ReadHeaderBytes(R, hdr.magic, 8, chksum);
		ReadHeaderBytes(R, hdr.uname, TuNmLen, chksum);
		ReadHeaderBytes(R, hdr.gname, TgNmLen, chksum);
		ReadHeaderBytes(R, hdr.devmajor, 8, chksum);
		ReadHeaderBytes(R, hdr.devminor, 8, chksum);
		INC(chksum, 8*32); OctStrToInt(hdr.chksum, chksum2);
		RETURN chksum = chksum2
	END ReadHeader;

	PROCEDURE Empty(VAR buf: ARRAY OF CHAR; len: LONGINT);
	VAR i: LONGINT;
	BEGIN
		i := 0; WHILE i < len DO buf[i] := 0X; INC(i) END
	END Empty;

	PROCEDURE EmptyHeader(VAR hdr: Header);
	BEGIN
		ASSERT(hdr # NIL);
		Empty(hdr.name, NamSiz);
		Empty(hdr.mode, 8);
		Empty(hdr.uid, 8);
		Empty(hdr.gid, 8);
		Empty(hdr.size, 12);
		Empty(hdr.mtime, 12);
		Empty(hdr.chksum, 8);
		Empty(hdr.linkflag, 1);
		Empty(hdr.linkname, NamSiz);
		Empty(hdr.magic, 8);
		Empty(hdr.uname, TuNmLen);
		Empty(hdr.gname, TgNmLen);
		Empty(hdr.devmajor, 8);
		Empty(hdr.devminor, 8)
	END EmptyHeader;

	PROCEDURE CheckHeaderBytes(VAR buf: ARRAY OF CHAR; len: LONGINT; VAR chksum: LONGINT);
	VAR i: LONGINT;
	BEGIN
		i := 0; WHILE i < len DO INC(chksum, ORD(buf[i])); INC(i) END
	END CheckHeaderBytes;

	PROCEDURE CalcCheckSum(VAR hdr: Header);
	VAR chksum: LONGINT;
	BEGIN
		ASSERT(hdr # NIL);
		CheckHeaderBytes(hdr.name, NamSiz, chksum);
		CheckHeaderBytes(hdr.mode, 8, chksum);
		CheckHeaderBytes(hdr.uid, 8, chksum);
		CheckHeaderBytes(hdr.gid, 8, chksum);
		CheckHeaderBytes(hdr.size, 12, chksum);
		CheckHeaderBytes(hdr.mtime, 12, chksum);
		CheckHeaderBytes(hdr.linkflag, 1, chksum);
		CheckHeaderBytes(hdr.linkname, NamSiz, chksum);
		CheckHeaderBytes(hdr.magic, 8, chksum);
		CheckHeaderBytes(hdr.uname, TuNmLen, chksum);
		CheckHeaderBytes(hdr.gname, TgNmLen, chksum);
		CheckHeaderBytes(hdr.devmajor, 8, chksum);
		CheckHeaderBytes(hdr.devminor, 8, chksum);
		INC(chksum, 8*32);
		IntToOctStr(chksum, hdr.chksum)
	END CalcCheckSum;

	PROCEDURE WriteHeader(W: AosIO.Writer; VAR hdr: Header);
	VAR i: LONGINT;
	BEGIN
		ASSERT(hdr # NIL);
		W.Bytes(hdr.name, 0, NamSiz);
		W.Bytes(hdr.mode, 0, 8);
		W.Bytes(hdr.uid, 0, 8);
		W.Bytes(hdr.gid, 0, 8);
		W.Bytes(hdr.size, 0, 12);
		W.Bytes(hdr.mtime, 0, 12);
		W.Bytes(hdr.chksum, 0, 8);
		W.Bytes(hdr.linkflag, 0, 1);
		W.Bytes(hdr.linkname, 0, NamSiz);
		W.Bytes(hdr.magic, 0, 8);
		W.Bytes(hdr.uname, 0, TuNmLen);
		W.Bytes(hdr.gname, 0, TgNmLen);
		W.Bytes(hdr.devmajor, 0, 8);
		W.Bytes(hdr.devminor, 0, 8);
		i := 345;
		WHILE i < 512 DO
			W.Char(0X); INC(i)
		END
	END WriteHeader;

	PROCEDURE OctStrToInt(VAR str: ARRAY OF CHAR; VAR val: LONGINT);
		VAR i, d: LONGINT; ch: CHAR;
	BEGIN
		i := 0; ch := str[0]; val := 0;
		WHILE (ch = " ") DO
			INC(i); ch := str[i];
		END;
		WHILE (ch >= "0") & (ch <= "7")  DO
			d := ORD(ch) - ORD("0");
			INC(i); ch := str[i];
			IF val <= ((MAX(LONGINT)-d) DIV 8) THEN
				val := 8*val+d
			ELSE
				HALT(99)
			END
		END
	END OctStrToInt;

	PROCEDURE IntToOctStr(val: LONGINT; VAR str: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := LEN(str)-1; str[i] := 0X;
		WHILE i > 0 DO
			DEC(i);
			str[i] := CHR((val MOD 8) + ORD("0"));
			val := val DIV 8
		END
	END IntToOctStr;

	PROCEDURE CopyArchiveName(VAR from, to : ARRAY OF CHAR);
	VAR i : LONGINT;
	BEGIN
		IF LEN(from) < NamSiz THEN i := LEN(from)-1 ELSE i := NamSiz-1 END;
		WHILE i > -1 DO to[i] := from[i]; DEC(i) END
	END CopyArchiveName;

	PROCEDURE Backup(f: AosFS.File);
	VAR old, new: AosFS.FileName; res: LONGINT;
	BEGIN
		f.GetName(old); COPY(old, new);
		Utilities.Append(new, ".Bak");
		AosOut.String("  "); AosOut.String(new); AosOut.Ln();
		AosFS.Rename(old, new, res);
		ASSERT(res = 0)
	END Backup;

	PROCEDURE CopyFiles(VAR from, to : AosFS.File);
	VAR in : AosFS.Reader;
		out : AosFS.Writer;
	BEGIN
		AosFS.OpenReader(in, from, 0);
		AosFS.OpenWriter(out, to, 0);
		TransferBytes(in, out, from.Length());
		out.Update
	END CopyFiles;

	PROCEDURE TransferBytes(from : AosIO.Reader; to : AosIO.Writer; n : LONGINT);
	VAR buf : ARRAY 1024 OF CHAR;
		len : LONGINT;
	BEGIN
		WHILE n > 1024 DO
			from.Bytes(buf, 0, 1024, len);
			to.Bytes(buf, 0, 1024);
			DEC(n, 1024)
		END;
		from.Bytes(buf, 0, n, len);
		to.Bytes(buf, 0, n);
		to.Update()
	END TransferBytes;

	(* ----- api --------------------------------------------------------------------------- *)

	(** open an existing archive. applications should use the method Old in the superclass *)
	PROCEDURE Old*(a: ANY) : ANY;
	VAR archive : Archive;
		file : AosFS.File;
		name : AosArchives.StringObject;
	BEGIN
		ASSERT(a IS AosArchives.StringObject);
		name := a(AosArchives.StringObject);
		file := AosFS.Old(name.value);
		IF file = NIL THEN
			RETURN NIL
		ELSE
			NEW(archive, file);
			RETURN archive
		END
	END Old;

	(** create a new archive, overwrite existing. applications should use the method New in the superclass *)
	PROCEDURE New*(a: ANY) : ANY;
	VAR archive : Archive;
		file : AosFS.File;
		name : AosArchives.StringObject;
	BEGIN
		ASSERT(a IS AosArchives.StringObject);
		name := a(AosArchives.StringObject);
		file := AosFS.New(name.value);
		AosFS.Register(file);
		NEW(archive, file);
		RETURN archive
	END New;

	(* ----- command line tools --------------------------------------------------------------- *)

	PROCEDURE List*(par: ANY): ANY;
	VAR
		fn: AosFS.FileName; F: AosFS.File; R: AosFS.Reader;
		hdr: Header; pos, size: LONGINT;
		sr : AosIO.StringReader;
	BEGIN
		AosCommands.PosPar(par, sr);
		AosCommands.GetTok(sr, fn); F := AosFS.Old(fn);
		IF F = NIL THEN AosOut.String(fn); AosOut.String(" : no such file found."); AosOut.Ln; RETURN NIL END;
		NEW(hdr);
		pos := 0; AosFS.OpenReader(R, F, 0);
		WHILE (R.res = AosIO.Ok) & ReadHeader(R, hdr) DO
			AosOut.String(hdr.name); AosOut.String("  ");
			OctStrToInt(hdr.size, size);
			AosOut.Int(size, 0); AosOut.Ln();
			pos := pos + RecordSize + size + ((-size) MOD RecordSize);
			AosFS.OpenReader(R, F, pos)
		END;
		AosOut.String(hdr.chksum);
		IF (R.res = AosIO.Ok) & (hdr.chksum # "") THEN
			AosOut.String(hdr.name); AosOut.String("  checksum error"); AosOut.Ln()
		END;
		RETURN NIL
	END List;

	PROCEDURE Extract*(par: ANY): ANY;
	VAR
		fn: AosFS.FileName; F, f: AosFS.File; R: AosFS.Reader; w: AosFS.Writer;
		hdr: Header; pos, size, i: LONGINT; ch: CHAR;
		sr : AosIO.StringReader;
	BEGIN
		AosCommands.PosPar(par, sr);
		AosCommands.GetTok(sr, fn);
		F := AosFS.Old(fn);
		IF F = NIL THEN AosOut.String(fn); AosOut.String(" : no such file found."); AosOut.Ln; RETURN NIL END;
		NEW(hdr);
		pos := 0; AosFS.OpenReader(R, F, 0);
		WHILE (R.res = AosIO.Ok) & ReadHeader(R, hdr) DO
			AosOut.String(hdr.name); AosOut.String("  ");
			OctStrToInt(hdr.size, size);
			AosOut.Int(size, 0); AosOut.Ln();
			f := AosFS.Old(hdr.name);
			IF f # NIL THEN Backup(f) END;
			f := AosFS.New(hdr.name); AosFS.OpenWriter(w, f, 0);
			AosFS.OpenReader(R, F, pos + RecordSize);
			i := 0;
			WHILE i < size DO
				R.Char(ch); w.Char(ch); INC(i)
			END;
			w.Update(); AosFS.Register(f);
			pos := pos + RecordSize + size + ((-size) MOD RecordSize);
			AosFS.OpenReader(R, F, pos)
		END;
		IF (R.res = AosIO.Ok) & (hdr.chksum # "") THEN
			AosOut.String(hdr.name); AosOut.String("  checksum error"); AosOut.Ln()
		END;
		RETURN NIL
	END Extract;

	PROCEDURE Create*(par : ANY) : ANY;
	VAR
		fn, archivename: AosFS.FileName; F, f: AosFS.File; W: AosFS.Writer; r: AosFS.Reader;
		hdr: Header; size, i: LONGINT; ch: CHAR;
		sr : AosIO.StringReader;
		nofAdded, nofErrors : LONGINT;
	BEGIN
		AosCommands.PosPar(par, sr);
		AosCommands.GetTok(sr, archivename);
		AosOut.String("Creating "); AosOut.String(archivename); AosOut.Ln;
		F := AosFS.New(archivename); AosFS.OpenWriter(W, F, 0);
		AosCommands.GetTok(sr, fn);
		nofAdded := 0; nofErrors := 0;
		WHILE (sr.res = AosIO.Ok) & (fn # "") DO
			AosOut.String("  adding "); AosOut.String(fn);
			f := AosFS.Old(fn);
			IF f # NIL THEN
				AosFS.OpenReader(r, f, 0); size := f.Length();
				NEW(hdr); COPY(fn, hdr.name);
				IntToOctStr(size, hdr.size);
				CalcCheckSum(hdr);
				WriteHeader(W, hdr);
				i := 0;
				WHILE i < size DO
					r.Char(ch); W.Char(ch); INC(i)
				END;
				size := (-size) MOD RecordSize;
				WHILE size > 0 DO
					W.Char(0X); DEC(size)
				END;
				INC(nofAdded);
			ELSE
				INC(nofErrors);
				AosOut.String(" (error : file not found)")
			END;
			AosOut.Ln;
			AosCommands.GetTok(sr, fn);
		END;
		EmptyHeader(hdr); WriteHeader(W, hdr);
		W.Update(); AosFS.Register(F);
		AosOut.String("Added "); AosOut.Int(nofAdded, 0); AosOut.String(" files to archive ");
		AosOut.String(archivename);
		IF nofErrors > 0 THEN
			AosOut.String(" ("); AosOut.Int(nofErrors, 0); AosOut.String(" errors)"); 
		END;
		AosOut.Ln;
		RETURN NIL
	END Create;

END AosTar.

S.Free AosTar ~
