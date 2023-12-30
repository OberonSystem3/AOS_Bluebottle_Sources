MODULE PET; (** AUTHOR "TF, PL"; PURPOSE "Programmer's Editing Tool"; *)
(**
 * Shortcuts:
 *
 *	CTRL-F:		Show search panel of current page, set focus to its editor and clear the content of the editor
 *	CTRL-N:	Find next occurence downwards
 *	CTRL-P:		Find next occurence upwards
 *	CTRL-W:	Toggle wrap on/off
 *
 *	CTRL-0:		Set cursor to position zero
 *
 *	CTRL-O:	Set focus to filename editor and clear its content
 *	CTRL-S:		Store current page
 *
 *	CTRL-M:	Toggle visibility of sidepanel
 *	CTRL-E:		Toggle visibility of error markers
 *	
 *	CTRL-H:		Compile file opened in current page
 *	CTRL-U:		Unload module opened in current  page
 *	CTRL-D:	Diff current tab to file
 *
 *	CTRL-PgUp	Load PET state from file
 * 	CTRL-PgDn	Save PET state to file
 *
 *	CTRL-Del	Select previous tab
 *	CTRL-End	Select next tab
 *
 * History:
 *
 *	21.03.2006	Replaced Window.form field by local variable in &New, added SearchPanel.Finalize & PETPanel.Finalize,
 *				Remove onTextChanged listener in Window.Load when assigning another text object, Finalize Panels
 *				in Window.Close (staubesv)
 *	29.05.2006	Introduced OptionsStringLength constant (staubesv)
 *	07.08.2006	Remember option string when switching between tabs, re-calculate tab width when storing a file, cleanup (staubesv)
 *	22.12.2006	Search panel editor's size improved, added shortcuts, more generic error handlig, small cleanups (staubesv)
 *	09.01.2007	Save desktop capabilities enhanced, state storing/restoring, case-insensitive searching, search direction option,
 *				different picture for warnings (staubesv)
 *	28.02.2007	Window.LoadHandler: Save option string of current tab before open a new tab when loading files,
 *				changed compile file shortcut from CTRL-Y to CTRL-H since CTRL-Y is used by Editor for Redo,
 *				set keyboard focus to editor when using CTRL-N or CTRL-P, added CTRL-0 & CTRL-W, CTRL-D & TAB  (staubesv)
 *)

IMPORT
	AosOut, AosModules, AosCommands, AosIO, AosInputs, AosFS, WMRestorable, XML, XMLScanner, XMLParser, XMLObjects,
	WMStandardComponents, WMGraphics, WMGraphicUtilities,
	WMComponents, WMRectangles, WMMessages, WMDialogs,
	WMTextView, WMEditors, Utilities, AosTextUtilities, AosTexts, WMBitmapFont,
	WMWindowManager, WMGrids, WMMacros, WMPopups, WMDropTarget,
	PCM, PC0, ModuleTrees, WMXMLTree, UTF8Strings, AosConfig, AosCodecs, WMTabComponents, UndoManager;
	
