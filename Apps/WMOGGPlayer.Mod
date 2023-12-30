MODULE WMOGGPlayer;	(** AUTHOR "TF/Christian Wassmer"; PURPOSE "Simple GUI to the OGG Player"; *)

IMPORT
	AosCommands, AosFS, AosIO, AosModules,
	Utilities, WMMessages, WMComponents, WMStandardComponents,
	WMGrids, WMStringGrids, OGGVorbisPlayer,
	WM := WMWindowManager;

TYPE
	KillerMsg = OBJECT
	END KillerMsg;

	PlaylistEntry = OBJECT
	VAR url : Utilities.String;
	END PlaylistEntry;

	Player = OBJECT
	VAR url : Utilities.String;
		dummy : BOOLEAN;
		PROCEDURE &Init(url : Utilities.String);
		BEGIN
			SELF.url := url
		END Init;

	BEGIN {ACTIVE}
		dummy := OGGVorbisPlayer.PlayURL(url);
	END Player;

	Window* = OBJECT (WMComponents.FormWindow)
	VAR
		playBtn, stopBtn : WMStandardComponents.Button;
		list : WMStringGrids.StringGrid;
		player : Player;

		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			toolbar : WMStandardComponents.Panel;
			button : WMStandardComponents.Button;

		BEGIN
			NEW(panel); panel.bounds.SetExtents(200, 700); panel.fillColor.Set(0FFFFFFFFH); panel.takesFocus.Set(TRUE);
			NEW(toolbar); toolbar.fillColor.Set(0A0A0A0FFH); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(button); button.alignment.Set(WMComponents.AlignLeft); button.caption.SetAOC("Play");
			toolbar.AddContent(button);
			playBtn := button;

			NEW(button); button.alignment.Set(WMComponents.AlignLeft); button.caption.SetAOC("Stop");
			toolbar.AddContent(button);
			stopBtn := button;

			NEW(list); list.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(list);

			RETURN panel
		END CreateForm;

		PROCEDURE &New(filename : AosFS.FileName);
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount;
			(* To create a multi language app, try loading the respective XML instead of CreateForm()
			if the XML was not found or does not contain all needed elements, use CreateForm as fallback *)
			vc := CreateForm();

			(* wire the form *)
			list.model.Acquire;
			list.model.SetNofCols(1);
			list.model.SetNofRows(1);
			list.SetSelectionMode(WMGrids.GridSelectRows);
			list.model.Release;

			playBtn.onClick.Add(Play);
			stopBtn.onClick.Add(Stop);

			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);

			FillList(filename);

			 WM.DefaultAddWindow(SELF);
			SetTitle(Utilities.NewString("OGG Player"));
		END New;

		(* fills the list with radio stations read from a file ("OGGRadios.Text")*)
		PROCEDURE FillList(OGGlist : ARRAY OF CHAR);
		VAR entry : PlaylistEntry;
			first : BOOLEAN;
			i : LONGINT;
			r : AosFS.Reader;
			f : AosFS.File;
			url, name : ARRAY 256 OF CHAR;
		BEGIN
			f := AosFS.Old(OGGlist);
			AosFS.OpenReader(r, f, 0);
			i := 0; first := TRUE;
			list.model.Acquire;
			list.model.SetNofRows(64);
			WHILE (r.res = 0) & (i # 64) DO
				r.SkipWhitespace;
				r.String(url);
				IF first OR (url[0] = '#') THEN
					first := FALSE;
					r.SkipLn
				ELSE
					r.SkipWhitespace;
					r.Ln(name);
					list.model.SetCellText(0, i,Utilities.NewString(name));
					NEW(entry);
					entry.url := Utilities.NewString(url);
					list.model.SetCellData(0, i, entry);
					INC(i)
				END
			END;
			list.model.Release;
			list.Invalidate;
		END FillList;

		PROCEDURE Play(sender, data : ANY);
		VAR l, t, r, b : LONGINT;
			p : ANY; url : Utilities.String;
		BEGIN
			list.Acquire;
			list.model.Acquire;
			list.GetSelection(l, t, r, b);
			p := list.model.GetCellData(0, t);
			IF (p # NIL) & (p IS PlaylistEntry) THEN
				url := p(PlaylistEntry).url;
				IF url # NIL THEN
					NEW(player, url)
				END
			END;
			list.model.Release;
			list.Release;
		END Play;

		PROCEDURE Stop(sender, data : ANY);
		BEGIN
			OGGVorbisPlayer.StopURL()
		END Stop;

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

	END Window;

VAR
	nofWindows : LONGINT;

PROCEDURE Open*(par : ANY) : ANY;
VAR win : Window;
	sr : AosIO.StringReader; fn : AosFS.FileName;
BEGIN
	AosCommands.PosPar(par, sr);
	AosCommands.GetTok(sr, fn);
	IF fn = "" THEN fn := "OGGRadios.Text" END;
	NEW(win, fn);
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
	AosModules.InstallTermHandler(Cleanup);
END WMOGGPlayer.

WMOGGPlayer.Open OGGRadios.Text ~
S.Free WMOGGPlayer OGGVorbisPlayer OGGUtilities ~
S.Free EnsoniqSound ~
