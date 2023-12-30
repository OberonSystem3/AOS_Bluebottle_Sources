MODULE WMTextStyleTool;	(** AUTHOR "TF"; PURPOSE "Text Tool"; *)
(**
 * History:
 *
 *	04.09.2006	Added SetStyleByName command procedure (staubesv)
 *)
 
IMPORT
	AosCommands, AosIO, AosTexts, Utilities, WMProperties, WMEvents, WMComponents, WMRestorable, WMStringGrids, WMGrids, 
	WMEditors, WMGraphics, WMMessages, WMStandardComponents, AosModules,
	WMPopups, WMRectangles, WMDialogs, FP1616, AosFS, XMLParser, XMLScanner, XML, XMLObjects,
	WMGraphicUtilities, WMRasterScale, AosOut, WMTextView,
	WM := WMWindowManager;

CONST
	AlignLeft = 0; AlignCenter = 1; AlignRight = 2; AlignJustified = 3;
	StyleRegular = 0; StyleBold = 1; StyleItalic = 2; StyleBoldItalic = 3;

TYPE
	KillerMsg = OBJECT
	END KillerMsg; 
	
	ContextMenuData = OBJECT
	VAR val: LONGINT;
		PROCEDURE &New(val: LONGINT);
		BEGIN
			SELF.val := val;
		END New;
	END ContextMenuData;
	
	Window* = OBJECT (WMComponents.FormWindow)
	VAR 
		bold, lock, comment, stupid, assert, preferred, debug, normal, hadd, hrem,
		highlight, adhoc, more, edit, link, label: WMStandardComponents.Button;
		winpanel : WMStandardComponents.Panel;
		cList : WMStringGrids.StringGrid;
		styleEditor : StyleEditor;
		
		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			toolbar: WMStandardComponents.Panel;
			
			PROCEDURE AB(panel : WMStandardComponents.Panel; btn: WMStandardComponents.Button);
			BEGIN
				btn.alignment.Set(WMComponents.AlignLeft); btn.bounds.SetWidth(60); panel.AddContent(btn)
			END AB;	

		BEGIN
			NEW(panel); panel.bounds.SetExtents(120, 140); panel.takesFocus.Set(TRUE);

			(* link & label*)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(link); link.caption.SetAOC("Add Link"); AB(toolbar, link); link.clDefault.Set(080CC80H);
			NEW(label); label.caption.SetAOC("Add Label"); AB(toolbar, label); label.clDefault.Set(080CC80H);	
			
			(* styles *)
			(**)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);			
			NEW(bold); bold.caption.SetAOC("Bold"); AB(toolbar, bold);
			NEW(lock); lock.caption.SetAOC("Lock"); AB(toolbar, lock);
	
			(**)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(comment); comment.caption.SetAOC("Comment"); AB(toolbar, comment);
			NEW(debug); debug.caption.SetAOC("Debug"); AB(toolbar, debug);
	
			(**)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);			
			NEW(stupid); stupid.caption.SetAOC("Stupid"); AB(toolbar, stupid);
			NEW(assert); assert.caption.SetAOC("Assert"); AB(toolbar, assert);
			
			(**)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(preferred); preferred.caption.SetAOC("Preferred"); AB(toolbar, preferred);
			NEW(normal); normal.caption.SetAOC("Normal"); AB(toolbar, normal);
			
			(**)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(highlight); highlight.caption.SetAOC("Highlight"); AB(toolbar, highlight);
			NEW(adhoc); adhoc.caption.SetAOC("AdHoc"); AB(toolbar, adhoc); adhoc.clDefault.Set(0CC0080H);			
			
(* 			(* highlight *)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(hadd); hadd.caption.SetAOC("HL Add"); AB(toolbar, hadd);
			NEW(hrem); hrem.caption.SetAOC("HL Remove"); AB(toolbar, hrem);			
*)
			(* style edit *)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(more); more.caption.SetAOC("More"); AB(toolbar, more); more.clDefault.Set(0CC000080H);
			NEW(edit); edit.caption.SetAOC("Edit"); AB(toolbar, edit); edit.clDefault.Set(0CC000080H); edit.visible.Set(FALSE);
			
			(* List *)
			NEW(cList); cList.alignment.Set(WMComponents.AlignClient);
			cList.onClick.Add(SetStyleFromList); cList.clCell.Set(0FFFFFFCCH); cList.clHover.Set(0FFFF00CCH);
			cList.model.Acquire;
			cList.model.SetNofCols(1);
			cList.model.SetNofRows(1);
			cList.SetSelectionMode(WMGrids.GridSelectSingleRow);
			cList.model.Release;
			panel.AddContent(cList);		
				
			winpanel := panel;
			RETURN panel
		END CreateForm;

		PROCEDURE &New(c : WMRestorable.Context);
		VAR vc : WMComponents.VisualComponent;
			xml : XML.Element;
			 s : Utilities.String;
			 temp : BOOLEAN;
		BEGIN
			IncCount;
			vc := CreateForm();

			bold.onClick.Add(SetStyle);
			lock.onClick.Add(SetStyle);
			comment.onClick.Add(SetStyle);
			debug.onClick.Add(SetStyle);
			stupid.onClick.Add(SetStyle);
			assert.onClick.Add(SetStyle);
			preferred.onClick.Add(SetStyle);
			normal.onClick.Add(SetStyle);
			highlight.onClick.Add(SetStyle);
			(* adhoc style *)
			adhoc.onClick.Add(AdHocStyle);
			(* style editor *)
			more.onClick.Add(ShowList);
			edit.onClick.Add(EditStyles);
