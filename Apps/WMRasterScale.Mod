MODULE WMRasterScale;	(** AUTHOR "TF"; PURPOSE "Support scaling of images"; *)

IMPORT
	SYSTEM, Raster, Rect := WMRectangles, AosOut, Utilities;
	
CONST
	(** Copy Modes *)
	ModeCopy* = 0; ModeSrcOverDst* = 1; 
	
	(** Scale Modes *)
	ScaleBox* = 0; ScaleBilinear* = 1;

TYPE
	Rectangle = Rect.Rectangle;
	Image = Raster.Image;
	ScalerProc = PROCEDURE (src, dst : Image; VAR dr : Rectangle; sx, sy, sdx, sdy : LONGINT);
	XScalerProc = PROCEDURE (srcadr, dstadr, srcbpr, dstbpr, dl, dt, dr, db, sx, sy, sdx, sdy, sw, sh : LONGINT);

VAR newFeatures : BOOLEAN;

(* copy sr in 16.16 fix rectangle  from src to dr integer rectangle in dst *)
PROCEDURE Q0GenericCopy(src, dst : Image; VAR dr : Rectangle; sx, sy, sdx, sdy : LONGINT);
VAR x, y : LONGINT; col : Raster.Pixel;
	getMode, putMode : Raster.Mode; 
	fx, fy : LONGINT;
BEGIN
	Raster.InitMode(getMode, Raster.srcCopy); 
	Raster.InitMode(putMode, Raster.srcCopy);
	fy := sy;
	FOR y := dr.t TO dr.b - 1 DO
		fx := sx;
		FOR x := dr.l TO dr.r - 1 DO
			Raster.Get(src, fx DIV 65536, fy DIV 65536, col, getMode);
			INC(fx, sdx);
			Raster.Put(dst, x, y, col, putMode)
		END;
		INC(fy, sdy)
	END
END Q0GenericCopy;

PROCEDURE Q0GenericSrcOverDst(src, dst : Image; VAR dr : Rectangle; sx, sy, sdx, sdy : LONGINT);
VAR x, y : LONGINT; col : Raster.Pixel;
	getMode, putMode : Raster.Mode; 
	fx, fy : LONGINT;
BEGIN
	Raster.InitMode(getMode, Raster.srcCopy); 
	Raster.InitMode(putMode, Raster.srcOverDst);
	fy := sy;
	FOR y := dr.t TO dr.b - 1 DO
		fx := sx;
		FOR x := dr.l TO dr.r - 1 DO
			Raster.Get(src, fx DIV 65536, fy DIV 65536, col, getMode);
			INC(fx, sdx);
			Raster.Put(dst, x, y, col, putMode)
		END;
		INC(fy, sdy)
	END
END Q0GenericSrcOverDst;

(* copy sr in 16.16 fix rectangle  from src to dr integer rectangle in dst *)
PROCEDURE Q1GenericCopy(src, dst : Image; VAR dr : Rectangle; sx, sy, sdx, sdy : LONGINT);
VAR x, y, xfleft, xfright, yftop, yfbottom : LONGINT; col, col0, col1, col2, col3 : Raster.Pixel;
	b0, g0, r0, a0, b1, g1, r1, a1, cb, cg, cr, ca : LONGINT;
	getMode, putMode : Raster.Mode; 
	fx, fy : LONGINT; x0, x1, y0, y1 : LONGINT;
