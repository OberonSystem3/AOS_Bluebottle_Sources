MODULE WMTextView;	(** AUTHOR "TF"; PURPOSE "Generic unicode text viewer"; *)

IMPORT
	AosModules, AosInputs, AosOut, AosTexts, AosTextUtilities, 
	WMGraphics, WMGraphicUtilities, WMMessages, WMComponents, 
	WMStandardComponents, Utilities, WMDropTarget, Raster,
	WMRectangles, WMWindowManager, WMProperties, AosKernel, AosCommands;

CONST
	TraceRenderOptimize = 0;
	TraceLayout = 1;
	TraceBaseLine = 2;
	TraceInvalidate = 3;
	Trace = { };
	
	Wrap* = 0; WrapWord* = 1;
	AlignLeft = 0; AlignRight = 1; AlignCenter = 2;
	
	DragDist = 5;
	MaxCallParameterBuf = 1 * 1024 * 1024;
	
TYPE
	Char32 = AosTexts.Char32;
	String = Utilities.String;

	TabStops* = OBJECT
	VAR tabDist : LONGINT;
		(* return the next TabStop from the x position *)
		PROCEDURE GetNextTabStop*(x : LONGINT) : LONGINT;
		BEGIN
			RETURN ((x DIV tabDist) + 1) * tabDist
		END GetNextTabStop;
	END TabStops;

	LineInfo = RECORD
		height, width, ascent : LONGINT;
		pos : LONGINT; (* the position in the text, where this line starts *)
		align : LONGINT;
		flags : SET;
		tabStops : TabStops;
	END;
	
	LineInfoArray = POINTER TO ARRAY OF LineInfo;

TYPE
	Layout = OBJECT
	VAR
		nofLines : LONGINT;
		lines : LineInfoArray;
		text : AosTexts.Text;
		paperWidth : LONGINT;
		textWidth : LONGINT; (* maximal width of the text <= textWidth *)
		textHeight : LONGINT; 
		layoutLineProc : PROCEDURE {DELEGATE} (VAR pos : LONGINT; VAR lineInfo : LineInfo; wrapWidth, stopPos, stopXPos : LONGINT);
		
		PROCEDURE &New;
		BEGIN
			NEW(lines, 4)
		END New;
		
		(** Replace the text *)
		PROCEDURE SetText*(t : AosTexts.Text);
		BEGIN
			text := t
		END SetText;
		
		PROCEDURE GrowLines;
		VAR i : LONGINT; newLines : LineInfoArray;
		BEGIN
			NEW(newLines, LEN(lines) * 2);
			FOR i := 0 TO LEN(lines) - 1 DO newLines[i] := lines[i] END;
			lines := newLines
		END GrowLines;
		
		(** find the linenumber by the position *)
		PROCEDURE FindLineNrByPos(pos : LONGINT) : LONGINT;
		VAR a, b, m, i : LONGINT;
		BEGIN
			a := 0; b := nofLines - 1;
			WHILE (a < b) DO m := (a + b) DIV 2; 
				IF lines[m].pos <= pos THEN a := m + 1 
				ELSE b := m
				END 
			END;
			(* last line hack *)
			IF lines[a].pos <= pos THEN INC(a) END; 
