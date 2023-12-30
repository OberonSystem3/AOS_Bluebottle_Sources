MODULE WMFontManager;	(** AUTHOR "TF"; PURPOSE "Default implementation of a simple font manager"; *)

IMPORT
	AosOut, AosKernel, AosModules, WMGraphics, WMDefaultFont, Utilities, AosConfig, XML, XMLObjects;
	
TYPE
	String = XML.String;
	
	FontInfo* = OBJECT
	VAR
		name* : String; 
		size* : LONGINT;
		style* : SET;
	END FontInfo;
	
	LoaderInfo = POINTER TO RECORD
		loader : String;
		next : LoaderInfo;
	END; 

	FontManager = OBJECT (WMGraphics.FontManager)
	VAR
		fontCache : AosKernel.FinalizedCollection;
		defaultFont : WMGraphics.Font;
		font : WMGraphics.Font; (* set by the enumerator *)
		searchName : ARRAY 256 OF CHAR;
		searchSize : LONGINT;
		searchStyle : SET;
		found : BOOLEAN;
		exactLoaders, approximateLoaders : LoaderInfo;
		
		PROCEDURE &Init;
		VAR t : WMGraphics.Font;
		BEGIN 
			NEW(fontCache);
			GetConfig;
			defaultFont := WMDefaultFont.LoadDefaultFont(); (* fallback case *)
			t := GetFont("Oberon", 12, {});
			IF t = defaultFont THEN AosOut.String("Using embedded font"); AosOut.Ln ELSE defaultFont := t END;
			WMGraphics.InstallDefaultFont(defaultFont)
		END Init;
		
		PROCEDURE MatchExact(obj : PTR; VAR cont : BOOLEAN);
		VAR f : WMGraphics.Font;
		BEGIN
			cont := TRUE;
			IF obj IS WMGraphics.Font THEN
				f := obj(WMGraphics.Font);
				IF (f.name = searchName) & (f.size = searchSize) & (f.style = searchStyle) THEN 
					font := f; cont := FALSE; found := TRUE;
				END
			END;
		END MatchExact;
		
		PROCEDURE MatchSimiliar(obj : PTR; VAR cont : BOOLEAN);
		VAR f : WMGraphics.Font;
		BEGIN
			cont := TRUE;
			IF obj IS WMGraphics.Font THEN
				f := obj(WMGraphics.Font);
				IF (f.name = searchName) & (f.size = searchSize) THEN 
					font := f; cont := FALSE; found := TRUE;
				END
			END;
		END MatchSimiliar;
		
		PROCEDURE AddExact(str : String);
		VAR n : LoaderInfo;
		BEGIN
			IF str = NIL THEN RETURN END;
			NEW(n); n.loader := str;
			n.next := exactLoaders; exactLoaders := n
		END AddExact;
		
		PROCEDURE AddApproximate(str : String);
		VAR n : LoaderInfo;
		BEGIN
			IF str = NIL THEN RETURN END;
			NEW(n); n.loader := str;
			n.next := approximateLoaders; approximateLoaders := n
		END AddApproximate;

		PROCEDURE GetConfig;
		VAR sectWM, sectFM, e : XML.Element; 
			p : PTR; enum: XMLObjects.Enumerator; 

			PROCEDURE Error;
			BEGIN AosOut.String("WindowManager.FontManager subsection missing in AosConfig. Running on defaults"); AosOut.Ln
			END Error;
			
		BEGIN { EXCLUSIVE }
			sectWM := AosConfig.GetNamedElement(AosConfig.config.GetRoot(), "Section", "WindowManager");
			IF sectWM # NIL THEN
				sectFM := AosConfig.GetNamedElement(sectWM, "Section", "FontManager");
				IF sectFM # NIL THEN
					enum := sectFM.GetContents();
					WHILE enum.HasMoreElements() DO
						p := enum.GetNext();
						IF p IS XML.Element THEN
							e := AosConfig.GetNamedElement(p(XML.Element), "Setting", "Exact");
							IF e # NIL THEN AddExact(e.GetAttributeValue("value")) END;
							e := AosConfig.GetNamedElement(p(XML.Element), "Setting", "Approximate");
							IF e # NIL THEN AddApproximate(e.GetAttributeValue("value")) END;
						END
					END
				ELSE Error
				END
			ELSE Error
			END
		END GetConfig;
		
		PROCEDURE GetCommandByString(cmd : ARRAY OF CHAR) : AosModules.CommandParProc;
		VAR i, n, res: LONGINT; msg: ARRAY 64 OF CHAR; mod: AosModules.Module; proc: AosModules.CommandParProc;
		BEGIN
			i := 0; WHILE (cmd[i] # 0X) & (cmd[i] # ".") DO INC(i) END;
			IF cmd[i] = "." THEN
				cmd[i] := 0X;
				mod := AosModules.ThisModule(cmd, res, msg);
				IF mod # NIL THEN
					INC(i); n := i; WHILE cmd[i] # 0X DO cmd[i-n] := cmd[i]; INC(i) END;
					cmd[i-n] := 0X; 
					RETURN AosModules.ThisCommandPar(mod, cmd);
				END
			END;
			RETURN NIL
		END GetCommandByString;
		
		PROCEDURE Load(ln : String; fi : FontInfo) : WMGraphics.Font;
		VAR msg : ARRAY 128 OF CHAR; res : LONGINT; c : AosModules.CommandParProc; t : PTR;
		BEGIN
			IF ln = NIL THEN RETURN NIL END;
			c := GetCommandByString(ln^);
			IF c # NIL THEN 
				t := c(fi);
				IF (t # NIL) & (t IS WMGraphics.Font) THEN RETURN t(WMGraphics.Font)
				ELSE RETURN NIL
				END
			END;
			RETURN NIL
		END Load;
		
		PROCEDURE GetFont*(name : ARRAY OF CHAR; size : LONGINT; style : SET) : WMGraphics.Font;
		VAR tf : WMGraphics.Font; l : LoaderInfo; fi : FontInfo;
		BEGIN {EXCLUSIVE}
			font := defaultFont;
			found := FALSE;
			COPY(name, searchName); searchSize := size; searchStyle := style;
			fontCache.Enumerate(MatchExact);
			IF ~found THEN
				NEW(fi);
				fi.name := Utilities.NewString(name); 
				fi.size := size; fi.style := style;
				(* search for exact matches *)
				l := exactLoaders;
				WHILE ~found & (l # NIL) DO 
					tf := Load(l.loader, fi);
					IF tf # NIL THEN font := tf; fontCache.Add(font, NIL); found := TRUE END;
					l := l.next;
				END;
				(* search for approximate matches (not exact style) *)
				IF ~found THEN fontCache.Enumerate(MatchSimiliar) END;
				l := approximateLoaders;
				WHILE ~found & (l # NIL) DO 
					tf := Load(l.loader, fi);
					IF tf # NIL THEN font := tf; fontCache.Add(font, NIL); found := TRUE END;
					l := l.next;
				END
			END;
			RETURN font
		END GetFont;
		
	END FontManager;
VAR fm : FontManager;

PROCEDURE Install*(par : PTR) : PTR;
BEGIN
	fm.GetConfig();
	RETURN NIL
END Install;

PROCEDURE Load;
BEGIN
	NEW(fm);
	WMGraphics.InstallFontManager(fm)
END Load;

PROCEDURE Cleanup;
BEGIN
	WMGraphics.InstallFontManager(NIL)
END Cleanup;

BEGIN
	Load;
	AosModules.InstallTermHandler(Cleanup)
END WMFontManager.