BEGIN
	Raster.InitMode(getMode, Raster.srcCopy); 
	Raster.InitMode(putMode, Raster.srcCopy);
	fy := sy - 8000H; sx := sx - 8000H;
	FOR y := dr.t TO dr.b - 1 DO
		fx := sx; y0 := Bounds(fy DIV 65536, 0, src.height - 1); y1 := Bounds(fy DIV 65536 + 1, 0, src.height - 1);
		FOR x := dr.l TO dr.r - 1 DO
			x0 := Bounds(fx DIV 65536, 0, src.width - 1); x1 := Bounds(fx DIV 65536 + 1, 0, src.width - 1);
			Raster.Get(src, x0, y0, col0, getMode);
			Raster.Get(src, x1, y0, col1, getMode);
			Raster.Get(src, x0, y1, col2, getMode);
			Raster.Get(src, x1, y1, col3, getMode);
			
			xfleft := (65536 - fx MOD 65536);
			xfright := (fx MOD 65536);
			
			b0 := (ORD(col0[Raster.b]) * xfleft + ORD(col1[Raster.b]) * xfright) DIV 65536;
			g0 := (ORD(col0[Raster.g]) * xfleft + ORD(col1[Raster.g]) * xfright) DIV 65536;
			r0 := (ORD(col0[Raster.r]) * xfleft + ORD(col1[Raster.r]) * xfright) DIV 65536;
			a0 := (ORD(col0[Raster.a]) * xfleft + ORD(col1[Raster.a]) * xfright) DIV 65536;
			
			b1 := (ORD(col2[Raster.b]) * xfleft + ORD(col3[Raster.b]) * xfright) DIV 65536;
			g1 := (ORD(col2[Raster.g]) * xfleft + ORD(col3[Raster.g]) * xfright) DIV 65536;
			r1 := (ORD(col2[Raster.r]) * xfleft + ORD(col3[Raster.r]) * xfright) DIV 65536;
			a1 := (ORD(col2[Raster.a]) * xfleft + ORD(col3[Raster.a]) * xfright) DIV 65536;
			
			yftop := (65536 - fy MOD 65536);
			yfbottom := (fy MOD 65536);
			cb := (b0 * yftop + b1 * yfbottom) DIV 65536;
			cg := (g0 * yftop + g1 * yfbottom) DIV 65536;
			cr := (r0 * yftop + r1 * yfbottom) DIV 65536; 
			ca := (a0 * yftop + a1 * yfbottom) DIV 65536; 
			
			col[Raster.b] := CHR(cb);
			col[Raster.g] := CHR(cg);
			col[Raster.r] := CHR(cr);
			col[Raster.a] := CHR(ca);
			INC(fx, sdx);
			Raster.Put(dst, x, y, col, putMode)
		END;
		INC(fy, sdy)
	END
END Q1GenericCopy;

(* copy sr in 16.16 fix rectangle  from src to dr integer rectangle in dst *)
PROCEDURE Q1GenericSrcOverDst(src, dst : Image; VAR dr : Rectangle; sx, sy, sdx, sdy : LONGINT);
VAR x, y, xfleft, xfright, yftop, yfbottom : LONGINT; col, col0, col1, col2, col3 : Raster.Pixel;
	b0, g0, r0, a0, b1, g1, r1, a1, cb, cg, cr, ca : LONGINT;
	getMode, putMode : Raster.Mode; 
	fx, fy : LONGINT; x0, x1, y0, y1 : LONGINT;
