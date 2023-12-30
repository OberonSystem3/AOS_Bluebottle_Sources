MODULE WMFTPClient; (** AUTHOR "PL"; PURPOSE "FTPClient GUI"; *)

IMPORT
	WMStandardComponents, WMEvents, WMWindowManager, WMComponents, AosFTPClient, AosTextUtilities,
	WMMessages, WMGraphics, Utilities, WMRectangles, AosModules, AosOut, WMPopups, Raster, AosTexts,
	WMEditors, WMGrids, WMStringGrids, WMDialogs, WMProperties, WMDropTarget, AosFS, AosIO;

CONST
	BufSize = 16*1024; (* internal buffer size, used for file transfer *)

TYPE
	KillerMsg = OBJECT
	END KillerMsg;
	
	SelectionWrapper = POINTER TO RECORD
		sel : AosFTPClient.FTPListing;
	END;
	
	 AosFTPDropInterface = OBJECT(WMDropTarget.DropFiles)
	 VAR w : AosIO.Writer;
	 	ftp : AosFTPClient.FTPClient;
	 			
		PROCEDURE &New(ftp : AosFTPClient.FTPClient);
		BEGIN
			SELF.ftp := ftp
		END New;
	
		PROCEDURE OpenPut*(remoteName : ARRAY OF CHAR; VAR outw : AosIO.Writer; VAR res : LONGINT);
		BEGIN
			res := -1;
			IF ftp = NIL THEN RETURN END;
			AosOut.String("Uploading File: "); AosOut.String(remoteName); AosOut.Ln;
			ftp.OpenPut(remoteName, outw, res);
			IF res # 0 THEN AosOut.String("Error: "); AosOut.String(ftp.msg); AosOut.Ln;
			ELSE w := outw END
		END OpenPut;
		
		PROCEDURE ClosePut*(VAR res : LONGINT);
		BEGIN
			res := -1;
			AosOut.String("ClosePut called"); AosOut.Ln;
			IF ftp = NIL THEN RETURN END;
			IF w # NIL THEN w.Update END;
			ftp.ClosePut(res)				
		END ClosePut;
			
	END AosFTPDropInterface;
	
	AosFTPDropTarget = OBJECT(WMDropTarget.DropTarget)
	VAR ftp : AosFTPClient.FTPClient;
		
		PROCEDURE &New(ftp : AosFTPClient.FTPClient);
		BEGIN
			SELF.ftp := ftp
		END New;
		
		PROCEDURE GetInterface*(type : LONGINT) : WMDropTarget.DropInterface;
		VAR di : AosFTPDropInterface;
		BEGIN
			IF type = WMDropTarget.TypeFiles THEN
				NEW(di, ftp); 
				RETURN di
			ELSE RETURN NIL
			END
		END GetInterface;
	END AosFTPDropTarget;	
	
	(* Client Window *)
	Window* = OBJECT (WMComponents.FormWindow)
	VAR
		topToolbar, statusbar : WMStandardComponents.Panel;
		statusLabel, conLabel, busyLabel : WMStandardComponents.Label;
		connect, refresh : WMStandardComponents.Button;
		address, port, cmd : WMEditors.Editor;
		fullList : WMStandardComponents.Checkbox;
		ftpPanel : FTPPanel;
		ftp : AosFTPClient.FTPClient;
		
		connected : BOOLEAN;
		busy : BOOLEAN;
		
		PROCEDURE &New;
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount;
			vc := CreateForm();	
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc); ftpPanel.SetColSize;
			SetTitle(Utilities.NewString("WMFTPClient"));
			WMWindowManager.DefaultAddWindow(SELF);
			
			connected := FALSE;
		END New;
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			panel, pnl : WMStandardComponents.Panel;
			label : WMStandardComponents.Label;
			bearing : WMRectangles.Rectangle;
		
		BEGIN
			NEW(panel); panel.bounds.SetExtents(600, 400); panel.fillColor.Set(0CCCCCCFFH);
			
			bearing := WMRectangles.MakeRect(3, 3, 3, 3);
			
			(* --- Toolbar --- *)
			NEW(topToolbar); topToolbar.bounds.SetHeight(20); topToolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(topToolbar);
			
			NEW(label); label.bounds.SetWidth(40); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC(" Host: "); label.textColor.Set(0000000FFH); topToolbar.AddContent(label);			
			
			NEW(address); address.bounds.SetWidth(150); address.alignment.Set(WMComponents.AlignLeft);
			address.multiLine.Set(FALSE); address.fillColor.Set(0FFFFFFFFH); address.tv.showBorder.Set(TRUE);
			address.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1));
			address.onEnter.Add(ConnectHandler);
			topToolbar.AddContent(address);
			address.SetAsString("bluebottle.ethz.ch");
			
			NEW(label); label.bounds.SetWidth(40); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC(" Port: "); label.textColor.Set(0000000FFH); topToolbar.AddContent(label);	
			
			NEW(port); port.bounds.SetWidth(50); port.alignment.Set(WMComponents.AlignLeft);		
			port.multiLine.Set(FALSE); port.fillColor.Set(0FFFFFFFFH); port.tv.showBorder.Set(TRUE);
			port.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1)); port.SetAsString("21");
			topToolbar.AddContent(port);
			
			NEW(connect); connect.bounds.SetWidth(100); connect.alignment.Set(WMComponents.AlignLeft);
			connect.caption.SetAOC("Connect"); connect.onClick.Add(ConnectHandler);
			topToolbar.AddContent(connect);
			
			NEW(refresh); refresh.bounds.SetWidth(100); refresh.alignment.Set(WMComponents.AlignLeft);
			refresh.caption.SetAOC("Refresh"); refresh.onClick.Add(RefreshHandler);
			topToolbar.AddContent(refresh);
			
			NEW(fullList); fullList.bearing.Set(bearing); fullList.bounds.SetWidth(14); fullList.alignment.Set(WMComponents.AlignLeft);
			topToolbar.AddContent(fullList); fullList.state.Set(1);
			
			NEW(label); label.bounds.SetWidth(100); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC(" Full Listing"); label.textColor.Set(0000000FFH); topToolbar.AddContent(label);	
						
			(* --- statusbar --- *)
			NEW(statusbar); statusbar.bounds.SetHeight(20); statusbar.alignment.Set(WMComponents.AlignBottom);
			panel.AddContent(statusbar);
			
			NEW(conLabel); conLabel.bounds.SetWidth(14); conLabel.alignment.Set(WMComponents.AlignLeft);
			statusbar.AddContent(conLabel); conLabel.bearing.Set(bearing); conLabel.fillColor.Set(0CC0000FFH);
			
			NEW(busyLabel); busyLabel.bounds.SetWidth(14); busyLabel.alignment.Set(WMComponents.AlignLeft);
			statusbar.AddContent(busyLabel); busyLabel.bearing.Set(bearing); busyLabel.fillColor.Set(0888888FFH);
			
			NEW(statusLabel); statusLabel.bounds.SetWidth(400); statusLabel.alignment.Set(WMComponents.AlignLeft);
			statusLabel.textColor.Set(0000000FFH);
			(* statusbar.AddContent(statusLabel); *)
			
			(* --- cmd --- *)
			NEW(pnl); pnl.bounds.SetHeight(20); pnl.alignment.Set(WMComponents.AlignBottom);
			(* panel.AddContent(pnl); *)

			NEW(label); label.bounds.SetWidth(80); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC(" Command: "); label.textColor.Set(0000000FFH); pnl.AddContent(label);	
			
			NEW(cmd); cmd.alignment.Set(WMComponents.AlignClient);
			cmd.multiLine.Set(FALSE); cmd.fillColor.Set(0FFFFFFFFH); cmd.tv.showBorder.Set(TRUE);
			cmd.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1));
			cmd.onEnter.Add(CommandHandler);
			pnl.AddContent(cmd);
			
			statusbar.AddContent(pnl);

			(* --- FTP main panel --- *)
			NEW(ftpPanel); ftpPanel.alignment.Set(WMComponents.AlignClient); ftpPanel.fillColor.Set(0FFFFFFFFH);
			panel.AddContent(ftpPanel);
			ftpPanel.owner := SELF;
			
			RETURN panel
		END CreateForm;
		
		(* -- Handlers -------------------------------------- *)
		
		PROCEDURE ConnectHandler(sender, data : ANY);
		BEGIN
			IF connected THEN Disconnect ELSE Connect END			
		END ConnectHandler;
		
		PROCEDURE Connect;
		VAR user, pass, host, temp : ARRAY 64 OF CHAR;
			port, res : LONGINT;
		BEGIN
			IF ftp # NIL THEN 
				AosOut.String("Already open"); AosOut.Ln; RETURN
			END;
			user := "anonymous";
			pass := "anonymous@somewhere.net";
			IF WMDialogs.QueryString("Enter Username:", user) = WMDialogs.ResOk THEN
				IF WMDialogs.QueryPassword("Enter Password", pass) = WMDialogs.ResOk THEN
					address.GetAsString(host);
					IF (host = "") THEN RETURN END; (* check addy *)
					SELF.port.GetAsString(temp); Utilities.StrToInt(temp, port);
					
					NEW(ftp);
					ftp.Open(host, user, pass, port, res);
					AosOut.String(ftp.msg);
					IF res = 0 THEN
						AosOut.String("Connected"); AosOut.Ln;
						SetConnected(TRUE);
						RefreshHandler(SELF, NIL);
					ELSE
						ftp := NIL;
						AosOut.String("Connecting failed"); AosOut.Ln; 
					END				
				END
			END
		END Connect;
		
		PROCEDURE Disconnect;
		VAR res : LONGINT;
		BEGIN
			IF ftp = NIL THEN 
				AosOut.String("not connected"); AosOut.Ln; 
				RETURN
			END;
			ftp.Close(res);
			AosOut.String("closed."); AosOut.String(ftp.msg); AosOut.Ln; 
			ftp := NIL; ftpPanel.curList := NIL; ftpPanel.nofEntries := 0; ftpPanel.PrepareList; ftpPanel.pathEdit.SetAsString("/");
			SetConnected(FALSE);
			SetBusy(FALSE)
		END Disconnect;
		
		PROCEDURE Close;
		BEGIN
			IF ftp # NIL THEN Disconnect END;
			Close^;
			DecCount
		END Close;
		
		PROCEDURE CommandHandler(sender, data : ANY);
		VAR res : LONGINT; command : ARRAY 256 OF CHAR;
		BEGIN
			IF ftp = NIL THEN 
				AosOut.String("not connected"); AosOut.Ln; 
				RETURN
			END;
			SetBusy(TRUE);
			cmd.GetAsString(command);
			IF command # "" THEN ftp.Raw(command, res) END;
			cmd.SetAsString("");
			SetBusy(FALSE)
		END CommandHandler;
		
		PROCEDURE ListHandler(sender, data : ANY);
		BEGIN
			IF ftp = NIL THEN 
				AosOut.String("not connected"); AosOut.Ln; 
				RETURN
			END;
			SetBusy(TRUE);
			IF fullList.state.Get() = 1 THEN			
				ftp.EnumerateDir("")
			ELSE
				ftp.EnumerateNames
			END;
			ftpPanel.curList := ftp.listing; ftpPanel.nofEntries := ftp.nofEntries;	
			ftpPanel.PrepareList;
			SetBusy(FALSE)			
		END ListHandler;
		
		PROCEDURE ChangeDir(path :Utilities.String);
		VAR res : LONGINT; dir : ARRAY 256 OF CHAR;
		BEGIN
			IF ftp = NIL THEN 
				AosOut.String("not connected"); AosOut.Ln; 
				RETURN
			END;
			SetBusy(TRUE);
			ftp.ChangeDir(path^, res);
			IF res = 0 THEN
				ftp.GetCurrentDir(dir, res);
				IF res = 0 THEN
					ftpPanel.pathEdit.SetAsString(dir);
					ListHandler(SELF, NIL)
				END;
			ELSE
				AosOut.String("no such directory"); AosOut.Ln; 
			END;
			SetBusy(FALSE)
		END ChangeDir;	
		
		PROCEDURE RefreshHandler(sender, data : ANY);
		VAR test : BOOLEAN;
		BEGIN
			ftpPanel.SetColSize;
			IF ftp # NIL THEN
				test := ftp.IsAlive();
				IF test THEN ListHandler(SELF, NIL)
				ELSE Disconnect END;
			END
		END RefreshHandler;
		
		PROCEDURE ShowStatusMsg(msg : ARRAY  OF CHAR);
		BEGIN
			statusLabel.caption.SetAOC(msg);
		END ShowStatusMsg;
		
		PROCEDURE SetConnected(con : BOOLEAN);
		BEGIN
			connected := con;
			IF con THEN
				conLabel.fillColor.Set(0CC00FFH);
				connect.caption.SetAOC("Disconnect");								
			ELSE				
				conLabel.fillColor.Set(0CC0000FFH);
				connect.caption.SetAOC("Connect");
			END	
		END SetConnected;
		
		PROCEDURE SetBusy(bus : BOOLEAN);
		BEGIN
			busy := bus;
			IF bus THEN	busyLabel.fillColor.Set(0FF8800FFH)
			ELSE busyLabel.fillColor.Set(0888888FFH)	END	
		END SetBusy;	
	
	END Window;

	(* FTPPanel *)	
 	FTPPanel = OBJECT(WMComponents.VisualComponent)
	VAR grid : WMStringGrids.StringGrid;
		colWidths : WMGrids.Spacings;
		path : WMProperties.StringProperty;
		filter : WMProperties.StringProperty;
		prefixSearch : WMProperties.BooleanProperty;
		filterEdit, pathEdit : WMEditors.Editor;
		popup: WMPopups.Popup; 
		nfiles : LONGINT;
		px, py : LONGINT;
		parent : AosFTPClient.FTPEntry;
		selection : AosFTPClient.FTPListing;
		
		owner : Window;
		curList : AosFTPClient.FTPListing;
		nofEntries : LONGINT;
		
		PROCEDURE &Init;
		VAR label : WMStandardComponents.Label;
			panel : WMStandardComponents.Panel;
		BEGIN
			Init^;
			NEW(parent);
			
			(* new properties *)
			NEW(path, FileListPathProt, NIL, NIL); properties.Add(path);
			NEW(filter, FileListFilterProt, NIL, NIL); properties.Add(filter);

			NEW(panel); panel.bounds.SetHeight(20); panel.alignment.Set(WMComponents.AlignTop);
			panel.fillColor.Set(0CCCCCCFFH); AddContent(panel);
			NEW(label); label.bounds.SetWidth(40); label.alignment.Set(WMComponents.AlignLeft);
			label.caption.SetAOC(" Path: "); panel.AddContent(label); label.textColor.Set(0000000FFH);
			NEW(pathEdit); pathEdit.alignment.Set(WMComponents.AlignClient); 
			panel.AddContent(pathEdit); pathEdit.fillColor.Set(0EEEEEEFFH);
			pathEdit.onEnter.Add(PathChanged); pathEdit.SetAsString("/");
			pathEdit.multiLine.Set(FALSE); pathEdit.tv.defaultTextBgColor.Set(pathEdit.fillColor.Get());
			pathEdit.tv.showBorder.Set(TRUE); pathEdit.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1));
						
			NEW(prefixSearch, FileListPrefixSearchProt, NIL, NIL); properties.Add(prefixSearch);
			NEW(filterEdit); filterEdit.alignment.Set(WMComponents.AlignTop); 
			filterEdit.bounds.SetHeight(25); AddContent(filterEdit);
			filterEdit.text.onTextChanged.Add(TextChanged);
			filterEdit.multiLine.Set(FALSE);
			filterEdit.tv.showBorder.Set(TRUE);
			NEW(grid);
			grid.alignment.Set(WMComponents.AlignClient);
			AddContent(grid);
			grid.onClickSelected.Add(ClickSelected);
			grid.SetExtContextMenuHandler(ContextMenu);
			grid.onStartDrag.Add(MyStartDrag);
			grid.SetExtDragDroppedHandler(MyDragDropped);
			grid.model.Acquire;
			grid.model.SetNofCols(4);
			grid.model.SetNofRows(1);
			grid.fixedRows.Set(1);
			grid.model.SetCellText(0, 0, Utilities.NewString("Filename"));
			grid.model.SetCellText(1, 0, Utilities.NewString("Size"));
			grid.model.SetCellText(2, 0, Utilities.NewString("Modified"));
			grid.model.SetCellText(3, 0, Utilities.NewString("Attributes"));
			grid.SetSelectionMode(WMGrids.GridSelectRows);
			NEW(colWidths, 4);				
			grid.model.Release
		END Init;
		
		PROCEDURE SetColSize;
		BEGIN
			colWidths[0] := (bounds.GetWidth() DIV 2);
			colWidths[1] := bounds.GetWidth() DIV 6;
			colWidths[2] := bounds.GetWidth() DIV 6;	
			colWidths[3] := bounds.GetWidth() DIV 6;	
			grid.SetColSpacings(colWidths);		
		END SetColSize;	
		
		(* -- Handlers -------------------------------------- *)

		PROCEDURE ClickSelected(sender, data : ANY);
		VAR curSel : AosFTPClient.FTPListing;
		BEGIN
			IF (data # NIL) & (data IS AosFTPClient.FTPEntry) THEN
				NEW(curSel, 1);
				curSel[0] := data(AosFTPClient.FTPEntry);
				owner.SetBusy(TRUE);
				IF curSel[0] = parent THEN AosOut.String("Directory UP "); owner.ChangeDir(Utilities.NewString("..")) END;
				IF IsFolder(curSel[0]) THEN	(* change into folder *)
					owner.ChangeDir(Utilities.NewString(curSel[0].filename))
				END;
				owner.SetBusy(FALSE)
			END	
		END ClickSelected;
		
		PROCEDURE ContextMenu(sender : ANY; x, y: LONGINT);
		VAR curSel : AosFTPClient.FTPListing;
			w : SelectionWrapper;
			data : ANY;
		BEGIN
			px := x; py := y;
			NEW(popup);
			curSel := GetSelection();
			NEW(w); w.sel := curSel;

			IF LEN(curSel) = 0 THEN RETURN END; 
			IF LEN(curSel) = 1 THEN
				popup.AddParButton("Create Dir", CreateDir, w);
				popup.AddParButton("Rename", RenameEntry, w)
			END;
			popup.AddParButton("Delete", DeleteEntries, w);
			
			grid.ToWMCoordinates(x, y, px, py);
			popup.Popup(px, py)		
		END ContextMenu;
			
		PROCEDURE DeleteEntries(sender, data : ANY);
		VAR  d : AosFTPClient.FTPEntry; 
			dr, res, i  : LONGINT;
			dp : ARRAY 128 OF CHAR;
			delete, always, never : BOOLEAN;
		BEGIN
			IF popup # NIL THEN popup.Close; popup := NIL END;
			IF (data # NIL) & (data IS SelectionWrapper) THEN
				always := FALSE; never := FALSE;
				FOR i := 0 TO LEN(data(SelectionWrapper).sel) - 1 DO
					d := data(SelectionWrapper).sel[i];
					delete := FALSE;
					IF d # NIL THEN
						COPY(d.filename, dp);
						IF ~always & ~never THEN
							dr := WMDialogs.Message("Confirm deleting file", dp, 
								{WMDialogs.ResNo, WMDialogs.ResAbort, WMDialogs.ResYes, WMDialogs.ResAll});
							IF dr IN {WMDialogs.ResYes, WMDialogs.ResAll} THEN delete := TRUE END;
							IF dr = WMDialogs.ResAll THEN always := TRUE END;							
							IF dr = WMDialogs.ResAbort THEN never := TRUE END;
						END;
						IF ~never & (delete OR always) THEN
							owner.SetBusy(TRUE);
							IF IsFolder(d) THEN
								owner.ftp.RemoveDir(dp, res)
							ELSE
								owner.ftp.DeleteFile(dp, res)
							END;
							IF res # 0 THEN
								res := WMDialogs.Message("Deleting failed", dp, {WMDialogs.ResOk})	
							END;
							owner.SetBusy(FALSE);
							(* if the dialog was shown then visually update *)
(*							IF delete THEN Refresh(NIL, NIL) END *)
						END
					END
				END;
				(* end of the operation refresh list *)
(*				Refresh(NIL, NIL) *)
			END
		END DeleteEntries;
		
		PROCEDURE RenameEntry(sender, data : ANY);
		VAR  d : AosFTPClient.FTPEntry; rename : WMDialogs.MiniStringInput;
			wmx, wmy, res : LONGINT;
			name, op : ARRAY 128 OF CHAR;
		BEGIN
			IF popup # NIL THEN popup.Close; popup := NIL END;
			IF (data # NIL) & (data IS SelectionWrapper) THEN
				d := data(SelectionWrapper).sel[0];
				IF d # NIL THEN
					(* grid.Acquire; grid.ToWMCoordinates(px, py, wmx, wmy); grid.Release; *)
					NEW(rename);
					COPY(d.filename, name);
					IF rename.Show(px, py, name) = WMDialogs.ResOk THEN
						IF name # d.filename THEN
							owner.SetBusy(TRUE);
							COPY(d.filename, op);
							AosOut.String("Renaming File/Folder: "); AosOut.String(op); AosOut.Ln;
							owner.ftp.RenameFile(op, name, res);
							IF res # 0 THEN
								AosOut.String("Renaming failed: "); AosOut.Int(res, 0); AosOut.Ln;
								res := WMDialogs.Message("Renaming failed", name, {WMDialogs.ResOk})	
							END;
							owner.SetBusy(FALSE);
(*							Refresh(NIL, NIL)	*)
						END
					END
				END
			END
		END RenameEntry;
		
		PROCEDURE CreateDir(sender, data : ANY);
		VAR res : LONGINT;
			name : ARRAY 128 OF CHAR;
		BEGIN
			COPY("NewFolder", name);
			IF WMDialogs.QueryString("Create Folder: ", name) = WMDialogs.ResOk THEN
				owner.SetBusy(TRUE);
				AosOut.String("Creating Folder: "); AosOut.String(name); AosOut.Ln;
				owner.ftp.MakeDir(name, res);
				IF res # 0 THEN
					AosOut.String("Creating Folder failed: "); AosOut.Int(res, 0); AosOut.Ln;
					res := WMDialogs.Message("Creating new Folder failed", name, {WMDialogs.ResOk})						
				END;
				owner.SetBusy(FALSE);
(*				Refresh(NIL, NIL)	*)				
			END
		END CreateDir;		
		
		PROCEDURE TextChanged(sender, data : ANY);
		VAR str : ARRAY 128 OF CHAR;
		BEGIN
			filterEdit.GetAsString(str);
			filter.Set(Utilities.NewString(str))
		END TextChanged;
		
		PROCEDURE PathChanged(sender, data : ANY);
		VAR str : ARRAY 512 OF CHAR;
		BEGIN
			pathEdit.GetAsString(str);
			path.Set(Utilities.NewString(str))
		END PathChanged;
		
		PROCEDURE PropertyChanged*(sender, data : ANY);
		BEGIN
			IF data = path THEN
				owner.ChangeDir(path.Get());
			ELSIF (data = filter) OR (data = prefixSearch) THEN
				PrepareList
			ELSE PropertyChanged^(sender, data)
			END
		END PropertyChanged;
		
		PROCEDURE PrepareList;
		VAR i, vis : LONGINT; mask, t : ARRAY 128 OF CHAR; s : Utilities.String;
			img: WMGraphics.Image;
		BEGIN
			IF curList = NIL THEN
				grid.model.Acquire;
				grid.model.SetNofRows(1);
				grid.model.Release;
				RETURN
			END;
			s := filter.Get();
			mask := "";
			IF s # NIL THEN COPY(s^, mask) END;
			IF mask = "" THEN
				FOR i := 0 TO nofEntries - 1 DO curList[i].visible := TRUE END;
				vis := nofEntries
			ELSE
				IF prefixSearch.Get() & ( mask[Utilities.Length(mask)] # "*") THEN Utilities.Append(mask, "*") END;
				vis := 0;
				FOR i := 0 TO nofEntries - 1 DO
					IF Utilities.Match(mask, curList[i].filename) THEN
						curList[i].visible := TRUE;
						INC(vis)
					ELSE curList[i].visible := FALSE
					END
				END;
			END;
		
			grid.model.Acquire;
			grid.model.SetNofRows(vis + 2);
			grid.model.SetCellText(0, 1, Utilities.NewString("Parent Directory")); grid.model.SetCellData(0, 1, parent);
			grid.model.SetCellImage(0, 1, WMGraphics.LoadImage("icons.tar://Parent.png", TRUE));

			vis := 0;
			FOR i := 0 TO nofEntries - 1 DO
				IF curList[i].visible THEN
					img := GetImage(curList[i]);
					grid.model.SetCellImage(0, vis+2, img);
					grid.model.SetCellText(0, vis+2, Utilities.NewString(curList[i].filename));
					grid.model.SetCellData(0, vis+2, curList[i]);
					grid.model.SetCellText(1, vis+2, Utilities.NewString(curList[i].size));
					COPY(curList[i].d0, t); Utilities.Append(t, " "); Utilities.Append(t, curList[i].d1); Utilities.Append(t, " "); Utilities.Append(t, curList[i].d2); 
					grid.model.SetCellText(2, vis+2, Utilities.NewString(t));
					grid.model.SetCellText(3, vis+2, Utilities.NewString(curList[i].flags));
					INC(vis)
				END	
			END;
			grid.SetTopPosition(0, 0, TRUE);
			grid.model.Release;
		END PrepareList;			
		
		(* -- Drag-Drop Handlers -----------------------------*)
		
		(* called when an object has been dropped on this FTPList *)
		PROCEDURE MyDragDropped(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo; VAR handled : BOOLEAN);
		BEGIN
			handled := TRUE;
			DragDroppedList(x, y, dragInfo)
		END MyDragDropped;
		
		(* called by MyDraggedDropped *)
		PROCEDURE DragDroppedList(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo);
		VAR dropTarget : AosFTPDropTarget;
		BEGIN
			NEW(dropTarget, owner.ftp);
			dragInfo.data := dropTarget;
			owner.SetBusy(TRUE);
			IF dragInfo.sender = grid THEN ConfirmDrag(FALSE, dragInfo)
			ELSE ConfirmDrag(TRUE, dragInfo) END;
			owner.SetBusy(FALSE)
		END DragDroppedList;
		
		(* called when a drag-operation has been started *)
		PROCEDURE MyStartDrag(sender, data : ANY);
		VAR img : WMGraphics.Image;
			c : WMGraphics.BufferCanvas;
			top, i : LONGINT;
		BEGIN
			selection := GetSelection();
			(* render to bitmap *)
			NEW(img);	Raster.Create(img, 100, 200, Raster.BGRA8888);
			NEW(c, img);
			c.SetColor(0FFFF00FFH);
			top := 0;
			FOR i := 0 TO LEN(selection) - 1 DO
				IF selection[i] # NIL THEN
					c.Fill(WMRectangles.MakeRect(0, top, 100, top + 25), 0FF80H, WMGraphics.ModeCopy);
					c.DrawString(3, top + 20, selection[i].filename);
					INC(top, 25)
				END
			END;
			IF grid.StartDrag(NIL, img, DragArrivedList, NIL) THEN AosOut.String("DraggingStarted")
			ELSE AosOut.String("Drag could not be started")
			END;
		END MyStartDrag;
		
		(* called when an object dragged from this FTPList has been dropped anywhere *)
		PROCEDURE DragArrivedList(sender, data : ANY);
		VAR di : WMWindowManager.DragInfo;
			dt : WMDropTarget.DropTarget;
			itf : WMDropTarget.DropInterface;
			w : AosIO.Writer;
			i, res : LONGINT;
			sel : AosFTPClient.FTPListing;
			url : ARRAY 1024 OF CHAR;
			text : AosTexts.Text;
			textPos : AosTexts.TextPosition;
		BEGIN
			sel := selection;
			IF sel = NIL THEN RETURN END;
			
			IF (data # NIL) & (data IS WMWindowManager.DragInfo) THEN
				di := data(WMWindowManager.DragInfo);
				IF (di.data # NIL) & (di.data IS WMDropTarget.DropTarget) THEN		
					dt := di.data(WMDropTarget.DropTarget)
				ELSE RETURN
				END
			ELSE RETURN
			END;
			
			(* File *)
			itf := dt.GetInterface(WMDropTarget.TypeFiles);
			IF itf # NIL THEN
				FOR i := 0 TO LEN(selection) - 1 DO 
					IF selection[i] # NIL THEN
						COPY(selection[i].filename, url);
						IF ~IsFolder(selection[i]) THEN
							CopyFile(itf(WMDropTarget.DropFiles), url, url, res)
						END
					END
				END;
				RETURN
			END;
	
			(* Text *)
			itf := dt.GetInterface(WMDropTarget.TypeText);
			IF itf # NIL THEN
				text := itf(WMDropTarget.DropText).text;
				textPos := itf(WMDropTarget.DropText).pos;
				IF (text # NIL) & (textPos # NIL) THEN
					text.AcquireWrite;
					FOR i := 0 TO LEN(selection) - 1 DO 
						IF selection[i] # NIL THEN
							COPY(selection[i].filename, url);
							Utilities.Append(url, CHR(AosTexts.NewLineChar));
							AosTextUtilities.StrToText(text, textPos.GetPosition(), url)
						END
					END;
					text.ReleaseWrite
				END;
				RETURN						
			END;
		END DragArrivedList;

		(* -- Helpers --------------------------------------- *)
		
		PROCEDURE GetSelection() : AosFTPClient.FTPListing;
		VAR selection : AosFTPClient.FTPListing;
			l, t, r, b, i, j : LONGINT;
			p : ANY;
		BEGIN
			grid.model.Acquire;
			grid.GetSelection(l, t, r, b);
			NEW(selection, b- t + 1);
			j := 0;
			FOR i := t TO b DO
				p := grid.model.GetCellData(0, i); 
				IF (p # NIL) & (p IS AosFTPClient.FTPEntry) THEN
					selection[j] := p(AosFTPClient.FTPEntry);
					INC(j)
				END
			END;
			grid.model.Release;
			RETURN selection
		END GetSelection;
		
		PROCEDURE CopyFile(target : WMDropTarget.DropFiles; local, remote : ARRAY OF CHAR; VAR res : LONGINT);
		VAR w : AosIO.Writer;
			r : AosIO.Reader;
			buf: ARRAY BufSize OF CHAR; len : LONGINT;
		BEGIN
			res := -1;
			owner.SetBusy(TRUE);			
			owner.ftp.OpenGet(local, r, res);
			IF  res = 0 THEN
				target.OpenPut(remote, w, res);
				AosOut.String("Downloading File: "); AosOut.String(local); AosOut.Ln;
				IF res = 0 THEN
					REPEAT
						r.Bytes(buf, 0, BufSize, len); w.Bytes(buf, 0, len);
					UNTIL r.res # 0;
					target.ClosePut(res)
				END;
				owner.ftp.CloseGet(res)
			ELSE
				AosOut.String("Error: "); AosOut.String(owner.ftp.msg); AosOut.Ln
			END;
			owner.SetBusy(FALSE)
		END CopyFile;		
		
		PROCEDURE IsFolder(entry : AosFTPClient.FTPEntry) : BOOLEAN;
		BEGIN
			IF (entry.flags[0] = "<") OR (entry.flags[0] = "d") THEN RETURN TRUE;
			ELSE RETURN FALSE END;
		END IsFolder;
		
		PROCEDURE GetImage(entry : AosFTPClient.FTPEntry) : WMGraphics.Image;
		VAR img : WMGraphics.Image; temp: ARRAY 256 OF CHAR;
		BEGIN
			COPY("icons.tar://", temp);
			IF IsFolder(entry) THEN		
				Utilities.Append(temp, "Folder.png");
			ELSE
				Utilities.Append(temp, "File.png");
			END;
			Utilities.Append(temp, 0X);					
			img := WMGraphics.LoadImage(temp, TRUE);
			RETURN img
		END GetImage;
		
	END FTPPanel;
(* ------------------------------------------------------------------ *)

VAR
	nofWindows : LONGINT;
	FileListPathProt : WMProperties.StringProperty;
	FileListFilterProt : WMProperties.StringProperty;
	FileListPrefixSearchProt : WMProperties.BooleanProperty;
		
PROCEDURE InitPrototypes;
BEGIN
	NEW(FileListPathProt, NIL, Utilities.NewString("Path"), Utilities.NewString("contains the displayed path"));
	NEW(FileListFilterProt, NIL, Utilities.NewString("Filter"), Utilities.NewString("display filename filter"));
	NEW(FileListPrefixSearchProt, NIL, Utilities.NewString("PrefixSearch"), Utilities.NewString("match prefix only"));
	FileListPrefixSearchProt.Set(TRUE);
END InitPrototypes;	

PROCEDURE Open*(par : ANY): ANY;
VAR instance : Window;
BEGIN
	NEW(instance);
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
	NEW(die); msg.ext := die; msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	InitPrototypes;
	AosModules.InstallTermHandler(Cleanup);
END WMFTPClient.

---------------------------------------------

WMFTPClient.Open~
