MODULE AosHotKeys; (** AUTHOR "staubesv"; PURPOSE "Hotkey support"; *)
(**
 * This tool registers a message preview handler at the window manager. If the previewed message is a keyboard message,
 * the tool checks whether a command or key remapping has been defined for that key.
 * In case of a defined command, the command is executed and the keyboard message is discarded. In case of a key remapping, the
 * keyboard message is modified and then forwarded.
 *
 * Usage:
 *	
 *	AosHotKeys.Open ~ enables the hot keys defined in the DefaultHotKeyFile
 *	AosHotKeys.Open <filename> ~ enables the hot keys defined in the specified file
 *
 *	AosHotKeys.Show ~ displays a list of bound hot keys
 *
 *	S.Free AosHotKeys ~ disables all hot keys and unloads the module
 *
 * History:
 *
 *	22.08.2006	First release (staubesv)
 *)
 
IMPORT
	AosOut, Utilities, AosInputs, AosModules,
	AosCommands, AosFS, AosIO, WMWindowManager, WMMessages,
	XML, XMLScanner, XMLParser, XMLObjects;

CONST
	(* Load this file if no file specified *)
	DefaultHotKeyFile = "AosHotKeys.XML";
	
	(* Keywords used in XML file *)
	XMLKeysString = "keys";
	XMLCommandString = "command";
	KeySeparatorCharacter = "+";
	
	NoKeysym = -1;
			
	Trace = FALSE;
		
TYPE

	Remapping = POINTER TO RECORD
		ch : CHAR;
		flags : SET;
		keysym : LONGINT;
	END;

	HotKey = POINTER TO RECORD
		ch : CHAR;
		flags : SET;
		keyString : XML.String;
		keysym : LONGINT;
		command : XML.String;
		remapping : Remapping; (* Remap key if not NIL *)
		next : HotKey;
	END;
	
VAR 
	hotkeys : HotKey; (* List head of linked list of hot keys *)
	hasErrors : BOOLEAN;
	
	manager : WMWindowManager.WindowManager;

