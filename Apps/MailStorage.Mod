MODULE MailStorage; (** AUTHOR "TF"; PURPOSE "Simple mail storeage"; *)

IMPORT
	AosIO, AosFS, AosOut, Utilities;
	
TYPE IndexEntry* = RECORD
		from, to : LONGINT;
		hFrom, hTo, hSubject, hDate : ARRAY 64 OF CHAR;
	END;
	
TYPE Index = POINTER TO ARRAY OF IndexEntry;	

TYPE Storage* = OBJECT
	VAR 
		storageFile : AosFS.File;
		indexFile : AosFS.File;
		hFrom, hTo, hSubject, hDate : ARRAY 64 OF CHAR;
		nofItems : LONGINT;
		index : Index;
		persistentIndex : BOOLEAN;
		
		PROCEDURE &Init;
		BEGIN
			NEW(index, 1024);
			nofItems := 0
		END Init;
		
		PROCEDURE Open*(storageName, indexName : ARRAY OF CHAR);
		BEGIN
			storageFile := AosFS.Old(storageName);
			persistentIndex := indexName # "";
			IF storageFile = NIL THEN
				storageFile := AosFS.New(storageName);
			ELSE
				indexFile := AosFS.Old(indexName);
				IF indexFile = NIL THEN RebuildIndex 
				ELSE (* LoadIndex *)
				END
			END	
		END Open;
		
		PROCEDURE Match(VAR buf: ARRAY OF CHAR; with: ARRAY OF CHAR; VAR i : LONGINT): BOOLEAN;
		VAR j : LONGINT;
			PROCEDURE MYCAP(c : CHAR) : CHAR;
			BEGIN
				IF ('a' <= c) & (c <= 'z') THEN c := CAP(c) END;
				RETURN c
			END MYCAP;
			
		BEGIN
			i := 0;
			j := 0; WHILE (with[j] # 0X) & (MYCAP(buf[i]) = with[j]) DO INC(i); INC(j) END;
			RETURN with[j] = 0X
		END Match;
		
		PROCEDURE ScanMessage(r : AosIO.Reader; VAR from, to : LONGINT);
		VAR line : ARRAY 1001 OF CHAR; i : LONGINT;
		BEGIN
			hFrom := ""; hTo := ""; hSubject := ""; hDate := "";
			from := r.Pos();
			r.Ln(line);
			REPEAT 
				r.Ln(line);
				IF (hFrom = "") & Match(line, "FROM:", i) THEN Utilities.Delete(line, 0, i); COPY(line, hFrom) 
					;AosOut.String("line = "); AosOut.String(line); 
				ELSIF (hTo = "") & Match(line, "TO:", i) THEN Utilities.Delete(line, 0, i); COPY(line, hTo) 
					;AosOut.String("line = "); AosOut.String(line); 
				ELSIF (hSubject = "") & Match(line, "SUBJECT:", i) THEN Utilities.Delete(line, 0, i); COPY(line, hSubject) 
					;AosOut.String("line = "); AosOut.String(line); 
				ELSIF (hDate = "") & Match(line, "DATE:", i) THEN Utilities.Delete(line, 0, i); COPY(line, hDate) 
					;AosOut.String("line = "); AosOut.String(line); 
				END;
			UNTIL (line = ".") OR (r.res # 0);
			to := r.Pos();
		END ScanMessage;
		
		PROCEDURE ScanStorage(r : AosIO.Reader);
		VAR from, to : LONGINT;
		BEGIN
			nofItems := 0;
			REPEAT
				ScanMessage(r, from, to);
				IF from # to THEN AddIndex(from, to, hFrom, hTo, hSubject, hDate) END
			UNTIL (r.res # 0) OR (from = to)
		END ScanStorage;
		
		PROCEDURE GrowIndex;
		VAR new : Index; i : LONGINT;
		BEGIN
			NEW(new, LEN(index) * 2);
			FOR i := 0 TO nofItems - 1 DO new[i] := index[i] END;
			index := new
		END GrowIndex;
		
		PROCEDURE AddIndex(from, to : LONGINT; hFrom, hTo, hSubject, hDate : ARRAY OF CHAR);
		BEGIN
			IF nofItems = LEN(index) THEN GrowIndex END;
			index[nofItems].from := from;
			index[nofItems].to:= to;
			COPY(hFrom, index[nofItems].hFrom);
			COPY(hTo, index[nofItems].hTo);
			COPY(hSubject, index[nofItems].hSubject);
			COPY(hDate, index[nofItems].hDate);
			INC(nofItems)
		END AddIndex;
		
		PROCEDURE GetCount*(): LONGINT;
		BEGIN
			RETURN nofItems
		END GetCount;
		
		PROCEDURE GetHeader*(nr : LONGINT; VAR hFrom, hTo, hSubject, hDate : ARRAY OF CHAR);
		BEGIN
			IF (nr >= 0) & (nr < nofItems) THEN
				COPY(index[nr].hFrom, hFrom);
				COPY(index[nr].hTo, hTo);
				COPY(index[nr].hSubject, hSubject);
				COPY(index[nr].hDate, hDate);
			END
		END GetHeader;
		
		PROCEDURE ToFile*(nr : LONGINT; filename : ARRAY OF CHAR) : BOOLEAN;
		VAR f : AosFS.File; r : AosFS.Reader; w : AosFS.Writer; str : ARRAY 1001 OF CHAR;
		BEGIN
			IF (nr >= 0) & (nr < nofItems) & (storageFile # NIL) THEN
				f := AosFS.New(filename);
				IF f # NIL THEN AosFS.OpenWriter(w, f, 0)
				ELSE RETURN FALSE
				END;
				AosFS.OpenReader(r, storageFile, index[nr].from);
				REPEAT
					r.Ln(str);
					IF str # "." THEN
						IF str[0] = "." THEN Utilities.Delete(str, 0, 1) END;
						w.String(str); w.Ln;
						AosOut.String(str)
					END	
				UNTIL (str = ".") OR (r.res # 0);			
				w.Update;
				AosFS.Register(f);
				RETURN TRUE
			ELSE RETURN FALSE	
			END
		END ToFile;
		
		PROCEDURE RebuildIndex;
		VAR sr : AosFS.Reader;
		BEGIN
			IF storageFile # NIL THEN
				AosFS.OpenReader(sr, storageFile, 0);
				ScanStorage(sr)
			END
		END RebuildIndex;
		
	END Storage;

PROCEDURE Test*(par : ANY) : ANY;
VAR storage : Storage; i : LONGINT;
BEGIN
	NEW(storage);
	storage.Open("MailMessages", "");
	FOR i := 0 TO storage.nofItems - 1 DO
		AosOut.String("i = "); AosOut.Int(i, 0); AosOut.String(" : "); 
		AosOut.String("storage.index[i].from = "); AosOut.Int(storage.index[i].from, 0);   
		AosOut.String("storage.index[i].to = "); AosOut.Int(storage.index[i].to, 0); AosOut.Ln; 
	END;
	RETURN NIL
END Test;


END MailStorage.

S.Free MailStorage 
MailStorage.Test 

Color Codes
 Highlight
Types and Procedures
Lock Acquire / Lock Release
Preferred notation (comment)
Unsafe / Temporary / Stupid / requires attention
Permanent Comment 
Assertion
Debug

