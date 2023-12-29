MODULE WMGraphicUtilities;	(** AUTHOR "TF"; PURPOSE "Tools using WMGraphics"; *)

IMPORT
	WMGraphics, WMRectangles, Utilities;
	
(* factor in 1/256, alpha remains unchanged *)
PROCEDURE ScaleColor*(color : LONGINT; factor : LONGINT): LONGINT;	
VAR r, g, b, a : LONGINT;
BEGIN
	WMGraphics.ColorToRGBA(color, r, g, b, a);
	r := Utilities.Min(r * factor DIV 256, 255); 
	g := Utilities.Min(g * factor DIV 256, 255);
	b := Utilities.Min(b * factor DIV 256, 255);
	RETURN WMGraphics.RGBAToColor(r, g, b, a)
END ScaleColor;

(** linear interpolation percent in [0..256] *)
PROCEDURE InterpolateLinear*(a, b, percent : LONGINT) : LONGINT;
BEGIN
	RETURN ((a * (256 - percent)) + b * percent) DIV 256
END InterpolateLinear;

(* interpolate between two colors; percent [0..256]*)
PROCEDURE InterpolateColorLinear*(cl0, cl1, percent : LONGINT) : LONGINT;
VAR r0, g0, b0, a0, r1, g1, b1, a1: LONGINT;
BEGIN
	WMGraphics.ColorToRGBA(cl0, r0, g0, b0, a0);
	WMGraphics.ColorToRGBA(cl1, r1, g1, b1, a1);
	RETURN WMGraphics.RGBAToColor(InterpolateLinear(r0, r1, percent), 
			InterpolateLinear(g0, g1, percent), 
			InterpolateLinear(b0, b1, percent), 
			InterpolateLinear(a0, a1, percent))
END InterpolateColorLinear;

(** Draw a 3d effect border *)
PROCEDURE DrawBevel*(canvas : WMGraphics.Canvas; rect : WMRectangles.Rectangle; borderWidth : LONGINT; down : BOOLEAN; color, mode : LONGINT);
VAR i, ul, dr : LONGINT;
BEGIN
	IF down THEN ul := ScaleColor(color, 128); dr :=  ScaleColor(color, 256 + 128)
	ELSE dr := ScaleColor(color, 128); ul :=  ScaleColor(color, 256 + 128)
	END;
	FOR i := 0 TO borderWidth - 1 DO
		canvas.Fill(WMRectangles.MakeRect(rect.l + i , rect.t + i, rect.r - i, rect.t + i + 1), ul, mode);
		canvas.Fill(WMRectangles.MakeRect(rect.l + i, rect.t + i + 1, rect.l + i + 1, rect.b - i), ul, mode);
		canvas.Fill(WMRectangles.MakeRect(rect.l + 1 + i, rect.b - 1 - i, rect.r - i, rect.b - i), dr, mode);
		canvas.Fill(WMRectangles.MakeRect(rect.r - 1 - i, rect.t + 1 + i, rect.r - i, rect.b - i - 1), dr, mode)
	END	
END DrawBevel;

(** Draw a 3d effect panel *)
PROCEDURE DrawBevelPanel*(canvas : WMGraphics.Canvas; rect : WMRectangles.Rectangle; borderWidth : LONGINT; down : BOOLEAN; color, mode : LONGINT);
BEGIN
	canvas.Fill(WMRectangles.ResizeRect(rect, -1), color, mode);
	DrawBevel(canvas, rect, borderWidth, down, color, mode)
END DrawBevelPanel;

PROCEDURE FillGradientHorizontal*(canvas : WMGraphics.Canvas; rect : WMRectangles.Rectangle; clLeft, clRight, mode : LONGINT);
VAR dist, cl, i, f : LONGINT;
BEGIN
	dist := rect.r - rect.l;
	FOR i := 0 TO dist - 1 DO
		f := ENTIER(256 * i / dist); 
		cl := InterpolateColorLinear(clLeft, clRight, f);
		canvas.Fill(WMRectangles.MakeRect(rect.l + i, rect.t, rect.l + i + 1, rect.b), cl, mode)
	END;
