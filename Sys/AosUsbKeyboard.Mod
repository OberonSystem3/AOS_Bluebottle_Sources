MODULE AosUsbKeyboard; (** AUTHOR "cplattner; staubesv"; PURPOSE "Bluebottle USB Keyboard Driver" *) (** non-portable **)
(**
 * Bluebottle USB Keyboard Driver (HID boot protocol)
 *
 * Usage:
 *
 *	AosUsbKeyboard.Install ~ loads this driver		S.Free AosUsbKeyboard ~ unloads it
 *
 *	AosUsbKeyboard.SetLayout dev file ~ sets the keyboard layout
 * 	AosUsbKeyboard.SetLayout UsbKeyboard00 KeyCH.Bin ~ sets the CH keyboard layout, for example
 *
 * References: 
 *
 *	Device Class Definition for Human Interface Devices (HID), version 1.11
 *	HID Usage Tables, version 1.11
 *	
 *	References are available at http://www.usb.org
 *
 * History:
 *
 *	30.09.2000 	cp first release
 *	18.10.2000 	cp fix size of interrupt endpoint and add warning message if keyboard fails
 *	27.02.2006	Correct handling for modifier keys (also generate event if only a modifier key is pressed) (staubesv)
 *	01.03.2006	Added SetLayout & KeyboardDriver.SetLayout (staubesv)
 *	22.01.2007	Splitted up Keyboard Driver for HID compatibility (ottigerm)
 *)

IMPORT SYSTEM, AosBoot, AosFS, AosInputs, AosCommands, AosOut, AosIO, AosPlugins, AosModules, AosUsb, AosUsbdi, AosUsbHid;

CONST

	Name = "UsbKeyboard";
	Description = "USB Keyboard Driver";
	Priority = 10;
	
	NumLock* = 0;
	CapsLock* = 1;  
	ScrollLock* = 2;  
	(* Compose & kana not yet implemented *)
	Compose = 3; 
	Kana = 4;
	
	(* If you press a key and hold it down, the following will happen:					*)
	(* 1. A AosInputs.KeyboardMsg is sent											*)
	(* 2. No further messages are sent until the period KeyDeadTime expires			*)
	(* 3. Further messages are sent with the interval KeyDeadTimeRepeat				*)
	(*																				*)
	(* A release event is sent when you release the key.								*)
	(* The values KeyDeadTime and KeyDeadTimeRepeat are set in milliseconds. 		*)
	(*																				*)
	KeyDeadTime* = 100;
	KeyDeadTimeRepeat* = 0;  (* 10 <= value < infinity  && value mod 10 = 0 *)
	
	TraceKeys* = FALSE; (* Displays scan code of pressed key on KernelLog if TRUE *)
	Debug* = TRUE;

TYPE

	Key* = RECORD 
		ch* : CHAR;
		keysym* : LONGINT;
		counter* : LONGINT;  
		repeat* : BOOLEAN;
		updated* : BOOLEAN;
	END;
	
