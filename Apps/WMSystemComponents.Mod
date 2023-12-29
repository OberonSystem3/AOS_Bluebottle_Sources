MODULE WMSystemComponents;	(** AUTHOR "TF"; PURPOSE "Components for File-Listings etc"; *)

IMPORT
	AosFS, Utilities, WMProperties, WMEvents, WMComponents, WMTrees, WMGrids, WMStringGrids, WMEditors,
(* for testing only *)
	WMRectangles, WMGraphics, Raster, WMMessages, WMStandardComponents, WMWindowManager, AosModules, AosOut, WMBitmapFont,
	WMDropTarget, AosTexts, AosTextUtilities, AosIO, WMPopups, WMDialogs, AosConfig, AosCommands;

CONST
	BufSize = 16*1024; (* internal buffer size, used for copy *)
	
TYPE 
	 AosFSDropInterface = OBJECT(WMDropTarget.DropFiles)
	 VAR path : ARRAY 128 OF CHAR;
	 	hierarchical : BOOLEAN;
		f : AosFS.File;
		w : AosFS.Writer;
		refresh : WMEvents.EventSource;
	 	
		PROCEDURE &New(VAR str : ARRAY OF CHAR);
		BEGIN
			COPY(str, path);
			NEW(refresh, SELF, NIL, NIL, NIL);
		END New;
		
		PROCEDURE OpenPut*(remoteName : ARRAY OF CHAR; VAR outw : AosIO.Writer; VAR res : LONGINT);
		VAR name : ARRAY 1024 OF CHAR;
		BEGIN
			res := -1;
			COPY(path, name); Utilities.Append(name, remoteName);
			IF (AosFS.Old(name) = NIL) OR
				(WMDialogs.Message("Confirm overwriting", remoteName, {WMDialogs.ResNo, WMDialogs.ResYes}) = WMDialogs.ResYes) THEN
				AosOut.String(name); AosOut.Ln; 
				f := AosFS.New(name);
				IF f # NIL THEN
					AosFS.OpenWriter(w, f, 0);
					outw := w;
					res := 0
				END 
			END;	
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
	
