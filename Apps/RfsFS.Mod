(* Patrick Stuedi, 30.08.01 *)

 MODULE RfsFS; (** AUTHOR "pstuedi"; PURPOSE "Remote File System"; *)

IMPORT SYSTEM, AosModules, AosClock, AosFS, RfsClientProxy, AosOut;

CONST	
	BufSize = RfsClientProxy.Payload;		
	MaxBufs = 2;	
	FnLength = 32;	(* includes 0X *)
	EnumRegular = 0;
	EnumDetail = 1;
	Ok = RfsClientProxy.REPLYOK;
	Trace = 0;
	
TYPE
	DiskSector = RECORD END;	(* Oberon Sector, size SS *)
	FileName = ARRAY FnLength OF CHAR;

	DataSector = RECORD (DiskSector)
		B: ARRAY BufSize OF CHAR
	END;

	Buffer* = POINTER TO RECORD (AosFS.Hint)
		apos*, lim*: LONGINT;
		mod: BOOLEAN;
		next: Buffer;
		data*: DataSector
	END;
	
TYPE
	(** Interface from AosFS. One of the three Interfaces (Filesystem, File and Volume) which have to be implemented **)
	FileSystem* = OBJECT (AosFS.FileSystem)	(* Rfs file system type *)
		VAR stubs: RfsClientProxy.Proxy;
		
		(** Creates a new file with the specified name **)
		PROCEDURE New0*(name: ARRAY OF CHAR): AosFS.File;
		VAR 
			res: LONGINT; 
			f: File; 
			buf: Buffer; 
			namebuf, nameTemp: FileName;
			hashval, errorcode: LONGINT;
		BEGIN {EXCLUSIVE}
			f := NIL; 												
			Check(name, namebuf, res);							
			IF res <= 0 THEN
				FillBuf(nameTemp, 0X);
				stubs.CreateTmp(nameTemp, hashval, errorcode);
				IF errorcode = Ok THEN
					NEW(buf); 
					buf.apos := 0; 
					buf.mod := TRUE; 
					buf.lim := 0;
					buf.next := buf;
					NEW(f); 
					f.fs := SELF; 
					f.key := hashval; 
					f.aleng := 0; 
					f.bleng := 0; 
					f.modH := TRUE;
					f.firstbuf := buf; 
					f.nofbufs := 1; 
					f.name := namebuf; 
					f.nameTemp := nameTemp;
					AosClock.Get(f.time, f.date);
					f.registered := (f.name[0] = 0X);
				END;
			END;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("New0->name:");
				AosOut.String(name);
				AosOut.String(", res:");
				AosOut.Int(res, 1);
				AosOut.Exit;
			END;
			
			RETURN f
		END New0;

		(** opens an existing File **)
		PROCEDURE Old0*(name: ARRAY OF CHAR): AosFS.File;
		VAR
			res: LONGINT; 
			f: File; 
			buf: Buffer; 
			namebuf: FileName; 
			hashval, errorcode, fileLen, time, date: LONGINT;
		BEGIN {EXCLUSIVE}
			f := NIL; 
			Check(name, namebuf, res);
			IF res = 0 THEN
				stubs.Lookup(namebuf, hashval, errorcode);
				IF (errorcode =  Ok) & (hashval # 0) THEN
					NEW(buf); 
					NEW(f);
					f.key := hashval;
					f.fs := SELF;
					stubs.GetAttr(hashval, fileLen, time, date, errorcode);
					f.aleng := fileLen DIV BufSize;
					f.bleng := fileLen MOD BufSize;
					ReadBuf(f, buf, 0, errorcode);
					IF errorcode # Ok THEN
						RETURN NIL;
					END;					
					buf.next := buf; 
					buf.mod := FALSE;
					buf.apos := 0;
					IF f.aleng = 0 THEN 
						buf.lim := f.bleng; 
					ELSE 
						buf.lim := BufSize;
					END;
					f.firstbuf := buf; 
					f.nofbufs := 1;
					f.name := namebuf; 
					f.time := time;
					f.date := date;
					f.registered := TRUE;
				END;
			END;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Old0->name:");
				AosOut.String(name);
				AosOut.String(", res:");
				AosOut.Int(res, 1);
				AosOut.Exit;
			END;

			RETURN f
		END Old0;
		
		(** deletes a file, res = 0 indicates succsess **)
		PROCEDURE Delete0*(name: ARRAY OF CHAR; VAR key, res: LONGINT);
		VAR namebuf: FileName; errorcode: LONGINT;
		BEGIN {EXCLUSIVE}
			Check(name, namebuf, res);
			IF res = 0 THEN
				stubs.Remove(namebuf, errorcode);
				IF errorcode = Ok THEN
					res := 0;
				ELSE
					res := 2;
				END;
				key := 1;
			ELSE
				key := 0
			END;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Delete0->name:");
				AosOut.String(name);
				AosOut.String(", key:");
				AosOut.Int(key, 1);
				AosOut.String(", res:");
				AosOut.Int(res, 1);
				AosOut.Exit;
			END;		
		END Delete0;
	
		(** renames a file. res = 0 indicates success **)
		PROCEDURE Rename0*(old, new: ARRAY OF CHAR; f: AosFS.File; VAR res: LONGINT);
		VAR oldbuf, newbuf: FileName; errorcode: LONGINT;
		BEGIN {EXCLUSIVE}
			Check(old, oldbuf, res);
			IF res = 0 THEN
				Check(new, newbuf, res);
				IF res = 0 THEN
					IF f # NIL THEN
						stubs.Rename(oldbuf, newbuf, errorcode);
						IF errorcode # Ok THEN
							res := 2;
						END;
					ELSE
						res := 2;
					END;
				END;
			END;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Rename0->old:");
				AosOut.String(old);
				AosOut.String(", new:");
				AosOut.String(new);
				AosOut.String(", res:");
				AosOut.Int(res, 1);
				AosOut.Exit;
			END;
		END Rename0;

		(** enumerates the contents of a directory **)		
		PROCEDURE Enumerate0*(mask: ARRAY OF CHAR; flags: SET; enum: AosFS.Enumerator);
		VAR fnTmp, fn: ARRAY AosFS.PrefixLength+FnLength OF CHAR; dir: RfsClientProxy.Dir; 
				errorcode, cookie, endOfDir, helper, time, date, size, detail: LONGINT;
		BEGIN {EXCLUSIVE}			
			fn := ".";
			cookie := 0;		
			helper := 0;
			IF (AosFS.EnumTime IN flags)  OR (AosFS.EnumSize IN flags) THEN
				detail := EnumDetail;
			ELSE
				detail := EnumRegular;
			END;
			NEW(dir);
		
			WHILE helper = 0 DO
				stubs.ReadDir(fn, mask, detail, cookie, dir, endOfDir, errorcode);
				IF errorcode = Ok THEN
					WHILE (dir.nbrOfEntrys > 0) & (dir.first # NIL) DO
						dir.Get(fnTmp, time, date, size);
						AosFS.JoinName(prefix, fnTmp, fn);
						enum.PutEntry(fn, {}, time, date, size);			
					END;
					cookie := dir.nbrOfEntrys;
					helper := endOfDir;
				ELSE
					helper := 1;
				END;
			END;	
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Enumerate0->mask:");
				AosOut.String(mask);
				AosOut.Exit;
			END;							
		END Enumerate0;

		(** return an unique id for a file registered in the filesystem **)
		PROCEDURE FileKey*(name: ARRAY OF CHAR): LONGINT;
			VAR 
				res: LONGINT; 
				namebuf: FileName; 
				hashval, errorcode: LONGINT;
		BEGIN {EXCLUSIVE}
			hashval := 0;
			Check(name, namebuf, res);
			IF res = 0 THEN
				stubs.Lookup(namebuf, hashval, errorcode);
			END;

			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("FileKey->name:");
				AosOut.String(name);
				AosOut.String(", filekey:");
				AosOut.Int(hashval, 1);
				AosOut.Exit;
			END;		
			
			RETURN hashval;
		END FileKey;
		
		PROCEDURE &RfsInit(vol: RfsClientProxy.Proxy);
		BEGIN
			SELF.stubs := vol;
		END RfsInit;

		PROCEDURE Finalize;
			VAR errorcode: LONGINT;
		BEGIN {EXCLUSIVE}
			stubs.Unmount(errorcode);
			Finalize^;	(* see note in AosFS *)
		END Finalize;

	END FileSystem;

TYPE
	File* = OBJECT (AosFS.File)
		VAR
			aleng, bleng: LONGINT;
			nofbufs: LONGINT;
			modH, registered: BOOLEAN;
			firstbuf*: Buffer;
			name*, nameTemp*: FileName;
			time, date: LONGINT;
		
		(** positions a rider on a file at a given position. Riders cannot be positioned past the end of a file **)	
		PROCEDURE Set*(VAR r: AosFS.Rider; pos: LONGINT);
		VAR a, b: LONGINT;
		BEGIN {EXCLUSIVE}
			r.eof := FALSE; 
			r.res := 0; 
			r.file := SELF; 
			r.fs := fs;
			IF pos < 0 THEN
				a := 0; b := 0;
			ELSIF pos < aleng*BufSize + bleng THEN
				a := pos DIV BufSize; 
				b := pos MOD BufSize;
			ELSE
				a := aleng; 
				b := bleng;
			END;
			r.apos := a; 
			r.bpos := b; 
			r.hint := firstbuf;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Set->pos:");
				AosOut.Int(pos, 1);
				AosOut.Exit;
			END;
		END Set;
		
		(** return the current position of a rider **)
		PROCEDURE Pos*(VAR r: AosFS.Rider): LONGINT;
		BEGIN {}
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Pos->pos:");
				AosOut.Int(r.apos*BufSize + r.bpos, 1);
				AosOut.Exit;
			END;			

			RETURN r.apos*BufSize + r.bpos;		
		END Pos;

		(** reads one byte from a file **)
		PROCEDURE Read*(VAR r: AosFS.Rider; VAR x: CHAR);
		VAR buf: Buffer; errorcode: LONGINT;
		BEGIN {EXCLUSIVE}
			buf := r.hint(Buffer);
			IF r.apos # buf.apos THEN 
				buf := GetBuf(SELF, r.apos); 
				r.hint := buf; 
			END;
			IF r.bpos < buf.lim THEN
				x := buf.data.B[r.bpos]; 
				INC(r.bpos);
			ELSIF r.apos < aleng THEN
				INC(r.apos);
				buf := SearchBuf(SELF, r.apos);
				IF buf = NIL THEN
					buf := r.hint(Buffer);
					IF buf.mod THEN 
						WriteBuf(SELF, buf, errorcode); 
					END ;
						ReadBuf(SELF, buf, r.apos, errorcode);
				ELSE
					r.hint := buf;
				END;
				IF buf.lim > 0 THEN
					x := buf.data.B[0]; 
					r.bpos := 1;
				ELSE
					x := 0X; 
					r.eof := TRUE;
				END;
			ELSE
				x := 0X; r.eof := TRUE
			END;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Read->x:");
				AosOut.Char(x);
				AosOut.Exit;
			END;
		END Read;
		
		(** read len bytes from a file. **)
		PROCEDURE ReadBytes*(VAR r: AosFS.Rider; VAR x: ARRAY OF CHAR; ofs, len: LONGINT);
		VAR src, dst, m, errorcode: LONGINT; buf: Buffer;
		BEGIN {EXCLUSIVE}
			IF LEN(x)-ofs < len THEN 
				SYSTEM.HALT(19);
			END;
			IF len > 0 THEN
				dst := SYSTEM.ADR(x[ofs]);
				buf := r.hint(Buffer);
				IF r.apos # buf.apos THEN 
					buf := GetBuf(SELF, r.apos); r.hint := buf; 
				END;
				LOOP
					IF len <= 0 THEN 
						EXIT; 
					END ;
					src := SYSTEM.ADR(buf.data.B[0]) + r.bpos; 
					m := r.bpos + len;
					IF m <= buf.lim THEN
						SYSTEM.MOVE(src, dst, len); 
						r.bpos := m; 
						r.res := 0; 
						EXIT;
					ELSIF buf.lim = BufSize THEN
						m := buf.lim - r.bpos;
						IF m > 0 THEN 
							SYSTEM.MOVE(src, dst, m); 
							INC(dst, m); 
							DEC(len, m) 
						END;
						IF r.apos < aleng THEN
							INC(r.apos); 
							r.bpos := 0; 
							buf := SearchBuf(SELF, r.apos);
							IF buf = NIL THEN
								buf := r.hint(Buffer);
								IF buf.mod THEN 
									WriteBuf(SELF, buf, errorcode) 
								END;
								ReadBuf(SELF, buf, r.apos, errorcode);
							ELSE
								r.hint := buf;
							END;
						ELSE
							r.bpos := buf.lim; 
							r.res := len; 
							r.eof := TRUE; 
							EXIT;
						END
					ELSE
						m := buf.lim - r.bpos;
						IF m > 0 THEN 
							SYSTEM.MOVE(src, dst, m); 
							r.bpos := buf.lim; 
						END;
						r.res := len - m; r.eof := TRUE; EXIT
					END;
				END;
			ELSE
				r.res := 0
			END;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("ReadBytes->ofs:");
				AosOut.Int(ofs, 1);
				AosOut.String(", len:");
				AosOut.Int(len, 1);
				AosOut.Exit;
			END;
		END ReadBytes;
		
		(** writes one byte into a file **)
		PROCEDURE Write*(VAR r: AosFS.Rider; x: CHAR);
		VAR buf: Buffer; errorcode: LONGINT;
		BEGIN {EXCLUSIVE}
			buf := r.hint(Buffer);
			IF r.apos # buf.apos THEN 
				buf := GetBuf(SELF, r.apos); 
				r.hint := buf 
			END;
			IF r.bpos >= buf.lim THEN
				IF r.bpos < BufSize THEN
					INC(buf.lim); 
					INC(bleng); 
					modH := TRUE;
				ELSE
					WriteBuf(SELF, buf, errorcode); 
					INC(r.apos); 
					buf := SearchBuf(SELF, r.apos);
					IF buf = NIL THEN
						buf := r.hint(Buffer);
						IF r.apos <= aleng THEN
							ReadBuf(SELF, buf, r.apos, errorcode)
						ELSE
							buf.apos := r.apos; 
							buf.lim := 1; 
							INC(aleng); 
							bleng := 1; 
							modH := TRUE;
						END
					ELSE
						r.hint := buf;
					END;
					r.bpos := 0
				END
			END;
			buf.data.B[r.bpos] := x; 
			INC(r.bpos); 
			buf.mod := TRUE;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Write->x:");
				AosOut.Char(x);
				AosOut.Exit;
			END;
		END Write;

		(** write len bytes into a file **)
		PROCEDURE WriteBytes*(VAR r: AosFS.Rider; VAR x: ARRAY OF CHAR; ofs, len: LONGINT);
		VAR src, dst, m, errorcode: LONGINT; buf: Buffer; 
		BEGIN {EXCLUSIVE}
			IF LEN(x)-ofs < len THEN 
				SYSTEM.HALT(19); 
			END;
			IF len > 0 THEN
				src := SYSTEM.ADR(x[ofs]);
				buf := r.hint(Buffer);
				IF r.apos # buf.apos THEN 
					buf := GetBuf(SELF, r.apos); 
					r.hint := buf 
				END;
				LOOP
					IF len <= 0 THEN 
						EXIT; 
					END;
					buf.mod := TRUE; 
					dst := SYSTEM.ADR(buf.data.B[0]) + r.bpos; 
					m := r.bpos + len;
					IF m <= buf.lim THEN
						SYSTEM.MOVE(src, dst, len); 
						r.bpos := m; 
						EXIT;
					ELSIF m <= BufSize THEN
						SYSTEM.MOVE(src, dst, len); 
						r.bpos := m;
						bleng := m; 
						buf.lim := m; 
						modH := TRUE; 
						EXIT
					ELSE
						m := BufSize - r.bpos;
						IF m > 0 THEN 
							SYSTEM.MOVE(src, dst, m); 
							buf.lim := BufSize;
							INC(src, m); 
							DEC(len, m); 
						END;
						WriteBuf(SELF, buf, errorcode); 
						INC(r.apos); 
						r.bpos := 0; 
						buf := SearchBuf(SELF, r.apos);
						IF buf = NIL THEN
							buf := r.hint(Buffer);
							IF r.apos <= aleng THEN 
								ReadBuf(SELF, buf, r.apos, errorcode)
							ELSE
								buf.apos := r.apos; 
								buf.lim := 0; 
								INC(aleng); 
								bleng := 0; 
								modH := TRUE;
								(*
								IF (aleng - STS) MOD XS = 0 THEN 
									NewSub(SELF) 
								END
								*)
							END
						ELSE
							r.hint := buf
						END
					END
				END
			END;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("WriteBytes->ofs:");
				AosOut.Int(ofs, 1);
				AosOut.String(", len:");
				AosOut.Int(len, 1);
				AosOut.Exit;
			END;
		END WriteBytes;

		(** return the lenght of a file **)
		PROCEDURE Length*(): LONGINT;
		BEGIN {EXCLUSIVE}
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Length->size:");
				AosOut.Int(aleng*BufSize + bleng, 1);
				AosOut.Exit;
			END;		
		
			RETURN aleng*BufSize + bleng;
		END Length;
		
		(** returns the last modified of a file **)
		PROCEDURE GetDate*(VAR t, d: LONGINT);
		BEGIN {EXCLUSIVE}
			t := time; 
			d := date;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("GetDate->time:");
				AosOut.Int(time, 1);
				AosOut.String(", date:");
				AosOut.Int(date, 1);
				AosOut.Exit;
			END;

		END GetDate;
		
		(** sets the write-timestamp of file **)
		PROCEDURE SetDate*(t, d: LONGINT);
			VAR errorcode: LONGINT; fsCasted: FileSystem;
		BEGIN {EXCLUSIVE}
			time := t; 
			date := d;
			fsCasted := SELF.fs(FileSystem);
			fsCasted.stubs.SetAttr(name, time, date, errorcode);
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("SetDate->time:");
				AosOut.Int(time, 1);
				AosOut.String(", date:");
				AosOut.Int(date, 1);
				AosOut.Exit;
			END;
		END SetDate;

		(** return the name of a file **)
		PROCEDURE GetName*(VAR name: ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			AosFS.JoinName(fs.prefix, SELF.name, name);
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("GetName->name:");
				AosOut.String(name);
				AosOut.Exit;
			END;
		END GetName;		
		
		(** registers a file in the filesystem **)		
		PROCEDURE Register0*(VAR res: LONGINT);
		VAR
			buf: Buffer;	
			errorcode: LONGINT;
			fsCasted : FileSystem;
		BEGIN
			IF ~registered & (name # "") THEN
				fsCasted := SELF.fs(FileSystem);
				fsCasted.stubs.Rename(nameTemp, name, errorcode);
				IF errorcode = Ok THEN
					registered := TRUE; 
					res := 0;
				ELSE
					res := 1;
				END;
			ELSE
				res := 1;
			END;
			buf := firstbuf;
			REPEAT
				IF buf.mod THEN WriteBuf(SELF, buf, errorcode) END;
				buf := buf.next;
			UNTIL buf = firstbuf;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Register->res:");
				AosOut.Int(res, 1);
				AosOut.Exit;
			END;
		END Register0;					
		
				
		PROCEDURE Update*;
			VAR buf: Buffer; errorcode: LONGINT;
		BEGIN {EXCLUSIVE}
			buf := firstbuf;
			REPEAT
				IF buf.mod THEN WriteBuf(SELF, buf, errorcode) END;
				buf := buf.next;
			UNTIL buf = firstbuf;
			
			IF Trace = 1 THEN
				AosOut.Enter;
				AosOut.String("Update");
				AosOut.Exit;
			END;
		END Update;

	END File;


(* Check a file name. *)


VAR newfs*: FileSystem;


PROCEDURE Check(VAR s: ARRAY OF CHAR; VAR name: FileName; VAR res: LONGINT);
	VAR i: LONGINT; ch: CHAR;
BEGIN
	ch := s[0]; i := 0;
	IF ch = "/" THEN
		res := 3;
	ELSIF ("A" <= CAP(ch)) & (CAP(ch) <= "Z") THEN
		LOOP name[i] := ch; INC(i); ch := s[i];
			IF (ch = ".") & (name[i-1] = ".") THEN
				res := 3;
				EXIT;
			ELSIF ch = 0X THEN
				WHILE i < FnLength DO name[i] := 0X; INC(i) END ;
				res := 0; EXIT
			END ;
			IF ~(("A" <= CAP(ch)) & (CAP(ch) <= "Z")
				OR ("0" <= ch) & (ch <= "9") OR (ch = ".")) THEN res := 3; EXIT
			END ;
			IF i = FnLength-1 THEN res := 4; EXIT END
		END
	ELSIF ch = 0X THEN name[0] := 0X; res := -1
	ELSE res := 3
	END
END Check;

(*
PROCEDURE CheckTmp(VAR s: ARRAY OF CHAR; VAR name: FileName; VAR res: LONGINT);
	VAR i: LONGINT; ch: CHAR;
BEGIN
	s[6] := 0X;
	AosOut.String("CheckTMP : ");
	AosOut.String(s);
	AosOut.Ln;
	ch := s[0]; i := 0;
	IF (ch # ".") THEN  
		AosOut.String("tmpfile");
		AosOut.Ln;
		res := 3;
	ELSE
		ch := s[1]; i := 1;
		AosOut.String("step1..");
		AosOut.Ln;
		IF ("A" <= CAP(ch)) & (CAP(ch) <= "Z") THEN
			AosOut.String("step2..");
			AosOut.Ln;
			LOOP name[i] := ch; INC(i); ch := s[i];
				AosOut.String("step3..");
				AosOut.Ln;
				IF ch = 0X THEN
					AosOut.String("step4..");
					AosOut.Ln;
					WHILE i < FnLength DO 
						AosOut.String("step4..");
						AosOut.Ln;
						name[i] := 0X; INC(i) 
					END ;
					res := 0; EXIT
				END ;
				IF ~(("A" <= CAP(ch)) & (CAP(ch) <= "Z")
					OR ("0" <= ch) & (ch <= "9") OR (ch = ".")) THEN res := 3; EXIT
				END ;
				IF i = FnLength-1 THEN res := 4; EXIT END
			END
		ELSIF ch = 0X THEN name[0] := 0X; res := -1
		ELSE res := 3
		END
	END;
END CheckTmp;
*)


(** Read Buf - reads a buffer from a file f into buf **)
PROCEDURE ReadBuf(f: File; buf: Buffer; pos: LONGINT; VAR errorcode: LONGINT);
VAR fsCasted: FileSystem; received: LONGINT;
BEGIN
	fsCasted := f.fs(FileSystem);
	fsCasted.stubs.Read(f.key, pos*BufSize, BufSize, buf.data.B, 0, received, errorcode);	
	IF errorcode = Ok THEN
		IF pos < f.aleng THEN
			buf.lim := received;
		ELSE
			buf.lim := f.bleng;
		END;
		buf.apos := pos; 
		buf.mod := FALSE;
	ELSIF errorcode = RfsClientProxy.CACHEMISS THEN
		IF Trace = 1 THEN
			AosOut.Enter;
			AosOut.String("ReadBuf->errorcode: ");
			AosOut.Int(errorcode, 1);
			AosOut.Exit;
		END;
		IF ~f.registered THEN
			fsCasted.stubs.Lookup(f.nameTemp, f.key, errorcode);
		ELSE
			fsCasted.stubs.Lookup(f.name, f.key, errorcode);
		END;
		fsCasted.stubs.Read(f.key, pos*BufSize, BufSize, buf.data.B, 0, received, errorcode);	
		IF errorcode = Ok THEN
			IF pos < f.aleng THEN
				buf.lim := received;
			ELSE
				buf.lim := f.bleng;
			END;
			buf.apos := pos; 
			buf.mod := FALSE;
		END;
	END;
END ReadBuf;

(** WriteBuf - writes a buffer buf into a file f **)
PROCEDURE WriteBuf(f: File; buf: Buffer; VAR errorcode: LONGINT);
VAR fsCasted: FileSystem; written: LONGINT;
BEGIN
	f.modH := TRUE;
	fsCasted := f.fs(FileSystem);
	fsCasted.stubs.Write(f.key, buf.apos*BufSize, buf.lim, buf.data.B, written, errorcode);
	IF errorcode = Ok THEN
		buf.mod := FALSE;
	ELSIF errorcode = RfsClientProxy.CACHEMISS THEN
		IF Trace = 1 THEN
			AosOut.Enter;
			AosOut.String("WriteBuf->errorcode: ");
			AosOut.Int(errorcode, 1);
			AosOut.Exit;
		END;
		IF ~f.registered THEN
			fsCasted.stubs.Lookup(f.nameTemp, f.key, errorcode);
		ELSE
			fsCasted.stubs.Lookup(f.name, f.key, errorcode);
		END;
		fsCasted.stubs.Write(f.key, buf.apos*BufSize, buf.lim, buf.data.B, written, errorcode);	
		IF errorcode = Ok THEN
			buf.mod := FALSE;
		END;
	END;
END WriteBuf;

PROCEDURE SearchBuf(f: File; pos: LONGINT): Buffer;
VAR buf: Buffer;
BEGIN
	buf := f.firstbuf;
	LOOP
		IF buf.apos = pos THEN EXIT END;
		buf := buf.next;
		IF buf = f.firstbuf THEN buf := NIL; EXIT END
	END;
	RETURN buf
END SearchBuf;

PROCEDURE GetBuf(f: File; pos: LONGINT): Buffer;
VAR buf: Buffer; errorcode: LONGINT;
BEGIN
	buf := f.firstbuf;
	LOOP
		IF buf.apos = pos THEN EXIT END;
		IF buf.next = f.firstbuf THEN
			IF f.nofbufs < MaxBufs THEN (* allocate new buffer *)
				NEW(buf); buf.next := f.firstbuf.next; f.firstbuf.next := buf;
				INC(f.nofbufs)
			ELSE (* take one of the buffers *)
				f.firstbuf := buf;
				IF buf.mod THEN WriteBuf(f, buf, errorcode) END
			END;
			buf.apos := pos;
			IF pos <= f.aleng THEN ReadBuf(f, buf, pos, errorcode) END;
			EXIT
		END;
		buf := buf.next
	END;
	RETURN buf
END GetBuf;


(** Generate a new file system object.  AosFS.NewVol has volume parameter, AosFS.Par has mount prefix. *)
PROCEDURE NewFS*(par: PTR): PTR;
VAR vol: RfsClientProxy.Proxy; p: AosFS.Parameters;
BEGIN
	p := par(AosFS.Parameters); vol := p.vol(RfsClientProxy.Proxy);
	IF vol # NIL THEN
		NEW(newfs, vol);
		newfs.desc := "Remote File System";
		AosFS.Add(newfs, p.prefix);
		AosOut.String("FS->");
		AosOut.String(p.prefix);
		AosOut.String(" added");
		AosOut.Ln
	ELSE
		AosOut.String("FS");
		AosOut.String("RfsFS: Failure");
		AosOut.Ln
	END;			
	p.str[0] := 0X;	(* no error message *)
	RETURN NIL
END NewFS;
	
PROCEDURE FillBuf(VAR x: ARRAY OF CHAR; ch: CHAR);
	VAR len, i: LONGINT;
BEGIN
	len := LEN(x);
	FOR i := 0 TO len-1 DO
		x[i] := ch;
	END;
END FillBuf;



(* Clean up when module unloaded. *)

PROCEDURE Cleanup;
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
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	newfs := NIL;
END RfsFS.

(*
	aleng * BufSize + bleng = length of File
	apos * BufSize + bpos = current position
	0 <= bpos <= lim <= BufSize
	0 <= apos <= aleng 
	(apos < aleng) & (lim = BufSize) OR (apos = aleng)
	
	Methods with {} notation are explicitly unprotected.  They must be called only from a protected context.
*)
