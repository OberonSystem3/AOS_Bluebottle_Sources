MODULE AosUsbHidDriver;  (** AUTHOR "ottigerm"; PURPOSE "USB HID Parser"; *)
(**	
 * Bluebottle USB HID Driver
 *
 * This driver currently supports:
 *
 *	Mouse:		2 axis, 1 mouse wheel, up to 32 buttons
 *	Keyboard	incl. consumer keys
 *	Joystick		x, y, z, rx, ry, rz and one slider axis, one coolie hat and arbitrary many buttons
 *
 * Usage:
 *	AosUsbHidDriver.Install ~ load this driver
 *	S.Free AosUsbHidDriver ~ unload this driver
 *		
 * Remarks: 
 *	
 * References:
 *	Device Class Definition for Human Interface Devices (HID), Version 1., 27.09.2006, www.usb.org
 *
 * History:
 *	21.04.2006	starting
 *	22.01.2007	Version 1.0
 *)

IMPORT 	
	SYSTEM, AosBoot, AosOut, AosModules, AosInputs, AosUsbdi, AosUsbHid, 
	HidParser := AosUsbHidParser, AosUsbHidReport, UsagePage := AosUsbHidUP, AosUsbKeyboard,
	Joystick := AosJoysticks;

CONST

	Name = "UsbHid";	
	Description = "USB HID driver";
	
	Debug 	= HidParser.Debug;
	Trace	= HidParser.Trace;
	
	(* use for logging the reports *)
	ShowNoReport 			= 0;	(* do not show any reports *)
	ShowVeryShortReport 	= 1; (* show short and non zero valued reports *)
	ShowShortReport 		= 2; (* show short reports; only the ids with their assigned value *)
	ShowFullReport 		= 3; (* show reports including description *)
	
	LoggingMode = ShowNoReport;
	
	MouseSpeed = 50;
	MouseWheelSpeed = 3;   
	MouseAcceleration = 0;

