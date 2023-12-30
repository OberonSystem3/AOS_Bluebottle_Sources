MODULE WMTabComponents;
(** 
 * History:
 *
 *	12.03.2007	Added Tabs.clDefault property (staubesv)
 *)
 
IMPORT
	Utilities, AosModules, WMEvents, WMProperties,
	WMStandardComponents, WMRectangles, WMComponents, WMGraphics;

TYPE
	String = Utilities.String;
	Tab* = OBJECT
	VAR caption- : String;
		w : LONGINT;
		color- : LONGINT;
		data- : ANY;
		inserted, attention* : BOOLEAN;
		next- : Tab;
	END Tab;
	
	Tabs* = OBJECT(WMComponents.VisualComponent)
	VAR left, right : WMStandardComponents.Button;
		leftOfs, totalWidth, border : LONGINT;
		tabs-, hover, selected- : Tab;
		canvasState : WMGraphics.CanvasState;
		
		onSelectTab- : WMEvents.EventSource;
		(* general look *)
		useBgBitmaps : WMProperties.BooleanProperty;
		borderWidth- : WMProperties.Int32Property;
		(* colors *)
		clDefault-, clHover-, clSelected-, clAttention-,
		clTextDefault-, clTextHover-, clTextSelected-, clTextAttention : WMProperties.ColorProperty;
		(* background bitmaps *)
		bgLeftDefault, bgMiddleDefault, bgRightDefault,
		bgLeftHover, bgMiddleHover, bgRightHover,
		bgLeftSelected, bgMiddleSelected, bgRightSelected,
		bgLeftAttention, bgMiddleAttention, bgRightAttention : WMProperties.StringProperty;
		
		imgLeftDefault, imgMiddleDefault, imgRightDefault,
		imgLeftHover, imgMiddleHover, imgRightHover,
		imgLeftSelected, imgMiddleSelected, imgRightSelected,
		imgLeftAttention, imgMiddleAttention, imgRightAttention : WMGraphics.Image;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(left); NEW(right);
			left.alignment.Set(WMComponents.AlignLeft); 
			left.bounds.SetWidth(10);
			left.isRepeating.Set(TRUE);
			left.onClick.Add(MoveLeft);
			left.visible.Set(FALSE);
		
			right.alignment.Set(WMComponents.AlignRight); 
			right.bounds.SetWidth(10);
			right.isRepeating.Set(TRUE);
			right.onClick.Add(MoveRight);
			right.visible.Set(FALSE);
			
			AddContent(left); AddContent(right);
			NEW(onSelectTab, SELF, Utilities.NewString("onSelectTab"), Utilities.NewString("if tab clicked"), SELF.StringToCompCommand);
			(* general look *)
			NEW(borderWidth, ProtoTcBorderWidth, NIL, NIL); properties.Add(borderWidth);	
			NEW(useBgBitmaps, ProtoTcUseBgBitmaps, NIL, NIL); properties.Add(useBgBitmaps);
			(* background colors *)
			fillColor.SetPrototype(ProtoTcDefault);
			NEW(clDefault, ProtoTcDefault, NIL, NIL); properties.Add(clDefault);
			NEW(clHover, ProtoTcHover, NIL, NIL); properties.Add(clHover);
			NEW(clSelected, ProtoTcSelected, NIL, NIL); properties.Add(clSelected);
			NEW(clAttention, ProtoTcAttention, NIL, NIL); properties.Add(clAttention);
			(* text colors *)
			NEW(clTextDefault, ProtoTcTextDefault, NIL, NIL); properties.Add(clTextDefault);
			NEW(clTextHover, ProtoTcTextHover, NIL, NIL); properties.Add(clTextHover);
			NEW(clTextSelected, ProtoTcTextSelected,  NIL, NIL); properties.Add(clTextSelected);
			NEW(clTextAttention, ProtoTcTextAttention,  NIL, NIL); properties.Add(clTextAttention);
			(* background bitmaps *)
			NEW(bgLeftDefault, ProtoTcBgLeftDefault, NIL, NIL); properties.Add(bgLeftDefault);
			NEW(bgMiddleDefault, ProtoTcBgMiddleDefault, NIL, NIL); properties.Add(bgMiddleDefault);
			NEW(bgRightDefault, ProtoTcBgRightDefault, NIL, NIL); properties.Add(bgRightDefault);

			NEW(bgLeftHover, ProtoTcBgLeftHover, NIL, NIL); properties.Add(bgLeftHover);
			NEW(bgMiddleHover, ProtoTcBgMiddleHover, NIL, NIL); properties.Add(bgMiddleHover);
			NEW(bgRightHover, ProtoTcBgRightHover, NIL, NIL); properties.Add(bgRightHover);

			NEW(bgLeftSelected, ProtoTcBgLeftSelected, NIL, NIL); properties.Add(bgLeftSelected);
			NEW(bgMiddleSelected, ProtoTcBgMiddleSelected, NIL, NIL); properties.Add(bgMiddleSelected);
			NEW(bgRightSelected, ProtoTcBgRightSelected, NIL, NIL); properties.Add(bgRightSelected);
		
			NEW(bgLeftAttention, ProtoTcBgLeftAttention, NIL, NIL); properties.Add(bgLeftAttention);
			NEW(bgMiddleAttention, ProtoTcBgMiddleAttention, NIL, NIL); properties.Add(bgMiddleAttention);
			NEW(bgRightAttention, ProtoTcBgRightAttention, NIL, NIL); properties.Add(bgRightAttention);
		
		END Init;
		
		PROCEDURE RecacheProperties;
		VAR s : String;
		BEGIN
			RecacheProperties^;
			s := bgLeftDefault.Get();	IF s # NIL THEN imgLeftDefault := WMGraphics.LoadImage(s^, TRUE) END;
			s := bgMiddleDefault.Get();	IF s # NIL THEN imgMiddleDefault := WMGraphics.LoadImage(s^, TRUE) END;
			s := bgRightDefault.Get();	IF s # NIL THEN imgRightDefault := WMGraphics.LoadImage(s^, TRUE) END;

			s := bgLeftHover.Get();	IF s # NIL THEN imgLeftHover := WMGraphics.LoadImage(s^, TRUE) END;
			s := bgMiddleHover.Get();	IF s # NIL THEN imgMiddleHover := WMGraphics.LoadImage(s^, TRUE) END;
			s := bgRightHover.Get();	IF s # NIL THEN imgRightHover := WMGraphics.LoadImage(s^, TRUE) END;
			
			s := bgLeftSelected.Get();	IF s # NIL THEN imgLeftSelected := WMGraphics.LoadImage(s^, TRUE) END;
			s := bgMiddleSelected.Get();	IF s # NIL THEN imgMiddleSelected := WMGraphics.LoadImage(s^, TRUE) END;
			s := bgRightSelected.Get();	IF s # NIL THEN imgRightSelected := WMGraphics.LoadImage(s^, TRUE) END;

			s := bgLeftAttention.Get();	IF s # NIL THEN imgLeftAttention := WMGraphics.LoadImage(s^, TRUE) END;
			s := bgMiddleAttention.Get();	IF s # NIL THEN imgMiddleAttention := WMGraphics.LoadImage(s^, TRUE) END;
			s := bgRightAttention.Get();	IF s # NIL THEN imgRightAttention := WMGraphics.LoadImage(s^, TRUE) END;
			Invalidate	
		END RecacheProperties;
		
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
				IF (selected # new) & (new # NIL) THEN 
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
		
		PROCEDURE MoveLeft(sender, data : ANY);
		BEGIN
			DEC(leftOfs, 10);
			IF leftOfs < 0 THEN leftOfs := 0 END;
			Invalidate;
		END MoveLeft;

		PROCEDURE MoveRight(sender, data : ANY);
		BEGIN
			INC(leftOfs, 10);
			IF leftOfs > totalWidth - 10 THEN leftOfs := totalWidth - 10 END;
			Invalidate;
		END MoveRight;
		
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
			CalcSize;
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
				WHILE (cur # NIL) & (cur.next # tab) DO cur := cur.next END;
				IF cur # NIL THEN cur.next := cur.next.next END
			END;
			CalcSize;
			tab.inserted := FALSE;
			Release;
			Invalidate
		END RemoveTab;
		
		PROCEDURE RemoveAllTabs*;
		BEGIN
			Acquire;
			tabs := NIL;
			CalcSize;
			Release;
			Invalidate
		END RemoveAllTabs;

		PROCEDURE CheckLeftRightButtons;
		BEGIN
			IF totalWidth >= bounds.GetWidth() THEN 
				right.visible.Set(TRUE);
				left.visible.Set(TRUE)
			ELSE	
				leftOfs := 0;
				right.visible.Set(FALSE);
				left.visible.Set(FALSE)
			END
		END CheckLeftRightButtons;
		
		PROCEDURE Resized;
		BEGIN
			Resized^;
			CheckLeftRightButtons
		END Resized;
		
		PROCEDURE CalcSize;
		VAR cur : Tab; font : WMGraphics.Font; dx, dy : LONGINT;
		BEGIN
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
			CheckLeftRightButtons
		END CalcSize;
		
		PROCEDURE SetTabCaption*(tab : Tab; caption : String);
		BEGIN
			Acquire;
			tab.caption := caption;
			CalcSize;
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
			w, h, dl, dr, wLeft, wRight : LONGINT;
			pos : LONGINT; dx, dy, dc : LONGINT;
			cur : Tab; font : WMGraphics.Font;
			imgLeft, imgMiddle, imgRight : WMGraphics.Image;
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
				
				IF useBgBitmaps.Get() THEN
					IF cur = hover THEN 
						imgLeft := imgLeftHover;
						imgMiddle := imgMiddleHover;
						imgRight := imgRightHover;
					ELSIF cur = selected THEN 
						imgLeft := imgLeftSelected;
						imgMiddle := imgMiddleSelected;
						imgRight := imgRightSelected;
					ELSIF cur.attention THEN
						imgLeft := imgLeftAttention;
						imgMiddle := imgMiddleAttention;
						imgRight := imgRightAttention;
					ELSE
						imgLeft := imgLeftDefault;
						imgMiddle := imgMiddleDefault;
						imgRight := imgRightDefault
					END;
					(* left *)
			 		IF imgLeft # NIL THEN
						wLeft := imgLeft.width;
						canvas.ScaleImage(	imgLeft,
						 	WMRectangles.MakeRect(0, 0, imgLeft.width, imgLeft.height),
							WMRectangles.MakeRect(pos, 0, pos+wLeft, bounds.GetHeight()), 
							WMGraphics.ModeSrcOverDst, 10)
					ELSE
						wLeft := 0
					END;
					(* right *)
			 		IF imgRight # NIL THEN
						wRight := imgRight.width;
						canvas.ScaleImage(	imgRight,
						 	WMRectangles.MakeRect(0, 0, imgRight.width, imgRight.height),
							WMRectangles.MakeRect(pos+w-wRight, 0, pos+w, bounds.GetHeight()), 
							WMGraphics.ModeSrcOverDst, 10)
					ELSE
						wRight := 0
					END;
					(* middle *)
					IF imgMiddle # NIL THEN
						canvas.ScaleImage(	imgMiddle,
								 	WMRectangles.MakeRect(0, 0, imgMiddle.width, imgMiddle.height),
									WMRectangles.MakeRect(pos+wLeft, 0, pos+w-wRight, bounds.GetHeight()), WMGraphics.ModeSrcOverDst, 10) 
					END
				ELSE (* no bitmaps are used to decorate the background *)
					IF cur = hover THEN 
						canvas.Fill(r, clHover.Get(), WMGraphics.ModeSrcOverDst)
					ELSIF cur = selected THEN 
						canvas.Fill(r, clSelected.Get(), WMGraphics.ModeSrcOverDst)
					ELSIF cur.attention THEN
						canvas.Fill(r, clAttention.Get(), WMGraphics.ModeSrcOverDst)
					ELSE 
						IF cur.color # 0 THEN canvas.Fill(r, cur.color, WMGraphics.ModeSrcOverDst)
						ELSE canvas.Fill(r, fillColor.Get(), WMGraphics.ModeSrcOverDst)
						END
					END;
					RectGlassShade(canvas, r, {2}, 2, cur = selected)
				END;
				(* caption *)
				IF cur = hover THEN 
					canvas.SetColor(clTextHover.Get());
				ELSIF cur = selected THEN 
					canvas.SetColor(clTextSelected.Get());
				ELSE 
					canvas.SetColor(clTextDefault.Get());
				END;
				IF cur.caption # NIL THEN canvas.DrawString(r.l + border , r.b - dc - 1, cur.caption^) END;
				pos := pos + w;
				cur := cur.next 
			END;
			canvas.RestoreState(canvasState)
		END DrawBackground;
		
	END Tabs;

VAR ColorPrototype, ProtoTcDefault*, ProtoTcHover*, ProtoTcSelected*, ProtoTcAttention*,
	 ProtoTcTextDefault*, ProtoTcTextHover*, ProtoTcTextSelected*, ProtoTcTextAttention* : WMProperties.ColorProperty; 
	 Int32Prototype, ProtoTcBorderWidth* : WMProperties.Int32Property;
	 StringPrototype, ProtoTcBgLeftDefault, ProtoTcBgMiddleDefault, ProtoTcBgRightDefault,
	 ProtoTcBgLeftHover, ProtoTcBgMiddleHover, ProtoTcBgRightHover,
	 ProtoTcBgLeftSelected, ProtoTcBgMiddleSelected, ProtoTcBgRightSelected,
	 ProtoTcBgLeftAttention, ProtoTcBgMiddleAttention, ProtoTcBgRightAttention : WMProperties.StringProperty;
	 BooleanPrototype, ProtoTcUseBgBitmaps : WMProperties.BooleanProperty;
	
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
	NEW(plTabs); WMComponents.propertyListList.Add("Tab", plTabs);
	(* tab background *)
	NEW(BooleanPrototype, NIL, Utilities.NewString("UseBgBitmaps"), Utilities.NewString("Will the background be decorated with bitmaps?")); 
	BooleanPrototype.Set(FALSE); 
	NEW(ProtoTcUseBgBitmaps, BooleanPrototype, NIL, NIL); plTabs.Add(ProtoTcUseBgBitmaps);
	(* background colors *)
	NEW(ColorPrototype, NIL, Utilities.NewString("ClDefault"), Utilities.NewString("color of the tab item")); ColorPrototype.Set(0000FF88H);
	NEW(ProtoTcDefault, ColorPrototype, NIL, NIL); plTabs.Add(ProtoTcDefault);
	NEW(ColorPrototype, NIL, Utilities.NewString("ClHover"), Utilities.NewString("color of the tab item, if the mouse is over it")); ColorPrototype.Set(0FFFF00FFH);
	NEW(ProtoTcHover, ColorPrototype, NIL, NIL); plTabs.Add(ProtoTcHover);
	NEW(ColorPrototype, NIL, Utilities.NewString("ClSelected"), Utilities.NewString("color of the the tab item, if it is selected")); ColorPrototype.Set(0FFFF00FFH);
	NEW(ProtoTcSelected, ColorPrototype, NIL, NIL); plTabs.Add(ProtoTcSelected);
	NEW(ColorPrototype, NIL, Utilities.NewString("ClAttention"), Utilities.NewString("color of the the tab item, if attention is required")); ColorPrototype.Set(0FF8040FFH);
	NEW(ProtoTcAttention, ColorPrototype, NIL, NIL); plTabs.Add(ProtoTcAttention);
	(* background bitmaps *)
	NEW(StringPrototype, NIL, Utilities.NewString("BgLeftDefault"), Utilities.NewString("Left default background bitmap")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgLeftDefault, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgLeftDefault);
	NEW(StringPrototype, NIL, Utilities.NewString("BgMiddleDefault"), Utilities.NewString("Middle default background bitmap")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgMiddleDefault, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgMiddleDefault);
	NEW(StringPrototype, NIL, Utilities.NewString("BgRightDefault"), Utilities.NewString("Right default background bitmap")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgRightDefault, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgRightDefault);

	NEW(StringPrototype, NIL, Utilities.NewString("BgLeftHover"), Utilities.NewString("Left mouseover background bitmap")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgLeftHover, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgLeftHover);
	NEW(StringPrototype, NIL, Utilities.NewString("BgMiddleHover"), Utilities.NewString("Middle mouseover background bitmap")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgMiddleHover, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgMiddleHover);
	NEW(StringPrototype, NIL, Utilities.NewString("BgRightHover"), Utilities.NewString("Right mouseover background bitmap")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgRightHover, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgRightHover);

	NEW(StringPrototype, NIL, Utilities.NewString("BgLeftSelected"), Utilities.NewString("Left selected background bitmap")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgLeftSelected, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgLeftSelected);
	NEW(StringPrototype, NIL, Utilities.NewString("BgMiddleSelected"), Utilities.NewString("Middle selected background bitmap")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgMiddleSelected, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgMiddleSelected);
	NEW(StringPrototype, NIL, Utilities.NewString("BgRightSelected"), Utilities.NewString("Right selected background bitmap")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgRightSelected, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgRightSelected);

	NEW(StringPrototype, NIL, Utilities.NewString("BgLeftAttention"), Utilities.NewString("Left background bitmap when attention is required")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgLeftAttention, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgLeftAttention);
	NEW(StringPrototype, NIL, Utilities.NewString("BgMiddleAttention"), Utilities.NewString("Middle background bitmap when attention is required")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgMiddleAttention, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgMiddleAttention);
	NEW(StringPrototype, NIL, Utilities.NewString("BgRightAttention"), Utilities.NewString("Right background bitmap when attention is required")); 
	StringPrototype.Set(NIL); NEW(ProtoTcBgRightAttention, StringPrototype, NIL, NIL); plTabs.Add(ProtoTcBgRightAttention);
	(* text colors *)
	NEW(ColorPrototype, NIL, Utilities.NewString("ClTextDefault"), Utilities.NewString("default text color of the tab  item")); ColorPrototype.Set(WMGraphics.Yellow);
	NEW(ProtoTcTextDefault, ColorPrototype, NIL, NIL); plTabs.Add(ProtoTcTextDefault);
	NEW(ColorPrototype, NIL, Utilities.NewString("ClTextHover"), Utilities.NewString("text color of the tab item, if the mouse is over it")); ColorPrototype.Set(00000FFFFH);
	NEW(ProtoTcTextHover, ColorPrototype, NIL, NIL); plTabs.Add(ProtoTcTextHover);
	NEW(ColorPrototype, NIL, Utilities.NewString("ClTextSelected"), Utilities.NewString("text color of the tab item, when selected")); ColorPrototype.Set(0000FFFFH);
	NEW(ProtoTcTextSelected, ColorPrototype, NIL, NIL); plTabs.Add(ProtoTcTextSelected);
	NEW(ColorPrototype, NIL, Utilities.NewString("ClTextAttention"), Utilities.NewString("text color of the tab item, when attention is required")); ColorPrototype.Set(0000FFFFH);
	NEW(ProtoTcTextAttention, ColorPrototype, NIL, NIL); plTabs.Add(ProtoTcTextAttention);
	(* border width *)
	NEW(Int32Prototype, NIL, Utilities.NewString("BorderWidth"), Utilities.NewString("Width of the border of the tabs")); Int32Prototype.Set(3);
	NEW(ProtoTcBorderWidth, Int32Prototype, NIL, NIL);	plTabs.Add(ProtoTcBorderWidth); 

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

