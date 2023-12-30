MODULE AosUsbHidUP; (** AUTHOR "ottigerm"; PURPOSE "HID Items usage pages" *)
(**
 * Bluebottle USB HID Items Usage Pages for Generic Desktop Controls, Keyboard/Keypad and Button
 *
 * This module decodes usages for usage pages:
 *	Generic Desktop Controls 
 *	Keyboard/Keypad
 *	Led
 *	Button
 *	Consumer
 * 
 * References:
 *	USB, HID Usage Tables, 21.01.2005 Version 1.12
 *
 * Overview:
 *	Generic Desktop Controls(01H)	p. HID Usage Tables
 *	Keyboard/Keypad(07H)			p. HID Usage Tables
 *	Led(08H)						p. HID Usage Tables
 *	Button(09H)					p. HID Usage Tables
 *	Consumer(0CH)					p. HID Usage Tables
 * 
 * History:
 *
 *	22.01.2007 Version 1.0
 *)

IMPORT AosOut;

CONST

	(** Usage Pages overtaken from HID Usage Tables*)
	GenericDesktopPage* 	= 01H;
	KeyboardPage*			= 06H;
	KeypadPage*			= 07H; (*Same as KeyboardPage*)
	LedPage*				= 08H;
	ButtonPage* 			= 09H;
	ConsumerPage*			= 0CH;

(* print out the decoded usage for usage page Generic Desktop
 * 	param 	pos, usage of the usage page Generic Desktop
 *)
PROCEDURE PrintGenericDesktop(pos: LONGINT);
BEGIN
	(*Generic Desktop Page (0x01)*)
	CASE pos OF
		|00H: AosOut.String("Undefined" ); 
		|01H: AosOut.String("Pointer" );
		|02H: AosOut.String("Mouse" );
		|03H: AosOut.String("Reserved" );
		|04H: AosOut.String("Joystick" );
		|05H: AosOut.String("Game Pad" );
		|06H: AosOut.String("Keyboard" );
		|07H: AosOut.String("Keypad" );
		|08H: AosOut.String("Multi-axis Controller" );
		|09H: AosOut.String("Tablet PC System Controls" );
		(*|0A-2FH: AosOut.String("Reserved" );*)
		|30H: AosOut.String("X" );
		|31H: AosOut.String("Y" );
		|32H: AosOut.String("Z" );
		|33H: AosOut.String("Rx" );
		|34H: AosOut.String("Ry" );
		|35H: AosOut.String("Rz" );
		|36H: AosOut.String("Slider" );
		|37H: AosOut.String("Dial" );
		|38H: AosOut.String("Wheel" );
		|39H: AosOut.String("Hat switch" );
		|3AH: AosOut.String("Counted Buffer" );
		|3BH: AosOut.String("Byte Count" );
		|3CH: AosOut.String("Motion Wakeup" );
		|3DH: AosOut.String("Start" );
		|3EH: AosOut.String("Select" );
		|3FH: AosOut.String("Reserved" );
		|40H: AosOut.String("Vx" );
		|41H: AosOut.String("Vy" );
		|42H: AosOut.String("Vz" );
		|43H: AosOut.String("Vbrx" );
		|44H: AosOut.String("Vbry" );
		|45H: AosOut.String("Vbrz" );
		|46H: AosOut.String("Vno" );
		|47H: AosOut.String("Feature Notification" );
		|48H: AosOut.String("Resolution Multiplier DV" );
		(*|49-7FH: AosOut.String("Reserved" );*)
		|80H: AosOut.String("System Control" );
		|81H: AosOut.String("System Power Down" );
		|82H: AosOut.String("System Sleep" );
		|83H: AosOut.String("System Wake Up" );
		|84H: AosOut.String("System Context Menu" );
		|85H: AosOut.String("System Main Menu" );
		|86H: AosOut.String("System App Menu" );
		|87H: AosOut.String("System Menu Help" );
		|88H: AosOut.String("System Menu Exit" );
		|89H: AosOut.String("System Menu Select" );
		|8AH: AosOut.String("System Menu Right" );
		|8BH: AosOut.String("System Menu Left" );
		|8CH: AosOut.String("System Menu Up" );
		|8DH: AosOut.String("System Menu Down" );
		|8EH: AosOut.String("System Cold Restart" );
		|8FH: AosOut.String("System Warm Restart" );
		|90H: AosOut.String("D-pad Up" );
		|91H: AosOut.String("D-pad Down" );
		|92H: AosOut.String("D-pad Right" );
		|93H: AosOut.String("D-pad Left" );
		(*|94-9FH: AosOut.String("Reserved" );*)
		|0A0H: AosOut.String("System Dock" );
		|0A1H: AosOut.String("System Undock" );
		|0A2H: AosOut.String("System Setup" );
		|0A3H: AosOut.String("System Break" );
		|0A4H: AosOut.String("System Debugger Break" );
		|0A5H: AosOut.String("Application Break" );
		|0A6H: AosOut.String("Application Debugger Break" );
		|0A7H: AosOut.String("System Speaker Mute" );
		|0A8H: AosOut.String("System Hibernate" );
		(*|A9-AFH: AosOut.String("Reserved" );*)
		|0B0H: AosOut.String("System Display Invert" );
		|0B1H: AosOut.String("System Display Internal" );
		|0B2H: AosOut.String("System Display External" );
		|0B3H: AosOut.String("System Display Both" );
		|0B4H: AosOut.String("System Display Dual" );
		|0B5H: AosOut.String("System Display Toggle Int/Ext" );
		|0B6H: AosOut.String("System Display Swap Primary/Secondary" );
		|0B7H: AosOut.String("System Display LCD Autoscale" );
		ELSE AosOut.String("Reserved");
	END;
END PrintGenericDesktop;

(* Print out the decoded usage for usage page Keyboard 
 * 	param 	pos, usage of the usage page Keyboard 
 *)
