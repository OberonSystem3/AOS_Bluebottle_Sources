MODULE WMUnicodeIME; (** AUTHOR "tf, pl"; PURPOSE "Unicode input mode editor"; *)

IMPORT
	AosOut, AosModules, Utilities, AosFS, AosIO, AosTexts, AosTextUtilities, UTF8Strings,
	WMInputMethods, WMMessages, 
	(* visual part *)
	WMRectangles, WMWindowManager, WMComponents, WMStandardComponents, WMTextView, WMEditors, 
	WMGraphics, WMStringGrids, WMGrids;

CONST
	ResOk = 0;
	ResAbort = -1; 
	CmdHide = 1;

TYPE
	IMEWindow*  = OBJECT (WMComponents.FormWindow)
	VAR edit : WMEditors.Editor;
		curEditStr : ARRAY 64 OF CHAR;
		uniChar : WMStandardComponents.Label;
		font : WMGraphics.Font;

		ime : IME;

		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			ep, sb, sr, gb, gr, d : WMStandardComponents.Panel;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(200, 104); panel.fillColor.Set(0); panel.takesFocus.Set(TRUE);
			
			(* right shadow *)
			NEW(sr); sr.bounds.SetWidth(4); sr.alignment.Set(WMComponents.AlignRight); sr.fillColor.Set(0);
			panel.AddContent(sr);

			NEW(d); d.bounds.SetHeight(4); d.alignment.Set(WMComponents.AlignTop); d.fillColor.Set(0);
			sr.AddContent(d);
			
			NEW(gr); gr.alignment.Set(WMComponents.AlignClient); gr.fillColor.Set(080H); 
			sr.AddContent(gr);
						
			(* bottom shadow *)
			NEW(sb); sb.bounds.SetHeight(4); sb.alignment.Set(WMComponents.AlignBottom); sb.fillColor.Set(0);
			panel.AddContent(sb);
			
			NEW(d); d.bounds.SetWidth(4); d.alignment.Set(WMComponents.AlignLeft); d.fillColor.Set(0);
			sb.AddContent(d);
			
			NEW(gb); gb.alignment.Set(WMComponents.AlignClient); gb.fillColor.Set(080H); 
			sb.AddContent(gb);
			
			(* edit panel *)
			NEW(ep); ep.alignment.Set(WMComponents.AlignClient); ep.fillColor.Set(0DDDD00EEH);
			panel.AddContent(ep);

			NEW(edit); edit.bounds.SetHeight(20); edit.alignment.Set(WMComponents.AlignTop); edit.tv.showBorder.Set(TRUE);
			edit.tv.defaultTextBgColor.Set(0);
			
			edit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 2, 2));
			edit.allowIME := FALSE;
			edit.multiLine.Set(FALSE);
			ep.AddContent(edit);

			(* preview Unicode Char *)
			NEW(uniChar); uniChar.alignment.Set(WMComponents.AlignClient);
			uniChar.textColor.Set(0000000FFH); uniChar.alignH.Set(WMGraphics.AlignCenter);
			uniChar.caption.SetAOC(""); uniChar.alignV.Set(WMGraphics.AlignTop);
			ep.AddContent(uniChar);

			RETURN panel
		END CreateForm;

		PROCEDURE &New(ime : IME; x, y :LONGINT; text : ARRAY OF CHAR);
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			vc := CreateForm();
			SELF.ime := ime;
			edit.onEnter.Add(Ok);
			edit.tv.SetExtKeyEventHandler(EditKeyPressed);
			
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), TRUE);
			SetContent(vc);
			
			font := WMGraphics.GetFont("Cyberbit", 60, {});
			IF font # NIL THEN uniChar.SetFont(font) END;			
			
			manager := WMWindowManager.GetDefaultManager();
			manager.Add(x, y, SELF, {});
			manager.SetFocus(SELF);
			edit.SetAsString(text);
			edit.SetFocus;
			edit.text.onTextChanged.Add(TextChanged);
		END New;		
		
		PROCEDURE EditKeyPressed(ucs : LONGINT; flags : SET; VAR keySym : LONGINT; VAR handled : BOOLEAN);
		BEGIN
			handled := TRUE;
			IF keySym = 20H THEN (* space *)
				IF curEditStr = "" THEN ScheduleHide
				ELSE WriteSelected;
					(* private change, dont need to evaluate anything *)
					edit.text.onTextChanged.Remove(TextChanged);
					edit.SetAsString("");
					curEditStr := "";
					edit.text.onTextChanged.Add(TextChanged);
					ClearSelection
				END
			ELSIF keySym = 0FF08H THEN
				IF curEditStr = "" THEN ScheduleHide
				ELSE edit.KeyPressed(ucs, flags, keySym, handled)
				END
			ELSIF keySym = 0FF54H THEN
			ELSIF (keySym >= 48) & (keySym <= 57) THEN
				edit.KeyPressed(ucs, flags, keySym, handled)
			ELSIF keySym = 0FF0DH THEN (* enter *)
				edit.KeyPressed(ucs, flags, keySym, handled)
			END;
		END EditKeyPressed;
		
		PROCEDURE ScheduleHide;
		VAR msg : WMMessages.Message;
		BEGIN
			msg.msgType := WMMessages.MsgExt;
			msg.ext := SELF;
			IF ~sequencer.Add(msg) THEN AosOut.String("IME Editor out of sync") END;
		END ScheduleHide;
		
		PROCEDURE WriteSelected;
		VAR uni : Utilities.String;
		BEGIN
			uni := uniChar.caption.Get();
			ime.AddString(uni^)		
		END WriteSelected;

		PROCEDURE ClearSelection;
		BEGIN
			uniChar.caption.SetAOC("")
		END ClearSelection;
		
		PROCEDURE Ok*(sender, data:PTR);
		BEGIN
			WriteSelected;
			ScheduleHide
		END Ok;
		
		PROCEDURE TextChanged*(sender, data:PTR);
		VAR ch, no : LONGINT; str : ARRAY 2 OF CHAR;
			charString : ARRAY 16 OF CHAR;
			
		BEGIN
			(* avoid recursion *)
			edit.text.onTextChanged.Remove(TextChanged);
			
			(* find representation for the unicode *)
			edit.GetAsString(curEditStr);
			IF Utilities.Length(curEditStr) > 8 THEN
				uniChar.caption.SetAOC("overflow");
			ELSE
				uniChar.caption.SetAOC("");
				Utilities.StrToInt(curEditStr, ch);
				
				no := 0;
				IF UTF8Strings.EncodeChar(ch, charString, no) THEN
					uniChar.caption.SetAOC(charString)
				ELSE
					uniChar.caption.SetAOC("error")
				END;
				
			END;

			edit.text.onTextChanged.Add(TextChanged)
		END TextChanged;
		
		PROCEDURE FocusLost;
		BEGIN
			FocusLost^;
			ScheduleHide
		END FocusLost;
		
		PROCEDURE FocusGot;
		BEGIN
			manager.SetFocus(SELF)
		END FocusGot;		
		
		PROCEDURE Hide;
		BEGIN
			manager := WMWindowManager.GetDefaultManager();
			manager.Remove(SELF);
			ime.w := NIL;
		END Hide;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) THEN
				IF (x.ext = SELF) THEN Hide
				END
			ELSE Handle^(x)
			END
		END Handle;
		
	END IMEWindow;

