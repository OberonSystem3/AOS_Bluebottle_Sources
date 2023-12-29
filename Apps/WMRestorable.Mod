MODULE WMRestorable; (** AUTHOR "tf"; PURPOSE "Save and restore the desktop"; *)

IMPORT
	AosKernel, AosModules, AosCommands, AosIO, AosFS, Utilities, WMMessages, WMWindowManager, 
	XML, XMLObjects, XMLScanner, XMLParser, 
	AosOut;

TYPE
	Storage* = OBJECT
	VAR data : XML.Element;

		PROCEDURE &New;
		VAR n : ARRAY 16 OF CHAR;
		BEGIN
			NEW(data); n := "Desktop"; data.SetName(n);
		END New;
		
		PROCEDURE Add*(name, loader: ARRAY OF CHAR; w : WMWindowManager.Window; appData: XML.Element);
		VAR a : XML.Attribute; n, s : ARRAY 16 OF CHAR;
			bounds : XML.Element;
			window: XML.Element;
		BEGIN {EXCLUSIVE}
			NEW(window); n := "Window"; window.SetName(n);
			NEW(a); n := "name"; a.SetName(n); a.SetValue(name); window.AddAttribute(a);
			NEW(a); n := "loader"; a.SetName(n); a.SetValue(loader); window.AddAttribute(a);

			NEW(a); n := "l"; a.SetName(n); Utilities.IntToStr(w.bounds.l, s); a.SetValue(s); window.AddAttribute(a);
			NEW(a); n := "t"; a.SetName(n); Utilities.IntToStr(w.bounds.t, s); a.SetValue(s); window.AddAttribute(a);
			NEW(a); n := "r"; a.SetName(n); Utilities.IntToStr(w.bounds.r, s); a.SetValue(s); window.AddAttribute(a);
			NEW(a); n := "b"; a.SetName(n); Utilities.IntToStr(w.bounds.b, s); a.SetValue(s); window.AddAttribute(a);

			IF appData # NIL THEN window.AddContent(appData) END;
			
			data.AddContent(window)
		END Add;

		PROCEDURE Write*(name : ARRAY OF CHAR);
		VAR f : AosFS.File; w : AosFS.Writer;
		BEGIN {EXCLUSIVE}
			f := AosFS.New(name);
			AosFS.OpenWriter(w, f, 0);
			data.Write(w, 0);
			w.Update;
			AosFS.Register(f)
		END Write;
		
	END Storage;
	
TYPE Context* = OBJECT
	VAR l*, t*, r*, b* : LONGINT;
		appData* : XML.Element;
	END Context;

TYPE Loader = OBJECT
	VAR c : AosModules.CommandParProc;
		par : Context;
	
		PROCEDURE &New(c : AosModules.CommandParProc; par : Context);
		BEGIN
			SELF.c := c; SELF.par := par 
		END New;
	BEGIN {ACTIVE}
		AosOut.String("loading"); AosOut.Ln; 
		IF c(par) = NIL THEN END
	END Loader;


VAR hasErrors : BOOLEAN;

PROCEDURE Store*(par : ANY) : ANY;
VAR context : Storage;
	m : WMWindowManager.WindowManager;
	msg : WMMessages.Message;
	n : ARRAY 16 OF CHAR;
	t : AosKernel.Timer;

	sp : AosCommands.Parameters;
	sr : AosIO.StringReader;
	name : ARRAY 256 OF CHAR;	
BEGIN 
	sp := par(AosCommands.Parameters);
	NEW(sr, LEN(sp.str^)); sr.Set(sp.str^);
	sr.String(name);
	
	NEW(context);
	msg.ext := context; msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	NEW(t); t.Sleep(100);
	context.Write(name);
	NEW(t); t.Sleep(500);
	context.Write(name);
	NEW(t); t.Sleep(1500);
	context.Write(name);
	AosOut.String("Stored"); AosOut.Ln; 
	RETURN NIL
END Store;

PROCEDURE AddByContext*(w : WMWindowManager.Window; c : Context; flags : SET);
VAR manager : WMWindowManager.WindowManager;
BEGIN
	manager := WMWindowManager.GetDefaultManager();
	w.bounds.l := c.l; 
	w.bounds.t := c.t; 
	w.bounds.r := c.r; 
	w.bounds.b := c.b; 
	manager.Add(c.l, c.t, w, flags);
END AddByContext;


(* Report errors while parsing *)
PROCEDURE Error(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	AosOut.String("Parse error at pos "); AosOut.Int(pos, 5); AosOut.String(" in line "); AosOut.Int(line, 5); 
	AosOut.String(" row "); AosOut.Int(row, 5); AosOut.String(" - "); AosOut.String(msg); AosOut.Ln;
	hasErrors := TRUE
END Error;

PROCEDURE RestoreWindow(w : XML.Element);
VAR s, l : Utilities.String;
	c : AosModules.CommandParProc;
	loader : Loader;
	context : Context;	
	en : XMLObjects.Enumerator;
	p : ANY;
BEGIN
	l := w.GetAttributeValue("loader");
	IF l # NIL THEN
		NEW(context);
		s := w.GetAttributeValue("l"); Utilities.StrToInt(s^, context.l); 
		s := w.GetAttributeValue("t"); Utilities.StrToInt(s^, context.t); 
		s := w.GetAttributeValue("r"); Utilities.StrToInt(s^, context.r); 
		s := w.GetAttributeValue("b"); Utilities.StrToInt(s^, context.b);
		en := w.GetContents(); 
		IF  en.HasMoreElements() THEN 
			p := en.GetNext();
			IF (p # NIL) & (p IS XML.Element) THEN context.appData := p(XML.Element) END
		END;
		c := AosModules.GetCommandByString(l^);
		IF c # NIL THEN NEW(loader, c, context) END
	END
END RestoreWindow;


PROCEDURE Load*(par : ANY) : ANY;
VAR f : AosFS.File;
	scanner : XMLScanner.Scanner;
	parser : XMLParser.Parser;
	doc : XML.Document;
	content : XML.Element;
	en : XMLObjects.Enumerator;
	s : Utilities.String;
	p : ANY;
	
	sp : AosCommands.Parameters;
	sr : AosIO.StringReader;
	name : ARRAY 256 OF CHAR;	
BEGIN {EXCLUSIVE}
	sp := par(AosCommands.Parameters);
	NEW(sr, LEN(sp.str^)); sr.Set(sp.str^);
	sr.String(name);
	
	hasErrors := FALSE;
	f := AosFS.Old(name);
	IF f # NIL THEN
		NEW(scanner, f); scanner.reportError := Error;
		NEW(parser, scanner); parser.reportError := Error;
		doc := parser.Parse();
		IF hasErrors THEN RETURN NIL END;
		content := doc.GetRoot();
		en := content.GetContents(); 
		WHILE en.HasMoreElements() DO
			p := en.GetNext();
			IF p IS XML.Element THEN
				s := p(XML.Element).GetName();
				IF (s # NIL) & (s^ = "Window") THEN
					RestoreWindow(p(XML.Element))
				END
			END
		END
	END;
	RETURN NIL
END Load;


END WMRestorable.

S.Free WMRestorable 
WMRestorable.Store 
WMRestorable.Load 
PET.Open test.dsk 