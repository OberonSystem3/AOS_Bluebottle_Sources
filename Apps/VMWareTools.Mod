MODULE VMWareTools; (** AUTHOR "thomas.frey@alumni.ethz.ch"; PURPOSE "Tools to integrate BB into VMWare"; *)
(* Reference found on : http://chitchat.at.infoseek.co.jp/vmware/backdoor.html 
	Thanks to Ken Kato for this documentation 
*)

IMPORT
	SYSTEM, Utilities, AosModules, AosOut, WMWindowManager, WindowManager, WMMessages, AosTexts, AosTextUtilities, AosKernel;

TYPE 
	MouseGrabber= OBJECT
	VAR timer : AosKernel.Timer;
		alive : BOOLEAN;
		t : LONGINT;
	BEGIN	{ACTIVE}
		NEW(timer);
		alive := TRUE;
		WHILE alive DO
			timer.Sleep(10);
			t := ReadMouse();
		END;
	END MouseGrabber;

VAR
	manager : WMWindowManager.WindowManager;
	viewPort : WMWindowManager.ViewPort;
	w, h : LONGINT;
	hw : LONGINT;
	oldGUIBits : SET;
	mouseGrabber : MouseGrabber;
	textbuffer : Utilities.String;



PROCEDURE -ReadMouse() : LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	MOV ECX, 4
	MOV DX, 5658H
	IN EAX, DX;
END ReadMouse;

PROCEDURE -WriteMouse(pos : LONGINT);
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	POP EBX
	MOV ECX, 5
	MOV DX, 5658H
	OUT DX, EAX;
END WriteMouse;

PROCEDURE -SendLength(l : LONGINT);
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	POP EBX
	MOV ECX, 8
	MOV DX, 5658H
	OUT DX, EAX;
END SendLength;

PROCEDURE -Send4Chars(chars : LONGINT);
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	POP EBX
	MOV ECX, 9
	MOV DX, 5658H
	OUT DX, EAX;
END Send4Chars;

PROCEDURE -ReceiveLength() : LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	MOV ECX, 6
	MOV DX, 5658H
	IN EAX, DX;
END ReceiveLength;

PROCEDURE -Receive4Chars() : LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	MOV ECX, 7
	MOV DX, 5658H
	IN EAX, DX
END Receive4Chars;

PROCEDURE -GetVirtualHWVersion() : LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	MOV ECX, 11H
	MOV DX, 5658H
	IN EAX, DX
END GetVirtualHWVersion;

PROCEDURE -GetVMWareVersion() : LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	MOV ECX, 0AH
	MOV DX, 5658H
	IN EAX, DX
	MOV EAX, ECX
END GetVMWareVersion;

PROCEDURE -GetDeviceInformation(nrnr : LONGINT) : LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	POP EBX
	MOV ECX, 0BH
	MOV DX, 5658H
	IN EAX, DX
	MOV EAX, EBX
END GetDeviceInformation;

PROCEDURE -SetGUIOptions(options: SET);
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	POP EBX
	MOV ECX, 0EX
	MOV DX, 5658H
	OUT DX, EAX;
END SetGUIOptions;

PROCEDURE -GetGUIOptions(): SET;
CODE {SYSTEM.i386}
	MOV EAX, 564D5868H
	MOV ECX, 0DX
	MOV DX, 5658H
	IN EAX, DX;
END GetGUIOptions;

PROCEDURE SetMousePos(x, y : LONGINT);
VAR t : LONGINT;
BEGIN
	WriteMouse(x * 10000H + y); 
	t := ReadMouse(); (* readback seems to trigger the mouse exit routine *)
END SetMousePos;

PROCEDURE DevId; (* print one device ID...  only works for 1 device like this*)
VAR i, t : LONGINT; text : ARRAY 50 OF CHAR;
BEGIN
	FOR i := 0 TO 9 DO
		t := GetDeviceInformation(i * 4);
		SYSTEM.PUT32(SYSTEM.ADR(text[0]) + i * 4, t);
	END;
	AosOut.String(text);
END DevId;