BEGIN
	Raster.InitMode(getMode, Raster.srcCopy); 
	Raster.InitMode(putMode, Raster.srcOverDst);
	fy := sy - 8000H; sx := sx - 8000H;
	FOR y := dr.t TO dr.b - 1 DO
		fx := sx; y0 := Bounds(fy DIV 65536, 0, src.height - 1); y1 := Bounds(fy DIV 65536 + 1, 0, src.height - 1);
		FOR x := dr.l TO dr.r - 1 DO
			x0 := Bounds(fx DIV 65536, 0, src.width - 1); x1 := Bounds(fx DIV 65536 + 1, 0, src.width - 1);
			Raster.Get(src, x0, y0, col0, getMode);
			Raster.Get(src, x1, y0, col1, getMode);
			Raster.Get(src, x0, y1, col2, getMode);
			Raster.Get(src, x1, y1, col3, getMode);

			xfleft := (65536 - fx MOD 65536);
			xfright := (fx MOD 65536);
			
			b0 := (ORD(col0[Raster.b]) * xfleft + ORD(col1[Raster.b]) * xfright) DIV 65536;
			g0 := (ORD(col0[Raster.g]) * xfleft + ORD(col1[Raster.g]) * xfright) DIV 65536;
			r0 := (ORD(col0[Raster.r]) * xfleft + ORD(col1[Raster.r]) * xfright) DIV 65536;
			a0 := (ORD(col0[Raster.a]) * xfleft + ORD(col1[Raster.a]) * xfright) DIV 65536;
			
			b1 := (ORD(col2[Raster.b]) * xfleft + ORD(col3[Raster.b]) * xfright) DIV 65536;
			g1 := (ORD(col2[Raster.g]) * xfleft + ORD(col3[Raster.g]) * xfright) DIV 65536;
			r1 := (ORD(col2[Raster.r]) * xfleft + ORD(col3[Raster.r]) * xfright) DIV 65536;
			a1 := (ORD(col2[Raster.a]) * xfleft + ORD(col3[Raster.a]) * xfright) DIV 65536;
			
			yftop := (65536 - fy MOD 65536);
			yfbottom := (fy MOD 65536);
			cb := (b0 * yftop + b1 * yfbottom) DIV 65536;
			cg := (g0 * yftop + g1 * yfbottom) DIV 65536;
			cr := (r0 * yftop + r1 * yfbottom) DIV 65536; 
			ca := (a0 * yftop + a1 * yfbottom) DIV 65536; 
			
			col[Raster.b] := CHR(cb);
			col[Raster.g] := CHR(cg);
			col[Raster.r] := CHR(cr);
			col[Raster.a] := CHR(ca);
			INC(fx, sdx);
			Raster.Put(dst, x, y, col, putMode)
		END;
		INC(fy, sdy)
	END
END Q1GenericSrcOverDst;

PROCEDURE Q0BGR565BGR565(srcadr, dstadr, srcbpr, dstbpr, dl, dt, dr, db, sx, sy, sdx, sdy, sw, sh : LONGINT);
VAR x, y : LONGINT; yadr, adr, sa, col : LONGINT;
	fx, fy : LONGINT;
BEGIN
	fy := sy;
	yadr := dstadr + dl * 2 + dt * dstbpr;
	FOR y := dt TO db - 1 DO
		fx := sx;
		adr := yadr;
		sa := srcadr + (fy DIV 65536) * srcbpr;
		FOR x := dl TO dr - 1 DO
			col := SYSTEM.GET16(sa + (fx DIV 65536) * 2);
			INC(fx, sdx);
			SYSTEM.PUT16(adr, col);
			INC(adr, 2);
		END;
		INC(fy, sdy);
		INC(yadr, dstbpr)
	END
END Q0BGR565BGR565;

(* this asm version is 2.3 times faster than the portable version. (P3/600/Dell precision 420 (dual)) *)
PROCEDURE XQ0BGR565BGR565(srcadr, dstadr, srcbpr, dstbpr, dl, dt, dr, db, sx, sy, sdx, sdy, sw, sh : LONGINT);
VAR yadr : LONGINT;
CODE {SYSTEM.i386}
 	MOV	EDX, dstadr[EBP]
	MOV	EBX, dl[EBP]
	SHL	EBX, 1
	ADD	EDX, EBX	
	MOV	EBX, dt[EBP]
	IMUL	EBX, dstbpr[EBP]
	ADD	EDX, EBX	(* edx = dstadr + 2 * dl + dt * dstbpr *)
	MOV	yadr[EBP], EDX
	(* init first EDI *)
	MOV	EDI, EDX
	
	MOV	ECX, dt[EBP]
	SUB	db[EBP], ECX	(* counter in db *)

	MOV	EDX, sdx[EBP]	(* keep EDX *)
	
	(* init first ESI *)
	MOV	ESI, srcadr[EBP]	(* calc new source adr *)
	MOV	EAX, sy[EBP]
	SHR	EAX, 16	(* integer part of sy *)
	IMUL 	EAX, srcbpr[EBP]	(* sy * srcbpr *)
	ADD	ESI, EAX	(* first source adr in ESI *)
	
