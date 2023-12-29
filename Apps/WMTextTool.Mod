MODULE WMTextTool;	(** AUTHOR "TF"; PURPOSE "Text Tool"; *)

IMPORT
	AosTexts, Utilities, WMProperties, WMEvents, WMComponents, WMRestorable, 
	WMGraphics, WMMessages, WMStandardComponents, WMWindowManager, AosModules, AosOut, WMBitmapFont;

TYPE
	KillerMsg = OBJECT
	END KillerMsg; 
	
	Window* = OBJECT (WMComponents.FormWindow)
	VAR 
		bold, lock, comment, stupid, assert, preferred, debug, normal: WMStandardComponents.Button;
		
		PROCEDURE CreateForm(): WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			toolbar: WMStandardComponents.Panel;
			
			PROCEDURE AB(panel : WMStandardComponents.Panel; btn: WMStandardComponents.Button);
			BEGIN
				btn.alignment.Set(WMComponents.AlignLeft); btn.bounds.SetWidth(60); panel.AddContent(btn)
			END AB;
			

		BEGIN
			NEW(panel); panel.bounds.SetExtents(120, 80); panel.takesFocus.Set(TRUE);

			(**)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			
			NEW(bold); bold.caption.SetAOC("Bold"); AB(toolbar, bold);
			NEW(lock); lock.caption.SetAOC("Lock"); AB(toolbar, lock);
	
			(**)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);

			NEW(comment); comment.caption.SetAOC("Comment"); AB(toolbar, comment);
			NEW(debug); debug.caption.SetAOC("Debug"); AB(toolbar, debug);
	
			(**)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			
			NEW(stupid); stupid.caption.SetAOC("Stupid"); AB(toolbar, stupid);
			NEW(assert); assert.caption.SetAOC("Assert"); AB(toolbar, assert);
			
	
			(**)
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			NEW(preferred); preferred.caption.SetAOC("Preferred"); AB(toolbar, preferred);
			NEW(normal); normal.caption.SetAOC("Normal"); AB(toolbar, normal);
	
			RETURN panel
		END CreateForm;

		PROCEDURE &New(c : WMRestorable.Context);
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount;
			vc := CreateForm();

			bold.onClick.Add(SetStyle);
			lock.onClick.Add(SetStyle);
			comment.onClick.Add(SetStyle);
			debug.onClick.Add(SetStyle);
			stupid.onClick.Add(SetStyle);
			assert.onClick.Add(SetStyle);
			preferred.onClick.Add(SetStyle);
			normal.onClick.Add(SetStyle);
			
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), TRUE);
			SetContent(vc);

			IF c # NIL THEN WMRestorable.AddByContext(SELF, c, {WMWindowManager.FlagStayOnTop, WMWindowManager.FlagFrame})				
			ELSE  WMWindowManager.ExtAddWindow(SELF, 50, 50, 
			 	{WMWindowManager.FlagStayOnTop, WMWindowManager.FlagFrame})
			 END;	
			SetTitle(Utilities.NewString("Text Styles"))
		END New;
		
		PROCEDURE SetStyle(sender, data : ANY);
		VAR text : AosTexts.Text;
			from, to : AosTexts.TextPosition;
			utilreader : AosTexts.TextReader;
			attr : AosTexts.Attributes;
			a, b, ch : LONGINT;
			style : SET;
			fgColor : LONGINT;
		BEGIN
			IF AosTexts.GetLastSelection(text, from, to) THEN
				IF sender = bold THEN
					style := {WMGraphics.FontBold};
					fgColor := WMGraphics.RGBAToColor(0, 0, 0, 0FFH);
				ELSIF sender = lock THEN
					style := {};
					fgColor := WMGraphics.RGBAToColor(0FFH, 0, 0FFH, 0FFH);
				ELSIF sender = preferred THEN
					style := {WMGraphics.FontBold};
					fgColor := WMGraphics.RGBAToColor(0FFH, 0, 0FFH, 0FFH);
				ELSIF sender = assert THEN
					style := {WMGraphics.FontBold};
					fgColor := WMGraphics.RGBAToColor(0, 0, 0FFH, 0FFH);
				ELSIF sender = comment THEN
					style := {};
					fgColor := WMGraphics.RGBAToColor(80H, 80H, 080H, 0FFH);
				ELSIF sender = debug THEN
					style := {};
					fgColor := WMGraphics.RGBAToColor(0H, 0H, 0FFH, 0FFH);
				ELSIF sender = stupid THEN
					style := {};
					fgColor := WMGraphics.RGBAToColor(0FFH, 0H, 0H, 0FFH);
				ELSIF sender = normal THEN
					style := {};
					fgColor := WMGraphics.RGBAToColor(0H, 0H, 0H, 0FFH);
				END;
				text.AcquireWrite;
				a := Utilities.Min(from.GetPosition(), to.GetPosition());
				b := Utilities.Max(from.GetPosition(), to.GetPosition());
				NEW(utilreader, text);
				utilreader.SetPosition(a);
				utilreader.ReadCh(ch);
				IF utilreader.attributes = NIL THEN
					NEW(attr); NEW(attr.fontInfo);
					attr.fontInfo.name := "Oberon";
					attr.fontInfo.size := 16;
				ELSE
					attr := utilreader.attributes.Clone();
				END; 
				attr.fontInfo.style := style;
				attr.color := fgColor;
				attr.fontInfo.fontcache := NIL;
				text.SetAttributes(a, b - a, attr);
				text.ReleaseWrite
			END
		END SetStyle;
		
		
		PROCEDURE Close;
		BEGIN
			DecCount;
			Close^;
		END Close;
		
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) THEN
				IF (x.ext IS KillerMsg) THEN Close
				ELSIF (x.ext IS WMRestorable.Storage) THEN
					x.ext(WMRestorable.Storage).Add("WMTextTool", "WMTextTool.Restore", SELF, NIL)
				ELSE Handle^(x)
				END
			ELSE Handle^(x)
			END
		END Handle;		
		
	END Window;
(***************************************************************************************)


VAR
	nofWindows : LONGINT;

PROCEDURE Open*(par : ANY) : ANY;
VAR inst : Window;
BEGIN
	NEW(inst, NIL);
	RETURN NIL
END Open;


PROCEDURE Restore*(par : ANY) : ANY;
VAR w : Window;
BEGIN
	IF (par # NIL) & (par IS WMRestorable.Context) THEN
		NEW(w, par(WMRestorable.Context))
	END;
	RETURN NIL
END Restore;

PROCEDURE IncCount;
BEGIN {EXCLUSIVE}
	INC(nofWindows);
END IncCount;		

PROCEDURE DecCount;
BEGIN {EXCLUSIVE}
	DEC(nofWindows);
END DecCount;		

PROCEDURE Cleanup;
VAR die : KillerMsg;
	 msg : WMMessages.Message;
	 m : WMWindowManager.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die); msg.ext := die; msg.msgType := WMMessages.MsgExt;
	m := WMWindowManager.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END WMTextTool.

S.Free WMTextTool 
WMTextTool.Open   