PROCEDURE PrintKeyboardPage(pos: LONGINT);
BEGIN
	(*Keyboard/Keypad Page (0x07)*)
	CASE pos OF
		|00H: AosOut.String("Reserved (no event indicated)" );
		|01H: AosOut.String("Keyboard ErrorRollOver" );
		|02H: AosOut.String("Keyboard POSTFail" );
		|03H: AosOut.String("Keyboard ErrorUndefined" );
		|04H: AosOut.String("Keyboard a and A" );
		|05H: AosOut.String("Keyboard b and B" );
		|06H: AosOut.String("Keyboard c and C" );
		|07H: AosOut.String("Keyboard d and D" );
		|08H: AosOut.String("Keyboard e and E" );
		|09H: AosOut.String("Keyboard f and F" );
		|0AH: AosOut.String("Keyboard g and G" );
		|0BH: AosOut.String("Keyboard h and H" );
		|0CH: AosOut.String("Keyboard i and I" );
		|0DH: AosOut.String("Keyboard j and J" );
		|0EH: AosOut.String("Keyboard k and K" );
		|0FH: AosOut.String("Keyboard l and L" );
		|10H: AosOut.String("Keyboard m and M" );
		|11H: AosOut.String("Keyboard n and N" );
		|12H: AosOut.String("Keyboard o and O" );
		|13H: AosOut.String("Keyboard p and P" );
		|14H: AosOut.String("Keyboard q and Q" );
		|15H: AosOut.String("Keyboard r and R" );
		|16H: AosOut.String("Keyboard s and S" );
		|17H: AosOut.String("Keyboard t and T" );
		|18H: AosOut.String("Keyboard u and U" );
		|19H: AosOut.String("Keyboard v and V" );
		|1AH: AosOut.String("Keyboard w and W" );
		|1BH: AosOut.String("Keyboard x and X" );
		|1CH: AosOut.String("Keyboard y and Y" );
		|1DH: AosOut.String("Keyboard z and Z" );
		|1EH: AosOut.String("Keyboard 1 and !" );
		|1FH: AosOut.String("Keyboard 2 and @");
		|20H: AosOut.String("Keyboard 3 and #");
		|21H: AosOut.String("Keyboard 4 and $");
		|22H: AosOut.String("Keyboard 5 and %");
		|23H: AosOut.String("Keyboard 6 and ^");
		|24H: AosOut.String("Keyboard 7 and &");
		|25H: AosOut.String("Keyboard 8 and *");
		|26H: AosOut.String("Keyboard 9 and (");
		|27H: AosOut.String("Keyboard 0 and )" );
		|28H: AosOut.String("Keyboard Return (ENTER)" );
		|29H: AosOut.String("Keyboard ESCAPE" );
		|2AH: AosOut.String("Keyboard DELETE (Backspace)" );
		|2BH: AosOut.String("Keyboard Tab" );
		|2CH: AosOut.String("Keyboard Spacebar" );
		|2DH: AosOut.String("Keyboard - and (underscore)" );
		|2EH: AosOut.String("Keyboard = and +");
		|2FH: AosOut.String("Keyboard [ and {");
		|30H: AosOut.String("Keyboard ] and }");
		|31H: AosOut.String("Keyboard \ and |");
		|32H: AosOut.String("Keyboard Non-US # and ~");
		|33H: AosOut.String("Keyboard ; and :" );
		|34H: AosOut.String("Keyboard ");
		|35H: AosOut.String("Keyboard Grave Accent and Tilde" );
		|36H: AosOut.String("Keyboard, and <");
		|37H: AosOut.String("Keyboard . and >");
		|38H: AosOut.String("Keyboard / and ?" );
		|39H: AosOut.String("Keyboard Caps Lock" );
		|3AH: AosOut.String("Keyboard F1" );
		|3BH: AosOut.String("Keyboard F2" );
		|3CH: AosOut.String("Keyboard F3" );
		|3DH: AosOut.String("Keyboard F4" );
		|3EH: AosOut.String("Keyboard F5" );
		|3FH: AosOut.String("Keyboard F6" );
		|40H: AosOut.String("Keyboard F7" );
		|41H: AosOut.String("Keyboard F8" );
		|42H: AosOut.String("Keyboard F9" );
		|43H: AosOut.String("Keyboard F10" );
		|44H: AosOut.String("Keyboard F11" );
		|45H: AosOut.String("Keyboard F12" );
		|46H: AosOut.String("Keyboard PrintScreen" );
		|47H: AosOut.String("Keyboard Scroll Lock" );
		|48H: AosOut.String("Keyboard Pause" );
		|49H: AosOut.String("Keyboard Insert" );
		|4AH: AosOut.String("Keyboard Home" );
		|4BH: AosOut.String("Keyboard PageUp" );
		|4CH: AosOut.String("Keyboard Delete Forward" );
		|4DH: AosOut.String("Keyboard End" );
		|4EH: AosOut.String("Keyboard PageDown" );
		|4FH: AosOut.String("Keyboard RightArrow" );
		|50H: AosOut.String("Keyboard LeftArrow" );
		|51H: AosOut.String("Keyboard DownArrow" );
		|52H: AosOut.String("Keyboard UpArrow" );
		|53H: AosOut.String("Keypad Num Lock and Clear" );
		|54H: AosOut.String("Keypad /");
		|55H: AosOut.String("Keypad *");
		|56H: AosOut.String("Keypad -");
		|57H: AosOut.String("Keypad +");
		|58H: AosOut.String("Keypad ENTER" );
		|59H: AosOut.String("Keypad 1 and End" );
		|5AH: AosOut.String("Keypad 2 and Down Arrow" );
		|5BH: AosOut.String("Keypad 3 and PageDn" );
		|5CH: AosOut.String("Keypad 4 and Left Arrow" );
		|5DH: AosOut.String("Keypad 5" );
		|5EH: AosOut.String("Keypad 6 and Right Arrow" );
		|5FH: AosOut.String("Keypad 7 and Home" );
		|60H: AosOut.String("Keypad 8 and Up Arrow" );
		|61H: AosOut.String("Keypad 9 and PageU");
		|62H: AosOut.String("Keypad 0 and Insert" );
		|63H: AosOut.String("Keypad . and Delete" );
		|64H: AosOut.String("Keyboard Non-US \ and |");
		|65H: AosOut.String("Keyboard Application" );
		|66H: AosOut.String("Keyboard Power" );
		|67H: AosOut.String("Keypad =");
		|68H: AosOut.String("Keyboard F13" );
		|69H: AosOut.String("Keyboard F14" );
		|6AH: AosOut.String("Keyboard F15" );
		|6BH: AosOut.String("Keyboard F16" );
		|6CH: AosOut.String("Keyboard F17" );
		|6DH: AosOut.String("Keyboard F18" );
		|6EH: AosOut.String("Keyboard F19" );
		|6FH: AosOut.String("Keyboard F20" );
		|70H: AosOut.String("Keyboard F21" );
		|71H: AosOut.String("Keyboard F22" );
		|72H: AosOut.String("Keyboard F23" );
		|73H: AosOut.String("Keyboard F24" );
		|74H: AosOut.String("Keyboard Execute" );
		|75H: AosOut.String("Keyboard Help" );
		|76H: AosOut.String("Keyboard Menu" );
		|77H: AosOut.String("Keyboard Select" );
		|78H: AosOut.String("Keyboard Stop" );
		|79H: AosOut.String("Keyboard Again" );
		|7AH: AosOut.String("Keyboard Undo" );
		|7BH: AosOut.String("Keyboard Cut" );
		|7CH: AosOut.String("Keyboard Copy" );
		|7DH: AosOut.String("Keyboard Paste" );
		|7EH: AosOut.String("Keyboard Find" );
		|7FH: AosOut.String("Keyboard Mute" );
		|80H: AosOut.String("Keyboard Volume Up" );
		|81H: AosOut.String("Keyboard Volume Down" );
		|82H: AosOut.String("Keyboard Locking Caps Lock" );
		|83H: AosOut.String("Keyboard Locking Num Lock" );
		|84H: AosOut.String("Keyboard Locking Scroll Lock" );
		|85H: AosOut.String("Keypad Comma" );
		|86H: AosOut.String("Keypad Equal Sign" );
		|87H: AosOut.String("Keyboard International1" );
		|88H: AosOut.String("Keyboard International2" );
		|89H: AosOut.String("Keyboard International3" );
		|8AH: AosOut.String("Keyboard International4" );
		|8BH: AosOut.String("Keyboard International5" );
		|8CH: AosOut.String("Keyboard International6" );
		|8DH: AosOut.String("Keyboard International7" );
		|8EH: AosOut.String("Keyboard International8" );
		|8FH: AosOut.String("Keyboard International9" );
		|90H: AosOut.String("Keyboard LANG1" );
		|91H: AosOut.String("Keyboard LANG2" );
		|92H: AosOut.String("Keyboard LANG3" );
		|93H: AosOut.String("Keyboard LANG4" );
		|94H: AosOut.String("Keyboard LANG5" );
		|95H: AosOut.String("Keyboard LANG6" );
		|96H: AosOut.String("Keyboard LANG7" );
		|97H: AosOut.String("Keyboard LANG8" );
		|98H: AosOut.String("Keyboard LANG9" );
		|99H: AosOut.String("Keyboard Alternate Erase" );
		|9AH: AosOut.String("Keyboard SysReq/Attention" );
		|9BH: AosOut.String("Keyboard Cancel" );
		|9CH: AosOut.String("Keyboard Clear" );
		|9DH: AosOut.String("Keyboard Prior" );
		|9EH: AosOut.String("Keyboard Return" );
		|9FH: AosOut.String("Keyboard Separator" );
		|0A0H: AosOut.String("Keyboard Out" );
		|0A1H: AosOut.String("Keyboard Oper" );
		|0A2H: AosOut.String("Keyboard Clear/Again" );
		|0A3H: AosOut.String("Keyboard CrSel/Props" );
		|0A4H: AosOut.String("Keyboard ExSel" );
		(*|0A5-CFH: AosOut.String("Reserved" );*)
		|0B0H: AosOut.String("Keypad 00" );
		|0B1H: AosOut.String("Keypad 000" );
		|0B2H: AosOut.String("Thousands Separator" );
		|0B3H: AosOut.String("Decimal Separator" );
		|0B4H: AosOut.String("Currency Unit" );
		|0B5H: AosOut.String("Currency Sub-unit" );
		|0B6H: AosOut.String("Keypad (");
		|0B7H: AosOut.String("Keypad )" );
		|0B8H: AosOut.String("Keypad {");
		|0B9H: AosOut.String("Keypad }");
		|0BAH: AosOut.String("Keypad Tab" );
		|0BBH: AosOut.String("Keypad Backspace" );
		|0BCH: AosOut.String("Keypad A" );
		|0BDH: AosOut.String("Keypad B" );
		|0BEH: AosOut.String("Keypad C" );
		|0BFH: AosOut.String("Keypad D" );
		|0C0H: AosOut.String("Keypad E" );
		|0C1H: AosOut.String("Keypad F" );
		|0C2H: AosOut.String("Keypad XOR" );
		|0C3H: AosOut.String("Keypad ^");
		|0C4H: AosOut.String("Keypad %");
		|0C5H: AosOut.String("Keypad <");
		|0C6H: AosOut.String("Keypad >");
		|0C7H: AosOut.String("Keypad &");
		|0C8H: AosOut.String("Keypad &&");
		|0C9H: AosOut.String("Keypad |");
		|0CAH: AosOut.String("Keypad ||");
		|0CBH: AosOut.String("Keypad :" );
		|0CCH: AosOut.String("Keypad #");
		|0CDH: AosOut.String("Keypad Space" );
		|0CEH: AosOut.String("Keypad @");
		|0CFH: AosOut.String("Keypad !" );
		|0D0H: AosOut.String("Keypad Memory Store" );
		|0D1H: AosOut.String("Keypad Memory Recall" );
		|0D2H: AosOut.String("Keypad Memory Clear" );
		|0D3H: AosOut.String("Keypad Memory Add" );
		|0D4H: AosOut.String("Keypad Memory Subtract" );
		|0D5H: AosOut.String("Keypad Memory Multiply" );
		|0D6H: AosOut.String("Keypad Memory Divide" );
		|0D7H: AosOut.String("Keypad +/-");
		|0D8H: AosOut.String("Keypad Clear" );
		|0D9H: AosOut.String("Keypad Clear Entry" );
		|0DAH: AosOut.String("Keypad Binary" );
		|0DBH: AosOut.String("Keypad Octal" );
		|0DCH: AosOut.String("Keypad Decimal" );
		|0DDH: AosOut.String("Keypad Hexadecimal" );
		(*|0DE-DFH: AosOut.String("Reserved" );*)
		|0E0H: AosOut.String("Keyboard LeftControl" );
		|0E1H: AosOut.String("Keyboard LeftShift" );
		|0E2H: AosOut.String("Keyboard LeftAlt" );
		|0E3H: AosOut.String("Keyboard Left GUI" );
		|0E4H: AosOut.String("Keyboard RightControl" );
		|0E5H: AosOut.String("Keyboard RightShift" );
		|0E6H: AosOut.String("Keyboard RightAlt" );
		|0E7H: AosOut.String("Keyboard Right GUI" );
		ELSE AosOut.String("Reserved");
	END;
