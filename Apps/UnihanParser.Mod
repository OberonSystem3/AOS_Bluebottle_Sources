MODULE UnihanParser;	(** AUTHOR "tf"; PURPOSE "Parse unihan database of unicode.org"; *)
(* the file Unihan.txt is not included in the release since it should be downloaded directly from
unicode.org

 *)
IMPORT
	AosIO, AosFS, Utilities, UTF8Strings, AosTextUtilities, AosOut;

CONST
	MaxCode = 200000;

TYPE
	String = Utilities.String;
	Character* = OBJECT
	VAR
		radical*, tradvariant*, simpvariant*,
		additionalstrokes*, totalstrokes*, freq*, xfreq* : LONGINT;
		mandarin*, pinyin*, cantonese*, korean*, definition* : String;
	END Character;

TYPE (* generic sortable list *)
	ListElement = POINTER TO RECORD
		next : ListElement;
	END;

	(* return -1, if a < b; 0, if a = b; 1, if a > b *)
	CompareProc = PROCEDURE {DELEGATE} (a, b : ListElement) : LONGINT;

TYPE 
	PIMEEntry = POINTER TO RECORD(ListElement)
		pinyin : ARRAY 8 OF CHAR;
		ucs : LONGINT;
		freq : LONGINT;	
	END;		


VAR
	codeArray : POINTER TO ARRAY OF Character;
	nofLines : LONGINT;
	tok : ARRAY 32 OF CHAR;
	data : ARRAY 256 OF CHAR;
	cap : ARRAY 256 OF CHAR; (* lookup for capital characters *)
	isNum : ARRAY 256 OF BOOLEAN;	
	
PROCEDURE GetHex(r : AosIO.Reader) : LONGINT;
VAR c : CHAR; i, res : LONGINT;
BEGIN
	res := 0;
	c := r.Get();
	WHILE (c >= "0") & (c <= "9") OR (CAP(c) >= "A") & (CAP(c) <= "F") DO
		IF (c >= "0") & (c <= "9") THEN res := res * 16 + (ORD(c)-ORD("0")) 
		ELSE res := res * 16 + (ORD(CAP(c))-ORD("A") + 10)
		END;
		c := r.Get()
	END;
	RETURN res
END GetHex;

