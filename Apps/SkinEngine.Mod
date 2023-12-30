MODULE SkinEngine; (** AUTHOR "FN"; PURPOSE "Infrastructure for skin support"; *)

IMPORT
	AosOut, AosFS, AosIO, XML, Objects := XMLObjects, AosCommands, Utilities, BSL := SkinLanguage, 
	AosTexts, AosCodecs, AosPipes, AosConfig, UTF8Strings, 
	WM := WMWindowManager, WMComponents, WMProperties, Messages := WMMessages, Graphics := WMGraphics;
	
TYPE
	String = Utilities.String;
	
	ReportError* = BSL.ReportError;
	
	Skin* = OBJECT
	VAR xml- : XML.Document;
		filename- : ARRAY 256 OF CHAR (* for reloading skin from file *)
	END Skin;

VAR
	manager : WM.WindowManager;
	current -: Skin;

(* ----- internal functions ----------------------------------------------*)

(*load cursor bitmaps specified by xml-tree with root el *)
PROCEDURE LoadCursors(el : XML.Element; manager : WM.WindowManager);
VAR en: Objects.Enumerator; p : ANY; x : XML.Element; s : String;
	
	PROCEDURE LoadPointerInfo(x : XML.Element; pi : WM.PointerInfo);
	VAR hotX, hotY : LONGINT; s, bitmap : String;
		en : Objects.Enumerator; a : ANY; y : XML.Element;
	BEGIN
		en := x.GetContents(); en.Reset();
		WHILE en.HasMoreElements() DO
			a := en.GetNext();
			IF a IS XML.Element THEN
				y := a(XML.Element);
				s := y.GetName();
				IF s^ = "Bitmap" THEN
					bitmap := GetCharContent(y)
				ELSIF s^ = "HotX" THEN
					s := GetCharContent(y); Utilities.StrToInt(s^, hotX)
				ELSIF s^ = "HotY" THEN
					s := GetCharContent(y); Utilities.StrToInt(s^, hotY)
				END
			END
		END;
		WM.LoadCursor(bitmap^, hotX, hotY, pi);
	END LoadPointerInfo;

BEGIN
	en:= el.GetContents(); en.Reset();
	WHILE en.HasMoreElements() DO
		p := en.GetNext();
		IF p IS XML.Element THEN
			x := p(XML.Element);
			s := x.GetName(); 
			IF s^ = "Default" THEN
				LoadPointerInfo(x, manager.pointerStandard)
			ELSIF s^ = "Move" THEN
				LoadPointerInfo(x, manager.pointerMove)
			ELSIF s^ = "Text" THEN
				LoadPointerInfo(x, manager.pointerText)
			ELSIF s^ = "Crosshair" THEN
				LoadPointerInfo(x, manager.pointerCrosshair)
			ELSIF s^ = "Upleftdownright" THEN
				LoadPointerInfo(x, manager.pointerULDR)
			ELSIF s^ = "Uprightdownleft" THEN
				LoadPointerInfo(x, manager.pointerURDL)
			ELSIF s^ = "Updown" THEN
				LoadPointerInfo(x, manager.pointerUpDown)
			ELSIF s^ = "Leftright" THEN
				LoadPointerInfo(x, manager.pointerLeftRight)
			ELSIF s^ = "Link" THEN
				LoadPointerInfo(x, manager.pointerLink)
			END
		END
	END
END LoadCursors;

(* load window-style specified by xml-tree with root el *)
PROCEDURE LoadWindow(el : XML.Element) : WM.WindowStyle;
VAR contents, en : Objects.Enumerator; p : ANY; x, y : XML.Element; 
	s, ts, ss : XML.String; desc : WM.WindowStyle; res : LONGINT;

		PROCEDURE Error(x: ARRAY OF CHAR);
		BEGIN
			AosOut.String("Style not completely defined, missing : ");	AosOut.String(x); AosOut.Ln
		END Error;
		
		PROCEDURE LoadImg(name : ARRAY OF CHAR; VAR img : Graphics.Image);
		BEGIN
			img := Graphics.LoadImage(name, TRUE)
		END LoadImg;
		