END PrintKeyboardPage;

(* print out the decoded usage for usage page Led 
 * 	param 	pos, usage of the usage page Led 
 *)
PROCEDURE PrintLedPage(pos: LONGINT);
BEGIN
	(*LEDPage (0x08)*)
	CASE pos OF	
		00H:  AosOut.String("Undefined");
		|01H: AosOut.String("Num Lock");
		|02H: AosOut.String(" Caps Lock");
		|03H: AosOut.String(" Scroll Lock");
		|04H: AosOut.String(" Compose");
		|05H: AosOut.String(" Kana");
		|06H: AosOut.String(" Power");
		|07H: AosOut.String(" Shift");
		|08H: AosOut.String(" Do Not Disturb");
		|09H: AosOut.String(" Mute");
		|0AH: AosOut.String(" Tone Enable");
		|0BH: AosOut.String(" High Cut Filter");
		|0CH: AosOut.String(" Low Cut Filter");
		|0DH: AosOut.String(" Equalizer Enable");
		|0EH: AosOut.String(" Sound Field On");
		|0FH: AosOut.String(" Surround On");
		|10H: AosOut.String(" Repeat");
		|11H: AosOut.String(" Stereo");
		|12H: AosOut.String(" Sampling Rate Detect");
		|13H: AosOut.String(" Spinning");
		|14H: AosOut.String(" CAV");
		|15H: AosOut.String(" CLV");
		|16H: AosOut.String(" Recording Format Detect");
		|17H: AosOut.String(" Off-Hook");
		|18H: AosOut.String(" Ring");
		|19H: AosOut.String(" Message Waiting");
		|1AH: AosOut.String(" Data Mode");
		|1BH: AosOut.String(" Battery Operation");
		|1CH: AosOut.String(" Battery OK");
		|1DH: AosOut.String(" Battery Low");
		|1EH: AosOut.String(" Speaker");
		|1FH: AosOut.String(" Head Set");
		|20H: AosOut.String(" Hold");
		|21H: AosOut.String(" Microphone");
		|22H: AosOut.String(" Coverage");
		|23H: AosOut.String(" Night Mode");
		|24H: AosOut.String(" Send Calls");
		|25H: AosOut.String(" Call Pickup");
		|26H: AosOut.String(" Conference");
		|27H: AosOut.String(" Stand-by");
		|28H: AosOut.String(" Camera On");
		|29H: AosOut.String(" Camera Off");
		|2AH: AosOut.String(" On-Line");
		|2BH: AosOut.String(" Off-Line");
		|2CH: AosOut.String(" Busy");
		|2DH: AosOut.String(" Ready");
		|2EH: AosOut.String(" Paper-Out");
		|2FH: AosOut.String(" Paper-Jam");
		|30H: AosOut.String(" Remote");
		|31H: AosOut.String(" Forward");
		|32H: AosOut.String(" Reverse");
		|33H: AosOut.String(" Stop");
		|34H: AosOut.String(" Rewind");
		|35H: AosOut.String(" Fast Forward");
		|36H: AosOut.String(" Play");
		|37H: AosOut.String(" Pause");
		|38H: AosOut.String(" Record");
		|39H: AosOut.String(" Error");
		|3AH: AosOut.String(" Usage Selected Indicator");
		|3BH: AosOut.String(" Usage In Use Indicator");
		|3CH: AosOut.String(" Usage Multi Mode Indicator");
		|3DH: AosOut.String(" Indicator On");
		|3EH: AosOut.String(" Indicator Flash");
		|3FH: AosOut.String(" Indicator Slow Blink");
		|40H: AosOut.String(" Indicator Fast Blink");
		|41H: AosOut.String(" Indicator Off");
		|42H: AosOut.String(" Flash On Time");
		|43H: AosOut.String(" Slow Blink On Time");
		|44H: AosOut.String(" Slow Blink Off Time");
		|45H: AosOut.String(" Fast Blink On Time");
		|46H: AosOut.String(" Fast Blink Off Time");
		|47H: AosOut.String(" Usage Indicator Color");
		|48H: AosOut.String(" Indicator Red");
		|49H: AosOut.String(" Indicator Green");
		|4AH: AosOut.String(" Indicator Amber");
		|4BH: AosOut.String(" Generic Indicator");
		|4CH: AosOut.String(" System Suspend");
		|4DH: AosOut.String(" External Power Connected");
	ELSE
		AosOut.String("Reserved ");
	END;
