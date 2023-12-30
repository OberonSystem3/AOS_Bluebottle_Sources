MODULE WMDialogs;	(** AUTHOR "TF"; PURPOSE "Standard dialogs"; *)
(**
 * History:
 *
 *	22.03.2007	Added LoginDlg & UserInfoDlg (provided by SAGE), dialog resizing improved, DefaultPos returns center position (staubesv)
 *)
 
IMPORT
	AosOut, Utilities, 
	WMComponents, WMStandardComponents,
	WMRectangles, WMGraphics,
	WMEditors, WMWindowManager, AosTexts;

CONST
	ResDialogFailure* = - 1;
	ResOk* = 0;
	ResNo* = 1;
	ResAbort* = 2;
	ResYes* = 4;
	ResAll* = 5;
	ResNever* = 6;
	ResIgnore* = 7;

	OkBtnId* = "OkBtn";
	AbortBtnId* = "AbortBtn";
	NoBtnId* = "NoBtn";
	YesBtnId* = "YesBtn";
	AllBtnId* = "AllBtn";
	NeverBtnId* = "NeverBtn";
	IgnoreBtnId* = "IgnoreBtn";
	
	ButtonWidth* = 60;
	LineHeight* = 30; (* Height of buttons, labels and editors *)
	
	(* Initial width and height of dialogs *)
	QueryStringWidth = 350;
	QueryStringHeight = 100;
	
	MessageWidth = 350;
	MessageHeight = 100;
	
	LoginWidth = 12 * 18;
	LoginHeight = 3 * LineHeight + 30;
	
	UserInfoWidth = 400;
	UserInfoHeight = 240;

TYPE

	Dialog* = OBJECT(WMComponents.FormWindow)
	VAR 
		result*, x*, y* : LONGINT;
		errors* : BOOLEAN;
		
		PROCEDURE Show*;
		BEGIN 
			result := ResDialogFailure; 
			manager := WMWindowManager.GetDefaultManager();
			manager.Add(x, y, SELF, {WMWindowManager.FlagFrame});
			manager.SetFocus(SELF); 
			BEGIN {EXCLUSIVE}
				AWAIT(result >= 0)
			END;	
			manager.Remove(SELF);
		END Show;
		
		PROCEDURE Close*;
		BEGIN {EXCLUSIVE} 
			result := ResAbort;
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
		
		PROCEDURE Ignore*(sender, data:PTR);
		BEGIN {EXCLUSIVE}
			result := ResIgnore
		END Ignore;		
		
		PROCEDURE WireError*(detectedBy, msg: ARRAY OF CHAR);
		BEGIN
			errors := TRUE;
			AosOut.String("WMDialogs - Wiring error : "); AosOut.String(detectedBy); AosOut.String(" - "); AosOut.String(msg); AosOut.Ln
		END WireError;	
	END Dialog;
	