BEGIN
	NEW(desc);
	manager.InitStyle(desc);
	contents := el.GetContents(); contents.Reset();
	WHILE contents.HasMoreElements() DO
		p := contents.GetNext();
		IF p IS XML.Element THEN
			x := p(XML.Element);
			s := x.GetName();
			IF s^ = "UseBitmaps" THEN
				en := x.GetContents();
				p := en.GetNext();
				IF p IS XML.Chars THEN
					ss := p(XML.Chars).GetStr();
					IF ss # NIL THEN
						Utilities.Trim(ss^, " "); Utilities.LowerCase(ss^);
						desc.useBitmaps := (ss^ = "true");
					END
				END;
			ELSIF s^ = "Title" THEN
				en := x.GetContents(); en.Reset();
				WHILE en.HasMoreElements() DO
					p := en.GetNext();
					IF p IS XML.Element THEN
						y := p(XML.Element);
						ss := y.GetName();
						IF ss^ = "ActiveCloseBitmap" THEN
							ts := GetCharContent(y); 
							IF ts # NIL THEN LoadImg(ts^, desc.ca) END
						ELSIF ss^ = "InactiveCloseBitmap" THEN
							ts := GetCharContent(y); 
							IF ts # NIL THEN LoadImg(ts^, desc.ci) END
						ELSIF ss^ = "ActiveTopMargin" THEN
							ts := GetCharContent(y); 
							IF ts # NIL THEN Utilities.StrToInt(ts^, desc.atextY) END
						ELSIF ss^ = "InactiveTopMargin" THEN
							ts := GetCharContent(y); 
							IF ts = NIL THEN desc.itextY := desc.atextY ELSE Utilities.StrToInt(ts^, desc.itextY) END
						ELSIF ss^ = "ActiveLeftMargin" THEN
							ts := GetCharContent(y); 
							IF ts # NIL THEN Utilities.StrToInt(ts^, desc.atextX) END;
						ELSIF ss^ = "InactiveLeftMargin" THEN
							ts := GetCharContent(y); 
							IF ts = NIL THEN desc.itextY := desc.atextY ELSE Utilities.StrToInt(ts^, desc.itextX) END
						ELSIF ss^ = "ActiveColor" THEN
							ts := GetCharContent(y);
							IF ts # NIL THEN Utilities.HexStrToInt(ts^, desc.atextColor, res) END
						ELSIF ss^ = "InactiveColor" THEN
							ts := GetCharContent(y);
							IF ts = NIL THEN desc.itextColor := desc.atextColor ELSE Utilities.HexStrToInt(ts^, desc.itextColor, res) END;
						END;
					END
				END				
			ELSIF s^ = "Top" THEN
				en := x.GetContents(); en.Reset();
				WHILE en.HasMoreElements() DO
					p := en.GetNext();
					IF p IS XML.Element THEN
						y := p(XML.Element);
						ss := y.GetName();
						IF ss^ = "ActiveLeft" THEN
							ts := GetCharContent(y); IF ts = NIL THEN Error("Top left active") ELSE LoadImg(ts^, desc.taa) END
						ELSIF ss^ = "InactiveLeft" THEN
							ts := GetCharContent(y); IF ts = NIL THEN desc.tia := desc.taa ELSE LoadImg(ts^, desc.tia) END
						ELSIF ss^ = "ActiveMiddle" THEN
							ts := GetCharContent(y); IF ts = NIL THEN Error("Top middle active") ELSE LoadImg(ts^, desc.tab) END
						ELSIF ss^ = "InactiveMiddle" THEN
							ts := GetCharContent(y); IF ts = NIL THEN desc.tib := desc.tab ELSE LoadImg(ts^, desc.tib) END
						ELSIF ss^ = "ActiveRight" THEN
							ts := GetCharContent(y); IF ts = NIL THEN Error("Top right active") ELSE LoadImg(ts^, desc.tac) END
						ELSIF ss^ = "InactiveRight" THEN
							ts := GetCharContent(y); IF ts = NIL THEN desc.tic := desc.tac ELSE LoadImg(ts^, desc.tic) END
						ELSIF ss^ = "FocusThreshold" THEN
							ts := GetCharContent(y); 	IF ts # NIL THEN Utilities.StrToInt(ts^, desc.topFocusThreshold) END
						ELSIF ss^ = "Threshold" THEN
							ts := GetCharContent(y); 	IF ts # NIL THEN Utilities.StrToInt(ts^, desc.topThreshold) END
						END
					END
				END
			ELSIF s^ = "Left" THEN
				en := x.GetContents(); en.Reset();
				WHILE en.HasMoreElements() DO
					p := en.GetNext();
					IF p IS XML.Element THEN
						y := p(XML.Element);
						ss := y.GetName();
						IF ss^ = "ActiveTop" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.laa) END;
						ELSIF ss^ = "InactiveTop" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.lia) END;
						ELSIF ss^ = "ActiveMiddle" THEN
							ts := GetCharContent(y); IF ts = NIL THEN Error("Left middle active") ELSE LoadImg(ts^, desc.lab) END;
						ELSIF ss^ = "InactiveMiddle" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.lib) END;
						ELSIF ss^ = "ActiveBottom" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.lac) END;
						ELSIF ss^ = "InactiveBottom" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.lic) END;
						ELSIF ss^ = "FocusThreshold" THEN
							ts := GetCharContent(y); 	IF ts # NIL THEN Utilities.StrToInt(ts^, desc.leftFocusThreshold) END
						ELSIF ss^ = "Threshold" THEN
							ts := GetCharContent(y); 	IF ts # NIL THEN Utilities.StrToInt(ts^, desc.leftThreshold) END
						END
					END
				END
			ELSIF s^ = "Right" THEN
				en := x.GetContents(); en.Reset();
				WHILE en.HasMoreElements() DO
					p := en.GetNext();
					IF p IS XML.Element THEN
						y := p(XML.Element);
						ss := y.GetName();
						IF ss^ = "ActiveTop" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.raa) END;
						ELSIF ss^ = "InactiveTop" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.ria) END;
						ELSIF ss^ = "ActiveMiddle" THEN
							ts := GetCharContent(y); IF ts = NIL THEN Error("Right middle active") ELSE LoadImg(ts^, desc.rab) END;
						ELSIF ss^ = "InactiveMiddle" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.rib) END;
						ELSIF ss^ = "ActiveBottom" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.rac) END;
						ELSIF ss^ = "InactiveBottom" THEN
							ts := GetCharContent(y); IF ts # NIL THEN LoadImg(ts^, desc.ric) END;
						ELSIF ss^ = "FocusThreshold" THEN
							ts := GetCharContent(y); 	IF ts # NIL THEN Utilities.StrToInt(ts^, desc.rightFocusThreshold) END
						ELSIF ss^ = "Threshold" THEN
							ts := GetCharContent(y); 	IF ts # NIL THEN Utilities.StrToInt(ts^, desc.rightThreshold) END
						END
					END
				END
			ELSIF s^ = "Bottom" THEN
				en := x.GetContents(); en.Reset();
				WHILE en.HasMoreElements() DO
					p := en.GetNext();
					IF p IS XML.Element THEN
						y := p(XML.Element);
						ss := y.GetName();
						IF ss^ = "ActiveLeft" THEN
							ts := GetCharContent(y); IF ts = NIL THEN Error("Bottom left active") ELSE LoadImg(ts^, desc.baa) END;
						ELSIF ss^ = "InactiveLeft" THEN
							ts := GetCharContent(y); IF ts = NIL THEN desc.bia := desc.baa ELSE LoadImg(ts^, desc.bia) END;
						ELSIF ss^ = "ActiveMiddle" THEN
							ts := GetCharContent(y); IF ts = NIL THEN Error("Bottom middle active") ELSE LoadImg(ts^, desc.bab) END;
						ELSIF ss^ = "InactiveMiddle" THEN
							ts := GetCharContent(y); IF ts = NIL THEN desc.bib := desc.bab ELSE LoadImg(ts^, desc.bib) END;
						ELSIF ss^ = "ActiveRight" THEN
							ts := GetCharContent(y); IF ts = NIL THEN Error("Bottom right active") ELSE LoadImg(ts^, desc.bac) END;
						ELSIF ss^ = "InactiveRight" THEN
							ts := GetCharContent(y); IF ts = NIL THEN desc.bic := desc.bac ELSE LoadImg(ts^, desc.bic) END;
						ELSIF ss^ = "FocusThreshold" THEN
							ts := GetCharContent(y); 	IF ts # NIL THEN Utilities.StrToInt(ts^, desc.bottomFocusThreshold) END
						ELSIF ss^ = "Threshold" THEN
							ts := GetCharContent(y); 	IF ts # NIL THEN Utilities.StrToInt(ts^, desc.bottomThreshold) END
						END
					END
				END
			ELSIF s^ = "Desktop" THEN
				en := x.GetContents(); en.Reset();
				WHILE en.HasMoreElements() DO
					p := en.GetNext();
					IF p IS XML.Element THEN
						y := p(XML.Element);
						ss := y.GetName();
						IF ss^ = "Color" THEN
							ts := GetCharContent(y);	IF ts # NIL THEN Utilities.HexStrToInt(ts^, desc.desktopColor, res) END
						ELSIF ss^ = "FgColor" THEN
							ts := GetCharContent(y);	IF ts # NIL THEN Utilities.HexStrToInt(ts^, desc.fgColor, res) END			
						ELSIF ss^ = "BgColor" THEN
							ts := GetCharContent(y);	IF ts # NIL THEN Utilities.HexStrToInt(ts^, desc.bgColor, res) END	
						ELSIF ss^ = "SelectColor" THEN
							ts := GetCharContent(y);	IF ts # NIL THEN Utilities.HexStrToInt(ts^, desc.selectCol, res) END				
						END
					END
				END
			ELSIF s^ = "Border" THEN
				en := x.GetContents(); en.Reset();
				WHILE en.HasMoreElements() DO
					p := en.GetNext();
					IF p IS XML.Element THEN
						y := p(XML.Element);
						ss := y.GetName();
						IF ss^ = "Left" THEN
							ts := GetCharContent(y); IF ts # NIL THEN Utilities.StrToInt(ts^, desc.lw) END;
						ELSIF ss^ = "Right" THEN
							ts := GetCharContent(y); IF ts # NIL THEN Utilities.StrToInt(ts^, desc.rw) END;
						ELSIF ss^ = "Top" THEN
							ts := GetCharContent(y); IF ts # NIL THEN Utilities.StrToInt(ts^, desc.th) END;
						ELSIF ss^ = "Bottom" THEN
							ts := GetCharContent(y); IF ts # NIL THEN ELSE Utilities.StrToInt(ts^, desc.bh) END;
						ELSIF ss^ = "ActiveColor" THEN
							ts := GetCharContent(y); IF ts # NIL THEN Utilities.HexStrToInt(ts^, desc.baCol, res) END;
						ELSIF ss^ = "InactiveColor" THEN
							ts := GetCharContent(y); IF ts # NIL THEN Utilities.HexStrToInt(ts^, desc.biCol, res) END;
						ELSIF ss^ = "Active3d" THEN
							ts := GetCharContent(y); IF ts # NIL THEN Utilities.HexStrToInt(ts^, desc.basw, res) END;
						ELSIF ss^ = "Inactive3d" THEN
							ts := GetCharContent(y); IF ts # NIL THEN Utilities.HexStrToInt(ts^, desc.bisw, res) END
						END
					END
				END
			END
		END
	END;
	RETURN desc