outerloop:
	MOV	EBX, sx[EBP]
	MOV	ECX, dr[EBP]	(* FOR x := dl TO dr - 1 DO *)
	SUB	ECX, dl[EBP]
innerloop:
	MOV	EAX, EBX
	SHR	EAX, 16	
	MOV	AX, WORD PTR [ESI + EAX * 2]	(* read the pixel *)
	ADD	EBX, EDX	(* INC fx, sdx *)
	MOV	[EDI], AX	(* set the pixel *)
	ADD	EDI, 2	(* inc adr *)
	LOOP	innerloop
	
	(* free : EAX, EBX, ECX *)
	MOV	EAX, sy[EBP]	(* sy := sy + sdy *)
	ADD	EAX, sdy[EBP]
	MOV	sy[EBP], EAX	(* keep sy in EAX *)
	
	MOV	ESI, srcadr[EBP]	(* calc new source adr *)
	SHR	EAX, 16	(* integer part of sy *)
	IMUL 	EAX, srcbpr[EBP]	(* sy * srcbpr *)
	ADD	ESI, EAX	(* new source adr in ESI *)
	
	(* new dst address *)
	MOV	ECX, dstbpr[EBP]
	MOV	EAX, yadr[EBP]
	ADD	EAX, ECX
	MOV	EDI, EAX
	MOV	yadr[EBP], EAX
	
	DEC	db[EBP]
	JNLE	outerloop
END XQ0BGR565BGR565;

PROCEDURE Q1BGR565BGR565(srcadr, dstadr, srcbpr, dstbpr, dl, dt, dr, db, sx, sy, sdx, sdy, sw, sh : LONGINT);
VAR x, y, xfleft, xfright, yftop, yfbottom : LONGINT; yadr, adr, col, col0, col1, col2, col3 : LONGINT;
	b0, g0, r0, b1, g1, r1, cb, cg, cr : LONGINT;
	fx, fy, yadd1, yadd2, xadd1, xadd2 : LONGINT;
BEGIN
	yadr := dstadr + dl * 2 + dt * dstbpr;
	fy := sy - 8000H; sx := sx - 8000H;
	FOR y := dt TO db - 1 DO
		fx := sx;
		adr := yadr;
		yadd1 := srcadr + Bounds(fy DIV 65536, 0, sh - 1) * srcbpr;
		yadd2 := srcadr + Bounds(fy DIV 65536 + 1, 0, sh - 1) * srcbpr;
		FOR x := dl TO dr - 1 DO
			xadd1 := Bounds(fx DIV 65536, 0, sw - 1) * 2;
			xadd2 := Bounds(fx DIV 65536 + 1, 0, sw - 1) * 2;
			col0 := SYSTEM.GET16(yadd1 + xadd1);
			col1 := SYSTEM.GET16(yadd1 + xadd2);
			col2 := SYSTEM.GET16(yadd2 + xadd1);
			col3 := SYSTEM.GET16(yadd2 + xadd2);
			
			xfleft := (65536 - fx MOD 65536);
			xfright := (fx MOD 65536);
					
			b0 := ((col0 MOD 32) * 8 * xfleft + (col1 MOD 32) * 8 * xfright) DIV 65536;
			g0 := ((col0 DIV 32 MOD 64) * 4 * xfleft + (col1 DIV 32 MOD 64) * 4 * xfright) DIV 65536;
			r0 := ((col0 DIV 2048 MOD 32) * 8 * xfleft + (col1 DIV 2048 MOD 32) * 8 * xfright) DIV 65536;
					
			b1 := ((col2 MOD 32) * 8 * xfleft + (col3 MOD 32) * 8 * xfright) DIV 65536;
			g1 := ((col2 DIV 32 MOD 64) * 4 * xfleft + (col3 DIV 32 MOD 64) * 4 * xfright) DIV 65536;
			r1 := ((col2 DIV 2048 MOD 32) * 8 * xfleft + (col3 DIV 2048 MOD 32) * 8 * xfright) DIV 65536; 
					
					
			yftop := (65536 - fy MOD 65536);
			yfbottom := (fy MOD 65536);
			cb := (b0 * yftop + b1 * yfbottom) DIV 65536;
			cg := (g0 * yftop + g1 * yfbottom) DIV 65536;
			cr := (r0 * yftop + r1 * yfbottom) DIV 65536; 
			INC(fx, sdx);
			SYSTEM.PUT16(adr, ASH(cb, -3) + ASH(ASH(cg, -2), 5) + ASH(ASH(cr, -3), 11));
			INC(adr, 2);
		END;
		INC(fy, sdy);
		INC(yadr, dstbpr)
	END
