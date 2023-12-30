MODULE WMRestorable; (** AUTHOR "tf"; PURPOSE "Save and restore the desktop"; *)

IMPORT
	AosCommands, AosIO, AosFS, AosKernel, AosModules, AosOut, Utilities, WMMessages,
	XML, XMLObjects, XMLScanner, XMLParser,
	WM := WMWindowManager;

TYPE
	String* = Utilities.String;
	XmlElement* = XML.Element;
	
	Storage* = OBJECT
	VAR data : XML.Element;

		PROCEDURE &New;
		BEGIN
			NEW(data); data.SetName("Desktop");
		END New;

		PROCEDURE Add*(name, loader : ARRAY OF CHAR; w : WM.Window; appData : XML.Element);
		VAR window: XML.Element;
		BEGIN {EXCLUSIVE}
			NEW(window); window.SetName("Window");

			StoreString(window, "name", name);
			StoreString(window, "loader", loader);
			
			StoreLongint(window, "l", w.bounds.l);
			StoreLongint(window, "t", w.bounds.t);
			StoreLongint(window, "r", w.bounds.r);
			StoreLongint(window, "b", w.bounds.b);

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

	Context* = OBJECT
	VAR l*, t*, r*, b* : LONGINT;
		appData* : XML.Element;
	END Context;

	Loader = OBJECT
	VAR c : AosModules.CommandParProc;
		par : Context;

		PROCEDURE &New(c : AosModules.CommandParProc; par : Context);
		BEGIN
			SELF.c := c; SELF.par := par
		END New;

	BEGIN {ACTIVE}
		IF c(par) = NIL THEN END
	END Loader;

VAR hasErrors : BOOLEAN;

PROCEDURE Store*(par : ANY) : ANY; (** filename ~ *)
VAR context : Storage;
	m : WM.WindowManager;
	msg : WMMessages.Message;
	t : AosKernel.Timer;
	sr : AosIO.StringReader;
	fn : ARRAY 256 OF CHAR;
BEGIN
	AosCommands.PosPar(par, sr);
	AosCommands.GetTok(sr, fn);
	NEW(context);
	msg.ext := context; msg.msgType := WMMessages.MsgExt;
	m := WM.GetDefaultManager();
	m.Broadcast(msg);
	AosOut.String("WMRestorable: Saving desktop to "); AosOut.String(fn); AosOut.String("..."); AosOut.Ln;
	NEW(t); t.Sleep(100);
	context.Write(fn);
	NEW(t); t.Sleep(500);
	context.Write(fn);
	NEW(t); t.Sleep(1500);
	context.Write(fn);
	AosOut.String("WMRestorable: Desktop saved."); AosOut.Ln; 
	RETURN NIL
END Store;

PROCEDURE AddByContext*(w : WM.Window; c : Context; flags : SET);
VAR manager : WM.WindowManager;
BEGIN
	manager := WM.GetDefaultManager();
	w.bounds.l := c.l;
	w.bounds.t := c.t;
	w.bounds.r := c.r;
	w.bounds.b := c.b;
	manager.Add(c.l, c.t, w, flags);
END AddByContext;

(* Report errors while parsing *)
PROCEDURE Error(pos, line, row : LONGINT; msg : ARRAY OF CHAR);
BEGIN
	AosOut.String("Parse error at pos "); AosOut.Int(pos, 5); AosOut.String(" in line "); AosOut.Int(line,5);
	AosOut.String(" row "); AosOut.Int(row, 5); AosOut.String(" - "); AosOut.String(msg); AosOut.Ln;
	hasErrors := TRUE
END Error;

PROCEDURE RestoreWindow(w : XML.Element);
VAR l : Utilities.String;
	c : AosModules.CommandParProc;
	loader : Loader;
	context : Context;
	en : XMLObjects.Enumerator;
	p : ANY;
