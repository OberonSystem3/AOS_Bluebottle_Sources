(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE PCM; (** AUTHOR "prk"; PURPOSE "Parallel Compiler: input and output module"; *)
	
IMPORT
		SYSTEM,
		AosOut, AosModules, AosActive, AosIO, AosFS,
		StringPool, PCDebug, Utilities;

	CONST
		(* value of constant NIL *)
		nilval* = 0;
		
		(* target machine minimum values of basic types expressed in host machine format: *)
		MinSInt* = -80H;
		MinInt* = -8000H;
		MinLInt* =  80000000H;	(* i386: -2147483648*)
		
		(* target machine maximum values of basic types expressed in host machine format: *)
		MaxSInt* = 7FH;
		MaxInt* = 7FFFH;
		MaxLInt* = 7FFFFFFFH;	(* i386: 2147483647*)
		MaxSet* = 31;	(* must be >= 15, else the bootstraped compiler cannot run (IN-tests) *)
	
		(* parametrization of numeric scanner: *)
		MaxHDig* = 8;	(* maximal hexadecimal longint length *)
		MaxHHDig* = 16;	(* maximal hexadecimal hugeint length *)
		MaxRExp* = 38;	(* maximal real exponent *)
		MaxLExp* = 308;	(* maximal longreal exponent *)
		
		(** code generator options *)
		ArrayCheck* = 0;		(* x - perform array boundary checks *)
		OverflowCheck* = 1;	(* v - perform overflow check *)
		NilCheck* = 2;			(* N - explicit hard-coded nil checks *)
		TypeCheck*= 3;		(* t - perform type checks *)
		PtrInit* = 5;				(* p - initialize pointers to NIL *)
		AssertCheck* = 6;		(* a - evaluate asserts *)
		Optimize* = 13;
		FullStackInit* = 20;	(* z - clear all values on stack *)

		ExportDefinitions* = 30;
		UseDefinitions* = 31;
		
		(** parser options *)
		NewSF* = 16;				(* s - generation of new symbol file allowed *)
		ExtSF* = 17;				(* e - generation of extended symbol file allowed *)
		Breakpoint* = 18;			(* f - find position in code *)
		CacheImports* = 19; 		(* c - Cache imported modules *)
		NoFiles* = 21;				(* n - don't generate files, parse only*)
		NoOpOverloading* = 22;	(* o - do NOT allow operator overloading *)
		BigEndian* = 23;			(* b - generate big endian code, makes only sense together with ARM backend *)
		Warnings* = 24;				(* W - display warnings *)
		SkipOldSFImport* = 25;		(* S - skip old symbol file import in PCOM.Export, avoids compiler error when migrating to new object file *) (* ug *)

		(** sysflags *)
		Untraced* = 4;	(** global vars + fields - weak pointer *)
		CParam* = 13; (* ejz *)

		(** compiler generated traps *)
		WithTrap* = 1;
		CaseTrap* = 2;
		ReturnTrap* = 3;
		TypeEqualTrap* = 5;
		TypeCheckTrap* = 6;
		IndexCheckTrap* = 7;
		AssertTrap* = 8;
		ArraySizeTrap* = 9;
		

			(** file names and extentions *)
		FileTag = 0BBX;				(* same constants are defined in AosLinker and AosLoader *)
		NoZeroCompress = 0ADX;	(* do. *)
		FileVersion* = 0B1X;			(* do. *)
		
		LocalUnicodeSupport* = TRUE;
		ExportedUnicodeSupport* = FALSE;
		
		InitErrMsgSize = 300;	(* initial size of array of error messages *)
		
	TYPE
		Errors = POINTER TO RECORD
			pos, err: LONGINT;
			msg: ARRAY 64 OF CHAR;
			next: Errors;
		END;
		
		ErrorEntry* = POINTER TO RECORD pos*, err*: LONGINT; msg*: ARRAY 128 OF CHAR; END;
		ErrorList* = OBJECT
			VAR
				act, found, size: LONGINT;
				list: POINTER TO ARRAY OF ErrorEntry;
			
			PROCEDURE &Init*(size: LONGINT);
			BEGIN
				SELF.size := size;
				NEW(list, size);
			END Init;
			
			PROCEDURE Erase;
			VAR i: LONGINT;
			BEGIN
				FOR i := 0 TO size-1 DO
					list[i] := NIL;
				END;
				act := 0; found := 0;
			END Erase;
						
			PROCEDURE HasMoreErrors*(): BOOLEAN;
			BEGIN
				RETURN act < found;
			END HasMoreErrors;
			
			PROCEDURE GetNext*(): ErrorEntry;
			VAR entry: ErrorEntry;
			BEGIN
				IF HasMoreErrors() THEN
					entry := list[act];
					INC(act);
				END;
				RETURN entry;
			END GetNext;
		END ErrorList;
		
		SymReader* = AosFS.Reader;
		
		Rider* = RECORD
			symmodF, symF, objF, refF: AosFS.File;
			symmod, sym, obj, ref: AosFS.Writer;		(*temp modlist, temp symfile, main file*)
		END;
		
		Attribute* = POINTER TO RECORD	END (*AttributeDesc*);
		
		ErrorProc* = PROCEDURE (pos, err: LONGINT; msg: ARRAY OF CHAR);
		ErrorMsgs = POINTER TO ARRAY OF StringPool.Index;
		
	VAR
		bigEndian*: BOOLEAN;

			(** status *)
		codeOptions*, parserOptions*: SET;
		error*: BOOLEAN;		(** actual compilation status *)
		errMsg: ErrorMsgs;	(*error messages*)
		errors: Errors;	(* first element is always empty *)
		
			(** input *)
		breakpc*: LONGINT;	(** code offset to be found or MAX(LONGINT) *) 
		breakpos*: LONGINT;	(** text pos corresponding to breakpc (err 400 pos) *)
		
			(** output *)
		prefix*, suffix*: ARRAY 32 OF CHAR;
			(** procedure to dump (/D option) *)
		dump*: ARRAY 32 OF CHAR;
		
		reportError: ErrorProc;
		log*: AosIO.Writer;

(** ---------- low level functions --------------------- *)

	PROCEDURE GetProcessID*(): LONGINT;
	BEGIN 
		RETURN SYSTEM.VAL(LONGINT, AosActive.ActiveObject())
	END GetProcessID;
	

(** ---------- file IO functions --------------------- *)

	PROCEDURE MakeFileName(VAR file: ARRAY OF CHAR; name, prefix, suffix: ARRAY OF CHAR);
		VAR i, j: LONGINT;
	BEGIN
		i := 0; WHILE prefix[i] # 0X DO  file[i] := prefix[i];  INC(i)  END;
		j := 0; WHILE name[j] # 0X DO  file[i+j] := name[j];  INC(j)  END;
		INC(i, j);
		j := 0; WHILE suffix[j] # 0X DO file[i+j] := suffix[j]; INC(j)  END;
		file[i+j] := 0X;
	END MakeFileName;

	PROCEDURE WriteString(w: AosIO.Writer; VAR s: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN
		i:=0; ch:=s[0];
		WHILE ch # 0X DO
			w.Char(ch); INC(i); ch := s[i];
		END;
		w.Char(0X);
	END WriteString;
	
	(** OpenSymFile - Open a symfile for reading *)

	PROCEDURE OpenSymFile*(name: ARRAY OF CHAR;  VAR r: SymReader;  VAR version: CHAR; VAR zeroCompress: BOOLEAN): BOOLEAN;
		VAR res: BOOLEAN;  file: AosFS.FileName;  f: AosFS.File; dummy: LONGINT; ch: CHAR;
	BEGIN
		res := FALSE; zeroCompress := TRUE;
		MakeFileName(file, name, prefix, suffix);
		f := AosFS.Old(file);
		IF f # NIL THEN
			AosFS.OpenReader(r, f, 0);
			r.Char(ch);
			IF ch = FileTag THEN
				r.Char(version);
				IF version = NoZeroCompress THEN
					zeroCompress := FALSE;
					r.Char(version);
				END;
				r.RawNum(dummy);	(*skip symfile size*)
				res := TRUE
			END
		END;
		RETURN res
	END OpenSymFile;

	PROCEDURE SymW*(VAR R: Rider; ch: CHAR);
	BEGIN  R.sym.Char(ch)  END SymW;
	
	PROCEDURE SymWNum*(VAR R: Rider; i: LONGINT);
	BEGIN  R.sym.RawNum(i)  END SymWNum;
	
	PROCEDURE SymWSet*(VAR R: Rider; s: SET);
	BEGIN  R.sym.RawNum(SYSTEM.VAL(LONGINT, s))  END SymWSet;
	
	PROCEDURE SymWString*(VAR R: Rider; str: ARRAY OF CHAR);
	BEGIN  WriteString(R.sym, str)  END SymWString;
	
	PROCEDURE SymWMod*(VAR R: Rider; str: ARRAY OF CHAR);
	BEGIN  WriteString(R.symmod, str) END SymWMod;
		
	PROCEDURE SymWReal*(VAR R: Rider; r: REAL);
	BEGIN  R.sym.RawReal(r)  END SymWReal;
	
	PROCEDURE SymWLReal*(VAR R: Rider; r: LONGREAL);
	BEGIN  R.sym.RawLReal(r)  END SymWLReal;
	

	PROCEDURE ObjWGetPos*(VAR R: Rider; VAR pos: LONGINT);
	BEGIN pos := R.obj.Pos()
	END ObjWGetPos;

	PROCEDURE ObjW*(VAR R: Rider; ch: CHAR);
	BEGIN  R.obj.Char(ch)
	END ObjW;
	
	PROCEDURE ObjWNum*(VAR R: Rider; i: LONGINT);
	BEGIN R.obj.RawNum(i)
	END ObjWNum;
	
	PROCEDURE ObjWInt*(VAR R: Rider; i: INTEGER);
	BEGIN R.obj.RawInt(i)
	END ObjWInt;
	
	PROCEDURE ObjWIntAt*(VAR R: Rider; pos: LONGINT; i: INTEGER);
		VAR w: AosFS.Writer;
	BEGIN
		R.obj.Update;
		AosFS.OpenWriter(w, R.objF, pos);
		w.RawInt(i);
		w.Update
	END ObjWIntAt;
	
	PROCEDURE ObjWLInt*(VAR R: Rider; i: LONGINT);
	BEGIN R.obj.RawLInt(i)
	END ObjWLInt;
	
	PROCEDURE ObjWLIntAt*(VAR R: Rider; pos: LONGINT; i: LONGINT);
		VAR w: AosFS.Writer;
	BEGIN
		R.obj.Update;
		AosFS.OpenWriter(w, R.objF, pos);
		w.RawLInt(i);
		w.Update
	END ObjWLIntAt;
	
	PROCEDURE ObjWName*(VAR R: Rider; str: ARRAY OF CHAR);
	BEGIN R.obj.RawString(str)
	END ObjWName;
	
	PROCEDURE RefW*(VAR R: Rider; ch: CHAR);
	BEGIN R.ref.Char(ch)
	END RefW;

	PROCEDURE RefWNum*(VAR R: Rider; i: LONGINT);
	BEGIN R.ref.RawNum(i)
	END RefWNum;

	PROCEDURE RefWString*(VAR R: Rider; str: ARRAY OF CHAR);
	BEGIN R.ref.RawString(str)
	END RefWString;

	
	PROCEDURE Open*(name: ARRAY OF CHAR; VAR R: Rider; VAR version: CHAR);
		VAR file: ARRAY 64 OF CHAR; ch: CHAR;
	BEGIN
		MakeFileName(file, name, prefix, suffix);
		R.symmodF := AosFS.New("");
		R.symF := AosFS.New("");
		R.objF := AosFS.New(file);
		R.refF := AosFS.New("");
		AosFS.OpenWriter(R.symmod, R.symmodF, 0);
		AosFS.OpenWriter(R.sym, R.symF, 0);
		AosFS.OpenWriter(R.obj, R.objF, 0);
		AosFS.OpenWriter(R.ref, R.refF, 0);
		R.obj.Char(FileTag);
		R.obj.Char(NoZeroCompress);
		R.obj.Char(version)
	END Open;
	
	PROCEDURE AppendFile(f: AosFS.File;  to: AosIO.Writer);
		VAR buffer: ARRAY 1024 OF CHAR;  r: AosFS.Reader;  read: LONGINT;
	BEGIN
		AosFS.OpenReader(r, f, 0);
		REPEAT
			r.Bytes(buffer, 0, 1024, read);
			to.Bytes(buffer, 0, read)
		UNTIL read # 1024
	END AppendFile;
	
	PROCEDURE CloseSym*(VAR R: Rider);
	BEGIN
		R.symmod.Update;	(* flush buffers to file *)
		R.sym.Update;
(*		IF OldFileFormat THEN
			R.obj.RawNum(R.symmod.sent + R.sym.sent);
		ELSE
			R.obj.RawNum(4 + R.symmod.sent + R.sym.sent);
			R.obj.RawSet(codeOptions)
		END; *)
		R.obj.RawNum(4 + R.symmod.sent + R.sym.sent);
		R.obj.RawSet(codeOptions);		
		AppendFile(R.symmodF, R.obj);
		AppendFile(R.symF, R.obj)
	END CloseSym;
	
	PROCEDURE CloseObj*(VAR R: Rider);
	BEGIN
		R.ref.Update;
		AppendFile(R.refF, R.obj);
		R.obj.Update;
		AosFS.Register(R.objF)
	END CloseObj;

	PROCEDURE RefSize*(VAR R: Rider): LONGINT;
	BEGIN  RETURN R.ref.Pos()
	END RefSize;

	
(** ---------- text output functions --------------------- *)

	PROCEDURE Append(VAR to(** in/out *): ARRAY OF CHAR; this: ARRAY OF CHAR);
		VAR i, j, l: LONGINT;
	BEGIN
		i := 0;
		WHILE to[i] # 0X DO
			INC(i)
		END;
		l := LEN(to)-1; j := 0;
		WHILE (i < l) & (this[j] # 0X) DO
			to[i] := this[j]; INC(i); INC(j)
		END;
		to[i] := 0X
	END Append;

	PROCEDURE FlushErrors*;
		VAR p: Errors; msg, str: ARRAY 128 OF CHAR;
			err: LONGINT;
	BEGIN
		p := errors.next;
		WHILE (p # NIL) DO
			COPY(p.msg, msg);
			IF p.err = 401 THEN
				Append(msg, " is no longer visible")
			ELSIF p.err = 402 THEN
				Append(msg, " is redefined")
			ELSIF p.err = 403 THEN
				Append(msg, " is new")
			ELSIF (p.err >=0) & (errMsg # NIL) & (LEN(errMsg) > p.err) THEN
				err := p.err;
				StringPool.GetString(errMsg[p.err], str);
				Append(msg, "  ");
				Append(msg, str)
			END;
			reportError(p.pos, p.err, msg);
			p := p.next
		END;
		errors.next := NIL
	END FlushErrors;
	
	PROCEDURE MakeErrorList*(l: ErrorList);
		VAR p: Errors; msg, str: ARRAY 128 OF CHAR;
			err: LONGINT;
	BEGIN
		IF l = NIL THEN RETURN END;
		l.Erase;
		p := errors.next;
		WHILE (l.found < l.size) & (p # NIL) DO
			NEW(l.list[l.found]);
			COPY(p.msg, l.list[l.found].msg);
			l.list[l.found].err := p.err;
			l.list[l.found].pos := p.pos;
			
			IF p.err = 401 THEN
				Append(l.list[l.found].msg, " is no longer visible")
			ELSIF p.err = 402 THEN
				Append(l.list[l.found].msg, " is redefined")
			ELSIF p.err = 403 THEN
				Append(l.list[l.found].msg, " is new")
			ELSIF (p.err >=0)  & (errMsg # NIL) & (LEN(errMsg) > p.err) THEN
				StringPool.GetString(errMsg[p.err], str);
				Append(l.list[l.found].msg, "  ");
				Append(l.list[l.found].msg, str)
			END;
			p := p.next;
			INC(l.found);
		END;
		errors.next := NIL
	END MakeErrorList;
	
	PROCEDURE Error* (err, pos: LONGINT;  msg: ARRAY OF CHAR);
		VAR p, q: Errors;
	BEGIN {EXCLUSIVE}
		error := error OR (err <= 400) OR (err >= 404);
		IF err = 400 THEN breakpos := pos END;
		p := errors; q := p.next;
		WHILE (q # NIL) & (q.pos <= pos) DO p := q; q := q.next END;
		IF (pos < 0) OR (p.err = -1) OR (p.pos+10 < pos) THEN
			NEW(q);
			q.pos := pos; q.err := err; COPY(msg, q.msg);
			q.next := p.next; p.next := q
		END;
	END Error;

	PROCEDURE ErrorN* (err, pos: LONGINT; msg: StringPool.Index);
		VAR str: ARRAY 256 OF CHAR;
	BEGIN
		StringPool.GetString(msg, str);
		Error(err, pos, str)
	END ErrorN;
	
	PROCEDURE Warning* (err, pos: LONGINT;  msg: ARRAY OF CHAR);
		VAR p, q: Errors;
	BEGIN {EXCLUSIVE}
		IF ~(Warnings IN parserOptions) THEN RETURN END;
		p := errors; q := p.next;
		WHILE (q # NIL) & (q.pos <= pos) DO p := q; q := q.next END;
		NEW(q);
		q.pos := pos; q.err := err; COPY(msg, q.msg);
		q.next := p.next; p.next := q
	END Warning;
	
	PROCEDURE LogW* (ch: CHAR);
	BEGIN
		IF log = NIL THEN AosOut.Char(ch) ELSE log.Char(ch) END
	END LogW;
	
	PROCEDURE LogWStr* (str: ARRAY OF CHAR);
	BEGIN IF log = NIL THEN AosOut.String(str) ELSE log.String(str) END
	END LogWStr;
	
	PROCEDURE LogWStr0* (str: StringPool.Index);
		VAR str0: ARRAY 256 OF CHAR;
	BEGIN
		StringPool.GetString(str, str0); LogWStr(str0)
	END LogWStr0;
	
	PROCEDURE LogWHex* (i: LONGINT);
	BEGIN IF log = NIL THEN AosOut.Hex(i, 0) ELSE log.Hex(i, 0) END
	END LogWHex;
	
	PROCEDURE LogWNum* (i: LONGINT);
	BEGIN IF log = NIL THEN AosOut.Int(i, 0) ELSE log.Int(i, 0) END
	END LogWNum;
	
	PROCEDURE LogWBool* (b: BOOLEAN);
	BEGIN
		IF b THEN LogWStr("TRUE") ELSE LogWStr("FALSE") END
	END LogWBool;
	
	PROCEDURE LogWType* (p: SYSTEM.PTR);
		VAR name: ARRAY 32 OF CHAR;
	BEGIN
		PCDebug.GetTypeName(p, name); LogWStr(name)
	END LogWType;
	
	PROCEDURE LogWLn*;
	BEGIN IF log = NIL THEN AosOut.Ln ELSE log.Ln END
	END LogWLn;
	
	PROCEDURE LogFlush*;
	BEGIN IF log # NIL THEN log.Update END
	END LogFlush;
	
(** ---------- configuration functions --------------------- *)

	(** Init - Prepare module for a new compilation *)
	
	PROCEDURE Init*(p: ErrorProc);	(* don't assume Reset is executed *)
	BEGIN
		error := FALSE;
		errors.next := NIL;
		PCDebug.ResetToDo;
		reportError := p
	END Init;
	
	(** Reset - allow deallocation of structures*)
	
	PROCEDURE Reset*;
	BEGIN
		errors.next := NIL;
		PCDebug.ResetToDo;
	END Reset;

	(** SetErrorMsg - Set message for error n *)
	
	PROCEDURE SetErrorMsg*(n: LONGINT; VAR msg: ARRAY OF CHAR);
	BEGIN
		IF errMsg = NIL THEN NEW(errMsg, InitErrMsgSize) END;
		WHILE LEN(errMsg^) < n DO Expand(errMsg) END;
		StringPool.GetIndex(msg, errMsg[n])
	END SetErrorMsg;
	
	PROCEDURE Expand(VAR oldAry: ErrorMsgs);
	VAR
		len, i: LONGINT;
		newAry: ErrorMsgs;
	BEGIN
		IF oldAry = NIL THEN RETURN END;
		len := LEN(oldAry^);
		NEW(newAry, len * 2);
		FOR i := 0 TO len-1 DO
			newAry[i] := oldAry[i];
		END;
		oldAry := newAry;
	END Expand;
	
	PROCEDURE InitMod;
	BEGIN
		NEW(errors); errors.pos := MIN(LONGINT);
		PCDebug.ResetToDo
	END InitMod;
	
PROCEDURE SwapBytes*(VAR p: ARRAY OF SYSTEM.BYTE; offset, len: LONGINT);
VAR i: LONGINT;
	tmp: SYSTEM.BYTE;
BEGIN
	FOR i := 0 TO (len-1) DIV 2 DO
		tmp := p[offset+i];
		p[offset+i] := p[offset+len-1-i];
		p[offset+len-1-i] := tmp;
	END;
END SwapBytes;

	PROCEDURE MakeErrorFile*;
	VAR f: AosFS.File; w: AosFS.Writer;
		msg, code: ARRAY 256 OF CHAR; i: LONGINT;
	BEGIN
		f := AosFS.New("Errors2.XML");
		IF f # NIL THEN
			AosFS.OpenWriter(w, f, 0);
			WHILE i < LEN(errMsg)-1 DO
				StringPool.GetString(errMsg[i], msg);
				w.String("    <Error code="); w.Char(CHR(34));
				Utilities.IntToStr(i, code); w.String(code);
				w.Char(CHR(34)); w.String(">");
				w.String(msg);
				w.String("</Error>");
				w.Ln;
				INC(i);
			END;
			w.Update;
			AosFS.Register(f);
		ELSE
			AosOut.String("Could not create file"); AosOut.Ln;
		END;
	END MakeErrorFile;
	
BEGIN
	InitMod;
	prefix := "";
	COPY(AosModules.extension[0], suffix)
END PCM.

(*
	15.11.06	ug	new compiler option /S added, FileVersion incremented
	20.09.03	prk	"/Dcode" compiler option added
	24.06.03	prk	Remove TDMask (no need to mask typedescriptors)
	22.02.02	prk	unicode support
	22.01.02	prk	cosmetic changes, some constants renamed
	22.01.02	prk	ToDo list moved to PCDebug
	18.01.02	prk	AosFS used instead of Files
	10.12.01	prk	ENTIER: rounding mode set to chop, rounding modes caches as globals
	22.11.01	prk	improved flag handling
	19.11.01	prk	definitions
	23.07.01	prk	read error messages into stringpool
	05.07.01	prk	optional explicit NIL checks
	27.06.01	prk	StringPool cleaned up
	14.06.01	prk	type descs for dynamic arrays of ptrs generated by the compiler
	17.05.01	prk	Delegates
	26.04.01	prk	separation of RECORD and OBJECT in the parser
	25.04.01	prk	array allocation: if length < 0 then trap PCM.ArraySizeTrap
	30.03.01	prk	object file version changed to 01X
	29.03.01	prk	Java imports
*)