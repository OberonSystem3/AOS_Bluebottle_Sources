MODULE WMMenus;	(** AUTHOR "TF"; PURPOSE "Menu support"; *)

IMPORT
	Utilities, Raster, WMRectangles, WMGraphics, WMMessages, WMComponents, WMStandardComponents, 
	WMWindowManager, WMProperties, WMEvents, AosModules, WMTrees, AosOut;

CONST
	HMenuDistance = 10;
	VMenuDistance = 4;
	OpenDefault* = 0;
	OpenUpLeft* = 1;
	OpenUpRight* = 2;
	OpenDownLeft* = 3;
	OpenDownRight* = 4;

TYPE
	MenuPanel*= OBJECT(WMComponents.VisualComponent)
	VAR menu : WMTrees.Tree;
		root : WMTrees.TreeNode;
		selection, hover : WMTrees.TreeNode;
		horizontal- : WMProperties.BooleanProperty;
		menuSelectEvent- : WMEvents.EventSource;
		openDirection- : WMProperties.Int32Property;
	
		subMenuIndicatorImg : WMGraphics.Image;
		
		subMenu : MenuWindow;
		
		parentMenuPanel : MenuPanel;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(horizontal, NIL, NIL, NIL); properties.Add(horizontal);
			NEW(openDirection, NIL, NIL, NIL); properties.Add(openDirection);
			NEW(menuSelectEvent, SELF, NIL, NIL, NIL);
			takesFocus.Set(TRUE);
		END Init;
		
		PROCEDURE SetParent(parentMenuPanel : MenuPanel);
		BEGIN
			SELF.parentMenuPanel := parentMenuPanel
		END SetParent;
		
		PROCEDURE SetMenu*(menu : WMTrees.Tree; root : WMTrees.TreeNode);
		BEGIN
			Acquire;
			SELF.menu := menu; SELF.root := root; selection := NIL;
			Invalidate;
			Release
		END SetMenu;
		
		PROCEDURE Measure(VAR w, h : LONGINT);
		VAR a : WMTrees.TreeNode;
		BEGIN
			w := 0;
			ASSERT((menu # NIL) & (root # NIL));
			IF horizontal.Get() THEN
				menu.Acquire;
				a := menu.GetChildren(root);
				WHILE a # NIL DO 
					w := w + ItemWidth(a);
					a := menu.GetNextSibling(a)
				END;
				menu.Release;
			ELSE
				menu.Acquire;
				h := 0; w := 10;
				a := menu.GetChildren(root);
				WHILE a # NIL DO 
					h := h + ItemHeight(a);
					w := Utilities.Max(w, ItemWidth(a));
					a := menu.GetNextSibling(a)
				END;
				menu.Release;
			END;
		END Measure; 
		
		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR a : WMTrees.TreeNode;
			h, w, dx, dy, t : LONGINT;
			f : WMGraphics.Font;
			s : Utilities.String;
			img : Raster.Image;
		BEGIN
			DrawBackground^(canvas);
			f := GetFont();
			canvas.SetFont(f);
			canvas.SetColor(0FFH);
			w := 0; h := 0;
			ASSERT((menu # NIL) & (root # NIL));
			IF horizontal.Get() THEN
				menu.Acquire;
				a :=menu.GetChildren(root);
				WHILE a # NIL DO
					IF a = hover THEN 
						canvas.Fill(WMRectangles.MakeRect(w, 0, w + ItemWidth(a), bounds.GetHeight()), 0FFFF00FFH, WMGraphics.ModeCopy);
					END;
					s := menu.GetNodeCaption(a);
					img := menu.GetNodeImage(a);
					IF img # NIL THEN 
						canvas.DrawImage(HMenuDistance DIV 2 + w, 0, img, WMGraphics.ModeSrcOverDst);
						w := w + img.width   
					END;
					IF s # NIL THEN 
						f.GetStringSize(s^, dx, dy); canvas.DrawString(HMenuDistance DIV 2 + w, dy, s^);
						w := w + dx 
					END;
					INC(w, HMenuDistance);
					a := menu.GetNextSibling(a)
				END;
				menu.Release;
			ELSE
				menu.Acquire;
				a :=menu.GetChildren(root);
				WHILE a # NIL DO
					IF a = hover THEN 
						canvas.Fill(WMRectangles.MakeRect(0, h, bounds.GetWidth(), h + ItemHeight(a)), 0FFFF00FFH, WMGraphics.ModeCopy);
					END;
					s := menu.GetNodeCaption(a);
					img := menu.GetNodeImage(a);
					dy := 0;
					IF img # NIL THEN 
						canvas.DrawImage(0, h, img, WMGraphics.ModeSrcOverDst);
						dy := img.width 
					END;
					IF s # NIL THEN 
						f.GetStringSize(s^, dx, t); canvas.DrawString(0, h + f.ascent + VMenuDistance DIV 2, s^);
						INC(t, VMenuDistance);
						IF t > dy THEN dy := t END
					END;
					IF menu.GetChildren(a) # NIL THEN
						IF subMenuIndicatorImg # NIL THEN
							canvas.DrawImage(bounds.GetWidth() - subMenuIndicatorImg.width, 0, subMenuIndicatorImg, WMGraphics.ModeSrcOverDst)
						ELSE
							canvas.DrawString(bounds.GetWidth() - 10, h + f.ascent, "...")
						END
					END;
					h := h + dy;
					INC(w, HMenuDistance);
					a := menu.GetNextSibling(a)
				END;
				menu.Release;
			END	
		END DrawBackground;
		
		(* caller must hold tree lock *)
		PROCEDURE ItemWidth(item : WMTrees.TreeNode) : LONGINT;
		VAR w, dx, dy : LONGINT;
			f : WMGraphics.Font;
			s : Utilities.String;
			img : Raster.Image;
		BEGIN
			f := GetFont();
			w := 0;
			s := menu.GetNodeCaption(item);
			img := menu.GetNodeImage(item);
			IF s # NIL THEN f.GetStringSize(s^, dx, dy); w := w + dx END;
			IF img # NIL THEN w := w + img.width END;
			INC(w, HMenuDistance);
			RETURN w
		END ItemWidth;
		
		(* caller must hold tree lock *)
		PROCEDURE ItemHeight(item : WMTrees.TreeNode) : LONGINT;
		VAR t, dx, dy : LONGINT;
			f : WMGraphics.Font;
			s : Utilities.String;
			img : Raster.Image;
		BEGIN
			f := GetFont();
			s := menu.GetNodeCaption(item);
			img := menu.GetNodeImage(item);
			dy := 0;
			IF img # NIL THEN dy := img.width END;
			IF s # NIL THEN f.GetStringSize(s^, dx, t); INC(t, VMenuDistance); IF t > dy THEN dy := t END END;
			RETURN dy
		END ItemHeight;
		
		PROCEDURE FindHorizontal(x : LONGINT) : WMTrees.TreeNode;
		VAR res : WMTrees.TreeNode;
			p : LONGINT;
			a : WMTrees.TreeNode;
		BEGIN
			p := 0;
			menu.Acquire;
			a :=menu.GetChildren(root);
			IF a # NIL THEN
				REPEAT
					p := p + ItemWidth(a);
					IF p < x THEN a := menu.GetNextSibling(a) END;
				UNTIL (a = NIL) OR (p >= x);
			END;
			menu.Release;
			RETURN a
		END FindHorizontal;

		PROCEDURE FindVertical(y : LONGINT) : WMTrees.TreeNode;
		VAR res : WMTrees.TreeNode;
			p : LONGINT;
			a : WMTrees.TreeNode;
		BEGIN
			p := 0;
			menu.Acquire;
			a :=menu.GetChildren(root);
			IF a # NIL THEN
				REPEAT
					p := p + ItemHeight(a);
					IF p < y THEN a := menu.GetNextSibling(a) END;
				UNTIL (a = NIL) OR (p >= y);
			END;
			menu.Release;
			RETURN a
		END FindVertical;
		
		PROCEDURE GetItemRect(i : WMTrees.TreeNode; VAR r : WMRectangles.Rectangle);
		VAR a : WMTrees.TreeNode;
		BEGIN
			menu.Acquire;
			a :=menu.GetChildren(root);
			r.l := 0; r.t := 0;
			WHILE (a # NIL) & (a # i) DO 
				IF horizontal.Get() THEN	INC(r.l, ItemWidth(a))
				ELSE INC(r.t, ItemHeight(a))
				END;
				a := menu.GetNextSibling(a);
			END;
			IF a # NIL THEN r.r := r.l + ItemWidth(a); r.b := r.t + ItemHeight(a) END;
			menu.Release
		END GetItemRect;
	
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET);
		VAR m : WMTrees.TreeNode;
		BEGIN
			IF horizontal.Get() THEN m := FindHorizontal(x)
			ELSE m := FindVertical(y)
			END;
			IF m # hover  THEN hover := m; Invalidate END;
		END PointerMove;
		
		PROCEDURE LeafSelect(item : WMTrees.TreeNode);
		BEGIN
			IF parentMenuPanel = NIL THEN 
				IF subMenu # NIL THEN subMenu.CloseMenu(SELF, NIL); subMenu := NIL END;	
				menuSelectEvent.Call(item)
			ELSE
				parentMenuPanel.LeafSelect(item);
			END
		END LeafSelect;
		
		PROCEDURE PointerDown(x, y : LONGINT; keys : SET);
		VAR m, s : WMTrees.TreeNode;
			r : WMRectangles.Rectangle;
		BEGIN
			IF horizontal.Get() THEN m := FindHorizontal(x)
			ELSE m := FindVertical(y)
			END;
			IF m # NIL THEN
				menu.Acquire;
				s := menu.GetChildren(m);
				IF s # NIL THEN
					GetItemRect(m, r);
					IF horizontal.Get() THEN
						IF openDirection.Get() IN {OpenUpLeft, OpenUpRight} THEN ToWMCoordinates(r.l, r.t, x, y)
						ELSE ToWMCoordinates(r.l, r.b, x, y)
						END
					ELSE
						CASE openDirection.Get() OF
							|OpenUpLeft : ToWMCoordinates(r.l, r.b, x, y)
							|OpenUpRight : ToWMCoordinates(r.r, r.b, x, y)
							|OpenDownLeft : ToWMCoordinates(r.l, r.t, x, y)
							|OpenDownRight : ToWMCoordinates(r.r, r.t, x, y)
						ELSE ToWMCoordinates(r.r, r.t, x, y)
						END;
					END;
					IF subMenu # NIL THEN subMenu.CloseMenu(SELF, NIL); subMenu := NIL END;
					NEW(subMenu, x, y, openDirection.Get(), menu, m, SELF);
					PointerLeave;
				ELSE
					LeafSelect(m)
				END;
				menu.Release;
			END;
		END PointerDown;
		
		PROCEDURE PointerLeave;
		BEGIN
			IF hover # NIL THEN hover := NIL; Invalidate END;
		END PointerLeave;
		
		PROCEDURE Finalize;
		BEGIN
			Finalize^;
			IF subMenu # NIL THEN subMenu.Close; subMenu := NIL END;
		END Finalize;
		
		PROCEDURE FocusLost;
		BEGIN
			IF subMenu # NIL THEN subMenu.Close; subMenu := NIL END;
		END FocusLost;
		
		
	END MenuPanel;
	
	MenuWindow= OBJECT(WMComponents.FormWindow)
	VAR menuPanel : MenuPanel;
	
		PROCEDURE &Open(x, y : LONGINT; openDirection : LONGINT;  menu : WMTrees.Tree; root : WMTrees.TreeNode; parent : MenuPanel);
		VAR w, h, dx, dy : LONGINT;
		BEGIN
			NEW(menuPanel);
			menuPanel.SetParent(parent);
			menuPanel.fillColor.Set(080808080);
			menuPanel.SetMenu(menu, root);
			menuPanel.Measure(w, h);
			IF h < 5 THEN h := 5 END; IF w < 5 THEN w := 5 END;
			menuPanel.bounds.SetExtents(w, h);
			CASE openDirection OF
				|OpenUpLeft : dx := -w; dy := -h
				|OpenUpRight : dy := -h
				|OpenDownLeft : dx := -w
			ELSE dx := 0; dy :=0
			END;
			menuPanel.openDirection.Set(openDirection);
			Init(menuPanel.bounds.GetWidth(), menuPanel.bounds.GetHeight(), TRUE);
			SetContent(menuPanel);
			manager := WMWindowManager.GetDefaultManager();
			manager.Add(x + dx, y + dy, SELF, {WMWindowManager.FlagStayOnTop, WMWindowManager.FlagNoFocus});
			IF manager.TransferPointer(SELF) THEN AosOut.String("Pointer transferred "); AosOut.Ln;  END; 
		END Open;
		
		PROCEDURE CloseMenu(sender, data : ANY);
		BEGIN
			IF ~sequencer.IsCallFromSequencer() THEN
				sequencer.ScheduleEvent(SELF.CloseMenu, NIL, NIL)
			ELSE Close
			END
		END CloseMenu;
		
	END MenuWindow;

END WMMenus.

