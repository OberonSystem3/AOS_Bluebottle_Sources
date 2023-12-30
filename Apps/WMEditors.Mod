MODULE WMEditors;	(** AUTHOR "TF"; PURPOSE "Editor component"; *)
(**
 * History:
 *
 *	21.03.2006	Call the finalizer of the TextView associated to a editor instance in Editor.Finalize (staubesv)
 *)
 
IMPORT
	AosModules, WMComponents, AosIO, UTF8Strings, AosCommands, 
	AosTexts, AosTextUtilities, WMEvents, WMProperties, AosInputs, Utilities, 
	WMStandardComponents, WMTextView, WMInputMethods, AosOut, UndoManager;
	
TYPE
	String = Utilities.String;
	MacroData* = OBJECT
	VAR
		text* : AosTexts.Text;
		cursor* : WMTextView.PositionMarker;
		keySym* : LONGINT; 
		flags* : SET;
		handled* : BOOLEAN;
	END MacroData;
	
	Editor* = OBJECT(WMComponents.VisualComponent)
	VAR tv- : WMTextView.TextView;
		vScrollbar- : WMStandardComponents.Scrollbar;
		hScrollbar- : WMStandardComponents.Scrollbar;
		ime : WMInputMethods.IME; 
		multiLine-, readOnly- : WMProperties.BooleanProperty;
		text- : AosTexts.Text;
		utilreader : AosTexts.TextReader;
		onEnter-, onEscape- : WMEvents.EventSource;
		macros- : WMEvents.EventSource; (* must be handled directly without queuing, text has writelock, may not trap *)
		macroData : MacroData;
		currentFlags : SET;
		allowIME* : BOOLEAN;
		allowScrollbars- : WMProperties.BooleanProperty;
		undoMgr*: UndoManager.UndoManager;

		PROCEDURE &Init;
		BEGIN
			Init^;
			allowIME := TRUE;
			NEW(multiLine, multiLineProto, NIL, NIL); properties.Add(multiLine);
			NEW(readOnly, readOnlyProto, NIL, NIL); properties.Add(readOnly);
			NEW(allowScrollbars, allowScrollbarsProto, NIL, NIL); properties.Add(allowScrollbars);
			(* events *)
			NEW(onEnter, SELF, GSonEnter, GSonEnterInfo, SELF.StringToCompCommand); events.Add(onEnter);
			NEW(onEscape, SELF, GSonEscape, GSonEscapeInfo, SELF.StringToCompCommand); events.Add(onEscape);
			NEW(macros, SELF, GSmacros, GSmacrosInfo, SELF.StringToCompCommand); events.Add(macros);
			
			NEW(vScrollbar); vScrollbar.alignment.Set(WMComponents.AlignRight); AddContent(vScrollbar);
			NEW(hScrollbar); hScrollbar.alignment.Set(WMComponents.AlignBottom); 
			hScrollbar.vertical.Set(FALSE); AddContent(hScrollbar);
			NEW(tv); tv.alignment.Set(WMComponents.AlignClient); AddContent(tv);
			tv.SetScrollbars(hScrollbar, vScrollbar);
			takesFocus.Set(FALSE);
			needsTab.Set(TRUE);
			NEW(text);
			NEW(utilreader, text);
			tv.SetText(text);
			NEW(macroData);
			tv.SetExtKeyEventHandler(KeyPressed);
			tv.SetExtPointerDownHandler(MousePressed)
		END Init;
		
		PROCEDURE SetUndoManager*(uMgr: UndoManager.UndoManager);
		BEGIN
			undoMgr := uMgr;
		END SetUndoManager;
		
		PROCEDURE Undo*;
		BEGIN
			IF undoMgr # NIL THEN
				undoMgr.Undo();
				tv.cursor.SetPosition(undoMgr.actualPos)
			END
		END Undo;
				
		PROCEDURE Redo*;
		BEGIN
			IF undoMgr # NIL THEN
				undoMgr.Redo();
				tv.cursor.SetPosition(undoMgr.actualPos)
			END
		END Redo;		
		
		PROCEDURE SetFocus*;
		BEGIN
			(* block super call to avoid loop *)
			tv.SetFocus
		END SetFocus;
		
		PROCEDURE Initialize*;
		BEGIN
			Initialize^;
			Resized
		END Initialize;
		
		PROCEDURE CheckScrollbars;
		BEGIN
			IF allowScrollbars.Get() & multiLine.Get() THEN
				vScrollbar.visible.Set(TRUE); hScrollbar.visible.Set(TRUE)
			ELSE
				vScrollbar.visible.Set(FALSE); hScrollbar.visible.Set(FALSE)
			END
		END CheckScrollbars;
		
		PROCEDURE RecacheProperties;
		BEGIN
			RecacheProperties^;
			tv.isMultiLine.Set(multiLine.Get());
			CheckScrollbars
		END RecacheProperties;
		
		PROCEDURE PropertyChanged*(sender, data : PTR);
		BEGIN
			IF data = multiLine THEN tv.isMultiLine.Set(multiLine.Get()); CheckScrollbars
			ELSE PropertyChanged^(sender, data)
			END;
		END PropertyChanged;
		
		PROCEDURE SetText*(t : AosTexts.Text);
		BEGIN
			Acquire;
			text := t;
			NEW(utilreader, text);
			tv.SetText(t);
			Release
		END SetText;
		
		PROCEDURE FocusReceived;
		VAR x, y : LONGINT;
		BEGIN 
			FocusReceived^;
			tv.SetFocus
		END FocusReceived;
		
		PROCEDURE FocusLost;
		BEGIN tv.FocusLost^; 
			IF ime # NIL THEN ime.Hide END;
		END FocusLost;
		
		PROCEDURE InsertChar*(ch : AosTexts.Char32);
		VAR buf : ARRAY 2 OF AosTexts.Char32;
		BEGIN
			IF tv.selection.b - tv.selection.a # 0 THEN DeleteSelection() END;
			buf[0] := ch; buf[1] := 0;
			text.InsertUCS32(tv.cursor.GetPosition(), buf) (* cursor moves automagically *)
		END InsertChar;
		
		PROCEDURE CopySelection*;
		BEGIN
			tv.CopySelection
		END CopySelection;
		
		PROCEDURE DeleteSelection*;
		BEGIN
			text.AcquireWrite;
			tv.selection.Sort;
			text.Delete(tv.selection.a, tv.selection.b - tv.selection.a);
			text.ReleaseWrite
		END DeleteSelection;
		
		PROCEDURE Paste*;
		BEGIN
			text.AcquireWrite;
			AosTexts.clipboard.AcquireRead;
			IF AosTexts.clipboard.GetLength() > 0 THEN
				IF tv.selection.b - tv.selection.a # 0 THEN DeleteSelection() END;
				text.CopyFromText(AosTexts.clipboard, 0, AosTexts.clipboard.GetLength(),tv.cursor.GetPosition())
			END;
			AosTexts.clipboard.ReleaseRead;
			text.ReleaseWrite
		END Paste;
		
		PROCEDURE Delete(flags : SET);
		VAR pos : LONGINT;
		BEGIN
			pos := tv.cursor.GetPosition();
			(* shift delete *)
			IF flags * AosInputs.Shift # {} THEN
				tv.selection.Sort;
				IF tv.selection.active & (pos >= tv.selection.a) & (pos <= tv.selection.b) THEN
					CopySelection
				END;			
			END;
			IF flags * AosInputs.Ctrl # {} THEN
				text.Delete(pos, AosTextUtilities.FindPosWordRight(utilreader, pos) - pos)
			ELSE
				tv.selection.Sort;
				IF tv.selection.active & (pos >= tv.selection.a) & (pos <= tv.selection.b) THEN DeleteSelection 
				ELSE text.Delete(pos, 1)
				END
			END
		END Delete;
		
		PROCEDURE Backspace(word : BOOLEAN);
		VAR pos, np : LONGINT;
		BEGIN
			pos := tv.cursor.GetPosition();
			IF word THEN
				np := AosTextUtilities.FindPosWordLeft(utilreader, pos - 1);
				text.Delete(np, pos - np)
			ELSE
				tv.selection.Sort;
				IF tv.selection.active & (pos >= tv.selection.a) & (pos <= tv.selection.b) THEN DeleteSelection 
				ELSE text.Delete(pos - 1, 1)
				END
			END
		END Backspace;
		
		PROCEDURE Enter(flags : SET);
		VAR pos, lineStart, nofWhitespace : LONGINT;
			ctrl : BOOLEAN;
			(* for call *)
			w : AosIO.StringWriter; i, p : LONGINT; ch : LONGINT; resstr: ARRAY 8 OF CHAR;
			msg : ARRAY 64 OF CHAR; res : LONGINT; str : String;
		BEGIN
			ctrl := flags * AosInputs.Ctrl # {};
			IF ctrl THEN (* put into different module ??? *)
				pos := tv.cursor.GetPosition();
				tv.StartCommand(pos, flags * AosInputs.Shift # {});
			ELSE
				IF multiLine.Get() THEN
					pos := tv.cursor.GetPosition();
					lineStart := AosTextUtilities.FindPosLineStart(utilreader, pos);
					nofWhitespace := AosTextUtilities.CountWhitespace(utilreader, lineStart);
					nofWhitespace := Utilities.Min(nofWhitespace, pos - lineStart);
					InsertChar(AosTexts.NewLineChar);
					IF nofWhitespace > 0 THEN
						text.CopyFromText(text, lineStart, nofWhitespace, pos+1);
					END;
				END
			END;
			onEnter.Call(NIL)
		END Enter;
		
		PROCEDURE IndentLeft;
		BEGIN
			text.AcquireWrite;
			tv.selection.Sort;
			AosTextUtilities.IndentText(text, tv.selection.a, tv.selection.b, TRUE);
			text.ReleaseWrite
		END IndentLeft;

		PROCEDURE IndentRight;
		BEGIN
			text.AcquireWrite;
			tv.selection.Sort;
			AosTextUtilities.IndentText(text, tv.selection.a, tv.selection.b, FALSE);
			text.ReleaseWrite
		END IndentRight;
		
		
		PROCEDURE MousePressed(x, y : LONGINT; keys : SET; VAR handled : BOOLEAN);
		VAR pos, a, b : LONGINT; ch : AosTexts.Char32;
			selectionText : AosTexts.Text;
			from, to : AosTexts.TextPosition;
		BEGIN
			IF (AosInputs.Alt * currentFlags # {}) & (0 IN keys) THEN
				text.AcquireWrite;
				IF AosTexts.GetLastSelection(selectionText, from, to) THEN
					selectionText.AcquireWrite;
					a := Utilities.Min(from.GetPosition(), to.GetPosition());
					b := Utilities.Max(from.GetPosition(), to.GetPosition());
		
					tv.ViewToTextPos(x, y, pos);
					utilreader.SetPosition(pos);
					utilreader.ReadCh(ch);
					IF utilreader.cstyle # NIL THEN
						handled := TRUE;
						selectionText.SetCharacterStyle(a, b - a, utilreader.cstyle);
					ELSIF utilreader.attributes # NIL THEN
						handled := TRUE;
						selectionText.SetAttributes(a, b - a, utilreader.attributes.Clone())
					END;
					IF utilreader.pstyle # NIL THEN
						selectionText.SetParagraphStyle(a, b - a, utilreader.pstyle);
					END;
					selectionText.ReleaseWrite
				END;
				text.ReleaseWrite
			END
		END MousePressed;
		
		PROCEDURE KeyPressed*(ucs : LONGINT; flags : SET; VAR keySym : LONGINT; VAR handled : BOOLEAN);
		BEGIN
			handled := TRUE;
			currentFlags := flags;
			tv.SetFlags(flags);
			IF readOnly.Get() THEN RETURN END;
			IF AosInputs.Release IN flags THEN RETURN END;
			text.AcquireWrite;
			(* relaying the navigation keys to the view *)
			IF keySym = 14H THEN (* Ctrl-T *)
				text.CheckHealth
			ELSIF keySym = 01H THEN (* Ctrl-A *)
				tv.SelectAll
			ELSIF keySym = 03H THEN (* Ctrl-C *)
				tv.CopySelection
			ELSIF keySym = 19H THEN (* Ctrl-Y *)
				IF undoMgr # NIL THEN 
					undoMgr.Redo
				END
			ELSIF keySym = 1AH THEN (* Ctrl-Z *)
				IF undoMgr # NIL THEN 
					undoMgr.Undo
				END			
			ELSIF keySym = 0FF09H THEN (* Tab *)				
			      InsertChar(AosTexts.TabChar)
 			ELSIF (keySym = 0FF63H) & (flags * AosInputs.Ctrl # {}) THEN  (*Ctrl Insert *) 
 				tv.CopySelection
			ELSIF keySym = 0FF51H THEN (* Cursor Left *)
				IF flags * AosInputs.Alt # {} THEN IndentLeft
				ELSE tv.CursorLeft(flags * AosInputs.Ctrl # {}, flags * AosInputs.Shift # {})
				END
			ELSIF keySym = 0FF53H THEN (* Cursor Right *)
				IF flags * AosInputs.Alt # {} THEN IndentRight
				ELSE tv.CursorRight(flags * AosInputs.Ctrl # {}, flags * AosInputs.Shift # {})
				END
			ELSIF keySym = 0FF54H THEN (* Cursor Down *)
				tv.CursorDown(flags * AosInputs.Shift # {})
			ELSIF keySym = 0FF52H THEN (* Cursor Up *)
				tv.CursorUp(flags * AosInputs.Shift # {})
			ELSIF keySym = 0FF56H THEN (* Page Down *)
				tv.PageDown(flags * AosInputs.Shift # {})
			ELSIF keySym = 0FF55H THEN (* Page Up *)
				tv.PageUp(flags * AosInputs.Shift # {})
			ELSIF keySym = 0FF50H THEN (* Cursor Home *)
				tv.Home(flags * AosInputs.Ctrl # {}, flags * AosInputs.Shift # {})
			ELSIF keySym = 0FF57H THEN (* Cursor End *)
				tv.End(flags * AosInputs.Ctrl # {}, flags * AosInputs.Shift # {})
			(* end of relay section *)	
			ELSIF keySym =  016H THEN (* Ctrl-V *) Paste
			ELSIF keySym = 018H THEN (* Ctrl-X *) CopySelection; DeleteSelection
			ELSIF keySym = 0FFFFH THEN (* Delete *) Delete(flags)
			ELSIF keySym = 0FF08H THEN (* Backspace *) Backspace(flags * AosInputs.Ctrl # {})
			ELSIF keySym = 0FF0DH THEN (* CR *) Enter(flags);
			ELSIF (keySym = 0FF63H) & (flags * AosInputs.Shift # {}) THEN  (* Shift Insert *) Paste 
			ELSIF (keySym = 0FF1BH) THEN onEscape.Call(NIL); FocusNext (* Escape *)
			ELSIF (keySym = 00020H) & (flags * AosInputs.Ctrl # {}) & allowIME (* Ctrl-Space *)  THEN
				IF ime = NIL THEN ime := WMInputMethods.GetIME("");
					IF ime # NIL THEN	
						text.ReleaseWrite;
						ime.SetCurrentText(text, tv);
						 text.AcquireWrite
					END
				ELSE ime := NIL
				END
			ELSE
				IF ((flags * AosInputs.Ctrl = {})) & allowIME & (ime # NIL) THEN
					ime.KeyEvent(ucs, flags, keySym)
				ELSE
					macroData.handled := FALSE;
					macroData.flags := flags;
					macroData.keySym := keySym;
					macroData.text := text;
					macroData.cursor := tv.cursor;
					macros.Call(macroData);
					IF ~macroData.handled THEN 
						IF ucs > 26 THEN InsertChar(ucs) END
					END
				END
			END;
			text.ReleaseWrite
		END KeyPressed;
		
		PROCEDURE GetAsString*(VAR x : ARRAY OF CHAR);
		BEGIN
			AosTextUtilities.TextToStr(text, x)
		END GetAsString;
		
		(** Set UTF8 string as text. (Intended for single line case) *)
		PROCEDURE SetAsString*(x : ARRAY OF CHAR);
		BEGIN
			text.AcquireWrite;
			text.Delete(0, text.GetLength());
			AosTextUtilities.StrToText(text, 0, x);
			text.ReleaseWrite
		END SetAsString;
		
		PROCEDURE Finalize;
		BEGIN
			Finalize^;
			IF ime # NIL THEN ime.Hide END;
			IF tv # NIL THEN tv.Finalize; END;
		END Finalize;
	
	END Editor;
	
VAR multiLineProto*, readOnlyProto*, allowScrollbarsProto* : WMProperties.BooleanProperty;
	GSonEnter, GSonEnterInfo : String;
	GSonEscape, GSonEscapeInfo : String;
	GSmacros, GSmacrosInfo : String;
	
PROCEDURE Init;
BEGIN
	GSonEnter := Utilities.NewString("onEnter");
	GSonEnterInfo := Utilities.NewString("called after the Enter key is pressed in the editor");
	GSonEscape := Utilities.NewString("onEscape");
	GSonEscape := Utilities.NewString("called when the Escape key is pressed in the editor");
	GSonEnter := Utilities.NewString("macros");
	GSonEnterInfo := Utilities.NewString("must be handled directly without queuing, text has writelock, may not trap");
END Init;

PROCEDURE InitPrototypes;
BEGIN
	NEW(multiLineProto, NIL, Utilities.NewString("multiLine"), NIL); multiLineProto.Set(TRUE);
	NEW(readOnlyProto, NIL, Utilities.NewString("readOnly"), NIL); readOnlyProto.Set(FALSE);
	NEW(allowScrollbarsProto, NIL, Utilities.NewString("allowScrollbars"), NIL); allowScrollbarsProto.Set(TRUE);
END InitPrototypes;


PROCEDURE EditFactory*(par: PTR): PTR;
VAR e : Editor;
BEGIN
	NEW(e); RETURN e
END EditFactory;

(* Register generator procedures *)
PROCEDURE Register;
BEGIN
	WMComponents.registry.RegisterElement("Editor", EditFactory);
END Register;

(* Cleanup on module free *)
PROCEDURE Cleanup;
BEGIN
	WMComponents.registry.UnregisterElement("Editor");
END Cleanup;

BEGIN
	Register;
	Init;
	InitPrototypes;
	AosModules.InstallTermHandler(Cleanup)
END WMEditors.

