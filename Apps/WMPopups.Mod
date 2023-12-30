MODULE WMPopups;	(** AUTHOR "BF"; PURPOSE ""; *)

IMPORT
	Standard := WMStandardComponents, WMEvents, WM := WMWindowManager, Base := WMComponents,
	WMMessages, WMGraphics, Utilities, WMRectangles;

TYPE
(* Open a Popup *)
	Popup* = OBJECT (Base.FormWindow)
	VAR
		panel : Standard.Panel;
		count : LONGINT;
		width : LONGINT;
		
		PROCEDURE&New;
		BEGIN
			NEW(panel);
			panel.fillColor.Set(WMGraphics.RGBAToColor(255, 255, 255, 255));
			count := 0;
			width := 100
		END New;
		
		PROCEDURE Add* (caption : ARRAY OF CHAR; onClickHandler : WMEvents.EventListener);
		VAR b : Standard.Button;
			f : WMGraphics.Font;
			dw, dh : LONGINT;
		BEGIN
			NEW(b); b.bounds.SetHeight(20); b.caption.SetAOC(caption);
			b.alignment.Set(Base.AlignTop);
			b.onClick.Add(onClickHandler);
			b.onClick.Add(Clicked);
			panel.AddContent(b);
			f := b.GetFont(); f.GetStringSize(caption, dw, dh); width := Utilities.Min(Utilities.Max(width, dw + 10), 1024);
			INC(count)
		END Add;
		
		PROCEDURE AddParButton* (caption : ARRAY OF CHAR; onClickHandler : WMEvents.EventListener; par : PTR);
		VAR b : Standard.Button;
			f : WMGraphics.Font;
			dw, dh : LONGINT;
		BEGIN
			NEW(b); b.bounds.SetHeight(20); b.caption.SetAOC(caption); b.userData := par;
			b.alignment.Set(Base.AlignTop);
			b.onClick.Add(onClickHandler);
			b.onClick.Add(Clicked);
			panel.AddContent(b);
			f := b.GetFont(); f.GetStringSize(caption, dw, dh); width := Utilities.Min(Utilities.Max(width, dw + 10), 1024);
			INC(count)
		END AddParButton;
		
		PROCEDURE Popup* (x, y : LONGINT);
		BEGIN
			panel.bounds.SetWidth(width); panel.bounds.SetHeight(count*20);
			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), FALSE);
			SetContent(panel);
			manager := WM.GetDefaultManager();
			manager.Add(x, y, SELF, {WM.FlagStayOnTop});
			manager.SetFocus(SELF);
		END Popup;
		
		PROCEDURE Clicked(sender, data : ANY);
		BEGIN
			Close
		END Clicked;
		
		PROCEDURE FocusLost;
		BEGIN
			Close
		END FocusLost;
		
		PROCEDURE FocusGot;
		BEGIN
			manager.SetFocus(SELF)
		END FocusGot;
	
	END Popup;
	
(** Open a color swatch dialog *)
	ColorSwatchPopup* = OBJECT (Base.FormWindow)
	VAR colorPanel : ColorSwatchPanel;
		color- : LONGINT;
		onColorChosen* : PROCEDURE {DELEGATE} (color : LONGINT);
		
		PROCEDURE &New;
		BEGIN
			color := 0H;
			CreatePopup;
			Init(colorPanel.bounds.GetWidth(), colorPanel.bounds.GetHeight(), FALSE);
			SetContent(colorPanel);
		END New;
		
		PROCEDURE CreatePopup;
		BEGIN
			NEW(colorPanel);
			colorPanel.ChosenColorProc := SetColor;			
		END CreatePopup;
		
		PROCEDURE Popup*(x, y : LONGINT);
		BEGIN 
			manager := WM.GetDefaultManager();
			manager.Add(x, y, SELF, {WM.FlagStayOnTop});
			manager.SetFocus(SELF); 
		END Popup;
		
		PROCEDURE Clicked(sender, data : ANY);
		BEGIN
			manager.Remove(SELF)
		END Clicked;
		
		PROCEDURE FocusLost;
		BEGIN
			manager.Remove(SELF)
		END FocusLost;
		
		PROCEDURE FocusGot;
		BEGIN
			manager.SetFocus(SELF)
		END FocusGot;
		
		PROCEDURE SetColor(color : LONGINT);
		BEGIN
			SELF.color := color;
			IF onColorChosen # NIL THEN onColorChosen(color) END;
			manager.Remove(SELF)
		END SetColor;

	END ColorSwatchPopup;

