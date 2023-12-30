MODULE WMTextView;	(** AUTHOR "TF"; PURPOSE "Generic unicode text viewer"; *)
(**
 * History:
 *
 *	21.03.2006	Added TextView.Finalize (staubesv)
 *	15.08.2006	Don't re-use piemenu instance, since its form is finalized when the menu window is closed, cleanup (staubesv)
 *	26.09.2006	Bugfix: TextView.TextChange: Don't update lastTimeStamp if info.timestamp is older than lastTimeStamp (staubesv)
 *	27.09.2006	TextView.StartCommand: Use AosCommands.Activate directly (staubesv)
 *)
 
IMPORT
	AosModules, AosInputs, AosOut, AosTexts, AosTextUtilities, 
	WMGraphics, WMGraphicUtilities, WMMessages, WMComponents, 
	WMStandardComponents, Utilities, WMDropTarget, Raster,
	WMRectangles, WMWindowManager, WMProperties,
	AosCommands, AosConfig, AosIO, AosFS, WMPopups, FP1616,
	WMPieMenu, WMEvents;

CONST
	TraceRenderOptimize = 0;
	TraceLayout = 1;
	TraceBaseLine = 2;
	TraceInvalidate = 3;
	TraceCopy = 4;
	TraceCommands = 5;
	Trace = {};

	CallURLPointer = 0;	(* mousebutton which will invoke the URL *)
	Wrap* = 0; WrapWord* = 1;
	AlignLeft = 0; AlignCenter = 1; AlignRight = 2;
	
	DragDist = 5;
	MaxCallParameterBuf = 1 * 1024 * 1024;

	(* If TRUE, a mouse middle click will open a pie menu *)
	UsePieMenu = TRUE;
	
