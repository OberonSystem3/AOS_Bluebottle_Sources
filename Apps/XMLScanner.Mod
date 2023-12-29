MODULE XMLScanner;	(** Stefan Walthert   *)
(** AUTHOR "swalthert"; PURPOSE "XML scanner"; *)

IMPORT
	Utilities, AosOut, AosIO, AosFS, DynamicStrings;

CONST
	(** Scanner: Tokens *)
	Invalid* = -1;
	TagElemStartOpen* = 0;	(** '<' *)
	TagElemEndOpen* = 1;	(** '</' *)
	TagDeclOpen* = 2;	(** '<!NAME' *)
	TagClose* = 3;	(** '>' *)
	TagEmptyElemClose* = 4;	(** '/>' *)
	TagXMLDeclOpen* = 5;	(** '<?xml' *)
	TagPIOpen* = 6;	(** '<?', PITarget := GetStr() *)
	TagPIClose* = 7;	(** '?>' *)
	TagCondSectOpen* = 8;	(** '<![' *)
	TagCondSectClose* = 9;	(** ']]>' *)
	BracketOpen* = 10;	(** '[' *)
	BracketClose* = 11;	(** ']' *)
	ParenOpen* = 12;	(** '(' *)
	ParenClose* = 13;	(** ')' *)
	Comment* = 14;	(** '<!--' chars '-->', chars := GetStr() *)
	CDataSect* = 15;	(** '<![CDATA[' chars ']]>', chars := GetStr() *)
	CharRef* = 16;	(** '&#' number ';' or '&#x' hexnumber ';', number, hexnumber := GetStr() *)
	EntityRef* = 17;	(** '&' name ';', name := GetStr() *)
	ParamEntityRef* = 18;	(** '%' name ';', name := GetStr() *)
	CharData* = 19;	(** chars := GetStr() *)
	Literal* = 20;	(** '"'chars'"' or "'"chars"'", chars := GetStr() *)
	Name* = 21;	(** 	Name ::= (Letter | '_' | ':') {NameChar}
										NameChar ::= Letter | Digit | '.' | '-' | '_' | ':' | CombiningChar | Extender
										chars := GetStr() *)
	Nmtoken* = 22;	(**	Nmtoken ::= NameChar {NameChar}, chars := GetStr() *)
	PoundName* = 23;	(** '#'name, name := GetStr() *)
	Question* = 24;	(** '?' *)
	Asterisk* = 25;	(** '*' *)
	Plus* = 26;	(** '+' *)
	Or* = 27;	(** '|' *)
	Comma* = 28;	(** ',' *)
	Percent* = 29;	(** '%' *)
	Equal* = 30;	(** '=' *)
	Eof* = 31;
	
