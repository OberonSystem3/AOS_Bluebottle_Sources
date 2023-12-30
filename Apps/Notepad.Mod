MODULE Notepad; (** AUTHOR "TF"; PURPOSE "Simple Text Editor"; *)
(**
 * History:
 *
 *	22.03.2006	Unregister TextChanged handler in Window.Close (staubesv)
 *)

IMPORT
	AosOut, AosModules, AosCommands, AosIO, AosFS, WMRestorable, XML, XMLObjects,
	WMStandardComponents, WMGraphics, WMGraphicUtilities, WMProperties,
	WMComponents, WMRectangles, WMMessages, WMDialogs,
	WMTextView, WMEditors, Utilities, AosTextUtilities, AosTexts,
	WMMacros, WMPopups, AosConfig, AosCodecs,
	WM := WMWindowManager;

TYPE
	KillerMsg = OBJECT
	END KillerMsg;

	ContextMenuData = OBJECT
		VAR val : LONGINT;
		
		PROCEDURE &New(val : LONGINT);
		BEGIN
			SELF.val := val
		END New;
	END ContextMenuData;

	CaptionObject = OBJECT
	VAR caption- : ARRAY 100 OF CHAR;
		
		PROCEDURE &New(caption : ARRAY OF CHAR);
		BEGIN
			COPY(caption, SELF.caption);
		END New;
	END CaptionObject;

	Window* = OBJECT (WMComponents.FormWindow)
	VAR
		editor : WMEditors.Editor;
		topToolbar, editPanel : WMStandardComponents.Panel;
		filenameEdit : WMEditors.Editor;
		load, store, formatBtn, wrap : WMStandardComponents.Button;
		label : WMStandardComponents.Label;
		
		wordWrap : BOOLEAN;

		popup : WMPopups.Popup;
		fileFormat : LONGINT;
		codecFormat : ARRAY 100 OF CHAR;
		autoCodecFormat : ARRAY 100 OF CHAR;
		 
		modified : BOOLEAN;
		debug : BOOLEAN;
		
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
			formatBtn.bounds.SetWidth(3 * formatBtn.bounds.GetWidth());
			topToolbar.AddContent(formatBtn);

			NEW(wrap); wrap.caption.SetAOC("Word Wrap"); wrap.alignment.Set(WMComponents.AlignLeft); 
			wrap.onClick.Add(WrapHandler); wrap.bounds.SetWidth(100);
			topToolbar.AddContent(wrap);

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
		VAR i, fl, cp : LONGINT;
			 vc : WMComponents.VisualComponent;
			 xml : XML.Element;
			 s : Utilities.String;
		BEGIN
			wordWrap := TRUE;			
			IncCount;
			vc := CreateForm();
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			InitCodecs;
			codecFormat := "AUTO";
			autoCodecFormat := "";
			SetFormatCaption("AUTO");
			modified := FALSE;

			IF c # NIL THEN 
				(* restore the desktop *)
				WMRestorable.AddByContext(SELF, c, {WM.FlagFrame});
				IF c.appData # NIL THEN
					xml := c.appData(XML.Element);
					s := xml.GetAttributeValue("codecFormat"); IF s # NIL THEN COPY(s^, codecFormat); END;
					s := xml.GetAttributeValue("firstLine");IF s # NIL THEN Utilities.StrToInt(s^, fl) END;
					s := xml.GetAttributeValue("cursorPos");IF s # NIL THEN Utilities.StrToInt(s^, cp) END;
					s := xml.GetAttributeValue("file"); 
					IF s # NIL THEN Load(s^, codecFormat) END;
					editor.tv.firstLine.Set(fl);
					editor.tv.cursor.SetPosition(cp);
					Resized(GetWidth(), GetHeight())
				END			
			ELSE WM.DefaultAddWindow(SELF)
			END;

			SetTitle(Utilities.NewString("Notepad"))
		END New;

		PROCEDURE Open(name : ARRAY OF CHAR);
		BEGIN
			filenameEdit.SetAsString(name);
			LoadHandler(SELF, SELF)
		END Open;

		PROCEDURE InitCodecs;
		VAR caption : CaptionObject;
			elem : XML.Element; enum : XMLObjects.Enumerator; ptr : ANY; str : Utilities.String;
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
						IF debug THEN AosOut.String(str^); AosOut.Ln; END;
						IF (str # NIL) & (str^ = "Codecs") THEN
							enum := ptr(XML.Element).GetContents(); enum.Reset();
							WHILE enum.HasMoreElements() DO
								ptr := enum.GetNext();
								IF ptr IS XML.Element THEN
									str := ptr(XML.Element).GetAttributeValue("name");
									IF debug THEN AosOut.String(str^); AosOut.Ln; END;
									IF (str # NIL) & (str^ = "Decoder") THEN
										enum := ptr(XML.Element).GetContents(); enum.Reset();
										WHILE enum.HasMoreElements() DO
											ptr := enum.GetNext();
											IF ptr IS XML.Element THEN
												str := ptr(XML.Element).GetAttributeValue("name");
												IF debug THEN AosOut.String(str^); AosOut.Ln; END;
												IF (str # NIL) & (str^ = "Text") THEN
													enum := ptr(XML.Element).GetContents(); enum.Reset();
													WHILE enum.HasMoreElements() DO
														ptr := enum.GetNext();
														IF ptr IS XML.Element THEN
															str := ptr(XML.Element).GetAttributeValue("name");
															IF debug THEN AosOut.String(str^); AosOut.Ln; END;
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

		PROCEDURE FormatHandler(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		VAR rectangle : WMRectangles.Rectangle;
		BEGIN
			handled := TRUE;
			rectangle := formatBtn.bounds.Get();
			popup.Popup(bounds.l + rectangle.l, bounds.t + rectangle.t + rectangle.b);
		END FormatHandler;

		PROCEDURE SetFormatCaption(format : ARRAY OF CHAR);
		VAR caption : ARRAY 100 OF CHAR;
		BEGIN			
			caption := "Format : ";
			Utilities.Append(caption, format);
			IF format = "AUTO" THEN Utilities.Append(caption, " "); Utilities.Append(caption, autoCodecFormat); END;
			formatBtn.caption.SetAOC(caption);
			formatBtn.Invalidate;
		END SetFormatCaption;

		PROCEDURE FormatPopupHandler(sender, data : ANY);
		VAR caption : ARRAY 100 OF CHAR;
		BEGIN
			IF (data # NIL) & (data IS CaptionObject) THEN;
				popup.Close;
				COPY(data(CaptionObject).caption, codecFormat);
				SetFormatCaption(codecFormat);
			END;
		END FormatPopupHandler;

		PROCEDURE LoadHandler(sender, data : ANY);
		VAR filename : ARRAY 256 OF CHAR;
		BEGIN
			filenameEdit.GetAsString(filename);
			Load(filename, codecFormat)
		END LoadHandler;

		PROCEDURE Load(filename,  format : ARRAY OF CHAR);
		VAR text : AosTexts.Text; res : LONGINT;
			decoder : AosCodecs.TextDecoder;
			in : AosIO.Reader;
		BEGIN
			res := -1;
			filenameEdit.SetAsString(filename);
			text := editor.text;
			text.AcquireWrite;
			modified := TRUE; (* avoid the ! on the store button while loading *)
			text.Delete(0, text.GetLength());
			editor.tv.firstLine.Set(0);
			text.ReleaseWrite;				

			IF (format = "AUTO") THEN
				decoder := AosTextUtilities.DecodeAuto(filename, autoCodecFormat);
			ELSE decoder := AosCodecs.GetTextDecoder(format);
			END;			
			IF decoder # NIL THEN
				COPY(format, codecFormat);
				in := AosCodecs.OpenInputStream(filename);
				IF in # NIL THEN
					decoder.Open(in, res);
					IF res = 0 THEN
						editor.text.onTextChanged.Remove(TextChanged);
						editor.SetText(decoder.GetText());
						editor.text.onTextChanged.Add(TextChanged);
					END;				
				ELSE
					AosOut.String("Can't open Stream: "); AosOut.String(filename); AosOut.Ln;
				END;
			ELSE
				AosOut.String("No decoder/file: "); AosOut.String(format); AosOut.String(" : "); AosOut.String(filename); AosOut.Ln;	
			END;

			SetFormatCaption(format);
			editor.tv.firstLine.Set(0);
			editor.tv.cursor.SetPosition(0);
			editor.tv.SetFocus;
			modified := FALSE; store.caption.SetAOC("Store")
		END Load;

		PROCEDURE StoreHandler(sender, data : ANY);
		VAR filename : ARRAY 256 OF CHAR;
		BEGIN
			filenameEdit.GetAsString(filename);
			Store(filename, codecFormat)
		END StoreHandler;

		PROCEDURE Store(filename,format  : ARRAY OF CHAR);
		VAR text : AosTexts.Text; res : LONGINT;
			backName : ARRAY 128 OF CHAR;
			encoder : AosCodecs.TextEncoder;
			w : AosFS.Writer;
			f : AosFS.File;
		BEGIN
			filenameEdit.SetAsString(filename);
			(* create backup *)
			Utilities.Concat(filename, ".Bak", backName);
			AosFS.Rename(filename, backName, res);
			IF res = 0 THEN AosOut.String("Backup created  in "); AosOut.String(backName); AosOut.Ln END;
			text := editor.text;
			text.AcquireWrite;

			IF (format = "AUTO") THEN
				IF (autoCodecFormat = "") THEN	encoder := AosCodecs.GetTextEncoder("UTF-8");
				ELSE encoder := AosCodecs.GetTextEncoder(autoCodecFormat); END;
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
			modified := FALSE; store.caption.SetAOC("Store")
		END Store;		

		PROCEDURE WrapHandler(sender, data : ANY);
		BEGIN
			IF wordWrap THEN editor.tv.SetWrapMode({}); wordWrap := FALSE;
			ELSE editor.tv.SetWrapMode({WMTextView.WrapWord}); wordWrap := TRUE;
			END;
		END WrapHandler;

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
			IF (editor # NIL) & (editor.text # NIL) THEN
				editor.text.onTextChanged.Remove(TextChanged)
			END;
			DecCount
		END Close;

		PROCEDURE Handle(VAR x : WMMessages.Message);
		VAR data : XML.Element; a : XML.Attribute; n, str : ARRAY 16 OF CHAR;
			filename : ARRAY 256 OF CHAR;
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS KillerMsg) THEN Close
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					NEW(data);  n := "NotepadData"; data.SetName(n);
					filenameEdit.GetAsString(filename);
					NEW(a); n := "file"; a.SetName(n); a.SetValue(filename); data.AddAttribute(a);
					NEW(a); n := "codecFormat"; a.SetName(n); COPY(codecFormat, str); a.SetValue(str); data.AddAttribute(a);
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

PROCEDURE GetNameFromPar(par : ANY; VAR name : ARRAY OF CHAR);
VAR s : AosCommands.Parameters;
	sr : AosIO.StringReader;
BEGIN
	s := par(AosCommands.Parameters); NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.String(name);	
END GetNameFromPar;

PROCEDURE OpenAscii*(par : ANY) : ANY;
VAR winstance : Window;
	name : ARRAY 256 OF CHAR;
BEGIN
	GetNameFromPar(par, name);
	NEW(winstance, NIL);
	winstance.Load(name, "ISO8859-1");
	RETURN NIL
END OpenAscii;

PROCEDURE OpenOberon*(par : ANY) : ANY;
VAR winstance : Window;
	name : ARRAY 256 OF CHAR;
BEGIN
	GetNameFromPar(par, name);
	NEW(winstance, NIL);
	winstance.Load(name, "Oberon");
	RETURN NIL
END OpenOberon;

PROCEDURE OpenUTF8*(par : ANY) : ANY;
VAR winstance : Window;
	name : ARRAY 256 OF CHAR;
BEGIN
	GetNameFromPar(par, name);
	NEW(winstance, NIL);
	winstance.Load(name, "UTF-8");
	RETURN NIL
END OpenUTF8;

PROCEDURE OpenEmpty*(par : ANY) : ANY;
VAR winstance : Window;
BEGIN
	NEW(winstance, NIL);
	RETURN NIL
END OpenEmpty;

PROCEDURE OpenExpXML*(par : ANY) : ANY;
VAR winstance : Window;
	name : ARRAY 256 OF CHAR;
BEGIN
	GetNameFromPar(par, name);
	NEW(winstance, NIL);
	winstance.Load(name, "BBT");
	RETURN NIL
END OpenExpXML;

PROCEDURE OpenAuto*(par : ANY) : ANY;
VAR winstance : Window;
	name : ARRAY 256 OF CHAR;
BEGIN
	GetNameFromPar(par, name);
	NEW(winstance, NIL);
	winstance.Load(name, "AUTO");
	RETURN NIL
END OpenAuto;

PROCEDURE Restore*(par : ANY) : ANY;
VAR winstance : Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(winstance, par(WMRestorable.Context))
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
END Notepad.

S.Free Notepad~

Notepad.OpenOberon x.txt ~
Notepad.OpenEmpty ~
Notepad.OpenUTF8 AosConfig.XML ~
Notepad.OpenUTF8 MenuPage60.XML ~
Notepad.OpenAscii x.txt ~
Notepad.OpenExpXML x.txt ~
Notepad.OpenAuto WMClock.Mod~
