MODULE WMObjectTracker; (** AUTHOR "tf"; PURPOSE "Visualize active objects"; *)
(** 
 * History:
 *
 *	23.09.2004	Rewrite for new component system (TF)
 * 	05.06.2006	Adjust column widths when resizing window, show number of active objects, sort by PID/Priority (staubesv)
 *	28.06.2006 	Integrated change provided by FF: User can display stack trace back for processes (staubesv)
 *	19.07.2006	Don't keep reference on threads in CellData, added refresh button, cpu cycles for all cpus (staubesv)
 *)

IMPORT 
	SYSTEM, AosOut,
	AosBoot, AosModules, AosHeap, AosTrap, AosCommands, AosKernel, AosActive,
	AosIO, WMRestorable, WMMessages, Utilities, WMComponents, 
	WMGrids, WMStringGrids, WMStandardComponents, WMGraphics, WMDialogs, WMRectangles, WMPopups,
	WM := WMWindowManager;

CONST

	(* Window size at startup *)
	DefaultWidth = 800; DefaultHeight = 400;
	
	(* States *)
	Running = 0; Closing = 1; Closed = 2;
	
	SortByPid = 0; SortByPriority = 1;
	
TYPE		

	SortInfo = OBJECT
	VAR
		mode : LONGINT;
		name : ARRAY 64 OF CHAR;
		
		PROCEDURE &New(mode : LONGINT; name : ARRAY OF CHAR);
		BEGIN
			SELF.mode := mode;
			COPY(name, SELF.name);
		END New;
		
	END SortInfo;
	
TYPE

	ProcessList = POINTER TO RECORD
		next : ProcessList;
		thread : AosActive.Process;
	END;
	
