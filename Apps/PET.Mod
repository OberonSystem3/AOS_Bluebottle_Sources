MODULE PET; (** AUTHOR "TF"; PURPOSE "Programmer's Editing Tool"; *)

IMPORT
	AosOut, AosModules, AosCommands, AosIO, AosFS, WMRestorable, XML,
	WMStandardComponents, WMGraphics, WMGraphicUtilities,
	WMComponents, WMRectangles, WMMessages, WMDialogs,
	WMTextView, WMEditors, Utilities, AosTextUtilities, AosTexts, WMBitmapFont,
	WMWindowManager, MultiLogger, WMGrids, WMMacros, WMTrees, WMPopups,
	PCS, PCM, PC0, ModuleTrees, UTF8Strings;
	
CONST
	EditorFocus = 1;
	SplitEditorFocus = 2;
	TreeBtnShow = "Show Tree";
	TreeBtnHide = "Hide Tree";
	TreeLabelCaption = "Tree View";
	TreeLabelCaptionError = "Tree View (Parse Error)";
	
	OberonFormat = 0;
	UTF8Format = 1;
	AsciiFormat = 2;
	ExpXMLFormat = 3;
	
	FormatString = "Format: ";
	OberonFormatString = "Oberon";
	UTF8FormatString = "UTF-8";
	AsciiFormatString = "Ascii";
	ExpXMLFormatString = "Exp. XML";
	
	WrapOn = "Wrap is On";
	WrapOff = "Wrap is Off";
	
