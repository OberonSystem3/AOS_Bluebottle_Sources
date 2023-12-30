MODULE XMLGeneratorSchema;	(** Stefan Walthert  *)
(** AUTHOR "swalthert"; PURPOSE "XCCS: XML Component Configuration Schema"; *)

IMPORT
	AosModules, AosOut, XMLObjects, XML, XMLScanner, XMLParser, AosFS;
	
PROCEDURE OpenGeneratorSchema*(xgsName: ARRAY OF CHAR): XML.ElementRegistry;
VAR xgsFile: AosFS.File; scanner: XMLScanner.Scanner; parser: XMLParser.Parser; doc: XML.Document;
	root: XML.Element; name, generator, elementName: XML.String; contents: XMLObjects.Enumerator; content: PTR;
	module: AosModules.Module; commandParProc: AosModules.CommandParProc; 
	res, i: LONGINT; msg: ARRAY 1024 OF CHAR; er: XML.ElementRegistry;
	reader: AosFS.Reader;
BEGIN
	xgsFile := AosFS.Old(xgsName);
	IF xgsFile = NIL THEN RETURN NIL END;
	NEW(reader, xgsFile, 0);
	NEW(scanner, reader); NEW(parser, scanner);
	doc := parser.Parse();
	root := doc.GetRoot();
	name := root.GetName();
	IF name^ = "generator-schema" THEN
		contents := root.GetContents();
		NEW(er);
		WHILE contents.HasMoreElements() DO
			content := contents.GetNext();
			IF content IS XML.Element THEN
				generator := content(XML.Element).GetAttributeValue("generator");
				IF generator # NIL THEN
					NEW(name, LEN(generator));
					i := 0;
					WHILE (i < LEN(name) - 1) & (generator[i] # '.') DO
						name[i] := generator[i]; INC(i)
					END;
					name[i] := 0X; INC(i);
					module := AosModules.ThisModule(name^, res, msg);
					IF module # NIL THEN
						res := i;
						WHILE i < LEN(name) - 1 DO
							name[i - res] := generator[i]; INC(i)
						END;
						name[i - res] := 0X;
						elementName := content(XML.Element).GetName();
						commandParProc := AosModules.ThisCommandPar(module, name^);
						IF commandParProc # NIL THEN
							er.RegisterElement(elementName^, commandParProc)
						ELSE
							AosOut.Enter; AosOut.String('CommandParProc "'); 
							AosOut.String(name^); AosOut.String('" not found'); AosOut.Exit
						END
					ELSE
						AosOut.Enter; AosOut.String('Module "'); AosOut.String(name^); AosOut.String('" not found'); AosOut.Exit
					END
				ELSE
					AosOut.Enter; AosOut.String("generator attribute not specified ('generator = "); AosOut.Char(22X);
					AosOut.String("Module.Generator"); AosOut.Char(22X); AosOut.String("')"); AosOut.Exit
				END
			END
		END
	ELSE
		AosOut.String("wrong document name: '"); AosOut.String(name^); AosOut.String("' instead of 'generator-schema'"); 
	END;
	RETURN er
END OpenGeneratorSchema;

END XMLGeneratorSchema.