MODULE WMPartitions; (** AUTHOR: "staubesv"; PURPOSE: "Partition Tool" *)
(**
 * The MainWindow manages PartitionsPlugins. It shows a graphical representation of all disk devices (AosDisks.Device) and their partition layout.
 * The user can select a partition of a device. This selection is passed to the currently active PartitionsPlugin which takes the selection as a parameter.
 * A special case plugin (PendingOperations) is always installed. It provides access to disk operations (AosPartitionsLib.Operation) which are registered
 * at the disk operation manager (AosPartitionsLib.OperationManager).
 *
 * History:
 *
 * 	05.08.2005	Mount prefixes shown at the correct partition, cleanup (staubesv)
 * 	25.11.2005	Improved ReportWindow scaling (staubesv)
 *	30.11.2005	Improved PopupWindow, added experimental CustomEditor (staubesv)
 *	08.12.2005	Force redraw when disks are added/removed, vertical scrollbar improved (staubesv)
 *	13.12.2005	Synchronization improved, don't update view when read operations finish (staubesv)
 *	14.12.2005	Improved scrollbar handling (staubesv)
 *	16.12.2005	Fixed vtable generation for extended partitions that do not contain logical drives (staubesv)
 *	19.12.2005	Don't reset scrollbars when updating view (staubesv)
 *	06.12.2005	Adapted to changes in AosPartitionsLib.Mod - type ResultString no longer available (staubesv)
 *	14.02.2006	Added support for restoring window (staubesv)
 *	07.07.2006	Window restoring improved (staubesv)
 *	09.08.2006	Display partition size in KB if size < 4MB, show disk geometry info (staubesv)
 *
 * TODO:
 *	- Finalization of VisualComponents
 *)
 
IMPORT 
	AosOut, AosBoot, AosPlugins, AosDisks, Utilities, AosModules,  AosKernel,  AosIO, AosTexts, AosTextUtilities, AosPartitionsLib,
	WMWindowManager,WMComponents, WMStandardComponents, WMGrids, WMStringGrids,
	WMGraphics, WMGraphicUtilities, WMRectangles, WMTextView, WMEditors, WMProperties, WMRestorable, WMMessages;

