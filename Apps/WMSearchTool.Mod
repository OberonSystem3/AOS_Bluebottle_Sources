(* Aos, Copyright 2005, U. Glavitsch, ETH Zurich *)

MODULE WMSearchTool; (** AUTHOR "ug"; PURPOSE "Search tool for text files"; *)

IMPORT AosFS, AosModules, AosOut, WMSystemComponents, WMComponents, WMStandardComponents, WMGraphics, 
	WMWindowManager, WMEditors, WMRectangles, WMGrids, WMStringGrids, WMMessages, WMRestorable, Utilities;
		
CONST
	RListSize = 1000;

TYPE
	KillerMsg = OBJECT
	END KillerMsg;  
	
	Window = OBJECT(WMComponents.FormWindow)
	VAR
		grid : WMStringGrids.StringGrid;	
		status : WMStandardComponents.Panel;
		statusLabel : WMStandardComponents.Label;	
		pathEdit, fmaskEdit, contentEdit : WMEditors.Editor;
		filelist : WMSystemComponents.FileList;
		lb : ListBuffer;
		s : Searcher;
		d : GridDisplayer;
				
		PROCEDURE &New(c : WMRestorable.Context);
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount;
			
			vc := CreateForm();
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE); 
			SetContent(vc);
			
			IF c # NIL THEN
				(* restore the desktop *)
				WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame});
			ELSE
				WMWindowManager.DefaultAddWindow(SELF);	
			END;		
			SetTitle(Utilities.NewString("Search Tool"));

			NEW(lb);
			NEW(s, lb);
			NEW(d, lb, filelist.DisplayGrid, SearchStartHandler, SearchDoneHandler)
		END New;
		
		PROCEDURE Close;
		BEGIN
			Close^;
			DecCount
		END Close;

		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR panel : WMStandardComponents.Panel;
			toolbarPath, toolbarFMask, toolbar, toolbarSearch : WMStandardComponents.Panel;
			pathLabel, fmaskLabel, contentLabel : WMStandardComponents.Label;
			filledPathString : ARRAY 1024 OF CHAR;
			searchBtn, stopBtn : WMStandardComponents.Button;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(700, 500); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
						
			NEW(toolbarPath); toolbarPath.fillColor.Set(0FFFFFFFFH);  toolbarPath.bounds.SetHeight(25);
			toolbarPath.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbarPath);
			
			NEW(toolbarFMask); toolbarFMask.fillColor.Set(0FFFFFFFFH); toolbarFMask.bounds.SetHeight(25);
			toolbarFMask.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbarFMask);

			NEW(toolbar); toolbar.fillColor.Set(0FFFFFFFFH); toolbar.bounds.SetHeight(25); 
			toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);			

			NEW(toolbarSearch); toolbarSearch.fillColor.Set(0FFFFFFFFH); toolbarSearch.bounds.SetHeight(20);
			toolbarSearch.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbarSearch);
			
			NEW(pathLabel); pathLabel.alignment.Set(WMComponents.AlignLeft);
			pathLabel.bounds.SetWidth(70); pathLabel.fillColor.Set(0FFFFFFFFH);
			pathLabel.SetCaption(" Path:");
			toolbarPath.AddContent(pathLabel);
			
			FillFirstMountedFS(filledPathString); 
			NEW(pathEdit); pathEdit.SetAsString(filledPathString); pathEdit.alignment.Set(WMComponents.AlignLeft);
			pathEdit.bounds.SetWidth(300); pathEdit.multiLine.Set(FALSE);
			pathEdit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1));
			pathEdit.tv.showBorder.Set(TRUE);
			pathEdit.fillColor.Set(0FFFFFFFFH);
			toolbarPath.AddContent(pathEdit);			
			
			NEW(pathLabel); pathLabel.alignment.Set(WMComponents.AlignLeft);
			pathLabel.bounds.SetWidth(300); pathLabel.fillColor.Set(0FFFFFFFFH);
			pathLabel.SetCaption(" e.g. FS:, FS:/subDir, FS:/subDir/subSubDir, etc.");
			toolbarPath.AddContent(pathLabel);
			
			NEW(fmaskLabel); fmaskLabel.alignment.Set(WMComponents.AlignLeft);
			fmaskLabel.bounds.SetWidth(70); fmaskLabel.fillColor.Set(0FFFFFFFFH);
			fmaskLabel.SetCaption(" Files:");
			toolbarFMask.AddContent(fmaskLabel);		
			
			NEW(fmaskEdit); fmaskEdit.alignment.Set(WMComponents.AlignLeft);
			fmaskEdit.bounds.SetWidth(300); fmaskEdit.multiLine.Set(FALSE);
			fmaskEdit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1));
			fmaskEdit.tv.showBorder.Set(TRUE);
			fmaskEdit.fillColor.Set(0FFFFFFFFH);
			toolbarFMask.AddContent(fmaskEdit);
			
			NEW(contentLabel); contentLabel.alignment.Set(WMComponents.AlignLeft);
			contentLabel.bounds.SetWidth(70); contentLabel.fillColor.Set(0FFFFFFFFH);
			contentLabel.SetCaption(" Content:");
			toolbar.AddContent(contentLabel);				

			NEW(contentEdit); contentEdit.alignment.Set(WMComponents.AlignLeft);
			contentEdit.bounds.SetWidth(300); contentEdit.multiLine.Set(FALSE);
			contentEdit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1));
			contentEdit.tv.showBorder.Set(TRUE);
			contentEdit.fillColor.Set(0FFFFFFFFH);
			toolbar.AddContent(contentEdit);

			NEW(searchBtn);
			searchBtn.caption.SetAOC("Go");
			searchBtn.alignment.Set(WMComponents.AlignLeft);
			searchBtn.bounds.SetWidth(80);
			searchBtn.onClick.Add(SearchHandler); 
			toolbarSearch.AddContent(searchBtn); 	
			
			NEW(stopBtn);
			stopBtn.caption.SetAOC("Stop");
			stopBtn.alignment.Set(WMComponents.AlignLeft);
			stopBtn.bounds.SetWidth(80);
			stopBtn.onClick.Add(StopHandler);
			toolbarSearch.AddContent(stopBtn);		

			NEW(status); status.alignment.Set(WMComponents.AlignBottom); status.bounds.SetHeight(20);
			panel.AddContent(status); status.fillColor.Set(0CCCCCCFFH);

			NEW(statusLabel); statusLabel.bounds.SetWidth(panel.bounds.GetWidth()); 
			statusLabel.caption.SetAOC("Status : Ready"); statusLabel.alignment.Set(WMComponents.AlignLeft);
			status.AddContent(statusLabel);
			
			NEW(filelist);
			filelist.SetSearchReqFlag;
			filelist.alignment.Set(WMComponents.AlignClient);			
			panel.AddContent(filelist);

			RETURN panel
		END CreateForm;
	
		PROCEDURE FillFirstMountedFS(VAR s : ARRAY OF CHAR);
		VAR list: AosFS.FileSystemTable;
		BEGIN
			AosFS.GetList(list);
			IF LEN(list) > 0 THEN
				COPY(list[0].prefix, s); Utilities.Append(s, ":")
			ELSE
				s := "";
			END
		END FillFirstMountedFS;
		
		PROCEDURE SearchDoneHandler;
		BEGIN
			statusLabel.caption.SetAOC("Status : Ready");				
		END SearchDoneHandler;
		
		PROCEDURE SearchStartHandler;
		BEGIN
			statusLabel.caption.SetAOC("Status : Processing ...")
		END SearchStartHandler;
		
		PROCEDURE SearchHandler(sender, data : ANY);
		VAR			
			searchPar : SearchPar;	
		BEGIN
			pathEdit.GetAsString(searchPar.path); fmaskEdit.GetAsString(searchPar.fmask); contentEdit.GetAsString(searchPar.content);
			StopSearcherAndDisplayer();
			filelist.ResetGrid;
			s.Start(searchPar);
			d.Start()
		END SearchHandler;
		
		PROCEDURE StopHandler(sender, data : ANY);
		BEGIN
			StopSearcherAndDisplayer()
		END StopHandler;
		
		PROCEDURE StopSearcherAndDisplayer();
		BEGIN
			s.Stop();
			d.Stop()
		END StopSearcherAndDisplayer;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS KillerMsg) THEN Close 
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("WMSearchTool", "WMSearchTool.Restore", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;
		
	BEGIN
	END Window;
	
TYPE
	SearchPar = RECORD
		path, fmask, content : ARRAY 256 OF CHAR
	END;
	
	Searcher = OBJECT
	VAR
		newlyStarted, stopped : BOOLEAN;
		currentPar, newPar : SearchPar;
		lb : ListBuffer;
	
		PROCEDURE &Init(lb : ListBuffer);
		BEGIN
			newlyStarted := FALSE;
			stopped := FALSE;
			SELF.lb := lb;
		END Init;
		
		PROCEDURE Start(searchPar : SearchPar);
		BEGIN {EXCLUSIVE}
			newPar := searchPar;
			newlyStarted := TRUE;
		END Start;
		
		PROCEDURE AwaitNewStart;
		BEGIN {EXCLUSIVE}
			AWAIT(newlyStarted = TRUE);
			newlyStarted := FALSE;
			stopped := FALSE;
		END AwaitNewStart;
		
		PROCEDURE CopySearchParams;
		BEGIN {EXCLUSIVE}
			currentPar := newPar
		END CopySearchParams;

		PROCEDURE Stop;
		BEGIN {EXCLUSIVE}
			stopped := TRUE;
		END Stop;
		
		PROCEDURE IsStopped() : BOOLEAN;
		BEGIN {EXCLUSIVE}
			RETURN stopped;
		END IsStopped;

		(* Boyer-Moore match for streams *)
		PROCEDURE ContainsStr(filename, content : ARRAY OF CHAR) : BOOLEAN;
		VAR r : AosFS.Reader;
			f : AosFS.File;
			d : ARRAY 256 OF LONGINT;
			cb : Utilities.String;
			cpos, i, j, k, m, l, shift : LONGINT;
		BEGIN
			m := Utilities.Length(content); 
			f := AosFS.Old(filename);
			IF f # NIL THEN
				AosFS.OpenReader(r, f, 0);
				NEW(cb, m);
				WHILE (r.res # 0) & (cpos < m) DO
					cb[cpos] := r.Get();
					INC(cpos);
				END;	
				IF r.res = 0 THEN
					FOR i := 0 TO 255 DO d[i] := m END;
					FOR i := 0 TO m-2 DO d[ORD(content[i])] := m - i - 1 END;
					i := m;
					REPEAT j := m; k := i;
						REPEAT DEC(k); DEC(j);
						UNTIL (j < 0) OR (content[j] # cb[k MOD m]);
						shift := d[ORD(cb[(i-1) MOD m])];
						i := i + shift;
						WHILE (cpos < i) & (r.res = 0) DO
							cb[cpos MOD m] := r.Get();
							INC(cpos);
						END;
						IF IsStopped() THEN RETURN FALSE END
					UNTIL (j < 0) OR (r.res # 0);
					IF j < 0 THEN RETURN TRUE END
				END;
				RETURN FALSE
			ELSE RETURN FALSE
			END	
		END ContainsStr;

		PROCEDURE Match(VAR name : ARRAY OF CHAR);
		VAR d : WMSystemComponents.DirEntry;
			p, filename : ARRAY 1024 OF CHAR;
			l : LONGINT;
		BEGIN
			IF (currentPar.content = "") OR ContainsStr(name, currentPar.content)  THEN 
				AosFS.SplitPath(name, p, filename);
				l := Utilities.Length(p);
				p[l] := name[l]; p[l + 1] := 0X;
				NEW(d, Utilities.NewString(filename), Utilities.NewString(p), 0, 0, 0, {});
				lb.Put(d)
			END;
		END Match;	

		PROCEDURE SearchPath;
		VAR mask, name : ARRAY 1024 OF CHAR;
			flags : SET;
			time, date, size, len : LONGINT;
			e : AosFS.Enumerator;
		BEGIN
			COPY(currentPar.path, mask); 
			len := Utilities.Length(mask);
			IF (mask[len-1] = ':') OR (mask[len-1] = '/') THEN
				Utilities.Append(mask, currentPar.fmask)
			ELSE
				Utilities.Append(mask, '/'); Utilities.Append(mask, currentPar.fmask)
			END;
			NEW(e);
			e.Open(mask, {});
			WHILE e.HasMoreEntries() DO
				IF IsStopped() THEN RETURN END;
				IF e.GetEntry(name, flags, time, date, size) THEN
					IF ~(AosFS.Directory IN flags) THEN
						Match(name)
					END;
				END
			END
		END SearchPath;
		
	BEGIN {ACTIVE}
		LOOP
			AwaitNewStart;
			CopySearchParams;
			lb.Reset;
			SearchPath;
			lb.Finished;
		END
	END Searcher;
	
	GridDisplayHandler = PROCEDURE {DELEGATE} (VAR data : ARRAY OF WMSystemComponents.DirEntry; noEl : LONGINT);
	SearchStatusHandler = PROCEDURE {DELEGATE} ();

	GridDisplayer= OBJECT
		VAR rl : RetrievedList;
			display : GridDisplayHandler;
			startHandler, stopHandler : SearchStatusHandler;
			newlyStarted, stopped : BOOLEAN;
			lb : ListBuffer;
			
		PROCEDURE &Init(lb : ListBuffer; display : GridDisplayHandler; sh, dh : SearchStatusHandler);
		BEGIN
			SELF.lb := lb;
			SELF.display := display;
			startHandler := sh;
			stopHandler := dh;
			newlyStarted := FALSE;
			stopped := FALSE
		END Init;
		
		PROCEDURE Start();
		BEGIN {EXCLUSIVE}
			newlyStarted := TRUE;
		END Start;
		
		PROCEDURE AwaitNewStart;
		BEGIN {EXCLUSIVE}
			AWAIT(newlyStarted);
			newlyStarted := FALSE;
			stopped := FALSE
		END AwaitNewStart;
		
		PROCEDURE Stop;
		BEGIN {EXCLUSIVE}
			stopped := TRUE
		END Stop;
		
	BEGIN {ACTIVE}
		LOOP
			AwaitNewStart; 
			startHandler;
			LOOP
				lb.Get(rl);
				IF (rl.noEl = 0) OR stopped THEN EXIT END; (* either done or stopped *)
				display(rl.data, rl.noEl)
			END;
			stopHandler;
		END
	END GridDisplayer;

TYPE
	RetrievedList = RECORD
		data : ARRAY RListSize OF WMSystemComponents.DirEntry;
		noEl : INTEGER;
	END;
	
	ListBuffer = OBJECT
	VAR
		data : ARRAY RListSize OF WMSystemComponents.DirEntry;
		in, out, maxNoEl : INTEGER;
		finished : BOOLEAN;
			
		PROCEDURE &Init;
		BEGIN
			Reset
		END Init;
			
		PROCEDURE Reset;
		BEGIN {EXCLUSIVE}
			in := 0; out := 0; maxNoEl := 1;
			finished := FALSE
		END Reset;
		
		PROCEDURE Put(d : WMSystemComponents.DirEntry);
		BEGIN {EXCLUSIVE}
			AWAIT(((in + 1) MOD RListSize) # (out MOD RListSize));
			data[in MOD RListSize] := d;
			INC(in)				
		END Put;
		
		PROCEDURE Finished;
		BEGIN {EXCLUSIVE}
			finished := TRUE;
		END Finished;
		
		PROCEDURE Get(VAR rlist : RetrievedList);
		VAR i, j : INTEGER;
		BEGIN {EXCLUSIVE}
			AWAIT((in - out >= maxNoEl) OR finished);
			i := 0;
			FOR j := out TO in -1 DO
				rlist.data[i] := data[j MOD RListSize];
				INC(i);	
			END;
			rlist.noEl := i;
			IF i > maxNoEl THEN maxNoEl := i END;
			out := in
		END Get;
		
	BEGIN
	END ListBuffer;				
				
VAR
	nofWindows : LONGINT;
	
PROCEDURE Restore*(par : ANY) : ANY;
VAR w : Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(w, par(WMRestorable.Context))
	END;
	RETURN NIL
END Restore;

PROCEDURE Open*(par : ANY) : ANY;
VAR inst : Window;
BEGIN
	NEW(inst, NIL);
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
VAR die : KillerMsg;  msg : WMMessages.Message;  m : WMWindowManager.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die); msg.ext := die; msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMSearchTool.

S.Free WMSystemComponents WMSearchTool WMFileManager~
WMSearchTool.Open ~

