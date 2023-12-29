MODULE WMTrees;	(** AUTHOR "TF"; PURPOSE "Tree component"; *)

IMPORT
	WMWindowManager, AosOut, AosActive, AosModules, WMComponents, WMGraphics, UTF8Strings,
	WMStandardComponents, WMMessages, WMProperties, WMEvents, Rect := WMRectangles, Utilities, AosInputs;

CONST
	NodeExpanded* = 0;
	NodeSubnodesUnknown* = 1;
	NodeAlwaysExpanded* = 2;
	
	StateSelected* = 0;
	StateHover* = 1;
	StateHasSubNodes* = 2;
	
	DefaultHeight = 25;

TYPE
	String = Utilities.String;
	
	(** TreeNode may not be shared between processes *)
	TreeNode* = OBJECT
	VAR 
		state : SET;
		parent, prevSibling, nextSibling, firstChild, lastChild : TreeNode;
		caption : String; 
		img : WMGraphics.Image; 
		data : PTR;
		inTree : BOOLEAN;
		
		PROCEDURE &Init;
		BEGIN
			inTree := FALSE
		END Init;
		
		PROCEDURE AddChild(x : TreeNode);
		BEGIN
			x.parent := SELF;
			IF lastChild = NIL THEN lastChild := x; firstChild := x;  x.prevSibling := NIL; x.nextSibling := NIL
			ELSE lastChild.nextSibling := x; x.prevSibling := lastChild; lastChild := x; x.nextSibling := NIL
			END
		END AddChild;
		
		PROCEDURE AddChildAfter(prev, x : TreeNode);
		BEGIN
			IF (lastChild = NIL) THEN AddChild(x)
			ELSE
				x.parent := SELF;
				x.nextSibling := prev.nextSibling;
				x.prevSibling := prev;
				prev.nextSibling := x;
				IF x.nextSibling # NIL THEN x.nextSibling.prevSibling := x ELSE lastChild := x END
			END
		END AddChildAfter;
		
		PROCEDURE AddChildBefore(next, x : TreeNode);
		BEGIN
			IF (lastChild = NIL) THEN AddChild(x)
			ELSE
				x.parent := SELF;
				IF next = firstChild THEN
					x.nextSibling := firstChild;
					x.prevSibling := NIL;
					firstChild := x
				ELSE
					x.nextSibling := next;
					x.prevSibling := next.prevSibling;
					next.prevSibling.nextSibling := x;
					next.prevSibling := x
				END
			END
		END AddChildBefore;
		
		PROCEDURE Remove;
		BEGIN
			IF SELF = parent.firstChild THEN parent.firstChild := parent.firstChild.nextSibling END;
			IF SELF = parent.lastChild THEN parent.lastChild := parent.lastChild.prevSibling END;
			IF prevSibling # NIL THEN prevSibling.nextSibling := nextSibling END;
			IF nextSibling # NIL THEN nextSibling.prevSibling := prevSibling END;
			parent := NIL; prevSibling := NIL; nextSibling := NIL;
			inTree := FALSE
		END Remove;
		
	END TreeNode;

	DrawNodeProc = PROCEDURE {DELEGATE} (canvas : WMGraphics.Canvas; w, h : LONGINT; node : TreeNode; state : SET);
	MeasureNodeProc = PROCEDURE {DELEGATE} (node : TreeNode; VAR w, h : LONGINT);
	
	(* Tree structure that can be visualized in the TreeView. No node may be inserted more than once.
		Before manipulating or querying, the tree must be locked with Acquire *)
