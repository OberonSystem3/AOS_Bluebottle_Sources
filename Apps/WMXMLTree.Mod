MODULE WMXMLTree; (** AUTHOR "TF"; PURPOSE "Simple XML Viewer"; *)
(**
 * History:
 *
 *	22.12.2006	Added error list (staubesv)
 *)
 
IMPORT
	AosIO, XML, XMLObjects, WMGraphics, 
	WMComponents, WMStandardComponents, WMTextView, WMEditors, WMEvents, Utilities, AosTextUtilities, AosTexts,
	WMTrees, XMLScanner, XMLParser, UTF8Strings;
	
TYPE

	Error* = RECORD
		pos- : LONGINT;
		line-, row- : LONGINT;
		msg- : ARRAY 128 OF CHAR;		
	END;
	
	ErrorList* = POINTER TO ARRAY OF Error;

TYPE

	XMLView* = OBJECT(WMComponents.VisualComponent)
	VAR 
		tree : WMTrees.Tree;
		treeView : WMTrees.TreeView;
		toolbar : WMStandardComponents.Panel;
		errorMsg : WMEditors.Editor;
		refresh- : WMStandardComponents.Button;
		onRefresh- : WMEvents.EventSource;
		label- : WMStandardComponents.Label;
		hasErrors :BOOLEAN;
		highlight : WMTextView.Highlight;
		
		(** Show error messages in XMLView? Default: FALSE *)
		showErrorMessage* : BOOLEAN; 
		
		errorList : ErrorList;
		
		text : AosTexts.Text;
		
		editor : WMEditors.Editor;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			
			NEW(onRefresh, SELF, NIL, NIL, NIL);
			
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			AddContent(toolbar);

			NEW(label); label.alignment.Set(WMComponents.AlignTop);
			label.fillColor.Set(0CCCCCCFFH);
			label.caption.SetAOC("XML Structure (alpha)");
			label.bounds.SetHeight(20);
			SELF.AddContent(label);
			
			NEW(refresh); refresh.caption.SetAOC("Refresh"); refresh.alignment.Set(WMComponents.AlignLeft);
			toolbar.AddContent(refresh);
			refresh.onClick.Add(Refresh);
			
			NEW(errorMsg);
			errorMsg.bounds.SetHeight(150); errorMsg.alignment.Set(WMComponents.AlignTop);
			errorMsg.visible.Set(FALSE);			
			AddContent(errorMsg);
						
			NEW(treeView); treeView.alignment.Set(WMComponents.AlignClient); 
			treeView.onClickNode.Add(Click);
			AddContent(treeView);
			tree := treeView.GetTree();
		END Init;
		
		PROCEDURE SetEditor*(e: WMEditors.Editor);
		BEGIN
			IF e = editor THEN RETURN END;
			IF (highlight # NIL) & (editor # NIL) THEN 
				editor.tv.RemoveHighlight(highlight);
				highlight := NIL
			END;
			text := e.text;
			editor := e;
			highlight := editor.tv.CreateHighlight();
			highlight.SetColor(0DDDD0060H);
			highlight.SetKind(WMTextView.HLOver)
		END SetEditor;
		
		PROCEDURE Click(sender, data : ANY);
		VAR p : ANY; a, b : LONGINT;
		BEGIN
			IF (data # NIL) & (data IS WMTrees.TreeNode) THEN
				tree.Acquire;
				p := tree.GetNodeData(data(WMTrees.TreeNode));
				tree.Release;
				IF (p # NIL) & (p IS XML.Element) THEN
					IF editor # NIL THEN 
						text.AcquireRead;
						editor.tv.cursor.SetPosition(p(XML.Element).GetPos());
						editor.tv.cursor.SetVisible(TRUE);
						editor.tv.FindCommand(p(XML.Element).GetPos()-1, a, b);
						IF highlight # NIL THEN highlight.SetFromTo(a, b) END;
						text.ReleaseRead;
					END
				END
			END;
		END Click;
		
		PROCEDURE AddSubNode(node : WMTrees.TreeNode; xml : XML.Element );
		VAR en : XMLObjects.Enumerator;
			p : ANY; s,t,c : Utilities.String;
			newNode : WMTrees.TreeNode;
		BEGIN
			NEW(newNode);
			tree.AddChildNode(node, newNode);
			tree.SetNodeData(newNode, xml);
			
			s := xml.GetName();
			t := xml.GetAttributeValue("name");
			IF (t#NIL) THEN
				NEW(c,Utilities.Length(s^) + Utilities.Length(t^) + 1 + 4);			
				c[0] := 0X;				
				IF (s # NIL) THEN
					Utilities.Append(c^,s^);
					Utilities.Append(c^,': ');
				END;
				Utilities.Append(c^,'"');
				Utilities.Append(c^,t^);
				Utilities.Append(c^,'"');
			ELSE
				c := s;
			END;
			
			IF c # NIL THEN tree.SetNodeCaption(newNode, c) END;
			
			en := xml.GetContents(); 
			WHILE en.HasMoreElements() DO
				p := en.GetNext();
				IF p IS XML.Element THEN
					AddSubNode(newNode, p(XML.Element));
				END
			END;
		END AddSubNode;
		
		PROCEDURE SetDocument(xml : XML.Element);
		VAR en : XMLObjects.Enumerator;
			p : ANY;
			node : WMTrees.TreeNode;
		BEGIN
			NEW(node);
			tree.Acquire;
			tree.SetRoot(node);
			tree.SetNodeState(node, {WMTrees.NodeAlwaysExpanded});
			tree.SetNodeData(node, xml);
			
			IF xml # NIL THEN
				en := xml.GetContents(); 
				
				WHILE en.HasMoreElements() DO
					p := en.GetNext();
					IF p IS XML.Element THEN
						AddSubNode(node, p(XML.Element));
					END
				END
			END;	
			tree.Release
		END SetDocument;
		
		(* Return a copy of the errorList or NIL in case of no errors *)
		PROCEDURE GetErrorList*() : ErrorList;
		VAR result : ErrorList; i : LONGINT;
		BEGIN
			IF errorList # NIL THEN
				NEW(result, LEN(errorList));
				FOR i := 0 TO LEN(errorList)-1 DO
					result[i] := errorList[i];
				END;
			END;
			RETURN result;
		END GetErrorList;
		
		PROCEDURE AddErrorToList(pos, line, row : LONGINT; msg : ARRAY OF CHAR);
		VAR temp : ErrorList; i : LONGINT;
		BEGIN
			IF errorList = NIL THEN
				i := 0;
				NEW(errorList, 1);
			ELSE
				NEW(temp, LEN(errorList)+1);
				FOR i := 0 TO LEN(errorList)-1 DO
					temp[i] := errorList[i];
				END;
				errorList := temp;
			END;
			errorList[i].pos := pos;
			errorList[i].line := line;
			errorList[i].row := row;
			COPY(msg, errorList[i].msg);
		END AddErrorToList;

		PROCEDURE Error(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
		VAR tw : AosTextUtilities.TextWriter; w : AosIO.Writer;
		BEGIN			
			AddErrorToList(pos, line, row, msg);		
			NEW(tw, errorMsg.text);
			w := tw.GetWriter();
			tw.SetFontStyle({WMGraphics.FontBold});
			w.String(msg); w.Ln;
			tw.SetFontStyle({});
			w.String("at pos "); w.Int(pos, 0); w.String(" (in line "); w.Int(line, 0); w.String(" row "); w.Int(row, 0); w.String(")"); w.Ln;
			w.Ln;
			hasErrors := TRUE;
			w.Update
		END Error;
					
		PROCEDURE Refresh*(sender, data : ANY);
		VAR r : AosIO.StringReader;
			scanner : XMLScanner.Scanner;
			parser : XMLParser.Parser;
			doc : XML.Document;	
			tr : AosTexts.TextReader; ch : AosTexts.Char32; i, p : LONGINT; resstr : ARRAY 7 OF CHAR;
			out : AosIO.Writer;
			ob : Utilities.Buffer;
			s : Utilities.String;
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.Refresh, sender, data)
			ELSE
				errorMsg.text.AcquireWrite;
				errorMsg.text.Delete(0, errorMsg.text.GetLength());
				errorMsg.text.ReleaseWrite;
				errorList := NIL;
				hasErrors := FALSE;
				
				IF text = NIL THEN RETURN END;
				text.AcquireRead;
				NEW(ob, (text.GetLength() * 3 DIV 2)); (* heuristic to avoid growing in most cases *)
				out := ob.GetWriter();
				
				NEW(tr, text);
				FOR i := 0 TO text.GetLength() - 1 DO 
					tr.ReadCh(ch); p := 0;
					IF (ch > 0) & UTF8Strings.EncodeChar(ch, resstr, p) THEN out.String(resstr) END
				END; 
				out.Update;		
				text.ReleaseRead;
	
				NEW(r, ob.GetLength() + 1);
				s := ob.GetString();
				r.SetRaw(s^, 0, ob.GetLength());
						
				hasErrors := FALSE;
				NEW(scanner, r); scanner.reportError := Error;
				NEW(parser, scanner); parser.reportError := Error;
				doc := parser.Parse();
				errorMsg.visible.Set(showErrorMessage & hasErrors);
				IF hasErrors THEN errorMsg.tv.firstLine.Set(0);
					label.caption.SetAOC("XML Structure (ERRORS)");
					label.fillColor.Set(0FF0000FFH);
				ELSE
					label.caption.SetAOC("XML Structure");
					label.fillColor.Set(0CCCCCCFFH);
				END;
				IF doc # NIL THEN
					SetDocument(doc.GetRoot())
				END;
				onRefresh.Call(SELF);
			END	
		END Refresh;
			
	END XMLView;
END WMXMLTree.

S.Free Notepad~

Notepad.OpenOberon x.txt ~
Notepad.OpenEmpty ~
Notepad.OpenUTF8 AosConfig.XML ~
Notepad.OpenUTF8 MenuPage60.XML ~
Notepad.OpenAscii x.txt ~
Notepad.OpenExpXML x.txt ~
Notepad.OpenAuto WMClock.Mod~