TYPE
	ErrorInfo = RECORD
		pos : POINTER TO ARRAY OF WMTextView.PositionMarker;
		err : LONGINT;
		errstr, msg: ARRAY 128 OF CHAR;
	END;
	
	ErrorList = POINTER TO ARRAY OF ErrorInfo;
	
	KillerMsg = OBJECT
	END KillerMsg;
	
	ContextMenuData = OBJECT
		VAR val: LONGINT;
		
		PROCEDURE & New(val: LONGINT);
		BEGIN
			SELF.val := val;
		END New;
	END ContextMenuData;
	
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
			searchBtn, replBtn, replAllBtn, closeBtn, wrapBtn: WMStandardComponents.Button;
			searchEdit, replEdit: WMEditors.Editor;
			searchLabel, replLabel: WMStandardComponents.Label;
			textView: WMTextView.TextView;
			text: AosTexts.Text;
			pos, len: LONGINT;
			posValid, wrap: BOOLEAN;
			wrapOn, wrapOff: Utilities.String;
			positionStack: PositionStack;
			
			PROCEDURE & Init;
			BEGIN
				Init^;

				NEW(upperPanel); upperPanel.alignment.Set(WMComponents.AlignTop);
				upperPanel.bounds.SetHeight(20);
				AddContent(upperPanel);
				
				NEW(searchLabel); searchLabel.alignment.Set(WMComponents.AlignLeft);
				searchLabel.bounds.SetWidth(40); searchLabel.fillColor.Set(0FFFFFFFFH);
				searchLabel.SetCaption("Search");
				upperPanel.AddContent(searchLabel);
				
				NEW(searchEdit); searchEdit.alignment.Set(WMComponents.AlignLeft);
				searchEdit.bounds.SetWidth(150); searchEdit.multiLine.Set(FALSE);
				searchEdit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1));
				searchEdit.tv.showBorder.Set(TRUE);
				searchEdit.fillColor.Set(0FFFFFFFFH);
				searchEdit.onEnter.Add(SearchHandler);
				searchEdit.text.onTextChanged.Add(TextChanged);
				searchEdit.tv.SetExtFocusHandler(FocusHandler);
				upperPanel.AddContent(searchEdit);
				
				NEW(replLabel); replLabel.alignment.Set(WMComponents.AlignLeft);
				replLabel.bounds.SetWidth(50); replLabel.fillColor.Set(0FFFFFFFFH);
				replLabel.SetCaption("Replace");
				upperPanel.AddContent(replLabel);
				
				NEW(replEdit); replEdit.alignment.Set(WMComponents.AlignLeft);
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
			
			PROCEDURE TextChanged(sender, data: ANY);
			VAR
				changeInfo: AosTexts.TextChangeInfo;
				searchStr: ARRAY 64 OF CHAR;
				ucsStr: ARRAY 64 OF AosTexts.Char32;
				idx, from: LONGINT;
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
				replStr, searchStr: ARRAY 64 OF CHAR;
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
				idx: LONGINT;
			BEGIN
				IF text = NIL THEN RETURN END;
				replEdit.GetAsString(replStr);
				UTF8Strings.UTF8toUnicode(replStr, ucsReplStr, idx); idx := 0;
				searchEdit.GetAsString(searchStr);
				UTF8Strings.UTF8toUnicode(searchStr, ucsSearchStr, idx);
				text.AcquireWrite();
				text.AcquireRead();
				Search(ucsSearchStr, 0);
				WHILE posValid DO
					Replace(ucsReplStr);
					Search(ucsSearchStr, pos + len);
				END;
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
				IF ucsStr[0] = 0 THEN posValid := FALSE; RETURN END;
				pos := AosTextUtilities.Pos(ucsStr, from, text);
				len := AosTextUtilities.UCS32StrLength(ucsStr);
				IF pos > -1 THEN posValid := TRUE
				ELSE posValid := FALSE
				END;
			END Search;
			
			PROCEDURE SearchAndHighlight(from: LONGINT);
			VAR
				searchStr: ARRAY 64 OF CHAR;
				ucsStr: ARRAY 64 OF AosTexts.Char32;
				idx: LONGINT;
			BEGIN
				IF text = NIL THEN RETURN END;
				searchEdit.GetAsString(searchStr);
				UTF8Strings.UTF8toUnicode(searchStr, ucsStr, idx);
				text.AcquireRead();
				Search(ucsStr, from);
				IF (pos = -1) & wrap THEN Search(ucsStr, 0) END;
				text.ReleaseRead();
				Highlight;
			END SearchAndHighlight;
			
			PROCEDURE Highlight;
			BEGIN
				IF textView = NIL THEN RETURN END;
				IF pos > -1 THEN
					textView.selection.SetFrom(pos);
					textView.selection.SetTo(pos + len);
					textView.cursor.SetPosition(pos + len);
				END;
			END Highlight;		
			
			PROCEDURE CloseHandler(sender, data: ANY);
			BEGIN
				visible.Set(FALSE);
			END CloseHandler;
			
	END SearchPanel;
	

	Window* = OBJECT (WMComponents.FormWindow)
	VAR
		editor, splitEditor, logEdit : WMEditors.Editor;
		errorLog : WMGrids.GenericGrid;
		topToolbar, splitPanel: WMStandardComponents.Panel;
		sidePanel : WMStandardComponents.Panel;
		logPanel, editPanel: WMStandardComponents.Panel;
		searchPanel: SearchPanel;
		filenameEdit, optionsEdit: WMEditors.Editor;
		load, store, compile, findPC, treeBtn: WMStandardComponents.Button;
		splitBtn, formatBtn, searchBtn: WMStandardComponents.Button;
		compileErrors : ErrorList;
		errlist : PCM.ErrorList;
		colWidths : WMGrids.Spacings;
		moduleTree: ModuleTrees.ModuleTree;

		popup: WMPopups.Popup;
		modified, splitted: BOOLEAN;
		focus, fileFormat: LONGINT;
		
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR panel : WMStandardComponents.Panel;
			resizerH, resizerV: WMStandardComponents.Resizer;
		BEGIN
			
			NEW(panel); panel.bounds.SetExtents(850, 700); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
			NEW(topToolbar); topToolbar.bounds.SetHeight(20); topToolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(topToolbar);
			
			
			(* left tool area *)
			NEW(sidePanel);
			sidePanel.bounds.SetWidth(250); sidePanel.alignment.Set(WMComponents.AlignLeft);
			panel.AddContent(sidePanel);
			
			NEW(resizerH); resizerH.alignment.Set(WMComponents.AlignRight);
			resizerH.bounds.SetWidth(4);
			sidePanel.AddContent(resizerH);
			
			NEW(moduleTree); moduleTree.alignment.Set(WMComponents.AlignClient);
			sidePanel.AddContent(moduleTree);
			
			
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
			
			NEW(formatBtn); formatBtn.caption.SetAOC("Format"); formatBtn.alignment.Set(WMComponents.AlignLeft);
			formatBtn.SetExtPointerDownHandler(FormatHandler);
			formatBtn.bounds.SetWidth(2 * formatBtn.bounds.GetWidth());
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
			
			NEW(treeBtn);
			IF sidePanel.visible.Get() THEN treeBtn.caption.SetAOC(TreeBtnHide)
			ELSE treeBtn.caption.SetAOC(TreeBtnShow)
			END;
			treeBtn.alignment.Set(WMComponents.AlignLeft);
			treeBtn.bounds.SetWidth(ENTIER(1.5 * treeBtn.bounds.GetWidth()));
			treeBtn.onClick.Add(ShowHideTree);
			topToolbar.AddContent(treeBtn);
			
			NEW(splitBtn); splitBtn.caption.SetAOC("Split"); splitBtn.alignment.Set(WMComponents.AlignLeft);
			splitBtn.onClick.Add(Split);
			topToolbar.AddContent(splitBtn);
			
			NEW(optionsEdit); optionsEdit.tv.showBorder.Set(TRUE); optionsEdit.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1));
			optionsEdit.alignment.Set(WMComponents.AlignLeft); optionsEdit.multiLine.Set(FALSE);
			optionsEdit.bounds.SetWidth(80); optionsEdit.fillColor.Set(0FFFFFFFFH);
			topToolbar.AddContent(optionsEdit);
			optionsEdit.SetAsString("/s");
			
