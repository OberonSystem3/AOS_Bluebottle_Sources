(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosMouseSerial; (** AUTHOR "pjm"; PURPOSE "Serial mouse driver"; *)

(* Aos serial mouse driver (quick and dirty port from Native Input.Mod and ConfigInput.Mod). *)

(* AFI 12.03.2003 - procedure Configure modified to support 8 serial ports i.o. 4 *)

(*
	Mouse protocol information from XFree in X11R6 distribution (Thomas Roell & David Dawes)
*)

IMPORT SYSTEM, AosBoot, AosOut, AosModules, AosKernel, AosInputs, V24;

CONST
	Trace = TRUE;
	
		(* mouse types *)
	MinType = 0;  MaxType = 9;
	MS = 0;  MSC1 = 1;  MM = 2;  Logi = 3;  MSC2 = 4;  LogiMan = 5;  PS2 = 6;  MSI = 7;  MSC3 = 8;  MSC4 = 9;
(*
	0  Microsoft serial (2-button)
	1  Mouse Systems Corp serial type a (dtr on, rts on)
	2  Logitech serial Type a (old models)
	3  Logitech serial Type b (old models)
	4  Mouse Systems Corp serial type b (dtr off, rts off)
	5  Logitech serial Type c (new models)
	6  PS/2 mouse (default)
	7  Microsoft serial IntelliMouse
	8  Mouse Systems Corp serial type c (dtr off, rts on)
	9  Mouse Systems Corp serial type d (dtr on, rts off)
	
	MT=PS2  PS/2 or built-in
	MT=LM1  Logitech 1
	MT=LM2  Logitech 2
	MT=LM3  Logitech 3
	MT=MS1  Mouse Systems 1
	MT=MS2  Mouse Systems 2
	MT=MS3  Mouse Systems 3
	MT=MS4  Mouse Systems 4
	MT=MSM  Microsoft (2-button)
	MT=MSI  Microsoft IntelliMouse
	MP=1
	MP=2
*)

	NONE = -2;
	
	Rate = 100;	(* Sampling rate *)
	BPS = 1200;	(* Speed *)
	
	DetectOffTime = 250;	(* ms *)
	DetectOnTime = 250;	(* ms *)
	DetectMaxIdent = 256;
	
TYPE
	Reader = OBJECT
		VAR m: AosInputs.MouseMsg; keys: SET;
	BEGIN {ACTIVE}
		LOOP
			IF GetMouseEvent(keys, m.dx, m.dy) THEN
				m.dz := 0; m.keys := {};
				IF 0 IN keys THEN INCL(m.keys, 2) END;
				IF 1 IN keys THEN INCL(m.keys, 1) END;
				IF 2 IN keys THEN INCL(m.keys, 0) END;
				AosInputs.mouse.Handle(m)
			END
		END
	END Reader;

VAR
	mouseErrors: LONGINT;
	
		(* mouse state *)
	port, oldport, newport: INTEGER;	(* Serial mouse port, bps and report rate (if supported) *)
	type: SHORTINT;	(* mouse type *)
	mbufp, numb: SHORTINT;	(* buffer pointer & protocol bytes *)
	mbuf: ARRAY 5 OF SET;	(* protocol buffer *)
	mask0, val0, mask1, val1, lastkeys: SET;	(* protocol parameters *)
	reader: Reader;

PROCEDURE SerialRead(port: LONGINT;  VAR c: SYSTEM.BYTE);
VAR res: LONGINT;
BEGIN
	V24.Receive(port, c, res)
END SerialRead;

PROCEDURE SerialWrite(port: LONGINT;  c: SYSTEM.BYTE);
VAR res: LONGINT;
BEGIN
	V24.Send(port, c, res)
END SerialWrite;

PROCEDURE SerialAvailable(port: LONGINT): LONGINT;
VAR n: LONGINT;
BEGIN
	IF port # NONE THEN
		n := V24.Available(port)
	ELSE
		n := 0
	END;
	RETURN n
END SerialAvailable;

(* ---- Mouse driver ---- *)

(* SetSpeed - Set mouse speed *)

PROCEDURE SetSpeed(old, new: LONGINT);
VAR word, stop, par: INTEGER;  c: CHAR;  res: LONGINT;  t: AosKernel.MilliTimer;
BEGIN
	IF oldport # NONE THEN V24.Stop(oldport) END;
	oldport := port;
	CASE type OF
		MS:  word := 7;  stop := V24.Stop1;  par := V24.ParNo |
		MSC1, MSC2, MSC3, MSC4:  word := 8;  stop := V24.Stop2;  par := V24.ParNo |
		MM:  word := 8;  stop := V24.Stop1;  par := V24.ParOdd |
		Logi:  word := 8;  stop := V24.Stop2;  par := V24.ParNo |
		LogiMan:  word := 7;  stop := V24.Stop1;  par := V24.ParNo |
		MSI:  word := 7;  stop := V24.Stop1;  par := V24.ParNo
	END;
	IF (type = Logi) OR (type = LogiMan) THEN
		V24.Start(port, old, word, par, stop, res);
		IF res = V24.Ok THEN
			IF new = 9600 THEN c := "q"
			ELSIF new = 4800 THEN c := "p"
			ELSIF new = 2400 THEN c := "o"
			ELSE c := "n"
			END;
			SerialWrite(port, "*");  SerialWrite(port, c);
			AosKernel.SetTimer(t, 100);
			REPEAT UNTIL AosKernel.Expired(t);
			V24.Stop(port)
		END
	END;
	V24.Start(port, new, word, par, stop, res);
	IF res = V24.Ok THEN
		V24.SetMC(port, {V24.DTR, V24.RTS})
	END
END SetSpeed;

(* InitMouse - Initialise mouse.
	"type" - mouse type from list
	"port" - V24.COM[12]
	"bps" - V24.BPS*
	"rate" - sample rate (not all mice support this) *)

PROCEDURE InitMouse;
VAR c: CHAR; timer: AosKernel.MilliTimer; n: INTEGER;
BEGIN
	IF type # PS2 THEN
		port := newport;
		mouseErrors := 0;
		IF oldport # NONE THEN V24.Stop(oldport) END;
		oldport := NONE;
		IF type = LogiMan THEN
			SetSpeed(1200, 1200);
			SerialWrite(port, "*");  SerialWrite(port, "X");
			SetSpeed(1200, BPS)
		ELSE
			SetSpeed(9600, BPS);
			SetSpeed(4800, BPS);
			SetSpeed(2400, BPS);
			SetSpeed(1200, BPS);
			IF type = Logi THEN
				SerialWrite(port, "S");  type := MM;  SetSpeed(BPS, BPS);  type := Logi
			END;
				(* set sample rate *)
			IF Rate <= 0 THEN c := "O"	(* continuous - don't use *)
			ELSIF Rate <= 15 THEN c := "J"	(* 10 Hz *)
			ELSIF Rate <= 27 THEN c := "K"	(* 20 *)
			ELSIF Rate <= 42 THEN c := "L"	(* 35 *)
			ELSIF Rate <= 60 THEN c := "R"	(* 50 *)
			ELSIF Rate <= 85 THEN c := "M"	(* 70 *)
			ELSIF Rate <= 125 THEN c := "Q"	(* 100 *)
			ELSE c := "N"	(* 150 *)
			END;
			SerialWrite(port, c);
			IF type = MSC2 THEN V24.ClearMC(port, {V24.DTR, V24.RTS})
			ELSIF type = MSC3 THEN V24.ClearMC(port, {V24.DTR})
			ELSIF type = MSC4 THEN V24.ClearMC(port, {V24.RTS})
			END
		END;
		mbufp := 0;  lastkeys := {};
			(* protocol parameters *)
		CASE type OF
			MS:  numb := 3;  mask0 := {6};  val0 := {6};  mask1 := {6};  val1 := {} |
			MSC1, MSC2, MSC3, MSC4:  numb := 5;  mask0 := {3..7};  val0 := {7};  mask1 := {};  val1 := {} |
			MM:  numb := 3;  mask0 := {5..7};  val0 := {7};  mask1 := {7};  val1 := {} |
			Logi:  numb := 3;  mask0 := {5..7};  val0 := {7};  mask1 := {7};  val1 := {} |
			LogiMan:  numb := 3;  mask0 := {6};  val0 := {6};  mask1 := {6};  val1 := {} |
(*
			PS2:  numb := 3;  mask0 := {6,7};  val0 := {};  mask1 := {};  val1 := {} |
*)
			MSI: numb := 4;  mask0 := {6};  val0 := {6};  mask1 := {6};  val1 := {}
		END;
			(* ignore the first few bytes from the mouse (e.g. Logitech MouseMan Sensa) *)
		n := 4;
		REPEAT
			WHILE SerialAvailable(port) # 0 DO SerialRead(port, c) END;
			AosKernel.SetTimer(timer, 1000 DIV n); DEC(n);	(* wait 1/4s, 1/3s, 1/2s, 1s *)
			REPEAT UNTIL AosKernel.Expired(timer)
		UNTIL (SerialAvailable(port) = 0) OR (n = 0)
	END;
		(* Lower/Raise DTR/RTS for autodetection, and to start an Intellimouse *)
	V24.ClearMC(port, {V24.DTR, V24.RTS});
	AosKernel.SetTimer(timer, DetectOffTime);
	REPEAT UNTIL AosKernel.Expired(timer);
	V24.SetMC(port, {V24.DTR, V24.RTS});
	AosKernel.SetTimer(timer, DetectOnTime);
	REPEAT UNTIL AosKernel.Expired(timer)
END InitMouse;

(* GetMouseEvent - Read a mouse event *)

PROCEDURE GetMouseEvent(VAR keys: SET;  VAR dx, dy: LONGINT): BOOLEAN;
VAR b: SET;
BEGIN
	b := {};  SerialRead(port, SYSTEM.VAL(CHAR, b));
		(* check for resync *)
	IF (mbufp # 0) & ((b * mask1 # val1) OR (b = {7})) THEN mbufp := 0 END;
	IF (mbufp = 0) & (b * mask0 # val0) THEN
			(* skip package, unless it is a LogiMan middle button... *)
		IF ((type = MS) OR (type = LogiMan)) & (b * {2..4,6,7} = {}) THEN
			keys := lastkeys * {0,2};
			IF 5 IN b THEN INCL(keys, 1) END;
			dx := 0;  dy := 0;
			RETURN TRUE
		ELSE
			INC(mouseErrors)
		END
	ELSE
		mbuf[mbufp] := b;  INC(mbufp);
		IF mbufp = numb THEN
			CASE type OF
				MS, LogiMan:
					keys := lastkeys * {1};
					IF 5 IN mbuf[0] THEN INCL(keys, 2) END;
					IF 4 IN mbuf[0] THEN INCL(keys, 0) END;
					dx := LONG(SYSTEM.VAL(SHORTINT, SYSTEM.LSH(mbuf[0] * {0,1}, 6) + mbuf[1] * {0..5}));
					dy := LONG(SYSTEM.VAL(SHORTINT, SYSTEM.LSH(mbuf[0] * {2,3}, 4) + mbuf[2] * {0..5})) |
				MSC1, MSC2, MSC3, MSC4:
					keys := {0..2} - (mbuf[0] * {0..2});
					dx := LONG(SYSTEM.VAL(SHORTINT, mbuf[1])) + LONG(SYSTEM.VAL(SHORTINT, mbuf[3]));
					dy := -(LONG(SYSTEM.VAL(SHORTINT, mbuf[2])) + LONG(SYSTEM.VAL(SHORTINT, mbuf[4]))) |
				MM, Logi:
					keys := mbuf[0] * {0..2};
					dx := SYSTEM.VAL(INTEGER, mbuf[1]);
					IF ~(4 IN mbuf[0]) THEN dx := -dx END;
					dy := SYSTEM.VAL(INTEGER, mbuf[2]);
					IF 3 IN mbuf[0] THEN dy := -dy END |
(*
				PS2:
					keys := {};
					IF 2 IN mbuf[0] THEN INCL(keys, 1) END;
					IF 1 IN mbuf[0] THEN INCL(keys, 0) END;
					IF 0 IN mbuf[0] THEN INCL(keys, 2) END;
					dx := SYSTEM.VAL(INTEGER, mbuf[1]);
					IF 4 IN mbuf[0] THEN DEC(dx, 256) END;
					dy := -SYSTEM.VAL(INTEGER, mbuf[2]);
					IF 5 IN mbuf[0] THEN INC(dy, 256) END |
*)
				MSI:
					keys := {};
					IF 4 IN mbuf[0] THEN INCL(keys, 0) END;
					IF 5 IN mbuf[0] THEN INCL(keys, 2) END;
					IF 3 IN mbuf[3] THEN INCL(keys, 3) END;
					IF 4 IN mbuf[3] THEN INCL(keys, 1) END;
					IF ~(3 IN mbuf[3]) & (mbuf[3] * {0..2} # {}) THEN INCL(keys, 4) END;
					dx := LONG(SYSTEM.VAL(SHORTINT, SYSTEM.LSH(mbuf[0] * {0,1}, 6) + mbuf[1] * {0..7}));
					dy := LONG(SYSTEM.VAL(SHORTINT, SYSTEM.LSH(mbuf[0] * {2,3}, 4) + mbuf[2] * {0..7}))
			END; (* CASE *)
			mbufp := 0;
			RETURN TRUE
		END
	END;
	keys := lastkeys;  dx := 0;  dy := 0;
	RETURN FALSE
END GetMouseEvent;

PROCEDURE SetMouseType(s: ARRAY OF CHAR);
BEGIN
	type := MinType-1;
	IF (s[0] >= "0") & (s[0] <= "9") THEN	(* old style config *)
		type := SHORT(ORD(s[0])-ORD("0"))
	ELSE	(* new style config *)
		IF s = "" THEN
			(* default if none specified *)
		ELSIF (CAP(s[0]) = "L") & (CAP(s[1]) = "M") THEN	(* Logitech *)
			CASE s[2] OF
				"1": type := LogiMan
				|"2": type := MM
				|"3": type := Logi
			END
		ELSIF (CAP(s[0]) = "M") & (CAP(s[1]) = "S") THEN	(* Mouse Systems or Microsoft *)
			IF CAP(s[2]) = "M" THEN type := MS
			ELSIF CAP(s[2]) = "I" THEN type := MSI
			ELSE
				CASE s[2] OF
					"1": type := MSC1
					|"2": type := MSC2
					|"3": type := MSC3
					|"4": type := MSC4
				END
			END
		ELSIF CAP(s[0]) = "P" THEN	(* PS/2 *)
			type := PS2
		END
	END;
	IF (type < MinType) OR (type > MaxType) THEN type := PS2 END;	(* unknown mouse type *)
(*
	IF Trace THEN
		Kernel.WriteString("MouseType=");  Kernel.WriteInt(type, 1);
		Kernel.WriteChar(" ");  Kernel.WriteInt(newport, 1);
		Kernel.WriteLn
	END;
*)
	InitMouse
END SetMouseType;

(* Configure input device parameters.  Normally only used by installation program. *)
PROCEDURE Configure(config, value: ARRAY OF CHAR);	(** non-portable *)
BEGIN
	IF Trace THEN
		AosOut.Enter;
		AosOut.String("AosMouseSerial: ");  AosOut.String(config);  AosOut.Char("="); AosOut.String(value);
		AosOut.Exit
	END;
	IF config = "MT" THEN	(* mouse type *)
		SetMouseType(value)
	ELSIF config = "MP" THEN	(* mouse port *)
		IF (value[0] >= "1") & (value[0] <= "8") THEN
			newport := V24.COM1 + (ORD(value[0])-ORD("1"))
		ELSE
			newport := V24.COM1
		END
	ELSE
(*
		IF Trace THEN Kernel.WriteString("Unknown setting");  Kernel.WriteLn END
*)
	END
END Configure;

PROCEDURE Setting(name: ARRAY OF CHAR);
VAR s: ARRAY 16 OF CHAR;
BEGIN
	AosBoot.GetConfig(name, s);  Configure(name, s)
END Setting;

PROCEDURE Install*;
VAR np: INTEGER; mouseIdent: ARRAY DetectMaxIdent OF CHAR;

	PROCEDURE Detect(port: INTEGER): BOOLEAN;
		VAR portString: ARRAY 2 OF CHAR; ch: CHAR; n, i, comport: INTEGER;
	BEGIN
		portString := "0"; portString[0] := CHR(ORD("0") + port);
		comport := V24.COM1 + (port-1);
		Configure("MP", portString); Configure("MT", "MSM"); (*arbitrary*)
			(* Previous call will lower and raise DTR/RTS *)
		REPEAT
			IF SerialAvailable(comport) = 0 THEN RETURN FALSE END;
			SerialRead(comport, ch);
			IF ch >= 80X THEN ch := CHR(ORD(ch)-80H) END
		UNTIL ch = "M";
		mouseIdent[0] := ch; i := 1;
		WHILE (SerialAvailable(comport) # 0) & (i < DetectMaxIdent-1) DO
			SerialRead(comport, ch);
			IF ch >= 80X THEN ch := CHR(ORD(ch)-80H) END;
			IF (ch < " ") OR (ch >= 7FX) THEN ch := "." END;
			mouseIdent[i] := ch; INC(i)
		END;
		mouseIdent[i] := 0X;
		IF Trace THEN
			AosOut.Enter; AosOut.String("Mouse ident:"); AosOut.Ln; AosOut.Buffer(mouseIdent, 0, i); AosOut.Exit
		END;
		RETURN TRUE
	END Detect;

BEGIN
	IF oldport = NONE THEN
		AosBoot.GetConfig("MT", mouseIdent);
		IF mouseIdent[0] # 0X THEN	(* manual config *)
			Setting("MP"); Setting("MT")	(* also calls InitMouse *)
		ELSE	(* auto config *)
			np := SHORT(V24.NumberOfPorts());
			IF (np >= 1) & Detect(1) OR (np >= 2) & Detect(2) OR (np >= 3) & Detect(3) OR (np >= 4) & Detect(4) THEN
				IF mouseIdent[1] = "3" THEN Configure("MT", "LM1")
				ELSIF mouseIdent[1] = "Z" THEN Configure("MT", "MSI")
				ELSE Configure("MT", "MSM")
				END
			ELSE type := PS2
			END
		END;
		IF reader = NIL THEN NEW(reader) END
	END
END Install;

PROCEDURE Remove*;
BEGIN
	AosOut.String("AosMouseSerial.Remove"); AosOut.Ln	(* to do *)
END Remove;

BEGIN
	AosModules.InstallTermHandler(Remove);
	oldport := NONE; reader := NIL;
	Install
END AosMouseSerial.

AosMouseSerial.Install

System.Free AosMouseSerial ~