(** Color Swatch Visual Component *)	
	ColorSwatchPanel* = OBJECT(Base.VisualComponent)
	VAR colors : ARRAY 19 OF LONGINT;
		ChosenColorProc* : PROCEDURE {DELEGATE} (color: LONGINT);
		(* CloseProc : PROCEDURE {DELEGATE}; *)
		
		PROCEDURE &Init();
		BEGIN
			Init^;
			bounds.SetExtents(190, 70);
			BuildPalette;
		END Init;
		
		PROCEDURE PointerDown(x, y : LONGINT; keys : SET);
		VAR r, g, b, a, i, j, cColor: LONGINT;
		BEGIN
			i := y DIV 10; j := x DIV 10;
			IF (i>= 0) & (i<=2) THEN
				WMGraphics.ColorToRGBA(colors[j], r, g, b, a);
				r := ENTIER((i+1)/4*r); g:= ENTIER((i+1)/4*g); b:= ENTIER((i+1)/4*b);
				cColor := WMGraphics.RGBAToColor(r, g, b, a);	
			ELSIF (i= 3) THEN
				cColor := colors[j];
			ELSIF (i>=4) & (i<=6) THEN
				i := i - 4;
				WMGraphics.ColorToRGBA(colors[j], r, g, b, a);
				r := 255-ENTIER((3-i)/4*(255-r)); g:= 255-ENTIER((3-i)/4*(255-g)); b:= 255-ENTIER((3-i)/4*(255-b));
				cColor := WMGraphics.RGBAToColor(r, g, b, a);
			ELSE
			END;
			IF (y>0) & (y<bounds.GetHeight()) & (x>0) &(x<bounds.GetWidth())THEN
				ChosenColorProc(cColor);
			END;
		END PointerDown;

		PROCEDURE DrawBackground*(canvas: WMGraphics.Canvas);
		VAR r, g, b, a, i, j, color: LONGINT;
		BEGIN
			DrawBackground^(canvas);
			
			FOR i := 0 TO 2 DO
				FOR j := 0 TO 18 DO
					WMGraphics.ColorToRGBA(colors[j], r, g, b, a);
					r := ENTIER((i+1)/4*r); g:= ENTIER((i+1)/4*g); b:= ENTIER((i+1)/4*b);
					color := WMGraphics.RGBAToColor(r, g, b, a);
					canvas.Fill(WMRectangles.MakeRect(10*j,10*i,10*j+10,10*i+10),color , WMGraphics.ModeCopy);
				END;
			END;

			FOR j := 0 TO 18 DO
				color := colors[j];
				canvas.Fill(WMRectangles.MakeRect(10*j,30,10*j+10,10+30),color , WMGraphics.ModeCopy);
			END;

			FOR i := 0 TO 2 DO
				FOR j := 0 TO 18 DO
					WMGraphics.ColorToRGBA(colors[j], r, g, b, a);
					r := 255-ENTIER((3-i)/4*(255-r)); g:= 255-ENTIER((3-i)/4*(255-g)); b:= 255-ENTIER((3-i)/4*(255-b));
					color := WMGraphics.RGBAToColor(r, g, b, a);
					canvas.Fill(WMRectangles.MakeRect(10*j,10*i+40,10*j+10,10*i+10+40),color , WMGraphics.ModeCopy);
				END;
			END;		
		END DrawBackground;
		
		PROCEDURE BuildPalette;
		BEGIN
			colors[0] := 0FF0000FFH;							(* red *)
			colors[1] := 0FF5500FFH;
			colors[2] := 0FFAA00FFH;
			colors[3] := 0FFFF00FFH;							(* yellow *)
			colors[4] := 0AAFF00FFH;
			colors[5] := 055FF00FFH;
			colors[6] := 000FF00FFH;							(* green *)
			colors[7] := 000FF55FFH;
			colors[8] := 000FFAAFFH;
			colors[9] := 000FFFFFFH;							(* cyan *)
			colors[10] := 000AAFFFFH;
			colors[11] := 00055FFFFH;
			colors[12] := 00000FFFFH;						(* blue *)
			colors[13] := 05500FFFFH;
			colors[14] := 0AA00FFFFH;
			colors[15] := 0FF00FFFFH;						(* magenta *)
			colors[16] := 0FF00AAFFH;
			colors[17] := 0FF0055FFH;
			colors[18] := 0888888FFH;						(* grey *)			
		END BuildPalette;
	
	END ColorSwatchPanel;		

END WMPopups.
-----------------------------------------------------
S.Free WMPopups
