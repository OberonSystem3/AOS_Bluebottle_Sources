MODULE Raster; (** non-portable *)	(* eos  **)
(** AUTHOR "eos"; PURPOSE "Raster operations"; *)

	(**
		Raster image bitmaps and basic image processing
	**)
	
	(*
		19.9.1999 - spawned from GfxMaps
		25.10.1999 - fixed bytes-per-row calculation in Create (need to make arguments LONG)
		17.11.1999 - eliminated F8 format, replaced by D8 (implemented with module Colors)
		19.11.1999 - fixed missing alpha component in computed palettes
		16.05.2000 - module Raster as Oberon-independent part of Images
		19.06.2000 - replaced DisplayFormat and InitDisplay by DisplayFormat()
		
		To do:
		- store in compressed format
	*)
	
	IMPORT
		SYSTEM, AosOut, AosBoot, AosIO, AosFS, AosModules, AosCLUTs, AosPlugins, AosDisplays, AosConfig;
		
	
	(*
		Interfacing with display hardware and foreign framebuffers may suffer a performance hit if their
		bit or byte ordering can't be made compatible with that of a built-in format and has to be converted
		manually. Predefined format A1 has the leftmost pixel in the least significant bit of a byte, and
		all hi/true color formats have their blue component at the lowest address, followed by green,
		red, and possibly alpha (which conforms to the specification of the transfer formats in AosDisplays).
		
		As SYSTEM is imported, the module is not portable and has always to be compiled to native code.
		However, it should usually suffice to recompile the module on other platforms without changing
		any code.
		
		Assumptions:
			* CHR(l) = CHR(l MOD 100H) for all l: LONGINT
			* SIZE(LONGINT)=4
	*)
	
	
	CONST
		b* = 0; g* = 1; r* = 2; a* = 3;	(** index of blue, green, red, and alpha components in a Pixel **)
		
		(** format codes **)
		custom* = 0; a1* = 1; a8* = 2; d8* = 3; p8* = 4; bgr555* = 5; bgr565* = 6; bgr466* = 7; bgr888* = 8; bgra8888* = 9;
		
		(** components **)
		color* = 0; alpha* = 1; index* = 2;
	
		(** compositing operations (srcCopy = replace, srcOverDst = paint **)
		clear* = 0; srcCopy* = 1; dstCopy* = 2; srcOverDst* = 3; dstOverSrc* = 4; srcInDst* = 5; dstInSrc* = 6;
		srcWithoutDst* = 7; dstWithoutSrc* = 8; srcAtopDst* = 9; dstAtopSrc* = 10; srcXorDst* = 11; InvDst*=12;
		InvOverDst*=13;		
	
	TYPE
		(** general pixels with red, green, blue, and alpha information in range 0..255; alpha is pre-multiplied into RGB **)
		Pixel* = ARRAY 4 OF CHAR;
		
		(** palette structure for indexed formats **)
		Palette* = POINTER TO PaletteDesc;
		PaletteDesc* = RECORD
			col*: ARRAY 256 OF Pixel;	(** color table **)
			used*: LONGINT;	(** number of valid entries in color table **)
			clut: AosCLUTs.CLUT;	(* reverse color lookup structure *)
		END;
		
		(** image format **)
		Format0* = RECORD
			code*: SHORTINT;	(** format code for quick format checks **)
			bpp*: SHORTINT;	(** number of bits per pixel **)
			align*: SHORTINT;	(** bytes per row must be multiple of this **)
			components*: SET;	(** components that are stored in a pixel **)
			pal*: Palette;	(** optional palette for indexed formats **)
		END;
		
		PackProc* = PROCEDURE (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		
		Format* = RECORD (Format0)
			pack*: PackProc;	(** store supported pixel components at given address **)
			unpack*: PackProc;	(** load supported pixel components from given address **)
		END;
		
		(** raster image **)
		Image* = POINTER TO ImageDesc;
		ImageDesc* = RECORD
			width*, height*: LONGINT;	(** image dimensions **)
			fmt*: Format;	(** pixel format **)
			bpr*: LONGINT;	(** number of bytes per row (may be negative) **)
			adr*: LONGINT;	(** address of lower left pixel **)
			mem*: POINTER TO ARRAY OF CHAR;	(** block where pixels are stored; mem#NIL implies adr=ADR(mem[0]) **)
		END;
		
		(** transfer mode **)
		Mode0* = RECORD
			src*, dst*: Format;	(** source and destination format **)
			op*: SHORTINT;	(** compositing operation **)
			col*: Pixel;	(** substitute color used when transfering from pure alpha formats to colored ones **)
			buf: Pixel;	(* constant area for special-case moving *)
			map: ARRAY 256 OF CHAR;	(* color map for transfer between indexed formats *)
		END;
		
		TransferProc* = PROCEDURE (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		
		Mode* = RECORD (Mode0)
			transfer*: TransferProc;	(** procedure transfering pixels from source to destination **)
		END;
		
		PictureTransferParameters* = POINTER TO RECORD
			img* : Image;
			name* : ARRAY 128 OF CHAR;
			done* : BOOLEAN
		END;
		
	VAR
		A1*, A8*, D8*, BGR555*, BGR565*, BGR466*, BGR888*, BGRA8888*: Format;	(** predefined formats **)
		PixelFormat*: Format;	(** special formats **)
	
		Clamp*: ARRAY 500H OF CHAR;	(** Clamp[200H+i] = CHR(min(max(i, 0), 0FFH)) **)
		
(*		LoadProc*: PROCEDURE (img: Image; VAR fname: ARRAY OF CHAR; VAR done: BOOLEAN);
		StoreProc*: PROCEDURE (img: Image; VAR fname: ARRAY OF CHAR; VAR done: BOOLEAN); *)
		
		Zero: Pixel;	(* pixel with all components cleared *)
		Bit: ARRAY 100H, 8 OF BOOLEAN;	(* Bit[b, i] means bit i in byte b is set *)
		Set, Clr: ARRAY 100H, 8 OF CHAR;	(* Set/Clr[b, i] is byte b with bit i set/cleared *)
		
		d8display: AosDisplays.Display;	(* only one system-wide D8 display supported *)
		plugin: AosPlugins.Plugin;
		
		MMXenabled* : BOOLEAN;
	
	(**--- Color/Pixel conversions ---**)
	
	(** set pixel to opaque RGB value **)
	PROCEDURE SetRGB* (VAR pix: Pixel; red, green, blue: LONGINT);
	BEGIN
		pix[b] := CHR(blue); pix[g] := CHR(green); pix[r] := CHR(red); pix[a] := 0FFX
	END SetRGB;
	
	(** set pixel to partly transparent RGB value **)
	PROCEDURE SetRGBA* (VAR pix: Pixel; red, green, blue, alpha: LONGINT);
	BEGIN
		pix[b] := CHR(blue * alpha DIV 255);
		pix[g] := CHR(green * alpha DIV 255);
		pix[r] := CHR(red * alpha DIV 255);
		pix[a] := CHR(alpha)
	END SetRGBA;
	
	(** retrieve RGB and alpha values from pixel **)
	PROCEDURE GetRGBA* (pix: Pixel; VAR red, green, blue, alpha: LONGINT);
	BEGIN
		alpha := ORD(pix[a]);
		IF alpha = 0 THEN	(* color has disappeared *)
			red := 255; green := 255; blue := 255
		ELSE
			red := ORD(pix[r]); green := ORD(pix[g]); blue := ORD(pix[b]);
			IF alpha # 255 THEN	(* un-multiply alpha *)
				red := 255 * red DIV alpha; IF red > 255 THEN red := 255 END;
				green := 255 * green DIV alpha; IF green > 255 THEN green := 255 END;
				blue := 255 * blue DIV alpha; IF blue > 255 THEN blue := 255 END
			END
		END
	END GetRGBA;
	
	
	(**--- Palettes ---**)
	
	(** return index of color in palette which approximates the requested color reasonably well **)
	PROCEDURE PaletteIndex* (pal: Palette; red, green, blue: LONGINT): LONGINT;
	BEGIN
		RETURN AosCLUTs.Match(pal.clut, ASH(red, 16) + ASH(green, 8) +  blue)
	END PaletteIndex;
	
	(** compute internal palette structures whenever palette colors have been modified **)
	PROCEDURE InitPalette* (pal: Palette; used, bits: LONGINT);
		VAR n, red, green, blue, alpha: LONGINT;
	BEGIN
		n := 0;
		WHILE n < used DO
			GetRGBA(pal.col[n], red, green, blue, alpha);
			AosCLUTs.Set(pal.clut, n, ASH(red, 16) + ASH(green, 8) + blue);
			INC(n)
		END;
		AosCLUTs.Init(pal.clut, used, bits);
		pal.used := used
	END InitPalette;
	
	(** copy palette contents **)
	PROCEDURE CopyPalette* (from, to: Palette);
		VAR n: LONGINT;
	BEGIN
		n := 0;
		WHILE n < from.used DO
			to.col := from.col; INC(n)
		END;
		to.used := from.used;
		AosCLUTs.Copy(from.clut, to.clut)
	END CopyPalette;
	
	(** compute and initialize a pseudo-optimal palette for an image (in hi-color or true-color format) **)
	PROCEDURE ComputePalette* (img: Image; pal: Palette; reservedcols, maxcols, bits: LONGINT);
		(*
			uses octree-quantization
		*)
		
		TYPE
			Node = POINTER TO RECORD	(* octree node *)
				dsc: ARRAY 8 OF Node;	(* descendants *)
				link: Node;	(* next reducible node on same level *)
				leaf: BOOLEAN;
				weight: LONGINT;	(* accumulated number of pixels represented by this node *)
				r, g, b: LONGINT;	(* accumulated color values *)
			END;
		
		VAR
			sent, root: Node; reducible: ARRAY 8 OF Node; colors, maxDepth, y, adr, x, aa, bb, used: LONGINT; pix: Pixel;
		
		PROCEDURE insert (VAR node: Node; depth: LONGINT; pix: Pixel);
			VAR idx, bit: LONGINT;
		BEGIN
			IF node = NIL THEN
				NEW(node);
				IF depth = maxDepth THEN
					node.leaf := TRUE;
					INC(colors)
				ELSE
					node.leaf := FALSE;
					node.link := reducible[depth]; reducible[depth] := node
				END
			END;
			INC(node.weight);	(* node represents more pixels *)
			IF node.leaf THEN
				INC(node.r, LONG(ORD(pix[r])));
				INC(node.g, LONG(ORD(pix[g])));
				INC(node.b, LONG(ORD(pix[b])))
			ELSE
				idx := 0; bit := 7-depth;
				IF ODD(ASH(ORD(pix[r]), -bit)) THEN INC(idx, 4) END;
				IF ODD(ASH(ORD(pix[g]), -bit)) THEN INC(idx, 2) END;
				IF ODD(ASH(ORD(pix[b]), -bit)) THEN INC(idx) END;
				insert(node.dsc[idx], depth+1, pix)
			END
		END insert;
		
		PROCEDURE reduce;
			VAR d, min, n, i: LONGINT; node, prev, dsc: Node;
		BEGIN
			d := maxDepth-1;
			WHILE reducible[d] = NIL DO
				DEC(d); DEC(maxDepth)
			END;
			sent.link := reducible[d];
			node := sent; min := MAX(LONGINT);
			WHILE node.link # NIL DO
				IF node.link.weight < min THEN
					min := node.link.weight; prev := node
				END;
				node := node.link
			END;
			node := prev.link; prev.link := node.link;
			reducible[d] := sent.link;
			n := 1;	(* number of colors is initially one for the node itself *)
			FOR i := 0 TO 7 DO
				dsc := node.dsc[i];
				IF dsc # NIL THEN
					DEC(n);	(* reducing one color *)
					INC(node.r, dsc.r); INC(node.g, dsc.g); INC(node.b, dsc.b);
					node.dsc[i] := NIL
				END
			END;
			node.leaf := TRUE;
			INC(colors, n)
		END reduce;
		
		PROCEDURE traverse (node: Node);
			VAR i: LONGINT;
		BEGIN
			IF node # NIL THEN
				IF node.leaf THEN
					pal.col[used, r] := CHR(node.r DIV node.weight);
					pal.col[used, g] := CHR(node.g DIV node.weight);
					pal.col[used, b] := CHR(node.b DIV node.weight);
					pal.col[used, a] := 0FFX;
					INC(used)
				ELSE
					FOR i := 0 TO 7 DO
						traverse(node.dsc[i])
					END
				END
			END
		END traverse;
		
	BEGIN	(* ComputePalette *)
		ASSERT(reservedcols + maxcols <= 256, 100);
		NEW(sent);
		root := NIL; colors := 0; maxDepth := 8;
		y := 0; adr := img.adr;
		WHILE y < img.height DO
			IF img.fmt.bpp < 8 THEN
				x := 0; aa := adr; bb := 0;
				WHILE x < img.width DO
					img.fmt.unpack(img.fmt, aa, bb, pix);
					insert(root, 0, pix);
					WHILE colors > maxcols DO
						reduce()
					END;
					INC(x); bb := bb + img.fmt.bpp; INC(aa, bb DIV 8); bb := bb MOD 8
				END
			ELSE
				x := 0; aa := adr; bb := img.fmt.bpp DIV 8;
				WHILE x < img.width DO
					img.fmt.unpack(img.fmt, aa, 0, pix);
					insert(root, 0, pix);
					WHILE colors > maxcols DO
						reduce()
					END;
					INC(x); INC(aa, bb)
				END
			END;
			INC(y); INC(adr, img.bpr)
		END;
		used := reservedcols;
		traverse(root);
		InitPalette(pal, used, bits)
	END ComputePalette;
	
	
	(**--- Formats ---**)
	
	(* A1 - one bit alpha, MSB leftmost *)
	PROCEDURE PackA1 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR b: CHAR;
	BEGIN
		SYSTEM.GET(adr, b);
		IF pix[a] >= 80X THEN SYSTEM.PUT(adr, Set[ORD(b), bit])
		ELSE SYSTEM.PUT(adr, Clr[ORD(b), bit])
		END
	END PackA1;
	
	PROCEDURE UnpackA1 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR b: CHAR;
	BEGIN
		SYSTEM.GET(adr, b);
		IF Bit[ORD(b), bit] THEN pix[a] := 0FFX
		ELSE pix := Zero
		END
	END UnpackA1;
	
	(* A8 - 8 bit alpha *)
	PROCEDURE PackA8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.PUT(adr, pix[a])
	END PackA8;
	
	PROCEDURE UnpackA8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR alpha: LONGINT;
	BEGIN
		SYSTEM.GET(adr, pix[a]);
		IF pix[a] = 0X THEN
			pix := Zero
		ELSIF pix[a] # 0FFX THEN
			alpha := ORD(pix[a]);
			pix[r] := CHR(ORD(pix[r]) * alpha DIV 255);
			pix[g] := CHR(ORD(pix[g]) * alpha DIV 255);
			pix[b] := CHR(ORD(pix[b]) * alpha DIV 255)
		END
	END UnpackA8;
	
	(* P8 - 8 bit indexed format with custom palette *)
	PROCEDURE PackP8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		IF pix[a] # 0X THEN	(* model alpha as brightness *)
			SYSTEM.PUT(adr, CHR(AosCLUTs.Match(fmt.pal.clut, ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))))
		END
	END PackP8;
	
	PROCEDURE UnpackP8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR idx: CHAR;
	BEGIN
		SYSTEM.GET(adr, idx); pix := fmt.pal.col[ORD(idx)]
	END UnpackP8;
	
	(* D8 - 8 bit indexed format with display palette *)
	PROCEDURE PackD8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		IF pix[a] # 0X THEN	(* model alpha as brightness *)
			SYSTEM.PUT(adr, CHR(d8display.ColorToIndex(ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))))
		END
	END PackD8;
	
	PROCEDURE UnpackD8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR idx: CHAR; col: LONGINT;
	BEGIN
		SYSTEM.GET(adr, idx); col := d8display.IndexToColor(ORD(idx));
		pix[b] := CHR(col MOD 100H); pix[g] := CHR(ASH(col, -8) MOD 100H); pix[r] := CHR(ASH(col, -16) MOD 100H)
	END UnpackD8;
	
	(* BGR555 - 16 hi-color with 5 bit blue, 5 bit green and 5 bit red in ascending order *)
	PROCEDURE PackBGR555 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR int: LONGINT;
	BEGIN
		IF pix[a] # 0X THEN	(* model alpha as brightness *)
			int := ASH(ORD(pix[b]), -3) + ASH(ASH(ORD(pix[g]), -3), 5) + ASH(ASH(ORD(pix[r]), -3), 10);
			SYSTEM.PUT(adr, CHR(int)); SYSTEM.PUT(adr+1, CHR(ASH(int, -8)))
		END
	END PackBGR555;
	
	PROCEDURE UnpackBGR555 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR lo, hi: CHAR; int: LONGINT;
	BEGIN
		SYSTEM.GET(adr, lo); SYSTEM.GET(adr+1, hi); int := ASH(ORD(hi), 8) + ORD(lo);
		pix[b] := CHR(ASH(int MOD 20H, 3) + 4);
		pix[g] := CHR(ASH(ASH(int, -5) MOD 20H, 3) + 4);
		pix[r] := CHR(ASH(ASH(int, -10) MOD 20H, 3) + 4);
		pix[a] := 0FFX
	END UnpackBGR555;
	
	(* BGR565 - 16 hi-color with 5 bit blue, 6 bit green and 5 bit red in ascending order *)
	PROCEDURE PackBGR565 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR int: LONGINT;
	BEGIN
		IF pix[a] # 0X THEN	(* model alpha as brightness *)
			int := ASH(ORD(pix[b]), -3) + ASH(ASH(ORD(pix[g]), -2), 5) + ASH(ASH(ORD(pix[r]), -3), 11);
			SYSTEM.PUT(adr, CHR(int)); SYSTEM.PUT(adr+1, CHR(ASH(int, -8)))
		END
	END PackBGR565;
	
	PROCEDURE UnpackBGR565 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR lo, hi: CHAR; int: LONGINT;
	BEGIN
		SYSTEM.GET(adr, lo); SYSTEM.GET(adr+1, hi); int := ASH(ORD(hi), 8) + ORD(lo);
		pix[b] := CHR(ASH(int MOD 20H, 3) + 4);
		pix[g] := CHR(ASH(ASH(int, -5) MOD 40H, 2) + 2);
		pix[r] := CHR(ASH(ASH(int, -11) MOD 20H, 3) + 4);
		pix[a] := 0FFX
	END UnpackBGR565;
	
	(* BGR466 - 16 hi-color with 4 bit blue, 6 bit green and 6 bit red in ascending order *)
	PROCEDURE PackBGR466 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR int: LONGINT;
	BEGIN
		IF pix[a] # 0X THEN	(* model alpha as brightness *)
			int := ASH(ORD(pix[b]), -4) + ASH(ASH(ORD(pix[g]), -2), 4) + ASH(ASH(ORD(pix[r]), -2), 10);
			SYSTEM.PUT(adr, CHR(int)); SYSTEM.PUT(adr+1, CHR(ASH(int, -8)))
		END
	END PackBGR466;
	
	PROCEDURE UnpackBGR466 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR lo, hi: CHAR; int: LONGINT;
	BEGIN
		SYSTEM.GET(adr, lo); SYSTEM.GET(adr+1, hi); int := ASH(ORD(hi), 8) + ORD(lo);
		pix[b] := CHR(ASH(int MOD 10H, 4) + 8);
		pix[g] := CHR(ASH(ASH(int, -4) MOD 40H, 2) + 2);
		pix[r] := CHR(ASH(ASH(int, -10) MOD 40H, 2) + 2);
		pix[a] := 0FFX
	END UnpackBGR466;
	
	(* BGR888 - 24 bit true color with blue in lower, green in middle, and red in upper byte *)
	PROCEDURE PackBGR888 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		IF pix[a] # 0X THEN	(* model alpha as brightness *)
			SYSTEM.MOVE(SYSTEM.ADR(pix[0]), adr, 3)
		END
	END PackBGR888;
	
	PROCEDURE UnpackBGR888 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.MOVE(adr, SYSTEM.ADR(pix[0]), 3); pix[a] := 0FFX
	END UnpackBGR888;
	
	(* BGRA8888 - 32 bit true color with blue in lowest, green in lower middle, red in upper middle, and alpha in top byte *)
	PROCEDURE PackBGRA8888 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.MOVE(SYSTEM.ADR(pix[0]), adr, 4)
	END PackBGRA8888;
	
	PROCEDURE UnpackBGRA8888 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.MOVE(adr, SYSTEM.ADR(pix[0]), 4)
	END UnpackBGRA8888;
	
	(** return image format for given AosDisplays transfer format **)
	PROCEDURE DisplayFormat* (format: LONGINT): Format;
	BEGIN
		CASE format OF
		| AosDisplays.index8: RETURN D8
		| AosDisplays.color565: RETURN BGR565
		| AosDisplays.color888: RETURN BGR888
		| AosDisplays.color8888: RETURN BGRA8888
		END
	END DisplayFormat;
	
	(** initialize format **)
	PROCEDURE InitFormat* (VAR fmt: Format; code, bpp, align: SHORTINT; comps: SET; pal: Palette; pack, unpack: PackProc);
	BEGIN
		fmt.code := code; fmt.bpp := bpp; fmt.align := align; fmt.components := comps; fmt.pal := pal;
		fmt.pack := pack; fmt.unpack := unpack
	END InitFormat;
	
	(** initialize 8 bit index format with custom palette **)
	PROCEDURE InitPaletteFormat* (VAR fmt: Format; pal: Palette);
	BEGIN
		fmt.code := p8; fmt.bpp := 8; fmt.align := 1; fmt.components := {index}; fmt.pal := pal;
		fmt.pack := PackP8; fmt.unpack := UnpackP8
	END InitPaletteFormat;
	
	(** return if two formats are the same **)
	PROCEDURE Same* (VAR fmt0, fmt1: Format): BOOLEAN;
	BEGIN
		RETURN
			(fmt0.pack = fmt1.pack) & (fmt0.unpack = fmt1.unpack) &
			(~(index IN fmt0.components) OR (fmt0.pal = fmt1.pal))	(* doesn't work if palette has been re-initialized *)
	END Same;
	
	
	(**--- Images ---**)
	
	(** initialize custom image **)
	PROCEDURE Init* (img: Image; width, height: LONGINT; VAR fmt: Format; bpr, adr: LONGINT);
	BEGIN
		ASSERT((width > 0) & (height > 0), 100);
		img.width := width; img.height := height; img.fmt := fmt; img.bpr := bpr; img.adr := adr
	END Init;
	
	(** initialize custom image on byte buffer **)
	PROCEDURE InitBuf* (img: Image; width, height: LONGINT; VAR fmt: Format; bpr, offset: LONGINT; VAR buf: ARRAY OF CHAR);
	BEGIN
		ASSERT((0 <= offset) & (offset + height * ABS(bpr) <= LEN(buf)), 100);
		IF bpr >= 0 THEN Init(img, width, height, fmt, bpr, SYSTEM.ADR(buf[0]))
		ELSE Init(img, width, height, fmt, bpr, SYSTEM.ADR(buf[offset]) + LEN(buf) - bpr)
		END
	END InitBuf;
	
	(** initialize image on rectangular area within existing image (lower left corner must fall on byte boundary) **)
	PROCEDURE InitRect* (img, base: Image; x, y, w, h: LONGINT);
	BEGIN
		ASSERT((0 <= x) & (x + w <= base.width) & (0 <= y) & (y + h <= base.height), 100);
		ASSERT(x * base.fmt.bpp MOD 8 = 0, 101);
		Init(img, w, h, base.fmt, base.bpr, base.adr + y * base.bpr + x * base.fmt.bpp DIV 8)
	END InitRect;
	
	(** create image in requested format (allocating or reusing necessary memory) **)
	PROCEDURE Create* (img: Image; width, height: LONGINT; fmt: Format);
		VAR size, a0, a1: LONGINT;
	BEGIN
		ASSERT((width > 0) & (height > 0), 100);
		img.width := width; img.height := height;
		img.fmt := fmt;
		img.bpr := (width * fmt.bpp + 7) DIV 8;
		IF fmt.align > 1 THEN
			img.bpr := (img.bpr + fmt.align - 1) DIV fmt.align * fmt.align
		END;
		size := height * img.bpr; INC(size, (-size) MOD 4);
		IF (img.mem = NIL) OR (size < LEN(img.mem^) DIV 2) OR (LEN(img.mem^) < size) THEN
			NEW(img.mem, size)
		ELSE
			a0 := SYSTEM.ADR(img.mem[0]); a1 := a0 + size;
			WHILE a0 # a1 DO
				SYSTEM.PUT32(a0,0); INC(a0, SIZE(LONGINT))
			END
		END;
		img.adr := SYSTEM.ADR(img.mem[0])
	END Create;
	
	
	(**--- Transfer Modes ---**)
	
	(** initialize transfer mode **)
	PROCEDURE InitMode* (VAR mode: Mode; op: SHORTINT);
	BEGIN
		mode.op := op;
		(*SetRGB(mode.col, 255, 255, 255);*)
		mode.col := SYSTEM.VAL(Pixel, -1);
		mode.src.pack := NIL; mode.dst.pack := NIL	(* force re-evaluation of transfer procedure *)
	END InitMode;
	
	(** initialize transfer mode with color components for pure alpha sources **)
	PROCEDURE InitModeColor* (VAR mode: Mode; op: SHORTINT; red, green, blue: LONGINT);
	BEGIN
		mode.op := op;
		SetRGB(mode.col, red, green, blue);
		mode.src.pack := NIL; mode.dst.pack := NIL
	END InitModeColor;
	
	(** set new source color for transfer mode **)
	PROCEDURE SetModeColor* (VAR mode: Mode; red, green, blue: LONGINT);
	BEGIN
		SetRGB(mode.col, red, green, blue);
		mode.src.pack := NIL; mode.dst.pack := NIL
	END SetModeColor;
	
	(** blend source pixel into destination pixel according to compositing operation **)
	PROCEDURE Blend* (op: SHORTINT; VAR src, dst: Pixel);
		VAR fs, fd, i: LONGINT;
	BEGIN
		CASE op OF
		| clear: fs := 0; fd := 0
		| srcCopy: fs := 255; fd := 0
		| dstCopy: fs := 0; fd := 255
		| srcOverDst: fs := 255; fd := 255-ORD(src[a])
		| dstOverSrc: fs := 255-ORD(dst[a]); fd := 255
		| srcInDst: fs := ORD(dst[a]); fd := 0
		| dstInSrc: fs := 0; fd := ORD(src[a])
		| srcWithoutDst: fs := 255-ORD(dst[a]); fd := 0
		| dstWithoutSrc: fs := 0; fd := 255-ORD(src[a])
		| srcAtopDst: fs := ORD(dst[a]); fd := 255-ORD(src[a])
		| dstAtopSrc: fs := 255-ORD(dst[a]); fd := ORD(src[a])
		| srcXorDst: fs := 255-ORD(dst[a]); fd := 255-ORD(src[a])
		END;
		
		IF fs + fd = 0 THEN
			FOR i := 0 TO 3 DO dst[i] := 0X END
		ELSIF fs = 0 THEN
			IF fd # 255 THEN
				FOR i := 0 TO 3 DO
					dst[i] := Clamp[200H + fd * ORD(dst[i]) DIV 255]
				END
			END
		ELSIF fd = 0 THEN
			IF fs = 255 THEN
				dst := src
			ELSE
				FOR i := 0 TO 3 DO
					dst[i] := Clamp[200H + fs * ORD(src[i]) DIV 255]
				END
			END
		ELSE
			dst[0] := Clamp[200H + (fs * ORD(src[0]) + fd * ORD(dst[0])) DIV 255];
			dst[1] := Clamp[200H + (fs * ORD(src[1]) + fd * ORD(dst[1])) DIV 255];
			dst[2] := Clamp[200H + (fs * ORD(src[2]) + fd * ORD(dst[2])) DIV 255];
			dst[3] := Clamp[200H + (fs * ORD(src[3]) + fd * ORD(dst[3])) DIV 255]
		END
	END Blend;
	
	
	(*--- General Transfer ---*)
	
	PROCEDURE AnyBlendAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR spix, dpix: Pixel;
	BEGIN
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, sbit, spix);
			mode.dst.unpack(mode.dst, dadr, dbit, dpix);
			Blend(mode.op, spix, dpix);
			mode.dst.pack(mode.dst, dadr, dbit, dpix);
			sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
			dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
			DEC(len)
		END
	END AnyBlendAny;
	
	
	(* --- invert --- *)
	
	PROCEDURE InvAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			mode.dst.unpack(mode.dst, dadr, dbit, mode.buf);
			mode.buf[r]:=CHR(255-ORD(mode.buf[r]));			
			mode.buf[g]:=CHR(255-ORD(mode.buf[g]));
			mode.buf[b]:=CHR(255-ORD(mode.buf[b]));
			mode.dst.pack(mode.dst, dadr, dbit, mode.buf);
			sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
			dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
			DEC(len)
		END
	END InvAny;
	
	(* --- alpha invert --- *)
	
	PROCEDURE InvOverAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	VAR pix:Pixel;
	BEGIN
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, sbit, pix);
			IF pix[a]>=80X THEN 
				mode.dst.unpack(mode.dst, dadr, dbit, mode.buf);
				mode.buf[r]:=CHR(255-ORD(mode.buf[r]));			
				mode.buf[g]:=CHR(255-ORD(mode.buf[g]));
				mode.buf[b]:=CHR(255-ORD(mode.buf[b]));
				mode.dst.pack(mode.dst, dadr, dbit, mode.buf)
			END;
			sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
			dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
			DEC(len)
		END
	END InvOverAny;
	
	(*--- clear ---*)
	
	PROCEDURE ClearAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR inc: LONGINT;
	BEGIN
		IF mode.dst.bpp MOD 8 = 0 THEN
			inc := mode.dst.bpp DIV 8;
			WHILE len > 0 DO
				mode.dst.pack(mode.dst, dadr, 0, Zero);
				INC(dadr, inc); DEC(len)
			END
		ELSE
			WHILE len > 0 DO
				mode.dst.pack(mode.dst, dadr, dbit, Zero);
				dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
				DEC(len)
			END
		END
	END ClearAny;
	
	PROCEDURE Clear1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR out: CHAR;
	BEGIN
		IF (dbit > 0) OR (len < 8) THEN
			SYSTEM.GET(dadr, out);
			WHILE (dbit < 8) & (len > 0) DO
				out := Clr[ORD(out), dbit];
				INC(dbit); DEC(len)
			END;
			SYSTEM.PUT(dadr, out)
		END;
		WHILE len >= 32 DO
			SYSTEM.PUT(dadr, LONG(LONG(0))); INC(dadr, 4); DEC(len, 32)
		END;
		WHILE len >= 8 DO
			SYSTEM.PUT(dadr, 0X); INC(dadr); DEC(len, 8)
		END;
		IF len > 0 THEN
			SYSTEM.GET(dadr, out); dbit := 0;
			REPEAT
				out := Clr[ORD(out), dbit];
				INC(dbit); DEC(len)
			UNTIL len = 0;
			SYSTEM.PUT(dadr, out)
		END
	END Clear1;
	
	PROCEDURE ClearBytes (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		len := len * mode.dst.bpp DIV 8;
		WHILE len >= 4 DO
			SYSTEM.PUT(dadr, LONG(LONG(0))); INC(dadr, 4); DEC(len)
		END;
		WHILE len > 0 DO
			SYSTEM.PUT(dadr, 0X); INC(dadr); DEC(len)
		END
	END ClearBytes;
	
	
	(*--- srcCopy Transfer ---*)
	
	(* constant values *)
	PROCEDURE Set1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR out: CHAR;
	BEGIN
		IF (dbit > 0) OR (len < 8) THEN
			SYSTEM.GET(dadr, out);
			WHILE (dbit < 8) & (len > 0) DO
				out := Set[ORD(out), dbit];
				INC(dbit); DEC(len)
			END;
			SYSTEM.PUT(dadr, out)
		END;
		WHILE len >= 8 DO
			SYSTEM.PUT(dadr, 0FFX);
			INC(dadr); DEC(len, 8)
		END;
		IF len > 0 THEN
			SYSTEM.GET(dadr, out); dbit := 0;
			REPEAT
				out := Set[ORD(out), dbit];
				INC(dbit); DEC(len)
			UNTIL len = 0;
			SYSTEM.PUT(dadr, out)
		END
	END Set1;
	
	PROCEDURE ConstCopy8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.PUT(dadr, mode.buf[0]); INC(dadr); DEC(len)
		END
	END ConstCopy8;
	
	PROCEDURE ConstCopy16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(SYSTEM.ADR(mode.buf[0]), dadr, 2); INC(dadr, 2); DEC(len)
		END
	END ConstCopy16;
	
	PROCEDURE ConstCopy24 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(SYSTEM.ADR(mode.buf[0]), dadr, 3); INC(dadr, 3); DEC(len)
		END
	END ConstCopy24;
	
	
	(* identical formats *)
	PROCEDURE Copy1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE (sbit = 0) & (dbit = 0) & (len >= 8) DO
			SYSTEM.PUT(dadr, in);
			INC(sadr); INC(dadr); DEC(len, 8);
			SYSTEM.GET(sadr, in)
		END;
		IF (dbit > 0) OR (len < 8) THEN
			SYSTEM.GET(dadr, out)
		END;
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN out := Set[ORD(out), dbit]
			ELSE out := Clr[ORD(out), dbit]
			END;
			INC(sbit); INC(dbit); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END;
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				IF len < 8 THEN
					SYSTEM.GET(dadr, out)
				END
			END
		END;
		IF dbit > 0 THEN
			SYSTEM.PUT(dadr, out)
		END
	END Copy1;
	
	PROCEDURE Copy8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		SYSTEM.MOVE(sadr, dadr, len)
	END Copy8;
	
	PROCEDURE I8CopyI8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR byte: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte); SYSTEM.PUT(dadr, mode.map[ORD(byte)]);
			INC(sadr); INC(dadr); DEC(len)
		END
	END I8CopyI8;
	
	PROCEDURE Copy16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		SYSTEM.MOVE(sadr, dadr, 2*len)
	END Copy16;
	
	PROCEDURE Copy24 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		SYSTEM.MOVE(sadr, dadr, 3*len)
	END Copy24;
	
	PROCEDURE Copy32 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		SYSTEM.MOVE(sadr, dadr, 4*len)
	END Copy32;
	
	
	(* general methods *)
	PROCEDURE AnyCopyAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			pix := mode.buf;
			mode.src.unpack(mode.src, sadr, sbit, mode.buf);
			mode.dst.pack(mode.dst, dadr, dbit, mode.buf);
			sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
			dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
			DEC(len)
		END
	END AnyCopyAny;	
	
	PROCEDURE AnyBytesCopyAnyBytes (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR sinc, dinc: LONGINT; pix: Pixel;
	BEGIN
		sinc := mode.src.bpp DIV 8; dinc := mode.dst.bpp DIV 8;
		WHILE len > 0 DO
			pix := mode.buf;
			mode.src.unpack(mode.src, sadr, sbit, mode.buf);
			mode.dst.pack(mode.dst, dadr, dbit, mode.buf);
			INC(sadr, sinc); INC(dadr, dinc); DEC(len)
		END
	END AnyBytesCopyAnyBytes;
	
	
	(* A1 *)
	PROCEDURE AnyCopyA1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR out: CHAR; pix: Pixel;
	BEGIN
		SYSTEM.GET(dadr, out); pix[a] := 0FFX;
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, sbit, pix);
			sbit := sbit + mode.src.bpp; INC(sadr, sbit MOD 8); sbit := sbit MOD 8;
			IF pix[a] >= 80X THEN out := Set[ORD(out), dbit]
			ELSE out := Clr[ORD(out), dbit]
			END;
			INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out); INC(dadr); SYSTEM.GET(dadr, out); dbit := 0
			END
		END;
		SYSTEM.PUT(dadr, out)
	END AnyCopyA1;
	
	PROCEDURE A8CopyA1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR out, in: CHAR;
	BEGIN
		IF (dbit > 0) OR (len < 8) THEN
			SYSTEM.GET(dadr, out)
		END;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, in);
			IF in >= 80X THEN out := Set[ORD(out), dbit]
			ELSE out := Clr[ORD(out), dbit]
			END;
			INC(sadr); INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				IF len < 8 THEN
					SYSTEM.GET(dadr, out)
				END
			END
		END;
		IF dbit > 0 THEN
			SYSTEM.PUT(dadr, out)
		END
	END A8CopyA1;
	
	PROCEDURE BGRA8888CopyA1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR out, in: CHAR;
	BEGIN
		INC(sadr, a);	(* only look at alpha component *)
		IF (dbit > 0) OR (len < 8) THEN
			SYSTEM.GET(dadr, out)
		END;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, in);
			IF in >= 80X THEN out := Set[ORD(out), dbit]
			ELSE out := Clr[ORD(out), dbit]
			END;
			INC(sadr, 4); INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				IF len < 8 THEN
					SYSTEM.GET(dadr, out)
				END
			END
		END;
		IF dbit > 0 THEN
			SYSTEM.PUT(dadr, out)
		END
	END BGRA8888CopyA1;
	
	PROCEDURE A1CopyAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN mode.dst.pack(mode.dst, dadr, dbit, mode.buf)
			ELSE mode.dst.pack(mode.dst, dadr, dbit, Zero)
			END;
			INC(sbit); dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END A1CopyAny;
	
	PROCEDURE A1CopyA8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN SYSTEM.PUT(dadr, 0FFX)
			ELSE SYSTEM.PUT(dadr, 0X)
			END;
			INC(sbit); INC(dadr); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END A1CopyA8;
	
	PROCEDURE A1CopyBGRA8888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel; in: CHAR;
	BEGIN
		pix := mode.buf;
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN pix[a] := 0FFX
			ELSE pix[a] := 0X
			END;
			SYSTEM.MOVE(SYSTEM.ADR(pix), dadr, 4);
			INC(sbit); INC(dadr, 4); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END A1CopyBGRA8888;
	
	
	(* A8 *)
	PROCEDURE AnyCopyA8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		pix[a] := 0FFX;
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, sbit, pix);
			SYSTEM.PUT(dadr, pix[a]);
			INC(dadr); sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8; DEC(len)
		END
	END AnyCopyA8;
	
	PROCEDURE BGRA8888CopyA8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR byte: CHAR;
	BEGIN
		INC(sadr, 3);
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte);
			SYSTEM.PUT(dadr, byte);
			INC(sadr, 4); INC(dadr); DEC(len)
		END
	END BGRA8888CopyA8;
	
	PROCEDURE A8CopyBGRA8888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		pix := mode.buf;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, pix[a]);
			SYSTEM.MOVE(SYSTEM.ADR(pix), dadr, 4);
			INC(sadr); INC(dadr, 4); DEC(len)
		END
	END A8CopyBGRA8888;
	
	
	(* P8 *)
	PROCEDURE AnyCopyP8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			pix := mode.buf;
			mode.src.unpack(mode.src, sadr, sbit, pix);
			SYSTEM.PUT(dadr, CHR(AosCLUTs.Match(mode.dst.pal.clut, ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))));
			INC(dadr); sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8; DEC(len)
		END
	END AnyCopyP8;
	
	PROCEDURE Any16CopyP8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, 0, pix);
			SYSTEM.PUT(dadr, CHR(AosCLUTs.Match(mode.dst.pal.clut, ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))));
			INC(sadr, 2); INC(dadr); DEC(len)
		END
	END Any16CopyP8;
	
	PROCEDURE BGR888CopyP8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 3);
			SYSTEM.PUT(dadr, CHR(AosCLUTs.Match(mode.dst.pal.clut, ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))));
			INC(sadr, 3); INC(dadr); DEC(len)
		END
	END BGR888CopyP8;
	
	PROCEDURE BGRA8888CopyP8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 4);
			SYSTEM.PUT(dadr, CHR(AosCLUTs.Match(mode.dst.pal.clut, ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))));
			INC(sadr, 4); INC(dadr); DEC(len)
		END
	END BGRA8888CopyP8;
	
	PROCEDURE P8CopyAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR b: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, b);
			mode.dst.pack(mode.dst, dadr, dbit, mode.src.pal.col[ORD(b)]);
			INC(sadr); dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END P8CopyAny;
	
	PROCEDURE P8CopyAny16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR b: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, b);
			mode.dst.pack(mode.dst, dadr, 0, mode.src.pal.col[ORD(b)]);
			INC(sadr); INC(dadr, 2); DEC(len)
		END
	END P8CopyAny16;
	
	PROCEDURE P8CopyBGR888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR b: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, b);
			SYSTEM.MOVE(SYSTEM.ADR(mode.src.pal.col[ORD(b)]), dadr, 3);
			INC(sadr); INC(dadr, 3); DEC(len)
		END
	END P8CopyBGR888;
	
	PROCEDURE P8CopyBGRA8888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR b: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, b);
			SYSTEM.MOVE(SYSTEM.ADR(mode.src.pal.col[ORD(b)]), dadr, 4);
			INC(sadr); INC(dadr, 4); DEC(len)
		END
	END P8CopyBGRA8888;
	
	
	(* D8 *)
	PROCEDURE AnyCopyD8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			pix := mode.buf;
			mode.src.unpack(mode.src, sadr, sbit, pix);
			SYSTEM.PUT(dadr, CHR(d8display.ColorToIndex(ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))));
			INC(dadr); sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8; DEC(len)
		END
	END AnyCopyD8;
	
	PROCEDURE Any16CopyD8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, 0, pix);
			SYSTEM.PUT(dadr, CHR(d8display.ColorToIndex(ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))));
			INC(sadr, 2); INC(dadr); DEC(len)
		END
	END Any16CopyD8;
	
	PROCEDURE BGR888CopyD8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 3);
			SYSTEM.PUT(dadr, CHR(d8display.ColorToIndex(ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))));
			INC(sadr, 3); INC(dadr); DEC(len)
		END
	END BGR888CopyD8;
	
	PROCEDURE BGRA8888CopyD8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 4);
			SYSTEM.PUT(dadr, CHR(d8display.ColorToIndex(ORD(pix[b]) + ASH(ORD(pix[g]), 8) + ASH(ORD(pix[r]), 16))));
			INC(sadr, 4); INC(dadr); DEC(len)
		END
	END BGRA8888CopyD8;
	
	PROCEDURE D8CopyAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel; byte: CHAR; col: LONGINT;
	BEGIN
		pix[a] := 0FFX;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte); col := d8display.IndexToColor(ORD(byte));
			pix[b] := CHR(col MOD 100H); pix[g] := CHR(ASH(col, -8) MOD 100H); pix[r] := CHR(ASH(col, -16) MOD 100H);
			mode.dst.pack(mode.dst, dadr, dbit, pix);
			INC(sadr); dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END D8CopyAny;
	
	PROCEDURE D8CopyAny16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel; byte: CHAR; col: LONGINT;
	BEGIN
		pix[a] := 0FFX;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte); col := d8display.IndexToColor(ORD(byte));
			pix[b] := CHR(col MOD 100H); pix[g] := CHR(ASH(col, -8) MOD 100H); pix[r] := CHR(ASH(col, -16) MOD 100H);
			mode.dst.pack(mode.dst, dadr, 0, pix);
			INC(sadr); INC(dadr, 2); DEC(len)
		END
	END D8CopyAny16;
	
	PROCEDURE D8CopyBGR888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR byte: CHAR; col: LONGINT; pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte); col := d8display.IndexToColor(ORD(byte));
			pix[b] := CHR(col MOD 100H); pix[g] := CHR(ASH(col, -8) MOD 100H); pix[r] := CHR(ASH(col, -16) MOD 100H);
			SYSTEM.MOVE(SYSTEM.ADR(pix[0]), dadr, 3);
			INC(sadr); INC(dadr, 3); DEC(len)
		END
	END D8CopyBGR888;
	
	PROCEDURE D8CopyBGRA8888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel; byte: CHAR; col: LONGINT;
	BEGIN
		pix[a] := 0FFX;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte); col := d8display.IndexToColor(ORD(byte));
			pix[b] := CHR(col MOD 100H); pix[g] := CHR(ASH(col, -8) MOD 100H); pix[r] := CHR(ASH(col, -16) MOD 100H);
			SYSTEM.MOVE(SYSTEM.ADR(pix[0]), dadr, 4);
			INC(sadr); INC(dadr, 4); DEC(len)
		END
	END D8CopyBGRA8888;
	
	
	(* BGR555, BGR565, BGR466 *)
	PROCEDURE AnyCopyAny16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			pix := mode.buf;
			mode.src.unpack(mode.src, sadr, 0, pix);
			mode.dst.pack(mode.dst, dadr, 0, pix);
			INC(dadr, 2); sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8; DEC(len)
		END
	END AnyCopyAny16;
	
	PROCEDURE Any16CopyAny16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, 0, pix);
			mode.dst.pack(mode.dst, dadr, 0, pix);
			INC(sadr, 2); INC(dadr, 2); DEC(len)
		END
	END Any16CopyAny16;
	
	PROCEDURE BGR888CopyAny16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		pix[a] := 0FFX;
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 3);
			mode.dst.pack(mode.dst, dadr, 0, pix);
			INC(sadr, 3); INC(dadr, 2); DEC(len)
		END
	END BGR888CopyAny16;
	
	PROCEDURE BGRA8888CopyAny16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 4);
			mode.dst.pack(mode.dst, dadr, 0, pix);
			INC(dadr, 2); sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8; DEC(len)
		END
	END BGRA8888CopyAny16;
	
	PROCEDURE Any16CopyAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, 0, pix);
			mode.dst.pack(mode.dst, dadr, 0, pix);
			INC(sadr, 2); dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END Any16CopyAny;
	
	PROCEDURE Any16CopyBGR888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, 0, pix);
			SYSTEM.MOVE(SYSTEM.ADR(pix[0]), dadr, 3);
			INC(sadr, 2); INC(dadr, 3); DEC(len)
		END
	END Any16CopyBGR888;
	
	PROCEDURE Any16CopyBGRA8888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, 0, pix);
			SYSTEM.MOVE(SYSTEM.ADR(pix[0]), dadr, 4);
			INC(sadr, 2); INC(dadr, 4); DEC(len)
		END
	END Any16CopyBGRA8888;
	
	
	(* BGR888 *)
	PROCEDURE AnyCopyBGR888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			pix := mode.buf;
			mode.src.unpack(mode.src, sadr, sbit, pix);
			SYSTEM.MOVE(SYSTEM.ADR(pix[0]), dadr, 3);
			INC(dadr, 3); sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8; DEC(len)
		END
	END AnyCopyBGR888;
	
	PROCEDURE BGRA8888CopyBGR888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, dadr, 3);
			INC(sadr, 4); INC(dadr, 3); DEC(len)
		END
	END BGRA8888CopyBGR888;
	
	PROCEDURE BGR888CopyAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		pix[a] := 0FFX;
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 3);
			mode.dst.pack(mode.dst, dadr, dbit, pix);
			INC(sadr, 3); dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END BGR888CopyAny;
	
	PROCEDURE BGR888CopyBGRA8888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, dadr, 3); SYSTEM.PUT(dadr+3, 0FFX);
			INC(sadr, 3); INC(dadr, 4); DEC(len)
		END
	END BGR888CopyBGRA8888;
	
	
	(* BGRA8888 *)
	PROCEDURE AnyCopyBGRA8888 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			pix := mode.buf;
			mode.src.unpack(mode.src, sadr, sbit, pix);
			SYSTEM.MOVE(SYSTEM.ADR(pix[0]), dadr, 4);
			INC(dadr, 4); sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8; DEC(len)
		END
	END AnyCopyBGRA8888;
	
	PROCEDURE BGRA8888CopyAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 4);
			mode.dst.pack(mode.dst, dadr, dbit, pix);
			INC(sadr, 4); dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END BGRA8888CopyAny;
	
	
	(*--- dstCopy Transfer ---*)
	
	PROCEDURE EmptyTransfer (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	END EmptyTransfer;
	
	
	(*--- srcOverDst Transfer ---*)
	
	(* A1 *)
	PROCEDURE AnyOverA1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR out: CHAR; pix: Pixel;
	BEGIN
		SYSTEM.GET(dadr, out);
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, sbit, pix);
			IF pix[a] >= 80X THEN
				out := Set[ORD(out), dbit]
			END;
			sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8; INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				SYSTEM.GET(dadr, out)
			END
		END;
		SYSTEM.PUT(dadr, out)
	END AnyOverA1;
	
	PROCEDURE A1OverA1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in); SYSTEM.GET(dadr, out);
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN
				out := Set[ORD(out), dbit]
			END;
			INC(sbit); INC(dbit); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END;
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				SYSTEM.GET(dadr, out)
			END
		END;
		SYSTEM.PUT(dadr, out)
	END A1OverA1;
	
	PROCEDURE A8OverA1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		SYSTEM.GET(dadr, out);
		WHILE len > 0 DO
			SYSTEM.GET(sadr, in);
			IF in >= 80X THEN
				out := Set[ORD(out), dbit]
			END;
			INC(sadr); INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				SYSTEM.GET(dadr, out)
			END
		END;
		SYSTEM.PUT(dadr, out)
	END A8OverA1;
	
	PROCEDURE BGRA8888OverA1 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		SYSTEM.GET(dadr, out);
		WHILE len > 0 DO
			SYSTEM.GET(sadr + a, in);
			IF in >= 80X THEN
				out := Set[ORD(out), dbit]
			END;
			INC(sadr, 4); INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				SYSTEM.GET(dadr, out)
			END
		END;
		SYSTEM.PUT(dadr, out)
	END BGRA8888OverA1;
	
	PROCEDURE A1OverAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN
				mode.dst.pack(mode.dst, dadr, dbit, mode.buf)
			END;
			INC(sbit); dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END A1OverAny;
	
	PROCEDURE A1OverConst8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN
				SYSTEM.PUT(dadr, mode.buf[0])
			END;
			INC(sbit); INC(dadr); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END A1OverConst8;
	
	PROCEDURE A1OverConst16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN
				SYSTEM.MOVE(SYSTEM.ADR(mode.buf[0]), dadr, 2)
			END;
			INC(sbit); INC(dadr, 2); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END A1OverConst16;
	
	PROCEDURE A1OverConst24 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN
				SYSTEM.MOVE(SYSTEM.ADR(mode.buf[0]), dadr, 3)
			END;
			INC(sbit); INC(dadr, 3); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END A1OverConst24;
	
	PROCEDURE A1OverConst32 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), sbit] THEN
				SYSTEM.MOVE(SYSTEM.ADR(mode.buf[0]), dadr, 4)
			END;
			INC(sbit); INC(dadr, 4); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END A1OverConst32;
	
	
	(* A8 *)
	PROCEDURE AnyOverA8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel; b: CHAR;
	BEGIN
		WHILE len > 0 DO
			mode.src.unpack(mode.src, sadr, sbit, pix);
			IF pix[a] = 0FFX THEN
				SYSTEM.PUT(dadr, 0FFX)
			ELSIF pix[a] # 0X THEN
				SYSTEM.GET(dadr, b);
				SYSTEM.PUT(dadr, CHR(ORD(pix[a]) + ORD(b) * LONG(255-ORD(pix[a])) DIV 255))
			END;
			sbit := sbit + mode.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8; INC(dadr); DEC(len)
		END
	END AnyOverA8;
	
	PROCEDURE A8OverAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR dpix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, mode.buf[a]);
			IF mode.buf[a] = 0FFX THEN
				mode.dst.pack(mode.dst, dadr, dbit, mode.buf)
			ELSIF mode.buf[a] # 0X THEN
				mode.dst.unpack(mode.dst, dadr, dbit, dpix);
				Blend(mode.op, mode.buf, dpix);
				mode.dst.pack(mode.dst, dadr, dbit, dpix)
			END;
			INC(sadr); DEC(len);
			dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8
		END
	END A8OverAny;
	
	PROCEDURE A8OverA8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, in);
			IF in = 0FFX THEN
				SYSTEM.PUT(dadr, 0FFX)
			ELSIF in # 0X THEN
				SYSTEM.GET(dadr, out);
				SYSTEM.PUT(dadr, CHR(ORD(in) + ORD(out) * LONG(255-ORD(in)) DIV 255))
			END;
			INC(sadr); INC(dadr); DEC(len)
		END
	END A8OverA8;
	
	
	(* BGRA8888 *)
	PROCEDURE BGRA8888OverAny (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR spix, dpix: Pixel;
	BEGIN
		WHILE len > 0 DO
			spix := SYSTEM.VAL(Pixel, SYSTEM.GET32(sadr));
			IF spix[a] = 0FFX THEN
				mode.dst.pack(mode.dst, dadr, dbit, spix)
			ELSIF spix[a] # 0X THEN
				mode.dst.unpack(mode.dst, dadr, dbit, dpix);
				Blend(mode.op, spix, dpix);
				mode.dst.pack(mode.dst, dadr, dbit, dpix)
			END;
			INC(sadr, 4); DEC(len);
			dbit := dbit + mode.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8
		END
	END BGRA8888OverAny;
	
	PROCEDURE BGRA8888OverA8 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr + a, in);
			IF in = 0FFX THEN
				SYSTEM.PUT(dadr, 0FFX)
			ELSIF in # 0X THEN
				SYSTEM.GET(dadr, out);
				SYSTEM.PUT(dadr, CHR(ORD(in) + ORD(out) * (255 - ORD(in)) DIV 255))
			END;
			INC(sadr, 4); INC(dadr); DEC(len)
		END
	END BGRA8888OverA8;
	
	PROCEDURE BGRA8888OverAny16 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR src, dst: Pixel; fd, t: LONGINT;
	BEGIN
		WHILE len > 0 DO
			src := SYSTEM.VAL(Pixel, SYSTEM.GET32(sadr));
			IF src[a] = 0FFX THEN
				mode.dst.pack(mode.dst, dadr, dbit, src)
			ELSIF src[a] # 0X THEN
				mode.dst.unpack(mode.dst, dadr, 0, dst);
				fd := 255-ORD(src[a]);
				t := (256 * ORD(src[0]) + fd * ORD(dst[0])) DIV 256;
				IF t < 255 THEN dst[0] := CHR(t) ELSE dst[0] := CHR(255) END;
				
				t := (256 * ORD(src[1]) + fd * ORD(dst[1])) DIV 256;
				IF t < 255 THEN dst[1] := CHR(t) ELSE dst[1] := CHR(255) END;
				t := (256 * ORD(src[2]) + fd * ORD(dst[2])) DIV 256;
				IF t < 255 THEN dst[2] := CHR(t) ELSE dst[2] := CHR(255) END;
				t := (256 * ORD(src[3]) + fd * ORD(dst[3])) DIV 256;
				IF t < 255 THEN dst[3] := CHR(t) ELSE dst[3] := CHR(255) END;
				mode.dst.pack(mode.dst, dadr, 0, dst);
			END;	
			INC(dadr, 2); INC(sadr, 4); DEC(len)
		END
	END BGRA8888OverAny16;
	
	PROCEDURE BGRA8888Over565 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR src, dst: Pixel; fd, t: LONGINT;
	BEGIN
		WHILE len > 0 DO
			src := SYSTEM.VAL(Pixel, SYSTEM.GET32(sadr));
			IF src[a] = 0FFX THEN
				SYSTEM.PUT16(dadr, ASH(ORD(src[b]), -3) + ASH(ASH(ORD(src[g]), -2), 5) + ASH(ASH(ORD(src[r]), -3), 11));
			ELSIF src[a] # 0X THEN
				t := SYSTEM.GET16(dadr);
				dst[b] := CHR((t MOD 32) * 8); dst[g] := CHR((t DIV 32 MOD 64) * 4); dst[r] := CHR((t DIV 2048 MOD 32) * 8);
				
				fd := 256-ORD(src[a]);
				t := (256 * ORD(src[0]) + fd * ORD(dst[0])) DIV 256;
				IF t < 255 THEN dst[0] := CHR(t) ELSE dst[0] := CHR(255) END;
				
				t := (256 * ORD(src[1]) + fd * ORD(dst[1])) DIV 256;
				IF t < 255 THEN dst[1] := CHR(t) ELSE dst[1] := CHR(255) END;
				t := (256 * ORD(src[2]) + fd * ORD(dst[2])) DIV 256;
				IF t < 255 THEN dst[2] := CHR(t) ELSE dst[2] := CHR(255) END;
				t := (256 * ORD(src[3]) + fd * ORD(dst[3])) DIV 256;
				IF t < 255 THEN dst[3] := CHR(t) ELSE dst[3] := CHR(255) END;
				SYSTEM.PUT16(dadr, ASH(ORD(dst[b]), -3) + ASH(ASH(ORD(dst[g]), -2), 5) + ASH(ASH(ORD(dst[r]), -3), 11));
			END;	
			INC(dadr, 2); INC(sadr, 4); DEC(len)
		END
	END BGRA8888Over565;
	
	PROCEDURE MMXBGRA8888Over565 (VAR mode: Mode0; sadr, sbit, dadr, dbit, len: LONGINT);
	CODE {SYSTEM.i386, SYSTEM.MMX}
		PUSHFD
		CLI
		MOV ESI, sadr[EBP]
		MOV EDI, dadr[EBP]  
		PXOR MM0, MM0
		
		MOV	 EAX, 0FFFFFFFFH
		MOVD	MM7, EAX 
		PUNPCKLBW	MM7, MM0  (* 00FF00FF00FF00FF *)
		
		MOV	ECX, len[EBP]
	loop:	
		CMP	ECX, 0
		JE end
		
			MOV	EAX, [ESI]
			XOR	EBX, EBX
			MOV	BX, [EDI]
	
			(* 255 - alpha *)
			MOV	EDX, EAX
			SHR	EDX, 24
			CMP	EDX, 0 
			JE	empty
			CMP	EDX, 255
			JE	full
			
		alpha:	
			NEG	EDX
			ADD	EDX, 255
			MOVD MM6, EDX
			PUNPCKLWD MM6, MM6
			PUNPCKLDQ MM6, MM6
			
			MOVD MM1, EAX
			
			(* unpack dst *)
			MOV	EDX, EBX (* b *)
			SHL	EDX, 3
			AND	EDX, 0F8H
			MOV	EAX, EDX
			
			MOV	EDX, EBX (* g *)
			SHL	EDX, 5
			AND	EDX, 0FC00H
			OR	EAX, EDX
			
			MOV	EDX, EBX (* r *)
			SHL	EDX, 8
			AND	EDX, 0F80000H
			OR	EAX, EDX


			MOVD	MM2, EAX 
		
			PUNPCKLBW	MM1, MM0  (* 0000ARGB --> 0A0R0G0B *)
			PMULLW MM1, MM7
			
			PUNPCKLBW	MM2, MM0  (* 0000ARGB --> 0A0R0G0B *)
			PMULLW MM2, MM6
			
			
			PADDUSW MM1, MM2 
			
		(*	PSRLW	MM1, 8 (* normalize *) *)
			DB 0FH, 71H, 0D1H, 08H 
			PACKUSWB MM1, MM0
			
			(* HUGA BIMBO Muell *)
			MOVD	EAX, MM1
			
		full:	  
