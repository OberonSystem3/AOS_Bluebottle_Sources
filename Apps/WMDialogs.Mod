MODULE WMDialogs;	(** AUTHOR "TF"; PURPOSE "Standard dialogs"; *)

IMPORT
	AosOut,
	WMGraphics, Utilities, 
	WMComponents, WMStandardComponents,
	WMRectangles, 
	WMEditors, WMWindowManager, AosTexts;

CONST
	ResDialogFailure* = - 1;
	ResOk* = 0;
	ResNo* = 1;
	ResAbort* = 2;
	ResYes* = 4;
	ResAll* = 5;
	ResNever* = 6;
	
	ViewPosXOffset = 300;
	ViewPosYOffset = 200;
	
	OkBtnId* = "OkBtn";
	AbortBtnId* = "AbortBtn";
	NoBtnId* = "NoBtn";
	YesBtnId* = "YesBtn";
	AllBtnId* = "AllBtn";
	NeverBtnId* = "NeverBtn";
	
TYPE
	String = Utilities.String;
	Dialog* = OBJECT(WMComponents.FormWindow)
	VAR result*, x*, y* : LONGINT;
		errors* : BOOLEAN;
		
		PROCEDURE Show*;
		BEGIN 
			result := -1; 
			manager := WMWindowManager.GetDefaultManager();
			manager.Add(x, y, SELF, {WMWindowManager.FlagFrame});
			manager.SetFocus(SELF); 
			BEGIN {EXCLUSIVE}
				AWAIT(result >= 0)
			END;	
			manager.Remove(SELF)
		END Show;
		
		PROCEDURE Close();
		BEGIN {EXCLUSIVE}
			result := ResAbort
		END Close;
		
		PROCEDURE Ok*(sender, data:PTR);
		BEGIN {EXCLUSIVE}
			result := ResOk
		END Ok;
		
		PROCEDURE Abort*(sender, data:PTR);
		BEGIN {EXCLUSIVE}
			result := ResAbort
		END Abort;
		
		PROCEDURE No*(sender, data:PTR);
		BEGIN {EXCLUSIVE}
			result := ResNo
		END No;
		
		PROCEDURE Yes*(sender, data:PTR);
		BEGIN {EXCLUSIVE}
			result := ResYes
		END Yes;
		
		PROCEDURE All*(sender, data:PTR);
		BEGIN {EXCLUSIVE}
			result := ResAll
		END All;
		
		PROCEDURE Never*(sender, data:PTR);
		BEGIN {EXCLUSIVE}
			result := ResNever
		END Never;
		
		PROCEDURE WireError(detectedBy, msg: ARRAY OF CHAR);
		BEGIN
			errors := TRUE;
			AosOut.String("WMDialogs - Wiring error : "); AosOut.String(detectedBy); AosOut.String(" - "); AosOut.String(msg); AosOut.Ln
		END WireError;	
	END Dialog;
	
