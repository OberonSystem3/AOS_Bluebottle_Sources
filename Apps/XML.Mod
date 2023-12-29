MODULE XML;	(** Stefan Walthert   *)
(** AUTHOR "swalthert"; PURPOSE "XML base"; *)
(** 2003.07.13 tf : added level parameter to write, writer no longer a VAR parameter *)
(** 2003.07.23 tf : added WriteAttributes to allow subclasses more control. Write exported to allow partial writing *)

IMPORT
	AosIO, Utilities, AosModules, DynamicStrings, Objects := XMLObjects, AosFS, AosOut;
	
CONST
	CR = DynamicStrings.CR;
	Tab = DynamicStrings.Tab;
	LF = DynamicStrings.LF;
	Space = 20X;
	
TYPE
	String* = Utilities.String;
	
	Content* = OBJECT
		VAR
			f: AosFS.File;
			pos: LONGINT;
		
		PROCEDURE SetFilePos*(f: AosFS.File; pos: LONGINT);
		BEGIN
			SELF.f := f;
			SELF.pos := pos
		END SetFilePos;
		
		PROCEDURE GetFile*(): AosFS.File;
		BEGIN
			RETURN f
		END GetFile;
		
		PROCEDURE GetPos*(): LONGINT;
		BEGIN
			RETURN pos
		END GetPos;
		
		(** write the content to stream w. level is the current hierarchy level. used for formatting *)
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
		END Write;
		
	END Content;
	
	NameContent* = OBJECT (Content)
		VAR name: String;
		
		PROCEDURE & Init();
		BEGIN
			NEW(name, 1); name[0] := 0X
		END Init;
		
		PROCEDURE GetName*(): String;
		BEGIN
			RETURN name
		END GetName;
		
		PROCEDURE SetName*(VAR name: ARRAY OF CHAR);
		BEGIN
			SELF.name := NewString(name)
		END SetName;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			w.String(name^)
		END Write;
		
	END NameContent;
	
	Container* = OBJECT (Content)
		VAR coll: Objects.Collection;
		
		PROCEDURE & Init();
		VAR arrColl: Objects.ArrayCollection;
		BEGIN
			NEW(arrColl); coll := arrColl
		END Init;
		
		PROCEDURE AddContent*(c: Content);
		BEGIN
			coll.Add(c)
		END AddContent;
		
		PROCEDURE GetContents*(): Objects.Enumerator;
		BEGIN
			RETURN coll.GetEnumerator()
		END GetContents;
		
		PROCEDURE RemoveContent*(c: Content);
		BEGIN
			coll.Remove(c)
		END RemoveContent;
		
		PROCEDURE GetNumberOfContents*(): LONGINT;
		BEGIN
			RETURN coll.GetNumberOfElements()
		END GetNumberOfContents;
	
	END Container;
	
	Document* = OBJECT (Container)
		VAR
			xmldecl: XMLDecl;
			dtd: DocTypeDecl;
			root: Element;
		
		PROCEDURE Init();
		BEGIN
			Init^();
			NEW(dtd)
		END Init;
		
		PROCEDURE GetXMLDecl*(): XMLDecl;
		BEGIN
			RETURN xmldecl
		END GetXMLDecl;
		
		PROCEDURE GetDocTypeDecl*(): DocTypeDecl;
		BEGIN
			RETURN dtd
		END GetDocTypeDecl;
		
		PROCEDURE GetRoot*(): Element;
		BEGIN
			RETURN root
		END GetRoot;
		
		PROCEDURE AddContent(c: Content);
		BEGIN
			IF (c IS XMLDecl) & (xmldecl = NIL) THEN xmldecl := c(XMLDecl)
			ELSIF (c IS DocTypeDecl) THEN dtd := c(DocTypeDecl)
			ELSIF (c IS Element) & (root = NIL) THEN root := c(Element); root.SetDocument(SELF)
			END;
			AddContent^(c)
		END AddContent;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		VAR e: Objects.Enumerator; c: PTR;
		BEGIN
			e := GetContents();
			WHILE e.HasMoreElements() DO
				c := e.GetNext();
				c(Content).Write(w, level + 1)
			END
		END Write;
		
	END Document;
	
	TextDecl* = OBJECT (Content)
		VAR version, encoding: String;
		
		PROCEDURE GetVersion*(): String;
		BEGIN
			RETURN version
		END GetVersion;
		
		PROCEDURE SetVersion*(VAR version: ARRAY OF CHAR);
		BEGIN
			SELF.version := NewString(version)
		END SetVersion;
				
		PROCEDURE GetEncoding*(): String;
		BEGIN
			RETURN encoding
		END GetEncoding;
		
		PROCEDURE SetEncoding*(VAR encoding: ARRAY OF CHAR);
		BEGIN
			SELF.encoding := NewString(encoding)
		END SetEncoding;

		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			w.String('<?xml version="'); w.String(version^);
			IF encoding # NIL THEN w.String('" encoding="'); w.String(encoding^);  w.Char('"') END;
			w.String("'?>"); NewLine(w, level)
		END Write;
		
	END TextDecl;
	
	XMLDecl* = OBJECT (TextDecl)
		VAR standalone: BOOLEAN;
		
		PROCEDURE IsStandalone*(): BOOLEAN;
		BEGIN
			RETURN standalone
		END IsStandalone;
		
		PROCEDURE SetStandalone*(standalone: BOOLEAN);
		BEGIN
			SELF.standalone := standalone
		END SetStandalone;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			w.String('<?xml version="'); w.String(version^);
			IF encoding # NIL THEN w.String('" encoding="'); w.String(encoding^);  w.Char('"') END;
			w.String(" standalone='");
			IF standalone THEN w.String("yes") ELSE w.String("no") END;
			w.String("'?>"); NewLine(w, level)
		END Write;
		
	END XMLDecl;
	
	DocTypeDecl* = OBJECT (NameContent)
		VAR
			elementDecls, notationDecls, generalEntities, parameterEntities: Objects.Dictionary;
			allMarkupDecls: Objects.Collection;
			externalSubset: EntityDecl;
		
		PROCEDURE Init();
		VAR ed: EntityDecl; arrDict: Objects.ArrayDict; arrColl: Objects.ArrayCollection;
		BEGIN
			Init^();
			NEW(arrDict); elementDecls := arrDict;
			NEW(arrDict); notationDecls := arrDict;
			NEW(arrDict); generalEntities := arrDict;
			NEW(arrDict); parameterEntities := arrDict;
			NEW(arrColl); allMarkupDecls := arrColl;
			(* add predefined entities *)
			NEW(ed); NEW(ed.name, 3); ed.name[0] := 'l'; ed.name[1] := 't'; ed.name[2] := 0X;
			NEW(ed.value, 2); ed.value[0] := '<'; ed.value[1] := 0X; ed.type := GeneralEntity; AddMarkupDecl(ed);
			NEW(ed); NEW(ed.name, 3); ed.name[0] := 'g'; ed.name[1] := 't'; ed.name[2] := 0X;
			NEW(ed.value, 2); ed.value[0] := '>'; ed.value[1] := 0X; ed.type := GeneralEntity; AddMarkupDecl(ed);
			NEW(ed); NEW(ed.name, 4); ed.name[0] := 'a'; ed.name[1] := 'm'; ed.name[2] := 'p'; ed.name[3] := 0X;
			NEW(ed.value, 2); ed.value[0] := '&'; ed.value[1] := 0X; ed.type := GeneralEntity; AddMarkupDecl(ed);
			NEW(ed); NEW(ed.name, 5); ed.name[0] := 'a'; ed.name[1] := 'p'; ed.name[2] := 'o'; ed.name[3] := 's'; ed.name[4] := 0X;
			NEW(ed.value, 2); ed.value[0] := "'"; ed.value[1] := 0X; ed.type := GeneralEntity; AddMarkupDecl(ed);
			NEW(ed); NEW(ed.name, 5); ed.name[0] := 'q'; ed.name[1] := 'u'; ed.name[2] := 'o'; ed.name[3] := 't'; ed.name[4] := 0X;
			NEW(ed.value, 2); ed.value[0] := '"'; ed.value[1] := 0X; ed.type := GeneralEntity; AddMarkupDecl(ed)
		END Init;
		
		PROCEDURE AddMarkupDecl*(c: Content);
		BEGIN
			IF c IS ElementDecl THEN
				elementDecls.Add(c(ElementDecl).name^, c); allMarkupDecls.Add(c)
			ELSIF (c IS EntityDecl) & (c(EntityDecl).type = GeneralEntity) THEN
				generalEntities.Add(c(EntityDecl).name^, c); allMarkupDecls.Add(c)
			ELSIF (c IS EntityDecl) & (c(EntityDecl).type = ParameterEntity) THEN
				parameterEntities.Add(c(EntityDecl).name^, c); allMarkupDecls.Add(c)
			ELSIF c IS NotationDecl THEN
				notationDecls.Add(c(NotationDecl).name^, c); allMarkupDecls.Add(c)
			ELSIF (c IS ProcessingInstruction) OR (c IS Comment) THEN
				allMarkupDecls.Add(c)
			END
		END AddMarkupDecl;
		
		PROCEDURE GetElementDecl*(name: ARRAY OF CHAR): ElementDecl;
		VAR p: PTR;
		BEGIN
			p := elementDecls.Get(name);
			IF p # NIL THEN RETURN p(ElementDecl)
			ELSE RETURN NIL
			END
		END GetElementDecl;
		
		PROCEDURE GetNotationDecl*(name: ARRAY OF CHAR): NotationDecl;
		VAR p: PTR;
		BEGIN
			p := elementDecls.Get(name);
			IF p # NIL THEN RETURN p(NotationDecl)
			ELSE RETURN NIL
			END
		END GetNotationDecl;
		
		PROCEDURE GetEntityDecl*(name: ARRAY OF CHAR; type: SHORTINT): EntityDecl;
		VAR p: PTR;
		BEGIN
			IF type = GeneralEntity THEN p := generalEntities.Get(name)
			ELSIF type = ParameterEntity THEN p := parameterEntities.Get(name)
			END;
			IF p # NIL THEN RETURN p(EntityDecl)
			ELSE RETURN NIL
			END
		END GetEntityDecl;
		
		PROCEDURE GetExternalSubset*(): EntityDecl;
		BEGIN
			RETURN externalSubset
		END GetExternalSubset;
		
		PROCEDURE SetExternalSubset*(externalSubset: EntityDecl);
		BEGIN
			SELF.externalSubset := externalSubset
		END SetExternalSubset;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		VAR e: Objects.Enumerator; p: PTR; s: String;
		BEGIN
			w.String("<!DOCTYPE "); w.String(name^);
			IF externalSubset # NIL THEN
				s := externalSubset.GetPublicId();
				IF s # NIL THEN
					w.String(' PUBLIC "'); w.String(s^); w.String('" "');
				ELSE
					w.String(' SYSTEM "')
				END;
				s := externalSubset.GetSystemId();
				w.String(s^); w.Char('"')
			END;
			e := allMarkupDecls.GetEnumerator();
			IF e.HasMoreElements() THEN
				w.String(" ["); NewLine(w, level);
				WHILE e.HasMoreElements() DO
					p := e.GetNext(); p(Content).Write(w, level + 1)
				END;
				w.String("] ")
			END;
			w.Char('>'); NewLine(w, level)
		END Write;
		
	END DocTypeDecl;
	
	NotationDecl* = OBJECT (NameContent)
		VAR systemId, publicId: String;
		
		PROCEDURE GetSystemId*(): String;
		BEGIN
			RETURN systemId
		END GetSystemId;
		
		PROCEDURE SetSystemId*(VAR systemId: ARRAY OF CHAR);
		BEGIN
			SELF.systemId := NewString(systemId)
		END SetSystemId;
		
		PROCEDURE GetPublicId*(): String;
		BEGIN
			RETURN publicId
		END GetPublicId;
		
		PROCEDURE SetPublicId*(VAR publicId: ARRAY OF CHAR);
		BEGIN
			SELF.publicId := NewString(publicId)
		END SetPublicId;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			w.String("<!NOTATION "); w.String(name^);
			IF publicId # NIL THEN
				w.String(' PUBLIC "'); w.String(publicId^); w.String('" "');
				IF systemId # NIL THEN w.String(systemId^); w.Char('"') END
			ELSE
				w.String(' SYSTEM "'); w.String(systemId^); w.Char('"')
			END;
			w.Char('>'); NewLine(w, level)
		END Write;
		
	END NotationDecl;
	
