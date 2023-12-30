MODULE PresentViewer;	(** AUTHOR "TF"; PURPOSE "Testbed for the component system"; *)

IMPORT
	AosOut, AosModules, AosIO, AosCommands, WMStandardComponents, WMComponents, XML, WMMessages,
	WM := WMWindowManager, WMEditors; 
	
VAR w : WMComponents.FormWindow;

PROCEDURE Open*(par : PTR) : PTR;
VAR c : XML.Content; filename : ARRAY 128 OF CHAR;
		s : AosCommands.Parameters;
		sr : AosIO.StringReader;
		m : WM.WindowManager;
		width, height : LONGINT;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^); sr.Token(filename);
	c := WMComponents.Load(filename);
	width := 320; height := 240;
	IF c # NIL THEN
		IF c IS WMComponents.VisualComponent THEN
			width := c(WMComponents.VisualComponent).bounds.GetWidth(); 
			height := c(WMComponents.VisualComponent).bounds.GetHeight();
			IF width <= 0 THEN width := 10 END; IF height <= 0 THEN height := 10 END
		END;
		NEW(w, width, height, TRUE); 
		w.pointerThreshold := 50;
		WM.ExtAddWindow(w, 500, 350, {});
(*		m := WM.GetDefaultManager(); m.Add(100, 100, w, {}); *)
		w.SetTitle(c(XML.Element).GetAttributeValue("caption"));
		w.SetContent(c);
	ELSE
		AosOut.String(filename); AosOut.String(" not correctly loaded"); AosOut.Ln
	END;	
	RETURN NIL
END Open;

(* Cleanup on module free *)
PROCEDURE Cleanup;
BEGIN
	IF w # NIL THEN w.Close END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END PresentViewer.

S.Free PresentViewer ~
PresentViewer.Open XmasMenu.XML ~