PROCEDURE ParseKeyString(keyString : XML.String; VAR ch : CHAR; VAR flags : SET; VAR keysym : LONGINT) : BOOLEAN;
VAR keys : Utilities.StringArray; i : LONGINT;
BEGIN
	ASSERT(keyString # NIL);
	ch := 0X; flags := {}; keysym := NoKeysym;
	keys :=	Utilities.Split(keyString^, KeySeparatorCharacter);
	FOR i := 0 TO LEN(keys)-1 DO
		Utilities.TrimWS(keys[i]^);
		Utilities.UpperCase(keys[i]^);
		IF Utilities.Match("ALT", keys[i]^) THEN flags := flags + AosInputs.Alt;
		ELSIF Utilities.Match("LALT", keys[i]^) THEN flags := flags + {AosInputs.LeftAlt};
		ELSIF Utilities.Match("RALT", keys[i]^) THEN flags := flags + {AosInputs.RightAlt};
		ELSIF Utilities.Match("SHIFT", keys[i]^) THEN flags := flags + AosInputs.Shift;
		ELSIF Utilities.Match("LSHIFT", keys[i]^) THEN flags := flags + {AosInputs.LeftShift};
		ELSIF Utilities.Match("RSHIFT", keys[i]^) THEN flags := flags + {AosInputs.RightShift};
		ELSIF Utilities.Match("CTRL", keys[i]^) THEN flags := flags + AosInputs.Ctrl;
		ELSIF Utilities.Match("LCTRL", keys[i]^) THEN flags := flags + {AosInputs.LeftCtrl};
		ELSIF Utilities.Match("RCTRL", keys[i]^) THEN flags := flags + {AosInputs.RightCtrl};
		ELSIF Utilities.Match("META", keys[i]^) THEN flags := flags + AosInputs.Meta;
		ELSIF Utilities.Match("LMETA", keys[i]^) THEN flags := flags + {AosInputs.LeftMeta};
		ELSIF Utilities.Match("RMETA", keys[i]^) THEN flags := flags + {AosInputs.RightMeta};
		ELSIF Utilities.Match("RELEASE", keys[i]^) THEN flags := flags + {AosInputs.Release};
		ELSIF Utilities.Length(keys[i]^) = 1 THEN
			ch := keys[i][0];
		ELSE
			IF (keysym # NoKeysym) OR (ch # 0X) THEN
				AosOut.String("AosHotKeys: Could not parse hotkey: "); AosOut.String(keyString^);
				AosOut.String(": Only one non-modifier key per hotkey allowed!"); AosOut.Ln;
				RETURN FALSE;
			END;
			keysym := StringToKeysym(keys[i]^);
			IF keysym = NoKeysym THEN
				AosOut.String("AosHotKeys: Could not parse hotkey: "); AosOut.String(keyString^); 
				AosOut.String(": Parse error at string: "); AosOut.String(keys[i]^); AosOut.Ln;
				RETURN FALSE;
			END;
		END;
	END;
	RETURN TRUE;
END ParseKeyString;

PROCEDURE ParseRemapping(hk : HotKey) : BOOLEAN;
BEGIN
	ASSERT(hk # NIL);
	IF Utilities.Match("REMAP*", hk.command^) THEN
		Utilities.Delete(hk.command^, 0, 5); (* remove REMAP *)
		NEW(hk.remapping);
		IF ~ParseKeyString(hk.command, hk.remapping.ch, hk.remapping.flags, hk.remapping.keysym) THEN
			RETURN FALSE;
		END;
	END;
	RETURN TRUE;
END ParseRemapping;

PROCEDURE StringToKeysym(string : ARRAY OF CHAR) : LONGINT;
VAR keysym : LONGINT;
BEGIN
	keysym := NoKeysym;
	IF Utilities.Match("BACKSPACE", string) THEN keysym := AosInputs.KsBackSpace;
	ELSIF Utilities.Match("TAB", string) THEN keysym := AosInputs.KsTab;
	ELSIF Utilities.Match("RETURN", string) THEN keysym := AosInputs.KsReturn;
	ELSIF Utilities.Match("PAUSE", string) THEN keysym := AosInputs.KsPause;
	ELSIF Utilities.Match("SCROLLLOCK", string) THEN keysym := AosInputs.KsScrollLock;
	ELSIF Utilities.Match("SYS", string) OR Utilities.Match("SYSREQ", string) THEN keysym := AosInputs.KsSysReq;
	ELSIF Utilities.Match("ESC", string) OR Utilities.Match("ESCAPE", string) THEN keysym := AosInputs.KsEscape;
	ELSIF Utilities.Match("DEL", string) OR Utilities.Match("DELETE", string) THEN keysym := AosInputs.KsDelete;
	ELSIF Utilities.Match("HOME", string) THEN keysym := AosInputs.KsHome;
	ELSIF Utilities.Match("LEFT", string) THEN keysym := AosInputs.KsLeft;
	ELSIF Utilities.Match("UP", string) THEN keysym := AosInputs.KsUp;
	ELSIF Utilities.Match("RIGHT", string) THEN keysym := AosInputs.KsRight;
	ELSIF Utilities.Match("DOWN", string) THEN keysym := AosInputs.KsDown;
	ELSIF Utilities.Match("PAGEUP", string) THEN keysym := AosInputs.KsPageUp;
	ELSIF Utilities.Match("PAGEDOWN", string) THEN keysym := AosInputs.KsPageDown;
	ELSIF Utilities.Match("END", string) THEN keysym := AosInputs.KsEnd;
	ELSIF Utilities.Match("PRINT", string) THEN keysym := AosInputs.KsPrint;
	ELSIF Utilities.Match("INS", string) OR Utilities.Match("INSERT", string) THEN keysym := AosInputs.KsInsert;
	ELSIF Utilities.Match("MENU", string) THEN keysym := AosInputs.KsMenu;
	ELSIF Utilities.Match("BREAK", string) THEN keysym := AosInputs.KsBreak;
	ELSIF Utilities.Match("NUMLOCK", string) THEN keysym := AosInputs.KsNumLock;
	ELSIF Utilities.Match("KPENTER", string) THEN keysym := AosInputs.KsKPEnter;
	ELSIF Utilities.Match("KPMULTIPLY", string) THEN keysym := AosInputs.KsKPMultiply;
	ELSIF Utilities.Match("KPADD", string) THEN keysym := AosInputs.KsKPAdd;
	ELSIF Utilities.Match("KPSUB", string) OR Utilities.Match("KPSUBTRACT", string) THEN keysym := AosInputs.KsKPSubtract;
	ELSIF Utilities.Match("KPDECIMAL", string) THEN keysym := AosInputs.KsKPDecimal;
	ELSIF Utilities.Match("KPDIV", string) OR Utilities.Match("KPDIVIDE", string) THEN keysym := AosInputs.KsKPDivide;
	ELSIF Utilities.Match("F1", string) THEN keysym := AosInputs.KsF1;
	ELSIF Utilities.Match("F2", string) THEN keysym := AosInputs.KsF2;
	ELSIF Utilities.Match("F3", string) THEN keysym := AosInputs.KsF3;
	ELSIF Utilities.Match("F4", string) THEN keysym := AosInputs.KsF4;
	ELSIF Utilities.Match("F5", string) THEN keysym := AosInputs.KsF5;
	ELSIF Utilities.Match("F6", string) THEN keysym := AosInputs.KsF6;
	ELSIF Utilities.Match("F7", string) THEN keysym := AosInputs.KsF7;
	ELSIF Utilities.Match("F8", string) THEN keysym := AosInputs.KsF8;
	ELSIF Utilities.Match("F9", string) THEN keysym := AosInputs.KsF9;
	ELSIF Utilities.Match("F10", string) THEN keysym := AosInputs.KsF10;
	ELSIF Utilities.Match("F11", string) THEN keysym := AosInputs.KsF11;
	ELSIF Utilities.Match("F12", string) THEN keysym := AosInputs.KsF12;
	END;
	RETURN keysym;
END StringToKeysym;

PROCEDURE IsDuplicate(hotkey : HotKey) : BOOLEAN;
VAR hk : HotKey;
BEGIN
	hk := hotkeys.next;
	WHILE (hk # NIL) DO
		IF (hotkey.ch = hk.ch) & (hotkey.flags = hk.flags) & (hotkey.keysym = hk.keysym) THEN
			AosOut.String("AosHotKeys: Warning: Duplicate hot key found: ");
			IF hotkey.keyString # NIL THEN AosOut.String(hotkey.keyString^); 
			ELSE AosOut.String("NIL");
			END;
			AosOut.String("... ignore!"); AosOut.Ln;
			RETURN TRUE;
		END;
		hk := hk.next;
	END;	
	RETURN FALSE;
END IsDuplicate;

(* Create HotKey object and insert it into the hotkeys list (sorted) *)
PROCEDURE AddHotKey(keys, command : XML.String);
VAR hk : HotKey;
BEGIN
	ASSERT((keys # NIL) & (command # NIL));
	NEW(hk); hk.command := command;	hk.keyString := keys;
	IF ParseKeyString(keys, hk.ch, hk.flags, hk.keysym) & ~IsDuplicate(hk) & ParseRemapping(hk) THEN
		hk.next := hotkeys.next;
		hotkeys.next := hk;
	END;
END AddHotKey;

PROCEDURE CreateHotKeyList(doc : XML.Document);
VAR 
	enum: XMLObjects.Enumerator; p: PTR; e: XML.Element; 
	s, keys, command  : XML.String;
BEGIN
	IF doc = NIL THEN RETURN END;
	(* First we just count the number of hot keys defined *)
	e := doc.GetRoot(); enum := e.GetContents();
	WHILE enum.HasMoreElements() DO
		p := enum.GetNext();
		IF p IS XML.Element THEN
			e := p(XML.Element); s := e.GetName();
			IF (s # NIL) & (s^ = "HotKey") THEN
				keys := e.GetAttributeValue(XMLKeysString);
				IF keys # NIL THEN
					command := e.GetAttributeValue(XMLCommandString);
					IF command # NIL THEN
						AddHotKey(keys, command);
					END;
				END;
			END;
		END;
	END;
END CreateHotKeyList;

PROCEDURE FlagsAreEqual(f1, f2 : SET) : BOOLEAN;
VAR match : BOOLEAN;
BEGIN
	match := TRUE;
	IF f1 # f2 THEN		
		IF f2 - f1 # {} THEN (* user pressed more modifier keys than hotkey defines *) 
			match := FALSE;
		ELSE (* maybe the hotkey defines ALT and the user presses LALT *)						
			IF (f1 * AosInputs.Alt = AosInputs.Alt) & (f2 * AosInputs.Alt = {}) THEN match := FALSE; END;
			IF (f1 * AosInputs.Alt # AosInputs.Alt) & (f1 * AosInputs.Alt # f2 * AosInputs.Alt) THEN match := FALSE; END;
			
			IF (f1 * AosInputs.Ctrl = AosInputs.Ctrl) & (f2 * AosInputs.Ctrl = {}) THEN match := FALSE; END;
			IF (f1 * AosInputs.Ctrl # AosInputs.Ctrl) & (f1 * AosInputs.Ctrl # f2 * AosInputs.Ctrl) THEN match := FALSE; END;

			IF (f1 * AosInputs.Shift = AosInputs.Shift) & (f2 * AosInputs.Shift = {}) THEN match := FALSE; END;
			IF (f1 * AosInputs.Shift # AosInputs.Shift) & (f1 * AosInputs.Shift # f2 * AosInputs.Shift) THEN match := FALSE; END;

			IF (f1 * AosInputs.Meta = AosInputs.Meta) & (f2 * AosInputs.Meta = {}) THEN match := FALSE; END;
			IF (f1 * AosInputs.Meta # AosInputs.Meta) & (f1 * AosInputs.Meta # f2 * AosInputs.Meta) THEN match := FALSE; END;
			
			IF (f1 * {AosInputs.Release}) # (f2 * {AosInputs.Release}) THEN match := FALSE; END;
		END;
	END;
	RETURN match;
END FlagsAreEqual;

PROCEDURE GetHotKey(ch : CHAR; flags : SET; keysym : LONGINT) : HotKey;
VAR hk : HotKey;
	
	PROCEDURE FixMessage(VAR ch : CHAR; flags : SET);
	BEGIN
		IF flags * AosInputs.Ctrl # {} THEN (* Reverse keyboard driver ctrl key mapping *)
			IF (0 < ORD(ch)) & (ORD(ch) < 32) THEN
				ch := CHR(ORD(ch) + 60H);
			END;
		END;
		IF (ch >= "a") & (ch <= "z") THEN ch := CAP(ch); END;
	END FixMessage;

BEGIN
	FixMessage(ch, flags);
	hk := hotkeys.next;
	LOOP
		IF (hk = NIL) THEN EXIT; END;
		IF (hk.keysym # NoKeysym) THEN
			IF (hk.keysym = keysym) & FlagsAreEqual(hk.flags, flags) THEN RETURN hk; END;
		ELSE
			IF (hk.ch = ch) & FlagsAreEqual(hk.flags, flags) THEN RETURN hk; END;
		END;
		hk := hk.next;
	END;	
	RETURN NIL;
END GetHotKey;

PROCEDURE ExecuteCommandFor(command : XML.String);
VAR msg : ARRAY 256 OF CHAR; res : LONGINT;
BEGIN
	ASSERT(command # NIL);
	IF Trace THEN AosOut.String("AosHotKeys: Executing "); AosOut.String(command^); AosOut.Ln; END;
	AosCommands.Call(command^, {}, res, msg);
	IF res # 0 THEN
		AosOut.String("AosHotKeys: Error when executing command "); AosOut.String(command^); AosOut.String(", res: ");
		AosOut.Int(res, 0); AosOut.String(" ("); AosOut.String(msg); AosOut.String(")"); AosOut.Ln;
	END;
END ExecuteCommandFor;

(* Report errors while parsing *)
PROCEDURE Error(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	AosOut.String("AosHotKeys: Parse error at pos "); AosOut.Int(pos, 5); AosOut.String(" in line "); AosOut.Int(line, 5); 
	AosOut.String(" row "); AosOut.Int(row, 5); AosOut.String(" - "); AosOut.String(msg); AosOut.Ln;
	hasErrors := TRUE
END Error;

PROCEDURE Read(name : ARRAY OF CHAR);
VAR f : AosFS.File; scanner : XMLScanner.Scanner; parser : XMLParser.Parser; reader : AosFS.Reader; doc : XML.Document;	
BEGIN
	AosOut.String("AosHotKeys: File "); AosOut.String(name);
	hasErrors := FALSE;
	f := AosFS.Old(name);
	IF f # NIL THEN
		NEW(reader, f, 0);
		NEW(scanner, reader); scanner.reportError := Error;
		NEW(parser, scanner); parser.reportError := Error;
		doc := parser.Parse();
		IF hasErrors THEN AosOut.String(" has errors.");
		ELSE
			CreateHotKeyList(doc); AosOut.String(" loaded.");
		END;
	ELSE AosOut.String(" not found.");
	END;
	AosOut.Ln;
END Read;

(* Message preview handler for window manager. MUST NOT TRAP!!! *)
PROCEDURE Handle(VAR msg : WMMessages.Message; VAR discard : BOOLEAN);
VAR hotkey : HotKey;
BEGIN
	IF msg.msgType # WMMessages.MsgKey THEN RETURN; END;
	IF (msg.x >= 0) & (msg.x < 256) THEN
		hotkey := GetHotKey(CHR(msg.x), msg.flags, msg.y);
	END;
	IF hotkey # NIL THEN
		IF hotkey.remapping = NIL THEN
			ExecuteCommandFor(hotkey.command);
			discard := TRUE;
		ELSE
			msg.x := ORD(hotkey.remapping.ch);
			msg.flags := hotkey.remapping.flags;
			msg.y := hotkey.remapping.keysym;
		END;
	END;
END Handle;

PROCEDURE InstallHandler;
BEGIN
	ASSERT(manager = NIL);
	manager := WMWindowManager.GetDefaultManager();
	IF manager # NIL THEN
		manager.InstallMessagePreview(Handle);
	ELSE
		AosOut.String("AosHotKeys: Window Manager not found."); AosOut.Ln;
	END;
END InstallHandler;

(** Show all currently loaded hot keys *)
PROCEDURE Show*(ignore : ANY) : ANY; (** ~ *)
VAR nbrOfHotKeys : LONGINT; hk : HotKey;
BEGIN
	AosOut.String("WMHotKeys: List of currently bound hot keys:"); AosOut.Ln;
	nbrOfHotKeys := 0; 
	hk := hotkeys.next;
	WHILE hk # NIL DO
		INC(nbrOfHotKeys);
		AosOut.String("Hotkey "); AosOut.Int(nbrOfHotKeys, 2); AosOut.String(": ");
		AosOut.String(hk.keyString^); 
		IF hk.keysym # NoKeysym THEN
			AosOut.String(" Keysym: "); AosOut.Hex(hk.keysym, 0); 
		END;
		AosOut.String(" Command: "); 
		AosOut.String(hk.command^); AosOut.Ln;
		hk := hk.next;
	END;
	AosOut.Int(nbrOfHotKeys, 0); AosOut.String(" hot keys in total."); AosOut.Ln;
	RETURN NIL;
END Show;

(** (Re)Load hotkeys of the specified file. If no filename is specified, the default filename is used *)
PROCEDURE Open*(par : ANY) : ANY; (** [filename] ~ *)
VAR r : AosIO.StringReader; filename : ARRAY 256 OF CHAR;
BEGIN
	hotkeys.next := NIL;
	AosCommands.PosPar(par, r);
	r.String(filename);
	IF r.res = AosIO.Ok THEN
		Read(filename);
	ELSE
		Read(DefaultHotKeyFile);
	END;
	RETURN NIL
END Open;

PROCEDURE Cleanup;
BEGIN
	IF manager # NIL THEN manager.RemoveMessagePreview(Handle); END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	NEW(hotkeys); (* head of list *)
	InstallHandler;
END AosHotKeys.