END Q1BGR565BGR565;

PROCEDURE Q1BGRA8888BGR565(srcadr, dstadr, srcbpr, dstbpr, dl, dt, dr, db, sx, sy, sdx, sdy, sw, sh : LONGINT);
VAR x, y, xfleft, xfright, yftop, yfbottom : LONGINT; yadr, adr, col, col0, col1, col2, col3 : LONGINT;
	b0, g0, r0, a0, b1, g1, r1, a1, cb, cg, cr, ca, dstb, dstg, dstr : LONGINT;
	fx, fy, yadd0, yadd1, xadd0, xadd1: LONGINT;
BEGIN
	yadr := dstadr + dl * 2 + dt * dstbpr;
	fy := sy - 8000H; sx := sx - 8000H;
	FOR y := dt TO db - 1 DO
		fx := sx;
		dstadr := yadr;
		yadd0 := srcadr + Bounds(fy DIV 65536, 0, sh - 1) * srcbpr;
		yadd1 := srcadr + Bounds(fy DIV 65536 + 1, 0, sh - 1) * srcbpr;
		FOR x := dl TO dr - 1 DO
			(* destination color *)
			col := SYSTEM.GET16(dstadr); 
			dstb := (col MOD 32) * 8; dstg := (col DIV 32 MOD 64) * 4; dstr := (col DIV 2048 MOD 32) * 8;
			xadd0 := Bounds(fx DIV 65536, 0, sw - 1) * 4;
			xadd1 := Bounds(fx DIV 65536 + 1, 0, sw - 1) * 4;
			col0 := SYSTEM.GET32(yadd0 + xadd0);
			col1 := SYSTEM.GET32(yadd0 + xadd1);
			col2 := SYSTEM.GET32(yadd1 + xadd0);
			col3 := SYSTEM.GET32(yadd1 + xadd1);
			
			xfleft := (65536 - fx MOD 65536);
			xfright := (fx MOD 65536);
			yftop := (65536 - fy MOD 65536);
			yfbottom := (fy MOD 65536);
			a0 := ((col0 DIV 1000000H MOD 100H) * xfleft + (col1 DIV 1000000H MOD 100H) * xfright) DIV 65536;
			a1 := ((col2 DIV 1000000H MOD 100H) * xfleft + (col3 DIV 1000000H MOD 100H) * xfright) DIV 65536;
			ca := (a0 * yftop + a1 * yfbottom) DIV 65536;
			
			IF ca # 0 THEN
				b0 := ((col0 MOD 100H) * xfleft + (col1 MOD 100H) * xfright) DIV 65536;
				g0 := ((col0 DIV 100H MOD 100H) * xfleft + (col1 DIV 100H MOD 100H) * xfright) DIV 65536;
				r0 := ((col0 DIV 10000H MOD 100H) * xfleft + (col1 DIV 10000H MOD 100H) * xfright) DIV 65536;
						
				b1 := ((col2 MOD 100H) * xfleft + (col3 MOD 100H) * xfright) DIV 65536;
				g1 := ((col2 DIV 100H MOD 100H) * xfleft + (col3 DIV 100H MOD 100H) * xfright) DIV 65536;
				r1 := ((col2 DIV 10000H MOD 100H) * xfleft + (col3 DIV 10000H MOD 100H) * xfright) DIV 65536;
						
				cb := (b0 * yftop + b1 * yfbottom) DIV 65536;
				cg := (g0 * yftop + g1 * yfbottom) DIV 65536;
				cr := (r0 * yftop + r1 * yfbottom) DIV 65536; 
				IF ca # 255 THEN
					cb := (cb * 256 + (256 - ca) * dstb) DIV 256; IF cb > 256 THEN cb := 256 END;
					cg := (cg * 256 + (256 - ca) * dstg) DIV 256; IF cg > 256 THEN cg := 256 END;
					cr := (cr * 256 + (256 - ca) * dstr) DIV 256; IF cr > 256 THEN cr := 256 END
				END;	
				SYSTEM.PUT16(dstadr, ASH(cb, -3) + ASH(ASH(cg, -2), 5) + ASH(ASH(cr, -3), 11))
			END;
			INC(fx, sdx);
			INC(dstadr, 2);
		END;
		INC(fy, sdy);
		INC(yadr, dstbpr)
	END
