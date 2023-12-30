MODULE IMAPGUI; (** AUTHOR "retmeier"; PURPOSE "A GUI for an IMAP Client"; *)

IMPORT
	AosIO, Utilities, AosOut, Classes := TFClasses, AosKernel, AosModules, IMAPClient, IMAPUtilities,
	WMComponents, WMStandardComponents, WMWindowManager, WMRectangles, WMEditors, WMDialogs, Raster, 
	WMGrids, WMStringGrids, WMGraphics, WMPopups, WMTrees, WMMessages, WMRestorable, AosTexts, UTF8Strings, AosFS, 
	XML, XMLScanner, XMLParser, RMSMTP;

CONST
	CR = 0DX; LF = 0AX;
	DEBUG = FALSE;
	REFRESHTIME = 1000 * 2; 		(* ms *)

VAR
	nofWindows: LONGINT;

TYPE
	String = Utilities.String;
	
	KillerMsg = OBJECT
	END KillerMsg;

	LoadWindow = OBJECT (WMComponents.FormWindow)
		VAR
			offline: WMStandardComponents.Checkbox;
			filename: WMEditors.Editor;
			load, cancel: WMStandardComponents.Button;
			ready, valid: BOOLEAN;			
			
		PROCEDURE &New();
		VAR
			vc : WMComponents.VisualComponent;
		BEGIN
			IncCount();
			ready := FALSE;
			valid := FALSE;
			vc := CreateForm();
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Load Account File"));
			WMWindowManager.DefaultAddWindow(SELF);
		END New;
	
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			ret, panel : WMStandardComponents.Panel;
			label : WMStandardComponents.Label;
			
		BEGIN
			NEW(ret); ret.bounds.SetExtents(400, 200); ret.fillColor.Set(0CCCCCCFFH);
			
			NEW(label); label.bounds.SetHeight(25); label.alignment.Set(WMComponents.AlignTop);
			label.caption.SetAOC("Please give the path of the file that contains the account data: ");
			label.bearing.Set(WMRectangles.MakeRect(10,10,10,10));
			ret.AddContent(label);
		
			NEW(filename); filename.bounds.SetHeight(25); filename.alignment.Set(WMComponents.AlignTop);
			filename.multiLine.Set(FALSE); filename.fillColor.Set(0FFFFFFFFH); filename.tv.showBorder.Set(TRUE);
			filename.bearing.Set(WMRectangles.MakeRect(10,10,10,10));
			ret.AddContent(filename);
			
			NEW(panel);
			panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			ret.AddContent(panel);
			NEW(label); label.bounds.SetWidth(150); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Open the account offline? ");
			label.bearing.Set(WMRectangles.MakeRect(10,0,10,0));
			panel.AddContent(label);
			NEW(offline); offline.bounds.SetWidth(20); offline.alignment.Set(WMComponents.AlignLeft);
			panel.AddContent(offline);
		
			NEW(panel);
			panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignBottom);
			ret.AddContent(panel);
			NEW(load);
			load.bounds.SetWidth(100); load.alignment.Set(WMComponents.AlignRight);
			load.caption.SetAOC("Load"); load.onClick.Add(LoadHandler);
			panel.AddContent(load);
			NEW(cancel);
			cancel.bounds.SetWidth(100); cancel.alignment.Set(WMComponents.AlignRight);
			cancel.caption.SetAOC("Cancel"); cancel.onClick.Add(CancelHandler);
			panel.AddContent(cancel);
			RETURN ret;
		END CreateForm;
		
		PROCEDURE Close();
		BEGIN
			Close^();
			DecCount();
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN
					Close();
			ELSE
				Handle^(x);
			END;
		END Handle;
		
		PROCEDURE LoadHandler(sender, data: ANY);
		BEGIN {EXCLUSIVE}
			ready := TRUE;
			valid := TRUE;
		END LoadHandler;
		
		PROCEDURE GetAnswer(VAR file: String; VAR b: BOOLEAN);
		VAR
			i: LONGINT;
		BEGIN
			BEGIN {EXCLUSIVE}
				AWAIT(ready);
				IF valid THEN
					IMAPUtilities.TextToStr(filename.text, file);
				ELSE
					file := NIL;
				END;
				i := offline.state.Get();
				b := (i = 1);
			END;
			Close^;
		END GetAnswer;
		
		PROCEDURE CancelHandler(sender, data: ANY);
		BEGIN
			BEGIN {EXCLUSIVE}
				ready := TRUE;
			END;
			Close();		
		END CancelHandler;
	END LoadWindow; 
	
	SaveWindow = OBJECT (WMComponents.FormWindow)
		VAR
			filename: WMEditors.Editor;
			save, cancel: WMStandardComponents.Button;
			ready, valid: BOOLEAN;
	
		PROCEDURE &New();
		VAR
			vc : WMComponents.VisualComponent;
		BEGIN
			IncCount();
			ready := FALSE;
			valid := FALSE;
			vc := CreateForm();
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Save Account As"));
			WMWindowManager.DefaultAddWindow(SELF);
		END New;
	
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			ret, panel : WMStandardComponents.Panel;
			label : WMStandardComponents.Label;
		BEGIN
			NEW(ret); ret.bounds.SetExtents(400, 200); ret.fillColor.Set(0CCCCCCFFH);
			
			NEW(label); label.bounds.SetHeight(25); label.alignment.Set(WMComponents.AlignTop);
			label.caption.SetAOC("Please give the name of the file that should be saved: ");
			label.bearing.Set(WMRectangles.MakeRect(10,10,10,10));
			ret.AddContent(label);
		
			NEW(filename); filename.bounds.SetHeight(25); filename.alignment.Set(WMComponents.AlignTop);
			filename.multiLine.Set(FALSE); filename.fillColor.Set(0FFFFFFFFH); filename.tv.showBorder.Set(TRUE);
			filename.bearing.Set(WMRectangles.MakeRect(10,10,10,10));
			ret.AddContent(filename);
			
			NEW(panel);
			panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignBottom);
			ret.AddContent(panel);
			NEW(save);
			save.bounds.SetWidth(100); save.alignment.Set(WMComponents.AlignRight);
			save.caption.SetAOC("Save"); save.onClick.Add(SaveHandler);
			panel.AddContent(save);
			NEW(cancel);
			cancel.bounds.SetWidth(100); cancel.alignment.Set(WMComponents.AlignRight);
			cancel.caption.SetAOC("Cancel"); cancel.onClick.Add(CancelHandler);
			panel.AddContent(cancel);
			RETURN ret;
		END CreateForm;
		
		PROCEDURE Close();
		BEGIN
			Close^();
			DecCount();
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN
					Close();
			ELSE
				Handle^(x);
			END;
		END Handle;		
		
		PROCEDURE SaveHandler(sender, data: ANY);
		BEGIN {EXCLUSIVE}
			ready := TRUE;
			valid := TRUE;
		END SaveHandler;
		
		PROCEDURE GetAnswer(VAR file: String);
		BEGIN
			BEGIN {EXCLUSIVE}
				AWAIT(ready);
				IF valid THEN
					IMAPUtilities.TextToStr(filename.text, file);
				ELSE
					file := NIL;
				END;
			END;
			Close^;
		END GetAnswer;
		
		PROCEDURE CancelHandler(sender, data: ANY);
		BEGIN
			BEGIN {EXCLUSIVE}
				ready := TRUE;
			END;
			Close();		
		END CancelHandler;
	END SaveWindow;
	
	
	MessageWindow = OBJECT (WMComponents.FormWindow)
		VAR
			topToolbar, statusbar, headerPanel, messagePanel: WMStandardComponents.Panel;
			statusLabel: WMStandardComponents.Label;
			send, reply, saveDraft: WMStandardComponents.Button;
			from, to, cc, subject, date: WMEditors.Editor;
			messageField: WMEditors.Editor;
			message: IMAPClient.Message;
			window: Window;
			folder: IMAPClient.Folder;
			
		PROCEDURE &New(win: Window);
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount();
			window := win;
			IF win # NIL THEN
				folder := win.client.currentFolder;
			END;
			vc := CreateForm();	
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Message Window"));
			from.hScrollbar.visible.Set(FALSE);
			to.hScrollbar.visible.Set(FALSE);
			cc.hScrollbar.visible.Set(FALSE);
			WMWindowManager.DefaultAddWindow(SELF);		
		END New;

		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			p: WMStandardComponents.Panel;
			label : WMStandardComponents.Label;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(800, 600); panel.fillColor.Set(0CCCCCCFFH);
			(* --- Toolbar --- *)
			NEW(topToolbar); topToolbar.bounds.SetHeight(40); topToolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(topToolbar);
			
			NEW(send);
			send.caption.SetAOC("Send");
			send.bounds.SetWidth(120); 
			send.bearing.Set(WMRectangles.MakeRect(10,10,10,10));
			send.alignment.Set(WMComponents.AlignLeft);
			send.onClick.Add(ButtonHandler);
			topToolbar.AddContent(send);
			
			NEW(reply);
			reply.caption.SetAOC("Change Fields to answer");
			reply.bounds.SetWidth(140);
			reply.bearing.Set(WMRectangles.MakeRect(10,10,10,10));
			reply.alignment.Set(WMComponents.AlignLeft);
			reply.onClick.Add(ButtonHandler);
			topToolbar.AddContent(reply);
			
			NEW(saveDraft);
			saveDraft.caption.SetAOC("Save in draft folder");
			saveDraft.bounds.SetWidth(120);
			saveDraft.bearing.Set(WMRectangles.MakeRect(10,10,10,10));
			saveDraft.alignment.Set(WMComponents.AlignLeft);
			saveDraft.onClick.Add(ButtonHandler);
			topToolbar.AddContent(saveDraft);
			
			(* --- statusbar --- *)
			NEW(statusbar); statusbar.bounds.SetHeight(20); statusbar.alignment.Set(WMComponents.AlignBottom);	
			panel.AddContent(statusbar);
		
			NEW(statusLabel); statusLabel.bounds.SetWidth(800); statusLabel.alignment.Set(WMComponents.AlignLeft);
			statusLabel.textColor.Set(0000000FFH);
			statusLabel.SetCaption("Status: loading ...");
			statusbar.AddContent(statusLabel);
			
			(* --- headerPanel --- *)			
			NEW(headerPanel); headerPanel.alignment.Set(WMComponents.AlignTop);
			headerPanel.bounds.SetHeight(150);
			headerPanel.fillColor.Set(0FFFFFFFFH);
			panel.AddContent(headerPanel);
			
			(* --- fromPanel --- *)
			NEW(p);
			p.alignment.Set(WMComponents.AlignTop);
			p.bounds.SetHeight(32);
			
			NEW(label);
			label.alignment.Set(WMComponents.AlignLeft);
			label.bounds.SetWidth(60);
			label.SetCaption(" FROM: ");
			p.AddContent(label);
						
			NEW(from);
			from.alignment.Set(WMComponents.AlignClient);
			from.tv.showBorder.Set(TRUE);
			from.hScrollbar.visible.Set(FALSE);
							
			p.AddContent(from);
			headerPanel.AddContent(p);
				
			(* --- toPanel --- *)
			NEW(p);
			p.alignment.Set(WMComponents.AlignTop);
			p.bounds.SetHeight(32);
			
			NEW(label);
			label.alignment.Set(WMComponents.AlignLeft);
			label.bounds.SetWidth(60);
			label.SetCaption(" TO: ");
			p.AddContent(label);
			
			NEW(to);
			to.alignment.Set(WMComponents.AlignClient);
			to.tv.showBorder.Set(TRUE);
			to.hScrollbar.visible.Set(FALSE);
			
			p.AddContent(to);
			headerPanel.AddContent(p);				
			
			(* --- ccPanel --- *)
			NEW(p);
			p.alignment.Set(WMComponents.AlignTop);
			p.bounds.SetHeight(32);
			
			NEW(label);
			label.alignment.Set(WMComponents.AlignLeft);
			label.bounds.SetWidth(60);
			label.SetCaption(" CC: ");
			p.AddContent(label);
					
			NEW(cc);
			cc.alignment.Set(WMComponents.AlignClient);
			cc.tv.showBorder.Set(TRUE);
			cc.hScrollbar.visible.Set(FALSE);
			
			p.AddContent(cc);
			headerPanel.AddContent(p);
				
			(* --- subjectPanel --- *)
			NEW(p);
			p.alignment.Set(WMComponents.AlignTop);
			p.bounds.SetHeight(25);
			
			NEW(label);
			label.alignment.Set(WMComponents.AlignLeft);
			label.bounds.SetWidth(60);
			label.SetCaption(" SUBJECT: ");
			p.AddContent(label);
			
			NEW(subject);
			subject.alignment.Set(WMComponents.AlignClient);
			subject.multiLine.Set(FALSE);
			subject.tv.showBorder.Set(TRUE);
			p.AddContent(subject);
			headerPanel.AddContent(p);				
			
			(* --- datePanel --- *)
			NEW(p);
			p.alignment.Set(WMComponents.AlignTop);
			p.bounds.SetHeight(25);
			
			NEW(label);
			label.alignment.Set(WMComponents.AlignLeft);
			label.bounds.SetWidth(60);
			label.SetCaption(" DATE: ");
			p.AddContent(label);
			
			NEW(date);
			date.alignment.Set(WMComponents.AlignClient);
			date.multiLine.Set(FALSE);
			date.tv.showBorder.Set(TRUE);
			p.AddContent(date);
			headerPanel.AddContent(p);			
			
			(* --- messagePanel --- *)
			NEW(messagePanel); messagePanel.alignment.Set(WMComponents.AlignClient);
			
			NEW(messageField);
			messageField.alignment.Set(WMComponents.AlignClient);
			messageField.tv.showBorder.Set(TRUE);
			messageField.SetAsString("");
			messagePanel.AddContent(messageField);
			messagePanel.fillColor.Set(0FFFFFFFFH);
			messageField.hScrollbar.visible.Set(FALSE);

			panel.AddContent(messagePanel);
						
			RETURN panel;			
		END CreateForm;	
		
		PROCEDURE Close();
		BEGIN
			Close^();
			DecCount();
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN
					Close();
			ELSE
				Handle^(x);
			END;
		END Handle;
		
		PROCEDURE ButtonHandler*(sender, data: ANY);
		BEGIN
			IF sender = send THEN
				Send();
			ELSIF sender = reply THEN
				Reply();
			ELSIF sender = saveDraft THEN
				SaveDraft();
			ELSE
				OutputError("An Unknown Button was pressed");
			END;
		END ButtonHandler;
		
		PROCEDURE Reply();
		VAR
			string: Utilities.String;
			buffer: Utilities.Buffer;
			w: AosIO.Writer;
			r: LONGINT;
			header: IMAPClient.HeaderElement;
			
		BEGIN
			header := message.header;
			IMAPUtilities.TextToStr(subject.text, string);
			NEW(buffer, 16);
			w := buffer.GetWriter();
			w.String("Re: ");
			w.String(string^);
			string := buffer.GetString();
			IMAPUtilities.SetEditorText(subject, string);
			
			IF header.from # NIL THEN
				IMAPUtilities.AddressesToString(header.from, string);
				IMAPUtilities.SetEditorText(to, string);
			ELSE
				string := Utilities.NewString("");
			END;
			
			NEW(buffer, 16);
			w := buffer.GetWriter();
			w.Char(CR); w.Char(LF); w.Char(CR); w.Char(LF);
			w.String(string^);
			w.String(" wrote:"); w.Char(CR); w.Char(LF); w.Char(CR); w.Char(LF);
			IMAPUtilities.TextToStr(messageField.text, string);
			w.String(string^);
			string := buffer.GetString();
			IMAPUtilities.SetEditorText(messageField, string);
			
			IF window # NIL THEN
				string := Utilities.NewString(window.client.preferences.From^);
				IMAPUtilities.SetEditorText(from, string);
				IF window.client.currentFolder # folder THEN
					buffer.Clear();
					w.String("The current Folder of your Mail Client is not equal to the Folder this Message is stored in. ");
					w.String("So the Answered Flag will not be updated. ");
					w.String("If you want the Answered Flag to be updated change to the Folder this Message is stored in and click Yes. ");
					w.String("Otherwise click No.");
					string := buffer.GetString();
					r := WMDialogs.ResYes;
					WHILE (r = WMDialogs.ResYes) & (window.client.currentFolder # folder) DO
						r := WMDialogs.Message("Warning",string^, {WMDialogs.ResYes, WMDialogs.ResNo});
					END;
					IF  (r = WMDialogs.ResYes) & (window.client.currentFolder = folder) THEN
						r := window.client.SetAnsweredFlag(message);
					END;
				ELSE
					r := window.client.SetAnsweredFlag(message);
				END;
			END;
		END Reply;
		
		PROCEDURE Send();
		VAR
			server, thisHost: ARRAY 1000 OF CHAR;
			preferences: IMAPClient.AccountPreferences;
			r: LONGINT;
			msg, caption: String;
			buttons: SET;
			header: IMAPClient.HeaderElement;
			newMessage: IMAPClient.Message;
		BEGIN
			NEW(header);
			NEW(newMessage);
			newMessage.header := header;
			message := newMessage;
			
			BuildMessage();
			
			IF window # NIL THEN
				preferences := window.client.preferences;
				IMAPUtilities.StringCopy(preferences.SMTPServer^, 0, IMAPUtilities.StringLength(preferences.SMTPServer^), server);
				IMAPUtilities.StringCopy(preferences.SMTPThisHost^, 0, IMAPUtilities.StringLength(preferences.SMTPThisHost^), thisHost);
			ELSE
				server := "";
				thisHost := "";
			END;
			statusLabel.caption.SetAOC("Status: Preparing...");
			IF WMDialogs.QueryString("Enter SMTP-Server:", server) = WMDialogs.ResOk THEN
				IF WMDialogs.QueryString("Enter Name of this host", thisHost) = WMDialogs.ResOk THEN
					statusLabel.caption.SetAOC("Status: Sending...");
				(*	r := RMSMTP.SendMessage(message, server, thisHost); *)
					statusLabel.caption.SetAOC("Status: Finished");
					
					IF r = RMSMTP.OK THEN
						buttons := {WMDialogs.ResYes, WMDialogs.ResNo};
						caption := Utilities.NewString("Send was successful");
						msg := Utilities.NewString("Send was successful. Do you want to close the MessageWindow now?");
						IF window # NIL THEN
							window.client.abort := TRUE;
							r := window.client.SaveSentMessage(message);
							window.client.abort := FALSE;
						END
					ELSE
						buttons := {WMDialogs.ResOk};
						caption := Utilities.NewString("Send was NOT successful");
						msg := Utilities.NewString("Send was NOT successful.");
					END;
					r := WMDialogs.Message(caption^, msg^, buttons);
					IF r = WMDialogs.ResYes THEN
						Close^;
					END;
				END;
			END;
			statusLabel.caption.SetAOC("Status: Finished");			
		END Send;
		
		PROCEDURE SaveDraft();
		VAR
			path: String;
			r: LONGINT;
		BEGIN
			path := window.client.preferences.DraftFolder;
			IF path^ = "" THEN
				OutputError("No Draft Folder specified in Preferences");
				RETURN;
			END;
			BuildMessage();
			r := window.client.AppendMessage(message, path);	
		END SaveDraft;
		
		(* Reads the input fields and stores them in the message object *)
		PROCEDURE BuildMessage();
		VAR
			string: String;
			addresses: Classes.List;
		BEGIN
			NEW(message);
			NEW(message.header);
			IMAPUtilities.TextToStr(from.text, string);
			IF Utilities.Length(string^) > 0 THEN
				IMAPUtilities.ParseAddresses(string, addresses);
				message.header.from := addresses;
			END;
			
			IMAPUtilities.TextToStr(to.text, string);
			IF Utilities.Length(string^) > 0 THEN
				IMAPUtilities.ParseAddresses(string, addresses);
				message.header.to := addresses;
			END;
			
			IMAPUtilities.TextToStr(cc.text, string);
			IF Utilities.Length(string^) > 0 THEN
				IMAPUtilities.ParseAddresses(string, addresses);
				message.header.cc := addresses;
			END;
			
			IMAPUtilities.TextToStr(subject.text, string);
			message.header.subject := Utilities.NewString(string^);
			message.header.date := IMAPUtilities.getRFC822Date();
			IMAPUtilities.TextToStr(messageField.text, string);
			message.message := string;
		END BuildMessage;
		
		PROCEDURE NewMessage*();
		VAR
			header: IMAPClient.HeaderElement;
			string: String;
		BEGIN
			NEW(message);
			NEW(header);
			message.header := header;
			IF window # NIL THEN
				string := Utilities.NewString(window.client.preferences.From^);
				IMAPUtilities.SetEditorText(from, string);
			END;
			statusLabel.caption.SetAOC("Status: Ready");
			from.hScrollbar.visible.Set(FALSE);
			to.hScrollbar.visible.Set(FALSE);
			cc.hScrollbar.visible.Set(FALSE);
			messageField.hScrollbar.visible.Set(FALSE);
		END NewMessage;

		PROCEDURE DisplayMessage*(message: IMAPClient.Message);
		VAR
			string, string2: String;
			header: IMAPClient.HeaderElement;
			i: LONGINT;
			text: AosTexts.Text;
		BEGIN
			SELF.message := message;
			from.hScrollbar.visible.Set(FALSE);
			to.hScrollbar.visible.Set(FALSE);
			cc.hScrollbar.visible.Set(FALSE);
			messageField.hScrollbar.visible.Set(FALSE);
			
			header := message.header;
			IF header.from # NIL THEN
				IMAPUtilities.AddressesToString(header.from, string);
				IMAPUtilities.replaceEncodedHeaderWord(string^);
				IMAPUtilities.SetEditorText(from, string);
			END;
			
			IF header.to # NIL THEN
				IMAPUtilities.AddressesToString(header.to, string);
				IMAPUtilities.replaceEncodedHeaderWord(string^);
				IMAPUtilities.SetEditorText(to, string);
			END;

			IF header.cc # NIL THEN
				IMAPUtilities.AddressesToString(header.cc, string);
				IMAPUtilities.replaceEncodedHeaderWord(string^);
				IMAPUtilities.SetEditorText(cc, string);
			END;
			
			IF header.subject # NIL THEN
				string := IMAPUtilities.NewString(header.subject^);
				IMAPUtilities.replaceEncodedHeaderWord(string^);
				IMAPUtilities.SetEditorText(subject, string);
			END;
			
			IF header.date # NIL THEN
				string := IMAPUtilities.NewString(header.date^);
				IMAPUtilities.replaceEncodedHeaderWord(string^);
				IMAPUtilities.SetEditorText(date, string);
			END;
			
			IF message.bodystructure # NIL THEN
				Utilities.UpperCase(message.bodystructure.type);
				Utilities.UpperCase(message.bodystructure.subtype);
				Utilities.UpperCase(message.bodystructure.encoding);
				Utilities.UpperCase(message.bodystructure.charset);
				IF DEBUG THEN
					AosOut.String("Type: "); AosOut.String(message.bodystructure.type); AosOut.Ln();
					AosOut.String("SubType: "); AosOut.String(message.bodystructure.subtype); AosOut.Ln();
					AosOut.String("Encoding: "); AosOut.String(message.bodystructure.encoding); AosOut.Ln();
					AosOut.String("Charset: "); AosOut.String(message.bodystructure.charset); AosOut.Ln();
				END;
				
				IF (message.bodystructure.type = "TEXT") & (message.bodystructure.subtype = "PLAIN") THEN
					IF message.message # NIL THEN
						IF message.bodystructure.encoding = "BASE64" THEN
							(* decode base64 *)
							string := IMAPUtilities.decodeBase64(message.message^);
						ELSIF message.bodystructure.encoding = "QUOTED-PRINTABLE" THEN
							(* decode quoted-printable *)
							string := IMAPUtilities.decodeQuotedPrintable(message.message^);
						ELSE
							(* don't have to decode *)
							string := Utilities.NewString(message.message^);
						END;
						
						(* transform message to the right charset *)
						NEW(text);
						IF message.bodystructure.charset = "UTF-8" THEN
							IMAPUtilities.StrToText(text, 0, string^);
						ELSIF message.bodystructure.charset = "ISO-8859-1" THEN
							i := IMAPUtilities.StringLength(string^);
							NEW(string2, 6*i + 1);
							UTF8Strings.ASCIItoUTF8(string^, string2^);
							IMAPUtilities.StrToText(text, 0, string2^);
						ELSE (* assume US-ASCII *)
							i := IMAPUtilities.StringLength(string^);
							NEW(string2, 6*i + 1);
							UTF8Strings.ASCIItoUTF8(string^, string2^);
							IMAPUtilities.StrToText(text, 0, string2^);
						END;
						messageField.SetText(text);
						statusLabel.SetCaption("Status: Finished");
					ELSE
						messageField.SetAsString("Message can not be loaded!");
						statusLabel.SetCaption("Finished");
					END;
				ELSE
					NEW(text);
					IMAPUtilities.StrToText(text, 0, message.message^);
					messageField.SetText(text);
					statusLabel.SetCaption("Message is not of type TEXT/PLAIN");
				END;
			ELSE
				IF message.message = NIL THEN
					OutputError("The body of this message is not available. Maybe your are offline and don't have the body in your local storage");
				ELSE
					(* assume TEXT/PLAIN, US-ASSCII, no Encoding *)
					NEW(text);
					IMAPUtilities.StrToText(text, 0, message.message^);
					messageField.SetText(text);
					statusLabel.SetCaption("The Bodystructure for this message is not available. TEXT/PLAIN is assumed.");
				END;
			END;
			from.hScrollbar.visible.Set(FALSE);
			to.hScrollbar.visible.Set(FALSE);
			cc.hScrollbar.visible.Set(FALSE);
		END DisplayMessage;
	END MessageWindow;				

	SearchWindow = OBJECT (WMComponents.FormWindow)
		VAR
			answered, unanswered, deleted, undeleted, draft, undraft, flagged, unflagged, seen, unseen, recent, old: WMStandardComponents.Checkbox;
			subject, text, from, minSize, maxSize: WMEditors.Editor;
			search, cancel: WMStandardComponents.Button;
			before, on, after: WMStandardComponents.Checkbox;
			day, month, year: WMEditors.Editor;
			utf8: WMStandardComponents.Checkbox;
			status: WMStandardComponents.Label;
			w: Window;
	
		PROCEDURE &New(win: Window);
		VAR
			vc : WMComponents.VisualComponent;
		BEGIN
			IncCount();
			w := win;
			vc := CreateForm();
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Search Window"));
			WMWindowManager.DefaultAddWindow(SELF);
		END New;
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			label: WMStandardComponents.Label;
			p: WMStandardComponents.Panel;			
		BEGIN
			NEW(panel); panel.bounds.SetExtents(600, 400); panel.fillColor.Set(0CCCCCCFFH);
			
			(* --- flags --- *)
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Answered: ");
			p.AddContent(label);
			NEW(answered); answered.bounds.SetWidth(20); answered.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(answered);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(label);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Unanswered: ");
			p.AddContent(label);
			NEW(unanswered); unanswered.bounds.SetWidth(20); unanswered.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(unanswered);
			
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Deleted: ");
			p.AddContent(label);
			NEW(deleted); deleted.bounds.SetWidth(20); deleted.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(deleted);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(label);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Undeleted: ");
			p.AddContent(label);
			NEW(undeleted); undeleted.bounds.SetWidth(20); undeleted.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(undeleted);
			
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Draft: ");
			p.AddContent(label);
			NEW(draft); draft.bounds.SetWidth(20); draft.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(draft);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(label);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Undraft: ");
			p.AddContent(label);
			NEW(undraft); undraft.bounds.SetWidth(20); undraft.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(undraft);

			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Flagged: ");
			p.AddContent(label);
			NEW(flagged); flagged.bounds.SetWidth(20); flagged.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(flagged);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(label);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Unflagged: ");
			p.AddContent(label);
			NEW(unflagged); unflagged.bounds.SetWidth(20); unflagged.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(unflagged);
			
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Seen: ");
			p.AddContent(label);
			NEW(seen); seen.bounds.SetWidth(20); seen.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(seen);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(label);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Unseen: ");
			p.AddContent(label);
			NEW(unseen); unseen.bounds.SetWidth(20); unseen.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(unseen);
			
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Recent: ");
			p.AddContent(label);
			NEW(recent); recent.bounds.SetWidth(20); recent.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(recent);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(label);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Old: ");
			p.AddContent(label);
			NEW(old); old.bounds.SetWidth(20); old.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(old);

			(* --- rest --- *)
			NEW(p);
			p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Subject: ");
			p.AddContent(label);
			NEW(subject); subject.bounds.SetWidth(300); subject.alignment.Set(WMComponents.AlignClient);
			subject.multiLine.Set(FALSE); subject.fillColor.Set(0FFFFFFFFH); subject.tv.showBorder.Set(TRUE);
			p.AddContent(subject);
			
			NEW(p);
			p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("From: ");
			p.AddContent(label);
			NEW(from); from.bounds.SetWidth(300); from.alignment.Set(WMComponents.AlignClient);
			from.multiLine.Set(FALSE); from.fillColor.Set(0FFFFFFFFH); from.tv.showBorder.Set(TRUE);
			p.AddContent(from);
			
			NEW(p);
			p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Body-Text: ");
			p.AddContent(label);
			NEW(text); text.bounds.SetWidth(300); text.alignment.Set(WMComponents.AlignClient);
			text.multiLine.Set(FALSE); text.fillColor.Set(0FFFFFFFFH); text.tv.showBorder.Set(TRUE);
			p.AddContent(text);
			
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Min Size: ");
			p.AddContent(label);
			NEW(minSize); minSize.bounds.SetWidth(100); minSize.alignment.Set(WMComponents.AlignLeft);
			minSize.multiLine.Set(FALSE); minSize.fillColor.Set(0FFFFFFFFH); minSize.tv.showBorder.Set(TRUE);
			p.AddContent(minSize);

			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC(" ");
			p.AddContent(label);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Max Size: ");
			p.AddContent(label);
			NEW(maxSize); maxSize.bounds.SetWidth(100); maxSize.alignment.Set(WMComponents.AlignLeft);
			maxSize.multiLine.Set(FALSE); maxSize.fillColor.Set(0FFFFFFFFH); maxSize.tv.showBorder.Set(TRUE);
			p.AddContent(maxSize);
			
			NEW(p);
			p.bounds.SetHeight(15); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Before: ");
			p.AddContent(label);
			NEW(before); before.bounds.SetWidth(20); before.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(before);
			
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("On: ");
			p.AddContent(label);
			NEW(on); on.bounds.SetWidth(20); on.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(on);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC(" ");
			p.AddContent(label);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Date: ");
			p.AddContent(label);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Day: ");
			p.AddContent(label);
			NEW(day); day.bounds.SetWidth(50); day.alignment.Set(WMComponents.AlignLeft);
			day.multiLine.Set(FALSE); day.fillColor.Set(0FFFFFFFFH); day.tv.showBorder.Set(TRUE);
			p.AddContent(day);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Month: ");
			p.AddContent(label);
			NEW(month); month.bounds.SetWidth(50); month.alignment.Set(WMComponents.AlignLeft);
			month.multiLine.Set(FALSE); month.fillColor.Set(0FFFFFFFFH); month.tv.showBorder.Set(TRUE);
			p.AddContent(month);
			NEW(label); label.bounds.SetWidth(50); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Year: ");
			p.AddContent(label);
			NEW(year); year.bounds.SetWidth(50); year.alignment.Set(WMComponents.AlignLeft);
			year.multiLine.Set(FALSE); year.fillColor.Set(0FFFFFFFFH); year.tv.showBorder.Set(TRUE);
			p.AddContent(year);

			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("After: ");
			p.AddContent(label);
			NEW(after); after.bounds.SetWidth(20); after.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(after);
			
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Try UTF-8 charset for search strings: ");
			p.AddContent(label);
			NEW(utf8); utf8.bounds.SetWidth(20); utf8.alignment.Set(WMComponents.AlignLeft);
			p.AddContent(utf8);
			
			(* --- buttons  --- *)
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignBottom);
			p.bearing.Set(WMRectangles.MakeRect(5,2,5,2));
			panel.AddContent(p);
			
			NEW(search);
			search.bounds.SetWidth(100); search.alignment.Set(WMComponents.AlignRight);
			search.caption.SetAOC("Search"); search.onClick.Add(SearchHandler);
			p.AddContent(search);
			
			NEW(cancel);
			cancel.bounds.SetWidth(100); cancel.alignment.Set(WMComponents.AlignRight);
			cancel.caption.SetAOC("Cancel"); cancel.onClick.Add(CancelHandler);
			p.AddContent(cancel);
			
			NEW(status); status.bounds.SetWidth(400); status.alignment.Set(WMComponents.AlignLeft);
			status.caption.SetAOC("Status: Ready");
			p.AddContent(status);
			
			RETURN panel;
		END CreateForm;
		
		PROCEDURE Close();
		BEGIN
			Close^();
			DecCount();
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN
					Close();
			ELSE
				Handle^(x);
			END;
		END Handle;

		PROCEDURE SearchHandler(sender, data: ANY);
		VAR
			buffer, dateBuffer: Utilities.Buffer;
			string, dateString: String;
			writer, dateWriter: AosIO.Writer;
			i, dateCount: LONGINT;
			monthString: ARRAY 37 OF CHAR;
			valid: BOOLEAN;
			errorString: ARRAY 65 OF CHAR;
		BEGIN
			valid := TRUE;
			NEW(buffer, 16);
			writer := buffer.GetWriter();
			
			i := utf8.state.Get();
			IF i = 1 THEN writer.String("CHARSET UTF-8 "); END;
			i := answered.state.Get();
			IF i = 1 THEN writer.String("ANSWERED "); END;
			i := unanswered.state.Get();
			IF i = 1 THEN writer.String("UNANSWERED ") END;
			i := deleted.state.Get();
			IF i = 1 THEN writer.String("DELETED ") END;
			i := undeleted.state.Get();
			IF i = 1 THEN writer.String("UNDELETED ") END;
			i := draft.state.Get();
			IF i = 1 THEN writer.String("DRAFT ") END;
			i := undraft.state.Get();
			IF i = 1 THEN writer.String("UNDRAFT ") END;
			i := flagged.state.Get();
			IF i = 1 THEN writer.String("FLAGGED ") END;
			i := unflagged.state.Get();
			IF i = 1 THEN writer.String("UNFLAGGED ") END;
			i := seen.state.Get();
			IF i = 1 THEN writer.String("SEEN ") END;
			i := unseen.state.Get();
			IF i = 1 THEN writer.String("UNSEEN ") END;
			i := recent.state.Get();
			IF i = 1 THEN writer.String("RECENT ") END;
			i := old.state.Get();
			IF i = 1 THEN writer.String("OLD ") END;
			
			IMAPUtilities.TextToStr(subject.text, string);
			IF IMAPUtilities.StringLength(string^) > 0 THEN
				IMAPUtilities.MakeQuotedString(string);
				writer.String("SUBJECT ");
				writer.String(string^);
				writer.String(" ");
			END;
			IMAPUtilities.TextToStr(from.text, string);
			IF IMAPUtilities.StringLength(string^) > 0 THEN
				IMAPUtilities.MakeQuotedString(string);
				writer.String("FROM ");
				writer.String(string^);
				writer.String(" ");
			END;
			IMAPUtilities.TextToStr(text.text, string);
			IF IMAPUtilities.StringLength(string^) > 0 THEN
				IMAPUtilities.MakeQuotedString(string);
				writer.String("BODY ");
				writer.String(string^);
				writer.String(" ");
			END;
			IMAPUtilities.TextToStr(minSize.text, string);
			IF IMAPUtilities.StringLength(string^) > 0 THEN
				Utilities.StrToInt(string^, i);
				Utilities.IntToStr(i-1, string^);
				writer.String("LARGER ");
				writer.String(string^);
				writer.String(" ");
			END;
			IMAPUtilities.TextToStr(maxSize.text, string);
			IF IMAPUtilities.StringLength(string^) > 0 THEN
				Utilities.StrToInt(string^,i);
				Utilities.IntToStr(i+1, string^);
				writer.String("SMALLER ");
				writer.String(string^);
				writer.String(" ");
			END;

			dateCount := 0;
			i := before.state.Get();
			IF i = 1 THEN INC(dateCount); END;
			i := on.state.Get();
			IF i = 1 THEN INC(dateCount); END;
			i := after.state.Get();
			IF i = 1 THEN INC(dateCount); END;
			
			IF dateCount = 3 THEN
				(* It doesn't make sense to do an OR on before, on and after because it is always true *)
			ELSE
				IF dateCount = 2 THEN
					(* do an OR *)
					writer.String("OR ");
				END;
				
				NEW(dateBuffer, 16);
				dateWriter := dateBuffer.GetWriter();
				
				IMAPUtilities.TextToStr(day.text, string);
				IF IMAPUtilities.StringLength(string^) > 0 THEN
					Utilities.StrToInt(string^,i);
					IF (i < 1) OR (i > 31) THEN
						valid := FALSE;
						COPY("Day should be between 1 and 31", errorString);
					END;
					Utilities.IntToStr(i, string^);
					dateWriter.String(string^);
					dateWriter.String("-");
				END;
				IMAPUtilities.TextToStr(month.text, string);
				IF IMAPUtilities.StringLength(string^) > 0 THEN
					Utilities.StrToInt(string^,i);
					IF (i < 1) OR (i > 12) THEN 
						valid := FALSE;
						COPY("Month should be between 1 and 12", errorString);
					ELSE
						COPY("JanFebMarAprMayJunJulAugSepOctNovDec", monthString);
						IMAPUtilities.StringCopy(monthString, (3*i)-3, 3, string^);
						dateWriter.String(string^);
						dateWriter.String("-");
					END;
				END;
				IMAPUtilities.TextToStr(year.text, string);
				IF IMAPUtilities.StringLength(string^) > 0 THEN
					Utilities.StrToInt(string^,i);
					Utilities.IntToStr(i, string^);
					IF IMAPUtilities.StringLength(string^) # 4 THEN
						valid := FALSE;
						COPY("Year should consist of 4 digits", errorString);
					END;
					dateWriter.String(string^);
				END;

				dateString := dateBuffer.GetString();
				
				i := before.state.Get();
				IF i = 1 THEN
					writer.String("BEFORE ");
					writer.String(dateString^);
					writer.String(" ");
				END;
				i := on.state.Get();
				IF i = 1 THEN
					writer.String("ON ");
					writer.String(dateString^);
					writer.String(" ");
				END;
				i := after.state.Get();
				IF i = 1 THEN
					writer.String("SINCE ");
					writer.String(dateString^);
					writer.String(" ");
				END;				
			END;

			IF valid THEN
				string := buffer.GetString();
				Utilities.TrimRight(string^, " ");
				IF DEBUG THEN AosOut.String("Performing search..."); END;
				status.caption.SetAOC("Status: Performing search...");
				i := w.client.Search(string^);
				IF i < 0 THEN
					status.caption.SetAOC("Status: Searching Not Successful");
				ELSE
					NEW(buffer,16);
					writer := buffer.GetWriter();
					writer.String("Status: Finished. ");
					NEW(string, 20);
					Utilities.IntToStr(i, string^);
					writer.String(string^);
					writer.String(" messages found.");
					string := buffer.GetString();
					status.caption.SetAOC(string^);
					IF DEBUG THEN AosOut.String("Search finished. "); AosOut.Int(i,0); AosOut.String(" messages found"); AosOut.Ln(); END; 
					w.messageGrid.SetTopPosition(0,0,TRUE);
					w.timer.Wakeup();
				END;
				
			ELSE
				NEW(buffer,16);
				writer := buffer.GetWriter();
				writer.String("Status: Invalid Input: ");
				writer.String(errorString);
				string := buffer.GetString();
				status.caption.SetAOC(string^);
				OutputError(errorString);
			END;
		END SearchHandler;
		
		PROCEDURE CancelHandler(sender, data: ANY);
		VAR
		BEGIN
			Close^;
		END CancelHandler;
	END SearchWindow;
	
	PreferencesWindow = OBJECT (WMComponents.FormWindow)
	VAR
		SMTPServer, SMTPThisHost, SentFolder, DraftFolder, TrashBin, From: WMEditors.Editor;
		ExpungeOnFolderChange, ExpungeOnDelete, UseDragNDropAsMove, ExpungeOnMove, UseATrashBin: WMStandardComponents.Checkbox;
		ok, cancel: WMStandardComponents.Button;
		window: Window;
		oldPreferences: IMAPClient.AccountPreferences;
		
		PROCEDURE &New(win: Window);
		VAR
			vc : WMComponents.VisualComponent;
		BEGIN
			IncCount();
			window := win;
			IF window.client # NIL THEN
				oldPreferences := window.client.preferences;
			ELSE
				NEW(oldPreferences);
			END;
			vc := CreateForm();
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Preferences"));
			WMWindowManager.DefaultAddWindow(SELF);
		END New;
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			label: WMStandardComponents.Label;
			p: WMStandardComponents.Panel;
			rect: WMRectangles.Rectangle;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(500, 400); panel.fillColor.Set(0CCCCCCFFH);
			rect := WMRectangles.MakeRect(5, 2, 5, 2);
			
			NEW(p); p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("IMAP server name: ");
			p.AddContent(label);
			NEW(label); label.alignment.Set(WMComponents.AlignClient);
			label.caption.Set(window.client.preferences.IMAPServer);
			p.AddContent(label);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("IMAP user name: ");
			p.AddContent(label);
			NEW(label); label.alignment.Set(WMComponents.AlignClient);
			label.caption.Set(window.client.preferences.UserName);
			p.AddContent(label);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("SMTP server name: ");
			p.AddContent(label);
			NEW(SMTPServer); SMTPServer.alignment.Set(WMComponents.AlignClient);
			SMTPServer.multiLine.Set(FALSE); SMTPServer.fillColor.Set(0FFFFFFFFH); SMTPServer.tv.showBorder.Set(TRUE);
			SMTPServer.SetAsString(oldPreferences.SMTPServer^);
			p.AddContent(SMTPServer);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Name of this host(for SMTP): ");
			p.AddContent(label);
			NEW(SMTPThisHost); SMTPThisHost.alignment.Set(WMComponents.AlignClient);
			SMTPThisHost.multiLine.Set(FALSE); SMTPThisHost.fillColor.Set(0FFFFFFFFH); SMTPThisHost.tv.showBorder.Set(TRUE);
			SMTPThisHost.SetAsString(oldPreferences.SMTPThisHost^);
			p.AddContent(SMTPThisHost);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Sent Folder: ");
			p.AddContent(label);
			NEW(SentFolder); SentFolder.alignment.Set(WMComponents.AlignClient);
			SentFolder.multiLine.Set(FALSE); SentFolder.fillColor.Set(0FFFFFFFFH); SentFolder.tv.showBorder.Set(TRUE);
			SentFolder.SetAsString(oldPreferences.SentFolder^);
			p.AddContent(SentFolder);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Draft Folder: ");
			p.AddContent(label);
			NEW(DraftFolder); DraftFolder.alignment.Set(WMComponents.AlignClient);
			DraftFolder.multiLine.Set(FALSE); DraftFolder.fillColor.Set(0FFFFFFFFH); DraftFolder.tv.showBorder.Set(TRUE);
			DraftFolder.SetAsString(oldPreferences.DraftFolder^);
			p.AddContent(DraftFolder);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Use A Trash Bin: ");
			p.AddContent(label);
			NEW(UseATrashBin); UseATrashBin.bounds.SetWidth(20); UseATrashBin.alignment.Set(WMComponents.AlignLeft);
			IF oldPreferences.UseATrashBin THEN
				UseATrashBin.state.Set(1);
			ELSE
				UseATrashBin.state.Set(0);
			END;
			p.AddContent(UseATrashBin);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Trash Bin: ");
			p.AddContent(label);
			NEW(TrashBin); TrashBin.alignment.Set(WMComponents.AlignClient);
			TrashBin.multiLine.Set(FALSE); TrashBin.fillColor.Set(0FFFFFFFFH); TrashBin.tv.showBorder.Set(TRUE);
			TrashBin.SetAsString(oldPreferences.TrashBin^);
			p.AddContent(TrashBin);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(25); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("From Field: ");
			p.AddContent(label);
			NEW(From); From.alignment.Set(WMComponents.AlignClient);
			From.multiLine.Set(FALSE); From.fillColor.Set(0FFFFFFFFH); From.tv.showBorder.Set(TRUE);
			From.SetAsString(oldPreferences.From^);
			p.AddContent(From);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Expunge On Folder Change: ");
			p.AddContent(label);
			NEW(ExpungeOnFolderChange); ExpungeOnFolderChange.bounds.SetWidth(20); ExpungeOnFolderChange.alignment.Set(WMComponents.AlignLeft);
			IF oldPreferences.ExpungeOnFolderChange THEN
				ExpungeOnFolderChange.state.Set(1);
			ELSE
				ExpungeOnFolderChange.state.Set(0);
			END;
			p.AddContent(ExpungeOnFolderChange);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Expunge On Delete: ");
			p.AddContent(label);
			NEW(ExpungeOnDelete); ExpungeOnDelete.bounds.SetWidth(20); ExpungeOnDelete.alignment.Set(WMComponents.AlignLeft);
			IF oldPreferences.ExpungeOnDelete THEN
				ExpungeOnDelete.state.Set(1);
			ELSE
				ExpungeOnDelete.state.Set(0);
			END;
			p.AddContent(ExpungeOnDelete);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Use Drag'n'Drop as Move: ");
			p.AddContent(label);
			NEW(UseDragNDropAsMove); UseDragNDropAsMove.bounds.SetWidth(20); UseDragNDropAsMove.alignment.Set(WMComponents.AlignLeft);
			IF oldPreferences.UseDragNDropAsMove THEN
				UseDragNDropAsMove.state.Set(1);
			ELSE
				UseDragNDropAsMove.state.Set(0);
			END;
			p.AddContent(UseDragNDropAsMove);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignTop);
			p.bearing.Set(rect);
			NEW(label); label.bounds.SetWidth(200); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Expunge On Move: ");
			p.AddContent(label);
			NEW(ExpungeOnMove); ExpungeOnMove.bounds.SetWidth(20); ExpungeOnMove.alignment.Set(WMComponents.AlignLeft);
			IF oldPreferences.ExpungeOnMove THEN
				ExpungeOnMove.state.Set(1);
			ELSE
				ExpungeOnMove.state.Set(0);
			END;
			p.AddContent(ExpungeOnMove);
			panel.AddContent(p);
			
			NEW(p); p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignBottom);
			NEW(ok);
			ok.bounds.SetWidth(100); ok.alignment.Set(WMComponents.AlignRight);
			ok.caption.SetAOC("OK"); ok.onClick.Add(OKHandler);
			p.AddContent(ok);
			NEW(cancel);
			cancel.bounds.SetWidth(100); cancel.alignment.Set(WMComponents.AlignRight);
			cancel.caption.SetAOC("Cancel"); cancel.onClick.Add(CancelHandler);
			p.AddContent(cancel);
			panel.AddContent(p);
			RETURN panel;
		END CreateForm;
		
		PROCEDURE Close();
		BEGIN
			Close^();
			DecCount();
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN
					Close();
			ELSE
				Handle^(x);
			END;
		END Handle;
		
		PROCEDURE OKHandler(sender, data: ANY);
		VAR
			i: LONGINT;
			string: String;
			preferences: IMAPClient.AccountPreferences;
		BEGIN
			IF window # NIL THEN
				preferences := window.client.preferences;
				IMAPUtilities.TextToStr(SMTPServer.text, string);
				window.client.preferences.SMTPServer := string;
				IMAPUtilities.TextToStr(SMTPThisHost.text, string);
				preferences.SMTPThisHost := string;
				IMAPUtilities.TextToStr(SentFolder.text, string);
				preferences.SentFolder := string;
				IMAPUtilities.TextToStr(DraftFolder.text, string);
				preferences.DraftFolder := string;
				IMAPUtilities.TextToStr(TrashBin.text, string);
				preferences.TrashBin := string;
				IMAPUtilities.TextToStr(From.text, string);
				preferences.From := string;
				
				i := ExpungeOnFolderChange.state.Get();
				preferences.ExpungeOnFolderChange := (i=1);
				i := ExpungeOnDelete.state.Get();
				preferences.ExpungeOnDelete := (i=1);
				i := UseDragNDropAsMove.state.Get();
				preferences.UseDragNDropAsMove := (i=1);
				i := ExpungeOnMove.state.Get();
				preferences.ExpungeOnMove := (i=1);
				i := UseATrashBin.state.Get();
				preferences.UseATrashBin := (i=1);
			ELSE
				OutputError("Updating Preferences not possible, because Client is not initialized");
			END;
			Close^();
		END OKHandler;
		
		PROCEDURE CancelHandler(sender, data: ANY);
		BEGIN
			Close^;
		END CancelHandler;	
	END PreferencesWindow;
	
	Window = OBJECT (WMComponents.FormWindow)
	VAR
		topToolbar, messagePanel : WMStandardComponents.Panel;
		statusLabel, currentFolderLabel, currentMessagesLabel: WMStandardComponents.Label;
		connect, disconnect, reload, abort, search, save, load, new, expunge, preferences, download, switchToOffline, switchToOnline: WMStandardComponents.Button;
		messageGrid : WMStringGrids.StringGrid;
		folderTree: WMTrees.TreeView;
		tree: WMTrees.Tree;
		colWidths : WMGrids.Spacings;
		address: WMEditors.Editor;
		popup: WMPopups.Popup; 
		px, py : LONGINT;
		IconRead, IconAnswered, IconUnread, IconDeleted: WMGraphics.Image;
		copyTarget: IMAPClient.Folder;
		client: IMAPClient.Client;
		timer: AosKernel.Timer;
		updateFlag: BOOLEAN;
		active: BOOLEAN;
		
		PROCEDURE &New(c: WMRestorable.Context);
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			NEW(client, RefreshDisplay, OutputError);
			vc := CreateForm();
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("IMAPClient"));
			active := TRUE;
			updateFlag := FALSE;
			copyTarget := NIL;
			IconRead := WMGraphics.LoadImage("IMAPIcons.tar://IMAPIconRead.png", FALSE);
			IconAnswered := WMGraphics.LoadImage("IMAPIcons.tar://IMAPIconAnswered.png", FALSE);
			IconUnread := WMGraphics.LoadImage("IMAPIcons.tar://IMAPIconUnread.png", FALSE);
			IconDeleted := WMGraphics.LoadImage("IMAPIcons.tar://IMAPIconDeleted.png", FALSE);
			IF DEBUG THEN AosOut.String("Window initialisiert"); AosOut.Ln(); END;
			IncCount();
			IF c # NIL THEN
				WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame});
				Resized(GetWidth(), GetHeight());
			ELSE
				WMWindowManager.DefaultAddWindow(SELF);
			END;
		END New;
		
		(* Wird aufgerufen, wenn das Fenster seine Groesse aendert *)
		PROCEDURE Resized(width, height : LONGINT);
		BEGIN
			Resized^(width, height);
			ResizeGrid;
		END Resized;
	
		PROCEDURE ResizeGrid;
		BEGIN
			IF LEN(colWidths) = 4 THEN
				NEW(colWidths, 4);				
				colWidths[0] := (messageGrid.bounds.GetWidth() DIV 8)*2;
				colWidths[1] := (messageGrid.bounds.GetWidth() DIV 8)*3;
				colWidths[2] := messageGrid.bounds.GetWidth() DIV 4;	
				colWidths[3] := messageGrid.bounds.GetWidth() DIV 8;
			ELSE
				NEW(colWidths, 1);				
				colWidths[0] := messageGrid.bounds.GetWidth();
			END;
			messageGrid.SetColSpacings(colWidths);
		END ResizeGrid;
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			label : WMStandardComponents.Label;
			p: WMStandardComponents.Panel;
			rect: WMRectangles.Rectangle;
			root: WMTrees.TreeNode;
		BEGIN
			rect := WMRectangles.MakeRect(2,3,0,3);
			NEW(panel); panel.bounds.SetExtents(1024, 768); panel.fillColor.Set(WMGraphics.White);
			
			(* --- Toolbar --- *)		
			NEW(topToolbar); topToolbar.bounds.SetHeight(78); topToolbar.alignment.Set(WMComponents.AlignTop);
			topToolbar.fillColor.Set(0CCCCCCFFH); 
			panel.AddContent(topToolbar);
			
			NEW(p); p.bounds.SetHeight(26); p.alignment.Set(WMComponents.AlignTop);
			topToolbar.AddContent(p);
			
			NEW(label); label.bounds.SetWidth(40); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC("Host: "); label.textColor.Set(0000000FFH); label.bearing.Set(rect); p.AddContent(label);			
	
			NEW(address); address.bounds.SetWidth(160); address.alignment.Set(WMComponents.AlignLeft);
			address.multiLine.Set(FALSE); address.fillColor.Set(0FFFFFFFFH); address.bearing.Set(rect); address.tv.showBorder.Set(TRUE);
			address.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1));
			address.onEnter.Add(ButtonHandler);
			p.AddContent(address);
			IMAPUtilities.SetEditorText(address, client.preferences.IMAPServer);
			
			NEW(connect); connect.bounds.SetWidth(100); connect.alignment.Set(WMComponents.AlignLeft);
			connect.caption.SetAOC("Connect"); connect.bearing.Set(rect); connect.onClick.Add(ButtonHandler);
			p.AddContent(connect);
			NEW(disconnect); disconnect.bounds.SetWidth(100); disconnect.alignment.Set(WMComponents.AlignLeft);
			disconnect.caption.SetAOC("Disconnect"); disconnect.bearing.Set(rect); disconnect.onClick.Add(ButtonHandler);
			p.AddContent(disconnect);
			NEW(save); save.bounds.SetWidth(100); save.alignment.Set(WMComponents.AlignLeft);
			save.caption.SetAOC("Save Account"); save.bearing.Set(rect); save.onClick.Add(ButtonHandler);
			p.AddContent(save);
			NEW(load); load.bounds.SetWidth(100); load.alignment.Set(WMComponents.AlignLeft);
			load.caption.SetAOC("Load Account"); load.bearing.Set(rect); load.onClick.Add(ButtonHandler);
			p.AddContent(load);
			NEW(switchToOffline); switchToOffline.bounds.SetWidth(100); switchToOffline.alignment.Set(WMComponents.AlignLeft);
			switchToOffline.caption.SetAOC("Switch To Offline"); switchToOffline.bearing.Set(rect); switchToOffline.onClick.Add(ButtonHandler);
			p.AddContent(switchToOffline);
			NEW(switchToOnline); switchToOnline.bounds.SetWidth(100); switchToOnline.alignment.Set(WMComponents.AlignLeft);
			switchToOnline.caption.SetAOC("Switch To Online"); switchToOnline.bearing.Set(rect); switchToOnline.onClick.Add(ButtonHandler);
			p.AddContent(switchToOnline);
			NEW(preferences); preferences.bounds.SetWidth(100); preferences.alignment.Set(WMComponents.AlignLeft);
			preferences.caption.SetAOC("Preferences"); preferences.bearing.Set(rect); preferences.onClick.Add(ButtonHandler);
			p.AddContent(preferences);
			
			NEW(p); p.bounds.SetHeight(26); p.alignment.Set(WMComponents.AlignTop);
			topToolbar.AddContent(p);
			
			NEW(new); new.bounds.SetWidth(100); new.alignment.Set(WMComponents.AlignLeft);
			new.caption.SetAOC("Send new"); new.bearing.Set(rect);new.onClick.Add(ButtonHandler);
			p.AddContent(new);
			NEW(reload); reload.bounds.SetWidth(100); reload.alignment.Set(WMComponents.AlignLeft);
			reload.caption.SetAOC("Reload"); reload.bearing.Set(rect); reload.onClick.Add(ButtonHandler);
			p.AddContent(reload);
			NEW(abort); abort.bounds.SetWidth(100); abort.alignment.Set(WMComponents.AlignLeft);
			abort.caption.SetAOC("Abort"); abort.bearing.Set(rect); abort.onClick.Add(ButtonHandler);
			p.AddContent(abort);
			NEW(search); search.bounds.SetWidth(100); search.alignment.Set(WMComponents.AlignLeft);
			search.caption.SetAOC("Search"); search.bearing.Set(rect); search.onClick.Add(ButtonHandler);
			p.AddContent(search);
			NEW(expunge); expunge.bounds.SetWidth(100); expunge.alignment.Set(WMComponents.AlignLeft);
			expunge.caption.SetAOC("Expunge"); expunge.bearing.Set(rect); expunge.onClick.Add(ButtonHandler);
			p.AddContent(expunge);
			NEW(download); download.bounds.SetWidth(100); download.alignment.Set(WMComponents.AlignLeft);
			download.caption.SetAOC("Load all messages"); download.bearing.Set(rect); download.onClick.Add(ButtonHandler);
			p.AddContent(download);
			
			NEW(p);
			p.bounds.SetHeight(26); p.alignment.Set(WMComponents.AlignTop);
			topToolbar.AddContent(p);
			
			(* --- currentMessagesLabel --- *)
			NEW(currentMessagesLabel);
			currentMessagesLabel.bounds.SetWidth(200);
			currentMessagesLabel.alignment.Set(WMComponents.AlignLeft);
			currentMessagesLabel.fillColor.Set(0CCCCCCFFH);
			currentMessagesLabel.caption.SetAOC("Current Messages: 0 ");
			currentMessagesLabel.bearing.Set(rect);
			p.AddContent(currentMessagesLabel);
			
			(* --- currentFolderLabel --- *)
			NEW(currentFolderLabel); 
			currentFolderLabel.alignment.Set(WMComponents.AlignClient); 
			currentFolderLabel.fillColor.Set(0CCCCCCFFH);
			currentFolderLabel.caption.SetAOC("Current Folder: "); 
			currentFolderLabel.bearing.Set(rect);
			p.AddContent(currentFolderLabel);
			
		
			(* --- statusbar --- *)
			NEW(p);
			p.bounds.SetHeight(20); p.alignment.Set(WMComponents.AlignBottom);
			p.fillColor.Set(0CCCCCCFFH);
			panel.AddContent(p);
			NEW(statusLabel); 
			statusLabel.bounds.SetHeight(20); 
			statusLabel.alignment.Set(WMComponents.AlignTop);
			statusLabel.bearing.Set(WMRectangles.MakeRect(3,0,0,0));
			statusLabel.textColor.Set(0000000FFH);
			statusLabel.SetCaption("Status: disconnected");
			p.AddContent(statusLabel);			
			
			(* --- folderPanel --- *)
			NEW(folderTree);
			folderTree.bounds.SetWidth(200);
			folderTree.alignment.Set(WMComponents.AlignLeft);
			folderTree.bearing.Set(WMRectangles.MakeRect(3,3,0,0));
			folderTree.fillColor.Set(WMGraphics.White);
			folderTree.onClickNode.Add(ChangeFolder);
			folderTree.SetExtContextMenuHandler(FolderContextMenu);
			folderTree.SetExtDragDroppedHandler(MessagesDragDropped);
			tree := folderTree.GetTree();
			tree.Acquire();
			NEW(root);
			tree.SetRoot(root);
			tree.SetNodeCaption(root, Utilities.NewString("Folders"));
			tree.Release();
			panel.AddContent(folderTree);
			
			(* --- messagePanel --- *)
			NEW(messagePanel);
			messagePanel.alignment.Set(WMComponents.AlignClient);
			messagePanel.bounds.SetWidth(824);
			messagePanel.fillColor.Set(0CCCCCCFFH);
			panel.AddContent(messagePanel);
			
			NEW(messageGrid);
			messageGrid.alignment.Set(WMComponents.AlignClient);

			messageGrid.bounds.SetWidth(824);
			messageGrid.onClickSelected.Add(DisplayMessage);
			messageGrid.SetExtContextMenuHandler(MessageContextMenu);
			messageGrid.onStartDrag.Add(MessagesStartDrag);
			messageGrid.fillColor.Set(WMGraphics.White);
			
			NEW(colWidths, 1);							
			colWidths[0] := messageGrid.bounds.GetWidth(); 
	
			messageGrid.model.Acquire;
			messageGrid.SetColSpacings(colWidths);   
			messageGrid.model.SetNofCols(1);
			messageGrid.model.SetNofRows(1);
			messageGrid.fixedRows.Set(1);
			messageGrid.clFixed.Set(0C0C0C0FFH);
			messageGrid.model.SetCellText(0, 0, Utilities.NewString(""));
			messageGrid.SetSelectionMode(WMGrids.GridSelectRows);
			messageGrid.showScrollX.Set(FALSE);
			messageGrid.alwaysShowScrollX.Set(FALSE);
			messageGrid.alwaysShowScrollY.Set(FALSE);
			messageGrid.model.Release;
			
			messagePanel.AddContent(messageGrid);
			panel.AddContent(messagePanel);
			RETURN panel;
		END CreateForm;
		
		PROCEDURE ButtonHandler(sender, data: ANY);
		BEGIN
			IF sender = address THEN
				Connect();
			ELSIF sender = connect THEN
				Connect();
			ELSIF sender = disconnect THEN
				Disconnect();
			ELSIF sender = search THEN
				Search();
			ELSIF sender = reload THEN
				Reload();
			ELSIF sender = abort THEN
				Abort();
			ELSIF sender = save THEN
				Save();
			ELSIF sender = load THEN
				Load();
			ELSIF sender = new THEN
				NewSend();
			ELSIF sender = expunge THEN
				Expunge();
			ELSIF sender = preferences THEN
				SetPreferences();
			ELSIF sender = download THEN
				DownloadAllMessages();
			ELSIF sender = switchToOffline THEN
				SwitchToOffline();
			ELSIF sender = switchToOnline THEN
				SwitchToOnline();
			ELSE
				OutputError("An Unknown Button was pressed");
			END;
		END ButtonHandler;
		
		PROCEDURE DisplayMessage(sender, data: ANY);
		VAR
			message: IMAPClient.Message;
			mw: MessageWindow;
			i: LONGINT;
		BEGIN
			IF (data # NIL) & (data IS IMAPClient.Message) THEN
				message := data(IMAPClient.Message);
				IF (message.message = NIL) & (client.status = IMAPClient.ONLINE) THEN
					client.abort := TRUE;
					i := client.FetchMessage(message);
					client.abort := FALSE;
					client.timer.Wakeup();
				END;
				IF DEBUG THEN AosOut.String("Display Message "); AosOut.Int(i,0); AosOut.Ln(); END;
				NEW(mw, SELF);
				mw.DisplayMessage(message);
			ELSE
				OutputError("Display Message NOT possible because your selection was invalid");
			END;			
		END DisplayMessage;
		
		PROCEDURE ChangeFolder(sender, data: ANY);
		VAR
			folder: IMAPClient.Folder;
			treeNode: WMTrees.TreeNode;
			p: PTR;
			i: LONGINT;
		BEGIN 
			IF (data # NIL) & (data IS WMTrees.TreeNode) THEN
				treeNode := data(WMTrees.TreeNode);
				p := tree.GetNodeData(treeNode);
				IF p = NIL THEN RETURN; END;
				folder := p(IMAPClient.Folder);
				IF DEBUG THEN AosOut.String("Change Folder: folder name: "); AosOut.String(folder.name^); AosOut.Ln(); END;
				client.userAbort := FALSE;
				client.abort := TRUE;
				i := client.SelectFolder(folder);
				client.abort := FALSE;
				client.timer.Wakeup();
				client.applySearchFilter := FALSE;
			END;
			messageGrid.Acquire;
			messageGrid.SetTopPosition(0,0,TRUE);
			messageGrid.Release;
			RefreshDisplay();
		END ChangeFolder;
		
		PROCEDURE FolderContextMenu(sender : ANY; x, y: LONGINT);
		VAR 
			p: PTR;
			folder: IMAPClient.Folder;
			selected: WMTrees.TreeNode;			
		BEGIN
			(* find selected Node *)
			selected := folderTree.GetNodeAtPos(x,y);
			tree.Acquire;
			p := tree.GetNodeData(selected);
			IF p # NIL THEN
				folder := p(IMAPClient.Folder);
				IF DEBUG THEN AosOut.String("Folder Name: "); AosOut.String(folder.name^); AosOut.Ln(); END;
				NEW(popup);
				popup.AddParButton("Create Sub-Folder", CreateDir, folder);
				popup.AddParButton("Rename", RenameDir, folder);
				popup.AddParButton("Delete", DeleteDir, folder);
				popup.AddParButton("Select as Copy-Target", TargetDir, folder);
				popup.AddParButton("Select as Sent Folder", SentFolder, folder);
				popup.AddParButton("Select as Draft Folder", DraftFolder, folder);
				popup.AddParButton("Select as Trash Bin", TrashBin, folder);
				folderTree.ToWMCoordinates(x, y, px, py);
				popup.Popup(px, py);
			ELSE
				IF DEBUG THEN AosOut.String("No Folder Selected"); AosOut.Ln(); END;
			END;
			tree.Release;
		END FolderContextMenu;
		
		PROCEDURE CreateDir(sender, data: ANY);
		VAR
			name : ARRAY 128 OF CHAR;
			folder: IMAPClient.Folder;
			r: LONGINT;
		BEGIN
			IF (data # NIL) & (data IS IMAPClient.Folder) THEN
				folder := data(IMAPClient.Folder);
				COPY("NewFolder", name);
				IF WMDialogs.QueryString("Create Folder: ", name) = WMDialogs.ResOk THEN
					IF DEBUG THEN AosOut.String("Creating Folder: "); AosOut.String(name); AosOut.Ln; END;
					client.abort := TRUE;
					r := client.Create(folder, name);
					client.abort := FALSE;
					RefreshDisplay();
				END;
			END;
		END CreateDir;
		
		PROCEDURE RenameDir(sender, data: ANY);
		VAR 
			folder: IMAPClient.Folder;
			name : ARRAY 128 OF CHAR;
			r: LONGINT;
		BEGIN
			IF (data # NIL) & (data IS IMAPClient.Folder) THEN
				folder := data(IMAPClient.Folder);
				
				COPY("NewName", name);
				IF WMDialogs.QueryString("Rename Folder: ", name) = WMDialogs.ResOk THEN
					IF DEBUG THEN AosOut.String("Renaming Folder: "); AosOut.String(folder.name^); AosOut.String(" to "); AosOut.String(name); AosOut.Ln; END;
					client.abort := TRUE;
					r := client.Rename(folder, name);
					client.abort := FALSE;
					client.timer.Wakeup();
					RefreshDisplay();
				END
			END;
		END RenameDir;
		
		PROCEDURE DeleteDir(sender, data: ANY);
		VAR
			folder: IMAPClient.Folder;
			r: LONGINT;
			buffer: Utilities.Buffer;
			w: AosIO.Writer;
			string: String;
		BEGIN
			IF (data # NIL) & (data IS IMAPClient.Folder) THEN
				folder := data(IMAPClient.Folder);
				NEW(buffer, 16);
				w := buffer.GetWriter();
				w.String("Do you want to delete the folder: ");
				w.String(folder.name^);
				string := buffer.GetString();
				r := WMDialogs.Message("Confirm deleting folder", string^, {WMDialogs.ResYes, WMDialogs.ResNo});
				IF r = WMDialogs.ResYes THEN
					client.abort := TRUE;
					r := client.Delete(folder);
					client.abort := FALSE;
					client.timer.Wakeup();
				END;
			END;
			RefreshDisplay();
		END DeleteDir;
		
		PROCEDURE TargetDir(sender, data: ANY);
		VAR
			path: String;
		BEGIN
			IF (data # NIL) & (data IS IMAPClient.Folder) THEN
				copyTarget := data(IMAPClient.Folder);
				path := copyTarget.GetPath();
				IF DEBUG THEN AosOut.String("Copy-Target selected: "); AosOut.String(path^); AosOut.Ln(); END;
			ELSE
				IF DEBUG THEN AosOut.String("No Copy-Target selected."); AosOut.Ln(); END;
			END;
		END TargetDir;
		
		PROCEDURE SentFolder(sender, data: ANY);
		VAR
			path: String;
			folder: IMAPClient.Folder;
		BEGIN
			IF (data # NIL) & (data IS IMAPClient.Folder) THEN
				folder := data(IMAPClient.Folder);
				path := folder.GetPath();
				client.preferences.SentFolder := path;
				IF DEBUG THEN AosOut.String("Sent Folder selected: "); AosOut.String(path^); AosOut.Ln(); END;
			ELSE
				IF DEBUG THEN AosOut.String("No Sent Folder selected."); AosOut.Ln(); END;
			END;
		END SentFolder;
		
		PROCEDURE DraftFolder(sender, data: ANY);
		VAR
			path: String;
			folder: IMAPClient.Folder;
		BEGIN
			IF (data # NIL) & (data IS IMAPClient.Folder) THEN
				folder := data(IMAPClient.Folder);
				path := folder.GetPath();
				client.preferences.DraftFolder := path;
				IF DEBUG THEN AosOut.String("Draft Folder selected: "); AosOut.String(path^); AosOut.Ln(); END;
			ELSE
				IF DEBUG THEN AosOut.String("No Draft Folder selected."); AosOut.Ln(); END;
			END;
		END DraftFolder;
		
		PROCEDURE TrashBin(sender, data: ANY);
		VAR
			path: String;
			folder: IMAPClient.Folder;
		BEGIN
			IF (data # NIL) & (data IS IMAPClient.Folder) THEN
				folder := data(IMAPClient.Folder);
				path := folder.GetPath();
				client.preferences.TrashBin := path;
				client.preferences.UseATrashBin := TRUE;
				IF DEBUG THEN AosOut.String("Trash Bin selected: "); AosOut.String(path^); AosOut.Ln(); END;
			ELSE
				IF DEBUG THEN AosOut.String("No Trash Bin selected."); AosOut.Ln(); END;
			END;
		END TrashBin;
		
		PROCEDURE MessagesDragDropped(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo; VAR handled : BOOLEAN);
		VAR
			selected: WMTrees.TreeNode;
			p: PTR;
			folder: IMAPClient.Folder;
			list: Classes.List;
			i, r: LONGINT;
			message: IMAPClient.Message;
			successful: BOOLEAN;
			path: String;
		BEGIN
			handled := TRUE;
			IF DEBUG THEN AosOut.String("MessagesDragDropped"); AosOut.Ln(); END;
			selected := folderTree.GetNodeAtPos(x,y);
			tree.Acquire;
			p := tree.GetNodeData(selected);
			tree.Release;
			
			IF p # NIL THEN
				folder := p(IMAPClient.Folder);
				IF DEBUG THEN AosOut.String("Folder Name: "); AosOut.String(folder.name^); AosOut.Ln(); END;
			ELSE
				IF DEBUG THEN AosOut.String("Folder NIL: "); AosOut.Ln(); END;
			END;
			p := dragInfo.data;
			IF p IS Classes.List THEN
				IF DEBUG THEN AosOut.String("Classes.List"); AosOut.Ln(); END;
				list := p(Classes.List);
				i := 0;
				client.abort := TRUE;
				successful := TRUE;
				WHILE i < list.GetCount() DO
					p := list.GetItem(i);
					message := p(IMAPClient.Message);
					path := folder.GetPath();
					r := client.CopyMessage(message, path);
					IF (r = IMAPClient.OK) & client.preferences.UseDragNDropAsMove THEN
						r := client.DeleteMessage(message, client.preferences.ExpungeOnMove);
					ELSE
						successful := FALSE;
					END;
					INC(i);
				END;
				IF successful & client.preferences.ExpungeOnMove THEN
					r := client.Expunge();
				END;
				client.abort := FALSE;
				client.timer.Wakeup();
			ELSE
				IF DEBUG THEN AosOut.String("Not Classes.List "); AosOut.Ln(); END;
			END;
		END MessagesDragDropped;
		
		PROCEDURE MessagesStartDrag(sender,data: ANY);
		VAR
			list: Classes.List;
			img : WMGraphics.Image;
			c : WMGraphics.BufferCanvas;
			top, i: LONGINT;
			p: PTR;
			message: IMAPClient.Message;
		BEGIN
			IF DEBUG THEN AosOut.String("In MessageStartDrag"); AosOut.Ln(); END;
			list := GetMessageSelection();
			(* render to bitmap *)
			NEW(img);	Raster.Create(img, 100, 200, Raster.BGRA8888);
			NEW(c, img);
			c.SetColor(0FFFF00FFH);
			top := 0;
			FOR i := 0 TO list.GetCount() - 1 DO
				c.Fill(WMRectangles.MakeRect(0, top, 100, top + 25), 0FF80H, WMGraphics.ModeCopy);
				p := list.GetItem(i);
				message := p(IMAPClient.Message);
				c.DrawString(3, top + 20, message.header.subject^);
				INC(top, 25)
			END;
			IF messageGrid.StartDrag(list, img, DragArrivedList, NIL) THEN 
				IF DEBUG THEN AosOut.String("DraggingStarted"); AosOut.Ln(); END;
			ELSE 
				IF DEBUG THEN AosOut.String("Drag could not be started"); AosOut.Ln(); END;
			END;
		END MessagesStartDrag;
		
		PROCEDURE DragArrivedList(sender, data : ANY);
		BEGIN
			IF DEBUG THEN AosOut.String("DragArrivedList"); AosOut.Ln(); END;
			IF sender = tree THEN
				AosOut.String("TREE"); AosOut.Ln();
			ELSE
				AosOut.String("Unknown"); AosOut.Ln();
			END;
			IF data IS Classes.List THEN
				AosOut.String("data vom Type List"); AosOut.Ln();
			ELSE
				AosOut.String("data nicht vom Type List"); AosOut.Ln();
			END;
		END DragArrivedList;
		
		PROCEDURE MessageContextMenu(sender : ANY; x, y: LONGINT);
		VAR 
			list: Classes.List;
		BEGIN	
			px := x; py := y;
			NEW(popup);
		
			list := GetMessageSelection();
			IF list.GetCount() > 0 THEN
				popup.AddParButton("Copy to Target", CopyMessages, list);
				popup.AddParButton("Delete", DeleteMessages, list);
				popup.AddParButton("Restore", RestoreMessages, list);	
			END;
			messageGrid.ToWMCoordinates(x, y, px, py);
			popup.Popup(px, py);
		END MessageContextMenu;
		
		PROCEDURE GetMessageSelection() : Classes.List;
		VAR selection : Classes.List;
			l, t, r, b, NofSel, i : LONGINT;
			p : ANY;
			message: IMAPClient.Message;
		BEGIN
			messageGrid.model.Acquire;
			messageGrid.GetSelection(l, t, r, b);
			NofSel:= b- t + 1;
			IF NofSel > 0 THEN
				NEW(selection);
				i := t;
				WHILE i <= b DO
					p := messageGrid.model.GetCellData(0, i);
					IF (p # NIL) & (p IS IMAPClient.Message) THEN
						message := p(IMAPClient.Message);
						selection.Add(message);
					END;
					INC(i);
				END;
			END;
			messageGrid.model.Release;
			RETURN selection
		END GetMessageSelection;
		
		PROCEDURE CopyMessages(sender, data: ANY);
		VAR
			list: Classes.List;
			i, r: LONGINT;
			p: PTR;
			message: IMAPClient.Message;
			path: String;
		BEGIN
			IF copyTarget # NIL THEN
				list := data(Classes.List);
				i := 0;
				client.abort := TRUE;
				WHILE i < list.GetCount() DO
					p := list.GetItem(i);
					message := p(IMAPClient.Message);
					path := copyTarget.GetPath();
					r := client.CopyMessage(message, path);
					INC(i);
				END;
				client.abort := FALSE;
				client.timer.Wakeup();
			ELSE
				OutputError("Copy NOT possible because there is no copy Target selected");
			END;
		END CopyMessages;
		
		PROCEDURE DeleteMessages(sender, data: ANY);
		VAR
			list: Classes.List;
			i, r: LONGINT;
			p: PTR;
			message: IMAPClient.Message;
		BEGIN
			list := data(Classes.List);
			IF list # NIL THEN
				i := 0;
				client.abort := TRUE;
				IF DEBUG THEN AosOut.String("Delete "); AosOut.Int(list.GetCount(),0); AosOut.String(" messages."); AosOut.Ln(); END;
				WHILE i < list.GetCount() DO
					p := list.GetItem(i);
					message := p(IMAPClient.Message);	
					IF (client.preferences.UseATrashBin) THEN
						r := client.MoveMessageToTrashBin(message);
					ELSE
						r := client.DeleteMessage(message, client.preferences.ExpungeOnDelete);
					END;
					INC(i);
				END;
				client.abort := FALSE;
				client.timer.Wakeup();
			END;
		END DeleteMessages;
		
		PROCEDURE RestoreMessages(sender, data: ANY);
		VAR
			list: Classes.List;
			i, r: LONGINT;
			p: PTR;
			message: IMAPClient.Message;
		BEGIN
			list := data(Classes.List);
			IF list # NIL THEN
				i := 0;
				client.abort := TRUE;
				IF DEBUG THEN AosOut.String("Restore "); AosOut.Int(list.GetCount(),0); AosOut.String(" messages."); AosOut.Ln(); END;
				WHILE i < list.GetCount() DO
					p := list.GetItem(i);
					message := p(IMAPClient.Message);
					r := client.RestoreMessage(message);
					INC(i);
				END;
				client.abort := FALSE;
				client.timer.Wakeup();
			END;
		END RestoreMessages;
		
		PROCEDURE Connect();
		VAR user, pass: ARRAY 1000 OF CHAR;
			host: String;
			r: LONGINT;
		BEGIN 	
			IMAPUtilities.TextToStr(address.text, host);
			IF (host^ = "") THEN 
				OutputError("Server not specified");
				RETURN;
			END;
			IMAPUtilities.StringCopy(client.preferences.UserName^, 0, IMAPUtilities.StringLength(client.preferences.UserName^), user);
			IF WMDialogs.QueryString("Enter Username:", user) = WMDialogs.ResOk THEN
				IF WMDialogs.QueryPassword("Enter Password", pass) = WMDialogs.ResOk THEN
					Disconnect();
					r := client.Connect(host^, user, pass);
				END;
			END;
		END Connect;
		
		PROCEDURE Disconnect();
		BEGIN
			client.abort := TRUE;
			client.Disconnect();
			client.abort := FALSE;
		END Disconnect;
		
		PROCEDURE Reload();
		BEGIN
			client.applySearchFilter := FALSE;
			client.userAbort := FALSE;
			client.abort := FALSE;
			client.timer.Wakeup();
		END Reload;
		
		PROCEDURE Abort();
		BEGIN
			client.userAbort := TRUE;
			client.abort := TRUE;
		END Abort;
		
		PROCEDURE Search();
		VAR
			sw: SearchWindow;
		BEGIN
			IF (client.status # IMAPClient.OK) & (client.status # IMAPClient.OFFLINE) THEN
				OutputError("Search not applicable because Client not connected.");
				RETURN;
			END;
			IF client.currentFolder.Noselect THEN
				OutputError("Search not applicable because Client not in Selected State.");
				RETURN;
			END;
			NEW(sw, SELF);
		END Search;
		
		PROCEDURE Save();
		VAR
			sw: SaveWindow;
			filename: String;
			doc: XML.Document;
			file: AosFS.File;
			fw: AosFS.Writer;
			r: LONGINT;	
		BEGIN
			IF (client.status # IMAPClient.ONLINE) & (client.status # IMAPClient.OFFLINE) THEN
				OutputError("Save is not applicable because you are disconnected");
				RETURN;
			END;
			NEW(sw);
			sw.GetAnswer(filename);
			IF filename = NIL THEN
				RETURN;
			END;
			
			r := client.Save(doc);
			IF DEBUG THEN AosOut.String("Save finished"); AosOut.Ln(); END;
			file := AosFS.New(filename^);
			IF file # NIL THEN
				AosFS.OpenWriter(fw, file, 0);
				doc.Write(fw, 0);		
				fw.Update();
				AosFS.Register(file);
				IF DEBUG THEN AosOut.String("Writing File successful"); AosOut.Ln(); 	END;
			ELSE
				OutputError("Writing File failed");
			END;		
		END Save;
		
		PROCEDURE NewSend();
		VAR
			mw: MessageWindow;
		BEGIN
			NEW(mw, SELF);
			mw.NewMessage();
		END NewSend;
		
		PROCEDURE Expunge();
		VAR
			r: LONGINT;
		BEGIN
			IF client.status = IMAPClient.ONLINE THEN
				r := WMDialogs.Message("Confirm Expunge", "Do you really want to expunge the deleted Messages?", {WMDialogs.ResYes, WMDialogs.ResNo});
				IF r = WMDialogs.ResYes THEN
					r := client.Expunge();
				END;
			END;
		END Expunge;
		
		PROCEDURE DownloadAllMessages();
		BEGIN
			IF client.status # IMAPClient.ONLINE THEN
				OutputError("The client is not online");
				RETURN;
			END;
			client.abort := FALSE;
			client.userAbort := FALSE;
			client.Task := IMAPClient.TLoadAllMessages;
			client.timer.Wakeup();
		END DownloadAllMessages;
		
		PROCEDURE SwitchToOffline();
		BEGIN
			client.SwitchToOffline();
		END SwitchToOffline;
		
		PROCEDURE SwitchToOnline();
		VAR
			pass: ARRAY 1000 OF CHAR;
		BEGIN
			IF DEBUG THEN 	AosOut.String("GUI: switch to online"); AosOut.Ln(); END;
			IF WMDialogs.QueryPassword("Enter Password", pass) = WMDialogs.ResOk THEN
				client.SwitchToOnline(pass);
			END;		
		END SwitchToOnline;
		
		PROCEDURE Load();
		VAR
			lw: LoadWindow;
			filename: String;
			offline: BOOLEAN;
			file: AosFS.File;
			fr: AosFS.Reader;
			string: String;
			r: LONGINT;
			scanner: XMLScanner.Scanner;
			parser: XMLParser.Parser;
			document: XML.Document;
			element: XML.Element;
			server, user: String;
			pass: ARRAY 1000 OF CHAR;
		BEGIN
			NEW(lw);
			lw.GetAnswer(filename, offline);
			IF filename # NIL THEN
				IF DEBUG THEN 	AosOut.String("start loading"); AosOut.Ln(); END;
				Disconnect();
				file := AosFS.Old(filename^);
				IF file # NIL THEN
					IF DEBUG THEN 	AosOut.String("start scanning and parsing..."); AosOut.Ln(); END;
					AosFS.OpenReader(fr, file, 0);
					NEW(scanner, fr);
					NEW(parser, scanner);
					document := parser.Parse();
					element := document.GetRoot();
					string := element.GetName();
					IF string^ # "account" THEN
						OutputError("The file is not compatible it doesn't start with the account tag");
						RETURN;
					END;
					
					IF offline THEN
						Disconnect();
						r := client.Load(document);
						RefreshDisplay();
					ELSE
						IF WMDialogs.QueryPassword("Enter Password", pass) = WMDialogs.ResOk THEN
							Disconnect();
							r := client.Load(document);
							IF r = IMAPClient.OK THEN
								server := client.preferences.IMAPServer;
								user := client.preferences.UserName;
								r := client.Connect(server^, user^, pass);
								IF DEBUG THEN 	AosOut.String("CONNECT RETURN = "); AosOut.Int(r,0); AosOut.Ln(); END;
								IMAPUtilities.SetEditorText(address, server);						
							END;
							RefreshDisplay();
						END;
					END;
				ELSE
					OutputError("Reading the file failed.");
				END;
			END;
		END Load;
		
		PROCEDURE SetPreferences();
		VAR
			pw: PreferencesWindow;
		BEGIN
			NEW(pw, SELF);
		END SetPreferences;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF(x.ext IS KillerMsg) THEN
					Close();
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("Window", "IMAPGUI.Restore", SELF, NIL);
				ELSE
					Handle^(x);
				END;
			ELSE
				Handle^(x);
			END;
		END Handle;
		
		PROCEDURE Close();
		BEGIN
			client.abort := TRUE;
			client.Close();
			active := FALSE;
			timer.Wakeup();
			Close^;
			DecCount();
		END Close;
		
		PROCEDURE DisplayCurrentFolder();
		BEGIN
			UpdateFolders();
			UpdateMessages();
			UpdateStatusLabels();
		END DisplayCurrentFolder;
		
		(* updates all the labels (statusLabel, currentFolderLabel, currentMessagesLabel) *)
		PROCEDURE UpdateStatusLabels();
		VAR
			status, currentWork, nofMessages: LONGINT;
			buffer: Utilities.Buffer;
			w: AosIO.Writer;
			string: String;
		BEGIN
			(* currentFolderLabel *)
			NEW(buffer, 16);
			w := buffer.GetWriter();
			w.String("Current Folder: ");
			IF IMAPUtilities.StringLength(client.currentFolder.path^) # 0 THEN
				w.String(client.currentFolder.path^);
				w.Char(client.currentFolder.hierarchyDelimiter);
			END;
			w.String(client.currentFolder.name^);
			string := buffer.GetString();
			currentFolderLabel.caption.SetAOC(string^);
			
			(* currentMessagesLabel *)
			NEW(buffer, 16);
			w := buffer.GetWriter();
			w.String("Current Messages: ");
			messageGrid.model.Acquire;
			nofMessages := messageGrid.model.GetNofRows() - 1;
			IF client.currentFolder.Noselect THEN
				nofMessages := 0;
			END;
			w.Int(nofMessages, 0);
			messageGrid.model.Release;
			string := buffer.GetString();
			currentMessagesLabel.caption.SetAOC(string^);
			
			(* statusLabel *)
			status := client.status;
			currentWork := client.currentWork;
			NEW(buffer, 16);
			w := buffer.GetWriter();
			w.String("Status: ");
			IF client.status = IMAPClient.ONLINE THEN
				w.String("online. ");
			ELSIF client.status = IMAPClient.OFFLINE THEN
				w.String("offline. ");
			ELSE
				w.String("disconnected. ");
			END;
			IF (status = IMAPClient.ONLINE) OR (status = IMAPClient.OFFLINE) THEN
				w.String("Current Work: ");
				IF currentWork = IMAPClient.CWFINISHED THEN
					w.String("Finished");
				ELSIF currentWork = IMAPClient.CWCONNECTING THEN
					w.String("Connecting...");
				ELSIF currentWork = IMAPClient.CWLOADING THEN
					w.String("Loading...");
				ELSIF currentWork = IMAPClient.CWCREATING THEN
					w.String("Creating Mailbox...");
				ELSIF currentWork = IMAPClient.CWRENAMING THEN
					w.String("Renaming Mailbox...");
				ELSIF currentWork = IMAPClient.CWDELETINGFOLDER THEN
					w.String("Deleting Mailbox...");	
				ELSIF currentWork = IMAPClient.CWSEARCHING THEN
					w.String("Searching...");	
				ELSIF currentWork = IMAPClient.CWCOPYING THEN
					w.String("Copying Message...");	
				ELSIF currentWork = IMAPClient.CWDELETINGMESSAGE THEN
					w.String("Deleting Message...");	
				ELSIF currentWork = IMAPClient.CWAPPENDING THEN
					w.String("Saving Message...");	
				ELSIF currentWork = IMAPClient.CWCLOSING THEN
					w.String("Closing Client...");	
				ELSIF currentWork = IMAPClient.CWSAVINGACCOUNT THEN
					w.String("Saving Account...");	
				ELSIF currentWork = IMAPClient.CWLOADINGACCOUNT THEN
					w.String("Loading Account...");	
				ELSIF currentWork = IMAPClient.CWPOLLING THEN
					w.String("Polling...");
				ELSIF currentWork = IMAPClient.CWEXPUNGING THEN
					w.String("Expunging...");
				ELSIF currentWork = IMAPClient.CWRESTORING THEN
					w.String("Restoring...");
				END;
			END;
			string := buffer.GetString();
			statusLabel.caption.SetAOC(string^);
		END UpdateStatusLabels;
		
		PROCEDURE UpdateFolders();
		VAR
			root: WMTrees.TreeNode;
			i: LONGINT;
			p: PTR;
			folder: IMAPClient.Folder;
			state: SET;
			
			PROCEDURE UpdateSub(parent: WMTrees.TreeNode; folder:IMAPClient.Folder);
			VAR
				node, child: WMTrees.TreeNode;
				i: LONGINT;
				sub: PTR;
				subFolder: IMAPClient.Folder;
				childData: PTR;
				childFolder: IMAPClient.Folder;
				present: BOOLEAN;
				name: String;
			BEGIN
				(* check if already present *)
				present := FALSE;
				child := tree.GetChildren(parent);
				WHILE (child # NIL) & (present = FALSE) DO
					childData := tree.GetNodeData(child);
					childFolder := childData(IMAPClient.Folder);
					IF childFolder = folder THEN
						present := TRUE;
						node := child;
					END;
					child := tree.GetNextSibling(child);
				END;
				(* add if not present *)
				IF present = FALSE THEN
					NEW(node);
					tree.AddChildNode(parent, node);
					name := IMAPUtilities.NewString(folder.name^);
					IMAPUtilities.replaceEncodedFolderName(name);
					tree.SetNodeCaption(node, name);
					tree.SetNodeData(node, folder);
				END;

				(* add Subfolders *)
				i := 0;
				WHILE i < folder.children.GetCount() DO
					sub := folder.children.GetItem(i);
					subFolder := sub(IMAPClient.Folder);
					UpdateSub(node, subFolder);
					INC(i);
				END;
				
				(* remove nodes that don't have a folder in the client's folderstructure anymore *)
				RemoveOldSubNodes(node);
			END UpdateSub;
			
			PROCEDURE RemoveOldSubNodes(node: WMTrees.TreeNode);
			VAR
				child, nextSibling: WMTrees.TreeNode;
				childFolder: IMAPClient.Folder;
				p: PTR;
				folder: IMAPClient.Folder;
				subFolders: Classes.List;
				subFolder: IMAPClient.Folder;
				i: LONGINT;
				found: BOOLEAN;
			BEGIN
				p := tree.GetNodeData(node);
				folder := p(IMAPClient.Folder);
				subFolders:= folder.children;
				child := tree.GetChildren(node);
				WHILE child # NIL DO
					p := tree.GetNodeData(child);
					childFolder := p(IMAPClient.Folder);
					found := FALSE;
					(* search corresponding folder *)
					i := 0;
					WHILE (i < subFolders.GetCount()) & ~found DO
						p := subFolders.GetItem(i);
						subFolder := p(IMAPClient.Folder);
						IF subFolder = childFolder THEN
							found := TRUE;
						END;
						INC(i);
					END;
					nextSibling := tree.GetNextSibling(child);
					IF ~found THEN
						tree.RemoveNode(child);
					END;
					child := nextSibling;
				END;
			END RemoveOldSubNodes;
			
		BEGIN
			tree.Acquire();
			root := tree.GetRoot();
			tree.SetNodeData(root, client.mailboxContent);
			state := {WMTrees.NodeAlwaysExpanded};
			tree.SetNodeState(root, state);
			i := 0;
			WHILE i < client.mailboxContent.children.GetCount() DO
				p := client.mailboxContent.children.GetItem(i);
				folder := p(IMAPClient.Folder);
				UpdateSub(root, folder);
				INC(i);
			END;
			RemoveOldSubNodes(root);
			tree.Release();	
		END UpdateFolders;
		
		PROCEDURE UpdateMessages();
		VAR
			i, count: LONGINT;
			message: IMAPClient.Message;
			messageP: PTR;
			header: IMAPClient.HeaderElement;
			list: Classes.List;
			address: IMAPUtilities.Address;
			addressP: PTR;
			buffer: Utilities.Buffer;
			w: AosIO.Writer;
			string: String;
			bResizeGrid: BOOLEAN;
			sortedList: Classes.SortedList;
			
			PROCEDURE Display(row: LONGINT; message: IMAPClient.Message);				
			BEGIN
				IF message.header # NIL THEN
					list := message.header.from;
					IF list # NIL THEN
						IF list.GetCount() > 0 THEN
							addressP := list.GetItem(0);
							address := addressP(IMAPUtilities.Address);
							IF address.realName^ # "" THEN
								IMAPUtilities.replaceEncodedHeaderWord(address.realName^);
								string := IMAPUtilities.NewString(address.realName^);
							ELSE
								NEW(buffer, 16);
								w := buffer.GetWriter();
								w.String("<");
								w.String(address.namePart^);
								w.String("@");
								w.String(address.domainPart^);
								w.String(">");
								string := buffer.GetString();
							END;
						ELSE
							string := Utilities.NewString("");
						END;
					ELSE
						string := Utilities.NewString("");
					END;
					messageGrid.model.SetCellText(0, row+1, string);
					IF message.flags.deleted THEN
						messageGrid.model.SetCellImage(0, row+1, IconDeleted);
					ELSE
						IF ~message.flags.seen THEN
							messageGrid.model.SetCellImage(0, row+1, IconUnread);
						ELSE
							IF message.flags.answered THEN
								messageGrid.model.SetCellImage(0, row+1, IconAnswered);
							ELSE
								messageGrid.model.SetCellImage(0, row+1, IconRead);
							END;
						END;
					END;
					messageGrid.model.SetCellData(0, row+1, message);		
					
					IF message.header.subject # NIL THEN
						IMAPUtilities.replaceEncodedHeaderWord(message.header.subject^);
						string := Utilities.NewString(message.header.subject^);
						messageGrid.model.SetCellText(1, row+1, string);
						messageGrid.model.SetCellData(1, row+1, message);
					END;
					IF message.internalDate # NIL THEN
						messageGrid.model.SetCellText(2, row+1, Utilities.NewString(message.internalDate^));
						messageGrid.model.SetCellData(2, row+1, message);
					END;
					NEW(buffer, 16);
					w := buffer.GetWriter();
					w.Int(message.size,0);
					string := buffer.GetString();
					messageGrid.model.SetCellText(3, row+1, string);
					messageGrid.model.SetCellData(3, row+1, message);
				END;
			END Display;
			
		BEGIN
			bResizeGrid := FALSE;
			IF client.currentFolder.Noselect THEN
				messageGrid.model.Acquire;
				IF messageGrid.model.GetNofCols() # 1 THEN
					bResizeGrid := TRUE;
					NEW(colWidths, 1);
					messageGrid.model.SetNofRows(2);
					messageGrid.model.SetNofCols(1); 
					messageGrid.model.SetCellText(0, 0, Utilities.NewString(""));
					messageGrid.model.SetCellData(0, 0, NIL);
					messageGrid.model.SetCellImage(0, 1, NIL);
					messageGrid.model.SetCellText(0, 1, Utilities.NewString("This Mailbox is not selectable and does not contain any mail."));
					messageGrid.model.SetCellData(0, 1, NIL);
				END;
				messageGrid.model.Release;
			ELSE
				messageGrid.model.Acquire;
				IF messageGrid.model.GetNofCols() # 4 THEN
					bResizeGrid := TRUE;
					NEW(colWidths, 4);
					messageGrid.model.SetNofCols(4); (* From, Subject, Date, Size *)
					messageGrid.model.SetNofRows(1);
					messageGrid.model.SetCellText(0, 0, Utilities.NewString("From"));
					messageGrid.model.SetCellData(0, 0, NIL);
					messageGrid.model.SetCellText(1, 0, Utilities.NewString("Subject"));
					messageGrid.model.SetCellData(1, 0, NIL);
					messageGrid.model.SetCellText(2, 0, Utilities.NewString("Date"));
					messageGrid.model.SetCellData(2, 0, NIL);
					messageGrid.model.SetCellText(3, 0, Utilities.NewString("Size"));
					messageGrid.model.SetCellData(3, 0, NIL);
					messageGrid.bounds.SetHeight(messageGrid.bounds.GetHeight()-20);
				END;
				messageGrid.model.Release;
				
				NEW(sortedList, IMAPClient.OldestFirst);
				IF client.applySearchFilter = TRUE THEN
					i := LEN(client.searchResult) -1;
					WHILE i >= 0 DO
						messageP := client.currentFolder.messages.GetItem(client.searchResult[i]);
						message := messageP(IMAPClient.Message);
						sortedList.Add(message);
						DEC(i);
					END;
				ELSE
					i := client.currentFolder.messages.GetCount() - 1;
					WHILE i >= 0 DO
						messageP := client.currentFolder.messages.GetItem(i);
						message := messageP(IMAPClient.Message);
						sortedList.Add(message);
						DEC(i);
					END;
				END;
				
				i := 0;
				count := 0;
				messageGrid.model.Acquire;
				IF sortedList.GetCount() = 0 THEN
					bResizeGrid := TRUE;
					messageGrid.model.SetNofRows(1);
					IF DEBUG THEN AosOut.String("keine Nachrichten"); AosOut.Ln(); END;
				END;
				WHILE i < sortedList.GetCount() DO
					messageP := sortedList.GetItem(i);
					message := messageP(IMAPClient.Message);
					header := message.header;
					
					IF (header # NIL) THEN
						messageGrid.model.SetNofRows(count + 2);
						Display(count, message);
						INC(count);
					END;
					INC(i);
				END;
				messageGrid.model.Release;				
			END;
			IF bResizeGrid THEN ResizeGrid(); END;
		END UpdateMessages;
		
		PROCEDURE RefreshDisplay();
		BEGIN
			updateFlag := TRUE;
			timer.Wakeup();
		END RefreshDisplay;
		
		BEGIN {ACTIVE} (* keepalive *)
		NEW(timer);
		WHILE active DO
			timer.Sleep(REFRESHTIME);
			IF DEBUG THEN AosOut.String("+"); END;
			IF (client.status = IMAPClient.DISCONNECTED) OR (client.status = IMAPClient.DEAD) THEN
				UpdateFolders();
				messageGrid.model.Acquire;
				NEW(colWidths, 1);				
				colWidths[0] := messageGrid.bounds.GetWidth();
				messageGrid.SetColSpacings(colWidths);
				messageGrid.model.SetNofRows(1);
				messageGrid.model.SetNofCols(1);
				messageGrid.model.SetCellText(0, 0, Utilities.NewString(""));
				messageGrid.model.Release;
				UpdateStatusLabels();
			ELSE
				WHILE updateFlag DO
					IF DEBUG THEN 	AosOut.Ln(); END;
					updateFlag := FALSE;
					DisplayCurrentFolder();
				END;
			END;
		END (* WHILE *);
		IF DEBUG THEN AosOut.String("Window Activity finished-------------------------------------------------------------------"); AosOut.Ln(); END;
	END Window;
	
PROCEDURE OutputError(error: ARRAY OF CHAR);
VAR
	r: LONGINT;
BEGIN
	r := WMDialogs.Message("ERROR", error, {WMDialogs.ResOk});
END OutputError;

PROCEDURE Open*(par: ANY): ANY;
VAR
	w: Window;
BEGIN
	NEW(w, NIL);
	RETURN NIL;
END Open;

PROCEDURE Restore*(par: ANY): ANY;
VAR
	w: Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(w, par(WMRestorable.Context));
	END;
	RETURN NIL;
END Restore;

PROCEDURE IncCount();
BEGIN {EXCLUSIVE}
	INC(nofWindows);
END IncCount;

PROCEDURE DecCount();
BEGIN {EXCLUSIVE}
	DEC(nofWindows);
END DecCount;

PROCEDURE Cleanup();
VAR
	die: KillerMsg;
	msg: WMMessages.Message;
	m: WMWindowManager.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die);
	msg.ext := die;
	msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END IMAPGUI.

IMAPGUI.Open ~

AosTools.FreeDownTo IMAPUtilities~ 