TYPE
	
	KeyboardBase*=OBJECT
	VAR
		msg*, lastMsg : AosInputs.KeyboardMsg;
		lastFlags : SET;
		
		numKeyVal : LONGINT;
		deadKey* : LONGINT; 
		dkHack* : LONGINT;  (* deadKey value should persist Release events ... *)
		
		(* Status of NumLock,ScrollLock,CapsLock,Compose & Kana *)
		leds*, lastLeds* : SET; 
		ledBuffer* : AosUsbdi.BufferPtr;
	
		keyboardFileTable : POINTER TO ARRAY OF CHAR;
		keytable* : LONGINT; (* used as pointer to keyboardFileTable[0] *)
	
		keyDeadTime*, keyDeadTimeRepeat* : LONGINT;
	
	
		PROCEDURE HandleKey*(c : CHAR);
		VAR k : LONGINT;
		BEGIN
			(* map USB Usage ID to keysym: Only non-alphanumeric keys are mapped by Keysym()  *)
			msg.keysym := KeySym(c, leds);
			IF TraceKeys THEN AosOut.String("USB Usage ID: "); AosOut.Hex(ORD(c), -3); END;
			(* map USB Usage ID to Oberon key code *)
			SYSTEM.GET(UsbScanTab() + ORD(c), c);
			IF TraceKeys THEN AosOut.String(" -> Oberon key code: "); AosOut.Hex(ORD(c), -3) END;

			IF c = CHR(58) THEN  leds := leds / {CapsLock}; 
			ELSIF c = CHR(69) THEN leds := leds / {NumLock};
			ELSIF c = CHR(70) THEN leds := leds / {ScrollLock};
			ELSE
				k := Translate(msg.flags, leds, c, keytable, deadKey, numKeyVal); 
				IF TraceKeys THEN AosOut.String(" translated into: "); AosOut.Char(CHR(k)); END;
				(* if c is an ASCII character, then map c to keysym *)
				IF (k  >= 1) & (k  <= 126) & (msg.keysym = AosInputs.KsNil)  THEN msg.keysym := k; END;
				IF k >= 0 THEN msg.ch := CHR(k) ELSE msg.ch := 0X END;
				IF TraceKeys THEN
					AosOut.String(" Aos Keysym: "); IF msg.keysym = AosInputs.KsNil THEN AosOut.String("No Key"); ELSE AosOut.Hex(msg.keysym, 9); END;
					AosOut.Ln; ShowFlags(msg.flags, leds); AosOut.Ln;
				END;
				(* build up message for this event *)
				IF (msg.flags # lastMsg.flags) OR (msg.ch # 0X) OR (msg.keysym # AosInputs.KsNil) THEN
					AosInputs.keyboard.Handle(msg);
				END;  
				lastMsg := msg;             
			END;
		END HandleKey;
	
		PROCEDURE HandleModifiers*(flags : SET);
		VAR i : LONGINT;
		BEGIN
			IF flags # lastFlags THEN
				msg.flags := {}; msg.ch := 0X; msg.keysym := AosInputs.KsNil; 
				FOR i := 0 TO MAX(SET) DO
					IF (i IN flags) & ~(i IN lastFlags) THEN (* modifier key pressed for the first time *)
						msg.flags := {i}; msg.keysym := GetModifierKeysym(i);
						AosInputs.keyboard.Handle(msg);
					ELSIF ~(i IN flags) & (i IN lastFlags) THEN (* modifier key released *)
						msg.flags := {AosInputs.Release}; msg.keysym := GetModifierKeysym(i);
						AosInputs.keyboard.Handle(msg);
					END;
				END;
			END;
			lastFlags := flags;
		END HandleModifiers;
		
		PROCEDURE TableFromFile*(name: ARRAY OF CHAR): LONGINT;
		VAR f: AosFS.File; r: AosFS.Rider; len: LONGINT;
		BEGIN
			AosOut.String("AosUsbKeyboard: "); AosOut.String(" Loading layout "); AosOut.String(name); AosOut.Ln;
			f := AosFS.Old(name);
			IF f # NIL THEN
				len := f.Length();
				IF len MOD 4 = 0 THEN
					NEW(keyboardFileTable, len+1);
					f.Set(r, 0); f.ReadBytes(r, keyboardFileTable^, 0, len);
					IF r.res = 0 THEN
						keyboardFileTable[len] := 0FFX;
						RETURN SYSTEM.ADR(keyboardFileTable[0])
					ELSIF Debug THEN AosOut.String("AosUsbKeyboard: TableFromFile: Error: res="); AosOut.Int(r.res, 1); AosOut.Ln;
					END
				ELSIF Debug THEN AosOut.String("AosUsbKeyboard: TableFromFile: Error: len="); AosOut.Int(len, 1); AosOut.Ln;
				END
			ELSIF Debug THEN AosOut.String("AosUsbKeyboard: TableFromFile: Error: File not found."); AosOut.Ln;
			END;
			RETURN -1;
		END TableFromFile;
		
		PROCEDURE SetLayout*(name : ARRAY OF CHAR);
		VAR adr : LONGINT;
		BEGIN
			IF name = "KeyUS.Bin" THEN adr := TableUS();
			ELSE adr := TableFromFile(name);
			END;
			IF adr = -1 THEN (* Leave the current setting *)
			ELSE SYSTEM.PUT(SYSTEM.ADR(keytable), adr); 
			END;
		END SetLayout;
	
	BEGIN
	
	END KeyboardBase;
	
	KeyboardDriver = OBJECT (AosUsbHid.HidDriver)
	VAR
		pipe : AosUsbdi.Pipe;

 		(* buffer[0] : modifier byte					*)
		(* buffer[1] : reserved						*)
		(* buffer[2]-buffer[7] : 6 one byte key codes  	*)
		buffer : AosUsbdi.BufferPtr;
		
		base : KeyboardBase;
		
		(*for keeping the pressed keys in mind*)
		pressed* : ARRAY 6 OF Key;
		
		PROCEDURE &Init;
		BEGIN
			NEW(base);
		END Init;
		
		PROCEDURE EventHandler(status : AosUsbdi.Status; actLen : LONGINT);
		VAR
			i, j : LONGINT;
			c : CHAR;
			modifiers, flags : SET;
			res : BOOLEAN;
			tempPressed : ARRAY 6 OF Key;
			found, kill : BOOLEAN;
		BEGIN
			IF (status=AosUsbdi.Ok) OR ((status = AosUsbdi.ShortPacket) & (actLen >= 8)) THEN 
			
				(* evaluate modifier keys *)
				base.msg.flags := {};
				modifiers := SYSTEM.VAL(SET, buffer[0]);
				IF modifiers * {0} # {} THEN INCL(base.msg.flags, AosInputs.LeftCtrl) END;
				IF modifiers * {1} # {} THEN INCL(base.msg.flags, AosInputs.LeftShift) END;
				IF modifiers * {2} # {} THEN INCL(base.msg.flags, AosInputs.LeftAlt) END;
				IF modifiers * {3} # {} THEN INCL(base.msg.flags, AosInputs.LeftMeta) END; 
				IF modifiers * {4} # {} THEN INCL(base.msg.flags, AosInputs.RightCtrl) END;
				IF modifiers * {5} # {} THEN INCL(base.msg.flags, AosInputs.RightShift) END;
				IF modifiers * {6} # {} THEN INCL(base.msg.flags, AosInputs.RightAlt) END;
				IF modifiers * {7} # {} THEN INCL(base.msg.flags, AosInputs.RightMeta) END; 
				flags := base.msg.flags;

				(* evaluate the six keycodes *)
				FOR i := 2 TO 7 DO
					c := buffer[i];
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
									IF (base.keyDeadTimeRepeat # 0) & (tempPressed[i-2].counter MOD base.keyDeadTimeRepeat # 0) THEN (* don't send key event *) kill := TRUE; END;
								ELSE
									IF tempPressed[i-2].counter MOD base.keyDeadTime # 0 THEN (* don't send key event *) 
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
				    	base.HandleKey(c); 
				    	tempPressed[i-2].keysym := base.msg.keysym; (* base.msg.keysym asigned by HandleKey() ... *)
				    END;
				END; (* FOR LOOP *)
				
				(* update pressed array. generate keyboard.base.msg's for released keys *)
				FOR i := 0 TO 5 DO
					IF (pressed[i].updated = FALSE) & (pressed[i].ch # CHR(0)) THEN (* this key has been released *)
						base.msg.flags := {};
						INCL(base.msg.flags, AosInputs.Release);
						base.msg.ch := pressed[i].ch;
						base.msg.keysym := pressed[i].keysym;
						base.dkHack := base.deadKey;  (* value of deadKey should persist the key release event *)
						base.HandleKey(c);
						base.deadKey := base.dkHack;
					END;
					pressed[i].counter := tempPressed[i].counter;
					pressed[i].ch := tempPressed[i].ch;
					pressed[i].keysym := tempPressed[i].keysym;
					pressed[i].repeat := tempPressed[i].repeat;
					pressed[i].updated := FALSE;
				END;
				
				(* Generate events for modifiers *)
				base.HandleModifiers(flags);
								
				(* update status of the LEDs  of the keyboad if necessary *)
				IF base.lastLeds # base.leds THEN (* LED status has changed *)
					base.ledBuffer[0] := SYSTEM.VAL(CHAR, base.leds); base.lastLeds := base.leds;
					res := SetReport(AosUsbHid.ReportOutput, 0, base.ledBuffer^, 1); (* ignore res *)
				END;
				status := pipe.Transfer(pipe.maxPacketSize, 0, buffer^);
			ELSE
				IF Debug THEN AosOut.String("AosUsbKeyboard: Error. Disabling keyboard "); AosOut.String(name); AosOut.Ln; END;
			END;
		END EventHandler;
		
		PROCEDURE Connect*(): BOOLEAN;
		VAR status : AosUsbdi.Status; endpoint, i : LONGINT; k : ARRAY 32 OF CHAR;
		BEGIN
			IF ~SetProtocol(0) THEN
				IF Debug THEN AosOut.String("AosUsbKeyboard: Error: Cannot set keyboard into boot protocol mode."); AosOut.Ln; END;
				RETURN FALSE
			END;

			IF ~SetIdle(0,10) THEN
				IF Debug THEN AosOut.String("AosUsbKeyboard: Error: Cannot set idle the keyboard."); AosOut.Ln; END;
				RETURN FALSE
			END;
	
			endpoint := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, interface.endpoints[0].bEndpointAddress) * {0,1,2,3,7});
			
			pipe := device.GetPipe(endpoint); 
			IF pipe = NIL THEN 
				IF Debug THEN AosOut.String("AosUsbKeyboard: Could not get pipe."); AosOut.Ln; END;
				RETURN FALSE; 
			END;
					
			(* Get  *)
			AosBoot.GetConfig("Keyboard", k);
			i := -1;
			IF k # "" THEN i := base.TableFromFile(k); END;
			IF i = -1 THEN (* Fallback to default *) i := TableUS(); END;
			SYSTEM.PUT(SYSTEM.ADR(base.keytable), i); 

			(* Apply Numlock boot up state *)
			AosBoot.GetConfig("NumLock", k); 
			IF k[0] = "1" THEN INCL(base.leds, NumLock) END;
	
			base.keyDeadTime := KeyDeadTime DIV 10; 
			base.keyDeadTimeRepeat := KeyDeadTimeRepeat DIV 10;		
			
			NEW(base.ledBuffer, 1);
			
			NEW(buffer, pipe.maxPacketSize); 
			pipe.SetTimeout(0);
			pipe.SetCompletionHandler(EventHandler);
			status := pipe.Transfer(pipe.maxPacketSize, 0, buffer^); (* ignore status *)
			
			RETURN TRUE;
		END Connect;
	
		PROCEDURE Disconnect*;
		BEGIN
			AosOut.String("AosUsbKeyboard: USB Keyboard disconnected."); AosOut.Ln;
		END Disconnect;

	END KeyboardDriver;
	
VAR

(* Translation table format:  
 *
 *	table = { scancode unshifted-code shifted-code flags }  0FFX .
 *	scancode = <scancode byte from keyboard, bit 7 set for "grey" extended keys>
 *	unshifted-code = <CHAR produced by this scancode, without shift>
 *	shifted-code = <CHAR produced by this scancode, with shift>
 *	flags = <bit-mapped flag byte indicating special behaviour>
 *	
 *	flag bit	function
 *		0	01	DeadKey: Set dead key flag according to translated key code (1-7)
 *		1	02	NumLock: if set, the state of NumLock will reverse the action of shift (for num keypad)
 *		2	04	CapsLock: if set, the state of CapsLock will reverse the action of shift (for alpha keys)
 *		3	08	LAlt:  \ the state of these two flags in the table and the current state of the two...
 *		4	10	RAlt: / ...Alt keys must match exactly, otherwise the search is continued.
 *		5	20	\
 *		6	40	 >  dead key number (0-7), must match current dead key flag
 *		7	80	/
 *	
 *	The table is scanned sequentially (speed not critical).  Ctrl-Break, Ctrl-F10 and Ctrl-Alt-Del
 *	are always defined and are not in the table.   The control keys are also always defined. 
 *)
 
(* TableUS - US keyboard translation table (dead keys: ^=1, '=2, `=3, ~=4, "=5) *)
PROCEDURE TableUS*(): LONGINT;
CODE {SYSTEM.i386}
	CALL L1
L1:
	POP EAX
	ADD EAX,8
	POP EBP
	RET
		(* alphabet *)
	DB 1EX, "a", "A", 4X,	30X, "b", "B", 4X,	2EX, "c", "C", 4X,	20X, "d", "D", 4X
	DB 12X, "e", "E", 4X,	21X, "f", "F", 4X,	22X, "g", "G", 4X,	23X, "h", "H", 4X
	DB 17X, "i", "I", 4X,	24X, "j", "J", 4X,	25X, "k", "K", 4X,	26X, "l", "L", 4X
	DB 32X, "m", "M", 4X,	31X, "n", "N", 4X,	18X, "o", "O", 4X,	19X, "p", "P", 4X
	DB 10X, "q", "Q", 4X,	13X, "r", "R", 4X,	1FX, "s", "S", 4X,	14X, "t", "T", 4X
	DB 16X, "u", "U", 4X,	2FX, "v", "V", 4X,	11X, "w", "W", 4X,	2DX, "x", "X", 4X
	DB 15X, "y", "Y", 4X,	2CX, "z", "Z", 4X
		(* Oberon accents (LAlt & RAlt) *)
(*	DB 1EX, "ä", "Ä", 0CX,	12X, "ë", 0FFX, 0CX,	18X, "ö", "Ö", 0CX,	16X, "ü", "Ü", 0CX
	DB 17X, "ï", 0FFX, 0CX,	1FX, "ß", 0FFX, 0CX,	2EX, "ç", 0FFX, 0CX,	31X, "ñ", 0FFX, 0CX
	DB 1EX, "ä", "Ä", 14X,	12X, "ë", 0FFX, 14X,	18X, "ö", "Ö", 14X,	16X, "ü", "Ü", 14X
	DB 17X, "ï", 0FFX, 14X,	1FX, "ß", 0FFX, 14X,	2EX, "ç", 0FFX, 14X,	31X, "ñ", 0FFX, 14X *)
		(* dead keys (LAlt & RAlt) *)
	DB 07X, 0FFX, 1X, 9X,	28X, 2X, 5X, 9X,	29X, 3X, 4X, 9X,
	DB 07X, 0FFX, 1X, 11X,	28X, 2X, 5X, 11X,	29X, 3X, 4X, 11X,
		(* following keys *)
(*	DB 1EX, "â", 0FFX, 20X,	12X, "ê", 0FFX, 20X,	17X, "î", 0FFX, 20X,	18X, "ô", 0FFX, 20X 
	DB 16X, "û", 0FFX, 20X,	1EX, "à", 0FFX, 60X,	12X, "è", 0FFX, 60X,	17X, "ì", 0FFX, 60X
	DB 18X, "ò", 0FFX, 60X,	16X, "ù", 0FFX, 60X,	1EX, "á", 0FFX, 40X,	12X, "é", 0FFX, 40X
	DB 1EX, "ä", "Ä", 0A4X,	12X, "ë", 0FFX, 0A0X,	17X, "ï", 0FFX, 0A0X,	18X, "ö", "Ö", 0A4X
	DB 16X, "ü", "Ü", 0A4X,	31X, "ñ", 0FFX, 80X *)
		(* numbers at top *)
	DB 0BX, "0", ")", 0X,	02X, "1", "!", 0X,	03X, "2", "@", 0X,	04X, "3", "#", 0X
	DB 05X, "4", "$", 0X,	06X, "5", "%", 0X,	07X, "6", "^", 0X,	08X, "7", "&", 0X
	DB 09X, "8", "*", 0X,	0AX, "9", "(", 0X
		(* symbol keys *)
	DB 28X, "'", 22X, 0X,	33X, ",", "<", 0X,	0CX, "-", "_", 0X,	34X, ".", ">", 0X
	DB 35X, "/", "?", 0X,	27X, ";", ":", 0X,	0DX, "=", "+", 0X,	1AX, "[", "{", 0X
	DB 2BX, "\", "|", 0X,	1BX, "]", "}", 0X,	29X, "`", "~", 0X
		(* control keys *)
	DB 0EX, 7FX, 7FX, 0X (* backspace *)
	DB 0FX, 09X, 09X, 0X (* tab *)
	DB 1CX, 0DX, 0DX, 0X (* enter *)
	DB 39X, 20X, 20X, 0X (* space *)
	DB 01X, 0FEX, 1BX, 0X (* esc *)
		(* keypad *)
	DB 4FX, 0A9X, "1", 2X (* end/1 *)
	DB 50X, 0C2X, "2", 2X (* down/2 *)
	DB 51X, 0A3X, "3", 2X (* pgdn/3 *)
	DB 4BX, 0C4X, "4", 2X (* left/4 *)
	DB 4CX, 0FFX, "5", 2X (* center/5 *)
	DB 4DX, 0C3X, "6", 2X (* right/6 *)
	DB 47X, 0A8X, "7", 2X (* home/7 *)
	DB 48X, 0C1X, "8", 2X (* up/8 *)
	DB 49X, 0A2X, "9", 2X (* pgup/9 *)
	DB 52X, 0A0X, "0", 2X (* insert/0 *)
	DB 53X, 0A1X, 2EX, 2X (* del/. *)
		(* gray keys *)
	DB 4AX, "-", "-", 0X (* gray - *)
	DB 4EX, "+", "+", 0X (* gray + *)
	DB 0B5X, "/", "/", 0X (* gray / *)
	DB 37X, "*", "*", 0X (* gray * *)
	DB 0D0X, 0C2X, 0C2X, 0X (* gray down *)
	DB 0CBX, 0C4X, 0C4X, 0X (* gray left *)
	DB 0CDX, 0C3X, 0C3X, 0X (* gray right *)
	DB 0C8X, 0C1X, 0C1X, 0X (* gray up *)
	DB 09CX, 0DX, 0DX, 0X (* gray enter *)
	DB 0D2X, 0A0X, 0A0X, 0X (* gray ins *)
	DB 0D3X, 0A1X, 0A1X, 0X (* gray del *)
	DB 0C9X, 0A2X, 0A2X, 0X (* gray pgup *)
	DB 0D1X, 0A3X, 0A3X, 0X (* gray pgdn *)
	DB 0C7X, 0A8X, 0A8X, 0X (* gray home *)
	DB 0CFX, 0A9X, 0A9X, 0X (* gray end *)
		(* function keys *)
	DB 3BX, 0A4X, 0FFX, 0X (* F1 *)
	DB 3CX, 0A5X, 0FFX, 0X (* F2 *)
	DB 3DX, 1BX, 0FFX, 0X (* F3 *)
	DB 3EX, 0A7X, 0FFX, 0X (* F4 *)
	DB 3FX, 0F5X, 0FFX, 0X (* F5 *)
	DB 40X, 0F6X, 0FFX, 0X (* F6 *)
	DB 41X, 0F7X, 0FFX, 0X (* F7 *)
	DB 42X, 0F8X, 0FFX, 0X (* F8 *)
	DB 43X, 0F9X, 0FFX, 0X (* F9 *)
	DB 44X, 0FAX, 0FFX, 0X (* F10 *)
	DB 57X, 0FBX, 0FFX, 0X (* F11 *)
	DB 58X, 0FCX, 0FFX, 0X (* F12 *)
	DB 0FFX
END TableUS;

(* maps USB usage ID's to Oberon character code *)
PROCEDURE UsbScanTab*() : LONGINT;
CODE {SYSTEM.i386}
	CALL L1
L1:
	POP EAX
	ADD EAX,8
	POP EBP
	RET
	(* Keyboard table stolen from Linux Usb keyboard driver, and corrected for Oberon *)
	DB 000, 000, 000, 000, 030, 048, 046, 032, 018, 033, 034, 035, 023, 036, 037, 038
	DB 050, 049, 024, 025, 016, 019, 031, 020, 022, 047, 017, 045, 021 ,044, 002, 003
	DB 004, 005, 006, 007, 008, 009, 010, 011, 028, 001, 014, 015 ,057, 012, 013, 026
	DB 027, 043, 043, 039, 040, 041, 051, 052, 053, 058, 059, 060, 061, 062, 063, 064
	DB 065, 066, 067, 068, 087, 088, 099, 070, 119, 210, 199, 201, 211, 207, 209, 205
	DB 203, 208, 200, 069, 181, 055, 074, 078, 156, 079, 080, 081, 075, 076, 077, 071
	DB 072, 073, 082, 083, 086, 127, 116, 117, 085, 089, 090, 091, 092, 093, 094, 095
	DB 120, 121, 122, 123, 134, 138, 130, 132, 128, 129, 131, 137, 133, 135, 136, 113
	DB 115, 114, 000, 000, 000, 000, 000, 124, 000, 000, 000, 000, 000, 000, 000, 000
	DB 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000
	DB 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000
	DB 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000
	DB 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000
	DB 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000, 000
	DB 029, 042, 056, 125, 097, 054, 100, 126, 164, 166, 165, 163, 161, 115, 114, 113
	DB 150, 158, 159, 128, 136, 177, 178, 176, 142, 152, 173, 140, 000, 000, 000, 000
END UsbScanTab;

(* Maps USB key code to X11 keysym (/usr/include/X11/keysymdef.h). *)
PROCEDURE KeySym*(VAR ch : CHAR; VAR leds : SET): LONGINT;
VAR res: LONGINT;
BEGIN
	CASE ch OF
		028X: res := AosInputs.KsReturn (* Return *)
	    	|029X: res := AosInputs.KsEscape (* Escape *)
	    	|02AX: res := AosInputs.KsBackSpace (* Delete (Backspace) *)
	   	|02BX: res := AosInputs.KsTab (* Tab *)
		|03AX: res := AosInputs.KsF1 (* f1 *)
		|03BX: res := AosInputs.KsF2 (* f2 *)
		|03CX: res := AosInputs.KsF3 (* f3 *) 
		|03DX: res := AosInputs.KsF4 (* f4 *)
		|03EX: res := AosInputs.KsF5 (* f5 *)
		|03FX: res := AosInputs.KsF6 (* f6 *)
		|040X: res := AosInputs.KsF7 (* f7 *)
		|041X: res := AosInputs.KsF8 (* f8 *)
		|042X: res := AosInputs.KsF9 (* f9 *)
		|043X: res := AosInputs.KsF10 (* f10 *)
		|044X: res := AosInputs.KsF11 (* f11 *)
		|045X: res := AosInputs.KsF12 (* f12 *)
		|046X: res := AosInputs.KsPrint (* Printscreen *)
		|047X: res := AosInputs.KsScrollLock (* ScrollLock *)
		|048X: res := AosInputs.KsPause (* Pause *)
		|049X: res := AosInputs.KsInsert (* insert *)
		|04AX: res := AosInputs.KsHome (* home *)
		|04BX: res := AosInputs.KsPageUp (* pgup *)
		|04CX: res := AosInputs.KsDelete (* delete *)
		|04DX: res := AosInputs.KsEnd (* end *)
		|04EX: res := AosInputs.KsPageDown (* pgdn *)
		|04FX: res := AosInputs.KsRight (* right *)
		|050X: res := AosInputs.KsLeft (* left *)
		|051X: res := AosInputs.KsDown (* down *)
		|052X: res := AosInputs.KsUp (* up *)
		|053X: res := AosInputs.KsNumLock; (* Keypad NumLock *)
		|054X: res := AosInputs.KsKPDivide (* Keypad / *)
		|055X: res := AosInputs.KsKPMultiply (* Keypad * *)
		|056X: res := AosInputs.KsKPSubtract (* Keypad - *)
		|057X: res := AosInputs.KsKPAdd (* Keypad + *)
		|058X: res := AosInputs.KsReturn (* Keypad Enter: Should be KsKPEnter *)
		|059X: IF ~(NumLock IN leds) THEN res := AosInputs.KsEnd; ELSE res := AosInputs.KsNil END;  (* Keypad 1 and End *)
		|05AX: IF ~(NumLock IN leds) THEN res := AosInputs.KsDown; ELSE res := AosInputs.KsNil END;  (* Keypad 2 and Down Arrow *)
		|05BX: IF ~(NumLock IN leds) THEN res := AosInputs.KsPageDown; ELSE res := AosInputs.KsNil END;  (* Keypad 3 and PageDown *)
		|05CX: IF ~(NumLock IN leds) THEN res := AosInputs.KsLeft; ELSE res := AosInputs.KsNil END;  (* Keypad 4 and Left Arrow *)
		|05DX: IF ~(NumLock IN leds) THEN ch := 0X; res := AosInputs.KsNil; ELSE res := AosInputs.KsNil END; (* don't report key event !! *)
		|05EX: IF ~(NumLock IN leds) THEN res := AosInputs.KsRight; ELSE res := AosInputs.KsNil END;  (* Keypad 6 and Right Arrow *)
		|05FX: IF ~(NumLock IN leds) THEN res := AosInputs.KsHome; ELSE res := AosInputs.KsNil END;  (* Keypad 7 and Home *)
		|060X: IF ~(NumLock IN leds) THEN res := AosInputs.KsUp; ELSE res := AosInputs.KsNil END;  (* Keypad 8 and Up Arrow *)
		|061X: IF ~(NumLock IN leds) THEN res := AosInputs.KsPageUp; ELSE res := AosInputs.KsNil END;  (* Keypad 9 and Page Up *)
		|062X: IF ~(NumLock IN leds) THEN res := AosInputs.KsInsert; ELSE res := AosInputs.KsNil END;  (* Keypad 0 and Insert *)
		|063X: IF ~(NumLock IN leds) THEN res := AosInputs.KsDelete; ELSE res := AosInputs.KsNil END;  (* Keypad . and Delete *)
		|067X:  IF ~(NumLock IN leds) THEN ch := 028X; res := AosInputs.KsKPEnter; ELSE res := AosInputs.KsNil END;  (* Keypad =; remap to KpEnter *)
		|0B0X: ch := 0X; res := AosInputs.KsNil;  (* Keypad 00; don't map *)
		|0B1X: ch := 0X; res := AosInputs.KsNil;  (* Keypad 000; don't map *)		
		|09AX: res := AosInputs.KsSysReq (* SysReq / Attention *)
		|0E0X: res := AosInputs.KsControlL (* Left Control *)
		|0E1X: res := AosInputs.KsShiftL (* Left Shift *)
		|0E2X: res := AosInputs.KsAltL (* Left Alt *)
		|0E3X: res := AosInputs.KsMetaL (* Left GUI *)
		|0E4X: res := AosInputs.KsControlR (* Right Control *)
		|0E5X: res := AosInputs.KsShiftR (* Right Shift *)
		|0E6X: res := AosInputs.KsAltR (* Right Alt *)
		|0E7X: res := AosInputs.KsMetaR (* Right GUI *)
		|076X: res := AosInputs.KsMenu (* Windows Menu *)
		|0FFX: res := AosInputs.KsBreak (* Break *)
	ELSE 
		(* if res=AosInputs.KsNil, the KeySym will be assigned later (see HandleKey) *)
		res := AosInputs.KsNil (* no key *)
	END;
	RETURN res
END KeySym;

PROCEDURE GetModifierKeysym(modifier : LONGINT) : LONGINT;
VAR res : LONGINT;
BEGIN
	CASE modifier OF
		|AosInputs.LeftCtrl: res := AosInputs.KsControlL;
		|AosInputs.LeftShift: res := AosInputs.KsShiftL;
		|AosInputs.LeftAlt: res := AosInputs.KsAltL;
		|AosInputs.LeftMeta: res := AosInputs.KsMetaL;
		|AosInputs.RightCtrl: res := AosInputs.KsControlR;
		|AosInputs.RightShift: res := AosInputs.KsShiftR;
		|AosInputs.RightAlt: res := AosInputs.KsAltR;
		|AosInputs.RightMeta: res := AosInputs.KsMetaR;
	ELSE
		res := AosInputs.KsNil;
	END;
	RETURN res;
END GetModifierKeysym;

(* Translate - Translate scan code "c" to key. *)
PROCEDURE Translate(flags, leds: SET;  c: CHAR; keyboardTable : LONGINT; VAR keyboardDeadKey, keyboardKeyVal : LONGINT): LONGINT;
CONST
	(* The flags stored in the keytable are not the same as the ones defined in AosInputs.
		The parameter flags and leds use the AosInputs constants.
		The constants below are for the use of the flags stored in the keytable (variable s) *)
	OScrollLock = 0;  
	ONumLock = 1;  
	OCapsLock = 2;  
	LAlt = 3;  
	RAlt = 4;
	LCtrl = 5;  
	RCtrl = 6;  
	LShift = 7;  
	RShift = 8;  
	GreyEsc = 9;
	LMeta = 13;
	RMeta = 14;
	Alt = {LAlt, RAlt};  
	Ctrl = {LCtrl, RCtrl};  
	Shift = {LShift, RShift};
	DeadKey = 0;
VAR 
	a: LONGINT;  
	s1: CHAR;  
	s : SET;  
	k: INTEGER;  
	dkn: SHORTINT;
BEGIN
	IF (c = 46X) & (flags * AosInputs.Ctrl # {}) THEN RETURN -2 END;  (* Ctrl-Break - break *)
	IF (c = 44X) & (flags * AosInputs.Ctrl # {}) THEN RETURN 0FFH END;	(* Ctrl-F10 - exit *)
	IF (c = 53X) & (flags * AosInputs.Ctrl # {}) & (flags * AosInputs.Alt # {}) THEN RETURN 0FFH END; (* Ctrl-Alt-Del - exit *)
	
	a := keyboardTable; 
	
	(* this loop linearly searches the keytable for an entry for the character c *)
	LOOP
		SYSTEM.GET(a, s1);
		
		IF s1 = 0FFX THEN (* end of table -> unmapped key *)
		
			(* reset key and dead key state *)
			k := -1;  keyboardDeadKey := 0;  EXIT;
			
		ELSIF s1 = c THEN (* found scan code in table *)
			
			k := 0; 

			SYSTEM.GET(a+3, SYSTEM.VAL(CHAR, s)); (* flags from table *)
			dkn := SHORT(SHORT(SYSTEM.VAL(LONGINT, SYSTEM.LSH(s * {5..7}, -5))));
			
			s := s * {DeadKey, ONumLock, OCapsLock, LAlt, RAlt, LCtrl, RCtrl};  
			
			IF ((s * Alt = SYSTEM.LSH(flags * AosInputs.Alt,-2)) OR (ONumLock IN s) OR (s1>03BX))  & (dkn = keyboardDeadKey) THEN	(* Alt & dead keys match exactly *)
				
				(* check if shift pressed *)
				IF flags * AosInputs.Shift # {} THEN INCL(s, LShift) END;
				
				(* handle CapsLock *)
				IF (OCapsLock IN s) & (CapsLock IN leds) THEN s := s / {LShift} END;
				
				(* handle NumLock *)
				IF ONumLock IN s THEN
					IF flags * AosInputs.Alt # {} THEN INCL(s, LShift)
					ELSIF NumLock IN leds THEN s := s / {LShift}
					END
				END;
				
				(* get key code *)
				IF LShift IN s THEN SYSTEM.GET(a+2, SYSTEM.VAL(CHAR, k))	(* shifted value *)
				ELSE SYSTEM.GET(a+1, SYSTEM.VAL(CHAR, k))	(* unshifted value *)
				END;
				
				IF (DeadKey IN s) & (k <= 7) THEN (* dead key *)
					keyboardDeadKey := SHORT(k);  k := -1	(* set new dead key state *)
				ELSIF k = 0FFH THEN	(* unmapped key *)
					k := -1;  keyboardDeadKey := 0	(* reset dead key state *)
				ELSE	(* mapped key *)
					IF flags * AosInputs.Ctrl # {} THEN
						IF ((k >= 64) & (k <= 95)) OR ((k >= 97) & (k <= 122)) THEN
							k := SHORT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, k) * {0..4}))	(* control *)
						ELSIF k = 13 THEN	(* Ctrl-Enter *)
							k := 10
						END
					END;
					IF flags * AosInputs.Alt # {} THEN	(* Alt-keypad *)
						IF (k >= ORD("0")) & (k <= ORD("9")) & (NumLock IN s) THEN	(* keypad num *)
							IF keyboardKeyVal = -1 THEN keyboardKeyVal := k-ORD("0")
							ELSE keyboardKeyVal := (10*keyboardKeyVal + (k-ORD("0"))) MOD 1000;
							END;
							k := -1
						END
					END;
					keyboardDeadKey := 0	(* reset dead key state *)
				END;
				EXIT
			END
		END;
		INC(a, 4) 
	END; (* LOOP *)
	RETURN k
END Translate;

(* Displays textual representation of the set flags to KernelLog *)
PROCEDURE ShowFlags(flags, leds : SET);
BEGIN
	AosOut.String("Flags: ");
	IF AosInputs.LeftAlt IN flags THEN AosOut.String("[Left Alt]"); END;
	IF AosInputs.RightAlt IN flags THEN AosOut.String("[Right Alt]"); END;
	IF AosInputs.LeftCtrl IN flags THEN AosOut.String("[Left Ctrl]"); END;
	IF AosInputs.RightCtrl IN flags THEN AosOut.String("[Rigth Ctrl]"); END;
	IF AosInputs.LeftShift IN flags THEN AosOut.String("[Left Shift]"); END;
	IF AosInputs.RightShift IN flags THEN AosOut.String("[Right Shift]"); END;
	IF AosInputs.LeftMeta IN flags THEN AosOut.String("[Left Meta]"); END;
	IF AosInputs.RightMeta IN flags THEN AosOut.String("[Rigth Meta]"); END;
	IF AosInputs.Release IN flags THEN AosOut.String("[Released]"); END;
	IF ScrollLock IN leds THEN AosOut.String("[ScrollLock]"); END;
	IF NumLock IN leds THEN AosOut.String("[NumLock]"); END;
	IF CapsLock IN leds THEN AosOut.String("[CapsLock]"); END;
	IF Compose IN leds THEN AosOut.String("[Compose]"); END;
	IF Kana IN leds THEN AosOut.String("[Kana]"); END;
END ShowFlags;

PROCEDURE Probe(dev : AosUsbdi.UsbDevice; if : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR driver : KeyboardDriver;
BEGIN
	IF if.bInterfaceClass # 3 THEN RETURN NIL END; (* HID class *)
	IF if.bInterfaceSubClass # 1 THEN RETURN NIL END; (* Boot protocol subclass *)
	IF if.bInterfaceProtocol # 1 THEN RETURN NIL END; (* Keyboard *)
	IF if.bNumEndpoints # 1 THEN RETURN NIL END;
	AosOut.String("AosUsbKeyboard: USB Keyboard found."); AosOut.Ln;
	NEW(driver);
	RETURN driver;
END Probe;

PROCEDURE SetLayout*(par : ANY) : ANY; (** dev file ~ *)
VAR 
	p : AosCommands.Parameters; r : AosIO.StringReader; string : ARRAY 64 OF CHAR;
	plugin : AosPlugins.Plugin; kd : KeyboardDriver;
BEGIN
	p := par (AosCommands.Parameters);	
	NEW(r, LEN(p.str^)); r.Set(p.str^); 
	r.SkipWhitespace; r.String(string);
	IF (r.res = AosIO.Ok) & (string # "") THEN
		plugin := AosUsb.usbDrivers.Get(string);
		IF plugin # NIL THEN
			IF plugin IS KeyboardDriver THEN
				kd := plugin (KeyboardDriver);
			ELSE AosOut.String("AosUsbKeyboard: Device "); AosOut.String(string); AosOut.String(" is not a keyboard."); AosOut.Ln;
			END;
		ELSE AosOut.String("AosUsbKeyboard: Device "); AosOut.String(string); AosOut.String(" not found."); AosOut.Ln;
		END;
	ELSE AosOut.String("AosUsbKeyboard: Expected <dev> parameter."); AosOut.Ln;
	END;
	IF kd # NIL THEN
		r.SkipWhitespace; r.String(string);
		IF (r.res = AosIO.Ok) & (string # "") THEN
			kd.base.SetLayout(string);
		END;
	END;
	RETURN NIL
END SetLayout;

PROCEDURE Install*(ptr : PTR): PTR;
BEGIN
	RETURN NIL;
END Install;

PROCEDURE Cleanup();
BEGIN
	AosUsbdi.drivers.Remove(Name);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	AosUsbdi.drivers.Add(Probe, Name, Description, Priority);
END AosUsbKeyboard.

AosUsbKeyboard.Install ~ S.Free AosUsbKeyboard ~

AosUsbKeyboard.SetLayout UsbKeyboard00 KeyBE.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyCA.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyCH.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyD.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyDV.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyFR.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyIT.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyN.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyPL.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeySF.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyTR.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyUK.Bin ~
AosUsbKeyboard.SetLayout UsbKeyboard00 KeyUS.Bin ~

WMKeyCode.Open ~	S.Free WMKeyCode ~