(*			hadd.onClick.Add(AddHighlight);
			hrem.onClick.Add(RemoveHighlight);
*)			
			link.onClick.Add(AddLink);
			label.onClick.Add(AddLabel);

			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), TRUE);
			SetContent(vc);
			BuildList;

			IF c # NIL THEN 	
				WMRestorable.AddByContext(SELF, c, {WM.FlagStayOnTop, WM.FlagFrame});
				IF c.appData # NIL THEN
					xml := c.appData(XML.Element);
					s := xml.GetAttributeValue("expanded");
					IF s # NIL THEN Utilities.StrToBool(s^, temp) END;
					IF temp THEN
						more.caption.SetAOC("Less");
						edit.visible.Set(TRUE);					
					END;
				END;
				Resized(GetWidth(), GetHeight());						
			ELSE  WM.ExtAddWindow(SELF, 50, 50, 
			 	{WM.FlagStayOnTop, WM.FlagFrame})
			 END;	
			SetTitle(Utilities.NewString("Text Styles"))
		END New;
		
		(* -- Handlers -- *)
		
		PROCEDURE AdHocStyle(sender, data : ANY);
		VAR adhocStyle : AdHocStyleWindow;
		BEGIN
			NEW(adhocStyle)
		END AdHocStyle;			
		
		PROCEDURE EditStyles(sender, data: ANY);
		BEGIN
			IF styleEditor = NIL THEN 
				NEW(styleEditor); 
				styleEditor.UpdateProc := BuildList;				
			END;
			styleEditor.Show(200, 150);
		END EditStyles;

		PROCEDURE ShowList(sender, data: ANY);
		VAR caption : Utilities.String;
			button : WMStandardComponents.Button;
			rect : WMGraphics.Rectangle;
			width, height : LONGINT;
		BEGIN
			button :=  sender(WMStandardComponents.Button);
			caption :=  button.caption.Get();
			manager := WM.GetDefaultManager();
			IF caption^ = "More" THEN
				button.caption.SetAOC("Less");
				width := GetWidth(); height := GetHeight()+ 300;
				edit.visible.Set(TRUE); 
			ELSE	
				button.caption.SetAOC("More");
				width := GetWidth(); height := 140;
				edit.visible.Set(FALSE); 
			END;
			manager.SetWindowSize(SELF, width, height); Resized(width, height);
		END ShowList;
		
		PROCEDURE BuildList;
		VAR styles : AosTexts.CharacterStyleArray;
		i : LONGINT;
		BEGIN
			styles := AosTexts.GetCharacterStyleArray();
			cList.model.Acquire;
			i := 0;
			WHILE ((i<LEN(styles))  & (styles[i] # NIL)) DO
				cList.model.SetNofRows(i+1);
				cList.model.SetCellText(0, i, Utilities.NewString(styles[i].name));
				cList.model.SetCellData(0, i, styles[i]);
				INC(i);
			END;
			cList.model.Release;			
		END  BuildList;
		
		PROCEDURE SetStyleFromList(sender, data: ANY);
		VAR text : AosTexts.Text;
			from, to : AosTexts.TextPosition;
			a, b, ch : LONGINT;
			cStyle : AosTexts.CharacterStyle;
		BEGIN
			IF (data # NIL ) THEN
				cStyle := data(AosTexts.CharacterStyle);
				IF AosTexts.GetLastSelection(text, from, to) THEN
				text.AcquireWrite;
				a := Utilities.Min(from.GetPosition(), to.GetPosition());
				b := Utilities.Max(from.GetPosition(), to.GetPosition());
				text.SetCharacterStyle(a, b - a, cStyle);
				text.ReleaseWrite				
				END
			END;
		END SetStyleFromList;
				
		PROCEDURE SetStyle(sender, data : ANY);
		VAR text : AosTexts.Text;
			from, to : AosTexts.TextPosition;
			a, b, ch : LONGINT;
			cStyle : AosTexts.CharacterStyle;
		BEGIN
			IF AosTexts.GetLastSelection(text, from, to) THEN

				IF sender = bold THEN
					cStyle := AosTexts.GetCharacterStyleByName("Bold");
				ELSIF sender = lock THEN
					cStyle := AosTexts.GetCharacterStyleByName("Lock");
				ELSIF sender = preferred THEN
					cStyle := AosTexts.GetCharacterStyleByName("Preferred");
				ELSIF sender = assert THEN
					cStyle := AosTexts.GetCharacterStyleByName("Assertion");
				ELSIF sender = comment THEN
					cStyle := AosTexts.GetCharacterStyleByName("Comment");
				ELSIF sender = debug THEN
					cStyle := AosTexts.GetCharacterStyleByName("Debug");
				ELSIF sender = stupid THEN
					cStyle := AosTexts.GetCharacterStyleByName("Stupid");
				ELSIF sender = normal THEN
					cStyle := AosTexts.GetCharacterStyleByName("Normal");
				ELSIF sender = highlight THEN
					cStyle := AosTexts.GetCharacterStyleByName("Highlight");	
				END;
				text.AcquireWrite;
				a := Utilities.Min(from.GetPosition(), to.GetPosition());
				b := Utilities.Max(from.GetPosition(), to.GetPosition());
				text.SetCharacterStyle(a, b - a, cStyle);
				text.ReleaseWrite
			END
		END SetStyle;
		
		PROCEDURE AddLink(sender, data: ANY);
		VAR text : AosTexts.Text;
			from, to : AosTexts.TextPosition;
			a, b, ch : LONGINT;
			tempLink: ARRAY 2083 OF CHAR;
			link : AosTexts.Link;
			
		BEGIN
			IF AosTexts.GetLastSelection(text, from, to) THEN
				IF WMDialogs.QueryString("Enter Link", tempLink) = WMDialogs.ResOk THEN
					link := Utilities.NewString(tempLink);
					text.AcquireWrite;
					a := Utilities.Min(from.GetPosition(), to.GetPosition());
					b := Utilities.Max(from.GetPosition(), to.GetPosition());
					text.SetLink(a, b - a, link);
					text.ReleaseWrite
				END
			END	
		END AddLink;
		
		PROCEDURE AddLabel(sender, data: ANY);
		VAR text : AosTexts.Text;
			from, to : AosTexts.TextPosition;
			a, b, ch : LONGINT;
			label : ARRAY 256 OF CHAR;
			lp : AosTexts.LabelPiece;
		BEGIN
			IF AosTexts.GetLastSelection(text, from, to) THEN
				IF WMDialogs.QueryString("Enter Label", label) = WMDialogs.ResOk THEN
					NEW(lp); lp.label := Utilities.NewString(label);
					text.AcquireWrite;
					a := Utilities.Min(from.GetPosition(), to.GetPosition());
					text.InsertPiece(a, lp);
					text.ReleaseWrite
				END
			END
		END AddLabel;		
		
		PROCEDURE AddHighlight(sender, data : ANY);
		VAR highlight : WMTextView.Highlight;
			hlText : AosTexts.Text;
		BEGIN
(*			hlText := AosTexts.GetLastText();
			highlight := hlText.CreateHighlight();
*)		END AddHighlight;
		
		PROCEDURE RemoveHighlight(sender, data : ANY);
		BEGIN
			
		END RemoveHighlight;	
		
		PROCEDURE Close;
		BEGIN
			IF styleEditor # NIL THEN styleEditor.Close END;
			Close^;
			DecCount
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		VAR data : XML.Element; a : XML.Attribute; n, str: ARRAY 32 OF CHAR;
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS KillerMsg) THEN Close
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					NEW(data);  n := "TextStyleToolData"; data.SetName(n);
					NEW(a); n := "expanded"; a.SetName(n); Utilities.BoolToStr(edit.visible.Get(), str); a.SetValue(str); data.AddAttribute(a);
					x.ext(WMRestorable.Storage).Add("WMTextStyleTool", "WMTextStyleTool.Restore", SELF, data)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;		
		
	END Window;

	(* Graphical User Interface to add AdHoc-Styles *)	
	AdHocStyleWindow* = OBJECT(WMComponents.FormWindow)
	VAR get, apply: WMStandardComponents.Button;
		famEdit, sizeEdit, styleEdit, colorEdit, bgColEdit: WMEditors.Editor;
		styleB, colB, bgColB : WMStandardComponents.Button;
		popup : WMPopups.Popup;
		cStyle : AosTexts.CharacterStyle;
		
		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			label : WMStandardComponents.Label;
			panel : WMStandardComponents.Panel;
			toolbar: WMStandardComponents.Panel;
			manager : WM.WindowManager;
			windowStyle : WM.WindowStyle;
			
			PROCEDURE AB(panel : WMStandardComponents.Panel; btn: WMStandardComponents.Button);
			BEGIN
				btn.alignment.Set(WMComponents.AlignLeft); btn.bounds.SetWidth(60); panel.AddContent(btn)
			END AB;
			
			PROCEDURE AL(panel : WMStandardComponents.Panel; lbl : WMStandardComponents.Label);
			BEGIN
				lbl.alignment.Set(WMComponents.AlignLeft); lbl.bounds.SetWidth(45); label.textColor.Set(0000000FFH);
				lbl.fillColor.Set(windowStyle.bgColor); panel.AddContent(lbl)
			END AL;
			
			PROCEDURE AE(panel : WMStandardComponents.Panel; edtr : WMEditors.Editor);
			BEGIN
				edtr.alignment.Set(WMComponents.AlignClient); edtr.multiLine.Set(FALSE); edtr.fillColor.Set(0FFFFFF88H); edtr.tv.showBorder.Set(TRUE);
				edtr.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1)); edtr.tv.defaultTextBgColor.Set(0FFFFFF88H);
				panel.AddContent(edtr)
			END AE;
			
			PROCEDURE AD(panel : WMStandardComponents.Panel; btn : WMStandardComponents.Button);
			BEGIN
				btn.alignment.Set(WMComponents.AlignRight); btn.bounds.SetWidth(17); panel.AddContent(btn)
			END AD;			

		BEGIN
			NEW(panel); panel.bounds.SetExtents(120, 120); panel.takesFocus.Set(TRUE);
			manager := WM.GetDefaultManager();
			windowStyle := manager.GetStyle();
			
			(* Get/Apply *)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(get); get.caption.SetAOC("Get"); AB(toolbar, get); get.clDefault.Set(088000088H);
			NEW(apply); apply.caption.SetAOC("Apply"); AB(toolbar, apply); apply.clDefault.Set(088000088H);
			
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar); 
			NEW(label); label.caption.SetAOC(" Font:"); AL(toolbar, label);
			NEW(famEdit); famEdit.SetAsString("Oberon"); AE(toolbar, famEdit);
			
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(label); label.caption.SetAOC(" Size:"); AL(toolbar, label);
			NEW(sizeEdit); sizeEdit.SetAsString("10"); AE(toolbar, sizeEdit);
			
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar); 
			NEW(label); label.caption.SetAOC(" Style:"); AL(toolbar, label);
			NEW(styleB); styleB.caption.SetAOC("+"); AD(toolbar, styleB);
			NEW(styleEdit); styleEdit.SetAsString("Regular"); AE(toolbar, styleEdit);
			
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar); 
			NEW(label); label.caption.SetAOC(" Color:"); AL(toolbar, label);
			NEW(colB); colB.caption.SetAOC("+"); AD(toolbar, colB);
			NEW(colorEdit); colorEdit.SetAsString("000000FF"); AE(toolbar, colorEdit);
			
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar); 
			NEW(label); label.caption.SetAOC(" BGCol:"); AL(toolbar, label);
			NEW(bgColB); bgColB.caption.SetAOC("+"); AD(toolbar, bgColB);
			NEW(bgColEdit); bgColEdit.SetAsString("00000000"); AE(toolbar, bgColEdit);					
			
	
			RETURN panel
		END CreateForm;

		PROCEDURE &New;
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			vc := CreateForm();

			get.onClick.Add(GetStyle);
			apply.onClick.Add(SetCustomStyle);
			styleB.SetExtPointerDownHandler(StyleDrop);
			colB.SetExtPointerDownHandler(ColorHandler);
			bgColB.SetExtPointerDownHandler(BGColorHandler);
			
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), TRUE);
			SetContent(vc);

			WM.ExtAddWindow(SELF, 50, 50, {WM.FlagStayOnTop, WM.FlagFrame});
			SetTitle(Utilities.NewString("AdHoc Text Styles"))
		END New;
		
		PROCEDURE GetStyle(sender, data : ANY);
		VAR text : AosTexts.Text; from, to : AosTexts.TextPosition;
			utilreader : AosTexts.TextReader; tempString : ARRAY 256 OF CHAR;
			attr : AosTexts.Attributes;
			a, b, ch, temp : LONGINT;
		BEGIN
			IF AosTexts.GetLastSelection(text, from, to) THEN
				text.AcquireWrite;
				a := Utilities.Min(from.GetPosition(), to.GetPosition());
				b := Utilities.Max(from.GetPosition(), to.GetPosition());
				NEW(utilreader, text);
				utilreader.SetPosition(a);
				utilreader.ReadCh(ch);
				IF utilreader.cstyle = NIL THEN
					famEdit.SetAsString("Oberon");
					sizeEdit.SetAsString("10");
					styleEdit.SetAsString("regular");
					colorEdit.SetAsString("000000FF");
					bgColEdit.SetAsString("00000000");
				ELSE
					cStyle := utilreader.cstyle;
					famEdit.SetAsString(cStyle.family);
					temp := ENTIER(FP1616.FixpToFloat(cStyle.size));
					Utilities.IntToStr(temp, tempString);
					sizeEdit.SetAsString(tempString);
					IF cStyle.style = {} THEN
						styleEdit.SetAsString("Regular");
					ELSIF cStyle.style = {0} THEN
						styleEdit.SetAsString("Bold");					
					ELSIF cStyle.style = {1} THEN
						styleEdit.SetAsString("Italic");			
					ELSIF cStyle.style = {0,1} THEN
						styleEdit.SetAsString("Bold Italic");
					ELSE
						styleEdit.SetAsString("Regular");
					END;
					Utilities.IntToHexStr(cStyle.color, 7, tempString);
					colorEdit.SetAsString(tempString);
					Utilities.IntToHexStr(cStyle.bgColor, 7, tempString);
					bgColEdit.SetAsString(tempString);					
				END; 
				text.ReleaseWrite		
			END;
		END GetStyle;
		
		PROCEDURE SetCustomStyle(sender, data: ANY);
		VAR text : AosTexts.Text;
			from, to : AosTexts.TextPosition;
			utilreader : AosTexts.TextReader;
			cStyle : AosTexts.CharacterStyle;
			a, b, ch : LONGINT;
			style : SET;
			fgColor, bgColor : LONGINT;
			name, string, tempString: ARRAY 256 OF CHAR;
			res, i, size, styleInt: LONGINT;
		BEGIN
			IF AosTexts.GetLastSelection(text, from, to) THEN
				(* create new AdHoc Style *)
				NEW(cStyle);
				famEdit.GetAsString(name);
				COPY(name, cStyle.family);
				sizeEdit.GetAsString(tempString);
				Utilities.StrToInt(tempString, size);
				size := FP1616.FloatToFixp(size);
				cStyle.size := size;
				styleEdit.GetAsString(tempString);
				IF tempString = "Regular" THEN
					style := {}; styleInt := 0
				ELSIF tempString = "Bold" THEN
					style := {0}; styleInt := 1
				ELSIF tempString = "Italic" THEN
					style := {1}; styleInt := 2
				ELSIF tempString = "Bold Italic" THEN
					style := {0, 1}; styleInt := 3
				ELSE
					style := {}; styleInt := 0
				END;
				cStyle.style := style;
				colorEdit.GetAsString(tempString);
				Utilities.HexStrToInt(tempString, fgColor, res);
				cStyle.color := fgColor;
				bgColEdit.GetAsString(tempString);
				Utilities.HexStrToInt(tempString, bgColor, res);
				cStyle.bgColor := bgColor;
				(* create AdHoc Name *)
				COPY("AdHoc", tempString); Utilities.Append(tempString, " ");
				Utilities.Append(tempString, name); Utilities.Append(tempString, " ");
				size := ENTIER(FP1616.FixpToFloat(size));
				Utilities.IntToStr(size, string); Utilities.Append(tempString, string); Utilities.Append(tempString, " ");
				Utilities.IntToStr(styleInt, string); Utilities.Append(tempString, string); Utilities.Append(tempString, " ");
				Utilities.IntToStr(0, string); Utilities.Append(tempString, string); Utilities.Append(tempString, " ");
				Utilities.IntToHexStr(fgColor,7, string); Utilities.Append(tempString, string); Utilities.Append(tempString, " ");
				Utilities.IntToHexStr(bgColor,7, string); Utilities.Append(tempString, string);
				COPY(tempString, cStyle.name);
				AosTexts.AddCharacterStyle(cStyle);
				(* Set the style *)
				text.AcquireWrite;
				a := Utilities.Min(from.GetPosition(), to.GetPosition());
				b := Utilities.Max(from.GetPosition(), to.GetPosition());
				text.SetCharacterStyle(a, b - a, cStyle);			
				text.ReleaseWrite
			END
		END SetCustomStyle;
		
		PROCEDURE StyleDrop(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		BEGIN
			NEW(popup);
			popup.Add("Regular", StylePopupHandler);
			popup.Add("Bold", StylePopupHandler);
			popup.Add("Italic", StylePopupHandler);
			popup.Add("Bold Italic", StylePopupHandler);
			handled := TRUE;

			popup.Popup(bounds.r-100, bounds.t+80);	
		END StyleDrop;

		PROCEDURE StylePopupHandler(sender, data: ANY);
		VAR button: WMStandardComponents.Button;
			tempString: Utilities.String;
		BEGIN
			popup.Close;
			IF sender IS WMStandardComponents.Button THEN
				button := sender(WMStandardComponents.Button);
				tempString := button.caption.Get();
				IF (tempString^ = "Regular") THEN
					styleEdit.SetAsString("Regular");
				ELSIF (tempString^ = "Bold") THEN
					styleEdit.SetAsString("Bold");
				ELSIF (tempString^ = "Italic") THEN
					styleEdit.SetAsString("Italic");
				ELSIF (tempString^ = "Bold Italic") THEN
					styleEdit.SetAsString("Bold Italic");
				ELSE
					styleEdit.SetAsString("Regular");
				END;
			END;	
		END StylePopupHandler;
		
		PROCEDURE ColorHandler(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		VAR result: LONGINT;
			colorString: ARRAY 16 OF CHAR;
			colorPanel : WMPopups.ColorSwatchPopup;
		BEGIN
			NEW(colorPanel);
			colorPanel.onColorChosen := ColorPopupHandler;
			colorPanel.Popup(bounds.r-190, bounds.t+100);

			handled := TRUE;		
		END ColorHandler;
		
		PROCEDURE ColorPopupHandler(result: LONGINT);
		VAR
			colorString: ARRAY 16 OF CHAR;
		BEGIN
			Utilities.IntToHexStr(result, 7, colorString);
			colorEdit.SetAsString(colorString);
		END ColorPopupHandler;
				
		PROCEDURE BGColorHandler(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		VAR result: LONGINT;
			colorString: ARRAY 16 OF CHAR;
			colorPanel: WMPopups.ColorSwatchPopup;
		BEGIN
			NEW(colorPanel);
			colorPanel.onColorChosen := BGColorPopupHandler;
			colorPanel.Popup(bounds.r-190, bounds.t+220);

			handled := TRUE;	
		END BGColorHandler;
		
		PROCEDURE BGColorPopupHandler(result: LONGINT);
		VAR
			colorString: ARRAY 16 OF CHAR;
		BEGIN
			Utilities.IntToHexStr(result, 7, colorString);
			bgColEdit.SetAsString(colorString);
		END BGColorPopupHandler;				
		
		PROCEDURE Close;
		BEGIN
			Close^;
		END Close;	
	
	END AdHocStyleWindow;
	
	(* Graphical User Interface to create & edit Text Styles *)
	StyleEditor* = OBJECT(WMComponents.FormWindow)
	VAR
		shown : BOOLEAN; popup: WMPopups.Popup;
		oldPStyleName, oldCStyleName: ARRAY 256 OF CHAR;
		tabColor, tabSelectedColor : LONGINT;
		previewLabel, fontNotFound : WMStandardComponents.Label;
		tabPanel, buttonPanel, pstylePanel, cstylePanel : WMStandardComponents.Panel;
		pstyleButton, cstyleButton, button : WMStandardComponents.Button;		
		pName, pAlign, pFirstIndent, pLeftIndent, pRightIndent, pSpaceBefore, pSpaceAfter, pDefCharStyle,
		cName, cFont, cSize, cStyle, cBaselineShift, cLeading, cColor, cBackColor, cTracking, cStretchH, cStretchV: WMEditors.Editor;
		pList, cList: WMStringGrids.StringGrid;

		UpdateProc* : PROCEDURE {DELEGATE};

		currentPStyle, tempPStyle : AosTexts.ParagraphStyle;
		currentCStyle, tempCStyle : AosTexts.CharacterStyle;		
		pStyles: AosTexts.ParagraphStyleArray;
		cStyles: AosTexts.CharacterStyleArray;
		
		vc : WMComponents.VisualComponent;
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR panel, mainPanel, gridPanel, propertyPanel : WMStandardComponents.Panel;
			groupPanel : WMStandardComponents.GroupPanel;
			editor: WMEditors.Editor;
			label : WMStandardComponents.Label;
			labelWidth : LONGINT;
			resizerH: WMStandardComponents.Resizer;
			manager : WM.WindowManager;
			windowStyle : WM.WindowStyle;
			
			check: WMStandardComponents.Checkbox;
			
			PROCEDURE CreateEditor(): WMEditors.Editor;
			VAR editor: WMEditors.Editor;
			BEGIN
				NEW(editor); editor.alignment.Set(WMComponents.AlignClient);
				editor.multiLine.Set(FALSE); editor.fillColor.Set(0FFFFFFFFH); editor.tv.showBorder.Set(TRUE);
				editor.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1)); editor.onEnter.Add(UpdateValueHandler);
				RETURN editor
			END CreateEditor;
			
			PROCEDURE CreateLabel(caption : ARRAY OF CHAR): WMStandardComponents.Label;
			VAR label: WMStandardComponents.Label;
			BEGIN
				NEW(label); label.bounds.SetWidth(labelWidth); label.caption.SetAOC(caption);
				label.alignment.Set(WMComponents.AlignLeft);
				RETURN label
			END CreateLabel;
			
		BEGIN
			labelWidth := 130;
			tabColor := 0008000FFH;
			tabSelectedColor := 000CC00FFH;
			manager := WM.GetDefaultManager();
			windowStyle := manager.GetStyle();			
		
			NEW(mainPanel); mainPanel.bounds.SetExtents(500, 420); mainPanel.fillColor.Set(windowStyle.bgColor);
			mainPanel.takesFocus.Set(TRUE);
			
			(* -- tabs -- *)
			NEW(tabPanel); tabPanel.bounds.SetHeight(20); tabPanel.fillColor.Set(0CCCCCCFFH);
			tabPanel.alignment.Set(WMComponents.AlignTop);
			NEW(pstyleButton); pstyleButton.caption.SetAOC("Paragraph"); pstyleButton.alignment.Set(WMComponents.AlignLeft);
			pstyleButton.onClick.Add(TabHandler); pstyleButton.clDefault.Set(tabSelectedColor);
			NEW(cstyleButton); cstyleButton.caption.SetAOC("Character"); cstyleButton.alignment.Set(WMComponents.AlignLeft); 
			cstyleButton.onClick.Add(TabHandler); cstyleButton.clDefault.Set(tabColor);
			(* tabPanel.AddContent(pstyleButton); *)
			(* tabPanel.AddContent(cstyleButton); *)
			mainPanel.AddContent(tabPanel);
			
			(* -- paragraph style -- *)
			NEW(pstylePanel); pstylePanel.alignment.Set(WMComponents.AlignClient);
			pstylePanel.visible.Set(FALSE);
			mainPanel.AddContent(pstylePanel);
			NEW(gridPanel); gridPanel.alignment.Set(WMComponents.AlignClient);
			gridPanel.fillColor.Set(0FFFFFFFFH);
			NEW(pList); pList.alignment.Set(WMComponents.AlignClient);
			pList.onClick.Add(PClickSelected);
			pList.model.Acquire;
			pList.model.SetNofCols(1);
			pList.model.SetNofRows(1);
			pList.SetSelectionMode(WMGrids.GridSelectSingleRow);
			pList.model.Release;
			gridPanel.AddContent(pList);
			pstylePanel.AddContent(gridPanel);
			NEW(propertyPanel); propertyPanel.alignment.Set(WMComponents.AlignClient);
			pstylePanel.AddContent(propertyPanel);
			
			NEW(label); label.bounds.SetHeight(13); label.alignment.Set(WMComponents.AlignTop);
			propertyPanel.AddContent(label);
			
			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Paragraph Style Name:"); panel.AddContent(label);
			pName := CreateEditor(); panel.AddContent(pName);
			propertyPanel.AddContent(panel);	
			
			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Alignment:"); panel.AddContent(label);
			NEW(button); button.caption.SetAOC("+"); button.alignment.Set(WMComponents.AlignRight);
			button.SetExtPointerDownHandler(AlignHandler); button.bounds.SetWidth(20); panel.AddContent(button);
			pAlign := CreateEditor(); panel.AddContent(pAlign);
			propertyPanel.AddContent(panel);	
	
			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" First Line Indent:"); panel.AddContent(label);
			pFirstIndent := CreateEditor(); panel.AddContent(pFirstIndent);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Left Line Indent:"); panel.AddContent(label);
			pLeftIndent := CreateEditor(); panel.AddContent(pLeftIndent);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Right Line Indent:"); panel.AddContent(label);
			pRightIndent := CreateEditor(); panel.AddContent(pRightIndent);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Space Before:"); panel.AddContent(label);
			pSpaceBefore := CreateEditor(); panel.AddContent(pSpaceBefore);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Space After:"); panel.AddContent(label);
			pSpaceAfter := CreateEditor(); panel.AddContent(pSpaceAfter);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Default Char Style:"); panel.AddContent(label);
			pSpaceAfter := CreateEditor(); panel.AddContent(pSpaceAfter);
			propertyPanel.AddContent(panel);	
	
			(* -- paragraph panel buttons -- *)
			NEW(buttonPanel); buttonPanel.bounds.SetHeight(20); buttonPanel.fillColor.Set(08888FFFFH);
			buttonPanel.alignment.Set(WMComponents.AlignBottom);

			NEW(button); button.caption.SetAOC("Apply"); button.alignment.Set(WMComponents.AlignRight);
			button.onClick.Add(ApplyPHandler);
			buttonPanel.AddContent(button);
			
			NEW(button); button.caption.SetAOC("Delete"); button.alignment.Set(WMComponents.AlignRight);
			button.onClick.Add(RemovePHandler);
			buttonPanel.AddContent(button);			

			NEW(button); button.caption.SetAOC("Import"); button.alignment.Set(WMComponents.AlignRight);
			button.onClick.Add(ImportPHandler);
			buttonPanel.AddContent(button);

			NEW(button); button.caption.SetAOC("New"); button.alignment.Set(WMComponents.AlignRight);
			button.onClick.Add(NewPHandler);
			buttonPanel.AddContent(button);
								
			propertyPanel.AddContent(buttonPanel);			


			(* -- character style -- *)
			NEW(cstylePanel); cstylePanel.alignment.Set(WMComponents.AlignClient);
			cstylePanel.visible.Set(TRUE);
			mainPanel.AddContent(cstylePanel);
			NEW(gridPanel); gridPanel.bounds.SetWidth(200); gridPanel.alignment.Set(WMComponents.AlignLeft);
			gridPanel.fillColor.Set(0FFFFFFFFH);
			NEW(cList); cList.alignment.Set(WMComponents.AlignClient);
			cList.onClick.Add(CClickSelected);
			cList.model.Acquire;
			cList.model.SetNofCols(1);
			cList.model.SetNofRows(1);
			cList.SetSelectionMode(WMGrids.GridSelectSingleRow);
			cList.model.Release;
			NEW(resizerH); resizerH.alignment.Set(WMComponents.AlignRight);
			resizerH.bounds.SetWidth(4);
			gridPanel.AddContent(resizerH);
			gridPanel.AddContent(cList);			
			cstylePanel.AddContent(gridPanel);

			NEW(propertyPanel); propertyPanel.alignment.Set(WMComponents.AlignClient);
			cstylePanel.AddContent(propertyPanel);
		
			NEW(label); label.bounds.SetHeight(13); label.alignment.Set(WMComponents.AlignTop);
			propertyPanel.AddContent(label);

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Character Style Name:"); panel.AddContent(label);
			cName := CreateEditor(); panel.AddContent(cName);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Font Name:"); panel.AddContent(label);
			cFont := CreateEditor(); panel.AddContent(cFont);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Font Style:"); panel.AddContent(label);
			NEW(button); button.caption.SetAOC("+"); button.alignment.Set(WMComponents.AlignRight);
			button.SetExtPointerDownHandler(StyleHandler); button.bounds.SetWidth(20); panel.AddContent(button);
			cStyle := CreateEditor(); panel.AddContent(cStyle);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Font Size:"); panel.AddContent(label);
			cSize := CreateEditor(); panel.AddContent(cSize);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Leading:"); panel.AddContent(label);
			cLeading := CreateEditor(); panel.AddContent(cLeading);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Baseline Shift:"); panel.AddContent(label);
			cBaselineShift := CreateEditor(); panel.AddContent(cBaselineShift);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Font Color:"); panel.AddContent(label);
			NEW(button); button.caption.SetAOC("+"); button.alignment.Set(WMComponents.AlignRight);
			button.SetExtPointerDownHandler(ColorHandler); button.bounds.SetWidth(20); panel.AddContent(button);
			cColor := CreateEditor(); panel.AddContent(cColor);
			propertyPanel.AddContent(panel);	

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Font BG Color:"); panel.AddContent(label);
			NEW(button); button.caption.SetAOC("+"); button.alignment.Set(WMComponents.AlignRight);
			button.SetExtPointerDownHandler(BGColorHandler); button.bounds.SetWidth(20); panel.AddContent(button);
			cBackColor := CreateEditor(); panel.AddContent(cBackColor);
			propertyPanel.AddContent(panel);

	(* --- not used yet ---> 	*)
			
			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Tracking:"); panel.AddContent(label);
			cTracking := CreateEditor(); panel.AddContent(cTracking);
			(* propertyPanel.AddContent(panel);	*)		
			
			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Stretch Horizontal:"); panel.AddContent(label);
			cStretchH := CreateEditor(); panel.AddContent(cStretchH);
			(* propertyPanel.AddContent(panel);	*)		
			
			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			label := CreateLabel(" Stretch Vertical:"); panel.AddContent(label);
			cStretchV := CreateEditor(); panel.AddContent(cStretchV);
			(* propertyPanel.AddContent(panel);	*)						
			
	(* 		<---------------- *)
				
			(* preview panel *)
			NEW(panel); panel.bounds.SetHeight(15); panel.alignment.Set(WMComponents.AlignTop); propertyPanel.AddContent(panel);
			NEW(groupPanel); groupPanel.alignment.Set(WMComponents.AlignTop); groupPanel.caption.SetAOC("Preview:"); groupPanel.bounds.SetHeight(80);
			NEW(previewLabel); previewLabel.fillColor.Set(0FFFFFFFFH); previewLabel.alignment.Set(WMComponents.AlignClient);
			previewLabel.caption.SetAOC("The quick brown Fox jumped over the lazy Dog"); previewLabel.alignH.Set(1); previewLabel.alignV.Set(1);
			groupPanel.AddContent(previewLabel); propertyPanel.AddContent(groupPanel);
			NEW(fontNotFound); fontNotFound.bounds.SetHeight(20); fontNotFound.alignment.Set(WMComponents.AlignTop);
			fontNotFound.caption.SetAOC("  ERROR: Font not found! - using DefaultFont"); fontNotFound.visible.Set(FALSE);
			propertyPanel.AddContent(fontNotFound); fontNotFound.textColor.Set(0FF0000FFH);					
			
			(* -- character style buttons -- *)																											
			NEW(buttonPanel); buttonPanel.bounds.SetHeight(20); buttonPanel.fillColor.Set(windowStyle.bgColor);
			buttonPanel.alignment.Set(WMComponents.AlignBottom);

			NEW(button); button.caption.SetAOC("Apply"); button.alignment.Set(WMComponents.AlignRight);
			button.onClick.Add(ApplyCHandler);
			buttonPanel.AddContent(button);					

			NEW(button); button.caption.SetAOC("Delete"); button.alignment.Set(WMComponents.AlignRight);
			button.onClick.Add(RemoveCHandler);
			buttonPanel.AddContent(button);
			
			NEW(button); button.caption.SetAOC("Export"); button.alignment.Set(WMComponents.AlignRight);
			button.onClick.Add(ExportCHandler);
			buttonPanel.AddContent(button);

			NEW(button); button.caption.SetAOC("Import"); button.alignment.Set(WMComponents.AlignRight);
			button.onClick.Add(ImportCHandler);
			buttonPanel.AddContent(button);			

			NEW(button); button.caption.SetAOC("New"); button.alignment.Set(WMComponents.AlignRight);
			button.onClick.Add(NewCHandler);
			buttonPanel.AddContent(button);

			propertyPanel.AddContent(buttonPanel);	
			
			RETURN mainPanel;
		END CreateForm;
		
		PROCEDURE &New;
		VAR 
		BEGIN
			vc := CreateForm();
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Style Editor"));
			
			pStyles := AosTexts.GetParagraphStyleArray();
			cStyles := AosTexts.GetCharacterStyleArray();				
		END New;

		PROCEDURE Show*(x, y: LONGINT);
		BEGIN
			LoadStyleList;
			IF ~shown THEN	shown := TRUE;
			ELSE Hide; shown := TRUE; END;
			manager := WM.GetDefaultManager();
			WM.ExtAddWindow(SELF, x, y, {WM.FlagFrame});	
			manager.SetFocus(SELF);
			cList.SetSelection(0,0,0,0)
		END Show;
		
		PROCEDURE Hide*;
		BEGIN
			IF shown THEN
				shown := FALSE;
				manager := WM.GetDefaultManager();
				manager.Remove(SELF);
			END;
		END Hide;
		
		PROCEDURE Close*;
		BEGIN
			Close^;
			IF UpdateProc # NIL THEN UpdateProc END;
			shown := FALSE;
		END Close;
		
		PROCEDURE LoadStyleList;
		VAR i : LONGINT;
		BEGIN
			vc.Acquire;
			pList.model.Acquire;
			i := 0;
			WHILE ((i<LEN(pStyles))  & (pStyles[i] # NIL)) DO
				pList.model.SetNofRows(i+1);
				pList.model.SetCellText(0, i, Utilities.NewString(pStyles[i].name));
				pList.model.SetCellData(0, i, pStyles[i]);
				INC(i);
			END;
			pList.model.Release;	
									
			cList.model.Acquire;
			i := 0;
			WHILE ((i<LEN(cStyles))  & (cStyles[i] # NIL)) DO
				cList.model.SetNofRows(i+1);
				cList.model.SetCellText(0, i, Utilities.NewString(cStyles[i].name));
				cList.model.SetCellData(0, i, cStyles[i]);
				INC(i);
			END;
			IF i >  0 THEN CClickSelected(NIL, cList.model.GetCellData(0, 0)); END;
			cList.model.Release;
			vc.Release;			
			
		END LoadStyleList;
		
		PROCEDURE TabHandler(sender, data: ANY);
		BEGIN
			IF (sender # NIL) & (sender IS WMStandardComponents.Button) THEN
				IF sender = pstyleButton THEN
					cstylePanel.visible.Set(FALSE); cstyleButton.clDefault.Set(tabColor);
					pstylePanel.visible.Set(TRUE); pstyleButton.clDefault.Set(tabSelectedColor);
				ELSIF sender = cstyleButton THEN
					pstylePanel.visible.Set(FALSE); pstyleButton.clDefault.Set(tabColor);
					cstylePanel.visible.Set(TRUE); cstyleButton.clDefault.Set(tabSelectedColor);					
				ELSE
				
				END;
			END;
		END TabHandler;
		
		PROCEDURE PClickSelected(sender, data: ANY);
		VAR tempString: ARRAY 64 OF CHAR;
		BEGIN
			IF (data # NIL) THEN
				currentPStyle := data(AosTexts.ParagraphStyle);
				tempPStyle := currentPStyle.Clone();
				pName.SetAsString(currentPStyle.name);
				IF (currentPStyle.alignment = 0) THEN tempString := "Left";
				ELSIF (currentPStyle.alignment = 1) THEN tempString := "Center";
				ELSIF (currentPStyle.alignment = 2) THEN tempString := "Right";
				ELSE tempString := "Justified";
				END;
				pAlign.SetAsString(tempString);
				Utilities.FloatToStr(currentPStyle.firstIndent, 0,4,0, tempString);
				pFirstIndent.SetAsString(tempString);
				Utilities.FloatToStr(currentPStyle.leftIndent, 0,4,0, tempString);
				pLeftIndent.SetAsString(tempString);
				Utilities.FloatToStr(currentPStyle.rightIndent, 0,4,0, tempString);
				pRightIndent.SetAsString(tempString);
				Utilities.FloatToStr(currentPStyle.spaceBefore, 0,4,0, tempString);
				pSpaceBefore.SetAsString(tempString);
				Utilities.FloatToStr(currentPStyle.spaceAfter, 0,4,0, tempString);
				pSpaceAfter.SetAsString(tempString);
				pDefCharStyle.SetAsString(currentPStyle.charStyle.name);
				COPY(currentPStyle.name, oldPStyleName);
			END;
		END PClickSelected;
		
		PROCEDURE CClickSelected(sender, data: ANY);
		VAR tempString: ARRAY 64 OF CHAR;
			tempFont: WMGraphics.Font;
		BEGIN
			IF (data # NIL) THEN
				currentCStyle := data(AosTexts.CharacterStyle);
				tempCStyle := currentCStyle.Clone();
				cName.SetAsString(currentCStyle.name);
				cFont.SetAsString(currentCStyle.family);
				IF (currentCStyle.style * {0, 1} = {}) THEN
					 tempString := "Regular";
				ELSIF (currentCStyle.style * {0, 1} = {0}) THEN
					tempString := "Bold";
				ELSIF (currentCStyle.style * {0, 1} = {1}) THEN
					tempString := "Italic";
				ELSE
					tempString := "Bold Italic";
				END;
				cStyle.SetAsString(tempString);
				Utilities.FloatToStr(FP1616.FixpToFloat(currentCStyle.size), 0,4,0, tempString);
				cSize.SetAsString(tempString);
				Utilities.FloatToStr(FP1616.FixpToFloat(currentCStyle.leading), 0,4,0, tempString);
				cLeading.SetAsString(tempString);
				Utilities.FloatToStr(currentCStyle.baselineShift, 0,4,0, tempString);
				cBaselineShift.SetAsString(tempString);
				Utilities.IntToHexStr(currentCStyle.color, 7, tempString);
				cColor.SetAsString(tempString);
				Utilities.IntToHexStr(currentCStyle.bgColor, 7, tempString);								
				cBackColor.SetAsString(tempString);
				Utilities.FloatToStr(FP1616.FixpToFloat(currentCStyle.tracking), 0,4,0, tempString);
				cTracking.SetAsString(tempString);
				Utilities.FloatToStr(FP1616.FixpToFloat(currentCStyle.scaleHorizontal), 0,4,0, tempString);
				cStretchH.SetAsString(tempString);
				Utilities.FloatToStr(FP1616.FixpToFloat(currentCStyle.scaleVertical), 0,4,0, tempString);
				cStretchV.SetAsString(tempString);
				COPY(currentCStyle.name, oldCStyleName);

				(* update preview *)
				tempFont := WMGraphics.GetFont(tempCStyle.family, ENTIER(FP1616.FixpToFloat(tempCStyle.size)), tempCStyle.style);
				previewLabel.SetFont(tempFont); previewLabel.fillColor.Set(tempCStyle.bgColor);
				previewLabel.textColor.Set(tempCStyle.color); previewLabel.Invalidate;
			END;
		END CClickSelected;	
		
		PROCEDURE UpdateValueHandler(sender, data: ANY);
		VAR tempString : ARRAY 64 OF CHAR;
			tempLReal : LONGREAL;
			tempInt, res : LONGINT;
			tempCharStyle : AosTexts.CharacterStyle;
			tempFont : WMGraphics.Font;
			tempEditor : WMEditors.Editor;
		BEGIN
			(* paragraph style *)
			IF sender IS WMEditors.Editor THEN
				tempEditor := sender(WMEditors.Editor);
				tempEditor.GetAsString(tempString);
			END;
			
			IF (tempEditor = pName) THEN
				COPY(tempString, tempPStyle.name);
			ELSIF (tempEditor = pAlign) THEN
				Utilities.LowerCase(tempString);
				IF (tempString = "left") THEN tempPStyle.alignment := 0; pAlign.SetAsString("Left");
				ELSIF (tempString = "center") THEN tempPStyle.alignment := 1; pAlign.SetAsString("Center");	
				ELSIF (tempString = "right") THEN tempPStyle.alignment := 2; pAlign.SetAsString("Right");								
				ELSIF (tempString = "justified") THEN tempPStyle.alignment := 3; pAlign.SetAsString("Justified");
				ELSE tempPStyle.alignment := 0; pAlign.SetAsString("Left"); END;
			ELSIF (tempEditor = pFirstIndent) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempPStyle.firstIndent := FP1616.FloatToFixp(SHORT(tempLReal));
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				pFirstIndent.SetAsString(tempString);
			ELSIF (tempEditor = pLeftIndent) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempPStyle.leftIndent := FP1616.FloatToFixp(SHORT(tempLReal));	
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				pLeftIndent.SetAsString(tempString);						
			ELSIF (tempEditor = pRightIndent) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempPStyle.rightIndent := FP1616.FloatToFixp(SHORT(tempLReal));
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				pRightIndent.SetAsString(tempString);
			ELSIF (tempEditor = pSpaceBefore) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempPStyle.spaceBefore := FP1616.FloatToFixp(SHORT(tempLReal));
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				pSpaceBefore.SetAsString(tempString);
			ELSIF (tempEditor = pSpaceAfter) THEN		
				Utilities.StrToFloat(tempString, tempLReal);
				tempPStyle.spaceAfter := FP1616.FloatToFixp(SHORT(tempLReal));				
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				pSpaceAfter.SetAsString(tempString);
			ELSIF (tempEditor = pDefCharStyle) THEN
				tempCharStyle := AosTexts.GetCharacterStyleByName(tempString);
				IF tempCharStyle # NIL THEN
					tempPStyle.charStyle := tempCharStyle;
				ELSE
					tempPStyle.charStyle := AosTexts.GetCharacterStyleByName("Normal");
					pDefCharStyle.SetAsString(tempPStyle.charStyle.name);
				END;
			
			(* character style *)
			ELSIF (tempEditor = cName) THEN
				COPY(tempString, tempCStyle.name);
			ELSIF (tempEditor = cFont) THEN
				COPY(tempString, tempCStyle.family);
				(* load font *)
				tempFont := WMGraphics.GetFont(tempCStyle.family, ENTIER(FP1616.FixpToFloat(tempCStyle.size)), tempCStyle.style);
				previewLabel.SetFont(tempFont); previewLabel.Invalidate;
				IF (tempFont.name # tempCStyle.family) OR (tempFont.size # ENTIER(FP1616.FixpToFloat(tempCStyle.size))) THEN (* OR (tempFont.style # tempCStyle.style) *)
					fontNotFound.visible.Set(TRUE);
				ELSE
					fontNotFound.visible.Set(FALSE);
				END;				
			ELSIF (tempEditor = cStyle) THEN
				Utilities.LowerCase(tempString);
				IF (tempString = "regular") THEN tempCStyle.style := {}; cStyle.SetAsString("Regular");
				ELSIF (tempString = "bold") THEN tempCStyle.style := {0}; cStyle.SetAsString("Bold");
				ELSIF (tempString = "italic") THEN tempCStyle.style := {1}; cStyle.SetAsString("Italic");
				ELSIF (tempString = "bold italic") THEN tempCStyle.style := {0, 1}; cStyle.SetAsString("Bold Italic");
				ELSE tempCStyle.style := {}; cStyle.SetAsString("Regular"); END;
				tempFont := WMGraphics.GetFont(tempCStyle.family, ENTIER(FP1616.FixpToFloat(tempCStyle.size)), tempCStyle.style);
				previewLabel.SetFont(tempFont); previewLabel.Invalidate;				
				IF (tempFont.name # tempCStyle.family) OR (tempFont.size # ENTIER(FP1616.FixpToFloat(tempCStyle.size))) THEN
					fontNotFound.visible.Set(TRUE);
				ELSE
					fontNotFound.visible.Set(FALSE);
				END;
			ELSIF (tempEditor = cSize) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempCStyle.size := FP1616.FloatToFixp(SHORT(tempLReal));				
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				cSize.SetAsString(tempString);
				(* set leading to 120% of size *)
				tempLReal := tempLReal*1.2;
				tempCStyle.leading := FP1616.FloatToFixp(SHORT(SHORT(tempLReal)));
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				cLeading.SetAsString(tempString);
				tempFont := WMGraphics.GetFont(tempCStyle.family, ENTIER(FP1616.FixpToFloat(tempCStyle.size)), tempCStyle.style);
				previewLabel.SetFont(tempFont); previewLabel.Invalidate;											
				IF (tempFont.name # tempCStyle.family) OR (tempFont.size # ENTIER(FP1616.FixpToFloat(tempCStyle.size))) THEN
					fontNotFound.visible.Set(TRUE);
				ELSE
					fontNotFound.visible.Set(FALSE);
				END;
			ELSIF (tempEditor = cLeading) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempCStyle.leading := FP1616.FloatToFixp(SHORT(tempLReal));				
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				cLeading.SetAsString(tempString);										
			ELSIF (tempEditor = cBaselineShift) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempCStyle.baselineShift := FP1616.FloatToFixp(SHORT(tempLReal));				
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				cBaselineShift.SetAsString(tempString);					
			ELSIF (tempEditor = cColor) THEN
				Utilities.HexStrToInt(tempString, tempInt, res);
				tempCStyle.color := tempInt;
				Utilities.IntToHexStr(tempInt, 7, tempString);
				cColor.SetAsString(tempString);
				previewLabel.textColor.Set(tempInt); previewLabel.Invalidate;
			ELSIF (tempEditor = cBackColor) THEN
				Utilities.HexStrToInt(tempString, tempInt, res);
				tempCStyle.bgColor := tempInt;
				Utilities.IntToHexStr(tempInt, 7, tempString);
				cBackColor.SetAsString(tempString);	
				previewLabel.fillColor.Set(tempInt); previewLabel.Invalidate;
			ELSIF (tempEditor = cTracking) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempCStyle.tracking := FP1616.FloatToFixp(SHORT(tempLReal));				
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				cTracking.SetAsString(tempString);					
			ELSIF (tempEditor = cStretchH) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempCStyle.scaleHorizontal := FP1616.FloatToFixp(SHORT(tempLReal));				
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				cStretchH.SetAsString(tempString);					
			ELSIF (tempEditor = cStretchV) THEN
				Utilities.StrToFloat(tempString, tempLReal);
				tempCStyle.scaleVertical := FP1616.FloatToFixp(SHORT(tempLReal));				
				Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
				cStretchV.SetAsString(tempString);																
			ELSE
			END;
		END UpdateValueHandler;
		
		PROCEDURE UpdateList;
		VAR i : LONGINT;
		BEGIN
			pList.model.Acquire;
			i := 0;
			WHILE ((i<LEN(pStyles))  & (pStyles[i] # NIL)) DO
				pList.model.SetNofRows(i+1);
				pList.model.SetCellText(0, i, Utilities.NewString(pStyles[i].name));
				pList.model.SetCellData(0, i, pStyles[i]);
				INC(i);
			END;
			pList.model.Release;	
									
			cList.model.Acquire;
			i := 0;
			WHILE ((i<LEN(cStyles))  & (cStyles[i] # NIL)) DO
				cList.model.SetNofRows(i+1);
				cList.model.SetCellText(0, i, Utilities.NewString(cStyles[i].name));
				cList.model.SetCellData(0, i, cStyles[i]);
				INC(i);
			END;
			cList.model.Release;		
			UpdateProc;
			SendUpdateMsg;
					
		END UpdateList;
		
		PROCEDURE SendUpdateMsg;
		VAR changed : AosTexts.StyleChangedMsg;
			 msg : WMMessages.Message;
			 m : WM.WindowManager;
		BEGIN
			NEW(changed); msg.ext := changed; msg.msgType := WMMessages.MsgExt;
			m := WM.GetDefaultManager();
			m.Broadcast(msg);
		END SendUpdateMsg;
		
		PROCEDURE NewPHandler(sender, data: ANY);
		VAR newPStyle: AosTexts.ParagraphStyle;
			tempString: ARRAY 256 OF CHAR;	
		BEGIN
			NEW(newPStyle);
			tempString := "newParagraphStyle";
			WHILE AosTexts.GetParagraphStyleByName(tempString) # NIL DO
				Utilities.Append(tempString, "Copy");
			END;
			Utilities.Append(newPStyle.name, tempString);		
			newPStyle.alignment := 0;						(* Left Align *)
			newPStyle.spaceBefore := 0;			
			newPStyle.spaceAfter := 0;
			newPStyle.leftIndent := 0;
			newPStyle.rightIndent := 0;	
			newPStyle.firstIndent := 0;	
			newPStyle.charStyle := AosTexts.GetCharacterStyleByName("Normal");
			UpdateList;	
		END NewPHandler;
		
		PROCEDURE ImportPHandler(sender, data: ANY);
		VAR filename: ARRAY 128 OF CHAR;
		BEGIN
			filename := "";
			IF WMDialogs.QueryString("Import Paragraph Styles from File:", filename) = WMDialogs.ResOk THEN
				ImportParagraphStyles(filename);
			END;		
			UpdateList;
		END ImportPHandler;
		
		PROCEDURE ImportParagraphStyles(filename: ARRAY OF CHAR);
		VAR tempString : ARRAY 256 OF CHAR;
			tempReal : LONGREAL;
			reader : AosFS.Reader;
			parser : XMLParser.Parser;
			scanner : XMLScanner.Scanner;
			f : AosFS.File;
			XMLdocStyle : XML.Document;
			root: XML.Element;
			cont: XMLObjects.Enumerator;
			ptr: ANY;
			str: Utilities.String;
			pStyle: AosTexts.ParagraphStyle;
			cStyle: AosTexts.CharacterStyle;
		BEGIN
			COPY(filename, tempString);
			Utilities.Append(tempString, ".XML");
			f := AosFS.Old(tempString);
			IF f = NIL THEN RETURN END;
			NEW(reader, f, 0);		
			NEW(scanner, reader);
			NEW(parser, scanner);
			XMLdocStyle := parser.Parse();
			
			root := XMLdocStyle.GetRoot();
			cont := root.GetContents(); cont.Reset();
			WHILE cont.HasMoreElements() DO
				ptr := cont.GetNext();
				IF ptr IS XML.Element THEN 
					str := ptr(XML.Element).GetName();

					IF (str # NIL) & (str^ = "paragraph-style") THEN				(* paragraph styles *)
						NEW(pStyle);
						str := ptr(XML.Element).GetAttributeValue("name"); IF str # NIL THEN COPY(str^, pStyle.name) END;
						str := ptr(XML.Element).GetAttributeValue("alignment"); IF str # NIL THEN Utilities.StrToInt(str^, pStyle.alignment) END;
						str := ptr(XML.Element).GetAttributeValue("first-indent"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); pStyle.firstIndent := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("left-indent"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); pStyle.leftIndent := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("right-indent"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); pStyle.rightIndent := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("space-before"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); pStyle.spaceBefore := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("space-after"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); pStyle.spaceAfter := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("character-style"); 
						IF str # NIL THEN
							cStyle := AosTexts.GetCharacterStyleByName(str^);
							IF cStyle # NIL THEN pStyle.charStyle := cStyle; END;
						END;
						AosTexts.AddParagraphStyle(pStyle);
					END;
				END;	
			END;
			
		END ImportParagraphStyles;	
		
		PROCEDURE RemovePHandler(sender, data: ANY);
		BEGIN
			AosTexts.RemoveParagraphStyle(currentPStyle);
			UpdateList;
		END RemovePHandler;
		
		PROCEDURE ApplyPHandler(sender, data: ANY);
		VAR tempString : ARRAY 256 OF CHAR;
			tempLReal: LONGREAL;
			tempInt, res : LONGINT;
			tempCharStyle : AosTexts.CharacterStyle;
			oldPName : ARRAY 256 OF CHAR;
		BEGIN
			(* retrieve tempvalues first.. *)
			pName.GetAsString(tempString);
			COPY(tempString, tempPStyle.name);
			pAlign.GetAsString(tempString); Utilities.LowerCase(tempString);
			IF (tempString = "left") THEN tempPStyle.alignment := 0; pAlign.SetAsString("Left");
			ELSIF (tempString = "center") THEN tempPStyle.alignment := 1; pAlign.SetAsString("Center");	
			ELSIF (tempString = "right") THEN tempPStyle.alignment := 2;	pAlign.SetAsString("Right");								
			ELSIF (tempString = "justified") THEN tempPStyle.alignment := 3; pAlign.SetAsString("Justified");
			ELSE tempPStyle.alignment := 0; pAlign.SetAsString("Left"); END;
			pFirstIndent.GetAsString(tempString);
			Utilities.StrToFloat(tempString, tempLReal);
			tempPStyle.firstIndent := FP1616.FloatToFixp(SHORT(tempLReal));
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			pFirstIndent.SetAsString(tempString);
			pLeftIndent.GetAsString(tempString);
			Utilities.StrToFloat(tempString, tempLReal);
			tempPStyle.leftIndent := FP1616.FloatToFixp(SHORT(tempLReal));	
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			pLeftIndent.SetAsString(tempString);						
			pRightIndent.GetAsString(tempString);
			Utilities.StrToFloat(tempString, tempLReal);
			tempPStyle.rightIndent := FP1616.FloatToFixp(SHORT(tempLReal));
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			pRightIndent.SetAsString(tempString);
			pSpaceBefore.GetAsString(tempString);
			Utilities.StrToFloat(tempString, tempLReal);
			tempPStyle.spaceBefore := FP1616.FloatToFixp(SHORT(tempLReal));
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			pSpaceBefore.SetAsString(tempString);
			pSpaceAfter.GetAsString(tempString);			
			Utilities.StrToFloat(tempString, tempLReal);
			tempPStyle.spaceAfter := FP1616.FloatToFixp(SHORT(tempLReal));				
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			pSpaceAfter.SetAsString(tempString);
			pDefCharStyle.GetAsString(tempString);
			tempCharStyle := AosTexts.GetCharacterStyleByName(tempString);
			IF tempCharStyle # NIL THEN
				tempPStyle.charStyle := tempCharStyle;
			ELSE
				tempPStyle.charStyle := AosTexts.GetCharacterStyleByName("Normal");
				pDefCharStyle.SetAsString(tempPStyle.charStyle.name);
			END;
		
			(* update currentStyle with temp, refresh list *)
			currentPStyle.name := tempPStyle.name;
			currentPStyle.alignment := tempPStyle.alignment;
			currentPStyle.firstIndent := tempPStyle.firstIndent;
			currentPStyle.leftIndent := tempPStyle.leftIndent;
			currentPStyle.rightIndent := tempPStyle.rightIndent;
			currentPStyle.spaceBefore := tempPStyle.spaceBefore;
			currentPStyle.spaceAfter := tempPStyle.spaceAfter;
			currentPStyle.charStyle := tempPStyle.charStyle;			
			UpdateList;		
		END ApplyPHandler;	
		
		PROCEDURE NewCHandler(sender, data: ANY);
		VAR newCStyle: AosTexts.CharacterStyle; 
			name : ARRAY 256 OF CHAR;
		BEGIN
			NEW(newCStyle);
			IF (currentCStyle # NIL) & (currentCStyle.name # "") THEN
				COPY(currentCStyle.name, name);
			ELSE
				COPY("NewCharacterStyle", name);
			END;
			WHILE AosTexts.GetCharacterStyleByName(name) # NIL DO
				Utilities.Append(name, "Copy");
			END;
			COPY(name, newCStyle.name);

			IF currentCStyle = NIL THEN			
				newCStyle.family := "Oberon";
				newCStyle.style := {};
				newCStyle.size := FP1616.FloatToFixp(12.0);
				newCStyle.leading := FP1616.FloatToFixp(14.0);
				newCStyle.baselineShift := 0;
				newCStyle.tracking := 0;
				newCStyle.scaleHorizontal := FP1616.FloatToFixp(100.0);
				newCStyle.scaleVertical := FP1616.FloatToFixp(100.0);
				newCStyle.color := 0000000FFH;
				newCStyle.bgColor := 0FFFFFF00H;
			ELSE
				(* copy selected style *)
				COPY(currentCStyle.family, newCStyle.family);
				newCStyle.style := currentCStyle.style;
				newCStyle.size := currentCStyle.size;
				newCStyle.leading := currentCStyle.leading;
				newCStyle.baselineShift := currentCStyle.baselineShift;
				newCStyle.tracking := currentCStyle.tracking;
				newCStyle.scaleHorizontal := currentCStyle.scaleHorizontal;
				newCStyle.scaleVertical := currentCStyle.scaleVertical;
				newCStyle.color := currentCStyle.color;
				newCStyle.bgColor := currentCStyle.bgColor;
			END;		
						
			AosTexts.AddCharacterStyle(newCStyle);
			UpdateList;
		END NewCHandler;
		
		PROCEDURE ExportCHandler(sender, data: ANY);
		VAR filename: ARRAY 128 OF CHAR;
		BEGIN
			filename := "UserTextStyles";
			IF WMDialogs.QueryString("Export Character Styles to File:", filename) = WMDialogs.ResOk THEN
				ExportCharacterStyles(filename);
			END;			
		END ExportCHandler;
		
		PROCEDURE ExportCharacterStyles(filename: ARRAY OF CHAR);
		VAR res, i : LONGINT; style : SET;
			tempString : ARRAY 256 OF CHAR;
			string : Utilities.String;
			w : AosFS.Writer; f : AosFS.File; ch :AosTexts.Char32;
			cStyle : AosTexts.CharacterStyle;
		BEGIN
			(* -- Save Style File -- *)
			COPY(filename, tempString);
			Utilities.Append(tempString, ".XML");
			f := AosFS.New(tempString); IF f = NIL THEN RETURN END;
			AosFS.OpenWriter(w, f, 0);
			w.String('<?xml version="1.0" encoding="UTF-8"?>'); w.Ln;
			w.String("<styles>"); w.Ln;
			
			(* processing character styles *)
			i := 0;
			WHILE ((i<LEN(cStyles)) & (cStyles[i] #NIL)) DO
				cStyle := cStyles[i];
				w.String('<character-style name="'); w.String(cStyle.name);
				w.String('" font-family="'); w.String(cStyle.family);
				w.String('" font-style="'); style := cStyle.style;
				IF (style = {}) THEN
					w.Int(0, 0);
				ELSIF (style = {0}) THEN
					w.Int(1, 0);
				ELSIF (style = {1}) THEN
					w.Int(2, 0);
				ELSIF (style = {0,1}) THEN
					w.Int(3, 0);
				ELSE
					w.Int(0, 0);
				END;
				w.String('" font-size="');	 Utilities.FloatToStr(FP1616.FixpToFloat(cStyle.size), 0,4,0, tempString); Utilities.TrimLeft(tempString, " "); w.String(tempString); 	
				w.String('" leading="');  Utilities.FloatToStr(FP1616.FixpToFloat(cStyle.leading), 0,4,0, tempString); Utilities.TrimLeft(tempString, " "); w.String(tempString); 
				w.String('" baseline-shift="');  Utilities.FloatToStr(FP1616.FixpToFloat(cStyle.baselineShift), 0,4,0, tempString); Utilities.TrimLeft(tempString, " "); w.String(tempString);
				w.String('" color="'); w.Hex(cStyle.color, 8);
				w.String('" bgcolor="');  w.Hex(cStyle.bgColor, 8);
				w.String('" tracking="');  Utilities.FloatToStr(FP1616.FixpToFloat(cStyle.tracking), 0,4,0, tempString); Utilities.TrimLeft(tempString, " "); w.String(tempString);
				w.String('" h-scale="');  Utilities.FloatToStr(FP1616.FixpToFloat(cStyle.scaleHorizontal), 0,4,0, tempString); Utilities.TrimLeft(tempString, " "); w.String(tempString);
				w.String('" v-scale="');  Utilities.FloatToStr(FP1616.FixpToFloat(cStyle.scaleVertical), 0,4,0, tempString); Utilities.TrimLeft(tempString, " "); w.String(tempString);
				w.String('" />'); w.Ln;
				INC(i);
			END;
			w.String("</styles>"); w.Ln;
			w.Update; AosFS.Register(f);
			
		END ExportCharacterStyles;
		
		
		PROCEDURE ImportCHandler(sender, data: ANY);
		VAR filename: ARRAY 128 OF CHAR;
		BEGIN
			filename := "";
			IF WMDialogs.QueryString("Import Character Styles from File:", filename) = WMDialogs.ResOk THEN
				ImportCharacterStyles(filename);
			END;	
			UpdateList;
		END ImportCHandler;
		
		PROCEDURE ImportCharacterStyles(filename: ARRAY OF CHAR);
		VAR tempString : ARRAY 256 OF CHAR;
			tempReal: LONGREAL;
			tempInt, res: LONGINT;
			reader : AosFS.Reader;
			parser : XMLParser.Parser;
			scanner : XMLScanner.Scanner;
			f : AosFS.File;
			XMLdocStyle : XML.Document;
			root: XML.Element;
			cont: XMLObjects.Enumerator;
			ptr: ANY;
			str: Utilities.String;
			cStyle: AosTexts.CharacterStyle;
		BEGIN
			COPY(filename, tempString);
			Utilities.Append(tempString, ".XML");
			f := AosFS.Old(tempString);
			IF f = NIL THEN RETURN END;
			NEW(reader, f, 0);		
			NEW(scanner, reader);
			NEW(parser, scanner);
			XMLdocStyle := parser.Parse();
			
			root := XMLdocStyle.GetRoot();
			cont := root.GetContents(); cont.Reset();
			WHILE cont.HasMoreElements() DO
				ptr := cont.GetNext();
				IF ptr IS XML.Element THEN 
					str := ptr(XML.Element).GetName();
					(* AosOut.String(str^); AosOut.Ln; *)
					IF (str # NIL) & (str^ = "character-style") THEN					(* character styles *)
						NEW(cStyle);
						str := ptr(XML.Element).GetAttributeValue("name"); IF str # NIL THEN COPY(str^, cStyle.name) END;
						str := ptr(XML.Element).GetAttributeValue("font-family"); IF str # NIL THEN COPY(str^, cStyle.family) END;
						str := ptr(XML.Element).GetAttributeValue("font-style");
						IF str # NIL THEN
							IF (str^ = "0") THEN cStyle.style := {};
							ELSIF (str^ = "1") THEN cStyle.style := {0};
							ELSIF (str^ = "2") THEN cStyle.style := {1};
							ELSIF (str^ = "3") THEN cStyle.style := {0,1};
							ELSE cStyle.style := {};
							END;
						END;
						str := ptr(XML.Element).GetAttributeValue("font-size"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); cStyle.size := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("leading"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); cStyle.leading := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("baseline-shift"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); cStyle.baselineShift := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("color"); IF str # NIL THEN Utilities.HexStrToInt(str^, tempInt, res); cStyle.color := tempInt; END;
						str := ptr(XML.Element).GetAttributeValue("bgcolor"); IF str # NIL THEN Utilities.HexStrToInt(str^, tempInt, res); cStyle.bgColor := tempInt; END;
						str := ptr(XML.Element).GetAttributeValue("tracking"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); cStyle.tracking := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("h-scale"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); cStyle.scaleHorizontal := FP1616.FloatToFixp(SHORT(tempReal)); END;
						str := ptr(XML.Element).GetAttributeValue("v-scale"); IF str # NIL THEN Utilities.StrToFloat(str^, tempReal); cStyle.scaleVertical := FP1616.FloatToFixp(SHORT(tempReal)); END;
						AosTexts.AddCharacterStyle(cStyle);
						
					END;
				END;	
			END;			
			
		END ImportCharacterStyles;	
		
		PROCEDURE RemoveCHandler(sender, data: ANY);
		VAR i : LONGINT;
		BEGIN
			AosTexts.RemoveCharacterStyle(currentCStyle);
			cList.model.Acquire;
			i := 0;
			WHILE ((i<LEN(cStyles))  & (cStyles[i] # NIL)) DO
				cList.model.SetNofRows(i+1);
				cList.model.SetCellText(0, i, Utilities.NewString(cStyles[i].name));
				cList.model.SetCellData(0, i, cStyles[i]);
				INC(i);
			END;
			CClickSelected(NIL, cList.model.GetCellData(0, i-1));
			cList.SetSelection(0,i-1, 0, i-1);
			cList.model.Release;
			UpdateProc;
			
		END RemoveCHandler;
		
		PROCEDURE ApplyCHandler(sender, data: ANY);
		VAR tempString : ARRAY 256 OF CHAR;
			tempLReal: LONGREAL;
			tempInt, res : LONGINT;
			tempFont : WMGraphics.Font;
		BEGIN
			(* retrieve tempvalues first for those who didn't press enter after changing a value... *)
			cName.GetAsString(tempString);
			COPY(tempString, tempCStyle.name);
			cFont.GetAsString(tempString);
			COPY(tempString, tempCStyle.family);
			cStyle.GetAsString(tempString); Utilities.LowerCase(tempString);
			IF (tempString = "regular") THEN tempCStyle.style := {}; cStyle.SetAsString("Regular");
			ELSIF (tempString = "bold") THEN tempCStyle.style := {0}; cStyle.SetAsString("Bold");
			ELSIF (tempString = "italic") THEN tempCStyle.style := {1}; cStyle.SetAsString("Italic");
			ELSIF (tempString = "bold italic") THEN tempCStyle.style := {0, 1}; cStyle.SetAsString("Bold Italic");
			ELSE tempCStyle.style := {}; cStyle.SetAsString("Regular"); END;
			cSize.GetAsString(tempString);
			Utilities.StrToFloat(tempString, tempLReal);
			tempCStyle.size := FP1616.FloatToFixp(SHORT(tempLReal));				
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			cSize.SetAsString(tempString);
			cLeading.GetAsString(tempString);
			Utilities.StrToFloat(tempString, tempLReal);
			tempCStyle.leading := FP1616.FloatToFixp(SHORT(tempLReal));				
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			cLeading.SetAsString(tempString);
			tempFont := WMGraphics.GetFont(tempCStyle.family, ENTIER(FP1616.FixpToFloat(tempCStyle.size)), tempCStyle.style);
			previewLabel.SetFont(tempFont); previewLabel.Invalidate;										
			IF (tempFont.name # tempCStyle.family) OR (tempFont.size # ENTIER(FP1616.FixpToFloat(tempCStyle.size))) THEN
				fontNotFound.visible.Set(TRUE);
			ELSE
				fontNotFound.visible.Set(FALSE);
			END;
			cLeading.GetAsString(tempString);	
			Utilities.StrToFloat(tempString, tempLReal);
			tempCStyle.leading := FP1616.FloatToFixp(SHORT(tempLReal));				
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			cLeading.SetAsString(tempString);										
			cBaselineShift.GetAsString(tempString);
			Utilities.StrToFloat(tempString, tempLReal);
			tempCStyle.baselineShift := FP1616.FloatToFixp(SHORT(tempLReal));				
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			cBaselineShift.SetAsString(tempString);					
			cColor.GetAsString(tempString);
			Utilities.HexStrToInt(tempString, tempInt, res);
			tempCStyle.color := tempInt;
			Utilities.IntToHexStr(tempInt, 7, tempString);
			cColor.SetAsString(tempString);
			previewLabel.textColor.Set(tempInt); previewLabel.Invalidate;
			cBackColor.GetAsString(tempString);
			Utilities.HexStrToInt(tempString, tempInt, res);
			tempCStyle.bgColor := tempInt;
			Utilities.IntToHexStr(tempInt, 7, tempString);
			cBackColor.SetAsString(tempString);	
			previewLabel.fillColor.Set(tempInt); previewLabel.Invalidate;
			cTracking.GetAsString(tempString);
			Utilities.StrToFloat(tempString, tempLReal);
			tempCStyle.tracking := FP1616.FloatToFixp(SHORT(tempLReal));				
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			cTracking.SetAsString(tempString);									
			cStretchH.GetAsString(tempString);
			Utilities.StrToFloat(tempString, tempLReal);
			tempCStyle.scaleHorizontal := FP1616.FloatToFixp(SHORT(tempLReal));				
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			cStretchH.SetAsString(tempString);					
			cStretchV.GetAsString(tempString);					
			Utilities.StrToFloat(tempString, tempLReal);
			tempCStyle.scaleVertical := FP1616.FloatToFixp(SHORT(tempLReal));				
			Utilities.FloatToStr(tempLReal, 0,4,0, tempString);
			cStretchV.SetAsString(tempString);
		
			(* update currentStyle with temp, refresh list *)
			currentCStyle.name := tempCStyle.name;
			currentCStyle.family := tempCStyle.family;
			currentCStyle.style := tempCStyle.style;
			currentCStyle.size := tempCStyle.size;
			currentCStyle.leading := tempCStyle.leading;
			currentCStyle.baselineShift := tempCStyle.baselineShift;
			currentCStyle.color := tempCStyle.color;
			currentCStyle.bgColor := tempCStyle.bgColor;
			currentCStyle.tracking := tempCStyle.tracking;
			currentCStyle.scaleHorizontal := tempCStyle.scaleHorizontal;
			currentCStyle.scaleVertical := tempCStyle.scaleVertical;
			(* Invalidate Cache *)
			currentCStyle.fontcache := NIL;
			UpdateList;					
		END ApplyCHandler;	

		PROCEDURE AlignHandler(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		BEGIN
			NEW(popup);
			popup.AddParButton("Left", AlignPopupHandler, ctxAlignLeft);
			popup.AddParButton("Center", AlignPopupHandler, ctxAlignCenter);
			popup.AddParButton("Right", AlignPopupHandler, ctxAlignRight);
			popup.AddParButton("Justified", AlignPopupHandler, ctxAlignJustified);
			handled := TRUE;

			popup.Popup(bounds.r-100, bounds.t+72);
		END AlignHandler;
		
		PROCEDURE AlignPopupHandler(sender, data: ANY);
		BEGIN		
			IF (data # NIL) THEN
				popup.Close;
				IF data(ContextMenuData).val = 0 THEN
					pAlign.SetAsString("Left"); tempPStyle.alignment := 0;
				ELSIF data(ContextMenuData).val = 1 THEN
					pAlign.SetAsString("Center"); tempPStyle.alignment := 1;
				ELSIF data(ContextMenuData).val = 2 THEN
					pAlign.SetAsString("Right"); tempPStyle.alignment := 2;
				ELSIF data(ContextMenuData).val = 3 THEN
					pAlign.SetAsString("Justified"); tempPStyle.alignment := 3;
				ELSE
				END;
			END;
		END AlignPopupHandler;		
		
		PROCEDURE StyleHandler(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		BEGIN
			NEW(popup);
			popup.AddParButton("Regular", StylePopupHandler, ctxRegular);
			popup.AddParButton("Bold", StylePopupHandler, ctxBold);
			popup.AddParButton("Italic", StylePopupHandler, ctxItalic);
			popup.AddParButton("Bold Italic", StylePopupHandler, ctxBoldItalic);
			handled := TRUE;

			popup.Popup(bounds.r-100, bounds.t+92);	
		END StyleHandler;

		PROCEDURE StylePopupHandler(sender, data: ANY);
		VAR tempFont : WMGraphics.Font;
		BEGIN		
			IF (data # NIL) THEN
				popup.Close;
				IF data(ContextMenuData).val = 0 THEN
					cStyle.SetAsString("Regular"); tempCStyle.style := {};
				ELSIF data(ContextMenuData).val = 1 THEN
					cStyle.SetAsString("Bold"); tempCStyle.style := {0};
				ELSIF data(ContextMenuData).val = 2 THEN
					cStyle.SetAsString("Italic"); tempCStyle.style := {1};
				ELSIF data(ContextMenuData).val = 3 THEN
					cStyle.SetAsString("Bold Italic"); tempCStyle.style := {0,1};
				ELSE
				END;
				tempFont := WMGraphics.GetFont(tempCStyle.family, ENTIER(FP1616.FixpToFloat(tempCStyle.size)), tempCStyle.style);
				previewLabel.SetFont(tempFont); previewLabel.Invalidate;
			END;	
		END StylePopupHandler;
	
		PROCEDURE ColorHandler(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		VAR result: LONGINT;
			colorString: ARRAY 16 OF CHAR;
			colorPanel : WMPopups.ColorSwatchPopup;
		BEGIN
			NEW(colorPanel);
			colorPanel.onColorChosen := ColorPopupHandler;
			colorPanel.Popup(bounds.r-190, bounds.t+172);

			handled := TRUE;		
		END ColorHandler;
		
		PROCEDURE ColorPopupHandler(result: LONGINT);
		VAR
			colorString: ARRAY 16 OF CHAR;
		BEGIN
			Utilities.IntToHexStr(result, 7, colorString);
			cColor.SetAsString(colorString);
			tempCStyle.color := result;
			previewLabel.textColor.Set(result); previewLabel.Invalidate;
		END ColorPopupHandler;
				
		PROCEDURE BGColorHandler(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		VAR result: LONGINT;
			colorString: ARRAY 16 OF CHAR;
			colorPanel: WMPopups.ColorSwatchPopup;
		BEGIN
			NEW(colorPanel);
			colorPanel.onColorChosen := BGColorPopupHandler;
			colorPanel.Popup(bounds.r-190, bounds.t+192);

			handled := TRUE;	
		END BGColorHandler;
		
		PROCEDURE BGColorPopupHandler(result: LONGINT);
		VAR
			colorString: ARRAY 16 OF CHAR;
		BEGIN
			Utilities.IntToHexStr(result, 7, colorString);
			cBackColor.SetAsString(colorString);
			tempCStyle.bgColor := result;
			previewLabel.fillColor.Set(result); previewLabel.Invalidate;
		END BGColorPopupHandler;			
		
	END StyleEditor;

VAR
	nofWindows : LONGINT;
	ctxAlignLeft, ctxAlignCenter, ctxAlignRight, ctxAlignJustified : ContextMenuData;
	ctxRegular, ctxBold, ctxItalic, ctxBoldItalic : ContextMenuData;
	
(** Set the style of the currently selected text by name *)
PROCEDURE SetStyleByName*(par : ANY) : ANY; (* stylename ~ *)
VAR 
	text : AosTexts.Text;
	from, to : AosTexts.TextPosition;
	a, b : LONGINT;
	cStyle : AosTexts.CharacterStyle;
	cStyleStr : ARRAY 32 OF CHAR;
	r : AosIO.StringReader;
BEGIN	
	AosCommands.PosPar(par, r); 
	r.String(cStyleStr);
	IF (r.res # AosIO.Ok) & (r.res # AosIO.EOF) THEN RETURN NIL; END;
	
	IF AosTexts.GetLastSelection(text, from, to) THEN
		cStyle := AosTexts.GetCharacterStyleByName(cStyleStr);
		IF cStyle # NIL THEN
			text.AcquireWrite;
			a := Utilities.Min(from.GetPosition(), to.GetPosition());
			b := Utilities.Max(from.GetPosition(), to.GetPosition());
			text.SetCharacterStyle(a, b - a, cStyle);
			text.ReleaseWrite
		END;
	END;
	RETURN NIL;
END SetStyleByName;
	
PROCEDURE Open*(par : ANY) : ANY;
VAR winstance : Window;
BEGIN
	NEW(winstance, NIL);
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
	INC(nofWindows)
END IncCount;		

PROCEDURE DecCount;
BEGIN {EXCLUSIVE}
	DEC(nofWindows)
END DecCount;		

PROCEDURE Cleanup;
VAR die : KillerMsg;
	 msg : WMMessages.Message;
	 m : WM.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die);
	msg.ext := die;
	msg.msgType := WMMessages.MsgExt;
	m := WM.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	NEW(ctxAlignLeft, AlignLeft);
	NEW(ctxAlignCenter, AlignCenter);
	NEW(ctxAlignRight, AlignRight);
	NEW(ctxAlignJustified, AlignJustified);
	NEW(ctxRegular, StyleRegular);
	NEW(ctxBold, StyleBold);
	NEW(ctxItalic, StyleItalic);
	NEW(ctxBoldItalic, StyleBoldItalic);	

	AosModules.InstallTermHandler(Cleanup)
END WMTextStyleTool.

S.Free WMTextStyleTool ~
WMTextStyleTool.Open  ~

WMTextStyleTool.SetStyle Bold ~
WMTextStyleTool.SetStyle Normal ~


