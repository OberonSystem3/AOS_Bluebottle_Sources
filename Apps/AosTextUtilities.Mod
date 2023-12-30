MODULE AosTextUtilities;	(** AUTHOR "TF"; PURPOSE "Utilities for the Unicode text system"; *)
(**
 * History:
 *
 *	22.12.2006	Fixed search algorithm in procedure Pos, added GenericPos, Equals & UpperCaseChar (staubesv)
 *	12.03.2007	Another bugfix in Pos & GenericPos (staubesv)
 *)
 
IMPORT
	SYSTEM, (* for Oberon Text colors *)
	AosConfig, AosCommands, AosCodecs, FP1616,
	AosOut, AosTexts, AosIO, AosFS, UTF8Strings, XML, XMLScanner, XMLParser, XMLObjects, Utilities, WMGraphics,
	WMComponents;

CONST
	CR = 0DX; LF = 0AX; TAB = 09X;
	
	(** FormatDescriptor features *)	
	LoadUnicode* = 0;  
	StoreUnicode* = 1;
	LoadFormated* = 2;
	StoreFormatted* = 3;

TYPE
	Char32 = AosTexts.Char32;
	Text = AosTexts.Text;
	LoaderProc* = PROCEDURE {DELEGATE} (text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
	
TYPE
	FormatDescriptor = OBJECT
	VAR name : Utilities.String;
		loadProc, storeProc : Utilities.String;
		features : SET;
	END FormatDescriptor;
	
	TextWriter* = OBJECT
	VAR text : AosTexts.Text;
		w : AosIO.Writer;
		ucs32buf : POINTER TO ARRAY OF LONGINT;
		fontName : ARRAY 32 OF CHAR;
		fontSize, fontColor, fontBgColor, fontVOff : LONGINT;
		fontStyle : SET;
		fontChanged : BOOLEAN;
		currentAttributes : AosTexts.Attributes;
		oldBytes : ARRAY 7 OF CHAR;
		nofOldBytes : LONGINT;
		
		PROCEDURE &Init(text : AosTexts.Text);
		BEGIN
			SELF.text := text;
			nofOldBytes := 0;
			fontChanged := TRUE;
			currentAttributes := AosTexts.GetDefaultAttributes();
			fontColor := currentAttributes.color;
			fontBgColor := currentAttributes.bgcolor;
			fontVOff := currentAttributes.voff;
			COPY(currentAttributes.fontInfo.name, fontName);
			fontSize := currentAttributes.fontInfo.size;
			fontStyle := currentAttributes.fontInfo.style
		END Init;		
		
		PROCEDURE Add*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		VAR
			p, i, idx, pos : LONGINT;
		BEGIN
			IF (ucs32buf = NIL) OR (len >= LEN(ucs32buf)) THEN NEW(ucs32buf, len + 1) END; 
			p := ofs; idx := 0;
			(* complete an unfinished character *)
			IF nofOldBytes > 0 THEN
				FOR i := nofOldBytes TO ORD(UTF8Strings.CodeLength[ORD(oldBytes[0])]) - 1 DO
					oldBytes[i] := buf[p]; INC(p)
				END;
				i := 0; IF UTF8Strings.DecodeChar(oldBytes, i, ucs32buf[idx]) THEN INC(idx) END;
				nofOldBytes := 0
			END;
			
			WHILE (p  < ofs + len) & (ORD(UTF8Strings.CodeLength[ORD(buf[p])]) <= ofs + len) & UTF8Strings.DecodeChar(buf, p, ucs32buf[idx]) DO INC(idx) END;
			ucs32buf[idx] := 0;
			
			IF (p < ofs + len) & (ORD(UTF8Strings.CodeLength[ORD(buf[p])]) >= ofs + len)  THEN (* could not be decoded because of missing bytes. ignore other problems *)
				WHILE p < ofs + len DO oldBytes[i] := buf[p]; INC(p); INC(i) END;
				nofOldBytes := i;
				AosOut.String("Update within UTF sequence "); AosOut.Ln; 
			END;
			
			IF fontChanged THEN
				NEW(currentAttributes);
				currentAttributes.Set(fontColor, fontBgColor, fontVOff, fontName, fontSize, fontStyle);
				fontChanged := FALSE
			END;
			text.AcquireWrite;
			pos := text.GetLength();
			text.InsertUCS32(text.GetLength(), ucs32buf^);
			text.SetAttributes(pos, text.GetLength()-pos, currentAttributes);
			text.ReleaseWrite;			
		END Add;

		(** returns an AosIO.Writer to the text *)
		PROCEDURE GetWriter*() : AosIO.Writer;
		BEGIN
			IF w = NIL THEN NEW(w, SELF.Add, 256) END;
			RETURN w
		END GetWriter;
		
		PROCEDURE SetFontName* (name : ARRAY OF CHAR);
		BEGIN
			IF w # NIL THEN w.Update END;
			COPY(name, fontName);
			fontChanged := TRUE
		END SetFontName;
		
		PROCEDURE SetFontSize* (size : LONGINT);
		BEGIN
			IF w # NIL THEN w.Update END;
			fontSize := size;
			fontChanged := TRUE
		END SetFontSize;
		
		PROCEDURE SetFontStyle* (style :  SET);
		BEGIN
			IF w # NIL THEN w.Update END;
			fontStyle := style;
			fontChanged := TRUE
		END SetFontStyle;
		
		PROCEDURE SetFontColor* (color : LONGINT);
		BEGIN
			IF w # NIL THEN w.Update END;
			fontColor := color;
			fontChanged := TRUE
		END SetFontColor;
		
		PROCEDURE SetBgColor* (bgColor : LONGINT);
		BEGIN
			IF w # NIL THEN w.Update END;
			fontBgColor := bgColor;
			fontChanged := TRUE
		END SetBgColor;
		
		PROCEDURE SetVerticalOffset* (voff : LONGINT);
		BEGIN
			IF w # NIL THEN w.Update END;
			fontVOff := voff;
			fontChanged := TRUE
		END SetVerticalOffset;
		
		PROCEDURE AddObject*(obj : ANY);
		VAR op : AosTexts.ObjectPiece;
		BEGIN
			IF w # NIL THEN w.Update END;
			NEW(op); op.object := obj;
			text.AcquireWrite;
			text.InsertPiece(text.GetLength(), op);
			text.ReleaseWrite;
		END AddObject;	
				
	END TextWriter;

TYPE
	LongintArray = POINTER TO ARRAY OF LONGINT;	
	Operation = RECORD op, pos, len : LONGINT END; 
	Operations  = POINTER TO ARRAY OF Operation;
	TextPositionKeeper* = OBJECT(AosTexts.TextPosition);
	VAR positions : LongintArray;
		nofPositions : LONGINT;
		operations : Operations;
		nofOperations, nofDeleted : LONGINT;

		PROCEDURE &New*(t : AosTexts.Text);
		BEGIN
			New^(t);
			NEW(positions, 256); NEW(operations, 256);
			nofOperations := 0; nofPositions := 0; nofDeleted := 0
		END New;
		
		PROCEDURE GrowOperations;
		VAR i : LONGINT;
			t : Operations;
		BEGIN
			NEW(t, nofOperations * 2);
			FOR i := 0 TO nofOperations - 1 DO t[i] := operations[i] END;
			operations := t
		END GrowOperations;
		
		PROCEDURE Cleanup;
		VAR i, j, p, op, pos : LONGINT;
		BEGIN
			IF nofOperations = 0 THEN RETURN END;
			FOR i := 0 TO nofPositions - 1 DO
				p := positions[i];
				IF p >= 0 THEN
					FOR j := 0 TO nofOperations - 1 DO
						op := operations[j].op; pos := operations[j].pos;
						IF (p >= pos) & (op = AosTexts.OpInsert) THEN INC(p, operations[j].len)
						ELSIF (p >= pos) & (p <= pos + operations[j].len)  & (op = AosTexts.OpDelete) THEN p := pos
						ELSIF (p > pos) & (op = AosTexts.OpDelete) THEN DEC(p, operations[j].len);
						END
					END;
					IF p < 0 THEN p := 0 END;
					positions[i] := p
				END
			END;
			nofOperations := 0
		END Cleanup;
		
		(** Listens for text changes *)
		PROCEDURE Changed*(op, pos, len :  LONGINT);
		CONST MaxOperations = 4096;
		BEGIN
			IF nofOperations > MaxOperations THEN Cleanup END;
			IF nofOperations >=  LEN(operations) THEN GrowOperations END;
			operations[nofOperations].op := op;
			operations[nofOperations].pos := pos;
			operations[nofOperations].len := len;
			INC(nofOperations)
		END Changed;
	
		PROCEDURE GrowPositions;
		VAR i : LONGINT;
			t : LongintArray;
		BEGIN
			NEW(t, nofPositions * 2);
			FOR i := 0 TO nofPositions - 1 DO t[i] := positions[i] END;
			positions := t
		END GrowPositions;
		
		PROCEDURE DeletePos*(index : LONGINT);
		BEGIN
			positions[index] := -1; 
			INC(nofDeleted)
		END DeletePos;
		
		PROCEDURE AddPos*(pos : LONGINT) : LONGINT;
		VAR i  : LONGINT;
		BEGIN
			ASSERT(pos >= 0);
			Cleanup;
			IF nofDeleted > 0 THEN
				i := 0; WHILE (i < nofPositions) & (positions[i] >= 0) DO INC(i) END;
				ASSERT(i < nofPositions);
				positions[i] := pos; 
				DEC(nofDeleted);
				RETURN i
			ELSE
				IF nofPositions >= LEN(positions) THEN GrowPositions END;
				positions[nofPositions] := pos;
				INC(nofPositions);
				RETURN nofPositions - 1 
			END
		END AddPos;
		
		(** throw away all positions *)
		PROCEDURE Clear*;
		BEGIN
			nofPositions := 0; nofOperations := 0
		END Clear;
		
		(** Returns position in elements from the text start *)
		PROCEDURE GetPos*(index : LONGINT):LONGINT;
		BEGIN
			Cleanup;
			RETURN positions[index]
		END GetPos;
		
		(** Change the position associated with index*)
		PROCEDURE SetPos*(index, pos : LONGINT);
		BEGIN
			Cleanup;
			positions[index] := pos
		END SetPos;		
	END TextPositionKeeper;
	
	OberonDecoder = OBJECT(AosCodecs.TextDecoder)
	VAR errors : BOOLEAN; 
		in : AosIO.Reader;
		text : AosTexts.Text;
		buffer : Utilities.Buffer;
		string: Utilities.String;
		reader, sreader : AosIO.StringReader;
		
		PROCEDURE Error(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("Oberon Decoder Error: ");
			AosOut.String(x); AosOut.Ln;
			errors := TRUE 
		END Error;

		PROCEDURE Log(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("Oberon Decoder Info: ");
			AosOut.String(x); AosOut.Ln;
		END Log;
		
		PROCEDURE LoadLibrary(buf: Utilities.Buffer; pos:LONGINT; VARflen:LONGINT);
		BEGIN
		END LoadLibrary;
		
		PROCEDURE IndexToColor(index: LONGINT): LONGINT;
		BEGIN
			RETURN
					ASH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, index) * {5..7}), 23-7) +
					ASH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, index) * {2..4}), 15-4) +
					ASH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, index) * {0..1}), 7-1)
		END IndexToColor;
		
		PROCEDURE InsertPiece(ofs, len : LONGINT; attr : AosTexts.Attributes);
		VAR i, j, m : LONGINT; ch, last : CHAR; tempUCS32 : ARRAY 1024 OF Char32;
			oldpos : LONGINT;
		BEGIN
			m := LEN(tempUCS32) - 1;
			sreader.SetPos(ofs);
			oldpos := text.GetLength();
			FOR j := 0 TO len - 1 DO
				ch := sreader.Get();	
				IF i = m  THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
				IF (last # CR) OR (ch # LF) THEN
					IF ch = CR THEN tempUCS32[i] := ORD(LF)
					ELSE tempUCS32[i] := OberonToUni(ORD(ch))
					END;	
					INC(i)
				END;	
				last := ch
			END;
			tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);
			IF attr # NIL THEN text.SetAttributes(oldpos, len, attr) END	
		END InsertPiece;			
		
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		CONST DocBlockId = 0F7X; OldTextBlockId = 1X; TextBlockId = 0F0X; OldTextSpex = 0F0X; TextSpex = 1X; LibBlockId = 0DBX;
		VAR propagate: BOOLEAN;
			ch: CHAR;
			tempInt : LONGINT;
			buflen: LONGINT;
			
			attr : AosTexts.Attributes;
			tattr : AosTexts.FontInfo;			
			fonts : ARRAY 256 OF AosTexts.FontInfo;
			col: SHORTINT;
			voff: SHORTINT;
			lib :SHORTINT;
			type, tag: CHAR;
			len, flen, n, off, hlen, tlen, pos, templen: LONGINT;
			x, y, w, h: INTEGER;
			temp: ARRAY 4096 OF CHAR;
			name, lName: ARRAY 32 OF CHAR;
			oberonColors : ARRAY 16 OF LONGINT;
		BEGIN
			errors := FALSE;
			res := -1;
			IF in = NIL THEN Error("Input Stream is NIL"); RETURN; END;
			SELF.in := in;
			
			(* write stream into buffer for further processing *)
			NEW(buffer, 64 * 1024);
			REPEAT
				in.Bytes(temp, 0, 4096, buflen);
				buffer.Add(temp, 0, buflen, propagate, res);		
			UNTIL (in.res # AosIO.Ok);
			
			(* define Oberon Colors *)
			oberonColors[0] := 0FFFFFFFFH; oberonColors[1] := 0FF0000FFH; oberonColors[2] := 000FF00FFH; oberonColors[3] := 00000FFFFH;
			oberonColors[4] := 0FF00FFFFH; oberonColors[5] := 0FFFF00FFH; oberonColors[6] := 000FFFFFFH; oberonColors[7] := 0AA0000FFH;
			oberonColors[8] := 000AA00FFH; oberonColors[9] := 00000AAFFH; oberonColors[10] := 0A6BCF3FFH; oberonColors[11] := 0008282FFH;
			oberonColors[12] := 08A8A8AFFH; oberonColors[13] := 0BEBEBEFFH; oberonColors[14] := 07B7B7BFFH; oberonColors[15] := 0000000FFH; 

			NEW(text);
			text.AcquireWrite;			

			string := buffer.GetString();
			NEW(reader, buffer.GetLength());
			reader.SetRaw(string^, 0, buffer.GetLength());
			ch := reader.Get();
		
			IF ch = DocBlockId THEN (* skip doc header *)
				reader.RawString(name); reader.RawInt(x); reader.RawInt(y); reader.RawInt(w); reader.RawInt(h);
				ch := reader.Get();
				IF ch = 0F7X THEN	(* skip meta info *)
					ch := reader.Get(); IF ch = 08X THEN reader.RawLInt(len); reader.Bytes(temp, 0, len, templen); ch := reader.Get(); END;
				END
			END;
			pos := reader.Pos();
			IF (ch = TextBlockId) OR (ch = OldTextBlockId) THEN
				type := reader.Get();
				reader.RawLInt(hlen);
				
				NEW(sreader, buffer.GetLength());
				tempInt := pos - 1 + hlen - 4;
				sreader.SetRaw(string^, 0, buffer.GetLength());
				sreader.SetPos(tempInt);
				sreader.RawLInt(tlen);
				
				IF (type = TextSpex) OR (type = OldTextSpex) THEN (*T.obs := NIL; flen := 0 *)
				ELSE (* NEW(T.obs); Objects.OpenLibrary(T.obs); *)
					tempInt  := pos - 1 + hlen + tlen;
					sreader.SetPos(tempInt);
					tag := sreader.Get();
	
					IF tag = LibBlockId THEN LoadLibrary(buffer, pos - 1 + hlen + tlen + 1, flen) END;
					INC(flen)
				END;
				n := 1;
				off := pos - 1 + hlen;
				WHILE reader.Pos() < pos - 1 + hlen - 5 DO
					reader.RawSInt(lib);
					IF lib = n THEN
						reader.RawString(lName);
						
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
					reader.RawSInt(col);
					reader.RawSInt(voff); voff := - voff;
					reader.RawLInt(len);
					IF len < 0 THEN AosOut.Enter; AosOut.String(" LoadAscii (T, f);"); AosOut.Int(len, 0); AosOut.Exit; RETURN END;
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
			ELSE Error("Not an Oberon File Format!");
			END;

			text.ReleaseWrite;
			res := 0
		END Open;
		
		PROCEDURE GetText*() : AosTexts.Text;
		BEGIN			
			RETURN text;
		END GetText;
		
		(* map oberon to unicode *)
		PROCEDURE OberonToUni(ch : LONGINT) : LONGINT;
		VAR ret : LONGINT;
		BEGIN
			
			CASE ch OF
				128 :	ret := 0C4H;
			|	129 :	ret:= 0D6H;
			|	130 :	ret:= 0DCH;
			|	131 :	ret:= 0E4H;
			|	132 :	ret:= 0F6H;
			|	133 :	ret:= 0FCH;
			|	134 :	ret:= 0E2H;
			|	135 :	ret:= 0EAH;
			|	136 :	ret:= 0EEH;
			|	137 :	ret:= 0F4H;
			|	138 :	ret:= 0FBH;
			|	139 :	ret:= 0E0H;
			|	140 :	ret:= 0E8H;
			|	141 :	ret:= 0ECH;
			|	142 :	ret:= 0F2H;
			|	143 :	ret:= 0F9H;
			|	144 :	ret:= 0E9H;
			|	145 :	ret:= 0EBH;
			|	146 :	ret:= 0EFH;
			|	147 :	ret:= 0E7H;
			|	148 :	ret:= 0E1H;
			|	149 :	ret:= 0F1H;
			|	150 :	ret:= 0DFH;
			|	151 :	ret:= 0A3H;
			|	152 :	ret:= 0B6H;
			|	153 :	ret:= 0C7H;
			|	154 :	ret:= 2030H;
			|	155 :	ret:= 2013H;
			ELSE
				ret := ch
			END;
			
			RETURN ret 
		END OberonToUni;
		
			
	END OberonDecoder;
	
	OberonEncoder = OBJECT(AosCodecs.TextEncoder)
	VAR out, w: AosIO.Writer;
		w2: AosIO.StringWriter;
		string: Utilities.String;
		buffer : Utilities.Buffer;
		oberonColors : ARRAY 16 OF LONGINT;
		fonts : ARRAY 256 OF AosTexts.FontInfo;
		font : AosTexts.FontInfo;
		nofFonts, hLen : LONGINT;
		firstPiece : BOOLEAN;
		voff: LONGINT;
		color : LONGINT;
		
		PROCEDURE Open*(out : AosIO.Writer);
		BEGIN
			IF out = NIL THEN AosOut.String("Oberon Encoder Error: output stream is NIL");
			ELSE SELF.out := out;
			END;
		END Open;
		
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
			w.RawLInt(len);
		END WritePiece;		

		PROCEDURE WriteText*(text : AosTexts.Text; VAR res : LONGINT);
		CONST TextBlockId = 0F0X; 
		VAR r: AosTexts.TextReader;
			ch :Char32;
			startPos, i, len, tempInt : LONGINT;

		BEGIN
			(* define Oberon colors *)
			oberonColors[0] := 0FFFFFFFFH; oberonColors[1] := 0FF0000FFH; oberonColors[2] := 000FF00FFH; oberonColors[3] := 00000FFFFH;
			oberonColors[4] := 0FF00FFFFH; oberonColors[5] := 0FFFF00FFH; oberonColors[6] := 000FFFFFFH; oberonColors[7] := 0AA0000FFH;
			oberonColors[8] := 000AA00FFH; oberonColors[9] := 00000AAFFH; oberonColors[10] := 0A6BCF3FFH; oberonColors[11] := 0008282FFH;
			oberonColors[12] := 08A8A8AFFH; oberonColors[13] := 0BEBEBEFFH; oberonColors[14] := 07B7B7BFFH; oberonColors[15] := 0000000FFH; 
			
			res := -1;
			text.AcquireRead;
			firstPiece := TRUE;
			NEW(r, text);
			NEW(buffer, 1024);
			w := buffer.GetWriter();
			nofFonts := 0;
					
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
						startPos := len;
					END
				END	
			UNTIL r.eot;
			WritePiece(len + 1 - startPos);
			w.Char(0X); (* ??? *)
			w.RawLInt(len); (* tLen ? *)
			w.Update;
			hLen := w.Pos();
				
			(* pure text ... *)
			r.SetPosition(0);
			FOR i := 0 TO text.GetLength() - 1 DO r.ReadCh(ch); IF ch = AosTexts.NewLineChar THEN ch := 0DH END;
				IF (ch >=0) & (ch < 256) THEN w.Char(CHR(UniToOberon(ch))) END 
			END;
			
			(* fixup header length *)
			w.Update;			
			string := buffer.GetString();
			NEW(w2, LEN(string));
			w2.Bytes(string^, 0, LEN(string));
			tempInt := w2.Pos();
			w2.SetPos(2);
			w2.RawLInt(hLen);
			w2.SetPos(tempInt); w2.Update;		

			(* write string to output stream *)
			NEW(string, text.GetLength()+hLen);
			w2.GetRaw(string^, len);
			out.Bytes(string^, 0, len); out.Update;

			text.ReleaseRead;
			res := 0		
		
		END WriteText;
		
		(* map unicode to oberon *)
		PROCEDURE UniToOberon(ch : LONGINT) : LONGINT;
		VAR ret : LONGINT;
		BEGIN
	
			CASE ch OF
				0C4H :	 ret := 128;
			|	0D6H :	 ret := 129;
			|	0DCH :	 ret := 130;
			|	0E4H :	 ret := 131;
			|	0F6H :	 ret := 132;
			|	0FCH :	 ret := 133;
			|	0E2H :	 ret := 134;
			|	0EAH :	 ret := 135;
			|	0EEH :	 ret := 136;
			|	0F4H :	 ret := 137;
			|	0FBH :	 ret := 138;
			|	0E0H :	 ret := 139;
			|	0E8H :	 ret := 140;
			|	0ECH :	 ret := 141;
			|	0F2H :	 ret := 142;
			|	0F9H :	 ret := 143;
			|	0E9H :	 ret := 144;
			|	0EBH :	 ret := 145;
			|	0EFH :	 ret := 146;
			|	0E7H :	 ret := 147;
			|	0E1H :	 ret := 148;
			|	0F1H :	 ret := 149;
			|	0DFH :	 ret := 150;
			|	0A3H :	 ret := 151;
			|	0B6H :	 ret := 152;
			|	0C7H :	 ret := 153;
			ELSE
				IF ch = 2030H THEN ret := 154
				ELSIF ch = 2013H THEN ret := 155
				ELSE ret := ch
				END
			END;
				
			RETURN ret	
		END UniToOberon;			
	
	END OberonEncoder;
	
	BluebottleDecoder* = OBJECT(AosCodecs.TextDecoder)
	VAR errors : BOOLEAN; 
		text : AosTexts.Text;
		doc : XML.Document;
		cont, tc, tc2 : XMLObjects.Enumerator; ptr : PTR; root : XML.Element; str : Utilities.String;
		o : AosTexts.ObjectPiece; attr: AosTexts.Attributes; fi : AosTexts.FontInfo;
		stylename, pstylename: ARRAY 64 OF CHAR;
		link : AosTexts.Link;
		
		PROCEDURE Error(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("Bluebottle Decoder Error: ");
			AosOut.String(x); AosOut.Ln;
			errors := TRUE 
		END Error;

		PROCEDURE Log(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("Bluebottle Decoder Info: ");
			AosOut.String(x); AosOut.Ln;
		END Log;	
		
		PROCEDURE GetUTF8Char(r : AosIO.Reader; VAR u : AosTexts.Char32; VAR pos : LONGINT) : BOOLEAN;
		VAR ch : ARRAY 8 OF CHAR; i : LONGINT;
		BEGIN
			ch[0] := r.Get(); INC(pos);
			FOR i := 1 TO ORD(UTF8Strings.CodeLength[ORD(ch[0])]) - 1 DO ch[i] := r.Get(); INC(pos) END;
			i := 0;
			RETURN UTF8Strings.DecodeChar(ch, i, u)
		END GetUTF8Char;
		
		PROCEDURE InsertPiece(charContent : XML.CDataSect);
		VAR i, m, tpos, res : LONGINT; ch, last : AosTexts.Char32; tempUCS32 : ARRAY 1024 OF AosTexts.Char32;
			oldpos, len : LONGINT;
			r, sr : AosIO.StringReader; token : ARRAY 256 OF CHAR;
			tempInt: LONGINT;
			buffer : Utilities.String;
			char : CHAR;
			cStyle : AosTexts.CharacterStyle;
			pStyle : AosTexts.ParagraphStyle;
		BEGIN
			m := LEN(tempUCS32) - 1;
			buffer := charContent.GetStr();
			NEW(r, LEN(buffer^));
			r.Set(buffer^);
			
			oldpos := text.GetLength();
			len := charContent.GetLength();
			tpos := 0;
			REPEAT
				IF GetUTF8Char(r, ch, tpos) THEN
					IF i = m  THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
					IF (last # ORD(CR)) OR (ch # ORD(LF)) THEN
						IF ch = ORD(CR) THEN tempUCS32[i] := ORD(LF) 
						ELSE tempUCS32[i] := ch
						END;
						INC(i)
					END;	
					last := ch;
				END
			UNTIL (tpos >= len) OR (r.res # AosIO.Ok);
			tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);
	
			(* get style from the System *)
			cStyle := AosTexts.GetCharacterStyleByName(stylename);
			pStyle := AosTexts.GetParagraphStyleByName(pstylename);
			
			(* set attributes to emulate style in non-style supporting applications *)
			IF (attr = NIL) THEN NEW(attr); END;
			attr.voff := 0; attr.color := 0000000FFH; attr.bgcolor := 000000000H;
			IF (attr.fontInfo = NIL) THEN NEW(fi); attr.fontInfo := fi; END;
			attr.fontInfo.name := "Oberon"; attr.fontInfo.size := 10; attr.fontInfo.style := {};
			IF (stylename = "Bold") THEN attr.fontInfo.style := {0};
			ELSIF (stylename = "Highlight") THEN attr.fontInfo.style := {1};
			ELSIF (stylename = "Assertion") THEN attr.fontInfo.style := {0}; attr.color := 00000FFFFH;
			ELSIF (stylename = "Debug") THEN attr.color := 00000FFFFH;
			ELSIF (stylename = "Lock") THEN attr.color := 0FF00FFFFH;
			ELSIF (stylename = "Stupid") THEN attr.color := 0FF0000FFH;
			ELSIF (stylename = "Comment") THEN attr.color := 0808080FFH;
			ELSIF (stylename = "Preferred") THEN attr.fontInfo.style := {0}; attr.color := 0800080FFH;
			ELSIF Utilities.Match("AdHoc*", stylename) THEN
				NEW(sr, LEN(stylename)); sr.Set(stylename);
				sr.SkipWhitespace; sr.Token(token);												(* AdHoc *)
				sr.SkipWhitespace; sr.Token(token); COPY(token, attr.fontInfo.name); 				(* family *)
				sr.SkipWhitespace; sr.Token(token); Utilities.StrToInt(token, attr.fontInfo.size);		(* size *)
				sr.SkipWhitespace; sr.Token(token); Utilities.StrToInt(token, res); 					(* style *)
				IF (res = 0) THEN attr.fontInfo.style := {};
				ELSIF (res = 1) THEN attr.fontInfo.style := {0};
				ELSIF (res = 2) THEN attr.fontInfo.style := {1};
				ELSIF (res = 3) THEN attr.fontInfo.style := {0,1};
				ELSE attr.fontInfo.style := {};
				END;
				sr.SkipWhitespace; sr.Token(token); Utilities.StrToInt(token, attr.voff);				(* voff *)
				sr.SkipWhitespace; sr.Token(token); Utilities.HexStrToInt(token, attr.color, res);		(* color *)
				sr.SkipWhitespace; sr.Token(token); Utilities.HexStrToInt(token, attr.bgcolor, res);	(* bgcolor *)
				
				(* add Ad-Hoc style to the System in case it was not present already *)
				IF cStyle = NIL THEN
					NEW(cStyle);
					COPY(stylename, cStyle.name);
					COPY(attr.fontInfo.name, cStyle.family);
					cStyle.size := FP1616.FloatToFixp(attr.fontInfo.size);
					cStyle.style := attr.fontInfo.style;
					cStyle.baselineShift := attr.voff;
					cStyle.color := attr.color;
					cStyle.bgColor := attr.bgcolor;
					AosTexts.AddCharacterStyle(cStyle);
				END;
			ELSE
				(* Get the attributes from the style for compatibility *)
				IF (cStyle # NIL) THEN attr := StyleToAttribute(cStyle)
				ELSE token := "Style not present in System: "; Utilities.Append(token, stylename); Error(token); END;
			END;
			text.SetAttributes(oldpos, text.GetLength()-oldpos, attr.Clone());
			
			(* set the style for style supporting applications *)
			text.SetCharacterStyle(oldpos, text.GetLength()-oldpos, cStyle);

			(* Get AdHoc paragraph style & add to system *)
			IF Utilities.Match("AdHoc*", pstylename) & (pStyle = NIL) THEN
				NEW(pStyle);
				NEW(sr, LEN(pstylename)); sr.Set(pstylename);
				sr.SkipWhitespace; sr.Token(token); COPY(pstylename, pStyle.name);														(* AdHoc *)	
				sr.SkipWhitespace; sr.Token(token); Utilities.StrToInt(token, tempInt); pStyle.alignment := tempInt;							(* alignment *)
				sr.SkipWhitespace; sr.Token(token); Utilities.StrToInt(token, tempInt); pStyle.firstIndent := FP1616.FloatToFixp(tempInt);		(* first Indent *)
				sr.SkipWhitespace; sr.Token(token); Utilities.StrToInt(token, tempInt); pStyle.leftIndent := FP1616.FloatToFixp(tempInt);		(* left Indent *)
				sr.SkipWhitespace; sr.Token(token); Utilities.StrToInt(token, tempInt); pStyle.rightIndent := FP1616.FloatToFixp(tempInt);	(* right Indent *)
				sr.SkipWhitespace; sr.Token(token); Utilities.StrToInt(token, tempInt); pStyle.spaceBefore := FP1616.FloatToFixp(tempInt);	(* space above *)
				sr.SkipWhitespace; sr.Token(token); Utilities.StrToInt(token, tempInt); pStyle.spaceAfter := FP1616.FloatToFixp(tempInt);		(* space below *)
				sr.SkipWhitespace; char := sr.Peek(); IF (char = "t") THEN sr.SkipBytes(1); sr.RawString(token); COPY(token, pStyle.tabStops); END; (* tabstops *)
				AosTexts.AddParagraphStyle(pStyle);
			END;
			
			(* set the paragraph style *)
			IF (pStyle # NIL) THEN text.SetParagraphStyle(oldpos, text.GetLength()-oldpos, pStyle) END;
			(* set the link *)
			text.SetLink(oldpos, text.GetLength()-oldpos, link);	
			
		END InsertPiece;
		
		PROCEDURE InsertChar(pos : LONGINT; ch : AosTexts.Char32);
		VAR bufUCS32 : ARRAY 2 OF AosTexts.Char32;
			oldpos : LONGINT;
			cStyle : AosTexts.CharacterStyle;
			pStyle : AosTexts.ParagraphStyle;
		BEGIN
			bufUCS32[0] := ch; bufUCS32[1] := 0;
			oldpos := text.GetLength();
			text.InsertUCS32(pos, bufUCS32);					 (* cursor moves automagically *)
			
			(* get style from the System *)
			cStyle := AosTexts.GetCharacterStyleByName(stylename);
			pStyle := AosTexts.GetParagraphStyleByName(pstylename);
			(* set the character style *)
			IF (cStyle # NIL) THEN text.SetCharacterStyle(oldpos, text.GetLength()-oldpos, cStyle) END;
			(* set the paragraph style *)
			IF (pStyle # NIL) THEN text.SetParagraphStyle(oldpos, text.GetLength()-oldpos, pStyle) END;
			(* set the link *)
			IF (link # NIL) THEN text.SetLink(oldpos, text.GetLength()-oldpos, link); AosOut.String("bonk"); END;	
		END InsertChar;
		
		PROCEDURE MalformedXML(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
		BEGIN
			Error(msg);
		END MalformedXML;
		
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		VAR
			scanner : XMLScanner.Scanner; parser : XMLParser.Parser;
			d : XML.Document;
		BEGIN
			res := -1;
			errors := FALSE;
			IF in = NIL THEN Error("Input Stream is NIL"); RETURN; END;
			NEW(scanner, in); NEW(parser, scanner);
			parser.elemReg := WMComponents.registry;
			parser.reportError := MalformedXML;
			d := parser.Parse();
			
			IF errors THEN RETURN END;
			OpenXML(d);
			res := 0;
		END Open;
		
		PROCEDURE OpenXML*(d : XML.Document);
		VAR lp : AosTexts.LabelPiece;
		BEGIN
			errors := FALSE;
			doc := d;
			NEW(text);
			text.AcquireWrite;			

			NEW(attr);		
			
			root := doc.GetRoot();
			cont := root.GetContents(); cont.Reset();
			WHILE cont.HasMoreElements() DO
				ptr := cont.GetNext();
				IF ptr IS XML.Element THEN 
					str := ptr(XML.Element).GetName();
					IF (str # NIL) & (str^ = "Label") THEN
						str := ptr(XML.Element).GetAttributeValue("name"); 
						IF str # NIL THEN NEW(lp); lp.label := Utilities.NewString(str^); text.InsertPiece(text.GetLength(), lp) END;			
					ELSIF (str # NIL) & (str^ = "Paragraph") THEN
						tc := ptr(XML.Element).GetContents(); tc.Reset();
						str := ptr(XML.Element).GetAttributeValue("style"); 
						IF str # NIL THEN COPY(str^, pstylename); END;
						WHILE tc.HasMoreElements() DO
							ptr := tc.GetNext();
							IF ptr IS XML.Element THEN
								str := ptr(XML.Element).GetName();
								IF (str # NIL) & (str^ = "Label") THEN
									str := ptr(XML.Element).GetAttributeValue("name"); 
									IF str # NIL THEN NEW(lp); lp.label := Utilities.NewString(str^); text.InsertPiece(text.GetLength(), lp) END;	
								ELSIF (str # NIL) & (str^ = "Span") THEN
									tc2 := ptr(XML.Element).GetContents(); tc2.Reset();
									str := ptr(XML.Element).GetAttributeValue("style"); IF str # NIL THEN COPY(str^, stylename); END;
									str := ptr(XML.Element).GetAttributeValue("link"); IF str # NIL THEN NEW(link, LEN(str^)); COPY(str^, link^); ELSE link := NIL; END;
									WHILE tc2.HasMoreElements() DO
										ptr := tc2.GetNext();
										IF ptr IS XML.CDataSect THEN InsertPiece(ptr(XML.CDataSect)) END;
									END;	
								ELSIF (str # NIL) & (str^ = "Object") THEN
									tc2 := ptr(XML.Element).GetContents(); tc2.Reset();
									IF tc2.HasMoreElements() THEN
										NEW(o); o.object := tc2.GetNext(); text.InsertPiece(text.GetLength(), o);
									END
								END
							END
						END;
						(* Insert a newline to finish paragraph *)	
						(* InsertChar(text.GetLength(), AosTexts.NewLineChar); *)	
					ELSIF (str # NIL) & (str^ = "Span") THEN
						COPY("Left", pstylename);
						tc := ptr(XML.Element).GetContents(); tc.Reset();
						str := ptr(XML.Element).GetAttributeValue("style"); IF str # NIL THEN COPY(str^, stylename); END;
						str := ptr(XML.Element).GetAttributeValue("link"); IF str # NIL THEN NEW(link, LEN(str^)); COPY(str^, link^); ELSE link := NIL; END;
						WHILE tc.HasMoreElements() DO
							ptr := tc.GetNext();
							IF ptr IS XML.CDataSect THEN InsertPiece(ptr(XML.CDataSect)) END;
						END	
					ELSIF (str # NIL) & (str^ = "Object") THEN
						tc := ptr(XML.Element).GetContents(); tc.Reset();
						IF tc.HasMoreElements() THEN
							NEW(o); o.object := tc.GetNext(); text.InsertPiece(text.GetLength(), o);
						END;
					END;
				END	
			END;
			
			text.ReleaseWrite;

		END OpenXML;
		
		PROCEDURE GetText*() : AosTexts.Text;
		BEGIN
			RETURN text;
		END GetText;

	END BluebottleDecoder;	
	
	BluebottleEncoder = OBJECT(AosCodecs.TextEncoder)
	VAR out: AosIO.Writer;
		ch :AosTexts.Char32;
		r: AosTexts.TextReader;
		changed, pchanged, pOpen : BOOLEAN;
		stylename, pstylename: ARRAY 256 OF CHAR;
		cStyle: AosTexts.CharacterStyle;
		pStyle: AosTexts.ParagraphStyle;
		link : AosTexts.Link;
	(*	hStyle: AosTexts.HighlightStyle;             <-- TO DO
	*)			
		(* Attributes attributes *)
		family, dfFamily : ARRAY 64 OF CHAR;
		size, dfSize : LONGINT;
		style, dfStyle : LONGINT;							(* 0 = regular; 1 = bold; 2 = italic; 3 = bold-italic *)
		voff, dfVoff : LONGINT;
		color, dfColor : LONGINT;
		bgcolor, dfBgcolor : LONGINT;
		
		(* Set the default  attribute values *)
		PROCEDURE Init;
		BEGIN
			dfFamily := "Oberon";
			dfSize := 10;
			dfStyle := 0;
			dfVoff := 0;
			dfColor := 0000000FFH;
			dfBgcolor := 000000000H;
		END Init;
		
		(* extract the attributes from the current textreader *)
		PROCEDURE RetrieveAttributes;
		VAR tempstring, string: ARRAY 128 OF CHAR;
		BEGIN
			(* Get Character Style if any *)
			IF (r.cstyle # NIL) THEN
				cStyle := r.cstyle;
				COPY(cStyle.name, stylename);
				COPY(cStyle.family, family);
				size := cStyle.size;
				IF (cStyle.style = {}) THEN style := 0; ELSIF (cStyle.style = {0}) THEN style := 1; ELSIF (cStyle.style = {1}) THEN style := 2; ELSIF (cStyle.style = {0,1}) THEN style := 3; ELSE style := 0; END;
				voff := cStyle.baselineShift;
				color := cStyle.color;
				bgcolor := cStyle.bgColor;
			ELSE
				cStyle := NIL;
				(* Get attributes from char *)
				IF (r.font = NIL) THEN								(* Fix missing values *)
					family := dfFamily;
					size := dfSize;
					style := dfStyle;
				ELSE
					COPY(r.font.name, family);
					size := r.font.size;
					IF (r.font.style = {}) THEN style := 0; ELSIF (r.font.style = {0}) THEN style := 1; ELSIF (r.font.style = {1}) THEN style := 2; ELSIF (r.font.style = {0,1}) THEN style := 3; ELSE style := 0; END;
				END;
				voff := r.voff;
				color := r.color;
				bgcolor := r.bgcolor;
				
				(* Find appropriate style *)
				IF (color = 0000000FFH) & (style = 0) THEN stylename := "Normal"
				ELSIF (color = 0000000FFH) & (style = 1) THEN stylename := "Bold"
				ELSIF (color = 0000000FFH) & (style = 2) THEN stylename := "Highlight"
				ELSIF ((color = 00000FFFFH) OR (color = 00000AAFFH)) & (style = 1) THEN stylename := "Assertion"
				ELSIF (color = 00000FFFFH) & (style = 0) THEN stylename := "Debug"
				ELSIF (color = 0FF00FFFFH) & (style = 0) THEN stylename := "Lock"
				ELSIF (color = 0FF0000FFH) & (style = 0) THEN stylename := "Stupid"
				ELSIF ((color = 0808080FFH) OR (color = 08A8A8AFFH)) & (style = 0) THEN stylename := "Comment"
				ELSIF (color = 0800080FFH) & (style = 1) THEN stylename := "Preferred"
				ELSE
					tempstring := "AdHoc"; Utilities.Append(tempstring, " ");
					Utilities.Append(tempstring, family); Utilities.Append(tempstring, " ");
					Utilities.IntToStr(size, string); Utilities.Append(tempstring, string); Utilities.Append(tempstring, " ");
					Utilities.IntToStr(style, string); Utilities.Append(tempstring, string); Utilities.Append(tempstring, " ");
					Utilities.IntToStr(voff, string); Utilities.Append(tempstring, string); Utilities.Append(tempstring, " ");
					Utilities.IntToHexStr(color,7, string); Utilities.Append(tempstring, string); Utilities.Append(tempstring, " ");
					Utilities.IntToHexStr(bgcolor,7, string); Utilities.Append(tempstring, string);
					COPY(tempstring, stylename);
					(* AosOut.String("Writing Ad-hoc Style: "); AosOut.String(tempstring);  AosOut.Ln; *)
				END;
			END;
			(* Get Paragraph Style if any *)
			IF (r.pstyle # NIL) THEN
				pStyle := r.pstyle;
				COPY(pStyle.name, pstylename)
			ELSE
				pStyle := NIL;
				COPY("", pstylename)		
			END;
			(* Get Link if any *)
			IF (r.link # NIL) THEN
				link := r.link;
			ELSE
				link := NIL;
			END;
								
		END RetrieveAttributes;
		
		PROCEDURE PrintAttributes;
		BEGIN
			AosOut.String("# family: "); AosOut.String(family);  AosOut.Ln;
			AosOut.String("# size: "); AosOut.Int(size, 0);  AosOut.Ln;
			AosOut.String("# style: "); AosOut.Int(style, 0);  AosOut.Ln;
			AosOut.String("# voff: "); AosOut.Int(voff, 0);  AosOut.Ln;
			AosOut.String("# color: "); AosOut.Hex(color, 0);  AosOut.Ln;
			AosOut.String("# bgcolor: "); AosOut.Hex(bgcolor, 0);  AosOut.Ln;
		END PrintAttributes;
		
		(* Return TRUE if current textreader attributes don't match the chached one *)
		PROCEDURE CompareAttributes():BOOLEAN;
		VAR tempstyle: LONGINT;
			isEqual : BOOLEAN;
		BEGIN
			IF (link = r.link) THEN	
				IF r.cstyle # NIL THEN
					isEqual := (stylename = r.cstyle.name);
					RETURN ~isEqual;
				ELSE
					IF (r.font = NIL) THEN
						isEqual := (family = dfFamily) & (size = dfSize) & (style = dfStyle) & (voff = r.voff) & (color = r.color) & (bgcolor = r.bgcolor);
					ELSE
						IF (r.font.style = {}) THEN tempstyle := 0; ELSIF (r.font.style = {0}) THEN tempstyle := 1; ELSIF (r.font.style = {1}) THEN tempstyle := 2; ELSIF (r.font.style = {0,1}) THEN tempstyle := 3; ELSE tempstyle := 0; END;					
						isEqual := (family = r.font.name) & (size = r.font.size) & (style = tempstyle) & (voff = r.voff) & (color = r.color) & (bgcolor = r.bgcolor);
					END;
					RETURN ~isEqual;	
				END;
			ELSE
				RETURN TRUE;
			END			
		END CompareAttributes;
		
		(* Return TRUE if current textreader paragraphstyle doesn't match the chached one *)
		PROCEDURE CompareParagraphs(): BOOLEAN;
		VAR isEqual : BOOLEAN;
		BEGIN
			IF r.pstyle # NIL THEN
				isEqual := (pstylename = r.pstyle.name);	
				RETURN ~isEqual
			ELSIF (r.pstyle = NIL) & (pStyle = NIL) THEN
				RETURN FALSE;
			ELSE
				RETURN TRUE;
			END;			
		END CompareParagraphs;
		
		PROCEDURE WriteParagraph(name : ARRAY OF CHAR);
		BEGIN
			pOpen := TRUE;
			out.String("<Paragraph ");
			out.String('style="'); out.String(name); out.String('"');
			out.String(">")			
		END WriteParagraph;
		
		PROCEDURE CloseParagraph;
		BEGIN
			IF pOpen THEN
				out.String("</Paragraph>");
				pOpen := FALSE;
			END;
		END CloseParagraph;
		
		PROCEDURE WriteSpan(name: ARRAY OF CHAR);
		BEGIN
			out.String("<Span ");
			out.String('style="'); out.String(name); out.String('"');
			IF link # NIL THEN
				out.String(' link="'); out.String(link^); out.String('"');
			END;
			out.String("><![CDATA[")
		END WriteSpan;	
		
		PROCEDURE CloseSpan;
		BEGIN
			out.String("]]></Span>");
		END CloseSpan;
		
		PROCEDURE WriteObject(o : ANY);
		BEGIN
			out.Ln;
			out.String("<Object>");
			IF (o # NIL) & (o IS XML.Element) THEN
				o(XML.Element).Write(out, 1);
			END;
			out.String("</Object>");out.Ln;
		END WriteObject;
		
		PROCEDURE WriteLabel(label: ARRAY OF CHAR);
		BEGIN
			out.String("<Label ");
			out.String('name="'); out.String(label); out.String('"/>');	
		END WriteLabel;
			
		PROCEDURE Open*(out : AosIO.Writer);
		BEGIN
			IF out = NIL THEN AosOut.String("Bluebottle Encoder Error: output stream is NIL");
			ELSE SELF.out := out;
			END;
		END Open;
		
		PROCEDURE WriteText*(text : AosTexts.Text; VAR res : LONGINT);
		VAR buf : Utilities.String; rbuf : ARRAY 4 OF CHAR; str : ARRAY 8 OF CHAR; counter, i, j : LONGINT;
		BEGIN
			Init;
			res := 1;

			out.String('<?xml version="1.0" encoding="UTF-8"?>'); out.Ln;
			out.String('<?bluebottle format version="0.1" ?>'); out.Ln;
			out.String('<?xml-stylesheet type="text/xsl" href="http://bluebottle.ethz.ch/bluebottle.xsl" ?>'); out.Ln;
			out.String("<Text>"); out.Ln;
			text.AcquireRead;
			NEW(r, text); NEW(buf, text.GetLength()+1);
			
			r.ReadCh(ch); counter := 0; COPY("   ", rbuf);
			IF (ch = AosTexts.LabelChar) THEN WriteLabel(r.object(AosTexts.LabelPiece).label^) END;
			
			RetrieveAttributes;
			(* PrintAttributes; *)
			
			IF (pStyle # NIL) & (pstylename # "Left") THEN WriteParagraph(pstylename) END;
			WriteSpan(stylename);
			WHILE ~r.eot DO

				i := 0;
				IF UTF8Strings.EncodeChar(ch, str, i) THEN			
					FOR j := 0 TO i-1 DO
						buf[counter+j] := str[j];
					END;
					(* CDATA escape fix *)
					rbuf[0] := rbuf[1]; rbuf[1] := rbuf[2]; rbuf[2] := CHR(ch);
					IF (rbuf = "]]>") THEN
						buf[counter] := 0X;
						out.String(buf^); out.String("]]><![CDATA["); counter := 0;
						buf[counter] := CHR(ch);					
					END;
					INC(counter, i);
				END;
			
				r.ReadCh(ch);
				
				
				IF ch = AosTexts.ObjectChar THEN
					buf[counter] := 0X; out.String(buf^); counter := 0; COPY("   ", rbuf);
					CloseSpan;			
					WriteObject(r.object);

					RetrieveAttributes;
					IF ~r.eot THEN WriteSpan(stylename) END
				ELSIF ch = AosTexts.LabelChar THEN
					buf[counter] := 0X; out.String(buf^); counter := 0; COPY("   ", rbuf);
					CloseSpan;	
					WriteLabel(r.object(AosTexts.LabelPiece).label^);

					RetrieveAttributes;
					IF ~r.eot THEN WriteSpan(stylename) END				
				ELSE
					pchanged := CompareParagraphs();
					changed := CompareAttributes();
					IF pchanged THEN
						RetrieveAttributes;
						IF ~r.eot THEN
							buf[counter] := 0X; out.String(buf^); counter := 0; COPY("   ", rbuf);
							CloseSpan;
							CloseParagraph;
							IF (pStyle # NIL) & (pstylename # "Left") THEN WriteParagraph(pstylename) END;
							WriteSpan(stylename)
						END
					ELSIF changed THEN
						RetrieveAttributes;
						IF ~r.eot THEN
							buf[counter] := 0X; out.String(buf^); counter := 0; COPY("   ", rbuf);
							CloseSpan; WriteSpan(stylename)
						END
					END
				END
			END;
			
			buf[counter] := 0X;
			out.String(buf^);
			CloseSpan; out.Ln;
			CloseParagraph; out.Ln;
			out.String("</Text>"); out.Ln;
			out.Update;
			text.ReleaseRead;
			res := 0		
		
		END WriteText;
	
	END BluebottleEncoder;
	
	UTF8Decoder = OBJECT(AosCodecs.TextDecoder)
	VAR errors : BOOLEAN; 
		in : AosIO.Reader;
		text : AosTexts.Text;
		
		PROCEDURE Error(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("UTF-8 Decoder Error: ");
			AosOut.String(x); AosOut.Ln;
			errors := TRUE 
		END Error;

		PROCEDURE Log(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("UTF-8 Decoder Info: ");
			AosOut.String(x); AosOut.Ln;
		END Log;		
		
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		VAR i, m: LONGINT;
			tempUCS32 : ARRAY 1024 OF Char32;
			ch, last : AosTexts.Char32;
		BEGIN
			errors := FALSE;
			res := -1;
			IF in = NIL THEN Error("Input Stream is NIL"); RETURN; END;
			SELF.in := in;

			NEW(text);
			text.AcquireWrite;			
			m := LEN(tempUCS32) - 1;
			i := 0;
			REPEAT
				IF GetUTF8Char(in, ch) THEN
					IF i = m  THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
					IF (last # ORD(CR)) OR (ch # ORD(LF)) THEN
						IF ch = ORD(CR) THEN tempUCS32[i] := ORD(LF) 
						ELSE tempUCS32[i] := ch
						END;
						INC(i)
					END;	
					last := ch
				END	
			UNTIL (in.res # AosIO.Ok);
			tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);
			
			res := 0;
			text.ReleaseWrite	
		END Open;
		
		PROCEDURE GetText*() : AosTexts.Text;
		BEGIN
			RETURN text;
		END GetText;
	
	END UTF8Decoder;
	
	UTF8Encoder = OBJECT(AosCodecs.TextEncoder)
	VAR out: AosIO.Writer;

		PROCEDURE Open*(out : AosIO.Writer);
		BEGIN
			IF out = NIL THEN AosOut.String("UTF-8 Encoder Error: output stream is NIL");
			ELSE SELF.out := out;
			END;
		END Open;
		
		PROCEDURE WriteText*(text : AosTexts.Text; VAR res : LONGINT);
		VAR r : AosTexts.TextReader; ch : AosTexts.Char32; i, p : LONGINT; resstr : ARRAY 7 OF CHAR;
		BEGIN
			res := -1;
			text.AcquireRead;
			
			NEW(r, text);
			FOR i := 0 TO text.GetLength() - 1 DO 
				r.ReadCh(ch); p := 0;
				IF (ch > 0) & UTF8Strings.EncodeChar(ch, resstr, p) THEN out.String(resstr) END
			END; 
			out.Update;
		
			text.ReleaseRead;
			res := 0;
		END WriteText;
	
	END UTF8Encoder;
	
	ISO88591Decoder = OBJECT(AosCodecs.TextDecoder)
	VAR errors : BOOLEAN; 
		in : AosIO.Reader;
		text : AosTexts.Text;
		
		PROCEDURE Error(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("ISO8859-1 Decoder Error: ");
			AosOut.String(x); AosOut.Ln;
			errors := TRUE 
		END Error;

		PROCEDURE Log(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("ISO8859-1 Decoder Info: ");
			AosOut.String(x); AosOut.Ln;
		END Log;		
		
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		VAR i, m: LONGINT;
			tempUCS32 : ARRAY 1024 OF Char32;
			ch, last : CHAR;
		BEGIN
			errors := FALSE;
			res := -1;
			IF in = NIL THEN Error("Input Stream is NIL"); RETURN; END;
			SELF.in := in;

			NEW(text);
			text.AcquireWrite;			
			m := LEN(tempUCS32) - 1;
			i := 0;
			REPEAT
				in.Char(ch);
				IF i = m  THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
				IF (last # CR) OR (ch # LF) THEN
					IF ch = CR THEN tempUCS32[i] := ORD(LF)
					ELSE tempUCS32[i] := ORD(ch)
					END;	
					INC(i)
				END;	
				last := ch	
			UNTIL (in.res # AosIO.Ok);
			tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);
			res := 0;
			text.ReleaseWrite	
		END Open;
		
		PROCEDURE GetText*() : AosTexts.Text;
		BEGIN
			RETURN text;
		END GetText;
	
	END ISO88591Decoder;
	
	ISO88591Encoder = OBJECT(AosCodecs.TextEncoder)
	VAR out: AosIO.Writer;

		PROCEDURE Open*(out : AosIO.Writer);
		BEGIN
			IF out = NIL THEN AosOut.String("ISO8859-1 Encoder Error: output stream is NIL");
			ELSE SELF.out := out;
			END;
		END Open;
		
		PROCEDURE WriteText*(text : AosTexts.Text; VAR res : LONGINT);
		VAR r : AosTexts.TextReader; ch : AosTexts.Char32; i : LONGINT;		
		BEGIN
			res :=  -1;
			text.AcquireRead;
			NEW(r, text);
			FOR i := 0 TO text.GetLength() - 1 DO 
				r.ReadCh(ch);
				IF (ch >= 0) & (ch < 256) THEN out.Char(CHR(ch)) END
			END; 
			out.Update;		
			text.ReleaseRead;			
			res := 0;
		END WriteText;
	
	END ISO88591Encoder;		

	HEXDecoder = OBJECT(AosCodecs.TextDecoder)
	VAR errors : BOOLEAN; 
		in : AosIO.Reader;
		text : AosTexts.Text;
		
		PROCEDURE Error(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("HEX Decoder Error: ");
			AosOut.String(x); AosOut.Ln;
			errors := TRUE 
		END Error;

		PROCEDURE Log(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("HEX Decoder Info: ");
			AosOut.String(x); AosOut.Ln;
		END Log;		
		
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		VAR i, j, m : LONGINT;
			tempUCS32 : ARRAY 1057 OF Char32; (* 1025 *)
			ch : CHAR;
			byte : ARRAY 3 OF CHAR;
			attr: AosTexts.Attributes; fi : AosTexts.FontInfo;
		BEGIN
			errors := FALSE;
			res := -1;
			IF in = NIL THEN Error("Input Stream is NIL"); RETURN; END;
			SELF.in := in;

			NEW(text); NEW(attr); NEW(fi);
			fi.name := "Courier";
			fi.size := 10;
			fi.style := {};
			attr.voff := 0;
			attr.color := 0000000FFH;
			attr.bgcolor := 000000000H;
			attr.fontInfo := fi;
			text.AcquireWrite;			
			m := LEN(tempUCS32) - 1;
			i := 0; j := 0;
			REPEAT
				in.Char(ch);
				IF (i = m) THEN tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32); i := 0 END;
				Utilities.IntToHexStr(ORD(ch), 1, byte);
				tempUCS32[i] := ORD(byte[0]); INC(i);
				tempUCS32[i] := ORD(byte[1]); INC(i);
				tempUCS32[i] := ORD(TAB); INC(i);	(* formatting space *)
				INC(j);
				IF (j = 16) THEN j := 0; tempUCS32[i-1] := ORD(LF); END;
			UNTIL (in.res # AosIO.Ok);
			tempUCS32[i] := 0; text.InsertUCS32(text.GetLength(), tempUCS32);
			res := 0;
			text.SetAttributes(0, text.GetLength(), attr.Clone());
			text.ReleaseWrite	
		END Open;
		
		PROCEDURE GetText*() : AosTexts.Text;
		BEGIN
			RETURN text;
		END GetText;
		
	END HEXDecoder;
	
	HEXEncoder = OBJECT(AosCodecs.TextEncoder)
	VAR out: AosIO.Writer;

		PROCEDURE Open*(out : AosIO.Writer);
		BEGIN
			IF out = NIL THEN AosOut.String("HEX Encoder Error: output stream is NIL");
			ELSE SELF.out := out;
			END;
		END Open;
		
		PROCEDURE WriteText*(text : AosTexts.Text; VAR res : LONGINT);
		VAR r : AosTexts.TextReader; ch : AosTexts.Char32; i, j, k : LONGINT;
			byte : ARRAY 2 OF CHAR;
		BEGIN
			res :=  -1;
			text.AcquireRead;
			NEW(r, text);
			i := 0;
			FOR i := 0 TO text.GetLength() - 1 DO 
				r.ReadCh(ch);
				IF ((ch >= 48) & (ch <= 57)) OR ((ch >= 65) & (ch <= 70)) OR ((ch >= 97) & (ch <= 102)) THEN
					byte[j] := CHR(ch); INC(j);
				END;
				IF (j = 2) THEN j := 0; Utilities.HexStrToInt(byte, ch, k); out.Char(CHR(ch)); END;
			END; 
			out.Update;
		
			text.ReleaseRead;
			res := 0;
		END WriteText;
			
	END HEXEncoder;
		
						
(* ----------------------------------------------------------------------------------- *)	
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

(** Procedure to load File without explicit given Format - appropriate Format will be chosen automaticaly *)
PROCEDURE LoadAuto*(text: Text; fileName: ARRAY OF CHAR; VAR format, res: LONGINT);
VAR f : AosFS.File; re : AosFS.Reader; ri: AosFS.Rider; ch: CHAR; fstring: ARRAY 64 OF CHAR; i: LONGINT;
BEGIN
	(* AosOut.String("Auto Format.... "); AosOut.Ln; *)
	text.AcquireWrite;
	res := -1; format := -1;
	f := AosFS.Old(fileName);
	IF f # NIL THEN 
		AosFS.OpenReader(re, f, 0);
		f.Set(ri, 0);
		f.Read(ri, ch); i := ORD(ch);
		IF (i = 0F0H) OR (i = 0F7H) OR (i = 01H) THEN				(* Oberon File Format *)
			format := 0;										
		ELSIF (i = 03CH) THEN										(* possibly an XML, check further *)
			(* check IF just an XML or BB Format *)
			f.Set(ri, 0);
			AosFS.ReadString(ri, fstring);
			Utilities.UpperCase(fstring);
			IF Utilities.Match("<?XML VERSION=*", fstring) THEN
				IF Utilities.Match("*<?BLUEBOTTLE FORMAT*", fstring) THEN
					format := 1;										(* Bluebottle File Format *)
				ELSE
					format := 2;										(* XML - treat as UTF-8 *)
				END;
			ELSE
				format := 2;											(* Text/Other - treat as UTF-8 *)
			END;		
		ELSE														(* Neither Oberon nor XML/BB *)
			format := 2;
		END;	
	END;
	text.ReleaseWrite;
	(* call correct loader *)
	CASE format OF
	| 0:	LoadOberonText(text, fileName, res);
	| 1: LoadText(text, fileName, res);
	| 2: LoadUTF8(text, fileName, res);
	ELSE
		LoadUTF8(text, fileName, res)
	END
END LoadAuto;

(** Procedure to get decoder for the given file - appropriate Format will be chosen automaticaly *)
PROCEDURE DecodeAuto*( fileName: ARRAY OF CHAR; VAR format: ARRAY OF CHAR): AosCodecs.TextDecoder;
VAR f : AosFS.File; re : AosFS.Reader; ri: AosFS.Rider; ch: CHAR; fstring: ARRAY 64 OF CHAR; i: LONGINT;
	decoder: AosCodecs.TextDecoder;
BEGIN
	decoder := NIL;
	COPY("", format);
	f := AosFS.Old(fileName);
	IF f # NIL THEN 
		AosFS.OpenReader(re, f, 0);
		f.Set(ri, 0);
		f.Read(ri, ch); i := ORD(ch);
		IF (i = 0F0H) OR (i = 0F7H) OR (i = 01H) THEN				(* Oberon File Format *)
			COPY("Oberon", format);										
		ELSIF (i = 03CH) THEN										(* possibly an XML, check further *)
			(* check IF just an XML or BB Format *)
			f.Set(ri, 0);
			AosFS.ReadString(ri, fstring);
			Utilities.UpperCase(fstring);
			IF Utilities.Match("<?XML VERSION=*", fstring) THEN
				IF Utilities.Match("*<?BLUEBOTTLE FORMAT*", fstring) THEN
					COPY("BBT", format);										(* Bluebottle File Format *)
				ELSE
					COPY("UTF-8", format);										(* XML - treat as UTF-8 *)
				END;
			ELSE
				COPY("UTF-8", format);											(* Text/Other - treat as UTF-8 *)
			END;		
		ELSE														(* Neither Oberon nor XML/BB *)
			COPY("UTF-8", format);
		END;	
	END;
	(* get correct decoder *)
	decoder := AosCodecs.GetTextDecoder(format);
	RETURN decoder;
END DecodeAuto;
		
(** Load text using codecs *)
PROCEDURE Load(text : Text; filename, format : ARRAY OF CHAR; VAR res : LONGINT);
VAR decoder : AosCodecs.TextDecoder;
	in: AosIO.Reader;
	t : Text;	
BEGIN
	res := -1;
	decoder := AosCodecs.GetTextDecoder(format);
	IF decoder = NIL THEN AosOut.String("Decoder not found: "); AosOut.String(format); AosOut.Ln; RETURN END;	
	in := AosCodecs.OpenInputStream(filename);	
	IF in = NIL THEN AosOut.String("Can't open file: "); AosOut.String(filename); AosOut.Ln; RETURN END;	
	decoder.Open(in, res);
	IF res = 0 THEN
		t := decoder.GetText();
		t.AcquireRead;
		text.AcquireWrite;
		text.CopyFromText(t, 0, t.GetLength(), 0);
		text.ReleaseWrite;
		t.ReleaseRead;
	END;
END Load;

(** Import text in ASCII format. *)
PROCEDURE LoadAscii*(text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
BEGIN
	Load(text, filename, "ISO8859-1", res)
END LoadAscii;

(** Import text in UTF8 format. *)
PROCEDURE LoadUTF8*(text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
BEGIN
	Load(text, filename, "UTF-8", res)
END LoadUTF8;

(** import text in UCS16 format *)
PROCEDURE LoadUCS16*(text : Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
VAR f : AosFS.File; r : AosFS.Reader;
	 i, m  : LONGINT;
	tempUCS32 : ARRAY 1024 OF Char32; 
	ch, last : Char32; tc1, tc2 : CHAR;
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

(** Import an Oberon Text *)
PROCEDURE LoadOberonText*(text: Text; fileName: ARRAY OF CHAR; VAR res: LONGINT);
BEGIN
	Load(text, fileName, "Oberon", res)
END LoadOberonText;

(** Import a BBT Text *)
PROCEDURE LoadText*(text : AosTexts.Text; filename : ARRAY OF CHAR; VAR res : LONGINT);
BEGIN
	Load(text, filename, "BBT", res)
END LoadText;

(** store text using codecs *)
PROCEDURE Store(text : Text; filename, format : ARRAY OF CHAR; VAR res : LONGINT);
VAR w : AosFS.Writer;
	f : AosFS.File;
	encoder : AosCodecs.TextEncoder;
BEGIN
	res := -1;
	encoder := AosCodecs.GetTextEncoder(format);
	IF encoder = NIL THEN AosOut.String("Decoder not found: "); AosOut.String(format); AosOut.Ln; RETURN END;
	f := AosFS.New(filename);
	IF f = NIL THEN RETURN END;
	AosFS.OpenWriter(w, f, 0);
	text.AcquireRead;
	encoder.Open(w);
	encoder.WriteText(text, res);
	text.ReleaseRead;
	IF res = 0 THEN AosFS.Register(f); f.Update; END
END Store;

(** Export text in ASCII format. Objects, attributes and characters > CHR(128) are lost *)
PROCEDURE ExportAscii*(text : Text; fileName : ARRAY OF CHAR; VAR res : LONGINT);
BEGIN
	Store(text, fileName, "ISO8859-1", res)
END ExportAscii;
	
(** Export text in UTF8 format Objects and attributes are lost *)
PROCEDURE ExportUTF8*(text : Text; fileName : ARRAY OF CHAR; VAR res : LONGINT);
BEGIN
	Store(text, fileName, "UTF-8", res)
END ExportUTF8;

(** Export text in Oberon format Objects are lost *)
PROCEDURE StoreOberonText*(text : Text; fileName: ARRAY OF CHAR; VAR res : LONGINT);
BEGIN
	Store(text, fileName, "Oberon", res)
END StoreOberonText;

(** Export text in Bluebottle format *)
PROCEDURE StoreText*(text : AosTexts.Text; fileName : ARRAY OF CHAR; VAR res : LONGINT);
BEGIN
	Store(text, fileName, "BBT", res)
END StoreText;

(** Text to UTF8 string. Objects and attributes are lost. The String is truncated if buffer is too small *)
PROCEDURE TextToStr*(text : Text; VAR string : ARRAY OF CHAR);
VAR i, l, pos : LONGINT; r : AosTexts.TextReader; ch : AosTexts.Char32; ok : BOOLEAN;
BEGIN
	text.AcquireRead;
	COPY("", string);
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
			IF i = m THEN tempUCS32[i] := 0; text.InsertUCS32(pos, tempUCS32); INC(pos, m); i := 0 END;
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

PROCEDURE GetUTF8Char*(r : AosIO.Reader; VAR u : AosTexts.Char32) : BOOLEAN;
VAR ch : ARRAY 8 OF CHAR; i : LONGINT;
BEGIN
	ch[0] := r.Get();
	FOR i := 1 TO ORD(UTF8Strings.CodeLength[ORD(ch[0])]) - 1 DO ch[i] := r.Get() END;
	i := 0;
	RETURN UTF8Strings.DecodeChar(ch, i, u)
END GetUTF8Char;

PROCEDURE WriteUTF8Char*(w : AosIO.Writer; ch : Char32);
VAR str : ARRAY 8 OF CHAR; i : LONGINT;
BEGIN
	i := 0; IF UTF8Strings.EncodeChar(ch, str, i) THEN w.Bytes(str, 0, i) END
END WriteUTF8Char;

(* Style to Attribute Converter *)
PROCEDURE StyleToAttribute*(style: AosTexts.CharacterStyle): AosTexts.Attributes;
VAR attr: AosTexts.Attributes; fi: AosTexts.FontInfo;
BEGIN
	IF (style = NIL) THEN RETURN NIL END;
	NEW(attr); NEW(fi);
	COPY(style.family, fi.name);
	fi.size := ENTIER(FP1616.FixpToFloat(style.size));
	fi.style := style.style;
	attr.color := style.color;
	attr.bgcolor := style.bgColor;
	attr.voff := ENTIER(FP1616.FixpToFloat(style.baselineShift));
	attr.fontInfo := fi;	
	RETURN attr
END StyleToAttribute;

(* Attribute To Style Converter, creates style with given name *)
PROCEDURE AttributeToStyle*(name: ARRAY OF CHAR; attr: AosTexts.Attributes): AosTexts.CharacterStyle;
VAR style: AosTexts.CharacterStyle;
BEGIN
	NEW(style);
	COPY(name, style.name);
	IF attr.fontInfo # NIL THEN
		COPY(attr.fontInfo.name, style.family);
		style.size := FP1616.FloatToFixp(attr.fontInfo.size*1.0);
		style.style := attr.fontInfo.style;
	ELSE
		COPY("Oberon", style.family);
		style.size := FP1616.FloatToFixp(12.0);
		style.style := {};
	END;
	style.color := attr.color;
	style.bgColor := attr.bgcolor;
	style.baselineShift := attr.voff;
	RETURN style
END AttributeToStyle;

(**
 *	-- Bluebottle File Format -- 
 *	Convert Procedure version:	0.1
 *	Usage: Convert file1.Mod file2.Mod ... fileN.Mod~
*)
PROCEDURE Convert*(par : ANY) : ANY;
VAR s : AosCommands.Parameters; sr : AosIO.StringReader;
	dstring : ARRAY 256 OF CHAR;
BEGIN
	AosOut.String("-- Oberon To Bluebottle File Converter v0.1 --"); AosOut.Ln;
	s := par(AosCommands.Parameters); NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	REPEAT
		sr.SkipWhitespace; sr.Token(dstring);
		ConvertFile(dstring);
	UNTIL (sr.Pos() = LEN(s.str^)-1);
	AosOut.String("-- all done --"); AosOut.Ln;
	RETURN NIL;
END Convert;

PROCEDURE ConvertAll*(par : ANY) : ANY;
VAR enumerator : AosFS.Enumerator;
	name : ARRAY 256 OF CHAR; flags : SET; time, date, size : LONGINT;
BEGIN
	NEW(enumerator);
	enumerator.Open("", {});
	AosOut.String("-- Oberon To Bluebottle File Converter v0.1 --"); AosOut.Ln;
	WHILE enumerator.HasMoreEntries() DO
		IF enumerator.GetEntry(name, flags, time, date, size) THEN
			IF Utilities.Match("*.Mod", name) THEN
				ConvertFile(name);
			END;
		END;
	END;
	AosOut.String("-- all done --"); AosOut.Ln;
	enumerator.Close;
	RETURN NIL;
END ConvertAll;	

(* Converts the file with the given name into bb file format *)
PROCEDURE ConvertFile(file: ARRAY OF CHAR);
VAR ext, ext2: ARRAY 16 OF CHAR; file2 : ARRAY 256 OF CHAR;
	text : AosTexts.Text; res : LONGINT;
BEGIN
	ext2 := "mod";							(* extension for the converted files *)
	Utilities.GetExtension(file, file2, ext);
	Utilities.Append(file2, "."); Utilities.Append(file2, ext2);
	(* check if file is Module *)
	IF (ext = "Mod") THEN
		NEW(text);
		AosOut.String("Converting: "); AosOut.String(file);
		(* read Oberon Format file *)
		text.AcquireWrite;
		LoadOberonText(text, file, res);
		text.ReleaseWrite;
		IF (res = 0) THEN 
			(* write Bluebottle Format File *)
			text.AcquireRead;
			StoreText(text, file2, res);
			text.ReleaseRead;
			IF (res # 0) THEN AosOut.String("Converter ERROR: Something went wrong... "); AosOut.Ln;
			ELSE AosOut.String("                 done"); AosOut.Ln; END;
		ELSE
			AosOut.String("Converter ERROR: Couldn't load Oberon File: "); AosOut.String(file); AosOut.Ln;
		END;		
	ELSE
		AosOut.String("Converter ERROR: Wrong Extension: "); AosOut.String(file); AosOut.Ln;
	END;	
END ConvertFile;


(* ------------------------------------------------------------------------- *)

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
CONST 
	q = 8204957;	(* prime number, {(d+1) * q <= MAX(LONGINT)} *)
	d = 256;			(* number of different characters *)
VAR h1, h2, dM, i, j, m, n: LONGINT; ch : Char32; found : BOOLEAN; r : AosTexts.TextReader;
BEGIN (* caller must hold read lock on text *)
	m := UCS32StrLength(pattern); n := text.GetLength();
	IF (from + m > n) THEN RETURN -1 END;

	NEW(r, text);  r.SetPosition(from);
	
	dM := 1; FOR i := 0 TO m-2 DO dM := (d*dM) MOD q END;
	h1 := 0; FOR i := 0 TO m-1 DO h1 := (h1*d + (pattern[i] MOD d)) MOD q END;
	h2 := 0; FOR i := 0 TO m-1 DO r.ReadCh(ch); ch := ch MOD d; h2 := (h2*d + ch) MOD q END;
	i := from; found := FALSE;
	
	IF (h1 = h2) THEN (* verify *)
		j := 0; r.SetPosition(i); found := TRUE;
		WHILE (j < m) DO
			r.ReadCh(ch); 
			IF (ch # pattern[j]) THEN found := FALSE; j := m; END; (* hash values are equal, but strings are not *)
			INC(j);
		END;			
	END;
	
	WHILE ~found & (i < n-m) DO
		r.SetPosition(i); r.ReadCh(ch); ch := ch MOD d; h2 := (h2 + d*q - ch*dM) MOD q;
		r.SetPosition(i + m); r.ReadCh(ch); ch := ch MOD d; h2 := (h2*d + ch) MOD q;
		INC(i);
		
		IF (h1 = h2) THEN (* verify *)
			j := 0; r.SetPosition(i); found := TRUE;
			WHILE (j < m) DO
				r.ReadCh(ch); 
				IF (ch # pattern[j]) THEN found := FALSE; j := m; END; (* hash values are equal, but strings are not *)
				INC(j);
			END;			
		END;
	END;
	
	IF found THEN RETURN i
	ELSE RETURN -1
	END	
END Pos;

PROCEDURE UpperCaseChar32*(VAR ch : AosTexts.Char32);
BEGIN
	(* LONGINT version of IF (ch >= "a") & (ch <= "z") THEN CAP(ch); END; *)
	IF (ch >= 61H) & (ch <= 7AH) THEN ch := ch - 32; END;
END UpperCaseChar32;

(* Compare the pattern string of length 'length' with the string at the current position/direction of the text reader 'r' *)
PROCEDURE Equals(VAR pattern : ARRAY OF Char32; r : AosTexts.TextReader; length : LONGINT; ignoreCase : BOOLEAN) : BOOLEAN;
VAR ch, chp : AosTexts.Char32; equals : BOOLEAN; i : LONGINT; 
BEGIN
	i := 0; equals := TRUE;
	WHILE (i < length) DO
		r.ReadCh(ch); chp := pattern[i];
		IF ignoreCase THEN UpperCaseChar32(ch); UpperCaseChar32(chp); END;
		IF (ch # chp) THEN equals := FALSE; i := length; END; (* hash values are equal, but strings are not *)
		INC(i);
	END;
	RETURN equals;			
END Equals;

(** More generic version of Pos. Basically the same search algorithm, but can also perform case-insensitive searching and/or 
 * backwards directed searching.
 * Returns the position of the first character of the first occurence of 'pattern' in 'text'  in search direction or -1 if pattern not found 
 *)
PROCEDURE GenericPos*(VAR pattern: ARRAY OF Char32; from : LONGINT; text : Text; ignoreCase, backwards : BOOLEAN): LONGINT;
CONST 
	q = 8204957;	(* prime number, {(d+1) * q <= MAX(LONGINT)} *)
	d = 256;			(* number of different characters *)
VAR h1, h2, dM, i, patternLength, stringLength: LONGINT; ch : Char32; found : BOOLEAN; r : AosTexts.TextReader;
BEGIN (* caller must hold read lock on text *)
	patternLength := UCS32StrLength(pattern); stringLength := text.GetLength();
	
	(* check whether the search pattern can be contained in the text regarding the search direction *)
	IF backwards THEN
		IF (patternLength > from + 1) THEN RETURN -1; END;
	ELSE
		IF (from + patternLength > stringLength) THEN RETURN -1; END;
	END;
	
	dM := 1; FOR i := 0 TO patternLength-2 DO dM := (d*dM) MOD q END;
	
	(* calculate hash value for search pattern string *)
	h1 := 0; 	
	FOR i := 0 TO patternLength-1  DO 
		IF backwards THEN
			ch := pattern[patternLength-1-i];
		ELSE
			ch := pattern[i]; 
		END;
		IF ignoreCase THEN UpperCaseChar32(ch); END;
		ch := ch MOD d;
		h1 := (h1*d + ch) MOD q;
	END;

	(* calculate hash value for the first 'patternLength' characters of the text to be searched *)
	NEW(r, text);  r.SetPosition(from); 
	IF backwards THEN r.SetDirection(-1); END;
	h2 := 0; 
	FOR i := 0 TO patternLength-1 DO 
		r.ReadCh(ch); 
		IF ignoreCase THEN UpperCaseChar32(ch); END;
		ch := ch MOD d;
		h2 := (h2*d + ch) MOD q; 
	END;
	
	i := from; found := FALSE;
	
	IF (h1 = h2) THEN (* Hash values match, compare strings *)
		IF backwards THEN
			r.SetDirection(1); r.SetPosition(i - patternLength + 1);
		ELSE
			r.SetPosition(i);
		END;
		found := Equals(pattern, r, patternLength,  ignoreCase); 
		IF backwards THEN r.SetDirection(-1); END;			
	END;
	
	LOOP
		(* check wether we're finished *)
		IF found THEN EXIT; END;
		IF backwards THEN
			IF (i < patternLength) THEN EXIT; END;
		ELSE
			IF (i >= stringLength-patternLength) THEN EXIT; END;
		END;
		
		(* remove last character from hash value *)
		r.SetPosition(i); r.ReadCh(ch); 
		IF ignoreCase THEN UpperCaseChar32(ch); END;
		ch := ch MOD d;
		h2 := (h2 + d*q - ch*dM) MOD q;
		
		(* add next character to hash value *)
		IF backwards THEN
			r.SetPosition(i - patternLength); 
		ELSE
			r.SetPosition(i + patternLength);
		END;
		r.ReadCh(ch);
		IF ignoreCase THEN UpperCaseChar32(ch); END;
		ch := ch MOD d;
		h2 := (h2*d + ch) MOD q;
		
		IF backwards THEN 
			DEC(i); 
		ELSE 
			INC(i); 
		END;
		
		IF (h1 = h2) THEN (* verify *)
			IF backwards THEN
				r.SetDirection(1); r.SetPosition(i - patternLength + 1);
			ELSE
				r.SetPosition(i);
			END;
			found := Equals(pattern, r, patternLength,  ignoreCase); 
			IF backwards THEN r.SetDirection(-1); END;
		END;
	END;
	
	IF found THEN 
		IF backwards THEN RETURN i - patternLength + 1;
		ELSE RETURN i;
		END;
	ELSE RETURN -1;
	END;
END GenericPos;

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

(* Oberon File Format *)
PROCEDURE OberonDecoderFactory*(par : ANY) : ANY;
VAR p : OberonDecoder;
BEGIN
	NEW(p);
	RETURN p
END OberonDecoderFactory;

PROCEDURE OberonEncoderFactory*(par : ANY) : ANY;
VAR p : OberonEncoder;
BEGIN
	NEW(p);
	RETURN p
END OberonEncoderFactory;

(* Bluebottle File Format *)
PROCEDURE BluebottleDecoderFactory*(par : ANY) : ANY;
VAR p : BluebottleDecoder;
BEGIN
	NEW(p);
	RETURN p
END BluebottleDecoderFactory;

PROCEDURE BluebottleEncoderFactory*(par : ANY) : ANY;
VAR p : BluebottleEncoder;
BEGIN
	NEW(p);
	RETURN p
END BluebottleEncoderFactory;

(* UTF-8 File Format *)
PROCEDURE UTF8DecoderFactory*(par : ANY) : ANY;
VAR p : UTF8Decoder;
BEGIN
	NEW(p);
	RETURN p
END UTF8DecoderFactory;

PROCEDURE UTF8EncoderFactory*(par : ANY) : ANY;
VAR p : UTF8Encoder;
BEGIN
	NEW(p);
	RETURN p
END UTF8EncoderFactory;

(* ISO8859-1 File Format *)
PROCEDURE ISO88591DecoderFactory*(par : ANY) : ANY;
VAR p : ISO88591Decoder;
BEGIN
	NEW(p);
	RETURN p
END ISO88591DecoderFactory;

PROCEDURE ISO88591EncoderFactory*(par : ANY) : ANY;
VAR p : ISO88591Encoder;
BEGIN
	NEW(p);
	RETURN p
END ISO88591EncoderFactory;

(* Hex File Format *)
PROCEDURE HEXDecoderFactory*(par : ANY) : ANY;
VAR p : HEXDecoder;
BEGIN
	NEW(p);
	RETURN p
END HEXDecoderFactory;

PROCEDURE HEXEncoderFactory*(par : ANY) : ANY;
VAR p : HEXEncoder;
BEGIN
	NEW(p);
	RETURN p
END HEXEncoderFactory;


BEGIN
	GetConfig;
END AosTextUtilities.

AosTextUtilities.ConvertAll~
AosTextUtilities.Convert WMClock.Mod AOS:WMTextTool.Mod Idontexist.Mod~