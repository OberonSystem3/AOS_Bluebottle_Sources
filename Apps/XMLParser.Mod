MODULE XMLParser;	(** Stefan Walthert   *)
(** AUTHOR "swalthert"; PURPOSE "XML parser"; *)

IMPORT
	Utilities, AosOut, DynamicStrings, AosIO, AosFS, Scanner := XMLScanner, XML;

TYPE
	String = Utilities.String;
	
	Parser* = OBJECT
		VAR
			scanner: Scanner.Scanner;
			dtd: XML.DocTypeDecl;
			elemReg*: XML.ElementRegistry;
			reportError*: PROCEDURE (pos, line, row: LONGINT; msg: ARRAY OF CHAR);
		
		PROCEDURE &Init(s: Scanner.Scanner);
		BEGIN
			reportError := DefaultReportError;
			scanner := s
		END Init;
		
		PROCEDURE Error(msg: ARRAY OF CHAR);
		BEGIN
			reportError(scanner.GetPos(), scanner.line, scanner.row, msg)
		END Error;
		
		PROCEDURE CheckSymbol(expectedSymbols: SET; errormsg: ARRAY OF CHAR): BOOLEAN;
		BEGIN
			IF ~(scanner.sym IN expectedSymbols) THEN
				Error(errormsg); RETURN FALSE
			ELSE
				RETURN TRUE
			END
		END CheckSymbol;
		
		PROCEDURE ExpandCharacterRef(num: LONGINT): CHAR;
		BEGIN
			RETURN CHR(SHORT(SHORT(num)))
		END ExpandCharacterRef;
		
		PROCEDURE ExpandEntityRef(name: ARRAY OF CHAR; type: SHORTINT): String;
		VAR generalEntity: XML.EntityDecl;
		BEGIN
			IF dtd # NIL THEN
				generalEntity := dtd.GetEntityDecl(name, type);
				IF generalEntity # NIL THEN
					RETURN generalEntity.GetValue()
				ELSE
					RETURN NIL
				END
			ELSE
				RETURN NIL
			END
		END ExpandEntityRef;
		
		PROCEDURE Parse*(): XML.Document;
		VAR doc: XML.Document; e : XML.Element; s: String;
		BEGIN
			NEW(doc); dtd := doc.GetDocTypeDecl(); doc.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			scanner.ScanContent();	(* prolog *)
			IF scanner.sym = Scanner.TagXMLDeclOpen THEN	(* XMLDecl? *)
				doc.AddContent(ParseXMLDecl());
				scanner.ScanContent()
			END;
			WHILE (scanner.sym # Scanner.TagDeclOpen) & (scanner.sym # Scanner.TagElemStartOpen) DO	(* Misc* *)
				CASE scanner.sym OF
				| Scanner.TagPIOpen: doc.AddContent(ParseProcessingInstruction())
				| Scanner.Comment: doc.AddContent(ParseComment())
				ELSE 
					Error("unknown XML content (Document Type Declaration, Processing Instruction, Comment or Root Element expected)");
					RETURN doc
				END;
				scanner.ScanContent()
			END;
			IF scanner.sym = Scanner.TagDeclOpen THEN	(* (doctypedecl Misc* )? *)
				s := scanner.GetStr();				(* doctypedecl .. *)
				IF s^ = 'DOCTYPE' THEN
					ParseDocTypeDecl(); doc.AddContent(dtd)
				ELSE
					Error("'<!DOCTYPE' expected"); RETURN doc
				END;
				scanner.ScanContent();
				WHILE (scanner.sym # Scanner.TagElemStartOpen) DO	(* .. Misc* *)
					CASE scanner.sym OF
					| Scanner.TagPIOpen: doc.AddContent(ParseProcessingInstruction())
					| Scanner.Comment: doc.AddContent(ParseComment())
					| Scanner.TagElemStartOpen: (* do nothing *)
					ELSE Error("unknown XML content (Processing Instruction, Comment or Root Element expected)"); RETURN doc
					END;
					scanner.ScanContent()
				END
			END;
			e := ParseElement();
			IF e = NIL THEN RETURN NIL END;
			doc.AddContent(e);	(* element *)
			scanner.ScanContent();
			WHILE scanner.sym # Scanner.Eof DO	(* Misc* *)
				CASE scanner.sym OF
				| Scanner.TagPIOpen: doc.AddContent(ParseProcessingInstruction())
				| Scanner.Comment: doc.AddContent(ParseComment())
				| Scanner.Eof: (* do nothing *)
				ELSE Error("unknown XML content (Processing Instruction, Comment or End of file expected)"); RETURN doc
				END;
				scanner.ScanContent()
			END;
			RETURN doc
		END Parse;
		
		PROCEDURE ParseExtGenEntity*(extEntityRef: XML.ExternalEntityRef);
		BEGIN
			scanner.ScanContent();
			IF scanner.sym = Scanner.TagXMLDeclOpen THEN
				extEntityRef.AddContent(ParseTextDecl());
				scanner.ScanContent()
			END;
			REPEAT
				CASE scanner.sym OF
				| Scanner.CharData: extEntityRef.AddContent(ParseCharData())
				| Scanner.TagElemStartOpen: extEntityRef.AddContent(ParseElement())
				| Scanner.CharRef: extEntityRef.AddContent(ParseCharRef())
				| Scanner.EntityRef: extEntityRef.AddContent(ParseEntityRef())
				| Scanner.CDataSect: extEntityRef.AddContent(ParseCDataSect())
				| Scanner.Comment: extEntityRef.AddContent(ParseComment())
				| Scanner.TagPIOpen: extEntityRef.AddContent(ParseProcessingInstruction())
				| Scanner.TagElemEndOpen: (* do nothing *)
				| Scanner.Eof: Error("element not closed"); RETURN
				ELSE
					Error("unknown Element Content"); RETURN
				END;
				scanner.ScanContent()
			UNTIL scanner.sym = Scanner.Eof
		END ParseExtGenEntity;
		
		PROCEDURE ParseXMLDecl(): XML.XMLDecl;
		VAR decl: XML.XMLDecl; s: String;
		BEGIN
			NEW(decl); decl.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Name}, "'version' expected") THEN RETURN decl END;
			s := scanner.GetStr();
			IF s^ # "version" THEN Error("'version' expected"); RETURN decl END;
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Literal}, "Version Number expected") THEN RETURN decl END;
			s := scanner.GetStr();
			decl.SetVersion(s^);
			scanner.ScanMarkup(); s := scanner.GetStr();
			IF (scanner.sym = Scanner.Name) & (s^ = "encoding") THEN
				scanner.ScanMarkup();
				IF ~CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
				scanner.ScanMarkup();
				IF ~CheckSymbol({Scanner.Literal}, "Encoding Name expected") THEN RETURN decl END;
				s := scanner.GetStr();
				decl.SetEncoding(s^);
				scanner.ScanMarkup(); s := scanner.GetStr()
			END;
			IF (scanner.sym = Scanner.Name) & (s^ = "standalone") THEN
				scanner.ScanMarkup();
				IF ~CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
				scanner.ScanMarkup();
				IF ~CheckSymbol({Scanner.Literal}, '"yes" or "no" expected') THEN RETURN decl END;
				s := scanner.GetStr();
				IF s^ = "yes" THEN decl.SetStandalone(TRUE)
				ELSIF s^ = "no" THEN decl.SetStandalone(FALSE)
				ELSE Error('"yes" or "no" expected'); RETURN decl
				END;
				scanner.ScanMarkup()
			END;
			IF ~CheckSymbol({Scanner.TagPIClose}, "'?>' expected") THEN RETURN decl END;
			RETURN decl
		END ParseXMLDecl;
		
		PROCEDURE ParseTextDecl(): XML.TextDecl;
		VAR decl: XML.TextDecl; s: String;
		BEGIN
			NEW(decl); decl.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Name}, "'version' expected") THEN RETURN decl END;
			s := scanner.GetStr();
			IF s^ # "version" THEN Error("'version' expected"); RETURN decl END;
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Literal}, "Version Number expected") THEN RETURN decl END;
			s := scanner.GetStr();
			decl.SetVersion(s^);
			scanner.ScanMarkup(); s := scanner.GetStr();
			IF (scanner.sym = Scanner.Name) & (s^ = "encoding") THEN
				scanner.ScanMarkup();
				IF ~CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN decl END;
				scanner.ScanMarkup();
				IF ~CheckSymbol({Scanner.Literal}, "Encoding Name expected") THEN RETURN decl END;
				s := scanner.GetStr();
				decl.SetEncoding(s^);
				scanner.ScanMarkup(); s := scanner.GetStr()
			END;
			IF ~CheckSymbol({Scanner.TagPIClose}, "'?>' expected") THEN RETURN decl END;
			RETURN decl
		END ParseTextDecl;
		
		PROCEDURE ParseComment(): XML.Comment;
		VAR comment: XML.Comment; s: String;
		BEGIN
			NEW(comment); comment.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			s := scanner.GetStr();
			comment.SetStr(s^);
			RETURN comment
		END ParseComment;
				
		PROCEDURE ParseProcessingInstruction(): XML.ProcessingInstruction;
		VAR pi: XML.ProcessingInstruction; s: String;
		BEGIN
			NEW(pi); pi.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			s := scanner.GetStr();
			pi.SetTarget(s^);
			scanner.ScanPInstruction();
			IF ~CheckSymbol({Scanner.TagPIClose}, "'?>' expected") THEN RETURN pi END;
			s := scanner.GetStr();
			pi.SetInstruction(s^);
			RETURN pi
		END ParseProcessingInstruction;
		
		PROCEDURE ParseDocTypeDecl();
		VAR externalSubset: XML.EntityDecl; s: String;
		BEGIN
			NEW(dtd); dtd.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Name}, "DTD name expected") THEN RETURN END;
			s := scanner.GetStr(); dtd.SetName(s^);
			scanner.ScanMarkup();
			IF scanner.sym = Scanner.Name THEN	(* DTD points to external subset *)
				NEW(externalSubset); externalSubset.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
				s := scanner.GetStr();
				IF s^ = 'SYSTEM' THEN
					s := ParseSystemLiteral();
					externalSubset.SetSystemId(s^)
				ELSIF s^ = 'PUBLIC' THEN
					s := ParsePubidLiteral();
					externalSubset.SetPublicId(s^);
					s := ParseSystemLiteral();
					externalSubset.SetSystemId(s^)
				ELSE
					Error("'SYSTEM' or 'PUBLIC' expected"); RETURN
				END;
				dtd.SetExternalSubset(externalSubset);
				scanner.ScanMarkup()
			END;
			IF scanner.sym = Scanner.BracketOpen THEN	(* markupdecl *)
				ParseMarkupDecls()
			END;
			IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
		END ParseDocTypeDecl;
		
		PROCEDURE ParseMarkupDecls();
		VAR s: String; oldscanner: Scanner.Scanner; f: AosFS.File; w: AosFS.Writer;
		BEGIN
			REPEAT
				scanner.ScanMarkup();
				CASE scanner.sym OF
				| Scanner.TagDeclOpen:
						s := scanner.GetStr();
						IF s^ = 'ELEMENT' THEN
							ParseElementDecl(dtd)
						ELSIF s^ = 'ATTLIST' THEN
							ParseAttListDecl(dtd)
						ELSIF s^ = 'ENTITY' THEN
							ParseEntityDecl(dtd)
						ELSIF s^ = 'NOTATION' THEN
							ParseNotationDecl(dtd)
						ELSE
							Error("'ELEMENT', 'ATTLIST' or 'NOTATION' expected"); RETURN
						END
				|Scanner.TagPIOpen: dtd.AddMarkupDecl(ParseProcessingInstruction())
				| Scanner.Comment: dtd.AddMarkupDecl(ParseComment())
				| Scanner.ParamEntityRef:
					s := scanner.GetStr();
					s := ExpandEntityRef(s^, XML.ParameterEntity);
					f := AosFS.New(""); AosFS.OpenWriter(w, f, 0); w.Bytes(s^, 0, LEN(s^) - 1); w.Update;
					oldscanner := scanner;
					NEW(scanner, f);
					ParseMarkupDecls();
					scanner := oldscanner
				| Scanner.BracketClose: (* end of markupdecl *)
				| Scanner.Eof, Scanner.Invalid: RETURN
				ELSE
					Error("unknown markup declaration"); RETURN
				END
			UNTIL scanner.sym = Scanner.BracketClose;
			scanner.ScanMarkup()
		END ParseMarkupDecls;
		
		PROCEDURE ParseElementDecl(dtd: XML.DocTypeDecl);
		VAR ed: XML.ElementDecl; ccp: XML.CollectionCP; s: String;
			contentType: SHORTINT;
		BEGIN
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Name}, "Element name expected") THEN RETURN END;
			s := scanner.GetStr();
			ed := dtd.GetElementDecl(s^);
			IF ed = NIL THEN	(* Attribute List Declaration not occured yet -> create new element declaration and add it to the DTD *)
				NEW(ed); ed.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
				ed.SetName(s^);
				dtd.AddMarkupDecl(ed)
			END;
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Name, Scanner.ParenOpen}, "'EMPTY', 'ANY', Mixed or Element Content expected") THEN
				RETURN END;
			IF scanner.sym = Scanner.Name THEN
				s := scanner.GetStr();
				IF s^ = 'EMPTY' THEN
					ed.SetContentType(XML.Empty)
				ELSIF s^ = 'ANY' THEN
					ed.SetContentType(XML.Any)
				ELSE
					Error("'EMPTY' or 'ANY' expected"); RETURN
				END;
				scanner.ScanMarkup();
				IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
			ELSIF scanner.sym = Scanner.ParenOpen THEN	(* Mixed or children element content *)
				ccp := ParseContentParticle(contentType);
				ed.SetContent(ccp);
				ed.SetContentType(contentType)
			END
		END ParseElementDecl;
		
		PROCEDURE ParseAttListDecl(dtd: XML.DocTypeDecl);
		VAR ed: XML.ElementDecl; ad: XML.AttributeDecl; s: String;
		BEGIN
			scanner.ScanMarkup();	(* parse element name *)
			IF ~CheckSymbol({Scanner.Name}, "Element name expected") THEN RETURN END;
			s := scanner.GetStr();
			ed := dtd.GetElementDecl(s^);
			IF ed = NIL THEN	(* Element Declaration not occured yet -> create new element declaration and add it to the DTD *)
				NEW(ed); ed.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
				ed.SetName(s^);
				dtd.AddMarkupDecl(ed)
			END;
			scanner.ScanMarkup();
			WHILE (scanner.sym # Scanner.TagClose)  DO	(* parse AttDefs *)
				IF ~CheckSymbol({Scanner.Name}, "Attribute Name expected") THEN RETURN END;
				s := scanner.GetStr(); NEW(ad); ad.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
				ad.SetName(s^);
				scanner.ScanMarkup();
				IF ~CheckSymbol({Scanner.Name, Scanner.ParenOpen}, "Attribute Type expected") THEN RETURN END;
				IF scanner.sym = Scanner.Name THEN
					s := scanner.GetStr();
					IF s^ = 'CDATA' THEN ad.SetType(XML.CData)
					ELSIF s^ = 'ID' THEN ad.SetType(XML.Id)
					ELSIF s^ = 'IDREF' THEN ad.SetType(XML.IdRef)
					ELSIF s^ = 'IDREFS' THEN ad.SetType(XML.IdRefs)
					ELSIF s^ = 'ENTITY' THEN ad.SetType(XML.Entity)
					ELSIF s^ = 'ENTITIES' THEN ad.SetType(XML.Entities)
					ELSIF s^ = 'NMTOKEN' THEN ad.SetType(XML.NmToken)
					ELSIF s^ = 'NMTOKENS' THEN ad.SetType(XML.NmTokens)
					ELSIF s^ = 'NOTATION' THEN
						ad.SetType(XML.Notation);
						scanner.ScanMarkup();
						IF ~CheckSymbol({Scanner.ParenOpen}, "'(' expected") THEN RETURN END;
						scanner.ScanMarkup();
						IF ~CheckSymbol({Scanner.Name}, "Notation Name expected") THEN RETURN END;
						scanner.ScanMarkup()
					ELSE Error("Attribute Type expected"); RETURN
					END
				ELSIF scanner.sym = Scanner.ParenOpen THEN
					ad.SetType(XML.Enumeration);
					scanner.ScanMarkup();
					IF ~CheckSymbol({Scanner.Name, Scanner.Nmtoken}, "Value Nmtoken expected") THEN RETURN END;
				END;
				IF (ad.GetType() = XML.Notation) OR (ad.GetType() = XML.Enumeration) THEN
					WHILE (scanner.sym = Scanner.Name) OR 
							((scanner.sym = Scanner.Nmtoken) & (ad.GetType() = XML.Enumeration)) DO
						s := scanner.GetStr();
						ad.AddAllowedValue(s^);
						scanner.ScanMarkup();
						IF scanner.sym = Scanner.Or THEN
							scanner.ScanMarkup()
						END
					END;
					IF ~CheckSymbol({Scanner.ParenClose}, "')' expected") THEN RETURN END;
				END;
				scanner.ScanMarkup();
				s := scanner.GetStr();	(* parse DefaultDecl *)
				IF ~CheckSymbol({Scanner.PoundName, Scanner.Literal}, 
					"'#REQUIRED', '#IMPLIED', '#FIXED' or AttValue expected") THEN RETURN END;
				IF scanner.sym =  Scanner.PoundName THEN
					IF (s^ = '#REQUIRED') THEN
						ad.SetRequired(TRUE)
					 ELSIF (s^ = '#FIXED') THEN
						ad.SetRequired(TRUE);
						scanner.ScanMarkup();
						IF ~CheckSymbol({Scanner.Literal}, "AttValue expected") THEN RETURN END
					ELSIF (s^ = '#IMPLIED') THEN
						ad.SetRequired(FALSE)
					ELSE
						Error("'#REQUIRED', '#IMPLIED' or '#FIXED' expected"); RETURN
					END
				ELSIF scanner.sym = Scanner.Literal THEN
					ad.SetRequired(FALSE)
				END;
				IF (scanner.sym = Scanner.Literal) THEN
					s := ParseAttributeValue();
					ad.SetDefaultValue(s^)
				END;
				scanner.ScanMarkup();
				ed.AddAttributeDecl(ad);
			END;
			IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
		END ParseAttListDecl;
		
		PROCEDURE ParseContentParticle(VAR contentType: SHORTINT): XML.CollectionCP;
		VAR cp: XML.ContentParticle; ncp: XML.NameContentParticle; ccp: XML.CollectionCP; s: String;
		BEGIN
			IF ~CheckSymbol({Scanner.ParenOpen}, "'(' expected") THEN RETURN ccp END;
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Name, Scanner.PoundName, Scanner.ParenOpen}, 
					"Element Name, '#PCDATA' or '(' expected") THEN RETURN ccp END;
			IF scanner.sym = Scanner.PoundName THEN
				contentType := XML.MixedContent;
				s := scanner.GetStr();
				IF s^ = '#PCDATA' THEN
					NEW(ncp); ncp.SetFilePos(scanner.GetFile(), scanner.GetOldPos()); ncp.SetName(s^); ncp.SetOccurence(XML.Once);
					NEW(ccp); ccp.SetFilePos(scanner.GetFile(), scanner.GetOldPos()); ccp.SetType(XML.Choice); ccp.AddChild(ncp);
					scanner.ScanMarkup();
					IF ~CheckSymbol({Scanner.ParenClose, Scanner.Or}, "')' or '|' expected") THEN RETURN ccp END;
					IF scanner.sym = Scanner.ParenClose THEN
						scanner.ScanMarkup();
						IF ~CheckSymbol({Scanner.Asterisk, Scanner.TagClose}, "'*' or '>' expected") THEN RETURN ccp END;
						IF scanner.sym = Scanner.Asterisk THEN
							ccp.SetOccurence(XML.ZeroOrMore);
							scanner.ScanMarkup();
							IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
						ELSIF scanner.sym = Scanner.TagClose THEN
							ccp.SetOccurence(XML.Once)
						END;
						cp := ccp
					ELSIF scanner.sym = Scanner.Or THEN
						WHILE scanner.sym = Scanner.Or DO
							scanner.ScanMarkup();
							IF ~CheckSymbol({Scanner.Name}, "Element Name expected") THEN RETURN ccp END;
							s := scanner.GetStr(); NEW(ncp); ncp.SetFilePos(scanner.GetFile(), scanner.GetOldPos()); 
							ncp.SetName(s^); ncp.SetOccurence(XML.Once);
							ccp.AddChild(ncp);
							scanner.ScanMarkup();
							IF ~CheckSymbol({Scanner.ParenClose, Scanner.Or}, "')' or '|' expected") THEN RETURN ccp END
						END;
						scanner.ScanMarkup();
						IF ~CheckSymbol({Scanner.Asterisk}, "'*' expected") THEN RETURN ccp END;
						ccp.SetOccurence(XML.ZeroOrMore);
						scanner.ScanMarkup();
						IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END;
						cp := ccp
					END
				ELSE
					Error('"#PCDATA" expected'); RETURN ccp
				END
			ELSE
				cp := ParseElementContent();
				IF ~CheckSymbol({Scanner.Or, Scanner.Comma}, "'|' or ',' expected") THEN RETURN ccp END;
				IF scanner.sym = Scanner.Or THEN
					NEW(ccp); ccp.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
					ccp.SetType(XML.Choice); ccp.AddChild(cp);
					REPEAT
						scanner.ScanMarkup();
						ccp.AddChild(ParseElementContent());
						IF ~CheckSymbol({Scanner.Or, Scanner.ParenClose}, "'|' or ')' expected") THEN RETURN ccp END;
					UNTIL scanner.sym = Scanner.ParenClose;
					cp := ccp
				ELSIF scanner.sym = Scanner.Comma THEN
					NEW(ccp); ccp.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
					ccp.SetType(XML.Sequence); ccp.AddChild(cp);
					REPEAT
						scanner.ScanMarkup();
						ccp.AddChild(ParseElementContent());
						IF ~CheckSymbol({Scanner.Comma, Scanner.ParenClose}, "',' or ')' expected") THEN RETURN ccp END;
					UNTIL scanner.sym = Scanner.ParenClose;
					cp := ccp
				END;
				scanner.ScanMarkup();
				CASE scanner.sym OF
				| Scanner.Question: cp.SetOccurence(XML.ZeroOrOnce);
					scanner.ScanMarkup(); IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
				| Scanner.TagPIClose: cp.SetOccurence(XML.ZeroOrOnce)
				| Scanner.Asterisk: cp.SetOccurence(XML.ZeroOrMore);
					scanner.ScanMarkup(); IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
				| Scanner.Plus: cp.SetOccurence(XML.OnceOrMore);
					scanner.ScanMarkup(); IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
				ELSE cp.SetOccurence(XML.Once);
					IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN ccp END
				END
			END;
			RETURN cp(XML.CollectionCP)
		END ParseContentParticle;
		
		PROCEDURE ParseElementContent(): XML.ContentParticle;
		VAR cp: XML.ContentParticle; ncp: XML.NameContentParticle; ccp: XML.CollectionCP; s: String;
		BEGIN
			IF ~CheckSymbol({Scanner.Name, Scanner.ParenOpen}, "Element Name or '(' expected") THEN RETURN cp END;
			IF scanner.sym = Scanner.Name THEN
				NEW(ncp); ncp.SetFilePos(scanner.GetFile(), scanner.GetOldPos()); s := scanner.GetStr();
				ncp.SetName(s^); cp := ncp
			ELSIF scanner.sym = Scanner.ParenOpen THEN
				scanner.ScanMarkup();
				cp := ParseElementContent();
				IF ~CheckSymbol({Scanner.Or, Scanner.Comma}, "'|' or ',' expected") THEN RETURN cp END;
				IF scanner.sym = Scanner.Or THEN
					NEW(ccp); ccp.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
					ccp.SetType(XML.Choice); ccp.AddChild(cp);
					REPEAT
						scanner.ScanMarkup();
						ccp.AddChild(ParseElementContent());
						IF ~CheckSymbol({Scanner.Or, Scanner.ParenClose}, "'|' or ')' expected") THEN RETURN cp END;
					UNTIL scanner.sym = Scanner.ParenClose;
					cp := ccp
				ELSIF scanner.sym = Scanner.Comma THEN
					NEW(ccp); ccp.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
					ccp.SetType(XML.Sequence); ccp.AddChild(cp);
					REPEAT
						scanner.ScanMarkup();
						ccp.AddChild(ParseElementContent());
						IF ~CheckSymbol({Scanner.Comma, Scanner.ParenClose}, "',' or ')' expected") THEN RETURN cp END
					UNTIL scanner.sym = Scanner.ParenClose;
					cp := ccp
				END
			END;
			scanner.ScanMarkup();
			CASE scanner.sym OF
			| Scanner.Question: cp.SetOccurence(XML.ZeroOrOnce); scanner.ScanMarkup()
			| Scanner.Asterisk: cp.SetOccurence(XML.ZeroOrMore); scanner.ScanMarkup()
			| Scanner.Plus: cp.SetOccurence(XML.OnceOrMore); scanner.ScanMarkup()
			ELSE cp.SetOccurence(XML.Once)
			END;
			RETURN cp
		END ParseElementContent;
		
		PROCEDURE ParseEntityDecl(dtd: XML.DocTypeDecl);
		VAR ed: XML.EntityDecl; s: String;
		BEGIN
			NEW(ed); ed.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			scanner.ScanMarkup();
			IF scanner.sym = Scanner.Percent THEN	(* Parameter Entity Decl *)
				ed.SetType(XML.ParameterEntity);
				scanner.ScanMarkup()
			ELSE	(* General Entity Declaration *)
				ed.SetType(XML.GeneralEntity);
			END;
			IF ~CheckSymbol({Scanner.Name}, "Entity Declaration Name expected") THEN RETURN END;
			s := scanner.GetStr();
			ed.SetName(s^);
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Literal, Scanner.Name}, "EntityValue, 'SYSTEM' or 'PUBLIC' expected") THEN RETURN END;
			IF scanner.sym = Scanner.Literal THEN	(* EntityValue *)
				s := ParseEntityValue();
				ed.SetValue(s^);
				scanner.ScanMarkup()
			ELSIF scanner.sym = Scanner.Name THEN	(* ExternalID *)
				s := scanner.GetStr();
				IF s^ = 'SYSTEM' THEN
					s := ParseSystemLiteral();
					ed.SetSystemId(s^);
					scanner.ScanMarkup()
				ELSIF s^ = 'PUBLIC' THEN
					s := ParsePubidLiteral();
					ed.SetPublicId(s^);
					s := ParseSystemLiteral();
					ed.SetSystemId(s^);
					scanner.ScanMarkup()
				ELSE
					Error("'SYSTEM' or 'PUBLIC' expected"); RETURN
				END;
				IF (scanner.sym = Scanner.Name) & (ed.GetType() = XML.GeneralEntity) THEN
					s := scanner.GetStr();
					IF s^ = 'NDATA' THEN	(* NDataDecl *)
						scanner.ScanMarkup();
						IF ~CheckSymbol({Scanner.Name}, "Notation Name expected") THEN RETURN END;
						s := scanner.GetStr();
						ed.SetNotationName(s^);
						scanner.ScanMarkup()
					ELSE
						Error("'NDATA' expected"); RETURN
					END
				END
			ELSE
				Error("EntityValue or SystemId expected"); RETURN
			END;
			IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
			dtd.AddMarkupDecl(ed)
		END ParseEntityDecl;
		
		PROCEDURE ParseNotationDecl(dtd: XML.DocTypeDecl);
		VAR nd: XML.NotationDecl; s: String;
		BEGIN
			NEW(nd); nd.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Name}, "Notation Name expected") THEN RETURN END;
			s := scanner.GetStr();
			nd.SetName(s^);
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Name}, "'PUBLIC' or 'SYSTEM' expected") THEN RETURN END;
			s := scanner.GetStr();
			IF s^ = 'PUBLIC' THEN
				s := ParsePubidLiteral();
				nd.SetPublicId(s^);
				scanner.ScanMarkup();
				IF scanner.sym = Scanner.Literal THEN	(* ExternalID 1 *)
					s := scanner.GetStr();
					nd.SetSystemId(s^);
					scanner.ScanMarkup()
				ELSE	(* PublicID, nothing more *)
				END
			ELSIF s^ = 'SYSTEM' THEN	(* ExternalID 2 *)
				s := ParseSystemLiteral();
				nd.SetSystemId(s^);
				scanner.ScanMarkup()
			END;
			IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
			dtd.AddMarkupDecl(nd)
		END ParseNotationDecl;
		
		PROCEDURE ParseSystemLiteral(): String;
		VAR systemLiteral: String;
		BEGIN
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Literal}, "System Literal expected") THEN RETURN systemLiteral END;
			systemLiteral := scanner.GetStr();
			RETURN systemLiteral
		END ParseSystemLiteral;
		
		PROCEDURE ParsePubidLiteral(): String;
		VAR pubidLiteral: String;
		BEGIN
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Literal}, "PubidLiteral expected") THEN RETURN pubidLiteral END;
			pubidLiteral := scanner.GetStr();
			IF ~IsPubidLiteral(pubidLiteral^) THEN Error("not a correct Pubid Literal"); RETURN pubidLiteral END;
			RETURN pubidLiteral
		END ParsePubidLiteral;

		PROCEDURE ParseCDataSect(): XML.CDataSect;
		VAR cds: XML.CDataSect; s: String;
		BEGIN
			NEW(cds); cds.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			s := scanner.GetStr();
			cds.SetStr(s^);
			RETURN cds
		END ParseCDataSect;
		
		PROCEDURE ParseCharData(): XML.CharData;
		VAR cd: XML.CharData; oldpos: LONGINT;
		BEGIN
			oldpos := scanner.GetOldPos();
			NEW(cd); cd.SetFilePos(scanner.GetFile(), scanner.GetOldPos()); cd.SetLen(scanner.GetPos() - oldpos);
			RETURN cd
		END ParseCharData;
		
		PROCEDURE ParseElement(): XML.Element;
		VAR e: XML.Element; empty: BOOLEAN;
		BEGIN
			ParseStartTag(e, empty);
			IF e = NIL THEN RETURN NIL END;
			IF ~empty THEN
				REPEAT
					scanner.ScanContent();
					CASE scanner.sym OF
					| Scanner.CharData: e.AddContent(ParseCharData())
					| Scanner.TagElemStartOpen: e.AddContent(ParseElement())
					| Scanner.CharRef: e.AddContent(ParseCharRef())
					| Scanner.EntityRef: e.AddContent(ParseEntityRef())
					| Scanner.CDataSect: e.AddContent(ParseCDataSect())
					| Scanner.Comment: e.AddContent(ParseComment())
					| Scanner.TagPIOpen: e.AddContent(ParseProcessingInstruction())
					| Scanner.TagElemEndOpen: (* do nothing *)
					| Scanner.Eof: Error("element not closed"); RETURN e
					ELSE
						Error("unknown Element Content"); RETURN e
					END
				UNTIL scanner.sym = Scanner.TagElemEndOpen;
				ParseEndTag(e);
			END;
			RETURN e
		END ParseElement;
		
		PROCEDURE ParseStartTag(VAR e: XML.Element; VAR empty: BOOLEAN);
		VAR s: String; pos: LONGINT;
		BEGIN
			pos := scanner.GetOldPos();
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Name}, "Element Name expected") THEN RETURN END;
			s := scanner.GetStr();
			IF elemReg # NIL THEN
				e := elemReg.InstantiateElement(s^)
			END;
			IF e = NIL THEN NEW(e) END;
			 e.SetFilePos(scanner.GetFile(), pos);
			e.SetName(s^);
			scanner.ScanMarkup();
			WHILE scanner.sym = Scanner.Name DO
				e.AddAttribute(ParseAttribute());
				scanner.ScanMarkup();
			END;
			IF ~CheckSymbol({Scanner.TagEmptyElemClose, Scanner.TagClose}, "'/>' or '>' expected") THEN RETURN END;
			IF scanner.sym = Scanner.TagEmptyElemClose THEN
				empty := TRUE
			ELSIF scanner.sym = Scanner.TagClose THEN
				empty := FALSE
			END
		END ParseStartTag;

		PROCEDURE ParseAttribute(): XML.Attribute;
		VAR a: XML.Attribute; s: String;
		BEGIN
			NEW(a); a.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			s := scanner.GetStr();
			a.SetName(s^);
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Equal}, "'=' expected") THEN RETURN a END;
			scanner.ScanMarkup();
			IF ~CheckSymbol({Scanner.Literal}, "Attribute Value expected") THEN RETURN a END;
			s := ParseAttributeValue();
			a.SetValue(s^);
			RETURN a
		END ParseAttribute;
		
		PROCEDURE ParseEndTag(e: XML.Element);
		VAR ds: DynamicStrings.DynamicString; s1, s2: String; msg: ARRAY 12 OF CHAR;
		BEGIN
			scanner.ScanMarkup();
			s1 := scanner.GetStr(); s2 := e.GetName();
			IF (scanner.sym = Scanner.Name) & (s1^ = s2^) THEN
				scanner.ScanMarkup();
				IF ~CheckSymbol({Scanner.TagClose}, "'>' expected") THEN RETURN END;
			ELSE
				NEW(ds);
				msg := "'</'"; ds.Append(msg); ds.Append(s2^);
				msg := ">' expected"; ds.Append(msg); s1 := ds.ToArrOfChar();
				Error(s1^); RETURN
			END
		END ParseEndTag;
		
		PROCEDURE ParseEntityValue(): String;
		VAR s: String; ds1, ds2: DynamicStrings.DynamicString;
			start, end, len, val: LONGINT; msg: ARRAY 17 OF CHAR;
		BEGIN
			s := scanner.GetStr(); NEW(ds1); ds1.Append(s^);
			start := 0; len := ds1.Length();
			WHILE start < len DO
				WHILE (start < len) & ((ds1.Get(start) # '&') OR (ds1.Get(start + 1) # '#')) & (ds1.Get(start) # '%') DO
					INC(start)
				END;
				IF ((ds1.Get(start) = '&') & (ds1.Get(start + 1) = '#')) OR (ds1.Get(start) = '%') THEN
					end := start + 1;
					WHILE (end < len) & (ds1.Get(end) # ';') DO
						INC(end)
					END;
					IF ds1.Get(end) = ';' THEN
						NEW(ds2);
						s := ds1.Extract(0, start);	(* literal before reference *)
						ds2.Append(s^);
						IF (ds1.Get(start) = '&') & (ds1.Get(start + 1) = '#') THEN	(* character reference *)
							s := ds1.Extract(start + 2, end - start - 1);
							val := StrToInt(s^);
							msg[0] := ExpandCharacterRef(val);
							msg[1] := 0X;
							ds2.Append(msg);
							start := start + 1;
						ELSE	(* parameter entity reference *)
							s := ds1.Extract(start + 1, end - start - 1);	(* reference name *)
							s := ExpandEntityRef(s^, XML.ParameterEntity);	(* reference value *)
							IF s = NIL THEN
								NEW(ds2);
								msg := 'unknown entity "'; ds2.Append(msg);
								s := ds1.Extract(start + 1, end - start - 1); ds2.Append(s^);
								msg := '"'; ds2.Append(msg);
								s := ds2.ToArrOfChar();
								Error(s^); RETURN ds1.ToArrOfChar()
							END;
							ds2.Append(s^);
						END;
						s := ds1.Extract(end + 1, len - end -1);	(* literal after reference *)
						ds2.Append(s^);
						ds1 := ds2;
						len := ds1.Length()
					ELSE
						Error("';' expected (unclosed reference)"); RETURN ds1.ToArrOfChar()
					END
				END
			END;
			RETURN ds1.ToArrOfChar()
		END ParseEntityValue;
		
		PROCEDURE ParseAttributeValue(): String;
		VAR s: String; ds1, ds2: DynamicStrings.DynamicString;
			start, end, len, val: LONGINT; msg: ARRAY 17 OF CHAR;
		BEGIN
			s := scanner.GetStr(); NEW(ds1); ds1.Append(s^);
			start := 0; len := ds1.Length();
			WHILE start < len DO
				WHILE (start < len) & (ds1.Get(start) # '&') DO
					INC(start)
				END;
				IF ds1.Get(start) = '&' THEN
					end := start + 1;
					WHILE (end < len) & (ds1.Get(end) # ';') DO
						INC(end)
					END;
					IF ds1.Get(end) = ';' THEN
						NEW(ds2);
						s := ds1.Extract(0, start);	(* literal before reference *)
						ds2.Append(s^);
						IF ds1.Get(start + 1) = '#' THEN	(* character reference *)
							s := ds1.Extract(start + 2, end - start - 1);
							val := StrToInt(s^);
							msg[0] := ExpandCharacterRef(val);
							msg[1] := 0X;
							ds2.Append(msg);
							start := start + 1;
						ELSE	(* general entity reference *)
							s := ds1.Extract(start + 1, end - start - 1);	(* reference name *)
							s := ExpandEntityRef(s^, XML.GeneralEntity);	(* reference value *)
							IF s = NIL THEN 
								NEW(ds2); 
								msg := 'unknown entity "'; ds2.Append(msg);
								s := ds1.Extract(start + 1, end - start - 1); ds2.Append(s^);
								msg := '"'; ds2.Append(msg);
								s := ds2.ToArrOfChar();
								Error(s^); RETURN ds1.ToArrOfChar()
							END;
							ds2.Append(s^);
						END;
						s := ds1.Extract(end + 1, len - end -1);	(* literal after reference *)
						ds2.Append(s^);
						ds1 := ds2;
						len := ds1.Length()
					ELSE
						Error("';' expected (unclosed reference)"); RETURN ds1.ToArrOfChar()
					END
				END
			END;
			RETURN ds1.ToArrOfChar()
		END ParseAttributeValue;
		
		PROCEDURE ParseCharRef(): XML.CharReference;
		VAR cRef: XML.CharReference; code, res: LONGINT; s: String;
		BEGIN
			s := scanner.GetStr();
			IF s[0] = 'x' THEN	(* hexadecimal *)
				Utilities.Delete(s^, 0, 1);
				Utilities.HexStrToInt(s^, code, res);
			ELSE	(* decimal *)
				Utilities.StrToInt(s^, code);
			END;
			NEW(cRef);
			cRef.SetCode(code);
			cRef.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
			RETURN cRef;
		END ParseCharRef;
		
		PROCEDURE ParseEntityRef(): XML.EntityRef;
		VAR ext: XML.ExternalEntityRef; int: XML.InternalEntityRef; s1, s2: String; ent: XML.EntityDecl;
		BEGIN
			s1 := scanner.GetStr();
			ent := dtd.GetEntityDecl(s1^, XML.GeneralEntity);
			IF ent # NIL THEN
				s2 := ent.GetValue();
				IF s2 # NIL THEN
					NEW(int); int.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
					int.SetName(s1^);
					RETURN int
				ELSE
					NEW(ext); ext.SetFilePos(scanner.GetFile(), scanner.GetOldPos());
					ext.SetName(s1^);
					RETURN ext
				END
			ELSE
				RETURN NIL
			END
		END ParseEntityRef;
		
	END Parser;
	
	PROCEDURE IsPubidLiteral(VAR str: ARRAY OF CHAR): BOOLEAN;
	VAR i, len: LONGINT; ch: CHAR;
	BEGIN
		i := 0; len := LEN(str); ch := str[0];
		REPEAT
			ch := str[i]; INC(i)
		UNTIL ((ch # 20X) & (ch # 0DX) & (ch # 0AX) & ((ch < 'a') OR ('z' < ch)) & ((ch < 'A') & ('Z' < ch))
				& ((ch < '0') & ('9' < ch)) & (ch # '(') & (ch # ')') & (ch # '+') & (ch # ',') & (ch # '.')
				& (ch # '/') & (ch # ':') & (ch # '=') & (ch # '?') & (ch # ';') & (ch # '!') & (ch # '*') & (ch # '#')
				& (ch # '@') & (ch # '$') & (ch # '_') & (ch # '%')) OR (i >= len);
		RETURN i = len
	END IsPubidLiteral;
	
	PROCEDURE StrToInt(VAR str: ARRAY OF CHAR): LONGINT;
	BEGIN
		IF str[0] = 'x' THEN	(* str in hexadecimal form *)
			str[0] := ' ';
			RETURN DynamicStrings.HexStrToInt(str)
		ELSE
			RETURN DynamicStrings.StrToInt(str)
		END
	END StrToInt;			
	
	PROCEDURE DefaultReportError(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
	BEGIN
		AosOut.Enter; AosOut.Char(CHR(9H)); AosOut.Char(CHR(9H)); AosOut.String("pos "); AosOut.Int(pos, 6);
		AosOut.String(", line "); AosOut.Int(line, 0); AosOut.String(", row "); AosOut.Int(row, 0);
		AosOut.String("    "); AosOut.String(msg); AosOut.Exit;
		HALT(99)
	END DefaultReportError;
	
BEGIN
END XMLParser.