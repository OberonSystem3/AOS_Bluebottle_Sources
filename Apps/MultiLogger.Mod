MODULE MultiLogger;

IMPORT
	AosIO, AosTextUtilities, 
	WMComponents, WMEditors, WMGraphics, WMStandardComponents,
	WM := WMWindowManager;

TYPE
	LogWindow* = OBJECT (WMComponents.FormWindow)
	VAR
		panel : WMStandardComponents.Panel;
		out- : WMEditors.Editor;
		tw- : AosTextUtilities.TextWriter;
		open : BOOLEAN;

		PROCEDURE &New(title : ARRAY OF CHAR; VAR stream : AosIO.Writer);
		BEGIN
			NEW(panel); panel.bounds.SetExtents(640, 420); panel.fillColor.Set(WMGraphics.RGBAToColor(255, 255, 255, 255));

			NEW(out); out.alignment.Set(WMComponents.AlignClient);
			out.tv.showBorder.Set(TRUE);
			panel.AddContent(out);

			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), FALSE);
			SetContent(panel);
			manager := WM.GetDefaultManager();
			SetTitle(WMComponents.NewString(title));
			WM.DefaultAddWindow(SELF);
			NEW(tw, out.text);
			stream := tw.GetWriter();
			open := TRUE
		END New;

		PROCEDURE Close;
		BEGIN
			open := FALSE;
			Close^
		END Close;

	END LogWindow;

END MultiLogger.
