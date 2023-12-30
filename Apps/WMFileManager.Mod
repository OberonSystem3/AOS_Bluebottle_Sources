MODULE WMFileManager;		(** AUTHOR "ug"; PURPOSE  "file manager"; *)

IMPORT AosFS, AosModules, WMProperties,
	WMEditors, WMSystemComponents, WMComponents, WMStandardComponents, WMMessages, WMRestorable, Utilities,
	WM := WMWindowManager;

TYPE
	KillerMsg = OBJECT
	END KillerMsg;

	FileListPanel* = OBJECT (WMComponents.VisualComponent)
		VAR pathProp*, filterProp : WMProperties.StringProperty;
			filterEdit : WMEditors.Editor;
			list* : WMSystemComponents.FileList;
		
		PROCEDURE &Init;
		BEGIN
			Init^;

			(* new properties *)
			NEW(pathProp, FileListPathProt, NIL, NIL); properties.Add(pathProp);
			NEW(filterProp, FileListFilterProt, NIL, NIL); properties.Add(filterProp);

			NEW(filterEdit); filterEdit.alignment.Set(WMComponents.AlignTop);
			filterEdit.bounds.SetHeight(25); AddContent(filterEdit);
			filterEdit.text.onTextChanged.Add(TextChanged);
			filterEdit.multiLine.Set(FALSE);
			filterEdit.tv.showBorder.Set(TRUE);

			NEW(list);
			list.alignment.Set(WMComponents.AlignClient);
			AddContent(list)
		END Init;

		PROCEDURE TextChanged(sender, data : ANY);
		VAR str : ARRAY 128 OF CHAR;
		BEGIN
			filterEdit.GetAsString(str);
			filterProp.Set(Utilities.NewString(str))
		END TextChanged;

		PROCEDURE PropertyChanged*(sender, data : ANY);
		BEGIN
			IF data = pathProp THEN
				list.StartNewPath(pathProp.Get())
			ELSIF (data = filterProp) THEN
				list.StartNewFilter(filterProp.Get())
			ELSE PropertyChanged^(sender, data)
			END
		END PropertyChanged;

	END FileListPanel;

	Window* = OBJECT (WMComponents.FormWindow)
	VAR label: WMStandardComponents.Label;
		tree : WMSystemComponents.DirectoryTree;
		flistPanel : FileListPanel;
		vol, cap, free, files : WMStandardComponents.Label;

		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			sidePanel, panel, status : WMStandardComponents.Panel;
			toolbar: WMStandardComponents.Panel;
			button : WMStandardComponents.Button;
			resizerH : WMStandardComponents.Resizer;

		BEGIN
			NEW(panel); panel.bounds.SetExtents(800, 700); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
			NEW(toolbar); toolbar.fillColor.Set(0FFFFFFFFH); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(button); button.alignment.Set(WMComponents.AlignLeft); button.caption.SetAOC("Refresh FileSystems");
			toolbar.AddContent(button); button.bounds.SetWidth(150); button.onClick.Add(RefreshHandler);
			NEW(button); button.alignment.Set(WMComponents.AlignLeft); button.caption.SetAOC("Toggle Properties");
			toolbar.AddContent(button); button.bounds.SetWidth(150); button.onClick.Add(TogglePropsHandler);
			NEW(status); status.alignment.Set(WMComponents.AlignBottom); status.bounds.SetHeight(20);
			panel.AddContent(status); status.fillColor.Set(0CCCCCCFFH);
			NEW(label); label.bounds.SetWidth(100); label.caption.SetAOC(" Volume: "); label.alignment.Set(WMComponents.AlignLeft);
			status.AddContent(label);
			NEW(vol); vol.bounds.SetWidth(100); vol.caption.SetAOC("-"); vol.alignment.Set(WMComponents.AlignLeft);
			status.AddContent(vol);
			NEW(label); label.bounds.SetWidth(100); label.caption.SetAOC(" Size: "); label.alignment.Set(WMComponents.AlignLeft);
			status.AddContent(label);
			NEW(cap); cap.bounds.SetWidth(100); cap.caption.SetAOC("-"); cap.alignment.Set(WMComponents.AlignLeft);
			status.AddContent(cap);
			NEW(label); label.bounds.SetWidth(100); label.caption.SetAOC(" Free: "); label.alignment.Set(WMComponents.AlignLeft);
			status.AddContent(label);
			NEW(free); free.bounds.SetWidth(100); free.caption.SetAOC("-"); free.alignment.Set(WMComponents.AlignLeft);
			status.AddContent(free);
			NEW(label); label.bounds.SetWidth(100); label.caption.SetAOC(" Files: "); label.alignment.Set(WMComponents.AlignLeft);
			status.AddContent(label);
			NEW(files); files.bounds.SetWidth(100); files.caption.SetAOC("-"); files.alignment.Set(WMComponents.AlignLeft);
			status.AddContent(files);

			NEW(sidePanel); sidePanel.alignment.Set(WMComponents.AlignLeft); sidePanel.bounds.SetWidth(200);
			NEW(resizerH); resizerH.alignment.Set(WMComponents.AlignRight); resizerH.bounds.SetWidth(4);
			sidePanel.AddContent(resizerH);
			NEW(tree); tree.alignment.Set(WMComponents.AlignClient);
			sidePanel.AddContent(tree);
			panel.AddContent(sidePanel);

			NEW(flistPanel); flistPanel.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(flistPanel);

			RETURN panel
		END CreateForm;

		PROCEDURE &New(c : WMRestorable.Context);
		VAR vc : WMComponents.VisualComponent; s : Utilities.String;
		BEGIN
			IncCount;
			vc := CreateForm();
			
			tree.onPathChanged.Add(PathChanged);
			
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);

			IF c # NIL THEN 
				(* restore the desktop *)
				WMRestorable.AddByContext(SELF, c, {WM.FlagFrame});
			ELSE 
				WM.DefaultAddWindow(SELF);
			END;

			SetTitle(Utilities.NewString("File Manager"));
			s := tree.currentPath.Get();
		END New; 

		PROCEDURE PathChanged(sender, data : ANY);
		BEGIN
			flistPanel.pathProp.Set(tree.currentPath.Get());
			UpdateStatus(tree.currentPath.Get());
		END PathChanged;

		PROCEDURE UpdateStatus(alias : Utilities.String);
		VAR sfree, total, nfiles, i: LONGINT; fs: AosFS.FileSystem; ft: AosFS.FileSystemTable;
			temp : ARRAY 32 OF CHAR;
		BEGIN
			AosFS.GetList(ft);
			IF ft # NIL THEN
				FOR i := 0 TO LEN(ft)-1 DO
					fs := ft[i];
					COPY(fs.prefix, temp);
					Utilities.Append(temp, ":");
					IF (alias^ = temp) THEN
						IF fs.vol # NIL THEN
							vol.caption.SetAOC(alias^);
							sfree := ENTIER(fs.vol.Available()/1024.0D0 * fs.vol.blockSize);
							total := ENTIER(fs.vol.size/1024.0D0 * fs.vol.blockSize);
							Utilities.IntToStr(total, temp); Utilities.Append(temp, " KB");
							cap.caption.SetAOC(temp);
							Utilities.IntToStr(sfree, temp); Utilities.Append(temp, " KB");
							free.caption.SetAOC(temp);
							nfiles := flistPanel.list.GetNofFiles();
							Utilities.IntToStr(nfiles, temp);
							files.caption.SetAOC(temp);
						END;
					END;
				END
			END;
		END UpdateStatus;

		PROCEDURE Close;
		BEGIN
			Close^;
			DecCount;
		END Close;

		PROCEDURE RefreshHandler(sender, data: ANY);
		BEGIN
			tree.Refresh;
		END RefreshHandler;

		PROCEDURE TogglePropsHandler(sender, data: ANY);
		BEGIN
			flistPanel.list.ToggleProps;
		END TogglePropsHandler;

		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
			ELSIF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS WMRestorable.Storage) THEN
				x.ext(WMRestorable.Storage).Add("FileManager", "WMFileManager.Restore", SELF, NIL)
			ELSE Handle^(x)
			END
		END Handle;

	END Window;

VAR
	nofWindows : LONGINT;
	FileListPathProt : WMProperties.StringProperty;
	FileListFilterProt : WMProperties.StringProperty;

PROCEDURE Open*(par : ANY) : ANY;
VAR win : Window;
BEGIN
	NEW(win, NIL);
	RETURN NIL
END Open;

PROCEDURE Restore*(par : ANY) : ANY;
VAR win : Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(win, par(WMRestorable.Context))
	END;
	RETURN NIL
END Restore;

PROCEDURE InitPrototypes;
BEGIN
	NEW(FileListPathProt, NIL, Utilities.NewString("Path"), Utilities.NewString("contains the displayed path"));
	NEW(FileListFilterProt, NIL, Utilities.NewString("Filter"), Utilities.NewString("display filename filter"));
END InitPrototypes;

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
	InitPrototypes;
	AosModules.InstallTermHandler(Cleanup);
END WMFileManager.

S.Free WMFileManager WMSystemComponents ~
WMFileManager.Open ~

