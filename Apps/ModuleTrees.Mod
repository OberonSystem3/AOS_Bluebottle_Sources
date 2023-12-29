MODULE ModuleTrees;

IMPORT
	WMStandardComponents, WMGraphics, WMComponents, WMRectangles,
	WMTextView, WMEditors, Utilities, AosTextUtilities, AosTexts, WMBitmapFont,
	WMWindowManager, MultiLogger, WMGrids, WMTrees,
	StringPool, PCS, ModuleParser, UTF8Strings;
	
CONST
	TreeLabelCaption = "Tree View";
	TreeLabelCaptionError = "Tree View (Parse Error)";

TYPE
	TextInfo = OBJECT
	VAR
		pos: AosTexts.TextPosition;
		name: Utilities.String;
		color: LONGINT;
		font: WMGraphics.Font;
	END TextInfo;

	ModuleTree* = OBJECT (WMStandardComponents.Panel)
		VAR
			toolbar: WMStandardComponents.Panel;
			label: WMStandardComponents.Label;
			refreshBtn, sortBtn: WMStandardComponents.Button;
			treeView: WMTrees.TreeView;
			tree: WMTrees.Tree;
			editor: WMEditors.Editor;
			
		PROCEDURE & Init*();
		BEGIN
			Init^;
			
			NEW(label); label.alignment.Set(WMComponents.AlignTop);
			label.SetCaption(TreeLabelCaption); label.bounds.SetWidth(40); label.bounds.SetHeight(20);
			SELF.AddContent(label);
			
			NEW(toolbar); toolbar.alignment.Set(WMComponents.AlignTop);
			toolbar.bounds.SetHeight(20);
			SELF.AddContent(toolbar);
			
			NEW(treeView); treeView.alignment.Set(WMComponents.AlignClient);
			treeView.SetFont(treeFontOberon10Plain);
			SELF.AddContent(treeView);
			
			tree := treeView.GetTree();
			treeView.SetDrawNodeProc(DrawNode);
			treeView.onClickNode.Add(ClickNode);
			
			NEW(refreshBtn); refreshBtn.alignment.Set(WMComponents.AlignLeft);
			refreshBtn.caption.SetAOC("Refresh");
			refreshBtn.onClick.Add(RefreshHandler);
			toolbar.AddContent(refreshBtn);
			
			NEW(sortBtn); sortBtn.alignment.Set(WMComponents.AlignLeft);
			sortBtn.caption.SetAOC("Sort");
			sortBtn.onClick.Add(SortHandler);
			toolbar.AddContent(sortBtn);
		END Init;
		
		PROCEDURE SetEditor*(e: WMEditors.Editor);
		BEGIN
			editor := e;
		END SetEditor;
		
		PROCEDURE Erase*;
		BEGIN
			tree.Acquire;
			tree.SetRoot(NIL);
			tree.Release;
			treeView.SetFirstLine(0, TRUE);
			label.SetCaption(TreeLabelCaption);
		END Erase;
		
		PROCEDURE RefreshHandler*(sender, data: ANY);
		VAR
			module: ModuleParser.Module;
			scanner: PCS.Scanner;
			rootNode: WMTrees.TreeNode;
		BEGIN
			IF ~IsCallFromSequencer() THEN 
				sequencer.ScheduleEvent(SELF.RefreshHandler, sender, data);
				RETURN
			END;
			scanner := PCS.InitWithText(editor.text, 0);
			ModuleParser.Parse(scanner, module);
			IF module # NIL THEN
				tree.Acquire;
				editor.text.AcquireRead;
				NEW(rootNode);
				treeView.SetFirstLine(0, TRUE);
				tree.SetRoot(rootNode);
				tree.SetNodeData(rootNode, GetTextInfo(module.ident, treeView.clTextDefault.Get(), {}));
				tree.SetNodeCaption(rootNode, module.ident.name);
				AddImportList(rootNode, module.importList);
				AddDefinitions(rootNode, module.definitions);
				AddDeclSeq(rootNode, module.declSeq);
				tree.SetNodeState(rootNode, {WMTrees.NodeExpanded});
				editor.text.ReleaseRead;
				tree.Release;
				IF module.hasError THEN label.SetCaption(TreeLabelCaptionError);
				ELSE label.SetCaption(TreeLabelCaption);
				END;
			END;
		END RefreshHandler;
		
		PROCEDURE SortHandler(sender, data: ANY);
			VAR rootNode: WMTrees.TreeNode;
		BEGIN
			tree.Acquire;
			SortTree(tree.GetRoot());
			tree.Release;
		END SortHandler;
				
		PROCEDURE SortTree(parent: WMTrees.TreeNode);
		VAR
			n, left, right: WMTrees.TreeNode;
			nodeCount, i: LONGINT;
		BEGIN
			n := tree.GetChildren(parent);
			WHILE n # NIL DO
				SortTree(n);
				INC(nodeCount);
				n := tree.GetNextSibling(n);
			END;
			FOR i := 1 TO nodeCount-1 DO
				n := tree.GetChildren(parent);
				WHILE tree.GetNextSibling(n) # NIL DO
					left := n; right := tree.GetNextSibling(n);
					IF IsNodeGreater(left, right) THEN
						SwapSiblings(parent, left, right);
						n := left;
					ELSE
						n := right;
					END;
				END;
			END;
		END SortTree;
		
		PROCEDURE IsNodeGreater(left, right: WMTrees.TreeNode): BOOLEAN;
		VAR
			leftCaption, rightCaption, leftTmp, rightTmp: Utilities.String;
			leftData, rightData: ANY;
		BEGIN
			leftData := tree.GetNodeData(left);
			rightData := tree.GetNodeData(right);
			IF (leftData # NIL) & (rightData # NIL) &
				(leftData IS TextInfo) & (rightData IS TextInfo) &
				(leftData(TextInfo).color = rightData(TextInfo).color) &
				(leftData(TextInfo).font = rightData(TextInfo).font) THEN
					(* continue *)
			ELSE
				RETURN FALSE;
			END;
			leftCaption := tree.GetNodeCaption(left);
			rightCaption := tree.GetNodeCaption(right);
			IF (leftCaption^ = "VAR") OR (rightCaption^ = "VAR") OR
				(leftCaption^ = "CONST") OR (rightCaption^ = "CONST") OR
				(leftCaption^ = "IMPORT") OR (rightCaption^ = "IMPORT")
				THEN RETURN FALSE
			END;
			leftTmp := Utilities.NewString(leftCaption^);
			rightTmp := Utilities.NewString(rightCaption^);
			Utilities.TrimLeft(leftTmp^, '-');
			Utilities.TrimLeft(rightTmp^, '-');
			RETURN leftTmp^ > rightTmp^;
		END IsNodeGreater;
		
		PROCEDURE SwapSiblings(parent, left, right: WMTrees.TreeNode);
		BEGIN
			ASSERT(tree.GetNextSibling(left) = right);
			tree.RemoveNode(left);
			tree.AddChildNodeAfter(parent, right, left);
		END SwapSiblings;
		
		PROCEDURE DrawNode(canvas: WMGraphics.Canvas; w, h: LONGINT; node: WMTrees.TreeNode; state: SET);
		VAR i, dx, tdx, tdy : LONGINT; f : WMGraphics.Font;
			caption: Utilities.String;
			ptr: ANY;
		BEGIN
			dx := 0;
			f := treeView.GetFont();
			ptr := tree.GetNodeData(node);
			IF (ptr # NIL) & (ptr IS TextInfo) THEN
				canvas.SetColor(ptr(TextInfo).color);
				f := ptr(TextInfo).font;
				canvas.SetFont(f);
			ELSE
				canvas.SetColor(treeView.clTextDefault.Get());
				canvas.SetFont(treeView.GetFont());
			END;
			caption := tree.GetNodeCaption(node);
			f.GetStringSize(caption^, tdx, tdy);
			IF WMTrees.StateSelected IN state THEN
				canvas.Fill(WMGraphics.MakeRectangle(0, 0, dx + tdx, h), treeView.clSelected.Get(), WMGraphics.ModeSrcOverDst)
			ELSIF WMTrees.StateHover IN state THEN
				canvas.Fill(WMGraphics.MakeRectangle(0, 0, dx + tdx, h), treeView.clHover.Get(), WMGraphics.ModeSrcOverDst)
			END;
			IF caption # NIL THEN canvas.DrawString(dx, h - f.descent - 1 , caption^) END;
		END DrawNode;
		
		PROCEDURE ClickNode(sender, data : ANY);
		VAR
			d: ANY;
			textInfo: TextInfo;
		BEGIN
			IF (data # NIL) & (data IS WMTrees.TreeNode) THEN
				tree.Acquire;
				d := tree.GetNodeData(data(WMTrees.TreeNode));
				tree.Release;
				IF (d # NIL) & (d IS TextInfo) THEN
					textInfo := d(TextInfo);
					editor.tv.cursor.SetPosition(textInfo.pos.GetPosition());
					editor.tv.cursor.SetVisible(TRUE);
					editor.SetFocus();
				END
			END
		END ClickNode;
		
		PROCEDURE GetTextInfo(infoItem: ModuleParser.InfoItem; color: LONGINT; style: SET): TextInfo;
		VAR newInfo: TextInfo; font: WMGraphics.Font;
		BEGIN
			NEW(newInfo);
			newInfo.name := infoItem.name;
			newInfo.color := color;
			IF style = {} THEN
				font := treeFontOberon10Plain;
			ELSIF style = {WMGraphics.FontBold} THEN
				font := treeFontOberon10Bold;
			ELSIF style = {WMGraphics.FontItalic} THEN
				font := treeFontOberon10Italic;
			ELSE
				(* unknown style *)
				font := treeFontOberon10Plain;
			END;
			newInfo.font := font;
			NEW(newInfo.pos, editor.text);
			newInfo.pos.SetPosition(infoItem.pos);
			RETURN newInfo;
		END GetTextInfo;
		
		PROCEDURE AddImportList(parent: WMTrees.TreeNode; importList: ModuleParser.Import);
		VAR
			n: ModuleParser.Node;
			newNode, importNode: WMTrees.TreeNode;
			import: ModuleParser.Import;
		BEGIN
			n := importList;
			IF n # NIL THEN
				NEW(importNode);
				tree.SetNodeCaption(importNode, Utilities.NewString("IMPORT"));
				tree.AddChildNode(parent, importNode);
			END;
			WHILE n # NIL DO
				import := n(ModuleParser.Import);
				newNode := AddInfoItem(importNode, import.ident, treeView.clTextDefault.Get(), {});
				IF import.alias # NIL THEN
					AddPostfixToCaption(newNode, Utilities.NewString(" := "));
					AddPostfixToCaption(newNode, import.alias.name);
				END;
				n := n.next;
			END;
		END AddImportList;
		
		PROCEDURE AddDefinitions(parent: WMTrees.TreeNode; definitions: ModuleParser.Definition);
			VAR
			n, p: ModuleParser.Node;
			defNode, newNode: WMTrees.TreeNode;
		BEGIN
			n := definitions;
			WHILE n # NIL DO
				defNode := AddInfoItem(parent, n(ModuleParser.Definition).ident, WMGraphics.Green, {WMGraphics.FontItalic});
				p := n(ModuleParser.Definition).procs;
				WHILE p # NIL DO
					newNode := AddProcHead(defNode, p(ModuleParser.ProcHead));
					p := p.next;
				END;
				n := n.next;
			END;
		END AddDefinitions;
		
		PROCEDURE AddDeclSeq(parent: WMTrees.TreeNode; declSeq: ModuleParser.DeclSeq);
		VAR
			n: ModuleParser.Node;
			newNode: WMTrees.TreeNode;
		BEGIN
			n := declSeq;
			WHILE n # NIL DO
				declSeq := n(ModuleParser.DeclSeq);
				IF declSeq.constDecl # NIL THEN
					NEW(newNode);
					tree.SetNodeCaption(newNode, Utilities.NewString("CONST"));
					tree.AddChildNode(parent, newNode);
					AddConstDecl(newNode, declSeq.constDecl);
				END;
				IF declSeq.varDecl # NIL THEN
					NEW(newNode);
					tree.SetNodeCaption(newNode, Utilities.NewString("VAR"));
					tree.AddChildNode(parent, newNode);
					AddVarDecl(newNode, declSeq.varDecl);
				END;
				IF declSeq.typeDecl # NIL THEN
					(*
					NEW(newNode);
					tree.SetNodeCaption(newNode, Utilities.NewString("TYPE"));
					tree.AddChildNode(parent, newNode);
					*)
					AddTypeDecl((*newNode*)parent, declSeq.typeDecl);
				END;
				IF declSeq.procDecl # NIL THEN
					(*
					NEW(newNode);
					tree.SetNodeCaption(newNode, Utilities.NewString("PROCEDURE"));
					tree.AddChildNode(parent, newNode);
					*)
					AddProcDecl((*newNode*)parent, declSeq.procDecl);
				END;
				n := n.next;
			END;
		END AddDeclSeq;
		
		PROCEDURE AddProcDecl(treeNode: WMTrees.TreeNode; procDecl: ModuleParser.ProcDecl);
		VAR n: ModuleParser.Node;
			newNode: WMTrees.TreeNode;
		BEGIN
			n := procDecl;
			WHILE n # NIL DO
				procDecl := n(ModuleParser.ProcDecl);
				newNode := AddProcHead(treeNode, procDecl.head);
				IF (procDecl.declSeq # NIL) & (newNode # NIL) THEN
					AddDeclSeq(newNode, procDecl.declSeq);
				END;
				n := n.next;
			END;
		END AddProcDecl;
				
		PROCEDURE AddProcHead(treeNode: WMTrees.TreeNode; procHead: ModuleParser.ProcHead): WMTrees.TreeNode;
		VAR newNode: WMTrees.TreeNode; caption: Utilities.String;
		BEGIN
			IF procHead # NIL THEN
				newNode :=  AddIdentDef(treeNode, procHead.identDef, WMGraphics.Black, {WMGraphics.FontBold});
				IF procHead.operator THEN
					IF procHead.identDef.vis = ModuleParser.Public THEN
							(* remove visibility sign (ugly) *)
						caption := tree.GetNodeCaption(newNode);
						Utilities.TrimRight(caption^, '*');
					END;
					AddPrefixToCaption(newNode, Utilities.NewString('"'));
					AddPostfixToCaption(newNode, Utilities.NewString('"'));
					IF procHead.identDef.vis = ModuleParser.Public THEN
							(* add visibility sign (still ugly) *)
						AddPostfixToCaption(newNode, Utilities.NewString("*"));
					END;
				END;
				IF procHead.constructor THEN
					AddPrefixToCaption(newNode, Utilities.NewString("& "));
				END;
				IF procHead.inline THEN
					AddPrefixToCaption(newNode, Utilities.NewString("-"));
				END;
				AddFormalPars(newNode, procHead.formalPars);
				RETURN newNode;
			ELSE
				RETURN NIL;
			END
		END AddProcHead;
		
		PROCEDURE AddFormalPars(parent: WMTrees.TreeNode; formalPars: ModuleParser.FormalPars);
		VAR newNode, dummy: WMTrees.TreeNode;
			add:BOOLEAN;
		BEGIN
			IF formalPars # NIL THEN
				AddFPSection(parent, formalPars.fpSectionList);
				NEW(newNode);
				tree.SetNodeCaption(newNode, Utilities.NewString("RETURN"));
				IF formalPars.returnType # NIL THEN
					dummy := AddQualident(newNode, formalPars.returnType, treeView.clTextDefault.Get(), {});
					add := TRUE;
				ELSIF formalPars.returnTypeAry # NIL THEN
					AddArray(newNode, formalPars.returnTypeAry);
					add := TRUE;
				ELSIF formalPars.returnTypeObj # NIL THEN
					dummy := AddInfoItem(newNode, formalPars.returnTypeObj, treeView.clTextDefault.Get(), {});
					add := TRUE;
				END;
				IF add THEN
					tree.AddChildNode(parent, newNode);
				END;
			END;
		END AddFormalPars;
		
		PROCEDURE AddFPSection(parent: WMTrees.TreeNode; fpSection: ModuleParser.FPSection);
		VAR
			newNode: WMTrees.TreeNode;
			n, l: ModuleParser.Node;
		BEGIN
			n := fpSection;
			WHILE n # NIL DO
				l := n(ModuleParser.FPSection).identList;
				WHILE l # NIL DO
					newNode := AddIdentDef(parent, l(ModuleParser.IdentList).identDef, treeView.clTextDefault.Get(), {});
					IF n(ModuleParser.FPSection).var THEN
						AddPostfixToCaption(newNode, Utilities.NewString(" (VAR)"));
					END;
					AddType(newNode, n(ModuleParser.FPSection).type, FALSE);
					l := l.next;
				END;
				n := n.next;
			END;
		END AddFPSection;
		
		PROCEDURE AddVarDecl(parent: WMTrees.TreeNode; varDecl: ModuleParser.VarDecl);
		VAR n: ModuleParser.Node;
		BEGIN
			n := varDecl;
			WHILE n # NIL DO
				varDecl := n(ModuleParser.VarDecl);
				AddIdentList(parent, varDecl.identList);
				n := n.next;
			END;
		END AddVarDecl;
				
		PROCEDURE AddTypeDecl(parent: WMTrees.TreeNode; typeDecl: ModuleParser.TypeDecl);
		VAR
			n: ModuleParser.Node;
			newNode: WMTrees.TreeNode;
		BEGIN
			n := typeDecl;
			WHILE n # NIL DO
				newNode := AddIdentDef(parent, n(ModuleParser.TypeDecl).identDef, WMGraphics.Blue, {WMGraphics.FontItalic});
				AddType(newNode, n(ModuleParser.TypeDecl).type, FALSE);
				n := n.next;
			END;
		END AddTypeDecl;
				
		PROCEDURE AddType(parent: WMTrees.TreeNode; type: ModuleParser.Type; anonymous: BOOLEAN);
		VAR newNode: WMTrees.TreeNode;
		BEGIN
			IF type # NIL THEN
				IF type.qualident # NIL THEN
					newNode := AddQualident(parent, type.qualident, treeView.clTextDefault.Get(), {});
				ELSIF type.array # NIL THEN
					AddArray(parent, type.array);
				ELSIF type.record # NIL THEN
					AddRecord(parent, type.record, anonymous);
				ELSIF type.pointer # NIL THEN
					AddPointer(parent, type.pointer);
				ELSIF type.object # NIL THEN
					AddObject(parent, type.object, anonymous);
				ELSIF type.procedure # NIL THEN
					AddProcedure(parent, type.procedure);
				END;
			END;
		END AddType;
		
		PROCEDURE AddRecord(parent: WMTrees.TreeNode; record: ModuleParser.Record; anonymous: BOOLEAN);
		VAR p: WMTrees.TreeNode;
		BEGIN
			IF record # NIL THEN
				IF anonymous THEN p := NewNode(parent, Utilities.NewString("RECORD"));
				ELSE p := parent;
				END;
				IF record.super # NIL THEN
					AddPostfixToCaption(p, Utilities.NewString(" ("));
					AddPostfixToCaption(p, record.super.ident.name);
					AddPostfixToCaption(p, Utilities.NewString(")"));
				END;
				AddFieldDecl(p, record.fieldList);
			END;
		END AddRecord;
		
		PROCEDURE AddFieldDecl(parent: WMTrees.TreeNode; fieldDecl: ModuleParser.FieldDecl);
		VAR
			newNode: WMTrees.TreeNode;
			n, l: ModuleParser.Node;
		BEGIN
			n := fieldDecl;
			WHILE n # NIL DO
				l := n(ModuleParser.FieldDecl).identList;
				WHILE l # NIL DO
					newNode := AddIdentDef(parent, l(ModuleParser.IdentList).identDef, treeView.clTextDefault.Get(), {});
					AddType(newNode, n(ModuleParser.FieldDecl).type, FALSE);
					l := l.next;
				END;
				n := n.next;
			END;
		END AddFieldDecl;
		
		PROCEDURE AddPointer(parent: WMTrees.TreeNode; pointer: ModuleParser.Pointer);
		VAR newNode: WMTrees.TreeNode;
		BEGIN
			IF pointer # NIL THEN
				newNode := NewNode(parent, Utilities.NewString("POINTER TO"));
				AddType(newNode, pointer.type, TRUE);
			END;
		END AddPointer;
		
		PROCEDURE AddArray(parent: WMTrees.TreeNode; array: ModuleParser.Array);
		VAR newNode: WMTrees.TreeNode;
			caption: Utilities.String;
		BEGIN
			IF array # NIL THEN
				newNode := NewNode(parent, Utilities.NewString("ARRAY "));
				IF ~array.open THEN
					IF (array.len # NIL) & (array.len.name # NIL) THEN
						AddPostfixToCaption(newNode, array.len.name);
						AddPostfixToCaption(newNode, Utilities.NewString(" "));
					END;
				END;
				AddPostfixToCaption(newNode, Utilities.NewString("OF"));
				AddType(newNode, array.base, TRUE);
			END;
		END AddArray;
		
		PROCEDURE NewNode(parent: WMTrees.TreeNode; caption: Utilities.String): WMTrees.TreeNode;
		VAR newNode: WMTrees.TreeNode;
		BEGIN
			IF parent # NIL THEN
				NEW(newNode);
				tree.SetNodeCaption(newNode, caption);
				tree.AddChildNode(parent, newNode);
			END;
			RETURN newNode;
		END NewNode;
		
		PROCEDURE AddQualident(parent: WMTrees.TreeNode; qualident: ModuleParser.Qualident; color: LONGINT; style: SET):
				WMTrees.TreeNode;
		VAR newNode: WMTrees.TreeNode;
			n: ModuleParser.Node;
		BEGIN
			IF qualident # NIL THEN
				newNode := AddInfoItem(parent, qualident.ident, color, style);
				n := qualident.next;
				WHILE n # NIL DO
					AddPostfixToCaption(newNode, Utilities.NewString(", "));
					AddPostfixToCaption(newNode, n(ModuleParser.Qualident).ident.name);
					n := n.next;
				END;
			END;
			RETURN newNode;
		END AddQualident;
		
		PROCEDURE AddObject(parent: WMTrees.TreeNode; object: ModuleParser.Object; anonymous: BOOLEAN);
		VAR newNode, p: WMTrees.TreeNode;
		BEGIN
			IF object # NIL THEN
				IF anonymous THEN p := NewNode(parent, Utilities.NewString("OBJECT"));
				ELSE p := parent;
				END;
				IF object.super # NIL THEN
					AddPostfixToCaption(p, Utilities.NewString(" ("));
					AddPostfixToCaption(p, object.super.ident.name);
					AddPostfixToCaption(p, Utilities.NewString(")"));
					(*
					newNode := AddQualident(parent, object.super, treeView.clTextDefault.Get(), {});
					AddPrefixToCaption(newNode, Utilities.NewString("Extends "));
					*)
				END;
				IF object.implements # NIL THEN
					newNode := AddQualident(p, object.implements, treeView.clTextDefault.Get(), {});
					AddPrefixToCaption(newNode, Utilities.NewString("Implements "));
				END;
				IF object.declSeq # NIL THEN
					AddDeclSeq(parent, object.declSeq)
				END	
			END;
		END AddObject;
		
		PROCEDURE AddProcedure(parent: WMTrees.TreeNode; proc: ModuleParser.Procedure);
		VAR newNode: WMTrees.TreeNode;
		BEGIN
			IF proc # NIL THEN
				newNode := NewNode(parent, Utilities.NewString("PROCEDURE"));
				IF proc.delegate THEN AddPostfixToCaption(newNode, Utilities.NewString(" {DELEGATE}")) END;
				AddFormalPars(newNode, proc.formalPars);
			END;
		END AddProcedure;
		
		PROCEDURE PrefixPostfixToCaption(node: WMTrees.TreeNode; prePost: Utilities.String; prefix: BOOLEAN);
		VAR
			oldCaption, newCaption: Utilities.String;
			len: LONGINT;
		BEGIN
			oldCaption := tree.GetNodeCaption(node);
			len := LEN(oldCaption^) + LEN(prePost^);
			NEW(newCaption, len);
			IF prefix THEN
				Utilities.Concat(prePost^, oldCaption^, newCaption^);
			ELSE
				Utilities.Concat(oldCaption^, prePost^, newCaption^);
			END;
			tree.SetNodeCaption(node, newCaption);
		END PrefixPostfixToCaption;
		
		PROCEDURE AddPrefixToCaption(node: WMTrees.TreeNode; prefix: Utilities.String);
		BEGIN
			PrefixPostfixToCaption(node, prefix, TRUE);
		END AddPrefixToCaption;
		
		PROCEDURE AddPostfixToCaption(node: WMTrees.TreeNode; postfix: Utilities.String);
		BEGIN
			PrefixPostfixToCaption(node, postfix, FALSE);
		END AddPostfixToCaption;
		
		PROCEDURE AddIdentList(parent: WMTrees.TreeNode; identList: ModuleParser.IdentList);
		VAR
			n: ModuleParser.Node;
			newNode: WMTrees.TreeNode;
		BEGIN
			n := identList;
			WHILE n # NIL DO
				newNode := AddIdentDef(parent, n(ModuleParser.IdentList).identDef, treeView.clTextDefault.Get(), {});
				n := n.next;
			END;
		END AddIdentList;
				
		PROCEDURE AddConstDecl(parent: WMTrees.TreeNode; constDecl: ModuleParser.ConstDecl);
		VAR
			n: ModuleParser.Node;
			newNode: WMTrees.TreeNode;
		BEGIN
			n := constDecl;
			WHILE n # NIL DO
				newNode := AddIdentDef(parent, n(ModuleParser.ConstDecl).identDef, treeView.clTextDefault.Get(), {});
				newNode := AddInfoItem(newNode, n(ModuleParser.ConstDecl).expr, treeView.clTextDefault.Get(), {});
				n := n.next;
			END;
		END AddConstDecl;
				
		PROCEDURE AddIdentDef(parent: WMTrees.TreeNode; identDef: ModuleParser.IdentDef; color: LONGINT; style: SET):
			WMTrees.TreeNode;
		VAR
			newNode: WMTrees.TreeNode;
		BEGIN
			IF identDef # NIL THEN
				newNode := AddInfoItem(parent, identDef.ident, color, style);
				IF identDef.vis = ModuleParser.Public THEN
					AddPostfixToCaption(newNode, Utilities.NewString("*"));
				ELSIF identDef.vis = ModuleParser.PublicRO THEN
					AddPostfixToCaption(newNode, Utilities.NewString("-"));
				END;
				RETURN newNode;
			ELSE
				RETURN NIL;
			END
		END AddIdentDef;
		
		PROCEDURE AddInfoItem(parent: WMTrees.TreeNode; infoItem: ModuleParser.InfoItem; color: LONGINT; style: SET):
			WMTrees.TreeNode;
		VAR newNode: WMTrees.TreeNode;
		BEGIN
			IF (infoItem # NIL) & (parent # NIL) THEN
				NEW(newNode);
				tree.SetNodeData(newNode, GetTextInfo(infoItem, color, style));
				tree.SetNodeCaption(newNode, infoItem.name);
				tree.AddChildNode(parent, newNode);
			END;
			RETURN newNode;
		END AddInfoItem;
		
	END ModuleTree;

VAR
	treeFontOberon10Plain, treeFontOberon10Bold, treeFontOberon10Italic: WMGraphics.Font;
	
BEGIN
	treeFontOberon10Plain := WMGraphics.GetFont("Oberon", 10, {});
	treeFontOberon10Bold := WMGraphics.GetFont("Oberon", 10, {WMGraphics.FontBold});
	treeFontOberon10Italic := WMGraphics.GetFont("Oberon", 10, {WMGraphics.FontItalic});
END ModuleTrees.