END LoadWindow;


(* reset skin-engine i.e. install zero-skin *)
PROCEDURE SetZeroSkin;
VAR i, j : LONGINT; lists : WMComponents.ListArray;
	 properties : WMProperties.PropertyArray; msg : Messages.Message;
BEGIN
	(* components *)
	lists := WMComponents.propertyListList.Enumerate();
	i := 0;
	WHILE i < LEN(lists^) DO
		properties := lists[i].Enumerate();
		j := 0;
		WHILE j < LEN(properties^) DO
			IF properties[j].HasPrototype() THEN properties[j].Reset() END;
			INC(j)
		END;
		INC(i)
	END;
	msg.msgType := Messages.MsgExt; msg.ext := WMComponents.componentStyleMsg;
	manager.Broadcast(msg);
	(* default-window and cursors *)
	manager.ZeroSkin
END SetZeroSkin;

(* install skin specified by xml-doc *)
PROCEDURE SetXmlSkinInternal(doc : XML.Document);
VAR p : ANY; cont : Objects.Enumerator; root: XML.Element;
	el : XML.Content; s : Utilities.String; desc : WM.WindowStyle;
BEGIN
	SetZeroSkin();
	root := doc.GetRoot();
	cont := root.GetContents(); cont.Reset();
	WHILE cont.HasMoreElements() DO
		p := cont.GetNext();
		IF p IS XML.Element THEN
			el := p(XML.Element);
			s := el(XML.Element).GetName();
			LowerCase(s);
			IF s^ = "window" THEN
				(* default window frame *)
				desc := LoadWindow(el(XML.Element))
			ELSIF s^ = "cursors" THEN
				(* cursors *)
				LoadCursors(el(XML.Element), manager)
			ELSIF s^ = "components" THEN
				(* Components *)
				WMComponents.SetStyle(p(XML.Element))
			END
		END
	END;
	WM.InitializeStyle(desc);
	manager.SetStyle(desc);