TYPE
	MouseState = POINTER TO RECORD
		(* mouse msg can hold up to 32 buttons *)
		buttons:			ARRAY 32 OF AosUsbHidReport.UsageTuple;
		(* identifies the last available button *)
		buttonCount:	LONGINT;
		buttonReport:	AosUsbHidReport.HidReport;
		x:				AosUsbHidReport.UsageTuple;
		y:				AosUsbHidReport.UsageTuple;
		axisReport:		AosUsbHidReport.HidReport;
		wheel:			AosUsbHidReport.UsageTuple;
		wheelReport:	AosUsbHidReport.HidReport;
		lastDx, lastDy: 	LONGINT;
	END;
	
	(*Handling keyboard devices*)
	KeyboardState = OBJECT(AosUsbKeyboard.KeyboardBase)
	VAR	
		modifierUsages: AosUsbHidReport.PtrToUsageTupleArr;     (*first ref on buffer*)
		keycodeUsages: AosUsbHidReport.PtrToUsageTupleArr;
		
		pressed* : POINTER TO ARRAY OF AosUsbKeyboard.Key;
		tempPressed : POINTER TO ARRAY OF AosUsbKeyboard.Key;
		
		ledStateChanged : BOOLEAN;
		
		(*init settings*)
		PROCEDURE Init();
		VAR i : LONGINT; k : ARRAY 32 OF CHAR;
		BEGIN
			(* Get  *)
			AosBoot.GetConfig("Keyboard", k);
			i := -1;
			IF k # "" THEN i := TableFromFile(k); END;
			IF i = -1 THEN (* Fallback to default *) i := AosUsbKeyboard.TableUS(); END;
			SYSTEM.PUT(SYSTEM.ADR(keytable), i); 

			(* Apply Numlock boot up state *)
			AosBoot.GetConfig("NumLock", k); 
			IF k[0] = "1" THEN INCL(leds, AosUsbKeyboard.NumLock) END;
	
			keyDeadTime := AosUsbKeyboard.KeyDeadTime DIV 10; 
			keyDeadTimeRepeat := AosUsbKeyboard.KeyDeadTimeRepeat DIV 10;		
			
			NEW(ledBuffer, 1);
		END Init;
		
		(** 
		 * Sets the maximum possible amount of keys, the device is sending at one time
		 * @param nofkeys: the number of keys maximumely sent by the device	
		 *)
		PROCEDURE SetMaxKeycodes(nofKeys: LONGINT);
		BEGIN
			ASSERT(pressed=NIL);
			ASSERT(tempPressed=NIL);
			NEW(pressed,nofKeys);
			NEW(tempPressed, nofKeys);		
		END SetMaxKeycodes;
		
		(** 
		 * Handle Keyboard Report
		 *)
		PROCEDURE HandleKeyboardEvent();
		VAR
			i, j : LONGINT;
			c : CHAR;
			flags : SET;
			found, kill : BOOLEAN;
		BEGIN
			(*AosOut.String('handle key'); AosOut.Ln;*)
			(* evaluate modifier keys *)
			msg.flags := {};
			
			IF (modifierUsages[0].usageValue=1) THEN INCL(msg.flags, AosInputs.LeftCtrl) END;
			IF (modifierUsages[1].usageValue=1) THEN INCL(msg.flags, AosInputs.LeftShift) END;
			IF (modifierUsages[2].usageValue=1) THEN INCL(msg.flags, AosInputs.LeftAlt) END;
			IF (modifierUsages[3].usageValue=1) THEN INCL(msg.flags, AosInputs.LeftMeta) END;
			IF (modifierUsages[4].usageValue=1) THEN INCL(msg.flags, AosInputs.RightCtrl) END;
			IF (modifierUsages[5].usageValue=1) THEN INCL(msg.flags, AosInputs.RightShift) END;
			IF (modifierUsages[6].usageValue=1) THEN INCL(msg.flags, AosInputs.RightAlt) END;
			IF (modifierUsages[7].usageValue=1) THEN INCL(msg.flags, AosInputs.RightMeta) END;
			
			flags := msg.flags;
			
			(* evaluate the six keycodes *)
			FOR i := 2 TO 7 DO
				c := SYSTEM.VAL(CHAR, keycodeUsages[i-2].usageValue);
				IF c # CHR(0) THEN (* buffer[i] contains key code *)
					
					(* check whether the key is pressed for the first time, is still being pressed or has been released *)
					FOR j := 0 TO 5 DO 
					
						IF pressed[j].ch = c THEN (* key is still pressed *)						
							found := TRUE;
							pressed[j].updated := TRUE;
							
							tempPressed[i-2].counter := pressed[j].counter + 1;
							tempPressed[i-2].ch := pressed[j].ch;
							tempPressed[i-2].keysym := pressed[j].keysym;
							tempPressed[i-2].updated := FALSE;
							tempPressed[i-2].repeat := pressed[j].repeat;
							
							IF pressed[j].repeat THEN 
								IF (keyDeadTimeRepeat # 0) & (tempPressed[i-2].counter MOD keyDeadTimeRepeat # 0) THEN (* don't send key event *) kill := TRUE; END;
							ELSE
								IF tempPressed[i-2].counter MOD keyDeadTime # 0 THEN (* don't send key event *) 
									kill := TRUE; 
								ELSE
									tempPressed[i-2].repeat := TRUE; 
								END;
							END;
						END; 
				    	END;
				 END; 	
					
				IF ~found THEN (* the key has not been pressed down before *)
					tempPressed[i-2].ch := c;
					tempPressed[i-2].repeat := FALSE;
					tempPressed[i-2].updated := FALSE;
					tempPressed[i-2].counter := 1;
				END;
					
			    (* kill : Key is pressed but do not generate key event this time -> repeat rate ... *)		
			    IF (c # CHR(0)) & ~kill THEN 
			    	HandleKey(c); 
			    	tempPressed[i-2].keysym := msg.keysym; (* msg.keysym asigned by HandleKey() ... *)
			    END;
			END; (* FOR LOOP *)
				
			(* update pressed array. generate keyboard.msg's for released keys *)
			FOR i := 0 TO 5 DO
				IF (pressed[i].updated = FALSE) & (pressed[i].ch # CHR(0)) THEN (* this key has been released *)
					msg.flags := {};
					INCL(msg.flags, AosInputs.Release);
					msg.ch := pressed[i].ch;
					msg.keysym := pressed[i].keysym;
					dkHack := deadKey;  (* value of deadKey should persist the key release event *)
					HandleKey(c);
					deadKey := dkHack;
				END;
				pressed[i].counter := tempPressed[i].counter;
				pressed[i].ch := tempPressed[i].ch;
				pressed[i].keysym := tempPressed[i].keysym;
				pressed[i].repeat := tempPressed[i].repeat;
				pressed[i].updated := FALSE;
			END;
				
			(* Generate events for modifiers *)
			HandleModifiers(flags);
								
			(* update status of the LEDs  of the keyboad if necessary *)
			IF lastLeds # leds THEN (* LED status has changed *)
				ledBuffer[0] := SYSTEM.VAL(CHAR, leds); lastLeds := leds;
				ledStateChanged := TRUE;
			END;
		END HandleKeyboardEvent;
	END KeyboardState;	
	
	(* When user presses button, the system has to store the pressed keys in this linked list *)
	ConsumerKey = POINTER TO RECORD
		key: LONGINT;
		usagePage: LONGINT;
		alive: BOOLEAN;
		next: ConsumerKey;
	END;
	
	(*handling consumer devices*)
	ConsumerState= OBJECT
	VAR
		(*where the consumer report is stored*)
		consumerReport : AosUsbHidReport.HidReport;
		first: ConsumerKey;
		
		(** 
		 * Checks, whether the usageID with the usagePage is still pressed by the user
		 * if found, also sets the alive flag to TRUE, such that the clean up method will not destroy it next time
		 * @param usageID: the usageID pressed
		 * @param usagePage: normally 0, for detected consumer devices; 9, if consumer send consumer keys as buttons
		 * @return TRUE, if found, FALSE otherwise
		 *)
		PROCEDURE IsSet(usageID, usagePage: LONGINT): BOOLEAN;
		VAR cursor:	ConsumerKey;
		BEGIN
			cursor := first;
			WHILE(cursor#NIL) DO
				IF ((cursor.key=usageID) & (cursor.usagePage=usagePage)) THEN
					cursor.alive := TRUE;
					RETURN TRUE;
				END;
				cursor := cursor.next;
			END;
			RETURN FALSE;
		END IsSet;
		
		(** 
		 * Adds the tuple.usageID and tuple.usagePage to the linked list
		 * @param tuple: the tuple to add
		 *)
		PROCEDURE AddKey(tuple:AosUsbHidReport.UsageTuple);
		VAR cursor: ConsumerKey;
		BEGIN
			IF first=NIL THEN
				NEW(first);
			ELSE
				NEW(cursor);
				cursor.next := first;
				first := cursor;
			END;
			first.key := tuple.usageID;
			first.usagePage := tuple.usagePage;
			first.alive := TRUE;
		END AddKey;
		
		(** 
		 * destroys all consumerKeys whose alive flag is not set
		 *)
		PROCEDURE CleanUp;
		VAR cursor, previous: ConsumerKey;
		BEGIN
			cursor := first;
			WHILE(cursor#NIL) DO
				IF cursor.alive = FALSE THEN
					SendKeySym(cursor.key,cursor.usagePage,FALSE);
					IF(cursor = first) THEN
						first := first.next;
					ELSE
						previous.next := cursor.next;
					END;
				ELSE
					cursor.alive := FALSE;
					previous := cursor;
				END;
				cursor := cursor.next;
			END;
		END CleanUp;
		
		(** 
		 * Checks whether the keysym is valid, if yes, it generates a keymsg and sends the key to AosInputs
		 * @param usage: the id of the keysym
		 * @param usagePage: 0: normally, 9: if key is sent as button
		 *)
		PROCEDURE SendKeySym(usage, usagePage:LONGINT; pressed:BOOLEAN);
		VAR keyMsg : AosInputs.KeyboardMsg;
		BEGIN
			IF Debug THEN
				AosOut.String("Handling key");
			END;
			IF (usagePage=0) THEN
				CASE usage OF
					0B5H: 	keyMsg.keysym := AosInputs.KsScanNextTrack; 		(*AosOut.String("KsScanNextTrack");*)
					|0B6H: 	keyMsg.keysym := AosInputs.KsScanPreviousTrack; 	(*AosOut.String("KsScanPreviousTrack");*)
					|0B7H: 	keyMsg.keysym := AosInputs.KsStopOSC; 				(*AosOut.String("KsStopOSC");*)
					|0CDH: 	keyMsg.keysym := AosInputs.KsPlayPause; 			(*AosOut.String("KsPlayPause");*)
					|0E2H: 	keyMsg.keysym := AosInputs.KsMute; 					(*AosOut.String("KsMute");*)
					|0E9H: 	keyMsg.keysym := AosInputs.KsVolumeIncrement; 		(*AosOut.String("KsVolumeIncrement");*)
					|0EAH: 	keyMsg.keysym := AosInputs.KsVolumeDecrement; 	(*AosOut.String("KsVolumeDecrement");*)
					|183H: 	keyMsg.keysym := AosInputs.KsALConsumerControl; 	(*AosOut.String("KsALConsumerControl");*)
					|18AH: 	keyMsg.keysym := AosInputs.KsALEmailReader; 		(*AosOut.String("KsALEmailReader");*)
					|221H: 	keyMsg.keysym := AosInputs.KsACSearch; 				(*AosOut.String("KsACSearch");*)
					|223H: 	keyMsg.keysym := AosInputs.KsACHome; 				(*AosOut.String("KsACHome");*)
					|224H: 	keyMsg.keysym := AosInputs.KsACBack; 				(*AosOut.String("KsACBack");*)
					|225H: 	keyMsg.keysym := AosInputs.KsACForward; 			(*AosOut.String("KsACForward");*)
					|22AH: 	keyMsg.keysym := AosInputs.KsACBookmarks; 			(*AosOut.String("KsACBookmarks");*)
				ELSE
					IF Trace THEN
						AosOut.String("Key Sym "); AosOut.Hex(usage,0 ); AosOut.String("H not found"); AosOut.Ln;
					END;
				END;
			ELSE
				(*special case: when usagePage Button is used*)
				IF (usagePage=9H) THEN
					keyMsg.keysym := AosInputs.KsConsumerButtons+usage;
				END;
			END;
			IF (keyMsg.keysym#0) THEN
				IF ~pressed THEN
					keyMsg.flags:= {};
					keyMsg.keysym := AosInputs.KsNil;
					INCL(keyMsg.flags, AosInputs.Release);
				END;
				IF Debug THEN
					IF usagePage=0 THEN
						CASE usage OF
							0B5H: 	AosOut.String("KsScanNextTrack");
							|0B6H: 	AosOut.String("KsScanPreviousTrack");
							|0B7H: 	AosOut.String("KsStopOSC");
							|0CDH:	AosOut.String("KsPlayPause");
							|0E2H: 	AosOut.String("KsMute");
							|0E9H: 	AosOut.String("KsVolumeIncrement");
							|0EAH: 	AosOut.String("KsVolumeDecrement");
							|183H: 	AosOut.String("KsALConsumerControl");
							|18AH: 	AosOut.String("KsALEmailReader");
							|192H: 	AosOut.String("KsALCalculator");
							|221H: 	AosOut.String("KsACSearch");
							|223H: 	AosOut.String("KsACHome");
							|224H: 	AosOut.String("KsACBack");
							|225H: 	AosOut.String("KsACForward");
							|22AH: 	AosOut.String("KsACBookmarks");
						ELSE
							AosOut.String("Key Sym not found"); AosOut.Ln;
						END;
					ELSE
						IF usagePage=9 THEN
							AosOut.String("KsConsumerButtons(");AosOut.Int(usage,0); AosOut.String(")");
						END;
					END;
					IF pressed THEN
						AosOut.String(" pressed");
					ELSE
						AosOut.String(" released");
					END;
					AosOut.Ln;
				END;
				AosInputs.keyboard.Handle(keyMsg);
			END;
		END SendKeySym;
		
	END ConsumerState;
	
	(*handle joystick devices*)
	JoystickState = POINTER TO RECORD
		(*use the joystick as a mouse*)
		(*mouse msg can hold up to 32 buttons*)
		buttons:			ARRAY 32 OF AosUsbHidReport.UsageTuple;
		(*identifies the last available button*)
		buttonCount:	LONGINT;
		buttonReport:	AosUsbHidReport.HidReport;
		x:				AosUsbHidReport.UsageTuple;
		y:				AosUsbHidReport.UsageTuple;
		z:				AosUsbHidReport.UsageTuple;
		rx:				AosUsbHidReport.UsageTuple;
		ry:				AosUsbHidReport.UsageTuple;
		rz:				AosUsbHidReport.UsageTuple;
		slider:			AosUsbHidReport.UsageTuple;
		hatSwitch:		AosUsbHidReport.UsageTuple;
		
		xReport:			AosUsbHidReport.HidReport;
		yReport:			AosUsbHidReport.HidReport;
		zReport:			AosUsbHidReport.HidReport;
		rxReport:			AosUsbHidReport.HidReport;
		ryReport:			AosUsbHidReport.HidReport;
		rzReport:			AosUsbHidReport.HidReport;
		sliderReport:		AosUsbHidReport.HidReport;
		hatSwitchReport:	AosUsbHidReport.HidReport;
		
		joystick:			Joystick.Joystick;
	END;

	(*the hid driver*)
	HidDriver= OBJECT (AosUsbHid.HidDriver)
	VAR
		(*itemParser is responsible for parsing the usb hid report descriptor*)
		itemParser 	: HidParser.ItemParser;
		endpoint	: LONGINT;
		pipe 		: AosUsbdi.Pipe;
		
		(*where the report interrupt in report is stored*)
		reportBuffer				: AosUsbdi.BufferPtr;
		reportManager			: AosUsbHidReport.HidReportManager;
		hidReportItemQueue	: AosUsbHidReport.ReportItemQueue;
		mouseState				: MouseState;
		keyboardState			: KeyboardState;
		consumerState			: ConsumerState;
		joystickState			: JoystickState;
		useReportIDMechanism	: BOOLEAN;
		
		(* 
		 * This procedure is called by the USB system software after an instance of this object has been passed to it via the probe procedure.
		 * Typically, the code here sets up the communication pipe(s) use by the driver using device.GetPipe(endpointnumber).
		 *)
		PROCEDURE Connect*() : BOOLEAN;
		VAR
			hidDescriptor 		: AosUsbHid.HidDescriptor;
			i					: LONGINT;
			reportDescBuffer 	: AosUsbdi.BufferPtr;
			status 				: AosUsbdi.Status;
			canManage			: BOOLEAN;
		BEGIN
			(*TestReader;*)
			(*parse the hid report descriptor*)
			NEW(itemParser);
			(*get interface descriptor*)
			
			hidDescriptor := GetHidDescriptor();
			IF (hidDescriptor = NIL) THEN
				RETURN FALSE;
			END;
			
			IF Debug THEN AosUsbHid.ShowHidDescriptor(hidDescriptor);	END;
			
			NEW(reportDescBuffer, hidDescriptor.wDescriptorLength);
			IF ~GetDescriptor(hidDescriptor.bClassDescriptorType,  0, interface.bInterfaceNumber , hidDescriptor.wDescriptorLength, reportDescBuffer^) THEN
				AosOut.String("    Could not get reportDescriptor"); AosOut.Ln;
				RETURN FALSE;
			ELSE
				IF Debug THEN
					(*print all all bytes of the reportDescBuffer*)
					LayoutBuffer(reportDescBuffer^, hidDescriptor.wDescriptorLength);
				END;
			END;
			IF(~itemParser.ParseReportDescriptor(hidDescriptor, reportDescBuffer)) THEN
				IF Debug THEN AosOut.String("    Could not parse Report Descriptor correctly"); AosOut.Ln; END;
			END;
			IF Trace THEN
				(*there are cases, where the report descriptor is not set correctly, but it can be used with this errors.*)
				itemParser.errorList.PrintAll;
			END;
			
			(*get reportManager and hidReportItemQueue*)
			reportManager := itemParser.GetReportManager();
			hidReportItemQueue := reportManager.GetReportItemQueue();
			
			LOOP
				IF i >= LEN(interface.endpoints) THEN EXIT; END;
				IF (interface.endpoints[i].type = AosUsbdi.InterruptIn)  THEN 
					endpoint := SHORT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, interface.endpoints[0].bEndpointAddress) * {0,1,2,3,7}));
					EXIT;
				END;		
				INC(i);			
			END;
			
			IF endpoint = 0 THEN
				IF Debug THEN AosOut.String("AosUsbMouse: No interrupt IN endpoint found."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			pipe := device.GetPipe(endpoint);
			IF pipe = NIL THEN RETURN FALSE END;
			
			IF InitializeMouseDriver() = TRUE THEN
				canManage := TRUE;
			END;
			
			IF InitializeKeyboardDriver()=TRUE THEN
				canManage := TRUE;
			END;
			
			IF InitializeConsumerDriver() = TRUE THEN
				canManage := TRUE;
			END;
			
			IF InitializeJoystickDriver()=TRUE THEN
				canManage := TRUE;
			END;
			
			IF (canManage) THEN
				
				useReportIDMechanism	:= reportManager.UsesReportIDMechanism();
				
				NEW(reportBuffer, pipe.maxPacketSize);
			
				pipe.SetTimeout(0);
				pipe.SetCompletionHandler(HandleHidEvent);
				
				status := pipe.Transfer(pipe.maxPacketSize, 0, reportBuffer^);
				IF Debug THEN
					AosOut.String("AosUsbHidDriver.HidDriver.Connect: Connect successfully finished"); AosOut.Ln;
				END;
		(*	ELSE  NOT SUPPORTED YET, because the whole driver is removed but not only the interface
				RETURN FALSE; *)
			END;
			
			RETURN TRUE;
		END Connect;
			
		(*called when detaching a usb hid device*)
		PROCEDURE Disconnect*;
		BEGIN
			itemParser.Disconnect();
			itemParser:=NIL;			
			(*joystick*)
			IF (joystickState#NIL) THEN
				IF joystickState.joystick#NIL THEN
					Joystick.registry.Remove(joystickState.joystick);
				END;
			END;
			IF Debug OR Trace THEN AosOut.String("USB HID Device disconnected."); AosOut.Ln; END;
		END Disconnect;
		
		(*is always called, when new report arrived*)
		PROCEDURE HandleHidEvent(status : AosUsbdi.Status; actLen : LONGINT);
		VAR
			ri			: AosUsbHidReport.ReportItem;
			i, bitIndex	: LONGINT;
			reportID	: LONGINT;
			res			: BOOLEAN;
			usageTuple	: AosUsbHidReport.UsageTuple;
			
			(* 
			* update the reportManager with the newest values
			*)
			PROCEDURE HandleReportItem;
			BEGIN
				FOR i:=0 TO (ri.reportItemCount-1) DO
					IF(ri.values=NIL) THEN
						(*there are no values to read, because the reportItem describes a constant field*)
					ELSE
						IF Debug THEN
							AosOut.String("HandleHidEvent: Reading..."); AosOut.Ln;
						END;
						usageTuple := ri.values[i];
						usageTuple.usageValue := ReadBits(bitIndex,ri.reportItemSize);
						IF (LoggingMode=ShowShortReport) OR (LoggingMode=ShowVeryShortReport) THEN
							IF((LoggingMode=ShowShortReport)OR(ri.values[i].usageValue#0)) THEN
								AosOut.String("usageValue for usageID "); 
								AosOut.Int(ri.values[i].usageID,0);
								AosOut.String(" is: "); 
								AosOut.Int(ri.values[i].usageValue,0); 
								AosOut.Ln;
							END;
						END;
					END;
				
					bitIndex := bitIndex + ri.reportItemSize;
				END;
			END HandleReportItem;
		BEGIN
			(*start reportParsing*)
			
			IF Debug THEN
				IF((hidReportItemQueue=NIL) OR (reportManager=NIL)) THEN
					AosOut.String("AosUsbHidDriver:HidDriver.HandleHidEvent: Internal Error,hidReportItemQueue or reportManager not found"); AosOut.Ln;
				END;
				LayoutBuffer(reportBuffer^,actLen);
			END;
			
			(*fill up report buffer with new values*)
			ri := hidReportItemQueue.first;
			
			IF(ri=NIL) THEN
				AosOut.String("ri=NIL"); AosOut.Ln;
				RETURN;
			END;
			(*index in the reportBuffer*)
			bitIndex := 0;
			IF (useReportIDMechanism) THEN
				reportID := ReadBits(0, 8);
				bitIndex := bitIndex + 8;
				
				WHILE(ri#NIL) DO
					IF(ri.reportID=reportID) THEN
						HandleReportItem;
					END;
					ri := ri.next;
				END;
			ELSE
				WHILE(ri#NIL) DO
					HandleReportItem;
					ri := ri.next;
				END;
			END;
			
			IF LoggingMode=ShowFullReport THEN reportManager.PrintReportState END;
			
			IF (  (status = AosUsbdi.Ok) OR (status=AosUsbdi.ShortPacket)) THEN
				
				IF(mouseState#NIL) THEN
					IF Debug THEN AosOut.String("handle mouse driver"); AosOut.Ln; END;
					HandleMouseDriver;
				END;
				IF(keyboardState#NIL) THEN
					IF Debug  THEN  AosOut.String("handle keyboard driver"); AosOut.Ln; END;
					HandleKeyboardDriver;
					(* update status of the LEDs  of the keyboad if necessary *)
					IF keyboardState.lastLeds # keyboardState.leds THEN (* LED status has changed *)
						keyboardState.ledBuffer[0] := SYSTEM.VAL(CHAR, keyboardState.leds); keyboardState.lastLeds := keyboardState.leds;
						res := SetReport(AosUsbHid.ReportOutput, 0, keyboardState.ledBuffer^, 1); (* ignore res *)
					END;
				END;
				
				IF(consumerState#NIL) THEN
					IF Debug THEN AosOut.String("handle consumer driver"); AosOut.Ln; END;
					HandleConsumerDriver;
				END;
				
				IF(joystickState#NIL) THEN
					IF Debug THEN AosOut.String("handle custom driver"); AosOut.Ln; END;
					HandleJoystickDriver;
				END;
				
				(*get new message from hid device*)
				status := pipe.Transfer(pipe.maxPacketSize, 0, reportBuffer^);
			ELSE
				IF Debug THEN
					AosOut.String("AosUsbHidDriver: "); AosOut.String(name); AosOut.String("("); AosOut.String(desc); AosOut.String(")");
					AosOut.String(" has been disabled."); AosOut.Ln;
				END;
				IF (status = AosUsbdi.Stalled) THEN
					IF pipe.ClearHalt() THEN
						IF Debug THEN AosOut.String("AosUsbHidDriver: Stall on Interrupt Pipe cleared."); AosOut.Ln; END;
						status := pipe.Transfer(pipe.maxPacketSize, 0, reportBuffer^); (* ignore status *)
					ELSE
						IF Debug THEN AosOut.String("AosUsbHidDriver: Couldn't clear stall on interrupt pipe. Abort."); AosOut.Ln; END;
						device.FreePipe(pipe); 
					END;
				END;
			END;
		END HandleHidEvent;
		
		(** 
		 * Is called by handleHidEvent when mouse device is found
		 *)
		PROCEDURE HandleMouseDriver;
		VAR
			mm : 			AosInputs.MouseMsg;
			dx, dy,i :		LONGINT;
			accelX, accelY : 	REAL;
		BEGIN
			dx := TwosComplement(mouseState.x.usageValue, mouseState.axisReport.reportSize); 
			dy := TwosComplement(mouseState.y.usageValue, mouseState.axisReport.reportSize);
			IF Debug THEN AosOut.String("x and y are: ");AosOut.Int(dx,0); AosOut.String(" and ");AosOut.Int(dy,0); AosOut.Ln; END;
			
			accelX := 1.0 + ABS(dx - mouseState.lastDx) / 128 * MouseAcceleration;
			accelY := 1.0 + ABS(dy - mouseState.lastDy) / 128 * MouseAcceleration; 
				
			mouseState.lastDx := dx; 
			mouseState.lastDy := dy;
			(*AosOut.String("X: "); AosOut.Int(dx,0); AosOut.String("  Y:"); AosOut.Int(dy,0); AosOut.Ln;*)			
			mm.dx := ENTIER(MouseSpeed / 50.0 *  dx * accelX);
			mm.dy := ENTIER(MouseSpeed / 50.0 * dy * accelY);
				
			IF (mouseState.wheel#NIL) THEN  
				mm.dz := - TwosComplement(mouseState.wheel.usageValue, mouseState.wheelReport.reportSize);
				IF mm.dz < 0 THEN mm.dz := - MouseWheelSpeed;
				ELSIF mm.dz>0 THEN mm.dz := + MouseWheelSpeed;
				END;
			END;
				
			IF (mouseState.buttons[0].usageValue#0) THEN mm.keys := mm.keys + {0}; END;
			IF (mouseState.buttons[1].usageValue#0) THEN mm.keys := mm.keys + {2}; END;
			IF (mouseState.buttons[2].usageValue#0) THEN mm.keys := mm.keys + {1}; END;
			
			FOR i:=3 TO 31 DO
				IF (mouseState.buttons[i]#NIL) THEN
					IF (mouseState.buttons[i].usageValue#0) THEN mm.keys := mm.keys + {i}; END;
				END;
			END;	
			AosInputs.mouse.Handle(mm);
		END HandleMouseDriver;
		
		(** 
		 * Is called by handleHidEvent when keyboard device is found
		 *)
		PROCEDURE HandleKeyboardDriver;
		VAR res : BOOLEAN;
		BEGIN
			keyboardState.HandleKeyboardEvent();
			IF keyboardState.ledStateChanged THEN
				res := SetReport(AosUsbHid.ReportOutput, 0, keyboardState.ledBuffer^, 1); (* ignore res *)
				keyboardState.ledStateChanged := FALSE;
			END;
		END HandleKeyboardDriver;
		
		(** 
		 * Is called by handleHidEvent when consumer device is found
		 *)
		PROCEDURE HandleConsumerDriver;
		VAR
			temp: 		AosUsbHidReport.HidReport;
			usageTuple:	AosUsbHidReport.UsageTuple;
			i: 			LONGINT;
			dictUsage:	LONGINT;
		BEGIN
			temp := consumerState.consumerReport;
			WHILE(temp#NIL) DO
				IF temp.usages # NIL THEN
					FOR i:=0 TO temp.reportCount-1 DO
						IF(temp.usages[i].usageValue#0)THEN
							IF HidParser.IDMainIsVariable IN SYSTEM.VAL(SET,temp.mainState) THEN
								IF Debug THEN
									AosOut.Int(temp.usages[i].usageID,0); 
									AosOut.String(" ("); UsagePage.PrintUsagePage(UsagePage.ConsumerPage, temp.usages[i].usageID);
								END;
								IF(consumerState.IsSet(temp.usages[i].usageID,temp.usages[i].usagePage)=FALSE) THEN
									consumerState.AddKey(temp.usages[i]);
									consumerState.SendKeySym(temp.usages[i].usageID, temp.usages[i].usagePage, TRUE);
								END;
							ELSE
								(*the data is sent in an array*)
								IF AosUsbHidReport.UseUsageDictionaryExt THEN
									IF Debug THEN
										AosOut.String("-> usage dictionary  index: "); AosOut.Int(temp.usages[i].usageValue,0); AosOut.String(";     ");
									END;
									usageTuple := reportManager.GetDictKey(temp.usages[i].usageValue-temp.logicalMinimum, temp.supportedUsages);
									(*dictUsage := usageTuple.usageID;
									AosOut.String("usageID is "); AosOut.Int(usageTuple.usagePage,0); AosOut.String("  "); AosOut.Hex(dictUsage,0); AosOut.Ln;*)
									IF (consumerState.IsSet(usageTuple.usageID,usageTuple.usagePage)=FALSE) THEN
										consumerState.AddKey(usageTuple);
										consumerState.SendKeySym(usageTuple.usageID, usageTuple.usagePage, TRUE);
									END;
									IF Debug THEN
										AosOut.Int(dictUsage,0);
										AosOut.String(" (");
										IF usageTuple.usagePage # 0 THEN
											UsagePage.PrintUsagePage(usageTuple.usagePage, dictUsage);
										ELSE
											UsagePage.PrintUsagePage(UsagePage.ConsumerPage, dictUsage);
										END;
									END;
								ELSE
									IF Debug THEN
										AosOut.Int(temp.usages[i].usageValue,0);
										AosOut.String(" ("); UsagePage.PrintUsagePage(UsagePage.ConsumerPage, temp.usages[i].usageValue);
									END;
									IF (consumerState.IsSet(temp.usages[i])=FALSE) THEN
										consumerState.AddKey(temp.usages[i]);
										consumerState.SendKeySym(temp.usages[i].usageValue,temp.usages[i].usagePage, TRUE);
									END;
								END;
							END;
							IF Debug THEN AosOut.String(") pressed."); AosOut.Ln; END;
						END;
					END;
				END;	
				temp := temp.next;
			END;
			consumerState.CleanUp;
		END HandleConsumerDriver;
		
		(** 
		 * Is called by handleHidEvent when joystick device is found
		 *)
		 PROCEDURE HandleJoystickDriver;
		VAR
			msg : 		Joystick.JoystickDataMessage;
			i:			LONGINT;
		BEGIN
			FOR i:=0 TO joystickState.buttonCount-1 DO
				IF (joystickState.buttons[i].usageValue#0) THEN
					msg.buttons := msg.buttons + {joystickState.buttons[i].usageID-1};
				END;
			END;
			
			IF joystickState.x # NIL THEN
				IF joystickState.xReport.logicalMinimum<0 THEN
					msg.axis[Joystick.AxisX] := TwosComplement(joystickState.x.usageValue,joystickState.xReport.reportSize);
				ELSE
					msg.axis[Joystick.AxisX] := joystickState.x.usageValue;
				END;
			END;
			
			IF joystickState.y # NIL THEN
				IF joystickState.yReport.logicalMinimum<0 THEN
					msg.axis[Joystick.AxisY] := TwosComplement(joystickState.y.usageValue,joystickState.yReport.reportSize);
				ELSE
					msg.axis[Joystick.AxisY] := joystickState.y.usageValue;
				END;
			END;
			
			IF joystickState.z # NIL THEN
				IF joystickState.zReport.logicalMinimum<0 THEN
					msg.axis[Joystick.AxisZ] := TwosComplement(joystickState.z.usageValue,joystickState.zReport.reportSize);
				ELSE
					msg.axis[Joystick.AxisZ] := joystickState.z.usageValue;
				END;
			END;
			
			IF joystickState.rx # NIL THEN
				IF joystickState.rxReport.logicalMinimum<0 THEN
					msg.axis[Joystick.AxisRx] := TwosComplement(joystickState.rx.usageValue,joystickState.rxReport.reportSize);
				ELSE
					msg.axis[Joystick.AxisRx] := joystickState.rx.usageValue;
				END;
			END;
			
			IF joystickState.ry # NIL THEN
				IF joystickState.ryReport.logicalMinimum<0 THEN
					msg.axis[Joystick.AxisRy] := TwosComplement(joystickState.ry.usageValue,joystickState.ryReport.reportSize);
				ELSE
					msg.axis[Joystick.AxisRy] := joystickState.ry.usageValue;
				END;
			END;
			
			IF joystickState.rz # NIL THEN
				IF joystickState.rzReport.logicalMinimum<0 THEN
					msg.axis[Joystick.AxisRz] := TwosComplement(joystickState.rz.usageValue,joystickState.rzReport.reportSize);
				ELSE
					msg.axis[Joystick.AxisRz] := joystickState.rz.usageValue;
				END;
			END;
			
			IF joystickState.slider # NIL THEN
				IF joystickState.sliderReport.logicalMinimum<0 THEN
					msg.axis[Joystick.Slider1] := TwosComplement(joystickState.slider.usageValue,joystickState.sliderReport.reportSize);
				ELSE
					msg.axis[Joystick.Slider1] := joystickState.slider.usageValue;
				END;
			END;
			
			IF joystickState.hatSwitch # NIL THEN
				CASE (joystickState.hatSwitch.usageValue-joystickState.hatSwitchReport.logicalMinimum+1) OF
					1:	msg.coolieHat[0]:= {Joystick.HatUp};
					|2: 	msg.coolieHat[0]:= {Joystick.HatUp}+{Joystick.HatLeft};
					|3:	msg.coolieHat[0]:= {Joystick.HatLeft};
					|4:	msg.coolieHat[0]:= {Joystick.HatLeft}+{Joystick.HatDown};
					|5:	msg.coolieHat[0]:= {Joystick.HatDown};
					|6:	msg.coolieHat[0]:= {Joystick.HatDown}+{Joystick.HatRight};
					|7:	msg.coolieHat[0]:= {Joystick.HatRight};
					|8:	msg.coolieHat[0]:= {Joystick.HatRight}+{Joystick.HatUp};
				ELSE
					
				END;
			END;

			joystickState.joystick.Handle(msg);
		END HandleJoystickDriver;
		
		(** 
		 * checks, whether the device sends mouse informations or not
		 *)
		PROCEDURE InitializeMouseDriver():BOOLEAN;
		VAR
			mouseCollection	: AosUsbHidReport.HidCollection;
			temp			: AosUsbHidReport.HidReport;
			i				: LONGINT;
			isReportProtocol: BOOLEAN;
		BEGIN
			(*get mouse collection: mouse collection uses UsagePage(Generic Desktop Controlsl)->1 and Usage(Mouse)->2*)
			mouseCollection := reportManager.GetCollection(1,2);
			IF (mouseCollection#NIL) THEN
				NEW(mouseState);
				mouseState.buttonCount := 0;
				FOR i:=0 TO 31 DO
					IF( mouseState.buttonReport = NIL) THEN
						mouseState.buttons[i] := reportManager.GetUsage(UsagePage.ButtonPage, i+1, mouseCollection,mouseState.buttonReport);
					ELSE
						mouseState.buttons[i] := reportManager.GetUsage(UsagePage.ButtonPage, i+1, mouseCollection,temp);
					END;
					IF(mouseState.buttons[i]#NIL) THEN
						mouseState.buttonCount := i;
					END;
					(*AosOut.String("mouseState.buttons ["); AosOut.Int(i,0); AosOut.String("] is "); 
					AosOut.Int(SYSTEM.VAL(LONGINT, mouseState.buttons[i]),0); AosOut.Ln;*)
				END;
				mouseState.x := reportManager.GetUsage(UsagePage.GenericDesktopPage, 30H, mouseCollection,mouseState.axisReport);
				IF(mouseState.x=NIL) THEN
					AosOut.String("Initialize mouse driver: error did not find x axis"); AosOut.Ln;
				END;
				IF(mouseState.axisReport=NIL) THEN
					AosOut.String("InitializeMouseDriver: Error: Did not find axis report"); AosOut.Ln;
				END;
				mouseState.y 		:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 31H, mouseCollection,temp);
				IF(mouseState.y=NIL) THEN
					AosOut.String("Initialize mouse driver: error did not find y axis"); AosOut.Ln;
				END;
				mouseState.wheel	:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 38H, mouseCollection,mouseState.wheelReport);
				IF(mouseState.wheel=NIL) THEN
					AosOut.String("Initialize mouse driver: warning did not find wheel"); AosOut.Ln;
				END;
				IF Trace THEN
					AosOut.String("Found Mouse Configuration"); AosOut.Ln;
					AosOut.String("Mouse Driver initialized");AosOut.Ln;
				END;
				isReportProtocol := SetReportProtocol();
				RETURN TRUE;
			ELSE
				RETURN FALSE;
			END;
		END InitializeMouseDriver;
		
		(** 
		 * checks, whether the device sends keyboard informations or not
		 *)
		PROCEDURE InitializeKeyboardDriver():BOOLEAN;
		VAR
			keyboardColl: AosUsbHidReport.HidCollection;
			aUsageTuple : AosUsbHidReport.UsageTuple;
			modifierReport: AosUsbHidReport.HidReport;
			keycodeReport: AosUsbHidReport.HidReport;
		BEGIN
			keyboardColl:= reportManager.GetCollection(UsagePage.GenericDesktopPage,UsagePage.KeyboardPage);
			IF(keyboardColl#NIL) THEN
				IF ~SetIdle(0,10) THEN
					IF Debug THEN AosOut.String("AosUsbKeyboard: Error: Cannot set idle the keyboard."); AosOut.Ln; END;
				END;
				NEW(keyboardState);
				keyboardState.Init;
				
				aUsageTuple:= reportManager.GetUsage(UsagePage.KeypadPage, 224, 
						keyboardColl, modifierReport);
				IF (modifierReport=NIL) THEN 
					IF Debug THEN AosOut.String("Error did not find modifier"); AosOut.Ln; END;
					keyboardState := NIL;
					RETURN FALSE;
				ELSE
					IF (modifierReport.usages=NIL) THEN 
						IF Debug THEN AosOut.String("Error did not find modifiers usages"); AosOut.Ln; END;
						keyboardState := NIL;
						RETURN FALSE; 
					ELSE
						IF (LEN(modifierReport.usages)<8) THEN
							keyboardState := NIL;
							RETURN FALSE;
						END;
					END;
					keyboardState.modifierUsages := modifierReport.usages;
				END;
				
				(*assume that the keycodes always begin at usage 0*)
				aUsageTuple:= reportManager.GetUsage(UsagePage.KeypadPage, 0,
						keyboardColl, keycodeReport);
				IF(keycodeReport=NIL) THEN 
					IF Debug THEN AosOut.String("Error did not find keycodeReport"); AosOut.Ln; END;
					keyboardState := NIL;
					RETURN FALSE; 
				ELSE
					IF(keycodeReport.usages=NIL) THEN 
						keyboardState := NIL;
						IF Debug THEN AosOut.String("Error did not find keycodeReports usages"); AosOut.Ln; END;
						RETURN FALSE;
					(*ELSE
						IF (LEN(modifierReport.usages)<8) THEN
							keyboardState := NIL;
							RETURN FALSE;
						END;*)
					END;
				END;
				keyboardState.keycodeUsages := keycodeReport.usages;
				keyboardState.SetMaxKeycodes(LEN(keycodeReport.usages));
				RETURN SetReportProtocol();
			ELSE
				RETURN FALSE;
			END;
		END InitializeKeyboardDriver;
		
		(** 
		 * checks, whether the device sends consumer informations or not
		 *)
		PROCEDURE InitializeConsumerDriver():BOOLEAN;
		VAR
			consumerColl	: AosUsbHidReport.HidCollection;
			temp			: AosUsbHidReport.HidReport;
			usageCounter	: LONGINT;
		BEGIN
			consumerColl := reportManager.GetCollection(UsagePage.ConsumerPage, 1H);
			IF consumerColl # NIL THEN
				NEW(consumerState);
				consumerState.consumerReport := consumerColl.firstReport;
				IF consumerState.consumerReport # NIL THEN
					temp := consumerState.consumerReport;
					WHILE (temp # NIL) DO
							usageCounter := usageCounter + temp.reportCount;
						temp := temp.next;
					END;
					temp := consumerState.consumerReport;
					RETURN TRUE;
				ELSE
					consumerState := NIL;
				END;
			END;
			RETURN FALSE;
		END InitializeConsumerDriver;
		
		(** 
		 * checks, whether the device sends joystick informations or not
		 *)
		 PROCEDURE InitializeJoystickDriver():BOOLEAN;
		VAR
			joystickColl		: AosUsbHidReport.HidCollection;
			temp			: AosUsbHidReport.HidReport;
			res,i			: LONGINT;
		BEGIN
			(*get joystick collection: joystick collection uses UsagePage(Generic Desktop Controlsl)->1 and Usage(Joystick)->4*)
			joystickColl := reportManager.GetCollection(UsagePage.GenericDesktopPage,4);
			IF (joystickColl#NIL) THEN
				NEW(joystickState);
				joystickState.buttonCount := 0;
				FOR i:=0 TO 31 DO
					IF( joystickState.buttonReport = NIL) THEN
						joystickState.buttons[i] := reportManager.GetUsage(UsagePage.ButtonPage, i+1, joystickColl,joystickState.buttonReport);
						(*AosOut.String("Found button report"); AosOut.Ln;*)
					ELSE
						joystickState.buttons[i] := reportManager.GetUsage(UsagePage.ButtonPage, i+1, joystickColl,temp);
					END;
					IF(joystickState.buttons[i]#NIL) THEN
						joystickState.buttonCount := joystickState.buttonCount +1;
						(*AosOut.String(" button "); 
						AosOut.Int(joystickState.buttonReport.usages[i].usageID,0);  AosOut.Ln;*)
					END;
				END;
				
				IF Debug THEN
					AosOut.String("Found Joystick Configuration"); AosOut.Ln;
				END;
				
				NEW(joystickState.joystick,joystickState.buttonCount);
				joystickState.joystick.desc := "USBHIDJoystick";
				
				joystickState.x := reportManager.GetUsage(UsagePage.GenericDesktopPage, 30H, joystickColl,joystickState.xReport);
				IF(joystickState.x#NIL) THEN
					joystickState.joystick.AddAxis(Joystick.AxisX, joystickState.xReport.logicalMinimum, joystickState.xReport.logicalMaximum);
				END;
				
				joystickState.y 		:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 31H, joystickColl,joystickState.yReport);
				IF(joystickState.y#NIL) THEN
					joystickState.joystick.AddAxis(Joystick.AxisY, joystickState.yReport.logicalMinimum, joystickState.yReport.logicalMaximum);
				END;
				
				joystickState.z 		:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 32H, joystickColl,joystickState.zReport);
				IF(joystickState.z#NIL) THEN
					joystickState.joystick.AddAxis(Joystick.AxisZ, joystickState.zReport.logicalMinimum, joystickState.zReport.logicalMaximum);
				END;
				
				joystickState.rx 		:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 33H, joystickColl,joystickState.rxReport);
				IF(joystickState.rx#NIL) THEN
					joystickState.joystick.AddAxis(Joystick.AxisRx, joystickState.rxReport.logicalMinimum, joystickState.rxReport.logicalMaximum);
				END;
				
				joystickState.ry 		:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 34H, joystickColl,joystickState.ryReport);
				IF(joystickState.ry#NIL) THEN
					joystickState.joystick.AddAxis(Joystick.AxisRy, joystickState.ryReport.logicalMinimum, joystickState.ryReport.logicalMaximum);
				END;
				
				joystickState.rz 		:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 35H, joystickColl,joystickState.rzReport);
				IF(joystickState.rz#NIL) THEN
					joystickState.joystick.AddAxis(Joystick.AxisRz, joystickState.rzReport.logicalMinimum, joystickState.rzReport.logicalMaximum);
				END;
				
				joystickState.slider	:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 36H, joystickColl,joystickState.sliderReport);
				IF(joystickState.slider#NIL) THEN
					joystickState.joystick.AddAxis(Joystick.Slider1, joystickState.sliderReport.logicalMinimum, joystickState.sliderReport.logicalMaximum);
				END;
				
				joystickState.hatSwitch:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 39H, joystickColl,joystickState.hatSwitchReport);
				IF(joystickState.hatSwitch#NIL) THEN
					IF (joystickState.hatSwitchReport.logicalMaximum-joystickState.hatSwitchReport.logicalMinimum=7) THEN
						joystickState.joystick.AddCoolieHat();
					ELSE
						AosOut.String("HatSwitch found, but not compatible. HatSwitch events are not sent to AosJoysticks.."); AosOut.Ln;
					END;
				END;
				
				Joystick.registry.Add(joystickState.joystick,res);
				RETURN TRUE;
			ELSE
				RETURN FALSE;
			END;
		END InitializeJoystickDriver;
		
		(** 
		 * Reads bitlen bits from a position index
		 * @param index[in bits]: where to start reading [1..32]
		 * @param bitLen: the amount of bits to read
		 * @return value
		 *)
		 PROCEDURE ReadBits(index, bitLen: LONGINT):LONGINT;
		VAR rv : LONGINT;
		BEGIN
			rv := ReadBitsBuffer(index,bitLen,reportBuffer);
			RETURN rv;
		END ReadBits;
		
		 (** 
		 * Reads bitlen bits from a position index
		 * @param index[in bits]: where to start reading [1..32]
		 * @param bitLen: the amount of bits to read
		 * @param localBuf: the buffer to read from
		 * @return value
		 *)
		PROCEDURE ReadBitsBuffer(index, bitLen: LONGINT; localBuf: AosUsbdi.BufferPtr):LONGINT;
		VAR
			endIndex	: LONGINT;
			rv			: LONGINT;
			temp		: LONGINT;
			indexEightAligned : LONGINT;
			bitsToShift	: LONGINT;
			set			: SET;
		BEGIN
			endIndex := index + bitLen-1;
			
			IF bitLen<=0 THEN RETURN 0 END;
			
			IF Debug THEN AosOut.String("read bits from "); AosOut.Int(index,0); AosOut.String(" to "); AosOut.Int(endIndex,0); AosOut.Ln; END;
			
			IF(endIndex>=(8*LEN(localBuf))) THEN
				IF Debug THEN AosOut.String("ReadBits: Buffer overflow, endindex is out of localBuf"); AosOut.Ln; END;
				RETURN 0;
			END;
			
			IF (bitLen=1) THEN
				(*simply get the bit*)
				set := SYSTEM.VAL(SET, localBuf[index DIV 8]);
				IF (index MOD 8) IN set THEN
					rv := 1;
				ELSE
					rv := 0;
				END;
				RETURN rv;
			END;
			
			IF ((index DIV 8) = (endIndex DIV 8)) THEN
				(*detect reading simple byte*)
				
				temp := SYSTEM.VAL(LONGINT, ORD(localBuf[index DIV 8]));
				
				IF (bitLen=8) THEN
					rv:= temp;
					IF Debug THEN
						AosOut.String("the byte value is: "); AosOut.Int(rv,0); AosOut.Ln;
					END;
					RETURN rv;
				ELSE
					(*simply read in the byte index DIV 8*)
					IF Debug THEN
						AosOut.Ln;
						AosOut.String("       the value of the byte is: "); AosOut.Int(temp,0); AosOut.Ln;
						AosOut.String(" (");AosOut.Bits(SYSTEM.VAL(SET, temp),0,8); AosOut.String(")"); AosOut.Ln;
						AosOut.String("       read in the byte from "); AosOut.Int(index MOD 8,0); AosOut.String(" to ");
						AosOut.Int(endIndex MOD 8,0); AosOut.String(")"); AosOut.Ln;
					END;
					
					temp := SYSTEM.VAL(LONGINT,(SYSTEM.VAL(SET, temp) * {(index MOD 8)..(endIndex MOD 8)}));
					IF Debug THEN
						AosOut.String("        the value of the byte after masking: "); AosOut.Bits(SYSTEM.VAL(SET, temp),0,8); AosOut.Ln;
					END;
					
					bitsToShift := index MOD 8;
					IF Debug THEN
						AosOut.String("        bits to shift: "); AosOut.Int(bitsToShift,0); AosOut.Ln;
					END;
					
					rv := SYSTEM.VAL(LONGINT,SYSTEM.LSH(SYSTEM.VAL(CHAR,temp),-bitsToShift));
					
					IF Debug THEN
						AosOut.String("        the value of the byte after shifting: "); AosOut.Bits(SYSTEM.VAL(SET, rv),0,8); AosOut.Ln;
					END;
					
				END;
			ELSE
				(* the index and the endIndex are not in the same byte
					
					block position k of index is k="index DIV 8"
					so endBit in the same block is   eb=k * 8 + 7
					ex: given: index := 27;
					asked:	how many bits to shift the current rv to left
							
							k := 27 div 8
							k := 3;
							eb := 3 * 8 + 7= 31
							
				*)
				indexEightAligned := SYSTEM.VAL(LONGINT,SYSTEM.VAL(SET,index)+{0..2});
				
				IF Debug THEN
					AosOut.String("index, indexEightAligned, endIndex");
					AosOut.Int(index,6);AosOut.Int(indexEightAligned,6);AosOut.Int(endIndex,6); AosOut.Ln;
				END;
				
				temp := ReadBitsBuffer(indexEightAligned+1,endIndex-indexEightAligned, localBuf);
				temp := SYSTEM.LSH(temp,indexEightAligned-index+1);
				rv := temp + ReadBitsBuffer(index, indexEightAligned-index+1,localBuf);
			END;
			RETURN rv;
		END ReadBitsBuffer;
		
		(** 
		 * for testing the readBits Procedure
		 
		PROCEDURE TestReader;
		VAR
			myBuf:	AosUsbdi.BufferPtr;
			test:	LONGINT;
		BEGIN
			NEW(myBuf,8);
			
			myBuf[0] := CHR(5H);
			myBuf[1] := CHR(7H);
			myBuf[2] := CHR(55H);
			myBuf[3] := CHR(3H);
			myBuf[4] := CHR(5H);
			myBuf[5] := CHR(7H);
			myBuf[6] := CHR(0FFH);
			myBuf[7] := CHR(0FFH);
			
			
			AosOut.Ln;
			AosOut.String("Initialize TestReader"); AosOut.Ln;
			
			AosOut.String("myBuf[0]: "); AosOut.Int(SYSTEM.VAL(LONGINT,ORD(myBuf[0])),0); AosOut.Ln;
			AosOut.String("myBuf[1]: "); AosOut.Int(SYSTEM.VAL(LONGINT,ORD(myBuf[1])),0); AosOut.Ln;
			AosOut.String("myBuf[2]: "); AosOut.Int(SYSTEM.VAL(LONGINT,ORD(myBuf[2])),0); AosOut.Ln;
			AosOut.String("myBuf[3]: "); AosOut.Int(SYSTEM.VAL(LONGINT,ORD(myBuf[3])),0); AosOut.Ln;
			AosOut.String("myBuf[4]: "); AosOut.Int(SYSTEM.VAL(LONGINT,ORD(myBuf[4])),0); AosOut.Ln;
			AosOut.String("myBuf[5]: "); AosOut.Int(SYSTEM.VAL(LONGINT,ORD(myBuf[5])),0); AosOut.Ln;
			AosOut.String("myBuf[6]: "); AosOut.Int(SYSTEM.VAL(LONGINT,ORD(myBuf[6])),0); AosOut.Ln;
			AosOut.String("myBuf[7]: "); AosOut.Int(SYSTEM.VAL(LONGINT,ORD(myBuf[7])),0); AosOut.Ln;
			
			IF FALSE THEN
			AosOut.Ln;
			AosOut.String("Starting Testcases"); AosOut.Ln;	
			AosOut.String("Reading every bit from myBuf[0]: "); AosOut.Bits(SYSTEM.VAL(SET,myBuf[0]),0,8); AosOut.Ln;		
			AosOut.String("    Read 1 bit from 0:  "); AosOut.Int(ReadBitsBuffer(0,1,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 1 bit from 1:  "); AosOut.Int(ReadBitsBuffer(1,1,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 1 bit from 2:  "); AosOut.Int(ReadBitsBuffer(2,1,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 1 bit from 3:  "); AosOut.Int(ReadBitsBuffer(3,1,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 1 bit from 4:  "); AosOut.Int(ReadBitsBuffer(4,1,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 1 bit from 5:  "); AosOut.Int(ReadBitsBuffer(5,1,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 1 bit from 6:  "); AosOut.Int(ReadBitsBuffer(6,1,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 1 bit from 7:  "); AosOut.Int(ReadBitsBuffer(7,1,myBuf),0); AosOut.Ln;
			AosOut.Ln;
			
			
			AosOut.String("Reading 1-8 bits from myBuf[1]: "); AosOut.Bits(SYSTEM.VAL(SET,myBuf[1]),0,8); AosOut.Ln;		
			AosOut.String("    Read 1 bits from 8:  "); AosOut.Int(ReadBitsBuffer(8,1,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 2 bits from 8:  "); AosOut.Int(ReadBitsBuffer(8,2,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 3 bits from 8:  "); AosOut.Int(ReadBitsBuffer(8,3,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 4 bits from 8:  "); AosOut.Int(ReadBitsBuffer(8,4,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 5 bits from 8:  "); AosOut.Int(ReadBitsBuffer(8,5,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 6 bits from 8:  "); AosOut.Int(ReadBitsBuffer(8,6,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 7 bits from 8:  "); AosOut.Int(ReadBitsBuffer(8,6,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 8 bits from 8:  "); AosOut.Int(ReadBitsBuffer(8,8,myBuf),0); AosOut.Ln;
			AosOut.Ln;
			
			AosOut.String("Reading 1-7 bits from myBuf[2]: "); AosOut.Bits(SYSTEM.VAL(SET,myBuf[2]),0,8); AosOut.Ln;		
			AosOut.String("    Read 1 bit   from 17:  "); AosOut.Int(ReadBitsBuffer(17,1,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 2 bits from 17:  "); AosOut.Int(ReadBitsBuffer(17,2,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 3 bits from 17:  "); AosOut.Int(ReadBitsBuffer(17,3,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 4 bits from 17:  "); AosOut.Int(ReadBitsBuffer(17,4,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 5 bits from 17:  "); AosOut.Int(ReadBitsBuffer(17,5,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 6 bits from 17:  "); AosOut.Int(ReadBitsBuffer(17,6,myBuf),0); AosOut.Ln;
			AosOut.String("    Read 7 bits from 17:  "); AosOut.Int(ReadBitsBuffer(17,6,myBuf),0); AosOut.Ln;
			AosOut.Ln;
			
			
			AosOut.String("Read 8 bits from 0:  "); AosOut.Int(ReadBitsBuffer(0,8,myBuf),0); AosOut.Ln;
			AosOut.String("Read 9 bits from 0:  "); AosOut.Int(ReadBitsBuffer(0,9,myBuf),0); AosOut.Ln;
			AosOut.String("Read 10 bits from 0:  "); AosOut.Int(ReadBitsBuffer(0,10,myBuf),0); AosOut.Ln;
			AosOut.String("Read 11 bits from 0:  "); AosOut.Int(ReadBitsBuffer(0,11,myBuf),0); AosOut.Ln;
			AosOut.String("Read 12 bits from 0:  "); AosOut.Int(ReadBitsBuffer(0,12,myBuf),0); AosOut.Ln;
			AosOut.String("Read 13 bits from 0:  "); AosOut.Int(ReadBitsBuffer(0,13,myBuf),0); AosOut.Ln;
			AosOut.String("Read 14 bits from 0:  "); AosOut.Int(ReadBitsBuffer(0,14,myBuf),0); AosOut.Ln;
			AosOut.Ln;
			
			AosOut.String("Read 7 bits from 1:  "); AosOut.Int(ReadBitsBuffer(1,7,myBuf),0); AosOut.Ln;
			AosOut.String("Read 8 bits from 1:  "); AosOut.Int(ReadBitsBuffer(1,8,myBuf),0); AosOut.Ln;
			AosOut.String("Read 9 bits from 1:  "); AosOut.Int(ReadBitsBuffer(1,9,myBuf),0); AosOut.Ln;
			AosOut.String("Read 10 bits from 1:  "); AosOut.Int(ReadBitsBuffer(1,10,myBuf),0); AosOut.Ln;
			AosOut.String("Read 11 bits from 1:  "); AosOut.Int(ReadBitsBuffer(1,11,myBuf),0); AosOut.Ln;
			AosOut.String("Read 12 bits from 1:  "); AosOut.Int(ReadBitsBuffer(1,12,myBuf),0); AosOut.Ln;
			AosOut.String("Read 13 bits from 1:  "); AosOut.Int(ReadBitsBuffer(1,13,myBuf),0); AosOut.Ln;
			AosOut.Ln;
			
			AosOut.String("Read 8 bits from 32:  "); AosOut.Int(ReadBitsBuffer(32,8,myBuf),0); AosOut.Ln;
			AosOut.String("Read 9 bits from 32:  "); AosOut.Int(ReadBitsBuffer(32,9,myBuf),0); AosOut.Ln;
			AosOut.String("Read 10 bits from 32:  "); AosOut.Int(ReadBitsBuffer(32,10,myBuf),0); AosOut.Ln;
			AosOut.String("Read 11 bits from 32:  "); AosOut.Int(ReadBitsBuffer(32,11,myBuf),0); AosOut.Ln;
			AosOut.String("Read 12 bits from 32:  "); AosOut.Int(ReadBitsBuffer(32,12,myBuf),0); AosOut.Ln;
			AosOut.String("Read 13 bits from 23:  "); AosOut.Int(ReadBitsBuffer(32,13,myBuf),0); AosOut.Ln;
			AosOut.String("Read 14 bits from 32:  "); AosOut.Int(ReadBitsBuffer(32,14,myBuf),0); AosOut.Ln;
			AosOut.Ln;
			
			AosOut.String("Read 7 bits from 33:  "); AosOut.Int(ReadBitsBuffer(33,7,myBuf),0); AosOut.Ln;
			AosOut.String("Read 8 bits from 33:  "); AosOut.Int(ReadBitsBuffer(33,8,myBuf),0); AosOut.Ln;
			AosOut.String("Read 9 bits from 33:  "); AosOut.Int(ReadBitsBuffer(33,9,myBuf),0); AosOut.Ln;
			AosOut.String("Read 10 bits from 33:  "); AosOut.Int(ReadBitsBuffer(33,10,myBuf),0); AosOut.Ln;
			AosOut.String("Read 11 bits from 33:  "); AosOut.Int(ReadBitsBuffer(33,11,myBuf),0); AosOut.Ln;
			AosOut.String("Read 12 bits from 33:  "); AosOut.Int(ReadBitsBuffer(33,12,myBuf),0); AosOut.Ln;
			AosOut.String("Read 13 bits from 33:  "); AosOut.Int(ReadBitsBuffer(33,13,myBuf),0); AosOut.Ln;
			AosOut.Ln;
			END;
			AosOut.String("TwosComplement of 6 in (4 Bits): "); AosOut.Int(TwosComplement(6,4),0); AosOut.Ln;
			AosOut.String("TwosComplement of 7 in (4 Bits): "); AosOut.Int(TwosComplement(7,4),0); AosOut.Ln;
			AosOut.String("TwosComplement of 8 in (4 Bits): "); AosOut.Int(TwosComplement(8,4),0); AosOut.Ln;
			AosOut.String("TwosComplement of 13 in (4 Bits): "); AosOut.Int(TwosComplement(13,4),0); AosOut.Ln;
			AosOut.String("TwosComplement of 14 in (4 Bits): "); AosOut.Int(TwosComplement(14,4),0); AosOut.Ln;
			AosOut.String("TwosComplement of 15 in (4 Bits): "); AosOut.Int(TwosComplement(15,4),0); AosOut.Ln;
			AosOut.String("TwosComplement of 15 in (5 Bits): "); AosOut.Int(TwosComplement(15,5),0); AosOut.Ln;
			AosOut.String("TwosComplement of 16 in (5 Bits): "); AosOut.Int(TwosComplement(16,5),0); AosOut.Ln;
			AosOut.String("TwosComplement of 28 in (5 Bits): "); AosOut.Int(TwosComplement(28,5),0); AosOut.Ln;
			AosOut.String("TwosComplement of 29 in (5 Bits): "); AosOut.Int(TwosComplement(29,5),0); AosOut.Ln;
			AosOut.String("TwosComplement of 30 in (5 Bits): "); AosOut.Int(TwosComplement(30,5),0); AosOut.Ln;
			AosOut.String("TwosComplement of 31 in (5 Bits): "); AosOut.Int(TwosComplement(31,5),0); AosOut.Ln;
			AosOut.Ln;
			
			test := ReadBitsBuffer(48,12, myBuf);
			AosOut.String("Reading 12 Bits at block 6 (starting at 48, 12 bits: "); AosOut.Int(test,0); AosOut.Ln;
			AosOut.String("      ?= 4095. Twos Complement should be -1: "); AosOut.Int(TwosComplement(test,12),0); AosOut.Ln;
			
			test := ReadBitsBuffer(49,12, myBuf);
			AosOut.String("Reading 12 Bits at block 6 (starting at 49, 12 bits: "); AosOut.Int(test,0); AosOut.Ln;
			AosOut.String("      ?= 4095. Twos Complement should be -1: "); AosOut.Int(TwosComplement(test,12),0); AosOut.Ln;
			
			
		END TestReader;
		*)
		
		(** 
		 * returns the twos complement of a value by the predicted bitLen
		 * @param value: the value to convert
		 * @param bitLen: the bit length of the value it can have
		 * @return twos complement of value
		 *)
		PROCEDURE TwosComplement(value: LONGINT; bitLen: LONGINT) : LONGINT;
		VAR toMuch : LONGINT;
		BEGIN
			IF(bitLen<32) & (bitLen>0) THEN
				IF ((bitLen-1) IN SYSTEM.VAL(SET,value)) THEN
					toMuch:= SYSTEM.VAL(LONGINT,{bitLen});
					value := value - toMuch;
				END;
			END;
			RETURN value;
		END TwosComplement;
		
		(** 
		 * Sets the device into normal mode (report protocol mode)
		 *)
		PROCEDURE SetReportProtocol():BOOLEAN;
		VAR
			(*0: if boot protocol, 1: if report protocol*)
			bootFlag:	LONGINT;
		BEGIN
			IF (GetProtocol(bootFlag)) THEN
				IF(bootFlag=0) THEN
					IF Debug THEN
						AosOut.String("AosUsbHidDriver:HidDriver.Connect: GetProtocol returned boot protocol, set to report protocol"); AosOut.Ln;
					END;
					IF(SetProtocol(1)=FALSE) THEN
						AosOut.String("AosUsbHidDriver:HidDriver.Connect: SetProtocol to report failed"); AosOut.Ln;
						RETURN FALSE;
					END;
				ELSE
					IF Debug THEN
						AosOut.String("AosUsbHidDriver:HidDriver.Connect: GetProtocol returned report protocol"); AosOut.Ln;
					END;
				END;
			END;
			RETURN TRUE;
		END SetReportProtocol;
		
	END HidDriver;

(*used for debug output. lists the report descriptor as described in Device Class Definition for Human Interface Devices, 
	f.e. page 61 Appendix A, B.2 Protocol 2 (Mouse)*)
PROCEDURE LayoutBuffer*(buf : AosUsbdi.Buffer;  len : LONGINT);
VAR temp : LONGINT; 
BEGIN
	AosOut.String("Buffer Outline:"); AosOut.Ln;
	FOR temp := 0 TO len-1 DO
		IF (temp MOD 2 = 0) THEN 
			AosOut.Ln();
			AosOut.Int(temp, 4);
			AosOut.String("    ");
			AosOut.Hex(ORD(buf[temp]), -2);
		ELSE
			AosOut.String("    ");
			AosOut.Hex(ORD(buf[temp]), -2);
		END;
	END;
	AosOut.Ln(); AosOut.Ln();
END LayoutBuffer;

(*check, whether the device is a hid device
 *	return 	HidDriver, if hid device found, NIL otherwise
 *)
PROCEDURE Probe(dev : AosUsbdi.UsbDevice; if : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR hidDriver : HidDriver;
BEGIN
	IF if.bInterfaceClass # 3 THEN RETURN NIL END;	
	NEW(hidDriver);
	RETURN hidDriver;
END Probe;

(* Called, when detaching the AosUsbHidDriver *)
PROCEDURE Cleanup;
BEGIN
	AosUsbdi.drivers.Remove(Name);
END Cleanup;

PROCEDURE Install*(ptr : PTR): PTR;
BEGIN
	RETURN NIL;
END Install;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	AosUsbdi.drivers.Add(Probe, Name, Description, 10);
END AosUsbHidDriver.

AosUsbHidDriver.Install ~  S.Free AosUsbHidDriver AosUsbHidParser AosUsbHidErrors AosUsbHidParserExt AosUsbHidReport AosUsbHidUP~
