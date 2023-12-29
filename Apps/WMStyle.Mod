MODULE WMStyle; (** AUTHOR "TF"; PURPOSE "Load window styles"; *)

IMPORT
	AosOut, AosIO, AosFS, Raster, WM := WMWindowManager,
	(* XML framework *)
	XML, Scanner := XMLScanner, XMLParser, Objects := XMLObjects, AosCommands,
	Utilities, Graphics := WMGraphics;

CONST
	DefaultDecoration = "BluePlastic.XML";
	
VAR
	hasErrors : BOOLEAN;
	manager : WM.WindowManager;

PROCEDURE ReportError(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	hasErrors := TRUE;
	AosOut.Enter; AosOut.String("WMDecorate : Invalid XML file, error at "); AosOut.Int(pos, 5); AosOut.String(" (Line ");
	AosOut.Int(line, 5); AosOut.String(" col "); AosOut.Int(row, 5); AosOut.String(") Message = "); AosOut.String(msg);
	AosOut.Exit
END ReportError;
		
PROCEDURE ReadCursors(el : XML.Element);
VAR contents : Objects.Enumerator; p : PTR; x : XML.Element; s, ts : XML.String;
	
	PROCEDURE LoadPointerInfo(tx : XML.Element; pi : WM.PointerInfo);
	VAR hotX, hotY : LONGINT; ts : XML.String;
	BEGIN
		ts := tx.GetAttributeValue("hotX"); Utilities.StrToInt(ts^, hotX);
		ts := tx.GetAttributeValue("hotY"); Utilities.StrToInt(ts^, hotY);
		ts := tx.GetAttributeValue("img"); 

		WM.LoadCursor(ts^, hotX, hotY, pi);
	END LoadPointerInfo;

BEGIN
	contents := el.GetContents(); contents.Reset();
	WHILE contents.HasMoreElements() DO
		p := contents.GetNext();
		IF p IS XML.Element THEN
			x := p(XML.Element);
			s := x.GetName(); 
			IF (s # NIL) & (s^ = "Cursor") THEN
				ts := x.GetAttributeValue("name");
				IF ts # NIL THEN 
					IF ts^ = "default" THEN LoadPointerInfo(x, manager.pointerStandard) 
					ELSIF ts^ = "move" THEN LoadPointerInfo(x, manager.pointerMove)
					ELSIF ts^ = "text" THEN LoadPointerInfo(x, manager.pointerText)
					ELSIF ts^ = "crosshair" THEN LoadPointerInfo(x, manager.pointerCrosshair)
					ELSIF ts^ = "upleftdownright" THEN LoadPointerInfo(x, manager.pointerULDR)
					ELSIF ts^ = "updown" THEN LoadPointerInfo(x, manager.pointerUpDown)
					ELSIF ts^ = "leftright" THEN LoadPointerInfo(x, manager.pointerLeftRight)
					END
				END	
			END
		END
	END
END ReadCursors;

PROCEDURE Install*(par : PTR) : PTR;
VAR filename : AosFS.FileName;
		f : AosFS.File;
		scanner : Scanner.Scanner;
		parser : XMLParser.Parser;
		doc : XML.Document;
		p : PTR;
		cont : Objects.Enumerator;
		root: XML.Element;
		el : XML.Content;
		s, ts : Utilities.String;
		ps : AosCommands.Parameters; 
		desc : WM.WindowStyle;
		sr : AosIO.StringReader;
		res :LONGINT;
		
		PROCEDURE Error(x: ARRAY OF CHAR);
		BEGIN
(*			hasErrors := TRUE; *)
			AosOut.String("Style not completely defined, missing : ");
			AosOut.String(x);
			AosOut.Ln
		END Error;
		
		PROCEDURE LoadImg(name : ARRAY OF CHAR;VAR img : Graphics.Image);
		BEGIN
			img := Graphics.LoadImage(name, TRUE);
		END LoadImg;
		
BEGIN {EXCLUSIVE}
	NEW(desc);
	manager := WM.GetDefaultManager();
	ps := par(AosCommands.Parameters);
	NEW(sr, LEN(ps.str^)); sr.Set(ps.str^);
	sr.Token(filename); sr.SkipWhitespace;
	IF filename = "" THEN filename := DefaultDecoration END;
	hasErrors := TRUE;
	f := AosFS.Old(filename);
	AosOut.String("WMDecorate : "); AosOut.String(filename);
	IF f # NIL THEN 
		AosOut.String(" loaded."); AosOut.Ln;
		hasErrors := FALSE;
		NEW(scanner, f); NEW(parser, scanner); parser.reportError := ReportError; doc := parser.Parse();
		IF ~hasErrors THEN 
			NEW(desc);
			desc.style := 2;
			(* set default values for style 0 *)
			desc.baCol := 0FFFF0H; desc.biCol := 0FF80H; desc.basw := 5; desc.bisw := 5;
			desc.th := 20; desc.lw := 2; desc.rw := 2; desc.bh := 2; 
			
			root := doc.GetRoot();
			cont := root.GetContents(); cont.Reset();
			WHILE cont.HasMoreElements() DO
				p := cont.GetNext();
				IF p IS XML.Element THEN
					el := p(XML.Element);
					s := el(XML.Element).GetName(); 
					IF s^ = "Title" THEN
						(* left *)
						ts := el(XML.Element).GetAttributeValue("aleft"); 
 						IF ts = NIL THEN Error("Title left active") ELSE LoadImg(ts^, desc.taa) END; 
						
						ts := el(XML.Element).GetAttributeValue("ileft"); 
						IF ts = NIL THEN desc.tia := desc.taa ELSE LoadImg(ts^, desc.tia) END;
						
						(* middle *)
						ts := el(XML.Element).GetAttributeValue("amiddle"); 
						IF ts = NIL THEN Error("Title middle active") ELSE LoadImg(ts^, desc.tab) END; 
						
						ts := el(XML.Element).GetAttributeValue("imiddle"); 
						IF ts = NIL THEN desc.tib := desc.tab ELSE LoadImg(ts^, desc.tib) END;
						
						(* right *)
						ts := el(XML.Element).GetAttributeValue("aright"); 
						IF ts = NIL THEN Error("Title middle active") ELSE LoadImg(ts^, desc.tac) END; 
						
						ts := el(XML.Element).GetAttributeValue("iright"); 
						IF ts = NIL THEN desc.tic := desc.tac ELSE LoadImg(ts^, desc.tic) END;
						
						(* close button *)
						ts := el(XML.Element).GetAttributeValue("aclose"); IF ts # NIL THEN LoadImg(ts^, desc.ca) END;
						ts := el(XML.Element).GetAttributeValue("iclose"); IF ts # NIL THEN LoadImg(ts^, desc.ci) END;
						
						(* text *)
						ts := el(XML.Element).GetAttributeValue("atextX"); 
						IF ts = NIL THEN desc.atextX := 5 ELSE Utilities.StrToInt(ts^, desc.atextX) END;
						ts := el(XML.Element).GetAttributeValue("itextX"); 
						IF ts = NIL THEN desc.itextX := desc.atextX ELSE Utilities.StrToInt(ts^, desc.itextX) END;
						
						ts := el(XML.Element).GetAttributeValue("atextY"); 
						IF ts = NIL THEN desc.atextY := 15 ELSE Utilities.StrToInt(ts^, desc.atextY) END;
						ts := el(XML.Element).GetAttributeValue("itextY"); 
						IF ts = NIL THEN desc.itextY := desc.atextY ELSE Utilities.StrToInt(ts^, desc.itextY) END;
						
						ts := el(XML.Element).GetAttributeValue("atextColor"); 
						IF ts = NIL THEN desc.atextColor := 0FFFFFFH ELSE Utilities.HexStrToInt(ts^, desc.atextColor, res) END;
						ts := el(XML.Element).GetAttributeValue("itextColor"); 
						IF ts = NIL THEN desc.itextColor := desc.atextColor ELSE Utilities.HexStrToInt(ts^, desc.itextColor, res) END;
					END;
					IF s^ = "Left" THEN
						(* top *)
						ts := el(XML.Element).GetAttributeValue("atop"); IF ts # NIL THEN LoadImg(ts^, desc.laa) END;
						ts := el(XML.Element).GetAttributeValue("itop");  IF ts # NIL THEN LoadImg(ts^, desc.lia) END;

						(* middle *)
						ts := el(XML.Element).GetAttributeValue("amiddle"); IF ts = NIL THEN Error("Left middle active") ELSE LoadImg(ts^, desc.lab) END;
						ts := el(XML.Element).GetAttributeValue("imiddle"); IF ts # NIL THEN LoadImg(ts^, desc.lib) END;
						
						(* bottom *)
						ts := el(XML.Element).GetAttributeValue("abottom"); IF ts # NIL THEN LoadImg(ts^, desc.lac) END;
						ts := el(XML.Element).GetAttributeValue("itbottom");  IF ts # NIL THEN LoadImg(ts^, desc.lic) END;
					END;
					IF s^ = "Right" THEN
						(* top *)
						ts := el(XML.Element).GetAttributeValue("atop"); IF ts # NIL THEN LoadImg(ts^, desc.raa) END;
						ts := el(XML.Element).GetAttributeValue("itop");  IF ts # NIL THEN LoadImg(ts^, desc.ria) END;

						(* middle *)
						ts := el(XML.Element).GetAttributeValue("amiddle"); IF ts = NIL THEN Error("Right middle active") ELSE LoadImg(ts^, desc.rab) END;
						ts := el(XML.Element).GetAttributeValue("imiddle"); IF ts # NIL THEN LoadImg(ts^, desc.rib) END;
						
						(* bottom *)
						ts := el(XML.Element).GetAttributeValue("abottom"); IF ts # NIL THEN LoadImg(ts^, desc.rac) END;
						ts := el(XML.Element).GetAttributeValue("ibottom");  IF ts # NIL THEN LoadImg(ts^, desc.ric) END;
					END;
					IF s^ = "Bottom" THEN
						(* left *)
						ts := el(XML.Element).GetAttributeValue("aleft"); 
						IF ts = NIL THEN Error("Title left active") ELSE LoadImg(ts^, desc.baa) END;
						
						ts := el(XML.Element).GetAttributeValue("ileft"); 
						IF ts = NIL THEN desc.bia := desc.baa ELSE LoadImg(ts^, desc.bia) END;
						
						(* middle *)
						ts := el(XML.Element).GetAttributeValue("amiddle"); 
						IF ts = NIL THEN Error("Title middle active") ELSE LoadImg(ts^, desc.bab) END;
						
						ts := el(XML.Element).GetAttributeValue("imiddle"); 
						IF ts = NIL THEN desc.bib := desc.bab ELSE LoadImg(ts^, desc.bib) END;
						
						(* right *)
						ts := el(XML.Element).GetAttributeValue("aright"); 
						IF ts = NIL THEN Error("Title middle active") ELSE LoadImg(ts^, desc.bac) END;
						
						ts := el(XML.Element).GetAttributeValue("iright"); 
						IF ts = NIL THEN desc.bic := desc.bac ELSE LoadImg(ts^, desc.bic) END;
					ELSIF s^ = "StyleColors" THEN
						ts := el(XML.Element).GetAttributeValue("bgColor"); 
						IF ts = NIL THEN desc.bgColor := 0FFFFFFH ELSE Utilities.StrToInt(ts^, desc.bgColor) END;
						ts := el(XML.Element).GetAttributeValue("fgColor"); 
						IF ts = NIL THEN desc.fgColor := 00000FFH ELSE Utilities.StrToInt(ts^, desc.bgColor) END;
						ts := el(XML.Element).GetAttributeValue("desktopColor"); 
						IF ts = NIL THEN desc.desktopColor := 08080FFFFH ELSE Utilities.HexStrToInt(ts^, desc.desktopColor, res) END;
					ELSIF s^ = "Style" THEN
						ts := el(XML.Element).GetAttributeValue("style"); 
						IF ts = NIL THEN desc.style := 2 ELSE Utilities.StrToInt(ts^, desc.style) END;

						ts := el(XML.Element).GetAttributeValue("lw"); 
						IF ts = NIL THEN desc.lw := 2 ELSE Utilities.StrToInt(ts^, desc.lw) END;

						ts := el(XML.Element).GetAttributeValue("rw"); 
						IF ts = NIL THEN desc.rw := 2 ELSE Utilities.StrToInt(ts^, desc.rw) END;

						ts := el(XML.Element).GetAttributeValue("th"); 
						IF ts = NIL THEN desc.th := 20 ELSE Utilities.StrToInt(ts^, desc.th) END;

						ts := el(XML.Element).GetAttributeValue("bh"); 
						IF ts = NIL THEN desc.bh := 2 ELSE Utilities.StrToInt(ts^, desc.bh) END;

						ts := el(XML.Element).GetAttributeValue("baCol"); 
						IF ts = NIL THEN desc.baCol := 0FFFFH ELSE Utilities.HexStrToInt(ts^, desc.baCol, res) END;

						ts := el(XML.Element).GetAttributeValue("biCol"); 
						IF ts = NIL THEN desc.biCol := 0FF80H ELSE Utilities.HexStrToInt(ts^, desc.biCol, res) END;

						ts := el(XML.Element).GetAttributeValue("basw"); 
						IF ts = NIL THEN desc.basw := 5 ELSE Utilities.HexStrToInt(ts^, desc.basw, res) END;

						ts := el(XML.Element).GetAttributeValue("bisw"); 
						IF ts = NIL THEN desc.bisw := 5 ELSE Utilities.HexStrToInt(ts^, desc.bisw, res) END
					ELSIF s^ = "Cursors" THEN
						ReadCursors(el(XML.Element))
					END
				END
			END
		END
	ELSE
		AosOut.String(" not found."); AosOut.Ln;
	END;
	IF ~hasErrors THEN
		WM.InitializeStyle(desc);
		manager.SetStyle(desc)
	END;
	RETURN NIL
END Install;

END WMStyle.

S.Free WMStyle ~

WMStyle.Install BluePlastic.XML ~
WMStyle.Install StyleA5.XML ~
WMStyle.Install RedLook.XML ~
WMStyle.Install HugaLook.XML ~
WMStyle.Install PkLook.XML ~
WMStyle.Install Traditional.XML ~

