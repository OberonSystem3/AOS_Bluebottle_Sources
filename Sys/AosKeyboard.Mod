(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosKeyboard; (** AUTHOR "pjm"; PURPOSE "PC keyboard driver"; *)

(* temporary Native-based version *)

IMPORT SYSTEM, AosBoot, AosOut, AosInterrupts, AosModules, AosKernel, AosActive, AosInputs, AosIO, AosCommands, AosFS;

CONST
		(* do not change these values, as they are used in the keyboard tables from Native *)
	ScrollLock = 0; NumLock = 1; CapsLock = 2; LAlt = 3; RAlt = 4;
	LCtrl = 5; RCtrl = 6; LShift = 7; RShift = 8; GreyEsc = 9;
	Resetting = 10; SetTypematic = 11; SendingLEDs = 12;
	LMeta = 13; RMeta = 14;
	
	DeadKey = 0;
	
	TraceKeys = FALSE;
	
TYPE
	Keyboard = OBJECT
		VAR last: AosInputs.KeyboardMsg;
		
		PROCEDURE HandleInterrupt;
		VAR m: SET; i: LONGINT; msg: AosInputs.KeyboardMsg; k: INTEGER; c: CHAR;
		BEGIN {EXCLUSIVE}
			SYSTEM.PORTIN(060H, c);	(* get scan code *)
			SYSTEM.PORTIN(061H, SYSTEM.VAL(CHAR, m));
			INCL(m, 7); SYSTEM.PORTOUT(061H, SYSTEM.VAL(CHAR, m));
			EXCL(m, 7); SYSTEM.PORTOUT(061H, SYSTEM.VAL(CHAR, m));	(* ack *)
			IF TraceKeys THEN AosOut.Hex(ORD(c), -3) END;
			k := MapScanCode(c, msg.keysym);
			IF k >= 0 THEN msg.ch := CHR(k) ELSE msg.ch := 0X END;
			IF TraceKeys & (msg.keysym # AosInputs.KsNil) THEN
				AosOut.Hex(msg.keysym, 9); AosOut.Ln
			END;
			(*msg.key := CHR(ORD(c) MOD 80H);*)
			msg.flags := {};
			FOR i := LAlt TO RShift DO
				IF i IN flags THEN INCL(msg.flags, mapflag[i]) END
			END;
			FOR i := LMeta TO RMeta DO
				IF i IN flags THEN INCL(msg.flags, i-LMeta+AosInputs.LeftMeta) END
			END;
			IF c >= 80X THEN INCL(msg.flags, AosInputs.Release) END;
			IF (msg.flags # last.flags) OR (msg.ch # 0X) OR (msg.keysym # AosInputs.KsNil) THEN
				last := msg; AosInputs.keyboard.Handle(msg)
			END
		END HandleInterrupt;
		
		PROCEDURE &Init;
		BEGIN
			last.ch := 0X; (*last.key := 0X;*) last.flags := {0..31};
			AosActive.InstallHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0+1)
		END Init;
		
		PROCEDURE Finalize;
		BEGIN
			AosActive.RemoveHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0+1)
		END Finalize;
		
	END Keyboard;

VAR
	dkey: SHORTINT;
	lastport: LONGINT;
	lastvalue: SYSTEM.BYTE;
	keyval: INTEGER;
	table: LONGINT;
	flags: SET;
	keytable: POINTER TO ARRAY OF CHAR;
	keyboard: Keyboard;
	mapflag: ARRAY RShift+1 OF SHORTINT;

(* ---- Keyboard Driver ---- *)

(* Translation table format: 

	table = { scancode unshifted-code shifted-code flags }  0FFX .
	scancode = <scancode byte from keyboard, bit 7 set for "grey" extended keys>
	unshifted-code = <CHAR produced by this scancode, without shift>
	shifted-code = <CHAR produced by this scancode, with shift>
	flags = <bit-mapped flag byte indicating special behaviour>
	
	flag bit	function
		0	01	DeadKey: Set dead key flag according to translated key code (1-7)
		1	02	NumLock: if set, the state of NumLock will reverse the action of shift (for num keypad) *** no longer ***
		2	04	CapsLock: if set, the state of CapsLock will reverse the action of shift (for alpha keys)
		3	08	LAlt:  \ the state of these two flags in the table and the current state of the two...
		4	10	RAlt: / ...Alt keys must match exactly, otherwise the search is continued.
		5	20	\
		6	40	 >  dead key number (0-7), must match current dead key flag
		7	80	/
	
	The table is scanned sequentially (speed not critical).  Ctrl-Break, Ctrl-F10 and Ctrl-Alt-Del
	are always defined and are not in the table.   The control keys are also always defined. *)

(* TableUS - US keyboard translation table (dead keys: ^=1, '=2, `=3, ~=4, "=5) *)

PROCEDURE TableUS(): LONGINT;
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
	DB 17X, "ï", 0FFX, 14X,	1FX, "ß", 0FFX, 14X,	2EX, "ç", 0FFX, 14X,	31X, "ñ", 0FFX, 14X
		(* dead keys (LAlt & RAlt) *)
	DB 07X, 0FFX, 1X, 9X,	28X, 2X, 5X, 9X,	29X, 3X, 4X, 9X,
	DB 07X, 0FFX, 1X, 11X,	28X, 2X, 5X, 11X,	29X, 3X, 4X, 11X,
		(* following keys *)
	DB 1EX, "â", 0FFX, 20X,	12X, "ê", 0FFX, 20X,	17X, "î", 0FFX, 20X,	18X, "ô", 0FFX, 20X
	DB 16X, "û", 0FFX, 20X,	1EX, "à", 0FFX, 60X,	12X, "è", 0FFX, 60X,	17X, "ì", 0FFX, 60X
	DB 18X, "ò", 0FFX, 60X,	16X, "ù", 0FFX, 60X,	1EX, "á", 0FFX, 40X,	12X, "é", 0FFX, 40X
	DB 1EX, "ä", "Ä", 0A4X,	12X, "ë", 0FFX, 0A0X,	17X, "ï", 0FFX, 0A0X,	18X, "ö", "Ö", 0A4X
	DB 16X, "ü", "Ü", 0A4X,	31X, "ñ", 0FFX, 80X *)
	
	DB 1EX, 83X, 80X, 0CX,	12X, 91X, 0FFX, 0CX,	18X, 84X, 81X, 0CX,	16X, 85X, 82X, 0CX
	DB 17X, 92X, 0FFX, 0CX,	1FX, 96X, 0FFX, 0CX,	2EX, 93X, 0FFX, 0CX,	31X, 95X, 0FFX, 0CX
	DB 1EX, 83X, 80X, 14X,	12X, 91X, 0FFX, 14X,	18X, 84X, 81X, 14X,	16X, 85X, 82X, 14X
	DB 17X, 92X, 0FFX, 14X,	1FX, 96X, 0FFX, 14X,	2EX, 93X, 0FFX, 14X,	31X, 95X, 0FFX, 14X
		(* dead keys (LAlt & RAlt) *)
	DB 07X, 0FFX, 1X, 9X,	28X, 2X, 5X, 9X,	29X, 3X, 4X, 9X,
	DB 07X, 0FFX, 1X, 11X,	28X, 2X, 5X, 11X,	29X, 3X, 4X, 11X,
		(* following keys *)
	DB 1EX, 86X, 0FFX, 20X,	12X, 87X, 0FFX, 20X,	17X, 88X, 0FFX, 20X,	18X, 89X, 0FFX, 20X
	DB 16X, 8AX, 0FFX, 20X,	1EX, 8BX, 0FFX, 60X,	12X, 8CX, 0FFX, 60X,	17X, 8DX, 0FFX, 60X
	DB 18X, 8EX, 0FFX, 60X,	16X, 8FX, 0FFX, 60X,	1EX, 94X, 0FFX, 40X,	12X, 90X, 0FFX, 40X
	DB 1EX, 83X, 80X, 0A4X,	12X, 91X, 0FFX, 0A0X,	17X, 92X, 0FFX, 0A0X,	18X, 84X, 81X, 0A4X
	DB 16X, 85X, 82X, 0A4X,	31X, 95X, 0FFX, 80X
	
	DB 1EX, "a", "A", 0CX,	12X, "e", 0FFX, 0CX,	18X, "o", "O", 0CX,	16X, "u", "U", 0CX
	DB 17X, "i", 0FFX, 0CX,	1FX, "s", 0FFX, 0CX,	2EX, "c", 0FFX, 0CX,	31X, "n", 0FFX, 0CX
	DB 1EX, "a", "A", 14X,	12X, "e", 0FFX, 14X,	18X, "o", "O", 14X,	16X, "u", "U", 14X
	DB 17X, "i", 0FFX, 14X,	1FX, "s", 0FFX, 14X,	2EX, "c", 0FFX, 14X,	31X, "n", 0FFX, 14X
		(* dead keys (LAlt & RAlt) *)
	DB 07X, 0FFX, 1X, 9X,	28X, 2X, 5X, 9X,	29X, 3X, 4X, 9X,
	DB 07X, 0FFX, 1X, 11X,	28X, 2X, 5X, 11X,	29X, 3X, 4X, 11X,
		(* following keys *)
	DB 1EX, "a", 0FFX, 20X,	12X, "e", 0FFX, 20X,	17X, "i", 0FFX, 20X,	18X, "o", 0FFX, 20X
	DB 16X, "u", 0FFX, 20X,	1EX, "a", 0FFX, 60X,	12X, "e", 0FFX, 60X,	17X, "i", 0FFX, 60X
	DB 18X, "o", 0FFX, 60X,	16X, "u", 0FFX, 60X,	1EX, "a", 0FFX, 40X,	12X, "e", 0FFX, 40X
	DB 1EX, "a", "A", 0A4X,	12X, "e", 0FFX, 0A0X,	17X, "i", 0FFX, 0A0X,	18X, "o", "O", 0A4X
	DB 16X, "u", "U", 0A4X,	31X, "n", 0FFX, 80X
		(* numbers at top *)
	DB 0BX, "0", ")", 0X,	02X, "1", "!", 0X,	03X, "2", "@", 0X,	04X, "3", "#", 0X
	DB 05X, "4", "$", 0X,	06X, "5", "%", 0X,	07X, "6", "^", 0X,	08X, "7", "&", 0X
	DB 09X, "8", "*", 0X,	0AX, "9", "(", 0X
		(* symbol keys *)
	DB 28X, "'", 22X, 0X,	33X, ",", "<", 0X,	0CX, "-", "_", 0X,	34X, ".", ">", 0X
	DB 35X, "/", "?", 0X,	27X, ";", ":", 0X,	0DX, "=", "+", 0X,	1AX, "[", "{", 0X
	DB 2BX, "\", "|", 0X,	1BX, "]", "}", 0X,	29X, "`", "~", 0X
		(* control keys *)
	DB 0EX, 7FX, 7FX, 0X	(* backspace *)
	DB 0FX, 09X, 09X, 0X	(* tab *)
	DB 1CX, 0DX, 0DX, 0X	(* enter *)
	DB 39X, 20X, 20X, 0X	(* space *)
	DB 01X, 1BX, 1BX, 0X	(* esc *)
	 	(* keypad *)
	DB 4FX, 0A9X, "1", 2X	(* end/1 *)
	DB 50X, 0C2X, "2", 2X	(* down/2 *)
	DB 51X, 0A3X, "3", 2X	(* pgdn/3 *)
	DB 4BX, 0C4X, "4", 2X	(* left/4 *)
	DB 4CX, 0FFX, "5", 2X	(* center/5 *)
	DB 4DX, 0C3X, "6", 2X	(* right/6 *)
	DB 47X, 0A8X, "7", 2X	(* home/7 *)
	DB 48X, 0C1X, "8", 2X	(* up/8 *)
	DB 49X, 0A2X, "9", 2X	(* pgup/9 *)
	DB 52X, 0A0X, "0", 2X	(* insert/0 *)
	DB 53X, 0A1X, 2EX, 2X	(* del/. *)
		(* grey keys *)
	DB 4AX, "-", "-", 0X	(* grey - *)
	DB 4EX, "+", "+", 0X	(* grey + *)
	DB 0B5X, "/", "/", 0X	(* grey / *)
	DB 37X, "*", "*", 0X	(* grey * *)
	DB 0D0X, 0C2X, 0C2X, 0X	(* grey down *)
	DB 0CBX, 0C4X, 0C4X, 0X	(* grey left *)
	DB 0CDX, 0C3X, 0C3X, 0X	(* grey right *)
	DB 0C8X, 0C1X, 0C1X, 0X	(* grey up *)
	DB 09CX, 0DX, 0DX, 0X	(* grey enter *)
	DB 0D2X, 0A0X, 0A0X, 0X	(* grey ins *)
	DB 0D3X, 0A1X, 0A1X, 0X	(* grey del *)
	DB 0C9X, 0A2X, 0A2X, 0X	(* grey pgup *)
	DB 0D1X, 0A3X, 0A3X, 0X	(* grey pgdn *)
	DB 0C7X, 0A8X, 0A8X, 0X	(* grey home *)
	DB 0CFX, 0A9X, 0A9X, 0X	(* grey end *)
		(* function keys *)
	DB 3BX, 0A4X, 0FFX, 0X	(* F1 *)
	DB 3CX, 0A5X, 0FFX, 0X	(* F2 *)
	DB 3DX, 0A6X, 0FFX, 0X	(* F3 *)
	DB 3EX, 0A7X, 0FFX, 0X	(* F4 *)
	DB 3FX, 0F5X, 0FFX, 0X	(* F5 *)
	DB 40X, 0F6X, 0FFX, 0X	(* F6 *)
	DB 41X, 0F7X, 0FFX, 0X	(* F7 *)
	DB 42X, 0F8X, 0FFX, 0X	(* F8 *)
	DB 43X, 0F9X, 0FFX, 0X	(* F9 *)
	DB 44X, 0FAX, 0FFX, 0X	(* F10 *)
	DB 57X, 0FBX, 0FFX, 0X	(* F11 *)
	DB 58X, 0FCX, 0FFX, 0X	(* F12 *)
	DB 0FFX
END TableUS;

PROCEDURE TableFromFile(name: ARRAY OF CHAR): LONGINT;
VAR f: AosFS.File; r: AosFS.Rider; len: LONGINT;
BEGIN
	AosOut.String("AosKeyboard: "); AosOut.String(name);
	f := AosFS.Old(name);
	IF f # NIL THEN
		len := f.Length();
		IF len MOD 4 = 0 THEN
			NEW(keytable, len+1);
			f.Set(r, 0); f.ReadBytes(r, keytable^, 0, len);
			IF r.res = 0 THEN
				AosOut.String(" loaded."); AosOut.Ln;
				keytable[len] := 0FFX;
				RETURN SYSTEM.ADR(keytable[0])
			ELSE
				AosOut.String(" res="); AosOut.Int(r.res, 1)
			END
		ELSE
			AosOut.String(" len="); AosOut.Int(len, 1)
		END
	ELSE
		AosOut.String(" not found.")
	END;
	AosOut.Ln;
	RETURN TableUS()
END TableFromFile;

(* Translate - Translate scan code "c" to key. *)

PROCEDURE Translate(flags: SET; c: CHAR): INTEGER;
CONST
	Alt = {LAlt, RAlt}; Ctrl = {LCtrl, RCtrl}; Shift = {LShift, RShift};
VAR a: LONGINT; s1: CHAR; s: SET; k: INTEGER; dkn: SHORTINT;
BEGIN {EXCLUSIVE}
	IF (c = 46X) & (flags * Ctrl # {}) THEN RETURN -2 END;	(* Ctrl-Break - break *)
	IF (c = 44X) & (flags * Ctrl # {}) THEN RETURN 0FFH END;	(* Ctrl-F10 - exit *)
	IF (c = 53X) & (flags * Ctrl # {}) & (flags * Alt # {}) THEN RETURN 0A1H END;	(* Ctrl-Alt-Del - Del *)
	IF GreyEsc IN flags THEN c := CHR(ORD(c)+80H) END;
	a := table;
	LOOP
		SYSTEM.GET(a, s1);
		IF s1 = 0FFX THEN	(* end of table, unmapped key *)
			k := -1; dkey := 0; EXIT
		ELSIF s1 = c THEN	(* found scan code in table *)
			SYSTEM.GET(a+3, SYSTEM.VAL(CHAR, s));	(* flags from table *)
			dkn := SHORT(SHORT(SYSTEM.VAL(LONGINT, SYSTEM.LSH(s * {5..7}, -5))));
			s := s * {DeadKey, NumLock, CapsLock, LAlt, RAlt, LCtrl, RCtrl}; k := 0;
			IF ((s * Alt = flags * Alt) OR (NumLock IN s) OR (s1 > 03BX)) & (dkn = dkey) THEN	(* Alt & dead keys match exactly *)
				IF flags * Shift # {} THEN INCL(s, LShift) END;	(* check if shift pressed *)
					(* handle CapsLock *)
				IF (CapsLock IN s) & (CapsLock IN flags) THEN s := s / {LShift} END;
					(* handle NumLock *)
				IF NumLock IN s THEN
					IF NumLock IN flags THEN s := s + {LShift} ELSE s := s - {LShift} END
				END;
					(* get key code *)
				IF LShift IN s THEN SYSTEM.GET(a+2, SYSTEM.VAL(CHAR, k))	(* shifted value *)
				ELSE SYSTEM.GET(a+1, SYSTEM.VAL(CHAR, k))	(* unshifted value *)
				END;
				IF (DeadKey IN s) & (k <= 7) THEN	(* dead key *)
					dkey := SHORT(k); k := -1	(* set new dead key state *)
				ELSIF k = 0FFH THEN	(* unmapped key *)
					k := -1; dkey := 0	(* reset dead key state *)
				ELSE	(* mapped key *)
					IF flags * Ctrl # {} THEN
						IF ((k >= 64) & (k <= 95)) OR ((k >= 97) & (k <= 122)) THEN
							k := SHORT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, k) * {0..4}))	(* control *)
						ELSIF k = 13 THEN	(* Ctrl-Enter *)
							k := 10
						END
					END;
					IF flags * Alt # {} THEN	(* Alt-keypad *)
						IF (k >= ORD("0")) & (k <= ORD("9")) & (NumLock IN s) THEN	(* keypad num *)
							IF keyval = -1 THEN keyval := k-ORD("0")
							ELSE keyval := (10*keyval + (k-ORD("0"))) MOD 1000
							END;
							k := -1
						END
					END;
					dkey := 0	(* reset dead key state *)
				END;
				EXIT
			END
		END;
		INC(a, 4)
	END; (* LOOP *)
	RETURN k
END Translate;

(* Wait - Wait for keyboard serial port to acknowledge byte. *)

PROCEDURE Wait;
VAR t: AosKernel.MilliTimer; s: SET;
BEGIN
	AosKernel.SetTimer(t, 20);	(* wait up to 17 ms *)
	REPEAT
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s))
	UNTIL ~(1 IN s) OR AosKernel.Expired(t)
END Wait;

(* SendByte - Send a byte to the keyboard. *)

PROCEDURE SendByte(port: LONGINT; value: SYSTEM.BYTE);
BEGIN
	Wait; SYSTEM.PORTOUT(port, SYSTEM.VAL(CHAR, value));
	lastport := port; lastvalue := value
END SendByte;

(* ShiftKey - Handle shift keys. *)

PROCEDURE ShiftKey(left, right: SHORTINT; in: BOOLEAN);
BEGIN
	IF in THEN
		IF GreyEsc IN flags THEN INCL(flags, right)
		ELSE INCL(flags, left)
		END
	ELSE
		IF GreyEsc IN flags THEN EXCL(flags, right)
		ELSE EXCL(flags, left)
		END
	END
END ShiftKey;

(* LedKey - Handle "lock" keys. *)

PROCEDURE LedKey(VAR flags: SET; lock: SHORTINT; c: CHAR;
		VAR k: INTEGER);
BEGIN
	IF flags * {LAlt, RAlt, LCtrl, RCtrl, LShift, RShift} = {} THEN
		flags := flags / {lock}
	ELSE
		k := Translate(flags, c)
	END
END LedKey;

(* MapScanCode - Map a scan code "c" to a key code. *)

PROCEDURE MapScanCode(c: CHAR; VAR keysym: LONGINT): INTEGER;
VAR k: INTEGER; oldleds: SET;
BEGIN
	SendByte(64H, 0ADX); Wait;	(* disable keyboard *)
	k := -1; oldleds := flags * {ScrollLock, NumLock, CapsLock};
	keysym := AosInputs.KsNil;	(* no key *)
	IF c = 0X THEN	(* overrun, ignore *)
	ELSIF c = 0FAX THEN	(* keyboard ack *)
		IF Resetting IN flags THEN
			EXCL(flags, Resetting); INCL(flags, SendingLEDs);
			SendByte(60H, 0EDX)	(* set keyboard LEDs *)
		ELSIF SendingLEDs IN flags THEN
			SendByte(60H, SYSTEM.VAL(CHAR, oldleds));
			EXCL(flags, SendingLEDs)
		ELSIF SetTypematic IN flags THEN
			EXCL(flags, SetTypematic); INCL(flags, Resetting);
			SendByte(60H, 020X)	(* 30Hz, 500 ms *)
		ELSE (* assume ack was for something else *)
		END
	ELSIF c = 0FEX THEN	(* keyboard resend *)
		SendByte(lastport, lastvalue)
	ELSIF c = 038X THEN	(* Alt make *)
		ShiftKey(LAlt, RAlt, TRUE); keysym := AosInputs.KsAltL
	ELSIF c = 01DX THEN	(* Ctrl make *)
		ShiftKey(LCtrl, RCtrl, TRUE); keysym := AosInputs.KsControlL
	ELSIF c = 02AX THEN	(* LShift make *)
		IF ~(GreyEsc IN flags) THEN
			INCL(flags, LShift); keysym := AosInputs.KsShiftL
		END
	ELSIF c = 036X THEN	(* RShift make *)
		IF ~(GreyEsc IN flags) THEN
			INCL(flags, RShift); keysym := AosInputs.KsShiftR
		END
	ELSIF c = 05BX THEN	(* LMeta make *)
		INCL(flags, LMeta); keysym := AosInputs.KsMetaL
	ELSIF c = 05CX THEN	(* RMeta make *)
		INCL(flags, RMeta); keysym := AosInputs.KsMetaR
	ELSIF c = 03AX THEN	(* Caps make *)
		LedKey(flags, CapsLock, c, k)
	ELSIF c = 046X THEN	(* Scroll make *)
		LedKey(flags, ScrollLock, c, k);
		IF k = -2 THEN keysym := AosInputs.KsBreak END	(* Break *)
	ELSIF c = 045X THEN	(* Num make *)
		LedKey(flags, NumLock, c, k)
	ELSIF c = 0B8X THEN	(* Alt break *)
		ShiftKey(LAlt, RAlt, FALSE); keysym := AosInputs.KsAltL;
		IF (keyval >= 0) & (keyval < 255) THEN k := keyval END;	(* exclude 255 - reboot *)
		keyval := -1
	ELSIF c = 09DX THEN	(* Ctrl break *)
		ShiftKey(LCtrl, RCtrl, FALSE); keysym := AosInputs.KsControlL
	ELSIF c = 0AAX THEN	(* LShift break *)
		IF ~(GreyEsc IN flags) THEN
			EXCL(flags, LShift); keysym := AosInputs.KsShiftL
		END
	ELSIF c = 0B6X THEN	(* RShift break *)
		IF ~(GreyEsc IN flags) THEN
			EXCL(flags, RShift); keysym := AosInputs.KsShiftR
		END
	ELSIF c = 0DBX THEN	(* LMeta break *)
		EXCL(flags, LMeta); keysym := AosInputs.KsMetaL
	ELSIF c = 0DCX THEN	(* RMeta break *)
		EXCL(flags, RMeta); keysym := AosInputs.KsMetaR
	ELSIF c = 05DX THEN	(* Menu make *)
		keysym := AosInputs.KsMenu	(* Windows menu *)
	ELSIF c < 080X THEN	(* Other make *)
		k := Translate(flags, c);
		IF c = 0EX THEN keysym := AosInputs.KsBackSpace	(* backspace *)
		ELSIF c = 0FX THEN keysym := AosInputs.KsTab	(* tab *)
		ELSIF c = 1CX THEN keysym := AosInputs.KsReturn	(* enter *)
		ELSIF c = 01X THEN keysym := AosInputs.KsEscape	(* esc *)
		ELSIF c = 3DX THEN keysym := AosInputs.KsF3	(* f3 *)
		ELSIF c = 4AX THEN keysym := AosInputs.KsKPSubtract	(* kp - *)
		ELSIF c = 4EX THEN keysym := AosInputs.KsKPAdd	(* kp + *)
		ELSIF c = 0B5X THEN keysym := AosInputs.KsKPDivide	(* kp / *)
		ELSIF c = 37X THEN keysym := AosInputs.KsKPMultiply	(* kp * *)
		ELSIF k >= 0 THEN keysym := KeySym(CHR(k))
		ELSE (* skip *)
		END
	ELSE	(* ignore *)
	END;
	IF c = 0E0X THEN INCL(flags, GreyEsc) ELSE EXCL(flags, GreyEsc) END;
	IF flags * {ScrollLock, NumLock, CapsLock} # oldleds THEN
		INCL(flags, SendingLEDs);
		SendByte(60H, 0EDX)	(* set keyboard LEDs *)
	END;
	SendByte(64H, 0AEX);	(* enable keyboard *)
		(* now do additional mappings *)
	RETURN k
END MapScanCode;

(* Map Oberon character code to X11 keysym (/usr/include/X11/keysymdef.h). *)

PROCEDURE KeySym(ch: CHAR): LONGINT;
VAR x: LONGINT;
BEGIN
	IF (ch >= 1X) & (ch <= 7EX) THEN x := ORD(ch)	(* ascii *)
	ELSIF ch = 0A0X THEN x := AosInputs.KsInsert	(* insert *)
	ELSIF ch = 0A1X THEN x := AosInputs.KsDelete	(* delete *)
	ELSIF ch = 0A8X THEN x := AosInputs.KsHome	(* home *)
	ELSIF ch = 0A9X THEN x := AosInputs.KsEnd	(* end *)
	ELSIF ch = 0A2X THEN x := AosInputs.KsPageUp	(* pgup *)
	ELSIF ch = 0A3X THEN x := AosInputs.KsPageDown	(* pgdn *)
	ELSIF ch = 0C4X THEN x := AosInputs.KsLeft	(* left *)
	ELSIF ch = 0C1X THEN x := AosInputs.KsUp	(* up *)
	ELSIF ch = 0C3X THEN x := AosInputs.KsRight	(* right *)
	ELSIF ch = 0C2X THEN x := AosInputs.KsDown	(* down *)
	ELSIF ch = 0A4X THEN x := AosInputs.KsF1	(* f1 *)
	ELSIF ch = 0A5X THEN x := AosInputs.KsF2	(* f2 *)
	(*ELSIF ch = 0xxX THEN x := AosInputs.KsF3*)	(* f3 *)
	ELSIF ch = 0A7X THEN x := AosInputs.KsF4	(* f4 *)
	ELSIF ch = 0F5X THEN x := AosInputs.KsF5	(* f5 *)
	ELSIF ch = 0F6X THEN x := AosInputs.KsF6	(* f6 *)
	ELSIF ch = 0F7X THEN x := AosInputs.KsF7	(* f7 *)
	ELSIF ch = 0F8X THEN x := AosInputs.KsF8	(* f8 *)
	ELSIF ch = 0F9X THEN x := AosInputs.KsF9	(* f9 *)
	ELSIF ch = 0FAX THEN x := AosInputs.KsF10	(* f10 *)
	ELSIF ch = 0FBX THEN x := AosInputs.KsF11	(* f11 *)
	ELSIF ch = 0FCX THEN x := AosInputs.KsF12	(* f12 *)
	ELSE x := 0
	END;
	RETURN x
END KeySym;

(* InitKeyboard - Initialise the keyboard. *)

PROCEDURE InitKeyboard;
VAR s: SET; c: CHAR; i: SHORTINT; k: ARRAY 32 OF CHAR;
BEGIN
	keyval := -1; dkey := 0;
	mapflag[LAlt] := AosInputs.LeftAlt; mapflag[RAlt] := AosInputs.RightAlt;
	mapflag[LCtrl] := AosInputs.LeftCtrl; mapflag[RCtrl] := AosInputs.RightCtrl;
	mapflag[LShift] := AosInputs.LeftShift; mapflag[RShift] := AosInputs.RightShift;
		(* Get table *)
	AosBoot.GetConfig("Keyboard", k);
	i := 0; WHILE (k[i] # 0X) & (k[i] # ".") DO INC(i) END;
	IF k[i] = "." THEN table := TableFromFile(k)
	ELSE table := TableUS()
	END;
		(* Get compatibility option *)
	flags := {};
	NEW(keyboard);
		(* clear the keyboard's internal buffer *)
	i := 8;
	LOOP
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s));
		IF ~(0 IN s) OR (i = 0) THEN EXIT END;
		SYSTEM.PORTIN(60H, c);	(* read byte *)
		SYSTEM.PORTIN(61H, SYSTEM.VAL(CHAR, s));
		INCL(s, 7); SYSTEM.PORTOUT(61H, SYSTEM.VAL(CHAR, s));
		EXCL(s, 7); SYSTEM.PORTOUT(61H, SYSTEM.VAL(CHAR, s));	(* ack *)
		DEC(i)
	END;
	flags := {SetTypematic};
	AosBoot.GetConfig("NumLock", k);
	IF k[0] = "1" THEN INCL(flags, NumLock) END;
	SendByte(60H, 0F3X)	(* settypedel, will cause Ack from keyboard *)
END InitKeyboard;

PROCEDURE SetLayout*(par : ANY) : ANY; (** KeyboardLayoutFile ~ *)
VAR layoutFilename : ARRAY 256 OF CHAR; r : AosIO.StringReader;
BEGIN {EXCLUSIVE}
	IF (keyboard # NIL) THEN
		AosCommands.PosPar(par, r);
		r.String(layoutFilename);
		table := TableFromFile(layoutFilename);
	ELSE
		AosOut.String("AosKeyboard: No keyboard found."); AosOut.Ln;
	END;
	RETURN NIL
END SetLayout;

PROCEDURE Install*(par : ANY) : ANY;
BEGIN
	RETURN NIL;
END Install;

PROCEDURE Cleanup;
BEGIN
	IF (keyboard # NIL) & (AosModules.shutdown = AosModules.None) THEN
		keyboard.Finalize; keyboard := NIL
	END
END Cleanup;

BEGIN
	InitKeyboard;
	AosModules.InstallTermHandler(Cleanup)
END AosKeyboard.

(*
19.08.1999	pjm	Split from Aos.Input
20.09.2006	Added SetLayout (staubesv)
*)

AosKeyboard.Install ~

AosKeyboard.SetLayout KeyCH.Bin ~
AosKeyboard.SetLayout KeyUS.Bin ~

S.Free AosKeyboard ~