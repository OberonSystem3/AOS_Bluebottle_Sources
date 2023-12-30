MODULE XMLTransformer;	(** AUTHOR "Simon L. Keel"; PURPOSE "transforming XML to BB-text"; *)

IMPORT
	WMMessages, Utilities, XML, XMLObjects, AosOut, WMComponents, WebBrowserComponents, AosCommands, AosIO, AosFS, AosModules;

TYPE
	String = Utilities.String;
	
	XMLPluginProcInfo = POINTER TO RECORD
		name, procedure : ARRAY 128 OF CHAR;
		next : XMLPluginProcInfo;
	END;

VAR
	xmlPluginProcs : XMLPluginProcInfo;


PROCEDURE Transform*(elem : XML.Element) : XML.Container;
VAR
	container : XML.Container;
	s, name : String;
	p : AosModules.CommandParProc;
	ptr : ANY;
BEGIN
	s := elem.GetName();
	name := Utilities.UpperCaseInNew(s^);
	p := FindProcedure(name^);
	IF p # NIL THEN
		ptr := p(elem);
		RETURN ptr(XML.Container);
	ELSE
		NEW(container);
		RETURN container;
	END;
END Transform;

PROCEDURE AddContentsOf*(source, target : XML.Container);
VAR
	enum: XMLObjects.Enumerator;
	p : PTR;
BEGIN
	enum := source.GetContents();
	WHILE (enum.HasMoreElements()) DO
		p := enum.GetNext();
		target.AddContent(p(XML.Content));
	END;
END AddContentsOf;

PROCEDURE TransformElemsIn*(container : XML.Container) : XML.Container;
VAR
	c : XML.Container;
	enum: XMLObjects.Enumerator;
	p : PTR;
BEGIN
	NEW(c);
	enum := container.GetContents();
	WHILE (enum.HasMoreElements()) DO
		p := enum.GetNext();
		IF p IS XML.Element THEN
			AddContentsOf(Transform(p(XML.Element)), c);
		END;
	END;
	RETURN c;
END TransformElemsIn;

PROCEDURE GetNewParagraph*(style : ARRAY OF CHAR) : XML.Element;
VAR
	paragraph : XML.Element;
	styleAttrPar : XML.Attribute;
	s : String;
BEGIN
	NEW(paragraph); paragraph.SetName("Paragraph");
	NEW(styleAttrPar); s := Utilities.NewString("style"); styleAttrPar.SetName(s^);
	styleAttrPar.SetValue(style);
	paragraph.AddAttribute(styleAttrPar);
	RETURN paragraph;
END GetNewParagraph;

PROCEDURE GetNewSpan*(style : ARRAY OF CHAR) : XML.Element;
VAR
	span : XML.Element;
	styleAttrPar : XML.Attribute;
	s : String;
BEGIN
	NEW(span); span.SetName("Span");
	NEW(styleAttrPar); s := Utilities.NewString("style"); styleAttrPar.SetName(s^);
	styleAttrPar.SetValue(style);
	span.AddAttribute(styleAttrPar);
	RETURN span;
END GetNewSpan;

PROCEDURE FindProcedure(name : ARRAY OF CHAR) : AosModules.CommandParProc;
VAR cur : XMLPluginProcInfo;
BEGIN {EXCLUSIVE}
	Utilities.Delete(name, 0, 3);
	cur := xmlPluginProcs;
	WHILE cur # NIL DO
		IF cur.name = name THEN
			RETURN AosModules.GetCommandByString(cur.procedure) 
		END;
		cur := cur.next
	END;
	RETURN NIL
END FindProcedure;

PROCEDURE Register*(par : ANY): ANY;
VAR s: AosCommands.Parameters;
	sr : AosIO.StringReader;
	c : XMLPluginProcInfo;
BEGIN {EXCLUSIVE}
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	NEW(c);
	sr.String(c.name); sr.SkipWhitespace(); sr.String(c.procedure);
	c.next := xmlPluginProcs; xmlPluginProcs := c;
	StoreXMLPlugins;
	RETURN NIL
END Register;

PROCEDURE StoreXMLPlugins;
VAR f : AosFS.File;
	w : AosFS.Writer;
	cur : XMLPluginProcInfo;
	res : LONGINT;
	n0, n1 : ARRAY 64 OF CHAR;
BEGIN
	n0 := "XMLPluginConfig.dat"; n1 := "XMLPluginConfig.dat.Bak";
	AosFS.Rename(n0, n1, res);
	f := AosFS.New("XMLPluginConfig.dat");
	AosFS.OpenWriter(w, f, 0);
	AosFS.Register(f);
	cur := xmlPluginProcs;
	WHILE cur # NIL DO
		w.Char('"'); w.String(cur.name); w.Char('"'); w.Char(09X);
		w.Char('"'); w.String(cur.procedure); w.Char('"'); w.Ln;
 		cur := cur.next
	END;
	w.Update
END StoreXMLPlugins;

PROCEDURE LoadXMLPlugins;
VAR f : AosFS.File;
	r : AosFS.Reader;
	c : XMLPluginProcInfo;
BEGIN 
	f := AosFS.Old("XMLPluginConfig.dat");
	IF f # NIL THEN
		AosFS.OpenReader(r, f, 0);
		WHILE r.res = 0 DO 
			NEW(c);
			r.String(c.name); r.SkipWhitespace;
			r.String(c.procedure);
			IF r.res = 0 THEN c.next := xmlPluginProcs; xmlPluginProcs:= c END;
			r.SkipLn
		END
	END
END LoadXMLPlugins;

BEGIN
	LoadXMLPlugins;
END XMLTransformer.