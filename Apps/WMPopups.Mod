MODULE WMPopups;	(** AUTHOR "BF"; PURPOSE ""; *)

IMPORT
	Standard := WMStandardComponents, WMEvents, WM := WMWindowManager, Base := WMComponents,
	WMMessages, Graphics := WMGraphics;

TYPE
	Popup* = OBJECT (Base.FormWindow)
	
	VAR
		panel : Standard.Panel;
		count : LONGINT;
	
	PROCEDURE&New;
	BEGIN
		NEW(panel);
		panel.fillColor.Set(Graphics.RGBAToColor(255, 255, 255, 255));
		count := 0
	END New;
	
	PROCEDURE Add* (caption : ARRAY OF CHAR; onClickHandler : WMEvents.EventListener);
	VAR b : Standard.Button;
	BEGIN
		NEW(b); b.bounds.SetWidth(100); b.bounds.SetHeight(20); b.caption.SetAOC(caption);
		b.alignment.Set(Base.AlignTop);
		b.onClick.Add(onClickHandler);
		panel.AddContent(b);
		INC(count)
	END Add;
	
	PROCEDURE AddParButton* (caption : ARRAY OF CHAR; onClickHandler : WMEvents.EventListener; par : PTR);
	VAR b : Standard.Button;
	BEGIN
		NEW(b); b.bounds.SetWidth(100); b.bounds.SetHeight(20); b.caption.SetAOC(caption); b.userData := par;
		b.alignment.Set(Base.AlignTop);
		b.onClick.Add(onClickHandler);
		panel.AddContent(b);
		INC(count)
	END AddParButton;
	
	PROCEDURE Popup* (x, y : LONGINT);
	BEGIN
		panel.bounds.SetWidth(100); panel.bounds.SetHeight(count*20);
		Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), FALSE);
		SetContent(panel);
		manager := WM.GetDefaultManager();
		manager.Add(x, y, SELF, {WM.FlagStayOnTop});
		manager.SetFocus(SELF);
	END Popup;
	
	PROCEDURE FocusLost;
	BEGIN
		manager.Remove(SELF)
	END FocusLost;
	
	PROCEDURE FocusGot;
	BEGIN
		manager.SetFocus(SELF)
	END FocusGot;
	
	END Popup;

END WMPopups.

S.Free WMPopups
