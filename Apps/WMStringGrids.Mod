MODULE WMStringGrids;	(** AUTHOR "TF"; PURPOSE "String grid  component"; *)
(**
 * History:
 *
 *	12.03.2007	Added StringGridModel.SetCellColors and StringGridModel.GetCellColors (staubesv)
 *)
 
IMPORT
		WMWindowManager, AosOut, AosActive, AosModules, WMComponents, WMGraphics,
		WMStandardComponents, WMMessages, WMProperties, WMEvents, WMRectangles, Utilities, 
		WMGrids, WMGraphicUtilities;

TYPE
	String = Utilities.String;
	Cell* = OBJECT
	VAR
		caption : String;
		usePerCellColors : BOOLEAN;
		color, textColor : LONGINT;
		align: LONGINT;
		img : WMGraphics.Image;
		data : ANY;
	END Cell;
	
	CellArray = POINTER TO ARRAY OF Cell;
	Row = POINTER TO RECORD
		cells : CellArray;
	END;
	RowArray = POINTER TO ARRAY OF Row;
	
TYPE
	StringGridModel* = OBJECT
	VAR 
		lockedBy : PTR;
		lockLevel : LONGINT;
		viewChanged : BOOLEAN;
		onChanged* : WMEvents.EventSource; (** does not hold the lock, if called *)
		rows : RowArray;
		nofRows, nofCols : LONGINT;
		
		PROCEDURE &Init;
		BEGIN
			NEW(onChanged, SELF, WMComponents.NewString("TreeModelChanged"), NIL, NIL);
			NEW(rows, 4);
			lockLevel :=0 
		END Init;
		
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
		
		PROCEDURE AdjustRows(newSize : LONGINT);
		VAR i : LONGINT; 
			newRows : RowArray;
		BEGIN
			NEW(newRows, newSize);
			FOR i := 0 TO Utilities.Min(nofRows, newSize) - 1 DO
				newRows[i] := rows[i]
			END;
			FOR i := Utilities.Min(nofRows, newSize)  TO newSize - 1 DO
				NEW(newRows[i]);
				AdjustRow(newRows[i])
			END; 
			rows := newRows
		END AdjustRows;
		
		PROCEDURE AdjustRow(row : Row);
		VAR i : LONGINT;
			newCells : CellArray;
		BEGIN
			IF row.cells = NIL THEN NEW(row.cells, nofCols) END;
			IF LEN(row.cells) # nofCols THEN
				NEW(newCells, nofCols);
				FOR i := 0 TO Utilities.Min(nofCols, LEN(row.cells)) - 1 DO
					newCells[i] := row.cells[i]
				END;
				row.cells := newCells
			END
		END AdjustRow;
		
		PROCEDURE SetNofRows*(newNofRows : LONGINT);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (newNofRows > nofRows) OR (newNofRows < nofRows DIV 2)  THEN AdjustRows(newNofRows) END;
			nofRows := newNofRows;
			viewChanged := TRUE
		END SetNofRows;
		
		PROCEDURE SetNofCols*(newNofCols : LONGINT);
		VAR i : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			nofCols := newNofCols;
			FOR i := 0 TO nofRows - 1 DO AdjustRow(rows[i]) END;
			viewChanged := TRUE
		END SetNofCols;
		
		PROCEDURE GetNofRows*() : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			RETURN nofRows
		END GetNofRows;

		PROCEDURE GetNofCols*() : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			RETURN nofCols
		END GetNofCols;
		
		PROCEDURE SetCellText*(col, row : LONGINT; caption : String);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF rows[row].cells[col] = NIL THEN NEW(rows[row].cells[col]) END;
				IF rows[row].cells[col].caption # caption THEN
					rows[row].cells[col].caption := caption;
					viewChanged := TRUE
				END
			END	
		END SetCellText;
		
		PROCEDURE GetCellText*(col, row : LONGINT ) : String;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF rows[row].cells[col] = NIL THEN RETURN NIL END;
				RETURN rows[row].cells[col].caption
			ELSE RETURN NIL
			END	
		END GetCellText;
		
		PROCEDURE SetCellColors*(col, row, color, textColor : LONGINT);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF rows[row].cells[col] = NIL THEN NEW(rows[row].cells[col]) END;
				rows[row].cells[col].usePerCellColors := TRUE;
				IF rows[row].cells[col].color # color THEN
					rows[row].cells[col].color := color;
					viewChanged := TRUE;
				END;
				IF rows[row].cells[col].textColor # textColor THEN
					rows[row].cells[col].textColor := textColor;
					viewChanged := TRUE;
				END;
			END;
		END SetCellColors;
		
		PROCEDURE GetCellColors*(col, row : LONGINT; VAR color, textColor : LONGINT; VAR valid : BOOLEAN);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			valid := FALSE;
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF (rows[row].cells[col] # NIL) & (rows[row].cells[col].usePerCellColors) THEN
					valid := TRUE;
					color := rows[row].cells[col].color;
					textColor := rows[row].cells[col].textColor;
				END;
			END;
		END GetCellColors;
		
		PROCEDURE SetCellData*(col, row : LONGINT; data : ANY);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF rows[row].cells[col] = NIL THEN NEW(rows[row].cells[col]) END;
				IF rows[row].cells[col].data # data THEN
					rows[row].cells[col].data:= data;
					viewChanged := TRUE
				END
			END	
		END SetCellData;
		
		PROCEDURE GetCellData*(col, row : LONGINT) : ANY;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF rows[row].cells[col] = NIL THEN RETURN NIL END;
				RETURN rows[row].cells[col].data
			ELSE RETURN NIL
			END	
		END GetCellData;
		
		PROCEDURE SetCellImage*(col, row : LONGINT; img : WMGraphics.Image);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF rows[row].cells[col] = NIL THEN NEW(rows[row].cells[col]) END;
				IF rows[row].cells[col].img # img THEN
					rows[row].cells[col].img := img;
					viewChanged := TRUE
				END
			END	
		END SetCellImage;
		
		PROCEDURE GetCellImage*(col, row : LONGINT) : WMGraphics.Image;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF rows[row].cells[col] = NIL THEN RETURN NIL END;
				RETURN rows[row].cells[col].img
			ELSE RETURN NIL
			END	
		END GetCellImage;
		
		PROCEDURE SetTextAlign*(col, row, align : LONGINT);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF rows[row].cells[col] = NIL THEN NEW(rows[row].cells[col]) END;
				IF rows[row].cells[col].align # align THEN
					rows[row].cells[col].align:= align;
					viewChanged := TRUE
				END	
			END	
		END SetTextAlign;
		
		PROCEDURE GetTextAlign*(col, row : LONGINT) : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (col >= 0) & (row >= 0) & (col < nofCols) & (row < nofRows) THEN
				IF rows[row].cells[col] = NIL THEN RETURN 0 END;
				RETURN rows[row].cells[col].align
			ELSE RETURN 0
			END	
		END GetTextAlign;
		
		PROCEDURE DeleteRow*(rowNo : LONGINT; viewChanged : BOOLEAN);
		VAR i : LONGINT;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (rowNo >=  0) & (rowNo < nofRows) THEN
				FOR i := rowNo TO nofRows - 2 DO
					rows[i] := rows[i + 1]
				END;
				DEC(nofRows);
				SELF.viewChanged := viewChanged
			END
		END DeleteRow;
		
		PROCEDURE InsertEmptyRow*(atRowNo : LONGINT);
		VAR i : LONGINT;
			newRows : RowArray;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF (atRowNo >= 0) & (atRowNo <= nofRows) THEN
				NEW(newRows, nofRows + 1);
				FOR i := 0 TO atRowNo - 1 DO
					newRows[i] := rows[i]
				END;
				NEW(newRows[atRowNo]);
				AdjustRow(newRows[atRowNo]);
				FOR i := atRowNo + 1 TO nofRows DO
					newRows[i] := rows[i - 1]
				END
			END;
			INC(nofRows);
			rows := newRows;
			viewChanged := TRUE
		END InsertEmptyRow;
		
	END StringGridModel;
	
TYPE StringGrid* = OBJECT(WMGrids.GenericGrid)
	VAR model- : StringGridModel;
		cellColor, hoverColor, selectedColor, fixedColor, textHoverColor, textColor, textSelectedColor : LONGINT;
		clCell-, clFixed-, clHover-, clSelected-, clTextDefault-, clTextHover-, clTextSelected- : WMProperties.ColorProperty;
		
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(clCell, PrototypeTclCell, NIL, NIL); properties.Add(clCell);
			NEW(clHover, PrototypeTclHover, NIL, NIL); properties.Add(clHover);
			NEW(clSelected, PrototypeTclSelected, NIL, NIL); properties.Add(clSelected);
			NEW(clFixed, PrototypeTclFixed, NIL, NIL); properties.Add(clFixed);
			
			NEW(clTextDefault, PrototypeTclTextDefault, NIL, NIL); properties.Add(clTextDefault);
			NEW(clTextHover, PrototypeTclTextHover, NIL, NIL); properties.Add(clTextHover);
			NEW(clTextSelected, PrototypeTclTextSelected,  NIL, NIL); properties.Add(clTextSelected);
		(*	NEW(fontHeight, PrototypeTfontHeight, NIL, NIL); properties.Add(fontHeight);	*)
			takesFocus.Set(TRUE);
			NEW(model);
			model.onChanged.Add(ModelChanged)
		END Init;
		
		PROCEDURE ModelChanged(sender, data : ANY);
		BEGIN
			Acquire;
			nofCols.Set(model.nofCols);
			nofRows.Set(model.nofRows);
			Invalidate;
			SetDrawCellProc(DrawCell);
			Release
		END ModelChanged;
		
		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		BEGIN
			cellColor := clCell.Get();
			hoverColor := clHover.Get();
			selectedColor := clSelected.Get();
			fixedColor := clFixed.Get();
			textColor := clTextDefault.Get();
			textHoverColor := clTextHover.Get();
			textSelectedColor := clTextSelected.Get();
			model.Acquire;
			DrawBackground^(canvas);
			model.Release
		END DrawBackground;
		
		PROCEDURE GetCellData*(col, row : LONGINT) : ANY;
		VAR data : ANY;
		BEGIN
			model.Acquire;
			data := model.GetCellData(col, row);
			model.Release;
			RETURN data
		END GetCellData;
		
(*		PROCEDURE CellClicked*(col, row : LONGINT); (** PROTECTED *)
		BEGIN
			model.Acquire;
			data := model.GetCellData(col, row);
			model.Release;
			CellClicked^(col, row);
	(*		onClick.Call(data);
			IF wasSelected  & onClickSelected.HasListeners() THEN 
				onClickSelected.Call(data)
			END; *)
		END CellClicked; *)
		
		PROCEDURE DrawCell(canvas : WMGraphics.Canvas; w, h : LONGINT; state : SET; x, y : LONGINT);
		VAR 
			s : String; font : WMGraphics.Font; left, c, tc: LONGINT; img : WMGraphics.Image;
			valid : BOOLEAN;
		BEGIN
			s := model.GetCellText(x, y);

			model.GetCellColors(x, y, c, tc, valid);
			IF ~valid THEN 
				c := cellColor;
				tc := textColor;
			END;

			IF WMGrids.CellFixed IN state THEN 
				c := fixedColor; 
				IF WMGrids.CellSelected IN state THEN 
					c := WMGraphicUtilities.InterpolateColorLinear(c, selectedColor, 128)
				ELSIF  WMGrids.CellHighlighted IN state THEN 
					c := WMGraphicUtilities.InterpolateColorLinear(c, hoverColor, 128)
				END;
				canvas.Fill(WMRectangles.MakeRect(0, 0, w, h), c, WMGraphics.ModeCopy)
			ELSIF WMGrids.CellSelected IN state THEN 
				canvas.Fill(WMRectangles.MakeRect(0, 0, w, h), selectedColor, WMGraphics.ModeSrcOverDst);
				tc := textSelectedColor
			ELSIF WMGrids.CellHighlighted IN state THEN
				canvas.Fill(WMRectangles.MakeRect(0, 0, w, h), hoverColor, WMGraphics.ModeSrcOverDst);
				tc := textHoverColor
			ELSE 
				canvas.Fill(WMRectangles.MakeRect(0, 0, w, h), c, WMGraphics.ModeSrcOverDst)		
			END;
			
			font := GetFont();
			canvas.SetColor(tc);
			left := 1; img := model.GetCellImage(x, y);
			IF img # NIL THEN INC(left, img.width + 1) END;
			
			IF s # NIL THEN 
				canvas.DrawImage(1, 1, img, WMGraphics.ModeSrcOverDst);
				WMGraphics.DrawStringInRect(canvas, WMRectangles.MakeRect(left, 1, w - 2, h - 2), FALSE, 
					model.GetTextAlign(x, y), WMGraphics.AlignCenter, s^)
			END;
			IF WMGrids.CellSelected IN state THEN 
				WMGraphicUtilities.ExtRectGlassShade(canvas, WMRectangles.MakeRect(0, 0, w, h), {1, 3}, 5, FALSE);
			END
			(* IF s # NIL THEN canvas.DrawString(0, h - font.descent, s^) END *)
		END DrawCell;

	END StringGrid;

(***************************************************************************************)
(* Testbed *)
(***************************************************************************************)
TYPE
	KillerMsg = OBJECT
	END KillerMsg; 
	
	Window* = OBJECT (WMComponents.FormWindow)
	VAR label: WMStandardComponents.Label;	
		tabs : StringGrid;
		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			toolbar: WMStandardComponents.Panel;
			button : WMStandardComponents.Button;

		BEGIN
			NEW(panel); panel.bounds.SetExtents(800, 700); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
			NEW(toolbar); toolbar.fillColor.Set(000FF00FFH); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(button); button.alignment.Set(WMComponents.AlignLeft); button.caption.SetAOC("Test"); 
			toolbar.AddContent(button);
			button.onClick.Add(Test);
		
			NEW(label); label.bounds.SetHeight(20);label.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(label);

			NEW(tabs);
			tabs.alignment.Set(WMComponents.AlignClient);
			tabs.fillColor.Set(0FF0000FFH);
			panel.AddContent(tabs);
			tabs.model.Acquire;
			tabs.model.SetNofCols(4);
			tabs.model.SetNofRows(10);
			tabs.model.Release;
			RETURN panel
		END CreateForm;

		PROCEDURE &New();
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount;
			vc := CreateForm();
			
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			manager := WMWindowManager.GetDefaultManager();
			manager.Add(100, 100, SELF, {WMWindowManager.FlagFrame});
			SetTitle(Utilities.NewString("Test Window"));
		END New;
		
		PROCEDURE Test(sender, data : ANY);
		VAR i : LONGINT; str : ARRAY 20 OF CHAR;
		BEGIN
			tabs.model.Acquire;
			FOR i := 0 TO 4 * 5 - 1 DO
				Utilities.IntToStr(i, str);
				tabs.model.SetCellText(i MOD 4, i DIV 4, Utilities.NewString(str))
			END;			
			tabs.model.Release;
		END Test;
		
			
		PROCEDURE Close;
		BEGIN
			DecCount;
			Close^;
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
			ELSE Handle^(x)
			END
		END Handle;		
		
		
	END Window;
(***************************************************************************************)

VAR
	 PrototypeTclCell*, PrototypeTclHover*, PrototypeTclSelected*, PrototypeTclTextDefault*, 
	 PrototypeTclTextHover*, PrototypeTclTextSelected*, PrototypeTclFixed* : WMProperties.ColorProperty; 
	 PrototypeTfontHeight* : WMProperties.Int32Property;
	 
VAR
	nofWindows : LONGINT;	 
	 
PROCEDURE InitPrototypes;
VAR plStringGrid : WMProperties.PropertyList;
BEGIN
	NEW(plStringGrid);
	NEW(PrototypeTclCell, NIL, Utilities.NewString("ClCell"), Utilities.NewString("color of the cell"));
	plStringGrid.Add(PrototypeTclCell);
	NEW(PrototypeTclFixed, NIL, Utilities.NewString("ClFixed"), Utilities.NewString("color of a fixed cell"));
	plStringGrid.Add(PrototypeTclFixed);	
	NEW(PrototypeTclHover, NIL, Utilities.NewString("ClHover"), Utilities.NewString("color of the tree item, if the mouse is over it"));
	plStringGrid.Add(PrototypeTclHover);
	NEW(PrototypeTclSelected, NIL, Utilities.NewString("ClSelected"), Utilities.NewString("color of the the tree item, if it is selected"));
	plStringGrid.Add(PrototypeTclSelected);
	NEW(PrototypeTclTextDefault, NIL, Utilities.NewString("ClTextDefault"), Utilities.NewString("default text color of the tree item"));
	plStringGrid.Add(PrototypeTclTextDefault);
	NEW(PrototypeTclTextHover, NIL, Utilities.NewString("ClTextHover"), Utilities.NewString("text color of the tree item, if the mouse is over it"));
	plStringGrid.Add(PrototypeTclTextHover);
	NEW(PrototypeTclTextSelected, NIL, Utilities.NewString("ClTextSelected"), Utilities.NewString("text color of the tree item, when selected"));
	plStringGrid.Add(PrototypeTclTextSelected);
	NEW(PrototypeTfontHeight, NIL, Utilities.NewString("FontHeight"), Utilities.NewString("height of the tree item text"));
	plStringGrid.Add(PrototypeTfontHeight);
	PrototypeTclCell.Set(0FFFFFFFFH);
	PrototypeTclFixed.Set(0CCCCCCFFH);
	PrototypeTclHover.Set(0FFFF00FFH);
	PrototypeTclSelected.Set(00000FFFFH);
	PrototypeTclTextDefault.Set(0000000FFH);
	PrototypeTclTextHover.Set(00000FFFFH);
	PrototypeTclTextSelected.Set(0FFFFFFFFH);

	PrototypeTfontHeight.Set(12);
	WMComponents.propertyListList.Add("StringGrid", plStringGrid);
	WMComponents.propertyListList.UpdateStyle;
END InitPrototypes;	

PROCEDURE Install*(par : PTR) : PTR;
BEGIN
	RETURN NIL
END Install;

PROCEDURE Test*(par : ANY) : ANY;
VAR strings : StringGridModel;
	str : ARRAY 12 OF CHAR;
	s : String;
	i : LONGINT;
BEGIN
	NEW(strings);
	strings.Acquire;
	strings.SetNofCols(4);
	strings.SetNofRows(5);
	FOR i := 0 TO 4 * 5 - 1 DO
		Utilities.IntToStr(i, str);
		strings.SetCellText(i MOD 4, i DIV 4, Utilities.NewString(str))
	END;
	FOR i := 0 TO 4 * 5 - 1 DO
		s := strings.GetCellText(i MOD 4, i DIV 4);
		IF s # NIL THEN AosOut.String(s^) ELSE AosOut.String("NIL") END; AosOut.Ln; 
	END;
	strings.Release;
	RETURN NIL
END Test;


PROCEDURE Init;
BEGIN
	InitPrototypes
END Init;

PROCEDURE Uninstall;
BEGIN
	WMComponents.registry.UnregisterElement("TreeView");
	Cleanup
END Uninstall;

PROCEDURE Open*(par : ANY) : ANY;
VAR inst : Window;
BEGIN
	NEW(inst);
	RETURN NIL
END Open;

PROCEDURE IncCount;
BEGIN {EXCLUSIVE}
	INC(nofWindows);
END IncCount;		

PROCEDURE DecCount;
BEGIN {EXCLUSIVE}
	DEC(nofWindows);
END DecCount;		

PROCEDURE Cleanup;
VAR die : KillerMsg;
	 msg : WMMessages.Message;
	 m : WMWindowManager.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die); msg.ext := die; msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	Init;
	AosModules.InstallTermHandler(Uninstall)
END WMStringGrids.

S.Free WMStringGrids 
WMStringGrids.Open  