(*			NEW(pcLabel); pcLabel.SetCaption(" pc="); pcLabel.alignment.Set(WMComponents.AlignLeft);
			pcLabel.bounds.SetWidth(25); pcLabel.fillColor.Set(0FFFFFFFFH);
			topToolbar.AddContent(pcLabel); 
			
			NEW(pcEdit); pcEdit.tv.showBorder.Set(TRUE); pcEdit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1));
			pcEdit.alignment.Set(WMComponents.AlignLeft); pcEdit.multiLine.Set(FALSE);
			pcEdit.bounds.SetWidth(40); pcEdit.fillColor.Set(0FFFFFFFFH);
			topToolbar.AddContent(pcEdit); *)
			
			NEW(editPanel); editPanel.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(editPanel);
			
			NEW(logPanel);
			logPanel.alignment.Set(WMComponents.AlignBottom);
			logPanel.bounds.SetHeight(130);
						
			NEW(logEdit); logEdit.bounds.SetHeight(30); logEdit.alignment.Set(WMComponents.AlignBottom);
			logEdit.allowScrollbars.Set(FALSE);
			editPanel.AddContent(logEdit);
			logEdit.tv.showBorder.Set(TRUE); logEdit.visible.Set(FALSE);
	(*		logEdit.tv.SetFont(WMBitmapFont.bimbofont); *)
			
			editPanel.AddContent(logPanel);
			NEW(errorLog);
			errorLog.alignment.Set(WMComponents.AlignClient);
			errorLog.nofCols.Set(3);
			errorLog.fixedRows.Set(1);
			NEW(colWidths, 3); 
			colWidths[0] := errorLog.defaultColWidth.Get() DIV 2;
			colWidths[1] := errorLog.defaultColWidth.Get() DIV 2;
			colWidths[2] := errorLog.defaultColWidth.Get() * 4;
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
			(*editor.tv.SetFont(WMBitmapFont.bimbofont);*)
			editor.text.onTextChanged.Add(TextChanged);
			
			searchPanel.SetText(editor.text);
			moduleTree.SetEditor(editor);
			
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
		(*	splitEditor.tv.SetFont(WMBitmapFont.bimbofont); *)
			
			RETURN panel
		END CreateForm;
		
			
		PROCEDURE &New(c : WMRestorable.Context);
		VAR i, fl, cp: LONGINT;
			 vc : WMComponents.VisualComponent;
			 xml : XML.Element;
			 s : Utilities.String;
		BEGIN
			IncCount;
			vc := CreateForm();
			splitEditor.SetText(editor.text);

			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			logPanel.visible.Set(FALSE);
			splitPanel.visible.Set(FALSE);
			SetContent(vc);
			
			NEW(errlist, 20);
			NEW(compileErrors, 20);
			FOR i := 0 TO LEN(compileErrors)-1 DO
				NEW(compileErrors[i].pos, 2);	(* number of editors *)
			END;
			
			IF c # NIL THEN 
				(* restore the desktop *)
				WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame});
				IF c.appData # NIL THEN
					xml := c.appData(XML.Element);
					s := xml.GetAttributeValue("fileFormat"); IF s # NIL THEN Utilities.StrToInt(s^, fileFormat) END;
					s := xml.GetAttributeValue("firstLine");IF s # NIL THEN Utilities.StrToInt(s^, fl) END;
					s := xml.GetAttributeValue("cursorPos");IF s # NIL THEN Utilities.StrToInt(s^, cp) END;
					s := xml.GetAttributeValue("optionsString");IF s # NIL THEN optionsEdit.SetAsString(s^) END;
					
					s := xml.GetAttributeValue("file"); 
					IF s # NIL THEN Load(s^, fileFormat) END;
					editor.tv.firstLine.Set(fl);
					editor.tv.cursor.SetPosition(cp)
				END			
			ELSE WMWindowManager.DefaultAddWindow(SELF);
				fileFormat := 0
			END;
			SetFormatCaption(fileFormat);
			SetTitle(Utilities.NewString("Programmer's Editing Tool"))
		END New;
		
		PROCEDURE EditorFocusHandler(hasFocus: BOOLEAN);
		BEGIN
			IF hasFocus THEN
				focus := EditorFocus;
				searchPanel.SetTextView(editor.tv);
				moduleTree.SetEditor(editor);
			END;
		END EditorFocusHandler;
		
		PROCEDURE SplitEditorFocusHandler(hasFocus: BOOLEAN);
		BEGIN
			IF hasFocus THEN
				focus := SplitEditorFocus;
				searchPanel.SetTextView(splitEditor.tv);
				moduleTree.SetEditor(splitEditor);			
			END
		END SplitEditorFocusHandler;

