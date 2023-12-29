MODULE WMDiagramComponents;	(** AUTHOR "TF"; PURPOSE "Diagram components"; *)

IMPORT
	AosActive, Utilities, WMRectangles, WMGraphics, WMMessages, WMEvents, WMProperties, AosOut, 
	WMComponents, WMStandardComponents, WMWindowManager, AosModules,
	AosRandom, WMGraphicUtilities;

TYPE
	PerfViewPanel* = OBJECT(WMComponents.VisualComponent)
	VAR model- : PerfMonModel;
		min-, max-, deltax-, deltaXGrid-, deltaXGridSmall-, glassShade-, valueWidth- : WMProperties.Int32Property;
		color-, gridColor- : WMProperties.ColorProperty;
		autoMin-, autoMax-: WMProperties.BooleanProperty;
		unit- : WMProperties.StringProperty;
		showValues- : WMProperties.BooleanProperty;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(model, 1024);
			NEW(min, PrototypeMin, NIL, NIL); properties.Add(min);	
			NEW(max, PrototypeMax,  NIL, NIL); properties.Add(max);	
			NEW(deltax, PrototypeDeltax,  NIL, NIL); properties.Add(deltax);	
			NEW(deltaXGrid, PrototypeDeltaXGrid,  NIL, NIL); properties.Add(deltaXGrid);	
			NEW(deltaXGridSmall, PrototypeDeltaXGridSmall,  NIL, NIL); properties.Add(deltaXGridSmall);	
			NEW(color, PrototypeColor,  NIL, NIL); properties.Add(color);	
			NEW(gridColor, PrototypeGridColor,  NIL, NIL); properties.Add(gridColor);	
			NEW(glassShade, PrototypeGlassShade,  NIL, NIL); properties.Add(glassShade);
			NEW(valueWidth, PrototypeValueWidth,  NIL, NIL); properties.Add(valueWidth);
			NEW(autoMin, PrototypeAutoMin,  NIL, NIL); properties.Add(autoMin);	
			NEW(autoMax, PrototypeAutoMax,  NIL, NIL); properties.Add(autoMax);
			NEW(showValues, PrototypeShowValues,  NIL, NIL); properties.Add(showValues);
			NEW(unit, PrototypeUnit,  NIL, NIL); properties.Add(unit);
			
			SetFont(WMGraphics.GetFont("Oberon", 8, {}));
			model.onChanged.Add(Update)			
		END Init;
	
		PROCEDURE Update(sender, data : ANY);
		BEGIN
			Invalidate
		END Update;
		
		(* find the max and min value in the model dataset. model lock must be held *)
		PROCEDURE FindMinMax(from, len : LONGINT; VAR min, max : REAL);
		VAR i : LONGINT; first : BOOLEAN;
			v : REAL;
		BEGIN
			ASSERT((from >= 0) & (len > 0) & (from + len < model.GetNofPoints()));
			i := from; 
			
			v := model.GetPointValue(i); INC(i); DEC(len);
			min := v; max := v;
			
			WHILE len > 0 DO
				v := model.GetPointValue(i);
				min := RMin(min, v); max := RMax(max, v);
				INC(i); DEC(len)
			END
		END FindMinMax;
		
		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR from, w, h, i, x, v0, v1, virtp, dx, dxgrid, dxgrids, t : LONGINT;
			nofVisible : LONGINT;
			tmin, tmax : REAL;
			col, gcol, gcolhalf, yborder : LONGINT;
			str : ARRAY 16 OF CHAR;
			s : Utilities.String;
			
			PROCEDURE Scale(x : REAL) : LONGINT;
			VAR f : REAL; 
			BEGIN
				IF (tmax - tmin) = 0 THEN f := 1 ELSE f := 1 / (tmax - tmin) END;
				RETURN ENTIER(((x - tmin) * f) * (h - 2 * yborder))
			END Scale;
			
			
		BEGIN
			canvas.SetFont(GetFont());
			yborder := 5;
			model.Acquire;
			IF fillColor.Get() # 0 THEN canvas.Fill(GetClientRect(), fillColor.Get(), WMGraphics.ModeCopy) END;
			col := color.Get();
			gcol := gridColor.Get();
			gcolhalf := WMGraphicUtilities.ScaleColor(gcol, 80H);
			w := bounds.GetWidth(); h := bounds.GetHeight();
			IF showValues.Get() THEN DEC(w, valueWidth.Get()) END;
			dx := deltax.Get();
			dxgrid := deltaXGrid.Get(); dxgrids := deltaXGridSmall.Get();
			i := model.GetNofPoints() - 1;
			virtp := model.viewSampleCount;
			nofVisible := Utilities.Min(i, w DIV dx + 1);
			
			canvas.Line(0, yborder, w, yborder, gcolhalf, WMGraphics.ModeSrcOverDst);
			canvas.Line(0, h - yborder, w, h - yborder, gcolhalf, WMGraphics.ModeSrcOverDst);
			

			IF dxgrids > 0 THEN
				t := w - (virtp MOD dxgrids) * dx;
				WHILE t > 0 DO
					canvas.Line(t, 0, t, h, gcolhalf, WMGraphics.ModeSrcOverDst);
					DEC(t, dx* dxgrids)
				END
			END;

			IF dxgrid > 0 THEN
				t := w - (virtp MOD dxgrid) * dx;
				IF virtp MOD dxgrid = 0 THEN model.viewSampleCount := 0 END;
				WHILE t > 0 DO
					canvas.Line(t, 0, t, h, gcol, WMGraphics.ModeSrcOverDst);
					DEC(t, dx* dxgrid)
				END
			END;

			IF nofVisible >= 2 THEN
				FindMinMax(i - nofVisible, nofVisible, tmin, tmax);
				IF ~autoMin.Get() THEN tmin := min.Get() END;
				IF ~autoMax.Get() THEN tmax := max.Get() END;

				x := w;
				v0 := Scale(model.GetPointValue(i));
				DEC(i);
				WHILE (i > 0) & (x >= 0) DO
					v1 := v0;
					v0 := Scale(model.GetPointValue(i));
					canvas.Line(x - dx, (h - yborder) - v0, x, (h - yborder) - v1, col, WMGraphics.ModeCopy);
					x := x - dx;
					DEC(i);
				END;
			END;
			model.Release;
			
			IF showValues.Get() THEN
				canvas.Fill(WMRectangles.MakeRect(w, 0, w + 4, h), 080H, WMGraphics.ModeSrcOverDst);
				canvas.SetColor(col);
				Utilities.FloatToStr(tmax, 0, 1, 0, str); canvas.DrawString(w + 5, 8 + 5, str);
				Utilities.FloatToStr(tmin, 0, 1, 0, str); canvas.DrawString(w + 5, h - 5, str);
				s := unit.Get();
				IF s # NIL THEN canvas.DrawString(w + 10, h DIV 2 + 4, s^) END
			END;
			IF glassShade.Get() # 0 THEN
				WMGraphicUtilities.RectGlassShade(canvas, GetClientRect(), glassShade.Get(), FALSE)
			END	
		END DrawBackground;

	END PerfViewPanel;
	
	DataPointModel = OBJECT
	VAR
		lockedBy : PTR;
		lockLevel : LONGINT;
		viewChanged : BOOLEAN;
		onChanged- : WMEvents.EventSource; (** does not hold the lock, if called *)
		
		PROCEDURE &New;
		BEGIN
			NEW(onChanged, SELF, WMComponents.NewString("DataPointModelChanged"), NIL, NIL);
			lockLevel :=0 
		END New;
		
		(** acquire a read/write lock on the object *)
		PROCEDURE Acquire*;
		VAR me : PTR;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			IF lockedBy = me THEN
				ASSERT(lockLevel # -1);	(* overflow *)
				INC(lockLevel)
			ELSE
				AWAIT(lockedBy = NIL); viewChanged := FALSE;
				lockedBy := me; lockLevel := 1
			END
		END Acquire;
		
		(** release the read/write lock on the object *)
		PROCEDURE Release*;
		VAR hasChanged : BOOLEAN;
		BEGIN 
			BEGIN {EXCLUSIVE}
				ASSERT(lockedBy = AosActive.ActiveObject(), 3000);
				hasChanged := FALSE;
				DEC(lockLevel);
				IF lockLevel = 0 THEN lockedBy := NIL; hasChanged := viewChanged END
			END;
			IF hasChanged THEN onChanged.Call(NIL) END
		END Release;
		
		PROCEDURE GetNofPoints*() : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			RETURN 0
		END GetNofPoints;
		
		PROCEDURE GetPointValue*(i : LONGINT) : REAL;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);	
			RETURN 0.0
		END GetPointValue;
				
	END DataPointModel;
	
	PerfMonModel* = OBJECT(DataPointModel)
	VAR bufSize : LONGINT;
		buffer : POINTER TO ARRAY OF REAL;
		nofItems : LONGINT;
		pos : LONGINT;
		viewSampleCount* : LONGINT;
	
		PROCEDURE &Init(bufSize : LONGINT);
		BEGIN
			New;
			SELF.bufSize := bufSize;
			NEW(buffer, bufSize);
			nofItems := 0; pos := 0;
			viewSampleCount := 0; 
		END Init;
	
		PROCEDURE Put*(value : REAL);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);		
			IF nofItems < bufSize THEN INC(nofItems) END;
			buffer[pos] := value;
			pos := (pos + 1) MOD bufSize;
			INC(viewSampleCount);
			viewChanged := TRUE
		END Put;

		PROCEDURE GetNofPoints*() : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);		
			RETURN nofItems
		END GetNofPoints;
		
		PROCEDURE GetPointValue*(i : LONGINT) : REAL;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);	
			RETURN buffer[(pos + bufSize - nofItems + i) MOD bufSize]
		END GetPointValue;
		
	END PerfMonModel;

