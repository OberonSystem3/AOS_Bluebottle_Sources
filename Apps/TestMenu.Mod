MODULE TestMenu;

IMPORT
	WMMenus, WMTrees, WMStandardComponents, Utilities,
	AosFS, WMComponents, AosOut, AosModules, WMMessages,
	XML, XMLObjects, XMLParser, XMLScanner,
	WM := WMWindowManager;

TYPE
	String = Utilities.String;

	KillerMsg = OBJECT
	END KillerMsg; 

	Window* = OBJECT (WMComponents.FormWindow)
	VAR menu : WMTrees.Tree;
		menuPanel : WMMenus.MenuPanel;
		hasErrors : BOOLEAN;

		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			root : WMTrees.TreeNode;
		BEGIN
			NEW(panel);
			panel.bounds.SetExtents(800, 700);
			panel.fillColor.Set(0FFFFFFFFH);
			panel.takesFocus.Set(TRUE);

			NEW(menu); NEW(root);

			NEW(menuPanel);
			menuPanel.fillColor.Set(08080FFFFH);
			menuPanel.bounds.SetHeight(20);
			menuPanel.alignment.Set(WMComponents.AlignTop);
			menuPanel.horizontal.Set(TRUE);
			menuPanel.openDirection.Set(WMMenus.OpenDownRight);
			menuPanel.SetMenu(menu, root);
			menuPanel.menuSelectEvent.Add(Selected);
			panel.AddContent(menuPanel);

			RETURN panel
		END CreateForm;

		PROCEDURE &New();
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount;
			(* To create a multi language app, try loading the respective XML instead of CreateForm()
			if the XML was not found or does not contain all needed elements, use CreateForm as fallback *)
			vc := CreateForm();

			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);

			 WM.DefaultAddWindow(SELF);
			SetTitle(Utilities.NewString("Test Window"));
		END New;

		PROCEDURE AddMenuItem(node : WMTrees.TreeNode; xml : XML.Element);
		VAR newNode : WMTrees.TreeNode;
		BEGIN
			NEW(newNode);
			menu.AddChildNode(node, newNode);			
			menu.SetNodeData(newNode, xml);
			menu.SetNodeCaption(newNode, xml.GetAttributeValue("caption"));
		END AddMenuItem;
		
(*		PROCEDURE GetString(xml : XML.Element) : String;
		VAR en : XMLObjects.Enumerator;
			p : PTR;	
		BEGIN
			en := xml.GetContents();
			p := en.GetNext();
			IF p # NIL THEN RETURN p(XML.Chars).GetStr()
			ELSE RETURN NIL 
			END
		END GetString;
*)

		PROCEDURE Selected(sender, data : ANY);
		VAR s : Utilities.String;
		BEGIN
			IF ~sequencer.IsCallFromSequencer() THEN
				sequencer.ScheduleEvent(SELF.Selected, sender, data)
			ELSE			
				IF (data # NIL) & (data IS WMTrees.TreeNode) THEN
					menu.Acquire;
					s := menu.GetNodeCaption(data(WMTrees.TreeNode));
					IF s # NIL THEN AosOut.String(s^); AosOut.Ln; END;
					menu.Release;
				END
			END	
		END Selected;

		PROCEDURE AddSubMenu(node : WMTrees.TreeNode; xml : XML.Element );
		VAR en : XMLObjects.Enumerator;
			p : ANY; s : String;
			newNode : WMTrees.TreeNode;
		BEGIN
			NEW(newNode);
			menu.AddChildNode(node, newNode);
			menu.SetNodeData(newNode, xml);
			menu.SetNodeCaption(newNode, xml.GetAttributeValue("caption"));
			
			en := xml.GetContents(); 
			WHILE en.HasMoreElements() DO
				p := en.GetNext();
				IF p IS XML.Element THEN
					s := p(XML.Element).GetName();
					IF s # NIL THEN
						IF s^ = "MenuItem" THEN AddMenuItem(newNode, p(XML.Element))
						ELSIF s^ = "SubMenu" THEN AddSubMenu(newNode, p(XML.Element))
						END
					END
				END
			END;
		END AddSubMenu;

		PROCEDURE SetDocument(xml : XML.Element);
		VAR en : XMLObjects.Enumerator;
			p : ANY; s : String;
			node : WMTrees.TreeNode;
		BEGIN
			NEW(node);
			menu.Acquire;
			menu.SetRoot(node);
			menu.SetNodeState(node, {WMTrees.NodeAlwaysExpanded});
			menu.SetNodeData(node, xml);
			en := xml.GetContents(); 
			WHILE en.HasMoreElements() DO
				p := en.GetNext();
				IF p IS XML.Element THEN
					s := p(XML.Element).GetName();
					IF s # NIL THEN
						IF s^ = "SubMenu" THEN AddSubMenu(node, p(XML.Element))
						ELSIF s^ = "MenuItem" THEN AddMenuItem(node, p(XML.Element))
						END
					END
				END
			END;
			menu.Release;
			menuPanel.SetMenu(menu, node)
		END SetDocument;

		PROCEDURE Error(pos, line, row : LONGINT; msg : ARRAY OF CHAR);
		BEGIN
			AosOut.String("Parse error at pos "); AosOut.Int(pos, 5); AosOut.String(" in line "); AosOut.Int(line, 5); 
			AosOut.String(" row "); AosOut.Int(row, 5); AosOut.String(" - "); AosOut.String(msg); AosOut.Ln;
			hasErrors := TRUE
		END Error;

		PROCEDURE Read(name : ARRAY OF CHAR);
		VAR f : AosFS.File;
			r : AosFS.Reader;
			scanner : XMLScanner.Scanner;
			parser : XMLParser.Parser;
			doc : XML.Document;	
		BEGIN
			hasErrors := FALSE;
			f := AosFS.Old(name);
			IF f # NIL THEN
				AosFS.OpenReader(r, f, 0);
				NEW(scanner, r); scanner.reportError := Error;
				NEW(parser, scanner); parser.reportError := Error;
				doc := parser.Parse();
				IF hasErrors THEN AosOut.String("menu not loaded"); AosOut.Ln
				ELSE SetDocument(doc.GetRoot());
				END
			ELSE
				AosOut.String("name = "); AosOut.String(name); AosOut.String(" not found"); AosOut.Ln
			END
		END Read;

		PROCEDURE Close;
		BEGIN
			Close^;
			DecCount
		END Close;

		PROCEDURE Handle(VAR x : WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
			ELSE Handle^(x)
			END
		END Handle;

	END Window;

VAR
	nofWindows : LONGINT;

PROCEDURE Open*(par : ANY) : ANY;
VAR winstance : Window;
BEGIN
	NEW(winstance);
	winstance.Read("Menu.XML");
	RETURN NIL
END Open;

PROCEDURE IncCount;
BEGIN {EXCLUSIVE}
	INC(nofWindows)
END IncCount;		

PROCEDURE DecCount;
BEGIN {EXCLUSIVE}
	DEC(nofWindows)
END DecCount;		

PROCEDURE Cleanup;
VAR die : KillerMsg;
	 msg : WMMessages.Message;
	 m : WM.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die);
	msg.ext := die;
	msg.msgType := WMMessages.MsgExt;
	m := WM.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END TestMenu.

S.Free TestMenu WMMenus ~
TestMenu.Open ~