TYPE
	
	Window = OBJECT (WMComponents.FormWindow)
	VAR 
		grid : WMStringGrids.StringGrid;
		nofups, interval, interleave : LONGINT;
		timer : AosKernel.Timer;
		state : LONGINT;
		
		colWidth : WMGrids.Spacings;
		f : WMGraphics.Font;
		
		haltBtn, unbreakHaltBtn, showBtn : WMStandardComponents.Button;
		
		sortBtn : WMStandardComponents.Button;
		sortPopup : WMPopups.Popup;
		sortMode : LONGINT;
		
		refreshBtn : WMStandardComponents.Button;

		nbrOfProcessesLabel : WMStandardComponents.Label;
		
		lastProcTime : HUGEINT;

		tl : ProcessList;
		
		sw : AosIO.StringWriter; (* Only use in procedure Update *)

		PROCEDURE Decision(message : ARRAY OF CHAR) : BOOLEAN;
		BEGIN
			RETURN WMDialogs.Message("Confirm terminating process", message, {WMDialogs.ResNo, WMDialogs.ResYes}) = WMDialogs.ResYes;			
		END Decision;
		
		PROCEDURE HaltThread(unbreakable : BOOLEAN);
		VAR
			scol, srow, ecol, erow, threadID, i : LONGINT;
			str : Utilities.String;
			process : ProcessList;
		BEGIN						
			(* One can halt more than one process, else adapt selection mode. *)
			grid.GetSelection(scol, srow, ecol, erow);
			grid.Acquire;
			grid.model.Acquire;
			FOR i := srow TO erow DO
				str := grid.model.GetCellText(0, i); (* Get the Process ID *) 
				Utilities.StrToInt(str^, threadID);
				IF threadID > 0 THEN
					process := tl;
					WHILE (process # NIL) & (process.thread.id # threadID) DO
						process := process.next
					END;
					IF process # NIL THEN
						(* Make these checks before acquiring the locks *)
						IF (AosActive.Resistant IN tl.thread.flags) THEN
							IF Decision("Teminate a resistant process") THEN
								AosActive.TerminateThis(process.thread, unbreakable);
							END
						ELSE
							AosActive.TerminateThis(process.thread, unbreakable);
						END;											
					END;
				END;
			END;
			grid.model.Release;
			grid.Release;
		END HaltThread;

		PROCEDURE HandleHalt(sender, data : ANY);
		BEGIN
			HaltThread(FALSE);
		END HandleHalt;

		PROCEDURE HandleUnbreakableHalt(sender, data : ANY);
		BEGIN 
			HaltThread(TRUE);
		END HandleUnbreakableHalt;		
		
		PROCEDURE HandleSort(sender, data : ANY);
		VAR rectangle: WMRectangles.Rectangle;
		BEGIN
			rectangle := sortBtn.bounds.Get();
			sortPopup.Popup(bounds.l + rectangle.l, bounds.b + rectangle.b- 20);
		END HandleSort;
		
		PROCEDURE HandleSortPopup(sender, data : ANY);
		VAR string, caption : ARRAY 100 OF CHAR; newSortMode : LONGINT; sortInfo : SortInfo;
		BEGIN
			IF (data # NIL) & (data IS SortInfo) THEN
				sortPopup.Close;
				sortInfo := data(SortInfo);
				IF sortMode # sortInfo.mode THEN				
					sortMode := sortInfo.mode;
					sortBtn.caption.SetAOC(sortInfo.name);					
					Refresh;
				END;
			END;
		END HandleSortPopup;
		
		PROCEDURE HandleShowStack(sender, data : ANY);
		BEGIN 
			ShowStack;
		END HandleShowStack;	
		
		PROCEDURE HandleRefresh(sender, data : ANY);
		BEGIN
			Refresh;
			timer.Wakeup;
		END HandleRefresh;
		
		PROCEDURE ShowStack;
		VAR 
			w: AosIO.Writer;	
			scol, srow, ecol, erow, id, i : LONGINT;
			pl: ProcessList; t: AosActive.Process; str: Utilities.String;
		BEGIN
			AosIO.OpenWriter(w, AosOut.Send); 
			(* One can halt more than one process, else adapt selection mode. *)
			grid.GetSelection(scol, srow, ecol, erow);
			grid.Acquire;
			grid.model.Acquire;
			FOR i := srow TO erow DO
				str := grid.model.GetCellText(0, i); (* Get the Process ID *) 
				Utilities.StrToInt(str^, id);
				IF id > 0 THEN
					pl := tl;
					WHILE (pl # NIL) & (pl.thread.id # id) DO
						pl := pl.next
					END;
					IF pl # NIL THEN
						(* Make these checks before acquiring the locks *)
						t := pl.thread; 
						
						w.String("Active Object: "); WriteActiveObject(t, w); w.Ln;
						w.String("Current Procedure: "); 
						AosTrap.WriteProc(w,t.state.EIP); w.Ln;
			
						(* mode *)
						w.String("Mode: "); WriteMode(t.mode, w); w.Ln;
						w.String("Waiting On: "); WriteWaitingOn(t, w); w.Ln;
						
						(* Flags *)
						w.String("Flags: "); WriteFlags(t.flags, w); w.Ln;
								
						w.String("Stack Trace Back:"); w.Ln; w.Update;
						AosTrap.StackTraceBack(w, t.state.EIP, t.state.EBP, TRUE, FALSE); 
						w.Ln; w.Update;
					END;
				END;
			END; (* FOR *)
			pl := NIL; t := NIL;
			grid.model.Release;
			grid.Release;
		END ShowStack;
		
		PROCEDURE Resized(width, height : LONGINT);
		VAR w, add, i : LONGINT; newColWidth : WMGrids.Spacings;
		BEGIN
			NEW(newColWidth, LEN(colWidth));
			FOR i := 0 TO LEN(colWidth)-1 DO 
				w := w + colWidth[i]; 
				newColWidth[i] := colWidth[i];
			END;
			
			IF w < width THEN
				add := (width - w) DIV 3;
				INC(newColWidth[6], add);
				INC(newColWidth[8], add);
				INC(newColWidth[9], add);
				
				colWidth := newColWidth;
				grid.SetColSpacings(colWidth);
			END;
					
			Resized^(width, height);
		END Resized;							

		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			panel, toolbar : WMStandardComponents.Panel;
			font : WMGraphics.Font; dx, dy : LONGINT;
			sortInfo : SortInfo;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(DefaultWidth, DefaultHeight);
			panel.takesFocus.Set(TRUE);
			
			NEW(toolbar);
			toolbar.bounds.SetHeight(20);
			toolbar.alignment.Set(WMComponents.AlignBottom);			
			panel.AddContent(toolbar);
			
			NEW(haltBtn);			
			haltBtn.alignment.Set(WMComponents.AlignLeft);
			haltBtn.SetCaption("Halt process");
			haltBtn.onClick.Add(HandleHalt);
			toolbar.AddContent(haltBtn);

			font := haltBtn.GetFont();
			font.GetStringSize(" Halt process ", dx, dy);			
			haltBtn.bounds.SetWidth(dx);
			
			NEW(unbreakHaltBtn);
			unbreakHaltBtn.alignment.Set(WMComponents.AlignLeft);
			unbreakHaltBtn.SetCaption("Halt process unbreakable");
			unbreakHaltBtn.onClick.Add(HandleUnbreakableHalt);
			toolbar.AddContent(unbreakHaltBtn);

			font := unbreakHaltBtn.GetFont();
			font.GetStringSize(" Halt process unbreakable ", dx, dy);			
			unbreakHaltBtn.bounds.SetWidth(dx);
			
			NEW(sortBtn);
			sortBtn.bounds.SetWidth(80); sortBtn.alignment.Set(WMComponents.AlignLeft);
			sortBtn.caption.SetAOC("SortBy:PID");
			sortBtn.onClick.Add(HandleSort);
			toolbar.AddContent(sortBtn);
			
			NEW(sortPopup);
			NEW(sortInfo, SortByPid, "SortBy:PID"); sortPopup.AddParButton("PID", HandleSortPopup, sortInfo);
			NEW(sortInfo, SortByPriority, "SortBy:Priority"); sortPopup.AddParButton("Priority", HandleSortPopup, sortInfo);
			
			NEW(showBtn);
			showBtn.alignment.Set(WMComponents.AlignLeft);
			showBtn.SetCaption(" Show Stack ");
			showBtn.onClick.Add(HandleShowStack);
			toolbar.AddContent(showBtn);
			font := showBtn.GetFont();
			font.GetStringSize(" Show Stack ", dx, dy);			
			showBtn.bounds.SetWidth(dx);
			
			NEW(nbrOfProcessesLabel);
			nbrOfProcessesLabel.alignment.Set(WMComponents.AlignClient);
			nbrOfProcessesLabel.textColor.Set(WMGraphics.White);
			toolbar.AddContent(nbrOfProcessesLabel);
			
			NEW(refreshBtn);
			refreshBtn.alignment.Set(WMComponents.AlignRight);
			refreshBtn.SetCaption("Refresh");
			refreshBtn.onClick.Add(HandleRefresh);
			toolbar.AddContent(refreshBtn);
	
			NEW(grid); grid.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(grid);
			
			RETURN panel
		END CreateForm;				
			
		PROCEDURE &New(interval, interleave : LONGINT; c : WMRestorable.Context);
		VAR 
			vc : WMComponents.VisualComponent;
			str : ARRAY 256 OF CHAR;
			i, dx, dy, minWidth : LONGINT;
		BEGIN
			SELF.interval := interval; 
			SELF.interleave := interleave;
			NEW(timer);
			NEW(sw, 128);
			
			vc := CreateForm();
						
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);			
			SetTitle(Utilities.NewString("Object Tracker"));
			
			f := WMGraphics.GetFont("Oberon", 12, {});
			grid.fixedCols.Set(2); grid.fixedRows.Set(1); 
			grid.SetSelectionMode(WMGrids.GridSelectRows);			
			grid.Acquire;
			grid.model.Acquire;
			grid.model.SetNofCols(11);
			grid.model.SetNofRows(2);
			NEW(colWidth, 11);
			f.GetStringSize("-999999999", minWidth, dy);
			FOR i := 0 TO 5 DO
				GetTitleStr(i, str);
				f.GetStringSize(str, dx, dy);
				colWidth[i] := Utilities.Max(dx + 4, 30);
				grid.model.SetCellText(i, 0, Utilities.NewString(str));
				grid.model.SetTextAlign(i, 0, WMGraphics.AlignCenter)
			END;
			FOR i := 6 TO 11 - 1 DO
				GetTitleStr(i, str);
				f.GetStringSize(str, dx, dy);
				colWidth[i] := Utilities.Max(dx + 4, minWidth+ 40);
				grid.model.SetCellText(i, 0, Utilities.NewString(str));
				grid.model.SetTextAlign(i, 0, WMGraphics.AlignCenter)
			END;
			grid.SetColSpacings(colWidth);
			grid.model.Release;
			grid.Release;

			lastProcTime := AosBoot.GetTimer();
			state := Running;
			
			Resized(DefaultWidth, DefaultHeight);

			IF c # NIL THEN WMRestorable.AddByContext(SELF, c, {WM.FlagFrame})				
			ELSE WM.DefaultAddWindow(SELF)
			END
		END New;
		
		PROCEDURE GetTitleStr(col : LONGINT; VAR x : ARRAY OF CHAR);
		BEGIN
			CASE col OF
				| 0 : COPY("PID", x)
				| 1 : COPY("CPU #", x)
				| 2 : COPY("CPU %", x)
				| 3 : COPY("Prio", x)
				| 4 : COPY("Mode", x)
				| 5 : COPY("PC", x)
				| 6 : COPY("Active Object", x)
				| 7 : COPY("Module", x)
				| 8 : COPY("Procedure", x)
				| 9 : COPY("Await condition", x)
				| 10 : COPY("Flags", x);
			ELSE COPY("", x);
			END
		END GetTitleStr;

		PROCEDURE GetAlign(col : LONGINT) : LONGINT;
		BEGIN
			CASE col OF
				| 6, 7, 8, 9, 10 : RETURN WMGraphics.AlignLeft;
				| 3, 1 : RETURN WMGraphics.AlignCenter;
				| 0, 2, 4, 5 : RETURN WMGraphics.AlignRight;
			ELSE RETURN WMGraphics.AlignRight
			END
		END GetAlign;
		
		PROCEDURE WriteMode(mode : LONGINT; w : AosIO.Writer);
		BEGIN
			CASE mode OF
				|AosActive.Ready : w.String("rdy");
				|AosActive.Running : w.String("run");
				|AosActive.AwaitingLock : w.String("awl");
				|AosActive.AwaitingCond : w.String("awc");
				|AosActive.AwaitingEvent : w.String("awe");
				|AosActive.Terminated : w.String("rip");
			ELSE w.String("???");
			END;
			w.Update;
		END WriteMode;
		
		PROCEDURE WriteFlags(flags : SET; w : AosIO.Writer);
		VAR comma : BOOLEAN;
		BEGIN	
			comma := FALSE;
			IF AosActive.Restart IN flags THEN 
				w.String("restart"); comma := TRUE; 
			END;
			IF AosActive.Resistant IN flags THEN
				IF comma THEN w.String(", "); END;
				w.String("resistant"); comma := TRUE;
			END;
			IF AosActive.Preempted IN flags THEN
				IF comma THEN w.String(", "); END;
				w.String("preempted"); comma := TRUE;
			END;
			IF AosActive.PleaseHalt IN flags THEN
				IF comma THEN w.String(", "); END;
				w.String("pleaseHalt");
			END;
			w.Update;
		END WriteFlags;
		
		PROCEDURE WriteActiveObject(t : AosActive.Process; w : AosIO.Writer);
		VAR adr : LONGINT;
		BEGIN
			IF t.obj # NIL THEN
				SYSTEM.GET(SYSTEM.VAL(LONGINT, t.obj)-4, adr);
				AosTrap.WriteType(w, adr-adr MOD 8); 
			END;			
		END WriteActiveObject;
		
		PROCEDURE WriteWaitingOn(t : AosActive.Process; w : AosIO.Writer);
		VAR adr : LONGINT; mod : AosModules.Module;
		BEGIN
			IF t.mode = AosActive.AwaitingLock THEN
				adr := SYSTEM.VAL(LONGINT, t.waitingOn);
				IF adr # 0 THEN	(* can be 0 when snapshot is taken *)
					SYSTEM.GET(adr-4, adr); DEC(adr, adr MOD 8);
					IF adr = SYSTEM.TYPECODE(AosModules.Module) THEN
						mod := SYSTEM.VAL(AosModules.Module, adr);
						w.String(mod.name);
					ELSE
						AosTrap.WriteType(w, adr);
					END;
				END
			ELSIF t.mode = AosActive.AwaitingCond THEN
				AosTrap.WriteProc(w, SYSTEM.VAL(LONGINT, t.condition));
			END;
			w.Update;
		END WriteWaitingOn;

		PROCEDURE Refresh;
		VAR p, n, c : ProcessList; t : AosActive.Process;	
		BEGIN			
			tl := NIL;
			
			(* generate new snapshot of processes as sideeffect of garbage collection *)
			AosActive.snapshotEnabled := TRUE;
			AosHeap.GC; 
		
			grid.model.Acquire;
			WHILE AosActive.snapshot # NIL DO
				(* remove a node from snapshot list *)
				t := AosActive.snapshot;  AosActive.snapshot := t.link;  t.link := NIL;
				(* insert in sorted list *)
				NEW(n);  n.thread := t;
				p := NIL;  c := tl;
				IF sortMode = SortByPid THEN
					WHILE (c # NIL) & ((c.thread.id > t.id) OR ((c.thread.id = t.id) & (c.thread.id < t.id))) DO
						p := c;  c := c.next;
					END;
				ELSIF sortMode = SortByPriority THEN
					WHILE (c # NIL) & ((c.thread.priority > t.priority) OR ((c.thread.priority = t.priority) & (c.thread.priority < t.priority))) DO
						p := c;  c := c.next;
					END;
				ELSE
					HALT(99);
				END;
				IF p = NIL THEN tl := n ELSE p.next := n END;
				n.next := c
			END;
			grid.model.Release;
		END Refresh;

		PROCEDURE Update;
		VAR 
			t : AosActive.Process; cur : ProcessList;
			i, posP, beg, nbrOfThreads, cpuNbr : LONGINT;
			mod : AosModules.Module;
			str : ARRAY 256 OF CHAR;
			t0, t1, perfCyc, thisProcTime : HUGEINT;
			pc : LONGINT;
			
			PROCEDURE SetText(line, cell : LONGINT; VAR str : ARRAY OF CHAR);
			VAR s : Utilities.String;
			BEGIN
				s := grid.model.GetCellText(cell, line); (* recycle the string *) 
				IF s = NIL THEN NEW(s, 64) END;
				COPY(str, s^);
				grid.model.SetTextAlign(cell, line, GetAlign(cell));
				grid.model.SetCellText(cell, line, s)
			END SetText;
		
		BEGIN
			(* count  the threads *)
			cur := tl; 
			nbrOfThreads := 0; WHILE cur # NIL DO INC(nbrOfThreads); cur := cur.next END;
			
			sw.Reset; sw.String("   "); sw.Int(nbrOfThreads, 0); sw.String(" active objects"); sw.Get(str);
			nbrOfProcessesLabel.caption.SetAOC(str);
				
			t1 := AosBoot.GetTimer() - lastProcTime;
			lastProcTime := AosBoot.GetTimer();

			grid.model.Acquire;
			grid.model.SetNofRows(nbrOfThreads + 1);

			cur := tl; i := 0; 
			WHILE cur # NIL DO
				INC(i);
				t := cur.thread; cur := cur.next;

				(* PID Process ID - 0 *)
				Utilities.IntToStr(t.id, str); SetText(i, 0, str); 

				(* CPU - processor number - 1 *)
				Utilities.IntToStr(t.procID, str); SetText(i, 1, str);
				
				(* CPU% - 2 *)				
				t0 := t.perfCyc[0];
				Utilities.IntToStr(AosBoot.HIntToLInt(AosBoot.DivH(AosBoot.MulH(t0, 100)  , t1)), str);SetText(i, 2, str);
	

				(* priority - 3 *)
				Utilities.IntToStr(t.priority, str); SetText(i, 3, str);

				(* mode - 4 *)
				sw.Reset; WriteMode(t.mode, sw); sw.Get(str); SetText(i, 4, str);
				
				(* PC - 5 *)
				IF mod # NIL THEN DEC(pc, SYSTEM.ADR(mod.code[0])) END;
				Utilities.IntToStr(pc, str); SetText(i, 5, str);
				
				(* active object type - 6 *)
				sw.Reset; WriteActiveObject(t, sw); sw.Get(str);
				SetText(i, 6, str);
				
				(* Module - 7 *)
				pc := t.state.EIP;
				mod := AosModules.ThisModuleByAdr(pc);
				IF mod # NIL THEN SetText(i, 7, mod.name)
				ELSE  str := "Unknown"; SetText(i, 7, str);
				END;
				
				(* Procedure - 8 - Module name (prefix) and "pc=xyz" (suffix) suppressed *)
				sw.Reset; AosTrap.WriteProc(sw, t.state.EIP); 
				sw.Get(str);
				IF (str # "NIL") & (mod#NIL) THEN
					posP := 0;
					REPEAT INC(posP) UNTIL  (posP=LEN(str)) OR (str[posP]=0X)  OR (str[posP] = ".");	(* Skip prefix *)
					INC(posP);
					beg := 0;
					REPEAT
						str[beg] := str[posP];
						INC(beg); INC(posP);
					UNTIL (posP=LEN(str)) OR (str[posP]=0X) OR (str[posP] = " ");	(* Here follows "pc=xyz" now suppressed *)
					str[beg] := 0X
				END;
				SetText(i, 8, str);
				
				(* Waiting on condition - 9 *)
				sw.Reset;  WriteWaitingOn(t, sw);  sw.Get(str);
				SetText(i, 9, str);

				(* Flags - 10 *)
				sw.Reset; WriteFlags(t.flags, sw); sw.Get(str);
				SetText(i, 10, str);				
				
				(* Note: Remove for WinAOS *)
				t.perfCyc[0] := 0;
			END;
			grid.model.Release;
			lastProcTime := AosBoot.GetTimer();
		END Update;

		PROCEDURE Join;
		BEGIN {EXCLUSIVE}
			AWAIT(state = Closed)
		END Join;

		PROCEDURE Close; (* override *)
		BEGIN 
			BEGIN {EXCLUSIVE}
				IF state = Running THEN state := Closing END; (* multiple calls possible *)
				timer.Wakeup
			END;
			Close^;
			window := NIL
		END Close;

		PROCEDURE Handle(VAR x : WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("WMObjectTracker", "WMObjectTracker.Restore", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;		

	BEGIN {ACTIVE, PRIORITY(AosActive.High)}
		WHILE state = Running DO
			IF nofups MOD interleave = 0 THEN Refresh END;
			Update;
			INC(nofups);
			timer.Sleep(interval)
		END;
		BEGIN {EXCLUSIVE}
			state := Closed
		END
	END Window;

VAR
	window : Window;

PROCEDURE Open*(par : PTR) : PTR;	(** [ms] [interleave] *)
VAR s : AosIO.StringReader; interval, interleave : LONGINT;
BEGIN
	WITH par: AosCommands.Parameters DO
		NEW(s, LEN(par.str^)); s.Set(par.str^)
	END;
	s.SkipSpaces; s.Int(interval, FALSE);
	IF interval < 1 THEN interval := 100 END;	(* default interval *)
	s.SkipSpaces; s.Int(interleave, FALSE);
	IF interleave < 1 THEN interleave := 10 END;	(* default interelave *)
	BEGIN {EXCLUSIVE}
		IF window = NIL THEN 
			NEW(window, interval, interleave, NIL)
		ELSE
			WM.DefaultBringToView(window, TRUE)
		END
	END;
	RETURN NIL
END Open;

PROCEDURE Restore*(par : ANY) : ANY;
BEGIN {EXCLUSIVE}
	IF window = NIL THEN 
		IF (par # NIL) & (par IS WMRestorable.Context) THEN 
			NEW(window, 100, 10, par(WMRestorable.Context))
		ELSE 
			NEW(window, 100, 10, NIL) 
		END
	ELSE WM.DefaultBringToView(window, TRUE)
	END;
	RETURN NIL
END Restore;

PROCEDURE Close*(par : PTR) : PTR;
VAR w : Window;
BEGIN
	BEGIN {EXCLUSIVE} w := window END;	(* avoid race between Join call and FreeWindow *)
	IF w # NIL THEN w.Close; w.Join END;
	RETURN NIL
END Close;

PROCEDURE Cleanup;
BEGIN
	IF Close(NIL) = NIL THEN END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMObjectTracker.

WMObjectTracker.Open 200 100 ~ 
WMObjectTracker.Close ~
S.Free WMObjectTracker ~ 