TYPE
	String = Utilities.String;

	Scanner* = OBJECT
		VAR
			sym-: SHORTINT;	(** current token *)
			line-, row-, oldpos, pos: LONGINT;
			reportError*: PROCEDURE (pos, line, row: LONGINT; msg: ARRAY OF CHAR);
			nextCh: CHAR;	(* look-ahead *)
			dynstr: DynamicStrings.DynamicString;	(* buffer for CharData, Literal, Name, CharRef, EntityRef and ParamEntityRef *)
			f: AosFS.File;	(* source file *)
			r: AosFS.Reader;	(* rider on source file *)
		
		(** Initialize scanner to read from the given ascii file *)
		PROCEDURE & Init*(f: AosFS.File);
		BEGIN
			IF f = NIL THEN
				sym := Invalid
			ELSE
				reportError := DefaultReportError;
				SELF.f := f;
				AosFS.OpenReader(r, f, 0);
				NEW(dynstr);
				dynstr.Init();
				line := 1; row := 1; pos := 0;
				NextCh()
			END
		END Init;
		
		PROCEDURE Error(msg: ARRAY OF CHAR);
		BEGIN
			sym := Invalid;
			reportError(GetPos(), line, row, msg)
		END Error;
		
		PROCEDURE NextCh();
		BEGIN
			IF (nextCh = DynamicStrings.CR) (* OR (nextCh = Strings.LF) *) THEN INC(line); row := 1
			ELSE INC(row)
			END;
			IF r.res # AosIO.Ok THEN
				nextCh := 0X; sym := Eof
			ELSE
				nextCh := r.Get(); INC(pos)
			END
		END NextCh;

		PROCEDURE ReadTillChar(ch: CHAR);
		VAR i: LONGINT;
		BEGIN
			i := 0;
			WHILE (nextCh # ch) & (sym # Eof) DO
				dynstr.Put(nextCh, i); INC(i); NextCh()
			END;
			dynstr.Put(0X, i);
			IF sym = Eof THEN sym := Invalid END
		END ReadTillChar;
		
		PROCEDURE SkipWhiteSpaces();
		BEGIN
			WHILE IsWhiteSpace(nextCh) & (sym # Eof) DO
				NextCh()
			END
		END SkipWhiteSpaces;
		
		PROCEDURE ScanPoundName();
		VAR i: LONGINT;
		BEGIN
			dynstr.Put(nextCh, 0);
			i := 1; NextCh();
			WHILE (('a' <= nextCh) & (nextCh <= 'z')) OR (('A' <= nextCh) & (nextCh <= 'Z')) OR 
				(('0' <= nextCh) & (nextCh <= '9')) OR (nextCh = '.') OR (nextCh = '-') OR (nextCh = '_') OR (nextCh = ':') DO
				dynstr.Put(nextCh, i); INC(i); NextCh()
			END;
			dynstr.Put(0X, i);
			IF sym # Eof THEN sym := PoundName ELSE sym := Invalid END
		END ScanPoundName;
		
		(* Possible results:
				Name
				Nmtoken
				Invalid	*)
		PROCEDURE ScanNm();
		VAR i: LONGINT;
		BEGIN
			SkipWhiteSpaces();
			IF (('0' <= nextCh) & (nextCh <= '9')) OR (nextCh = '.') OR (nextCh = '-') THEN
				sym := Nmtoken
			ELSIF (('a' <= nextCh) & (nextCh <= 'z')) OR (('A' <= nextCh) & (nextCh <= 'Z')) OR (nextCh = '_') OR (nextCh = ':') THEN
				sym := Name
			ELSE
				sym := Invalid; RETURN
			END;
			dynstr.Put(nextCh, 0);
			i := 1; NextCh();
			WHILE ((('a' <= nextCh) & (nextCh <= 'z')) OR (('A' <= nextCh) & (nextCh <= 'Z')) OR 
					(('0' <= nextCh) & (nextCh <= '9')) OR (nextCh = '.') OR (nextCh = '-') OR (nextCh = '_') 
					OR (nextCh = ':')) & (sym # Eof) DO
				dynstr.Put(nextCh, i); INC(i); NextCh()
			END;
			dynstr.Put(0X, i);
			IF sym = Eof THEN sym := Invalid END
		END ScanNm;
		
		(* Scan Comment after comment open tag '<!--', write characters to dynstr.
				Possible results:
				Invalid
				Comment	*)
		PROCEDURE ScanComment();
		VAR i: LONGINT;
		BEGIN
			i := 0;
			LOOP
				WHILE (nextCh # '-') & (sym # Eof) DO
					dynstr.Put(nextCh, i); INC(i); NextCh()
				END;
				IF nextCh = '-' THEN
					NextCh();
					IF nextCh = '-' THEN
						NextCh();
						IF nextCh = '>' THEN
							dynstr.Put(0X, i); NextCh(); sym := Comment; RETURN
						ELSE
							sym := Invalid; RETURN
						END
					ELSE
						dynstr.Put('-', i); INC(i)
					END
				ELSE
					sym := Invalid; RETURN
				END
			END
		END ScanComment;
		
		(* Possible results:
				CharData
				TagCDataSectClose
				Invalid	*)
		PROCEDURE ScanCDataSect();
		VAR i: LONGINT;
		BEGIN
			IF sym = Eof THEN
				sym := Invalid;
				RETURN
			END;
			i := 0;
			LOOP
				WHILE (nextCh # ']') &  (sym # Eof) DO
					dynstr.Put(nextCh, i); INC(i); NextCh()
				END;
				IF nextCh = ']' THEN
					NextCh();
					IF nextCh = ']' THEN
						NextCh();
						IF nextCh = '>' THEN
							NextCh();
							dynstr.Put(0X, i);
							sym := CDataSect; RETURN
						ELSE
							dynstr.Put(']', i); INC(i); dynstr.Put(']', i); INC(i)
						END
					ELSE
						dynstr.Put(']', i); INC(i)
					END
				ELSE
					dynstr.Put(0X, i); sym := CharData; RETURN
				END
			END
		END ScanCDataSect;
		
		(* possible results:
			Invalid
			ParamEntityRef *)
		PROCEDURE ScanPEReference();
		BEGIN
			ReadTillChar(';'); NextCh();
			IF sym # Invalid THEN sym := ParamEntityRef END
		END ScanPEReference;

		(* possible results:
			Invalid
			CharRef
			EntityRef *)
		PROCEDURE ScanReference();
		BEGIN
			IF nextCh = '#' THEN
				NextCh();
				ReadTillChar(';'); NextCh();
				IF sym # Invalid THEN sym := CharRef END;
			ELSE
				ReadTillChar(';'); NextCh();
				IF sym # Invalid THEN sym := EntityRef END
			END
		END ScanReference;
	
		(** possible results:
			Invalid
			TagPIClose
			CharData	*)
		PROCEDURE ScanPInstruction*();
		VAR i: LONGINT;
		BEGIN
			IF sym = Eof THEN
				sym := Invalid;
				RETURN
			END;
			i := 0;
			LOOP
				WHILE (nextCh # '?') & (sym # Eof) DO
					dynstr.Put(nextCh, i); INC(i); NextCh()
				END;
				IF nextCh = '?' THEN
					NextCh();
					IF nextCh = '>' THEN
						sym := TagPIClose; NextCh(); RETURN
					ELSE
						dynstr.Put('?', i); INC(i)
					END
				ELSIF sym = Eof THEN
					sym := Invalid; RETURN
				ELSE						
					dynstr.Put(0X, i); sym := CharData; RETURN
				END
			END
		END ScanPInstruction;
		
		(** Possible results:
			Invalid
			TagPIOpen
			TagCondSectOpen
			TagDeclOpen
			TagXMLDeclOpen
			TagClose
			TagEmptyElemClose
			TagPIClose
			TagCondSectClose
			Comment
			CharRef
			EntityRef
			ParamEntityRef
			Literal
			Name
			Nmtoken
			PoundName
			Question
			Asterisk
			Plus
			Or
			Comma
			Percent
			Equal
			ParenOpen
			ParenClose
			BracketOpen
			BracketClose	*)
		PROCEDURE ScanMarkup*();
		VAR ch: CHAR;
		BEGIN
			SkipWhiteSpaces();
			oldpos := GetPos();
			IF sym = Eof THEN
				sym := Eof; RETURN
			END;
			CASE nextCh OF
			| '<': NextCh();
					IF nextCh = '!' THEN
						NextCh();
						IF nextCh = '-' THEN
							NextCh();
							IF nextCh = '-' THEN
								NextCh(); ScanComment()
							ELSE
								Error("'<!--' expected")
							END
						ELSIF nextCh = '[' THEN
							sym := TagCondSectOpen
						ELSE
							ScanNm();
							IF sym = Name THEN
								sym := TagDeclOpen
							ELSE
								Error("'<!NAME' expected")
							END
						END
					ELSIF nextCh = '?' THEN
						NextCh(); ScanNm();
						IF sym = Name THEN
							sym := TagPIOpen
						ELSE
							Error("'<?' Name expected")
						END
					ELSE
						Error("'<?' Name or '<!--' expected")
					END
			| '/': NextCh();
					IF nextCh = '>' THEN
						NextCh(); sym := TagEmptyElemClose
					ELSE
						sym := Invalid
					END
			| '>': NextCh(); sym := TagClose
			| '%': NextCh();
					IF nextCh = ' ' THEN 
						sym := Percent
					ELSE
						ScanPEReference()
					END						
			| '?': NextCh();
					IF nextCh = '>' THEN
						NextCh();
						sym := TagPIClose
					ELSE
						sym := Question
					END
			| '*': NextCh(); sym := Asterisk
			| '+': NextCh(); sym := Plus
			| '|': NextCh(); sym := Or
			| ',': NextCh(); sym := Comma
			| '(': NextCh(); sym := ParenOpen
			| ')': NextCh(); sym := ParenClose
			| '[': NextCh(); sym := BracketOpen
			| ']': NextCh();
					IF nextCh = ']' THEN
						NextCh();
						IF nextCh = '>' THEN
							NextCh(); sym := TagCondSectClose
						ELSE
							Error("']]>' expected")
						END
					ELSE
						sym := BracketClose
					END
			| '=': NextCh(); sym := Equal
			| '"', "'": ch := nextCh; NextCh(); ReadTillChar(ch); NextCh();
					IF sym # Invalid THEN sym := Literal END;
			| '#': ScanPoundName()
			ELSE ScanNm()
			END
		END ScanMarkup;
		
		(** possible results:
			TagElemEndOpen
			TagPIOpen
			TagDocTypeOpen
			CDataSect
			TagElemStartOpen
			Comment
			CharData
			CharRef
			EntityRef
			Eof *)
		PROCEDURE ScanContent*();
		VAR s: String; op: LONGINT;
		BEGIN
			op := GetPos();
			SkipWhiteSpaces(); oldpos := GetPos();
			IF sym = Eof THEN nextCh := 0X END;
			CASE nextCh OF
			| 0X: sym := Eof
			| '<': NextCh();
					CASE nextCh OF
					| '/': sym := TagElemEndOpen; NextCh()
					| '?': NextCh(); ScanNm();
							IF (sym = Name) THEN
								s := dynstr.ToArrOfChar(); DynamicStrings.Lower(s^, s^);
								IF s^ = "xml" THEN
									sym := TagXMLDeclOpen
								ELSE
									sym := TagPIOpen
								END
							ELSE
								Error("'<? Name' expected")
							END
					| '!': NextCh();
							IF nextCh = '-' THEN
								NextCh();
								IF nextCh = '-' THEN
									NextCh(); ScanComment()
								ELSE
									Error("'<!--' expected")
								END
							ELSIF nextCh = '[' THEN
								NextCh(); ScanNm(); s := dynstr.ToArrOfChar();
								IF (sym = Name) & (s^ = "CDATA") & (nextCh = '[') THEN
									NextCh(); ScanCDataSect()
								ELSE
									Error("'<[CDATA[' expected'")
								END
							ELSE
								ScanNm();
								IF  sym = Name THEN
									sym := TagDeclOpen
								ELSE
									Error("'<!xml' or '<!NAME' expected")
								END
							END
					ELSE
						sym:=TagElemStartOpen
					END
			| '?': NextCh();
					IF nextCh = '>' THEN
						NextCh(); sym := TagPIClose
					ELSE
						Error("'?>' expected")
					END
			| '&': NextCh(); ScanReference()
			ELSE
				REPEAT
					NextCh();
				UNTIL (nextCh='<') OR (nextCh='&') OR (sym = Eof);
				oldpos := op;
				sym := CharData
			END
		END ScanContent;

		PROCEDURE GetStr*(): String;
		BEGIN
			RETURN dynstr.ToArrOfChar();
		END GetStr;
		
		PROCEDURE GetPos*(): LONGINT;
		BEGIN
			RETURN pos - 1
		END GetPos;
		
		PROCEDURE GetOldPos*(): LONGINT;
		BEGIN
			RETURN oldpos
		END GetOldPos;
		
		PROCEDURE GetFile*(): AosFS.File;
		BEGIN
			RETURN f
		END GetFile;
	
	END Scanner;

	PROCEDURE IsWhiteSpace(ch: CHAR): BOOLEAN;
	BEGIN
		RETURN (ch = 020X) OR (ch = 9X) OR (ch = 0DX) OR (ch = 0AX)
	END IsWhiteSpace;
	
	PROCEDURE DefaultReportError(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
	BEGIN
		AosOut.Enter; AosOut.Char(CHR(9H)); AosOut.Char(CHR(9H)); AosOut.String("pos "); AosOut.Int(pos, 6);
		AosOut.String(", line "); AosOut.Int(line, 0); AosOut.String(", row "); AosOut.Int(row, 0);
		AosOut.String("    "); AosOut.String(msg); AosOut.Exit;
		HALT(99)
	END DefaultReportError;
	
BEGIN
END XMLScanner.