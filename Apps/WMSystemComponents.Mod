MODULE WMSystemComponents;	(** AUTHOR "TF/UG"; PURPOSE "Components for File-Listings etc"; *)
(**
 * History:
 *
 *	10.12.2006	Clear selection in FileList.Refresh, added All, Never & Abort option when copying files (staubesv)
 *)
 
IMPORT
	AosFS, Utilities, WMProperties, WMEvents, WMComponents, WMTrees, WMGrids, WMStringGrids,
(* for testing only *)
	WMRectangles, WMGraphics, Raster,
	AosOut,
	WMDropTarget, AosTexts, AosTextUtilities, AosIO, WMPopups, WMDialogs, AosConfig, AosCommands,
	AosArchives, UTF8Strings,
	WM := WMWindowManager;

CONST
	BufSize = 16*1024; (* internal buffer size, used for copy *)
	
	TraceCopy = 0;
	TraceDragging = 1;
	
	Trace = {0};
	
TYPE 
	 AosFSDropInterface = OBJECT(WMDropTarget.DropFiles)
	 VAR 
	 	path : ARRAY 128 OF CHAR;
		f : AosFS.File;
		w : AosFS.Writer;
		refresh : WMEvents.EventSource;
		overwriteOnce, overwriteAll, overwriteNever, abort : BOOLEAN;
	 	
		PROCEDURE &New(VAR str : ARRAY OF CHAR);
		BEGIN
			COPY(str, path);
			NEW(refresh, SELF, NIL, NIL, NIL);
			overwriteAll := FALSE; overwriteNever := FALSE; abort := FALSE;
		END New;
				
		PROCEDURE OpenPut*(remoteName : ARRAY OF CHAR; VAR outw : AosIO.Writer; VAR res : LONGINT);
		VAR oldFile : AosFS.File; name : ARRAY 1024 OF CHAR;
		BEGIN
			res := -1;
			IF abort THEN RETURN; END;
			COPY(path, name); Utilities.Append(name, remoteName);
			overwriteOnce := FALSE;
			oldFile := AosFS.Old(name);
			IF (oldFile # NIL) & ~overwriteAll & ~overwriteNever THEN
				res := WMDialogs.Message("Confirm overwriting", remoteName, {WMDialogs.ResNo, WMDialogs.ResYes, WMDialogs.ResAll, WMDialogs.ResAbort, WMDialogs.ResNever});
				CASE res OF
					|WMDialogs.ResYes: overwriteOnce := TRUE;
					|WMDialogs.ResNo: overwriteOnce := FALSE;
					|WMDialogs.ResAll: overwriteAll := TRUE;
					|WMDialogs.ResAbort: abort := TRUE;
					|WMDialogs.ResNever: overwriteNever := TRUE;
				ELSE	
					AosOut.String("WMSystemComponents: Implementation error, unexpected WMDialog result type."); AosOut.Ln;
				END;
			END;
					
			IF TraceCopy IN Trace THEN AosOut.String(name); AosOut.String(" ... "); END;
			IF (oldFile = NIL) OR overwriteOnce OR overwriteAll THEN
				f := AosFS.New(name);
				IF f # NIL THEN
					AosFS.OpenWriter(w, f, 0);
					outw := w;
					res := AosFS.Ok;
					IF TraceCopy IN Trace THEN
						AosOut.String(" done");
						IF (oldFile # NIL) THEN AosOut.String(" (overwritten)"); END;
						AosOut.String(".");
					END;
				ELSE
					AosOut.String("Error: Could not create file "); AosOut.String(name); AosOut.Ln;
				END;
			ELSE
				IF (TraceCopy IN Trace) & (oldFile # NIL) THEN AosOut.String("skipped."); AosOut.Ln; END;
			END;
			IF TraceCopy IN Trace THEN AosOut.Ln; END;
		END OpenPut;
		
		PROCEDURE ClosePut*(VAR res : LONGINT);
		BEGIN
			IF (f # NIL) & (w # NIL)  THEN
				w.Update;
				f.Update;
				AosFS.Register(f);
				refresh.Call(NIL)
			END	
		END ClosePut;
			
	END AosFSDropInterface;
	
	AosFSDropTarget = OBJECT(WMDropTarget.DropTarget)
	VAR path : ARRAY 128 OF CHAR;
		eh : WMEvents.EventListener;
	
		PROCEDURE &New(str : Utilities.String; e : WMEvents.EventListener);
		BEGIN
			IF str # NIL THEN COPY(str^, path) END; 
			MakePathString(path);
			eh := e
		END New;
		
		PROCEDURE GetInterface*(type : LONGINT) : WMDropTarget.DropInterface;
		VAR di : AosFSDropInterface;
		BEGIN
			IF type = WMDropTarget.TypeFiles THEN
				NEW(di, path); 
				IF eh # NIL THEN di.refresh.Add(eh) END;
				RETURN di
			ELSE RETURN NIL
			END
		END GetInterface;
	END AosFSDropTarget;
	
	CommandCaller = OBJECT
	VAR msg : ARRAY 512 OF CHAR;
		s : Utilities.String;
		res : LONGINT;
		
		PROCEDURE &Init(command : ARRAY OF CHAR);
		BEGIN
			s := Utilities.NewString(command)
		END Init;

	BEGIN {ACTIVE}
		AosCommands.Call(s^, {}, res, msg);
		IF res # 0 THEN AosOut.String(msg); AosOut.Ln END;
	END CommandCaller;	
	
TYPE
	TreeData = OBJECT
	VAR path : Utilities.String;
	END TreeData;
	
	DirectoryTree* = OBJECT(WMTrees.TreeView)
	VAR
		enumerator : AosFS.Enumerator;
		tree : WMTrees.Tree;
		currentPath* : WMProperties.StringProperty;
		onPathChanged* : WMEvents.EventSource;
		tr : WMTrees.TreeNode; 
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			(* new properties *)
			NEW(currentPath, DirTreePathProt, NIL, NIL); properties.Add(currentPath);
			(* new events *)
			NEW(onPathChanged, SELF, GSonPathChanged, GSonPathChangedInfo, SELF.StringToCompCommand); 
			events.Add(onPathChanged);
			
			tree := GetTree();
			NEW(enumerator);
			onSelectNode.Add(NodeSelected);
			onExpandNode.Add(NodeExpanded);
			tree.Acquire;
			NEW(tr);
			tree.SetRoot(tr);
			tree.SetNodeCaption(tr, WMComponents.NewString("FileSystems"));
			tree.InclNodeState(tr, WMTrees.NodeAlwaysExpanded);
			FillMountedFS(tree, tr);
			tree.Release;
		END Init;
		
		PROCEDURE Refresh*;
		BEGIN
			tree.Acquire;
			FillMountedFS(tree, tr);
			tree.Release;
		END Refresh;
	
		PROCEDURE NodeExpanded(sender, data : ANY);
		VAR p : ANY;
		BEGIN
			IF (data = NIL) OR ~(data IS WMTrees.TreeNode) THEN RETURN END;
			tree.Acquire;
			p := tree.GetNodeData(data(WMTrees.TreeNode));
			IF (p # NIL) & (p IS TreeData) THEN
				IF WMTrees.NodeSubnodesUnknown IN tree.GetNodeState(data(WMTrees.TreeNode)) THEN
					EnumerateSubDirectories(tree, data(WMTrees.TreeNode), p(TreeData).path)
				END	
			END;
			tree.Release
		END NodeExpanded;
		
		PROCEDURE NodeSelected(sender, data : ANY);
		VAR p : ANY;
		BEGIN
			IF (data = NIL) OR ~(data IS WMTrees.TreeNode) THEN RETURN END;
			tree.Acquire;
			p := tree.GetNodeData(data(WMTrees.TreeNode));
			IF (p # NIL) & (p IS TreeData) THEN 
				EnumerateSubDirectories(tree, data(WMTrees.TreeNode), p(TreeData).path); 
				currentPath.Set(p(TreeData).path);
				onPathChanged.Call(p(TreeData).path)
			END;
			tree.Release
		END NodeSelected;
		
		PROCEDURE DragDropped(x, y : LONGINT; dragInfo : WM.DragInfo);
		VAR node : WMTrees.TreeNode;
			dropTarget : AosFSDropTarget;
			p : ANY;
		BEGIN
			tree.Acquire;
			node := GetNodeAtPos(x, y);
			p := tree.GetNodeData(node);
			tree.Release;
			IF (p # NIL) & (p IS TreeData) THEN 
(*				AosOut.String("p(TreeData).path = "); AosOut.String(p(TreeData).path^); AosOut.Ln;  *)
				NEW(dropTarget, p(TreeData).path, NIL);
				dragInfo.data := dropTarget;
				ConfirmDrag(TRUE, dragInfo)
			END
		END DragDropped;
		
		PROCEDURE PropertyChanged*(sender, property : PTR);
		BEGIN
			IF (property = currentPath) THEN (*SetPath(currentPath.Get()) *)
			ELSE PropertyChanged^(sender, property)
			END;
		END PropertyChanged;
		
		PROCEDURE EnumerateSubDirectories(tree : WMTrees.Tree; node : WMTrees.TreeNode; dir : Utilities.String);
		VAR name, path, filename, mask : ARRAY 256 OF CHAR; flags : SET; time, date, size : LONGINT;
			dirNode : WMTrees.TreeNode;
			td : TreeData; has : BOOLEAN;
		BEGIN
			tree.Acquire;
			IF tree.GetChildren(node) # NIL THEN tree.Release; RETURN END; (* assuming there will be no changes in the structures *)
			WHILE tree.GetChildren(node) # NIL DO tree.RemoveNode(tree.GetChildren(node)) END;
			COPY(dir^, mask); Utilities.Append(mask, "/*");
			enumerator.Open(mask, {});
			has := FALSE;
			WHILE enumerator.HasMoreEntries() DO
				IF enumerator.GetEntry(name, flags, time, date, size) THEN
					IF AosFS.Directory IN flags THEN
						has := TRUE;
						NEW(dirNode); 
						AosFS.SplitPath(name, path, filename);
						NEW(td); td.path := WMComponents.NewString(name);
						tree.SetNodeData(dirNode, td);
						tree.SetNodeCaption(dirNode, WMComponents.NewString(filename));
						tree.InclNodeState(dirNode, WMTrees.NodeSubnodesUnknown);
						tree.AddChildNode(node, dirNode)
					END
				END
			END;
			IF has THEN tree.SetNodeState(node, {WMTrees.NodeExpanded})
			ELSE tree.SetNodeState(node, {})
			END;
			enumerator.Close;
			tree.Release
		END EnumerateSubDirectories;
		
		PROCEDURE FillMountedFS(tree : WMTrees.Tree; node : WMTrees.TreeNode);
		VAR list: AosFS.FileSystemTable;
			prefixNode : WMTrees.TreeNode;
			td : TreeData;
			i : LONGINT;
			prefix : ARRAY 32 OF CHAR;
		BEGIN
			AosFS.GetList(list);
			tree.Acquire;
			WHILE tree.GetChildren(node) # NIL DO tree.RemoveNode(tree.GetChildren(node)) END;
			FOR i := 0 TO LEN(list) - 1 DO
				NEW(prefixNode); 
				tree.SetNodeCaption(prefixNode, WMComponents.NewString(list[i].prefix));
				COPY(list[i].prefix, prefix); Utilities.Append(prefix, ":");
				NEW(td); td.path := WMComponents.NewString(prefix);
(*				IF i = 0 THEN
					currentPath.Set(td.path);
					first := prefixNode;
				END; *)
				tree.SetNodeData(prefixNode, td);
				tree.SetNodeState(prefixNode, {WMTrees.NodeSubnodesUnknown});
				tree.AddChildNode(node, prefixNode);
			END;
			tree.Release;
(*			IF first # NIL THEN SelectNode(first) END; *)
		END FillMountedFS;
		
	END DirectoryTree;

TYPE 
	DirEntry* = OBJECT
	VAR name*, path-, full* : Utilities.String;
		time, date, size*: LONGINT;
		flags : SET;
		visible : BOOLEAN;
		node* : WMTrees.TreeNode;
		
		PROCEDURE &Init(name, path : Utilities.String; time, date, size : LONGINT; flags : SET);
		BEGIN
			SELF.name := name;
			SELF.path := path;
			SELF.time := time;
			SELF.date := date;
			SELF.size := size;
			SELF.flags := flags;
			visible := FALSE;
			NEW(node)
		END Init;
		
	END DirEntry;
	
	DirEntries* = POINTER TO ARRAY OF DirEntry;		
	
	SelectionWrapper* = POINTER TO RECORD
		sel* : DirEntries;
	END;

	FileList* = OBJECT(WMComponents.VisualComponent)
	VAR grid : WMStringGrids.StringGrid;
		prefixSearch : WMProperties.BooleanProperty;
		path, filter : Utilities.String;
		fullView, fromSearchReq : BOOLEAN;
		popup: WMPopups.Popup; 
		enumerator : AosFS.Enumerator;
		dir : DirEntries;
		selection : DirEntries;
		nfiles, nofRows : LONGINT;
		px, py : LONGINT;
		colWidths : WMGrids.Spacings;
	
		PROCEDURE &Init;
		BEGIN
			Init^;

			(* new properties *) (* it is not possible to change this property at any time but we leave it for the moment *)
			NEW(prefixSearch, FileListPrefixSearchProt, NIL, NIL); properties.Add(prefixSearch);

			fullView := FALSE;
			fromSearchReq := FALSE;

			NEW(grid);
			grid.alignment.Set(WMComponents.AlignClient);
			AddContent(grid);
			grid.SetExtDragDroppedHandler(MyDragDropped);
			grid.onClickSelected.Add(ClickSelected);
			grid.SetExtContextMenuHandler(ContextMenu);
			grid.onStartDrag.Add(MyStartDrag);
			grid.model.Acquire;
			grid.model.SetNofCols(1);
			grid.model.SetNofRows(1);
			grid.fixedRows.Set(1);
			NEW(colWidths, 3); 
			grid.model.SetCellText(0, 0, Utilities.NewString("Filename"));
			grid.model.SetCellText(1, 0, Utilities.NewString("Size"));
			grid.model.SetCellText(2, 0, Utilities.NewString("Modified"));
			grid.SetSelectionMode(WMGrids.GridSelectRows);
			grid.model.Release;
			NEW(enumerator);

			SELF.path := Utilities.NewString("");
			SELF.filter := Utilities.NewString("");
		END Init;
		
		PROCEDURE SetSearchReqFlag*;
		BEGIN
			fromSearchReq := TRUE
		END SetSearchReqFlag;
		
		PROCEDURE GetSelection*() : DirEntries;
		VAR selection : DirEntries;
			l, t, r, b, i, j : LONGINT;
			p : ANY;
		BEGIN
			grid.model.Acquire;
			grid.GetSelection(l, t, r, b);
			NEW(selection, b- t + 1);
			j := 0;
			FOR i := t TO b DO
				p := grid.model.GetCellData(0, i); 
				IF (p # NIL) & (p IS DirEntry) THEN
					selection[j] := p(DirEntry);
					INC(j)
				END
			END;
			grid.model.Release;
			RETURN selection
		END GetSelection;
		
		PROCEDURE ClickSelected(sender, data : ANY);
		VAR curSel : DirEntries;
			w : SelectionWrapper;
			p : ARRAY 128 OF CHAR;
		BEGIN
			IF (data # NIL) & (data IS DirEntry) THEN
				NEW(curSel, 1);
				curSel[0] := data(DirEntry);
				IF AosFS.Directory IN curSel[0].flags THEN
					COPY(curSel[0].path^, p); Utilities.Append(p, curSel[0].name^);
					MakePathString(p);
					StartNewPath(Utilities.NewString(p));
				ELSE
					NEW(w); w.sel := curSel;
					Open(sender, w)
				END
			END	
		END ClickSelected;
		
		PROCEDURE ContextMenu(sender : ANY; x, y: LONGINT);
		VAR wmx, wmy : LONGINT;
			curSel : DirEntries;
			w : SelectionWrapper;
		BEGIN
			px := x; py := y;
			NEW(popup);
			curSel := GetSelection();
			NEW(w); w.sel := curSel;
			IF ~fromSearchReq THEN
				(* allow operations on files such as renaming, duplicating, deleting, etc. only in not content-based search lists *)
				IF LEN(curSel) = 1 THEN
					popup.AddParButton("Open", Open, w);
					popup.AddParButton("Rename", Rename, w);
					popup.AddParButton("Duplicate", Duplicate, w);
					popup.AddParButton("Untar", Untar, w);
				END;
				popup.AddParButton("Tar", Tar, w);
				popup.AddParButton("Delete", Delete, w);
			ELSE
				IF LEN(curSel) = 1 THEN
					(* only allow opening of files in this case *)
					popup.AddParButton("Open", Open, w);
				END					
			END;				
			grid.Acquire; grid.ToWMCoordinates(x, y, wmx, wmy); grid.Release;
			popup.Popup(wmx, wmy)
		END ContextMenu;
		
		PROCEDURE Rename(sender, data : ANY);
		VAR  d : DirEntry; rename : WMDialogs.MiniStringInput;
			wmx, wmy, res : LONGINT;
			name, op, np : ARRAY 128 OF CHAR;
		BEGIN
			IF popup # NIL THEN popup.Close; popup := NIL END;
			IF (data # NIL) & (data IS SelectionWrapper) THEN
				d := data(SelectionWrapper).sel[0];
				IF d # NIL THEN
					grid.Acquire; grid.ToWMCoordinates(px, py, wmx, wmy); grid.Release;
					NEW(rename);
					COPY(d.name^, name);
					IF rename.Show(wmx, wmy, name) = WMDialogs.ResOk THEN
						IF name # d.name^ THEN
							COPY(d.path^, op); Utilities.Append(op, d.name^);
							COPY(d.path^, np); Utilities.Append(np, name);
							IF ~FileExists(np) OR
								(WMDialogs.Message("Confirm overwriting existing file", np, {WMDialogs.ResNo, WMDialogs.ResYes}) = WMDialogs.ResYes) THEN
								AosFS.Rename(op, np, res);
								IF res # 0 THEN
									AosOut.Int(res, 0); AosOut.Ln;
									res := WMDialogs.Message("Renaming failed", np, {WMDialogs.ResOk})	
								END;
								Refresh(NIL, NIL)
							END
						END
					END
				END
			END
		END Rename;

		PROCEDURE Delete(sender, data : ANY);
		VAR  d : DirEntry; 
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
						COPY(d.path^, dp); Utilities.Append(dp, d.name^);
						IF ~always & ~never THEN
							dr := WMDialogs.Message("Confirm deleting file", dp, 
								{WMDialogs.ResNo, WMDialogs.ResAbort, WMDialogs.ResYes, WMDialogs.ResAll});
							IF dr IN {WMDialogs.ResYes, WMDialogs.ResAll} THEN delete := TRUE END;
							IF dr = WMDialogs.ResAll THEN always := TRUE END;							
							IF dr = WMDialogs.ResAbort THEN never := TRUE END;
						END;
						IF ~never & (delete OR always) THEN
							AosFS.Delete(dp, res);
							IF res # 0 THEN
								res := WMDialogs.Message("Deleting failed", dp, {WMDialogs.ResOk})	
							END;
							(* if the dialog was shown then visually update *)
							IF delete THEN Refresh(NIL, NIL) END
						END
					END
				END;
				(* end of the operation refresh list *)
				Refresh(NIL, NIL)
			END
		END Delete;
		
		PROCEDURE Duplicate(sender, data : ANY);
		VAR  d : DirEntry; 
			name : ARRAY 128 OF CHAR;
			res : LONGINT;
		BEGIN
			IF popup # NIL THEN popup.Close; popup := NIL END;
			IF (data # NIL) & (data IS SelectionWrapper) THEN
				d := data(SelectionWrapper).sel[0];
				IF d # NIL THEN
					COPY(d.path^, name);
					Utilities.Append(name, d.name^);
					AosFS.Copy(name, res);
					IF res = 0 THEN
						Utilities.Append(name, ".COPY");
						AosFS.Paste(name, res);
						WHILE res # 0 DO
							IF res = 2908 THEN
								IF WMDialogs.QueryString("File already exists. Enter a new Name", name) = WMDialogs.ResOk THEN
									AosFS.Paste(name, res);
								ELSE
									res := 0;
								END;							
							ELSIF res = 2909 THEN
								IF WMDialogs.QueryString("FileName too long. Enter a new Name", name) = WMDialogs.ResOk THEN
									AosFS.Paste(name, res);
								ELSE
									res := 0;
								END;								
							ELSE							
								res := WMDialogs.Message("Error", "Some Error occoured while duplicating", {WMDialogs.ResOk});
							END;
						END;
					END;
				END;
				Refresh(NIL, NIL);
			END;		
		END Duplicate;

(*
		PROCEDURE Unzip(sender, data : ANY);
		VAR d : DirEntry; 
		BEGIN
			IF popup # NIL THEN popup.Close; popup := NIL END;
			IF (data # NIL) & (data IS SelectionWrapper) THEN
				d := data(SelectionWrapper).sel[0];
				IF d # NIL THEN
						
				END
			END						
		END Unzip;
*)	
		PROCEDURE Untar(sender, data : ANY);
		VAR d : DirEntry; 
			name : ARRAY 128 OF CHAR;
			caller : CommandCaller;
		BEGIN
			IF popup # NIL THEN popup.Close; popup := NIL END;
			IF (data # NIL) & (data IS SelectionWrapper) THEN
				d := data(SelectionWrapper).sel[0];
				IF d # NIL THEN
					COPY("AosTar.Extract ", name);
					Utilities.Append(name, d.path^);
					Utilities.Append(name, d.name^);
					NEW(caller, name);
				END;
				(* end of the operation refresh list *)
				Refresh(NIL, NIL)
			END
		END Untar;
		
		PROCEDURE Tar(sender, data : ANY);
		VAR  d : DirEntry; i, len : LONGINT;
			filename, format, temp : ARRAY 128 OF CHAR;
			buf: ARRAY BufSize OF CHAR;
			arc : AosArchives.Archive;
			file : AosFS.File; reader : AosFS.Reader;
			writer : AosIO.Writer;
		
			PROCEDURE GetFormatFromFilename(filename : ARRAY OF CHAR; VAR format : ARRAY OF CHAR);
			VAR file : ARRAY 128 OF CHAR;
			BEGIN
				IF filename = "" THEN COPY("tar", format);
				ELSE
					Utilities.GetExtension(filename, file, format);
					Utilities.LowerCase(format);
				 END	
			END GetFormatFromFilename;
		
		BEGIN
			IF popup # NIL THEN popup.Close; popup := NIL END;
			IF (data # NIL) & (data IS SelectionWrapper) THEN
				IF (WMDialogs.QueryString("Enter Name of Archive: ", filename) = WMDialogs.ResOk) THEN

					GetFormatFromFilename(filename, format);
					arc := AosArchives.Old(filename, format);
					IF arc = NIL THEN
						arc := AosArchives.New(filename, format)
					END;
									
					AosOut.String("File Manager: building "); AosOut.String(filename);
					FOR i := 0 TO LEN(data(SelectionWrapper).sel) - 1 DO
						d := data(SelectionWrapper).sel[i];
						COPY(d.path^, temp); Utilities.Append(temp, d.name^);
						file := AosFS.Old(temp);
						IF file # NIL THEN
							AosFS.OpenReader(reader, file, 0);
							arc.Acquire;
							AosIO.OpenWriter(writer, arc.OpenSender(d.name^));

							REPEAT
								reader.Bytes(buf, 0, LEN(buf), len); writer.Bytes(buf, 0, len);
							UNTIL reader.res # 0;							
							IF writer # NIL THEN writer.Update END;																				
							arc.Release;
						END;
					END;
					AosOut.String(" - done!"); AosOut.Ln;
					(* end of the operation refresh list *)
					Refresh(NIL, NIL)
				END
			END			
		END Tar;			
			
		PROCEDURE Open(sender, data : ANY);
		VAR  d : DirEntry; 
			name : ARRAY 128 OF CHAR;
		BEGIN
			IF popup # NIL THEN popup.Close; popup := NIL END;
			IF (data # NIL) & (data IS SelectionWrapper) THEN
				d := data(SelectionWrapper).sel[0];
				IF d # NIL THEN
					COPY(d.path^, name);
					Utilities.Append(name, d.name^);
					OpenFile(name)
				END
			END
		END Open;
		
		PROCEDURE MyDragDropped(x, y : LONGINT; dragInfo : WM.DragInfo; VAR handled : BOOLEAN);
		BEGIN
			handled := TRUE;
			DragDropped(x, y, dragInfo)
		END MyDragDropped;
		
		PROCEDURE DragDropped(x, y : LONGINT; dragInfo : WM.DragInfo);
		VAR dropTarget : AosFSDropTarget;
		BEGIN
			NEW(dropTarget, path, Refresh);
			dragInfo.data := dropTarget;
			ConfirmDrag(TRUE, dragInfo)
		END DragDropped;
		
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
					c.DrawString(3, top + 20, selection[i].name^);
					INC(top, 25)
				END
			END;
			IF grid.StartDrag(NIL, img, DragArrived, NIL) THEN 
				IF TraceDragging IN Trace THEN AosOut.String("WMSystemComponents: DraggingStarted"); END;
			ELSE 
				IF TraceDragging IN Trace THEN AosOut.String("WMSystemComponents: Drag could not be started"); END;
			END;
		END MyStartDrag;
		
		PROCEDURE CopyFile(target : WMDropTarget.DropFiles; local, remote : ARRAY OF CHAR; VAR res : LONGINT);
		VAR w : AosIO.Writer;
			f : AosFS.File;
			r : AosFS.Reader;
			buf: ARRAY BufSize OF CHAR; len: LONGINT;
		BEGIN
			res := -1;
			f := AosFS.Old(local);
			IF f # NIL THEN
				AosFS.OpenReader(r, f, 0);
				target.OpenPut(remote, w, res);
				IF res = 0 THEN
					REPEAT
						r.Bytes(buf, 0, BufSize, len); w.Bytes(buf, 0, len);
					UNTIL r.res # 0;
					target.ClosePut(res)
				END;
			END	
		END CopyFile;
		
		PROCEDURE Refresh(sender, data : ANY);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Refresh, sender, data)
			ELSE 
				ScanPath; PrepareList;
				grid.Acquire;
				grid.SetSelection(-1, -1, -1, -1);
				selection := NIL;
				grid.Release;
			END
		END Refresh;
		
		PROCEDURE Resized;
		BEGIN
			grid.model.Acquire;
			IF fullView THEN
				colWidths[0] := (bounds.GetWidth() DIV 3)*2 - 20;
				colWidths[1] := bounds.GetWidth() DIV 6;
				colWidths[2] := bounds.GetWidth() DIV 6;	
			ELSE
				colWidths[0] := bounds.GetWidth();
			END;
			grid.SetColSpacings(colWidths);
			grid.model.Release;	
			Resized^;
		END Resized;
		
		PROCEDURE DragArrived(sender, data : ANY);
		VAR di : WM.DragInfo;
			dt : WMDropTarget.DropTarget;
			itf : WMDropTarget.DropInterface;
			i, res : LONGINT;
			sel : DirEntries;
			url : ARRAY 1024 OF CHAR;
			text : AosTexts.Text;
			textPos : AosTexts.TextPosition;
		BEGIN
			sel := selection;
			IF sel = NIL THEN RETURN END;
			
			IF (data # NIL) & (data IS WM.DragInfo) THEN
				di := data(WM.DragInfo);
				IF (di.data # NIL) & (di.data IS WMDropTarget.DropTarget) THEN		
					dt := di.data(WMDropTarget.DropTarget)
				ELSE RETURN
				END
			ELSE RETURN
			END;
			
			itf := dt.GetInterface(WMDropTarget.TypeFiles);
			IF itf # NIL THEN
				FOR i := 0 TO LEN(selection) - 1 DO 
					IF selection[i] # NIL THEN
						COPY(selection[i].path^, url);
						Utilities.Append(url, selection[i].name^);
						CopyFile(itf(WMDropTarget.DropFiles), url, selection[i].name^, res);
					END
				END;
				RETURN
			END;
			
			itf := dt.GetInterface(WMDropTarget.TypeURL);
			IF itf # NIL THEN
				FOR i := 0 TO LEN(selection) - 1 DO 
					IF selection[i] # NIL THEN
						COPY(selection[i].path^, url);
						Utilities.Append(url, selection[i].name^);
						itf(WMDropTarget.DropURLs).URL(url, res)
					END
				END;
				RETURN						
			END;

			itf := dt.GetInterface(WMDropTarget.TypeText);
			IF itf # NIL THEN
				text := itf(WMDropTarget.DropText).text;
				textPos := itf(WMDropTarget.DropText).pos;
				IF (text # NIL) & (textPos # NIL) THEN
					text.AcquireWrite;
					FOR i := 0 TO LEN(selection) - 1 DO 
						IF selection[i] # NIL THEN
							COPY(selection[i].path^, url);
							Utilities.Append(url, selection[i].name^);
							Utilities.Append(url, CHR(AosTexts.NewLineChar));
							AosTextUtilities.StrToText(text, textPos.GetPosition(), url)
						END
					END;
					text.ReleaseWrite
				END;
				RETURN						
			END;
		END DragArrived;

		PROCEDURE ResetGrid*;
		BEGIN
			nofRows := 1;
			grid.model.Acquire;
			grid.model.SetNofRows(nofRows);
			grid.SetTopPosition(0, 0, TRUE);
			grid.SetSelection(0, 0, 0, 0);
			grid.model.Release
		END ResetGrid;
		
		PROCEDURE DisplayGrid*(VAR data : ARRAY OF DirEntry; noEl : LONGINT);
		VAR i, gridindex : LONGINT;
			d : DirEntry;
			t : ARRAY 128 OF CHAR; 
		BEGIN
			grid.model.Acquire;
			grid.model.SetNofRows(nofRows + noEl);
			FOR i := 0 TO noEl -1 DO
				d := data[i];
				gridindex := nofRows + i;
				grid.model.SetCellText(0, gridindex , d.name);
				grid.model.SetCellData(0, gridindex, d);
				IF fullView THEN
					Utilities.IntToStr(d.size, t);
					grid.model.SetCellText(1, gridindex, Utilities.NewString(t));
					Utilities.FormatDateTime(" yyyy mmm dd hh:nn ", Utilities.OberonToDateTime(d.date, d.time), t);
					grid.model.SetCellText(2, gridindex, Utilities.NewString(t));
				END;					
				IF AosFS.Directory IN d.flags THEN
					grid.model.SetCellImage(0, gridindex, WMGraphics.LoadImage("Folder.png", TRUE))
				ELSE
					grid.model.SetCellImage(0, gridindex, NIL)
				END
			END;
			grid.model.Release;
			nofRows := nofRows + noEl;
		END DisplayGrid;
		
		PROCEDURE ToggleProps*;
		BEGIN
			grid.model.Acquire;
			IF fullView THEN
				fullView := FALSE;
				grid.model.SetNofCols(1);
				colWidths[0] := bounds.GetWidth();
			ELSE
				fullView := TRUE;
				grid.model.SetNofCols(3);
				colWidths[0] := (bounds.GetWidth() DIV 3)*2 - 20;
				colWidths[1] := bounds.GetWidth() DIV 6;
				colWidths[2] := bounds.GetWidth() DIV 6;
				grid.model.SetCellText(1, 0, Utilities.NewString("Size"));
				grid.model.SetCellText(2, 0, Utilities.NewString("Modified"));
			END;
			grid.SetColSpacings(colWidths);
			grid.model.Release;
			Refresh(NIL, NIL);
		END ToggleProps;		

		PROCEDURE FillGridRow(rowNo : LONGINT; dir : DirEntry);
		VAR t : ARRAY 128 OF CHAR;
		BEGIN
			grid.model.SetCellText(0, rowNo, dir.name);
			grid.model.SetCellData(0, rowNo, dir);
			IF fullView THEN
				Utilities.IntToStr(dir.size, t);
				grid.model.SetCellText(1, rowNo, Utilities.NewString(t));
				Utilities.FormatDateTime(" yyyy mmm dd hh:nn ", Utilities.OberonToDateTime(dir.date, dir.time), t);
				grid.model.SetCellText(2, rowNo, Utilities.NewString(t));
			END;					
			IF AosFS.Directory IN dir.flags THEN
				grid.model.SetCellImage(0, rowNo, WMGraphics.LoadImage("Folder.png", TRUE))
			ELSE
				grid.model.SetCellImage(0, rowNo, NIL)
			END;			
		END FillGridRow;		

		PROCEDURE PrepareList;
		VAR i, vis : LONGINT; mask : ARRAY 128 OF CHAR; s : Utilities.String;
		BEGIN
			IF dir = NIL THEN RETURN END;
			s := SELF.filter;
			mask := "";
			IF s # NIL THEN COPY(s^, mask) END;
			IF mask = "" THEN
				FOR i := 0 TO LEN(dir) - 1 DO dir[i].visible := TRUE END;
				vis := LEN(dir)
			ELSE
				IF prefixSearch.Get() & ( mask[Utilities.Length(mask)] # "*") THEN Utilities.Append(mask, "*") END;
				vis := 0;
				FOR i := 0 TO LEN(dir) - 1 DO
					IF Utilities.Match(mask, dir[i].name^) THEN
						dir[i].visible := TRUE;
						INC(vis)
					ELSE dir[i].visible := FALSE
					END
				END;
			END;
		
			grid.model.Acquire;
			grid.model.SetNofRows(vis + 1);

			vis := 0;
			FOR i := 0 TO LEN(dir) - 1 DO
				IF dir[i].visible THEN
					FillGridRow(vis + 1, dir[i]);
					INC(vis)
				END	
			END;
			grid.SetTopPosition(0, 0, TRUE);
			grid.model.Release;
		END PrepareList;

		
		PROCEDURE ScanPath;
		VAR s, pathS : Utilities.String;
			i, l : LONGINT;
			name, path, filename, mask : ARRAY 256 OF CHAR; flags : SET; time, date, size : LONGINT;
			sorted : BOOLEAN;
		BEGIN
			s := SELF.path;
			IF s = NIL THEN RETURN END;
			COPY(s^, mask);
			IF Utilities.Length(mask) > 1 THEN
				IF mask[Utilities.Length(mask) - 1] = ':' THEN Utilities.Append(mask, '*')
				ELSE Utilities.Append(mask, '/*')
				END
			ELSE mask := '*'
			END;
			
			IF fullView THEN enumerator.Open(mask, {AosFS.EnumSize, AosFS.EnumTime}); ELSE enumerator.Open(mask, {}); END;
			nfiles := enumerator.size;
			i := 0;
			sorted := TRUE;
			NEW(dir, enumerator.size);
			WHILE enumerator.HasMoreEntries() DO
				IF enumerator.GetEntry(name, flags, time, date, size) THEN
					AosFS.SplitPath(name, path, filename);
					l := Utilities.Length(path);
					path[l] := name[l]; path[l + 1] := 0X;
					IF (pathS = NIL) OR (pathS^ # path) THEN pathS := Utilities.NewString(path) END;
					NEW(dir[i], Utilities.NewString(filename), pathS, time, date, size, flags);
					IF i > 0 THEN
						sorted := sorted & (UTF8Strings.Compare(dir[i-1].name^, dir[i].name^) = UTF8Strings.CmpLess)
					END
				END;
				INC(i)
			END;
			enumerator.Close;
			IF ~sorted THEN
				SortDir
			END
		END ScanPath;
		
		PROCEDURE StartNewPath*(path : Utilities.String);
		BEGIN
			SELF.path := path;
			ScanPath;
			PrepareList
		END StartNewPath;
		
		PROCEDURE StartNewFilter*(filter : Utilities.String);
		BEGIN
			SELF.filter := filter;
			PrepareList
		END StartNewFilter;

		PROCEDURE GetNofFiles*() : LONGINT;
		BEGIN
			RETURN nfiles
		END GetNofFiles;
		
		(* binary insertion algorithm from "Algorithms and Data Structures" by N. Wirth *)
		PROCEDURE SortDir;
		VAR i, j, m, L, R : LONGINT;
			x : DirEntry;		
		BEGIN
			FOR i := 1 TO LEN(dir) - 1 DO
				x := dir[i]; L := 0; R := i;
				WHILE L < R DO
					m := (L + R) DIV 2;
					IF UTF8Strings.Compare(dir[m].name^, x.name^) = UTF8Strings.CmpGreater THEN 
						R := m
					ELSE
						L := m + 1
					END
				END;
				FOR j := i TO R + 1 BY -1 DO dir[j] := dir[j - 1] END;
				dir[R] := x
			END
		END SortDir;

	END FileList;	
	
VAR
	DirTreePathProt : WMProperties.StringProperty;
	FileListPrefixSearchProt : WMProperties.BooleanProperty;
	GSonPathChanged, GSonPathChangedInfo : Utilities.String;

PROCEDURE InitPrototypes;
BEGIN
	NEW(DirTreePathProt, NIL, Utilities.NewString("CurrentPath"), Utilities.NewString("contains the selected path"));
	GSonPathChanged := Utilities.NewString("onPathChanged");
	GSonPathChangedInfo := Utilities.NewString("called when the path is changed");

	NEW(FileListPrefixSearchProt, NIL, Utilities.NewString("PrefixSearch"), Utilities.NewString("match prefix only"));
	FileListPrefixSearchProt.Set(TRUE);
END InitPrototypes;

(*
PROCEDURE CopyDirEntry(from, to : DirEntry);
BEGIN
	to.name := from.name;
	to.path := from.path;
	to.time := from.time;
	to.date := from.date;
	to.size := from.size;
	to.flags := from.flags;
	to.visible := from.visible
END CopyDirEntry;
*)

(** Opens the file path; corresponding file handlers are specified in AosConfig.XML *)
PROCEDURE OpenFile* (path : ARRAY OF CHAR);
VAR config, filehandler, name, ext : ARRAY 128 OF CHAR;
	res : LONGINT;
BEGIN
	AosFS.SplitExtension(path, name, ext);
	Utilities.LowerCase(ext);
	config := "Filehandlers.";
	(* get the right handler *)
	Utilities.Append(config, ext);
	AosConfig.Get(config, filehandler);
	
	IF filehandler = "" THEN RETURN END;
	
	(* construct the command *)
	Utilities.Append(filehandler, ' "');
	Utilities.Append(filehandler, path);
	Utilities.Append(filehandler, '"');
	
	(* call the command *)
	AosCommands.Call(filehandler, {}, res, name);
END OpenFile;

PROCEDURE FileExists*(name : ARRAY OF CHAR) : BOOLEAN;
BEGIN
	RETURN AosFS.Old(name) # NIL
END FileExists;

PROCEDURE MakePathString*(VAR s : ARRAY OF CHAR);
VAR l : LONGINT;
BEGIN
	l := Utilities.Length(s);
	IF (l > 1) & (s[l - 1] # ":") & (s[l - 1] # "/") THEN Utilities.Append(s, "/") END;
END MakePathString;

BEGIN
	InitPrototypes;
END WMSystemComponents.

S.Free WMSystemComponents ~

