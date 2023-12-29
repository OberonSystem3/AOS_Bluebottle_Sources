MODULE AosTextUtilities;	(** AUTHOR "TF"; PURPOSE "Utilities for the Unicode text system"; *)

IMPORT
	SYSTEM, (* for Oberon Text colors *)
	AosConfig, 
	AosOut, AosTexts, AosIO, AosFS, UTF8Strings, XML, XMLScanner, XMLParser, XMLObjects, Utilities, WMGraphics;

CONST
	CR = 0DX; LF = 0AX;
	
	(** FormatDescriptor features *)	
	LoadUnicode* = 0;  
	StoreUnicode* = 1;
	LoadFormated* = 2;
	StoreFormatted* = 3;

TYPE
	Char32 = AosTexts.Char32;
	Text = AosTexts.Text; 
	LoaderProc* = PROCEDURE {DELEGATE} (text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
	
TYPE FormatDescriptor = OBJECT
	VAR name : Utilities.String;
		loadProc, storeProc : Utilities.String;
		features : SET;
	END FormatDescriptor;
	
	
(* Return true if the unicode character x should be regarded as a white-space *)
PROCEDURE IsWhiteSpace*(x : Char32) : BOOLEAN;
BEGIN
	RETURN (x <= 32)
END IsWhiteSpace;

(* Return true if the unicode character x is alpha numeric *)
PROCEDURE IsAlphaNum*(x:Char32): BOOLEAN; 
BEGIN
	RETURN (ORD("0") <= x) & (x <= ORD("9"))
			OR (ORD("A") <= x) & (x <= ORD("Z") )
			OR (ORD("a") <= x) & (x <= ORD("z") )
END IsAlphaNum;
	
(** Find the position of the next word start to the left *) 
PROCEDURE FindPosWordLeft*(utilreader: AosTexts.TextReader; pos : LONGINT) : LONGINT;
VAR ch : AosTexts.Char32;
	new : LONGINT;
BEGIN
	utilreader.SetPosition(pos); utilreader.SetDirection(-1);
	utilreader.ReadCh(ch);
	WHILE (IsWhiteSpace(ch) & (ch # AosTexts.NewLineChar)) & (~utilreader.eot) DO utilreader.ReadCh(ch) END;
	WHILE (IsAlphaNum(ch)) & (~utilreader.eot) DO utilreader.ReadCh(ch) END; 
	new := utilreader.GetPosition() + 1;
	IF utilreader.eot THEN RETURN 0
	ELSIF new = pos THEN RETURN new
	ELSE RETURN new + 1
	END
END FindPosWordLeft;

(** Find the position of the next word start to the right *) 
PROCEDURE FindPosWordRight*(utilreader: AosTexts.TextReader; pos : LONGINT) : LONGINT;
VAR ch : AosTexts.Char32;
	new : LONGINT;
BEGIN
	utilreader.SetPosition(pos); utilreader.SetDirection(1);
	utilreader.ReadCh(ch);
	WHILE (IsAlphaNum(ch)) & (~utilreader.eot) DO utilreader.ReadCh(ch) END; 
	WHILE (IsWhiteSpace(ch) & (ch # AosTexts.NewLineChar)) & (~utilreader.eot) DO utilreader.ReadCh(ch) END;
	new := utilreader.GetPosition()-1;
	IF utilreader.eot THEN RETURN utilreader.text.GetLength()
	ELSIF new = pos THEN RETURN new+1
	ELSE RETURN new
	END
END FindPosWordRight;

(* rearch left until the first NewLineChar is encountered. Return the position of the following character *)
PROCEDURE FindPosLineStart* (utilreader: AosTexts.TextReader; pos: LONGINT): LONGINT;
VAR ch : AosTexts.Char32;
BEGIN
	utilreader.SetPosition(pos - 1);
	utilreader.SetDirection(-1);
	utilreader.ReadCh(ch);
	WHILE (ch # AosTexts.NewLineChar) & (~utilreader.eot) DO utilreader.ReadCh(ch) END;
	IF utilreader.eot THEN RETURN 0
	ELSE RETURN utilreader.GetPosition() + 2
	END
END FindPosLineStart;

(** Search right in the text until the first non whitespace is encountered. Return the number of whitespace characters *)
PROCEDURE CountWhitespace* (utilreader: AosTexts.TextReader; pos: LONGINT): LONGINT;
VAR ch : AosTexts.Char32;
	count : LONGINT;
BEGIN
	utilreader.SetPosition(pos);
	utilreader.SetDirection(1);
	utilreader.ReadCh(ch);
	count := 0; 
	WHILE (IsWhiteSpace(ch)) & (ch # AosTexts.NewLineChar) & (~utilreader.eot) DO INC(count); utilreader.ReadCh(ch) END;
	RETURN count
END CountWhitespace;

		
(** Import text in ASCII format. *)
PROCEDURE LoadAscii*(text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
VAR f : AosFS.File; r : AosFS.Reader;
	i, m: LONGINT;
	tempUCS32 : ARRAY 1024 OF Char32;
	ch, last : CHAR;
BEGIN
	text.AcquireWrite;
	res := -1;
	f := AosFS.Old(filename);
	IF f # NIL THEN 
		m := LEN(tempUCS32) - 1;
		AosFS.OpenReader(r, f, 0);
		i := 0;
		REPEAT
			r.Char(ch);
			IF i = m  THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
			IF (last # CR) OR (ch # LF) THEN
				IF ch = CR THEN tempUCS32[i] := ORD(LF)
				ELSE tempUCS32[i] := ORD(ch)
				END;	
				INC(i)
			END;	
			last := ch	
		UNTIL (r.res # AosIO.Ok);
		tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);
		res := 0
	END;
	text.ReleaseWrite
END LoadAscii;

PROCEDURE GetUTF8Char*(r : AosIO.Reader; VAR u : AosTexts.Char32) : BOOLEAN;
VAR ch : ARRAY 8 OF CHAR; i : LONGINT;
BEGIN
	ch[0] := r.Get();
	FOR i := 1 TO ORD(UTF8Strings.CodeLength[ORD(ch[0])]) - 1 DO ch[i] := r.Get() END;
	i := 0;
	RETURN UTF8Strings.DecodeChar(ch, i, u)
END GetUTF8Char;

(** Import text in UTF8 format. *)
PROCEDURE LoadUTF8*(text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
VAR f : AosFS.File; r : AosFS.Reader;
	i, m: LONGINT;
	tempUCS32 : ARRAY 1024 OF Char32;
	ch, last : AosTexts.Char32;
BEGIN
	text.AcquireWrite;
	res := -1;
	f := AosFS.Old(filename);
	IF f # NIL THEN 
		m := LEN(tempUCS32) - 1;
		AosFS.OpenReader(r, f, 0);
		i := 0;
		REPEAT
			IF GetUTF8Char(r, ch) THEN
				IF i = m  THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
				IF (last # ORD(CR)) OR (ch # ORD(LF)) THEN
					IF ch = ORD(CR) THEN tempUCS32[i] := ORD(LF) 
					ELSE tempUCS32[i] := ch
					END;
					INC(i)
				END;	
				last := ch
			END	
		UNTIL (r.res # AosIO.Ok);
		tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);
		res := 0
	END;
	text.ReleaseWrite
END LoadUTF8;

(** import text in UCS16 format *)
PROCEDURE LoadUCS16*(text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
VAR f : AosFS.File; r : AosFS.Reader;
	 i, m  : LONGINT;
	tempUCS32 : ARRAY 1024 OF Char32; 
	ch, last : Char32; ti : INTEGER; tc1, tc2 : CHAR;
BEGIN
	text.AcquireWrite;
	res := -1;
	f := AosFS.Old(filename);
	IF f # NIL THEN 
		m := LEN(tempUCS32) - 1;
		AosFS.OpenReader(r, f, 0);
		i := 0;
		REPEAT
			r.Char(tc1); r.Char(tc2); ch := ORD(tc1) * 256 + ORD(tc2);
			IF i = m  THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
			IF (last # ORD(CR)) OR (ch # ORD(LF)) THEN
				IF ch = ORD(CR) THEN tempUCS32[i] := ORD(LF)
				ELSE tempUCS32[i] := ch
				END;	
				INC(i)
			END;	
			last := ch	
		UNTIL (r.res # AosIO.Ok);
		tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);
		res := 0
	END;
	text.ReleaseWrite;
END LoadUCS16;

	
(** Export text in ASCII format. Objects, attributes and characters > CHR(128) are lost *)
PROCEDURE ExportAscii*(text : Text; fileName : ARRAY OF CHAR; VAR res : LONGINT);
VAR r : AosTexts.TextReader; ch : AosTexts.Char32; i : LONGINT;
	w : AosFS.Writer;
	f : AosFS.File;
BEGIN
	res := -1;
	f := AosFS.New(fileName);
	IF f = NIL THEN RETURN END;
	AosFS.OpenWriter(w, f, 0);
	text.AcquireRead;
	NEW(r, text);
	FOR i := 0 TO text.GetLength() - 1 DO 
		r.ReadCh(ch);
		IF (ch >= 0) & (ch < 128) THEN w.Char(CHR(ch)) END
	END; 
	w.Update;
	AosFS.Register(f); f.Update;
	text.ReleaseRead;
	res := 0
END ExportAscii;
	
(** Export text in UTF8 format Objects and attributes are lost *)
PROCEDURE ExportUTF8*(text : Text; fileName : ARRAY OF CHAR; VAR res : LONGINT);
VAR r : AosTexts.TextReader; ch : AosTexts.Char32; i, p : LONGINT; resstr : ARRAY 7 OF CHAR;
	w : AosFS.Writer;
	f : AosFS.File;
BEGIN
	res := -1;
	f := AosFS.New(fileName);
	IF f = NIL THEN RETURN END;
	AosFS.OpenWriter(w, f, 0);
	text.AcquireRead;
	NEW(r, text);
	FOR i := 0 TO text.GetLength() - 1 DO 
		r.ReadCh(ch); p := 0;
		IF (ch > 0) & UTF8Strings.EncodeChar(ch, resstr, p) THEN w.String(resstr) END
	END; 
	w.Update;
	AosFS.Register(f); f.Update;
	text.ReleaseRead;
	res := 0
END ExportUTF8;

(** Text to UTF8 string. Objects and attributes are lost. The String is truncated if buffer is too small *)
PROCEDURE TextToStr*(text : Text; VAR string : ARRAY OF CHAR);
VAR i, l, pos : LONGINT; r : AosTexts.TextReader; ch : AosTexts.Char32; ok : BOOLEAN;
BEGIN
	text.AcquireRead;
	string := "";
	NEW(r, text);
	i := 0; l := text.GetLength(); pos := 0; ok := TRUE;
	WHILE (i < l) & ok DO
		r.ReadCh(ch); 
		IF (ch > 0) THEN ok := UTF8Strings.EncodeChar(ch, string, pos) END;
		INC(i)
	END;
	text.ReleaseRead
END TextToStr;

(** Text to UTF8 string. Objects and attributes are lost. The String is truncated if buffer is too small *)
PROCEDURE SubTextToStr*(text : Text; spos, len : LONGINT; VAR string : ARRAY OF CHAR);
VAR i, l, pos : LONGINT; r : AosTexts.TextReader; ch : AosTexts.Char32; ok : BOOLEAN;
BEGIN
	text.AcquireRead;
	string[0] := 0X;
	NEW(r, text);
	r.SetPosition(spos);
	i := 0; l := len; pos := 0; ok := TRUE;
	WHILE (i < l) & ok DO
		r.ReadCh(ch); 
		IF (ch > 0) THEN ok := UTF8Strings.EncodeChar(ch, string, pos) END;
		INC(i)
	END;
	text.ReleaseRead
END SubTextToStr;

(** insert utf8 string into text *)
PROCEDURE StrToText*(text : Text; pos : LONGINT; string : ARRAY OF CHAR);
VAR r : AosIO.StringReader;
	i, m: LONGINT;
	tempUCS32 : ARRAY 1024 OF Char32;
	ch, last : AosTexts.Char32;
BEGIN
	text.AcquireWrite;
	NEW(r, LEN(string));
	m := LEN(tempUCS32) - 1;
	r.Set(string);
	i := 0;
	REPEAT
		IF GetUTF8Char(r, ch) THEN
			IF i = m THEN tempUCS32[i] := 0; text.InsertUCS32(pos, tempUCS32); INC(pos, m - 1); i := 0 END;
			IF (last # ORD(CR)) OR (ch # ORD(LF)) THEN
				IF ch = ORD(CR) THEN tempUCS32[i] := ORD(LF) 
				ELSE tempUCS32[i] := ch
				END;
				INC(i)
			END;	
			last := ch
		END	
	UNTIL (r.res # AosIO.Ok);
	tempUCS32[i] := 0; text.InsertUCS32(pos, tempUCS32);
	text.ReleaseWrite
END StrToText;

PROCEDURE DecodeOberonFontName(name : ARRAY OF CHAR; VAR fn : ARRAY OF CHAR; VAR size : LONGINT; VAR style : SET);
VAR i, j: LONGINT; sizeStr : ARRAY 8 OF CHAR;
BEGIN
	(* first name in oberon font names is capital, all following are non-capital *)
	fn[0] := name[0];
	i := 1; WHILE (name[i] >= "a") & (name[i] <= "z") DO fn[i] := name[i]; INC(i) END; fn[i] := 0X;
	(* read the size *)
	j := 0; WHILE (name[i] >= "0") & (name[i] <= "9") DO sizeStr[j] := name[i]; INC(j); INC(i) END; sizeStr[j] := 0X;
	Utilities.StrToInt(sizeStr, size);
	style := {};
	CASE CAP(name[i]) OF
		| "I" : INCL(style, WMGraphics.FontItalic);
		| "B" : INCL(style, WMGraphics.FontBold); 
	ELSE
	END
END DecodeOberonFontName;

(** Import an Oberon Text *)
PROCEDURE LoadOberonText*(text: Text; fileName: ARRAY OF CHAR; VAR res: LONGINT);
CONST DocBlockId = 0F7X; OldTextBlockId = 1X; TextBlockId = 0F0X; OldTextSpex = 0F0X; TextSpex = 1X; LibBlockId = 0DBX;
VAR f: AosFS.File; r, s: AosFS.Rider; ch: CHAR; lib :SHORTINT;
	len, flen, n, off, hlen, tlen, pos: LONGINT; x, y, w, h: INTEGER; name, lName: ARRAY 32 OF CHAR;
	type, ref, tag: CHAR;
	col: SHORTINT;
	voff: SHORTINT;
	fonts : ARRAY 256 OF AosTexts.FontInfo;
	attr : AosTexts.Attributes;
	tattr : AosTexts.FontInfo;
	oberonColors : ARRAY 16 OF LONGINT;
	
	PROCEDURE LoadLibrary(f:AosFS.File; pos:LONGINT; VARflen:LONGINT);
	BEGIN
	END LoadLibrary;
	
	PROCEDURE InsertPiece(ofs, len : LONGINT; attr : AosTexts.Attributes);
	VAR i, j, m : LONGINT; ch, last : CHAR;	tempUCS32 : ARRAY 1024 OF Char32;
		r : AosFS.Rider; oldpos : LONGINT;
	BEGIN
		m := LEN(tempUCS32) - 1;
(*		AosFS.OpenReader(r, f, ofs); *)
		f.Set(r, ofs);
		oldpos := text.GetLength();
		FOR j := 0 TO len - 1 DO
		(*	r.Char(ch); *)
			f.Read(r, ch);
			IF i = m  THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
			IF (last # CR) OR (ch # LF) THEN
				IF ch = CR THEN tempUCS32[i] := ORD(LF)
				ELSE tempUCS32[i] := ORD(ch)
				END;	
				INC(i)
			END;	
			last := ch
		END;
		tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);
		IF attr # NIL THEN text.SetAttributes(oldpos, len, attr) END	
	END InsertPiece;
	
	PROCEDURE IndexToColor(index: LONGINT): LONGINT;
	BEGIN
		RETURN
				ASH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, index) * {5..7}), 23-7) +
				ASH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, index) * {2..4}), 15-4) +
				ASH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, index) * {0..1}), 7-1)
	END IndexToColor;

BEGIN
	oberonColors[0] := 0FFFFFFFFH; oberonColors[1] := 0FF0000FFH; oberonColors[2] := 000FF00FFH; oberonColors[3] := 00000FFFFH;
	oberonColors[4] := 0FF00FFFFH; oberonColors[5] := 0FFFF00FFH; oberonColors[6] := 000FFFFFFH; oberonColors[7] := 0AA0000FFH;
	oberonColors[8] := 000AA00FFH; oberonColors[9] := 00000AAFFH; oberonColors[10] := 0A6BCF3FFH; oberonColors[11] := 0008282FFH;
	oberonColors[12] := 08A8A8AFFH; oberonColors[13] := 0BEBEBEFFH; oberonColors[14] := 07B7B7BFFH; oberonColors[15] := 0000000FFH; 
	text.AcquireWrite;
	
    f := AosFS.Old(fileName);
    IF f # NIL THEN
		f.Set(r, 0); f.Read(r, ch);
		IF ch = DocBlockId THEN (* skip doc header *)
			AosFS.ReadString(r, name); AosFS.ReadInt(r, x); AosFS.ReadInt(r, y); AosFS.ReadInt(r, w); AosFS.ReadInt(r, h);
			f.Read(r, ch); 
			IF ch = 0F7X THEN	(* skip meta info *)
				f.Read(r, ch); IF ch = 08X THEN AosFS.ReadLInt(r, len); f.Set(r, f.Pos(r) + len); f.Read(r, ch) END
			END
		END;
		pos := f.Pos(r);
		IF (ch = TextBlockId) OR (ch = OldTextBlockId) THEN
			f.Read(r, type);
			AosFS.ReadLInt(r, hlen);

			f.Set(s, pos - 1 + hlen - 4);
			AosFS.ReadLInt(s, tlen);

			IF (type = TextSpex) OR (type = OldTextSpex) THEN (*T.obs := NIL; flen := 0 *)
			ELSE (* NEW(T.obs); Objects.OpenLibrary(T.obs); *)
				f.Set(s, pos - 1 + hlen + tlen); f.Read(s, tag);
				IF tag = LibBlockId THEN LoadLibrary(f, pos - 1 + hlen + tlen + 1, flen) END;
				INC(flen)
			END;
			n := 1;
			off := pos - 1 + hlen;
			WHILE f.Pos(r) < pos - 1 + hlen - 5 DO
				AosFS.ReadSInt(r, lib);
				IF lib = n THEN
					AosFS.ReadString(r, lName); 
					NEW(fonts[n]);
					COPY(lName, fonts[n].name); 
					DecodeOberonFontName(lName, fonts[n].name, fonts[n].size, fonts[n].style);
					tattr := fonts[n];
					INC(n)
				ELSE
					IF (lib >= 0) & (lib < 255) & (fonts[lib] # NIL) THEN
						tattr := fonts[lib];
					END
				END;
				AosFS.ReadSInt(r, col);
				AosFS.ReadSInt(r, voff);
				AosFS.ReadLInt(r, len);
				IF len < 0 THEN AosOut.Enter; AosOut.String(" LoadAscii (T, f);"); AosOut.Exit; RETURN END;
				NEW(attr);
				CASE col OF
					0..15 : attr.color := oberonColors[col]
				ELSE attr.color := IndexToColor(col) * 100H + 0FFH
				END;
				attr.voff := voff;
				NEW(attr.fontInfo);
				IF tattr # NIL THEN 
					COPY(tattr.name, attr.fontInfo.name);
					attr.fontInfo.style := tattr.style;
					attr.fontInfo.size := tattr.size
				END;
				IF lib > 0 THEN (* ignore objects for now *)
					InsertPiece(off, len, attr)
				END;
				off := off + len
			END;	
		ELSE LoadAscii(text, fileName, res)
		END
	ELSE AosOut.Enter; AosOut.String("Not found: "); AosOut.String(fileName); AosOut.Exit
	END;
	text.ReleaseWrite;
	res := 0
END LoadOberonText;

PROCEDURE ToOberonFont(name : ARRAY OF CHAR; size : LONGINT; style : SET; VAR oname : ARRAY OF CHAR) : BOOLEAN;
VAR str : ARRAY 32 OF CHAR;
BEGIN
	COPY(name, oname);
	Utilities.IntToStr(size, str); Utilities.Append(oname, str);
	IF WMGraphics.FontBold IN style THEN Utilities.Append(oname, "b") END;
	IF WMGraphics.FontItalic IN style THEN Utilities.Append(oname, "i") END;
	Utilities.Append(oname, ".Scn.Fnt");
	RETURN AosFS.Old(oname) # NIL
END ToOberonFont;

PROCEDURE StoreOberonText*(text : Text; fileName: ARRAY OF CHAR; VAR res : LONGINT);
CONST DocBlockId = 0F7X; OldTextBlockId = 1X; TextBlockId = 0F0X; OldTextSpex = 0F0X; TextSpex = 1X; LibBlockId = 0DBX;
VAR r: AosTexts.TextReader;
	oberonColors : ARRAY 16 OF LONGINT;
	ch :Char32;
	voff: LONGINT;
	color : LONGINT;
	startPos, i, len : LONGINT;
	f: AosFS.File;
	w: AosFS.Writer;
	nofFonts, hLen : LONGINT;
	firstPiece : BOOLEAN;
	fonts : ARRAY 256 OF AosTexts.FontInfo;
	font : AosTexts.FontInfo;
	
	PROCEDURE ColorToIndex(col: LONGINT): LONGINT;
	BEGIN
		RETURN SYSTEM.VAL(LONGINT, 
				SYSTEM.VAL(SET, ASH(col, 7-23)) * {5..7} +
				SYSTEM.VAL(SET, ASH(col, 4-15)) * {2..4} +
				SYSTEM.VAL(SET, ASH(col, 1-7)) * {0..1})
	END ColorToIndex;

	PROCEDURE GetOberonColor(color : LONGINT):LONGINT;
	VAR i: LONGINT;
	BEGIN
		i := 0; WHILE i < LEN(oberonColors) DO IF oberonColors[i] = color THEN RETURN i END; INC(i) END;
		RETURN ColorToIndex(color DIV 100H)
	END GetOberonColor;
	
	PROCEDURE WritePiece(len: LONGINT);
	VAR i :LONGINT; oname : ARRAY 32 OF CHAR;
	BEGIN
		IF (font # NIL) THEN 
			i := 0; WHILE (i < nofFonts)  &  (~fonts[i].IsEqual(font)) DO INC(i) END;
			IF (i = nofFonts) THEN
				IF ToOberonFont(font.name, font.size, font.style, oname) THEN
					w.RawSInt(SHORT(SHORT(i+1)));
					IF i = nofFonts THEN w.RawString(oname); fonts[nofFonts] := font; INC(nofFonts) END
				ELSE
					w.RawSInt(1);
					IF firstPiece THEN 
						w.RawString("Oberon10.Scn.Fnt"); 
						NEW(fonts[nofFonts]);
						fonts[nofFonts].name := "Oberon"; fonts[nofFonts].size := 10; fonts[nofFonts].style := {};
						INC(nofFonts) 
					END;
				END
			ELSE w.RawSInt(SHORT(SHORT(i+1)));
			END
		ELSE
			w.RawSInt(1);
			IF firstPiece THEN 
				w.RawString("Oberon10.Scn.Fnt"); 
				NEW(fonts[nofFonts]);
				fonts[nofFonts].name := "Oberon"; fonts[nofFonts].size := 10; fonts[nofFonts].style := {};
				INC(nofFonts) 
			END;
		END;	
		firstPiece := FALSE;
		w.RawSInt(SHORT(SHORT(GetOberonColor(color))));
		w.RawSInt(SHORT(SHORT(-voff)));
		w.RawLInt(len)
	END WritePiece;
	
	
BEGIN
	oberonColors[0] := 0FFFFFFFFH; oberonColors[1] := 0FF0000FFH; oberonColors[2] := 000FF00FFH; oberonColors[3] := 00000FFFFH;
	oberonColors[4] := 0FF00FFFFH; oberonColors[5] := 0FFFF00FFH; oberonColors[6] := 000FFFFFFH; oberonColors[7] := 0AA0000FFH;
	oberonColors[8] := 000AA00FFH; oberonColors[9] := 00000AAFFH; oberonColors[10] := 0A6BCF3FFH; oberonColors[11] := 0008282FFH;
	oberonColors[12] := 08A8A8AFFH; oberonColors[13] := 0BEBEBEFFH; oberonColors[14] := 07B7B7BFFH; oberonColors[15] := 0000000FFH; 
	text.AcquireRead;
	firstPiece := TRUE;
	NEW(r, text);
	
	nofFonts := 0;
	
	f := AosFS.New(fileName);
	AosFS.OpenWriter(w, f, 0);
	
	w.Char(TextBlockId);
	w.Char(01X); (* simple text *) 
	w.RawLInt(0); (* header len place holder *)
	startPos := 1; len := 0;
	REPEAT 
		r.ReadCh(ch);
		IF ~r.eot & (ch >= 0) & (ch < 256) THEN
			INC(len);
			IF len < 2 THEN font := r.font; voff := r.voff; color := r.color END;
			IF (r.font # font) OR (r.voff # voff) OR (r.color # color) THEN 
				WritePiece(len - startPos);
				font := r.font; voff := r.voff; color := r.color;
				startPos := len
			END
		END	
	UNTIL r.eot;
	WritePiece(len + 1 - startPos);
	w.Char(0X); (* ??? *)
	w.RawLInt(len); (* tLen ? *)
	w.Update;
	hLen := w.sent; 
		
	(* pure text ... *)
	r.SetPosition(0);
	FOR i := 0 TO text.GetLength() - 1 DO r.ReadCh(ch); IF ch = AosTexts.NewLineChar THEN ch := 0DH END;
		IF (ch >=0) & (ch < 256) THEN w.Char(CHR(ch)) 
	END END;
	
	(* fixup header length *)
	w.Update;
	AosFS.OpenWriter(w, f, 2); w.RawLInt(hLen); w.Update;
	AosFS.Register(f);
	text.ReleaseRead;
	res := 0
END StoreOberonText;

PROCEDURE WriteUTF8Char*(w : AosIO.Writer; ch : Char32);
VAR str : ARRAY 8 OF CHAR; i : LONGINT;
BEGIN
	i := 0; IF UTF8Strings.EncodeChar(ch, str, i) THEN w.Bytes(str, 0, i) END
END WriteUTF8Char;

PROCEDURE StoreText*(text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
VAR w : AosFS.Writer; f : AosFS.File;
	ch :Char32;
	voff: LONGINT;
	color : LONGINT;
	r: AosTexts.TextReader;
	wvoff, wcolor : BOOLEAN;
	
	PROCEDURE WriteSection(wcolor, wvoff : BOOLEAN);
	BEGIN
		w.String("<Section ");
		IF wcolor THEN w.String('color="'); w.Hex(color, 8); w.String('" ') END;
		IF wvoff THEN w.String('voff="'); w.Int(voff, 0); w.String('" ') END;
		w.String(">")
	END WriteSection;
	
BEGIN
	res := 1;
	f := AosFS.New(filename); IF f = NIL THEN RETURN END;
	AosFS.OpenWriter(w, f, 0);
	w.String("<Text>"); w.Ln;
	text.AcquireRead;
	NEW(r, text);
	
	r.ReadCh(ch);
	voff := r.voff; color := r.color;
	WriteSection(TRUE, TRUE);
	WHILE ~r.eot DO
		IF ch < 128 THEN
			CASE CHR(ch) OF 
				|"<" : w.String("&lt;");
				|">" : w.String("&gt;");
				|"&" : w.String("&amp;");
			ELSE WriteUTF8Char(w, ch)
			END
		ELSE WriteUTF8Char(w, ch)
		END;
			
		r.ReadCh(ch);
		wcolor := (color # r.color);
		wvoff := (voff # r.voff);
		IF wvoff OR wcolor THEN
			voff := r.voff; color := r.color;
			IF ~r.eot THEN w.String("</Section>"); WriteSection(wcolor, wvoff) END
		END
	END;
	
	w.String("</Section>");
	w.String("</Text>"); w.Ln;
	w.Update;
	AosFS.Register(f);
	text.ReleaseRead;
	res := 0
END StoreText;

PROCEDURE LoadText*(text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
VAR scanner : XMLScanner.Scanner; parser : XMLParser.Parser; doc : XML.Document; f : AosFS.File;
	cont, tc : XMLObjects.Enumerator; ptr : PTR; el, root : XML.Element; str : Utilities.String;
	o : AosTexts.ObjectPiece; attr: AosTexts.Attributes;

		PROCEDURE GetUTF8Char(r : AosIO.Reader; VAR u : AosTexts.Char32; VAR pos : LONGINT) : BOOLEAN;
		VAR ch : ARRAY 8 OF CHAR; i : LONGINT;
		BEGIN
			ch[0] := r.Get(); INC(pos);
			FOR i := 1 TO ORD(UTF8Strings.CodeLength[ORD(ch[0])]) - 1 DO ch[i] := r.Get(); INC(pos) END;
			i := 0;
			RETURN UTF8Strings.DecodeChar(ch, i, u)
		END GetUTF8Char;
	
	PROCEDURE InsertPiece(charContent : XML.CharData);
	VAR i, j, m, tpos : LONGINT; ch, last : Char32;	tempUCS32 : ARRAY 1024 OF Char32;
		r : AosFS.Reader; oldpos, len : LONGINT; tstr : ARRAY 10 OF CHAR;
	BEGIN
		AosOut.String("INSERT PIECE!!!!");
		m := LEN(tempUCS32) - 1;
		AosFS.OpenReader(r, charContent.GetFile(), charContent.GetPos());
		oldpos := text.GetLength();
		len := charContent.GetLength();
		AosOut.String("StartPos : "); AosOut.Int(charContent.GetPos(), 5); AosOut.String(" len : "); 
		AosOut.Int(charContent.GetLength(), 5); AosOut.Ln;
		tpos := 0;
		REPEAT
			IF GetUTF8Char(r, ch, tpos) THEN
				IF ch = ORD("&") THEN
					i := 0; tstr[i] := "&";
					REPEAT 
						INC(i);
						IF GetUTF8Char(r, ch, tpos) THEN tstr[i] := CHR(ch) END
					UNTIL (i >= LEN(tstr)-1) OR (tstr[i] = ";");
					tstr[i] := 0X;
					IF tstr =" &amp;" THEN ch := ORD("&")
					ELSIF tstr =" &lt;" THEN ch := ORD("<")
					ELSIF tstr =" &gt;" THEN ch := ORD(">")
					END
				END;
				IF i = m  THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
				IF (last # ORD(CR)) OR (ch # ORD(LF)) THEN
					IF ch = ORD(CR) THEN tempUCS32[i] := ORD(LF) 
					ELSE tempUCS32[i] := ch
					END;
					INC(i)
				END;	
				last := ch
			END	
		UNTIL (tpos >= len) OR (r.res # AosIO.Ok);
		tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);

		IF attr # NIL THEN text.SetAttributes(oldpos, len, attr.Clone()) END;
		AosOut.Ln;
	END InsertPiece;
	
BEGIN
	text.AcquireWrite;
	NEW(attr);
	f := AosFS.Old(filename);
	IF f = NIL THEN RETURN END;
	NEW(scanner, f); NEW(parser, scanner); doc := parser.Parse(); root := doc.GetRoot();
	cont := root.GetContents(); cont.Reset();
	WHILE cont.HasMoreElements() DO
		ptr := cont.GetNext();
		IF ptr IS XML.Element THEN 
			str := ptr(XML.Element).GetName();
			IF (str # NIL) & (str^ = "Section") THEN
				tc := ptr(XML.Element).GetContents(); tc.Reset();
				str := ptr(XML.Element).GetAttributeValue("color"); IF str # NIL THEN Utilities.HexStrToInt(str^, attr.color, res) END;
				str := ptr(XML.Element).GetAttributeValue("voff"); IF str # NIL THEN Utilities.StrToInt(str^, attr.voff) END;
				IF tc.HasMoreElements() THEN
					ptr := tc.GetNext();
					IF ptr IS XML.CharData THEN InsertPiece(ptr(XML.CharData)) END
				END	
			ELSE
				NEW(o); o.object := ptr; text.InsertPiece(text.GetLength(), o);
			END;
		END	
	END;	
	text.ReleaseWrite
END LoadText;

PROCEDURE SkipLine(utilreader: AosTexts.TextReader; pos: LONGINT): LONGINT;
VAR ch : AosTexts.Char32;
BEGIN
	utilreader.SetPosition(pos );
	utilreader.SetDirection(1);
	utilreader.ReadCh(ch);
	WHILE (ch # AosTexts.NewLineChar) & (~utilreader.eot) DO utilreader.ReadCh(ch) END;
	RETURN utilreader.GetPosition()
END SkipLine;


PROCEDURE IndentText*(text : AosTexts.Text; from, to : LONGINT; minus : BOOLEAN);
VAR r : AosTexts.TextReader;
	p, pto : AosTexts.TextPosition;
	tab : ARRAY 2 OF AosTexts.Char32;
	c : AosTexts.Char32;
BEGIN
	tab[0] := AosTexts.TabChar; tab[1] := 0;
	text.AcquireWrite;
	NEW(r, text); NEW(p, text); NEW(pto, text); 
	pto.SetPosition(to);
	p.SetPosition(from);
	WHILE p.GetPosition() < pto.GetPosition() DO
		p.SetPosition(FindPosLineStart(r, p.GetPosition()));
		IF minus THEN
			r.SetPosition(p.GetPosition()); r.SetDirection(1);
			r.ReadCh(c);
			IF c = AosTexts.TabChar THEN 
				text.Delete(p.GetPosition(), 1)
			END
		ELSE
			text.InsertUCS32(p.GetPosition(), tab);
		END;
		p.SetPosition(SkipLine(r, p.GetPosition()))
	END;
	text.ReleaseWrite
END IndentText;


PROCEDURE UCS32StrLength*(VAR string: ARRAY OF Char32): LONGINT;
VAR len: LONGINT;
BEGIN
	len := 0; WHILE (string[len] # 0) DO INC(len) END;
	RETURN len
END UCS32StrLength;

(** returns the position of the first occurrence of pattern (ucs32) in the text or -1 if no occurrence is found *)
(* Rabin-Karp algorithm, adopted from Sedgewick *)
(* efficiency could be improved by not seeking so much *)
PROCEDURE Pos*(VAR pattern: ARRAY OF Char32; from : LONGINT; text : Text): LONGINT;
CONST q=33554393; d = 32;
VAR h1, h2, dM, i, j, m, n: LONGINT; check: BOOLEAN; ch : Char32; r : AosTexts.TextReader;
BEGIN
	NEW(r, text);  r.SetPosition(from);
	m := UCS32StrLength(pattern); n := text.GetLength();
	IF (m > n) THEN RETURN -1 END;

	dM := 1; FOR i := 0 TO m-2 DO dM := (d*dM) MOD q END;
	h1 := 0; FOR i := 0 TO m-1 DO h1 := (h1*d + pattern[i]) MOD q END;
	h2 := 0; FOR i := 0 TO m-1 DO r.ReadCh(ch); h2 := (h2*d + ch) MOD q END;
	i := from;
	WHILE (h1 # h2) & (i < n-m) DO
		r.SetPosition(i);r.ReadCh(ch); h2 := (h2 + d*q - ch*dM) MOD q;
		r.SetPosition(i + m); r.ReadCh(ch); h2 := (h2*d + ch) MOD q;
		INC(i);
		
		IF (h1 = h2) THEN	(* verify *)
			check := TRUE; j := 0;
			WHILE (j < m) & check DO
				r.SetPosition(i + j); r.ReadCh(ch); 
				IF (ch # pattern[j]) THEN INC(h2); j := m END;	(* hash values are equal, but strings are not *)
				INC(j)
			END
		END
	END;
	
	IF (h1 = h2) THEN RETURN i
	ELSE RETURN -1
	END	
END Pos;

PROCEDURE AddFontFormat*(x : FormatDescriptor);
BEGIN
	IF x.name # NIL THEN AosOut.String("name = "); AosOut.String(x.name^); AosOut.Ln  END; 
	IF x.loadProc # NIL THEN AosOut.String("loadProc = "); AosOut.String(x.loadProc^); AosOut.Ln  END; 
	IF x.storeProc # NIL THEN AosOut.String("storeProc = "); AosOut.String(x.storeProc^); AosOut.Ln  END; 
END AddFontFormat;


PROCEDURE GetConfig;
VAR sectWM, sectFM, e : XML.Element; 
	p : PTR; enum: XMLObjects.Enumerator;
	f : FormatDescriptor;
BEGIN
	sectWM := AosConfig.GetNamedElement(AosConfig.config.GetRoot(), "Section", "TextFormats");
	IF sectFM # NIL THEN
		enum := sectFM.GetContents();
		WHILE enum.HasMoreElements() DO
			p := enum.GetNext();
			IF p IS XML.Element THEN
				NEW(f);
				f.name := p(XML.Element).GetName();

				e := AosConfig.GetNamedElement(p(XML.Element), "Setting", "Load");
				IF e # NIL THEN f.loadProc := e.GetAttributeValue("Value") END;

				e := AosConfig.GetNamedElement(p(XML.Element), "Setting", "Store");
				IF e # NIL THEN f.storeProc := e.GetAttributeValue("Value") END;
				
				AddFontFormat(f);
			END
		END
	END
END GetConfig;

BEGIN
	GetConfig;
END AosTextUtilities.