(** Open a query string dialog *)
	QueryStringDlg* = OBJECT (Dialog)
	VAR edit : WMEditors.Editor; ok, abort : WMStandardComponents.Button;
		content : WMComponents.VisualComponent;
		
		PROCEDURE &New;
		BEGIN
			errors := FALSE;
			CreateDialog;
			WireDialog;
			Init(content.bounds.GetWidth(), content.bounds.GetHeight(), FALSE);
			SetContent(content);
			IF edit # NIL THEN edit.SetFocus; edit.SetFocus  END
		END New;
		
		PROCEDURE CreateDialog;
		VAR panel : WMStandardComponents.Panel;
			width, height : LONGINT;
		BEGIN
			width := 350; height := 100;
			NEW(panel); panel.bounds.SetExtents(width, height);
			panel.fillColor.Set(09999FFFFH);
			panel.takesFocus.Set(FALSE);
			NEW(edit); edit.uid.SetAOC("Input");
			
			edit.bounds.Set(WMRectangles.MakeRect(10, 10, width - 10, 40)); panel.AddContent(edit);
			edit.multiLine.Set(FALSE); edit.tv.borders.Set(WMRectangles.MakeRect(5, 2, 3, 2)); edit.tv.showBorder.Set(TRUE);
			
			ok := InstantiateButton(OkBtnId, "Ok"); 
			abort := InstantiateButton(AbortBtnId, "Abort");
			ok.bounds.SetExtents(60, 30); abort.bounds.SetExtents(60, 30);				
			panel.AddContent(ok); panel.AddContent(abort);
			abort.bounds.SetLeft(width - abort.bounds.GetWidth() - 10);
			ok.bounds.SetLeft(width - ok.bounds.GetWidth() - 10 - abort.bounds.GetWidth() - 10);
			ok.bounds.SetTop(height - ok.bounds.GetHeight() - 10); 
			abort.bounds.SetTop(height - abort.bounds.GetHeight() - 10); 
			content := panel
		END CreateDialog;
		
		PROCEDURE WireDialog;
		VAR c : WMComponents.Component;
		BEGIN
			c := FindComponent(content, "Input"); 
			IF (c # NIL) & (c IS WMEditors.Editor) THEN edit := c(WMEditors.Editor) END;
			
			IF edit = NIL THEN  WireError("QueryStringDlg", "Required component 'Input' not found."); RETURN END;
			
			ok := FindButton(content, OkBtnId); 
			abort := FindButton(content, AbortBtnId); 
			IF ok = NIL THEN WireError("QueryStringDlg", "Required component 'Ok' not found."); RETURN END;
			IF abort = NIL THEN WireError("QueryStringDlg", "Required component 'Abort' not found."); RETURN END;
			
			ok.onClick.Add(Ok);
			abort.onClick.Add(Abort);
			edit.onEnter.Add(Ok)
		END WireDialog;
		
	END QueryStringDlg;
	
	(** Generic Message Dialog  *)
	MessageDlg* =OBJECT(Dialog)
	VAR buttons : SET;
			msg : WMEditors.Editor; ok, abort, no, yes, all, never: WMStandardComponents.Button;
			content : WMComponents.VisualComponent;
	
		PROCEDURE &New(buttons : SET);
		BEGIN
			errors := FALSE;
			SELF.buttons := buttons;
			CreateDialog;
			WireDialog;
			Init(content.bounds.GetWidth(), content.bounds.GetHeight(), FALSE);
			SetContent(content)
		END New;
	
		PROCEDURE CreateDialog;
		VAR panel, buttonPanel : WMStandardComponents.Panel;
			width, height : LONGINT;
		CONST BWidth = 60; BHeight = 30;
		BEGIN
			width := 350; height := 150;
			NEW(panel); panel.bounds.SetExtents(width, height); 
			panel.fillColor.Set(09999FFFFH);
			panel.takesFocus.Set(TRUE);
			
			NEW(msg); 
			msg.uid.SetAOC("Msg");
			msg.readOnly.Set(TRUE); msg.tv.borders.Set(WMRectangles.MakeRect(5, 2, 3, 2)); msg.tv.showBorder.Set(TRUE);
			msg.bounds.Set(WMRectangles.MakeRect(10, 10, width - 10, 100)); panel.AddContent(msg);
			
			NEW(buttonPanel); buttonPanel.bounds.SetHeight(BHeight); buttonPanel.alignment.Set(WMComponents.AlignBottom);
			panel.AddContent(buttonPanel);
			ok := InstantiateButton(OkBtnId, "Ok"); buttonPanel.AddContent(ok); 
			ok.bounds.SetWidth(BWidth); ok.alignment.Set(WMComponents.AlignLeft);
			
			yes := InstantiateButton(YesBtnId, "Yes"); buttonPanel.AddContent(yes);
			yes.bounds.SetWidth(BWidth); yes.alignment.Set(WMComponents.AlignLeft);
			
			all := InstantiateButton(AllBtnId, "All"); buttonPanel.AddContent(all);
			all.bounds.SetWidth(BWidth); all.alignment.Set(WMComponents.AlignLeft);
			
			never := InstantiateButton(NeverBtnId, "Never"); buttonPanel.AddContent(never);
			never.bounds.SetWidth(BWidth); never.alignment.Set(WMComponents.AlignLeft);
			
			no := InstantiateButton(NoBtnId, "No"); buttonPanel.AddContent(no);
			no.bounds.SetWidth(BWidth); no.alignment.Set(WMComponents.AlignLeft);
			
			abort := InstantiateButton(AbortBtnId, "Abort"); buttonPanel.AddContent(abort);
			abort.bounds.SetWidth(BWidth); abort.alignment.Set(WMComponents.AlignLeft);
			
			content := panel
		END CreateDialog;
		
		PROCEDURE WireDialog;
		VAR c : WMComponents.Component;
		BEGIN
			c := FindComponent(content, "Msg"); 
			IF (c # NIL) & (c IS WMEditors.Editor) THEN msg := c(WMEditors.Editor) END;
			
			ok := FindButton(content, OkBtnId); 
			no := FindButton(content, NoBtnId); 
			abort := FindButton(content, AbortBtnId); 
			yes := FindButton(content, YesBtnId);
			all := FindButton(content, AllBtnId);
			
			IF msg # NIL THEN
				msg.SetFocus
			ELSE WireError("QueryStringDlg", "Required component 'Input' not found.")
			END;
			
			IF ok # NIL THEN ok.onClick.Add(Ok) END;
			IF abort # NIL THEN abort.onClick.Add(Abort) END;
			IF no # NIL THEN no.onClick.Add(No) END;
			IF yes # NIL THEN yes.onClick.Add(Yes) END;
			IF all # NIL THEN all.onClick.Add(All) END;
			IF never # NIL THEN never.onClick.Add(Never) END;
			
			IF abort # NIL THEN abort.visible.Set(ResAbort IN buttons) END;
			IF no # NIL THEN no.visible.Set(ResNo IN buttons) END;
			IF ok # NIL THEN ok.visible.Set(ResOk IN buttons) END;
			IF yes # NIL THEN yes.visible.Set(ResYes IN buttons) END;
			IF all # NIL THEN all.visible.Set(ResAll IN buttons) END;
			IF never # NIL THEN never.visible.Set(ResNever IN buttons) END;
		END WireDialog;

	END MessageDlg;
	

TYPE
	MiniStringInput*  = OBJECT (WMComponents.FormWindow)
	VAR edit : WMEditors.Editor;
		result : LONGINT;

		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			ep, sb, sr, gb, gr, d : WMStandardComponents.Panel;
		BEGIN
			NEW(panel); panel.bounds.SetExtents(200, 25); panel.fillColor.Set(0); panel.takesFocus.Set(TRUE);
			
			(* bottom shadow *)
			NEW(sb); sb.bounds.SetHeight(4); sb.alignment.Set(WMComponents.AlignBottom); sb.fillColor.Set(0);
			panel.AddContent(sb);
			
			NEW(d); d.bounds.SetWidth(4); d.alignment.Set(WMComponents.AlignLeft); d.fillColor.Set(0);
			sb.AddContent(d);
			
			NEW(gb); gb.alignment.Set(WMComponents.AlignClient); gb.fillColor.Set(080H); 
			sb.AddContent(gb);
			
			(* right shadow *)
			NEW(sr); sr.bounds.SetWidth(4); sr.alignment.Set(WMComponents.AlignRight); sr.fillColor.Set(0);
			panel.AddContent(sr);

			NEW(d); d.bounds.SetHeight(4); d.alignment.Set(WMComponents.AlignTop); d.fillColor.Set(0);
			sr.AddContent(d);
			
			NEW(gr); gr.alignment.Set(WMComponents.AlignClient); gr.fillColor.Set(080H); 
			sr.AddContent(gr);
			

			(* edit panel *)
			NEW(ep); ep.alignment.Set(WMComponents.AlignClient); ep.fillColor.Set(0DDDD00EEH);
			panel.AddContent(ep);

			NEW(edit); edit.alignment.Set(WMComponents.AlignClient); edit.tv.showBorder.Set(TRUE);
			edit.tv.defaultTextBgColor.Set(0);
			edit.tv.borders.Set(WMRectangles.MakeRect(3, 3, 2, 2));
			edit.multiLine.Set(FALSE);
			ep.AddContent(edit);
			RETURN panel
		END CreateForm;

		PROCEDURE &New();
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			vc := CreateForm();
			edit.onEnter.Add(Ok);
			edit.onEscape.Add(Abort);
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), TRUE);
			SetContent(vc);
			manager := WMWindowManager.GetDefaultManager();
		END New;
		
		PROCEDURE Ok*(sender, data:PTR);
		BEGIN {EXCLUSIVE}
			result := ResOk
		END Ok;
	
		PROCEDURE Abort*(sender, data:PTR);
		BEGIN {EXCLUSIVE}
			result := ResAbort
		END Abort;

		PROCEDURE Show*(x, y : LONGINT; VAR text : ARRAY OF CHAR) : LONGINT;
		BEGIN
			result := -1;
			edit.SetAsString(text);
			manager.Add(x, y, SELF, {});
			manager.SetFocus(SELF);
			edit.SetFocus;
			BEGIN {EXCLUSIVE}
				AWAIT(result >= 0)
			END;
			manager.Remove(SELF);
			IF result = ResOk THEN 
				edit.GetAsString(text)
			END;
			RETURN result
		END Show;
		
		PROCEDURE FocusLost;
		BEGIN {EXCLUSIVE}
			result := ResAbort
		END FocusLost;
	
	END MiniStringInput;
	
	