(*			XOR EDX, EDX
			SHR EAX, 3
			MOV EDX, EAX
			AND EDX, 1FH
			SHR EAX, 2
			AND EAX, 0FFFFFFE0H
			OR EDX, EAX
			AND EDX, 7FFH
			
			SHR EAX, 3
			AND EAX, 
			
			
			SHR AL, 3
			SHR AH, 2
			MOV EDX, EAX
			SHR EAX, 3
			AND EAX, 01F0000H
			OR EDX, EAX
			AND EDX, 01F3F1FH *)
			
			
		
			MOV	EBX, EAX 
			AND	EBX, 0FFH
			SHR	EBX, 3
			MOV	EDX, EBX
			
			MOV	EBX, EAX
			SHR	EBX, 8
			AND	EBX, 0FFH
			SHR	EBX, 2
			SHL	EBX, 5
			OR	EDX, EBX
			
			MOV	EBX, EAX
			SHR	EBX, 16
			AND	EBX, 0FFH
			SHR	EBX, 3
			SHL	EBX, 11
			OR	EDX, EBX
			  
			MOV [EDI], DX
		empty:	
			ADD ESI, 4;
			ADD EDI, 2;
			DEC	ECX
		JMP loop
	end:	
		EMMS (* declare FPU registers free *)
		POPFD
	END MMXBGRA8888Over565;
	
