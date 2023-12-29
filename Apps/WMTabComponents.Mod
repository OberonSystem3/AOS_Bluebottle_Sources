MODULE WMTabComponents;

IMPORT
	Utilities, AosModules, WMEvents, WMProperties,
	WMWindowManager, WMStandardComponents, WMRectangles, WMMessages, WMComponents, WMGraphics, WMGraphicUtilities;

TYPE
	String = Utilities.String;
	Tab* = OBJECT
	VAR caption- : String;
		w : LONGINT;
		color- : LONGINT;
		data- : ANY;
		inserted : BOOLEAN;
		next : Tab;
	END Tab;
	
TYPE
	Tabs* = OBJECT(WMComponents.VisualComponent)
	VAR left, right : WMStandardComponents.Button;
		leftOfs : LONGINT;
		totalWidth : LONGINT;
		tabs : Tab;
		border : LONGINT;
		canvasState : WMGraphics.CanvasState;
		hover : Tab;
		selected : Tab;
		
		onSelectTab* : WMEvents.EventSource;
		clHover*, clSelected*, 
		clTextDefault*, clTextHover*, clTextSelected* : WMProperties.ColorProperty;
		borderWidth* : WMProperties.Int32Property;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(left); NEW(right);
			left.alignment.Set(WMComponents.AlignLeft); 
			left.bounds.SetWidth(10);
			left.visible.Set(FALSE);
		
			right.alignment.Set(WMComponents.AlignRight); 
			right.bounds.SetWidth(10);
			right.visible.Set(FALSE);
			
			AddContent(left); AddContent(right);

			NEW(clHover, PrototypeTclHover, NIL, NIL); properties.Add(clHover);
			NEW(clSelected, PrototypeTclSelected, NIL, NIL); properties.Add(clSelected);
			NEW(clTextDefault, PrototypeTclTextDefault, NIL, NIL); properties.Add(clTextDefault);
			NEW(clTextHover, PrototypeTclTextHover, NIL, NIL); properties.Add(clTextHover);
			NEW(clTextSelected, PrototypeTclTextSelected,  NIL, NIL); properties.Add(clTextSelected);
			NEW(borderWidth, PrototypeTborderWidth, NIL, NIL); properties.Add(borderWidth);	
			NEW(onSelectTab, SELF, Utilities.NewString("onSelectTab"), Utilities.NewString("if tab clicked"), SELF.StringToCompCommand);
		END Init;
		
		PROCEDURE FindTabFromPos(x: LONGINT) : Tab;
		VAR cur : Tab;
			pos, dl, w: LONGINT;
		BEGIN
			IF left.visible.Get() THEN dl := left.bounds.GetWidth() ELSE dl := 0 END;
			pos := - leftOfs + dl;
			cur := tabs;
			WHILE cur # NIL DO 
				w := cur.w;
				IF pos > bounds.GetWidth() THEN RETURN NIL END;
				pos := pos + w;
				IF x < pos THEN RETURN cur END;
				cur := cur.next 
			END;
			RETURN NIL
		END FindTabFromPos;
		
		PROCEDURE PointerDown*(x, y: LONGINT; keys: SET); (** PROTECTED *)
		VAR  new : Tab;
		BEGIN 
			IF 0 IN keys THEN
				new := FindTabFromPos(x);
				IF selected # new THEN 
					selected := new;
					onSelectTab.Call(selected);
					Invalidate
				END
			END	
		END PointerDown;
		
		PROCEDURE Select*(new : Tab);
		BEGIN
			Acquire;
			IF selected # new THEN 
				selected := new;
				Invalidate
			END;
			Release		
		END Select;
		
		
		PROCEDURE PointerMove*(x, y: LONGINT; keys: SET); (** PROTECTED *)
		VAR  new : Tab;
		BEGIN
			new := FindTabFromPos(x);
			IF hover # new THEN 
				hover := new;
				Invalidate
			END
		END PointerMove;
		
		PROCEDURE PointerLeave;
		BEGIN
			hover := NIL;
			Invalidate
		END PointerLeave;
		
		PROCEDURE AddTab*(tab : Tab);
		VAR cur : Tab;
		BEGIN
			Acquire;
			tab.next := NIL; tab.inserted := TRUE;
			IF tabs = NIL THEN tabs := tab; selected := tab;
			ELSE
				cur := tabs;
				WHILE cur.next # NIL DO cur := cur.next END;
				cur.next := tab
			END;
			Release;
			Invalidate
		END AddTab;
		
		PROCEDURE RemoveTab*(tab : Tab);
		VAR cur : Tab;
		BEGIN
			IF (tabs = NIL) OR (tab = NIL)  THEN RETURN END;
			Acquire;
			IF tabs = tab THEN tabs := tabs.next
			ELSE
				cur := tabs;
				WHILE (cur # NIL) & (cur.next # tab) DO tab := tab.next END;
				IF cur # NIL THEN cur.next := cur.next.next END
			END;
			CalcSize;
			IF totalWidth < bounds.GetWidth() THEN 
				left.visible.Set(FALSE);
				right.visible.Set(FALSE);
				leftOfs := 0;
			END;
			tab.inserted := FALSE;
			Release;
			Invalidate
		END RemoveTab;
		
		PROCEDURE RemoveAllTabs*;
		BEGIN
			Acquire;
			tabs := NIL;
			Release;
			Invalidate
		END RemoveAllTabs;
		
		
		PROCEDURE CalcSize;
		VAR cur : Tab; font : WMGraphics.Font; dx, dy : LONGINT;
		BEGIN
			Acquire;
			font := GetFont();
			totalWidth := 0;
			cur := tabs;
			WHILE cur # NIL DO 
				IF cur.caption # NIL THEN 
					font.GetStringSize(cur.caption^, dx, dy);
					totalWidth := totalWidth + dx + 2 * border
				ELSE	
					totalWidth := totalWidth + 2 * border
				END;	
				cur := cur.next 
			END;
			Release;
		END CalcSize;
		
		PROCEDURE SetTabCaption*(tab : Tab; caption : String);
		BEGIN
			Acquire;
			tab.caption := caption;
			Release;
			IF tab.inserted THEN Invalidate END
		END SetTabCaption;
		
		PROCEDURE SetTabColor*(tab : Tab; color : LONGINT);
		BEGIN
			Acquire;
			tab.color := color;
			Release;
			IF tab.inserted THEN Invalidate END
		END SetTabColor;

		PROCEDURE SetTabData*(tab : Tab; data : ANY);
		BEGIN
			Acquire;
			tab.data := data;
			Release;
			IF tab.inserted THEN Invalidate END
		END SetTabData;
		
		PROCEDURE NewTab*() : Tab;
		VAR tab : Tab;
		BEGIN
			NEW(tab); RETURN tab
		END NewTab;
		
		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		VAR r : WMRectangles.Rectangle;
			w, h, dl, dr : LONGINT; i : LONGINT;
			pos : LONGINT; dx, dy, dc : LONGINT;
			cur : Tab; font : WMGraphics.Font;
		BEGIN
			border := borderWidth.Get();
			font := GetFont();
			dc := font.descent;
(*			DrawBackground^(canvas); *)
			h := bounds.GetHeight(); w := bounds.GetWidth();

			IF left.visible.Get() THEN dl := left.bounds.GetWidth() ELSE dl := 0 END;
			IF right.visible.Get() THEN dr := right.bounds.GetWidth() ELSE dr := 0 END;
			canvas.SaveState(canvasState);
			canvas.SetClipRect(WMRectangles.MakeRect(dl, 0, w - dr, h));
			canvas.ClipRectAsNewLimits(dl, 0);
			
			pos := - leftOfs;
			cur := tabs;
			WHILE cur # NIL DO 
				IF cur.caption # NIL THEN 
					font.GetStringSize(cur.caption^, dx, dy); w := dx + 2 * border;
				ELSE w := 2 * border
				END;
				cur.w := w;
				r := WMRectangles.MakeRect(pos, 0, pos + w, h);
				IF cur = hover THEN 
					canvas.SetColor(clTextHover.Get());
					canvas.Fill(r, clHover.Get(), WMGraphics.ModeSrcOverDst)
				ELSIF cur = selected THEN 
					canvas.SetColor(clTextSelected.Get());
					canvas.Fill(r, clSelected.Get(), WMGraphics.ModeSrcOverDst)
				ELSE 
					canvas.SetColor(clTextDefault.Get());
					IF cur.color # 0 THEN canvas.Fill(r, cur.color, WMGraphics.ModeCopy)
					ELSE canvas.Fill(r, fillColor.Get(), WMGraphics.ModeCopy)
					END
				END;
				IF cur.caption # NIL THEN canvas.DrawString(r.l + border , r.b - dc - 1, cur.caption^) END;
				RectGlassShade(canvas, r, {2}, border, cur = selected);
				pos := pos + w;
				cur := cur.next 
			END;
			canvas.RestoreState(canvasState)
		END DrawBackground;
		
	END Tabs;

VAR
	 PrototypeTclHover*, PrototypeTclSelected*, PrototypeTclTextDefault*, 
	 PrototypeTclTextHover*, PrototypeTclTextSelected* : WMProperties.ColorProperty; 
	 PrototypeTborderWidth* : WMProperties.Int32Property;
	
PROCEDURE RectGlassShade*(canvas : WMGraphics.Canvas; rect : WMRectangles.Rectangle; openSides : SET; borderWidth : LONGINT; down : BOOLEAN);
VAR i, ul, dr, da, w, a, b, c, d : LONGINT;
BEGIN
	IF down THEN ul := 090H; dr := 0FFFFFF90H 
	ELSE dr := 090H; ul := 0FFFFFF90H
	END;
	da := 90H DIV borderWidth;
	FOR i := 0 TO borderWidth - 1 DO
		IF  (0 IN openSides) THEN a := 0 ELSE a := i END;
		IF  (1 IN openSides) THEN b := 0 ELSE b := i + 1 END;
		IF  (2 IN openSides) THEN c := 0 ELSE c := i END;
		IF  (3 IN openSides) THEN d := 0 ELSE d := i + 1 END;
		(* top *)
		IF ~(0 IN openSides) THEN canvas.Fill(WMRectangles.MakeRect(rect.l + b , rect.t + i, rect.r - d, rect.t + i + 1), ul, WMGraphics.ModeSrcOverDst) END;
		(* left *)
		IF ~(1 IN openSides) THEN canvas.Fill(WMRectangles.MakeRect(rect.l + i, rect.t + a, rect.l + i + 1, rect.b - c), ul, WMGraphics.ModeSrcOverDst) END;
		(* bottom *)
		IF ~(2 IN openSides) THEN canvas.Fill(WMRectangles.MakeRect(rect.l + b, rect.b - 1 - i, rect.r - d, rect.b - i), dr, WMGraphics.ModeSrcOverDst) END;
		(* right *)
		IF ~(3 IN openSides) THEN canvas.Fill(WMRectangles.MakeRect(rect.r - 1 - i, rect.t + a, rect.r - i, rect.b - c), dr, WMGraphics.ModeSrcOverDst) END;
		DEC(ul, da); DEC(dr, da)
	END;
	i := 3; ul := 0FFFFFF40H; w := 5;
	canvas.Fill(WMRectangles.MakeRect(rect.l + i , rect.t + i, rect.l + i + w, rect.t + i + 2), ul, WMGraphics.ModeSrcOverDst);
	canvas.Fill(WMRectangles.MakeRect(rect.l + i, rect.t + i, rect.l + i + 2, rect.t + i + w), ul, WMGraphics.ModeSrcOverDst);
END RectGlassShade;	


	 
PROCEDURE InitPrototypes;
VAR plTabs: WMProperties.PropertyList;
BEGIN
	NEW(plTabs);
	NEW(PrototypeTclHover, NIL, Utilities.NewString("ClHover"), Utilities.NewString("color of the tab item, if the mouse is over it"));
	plTabs.Add(PrototypeTclHover);
	NEW(PrototypeTclSelected, NIL, Utilities.NewString("ClSelected"), Utilities.NewString("color of the the tab item, if it is selected"));
	plTabs.Add(PrototypeTclSelected);
	NEW(PrototypeTclTextDefault, NIL, Utilities.NewString("ClTextDefault"), Utilities.NewString("default text color of the tab  item"));
	plTabs.Add(PrototypeTclTextDefault);
	NEW(PrototypeTclTextHover, NIL, Utilities.NewString("ClTextHover"), Utilities.NewString("text color of the tab item, if the mouse is over it"));
	plTabs.Add(PrototypeTclTextHover);
	NEW(PrototypeTclTextSelected, NIL,Utilities. NewString("ClTextSelected"),Utilities. NewString("text color of the tab item, when selected"));
	plTabs.Add(PrototypeTclTextSelected);
	NEW(PrototypeTborderWidth, NIL, Utilities.NewString("BorderWidth"), Utilities.NewString("Width of the border of the tabs"));
	plTabs.Add(PrototypeTborderWidth);
	PrototypeTclHover.Set(0FFFF00FFH);
	PrototypeTclSelected.Set(0FFFF00FFH);
	PrototypeTclTextDefault.Set(0000000FFH);
	PrototypeTclTextHover.Set(00000FFFFH);
	PrototypeTclTextSelected.Set(00FFFFH);
	PrototypeTborderWidth.Set(3);
	WMComponents.propertyListList.Add("Tabs", plTabs);
	WMComponents.propertyListList.UpdateStyle;
END InitPrototypes;	

PROCEDURE Cleanup;
BEGIN
END Cleanup;

BEGIN
	InitPrototypes;
	AosModules.InstallTermHandler(Cleanup); 
END WMTabComponents.

S.Free WMTabComponents 
WMTabComponents.Open 

Color Codes
 Highlight
Types and Procedures
Lock Acquire / Lock Release
Preferred notation (comment)
Unsafe / Temporary / Stupid / requires attention
Permanent Comment 
Assertion
Debug