PROCEDURE SetTextToClipBoard(VAR text : ARRAY OF CHAR);
VAR l, t, i, f : LONGINT;
BEGIN
	l := Utilities.Length(text);
	SendLength(l);
	t := 0;
	FOR i := 0 TO (l - 1) DIV 4 DO
		t := SYSTEM.GET32(SYSTEM.ADR(text[i * 4]));
		Send4Chars(t);	
	END;
END SetTextToClipBoard;

PROCEDURE GetTextFromClipBoard(VAR s : Utilities.String);
VAR l, t, i, f : LONGINT;
BEGIN
	l := ReceiveLength();
	IF (l > 0) & (l < 10000H) THEN 
		NEW(s, l + 5);
		f := SYSTEM.ADR(s[0]);
		FOR i := 0 TO (l - 1) DIV 4 DO
			t := Receive4Chars();
			SYSTEM.PUT32(f + i * 4, t);
		END;
	END
END GetTextFromClipBoard;

PROCEDURE GetHostClipboard*(par : ANY) : ANY;
VAR s : Utilities.String;
BEGIN
	GetTextFromClipBoard(s);
	AosTexts.clipboard.AcquireWrite;
	IF AosTexts.clipboard.GetLength() > 0 THEN AosTexts.clipboard.Delete(0, AosTexts.clipboard.GetLength()) END;
	AosTextUtilities.StrToText(AosTexts.clipboard, 0, s^);
	AosTexts.clipboard.ReleaseWrite;
	AosOut.String("Copied host clipboard text to AOS "); AosOut.Ln; 
	RETURN NIL
END GetHostClipboard;

PROCEDURE ClipboardChanged(sender, data : ANY);
BEGIN
	AosTextUtilities.TextToStr(AosTexts.clipboard, textbuffer^);
	SetTextToClipBoard(textbuffer^);
END ClipboardChanged;



(* This procedure is directly called by the window manager. It must be safe. *)
PROCEDURE MessagePreview(VAR m : WMMessages.Message; VAR discard : BOOLEAN);
BEGIN
	IF m.msgType = WMMessages.MsgPointer THEN
		SetMousePos(ENTIER((m.x - viewPort.range.l) * w / (viewPort.range.r - viewPort.range.l)) , 
					ENTIER((m.y  - viewPort.range.t) * h / (viewPort.range.b - viewPort.range.t)));
	END
END MessagePreview;

PROCEDURE Install*(par : ANY) : ANY;
BEGIN
	RETURN NIL
END Install;

PROCEDURE Cleanup;
BEGIN
	AosOut.String("Cleanup"); AosOut.Ln; 
	mouseGrabber.alive := FALSE;
	mouseGrabber.timer.Wakeup;
	SetGUIOptions({});
	(* removal must be done in all cases to avoid system freeze *)
	manager.RemoveMessagePreview(MessagePreview);
	AosTexts.clipboard.onTextChanged.Remove(ClipboardChanged)
END Cleanup;

BEGIN
	AosOut.String("Bimbo-VMWare Tools Installed"); AosOut.Ln; 
	hw := GetVirtualHWVersion();
	AosOut.String("VMVare Version : "); AosOut.Int(GetVMWareVersion(), 0); AosOut.Ln; ;
	AosOut.String("Virtual Hardware Version : "); AosOut.Int(hw, 0); AosOut.Ln; 
	AosOut.String("VMWare GUI Bits :");
	oldGUIBits := GetGUIOptions();
	AosOut.Bits(oldGUIBits, 0, 32); AosOut.Ln; 
	SetGUIOptions({0, 1, 2, 3, 4}); 
	
	NEW(textbuffer, 65536 + 5);
	
	(* register in clipboard *)
	AosTexts.clipboard.onTextChanged.Add(ClipboardChanged);
	
	(* register in window manager *)
	manager := WMWindowManager.GetDefaultManager();
	viewPort := WMWindowManager.GetDefaultView();
	w := viewPort(WindowManager.ViewPort).backbuffer.width;
	h := viewPort(WindowManager.ViewPort).backbuffer.height;
	manager.InstallMessagePreview(MessagePreview);
	
	NEW(mouseGrabber);
	AosModules.InstallTermHandler(Cleanup);
	
END VMWareTools.

VMWareTools.Install ~
VMWareTools.GetHostClipboard ~
S.Free VMWareTools ~

