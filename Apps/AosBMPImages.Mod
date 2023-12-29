(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE AosBMPImages; (** portable **)	(* eos   *)
(** AUTHOR "eos"; PURPOSE "BMP image format"; *)

	(**
		Load and store Windows .BMP files
	**)
	
	(*
		19.06.2000 - Aos version
		
		- store files
		- support for JPEG and PNG compression in newer versions of file format
	*)
	
	IMPORT
		SYSTEM, AosOut, AosFS, Raster;
		
	
	CONST
		FileHeaderSize = 14;
		RGB = 0; RLE8 = 1; RLE4 = 2; BITFIELDS = 3;	(* compression *)
		
	
	PROCEDURE Log (msg: ARRAY OF CHAR);
	BEGIN
		AosOut.String("BMPImages: "); AosOut.String(msg); AosOut.Ln;
	END Log;
	
	PROCEDURE LogInt (msg: ARRAY OF CHAR; val: LONGINT);
		VAR i, j, n: LONGINT; s: ARRAY 100 OF CHAR;
	BEGIN
		i := 0; WHILE msg[i] # "%" DO s[i] := msg[i]; INC(i) END; j := i+1;
		n := 1000000; WHILE n > val DO n := n DIV 10 END;
		WHILE n > 1 DO s[i] := CHR(ORD("0") + val DIV n); INC(i); val := val MOD n; n := n DIV 10 END;
		s[i] := CHR(ORD("0") + val); INC(i);
		WHILE msg[j] # 0X DO s[i] := msg[j]; INC(i); INC(j) END;
		s[i] := 0X;
		Log(s)
	END LogInt;
	
	PROCEDURE Unmask (val, mask, nbits: LONGINT): LONGINT;
		VAR res, m, bits: LONGINT;
	BEGIN
		res := val; m := mask; bits := 0;
		WHILE (m # 0) & ~ODD(m) DO	(* shift down to first valid bit *)
			m := m DIV 2; res := res DIV 2
		END;
		WHILE ODD(m) DO	(* count valid bits *)
			m := m DIV 2; INC(bits)
		END;
		res := res MOD ASH(1, bits);	(* mask out everything else *)
		WHILE bits > nbits DO	(* reduce to requested number of bits *)
			res := res DIV 2; DEC(bits)
		END;
		WHILE bits < nbits DO	(* blow up to requested number of bits *)
			res := 2*res+1; INC(bits)
		END
	END Unmask;
	
	PROCEDURE Load1 (img: Raster.Image; w, h: LONGINT; VAR pal: Raster.Palette; VAR r: AosFS.Rider);
		VAR y, dy, x, p, b, i: LONGINT; fmt: Raster.Format; ch: CHAR;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		Raster.InitPaletteFormat(fmt, pal);
		Raster.Create(img, SHORT(w), SHORT(h), fmt);
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				r.file.Read(r, ch); b := ORD(ch);
				FOR i := -7 TO 0 DO
					IF x < w THEN
						img.mem[p] := CHR(ASH(b, i) MOD 2); INC(p)
					END;
					INC(x)
				END
			END;
			WHILE x MOD 32 # 0 DO r.file.Read(r, ch); INC(x, 8) END;	(* align to double word boundary *)
			DEC(h); INC(y, dy)
		END
	END Load1;
	
	PROCEDURE Load4 (img: Raster.Image; w, h, compression: LONGINT; pal: Raster.Palette; VAR r: AosFS.Rider);
		VAR y, dy, x, p, b, i: LONGINT; fmt: Raster.Format; ch: CHAR; col: ARRAY 2 OF CHAR;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		Raster.InitPaletteFormat(fmt, pal);
		Raster.Create(img, SHORT(w), SHORT(h), fmt);
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				r.file.Read(r, ch); b := ORD(ch);
				IF compression = RLE4 THEN
					r.file.Read(r, ch);
					IF b # 0 THEN	(* encoded mode *)
						i := 0; col[0] := CHR(ORD(ch) DIV 10H); col[1] := CHR(ORD(ch) MOD 10H);
						WHILE i < b DO
							img.mem[p] := col[i MOD 2]; INC(i); INC(p)
						END;
						INC(x, b)
					ELSIF ch = 0X THEN	(* end of line *)
						DEC(h); INC(y, dy); x := 0; p := y * img.bpr	(* align to double word boundary? *)
					ELSIF ch = 1X THEN	(* end of bitmap data *)
						RETURN
					ELSIF ch = 2X THEN	(* delta record *)
						r.file.Read(r, ch); INC(x, LONG(ORD(ch)));
						r.file.Read(r, ch); INC(y, LONG(ORD(ch))); p := y * img.bpr + x
					ELSE	(* absolute mode *)
						b := ORD(ch);
						FOR i := 1 TO b DO
							IF ODD(i) THEN r.file.Read(r, ch); img.mem[p] := CHR(ORD(ch) DIV 10H); INC(p)
							ELSE img.mem[p] := CHR(ORD(ch) MOD 10H); INC(p)
							END
						END;
						INC(x, b);
						IF ODD((b+1) DIV 2) THEN r.file.Read(r, ch) END;	(* align run length to even number of bytes *)
					END
				ELSE	(* uncompressed *)
					img.mem[p] := CHR(b DIV 10H); INC(p);
					IF x+1 < w THEN
						img.mem[p] := CHR(b MOD 10H); INC(p)
					END;
					INC(x, 2)
				END
			END;
			IF compression = RGB THEN	(* is this also needed for RLE4 compression? *)
				WHILE x MOD 8 # 0 DO r.file.Read(r, ch); INC(x, 2) END	(* align to double word boundary *)
			END;
			DEC(h); INC(y, dy)
		END
	END Load4;
	
	PROCEDURE Load8 (img: Raster.Image; w, h, compression: LONGINT; pal: Raster.Palette; VAR r: AosFS.Rider);
		VAR y, dy, x, p, b, i: LONGINT; fmt: Raster.Format; ch: CHAR;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		Raster.InitPaletteFormat(fmt, pal);
		Raster.Create(img, SHORT(w), SHORT(h), fmt);
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				r.file.Read(r, ch);
				IF compression = RLE8 THEN
					b := ORD(ch); r.file.Read(r, ch);
					IF b # 0 THEN	(* encoded mode *)
						FOR i := 1 TO b DO
							img.mem[p] := ch; INC(p)
						END;
						INC(x, b)
					ELSIF ch = 0X THEN	(* end of line *)
						DEC(h); INC(y, dy); x := 0; p := y * img.bpr	(* align to double word boundary? *)
					ELSIF ch = 1X THEN	(* end of bitmap data *)
						RETURN
					ELSIF ch = 2X THEN	(* delta record *)
						r.file.Read(r, ch); INC(x, LONG(ORD(ch)));
						r.file.Read(r, ch); INC(y, LONG(ORD(ch))); p := y * img.bpr + x
					ELSE	(* absolute mode *)
						b := ORD(ch);
						FOR i := 1 TO b DO
							r.file.Read(r, img.mem[p]); INC(p)
						END;
						INC(x, b);
						IF ODD(b) THEN r.file.Read(r, ch) END;	(* align run length to even number of bytes *)
					END
				ELSE	(* uncompressed *)
					img.mem[p] := ch; INC(p); INC(x)
				END
			END;
			IF compression = RGB THEN	(* is this also needed for RLE8 compression? *)
				WHILE x MOD 4 # 0 DO r.file.Read(r, ch); INC(x) END	(* align to double word boundary *)
			END;
			DEC(h); INC(y, dy)
		END
	END Load8;
	
	PROCEDURE Load16 (img: Raster.Image; w, h, compression, rMask, gMask, bMask: LONGINT; VAR r: AosFS.Rider);
		VAR y, dy, x, p, val, red, green, blue: LONGINT; convert: BOOLEAN; align: ARRAY 2 OF CHAR;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		convert := FALSE;
		IF (compression = RGB) OR (compression = BITFIELDS) & (rMask = 7C00H) & (gMask = 3E0H) & (bMask = 1FH) THEN
			Raster.Create(img, SHORT(w), SHORT(h), Raster.BGR555)
		ELSIF (compression = BITFIELDS) & (rMask = 0F800H) & (gMask = 7E0H) & (bMask = 1FH) THEN
			Raster.Create(img, SHORT(w), SHORT(h), Raster.BGR565)
		ELSIF (compression = BITFIELDS) & (rMask = 0FC00H) & (gMask = 3F0H) & (bMask = 0FH) THEN
			Raster.Create(img, SHORT(w), SHORT(h), Raster.BGR466)
		ELSE
			Raster.Create(img, SHORT(w), SHORT(h), Raster.BGR565);
			convert := TRUE
		END;
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				r.file.Read(r, img.mem[p]); r.file.Read(r, img.mem[p+1]);
				IF convert THEN
					val := ORD(img.mem[p]) + ASH(ORD(img.mem[p+1]), 8);
					red := Unmask(val, rMask, 5); green := Unmask(val, gMask, 6); blue := Unmask(val, bMask, 5);
					val := blue + ASH(green, 5) + ASH(red, 11);
					img.mem[p] := CHR(val); img.mem[p+1] := CHR(val DIV 100H);
				END;
				INC(x); INC(p, 2)
			END;
			IF ODD(w) THEN r.file.ReadBytes(r, align, 0, 2) END;
			DEC(h); INC(y, dy)
		END
	END Load16;
	
	PROCEDURE Load24 (img: Raster.Image; w, h: LONGINT; VAR r: AosFS.Rider);
		VAR y, dy, x, p: LONGINT; align: ARRAY 3 OF CHAR;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		Raster.Create(img, SHORT(w), SHORT(h), Raster.BGR888);
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				r.file.Read(r, img.mem[p]); r.file.Read(r, img.mem[p+1]); r.file.Read(r, img.mem[p+2]);
				INC(x); INC(p, 3)
			END;
			r.file.ReadBytes(r, align, 0, w MOD 4);
			DEC(h); INC(y, dy)
		END
	END Load24;
	
	PROCEDURE Load32 (img: Raster.Image; w, h, compression, rMask, gMask, bMask: LONGINT; VAR r: AosFS.Rider);
		VAR y, dy, x, p, val, red, green, blue: LONGINT; convert: BOOLEAN; ch: CHAR;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		Raster.Create(img, SHORT(w), SHORT(h), Raster.BGR888);
		convert := (compression = BITFIELDS) & ((rMask # 0FF0000H) OR (gMask # 0FF00H) OR (bMask # 0FFH));
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				r.file.Read(r, img.mem[p]); r.file.Read(r, img.mem[p+1]); r.file.Read(r, img.mem[p+2]); r.file.Read(r, ch);
				IF convert THEN
					val := ORD(img.mem[p]) + ASH(ORD(img.mem[p+1]), 8) + ASH(ORD(img.mem[p+2]), 16) + ASH(ORD(ch), 24);
					red := Unmask(val, rMask, 8); green := Unmask(val, gMask, 8); blue := Unmask(val, bMask, 8);
					img.mem[p] := CHR(blue); img.mem[p+1] := CHR(green); img.mem[p+2] := CHR(red)
				END;
				INC(x); INC(p, 3)
			END;
			DEC(h); INC(y, dy)
		END
	END Load32;
	
	PROCEDURE Load (img: Raster.Image; VAR fname: ARRAY OF CHAR; VAR done: BOOLEAN);
		VAR
			file: AosFS.File; r: AosFS.Rider; type: ARRAY 2 OF CHAR;
			size, reserved, offset, width, height, compression, colors, importantColors, col, redMask, greenMask, blueMask: LONGINT;
			planes, bpp: INTEGER; pal: Raster.Palette; pix: Raster.Pixel; ch: CHAR;
	BEGIN
		file := AosFS.Old(fname);
		IF file = NIL THEN RETURN END;
		file.Set(r, 0);
		
		(* bitmap file header *)
		r.file.ReadBytes(r, type, 0, 2);
		IF (type[0] # "B") OR (type[1] # "M") THEN RETURN END;
		AosFS.ReadLInt(r, size); AosFS.ReadLInt(r, reserved); AosFS.ReadLInt(r, offset);
		
		(* bitmap info header *)
		AosFS.ReadLInt(r, size);	(* size of bitmap info header *)
		IF size > 28H THEN Log("ignoring extra header fields") END;
		AosFS.ReadLInt(r, width); AosFS.ReadLInt(r, height);
		AosFS.ReadInt(r, planes);
		IF planes # 1 THEN LogInt("don't know how to treat % planes", planes) END;
		AosFS.ReadInt(r, bpp);
		IF ~((bpp = 1) OR (bpp = 4) OR (bpp = 8) OR (bpp = 16) OR (bpp = 24) OR (bpp = 32)) THEN
			LogInt("can't deal with % bits per pixel", bpp); RETURN
		END;
		AosFS.ReadLInt(r, compression);
		IF ~(compression IN {RGB, RLE8, RLE4, BITFIELDS}) THEN
			LogInt("can't deal with compression type %", compression); RETURN
		END;
		file.Set(r,  file.Pos(r) + 12); AosFS.ReadLInt(r, colors);
		IF (colors = 0) & (bpp < 16) THEN colors := ASH(1, bpp) END;
		AosFS.ReadLInt(r, importantColors);
		
		(* color table *)
		IF bpp < 16 THEN
			file.Set(r, FileHeaderSize + size);
			NEW(pal); col := 0; pix[Raster.a] := 0FFX;
			WHILE col < colors DO
				r.file.Read(r, pix[Raster.b]); r.file.Read(r, pix[Raster.g]); r.file.Read(r, pix[Raster.r]); r.file.Read(r, ch);
				pal.col[col] := pix;
				INC(col)
			END;
			Raster.InitPalette(pal, SHORT(colors), 2 + bpp DIV 4)
		ELSIF ((bpp = 16) OR (bpp = 32)) & (compression = BITFIELDS) THEN
			AosFS.ReadLInt(r, redMask); AosFS.ReadLInt(r, greenMask); AosFS.ReadLInt(r, blueMask)
		END;
		
		(* bitmap data *)
		file.Set(r, offset);
		CASE bpp OF
		| 1: Load1(img, width, height, pal, r)
		| 4: Load4(img, width, height, compression, pal, r)
		| 8: Load8(img, width, height, compression, pal, r)
		| 16: Load16(img, width, height, compression, redMask, greenMask, blueMask, r)
		| 24: Load24(img, width, height, r)
		| 32: Load32(img, width, height, compression, redMask, greenMask, blueMask, r)
		END;
		
		done := TRUE
	END Load;
	
	PROCEDURE Store1 (img: Raster.Image; w, h: LONGINT; VAR r: AosFS.Rider);
		VAR y, dy, x, p, b, i: LONGINT;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				b := 0;
				FOR i := -7 TO 0 DO
					IF x < w THEN b := ASH(b, 1) + ORD(img.mem[p]); INC(p) END;
					INC(x)
				END;
				r.file.Write(r, CHR(b))
			END;
			WHILE x MOD 32 # 0 DO r.file.Write(r, 0X); INC(x, 8) END;	(* Align to double word boundary *)
			DEC(h); INC(y, dy)
		END
	END Store1;

	PROCEDURE Store4 (img: Raster.Image; w, h: LONGINT; VAR r: AosFS.Rider);
		VAR y, dy, x, p, b: LONGINT;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				b := 0;
				b := ORD(img.mem[p]) MOD 10H; INC(p);
				IF x+1 < w THEN
					b := ASH(b, 4) + ORD(img.mem[p]) MOD 10H; INC(p)
				END;
				r.file.Write(r, CHR(b));
				INC(x, 2)
			END;
			DEC(h); INC(y, dy)
		END
	END Store4;

	PROCEDURE Store8 (img: Raster.Image; w, h: LONGINT; VAR r: AosFS.Rider);
		VAR y, dy, x, p: LONGINT;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				r.file.Write(r, img.mem[p]);
				INC(p); INC(x)
			END;
			DEC(h); INC(y, dy)
		END
	END Store8;

	PROCEDURE Store16 (img: Raster.Image; w, h, rMask, gMask, bMask: LONGINT; VAR r: AosFS.Rider);
		VAR y, dy, x, p: LONGINT; align: ARRAY 2 OF CHAR;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			r.file.WriteBytes(r, img.mem^, p, w * 2);
			IF ODD(w) THEN r.file.WriteBytes(r, align, 0, 2) END;
			DEC(h); INC(y, dy)
		END
	END Store16;

	PROCEDURE Store24 (img: Raster.Image; w, h: LONGINT; VAR r: AosFS.Rider);
		VAR y, dy, x, p: LONGINT; align: ARRAY 3 OF CHAR;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				r.file.Write(r, img.mem[p]); r.file.Write(r, img.mem[p+1]); r.file.Write(r, img.mem[p+2]);
				INC(x); INC(p, 3)
			END;
			r.file.WriteBytes(r, align, 0, w MOD 4);
			DEC(h); INC(y, dy)
		END
	END Store24;

	PROCEDURE Store32 (img: Raster.Image; w, h, rMask, gMask, bMask: LONGINT; VAR r: AosFS.Rider);
		VAR y, dy, x, p: LONGINT;
	BEGIN
		IF h > 0 THEN y := 0; dy := 1
		ELSE h := -h; y := h-1; dy := -1
		END;
		WHILE h > 0 DO
			x := 0; p := y * img.bpr;
			WHILE x < w DO
				r.file.Write(r, img.mem[p]); r.file.Write(r, img.mem[p+1]); r.file.Write(r, img.mem[p+2]); r.file.Write(r, img.mem[p+3]);
				INC(x); INC(p, 4)
			END;
			DEC(h); INC(y, dy)
		END
	END Store32;

	PROCEDURE Store (img: Raster.Image; VAR fname: ARRAY OF CHAR; VAR done: BOOLEAN);
		VAR
			file: AosFS.File; r: AosFS.Rider;
			col, redMask, greenMask, blueMask: LONGINT;
			Tag: ARRAY 6 OF CHAR; pos, posdata: LONGINT; bpp: INTEGER;
	BEGIN
		file := AosFS.New(fname);
		file.Set(r, 0);

		(* Bitmap file header *)
		Tag := "BM";
		r.file.WriteBytes(r, Tag, 0, 2);
		Tag[0] := 00X; Tag[1] := 00X; Tag[3] := 00X; Tag[4] := 00X;
		r.file.WriteBytes(r, Tag, 0, 4);
		r.file.WriteBytes(r, Tag, 0, 4);
		r.file.WriteBytes(r, Tag, 0, 4);

		(* Bitmap info header *)
		AosFS.WriteLInt(r, 40);
		AosFS.WriteLInt(r, img.width);
		AosFS.WriteLInt(r, img.height);
		AosFS.WriteInt(r, 1);	(* biPlanes *)
		IF img.fmt.pal # NIL THEN
			CASE img.fmt.pal.used OF
				  2: bpp := 1
				| 16: bpp := 4
				| 256: bpp := 8
			ELSE
			END
		ELSIF (img.fmt.code = Raster.bgr565) OR (img.fmt.code = Raster.bgr555) OR (img.fmt.code = Raster.bgr466) THEN
			bpp := 16
		ELSIF img.fmt.code = Raster.bgr888 THEN bpp := 24
		ELSIF img.fmt.code = Raster.bgra8888 THEN bpp := 32
		END;
		AosFS.WriteInt(r, bpp);	(* biBitCount *)
		(* biCompression *)
		CASE img.fmt.code OF
			  Raster.bgr565: AosFS.WriteLInt(r, BITFIELDS)	(* BITFIELDS compression *)
			| Raster.bgr555: AosFS.WriteLInt(r, BITFIELDS)	(* BITFIELDS compression *)
			| Raster.bgr466: AosFS.WriteLInt(r, BITFIELDS)	(* BITFIELDS compression *)
			| Raster.bgra8888: AosFS.WriteLInt(r, BITFIELDS)	(* BITFIELDS compression *)
		ELSE
			r.file.WriteBytes(r, Tag, 0, 4);
		END;
		r.file.WriteBytes(r, Tag, 0, 4);	(* biSizeImage *)
		r.file.WriteBytes(r, Tag, 0, 4);	(* biXPelsPerMeter *)
		r.file.WriteBytes(r, Tag, 0, 4);	(* biYPelsPerMeter *)
		IF img.fmt.pal # NIL THEN
			AosFS.WriteLInt(r, img.fmt.pal.used);	(* biClrUsed *)
			AosFS.WriteLInt(r, img.fmt.pal.used);	(* biClrImportant *)

			(* RGBQUAD color table *)
			col := 0;
			WHILE col < img.fmt.pal.used DO
				r.file.Write(r, img.fmt.pal.col[col, Raster.b]);
				r.file.Write(r, img.fmt.pal.col[col, Raster.g]);
				r.file.Write(r, img.fmt.pal.col[col, Raster.r]);
				r.file.Write(r, 0X);
				INC(col)
			END
		ELSE
			r.file.WriteBytes(r, Tag, 0, 4);
			r.file.WriteBytes(r, Tag, 0, 4)
		END;

		CASE img.fmt.code OF
			  Raster.bgr565: AosFS.WriteLInt(r, 0F800H); AosFS.WriteLInt(r, 07E0H); AosFS.WriteLInt(r, 01FH)
			| Raster.bgr555: AosFS.WriteLInt(r, 07C00H); AosFS.WriteLInt(r, 03E0H); AosFS.WriteLInt(r, 01FH)
			| Raster.bgr466: AosFS.WriteLInt(r, 0FC00H); AosFS.WriteLInt(r, 03F0H); AosFS.WriteLInt(r, 00FH)
			| Raster.bgr888: AosFS.WriteLInt(r, 0FF00H); AosFS.WriteLInt(r, 0FF0H); AosFS.WriteLInt(r, 0FFH)
			| Raster.bgra8888: AosFS.WriteLInt(r, 0FF0000H); AosFS.WriteLInt(r, 0FF00H); AosFS.WriteLInt(r, 0FFH)
		ELSE
		END;

		posdata := r.file.Pos(r);
		file.Set(r, 10);
		AosFS.WriteLInt(r, posdata);
		file.Set(r, posdata);

		(* Bitmap data *)
		IF img.fmt.code = Raster.bgra8888 THEN Store32(img, img.width, -img.height, redMask, greenMask, blueMask, r)
		ELSIF img.fmt.code = Raster.bgr888 THEN Store24(img, img.width, -img.height, r)
		ELSIF img.fmt.code = Raster.bgr466 THEN Store16(img, img.width, -img.height, redMask, greenMask, blueMask, r)
		ELSIF img.fmt.code = Raster.bgr555 THEN Store16(img, img.width, -img.height, redMask, greenMask, blueMask, r)
		ELSIF img.fmt.code = Raster.bgr565 THEN Store16(img, img.width, -img.height, redMask, greenMask, blueMask, r)
		ELSIF img.fmt.pal.used = 256 THEN Store8(img, img.width, -img.height, r)
		ELSIF img.fmt.pal.used = 16 THEN Store4(img, img.width, -img.height, r)
		ELSIF img.fmt.pal.used = 2 THEN Store1(img, img.width, -img.height, r)
		END;
		pos := r.file.Pos(r);
		file.Set(r, 2);
		AosFS.WriteLInt(r, pos);
		file.Set(r, 34);
		AosFS.WriteLInt(r, pos - posdata);
		AosFS.Register (file);
		done := TRUE
	END Store;
	
	PROCEDURE AosLoad*(x: PTR) : PTR;
	BEGIN
		IF x IS Raster.PictureTransferParameters THEN WITH x:Raster.PictureTransferParameters DO
			Load(x.img, x.name, x.done);
			Raster.Init(x.img, x.img.width, x.img.height, x.img.fmt, -x.img.bpr, SYSTEM.ADR(x.img.mem[0]) + (x.img.height-1)*x.img.bpr);
		END END;	
		RETURN NIL
	END AosLoad;
	
	PROCEDURE AosStore*(x: PTR) : PTR;
	BEGIN
		IF x IS Raster.PictureTransferParameters THEN WITH x:Raster.PictureTransferParameters DO
			Store(x.img, x.name, x.done)
		END END;	
		RETURN NIL
	END AosStore;
	
END AosBMPImages.