(*		PROCEDURE Open(name : ARRAY OF CHAR);
		BEGIN
			filenameEdit.SetAsString(name);
		(*	LoadHandler(SELF, SELF) *)
		END Open; *)
		
		PROCEDURE ErrorClick(sender, data : ANY);
		VAR scol, srow, ecol, erow, y : LONGINT;
			focusEditor: WMEditors.Editor;
			index: LONGINT;
		BEGIN
			errorLog.GetSelection(scol, srow, ecol, erow);
			y := srow;
			IF (compileErrors # NIL) & (y > 0) & (y <= LEN(compileErrors^)) THEN
				DEC(y);	(* first row is header row *)
				IF focus = EditorFocus THEN focusEditor := editor; index := 0
				ELSIF focus = SplitEditorFocus THEN focusEditor := splitEditor; index := 1
				ELSE RETURN
				END;
				IF compileErrors[y].pos[index] # NIL THEN
					focusEditor.tv.cursor.SetPosition(compileErrors[y].pos[index].GetPosition());
					focusEditor.SetFocus
				END
			END
		END ErrorClick;

		PROCEDURE FormatHandler(x, y: LONGINT; keys: SET; VAR handled: BOOLEAN);
		VAR rectangle: WMRectangles.Rectangle;
		BEGIN
			NEW(popup);
			popup.AddParButton(OberonFormatString, FormatPopupHandler, ctxMenuOberon);
			popup.AddParButton(UTF8FormatString, FormatPopupHandler, ctxMenuUTF8);
			popup.AddParButton(AsciiFormatString, FormatPopupHandler, ctxMenuAscii);
			popup.AddParButton(ExpXMLFormatString, FormatPopupHandler, ctxMenuExpXML);
			handled := TRUE;
			rectangle := formatBtn.bounds.Get();
			popup.Popup(bounds.l + rectangle.l, bounds.t + rectangle.t + rectangle.b);
		END FormatHandler;
		
		PROCEDURE SetFormatCaption(format : LONGINT);
		VAR caption : ARRAY 100 OF CHAR;
		BEGIN			
			caption := "Format : ";
			CASE format OF
				| AsciiFormat : Utilities.Append(caption, AsciiFormatString)
				| UTF8Format : Utilities.Append(caption, UTF8FormatString)
				| OberonFormat : Utilities.Append(caption, OberonFormatString)
				| ExpXMLFormat : Utilities.Append(caption, ExpXMLFormatString)
			ELSE Utilities.Append(caption, "??? unknown")
			END;
			formatBtn.caption.SetAOC(caption)
		END SetFormatCaption;
		
		PROCEDURE FormatPopupHandler(sender, data: ANY);
		BEGIN
			IF (data # NIL) & (data IS ContextMenuData) THEN;
				popup.Close;
				fileFormat := data(ContextMenuData).val;
				SetFormatCaption(fileFormat)
			END;
		END FormatPopupHandler;
		
		PROCEDURE LoadHandler(sender, data : ANY);
		VAR filename : ARRAY 256 OF CHAR;
		BEGIN
			filenameEdit.GetAsString(filename);
			Load(filename, fileFormat)
		END LoadHandler;
		
		PROCEDURE Load(filename : ARRAY OF CHAR; format : LONGINT);
		VAR text : AosTexts.Text; res : LONGINT;
		BEGIN
			fileFormat := format;
			SetFormatCaption(fileFormat); 
			filenameEdit.SetAsString(filename);
			text := editor.text;
			text.AcquireWrite;
			modified := TRUE; (* avoid the ! on the store button while loading *)
			text.Delete(0, text.GetLength());
			IF format = OberonFormat THEN AosTextUtilities.LoadOberonText(text, filename, res)
			ELSIF format = UTF8Format THEN AosTextUtilities.LoadUTF8(text, filename, res)
			ELSIF format = AsciiFormat THEN AosTextUtilities.LoadAscii(text, filename, res)
			ELSIF format = ExpXMLFormat THEN AosTextUtilities.LoadText(text, filename, res)
			END;
			text.ReleaseWrite;
			moduleTree.Erase();
			editor.tv.firstLine.Set(0);
			editor.tv.cursor.SetPosition(0);
			editor.tv.SetFocus;
			IF Utilities.Pos('.Mod', filename) > 0 THEN
				moduleTree.RefreshHandler(SELF, NIL);
				sidePanel.visible.Set(TRUE);
				treeBtn.caption.SetAOC(TreeBtnHide)
			ELSE
				sidePanel.visible.Set(FALSE);
				treeBtn.caption.SetAOC(TreeBtnShow)
			END;
			modified := FALSE; store.caption.SetAOC("Store")	
		END Load;

		PROCEDURE StoreHandler(sender, data : ANY);
		VAR filename : ARRAY 256 OF CHAR;
		BEGIN
			filenameEdit.GetAsString(filename);
			Store(filename, fileFormat)
		END StoreHandler;
				
		PROCEDURE Store(filename : ARRAY OF CHAR; format : LONGINT);
		VAR text : AosTexts.Text; res : LONGINT;
		BEGIN
			filenameEdit.SetAsString(filename);
			text := editor.text;
			text.AcquireWrite;
			IF format = OberonFormat THEN AosTextUtilities.StoreOberonText(text, filename, res)
			ELSIF format = UTF8Format THEN AosTextUtilities.ExportUTF8(text, filename, res)
			ELSIF format = AsciiFormat THEN AosTextUtilities.ExportAscii(text, filename, res)
			ELSIF format = ExpXMLFormat THEN AosTextUtilities.StoreText(text, filename, res)
			END;
			text.ReleaseWrite;			
			modified := FALSE; store.caption.SetAOC("Store")
		END Store;		

		PROCEDURE SearchHandler(sender, data: ANY);
		BEGIN
			searchPanel.visible.Set(TRUE);
		END SearchHandler;
		
		PROCEDURE ShowHideTree(sender, data: ANY);
		BEGIN
			IF sidePanel.visible.Get() THEN
				sidePanel.visible.Set(FALSE);
				treeBtn.caption.SetAOC(TreeBtnShow);
			ELSE
				sidePanel.visible.Set(TRUE);
				treeBtn.caption.SetAOC(TreeBtnHide);
			END;
		END ShowHideTree;
		
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
					| 2 : str := "Error Str"
				ELSE
				END
			ELSIF (compileErrors # NIL) & (y - 1 >= 0) & (y < LEN(compileErrors^)) THEN
				CASE x OF
					| 0 : IF compileErrors[y - 1].pos[0] # NIL THEN Utilities.IntToStr(compileErrors[y - 1].pos[0].GetPosition(), str) END
					| 1 : Utilities.IntToStr(compileErrors[y - 1].err, str)
					| 2 : COPY(compileErrors[y - 1].msg, str) 
				ELSE
				END
			END;
			canvas.DrawString(4, h-4, str)
		END DrawCell;
		
		PROCEDURE TextChanged(sender, data : ANY);
		BEGIN
			IF logPanel.visible.Get() THEN
				logPanel.Invalidate
			END;
			
			IF ~modified THEN
				store.caption.SetAOC("Store !");
				modified := TRUE
			END
		END TextChanged;

		PROCEDURE Split(sender, data: ANY);
		BEGIN
			IF splitted THEN
				splitBtn.caption.Set(Utilities.NewString("Split"));
				splitPanel.visible.Set(FALSE);
			ELSE
				splitBtn.caption.Set(Utilities.NewString("Unsplit"));
				splitPanel.visible.Set(TRUE);
			END;
			splitted := ~splitted;
		END Split;
						
		PROCEDURE FindPC(sender, data : ANY);
		VAR pc, a, b : LONGINT;
			pcStr : ARRAY 64 OF CHAR;
			selectionText: AosTexts.Text;
			from, to: AosTexts.TextPosition;
		BEGIN
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
				DoCompile(TRUE, 0)
			END
		END FindPC;
						
		PROCEDURE Compile(sender, data : ANY);
		BEGIN
			DoCompile(FALSE, 0)
		END Compile;
						
		PROCEDURE DoCompile(findPC : BOOLEAN; pc : LONGINT);
		VAR text : AosTexts.Text; errors : BOOLEAN;
			logStream : AosIO.Writer;
			logger : MultiLogger.StreamLogger;
			i, j: LONGINT;
			arg : ARRAY 64 OF CHAR;
			entry: PCM.ErrorEntry;
		BEGIN
			text := editor.text;
			text.AcquireRead;
			FOR i := 0 TO LEN(compileErrors) - 1 DO 
				IF compileErrors[i].pos[0] # NIL THEN 
					editor.tv.RemovePositionMarker(compileErrors[i].pos[0]);
					compileErrors[i].pos[0] := NIL;
				END;
				IF compileErrors[i].pos[1] # NIL THEN
					splitEditor.tv.RemovePositionMarker(compileErrors[i].pos[1]);
					compileErrors[i].pos[1] := NIL
				END
			END;

			(* clear the log *)		
			logEdit.text.AcquireWrite;
			logEdit.text.Delete(0, logEdit.text.GetLength());
			logEdit.tv.firstLine.Set(0); logEdit.tv.cursor.SetPosition(0);
			logEdit.text.ReleaseWrite;
			
			
			NEW(logger, logStream, logEdit.text);
			
			optionsEdit.GetAsString(arg);
			IF findPC THEN Utilities.Append(arg, " /f") END;
		
			PC0.CompileText(text, 0, pc, arg, logStream, errlist, errors);
			IF errors & (errlist # NIL) THEN
				j := 0;
				WHILE errlist.HasMoreErrors() DO
					entry := errlist.GetNext();
						(* main editor *)
					compileErrors[j].pos[0] := editor.tv.CreatePositionMarker();
					compileErrors[j].pos[0].Load("Flash.png");	
					compileErrors[j].pos[0].SetPosition(entry.pos);
						(* split editor *)
					compileErrors[j].pos[1] := splitEditor.tv.CreatePositionMarker();
					compileErrors[j].pos[1].Load("Flash.png");	
					compileErrors[j].pos[1].SetPosition(entry.pos);
					compileErrors[j].err := entry.err;
					COPY(entry.msg, compileErrors[j].msg);
					INC(j)
				END;
				IF compileErrors[0].pos # NIL THEN
					IF focus = EditorFocus THEN 
						editor.tv.cursor.SetPosition(compileErrors[0].pos[0].GetPosition());
						editor.SetFocus
					ELSE
						splitEditor.tv.cursor.SetPosition(compileErrors[0].pos[1].GetPosition());
						splitEditor.SetFocus
					END
				END;
				
				logPanel.visible.Set(TRUE); logEdit.visible.Set(FALSE);
				logPanel.Invalidate;
				errorLog.nofRows.Set(j + 1); 
			ELSE logPanel.visible.Set(FALSE); logEdit.visible.Set(TRUE)
			END;
			IF logger # NIL THEN logger.Kill() END;
			text.ReleaseRead;
		END DoCompile;
		
		PROCEDURE Close;
		BEGIN
			Close^;
			DecCount
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		VAR data : XML.Element; a : XML.Attribute; n, str : ARRAY 16 OF CHAR;
			filename : ARRAY 256 OF CHAR;
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS KillerMsg) THEN Close
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					NEW(data);  n := "PETData"; data.SetName(n);
					filenameEdit.GetAsString(filename);
					NEW(a); n := "file"; a.SetName(n); a.SetValue(filename); data.AddAttribute(a);
					NEW(a); n := "fileFormat"; a.SetName(n); Utilities.IntToStr(fileFormat, str); a.SetValue(str); data.AddAttribute(a);
					NEW(a); n := "firstLine"; a.SetName(n); Utilities.IntToStr(editor.tv.firstLine.Get(), str); a.SetValue(str); data.AddAttribute(a);
					NEW(a); n := "cursorPos"; a.SetName(n); Utilities.IntToStr(editor.tv.cursor.GetPosition(), str); a.SetValue(str); data.AddAttribute(a);
					NEW(a); n := "optionsString"; a.SetName(n); optionsEdit.GetAsString(str); a.SetValue(str); data.AddAttribute(a);
					x.ext(WMRestorable.Storage).Add("PET", "PET.Restore", SELF, data)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;

	END Window;

VAR
	nofWindows : LONGINT;
	ctxMenuOberon, ctxMenuUTF8, ctxMenuAscii, ctxMenuExpXML : ContextMenuData;
	treeFontOberon10Plain, treeFontOberon10Bold, treeFontOberon10Italic: WMGraphics.Font;
	
(*PROCEDURE Open*(par : ANY) : ANY;
VAR inst : Window;
	s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	name : ARRAY 256 OF CHAR;
BEGIN
	NEW(inst, NIL);
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.String(name);
	inst.Load(name, OberonFormat);
	RETURN NIL
END Open; *)

PROCEDURE GetNameFromPar(par : ANY; VAR name : ARRAY OF CHAR);
VAR s : AosCommands.Parameters;
	sr : AosIO.StringReader;
BEGIN
	s := par(AosCommands.Parameters); NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.String(name);	
END GetNameFromPar;

PROCEDURE OpenAscii*(par : ANY) : ANY;
VAR inst : Window;
	name : ARRAY 256 OF CHAR;
BEGIN
	GetNameFromPar(par, name);
	NEW(inst, NIL); inst.Load(name, AsciiFormat);
	RETURN NIL
END OpenAscii;

PROCEDURE OpenOberon*(par : ANY) : ANY;
VAR inst : Window;
	name : ARRAY 256 OF CHAR;
BEGIN
	GetNameFromPar(par, name);
	NEW(inst, NIL); inst.Load(name, OberonFormat);
	RETURN NIL
END OpenOberon;

PROCEDURE OpenUTF8*(par : ANY) : ANY;
VAR inst : Window;
	name : ARRAY 256 OF CHAR;
BEGIN
	GetNameFromPar(par, name);
	NEW(inst, NIL); inst.Load(name, UTF8Format);
	RETURN NIL
END OpenUTF8;

PROCEDURE Open*(par : ANY) : ANY;
VAR inst : Window;
BEGIN
	NEW(inst, NIL);
	RETURN NIL
END Open;

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
	AosModules.InstallTermHandler(Cleanup);
	NEW(ctxMenuOberon, OberonFormat);
	NEW(ctxMenuUTF8, UTF8Format);
	NEW(ctxMenuAscii, AsciiFormat);
	NEW(ctxMenuExpXML, ExpXMLFormat);
	
	treeFontOberon10Plain := WMGraphics.GetFont("Oberon", 10, {});
	treeFontOberon10Bold := WMGraphics.GetFont("Oberon", 10, {WMGraphics.FontBold});
	treeFontOberon10Italic := WMGraphics.GetFont("Oberon", 10, {WMGraphics.FontItalic});
END PET.

S.Free PET ~
WMMacros.ReadMacros Macros.XML ~
PET.Open ~
PET.Open PET.Mod ~

PC0.Compile PET.Mod ~