TYPE
	Tree* = OBJECT
	VAR root : TreeNode;
		lockedBy : PTR;
		lockLevel : LONGINT;
		viewChanged : BOOLEAN;
		onChanged* : WMEvents.EventSource; (** does not hold the lock, if called *)
		beforeExpand* : WMEvents.EventSource; (** does hold the lock, if called *)
		
		PROCEDURE &Init;
		BEGIN
			NEW(onChanged, SELF, WMComponents.NewString("TreeModelChanged"), NIL, NIL);
			NEW(beforeExpand, SELF, WMComponents.NewString("BeforeExpand"), NIL, NIL);
			lockLevel :=0 
		END Init;
		
		(** acquire a read/write lock on the object *)
		PROCEDURE Acquire*;
		VAR me : PTR;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			IF lockedBy = me THEN
				ASSERT(lockLevel # -1);	(* overflow *)
				INC(lockLevel)
			ELSE
				AWAIT(lockedBy = NIL); viewChanged := FALSE;
				lockedBy := me; lockLevel := 1
			END
		END Acquire;
		
		(** release the read/write lock on the object *)
		PROCEDURE Release*;
		VAR haschanged : BOOLEAN;
		BEGIN 
			BEGIN {EXCLUSIVE}
				ASSERT(lockedBy = AosActive.ActiveObject(), 3000);
				haschanged := FALSE;
				DEC(lockLevel);
				IF lockLevel = 0 THEN lockedBy := NIL; haschanged := viewChanged END
			END;
			IF haschanged THEN onChanged.Call(NIL) END
		END Release;
	
		(** Set the root node of the tree. All this reinitializes the tree.*)
		PROCEDURE SetRoot*(x : TreeNode);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			root := x; viewChanged := TRUE
		END SetRoot;
		
		(** Get the tree root *)
		PROCEDURE GetRoot*() : TreeNode;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			RETURN root
		END GetRoot;
		
		(** Add a child node to parent *)
		PROCEDURE AddChildNode*(parent, node : TreeNode);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			ASSERT(~node.inTree, 4000);
			parent.AddChild(node); node.inTree := TRUE; viewChanged := TRUE
		END AddChildNode;
		
		(** Add a child node to parent *)
		PROCEDURE AddChildNodeAfter*(parent,  prev, node : TreeNode);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			ASSERT(~node.inTree, 4000);
			parent.AddChildAfter(prev, node); node.inTree := TRUE; viewChanged := TRUE
		END AddChildNodeAfter;
		
		(** Add a child node to parent *)
		PROCEDURE AddChildNodeBefore*(parent,  next, node : TreeNode);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			ASSERT(~node.inTree, 4000);
			parent.AddChildBefore(next, node); node.inTree := TRUE; viewChanged := TRUE
		END AddChildNodeBefore;
		
		(** Remove a node (including all sub nodes) *)
		PROCEDURE RemoveNode*(node : TreeNode);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = root THEN root := NIL
			ELSE node.Remove
			END; viewChanged := TRUE
		END RemoveNode;
		
		(** expand all parent nodes up to the root so that node is visible *)
		PROCEDURE ExpandToRoot*(node : TreeNode);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			WHILE node.parent # NIL DO INCL(node.parent.state, NodeExpanded); node := node.parent END; 
			viewChanged := TRUE
		END ExpandToRoot;
		
		(** Get the next sibling of a node *)
		PROCEDURE GetNextSibling*(node : TreeNode) : TreeNode;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN NIL END;
			RETURN node.nextSibling
		END GetNextSibling;
		
		(** Get the previous sibling of a node *)
		PROCEDURE GetPrevSibling*(node : TreeNode) : TreeNode;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN NIL END;
			RETURN node.prevSibling
		END GetPrevSibling;
		
		(** Get the first child node *)
		PROCEDURE GetChildren*(node : TreeNode) : TreeNode;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN NIL END;
			RETURN node.firstChild
		END GetChildren;
		
		(** Get the last child node *)
		PROCEDURE GetLastChild*(node : TreeNode) : TreeNode;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN NIL END;
			RETURN node.lastChild
		END GetLastChild;
		
		(** Get parent of node *)
		PROCEDURE GetParent*(node : TreeNode) : TreeNode;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN NIL END;
			RETURN node.parent
		END GetParent;
		
		(** Set node state *)
		PROCEDURE SetNodeState*(node : TreeNode; state : SET);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN END;
			IF ~(NodeExpanded IN node.state) & (NodeExpanded IN state) THEN
				beforeExpand.Call(node);
				IF GetChildren(node) = NIL THEN EXCL(state, NodeExpanded) END;
			END;
			IF NodeAlwaysExpanded IN state THEN INCL(state, NodeExpanded) END;
			IF node.state # state THEN
				viewChanged := TRUE;
				node.state := state
			END	
		END SetNodeState;
		
		(** Incl node state *)
		PROCEDURE InclNodeState*(node : TreeNode; state : LONGINT);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN END;
			IF ~(NodeExpanded IN node.state) & (state = NodeExpanded) THEN
				beforeExpand.Call(node);
				IF GetChildren(node) = NIL THEN RETURN END
			END;
			IF state = NodeAlwaysExpanded THEN INCL(node.state, NodeExpanded) END;
			viewChanged := TRUE;
			INCL(node.state, state)
		END InclNodeState;
		
		(**Excl node state *)
		PROCEDURE ExclNodeState*(node : TreeNode; state : LONGINT);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN END;
			viewChanged := TRUE;
			EXCL(node.state, state);
			IF NodeAlwaysExpanded IN node.state THEN INCL(node.state, NodeExpanded) END
		END ExclNodeState;
		
		(** Get node state *)
		PROCEDURE GetNodeState*(node : TreeNode) : SET;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN {} END;
			RETURN node.state
		END GetNodeState;
		
		PROCEDURE SetNodeCaption*(node : TreeNode; caption : String);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN END;
			viewChanged := TRUE;
			node.caption := caption
		END SetNodeCaption;
		
		PROCEDURE GetNodeCaption*(node : TreeNode) : String;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN NIL END;
			RETURN node.caption
		END GetNodeCaption;
		
		PROCEDURE SetNodeImage*(node : TreeNode; i : WMGraphics.Image);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN END;
			viewChanged := TRUE;
			node.img := i
		END SetNodeImage;
		
		PROCEDURE GetNodeImage*(node : TreeNode) : WMGraphics.Image;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN NIL END;
			RETURN node.img
		END GetNodeImage;
		
		PROCEDURE SetNodeData*(node : TreeNode; data : PTR);
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN END;
			node.data := data
		END SetNodeData;
		
		PROCEDURE GetNodeData*(node : TreeNode) : PTR;
		BEGIN
			ASSERT(AosActive.ActiveObject() = lockedBy, 3000);
			IF node = NIL THEN RETURN NIL END;
			RETURN node.data
		END GetNodeData;
		
	END Tree;

	(* Tree view component *)
TYPE
	TreeView* = OBJECT (WMComponents.VisualComponent)
	VAR tree : Tree;
		firstLine, lines : LONGINT;
		vscrollbar, hscrollbar : WMStandardComponents.Scrollbar;
		drawNode : DrawNodeProc;
		measureNode : MeasureNodeProc;
		selectedNode, hoverNode : TreeNode;
		selecting : BOOLEAN;
		cs : WMGraphics.CanvasState;
		hindent, indent, hdelta : LONGINT;
		onSelectNode-, onExpandNode-, onClickNode- : WMEvents.EventSource;
		clHover*, clSelected*, 
		clTextDefault*, clTextHover*, clTextSelected* : WMProperties.ColorProperty;
		fontHeight* : WMProperties.Int32Property;
		
	
		PROCEDURE &Init;
		VAR root, t, t1, t2 : TreeNode;
			i : LONGINT;
		BEGIN
			Init^;
			NEW(clHover, PrototypeTclHover, NIL, NIL); properties.Add(clHover);
			NEW(clSelected, PrototypeTclSelected, NIL, NIL); properties.Add(clSelected);
			NEW(clTextDefault, PrototypeTclTextDefault, NIL, NIL); properties.Add(clTextDefault);
			NEW(clTextHover, PrototypeTclTextHover, NIL, NIL); properties.Add(clTextHover);
			NEW(clTextSelected, PrototypeTclTextSelected,  NIL, NIL); properties.Add(clTextSelected);
			NEW(fontHeight, PrototypeTfontHeight, NIL, NIL); properties.Add(fontHeight);	
			takesFocus.Set(TRUE);
			NEW(tree);

			(* Events *)
			NEW(onSelectNode, SELF, Utilities.NewString("onSelectNode"), Utilities.NewString("if node selected"), 
			SELF.StringToCompCommand); 
			events.Add(onSelectNode);

			NEW(onExpandNode, SELF, Utilities.NewString("onExpandNode"), Utilities.NewString("if node expanded"), 
			SELF.StringToCompCommand); 
			
			NEW(onClickNode, SELF, Utilities.NewString("onClickNode"), Utilities.NewString("if node clicked"), 
			SELF.StringToCompCommand); 
			events.Add(onClickNode);

			(* Scrollbar *)
			NEW(vscrollbar); vscrollbar.alignment.Set(WMComponents.AlignRight);
			AddContent(vscrollbar); vscrollbar.onPositionChanged.Add(ScrollbarChanged);
			NEW(hscrollbar); hscrollbar.alignment.Set(WMComponents.AlignBottom); hscrollbar.vertical.Set(FALSE);
			AddContent(hscrollbar); hscrollbar.onPositionChanged.Add(ScrollbarChanged);
			SetMeasureNodeProc(MeasureNode);
			SetDrawNodeProc(DrawNode);
			SetIndent(30);
			hdelta := 0
		END Init;
		
		PROCEDURE FocusReceived*;
		BEGIN FocusReceived^
		END FocusReceived;
		
		PROCEDURE FocusLost*;
		BEGIN FocusLost^
		END FocusLost;
		
		PROCEDURE SetIndent*(indent : LONGINT);
		BEGIN
			Acquire;
			IF indent # SELF.indent THEN
				SELF.indent := indent; hindent := indent DIV 2;
				hscrollbar.pageSize.Set(indent);
				Invalidate
			END;
			Release
		END SetIndent;
		
		(** Return the tree. All modifications are performed on the tree *)
		PROCEDURE GetTree*() : Tree;
		BEGIN
			RETURN tree
		END GetTree;
		
		PROCEDURE Initialize;
		BEGIN
			Initialize^;
			Invalidate;
			tree.onChanged.Add(TreeChanged)
		END Initialize;
		
		PROCEDURE TreeChanged*(sender, data : PTR);
		VAR width, t : LONGINT;
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.TreeChanged, sender, data)
			ELSE
				MeasureTree(lines, width);
				vscrollbar.max.Set(lines - 1);
				IF vscrollbar.pos.Get() >=  lines THEN vscrollbar.pos.Set(lines - 1) END;
				t := width - (bounds.GetWidth() - vscrollbar.bounds.GetWidth());
				IF t > 0 THEN 
					hscrollbar.visible.Set(TRUE);
					hscrollbar.max.Set(t)
				ELSE
					hdelta := 0;
					hscrollbar.visible.Set(FALSE)
				END;	
				Invalidate
			END
		END TreeChanged;
		
		PROCEDURE SetFirstLine*(line : LONGINT; adjustScrollbar : BOOLEAN);
		BEGIN
			Acquire;
			firstLine := line; 
			IF adjustScrollbar THEN vscrollbar.pos.Set(line) END;
			Release;
			Invalidate
		END SetFirstLine;
		
		PROCEDURE SetDrawNodeProc*(x : DrawNodeProc);
		BEGIN
			Acquire;
			drawNode := x;
			Acquire;
			Invalidate
		END SetDrawNodeProc;
		
		PROCEDURE SetMeasureNodeProc*(x : MeasureNodeProc);
		BEGIN
			Acquire;
			measureNode := x;
			Acquire;
			Invalidate
		END SetMeasureNodeProc;

		PROCEDURE MeasureTree(VAR lines, width : LONGINT);
		VAR cury : LONGINT;
		
			PROCEDURE RenderTree(x : TreeNode; level : LONGINT);
			VAR a : TreeNode;
				w, h : LONGINT;
			BEGIN
				IF x = NIL THEN RETURN END;
				INC(lines);
				h := DefaultHeight; w := bounds.GetWidth();
				IF measureNode # NIL THEN measureNode(x, w, h) END;
				width := Utilities.Max(width, w + level * indent);
				INC(cury, h);
				IF NodeExpanded IN x.state THEN 
					a := tree.GetChildren(x);
					WHILE a # NIL DO
						RenderTree(a, level + 1);
						a := tree.GetNextSibling(a)
					END
				END	
			END RenderTree;
			
		BEGIN
			tree.Acquire;
			cury := 0; lines := 0; width := 0;
			RenderTree(tree.GetRoot(), 0);
			tree.Release
		END MeasureTree;
		
		(** default DrawNode, can be replaced with SetDrawNodeMethod *)
		PROCEDURE DrawNode(canvas : WMGraphics.Canvas; w, h : LONGINT; node : TreeNode; state : SET);
		VAR i, dx, tdx, tdy : LONGINT; f : WMGraphics.Font;
		BEGIN
			dx := 0;
			f := GetFont();
			IF node.img # NIL THEN 
				canvas.DrawImage(0, 0, node.img, WMGraphics.ModeSrcOverDst); dx := node.img.width + 5;
			END;
			canvas.SetFont(f);
			IF StateSelected IN state THEN canvas.SetColor(clTextSelected.Get())
			ELSIF StateHover IN state THEN canvas.SetColor(clTextHover.Get())
			ELSE canvas.SetColor(clTextDefault.Get())
			END;
			f.GetStringSize(node.caption^, tdx, tdy);
			IF StateSelected IN state THEN canvas.Fill(WMGraphics.MakeRectangle(0, 0, dx + tdx, h), clSelected.Get(), WMGraphics.ModeSrcOverDst)
			ELSIF StateHover IN state THEN canvas.Fill(WMGraphics.MakeRectangle(0, 0, dx + tdx, h), clHover.Get(), WMGraphics.ModeSrcOverDst)
			END;
			IF node.caption # NIL THEN canvas.DrawString(dx, h - f.descent -1, node.caption^) END;
		END DrawNode;
		
		(** default MeasuereNode, can be replaced with SetMeasureNodeMethod *)
		PROCEDURE MeasureNode*(node : TreeNode; VAR w, h : LONGINT);
		VAR dx, dy : LONGINT; f : WMGraphics.Font; 
		BEGIN
			w := 0; h := 0;
			f := WMGraphics.GetDefaultFont();
			IF node.img # NIL THEN w := node.img.width + 5; h := node.img.height END;
			IF node.caption # NIL THEN 
				f.GetStringSize(node.caption^, dx, dy); dy := f.GetHeight() + 2;
				w := w + dx;
				IF dy > h THEN h := dy END
			END
		END MeasureNode;
		
		PROCEDURE RenderTreeNode(canvas : WMGraphics.Canvas; y, h : LONGINT; node : TreeNode; level : LONGINT);
		VAR x, i, px, py : LONGINT; t : TreeNode;  height, color : LONGINT;
			state : SET;
		BEGIN
			canvas.RestoreState(cs);
			i := level; height := h;
			
			(* draw the vertical lines *)
			x := hindent + (level - 1) * indent - hdelta;
			t := node;
			(* on each level *)
			WHILE i > 0 DO
				(* vertical line is needed if node/parent on level has a next sibling *)
				IF tree.GetNextSibling(t) # NIL THEN canvas.Line(x, y, x, y + height, 0FFH, WMGraphics.ModeCopy) END;
				t := tree.GetParent(t);
				ASSERT(t # NIL);
				DEC(i); DEC(x, indent) 
			END;
			x := level * indent - hdelta;
			(* if the current node is the last in chain it needs half a vertical line *)
			IF tree.GetNextSibling(node) = NIL THEN 
				canvas.Line(x - hindent, y, x - hindent, y + height DIV 2, 0FFH, WMGraphics.ModeCopy)
			END;
			(* draw small horizontal line if not root node *)			
			IF level > 0 THEN canvas.Line(x - hindent, y + height DIV 2, x - 5, y + height DIV 2, 0FFH, WMGraphics.ModeCopy) END;
			
			IF level > 0 THEN 
				state := tree.GetNodeState(node);
				IF ((tree.GetChildren(node) # NIL) OR (NodeSubnodesUnknown IN state)) & ~(NodeAlwaysExpanded IN state) THEN
					(* draw a plus sign *)
					px := x - hindent; py := y + height DIV 2;
					IF ~(NodeSubnodesUnknown IN state) THEN color := 0FFFFFFFFH ELSE color := 0808080FFH END;
					canvas.Fill(Rect.MakeRect(px - 5, py - 5, px +  5 + 1, py + 5 + 1), 0FFH, WMGraphics.ModeCopy);
					canvas.Fill(Rect.MakeRect(px - 4, py - 4, px +  4 + 1, py + 4 + 1), color, WMGraphics.ModeCopy);
					canvas.Line(px - 2, py , px + 2 + 1, py, 00000FFFFH, WMGraphics.ModeCopy);
					IF ~(NodeExpanded IN state) THEN (* | of the + *)
						canvas.Line(px, py - 2 , px, py + 2 + 1, 00000FFFFH, WMGraphics.ModeCopy)
					END;
				END
			END; 
						
			IF drawNode # NIL THEN 
				canvas.SetClipRect(WMGraphics.MakeRectangle(x, y, bounds.GetWidth(), y + height)); 
				canvas.ClipRectAsNewLimits(x, y);
				state := {};
				IF node = selectedNode THEN INCL(state, StateSelected) END;
				IF node = hoverNode THEN INCL(state, StateHover) END; 
				drawNode(canvas, bounds.GetWidth() - x, height, node, state)
			END	
		END RenderTreeNode;
		
		(* draw tree *)
		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		VAR y, height, i : LONGINT; clip : Rect.Rectangle;
		
			PROCEDURE RenderTree(x : TreeNode; level : LONGINT);
			VAR a : TreeNode; w, h : LONGINT; t: Rect.Rectangle;
			BEGIN
				IF x = NIL THEN RETURN END;
				INC(i);
				IF y > height THEN RETURN END;
				IF i > firstLine THEN
					h := DefaultHeight; w := bounds.GetWidth();
					IF measureNode # NIL THEN measureNode(x, w, h) END;
					t := Rect.MakeRect(0, y, w, y + h);
					IF Rect.Intersect(clip, t) THEN
						RenderTreeNode(canvas, y, h, x, level);
					END;	
					INC(y, h)
				END;
				IF NodeExpanded IN x.state THEN 
					a := tree.GetChildren(x);
					WHILE a # NIL DO
						RenderTree(a, level + 1);
						a := tree.GetNextSibling(a)
					END
				END	
			END RenderTree;
			
		BEGIN
			tree.Acquire;
			height := bounds.GetHeight();
			canvas.GetClipRect(clip);
			y := 0;
			canvas.SaveState(cs);
			RenderTree(tree.GetRoot(), 0);
			canvas.RestoreState(cs);
			tree.Release
		END DrawBackground;
	
		(** Return the TreeNode at the position x, y *)
		PROCEDURE GetNodeAtPos*(x, y : LONGINT) : TreeNode;
		VAR cury, i, height : LONGINT;
				found : TreeNode;
		
			PROCEDURE RenderTree(x : TreeNode; level : LONGINT);
			VAR a : TreeNode;
				w, h : LONGINT;
			BEGIN
				IF x = NIL THEN RETURN END;	
				INC(i); IF cury > height THEN RETURN END;
				IF i > firstLine THEN
					h := DefaultHeight; w := bounds.GetWidth();
					IF measureNode # NIL THEN measureNode(x, w, h) END;
					INC(cury, h)
				END;
				IF cury >= y THEN found := x; RETURN END;
				IF NodeExpanded IN x.state THEN 
					a := tree.GetChildren(x);
					WHILE a # NIL DO
						IF found = NIL THEN RenderTree(a, level + 1) END;
						a := tree.GetNextSibling(a)
					END
				END	
			END RenderTree;
			
		BEGIN
			tree.Acquire;
			found := NIL;
			height := bounds.GetHeight();
			cury := 0; i := 0;
			RenderTree(tree.GetRoot(), 0);
			tree.Release;
			RETURN found
		END GetNodeAtPos;
		
		PROCEDURE GetNextVisibleNode(this : TreeNode; ignoreChildren : BOOLEAN) : TreeNode;
		VAR state : SET;
		BEGIN
			state := tree.GetNodeState(this);
			IF ~ignoreChildren & (NodeExpanded IN state) & (tree.GetChildren(this) # NIL) THEN RETURN tree.GetChildren(this);
			ELSIF tree.GetNextSibling(this) # NIL THEN RETURN tree.GetNextSibling(this);
			ELSIF tree.GetParent(this) # NIL THEN RETURN GetNextVisibleNode(tree.GetParent(this), TRUE)
			ELSE RETURN NIL
			END;
		END GetNextVisibleNode;
		
		PROCEDURE GetPrevVisibleNode(this : TreeNode) : TreeNode;
		VAR state : SET; temp : TreeNode;
		BEGIN
			state := tree.GetNodeState(this);
			temp := tree.GetPrevSibling(this);
			IF (temp # NIL) THEN 
				IF (NodeExpanded IN tree.GetNodeState(temp)) & (tree.GetChildren(temp) # NIL) THEN
					RETURN tree.GetLastChild(temp)
				ELSE RETURN temp
				END
			ELSIF tree.GetParent(this) # NIL THEN RETURN tree.GetParent(this)
			ELSE RETURN NIL
			END;
		END GetPrevVisibleNode; 
		
		PROCEDURE KeyEvent*(ucs : LONGINT; flags : SET; VAR keysym : LONGINT);
		VAR selNode : TreeNode;
			PROCEDURE Up;
			BEGIN
				tree.Acquire; selNode := GetPrevVisibleNode(selectedNode); tree.Release;
				IF selNode # NIL THEN selectedNode := selNode; Invalidate; onSelectNode.Call(selectedNode) END
			END Up;
			
			PROCEDURE Down;
			BEGIN
				tree.Acquire; selNode := GetNextVisibleNode(selectedNode, FALSE); tree.Release;
				IF selNode # NIL THEN selectedNode := selNode; Invalidate; onSelectNode.Call(selectedNode) END
			END Down;
			
		BEGIN
			IF ~ (AosInputs.Release IN flags) THEN
				IF (keysym = 0FF54H) THEN Down (* cursor down *)
				ELSIF (keysym = 0FF52H) THEN Up(* cursor up *)
				ELSIF (keysym = 0FF51H) THEN (* cursor left *)
					tree.Acquire; 
					IF NodeExpanded IN tree.GetNodeState(selectedNode) THEN 
						tree.ExclNodeState(selectedNode, NodeExpanded)
					ELSE Up
					END; tree.Release;
				ELSIF (keysym = 0FF53H) THEN (* cursor right *)
					tree.Acquire; 
					IF (NodeExpanded IN tree.GetNodeState(selectedNode)) OR (tree.GetChildren(selectedNode) = NIL) THEN Down 
					ELSE tree.InclNodeState(selectedNode, NodeExpanded)
					END; tree.Release;
				END
			END
		END KeyEvent;
		
		PROCEDURE PointerDown(x, y : LONGINT; keys : SET);
		BEGIN
			ASSERT(IsCallFromSequencer());
			selecting := 0 IN keys;
			IF keys = {2} THEN ShowContextMenu(x, y) END
		END PointerDown;
		
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET);
		VAR new : TreeNode;
		BEGIN
			new := GetNodeAtPos(x, y);
			IF new # hoverNode THEN
				hoverNode := new;
				Invalidate
			END	
		END PointerMove;
		
		PROCEDURE ClickNode*(node : TreeNode);
		BEGIN
			onClickNode.Call(node);
		END ClickNode;
		
		PROCEDURE PointerUp(x, y : LONGINT; keys : SET);
		VAR new : TreeNode; tn : TreeNode; w : LONGINT;
		BEGIN
			tree.Acquire;
			IF selecting & ~(0 IN keys)  THEN
				new := GetNodeAtPos(x, y);
				IF new # NIL THEN
					ClickNode(new);
					tn := new.parent; WHILE tn # NIL DO tn := tn.parent; INC(w, indent) END;
					IF x + hdelta  < w THEN 						
						IF NodeExpanded IN tree.GetNodeState(new) THEN 
							tree.ExclNodeState(new, NodeExpanded)
						ELSE
							onExpandNode.Call(new);
							tree.InclNodeState(new, NodeExpanded)
						END
					ELSE
						IF new = selectedNode THEN
							IF NodeExpanded IN tree.GetNodeState(selectedNode) THEN 
								onExpandNode.Call(new);
								tree.ExclNodeState(selectedNode, NodeExpanded)
							ELSE
								tree.InclNodeState(selectedNode, NodeExpanded)
							END
						ELSE
							IF selectedNode # new THEN 
								selectedNode := new;
								onSelectNode.Call(selectedNode);
								Invalidate
							END
						END
					END	
				END
			END;
			tree.Release
		END PointerUp;
		
		PROCEDURE DragOver(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo);
		VAR node : TreeNode;
		BEGIN
			tree.Acquire;
			node := GetNodeAtPos(x, y);
			IF ~(NodeExpanded IN tree.GetNodeState(node)) THEN 
				onExpandNode.Call(node);
				tree.InclNodeState(node, NodeExpanded) 
			END;
			IF node # hoverNode THEN
				hoverNode := node;
				Invalidate
			END;
			tree.Release
		END DragOver;
		
		PROCEDURE WheelMove*(dz: LONGINT); (** PROTECTED *)
		BEGIN
			SetFirstLine(Utilities.Min(Utilities.Max(firstLine + dz, 0), lines - 1), TRUE)
		END WheelMove;
		
		PROCEDURE SelectNode*(node : TreeNode);
		BEGIN
			IF selectedNode # node THEN
				selectedNode := node;
				Invalidate
			END	
		END SelectNode;
		
		PROCEDURE PointerLeave;
		BEGIN
			IF hoverNode # NIL THEN hoverNode := NIL; Invalidate END
		END PointerLeave;
		
		(** Hande scrollbar changed event *)
		PROCEDURE ScrollbarChanged*(sender, data : PTR);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.ScrollbarChanged, sender, data)
			ELSE
				IF sender = vscrollbar THEN SetFirstLine(vscrollbar.pos.Get(), FALSE)
				ELSE hdelta := hscrollbar.pos.Get(); Invalidate
				END
			END	
		END ScrollbarChanged;
		
	END TreeView;

VAR
	 PrototypeTclHover*, PrototypeTclSelected*, PrototypeTclTextDefault*, 
	 PrototypeTclTextHover*, PrototypeTclTextSelected* : WMProperties.ColorProperty; 
	 PrototypeTfontHeight* : WMProperties.Int32Property;
	 
PROCEDURE InitPrototypes;
VAR plTreeView : WMProperties.PropertyList;
BEGIN
	NEW(plTreeView);
	NEW(PrototypeTclHover, NIL, NewString("ClHover"), NewString("color of the tree item, if the mouse is over it"));
	plTreeView.Add(PrototypeTclHover);
	NEW(PrototypeTclSelected, NIL, NewString("ClSelected"), NewString("color of the the tree item, if it is selected"));
	plTreeView.Add(PrototypeTclSelected);
	NEW(PrototypeTclTextDefault, NIL, NewString("ClTextDefault"), NewString("default text color of the tree item"));
	plTreeView.Add(PrototypeTclTextDefault);
	NEW(PrototypeTclTextHover, NIL, NewString("ClTextHover"), NewString("text color of the tree item, if the mouse is over it"));
	plTreeView.Add(PrototypeTclTextHover);
	NEW(PrototypeTclTextSelected, NIL, NewString("ClTextSelected"), NewString("text color of the tree item, when selected"));
	plTreeView.Add(PrototypeTclTextSelected);
	NEW(PrototypeTfontHeight, NIL, NewString("FontHeight"), NewString("height of the tree item text"));
	plTreeView.Add(PrototypeTfontHeight);
	PrototypeTclHover.Set(0FFFF00FFH);
	PrototypeTclSelected.Set(00000FFFFH);
	PrototypeTclTextDefault.Set(0000000FFH);
	PrototypeTclTextHover.Set(00000FFFFH);
	PrototypeTclTextSelected.Set(0FFFFFFFFH);
	PrototypeTfontHeight.Set(12);
	WMComponents.propertyListList.Add("TreeView", plTreeView);
	WMComponents.propertyListList.UpdateStyle;
END InitPrototypes;	

PROCEDURE TreeViewGen*(ptr : PTR):PTR;
VAR x : TreeView;
BEGIN
	NEW(x); RETURN x
END TreeViewGen;

PROCEDURE NewString*(x : ARRAY OF CHAR) : String;
VAR t : String;
BEGIN
	NEW(t, LEN(x)); COPY(x, t^); RETURN t
END NewString;

PROCEDURE Install*(par : PTR) : PTR;
BEGIN
	RETURN NIL
END Install;

PROCEDURE Init;
BEGIN
	WMComponents.registry.RegisterElement("TreeView", TreeViewGen);
	InitPrototypes
END Init;

PROCEDURE Uninstall;
BEGIN
	WMComponents.registry.UnregisterElement("TreeView")
END Uninstall;

BEGIN
	Init;
	AosModules.InstallTermHandler(Uninstall)
END WMTrees.


Aos.Call WMTrees.Install ~
System.Free WMTrees ~