PROCEDURE HasCode*(code : LONGINT) : BOOLEAN;
BEGIN
	RETURN (code >= 0) & (code < MaxCode) & (codeArray[code] # NIL)
END HasCode;

(** If not existing, creates the character *)
PROCEDURE GetCharacter*(code : LONGINT) : Character;
BEGIN
	ASSERT( (code >= 0) & (code < MaxCode) );
	IF (codeArray[code] = NIL) THEN NEW(codeArray[code]) END;
	RETURN codeArray[code]
END GetCharacter;

PROCEDURE CountCharacters() : LONGINT;
VAR i, count : LONGINT;
BEGIN
	count := 0;
	FOR i := 0 TO MaxCode - 1 DO IF codeArray[i] # NIL THEN INC(count) END END;
	RETURN count
END CountCharacters;

PROCEDURE ParseLine(r: AosIO.Reader);
VAR code : LONGINT; c : CHAR; char : Character;
BEGIN
	c := r.Get();
	IF c = "U" THEN
		r.SkipBytes(1);
		code := GetHex(r);
		char := GetCharacter(code);
		r.SkipWhitespace;
		r.Token(tok);
		r.SkipWhitespace;
		IF tok = "kDefinition" THEN
			r.Ln(data);
			char.definition := Utilities.NewString(data)
		ELSIF tok = "kMandarin" THEN	
			r.Ln(data);
			char.mandarin := Utilities.NewString(data)
		ELSIF tok = "kFrequency" THEN	
			(* r.SkipWhitespace; r.Int(char.freq, FALSE); r.SkipLn; *)
		ELSIF tok = "kCantonese" THEN	
			r.Ln(data);
			char.cantonese := Utilities.NewString(data)
		ELSIF tok = "kKorean" THEN	
			r.Ln(data);
			char.korean := Utilities.NewString(data)
		ELSIF tok = "kSimplifiedVariant" THEN	
			r.Ln(data);
		ELSIF tok = "kTraditionalVariant" THEN	
			r.Ln(data);
		ELSE r.SkipLn;	
		END
	ELSE r.SkipLn;
	END;
	INC(nofLines);
	IF nofLines MOD 50000 = 0 THEN AosOut.Int(nofLines, 5); AosOut.String(" lines and counting..."); AosOut.Ln END; 
END ParseLine;

PROCEDURE AddRadicals;
VAR f : AosFS.File; r : AosFS.Reader;
	code, count : LONGINT; char : Character;
BEGIN
	f := AosFS.Old("Radicals.txt");
	IF f # NIL THEN
		AosOut.String("Adding radical info..."); AosOut.Ln;
		AosFS.OpenReader(r, f, 0);			
		count := 0;
		WHILE r.res = 0 DO 
			IF ~AosTextUtilities.GetUTF8Char(r, code) THEN HALT(1234) END; r.SkipWhitespace;
			char := GetCharacter(code);
			IF ~AosTextUtilities.GetUTF8Char(r, char.radical) THEN HALT(1234) END; r.SkipWhitespace;
			r.Ln(data);
			char.pinyin := Utilities.NewString(data);
			INC(count)
		END;
		AosOut.String("Radical info to "); AosOut.Int(count, 4); AosOut.String(" characters added."); AosOut.Ln	
	ELSE
		AosOut.String("Could not find radicals.txt"); AosOut.Ln	
	END	
END AddRadicals;

PROCEDURE AddFrequencies;
VAR f : AosFS.File; r : AosFS.Reader;
	code, count, i : LONGINT; char : Character;
BEGIN
	f := AosFS.Old("frequencies.txt");
	IF f # NIL THEN
		AosOut.String("Adding frequency info..."); AosOut.Ln;
		count := 0;
		AosFS.OpenReader(r, f, 0);			
		(* input is sorted list of characters, most frequent on top *)
		WHILE r.res = 0 DO 
			r.SkipLn; INC(count)
		END;

		AosFS.OpenReader(r, f, 0);
		i := 0;			
		WHILE r.res = 0 DO 
			IF ~AosTextUtilities.GetUTF8Char(r, code) THEN HALT(1234) END; r.SkipWhitespace;
			char := GetCharacter(code);
			char.xfreq := ENTIER(99 * i / count) + 1;
			r.SkipLn;
			INC(i)
		END;

		(* rescale the unicode frequencies to frequency numbers found above *)
		FOR i := 0 TO MaxCode - 1 DO 
			IF codeArray[i] # NIL THEN 
				IF (codeArray[i].xfreq = 0) & (codeArray[i].freq # 0) THEN
					codeArray[i].xfreq := (codeArray[i].freq - 1) * 20
				END
			END 
		END;
		
		
		AosOut.String("Frequency info added to "); AosOut.Int(count, 4); AosOut.String(" characters."); AosOut.Ln	
	ELSE
		AosOut.String("Could not find frequencies.txt"); AosOut.Ln	
	END	
END AddFrequencies;

PROCEDURE ParseFile*(par : PTR) : PTR;
VAR f : AosFS.File; r : AosFS.Reader;
BEGIN
	f := AosFS.Old("Unihan.txt");
	IF f # NIL THEN
		AosFS.OpenReader(r, f, 0);			
		WHILE r.res = 0 DO ParseLine(r) END;
		AosOut.Int(nofLines, 5); AosOut.String(" lines processed."); AosOut.Ln;
		AosOut.Int(CountCharacters(), 5); AosOut.String(" unique characters"); AosOut.Ln;
		AddRadicals;
		AddFrequencies
	ELSE AosOut.String("Unihan.txt not found"); AosOut.Ln
	END;
	RETURN NIL
END ParseFile;

(** Merge-sort a single-linked list. The root element is a dummy node *)
(* Algorithm by Simon Tatham *)
PROCEDURE Sort(root: ListElement; compare : CompareProc);	(* root is dummy node *)
VAR m, n, np, nq: LONGINT; p, q, tail: ListElement;
BEGIN
	n := 1;
	REPEAT
		p := root.next; q := p; tail := root; m := 0;
		WHILE p # NIL DO	(* merge sorted lists of length n into sorted lists of length 2*n (sort of) *)
			np := 0;	(* step q over <= n nodes *)
			REPEAT q := q.next; INC(np) UNTIL (q = NIL) OR (np = n);
			nq := n; INC(m);
			LOOP	(* merge list p with np nodes and list q with <= nq nodes at end of tail *)
				IF (np # 0) & ((nq = 0) OR (q = NIL) OR (compare(p, q) <= 0)) THEN
					tail.next := p; tail := p; p := p.next; DEC(np)
				ELSIF (nq # 0) & (q # NIL) THEN
					tail.next := q; tail := q; q := q.next; DEC(nq)
				ELSE	(* (np = 0) & ((nq = 0) OR (q = NIL)) *)
					EXIT
				END
			END;
			tail.next := NIL; p := q
		END;
		n := n*2
	UNTIL m <= 1
END Sort;

PROCEDURE ComparePinyinFreq(a, b: ListElement) : LONGINT;
BEGIN
	IF a(PIMEEntry).pinyin < b(PIMEEntry).pinyin THEN RETURN -1 END;
	IF a(PIMEEntry).pinyin > b(PIMEEntry).pinyin THEN RETURN 1 END;
	(* equals *)
	IF a(PIMEEntry).freq > b(PIMEEntry).freq THEN RETURN -1 END;
	IF a(PIMEEntry).freq < b(PIMEEntry).freq THEN RETURN 1 END;
	RETURN 0 
END ComparePinyinFreq;

	
PROCEDURE BuildBasicPinyinIMETable*(par : ANY) : ANY;
VAR i, words : LONGINT;
	list : ListElement; (* first element is dummy for sort *)
	cur : ListElement;
	str : ARRAY 16 OF CHAR;
	f : AosFS.File;
	w : AosFS.Writer;

	PROCEDURE AddEntry(pinyin : ARRAY OF CHAR; code, freq : LONGINT);
	VAR e : PIMEEntry; 
	BEGIN
		NEW(e);
		INC(words);
		COPY(pinyin, e.pinyin); e.ucs := code; e.freq := freq; e.next := list.next;
		list.next := e
	END AddEntry;
	
	
	PROCEDURE FixBugs(pinyin : ARRAY OF CHAR; code, freq : LONGINT);
	VAR i, l : LONGINT; t : ARRAY 100 OF CHAR;
	BEGIN
		Utilities.Trim(pinyin, " ");
		
		(* workaround some bugs in the Unihan table *)
		l := Utilities.Length(pinyin);
		i := 1; WHILE i < l DO
			IF (isNum[ORD(pinyin[i])]) & (pinyin[i + 1] # 0X) THEN
				Utilities.Copy(pinyin, 0, i + 1, t);
				AddEntry(t, code, freq);
				Utilities.Delete(pinyin, 0, i + 1); 
				i := 1; l := Utilities.Length(pinyin);
			ELSE INC(i)
			END
		END;
		IF pinyin # "" THEN 
			AddEntry(pinyin, code, freq)
		END	
	END FixBugs;
	
	PROCEDURE DumpChar(i : LONGINT; c : Character);
	VAR p, t : ARRAY 256 OF CHAR;
	BEGIN
		IF c.mandarin = NIL THEN 
			AosOut.String("unexpected :  no mandarininfo "); AosOut.String("i = "); AosOut.Int(i, 0); AosOut.Ln;
			RETURN
		END;
		COPY(c.mandarin^, p);
		Utilities.Trim(p, " ");
		WHILE Utilities.Length(p) > 1 DO
			IF Utilities.Pos(" ", p) >= 0 THEN
				Utilities.Copy(p, 0, Utilities.Pos(" ", p), t);
				FixBugs(t, i, c.xfreq);
				Utilities.Delete(p, 0, Utilities.Pos(" ", p));
				Utilities.Trim(p, " ");
			ELSE
				FixBugs(p, i, c.xfreq);
				p := ""
			END
		END
	END DumpChar;
	
BEGIN
	NEW(list);
	words := 0;
	AosOut.String("creating list..."); 
	FOR i := 0 TO MaxCode - 1 DO 
		IF codeArray[i] # NIL THEN 
			IF codeArray[i].xfreq > 0 THEN
				DumpChar(i, codeArray[i])
			END
		END 
	END;
	AosOut.String("done."); AosOut.Ln; 
	AosOut.String("sorting");
	Sort(list, ComparePinyinFreq);
	AosOut.String("done."); AosOut.Ln; 
	AosOut.String("Writing PinyinIMETable.txt"); 
	
	
	f := AosFS.New("PinyinIMETable.txt");
	AosFS.OpenWriter(w, f, 0);
	w.Int(words, 0); w.Ln;
	
	cur := list.next;
	WHILE cur # NIL DO
		w.String(cur(PIMEEntry).pinyin); w.Char(09X);
		i := 0; IF UTF8Strings.EncodeChar(cur(PIMEEntry).ucs, str, i) THEN END;
		w.String(str); w.Char(09X);
		w.Int(cur(PIMEEntry).freq, 0);
		w.Ln;
		INC(words);
		cur := cur.next
	END;
	w.Update;
	AosFS.Register(f);	
	AosOut.String("done."); AosOut.Ln; 
	RETURN NIL
END BuildBasicPinyinIMETable;
	
PROCEDURE InitLookup;
VAR i : LONGINT;
BEGIN
	(* to captial conversion table *)
	FOR i := 0 TO 255 DO cap[i] := CHR(i) END;
	FOR i := ORD("a") TO ORD("z") DO cap[i] := CHR(i - 32) END;
	(* number lookup *)
	FOR i := 0 TO 255 DO isNum[i] := FALSE END;
	FOR i := ORD("0") TO ORD("9") DO isNum[i] := TRUE END;
END InitLookup;

BEGIN
	InitLookup;
	NEW(codeArray, MaxCode);
	IF ParseFile(NIL) = NIL THEN END
END UnihanParser.

S.Free UnihanParser ~
UnihanParser.ParseFile ~
PET.Open PinyinIMETable.txt 

UnihanParser.BuildBasicPinyinIMETable ;