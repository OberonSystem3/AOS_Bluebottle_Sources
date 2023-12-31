(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosConfig; (** AUTHOR "pjm"; PURPOSE "XML-based configuration"; *)

IMPORT AosOut, Utilities, AosFS, XMLObjects, XML, XMLScanner, XMLParser;

CONST
	SaveConfigFile = "Save.AosConfig.XML";
	ConfigFile = "AosConfig.XML";
	
	(* element and attribute names - must match DTD in ConfigFile *)
	Section = "Section"; Setting = "Setting";
	NameAttr = "name"; ValueAttr = "value";

VAR
	config*: XML.Document;	(** internalized config file *)
	error : BOOLEAN;

(* In the children of element "parent", find an element with name "type" and "NameAttr" attribute "name". *)

PROCEDURE GetNamedElement*(parent: XML.Element; type, name: ARRAY OF CHAR): XML.Element;
VAR enum: XMLObjects.Enumerator; p: PTR; e: XML.Element; s: XML.String;
BEGIN
	enum := parent.GetContents();
	WHILE enum.HasMoreElements() DO
		p := enum.GetNext();
		IF p IS XML.Element THEN
			e := p(XML.Element); s := e.GetName();
			IF (s # NIL) & (s^ = type) THEN	(* correct element name *)
				s := e.GetAttributeValue(NameAttr);
				IF (s # NIL) & (s^ = name) THEN	(* correct element name attribute *)
					RETURN e
				END
			END
		END
	END;
	RETURN NIL
END GetNamedElement;

(** Find the setting specified by the key, which is a path name through the sections to the setting, and return its value.  If the setting is not found, or the value is too long for the specified parameter, return an empty string. *)

PROCEDURE Get*(key: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
VAR e: XML.Element; s: Utilities.String; a: XML.Attribute; name: ARRAY 64 OF CHAR; i, j: LONGINT;
BEGIN
	val[0] := 0X;
	IF config # NIL THEN
		i := 0; e := config.GetRoot();
		WHILE e # NIL DO
			j := 0; WHILE (key[i] # 0X) & (key[i] # ".") DO name[j] := key[i]; INC(i); INC(j) END;
			name[j] := 0X;
			(*AosOut.String("Looking for "); AosOut.String(name); AosOut.Ln;*)
			IF key[i] = 0X THEN	(* look for setting *)
				e := GetNamedElement(e, Setting, name);
				IF e # NIL THEN	(* found *)
					a := e.GetAttribute(ValueAttr);
					IF a # NIL THEN
						s := a.GetValue();
						IF (s # NIL) & (Utilities.Length(s^) < LEN(val)) THEN
							COPY(s^, val)
						END
					END;
					e := NIL	(* exit loop *)
				END
			ELSE	(* look for section *)
				INC(i);	(* skip . *)
				e := GetNamedElement(e, Section, name)
			END
		END
	END
END Get;

PROCEDURE TrapHandler(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	IF ~error THEN
		AosOut.String("Error in ");
		AosOut.String(ConfigFile);
		AosOut.String(" switching to "); AosOut.String(SaveConfigFile); AosOut.String(" !"); AosOut.Ln
	ELSE
		AosOut.String("Error in ");
		AosOut.String(SaveConfigFile); AosOut.String(" giving up!"); AosOut.Ln;
	END;	
	error := TRUE; config := NIL
END TrapHandler;

(** Internalize the config file. *)

PROCEDURE Init*(par : ANY) : ANY;
VAR f: AosFS.File; scanner: XMLScanner.Scanner; parser: XMLParser.Parser;
BEGIN {EXCLUSIVE}
	error := FALSE;
	config := NIL;
	f := AosFS.Old(ConfigFile);
	IF f # NIL THEN
		NEW(scanner, f); NEW(parser, scanner); parser.reportError := TrapHandler; config := parser.Parse();
		IF error THEN
			f := AosFS.Old(SaveConfigFile);
			IF f # NIL THEN
				NEW(scanner, f); NEW(parser, scanner); parser.reportError := TrapHandler; config := parser.Parse()
			END
		END
	END;
	RETURN NIL
END Init;

BEGIN
	IF Init(NIL) = NIL THEN END
END AosConfig.

S.Free AosConfig ~

PET.Open AosConfig.XML