CONST

	(** Return values of PopupWindow.Popup() *)
	ResNone* = 0; 	
	ResOk* = 1;
	ResCancel* = 2;
	
	(** Parameter types for Parameter.type field *)
	ParInteger* = 0;
	ParString* = 1;
	ParBoolean* = 2;
	
	(** Return values of PartitionsPlugin.SelectionUpdated *)
	SelectionValid* = 1; (** selected partition seems to be of the exspected type *)
	SelectionInvalid* = 2; (** plugin will do nothing when user tries to apply it *)
	SelectionMaybe* = 3; (** plugin can't determine whether its application will be successful *)
	SelectionNotSupported* = 0; (** plugin doesn't care about this return value *)
	
	DefaultPlugin = "FSTools"; (* plugin selected at application startup *)
	
	(* Default window size at startup *)
	DefaultWidth = 700; DefaultHeight = 400;
	
	(* If the window is smaller than this size, scale it *)
	WindowMinWidth = 350; WindowMinHeight = 350;

	WindowBg* = 0999999FFH; 

	MainPanelMarginH* = 5 ; 
	MainPanelMarginV* = 5 ; 
	MainPanelMarginColor* = 0BFBFBFFFH; 
	
	ButtonHeight* = 20;
	ButtonWidth* = 80;
	ButtonSpacer* = 2; 

	(* the DiskOverviewPanel contains the DiskPanels & Grids *)
	DiskOverviewPanelMarginH* = 7;
	DiskOverviewPanelMarginV* = 7;
	DiskOverviewPanelBgColor = WMGraphics.White;	
	DiskOverviewTableColumns = 6; 
	
	(* DiskPanels are graphical representations of disks *)
	DiskPanelHeight = 40;
	DiskPanelMarginH = 5;
	DiskPanelMarginV = 5;
	DiskPanelSpacer = 5; (* spacer between partitions *)
	PanelMinWidth = 10; (* minimum width of the graphical representation of a partition *)
	LabelHeight = 18;  
	LabelBgColor = WindowBg;
	LabelTxtColor = WMGraphics.Black;
	GridMinSpacerV = 2;
	GridMinSpacerH = 2;

	StatusBarHeight = 20;
	StatusBarBgColor = WMGraphics.Blue;

	SelectionLabelBgColor = WindowBg;
	
	OperationPanelHeight = ButtonHeight + 2*DiskOverviewPanelMarginV;
	OperationPanelBgColor = WindowBg;
	
	PluginPanelHeight = 2*ButtonHeight + ButtonSpacer + DiskPanelMarginV;
	PluginPanelBgColor = WindowBg;
	PluginButtonColor = WMGraphics.Blue;
	
	ShowDiskGeometry = TRUE;
	
	(* speed of scrolling *)
	Multiplier = 30;
	
	PopupLabelHeight = 20;

	(* Pending operation plugin constants *)
	RemoveSelected = 0;
	RemoveFinished = 1;
	RemoveAll = 2;
	
	(* BevelPanel *)
	BevelBorderWidth = 2;
	BevelBgColor = 0808080FFH;
	
TYPE
	
	BevelPanel* = OBJECT(WMStandardComponents.Panel);
	
		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		BEGIN
			IF ~visible.Get() THEN RETURN END;
			Acquire;
			WMGraphicUtilities.DrawBevelPanel(canvas, GetClientRect(), BevelBorderWidth, TRUE, WindowBg, 0 );
			Release;
		END DrawBackground;
	END BevelPanel;
	
	BorderLabel* = OBJECT(WMStandardComponents.Label);
	
		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		VAR str : Utilities.String;
		BEGIN
			IF ~visible.Get() THEN RETURN END;
			Acquire;
			WMGraphicUtilities.DrawBevel(canvas, WMRectangles.ResizeRect(GetClientRect(), -1), 1, TRUE, BevelBgColor, WMGraphics.ModeCopy);
			str := caption.Get();
			IF str # NIL THEN
				canvas.SetColor(textColor.Get());
				WMGraphics.DrawStringInRect(canvas, WMRectangles.ResizeRect(GetClientRect(), -2), FALSE, alignH.Get(), alignV.Get(), str^)
			END;
			Release;
		END DrawBackground;
	END BorderLabel;
	
	NoWheelGrid* = OBJECT(WMStringGrids.StringGrid);
		PROCEDURE WheelMove*(dz : LONGINT); BEGIN (* do nothing *) END WheelMove;
	END NoWheelGrid;
	
	(* Special handling for Tab key *)
	CustomEditor = OBJECT(WMEditors.Editor);
		
		PROCEDURE KeyPressed*(ucs : LONGINT; flags : SET; VAR keySym : LONGINT; VAR handled : BOOLEAN);
		BEGIN
			IF keySym = 0FF09H THEN (* Tab *)				
			      (* TODO: Actually, I want to switch to the next editor here... *)
			      FocusNext;
			ELSE
				KeyPressed^(ucs, flags, keySym, handled);
			END;
		END KeyPressed;
		
		(* TODO: Does not work. Editor does not receive focus when clicked *)
		PROCEDURE FocusReceived*;
		BEGIN
			FocusReceived^;
			fillColor.Set(WMGraphics.White);
			Invalidate;
		END FocusReceived;
		
	END CustomEditor;
	
TYPE

	PartitionsPlugin* = OBJECT(AosPlugins.Plugin);
	VAR
		(** Usage: owner.UpdateStatusLabel(string : Utilities.String) updates the main window status bar *)
		owner- : Window;
		panel* : WMStandardComponents.Panel;
		selection* : Selection;
		
		(** This procedure is called everytime when the selection has been updated *)
		(** Return values: SelectionValid, SelectionInvalid, SelectionMaybe or SelectionNotSupported *)
		PROCEDURE SelectionUpdated*(selection : Selection) : LONGINT;
		BEGIN
			HALT(301); RETURN -1; (* abstract *)
		END SelectionUpdated;
		
		(** called whenever the size of the plugin panel changes *)
		PROCEDURE Resized*(width, height : LONGINT);
		BEGIN
			panel.bounds.SetExtents(width, height);
			panel.bounds.SetLeft(0); panel.bounds.SetTop(0);
		END Resized;
	
		(** Access to the operation panel of the plugin  *)
		PROCEDURE GetPanel*(width, height : LONGINT) : WMStandardComponents.Panel;
		BEGIN
			RETURN panel; 
		END GetPanel;
		
		(** Returns TRUE if the selection is valid *)
		PROCEDURE IsValid*(selection : Selection) : BOOLEAN;
		BEGIN
			RETURN (selection.disk.device#NIL) & (selection.partition >= 0) & (selection.disk.table#NIL) & (selection.partition < LEN(selection.disk.table));
		END IsValid;
		
		(** Returns TRUE if PartitionsPlugin.selection # selection *)
		PROCEDURE HasChanged*(selection : Selection) : BOOLEAN;
		BEGIN
			RETURN (SELF.selection.disk.device = selection.disk.device) & (SELF.selection.partition = selection.partition);
		END HasChanged;
	
		(** Called when the Partition Viewer window is closed *)
		PROCEDURE Finalize*;
		BEGIN
			(* optional *)
		END Finalize;
		
	END PartitionsPlugin;
	
TYPE
	
	Selection* = RECORD (AosPartitionsLib.Selection);
		SelectionState : LONGINT; (* SelectionValid, SelectionInvalid, SelectionMaybe or SelectionNotSupported*)
	END;
	
TYPE

	Disk = RECORD (AosPartitionsLib.Disk);
		panel : BevelPanel; (* disk panel: contains all other fields *)
		label : WMStandardComponents.Label; 
		buttons : POINTER TO ARRAY OF WMStandardComponents.Button; (* references to the partition buttons; *)
		mapping : POINTER TO ARRAY OF LONGINT; (* maps buttons[i] to correctly ordered partition number *)
		vtable : AosDisks.PartitionTable; (* virtual partition table (order different to disk.table, only used for graphical representation *)
		grid, titlegrid : NoWheelGrid; (* reference to grid (table); *)
	END;
	
	Disks = POINTER TO ARRAY OF Disk; (* no devices when NIL *)
	
TYPE
	
	(** Simple text view window *)
	ReportWindow* = OBJECT(WMComponents.FormWindow)
	VAR
		mainpanel : WMStandardComponents.Panel;
		panel : BevelPanel;
		textView : WMTextView.TextView;
		
		PROCEDURE Resized(width, height : LONGINT);
		BEGIN 
			Resized^(width, height);
			mainpanel.bounds.SetExtents(width, height);
		END Resized;
		
		PROCEDURE Show*;
		BEGIN
			WMWindowManager.ExtAddWindow(SELF, 100, 100, {WMWindowManager.FlagFrame});
			manager := WMWindowManager.GetDefaultManager ();
			manager.SetFocus(SELF);
			SetTitle(WMWindowManager.NewString("  Operation Status Report"));			
		END Show;
			
		PROCEDURE &New(text : AosTexts.Text;  width, height : LONGINT; visible : BOOLEAN);
		BEGIN
			Init^(width, height, visible); scaling := FALSE;
			
			NEW(mainpanel);
			mainpanel.bounds.SetExtents(width, height); mainpanel.bounds.SetLeft(0); mainpanel.bounds.SetTop(0);
			mainpanel.fillColor.Set(MainPanelMarginColor);
			
			NEW(panel); panel.alignment.Set(WMComponents.AlignClient);
			mainpanel.AddContent(panel); 
			
			NEW(textView); textView.alignment.Set(WMComponents.AlignClient);
			textView.isMultiLine.Set(TRUE); textView.showBorder.Set(FALSE);
			textView.alwaysShowCursor.Set(FALSE);
			
			textView.SetText(text);
			panel.AddContent(textView);
			
			SetContent(mainpanel);				
		END New;
	
	END ReportWindow;
	
TYPE
	
	(** Specifies a single parameter for the PopupWindow *)
	Parameter* = RECORD
		description* : ARRAY 32 OF CHAR;
		type* : LONGINT; (* ParInteger, ParString *)
		resInteger* : LONGINT;
		resString* : ARRAY 32 OF CHAR;
		resBoolean* : BOOLEAN;
		width* : LONGINT; (* width of editor field *)
		valid- : BOOLEAN; (* is the resInteger/resString value valid *)
		optional* : BOOLEAN; (* Ok possible width filling this parameter *)
		default* : BOOLEAN; (* if default is TRUE, the values of ResInteger/ResString is used as default value *)
	END;
	
	(** Parameters passed to PopupWindow via SetParameters() *)
	Parameters* = POINTER TO ARRAY OF Parameter;

	(** Pop up window capable of getting inputs specified with Parameters *)
	PopupWindow* = OBJECT(WMComponents.FormWindow)
	VAR
		mainpanel : WMStandardComponents.Panel;
		params : BevelPanel;
		ok, cancel : WMStandardComponents.Button;
		
		parameters : Parameters;
		editors : POINTER TO ARRAY OF CustomEditor; 
		boxes : POINTER TO ARRAY OF WMStandardComponents.Button;
		labelOffset : LONGINT;
	
		operationName, diskpartString : Utilities.String; 
		
		textView : WMTextView.TextView;
		text : AosTexts.Text;
		attr : AosTexts.Attributes;
		
		result : LONGINT;
		
		width, height : LONGINT; (* of this popup window *)
		
		PROCEDURE Resized(width, height : LONGINT);
		VAR i, ofs : LONGINT;
		BEGIN 
			Resized^(width, height);
			scaling := FALSE;
			SELF.width := width; SELF.height := height;
			mainpanel.bounds.SetExtents(width, height);
			params.bounds.SetExtents(width - 2*MainPanelMarginH, height - 3*MainPanelMarginV - ButtonHeight);
			ofs := (width - 2*ButtonWidth - ButtonSpacer) DIV 2;
			ok.bounds.SetLeft(ofs); ok.bounds.SetTop(height - MainPanelMarginV - ButtonHeight);
			cancel.bounds.SetLeft(ofs + ButtonWidth + ButtonSpacer); cancel.bounds.SetTop(height - MainPanelMarginV - ButtonHeight);
			IF text # NIL THEN textView.bounds.SetWidth(width - 2*MainPanelMarginH - 2*DiskPanelMarginH); END;
			IF parameters # NIL THEN
				FOR i := 0 TO LEN(parameters)-1 DO
					IF (parameters[i].type = ParInteger) OR (parameters[i].type = ParString) THEN 
						IF parameters[i].width = 0 THEN (* auto size *)
							editors[i].bounds.SetWidth(SELF.width - 2*MainPanelMarginH - 2*DiskPanelMarginH - labelOffset); 
						ELSE (* use specified size *)
							editors[i].bounds.SetWidth(parameters[i].width); 
						END;
					END;
				END;
			END;
		END Resized;
		
		(** Set text displayed by the PopupWindow as AosTexts.Text *)
		PROCEDURE SetText*(text : AosTexts.Text);
		BEGIN
			SELF.text := text;
		END SetText;
		
		(** Set text displayed by the PopupWindow as string *)
		PROCEDURE SetTextAsString*(string : ARRAY OF CHAR);
		BEGIN
			NEW(text); AosTextUtilities.StrToText(text, 0, string);
			text.AcquireWrite;
			text.SetAttributes(0, text.GetLength(), attr); 
			text.ReleaseWrite;
		END SetTextAsString;
		
		(** Pass parameters *)
		PROCEDURE SetParameters*(operationName  : ARRAY OF CHAR; selection : AosPartitionsLib.Selection; VAR parameters : Parameters);
		VAR string, temp : ARRAY 32 OF CHAR;
		BEGIN
			SELF.operationName := Utilities.NewString(operationName); 
			string := ""; Utilities.Append(string, selection.disk.device.name); 
			Utilities.IntToStr(selection.partition, temp); Utilities.Append(string, "#"); Utilities.Append(string, temp);
			diskpartString := Utilities.NewString(string);
			SELF.parameters := parameters;
		END SetParameters; 
	
		(** Show popup window at position (x,y); call is blocking; res = ResNone | ResCancel | ResOk *)
		PROCEDURE Popup*(x, y : LONGINT;  VAR res : LONGINT);
		VAR i : LONGINT; 
		BEGIN 
			BuildLayout;
			WMWindowManager.ExtAddWindow (SELF, x, y, {WMWindowManager.FlagFrame});
			IF editors # NIL THEN 
				i := 0; 
				LOOP 
					IF editors[i] # NIL THEN editors[i].SetFocus; EXIT; END;
					INC(i); 
					IF i >= LEN(editors) THEN EXIT; END;
				END;
			END;
			result := ResNone;
			BEGIN {EXCLUSIVE} AWAIT(result # ResNone); END;
			res := result;
		END Popup;
		
		PROCEDURE BuildLayout;
		CONST
			MinSpacer = 5;
			TextViewHeight = 50;
		VAR
			label : WMStandardComponents.Label;
			width, height, top, labelwidth, ofs : LONGINT;
			maxWidth, ignore : LONGINT;
			font : WMGraphics.Font;
			caption : ARRAY 128 OF CHAR;
			i : LONGINT;
		BEGIN
			mainpanel.bounds.SetExtents(SELF.width, SELF.height);
		
			width := SELF.width - 2*MainPanelMarginH - 2*DiskPanelMarginH; 
			height := SELF.height - 2*MainPanelMarginV - 2*DiskPanelMarginV - ButtonHeight;
			
			top := MainPanelMarginV + DiskPanelMarginV; height := 0;
			
			caption := ""; Utilities.Append(caption, operationName^); Utilities.Append(caption, " "); Utilities.Append(caption, diskpartString^);
			SetTitle(Utilities.NewString(caption));
			
			(* show PopupWindow text if there is any *)
			IF text # NIL THEN 
				NEW(textView);
				textView.bounds.SetExtents(width, TextViewHeight);
				textView.bounds.SetLeft(MainPanelMarginH + DiskPanelMarginH); textView.bounds.SetTop(top);
				textView.isMultiLine.Set(TRUE); textView.showBorder.Set(TRUE);
				textView.alwaysShowCursor.Set(FALSE);
				textView.SetText(text);
				mainpanel.AddContent(textView);
				textView.Reset(NIL, NIL);
				top := top + TextViewHeight + DiskPanelMarginV;
			END;
				
			IF parameters # NIL THEN 
				
				NEW(editors, LEN(parameters)); NEW(boxes, LEN(parameters));
				
				(* look for the widest string *)
				font := textView.GetFont(); maxWidth := 0;
				FOR i := 0 TO LEN(parameters) -1 DO
					font.GetStringSize(parameters[i].description, width, ignore); 
					IF width > maxWidth THEN maxWidth := width; END;
				END;
				
				labelOffset := maxWidth + MinSpacer;
					
				FOR i := 0 TO LEN(parameters)-1 DO
					
					(* parameter description *)
					NEW(label); labelwidth := maxWidth + MinSpacer;
					label.bounds.SetExtents(labelwidth, PopupLabelHeight); 
					label.bounds.SetLeft(DiskPanelMarginH); label.bounds.SetTop(top); 
					label.caption.Set(Utilities.NewString(parameters[i].description));
					params.AddContent(label);
					
					(* parameter input editor *)
					IF (parameters[i].type = ParInteger) OR (parameters[i].type = ParString) THEN 
						NEW(editors[i]);
						IF parameters[i].width = 0 THEN (* auto size *)
							editors[i].bounds.SetExtents(SELF.width - 2*MainPanelMarginH - 2*DiskPanelMarginH - labelwidth, PopupLabelHeight); 
						ELSE (* use specified size *)
							editors[i].bounds.SetExtents(parameters[i].width, PopupLabelHeight); 
						END;
						editors[i].bounds.SetLeft(labelwidth + DiskPanelMarginH); editors[i].bounds.SetTop(top);
						editors[i].multiLine.Set(FALSE);
						editors[i].tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); editors[i].tv.showBorder.Set(TRUE);
						editors[i].fillColor.Set(0FFFFFFFFH);
						editors[i].allowScrollbars.Set(FALSE);
						IF parameters[i].default THEN
							ASSERT((parameters[i].type = ParInteger) OR (parameters[i].type = ParString));
							IF parameters[i].type = ParInteger THEN
								Utilities.IntToStr(parameters[i].resInteger, caption);
								editors[i].SetAsString(caption);
							ELSE (* ParString *)
								editors[i].SetAsString(parameters[i].resString); 
							END;
						END;
						params.AddContent(editors[i]); 
						editors[i].Reset(NIL, NIL);						
					ELSIF parameters[i].type = ParBoolean THEN
						NEW(boxes[i]);
						boxes[i].bounds.SetExtents(PopupLabelHeight, PopupLabelHeight);
						boxes[i].bounds.SetLeft(labelwidth + DiskPanelMarginH); boxes[i].bounds.SetTop(top);
						boxes[i].onClick.Add(CheckboxHandler); 
						IF (parameters[i].default) & (parameters[i].resBoolean) THEN 
							boxes[i].caption.Set(Utilities.NewString("X"));
						ELSE
							boxes[i].caption.Set(Utilities.NewString(""));
						END;
						params.AddContent(boxes[i]);
					END;
			
					IF parameters[i].optional THEN
						NEW(label);
						label.bounds.SetExtents(45, PopupLabelHeight); 
						label.bounds.SetLeft(labelwidth + parameters[i].width + 2*DiskPanelMarginH); label.bounds.SetTop(top); 
						label.caption.Set(Utilities.NewString("(optional)"));				
					END;
					top := top + PopupLabelHeight + DiskPanelMarginV;
				END;
			END;
			params.bounds.SetExtents(SELF.width - 2*MainPanelMarginH, SELF.height - ButtonHeight - 3*MainPanelMarginV);
			ofs := (SELF.width - 2*MainPanelMarginH - 2*DiskPanelMarginH - 2*ButtonWidth - ButtonSpacer) DIV 2;
			top := SELF.height - ButtonHeight - MainPanelMarginV;
			ok.bounds.SetLeft(ofs); ok.bounds.SetTop(top);
			cancel.bounds.SetLeft(ofs + ButtonWidth + ButtonSpacer); cancel.bounds.SetTop(top);
		END BuildLayout;
		
		PROCEDURE EvalParameters() : BOOLEAN;
		VAR  result : BOOLEAN; string : ARRAY 32 OF CHAR; temp : Utilities.String; i : LONGINT;
		BEGIN
			IF parameters=NIL THEN result := TRUE;
			ELSE
				result := TRUE;
				FOR i := 0 TO LEN(parameters)-1 DO
					IF (parameters[i].type = ParString) OR (parameters[i].type = ParInteger) THEN 
						editors[i].GetAsString(string);
						IF string # "" THEN 
							parameters[i].valid := TRUE;
							IF parameters[i].type = ParInteger THEN
								Utilities.StrToInt(string, parameters[i].resInteger); 
							ELSIF parameters[i].type = ParString THEN
								parameters[i].resString := ""; Utilities.Append(parameters[i].resString, string);
							END;
							editors[i].fillColor.Set(WMGraphics.White);
						ELSIF ~parameters[i].optional THEN 
							editors[i].fillColor.Set(WMGraphics.Red);
							result := FALSE; 
						END;
					ELSIF parameters[i].type = ParBoolean THEN
						temp := boxes[i].caption.Get();
						parameters[i].valid := TRUE;
						parameters[i].resBoolean := temp^ = "X";
					END;
				END;		
			END;
			RETURN result;
		END EvalParameters;
		
		PROCEDURE CheckboxHandler(sender, data : PTR);
		VAR
			checkbox : WMStandardComponents.Button;
			string : Utilities.String;
			i : LONGINT;
		BEGIN
			checkbox := sender (WMStandardComponents.Button);
			FOR i := 0 TO LEN(boxes)-1 DO
				IF boxes[i]=checkbox THEN
					string := checkbox.caption.Get();
					IF string^ = "X" THEN string := Utilities.NewString(""); ELSE string := Utilities.NewString("X"); END;
					checkbox.caption.Set(string);
					checkbox.Reset(NIL, NIL);
				END;
			END;
		END CheckboxHandler;
		
		PROCEDURE Ok(sender, data : PTR);
		BEGIN 
			IF EvalParameters() THEN 
				BEGIN {EXCLUSIVE} result := ResOk; END;
				Close^; 
			ELSE
				CSChanged; (* force redraw *)
			END;
		END Ok;
		
		PROCEDURE Cancel(sender, data : PTR);
		BEGIN
			Close^; BEGIN {EXCLUSIVE} result := ResCancel; END; 
		END Cancel;
		
		PROCEDURE Close;
		BEGIN
			Close^; BEGIN {EXCLUSIVE} result := ResCancel; END;
		END Close;
		
		PROCEDURE &Init(width, height : LONGINT; alpha : BOOLEAN);
		BEGIN
			SELF.width := width; SELF.height := height; scaling := FALSE;	
			Init^(width, height, alpha);
			
			NEW(mainpanel);
			mainpanel.bounds.SetExtents(width, height);
			mainpanel.bounds.SetLeft(0); mainpanel.bounds.SetTop(0);
			mainpanel.fillColor.Set(MainPanelMarginColor);
			
			NEW(params);
			params.bounds.SetExtents(width - 2*MainPanelMarginH, height - 3*MainPanelMarginV  - ButtonHeight);
			params.bounds.SetLeft(MainPanelMarginH); params.bounds.SetTop(MainPanelMarginV);
			mainpanel.AddContent(params);
			
			NEW(ok);
			ok.bounds.SetExtents(ButtonWidth, ButtonHeight);
			ok.onClick.Add(Ok); ok.caption.Set(Utilities.NewString("Ok"));
			mainpanel.AddContent(ok);

			NEW(cancel);
			cancel.bounds.SetExtents(ButtonWidth, ButtonHeight);
			cancel.onClick.Add(Cancel); cancel.caption.Set(Utilities.NewString("Cancel"));
			mainpanel.AddContent(cancel);
			
			NEW(attr); attr.color := WMGraphics.Black; attr.bgcolor := WindowBg;
			
			SetContent(mainpanel);				
		END Init;
	
	END PopupWindow;

TYPE

	ButtonArray = POINTER TO ARRAY OF WMStandardComponents.Button;
	
TYPE

	DiskModel = OBJECT
	VAR
		disks : Disks;
		diskmodel : AosPartitionsLib.DisksModel;
		
		locked : BOOLEAN; (* Access via Acquire/Release only *)
		
		PROCEDURE Acquire*;
		BEGIN {EXCLUSIVE}
			AWAIT(locked = FALSE);
			locked := TRUE;
		END Acquire;
		
		PROCEDURE Release*;
		BEGIN {EXCLUSIVE}
			locked := FALSE;
		END Release;
		
		(** Synchronize to AosPartitionsLib.DiskModel. 
		 * force: Force the latter being updated 
		 * disk: Just update this disk 
		 * diskValid: disk parameter valid?
		 *)
		PROCEDURE Synchronize;
		VAR i : LONGINT;
		BEGIN (* diskModel must be locked *)
			diskmodel.Acquire;
			NEW(disks, LEN(diskmodel.disks));
			FOR i := 0 TO LEN(disks)-1 DO
				(* copy information from disk model *)
				disks[i].device := diskmodel.disks[i].device;
				disks[i].isDiskette := diskmodel.disks[i].isDiskette;
				disks[i].table := diskmodel.disks[i].table;
				disks[i].size := diskmodel.disks[i].size; disks[i].res := diskmodel.disks[i].res;
				disks[i].geo := diskmodel.disks[i].geo; disks[i].gres := diskmodel.disks[i].gres;
				disks[i].fs := diskmodel.disks[i].fs;
			END;
			diskmodel.Release;
		END Synchronize;		
				
		PROCEDURE &Init(dm : AosPartitionsLib.DisksModel);
		BEGIN
			ASSERT(dm # NIL);
			SELF.diskmodel := dm;
		END Init;

	END DiskModel;
	
TYPE

	Window = OBJECT(WMComponents.FormWindow)
	VAR
		dm : DiskModel;
		diskmodel : AosPartitionsLib.DisksModel;
		selection : Selection; (* current selection *)
		
		pluginTable : AosPlugins.Table; (* installed PartitionsPlugins *)
		pluginButtons : ButtonArray;
		
		(* The mainpanel contains the upperpanel, operationPanel & statusBar *)
		mainpanel: WMStandardComponents.Panel; 
		
		(* upper panel: graphical and textual representation of the Disks & Operations*)
		upperpanel : WMStandardComponents.Panel; 
	
		diskOverviewScrollPanel : WMStandardComponents.Panel; (* contains diskOverviewPanel *)
		scrollbarX, scrollbarY : WMStandardComponents.Scrollbar;
		scrollX, scrollY : LONGINT; (* current position of scrollbars *)
		diskOverviewPanel : WMStandardComponents.Panel; (* graphical & textual representation of disks *)
		
		lowerpanel : WMStandardComponents.Panel; (* textual representation of Pending operations *)

		operationspanel : WMStandardComponents.Panel; (* contains opScollBarX/Y, oppanel *)
		opScrollbarX, opScrollbarY : WMStandardComponents.Scrollbar;
		oppanel : WMStandardComponents.Panel; (* contains panel of PendingOperations plugin *)
		
		(* operation panel *)
		operationPanel : BevelPanel;
		selectionLabel : WMStandardComponents.Label; (* show the current selection *)
		selectionState : WMStandardComponents.Panel; (* indicates selection state (SelectionValid, SelectionInvalid, SelectionMaybe or SelectionNotSupported*)
		selectedPanel : WMStandardComponents.Panel; (* reference to the panel of the currently selected PartitionsPlugin*)
		selectedPlugin : PartitionsPlugin; (* currently selected plugin, NIL if no plugin is selected *)
		refresh, showdetails : WMStandardComponents.Button;
		showDetails : BOOLEAN; (* state of the showdetails button *)
		pluginPanel : WMStandardComponents.Panel; (* contains selectedPanel *)
		(* dummy panel if no plugin is installed *)
		noPlugins : WMStandardComponents.Panel;
		noPluginsLabel : WMStandardComponents.Label;
		
		(* status bar *)
		statusBar : WMStandardComponents.Panel; (* contains statusLabel *)
		statusLabel : WMStandardComponents.Label;
		
		titleGrid : NoWheelGrid; (* prototype; for layouting only *)
		
		maxWidths : ARRAY DiskOverviewTableColumns OF LONGINT; (* maximum cell widths per column*)
		maxHeight : LONGINT; (* maximum height of test *)
		minWidth, minHeight : LONGINT; (* of the diskoverview panel *)
		
		width, height : LONGINT; (* caches "window size"; needed for correct update when downscaled *)
	
		PROCEDURE Resized(width, height : LONGINT);
		BEGIN
			IF (width >= WindowMinWidth) & (height >= WindowMinHeight) THEN 
				scaling := FALSE; 
				SELF.width := width; SELF.height := height;
				dm.Acquire;
				UpdateLayout(width, height, FALSE); 
				dm.Release;
			ELSE 
				scaling := TRUE; 
			END; 
			Resized^(width, height);
		END Resized;

		(** Set string displayed by the Partition Viewer's status bar *)
		PROCEDURE UpdateStatusLabel*(string : Utilities.String);
		BEGIN
			statusLabel.caption.Set(string);
		END UpdateStatusLabel;
		
		PROCEDURE BuildOperationPanel() : WMStandardComponents.Panel;
		VAR
			button : WMStandardComponents.Button;
			plugin : PartitionsPlugin;
			i : LONGINT;
		BEGIN
			NEW(operationPanel); operationPanel.fillColor.Set(OperationPanelBgColor); 
		
			NEW(showdetails);
			showdetails.alignment.Set(WMComponents.AlignNone); 
			showdetails.isToggle.Set(TRUE); showdetails.onClick.Add(ShowDetails); 
			showdetails.caption.Set(Utilities.NewString("Show Details"));
			operationPanel.AddContent(showdetails);
			
			NEW(refresh);
			refresh.alignment.Set(WMComponents.AlignNone); 
			refresh.onClick.Add(Refresh); refresh.caption.Set(Utilities.NewString("Refresh"));
			operationPanel.AddContent(refresh);
			
			plugins.GetAll(pluginTable); 
			IF pluginTable # NIL THEN	
				NEW(pluginButtons, LEN(pluginTable));
				FOR i := 0 TO LEN(pluginTable)-1 DO
					plugin := pluginTable[i] (PartitionsPlugin);
					IF plugin IS PendingOperations THEN 
						ASSERT(plugin.panel#NIL);
						oppanel := plugin(PendingOperations).GetOpPanel();
						operationspanel.AddContent(oppanel);
					END;
					plugin.owner := SELF;
					NEW(button);
					button.alignment.Set(WMComponents.AlignNone); 
					button.isToggle.Set(TRUE); button.onClick.Add(PluginHandler);
					button.caption.Set(Utilities.NewString(plugin.name));
					button.clDefault.Set(PluginButtonColor);
					IF (selectedPlugin = plugin) THEN button.SetPressed(TRUE); END;
					operationPanel.AddContent(button);
					pluginButtons[i] := button;
				END;
			END;
		
			NEW(selectionState); selectionState.fillColor.Set(WindowBg);
			operationPanel.AddContent(selectionState);
			 
			NEW(selectionLabel); selectionLabel.fillColor.Set(SelectionLabelBgColor);
			selectionLabel.alignV.Set(WMGraphics.AlignCenter);
			operationPanel.AddContent(selectionLabel);
			
			NEW(pluginPanel); pluginPanel.alignment.Set(WMComponents.AlignNone);
			pluginPanel.fillColor.Set(PluginPanelBgColor);
		
			IF selectedPanel # NIL THEN 
				selectedPanel.bounds.SetExtents(pluginPanel.bounds.GetWidth(), pluginPanel.bounds.GetHeight());
				pluginPanel.AddContent(selectedPanel); 
			END;
			operationPanel.AddContent(pluginPanel);
			RETURN operationPanel;
		END BuildOperationPanel;
	
		PROCEDURE PluginHandler(sender, data : PTR);
		VAR
			button : WMStandardComponents.Button;
			plugin : PartitionsPlugin;
			i, j : LONGINT;
		BEGIN (* {EXCLUSIVE} (* lock pluginTable & pluginButtons *)  *)
			ASSERT(pluginButtons#NIL);
			button := sender (WMStandardComponents.Button);
			i := 0; WHILE (i < LEN(pluginButtons)) & (pluginButtons[i] # button) DO INC(i); END;
			IF i < LEN(pluginButtons) THEN (* button found *)
				plugin := pluginTable[i] (PartitionsPlugin);
				IF plugin # selectedPlugin THEN
					selectedPlugin := plugin;
					ASSERT(selectedPlugin#NIL);	
					plugin.owner := SELF;
					pluginPanel.RemoveContent(selectedPanel);
					selectedPanel := plugin.GetPanel(pluginPanel.bounds.GetWidth(), pluginPanel.bounds.GetHeight());
					pluginPanel.AddContent(selectedPanel);
					selection.SelectionState := plugin.SelectionUpdated(selection);
					CASE selection.SelectionState OF
						SelectionValid : selectionState.fillColor.Set(WMGraphics.Green);
						|SelectionInvalid : selectionState.fillColor.Set(WMGraphics.Red);
						|SelectionMaybe : selectionState.fillColor.Set(WMGraphics.Yellow);
						|SelectionNotSupported : selectionState.fillColor.Set(WindowBg);
					ELSE
						selectionState.fillColor.Set(WindowBg);
					END;
					CSChanged;
				END;
				FOR j := 0 TO LEN(pluginButtons)-1 DO
					IF i # j THEN pluginButtons[j].SetPressed(FALSE); ELSE pluginButtons[j].SetPressed(TRUE); END;
				END;
				CSChanged;
			ELSE 
				HALT(99);
			END;
		END PluginHandler;
		
		PROCEDURE ShowDetails(sender, data : PTR);
		BEGIN
			IF showDetails THEN showDetails := FALSE; ELSE showDetails := TRUE; END;
			scrollbarY.pos.Set(0); scrollY := 0;
			dm.Acquire;
			UpdateLayout(width, height, FALSE);  
			dm.Release;
			diskOverviewPanel.bounds.SetTop(0);
		 	CSChanged; 
		END ShowDetails;
		
		PROCEDURE Refresh(sender, data : PTR);
		BEGIN
			scrollX := 0; scrollY := 0;
			diskmodel.Update; (* Will call DiskEventHandler callback *)
		END Refresh;
		
		PROCEDURE ScrollY(sender, data : PTR);
		VAR y : WMProperties.Int32Property;
		BEGIN
			IF data # NIL THEN y := data (WMProperties.Int32Property); scrollY := y.Get(); END;
			diskOverviewPanel.bounds.SetTop(-scrollY);
		END ScrollY;
		
		PROCEDURE ScrollX(sender, data : PTR);
		VAR x : WMProperties.Int32Property;
		BEGIN
			IF data # NIL THEN x := data (WMProperties.Int32Property); scrollX := x.Get(); END;
			diskOverviewPanel.bounds.SetLeft(-scrollX);
		END ScrollX;
		
		PROCEDURE OpScrollY(sender, data : PTR);
		VAR y : WMProperties.Int32Property;
		BEGIN
			y := data (WMProperties.Int32Property);
			oppanel.bounds.SetTop(-y.Get());
		END OpScrollY;
		
		PROCEDURE OpScrollX(sender, data : PTR);
		VAR x : WMProperties.Int32Property;
		BEGIN
			x := data (WMProperties.Int32Property);
			oppanel.bounds.SetLeft(-x.Get());
		END OpScrollX;
		
		PROCEDURE WheelMove*(dz : LONGINT);
		VAR pos : LONGINT;
		BEGIN
			IF scrollbarY.visible.Get() THEN
				pos := scrollbarY.pos.Get() + Multiplier*dz;
				IF pos < scrollbarY.min.Get() THEN pos := scrollbarY.min.Get(); END;
				IF pos > scrollbarY.max.Get() THEN pos := scrollbarY.max.Get(); END;
				scrollbarY.pos.Set(pos);
				scrollbarY.onPositionChanged.Call(scrollbarY.pos)
			END;
		END WheelMove; 
		
		PROCEDURE GridClicked(sender, x : ANY);
		VAR ignore, row, i : LONGINT; grid : NoWheelGrid;
		BEGIN 
			grid := sender (NoWheelGrid);
			grid.GetSelection(ignore, row, ignore, ignore);	
			dm.Acquire;
			i := 0;
			LOOP
				IF dm.disks[i].grid = grid THEN UpdateSelection(i, row); EXIT END;
				INC(i); IF i >= LEN(dm.disks) THEN EXIT; END;
			END;
			dm.Release;
		END GridClicked;
		
		PROCEDURE UpdateDiskOverview(disk : Disk;  top : LONGINT; updateContent : BOOLEAN): WMStandardComponents.Panel;
		VAR 
			height : LONGINT;
			msg : ARRAY 32 OF CHAR;
			(* updateContent variables *)
			dev : AosDisks.Device;
			string : Utilities.String;
			caption, temp : ARRAY 128 OF CHAR;	
		BEGIN (* CALLER MUST HOLD dm.locked *)
			ASSERT(disk.panel#NIL);
			disk.panel.bounds.SetExtents(diskOverviewPanel.bounds.GetWidth() - 2*MainPanelMarginH , height); 
			disk.panel.bounds.SetLeft(MainPanelMarginH); disk.panel.bounds.SetTop(top); 
			disk.panel.fillColor.Set(DiskOverviewPanelBgColor);
			
			disk.label.bounds.SetExtents(disk.panel.bounds.GetWidth() - 2*DiskOverviewPanelMarginH, LabelHeight);
			disk.label.bounds.SetLeft(DiskOverviewPanelMarginH); disk.label.bounds.SetTop(DiskOverviewPanelMarginV);
		
			IF updateContent THEN
				ASSERT(disk.device #NIL ); dev := disk.device;
				Utilities.Append(caption, dev.name); Utilities.Append(caption, " ("); Utilities.Append(caption, dev.desc); Utilities.Append(caption, ")");			
				IF AosDisks.ReadOnly IN dev.flags THEN Utilities.Append(caption, ", readonly"); END;
				IF AosDisks.Removable IN dev.flags THEN Utilities.Append(caption, ", removable"); END;
			END;
			
			IF (disk.table # NIL) THEN 
			
				IF updateContent THEN 
					Utilities.Append(caption,", Size: " );
					IF disk.res = AosDisks.Ok THEN 
						string := GetSizeString(disk.size, dev.blockSize);
					ELSE 
						string := Utilities.NewString("GetSize Error");
					END;
					Utilities.Append(caption, string^);
					Utilities.IntToStr(dev.openCount, temp); Utilities.Append(caption, ", Open count: "); Utilities.Append(caption, temp);
					
					IF ShowDiskGeometry THEN
						IF disk.gres # AosDisks.MediaMissing THEN						
							Utilities.Append(caption, ", CHS: ");
							IF disk.gres = AosDisks.Ok THEN
								Utilities.IntToStr(disk.geo.cyls, temp); Utilities.Append(caption, temp); Utilities.Append(caption, "x");
								Utilities.IntToStr(disk.geo.hds, temp); Utilities.Append(caption, temp); Utilities.Append(caption, "x");
								Utilities.IntToStr(disk.geo.spt, temp); Utilities.Append(caption, temp);
							ELSE
								Utilities.Append(caption, AosPartitionsLib.GetErrorMsg("Unknown", disk.gres));
							END;
						END;
					END;

					disk.label.caption.Set(Utilities.NewString(caption));
				END;
				
				UpdateDiskPanel(disk);
			
				height :=  2*DiskOverviewPanelMarginV + LabelHeight + DiskPanelHeight;
			
				IF showDetails & (disk.grid#NIL) THEN 
	 			  	ASSERT(disk.titlegrid#NIL);
					disk.titlegrid.bounds.SetLeft(DiskOverviewPanelMarginH); disk.titlegrid.bounds.SetTop(height); 
					SetGridBounds(disk.titlegrid); 
					height := height + disk.titlegrid.bounds.GetHeight();
					disk.grid.bounds.SetLeft(DiskOverviewPanelMarginH); disk.grid.bounds.SetTop(height);
					SetGridBounds(disk.grid); 
					height := height + disk.grid.bounds.GetHeight() + DiskOverviewPanelMarginV;
					disk.grid.visible.Set(TRUE);
					disk.titlegrid.visible.Set(TRUE);
				ELSIF disk.grid # NIL THEN
					disk.grid.visible.Set(FALSE);
					disk.titlegrid.visible.Set(FALSE);
				END; 
				disk.panel.bounds.SetExtents(diskOverviewPanel.bounds.GetWidth() - 2*MainPanelMarginH , height); 
			ELSE
				IF updateContent THEN 
					IF  disk.res = AosDisks.MediaMissing THEN  
						msg := "No Media"; 
					ELSE
						Utilities.IntToStr(disk.res, temp);
						msg := "Error: "; Utilities.Append(msg, temp);
					END;
					disk.label.caption.Set(Utilities.NewString(caption));
					disk.buttons[0].caption.Set(Utilities.NewString(msg));
				END;
				
				(* update empty disk panel (no partition table) *)
				disk.buttons[0].bounds.SetExtents(diskOverviewPanel.bounds.GetWidth() - 2*MainPanelMarginH - 2*DiskOverviewPanelMarginH, DiskPanelHeight);
				disk.buttons[0].bounds.SetLeft(DiskOverviewPanelMarginH); disk.buttons[0].bounds.SetTop(DiskOverviewPanelMarginV + LabelHeight);
				
				height := DiskPanelHeight + LabelHeight + 2*DiskOverviewPanelMarginV;			
				disk.panel.bounds.SetExtents(diskOverviewPanel.bounds.GetWidth() - 2*MainPanelMarginH , height);  
			END;
			RETURN disk.panel;
		END UpdateDiskOverview;
		
		(* changes the order of the partition of disk.table so that it's sequential *)
		PROCEDURE BuildVTable(VAR disk : Disk);
		VAR part, i : LONGINT; isIncluded : POINTER TO ARRAY OF BOOLEAN;
			
			PROCEDURE GetNext(lastStart : LONGINT) : LONGINT;
			VAR i, min, next : LONGINT;
			BEGIN
				min := MAX(LONGINT);
				FOR i := 1 TO LEN(disk.table)-1 DO
					(* Note: Extended partitions that do not contain logical drives will be found twice: The extended partition and a pseudo *)
					(* partition (free) with the same boundaries -> Therefor, isIncluded is used *)
					IF ~isIncluded[i] & (disk.table[i].start >= lastStart) & (disk.table[i].start < min) THEN min := disk.table[i].start; next := i; END;
				END;
				ASSERT((next > 0) & (next < LEN(disk.table)));
				RETURN next; 
		 	END GetNext;
		 	
		BEGIN (* CALLER MUST HOLD dm.locked *)
			IF disk.table # NIL THEN
				NEW(disk.vtable, LEN(disk.table)); NEW(disk.mapping, LEN(disk.table)); NEW(isIncluded, LEN(disk.table));
				disk.vtable[0] := disk.table[0]; disk.mapping[0] := 0; (* whole disk;  not mapped *)
				IF LEN(disk.table) > 1 THEN
					FOR i := 1 TO LEN(disk.vtable)-1 DO
						part := GetNext(disk.vtable[i-1].start);
						isIncluded[part] := TRUE;
						disk.vtable[i] := disk.table[part];
						disk.mapping[i] := part;
					END;
				END;
			ELSE
				disk.vtable := NIL;
			END;
		END BuildVTable;
		
		PROCEDURE BuildDiskPanel(VAR disk  : Disk): WMStandardComponents.Panel;
		VAR
			diskSelected : BOOLEAN;
			fillColor : LONGINT;
			text : ARRAY 32 OF CHAR;  
			logical : LONGINT; (* nbr of logical partitions on disk *) 
			i, k : LONGINT;
		BEGIN (* CALLER MUST HOLD dm.locked *)
			BuildVTable(disk);
			(* disk.buttons[0]: representation of "whole disk" *)
			(* disk.buttons[i]: primary or extended partitions *)
			IF (disk.vtable # NIL) THEN
			
				AosPartitionsLib.WriteType(disk.vtable[0].type, text, fillColor); (* get whole disk color *)
		
				IF selection.disk.device = disk.device THEN diskSelected := TRUE; ELSE diskSelected := FALSE; END;
				disk.buttons[0].onClick.Add(DiskPanelHandler);
				disk.buttons[0].clDefault.Set(fillColor);
				disk.buttons[0].isToggle.Set(TRUE);
				disk.buttons[0].useBgBitmaps.Set(FALSE);
				
				IF diskSelected & (selection.partition = 0) THEN disk.buttons[0].SetPressed(TRUE); END;
	
				i := 1;
				WHILE i < LEN(disk.vtable) DO (* draw bar for each partition *);
				
					AosPartitionsLib.WriteType(disk.vtable[i].type, text, fillColor); 
	
					IF ((disk.vtable[i].type = 15) OR (disk.vtable[i].type=5)) & (disk.vtable[i].flags * {AosDisks.Primary} = {AosDisks.Primary}) THEN (* it's an extended partition *)
					
						disk.buttons[i].clDefault.Set(fillColor); disk.buttons[i].isToggle.Set(TRUE);
						disk.buttons[i].onClick.Add(DiskPanelHandler);
						disk.buttons[i].useBgBitmaps.Set(FALSE);
						
						IF diskSelected & (selection.partition = i) THEN disk.buttons[i].SetPressed(TRUE); END;
						
						(* how many logical drives does the extented partition contain? *)
						logical := 0;
						WHILE(i+logical+1 < LEN(disk.vtable)) & (disk.vtable[i+logical+1].flags * {AosDisks.Primary} = {}) DO
							INC(logical);	
						END;
	
						IF logical > 0 THEN (* extended partition contains at least one logical drive *)
								FOR k := 1 TO logical DO
									AosPartitionsLib.WriteType(disk.vtable[i+k].type, text, fillColor); 
						
									disk.buttons[i+k].clDefault.Set(fillColor); 
									disk.buttons[i+k].isToggle.Set(TRUE);
									disk.buttons[i+k].onClick.Add(DiskPanelHandler);
									disk.buttons[i+k].useBgBitmaps.Set(FALSE);
								
									IF diskSelected & (selection.partition = i+k) THEN disk.buttons[i+k].SetPressed(TRUE); END;
		
									disk.buttons[i].AddContent(disk.buttons[i+k]); (* add logical drives to extended partition *)					
								END;
						END;
					
						(* Add extended partition to whole disk *)
						disk.buttons[0].AddContent(disk.buttons[i]); 
						i := i + 1 + logical;
					
					ELSE (* It's a primary partition *)
						disk.buttons[i].clDefault.Set(fillColor);
						disk.buttons[i].isToggle.Set(TRUE);
						disk.buttons[i].onClick.Add(DiskPanelHandler);	
						disk.buttons[i].useBgBitmaps.Set(FALSE);
						IF diskSelected & (selection.partition = i) THEN disk.buttons[i].SetPressed(TRUE); END;
						(* add primary partition to whole disk *)
						disk.buttons[0].AddContent(disk.buttons[i]);
						INC(i);
					END;
				END;	
			ELSE (* unpartitioned space or unpartitioned device *)
				AosPartitionsLib.WriteType(-1, text, fillColor); (* get color of unallocated space *)
				disk.buttons[0].clDefault.Set(fillColor); 
				disk.buttons[0].clTextDefault.Set(WMGraphics.Black);
				disk.buttons[0].isToggle.Set(TRUE);
				disk.buttons[0].onClick.Add(DiskPanelHandler);
				disk.buttons[0].useBgBitmaps.Set(FALSE);
				IF diskSelected & (selection.partition = 0) THEN disk.buttons[0].SetPressed(TRUE); END;
			END;
			disk.panel.AddContent(disk.buttons[0]);
			RETURN disk.panel;
		END BuildDiskPanel;
		
		PROCEDURE UpdateDiskPanel(disk  : Disk);
		VAR
			width, offset, extWidth, extOffset, totalWidth, extTotalWidth : LONGINT;
			fillColor : LONGINT;
			text : ARRAY 32 OF CHAR;  
			primary, logical : LONGINT; (* nbr of primary/logical partitions on disk *)
			i, k : LONGINT;
		BEGIN (* CALLER MUST HOLD dm.locked *)
			disk.buttons[0].bounds.SetExtents(diskOverviewPanel.bounds.GetWidth() - 2*MainPanelMarginH - 2*DiskOverviewPanelMarginH, DiskPanelHeight);
			disk.buttons[0].bounds.SetLeft(DiskOverviewPanelMarginH); disk.buttons[0].bounds.SetTop(DiskOverviewPanelMarginV + LabelHeight);
			
			(* For the case we deal with an unpartitioned device which is mounted *)
			IF (disk.table # NIL) & (LEN(disk.table) = 1) & (disk.fs#NIL) & (disk.fs[0] # NIL) THEN 
				disk.buttons[0].caption.Set(Utilities.NewString(disk.fs[0].prefix)); 
			END;				
			
			(* how many primary partitions does the drive contain? (needed for layout only) *)
			primary := 0; 
			FOR i := 1 TO LEN(disk.vtable)-1 DO (* table[0] is whole disk *) (* should also count reserved / free *)
				IF disk.vtable[i].flags * {AosDisks.Primary} # {} THEN INC(primary) END;
			END;		
			
			(* the graphical representation of some partition may have to be enlarged to PanelMinWidth... how many pixels are added? (Layouting) *)
			totalWidth :=disk.buttons[0].bounds.GetWidth() - 2*DiskPanelMarginH - (primary-1)*DiskPanelSpacer; 
			
			i := 1;
			WHILE i < LEN(disk.vtable) DO
			
				IF disk.vtable[i].type = 15 THEN
					WHILE (i+1 < LEN(disk.vtable)) & (disk.vtable[i+1].flags * {AosDisks.Primary} = {}) DO INC(i); END; (* skip logical drives *)
				END;
				width := ENTIER((disk.vtable[i].size / disk.vtable[0].size) * totalWidth);
				IF width < PanelMinWidth THEN 
					totalWidth := totalWidth - (PanelMinWidth - width);
				END;
				INC(i);
			END; 
			
			offset := DiskPanelMarginH;
		
			i := 1;
			WHILE i < LEN(disk.vtable) DO (* draw bar for each partition *);
				
				width := ENTIER((disk.vtable[i].size / disk.vtable[0].size) * totalWidth);
				IF width < PanelMinWidth THEN width := PanelMinWidth; END;
			
				AosPartitionsLib.WriteType(disk.vtable[i].type, text, fillColor); 

				IF ((disk.vtable[i].type = 15) OR (disk.vtable[i].type=5)) & (disk.vtable[i].flags * {AosDisks.Primary} = {AosDisks.Primary}) THEN (* it's an extended partition *)
				
					disk.buttons[i].bounds.SetExtents(width, DiskPanelHeight - 2*DiskPanelMarginV);
					disk.buttons[i].bounds.SetLeft(offset); disk.buttons[i].bounds.SetTop(DiskPanelMarginV);
						
					(* how many logical drives does the extented partition contain? *)
					logical := 0;
					WHILE(i+logical+1 < LEN(disk.vtable)) & (disk.vtable[i+logical+1].flags * {AosDisks.Primary} = {}) DO
						INC(logical);	
					END;
					
					extTotalWidth := + disk.buttons[i].bounds.GetWidth() - 2*DiskPanelMarginH-(logical-1)*DiskPanelSpacer;
				
					logical := 0;
					WHILE(i+logical+1 < LEN(disk.vtable)) & (disk.vtable[i+logical+1].flags * {AosDisks.Primary} = {}) DO
						extWidth := ENTIER((disk.vtable[i+logical+1].size / disk.vtable[i].size) * extTotalWidth);
						IF extWidth < PanelMinWidth THEN
							extTotalWidth := extTotalWidth - (PanelMinWidth - extWidth);
						END;
						INC(logical);	
					END;
					
					IF logical > 0 THEN (* extended partition contains at least one logical drive *)
					
							extOffset := DiskPanelMarginH;
							
							FOR k := 1 TO logical DO
								extWidth := ENTIER((disk.vtable[i+k].size / disk.vtable[i].size) * extTotalWidth);
								IF extWidth < PanelMinWidth THEN
									extWidth := PanelMinWidth;
								END;
								
								AosPartitionsLib.WriteType(disk.vtable[i+k].type, text, fillColor); 
								disk.buttons[i+k].clDefault.Set(fillColor);
								disk.buttons[i+k].bounds.SetExtents(extWidth, disk.buttons[i].bounds.GetHeight() - 2*DiskPanelMarginV);
								disk.buttons[i+k].bounds.SetLeft(extOffset); disk.buttons[i+k].bounds.SetTop(DiskPanelMarginV);
				
								IF (disk.fs#NIL) & (disk.mapping[i+k] < LEN(disk.fs)) & (disk.fs[disk.mapping[i+k]]#NIL) THEN
									disk.buttons[i+k].caption.Set(Utilities.NewString(disk.fs[disk.mapping[i+k]].prefix)); 
								END;
				
								extOffset := extOffset + extWidth + DiskPanelSpacer;
							END;
					END;
					
					offset := offset + width + DiskPanelSpacer;
					i := i + 1 + logical;
					
				ELSE (* It's a primary partition *)
					disk.buttons[i].clDefault.Set(fillColor);
					disk.buttons[i].bounds.SetExtents(width, DiskPanelHeight - 2*DiskPanelMarginV);
					disk.buttons[i].bounds.SetLeft(offset); disk.buttons[i].bounds.SetTop(DiskPanelMarginV);
					
					IF (disk.fs#NIL) & (disk.mapping[i] < LEN(disk.fs)) & (disk.fs[disk.mapping[i]]#NIL) THEN 
						disk.buttons[i].caption.Set(Utilities.NewString(disk.fs[disk.mapping[i]].prefix)); 
					END;
					
					offset := offset + width + DiskPanelSpacer;
					INC(i);
				END;
			END;	
		END UpdateDiskPanel;
		
		PROCEDURE DiskPanelHandler(owner, par : PTR);
		VAR
			found : BOOLEAN;
			disk, partition : LONGINT;
			button : WMStandardComponents.Button;
		BEGIN
			button := owner (WMStandardComponents.Button); found := FALSE; 
			dm.Acquire;
			disk := 0;
			LOOP
				IF dm.disks[disk].buttons#NIL THEN 
					partition := 0;
					LOOP
						IF dm.disks[disk].buttons[partition] = button THEN 
							found := TRUE; 
						END;
						IF found OR (dm.disks[disk].table = NIL) OR (partition >= LEN(dm.disks[disk].table)-1) THEN EXIT END;
						INC(partition);
					END;
				END;
				IF found OR (disk >= LEN(dm.disks)-1) THEN EXIT END;
				INC(disk);
			END;
			IF dm.disks[disk].table # NIL THEN partition := dm.disks[disk].mapping[partition]; END; (* map to oberon partition numbering *)
			IF found THEN UpdateSelection(disk, partition); END;
			dm.Release;
		END DiskPanelHandler;
		
		(* Registered as event handler at WMPArtitions.plugins; keeps the operation panel up-to-date *)
		PROCEDURE PluginEventHandler(event : LONGINT; plugin : AosPlugins.Plugin);
		VAR
			newTable : AosPlugins.Table;
			newButtons : ButtonArray;
			button : WMStandardComponents.Button;
			pp : PartitionsPlugin;
			i, j : LONGINT;
		BEGIN
			ASSERT((plugin#NIL) & ((event = AosPlugins.EventAdd) OR (event = AosPlugins.EventRemove)));
			pp := plugin (PartitionsPlugin);
			IF event = AosPlugins.EventAdd THEN
				
				selectedPlugin := pp;
				FOR i := 0 TO LEN(pluginButtons)-1 DO pluginButtons[i].SetPressed(FALSE); END;

				NEW(button);
				button.isToggle.Set(TRUE); button.onClick.Add(PluginHandler);
				button.caption.Set(Utilities.NewString(pp.name));
				button.clDefault.Set(WMGraphics.RGBAToColor(100,150,150,255));
				IF (selectedPlugin = plugin) THEN button.SetPressed(TRUE); END;
				operationPanel.AddContent(button);
				
				IF pluginTable # NIL THEN
					NEW(newTable, LEN(pluginTable)+1); NEW(newButtons, LEN(pluginTable)+1);
					FOR i := 0 TO LEN(pluginTable)-1 DO 
						newTable[i] := pluginTable[i]; 
						newButtons[i] := pluginButtons[i];
					END;
					newTable[LEN(pluginTable)] := pp;
					newButtons[LEN(pluginTable)] := button;
				ELSE
					NEW(newTable, 1); newTable[0] := pp;
					NEW(newButtons, 1); newButtons[0] := button;
				END;
				
			ELSIF event = AosPlugins.EventRemove THEN
			
				IF selectedPlugin = pp THEN selectedPlugin := NIL; END;
				IF (pluginTable#NIL) & (LEN(pluginTable)>1) THEN
					NEW(newTable, LEN(pluginTable)-1); NEW(newButtons, LEN(pluginTable)-1); 
					i := 0; j := 0;
					LOOP
						IF pluginTable[i]#pp THEN
							newTable[j] := pluginTable[i];
							newButtons[j] := pluginButtons[i];
							INC(j);
						ELSE
							operationPanel.RemoveContent(pluginButtons[i]);
						END;
						INC(i);
						IF i >= LEN(pluginTable) THEN EXIT; END;
					END;
				ELSE
					newTable := NIL; newButtons := NIL; 
				END;
			END;
			BEGIN {EXCLUSIVE} (* lock pluginTable & pluginButtons *)
				pluginTable := newTable;
				pluginButtons := newButtons;
			END;
			operationPanel.Invalidate; 
			UpdateOperationPanel; 
		END PluginEventHandler;
		
		(* called when disks[] has changed *)
		PROCEDURE RebuildDiskOverview;
		VAR
			panel : WMStandardComponents.Panel;
			top, i : LONGINT;
			minHeight, minWidth, min : LONGINT;
			width, height : LONGINT;
		BEGIN (* CALLER MUST HOLD dm.locked *)
			DisableUpdate;
			diskOverviewScrollPanel.RemoveContent(diskOverviewPanel);
			
			NEW(diskOverviewPanel); 
			diskOverviewPanel.fillColor.Set(MainPanelMarginColor); 
			diskOverviewScrollPanel.AddContent(diskOverviewPanel);

			BuildSkeleton;
			CalcDiskPanelBounds(minWidth, minHeight);
			UpdateDiskGrids;  
		
			IF showDetails THEN (* also consider the bounds of the grids *)
				(* minWidth *)
				min := 0;
				FOR i := 0 TO DiskOverviewTableColumns-1 DO
					min := min + maxWidths[i] (* cell width *) + GridMinSpacerH +1; (* spacing between cells *);
				END;
				min := min - 1; (* counted one spacing to much *)
				IF min > minWidth THEN minWidth := min; END;
				
				FOR i := 0 TO LEN(dm.disks)-1 DO
					IF dm.disks[i].grid # NIL THEN
						SetGridBounds(dm.disks[i].grid); 
					END;
				END;
							
				(* minHeight *)
				FOR i := 0 TO LEN(dm.disks)-1 DO
					IF dm.disks[i].grid # NIL THEN
						minHeight := minHeight + dm.disks[i].grid.bounds.GetHeight() + titleGrid.bounds.GetHeight() + DiskOverviewPanelMarginV + 8;
					END;
				END;
			END;
			
			IF mainpanel.bounds.GetWidth() >= (minWidth + 2*MainPanelMarginH + 2*DiskOverviewPanelMarginH) THEN
				width := mainpanel.bounds.GetWidth();
			ELSE
				width := minWidth + 2*MainPanelMarginH + 2*DiskOverviewPanelMarginH;
			END;
			
			height := mainpanel.bounds.GetHeight() - PluginPanelHeight - StatusBarHeight - OperationPanelHeight - 2*MainPanelMarginV;
			IF height  < minHeight THEN 
				height := minHeight + 2*MainPanelMarginV;
				width := width- scrollbarY.bounds.GetWidth();
			END;  
	
			diskOverviewPanel.bounds.SetLeft(0); diskOverviewPanel.bounds.SetTop(-scrollbarY.pos.Get());
			diskOverviewPanel.bounds.SetExtents(width, height);  
			
			FOR i := 0 TO LEN(dm.disks)-1 DO diskOverviewPanel.AddContent(BuildDiskPanel(dm.disks[i])); END; 

			top := 0;
			FOR i := 0 TO LEN(dm.disks)-1 DO
				top := top + MainPanelMarginV;
				panel := UpdateDiskOverview(dm.disks[i], top, TRUE);
				top := top + panel.bounds.GetHeight();
			END; 
			EnableUpdate;
			CSChanged; 
		END RebuildDiskOverview;
		
		PROCEDURE BuildSkeleton;
		VAR
			grid : WMStringGrids.StringGrid;
			i, j : LONGINT;
		BEGIN (* CALLER MUST HOLD dm.locked *)
			FOR i := 0 TO LEN(dm.disks)-1 DO
				(* build skeleton for graphical representation of the disk models data *)
				NEW(dm.disks[i].label); dm.disks[i].label.fillColor.Set(LabelBgColor); dm.disks[i].label.textColor.Set(LabelTxtColor);
				NEW(dm.disks[i].panel); dm.disks[i].panel.fillColor.Set(DiskOverviewPanelBgColor);
				dm.disks[i].panel.AddContent(dm.disks[i].label);
				
				IF dm.disks[i].table # NIL THEN 
					NEW(dm.disks[i].grid); dm.disks[i].panel.AddContent(dm.disks[i].grid);
					grid := dm.disks[i].grid;
					grid.alwaysShowScrollX.Set(FALSE); grid.showScrollX.Set(FALSE); 
					grid.alwaysShowScrollY.Set(FALSE); grid.showScrollY.Set(FALSE);		
					grid.SetSelectionMode(WMGrids.GridSelectRows);
					grid.onClick.Add(GridClicked);
					grid.Acquire;
					grid.model.Acquire;
					grid.model.SetNofCols(DiskOverviewTableColumns);
					grid.model.SetNofRows(LEN(dm.disks[i].table));
					grid.allowColResize.Set(FALSE); grid.allowRowResize.Set(FALSE);
					FOR j := 0 TO LEN(dm.disks[i].table) -1 DO  
						grid.model.SetTextAlign(0, j, WMGraphics.AlignLeft); 
						grid.model.SetTextAlign(1, j, WMGraphics.AlignRight);
						grid.model.SetTextAlign(2, j,  WMGraphics.AlignRight);
						grid.model.SetTextAlign(3, j, WMGraphics.AlignRight);   
						grid.model.SetTextAlign(4, j, WMGraphics.AlignCenter);
						grid.model.SetTextAlign(5, j, WMGraphics.AlignCenter); 
					END;
					grid.model.Release;
					grid.Release;
 					dm.disks[i].titlegrid := BuildTitleGrid(); dm.disks[i].panel.AddContent(dm.disks[i].titlegrid);
					NEW(dm.disks[i].buttons, LEN(dm.disks[i].table));
					FOR j := 0 TO LEN(dm.disks[i].table)-1 DO NEW(dm.disks[i].buttons[j]); END;
				ELSE 
					NEW(dm.disks[i].buttons, 1); NEW(dm.disks[i].buttons[0]); 
				END;
			END; 			
		END BuildSkeleton; 
		
		PROCEDURE GetSizeString(nbrOfBlocks, blockSize : LONGINT) : Utilities.String;
		VAR sizeKB : HUGEINT; caption : ARRAY 128 OF CHAR;
		BEGIN
			sizeKB := AosBoot.DivH(AosBoot.MulH(nbrOfBlocks, blockSize), 1024);
			IF AosBoot.GreaterH(sizeKB, 4*1024) THEN
				Utilities.IntToStr(AosBoot.HIntToLInt(AosBoot.DivH(sizeKB, 1024)), caption);
				Utilities.Append(caption, " MB");							
			ELSE
				Utilities.IntToStr(AosBoot.HIntToLInt(sizeKB), caption);
				Utilities.Append(caption, " KB");
			END;
			RETURN Utilities.NewString(caption);
		END GetSizeString;
		
		PROCEDURE UpdateDiskGrids;
		VAR (* CALLER MUST HOLD dm.locked *)	
			table : AosDisks.PartitionTable;
			caption, temp : ARRAY 128 OF CHAR;
			fillColor : LONGINT;
			grid : NoWheelGrid;
			disk, partition : LONGINT;
			width, height : LONGINT;
			minHeights : POINTER TO ARRAY OF LONGINT; (* minimum heights of each grid *)
			col, row : LONGINT;
			string : Utilities.String;
			font : WMGraphics.Font;
		BEGIN
			FOR disk := 0 TO LEN(dm.disks)-1 DO				
				table := dm.disks[disk].table;	grid := dm.disks[disk].grid;			
				IF (table # NIL) & (grid # NIL) THEN
					FOR partition := 0 TO LEN(table)-1 DO 
						grid.Acquire;
						grid.model.Acquire;
						(* Column 1: Partition : dev#part *)
						caption := "";
						Utilities.Append(caption, dm.disks[disk].device.name); Utilities.Append(caption, "#"); 
						Utilities.IntToStr(partition, temp); Utilities.Append(caption, temp);
						grid.model.SetCellText(0, partition, Utilities.NewString(caption));
						(* Column 2: Start *)
						Utilities.IntToStr(table[partition].start, caption);
						grid.model.SetCellText(1, partition, Utilities.NewString(caption));
						(* Column 3: End *)
						Utilities.IntToStr(table[partition].start + table[partition].size -1, caption);
						grid.model.SetCellText(2, partition, Utilities.NewString(caption));
						(* Column 4: Size in MB or KB*)
						grid.model.SetCellText(3, partition, GetSizeString(table[partition].size, dm.disks[disk].device.blockSize));
						(* Column 5: Type: Number and description *)
						Utilities.IntToStr(table[partition].type, caption);
						AosPartitionsLib.WriteType(table[partition].type, temp, fillColor);
						Utilities.Append(caption, " ("); Utilities.Append(caption, temp); Utilities.Append(caption, ")");
						grid.model.SetCellText(4, partition, Utilities.NewString(caption));
						(* Column 6: Flags *)
						caption := "";
						IF AosDisks.Mounted IN table[partition].flags THEN Utilities.Append(caption, "[M]"); END;
						IF AosDisks.Valid IN table[partition].flags THEN Utilities.Append(caption, "[V]"); END;
						IF AosDisks.Primary IN table[partition].flags THEN Utilities.Append(caption, "[P]"); END;
						IF AosDisks.Boot IN table[partition].flags THEN Utilities.Append(caption, "[B]"); END;
						grid.model.SetCellText(5, partition, Utilities.NewString(caption)); 
						grid.model.Release;
						grid.Release;	
					END;		
				ELSE (* no partition table available *)
					dm.disks[disk].grid := NIL;
				END;
			END;
		
			(* now we calculate the minimum column widths so that the cell text does fit into the cells *)
			(* also consider alignment of title grid ... *)
			font := titleGrid.GetFont();
			titleGrid.Acquire;
			titleGrid.model.Acquire;
			FOR col := 0 TO titleGrid.model.GetNofCols() -1 DO
				string := titleGrid.model.GetCellText(col, row);
				IF string # NIL THEN font.GetStringSize(string^, width, height); END;
				IF width  > maxWidths[col] THEN maxWidths[col] := width; END;
				IF height > maxHeight THEN maxHeight := height; END;
			END;
			titleGrid.model.Release;
			titleGrid.Release;
			
			NEW(minHeights, LEN(dm.disks)); 
			
			FOR disk := 0 TO LEN(dm.disks)-1 DO
				grid := dm.disks[disk].grid;
				IF grid # NIL THEN
					font := grid.GetFont();
					grid.Acquire;
					grid.model.Acquire;
					(* determine minimum heigths and widths needed to show the text in the cells *)
					FOR col := 0 TO grid.model.GetNofCols() -1 DO
						FOR row := 0 TO grid.model.GetNofRows() - 1 DO
							string := grid.model.GetCellText(col, row);
							IF string # NIL THEN font.GetStringSize(string^, width, height); END;
							IF width  > maxWidths[col] THEN maxWidths[col] := width; END;
							IF height > maxHeight THEN maxHeight := height; END;
						END;
					END;
					grid.model.Release;
					grid.Release;
				END;
			END;
		END UpdateDiskGrids;
		
		(* calculates the minimum width/height which is needed to display the disk panels correctly *)
		PROCEDURE CalcDiskPanelBounds(VAR minWidth, minHeight : LONGINT);
		VAR i, j : LONGINT;
		BEGIN (* CALLER MUST HOLD dm.locked *)
			minWidth := 0; minHeight := MainPanelMarginV;
			(*determine the minimum width and height required for  the disk panels *)
			FOR i := 0 TO LEN(dm.disks)-1 DO (* traverse all dm.disks ... *)
				minHeight := minHeight + MainPanelMarginV + 2*DiskOverviewPanelMarginV + LabelHeight + DiskPanelHeight;
				IF dm.disks[i].table#NIL THEN 
					WHILE j < LEN(dm.disks[i].table) DO (* ... and all partitions *)
						IF dm.disks[i].table[j].flags * {AosDisks.Primary} # {} THEN (* primary partition *)
							minWidth := minWidth + PanelMinWidth + DiskPanelMarginH;
						ELSE (* extended partition *)
							minWidth := minWidth + DiskPanelMarginH + PanelMinWidth;
						END;
						INC(j);
					END;
				END;
				minWidth := minWidth + 2*DiskOverviewPanelMarginH + DiskPanelMarginH;
			END;
		END CalcDiskPanelBounds;

 		PROCEDURE BuildTitleGrid() : NoWheelGrid;
		VAR grid : NoWheelGrid;
		BEGIN
			NEW(grid);
			grid.Acquire;
			grid.model.Acquire;
			grid.alwaysShowScrollX.Set(FALSE); grid.showScrollX.Set(FALSE);
			grid.alwaysShowScrollY.Set(FALSE); grid.showScrollY.Set(FALSE);		
			grid.SetSelectionMode(WMGrids.GridSelectNone);
			grid.allowColResize.Set(FALSE); grid.allowRowResize.Set(FALSE);
			grid.model.SetNofCols(DiskOverviewTableColumns); grid.model.SetNofRows(1);
			grid.fixedCols.Set(DiskOverviewTableColumns); grid.fixedRows.Set(1);  
			grid.model.SetCellText(0, 0, Utilities.NewString("Partition"));
			grid.model.SetCellText(1, 0, Utilities.NewString("Start"));
			grid.model.SetCellText(2, 0, Utilities.NewString("End"));
			grid.model.SetCellText(3, 0, Utilities.NewString("Size"));
			grid.model.SetCellText(4, 0, Utilities.NewString("Type"));
			grid.model.SetCellText(5, 0, Utilities.NewString("Flags"));
			grid.model.Release;
			grid.Release; 
			RETURN grid;
		END BuildTitleGrid;
		 
		(** calculates the length/height of the largest string per row/column *)
		PROCEDURE SetGridBounds(VAR grid : NoWheelGrid);
		VAR
			col, row : LONGINT;
			widths, heights : WMGrids.Spacings;
			width, height: LONGINT;
			spacer : LONGINT;
		BEGIN
			ASSERT(grid#NIL);
			grid.Acquire;
			grid.model.Acquire;		
			(* set the widths ... *)
			IF mainpanel.bounds.GetWidth() >= (minWidth + 2*MainPanelMarginH + 2*DiskOverviewPanelMarginH) THEN
			 	spacer := (mainpanel.bounds.GetWidth() - 2*MainPanelMarginH  - minWidth) DIV DiskOverviewTableColumns; 
				width := mainpanel.bounds.GetWidth() - 2*MainPanelMarginH - 2*DiskOverviewPanelMarginH;
				IF GridMinSpacerH > spacer THEN spacer := GridMinSpacerH; END;
			ELSE 
				spacer := GridMinSpacerH;
				width := minWidth;
			END;
			
			NEW(widths, DiskOverviewTableColumns);
			FOR col := 0 TO DiskOverviewTableColumns-1 DO widths[col] := maxWidths[col] + spacer; END;
			(* Correct integer division rounding error *) 
			IF (mainpanel.bounds.GetWidth() - 2*MainPanelMarginH -2*DiskOverviewPanelMarginH - minWidth) MOD DiskOverviewTableColumns # 0 THEN INC(widths[0]); END;
			grid.SetColSpacings(widths);
		
			(* set the heights *)
			height := 0;
			spacer := GridMinSpacerV;
			NEW(heights, grid.model.GetNofRows());
			FOR row := 0 TO grid.model.GetNofRows()-1 DO heights[row] := maxHeight + spacer; height := height + maxHeight + spacer + 1; END;
			grid.SetRowSpacings(heights);  
			grid.bounds.SetExtents(width, height);
			grid.model.Release;
			grid.Release; 
		END SetGridBounds;
		
		(** Update Layout & Contents *)
		PROCEDURE UpdateContent*;
		BEGIN
			dm.Acquire;
			UpdateLayout(width, height, TRUE);
			dm.Release;
			CSChanged;
		END UpdateContent;
		
		(** Update partition table & graphical & textual representation of disk disk *)
		PROCEDURE UpdateDisk*(disk : AosPartitionsLib.Disk);
		BEGIN
			diskmodel.UpdateDisk(disk); (* will call DiskEventHandler callback *)
		END UpdateDisk;
		
		(** Update all partition tables and its representation *)
		PROCEDURE UpdateDisks*;
		BEGIN
			diskmodel.Update; (* will call DiskEventHandler callback *)
		END UpdateDisks; 
			
		PROCEDURE UpdateLayout(w, h : LONGINT; updateContent : BOOLEAN);
		VAR
			panel : WMStandardComponents.Panel;
			min, top : LONGINT;
			width, height : LONGINT;
			i : LONGINT;
		BEGIN (* CALLER MUST HOLD dm.locked *)
			DisableUpdate; 
			CalcDiskPanelBounds(minWidth, minHeight);
			
			IF updateContent THEN UpdateDiskGrids; END; 

			mainpanel.bounds.SetExtents(w, h); mainpanel.bounds.SetLeft(0); mainpanel.bounds.SetTop(0);

			upperpanel.bounds.SetExtents(w, h - PluginPanelHeight - StatusBarHeight - OperationPanelHeight - 2*MainPanelMarginV); 
			upperpanel.bounds.SetTop(0); upperpanel.bounds.SetLeft(0);
			
			lowerpanel.bounds.SetWidth(w - 2*MainPanelMarginH);
			
			operationspanel.bounds.SetWidth(w - 2*MainPanelMarginH); operationspanel.bounds.SetLeft(0);
			
			IF showDetails THEN (* also consider the bounds of the grids *)
				(* minWidth *)
				min := 0;
				FOR i := 0 TO DiskOverviewTableColumns-1 DO
					min := min + maxWidths[i] (* cell width *) + GridMinSpacerH +1; (* spacing between cells *);
				END;
				min := min - 1; (* counted one spacing to much *)
				IF min > minWidth THEN minWidth := min; END;
				
				FOR i := 0 TO LEN(dm.disks)-1 DO
					IF dm.disks[i].grid # NIL THEN
						SetGridBounds(dm.disks[i].grid); 
					END;
				END;
							
				(* minHeight *)
				FOR i := 0 TO LEN(dm.disks)-1 DO
					IF dm.disks[i].grid # NIL THEN
						minHeight := minHeight + dm.disks[i].grid.bounds.GetHeight() + titleGrid.bounds.GetHeight() + DiskOverviewPanelMarginV + 13;
					END;
				END;
			END;
			
			statusBar.bounds.SetExtents(mainpanel.bounds.GetWidth(), StatusBarHeight);
			statusBar.bounds.SetLeft(0); statusBar.bounds.SetTop(mainpanel.bounds.GetHeight()-StatusBarHeight);
		
			statusLabel.bounds.SetExtents(statusBar.bounds.GetWidth() - 2*MainPanelMarginH, StatusBarHeight - 2);
			statusLabel.bounds.SetLeft(MainPanelMarginH); statusLabel.bounds.SetTop(1);
		
			(* if the actual diskoverview panel bounds are bigger then minWidth&minHeight, then use them *)
			IF mainpanel.bounds.GetWidth() >= (minWidth + 2*MainPanelMarginH + 2*DiskOverviewPanelMarginH) THEN
				width := mainpanel.bounds.GetWidth();
			ELSE
				width := minWidth + 2*MainPanelMarginH + 2*DiskOverviewPanelMarginH;
			END;
			
			height := mainpanel.bounds.GetHeight() - PluginPanelHeight - StatusBarHeight - OperationPanelHeight - 2*MainPanelMarginV;
			IF height  < minHeight + 2*MainPanelMarginV THEN 
				height := minHeight + 2*MainPanelMarginV;
				width := width - scrollbarY.bounds.GetWidth();
			END;  
			
			diskOverviewPanel.bounds.SetExtents(width, height); diskOverviewPanel.bounds.SetLeft(0);
			diskOverviewPanel.fillColor.Set(MainPanelMarginColor); 
		
			UpdateOperationPanel;	
			
			top := 0;
			FOR i := 0 TO LEN(dm.disks)-1 DO
				top := top + MainPanelMarginV;
				panel := UpdateDiskOverview(dm.disks[i], top, updateContent);
				top := top + panel.bounds.GetHeight();
			END;
		
			(* do we need scrollbars for the diskoverview panel ? *)
			IF minHeight > diskOverviewScrollPanel.bounds.GetHeight() THEN (* need a vertical scrollbar ... *)
				scrollbarY.max.Set(minHeight - diskOverviewScrollPanel.bounds.GetHeight()); 
				scrollbarY.pos.Set(scrollY);
				scrollbarY.visible.Set(TRUE); 
			ELSE 
				scrollY := 0; diskOverviewPanel.bounds.SetTop(0);
				scrollbarY.visible.Set(FALSE); 
			END;
								
			IF diskOverviewPanel.bounds.GetWidth() > w THEN (* need a horizontal scrollbar *)
				scrollbarX.max.Set(diskOverviewPanel.bounds.GetWidth() - w - scrollbarY.bounds.GetWidth()); 
				scrollbarX.pos.Set(scrollX);
				scrollbarX.visible.Set(TRUE);
			ELSE
				scrollX := 0; diskOverviewPanel.bounds.SetLeft(0);
				scrollbarX.visible.Set(FALSE);
			END;	
			
			IF oppanel.bounds.GetHeight()  > operationspanel.bounds.GetHeight() THEN (* need a vertical scrollbar ... *)
				opScrollbarY.max.Set(oppanel.bounds.GetHeight() - operationspanel.bounds.GetHeight()); 
				opScrollbarY.visible.Set(TRUE); 
			ELSE 
				opScrollbarY.visible.Set(FALSE); 
			END;
					
			IF operationspanel.bounds.GetWidth()  > w THEN (* need a horizontal scrollbar *)
				opScrollbarX.max.Set(oppanel.bounds.GetWidth() - w - scrollbarY.bounds.GetWidth()); 
				opScrollbarX.visible.Set(TRUE);
			ELSE
				opScrollbarX.visible.Set(FALSE);
			END;
			EnableUpdate; 
		END UpdateLayout;
		
		PROCEDURE UpdateOperationPanel;
		VAR plugin : PartitionsPlugin; left, i : LONGINT;
		BEGIN
			operationPanel.bounds.SetExtents(mainpanel.bounds.GetWidth() - 2*MainPanelMarginH, OperationPanelHeight + PluginPanelHeight);
			operationPanel.bounds.SetLeft(MainPanelMarginH); operationPanel.bounds.SetTop(upperpanel.bounds.GetHeight() + MainPanelMarginV); 
		
			left := DiskOverviewPanelMarginH;
			
			showdetails.bounds.SetExtents(ButtonWidth, ButtonHeight);
			showdetails.bounds.SetLeft(left); showdetails.bounds.SetTop(DiskOverviewPanelMarginV);
			IF showDetails THEN showdetails.SetPressed(TRUE); ELSE showdetails.SetPressed(FALSE); END;
		
			left := left + ButtonWidth + ButtonSpacer;

			refresh.bounds.SetExtents(ButtonWidth, ButtonHeight);
			refresh.bounds.SetLeft(left); refresh.bounds.SetTop(DiskOverviewPanelMarginV);
		
			left := left + ButtonWidth + ButtonSpacer;
		
			pluginPanel.bounds.SetExtents(mainpanel.bounds.GetWidth() - 2*MainPanelMarginH - 2*DiskOverviewPanelMarginH, PluginPanelHeight);
			pluginPanel.bounds.SetLeft(DiskOverviewPanelMarginH); pluginPanel.bounds.SetTop(MainPanelMarginV + DiskOverviewPanelMarginV + ButtonHeight);
		(*	BEGIN {EXCLUSIVE} (* pluginTable & pluginButtons asynchronously changed by PluginEventHandler() *)*)
				IF pluginTable # NIL THEN
					FOR i := 0 TO LEN(pluginTable)-1 DO
						ASSERT(pluginButtons[i]#NIL);
						pluginButtons[i].bounds.SetExtents(ButtonWidth, ButtonHeight);
						pluginButtons[i].bounds.SetLeft(left); pluginButtons[i].bounds.SetTop(DiskOverviewPanelMarginV);
						left := left + ButtonWidth + ButtonSpacer;
						plugin := pluginTable[i] (PartitionsPlugin);
						plugin.Resized(pluginPanel.bounds.GetWidth(), pluginPanel.bounds.GetHeight());
					END;
				ELSE
					noPlugins.bounds.SetExtents(pluginPanel.bounds.GetWidth(), pluginPanel.bounds.GetHeight());
					noPluginsLabel.bounds.SetExtents(pluginPanel.bounds.GetWidth() - 2*DiskOverviewPanelMarginH, pluginPanel.bounds.GetHeight() - 2*DiskOverviewPanelMarginV);
				END;
	(*		END; *)
			left := left + ButtonSpacer;
			
			selectionState.bounds.SetExtents(10, ButtonHeight);
			selectionState.bounds.SetLeft(left); selectionState.bounds.SetTop(DiskOverviewPanelMarginV);
		
			left := left + 10 + ButtonSpacer;
			 
			selectionLabel.bounds.SetExtents(mainpanel.bounds.GetWidth() - 2*MainPanelMarginH - left - 10, ButtonHeight);
			selectionLabel.bounds.SetLeft(left + ButtonSpacer); selectionLabel.bounds.SetTop(DiskOverviewPanelMarginV);	
		
			IF selectedPanel # NIL THEN 
				selectedPanel.bounds.SetExtents(pluginPanel.bounds.GetWidth(), pluginPanel.bounds.GetHeight());
			END;
		END UpdateOperationPanel;
		
		(* UpdateSelection(-1,-1) means "no selection" *)
		PROCEDURE UpdateSelection(disk, partition : LONGINT);
		VAR (* CALLER MUST HOLD diskmodel.locked *)
			caption, temp : ARRAY 128 OF CHAR;
			selectionNone : LONGINT;
			i, j : LONGINT;
		BEGIN
			selection.partition := partition; 
			
			caption := "Selection: ";
			IF (disk = -1) & (partition = -1) THEN (* selection: none *)		
				Utilities.Append(caption, "none");
				selection.disk.device := NIL;
			ELSE 
				selection.disk := dm.disks[disk];
				Utilities.Append(caption, selection.disk.device.name); Utilities.Append(caption, "#"); 
				Utilities.IntToStr(selection.partition, temp); Utilities.Append(caption, temp);
				Utilities.Append(caption, " ("); Utilities.Append(caption, selection.disk.device.desc); Utilities.Append(caption, ")");
				Utilities.Append(caption, 0X);
			END;	
			
			IF selectedPlugin # NIL THEN 
				selection.SelectionState := selectedPlugin.SelectionUpdated(selection); 
				CASE selection.SelectionState OF
					SelectionValid : selectionState.fillColor.Set(WMGraphics.Green);
					|SelectionInvalid : selectionState.fillColor.Set(WMGraphics.Red);
					|SelectionMaybe : selectionState.fillColor.Set(WMGraphics.Yellow);
					|SelectionNotSupported : selectionState.fillColor.Set(WindowBg);
				ELSE
					selectionState.fillColor.Set(WindowBg);
				END;
			END;

			selectionLabel.caption.Set(Utilities.NewString(caption));
			
			(* update grids & buttons *)	
			FOR i := 0 TO LEN(dm.disks)-1 DO
				IF (dm.disks[i].grid # NIL) THEN
					IF i = disk THEN
						dm.disks[i].grid.SetSelection(disk,partition,disk,partition);
					ELSE	
						selectionNone := LEN(dm.disks[i].table); (* not visible *)
						dm.disks[i].grid.SetSelection(selectionNone,selectionNone,selectionNone,selectionNone);
					END;
				END;
			
				IF dm.disks[i].buttons#NIL THEN 
					FOR j := 0 TO LEN(dm.disks[i].buttons)-1 DO (* for all partitions... *)
						IF dm.disks[i].table#NIL THEN 
							IF (i = disk) & (dm.disks[i].mapping[j] = partition) THEN (* selected *)
								dm.disks[i].buttons[j].SetPressed(TRUE); 
							ELSE
								dm.disks[i].buttons[j].SetPressed(FALSE); 
							END;
						ELSE (* no partition table *)
							IF (i = disk) & (partition = 0) THEN
								dm.disks[i].buttons[0].SetPressed(TRUE);
							ELSE
								dm.disks[i].buttons[0].SetPressed(FALSE);
							END;
						END;
					END;	
				END;
			END;
		END UpdateSelection;
		
		(* Since selection.disk is a copy (RECORD), we may want to refresh it *)
		PROCEDURE RefreshSelection*;
		VAR i : LONGINT;
		BEGIN
			dm.Acquire;
			IF (selection.disk.device # NIL) & (selection.partition # -1) THEN (* selection valid *)
				IF dm.disks # NIL THEN
					i := 0; WHILE (i < LEN(dm.disks)) & (dm.disks[i].device # selection.disk.device) DO INC(i); END;
					IF dm.disks[i].device = selection.disk.device THEN
						UpdateSelection(i, selection.partition); (* notify plugins... *)
					END;
				END;
			END;
			dm.Release;
		END RefreshSelection;
		
		PROCEDURE Close;
		VAR plugin : PartitionsPlugin; i, ignore : LONGINT;
		BEGIN 
			pluginPanel.RemoveContent(selectedPanel);
			plugins.RemoveEventHandler(PluginEventHandler, ignore); 
			diskmodel.onChanged.Remove(DiskEventHandler);
			IF pluginTable # NIL THEN
				FOR i := 0 TO LEN(pluginTable)-1 DO
					plugin := pluginTable[i] (PartitionsPlugin);
					plugin.Finalize;
					IF plugin IS PendingOperations THEN
						plugins.Remove(plugin);
					END;
				END; 
			END;
			Close^;
			window := NIL;
		END Close;
		
		PROCEDURE DiskEventHandler(sender, data : PTR);
		BEGIN
			dm.Acquire;
			dm.Synchronize;
			RebuildDiskOverview;
			UpdateLayout(width, height, TRUE);
			ScrollX(NIL, NIL); ScrollY(NIL, NIL);
			dm.Release;
			CSChanged;
		END DiskEventHandler;
				
		PROCEDURE Handle(VAR x: WMMessages.Message);
		VAR configuration : WMRestorable.XmlElement;
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS WMRestorable.Storage) THEN
					NEW(configuration); configuration.SetName("Configuration");
					WMRestorable.StoreLongint(configuration, "Width", width);
					WMRestorable.StoreLongint(configuration, "Height", height);
					WMRestorable.StoreBoolean(configuration, "Details", showDetails);
					x.ext(WMRestorable.Storage).Add("PartitionTool", "WMPartitions.Restore", SELF, configuration);
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;		
		
		PROCEDURE &New(c : WMRestorable.Context);
		CONST
			OpPanelInitHeight = 60;
		VAR
			plugin : AosPlugins.Plugin;
			configuration : WMRestorable.XmlElement;
			ignore : LONGINT; 
			scale : BOOLEAN;
			resizer : WMStandardComponents.Resizer;
			i : LONGINT;
		BEGIN
			scale := FALSE; showDetails := TRUE; 
			IF c # NIL THEN
				width := c.r - c.l; height := c.b - c.t;
				configuration := WMRestorable.GetElement(c, "Configuration");
				IF configuration # NIL THEN
					WMRestorable.LoadLongint(configuration, "Width", width);
					WMRestorable.LoadLongint(configuration, "Height", height);
					WMRestorable.LoadBoolean(configuration, "Details", showDetails);
					IF (width < WindowMinWidth) OR (height < WindowMinHeight) THEN
						(* First render window in real size and then scale it down to the size specified by the context *)
						scale := TRUE;
					END;
				END;
			ELSE
				width := DefaultWidth; height := DefaultHeight;
			END;
			Init(width, height, FALSE);
		
			SetTitle(WMWindowManager.NewString("Partition Tool"));			
			scaling := FALSE;
			
			titleGrid := BuildTitleGrid();
		
			NEW(mainpanel); mainpanel.fillColor.Set(MainPanelMarginColor);
		
			NEW(statusBar); statusBar.fillColor.Set(StatusBarBgColor); 
			mainpanel.AddContent(statusBar);
		
			NEW(statusLabel); statusLabel.fillColor.Set(StatusBarBgColor); 
			statusLabel.textColor.Set(WMGraphics.White); statusLabel.caption.Set(Utilities.NewString("Ready"));
			statusBar.AddContent(statusLabel);
				
			NEW(upperpanel);
			mainpanel.AddContent(upperpanel);
		
			NEW(lowerpanel); lowerpanel.fillColor.Set(MainPanelMarginColor);
			lowerpanel.alignment.Set(WMComponents.AlignBottom); 
			lowerpanel.bounds.SetHeight(OpPanelInitHeight); lowerpanel.bounds.SetLeft(MainPanelMarginV);
			upperpanel.AddContent(lowerpanel);
			
			NEW(resizer); resizer.bounds.SetHeight(4); resizer.alignment.Set(WMComponents.AlignTop); 
			lowerpanel.AddContent(resizer);
			
			NEW(operationspanel);
			operationspanel.alignment.Set(WMComponents.AlignClient);
			lowerpanel.AddContent(operationspanel);
			
			(* set startup default plugin *)
			plugin := plugins.Get(DefaultPlugin);
			IF plugin # NIL THEN
				selectedPlugin := plugin (PartitionsPlugin);
				selectedPanel := plugin(PartitionsPlugin).GetPanel(0,0);
			ELSE
				AosOut.String("WMPartitions: Default plugin not found."); AosOut.Ln;
			END;
	
			mainpanel.AddContent(BuildOperationPanel());	
			
			diskmodel := AosPartitionsLib.diskModel; 
			diskmodel.Update;
			ASSERT(diskmodel # NIL);
			NEW(dm, diskmodel);
			dm.Acquire;
			dm.Synchronize;
			BuildSkeleton;
			UpdateDiskGrids; 
			
			NEW(diskOverviewPanel);
			FOR i := 0 TO LEN(dm.disks)-1 DO diskOverviewPanel.AddContent(BuildDiskPanel(dm.disks[i])); END;

			(* build & add the diskoverview panel *)
			NEW(diskOverviewScrollPanel);	diskOverviewScrollPanel.fillColor.Set(MainPanelMarginColor); 	
			diskOverviewScrollPanel.alignment.Set(WMComponents.AlignClient); 
			diskOverviewScrollPanel.bounds.SetHeight(height - OpPanelInitHeight - PluginPanelHeight - OperationPanelHeight - StatusBarHeight - 2*MainPanelMarginV);
			diskOverviewPanel.bounds.SetTop(0);
			diskOverviewScrollPanel.AddContent(diskOverviewPanel);
			upperpanel.AddContent(diskOverviewScrollPanel);
			
			NEW(scrollbarY); 
			scrollbarY.vertical.Set(TRUE); scrollbarY.alignment.Set(WMComponents.AlignRight);
			scrollbarY.min.Set(0); scrollbarY.onPositionChanged.Add(ScrollY);
			diskOverviewScrollPanel.AddContent(scrollbarY); 

			NEW(scrollbarX); 
			scrollbarX.vertical.Set(FALSE); scrollbarX.alignment.Set(WMComponents.AlignBottom);
			scrollbarX.min.Set(0); scrollbarX.onPositionChanged.Add(ScrollX);
			diskOverviewScrollPanel.AddContent(scrollbarX); 
			
			NEW(opScrollbarY); 
			opScrollbarY.vertical.Set(TRUE); opScrollbarY.alignment.Set(WMComponents.AlignRight);
			opScrollbarY.min.Set(0); opScrollbarY.onPositionChanged.Add(OpScrollY);
			operationspanel.AddContent(opScrollbarY); 

			NEW(opScrollbarX); 
			opScrollbarX.vertical.Set(FALSE); opScrollbarX.alignment.Set(WMComponents.AlignBottom);
			opScrollbarX.min.Set(0); opScrollbarX.onPositionChanged.Add(OpScrollX);
			operationspanel.AddContent(opScrollbarX); 		
			
			NEW(noPlugins);	
			noPlugins.bounds.SetLeft(0); noPlugins.bounds.SetTop(0); noPlugins.fillColor.Set(WindowBg);
			
			NEW(noPluginsLabel);
			noPluginsLabel.bounds.SetLeft(DiskOverviewPanelMarginH); noPluginsLabel.bounds.SetTop(DiskOverviewPanelMarginV); 
			noPluginsLabel.caption.Set(Utilities.NewString("No plugins installed")); noPluginsLabel.fillColor.Set(WindowBg);
		
			UpdateSelection(-1, -1);   
			UpdateLayout(width, height, TRUE);
			dm.Release;
	
			SetContent(mainpanel);				
	
			IF c # NIL THEN 
				WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame});
				IF scale THEN Resized(c.r - c.l, c.b - c.t); END;
			ELSE
				WMWindowManager.ExtAddWindow (SELF, 100, 100, {WMWindowManager.FlagFrame});
				manager := WMWindowManager.GetDefaultManager ();
				manager.SetFocus(SELF);
			END;
		
			diskmodel.onChanged.Add(DiskEventHandler);	
			plugins.AddEventHandler(PluginEventHandler, ignore); 
			CSChanged;    
		END New;

	END Window;
	
TYPE 

	(* This is a special case plugin. It provides access to disk operations (AosPartitionsLib.Operation) which are registered at the disk
	 * operation manager (AosPartitionsLib.OperationManager).
	 *)
	PendingOperations = OBJECT(PartitionsPlugin);
	VAR
		(* buttons *)
		abort, remove, showerrors : WMStandardComponents.Button;
		finished, all, selected : WMStandardComponents.Button; (* check boxes *)
		removeMode : LONGINT; (* RemoveSelected | RemoveFinished | RemoveAll *)
		info : BorderLabel; 
	
		oppanel : BevelPanel; 
	
		grid, titleGrid : NoWheelGrid;
		spacings : WMGrids.Spacings; noOfCols : LONGINT;
		
		operations : AosPartitionsLib.AllOperations;
		
		selectedOperation: AosPartitionsLib.Operation; (* NIL if no operation is selected *) 
		
		alive, dead : BOOLEAN;
		timer : AosKernel.Timer;
		
		PROCEDURE GetOpPanel() : BevelPanel;
		BEGIN
			RETURN oppanel;
		END GetOpPanel;
		
		PROCEDURE GridClicked(sender, x : ANY);
		VAR grid : NoWheelGrid; ignore, row : LONGINT; w : AosIO.StringWriter; string : ARRAY 128 OF CHAR;
		BEGIN {EXCLUSIVE} (* lock operations *)
			grid := sender (NoWheelGrid);
			IF operations # NIL THEN 
				grid.Acquire;
				grid.model.Acquire;
				grid.GetSelection(ignore, row, ignore, ignore);	
				IF row < LEN(operations) THEN 
					selectedOperation := operations[row]; 
				ELSE
					selectedOperation := NIL;
					grid.model.SetTextAlign(0, 0, WMGraphics.AlignLeft); 
				END;
				grid.model.Release;
				grid.Release;
				NEW(w, 128);
				w.String(" Selected operation: "); w.String("UID "); w.Int(selectedOperation.uid, 0); w.String(": ");
				w.String(selectedOperation.name);	w.String(" ("); w.String(selectedOperation.desc); w.String(")");
				w.Get(string);
				info.caption.Set(Utilities.NewString(string));
			ELSE
				selectedOperation := NIL;
				info.caption.Set(Utilities.NewString(" Selected operation: none"));
			END;
		END GridClicked;
		
		PROCEDURE CheckBoxes(sender, data : PTR);
		VAR button : WMStandardComponents.Button;
		BEGIN
			button := sender (WMStandardComponents.Button);
			
			(* clear all check boxes *)
			selected.caption.Set(Utilities.NewString(""));
			finished.caption.Set(Utilities.NewString(""));
			all.caption.Set(Utilities.NewString(""));
			
			IF button = selected THEN
				removeMode := RemoveSelected;
				selected.caption.Set(Utilities.NewString("X"));
			ELSIF button = finished THEN
				removeMode := RemoveFinished;
				finished.caption.Set(Utilities.NewString("X"));
			ELSIF button = all THEN
				removeMode := RemoveAll;
				all.caption.Set(Utilities.NewString("X"));
			ELSE
				HALT(399);
			END;
		END CheckBoxes;
		
		PROCEDURE Resized*(width, height : LONGINT);
		BEGIN
			panel.bounds.SetExtents(width, height);
			info.bounds.SetExtents(width, ButtonHeight);
			oppanel.bounds.SetExtents(width, 0 (* set in UpdateGrids() *)); 
			UpdateGrid(FALSE);
		END Resized;
		
		(* we don't care about which disk is currently selected *)
		PROCEDURE SelectionUpdated*(selection : Selection): LONGINT;
		BEGIN
			RETURN SelectionNotSupported;
		END SelectionUpdated; 

		PROCEDURE UpdateGrid(updateContent : BOOLEAN);
		CONST
			ColStatus = 3;
		VAR	
			caption : ARRAY 128 OF CHAR;
			operation : AosPartitionsLib.Operation;
			width, height, minWidth : LONGINT;
			row, i, ignore, cellHeight : LONGINT;
			font : WMGraphics.Font;
			operationState : AosPartitionsLib.OperationState;
			widths, heights : WMGrids.Spacings;
		BEGIN (* caller must hold lock *)
			ASSERT((grid # NIL) & (titleGrid#NIL)); 
			IF operations # NIL THEN 
				IF updateContent THEN 
					grid.Acquire;
					grid.model.Acquire;
					grid.SetSelectionMode(WMGrids.GridSelectSingleRow);
					grid.model.SetNofCols(noOfCols); grid.model.SetNofRows(LEN(operations));
					
					FOR row := 0 TO LEN(operations)-1 DO
						operation := operations[row];
						FOR i := 0 TO LEN(operations) -1 DO  
							grid.model.SetTextAlign(0, i, WMGraphics.AlignCenter); (* uid *)
							grid.model.SetTextAlign(1, i, WMGraphics.AlignLeft); (* operation *)
							grid.model.SetTextAlign(2, i,  WMGraphics.AlignCenter); (* device *)
							grid.model.SetTextAlign(3, i, WMGraphics.AlignLeft); (* status *)
							grid.model.SetTextAlign(4, i, WMGraphics.AlignCenter); (* errors *)
							grid.model.SetTextAlign(5, i, WMGraphics.AlignCenter); (* progress *)  
						END; 
						operationState := operation.GetState();
						(* Column 1: UID *)
						Utilities.IntToStr(operation.uid, caption); 
						grid.model.SetCellText(0, row, Utilities.NewString(caption));
						(* Column 2: Operation Name *)
						grid.model.SetCellText(1, row, Utilities.NewString(operation.name));
						(* Column 3: Device#partition *)
						grid.model.SetCellText(2, row, Utilities.NewString(operation.diskpartString));
						(* Column 4: Status *)
						grid.model.SetCellText(3, row, Utilities.NewString(operationState.statusString));
						(* Column 5: Errors *)
						Utilities.IntToStr(operationState.errorCount, caption);
						grid.model.SetCellText(4, row, Utilities.NewString(caption));
						(* Column 6: Progress *)
						IF operationState.progressValid THEN 
							Utilities.IntToStr(ENTIER(operationState.cur*100.0 / operationState.max), caption); Utilities.Append(caption, "%"); 
						ELSE
							caption := "";
						END;
						grid.model.SetCellText(5, row, Utilities.NewString(caption));
					END;
					grid.model.Release;
					grid.Release;	
				END;
	
			ELSE (* no operations registered *)
				grid.Acquire;
				grid.model.Acquire;
				grid.model.SetNofCols(1); grid.model.SetNofRows(1);
				grid.model.SetCellText(0, 0, Utilities.NewString("No operations"));
				grid.SetSelectionMode(WMGrids.GridSelectNone);
				grid.model.Release;
				grid.Release;	
			END;
			
			(* only the column "Status" is resizable, all others have a fixed width *)
			FOR i := 0 TO noOfCols-1 DO
				IF i # ColStatus THEN 
					minWidth := minWidth + spacings[i] (* cell width *) +1; (* spacing between cells *);
				END;
			END;
			
			IF oppanel.bounds.GetWidth() - 2*DiskOverviewPanelMarginH >= minWidth THEN
			 	spacings[ColStatus] := (oppanel.bounds.GetWidth() - minWidth - 2*DiskOverviewPanelMarginH); width := oppanel.bounds.GetWidth();
			ELSE (* should not be the case *)
				spacings[ColStatus] := 0;	width := minWidth;
			END;

			titleGrid.Acquire; titleGrid.model.Acquire; 
			font := titleGrid.GetFont(); font.GetStringSize("TestString", ignore, height); 
			cellHeight := height + GridMinSpacerV;  
			titleGrid.SetColSpacings(spacings); 
			titleGrid.model.Release; titleGrid.Release;
			titleGrid.bounds.SetTop(DiskOverviewPanelMarginV); titleGrid.bounds.SetLeft(DiskOverviewPanelMarginH);
			titleGrid.bounds.SetExtents(width, cellHeight);
		
			grid.Acquire;
			grid.model.Acquire;
			IF operations # NIL THEN  
				(* set the heights *)
				height := 0;
				NEW(heights, grid.model.GetNofRows()); 
				FOR row := 0 TO grid.model.GetNofRows()-1 DO heights[row] := cellHeight; height := height + cellHeight + 1; END; 
				grid.SetRowSpacings(heights); grid.SetColSpacings(spacings);
			ELSE
				height := 0;
				NEW(heights, 1); heights[0] := cellHeight; height := height + cellHeight + 1;
				NEW(widths, 1);widths[0] := oppanel.bounds.GetWidth() - 2*DiskOverviewPanelMarginH;
				grid.SetRowSpacings(heights); grid.SetColSpacings(widths);
			END; 
			grid.model.Release; 
			grid.Release;
			grid.bounds.SetExtents(width, height); grid.bounds.SetTop(titleGrid.bounds.GetHeight() + DiskOverviewPanelMarginV + 1);
			grid.bounds.SetLeft(DiskOverviewPanelMarginH);
			
			oppanel.bounds.SetHeight(grid.bounds.GetHeight() + titleGrid.bounds.GetHeight() + 2*DiskOverviewPanelMarginV + 1);
			
			IF updateContent & (owner#NIL) THEN owner.UpdateContent; END; 
		END UpdateGrid;
		
		PROCEDURE OperationEventHandler(sender, data :  PTR);
		BEGIN {EXCLUSIVE}
			operations := AosPartitionsLib.operations.GetAllInternal();
			UpdateGrid(TRUE);
		END OperationEventHandler;
		
		PROCEDURE Abort(sender, data : PTR);
		VAR result : ARRAY 256 OF CHAR; temp : ARRAY 10 OF CHAR;
		BEGIN
			IF selectedOperation # NIL THEN
				selectedOperation.Abort;
				result := "UID ";
				Utilities.IntToStr(selectedOperation.uid, temp); Utilities.Append(result, temp);
				Utilities.Append(result, " : "); Utilities.Append(result, "Operation aborted");
			ELSE
				result := "No operation selected";
			END;
			owner.UpdateStatusLabel(Utilities.NewString(result));
		END Abort;
		
		PROCEDURE Remove(sender, data : PTR);
		VAR result : ARRAY 256 OF CHAR; temp : ARRAY 10 OF CHAR; num : LONGINT;
		BEGIN
			ASSERT(AosPartitionsLib.operations # NIL);
			IF removeMode = RemoveSelected THEN 
				IF selectedOperation # NIL THEN
					result := "UID ";
					Utilities.IntToStr(selectedOperation.uid, temp); Utilities.Append(result, temp);
					Utilities.Append(result, " : "); Utilities.Append(result, "Operation removed");
					IF AosPartitionsLib.operations.Remove(selectedOperation) THEN
						result := "UID ";
						Utilities.IntToStr(selectedOperation.uid, temp); Utilities.Append(result, temp);
						Utilities.Append(result, " : "); Utilities.Append(result, "Operation removed");
						selectedOperation := NIL;
						info.caption.Set(Utilities.NewString(" Selected operation: none"));
					ELSE
						result := "Could not remove operation";
					END;
				ELSE
					result := "No operation selected";
				END;
			ELSIF removeMode = RemoveFinished THEN 
				num := AosPartitionsLib.operations.RemoveAll(TRUE);
				Utilities.IntToStr(num, temp);
				result := ""; Utilities.Append(result, temp); Utilities.Append(result, " finished operations removed");
				selectedOperation := NIL;
				info.caption.Set(Utilities.NewString(" Selected operation: none"));
			ELSIF removeMode = RemoveAll THEN 
				num := AosPartitionsLib.operations.RemoveAll(FALSE);
				Utilities.IntToStr(num, temp);
				result := ""; Utilities.Append(result, temp); Utilities.Append(result, " operations removed");
				selectedOperation := NIL;
				info.caption.Set(Utilities.NewString(" Selected operation: none"));
			ELSE
				HALT(398);
			END;
			owner.UpdateStatusLabel(Utilities.NewString(result));
		END Remove;

		PROCEDURE Showerrors(sender, data : PTR);
		VAR text : AosTexts.Text; reportWindow : ReportWindow; result : ARRAY 256 OF CHAR; temp : ARRAY 10 OF CHAR;
		BEGIN
			IF selectedOperation # NIL THEN
				result := "UID ";
				Utilities.IntToStr(selectedOperation.uid, temp); Utilities.Append(result, temp);
				Utilities.Append(result, " : "); Utilities.Append(result, "Showing status report");
				text := selectedOperation.GetReport(TRUE);
				NEW(reportWindow, text, 500, 200, FALSE);
				reportWindow.Show();
			ELSE
				result := "No operation selected";
			END;
			owner.UpdateStatusLabel(Utilities.NewString(result));
		END Showerrors;
		
		PROCEDURE &Init;
		VAR
			allOperations : AosPartitionsLib.AllOperations;
			selectNone, left : LONGINT;
			label : WMStandardComponents.Label;
			i : LONGINT;
		BEGIN
			SetName("Operation"); desc := "Show pending operations and operations history";
			NEW(timer); alive := TRUE; dead := FALSE; noOfCols := 6;
			
			NEW(titleGrid);
			titleGrid.bounds.SetLeft(0); titleGrid.bounds.SetTop(0);
			titleGrid.alwaysShowScrollX.Set(FALSE); titleGrid.showScrollX.Set(FALSE);
			titleGrid.alwaysShowScrollY.Set(FALSE); titleGrid.showScrollY.Set(FALSE);		
			titleGrid.allowColResize.Set(FALSE); titleGrid.allowRowResize.Set(FALSE);
			titleGrid.fixedCols.Set(noOfCols); titleGrid.fixedRows.Set(1);  
			titleGrid.Acquire;
			titleGrid.model.Acquire;
			titleGrid.SetSelectionMode(WMGrids.GridSelectNone);
			titleGrid.model.SetNofCols(noOfCols); titleGrid.model.SetNofRows(1);
			titleGrid.model.SetCellText(0, 0, Utilities.NewString("UID")); titleGrid.model.SetTextAlign(0, 0, WMGraphics.AlignCenter);
			titleGrid.model.SetCellText(1, 0, Utilities.NewString("Operation")); titleGrid.model.SetTextAlign(1, 0, WMGraphics.AlignLeft);
			titleGrid.model.SetCellText(2, 0, Utilities.NewString("Device")); titleGrid.model.SetTextAlign(2, 0, WMGraphics.AlignCenter);
			titleGrid.model.SetCellText(3, 0, Utilities.NewString("Status")); titleGrid.model.SetTextAlign(3, 0, WMGraphics.AlignLeft);
			titleGrid.model.SetCellText(4, 0, Utilities.NewString("Errors")); titleGrid.model.SetTextAlign(4, 0, WMGraphics.AlignCenter);
			titleGrid.model.SetCellText(5, 0, Utilities.NewString("Progress")); titleGrid.model.SetTextAlign(5, 0, WMGraphics.AlignCenter);
			titleGrid.model.Release;
			titleGrid.Release; 
			
			NEW(spacings, noOfCols); 
			spacings[0] := 30; spacings[1] := 100; spacings[2] := 50;
			spacings[3] := 0; (* will be set later *)
			spacings[4] := 35; spacings[5] := 50;
				
				
			allOperations := AosPartitionsLib.operations.GetAll();
			
			IF allOperations # NIL THEN
				NEW(operations, LEN(allOperations));
				FOR i := 0 TO LEN(allOperations)-1 DO
					operations[i] := allOperations[i];
				END;
			ELSE
				operations := NIL;
			END;	
							
			NEW(panel);
			panel.fillColor.Set(WindowBg);
			panel.bounds.SetTop(0); panel.bounds.SetLeft(0);
			
			NEW(abort); left := 0;
			abort.bounds.SetExtents(ButtonWidth, ButtonHeight); abort.bounds.SetLeft(left); abort.bounds.SetTop(0);
			abort.onClick.Add(Abort); abort.SetCaption("Abort");
			panel.AddContent(abort);
	
			NEW(showerrors); left := left + ButtonWidth + ButtonSpacer;
			showerrors.bounds.SetExtents(ButtonWidth, ButtonHeight); showerrors.bounds.SetLeft(left); showerrors.bounds.SetTop(0);
			showerrors.onClick.Add(Showerrors); showerrors.SetCaption("Report");
			panel.AddContent(showerrors);
		
			NEW(remove); left := left + ButtonWidth + ButtonSpacer;
			remove.bounds.SetExtents(ButtonWidth, ButtonHeight); remove.bounds.SetLeft(left); remove.bounds.SetTop(0);
			remove.onClick.Add(Remove); remove.SetCaption("Remove");
			panel.AddContent(remove);
			
			(* check boxes *)
			removeMode := RemoveSelected;
	
			NEW(selected); left := left + ButtonWidth + ButtonSpacer;
			selected.bounds.SetExtents(ButtonHeight, ButtonHeight); selected.bounds.SetLeft(left); selected.bounds.SetTop(0);
			selected.onClick.Add(CheckBoxes); selected.caption.Set(Utilities.NewString("X"));
			panel.AddContent(selected); 
			
			NEW(label); left := left + ButtonHeight + ButtonSpacer;
			label.bounds.SetExtents(50, ButtonHeight); label.bounds.SetLeft(left); label.bounds.SetTop(0);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("Selected"));
			panel.AddContent(label);

			NEW(finished); left := left + 50 + ButtonSpacer;
			finished.bounds.SetExtents(ButtonHeight, ButtonHeight); finished.bounds.SetLeft(left); finished.bounds.SetTop(0);
			finished.onClick.Add(CheckBoxes); finished.caption.Set(Utilities.NewString(""));
			panel.AddContent(finished); 
			
			NEW(label); left := left + ButtonHeight + ButtonSpacer;
			label.bounds.SetExtents(50, ButtonHeight); label.bounds.SetLeft(left); label.bounds.SetTop(0);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("Finished"));
			panel.AddContent(label);
			
			NEW(all); left := left + 50 + ButtonSpacer;
			all.bounds.SetExtents(ButtonHeight, ButtonHeight); all.bounds.SetLeft(left); all.bounds.SetTop(0);
			all.onClick.Add(CheckBoxes); all.caption.Set(Utilities.NewString(""));
			panel.AddContent(all); 
			
			NEW(label); left := left + ButtonHeight + ButtonSpacer;
			label.bounds.SetExtents(50, ButtonHeight); label.bounds.SetLeft(left); label.bounds.SetTop(0);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("All"));
			panel.AddContent(label);
			
			NEW(info);
			info.bounds.SetLeft(0); info.bounds.SetTop(ButtonHeight + ButtonSpacer);
			info.fillColor.Set(WMGraphics.White); info.caption.Set(Utilities.NewString(" Selected operation: none"));
			panel.AddContent(info);			
			
			NEW(oppanel);
			oppanel.bounds.SetLeft(MainPanelMarginH); oppanel.bounds.SetTop(MainPanelMarginV); 
			oppanel.fillColor.Set(WindowBg);
			
			NEW(grid); 
			grid.bounds.SetLeft(0); grid.bounds.SetTop(15);
			grid.SetSelectionMode(WMGrids.GridSelectSingleRow); grid.onClick.Add(GridClicked);
			grid.alwaysShowScrollX.Set(FALSE); grid.showScrollX.Set(FALSE); 
			grid.alwaysShowScrollY.Set(FALSE); grid.showScrollY.Set(FALSE);		
			grid.allowColResize.Set(FALSE); grid.allowRowResize.Set(FALSE);

			UpdateGrid(TRUE);
			
			IF operations = NIL THEN
				selectNone := 10;
				grid.SetSelection(selectNone, selectNone, selectNone, selectNone);
			END;

			oppanel.AddContent(titleGrid); oppanel.AddContent(grid);
			ASSERT(AosPartitionsLib.operations # NIL);
			AosPartitionsLib.operations.onChanged.Add(OperationEventHandler);
		END Init;
	
		PROCEDURE Finalize*;
		BEGIN
			ASSERT(AosPartitionsLib.operations # NIL);
			AosPartitionsLib.operations.onChanged.Remove(OperationEventHandler);
			alive := FALSE; timer.Wakeup; AwaitDead;
		END Finalize;
		
		PROCEDURE SetDead; BEGIN {EXCLUSIVE} dead := TRUE; END SetDead;
		PROCEDURE AwaitDead; BEGIN {EXCLUSIVE} AWAIT(dead); END AwaitDead;
	
		PROCEDURE PollStatus;
		VAR
			operation : AosPartitionsLib.Operation;
			state : AosPartitionsLib.OperationState;
			result : ARRAY 256 OF CHAR;
			caption, temp : ARRAY 32 OF CHAR;
			i : LONGINT; 
		BEGIN {EXCLUSIVE} (* lock operations *)
			IF operations # NIL THEN 
				grid.Acquire;
				grid.model.Acquire;
				FOR i := 0 TO LEN(operations)-1 DO
					operation := operations[i];
					state := operation.GetState();
					(* Column 4: Status *)
					grid.model.SetCellText(3, i, Utilities.NewString(state.statusString));
					
					(* Column 5: errors *)
					Utilities.IntToStr(state.errorCount, caption);
					grid.model.SetCellText(4, i, Utilities.NewString(caption));
					
					(* Column 6: Progress *)
					IF state.progressValid THEN 
						Utilities.IntToStr(ENTIER(state.cur*100.0 / state.max), caption); Utilities.Append(caption, "%"); 
						grid.model.SetCellText(5, i, Utilities.NewString(caption));
					ELSE
						caption := "";
						grid.model.SetCellText(5, i, Utilities.NewString(caption));						
					END;		
					IF owner # NIL THEN
						IF (state.status * AosPartitionsLib.StatusFinished # {}) & (state.status * AosPartitionsLib.StatusRunning # {}) THEN
							result := "Operation UID "; Utilities.IntToStr(operation.uid, temp); Utilities.Append(result, temp);
							Utilities.Append(result, ": "); Utilities.Append(result, operation.GetResult());
							IF result # "" THEN owner.UpdateStatusLabel(Utilities.NewString(result)); END;
							operation.SetStatus(state.status - AosPartitionsLib.StatusRunning, state.statusString, state.min, state.cur, state.max, state.progressValid);
							IF operation.locktype # AosPartitionsLib.ReaderLock THEN owner.diskmodel.UpdateDisk(operation.disk); END;
							IF operation.invalidateSelection THEN 
								owner.UpdateSelection(-1, -1);
							ELSE
								owner.RefreshSelection;
							END;
							owner.UpdateContent; 
						END;			
					END;
				END;
				grid.model.Release;
				grid.Release;
			END;
		END PollStatus;
	
	BEGIN {ACTIVE}
		WHILE alive DO
			PollStatus;
			timer.Sleep(100);	
		END;
		SetDead;
	END PendingOperations;
	
VAR
	window : Window;
	plugins- : AosPlugins.Registry;

PROCEDURE LoadDefaultPlugins;
VAR 
	operations : PendingOperations;
	m: AosModules.Module; c: AosModules.CommandProc;
	ignore : LONGINT;
	msg : ARRAY 2 OF CHAR;    
BEGIN
	NEW(operations); plugins.Add(operations, ignore); 
	m:= AosModules.ThisModule("WMPartitionsPlugins", ignore, msg);
	IF m # NIL THEN
		c := AosModules.ThisCommand(m, "Install");
		IF c # NIL THEN c() END
	END;
END LoadDefaultPlugins;
			
PROCEDURE Cleanup;
VAR timer : AosKernel.Timer;
BEGIN {EXCLUSIVE}
	IF window # NIL THEN window.Close; window := NIL; END;
	(* TODO: Remove timer hack *)
	NEW(timer); timer.Sleep(500);
	AosPlugins.main.Remove(plugins);
END Cleanup;

PROCEDURE Open*(ptr : PTR) : PTR;
BEGIN {EXCLUSIVE}
	IF window = NIL THEN 
		LoadDefaultPlugins;
		NEW(window, NIL); 
	ELSE
		window.manager.SetFocus(window);
		window.manager.ToFront(window);
	END;
	RETURN NIL; 
END Open;

PROCEDURE Restore*(par : ANY) : ANY;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		LoadDefaultPlugins;
		NEW(window, par(WMRestorable.Context));
	END; 
	RETURN NIL 
END Restore;

BEGIN
	NEW(plugins, "PartitionPlugin", "WMPartitions plugins");
	AosModules.InstallTermHandler(Cleanup);
END WMPartitions.

WMPartitions.Open ~ 

S.Free WMPartitionsPlugins  AosDiskTests AosDiskBench AosPartitions AosFATScavenger WMPartitions AosPartitionsLib ~

PC0.Compile \s AosPartitionsLib.Mod WMPartitions.Mod AosFATScavenger.Mod AosDiskBench.Mod AosDiskTests.Mod AosPartitions.Mod WMPartitionsPlugins.Mod~

AosTar.Create PartitionTool.Tar
AosPartitions.Mod
AosPartitionsLib.Mod
WMPartitions.Mod
WMPartitionsPlugins.Mod
AosDiskBench.Mod
AosDiskTests.Mod
AosFATScavenger.Mod
~