END FillGradientHorizontal;

PROCEDURE FillGradientVertical*(canvas : WMGraphics.Canvas; rect : WMRectangles.Rectangle; clTop, clBottom, mode : LONGINT);
VAR dist, cl, i, f : LONGINT;
BEGIN
	dist := rect.b - rect.t;
	FOR i := 0 TO dist - 1 DO
		f := ENTIER(256 * i / dist); 
		cl := InterpolateColorLinear(clTop, clBottom, f);
		canvas.Fill(WMRectangles.MakeRect(rect.l, rect.t + i, rect.r, rect.t + i + 1), cl, mode)
	END;
END FillGradientVertical;

PROCEDURE FillRoundHorizontalBar*(canvas : WMGraphics.Canvas; rect : WMRectangles.Rectangle; down : BOOLEAN; color, mode : LONGINT);
VAR cl2, d : LONGINT;
BEGIN
	cl2 := ScaleColor(color, 200);
	IF down THEN d := (rect.b - rect.t) * 5 DIV 16;
	ELSE d := (rect.b - rect.t) * 11 DIV 16	
	END;	
	FillGradientVertical(canvas, WMRectangles.MakeRect(rect.l, rect.t, rect.r, rect.t + d), color, cl2, WMGraphics.ModeCopy);
	FillGradientVertical(canvas, WMRectangles.MakeRect(rect.l, rect.t + d, rect.r, rect.b), cl2, color, WMGraphics.ModeCopy);
END FillRoundHorizontalBar;

PROCEDURE FillRoundVerticalBar*(canvas : WMGraphics.Canvas; rect : WMRectangles.Rectangle; down : BOOLEAN; color, mode : LONGINT);
VAR cl2, d : LONGINT;
BEGIN
	cl2 := ScaleColor(color, 200);
	IF down THEN d := (rect.r - rect.l) * 5 DIV 16;
	ELSE d := (rect.r - rect.l) * 11 DIV 16	
	END;	
	FillGradientHorizontal(canvas, WMRectangles.MakeRect(rect.l, rect.t, rect.l + d, rect.b), color, cl2, WMGraphics.ModeCopy);
	FillGradientHorizontal(canvas, WMRectangles.MakeRect(rect.l + d, rect.t, rect.r, rect.b), cl2, color, WMGraphics.ModeCopy);
END FillRoundVerticalBar;

PROCEDURE DrawRect*(canvas : WMGraphics.Canvas; r : WMRectangles.Rectangle; color : WMGraphics.Color; mode : LONGINT);
BEGIN
	canvas.Fill(WMRectangles.MakeRect(r.l, r.t, r.r, r.t + 1), color, mode);
	canvas.Fill(WMRectangles.MakeRect(r.l, r.t, r.l + 1, r.b), color, mode);
	canvas.Fill(WMRectangles.MakeRect(r.l, r.b - 1, r.r, r.b), color, mode);
	canvas.Fill(WMRectangles.MakeRect(r.r - 1, r.t, r.r, r.b), color, mode)
END DrawRect;

