MODULE WMOTFonts;	(** AUTHOR "PL"; PURPOSE "OpenType Support" *)

IMPORT
	SYSTEM, AosIO, AosOut, AosCommands, WMWindowManager,
	WMGraphics, Raster, WMFontManager,
	Utilities, WMRectangles, 
	AosFS, AosKernel,
	AosOTFonts, AosOType, AosOTInt;

CONST
	ScreenDPI = 71;
	
	Debug = FALSE;

TYPE
	Glyph*  = RECORD
		img- : WMGraphics.Image;
		code- : LONGINT; 										(* import only *)
		dx, x, y, w, h : LONGINT;
	END;
	GlyphArray* = POINTER TO ARRAY OF Glyph;
	
	GlyphRange* = RECORD
		firstCode-, lastCode- : LONGINT;							 (* inclusive *)
		glyphs- : GlyphArray;
		loaded- : BOOLEAN;
	END;
	GlyphRangeArray* = POINTER TO ARRAY OF GlyphRange;

	Font*  = OBJECT(WMGraphics.Font)
	VAR nofGlyphs- : LONGINT;
		nofGlyphRanges- : LONGINT;
		glyphRanges : GlyphRangeArray;
		placeholderimg : WMGraphics.Image;
		fontFile : AosFS.File;
		empty : WMRectangles.Rectangle;
		fname-, subfam- : ARRAY 256 OF CHAR;
		ofont : AosOType.Font;
		inst: AosOType.Instance;
		glyph : AosOType.Glyph;
		
		PROCEDURE &Init;
		VAR mode : Raster.Mode; pix : Raster.Pixel;
		BEGIN
			Init^;
			nofGlyphRanges := 0;
			empty := WMRectangles.MakeRect(0, 0, 0, 0);		(* save the proc call *)
			NEW(placeholderimg); Raster.Create(placeholderimg, 16, 16, Raster.A1);
			Raster.InitMode(mode, Raster.srcCopy);
			Raster.SetRGBA(pix, 255, 0, 0, 0);
			Raster.Fill(placeholderimg, 0, 0, 15, 15, pix, mode);
			ascent := 16; descent := 5;
		END Init;
		
		(* support the oberon encoding scheme *)
		PROCEDURE MapCode(VAR code : LONGINT);
		BEGIN
			IF (code >= 126) & (code <= 155) THEN code := AosOType.CharToUnicode[code] END;
		END MapCode;
		
		PROCEDURE GetGlyphMap*(code : LONGINT; VAR map : WMGraphics.Image);
		VAR g : Glyph; range : LONGINT;
		BEGIN
			IF FindGlyphRange(code, range) THEN
				IF FindGlyph(code, g) THEN 			
					map := g.img
				ELSE map := placeholderimg	
				END
			ELSE map := placeholderimg
			END
		END GetGlyphMap;
		
		PROCEDURE HasChar*(code : LONGINT) : BOOLEAN;
		VAR dummy : LONGINT;
		BEGIN
			RETURN FindGlyphRange(code, dummy)
		END HasChar;
		
		PROCEDURE GetGlyphSpacings*(code : LONGINT; VAR glyphSpacings : WMGraphics.GlyphSpacings);
		VAR g : Glyph; range : LONGINT;
		BEGIN
			IF FindGlyphRange(code, range) THEN
				IF FindGlyph(code, g) THEN
					glyphSpacings.width := g.w; 
					glyphSpacings.ascent := ascent; glyphSpacings.descent := descent;
					glyphSpacings.bearing.l := g.x; 
					glyphSpacings.bearing.r := g.dx - (g.w + g.x); 
				
					glyphSpacings.height := g.h; 
					glyphSpacings.dy := ascent - g.h - g.y
				ELSE glyphSpacings.width := 5; glyphSpacings.height := 15; glyphSpacings.ascent := 16; 
				END						
			ELSE 
				AosOut.String("code= "); AosOut.Int(code, 0); AosOut.String("out of range"); AosOut.Ln; 
			glyphSpacings.width := 5; glyphSpacings.height := 15; glyphSpacings.ascent := 16; 
			END
		END GetGlyphSpacings;
		
		PROCEDURE LoadGlyphRange(gri : LONGINT);
		VAR i : LONGINT;
		BEGIN
			IF glyphRanges[gri].glyphs = NIL THEN
				NEW(glyphRanges[gri].glyphs, glyphRanges[gri].lastCode - glyphRanges[gri].firstCode + 1)
			END;
			AosOut.String("OT: Loading range: "); AosOut.Hex(glyphRanges[gri].firstCode, 6); AosOut.String(".."); AosOut.Hex(glyphRanges[gri].lastCode, 6);
			FOR i := glyphRanges[gri].firstCode TO glyphRanges[gri].lastCode DO
				ReadGlyph(i, glyphRanges[gri].glyphs[i - glyphRanges[gri].firstCode])
			END;
			AosOut.String("  done"); AosOut.Ln;
			glyphRanges[gri].loaded := TRUE		
		END LoadGlyphRange;	
		
		PROCEDURE FindGlyphRange(code : LONGINT; VAR gri : LONGINT) : BOOLEAN;
		VAR a, b, m : LONGINT;
		BEGIN
			gri := 0;
			a := 0; b := LEN(glyphRanges)- 1;
			WHILE (a < b) DO m := (a + b) DIV 2; 
				IF glyphRanges[m].lastCode < code THEN a := m + 1 
				ELSE b := m
				END 
			END;
			IF (glyphRanges[a].firstCode <= code) & (glyphRanges[a].lastCode >= code) THEN
				IF ~glyphRanges[a].loaded THEN LoadGlyphRange(a) END;
				gri := a; RETURN TRUE 
			ELSE RETURN FALSE 
			END
		END FindGlyphRange;
		
		PROCEDURE FindGlyph(code : LONGINT; VAR glyph : Glyph) : BOOLEAN;
		VAR gri : LONGINT;
		BEGIN
			IF FindGlyphRange(code, gri) THEN
				glyph := glyphRanges[gri].glyphs[code - glyphRanges[gri].firstCode]; RETURN TRUE
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
		
		PROCEDURE ReadGlyph(code : LONGINT; VAR g : Glyph);
		VAR no, k, l, bytes, pos, xw, bits, b : LONGINT;
			ch : CHAR;
			data : AosOTFonts.RasterData;
			p1 : Raster.Pixel;
			mode : Raster.Mode;
			
		BEGIN
			Raster.SetRGBA(p1, 255, 0, 0, 255);
			Raster.InitMode(mode, Raster.srcCopy);
		
			no := AosOType.UnicodeToGlyph(ofont, code);
			IF Debug THEN AosOut.String("Reading Glyph Nr: "); AosOut.Int(no, 0); AosOut.String(" Code: u"); AosOut.Hex(code, 4); AosOut.Ln END;
			AosOType.LoadGlyph(inst, glyph, no,  {AosOType.Hinted, AosOType.Width, AosOType.Raster});
			g.dx := glyph.awx;													(* advance *)			
			g.x := glyph.hbx;													(* horizontal bearing x *)
			g.y := glyph.hby;														(* horizontal bearing y *)
			g.w := glyph.rw;														(* image width *)
			g.h := glyph.rh;														(* image height *)

			IF glyph.rw * glyph.rh # 0 THEN
				
				data.rect := AosOTFonts.FillRect; data.adr := SYSTEM.ADR(Pattern); data.bpr := (glyph.rw+7) DIV 8; data.len := LEN(Pattern);
				bytes := glyph.rh * ((glyph.rw+7) DIV 8);
				ASSERT(bytes < LEN(Pattern));
				ASSERT(bytes > 0);
				k := 0; REPEAT Pattern[k] := 0X; INC(k) UNTIL k = bytes;
				AosOType.EnumRaster(glyph, data);
			
				xw := ((glyph.rw + 7) DIV 8) * 8;
				l := xw * glyph.rh DIV 8;
				IF xw *  glyph.rh > 0 THEN 
					NEW(g.img); Raster.Create(g.img, xw, glyph.rh, Raster.A1);
					pos := 0; k := 0;
					WHILE l > 0 DO 
						ch := Pattern[k]; bits := ORD(ch); DEC(l); INC(k);
						FOR b := 0 TO 7 DO
							IF bit[ORD(ch), b]  THEN
								IF pos MOD xw < glyph.rw THEN
									Raster.Put(g.img, pos MOD xw, glyph.rh - pos DIV xw - 1, p1, mode); 
								END
							ELSE
							END;
							INC(pos)
						END
					END
				END					
			
			END;

		END ReadGlyph;
		
		PROCEDURE Load(filename : ARRAY OF CHAR; size : LONGINT) : BOOLEAN;
		VAR i, j, k, ngri, splitCount : LONGINT; res : INTEGER;
			height, ascent, descent : LONGINT;
		
		BEGIN
			fontFile := AosFS.Old(filename);															(* open file *)
			IF fontFile = NIL THEN RETURN FALSE END;
			ofont := AosOType.Open(filename);														(* read file *)
			IF ofont = NIL THEN AosOut.String("OT: Could not open Font: "); AosOut.String(filename); AosOut.Ln; RETURN FALSE END;
	
			NEW(glyph);
			AosOType.InitGlyph(glyph, ofont);
			res := ScreenDPI;
			AosOType.GetInstance(ofont, 40H*size, res, res, AosOType.Identity, inst);					(* get instance *)
			IF inst = NIL THEN AosOut.String("OT: Could not get Instance: "); AosOut.String(filename);  AosOut.Ln; RETURN FALSE END;
	
			AosOType.GetName(ofont, 1, fname);													(* get Name *)
			AosOType.GetName(ofont, 2, subfam);													(* get SubFamily *)
	
			nofGlyphs := glyph.font.maxp.numGlyphs;													(* number of glyphs *)
			nofGlyphRanges := 0; (*ofont.cmap.segCount;*)											(* number of ranges *)
			
			(* split into ranges of max size 256 *)
			ngri := ofont.cmap.segCount;
			FOR i := 0 TO ngri - 1 DO
				IF (ofont.cmap.seg[i].end # 0) THEN
					INC(nofGlyphRanges, 1 + ((ofont.cmap.seg[i].end - ofont.cmap.seg[i].start) MOD 10000H) DIV 100H)
				END
			END;
			
			NEW(glyphRanges, nofGlyphRanges); i := 0; k := 0;
			IF Debug  THEN AosOut.String("-- Building Ranges: "); AosOut.Int(nofGlyphRanges, 0); AosOut.Ln END;
			WHILE k < ngri DO
				IF ofont.cmap.seg[k].end # 0 THEN
					splitCount := ((ofont.cmap.seg[k].end - ofont.cmap.seg[k].start) MOD 10000H) DIV 100H; j := 0;
					WHILE j < splitCount DO
						glyphRanges[i+j].firstCode := (ofont.cmap.seg[k].start MOD 10000H) + 100H*j; glyphRanges[i+j].lastCode := (ofont.cmap.seg[k].start MOD 10000H) + 100H*(j+1) - 1;
						IF Debug THEN AosOut.String("  SRange: "); AosOut.Int(i+j, 0); AosOut.String("  Start: "); AosOut.Int(glyphRanges[i+j].firstCode, 0); AosOut.String("  End: "); AosOut.Int(glyphRanges[i+j].lastCode, 0); AosOut.Ln END;
						INC(j);
					END;
					glyphRanges[i+j].firstCode := (ofont.cmap.seg[k].start MOD 10000H) + 100H*splitCount ; glyphRanges[i+j].lastCode := ofont.cmap.seg[k].end MOD 10000H;
					IF Debug THEN AosOut.String("  Range: "); AosOut.Int(i+j, 0); AosOut.String("  Start: "); AosOut.Int(glyphRanges[i+j].firstCode, 0); AosOut.String("  End: "); AosOut.Int(glyphRanges[i+j].lastCode, 0); AosOut.Ln END;
					INC(i, splitCount+1); 
				END;
				INC(k)
			END;
					
(*			height := inst.font.hhea.ascender + inst.font.hhea.descender + inst.font.hhea.lineGap;
			SELF.height := SHORT(AosOTInt.MulDiv(height, inst.yppm, 40H*LONG(inst.font.head.unitsPerEm)));		(* height *)
*)
			ascent := inst.font.hhea.ascender;
			SELF.ascent := SHORT(AosOTInt.MulDiv(ascent, inst.yppm, 40H*LONG(inst.font.head.unitsPerEm)));		(* ascent *)
			descent := inst.font.hhea.descender;
			SELF.descent := -SHORT(AosOTInt.MulDiv(descent, inst.yppm, 40H*LONG(inst.font.head.unitsPerEm)));	(* descent *)	
					
			RETURN TRUE
		END Load;
		
	END Font;
	
(* ------------------------------------------------- *)	
	
VAR bit: ARRAY 100H, 8 OF BOOLEAN;					(* Bit[b, i] means bit i in byte b is set *)
	Pattern: ARRAY 360*360 DIV 8 OF CHAR;				(* enough for 36 point at 720 dpi *)
	font : Font;

PROCEDURE InitBitTable;
VAR b, i: LONGINT;
BEGIN
	FOR b := 0 TO 0FFH DO
		FOR i := 0 TO 7 DO
			bit[b, i] := ODD(ASH(b, -i))
		END
	END
END InitBitTable;

PROCEDURE LoadFont(name : ARRAY OF CHAR; size : LONGINT) : Font;
BEGIN
	IF Debug THEN AosOut.String("Loading Font: "); AosOut.String(name); AosOut.Ln END;
	NEW(font); IF ~font.Load(name, size) THEN RETURN NIL END;		
	RETURN font
END LoadFont;

PROCEDURE LoadExactFont*(par : PTR) : PTR;
VAR exactName : ARRAY 256 OF CHAR;
	str : ARRAY 16 OF CHAR; f : WMGraphics.Font;
	fi : WMFontManager.FontInfo;
BEGIN
	ASSERT((par # NIL) & (par IS WMFontManager.FontInfo));
	fi := par(WMFontManager.FontInfo);
	COPY(fi.name^, exactName);
	IF WMGraphics.FontBold IN fi.style THEN Utilities.Append(exactName, "b") END;
	IF WMGraphics.FontItalic IN fi.style THEN Utilities.Append(exactName, "i") END;
	Utilities.Append(exactName, ".ttf");
	f := LoadFont(exactName, fi.size);
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
	Utilities.Append(exactName, ".ttf");
	f := LoadFont(exactName, fi.size);
	IF f # NIL THEN
		f.size := fi.size;
		f.style := fi.style
	END;
	RETURN f
END LoadApproximateFont;

PROCEDURE MultiTest*(par : ANY):ANY;
VAR name : ARRAY 256 OF CHAR; flags : SET; time, date, size : LONGINT;
	enumerator : AosFS.Enumerator;
	f : WMGraphics.Font;
BEGIN
	NEW(enumerator);
	enumerator.Open("*.ttf", {});
	AosOut.String("*** TrueType MultiTester v0.1 ***"); AosOut.Ln;
	WHILE enumerator.HasMoreEntries() DO
		IF enumerator.GetEntry(name, flags, time, date, size) THEN
			AosOut.String("    Testing File: "); AosOut.String(name);
			f := LoadFont(name, 40);
			IF f # NIL THEN
				AosOut.String("            all ok")
			ELSE
				AosOut.String("            failed")
			END;
			AosOut.Ln
		END
	END;
	AosOut.String("*** all done ***"); AosOut.Ln;
	enumerator.Close;	
	RETURN NIL
END MultiTest;


BEGIN
	InitBitTable
END WMOTFonts.


--------------------------------------------

S.Free WMOTFonts~
WMOTFonts.MultiTest~
