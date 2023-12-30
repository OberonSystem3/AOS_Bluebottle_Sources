MODULE WMProgressComponents; (** AUTHOR: "staubesv"; PURPOSE: "Progress indication components and windows"; *)

IMPORT
	AosModules, Utilities,
	WMComponents, WMProperties, WMRectangles, WMGraphics;
	
TYPE

	ProgressBar* = OBJECT(WMComponents.VisualComponent)
	VAR
		start-, end-, cur-: WMProperties.Int32Property;
		
		color-: WMProperties.ColorProperty;
		borderColor-: WMProperties.ColorProperty;
		textColor- : WMProperties.ColorProperty;
		
		showPercents- : WMProperties.BooleanProperty; (* Default: TRUE *)
				
		PROCEDURE &Init;
		BEGIN
			Init^;
			takesFocus.Set(FALSE);
			NEW(color, PrototypePbColor, NIL, NIL); properties.Add(color);
			NEW(borderColor, PrototypePbBorderColor, NIL, NIL); properties.Add(borderColor);
			NEW(start, PrototypePbStart, NIL, NIL); properties.Add(start);
			NEW(end, PrototypePbEnd, NIL, NIL); properties.Add(end);
			NEW(cur, PrototypePbCur, NIL, NIL); properties.Add(cur);
			NEW(showPercents, PrototypePbShowPercents, NIL, NIL); properties.Add(showPercents);
			NEW(textColor, PrototypePbTextColor, NIL, NIL); properties.Add(textColor);
			SetNameAsString(Utilities.NewString("ProgressBar"));
		END Init;
		
		PROCEDURE SetRange*(start, end : LONGINT);
		BEGIN
			Acquire;
			SELF.start.Set(start);
			SELF.end.Set(end);
			Release;
		END SetRange;
		
		PROCEDURE IncPos*();
		BEGIN
			Acquire;
			cur.Set(cur.Get() + 1);
			Release;
		END IncPos;
		
		PROCEDURE PropertyChanged*(sender, property : ANY);
		BEGIN
			IF (property = start) OR (property = end) THEN
				cur.SetBounds(start.Get(), end.Get());
				Invalidate;
			ELSIF (property = cur) OR (property = color) OR (property = borderColor) OR (property = textColor) OR 
				 	(property = showPercents) THEN
				Invalidate;
			ELSE PropertyChanged^(sender, property)
			END;
		END PropertyChanged;
		
		PROCEDURE DrawBackground*(canvas: WMGraphics.Canvas);
		VAR
			rect: WMRectangles.Rectangle;
			width: LONGINT;
			pt: ARRAY 4 OF WMGraphics.Point2d;
			number, string : ARRAY 32 OF CHAR;
			start, end, cur, percent : LONGINT;
		BEGIN
			start := SELF.start.Get();
			end := SELF.end.Get();
			cur := SELF.cur.Get();
			
			DrawBackground^(canvas);
			IF end > start THEN
				width := ENTIER((cur-start) / (end - start) * bounds.GetWidth());
			END;
			rect := WMRectangles.MakeRect(0, 0, width, bounds.GetHeight());
			
			canvas.Fill(rect, color.Get(), WMGraphics.ModeCopy);
			
			rect := GetClientRect();
			rect.l := width;
			canvas.Fill(rect, fillColor.Get(), WMGraphics.ModeCopy);
			
			pt[0].x := 0; pt[0].y := 0;
			pt[1].x := bounds.GetWidth()-1; pt[1].y := 0;
			pt[2].x := bounds.GetWidth()-1; pt[2].y := bounds.GetHeight()-1;
			pt[3].x := 0; pt[3].y := bounds.GetHeight()-1;
			canvas.PolyLine(pt, 4, TRUE, borderColor.Get(), WMGraphics.ModeCopy);
		
			IF showPercents.Get() & (end - start > 0) THEN
				percent := ENTIER(100 * (cur - start) / (end - start)); Utilities.IntToStr(percent, string); Utilities.Append(string, "%");
				canvas.SetColor(textColor.Get());
				WMGraphics.DrawStringInRect(canvas, GetClientRect(), FALSE, WMGraphics.AlignCenter, WMGraphics.AlignCenter, string)
			END;
		END DrawBackground;
		
	END ProgressBar;
	