PROCEDURE RectGlassShade*(canvas : WMGraphics.Canvas; rect : WMRectangles.Rectangle; borderWidth : LONGINT; down : BOOLEAN);
VAR i, ul, dr, da, w : LONGINT;
BEGIN
	IF borderWidth <= 0 THEN RETURN END;
	IF down THEN ul := 090H; dr := 0FFFFFF90H 
	ELSE dr := 090H; ul := 0FFFFFF90H
	END;
	da := 90H DIV borderWidth;
	FOR i := 0 TO borderWidth - 1 DO
		(* top *)
		canvas.Fill(WMRectangles.MakeRect(rect.l + i , rect.t + i, rect.r - i, rect.t + i + 1), ul, WMGraphics.ModeSrcOverDst);
		(* left *)
		canvas.Fill(WMRectangles.MakeRect(rect.l + i, rect.t + i + 1, rect.l + i + 1, rect.b - i), ul, WMGraphics.ModeSrcOverDst);
		(* bottom *)
		canvas.Fill(WMRectangles.MakeRect(rect.l + 1 + i, rect.b - 1 - i, rect.r - i, rect.b - i), dr, WMGraphics.ModeSrcOverDst);
		(* right *)
		canvas.Fill(WMRectangles.MakeRect(rect.r - 1 - i, rect.t + 1 + i, rect.r - i, rect.b - i - 1), dr, WMGraphics.ModeSrcOverDst);
		DEC(ul, da); DEC(dr, da)
	END;
	i := 3; ul := 0FFFFFF40H; w := 5;
	canvas.Fill(WMRectangles.MakeRect(rect.l + i , rect.t + i, rect.l + i + w, rect.t + i + 2), ul, WMGraphics.ModeSrcOverDst);
	canvas.Fill(WMRectangles.MakeRect(rect.l + i, rect.t + i, rect.l + i + 2, rect.t + i + w), ul, WMGraphics.ModeSrcOverDst);
END RectGlassShade;



PROCEDURE ExtRectGlassShade*(canvas : WMGraphics.Canvas; rect : WMRectangles.Rectangle; openSides : SET; borderWidth : LONGINT; down : BOOLEAN);
VAR i, ul, dr, da, w, a, b, c, d : LONGINT;
BEGIN
	IF borderWidth <= 0 THEN RETURN END;
	IF down THEN ul := 090H; dr := 0FFFFFF90H 
	ELSE dr := 090H; ul := 0FFFFFF90H
	END;
	da := 90H DIV borderWidth;
	FOR i := 0 TO borderWidth - 1 DO
		IF  (0 IN openSides) THEN a := 0 ELSE a := i END;
		IF  (1 IN openSides) THEN b := 0 ELSE b := i + 1 END;
		IF  (2 IN openSides) THEN c := 0 ELSE c := i END;
		IF  (3 IN openSides) THEN d := 0 ELSE d := i + 1 END;
		(* top *)
		IF ~(0 IN openSides) THEN canvas.Fill(WMRectangles.MakeRect(rect.l + b , rect.t + i, rect.r - d, rect.t + i + 1), ul, WMGraphics.ModeSrcOverDst) END;
		(* left *)
		IF ~(1 IN openSides) THEN canvas.Fill(WMRectangles.MakeRect(rect.l + i, rect.t + a, rect.l + i + 1, rect.b - c), ul, WMGraphics.ModeSrcOverDst) END;
		(* bottom *)
		IF ~(2 IN openSides) THEN canvas.Fill(WMRectangles.MakeRect(rect.l + b, rect.b - 1 - i, rect.r - d, rect.b - i), dr, WMGraphics.ModeSrcOverDst) END;
		(* right *)
		IF ~(3 IN openSides) THEN canvas.Fill(WMRectangles.MakeRect(rect.r - 1 - i, rect.t + a, rect.r - i, rect.b - c), dr, WMGraphics.ModeSrcOverDst) END;
		DEC(ul, da); DEC(dr, da)
	END;
	i := 3; ul := 0FFFFFF40H; w := 5;
(*	canvas.Fill(WMRectangles.MakeRect(rect.l + i , rect.t + i, rect.l + i + w, rect.t + i + 2), ul, WMGraphics.ModeSrcOverDst);
	canvas.Fill(WMRectangles.MakeRect(rect.l + i, rect.t + i, rect.l + i + 2, rect.t + i + w), ul, WMGraphics.ModeSrcOverDst);
*)
END ExtRectGlassShade;	

END WMGraphicUtilities.
