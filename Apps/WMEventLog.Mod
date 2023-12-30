MODULE WMEventLog; (** AUTHOR "staubesv"; PURPOSE "GUI for event log"; *)
(**
 * History:
 *
 *	15.03.2007	First release (staubesv)
 *)
 
IMPORT
	AosEvents, AosEventsUtils, AosEventsMemoryLog, 
	AosCommands, AosIO, AosModules, AosKernel, Utilities,
	WMWindowManager, WMComponents, WMStandardComponents, WMGrids, WMStringGrids, WMGraphics, WMEditors,
	WMMessages, WMRestorable, WMRectangles, WMEvents, WMDialogs;
	
CONST
	
	DefaultWidth = 640;
	DefaultHeight = 300;
	
	PollingInterval = 1000;
	
	GridBgFillColor = 0E0E0E0FFH;
	NofColumns = 7;
	
	ColorUnknown = 0C0C0C0FFH;
	ColorInformation = WMGraphics.White;
	ColorWarning = WMGraphics.Yellow;
	ColorError = 0FF0000C0H;
	ColorCritical = 0FF0000E0H;
	ColorAlert = WMGraphics.Blue;
	ColorFailure = WMGraphics.Red;
	ColorOther = WMGraphics.White;
	
	DateTimeFormat = "yyyy.mm.dd hh:nn:ss";
	
	Running = 1;
	Terminating = 2;
	Terminated = 3;

