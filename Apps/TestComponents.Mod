MODULE TestComponents;	(** AUTHOR "TF"; PURPOSE "Template/Example  for component windows"; *)

(** This program shows the implementation of a multi instance component containing window *)

IMPORT
	Utilities, WMMessages, WMComponents, WMStandardComponents, AosModules, AosOut,
	WM := WMWindowManager;

TYPE
	KillerMsg = OBJECT
	END KillerMsg;
	
	O= OBJECT
	VAR name : ARRAY 10 OF CHAR;
		
		PROCEDURE &Init(name : ARRAY OF CHAR);
		BEGIN
			COPY(name, SELF.name)
		END Init;

		PROCEDURE SayHello2(sender, data : ANY);
		BEGIN
			AosOut.String("name= "); AosOut.String(name);
			AosOut.String("  Hello"); AosOut.Ln
		END SayHello2;

		PROCEDURE SayBye2(sender, data : ANY);
		BEGIN
			AosOut.String("name= "); AosOut.String(name);
			AosOut.String("  Bye"); AosOut.Ln
		END SayBye2;

	END O;

	Window* = OBJECT (WMComponents.FormWindow)
	VAR label : WMStandardComponents.Label;	
		o1, o2 : O;
		x : PROCEDURE {DELEGATE} (sender, data : ANY);

		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			panel : WMStandardComponents.Panel;
			toolbar : WMStandardComponents.Panel;
			button : WMStandardComponents.Button;

		BEGIN
			NEW(o1, "Object1");
			NEW(o2, "Object2");

			x := o2.SayBye2;
			x := o1.SayHello2;

			x(NIL, NIL);

			NEW(panel);
			panel.bounds.SetExtents(800, 700);
			panel.fillColor.Set(0FFFFFFFFH);
			panel.takesFocus.Set(TRUE);

			NEW(toolbar); 
			toolbar.fillColor.Set(000FF00FFH);
			toolbar.bounds.SetHeight(20);
			toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);

			NEW(button);
			button.alignment.Set(WMComponents.AlignLeft);
			button.caption.SetAOC("Hello");
			button.onClick.Add(o1.SayHello2);	
			toolbar.AddContent(button);

			NEW(button);
			button.alignment.Set(WMComponents.AlignLeft);
			button.caption.SetAOC("Bye"); 
			button.onClick.Add(o2.SayBye2);
			toolbar.AddContent(button);

			NEW(label);
			label.bounds.SetHeight(20);
			label.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(label);

			RETURN panel
		END CreateForm;

		PROCEDURE SayHello(sender, data : ANY);
		BEGIN
			AosOut.String("Guten Tag"); AosOut.Ln
		END SayHello;

		PROCEDURE SayBye(sender, data : ANY);
		BEGIN
			AosOut.String("Auf Wiedersehen"); AosOut.Ln
		END SayBye;

		PROCEDURE &New();
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			IncCount;
			(* To create a multi language app, try loading the respective XML instead of CreateForm()
			if the XML was not found or does not contain all needed elements, use CreateForm as fallback *)
			vc := CreateForm();

			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);

			 WM.DefaultAddWindow(SELF);
			SetTitle(Utilities.NewString("Test Window"));
		END New;

		PROCEDURE Close;
		BEGIN
			Close^;
			DecCount
		END Close;
		
		PROCEDURE Handle(VAR x : WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
			ELSE Handle^(x)
			END
		END Handle;
		
	END Window;

VAR
	nofWindows : LONGINT;

PROCEDURE Open*(par : ANY) : ANY;
VAR inst : Window;
BEGIN
	NEW(inst);
	RETURN NIL
END Open;

PROCEDURE IncCount;
BEGIN {EXCLUSIVE}
	INC(nofWindows)
END IncCount;

PROCEDURE DecCount;
BEGIN {EXCLUSIVE}
	DEC(nofWindows)
END DecCount;

PROCEDURE Cleanup;
VAR die : KillerMsg;
	 msg : WMMessages.Message;
	 m : WM.WindowManager;
BEGIN {EXCLUSIVE}
	NEW(die);
	msg.ext := die;
	msg.msgType := WMMessages.MsgExt;
	m := WM.GetDefaultManager();
	m.Broadcast(msg);
	AWAIT(nofWindows = 0)
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END TestComponents.

S.Free TestComponents ~
TestComponents.Open ~
