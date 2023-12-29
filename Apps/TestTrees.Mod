MODULE TestTrees;	(** AUTHOR "TF"; PURPOSE "Testing Tree Component"; *)

IMPORT
	AosOut, Utilities, AosModules, DynamicStrings, AosCommands, WMStandardComponents, 
	WMWindowManager, WMComponents, WMMessages, 
	WMGraphics, WMTrees,  WMEditors;

TYPE
	String = Utilities.String;
	Window = OBJECT (WMComponents.FormWindow)
	VAR 
		panel : WMStandardComponents.Panel;
		tree : WMTrees.TreeView;
		delete, add : WMStandardComponents.Button;
		node : WMTrees.TreeNode;
		editor : WMEditors.Editor; 
			
		PROCEDURE &New;
		BEGIN
			(* add a panel *)
			NEW(panel); panel.bounds.SetExtents(640, 420); panel.fillColor.Set(WMGraphics.RGBAToColor(255, 255, 255, 255));
			
			(* add a tree component *)
			NEW(tree); tree.bounds.SetWidth(200); tree.alignment.Set(WMComponents.AlignLeft);
			tree.onSelectNode.Add(NodeSelected);
			panel.AddContent(tree);
			
			(* add a button *)
			NEW(delete); delete.bounds.SetExtents(200, 20); delete.caption.SetAOC("Delete");
			delete.alignment.Set(WMComponents.AlignTop); delete.onClick.Add(DeleteNode);
			panel.AddContent(delete);
			
			(* add a button *)
			NEW(add); delete.bounds.SetExtents(200, 20); add.caption.SetAOC("Add Subnode");
			add.alignment.Set(WMComponents.AlignTop); add.onClick.Add(AddNode);
			panel.AddContent(add);
			
			(* add an editor *)
			NEW(editor); editor.bounds.SetHeight(30);
			editor.alignment.Set(WMComponents.AlignTop); editor.multiLine.Set(FALSE);
			editor.onEnter.Add(RenameNode);
			panel.AddContent(editor);
			
			FillTree;
			
			(* create the form window with panel size *)
			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), FALSE);
			SetContent(panel);
			editor.SetAsString("Sub-Element");

			SetTitle(Utilities.NewString("Hierarchy editor"));
			(* open the window *)
			WMWindowManager.DefaultAddWindow(SELF)
		END New;
		
		PROCEDURE NodeSelected(sender, data :PTR);
		VAR t : WMTrees.Tree; caption : String;
		BEGIN
			IF (data # NIL) & (data IS WMTrees.TreeNode) THEN 
				node := data(WMTrees.TreeNode);
				t := tree.GetTree();
				t.Acquire;
				caption := t.GetNodeCaption(node);
				t.Release;
				IF caption # NIL THEN editor.SetAsString(caption^) END
			END
		END NodeSelected;
		
		PROCEDURE DeleteNode(sender, data :PTR);
		VAR t : WMTrees.Tree;
		BEGIN
			IF node # NIL THEN 
				t := tree.GetTree();
				t.Acquire;
				t.RemoveNode(node);
				node := NIL;
				t.Release
			END
		END DeleteNode;
		
		PROCEDURE RenameNode(sender, data :PTR);
		VAR t : WMTrees.Tree; string : ARRAY 64 OF CHAR;
		BEGIN
			IF node # NIL THEN 
				t := tree.GetTree();
				t.Acquire;
				editor.GetAsString(string);
				t.SetNodeCaption(node, Utilities.NewString(string));
				t.Release
			END
		END RenameNode;
		
		PROCEDURE AddNode(sender, data :PTR);
		VAR t : WMTrees.Tree; new : WMTrees.TreeNode; string : ARRAY 64 OF CHAR;
		BEGIN
			IF node # NIL THEN 
				t := tree.GetTree();
				t.Acquire;
				NEW(new);
				t.AddChildNode(node, new);
				editor.GetAsString(string);
				t.SetNodeCaption(new, Utilities.NewString(string));
				t.Release
			END
		END AddNode;
		
		PROCEDURE FillTree;
		VAR t : WMTrees.Tree;
			root , sub: WMTrees.TreeNode;
		BEGIN
			t := tree.GetTree();
			t.Acquire;
			NEW(root); 
			t.SetRoot(root);
			t.InclNodeState(root, WMTrees.NodeAlwaysExpanded);
			t.SetNodeCaption(root, Utilities.NewString("Root"));
			
			NEW(sub);
			t.AddChildNode(root, sub); 
			t.SetNodeCaption(sub, Utilities.NewString("Sub"));
			
			t.Release
		END FillTree;
		
		PROCEDURE Close;
		BEGIN
			FreeWindow;
			Close^
		END Close;
		
	END Window;

VAR window : Window;

PROCEDURE FreeWindow;
BEGIN {EXCLUSIVE}
	window := NIL
END FreeWindow;

PROCEDURE Open*(par: PTR): PTR;
BEGIN {EXCLUSIVE}
	IF window = NIL THEN NEW(window)
	ELSE AosOut.String("Already open"); AosOut.Ln
	END;
	RETURN NIL
END Open;

PROCEDURE Cleanup;
BEGIN
	IF window # NIL THEN window.Close END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END TestTrees.

TestTrees.Open ~
S.Free TestTrees WMTrees ~