TYPE
	IME* = OBJECT(WMInputMethods.IME)
	VAR name : Utilities.String;
		w : IMEWindow;
	
		PROCEDURE &Init;
		BEGIN
			name := Utilities.NewString("WMUnicodeIME");
		END Init;
		
		PROCEDURE GetName*() : Utilities.String;
		BEGIN
			RETURN name
		END GetName;	
					
		PROCEDURE SetCurrentText*(text : AosTexts.Text; tv : WMTextView.TextView);
		BEGIN
			SELF.text := text;
			SELF.tv := tv
		END SetCurrentText;
		
		PROCEDURE AddString(str : ARRAY OF CHAR);
		BEGIN
			text.AcquireWrite;
			AosTextUtilities.StrToText(text, tv.cursor.GetPosition(), str);
			text.ReleaseWrite
		END AddString;
		
		PROCEDURE InsertChar(ucs : LONGINT);
		VAR buf : ARRAY 2 OF AosTexts.Char32;
		BEGIN
			text.AcquireWrite;
			buf[0] := ucs; buf[1] := 0;
			text.InsertUCS32(tv.cursor.GetPosition(), buf);
			text.ReleaseWrite
		END InsertChar;
		
		PROCEDURE KeyEvent*(ucs : LONGINT; flags : SET; keysym : LONGINT);
		VAR x, y, pos : LONGINT; str : ARRAY 8 OF CHAR;
		BEGIN
			IF (ucs >= 48) & (ucs <= 57) THEN
				tv.Acquire;
				text.AcquireRead;
				IF tv.FindScreenPos(tv.cursor.GetPosition(), x, y) THEN END;
				tv.ToWMCoordinates(x, y, x, y);
				text.ReleaseRead;
				tv.Release;
				pos := 0; IF UTF8Strings.EncodeChar(ucs, str, pos) THEN END;
				NEW(w, SELF, x, y, str);
			ELSE InsertChar(ucs)	
			END	
		END KeyEvent;
		
		PROCEDURE Finalize;
		BEGIN
		END Finalize;
		
	END IME;

(* ----------------------------------------- *)


PROCEDURE Install*(par : ANY) : ANY;
VAR ime : IME;
BEGIN
	NEW(ime);
	WMInputMethods.defaultIME := ime;
	RETURN NIL
END Install;

PROCEDURE Cleanup;
BEGIN
	IF WMInputMethods.defaultIME # NIL THEN 
		WMInputMethods.defaultIME(IME).Finalize
	END;
	WMInputMethods.defaultIME := NIL
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMUnicodeIME.

-------------------------------------------------

S.Free WMUnicodeIME ~
WMUnicodeIME.Install ~
