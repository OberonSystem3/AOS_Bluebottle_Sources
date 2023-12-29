(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE PCS; (** AUTHOR "prk"; PURPOSE "Parallel Compiler: scanner"; *)
	
	IMPORT
		SYSTEM, AosIO, AosFS, AosOut,
		AosTexts, UTF8Strings, Utilities,
		StringPool, PCM;
	
	CONST
		Trace = FALSE;
	
		MaxStrLen* = 256;
		MaxIdLen = 32;
	
	TYPE
		Name* = StringPool.Index;
		String* = ARRAY MaxStrLen OF CHAR;
		
		Buffer = POINTER TO ARRAY OF CHAR;

		Token* = SHORTINT;
		
	CONST
		Eot* = 0X;
		ObjectMarker = 020X;
	
		(* numtyp values *)
		char* = 1; integer* = 2; longinteger* = 3; real* = 4; longreal* = 5;
(*	Oberon-1
	ProgTools.Enum 0 *
		null
		times slash div mod and 
		plus minus or eql neq  lss leq gtr geq in is 
		arrow period comma
		colon upto rparen rbrak rbrace
		of then do to by
		lparen lbrak lbrace
		not
		becomes
		number nil true false string
		ident semicolon bar end else
		elsif until if case while
		repeat for loop with exit passivate return
		refines implements
		array definition object record pointer begin code
		const type var procedure import
		module eof
		~
	
	OberonX
	ProgTools.Enum 0 *
		null
		
		times times0 times1 times2 times3 times4 times5 times6 times7
		slash slash0 slash1 slash2 slash3 slash4 slash5 slash6 slash7
		div mod and 
		
		plus plus0 plus1 plus2 plus3 plus4 plus5 plus6 plus7
		minus minus0 minus1 minus2 minus3 minus4 minus5 minus6 minus7 
		or 
		
		eql neq  lss leq gtr geq in is 
		
		arrow period comma
		colon upto rparen rbrak rbrace
		of then do to by
		lparen lbrak lbrace
		not percent backslash
		becomes
		number nil self true false string
		ident semicolon bar end else
		elsif until if case while
		repeat for loop with exit passivate
		return array record pointer begin code
		const type var procedure import
		module eof
		~
	
*)
	null* =   0; times* =   1; slash* =   2; div* =   3; mod* =   4; and* =   5; 
	plus* =   6; minus* =   7; or* =   8; eql* =   9; neq* =  10; lss* =  11; 
	leq* =  12; gtr* =  13; geq* =  14; in* =  15; is* =  16; arrow* =  17; 
	period* =  18; comma* =  19; colon* =  20; upto* =  21; rparen* =  22; 
	rbrak* =  23; rbrace* =  24; of* =  25; then* =  26; do* =  27; to* =  28; 
	by* =  29; lparen* =  30; lbrak* =  31; lbrace* =  32; not* =  33; 
	becomes* =  34; number* =  35; nil* =  36; true* =  37; false* =  38; 
	string* =  39; ident* =  40; semicolon* =  41; bar* =  42; end* =  43; 
	else* =  44; elsif* =  45; until* =  46; if* =  47; case* =  48; while* =  49; 
	repeat* =  50; for* =  51; loop* =  52; with* =  53; exit* =  54; 
	passivate* =  55; return* =  56; refines* =  57; implements* =  58; 
	array* =  59; definition* =  60; object* =  61; record* =  62; pointer* =  63; 
	begin* =  64; code* =  65; const* =  66; type* =  67; var* =  68; 
	procedure* =  69; import* =  70; module* =  71; eof* =  72; 
		
VAR
	opTable: ARRAY 73 OF Name;
	reservedChar-, newChar: ARRAY 256 OF BOOLEAN;
			
TYPE
	Scanner* = OBJECT
		VAR
			buffer: Buffer;
			pos: LONGINT;	(*pos in buffer*)
			ch-: CHAR;	(**look-ahead *)
			name-: Name;
			str-: String;
			numtyp-: INTEGER; (* 1 = char, 2 = integer, 3 = real, 4 = longreal *)
			intval-: LONGINT;	(* integer value or string length *)
			longintval-: HUGEINT;
			realval-: REAL;
			lrlval-: LONGREAL;
			numStartPos, numEndPos: LONGINT;
			curpos-, errpos-: LONGINT;	(*pos in text*)
			isNummer: BOOLEAN;
	
		PROCEDURE err(n: INTEGER);
		BEGIN PCM.Error(n, errpos, "")
		END err;
		
		PROCEDURE NextChar*;
		BEGIN
			(*REPEAT*)
				IF pos < LEN(buffer) THEN
					ch := buffer[pos]; INC(pos)
				ELSE
					ch := Eot
				END;
			(*UNTIL (ch # ObjectMarker);*)
			
			IF newChar[ORD(ch)] THEN INC(curpos) END; (* curpos := pos; *)
		END NextChar;
		
		PROCEDURE Str(VAR sym: SHORTINT);
			VAR i: INTEGER; och: CHAR;
		BEGIN i := 0; och := ch;
			LOOP NextChar;
				IF ch = och THEN EXIT END ;
				IF ch < " " THEN err(3); EXIT END ;
				IF i = MaxStrLen-1 THEN err(241); EXIT END ;
				str[i] := ch; INC(i)
			END ;
			NextChar; str[i] := 0X; intval := i + 1;
			IF intval = 2 THEN
				sym := number; numtyp := 1; intval := ORD(str[0])
			ELSE sym := string
			END
		END Str;
	
		PROCEDURE Identifier(VAR sym: SHORTINT);
			VAR i: LONGINT;
		BEGIN i := 0;
			REPEAT
				str[i] := ch; INC(i); NextChar
			(* UNTIL (ch < "0") OR ("9" < ch) & (CAP(ch) < "A") OR ("Z" < CAP(ch)) OR (i = MaxIdLen); *)
			UNTIL reservedChar[ORD(ch)] OR (i = MaxIdLen);
			IF i = MaxIdLen THEN err(240); DEC(i) END ;
			str[i] := 0X; sym := ident;
				(* temporary code! delete when moving to ANY and adapt PCT *)
			IF str = "ANY" THEN COPY("PTR", str) END;
		END Identifier;
	
		PROCEDURE Number;
		VAR i, m, n, d, e: INTEGER; dig: ARRAY 24 OF CHAR; f: LONGREAL; expCh: CHAR; neg, long: BOOLEAN;

			PROCEDURE Ten(e: INTEGER): LONGREAL;
				VAR x, p: LONGREAL;
			BEGIN x := 1; p := 10;
				WHILE e > 0 DO
					IF ODD(e) THEN x := x*p END;
					e := e DIV 2;
					IF e > 0 THEN p := p*p END (* prevent overflow *)
				END;
				RETURN x
			END Ten;
	
			PROCEDURE Ord(ch: CHAR; hex: BOOLEAN): INTEGER;
			BEGIN (* ("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F") *)
				IF ch <= "9" THEN RETURN ORD(ch) - ORD("0")
				ELSIF hex THEN RETURN ORD(ch) - ORD("A") + 10
				ELSE err(2); RETURN 0
				END
			END Ord;
			
		BEGIN (* ("0" <= ch) & (ch <= "9") *)
			i := 0; m := 0; n := 0; d := 0; long := FALSE;
			LOOP (* read mantissa *)
				IF ("0" <= ch) & (ch <= "9") OR (d = 0) & ("A" <= ch) & (ch <= "F") THEN
					IF (m > 0) OR (ch # "0") THEN (* ignore leading zeros *)
						IF n < LEN(dig) THEN dig[n] := ch; INC(n) END;
						INC(m)
					END;
					NextChar; INC(i)
				ELSIF ch = "." THEN NextChar;
					IF ch = "." THEN (* ellipsis *) ch := 7FX; EXIT
					ELSIF d = 0 THEN (* i > 0 *) d := i
					ELSE err(2)
					END
				ELSE EXIT
				END
			END; (* 0 <= n <= m <= i, 0 <= d <= i *)
			IF d = 0 THEN (* integer *)
				IF n = m THEN intval := 0; i := 0;
(* > bootstrap 1 *)
					longintval := 0;
(* < bootstrap 1 *)
					IF ch = "X" THEN (* character *) NextChar; numtyp := char;
						IF PCM.LocalUnicodeSupport & (n <= 8) THEN
							IF (n = 8) & (dig[0] > "7") THEN (* prevent overflow *) intval := -1 END;
							WHILE i < n DO intval := intval*10H + Ord(dig[i], TRUE); INC(i) END
						ELSIF ~PCM.LocalUnicodeSupport & (n <= 2) THEN
							WHILE i < n DO intval := intval*10H + Ord(dig[i], TRUE); INC(i) END
						ELSE err(203)
						END
					ELSIF ch = "H" THEN (* hexadecimal *) NextChar;
						IF n <= PCM.MaxHDig THEN
							numtyp := integer;
							IF (n = PCM.MaxHDig) & (dig[0] > "7") THEN (* prevent overflow *) intval := -1 END;
							WHILE i < n DO intval := intval*10H + Ord(dig[i], TRUE); INC(i) END
(* > bootstrap 1 *)
						ELSIF n <= PCM.MaxHHDig THEN
							numtyp := longinteger;
							IF (n = PCM.MaxHHDig) & (dig[0] > "7") THEN (* prevent overflow *) longintval := -1 END;
							WHILE i < n DO longintval := Ord(dig[i], TRUE) + longintval*10H; INC(i) END
(* < bootstrap 1 *)
						ELSE err(203)
						END
					ELSE (* decimal *) numtyp := integer;
						WHILE i < n DO d := Ord(dig[i], FALSE); INC(i);
							IF intval <= (MAX(LONGINT) - d) DIV 10 THEN intval := intval*10 + d
(* > bootstrap 2
							ELSE err(203)
< bootstrap 2 *)
(* > bootstrap 1 *)
							ELSE long := TRUE
(* < bootstrap 1 *)
							END
						END;
(* > bootstrap 1 *)
						IF long THEN
							numtyp := longinteger; longintval := LONG(intval)*10+d;
							WHILE i < n DO d := Ord(dig[i], FALSE); INC(i);
								IF longintval*10+d >= 0 THEN longintval := longintval*10 + d
								ELSE err(203)
								END
							END
						END
(* < bootstrap 1 *)
					END
				ELSE err(203)
				END
			ELSE (* fraction *)
				f := 0; e := 0; expCh := "E";
				WHILE n > 0 DO (* 0 <= f < 1 *) DEC(n); f := (Ord(dig[n], FALSE) + f)/10 END;
				IF (ch = "E") OR (ch = "D") THEN expCh := ch; NextChar; neg := FALSE;
					IF ch = "-" THEN neg := TRUE; NextChar
					ELSIF ch = "+" THEN NextChar
					END;
					IF ("0" <= ch) & (ch <= "9") THEN
						REPEAT n := Ord(ch, FALSE); NextChar;
							IF e <= (MAX(INTEGER) - n) DIV 10 THEN e := e*10 + n
							ELSE err(203)
							END
						UNTIL (ch < "0") OR ("9" < ch);
						IF neg THEN e := -e END
					ELSE err(2)
					END
				END;
				DEC(e, i-d-m); (* decimal point shift *)
				IF expCh = "E" THEN numtyp := real;
					IF (1-PCM.MaxRExp < e) & (e <= PCM.MaxRExp) THEN
						IF e < 0 THEN realval := SHORT(f / Ten(-e))
						ELSE realval := SHORT(f * Ten(e))
						END
					ELSE err(203)
					END
				ELSE numtyp := longreal;
					IF (1-PCM.MaxLExp < e) & (e <= PCM.MaxLExp) THEN
						IF e < 0 THEN lrlval := f / Ten(-e)
						ELSE lrlval := f * Ten(e)
						END
					ELSE err(203)
					END
				END
			END
		END Number;
	
		PROCEDURE GetNumAsString*(VAR val: ARRAY OF CHAR);
		VAR i, l: LONGINT;
		BEGIN
			(*Utilities.Copy(buffer^, numStartPos, numEndPos-numStartPos, val);*)
			IF isNummer THEN
				i := 0; l := LEN(val)-1;
				WHILE (i < numEndPos-numStartPos) & (i < l) DO
					val[i] := buffer[numStartPos + i];
					INC(i);
				END;
			END;
			val[i] := 0X
		END GetNumAsString;

		PROCEDURE Get*(VAR s: SHORTINT);
	
			PROCEDURE Comment;	(* do not read after end of file *)
				VAR dump: BOOLEAN;
			BEGIN NextChar;
				IF ch = "#" THEN dump := TRUE; PCM.LogWLn END;	(* implementation-specific feature *)
				LOOP
					LOOP
						WHILE ch = "(" DO NextChar;
							IF ch = "*" THEN Comment ELSIF dump THEN PCM.LogW ("(") END
						END ;
						IF ch = "*" THEN NextChar; EXIT END ;
						IF ch = Eot THEN EXIT END ;
						IF dump THEN PCM.LogW (ch) END;
						NextChar
					END ;
					IF ch = ")" THEN NextChar; EXIT END ;
					IF dump THEN PCM.LogW ("*") END;
					IF ch = Eot THEN err(5); EXIT END
				END
			END Comment;

		BEGIN
			REPEAT
				WHILE ch <= " " DO (*ignore control characters*)
					IF ch = Eot THEN
						IF Trace THEN
							PCM.LogWLn; PCM.LogWStr("Scan ");
							PCM.LogWNum((*curpos*)pos); 			(*reader version*)
							PCM.LogWHex(eof)
						END;
						s := eof; RETURN
					ELSE NextChar
					END
				END ;
				(* errpos := (*curpos*)pos-1;			(*reader version*) *)
				errpos := curpos - 1;
				isNummer := FALSE;
				CASE ch OF   (* ch > " " *)
					| 22X, 27X  : Str(s)
					| "#"  : s := neq; NextChar
					| "&"  : s :=  and; NextChar
					| "("  : NextChar;
									 IF ch = "*" THEN Comment; (*GlobalGet; RETURN*) s := -1;		(*allow recursion without reentrancy*)
										 ELSE s := lparen
									 END
					| ")"  : s := rparen; NextChar
					| "*"  : s:=times; NextChar
					| "+"  : s :=  plus; NextChar
					| ","  : s := comma; NextChar
					| "-"  : s :=  minus; NextChar
					| "."  : NextChar;
									 IF ch = "." THEN NextChar; s := upto ELSE s := period END
					| "/"  : s :=  slash; NextChar
					| "0".."9": isNummer := TRUE; numStartPos := pos-1; Number; numEndPos := pos-1; s := number
					| ":"  : NextChar;
									 IF ch = "=" THEN NextChar; s := becomes ELSE s := colon END
					| ";"  : s := semicolon; NextChar
					| "<"  : NextChar;
									 IF ch = "=" THEN NextChar; s := leq; ELSE s := lss; END
					| "="  : s :=  eql; NextChar
					| ">"  : NextChar;
									 IF ch = "=" THEN NextChar; s := geq; ELSE s := gtr; END
					| "A": Identifier(s);
								IF str = "ARRAY" THEN s := array
								ELSIF str = "AWAIT" THEN s := passivate
								END
					| "B": Identifier(s);
								IF str = "BEGIN" THEN s := begin
								ELSIF str = "BY" THEN s := by
								END
					| "C": Identifier(s);
								IF str = "CONST" THEN s := const
								ELSIF str = "CASE" THEN s := case
								ELSIF str = "CODE" THEN s := code
								END
					| "D": Identifier(s);
								IF str = "DO" THEN s := do
								ELSIF str = "DIV" THEN s := div
								ELSIF str = "DEFINITION" THEN s := definition
								END
					| "E": Identifier(s);
								IF str = "END" THEN s := end
								ELSIF str = "ELSE" THEN s := else
								ELSIF str = "ELSIF" THEN s := elsif
								ELSIF str = "EXIT" THEN s := exit
								END
					| "F": Identifier(s);
								IF str = "FALSE" THEN s := false
								ELSIF str = "FOR" THEN s := for
								END
					| "I": Identifier(s);
								IF str = "IF" THEN s := if
								ELSIF str = "IN" THEN s := in
								ELSIF str = "IS" THEN s := is
								ELSIF str = "IMPORT" THEN s := import
								ELSIF str = "IMPLEMENTS" THEN s := implements
								END
					| "L": Identifier(s);
								IF str = "LOOP" THEN s := loop END
					| "M": Identifier(s);
								IF str = "MOD" THEN s := mod
								ELSIF str = "MODULE" THEN s := module
								END
					| "N": Identifier(s);
								IF str = "NIL" THEN s := nil END
					| "O": Identifier(s);
								IF str = "OR" THEN s := or
								ELSIF str = "OF" THEN s := of
								ELSIF str = "OBJECT" THEN s := object
								END
					| "P": Identifier(s);
								IF str = "PROCEDURE" THEN s := procedure
								ELSIF str = "POINTER" THEN s := pointer
								END
					| "R": Identifier(s);
								IF str = "RECORD" THEN s := record
								ELSIF str = "REPEAT" THEN s := repeat
								ELSIF str = "RETURN" THEN s := return
								ELSIF str = "REFINES" THEN s := refines
								END
					| "T": Identifier(s);
								IF str = "THEN" THEN s := then
								ELSIF str = "TRUE" THEN s := true
								ELSIF str = "TO" THEN s := to
								ELSIF str = "TYPE" THEN s := type
								END
					| "U": Identifier(s);
								IF str = "UNTIL" THEN s := until END
					| "V": Identifier(s);
								IF str = "VAR" THEN s := var END
					| "W": Identifier(s);
								IF str = "WHILE" THEN s := while
								ELSIF str = "WITH" THEN s := with
								END
					| "G".."H", "J", "K", "Q", "S", "X".."Z": Identifier(s)
					| "["  : s := lbrak; NextChar
					| "]"  : s := rbrak; NextChar
					| "^"  : s := arrow; NextChar
					| "a".."z": Identifier(s)
					| "{"  : s := lbrace; NextChar
					| "|"  : s := bar; NextChar
					| "}"  : s := rbrace; NextChar
					| "~"  : s := not; NextChar
					| 7FX  : s := upto; NextChar 
				ELSE  Identifier(s); (* s := null; NextChar; *)
				END ;
			UNTIL s >= 0;
			
			IF s = ident THEN StringPool.GetIndex(str, name) END;
			
			IF Trace THEN
				PCM.LogWLn; PCM.LogWStr("Scan "); 
				PCM.LogWNum(errpos); PCM.LogWHex(s); 
			END;
		END Get;
	
		PROCEDURE IsOperatorValid*(): BOOLEAN;
		VAR
			op: ARRAY 3 OF CHAR;
			ch0, ch1, ch2: CHAR;
		BEGIN
			COPY(str, op);
			ch0 := op[0]; ch1 := op[1]; ch2 := op[2];
			CASE str[0] OF
			| "=", "#", "&": IF ch1 = 0X THEN RETURN TRUE END
			| "<", ">": IF (ch1 = 0X) OR ((ch1 = "=") & (ch2 = 0X)) THEN RETURN TRUE END	(* <, <=, >, >= *)
			| "I": IF (ch1 = "N") & (ch2 = 0X) THEN RETURN TRUE END	(* IN *)
			| "D": IF str="DIV" THEN RETURN TRUE END	(* DIV *)
			| "M": IF str="MOD" THEN RETURN TRUE END	(* MOD *)
			| "O": IF str="OR" THEN RETURN TRUE END	(* OR *)
			| "+", "-", "*", "/" : IF (ch1=0X) (* OR ((ch2=0X) & (ch1="*")) *) THEN RETURN TRUE END;
			| "~": IF (ch1=0X) THEN RETURN TRUE END;
			| ":": IF str=":=" THEN RETURN TRUE END;
			END;
			RETURN FALSE;
		END IsOperatorValid;
	
	END Scanner;

	PROCEDURE GetOpName*(op: SHORTINT; VAR name: Name);
	BEGIN
		name := opTable[op];
	END GetOpName;
	
	(** Create a new scanner at the same position *)
	PROCEDURE ForkScanner* (s: Scanner): Scanner;
	VAR t: Scanner;
	BEGIN 
		NEW(t);
		t^ := s^;
		RETURN t
	END ForkScanner;
(*	
	PROCEDURE SaveBuffer(b: Buffer);
		VAR f: AosFS.File; r: AosFS.Rider;
	BEGIN
		f := AosFS.New("SillyFile.bin");
		f.Set(r, 0);
		f.WriteBytes(r, b^, 0, LEN(b^));
		AosFS.Register(f);
	END SaveBuffer;
*)
	PROCEDURE NewScanner(b: Buffer;  pos: LONGINT): Scanner;
	VAR s: Scanner;
	BEGIN
(*
		SaveBuffer(b);
*)
		NEW(s);
		s.buffer := b;
		s.pos := pos;
		s.ch := " ";
		RETURN s
	END NewScanner;
	
	PROCEDURE InitWithText*(t: AosTexts.Text; pos: LONGINT): Scanner;
		VAR buffer: Buffer; len, i, j, ch: LONGINT; r: AosTexts.TextReader;
		bytesPerChar: LONGINT;
	BEGIN
		t.AcquireRead;
		len := t.GetLength();
		bytesPerChar := 2;
		NEW(buffer, len * bytesPerChar);	(* UTF8 encoded characters use up to 5 bytes *)
		NEW(r, t);
		r.SetPosition(pos);
		j := 0;
		FOR i := 0 TO len-1 DO
			r.ReadCh(ch);
			WHILE ~UTF8Strings.EncodeChar(ch, buffer^, j) DO
					(* buffer too small *)
				INC(bytesPerChar);
				ExpandBuf(buffer, bytesPerChar * len);
			END;
		END;
		t.ReleaseRead;
		RETURN NewScanner(buffer, pos);
	END InitWithText;
	
	PROCEDURE ExpandBuf(VAR oldBuf: Buffer; newSize: LONGINT);
	VAR newBuf: Buffer; i: LONGINT;
	BEGIN
		IF LEN(oldBuf^) >= newSize THEN RETURN END;
		NEW(newBuf, newSize);
		FOR i := 0 TO LEN(oldBuf^)-1 DO
			newBuf[i] := oldBuf[i];
		END;
		oldBuf := newBuf;
	END ExpandBuf;
	
	PROCEDURE InitWithReader*(r: AosIO.Reader; size: LONGINT): Scanner;
		VAR buffer: Buffer; read: LONGINT;
	BEGIN
		NEW(buffer, size);
		r.Bytes(buffer^, 0, size, read);
		RETURN NewScanner(buffer, 0)
	END InitWithReader;
	
	PROCEDURE InitReservedCharsOld;
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO LEN(reservedChar)-1 DO
			IF (CHR(i) < "0") OR ("9" < CHR(i)) & (CHR(i) < "A") OR ("Z"< CHR(i)) & (CHR(i) < "a") OR ("z" < CHR(i)) THEN
				reservedChar[i] := TRUE;
			ELSE
				reservedChar[i] := FALSE;
			END;
		END;
	END InitReservedCharsOld;
	
	PROCEDURE InitReservedChars;
	VAR
		i: LONGINT;
	BEGIN
		FOR i := 0 TO LEN(reservedChar)-1 DO
			IF CHR(i) <= 20X THEN	(* TAB, CR, ESC ... *)
				reservedChar[i] := TRUE;
			ELSE
				CASE CHR(i) OF
					| "#", "&", "(", ")", "*", "+", ",", "-", ".", "/": reservedChar[i] := TRUE;
					| ":", ";", "<", "=", ">": reservedChar[i] := TRUE;
					| "[", "]", "^", "{", "|", "}", "~": reservedChar[i] := TRUE;
					| "$": reservedChar[i] := TRUE;
					| 22X, 27X, 7FX: reservedChar[i] := TRUE;	(* 22X = ", 27X = ', 7FX = del *)
				ELSE
					reservedChar[i] := FALSE;
				END;
			END;
		END;
	END InitReservedChars;
	
	PROCEDURE InitNewChar;
	VAR
		i: LONGINT;
	BEGIN
		FOR i := 0 TO LEN(newChar)-1 DO
			(* UTF-8 encoded characters with bits 10XXXXXX do not start a new unicode character *)
			IF (i < 80H) OR (i > 0BFH) THEN
				newChar[i] := TRUE;
			ELSE
				newChar[i] := FALSE;
			END
		END
	END InitNewChar;
		
	PROCEDURE CreateOperatorTable;
	BEGIN
		opTable[becomes] := StringPool.GetIndex1(":=");
		opTable[times] := StringPool.GetIndex1("*");
		opTable[slash] := StringPool.GetIndex1("/");
		opTable[div] := StringPool.GetIndex1("DIV");
		opTable[mod] := StringPool.GetIndex1("MOD");
		opTable[and] := StringPool.GetIndex1("&");
		opTable[plus] := StringPool.GetIndex1("+");
		opTable[minus] := StringPool.GetIndex1("-");
		opTable[or] := StringPool.GetIndex1("OR");
		opTable[eql] := StringPool.GetIndex1("=");
		opTable[neq] := StringPool.GetIndex1("#");
		opTable[lss] := StringPool.GetIndex1("<");
		opTable[leq] := StringPool.GetIndex1("<=");
		opTable[gtr] := StringPool.GetIndex1(">");
		opTable[geq] := StringPool.GetIndex1(">=");
		opTable[in] := StringPool.GetIndex1("IN");
		opTable[not] := StringPool.GetIndex1("~");
	END CreateOperatorTable;
	
BEGIN
	IF Trace THEN PCM.LogWLn; PCM.LogWStr("PCS.Trace on") END;
	CreateOperatorTable;
	InitReservedChars;
	InitNewChar;
END PCS.
(*
	28.12.02	prk	InitWithReader, remove VAR (reader is passed as reference anyway)
	05.02.02	prk	PCS takes AosIO.Reader as parameter, let PC handle the Oberon Text format
	18.01.02	prk	AosFS used instead of Files
	27.06.01	prk	StringPool cleaned up
	21.06.01	prk	using stringpool index instead of array of char
	12.06.01	prk	Interfaces
	26.04.01	prk	separation of RECORD and OBJECT in the parser
*)