VAR 
	PrototypeUnit : WMProperties.StringProperty;
	PrototypeMin, PrototypeMax, PrototypeDeltax, PrototypeDeltaXGrid, PrototypeDeltaXGridSmall, 
	PrototypeGlassShade, PrototypeValueWidth : WMProperties.Int32Property;
	PrototypeColor, PrototypeGridColor : WMProperties.ColorProperty;
	PrototypeAutoMin, PrototypeAutoMax, PrototypeShowValues  : WMProperties.BooleanProperty;

PROCEDURE InitProtoTypes;
	PROCEDURE S(s : ARRAY OF CHAR) : Utilities.String;
	BEGIN
		RETURN Utilities.NewString(s)
	END S;
	
BEGIN
	NEW(PrototypeUnit, NIL, S("Unit"), S("unit string for the diagram, if any"));
	NEW(PrototypeMin, NIL, S("Min"), S("minimum to assume if not autoMin")); PrototypeMin.Set(0);
	NEW(PrototypeMax, NIL, S("Max"), S("maximum to assume if not autoMax")); PrototypeMax.Set(100);
	NEW(PrototypeDeltax, NIL, S("Deltax"), S("pixel between samples")); PrototypeDeltax.Set(2);
	NEW(PrototypeDeltaXGrid, NIL, S("DeltaXGrid"), S("samples between separator lines")); PrototypeDeltaXGrid.Set(60);
	NEW(PrototypeDeltaXGridSmall, NIL, S("DeltaXGridSmall"), 
		S("samples between small separator lines")); PrototypeDeltaXGridSmall.Set(10);
	
	NEW(PrototypeColor, NIL, S("Color"), S("color of the graph")); PrototypeColor.Set(0CC00FFH);
	NEW(PrototypeGridColor, NIL, S("GridColor"), S("color of the grid")); PrototypeGridColor.Set(0FFCC00FFH);
	
	NEW(PrototypeGlassShade, NIL, S("GlassShade"), NIL); PrototypeGlassShade.Set(8);
	NEW(PrototypeValueWidth, NIL, S("ValueWidth"), NIL); PrototypeValueWidth.Set(50);
	NEW(PrototypeAutoMin, NIL, S("AutoMin"), NIL); PrototypeAutoMin.Set(TRUE);
	NEW(PrototypeAutoMax, NIL, S("AutoMax"), NIL); PrototypeAutoMax.Set(TRUE);
	NEW(PrototypeShowValues, NIL, S("ShowValues"), NIL); PrototypeShowValues.Set(FALSE);
END InitProtoTypes;

PROCEDURE RMin(a, b : REAL) : REAL;
BEGIN
	IF a < b THEN RETURN a ELSE RETURN b END
END RMin;

PROCEDURE RMax(a, b : REAL) : REAL;
BEGIN
	IF a> b THEN RETURN a ELSE RETURN b END
END RMax;


PROCEDURE Cleanup;
BEGIN 
END Cleanup;

BEGIN
	InitProtoTypes;
	AosModules.InstallTermHandler(Cleanup)
END WMDiagramComponents.

S.Free WMDiagramComponents 
WMDiagramComponents.Test 
WMDiagramComponents.Open 
 