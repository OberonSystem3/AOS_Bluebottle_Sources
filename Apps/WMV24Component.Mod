MODULE WMV24Component; (** AUTHOR "TF/staubesv"; PURPOSE "Terminal"; *)
(**
 * History:
 *	19.01.2006	Adapted to AosSerials, added clear button, synchronize operations to V24Panel.open (staubesv)
 *	10.06.2006	Added YSend functionality, use AosXYModem.Mod instead of XModem.Mod, command button
 *	14.06.2006 	Busy loop removed, made window restorable (staubesv)
 *	15.06.2006	Support to paste to terminal window from clipboard, cursor always at the end of the text, keyboard focus indication, added scrollbar (staubesv)
 *	16.06.2006	Added SendCommand functionality (staubesv)
 *	21.06.2006	Improved error reporting (staubesv)
 *	22.06.2006	Added LineFeed and UseBackspace options, added status bar (staubesv)
 *	05.09.2006	Relay all keys to serial port, added copy&paste buttons since shortcuts are relayed to text view anymore, 
 *				don't send command if port is not open, configuration can be specified in AosConfig.XML (staubesv)
 *	25.09.2006	Added XY modem receive & echo capability (staubesv)
 *	20.02.2007	Better usability for selection, can send multiple files via XY-Modem protocol (staubesv)
 *
 * TODO:
 *
 * Sometimes, not all data that is received is displayed until the user sends a character to the device (The data is really receive, w.Char and w.Update
 * are both called but the content of the writer w are not displayed). FIX!
 *)

IMPORT
	AosOut, AosIO, AosConfig, AosTexts, AosTextUtilities, Utilities, 
	AosModules, AosKernel, AosSerials, AosXYModem, AosFS, AosInputs,
	WMWindowManager, WMMessages, WMRestorable, WMGraphics, WMRectangles,
	WMComponents, WMStandardComponents, WMProgressComponents, WMTextView, WMEditors, WMPopups, WMDialogs,
	XML, XMLObjects;
	
CONST

	(* Terminal Configuration - The default configuration is overriden by the configuration in AosConfig.XML if available *)

	(* Default size of window at start up *)
	DefaultWidth = 800; DefaultHeight = 400;
	
	(* Default serial port settings *)
	DefaultPort = 1;
	DefaultBps = 115200;
	DefaultDataBits = 8;
	DefaultParity = AosSerials.ParNo;
	DefaultStopBits = AosSerials.Stop1;
		
	(* If TRUE, the terminal panel is grey when it has no keyboard focus *)
	DefaultIndicateKeyboardFocus = TRUE;
	
	(* Display status bar with error & port status indication? *)
	DefaultShowStatusBar = TRUE;
	
	(* Send <CR><LF> when the user presses <CR>. Also send <CR><LF> instead of <CR> when sending commands *)
	DefaultLineFeed = FALSE;
	
	(* The window manager reports a DEL key pressed when pressing backspace. If TRUE, the terminal sends backspaces instead of deletes *)
	DefaultUseBackspace = TRUE;
	
	(* Should received characters be sent back? *)
	DefaultEcho = FALSE;
	
	(* Internal terminal configuration *)
	
	(* How often should the port status be polled? *)
	UpdateInterval = 200; (* ms *)
	
	ReceiveBufferSize = 1024;

	(* Trace Configuration *)

	TraceCharactersSent = {0};
	TraceCharactersReceived = {1};
	TraceNone = {};
	TraceAll = {0..31};

	Trace = TraceNone;
	
	(* Internal Constants *)
	
	Backspace = 08X;
	CR = 0DX;  
	LF = 0AX;  
	ESC = 1BX;
	DEL = 7FX;
	
	(* Lock *)
	Free = 0;
	Terminal = 1;
	DataTransfer = 2;
	
	ModuleName = "WMV24Component";
	
TYPE

	Settings = RECORD
		portSettings : ARRAY 64 OF CHAR;
		indicateKeyboardFocus : BOOLEAN;
		showStatusBar : BOOLEAN;
		linefeed : BOOLEAN;
		echo : BOOLEAN;
		useBackspace : BOOLEAN;
		xReceiveCommand, yReceiveCommand : Utilities.String;
		xSendCommand, ySendCommand : Utilities.String;
	END;
	
