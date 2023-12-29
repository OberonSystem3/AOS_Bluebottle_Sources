MODULE WMTCPTracker;	(** AUTHOR "pjm"; PURPOSE "Watch TCP connections"; *)
(* 21.11.2002 - tf : rewritten to use grid component...  *)
(* 11.01.2004 - tf : rewritten to use string grid, added discard button *)

IMPORT
	AosOut, AosModules, AosIO, AosCommands, WMStandardComponents, 
	AosIP, AosTCP, AosKernel, AosActive, WMRestorable, WMMessages, 
	WMWindowManager, WMGraphics, WMGraphicUtilities, WMRectangles,
	WMComponents, XML, Messages := WMMessages, Utilities, WMGrids, WMStringGrids;

CONST
	Running = 0; Closing = 1; Closed = 2;	(* states *)
	
TYPE
	Closer = OBJECT
		VAR c: AosTCP.Connection;
		
		PROCEDURE &Init(c: AosTCP.Connection);
		BEGIN
			SELF.c := c
		END Init;
		
	BEGIN {ACTIVE}
		c.Close
	END Closer;
	
	Discarder = OBJECT
		VAR c: AosTCP.Connection;
		
		PROCEDURE &Init(c: AosTCP.Connection);
		BEGIN
			SELF.c := c
		END Init;
		
	BEGIN {ACTIVE}
		c.Discard
	END Discarder;
	
	ConnectionArray = POINTER TO ARRAY OF AosTCP.Connection;
	
	Window = OBJECT (WMComponents.FormWindow)
	VAR grid : WMStringGrids.StringGrid;
		delay : LONGINT;
		timer : AosKernel.Timer;
		state : LONGINT;
		
		currentIndex, nofConnections : LONGINT;
		currentList : ConnectionArray;
		colWidth : WMGrids.Spacings;
		f  : WMGraphics.Font;
		
		selectedConnection : AosTCP.Connection;
		detailPanel : WMStandardComponents.Panel;
		closeBtn, discardBtn : WMStandardComponents.Button;
		
		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			toolbar: WMStandardComponents.Panel;
			cBtn, dBtn : WMStandardComponents.Button;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(800, 400);
			panel.takesFocus.Set(TRUE);

			NEW(toolbar); toolbar.fillColor.Set(000FF00FFH); toolbar.bounds.SetHeight(20); 
			toolbar.alignment.Set(WMComponents.AlignBottom);
			panel.AddContent(toolbar);
			detailPanel := toolbar;
			
			NEW(cBtn); cBtn.caption.SetAOC("Close selected connection (think 2x !)");
			cBtn.bounds.SetWidth(panel.bounds.GetWidth() DIV 2);
			cBtn.alignment.Set(WMComponents.AlignLeft);
			toolbar.AddContent(cBtn);
			cBtn.clDefault.Set(0FF0000FFH);
			SELF.closeBtn := cBtn;
			
			NEW(dBtn); dBtn.caption.SetAOC("Discard selected connection (think 2x !)");
			dBtn.bounds.SetWidth(panel.bounds.GetWidth() DIV 2);
			dBtn.alignment.Set(WMComponents.AlignLeft);
			toolbar.AddContent(dBtn);
			dBtn.clDefault.Set(0FF0000FFH);
			SELF.discardBtn := dBtn;			
			
			NEW(grid); grid.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(grid);
			
			RETURN panel
		END CreateForm;
			
		PROCEDURE &New(delay : LONGINT;  c : WMRestorable.Context);
		VAR str : ARRAY 256 OF CHAR;
			i, dx, dy, minWidth : LONGINT;
			 vc : WMComponents.VisualComponent;
			f  : WMGraphics.Font;
		BEGIN
			SELF.delay := delay;
			NEW(timer);
			NEW(currentList, 16 *  1024);
			vc := CreateForm();
						
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);			

			f := WMGraphics.GetFont("Oberon", 12, {});
			grid.fixedCols.Set(4); grid.fixedRows.Set(1); 
			grid.SetSelectionMode(WMGrids.GridSelectSingleRow);
			grid.Acquire;
			grid.model.Acquire;
			grid.model.SetNofCols(32);
			grid.model.SetNofRows(1);
			NEW(colWidth, 32);
			f.GetStringSize("-999999999", minWidth, dy);
			FOR i := 0 TO 32 - 1 DO
				GetTitleStr(i, str);
				f.GetStringSize(str, dx, dy);
				colWidth[i] := Utilities.Max(dx + 4, minWidth);
				grid.model.SetCellText(i, 0, Utilities.NewString(str));
				grid.model.SetTextAlign(i, 0, WMGraphics.AlignCenter);
			END;
			f.GetStringSize("999.999.999.999:99999", dx, dy); colWidth[0] := dx + 4;
			f.GetStringSize("SynReceived", dx, dy); colWidth[2] := dx + 4;
			f.GetStringSize("999.999.999.999", dx, dy); colWidth[3] := dx + 4;
			grid.SetColSpacings(colWidth);
			grid.model.Release;
			grid.Release;
			grid.onClick.Add(Click);
			
			detailPanel.visible.Set(FALSE);
			closeBtn.onClick.Add(CloseConnection);
			discardBtn.onClick.Add(DiscardConnection);
		
			IF c # NIL THEN WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame})				
			ELSE WMWindowManager.DefaultAddWindow(SELF)
			END;

			SetTitle(Utilities.NewString("TCP Tracker")); 
			ScanConnections;
			grid.SetTopPosition(3, 1, TRUE);
			state := Running
		END New;
		
		PROCEDURE GetTitleStr(col: LONGINT; VAR x : ARRAY OF CHAR);
		BEGIN
			CASE col OF
				|0 : COPY("Remote", x)
				|1 : COPY("Local Port", x)
				|2 : COPY("State", x)
				|3 : COPY("Local IP", x)
				|4 : COPY("Idle", x)
				|5 : COPY("RecvAdv", x)
				|6 : COPY("SendNext", x)
				|7 : COPY("SendBuf", x)
				|8 : COPY("SendFree", x)
				|9 : COPY("SendWnd", x)
				|10 : COPY("SendCWnd", x)
				|11 : COPY("RecvFree", x)
				|12 : COPY("RecvWnd", x)
				|13 : COPY("RecvHW", x)
				|14 : COPY("SendUnack", x)
				|15 : COPY("SendMax", x)
				|16 : COPY("RTSN", x)
				|17 : COPY("WUSAN", x)
				|18 : COPY("RecvNext", x)
				|19 : COPY("WUSSN", x)
				|20 : COPY("LASN", x)
				|21 : COPY("SRTT", x)
				|22 : COPY("DupAcks", x)
				|23 : COPY("ReXmitT", x)
				|24 : COPY("Backoff", x)
				|25 : COPY("RTT", x)
				|26 : COPY("RTTVar", x)
				|27 : COPY("RTTMin", x)
				|28 : COPY("MaxSeg", x)
				|29 : COPY("ISS", x)
				|30 : COPY("IRS", x)
				|31 : COPY("SSThresh", x)
			ELSE COPY("", x);
			END
		END GetTitleStr;
		
		PROCEDURE Click(sender, data : ANY);
		BEGIN
			AosOut.String("Cilck"); AosOut.Ln; 
			IF (data # NIL) & (data IS AosTCP.Connection) (* & (data(AosTCP.Connection).state # AosTCP.Listen)*) THEN
				AosOut.String("Huga"); AosOut.Ln; 
				selectedConnection := data(AosTCP.Connection);
				detailPanel.visible.Set(TRUE)
			ELSE detailPanel.visible.Set(FALSE)
			END
		END Click;
		
		PROCEDURE CloseConnection(sender, data : ANY);
		VAR tc : AosTCP.Connection;
			killer : Closer;
		BEGIN
			tc := selectedConnection;
			IF tc # NIL THEN 
				NEW(killer, tc);
				selectedConnection := NIL;
				detailPanel.visible.Set(FALSE)
			END
		END CloseConnection;
		
		PROCEDURE DiscardConnection(sender, data : ANY);
		VAR tc : AosTCP.Connection;
			killer : Discarder;
		BEGIN
			tc := selectedConnection;
			IF tc # NIL THEN 
				NEW(killer, tc);
				selectedConnection := NIL;
				detailPanel.visible.Set(FALSE)
			END
		END DiscardConnection;
		
		PROCEDURE GetAlign(col : LONGINT) : LONGINT;
		BEGIN
			CASE col OF
				0..3 : RETURN WMGraphics.AlignCenter;
			ELSE RETURN WMGraphics.AlignRight
			END
		END GetAlign;
		
		PROCEDURE StateToString(state : LONGINT; VAR str : ARRAY OF CHAR);
		BEGIN
			CASE state OF
				AosTCP.Closed: COPY("Closed", str)
				|AosTCP.Listen: COPY("Listen", str)
				|AosTCP.SynSent: COPY("SynSent", str)
				|AosTCP.SynReceived: COPY("SynReceived", str)
				|AosTCP.Established: COPY("Established", str)
				|AosTCP.CloseWait: COPY("CloseWait", str)
				|AosTCP.FinWait1: COPY("FinWait1", str)
				|AosTCP.Closing: COPY("Closing", str)
				|AosTCP.LastAck: COPY("LastAck", str)
				|AosTCP.FinWait2: COPY("FinWait2", str)
				|AosTCP.TimeWait: COPY("TimeWait", str)
				ELSE COPY("Unknown", str)
			END
		END StateToString;
		
		PROCEDURE GetConnectionStr(x, col: LONGINT; VAR str : ARRAY OF CHAR);
		VAR c : AosTCP.Connection;
				t : ConnectionArray;
				s : ARRAY 64 OF CHAR;
		BEGIN
			t := currentList; (* to prevent problems with not yet implemented shrinking *)
			COPY("", str);
			IF x < LEN(t) THEN 
				c := t[x];
				IF c # NIL THEN
					CASE col OF
						|0 : AosIP.AdrToStr(c.fip, str); Utilities.Append(str, ":"); Utilities.IntToStr(c.fport, s); Utilities.Append(str, s)
						|1 :  Utilities.IntToStr(c.lport, str)
						|2 : StateToString(c.state, str)
						|3 : IF c.int # NIL THEN AosIP.AdrToStr(c.int.localAdr, str); ELSE COPY("n/a", str); END;
						|4: Utilities.IntToStr(c.idle, str)
						|5 : Utilities.IntToStr(c.rcvadv - c.irs, str)
						|6 : Utilities.IntToStr(c.sndnxt - c.iss, str)
						|7: Utilities.IntToStr(c.sndcc, str)
						|8 : Utilities.IntToStr(c.sndspace, str)
						|9 : Utilities.IntToStr(c.sndwnd, str)
						|10 : Utilities.IntToStr(c.sndcwnd, str)
						|11 : Utilities.IntToStr(c.rcvspace, str)
						|12 : Utilities.IntToStr(c.rcvwnd, str)
						|13 : Utilities.IntToStr(c.rcvhiwat, str)
						|14: Utilities.IntToStr(c.snduna - c.iss, str)
						|15 : Utilities.IntToStr(c.sndmax - c.iss, str)
						|16 : Utilities.IntToStr(c.rtseq - c.iss, str)
						|17 : Utilities.IntToStr(c.sndwl2 - c.iss, str)
						|18 : Utilities.IntToStr(c.rcvnxt - c.irs, str)
						|19 : Utilities.IntToStr(c.sndwl1 - c.irs, str)
						|20 : Utilities.IntToStr(c.lastacksent - c.irs, str)
						|21 : Utilities.IntToStr(c.srtt, str)
						|22 : Utilities.IntToStr(c.dupacks, str)
						|23 : Utilities.IntToStr(c.rxtcur, str)
						|24 : Utilities.IntToStr(c.rxtshift, str)
						|25 : Utilities.IntToStr(c.rtt, str)
						|26 : Utilities.IntToStr(c.rttvar, str)
						|27 : Utilities.IntToStr(c.rttmin, str)
						|28 : Utilities.IntToStr(c.maxseg, str)
						|29 : Utilities.IntToStr(c.iss, str)
						|30 : Utilities.IntToStr(c.irs, str)
						|31 : Utilities.IntToStr(c.sndssthresh, str) 
					ELSE
					END
				END;
			END
		END GetConnectionStr;

		PROCEDURE AddConnection(c : AosTCP.Connection);
		VAR t : ConnectionArray; i : LONGINT;
		BEGIN
			IF currentIndex >= LEN(currentList) THEN (* grow the list *)
				NEW(t, LEN(currentList) * 2); FOR i := 0 TO currentIndex - 1 DO t[i] := currentList[i] END;
				currentList := t
			END;
			currentList[currentIndex] := c;
			INC(currentIndex)
		END AddConnection;
						
		PROCEDURE ScanConnections;
		BEGIN {EXCLUSIVE}
			currentIndex := 0;
			AosTCP.pool.Enumerate(AddConnection);
			nofConnections := currentIndex
		END ScanConnections;
		
		PROCEDURE Update;
		VAR i, j : LONGINT; s : Utilities.String;
		BEGIN
			ScanConnections;
			grid.model.Acquire;
			grid.model.SetNofRows(nofConnections + 1);
			FOR i := 0 TO nofConnections - 1 DO
				FOR j := 0 TO 32 - 1 DO
					s := grid.model.GetCellText(j, i + 1); (* recycle the string *) 
					IF s = NIL THEN NEW(s, 64) END;
					GetConnectionStr(i, j, s^);
					grid.model.SetTextAlign(j, i + 1, GetAlign(j));
					grid.model.SetCellData(j, i + 1, currentList[i]);
					grid.model.SetCellText(j, i + 1, s)
				END
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
					x.ext(WMRestorable.Storage).Add("WMTCPTracker", "WMTCPTracker.Restore", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;
		
	BEGIN {ACTIVE}
		WHILE state = Running DO
			Update; grid.Invalidate(); timer.Sleep(delay)
		END;
		BEGIN {EXCLUSIVE} state := Closed END
	END Window;

VAR window : Window;

PROCEDURE FreeWindow;
BEGIN {EXCLUSIVE}
	window := NIL
END FreeWindow;

PROCEDURE Open*(par: PTR): PTR;	(** [ms] *)
VAR s: AosIO.StringReader; delay: LONGINT;
BEGIN
	IF AosTCP.pool # NIL THEN
		WITH par: AosCommands.Parameters DO
			NEW(s, LEN(par.str^)); s.Set(par.str^)
		END;
		s.SkipSpaces; s.Int(delay, FALSE);
		IF delay < 1 THEN delay := 250 END;	(* default delay *)
		BEGIN {EXCLUSIVE}
			IF window = NIL THEN NEW(window, delay, NIL) 
			ELSE WMWindowManager.DefaultBringToView(window, TRUE)
			END
		END
	ELSE AosOut.String("AosTCP.pool = NIL"); AosOut.Ln;  
	END;
	RETURN NIL
END Open;

PROCEDURE Restore*(par: ANY): ANY;
BEGIN{EXCLUSIVE}
	IF window = NIL THEN 
		IF (par # NIL) & (par IS WMRestorable.Context) THEN 
				NEW(window, 250, par(WMRestorable.Context))
		ELSE NEW(window, 250, NIL) 
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
END WMTCPTracker.

S.Free WMTCPTracker WMStringGrids 

WMTCPTracker.Open 250 
AosTestServer.Open 
AosTestServer.Close
WMTCPTracker.Close ~