PROCEDURE InstantiateButton(uid, caption : ARRAY OF CHAR) : WMStandardComponents.Button;
VAR b : WMStandardComponents.Button; 
BEGIN
	NEW(b); b.caption.SetAOC(caption); 
	b.uid.SetAOC(uid); 
	RETURN b
END InstantiateButton;
	
PROCEDURE FindComponent(c : WMComponents.Component; id : ARRAY OF CHAR) : WMComponents.Component;
BEGIN
	RETURN c.FindByUID(Utilities.NewString(id))
END FindComponent;

PROCEDURE FindButton(c : WMComponents.Component; id : ARRAY OF CHAR) : WMStandardComponents.Button;
VAR tc : WMComponents.Component;
	s : String;
BEGIN
	tc := c.FindByUID(Utilities.NewString(id));
	IF (tc # NIL) & (tc IS WMStandardComponents.Button) THEN RETURN tc(WMStandardComponents.Button) END;
	RETURN NIL
END FindButton;


(** Open a string query dialog at position x, y with title caption and default value string. 
	Return ResOk or ResAbort. If res is ResOk string contains the utf8 string. String is not changed if
	res is ResAbort *)
PROCEDURE QueryStringXY*(x, y : LONGINT; VAR caption : ARRAY OF CHAR; VAR string : ARRAY OF CHAR) : LONGINT;
VAR qsd : QueryStringDlg;
BEGIN
	NEW(qsd); 
	IF ~qsd.errors THEN
		qsd.SetTitle(Utilities.NewString(caption)); qsd.edit.SetAsString(string);
		qsd.x := x; qsd.y := y; qsd.Show;
		IF qsd.result = ResOk THEN qsd.edit.GetAsString(string) END;
		RETURN qsd.result
	ELSE RETURN ResDialogFailure
	END
END QueryStringXY;

(** Open a string query at default position with title caption and default value string. 
	Return ResOk or ResAbort. If res is ResOk string contains the utf8 string. String is not changed if
	res is ResAbort *)
PROCEDURE QueryString*(caption : ARRAY OF CHAR; VAR string : ARRAY OF CHAR) : LONGINT;
VAR x, y : LONGINT;
BEGIN
	DefaultPos(x, y);
	RETURN QueryStringXY(x, y, caption, string)
END QueryString;


(** Open a string query dialog at position x, y with title caption and default value string. 
	Return ResOk or ResAbort. If res is ResOk string contains the utf8 string. String is not changed if
	res is ResAbort *)
PROCEDURE QueryPasswordXY*(x, y : LONGINT; VAR caption, string : ARRAY OF CHAR) : LONGINT;
VAR qsd : QueryStringDlg;
BEGIN
	NEW(qsd); 	
	IF ~qsd.errors THEN
		qsd.SetTitle(Utilities.NewString(caption)); qsd.edit.tv.isPassword.Set(TRUE); qsd.edit.SetAsString(string);
		qsd.x := x; qsd.y := y; qsd.Show;
		IF qsd.result = ResOk THEN qsd.edit.GetAsString(string) END;
		RETURN qsd.result
	ELSE RETURN ResDialogFailure
	END
END QueryPasswordXY;

(** Open a string query at default position with title caption and default value string. 
	Return ResOk or ResAbort. If res is ResOk string contains the utf8 string. String is not changed if
	res is ResAbort *)
PROCEDURE QueryPassword*(caption : ARRAY OF CHAR; VAR string : ARRAY OF CHAR) : LONGINT;
VAR x, y : LONGINT;
BEGIN
	DefaultPos(x, y);
	RETURN QueryPasswordXY(x, y, caption, string)
END QueryPassword;


(** Open a message dialog at position x, y*)
PROCEDURE MessageXY*(x, y : LONGINT; caption, string : ARRAY OF CHAR; buttons : SET) : LONGINT;
VAR qsd : MessageDlg;
BEGIN
	NEW(qsd, buttons); 	
	IF ~qsd.errors THEN
		qsd.SetTitle(Utilities.NewString(caption)); qsd.msg.SetAsString(string);
		qsd.x := x; qsd.y := y; qsd.Show;
		RETURN qsd.result
	ELSE RETURN ResDialogFailure
	END
END MessageXY;

(** Open a string query at default position with title caption and default value string. 
	Return ResOk or ResAbort. If res is ResOk string contains the utf8 string. String is not changed if
	res is ResAbort *)
PROCEDURE Message*(caption, string : ARRAY OF CHAR; buttons : SET) : LONGINT;
VAR x, y : LONGINT;
BEGIN
	DefaultPos(x, y);
	RETURN MessageXY(x, y, caption, string, buttons)
END Message;


(** Open a string query dialog at position x, y with title caption and default value string. 
	Return ResOk or ResAbort. If res is ResOk string contains the utf8 string. String is not changed if
	res is ResAbort *)
PROCEDURE TextMessageXY*(x, y : LONGINT; VAR caption: ARRAY OF CHAR; text : AosTexts.Text; buttons : SET) : LONGINT;
VAR qsd : MessageDlg;
BEGIN
	NEW(qsd, buttons); 	
	IF ~qsd.errors THEN
		qsd.SetTitle(Utilities.NewString(caption)); qsd.msg.SetText(text);
		qsd.x := x; qsd.y := y; qsd.Show;
		RETURN qsd.result
	ELSE RETURN ResDialogFailure
	END
END TextMessageXY;

(** Open a string query at default position with title caption and default value string. 
	Return ResOk or ResAbort. If res is ResOk string contains the utf8 string. String is not changed if
	res is ResAbort *)
PROCEDURE TextMessage*(caption : ARRAY OF CHAR; text : AosTexts.Text; buttons : SET) : LONGINT;
VAR x, y : LONGINT;
BEGIN
	DefaultPos(x, y);
	RETURN TextMessageXY(x, y, caption, text, buttons)
END TextMessage;

PROCEDURE DefaultPos(VAR x, y : LONGINT);
VAR manager : WMWindowManager.WindowManager;
	view : WMWindowManager.ViewPort;
	s : WMWindowManager.WindowStyle; dy : LONGINT;
BEGIN
	manager := WMWindowManager.GetDefaultManager();
	view := WMWindowManager.GetDefaultView();
	s := manager.GetStyle();
	IF s # NIL THEN dy := s.th ELSE dy := 0 END;
	x := ENTIER(view.range.l) + ViewPosXOffset; y := ENTIER(view.range.t) + dy + ViewPosYOffset;
END DefaultPos;


PROCEDURE Test*(par : PTR): PTR;
VAR bimbo : ARRAY 100 OF CHAR;
BEGIN
	bimbo := "Test";
	AosOut.Int(QueryString("Input", bimbo), 5);
	AosOut.String("Result = "); AosOut.String(bimbo); AosOut.Ln;
	RETURN NIL
END Test;

PROCEDURE TestMsg*(par : PTR): PTR;
BEGIN
	AosOut.Int(Message("Huga", "You should only see the Ok button", {ResOk}), 5);
	AosOut.Int(Message("Huga", "You should only see the Abort button", {ResAbort}), 5);
	AosOut.Int(Message("Huga", "You should only see the No button", {ResNo}), 5);
	AosOut.Int(Message("Huga", "You should see the Ok + Abort  button", {ResOk, ResAbort}), 5);
	AosOut.Int(Message("Huga", "You should see the Ok + Abort + No button", {ResOk, ResNo, ResAbort}), 5);
	RETURN NIL
END TestMsg;

END WMDialogs.


S.Free WMDialogs ~
WMDialogs.Test ~
WMDialogs.TestMsg ~