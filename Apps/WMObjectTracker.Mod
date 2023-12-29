MODULE WMObjectTracker; (** AUTHOR "tf"; PURPOSE "Visualize active objects"; *)
(* TF 28.09.2000 14:10 *)
(* TF 13.09.2004 Rewrite for new component system *)

IMPORT 
	SYSTEM,
	AosBoot, AosModules, AosHeap, AosTrap, AosCommands, AosKernel, AosActive,
	AosIO, WMRestorable, WMMessages, WMWindowManager, Utilities, WMComponents, 
	WMGrids, WMStringGrids, WMStandardComponents, WMGraphics;

CONST
	Width = 1200;
	Height = 800;
	
CONST
	Running = 0; Closing = 1; Closed = 2;	(* states *)
	
TYPE		
	ProcessList = POINTER TO RECORD
		next: ProcessList;
		thread: AosActive.Process
	END;
	
	Window = OBJECT (WMComponents.FormWindow)
	VAR grid : WMStringGrids.StringGrid;
		nofups, interval, interleave: LONGINT;
		timer : AosKernel.Timer;
		state : LONGINT;
		
		colWidth : WMGrids.Spacings;
		f : WMGraphics.Font;
		
		detailPanel : WMStandardComponents.Panel;
		closeBtn, discardBtn : WMStandardComponents.Button;
		lastProcTime : HUGEINT;
		tl : ProcessList;
		
		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel: WMStandardComponents.Panel;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(800, 400);
			panel.takesFocus.Set(TRUE);
	
			NEW(grid); grid.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(grid);
			
			RETURN panel
		END CreateForm;
			
		PROCEDURE &New(interval, interleave : LONGINT; c : WMRestorable.Context);
		VAR str : ARRAY 256 OF CHAR;
			i, dx, dy, minWidth : LONGINT;
			 vc : WMComponents.VisualComponent;
		BEGIN
			SELF.interval := interval;
			SELF.interleave := interleave;
			NEW(timer);

			vc := CreateForm();
						
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);			
			
			f := WMGraphics.GetFont("Oberon", 12, {});
			grid.fixedCols.Set(2); grid.fixedRows.Set(1); 
			grid.SetSelectionMode(WMGrids.GridSelectSingleRow);			
			grid.Acquire;
			grid.model.Acquire;
			grid.model.SetNofCols(10);
			grid.model.SetNofRows(2);
			NEW(colWidth, 10);
			f.GetStringSize("-999999999", minWidth, dy);
			FOR i := 0 TO 10 - 1 DO
				GetTitleStr(i, str);
				f.GetStringSize(str, dx, dy);
				colWidth[i] := Utilities.Max(dx + 4, minWidth);
				grid.model.SetCellText(i, 0, Utilities.NewString(str));
				grid.model.SetTextAlign(i, 0, WMGraphics.AlignCenter)
			END;
			grid.SetColSpacings(colWidth);
			grid.model.Release;
			grid.Release;

			NEW(timer);
			SetTitle(Utilities.NewString("Object tracker"));
			lastProcTime := AosBoot.GetTimer();
			state := Running;

			IF c # NIL THEN WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame})				
			ELSE WMWindowManager.DefaultAddWindow(SELF)
			END
		END New;
		
		PROCEDURE GetTitleStr(col: LONGINT; VAR x : ARRAY OF CHAR);
		BEGIN
			CASE col OF
				|0 : COPY("PID", x)
				|1 : COPY("CPU%", x)
				|2 : COPY("Prio", x)
				|3 : COPY("Mode", x)
				|4 : COPY("Active Object", x)
				|5 : COPY("CPU Nr", x)
				|6 : COPY("Module", x)
				|7 : COPY("PC", x)
				|8 : COPY("Procedure", x)
				|9 : COPY("Condition", x)
			ELSE COPY("", x);
			END
		END GetTitleStr;

		PROCEDURE GetAlign(col : LONGINT) : LONGINT;
		BEGIN
			CASE col OF
				|4, 6, 8, 9 : RETURN WMGraphics.AlignLeft;
				|2, 5 : RETURN WMGraphics.AlignCenter;
				|0, 1,  7 : RETURN WMGraphics.AlignRight;
			ELSE RETURN WMGraphics.AlignRight
			END
		END GetAlign;
		
		PROCEDURE Refresh;
		VAR
			p, n, c: ProcessList; t : AosActive.Process;
			model : WMStringGrids.StringGridModel;
			i, j : LONGINT; tp : ANY;
		BEGIN (* {EXCLUSIVE} *)
			AosActive.snapshotEnabled := TRUE;

			(* allow GC of RIP procs *)
			model := grid.model;
			model.Acquire;
			FOR i := 0 TO model.GetNofCols() - 1 DO
				FOR j := 0 TO model.GetNofRows() - 1 DO
					model.SetCellData(i, j, NIL)
				END
			END;
			model.Release;
			tl := NIL;
			AosHeap.GC;
			WHILE AosActive.snapshot # NIL DO
				(* remove a node from snapshot list *)
				t := AosActive.snapshot;  AosActive.snapshot := t.link;  t.link := NIL;
				(* insert in sorted list *)
				NEW(n);  n.thread := t;  p := NIL;  c := tl;
				WHILE (c # NIL) & ((c.thread.priority > t.priority) OR ((c.thread.priority = t.priority) & (c.thread.id < t.id))) DO
					p := c;  c := c.next
				END;
				IF p = NIL THEN tl := n ELSE p.next := n END;
				n.next := c
			END;
		END Refresh;

		PROCEDURE Update;
		 VAR t : AosActive.Process;		
			cur : ProcessList;
			i, count : LONGINT;
			str : ARRAY 256 OF CHAR;

			sw : AosIO.StringWriter; 
			t0, t1 : HUGEINT;
			pc : LONGINT;
			mod : AosModules.Module;
			adr : LONGINT;
			
			PROCEDURE SetText(line, cell : LONGINT; t : ANY; VAR str : ARRAY OF CHAR);
			VAR s : Utilities.String;
			BEGIN
				s := grid.model.GetCellText(cell, line); (* recycle the string *) 
				IF s = NIL THEN NEW(s, 64) END;
				COPY(str, s^);
				grid.model.SetTextAlign(cell, line, GetAlign(cell));
				grid.model.SetCellData(cell, line, t);
				grid.model.SetCellText(cell, line, s)
			END SetText;

			PROCEDURE Handle(VAR x: WMMessages.Message);
			BEGIN
				IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
					IF (x.ext IS WMRestorable.Storage) THEN
						x.ext(WMRestorable.Storage).Add("WMObjectTracker", "WMObjectTracker.Open", SELF, NIL)
					ELSE Handle^(x)
					END
				ELSE Handle^(x)
				END
			END Handle;
		
		BEGIN (* {EXCLUSIVE} *)
			(* count  the threads *)
			cur := tl; i := 0; WHILE cur # NIL DO INC(i); cur := cur.next END;
			count := i;
			
			t1 := AosBoot.GetTimer() - lastProcTime;
			lastProcTime := AosBoot.GetTimer();

			grid.model.Acquire;
			grid.model.SetNofRows(count + 1);
			cur := tl; i := 0; 
			WHILE cur # NIL DO
				INC(i);
				t := cur.thread; cur := cur.next;
				t0 := t.perfCyc[0];
				
				(* ID *)
				Utilities.IntToStr(t.id, str); SetText(i, 0, t, str); 

				(* CPU% *)
				Utilities.IntToStr(AosBoot.HIntToLInt(AosBoot.DivH(AosBoot.MulH(t0, 100)  , t1)), str);SetText(i, 1, t, str);
	
				(* priority *)
				Utilities.IntToStr(t.priority, str); SetText(i, 2, t, str);

				(* mode *)
				CASE t.mode OF
					|AosActive.Ready : str := "rdy"
					|AosActive.Running : str := "run"
					|AosActive.AwaitingLock : str := "awl"
					|AosActive.AwaitingCond : str := "awc"
					|AosActive.AwaitingEvent : str := "awe"
					|AosActive.Terminated : str := "rip"
				ELSE str := "???"	
				END;	
				SetText(i, 3, t, str);
				
				(* object type *)
				IF t.obj # NIL THEN
					SYSTEM.GET(SYSTEM.VAL(LONGINT, t.obj)-4, adr);
					NEW(sw, 64); AosTrap.WriteType(sw, adr-adr MOD 8); 
					sw.Get(str);
					SetText(i, 4, t, str)
				END;
				
				(* processor *)
				Utilities.IntToStr(t.procID, str); SetText(i, 5, t, str);
				
				(* Module *)
				pc := t.state.EIP;
				mod := AosModules.ThisModuleByAdr(pc);
				IF mod # NIL THEN SetText(i, 6, t, mod.name)
				ELSE  str := "Unknown"; SetText(i, 6, t, str);
				END;
				
				(* PC *)
				IF mod # NIL THEN DEC(pc, SYSTEM.ADR(mod.code[0])) END;
				Utilities.IntToStr(pc, str); SetText(i, 7, t, str);
				
				(* Procedure *)
				NEW(sw, 64); AosTrap.WriteProc(sw, t.state.EIP); 
				sw.Get(str);
				SetText(i, 8, t, str);
				
				(* Waiting on *)
				str := "";
				IF t.mode = AosActive.AwaitingLock THEN
					adr := SYSTEM.VAL(LONGINT, t.waitingOn);
					IF adr # 0 THEN	(* can be 0 when snapshot is taken *)
						SYSTEM.GET(adr-4, adr); DEC(adr, adr MOD 8);
						IF adr = SYSTEM.TYPECODE(AosModules.Module) THEN
							mod := SYSTEM.VAL(AosModules.Module, adr);
							COPY(mod.name, str)
						ELSE
							NEW(sw, 64); AosTrap.WriteType(sw, adr);
							sw.Get(str)
						END;
					END
				ELSIF t.mode = AosActive.AwaitingCond THEN
					NEW(sw, 64);
					AosTrap.WriteProc(sw, SYSTEM.VAL(LONGINT, t.condition));
					sw.Get(str);
				END;
				SetText(i, 9, t, str);
				
				 t.perfCyc[0] := 0
			END;
			grid.model.Release;
		END Update;

		PROCEDURE Join;
		BEGIN {EXCLUSIVE}
			AWAIT(state = Closed)
		END Join;

		PROCEDURE Close;	(* override *)
		BEGIN 
			BEGIN {EXCLUSIVE}
				IF state = Running THEN state := Closing END;	(* multiple calls possible *)
				timer.Wakeup
			END;
			FreeWindow;
			Close^
		END Close;

		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("WMObjectTracker", "WMObjectTracker.Restore", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;		

	BEGIN {ACTIVE}
		AosActive.SetPriority(AosActive.High);
		WHILE state = Running DO
			IF nofups MOD interleave = 0 THEN Refresh END;
			Update;
			INC(nofups);
			timer.Sleep(interval)
		END;
		BEGIN {EXCLUSIVE} state := Closed END
	END Window;
	
VAR window: Window;


PROCEDURE FreeWindow;
BEGIN {EXCLUSIVE}
	window := NIL
END FreeWindow;

PROCEDURE Open*(par: PTR): PTR;	(** [ms] [interleave] *)
VAR s: AosIO.StringReader; interval, interleave: LONGINT;
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
			IF (par # NIL) & (par IS WMRestorable.Context) THEN
				NEW(window, interval, interleave, par(WMRestorable.Context)) 			
			ELSE NEW(window, interval, interleave, NIL) 
			END
		ELSE
			WMWindowManager.DefaultBringToView(window, TRUE)
		END
	END;
	RETURN NIL
END Open;

PROCEDURE Restore*(par: ANY): ANY;
BEGIN{EXCLUSIVE}
	IF window = NIL THEN 
		IF (par # NIL) & (par IS WMRestorable.Context) THEN 
			NEW(window, 100, 10, par(WMRestorable.Context))
		ELSE NEW(window, 100, 10, NIL) 
		END
	ELSE WMWindowManager.DefaultBringToView(window, TRUE)
	END
END Restore;

PROCEDURE Close*(par: PTR): PTR;
VAR w: Window;
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
	window := NIL;
	AosModules.InstallTermHandler(Cleanup)
END WMObjectTracker.

WMObjectTracker.Open 100 10 ~ 
WMObjectTracker.Close ~
S.Free WMObjectTracker ~ 

Color Codes
 Highlight   Types and Procedures     Lock Acquire / Lock Release
Preferred notation (comment)
Unsafe / Temporary / Stupid / requires attention
Permanent Comment  Assertion   Debug