END PrintLedPage;

(* print out the decoded usage for usage page Button
 *	param 	pos, usage of the usage page Button
 *)
PROCEDURE PrintButtonPage(pos: LONGINT);
BEGIN
	(*Button Page (0x09)*)
	CASE pos OF	
		00H: AosOut.String("No button pressed" );
		|01H: AosOut.String("Button 1 (primary/trigger)" );
		|02H: AosOut.String("Button 2 (secondary)" );
		|03H: AosOut.String("Button 3 (tertiary)" );
		|04H: AosOut.String("Button 4");
		(*|FFFFH: AosOut.String("Button 65535");*)
		ELSE
			AosOut.String("Button "); AosOut.Int(pos,0);
	END;
END PrintButtonPage;

(* print out the decoded usage for usage page Consumer
 *	param 	pos, usage of the usage page Consumer
 *)
PROCEDURE PrintConsumerPage(pos: LONGINT);
BEGIN
	(*Consumer Page (0x0C)*)
	CASE pos OF	
		00H: AosOut.String("Unassigned");
		|01H: AosOut.String("Consumer Control");
		|02H: AosOut.String("Numeric Key Pad");
		|03H: AosOut.String("Programmable Buttons");
		|04H: AosOut.String("Microphone");
		|05H: AosOut.String("Headphone");
		|06H: AosOut.String("Graphic Equalizer");
		(*|07-1F Reserved*)
		|20H: AosOut.String("+10");
		|21H: AosOut.String("+100");
		|22H: AosOut.String(" AM/PM");
		(*|23-3F Reserved*)
		|30H: AosOut.String(" Power");
		|31H: AosOut.String(" Reset");
		|32H: AosOut.String(" Sleep");
		|33H: AosOut.String(" Sleep After");
		|34H: AosOut.String(" Sleep Mode");
		|35H: AosOut.String(" Illumination");
		|36H: AosOut.String(" Function Buttons");
		(*|37-3F Reserved*)
		|40H: AosOut.String("Menu");
		|41H: AosOut.String(" Menu Pick");
		|42H: AosOut.String(" Menu Up");
		|43H: AosOut.String(" Menu Down");
		|44H: AosOut.String(" Menu Left");
		|45H: AosOut.String(" Menu Right");
		|46H: AosOut.String(" Menu Escape");
		|47H: AosOut.String(" Menu Value Increase");
		|48H: AosOut.String(" Menu Value Decrease");
		(*|49-5F Reserved*)
		|60H: AosOut.String(" Data On Screen");
		|61H: AosOut.String(" Closed Caption");
		|62H: AosOut.String(" Closed Caption Select");
		|63H: AosOut.String(" VCR/TV ");
		|64H: AosOut.String(" Broadcast Mode");
		|65H: AosOut.String(" Snapshot");
		|66H: AosOut.String(" Stil");
		(*|67-7F Reserved*)
		|80H: AosOut.String(" Selection");
		|81H: AosOut.String(" Assign Selection");
		|82H: AosOut.String(" Mode Step");
		|83H: AosOut.String(" Recall Last");
		|84H: AosOut.String(" Enter Channel");
		|85H: AosOut.String(" Order Movie");
		|86H: AosOut.String(" Channel LC");
		|87H: AosOut.String(" Media Selection");
		|88H: AosOut.String(" Media Select Computer ");
		|89H: AosOut.String(" Media Select TV");
		|8AH: AosOut.String(" Media Select WWW");
		|8BH: AosOut.String(" Media Select DVD");
		|8CH: AosOut.String(" Media Select Telephone");
		|8DH: AosOut.String(" Media Select Program Guide");
		|8EH: AosOut.String(" Media Select Video Phone");
		|8FH: AosOut.String(" Media Select Games");
		|90H: AosOut.String(" Media Select Messages");
		|91H: AosOut.String(" Media Select CD");
		|92H: AosOut.String(" Media Select VCR");
		|93H: AosOut.String(" Media Select Tuner");
		|94H: AosOut.String(" Quit");
		|95H: AosOut.String(" Help");
		|96H: AosOut.String(" Media Select Tape");
		|97H: AosOut.String(" Media Select Cable");
		|98H: AosOut.String(" Media Select Satellite");
		|99H: AosOut.String(" Media Select Security");
		|9AH: AosOut.String(" Media Select Home");
		|9BH: AosOut.String(" Media Select Call");
		|9CH: AosOut.String(" Channel Increment");
		|9DH: AosOut.String(" Channel Decrement");
		|9EH: AosOut.String(" Media Select SAP");
		|9FH: AosOut.String(" Reserved");
		|0A0H: AosOut.String(" VCR Plus");
		|0A1H: AosOut.String(" Once");
		|0A2H: AosOut.String(" Daily");
		|0A3H: AosOut.String(" Weekly");
		|0A4H: AosOut.String(" Monthly");
		(*|0A5-AF Reserved*)
		|0B0H: AosOut.String(" Play");
		|0B1H: AosOut.String(" Pause");
		|0B2H: AosOut.String(" Record");
		|0B3H: AosOut.String(" Fast Forward");
		|0B4H: AosOut.String(" Rewind");
		|0B5H: AosOut.String(" Scan Next Track");
		|0B6H: AosOut.String(" Scan Previous Track");
		|0B7H: AosOut.String(" Stop OSC");
		|0B8H: AosOut.String(" Eject OSC");
		|0B9H: AosOut.String(" Random Play");
		|0BAH: AosOut.String(" Select Disc");
		|0BBH: AosOut.String(" Enter Disc");
		|0BCH: AosOut.String(" Repeat");
		|0BDH: AosOut.String(" Tracking");
		|0BEH: AosOut.String(" Track Normal");
		|0BFH: AosOut.String(" Slow Tracking");
		|0C0H: AosOut.String(" Frame Forward");
		|0C1H: AosOut.String(" Frame Back");
		|0C2H: AosOut.String(" Mark OSC");
		|0C3H: AosOut.String(" Clear Mark");
		|0C4H: AosOut.String(" Repeat From Mark");
		|0C5H: AosOut.String(" Return To Mark");
		|0C6H: AosOut.String(" Search Mark Forward");
		|0C7H: AosOut.String(" Search Mark Backwards");
		|0C8H: AosOut.String(" Counter Reset");
		|0C9H: AosOut.String(" Show Counter");
		|0CAH: AosOut.String(" Tracking Increment");
		|0CBH: AosOut.String(" Tracking Decrement");
		|0CCH: AosOut.String(" Stop/Eject");
		|0CDH: AosOut.String(" Play/Pause");
		|0CEH: AosOut.String(" Play/Skip");
		(*|0CF-DF Reserved*)
		|0E0H: AosOut.String(" Volume");
		|0E1H: AosOut.String(" Balance");
		|0E2H: AosOut.String(" Mute");
		|0E3H: AosOut.String(" Bass");
		|0E4H: AosOut.String(" Treble");
		|0E5H: AosOut.String(" Bass Boost");
		|0E6H: AosOut.String(" Surround Mode");
		|0E7H: AosOut.String(" Loudness");
		|0E8H: AosOut.String(" MPX");
		|0E9H: AosOut.String(" Volume Increment");
		|0EAH: AosOut.String(" Volume Decrement");
		(*|0EB-EF Reserved*)
		|0F0H: AosOut.String(" Speed Select");
		|0F1H: AosOut.String(" Playback Speed");
		|0F2H: AosOut.String(" Standard Play");
		|0F3H: AosOut.String(" Long Play");
		|0F4H: AosOut.String(" Extended Play");
		|0F5H: AosOut.String(" Slow");
		(*|0F6-FF Reserved*)
		|100H: AosOut.String(" Fan Enable");
		|101H: AosOut.String(" Fan Speed");
		|102H: AosOut.String(" Light Enable");
		|103H: AosOut.String(" Light Illumination Level");
		|104H: AosOut.String(" Climate Control Enable");
		|105H: AosOut.String(" Room Temperature");
		|106H: AosOut.String(" Security Enable");
		|107H: AosOut.String(" Fire Alarm");
		|108H: AosOut.String(" Police Alarm");
		|109H: AosOut.String(" Proximity");
		|10AH: AosOut.String(" Motion");
		|10BH: AosOut.String(" Duress Alarm");
		|10CH: AosOut.String(" Holdup Alarm");
		|10DH: AosOut.String(" Medical Alarm");
		(*|10E-14F Reserved*)
		|150H: AosOut.String(" Balance Right");
		|151H: AosOut.String(" Balance Left");
		|152H: AosOut.String(" Bass Increment");
		|153H: AosOut.String(" Bass Decrement");
		|154H: AosOut.String(" Treble Increment");
		|155H: AosOut.String(" Treble Decrement");
		(*156-15F Reserved*)
		|160H: AosOut.String(" Speaker System");
		|161H: AosOut.String(" Channel Left");
		|162H: AosOut.String(" Channel Right");
		|163H: AosOut.String(" Channel Center");
		|164H: AosOut.String(" Channel Front");
		|165H: AosOut.String(" Channel Center Front");
		|166H: AosOut.String(" Channel Side");
		|167H: AosOut.String(" Channel Surround");
		|168H: AosOut.String(" Channel Low Frequency");
		(*|16B-16F Reserved*)
		|170H: AosOut.String(" Sub-channel");
		|171H: AosOut.String(" Sub-channel Increment");
		|172H: AosOut.String(" Sub-channel Decrement");
		|173H: AosOut.String(" Alternate Audio Increment");
		|174H: AosOut.String(" Alternate Audio Decrement");
		(*|175-17F Reserved*)
		|180H: AosOut.String(" Application Launch Buttons");
		|181H: AosOut.String(" AL Launch Button Configuration");
		|182H: AosOut.String(" AL Programmable Button");
		|183H: AosOut.String(" AL Consumer Control");
		|184H: AosOut.String(" AL Word Processor");
		|185H: AosOut.String(" AL Text Editor");
		|186H: AosOut.String(" AL Spreadsheet");
		|187H: AosOut.String(" AL Graphics Editor");
		|188H: AosOut.String(" AL Presentation App");
		|189H: AosOut.String(" AL Database App");
		|18AH: AosOut.String(" AL Email Reader");
		|18BH: AosOut.String(" AL Newsreader");
		|18CH: AosOut.String(" AL Voicemail");
		|18DH: AosOut.String(" AL Contacts/Address Book");
		|18EH: AosOut.String(" AL Calendar/Schedule");
		|18FH: AosOut.String(" AL Task/Project Manager");
		|190H: AosOut.String(" AL Log/Journal/Timecard");
		|191H: AosOut.String(" AL Checkbook/Finance");
		|192H: AosOut.String(" AL Calculator");
		|193H: AosOut.String(" AL A/V Capture/Playback");
		|194H: AosOut.String(" AL Local Machine Browser");
		|195H: AosOut.String(" AL LAN/WAN Browser");
		|196H: AosOut.String(" AL Internet Browser");
		|197H: AosOut.String(" AL Remote Networking/ISP");
		|198H: AosOut.String(" AL Network Conference");
		|199H: AosOut.String(" AL Network Chat");
		|19AH: AosOut.String(" AL Telephony/Dialer");
		|19BH: AosOut.String(" AL Logon");
		|19CH: AosOut.String(" AL Logoff");
		|19DH: AosOut.String(" AL Logon/Logoff");
		|19EH: AosOut.String(" AL Terminal Lock/Screensaver");
		|19FH: AosOut.String(" AL Control Panel");
		|1A0H: AosOut.String(" AL Command Line Processor/Run");
		|1A1H: AosOut.String(" AL Process/Task Manager");
		|1A2H: AosOut.String(" AL Select Task/Application");
		|1A3H: AosOut.String(" AL Next Task/Application");
		|1A4H: AosOut.String(" AL Previous Task/Application");
		|1A5H: AosOut.String(" AL Preemptive Halt");
		|1A6H: AosOut.String(" AL Integrated Help Center");
		|1A7H: AosOut.String(" AL Documents");
		|1A8H: AosOut.String(" AL Thesaurus");
		|1A9H: AosOut.String(" AL Dictionary");
		|1AAH: AosOut.String(" AL Desktop");
		|1ABH: AosOut.String(" AL Spell Check");
		|1ACH: AosOut.String(" AL Grammar Check");
		|1ADH: AosOut.String(" AL Wireless Status");
		|1AEH: AosOut.String(" AL Keyboard Layout");
		|1AFH: AosOut.String(" AL Virusu Protection");
		|1B0H: AosOut.String(" AL Encryption");
		|1B1H: AosOut.String(" AL Screen Saver");
		|1B2H: AosOut.String(" AL Alarms");
		|1B3H: AosOut.String(" AL Clock");
		|1B4H: AosOut.String(" AL File Browser");
		|1B5H: AosOut.String(" AL Power Status");
		|1B6H: AosOut.String(" AL Image Browser");
		|1B7H: AosOut.String(" AL Audio Browser");
		|1B8H: AosOut.String(" AL Movie Browser");
		|1B9H: AosOut.String(" AL Digital Rights Manager");
		|1BAH: AosOut.String(" AL Digital Wallet");
		(*|1BB Reserved*)
		|1BCH: AosOut.String(" AL Instant Messaging");
		|1BDH: AosOut.String(" AL OEM Features/ Tips/Tutorial");
		|1BEH: AosOut.String(" AL OEM Help");
		|1BFH: AosOut.String(" AL Online Community");
		|1C0H: AosOut.String(" AL Entertainment Content");
		|1C1H: AosOut.String(" AL Online Shopping Browser");
		|1C2H: AosOut.String(" AL SmartCard Information/Help");
		|1C3H: AosOut.String(" AL Market Monitor/Finance");
		|1C4H: AosOut.String(" AL Customized Corporate News");
		|1C5H: AosOut.String(" AL Online Activity Browser");
		|1C6H: AosOut.String(" AL Research/Search Browser");
		|1C7H: AosOut.String(" AL Audio Player");
		(*|1C8-1FF Reserved*)
		|200H: AosOut.String(" Generic GUI Application");
		|201H: AosOut.String(" AC New");
		|202H: AosOut.String(" AC Open");
		|203H: AosOut.String(" AC Close");
		|204H: AosOut.String(" AC Exit");
		|205H: AosOut.String(" AC Maximize");
		|206H: AosOut.String(" AC Minimize");
		|207H: AosOut.String(" AC Save");
		|208H: AosOut.String(" AC Print");
		|209H: AosOut.String(" AC Properties");
		|21AH: AosOut.String(" AC Undo");
		|21BH: AosOut.String(" AC Copy");
		|21CH: AosOut.String(" AC Cut");
		|21DH: AosOut.String(" AC Paste");
		|21EH: AosOut.String(" AC Select All");
		|21FH: AosOut.String(" AC Find");
		|220H: AosOut.String(" AC Find and Replace");
		|221H: AosOut.String(" AC Search");
		|222H: AosOut.String(" AC Go To");
		|223H: AosOut.String(" AC Home");
		|224H: AosOut.String(" AC Back");
		|225H: AosOut.String(" AC Forward");
		|226H: AosOut.String(" AC Stop");
		|227H: AosOut.String(" AC Refresh");
		|228H: AosOut.String(" AC Previous Link");
		|229H: AosOut.String(" AC Next Link");
		|22AH: AosOut.String(" AC Bookmarks");
		|22BH: AosOut.String(" AC History");
		|22CH: AosOut.String(" AC Subscriptions");
		|22DH: AosOut.String(" AC Zoom In");
		|22EH: AosOut.String(" AC Zoom Out");
		|22FH: AosOut.String(" AC Zoom");
		|230H: AosOut.String(" AC Full Screen View");
		|231H: AosOut.String(" AC Normal View");
		|232H: AosOut.String(" AC View Toggle");
		|233H: AosOut.String(" AC Scroll Up");
		|234H: AosOut.String(" AC Scroll Down");
		|235H: AosOut.String(" AC Scroll");
		|236H: AosOut.String(" AC Pan Left");
		|237H: AosOut.String(" AC Pan Right");
		|238H: AosOut.String(" AC Pan");
		|239H: AosOut.String(" AC New Window");
		|23AH: AosOut.String(" AC Tile Horizontally");
		|23BH: AosOut.String(" AC Tile Vertically");
		|23CH: AosOut.String(" AC Format");
		|23DH: AosOut.String(" AC Edit");
		|23EH: AosOut.String(" AC Bold");
		|23FH: AosOut.String(" AC Italics");
		|240H: AosOut.String(" AC Underline");
		|241H: AosOut.String(" AC Strikethrough");
		|242H: AosOut.String(" AC Subscript");
		|243H: AosOut.String(" AC Superscript");
		|244H: AosOut.String(" AC All Caps");
		|245H: AosOut.String(" AC Rotate");
		|246H: AosOut.String(" AC Resize");
		|247H: AosOut.String(" AC Flip horizontal");
		|248H: AosOut.String(" AC Flip Vertical");
		|249H: AosOut.String(" AC Mirror Horizontal");
		|24AH: AosOut.String(" AC Mirror Vertical");
		|24BH: AosOut.String(" AC Font Select");
		|24CH: AosOut.String(" AC Font Color");
		|24DH: AosOut.String(" AC Font Size");
		|24EH: AosOut.String(" AC Justify Left");
		|24FH: AosOut.String(" AC Justify Center H");
		|250H: AosOut.String(" AC Justify Right");
		|251H: AosOut.String(" AC Justify Block H");
		|252H: AosOut.String(" AC Justify Top");
		|253H: AosOut.String(" AC Justify Center V");
		|254H: AosOut.String(" AC Justify Bottom");
		|255H: AosOut.String(" AC Justify Block V");
		|256H: AosOut.String(" AC Indent Decrease");
		|257H: AosOut.String(" AC Indent Increase");
		|258H: AosOut.String(" AC Numbered List");
		|259H: AosOut.String(" AC Restart Numbering");
		|25AH: AosOut.String(" AC Bulleted List");
		|25BH: AosOut.String(" AC Promote");
		|25CH: AosOut.String(" AC Demote");
		|25DH: AosOut.String(" AC Yes");
		|25EH: AosOut.String(" AC No");
		|25FH: AosOut.String(" AC Cancel");
		|260H: AosOut.String(" AC Catalog");
		|261H: AosOut.String(" AC Buy/Checkout");
		|262H: AosOut.String(" AC Add to Cart");
		|263H: AosOut.String(" AC Expand");
		|264H: AosOut.String(" AC Expand All");
		|265H: AosOut.String(" AC Collapse");
		|266H: AosOut.String(" AC Collapse All");
		|267H: AosOut.String(" AC Print Preview");
		|268H: AosOut.String(" AC Paste Special");
		|269H: AosOut.String(" AC Insert Mode");
		|26AH: AosOut.String(" AC Delete");
		|26BH: AosOut.String(" AC Lock");
		|26CH: AosOut.String(" AC Unlock");
		|26DH: AosOut.String(" AC Protect");
		|26EH: AosOut.String(" AC Unprotect");
		|26FH: AosOut.String(" AC Attach Comment");
		|270H: AosOut.String(" AC Delete Comment");
		|271H: AosOut.String(" AC View Comment");
		|272H: AosOut.String(" AC Select Word");
		|273H: AosOut.String(" AC Select Sentence");
		|274H: AosOut.String(" AC Select Paragraph");
		|275H: AosOut.String(" AC Select Column");
		|276H: AosOut.String(" AC Select Row");
		|277H: AosOut.String(" AC Select Table");
		|278H: AosOut.String(" AC Select Object");
		|279H: AosOut.String(" AC Redo/Repeat");
		|27AH: AosOut.String(" AC Sort");
		|27BH: AosOut.String(" AC Sort Ascending");
		|27CH: AosOut.String(" AC Sort Descending");
		|27DH: AosOut.String(" AC Filter");
		|27EH: AosOut.String(" AC Set Clock");
		|27FH: AosOut.String(" AC View Clock");
		|280H: AosOut.String(" AC Select Time Zone");
		|281H: AosOut.String(" AC Edit Time Zones");
		|282H: AosOut.String(" AC Set Alarm");
		|283H: AosOut.String(" AC Clear Alarm");
		|284H: AosOut.String(" AC Snooze Alarm");
		|285H: AosOut.String(" AC Reset Alarm");
		|286H: AosOut.String(" AC Synchronize");
		|287H: AosOut.String(" AC Send/Receive");
		|288H: AosOut.String(" AC Send To");
		|289H: AosOut.String(" AC Reply");
		|28AH: AosOut.String(" AC Reply All");
		|28BH: AosOut.String(" AC Forward Msg");
		|28CH: AosOut.String(" AC Send");
		|28DH: AosOut.String(" AC Attach File");
		|28EH: AosOut.String(" AC Upload");
		|28FH: AosOut.String(" AC Download (Save Target As)");
		|290H: AosOut.String(" AC Set Borders");
		|291H: AosOut.String(" AC Insert Row");
		|292H: AosOut.String(" AC Insert Column");
		|293H: AosOut.String(" AC Insert File");
		|294H: AosOut.String(" AC Insert Picture");
		|295H: AosOut.String(" AC Insert Object");
		|296H: AosOut.String(" AC Insert Symbol");
		|297H: AosOut.String(" AC Save and Close");
		|298H: AosOut.String(" AC Rename");
		|299H: AosOut.String(" AC Merge");
		|29AH: AosOut.String(" AC Split");
		|29BH: AosOut.String(" AC Disribute Horizontally");
		|29CH: AosOut.String(" AC Distribute Vertically");
		(*|29D-FFFF Reserved*)
	ELSE
		AosOut.String("Reserved");
	END;