BEGIN
	l := w.GetAttributeValue("loader");
	IF l # NIL THEN
		NEW(context);
		LoadLongint(w, "l", context.l);
		LoadLongint(w, "t", context.t);
		LoadLongint(w, "r", context.r);
		LoadLongint(w, "b", context.b);
		en := w.GetContents();
		IF en.HasMoreElements() THEN
			p := en.GetNext();
			IF (p # NIL) & (p IS XML.Element) THEN context.appData := p(XML.Element) END
		END;
		c := AosModules.GetCommandByString(l^);
		IF c # NIL THEN NEW(loader, c, context) END
	END
END RestoreWindow;

PROCEDURE Load*(par : ANY) : ANY; (** filename ~ *)
VAR f : AosFS.File;
	scanner : XMLScanner.Scanner;
	parser : XMLParser.Parser;
	reader : AosFS.Reader;
	doc : XML.Document;
	content : XML.Element;
	en : XMLObjects.Enumerator;
	s : Utilities.String;
	p : ANY;
	sr : AosIO.StringReader;
	fn : ARRAY 256 OF CHAR;
BEGIN {EXCLUSIVE}
	AosCommands.PosPar(par, sr);
	AosCommands.GetTok(sr, fn);
	AosOut.String("WMRestorable: Loading desktop from "); AosOut.String(fn); AosOut.String("..."); AosOut.Ln;

	hasErrors := FALSE;
	f := AosFS.Old(fn);
	IF f # NIL THEN
		NEW(reader, f, 0);
		NEW(scanner, reader); scanner.reportError := Error;
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
	ELSE
		AosOut.String("WMRestorable: File "); AosOut.String(fn); AosOut.String(" not found."); AosOut.Ln;
	END;
	RETURN NIL
END Load;

(** Returns a XML element contained in Context.appData by its path 
	e.g. GetElement(c, "Configuration\DisplaySettings") *)
PROCEDURE GetElement*(c : Context; path : ARRAY OF CHAR) : XmlElement;
CONST 
	PathDelimiter = "\";
VAR 
	strings : Utilities.StringArray;	
	string : String;
	elem : XML.Element; 
	idx : LONGINT;
BEGIN
	IF (c # NIL) & (c.appData # NIL) THEN	
		elem := c.appData (XML.Element);
		strings := Utilities.Split(path, PathDelimiter);
		string := elem.GetName();
		IF (string # NIL) OR (string^ = strings[0]^) THEN			
			idx := 1;
			LOOP
				IF (idx >= LEN(strings)) OR (elem = NIL) THEN EXIT; END;
				elem := GetElementByName(elem, strings[idx]^);
				INC(idx);
			END;
		END;
	END;
	IF elem = NIL THEN
		AosOut.String("WMRestorable: Element "); AosOut.String(path); AosOut.String(" not found."); AosOut.Ln;
	END;
	RETURN elem;
END GetElement;

PROCEDURE LoadBoolean*(elem : XML.Element; name : ARRAY OF CHAR; VAR value : BOOLEAN);
VAR string : String;
BEGIN
	string := elem.GetAttributeValue(name);
	IF (string # NIL) THEN
		IF (string^ = "true") THEN value := TRUE; ELSE value := FALSE; END;
	ELSE
		ShowLoadError("LoadBoolean", elem, name);
	END;
END LoadBoolean;

PROCEDURE StoreBoolean*(elem : XML.Element; name : ARRAY OF CHAR; value : BOOLEAN);
VAR a : XML.Attribute; string : ARRAY 8 OF CHAR;
BEGIN
	NEW(a); a.SetName(name); 
	IF value THEN string := "true"; ELSE string := "false"; END; a.SetValue(string);
	elem.AddAttribute(a);
END StoreBoolean;

PROCEDURE LoadLongint*(elem : XML.Element; name : ARRAY OF CHAR; VAR value : LONGINT);
VAR string : String;
BEGIN
	string := elem.GetAttributeValue(name);
	IF string # NIL THEN 
		Utilities.StrToInt(string^, value); 
	ELSE
		ShowLoadError("LoadLongint", elem, name);
	END;
END LoadLongint;

PROCEDURE StoreLongint*(elem : XML.Element; name : ARRAY OF CHAR; value : LONGINT);
VAR a : XML.Attribute; string : ARRAY 32 OF CHAR;
BEGIN
	NEW(a); a.SetName(name); Utilities.IntToStr(value, string); a.SetValue(string);
	elem.AddAttribute(a);
END StoreLongint;

PROCEDURE LoadString*(elem : XML.Element; name : ARRAY OF CHAR; VAR value : ARRAY OF CHAR);
VAR string : String;
BEGIN
	value := ""; string := elem.GetAttributeValue(name);
	IF string # NIL THEN
		COPY(string^, value); 
	ELSE
		ShowLoadError("LoadString", elem, name);
	END;
END LoadString;

PROCEDURE StoreString*(elem : XML.Element; name, value : ARRAY OF CHAR);
VAR a : XML.Attribute;
BEGIN
	NEW(a); a.SetName(name); a.SetValue(value); elem.AddAttribute(a);
END StoreString;

PROCEDURE LoadStringPtr*(elem : XML.Element; name : ARRAY OF CHAR; VAR value : String);
BEGIN
	value := elem.GetAttributeValue(name);
	IF value = NIL THEN
		ShowLoadError("LoadStringPtr", elem, name);
	END;
END LoadStringPtr;

PROCEDURE StoreStringPtr*(elem : XML.Element; name : ARRAY OF CHAR;  value : String);
VAR a : XML.Attribute;
BEGIN
	NEW(a); a.SetName(name); a.SetValue(value^); elem.AddAttribute(a);
END StoreStringPtr;

PROCEDURE GetElementByName(parent : XML.Element; name : ARRAY OF CHAR) : XML.Element;
VAR elem : XML.Element; enum : XMLObjects.Enumerator; ptr : PTR; string : String;
BEGIN
	IF parent # NIL THEN
		enum := parent.GetContents(); enum.Reset();
		WHILE enum.HasMoreElements() DO
			ptr := enum.GetNext();
			IF ptr IS XML.Element THEN
				elem := ptr (XML.Element);
				string := elem.GetName();
				IF (string # NIL) & (string^ = name) THEN
					RETURN elem;
				END;
			END;
		END;						 		
 	END;
 	RETURN NIL;
END GetElementByName;

PROCEDURE ShowLoadError(procedureName : ARRAY OF CHAR; elem : XML.Element; name : ARRAY OF CHAR);
VAR string : String;
BEGIN
	AosOut.String("WMRestorable: "); AosOut.String(procedureName); 
	AosOut.String(": Attribute '"); AosOut.String(name); AosOut.String("' of element "); 
	string := elem.GetName(); IF string # NIL THEN AosOut.String(string^); ELSE AosOut.String("<no name>"); END;
	AosOut.String(" not found."); 
	AosOut.Ln;
END ShowLoadError;

END WMRestorable.

S.Free WMRestorable ~
WMRestorable.Store ~
WMRestorable.Load ~

PET.Open Auto.dsk ~	(* used to verify the behaviour of WMRestorable *)