END Q1BGRA8888BGR565;

PROCEDURE Q0BGRA8888BGR565(srcadr, dstadr, srcbpr, dstbpr, dl, dt, dr, db, sx, sy, sdx, sdy, sw, sh : LONGINT);
VAR x, y, xfleft, xfright, yftop, yfbottom : LONGINT; yadr, adr, col, col0, col1, col2, col3 : LONGINT;
	cb, cg, cr, ca, dstb, dstg, dstr, yadd : LONGINT;
	fx, fy : LONGINT;
BEGIN
	fy := sy;
	yadr := dstadr + dl * 2 + dt * dstbpr;
	FOR y := dt TO db - 1 DO
		fx := sx;
		adr := yadr;
		yadd := srcadr + (fy DIV 65536) * srcbpr;
		FOR x := dl TO dr - 1 DO
			(* destination color *)
			col := SYSTEM.GET16(adr); 
			dstb := (col MOD 32) * 8; dstg := (col DIV 32 MOD 64) * 4; dstr := (col DIV 2048 MOD 32) * 8;
			
			col0 := SYSTEM.GET32(yadd + (fx DIV 65536) * 4);
			
			ca := (col0 DIV 1000000H MOD 100H);
			IF ca # 0 THEN
				cb := (col0 MOD 100H);
				cg := (col0 DIV 100H MOD 100H);
				cr := (col0 DIV 10000H MOD 100H);
						
				IF ca # 255 THEN
					cb := (cb * 256 + (256 - ca) * dstb) DIV 256; IF cb > 256 THEN cb := 256 END;
					cg := (cg * 256 + (256 - ca) * dstg) DIV 256; IF cg > 256 THEN cg := 256 END;
					cr := (cr * 256 + (256 - ca) * dstr) DIV 256; IF cr > 256 THEN cr := 256 END
				END;	
				SYSTEM.PUT16(adr, ASH(cb, -3) + ASH(ASH(cg, -2), 5) + ASH(ASH(cr, -3), 11))
			END;
			INC(fx, sdx);
			INC(adr, 2)
		END;
		INC(fy, sdy);
		INC(yadr, dstbpr)
	END
END Q0BGRA8888BGR565;

PROCEDURE Scale*(src : Image; sr : Rectangle; dst : Image; dr : Rectangle; clip : Rectangle; copyMode, scaleMode : LONGINT);
VAR dw, dh, sw, sh : LONGINT;
	fw, fh : LONGREAL; sx, sy : LONGINT;
	scaler : ScalerProc; xscaler : XScalerProc;
	mode : Raster.Mode;
