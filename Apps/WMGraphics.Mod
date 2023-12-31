MODULE WMGraphics;	(** AUTHOR "TF"; PURPOSE "Generic Graphic Support"; *)

IMPORT
	AosKernel, Rectangles := WMRectangles, Raster, AosOut, UTF8Strings, Utilities, RasterScale := WMRasterScale;

CONST
	(** Copy Modes *)
	ModeCopy* = RasterScale.ModeCopy; ModeSrcOverDst* = RasterScale.ModeSrcOverDst; 
	
	(** Scale Modes *)
	ScaleBox* = RasterScale.ScaleBox; ScaleBilinear* = RasterScale.ScaleBilinear;
	
	(** Clip Modes *)
	ClipNone* = 0; ClipRect* = 1; (*ClipStencil* = 2;*)
	
	(** FontStyles *)
	FontBold* = 0; FontItalic* = 1;
	
	Black* = 0FFH; White* = 0FFFFFFFFH;
	Red* = 0FF0000FFH; Green* = 000FF00FFH; Blue* = 0FFFFH;
	Yellow* = 0FFFF00FFH; Magenta* = 0FF00FFFFH; Cyan* = 00FFFFFFH; 
	

TYPE
	Char32 = LONGINT;
	Point2d* = RECORD x*, y* : LONGINT END;
	Image* = OBJECT(Raster.Image)
	VAR
		key : POINTER TO ARRAY OF CHAR;
	END Image;
	
	Rectangle* = Rectangles.Rectangle;
	Color* = LONGINT;
	
	GlyphSpacings* = RECORD
		bearing* : Rectangle;
		width*, height*, ascent*, descent* : LONGINT;
		dx*, dy* : LONGINT; (** Delta position where the bitmap returned by GetGlyphMap has to be placed relatively to
											x, y on the base line *)
	END;
	
	(* Bearings are the blank spaces left an right of a character. 
		bearing.l is the left, bearing.r is the right, bearing.t top and bearing.b the bottom side - bearing of the character
		hadvance = bearing.l + width + bearing.r --> the distance to the next character on the line without --> kerning
		vadvance = bearing.t + height + bearing.b --> the baseline to baseline distance of two lines of this font

		When rendering a character at the position (x, y), y refers to the y position of the baseline, x refers to .
		--> Kerning pairs
		
		
	*)
	(* ascent is the height of the font above the base line in units of the destination canvas *)
	(* descent is the height of the font below the base line in units of the destination canvas *)
	(* basetobasedist is the suggested distance between two lines of this font *)

	Font* = OBJECT
	VAR
		ascent*, descent* : LONGINT;
		name* : ARRAY 256 OF CHAR;
		size* : LONGINT;
		style* : SET;
		
		PROCEDURE &Init;
		BEGIN
		END Init;
		
		PROCEDURE GetHeight*():LONGINT;
		BEGIN
			RETURN ascent + descent
		END GetHeight;
		
		PROCEDURE GetAscent*():LONGINT;
		BEGIN
			RETURN ascent
		END GetAscent;
		
		PROCEDURE GetDescent*():LONGINT;
		BEGIN
			RETURN descent
		END GetDescent;
		
		(* return TRUE if the font can render the character *)
		PROCEDURE HasChar*(char : Char32) : BOOLEAN;
		BEGIN
			RETURN FALSE
		END HasChar;
		
		(** Render an UTF8 string to a canvas *)
		PROCEDURE RenderString*(canvas : Canvas ; x, y : REAL; text : ARRAY OF CHAR); 
		VAR i, len, code : LONGINT;
			g : GlyphSpacings; img : Image;
		BEGIN
			len := LEN(text); i := 0;
			WHILE (i < len) & (text[i] # 0X) DO
				IF UTF8Strings.DecodeChar(text, i, code) THEN
					IF HasChar(code) THEN
						GetGlyphSpacings(code, g);
						RenderChar(canvas, x, y, code)
					ELSE
						FBGetGlyphSpacings(code, g);
						FBRenderChar(canvas, x, y, code)						
					END;
					x := x + g.bearing.l + g.width + g.bearing.r
				ELSE INC(i) (* avoid endless loop *)
				END	
			END
		END RenderString;
		
		(** Render an UTF8 string to a canvas *)
		PROCEDURE GetStringSize*(text : ARRAY OF CHAR; VAR dx, dy : LONGINT);
		VAR i, len, code : LONGINT;
			g : GlyphSpacings; img : Image;
		BEGIN
			len := LEN(text); i := 0; dx := 0; dy := GetHeight();
			WHILE (i < len) & (text[i] # 0X) DO
				IF UTF8Strings.DecodeChar(text, i, code) THEN
					IF HasChar(code) THEN GetGlyphSpacings(code, g);
					ELSE FBGetGlyphSpacings(code, g)
					END;
					dy := Utilities.Max(dy, g.height);
					dx := dx + g.bearing.l + g.width + g.bearing.r
				ELSE INC(i) (* avoid endless loop *)
				END	
			END
		END GetStringSize;
		
		(** Render character char to canvas at x, y (baseline) *)
		PROCEDURE RenderChar*(canvas : Canvas ; x, y : REAL; char : Char32); 
		VAR g : GlyphSpacings; img : Image;
		BEGIN
			GetGlyphSpacings(char, g);
			GetGlyphMap(char, img);
			canvas.DrawImage(ENTIER(x + g.bearing.l) + g.dx, ENTIER(y - ascent) + g.dy, img, ModeSrcOverDst)
		END RenderChar;
		
		(** return a bitmap of character code *)
		PROCEDURE GetGlyphMap*(code : LONGINT; VAR map : Image);
		BEGIN
		END GetGlyphMap;
		
		(** return spacing of character code *)
		PROCEDURE GetGlyphSpacings*(code : LONGINT; VAR glyphSpacings : GlyphSpacings);
		BEGIN
		END GetGlyphSpacings;
	END Font;
	
	FontManager* = OBJECT
		PROCEDURE GetFont*(name : ARRAY OF CHAR; size : LONGINT; style : SET) : Font;
		BEGIN
			RETURN NIL
		END GetFont;
	END FontManager;
	
	CanvasState* = OBJECT
	VAR
		clipMode : SET;
		clipRect : Rectangle;
		limits : Rectangle;
		dx, dy : LONGINT;
		font : Font;
		color : LONGINT;
	END CanvasState; 
	
	Canvas* = OBJECT 
	VAR
		limits*, (* The limits to which the clip Rect can be set *)
		clipRect* : Rectangle; (* The current clip rectangle *)
		dx*, dy*, color* : LONGINT;
		clipMode* : SET;
		
		font : Font;
		
		(** IF cs is NIL a new canvas state object is created for this canvas, otherwise cs is reused *)
		PROCEDURE SaveState*(VAR cs : CanvasState);
		BEGIN
			IF cs = NIL THEN NEW(cs) END;
			cs.clipMode := clipMode;
			cs.limits := limits;
			cs.dx := dx; cs.dy := dy;
			cs.font := font; cs.color := color;
			GetClipRect(cs.clipRect)
		END SaveState;
		
		(** Restore a previously saved canvas state *)
		PROCEDURE RestoreState*(cs : CanvasState);
		BEGIN
			IF cs # NIL THEN 
				clipMode := cs.clipMode;
				limits := cs.limits; 
				dx := cs.dx; dy := cs.dy;
				font := cs.font; color := cs.color;
				SetClipRect(cs.clipRect)
			END	
		END RestoreState;
		
		(** set the current clipping rectangle as the limit for new SetClipRect operations.
			ddx and ddy specify a coordinate shift. *)
		PROCEDURE ClipRectAsNewLimits*(ddx, ddy : LONGINT);
		VAR t : Rectangle;
		BEGIN
			limits := clipRect;
			SetDelta(dx + ddx, dy + ddy)
		END ClipRectAsNewLimits;
		
		(** in user coordinates *)
		PROCEDURE SetClipRect*(rect : Rectangle);
		BEGIN
			INCL(clipMode, ClipRect);
			rect.r := Max(rect.r, rect.l); rect.b := Max(rect.b, rect.t);
			Rectangles.MoveRel(rect, dx, dy);
			Rectangles.ClipRect(rect, limits);
			clipRect := rect
		END SetClipRect;
		
		(** return the current Clipping rectangle in user coordinates; Clients may use this to avoid drawing that is
			clipped away for sure *)
		PROCEDURE GetClipRect*(VAR rect : Rectangle);
		BEGIN
			rect := clipRect;
			Rectangles.MoveRel(rect, -dx, -dy)
		END GetClipRect;
		
		(**  *)
		PROCEDURE SetClipMode*(mode : SET);
		BEGIN
			clipMode := mode
		END SetClipMode;
		
		(** Set color for fonts *)
		PROCEDURE SetColor*(x : Color);
		BEGIN
			color := x
		END SetColor;
	
		(** Set the current font. IF f is NIL, GetFont will search for the system default font. *)
		PROCEDURE SetFont*(f: Font);
		BEGIN
			font := f
		END SetFont;
		
		(** Return the font currently set for this canvas. If no font is set, return the system default font. If no
			system default font is set, block until a default font is set *)
		PROCEDURE GetFont*():Font;
		BEGIN
			IF font = NIL THEN font := GetDefaultFont() END;
			RETURN font
		END GetFont;
		
		(** Draw an UTF8 String at position x, y (base line)
			The currently set font and color is used
		*)
		PROCEDURE DrawString*(x, y: LONGINT; text : ARRAY OF CHAR);
		BEGIN
			IF font # NIL THEN 
				font.RenderString(SELF, x, y, text)
			END	
		END DrawString;
		
		(** draw a line within the current clipping rectangle *)
		(** Override for improved speed *)
		PROCEDURE Line*(x0, y0, x1, y1 : LONGINT; color : Color; mode : LONGINT);
		VAR t, xi, mi, xf, mf, dt2 : LONGINT;
		BEGIN
			IF y0 = y1 THEN (* horizontal case *)
				IF x0 > x1 THEN t := x0; x0 := x1; x1 := t END;
				Fill(Rectangles.MakeRect(x0, y0, x1 + 1, y0 + 1), color, mode)
			ELSIF x0 = x1 THEN (* vertical case *)
				IF y0 > y1 THEN t := y0; y0 := y1; y1 := t END;
				Fill(Rectangles.MakeRect(x0, y0, x0 + 1, y1 + 1), color, mode)
			ELSE (* general case *)
				IF ABS(y1 - y0) > ABS(x1 - x0) THEN
					IF y0 > y1 THEN t := y0; y0 := y1; y1 := t; t := x0; x0 := x1; x1 := t END;
					xi := x0; xf :=  y0 - y1; mi := (x1 - x0) DIV (y1 - y0); mf := 2 * ( (x1 - x0) MOD (y1 - y0)); dt2 := 2 * (y1 - y0);
					FOR t := y0 TO y1 DO
						SetPixel(xi, t, color, mode);
						INC(xi, mi); INC(xf, mf); 
						IF xf > 0 THEN INC(xi); DEC(xf, dt2) END
					END
				ELSE
					IF x0 > x1 THEN t := y0; y0 := y1; y1 := t; t := x0; x0 := x1; x1 := t END;
					xi := y0; xf :=  x0 - x1; mi := (y1 - y0) DIV (x1 - x0); mf := 2 * ( (y1 - y0) MOD (x1 - x0)); dt2 := 2 * (x1 - x0);
					FOR t := x0 TO x1 DO
						SetPixel(t, xi, color, mode);
						INC(xi, mi); INC(xf, mf); 
						IF xf > 0 THEN INC(xi); DEC(xf, dt2) END
					END
				END
			END
		END Line;
		
		(** set a pixel within the current clipping rectangle *)
		PROCEDURE SetPixel*(x, y : LONGINT; color : Color; mode : LONGINT);
		BEGIN
			Fill(MakeRectangle(x, y, x + 1, y + 1), color, mode)
		END SetPixel;
		
		(** fill a rectangle within the current clipping rectangle *)
		PROCEDURE Fill*(rect : Rectangle; color : Color; mode : LONGINT);
		BEGIN
		END Fill;
		
		(** fill a polygon given by points *)
		PROCEDURE FillPolygonFlat*(VAR points : ARRAY OF Point2d; nofPoints : LONGINT; color : Color; mode : LONGINT);
		BEGIN
		END FillPolygonFlat; 
		
		PROCEDURE FillPolygonCB*(VAR points : ARRAY OF Point2d; nofPoints : LONGINT; callBack : FillLineCallBack);
		BEGIN
		END FillPolygonCB;
		
		(** draw an image within the current clipping rectangle *)
		PROCEDURE DrawImage*(x, y: LONGINT; image: Raster.Image; mode : LONGINT);
		BEGIN
		END DrawImage;
		
		PROCEDURE ScaleImage*(src : Raster.Image; sr, dr : Rectangle; copyMode, scaleMode : LONGINT);
		BEGIN
		END ScaleImage; 
		
		(** Set coordinate shift *)
		PROCEDURE SetDelta*(dx, dy: LONGINT);
		BEGIN
			SELF.dx := dx; SELF.dy := dy
		END SetDelta;
		
		(** Set the available range in the super drawing space *)
		PROCEDURE SetLimits*(r : Rectangle);
		BEGIN
			limits := r
		END SetLimits;
		
		(** Get the avalilable range in the super drawing space, like the range set but clipped *)
		PROCEDURE GetLimits*(): Rectangle;
		BEGIN
			RETURN limits
		END GetLimits;
		
	END Canvas;
	
TYPE
	FillPosEntry = RECORD pos, next : LONGINT END;
	FillHeap = POINTER TO ARRAY OF FillPosEntry;
	FillLineCallBack* = PROCEDURE {DELEGATE} (canvas : Canvas; y, x0, x1 : LONGINT);
	
TYPE
	BufferCanvas* = OBJECT(Canvas)
	VAR img : Raster.Image;
			bounds : Rectangle; (* real limiting img bounds *)
		(* filling *)	
			fillHeap : FillHeap;
			heapSize, topHeap : LONGINT;
			height : LONGINT;
			edges : POINTER TO ARRAY OF LONGINT;
		
		PROCEDURE &New(img : Raster.Image);
		BEGIN
			SELF.img := img;
			bounds := MakeRectangle(0, 0, img.width, img.height);
			SetLimits(MakeRectangle(0, 0, img.width, img.height ));
			clipRect := bounds;
			clipMode := { ClipRect };
			SetFont(GetDefaultFont());
			(* filling *)
			height := img.height; NEW(edges, height)
		END New;
		
		PROCEDURE SetLimits*(r : Rectangle);
		BEGIN
			r.r := Max(r.r, r.l); r.b := Max(r.t, r.b);
			Rectangles.ClipRect(r, bounds); SetLimits^(r)
		END SetLimits;
		
	(*	PROCEDURE Line*(x0, y0, x1, y1 : LONGINT; color : Color; mode : LONGINT);
		BEGIN
		END Line; *)
		
		PROCEDURE Fill*(rect : Rectangle; color : Color; mode : LONGINT);
		VAR rm : Raster.Mode; pix : Raster.Pixel;
		BEGIN
			(* convert to super coordinates *)
			Rectangles.MoveRel(rect, dx, dy);
			IF ClipRect IN clipMode THEN Rectangles.ClipRect(rect, clipRect) END;
			Rectangles.ClipRect(rect, limits);

			IF ~Rectangles.RectEmpty(rect) THEN
				Raster.SetRGBA(pix, ((color DIV 65536) DIV 256) MOD 256, (color DIV 65536) MOD 256,
				(color DIV 256) MOD 256, color MOD 256);
											
				IF mode = ModeCopy THEN Raster.InitMode(rm, Raster.srcCopy) ELSE Raster.InitMode(rm, Raster.srcOverDst) END;
				Raster.Fill(SELF.img, rect.l, rect.t, rect.r, rect.b, pix, rm);
			END
		END Fill;
		
		(* Polygon filling *)
		(** fill a polygon given by points *)
		PROCEDURE FillPolygonFlat*(VAR points : ARRAY OF Point2d; nofPoints : LONGINT; color : Color; mode : LONGINT);
		VAR i : LONGINT;
		BEGIN
			IF nofPoints < 3 THEN RETURN END;
			ASSERT(nofPoints <= LEN(points));
			ClearHeap;
	     	FOR i := 1 TO nofPoints - 1 DO AddLine(points[i - 1].x, points[i - 1].y, points[i].x, points[i].y) END;
	     	AddLine(points[nofPoints - 1].x, points[nofPoints - 1].y, points[0].x, points[0].y);
	     	FillFlat(color, mode)
		END FillPolygonFlat;
		
		(** fill a polygon given by points *)
		PROCEDURE FillPolygonCB*(VAR points : ARRAY OF Point2d; nofPoints : LONGINT; callBack : FillLineCallBack);
		VAR i : LONGINT;
		BEGIN
			IF nofPoints < 3 THEN RETURN END;
			ASSERT(nofPoints <= LEN(points));
			ClearHeap;
	     	FOR i := 1 TO nofPoints - 1 DO AddLine(points[i - 1].x, points[i - 1].y, points[i].x, points[i].y) END;
	     	AddLine(points[nofPoints - 1].x, points[nofPoints - 1].y, points[0].x, points[0].y);
	     	FillCB(callBack)
		END FillPolygonCB;
		
	     PROCEDURE ClearHeap;
	     VAR i : LONGINT;
	     BEGIN
	     	topHeap := 0;
	     	FOR i := 0 TO height - 1 DO edges[i] := 0 END;
	     	IF fillHeap = NIL THEN NEW(fillHeap, 1024); heapSize := 1024 END
	     END ClearHeap;
	     
	     PROCEDURE NewFillPos(pos : LONGINT) : LONGINT;
	     VAR newHeap : FillHeap;
	     	i : LONGINT;
	     BEGIN
	     	INC(topHeap);
	     	IF topHeap >= heapSize THEN (* grow heap *)
	     		NEW(newHeap, heapSize * 2);
	     		FOR i := 0 TO heapSize - 1 DO newHeap[i] := fillHeap[i] END;
	     		heapSize := heapSize * 2;
	     		fillHeap := newHeap
	     	END;
	     	fillHeap[topHeap].pos := pos;
	     	fillHeap[topHeap].next := 0;
	     	RETURN topHeap
	     END NewFillPos;
	     
	     PROCEDURE AddIntersection(y, pos : LONGINT);
	     VAR new, cur : LONGINT;
	     BEGIN
	     	IF (y < 0) OR (y >= height) THEN RETURN END;
	     	new := NewFillPos(pos);
	     	IF edges[y] = 0 THEN edges[y] := new 
	     	ELSE
	     		cur := edges[y];
	     		IF fillHeap[cur].pos > pos THEN
	     			fillHeap[new].next := cur;
	     			edges[y] := new
	     		ELSE	
	     			WHILE (fillHeap[cur].next # 0) & (fillHeap[fillHeap[cur].next].pos < pos) DO cur := fillHeap[cur].next END;
	     			fillHeap[new].next := fillHeap[cur].next;
	     			fillHeap[cur].next := new
	     		END;
	     	END;
	     END AddIntersection;
		
	     PROCEDURE AddLine(x0, y0, x1, y1 : LONGINT);
	     VAR t, xi, xf, mi, mf, dt2  : LONGINT ;
	     BEGIN
	    	IF (y0 = y1) THEN RETURN END; 
			IF y0 > y1 THEN t := y0; y0 := y1; y1 := t; t := x0; x0 := x1; x1 := t END;
			xi := x0; xf :=  y0 - y1; mi := (x1 - x0) DIV (y1 - y0); mf := 2 * ( (x1 - x0) MOD (y1 - y0)); dt2 := 2 * (y1 - y0);
			FOR t := y0 TO y1 - 1 DO
				AddIntersection(t, xi);
				INC(xi, mi); INC(xf, mf); 
				IF xf > 0 THEN INC(xi); DEC(xf, dt2) END
			END
	     END AddLine;
	     
	     PROCEDURE FillFlat(color, mode : LONGINT);
	     VAR i, sp, cur : LONGINT;
	     	in : BOOLEAN;
	     BEGIN
	     	FOR i := 0 TO height - 1 DO 
	     		cur := edges[i];
	     		in := FALSE;
     			WHILE cur # 0 DO 
     				in := ~in;
     				IF in THEN sp := fillHeap[cur].pos
     				ELSE Fill(Rectangles.MakeRect(sp, i, fillHeap[cur].pos, i + 1), color, mode)
     				END;
     				cur := fillHeap[cur].next 
     			END
     		END
		END FillFlat;
		
	     PROCEDURE FillCB(cb : FillLineCallBack);
	     VAR i, sp, cur : LONGINT;
	     	in : BOOLEAN;
	     BEGIN
	     	FOR i := 0 TO height - 1 DO 
	     		cur := edges[i];
	     		in := FALSE;
     			WHILE cur # 0 DO 
     				in := ~in;
     				IF in THEN sp := fillHeap[cur].pos
     				ELSE cb(SELF, i, sp, fillHeap[cur].pos)
     				END;
     				cur := fillHeap[cur].next 
     			END
     		END
		END FillCB;
		
		PROCEDURE DrawImage*(x, y: LONGINT; img: Raster.Image; mode : LONGINT);
		VAR imgBounds : Rectangle;
			rm : Raster.Mode;
		BEGIN
			IF img = NIL THEN RETURN END;
			imgBounds := MakeRectangle(0, 0, img.width, img.height);
			
			(* to super coordinates *)
			Rectangles.MoveRel(imgBounds, x + dx, y + dy);
			IF ClipRect IN clipMode THEN Rectangles.ClipRect(imgBounds, clipRect) END;
			Rectangles.ClipRect(imgBounds, limits);
			
			IF ~Rectangles.RectEmpty(imgBounds) THEN
				IF mode = ModeCopy THEN Raster.InitMode(rm, Raster.srcCopy) ELSE Raster.InitMode(rm, Raster.srcOverDst) END;
				Raster.SetRGBA(rm.col, (color DIV 1000000H) MOD 100H, (color DIV 10000H) MOD 100H,
				(color DIV 100H) MOD 100H, color MOD 100H);
				IF imgBounds.l - (x + dx) < 0 THEN 
					AosOut.String("Error...");
					AosOut.String("x + dx = "); AosOut.Int(x + dx, 4); AosOut.Ln;
					AosOut.String("x = "); AosOut.Int(x, 4); AosOut.Ln;
					AosOut.String("dx = "); AosOut.Int(dx, 4); AosOut.Ln;
					AosOut.String("clip = "); AosOut.Int(clipRect.l, 4); AosOut.Int(clipRect.t, 4); 
						AosOut.Int(clipRect.r, 4); AosOut.Int(clipRect.b, 4);AosOut.Ln;
					AosOut.String("imgBounds = "); 
						AosOut.Int(imgBounds.l, 4); AosOut.Int(imgBounds.t, 4); AosOut.Int(imgBounds.r, 4); AosOut.Int(imgBounds.b, 4);AosOut.Ln;
					AosOut.String("limits = "); AosOut.Int(limits.l, 4); AosOut.Int(limits.t, 4); 
						AosOut.Int(limits.r, 4); AosOut.Int(limits.b, 4);AosOut.Ln;
					RETURN	
				END;
				Raster.Copy(img, SELF.img,  imgBounds.l - (x + dx), imgBounds.t - (y + dy), 
					imgBounds.r - imgBounds.l + (imgBounds.l - (x + dx)), imgBounds.b - imgBounds.t + (imgBounds.t - (y + dy)), 
					imgBounds.l, imgBounds.t, rm);
			END;
		END DrawImage;
		
		PROCEDURE ScaleImage*(src : Raster.Image; sr , dr : Rectangle; copyMode, scaleMode : LONGINT);
		BEGIN
			Rectangles.MoveRel(dr, dx, dy);
			RasterScale.Scale(src, sr, img, dr, clipRect, copyMode, scaleMode);
		END ScaleImage;
		
	END BufferCanvas;
	

VAR imgCache : AosKernel.FinalizedCollection;
	searchName : ARRAY 128 OF CHAR;
	foundImg : Image;
	
	defaultFont : Font;
	fontManager : FontManager;
	fallbackFonts* : ARRAY 5 OF Font;
	nofFallbackFonts : LONGINT;
	
CONST 
	AlignLeft* = 0; AlignCenter* = 1; AlignRight* = 2;
	AlignTop* = 0; AlignBottom* = 2;
		
PROCEDURE Min(a, b:LONGINT):LONGINT;
BEGIN
	IF a<b THEN RETURN a ELSE RETURN b END
END Min;

PROCEDURE Max(a, b:LONGINT):LONGINT;
BEGIN
	IF a>b THEN RETURN a ELSE RETURN b END
END Max;

(* Tool Functions *)
PROCEDURE MakeRectangle*(l, t, r, b: LONGINT):Rectangle;
VAR result : Rectangle;
BEGIN
	result.l := l; result.t := t; result.r := r; result.b := b; RETURN result
END MakeRectangle;

PROCEDURE ColorToRGBA*(color : Color; VAR r, g, b, a : LONGINT);
BEGIN
	r := (color DIV 1000000H) MOD 100H;
	g := (color DIV 10000H) MOD 100H;
	b := (color DIV 100H) MOD 100H;
	a :=  color MOD 100H
END ColorToRGBA;

PROCEDURE RGBAToColor*(r, g, b, a: LONGINT): Color;
BEGIN
	RETURN r * 1000000H + g * 10000H + b * 100H + a
END RGBAToColor;

PROCEDURE CheckImage(obj: PTR; VAR cont: BOOLEAN);
BEGIN
	IF obj IS Image THEN
		IF obj(Image).key # NIL THEN 
			IF obj(Image).key^ = searchName THEN 
				foundImg := obj(Image);
				cont := FALSE
			END
		END
	END
END CheckImage;

(** loads an image and returns a BGRA8888 bitmap if successful, NIL otherwise. 
	If shared is TRUE, the image will not be reloaded if it is already in memory. 
*)
PROCEDURE LoadImage*(name : ARRAY OF CHAR; shared : BOOLEAN): Image;
VAR img, fix : Image; done : BOOLEAN; mode : Raster.Mode;
BEGIN {EXCLUSIVE}
	IF shared THEN
		foundImg := NIL; COPY(name, searchName);
		imgCache.Enumerate(CheckImage);
		IF foundImg # NIL THEN RETURN foundImg END
	END;

	NEW(img); Raster.Load(img, name, done);
	IF ~done THEN img := NIL 
	ELSE
		IF img.fmt.code # Raster.BGRA8888.code THEN 
			NEW(fix); Raster.Create(fix, img.width, img.height, Raster.BGRA8888);
			Raster.InitMode(mode, Raster.srcCopy);
			Raster.Copy(img, fix, 0, 0, img.width, img.height, 0, 0, mode);
			img := fix
		END;
		NEW(img.key, LEN(name)); COPY(name, img.key^);
		IF shared THEN imgCache.Add(img, NIL) END
	END;
	RETURN img
END LoadImage;

(** Draw an UTF8 String in a rectangle *)
PROCEDURE DrawStringInRect*(canvas : Canvas; rect : Rectangle; wrap : BOOLEAN; hAlign, vAlign : LONGINT; text : 
	ARRAY OF CHAR);
VAR tw, th, xPos, yPos : LONGINT;
	font : Font;
BEGIN
	font := canvas.GetFont(); 
	IF font # NIL THEN
		font.GetStringSize(text, tw, th);
	END;	
	xPos := rect.l; yPos := rect.t + font.GetAscent();
	IF ~wrap THEN
		IF hAlign = AlignCenter THEN xPos := ((rect.l + rect.r) - tw) DIV 2
		ELSIF hAlign = AlignRight THEN xPos := rect.r - tw
		END;
		IF vAlign = AlignCenter THEN yPos := ((rect.t + rect.b) + th - font.GetDescent()) DIV 2
		ELSIF vAlign = AlignBottom THEN yPos := rect.b - th DIV 2
		END;
		canvas.DrawString(xPos, yPos, text)
	ELSE
		(* not implemented *)
	END
END DrawStringInRect;

PROCEDURE InstallDefaultFont*(f : Font);
BEGIN { EXCLUSIVE }
	defaultFont := f;
	fallbackFonts[0] := defaultFont
END InstallDefaultFont;

PROCEDURE GetDefaultFont*() : Font;
BEGIN { EXCLUSIVE }
	AWAIT(defaultFont # NIL);
	RETURN defaultFont
END GetDefaultFont;

PROCEDURE InstallFontManager*(fm : FontManager);
BEGIN { EXCLUSIVE }
	fontManager := fm;
	IF fontManager # NIL THEN
		fallbackFonts[1] := fontManager.GetFont("Single", 20, {});	
	END	
END InstallFontManager;

PROCEDURE GetFont*(name : ARRAY OF CHAR; size : LONGINT; style : SET) : Font;
VAR f : Font;
BEGIN { EXCLUSIVE }
	f := NIL;
	IF fontManager # NIL THEN f := fontManager.GetFont(name, size, style) END;
	IF f = NIL THEN AWAIT(defaultFont # NIL); f := defaultFont END;
	RETURN f
END GetFont;

(** Render the fallback case of the character char to canvas at x, y (baseline) *)
PROCEDURE FBRenderChar*(canvas : Canvas ; x, y : REAL; char : Char32); 
VAR i, w, h : LONGINT; f : Font; found : BOOLEAN; str : ARRAY 16 OF CHAR; r: Rectangles.Rectangle;
BEGIN
	i := 0; found := FALSE;
	WHILE ~found & (i < nofFallbackFonts) DO
		f := fallbackFonts[i];
		IF (f # NIL) & f.HasChar(char) THEN found := TRUE END;
		INC(i)
	END;
	IF f # NIL THEN f.RenderChar(canvas, x, y, char) 
	ELSE
		f := GetDefaultFont();
		Utilities.IntToStr(char,str); Utilities.Concat("U", str, str);
		f.GetStringSize(str, w, h);
		r := Rectangles.MakeRect(ENTIER(x), ENTIER(y) - f.ascent, ENTIER(x) + w, ENTIER(y) + f.descent);
		canvas.Fill(r, 0CCCC00FFH, ModeCopy);
		f.RenderString(canvas, x, y, str)
	END
END FBRenderChar;

(** return the fallback spacing of character code *)
PROCEDURE FBGetGlyphSpacings*(code : LONGINT; VAR glyphSpacings : GlyphSpacings);
VAR i : LONGINT; f : Font; found : BOOLEAN; str : ARRAY 16 OF CHAR;
BEGIN
	i := 0; found := FALSE;
	WHILE ~found & (i < nofFallbackFonts) DO
		f := fallbackFonts[i];
		IF (f # NIL) & f.HasChar(code) THEN found := TRUE END;
		INC(i)
	END;
	IF f # NIL THEN f.GetGlyphSpacings(code, glyphSpacings) 
	ELSE
		f := GetDefaultFont();
		Utilities.IntToStr(code, str); Utilities.Concat("U", str, str);
		glyphSpacings.bearing := Rectangles.MakeRect(0, 0, 0, 0);
		f.GetStringSize(str, glyphSpacings.width, glyphSpacings.height);
		glyphSpacings.ascent := f.ascent; glyphSpacings.descent := f.descent;
		glyphSpacings.dx := 0; glyphSpacings.dy := 0
	END
END FBGetGlyphSpacings;

(** Tools *)
(* Return true if the alpha value at pos x, y in img is >= threshold. Returns false if x, y are out of image *)
PROCEDURE IsBitmapHit*(x, y, threshold: LONGINT; img: Raster.Image) : BOOLEAN;
VAR pix : Raster.Pixel;
		mode : Raster.Mode;
BEGIN
	IF (img # NIL) & (x >= 0) & (y >= 0) & (x < img.width) & (y < img.height) THEN
		Raster.InitMode(mode, Raster.srcCopy);
		Raster.Get(img, x, y, pix, mode);
		RETURN (ORD(pix[Raster.a]) >= threshold)
	ELSE RETURN FALSE
	END
END IsBitmapHit;

BEGIN
 	nofFallbackFonts := 3;
	NEW(imgCache)
END WMGraphics.