CONST

	BackupParanoid = TRUE;
	
	(* If you really don't like any shortcuts, disable them! *)
	DisableShortcuts = FALSE;
	
	ScratchTextFilename = "PETScratch.Text";
	StateFileExtension = ".pet";
	
	DiffCommand = "WMDiff.Open";
		
	DefaultOptionsString = "\Ws";
	OptionsStringLength = 128;
	
	MaxNbrOfTabs = 100;
	
	ErrorListSize = 50;

	PictureError = "errorpos.png";
	PictureWarning = "warningpos.png";

	WindowTitle = "Programmer's Editing Tool v2.1";
	
	WrapOn = "Wrap is On";
	WrapOff = "Wrap is Off";
	
	CaseSensitiveOn = "CaseSensitive is On";
	CaseSensitiveOff = "CaseSensitive is Off";
	
	DirectionUp = "Direction is UP";
	DirectionDown = "Direction is DOWN";

	(* ErrorInfo.type *)
	TypeInformation = 0;
	TypeError = 1;
	TypeWarning = 2;
	
	EditorFocus = 1;
	SplitEditorFocus = 2;
	
TYPE
	ErrorInfo = RECORD
		type : LONGINT;
		pos : POINTER TO ARRAY OF WMTextView.PositionMarker;
		err : LONGINT;
		msg : ARRAY 128 OF CHAR;
	END;
	
	ErrorList = POINTER TO ARRAY OF ErrorInfo;
	
	KillerMsg = OBJECT
	END KillerMsg;
	
	CaptionObject = OBJECT
	VAR caption- : ARRAY 128 OF CHAR;
		
		PROCEDURE &New(caption: ARRAY OF CHAR);
		BEGIN
			COPY(caption, SELF.caption);
		END New;		
	END CaptionObject;

	StackData = POINTER TO ARRAY OF LONGINT;
	
	PositionStack = OBJECT
		VAR 
			data: StackData;
			size, top: LONGINT;
			
		PROCEDURE & Init;
		BEGIN
			size := 32;
			NEW(data, 32);
		END Init;
			
		PROCEDURE Push(l: LONGINT);
		BEGIN
			IF top = size THEN Expand END;
			data[top] := l;
			INC(top);
		END Push;
		
		PROCEDURE Pop(): LONGINT;
		VAR val: LONGINT;
		BEGIN
			IF top > 0 THEN
				DEC(top);
				val := data[top];
			ELSE
				val := -1;
			END;
			RETURN val;
		END Pop;
		
		PROCEDURE Expand;
		VAR
			newSize, i: LONGINT;
			newData: StackData;
		BEGIN
			newSize := 2*size;
			NEW(newData, newSize);
			FOR i := 0 TO size-1 DO
				data[i] := newData[i];
			END;
			size := newSize;
			data := newData;
		END Expand;
		
		PROCEDURE Invalidate;
		BEGIN
			IF size > 32 THEN Init END;
			top := 0;
		END Invalidate;
	END PositionStack;
	
	SearchPanel = OBJECT(WMComponents.VisualComponent)
	VAR
		upperPanel, lowerPanel: WMStandardComponents.Panel;
		searchBtn, replBtn, replAllBtn, closeBtn, wrapBtn, caseSensitiveBtn, directionBtn: WMStandardComponents.Button;
		searchEdit, replEdit: WMEditors.Editor;
		searchLabel, replLabel: WMStandardComponents.Label;
		textView: WMTextView.TextView;
		text: AosTexts.Text;
		pos, len: LONGINT;
		posValid, wrap, caseSensitive, backwards  : BOOLEAN;
		wrapOn, wrapOff, caseSensitiveOn, caseSensitiveOff, directionUp, directionDown: Utilities.String;
		positionStack: PositionStack;

		lastPos : LONGINT;
		lastBackwards : BOOLEAN;
			
			PROCEDURE & Init;
			BEGIN
				Init^;
				
				caseSensitive := TRUE; backwards := FALSE; 
				lastPos := -1; lastBackwards := FALSE;

				NEW(upperPanel); upperPanel.alignment.Set(WMComponents.AlignTop);
				upperPanel.bounds.SetHeight(20);
				AddContent(upperPanel);

				NEW(searchLabel); searchLabel.alignment.Set(WMComponents.AlignLeft);
				searchLabel.bounds.SetWidth(40); searchLabel.fillColor.Set(0FFFFFFFFH);
				searchLabel.alignH.Set(WMGraphics.AlignCenter);
				searchLabel.SetCaption("Search");
				upperPanel.AddContent(searchLabel);

				NEW(searchEdit); searchEdit.alignment.Set(WMComponents.AlignLeft);
				searchEdit.bounds.SetWidth(200); searchEdit.multiLine.Set(FALSE);
				searchEdit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1));
				searchEdit.tv.showBorder.Set(TRUE);
				searchEdit.fillColor.Set(0FFFFFFFFH);
				searchEdit.onEnter.Add(SearchHandler);
				searchEdit.text.onTextChanged.Add(TextChanged);
				searchEdit.tv.SetExtFocusHandler(FocusHandler);
				upperPanel.AddContent(searchEdit);

				NEW(replLabel); replLabel.alignment.Set(WMComponents.AlignLeft);
				replLabel.bounds.SetWidth(50); replLabel.fillColor.Set(0FFFFFFFFH);
				replLabel.alignH.Set(WMGraphics.AlignCenter);
				replLabel.SetCaption("Replace");
				upperPanel.AddContent(replLabel);
				
				NEW(replEdit); replEdit.alignment.Set(WMComponents.AlignClient);
				replEdit.bounds.SetWidth(150); replEdit.multiLine.Set(FALSE);
				replEdit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1));
				replEdit.tv.showBorder.Set(TRUE);
				replEdit.fillColor.Set(0FFFFFFFFH);
				replEdit.onEnter.Add(ReplaceHandler);
				upperPanel.AddContent(replEdit);

				NEW(lowerPanel); lowerPanel.alignment.Set(WMComponents.AlignTop);
				lowerPanel.bounds.SetHeight(20);
				AddContent(lowerPanel);

				NEW(searchBtn); searchBtn.alignment.Set(WMComponents.AlignLeft);
				searchBtn.caption.SetAOC("Search");
				searchBtn.bounds.SetWidth(80);
				searchBtn.onClick.Add(SearchHandler);
				lowerPanel.AddContent(searchBtn);

				NEW(replBtn); replBtn.alignment.Set(WMComponents.AlignLeft);
				replBtn.caption.SetAOC("Replace");
				replBtn.bounds.SetWidth(80);
				replBtn.onClick.Add(ReplaceHandler);
				lowerPanel.AddContent(replBtn);

				NEW(replAllBtn); replAllBtn.alignment.Set(WMComponents.AlignLeft);
				replAllBtn.caption.SetAOC("Replace All");
				replAllBtn.bounds.SetWidth(80);
				replAllBtn.onClick.Add(ReplaceAllHandler);
				lowerPanel.AddContent(replAllBtn);

				wrapOn := Utilities.NewString(WrapOn);
				wrapOff := Utilities.NewString(WrapOff);

				NEW(wrapBtn); wrapBtn.alignment.Set(WMComponents.AlignLeft);
				IF wrap THEN wrapBtn.caption.Set(wrapOn) ELSE wrapBtn.caption.Set(wrapOff) END;
				wrapBtn.bounds.SetWidth(80);
				wrapBtn.onClick.Add(WrapHandler);
				lowerPanel.AddContent(wrapBtn);
				
				caseSensitiveOn := Utilities.NewString(CaseSensitiveOn);
				caseSensitiveOff := Utilities.NewString(CaseSensitiveOff);

				NEW(caseSensitiveBtn); caseSensitiveBtn.alignment.Set(WMComponents.AlignLeft);
				IF caseSensitive THEN caseSensitiveBtn.caption.Set(caseSensitiveOn) ELSE caseSensitiveBtn.caption.Set(caseSensitiveOff); END;
				caseSensitiveBtn.bounds.SetWidth(120);
				caseSensitiveBtn.onClick.Add(CaseSensitiveHandler);
				lowerPanel.AddContent(caseSensitiveBtn);

				directionUp := Utilities.NewString(DirectionUp);
				directionDown := Utilities.NewString(DirectionDown);

				NEW(directionBtn); directionBtn.alignment.Set(WMComponents.AlignLeft);
				IF backwards THEN directionBtn.caption.Set(directionUp) ELSE directionBtn.caption.Set(directionDown); END;
				directionBtn.bounds.SetWidth(120);
				directionBtn.onClick.Add(DirectionHandler);
				lowerPanel.AddContent(directionBtn);

				NEW(closeBtn); closeBtn.alignment.Set(WMComponents.AlignLeft);
				closeBtn.caption.SetAOC("Close");
				closeBtn.bounds.SetWidth(80);
				closeBtn.onClick.Add(CloseHandler);
				lowerPanel.AddContent(closeBtn);
				
				NEW(positionStack);
			END Init;
			
			PROCEDURE SetText(t: AosTexts.Text);
			BEGIN
				text := t;
				posValid := FALSE
			END SetText;
			
			PROCEDURE SetTextView(tv: WMTextView.TextView);
			BEGIN
				textView := tv;
				posValid := FALSE;
			END SetTextView;
			
			PROCEDURE FocusHandler(hasFocus: BOOLEAN);
			BEGIN
				IF textView = NIL THEN RETURN END;
				IF hasFocus THEN
					pos := textView.cursor.GetPosition();
					positionStack.Invalidate;
				END;
			END FocusHandler;
			
			PROCEDURE WrapHandler(sender, data: ANY);
			BEGIN
				wrap := ~wrap;
				IF wrap THEN wrapBtn.caption.Set(wrapOn) ELSE wrapBtn.caption.Set(wrapOff) END;
			END WrapHandler;
			
			PROCEDURE CaseSensitiveHandler(sender, data : ANY);
			BEGIN
				caseSensitive := ~caseSensitive;
				IF caseSensitive THEN caseSensitiveBtn.caption.Set(caseSensitiveOn) ELSE caseSensitiveBtn.caption.Set(caseSensitiveOff); END;
			END CaseSensitiveHandler;
			
			PROCEDURE DirectionHandler(sender, data : ANY);
			BEGIN
				backwards := ~backwards;
				IF backwards THEN directionBtn.caption.Set(directionUp) ELSE directionBtn.caption.Set(directionDown); END;
			END DirectionHandler;
			
			PROCEDURE TextChanged(sender, data: ANY);
			VAR
				changeInfo: AosTexts.TextChangeInfo;
				from : LONGINT;
			BEGIN
				IF data IS AosTexts.TextChangeInfo THEN
					changeInfo := data(AosTexts.TextChangeInfo);
					IF (changeInfo.op = AosTexts.OpInsert) & (changeInfo.len = 1) THEN
						positionStack.Push(pos);
						SearchAndHighlight(pos);
					ELSIF (changeInfo.op = AosTexts.OpDelete) & (changeInfo.len = 1) THEN
						from := positionStack.Pop();
						IF from = 1 THEN from := pos END;
						SearchAndHighlight(from);
					ELSE
						positionStack.Invalidate();
					END;
				END;
			END TextChanged;
						
			PROCEDURE SearchHandler(sender, data: ANY);
			BEGIN
				IF textView = NIL THEN RETURN END;
				SearchAndHighlight(textView.cursor.GetPosition());
			END SearchHandler;
			
			PROCEDURE ReplaceHandler(sender, data: ANY);
			VAR
				replStr : ARRAY 64 OF CHAR;
				ucsStr: ARRAY 64 OF AosTexts.Char32;
				idx: LONGINT;
			BEGIN
				IF text = NIL THEN RETURN END;
				IF posValid THEN
					replEdit.GetAsString(replStr);
					UTF8Strings.UTF8toUnicode(replStr, ucsStr, idx);
					text.AcquireWrite();
					Replace(ucsStr);
					text.ReleaseWrite();
					Highlight;
					SearchHandler(sender, data);
				END;
			END ReplaceHandler;
			
			PROCEDURE ReplaceAllHandler(sender, data: ANY);
			VAR
				searchStr, replStr: ARRAY 64 OF CHAR;
				ucsSearchStr, ucsReplStr: ARRAY 64 OF AosTexts.Char32;
				oldBackwards : BOOLEAN;
				idx: LONGINT;
			BEGIN
				IF text = NIL THEN RETURN END;
				replEdit.GetAsString(replStr);
				UTF8Strings.UTF8toUnicode(replStr, ucsReplStr, idx); idx := 0;
				searchEdit.GetAsString(searchStr);
				UTF8Strings.UTF8toUnicode(searchStr, ucsSearchStr, idx);
				text.AcquireWrite();
				text.AcquireRead();
				oldBackwards := backwards;
				backwards := FALSE;
				Search(ucsSearchStr, 0);
				WHILE posValid DO
					Replace(ucsReplStr);
					Search(ucsSearchStr, pos + len);
				END;
				backwards := oldBackwards;
				text.ReleaseRead();
				text.ReleaseWrite();
			END ReplaceAllHandler;
			
			PROCEDURE Replace(VAR ucsStr: ARRAY OF AosTexts.Char32);
			BEGIN
				text.Delete(pos, len);
				text.InsertUCS32(pos, ucsStr);
				len := AosTextUtilities.UCS32StrLength(ucsStr);
				posValid := FALSE;
			END Replace;
			
			PROCEDURE Search(VAR ucsStr: ARRAY OF AosTexts.Char32; from: LONGINT);
			BEGIN
				IF ucsStr[0] = 0 THEN posValid := FALSE; RETURN; END;
				IF caseSensitive & ~backwards THEN
					pos := AosTextUtilities.Pos(ucsStr, from, text);
				ELSE
					(* We want to search the text that's on the left hand side of the cursor. If we start searching at position 'from',
					we also consider the character at the current cursor position, which is on the left hand side of the cursro *)
					IF (backwards) & (from > 1) THEN DEC(from); END;
					
					pos := AosTextUtilities.GenericPos(ucsStr, from, text, ~caseSensitive, backwards);
				END;
				len := AosTextUtilities.UCS32StrLength(ucsStr);
				IF pos > -1 THEN posValid := TRUE
				ELSE posValid := FALSE
				END;
			END Search;
			
			PROCEDURE SearchAndHighlight(from: LONGINT);
			VAR
				searchStr : ARRAY 64 OF CHAR;
				ucsStr: ARRAY 64 OF AosTexts.Char32;
				length : LONGINT;
				idx: LONGINT;
			BEGIN
				IF text = NIL THEN RETURN END;
				searchEdit.GetAsString(searchStr);
				IF searchStr # "" THEN
					UTF8Strings.UTF8toUnicode(searchStr, ucsStr, idx);
					text.AcquireRead();
					Search(ucsStr, from);
					(* Detect whether we have found the last search result again but in different search direction *)
					IF (((pos = lastPos) OR (lastPos = -1)) & (lastBackwards # backwards))  THEN
						length := AosTextUtilities.UCS32StrLength(ucsStr);
						IF backwards THEN
							IF from >= length - 1 THEN
								Search(ucsStr, from - Utilities.Length(searchStr));
							END;
						ELSE
							IF from + length < text.GetLength() THEN
								Search(ucsStr, from + Utilities.Length(searchStr));
							END;
						END;
					END;
					IF (pos = -1) & wrap THEN 
						IF backwards THEN
							Search(ucsStr, text.GetLength() - 1);
						ELSE
							Search(ucsStr, 0);
						END;
					END;
					text.ReleaseRead();
				END; 
				lastPos := pos; lastBackwards := backwards;
				Highlight;
			END SearchAndHighlight;
			
			PROCEDURE Highlight;
			VAR string : ARRAY 128 OF CHAR;
			BEGIN
				IF textView = NIL THEN RETURN END;
				IF posValid THEN
					textView.selection.SetFrom(pos);
					textView.selection.SetTo(pos + len);
					IF backwards THEN 
						textView.cursor.SetPosition(pos);
					ELSE
						textView.cursor.SetPosition(pos + len);
					END;
				END;
				searchEdit.GetAsString(string);
				IF (string = "") THEN textView.selection.SetFromTo(0, 0); END;
			END Highlight;		
			
			PROCEDURE CloseHandler(sender, data: ANY);
			BEGIN
				visible.Set(FALSE);
			END CloseHandler;
			
			PROCEDURE Finalize;
			BEGIN
				Finalize^;
				IF searchEdit # NIL THEN searchEdit.text.onTextChanged.Remove(TextChanged); END;
			END Finalize;
			
	END SearchPanel;
	
	ScratchPanel = OBJECT(WMComponents.VisualComponent)

		PROCEDURE &Init;
		VAR l : WMStandardComponents.Label;
			e : WMEditors.Editor;
		BEGIN
			Init^;
			NEW(l); l.alignment.Set(WMComponents.AlignTop); l.bounds.SetHeight(20); 
			l.fillColor.Set(0CCCCCCFFH); l.caption.SetAOC("Scratch text");
			AddContent(l);
			
			NEW(e); e.alignment.Set(WMComponents.AlignClient);
			e.tv.showBorder.Set(TRUE);
			AddContent(e);
			e.SetText(scratchText)
		END Init;
		
		PROCEDURE Finalize;
		BEGIN
			Finalize^;
			StoreScratchText
		END Finalize;
	
	END ScratchPanel;
	
	URLDropTarget* = OBJECT(WMDropTarget.DropTarget);
	VAR win : Window;

		PROCEDURE &New(win : Window);
		BEGIN
			SELF.win := win
		END New;

		PROCEDURE GetInterface*(type : LONGINT) : WMDropTarget.DropInterface;
		VAR di : DropURL;
		BEGIN
			IF type = WMDropTarget.TypeURL THEN
				NEW(di, SELF.win);
				RETURN di
			ELSE RETURN NIL
			END
		END GetInterface;				
	END URLDropTarget;
	
	DropURL* = OBJECT(WMDropTarget.DropURLs)
	VAR win : Window;
		
		PROCEDURE &New(win: Window);
		BEGIN
			SELF.win := win;
		END New;
		
		PROCEDURE URL*(url : ARRAY OF CHAR; VAR res : LONGINT);
		BEGIN
			win.Load(url, "AUTO");
			res := 0
		END URL;	
	END DropURL;	
	
	PETPanel = OBJECT(WMComponents.VisualComponent)
	VAR	
		editor-, splitEditor, logEdit : WMEditors.Editor;
		errorLog : WMGrids.GenericGrid;
		scratchPanel, splitPanel : WMStandardComponents.Panel;
		sidePanel : WMStandardComponents.Panel;
		logPanel, editPanel: WMStandardComponents.Panel;
		searchPanel: SearchPanel;

		moduleTree: ModuleTrees.ModuleTree;
		xmlTree : WMXMLTree.XMLView;
			
		modified, splitted: BOOLEAN;
		focus : LONGINT;
		
		codecFormat: ARRAY 128 OF CHAR;
		autoCodecFormat: ARRAY 128 OF CHAR;
		filename : ARRAY 256 OF CHAR;
		optionsString : ARRAY OptionsStringLength OF CHAR;
		
		errorList : ErrorList;
		errlist : PCM.ErrorList;
		errorSummaryStr : ARRAY 128 OF CHAR;
		nbrOfErrors, nbrOfWarnings : LONGINT;
		showErrorMarkers : BOOLEAN;
	
		owner : Window;		

		PROCEDURE &Init();
		VAR
			resizerH, resizerV: WMStandardComponents.Resizer;
			sp : ScratchPanel;
			i : LONGINT;
			um: UndoManager.UndoManager;
			colWidths : WMGrids.Spacings;
		BEGIN	
			Init^;
			showErrorMarkers := TRUE;
			COPY("Untitled.Mod", filename);	
			
			(* -- left tool area *)
			NEW(sidePanel);
			sidePanel.bounds.SetWidth(250); sidePanel.alignment.Set(WMComponents.AlignLeft);
			AddContent(sidePanel);
			
			NEW(resizerH); resizerH.alignment.Set(WMComponents.AlignRight);
			resizerH.bounds.SetWidth(4);
			sidePanel.AddContent(resizerH);
			
			(* scratch panel *)			
			NEW(scratchPanel);
			scratchPanel.bounds.SetHeight(250); scratchPanel.alignment.Set(WMComponents.AlignBottom);

			NEW(resizerV); resizerV.alignment.Set(WMComponents.AlignTop);
			resizerV.bounds.SetHeight(4);
			scratchPanel.AddContent(resizerV);

			NEW(sp); sp.alignment.Set(WMComponents.AlignClient);
			scratchPanel.AddContent(sp);
			
			sidePanel.AddContent(scratchPanel);					
			
			(* -- Editor Area *)
			NEW(editPanel); editPanel.alignment.Set(WMComponents.AlignClient);
			AddContent(editPanel);
			
			NEW(logPanel);
			logPanel.alignment.Set(WMComponents.AlignBottom);
			logPanel.bounds.SetHeight(130);

			NEW(resizerH); resizerH.alignment.Set(WMComponents.AlignTop);
			resizerH.bounds.SetHeight(4);
			logPanel.AddContent(resizerH);		
						
			NEW(logEdit); logEdit.bounds.SetHeight(30); logEdit.alignment.Set(WMComponents.AlignBottom);
			logEdit.allowScrollbars.Set(FALSE);
			logEdit.tv.showBorder.Set(TRUE); logEdit.visible.Set(FALSE);
			editPanel.AddContent(logEdit);			
			editPanel.AddContent(logPanel);

			NEW(errorLog);
			errorLog.alignment.Set(WMComponents.AlignClient);
			errorLog.nofCols.Set(3);
			errorLog.fixedRows.Set(1);
			errorLog.adjustFocusPosition.Set(FALSE);			
			NEW(colWidths, 3); 
			colWidths[0] := 60;
			colWidths[1] := 40;
			colWidths[2] := 2048;
			errorLog.SetColSpacings(colWidths);
			errorLog.SetDrawCellProc(DrawCell);
			errorLog.onClick.Add(ErrorClick);
			errorLog.SetSelectionMode(WMGrids.GridSelectSingleRow);
			logPanel.AddContent(errorLog);
			
			NEW(searchPanel);
			searchPanel.alignment.Set(WMComponents.AlignBottom);
			searchPanel.bounds.SetHeight(45); searchPanel.visible.Set(FALSE);
			editPanel.AddContent(searchPanel);
			
			NEW(splitPanel);
			splitPanel.alignment.Set(WMComponents.AlignBottom);
			splitPanel.bounds.SetHeight(400);
			editPanel.AddContent(splitPanel);
			
			NEW(editor); editor.alignment.Set(WMComponents.AlignClient); editor.tv.showBorder.Set(TRUE);
			editor.tv.SetExtFocusHandler(EditorFocusHandler);
			editPanel.AddContent(editor);
			editor.macros.Add(WMMacros.Handle);
			editor.multiLine.Set(TRUE);
			editor.tv.SetWrapMode({});
			editor.tv.onCursorChanged := CursorChanged;
			editor.text.onTextChanged.Add(TextChanged);
			
			searchPanel.SetText(editor.text);
			
			NEW(resizerV);
			resizerV.bounds.SetHeight(5); resizerV.alignment.Set(WMComponents.AlignTop);
			resizerV.fillColor.Set(0808080FFH);
			splitPanel.AddContent(resizerV);
						
			NEW(splitEditor); splitEditor.alignment.Set(WMComponents.AlignClient); splitEditor.tv.showBorder.Set(TRUE);
			splitEditor.tv.SetExtFocusHandler(SplitEditorFocusHandler);
			splitPanel.AddContent(splitEditor);
			splitEditor.macros.Add(WMMacros.Handle);
			splitEditor.multiLine.Set(TRUE);
			splitEditor.tv.SetWrapMode({});
			splitEditor.SetText(editor.text);
			logPanel.visible.Set(FALSE);
			splitPanel.visible.Set(FALSE);
			
			NEW(errlist, ErrorListSize);
			NEW(errorList, ErrorListSize);
			FOR i := 0 TO LEN(errorList)-1 DO
				NEW(errorList[i].pos, 2);	(* number of editors *)
			END;			
			
			modified := FALSE;
			splitted := FALSE;
			codecFormat := "AUTO";
			autoCodecFormat := "";
			optionsString := DefaultOptionsString;
			
			NEW(um, 1001, TRUE);
			editor.text.SetUndoManager(um);
			editor.SetUndoManager(um);
		END Init;
				
		PROCEDURE DrawCell(canvas : WMGraphics.Canvas; w, h : LONGINT; state : SET; x, y : LONGINT);
		VAR color: LONGINT; str : ARRAY 128 OF CHAR;
		BEGIN
			color := WMGraphics.RGBAToColor(255, 255, 255, 255);
			IF state * {WMGrids.CellFixed, WMGrids.CellSelected} = {WMGrids.CellFixed, WMGrids.CellSelected} THEN 
				color := WMGraphics.RGBAToColor(0, 128, 255, 255) 
			ELSIF WMGrids.CellFixed IN state THEN
				color := WMGraphics.RGBAToColor(196, 196, 196, 255) 
			ELSIF WMGrids.CellSelected IN state THEN
				color := WMGraphics.RGBAToColor(196, 196, 255, 255)
			END;
			canvas.SetColor(WMGraphics.RGBAToColor(0, 0, 0, 255));
			canvas.SetFont(WMBitmapFont.bimbofont);
			
			canvas.Fill(WMRectangles.MakeRect(0, 0, w, h), color, WMGraphics.ModeCopy);
			IF (WMGrids.CellFocused IN state) & ~(WMGrids.CellHighlighted IN state) THEN 
				WMGraphicUtilities.DrawBevel(canvas, WMRectangles.MakeRect(0, 0, w, h), 1, TRUE, WMGraphics.RGBAToColor(0, 0, 0, 196), 
				WMGraphics.ModeSrcOverDst)
			END;

			IF y = 0 THEN
				CASE x OF
					| 0 : str := "pos"
					| 1 : str := "err"
					| 2 : 
						str := "Error Str";
						Utilities.Append(str, " ("); Utilities.Append(str, errorSummaryStr); Utilities.Append(str, ")");
				ELSE
				END
			ELSIF (errorList # NIL) & (y - 1 >= 0) & (y < LEN(errorList^)) THEN
				CASE x OF
					| 0 : 
						IF errorList[y - 1].pos[0] # NIL THEN Utilities.IntToStr(errorList[y - 1].pos[0].GetPosition(), str) END;
						IF errorList[y - 1].type = TypeError THEN
							color := WMGraphics.RGBAToColor(255, 128, 128, 90);
							canvas.Fill(WMRectangles.MakeRect(0, 0, w, h), color, WMGraphics.ModeSrcOverDst);
						ELSIF errorList[y - 1].type = TypeWarning THEN
							color := WMGraphics.RGBAToColor(255, 255, 128, 90);
							canvas.Fill(WMRectangles.MakeRect(0, 0, w, h), color, WMGraphics.ModeSrcOverDst);
						ELSIF errorList[y - 1].type = TypeInformation THEN
							(* no coloring *)
						END;
					| 1 : Utilities.IntToStr(errorList[y - 1].err, str);
					| 2 : COPY(errorList[y - 1].msg, str) 
				ELSE
				END
			END;

			canvas.DrawString(4, h - 4, str)
		END DrawCell;
		
		PROCEDURE ErrorClick(sender, data : ANY);
		VAR scol, srow, ecol, erow, y : LONGINT;
			focusEditor: WMEditors.Editor;
			index: LONGINT;
		BEGIN
			errorLog.GetSelection(scol, srow, ecol, erow);
			y := srow;
			IF (errorList # NIL) & (y > 0) & (y <= LEN(errorList^)) THEN
				DEC(y);	(* first row is header row *)
				IF focus = EditorFocus THEN focusEditor := editor; index := 0
				ELSIF focus = SplitEditorFocus THEN focusEditor := splitEditor; index := 1
				ELSE RETURN
				END;
				IF errorList[y].pos[index] # NIL THEN
					focusEditor.tv.cursor.SetPosition(errorList[y].pos[index].GetPosition());
					focusEditor.SetFocus
				END
			END
		END ErrorClick;
	
		PROCEDURE EditorFocusHandler(hasFocus: BOOLEAN);
		BEGIN
			IF hasFocus THEN
				focus := EditorFocus;
				searchPanel.SetTextView(editor.tv);
				IF moduleTree # NIL THEN moduleTree.SetEditor(editor) END;
				IF xmlTree # NIL THEN xmlTree.SetEditor(editor) END;
			END;
		END EditorFocusHandler;
		
		PROCEDURE SplitEditorFocusHandler(hasFocus: BOOLEAN);
		BEGIN
			IF hasFocus THEN
				focus := SplitEditorFocus;
				searchPanel.SetTextView(splitEditor.tv);
				IF moduleTree # NIL THEN moduleTree.SetEditor(splitEditor) END;
				IF xmlTree # NIL THEN xmlTree.SetEditor(splitEditor) END;
			END
		END SplitEditorFocusHandler;
		
		PROCEDURE TextChanged(sender, data : ANY);
		BEGIN
			IF logPanel.visible.Get() THEN
				logPanel.Invalidate
			END;
			IF ~modified THEN
				IF (owner # NIL) THEN owner.SetModified(TRUE) END;
				modified := TRUE
			END;
			CursorChanged
		END TextChanged;
		
		PROCEDURE CursorChanged;
		VAR position : LONGINT; pos : ARRAY 16 OF CHAR;
		BEGIN
			position := editor.tv.cursor.GetPosition();
			Utilities.IntToStr(position, pos);
			owner.positionEdit.SetAsString(pos);		
		END CursorChanged;			
			
		PROCEDURE Finalize;
		BEGIN
			Finalize^;
			IF (editor # NIL) & (editor.text # NIL) THEN
				editor.text.onTextChanged.Remove(TextChanged);
				editor.tv.onCursorChanged := NIL;
				IF editor.undoMgr # NIL THEN
					editor.undoMgr.nrUndoListener := NIL;
					editor.undoMgr.nrRedoListener := NIL;
				END;
			END;
		END Finalize;
		
	END PETPanel;

	Window* = OBJECT (WMComponents.FormWindow)
	VAR
		topToolbar, statusPanel : WMStandardComponents.Panel;
		filenameEdit, optionsEdit, positionEdit: WMEditors.Editor;
		load, store, close, compile, findPC, undo, redo: WMStandardComponents.Button;
		splitBtn, formatBtn, searchBtn, lbBtn : WMStandardComponents.Button;
		popup: WMPopups.Popup;
		
		tabs : WMTabComponents.Tabs;
		pages : ARRAY MaxNbrOfTabs OF PETPanel; 
		tabList : ARRAY MaxNbrOfTabs OF WMTabComponents.Tab;
		currentPage- : PETPanel;
		currentPageNr : LONGINT;
		page : WMStandardComponents.Panel;
		
		xmlHasErrors : BOOLEAN;
		
		codecFormat: ARRAY 128 OF CHAR;
		autoCodecFormat: ARRAY 128 OF CHAR;		

		PROCEDURE CreateForm():WMComponents.VisualComponent;
		VAR panel : WMStandardComponents.Panel;
			posLabel : WMStandardComponents.Label;
			font: WMGraphics.Font;
			dx, dy: LONGINT;
		BEGIN
			(* -- Main Panel holding the tabs, toolbar and tabcontents (instance of PETPanel) *)
			NEW(panel); panel.bounds.SetExtents(1024, 768); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);				
			
			(* -- Tabs for the PETPanels *)
			NEW(tabs); tabs.fillColor.Set(00000CCCCH); tabs.bounds.SetHeight(20); tabs.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(tabs); tabs.SetExtDragDroppedHandler(DragDroppedH);

			(* -- top toolbar *)
			NEW(topToolbar); topToolbar.bounds.SetHeight(20); topToolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(topToolbar);						

			NEW(filenameEdit); filenameEdit.alignment.Set(WMComponents.AlignLeft);
			filenameEdit.multiLine.Set(FALSE); filenameEdit.bounds.SetWidth(200);
			topToolbar.AddContent(filenameEdit); filenameEdit.fillColor.Set(0FFFFFFFFH);
			filenameEdit.tv.showBorder.Set(TRUE);
			filenameEdit.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1));
			filenameEdit.onEnter.Add(LoadHandler);
						
			NEW(load); load.caption.SetAOC("Load"); load.alignment.Set(WMComponents.AlignLeft);
			load.onClick.Add(LoadHandler);
			topToolbar.AddContent(load);
			
			NEW(store); store.caption.SetAOC("Store"); store.alignment.Set(WMComponents.AlignLeft); 
			store.onClick.Add(StoreHandler);
			topToolbar.AddContent(store);
			
			NEW(close); close.caption.SetAOC("Close"); close.alignment.Set(WMComponents.AlignLeft); 
			close.onClick.Add(CloseHandler);
			topToolbar.AddContent(close);			
			
			NEW(formatBtn); formatBtn.caption.SetAOC("Format : ---"); formatBtn.alignment.Set(WMComponents.AlignLeft);
			formatBtn.SetExtPointerDownHandler(FormatHandler);
			formatBtn.bounds.SetWidth(3 * formatBtn.bounds.GetWidth());
			topToolbar.AddContent(formatBtn);
			
			NEW(searchBtn); searchBtn.caption.SetAOC("Search"); searchBtn.alignment.Set(WMComponents.AlignLeft);
			searchBtn.onClick.Add(SearchHandler);						
			topToolbar.AddContent(searchBtn);
			
			NEW(compile); compile.caption.SetAOC("Compile"); compile.alignment.Set(WMComponents.AlignLeft); 
			compile.onClick.Add(Compile);
			topToolbar.AddContent(compile);

			NEW(findPC); findPC.caption.SetAOC("Find PC"); findPC.alignment.Set(WMComponents.AlignLeft); 
			findPC.onClick.Add(FindPC);
			topToolbar.AddContent(findPC);
			
			NEW(splitBtn); splitBtn.caption.SetAOC("Split"); splitBtn.alignment.Set(WMComponents.AlignLeft);
			splitBtn.onClick.Add(Split);
			topToolbar.AddContent(splitBtn);

			NEW(lbBtn); lbBtn.caption.SetAOC("Labels"); lbBtn.alignment.Set(WMComponents.AlignLeft);
			lbBtn.onClick.Add(lbShow);
			topToolbar.AddContent(lbBtn);			
			
			NEW(undo); 
			font := undo.GetFont();
			font.GetStringSize(" Undo (000) ", dx, dy);		
			undo.bounds.SetWidth(dx);	
			undo.caption.SetAOC("Undo"); undo.alignment.Set(WMComponents.AlignLeft);
			undo.onClick.Add(Undo);
			topToolbar.AddContent(undo);			
			
			NEW(redo); 
			font := redo.GetFont();
			font.GetStringSize(" Redo (000) ", dx, dy);		
			redo.bounds.SetWidth(dx);	
			redo.caption.SetAOC("Redo"); redo.alignment.Set(WMComponents.AlignLeft);
			redo.onClick.Add(Redo);
			topToolbar.AddContent(redo);			

			NEW(optionsEdit); optionsEdit.tv.showBorder.Set(TRUE); optionsEdit.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1));
			optionsEdit.alignment.Set(WMComponents.AlignClient); optionsEdit.multiLine.Set(FALSE);
			optionsEdit.bounds.SetWidth(80); optionsEdit.fillColor.Set(0FFFFFFFFH);
			topToolbar.AddContent(optionsEdit);
			optionsEdit.SetAsString(DefaultOptionsString);
			
			(* -- status Panel *)
			NEW(statusPanel); statusPanel.bounds.SetHeight(20); statusPanel.alignment.Set(WMComponents.AlignBottom); statusPanel.fillColor.Set(0CCCCCCFFH);
			panel.AddContent(statusPanel);
			
			NEW(posLabel); posLabel.caption.SetAOC(" Position: "); posLabel.bounds.SetWidth(60); posLabel.alignment.Set(WMComponents.AlignLeft);
			statusPanel.AddContent(posLabel); posLabel.textColor.Set(0000000FFH);
			
			NEW(positionEdit); positionEdit.tv.showBorder.Set(TRUE); positionEdit.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1));
			positionEdit.alignment.Set(WMComponents.AlignLeft); positionEdit.multiLine.Set(FALSE);
			positionEdit.bounds.SetWidth(80); positionEdit.fillColor.Set(0FFFFFFFFH); positionEdit.onEnter.Add(PositionHandler);
			statusPanel.AddContent(positionEdit);	

			(* -- Page holding the PETPanel *)
			NEW(page); page.fillColor.Set(0CCCCCCFFH); page.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(page);			
			
			RETURN panel;
		END CreateForm;
		
		PROCEDURE Undo(sender, data: ANY);
		BEGIN
			currentPage.editor.Undo
		END Undo;
		
		PROCEDURE Redo(sender, data: ANY);
		BEGIN
			currentPage.editor.Redo
		END Redo;
		
		PROCEDURE ResetUndo;
		BEGIN
			undo.caption.Reset();
			redo.caption.Reset();
			undo.clDefault.Reset();
			redo.clDefault.Reset();
		END ResetUndo;
		
		PROCEDURE UndoNrChanged(nrUndos: LONGINT);
		VAR lbl, str: ARRAY 32 OF CHAR;
		BEGIN
			IF nrUndos = 0 THEN 
				undo.enabled.Set(FALSE);
				undo.clDefault.Set(999999FFH);
			ELSE
				undo.enabled.Set(TRUE);
				undo.clDefault.Reset();
			END;
			lbl := "Undo (";
			Utilities.IntToStr(nrUndos, str);
			Utilities.Append(lbl, str);
			Utilities.Append(lbl, ")");
			undo.caption.SetAOC(lbl);
		END UndoNrChanged;
		
		PROCEDURE RedoNrChanged(nrRedos: LONGINT);
		VAR lbl, str: ARRAY 32 OF CHAR;
		BEGIN
			IF nrRedos = 0 THEN 
				redo.enabled.Set(FALSE);
				redo.clDefault.Set(999999FFH);
			ELSE
				redo.enabled.Set(TRUE);
				redo.clDefault.Reset();
			END;
			lbl := "Redo (";
			Utilities.IntToStr(nrRedos, str);
			Utilities.Append(lbl, str);
			Utilities.Append(lbl, ")");
			redo.caption.SetAOC(lbl);
		END RedoNrChanged;
		
		PROCEDURE CreateSidePanel(kind : LONGINT);
		BEGIN
			IF currentPage.moduleTree # NIL THEN currentPage.sidePanel.RemoveContent(currentPage.moduleTree); currentPage.moduleTree := NIL END;
			IF currentPage.xmlTree # NIL THEN 
				currentPage.xmlTree.refresh.onClick.Remove(HandleXmlRefresh);
				currentPage.sidePanel.RemoveContent(currentPage.xmlTree); currentPage.xmlTree := NIL 
			END;
			IF kind = 0 THEN
				currentPage.sidePanel.visible.Set(FALSE);
				currentPage.scratchPanel.alignment.Set(WMComponents.AlignClient);
				currentPage.scratchPanel.bounds.Set(currentPage.sidePanel.bounds.Get());
			ELSIF kind = 1 THEN
				(* Module Tree *)
				NEW(currentPage.moduleTree); currentPage.moduleTree.alignment.Set(WMComponents.AlignClient);
				currentPage.sidePanel.AddContent(currentPage.moduleTree);			
				currentPage.moduleTree.SetEditor(currentPage.editor);
				currentPage.sidePanel.visible.Set(TRUE);
				currentPage.moduleTree.RefreshHandler(SELF, NIL);
			ELSIF kind = 2 THEN
				(* XML Tree *)
				NEW(currentPage.xmlTree); currentPage.xmlTree.alignment.Set(WMComponents.AlignClient);
				currentPage.sidePanel.AddContent(currentPage.xmlTree);			
				currentPage.xmlTree.SetEditor(currentPage.editor);
				currentPage.sidePanel.visible.Set(TRUE);
				currentPage.xmlTree.Refresh(SELF, NIL);
				EvaluateXmlErrors(currentPage.editor); 
				currentPage.xmlTree.onRefresh.Add(HandleXmlRefresh);
			END;
		END CreateSidePanel;
		
		PROCEDURE &New(c : WMRestorable.Context);
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount;
			InitCodecs;
			vc := CreateForm();
			
			currentPageNr := -1;
			tabs.onSelectTab.Add(TabSelected);				

			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString(WindowTitle));
							
			IF c # NIL THEN (* restore the desktop *)
				WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame});
				IF c.appData # NIL THEN
					DisableUpdate;
					LoadPages(c.appData(XML.Element));
					Resized(GetWidth(), GetHeight());
					EnableUpdate;
				END;
			ELSE WMWindowManager.DefaultAddWindow(SELF);
				(* NewTab; *)
				codecFormat := "AUTO";
				autoCodecFormat := "BBT";
				SetFormatCaption("AUTO");				
			END;
		END New;
		
		PROCEDURE InitCodecs;
		VAR caption: CaptionObject;
			elem: XML.Element; enum: XMLObjects.Enumerator; ptr: ANY; str : Utilities.String;
		BEGIN
			NEW(popup);
			(* retrieve available Text-Codecs *)
			elem := AosConfig.config.GetRoot();
			IF elem # NIL THEN
				enum := elem.GetContents(); enum.Reset();
				WHILE enum.HasMoreElements() DO
					ptr := enum.GetNext();
					IF ptr IS XML.Element THEN
						str := ptr(XML.Element).GetAttributeValue("name");
						IF (str # NIL) & (str^ = "Codecs") THEN
							enum := ptr(XML.Element).GetContents(); enum.Reset();
							WHILE enum.HasMoreElements() DO
								ptr := enum.GetNext();
								IF ptr IS XML.Element THEN
									str := ptr(XML.Element).GetAttributeValue("name");
									IF (str # NIL) & (str^ = "Decoder") THEN
										enum := ptr(XML.Element).GetContents(); enum.Reset();
										WHILE enum.HasMoreElements() DO
											ptr := enum.GetNext();
											IF ptr IS XML.Element THEN
												str := ptr(XML.Element).GetAttributeValue("name");
												IF (str # NIL) & (str^ = "Text") THEN
													enum := ptr(XML.Element).GetContents(); enum.Reset();
													WHILE enum.HasMoreElements() DO
														ptr := enum.GetNext();
														IF ptr IS XML.Element THEN
															str := ptr(XML.Element).GetAttributeValue("name");
															NEW(caption, str^);
															popup.AddParButton(str^, FormatPopupHandler, caption);
														END;
													END;				
												END;				
											END;			
										END;		
									END;	
								END;
							END;
						END;
					END;
				END;
			END;
			NEW(caption, "AUTO");
			popup.AddParButton("AUTO", FormatPopupHandler, caption);
		END InitCodecs;	
		
		PROCEDURE SelectNextTab;
		VAR i : LONGINT;
		BEGIN	
			IF currentPageNr < 0 THEN RETURN; END;
			i := currentPageNr + 1;
			LOOP
				IF (i >= MaxNbrOfTabs) OR (pages[i] # NIL) THEN EXIT; END;
				INC(i);
			END;
			IF (i < MaxNbrOfTabs) THEN
				SelectTab(i);
			END;
		END SelectNextTab;
		
		PROCEDURE SelectPreviousTab;
		VAR i : LONGINT;
		BEGIN
			IF currentPageNr < 0 THEN RETURN; END;
			i := currentPageNr - 1;
			LOOP
				IF (i < 0) OR (pages[i] # NIL) THEN EXIT; END;
				DEC(i);
			END;
			IF (i >= 0) THEN
				SelectTab(i);
			END;
		END SelectPreviousTab;
		
		PROCEDURE SelectTab(tabNr : LONGINT);
		BEGIN
			IF (tabNr >= 0) & (tabNr < LEN(SELF.pages)) & (SELF.pages[tabNr] # NIL) THEN
				TabSelected(NIL, tabList[tabNr]);
				tabs.Select(tabList[tabNr]);
			END;
		END SelectTab;
		
		PROCEDURE GetNrFromPage(page : PETPanel): LONGINT;
		VAR i : LONGINT; found : BOOLEAN;
		BEGIN
			i := 0; found := FALSE;
			WHILE (~found & (i < MaxNbrOfTabs)) DO
				IF (page = pages[i]) THEN RETURN i END;
				INC(i)
			END;
			RETURN -1
		END GetNrFromPage;
		
		PROCEDURE TabSelected(sender, data : ANY);
		VAR tab : WMTabComponents.Tab;
		BEGIN
			IF (data # NIL) & (data IS WMTabComponents.Tab) THEN
				DisableUpdate;
				optionsEdit.GetAsString(currentPage.optionsString);
				page.RemoveContent(currentPage);
				tab := data(WMTabComponents.Tab);
				IF (tab.data # NIL) & (tab.data IS WMComponents.VisualComponent) THEN
					currentPage := tab.data(PETPanel);
					currentPageNr := GetNrFromPage(currentPage);	
					page.AddContent(currentPage);
					IF ~currentPage.initialized THEN currentPage.Initialize END;					
					currentPage.Reset(SELF, NIL);
					page.AlignSubComponents;
				END;
				EnableUpdate;
				UpdateState;
				page.Invalidate
			END	
		END TabSelected;
		
		PROCEDURE UpdatePages;
		VAR i : LONGINT;
			tab : WMTabComponents.Tab;
			s : Utilities.String;
		BEGIN
			tabs.RemoveAllTabs;
			IF currentPage # NIL THEN page.RemoveContent(currentPage);
				currentPage := NIL
			END;			
			IF currentPageNr >= 0 THEN currentPage := pages[currentPageNr] END;
			FOR i := 0 TO 99 DO
				tabList[i] := NIL;
				IF pages[i] # NIL THEN
					pages[i].alignment.Set(WMComponents.AlignClient);
					tab := tabs.NewTab();
					tabs.AddTab(tab);					
					tabList[i] := tab;
					s := Utilities.NewString(pages[i].filename);
					tabs.SetTabCaption(tab, s);
					tabs.SetTabData(tab, pages[i]);
				END
			END;
			IF currentPage = NIL THEN
				i := 0;
				WHILE (i < MaxNbrOfTabs) & (currentPage = NIL) DO
					IF pages[i] # NIL THEN currentPage := pages[i]; currentPageNr := i END;
					INC(i);
				END;
				IF currentPage = NIL THEN SetModified(FALSE) END;
			END;
			IF currentPage # NIL THEN
				IF ~currentPage.initialized THEN currentPage.Initialize END;
				page.AddContent(currentPage);
				currentPage.Reset(SELF, NIL);
				page.AlignSubComponents;
				page.Invalidate;
				IF tabList[currentPageNr] # NIL THEN tabs.Select(tabList[currentPageNr]) END
			END;
			UpdateState
		END UpdatePages;
		
		PROCEDURE UpdateState;
		VAR tInt : LONGINT;
			tStr : ARRAY 16 OF CHAR;
		BEGIN	
			(* set state of current page *)
			IF (currentPage # NIL) THEN
				SetModified(currentPage.modified);
				SetSplitted(currentPage.splitted);
				SetFormatCaption(currentPage.codecFormat);
				filenameEdit.SetAsString(currentPage.filename);
				optionsEdit.SetAsString(currentPage.optionsString);
				currentPage.editor.tv.cursor.SetVisible(TRUE);
				currentPage.editor.SetFocus();
				tInt := currentPage.editor.tv.cursor.GetPosition(); Utilities.IntToStr(tInt, tStr);
				positionEdit.SetAsString(tStr);
				IF currentPage.editor.undoMgr # NIL THEN
					UndoNrChanged(currentPage.editor.undoMgr.nrUndoUpdates);
					RedoNrChanged(currentPage.editor.undoMgr.nrRedoUpdates)
				END
			ELSE
				SetModified(FALSE);
				SetSplitted(FALSE);
				autoCodecFormat := "BBT";
				SetFormatCaption("AUTO");
				filenameEdit.SetAsString("");
				optionsEdit.SetAsString(DefaultOptionsString);
				positionEdit.SetAsString("-");
				ResetUndo();
			END;
			topToolbar.Invalidate;
		END UpdateState;
		
		PROCEDURE DragDroppedH(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo; VAR handled : BOOLEAN);
		VAR dropTarget : URLDropTarget;
		BEGIN
			NEW(dropTarget, SELF);
			dragInfo.data := dropTarget; 
			ConfirmDrag(TRUE, dragInfo)
		END DragDroppedH;		
		
		PROCEDURE PositionHandler(sender, data : ANY);
		VAR tempString : ARRAY 16 OF CHAR;
			tempInt : LONGINT;
		BEGIN
			IF (currentPage # NIL) THEN
				positionEdit.GetAsString(tempString);
				Utilities.StrToInt(tempString, tempInt);
				currentPage.editor.tv.cursor.SetPosition(tempInt);
				currentPage.editor.tv.cursor.SetVisible(TRUE);
				currentPage.editor.SetFocus()
			END
		END PositionHandler;	
			
		PROCEDURE FormatHandler(x, y: LONGINT; keys: SET; VAR handled: BOOLEAN);
		VAR rectangle: WMRectangles.Rectangle;
		BEGIN
			handled := TRUE;
			rectangle := formatBtn.bounds.Get();
			popup.Popup(bounds.l + rectangle.l, bounds.t + rectangle.b+ 20);
		END FormatHandler;		
		
		PROCEDURE SetFormatCaption(format: ARRAY OF CHAR);
		VAR caption : ARRAY 100 OF CHAR;
		BEGIN			
			caption := "Format : ";
			Utilities.Append(caption, format);
			IF (format = "AUTO") & (currentPage # NIL) THEN Utilities.Append(caption, " "); Utilities.Append(caption, currentPage.autoCodecFormat);
			ELSIF (format = "AUTO") THEN Utilities.Append(caption, " "); Utilities.Append(caption, autoCodecFormat); END;
			formatBtn.caption.SetAOC(caption);
		END SetFormatCaption;
		
		PROCEDURE SetModified(modified : BOOLEAN);
		BEGIN
			IF currentPage # NIL THEN
				tabList[currentPageNr].attention := modified;
				IF modified THEN store.caption.SetAOC("Store !")
				ELSE store.caption.SetAOC("Store") END
			END
		END SetModified;
		
		PROCEDURE SetSplitted(splitted : BOOLEAN);
		BEGIN
			IF splitted THEN splitBtn.caption.Set(Utilities.NewString("Unsplit"))
			ELSE splitBtn.caption.Set(Utilities.NewString("Split")) END;
		END SetSplitted;	
				
		PROCEDURE FormatPopupHandler(sender, data: ANY);
		BEGIN
			IF (data # NIL) & (data IS CaptionObject) THEN
				popup.Close;
				IF (currentPage # NIL) THEN
					COPY(data(CaptionObject).caption, currentPage.codecFormat);
					COPY(currentPage.codecFormat, codecFormat);
					COPY(currentPage.autoCodecFormat, autoCodecFormat);
				ELSE
					COPY(data(CaptionObject).caption, codecFormat);
					COPY("BBT", autoCodecFormat);						
				END;
				SetFormatCaption(codecFormat);
			END
		END FormatPopupHandler;		
		
		PROCEDURE LoadHandler(sender, data : ANY);
		VAR filename : ARRAY 256 OF CHAR;
		BEGIN
			IF currentPage # NIL THEN
				optionsEdit.GetAsString(currentPage.optionsString);
			END;
			filenameEdit.GetAsString(filename);
			Load(filename, codecFormat)
		END LoadHandler;
		
		PROCEDURE Load*(filename,  format : ARRAY OF CHAR);
		VAR text : AosTexts.Text; res : LONGINT;
			decoder : AosCodecs.TextDecoder;
			in: AosIO.Reader;
		BEGIN
			res := -1;
			
			NewTab;	(* create a new Tab with an empty PETPanel to Load into *)		
			filenameEdit.SetAsString(filename);
			COPY(filename, currentPage.filename);
			
			text := currentPage.editor.text;
			text.AcquireWrite;
			currentPage.modified := TRUE; (* avoid the ! on the store button while loading *)			
			text.Delete(0, text.GetLength());
			currentPage.editor.tv.firstLine.Set(0);
			currentPage.editor.tv.onLinkClicked.Add(LinkClickedHandler);
			text.ReleaseWrite;				
			
			IF (format = "AUTO") THEN
				decoder := AosTextUtilities.DecodeAuto(filename, autoCodecFormat);
				COPY(autoCodecFormat, currentPage.autoCodecFormat);
			ELSE decoder := AosCodecs.GetTextDecoder(format);
			END;			
			IF decoder # NIL THEN
				COPY(format, currentPage.codecFormat);
				in := AosCodecs.OpenInputStream(filename);
				IF in # NIL THEN
					decoder.Open(in, res);
					IF res = 0 THEN
						currentPage.editor.text.onTextChanged.Remove(currentPage.TextChanged);
						currentPage.editor.SetText(decoder.GetText());						
						currentPage.searchPanel.SetText(decoder.GetText());
						currentPage.splitEditor.SetText(currentPage.editor.text);
						currentPage.editor.text.onTextChanged.Add(currentPage.TextChanged);
						currentPage.editor.text.SetUndoManager(currentPage.editor.undoMgr)
					END;				
				ELSE
					AosOut.String("Can't open Stream: "); AosOut.String(filename); AosOut.Ln;
				END;
			ELSE
				AosOut.String("No decoder/file: "); AosOut.String(format); AosOut.String(" : "); AosOut.String(filename); AosOut.Ln;	
			END;

			SetFormatCaption(format);
			
			currentPage.editor.tv.firstLine.Set(0);
			currentPage.editor.tv.cursor.SetPosition(0);
			currentPage.editor.tv.SetFocus;

			IF (Utilities.Pos('.Mod', filename) > 0) OR (Utilities.Pos('.mod', filename) > 0) THEN
				CreateSidePanel(1)
			ELSIF (Utilities.Pos('.XML', filename) > 0) OR (Utilities.Pos('.xml', filename) > 0) THEN
				CreateSidePanel(2)
			ELSE
				CreateSidePanel(0)
			END;
			
			COPY(filename, tabList[currentPageNr].caption^); tabs.Invalidate;
			currentPage.modified := FALSE;
			SetModified(FALSE);
			UpdatePages
		END Load;

		PROCEDURE StoreHandler(sender, data : ANY);
		VAR filename : ARRAY 256 OF CHAR;
		BEGIN
			IF (currentPage # NIL) THEN
				filenameEdit.GetAsString(filename);
				Store(filename, currentPage.codecFormat)
			END
		END StoreHandler;
				
		PROCEDURE Store(filename,format  : ARRAY OF CHAR);
		VAR text : AosTexts.Text; res : LONGINT;
			backName: ARRAY 128 OF CHAR;
			backExt, t : ARRAY 12 OF CHAR;
			optionsString : ARRAY OptionsStringLength OF CHAR;
			encoder : AosCodecs.TextEncoder;
			w : AosFS.Writer; i : LONGINT;
			f : AosFS.File;

			PROCEDURE FileExists(fileName : ARRAY OF CHAR) : BOOLEAN;
			BEGIN
				RETURN AosFS.Old(fileName) # NIL
			END FileExists;			
			
		BEGIN
			IF currentPage # NIL THEN
				filenameEdit.SetAsString(filename);
				(* create backup *)
				IF BackupParanoid THEN
					Utilities.Concat(filename, ".Bak", backName);
					IF FileExists(backName) THEN
						i := 0;
						REPEAT
							backExt := "."; Utilities.IntToStr(i, t);
							Utilities.Append(backExt, t); Utilities.Append(backExt, ".Bak");
							Utilities.Concat(filename, backExt, backName);
							INC(i);
						UNTIL ~FileExists(backName)	
					END;	
				ELSE 
					Utilities.Concat(filename, ".Bak", backName) 
				END;
				
				AosFS.Rename(filename, backName, res);
				IF res = AosFS.Ok THEN AosOut.String("Backup created  in "); AosOut.String(backName); AosOut.Ln END;
				
				text := currentPage.editor.text;
				text.AcquireWrite;
				
				IF (format = "AUTO") THEN
					IF (currentPage.autoCodecFormat = "") THEN	encoder := AosCodecs.GetTextEncoder("BBT");
					ELSE encoder := AosCodecs.GetTextEncoder(currentPage.autoCodecFormat); 
						IF encoder = NIL THEN encoder := AosCodecs.GetTextEncoder("BBT"); END;
					END;
				ELSE encoder := AosCodecs.GetTextEncoder(format);
				END;
	
				IF (encoder # NIL) THEN
					f := AosFS.New(filename);
					IF f = NIL THEN RETURN END;
					AosFS.OpenWriter(w, f, 0);			
					
					encoder.Open(w);
					encoder.WriteText(text, res);
					IF res = 0 THEN AosFS.Register(f); f.Update; END;
				ELSE
					AosOut.String("No encoder found"); AosOut.Ln;
				END;
				text.ReleaseWrite;
				
				tabs.SetTabCaption(tabList[currentPageNr], Utilities.NewString(filename)); tabs.Invalidate;
				COPY(filename, pages[currentPageNr].filename);
 				optionsEdit.GetAsString(optionsString); COPY(optionsString, currentPage.optionsString);
				currentPage.modified := FALSE;
				SetModified(FALSE)
			END
		END Store;	

		PROCEDURE NewTab;
		VAR pet : PETPanel;
			i : LONGINT;
			found : BOOLEAN;
		BEGIN
			found := FALSE;
			NEW(pet); pet.alignment.Set(WMComponents.AlignClient); pet.fillColor.Set(0FFFFFFFFH); pet.takesFocus.Set(TRUE); 
			pet.owner := SELF; 
			IF pet.editor.undoMgr # NIL THEN 
				pet.editor.undoMgr.nrUndoListener := UndoNrChanged;
				pet.editor.undoMgr.nrRedoListener := RedoNrChanged;
				UndoNrChanged(0);RedoNrChanged(0)
			END;
			(* find a free place *)
			i := 0;
			WHILE (i < MaxNbrOfTabs) & (~found) DO
				IF pages[i] = NIL THEN pages[i] := pet; currentPageNr := i; found := TRUE; END;
				INC(i)
			END;			
			UpdatePages;				
		END NewTab;
		
		(* Returns FALSE if the user declines to close all tabs *)
		PROCEDURE CloseAllTabs() : BOOLEAN;
		VAR res, i : LONGINT;
		BEGIN
			(* First check whether all pages are saved to disk *)
			i := 0; 
			LOOP
				IF i >= MaxNbrOfTabs THEN EXIT; END;
				IF (pages[i] # NIL) & (pages[i].modified) THEN
					res := WMDialogs.Message("Warning", "At least on page has not been stored. Continue?", {WMDialogs.ResYes, WMDialogs.ResNo});
					IF res = WMDialogs.ResNo THEN
						RETURN FALSE; 
					ELSIF res = WMDialogs.ResYes THEN
						EXIT;
					END;
				END;
				INC(i);
			END;
		
			i := 0;
			WHILE (i < MaxNbrOfTabs) DO
				IF (pages[i] # NIL) THEN 	pages[i].Finalize; pages[i] := NIL; END;
				INC(i);
			END;
			UpdatePages;
			RETURN TRUE;
		END CloseAllTabs;

		PROCEDURE CloseHandler(sender, data: ANY);
		VAR found : BOOLEAN; i : LONGINT;
		BEGIN
			(* close current tab, warn user if not saved *)
			IF (currentPage = NIL) OR (currentPage.modified) & (
				WMDialogs.Message("Warning", "The current text was not stored. Continue ?", {WMDialogs.ResYes, WMDialogs.ResNo}) = WMDialogs.ResNo)
			THEN RETURN END;
			(* remove current page *)
			found := FALSE; i := 0;
			WHILE (~found & (i < MaxNbrOfTabs)) DO
				IF (currentPage = pages[i]) THEN pages[i].Finalize; pages[i] := NIL; found := TRUE END;
				INC(i);
			END;
			UpdatePages;
			page.Invalidate;
		END CloseHandler;

		PROCEDURE SearchHandler(sender, data: ANY);
		BEGIN
			IF (currentPage # NIL) THEN
				currentPage.searchPanel.visible.Set(TRUE)
			END
		END SearchHandler;
				
		PROCEDURE Split(sender, data: ANY);
		BEGIN
			IF (currentPage # NIL) THEN
				IF currentPage.splitted THEN
					splitBtn.caption.Set(Utilities.NewString("Split"));
					currentPage.splitPanel.visible.Set(FALSE);
				ELSE
					splitBtn.caption.Set(Utilities.NewString("Unsplit"));
					currentPage.splitPanel.visible.Set(TRUE);
				END;
				currentPage.splitted := ~currentPage.splitted
			END
		END Split;
		
		PROCEDURE LinkClickedHandler(sender, data : ANY);
		BEGIN
			IF data IS WMTextView.LinkWrapper THEN
				AosOut.String("Link: "); AosOut.String(data(WMTextView.LinkWrapper).link^); AosOut.Ln
			END;
		END LinkClickedHandler;	
		
		PROCEDURE lbShow(sender, data : ANY);
		BEGIN
			IF (currentPage # NIL) THEN
				IF currentPage.editor.tv.showLabels.Get() THEN
					currentPage.editor.tv.showLabels.Set(FALSE);
					currentPage.splitEditor.tv.showLabels.Set(FALSE);
				ELSE
					currentPage.editor.tv.showLabels.Set(TRUE);
					currentPage.splitEditor.tv.showLabels.Set(TRUE);
				END;
				currentPage.Invalidate;
			END;
		END lbShow;			
						
		PROCEDURE FindPC(sender, data : ANY);
		VAR pc, a, b : LONGINT;
			pcStr : ARRAY 64 OF CHAR;
			selectionText: AosTexts.Text;
			from, to: AosTexts.TextPosition;
		BEGIN
			IF currentPage = NIL THEN RETURN; END;
			IF AosTexts.GetLastSelection(selectionText, from, to) THEN
				selectionText.AcquireRead;
				a := Utilities.Min(from.GetPosition(), to.GetPosition());
				b := Utilities.Max(from.GetPosition(), to.GetPosition());
				AosTextUtilities.SubTextToStr(selectionText, a, b - a, pcStr);
				selectionText.ReleaseRead;
				Utilities.Trim(pcStr, " ");
				Utilities.StrToInt(pcStr, pc);
			END;
			IF pc <= 0 THEN
				IF WMDialogs.QueryString("Enter PC to locate", pcStr) = WMDialogs.ResOk THEN 
					Utilities.StrToInt(pcStr, pc);
					DoCompile(TRUE, pc)
				END
			ELSE
				DoCompile(TRUE, pc)
			END
		END FindPC;
						
		PROCEDURE Compile(sender, data : ANY);
		BEGIN
			DoCompile(FALSE, 0) 
		END Compile;
		
		PROCEDURE RemoveErrorMarkers;
		VAR i : LONGINT;
		BEGIN
			ASSERT(currentPage # NIL);
			FOR i := 0 TO LEN(currentPage.errorList) - 1 DO 
				IF currentPage.errorList[i].pos[0] # NIL THEN 
					currentPage.editor.tv.RemovePositionMarker(currentPage.errorList[i].pos[0]);
					currentPage.errorList[i].pos[0] := NIL;
				END;
				IF currentPage.errorList[i].pos[1] # NIL THEN
					currentPage.splitEditor.tv.RemovePositionMarker(currentPage.errorList[i].pos[1]);
					currentPage.errorList[i].pos[1] := NIL
				END
			END; 			
		END RemoveErrorMarkers;
		
		PROCEDURE ShowErrorMarkes(show : BOOLEAN);
		VAR i : LONGINT;
		BEGIN
			ASSERT(currentPage # NIL);
			currentPage.editor.text.AcquireRead;
			FOR i := 0 TO LEN(currentPage.errorList) - 1 DO 
				IF currentPage.errorList[i].pos[0] # NIL THEN 
					currentPage.errorList[i].pos[0].SetVisible(show);
				END;
				IF currentPage.errorList[i].pos[1] # NIL THEN
					currentPage.errorList[i].pos[1].SetVisible(show);
				END
			END; 		
			currentPage.editor.text.ReleaseRead;	
		END ShowErrorMarkes;
				
		PROCEDURE ClearLog;
		BEGIN
			ASSERT(currentPage # NIL);
			currentPage.logEdit.text.AcquireWrite;
			currentPage.logEdit.text.Delete(0, currentPage.logEdit.text.GetLength());
			currentPage.logEdit.tv.firstLine.Set(0); currentPage.logEdit.tv.cursor.SetPosition(0);
			currentPage.logEdit.text.ReleaseWrite;
		END ClearLog;
		
		PROCEDURE EvaluateXmlErrors(data : PTR);
		VAR xmlErrorList : WMXMLTree.ErrorList; i : LONGINT;
		BEGIN
			ASSERT(currentPage # NIL);
			(* Since messages are handled asynchronously, it is possible that the currentPage may have changed *)
			IF (currentPage.xmlTree = NIL) OR (currentPage.xmlTree # data) THEN RETURN; END;
			RemoveErrorMarkers;
			ClearLog;
		 	currentPage.editor.text.AcquireRead;
		 	currentPage.nbrOfErrors := 0; currentPage.nbrOfWarnings := 0;
			xmlErrorList := currentPage.xmlTree.GetErrorList();
			IF xmlErrorList # NIL THEN
				i := 0;
				WHILE (i < LEN(xmlErrorList)) & (i < LEN(currentPage.errorList)) DO
					COPY(xmlErrorList[i].msg, currentPage.errorList[i].msg);
					currentPage.errorList[i].type := TypeError;
					(* main editor *)
					currentPage.errorList[i].pos[0] := currentPage.editor.tv.CreatePositionMarker();
					currentPage.errorList[i].pos[0].Load(PictureError);
					currentPage.errorList[i].pos[0].SetPosition(xmlErrorList[i].pos);
					(* split editor *)
					currentPage.errorList[i].pos[1] := currentPage.splitEditor.tv.CreatePositionMarker();
					currentPage.errorList[i].pos[1].Load(PictureError);
					currentPage.errorList[i].pos[1].SetPosition(xmlErrorList[i].pos);
					INC(i);
					INC(currentPage.nbrOfErrors);
				END;

				WriteErrorSummary(currentPage.errorSummaryStr, currentPage.nbrOfErrors, currentPage.nbrOfWarnings, FALSE);

				IF (currentPage.errorList[0].pos # NIL) THEN
					IF currentPage.focus = EditorFocus THEN 
						currentPage.editor.tv.cursor.SetPosition(currentPage.errorList[0].pos[0].GetPosition());
						currentPage.editor.SetFocus;
					ELSE
						currentPage.splitEditor.tv.cursor.SetPosition(currentPage.errorList[0].pos[1].GetPosition());
						currentPage.splitEditor.SetFocus;
					END;
				END;
				
				currentPage.logPanel.visible.Set(TRUE); currentPage.logEdit.visible.Set(FALSE);
				currentPage.logPanel.Invalidate;
				currentPage.errorLog.nofRows.Set(i + 1); 
				currentPage.errorLog.SetTopPosition(0, 0, TRUE);
			ELSE
				currentPage.logPanel.visible.Set(FALSE); currentPage.logEdit.visible.Set(FALSE);
			END;
			currentPage.editor.text.ReleaseRead;
		END EvaluateXmlErrors;
		
		PROCEDURE HandleXmlRefresh(sender, data : ANY);
		BEGIN
			(* The XML tree sends a reference to the editor that's assigned to it so we can identify the page it's belonging to *)
			EvaluateXmlErrors(data);
		END HandleXmlRefresh;
		
		PROCEDURE WriteErrorSummary(VAR summary : ARRAY OF CHAR; nbrOfErrors, nbrOfWarnings : LONGINT; warningsEnabled : BOOLEAN);
		VAR nbr : ARRAY 8 OF CHAR;
		BEGIN
			summary := "";
			IF nbrOfErrors > 0 THEN
				Utilities.IntToStr(nbrOfErrors, nbr);
				Utilities.Append(summary, nbr);
				IF nbrOfErrors > 1 THEN
					Utilities.Append(summary, " errors");
				ELSE
					Utilities.Append(summary, "error");
				END;				
			ELSE
				summary := "no";
				Utilities.Append(summary, " errors");
			END;
			
			IF warningsEnabled THEN
				Utilities.Append(summary, ", ");
				IF nbrOfWarnings > 0 THEN
					Utilities.IntToStr(nbrOfWarnings, nbr);
					Utilities.Append(summary, nbr);
					IF nbrOfWarnings > 1 THEN
						Utilities.Append(summary, " warnings");
					ELSE
						Utilities.Append(summary, " warning");
					END;
				ELSE
					Utilities.Append(summary, "no");
					Utilities.Append(summary, " warnings");
				END;
			END;
		END WriteErrorSummary;
		
		PROCEDURE EvaluateCompileErrors(hasErrors : BOOLEAN);
		VAR
			pictureName : ARRAY 64 OF CHAR;
			options : ARRAY OptionsStringLength OF CHAR;
			entry : PCM.ErrorEntry;
			j : LONGINT;
		BEGIN
			ASSERT(currentPage # NIL);
			currentPage.editor.text.AcquireRead;
			IF (currentPage.errlist # NIL) & (currentPage.errlist.HasMoreErrors()) THEN
				j := 0;
				WHILE (currentPage.errlist.HasMoreErrors()) DO
					entry := currentPage.errlist.GetNext();
					IF (entry # NIL) THEN
						IF entry.err >= 300 THEN 
							currentPage.errorList[j].type := TypeWarning;
							pictureName := PictureWarning;
							INC(currentPage.nbrOfWarnings);
						ELSE 
							currentPage.errorList[j].type := TypeError;
							pictureName := PictureError; 
							INC(currentPage.nbrOfErrors);
						END;
					
						(* main editor *)
						currentPage.errorList[j].pos[0] := currentPage.editor.tv.CreatePositionMarker();
						currentPage.errorList[j].pos[0].Load(pictureName);
						currentPage.errorList[j].pos[0].SetPosition(entry.pos);
						(* split editor *)
						currentPage.errorList[j].pos[1] := currentPage.splitEditor.tv.CreatePositionMarker();
						currentPage.errorList[j].pos[1].Load(pictureName);	
						currentPage.errorList[j].pos[1].SetPosition(entry.pos);
						
						currentPage.errorList[j].err := entry.err;
						COPY(entry.msg, currentPage.errorList[j].msg);
						INC(j);
					END;
				END;

				optionsEdit.GetAsString(options);
				WriteErrorSummary(currentPage.errorSummaryStr, currentPage.nbrOfErrors, currentPage.nbrOfWarnings, Utilities.ContainsChar(options, "W", TRUE));

				IF (currentPage.errorList[0].pos # NIL) & hasErrors THEN
					IF currentPage.focus = EditorFocus THEN 
						currentPage.editor.tv.cursor.SetPosition(currentPage.errorList[0].pos[0].GetPosition());
						currentPage.editor.SetFocus
					ELSE
						currentPage.splitEditor.tv.cursor.SetPosition(currentPage.errorList[0].pos[1].GetPosition());
						currentPage.splitEditor.SetFocus
					END
				END;
				currentPage.logPanel.visible.Set(TRUE); currentPage.logEdit.visible.Set(TRUE);
				currentPage.logPanel.Invalidate;
				currentPage.errorLog.nofRows.Set(j + 1); 
				currentPage.errorLog.SetTopPosition(0, 0, TRUE);
			ELSE 
				currentPage.logPanel.visible.Set(FALSE); currentPage.logEdit.visible.Set(TRUE)
			END; 
			currentPage.editor.text.ReleaseRead;
		END EvaluateCompileErrors;
		
		PROCEDURE DoCompile(findPC : BOOLEAN; pc : LONGINT);
		VAR 
			tw : AosTextUtilities.TextWriter; 
			arg : ARRAY OptionsStringLength OF CHAR;
			errors : BOOLEAN;
		BEGIN
			IF (currentPage # NIL) THEN
				RemoveErrorMarkers;
				ClearLog;

				NEW(tw, currentPage.logEdit.text);
				
				optionsEdit.GetAsString(arg);
				IF findPC THEN Utilities.Append(arg, " /f") END; 

				currentPage.nbrOfErrors := 0; currentPage.nbrOfWarnings := 0;
				PC0.CompileText(currentPage.editor.text, 0, pc, arg, tw.GetWriter(), currentPage.errlist, errors);
				
				EvaluateCompileErrors(errors);				
			END;
		END DoCompile;
		
		PROCEDURE UnloadModule;
		VAR 
			name, extension, msg : ARRAY 128 OF CHAR; 
			tw : AosTextUtilities.TextWriter;
			res : LONGINT;
		BEGIN
			ASSERT(currentPage # NIL);
			Utilities.GetExtension(currentPage.filename, name, extension);
			IF (name # "PET") THEN
				AosModules.FreeModule(name, res, msg);
			ELSE
				res := -1; msg := "Unloading module PET not allowed! PET is running.";
			END;
			IF res = 0 THEN
				msg := "Module "; Utilities.Append(msg, name); Utilities.Append(msg, " unloaded.");
			END;
			ClearLog;
			NEW(tw, currentPage.logEdit.text);
			tw.Add(msg, 0, Utilities.Length(msg), TRUE, res);
			IF currentPage.logEdit.visible.Get() = FALSE THEN currentPage.logEdit.visible.Set(TRUE); END;
		END UnloadModule;
		
		PROCEDURE Close;
		VAR page : LONGINT;
		BEGIN
			Close^;
			FOR page := 0 TO LEN(pages)-1 DO
				IF pages[page] # NIL THEN pages[page].Finalize; END;
			END;
			DecCount;
		END Close;
		
		(* XML scanner/parser error handler *)
		PROCEDURE Error(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
		BEGIN			
			xmlHasErrors := TRUE;
		END Error;
		
		PROCEDURE LoadState*(filename : ARRAY OF CHAR) : BOOLEAN;
		VAR 
			file : AosFS.File;
			scanner : XMLScanner.Scanner;
			parser : XMLParser.Parser;
			reader : AosFS.Reader;
			doc : XML.Document;
			elem : XML.Element;
			string : XML.String;
			ignore : LONGINT;
			msg : ARRAY 128 OF CHAR;
		BEGIN
			xmlHasErrors := FALSE;
			file := AosFS.Old(filename);
			IF file # NIL THEN
				NEW(reader, file, 0);
				NEW(scanner, reader); scanner.reportError := Error;
				NEW(parser, scanner); parser.reportError := Error;
				doc := parser.Parse();
				IF xmlHasErrors THEN
					msg := "Could not load state: "; Utilities.Append(msg, filename); Utilities.Append(msg, " could not be parsed"); 
					ignore := WMDialogs.Message("Error", msg, {WMDialogs.ResOk});
					RETURN FALSE;
				END;
				elem := doc.GetRoot();
				IF elem # NIL THEN string := elem.GetName(); END;
				IF (string # NIL) & (string^ = "PETData") THEN
					DisableUpdate;
					LoadPages(doc.GetRoot());
					EnableUpdate;
				ELSE
					msg := "Could not load state: "; Utilities.Append(msg, filename); Utilities.Append(msg, " not valid");
					ignore := WMDialogs.Message("Error", msg, {WMDialogs.ResOk});
					RETURN FALSE;
				END;
			ELSE
				msg := "Could not load state: XML file "; Utilities.Append(msg, filename); Utilities.Append(msg, " not found"); 
				ignore := WMDialogs.Message("Error", msg, {WMDialogs.ResOk});
				RETURN FALSE;
			END;
			RETURN TRUE;
		END LoadState;
		
		(* Store the current editor settings into a file *)
		PROCEDURE StoreState(filename : ARRAY OF CHAR);
		VAR state : XML.Element; file : AosFS.File; w : AosFS.Writer; ignore : LONGINT;
		BEGIN					
			file := AosFS.New(filename);
			IF file # NIL THEN
				AosFS.OpenWriter(w, file, 0);
				state := StorePages();
				state.Write(w, 0);
				w.Update;
				AosFS.Register(file);
				AosOut.String("PET state saved into "); AosOut.String(filename); AosOut.Ln;
			ELSE
				ignore := WMDialogs.Message("Error", "Could not create file", {WMDialogs.ResOk});
			END;
		END StoreState;
		
		PROCEDURE LoadPages(pages : XML.Element);
		VAR 
			elem : XML.Element; enum : XMLObjects.Enumerator; ptr : PTR; s : XML.String;
			selectedPageNr : LONGINT;
		BEGIN 
			selectedPageNr := -1;
			enum := pages.GetContents(); enum.Reset();
			WHILE (enum.HasMoreElements()) DO
				ptr := enum.GetNext();
				IF ptr IS XML.Element THEN
					elem := ptr(XML.Element);
					s := elem.GetName();
					IF (s # NIL) & (s^ = "Tab") THEN		
						LoadPage(elem);
					ELSIF (s # NIL) & (s^ = "General") THEN
						WMRestorable.LoadLongint(elem, "SelectedPageNr", selectedPageNr);
					END;
				END;						
			END;
			IF (selectedPageNr >= 0) & (selectedPageNr < LEN(SELF.pages)) & (SELF.pages[selectedPageNr] # NIL) THEN
				TabSelected(NIL, tabList[selectedPageNr]);
				tabs.Select(tabList[selectedPageNr]);
			END;
		END LoadPages;
		
		PROCEDURE StorePages() : XML.Element;
		VAR data, elem : WMRestorable.XmlElement; i : LONGINT;
		BEGIN
			NEW(data); data.SetName("PETData");
			NEW(elem); elem.SetName("General");
			WMRestorable.StoreLongint(elem, "SelectedPageNr", currentPageNr);
			data.AddContent(elem);
			WHILE (i < MaxNbrOfTabs) DO
				IF (pages[i] # NIL) THEN
					elem := StorePage(pages[i]);
					data.AddContent(elem);
				END;
				INC(i)
			END;
			RETURN data;
		END StorePages;
		
		PROCEDURE LoadPage(page : WMRestorable.XmlElement);
		VAR
			entries: XMLObjects.Enumerator;
			entry : XML.Element;
			s : Utilities.String;
			firstLine, cursorPos, width, height : LONGINT;
			optionsString : ARRAY OptionsStringLength OF CHAR;
			searchString, replaceString : ARRAY 256 OF CHAR;
			visible, wrap, casesensitive, backwards : BOOLEAN;
			ptr : ANY;
		BEGIN
			WMRestorable.LoadString(page, "codecFormat", codecFormat);
			WMRestorable.LoadString(page, "optionsString", optionsString);
			WMRestorable.LoadStringPtr(page, "file", s);
			IF s # NIL THEN 
				Load(s^, codecFormat);
				COPY(optionsString, currentPage.optionsString);
				optionsEdit.SetAsString(optionsString);
				
				entries := page.GetContents(); entries.Reset();
				WHILE(entries.HasMoreElements()) DO
					ptr := entries.GetNext();
					IF ptr IS XML.Element THEN
						entry := ptr (XML.Element);
						s := entry.GetName();
						IF (s # NIL) THEN
							IF (s^ = "Editor") THEN
								WMRestorable.LoadLongint(entry, "firstLine", firstLine);
								WMRestorable.LoadLongint(entry, "cursorPos", cursorPos);
								currentPage.editor.tv.firstLine.Set(firstLine);
								currentPage.editor.tv.cursor.SetPosition(cursorPos);
							ELSIF (s^ = "SplitEditor") THEN
								WMRestorable.LoadLongint(entry, "firstLine", firstLine);
								WMRestorable.LoadLongint(entry, "cursorPos", cursorPos);
								WMRestorable.LoadBoolean(entry, "visible", visible);
								WMRestorable.LoadLongint(entry, "height", height);
								currentPage.splitEditor.tv.firstLine.Set(firstLine);
								currentPage.splitEditor.tv.cursor.SetPosition(cursorPos);
								currentPage.splitPanel.visible.Set(visible);
								currentPage.splitted := visible;
								currentPage.splitPanel.bounds.SetHeight(height);
							ELSIF (s^ = "SidePanel") THEN
								WMRestorable.LoadBoolean(entry, "visible", visible);
								WMRestorable.LoadLongint(entry, "width", width);
								WMRestorable.LoadLongint(entry, "scratchHeight", height);												
								currentPage.sidePanel.visible.Set(visible);
								currentPage.sidePanel.bounds.SetWidth(width);
								currentPage.scratchPanel.bounds.SetHeight(height);
							ELSIF (s^ = "SearchPanel") THEN												
								WMRestorable.LoadBoolean(entry, "visible", visible);
								WMRestorable.LoadBoolean(entry, "wrap", wrap);
								WMRestorable.LoadBoolean(entry, "casesensitive", casesensitive);
								WMRestorable.LoadBoolean(entry, "backwards", backwards);
								WMRestorable.LoadString(entry, "searchString", searchString);
								WMRestorable.LoadString(entry, "replaceString", replaceString);
								currentPage.searchPanel.visible.Set(visible);
								currentPage.searchPanel.wrap := wrap;
								IF wrap THEN currentPage.searchPanel.wrapBtn.caption.Set(currentPage.searchPanel.wrapOn);
								ELSE currentPage.searchPanel.wrapBtn.caption.Set(currentPage.searchPanel.wrapOff);
								END;
								currentPage.searchPanel.caseSensitive := casesensitive;
								IF casesensitive THEN currentPage.searchPanel.caseSensitiveBtn.caption.Set(currentPage.searchPanel.caseSensitiveOn);
								ELSE currentPage.searchPanel.caseSensitiveBtn.caption.Set(currentPage.searchPanel.caseSensitiveOff);
								END;
								currentPage.searchPanel.backwards := backwards;
								IF backwards THEN currentPage.searchPanel.directionBtn.caption.Set(currentPage.searchPanel.directionUp);
								ELSE currentPage.searchPanel.directionBtn.caption.Set(currentPage.searchPanel.directionDown);
								END;
								currentPage.searchPanel.searchEdit.SetAsString(searchString);
								currentPage.searchPanel.replEdit.SetAsString(replaceString);
							ELSIF (s^ = "LogPanel") THEN
								WMRestorable.LoadLongint(entry, "height", height);
								currentPage.logPanel.bounds.SetHeight(height);
							END;
						END;
					END;
				END; (* WHILE (entries.HasMoreElements() *)
			END;
		END LoadPage;

		PROCEDURE StorePage(page : PETPanel) : WMRestorable.XmlElement;
		VAR 
			elem, entry : WMRestorable.XmlElement;
			string : ARRAY 256 OF CHAR;
		BEGIN
			ASSERT(page # NIL);
			NEW(elem); elem.SetName("Tab");
			WMRestorable.StoreString(elem, "file", page.filename);
			WMRestorable.StoreString(elem, "codecFormat", page.codecFormat);
			WMRestorable.StoreString(elem, "optionsString", page.optionsString);		
			
			NEW(entry); entry.SetName("Editor");
				WMRestorable.StoreLongint(entry, "firstLine", page.editor.tv.firstLine.Get());
				WMRestorable.StoreLongint(entry, "cursorPos", page.editor.tv.cursor.GetPosition());					
			elem.AddContent(entry);
			
			NEW(entry); entry.SetName("SplitEditor");
				WMRestorable.StoreBoolean(entry, "visible", page.splitPanel.visible.Get());
				WMRestorable.StoreLongint(entry, "firstLine", page.splitEditor.tv.firstLine.Get());
				WMRestorable.StoreLongint(entry, "cursorPos", page.splitEditor.tv.cursor.GetPosition());
				WMRestorable.StoreLongint(entry, "height", page.splitPanel.bounds.GetHeight());
			elem.AddContent(entry);
			
			NEW(entry); entry.SetName("SearchPanel");							
				WMRestorable.StoreBoolean(entry, "visible", page.searchPanel.visible.Get());
				WMRestorable.StoreBoolean(entry, "wrap", page.searchPanel.wrap);
				WMRestorable.StoreBoolean(entry, "casesensitive", page.searchPanel.caseSensitive);
				WMRestorable.StoreBoolean(entry, "backwards", page.searchPanel.backwards);
				page.searchPanel.searchEdit.GetAsString(string);
				WMRestorable.StoreString(entry, "searchString", string);
				page.searchPanel.replEdit.GetAsString(string);
				WMRestorable.StoreString(entry, "replaceString", string);
			elem.AddContent(entry);
			
			NEW(entry); entry.SetName("LogPanel");
				WMRestorable.StoreLongint(entry, "height", page.logPanel.bounds.GetHeight());
			elem.AddContent(entry);
			
			NEW(entry); entry.SetName("SidePanel");
				WMRestorable.StoreBoolean(entry, "visible", page.sidePanel.visible.Get());	
				WMRestorable.StoreLongint(entry, "width", page.sidePanel.bounds.GetWidth());
				WMRestorable.StoreLongint(entry, "scratchHeight", page.scratchPanel.bounds.GetHeight());	
			elem.AddContent(entry);

			RETURN elem;
		END StorePage;
					
		PROCEDURE HandleShortcut(ucs : LONGINT; flags : SET; keysym : LONGINT) : BOOLEAN;
		VAR 
			filename, string : ARRAY 256 OF CHAR;
			backwards : BOOLEAN;
			par : AosCommands.Parameters;
		BEGIN
			IF DisableShortcuts THEN RETURN FALSE; END;
			IF (ucs = 06H) & (flags * AosInputs.Ctrl # {}) THEN (* CTRL-F *)
				IF (currentPage # NIL) & (flags * {AosInputs.Release} = {}) THEN
					IF ~currentPage.searchPanel.visible.Get() THEN
						currentPage.searchPanel.visible.Set(TRUE);
						currentPage.searchPanel.searchEdit.SetAsString("");
						currentPage.searchPanel.searchEdit.SetFocus;
					ELSE
						currentPage.searchPanel.searchEdit.GetAsString(string);
						IF string = "" THEN
							currentPage.searchPanel.replEdit.SetAsString("");
							currentPage.searchPanel.visible.Set(FALSE);
							currentPage.editor.SetFocus;
						ELSE
							currentPage.searchPanel.searchEdit.SetAsString("");
							currentPage.searchPanel.searchEdit.SetFocus;
						END;
					END;
				END;
				RETURN TRUE;
			ELSIF (ucs = 0EH) & (flags * AosInputs.Ctrl # {}) THEN (* CTRL-N *)
				IF (currentPage # NIL)  & (flags * {AosInputs.Release} = {}) THEN
					currentPage.editor.SetFocus;
					backwards := currentPage.searchPanel.backwards;
					currentPage.searchPanel.backwards := FALSE;
					currentPage.searchPanel.SearchHandler(NIL, NIL);
					currentPage.searchPanel.backwards := backwards;
				END;
				RETURN TRUE;
			ELSIF (ucs = 10H) & (flags * AosInputs.Ctrl # {}) THEN (* CTRL-P *)
				IF (currentPage # NIL)  & (flags * {AosInputs.Release} = {}) THEN
					currentPage.editor.SetFocus;
					backwards := currentPage.searchPanel.backwards;
					currentPage.searchPanel.backwards := TRUE;
					currentPage.searchPanel.SearchHandler(NIL, NIL);
					currentPage.searchPanel.backwards := backwards;
				END;
				RETURN TRUE;
			ELSIF (ucs= 13H) & (flags * AosInputs.Ctrl # {}) THEN (* CTRL-S *)
				IF  (flags * {AosInputs.Release} = {}) THEN StoreHandler(NIL, NIL); END;
				RETURN TRUE;
			ELSIF (ucs = 0DH) & (flags * AosInputs.Ctrl # {}) THEN (* CTRL-M *)
				IF (currentPage # NIL)  & (flags * {AosInputs.Release} = {}) THEN
					IF currentPage.sidePanel.visible.Get() THEN currentPage.sidePanel.visible.Set(FALSE);
					ELSE currentPage.sidePanel.visible.Set(TRUE);
					END;
				END;
				RETURN TRUE;
			ELSIF (ucs = 08H) & (flags * AosInputs.Ctrl # {}) THEN (* CTRL-H *)
				IF (flags * {AosInputs.Release} = {}) THEN Compile(NIL, NIL); END;
				RETURN TRUE;
			ELSIF (ucs = 0FH) & (flags * AosInputs.Ctrl # {}) THEN (* CTRL-O *)
				IF (flags * {AosInputs.Release} = {}) THEN 
					filenameEdit.SetAsString("");
					filenameEdit.SetFocus;
				END;
				RETURN TRUE;
			ELSIF (ucs = 04H) & (flags * AosInputs.Ctrl # {}) THEN (* CTRL-D *)
				IF (currentPage # NIL) THEN
					filename := ""; Utilities.Append(filename, currentPage.filename); Utilities.Append(filename, ".Bak");
					IF (WMDialogs.QueryString("Diff to file...", filename) = WMDialogs.ResOk) THEN
						string := ""; Utilities.Append(string, currentPage.filename); Utilities.Append(string, " "); Utilities.Append(string, filename);
						NEW(par); NEW(par.str, LEN(string)); COPY(string, par.str^);
						AosCommands.Activate(DiffCommand, par, {}, res, string);
						IF (res # AosCommands.Ok) THEN
							res := WMDialogs.Message("Error", string, {WMDialogs.ResOk}); (* ignore res *)
						END;
					END;
				END;
				RETURN TRUE;
			ELSIF (ucs = 05H) & (flags * AosInputs.Ctrl # {}) THEN (* CTRL-E *)
				IF (currentPage # NIL)  & (flags * {AosInputs.Release} = {}) THEN
					currentPage.showErrorMarkers := ~currentPage.showErrorMarkers;
					ShowErrorMarkes(currentPage.showErrorMarkers);
					(* TODO: Indicate in GUI *)
					AosOut.String("PET: Error markers set "); 
					IF currentPage.showErrorMarkers THEN AosOut.String("visible."); 
					ELSE AosOut.String("INVISIBLE. Press CTRL-E to make them visible again.");
					END; 
					AosOut.Ln;
				END;
				RETURN TRUE;
			ELSIF (ucs = 0A3H) & (flags * AosInputs.Ctrl # {}) & (flags * {AosInputs.Release} = {}) THEN (* CTRL-PgDn *)
				IF  (flags * {AosInputs.Release} = {}) & (WMDialogs.QueryString("Save PET state into (.pet extension is appended)", filename) = WMDialogs.ResOk) & (filename # "") THEN
					Utilities.Append(filename, StateFileExtension);
					StoreState(filename);
				END;
				RETURN TRUE;
			ELSIF (ucs = 0A2H) & (flags * AosInputs.Ctrl # {}) & (flags * {AosInputs.Release} = {}) THEN (* CTRL-PgUp *)
				IF (flags * {AosInputs.Release} = {}) & (WMDialogs.QueryString("Load PET state from (.pet extension  is appended)", filename) = WMDialogs.ResOk) & (filename # "") THEN
					DisableUpdate;
					IF CloseAllTabs() THEN
						Utilities.Append(filename, StateFileExtension);
						IF LoadState(filename) THEN 
							UpdatePages;							
							UpdateState;
						END;
					END;
					EnableUpdate;
					IF (currentPage = NIL) THEN CSChanged; END;
				END;
				RETURN TRUE;
			ELSIF (ucs = 0A9H) & (flags * AosInputs.Ctrl # {}) & (flags * {AosInputs.Release} = {}) THEN (* CTRL-END *)
				DisableUpdate;
				SelectNextTab;
				EnableUpdate;
				RETURN TRUE;
			ELSIF (ucs = 0A1H) & (flags * AosInputs.Ctrl # {}) & (flags * {AosInputs.Release} = {}) THEN (* CTRL-DEL *)
				DisableUpdate;
				SelectPreviousTab;
				EnableUpdate;
				RETURN TRUE;
			ELSIF (ucs = 015H) & (flags * AosInputs.Ctrl # {}) & (flags * {AosInputs.Release} = {}) THEN (* CTRL-U *)
				IF (currentPage # NIL) THEN UnloadModule; END;
				RETURN TRUE;
			ELSIF (ucs = 30H) & (flags * AosInputs.Ctrl # {}) & (flags * {AosInputs.Release} = {}) THEN (* CTRL- 0 *)
				IF (currentPage # NIL) THEN currentPage.editor.tv.cursor.SetPosition(0); END;
				RETURN TRUE;
			ELSIF (ucs = 017H) & (flags * AosInputs.Ctrl # {}) & (flags * {AosInputs.Release} = {}) THEN (* CTRL-W *)
				IF (currentPage # NIL) THEN currentPage.searchPanel.WrapHandler(NIL, NIL); END;
			ELSIF (ucs = 009H) & (flags = {}) THEN (* TAB *)
				IF (currentPage # NIL) & (currentPage.searchPanel.visible.Get()) THEN
					(* hack - should not access hasFocus field *)
					IF currentPage.searchPanel.searchEdit.tv.hasFocus THEN
						currentPage.searchPanel.replEdit.SetFocus;
						currentPage.searchPanel.replEdit.Invalidate;
						RETURN TRUE;
					ELSIF currentPage.searchPanel.replEdit.tv.hasFocus THEN
						currentPage.searchPanel.searchEdit.SetFocus;
						currentPage.searchPanel.searchEdit.Invalidate;
						RETURN TRUE;
					END;
				END;
			END;
			RETURN FALSE;
		END HandleShortcut;

		PROCEDURE Handle(VAR m: WMMessages.Message);
		VAR data : WMRestorable.XmlElement;
		BEGIN
			IF m.msgType = WMMessages.MsgKey THEN 
				IF ~HandleShortcut(m.x, m.flags, m.y) THEN
					Handle^(m);
				END;
			ELSIF (m.msgType = WMMessages.MsgExt) & (m.ext # NIL) THEN
				IF (m.ext IS KillerMsg) THEN Close
				ELSIF (m.ext IS WMRestorable.Storage) THEN
					data := StorePages();
					m.ext(WMRestorable.Storage).Add("PET", "PET.Restore", SELF, data)
				ELSE Handle^(m)
				END
			ELSE Handle^(m)
			END
		END Handle;

	END Window;

VAR
	nofWindows, res : LONGINT;
	scratchText : AosTexts.Text;
	scratchModified : BOOLEAN;
	
PROCEDURE OpenFilesAs(par : ANY; format : ARRAY OF CHAR);
VAR 
	r : AosIO.StringReader;
	window : Window; count : LONGINT;
	filename : ARRAY 256 OF CHAR;
BEGIN
	AosCommands.PosPar(par, r);
	NEW(window, NIL); 
	count := 0;
	REPEAT
		r.SkipWhitespace; r.String(filename);
		IF filename # "" THEN window.Load(filename, format); INC(count) END
	UNTIL (r.res # AosIO.Ok);
	IF count = 0 THEN window.Load("Untitled.Mod", "AUTO") END;
END OpenFilesAs;
	
PROCEDURE OpenAscii*(par : ANY) : ANY;
BEGIN
	OpenFilesAs(par, "ISO8859-1");
	RETURN NIL
END OpenAscii;

PROCEDURE OpenOberon*(par : ANY) : ANY;
BEGIN
	OpenFilesAs(par, "Oberon");
	RETURN NIL
END OpenOberon;

PROCEDURE OpenUTF8*(par : ANY) : ANY;
BEGIN
	OpenFilesAs(par, "UTF-8");
	RETURN NIL
END OpenUTF8;

PROCEDURE OpenBB*(par : ANY) : ANY;
BEGIN
	OpenFilesAs(par, "BBT");
	RETURN NIL
END OpenBB;

PROCEDURE OpenHex*(par : ANY) : ANY;
BEGIN
	OpenFilesAs(par, "HEX");
	RETURN NIL
END OpenHex;

PROCEDURE Open*(par : ANY) : ANY;
BEGIN
	OpenFilesAs(par, "AUTO");
	RETURN NIL
END Open;

PROCEDURE OpenState*(par : ANY) : ANY; (** filename ~ *)
VAR r : AosIO.StringReader; filename : ARRAY 256 OF CHAR; window : Window;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(filename);
	NEW(window, NIL);
	IF ~window.LoadState(filename) THEN
		AosOut.String("PET: Could not load state from file "); AosOut.String(filename); AosOut.Ln;
	END;
	RETURN NIL
END OpenState;

PROCEDURE Restore*(par : ANY) : ANY;
VAR w : Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(w, par(WMRestorable.Context))
	END;
	RETURN NIL
END Restore;

PROCEDURE IncCount;
BEGIN {EXCLUSIVE}
	INC(nofWindows);
END IncCount;		

PROCEDURE DecCount;
BEGIN {EXCLUSIVE}
	DEC(nofWindows);
END DecCount;		

PROCEDURE ScratchModified(sender, data : ANY);
BEGIN
	scratchModified := TRUE
END ScratchModified;

PROCEDURE StoreScratchText;
VAR res : LONGINT;
BEGIN {EXCLUSIVE}
	IF scratchModified THEN
		scratchText.AcquireRead;
		AosTextUtilities.StoreOberonText(scratchText, ScratchTextFilename, res);
		scratchModified := FALSE;
		scratchText.ReleaseRead
	END;
END StoreScratchText;

PROCEDURE Cleanup;
VAR die : KillerMsg;
	 msg : WMMessages.Message;
	 m : WMWindowManager.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die); msg.ext := die; msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	(* load scratch text *)
	NEW(scratchText);
	scratchText.onTextChanged.Add(ScratchModified);
	scratchText.AcquireWrite;
	AosTextUtilities.LoadOberonText(scratchText, ScratchTextFilename, res);
	scratchText.ReleaseWrite
END PET.

S.Free PET ~
WMMacros.ReadMacros Macros.XML ~
PET.Open ~
PET.Open PET.Mod ~

S.Free PET WMXMLTree ~

PC0.Compile PET.Mod ~