VAR

	(** ProgressBar property prototypes *)
	PrototypePbStart*, PrototypePbEnd*, PrototypePbCur* : WMProperties.Int32Property;
	PrototypePbColor*, PrototypePbBorderColor* : WMProperties.ColorProperty;
	PrototypePbShowPercents* : WMProperties.BooleanProperty;
	PrototypePbTextColor* : WMProperties.ColorProperty;
	
	 (* temporary prototype-prototypes *)
	 ColorPrototype : WMProperties.ColorProperty; 
	 BooleanPrototype : WMProperties.BooleanProperty;
	 StringPrototype : WMProperties.StringProperty;
	 Int32Prototype : WMProperties.Int32Property;
	 RectanglePrototype : WMProperties.RectangleProperty;
 	 
PROCEDURE GenProgressBar*(par : ANY) : ANY;
VAR pb : ProgressBar;
BEGIN NEW(pb); RETURN pb
END GenProgressBar;

PROCEDURE InitPrototypes;
VAR plProgressBar : WMProperties.PropertyList;
BEGIN
	(* ProgressBar properties *)
	NEW(plProgressBar); WMComponents.propertyListList.Add("ProgressBar", plProgressBar);
	(* colors *)
	NEW(ColorPrototype, NIL, Utilities.NewString("BorderColor"), Utilities.NewString("Progressbar Border Color")); ColorPrototype.Set(WMGraphics.White);
	NEW(PrototypePbBorderColor, ColorPrototype, NIL, NIL); plProgressBar.Add(PrototypePbBorderColor);
	NEW(ColorPrototype, NIL, Utilities.NewString("Color"), Utilities.NewString("Progressbar Color")); ColorPrototype.Set(WMGraphics.Blue);
	NEW(PrototypePbColor, ColorPrototype, NIL, NIL); plProgressBar.Add(PrototypePbColor);
	NEW(ColorPrototype, NIL, Utilities.NewString("TextColor"), Utilities.NewString("Progressbar Text Color")); ColorPrototype.Set(WMGraphics.White);
	NEW(PrototypePbTextColor, ColorPrototype, NIL, NIL); plProgressBar.Add(PrototypePbTextColor);	
	(* position *)	
	NEW(Int32Prototype, NIL, Utilities.NewString("Start"), Utilities.NewString("Progressbar Start Position")); Int32Prototype.Set(0);
	NEW(PrototypePbStart, Int32Prototype, NIL, NIL); plProgressBar.Add(PrototypePbStart);
	NEW(Int32Prototype, NIL, Utilities.NewString("End"), Utilities.NewString("Progressbar End Position")); Int32Prototype.Set(0);
	NEW(PrototypePbEnd, Int32Prototype, NIL, NIL); plProgressBar.Add(PrototypePbEnd);
	NEW(Int32Prototype, NIL, Utilities.NewString("Cur"), Utilities.NewString("Progressbar Current Position")); Int32Prototype.Set(0);
	NEW(PrototypePbCur, Int32Prototype, NIL, NIL); plProgressBar.Add(PrototypePbCur);
	(* other *)
	NEW(BooleanPrototype, NIL, Utilities.NewString("ShowPercents"), Utilities.NewString("Should the progress also be displayed in percent?")); BooleanPrototype.Set(TRUE);
	NEW(PrototypePbShowPercents, BooleanPrototype, NIL, NIL); plProgressBar.Add(PrototypePbShowPercents);
END InitPrototypes;

PROCEDURE Register;
BEGIN
	WMComponents.registry.RegisterElement("ProgressBar", GenProgressBar);
END Register;

PROCEDURE Cleanup;
BEGIN
	WMComponents.registry.UnregisterElement("ProgressBar");
END Cleanup;

BEGIN
	InitPrototypes;
	Register;
	AosModules.InstallTermHandler(Cleanup)
END WMProgressComponents.