END SetXmlSkinInternal;

(* ----- api --------------------------------------------------------- *)

(** make SKIN the current skin, if SKIN is NIL, zeroskin will be installed *)
PROCEDURE InstallSkin*(skin : Skin);
BEGIN
	IF skin # NIL THEN
		current := skin;
		IF skin.xml # NIL THEN
			SetXmlSkinInternal(skin.xml)
		ELSE
			SetZeroSkin()
		END
	END
END InstallSkin;

(* read skin from ascii-stream. the stream must provide a skin-definition in bsl (Bluebottle SkinLanguage) *)
PROCEDURE GetSkinFromStream(filename : ARRAY OF CHAR; r : AosIO.Reader; reportError : ReportError; warnings : BOOLEAN) : Skin;
VAR scn : BSL.Scanner; prs : BSL.Parser; skin : Skin;
BEGIN
	NEW(scn, r);
	NEW(prs, filename, scn);
	IF reportError # NIL THEN prs.reportError := reportError END;
	NEW(skin);
	skin.xml := prs.Parse(warnings);
	IF skin.xml # NIL THEN
		COPY(filename, skin.filename);
		RETURN skin
	ELSE
		RETURN NIL
	END
END GetSkinFromStream;

(** parse T and return a skin-object defined by the bsl-definition provided in T *)
PROCEDURE GetSkinFromText*(filename : ARRAY OF CHAR; t : AosTexts.Text; re : ReportError; warnings : BOOLEAN) : Skin;
VAR encoder : AosCodecs.TextEncoder; pipe : AosPipes.Pipe; w : AosIO.Writer;
	r : AosIO.Reader; res : LONGINT; 
