MODULE LogWindow;	(** AUTHOR "TF"; PURPOSE "Kernel log window"; *)

IMPORT
	AosModules, WMStandardComponents, WMComponents,
	WMEditors, WMGraphics, Utilities,
	WMRestorable, WMMessages, WMLog,
	WM := WMWindowManager;

TYPE
	Window* = OBJECT (WMComponents.FormWindow)
	VAR 
		panel, toolbar : WMStandardComponents.Panel;
		clear : WMStandardComponents.Button;
		out- : WMEditors.Editor;

		PROCEDURE &New(c : WMRestorable.Context);
		BEGIN
			NEW(panel); panel.bounds.SetExtents(640, 420); panel.fillColor.Set(WMGraphics.RGBAToColor(255, 255, 255, 255));

			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop); 
			panel.AddContent(toolbar);

			NEW(clear); clear.alignment.Set(WMComponents.AlignLeft);
			toolbar.AddContent(clear);
			clear.SetCaption("clear");
			clear.onClick.Add(ClearText);
			
			NEW(out); out.alignment.Set(WMComponents.AlignClient); out.tv.showBorder.Set(TRUE);
			panel.AddContent(out);

			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), FALSE);
			SetContent(panel);
			out.multiLine.Set(TRUE);
			SetTitle(Utilities.NewString("Kernel log"));
			out.SetText(WMLog.kernelLog);
			WMLog.kernelLog.AcquireRead;
			out.tv.cursor.SetPosition(WMLog.kernelLog.GetLength());
			WMLog.kernelLog.ReleaseRead;

			IF c # NIL THEN WMRestorable.AddByContext(SELF, c, {WM.FlagFrame});
				Resized(GetWidth(), GetHeight())		
			ELSE WM.DefaultAddWindow(SELF)
			END
		END New;

		PROCEDURE ClearText(sender, data : ANY);
		BEGIN
			WMLog.kernelLog.AcquireWrite;
			WMLog.kernelLog.Delete(0, WMLog.kernelLog.GetLength());
			out.tv.firstLine.Set(0); out.tv.cursor.SetPosition(0);
			WMLog.kernelLog.ReleaseWrite
		END ClearText;

		PROCEDURE Handle(VAR x : WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("Logwindow", "LogWindow.Restore", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;

		PROCEDURE Close;
		BEGIN
			Close^;
			winstance := NIL
		END Close;
		
	END Window;

VAR winstance : Window;

PROCEDURE Open*(par : PTR) : PTR;
BEGIN
	IF winstance = NIL THEN
		NEW(winstance, NIL)
	ELSE
		WM.DefaultBringToView(winstance, TRUE)
	END;
	RETURN NIL
END Open;

PROCEDURE Restore* (par : ANY) : ANY;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(winstance, par(WMRestorable.Context))
	END;
	RETURN NIL
END Restore;

PROCEDURE Cleanup;
BEGIN
	IF winstance # NIL THEN winstance.Close END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END LogWindow.

LogWindow.Open ~
S.Free LogWindow ~

WMLog.Mod
WMLog.Start ~
WMLog.Stop ~