CONST
	(** EntityDecl.SetType *)
	GeneralEntity* = 0;
	ParameterEntity* = 1;

TYPE
	EntityDecl* = OBJECT (NotationDecl)
		VAR
			value, notationName: String;
			type: SHORTINT;
		
		PROCEDURE GetType*(): SHORTINT;
		BEGIN
			RETURN type
		END GetType;
		
		PROCEDURE SetType*(type: SHORTINT);
		BEGIN
			SELF.type := type
		END SetType;
		
		PROCEDURE GetValue*(): String;
		BEGIN
			RETURN value
		END GetValue;
		
		PROCEDURE SetValue*(VAR value: ARRAY OF CHAR);
		BEGIN
			SELF.value := NewString(value)
		END SetValue;
		
		PROCEDURE GetNotationName*(): String;
		BEGIN
			RETURN notationName
		END GetNotationName;
		
		PROCEDURE SetNotationName*(VAR notationName: ARRAY OF CHAR);
		BEGIN
			SELF.notationName := NewString(notationName)
		END SetNotationName;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			w.String("<!ENTITY ");
			IF type = ParameterEntity THEN w.String("% ") END;
			w.String(name^);
			IF value # NIL THEN
				w.String(' "'); w.String(value^); w.Char('"')
			ELSE
				IF publicId # NIL THEN
					w.String(' PUBLIC "'); w.String(publicId^); w.String('" "');
					IF systemId # NIL THEN w.String(systemId^); w.Char('"') END
				ELSE
					w.String(' SYSTEM "'); w.String(systemId^); w.Char('"')
				END;
				IF (type = GeneralEntity) & (notationName # NIL) THEN
					w.String(' NDATA '); w.String(notationName^)
				END
			END;
			w.Char('>'); NewLine(w, level)
		END Write;
		
	END EntityDecl;
	
CONST
	(** ElementDecl.SetContentType *)
	Any* = 0;	(** 'ANY' *)
	Empty* = 1;	(** 'EMPTY' *)
	ElementContent* = 2;	(** children *)
	MixedContent* = 3;	(** Mixed *)
	
TYPE	
	ElementDecl* = OBJECT (NameContent)
		VAR
			contentType: SHORTINT;
			content: CollectionCP;	(* for contentType = Mixed or contentType = Element *)
			attributeDecls: Objects.Dictionary;
		
		PROCEDURE & Init*();
		VAR arrDict: Objects.ArrayDict;
		BEGIN
			NEW(arrDict); attributeDecls := arrDict
		END Init;
		
		PROCEDURE GetContentType*(): SHORTINT;
		BEGIN
			RETURN contentType
		END GetContentType;
		
		PROCEDURE SetContentType*(contentType: SHORTINT);
		BEGIN
			SELF.contentType := contentType
		END SetContentType;
		
		PROCEDURE GetContent*(): CollectionCP;
		BEGIN
			RETURN content
		END GetContent;
		
		PROCEDURE SetContent*(lcp: CollectionCP);
		BEGIN
			content := lcp
		END SetContent;
		
		PROCEDURE GetAttributeDecl*(name: ARRAY OF CHAR): AttributeDecl;
		VAR nc: PTR;
		BEGIN
			nc := attributeDecls.Get(name);
			IF nc # NIL THEN RETURN nc (AttributeDecl) ELSE RETURN NIL END
		END GetAttributeDecl;
		
		PROCEDURE GetAttributeDecls*(): Objects.Enumerator;
		BEGIN
			RETURN attributeDecls.GetEnumerator()
		END GetAttributeDecls;
		
		PROCEDURE AddAttributeDecl*(attributeDecl: AttributeDecl);
		BEGIN
			attributeDecls.Add(attributeDecl.name^, attributeDecl)
		END AddAttributeDecl;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		VAR e: Objects.Enumerator; p: PTR;
		BEGIN
			w.String("<!ELEMENT "); w.String(name^); w.Char(Space);
			IF contentType = Empty THEN
				w.String("EMPTY")
			ELSIF contentType = Any THEN
				w.String("ANY")
			ELSIF content # NIL THEN
				content.Write(w, level + 1)
			END;
			w.Char('>'); NewLine(w, level);
			e := GetAttributeDecls();
			IF e.HasMoreElements() THEN
				w.String("<!ATTLIST "); w.String(name^); NewLine(w, level);
				WHILE e.HasMoreElements() DO
					p := e.GetNext(); p(Content).Write(w, level + 1)
				END;
				w.Char('>'); NewLine(w, level)
			END
		END Write;
		
	END ElementDecl;

CONST
	(** ContentParticle.SetOccurence *)
	ZeroOrOnce* = 0;	(** '?' *)
	ZeroOrMore* = 1;	(** '*' *)
	Once* = 2;	(** nothing *)
	OnceOrMore* = 3;	(** '+' *)

TYPE
	ContentParticle* = OBJECT (Content)
		VAR occurence: SHORTINT;
		
		PROCEDURE GetOccurence*(): SHORTINT;
		BEGIN
			RETURN occurence
		END GetOccurence;
		
		PROCEDURE SetOccurence*(occ: SHORTINT);
		BEGIN
			occurence := occ
		END SetOccurence;
		
		PROCEDURE GetOccurenceChar(): CHAR;
		BEGIN
			CASE occurence OF
			| ZeroOrOnce: RETURN '?'
			| ZeroOrMore: RETURN '*'
			| Once: RETURN 0X
			| OnceOrMore: RETURN '+'
			END
		END GetOccurenceChar;
		
	END ContentParticle;
	
	NameContentParticle* = OBJECT (ContentParticle)
		VAR name: String;
		
		PROCEDURE GetName*(): String;
		BEGIN
			RETURN name
		END GetName;
		
		PROCEDURE SetName*(VAR name: ARRAY OF CHAR);
		BEGIN
			SELF.name := NewString(name)
		END SetName;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		VAR ch: CHAR;
		BEGIN
			w.String(name^);
			ch := GetOccurenceChar(); IF ch # 0X THEN w.Char(ch) END
		END Write;
		
	END NameContentParticle;
	
CONST
	(** CollectionCP.SetType *)
	Choice* = 1;
	Sequence* = 2;
	
TYPE
	CollectionCP* = OBJECT (ContentParticle)
		VAR
			children: Objects.Collection;
			type: SHORTINT;
		
		PROCEDURE & Init();
		VAR arrColl: Objects.ArrayCollection;
		BEGIN
			NEW(arrColl); children := arrColl
		END Init;
		
		PROCEDURE GetType*(): SHORTINT;
		BEGIN
			RETURN type
		END GetType;
		
		PROCEDURE SetType*(type: SHORTINT);
		BEGIN
			SELF.type := type
		END SetType;
		
		PROCEDURE GetChildren*(): Objects.Enumerator;
		BEGIN
			RETURN children.GetEnumerator()
		END GetChildren;
		
		PROCEDURE AddChild*(cp: ContentParticle);
		BEGIN
			children.Add(cp)
		END AddChild;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		VAR e: Objects.Enumerator; ch: CHAR; p: PTR;
		BEGIN
			e := GetChildren();
			p := e.GetNext();
			w.Char('(');
			p(Content).Write(w, level + 1);
			WHILE e.HasMoreElements() DO
				p := e.GetNext();
				IF type = Choice THEN w.String(" | ")
				ELSIF type = Sequence THEN w.String(", ")
				END;
				p(Content).Write(w, level + 1)
			END;
			w.Char(')');
			ch := GetOccurenceChar(); IF ch # 0X THEN w.Char(ch) END
		END Write;
	
	END CollectionCP;

CONST
	(** AttributeDecl.SetType *)
	CData* = 0;	(** CDATA *)
	Id* = 1;	(** ID *)
	IdRef* = 2;	(** IDREF *)
	IdRefs* = 3;	(** IDREFS *)
	Entity* = 4;	(** ENTITY *)
	Entities* = 5;	(** ENTITIES *)
	NmToken* = 6;	(** NMTOKEN *)
	NmTokens* = 7;	(** NMTOKENS *)
	Notation* = 8;	(** NOTATION *)
	Enumeration* = 9;	(** Enumeration *)

TYPE
	AttributeDecl* = OBJECT (NameContent)
		VAR
			defaultValue: String;
			type: SHORTINT;
			allowedValues: Objects.Dictionary;
			required: BOOLEAN;
		
		PROCEDURE & Init();
		VAR arrDict: Objects.ArrayDict;
		BEGIN
			NEW(arrDict); allowedValues := arrDict
		END Init;
		
		PROCEDURE GetDefaultValue*(): String;
		BEGIN
			RETURN defaultValue
		END GetDefaultValue;
		
		PROCEDURE SetDefaultValue*(VAR defaultValue: ARRAY OF CHAR);
		BEGIN
			SELF.defaultValue := NewString(defaultValue)
		END SetDefaultValue;
		
		PROCEDURE GetType*(): SHORTINT;
		BEGIN
			RETURN type
		END GetType;
		
		PROCEDURE SetType*(type: SHORTINT);
		BEGIN
			SELF.type := type
		END SetType;
		
		(** Collection of NameContents *)
		PROCEDURE GetAllowedValues*(): Objects.Enumerator;
		BEGIN
			RETURN allowedValues.GetEnumerator()
		END GetAllowedValues;
		
		PROCEDURE AddAllowedValue*(VAR value: ARRAY OF CHAR);
		VAR nameContent: NameContent;
		BEGIN
			NEW(nameContent); nameContent.SetName(value);
			allowedValues.Add(value, nameContent)
		END AddAllowedValue;
		
		PROCEDURE IsRequired*(): BOOLEAN;
		BEGIN
			RETURN required
		END IsRequired;
		
		PROCEDURE SetRequired*(required: BOOLEAN);
		BEGIN
			SELF.required := required
		END SetRequired;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		VAR e: Objects.Enumerator; p: PTR;
		BEGIN
			w.String(name^); w.Char(Space);
			CASE type OF
			| CData: w.String("CDATA")
			| Id: w.String("ID")
			| IdRef: w.String("IDREF")
			| IdRefs: w.String("IDREFS")
			| Entity: w.String("ENTITY")
			| Entities: w.String("ENTITIES")
			| NmToken: w.String("NMTOKEN")
			| NmTokens: w.String("NMTOKENS")
			| Notation: w.String("NOTATION")
			| Enumeration:
			END;
			IF type # Enumeration THEN w.Char(Space) END;
			IF (type = Notation) OR (type = Enumeration) THEN
				w.Char('('); e := GetAllowedValues();
				p := e.GetNext(); p(Content).Write(w, level + 1);
				WHILE e.HasMoreElements() DO
					w.Char('|'); p := e.GetNext(); p(Content).Write(w, level + 1)
				END;
				w.String(") ")
			END;
			IF required THEN
				IF defaultValue = NIL THEN w.String('#REQUIRED')
				ELSE w.String('#FIXED "'); w.String(defaultValue^); w.String('"')
				END
			ELSE
				IF defaultValue = NIL THEN w.String('#IMPLIED')
				ELSE w.String("); w.String(defaultValue^); w.String(")
				END
			END;
			NewLine(w, level)
		END Write;
		
	END AttributeDecl;
	
TYPE
	CharReference* = OBJECT (Content)
		VAR code: LONGINT;
		
		PROCEDURE SetCode*(code: LONGINT);
		BEGIN
			SELF.code := code
		END SetCode;
		
		PROCEDURE GetCode*(): LONGINT;
		BEGIN
			RETURN code
		END GetCode;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		VAR codeArray: ARRAY 16 OF CHAR; codeStr: String;
		BEGIN
			DynamicStrings.IntToStr(code, codeArray);
			codeStr := NewString(codeArray);
			w.String('&#'); w.String(codeStr^); w.Char(';')
		END Write;
	
	END CharReference;
	
TYPE
	EntityRef* = OBJECT (NameContent)
		VAR
			decl: EntityDecl;
		
		PROCEDURE GetEntityDecl*(): EntityDecl;
		BEGIN
			RETURN decl
		END GetEntityDecl;
		
		PROCEDURE SetDocument(document: Document);
		VAR dtd: DocTypeDecl;
		BEGIN
			dtd := document.GetDocTypeDecl();
			IF dtd # NIL THEN	
				decl := dtd.GetEntityDecl(name^, GeneralEntity)
			END
		END SetDocument;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			w.Char('&'); w.String(name^); w.Char(';')
		END Write;
	
	END EntityRef;

TYPE	
	InternalEntityRef* = OBJECT (EntityRef)
		
		PROCEDURE GetValue*(): String;
		BEGIN
			IF decl # NIL THEN RETURN decl.value
			ELSE RETURN NIL
			END
		END GetValue;
		
	END InternalEntityRef;

TYPE	
	ExternalEntityRef* = OBJECT (EntityRef)
		VAR
			coll: Objects.Collection;
			textDecl: TextDecl;
		
		PROCEDURE GetTextDecl*(): TextDecl;
		BEGIN
			RETURN textDecl
		END GetTextDecl;
		
		PROCEDURE GetContents*(): Objects.Enumerator;
		BEGIN
			IF IsParsed() THEN RETURN coll.GetEnumerator()
			ELSE RETURN NIL
			END
		END GetContents;
		
		PROCEDURE AddContent*(c: Content);
		VAR arrColl: Objects.ArrayCollection;
		BEGIN
			IF coll = NIL THEN NEW(arrColl); coll := arrColl END;
			IF c IS TextDecl THEN
				textDecl := c(TextDecl)
			END;
			coll.Add(c)
		END AddContent;
		
		PROCEDURE IsParsed*(): BOOLEAN;
		BEGIN
			RETURN coll # NIL
		END IsParsed;
		
		PROCEDURE GetIdElement(name, id: ARRAY OF CHAR): Element;
		VAR contents: Objects.Enumerator; p: PTR; retElement: Element;
		BEGIN
			IF IsParsed() THEN
				contents := GetContents();
				WHILE contents.HasMoreElements() & (retElement = NIL) DO
					p := contents.GetNext();
					IF p IS Element THEN
						retElement := p(Element).GetIdElement(name, id)
					ELSIF p IS ExternalEntityRef THEN
						retElement := p(ExternalEntityRef).GetIdElement(name, id)
					END
				END
			END;
			RETURN retElement
		END GetIdElement;
		
	END ExternalEntityRef;
	
TYPE
	Chars* = OBJECT (Content)
		
		PROCEDURE GetStr*(): String;
		BEGIN
		END GetStr;
		
		PROCEDURE GetLength*(): LONGINT;
		BEGIN
			RETURN 0
		END GetLength;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		VAR s: String;
		BEGIN
			s := GetStr(); w.String(s^)
		END Write;
		
	END Chars;
	
TYPE
	ArrayChars* = OBJECT (Chars)
		VAR
			str: String;
			len: LONGINT;
		
		PROCEDURE GetStr(): String;
		BEGIN
			RETURN str
		END GetStr;
		
		PROCEDURE GetLength(): LONGINT;
		BEGIN
			RETURN len
		END GetLength;
		
		PROCEDURE SetStr*(VAR str: ARRAY OF CHAR);
		BEGIN
			SELF.str := NewString(str);
			len := DynamicStrings.StringLength(str)
		END SetStr;
		
	END ArrayChars;
	
	Comment* = OBJECT (ArrayChars)
	
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			w.String("<!--"); Write^(w, level); w.String("-->"); NewLine(w, level)
		END Write;
	
	END Comment;

TYPE	
	CDataSect* = OBJECT (ArrayChars)
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			w.String("<![CDATA["); Write^(w, level + 1); w.String("]]>"); NewLine(w, level)
		END Write;
	
	END CDataSect;

TYPE	
	CharData* = OBJECT (Chars)
		VAR len: LONGINT;
		
		PROCEDURE GetLength(): LONGINT;
		BEGIN
			RETURN len
		END GetLength;
		
		PROCEDURE SetLen*(len: LONGINT);
		BEGIN
			SELF.len := len
		END SetLen;
		
		PROCEDURE GetStr(): String;
		VAR r: AosFS.Reader; s: String; p: LONGINT;
		BEGIN
			IF f # NIL THEN
				NEW(s, len + 1);
				p := 0;
				AosFS.OpenReader(r, f, pos);
				WHILE (r.res = AosIO.Ok) & (p < len) DO
					s[p] := r.Get(); INC(p)
				END;
				s[p] := 0X
			END;
			RETURN s
		END GetStr;
		
	END CharData;

TYPE	
	ProcessingInstruction* = OBJECT (Content)
		VAR target, instruction: String;
		
		PROCEDURE GetTarget*(): String;
		BEGIN
			RETURN target
		END GetTarget;
		
		PROCEDURE SetTarget*(VAR target: ARRAY OF CHAR);
		BEGIN
			SELF.target := NewString(target)
		END SetTarget;
		
		PROCEDURE GetInstruction*(): String;
		BEGIN
			RETURN instruction
		END GetInstruction;
		
		PROCEDURE SetInstruction*(VAR instruction: ARRAY OF CHAR);
		BEGIN
			SELF.instruction := NewString(instruction)
		END SetInstruction;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			w.String("<?"); w.String(target^); w.Char(Space);
			w.String(instruction^); w.String("?>"); NewLine(w, level)
		END Write;
		
	END ProcessingInstruction;

TYPE
	Attribute* = OBJECT (NameContent)
		VAR
			value, elementName: String;
			document: Document;
			decl: AttributeDecl;
		
		PROCEDURE SetDocument(document: Document; elementName: String);
		VAR dtd: DocTypeDecl; elementDecl: ElementDecl;
		BEGIN
			SELF.document := document;
			SELF.elementName := elementName;
			dtd := document.GetDocTypeDecl();
			IF dtd # NIL THEN
				elementDecl := dtd.GetElementDecl(elementName^);
				IF elementDecl # NIL THEN
					decl := elementDecl.GetAttributeDecl(name^);
					IF (decl # NIL) & ((value = NIL) OR ~IsAllowedValue(value^)) THEN
						value := decl.defaultValue
					END
				END
			END
		END SetDocument;
			
		PROCEDURE IsAllowedValue*(VAR value: ARRAY OF CHAR): BOOLEAN;
		BEGIN
			IF decl = NIL THEN
				RETURN TRUE
			ELSE
				CASE decl.GetType() OF
				| CData: RETURN TRUE
				| Id: RETURN document.root.GetIdElement(elementName^, value) = NIL
				| IdRef: RETURN TRUE
				| IdRefs: RETURN TRUE
				| Entity: RETURN TRUE
				| Entities: RETURN TRUE
				| NmToken: RETURN TRUE
				| NmTokens: RETURN TRUE
				| Notation:
					RETURN decl.allowedValues.Get(value) # NIL
				| Enumeration:
					RETURN decl.allowedValues.Get(value) # NIL
				ELSE
				END
			END
		END IsAllowedValue;
		
		PROCEDURE GetValue*(): String;
		BEGIN
			RETURN value
		END GetValue;
		
		PROCEDURE SetValue*(VAR value: ARRAY OF CHAR);
		BEGIN
			IF IsAllowedValue(value) THEN
				SELF.value := NewString(value)
			END
		END SetValue;
		
		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		BEGIN
			IF value = NIL THEN AosOut.String("NIL attribute "); AosOut.Ln; RETURN END;
			w.Char(Space); w.String(name^); w.String('="'); w.String(value^); w.Char('"')
		END Write;
		
	END Attribute;
	
	TraverseProc* = PROCEDURE (c: Content; data: PTR);
TYPE	
	Element* = OBJECT (Container)
		VAR
			root, parent, sibling, lastChild: Element;
			name: String;
			document: Document;
			attributes: Objects.Dictionary;
			idAttribute: Attribute;
		
		PROCEDURE Init();
		VAR arrDict: Objects.ArrayDict;
		BEGIN
			Init^();
			NEW(name, 1); name[0] := 0X;
			NEW(arrDict); attributes := arrDict
		END Init;
		
		PROCEDURE AddContent(c: Content);
		BEGIN
			IF c = NIL THEN RETURN END;
			IF c IS Element THEN
				WITH c: Element DO
					IF root # NIL THEN c.root := root ELSE c.root := SELF END;
					c.parent := SELF;
					IF lastChild # NIL THEN lastChild.sibling := c END;
					lastChild := c
				END
			END;
			AddContent^(c)
		END AddContent;
		
		PROCEDURE SetDocument(document: Document);
		VAR dtd: DocTypeDecl; elementDecl: ElementDecl;
			enum: Objects.Enumerator; p: PTR; attribute: Attribute;
		BEGIN
			SELF.document := document;
			root := document.GetRoot();
			dtd := document.GetDocTypeDecl();
			IF dtd # NIL THEN
				elementDecl := dtd.GetElementDecl(name^);
				IF elementDecl # NIL THEN
					enum := elementDecl.GetAttributeDecls();
					WHILE enum.HasMoreElements() DO
						p := enum.GetNext();
						WITH p: AttributeDecl DO
							attribute := GetAttribute(p.name^);
							IF attribute # NIL THEN
								attribute.SetDocument(document, name);
							ELSE
								NEW(attribute);
								attribute.name := p.name;
								attribute.value := p.defaultValue;
								attribute.SetDocument(document, name);
								attributes.Add(attribute.name^, attribute)
							END;
							IF p.type = Id THEN idAttribute := attribute END
						END
					END
				END
			END;
			enum := GetContents();
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS Element THEN p(Element).SetDocument(document)
				ELSIF p IS EntityRef THEN p(EntityRef).SetDocument(document)
				END
			END
		END SetDocument;
		
		PROCEDURE SetName*(name: ARRAY OF CHAR);
		BEGIN
			SELF.name := NewString(name)
		END SetName;
		
		PROCEDURE SetNameAsString*(name : String);
		BEGIN
			SELF.name := name
		END SetNameAsString;
		
		PROCEDURE GetName*(): String;
		BEGIN
			RETURN name
		END GetName;
		
		PROCEDURE GetId*(): String;
		BEGIN
			IF idAttribute # NIL THEN RETURN idAttribute.value
			ELSE RETURN NIL
			END
		END GetId;
		
		PROCEDURE GetIdElement*(name, id: ARRAY OF CHAR): Element;
		VAR contents: Objects.Enumerator; content: PTR; idString: String; retElement: Element;
		BEGIN
			IF SELF.name^ = name THEN
				idString := GetId();
				IF (idString # NIL) & (idString^ = id) THEN retElement := SELF END
			END;
			IF retElement = NIL THEN
				contents := GetContents();
				WHILE contents.HasMoreElements() & (retElement = NIL) DO
					content := contents.GetNext();
					IF content IS Element THEN
						retElement := content(Element).GetIdElement(name, id)
					ELSIF content IS ExternalEntityRef THEN
						retElement := content(ExternalEntityRef).GetIdElement(name, id)
					END
				END
			END;
			RETURN retElement
		END GetIdElement;
		
		PROCEDURE AddAttribute*(attribute: Attribute);
		BEGIN
			attributes.Remove(attribute.name^);
			attributes.Add(attribute.name^, attribute)
		END AddAttribute;
		
		PROCEDURE SetAttributeValue*(name, value: ARRAY OF CHAR);
		VAR attribute: Attribute;
		BEGIN
			NEW(attribute); attribute.SetName(name); attribute.SetValue(value); AddAttribute(attribute)
		END SetAttributeValue;
		
		PROCEDURE GetAttribute*(name: ARRAY OF CHAR): Attribute;
		VAR p: PTR;
		BEGIN
			p := attributes.Get(name);
			IF p # NIL THEN RETURN p(Attribute) ELSE RETURN NIL END
		END GetAttribute;
		
		PROCEDURE GetAttributeValue*(name: ARRAY OF CHAR): String;
		VAR attr: PTR;
		BEGIN
			attr := attributes.Get(name);
			IF attr # NIL THEN RETURN attr(Attribute).GetValue()
			ELSE RETURN NIL
			END
		END GetAttributeValue;
		
		PROCEDURE GetAttributes*(): Objects.Enumerator;
		BEGIN
			RETURN attributes.GetEnumerator()
		END GetAttributes;
		
		PROCEDURE RemoveAttribute*(name: ARRAY OF CHAR);
		BEGIN
			attributes.Remove(name)
		END RemoveAttribute;
		
		PROCEDURE GetRoot*(): Element;
		BEGIN
			RETURN root
		END GetRoot;
		
		PROCEDURE GetParent*(): Element;
		BEGIN
			RETURN parent
		END GetParent;
		
		PROCEDURE GetSibling*(): Element;
		BEGIN
			RETURN sibling
		END GetSibling;
		
		PROCEDURE Traverse*(traverseProc: TraverseProc; data: PTR);
		VAR contents: Objects.Enumerator; content: PTR;
		BEGIN
			traverseProc(SELF, data);
			contents := GetContents();
			WHILE contents.HasMoreElements() DO
				content := contents.GetNext();
				IF content IS Element THEN content(Element).Traverse(traverseProc, data)
				ELSE traverseProc(content(Content), data)
				END
			END
		END Traverse;
		
		PROCEDURE WriteAttributes*(w: AosIO.Writer; level : LONGINT);
		VAR e: Objects.Enumerator; c: PTR;
		BEGIN
			e := GetAttributes();
			WHILE e.HasMoreElements() DO	(* write attributes *)
				c := e.GetNext();
				c(Attribute).Write(w, level + 1)
			END;
		END WriteAttributes;

		PROCEDURE Write*(w: AosIO.Writer; level : LONGINT);
		VAR e: Objects.Enumerator; c: PTR;
		BEGIN
			w.Char('<'); IF name = NIL THEN w.String("_NILNAME_") ELSE w.String(name^) END;
			WriteAttributes(w, level);
			e := GetContents();
			IF ~e.HasMoreElements() THEN w.String("/>")
			ELSE
				w.Char('>');
				c := e.GetNext(); (* we know there is a next element at this position *)
				IF ~((c IS ArrayChars) OR (c IS CharData)) THEN NewLine(w, level + 1) END;
				c(Content).Write(w, level + 1);
				WHILE e.HasMoreElements() DO c := e.GetNext(); NewLine(w, level + 1); c(Content).Write(w, level + 1) END;
				IF ~((c IS ArrayChars) OR (c IS CharData)) THEN NewLine(w, level) END;
				w.String("</"); IF name = NIL THEN w.String("_NILNAME_") ELSE w.String(name^) END; w.Char('>')
			END;
	(*		NewLine(w, level) *)
		END Write;

	END Element;
	
	ElementEntry = OBJECT
		VAR generator: AosModules.CommandParProc;
		generatorName : AosModules.Name;
	END ElementEntry;
	
TYPE
	ElementRegistry* = OBJECT
		VAR
			generators: Objects.Dictionary;
			
		PROCEDURE & Init();
		VAR arrDict: Objects.ArrayDict;
		BEGIN
			NEW(arrDict); generators := arrDict
		END Init;
			
		PROCEDURE RegisterElement*(name: ARRAY OF CHAR; generator: AosModules.CommandParProc);
		VAR e: ElementEntry; p: PTR;
		BEGIN
			IF generator # Unassigned THEN
				p := generators.Get(name);
				IF p = NIL THEN
					NEW(e); e.generator := generator; generators.Add(name, e)
				ELSE p(ElementEntry).generator := generator (* redefinition *)
				END
			END
		END RegisterElement;
		
		PROCEDURE RegisterElementByName*(name: ARRAY OF CHAR; generatorName: AosModules.Name);
		VAR e: ElementEntry; p: PTR;
		BEGIN
			IF generatorName # "" THEN
				p := generators.Get(name);
				IF p = NIL THEN
					NEW(e); e.generatorName := generatorName; generators.Add(name, e)
				ELSE p(ElementEntry).generatorName := generatorName (* redefinition *)
				END
			END
		END RegisterElementByName;
		
		PROCEDURE UnregisterElement*(name: ARRAY OF CHAR);
		BEGIN
			generators.Remove(name)
		END UnregisterElement;
		
		PROCEDURE InstantiateElement*(name: ARRAY OF CHAR): Element;
		VAR p: PTR; gen : AosModules.CommandParProc;
		BEGIN
			p := generators.Get(name);
			IF p # NIL THEN
				IF p(ElementEntry).generator # NIL THEN
					p := p(ElementEntry).generator(NIL);
					IF (p # NIL) & (p IS Element) THEN RETURN p(Element) END
				ELSE	
					gen := AosModules.GetCommandByString(p(ElementEntry).generatorName);
					IF gen # NIL THEN
						p := gen(NIL);
						IF (p # NIL) & (p IS Element) THEN RETURN p(Element) END
					END	
				END	
			END;
			RETURN NIL
		END InstantiateElement;
		
	END ElementRegistry;
	
VAR
	defaultRegistry-: ElementRegistry;
	Unassigned: AosModules.CommandParProc;

PROCEDURE NewLine(w : AosIO.Writer; level : LONGINT);
BEGIN
	w.Ln; WHILE level > 0 DO w.Char(Tab); DEC(level) END
END NewLine;

PROCEDURE NewString(VAR value: ARRAY OF CHAR): String;
VAR s: String;
BEGIN
	NEW(s, DynamicStrings.StringLength(value) + 1);
	COPY(value, s^);
	RETURN s
END NewString;
	
BEGIN
	NEW(defaultRegistry)
END XML.