END PrintConsumerPage;

(*print out the decoded usage for a usage page
 *	param	page,	usage page
 *		 	pos, 	usage of the usage page [page]
 *)
PROCEDURE PrintUsagePage*(page, pos: LONGINT);
BEGIN
	CASE page OF
		|GenericDesktopPage: 	PrintGenericDesktop(pos);
		|KeyboardPage:			PrintKeyboardPage(pos);
		|KeypadPage:			PrintKeyboardPage(pos);
		|LedPage:				PrintLedPage(pos);
		|ButtonPage:			PrintButtonPage(pos);
		|ConsumerPage:			PrintConsumerPage(pos);
	ELSE
		AosOut.String("NO IMPLEMENTATION FOR USAGE PAGE(");AosOut.Int(page,0); AosOut.String(") USAGE(");AosOut.Int(pos,1); AosOut.String(")");
	END;
END PrintUsagePage;

PROCEDURE PrintUsagePageName*(page: LONGINT);
BEGIN
	CASE page OF
		|GenericDesktopPage: 	AosOut.String("GenericDesktop");
		|KeyboardPage:			AosOut.String("KeyboardPage");
		|KeypadPage:			AosOut.String("KeypadPage");
		|LedPage:				AosOut.String("LedPage");
		|ButtonPage:			AosOut.String("ButtonPage");
		|ConsumerPage:			AosOut.String("ConsumerPage");
	ELSE
		AosOut.String("n/a");
	END;
END PrintUsagePageName;

END AosUsbHidUP.

S.Free AosUsbHidUP~