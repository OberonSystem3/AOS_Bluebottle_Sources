MODULE Notepad; (** AUTHOR "TF"; PURPOSE "Simple Text Editor"; *)

IMPORT
	AosOut, AosModules, AosCommands, AosIO, AosFS, WMRestorable, XML,
	WMStandardComponents, WMGraphics, WMGraphicUtilities,
	WMComponents, WMRectangles, WMMessages, WMDialogs,
	WMTextView, WMEditors, Utilities, AosTextUtilities, AosTexts,
	WMWindowManager, WMMacros, WMPopups;
	
CONST
	OberonFormat = 0;
	UTF8Format = 1;
	AsciiFormat = 2;
	ExpXMLFormat = 3;
	
	FormatString = "Format: ";
	OberonFormatString = "Oberon";
	UTF8FormatString = "UTF-8";
	AsciiFormatString = "Ascii";
	ExpXMLFormatString = "Exp. XML";
		
TYPE
	KillerMsg = OBJECT
	END KillerMsg;
	
	ContextMenuData = OBJECT
		VAR val: LONGINT;
		
		PROCEDURE &New(val: LONGINT);
		BEGIN
			SELF.val := val
		END New;
	END ContextMenuData;
	
	Window* = OBJECT (WMComponents.FormWindow)
	VAR
		editor : WMEditors.Editor;
		topToolbar, editPanel: WMStandardComponents.Panel;
		filenameEdit : WMEditors.Editor;
		load, store, formatBtn : WMStandardComponents.Button;

		popup: WMPopups.Popup;
		fileFormat: LONGINT;
		 
		modified : BOOLEAN;
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			
			NEW(panel); panel.bounds.SetExtents(850, 700); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
			NEW(topToolbar); topToolbar.bounds.SetHeight(20); topToolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(topToolbar);

			NEW(filenameEdit); filenameEdit.alignment.Set(WMComponents.AlignLeft);
			filenameEdit.multiLine.Set(FALSE); filenameEdit.bounds.SetWidth(300);
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
			
			NEW(editPanel); editPanel.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(editPanel);
			
			NEW(editor); editor.alignment.Set(WMComponents.AlignClient); editor.tv.showBorder.Set(TRUE);
			editPanel.AddContent(editor);
			editor.macros.Add(WMMacros.Handle);
			editor.multiLine.Set(TRUE);
			editor.tv.SetWrapMode({WMTextView.WrapWord});
			editor.text.onTextChanged.Add(TextChanged);
			
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
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			fileFormat := UTF8Format; SetFormatCaption(fileFormat);
			modified := FALSE;
			
			IF c # NIL THEN 
				(* restore the desktop *)
				WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame});
				IF c.appData # NIL THEN
					xml := c.appData(XML.Element);
					s := xml.GetAttributeValue("fileFormat");	IF s # NIL THEN Utilities.StrToInt(s^, fileFormat) END;
					s := xml.GetAttributeValue("firstLine");IF s # NIL THEN Utilities.StrToInt(s^, fl) END;
					s := xml.GetAttributeValue("cursorPos");IF s # NIL THEN Utilities.StrToInt(s^, cp) END;
					s := xml.GetAttributeValue("file"); 
					IF s # NIL THEN Load(s^, fileFormat) END;
					editor.tv.firstLine.Set(fl);
					editor.tv.cursor.SetPosition(cp)
				END			
			ELSE WMWindowManager.DefaultAddWindow(SELF)
			END;
			
			SetTitle(Utilities.NewString("Notepad"))
		END New;

		PROCEDURE Open(name : ARRAY OF CHAR);
		BEGIN
			filenameEdit.SetAsString(name);
			LoadHandler(SELF, SELF)
		END Open;

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
			editor.tv.firstLine.Set(0);
			text.ReleaseWrite;
			editor.tv.firstLine.Set(0);
			editor.tv.cursor.SetPosition(0);
			editor.tv.SetFocus;
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
		
		PROCEDURE TextChanged(sender, data : ANY);
		BEGIN
			IF ~modified THEN
				store.caption.SetAOC("Store !");
				modified := TRUE
			END
		END TextChanged;
		
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
					NEW(data);  n := "NotepadData"; data.SetName(n);
					filenameEdit.GetAsString(filename);
					NEW(a); n := "file"; a.SetName(n); a.SetValue(filename); data.AddAttribute(a);
					NEW(a); n := "fileFormat"; a.SetName(n); Utilities.IntToStr(fileFormat, str); a.SetValue(str); data.AddAttribute(a);
					NEW(a); n := "firstLine"; a.SetName(n); Utilities.IntToStr(editor.tv.firstLine.Get(), str); a.SetValue(str); data.AddAttribute(a);
					NEW(a); n := "cursorPos"; a.SetName(n); Utilities.IntToStr(editor.tv.cursor.GetPosition(), str); a.SetValue(str); data.AddAttribute(a);
					x.ext(WMRestorable.Storage).Add("Notepad", "Notepad.Restore", SELF, data)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;

	END Window;

VAR
	nofWindows : LONGINT;
	ctxMenuOberon, ctxMenuUTF8, ctxMenuAscii, ctxMenuExpXML: ContextMenuData;
	
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

PROCEDURE OpenEmpty*(par : ANY) : ANY;
VAR inst : Window;
BEGIN
	NEW(inst, NIL);
	RETURN NIL
END OpenEmpty;

PROCEDURE OpenExpXML*(par : ANY) : ANY;
VAR inst : Window;
	name : ARRAY 256 OF CHAR;
BEGIN
	GetNameFromPar(par, name);
	NEW(inst, NIL); inst.Load(name, ExpXMLFormat);
	RETURN NIL
END OpenExpXML;

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
END Notepad.

S.Free Notepad~

Notepad.OpenOberon x.txt ~
Notepad.OpenEmpty ~
Notepad.OpenUTF8 AosConfig.XML ~
Notepad.OpenUTF8 MenuPage60.XML ~
Notepad.OpenAscii x.txt ~
Notepad.OpenExpXML x.txt ~
