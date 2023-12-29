MODULE TeletextFont;	(** TF **)

IMPORT
	AosOut, AosCommands, 
	Graphics := WMGraphics, Raster, AosIO, 
	XML, Parser := XMLParser, Scanner := XMLScanner, DynamicStrings, Objects := XMLObjects, 
	Utilities, 
	AosFS;

TYPE
	Char32 = LONGINT;
	Glyph = RECORD
		img : Graphics.Image;
		code : Char32; (* import only *)
		fpos : LONGINT;
		loaded : BOOLEAN;
	END;
	GlyphArray = POINTER TO ARRAY OF Glyph;
	
	GlyphRange = RECORD
		firstCode, lastCode : LONGINT; (* inclusive *)
		glyphs : GlyphArray;
	END;
	GlyphRangeArray = POINTER TO ARRAY OF GlyphRange;

	Font = OBJECT(Graphics.Font)
	VAR
		nofGlyphRanges : LONGINT;
		glyphRanges : GlyphRangeArray;
		placeholderimg : Graphics.Image;
		fontFile : AosFS.File;
		
		PROCEDURE &Init;
		VAR mode : Raster.Mode; pix : Raster.Pixel;
		BEGIN
			Init^;
			nofGlyphRanges := 0;
			NEW(placeholderimg); Raster.Create(placeholderimg, 16, 16, Raster.A1);
			Raster.InitMode(mode, Raster.srcCopy);
			Raster.SetRGBA(pix, 255, 0, 0, 0);
			Raster.Fill(placeholderimg, 0, 0, 15, 15, pix, mode);
			ascent := 16; descent := 5;
			ascent := 10; descent := 8;	(* OJ *)
		END Init;
		
		PROCEDURE GetGlyphMap*(code : LONGINT; VAR map : Graphics.Image);
		VAR g : Glyph;
		BEGIN
			IF FindGlyph(code, g) THEN 
				IF ~g.loaded THEN LoadGlyph(code, g) END;
				map := g.img 
			ELSE map := placeholderimg
			END
		END GetGlyphMap;
		
		PROCEDURE GetGlyphSpacings*(code : LONGINT; VAR glyphSpacings : Graphics.GlyphSpacings);
		VAR g : Glyph;
		BEGIN
			IF FindGlyph(code, g) THEN 
				IF ~g.loaded THEN LoadGlyph(code, g) END;
				glyphSpacings.width := g.img.width; glyphSpacings.height := g.img.height; glyphSpacings.dy := 0; (* <- OJ *)	(* -5;  <- TF !!! *)
			ELSE glyphSpacings.width := 15; glyphSpacings.height := 15; 
			END
		END GetGlyphSpacings;
		
		PROCEDURE LoadGlyph(code : LONGINT; VAR g : Glyph);
		VAR gr : GlyphRange;
		BEGIN
			IF FindGlyph(code, g) & ~g.loaded THEN 
				ReadGlyph(fontFile, g); g.loaded := TRUE;
				IF FindGlyphRange(code, gr) THEN gr.glyphs[code - gr.firstCode] := g END;
			END
		END LoadGlyph;
		
		PROCEDURE FindGlyphRange(code : Char32; VAR glyphRange : GlyphRange) : BOOLEAN;
		VAR a, b, m : LONGINT;
		BEGIN
			IF nofGlyphRanges = 0 THEN RETURN FALSE END;
			a := 0; b := nofGlyphRanges - 1;
			WHILE (a < b) DO m := (a + b) DIV 2; 
				IF glyphRanges[m].lastCode < code THEN a := m + 1 
				ELSE b := m
				END 
			END;
			IF (glyphRanges[a].firstCode <= code) & (glyphRanges[a].lastCode >= code) THEN 
				glyphRange := glyphRanges[a]; RETURN TRUE 
			ELSE RETURN FALSE 
			END
		END FindGlyphRange;
		
		PROCEDURE FindGlyph(code : Char32; VAR glyph : Glyph) : BOOLEAN;
		VAR gr : GlyphRange;
		BEGIN
			IF FindGlyphRange(code, gr) THEN glyph := gr.glyphs[code - gr.firstCode]; RETURN TRUE
			ELSE RETURN FALSE
			END
		END FindGlyph;
		
		PROCEDURE CountGlyphes():LONGINT;
		VAR i, c : LONGINT;
		BEGIN
			FOR i := 0 TO nofGlyphRanges - 1 DO 
				c := c + glyphRanges[i].lastCode - glyphRanges[i].firstCode + 1;
			END;
			RETURN c	
		END CountGlyphes;
		
		PROCEDURE Import(filename : ARRAY OF CHAR);
		VAR f : AosFS.File;
			scanner : Scanner.Scanner;
			parser : Parser.Parser;
			doc : XML.Document;
			p : PTR;
			root : XML.Element;
			el : XML.Content;
			s : DynamicStrings.String;
			cont : Objects.Enumerator;
			nofGlyphs : LONGINT;
			glyphs : GlyphArray;
				
			curindex : LONGINT;
			
			PROCEDURE CountRanges(): LONGINT;
			VAR i : LONGINT; c, t, r : LONGINT;
			BEGIN
				c := glyphs[0].code + 1; r := 1;
				FOR i := 1 TO nofGlyphs - 1 DO
					IF (glyphs[i].code # c) THEN INC(r); c := glyphs[i].code END;
					INC(c);
				END;
				RETURN r
			END CountRanges;
			
			PROCEDURE GetRangeLength(i : LONGINT): LONGINT;
			VAR count, c : LONGINT;
			BEGIN
				count := 1; c := glyphs[i].code;
				WHILE (i + count < nofGlyphs) & (glyphs[i + count].code = c + count) DO INC(count) END;
				RETURN count
			END GetRangeLength;
			
			PROCEDURE MakeRanges();
			VAR i, j, rl, r : LONGINT;
			BEGIN
				nofGlyphRanges := CountRanges();
				NEW(glyphRanges, nofGlyphRanges);
				i := 0; r := 0;
				WHILE i < nofGlyphs DO 
					rl := GetRangeLength(i);
					NEW(glyphRanges[r].glyphs, rl)
					;glyphRanges[r].firstCode := glyphs[i].code; 
					glyphRanges[r].lastCode := glyphs[i].code + rl - 1;
					FOR j := 0 TO rl - 1 DO glyphRanges[r].glyphs[j] := glyphs[i]; INC(i) END;
					INC(r)
				END
			END MakeRanges;
			
			PROCEDURE HexStrToInt(VAR s: ARRAY OF CHAR): LONGINT;
				VAR vh, d, i: LONGINT;
			BEGIN
				i:=0;
				vh := 0;
				LOOP
					IF (s[i] >= "0") & (s[i] <= "9") THEN d := ORD(s[i])-ORD("0")
					ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN d := ORD(CAP(s[i]))-ORD("A")+10
					ELSE EXIT
					END;
					 vh := 16 * vh + d;
					INC(i)
				END;
				RETURN vh
			END HexStrToInt;
						
			PROCEDURE ReadByte(VAR s : ARRAY OF CHAR; pos: LONGINT): LONGINT;
			VAR hex : ARRAY 3 OF CHAR;
			BEGIN
				Utilities.Copy(s, pos, 2, hex);
				RETURN HexStrToInt(hex)
			END ReadByte;

			PROCEDURE GenChar(x : XML.Element);
			VAR scode, sbitmap : XML.String; code, count, i, w, h : LONGINT; bitmap : Graphics.Image;
				pos : LONGINT; color : BOOLEAN;
				p0, p1 : Raster.Pixel;
				mode : Raster.Mode;
			BEGIN
				scode := x.GetAttributeValue("code");
				sbitmap := x.GetAttributeValue("bitmap");
				Raster.InitMode(mode, Raster.srcCopy);
				IF (scode # NIL) & (sbitmap # NIL) THEN
					Utilities.StrToInt(scode^, code);
					pos := 0;
					w := ReadByte(sbitmap^, pos); INC(pos, 2);
					h := ReadByte(sbitmap^, pos); INC(pos, 2);
					Raster.SetRGBA(p0, 0, 0, 255, 255); Raster.SetRGBA(p1, 255, 255, 255, 255);
					IF w * h = 0 THEN AosOut.String("Illegal char : "); AosOut.Int(code, 5); AosOut.Ln END;
					NEW(bitmap); Raster.Create(bitmap, w, h, Raster.BGR888);
					i := 0;
					WHILE sbitmap[pos] # 0X DO 
						count := ReadByte(sbitmap^, pos); INC(pos, 2);
						WHILE count > 0 DO
							IF color THEN Raster.Put(bitmap, i MOD w, i DIV w, p1, mode) 
							ELSE Raster.Put(bitmap, i MOD w, i DIV w, p0, mode) 
							END;
							INC(i); DEC(count);
						END;
						color := ~color
					END;
					
					glyphs[curindex].code := code;
					glyphs[curindex].img := bitmap;
					INC(curindex)
				END;
			END GenChar;
			
		BEGIN
			f := AosFS.Old(filename);
			IF f # NIL THEN 
				NEW(scanner, f); NEW(parser, scanner); doc := parser.Parse()
			END;
			
			root := doc.GetRoot();
			cont := root.GetContents(); cont.Reset();
			nofGlyphs := root.GetNumberOfContents();
			NEW(glyphs, nofGlyphs);
			
			AosOut.Int(root.GetNumberOfContents(), 5); AosOut.String(" glyphs loaded."); AosOut.Ln;
			curindex := 0;
			WHILE cont.HasMoreElements() DO
				p := cont.GetNext();
				el := p(XML.Element);
				IF el IS XML.Element THEN
					s := el(XML.Element).GetName(); 
					IF s^ = "char" THEN GenChar(el(XML.Element)) END	
				END
			END;
			MakeRanges
		END Import;
		
		(** works up to 255x255x2 *)
		PROCEDURE RasterToBWRLBytes(img : Raster.Image; VAR buf : ARRAY OF CHAR; VAR pos : LONGINT);
		VAR i, count: LONGINT;
				p : Raster.Pixel;
				pix, curpix : BOOLEAN; mode : Raster.Mode;
		BEGIN
			buf[pos] := CHR(img.width); INC(pos);
			buf[pos] := CHR(img.height); INC(pos);
			IF (img.width = 0) OR (img.height = 0) THEN HALT(12345) END;
			Raster.InitMode(mode, Raster.srcCopy);
			count := 0; curpix := FALSE;
			FOR i := 0 TO img.width * img.height - 1 DO
				Raster.Get(img, i MOD img.width, i DIV img.width, p, mode);
				pix := p[Raster.r] > CHR(128);
				IF pix # curpix THEN
					curpix := pix;
					WHILE count > 255 DO buf[pos] := CHR(255); INC(pos); buf[pos] := CHR(0); INC(pos); DEC(count, 255) END;
					buf[pos] := CHR(count); INC(pos);
					count := 0
				END;
				INC(count)
			END;
			IF count > 0 THEN
				WHILE count > 255 DO buf[pos] := CHR(255); INC(pos); buf[pos] := CHR(0); INC(pos); DEC(count, 255) END;
				buf[pos] := CHR(count); INC(pos)
			END	
		END RasterToBWRLBytes;
		
		PROCEDURE Save(filename : ARRAY OF CHAR);
		VAR w : AosFS.Rider; i, j, c: LONGINT; f : AosFS.File;
				buf : ARRAY 1024 OF CHAR; fixup, pos : LONGINT;
		BEGIN
			f := AosFS.New(filename);f.Set(w, 0);
			(* write number of ranges *)
			AosFS.WriteLInt(w, nofGlyphRanges);
			(* write ranges *)
			FOR i := 0 TO nofGlyphRanges - 1 DO
				AosFS.WriteLInt(w, glyphRanges[i].firstCode);
				AosFS.WriteLInt(w, glyphRanges[i].lastCode);
				AosOut.String("Range : "); AosOut.Int(glyphRanges[i].firstCode, 5); AosOut.String("..");AosOut.Int(glyphRanges[i].lastCode, 5); AosOut.Ln;
			END;
			fixup := f.Pos(w);
			
			(* reserve space for per character file position table *)
			FOR i := 0 TO nofGlyphRanges - 1 DO
				FOR j := 0 TO glyphRanges[i].lastCode - glyphRanges[i].firstCode DO
					AosFS.WriteLInt(w, 0);
				END
			END;
			c := 0;
			FOR i := 0 TO nofGlyphRanges - 1 DO
				FOR j := 0 TO glyphRanges[i].lastCode - glyphRanges[i].firstCode DO
					INC(c);
					pos := 0;
					IF glyphRanges[i].glyphs = NIL THEN AosOut.String("WhatHappened ? Info :"); AosOut.Int(j, 4);  AosOut.Ln END;
					RasterToBWRLBytes(glyphRanges[i].glyphs[j].img, buf, pos);
					glyphRanges[i].glyphs[j].fpos := f.Pos(w);
					AosOut.Int(pos, 5); AosOut.Ln;
					f.WriteBytes(w, buf, 0, pos)
				END
			END;
			f.Set(w, fixup);
			FOR i := 0 TO nofGlyphRanges - 1 DO
				FOR j := 0 TO glyphRanges[i].lastCode - glyphRanges[i].firstCode DO
					AosFS.WriteLInt(w, glyphRanges[i].glyphs[j].fpos)
				END
			END;
			f.Update;
			AosFS.Register(f)
		END Save;
		
		PROCEDURE ReadGlyph(VAR f: AosFS.File;  VAR g : Glyph);
		VAR r : AosFS.Rider;
			w, h, i, c : LONGINT;
			pix : BOOLEAN;
			p0, p1 : Raster.Pixel;
			mode : Raster.Mode;
			t : ARRAY 5 OF CHAR;
			gr : GlyphRange;
			
			PROCEDURE GetB():LONGINT;
			VAR ch : CHAR;
			BEGIN
				f.Read(r, ch);
				RETURN ORD(ch)
			END GetB;
			
		BEGIN
			Raster.InitMode(mode, Raster.srcCopy);
			Raster.SetRGBA(p0, 0, 0, 0, 0); Raster.SetRGBA(p1, 0, 0, 0, 255);
			f.Set(r, g.fpos);
			w := GetB(); h := GetB();
			IF w * h <= 0 THEN 
				AosOut.String("Empty"); AosOut.Ln;
				RETURN 
			END;
			NEW(g.img); Raster.Create(g.img, w, h, Raster.A1);
			i := 0; pix := FALSE;
			WHILE i < w * h DO
				c := GetB();
				WHILE c > 0 DO 
					IF i >= w * h THEN AosOut.String("error."); AosOut.Ln 
					ELSE
						IF pix THEN Raster.Put(g.img, i MOD w, i DIV w, p1, mode) 
						ELSE Raster.Put(g.img, i MOD w, i DIV w, p0, mode) 
						END;
					END;	
					INC(i); DEC(c)
				END;
				pix := ~pix;
			END
		END ReadGlyph;
		
		PROCEDURE Load(filename : ARRAY OF CHAR);
		VAR r : AosFS.Rider; i, j, nofGlyphes : LONGINT; f : AosFS.File;
				buf : ARRAY 1024 OF CHAR; fixup, pos, notenoughregisters: LONGINT;
		BEGIN
			f := AosFS.Old(filename); f.Set(r, 0);
			fontFile := f;
			(* read number of ranges *)
			AosFS.ReadLInt(r, nofGlyphRanges);
			(* read ranges *)
			NEW(glyphRanges, nofGlyphRanges);
			FOR i := 0 TO nofGlyphRanges - 1 DO
				AosFS.ReadLInt(r, glyphRanges[i].firstCode);
				AosFS.ReadLInt(r, glyphRanges[i].lastCode);
				notenoughregisters := glyphRanges[i].lastCode - glyphRanges[i].firstCode;
				NEW(glyphRanges[i].glyphs, notenoughregisters + 1)
			END;
			FOR i := 0 TO nofGlyphRanges - 1 DO
				FOR j := 0 TO glyphRanges[i].lastCode - glyphRanges[i].firstCode DO
					AosFS.ReadLInt(r, glyphRanges[i].glyphs[j].fpos);
				END
			END;
			(* for now no indexing *)
(*			FOR i := 0 TO nofGlyphRanges - 1 DO
				FOR j := 0 TO glyphRanges[i].lastCode - glyphRanges[i].firstCode DO
					
					ReadGlyph(f, r, glyphRanges[i].glyphs[j])
				END
			END; *)
		END Load;
		
	END Font;
	
VAR bimbofont* : Font;
		
PROCEDURE Load*(par : PTR) : PTR;
BEGIN
	NEW(bimbofont);
	bimbofont.Load("teletext.bfnt");
	RETURN NIL
END Load;

(** convert a xml coded bitmap font to bfnt *)
PROCEDURE Import*(par : PTR) : PTR;
VAR temp : Font;
	 s : AosCommands.Parameters;
	filename, name, ext : ARRAY 128 OF CHAR;
	sr : AosIO.StringReader;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.String(filename); 
	NEW(temp);
	
	temp.Import(filename);
	AosOut.String(filename); AosOut.String(" imported."); AosOut.Ln;
	AosFS.SplitExtension(filename, name, ext);
	AosFS.JoinExtension(name, "bfnt", filename);
	temp.Save(filename);
	AosOut.String(filename); AosOut.String(" saved."); AosOut.Ln;
	RETURN NIL
END Import;
	
PROCEDURE ShowCode*(par : PTR) : PTR;
VAR s : AosCommands.Parameters;
		code : LONGINT;
		sr : AosIO.StringReader;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.Int(code, TRUE); 
	RETURN NIL
END ShowCode;

BEGIN
	IF Load(NIL) = NIL THEN END
END TeletextFont.
 
System.Free TeletextFont ~

Aos.Call WMBitmapFont.Import teletext.xml ~