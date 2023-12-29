MODULE WMLineFontEditor;

IMPORT
	AosOut, 
	AosModules, AosIO, AosFS, WMDialogs, WMRectangles,
	WMComponents, WMStandardComponents, WMWindowManager, WMGraphics;
	
CONST BufferSpace = 1024 * 1024;
	MaxCodepoint = 65536;

TYPE
	Glyph = POINTER TO RECORD
		ucs, variant, pos : LONGINT;
		next : Glyph;
	END;
	
TYPE Editor = OBJECT(WMComponents.FormWindow);
		PROCEDURE &New();
		BEGIN
		END New;
		
	END Editor;
	
TYPE Line16Font = OBJECT
	VAR buf : POINTER TO ARRAY OF CHAR;
		bc : LONGINT;
		glyphs : POINTER TO ARRAY OF Glyph;
		maxi, sum, nof : LONGINT;
		
	
		PROCEDURE &New;
		BEGIN
			NEW(buf, BufferSpace); bc := 0;
			NEW(glyphs, MaxCodepoint);
		END New;
		
		PROCEDURE Import(r : AosIO.Reader);
		BEGIN
			WHILE r.res = 0 DO ParseGlyph(r) END;
			AosOut.String("maxi = "); AosOut.Int(maxi, 0); AosOut.Ln;
			AosOut.String("sum = "); AosOut.Int(sum, 0); AosOut.Ln; 
			AosOut.String("nof = "); AosOut.Int(nof, 0); AosOut.Ln; 
			AosOut.String("avg = "); AosOut.Int(sum DIV nof, 0); AosOut.Ln; 
		END Import;
		
		PROCEDURE ParseGlyph(r : AosIO.Reader);
		VAR g, cur : Glyph; x, y, ucs, child, i : LONGINT;
		BEGIN
			NEW(g);
			ucs := GetNCharHex(r, 4);
			IF (ucs < 0) OR (ucs >= MaxCodepoint) THEN AosOut.String("ucs = "); AosOut.Int(ucs, 0); AosOut.Ln; 
				RETURN
			END;
			g.ucs := ucs;
			g.variant := GetNCharHex(r, 2);
			g.pos := bc;
			IF glyphs[g.ucs] = NIL THEN glyphs[g.ucs] := g ELSE
				cur := glyphs[g.ucs]; WHILE cur.next # NIL DO cur := cur.next END; cur.next := g
			END;
			r.SkipBytes(1);
			i := 0;
			WHILE (r.Peek() >= "0") & (r.res = 0)  DO
				x := GetNCharHex(r, 1); y := GetNCharHex(r, 1);
				IF (x = 0) & (y > 1) THEN
					child := GetNCharHex(r, 4) * 100H + (y - 2);
					buf[bc] := CHR(02H); INC(bc);
					buf[bc] := CHR(child DIV 1000000H MOD 100H); INC(bc);
					buf[bc] := CHR(child DIV 10000H MOD 100H); INC(bc);
					buf[bc] := CHR(child DIV 100H MOD 100H); INC(bc);
					buf[bc] := CHR(child MOD 100H); INC(bc)
				ELSE buf[bc] := CHR(x * 16 + y); INC(bc)
				END
			END;
			buf[bc] := 0X; INC(bc);
			IF i > maxi THEN maxi := i END;
			INC(nof); INC(sum, i);
			r.SkipWhitespace
		END ParseGlyph;
		
		PROCEDURE RenderInternal(canvas : WMGraphics. Canvas ; x, y, f, trace : LONGINT; char, variant : LONGINT); 
		VAR glyph : Glyph; p, t, lx, ly, c, v : LONGINT; first : BOOLEAN;
			color, mode : LONGINT;
		BEGIN
			color := 0FFH;
			mode := WMGraphics.ModeSrcOverDst;
			IF (char < 0) OR (char >= MaxCodepoint) THEN AosOut.String("unsupported char number "); AosOut.Int(char, 0); AosOut.Ln; 
				RETURN
			END;
			glyph := glyphs[char];
			(* find the variant *)
			WHILE (glyph # NIL) & (glyph.variant # variant) & (glyph.next # NIL) DO glyph := glyph.next END;
			IF glyph = NIL THEN
				AosOut.String("trace = "); AosOut.Hex(trace, 0); 
				AosOut.String(" char = "); AosOut.Int(char, 0); AosOut.String(" variant = "); AosOut.Int(variant, 0); AosOut.String(" not found"); AosOut.Ln; 
				RETURN
			END; 
			p := glyph.pos;
			first := TRUE; lx := -1;
			WHILE buf[p] # 0X DO
				CASE ORD(buf[p]) OF
				| 01H : IF lx # -1  THEN canvas.SetPixel((lx * f DIV 100H), (ly * f DIV 100H), 0FF00FFH, mode); lx := -1;  END; INC(p); t := ORD(buf[p]); lx := t DIV 16; ly := t MOD 16; 
				| 02H : INC(p); c := ORD(buf[p]);  c := c * 100H; INC(p); c := c + ORD(buf[p]); INC(p); c := c * 100H; c := c + ORD(buf[p]); INC(p); v := ORD(buf[p]);
					RenderInternal(canvas, x, y, f, trace, c, v);
				ELSE
					t := ORD(buf[p]);
					IF first THEN lx := t DIV 16; ly := t MOD 16; first := FALSE
					ELSE
						canvas.Line(x + (lx * f DIV 100H), y + (ly * f DIV 100H), x + ((t DIV 16) * f DIV 100H) , y + ((t MOD 16) * f DIV 100H), color, mode);
						lx := t DIV 16; ly := t MOD 16;
					END
				END;
				INC(p)
			END;
			IF lx # -1 THEN canvas.SetPixel((lx * f DIV 100H), (ly * f DIV 100H), 0FF00FFH, mode) END
		END RenderInternal;
		
		
		(** Render character char to canvas at x, y (baseline) *)
		PROCEDURE RenderChar*(canvas : WMGraphics. Canvas ; x, y : REAL; char : LONGINT); 
		BEGIN
			RenderInternal(canvas, ENTIER(x), ENTIER(y), 100H, char, char, 0)
		END RenderChar;
		
		(** return spacing of character code *)
		PROCEDURE GetGlyphSpacings*(code : LONGINT; VAR glyphSpacings : WMGraphics.GlyphSpacings);
		BEGIN
			glyphSpacings.width := 16;
			glyphSpacings.height := 16
		END GetGlyphSpacings;
		

	END Line16Font;
	

VAR
	w : WMWindowManager.BufferWindow;
	font : Line16Font;
	
PROCEDURE GetNCharHex(r : AosIO.Reader; nofChars : LONGINT) : LONGINT;
VAR c : CHAR; i, res : LONGINT;
BEGIN
	res := 0;
	FOR i := 0 TO nofChars - 1 DO
		c := r.Get();
		IF (c >= "0") & (c <= "9") THEN res := res * 16 + (ORD(c)-ORD("0")) 
		ELSE res := res * 16 + (ORD(CAP(c))-ORD("A") + 10)
		END
	END;
	RETURN res
END GetNCharHex;

PROCEDURE Dump*(par : ANY) : ANY;
VAR f : AosFS.File;
	r : AosFS.Reader;
	i : LONGINT;
BEGIN
	f := AosFS.Old("16x16.txt");
	AosFS.OpenReader(r, f, 0);
	font.Import(r);
	
	i := 0; 
	WHILE i < LEN(font.glyphs^) DO
		IF font.glyphs[i] # NIL THEN
			w.canvas.Fill(WMRectangles.MakeRect(0, 0, 200, 200), 0FFFFFFFFH, WMGraphics.ModeCopy); 
			font.RenderChar(w.canvas, 0, 0, font.glyphs[i].ucs);
			w.Invalidate(WMRectangles.MakeRect(0, 0, 200, 200))
		END;
		INC(i)
	END;
	RETURN NIL
END Dump;		

PROCEDURE Cleanup;
BEGIN
	w.Close	
END Cleanup;


BEGIN
	NEW(font);
	NEW(w, 200,200, FALSE);
	w.manager := WMWindowManager.GetDefaultManager();
	w.manager.Add(100, 100, w, {WMWindowManager.FlagFrame});
	AosModules.InstallTermHandler(Cleanup)
END WMLineFontEditor.

PED.Open 16x16.txt 

PED.Open WMBitmapFont.Mod 

S.Free WMLineFontEditor  
WMLineFontEditor.Dump 