TYPE

	EventLog* = OBJECT(WMComponents.VisualComponent)
	VAR
		grid : WMStringGrids.StringGrid;
		spacings : WMGrids.Spacings;
		
		events : AosEventsUtils.EventContainer;
		eventsInGrid : LONGINT;
		
		(* Filter panel *)
		timeEdit, originatorEdit, typeEdit, classEdit, subclassEdit, codeEdit, messageEdit : WMEditors.Editor;
		
		(* Status panel *)
		updateBtn, clearBtn : WMStandardComponents.Button;
		statusLabel : WMStandardComponents.Label;
		
		nofEventsInGrid, nofEventsTot, containerSize : LONGINT;
		
		lastCleared, stamp, lastStamp : LONGINT;
		
		update, fullUpdate : BOOLEAN;
		
		state : LONGINT;
		timer : AosKernel.Timer;
		
		PROCEDURE HandleButtons(sender, data : ANY);
		BEGIN
			IF sender = updateBtn THEN
				update := TRUE; fullUpdate := TRUE; timer.Wakeup;
			ELSIF sender = clearBtn THEN
				ClearLog;
			END;
		END HandleButtons;
		
		PROCEDURE HandleEditors(sender, data : ANY);
		BEGIN
			update := TRUE; fullUpdate := TRUE; timer.Wakeup;
		END HandleEditors;
				
		PROCEDURE FilterTime(event : AosEvents.Event; VAR discard : BOOLEAN);
		VAR string, timeString : ARRAY 32 OF CHAR; dt : Utilities.TDateTime;
		BEGIN
			discard := FALSE;
			timeEdit.GetAsString(string);
			dt := Utilities.OberonToDateTime(event.date, event.time);
			Utilities.FormatDateTime(DateTimeFormat, dt, timeString);
			IF (string # "") & ~Utilities.Match(string, timeString) THEN
				discard := TRUE;
			END;
		END FilterTime;
		
		PROCEDURE FilterType(event : AosEvents.Event; VAR discard : BOOLEAN);
		VAR string : ARRAY 32 OF CHAR;
		BEGIN
			discard := FALSE;
			typeEdit.GetAsString(string);
			IF (string # "") & ~Utilities.Match(string, AosEventsUtils.GetTypeString(event.type))THEN
				discard := TRUE;
			END;
		END FilterType;
		
		PROCEDURE FilterOriginator(event : AosEvents.Event; VAR discard : BOOLEAN);
		VAR string : AosEvents.Name;
		BEGIN
			discard := FALSE;
			originatorEdit.GetAsString(string);
			IF (string # "") & ~Utilities.Match(string, event.originator) THEN
				discard := TRUE;
			END;
		END FilterOriginator;
		
		PROCEDURE FilterClassification(event : AosEvents.Event; VAR discard : BOOLEAN);
		VAR string : ARRAY 16 OF CHAR; value : LONGINT;
		BEGIN
			discard := FALSE;

			classEdit.GetAsString(string);
			IF (string # "") & (string # "*") THEN
				Utilities.StrToInt(string, value); IF event.class # value THEN discard := TRUE; RETURN; END;
			END;
			
			subclassEdit.GetAsString(string);
			IF (string # "") & (string # "*") THEN
				Utilities.StrToInt(string, value); IF event.subclass # value THEN discard := TRUE; RETURN; END;
			END;
			
			codeEdit.GetAsString(string);
			IF (string # "") & (string # "*") THEN
				Utilities.StrToInt(string, value); IF event.code # value THEN discard := TRUE; RETURN; END;
			END;
		END FilterClassification;
		
		PROCEDURE FilterMessage(event : AosEvents.Event; VAR discard : BOOLEAN);
		VAR string : AosEvents.Message;
		BEGIN
			discard := FALSE;
			IF (string # "") & ~Utilities.Match(string, event.message) THEN
				discard := TRUE;
			END;
		END FilterMessage;
		
		PROCEDURE Filter(event : AosEvents.Event; VAR discard : BOOLEAN);
		BEGIN
			discard := FALSE;
			FilterTime(event, discard);
			IF ~discard THEN
				FilterType(event, discard);
				IF ~discard THEN
					FilterOriginator(event, discard);
					IF ~discard THEN
						FilterClassification(event, discard);
						IF ~discard THEN
							FilterMessage(event, discard);
						END;
					END;
				END;
			END;
		END Filter;
		
		PROCEDURE UpdateRow(row : LONGINT; event : AosEvents.Event);
		VAR 
			col : LONGINT; caption : ARRAY 128 OF CHAR;
			dt : Utilities.TDateTime;
			
			PROCEDURE GetCaption(VAR caption : ARRAY OF CHAR; string : ARRAY OF CHAR);
			BEGIN
				COPY(string, caption);
			END GetCaption;
			
		BEGIN (* has lock on grid and grid.model *)
			FOR col := 0 TO 	NofColumns-1 DO
				CASE col OF
					|0:	dt := Utilities.OberonToDateTime(event.date, event.time);
						Utilities.FormatDateTime(DateTimeFormat, dt, caption);
						grid.model.SetTextAlign(col, row, WMGraphics.AlignCenter);
					|1: 	GetCaption(caption, AosEventsUtils.GetTypeString(event.type));
						IF event.type = AosEvents.Unknown THEN grid.model.SetCellColors(col, row, ColorUnknown, WMGraphics.Black);
						ELSIF event.type = AosEvents.Information THEN grid.model.SetCellColors(col, row, ColorInformation, WMGraphics.Black);
						ELSIF event.type = AosEvents.Warning THEN grid.model.SetCellColors(col, row, ColorWarning, WMGraphics.Black);
						ELSIF event.type = AosEvents.Error THEN grid.model.SetCellColors(col, row, ColorError, WMGraphics.Black);
						ELSIF event.type = AosEvents.Critical THEN grid.model.SetCellColors(col, row, ColorCritical, WMGraphics.Black);
						ELSIF event.type = AosEvents.Alert THEN grid.model.SetCellColors(col, row, ColorAlert, WMGraphics.Black);
						ELSIF event.type = AosEvents.Failure THEN grid.model.SetCellColors(col, row, ColorFailure, WMGraphics.Black);
						ELSE
							grid.model.SetCellColors(col, row, ColorOther, WMGraphics.Black);
						END;
					|2:	COPY(event.originator, caption);
					|3:	Utilities.IntToStr(event.class, caption); grid.model.SetTextAlign(col, row, WMGraphics.AlignCenter);
					|4:	Utilities.IntToStr(event.subclass, caption); grid.model.SetTextAlign(col, row, WMGraphics.AlignCenter);
					|5:	Utilities.IntToStr(event.code, caption); grid.model.SetTextAlign(col, row, WMGraphics.AlignCenter);
					|6:	COPY(event.message, caption);
				ELSE
				END;
				grid.model.SetCellText(col, row, Utilities.NewString(caption));
			END;
		END UpdateRow;
		
		PROCEDURE FullUpdate(wrapper : AosEventsUtils.EventWrapper; nofEvents : LONGINT);
		VAR i, idx : LONGINT; discard : BOOLEAN;
		BEGIN (* has lock on grid and grid.model *)
			nofEventsInGrid := 0; nofEventsTot := nofEvents;
			grid.model.SetNofRows(1);
			i := 0;
			WHILE (i < nofEvents) DO
				IF i >= LEN(wrapper.events) THEN wrapper := wrapper.next; END;
				idx := i MOD LEN(wrapper.events);
				Filter(wrapper.events[idx], discard);
				IF ~discard THEN
					INC(nofEventsInGrid);
					grid.model.InsertEmptyRow(1);
					UpdateRow(1, wrapper.events[idx]);
				END;
				INC(i);
			END;
			grid.SetTopPosition(0, 0, TRUE);
		END FullUpdate;
		
		PROCEDURE IncrementalUpdate(wrapper : AosEventsUtils.EventWrapper; nofEvents : LONGINT) : LONGINT;
		VAR i, idx, nofNewEvents : LONGINT; discard : BOOLEAN;
		BEGIN (* has lock on grid and grid.model *)
			nofNewEvents := nofEvents - eventsInGrid;
			IF nofNewEvents > 0 THEN
				i := eventsInGrid DIV LEN(wrapper.events);
				WHILE (i > 0) DO wrapper := wrapper.next; DEC(i); END;
				idx := eventsInGrid MOD LEN(wrapper.events);
				INC(nofEventsTot, nofNewEvents);
				i := nofNewEvents;
				WHILE (i > 0) DO
					Filter(wrapper.events[idx], discard);
					IF ~discard THEN
						INC(nofEventsInGrid);
						grid.model.InsertEmptyRow(1);
						UpdateRow(1, wrapper.events[idx]);
					END;
					IF (idx + 1) >= LEN(wrapper.events) THEN wrapper := wrapper.next; END;
					idx := (idx + 1) MOD LEN(wrapper.events);
					DEC(i);
				END;
			END;
			RETURN nofNewEvents;
		END IncrementalUpdate;
		
		PROCEDURE UpdateStatusLabel;
		VAR string, nbr : ARRAY 64 OF CHAR;
		BEGIN
			string := " ";
			Utilities.IntToStr(nofEventsInGrid, nbr); Utilities.Append(string, nbr);
			Utilities.Append(string, " of ");
			Utilities.IntToStr(nofEventsTot, nbr); Utilities.Append(string, nbr);
			Utilities.Append(string, " events (max. log size: ");
			Utilities.IntToStr(containerSize, nbr); Utilities.Append(string, nbr);
			Utilities.Append(string, ")");
			statusLabel.caption.SetAOC(string);	
		END UpdateStatusLabel;
		
		PROCEDURE Update;
		VAR 
			wrapper : AosEventsUtils.EventWrapper;
			nofEvents : LONGINT; full : BOOLEAN;
			lastCleared : LONGINT;
			oldNofEventsInGrid, oldNofEventsTot : LONGINT;
		BEGIN
			oldNofEventsInGrid := nofEventsInGrid;
			oldNofEventsTot := nofEventsTot;
			grid.Acquire;
			grid.model.Acquire;
			IF events # NIL THEN
				wrapper := events.GetEvents(nofEvents, full, lastCleared);
				IF nofEvents > 0 THEN
					IF fullUpdate OR (lastCleared # SELF.lastCleared) THEN
						fullUpdate := FALSE;
						FullUpdate(wrapper, nofEvents);
						eventsInGrid := nofEvents;
						SELF.lastCleared := lastCleared;
					ELSE
						eventsInGrid := eventsInGrid + IncrementalUpdate(wrapper, nofEvents);
					END;
				ELSE
					grid.model.SetNofRows(1);
				END;
			ELSE
				grid.model.SetNofRows(1);
			END;
			grid.model.Release;
			grid.Release;
			IF (nofEventsInGrid # oldNofEventsInGrid) OR (nofEventsTot # oldNofEventsTot) THEN
				UpdateStatusLabel;
			END;
		END Update;
		
		PROCEDURE NewGrid() : WMStringGrids.StringGrid;
		VAR grid : WMStringGrids.StringGrid;
		BEGIN
			NEW(grid); 			
			grid.fixedRows.Set(1);
			grid.fillColor.Set(GridBgFillColor);
			grid.alignment.Set(WMComponents.AlignClient);
			grid.SetSelectionMode(WMGrids.GridSelectRows); 
			grid.SetSelection(-1, -1, -1, -1);
			grid.alwaysShowScrollX.Set(FALSE); grid.showScrollX.Set(TRUE);  
			grid.alwaysShowScrollY.Set(FALSE); grid.showScrollY.Set(TRUE);		
			grid.allowColResize.Set(FALSE); grid.allowRowResize.Set(FALSE);
		
			grid.Acquire;
			grid.model.Acquire;
			grid.model.SetNofCols(NofColumns); grid.SetColSpacings(spacings);
			grid.model.SetNofRows(1);
			(* column titles *)
			grid.model.SetCellText(0, 0, Utilities.NewString("Time"));
			grid.model.SetCellText(1, 0, Utilities.NewString("Type"));
			grid.model.SetCellText(2, 0, Utilities.NewString("Originator"));
			grid.model.SetCellText(3, 0, Utilities.NewString("Class")); grid.model.SetTextAlign(3, 0, WMGraphics.AlignCenter);
			grid.model.SetCellText(4, 0, Utilities.NewString("Sub")); grid.model.SetTextAlign(4, 0, WMGraphics.AlignCenter);
			grid.model.SetCellText(5, 0, Utilities.NewString("Code")); grid.model.SetTextAlign(5, 0, WMGraphics.AlignCenter);
			grid.model.SetCellText(6, 0, Utilities.NewString("Message"));
			grid.model.Release;
			grid.Release;			
			RETURN grid;
		END NewGrid;
		
		PROCEDURE CreateFilterPanel() : WMStandardComponents.Panel;
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			NEW(panel); panel.alignment.Set(WMComponents.AlignBottom); panel.bounds.SetHeight(20);
			
			timeEdit := NewEditor("*", WMComponents.AlignLeft, spacings[0], HandleEditors); panel.AddContent(timeEdit);
			typeEdit := NewEditor("*", WMComponents.AlignLeft, spacings[1], HandleEditors); panel.AddContent(typeEdit);
			originatorEdit := NewEditor("*", WMComponents.AlignLeft, spacings[2], HandleEditors); panel.AddContent(originatorEdit);
			classEdit := NewEditor("*", WMComponents.AlignLeft, spacings[3], HandleEditors); panel.AddContent(classEdit);
			subclassEdit := NewEditor("*", WMComponents.AlignLeft, spacings[4], HandleEditors); panel.AddContent(subclassEdit);
			codeEdit := NewEditor("*", WMComponents.AlignLeft, spacings[5], HandleEditors); panel.AddContent(codeEdit);
			messageEdit := NewEditor("*", WMComponents.AlignLeft, spacings[6], HandleEditors); panel.AddContent(messageEdit);
			
			RETURN panel;
		END CreateFilterPanel;
		
		PROCEDURE CreateStatusPanel() : WMStandardComponents.Panel;
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			NEW(panel); panel.alignment.Set(WMComponents.AlignBottom); panel.bounds.SetHeight(20);
			
			NEW(updateBtn); updateBtn.alignment.Set(WMComponents.AlignLeft); updateBtn.bounds.SetWidth(80);
			updateBtn.caption.SetAOC("Update"); updateBtn.onClick.Add(HandleButtons);
			panel.AddContent(updateBtn);
			
			NEW(clearBtn); clearBtn.alignment.Set(WMComponents.AlignLeft); clearBtn.bounds.SetWidth(80);
			clearBtn.caption.SetAOC("Clear"); clearBtn.onClick.Add(HandleButtons);
			panel.AddContent(clearBtn);
			
			NEW(statusLabel); statusLabel.alignment.Set(WMComponents.AlignClient);
			statusLabel.fillColor.Set(WMGraphics.White);
			panel.AddContent(statusLabel);
			
			RETURN panel;
		END CreateStatusPanel;
	
		PROCEDURE Finalize;
		BEGIN
			state := Terminating; timer.Wakeup;
			BEGIN {EXCLUSIVE} AWAIT(state = Terminated); END;
			Finalize^;
		END Finalize;
		
		PROCEDURE SetEvents*(events : AosEventsUtils.EventContainer);
		BEGIN {EXCLUSIVE} 
			SELF.events := events;
			containerSize := events.GetSize();
			UpdateStatusLabel;
			update := TRUE; fullUpdate := TRUE; timer.Wakeup;
		END SetEvents;
		
		PROCEDURE ClearLog;
		BEGIN {EXCLUSIVE} 
			IF events # NIL THEN events.Clear; END;
		END ClearLog;		
	
		PROCEDURE &Init;
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			Init^;
			
			NEW(spacings, NofColumns); 
			spacings[0] := 110; spacings[1] := 80; spacings[2] := 120; spacings[3] := 40; spacings[4] := 40;
			spacings[5] := 40; spacings[6] := 600;
			
			panel := CreateStatusPanel(); AddContent(panel);
			panel := CreateFilterPanel(); AddContent(panel);
			grid := NewGrid(); AddContent(grid);
			state := Running;
			NEW(timer);
			lastCleared := -1; lastStamp := -1;
		END Init;
		
	BEGIN {ACTIVE}
		WHILE state = Running DO
			BEGIN {EXCLUSIVE} 
				IF (events # NIL) THEN
					stamp := events.GetStamp();
					IF (stamp # lastStamp) THEN
						update := TRUE;
						lastStamp := stamp;
					ELSE
						update := FALSE;
					END;
				ELSE
					update := FALSE; 
				END;
			END;
			IF fullUpdate OR update THEN Update; END;
			timer.Sleep(PollingInterval);
		END;
		BEGIN {EXCLUSIVE} state := Terminated; END;
	END EventLog;
	
TYPE

	KillerMsg = OBJECT
	END KillerMsg;

	Window = OBJECT(WMComponents.FormWindow)
	VAR 
		eventLog : EventLog;
		loadBtn, storeBtn : WMStandardComponents.Button;
		filenameEdit : WMEditors.Editor;
				
		PROCEDURE HandleLoadButton(sender, data : ANY);
		VAR events : AosEventsUtils.EventContainer; filename, msg : ARRAY 256 OF CHAR; res : LONGINT;
		BEGIN
			filenameEdit.GetAsString(filename);
			IF filename # "" THEN
				AosEventsUtils.LoadFromFile(filename, events, msg, res);
				IF (res = AosEventsUtils.Ok) THEN
					SetEvents(events);
				ELSIF (res = AosEventsUtils.Uncomplete) THEN
					SetEvents(events);
					res := WMDialogs.Message("Warning", msg, {WMDialogs.ResOk});
				ELSE
					res := WMDialogs.Message("Error", msg, {WMDialogs.ResOk});
				END;
			END;
		END HandleLoadButton;
		
		PROCEDURE HandleStoreButton(sender, data : ANY);
		VAR filename, msg : ARRAY 256 OF CHAR; res : LONGINT;
		BEGIN
			filenameEdit.GetAsString(filename);
			IF (filename # "") & (eventLog.events # NIL) THEN
				AosEventsUtils.StoreToFile(filename, eventLog.events, msg, res);
				IF res # AosEventsUtils.Ok THEN
					res := WMDialogs.Message("Error", msg, {WMDialogs.ResOk});
				END;
			END;
		END HandleStoreButton;
		
		PROCEDURE SetEvents(events : AosEventsUtils.EventContainer);
		BEGIN
			eventLog.SetEvents(events);
		END SetEvents;		
		
		PROCEDURE CreateFilePanel() : WMComponents.VisualComponent;
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			NEW(panel); panel.alignment.Set(WMComponents.AlignTop); panel.bounds.SetHeight(20);
			
			NEW(loadBtn); loadBtn.alignment.Set(WMComponents.AlignLeft); loadBtn.bounds.SetWidth(80);
			loadBtn.caption.SetAOC("Load"); loadBtn.onClick.Add(HandleLoadButton);
			panel.AddContent(loadBtn);
			
			NEW(storeBtn); storeBtn.alignment.Set(WMComponents.AlignLeft); storeBtn.bounds.SetWidth(80);
			storeBtn.caption.SetAOC("Store"); storeBtn.onClick.Add(HandleStoreButton);
			panel.AddContent(storeBtn);
			
			NEW(filenameEdit); filenameEdit.alignment.Set(WMComponents.AlignClient);
			filenameEdit.multiLine.Set(FALSE);
			filenameEdit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); filenameEdit.tv.showBorder.Set(TRUE);
			filenameEdit.fillColor.Set(WMGraphics.White);
			panel.AddContent(filenameEdit);
			
			RETURN panel;
		END CreateFilePanel;
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR panel : WMStandardComponents.Panel;
		BEGIN
			NEW(panel); panel.alignment.Set(WMComponents.AlignClient);
			
			panel.AddContent(CreateFilePanel());
			
			NEW(eventLog); eventLog.alignment.Set(WMComponents.AlignClient); 
			eventLog.fillColor.Set(WMGraphics.Black);
			panel.AddContent(eventLog);
			
			RETURN panel;	
		END CreateForm;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS KillerMsg) THEN Close
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("WMEventLog", "WMEventLog.Restore", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;

		PROCEDURE &New(c : WMRestorable.Context);
		VAR vc : WMComponents.VisualComponent;
		BEGIN	
			Init(DefaultWidth, DefaultHeight,  FALSE);
			
			vc := CreateForm();
			SetContent(vc);
			SetTitle(Utilities.NewString("Event Log"));
			
			IF c # NIL THEN 
				WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame});
			ELSE 
				WMWindowManager.DefaultAddWindow(SELF)
			END;			
			IncCount;
		END New;
		
		PROCEDURE Close;
		BEGIN
			Close^;
			DecCount;
		END Close;
	
	END Window;
	
VAR
	nofWindows : LONGINT;

PROCEDURE NewEditor(caption : ARRAY OF CHAR; alignment, width : LONGINT; onEnter : WMEvents.EventListener) : WMEditors.Editor;
VAR editor : WMEditors.Editor;
BEGIN
	NEW(editor); editor.bounds.SetWidth(width); editor.alignment.Set(WMComponents.AlignLeft);
	editor.multiLine.Set(FALSE);
	editor.SetAsString(caption);
	editor.onEnter.Add(onEnter);
	editor.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); editor.tv.showBorder.Set(TRUE);
	editor.fillColor.Set(WMGraphics.White);
	RETURN editor;
END NewEditor;

PROCEDURE Open*(par : ANY) : ANY; (** ~ *)
VAR w : Window;
BEGIN
	NEW(w, NIL);	
	w.SetEvents(AosEventsMemoryLog.GetEvents());
	w.CSChanged;
	RETURN NIL
END Open;

PROCEDURE OpenFile*(par : ANY) : ANY; (** filename ~ *)
VAR 
	r : AosIO.StringReader; filename : ARRAY 256 OF CHAR; 
	w : Window;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(filename);	
	NEW(w, NIL);
	w.filenameEdit.SetAsString(filename);
	w.HandleLoadButton(NIL, NIL);
	RETURN NIL
END OpenFile;

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
	AWAIT(nofWindows = 0);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END WMEventLog.

WMEventLog.Open ~	S.Free WMEventLog ~

WMEventLog.OpenFile test.log ~