TYPE

	(* Recursive lock. This lock is used to provide exclusive access to the currently opened serial port to either
	 * the Terminal or data tranfer operation *)
	Lock = OBJECT
	VAR
		lock : LONGINT;
		locklevel : LONGINT;
		
		PROCEDURE TryAcquire(lock : LONGINT) : BOOLEAN;
		BEGIN {EXCLUSIVE}
			IF (SELF.lock # Free) & (SELF.lock # lock) THEN
				RETURN FALSE;
			ELSE
				TakeLock(lock);
				RETURN TRUE;
			END;
		END TryAcquire;
				
		PROCEDURE Acquire(lock : LONGINT);
		BEGIN {EXCLUSIVE}
			IF (SELF.lock # Free) & (SELF.lock # lock) THEN 
				AWAIT(SELF.lock=Free);
			END;
			TakeLock(lock);
		END Acquire;
		
		PROCEDURE Release;
		BEGIN {EXCLUSIVE}
			ASSERT(locklevel > 0);
			DEC(locklevel);
			IF locklevel = 0 THEN lock := Free; END;
		END Release;
		
		PROCEDURE TakeLock(lock : LONGINT);
		BEGIN (* only call from critical sections !*)
			IF SELF.lock = lock THEN
				INC(locklevel);
			ELSE
				SELF.lock := lock; locklevel := 1;
			END;
		END TakeLock;
		
		PROCEDURE &Init;
		BEGIN
			lock := Free; locklevel := 0;
		END Init;
	
	END Lock;
	
TYPE

	Command = POINTER TO RECORD
		name : ARRAY 64 OF CHAR;
		commandString : ARRAY 256 OF CHAR;
		next : Command;
	END;
	
TYPE
	
	ProgressInfo = OBJECT(WMComponents.VisualComponent)
	VAR
		progressBar : WMProgressComponents.ProgressBar;
		filenameLabel : WMStandardComponents.Label;
		progressLabel : WMStandardComponents.Label;
		currentBytes, maxBytes : LONGINT;
		
		w : AosIO.StringWriter; 
		string : ARRAY 128 OF CHAR;
		
		PROCEDURE SetProgress(progress : LONGINT);
		BEGIN
			w.Reset;
			w.String("Received "); w.Int(progress, 0);
			IF maxBytes > 0 THEN
				w.String(" of "); w.Int(maxBytes, 0); w.String(" Bytes");
				progressBar.cur.Set(progress);
			ELSE
				w.String(" Bytes");
			END;
			w.Get(string);
			progressLabel.caption.SetAOC(string);
		END SetProgress;
		
		PROCEDURE &New(filename : ARRAY OF CHAR; length : LONGINT);
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			Init^;
			NEW(w, 128);
			currentBytes := 0; maxBytes := length;
			
			NEW(panel); panel.fillColor.Set(0FFFFFFFFH); panel.bounds.SetExtents(300, 60); panel.alignment.Set(WMComponents.AlignClient);
			AddContent(panel);
			
			NEW(filenameLabel); filenameLabel.bounds.SetHeight(20); filenameLabel.alignment.Set(WMComponents.AlignTop);
			filenameLabel.caption.SetAOC(filename);
			panel.AddContent(filenameLabel);
			
			NEW(progressLabel); progressLabel.bounds.SetHeight(20); progressLabel.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(progressLabel);
					
			IF maxBytes > 0 THEN
				NEW(progressBar); progressBar.bounds.SetHeight(20); progressBar.alignment.Set(WMComponents.AlignTop);
				progressBar.SetRange(0, maxBytes);
				panel.AddContent(progressBar);
			END;
			
			SetProgress(0);
		END New;
		
	END ProgressInfo;
	
TYPE

	(* The cursor position of this textview cannot be changed using the mouse pointer *)
	CustomTextView = OBJECT(WMTextView.TextView)
	VAR
		selecting, selectWords, dragPossible  : BOOLEAN;
		lastPos : LONGINT;
		downX, downY : LONGINT;
		
		utilreader : AosTexts.TextReader; 
		
		text : AosTexts.Text;
		
		PROCEDURE SetText(text : AosTexts.Text);
		BEGIN
			SetText^(text);
			SELF.text := text;
			NEW(utilreader, text);
		END SetText;
		
		PROCEDURE PointerDown*(x, y : LONGINT; keys : SET);
		VAR pos : LONGINT;
		BEGIN
			IF keys * {0, 1, 2} = {2} THEN 
				ShowContextMenu(x, y) END;
			IF 0 IN keys THEN
				text.AcquireRead;
				ViewToTextPos(x, y, pos);
				dragPossible := FALSE; selectWords := FALSE;
				IF pos >= 0 THEN
					selection.Sort;
					IF (pos >= selection.a) & (pos < selection.b) THEN
						dragPossible := TRUE; downX := x; downY := y
					ELSE
						(* clicking the same position twice --> Word Selection Mode *)
						IF pos = lastPos THEN
							selectWords := TRUE;
							selection.SetFromTo(AosTextUtilities.FindPosWordLeft(utilreader, pos - 1), 
									AosTextUtilities.FindPosWordRight(utilreader, pos + 1))
						ELSE
							selection.SetFromTo(pos, pos) (* reset selection *)
						END;
						selecting := TRUE
					END
				END;
				lastPos := pos;
				text.ReleaseRead;
			END;
		END PointerDown;
	
		PROCEDURE PointerMove*(x, y : LONGINT; keys : SET);
		CONST DragDist = 5;
		VAR pos : LONGINT;
		BEGIN
			IF dragPossible THEN
				IF (ABS(x - downX) > DragDist) OR (ABS(y - downY) > DragDist) THEN dragPossible := FALSE; AutoStartDrag END
			ELSE
				IF selecting THEN 
					text.AcquireRead;
					ViewToTextPos(x, y, pos);
					IF selecting THEN
						IF selectWords THEN
							IF pos < selection.from.GetPosition() THEN pos := AosTextUtilities.FindPosWordLeft(utilreader, pos - 1);
							ELSE pos := AosTextUtilities.FindPosWordRight(utilreader, pos + 1)
							END;
							selection.SetTo(pos)
						ELSE
							selection.SetTo(pos);
						END;						
						AosTexts.SetLastSelection(text, selection.from, selection.to);
					END;
					text.ReleaseRead; 
				END;
			END
		END PointerMove;
		
		PROCEDURE PointerUp*(x, y : LONGINT; keys : SET);
		BEGIN
			selecting := FALSE; 
			IF dragPossible THEN selection.SetFromTo(0, 0); AosTexts.ClearLastSelection (* reset selection *) END;
			dragPossible := FALSE
		END PointerUp;
		
	END CustomTextView;

TYPE

	TerminalComponent = OBJECT(WMComponents.VisualComponent)
	VAR 
		settings : Settings;
	
		(* Access to serial port *)
		in : AosIO.Reader; 
		out : AosIO.Writer;
		
		port : AosSerials.Port;
		portNr, bps, databits, parity, stop : LONGINT;
		open : BOOLEAN;

		lock : Lock;
				
		(* Terminal window text writer *)
		w : AosIO.Writer;
		
		textView : CustomTextView;
		text : AosTexts.Text;
		
		(* Upper Toolbar *)
		opencloseBtn : WMStandardComponents.Button;
		settingsEdit : WMEditors.Editor;
		sendXBtn, sendYBtn : WMStandardComponents.Button;		
		receiveXBtn, receiveYBtn : WMStandardComponents.Button;
		
		(* Lower Toolbar *)
		lowerToolBar : WMStandardComponents.Panel;
		sendCommandBtn : WMStandardComponents.Button;
		sendCommandEditor : WMEditors.Editor;
		commandPopup : WMPopups.Popup; (* can be NIL *)
		commandMenuBtn : WMStandardComponents.Button;
		
		(* Status Bar *)
		status : WMStandardComponents.Label;
		dsr : WMStandardComponents.Label;
		clearStatusBtn : WMStandardComponents.Button;
		
		(* Error Counters *)
		overrunErrors, framingErrors, parityErrors, breakInterrupts, transportErrors, otherErrors : LONGINT;
		
		statusUpdater : StatusUpdater;
		
		running : BOOLEAN;
		timer : AosKernel.Timer;
			
		PROCEDURE HandleCommandMenuButton(sender, data : ANY);
		VAR buttonBounds, panelBounds: WMRectangles.Rectangle; gx, gy : LONGINT;
		BEGIN
			buttonBounds := commandMenuBtn.bounds.Get();
			panelBounds := bounds.Get();
			ToWMCoordinates(panelBounds.l + buttonBounds.l, panelBounds.t + buttonBounds.b, gx, gy);
			commandPopup.Popup(gx,gy);
		END HandleCommandMenuButton;
		
		PROCEDURE HandleCommandPopup(sender, data : ANY);
		VAR command : Command;
		BEGIN
			IF (data # NIL) & (data IS Command) & open THEN
				command := data (Command);
				lock.Acquire(Terminal);
				out.String(command.commandString); out.Char(CR); 
				IF settings.linefeed THEN out.Char(LF); END;
				out.Update;
				lock.Release;
			END;
		END HandleCommandPopup;
			
		PROCEDURE HandleSendCommandButton(sender, data : ANY);
		VAR commandString : ARRAY 1024 OF CHAR;
		BEGIN
			sendCommandEditor.GetAsString(commandString);
			IF open & (commandString # "") THEN
				lock.Acquire(Terminal);
				out.String(commandString); out.Char(CR); 
				IF settings.linefeed THEN out.Char(LF); END;
				out.Update;
				lock.Release;
				sendCommandEditor.SetAsString("");
			END;
		END HandleSendCommandButton;
		
		PROCEDURE HandleClearStatusButton(sender, data : ANY);
		BEGIN
			ResetStatus;
		END HandleClearStatusButton;
		
		PROCEDURE HandleClearButton(sender, data : ANY);
		BEGIN
			text.AcquireWrite;
			text.Delete(0, text.GetLength());
			textView.firstLine.Set(0); textView.cursor.SetPosition(0);
			text.ReleaseWrite
		END HandleClearButton;
		
		PROCEDURE HandleCopyButton(sender, data : ANY);
		BEGIN
			textView.CopySelection;
		END HandleCopyButton;
		
		PROCEDURE HandlePasteButton(sender, data : ANY);
		BEGIN
			CopyFromClipboard;
		END HandlePasteButton;
		
		PROCEDURE HandleXYButtons(sender, data : ANY);
		VAR
			button : WMStandardComponents.Button;
			command : Utilities.String;
			filename, msg : ARRAY 512 OF CHAR;
			filenames : Utilities.StringArray;
			mode, i, res : LONGINT;
			send : BOOLEAN;
		BEGIN
			IF sender IS WMStandardComponents.Button THEN
				button := sender (WMStandardComponents.Button);
				IF button = sendXBtn THEN
					mode := AosXYModem.XModem; send := TRUE;
				ELSIF button = receiveXBtn THEN
					mode := AosXYModem.XModem; send := FALSE;
				ELSIF button = sendYBtn THEN
					mode := AosXYModem.YModem; send := TRUE;
				ELSIF button = receiveYBtn THEN
					mode := AosXYModem.YModem; send := FALSE;
				ELSE
					HALT(99);
				END;
			ELSE
				HALT(99);
			END;
						
			IF ~open THEN
				res := WMDialogs.Message("Error", "Port is not open", {WMDialogs.ResOk});
				RETURN;
			END;
			
			IF send THEN msg := "File to send:"; ELSE msg := "File to receive:"; END;
			
			IF WMDialogs.QueryString(msg, filename) = WMDialogs.ResOk THEN
			
				filenames := Utilities.Split(filename, ";");
				
				command := GetXYCommand(send, mode);
				
				IF (LEN(filenames) > 1) & (command = NIL) THEN
					res := WMDialogs.Message("Error", "Multiple files can only be sent if send command is specified", {WMDialogs.ResOk});
				ELSE
					FOR i := 0 TO LEN(filenames)-1 DO
						Utilities.TrimWS(filenames[i]^);
						IF command # NIL THEN SendXYCommand(send, command^, filenames[i]^); END;
						IF send THEN
							SendXYModem(filenames[i]^, mode);
						ELSE
							ReceiveXYModem(filenames[i]^, mode);
						END;
					END;
				END;				
			END;
		END HandleXYButtons;
		
		PROCEDURE ExtKeyPressed*(ucs : LONGINT; flags : SET; VAR keySym : LONGINT; VAR handled : BOOLEAN);
		BEGIN
			textView.SetFlags(flags);
			handled := TRUE;
			IF (ucs > 0) & (ucs < 256) THEN	
				IF open & ~(AosInputs.Release IN flags) THEN				
					IF lock.TryAcquire(Terminal) THEN
						IF Trace * TraceCharactersSent # {} THEN Show("Sending character: "); AosOut.Int(ucs, 0); AosOut.Ln; END;
						IF ucs > 127 THEN (* Escape non-ascii characters *)
							out.Char(ESC); out.Char("["); ucs := ucs - 128;				
						END;
						IF settings.linefeed & (ucs = ORD(CR)) THEN
							out.Char(CR); out.Char(LF); out.Update;
						ELSIF settings.useBackspace & (ucs = ORD(DEL)) THEN
							out.Char(Backspace); out.Update;
						ELSE
							out.Char(CHR(ucs)); out.Update;
						END;
						lock.Release;
					ELSE
						(* ignore characters *)
					END;
				END;
			END;
		END ExtKeyPressed;
		
		PROCEDURE ExtFocus(hasFocus : BOOLEAN);
		BEGIN
			IF hasFocus THEN
				FocusReceived;
				IF settings.indicateKeyboardFocus THEN textView.fillColor.Set(00H); END;
			ELSE
				FocusLost;
				IF settings.indicateKeyboardFocus THEN textView.fillColor.Set(0CCCCCCCCH); END;
			END;
		END ExtFocus;
		
		PROCEDURE CreateUpperToolBar() : WMComponents.VisualComponent;
		VAR toolbar : WMStandardComponents.Panel; label : WMStandardComponents.Label; button : WMStandardComponents.Button;
		BEGIN
			NEW(toolbar);
			toolbar.alignment.Set(WMComponents.AlignTop); toolbar.bounds.SetHeight(20);
			toolbar.fillColor.Set(0E0E0E0FFH);

			NEW(label);	
			label.alignment.Set(WMComponents.AlignLeft); label.bounds.SetWidth(50);
			label.caption.SetAOC(" Settings:");
			toolbar.AddContent(label);
		
			NEW(settingsEdit); 
			settingsEdit.alignment.Set(WMComponents.AlignLeft); settingsEdit.bounds.SetWidth(110);
			settingsEdit.multiLine.Set(FALSE);
			settingsEdit.fillColor.Set(WMGraphics.White);
			settingsEdit.tv.borders.Set(WMRectangles.MakeRect(4, 3, 2, 2));
			settingsEdit.tv.showBorder.Set(TRUE);
			settingsEdit.SetAsString(settings.portSettings);
			toolbar.AddContent(settingsEdit);

			(* open/close *)
			NEW(opencloseBtn);
			opencloseBtn.alignment.Set(WMComponents.AlignLeft);
			opencloseBtn.takesFocus.Set(FALSE);
			opencloseBtn.caption.SetAOC("Open");
			opencloseBtn.onClick.Add(ToggleOpen);
			toolbar.AddContent(opencloseBtn);
			
			NEW(label);	
			label.alignment.Set(WMComponents.AlignLeft); label.bounds.SetWidth(65);
			label.caption.SetAOC("  XModem: ");
			toolbar.AddContent(label);
			
			(* send XModem *)
			NEW(sendXBtn);
			sendXBtn.alignment.Set(WMComponents.AlignLeft);
			sendXBtn.bounds.SetWidth(40);
			sendXBtn.caption.SetAOC("Send");
			sendXBtn.onClick.Add(HandleXYButtons);
			toolbar.AddContent(sendXBtn);
			
			(* receive XModem *)
			NEW(receiveXBtn);
			receiveXBtn.alignment.Set(WMComponents.AlignLeft);
			receiveXBtn.bounds.SetWidth(40);
			receiveXBtn.caption.SetAOC("Receive");
			receiveXBtn.onClick.Add(HandleXYButtons);
			toolbar.AddContent(receiveXBtn);

			NEW(label);	
			label.alignment.Set(WMComponents.AlignLeft); label.bounds.SetWidth(65);
			label.caption.SetAOC("  YModem:");
			toolbar.AddContent(label);
			
			(* send YModem *)
			NEW(sendYBtn);
			sendYBtn.alignment.Set(WMComponents.AlignLeft);
			sendYBtn.bounds.SetWidth(40);
			sendYBtn.caption.SetAOC("Send");
			sendYBtn.onClick.Add(HandleXYButtons);
			toolbar.AddContent(sendYBtn);
			
			(* receive YModem *)
			NEW(receiveYBtn);
			receiveYBtn.alignment.Set(WMComponents.AlignLeft);
			receiveYBtn.bounds.SetWidth(40);
			receiveYBtn.caption.SetAOC("Receive");
			receiveYBtn.onClick.Add(HandleXYButtons);
			toolbar.AddContent(receiveYBtn);
			
			(* Clear *)
			NEW(button); button.alignment.Set(WMComponents.AlignRight);
			button.caption.SetAOC("Clear");
			button.onClick.Add(HandleClearButton);
			toolbar.AddContent(button);
			
			(* Paste *)
			NEW(button); button.alignment.Set(WMComponents.AlignRight);
			button.caption.SetAOC("Paste");
			button.onClick.Add(HandlePasteButton);
			toolbar.AddContent(button);

			(* Copy *)
			NEW(button); button.alignment.Set(WMComponents.AlignRight);
			button.caption.SetAOC("Copy");
			button.onClick.Add(HandleCopyButton);
			toolbar.AddContent(button);
			
			RETURN toolbar;
		END CreateUpperToolBar;
			
		PROCEDURE CreateCommandMenu() : WMStandardComponents.Button;
		VAR command : Command; button : WMStandardComponents.Button;
		BEGIN
			command := LoadCommandMenu();
			IF command # NIL THEN
				NEW(commandPopup);				
				WHILE command # NIL DO
					commandPopup.AddParButton(command.name, HandleCommandPopup, command);
					command := command.next;
				END;
				
				NEW(button);
				button.bounds.SetWidth(150); button.alignment.Set(WMComponents.AlignRight);
				button.takesFocus.Set(FALSE);
				button.caption.SetAOC("Commands");
				button.onClick.Add(HandleCommandMenuButton);
			END;	
			RETURN button;
		END CreateCommandMenu;		
		
		PROCEDURE CreateLowerToolBar() : WMStandardComponents.Panel;
		VAR toolbar : WMStandardComponents.Panel;
		BEGIN
			NEW(toolbar);
			toolbar.alignment.Set(WMComponents.AlignBottom); toolbar.bounds.SetHeight(20);
			toolbar.fillColor.Set(0E0E0E0FFH);
			
			NEW(sendCommandBtn);
			sendCommandBtn.alignment.Set(WMComponents.AlignLeft); sendCommandBtn.bounds.SetWidth(100);
			sendCommandBtn.takesFocus.Set(FALSE);
			sendCommandBtn.caption.SetAOC("Send Command:");
			sendCommandBtn.onClick.Add(HandleSendCommandButton);
			toolbar.AddContent(sendCommandBtn);
			
			commandMenuBtn := CreateCommandMenu();
			IF commandMenuBtn # NIL THEN
				toolbar.AddContent(commandMenuBtn);
			END;
			
			NEW(sendCommandEditor); 
			sendCommandEditor.alignment.Set(WMComponents.AlignClient);
			sendCommandEditor.multiLine.Set(FALSE);
			sendCommandEditor.fillColor.Set(WMGraphics.White);
			sendCommandEditor.tv.borders.Set(WMRectangles.MakeRect(4, 3, 2, 2));
			sendCommandEditor.tv.showBorder.Set(TRUE);
			sendCommandEditor.SetAsString("");
			sendCommandEditor.onEnter.Add(HandleSendCommandButton);
			toolbar.AddContent(sendCommandEditor);
			
			RETURN toolbar;	
		END CreateLowerToolBar;
		
		PROCEDURE CreateStatusBar() : WMStandardComponents.Panel;
		VAR statusBar : WMStandardComponents.Panel;
		BEGIN
			NEW(statusBar);
			statusBar.alignment.Set(WMComponents.AlignBottom); statusBar.bounds.SetHeight(20);
			statusBar.fillColor.Set(0E0E0E0FFH);
			
			NEW(clearStatusBtn);
			clearStatusBtn.bounds.SetWidth(80); clearStatusBtn.alignment.Set(WMComponents.AlignRight);
			clearStatusBtn.caption.SetAOC("Clear Status"); 
			clearStatusBtn.onClick.Add(HandleClearStatusButton);
			statusBar.AddContent(clearStatusBtn);
			
			NEW(dsr);
			dsr.bounds.SetWidth(30); dsr.alignment.Set(WMComponents.AlignRight);
			dsr.bearing.Set(WMRectangles.MakeRect(1,1,1,1));
			dsr.caption.SetAOC("DSR"); dsr.fillColor.Set(WMGraphics.White); dsr.alignH.Set(WMGraphics.AlignCenter);
			statusBar.AddContent(dsr);
						
			NEW(status);
			status.alignment.Set(WMComponents.AlignClient);
			statusBar.AddContent(status);
			
			RETURN statusBar;
		END CreateStatusBar;
	
		PROCEDURE CreateContent;
		VAR scrollbarY : WMStandardComponents.Scrollbar;
		BEGIN
			AddContent(CreateUpperToolBar()); (* AlignTop *)
			IF settings.showStatusBar THEN
				AddContent(CreateStatusBar()); (* AlignBottom *)
			END;
			lowerToolBar := CreateLowerToolBar();
			AddContent(lowerToolBar); (* AlignBottom *)
			
			NEW(scrollbarY); scrollbarY.alignment.Set(WMComponents.AlignRight); scrollbarY.vertical.Set(TRUE);
			AddContent(scrollbarY);
			
			NEW(text);
			NEW(textView); textView.alignment.Set(WMComponents.AlignClient);
			textView.SetText(text);
			textView.showBorder.Set(TRUE);
			textView.SetScrollbars(NIL, scrollbarY);
			textView.SetExtKeyEventHandler(ExtKeyPressed);
			textView.SetExtFocusHandler(ExtFocus);
			IF settings.indicateKeyboardFocus THEN textView.fillColor.Set(0CCCCCCCCH); END;
			AddContent(textView);			
		END CreateContent;
		
		PROCEDURE Wait(ms : LONGINT);
		BEGIN
			timer.Sleep(ms);
		END Wait;	

		PROCEDURE &Init;
		VAR tw : AosTextUtilities.TextWriter;
		BEGIN
			Init^;
			NEW(timer); NEW(lock);
			LoadSettings(settings);
			CreateContent;
			NEW(tw, text); tw.SetFontName("Courier"); w := tw.GetWriter();
			IF settings.showStatusBar THEN NEW(statusUpdater, SELF); END;
		END Init;
		
		(* Get global coordinates of the terminal panel *)
		PROCEDURE GetPanelCoordinates(VAR gx, gy : LONGINT);
		VAR rect : WMRectangles.Rectangle;
		BEGIN
			rect := bounds.Get();
			ToWMCoordinates(rect.l, rect.t, gx, gy);
		END GetPanelCoordinates;

		PROCEDURE CopyFromClipboard;
		VAR string : POINTER TO ARRAY OF CHAR;
		BEGIN
			AosTexts.clipboard.AcquireRead;
			IF AosTexts.clipboard.GetLength() > 0 THEN
				NEW(string, AosTexts.clipboard.GetLength()+1);
				AosTextUtilities.TextToStr(AosTexts.clipboard, string^);
			END;
			AosTexts.clipboard.ReleaseRead;
			lock.Acquire(Terminal); out.String(string^); out.Update; lock.Release;
		END CopyFromClipboard;
		
		PROCEDURE GetXYCommand(send : BOOLEAN; mode : LONGINT) : Utilities.String;
		VAR command : Utilities.String; 
		BEGIN
			IF (mode = AosXYModem.XModem) THEN
				IF send THEN command := settings.xReceiveCommand; 
				ELSE command := settings.xSendCommand; 
				END;
			ELSE
				IF send THEN command := settings.yReceiveCommand; 
				ELSE command := settings.ySendCommand; 
				END;
			END;	
			RETURN command;		
		END GetXYCommand;
		
		PROCEDURE SendXYCommand(send : BOOLEAN; command, filename : ARRAY OF CHAR);
		BEGIN
			lock.Acquire(Terminal);
			out.String(command);
			IF ~send THEN out.Char(" "); out.String(filename); END;
			out.Char(CR); 
			IF settings.linefeed THEN out.Char(LF); END;
			out.Update;
			lock.Release;
			Wait(500);
		END SendXYCommand;
				
		PROCEDURE SendXYModem(filename : ARRAY OF CHAR; mode : LONGINT);
		VAR 
			f : AosFS.File;
			progressWindow : ProgressWindow;
			progressInfo : ProgressInfo;
			xysender : AosXYModem.Sender;
			msg : ARRAY 32 OF CHAR;
			x, y, res : LONGINT;
		BEGIN
			f := AosFS.Old(filename);
			IF f # NIL THEN 
				IF open THEN 
					NEW(timer);
					open := FALSE;
					port.Close; (* Force ReceiveCharacters to release the lock *)
					lock.Acquire(DataTransfer);
					(* Now we have the port for us alone *)
					port.Open(bps, databits, parity, stop, res);
					IF res = AosSerials.Ok THEN
						in.Reset; out.Reset;
						NEW(xysender, out, in, f, mode);
						NEW(progressInfo, filename, f.Length()); progressInfo.bounds.SetExtents(300, 60);
						GetPanelCoordinates(x, y);
						NEW(progressWindow, progressInfo, x + 150, y + 50);
						WHILE ~xysender.IsDone() DO
							progressInfo.SetProgress(xysender.bytesProcessed);
							Wait(500);
						END;
						progressInfo.SetProgress(xysender.bytesProcessed);
						xysender.Await(msg);
					ELSE
						Show("FATAL ERROR, could not re-open the port"); AosOut.Ln;
					END;
					lock.Release;
					IF msg # "" THEN
						res := WMDialogs.Message("Transmission failed", msg, {WMDialogs.ResOk})
					END;
					Wait(1000);
					progressWindow.Close;
					BEGIN {EXCLUSIVE} open := TRUE; END;
				END;
			ELSE
				res := WMDialogs.Message("File not found", filename, {WMDialogs.ResOk});
			END;
		END SendXYModem;
		
		PROCEDURE ReceiveXYModem(filename : ARRAY OF CHAR; mode : LONGINT);
		VAR 
			f : AosFS.File;
			progressWindow : ProgressWindow;
			label : WMStandardComponents.Label;
			caption : ARRAY 128 OF CHAR;
			xyreceiver : AosXYModem.Receiver;
			msg : ARRAY 32 OF CHAR;
			x, y, res : LONGINT;
			awaitF : BOOLEAN;
		BEGIN
			IF filename # "" THEN
				f := AosFS.New(filename); awaitF := FALSE;
				IF f = NIL THEN
					res := WMDialogs.Message("Couldn't create file ", filename, {WMDialogs.ResOk});
					RETURN;
				END;
			ELSE
				f := NIL; awaitF := TRUE
			END;
			
			IF open THEN 
				NEW(timer);
				open := FALSE;
				port.Close; (* Force ReceiveCharacters to release the lock *)
				lock.Acquire(DataTransfer);
				(* Now we have the port for us alone *)
				port.Open(bps, databits, parity, stop, res);
				IF res = AosSerials.Ok THEN
					in.Reset; out.Reset;
					NEW(xyreceiver, out, in, f, mode);
					NEW(label); label.alignment.Set(WMComponents.AlignLeft);
					label.bounds.SetExtents(300, 100); label.fillColor.Set(WMGraphics.White);
					label.alignH.Set(WMGraphics.AlignCenter); label.alignV.Set(WMGraphics.AlignCenter);
					label.caption.SetAOC("Receiving data...");
					GetPanelCoordinates(x, y);
					NEW(progressWindow, label, x + 150, y + 50);
					WHILE ~xyreceiver.IsDone() DO
						Utilities.IntToStr(xyreceiver.bytesProcessed, caption);
						Utilities.Append(caption, " bytes received"); 
						label.caption.SetAOC(caption);
						Wait(500);
					END;
					Utilities.IntToStr(xyreceiver.bytesProcessed, caption);
					Utilities.Append(caption, " bytes received"); 
					label.caption.SetAOC(caption);
					IF ~awaitF THEN
						xyreceiver.Await(msg)
					ELSE
						xyreceiver.AwaitF(f, msg)
					END;
				ELSE
					Show("FATAL ERROR, could not re-open the port"); AosOut.Ln;
				END;
				lock.Release;
				
				Wait(500); (* Give the port open time so we see the output below *)

				IF msg # "" THEN
					res := WMDialogs.Message("Reception failed", msg, {WMDialogs.ResOk})
				ELSIF f = NIL THEN
					res := WMDialogs.Message("Error: File is NIL", msg, {WMDialogs.ResOk});
				ELSE
					AosFS.Register(f);
					IF awaitF THEN
						f.GetName(filename);
					END;
					caption := "File "; Utilities.Append(caption, filename); Utilities.Append(caption, " received ("); 
					Utilities.IntToStr(xyreceiver.bytesProcessed, msg); Utilities.Append(caption, msg); Utilities.Append(caption, "Bytes)");
					label.caption.SetAOC(caption);
				END;
														
				Wait(500);
				progressWindow.Close;
				BEGIN {EXCLUSIVE} open := TRUE; END;
			END;
		END ReceiveXYModem;

		PROCEDURE ResetStatus;
		BEGIN
			overrunErrors := 0; parityErrors := 0; framingErrors := 0; transportErrors := 0; breakInterrupts := 0;
		END ResetStatus;

		PROCEDURE ToggleOpen(sender, data : ANY);
		VAR msg, s, t : ARRAY 64 OF CHAR; parityChar : CHAR;
			r : AosIO.StringReader;
			res : LONGINT;
		BEGIN
			ResetStatus;
			IF open THEN 
				open := FALSE;
				port.Close; 
				opencloseBtn.caption.SetAOC("Open");
			ELSE
				settingsEdit.GetAsString(s);
				NEW(r, 64); r.Set(s); r.SkipWhitespace;
				r.Int(portNr, FALSE);  r.SkipWhitespace;
				r.Int(bps, FALSE); r.SkipWhitespace;
				r.Int(databits, FALSE); r.SkipWhitespace; 
				r.Int(stop, FALSE); r.SkipWhitespace;
				r.Char(parityChar);
				
				port := AosSerials.GetPort(portNr); 
				IF port # NIL THEN
					CASE CAP(parityChar) OF
						| "N" : parity := AosSerials.ParNo;
						| "O" : parity := AosSerials.ParOdd;
						| "E" : parity := AosSerials.ParEven;
						| "M" : parity := AosSerials.ParMark;
						| "S" : parity := AosSerials.ParSpace;
					ELSE parity := AosSerials.ParNo
					END;
					port.Open(bps, databits, parity, stop, res);
					IF res = AosSerials.Ok THEN
						opencloseBtn.caption.SetAOC("Close");
						NEW(in, port.Receive, 64); NEW(out, port.Send, 64);
						BEGIN {EXCLUSIVE}
							open := TRUE
						END
					ELSE
						ReportError("Configuration Error", res);
					END
				ELSE
					msg := "Port number not available: "; Utilities.IntToStr(portNr, t); Utilities.Append(msg, t);
					res := WMDialogs.Message("Port not found", msg, {WMDialogs.ResOk})
				END;
			END;
		END ToggleOpen;

		PROCEDURE Finalize;
		BEGIN
			Finalize^;
			IF settings.showStatusBar THEN statusUpdater.Terminate; END;
			BEGIN {EXCLUSIVE}
				running := FALSE;
				IF port # NIL THEN port.Close; open := FALSE; END;
			END;	
		END Finalize;
		
		PROCEDURE DeleteNCharacters(nbrOfCharacters : LONGINT);
		VAR pos : LONGINT;
		BEGIN
			text.AcquireWrite;
			pos := textView.cursor.GetPosition(); 
			text.Delete(pos - nbrOfCharacters, nbrOfCharacters);
			text.ReleaseWrite;
		END DeleteNCharacters;
		
		PROCEDURE ReportError(title : ARRAY OF CHAR; res : LONGINT);
		VAR ignore : LONGINT; msg : ARRAY 128 OF CHAR;
		BEGIN
		CASE res OF
			| AosSerials.PortInUse : msg := "Port already in use"
			| AosSerials.WrongBPS : msg := "Unsupported  BPS"
			| AosSerials.WrongData : msg := "Unsupported data or stop bits"
			| AosSerials.WrongParity : msg := "Unsupported parity";
			| AosSerials.OverrunError : msg := "Overrun Error";
			| AosSerials.ParityError : msg := "Parity Error";
			| AosSerials.FramingError : msg := "Framing Error (Wrong bitrate?)";
			| AosSerials.BreakInterrupt : msg := "Break Interrupt received";
			| AosSerials.Closed : msg := "Port is closed";
			| AosSerials.TransportError : msg := "Transport Layer Error";
		ELSE msg := "Unspecified error"
		END;
		ignore := WMDialogs.Message(title, msg, {WMDialogs.ResOk})
		END ReportError;
		
		PROCEDURE EvaluateError(res : LONGINT);
		BEGIN
			CASE res OF
				|AosSerials.OverrunError: INC(overrunErrors);
				|AosSerials.ParityError: INC(parityErrors);
				|AosSerials.FramingError: INC(framingErrors);
				|AosSerials.BreakInterrupt: INC(breakInterrupts);
				|AosSerials.TransportError: INC(transportErrors);
			ELSE
				INC(otherErrors);
			END;
		END EvaluateError;
		
		PROCEDURE ReceiveCharacters;
		VAR ch : CHAR; buffer : ARRAY ReceiveBufferSize OF CHAR; backspaces, i, len, res : LONGINT;
		BEGIN
			(* Receive at least one character *)
			lock.Acquire(Terminal);
			port.Receive(buffer, 0, ReceiveBufferSize, 1, len, res);
			lock.Release;
			IF res = AosSerials.Ok THEN
				FOR i := 0 TO len-1 DO
					ch := buffer[i];
					IF Trace * TraceCharactersReceived # {} THEN Show("Received character: "); AosOut.Int(ORD(ch), 0); AosOut.Ln; END;
					IF settings.echo THEN out.Char(ch); out.Update; END;
					IF (ch = DEL) OR (ch = Backspace) THEN
						INC(backspaces);
					ELSE
						IF (backspaces > 0) THEN
							w.Update;
							DeleteNCharacters(backspaces);
							backspaces := 0;
						END;	
						w.Char(ch);						
					END;
				END;
				w.Update;
			ELSE
				EvaluateError(res);
			END;
			DeleteNCharacters(backspaces);
		END ReceiveCharacters;
		
	BEGIN {ACTIVE}
		running := TRUE;
		WHILE running DO
			BEGIN {EXCLUSIVE} AWAIT(open OR ~running); END;
			IF running THEN ReceiveCharacters; END;
		END;	
	END TerminalComponent;
	
TYPE

	StatusUpdater = OBJECT
	VAR
		terminal : TerminalComponent;
		
		writer : AosIO.StringWriter;
	
		alive, dead : BOOLEAN;
		timer : AosKernel.Timer;
		
		PROCEDURE UpdateStatusLabel;
		VAR string : ARRAY 1024 OF CHAR; port : AosSerials.Port; mc : SET;
		BEGIN
			writer.Reset;
			writer.String("  Errors:   ");
			writer.String("Overruns: "); writer.Int(terminal.overrunErrors, 5); writer.String("   ");
			writer.String("Parity: "); writer.Int(terminal.parityErrors, 5); writer.String("   ");
			writer.String("Framing: "); writer.Int(terminal.framingErrors, 5); writer.String("   ");
			writer.String("Transport: "); writer.Int(terminal.transportErrors, 5);
			port := terminal.port;
			IF (port # NIL) & terminal.open THEN
				writer.String("      ");
				writer.String("Sent: "); writer.Int(port.charactersSent, 8); writer.String("   ");
				writer.String("Received: "); writer.Int(port.charactersReceived, 8);
				port.GetMC(mc);
				IF mc * {AosSerials.DSR} # {} THEN
					terminal.dsr.fillColor.Set(WMGraphics.Green);
				ELSE
					terminal.dsr.fillColor.Set(WMGraphics.Red);
				END;
			ELSE
				terminal.dsr.fillColor.Set(WMGraphics.White);
			END;
			writer.Get(string);
			terminal.status.caption.SetAOC(string);	
			IF (terminal.overrunErrors > 0) OR (terminal.parityErrors > 0) OR (terminal.framingErrors > 0) OR
				(terminal.transportErrors > 0) THEN
				terminal.status.fillColor.Set(WMGraphics.Red);
			ELSE
				terminal.status.fillColor.Set(0E0E0E0FFH);
			END;
		END UpdateStatusLabel;
		
		PROCEDURE Terminate;
		BEGIN {EXCLUSIVE}
			alive := FALSE; timer.Wakeup;
			AWAIT(dead);
		END Terminate;
		
		PROCEDURE &Init(terminal : TerminalComponent);
		BEGIN
			ASSERT(terminal # NIL);
			SELF.terminal := terminal;
			alive := TRUE; dead := FALSE;
			NEW(timer);
			NEW(writer, 1024);
		END Init;
	
	BEGIN {ACTIVE}
		WHILE alive DO
			UpdateStatusLabel;
			timer.Sleep(UpdateInterval);
		END;
		BEGIN {EXCLUSIVE} dead := TRUE; END;
	END StatusUpdater;

TYPE
	
	KillerMsg = OBJECT
	END KillerMsg; 
	
	ProgressWindow = OBJECT(WMComponents.FormWindow);

		PROCEDURE Close;
		BEGIN
			Close^;
			DecCount
		END Close;

		PROCEDURE Handle(VAR x : WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
			ELSE Handle^(x)
			END
		END Handle;		
		
		PROCEDURE &New(vc : WMComponents.VisualComponent; x, y : LONGINT);
		BEGIN
			IncCount;
			
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("Progress"));
			
			WMWindowManager.ExtAddWindow(SELF, x, y, {WMWindowManager.FlagFrame});
		END New;
		
	END ProgressWindow;

TYPE
	
	Window* = OBJECT (WMComponents.FormWindow)
	VAR 
		terminal : TerminalComponent;
		
		PROCEDURE GetStartupSize(VAR width, height : LONGINT);
		VAR strings : Utilities.StringArray; value : ARRAY 64 OF CHAR;
		BEGIN
			AosConfig.Get("Applications.WMV24Component.WindowStartupSize", value);
			Utilities.UpperCase(value);
			Utilities.TrimWS(value);
			strings := Utilities.Split(value, "X");
			IF LEN(strings) = 2 THEN
				Utilities.StrToInt(strings[0]^, width);
				Utilities.StrToInt(strings[1]^, height);
			ELSE
				width := DefaultWidth; height := DefaultHeight;
			END;
		END GetStartupSize;

		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR panel : WMStandardComponents.Panel; width, height : LONGINT;
		BEGIN
			GetStartupSize(width, height);
			NEW(panel); panel.bounds.SetExtents(width, height); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
			NEW(terminal); terminal.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(terminal);
			RETURN panel
		END CreateForm;

		PROCEDURE &New(c : WMRestorable.Context);
		VAR 
			vc : WMComponents.VisualComponent; 
			configuration : WMRestorable.XmlElement; string : ARRAY 64 OF CHAR;
		BEGIN
			IncCount;
			
			vc := CreateForm();			
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			SetTitle(Utilities.NewString("BlueTerminal"));

			IF c # NIL THEN
				configuration := WMRestorable.GetElement(c, "Configuration");
				IF configuration # NIL THEN
					WMRestorable.LoadString(configuration, "PortSettings", string);
					terminal.settingsEdit.SetAsString(string);
				END;
				WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame});
				Resized(GetWidth(), GetHeight());
			ELSE
				WMWindowManager.DefaultAddWindow(SELF);
			END;
		END New;

		PROCEDURE Close;
		BEGIN
			Close^;
			DecCount
		END Close;

		PROCEDURE Handle(VAR x : WMMessages.Message);
		VAR configuration : WMRestorable.XmlElement; string : ARRAY 64 OF CHAR;
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS KillerMsg) THEN 
					Close;
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					NEW(configuration); configuration.SetName("Configuration");
					terminal.settingsEdit.GetAsString(string);
					WMRestorable.StoreString(configuration, "PortSettings", string);
					x.ext(WMRestorable.Storage).Add("BlueTerminal", "WMV24Component.Restore", SELF, configuration);
				ELSE
					Handle^(x);
				END;
			ELSE Handle^(x)
			END
		END Handle;		

	END Window;

VAR
	nofWindows : LONGINT;

(* Load settings from AosConfig.XML. For settings that are not available, default settings are used *)
PROCEDURE LoadSettings(VAR settings : Settings);
VAR 
	value : ARRAY 256 OF CHAR;

	PROCEDURE GetDefaultPortSettings(VAR portSettings : ARRAY OF CHAR);
	VAR w : AosIO.StringWriter;
	BEGIN
		NEW(w, 64);
		w.Int(DefaultPort, 0); w.Char(" ");
		w.Int(DefaultBps, 0); w.Char(" ");
		w.Int(DefaultDataBits, 0); w.Char(" ");
		w.Int(DefaultStopBits, 0); w.Char(" ");
		CASE DefaultParity OF 
			|AosSerials.ParNo: w.String("none");
			|AosSerials.ParOdd: w.String("odd");
			|AosSerials.ParEven: w.String("even");
			|AosSerials.ParMark: w.String("mark");
			|AosSerials.ParSpace: w.String("space");
		ELSE
			w.String("unknown");
		END;
		w.Get(portSettings);
	END GetDefaultPortSettings;
	
	PROCEDURE IsTrue(value : ARRAY OF CHAR) : BOOLEAN;
	BEGIN
		Utilities.UpperCase(value);
		Utilities.TrimWS(value);
		RETURN Utilities.Match("TRUE", value);
	END IsTrue;
	
BEGIN
	AosConfig.Get("Applications.WMV24Component.PortSettings", value);
	IF value # "" THEN COPY(value, settings.portSettings);
	ELSE GetDefaultPortSettings(settings.portSettings);
	END;

	AosConfig.Get("Applications.WMV24Component.IndicateKeyboardFocus", value);
	IF value # "" THEN settings.indicateKeyboardFocus := IsTrue(value);
	ELSE settings.indicateKeyboardFocus := DefaultIndicateKeyboardFocus;
	END;
	
	AosConfig.Get("Applications.WMV24Component.LineFeed", value);
	IF value # "" THEN settings.linefeed := IsTrue(value);
	ELSE settings.linefeed := DefaultLineFeed;
	END;
	
	AosConfig.Get("Applications.WMV24Component.UseBackspace", value);
	IF value # "" THEN settings.useBackspace := IsTrue(value);
	ELSE settings.useBackspace := DefaultUseBackspace;
	END;
	
	AosConfig.Get("Applications.WMV24Component.ShowStatusBar", value);
	IF value # "" THEN settings.showStatusBar := IsTrue(value);
	ELSE settings.showStatusBar := DefaultShowStatusBar;
	END;
	
	AosConfig.Get("Applications.WMV24Component.Echo", value);
	IF value # "" THEN settings.echo := IsTrue(value);
	ELSE settings.echo := DefaultEcho;
	END;
	
	AosConfig.Get("Applications.WMV24Component.XReceiveCommand", value);
	IF value # "" THEN settings.xReceiveCommand := Utilities.NewString(value); END;

	AosConfig.Get("Applications.WMV24Component.YReceiveCommand", value);
	IF value # "" THEN settings.yReceiveCommand := Utilities.NewString(value); END;
	
	AosConfig.Get("Applications.WMV24Component.XSendCommand", value);
	IF value # "" THEN settings.xSendCommand := Utilities.NewString(value); END;
	
	AosConfig.Get("Applications.WMV24Component.YSendCommand", value);
	IF value # "" THEN settings.ySendCommand := Utilities.NewString(value); END;
END LoadSettings;
	
PROCEDURE LoadCommandMenu() : Command;
VAR 
	commandList : Command;
	enum: XMLObjects.Enumerator; p: PTR; e: XML.Element;
	
	PROCEDURE AddCommand(name,  value : XML.String);
	VAR c, newCmd : Command;
	BEGIN
		IF (name # NIL) & (value # NIL) THEN
			NEW(newCmd);
			COPY(name^, newCmd.name);
			COPY(value^, newCmd.commandString);
			(* append to command list *)
			c := commandList;
			WHILE (c.next # NIL) DO c := c.next; END;
			c.next := newCmd;	
		ELSE
			Show("Command menu definition has errors."); AosOut.Ln;
		END;
	END AddCommand;
	
BEGIN
	NEW(commandList); 

	e := AosConfig.GetNamedElement(AosConfig.config.GetRoot(), "Section", "Applications"); 
	IF e = NIL THEN RETURN NIL; END;

	e := AosConfig.GetNamedElement(e, "Section", "WMV24Component");
	IF e = NIL THEN RETURN NIL; END;

	e := AosConfig.GetNamedElement(e, "Section", "CommandMenu");
	IF e = NIL THEN RETURN NIL; END;
	
	enum := e.GetContents();
	WHILE enum.HasMoreElements() DO
		p := enum.GetNext();
		IF p IS XML.Element THEN
			e := p (XML.Element);
			AddCommand(e.GetAttributeValue("name"), e.GetAttributeValue("value"));
		END;
	END;	
		
	RETURN commandList.next;
END LoadCommandMenu;

PROCEDURE Show(string : ARRAY OF CHAR);
BEGIN
	AosOut.String(ModuleName); AosOut.String(": "); AosOut.String(string);
END Show;

PROCEDURE Restore*(par : ANY) : ANY;
VAR window : Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(window, par(WMRestorable.Context));
	END;
	RETURN NIL;
END Restore;

PROCEDURE Open*(par : ANY) : ANY;
VAR window : Window;
BEGIN
	NEW(window, NIL);
	RETURN NIL
END Open;

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
	NEW(die);
	msg.ext := die;
	msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMV24Component.


AosV24.Install ~
AosSerials.Show ~

S.Free WMV24Component WMProgressComponents AosXYModem ~  
WMV24Component.Open ~
 
AosSerials.CloseAllPorts ~