(*		WHILE len > 0 DO
			src := SYSTEM.VAL(Pixel, SYSTEM.GET32(sadr));
			IF src[a] = 0FFX THEN
				SYSTEM.PUT16(dadr, ASH(ORD(src[b]), -3) + ASH(ASH(ORD(src[g]), -2), 5) + ASH(ASH(ORD(src[r]), -3), 11));
			ELSIF src[a] # 0X THEN
				t := SYSTEM.GET16(dadr);
				dst[b] := CHR((t MOD 32) * 8); dst[g] := CHR((t DIV 32 MOD 64) * 4); dst[r] := CHR((t DIV 2048 MOD 32) * 8);
				
				fd := 256-ORD(src[a]);
				t := (256 * ORD(src[0]) + fd * ORD(dst[0])) DIV 256;
				IF t < 255 THEN dst[0] := CHR(t) ELSE dst[0] := CHR(255) END;
				
				t := (256 * ORD(src[1]) + fd * ORD(dst[1])) DIV 256;
				IF t < 255 THEN dst[1] := CHR(t) ELSE dst[1] := CHR(255) END;
				t := (256 * ORD(src[2]) + fd * ORD(dst[2])) DIV 256;
				IF t < 255 THEN dst[2] := CHR(t) ELSE dst[2] := CHR(255) END;
				t := (256 * ORD(src[3]) + fd * ORD(dst[3])) DIV 256;
				IF t < 255 THEN dst[3] := CHR(t) ELSE dst[3] := CHR(255) END;
				SYSTEM.PUT16(dadr, ASH(ORD(dst[b]), -3) + ASH(ASH(ORD(dst[g]), -2), 5) + ASH(ASH(ORD(dst[r]), -3), 11));
			END;	
			INC(dadr, 2); INC(sadr, 4); DEC(len)
		END
	END MMXBGRA8888Over565; *)
	
	(** find (optimized) pixel transfer procedure for transfer mode and given source and destination formats **)
	PROCEDURE Bind* (VAR mode: Mode; VAR src, dst: Format);
		VAR op: SHORTINT; i: LONGINT;
	BEGIN
		IF Same(src, mode.src) & Same(dst, mode.dst) THEN
			ASSERT(mode.transfer # NIL, 120);
			RETURN	(* assume transfer procedure is still valid *)
		END;
		mode.src := src; mode.dst := dst; mode.buf := mode.col;
		
		(* try to convert complex composite operations into simpler ones *)
		IF alpha IN src.components * dst.components THEN	(* source and destination contain alpha information *)
			op := mode.op
		ELSIF alpha IN src.components THEN	(* only source contains alpha *)
			CASE mode.op OF
			| dstOverSrc: op := dstCopy
			| srcInDst: op := srcCopy
			| srcWithoutDst: op := clear
			| srcAtopDst: op := srcOverDst
			| dstAtopSrc: op := dstInSrc
			| srcXorDst: op := dstWithoutSrc
			ELSE op := mode.op
			END
		ELSIF alpha IN dst.components THEN	(* only destination contains alpha *)
			CASE mode.op OF
			| srcOverDst: op := srcCopy
			| dstInSrc: op := dstCopy
			| dstWithoutSrc: op := clear
			| srcAtopDst: op := srcInDst
			| dstAtopSrc: op := dstOverSrc
			| srcXorDst: op := srcWithoutDst
			ELSE op := mode.op
			END
		ELSE	(* no alpha in either source or destination *)
			CASE mode.op OF
			| srcOverDst, srcInDst, srcAtopDst: op := srcCopy
			| dstOverSrc, dstInSrc, dstAtopSrc: op := dstCopy
			| srcWithoutDst, dstWithoutSrc, srcXorDst: op := clear
			ELSE op := mode.op
			END
		END;
		
		IF op = InvDst THEN
			mode.transfer:=InvAny;
		ELSIF op = InvOverDst THEN
			mode.transfer:=InvOverAny;
		ELSIF op = clear THEN
			CASE dst.code OF
			| a1: mode.transfer := Clear1
			| a8, bgr555, bgr565, bgr466, bgr888, bgra8888: mode.transfer := ClearBytes
			| p8:
				mode.buf[0] := CHR(AosCLUTs.Match(dst.pal.clut, 0));
				IF mode.buf[0] = 0X THEN mode.transfer := ClearBytes
				ELSE mode.transfer := ConstCopy8
				END
			| d8:
				mode.buf[0] := CHR(d8display.ColorToIndex(0));
				IF mode.buf[0] = 0X THEN mode.transfer := ClearBytes
				ELSE mode.transfer := ConstCopy8
				END
			ELSE mode.transfer := ClearAny
			END
			
		ELSIF op = srcCopy THEN
			CASE dst.code OF
			| a1:
				CASE src.code OF
				| a1: mode.transfer := Copy1
				| a8: mode.transfer := A8CopyA1
				| bgra8888: mode.transfer := BGRA8888CopyA1
				ELSE
					IF alpha IN src.components THEN mode.transfer := AnyCopyA1
					ELSE mode.transfer := Set1
					END
				END
			| a8:
				CASE src.code OF
				| a1: mode.transfer := A1CopyA8
				| a8: mode.transfer := Copy8
				| bgra8888: mode.transfer := BGRA8888CopyA8
				ELSE
					IF alpha IN src.components THEN mode.transfer := AnyCopyA8
					ELSE mode.buf[0] := 0FFX; mode.transfer := ConstCopy8
					END
				END
			| p8:
				CASE src.code OF
				| a1, a8:
					mode.buf[0] := CHR(AosCLUTs.Match(dst.pal.clut, ORD(mode.col[b]) + ASH(ORD(mode.col[g]), 8) +
						ASH(ORD(mode.col[r]), 16)));
					mode.transfer := ConstCopy8
				| p8:
					IF src.pal = dst.pal THEN mode.transfer := Copy8
					ELSE
						FOR i := 0 TO src.pal.used-1 DO
							mode.map[i] := CHR(AosCLUTs.Match(dst.pal.clut, ORD(src.pal.col[i, b]) + ASH(ORD(src.pal.col[i, g]), 8) +
								ASH(ORD(src.pal.col[i, r]), 16)))
						END;
						mode.transfer := I8CopyI8
					END
				| d8:
					FOR i := 0 TO 255 DO
						mode.map[i] := CHR(AosCLUTs.Match(dst.pal.clut, d8display.IndexToColor(i) MOD 1000000H))
					END;
					mode.transfer := I8CopyI8
				| bgr555, bgr565, bgr466: mode.transfer := Any16CopyP8
				| bgr888: mode.transfer := BGR888CopyP8
				| bgra8888: mode.transfer := BGRA8888CopyP8
				ELSE mode.transfer := AnyCopyP8
				END
			| d8:
				CASE src.code OF
				| a1, a8:
					mode.buf[0] := CHR(d8display.ColorToIndex(
						ORD(mode.col[b]) + ASH(ORD(mode.col[g]), 8) + ASH(ORD(mode.col[r]), 16)));
					mode.transfer := ConstCopy8
				| p8:
					FOR i := 0 TO src.pal.used-1 DO
						mode.map[i] := CHR(d8display.ColorToIndex(
							ORD(src.pal.col[i, b]) + ASH(ORD(src.pal.col[i, g]), 8) + ASH(ORD(src.pal.col[i, r]), 16)))
					END;
					mode.transfer := I8CopyI8
				| d8: mode.transfer := Copy8
				| bgr555, bgr565, bgr466: mode.transfer := Any16CopyD8
				| bgr888: mode.transfer := BGR888CopyD8
				| bgra8888: mode.transfer := BGRA8888CopyD8
				ELSE mode.transfer := AnyCopyD8
				END
			| bgr555, bgr565, bgr466:
				CASE src.code OF
				| a1, a8: dst.pack(dst, SYSTEM.ADR(mode.buf[0]), 0, mode.col); mode.transfer := ConstCopy16
				| p8: mode.transfer := P8CopyAny16
				| d8: mode.transfer := D8CopyAny16
				| bgr555, bgr565, bgr466:
					IF src.code = dst.code THEN mode.transfer := Copy16
					ELSE mode.transfer := Any16CopyAny16
					END
				| bgr888: mode.transfer := BGR888CopyAny16
				| bgra8888: mode.transfer := BGRA8888CopyAny16
				ELSE mode.transfer := AnyCopyAny16
				END
			| bgr888:
				CASE src.code OF
				| a1, a8: mode.buf := mode.col; mode.transfer := ConstCopy24
				| p8: mode.transfer := P8CopyBGR888
				| d8: mode.transfer := D8CopyBGR888
				| bgr555, bgr565, bgr466: mode.transfer := Any16CopyBGR888
				| bgr888: mode.transfer := Copy24
				| bgra8888: mode.transfer := BGRA8888CopyBGR888
				ELSE mode.transfer := AnyCopyBGR888
				END
			| bgra8888:
				CASE src.code OF
				| a1: mode.transfer := A1CopyBGRA8888
				| a8: mode.transfer := A8CopyBGRA8888
				| p8: mode.transfer := P8CopyBGRA8888
				| d8: mode.transfer := D8CopyBGRA8888
				| bgr555, bgr565, bgr466: mode.transfer := Any16CopyBGRA8888
				| bgr888: mode.transfer := BGR888CopyBGRA8888
				| bgra8888: mode.transfer := Copy32
				ELSE mode.transfer := AnyCopyBGRA8888
				END
			ELSE
				CASE src.code OF
				| a1: mode.transfer := A1CopyAny
				| p8: mode.transfer := P8CopyAny
				| d8: mode.transfer := D8CopyAny
				| bgr555, bgr565, bgr466: mode.transfer := Any16CopyAny
				| bgr888: mode.transfer := BGR888CopyAny
				| bgra8888: mode.transfer := BGRA8888CopyAny
				ELSE
					IF (src.bpp MOD 8 = 0) & (dst.bpp MOD 8 = 0) THEN mode.transfer := AnyBytesCopyAnyBytes
					ELSE mode.transfer := AnyCopyAny
					END
				END
			END
		
		ELSIF op = dstOverSrc THEN
			mode.transfer := EmptyTransfer
		
		ELSIF op = srcOverDst THEN
			CASE dst.code OF
			| a1:
				CASE src.code OF
				| a1: mode.transfer := A1OverA1
				| a8: mode.transfer := A8OverA1
				| bgra8888: mode.transfer := BGRA8888OverA1
				ELSE mode.transfer := AnyOverA1
				END
			| a8:
				CASE src.code OF
				| a1: mode.buf[0] := 0FFX; mode.transfer := A1OverConst8
				| a8: mode.transfer := A8OverA8
				| bgra8888: mode.transfer := BGRA8888OverA8
				ELSE mode.transfer := AnyOverA8
				END
			| bgra8888:
				CASE src.code OF
				| a1: mode.buf := mode.col; mode.transfer := A1OverConst32
				| a8: mode.buf := mode.col; mode.transfer := A8OverAny
				ELSE mode.transfer := BGRA8888OverAny
				END
			ELSE
				CASE src.code OF
				| a1:
					CASE dst.code OF
					| p8:
						mode.buf[0] := CHR(AosCLUTs.Match(dst.pal.clut, ORD(mode.col[b]) + ASH(ORD(mode.col[g]), 8) +
							ASH(ORD(mode.col[r]), 16)));
						mode.transfer := A1OverConst8
					| d8:
						mode.buf[0] := CHR(d8display.ColorToIndex(ORD(mode.col[b]) + ASH(ORD(mode.col[g]), 8) +
							ASH(ORD(mode.col[r]), 16)));
						mode.transfer := A1OverConst8
					| bgr555, bgr565, bgr466: dst.pack(dst, SYSTEM.ADR(mode.buf[0]), 0, mode.col); mode.transfer := A1OverConst16
					| bgr888: mode.buf := mode.col; mode.transfer := A1OverConst24
					ELSE mode.transfer := A1OverAny
					END
				| a8: mode.buf := mode.col; mode.transfer := A8OverAny
				| bgra8888:
					CASE dst.code OF
					| bgr555, bgr466: mode.transfer := BGRA8888OverAny16
					| bgr565 : IF MMXenabled THEN 
							mode.transfer := MMXBGRA8888Over565 
						ELSE mode.transfer := BGRA8888Over565 
						END
					ELSE mode.transfer := BGRA8888OverAny
					END
				ELSE 
			
				mode.transfer := AnyBlendAny
				END
			END		
		ELSE			
			mode.transfer := AnyBlendAny
		END;
		
		ASSERT(mode.transfer # NIL, 120)
	END Bind;
	
	
	(**--- Image Operations ---**)
	
	(** get pixel from image **)
	PROCEDURE Get* (img: Image; x, y: LONGINT; VAR pix: Pixel; VAR mode: Mode);
		VAR bit, adr: LONGINT;
	BEGIN
		ASSERT((0 <= x) & (x < img.width) & (0 <= y) & (y < img.height), 100);
		bit := x * img.fmt.bpp; adr := img.adr + y * img.bpr + bit DIV 8; bit := bit MOD 8;
		Bind(mode, img.fmt, PixelFormat);
		mode.transfer(mode, adr, bit, SYSTEM.ADR(pix), 0, 1)
	END Get;
	
	(** put pixel into image **)
	PROCEDURE Put* (img: Image; x, y: LONGINT; pix: Pixel; VAR mode: Mode);
		VAR bit, adr: LONGINT;
	BEGIN
		ASSERT((0 <= x) & (x < img.width) & (0 <= y) & (y < img.height), 100);
		bit := x * img.fmt.bpp; adr := img.adr + y * img.bpr + bit DIV 8; bit := bit MOD 8;
		Bind(mode, PixelFormat, img.fmt);
		mode.transfer(mode, SYSTEM.ADR(pix[0]), 0, adr, bit, 1)
	END Put;
	
	(** fill rectangular area **)
	PROCEDURE Fill* (img: Image; llx, lly, urx, ury: LONGINT; pix: Pixel; VAR mode: Mode);
		VAR bit, adr, bb, aa, x: LONGINT; m: Mode;
	BEGIN
		ASSERT((0 <= llx) & (llx < urx) & (urx <= img.width) & (0 <= lly) & (lly < ury) & (ury <= img.height), 100);
		bit := llx * img.fmt.bpp; adr := img.adr + lly * img.bpr + bit DIV 8; bit := bit MOD 8;
		Bind(mode, PixelFormat, img.fmt);
		IF (mode.op IN {clear, srcCopy}) OR (pix[a] = 0FFX) & (mode.op IN {srcOverDst, dstWithoutSrc}) THEN	(* dst is replaced *)
			(* copy one pixel to lower left corner of rect *)
			mode.transfer(mode, SYSTEM.ADR(pix[0]), 0, adr, bit, 1);
			
			(* copy pixel to rest of bottom row *)
			InitMode(m, srcCopy); Bind(m, img.fmt, img.fmt);
			IF (bit = 0) & (img.fmt.bpp MOD 8 = 0) THEN	(* use simple address calculation *)
				bb := img.fmt.bpp DIV 8; aa := adr + bb; x := llx+1;
				WHILE x < urx DO
					m.transfer(m, adr, 0, aa, 0, 1);
					INC(aa, bb); INC(x)
				END
			ELSE
				bb := bit + img.fmt.bpp; aa := adr + bb DIV 8; bb := bb MOD 8; x := llx+1;
				WHILE x < urx DO
					m.transfer(m, adr, bit, aa, bb, 1);
					bb := bb + img.fmt.bpp; aa := aa + bb DIV 8; bb := bb MOD 8; INC(x)
				END
			END;
			
			(* now copy bottom row to others *)
			INC(lly); aa := adr + img.bpr;
			WHILE lly < ury DO
				m.transfer(m, adr, bit, aa, bit, urx - llx);
				INC(lly); INC(aa, img.bpr)
			END
		
		ELSE	(* fill pixel by pixel *)
			WHILE lly < ury DO
				x := llx; aa := adr; bb := bit;
				WHILE x < urx DO
					mode.transfer(mode, SYSTEM.ADR(pix[0]), 0, aa, bb, 1);
					bb := bb + img.fmt.bpp; aa := aa + bb DIV 8; bb := bb MOD 8; INC(x)
				END;
				INC(lly); INC(adr, img.bpr)
			END
		END
	END Fill;
	
	(** clear image **)
	PROCEDURE Clear* (img: Image);
		VAR mode: Mode;
	BEGIN
		InitMode(mode, clear);
		Bind(mode, PixelFormat, img.fmt);
		Fill(img, 0, 0, img.width, img.height, Zero, mode)
	END Clear;
	
	(** get several pixels and store them in array in requested format **)
	PROCEDURE GetPixels* (img: Image; x, y, w: LONGINT; VAR fmt: Format; VAR buf: ARRAY OF CHAR; ofs : LONGINT; VAR mode: Mode);
		VAR sbit, sadr: LONGINT;
	BEGIN
		ASSERT((0 <= x) & (x + w <= img.width) & (0 <= y) & (y <= img.height), 100);
		ASSERT(ofs + w * fmt.bpp DIV 8 <= LEN(buf), 101);
		Bind(mode, img.fmt, fmt);
		sbit := x * img.fmt.bpp; sadr := img.adr + y * img.bpr + sbit DIV 8; sbit := sbit MOD 8;
		mode.transfer(mode, sadr, sbit, SYSTEM.ADR(buf[ofs]), 0, w)
	END GetPixels;
	
	(** put several pixels from array in given format into image **)
	PROCEDURE PutPixels* (img: Image; x, y, w: LONGINT; VAR fmt: Format; VAR buf: ARRAY OF CHAR; ofs : LONGINT; VAR mode: Mode);
		VAR dbit, dadr: LONGINT;
	BEGIN
		ASSERT((0 <= x) & (x + w <= img.width) & (0 <= y) & (y <= img.height), 100);
		ASSERT(ofs + w * fmt.bpp DIV 8 <= LEN(buf), 101);
		dbit := x * img.fmt.bpp; dadr := img.adr + y * img.bpr + dbit DIV 8; dbit := dbit MOD 8;
		Bind(mode, fmt, img.fmt);
		mode.transfer(mode, SYSTEM.ADR(buf[ofs]), 0, dadr, dbit, w)
	END PutPixels;
	
	(** copy rectangular area to the same or another image in specified mode **)
	PROCEDURE Copy* (src, dst: Image; llx, lly, urx, ury, dx, dy: LONGINT; VAR mode: Mode);
		VAR w, h, sbit, sadr, dbit, dadr, slen, sa, sb, da, db, len, l: LONGINT;
	BEGIN
		ASSERT((0 <= llx) & (llx <= urx) & (urx <= src.width) & (0 <= lly) & (lly <= ury) & (ury <= src.height), 100);
		ASSERT((0 <= dx) & (dx + urx - llx <= dst.width) & (0 <= dy) & (dy + ury - lly <= dst.height), 101);
		Bind(mode, src.fmt, dst.fmt);
		w := urx - llx; h := ury - lly;
		IF (src # dst) OR (lly > dy) OR (lly = dy) & ((llx > dx) OR (urx <= dx)) THEN	(* copy lines bottom-up *)
			sbit := llx * src.fmt.bpp; sadr := src.adr + lly * src.bpr + sbit DIV 8; sbit := sbit MOD 8;
			dbit := dx * dst.fmt.bpp; dadr := dst.adr + dy * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			WHILE h > 0 DO
				mode.transfer(mode, sadr, sbit, dadr, dbit, w);
				INC(sadr, src.bpr); INC(dadr, dst.bpr); DEC(h)
			END
		ELSIF lly < dy THEN	(* copy lines top-down *)
			sbit := llx * src.fmt.bpp; sadr := src.adr + ury * src.bpr + sbit DIV 8; sbit := sbit MOD 8;
			dbit := dx * dst.fmt.bpp; dadr := dst.adr + (dy + h) * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			WHILE h > 0 DO
				DEC(sadr, src.bpr); DEC(dadr, dst.bpr); DEC(h);
				mode.transfer(mode, sadr, sbit, dadr, dbit, w)
			END
		ELSIF llx # dx THEN	(* uh oh! overlapping spans *)
			slen := dx + w - urx;	(* maximal span length guaranteeing non-overlapping spans *)
			sbit := urx * src.fmt.bpp; sadr := src.adr + lly * src.bpr + sbit DIV 8; sbit := sbit MOD 8;
			dbit := (dx + w) * dst.fmt.bpp; dadr := dst.adr + dy * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			WHILE h > 0 DO
				sa := sadr; sb := sbit; da := dadr; db := dbit; len := w;
				WHILE len > 0 DO
					l := slen;
					IF l > len THEN l := len END;
					DEC(sb, l * src.fmt.bpp); INC(sa, sb DIV 8); sb := sb MOD 8;
					DEC(db, l * dst.fmt.bpp); INC(da, db DIV 8); db := db MOD 8;
					mode.transfer(mode, sa, sb, da, db, l);
					DEC(len, l)
				END;
				INC(sadr, src.bpr); INC(dadr, dst.bpr); DEC(h)
			END
		END
	END Copy;
	
	(** replicate pattern within rectangular area of image using given mode **)
	PROCEDURE FillPattern* (pat, dst: Image; llx, lly, urx, ury, px, py: LONGINT; VAR mode: Mode);
		VAR pw, ph, olx, oby, ilx, olw, irw, dy, sy, dx, sx, ty: LONGINT;
	BEGIN
		ASSERT((0 <= llx) & (llx <= urx) & (urx <= dst.width) & (0 <= lly) & (lly <= ury) & (ury <= dst.height), 100);
		pw := pat.width; ph := pat.height;
		olx := px + (llx - px) DIV pw * pw;
		oby := py + (lly - py) DIV ph * ph;
		ilx := olx + pw; olw := llx - olx;
		irw := (urx - px) MOD pw;
		IF urx - irw < ilx THEN irw := olw + urx - llx END;
		dy := lly; sy := lly - oby;
		IF (oby < lly) & (oby + ph <= ury) THEN
			dx := llx; sx := olw;
			IF (olx < llx) & (ilx <= urx) THEN
				Copy(pat, dst, sx, sy, pw, ph, llx, lly, mode);
				dx := ilx; sx := 0
			END;
			WHILE dx + pw <= urx DO
				Copy(pat, dst, 0, sy, pw, ph, dx, lly, mode);
				INC(dx, pw)
			END;
			IF dx < urx THEN
				Copy(pat, dst, sx, sy, irw, ph, dx, lly, mode)
			END;
			dy := oby + ph; sy := 0
		END;
		WHILE dy + ph <= ury DO
			dx := llx; sx := olw;
			IF (olx < llx) & (ilx <= urx) THEN
				Copy(pat, dst, sx, 0, pw, ph, llx, dy, mode);
				dx := ilx; sx := 0
			END;
			WHILE dx + pw <= urx DO
				Copy(pat, dst, 0, 0, pw, ph, dx, dy, mode);
				INC(dx, pw)
			END;
			IF dx < urx THEN
				Copy(pat, dst, sx, 0, irw, ph, dx, dy, mode)
			END;
			INC(dy, ph)
		END;
		IF dy < ury THEN
			ty := sy + ury - dy;
			dx := llx; sx := olw;
			IF (olx < llx) & (ilx <= urx) THEN
				Copy(pat, dst, sx, sy, pw, ty, llx, dy, mode);
				dx := ilx; sx := 0
			END;
			WHILE dx + pw <= urx DO
				Copy(pat, dst, 0, sy, pw, ty, dx, dy, mode);
				INC(dx, pw)
			END;
			IF dx < urx THEN
				Copy(pat, dst, sx, sy, irw, ty, dx, dy, mode)
			END
		END
	END FillPattern;
	
	(** darken image while maintaining coverage **)
	PROCEDURE Darken* (img: Image; factor: REAL);
		VAR s, i, j, k, y, x, adr, bit: LONGINT; clamp: ARRAY 256 OF CHAR; pix: Pixel;
	BEGIN
		s := ABS(ENTIER(255*factor + 0.5));
		IF (s # 255) & (img.fmt.components # {alpha}) THEN
			i := 256; j := 256*s;
			REPEAT
				DEC(i); DEC(j, s); k := j DIV 255;
				IF k <= 255 THEN clamp[i] := CHR(k) ELSE clamp[i] := 0FFX END
			UNTIL i = 0;
			y := 0;
			WHILE y < img.height DO
				x := 0; adr := img.adr + y * img.bpr; bit := 0;
				WHILE x < img.width DO
					img.fmt.unpack(img.fmt, adr, bit, pix);
					pix[r] := clamp[ORD(pix[r])]; pix[g] := clamp[ORD(pix[g])]; pix[b] := clamp[ORD(pix[b])];
					img.fmt.pack(img.fmt, adr, bit, pix);
					bit := bit + img.fmt.bpp; INC(adr, bit); bit := bit MOD 8;
					INC(x)
				END;
				INC(y)
			END
		END
	END Darken;
	
	(** fade image **)
	PROCEDURE Fade* (img: Image; factor: REAL);
		VAR s, i, j, k, y, x, adr, bit: LONGINT; clamp: ARRAY 256 OF CHAR; pix: Pixel;
	BEGIN
		s := ABS(ENTIER(255*factor + 0.5));
		IF s = 0 THEN
			Clear(img)
		ELSIF s # 255 THEN
			i := 256; j := 256*s;
			REPEAT
				DEC(i); DEC(j, s); k := j DIV 255;
				IF k <= 255 THEN clamp[i] := CHR(k) ELSE clamp[i] := 0FFX END
			UNTIL i = 0;
			y := 0;
			WHILE y < img.height DO
				x := 0; adr := img.adr + y * img.bpr; bit := 0;
				WHILE x < img.width DO
					img.fmt.unpack(img.fmt, adr, bit, pix);
					pix[r] := clamp[ORD(pix[r])]; pix[g] := clamp[ORD(pix[g])];
					pix[b] := clamp[ORD(pix[b])]; pix[a] := clamp[ORD(pix[a])];
					img.fmt.pack(img.fmt, adr, bit, pix);
					bit := bit + img.fmt.bpp; INC(adr, bit); bit := bit MOD 8;
					INC(x)
				END;
				INC(y)
			END
		END
	END Fade;
	
	(** make image brighter and more transparent; Opaque(I, f) = Darken(Fade(I, f), 1/f) **)
	PROCEDURE Opaque* (img: Image; factor: REAL);
		VAR s, i, j, k, y, x, adr, bit: LONGINT; clamp: ARRAY 256 OF CHAR; pix: Pixel;
	BEGIN
		s := ABS(ENTIER(255*factor + 0.5));
		IF s = 0 THEN
			Clear(img)
		ELSIF s # 255 THEN
			i := 256; j := 256*s;
			REPEAT
				DEC(i); DEC(j, s); k := j DIV 255;
				IF k <= 255 THEN clamp[i] := CHR(k) ELSE clamp[i] := 0FFX END
			UNTIL i = 0;
			y := 0;
			WHILE y < img.height DO
				x := 0; adr := img.adr + y * img.bpr; bit := 0;
				WHILE x < img.width DO
					img.fmt.unpack(img.fmt, adr, bit, pix);
					pix[a] := clamp[ORD(pix[a])];
					img.fmt.pack(img.fmt, adr, bit, pix);
					bit := bit + img.fmt.bpp; INC(adr, bit); bit := bit MOD 8;
					INC(x)
				END;
				INC(y)
			END
		END
	END Opaque;
	
	(** add components of two (faded) images **)
	PROCEDURE Add* (i, j, res: Image);
		VAR y, x, iadr, ibit, jadr, jbit, radr, rbit, k: LONGINT; ipix, jpix, rpix: Pixel;
	BEGIN
		ASSERT((i.width = j.width) & (i.height = j.height) & (i.width <= res.width) & (i.height <= res.height), 100);
		y := 0;
		WHILE y < i.height DO
			x := 0; iadr := i.adr + y * i.bpr; ibit := 0; jadr := j.adr + y * j.bpr; jbit := 0; radr := res.adr + y * res.bpr; rbit := 0;
			WHILE x < i.width DO
				i.fmt.unpack(i.fmt, iadr, ibit, ipix); j.fmt.unpack(j.fmt, jadr, jbit, jpix);
				FOR k := 0 TO 3 DO
					rpix[k] := Clamp[ORD(ipix[k]) + ORD(jpix[k])]
				END;
				res.fmt.pack(res.fmt, radr, rbit, rpix);
				ibit := ibit + i.fmt.bpp; INC(iadr, ibit); ibit := ibit MOD 8;
				jbit := jbit + j.fmt.bpp; INC(jadr, jbit); jbit := jbit MOD 8;
				rbit := rbit + res.fmt.bpp; INC(radr, rbit); rbit := rbit MOD 8;
				INC(x)
			END;
			INC(y)
		END
	END Add;
	
	(** copy image to another using error diffusion dithering (Floyd-Steinberg) **)
	PROCEDURE Dither* (src, dst: Image);
		TYPE
			error = RECORD r, g, b: LONGINT END;
		VAR
			e351: POINTER TO ARRAY OF error;
			y, sadr, dadr, x, sa, sb, da, db, ex, e, e3, e5: LONGINT;
			e7, e51, e1: error;
			spix, dpix: Pixel;
	BEGIN
		ASSERT((src.width <= dst.width) & (src.height <= dst.height), 100);
		NEW(e351, src.width+2);	(* accumulated error for next row *)
		y := 0; sadr := src.adr; dadr := dst.adr;
		WHILE y < src.height DO 	(* scan from left to right *)
			e7.r := 0; e7.g := 0; e7.b := 0;
			e51.r := 0; e51.g := 0; e51.b := 0;
			e1.r := 0; e1.g := 0; e1.b := 0;
			x := 0; sa := sadr; sb := 0; da := dadr; db := 0;
			WHILE x < src.width DO
				ex := x+1;
				src.fmt.unpack(src.fmt, sa, sb, spix);
				spix[r] := Clamp[200H + ORD(spix[r]) + e351[ex].r + e7.r];
				spix[g] := Clamp[200H + ORD(spix[g]) + e351[ex].g + e7.g];
				spix[b] := Clamp[200H + ORD(spix[b]) + e351[ex].b + e7.b];
				dst.fmt.pack(dst.fmt, da, db, spix);
				dst.fmt.unpack(dst.fmt, da, db, dpix);
				e := ORD(spix[r]) - ORD(dpix[r]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
				e7.r := 7*e DIV 16; e351[x].r := e3 + e51.r; e51.r := e5 + e1.r; e1.r := e - e3 - e5 - e7.r;
				e := ORD(spix[g]) - ORD(dpix[g]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
				e7.g := 7*e DIV 16; e351[x].g := e3 + e51.g; e51.g := e5 + e1.g; e1.g := e - e3 - e5 - e7.g;
				e := ORD(spix[b]) - ORD(dpix[b]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
				e7.b := 7*e DIV 16; e351[x].b := e3 + e51.b; e51.b := e5 + e1.b; e1.b := e - e3 - e5 - e7.b;
				sb := sb + src.fmt.bpp; INC(sa, sb DIV 8); sb := sb MOD 8;
				db := db + dst.fmt.bpp; INC(da, db DIV 8); db := db MOD 8;
				x := ex
			END;
			INC(y); INC(sadr, src.bpr); INC(dadr, dst.bpr);
			IF y < src.height THEN	(* scan from right to left *)
				e351[x] := e51;
				e7.r := 0; e7.g := 0; e7.b := 0;
				e51.r := 0; e51.g := 0; e51.b := 0;
				e1.r := 0; e1.g := 0; e1.b := 0;
				INC(sa, src.bpr); INC(da, dst.bpr);
				WHILE x > 0 DO
					ex := x; DEC(x);
					sb := sb - src.fmt.bpp; INC(sa, sb DIV 8); sb := sb MOD 8;
					db := db - dst.fmt.bpp; INC(da, db DIV 8); db := db MOD 8;
					src.fmt.unpack(src.fmt, sa, sb, spix);
					spix[r] := Clamp[200H + ORD(spix[r]) + e351[ex].r + e7.r];
					spix[g] := Clamp[200H + ORD(spix[g]) + e351[ex].g + e7.g];
					spix[b] := Clamp[200H + ORD(spix[b]) + e351[ex].b + e7.b];
					dst.fmt.pack(dst.fmt, da, db, spix);
					dst.fmt.unpack(dst.fmt, da, db, dpix);
					INC(ex);
					e := ORD(spix[r]) - ORD(dpix[r]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
					e7.r := 7*e DIV 16; e351[x].r := e3 + e51.r; e51.r := e5 + e1.r; e1.r := e - e3 - e5 - e7.r;
					e := ORD(spix[g]) - ORD(dpix[g]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
					e7.g := 7*e DIV 16; e351[x].g := e3 + e51.g; e51.g := e5 + e1.g; e1.g := e - e3 - e5 - e7.g;
					e := ORD(spix[b]) - ORD(dpix[b]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
					e7.b := 7*e DIV 16; e351[x].b := e3 + e51.b; e51.b := e5 + e1.b; e1.b := e - e3 - e5 - e7.b
				END;
				e351[1] := e51;
				INC(y); INC(sadr, src.bpr); INC(dadr, dst.bpr)
			END
		END
	END Dither;
	
	
	(**--- File I/O ---**)
	
	(** write image to file rider **)
	PROCEDURE Write* (VAR fr: AosIO.Writer; img: Image);
	VAR m: Image; h, adr, w, aa, len: LONGINT; buf: ARRAY 256 OF CHAR;
			SrcCopy:Mode;	
	BEGIN
		InitMode(SrcCopy, srcCopy);
		IF ~(img.fmt.code IN {a1..bgra8888}) THEN
			NEW(m);
			IF img.fmt.components = {color} THEN Create(m, img.width, img.height, BGR888)
			ELSIF img.fmt.components = {alpha} THEN Create(m, img.width, img.height, A8)
			ELSIF img.fmt.components = {index} THEN Create(m, img.width, img.height, D8)
			ELSE Create(m, img.width, img.height, BGRA8888)
			END;
			Copy(img, m, 0, 0, img.width, img.height, 0, 0, SrcCopy);
			img := m
		END;
		fr.RawNum(1);	(* version *)
		fr.RawNum(img.fmt.code);
		fr.RawNum(img.width); fr.RawNum(img.height);
		fr.RawNum(ABS(img.bpr));
		h := img.height; adr := img.adr;
		WHILE h > 0 DO
			w := ABS(img.bpr); aa := adr;
			WHILE w > 0 DO
				len := 256;
				IF len > w THEN len := w END;
				SYSTEM.MOVE(aa, SYSTEM.ADR(buf[0]), len);
				fr.Bytes(buf, 0, len);
				DEC(w, len); INC(aa, len)
			END;
			DEC(h); INC(adr, img.bpr)
		END;
		IF img.fmt.code = p8 THEN
			fr.RawInt(SHORT(img.fmt.pal.used));
			len := 0;
			WHILE len < img.fmt.pal.used DO
				fr.Char(img.fmt.pal.col[len, r]);
				fr.Char(img.fmt.pal.col[len, g]);
				fr.Char(img.fmt.pal.col[len, b]);
				INC(len)
			END
		END;
		fr.Update	(* optional *)
	END Write;
	
	(** read image from file rider **)
	PROCEDURE Read* (VAR fr: AosIO.Reader; img: Image);
		VAR ver, code, w, h, bpr, adr, aa, len, bytesRead: LONGINT; fmt: Format; buf: ARRAY 256 OF CHAR; used: INTEGER;
	BEGIN
		fr.RawNum(ver);	(* only know version 1, skip check *)
		fr.RawNum(code);
		CASE code OF
		| a1: fmt := A1
		| a8: fmt := A8
		| p8: InitFormat(fmt, p8, 8, 1, {index}, NIL, PackP8, UnpackP8)
		| d8: fmt := D8
		| bgr555: fmt := BGR555
		| bgr565: fmt := BGR565
		| bgr466: fmt := BGR466
		| bgr888: fmt := BGR888
		| bgra8888: fmt := BGRA8888
		END;
		fr.RawNum(w); fr.RawNum(h);
		Create(img, SHORT(w), SHORT(h), fmt);
		fr.RawNum(bpr);
		ASSERT(bpr <= img.bpr);
		adr := img.adr;
		WHILE h > 0 DO
			w := bpr; aa := adr;
			WHILE w > 0 DO
				len := 256;
				IF len > w THEN len := w END;
				fr.Bytes(buf, 0, len, bytesRead);	(* ignore bytesRead *)
				SYSTEM.MOVE(SYSTEM.ADR(buf[0]), aa, len);
				DEC(w, len); INC(aa, len)
			END;
			DEC(h); INC(adr, img.bpr)
		END;
		IF code = p8 THEN
			fr.RawInt(used);
			len := 0; NEW(img.fmt.pal);
			WHILE len < used DO
				fr.Char(img.fmt.pal.col[len, r]);
				fr.Char(img.fmt.pal.col[len, g]);
				fr.Char(img.fmt.pal.col[len, b]);
				img.fmt.pal.col[len, a] := 0FFX;
				INC(len)
			END;
			InitPalette(img.fmt.pal, used, 4)
		END
	END Read;
	
	PROCEDURE GetExtension (VAR name, ext: ARRAY OF CHAR);
		VAR i, j: LONGINT; ch: CHAR;
	BEGIN
		i := 0; j := 0;
		WHILE name[i] # 0X DO
			IF name[i] = "." THEN j := i+1 END;
			INC(i)
		END;
		i := 0;
		REPEAT
			ch := name[j]; ext[i] := ch; INC(i); INC(j)
		UNTIL ch = 0X
	END GetExtension;
	
	PROCEDURE GetCommandProc (VAR ext : ARRAY OF CHAR; function: ARRAY OF CHAR): AosModules.CommandParProc;
		VAR
			i, n, res: LONGINT; ch: CHAR; key, cmd, msg: ARRAY 64 OF CHAR;
			mod: AosModules.Module; proc: AosModules.CommandParProc;
			s:  AosIO.StringWriter;
	BEGIN
		NEW(s, 64);
		s.String("ImageFormats."); s.String(function); s.String("."); s.String(ext);
		s.Get(key);
		
		AosConfig.Get(key, cmd);
		i := 0; WHILE (cmd[i] # 0X) & (cmd[i] # ".") DO INC(i) END;
		IF cmd[i] = "." THEN
			cmd[i] := 0X;
			mod := AosModules.ThisModule(cmd, res, msg);
			IF mod # NIL THEN
				INC(i); n := i; WHILE cmd[i] # 0X DO cmd[i-n] := cmd[i]; INC(i) END;
				cmd[i-n] := 0X; 
				RETURN AosModules.ThisCommandPar(mod, cmd);
			ELSE
				AosOut.String("Raster: Module not found "); AosOut.String(cmd); AosOut.Ln;
				RETURN NIL
			END
		END;
		RETURN NIL
	END GetCommandProc;
	
	(** initialize image from file (see comment for LoadProc and StoreProc) **)
	PROCEDURE Load* (img: Image; name: ARRAY OF CHAR; VAR done: BOOLEAN);
	VAR file: AosFS.File; ext: ARRAY 64 OF CHAR; par : PictureTransferParameters;
		proc :  AosModules.CommandParProc;
	BEGIN
		done := FALSE; file := AosFS.Old(name);
		IF file # NIL THEN
			GetExtension(name, ext);
			IF ext # "" THEN
				proc := GetCommandProc(ext, "Load");
				IF proc # NIL THEN 
					NEW(par);
					COPY(name, par.name); par.img := img;
					IF proc(par) = NIL THEN END;
					done := par.done
				END
			END
		END
	END Load;
	
	(** store image in file (see comment for LoadProc and StoreProc) **)
	PROCEDURE Store* (img: Image; name: ARRAY OF CHAR; VAR done: BOOLEAN);
	VAR ext: ARRAY 64 OF CHAR;
		proc :  AosModules.CommandParProc; par : PictureTransferParameters;
	BEGIN
		done := FALSE;
		GetExtension(name, ext);
		IF ext # "" THEN
			proc := GetCommandProc(ext, "Store");
			IF proc # NIL THEN
				NEW(par);
				COPY(name, par.name); par.img := img;
				IF proc(par) = NIL THEN END;
				done := par.done
			END
		END
	END Store;
	
	
	(*--- Initialization ---*)
	
	PROCEDURE InitBitTables;
		VAR b, i: LONGINT;
	BEGIN
		FOR b := 0 TO 0FFH DO
			FOR i := 0 TO 7 DO
				IF ODD(ASH(b, -i)) THEN
					Bit[b, i] := TRUE; Set[b, i] := CHR(b); Clr[b, i] := CHR(b - ASH(1, i))
				ELSE
					Bit[b, i] := FALSE; Set[b, i] := CHR(b + ASH(1, i)); Clr[b, i] := CHR(b)
				END
			END
		END
	END InitBitTables;
	
	PROCEDURE InitClamp;
		VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO 1FFH DO Clamp[i] := 0X END;
		FOR i := 0 TO 0FFH DO Clamp[200H+i] := CHR(i) END;
		FOR i := 300H TO 4FFH DO Clamp[i] := 0FFX END
	END InitClamp;
	
	PROCEDURE ToggleMMX*;
	BEGIN
		MMXenabled := ~MMXenabled
	END ToggleMMX;
	
BEGIN
	MMXenabled := 23 IN AosBoot.features;
	plugin := AosDisplays.registry.Await("");	(* assume only one system-wide D8 display driver *)
	d8display := plugin(AosDisplays.Display);
	InitFormat(A1, a1, 1, 1, {alpha}, NIL, PackA1, UnpackA1);
	InitFormat(A8, a8, 8, 1, {alpha}, NIL, PackA8, UnpackA8);
	InitFormat(D8, d8, 8, 1, {index}, NIL, PackD8, UnpackD8);
	InitFormat(BGR555, bgr555, 16, 2, {color}, NIL, PackBGR555, UnpackBGR555);
	InitFormat(BGR565, bgr565, 16, 2, {color}, NIL, PackBGR565, UnpackBGR565);
	InitFormat(BGR466, bgr466, 16, 2, {color}, NIL, PackBGR466, UnpackBGR466);
	InitFormat(BGR888, bgr888, 24, 4, {color}, NIL, PackBGR888, UnpackBGR888);
	InitFormat(BGRA8888, bgra8888, 32, 4, {color, alpha}, NIL, PackBGRA8888, UnpackBGRA8888);
	PixelFormat := BGRA8888;
	Zero[0] := 0X; Zero[1] := 0X; Zero[2] := 0X; Zero[3] := 0X;
	InitBitTables; InitClamp
END Raster.

(**
Remarks

1. Images
While many applications wish to handle images of any kind without having to care about details, other applications need low-level access to image interna for maximum effiency. With this in mind, the Images module provides an abstract procedural interface but also discloses low-level information to those clients needing it:
	* an image references a contiguous block of memory holding pixel data
	* the point of reference is the address of the pixel in the lower-left corner
	* pixels are organized in rows (either bottom-up or top-down)
	* rows can be aligned to an arbitrary number of bytes
	* the leftmost pixel in a row has the lowest address of all pixels in that row
	* every pixel uses the same number of bits
Memory for images can be automatically allocated by using Create(). Alternatively, an image can be initialized on an existing memory block (Init(), InitBuf()) or even on part of an other image (InitRect()).

2. Pixels
A general pixel pix[] contains four components (in range 0X..255X), specifying red, green, blue, and alpha value of the pixel and accessable as pix[r], pix[g], pix[b] and pix[a]. Note that in order to speed up compositing operations, the alpha value is premultiplied into the color components. Example: a red pixel with 50% coverage can be initialized with SetRGBA(pix, 255, 0, 0, 127), after which pix[r]=pix[a]=7FX and pix[g]=pix[b]=0X. Use GetRGBA() to recover the original color and alpha values.

3. Palettes
Many bitmap images and Oberon display drivers use some kind of indexed format to store colors, i.e. the value stored in the bitmap serves as an index into an array of colors. A Palette stores up to 256 colors as an array of pixels, making the mapping of an index to the corresponding color straightforward. To speed up the inverse mapping from an RGB triple to an index with PaletteIndex(), additional data is initialized when InitPalette() is called. Use ComputePalette() to compute a palette that best approximates the colors in a given image (e.g. before quantizing it to indexed format).

4. Formats
While general pixels accurately describe color and alpha information, they use a lot of memory (32 bits). Most images therefore only store part of that information. A Format record describes how pixels are represented within an image. It contains
	* the number of bits used per pixel (must be 1, 2, 4, 8, 16, 24 or 32)
	* the set of components stored in a pixel (color, index and/or alpha)
	* a palette if the format uses one
	* procedures for storing (packing) and loading (unpacking) a general pixel
The pack and unpack procedures are given an address and a bit number specifying where the pixel is located in memory, with bit numbers ascending from left to right (although a format is free to choose any bit ordering within a pixel).

5. Predefined Formats
The following global variables contain formats which are special and have a unique code number identifying them. Besides, most operations have better performance if acting on images using them.
	* A1 (code a1): one bit alpha, MSB leftmost (corresponds to Oberon display patterns)
	* A8 (code a8): 8 bit alpha (mainly for anti-aliased character patterns)
	* - (code p8): 8 bit indexed with custom palette (Oberon pictures, use InitPaletteFormat to initialize)
	* D8 (code d8): 8 bit indexed with display palette (no palette structure attached)
	* BGR555 (code bgr555), BGR565 (code bgr565), BGR466 (code bgr466): 16 bit hi-color
	* BGR888 (code bgr888): 24 bit true-color
	* BGRA8888 (code bgra8888), PixelFormat: 32 bit true-color with alpha channel (general pixel format)
Procedure DisplayFormat() returns the format that best matches the supplied kind of display transfer format. The returned image format is preferably used for allocating shadow bitmaps.

6. Compositing
Most operations require a transfer mode for specifying how source and destination pixels should be combined when alpha information is present. The following compositing operations are supported:
	* clear: destination becomes black and completely transparent
	* srcCopy: source completely replaces destination (cf. Display.replace)
	* dstCopy: no effect
	* srcOverDst: source replaces destination where source is opaque (cf. Display.paint)
	* dstOverSrc: destination replaces source where destination is opaque
	* srcInDst: source where destination is opaque
	* dstInSrc: destination where source is opaque
	* srcWithoutDest*: source is cleared where destination is opaque
	* dstWithoutSrc*: destination is cleared where source is opaque
	* srcAtopDst*: source replaces destination where destination is opaque
	* dstAtopSrc*: destination replaces source where source is opaque
	* srcXorDst*: destination is cleared where both source and destination are opaque (cf. Display.invert)
A transfer mode is initialized with a compositing operation and optionally with a color. (The color is used when the source is a pure alpha format which doesn't contain any color of its own.) An initialized mode can be bound to a source and destination format by calling Bind(), by which the mode's transfer procedure is set appropriately. A transfer procedure unpacks pixels from source and destination, blends them according to the compositing operation, and packs the resulting pixel in the destination. Bind() chooses an optimal transfer procedure for the given combination of compositing operation, source format, and destination format.

7. Internalization and Externalization
Images can be loaded from file and stored to file using one of many popular image file formats. The Load() and Store() procedures rely on a section 'ImageFormats' in the Aos registry. This section contains a list of file types that are associated with command procedures. When one of these commands is called, it should initialize the global 'LoadProc' and 'StoreProc' variables. These, when called, should read an image from or write an image to the file and set 'done' to TRUE if successful.
**)

(* to do:
o perhaps remove D8 mode, so that Raster no longer needs to know display
*)