TYPE
	String = Utilities.String;
	TreeData = OBJECT
	VAR path : String;
	END TreeData;
	DirectoryTree* = OBJECT(WMTrees.TreeView)
	VAR
		enumerator : AosFS.Enumerator;
		tree : WMTrees.Tree;
		currentPath* : WMProperties.StringProperty;
		onPathChanged* : WMEvents.EventSource;
		tr, tn : WMTrees.TreeNode; 
		
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
		
	
		PROCEDURE NodeExpanded(sender, data : ANY);
		VAR td : TreeData; p : ANY;
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
		VAR s : String; td : TreeData; p : ANY;
		BEGIN
			IF (data = NIL) OR ~(data IS WMTrees.TreeNode) THEN RETURN END;
			tree.Acquire;
			p := tree.GetNodeData(data(WMTrees.TreeNode));
			IF (p # NIL) & (p IS TreeData) THEN 
(*				EnumerateSubDirectories(tree, data(WMTrees.TreeNode), p(TreeData).path); *)
				currentPath.Set(p(TreeData).path);
				onPathChanged.Call(p(TreeData).path)
			END;
			tree.Release
		END NodeSelected;
		
		PROCEDURE DragDropped(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo);
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
		
		PROCEDURE EnumerateSubDirectories(tree : WMTrees.Tree; node : WMTrees.TreeNode; dir : String);
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
			prefixNode, first : WMTrees.TreeNode;
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
	DirEntry = OBJECT
	VAR name, path : String;
		flags : SET;
		visible : BOOLEAN;
	END DirEntry;
	DirEntries = POINTER TO ARRAY OF DirEntry;		
	SelectionWrapper = POINTER TO RECORD
		sel : DirEntries;
	END ;
	
	
	FileList = OBJECT(WMComponents.VisualComponent)
	VAR grid : WMStringGrids.StringGrid;
		path : WMProperties.StringProperty;
		filter : WMProperties.StringProperty;
		prefixSearch : WMProperties.BooleanProperty;
		filterEdit : WMEditors.Editor;
		popup: WMPopups.Popup; 
		enumerator : AosFS.Enumerator;
		dir : DirEntries;
		selection : DirEntries;
		px, py : LONGINT;
	
		PROCEDURE &Init;
		BEGIN
			Init^;
			(* new properties *)
			NEW(path, FileListPathProt, NIL, NIL); properties.Add(path);
			NEW(filter, FileListFilterProt, NIL, NIL); properties.Add(filter);
			NEW(prefixSearch, FileListPrefixSearchProt, NIL, NIL); properties.Add(prefixSearch);

			NEW(filterEdit); filterEdit.alignment.Set(WMComponents.AlignTop); 
			filterEdit.bounds.SetHeight(25); AddContent(filterEdit);
			filterEdit.text.onTextChanged.Add(TextChanged);
			filterEdit.multiLine.Set(FALSE);
			filterEdit.tv.showBorder.Set(TRUE);
		(*	filterEdit.tv.borders.Set(WMRectangles.MakeRect(3,3,1,1)); *)
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
			grid.model.SetCellText(0, 0, Utilities.NewString("Filename"));
			grid.SetSelectionMode(WMGrids.GridSelectRows);
			grid.model.Release;
			NEW(enumerator)
		END Init;
		
		PROCEDURE GetSelection() : DirEntries;
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
					path.SetAOC(p)
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
			IF LEN(curSel) = 1 THEN
				popup.AddParButton("Open", Open, w);
				popup.AddParButton("Rename", Rename, w);
			ELSE
			
			END;
			popup.AddParButton("Delete", Delete, w);
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
		
		PROCEDURE MyDragDropped(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo; VAR handled : BOOLEAN);
		BEGIN
			handled := TRUE;
			DragDropped(x, y, dragInfo)
		END MyDragDropped;
		
		PROCEDURE DragDropped(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo);
		VAR dropTarget : AosFSDropTarget;
		BEGIN
			NEW(dropTarget, path.Get(), Refresh);
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
			IF grid.StartDrag(NIL, img, DragArrived, NIL) THEN AosOut.String("DraggingStarted")
			ELSE AosOut.String("Drag could not be started")
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
			ELSE ScanPath; PrepareList
			END
		END Refresh;
		
		PROCEDURE DragArrived(sender, data : ANY);
		VAR di : WMWindowManager.DragInfo;
			dt : WMDropTarget.DropTarget;
			itf : WMDropTarget.DropInterface;
			w : AosIO.Writer;
			i, res : LONGINT;
			sel : DirEntries;
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

		PROCEDURE PropertyChanged*(sender, data : ANY);
		BEGIN
			IF data = path THEN
				ScanPath;
				PrepareList
			ELSIF (data = filter) OR (data = prefixSearch) THEN
				PrepareList
			ELSE PropertyChanged^(sender, data)
			END
		END PropertyChanged;
		
		PROCEDURE TextChanged(sender, data : ANY);
		VAR str : ARRAY 128 OF CHAR;
		BEGIN
			filterEdit.GetAsString(str);
			filter.Set(Utilities.NewString(str))
		END TextChanged;
		
		PROCEDURE PrepareList;
		VAR i, vis : LONGINT; mask : ARRAY 128 OF CHAR; s : String;
		BEGIN
			IF dir = NIL THEN RETURN END;
			s := filter.Get();
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
					grid.model.SetCellText(0, vis + 1, dir[i].name);
					grid.model.SetCellData(0, vis + 1, dir[i]);
					IF AosFS.Directory IN dir[i].flags THEN
						grid.model.SetCellImage(0, i + 1, WMGraphics.LoadImage("Folder.png", TRUE))
					ELSE
						grid.model.SetCellImage(0, i + 1, NIL)
					END;
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
		BEGIN
			s := SELF.path.Get();
			IF s = NIL THEN RETURN END;
			COPY(s^, mask);
			IF Utilities.Length(mask) > 1 THEN
				IF mask[Utilities.Length(mask) - 1] = ':' THEN Utilities.Append(mask, '*')
				ELSE Utilities.Append(mask, '/*')
				END
			ELSE mask := '*'
			END;
			AosOut.String("mask = "); AosOut.String(mask); AosOut.Ln; 
			enumerator.Open(mask, {});
			i := 0;
			AosOut.String("enumerator.size = "); AosOut.Int(enumerator.size, 0); AosOut.Ln; 
			NEW(dir, enumerator.size);
			WHILE enumerator.HasMoreEntries() DO
				IF enumerator.GetEntry(name, flags, time, date, size) THEN
					NEW(dir[i]);
					AosFS.SplitPath(name, path, filename);
					l := Utilities.Length(path);
					path[l] := name[l]; path[l + 1] := 0X;
					dir[i].name := Utilities.NewString(filename);
					IF (pathS = NIL) OR (pathS^ # path) THEN pathS := Utilities.NewString(path) END;
					dir[i].path := pathS;
					dir[i].flags := flags;
				END;
				INC(i)
			END;
			enumerator.Close
		END ScanPath;
		
		
	END FileList;

(***************************************************************************************)
(***************************************************************************************)
TYPE
	KillerMsg = OBJECT
	END KillerMsg; 
	
	Window* = OBJECT (WMComponents.FormWindow)
	VAR label: WMStandardComponents.Label;	
		tree : DirectoryTree;
		list : FileList;

		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			toolbar: WMStandardComponents.Panel;
			button : WMStandardComponents.Button;

		BEGIN
			NEW(panel); panel.bounds.SetExtents(800, 700); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
(*			NEW(toolbar); toolbar.fillColor.Set(000FF00FFH); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(button); button.alignment.Set(WMComponents.AlignLeft); button.caption.SetAOC("Test"); 
			toolbar.AddContent(button); *)
	
			NEW(tree);
			tree.alignment.Set(WMComponents.AlignLeft); tree.bounds.SetWidth(200);
			panel.AddContent(tree);

			NEW(list);
			list.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(list);			
			
			RETURN panel
		END CreateForm;

		PROCEDURE &New();
		VAR vc : WMComponents.VisualComponent; s : Utilities.String;
		BEGIN
			IncCount;
			vc := CreateForm();
			
			tree.onPathChanged.Add(PathChanged);
			
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			WMWindowManager.DefaultAddWindow(SELF);
			SetTitle(Utilities.NewString("Test Window"));
			s := tree.currentPath.Get();
		END New; 
		
		PROCEDURE PathChanged(sender, data : ANY);
		BEGIN
			list.path.Set(tree.currentPath.Get());
		END PathChanged;
		
		PROCEDURE Close;
		BEGIN
			DecCount;
			Close^;
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
			ELSE Handle^(x)
			END
		END Handle;		
		
		
	END Window;
(***************************************************************************************)


VAR
	DirTreePathProt : WMProperties.StringProperty;
	FileListPathProt : WMProperties.StringProperty;
	FileListFilterProt : WMProperties.StringProperty;
	FileListPrefixSearchProt : WMProperties.BooleanProperty;
	
	GSonPathChanged, GSonPathChangedInfo : Utilities.String;
	
	nofWindows : LONGINT;
	
PROCEDURE InitPrototypes;
BEGIN
	NEW(DirTreePathProt, NIL, Utilities.NewString("CurrentPath"), Utilities.NewString("contains the selected path"));
	GSonPathChanged := Utilities.NewString("onPathChanged");
	GSonPathChangedInfo := Utilities.NewString("called when the path is changed");

	NEW(FileListPathProt, NIL, Utilities.NewString("Path"), Utilities.NewString("contains the displayed path"));
	NEW(FileListFilterProt, NIL, Utilities.NewString("Filter"), Utilities.NewString("display filename filter"));
	NEW(FileListPrefixSearchProt, NIL, Utilities.NewString("PrefixSearch"), Utilities.NewString("match prefix only"));
	FileListPrefixSearchProt.Set(TRUE);
END InitPrototypes;

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


PROCEDURE Open*(par : ANY) : ANY;
VAR inst : Window;
BEGIN
	NEW(inst);
	RETURN NIL
END Open;

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
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	InitPrototypes;
	AosModules.InstallTermHandler(Cleanup)
END WMSystemComponents.

S.Free WMSystemComponents ~
WMSystemComponents.Open ~

AosFSTools.Mount RUM RamFS 409600 4096 ~
AosFSTools.Unmount RAM ~
AosFSTools.Mount FAT FatFS IDE0#6 ~

