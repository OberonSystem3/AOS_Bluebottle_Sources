MODULE TestComponentDragDrop;	(** AUTHOR "TF"; PURPOSE "Testing Component Drag & Drop"; *)

IMPORT
	AosOut, Utilities, AosModules, AosCommands, WMStandardComponents, 
	WM := WMWindowManager, WMComponents, WMMessages, 
	WMGraphics, WMDialogs;

TYPE
	String = Utilities.String;
	
	TestComponent = OBJECT(WMComponents.VisualComponent)
		PROCEDURE PointerDown(x, y : LONGINT; keys : SET);
		BEGIN
			IF 0 IN keys THEN
				IF StartDrag(NIL, WMGraphics.LoadImage("Bart.Pict", TRUE), DragAccepted, DragRejected) THEN AosOut.String("DraggingStarted")
				ELSE AosOut.String("Drag could not be started")
				END;
			ELSE
				ToWMCoordinates(x, y, x, y);
				AosOut.Int(x, 5); AosOut.String(", "); AosOut.Int(y, 4); AosOut.Ln;
				AosOut.Int(WMDialogs.MessageXY(x, y, "Hello", "This should always be where you clicked the panel", {WMDialogs.ResOk}), 5);
			END
		END PointerDown;
		
		PROCEDURE DragOver(x, y: LONGINT; dragInfo : WM.DragInfo);
		BEGIN
			AosOut.String("Drag Over @ "); AosOut.Int(x, 4); AosOut.Int(y, 4); AosOut.Ln
		END DragOver;
		
		PROCEDURE DragDropped(x, y: LONGINT; dragInfo : WM.DragInfo);
		BEGIN
			AosOut.String("Drag dropped @ "); AosOut.Int(x, 4); AosOut.Int(y, 4); AosOut.Ln;
			IF dragInfo.sender = SELF THEN ConfirmDrag(FALSE, dragInfo)
			ELSE ConfirmDrag(TRUE, dragInfo)
			END
		END DragDropped;
		
		PROCEDURE DragAccepted(sender, data : PTR);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(DragAccepted, sender, data)
			ELSE
				AosOut.String("Accepted"); AosOut.Ln
			END;
		END DragAccepted;
		
		PROCEDURE DragRejected(sender, data : PTR);
		BEGIN
			IF ~IsCallFromSequencer() THEN sequencer.ScheduleEvent(DragRejected, sender, data)
			ELSE
				AosOut.String("Rejected"); AosOut.Ln
			END;
		END DragRejected;
		
	END TestComponent;
	
	Window = OBJECT (WMComponents.FormWindow)
	VAR 
		panel : WMStandardComponents.Panel;
		testComponent : TestComponent;
		
		PROCEDURE &New;
		BEGIN
			(* add a panel *)
			NEW(panel); panel.bounds.SetExtents(640, 420); panel.fillColor.Set(WMGraphics.RGBAToColor(255, 255, 255, 255));
			
			(* add a test component *)
			NEW(testComponent); testComponent.alignment.Set(WMComponents.AlignTop);
			 testComponent.bounds.SetExtents(200, 20); testComponent.fillColor.Set(0FFFFH);
			panel.AddContent(testComponent);
			
			(* add a test component *)
			NEW(testComponent); testComponent.alignment.Set(WMComponents.AlignTop);
			testComponent.bounds.SetExtents(200, 20); testComponent.fillColor.Set(0FF00FFH);
			panel.AddContent(testComponent);
			
			(* create the form window with panel size *)
			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), FALSE);
			SetContent(panel);
			
			manager := WM.GetDefaultManager();
			SetTitle(WM.NewString("Drag drop panels"));
			(* open the window *)
			manager.Add(100, 100, SELF, {WM.FlagFrame})
		END New;
		
		PROCEDURE Close;
		BEGIN
			FreeWindow;
			Close^
		END Close;
		
	END Window;

VAR window : Window;

PROCEDURE FreeWindow;
BEGIN {EXCLUSIVE}
	window := NIL
END FreeWindow;

PROCEDURE Open*(par: PTR): PTR;
BEGIN {EXCLUSIVE}
	IF window = NIL THEN NEW(window)
	ELSE AosOut.String("Already open"); AosOut.Ln
	END;
	RETURN NIL
END Open;

PROCEDURE Cleanup;
BEGIN
	IF window # NIL THEN window.Close END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END TestComponentDragDrop.

Aos.Call TestComponentDragDrop.Open ~
System.Free TestComponentDragDrop ~
WMComponents.Mod