TYPE
	
	(** Open a query string dialog *)
	QueryStringDlg* = OBJECT (Dialog)
	VAR 
		edit : WMEditors.Editor; 
		content : WMComponents.VisualComponent;
		ok, abort : WMStandardComponents.Button;
		
		PROCEDURE &New;
		BEGIN
			errors := FALSE;
			content := CreateDialog();
			WireDialog;
			Init(QueryStringWidth, QueryStringHeight, FALSE);
			SetContent(content);
			IF edit # NIL THEN edit.SetFocus; edit.SetFocus; END;
		END New;
		
		PROCEDURE CreateDialog() : WMComponents.VisualComponent;
		VAR 
			line, panel : WMStandardComponents.Panel;
			manager : WMWindowManager.WindowManager;
			windowStyle : WMWindowManager.WindowStyle;
		BEGIN
			manager := WMWindowManager.GetDefaultManager();
			windowStyle := manager.GetStyle();
			
			panel := NewPanel(windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			panel.takesFocus.Set(FALSE);
			
			(* Input *)
			edit := NewEditor("Input", windowStyle.fgColor, windowStyle.bgColor, WMComponents.AlignTop, 0, LineHeight);
			edit.bearing.Set(WMRectangles.MakeRect(10, 10, 10, 10));
			panel.AddContent(edit);
			
			(* Buttons *)
			line := NewPanel(windowStyle.bgColor, WMComponents.AlignBottom, 0, LineHeight);
			panel.AddContent(line);

			abort := InstantiateButton(AbortBtnId, "Abort"); line.AddContent(abort);
			abort.bounds.SetWidth(ButtonWidth); abort.alignment.Set(WMComponents.AlignRight);
			
			ok := InstantiateButton(OkBtnId, "Ok"); line.AddContent(ok); 
			ok.bounds.SetWidth(ButtonWidth); ok.alignment.Set(WMComponents.AlignRight);
			
			RETURN panel;
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
	
TYPE
	
	(** Generic Message Dialog  *)
	MessageDlg* =OBJECT(Dialog)
	VAR 
		buttons : SET;
		msg : WMEditors.Editor; ok, abort, no, yes, all, never: WMStandardComponents.Button;
		content : WMComponents.VisualComponent;
	
		PROCEDURE &New(buttons : SET);
		BEGIN
			errors := FALSE;
			SELF.buttons := buttons;
			CreateDialog;
			WireDialog;
			Init(MessageWidth, MessageHeight, FALSE);
			SetContent(content)
		END New;
	
		PROCEDURE CreateDialog;
		VAR 
			panel, buttonPanel : WMStandardComponents.Panel;
			manager : WMWindowManager.WindowManager;
			windowStyle : WMWindowManager.WindowStyle;
		BEGIN
			manager := WMWindowManager.GetDefaultManager();
			windowStyle := manager.GetStyle();
			
			panel := NewPanel(windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			panel.takesFocus.Set(TRUE);

			NEW(buttonPanel); buttonPanel.bounds.SetHeight(LineHeight); buttonPanel.alignment.Set(WMComponents.AlignBottom);
			panel.AddContent(buttonPanel);
			
			abort := InstantiateButton(AbortBtnId, "Abort"); buttonPanel.AddContent(abort);
			abort.bounds.SetWidth(ButtonWidth); abort.alignment.Set(WMComponents.AlignRight);

			no := InstantiateButton(NoBtnId, "No"); buttonPanel.AddContent(no);
			no.bounds.SetWidth(ButtonWidth); no.alignment.Set(WMComponents.AlignRight);
			
			never := InstantiateButton(NeverBtnId, "Never"); buttonPanel.AddContent(never);
			never.bounds.SetWidth(ButtonWidth); never.alignment.Set(WMComponents.AlignRight);

			all := InstantiateButton(AllBtnId, "All"); buttonPanel.AddContent(all);
			all.bounds.SetWidth(ButtonWidth); all.alignment.Set(WMComponents.AlignRight);
	
			yes := InstantiateButton(YesBtnId, "Yes"); buttonPanel.AddContent(yes);
			yes.bounds.SetWidth(ButtonWidth); yes.alignment.Set(WMComponents.AlignRight);
			
			ok := InstantiateButton(OkBtnId, "Ok"); buttonPanel.AddContent(ok); 
			ok.bounds.SetWidth(ButtonWidth); ok.alignment.Set(WMComponents.AlignRight);
			
			msg := NewEditor("Msg", windowStyle.fgColor, windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			msg.bearing.Set(WMRectangles.MakeRect(10, 10, 10, 10));
			msg.readOnly.Set(TRUE);
			panel.AddContent(msg);

			content := panel;
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

	LoginDlg* = OBJECT (Dialog)
	VAR 
		editUser, editPassword: WMEditors.Editor;
		ok, abort: WMStandardComponents.Button;
		content: WMComponents.VisualComponent;
      
     	 	PROCEDURE &New;
     	 	BEGIN
			errors := FALSE;
			CreateDialog;
			WireDialog;
          		
          		Init(LoginWidth, LoginHeight, FALSE);
			SetContent (content);
          
			IF editUser # NIL THEN editUser.SetFocus; editUser.SetFocus; END;          
		END New;

		PROCEDURE CreateDialog;
		VAR
			line, panel: WMStandardComponents.Panel;
			label : WMStandardComponents.Label;
			manager: WMWindowManager.WindowManager;
			windowStyle: WMWindowManager.WindowStyle;
		CONST
			LabelWidth = 60;
		BEGIN 	
			manager := WMWindowManager.GetDefaultManager ();
			windowStyle := manager.GetStyle ();          
          		
          		panel := NewPanel(windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
          		panel.takesFocus.Set(FALSE);
          
          		(* Username *)
          		line := NewPanel(windowStyle.bgColor, WMComponents.AlignTop, 0, LineHeight);
          		line.bearing.Set(WMRectangles.MakeRect(10, 10, 10, 5));
			line.takesFocus.Set(FALSE);
          		panel.AddContent(line);
          		
          		label := NewLabel("User: ", WMComponents.AlignLeft, LabelWidth, 0);
			label.alignH.Set(WMGraphics.AlignRight);
			label.takesFocus.Set(FALSE);
			line.AddContent(label);
			
			editUser := NewEditor("Login", windowStyle.fgColor, windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			editUser.needsTab.Set(FALSE);
			editUser.takesFocus.Set(TRUE);
			editUser.tv.needsTab.Set(FALSE);
			editUser.tv.takesFocus.Set(TRUE);
			line.AddContent (editUser);
			
			(* Password *)
			line := NewPanel(windowStyle.bgColor, WMComponents.AlignTop, 0, LineHeight);
			line.bearing.Set(WMRectangles.MakeRect(10, 5, 10, 5));
          		line.takesFocus.Set(FALSE);
          		panel.AddContent(line);
          		
          		label := NewLabel("Password: ", WMComponents.AlignLeft, LabelWidth, 0);
			label.alignH.Set (WMGraphics.AlignRight);
			label.takesFocus.Set(FALSE);
			line.AddContent (label);
			
			editPassword := NewEditor("Password", windowStyle.fgColor, windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			editPassword.takesFocus.Set(TRUE);
			editPassword.needsTab.Set(FALSE);
			editPassword.tv.isPassword.Set(TRUE);
			editPassword.tv.needsTab.Set(FALSE);
			line.AddContent (editPassword);
          
          		(* Buttons *)
			line := NewPanel(windowStyle.bgColor, WMComponents.AlignBottom, 0, LineHeight);
			panel.AddContent(line);

			abort := InstantiateButton(AbortBtnId, "Abort");
			abort.bounds.SetWidth(ButtonWidth); abort.alignment.Set(WMComponents.AlignRight);
			line.AddContent (abort);
          		
          		ok := InstantiateButton(OkBtnId, "Ok");
			ok.bounds.SetWidth(ButtonWidth); ok.alignment.Set(WMComponents.AlignRight);
			line.AddContent (ok);
          		
			content := panel
		END CreateDialog;
      
	      	PROCEDURE WireDialog;
		VAR c: WMComponents.Component;
		BEGIN
			c := FindComponent (content, "Login");
			IF (c # NIL) & (c IS WMEditors.Editor) THEN editUser := c (WMEditors.Editor) END;
	          
			IF editUser = NIL THEN
				WireError ("LoginDlg", "Required component 'Login' not found."); RETURN
			END;
	          
			c := FindComponent (content, "Password");
			IF (c # NIL) & (c IS WMEditors.Editor) THEN editPassword := c (WMEditors.Editor) END;
	    
			IF editPassword = NIL THEN
				WireError ("LoginDlg", "Required component 'Password' not found."); RETURN
			END;
	          
			ok := FindButton (content, OkBtnId);
			abort := FindButton (content, AbortBtnId);
			IF ok = NIL THEN WireError ("LoginDlg", "Required component 'Ok' not found."); RETURN END;
			IF abort = NIL THEN WireError ("LoginDlg", "Required component 'Abort' not found."); RETURN END;
	          
			ok.onClick.Add (Ok);
			abort.onClick.Add (Abort);
			editUser.onEnter.Add (Ok);
			editPassword.onEnter.Add (Ok);
	        END WireDialog;
	      
	END LoginDlg;

TYPE
	(** Dialog that allows to get basic User Info *)
	UserInfoDlg* = OBJECT (Dialog)
	VAR
		editShortName, editFullName, editEMail, editPassword, editPasswordConfirm: WMEditors.Editor;
		ok, abort: WMStandardComponents.Button;
		content: WMComponents.VisualComponent;
		
		PROCEDURE &New ();
		BEGIN
			errors := FALSE;
			CreateDialog;
			WireDialog;
						
			Init(UserInfoWidth, UserInfoHeight, FALSE);
			SetContent (content);
			
			IF editShortName # NIL THEN editShortName.SetFocus; editShortName.SetFocus END	
		END New;
		
		PROCEDURE CreateDialog;
		VAR
			line, panel : WMStandardComponents.Panel;
			label : WMStandardComponents.Label;
			manager: WMWindowManager.WindowManager;
			windowStyle: WMWindowManager.WindowStyle;
		CONST
			LabelWidth = 120;
		BEGIN
			manager := WMWindowManager.GetDefaultManager ();
			windowStyle := manager.GetStyle ();			
			
			panel := NewPanel(windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			panel.takesFocus.Set(FALSE);
						
			(* Short Name *)
			line := NewPanel(windowStyle.bgColor, WMComponents.AlignTop, 0, LineHeight);
			line.bearing.Set(WMRectangles.MakeRect(10, 10, 10, 5));
			panel.AddContent(line);
			
			label := NewLabel("Short Name: ", WMComponents.AlignLeft, LabelWidth, 0);
			label.alignH.Set(WMGraphics.AlignRight);
			line.AddContent(label);
		
			editShortName := NewEditor("ShortName", windowStyle.fgColor, windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			line.AddContent (editShortName);

			(* Full Name *)
			line := NewPanel(windowStyle.bgColor, WMComponents.AlignTop, 0, LineHeight);
			line.bearing.Set(WMRectangles.MakeRect(10, 5, 10, 5));
			panel.AddContent(line);
			
			label := NewLabel("Full Name: ", WMComponents.AlignLeft, LabelWidth, 0); 
			label.alignH.Set (WMGraphics.AlignRight);
			line.AddContent (label);
			
			editFullName := NewEditor("FullName", windowStyle.fgColor, windowStyle.bgColor, WMComponents.AlignClient, 0, 0);			
			line.AddContent (editFullName);
			
			(* E-Mail *)
			line := NewPanel(windowStyle.bgColor, WMComponents.AlignTop, 0, LineHeight);
			line.bearing.Set(WMRectangles.MakeRect(10, 5, 10, 5));
			panel.AddContent(line);
			
			label := NewLabel("E-Mail: ", WMComponents.AlignLeft, LabelWidth, 0); 
			label.alignH.Set (WMGraphics.AlignRight);
			line.AddContent (label);
			
			editEMail := NewEditor("EMail", windowStyle.fgColor, windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			line.AddContent (editEMail);
			
			(* Password *)
			line := NewPanel(windowStyle.bgColor, WMComponents.AlignTop, 0, LineHeight);
			line.bearing.Set(WMRectangles.MakeRect(10, 5, 10, 5));
			panel.AddContent(line);
			
			label := NewLabel("Password: ", WMComponents.AlignLeft, LabelWidth, 0); 
			label.alignH.Set (WMGraphics.AlignRight);
			line.AddContent (label);
			
			editPassword := NewEditor("Password", windowStyle.fgColor, windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			editPassword.tv.isPassword.Set (TRUE);
			line.AddContent (editPassword);
			
			(* Password Confirm *)
			line := NewPanel(windowStyle.bgColor, WMComponents.AlignTop, 0, LineHeight);
			line.bearing.Set(WMRectangles.MakeRect(10, 5, 10, 5));
			panel.AddContent(line);
			
			label := NewLabel("Password Confirm: ", WMComponents.AlignLeft, LabelWidth, 0); 
			label.alignH.Set (WMGraphics.AlignRight);
			line.AddContent (label);
			
			editPassword := NewEditor("PasswordConfirm", windowStyle.fgColor, windowStyle.bgColor, WMComponents.AlignClient, 0, 0);
			editPassword.tv.isPassword.Set (TRUE);
			line.AddContent (editPassword);
			
			(* Buttons *)
			line := NewPanel(windowStyle.bgColor, WMComponents.AlignBottom, 0, LineHeight);
			panel.AddContent(line);
						
			abort := InstantiateButton (AbortBtnId, "Abort"); line.AddContent (abort);
			abort.bounds.SetWidth (ButtonWidth); abort.alignment.Set (WMComponents.AlignRight);
			
			ok := InstantiateButton (OkBtnId, "Ok"); line.AddContent (ok); 
			ok.bounds.SetWidth (ButtonWidth); ok.alignment.Set (WMComponents.AlignRight);
			
			content := panel
		END CreateDialog;
		
		PROCEDURE WireDialog;
		VAR c: WMComponents.Component;
		BEGIN
			c := FindComponent (content, "FullName"); 
			IF (c # NIL) & (c IS WMEditors.Editor) THEN editFullName := c (WMEditors.Editor) END;
			
			IF editFullName = NIL THEN
				WireError ("UserInfoDlg", "Required component 'FullName' not found."); RETURN
			END;

			c := FindComponent (content, "EMail"); 
			IF (c # NIL) & (c IS WMEditors.Editor) THEN editEMail := c (WMEditors.Editor) END;
			
			IF editPassword = NIL THEN
				WireError ("UserInfoDlg", "Required component 'EMail' not found."); RETURN
			END;
			
			c := FindComponent (content, "Password"); 
			IF (c # NIL) & (c IS WMEditors.Editor) THEN editPassword := c (WMEditors.Editor) END;
			
			IF editPassword = NIL THEN
				WireError ("UserInfoDlg", "Required component 'Password' not found."); RETURN
			END;
			
			c := FindComponent (content, "PasswordConfirm"); 
			IF (c # NIL) & (c IS WMEditors.Editor) THEN editPasswordConfirm := c (WMEditors.Editor) END;
			
			IF editPasswordConfirm = NIL THEN
				WireError ("UserInfoDlg", "Required component 'PasswordConfirm' not found."); RETURN
			END;
			
			ok := FindButton (content, OkBtnId); 
			abort := FindButton (content, AbortBtnId); 
			IF ok = NIL THEN WireError ("UserInfoDlg", "Required component 'Ok' not found."); RETURN END;
			IF abort = NIL THEN WireError ("UserInfoDlg", "Required component 'Abort' not found."); RETURN END;
			
			ok.onClick.Add (Ok);
			abort.onClick.Add (Abort);
			editPasswordConfirm.onEnter.Add (Ok);
		END WireDialog;

	END UserInfoDlg;
	
TYPE

	MiniStringInput*  = OBJECT (WMComponents.FormWindow)
	VAR 
		edit : WMEditors.Editor;
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
	
(** Helper procedures *)

PROCEDURE NewPanel(fillColor, alignment, width, height : LONGINT) : WMStandardComponents.Panel;
VAR panel : WMStandardComponents.Panel;
BEGIN
	NEW(panel); panel.alignment.Set(alignment); panel.bounds.SetExtents(width, height);
	panel.fillColor.Set(fillColor);
	RETURN panel;
END NewPanel;

PROCEDURE NewLabel*(caption : ARRAY OF CHAR; alignment, width, height : LONGINT) : WMStandardComponents.Label;
VAR label : WMStandardComponents.Label;
BEGIN
	NEW(label); label.alignment.Set(alignment); label.bounds.SetExtents(width, height);
	label.caption.SetAOC(caption);
	RETURN label;
END NewLabel;

PROCEDURE NewEditor*(uid : ARRAY OF CHAR; textColor, textBgColor, alignment, width, height : LONGINT) : WMEditors.Editor;
VAR editor : WMEditors.Editor;
BEGIN
	NEW(editor); editor.uid.SetAOC(uid);
	editor.alignment.Set(alignment); editor.bounds.SetExtents(width, height);
	editor.tv.defaultTextColor.Set(textColor);
	editor.tv.defaultTextBgColor.Set(textBgColor);
	editor.multiLine.Set (FALSE);
	editor.tv.borders.Set (WMRectangles.MakeRect(5, 2, 3, 2));
	editor.tv.showBorder.Set (TRUE);
	RETURN editor;
END NewEditor;
	
(** Exported for implementation of Dialog subclasses *)
	
PROCEDURE InstantiateButton*(uid, caption : ARRAY OF CHAR) : WMStandardComponents.Button;
VAR b : WMStandardComponents.Button; 
BEGIN
	NEW(b); b.caption.SetAOC(caption); 
	b.uid.SetAOC(uid); 
	RETURN b
END InstantiateButton;
	
PROCEDURE FindComponent*(c : WMComponents.Component; id : ARRAY OF CHAR) : WMComponents.Component;
BEGIN
	RETURN c.FindByUID(Utilities.NewString(id))
END FindComponent;

PROCEDURE FindButton*(c : WMComponents.Component; id : ARRAY OF CHAR) : WMStandardComponents.Button;
VAR tc : WMComponents.Component;
BEGIN
	tc := c.FindByUID(Utilities.NewString(id));
	IF (tc # NIL) & (tc IS WMStandardComponents.Button) THEN RETURN tc(WMStandardComponents.Button) END;
	RETURN NIL
END FindButton;

(** Given the width and height of a visual components or window, calculate the center position (x, y) *)
PROCEDURE DefaultPos*(VAR x, y : LONGINT; width, height : LONGINT);
VAR manager : WMWindowManager.WindowManager;
	vp : WMWindowManager.ViewPort;
	s : WMWindowManager.WindowStyle;
BEGIN
	manager := WMWindowManager.GetDefaultManager();
	vp := WMWindowManager.GetDefaultView();
	s := manager.GetStyle();
	x := (ENTIER (vp.range.r - vp.range.l) - width) DIV 2;
	y := (ENTIER (vp.range.b - vp.range.t) - height) DIV 2;
	IF s # NIL THEN y := y +  s.th END;
END DefaultPos;


(** Open a string query dialog at position x, y with title caption and default value string. 
	Return ResOk or ResAbort. If res is ResOk string contains the utf8 string. String is not changed if
	res is ResAbort *)
PROCEDURE QueryStringXY*(x, y : LONGINT; VAR caption : ARRAY OF CHAR; VAR string : ARRAY OF CHAR) : LONGINT;
VAR qsd : QueryStringDlg;
BEGIN
	NEW(qsd); 
	IF ~qsd.errors THEN
		qsd.SetTitle(Utilities.NewString(caption)); qsd.edit.SetAsString(string); qsd.edit.tv.SelectAll();
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
	DefaultPos(x, y, QueryStringWidth, QueryStringHeight);
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
		qsd.SetTitle(Utilities.NewString(caption)); qsd.edit.tv.isPassword.Set(TRUE); qsd.edit.SetAsString(string);  qsd.edit.tv.SelectAll();
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
	DefaultPos(x, y, QueryStringWidth, QueryStringHeight);
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
	DefaultPos(x, y, MessageWidth, MessageHeight);
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
	DefaultPos(x, y, MessageWidth, MessageHeight);
	RETURN TextMessageXY(x, y, caption, text, buttons)
END TextMessage;

PROCEDURE QueryLoginXY*(x, y : LONGINT; caption : ARRAY OF CHAR; VAR login, password : ARRAY OF CHAR) : LONGINT;
VAR ld : LoginDlg;
BEGIN
	NEW(ld);
	IF ~ld.errors THEN
		ld.SetTitle(Utilities.NewString(caption));
		ld.editUser.SetAsString(login); ld.editUser.tv.SelectAll();
		ld.x := x; ld.y := y; ld.Show();
		IF ld.result = ResOk THEN
			ld.editUser.GetAsString(login);
			ld.editPassword.GetAsString(password);
		END;
		RETURN ld.result
	ELSE RETURN ResDialogFailure;
	END;	
END QueryLoginXY;

PROCEDURE QueryLogin*(caption: ARRAY OF CHAR; VAR login, password: ARRAY OF CHAR) : LONGINT;
VAR x, y : LONGINT;
BEGIN
	DefaultPos(x, y, LoginWidth, LoginHeight);
	RETURN QueryLoginXY(x, y, caption, login, password);
END QueryLogin;


(** Open a user info query dialog at center of default viewport with title caption.. 
	Return ResOk or ResAbort. If res is ResOk string contains the utf8 string. String is not changed if
	res is ResAbort *)
PROCEDURE QueryUserInfoXY*(x, y : LONGINT; 
	caption: ARRAY OF CHAR; VAR shortName, fullName, eMail, password, passwordConfirm: ARRAY OF CHAR) : LONGINT;
VAR
	uid: UserInfoDlg;
BEGIN
	NEW(uid); 
	IF ~uid.errors THEN
		uid.SetTitle(Utilities.NewString(caption));
		uid.x := x; uid.y := y; uid.Show();
		IF uid.result = ResOk THEN
			uid.editShortName.GetAsString (shortName);
			uid.editFullName.GetAsString (fullName);
			uid.editEMail.GetAsString (eMail);
			uid.editPassword.GetAsString (password);
			uid.editPasswordConfirm.GetAsString (passwordConfirm);
		END;
		RETURN uid.result
	ELSE RETURN ResDialogFailure
	END
END QueryUserInfoXY;

PROCEDURE QueryUserInfo*(caption : ARRAY OF CHAR; VAR shortName, fullName, eMail, password, passwordConfirm : ARRAY OF CHAR) : LONGINT;
VAR x, y : LONGINT;
BEGIN
	DefaultPos(x, y, UserInfoWidth, UserInfoHeight);
	RETURN QueryUserInfoXY(x, y, caption, shortName, fullName, eMail, password, passwordConfirm);
END QueryUserInfo;

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

PROCEDURE TestLogin*(par : ANY) : ANY;
VAR user, password : ARRAY 128 OF CHAR; res : LONGINT; 
BEGIN
	user := "TestUser";
	res := QueryLogin("Test login dialog", user, password);
	IF res = ResOk THEN
		AosOut.String("OK (User: "); AosOut.String(", login: "); AosOut.String(user);
		AosOut.String(", password: "); AosOut.String(password); AosOut.String(")");
	ELSE
		AosOut.String("res = "); AosOut.Int(res, 0);
	END;
	AosOut.Ln;
	RETURN NIL
END TestLogin;

PROCEDURE TestUserInfo*(par : ANY) : ANY;
VAR shortName, fullName, eMail, password, passwordConfirm : ARRAY 128 OF CHAR; res : LONGINT; 
BEGIN
	res := QueryUserInfo("Test user info dialog", shortName, fullName, eMail, password, passwordConfirm);
	IF res = ResOk THEN
		AosOut.String("OK (Short Name: "); AosOut.String(shortName);
		AosOut.String(", Full Name: "); AosOut.String(fullName);
		AosOut.String(", E-Mail: "); AosOut.String(eMail);
		AosOut.String(", Password: "); AosOut.String(password);
		AosOut.String(", Password confirm: "); AosOut.String(passwordConfirm);
		AosOut.String(")");
	ELSE
		AosOut.String("res = "); AosOut.Int(res, 0);
	END;
	AosOut.Ln;
	RETURN NIL
END TestUserInfo;

END WMDialogs.

S.Free WMDialogs ~
WMDialogs.Test ~
WMDialogs.TestMsg ~
WMDialogs.TestLogin ~
WMDialogs.TestUserInfo ~