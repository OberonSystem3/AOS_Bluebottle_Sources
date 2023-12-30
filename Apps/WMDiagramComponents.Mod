MODULE WMDiagramComponents;	(** AUTHOR "TF"; PURPOSE "Diagram components"; *)
(*
 * History:
 *
 *	02.02.2006	Added procedure PerfMonModel.Reset (staubesv)
 *	23.06.2006	Diagram can show multiple graphs with different colors, added DatasetDescriptorView (staubesv)
 *	26.02.2007	Added DataDescriptor.hide field and corresponding functionality (staubesv)
 *)
 
IMPORT
	AosActive, Utilities, WMRectangles, WMGraphics, WMEvents, WMProperties, WMStandardComponents,
	WMComponents, AosModules, WMGraphicUtilities;
	
TYPE

	DataPointModel = OBJECT
	VAR
		lockedBy : PTR;
		lockLevel : LONGINT;
		viewChanged : BOOLEAN;
		onChanged- : WMEvents.EventSource; (** does not hold the lock, if called *)

		PROCEDURE &New;
		BEGIN
			NEW(onChanged, SELF, WMComponents.NewString("DataPointModelChanged"), NIL, NIL);
			lockLevel := 0;
		END New;

		(** acquire a read/write lock on the object *)
		PROCEDURE Acquire*;
		VAR me : PTR;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			IF lockedBy = me THEN
				ASSERT(lockLevel # -1);	(* overflow *)
				INC(lockLevel);
			ELSE
				AWAIT(lockedBy = NIL); viewChanged := FALSE;
				lockedBy := me; lockLevel := 1;
			END;
		END Acquire;

		(** release the read/write lock on the object *)
		PROCEDURE Release*;
		VAR hasChanged : BOOLEAN;
		BEGIN 
			BEGIN {EXCLUSIVE}
				ASSERT(lockedBy = AosActive.ActiveObject(), 3000);
				hasChanged := FALSE;
				DEC(lockLevel);
				IF lockLevel = 0 THEN lockedBy := NIL; hasChanged := viewChanged; END;
			END;
			IF hasChanged THEN onChanged.Call(NIL); END;
		END Release;

	END DataPointModel;
		
TYPE

	DataDescriptor* = RECORD
		name* : ARRAY 32 OF CHAR;
		unit* : ARRAY 16 OF CHAR;
		color* : LONGINT;
		offset* : LONGREAL;
		(** Show graphically? Updates to this field are not synchronized with graphical representation! *)
		hide* : BOOLEAN; 
	END;
	
	DatasetDescriptor* = POINTER TO ARRAY OF DataDescriptor;

	Dataset* = POINTER TO ARRAY OF REAL;
	LongintDataset* = POINTER TO ARRAY OF LONGINT;
	
	Statistics* = RECORD
		valid- : BOOLEAN;
		cur*, min*, max*, avg*, sum* : Dataset;
		nbrOfSamples- : LONGINT;
	END;
	
TYPE

	MultiPointModel* = OBJECT(DataPointModel)
	VAR
		datasetDescriptor : DatasetDescriptor;
	
		buffer : POINTER TO ARRAY OF Dataset;
		pos, nofItems, dimensions : LONGINT;
		bufferSize : LONGINT;
		
		viewSampleCount : LONGINT;
		
		(* Lifetime statistics - min, max, sum of all value ever received (not just those in buffer) *)
		statistics : BOOLEAN;
		valid : BOOLEAN;
		nbrOfValues : LONGINT;
		cur, min, max, sum : Dataset;
		
		PROCEDURE &Init(bufferSize, dimensions : LONGINT);
		VAR i : LONGINT;
		BEGIN
			ASSERT(dimensions >= 1);
			New;
			SELF.bufferSize := bufferSize;
			SELF.dimensions := dimensions;
			
			(* Initialize buffer *)
			NEW(buffer, bufferSize);
			FOR i := 0 TO bufferSize - 1 DO
				NEW(buffer[i], dimensions);
			END;
			
			statistics := TRUE; nbrOfValues := 0; valid := FALSE;
			NEW(cur, dimensions); NEW(min, dimensions); NEW(max, dimensions); NEW(sum, dimensions);
		END Init;
		
		PROCEDURE Reset*;
		VAR i : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);		
			nofItems := 0; pos := 0; viewSampleCount := 0; viewChanged := TRUE;
			(* Reset statistics *)
			IF statistics THEN
				nbrOfValues := 0; valid := FALSE;
				FOR i := 0 TO dimensions-1 DO
					min[i] := MAX(REAL); max[i] := MIN(REAL);
					sum[i] := 0; cur[i] := 0;
				END;	
			END;
		END Reset;
		
		PROCEDURE GetStatistics*(VAR statistics : Statistics);
		VAR i : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			ASSERT(LEN(statistics.cur) = dimensions);
			ASSERT((LEN(statistics.min) = dimensions) & (LEN(statistics.max) = dimensions));
			ASSERT((LEN(statistics.sum) = dimensions) & (LEN(statistics.avg) = dimensions));
			IF valid THEN
				statistics.valid := TRUE;
				statistics.nbrOfSamples := nbrOfValues;
				FOR i := 0 TO dimensions-1 DO
					statistics.cur[i] := cur[i];
					statistics.min[i] := min[i];
					statistics.max[i] := max[i];
					statistics.sum[i] := sum[i];
					statistics.avg[i] := sum[i] / nbrOfValues;
				END;
			ELSE
				statistics.valid := FALSE;
			END;
		END GetStatistics;
		
		(* Find the max and min value in the model dataset. Model lock must be held *)
		PROCEDURE FindMinMax*(from, len : LONGINT; VAR min, max : REAL);
		VAR bufferIndex, dim : LONGINT; v : REAL; points : Dataset;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);		
			ASSERT((from >= 0) & (len > 0) & (from + len < nofItems));
			min := MAX(REAL); max := MIN(REAL);
			
			bufferIndex := (pos + bufferSize - nofItems + from) MOD bufferSize;
			
			WHILE len > 0 DO
				points := buffer[bufferIndex];
				FOR dim := 0 TO dimensions-1 DO
					IF (datasetDescriptor = NIL) OR ((datasetDescriptor # NIL) & (~datasetDescriptor[dim].hide)) THEN
						v := points[dim];
						min := RMin(min, v); max := RMax(max, v);
					END;
				END;
				bufferIndex := (bufferIndex + 1) MOD bufferSize;
				DEC(len);
			END;
		END FindMinMax;
		
		PROCEDURE SetDatasetDescriptor*(ds : DatasetDescriptor);
		BEGIN
			Acquire; datasetDescriptor := ds; Release;
		END SetDatasetDescriptor;
				
		PROCEDURE PutValues*(values : Dataset);
		VAR i : LONGINT; value : REAL;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			ASSERT(LEN(values) = dimensions);
			IF nofItems < bufferSize THEN INC(nofItems) END;
			FOR i := 0 TO dimensions - 1 DO
				buffer[pos][i] := values[i];
			END;
			pos := (pos + 1) MOD bufferSize;
			INC(viewSampleCount);
			viewChanged := TRUE;
			
			IF statistics THEN
				valid := TRUE; INC(nbrOfValues);
				FOR i := 0 TO dimensions - 1 DO
					value := values[i];
					cur[i] := value;
					IF value < min[i] THEN min[i] := value; END;
					IF value > max[i] THEN max[i] := value; END;
					sum[i] := sum[i] + value;
				END;
			END;
		END PutValues;
		
		PROCEDURE GetValues*(index : LONGINT; VAR dataset : Dataset);
		VAR dim, bufferIndex : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);	
			ASSERT((dataset # NIL) & (LEN(dataset) = dimensions));
			bufferIndex := (pos + bufferSize - nofItems + index) MOD bufferSize;
			FOR dim := 0 TO dimensions-1 DO
				dataset[dim] := buffer[bufferIndex][dim];
			END;
		END GetValues;
		
		PROCEDURE GetNofDimensions*() : LONGINT;
		BEGIN (* don't need lock here *)
			RETURN dimensions;
		END GetNofDimensions;
		
		PROCEDURE GetNofPoints*() : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			RETURN nofItems;
		END GetNofPoints;
		
	END MultiPointModel;
	
TYPE
	
	ExtUpdateHandler* = PROCEDURE {DELEGATE};

TYPE

	MultiPointView* = OBJECT(WMComponents.VisualComponent)
	VAR 
		model- : MultiPointModel;
		
		(* Note: Grid is not rendered when deltaXGrid/deltaXGridSmall are zero *)
		min-, max-, deltax-, deltaXGrid-, deltaXGridSmall-, glassShade-, valueWidth- : WMProperties.Int32Property;
		color-, gridColor- : WMProperties.ColorProperty;
		autoMin-, autoMax-: WMProperties.BooleanProperty;
		unit- : WMProperties.StringProperty;
		showValues- : WMProperties.BooleanProperty;
		
		extUpdate : ExtUpdateHandler;
		
		dimensions : LONGINT;
		
		points : Dataset;
		points0, points1 : LongintDataset;

		PROCEDURE &New;
		BEGIN
			Init;
			dimensions := 1; NEW(points0, 1); NEW(points1, 1); NEW(points, 1);
			NEW(model, 1024, 1);
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
			model.onChanged.Add(Update);
		END New;
		
		PROCEDURE SetExtModel*(model : MultiPointModel);
		BEGIN
			ASSERT(model # NIL);
			Acquire;
			IF model # NIL THEN model.onChanged.Remove(Update); END;
			SELF.model := model;
			SELF.dimensions := model.GetNofDimensions();
			NEW(points0, dimensions);
			NEW(points1, dimensions);
			NEW(points, dimensions);
			model.onChanged.Add(Update);
			Release;
			Invalidate;
		END SetExtModel;
		
		PROCEDURE SetExtUpdate*(extUpdate : ExtUpdateHandler);
		BEGIN
			Acquire; SELF.extUpdate := extUpdate; Release;
		END SetExtUpdate;

		PROCEDURE Update(sender, data : ANY);
		BEGIN
			IF extUpdate # NIL THEN 
				extUpdate();
			ELSE
				Invalidate;
			END;
		END Update;

		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR w, h, i, x, v0, v1, virtp, dx, dxgrid, dxgrids, t : LONGINT;
			nofVisible : LONGINT;
			tmin, tmax : REAL;
			col, gcol, gcolhalf, yborder : LONGINT;
			str : ARRAY 16 OF CHAR;
			s : Utilities.String;
			dim : LONGINT;
			
			PROCEDURE Scale(srcPoints : Dataset; tarPoints : LongintDataset);
			VAR x, f : REAL; dim : LONGINT;
			BEGIN
				FOR dim := 0 TO dimensions-1 DO
					x := srcPoints[dim];
					IF (tmax - tmin) = 0 THEN f := 1; ELSE f := 1 / (tmax - tmin); END;
					tarPoints[dim] := ENTIER(((x - tmin) * f) * (h - 2 * yborder));
				END;
			END Scale;

		BEGIN
			canvas.SetFont(GetFont());
			yborder := 5;
			model.Acquire;
			IF fillColor.Get() # 0 THEN canvas.Fill(GetClientRect(), fillColor.Get(), WMGraphics.ModeCopy); END;
			col := color.Get();
			gcol := gridColor.Get();
			gcolhalf := WMGraphicUtilities.ScaleColor(gcol, 80H);
			w := bounds.GetWidth(); h := bounds.GetHeight();
			IF showValues.Get() THEN DEC(w, valueWidth.Get()); END;
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
					DEC(t, dx* dxgrids);
				END;
			END;

			IF dxgrid > 0 THEN
				t := w - (virtp MOD dxgrid) * dx;
				IF virtp MOD dxgrid = 0 THEN model.viewSampleCount := 0; END;
				WHILE t > 0 DO
					canvas.Line(t, 0, t, h, gcol, WMGraphics.ModeSrcOverDst);
					DEC(t, dx* dxgrid);
				END;
			END;

			IF nofVisible >= 2 THEN
				model.GetValues(i, points);			
				model.FindMinMax(i - nofVisible, nofVisible, tmin, tmax);
				IF ~autoMin.Get() THEN tmin := min.Get(); END;
				IF ~autoMax.Get() THEN tmax := max.Get(); END;
				
				x := w;
				model.GetValues(i, points); Scale(points, points0);
				DEC(i);
				
				WHILE (i > 0) & (x >= 0) DO
					FOR dim := 0 TO dimensions-1 DO
						points1[dim] := points0[dim];
					END;
					model.GetValues(i, points); Scale(points, points0);
					
					FOR dim := 0 TO dimensions-1 DO
						v0 := points0[dim]; v1 := points1[dim];
						IF (model.datasetDescriptor = NIL) THEN
							canvas.Line(x - dx, (h - yborder) - v0, x, (h - yborder) - v1, col, WMGraphics.ModeCopy);
						ELSE
							IF ~model.datasetDescriptor[dim].hide THEN
								 col := model.datasetDescriptor[dim].color;
								 canvas.Line(x - dx, (h - yborder) - v0, x, (h - yborder) - v1, col, WMGraphics.ModeCopy);
							END;
						END;
					END;
					x := x - dx;
					DEC(i);
				END;
			END;
			model.Release;

			IF showValues.Get() THEN
				canvas.Fill(WMRectangles.MakeRect(w, 0, w + 4, h), 080H, WMGraphics.ModeSrcOverDst);
				canvas.SetColor(color.Get());
				Utilities.FloatToStr(tmax, 0, 1, 0, str); canvas.DrawString(w + 5, 8 + 5, str);
				Utilities.FloatToStr(tmin, 0, 1, 0, str); canvas.DrawString(w + 5, h - 5, str);
				s := unit.Get();
				IF s # NIL THEN canvas.DrawString(w + 10, h DIV 2 + 4, s^); END;
			END;
			IF glassShade.Get() # 0 THEN
				WMGraphicUtilities.RectGlassShade(canvas, GetClientRect(), glassShade.Get(), FALSE);
			END;
		END DrawBackground;
		
		PROCEDURE Finalize;
		BEGIN
			IF model # NIL THEN model.onChanged.Remove(Update); END;
			Finalize^;
		END Finalize;

	END MultiPointView;

TYPE

	(** Graphical represenation of a dataset descriptor *)
	DatasetDescriptorView* = OBJECT (WMComponents.VisualComponent)
	VAR
		datasetDescriptor : DatasetDescriptor;
		
		names, colors : POINTER TO ARRAY OF WMStandardComponents.Label;
		checkboxes : POINTER TO ARRAY OF WMStandardComponents.Checkbox;
		
		checkAllBtn, checkNoneBtn : WMStandardComponents.Button;
		
		(** Optimum width and height *)
		optWidth-, optHeight- : LONGINT;
		
		(** onClick handler called by each checkbox *)
		PROCEDURE HandleClick(sender, data : PTR);
		VAR i, state : LONGINT;
		BEGIN
			FOR i := 0 TO LEN(checkboxes)-1 DO
				state := checkboxes[i].state.Get();
				IF (state = WMStandardComponents.Checked) THEN
					datasetDescriptor[i].hide := FALSE;
				ELSE
					datasetDescriptor[i].hide := TRUE;
				END;				
			END;
		END HandleClick;
		
		PROCEDURE HandleButton(sender, data : PTR);
		VAR i : LONGINT;
		BEGIN
			IF sender = checkAllBtn THEN
				FOR i := 0 TO LEN(checkboxes)-1 DO
					datasetDescriptor[i].hide := FALSE;
					checkboxes[i].state.Set(WMStandardComponents.Checked);
				END;
			ELSIF sender = checkNoneBtn THEN
				FOR i := 0 TO LEN(checkboxes)-1 DO
					datasetDescriptor[i].hide := TRUE;
					checkboxes[i].state.Set(WMStandardComponents.Unchecked);
				END;
			ELSE
			END;
		END HandleButton;
	
		PROCEDURE &New(ds : DatasetDescriptor);
		VAR i : LONGINT; panel : WMStandardComponents.Panel;
		BEGIN
			ASSERT((ds # NIL) & (LEN(ds) >=1));
			datasetDescriptor := ds;
			Init;
			NEW(names, LEN(ds));
			NEW(colors, LEN(ds));
			NEW(checkboxes, LEN(ds));
			optWidth := 200; optHeight := LEN(ds) * 20;
			FOR i := 0 TO LEN(ds)-1 DO
				NEW(panel); panel.alignment.Set(WMComponents.AlignTop); panel.bounds.SetHeight(20);
				panel.fillColor.Set(WMGraphics.White);
				
				NEW(checkboxes[i]); checkboxes[i].alignment.Set(WMComponents.AlignLeft); checkboxes[i].bounds.SetExtents(20, 20);
				checkboxes[i].fillColor.Set(WMGraphics.White);
				checkboxes[i].onClick.Add(HandleClick);
				IF ds[i].hide THEN checkboxes[i].state.Set(WMStandardComponents.Unchecked); 
				ELSE checkboxes[i].state.Set(WMStandardComponents.Checked); 
				END;
				panel.AddContent(checkboxes[i]);
				
				NEW(colors[i]); colors[i].alignment.Set(WMComponents.AlignLeft); colors[i].bounds.SetWidth(40);
				colors[i].fillColor.Set(WMGraphics.Black);
				colors[i].caption.SetAOC(" __________ "); colors[i].textColor.Set(ds[i].color);
				panel.AddContent(colors[i]);
				
				NEW(names[i]); names[i].alignment.Set(WMComponents.AlignClient);
				names[i].fillColor.Set(WMGraphics.White);
				names[i].caption.SetAOC(ds[i].name);
				panel.AddContent(names[i]);
				
				AddContent(panel);
			END;	
			
			NEW(panel); panel.alignment.Set(WMComponents.AlignBottom); panel.bounds.SetHeight(20);
			panel.fillColor.Set(WMGraphics.White);
			AddContent(panel);
			
			NEW(checkAllBtn); checkAllBtn.alignment.Set(WMComponents.AlignLeft); checkAllBtn.bounds.SetWidth(optWidth DIV 2);
			checkAllBtn.caption.SetAOC("ALL");
			checkAllBtn.onClick.Add(HandleButton);
			panel.AddContent(checkAllBtn);
			
			NEW(checkNoneBtn); checkNoneBtn.alignment.Set(WMComponents.AlignClient); 
			checkNoneBtn.caption.SetAOC("NONE");
			checkNoneBtn.onClick.Add(HandleButton);
			panel.AddContent(checkNoneBtn);
		END New;
		
	END DatasetDescriptorView;

VAR 
	PrototypeUnit : WMProperties.StringProperty;
	PrototypeMin, PrototypeMax, PrototypeDeltax, PrototypeDeltaXGrid, PrototypeDeltaXGridSmall, 
	PrototypeGlassShade, PrototypeValueWidth : WMProperties.Int32Property;
	PrototypeColor, PrototypeGridColor : WMProperties.ColorProperty;
	PrototypeAutoMin, PrototypeAutoMax, PrototypeShowValues  : WMProperties.BooleanProperty;

PROCEDURE InitProtoTypes;

	PROCEDURE S(s : ARRAY OF CHAR) : Utilities.String;
	BEGIN
		RETURN Utilities.NewString(s);
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
	IF a < b THEN RETURN a; ELSE RETURN b; END;
END RMin;

PROCEDURE RMax(a, b : REAL) : REAL;
BEGIN
	IF a> b THEN RETURN a; ELSE RETURN b; END;
END RMax;

PROCEDURE CopyDatasetDescriptor*(ds : DatasetDescriptor) : DatasetDescriptor;
VAR result : DatasetDescriptor; i : LONGINT;
BEGIN
	IF ds # NIL THEN
		NEW(result, LEN(ds));
		FOR i := 0 TO LEN(ds)-1 DO
			COPY(ds[i].name, result[i].name);
			result[i].color := ds[i].color;
			result[i].hide := ds[i].hide;
		END;
	END;
	RETURN result;	
END CopyDatasetDescriptor;

PROCEDURE Cleanup;
BEGIN 
END Cleanup;

BEGIN
	InitProtoTypes;
	AosModules.InstallTermHandler(Cleanup);
END WMDiagramComponents.

S.Free WMDiagramComponents ~


 