BEGIN
	ASSERT((clip.l >= 0) & (clip.t >= 0) & (clip.r <= dst.width) & (clip.b <= dst.height));
	ASSERT((sr.l >= 0) & (sr.t >= 0) & (sr.r <= src.width) & (sr.b <= src.height));
	dw := dr.r - dr.l; dh := dr.b - dr.t;
	sw := sr.r - sr.l; sh := sr.b - sr.t;
	
	IF (sw = dw) & (sh = dh) THEN (* optimize special case *)
		IF ~Rect.IsContained(clip, dr) THEN
			IF dr.l < clip.l THEN DEC(dw, (clip.l - dr.l)); INC(sr.l, (clip.l - dr.l)); dr.l := clip.l END;
			IF dr.t < clip.t THEN DEC(dh, (clip.t - dr.t)); INC(sr.t, (clip.t - dr.t)); dr.t := clip.t END;
			IF dr.r > clip.r THEN DEC(dw, (dr.r - clip.r)) END;
			IF dr.b > clip.b THEN DEC(dh, (dr.b - clip.b)) END;
		END;
		IF (dw > 0) & (dh > 0) THEN
			IF copyMode = ModeCopy THEN Raster.InitMode(mode, Raster.srcCopy) 
			ELSE Raster.InitMode(mode, Raster.srcOverDst)
			END;
			Raster.Copy(src, dst, sr.l, sr.t, sr.l + dw, sr.t + dh, dr.l, dr.t, mode)
		END;
		RETURN
	END;
	
	fw := sw / dw;
	fh := sh / dh; 
	sx := sr.l * 65536;
	sy := sr.t * 65536;
	(* clipping *)
	IF ~Rect.IsContained(clip, dr) THEN
		sw := sr.r - sr.l; sh := sr.b - sr.t; 
		dw := dr.r - dr.l; dh := dr.b - dr.t; 
		IF dr.r > clip.r THEN dr.r := clip.r END;
		IF dr.b > clip.b THEN dr.b := clip.b END;
		IF dr.l < clip.l THEN sx := ENTIER(65536 * (sr.l +  sw * (clip.l - dr.l) / dw)); dr.l := clip.l END;
		IF dr.t < clip.t THEN sy := ENTIER(65536 * (sr.t + sh * (clip.t - dr.t) / dh)); dr.t := clip.t END;
	END;
	IF Rect.RectEmpty(dr) THEN RETURN END;
	xscaler := NIL;
	IF (src.fmt.code = Raster.bgr565) & (dst.fmt.code = Raster.bgr565) THEN
		IF copyMode = ModeCopy THEN
			IF scaleMode = 0 THEN xscaler := XQ0BGR565BGR565
			ELSIF scaleMode = 1 THEN xscaler := Q1BGR565BGR565
			END
		END
	ELSIF (src.fmt.code = Raster.bgra8888) & (dst.fmt.code = Raster.bgr565) THEN
		IF copyMode = ModeSrcOverDst THEN
			IF scaleMode = 0 THEN xscaler := Q0BGRA8888BGR565
			ELSIF scaleMode = 1 THEN xscaler := Q1BGRA8888BGR565
			END 
		END
	END;
	IF xscaler # NIL THEN
		xscaler(src.adr, dst.adr, src.bpr, dst.bpr, dr.l, dr.t, dr.r, dr.b, sx, sy, 
			ENTIER(fw * 65536), ENTIER(fh * 65536), src.width, src.height)
	ELSE
		scaler := Q0GenericSrcOverDst; (* fallback case *)
		IF copyMode = ModeCopy THEN
			IF scaleMode = 0 THEN scaler := Q0GenericCopy 
			ELSIF scaleMode = 1 THEN scaler := Q1GenericCopy
			END
		ELSIF copyMode = ModeSrcOverDst THEN 
			IF scaleMode = 0 THEN scaler := Q0GenericSrcOverDst 
			ELSIF scaleMode = 1 THEN scaler := Q1GenericSrcOverDst
			END
		END;
		scaler(src, dst, dr, sx, sy, ENTIER(fw * 65536), ENTIER(fh * 65536))	
	END
END Scale;

PROCEDURE Bounds(val, min, max : LONGINT) : LONGINT;
BEGIN
	IF val < min THEN RETURN min ELSIF val > max THEN RETURN max ELSE RETURN val END
END Bounds;

PROCEDURE ToggleNewFeatures*(par : PTR) : PTR;
BEGIN
	newFeatures := ~newFeatures;
	RETURN NIL
END ToggleNewFeatures;

END WMRasterScale.


SpeedTest.Mod