(*			i := 0; WHILE (i < nofLines) & (lines[i].pos <= pos) DO INC(i) END;
			IF a - 1 # i - 1 THEN
				AosOut.String("OffByOne"); AosOut.String("a - 1 = "); AosOut.Int(a - 1, 0); AosOut.String(" i - 1 = "); AosOut.Int(i - 1, 0); AosOut.Ln; 
			END; *)
			RETURN a - 1
		END FindLineNrByPos;
		
		PROCEDURE GetLineStartPos(lineNr : LONGINT) : LONGINT;
		BEGIN
			IF (lineNr >= 0) & (lineNr < nofLines) THEN RETURN lines[lineNr].pos ELSE RETURN 0 END
		END GetLineStartPos;
		
		(** return the length in characters of this line *)
		PROCEDURE GetLineLength(lineNr : LONGINT) : LONGINT;
		BEGIN
			IF (lineNr >= 0) & (lineNr < nofLines - 1) THEN RETURN lines[lineNr + 1].pos - lines[lineNr].pos 
			ELSE 
				IF (lineNr >= 0) & (lineNr < nofLines) THEN RETURN  text.GetLength() - lines[lineNr].pos + 1
				ELSE RETURN 0
				END
			END
		END GetLineLength;
		
		PROCEDURE GetNofLines() : LONGINT;
		BEGIN
			RETURN nofLines
		END GetNofLines;
		
		PROCEDURE LayoutLine(VAR pos : LONGINT; VAR lineInfo : LineInfo);
		BEGIN
			IF layoutLineProc # NIL THEN layoutLineProc(pos, lineInfo, paperWidth, -1, -1) END
		END LayoutLine;

		(* generate a new layout from scratch *)
		PROCEDURE FullLayout;
		VAR i, pos, oldpos : LONGINT;
		BEGIN
			IF text = NIL THEN RETURN END;
			textWidth := 0;
			ASSERT(lines#NIL);
			text.AcquireRead;
			IF TraceLayout IN Trace THEN AosOut.String("FullLayout"); AosOut.Ln END;
			i := 0;
			pos := 0; nofLines := 0; textHeight := 0;
			WHILE pos < text.GetLength() DO
				oldpos := pos;
				LayoutLine(pos, lines[nofLines]); INC(textHeight, lines[nofLines].height);
				textWidth := Utilities.Max(textWidth, lines[nofLines].width);
				ASSERT(pos > oldpos);
				IF TraceLayout IN Trace THEN AosOut.String("Line from : "); AosOut.Int(lines[nofLines].pos, 5); AosOut.Ln END;
				lines[nofLines].align := AlignLeft;
				INC(nofLines); IF nofLines >= LEN(lines) THEN GrowLines END
			END;
			IF TraceLayout IN Trace THEN AosOut.String("FullLayout found "); AosOut.Int(nofLines, 4); AosOut.String(" lines"); AosOut.Ln END;
			text.ReleaseRead
		END FullLayout;
		
		(** Fix the layouting of the text starting at pos where delta characters have been inserted (delta negativ if deleted) *)
		PROCEDURE FixLayoutFrom(pos, delta : LONGINT; VAR first, last : LONGINT; VAR linesChanged : BOOLEAN);
		VAR l, dl, oldh : LONGINT;
		BEGIN
			ASSERT(text#NIL);
			text.AcquireRead;
			 linesChanged := FALSE;
			l := FindLineNrByPos(pos);
			IF (l < 0) THEN FullLayout; first := 0; last := nofLines; text.ReleaseRead; RETURN END;
			pos := lines[l].pos;
			oldh := lines[l].height;
			LayoutLine(pos, lines[l]);
			IF oldh # lines[l].height THEN linesChanged := TRUE END;
			first := l;
			INC(l); dl := 0;
			IF (delta < 0) THEN
				IF (l >= nofLines) OR (lines[l].pos + delta = pos) THEN
					last := l; 
					WHILE (l < nofLines) DO lines[l].pos := lines[l].pos + delta; INC(l) END 
				ELSE
					linesChanged := TRUE;
					WHILE (pos < text.GetLength())   DO
						DEC(textHeight, lines[l].height);
						LayoutLine(pos, lines[l]);
						textWidth := Utilities.Max(textWidth, lines[l].width);
						INC(textHeight, lines[nofLines].height);
						INC(dl);
						IF TraceLayout IN Trace THEN AosOut.String("Line from : "); AosOut.Int(lines[nofLines].pos, 5); AosOut.Ln END;	
						INC(l)
					END;
					nofLines := l ;
					last := nofLines - 1
				END
			ELSE
				WHILE (pos < text.GetLength()) & (lines[l].pos + delta # pos)  DO
					linesChanged := TRUE;
					DEC(textHeight, (lines[l].height)); 
					LayoutLine(pos, lines[l]);
					textWidth := Utilities.Max(textWidth, lines[l].width);
					INC(textHeight, (lines[nofLines].height));
					INC(dl);
					IF TraceLayout IN Trace THEN AosOut.String("Line from : "); AosOut.Int(lines[nofLines].pos, 5); AosOut.Ln END;	
					INC(l); IF l >= LEN(lines) THEN GrowLines END
				END;
				last := l;
				IF TraceLayout IN Trace THEN 
					AosOut.String("Delta Lines : "); AosOut.Int(dl, 4); AosOut.Ln;	
					AosOut.String("Lines to redraw : "); AosOut.Int(first, 5); AosOut.String(" to "); AosOut.Int(last, 5); AosOut.Ln
				END;
				(* fix up the positions *)
				IF l < nofLines THEN WHILE (l < nofLines) DO lines[l].pos := lines[l].pos + delta; INC(l) END
				ELSE nofLines := l
				END
			END;
			text.ReleaseRead
		END FixLayoutFrom; 
		
	END Layout;

CONST HLOver* = 0; HLUnder* = 1; HLWave* = 2; 

TYPE
	Highlight* = OBJECT
	VAR
		kind : LONGINT;
		from*, to* : AosTexts.TextPosition;
		a*, b* : LONGINT; (* only valid after sort, while holding the lock *)
		active* : BOOLEAN; (* only valid after sort, while holding the lock *)
		oldFrom, oldTo : LONGINT;
		color : WMGraphics.Color;
		text : AosTexts.UnicodeText;
		onChanged : WMMessages.CompCommand;
		
		PROCEDURE &New;
		BEGIN
			color := 0FF80H
		END New;
		
		PROCEDURE SetKind*(kind : LONGINT);
		BEGIN
			IF SELF.kind # kind THEN
				SELF.kind := kind;
				onChanged(SELF, NIL)
			END
		END SetKind;
		
		PROCEDURE SetColor*(color : WMGraphics.Color);
		BEGIN
			IF SELF.color # color THEN
				SELF.color := color;
				onChanged(SELF, NIL)
			END
		END SetColor;
		
		PROCEDURE SetFrom*(from : LONGINT);
		BEGIN
			IF text = NIL THEN RETURN END; (* if no text is set, the position within is undef *)
			text.AcquireRead;
			oldFrom := SELF.from.GetPosition();
			IF oldFrom # from THEN
				SELF.from.SetPosition(from);
				onChanged(SELF, NIL)
			END;
			text.ReleaseRead
		END SetFrom;
		
		PROCEDURE SetTo*(to : LONGINT);
		BEGIN
			IF text = NIL THEN RETURN END; (* if no text is set, the position within is undef *)
			text.AcquireRead;
			oldTo := SELF.to.GetPosition();
			IF oldTo # to THEN
				SELF.to.SetPosition(to);
				onChanged(SELF, NIL)
			END;
			text.ReleaseRead
		END SetTo;
		
		PROCEDURE SetFromTo*(from, to : LONGINT);
		VAR t : LONGINT;
		BEGIN
			IF text = NIL THEN RETURN END; (* if no text is set, the position within is undef *)
			text.AcquireRead;
			oldTo := SELF.to.GetPosition();
			oldFrom := SELF.from.GetPosition();
			
			IF (oldTo # to) OR (oldFrom # from) THEN 
				IF  ((oldTo = oldFrom) & (to = from)) THEN
					SELF.to.SetPosition(to);
					SELF.from.SetPosition(from)
				ELSE
					SELF.to.SetPosition(to);
					SELF.from.SetPosition(from);
					onChanged(SELF, NIL) 
				END
			END;
			text.ReleaseRead
		END SetFromTo;
		
		PROCEDURE Sort*;
		VAR t : LONGINT;
		BEGIN
			a := from.GetPosition();
			b := to.GetPosition();
			IF a > b THEN t := a; a := b; b := t END;
			active := a # b
		END Sort;
		
		PROCEDURE SetText(text : AosTexts.UnicodeText);
		BEGIN
			IF text # NIL THEN SELF.text := text; NEW(from, text); NEW(to, text) END
		END SetText;
		
	END Highlight;
	
	HighlightArray = POINTER TO ARRAY OF Highlight;
	
TYPE 
	PositionMarker* = OBJECT
	VAR
		pos : AosTexts.TextPosition;
		
		img : WMGraphics.Image;
		str : String;
		color : WMGraphics.Color;
		
		hotX, hotY : LONGINT;
		currentArea : WMRectangles.Rectangle;
		ascent : LONGINT; 
		text : AosTexts.UnicodeText;
		onChanged : WMMessages.CompCommand;
		visible : BOOLEAN;
		
		PROCEDURE &Init;
		BEGIN
			color := 0FF0000CCH; visible := TRUE
		END Init;
		
		PROCEDURE Draw(canvas : WMGraphics.Canvas; x, y, ascent : LONGINT);
		BEGIN
			IF ~visible THEN RETURN END;
			IF img # NIL THEN canvas.DrawImage(x - hotX, y - hotY, img, WMGraphics.ModeSrcOverDst)
			ELSE
				currentArea := GetArea(x, y, ascent);
				canvas.Fill(currentArea, 0FF0000CCH, WMGraphics.ModeSrcOverDst)
			END
		END Draw;
		
		PROCEDURE GetArea(x, y, ascent : LONGINT) : WMRectangles.Rectangle;
		BEGIN
			IF img # NIL THEN RETURN WMRectangles.MakeRect(x - hotX, y - hotY, x - hotX + img.width, y - hotY + img.height)
			ELSE RETURN WMRectangles.MakeRect(x , y - ascent, x + 2, y)
			END
		END GetArea;
		
		PROCEDURE Load*(filename : ARRAY OF CHAR);
		BEGIN
			img := WMGraphics.LoadImage(filename, TRUE);
			IF img # NIL THEN hotX := img.width DIV 2; hotY := img.height END;
			onChanged(SELF, NIL)
		END Load;
		
		PROCEDURE SetVisible*(visible : BOOLEAN);
		BEGIN
			IF SELF.visible # visible THEN 
				SELF.visible := visible;
				onChanged(SELF, NIL)
			END
		END SetVisible;
		
		PROCEDURE SetPosition*(pos : LONGINT);
		BEGIN
			IF text = NIL THEN RETURN END; (* if no text is set, the position within is undef *)
			text.AcquireRead;
			IF pos # SELF.pos.GetPosition() THEN
				SELF.pos.SetPosition(pos);
				onChanged(SELF, NIL)
			END;
			text.ReleaseRead
		END SetPosition;
		
		PROCEDURE GetPosition*() : LONGINT;
		BEGIN
			RETURN pos.GetPosition()
		END GetPosition;
		
		PROCEDURE SetColor*(color : WMGraphics.Color);
		BEGIN
			IF SELF.color # color THEN
				SELF.color := color;
				onChanged(SELF, NIL)
			END
		END SetColor;
		
		PROCEDURE SetText(text : AosTexts.UnicodeText);
		BEGIN
			IF text # NIL THEN SELF.text := text; NEW(pos, text); END
		END SetText;
	END PositionMarker;
	
	PositionMarkerArray = POINTER TO ARRAY OF PositionMarker;
	
TYPE TextDropTarget* = OBJECT(WMDropTarget.DropTarget);
	VAR text : AosTexts.Text;
		pos : AosTexts.TextPosition;
		
		PROCEDURE &New(text : AosTexts.Text; pos : AosTexts.TextPosition);
		BEGIN
			SELF.text := text; SELF.pos := pos
		END New;

		PROCEDURE GetInterface*(type : LONGINT) : WMDropTarget.DropInterface;
		VAR di : WMDropTarget.DropText;
		BEGIN
			IF type = WMDropTarget.TypeText THEN
				NEW(di); di.text := text; di.pos := pos;
				RETURN di
			ELSE RETURN NIL
			END
		END GetInterface;		
		
	END TextDropTarget;


TYPE
	TextView* = OBJECT(WMComponents.VisualComponent)
	VAR 
		text : AosTexts.Text;
		firstLine* : WMProperties.Int32Property;
		firstLineI : LONGINT;
		
		leftShift* : WMProperties.Int32Property;
		leftShiftI : LONGINT; (* number of units, the view is shifted to left -> line scrolling *)
		
		bordersI, borderClip : WMRectangles.Rectangle;
		borders* : WMProperties.RectangleProperty;

		layout : Layout;
		utilreader : AosTexts.TextReader; (* single process ! *)
		(* if the view is a password view *)
		isPassword* : WMProperties.BooleanProperty;
		isPasswordI : BOOLEAN; (* cache of the property value to avoid per-character-locks *)
		
		alwaysShowCursor* : WMProperties.BooleanProperty;
		alwaysShowCursorI : BOOLEAN;
		
		passwordChar* : WMProperties.Int32Property; (* not cached *)
		defaultTextColor*, defaultTextBgColor* : WMProperties.ColorProperty; (* cached in defaultAttr *) 
		defaultAttr : AosTexts.Attributes; 
		
		(* wrapping *)
		wrap : SET;
		isMultiLine* : WMProperties.BooleanProperty;
		isMultiLineI : BOOLEAN;
		
		clipState : WMGraphics.CanvasState;

		showBorder* : WMProperties.BooleanProperty;
		showBorderI : BOOLEAN;
		
		defaultTabStops : TabStops;
		vScrollbar : WMStandardComponents.Scrollbar;
		hScrollbar : WMStandardComponents.Scrollbar;
		
		(* highlighting *)
		nofHighlights : LONGINT;
		highlights : HighlightArray;
		
		(* marked positions *)
		nofPositionMarkers : LONGINT;
		positionMarkers : PositionMarkerArray;
		
		cursor- : PositionMarker;
		selection- : Highlight;
		selecting : BOOLEAN;
		
		dragPossible : BOOLEAN;
		dragSelA, dragSelB : AosTexts.TextPosition;
		dragCopy : BOOLEAN;
		
		canStart : BOOLEAN; (* set for command selection mode *)
		commandMarker : Highlight;
		
		downX, downY : LONGINT;
		selectWords : BOOLEAN;
		wordSelOrdered : BOOLEAN;
		lineEnter : LONGINT;
		modifierFlags : SET;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
			NEW(layout);
			layout.layoutLineProc := LayoutLine;
			NEW(defaultAttr); 
			NEW(defaultTabStops); defaultTabStops.tabDist := 20;
			NEW(highlights, 4); nofHighlights := 0;
			NEW(positionMarkers, 4); nofPositionMarkers := 0;
			cursor := CreatePositionMarker();
			selection := CreateHighlight();
			selection.kind := HLOver;
			selection.color := 0000FF80H;
			wrap := { WrapWord };
			(* properties *)
			NEW(firstLine, PTVfirstLine, NIL, NIL); properties.Add(firstLine);
			NEW(leftShift, PTVleftShift, NIL, NIL); properties.Add(leftShift);
			NEW(isMultiLine, PTVIsMultiLine, NIL, NIL); properties.Add(isMultiLine);
			NEW(isPassword, PTVIsPassword, NIL, NIL); properties.Add(isPassword);
			NEW(passwordChar, PTVPasswordChar, NIL, NIL); properties.Add(passwordChar);
			NEW(showBorder, PTVShowBorder, NIL, NIL); properties.Add(showBorder);
			NEW(defaultTextColor, PTVdefaultTextColor, NIL, NIL); properties.Add(defaultTextColor);
			NEW(defaultTextBgColor, PTVdefaultTextBgColor, NIL, NIL); properties.Add(defaultTextBgColor);
			NEW(alwaysShowCursor, PTValwaysShowCursor, NIL, NIL); properties.Add(alwaysShowCursor);
			NEW(borders, PTVborders, NIL, NIL); properties.Add(borders);
			takesFocus.Set(TRUE); needsTab.Set(TRUE);
			SetPointerInfo(manager.pointerText);
			RecacheProperties
		END Init;
		
		PROCEDURE Invalidate;
		BEGIN
			Invalidate^;
		END Invalidate; 
		
		PROCEDURE FocusReceived*;
		BEGIN
			FocusReceived^;
			cursor.SetVisible(TRUE)
		END FocusReceived;
		
		PROCEDURE FocusLost*;
		BEGIN
			FocusLost^;
			IF ~alwaysShowCursorI THEN cursor.SetVisible(FALSE) END
		END FocusLost;
		
		PROCEDURE SetWrapMode*(wrapMode : SET);
		BEGIN
			IF wrapMode # wrap THEN 
				wrap := wrapMode;
				layout.FullLayout; CheckNumberOfLines;
				Invalidate
			END
		END SetWrapMode;
		
		PROCEDURE RecacheProperties;
		VAR oldBorders : WMRectangles.Rectangle;
		BEGIN
			RecacheProperties^;
			IF TraceInvalidate IN Trace THEN AosOut.String("R") END;
			isMultiLineI := isMultiLine.Get();
			isPasswordI := isPassword.Get();
			firstLineI := firstLine.Get();
			leftShiftI := leftShift.Get();
			alwaysShowCursorI := alwaysShowCursor.Get();
			showBorderI := showBorder.Get();
			oldBorders := bordersI; bordersI := borders.Get();
			defaultAttr.color := defaultTextColor.Get(); defaultAttr.bgcolor := defaultTextBgColor.Get();
			UpdateScrollbars;
			IF ~WMRectangles.IsEqual(oldBorders, bordersI) THEN BordersChanged END;
			Invalidate;
		END RecacheProperties;
		
		PROCEDURE Initialize*;
		BEGIN
			Initialize^;
			cursor.SetVisible(FALSE);
			Resized
		END Initialize;
		
		PROCEDURE SetScrollbars*(hScrollbar, vScrollbar : WMStandardComponents.Scrollbar);
		BEGIN
			Acquire;
			IF hScrollbar # NIL THEN hScrollbar.onPositionChanged.Remove(ScrollbarsChanged) END;	
			IF vScrollbar # NIL THEN vScrollbar.onPositionChanged.Remove(ScrollbarsChanged) END;	
			SELF.hScrollbar := hScrollbar; SELF.vScrollbar := vScrollbar;
			hScrollbar.onPositionChanged.Add(ScrollbarsChanged);
			vScrollbar.onPositionChanged.Add(ScrollbarsChanged);
			UpdateScrollbars;
			Release
		END SetScrollbars;
		
		PROCEDURE ScrollbarsChanged*(sender, data : PTR);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.ScrollbarsChanged, sender, data)
			ELSE
				IF sender = vScrollbar THEN 
					firstLine.Set(vScrollbar.pos.Get())
				ELSIF sender = hScrollbar THEN leftShift.Set(hScrollbar.pos.Get()) 
				END
			END
		END ScrollbarsChanged;
		
		PROCEDURE UpdateScrollbars;
		BEGIN
			IF vScrollbar # NIL THEN
				vScrollbar.max.Set(layout.GetNofLines());
				
				vScrollbar.pos.Set(firstLineI);
			END;
			IF hScrollbar # NIL THEN 
	(*			hScrollbar.visible.Set(layout.textWidth > bounds.GetWidth()); *)
				hScrollbar.max.Set(layout.textWidth);
				hScrollbar.pageSize.Set(bounds.GetWidth()); 
				hScrollbar.pos.Set(leftShiftI);
			END;
		END UpdateScrollbars;
		
		PROCEDURE BordersChanged;
		BEGIN
			borderClip := WMRectangles.MakeRect(bordersI.l, bordersI.t, bounds.GetWidth() - bordersI.r, bounds.GetHeight() - bordersI.b);
			layout.paperWidth := bounds.GetWidth() - (bordersI.l + bordersI.r);
			layout.FullLayout; CheckNumberOfLines;
		END BordersChanged;
		
		PROCEDURE PropertyChanged*(sender, data : PTR);
		BEGIN
			IF data = firstLine THEN firstLineI := firstLine.Get(); UpdateScrollbars; 
				IF TraceInvalidate IN Trace THEN AosOut.String("fl ") END; Invalidate
			ELSIF data = isPassword THEN isPasswordI := isPassword.Get(); 
				IF TraceInvalidate IN Trace THEN AosOut.String("ip ") END; Invalidate
			ELSIF data = leftShift THEN leftShiftI := leftShift.Get(); UpdateScrollbars; 
				IF TraceInvalidate IN Trace THEN AosOut.String("ls ") END; Invalidate
			ELSIF data = showBorder THEN showBorderI := showBorder.Get(); 
				IF TraceInvalidate IN Trace THEN AosOut.String("sb ") END; Invalidate
			ELSIF data = defaultTextColor THEN defaultAttr.color := defaultTextColor.Get(); 
				IF TraceInvalidate IN Trace THEN AosOut.String("dtc ") END; Invalidate
			ELSIF data = defaultTextBgColor THEN defaultAttr.bgcolor := defaultTextBgColor.Get(); 
				IF TraceInvalidate IN Trace THEN AosOut.String("dbg ") END; Invalidate
			ELSIF data = borders THEN bordersI := borders.Get(); 
				IF TraceInvalidate IN Trace THEN AosOut.String("brdrs ") END; Invalidate
			ELSE PropertyChanged^(sender, data)
			END
		END PropertyChanged;
		
		PROCEDURE Resized;
		BEGIN
			Resized^;
			layout.paperWidth := bounds.GetWidth() - (bordersI.l + bordersI.r);
			borderClip.r := bounds.GetWidth() - bordersI.r; borderClip.b := bounds.GetHeight() - bordersI.b;
			layout.FullLayout; CheckNumberOfLines;
		END Resized;
		
		(** Replace the text *)
		PROCEDURE SetText*(t : AosTexts.Text);
		VAR i : LONGINT;
		BEGIN
			ASSERT(t # NIL);
			Acquire; 
			IF text # NIL THEN text.onTextChanged.Remove(TextChanged) END;  (* unregister the TextChanged listener from the old text *)
			text := t; 
			text.onTextChanged.Add(TextChanged); (* register the TextChanged listener with the new text*)
			NEW(utilreader, text); 
			(* update all highlights *)
			FOR i := 0 TO nofHighlights - 1 DO highlights[i].SetText(text) END;
			FOR i := 0 TO nofPositionMarkers - 1 DO positionMarkers[i].SetText(text) END;
			layout.SetText(text);
			layout.FullLayout;
			CheckNumberOfLines;
			Invalidate;
			Release
		END SetText;

(* BEGIN highlighting *)
		PROCEDURE AddHighlight(highlight : Highlight);
		VAR newHighlights : HighlightArray; i : LONGINT;
		BEGIN
			INC(nofHighlights);
			IF nofHighlights > LEN(highlights) THEN
				NEW(newHighlights, LEN(highlights) * 2);
				FOR i := 0 TO LEN(highlights) - 1 DO newHighlights[i] := highlights[i] END;
				highlights := newHighlights;
			END;
			highlights[nofHighlights - 1] := highlight;
			HighlightChanged(NIL, NIL);
		END AddHighlight;
		
		PROCEDURE CreateHighlight*() : Highlight;
		VAR h : Highlight;
		BEGIN
			Acquire;
			NEW(h); h.SetText(text);
			h.onChanged := HighlightChanged;
			AddHighlight(h);
			Release;
			RETURN h
		END CreateHighlight;
		
		PROCEDURE RemoveHighlight*(x : Highlight);
		VAR i : LONGINT;
		BEGIN 
			Acquire;
			i := 0; WHILE (i < nofHighlights) & (highlights[i] # x) DO INC(i) END;
			IF i < nofHighlights THEN 
				WHILE (i < nofHighlights - 1) DO highlights[i] := highlights[i+1]; INC(i) END;
				DEC(nofHighlights);
				highlights[nofHighlights] := NIL
			END;
			HighlightChanged(NIL, NIL);
			Release
		END RemoveHighlight;
		
		PROCEDURE InvalidateRange(a, b : LONGINT);
		VAR t, l0, l1 : LONGINT; x0, y0, x1, y1, d : LONGINT;
		BEGIN
			IF a > b THEN t := a; a := b; b := t END;
			
			l0 := layout.FindLineNrByPos(a);
			l1 := layout.FindLineNrByPos(b);
			IF l0 = l1 THEN (* only one line... optimize *)
				LineYPos(l0, y0, y1);
				IF ~(FindScreenPos(a, x0, d) & FindScreenPos(b, x1, d)) THEN
					x0 := 0; x1 := bounds.GetWidth()
				END;
				InvalidateRect(WMRectangles.MakeRect(x0, y0, x1, y1));
			ELSE
				LineYPos(l0, y0, d); LineYPos(l1, d, y1);
				InvalidateRect(WMRectangles.MakeRect(0, y0, bounds.GetWidth(), y1));							
			END;
			IF TraceInvalidate IN Trace THEN AosOut.String("ir ") END;	
		END InvalidateRange;
		
		PROCEDURE HighlightChanged(sender, data : PTR);
		VAR hl : Highlight; min, max : LONGINT;
		BEGIN
			IF ~initialized THEN RETURN END;
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.HighlightChanged, sender, data)
			ELSE
				text.AcquireRead;
				IF (sender # NIL) & (sender IS Highlight) THEN
					hl := sender(Highlight);
					IF (hl.oldFrom # hl.from.GetPosition()) & (hl.oldTo # hl.to.GetPosition()) THEN (* both changed *)
						min := Utilities.Min(
										Utilities.Min(hl.oldFrom, hl.from.GetPosition()), 
										Utilities.Min(hl.oldTo, hl.to.GetPosition())); 
						max := Utilities.Max(
										Utilities.Max(hl.oldFrom, hl.from.GetPosition()), 
										Utilities.Max(hl.oldTo, hl.to.GetPosition())); 
						InvalidateRange(min, max)
					ELSIF hl.oldTo # hl.to.GetPosition() THEN (* to changed *)
						InvalidateRange(hl.oldTo, hl.to.GetPosition())
					ELSIF hl.oldFrom # hl.from.GetPosition() THEN (* from changed *)
						InvalidateRange(hl.oldFrom, hl.from.GetPosition())
					ELSE (* position noch changed... probably color, style or visibility changed, invalidate range *)
						InvalidateRange(hl.from.GetPosition(),hl.to.GetPosition())
					END
				ELSE
					IF TraceInvalidate IN Trace THEN AosOut.String("H") END;
					Invalidate
				END;
				text.ReleaseRead
			END
		END HighlightChanged;
(* END highlighting *)

(* BEGIN PositionMarkers *)
		PROCEDURE AddPositionMarker(pm : PositionMarker);
		VAR newPositionMarkers : PositionMarkerArray; i : LONGINT;
		BEGIN
			INC(nofPositionMarkers);
			IF nofPositionMarkers > LEN(positionMarkers) THEN
				NEW(newPositionMarkers, LEN(positionMarkers) * 2);
				FOR i := 0 TO LEN(positionMarkers) - 1 DO newPositionMarkers[i] := positionMarkers[i] END;
				positionMarkers := newPositionMarkers
			END;
			positionMarkers[nofPositionMarkers - 1] := pm
		END AddPositionMarker;
		
		PROCEDURE CreatePositionMarker*() : PositionMarker;
		VAR p : PositionMarker;
		BEGIN
			Acquire;
			NEW(p); p.SetText(text);
			p.onChanged := PositionMarkerChanged;
			AddPositionMarker(p);
			Release;
			RETURN p
		END CreatePositionMarker;
		
		PROCEDURE RemovePositionMarker*(x : PositionMarker);
		VAR i, xp, yp, l : LONGINT; newRect : WMRectangles.Rectangle; 
		BEGIN 
			Acquire;
			i := 0; WHILE (i < nofPositionMarkers) & (positionMarkers[i] # x) DO INC(i) END;
			IF i < nofPositionMarkers THEN 
				WHILE (i < nofPositionMarkers - 1) DO positionMarkers[i] := positionMarkers[i+1]; INC(i) END;
				DEC(nofPositionMarkers);
				positionMarkers[nofPositionMarkers] := NIL
			END;
			IF FindScreenPos(x.pos.GetPosition(), xp, yp) THEN
				l := layout.FindLineNrByPos(x.pos.GetPosition());
				IF (l < LEN(layout.lines^)) & (l >= 0) THEN
					newRect := x.GetArea(xp, yp, (layout.lines[l].ascent));
					InvalidateRect(newRect)
				END
			END;
			Release
		END RemovePositionMarker;
		
		PROCEDURE PositionMarkerChanged(sender, data : PTR);
		VAR newRect, combinedRect : WMRectangles.Rectangle; x, y, l : LONGINT;
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.PositionMarkerChanged, sender, data)
			ELSE
				data := sender;
				IF (data # NIL) & (data IS PositionMarker) THEN
					IF data = cursor THEN CheckCursor END;
					text.AcquireRead;
					IF FindScreenPos(data(PositionMarker).pos.GetPosition(), x, y) THEN
						l := layout.FindLineNrByPos(data(PositionMarker).pos.GetPosition());
						IF (l < LEN(layout.lines^)) & (l >= 0) THEN
							newRect := data(PositionMarker).GetArea(x, y, (layout.lines[l].ascent))
						END
					END;
					
					combinedRect := data(PositionMarker).currentArea;
					IF WMRectangles.RectEmpty(combinedRect) THEN combinedRect := newRect
					ELSE WMRectangles.ExtendRect(combinedRect, newRect)
					END;
					IF ~WMRectangles.RectEmpty(combinedRect) THEN
						IF (WMRectangles.Area(data(PositionMarker).currentArea) + WMRectangles.Area(newRect)) * 5 <  WMRectangles.Area(combinedRect) THEN 
							InvalidateRect(data(PositionMarker).currentArea);
							InvalidateRect(newRect)
						ELSE
							InvalidateRect(combinedRect)
						END
					END;
					text.ReleaseRead;
				ELSE
					Invalidate; AosOut.String("Editor: XXX")
				END;
			END
		END PositionMarkerChanged;
(* END PositionMarkers *)

		PROCEDURE CheckNumberOfLines;
		BEGIN
			UpdateScrollbars;
			firstLine.SetBounds(0, layout.GetNofLines() - 1)
		END CheckNumberOfLines;
		
		PROCEDURE CheckCursor;
		VAR cp, l, i : LONGINT; ty : REAL;
		BEGIN
			(* Scroll up, down to make cursor visible *)
			text.AcquireRead;
			cp := cursor.GetPosition();
			IF (cp < 0) THEN cursor.SetPosition(0)
			ELSIF (cp > text.GetLength()) THEN cursor.SetPosition(text.GetLength())
			END;
			l := layout.FindLineNrByPos(cursor.GetPosition());
			IF (l < firstLineI) THEN
				(* move the cursor down by 3 lines to get more context *)
				l := Utilities.Max(0, l - 3);
				firstLine.Set(l);
			ELSIF (l < layout.GetNofLines()) THEN
				ty := bordersI.t; i := firstLineI;
				WHILE i < l DO ty := ty + layout.lines[i].height; INC(i) END;
				ty := ty + layout.lines[i].height;
				IF ty >= bounds.GetHeight() - bordersI.b THEN 
					l := Utilities.Max(0, l - 3);
					firstLine.Set(l)
				END
			END;
			text.ReleaseRead;
			(* Scroll left right to make cursor visible *)
			(* $$$ TODO *)			
		END CheckCursor;
		

		PROCEDURE TextChanged(sender, data : PTR);
		VAR f, l, t, b, i, h: LONGINT; linesChanged : BOOLEAN;
			info : AosTexts.TextChangeInfo;
		BEGIN
			IF ~initialized THEN RETURN END;
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(SELF.TextChanged, sender, data)
			ELSE
				IF (data # NIL) & (data IS AosTexts.TextChangeInfo) & (data(AosTexts.TextChangeInfo).op # AosTexts.OpMulti) THEN
					text.AcquireRead;
					Acquire;
					info := data(AosTexts.TextChangeInfo);
					IF text.GetTimestamp() = info.timestamp THEN
						info := data(AosTexts.TextChangeInfo);
						IF info.op = AosTexts.OpInsert THEN layout.FixLayoutFrom(info.pos, info.len, f, l, linesChanged) 
						ELSE layout.FixLayoutFrom(info.pos, -info.len, f, l, linesChanged) 
						END;
						t := bordersI.t; FOR i := firstLineI TO f - 1 DO t := t + (layout.lines[i].height) END;
				
						h := bounds.GetHeight();
						IF linesChanged THEN b := h ELSE
							b := t; i := f; WHILE (i <= l) & (b < h) DO b := b + (layout.lines[i].height); INC(i) END
						END;
						CheckCursor; UpdateScrollbars;
						Release;
						InvalidateRect(WMRectangles.MakeRect(0, t, bounds.GetWidth(), b));
					ELSE
						IF TraceRenderOptimize IN Trace THEN AosOut.String("Timestamp not equal ==> Complete re_layout"); AosOut.Ln
						END;
						layout.FullLayout;
						CheckCursor;
						InvalidateRect(GetClientRect())
					END;
					text.ReleaseRead
				ELSE	
					layout.FullLayout;
					CheckCursor;
					InvalidateRect(GetClientRect())
				END;
				CheckNumberOfLines;
			END
		END TextChanged;
		
(* BEGIN view dependant layout functions *)
		(** Return the left indent of a line - depending on alignment *)
		(* returns left border, in case of errors *)
		PROCEDURE GetLineLeftIndent(linenr : LONGINT): LONGINT;
		BEGIN
			IF (linenr < 0) OR (linenr >= layout.nofLines) THEN RETURN 0 END;
			CASE layout.lines[linenr].align OF
				AlignLeft : RETURN 0;
				|AlignRight : RETURN (bounds.GetWidth() - layout.lines[linenr].width);
				|AlignCenter : RETURN (bounds.GetWidth() - (layout.lines[linenr].width)) DIV 2;
			ELSE
				 RETURN 0;
			END;
		END GetLineLeftIndent;
		
		(** Find the line number that currently contains the y value (y relative to 0 in component)*)
		PROCEDURE FindLineByY*(firstLine, y : LONGINT) : LONGINT;
		VAR i : LONGINT; ypos : REAL;
		BEGIN
			ypos := bordersI.t; i := firstLine;
			IF y < 0 THEN RETURN 0 END;
			WHILE (i < layout.nofLines) & (ypos <= y) DO ypos := ypos + layout.lines[i].height; INC(i) END;
			RETURN Utilities.Max(i -1, 0)
		END FindLineByY;

		PROCEDURE ViewToTextPos*(x, y: LONGINT; VAR pos : LONGINT);
		VAR l : LONGINT; dummy : LineInfo;
		BEGIN
			text.AcquireRead;
			pos := -1;
			x := Utilities.Max(0, Utilities.Min(x, bounds.GetWidth()));
			y := Utilities.Max(0, Utilities.Min(y, bounds.GetHeight()));
			
			l := FindLineByY(firstLineI, Utilities.Min(Utilities.Max(y, bordersI.t), bounds.GetHeight() - bordersI.b));
			
			x := x - bordersI.l + leftShiftI;
			IF x < 0 THEN x := 0 END;
			dummy := layout.lines[l];
			IF l >= 0 THEN pos := layout.GetLineStartPos(l); LayoutLine(pos, dummy, layout.paperWidth, -1, x) END;
			text.ReleaseRead
		END ViewToTextPos;

(* END view dependant layout functions *)

		PROCEDURE GetFontFromAttr(info : AosTexts.FontInfo) : WMGraphics.Font;
		BEGIN
			RETURN WMGraphics.GetFont(info.name, info.size, info.style);
		END GetFontFromAttr;
		
		PROCEDURE LayoutLine(VAR pos : LONGINT; VAR l : LineInfo; wrapwidth, stopPos, stopXPos : LONGINT);
		VAR i, wrapPos : LONGINT; ch : Char32;
			f : WMGraphics.Font;
			eol, first : BOOLEAN; 
			voff, ascent, descent, a, d, dx, x : LONGINT;
			
			PROCEDURE GetExtents(ch : Char32; VAR dx, ascent, descent: LONGINT);
			VAR gs : WMGraphics.GlyphSpacings; vc : WMComponents.VisualComponent;
			BEGIN
				IF ch = AosTexts.ObjectChar THEN
					IF (utilreader.object # NIL) & (utilreader.object IS WMGraphics.Image) THEN
						ascent := utilreader.object(WMGraphics.Image).height - voff;
						descent := voff;
						dx :=  utilreader.object(WMGraphics.Image).width 
					ELSIF (utilreader.object # NIL) & (utilreader.object IS WMComponents.VisualComponent) THEN
						vc := utilreader.object(WMComponents.VisualComponent);
						dx := vc.bounds.GetWidth();
						ascent := vc.bounds.GetHeight() - voff;
						descent := voff;
					END
				ELSIF ch = AosTexts.TabChar THEN
					IF l.tabStops # NIL THEN dx := l.tabStops.GetNextTabStop(x) - x 
					ELSE dx := defaultTabStops.GetNextTabStop(x) - x
					END;
					ascent := f.GetAscent() - voff;
					descent := f.GetDescent() + voff
				ELSE
					IF isPasswordI THEN ch := passwordChar.Get() END;
					IF f.HasChar(ch) THEN
						f.GetGlyphSpacings(ch, gs);
				(*		ascent := f.GetAscent() - voff;
						descent := f.GetDescent() + voff *)
					ELSE
						WMGraphics.FBGetGlyphSpacings(ch, gs);
(*						ascent := gs.ascent - voff;
						descent := gs.descent + voff *)
					END;
					ascent := gs.ascent - voff;
					descent := gs.descent + voff;
					dx := gs.bearing.l + gs.width + gs.bearing.r
				END
			END GetExtents; 
			
		BEGIN 
			f := GetFont(); (* set the default component font *)
			x := 0; l.pos := pos; l.height := f.GetHeight(); eol := FALSE; 
			utilreader.SetDirection(1); utilreader.SetPosition(pos); first := TRUE;
			i := 0; ascent := f.GetAscent(); descent := f.GetDescent(); 
			REPEAT
				utilreader.ReadCh(ch);
				IF utilreader.attributes # NIL THEN 
					voff := utilreader.attributes.voff;
					IF utilreader.attributes.fontInfo # NIL THEN
						IF (utilreader.attributes.fontInfo.fontcache # NIL) 
							& (utilreader.attributes.fontInfo.fontcache IS WMGraphics.Font) THEN 
							f := utilreader.attributes.fontInfo.fontcache(WMGraphics.Font);
						ELSE
							f := GetFontFromAttr(utilreader.attributes.fontInfo);
							utilreader.attributes.fontInfo.fontcache := f
						END
					ELSE f := GetFont()
					END					 
				ELSE voff := 0; f := GetFont(); 
				END;
				IF first THEN ascent := f.GetAscent(); descent := f.GetDescent(); first := FALSE END;
				INC(pos);
				IF (stopPos < 0) OR (pos <= stopPos) THEN
					IF ch # AosTexts.NewLineChar THEN
						GetExtents(ch, dx, a, d); ascent := Utilities.Max(ascent, a); descent := Utilities.Max(descent, d);
						IF isMultiLineI & (wrap # {}) & (i > 0) & (x + dx > wrapwidth) THEN
							eol := TRUE; DEC(pos); wrapPos := pos;
							(* Go left for last space *)
							IF wrap * { WrapWord } # {} THEN 
								pos := AosTextUtilities.FindPosWordLeft(utilreader, pos);
								IF pos <= l.pos THEN pos := wrapPos END; (* no word break found. wrap at latest possible pos *)
							END
						ELSE
							IF (stopXPos >= 0) & (x + dx DIV 2 > stopXPos) THEN DEC(pos); RETURN END;
							INC(x, dx)
						END;
					ELSE eol := TRUE; IF (stopXPos >= 0) THEN DEC(pos) END;
					END;
				ELSE eol := TRUE
				END;
				INC(i)
			UNTIL eol OR utilreader.eot;
			l.width := x;
			l.ascent := ascent; l.height := ascent + descent; IF l.height = 0 THEN l.height := f.GetHeight() END
		END LayoutLine;
		
		PROCEDURE LineYPos(lineNr : LONGINT; VAR y0, y1 : LONGINT);
		VAR i : LONGINT;
		BEGIN
			IF (lineNr >= firstLineI) & (lineNr < layout.GetNofLines()) THEN
				y0 := bordersI.t; i := firstLineI;
				WHILE i < lineNr DO y0 := y0 + layout.lines[i].height; INC(i) END;
				y1 := y0 + layout.lines[i].height
			ELSE y0 := 0; y1 := 0
			END	
		END LineYPos;
		
		PROCEDURE FindScreenPos*(pos : LONGINT; VAR x, y : LONGINT) : BOOLEAN;
		VAR l, i, startPos: LONGINT; ty : LONGINT; li : LineInfo; ch : Char32; lastLine : BOOLEAN;
			f : WMGraphics.Font;

		BEGIN 
			text.AcquireRead;
			lastLine := FALSE;
			IF (pos = text.GetLength()) THEN 
				utilreader.SetDirection(1); utilreader.SetPosition(text.GetLength() - 1);
				utilreader.ReadCh(ch);
				IF ch = AosTexts.NewLineChar THEN lastLine := TRUE END
			END;
			IF lastLine THEN
				ty := bordersI.t; i := firstLineI;
				WHILE i < layout.nofLines DO ty := ty + layout.lines[i].height; INC(i) END;
				IF i > 0 THEN y := (ty + layout.lines[i - 1 ].ascent) ELSE y := (ty + 10) END;
				x := bordersI.l - leftShiftI;
				text.ReleaseRead; RETURN TRUE
			ELSIF (pos = 0) & (firstLineI = 0) THEN x := bordersI.l - leftShiftI; f := GetFont();  y := f.GetAscent();
				text.ReleaseRead; RETURN TRUE
			ELSE
				l := layout.FindLineNrByPos(pos);
				IF (l >= firstLineI) & (l < layout.GetNofLines()) THEN
					ty := bordersI.t; i := firstLineI;
					WHILE i < l DO ty := ty + layout.lines[i].height; INC(i) END;
					y := (ty + layout.lines[i].ascent);
					startPos := layout.GetLineStartPos(i);
					LayoutLine(startPos, li, layout.paperWidth, pos, -1);
					x := (li.width + GetLineLeftIndent(l) + bordersI.l - leftShiftI);
					text.ReleaseRead; RETURN TRUE
				ELSE
					text.ReleaseRead; RETURN FALSE	
				END
			END	
		END FindScreenPos;
		
		(* llen = -1 to render until the end of line > 0 to render llen elements in the line *)
		PROCEDURE RenderLine*(canvas : WMGraphics.Canvas; VAR l : LineInfo; linenr, top, llen : LONGINT);
		VAR sx, dx, x, sp, i, j, k, linelength, w, voff, bgcolor, p : LONGINT; char : Char32; gs: WMGraphics.GlyphSpacings;
	 		curAttr : AosTexts.Attributes; font : WMGraphics.Font; vc : WMComponents.VisualComponent;
	 		hc : BOOLEAN;
		BEGIN
			font := GetFont();
			ASSERT(defaultAttr # NIL);
			curAttr := defaultAttr; canvas.SetColor(defaultAttr.color);
			bgcolor := defaultAttr.bgcolor;
			IF TraceRenderOptimize IN Trace THEN 
				AosOut.String("RenderLine : "); AosOut.Int(linenr, 5); AosOut.String(" from position : "); 
				AosOut.Int(layout.GetLineStartPos(linenr), 5); AosOut.Ln;
			END;
		
		(*	sp := layout.GetLineStartPos(linenr); *)
			sp := l.pos;
			IF sp >= text.GetLength() THEN RETURN END;
			utilreader.SetDirection(1); utilreader.SetPosition(sp);
			IF llen < 0 THEN 	linelength := layout.GetLineLength(linenr)
			ELSE linelength := llen
			END;
			i := 0;
			x := GetLineLeftIndent(linenr);
			sx := - leftShiftI + bordersI.l;
			IF TraceBaseLine IN Trace THEN
				canvas.Line(0, top + (l.ascent), bounds.GetWidth(), top + (l.ascent), 01F0000FFH, WMGraphics.ModeCopy) 
			END;
			
			w := bounds.GetWidth() - bordersI.r;
			REPEAT
				utilreader.ReadCh(char);
				IF curAttr # utilreader.attributes THEN
					IF utilreader.attributes # NIL THEN 
						(* Black is the default color *)
						IF utilreader.attributes.color # 0FFH THEN canvas.SetColor(utilreader.attributes.color);
						ELSE canvas.SetColor(defaultAttr.color)
						END;
						IF utilreader.attributes.fontInfo # NIL THEN
							IF (utilreader.attributes.fontInfo.fontcache # NIL) 
								& (utilreader.attributes.fontInfo.fontcache IS WMGraphics.Font) THEN 
								font := utilreader.attributes.fontInfo.fontcache(WMGraphics.Font);
							ELSE
								font := GetFontFromAttr(utilreader.attributes.fontInfo);
								utilreader.attributes.fontInfo.fontcache := font
							END
						ELSE font := GetFont()
						END;			 
						bgcolor := utilreader.attributes.bgcolor;
						voff := utilreader.attributes.voff;
						curAttr := utilreader.attributes
					ELSE
						IF curAttr # defaultAttr THEN
							canvas.SetColor(defaultAttr.color);
							bgcolor := defaultAttr.bgcolor;
							voff := defaultAttr.voff;
							curAttr := defaultAttr;
							font := GetFont()
						END
					END;
				END;
				
				IF char = AosTexts.ObjectChar THEN
					IF (utilreader.object # NIL) & (utilreader.object IS WMGraphics.Image) THEN
						canvas.DrawImage(x, top + (l.ascent) + voff - utilreader.object(WMGraphics.Image).height, utilreader.object(WMGraphics.Image), 
							WMGraphics.ModeSrcOverDst);
						dx := utilreader.object(WMGraphics.Image).width
					ELSIF (utilreader.object # NIL) & (utilreader.object IS WMComponents.VisualComponent) THEN
						vc := utilreader.object(WMComponents.VisualComponent);
						dx := vc.bounds.GetWidth();
						canvas.SaveState(clipState); (* save the current clip-state *)
						canvas.SetClipRect(WMRectangles.MakeRect(x + sx, top, x + dx + sx, top + (l.height)));
						canvas.ClipRectAsNewLimits(x + sx, top);
						(* assuming the component will not delay --> otherwise a buffer is needed *)
						vc.Acquire; vc.Draw(canvas); vc.Release;
						canvas.RestoreState(clipState)
					END
				ELSIF char = 0 THEN (* EOT *)
				ELSIF char = AosTexts.TabChar THEN
					IF l.tabStops # NIL THEN dx := l.tabStops.GetNextTabStop(x) - x 
					ELSE dx := defaultTabStops.GetNextTabStop(x) - x
					END;
					IF bgcolor # 0 THEN 
						canvas.Fill(WMRectangles.MakeRect(x + sx, top, x + dx + sx, top + (l.height)), bgcolor, WMGraphics.ModeCopy)
					END
				ELSE
					IF char = AosTexts.NewLineChar THEN RETURN END;
					IF isPasswordI THEN char := passwordChar.Get() END;
					hc := font.HasChar(char);
					IF hc THEN font.GetGlyphSpacings(char, gs)
					ELSE WMGraphics.FBGetGlyphSpacings(char, gs)
					END;
					dx := gs.bearing.l + gs.width + gs.bearing.r;
					IF bgcolor MOD 256 # 0 THEN 
						canvas.Fill(WMRectangles.MakeRect(x + sx, top, x + dx + sx, top + (l.height)), bgcolor, WMGraphics.ModeCopy)
					END;
					IF hc THEN font.RenderChar(canvas, x + sx, top + (l.ascent) + voff, char)
					ELSE WMGraphics.FBRenderChar(canvas, x + sx, top + (l.ascent) + voff, char)
					END
				END;
				
				(* highlight *)
				p := utilreader.GetPosition();
				FOR j := 0 TO nofHighlights - 1 DO 
					IF (p > highlights[j].a) & (p <= highlights[j].b) THEN
						CASE highlights[j].kind OF
							|HLOver: canvas.Fill(WMGraphics.MakeRectangle(x + sx, top, x + dx + sx, top + (l.height)), highlights[j].color, WMGraphics.ModeSrcOverDst)
							|HLUnder: canvas.Line(x + sx, top + (l.ascent), x + dx + sx, top + (l.ascent), highlights[j].color, WMGraphics.ModeSrcOverDst);
							|HLWave: FOR k := 0 TO dx - 1 DO 
								canvas.SetPixel(x + k + sx, top + (l.ascent) + (1 - ABS((x + k) MOD 4 - 2)), highlights[j].color, WMGraphics.ModeSrcOverDst);
							END;
						ELSE
						END
					END
				END;
				
				x := x + dx;
				INC(i)
			UNTIL (i >= linelength) OR utilreader.eot OR (x + sx > w)
		END RenderLine;
		
		PROCEDURE RenderAboveTextMarkers*(canvas : WMGraphics.Canvas);
		VAR x, y, l, pos, i, ascent : LONGINT;
		BEGIN
			AssertLock;
			IF text = NIL THEN RETURN END;
			text.AcquireRead;
			FOR i := nofPositionMarkers - 1 TO 0 BY -1 DO
				pos := positionMarkers[i].pos.GetPosition();
				l := layout.FindLineNrByPos(pos);
				IF FindScreenPos(pos, x, y) THEN
					IF (l >= 0) & (l < layout.GetNofLines()) THEN ascent := (layout.lines[l].ascent) ELSE ascent := 10 END;	
					positionMarkers[i].Draw(canvas, x, y, ascent)
				END
			END;
			text.ReleaseRead;
		END RenderAboveTextMarkers;

		PROCEDURE Draw*(canvas : WMGraphics.Canvas);
		VAR la, lb, i, top, t : LONGINT; cliprect : WMRectangles.Rectangle; cstate : WMGraphics.CanvasState;
		BEGIN
			ASSERT(layout # NIL);
			canvas.SaveState(cstate);
			canvas.GetClipRect(cliprect);
			IF WMRectangles.RectEmpty(cliprect) THEN RETURN END; 
			
			IF showBorderI THEN 
				WMGraphicUtilities.DrawBevel(canvas, WMRectangles.ResizeRect(GetClientRect(), -1), 
					1, TRUE, 0808080FFH, WMGraphics.ModeCopy)
			END;
			
			text.AcquireRead;
			la := FindLineByY(firstLineI, Utilities.Max(cliprect.t, bordersI.t)); 
			lb := FindLineByY(firstLineI, Utilities.Min(cliprect.b, bounds.GetHeight() - bordersI.b));
			
			(* allow clean clipping in at inner border *)
			WMRectangles.ClipRect(cliprect, borderClip);
			canvas.SetClipRect(cliprect); 
			
			(* prepare selections *)
			FOR i := 0 TO nofHighlights - 1 DO 
				highlights[i].a := highlights[i].from.GetPosition();
				highlights[i].b := highlights[i].to.GetPosition();
				IF highlights[i].a > highlights[i].b THEN t := highlights[i].a; highlights[i].a := highlights[i].b; highlights[i].b := t END
			END;
			
			top := bordersI.t; FOR i := firstLineI TO la - 1 DO top := top + (layout.lines[i].height) END;
			IF la >= 0 THEN 
				(* draw the lines that intersect the clipping rectangle *)
				FOR i := la TO lb DO 
					RenderLine(canvas, layout.lines[i], i, top, -1); 
					top := top + (layout.lines[i].height) 
				END 
			END;
			RenderAboveTextMarkers(canvas);
			text.ReleaseRead;
			canvas.RestoreState(cstate);
			Draw^(canvas);
		END Draw;
		
		PROCEDURE StoreLineEnter;
		VAR pos, cl : LONGINT;
		BEGIN
			pos := cursor.GetPosition();
			cl := layout.FindLineNrByPos(pos);
			lineEnter := pos - layout.GetLineStartPos(cl)
		END StoreLineEnter;
		
	(* navigation *)
		PROCEDURE WheelMove*(dz: LONGINT); (** PROTECTED *)
		BEGIN
			firstLine.Set(firstLine.Get() + dz) 
		END WheelMove;
		
		(* abort a possible start of a command. Clear the command start indicator, if it was set *)
		PROCEDURE AbortStart;
		BEGIN
			IF commandMarker # NIL THEN
				RemoveHighlight(commandMarker);
				commandMarker := NIL
			END;
			canStart := FALSE
		END AbortStart;
		
		PROCEDURE PointerDown*(x, y : LONGINT; keys : SET);
		VAR pos, i, j, a, b : LONGINT;
		BEGIN
			IF keys * {0, 1, 2} = {1} THEN 
				canStart := TRUE;
				IF commandMarker = NIL THEN
					commandMarker := CreateHighlight();
					commandMarker.SetKind(HLUnder);
					commandMarker.SetColor(0FF0000FFH);
					text.AcquireRead;
					ViewToTextPos(x, y, pos);
					FindCommand(pos, a, b);
					commandMarker.SetFromTo(a, b);
					text.ReleaseRead
				END;
			 END;
			IF 2 IN keys THEN AbortStart END;
			IF 0 IN keys THEN
				AbortStart;
				text.AcquireRead;
				dragPossible := FALSE; selectWords := FALSE;
				ViewToTextPos(x, y, pos);
				IF pos >= 0 THEN
					selection.Sort;
					IF (pos >= selection.a) & (pos < selection.b) THEN
						dragPossible := TRUE; downX := x; downY := y
					ELSE
						(* clicking the same position twice --> Word Selection Mode *)
						IF pos = cursor.GetPosition() THEN
							selectWords := TRUE; wordSelOrdered  := TRUE;
							selection.SetFromTo(AosTextUtilities.FindPosWordLeft(utilreader, pos - 1), 
									AosTextUtilities.FindPosWordRight(utilreader, pos + 1))
						ELSE
							selection.SetFromTo(pos, pos) (* reset selection *)
						END;
						selecting := TRUE
					END
				END;
				cursor.SetPosition(pos);
				text.ReleaseRead
			END;
		END PointerDown;
	
		PROCEDURE PointerMove*(x, y : LONGINT; keys : SET);
		VAR pos, from, a, b : LONGINT;
		BEGIN
			IF ~canStart & dragPossible THEN
				IF (ABS(x - downX) > DragDist) OR (ABS(y - downY) > DragDist) THEN dragPossible := FALSE; AutoStartDrag END
			ELSE
				IF selecting OR canStart THEN 
					text.AcquireRead;
					ViewToTextPos(x, y, pos);
					IF selecting THEN
						IF selectWords THEN
							IF pos < selection.from.GetPosition() THEN pos := AosTextUtilities.FindPosWordLeft(utilreader, pos - 1);
							ELSE pos := AosTextUtilities.FindPosWordRight(utilreader, pos + 1)
							END;				
						(*	(* if the mouse goes over the selected word, the selection from has to be moved to
							the other end of the word, but only once per side change *)
							IF wordSelOrdered # (selection.to.GetPosition() <= selection.from.GetPosition()) THEN
								wordSelOrdered := (selection.to.GetPosition() <= selection.from.GetPosition());
								IF (selection.to.GetPosition() <= selection.from.GetPosition()) THEN
									from := AosTextUtilities.FindPosWordRight(utilreader, selection.from.GetPosition());
								ELSE
									from := AosTextUtilities.FindPosWordLeft(utilreader, selection.from.GetPosition() + 1)
								END;
								selection.SetFromTo(from, pos)
							ELSE *)
								selection.SetTo(pos)
					(*		END; *)
				
			
						ELSE
							selection.SetTo(pos);
						END;
						
						AosTexts.SetLastSelection(text, selection.from, selection.to);
						cursor.SetPosition(pos);
						StoreLineEnter;
					ELSIF canStart THEN
						IF commandMarker # NIL THEN
							FindCommand(pos, a, b);
							commandMarker.SetFromTo(a, b)
						END
					END;
					text.ReleaseRead 
				END;
			END
		END PointerMove;
		
		PROCEDURE PointerUp*(x, y : LONGINT; keys : SET);
		BEGIN
			IF canStart & (commandMarker # NIL) THEN
				commandMarker.Sort;
				StartCommand((commandMarker.a + commandMarker.b) DIV 2);
				AbortStart
			END;
			selecting := FALSE; 
			IF dragPossible THEN selection.SetFromTo(0, 0); AosTexts.ClearLastSelection (* reset selection *) END;
			dragPossible := FALSE
		END PointerUp;
	
		(* Drag away operations *)		
		PROCEDURE AutoStartDrag*;
		VAR img : WMGraphics.Image;
			c : WMGraphics.BufferCanvas;
			w, h, i, la, lb, top : LONGINT;
			l : LineInfo;
		BEGIN
			text.AcquireRead;
			selection.Sort;
			NEW(dragSelA, text);NEW(dragSelB, text);
			dragSelA.SetPosition(selection.a); dragSelB.SetPosition(selection.b);

			la := Limit(layout.FindLineNrByPos(selection.a), 0, layout.GetNofLines() - 1);
			lb := Limit(layout.FindLineNrByPos(selection.b), 0, layout.GetNofLines() - 1);
			(* estimate the size of the selection *)
			h := 0; w := 0;
			FOR i := la TO lb DO
				h := h + (layout.lines[i].height);
				w := Utilities.Max(w, layout.lines[i].width);
			END;
			h := Limit(h, 20, 200);
			w := Limit(w, 20, 400);
			
			(* render to bitmap *)
			NEW(img);	Raster.Create(img, w, h, Raster.BGRA8888);
			NEW(c, img);
			top := 0;
			(* hack the startpos of the first line *)
			l := layout.lines[la]; l.pos := selection.a;
			IF la = lb THEN RenderLine(c, l, la, top, selection.b - selection.a)
			ELSE
				RenderLine(c, l, la, top, -1);
				top := top + l.height
			END;
						
			FOR i := la + 1 TO lb DO
				IF i = lb THEN 
					RenderLine(c, layout.lines[i], i, top, selection.b - layout.lines[i].pos) 
				ELSE
					RenderLine(c, layout.lines[i], i, top, -1); 
					top := top + (l.height)
				END
			END;

			text.ReleaseRead;

			IF StartDrag(NIL, img, DragWasAccepted, NIL) THEN 
			ELSE AosOut.String("WMTextView : Drag could not be started")
			END;
		END AutoStartDrag;
		
		PROCEDURE DragWasAccepted(sender, data : ANY);
		VAR di : WMWindowManager.DragInfo;
			dt : WMDropTarget.DropTarget;
			itf : WMDropTarget.DropInterface;
			i, res : LONGINT;
			targetText, temp : AosTexts.Text;
			pos, a, b : LONGINT;
		BEGIN
			IF (dragSelA = NIL) OR (dragSelB = NIL)  THEN RETURN END;
			
			IF (data # NIL) & (data IS WMWindowManager.DragInfo) THEN
				di := data(WMWindowManager.DragInfo);
				IF (di.data # NIL) & (di.data IS WMDropTarget.DropTarget) THEN		
					dt := di.data(WMDropTarget.DropTarget)
				ELSE RETURN
				END
			ELSE RETURN
			END;

			itf := dt.GetInterface(WMDropTarget.TypeText);
			IF itf # NIL THEN
				targetText := itf(WMDropTarget.DropText).text;
				IF targetText # NIL THEN
					targetText.AcquireWrite;
					IF ~dragCopy THEN
						AosOut.String("not copy"); AosOut.Ln; 
						text.AcquireWrite;
						a := dragSelA.GetPosition(); b := dragSelB.GetPosition();
						pos := itf(WMDropTarget.DropText).pos.GetPosition();
						IF (targetText # text) OR (pos < a) OR (pos > b) THEN
							NEW(temp); temp.AcquireWrite; text.CopyToText(a, b- a, temp, 0); temp.ReleaseWrite;
							text.Delete(a, b- a);
							pos := itf(WMDropTarget.DropText).pos.GetPosition();
							temp.AcquireRead;	temp.CopyToText(0, temp.GetLength(), targetText, pos); temp.ReleaseRead;
						END;
						text.ReleaseWrite
					ELSE
						AosOut.String("copy"); AosOut.Ln; 
						text.AcquireRead;
						pos := itf(WMDropTarget.DropText).pos.GetPosition();
						a := dragSelA.GetPosition(); b := dragSelB.GetPosition();
						text.CopyToText(a, b- a, targetText, pos);										
						text.ReleaseRead
					END;
					targetText.ReleaseWrite
				END;
				RETURN						
			END;
		END DragWasAccepted;			

		(* Drag onto operations *)
		PROCEDURE DragOver(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo);
		VAR pos : LONGINT;
		BEGIN
			text.AcquireRead;
			ViewToTextPos(x, y, pos);
			cursor.SetVisible(TRUE);
			cursor.SetPosition(pos);
			StoreLineEnter;
			text.ReleaseRead 
		END DragOver;
		
		PROCEDURE DragDropped*(x, y : LONGINT; dragInfo : WMWindowManager.DragInfo);
		VAR dropTarget : TextDropTarget;
			pos : LONGINT;
			p : AosTexts.TextPosition;
		BEGIN
			text.AcquireRead;
			ViewToTextPos(x, y, pos)	;
			NEW(p, text); p.SetPosition(pos);
			NEW(dropTarget, text, p);
			text.ReleaseRead;
			IF ~hasFocus & ~alwaysShowCursorI THEN cursor.SetVisible(FALSE) END;
			dragInfo.data := dropTarget;
			ConfirmDrag(TRUE, dragInfo)
		END DragDropped;
		
		PROCEDURE CopySelection*;
		BEGIN
			IF isPassword.Get() THEN RETURN END;
			text.AcquireRead;
			AosTexts.clipboard.AcquireWrite;
			selection.Sort;
			IF selection.b - selection.a > 0 THEN 
				(* clear the clipboard *)
				IF AosTexts.clipboard.GetLength() > 0 THEN AosTexts.clipboard.Delete(0, AosTexts.clipboard.GetLength()) END;
	
				text.CopyToText(selection.a, selection.b - selection.a, AosTexts.clipboard, 0);
			END;
			AosTexts.clipboard.ReleaseWrite;
			text.ReleaseRead
		END CopySelection;
		
		PROCEDURE SelectAll*;
		BEGIN
			text.AcquireRead;
			selection.SetFromTo(0, text.GetLength());
			AosTexts.SetLastSelection(text, selection.from, selection.to);
			text.ReleaseRead
		END SelectAll;
		
		(* Prepare to start the selection by keyboard. Clear the selection, if it is not contigous *)
		PROCEDURE KeyStartSelection(pos : LONGINT);
		BEGIN
			IF selection.to.GetPosition() # pos THEN selection.SetFromTo(pos, pos); AosTexts.ClearLastSelection END;
		END KeyStartSelection;
		
		(* update the keyboard selection with the new position, redraw from the last StartSelection *)
		PROCEDURE KeyUpdateSelection(pos : LONGINT);
		BEGIN
			selection.SetTo(pos);
			AosTexts.SetLastSelection(text, selection.from, selection.to)
		END KeyUpdateSelection;
		
		PROCEDURE CursorUp*(select : BOOLEAN);
		VAR pos, cl : LONGINT;
		BEGIN
			text.AcquireRead;
			pos := cursor.GetPosition();
			IF select THEN KeyStartSelection(pos)
			ELSE selection.SetFromTo(cursor.GetPosition(), cursor.GetPosition()); AosTexts.ClearLastSelection
			END;
			cl := layout.FindLineNrByPos(pos);
			IF cl > 0 THEN 
				DEC(cl);
				cursor.SetPosition(layout.GetLineStartPos(cl) + Utilities.Min(layout.GetLineLength(cl) - 1, lineEnter));
				IF cl < firstLineI THEN firstLine.Set(cl) END
			END;	
			IF select THEN KeyUpdateSelection(cursor.GetPosition()) END;
			text.ReleaseRead
		END CursorUp;
		
		PROCEDURE CursorDown*(select : BOOLEAN);
		VAR pos, cl : LONGINT;
		BEGIN
			text.AcquireRead;
			pos := cursor.GetPosition();
			IF select THEN KeyStartSelection(pos) 
			ELSE selection.SetFromTo(cursor.GetPosition(), cursor.GetPosition()); AosTexts.ClearLastSelection
			END;
			cl := layout.FindLineNrByPos(pos);
			IF cl < layout.GetNofLines() - 1 THEN 
				INC(cl);
				cursor.SetPosition(layout.GetLineStartPos(cl) + Utilities.Min(layout.GetLineLength(cl) - 1, lineEnter));
				IF cl > FindLineByY(firstLineI, bounds.GetHeight() - bordersI.b) THEN firstLine.Set(firstLineI + 1 ) END
			END;	
			IF select THEN KeyUpdateSelection(cursor.GetPosition()) END;
			text.ReleaseRead
		END CursorDown;
		
		(* Move the cursor one character/word to the left *)
		PROCEDURE CursorLeft*(word, select : BOOLEAN);
		BEGIN
			text.AcquireRead;
			IF select THEN KeyStartSelection(cursor.GetPosition()) 
			ELSE selection.SetFromTo(cursor.GetPosition(), cursor.GetPosition()); AosTexts.ClearLastSelection
			END;
			IF ~ word THEN cursor.SetPosition(cursor.GetPosition() - 1) 
			ELSE cursor.SetPosition(AosTextUtilities.FindPosWordLeft(utilreader, cursor.GetPosition() - 1)) 
			END;
			IF select THEN KeyUpdateSelection(cursor.GetPosition()) END;
			StoreLineEnter;
			text.ReleaseRead
		END CursorLeft;
		
		(* Move the cursor one character/word to the right *)
		PROCEDURE CursorRight*(word, select : BOOLEAN);
		BEGIN
			text.AcquireRead;
			IF select THEN KeyStartSelection(cursor.GetPosition()) 
			ELSE selection.SetFromTo(cursor.GetPosition(), cursor.GetPosition());AosTexts.ClearLastSelection
			END;
			IF ~ word THEN cursor.SetPosition(cursor.GetPosition() + 1) 
			ELSE cursor.SetPosition(AosTextUtilities.FindPosWordRight(utilreader, cursor.GetPosition() + 1))
			END;
			IF select THEN KeyUpdateSelection(cursor.GetPosition()) END;
			StoreLineEnter;
			text.ReleaseRead
		END CursorRight;
		
		PROCEDURE PageDown*(select : BOOLEAN);
		VAR dy : LONGINT; i, pos : LONGINT;
			cx, cy : LONGINT;
		BEGIN
			text.AcquireRead;
			IF select THEN KeyStartSelection(cursor.GetPosition()) 
			ELSE selection.SetFromTo(cursor.GetPosition(), cursor.GetPosition());AosTexts.ClearLastSelection
			END;
			IF firstLineI = layout.GetNofLines() - 1  THEN  cursor.SetPosition(text.GetLength())
			ELSE
				(* save cursor screen pos for repositioning *)
				IF ~FindScreenPos(cursor.GetPosition(), cx, cy) THEN cx := 0; cy := 0 END;
				i := firstLineI; dy := 0;
				WHILE (i < layout.GetNofLines() - 1) & (dy < bounds.GetHeight() - bordersI.t - bordersI.b) DO 
					INC(i); dy := dy + (layout.lines[i].height) 
				END;
				firstLine.Set(i);
				(* set cursor to nearest pos on new page *)
				ViewToTextPos(cx, cy, pos); IF pos >= 0 THEN cursor.SetPosition(pos) END;
			END;
			IF select THEN KeyUpdateSelection(cursor.GetPosition()) END;
			text.ReleaseRead
		END PageDown;

		PROCEDURE PageUp*(select : BOOLEAN);
		VAR dy : LONGINT; i, pos : LONGINT;
			cx, cy : LONGINT;
		BEGIN
			text.AcquireRead;
			IF select THEN KeyStartSelection(cursor.GetPosition()) 
			ELSE selection.SetFromTo(cursor.GetPosition(), cursor.GetPosition());AosTexts.ClearLastSelection
			END;
			IF firstLineI = 0 THEN cursor.SetPosition(0)
			ELSE
				(* save cursor screen pos for repositioning *)
				IF ~FindScreenPos(cursor.GetPosition(), cx, cy) THEN cx := 0; cy := 0 END;
				(* go up one page but at least one page *)
				i := firstLineI; dy := 0;
				WHILE (i > 0) & (dy < bounds.GetHeight() - bordersI.t - bordersI.b) DO 
					DEC(i); dy := dy + (layout.lines[i].height) 
				END;
				IF (i > 0) & (i = firstLineI) THEN DEC(i) END;
				firstLine.Set(i);
				(* set cursor to nearest pos on new page *)
				ViewToTextPos(cx, cy, pos); IF pos >= 0 THEN cursor.SetPosition(pos) END
			END;	
			IF select THEN KeyUpdateSelection(cursor.GetPosition()) END;
			text.ReleaseRead
		END PageUp;
		
		PROCEDURE Home*(ctrl, select : BOOLEAN);
		VAR cl : LONGINT;
		BEGIN
			text.AcquireRead;
			IF select THEN KeyStartSelection(cursor.GetPosition()) 
			ELSE selection.SetFromTo(cursor.GetPosition(), cursor.GetPosition()); AosTexts.ClearLastSelection
			END;
			IF ctrl THEN cursor.SetPosition(0); firstLine.Set(0)
			ELSE cl := layout.FindLineNrByPos(cursor.GetPosition());
				cursor.SetPosition(layout.GetLineStartPos(cl))
			END;
			StoreLineEnter;
			IF select THEN KeyUpdateSelection(cursor.GetPosition()) END;
			text.ReleaseRead
		END Home;
		
		PROCEDURE End*(ctrl, select : BOOLEAN);
		VAR cl : LONGINT;
		BEGIN
			text.AcquireRead;
			IF select THEN KeyStartSelection(cursor.GetPosition()) 
			ELSE selection.SetFromTo(cursor.GetPosition(), cursor.GetPosition()); AosTexts.ClearLastSelection
			END;
			IF ctrl THEN cursor.SetPosition(text.GetLength()); firstLine.Set(layout.FindLineNrByPos(text.GetLength()))
			ELSE cl := layout.FindLineNrByPos(cursor.GetPosition());
				cursor.SetPosition(layout.GetLineStartPos(cl) + layout.GetLineLength(cl) - 1)
			END;
			StoreLineEnter;
			IF select THEN KeyUpdateSelection(cursor.GetPosition()) END;
			text.ReleaseRead
		END End;
		
		PROCEDURE KeyEvent*(ucs :LONGINT; flags : SET; VAR keysym : LONGINT);
		BEGIN
			modifierFlags := flags;
			dragCopy := modifierFlags * AosInputs.Ctrl # {};
			IF keysym = 01H THEN (* Ctrl-A *)
				SelectAll
			ELSIF keysym = 03H THEN (* Ctrl-C *)
				CopySelection
 			ELSIF (keysym = 0FF63H) & (flags * AosInputs.Ctrl # {}) THEN  (*Ctrl Insert *) 
				CopySelection
			ELSIF keysym = 12H THEN (* Ctrl-R *)
				layout.FullLayout; Invalidate;CheckNumberOfLines;
				AosOut.String("Refreshed"); AosOut.Ln;
			ELSIF keysym = 0FF51H THEN (* Cursor Left *)
				CursorLeft(flags * AosInputs.Ctrl # {}, flags * AosInputs.Shift # {})
			ELSIF keysym = 0FF53H THEN (* Cursor Right *)
				CursorRight(flags * AosInputs.Ctrl # {}, flags * AosInputs.Shift # {})
			ELSIF keysym = 0FF54H THEN (* Cursor Down *)
				CursorDown(flags * AosInputs.Shift # {})
			ELSIF keysym = 0FF52H THEN (* Cursor Up *)
				CursorUp(flags * AosInputs.Shift # {})
			ELSIF keysym = 0FF56H THEN (* Page Down *)
				PageDown(flags * AosInputs.Shift # {})
			ELSIF keysym = 0FF55H THEN (* Page Up *)
				PageUp(flags * AosInputs.Shift # {})
			ELSIF keysym = 0FF50H THEN (* Cursor Home *)
				Home(flags * AosInputs.Ctrl # {}, flags * AosInputs.Shift # {})
			ELSIF keysym = 0FF57H THEN (* Cursor End *)
				End(flags * AosInputs.Ctrl # {}, flags * AosInputs.Shift # {})
			END
		END KeyEvent;
		
		(* called by users that override the KeyEvents to allow copy drag drop *)
		PROCEDURE SetFlags*(flags : SET);
		BEGIN
			modifierFlags := flags;
			dragCopy := modifierFlags * AosInputs.Ctrl # {};			
		END SetFlags;
		
		PROCEDURE FindCommandRange(pos: LONGINT; VAR start, end : LONGINT);
		VAR ch : LONGINT;
		BEGIN
		(*	start := AosTextUtilities.FindPosWordLeft(utilreader, pos); *)
			utilreader.SetDirection(-1); utilreader.SetPosition(pos);
			REPEAT	utilreader.ReadCh(ch) UNTIL AosTextUtilities.IsWhiteSpace(ch) OR utilreader.eot;
			start := utilreader.GetPosition() + 2;
			IF utilreader.eot THEN DEC(start, 2) END;
			(* search ~ *)
			utilreader.SetDirection(1); utilreader.SetPosition(start);
			REPEAT	utilreader.ReadCh(ch) UNTIL (ch = ORD("~")) OR (utilreader.eot);
			end:= utilreader.GetPosition() - 1;
			IF utilreader.eot THEN INC(end) END
		END FindCommandRange;
		
		PROCEDURE FindCommand(pos: LONGINT; VAR start, end : LONGINT);
		VAR ch : LONGINT;
		BEGIN
			utilreader.SetDirection(-1); utilreader.SetPosition(pos);
			REPEAT	utilreader.ReadCh(ch) UNTIL AosTextUtilities.IsWhiteSpace(ch) OR utilreader.eot;
			start := utilreader.GetPosition() + 2;
			IF utilreader.eot THEN DEC(start, 2) END;
			
			utilreader.SetDirection(1); utilreader.SetPosition(pos);
			REPEAT	utilreader.ReadCh(ch) UNTIL AosTextUtilities.IsWhiteSpace(ch) OR utilreader.eot;
			end := utilreader.GetPosition() - 1
		END FindCommand;
				
		
		(* start the AosCommand in the text, starting on pos (or wordboundary before),
		caller should hold lock on text  to make the pos stable *)
		PROCEDURE StartCommand*(pos : LONGINT);
		VAR start, end, bufSize : LONGINT;
			s : Utilities.String;
			res : LONGINT;
			msg : ARRAY 128 OF CHAR;
		BEGIN
			text.AcquireRead;
			FindCommandRange(pos, start, end);
			bufSize := Utilities.Max(Utilities.Min((end - start) * 5 + 1 (* for UTF *), MaxCallParameterBuf), 1); 
			NEW(s, bufSize);
			AosTextUtilities.SubTextToStr(text, start, end - start, s^);
			text.ReleaseRead;
			(* call the command *)
			AosCommands.Call(s^, {}, res, msg);
			IF res # 0 THEN AosOut.String(msg); AosOut.Ln END;
		END StartCommand;

	END TextView;
		
VAR manager : WMWindowManager.WindowManager;
	PTVIsMultiLine, PTVIsPassword, PTVShowBorder, PTValwaysShowCursor : WMProperties.BooleanProperty;
	PTVfirstLine, PTVleftShift, PTVPasswordChar : WMProperties.Int32Property;
	PTVdefaultTextColor, PTVdefaultTextBgColor : WMProperties.ColorProperty;
	PTVborders : WMProperties.RectangleProperty;
	
PROCEDURE Limit(x, min, max : LONGINT) : LONGINT;
BEGIN
	IF x < min THEN x := min END;
	IF x > max THEN x := max END;
	RETURN x
END Limit;

		
PROCEDURE TextViewDefaults;
BEGIN
	NEW(PTVIsMultiLine, NIL, NewString("multiLine"), NewString("defines if more than one line is visible"));
	PTVIsMultiLine.Set(TRUE); 
	NEW(PTVIsPassword, NIL, NewString("password"), 
		NewString("defines if the view is a password text. Characters are replaced by passwordChar"));
	NEW(PTVPasswordChar, NIL, NewString("passwordChar"), 
		NewString("character that is the placeholder for a character in a password")); 
	PTVPasswordChar.Set(43); 
	NEW(PTValwaysShowCursor, NIL, NewString("alwaysShowCursor"), 
		NewString("set to true, if the cursor should not be hidden when focus is lost"));
	PTValwaysShowCursor.Set(FALSE); 
	NEW(PTVfirstLine, NIL, NewString("firstLine"), 
		NewString("the first visible line of text in the view"));
	PTVfirstLine.Set(0);
	NEW(PTVleftShift, NIL, NewString("leftShift"), 
		NewString("how many pixels the text in the view is shifted to the left"));
	 PTVleftShift.Set(0);
	NEW(PTVdefaultTextColor, NIL, NewString("defaultTextColor"), 
		NewString("the color of a text that does not explicitly specify a color"));
	PTVdefaultTextColor.Set(0FFH);
	NEW(PTVdefaultTextBgColor, NIL, NewString("defaultTextBgColor"), 
		NewString("The color of a text background if not specified otherwise in the text"));
	PTVdefaultTextBgColor.Set(0FFFFFFFFH);
	NEW(PTVborders, NIL, NewString("borders"), 
		NewString("spaces from bounds of the component to the text"));
	PTVborders.Set(WMRectangles.MakeRect(5, 5, 5, 5));

END TextViewDefaults;

PROCEDURE NewString*(x : ARRAY OF CHAR) : String;
BEGIN
	RETURN Utilities.NewString(x)
END NewString;

PROCEDURE TextViewFactory*(par: PTR): PTR;
VAR e : TextView;
BEGIN
	NEW(e); RETURN e
END TextViewFactory;

PROCEDURE Register;
BEGIN
	WMComponents.registry.RegisterElement("TextView", TextViewFactory)
END Register;

PROCEDURE Finalize;
BEGIN
	WMComponents.registry.UnregisterElement("TextView")
END Finalize;

PROCEDURE Load*(par : PTR): PTR;
BEGIN
	RETURN NIL
END Load;

BEGIN
	TextViewDefaults;
	manager := WMWindowManager.GetDefaultManager();
	Register;
	AosModules.InstallTermHandler(Finalize)
END WMTextView.

Benchmark : PositionCursor took 1.434
Benchmark : SetTopPos took 74.177
Total Benchmark : 75.611