TYPE
	Char32 = AosTexts.Char32;
	String = Utilities.String;
	
	ClickInfo = OBJECT
	VAR cmd*, cmdPar* : Utilities.String;
	END ClickInfo;

	TabStops* = OBJECT
	VAR tabDist : LONGINT;
		(* return the next TabStop from the x position *)
		PROCEDURE GetNextTabStop*(x : LONGINT) : LONGINT;
		BEGIN
			RETURN ((x DIV tabDist) + 1) * tabDist
		END GetNextTabStop;
	END TabStops;
	
	TabPositions* = POINTER TO ARRAY OF LONGINT;
	
	CustomTabStops* = OBJECT (TabStops)
	VAR
		positions : TabPositions;
		
		PROCEDURE GetNextTabStop*(x : LONGINT) : LONGINT;
		VAR
			idx : LONGINT;
		BEGIN
			idx := 0;
			ASSERT(positions # NIL);
			IF x >= positions[LEN(positions) - 1] THEN RETURN GetNextTabStop^(x) END; (* return default tab stop *)
			WHILE x >= positions[idx] DO INC(idx) END;
			RETURN positions[idx]
		END GetNextTabStop;
		
		PROCEDURE &New (tp : TabPositions);
		VAR
			idx : LONGINT;
		BEGIN
			idx := 0; tabDist := 150;
			WHILE idx < LEN(tp)-1 DO ASSERT(tp[idx] <= tp[idx+1]); INC(idx) END;
			positions := tp
		END New;
	END CustomTabStops;
		

	LineInfo = RECORD
		leftIndent, rightIndent, firstIndent, spaceBefore, spaceAfter : LONGINT;
		firstInParagraph, lastInParagraph : BOOLEAN;
		height, width, ascent : LONGINT;
		pos : LONGINT; (* the position in the text, where this line starts *)
		align : LONGINT;
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
		VAR a, b, m : LONGINT;
		BEGIN
			a := 0; b := nofLines - 1;
			WHILE (a < b) DO m := (a + b) DIV 2; 
				IF lines[m].pos <= pos THEN a := m + 1 
				ELSE b := m
				END 
			END;
			(* last line hack *)
			IF lines[a].pos <= pos THEN INC(a) END; 
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
						INC(l);
						IF l >= LEN(lines) THEN GrowLines END
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
	
		PROCEDURE Show;
		VAR i : LONGINT;
		BEGIN
			FOR i := 0 TO LEN(lines)-1 DO
				AosOut.Int(i, 3); AosOut.String(": ");
				AosOut.String("pos: "); AosOut.Int(lines[i].pos, 0);
				AosOut.String(", w: "); AosOut.Int(lines[i].width, 0);
				AosOut.String(", h: "); AosOut.Int(lines[i].height, 0);
				AosOut.String(", ascent: "); AosOut.Int(lines[i].ascent, 0);		
				AosOut.String(" (");
				AosOut.String("li: "); AosOut.Int(lines[i].leftIndent, 0); 
				AosOut.String(", ri: "); AosOut.Int(lines[i].rightIndent, 0);
				AosOut.String(", fi: "); AosOut.Int(lines[i].firstIndent, 0);
				AosOut.String(", sb: "); AosOut.Int(lines[i].spaceBefore, 0);
				AosOut.String(", sa: "); AosOut.Int(lines[i].spaceAfter, 0);
				AosOut.String(")");
				AosOut.Ln;
			END;	
		END Show;
		
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
		color : WMGraphics.Color;
		
		hotX, hotY : LONGINT;
		currentArea : WMRectangles.Rectangle;
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
			IF img # NIL THEN hotX := img.width DIV 2; hotY := img.height DIV 2 END;
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
	LinkWrapper* = POINTER TO RECORD
		link* : AosTexts.Link;
	END;

TYPE
	TextView* = OBJECT(WMComponents.VisualComponent)
	VAR
		piemenu : WMPieMenu.Menu;
		
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
		
		canStart, openFile : BOOLEAN; (* set for command selection mode *)
		commandMarker : Highlight;
		
		downX, downY : LONGINT;
		selectWords : BOOLEAN;
		wordSelOrdered : BOOLEAN;
		lineEnter : LONGINT;
		modifierFlags : SET;
		oldFlags : SET;	(* old pointer flags *)
		
		lastTimeStamp : LONGINT;
		showLabels* : WMProperties.BooleanProperty;
		
		oldObject, focusObject : ANY;
		oldPos, focusPos : LONGINT;
		objHasFocus : BOOLEAN;
		
		onCursorChanged* : PROCEDURE {DELEGATE};
		onLinkClicked* : WMEvents.EventSource;
		
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
			NEW(showLabels, PTVShowLabels, NIL, NIL); properties.Add(showLabels);
			takesFocus.Set(TRUE); needsTab.Set(TRUE);
			SetPointerInfo(manager.pointerText);
			NEW(onLinkClicked, SELF, PTVonLinkClick, PTVonLinkClickInfo, SELF.StringToCompCommand); events.Add(onLinkClicked);
			onLinkClicked.Add(LinkClicked);
			RecacheProperties
		END Init;
		
		PROCEDURE Finalize;
		BEGIN
			Finalize^;
			IF text # NIL THEN text.onTextChanged.Remove(TextChanged); END;
		END Finalize;
		
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
			IF hScrollbar # NIL THEN hScrollbar.onPositionChanged.Add(ScrollbarsChanged) END;
			IF vScrollbar # NIL THEN vScrollbar.onPositionChanged.Add(ScrollbarsChanged) END;
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
		VAR vScroll : LONGINT;
		BEGIN
			IF (vScrollbar # NIL) & (vScrollbar.visible.Get()) THEN vScroll := vScrollbar.bounds.GetWidth() ELSE vScroll := 0 END;
			borderClip := WMRectangles.MakeRect(bordersI.l, bordersI.t, bounds.GetWidth() - bordersI.r, bounds.GetHeight() - bordersI.b);
			layout.paperWidth := bounds.GetWidth() - (bordersI.l + bordersI.r) - vScroll;
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
		
		PROCEDURE SetTabStops*(ts : TabStops);
		BEGIN
			Acquire;
			defaultTabStops := ts;
			Release;
			layout.FullLayout;
			CheckNumberOfLines
		END SetTabStops;
		

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
			HighlightChanged(highlight, NIL);
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
		VAR i, xp, yp, l, ascent : LONGINT; newRect : WMRectangles.Rectangle; 
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
					ascent := layout.lines[l].ascent;
(*					IF ascent = 0 THEN ascent := layout.lines[l].height END;
					IF ascent = 0 THEN ascent := 10 END; *)

					newRect := x.GetArea(xp, yp, ascent);
					InvalidateRect(newRect)
				END
			END;
			Release
		END RemovePositionMarker;
		
		PROCEDURE PositionMarkerChanged(sender, data : PTR);
		VAR newRect, combinedRect : WMRectangles.Rectangle; x, y, l, ascent : LONGINT;
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
							ascent := layout.lines[l].ascent;
(*							IF ascent = 0 THEN ascent := layout.lines[l].height END;
							IF ascent = 0 THEN ascent := 10 END;*)
							newRect := data(PositionMarker).GetArea(x, y, ascent)
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
					Invalidate; 
					AosOut.String("Editor: XXX"); AosOut.Ln;
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
		VAR cp, l, i : LONGINT; ty : LONGINT;
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
				WHILE i < l DO
					ty := ty + layout.lines[i].height;
					CheckParagraphBegin(i, ty);
					CheckParagraphEnd(i, ty);							
					INC(i);
				END;
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
		
		PROCEDURE CheckParagraphBegin(lineNr : LONGINT; VAR height: LONGINT);
		BEGIN
			IF layout.lines[lineNr].firstInParagraph THEN height := height + layout.lines[lineNr].spaceBefore END
		END CheckParagraphBegin;

		PROCEDURE CheckParagraphEnd(lineNr : LONGINT; VAR height: LONGINT);
		BEGIN
			IF layout.lines[lineNr].lastInParagraph THEN height := height + layout.lines[lineNr].spaceAfter; END;
		END CheckParagraphEnd;		
		
		PROCEDURE TextChanged(sender, data : PTR);
		VAR f, l, t, b, i, p, pa, pb, h: LONGINT; linesChanged : BOOLEAN;
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
						t := bordersI.t; 
						FOR i := firstLineI TO f - 1 DO
							t := t + (layout.lines[i].height);
							CheckParagraphBegin(i, t);
							CheckParagraphEnd(i, t);								
						END;

						h := bounds.GetHeight();
						IF linesChanged THEN b := h ELSE
							b := t; i := f; 
							WHILE (i <= l) & (b < h) DO
								b := b + (layout.lines[i].height);
								CheckParagraphBegin(i, b);
								CheckParagraphEnd(i, b);
								INC(i);
							END
						END;
						
						pa := layout.lines[f].pos;
						IF l + 1 < layout.nofLines THEN pb := layout.lines[l + 1].pos ELSE pb := text.GetLength() END;	
						FOR i := 0 TO nofPositionMarkers - 1 DO
							p := positionMarkers[i].pos.GetPosition();
							IF (p >= pa) & (p < pb) THEN 
								(* very conservative *)
								h := positionMarkers[i].currentArea.b - positionMarkers[i].currentArea.t;
								t := t - h;
								b := b + h
							END
						END;
						CheckCursor; UpdateScrollbars;
						Release;
						InvalidateRect(WMRectangles.MakeRect(0, t, bounds.GetWidth(), b));
					ELSE
						IF TraceRenderOptimize IN Trace THEN AosOut.String("Timestamp not equal ==> Complete re_layout"); AosOut.Ln
						END;
						
						IF (lastTimeStamp -  info.timestamp) > 0 THEN
							(* Don't update lastTimeStamp since we didn't update the layout *)
							Release
						ELSE
							layout.FullLayout;
							lastTimeStamp := text.GetTimestamp();
							CheckCursor;
							Release;
							InvalidateRect(GetClientRect())
						END; 
					END;
					text.ReleaseRead
				ELSE
					text.AcquireRead;
					layout.FullLayout;
					lastTimeStamp := text.GetTimestamp();
					text.ReleaseRead;
					CheckCursor;
					InvalidateRect(GetClientRect())
				END;
				CheckNumberOfLines;
			END;
		END TextChanged;
		
(* BEGIN view dependant layout functions *)
		(** Return the left indent of a line - depending on alignment *)
		(* returns left border, in case of errors *)
		PROCEDURE GetLineLeftIndent(linenr : LONGINT): LONGINT;
		VAR indent : LONGINT;
		BEGIN
			IF (linenr < 0) OR (linenr >= layout.nofLines) THEN RETURN 0 END;
			IF layout.lines[linenr].firstInParagraph THEN indent := layout.lines[linenr].firstIndent ELSE indent := layout.lines[linenr].leftIndent END;
			CASE layout.lines[linenr].align OF
				AlignLeft : RETURN indent;
				|AlignCenter : RETURN ((layout.paperWidth - (layout.lines[linenr].width)) DIV 2 - indent DIV 2);
				|AlignRight : RETURN (layout.paperWidth - layout.lines[linenr].width - layout.lines[linenr].rightIndent);			
			ELSE
				 RETURN 0;
			END;
		END GetLineLeftIndent;
		
		(** Find the line number that currently contains the y value (y relative to 0 in component)*)
		PROCEDURE FindLineByY*(firstLine, y : LONGINT) : LONGINT;
		VAR i : LONGINT; ypos : LONGINT;
		BEGIN
			ypos := bordersI.t; i := firstLine;
			IF y < 0 THEN RETURN 0 END;
			WHILE (i < layout.nofLines) & (ypos <= y) DO
				ypos := ypos + layout.lines[i].height; 
				CheckParagraphBegin(i, ypos);
				CheckParagraphEnd(i, ypos);		
				INC(i);
			END;
			RETURN Utilities.Max(i -1, 0)
		END FindLineByY;

		PROCEDURE ViewToTextPos*(x, y: LONGINT; VAR pos : LONGINT);
		VAR l : LONGINT; dummy : LineInfo; indent : LONGINT;
		BEGIN
			text.AcquireRead;
			pos := -1;
			x := Utilities.Max(0, Utilities.Min(x, bounds.GetWidth()));
			y := Utilities.Max(0, Utilities.Min(y, bounds.GetHeight()));
			
			l := FindLineByY(firstLineI, Utilities.Min(Utilities.Max(y, bordersI.t), bounds.GetHeight() - bordersI.b));
			
			x := x - bordersI.l + leftShiftI;
			IF x < 0 THEN x := 0 END;
			dummy := layout.lines[l];
			IF l >= 0 THEN
				pos := layout.GetLineStartPos(l);
				IF dummy.firstInParagraph THEN indent := dummy.firstIndent
				ELSE indent := dummy.leftIndent END;		

				IF dummy.align = 0 THEN (* Left *)
					LayoutLine(pos, dummy, layout.paperWidth, -1, x-indent)
				ELSIF dummy.align = 1 THEN (* Center *)
					LayoutLine(pos, dummy, layout.paperWidth, -1, x-((layout.paperWidth - dummy.width - indent) DIV 2))
				ELSIF dummy.align = 2 THEN (* Right *)
					LayoutLine(pos, dummy, layout.paperWidth, -1, x-(layout.paperWidth - dummy.width - dummy.rightIndent))
				END;				
				
			END;
			text.ReleaseRead
		END ViewToTextPos;
		
		(* Returns the height for the given width *)
		PROCEDURE GetHeight*(width: LONGINT): LONGINT;
		VAR oldWidth, height : LONGINT;
		BEGIN
			oldWidth := layout.paperWidth;
			layout.paperWidth := width;
			layout.FullLayout;
			height := layout.textHeight;
						
			(* reset old state *)
			layout.paperWidth := oldWidth;
			layout.FullLayout;
			RETURN height
		END GetHeight;
		
		(* Returns the size of the largest word and line in pixels *)
		PROCEDURE GetMinMaxWidth*(VAR word, line : LONGINT);
		VAR dx, pos : LONGINT;
			cws, cls : LONGINT;
			f : WMGraphics.Font;
			ch : Char32;
			tabstring : ARRAY 256 OF CHAR; tabs : CustomTabStops; tp : TabPositions;
			sr : AosIO.StringReader; tabCounter, tabPos : LONGINT; token : ARRAY 16 OF CHAR;
			pStyle : AosTexts.ParagraphStyle;
			cStyle : AosTexts.CharacterStyle;
			
			PROCEDURE GetWidth(ch : Char32; VAR dx : LONGINT);
			VAR gs : WMGraphics.GlyphSpacings; vc : WMComponents.VisualComponent;
			BEGIN
				IF ch = AosTexts.ObjectChar THEN
					IF (utilreader.object # NIL) & (utilreader.object IS WMGraphics.Image) THEN
						dx :=  utilreader.object(WMGraphics.Image).width 
					ELSIF (utilreader.object # NIL) & (utilreader.object IS WMComponents.VisualComponent) THEN
						vc := utilreader.object(WMComponents.VisualComponent);						
						dx := vc.bounds.GetWidth();
					END
				ELSIF ch = AosTexts.TabChar THEN
					IF tabs # NIL THEN dx := tabs.GetNextTabStop(cls) - cls 
					ELSE dx := defaultTabStops.GetNextTabStop(cls) - cls
					END;
				ELSE
					IF isPasswordI THEN ch := passwordChar.Get() END;
					IF f.HasChar(ch) THEN
						f.GetGlyphSpacings(ch, gs);
					ELSE
						WMGraphics.FBGetGlyphSpacings(ch, gs);
					END;
					dx := gs.bearing.l + gs.width + gs.bearing.r
				END
			END GetWidth;
			 			
		BEGIN
			f := GetFont(); (* set the default component font *)
			pos := 0; cws := 0; cls := 0; word := 0; line := 0;
			
			text.AcquireRead;
			utilreader.SetDirection(1); utilreader.SetPosition(pos);
				
			REPEAT
				utilreader.ReadCh(ch);
				
				(* Get the Paragraph Style *)
				IF utilreader.pstyle # NIL THEN
					pStyle := utilreader.pstyle;
					(* parse tabstops *)
					COPY(pStyle.tabStops, tabstring);
					IF (tabstring # "default") & (tabstring # "0") & (tabstring # "") THEN
						NEW(sr, LEN(tabstring)); sr.Set(tabstring); tabCounter := 0;
						WHILE (sr.res = AosIO.Ok) DO
							sr.SkipWhitespace; sr.String(token);
							INC(tabCounter);		
						END;
						NEW(tp, tabCounter);
						sr.Reset; tabCounter := 0;
						WHILE (sr.res = AosIO.Ok) DO
							sr.SkipWhitespace; sr.String(token);
							Utilities.StrToInt(token, tabPos);
							tp[tabCounter] := tabPos;
							INC(tabCounter);		
						END;						
						NEW(tabs, tp)
					END
				END;							
				(* Get the Character Styles / Attributes *)
				IF utilreader.cstyle # NIL THEN
					cStyle := utilreader.cstyle;
					IF (cStyle.fontcache #NIL) & (cStyle.fontcache IS WMGraphics.Font) THEN
						f := cStyle.fontcache(WMGraphics.Font);
					ELSE	
						 f := WMGraphics.GetFont(cStyle.family, ENTIER(FP1616.FixpToFloat(cStyle.size)), cStyle.style);
						utilreader.cstyle.fontcache := f
					END;					
				ELSIF utilreader.pstyle # NIL THEN
					IF pStyle.charStyle # NIL THEN
						cStyle := pStyle.charStyle;
						IF (cStyle.fontcache #NIL) &
							(cStyle.fontcache IS WMGraphics.Font) THEN
							f := cStyle.fontcache(WMGraphics.Font);
						ELSE	
							 f := WMGraphics.GetFont(cStyle.family, ENTIER(FP1616.FixpToFloat(cStyle.size)), cStyle.style);
							utilreader.pstyle.charStyle.fontcache := f
						END
					END;
				ELSIF utilreader.attributes # NIL THEN 
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
				ELSE f := GetFont();
				END;
				
				INC(pos);
				GetWidth(ch, dx);
				
				IF (ch = AosTexts.ObjectChar) THEN
					word := Utilities.Max(word, dx);
					cls := cls + dx;
					cws := 0
				ELSIF (ch = AosTexts.NewLineChar) THEN
					line := Utilities.Max(line, cls);
					cls := 0
				ELSIF (ch = 32) THEN
					word := Utilities.Max(word, cws);
					cws := 0
				ELSE
					cws := cws + dx;
					cls := cls + dx;
				END;
				 
			UNTIL utilreader.eot;
			line := Utilities.Max(line, cls);
			word := Utilities.Max(word, cws);
			text.ReleaseRead;
		
		END GetMinMaxWidth;

(* END view dependant layout functions *)

		PROCEDURE GetFontFromAttr(info : AosTexts.FontInfo) : WMGraphics.Font;
		BEGIN
			RETURN WMGraphics.GetFont(info.name, info.size, info.style);
		END GetFontFromAttr;
		
		PROCEDURE LayoutLine(VAR pos : LONGINT; VAR l : LineInfo; wrapwidth, stopPos, stopXPos : LONGINT);
		VAR i, wrapPos : LONGINT; ch : Char32;
			f : WMGraphics.Font;
			eol, first : BOOLEAN; 
			voff, ascent, descent, leading, ld, a, d, dx, x : LONGINT;
			align, firstIndent, leftIndent, rightIndent, spaceBefore, spaceAfter : LONGINT;
			tabstring : ARRAY 256 OF CHAR; tabs : CustomTabStops; tp : TabPositions;
			sr : AosIO.StringReader; tabCounter, tabPos : LONGINT; token : ARRAY 16 OF CHAR;
			pStyle : AosTexts.ParagraphStyle;
			cStyle : AosTexts.CharacterStyle;
			start, stop : BOOLEAN;
			
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
						(* Add a Sequencer to the object if none exists *)
						IF (vc.sequencer = NIL) OR (vc.sequencer # sequencer) THEN
							vc.SetSequencer(sequencer);
							vc.Reset(NIL, NIL);
						END;
					END
				ELSIF ch = AosTexts.TabChar THEN
					IF l.tabStops # NIL THEN dx := l.tabStops.GetNextTabStop(x) - x 
					ELSE dx := defaultTabStops.GetNextTabStop(x) - x
					END;
					ascent := f.GetAscent() - voff;
					descent := f.GetDescent() + voff
				ELSIF ch = AosTexts.LabelChar THEN
					IF showLabels.Get() THEN
						f := GetFont();
						f.GetStringSize(utilreader.object(AosTexts.LabelPiece).label^, dx, ascent);
						INC(dx, 4);
					ELSE 
						ascent := 0; descent := 0;
						dx := 0;
					END;
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
			
			start := FALSE; stop := FALSE;
			IF (pos = 0) THEN start := TRUE;
			ELSE 
				utilreader.SetPosition(pos-1);
				utilreader.ReadCh(ch);
				IF (ch = AosTexts.NewLineChar) THEN start := TRUE;
				ELSE start := FALSE;
				END;
			END;
			
			i := 0;  ascent := f.GetAscent(); descent := f.GetDescent(); 
			align := AlignLeft; l.tabStops := NIL; COPY("", tabstring);
			firstIndent := 0; leftIndent := 0; rightIndent := 0; spaceBefore := 0; spaceAfter := 0;
			
			REPEAT
				utilreader.ReadCh(ch);
				
				(* Get the Paragraph Style *)
				IF utilreader.pstyle # NIL THEN
					pStyle := utilreader.pstyle;
					(* pStyle := AosTexts.GetParagraphStyleByName(pStyle.name); *)
					spaceBefore := ENTIER(FP1616.FixpToFloat(pStyle.spaceBefore));
					spaceAfter := ENTIER(FP1616.FixpToFloat(pStyle.spaceAfter));
					firstIndent := ENTIER(FP1616.FixpToFloat(pStyle.firstIndent));
					leftIndent := ENTIER(FP1616.FixpToFloat(pStyle.leftIndent));
					rightIndent := ENTIER(FP1616.FixpToFloat(pStyle.rightIndent));
					align := pStyle.alignment;
					(* parse tabstops *)
					COPY(pStyle.tabStops, tabstring);
					IF (tabstring # "default") & (tabstring # "0") & (tabstring # "") THEN
						NEW(sr, LEN(tabstring)); sr.Set(tabstring); tabCounter := 0;
						WHILE (sr.res = AosIO.Ok) DO
							sr.SkipWhitespace; sr.String(token);
							INC(tabCounter);		
						END;
						NEW(tp, tabCounter);
						sr.Reset; tabCounter := 0;
						WHILE (sr.res = AosIO.Ok) DO
							sr.SkipWhitespace; sr.String(token);
							Utilities.StrToInt(token, tabPos);
							tp[tabCounter] := tabPos;
							INC(tabCounter);		
						END;						
						NEW(tabs, tp);
						IF l.tabStops = NIL THEN l.tabStops := tabs END
					END;
				END;								
				(* Get the Character Styles / Attributes *)
				IF utilreader.cstyle # NIL THEN
					cStyle := utilreader.cstyle;
					voff := ENTIER(FP1616.FixpToFloat(cStyle.baselineShift));
					ld := ENTIER(FP1616.FixpToFloat(cStyle.leading));
					IF (cStyle.fontcache #NIL) & (cStyle.fontcache IS WMGraphics.Font) THEN
						f := cStyle.fontcache(WMGraphics.Font);
					ELSE	
						 f := WMGraphics.GetFont(cStyle.family, ENTIER(FP1616.FixpToFloat(cStyle.size)), cStyle.style);
						utilreader.cstyle.fontcache := f
					END;					
				ELSIF utilreader.pstyle # NIL THEN
					IF pStyle.charStyle # NIL THEN
						cStyle := pStyle.charStyle;
						voff := ENTIER(FP1616.FixpToFloat(cStyle.baselineShift));
						ld := ENTIER(FP1616.FixpToFloat(cStyle.leading));
						IF (cStyle.fontcache #NIL) &
							(cStyle.fontcache IS WMGraphics.Font) THEN
							f := cStyle.fontcache(WMGraphics.Font);
						ELSE	
							 f := WMGraphics.GetFont(cStyle.family, ENTIER(FP1616.FixpToFloat(cStyle.size)), cStyle.style);
							utilreader.pstyle.charStyle.fontcache := f
						END
					END;
				ELSIF utilreader.attributes # NIL THEN 
					voff := utilreader.attributes.voff;
					ld := 0;
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
				ELSE voff := 0; f := GetFont(); ld := 0; 
				END;
				
				IF first THEN
					IF ch = AosTexts.NewLineChar THEN
						ascent := f.GetAscent(); descent := 0; 
					ELSE	
						descent := 0; ascent := 0;
					END;
					IF start THEN wrapwidth := wrapwidth - firstIndent - rightIndent;
					ELSE wrapwidth := wrapwidth - leftIndent - rightIndent;
					END;
					first := FALSE;
				END;
				INC(pos);
				IF (stopPos < 0) OR (pos <= stopPos) THEN
					IF ch # AosTexts.NewLineChar THEN
						GetExtents(ch, dx, a, d); ascent := Utilities.Max(ascent, a); descent := Utilities.Max(descent, d);
						IF ld = 0 THEN ld := ascent + descent; ELSE ld := Utilities.Max(ld, ascent + descent); END; leading := Utilities.Max(leading, ld);
						IF isMultiLineI & (wrap # {}) & (i > 0) & (x + dx > wrapwidth) THEN
							eol := TRUE; DEC(pos); wrapPos := pos;
							(* Go left for last space *)
							IF wrap * { WrapWord } # {} THEN 
								pos := AosTextUtilities.FindPosWordLeft(utilreader, pos);
								IF pos <= l.pos THEN pos := wrapPos (* no word break found. wrap at latest possible pos *)
								ELSE (* decrease width to actual size.. *)
(*									utilreader.SetPosition(pos);
									WHILE pos < wrapPos DO
										utilreader.ReadCh(ch); GetExtents(ch, dx, a, d); x := x - dx; INC(pos)
									END
*)								END
							END
						ELSE
							IF (stopXPos >= 0) & (x + dx DIV 2 > stopXPos) THEN DEC(pos); RETURN END;
							INC(x, dx)
						END;
					ELSE eol := TRUE; stop := TRUE; IF (stopXPos >= 0) THEN DEC(pos) END;
					END;
				ELSE eol := TRUE
				END;
				INC(i)
			UNTIL eol OR utilreader.eot;
			l.width := x;
			l.ascent := ascent; l.height := leading; (* ascent + descent; *)
			l.align := align; l.leftIndent := leftIndent; l.rightIndent := rightIndent;
			IF l.height = 0 THEN l.height := f.GetHeight() END;
			IF start THEN l.firstInParagraph := TRUE; l.firstIndent := firstIndent;	l.spaceBefore := spaceBefore;
			ELSE l.firstInParagraph := FALSE;	END;
			IF stop THEN l.lastInParagraph := TRUE; l.spaceAfter := spaceAfter; 
			ELSE l.lastInParagraph := FALSE END;
		END LayoutLine;
		
		PROCEDURE LineYPos(lineNr : LONGINT; VAR y0, y1 : LONGINT);
		VAR i : LONGINT;
		BEGIN
			IF (lineNr >= firstLineI) & (lineNr < layout.GetNofLines()) THEN
				y0 := bordersI.t; i := firstLineI;
				WHILE i < lineNr DO
					y0 := y0 + layout.lines[i].height; 
					CheckParagraphBegin(i, y0);
					CheckParagraphEnd(i, y0);	
					INC(i);			
				END;
				y1 := y0 + layout.lines[i].height;
				CheckParagraphBegin(i, y1);
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
				WHILE i < layout.nofLines DO
					ty := ty + layout.lines[i].height; 
					CheckParagraphBegin(i, ty);
					CheckParagraphEnd(i, ty);	
					INC(i);
				END;
				IF i > 0 THEN y := (ty + layout.lines[i - 1].ascent) ELSE y := (ty + 10) END;
				x := bordersI.l - leftShiftI;
				text.ReleaseRead; RETURN TRUE
			ELSIF (pos = 0) & (firstLineI = 0) THEN x := bordersI.l - leftShiftI; f := GetFont();  y := f.GetAscent();
				CheckParagraphBegin(i, y);
				text.ReleaseRead; RETURN TRUE
			ELSE
				l := layout.FindLineNrByPos(pos);
				IF (l >= firstLineI) & (l < layout.GetNofLines()) THEN
					ty := bordersI.t; i := firstLineI;
					WHILE i < l DO
						ty := ty + layout.lines[i].height; 
						CheckParagraphBegin(i, ty);
						CheckParagraphEnd(i, ty);							
						INC(i);
					END;
					y := (ty + layout.lines[i].ascent);
					CheckParagraphBegin(i, y);	
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
		VAR sx, dx, dy, x, sp, i, j, k, t, tx, linelength, w, voff, bgcolor, p : LONGINT; char : Char32; gs: WMGraphics.GlyphSpacings;
	 		curAttr : AosTexts.Attributes; curCStyle : AosTexts.CharacterStyle;
	 		font : WMGraphics.Font; vc : WMComponents.VisualComponent;
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
				
				IF utilreader.cstyle = NIL THEN
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
					ELSIF curAttr = NIL THEN;	
						canvas.SetColor(defaultAttr.color);
						bgcolor := defaultAttr.bgcolor;
						voff := defaultAttr.voff;
						curAttr := defaultAttr;
						font := GetFont();
					END;
					curCStyle := NIL;
				ELSE
					IF curCStyle # utilreader.cstyle THEN
						curCStyle := utilreader.cstyle;
						canvas.SetColor(curCStyle.color);
						bgcolor := curCStyle.bgColor;
						voff := curCStyle.baselineShift;
						(* get style from cache if possible *)
						IF (curCStyle.fontcache #NIL) & (curCStyle.fontcache IS WMGraphics.Font) THEN
							font := curCStyle.fontcache(WMGraphics.Font);
						ELSE	
							 font := WMGraphics.GetFont(curCStyle.family, ENTIER(FP1616.FixpToFloat(curCStyle.size)), curCStyle.style);
							curCStyle.fontcache := font
						END;							
					END;
					curAttr := NIL;
				END;
				
				IF char = AosTexts.ObjectChar THEN
					IF (utilreader.object # NIL) & (utilreader.object IS WMGraphics.Image) THEN
						canvas.DrawImage(x, top + (l.ascent) + voff - utilreader.object(WMGraphics.Image).height, utilreader.object(WMGraphics.Image), 
							WMGraphics.ModeSrcOverDst);
						dx := utilreader.object(WMGraphics.Image).width
					ELSIF (utilreader.object # NIL) & (utilreader.object IS WMComponents.VisualComponent) THEN
						vc := utilreader.object(WMComponents.VisualComponent);
						dx := vc.bounds.GetWidth();
						dy := vc.bounds.GetHeight();
						canvas.SaveState(clipState); (* save the current clip-state *)
						canvas.SetClipRect(WMRectangles.MakeRect(x + sx, top + (l.ascent - dy), x + dx + sx, top + (l.height)));
						canvas.ClipRectAsNewLimits(x + sx, top + (l.ascent - dy));
						(* assuming the component will not delay --> otherwise a buffer is needed *)
						vc.Acquire; vc.Draw(canvas); vc.Release;
						canvas.RestoreState(clipState)
					END
				ELSIF char = 0 THEN (* EOT *)
				ELSIF char = AosTexts.TabChar THEN
					tx := x;
					IF l.firstInParagraph THEN tx := tx - l.firstIndent
					ELSE tx := tx - l.leftIndent END;
					IF l.tabStops # NIL THEN dx := l.tabStops.GetNextTabStop(tx) - tx 
					ELSE dx := defaultTabStops.GetNextTabStop(tx) - tx
					END;
					IF bgcolor # 0 THEN 
						canvas.Fill(WMRectangles.MakeRect(x + sx, top, x + dx + sx, top + (l.height)), bgcolor, WMGraphics.ModeCopy)
					END
				ELSIF char = AosTexts.LabelChar THEN
					IF showLabels.Get() THEN
						font := GetFont();
						font.GetStringSize(utilreader.object(AosTexts.LabelPiece).label^, dx, dy);
						font.RenderString(canvas, x + sx+2, top + (l.ascent), utilreader.object(AosTexts.LabelPiece).label^);
						INC(dx, 4);						
						canvas.Fill(WMRectangles.MakeRect(x + sx, top, x + dx + sx, top + (l.height)), 0FF880050H, WMGraphics.ModeSrcOverDst);
						WMGraphicUtilities.RectGlassShade(canvas, WMRectangles.MakeRect(x + sx, top, x + dx + sx, top + (l.height)), 1, FALSE)
					ELSE dx := 0; END;
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
				
				(* link *)
				IF utilreader.link # NIL THEN
					canvas.Line(x + sx, top + (l.ascent)+1, x + dx + sx, top + (l.ascent)+1, canvas.color, WMGraphics.ModeSrcOverDst);
				END;
				
				(* highlight *)
				p := utilreader.GetPosition();
				FOR j := 0 TO nofHighlights - 1 DO 
					IF (p > highlights[j].a) & (p <= highlights[j].b) THEN
						CASE highlights[j].kind OF
							|HLOver: canvas.Fill(WMGraphics.MakeRectangle(x + sx, top, x + dx + sx, top + (l.height)), highlights[j].color, WMGraphics.ModeSrcOverDst)
							|HLUnder: canvas.Line(x + sx, top + (l.ascent), x + dx + sx, top + (l.ascent), highlights[j].color, WMGraphics.ModeSrcOverDst);
							|HLWave: 
								FOR k := 0 TO dx - 1 DO 
									t := 1 - ABS((x + k) MOD 4 - 2); (* because of compiler bug on intel *)
									canvas.SetPixel(x + k + sx, top + l.ascent + t, highlights[j].color, WMGraphics.ModeSrcOverDst);
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
					IF (l >= 0) & (l < layout.GetNofLines()) THEN 
						ascent := layout.lines[l].ascent;
					(*	IF ascent = 0 THEN ascent := layout.lines[l].height END;
						IF ascent = 0 THEN ascent := 10 END; *)
					ELSE ascent := 10 END;	
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
				WMGraphicUtilities.DrawBevel(canvas, GetClientRect(), 
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
			
			top := bordersI.t; 
			FOR i := firstLineI TO la - 1 DO
				top := top + (layout.lines[i].height);
				CheckParagraphBegin(i, top);
				CheckParagraphEnd(i, top);					
			END;
			IF la >= 0 THEN 
				(* draw the lines that intersect the clipping rectangle *)
				FOR i := la TO lb DO 
					CheckParagraphBegin(i, top);
					RenderLine(canvas, layout.lines[i], i, top, -1); 
					top := top + (layout.lines[i].height);
					CheckParagraphEnd(i, top);	
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
		VAR pos, a, b : LONGINT;
		BEGIN
			IF keys * {0, 1, 2} = {1} THEN 
				canStart := TRUE; openFile := FALSE;
				IF commandMarker = NIL THEN
					commandMarker := CreateHighlight();
					commandMarker.SetKind(HLUnder);
					commandMarker.SetColor(0FF0000FFH);
					text.AcquireRead;
					ViewToTextPos(x, y, pos);
					FindCommand(pos, a, b);
					commandMarker.SetFromTo(a, b);
					cursor.SetPosition(pos);
					text.ReleaseRead
				END;
			END;
			IF canStart & (2 IN keys) THEN openFile := TRUE END;
			IF keys * {0, 1, 2} = {0, 1, 2} THEN AbortStart END;
			IF keys * {0, 1, 2} = {2} THEN 
				text.AcquireRead;
				ViewToTextPos(x, y, pos);
				cursor.SetPosition(pos);
				text.ReleaseRead;
				ShowContextMenu(x, y) END;
			IF 0 IN keys THEN
				AbortStart;
				text.AcquireRead;
				ViewToTextPos(x, y, pos);
				dragPossible := FALSE; selectWords := FALSE;
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
				text.ReleaseRead;
				CursorChanged
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
					text.ReleaseRead; 
					CursorChanged
				END
			END
		END PointerMove;
		
		PROCEDURE PointerUp*(x, y : LONGINT; keys : SET);
		BEGIN
			IF canStart & (commandMarker # NIL) THEN
				commandMarker.Sort;
				StartCommand((commandMarker.a + commandMarker.b) DIV 2, openFile);
				AbortStart
			END;
			selecting := FALSE; 
			IF dragPossible THEN selection.SetFromTo(0, 0); AosTexts.ClearLastSelection (* reset selection *) END;
			dragPossible := FALSE
		END PointerUp;
		
		(* Transforms the TextView Coordinates into TextObject obj Coordinates *)
		PROCEDURE TransformCoordinates(VAR x, y : LONGINT; obj : WMComponents.VisualComponent);
		VAR line, pos, x0, y0, y1 : LONGINT;
		BEGIN
			ViewToTextPos(x, y, pos);
			IF FindScreenPos(pos, x0, y0) THEN
				IF x0 > x THEN pos := pos - 1;
					IF FindScreenPos(pos, x0, y0) THEN END;
				END;
				line := layout.FindLineNrByPos(pos);
				LineYPos(line, y0, y1);
				x := x - x0;
				y := y - y0;
				IF line >= 0 THEN y := y - (layout.lines[line].ascent - obj.bounds.GetHeight()); END								
			END
		END TransformCoordinates;
		
		(* Change the pointer according to the underlaying component *)
		PROCEDURE ChangePointer(pointerInfo : WMWindowManager.PointerInfo);
		BEGIN
			IF GetPointerInfo() # pointerInfo THEN
				SetPointerInfo(pointerInfo)
			END			
		END ChangePointer;		
		
		(* Returns TRUE if an Object is Hit, FALSE otherwise *)
		PROCEDURE HitObject(x, y : LONGINT; (* keys : SET;*)  VAR pos : LONGINT; VAR obj : ANY): BOOLEAN;
		VAR ch, tx, ty : LONGINT;
		BEGIN
			text.AcquireRead;
			ViewToTextPos(x, y, pos);
			IF FindScreenPos(pos, tx, ty) THEN
				IF tx > x THEN pos := pos - 1 END
			END;
			utilreader.SetPosition(pos);
			utilreader.ReadCh(ch);
			text.ReleaseRead;
			IF ch = AosTexts.ObjectChar THEN obj := utilreader.object;
				RETURN TRUE
			ELSE
				RETURN FALSE
			END
		END HitObject;
		
		(* Returns TRUE if a Link is Hit, FALSE otherwise *)
		PROCEDURE HitLink(x, y : LONGINT;  VAR pos : LONGINT; VAR link : AosTexts.Link): BOOLEAN;
		VAR ch, tx, ty : LONGINT;
		BEGIN
			text.AcquireRead;
			ViewToTextPos(x, y, pos);
			IF FindScreenPos(pos, tx, ty) THEN
				IF tx > x THEN pos := pos - 1 END
			END;
			utilreader.SetPosition(pos);
			utilreader.ReadCh(ch);
			text.ReleaseRead;
			IF utilreader.link # NIL THEN
				link := utilreader.link;
				RETURN TRUE
			ELSE
				RETURN FALSE
			END
		END HitLink;
		
		PROCEDURE LinkClick(link : AosTexts.Link);
		VAR w : LinkWrapper;
		BEGIN
			NEW(w); w.link := link;
			onLinkClicked.Call(w)
		END LinkClick;
		
		(* builtin behaviour *)
		PROCEDURE LinkClicked*(sender, data : ANY);
		VAR tempLink : ARRAY 2048 OF CHAR;
			tempLabel : ARRAY 256 OF CHAR;
			pos, i : LONGINT;
		BEGIN
			IF data IS LinkWrapper THEN
				COPY(data(LinkWrapper).link^, tempLink);
				IF tempLink[0] = "#" THEN	(* internal link *)
					i := 0;
					WHILE tempLink[i] # 0X DO
						tempLabel[i] := tempLink[i+1];
						INC(i);
					END;
					tempLink[i] := 0X;
					(* find label in tv *)
					IF FindLabel(tempLabel, pos) THEN
						i := layout.nofLines-1;
						WHILE (i >= 0) DO
							IF layout.GetLineStartPos(i) < pos THEN firstLine.Set(i); RETURN END;
							DEC(i);
						END;
					END;
				ELSE	(* other links *)
				
				END
			END
		END LinkClicked;
		
		(* Returns the position of the label in text *)
		PROCEDURE FindLabel*(label : ARRAY OF CHAR; VAR pos : LONGINT): BOOLEAN;
		VAR ch : LONGINT;
			found : BOOLEAN;
		BEGIN
			found := FALSE; pos := 0;
			text.AcquireRead;
			utilreader.SetDirection(1); utilreader.SetPosition(pos);
			REPEAT
				utilreader.ReadCh(ch);
				IF ch = AosTexts.LabelChar THEN
					IF utilreader.object(AosTexts.LabelPiece).label^ = label THEN
						found := TRUE;
					END;
				END;
				INC(pos);
			UNTIL utilreader.eot OR found;
			text.ReleaseRead;
			RETURN found;
		END FindLabel;			
	
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
						IF TraceCopy IN Trace THEN AosOut.String("WMTextView: Not copy"); AosOut.Ln; END;
						text.AcquireWrite;
						a := dragSelA.GetPosition(); b := dragSelB.GetPosition();
						pos := itf(WMDropTarget.DropText).pos.GetPosition();
						IF (targetText # text) OR (pos < a) OR (pos > b) THEN
							NEW(temp); temp.AcquireWrite; temp.CopyFromText(text, a, b-a, 0);	temp.ReleaseWrite;
							text.Delete(a, b- a);
							pos := itf(WMDropTarget.DropText).pos.GetPosition();
							temp.AcquireRead;	
								targetText.CopyFromText(temp, 0, temp.GetLength(), pos);
							temp.ReleaseRead;
						END;
						text.ReleaseWrite
					ELSE
						IF TraceCopy IN Trace THEN AosOut.String("WMTextView: Copy"); AosOut.Ln; END;
						text.AcquireRead;
						pos := itf(WMDropTarget.DropText).pos.GetPosition();
						a := dragSelA.GetPosition(); b := dragSelB.GetPosition();
						targetText.CopyFromText(text, a, b-a, 0);
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
				AosTexts.clipboard.CopyFromText(text, selection.a, selection.b - selection.a, 0);
			END;
			AosTexts.clipboard.ReleaseWrite;
			text.ReleaseRead
		END CopySelection;
		
		PROCEDURE DeleteSelection*;
		BEGIN
			text.AcquireWrite;
			selection.Sort;
			text.Delete(selection.a, selection.b - selection.a);
			text.ReleaseWrite
		END DeleteSelection;	

		PROCEDURE Paste*;
		BEGIN
			text.AcquireWrite;
			AosTexts.clipboard.AcquireRead;
			IF AosTexts.clipboard.GetLength() > 0 THEN
				IF selection.b - selection.a # 0 THEN DeleteSelection() END;
				text.CopyFromText(AosTexts.clipboard, 0, AosTexts.clipboard.GetLength(), cursor.GetPosition())
			END;
			AosTexts.clipboard.ReleaseRead;
			text.ReleaseWrite		
		END Paste;	
		
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
		
		PROCEDURE CursorChanged;
		BEGIN
			IF (onCursorChanged # NIL) THEN onCursorChanged END
		END CursorChanged;

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
			text.ReleaseRead;
			CursorChanged
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
			text.ReleaseRead;
			CursorChanged
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
			text.ReleaseRead;
			CursorChanged
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
			text.ReleaseRead;
			CursorChanged
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
			text.ReleaseRead;
			CursorChanged
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
			text.ReleaseRead;
			CursorChanged
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
			text.ReleaseRead;
			CursorChanged
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
			text.ReleaseRead;
			CursorChanged
		END End;
		
		PROCEDURE KeyEvent*(ucs :LONGINT; flags : SET; VAR keysym : LONGINT);
		BEGIN
			modifierFlags := flags;
			IF AosInputs.Release IN flags THEN RETURN END;
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
		
		PROCEDURE FindCommandRange*(pos: LONGINT; VAR start, end : LONGINT);
		VAR ch : LONGINT;
		BEGIN
		(*	start := AosTextUtilities.FindPosWordLeft(utilreader, pos); *)
			text.AcquireRead;
			utilreader.SetDirection(-1); utilreader.SetPosition(pos);
			REPEAT	utilreader.ReadCh(ch) UNTIL AosTextUtilities.IsWhiteSpace(ch) OR utilreader.eot;
			start := utilreader.GetPosition() + 2;
			IF utilreader.eot THEN DEC(start, 2) END;
			(* search ~ *)
			utilreader.SetDirection(1); utilreader.SetPosition(start);
			REPEAT	utilreader.ReadCh(ch) UNTIL (ch = ORD("~")) OR (utilreader.eot);
			end := utilreader.GetPosition() - 1;
			IF utilreader.eot THEN INC(end) END;
			text.ReleaseRead
		END FindCommandRange;
		
		PROCEDURE FindCommand*(pos: LONGINT; VAR start, end : LONGINT);
		VAR ch : LONGINT;
		BEGIN
			text.AcquireRead;
			utilreader.SetDirection(-1); utilreader.SetPosition(pos);
			REPEAT	utilreader.ReadCh(ch) UNTIL AosTextUtilities.IsWhiteSpace(ch) OR utilreader.eot;
			start := utilreader.GetPosition() + 2;
			IF utilreader.eot THEN DEC(start, 2) END;
			
			utilreader.SetDirection(1); utilreader.SetPosition(pos);
			REPEAT	utilreader.ReadCh(ch) UNTIL AosTextUtilities.IsWhiteSpace(ch) OR utilreader.eot;
			end := utilreader.GetPosition() - 1;
			IF utilreader.eot THEN INC(end) END;
			text.ReleaseRead;
		END FindCommand;
		
		(* start the AosCommand in the text, starting on pos (or wordboundary before),
		caller should hold lock on text  to make the pos stable *)
		PROCEDURE StartCommand*(pos : LONGINT; openFile : BOOLEAN);
		VAR 
			start, end, bufSize : LONGINT;
			parameters : AosCommands.Parameters;
			command : Utilities.String;
			s : Utilities.String;
			msg : ARRAY 128 OF CHAR;
			i, j, res : LONGINT;
		BEGIN
			text.AcquireRead;
			IF openFile THEN FindCommand(pos, start, end)
			ELSE FindCommandRange(pos, start, end)
			END;
			bufSize := Utilities.Max(Utilities.Min((end - start) * 5 + 1 (* for UTF *), MaxCallParameterBuf), 1); 
			NEW(s, bufSize);
			AosTextUtilities.SubTextToStr(text, start, end - start, s^);
			text.ReleaseRead;
			IF openFile THEN 
				OpenFile(s) 
			ELSE
				NEW(command, LEN(s)); 
				i := 0;
				WHILE (s[i] # 0X) & (s[i] # ";") & (s[i] # " ") & (s[i] # 09X) & (s[i] # 0DX) & (s[i] # 0AX) DO command[i] := s[i]; INC(i); END;
				IF i < LEN(command) THEN command[i] := 0X; END;
				
				IF (i < LEN(s)) THEN (* copy parameter string *)
					NEW(parameters); NEW(parameters.str, LEN(s));
					INC(i); WHILE i < LEN(s) DO parameters.str[j] := s[i]; INC(i); INC(j);  END;
					IF j < LEN(parameters.str) THEN parameters.str[j] := 0X; END;
				ELSE 
					parameters := NIL;
				END;
				
				IF TraceCommands IN Trace THEN
					AosOut.String("WMTextView: Executing command: '"); AosOut.String(command^); AosOut.String("'");
					AosOut.String(", parameters: ");
					IF parameters = NIL THEN AosOut.String("None"); ELSE AosOut.String("'"); AosOut.String(parameters.str^); AosOut.String("'"); END;
					AosOut.Ln;
				END;
				AosCommands.Activate(command^, parameters, {}, res, msg);
				IF res # AosCommands.Ok THEN
					AosOut.String("WMTextView: Command execution error, res: "); AosOut.Int(res, 0); 
					AosOut.String(" ("); AosOut.String(msg); AosOut.String(")"); AosOut.Ln;
				END;
			END;	
		END StartCommand;
		
		PROCEDURE Start(sender, data: ANY);
		VAR caller : CommandCaller;
		BEGIN
			IF (data # NIL) & (data IS ClickInfo) THEN
				IF data(ClickInfo).cmdPar # NIL THEN
					NEW(caller, data(ClickInfo).cmdPar^);
				END
			END
		END Start;
		
		PROCEDURE Open(sender, data: ANY);
		BEGIN
			IF (data # NIL) & (data IS ClickInfo) THEN
				IF data(ClickInfo).cmd # NIL THEN
					OpenFile(data(ClickInfo).cmd)
				END	
			END
		END Open;
		
		PROCEDURE PieMenuStart(sender, data: ANY);
		BEGIN
			Start(piemenu, piemenu.userData)
		END PieMenuStart;	
		
		PROCEDURE PieMenuOpen(sender, data: ANY);
		BEGIN
			Open(piemenu, piemenu.userData)
		END PieMenuOpen;
		
		PROCEDURE PieMenuCopy(sender, data: ANY);
		BEGIN
			CopySelection;
		END PieMenuCopy;
		
		PROCEDURE PieMenuPaste(sender, data: ANY);
		BEGIN
			Paste;
		END PieMenuPaste;			
		
		PROCEDURE ShowContextMenu(x, y: LONGINT);
		VAR 
			popup : WMPopups.Popup;
			start, end, bufSize : LONGINT;
			command, s : Utilities.String;
			clickInfo : ClickInfo;
			str : ARRAY 256 OF CHAR;
			window : WMWindowManager.Window;
		BEGIN
			text.AcquireRead;
			FindCommand(cursor.GetPosition(), start, end);
			bufSize := Utilities.Max(Utilities.Min((end - start) * 5 + 1 (* for UTF *), 4096), 1); 
			NEW(command, bufSize);
			AosTextUtilities.SubTextToStr(text, start, end - start, command^);

			FindCommandRange(cursor.GetPosition(), start, end);
			bufSize := Utilities.Max(Utilities.Min((end - start) * 5 + 1 (* for UTF *), MaxCallParameterBuf), 1); 
			NEW(s, bufSize);
			AosTextUtilities.SubTextToStr(text, start, end - start, s^);
			text.ReleaseRead;
			
			NEW(clickInfo);
			clickInfo.cmd := command;
			clickInfo.cmdPar := s;
								
			IF UsePieMenu THEN				
				NEW(piemenu); piemenu.SetEnabled({0, 1, 2, 3});
				piemenu.SetText(1, Utilities.NewString("Open")); 
				piemenu.SetText(3, Utilities.NewString("Start"));
				piemenu.SetText(2, Utilities.NewString("Copy"));
				piemenu.SetText(0, Utilities.NewString("Paste"));
					
				piemenu.userData := clickInfo;
					
				piemenu.on1.Add(PieMenuOpen);
				piemenu.on2.Add(PieMenuCopy);
				piemenu.on3.Add(PieMenuStart);
				piemenu.on0.Add(PieMenuPaste);
					
				manager := WMWindowManager.GetDefaultManager();
				window := manager.GetPositionOwner(x, y);
				IF window = NIL THEN RETURN END;
				
				Acquire; ToWMCoordinates(x, y, x, y); Release;
				piemenu.Show(window, x, y, FALSE);		
				(* TODO: Can't set  := NIL, since its used by the button handlers *)		
			ELSE
				NEW(popup);
				str := "Start "; Utilities.Append(str, command^); popup.AddParButton(str, Start, clickInfo);
				str := "Open "; Utilities.Append(str, command^); popup.AddParButton(str, Open, clickInfo);
				Acquire; ToWMCoordinates(x, y, x, y); Release;
				popup.Popup(x, y);
			END
		END ShowContextMenu;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		VAR pos, mx, my : LONGINT; obj : ANY; link : AosTexts.Link;
		BEGIN
			IF (x.msgType = WMMessages.MsgKey) & objHasFocus THEN					(* forward KeyMsg *)
				(* AosOut.String("Forwarding KeyMsg to FocusObject "); AosOut.Int(focusPos, 0); AosOut.Ln; *)
				WITH focusObject : WMComponents.VisualComponent DO
					focusObject.Handle(x);
					InvalidateRange(focusPos, focusPos+1)
				END
			ELSIF (x.msgType # WMMessages.MsgKey) & HitObject(x.x, x.y, pos, obj) THEN	(* forward Msg *)
				SetFocus; cursor.SetVisible(FALSE);
				(* AosOut.String("Forwarding Msg "); AosOut.Int(x.msgType, 0); AosOut.String(" to Object: "); AosOut.Int(pos, 0);AosOut.Ln; *)
				IF obj IS WMComponents.VisualComponent THEN
					WITH obj : WMComponents.VisualComponent DO
						(* remove oldObject first *)
						IF (oldObject # NIL) & (oldObject # obj) THEN
							(* AosOut.String("Killing old Object "); AosOut.Int(oldPos, 0); AosOut.Ln; *)
						(*	mx := x.x; my := x.y;
							TransformCoordinates(x.x, x.y, oldObject(WMComponents.VisualComponent));
						*)	oldObject(WMComponents.VisualComponent).Handle(x);
							InvalidateRange(oldPos, oldPos+1);
						(*	x.x := mx; x.y := my;		*)			
						END;
											
						TransformCoordinates(x.x, x.y, obj);									(* transform to obj coords *)
						obj.Handle(x);														(* call obj Handle *)
						ChangePointer(obj.GetPointerInfo());									(* change the pointer Image *)
						InvalidateRange(pos, pos+1);										(* redraw obj *)						
						oldObject := obj; oldPos := pos;										(* store last object *)
						(* transfer focus to Object *)
						IF (x.msgType = WMMessages.MsgPointer) & (x.flags * {0, 1, 2} = {0}) THEN
							(* AosOut.String("-> focus change"); AosOut.Ln; *)
							(* remove old focus first *)
							IF (focusObject # NIL) & (focusObject # obj) THEN
								focusObject(WMComponents.VisualComponent).FocusLost;
								InvalidateRange(focusPos, focusPos+1)
							END; 
			
							objHasFocus := TRUE;
							focusObject := obj; focusPos := pos;
(*							FocusLost *)
						END
					END
				END
			ELSIF (x.msgType = WMMessages.MsgPointer) & HitLink(x.x, x.y, pos, link) THEN (* Link *)
				ChangePointer(manager.pointerLink);
				IF (x.msgSubType = 2) &(oldFlags / x.flags =  {CallURLPointer}) THEN LinkClick(link); END;
				oldFlags := x.flags;
			ELSE
				ChangePointer(manager.pointerText);									(* change Pointer back *)
				(* AosOut.String("TV message"); *)
				(* transfer focus back to TextView *)
				IF (focusObject # NIL) & (x.msgType = WMMessages.MsgPointer) & (x.flags * {0, 1, 2} = {0}) THEN
					focusObject(WMComponents.VisualComponent).FocusLost;
					objHasFocus := FALSE;
					InvalidateRange(focusPos, focusPos+1);
					FocusReceived;
					focusObject := NIL
				END;
				(* update last Object *)
				IF (oldObject # NIL) & (x.msgType = WMMessages.MsgPointer) THEN
					(* AosOut.String(" - Killing old Object "); AosOut.Int(oldPos, 0); *)
					oldObject(WMComponents.VisualComponent).Handle(x);
					InvalidateRange(oldPos, oldPos+1);
					oldObject := NIL
				END;
				(* AosOut.Ln; *)
				
				IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS AosTexts.StyleChangedMsg) THEN
					layout.FullLayout; Invalidate; CheckNumberOfLines;
				ELSE
					Handle^(x);
				END;
			END
		END Handle;
		
	END TextView;
	
	CommandCaller = OBJECT
	VAR msg : ARRAY 512 OF CHAR;
		s : Utilities.String;
		res : LONGINT;
		
		PROCEDURE &Init(command : ARRAY OF CHAR);
		BEGIN
			s := Utilities.NewString(command)
		END Init;

	BEGIN {ACTIVE}
		AosCommands.Call(s^, {}, res, msg);
		IF res # 0 THEN AosOut.String("WMTextView.CommandCaller: "); AosOut.String(msg); AosOut.Ln END;
	END CommandCaller;
		
VAR manager : WMWindowManager.WindowManager;
	PTVIsMultiLine, PTVIsPassword, PTVShowBorder, PTValwaysShowCursor, PTVShowLabels : WMProperties.BooleanProperty;
	PTVfirstLine, PTVleftShift, PTVPasswordChar : WMProperties.Int32Property;
	PTVdefaultTextColor, PTVdefaultTextBgColor : WMProperties.ColorProperty;
	PTVborders : WMProperties.RectangleProperty;
	PTVonLinkClick, PTVonLinkClickInfo : Utilities.String;
	
PROCEDURE Limit(x, min, max : LONGINT) : LONGINT;
BEGIN
	IF x < min THEN x := min END;
	IF x > max THEN x := max END;
	RETURN x
END Limit;

(** Opens the file path; corresponding file handlers are specified in AosConfig.XML *)
PROCEDURE OpenFile* (path : Utilities.String);
VAR config, filehandler, name, ext : ARRAY 512 OF CHAR;
	i : LONGINT;
	fileOpener : CommandCaller;
BEGIN
	i := 0; WHILE path[i] # 0X DO IF path[i] <= 20X THEN path[i] := 0X ELSE INC(i) END END;
	AosFS.SplitExtension(path^, name, ext);
	Utilities.LowerCase(ext);
	config := "Filehandlers.";
	(* get the right handler *)
	Utilities.Append(config, ext);
	AosConfig.Get(config, filehandler);
	
	IF filehandler = "" THEN
		AosOut.String("WMTextView: Opening '"); AosOut.String(ext); AosOut.String("' files not specified in AosConfig.XML."); AosOut.Ln; 
		RETURN 
	END;
	
	(* construct the command *)
	Utilities.Append(filehandler, ' "');
	Utilities.Append(filehandler, path^);
	Utilities.Append(filehandler, '"');
	
	(* call the command in another process *)
	NEW(fileOpener, filehandler);
END OpenFile;
		
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
	NEW(PTVShowLabels, NIL, NewString("ShowLabels"), 
		NewString("set to true, if the labels should be shown in the text"));
	PTVShowLabels.Set(FALSE); 	
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
	PTVonLinkClick := Utilities.NewString("Link Click Event");
	PTVonLinkClickInfo := Utilities.NewString("fired when a link is pressed");
	AosModules.InstallTermHandler(Finalize)
END WMTextView.

Benchmark : PositionCursor took 1.434
Benchmark : SetTopPos took 74.177
Total Benchmark : 75.611