BEGIN
	NEW(pipe, 10000);
	AosIO.OpenWriter(w, pipe.Send);
	AosIO.OpenReader(r, pipe.Receive);
	encoder := AosCodecs.GetTextEncoder("ISO8859-1");
	IF encoder = NIL THEN AosOut.String("Could not open encoder ISO8859-1"); AosOut.Ln; RETURN NIL END;
	encoder.Open(w);
	encoder.WriteText(t, res);
	RETURN GetSkinFromStream(filename, r, re, warnings)
END GetSkinFromText;

(** return a skin-object defined by the *.skin-file specified by FILENAME *)
PROCEDURE GetSkinFromFile*(filename : ARRAY OF CHAR; re : ReportError; warnings : BOOLEAN) : Skin;
VAR res : LONGINT; in : AosIO.Reader; decoder : AosCodecs.TextDecoder; skin : Skin;
	description : ARRAY 128 OF CHAR;
BEGIN
	decoder := AosCodecs.GetTextDecoder("UTF-8");
	IF decoder = NIL THEN
		AosOut.String("Could not open decoder for UTF-8."); AosOut.Ln; RETURN NIL
	END;
	COPY(filename, description); Utilities.Append(description, "://skin.bsl");
	in := AosCodecs.OpenInputStream(description);
	IF in = NIL THEN
		AosOut.String("Could not open stream on file : "); AosOut.String(description); AosOut.Ln; RETURN NIL
	END;
	decoder.Open(in, res);
	skin := GetSkinFromText(filename, decoder.GetText(), re, warnings);
	RETURN skin
