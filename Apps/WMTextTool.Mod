MODULE WMTextTool;	(** AUTHOR "TF"; PURPOSE "Text Tool"; *)

IMPORT
	AosModules, AosTexts, Utilities, WMProperties, WMEvents, WMComponents, WMRestorable, WMEditors, WMPopups, WMRectangles,
	WMGraphics, WMMessages, WMStandardComponents,
	WM := WMWindowManager;

TYPE
	KillerMsg = OBJECT
	END KillerMsg; 

	ChangeInfo = OBJECT    
	VAR 
		fgColor : LONGINT;
		deltaSize : LONGINT;
		style : SET;	
	END ChangeInfo;

	Window* = OBJECT (WMComponents.FormWindow)
	VAR 
		bold, lock, comment, stupid, assert, preferred, debug, normal, incSize, decSize, get, apply: WMStandardComponents.Button;
		famEdit, sizeEdit, styleEdit, colorEdit, bgColEdit: WMEditors.Editor;
		famCheck, sizeCheck, styleCheck, colorCheck, bgColCheck: WMStandardComponents.Checkbox;
		styleB, colB, bgColB : WMStandardComponents.Button;
		popup : WMPopups.Popup;

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
				lbl.alignment.Set(WMComponents.AlignLeft); lbl.bounds.SetWidth(31); label.textColor.Set(0000000FFH);
				lbl.fillColor.Set(windowStyle.bgColor); panel.AddContent(lbl)
			END AL;

			PROCEDURE AC(panel : WMStandardComponents.Panel; chk : WMStandardComponents.Checkbox);
			VAR pnl : WMStandardComponents.Panel;
			BEGIN
				NEW(pnl); pnl.bounds.SetWidth(20); pnl.alignment.Set(WMComponents.AlignRight); pnl.fillColor.Set(windowStyle.bgColor);
				chk.bounds.SetWidth(16); chk.state.Set(1); chk.bearing.Set(WMRectangles.MakeRect(2, 2, 2, 2)); 
				chk.alignment.Set(WMComponents.AlignClient);
				pnl.AddContent(chk); panel.AddContent(pnl) 
			END AC;

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
			manager := WM.GetDefaultManager();
			windowStyle := manager.GetStyle();
			NEW(panel); panel.bounds.SetExtents(120, 220); panel.takesFocus.Set(TRUE);

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);			
			NEW(bold); bold.caption.SetAOC("Bold"); AB(toolbar, bold);
			NEW(lock); lock.caption.SetAOC("Lock"); AB(toolbar, lock);

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(comment); comment.caption.SetAOC("Comment"); AB(toolbar, comment);
			NEW(debug); debug.caption.SetAOC("Debug"); AB(toolbar, debug);
	
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);			
			NEW(stupid); stupid.caption.SetAOC("Stupid"); AB(toolbar, stupid);
			NEW(assert); assert.caption.SetAOC("Assert"); AB(toolbar, assert);

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(preferred); preferred.caption.SetAOC("Preferred"); AB(toolbar, preferred);
			NEW(normal); normal.caption.SetAOC("Normal"); AB(toolbar, normal);

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(incSize); incSize.caption.SetAOC("Inc Size"); AB(toolbar, incSize);
			NEW(decSize); decSize.caption.SetAOC("Dec Size"); AB(toolbar, decSize);

			(* Get/Apply *)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(get); get.caption.SetAOC("Get"); AB(toolbar, get); get.clDefault.Set(088000088H);
			NEW(apply); apply.caption.SetAOC("Apply"); AB(toolbar, apply); apply.clDefault.Set(088000088H);

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar); 
			NEW(label); label.caption.SetAOC("Font:"); AL(toolbar, label);
			NEW(famCheck); AC(toolbar, famCheck);
			NEW(famEdit); famEdit.SetAsString("Oberon"); AE(toolbar, famEdit);

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(label); label.caption.SetAOC("Size:"); AL(toolbar, label);
			NEW(sizeCheck); AC(toolbar, sizeCheck);
			NEW(sizeEdit); sizeEdit.SetAsString("10"); AE(toolbar, sizeEdit);

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar); 
			NEW(label); label.caption.SetAOC("Style:"); AL(toolbar, label);
			NEW(styleCheck); AC(toolbar, styleCheck);
			NEW(styleB); styleB.caption.SetAOC("+"); AD(toolbar, styleB);
			NEW(styleEdit); styleEdit.SetAsString("Regular"); AE(toolbar, styleEdit);

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar); 
			NEW(label); label.caption.SetAOC("Color:"); AL(toolbar, label);
			NEW(colorCheck); AC(toolbar, colorCheck);
			NEW(colB); colB.caption.SetAOC("+"); AD(toolbar, colB);
			NEW(colorEdit); colorEdit.SetAsString("000000FF"); AE(toolbar, colorEdit);

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar); 
			NEW(label); label.caption.SetAOC("BCol:"); AL(toolbar, label);
			NEW(bgColCheck); AC(toolbar, bgColCheck);
			NEW(bgColB); bgColB.caption.SetAOC("+"); AD(toolbar, bgColB);
			NEW(bgColEdit); bgColEdit.SetAsString("00000000"); AE(toolbar, bgColEdit);

			RETURN panel
		END CreateForm;

		PROCEDURE &New(c : WMRestorable.Context);
		VAR vc : WMComponents.VisualComponent;
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
			incSize.onClick.Add(SetStyle);
			decSize.onClick.Add(SetStyle);
			get.onClick.Add(GetStyle);
			apply.onClick.Add(SetCustomStyle);
			styleB.SetExtPointerDownHandler(StyleDrop);
			colB.SetExtPointerDownHandler(ColorHandler);
			bgColB.SetExtPointerDownHandler(BGColorHandler);

			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), TRUE);
			SetContent(vc);

			IF c # NIL THEN WMRestorable.AddByContext(SELF, c, {WM.FlagStayOnTop, WM.FlagFrame})				
			ELSE  WM.ExtAddWindow(SELF, 50, 50, 
			 	{WM.FlagStayOnTop, WM.FlagFrame})
			 END;	
			SetTitle(Utilities.NewString("Text Styles"))
		END New;

		PROCEDURE EnsureAttribute(VAR attr : AosTexts.Attributes);
		BEGIN
			IF attr = NIL THEN
				NEW(attr); NEW(attr.fontInfo);
				attr.fontInfo.name := "Oberon";
				attr.fontInfo.size := 12;
			END
		END EnsureAttribute;

		PROCEDURE ChangeSize(VAR attr : AosTexts.Attributes; userData : ANY);
		BEGIN
			EnsureAttribute(attr);
			IF (userData # NIL) & (userData IS ChangeInfo) THEN
				attr.fontInfo.size:= attr.fontInfo.size + userData(ChangeInfo).deltaSize;
				attr.fontInfo.fontcache := NIL;
				IF attr.fontInfo.size <= 0 THEN attr.fontInfo.size := 5 END
			END;
		END ChangeSize;

		PROCEDURE ReplaceColor(VAR attr : AosTexts.Attributes; userData : ANY);
		BEGIN
			EnsureAttribute(attr);
			IF (userData # NIL) & (userData IS ChangeInfo) THEN
				attr.color := userData(ChangeInfo).fgColor
			END;
		END ReplaceColor;

		PROCEDURE ReplaceStyle(VAR attr : AosTexts.Attributes; userData : ANY);
		BEGIN
			EnsureAttribute(attr);
			IF (userData # NIL) & (userData IS ChangeInfo) THEN
				attr.fontInfo.style := userData(ChangeInfo).style;
				attr.fontInfo.fontcache := NIL;
			END;
		END ReplaceStyle;

		PROCEDURE GetStyle(sender, data : ANY);
		VAR text : AosTexts.Text; from, to : AosTexts.TextPosition;
			utilreader : AosTexts.TextReader; tempString : ARRAY 256 OF CHAR;
			attr : AosTexts.Attributes;
			a, b, ch : LONGINT;
		BEGIN
			IF AosTexts.GetLastSelection(text, from, to) THEN
				text.AcquireWrite;
				a := Utilities.Min(from.GetPosition(), to.GetPosition());
				b := Utilities.Max(from.GetPosition(), to.GetPosition());
				NEW(utilreader, text);
				utilreader.SetPosition(a);
				utilreader.ReadCh(ch);
				IF utilreader.attributes = NIL THEN
					famEdit.SetAsString("Oberon");
					sizeEdit.SetAsString("10");
					styleEdit.SetAsString("regular");
					colorEdit.SetAsString("000000FF");
					bgColEdit.SetAsString("00000000");
				ELSE
					famEdit.SetAsString(utilreader.attributes.fontInfo.name);
					Utilities.IntToStr(utilreader.attributes.fontInfo.size, tempString);
					sizeEdit.SetAsString(tempString);
					IF utilreader.attributes.fontInfo.style = {} THEN
						styleEdit.SetAsString("Regular");
					ELSIF utilreader.attributes.fontInfo.style = {0} THEN
						styleEdit.SetAsString("Bold");					
					ELSIF utilreader.attributes.fontInfo.style = {1} THEN
						styleEdit.SetAsString("Italic");			
					ELSIF utilreader.attributes.fontInfo.style = {0,1} THEN
						styleEdit.SetAsString("Bold Italic");
					ELSE
						styleEdit.SetAsString("Regular");
					END;
					Utilities.IntToHexStr(utilreader.attributes.color, 7, tempString);
					colorEdit.SetAsString(tempString);
					Utilities.IntToHexStr(utilreader.attributes.bgcolor, 7, tempString);
					bgColEdit.SetAsString(tempString);					
				END; 
				text.ReleaseWrite		
			END;
		END GetStyle;

		PROCEDURE SetStyle(sender, data : ANY);
		VAR text : AosTexts.Text;
			from, to : AosTexts.TextPosition;
			utilreader : AosTexts.TextReader;
			attr : AosTexts.Attributes;
			a, b, ch : LONGINT;
			changeInfo : ChangeInfo;
			replaceColor, changeSize, 
			replaceStyle : BOOLEAN;
		BEGIN
			IF AosTexts.GetLastSelection(text, from, to) THEN
				NEW(changeInfo);

				IF sender = bold THEN
					changeInfo.style := {WMGraphics.FontBold};
					changeInfo.fgColor := WMGraphics.RGBAToColor(0, 0, 0, 0FFH);
					replaceStyle := TRUE; replaceColor := TRUE;
				ELSIF sender = lock THEN
					changeInfo.style := {};
					changeInfo.fgColor := WMGraphics.RGBAToColor(0FFH, 0, 0FFH, 0FFH);
					replaceStyle := TRUE; replaceColor := TRUE;				
				ELSIF sender = preferred THEN
					changeInfo.style := {WMGraphics.FontBold};
					changeInfo.fgColor := WMGraphics.RGBAToColor(0FFH, 0, 0FFH, 0FFH);
					replaceStyle := TRUE; replaceColor := TRUE;
				ELSIF sender = assert THEN
					changeInfo.style := {WMGraphics.FontBold};
					changeInfo.fgColor := WMGraphics.RGBAToColor(0, 0, 0FFH, 0FFH);
					replaceStyle := TRUE; replaceColor := TRUE;
				ELSIF sender = comment THEN
					changeInfo.style := {};
					changeInfo.fgColor := WMGraphics.RGBAToColor(80H, 80H, 080H, 0FFH);
					replaceStyle := TRUE; replaceColor := TRUE;
				ELSIF sender = debug THEN
					changeInfo.style := {};
					changeInfo.fgColor := WMGraphics.RGBAToColor(0H, 0H, 0FFH, 0FFH);
					replaceStyle := TRUE; replaceColor := TRUE;
				ELSIF sender = stupid THEN
					changeInfo.style := {};
					changeInfo.fgColor := WMGraphics.RGBAToColor(0FFH, 0H, 0H, 0FFH);
					replaceStyle := TRUE; replaceColor := TRUE;
				ELSIF sender = normal THEN
					changeInfo.style := {};
					changeInfo.fgColor := WMGraphics.RGBAToColor(0H, 0H, 0H, 0FFH);
					replaceStyle := TRUE; replaceColor := TRUE;
				ELSIF sender = incSize THEN
					changeInfo.deltaSize := 1; changeSize := TRUE
				ELSIF sender = decSize THEN
					changeInfo.deltaSize := -1; changeSize := TRUE
				END;
				text.AcquireWrite;
				a := Utilities.Min(from.GetPosition(), to.GetPosition());
				b := Utilities.Max(from.GetPosition(), to.GetPosition());
				IF replaceColor THEN text.UpdateAttributes(a, b - a, ReplaceColor, changeInfo) END;
				IF replaceStyle THEN text.UpdateAttributes(a, b - a, ReplaceStyle, changeInfo) END;
				IF changeSize THEN text.UpdateAttributes(a, b - a, ChangeSize, changeInfo) END;
				text.ReleaseWrite
			END
		END SetStyle;

		PROCEDURE SetCustomStyle(sender, data: ANY);
		VAR text : AosTexts.Text;
			from, to : AosTexts.TextPosition;
			utilreader : AosTexts.TextReader;
			attr : AosTexts.Attributes;
			a, b, ch : LONGINT;
			style : SET;
			fgColor : LONGINT;
			string: ARRAY 32 OF CHAR;
			integer, res, i: LONGINT;
		BEGIN
			IF AosTexts.GetLastSelection(text, from, to) THEN
				text.AcquireWrite;
				IF ((famCheck.state.Get() = 1) & (sizeCheck.state.Get() = 1) & (styleCheck.state.Get() = 1) & (colorCheck.state.Get() = 1) & (bgColCheck.state.Get() = 1)) THEN
					a := Utilities.Min(from.GetPosition(), to.GetPosition());
					b := Utilities.Max(from.GetPosition(), to.GetPosition());
					NEW(utilreader, text);
					utilreader.SetPosition(a);
					utilreader.ReadCh(ch);
					IF utilreader.attributes = NIL THEN
						NEW(attr); NEW(attr.fontInfo);
						attr.fontInfo.name := "Oberon";
						attr.fontInfo.size := 10;
					ELSE attr := utilreader.attributes.Clone(); END;
					famEdit.GetAsString(string);	COPY(string, attr.fontInfo.name);
					sizeEdit.GetAsString(string);	Utilities.StrToInt(string, integer); attr.fontInfo.size := integer;				
					styleEdit.GetAsString(string); Utilities.LowerCase(string);
					IF (string = "0") OR (string = "regular") THEN attr.fontInfo.style := 	{};		
					ELSIF (string = "1") OR (string = "bold") THEN attr.fontInfo.style := {0};	
					ELSIF (string = "2") OR (string = "italic") THEN attr.fontInfo.style := {1};	
					ELSIF (string = "3") OR (string = "bold italic") THEN attr.fontInfo.style := {0,1};	
					ELSE attr.fontInfo.style := {} END;
					colorEdit.GetAsString(string);
					Utilities.HexStrToInt(string, attr.color, res);
					bgColEdit.GetAsString(string);
					Utilities.HexStrToInt(string, attr.bgcolor, res); 
					attr.fontInfo.fontcache := NIL;
					text.SetAttributes(a, b - a, attr);	
				ELSE	
					a := Utilities.Min(from.GetPosition(), to.GetPosition());
					b := Utilities.Max(from.GetPosition(), to.GetPosition());
					NEW(utilreader, text); i := 0;
					utilreader.SetPosition(a);
					WHILE (i<(b-a)) DO
						utilreader.ReadCh(ch);
						IF utilreader.attributes = NIL THEN
							NEW(attr); NEW(attr.fontInfo);
							attr.fontInfo.name := "Oberon";
							attr.fontInfo.size := 10;
							attr.fontInfo.style := {};
							attr.color := 0000000FFH;
							attr.bgcolor := 000000000H;
						ELSE attr := utilreader.attributes.Clone() 	END;
						IF (famCheck.state.Get() = 1) THEN famEdit.GetAsString(string); COPY(string, attr.fontInfo.name); END;
						IF (sizeCheck.state.Get() = 1) THEN sizeEdit.GetAsString(string); Utilities.StrToInt(string, integer); attr.fontInfo.size := integer;	END;		
						IF (styleCheck.state.Get() = 1) THEN styleEdit.GetAsString(string); Utilities.LowerCase(string);
							IF (string = "0") OR (string = "regular") THEN	attr.fontInfo.style := 	{};		
							ELSIF (string = "1") OR (string = "bold") THEN attr.fontInfo.style := {0};	
							ELSIF (string = "2") OR (string = "italic") THEN attr.fontInfo.style := {1};	
							ELSIF (string = "3") OR (string = "bold italic") THEN attr.fontInfo.style := {0,1};	
							ELSE attr.fontInfo.style := {}; END;
						END;
						IF (colorCheck.state.Get() = 1) THEN colorEdit.GetAsString(string); Utilities.HexStrToInt(string, attr.color, res); END;
						IF (bgColCheck.state.Get() = 1) THEN bgColEdit.GetAsString(string); Utilities.HexStrToInt(string, attr.bgcolor, res); END;
						attr.fontInfo.fontcache := NIL;	
						text.SetAttributes(a+i, 1, attr);
						INC(i);
					END;
				END;
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

			popup.Popup(bounds.r-120, bounds.t+180);
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
			colorPanel.Popup(bounds.r-190, bounds.t+200);

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
			DecCount
		END Close;

		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS KillerMsg) THEN Close
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("WMTextTool", "WMTextTool.Restore", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;

	END Window;

VAR
	nofWindows : LONGINT;

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
	AosModules.InstallTermHandler(Cleanup)
END WMTextTool.

S.Free WMTextTool ~
WMTextTool.Open   


