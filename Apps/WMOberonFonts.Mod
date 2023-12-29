MODULE WMOberonFonts;	 (** AUTHOR "TF"; PURPOSE "Support for oberon bitmap fonts"; *)

IMPORT
	AosOut, AosIO, AosFS, WMGraphics, Raster, AosCommands, WMFontManager, Utilities;

CONST TraceImport = FALSE;

TYPE
	Glyph = RECORD
		img : WMGraphics.Image;
		available : BOOLEAN;
		dx, x, y, w, h : LONGINT;
	END;
	
	Font* = OBJECT(WMGraphics.Font)
	VAR glyphs : ARRAY 256 OF Glyph;
		placeholderimg : WMGraphics.Image;
		
		idch, typech, famch, varch : CHAR;
		height, minX, maxX, minY, maxY, nofRuns : INTEGER;
		
		runs : ARRAY 32 OF RECORD beg, end : LONGINT END;
	
		PROCEDURE &Init;
		VAR mode : Raster.Mode; pix : Raster.Pixel;
		BEGIN
			Init^;
			NEW(placeholderimg); Raster.Create(placeholderimg, 16, 16, Raster.A1);
			Raster.InitMode(mode, Raster.srcCopy);
			Raster.SetRGBA(pix, 0, 0, 0, 0);
			Raster.Fill(placeholderimg, 0, 0, 15, 15, pix, mode)
		END Init;
		
		PROCEDURE GetGlyphMap*(code : LONGINT; VAR map : WMGraphics.Image);
		VAR g : Glyph;
		BEGIN
			IF (code >= 0) & (code < 256) & (glyphs[code].available) & (glyphs[code].img # NIL) THEN
				map := glyphs[code].img
			ELSE map := placeholderimg
			END
		END GetGlyphMap;

		PROCEDURE HasChar*(code : LONGINT) : BOOLEAN;
		BEGIN
			RETURN (code >= 0) & (code < 256) & (glyphs[code].available)
		END HasChar;

		PROCEDURE GetGlyphSpacings*(code : LONGINT; VAR glyphSpacings : WMGraphics.GlyphSpacings);
		BEGIN
			IF (code >= 0) & (code < 256) & (glyphs[code].available) (* & (glyphs[code].img # NIL) *) THEN
				glyphSpacings.width := glyphs[code].w; 
				glyphSpacings.bearing.l := glyphs[code].x; 
				glyphSpacings.bearing.r := glyphs[code].dx - (glyphs[code].w + glyphs[code].x); 
				
				glyphSpacings.height := glyphs[code].h; 
				glyphSpacings.dy := ascent - glyphs[code].h - glyphs[code].y
			ELSE glyphSpacings.width := 5; glyphSpacings.height := 15; glyphSpacings.ascent := 16; 
			END
		END GetGlyphSpacings;
	END Font;

VAR
	bit: ARRAY 100H, 8 OF BOOLEAN;	(* Bit[b, i] means bit i in byte b is set *)


PROCEDURE LoadFont*(name : ARRAY OF CHAR) : Font;
VAR r : AosFS.Reader;  f : AosFS.File; 
BEGIN
	f := AosFS.Old(name); 
	IF f = NIL THEN RETURN NIL END;
	AosFS.OpenReader(r, f, 0);
	RETURN StreamLoad(r)
END LoadFont;

PROCEDURE StreamLoad(r : AosIO.Reader) : Font;
VAR 
	font : Font;
	ch : CHAR;
	minY, maxY, t, rbeg, rend : INTEGER;
	nofGlyphs, i, j, run, bits, b, pos, xw : LONGINT;
	p1 : Raster.Pixel;
	mode : Raster.Mode;
	
BEGIN
	Raster.SetRGBA(p1, 255, 0, 0, 255);
	Raster.InitMode(mode, Raster.srcCopy);
	
	NEW(font);
	r.Char(font.idch); (* id *)
	r.Char(font.typech); (* metric or font *)
	r.Char(font.famch); (* family *)
	r.Char(font.varch); (* variant *)
	r.RawInt(font.height); 
	r.RawInt(font.minX);
	r.RawInt(font.maxX);
	r.RawInt(minY); font.descent := -minY;
	r.RawInt(maxY); font.ascent := maxY;
	r.RawInt(font.nofRuns);
	IF TraceImport THEN 
		AosOut.String("id :"); AosOut.Int(ORD(font.idch), 4); AosOut.Ln;
		AosOut.String("type :"); AosOut.Int(ORD(font.typech), 4); AosOut.Ln;
		AosOut.String("family :"); AosOut.Int(ORD(font.famch), 4); AosOut.Ln;
		AosOut.String("variant :"); AosOut.Int(ORD(font.varch), 4); AosOut.Ln;
		AosOut.String("height :"); AosOut.Int(font.height, 4); AosOut.Ln;
		AosOut.String("minX :"); AosOut.Int(font.minX, 4); AosOut.Ln;
		AosOut.String("maxX :"); AosOut.Int(font.ascent, 4); AosOut.Ln;
		AosOut.String("minY :"); AosOut.Int(minY, 4); AosOut.Ln;
		AosOut.String("maxY :"); AosOut.Int(font.maxY, 4); AosOut.Ln;
		AosOut.String("nofRuns :"); AosOut.Int(font.nofRuns, 4); AosOut.Ln;
	END;
	
	nofGlyphs := 0; i := 0;
	WHILE i < font.nofRuns DO
		r.RawInt(rbeg); font.runs[i].beg := rbeg;
		r.RawInt(rend); font.runs[i].end := rend;
		nofGlyphs := nofGlyphs + rend - rbeg;
		INC(i)
	END;
	
	run := 0;
	i := font.runs[run].beg;
	FOR j := 0 TO nofGlyphs  - 1 DO
		r.RawInt(t); font.glyphs[i].dx := t;
		r.RawInt(t); font.glyphs[i].x := t;
		r.RawInt(t); font.glyphs[i].y := t;
		r.RawInt(t); font.glyphs[i].w := t; 
		r.RawInt(t); font.glyphs[i].h := t;
		font.glyphs[i].available := TRUE;
		INC(i);
		IF i >= font.runs[run].end THEN INC(run); i := font.runs[run].beg END
	END;
	
	FOR i := 0 TO 255 DO
		IF font.glyphs[i].available THEN
			xw := ((font.glyphs[i].w + 7) DIV 8) * 8;
			j := xw * font.glyphs[i].h DIV 8;
			IF xw *  font.glyphs[i].h > 0 THEN 
				NEW(font.glyphs[i].img); Raster.Create(font.glyphs[i].img, xw, font.glyphs[i].h, Raster.A1);
				pos := 0;
				WHILE j > 0 DO 
					r.Char(ch); bits := ORD(ch); DEC(j);
					FOR b := 0 TO 7 DO
						IF bit[ORD(ch), b]  THEN
							IF pos MOD xw < font.glyphs[i].w THEN
								Raster.Put(font.glyphs[i].img, pos MOD xw, font.glyphs[i].h - pos DIV xw - 1, p1, mode); 
							END
						ELSE
						END;
						INC(pos)
					END
				END
			END	
		END
	END;
	RETURN font
END StreamLoad;

PROCEDURE StoreFont*(name : ARRAY OF CHAR; font : Font);
VAR w : AosFS.Writer;  f : AosFS.File; 
BEGIN
	f := AosFS.New(name);
	IF f = NIL THEN RETURN END;
	AosFS.OpenWriter(w, f, 0);
	StreamStore(w, font);
	w.Update;
	AosFS.Register(f)
END StoreFont;

PROCEDURE StreamStore(w : AosIO.Writer; font : Font);
VAR 
	ch : CHAR;
	nofGlyphs, i, j, run, bits, b, pos, xw : LONGINT;
	p1 : Raster.Pixel;
	mode : Raster.Mode;
	
BEGIN
	Raster.InitMode(mode, Raster.srcCopy);
	
	w.Char(font.idch); (* id *)
	w.Char(font.typech); (* metric or font *)
	w.Char(font.famch); (* family *)
	w.Char(font.varch); (* variant *)
	w.RawInt(font.height); 
	w.RawInt(font.minX);
	w.RawInt(font.maxX);
	w.RawInt(-SHORT(font.descent));
	w.RawInt(SHORT(font.ascent));
	w.RawInt(font.nofRuns);
	
	nofGlyphs := 0; i := 0;
	WHILE i < font.nofRuns DO
		w.RawInt(SHORT(font.runs[i].beg));
		w.RawInt(SHORT(font.runs[i].end));
		nofGlyphs := nofGlyphs + font.runs[i].end - font.runs[i].beg;
		INC(i)
	END;
	
	run := 0;
	i := font.runs[run].beg;
	FOR j := 0 TO nofGlyphs  - 1 DO
		w.RawInt(SHORT(font.glyphs[i].dx));
		w.RawInt(SHORT(font.glyphs[i].x));
		w.RawInt(SHORT(font.glyphs[i].y));
		w.RawInt(SHORT(font.glyphs[i].w));
		w.RawInt(SHORT(font.glyphs[i].h));
		INC(i);
		IF i >= font.runs[run].end THEN INC(run); i := font.runs[run].beg END
	END;

	FOR i := 0 TO 255 DO
		IF font.glyphs[i].available THEN
			xw := ((font.glyphs[i].w + 7) DIV 8) * 8;
			j := xw * font.glyphs[i].h DIV 8;
			IF xw *  font.glyphs[i].h > 0 THEN 
				pos := 0;
				WHILE j > 0 DO 
					DEC(j);
					bits := 0;
					FOR b := 0 TO 7 DO
						Raster.Get(font.glyphs[i].img, pos MOD xw, font.glyphs[i].h - pos DIV xw - 1, p1, mode);
						IF p1[Raster.a] # 0X THEN INC(bits, 256) END;
						bits := bits DIV 2;
						INC(pos)
					END;
					w.Char(CHR(bits))
				END
			END	
		END
	END
END StreamStore;

PROCEDURE InitBitTable;
VAR b, i: LONGINT;
BEGIN
	FOR b := 0 TO 0FFH DO
		FOR i := 0 TO 7 DO
			bit[b, i] := ODD(ASH(b, -i))
		END
	END
END InitBitTable;

PROCEDURE LoadExactFont*(par : PTR) : PTR;
VAR exactName : ARRAY 256 OF CHAR;
	str : ARRAY 16 OF CHAR; f : WMGraphics.Font;
	fi : WMFontManager.FontInfo;
BEGIN
	ASSERT((par # NIL) & (par IS WMFontManager.FontInfo));
	fi := par(WMFontManager.FontInfo);
	COPY(fi.name^, exactName);
	Utilities.IntToStr(fi.size, str); Utilities.Append(exactName, str);
	IF WMGraphics.FontBold IN fi.style THEN Utilities.Append(exactName, "b") END;
	IF WMGraphics.FontItalic IN fi.style THEN Utilities.Append(exactName, "i") END;
	Utilities.Append(exactName, ".Scn.Fnt");
	f := LoadFont(exactName);
	IF f # NIL THEN 
		COPY(fi.name^, f.name);
		f.size := fi.size;
		f.style := fi.style;
	END;
	RETURN f
END LoadExactFont;
		
PROCEDURE LoadApproximateFont*(par : PTR) : PTR;
VAR exactName : ARRAY 256 OF CHAR;
	str : ARRAY 16 OF CHAR; f : WMGraphics.Font;
	fi : WMFontManager.FontInfo;
BEGIN
	ASSERT((par # NIL) & (par IS WMFontManager.FontInfo));
	fi := par(WMFontManager.FontInfo);
	COPY(fi.name^, exactName);
	Utilities.IntToStr(fi.size, str); Utilities.Append(exactName, str);
	Utilities.Append(exactName, ".Scn.Fnt");
	f := LoadFont(exactName);
	IF f # NIL THEN
		f.size := fi.size;
		f.style := fi.style
	END;
	RETURN f
END LoadApproximateFont;
		
BEGIN
	InitBitTable
END WMOberonFonts.


System.Free WMOberonFonts~

