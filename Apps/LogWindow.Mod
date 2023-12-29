MODULE LogWindow;	(** AUTHOR "TF"; PURPOSE "Kernel log window"; *)

IMPORT
	AosOut, AosModules, AosCommands, WMStandardComponents, 
	WMWindowManager, WMComponents,  
	WMEditors, WMGraphics, Utilities,
	WMRestorable, WMMessages,
	AosTexts, AosTextUtilities, WMLog, WMBitmapFont;

TYPE
	Window* = OBJECT (WMComponents.FormWindow)
	VAR 
		panel, toolbar : WMStandardComponents.Panel;
		out- : WMEditors.Editor;
		clear : WMStandardComponents.Button;
	
		PROCEDURE &New(c : WMRestorable.Context);
		BEGIN
			NEW(panel); panel.bounds.SetExtents(640, 420); panel.fillColor.Set(WMGraphics.RGBAToColor(255, 255, 255, 255));
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop); 
			panel.AddContent(toolbar);
			NEW(clear); clear.alignment.Set(WMComponents.AlignLeft); toolbar.AddContent(clear);
			clear.SetCaption("clear");
			clear.onClick.Add(ClearText);
			
			NEW(out); out.alignment.Set(WMComponents.AlignClient); out.tv.showBorder.Set(TRUE); panel.AddContent(out);
			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), FALSE);
			SetContent(panel);
			out.multiLine.Set(TRUE);
			out.readOnly.Set(TRUE);
			SetTitle(Utilities.NewString("Kernel log"));
			out.SetText(WMLog.kernelLog);
			WMLog.kernelLog.AcquireRead;
			out.tv.cursor.SetPosition(WMLog.kernelLog.GetLength());
			WMLog.kernelLog.ReleaseRead;

			IF c # NIL THEN WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagFrame})				
			ELSE WMWindowManager.DefaultAddWindow(SELF)
			END;
		END New;
		
		PROCEDURE ClearText(sender, data : ANY);
		BEGIN
			WMLog.kernelLog.AcquireWrite;
			WMLog.kernelLog.Delete(0, WMLog.kernelLog.GetLength());
			out.tv.firstLine.Set(0); out.tv.cursor.SetPosition(0);
			WMLog.kernelLog.ReleaseWrite
		END ClearText;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("Logwindow", "LogWindow.Open", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;
		
		PROCEDURE Close;
		BEGIN
			FreeWindow;
			Close^
		END Close;
		
	END Window;

VAR window : Window;

PROCEDURE FreeWindow;
BEGIN {EXCLUSIVE}
	window := NIL
END FreeWindow;

PROCEDURE Open*(par: PTR): PTR;		
BEGIN {EXCLUSIVE}
	IF window = NIL THEN 
		IF (par # NIL) & (par IS WMRestorable.Context) THEN NEW(window, par(WMRestorable.Context))
		ELSE NEW(window, NIL)
		END
	ELSE WMWindowManager.DefaultBringToView(window, TRUE)
	END;
	RETURN NIL
END Open;

PROCEDURE Cleanup;
BEGIN
	IF window # NIL THEN window.Close END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END LogWindow.
WMLog.Mod

WMLog.Start
WMLog.Stop

LogWindow.Open ~
S.Free LogWindow ~