END GetSkinFromFile;

(* ----- commands ---------------------------------------------------*)

(** Set the currently installed skin as default i.e. register it in the autostart-section of AosConfig.XML *)
PROCEDURE SetCurrentAsDefault*(par : ANY) : ANY;
VAR val : ARRAY 128 OF CHAR;
BEGIN
	IF current # NIL THEN
		val := "SkinEngine.Load "; Utilities.Append(val, current.filename);
		AosConfig.Put("Autostart.DefaultSkin", val);
		AosOut.String("Set "); AosOut.String(current.filename); AosOut.String(" as default."); AosOut.Ln
	ELSE (* ZeroSkin *)
		val := "SkinEngine.Unload";
		AosConfig.Put("Autostart.DefaultSkin", val);
		AosOut.String("Set ZeroSkin as default."); AosOut.Ln
	END;
	RETURN NIL
END SetCurrentAsDefault;

(** Set system to initial state (i.e. install ZeroSkin) *)
PROCEDURE Unload*(par : ANY) : ANY;
BEGIN
	IF current # NIL THEN
		SetZeroSkin(); 
		current := NIL;
	ELSE
		AosOut.String("ZeroSkin already loaded"); AosOut.Ln;
	END;
	RETURN NIL
END Unload;

(** Install the skin specified by given filename (.skin)*)
PROCEDURE Load*(a : ANY) : ANY;
VAR skinfile : AosFS.FileName; skin : Skin;
BEGIN
	skinfile := ReadName(a);
	IF (current = NIL) OR (UTF8Strings.Compare(skinfile, current.filename) # UTF8Strings.CmpEqual) THEN
		AosOut.String("SkinEngine : Loading "); AosOut.String(skinfile); AosOut.String("..."); 
		skin := GetSkinFromFile(skinfile, NIL, FALSE);
		IF skin # NIL THEN
			InstallSkin(skin);
			AosOut.String("ok"); AosOut.Ln
		END
	ELSE
		AosOut.String("Skin "); AosOut.String(skinfile); AosOut.String(" already loaded"); AosOut.Ln;
	END;
	RETURN NIL
END Load;

(* ----- helpers ----------------------------------------------------- *)

(* read a name from the command-line *)
PROCEDURE ReadName(a : ANY) : AosFS.FileName;
VAR p : AosCommands.Parameters; r : AosIO.StringReader; n : AosFS.FileName;
BEGIN
	p := a(AosCommands.Parameters);
	NEW(r, LEN(p.str)); r.Set(p.str^);
	r.Token(n); RETURN n
END ReadName;

(* convert s to lower case *)
PROCEDURE LowerCase(s : String);
VAR i : LONGINT;
BEGIN
	FOR i := 0 TO LEN(s^)-1 DO s^[i] := Utilities.LOW(s^[i]) END
END LowerCase;

(* return character-content of x's first child-node *)
PROCEDURE GetCharContent(x : XML.Element) : String;
VAR en : Objects.Enumerator; a : ANY;
BEGIN
	en := x.GetContents(); a := en.GetNext();
	IF a IS XML.Chars THEN RETURN a(XML.Chars).GetStr()
	ELSE RETURN NIL END
END GetCharContent;

BEGIN
	manager := WM.GetDefaultManager();
	current := NIL;
END SkinEngine.

S.Free SkinEngine ~


