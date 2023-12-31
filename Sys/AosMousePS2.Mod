(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosMousePS2; (** AUTHOR "pjm"; PURPOSE "PS/2 mouse driver"; *)

(*
	Mouse protocol information from XFree in X11R6 distribution (Thomas Roell & David Dawes)
	PS/2 Aux port information from Linux (Johan Myreen et al.)
*)

IMPORT SYSTEM, AosBoot, AosInterrupts, AosModules, AosActive, AosKernel, AosInputs;

TYPE
	Aux = OBJECT
		VAR
			p, numb: LONGINT;
			buf: ARRAY 4 OF SET;
			active: BOOLEAN;
			timer: AosActive.Timer;
		
		PROCEDURE HandleInterrupt;
		VAR b: SET; m: AosInputs.MouseMsg; ch: CHAR;
		BEGIN {EXCLUSIVE}
			SYSTEM.PORTIN(64H, ch); (* check for valid data *)
			IF SYSTEM.VAL(SET, ch) * {0} = {} THEN INC(ignored); RETURN	END;
			SYSTEM.PORTIN(60H, ch);	(* read byte *)
			IF active THEN
				b := SYSTEM.VAL(SET, LONG(ORD(ch)));
				IF (p = 0) & (b * {6,7} # {}) THEN	(* skip package *)
					INC(errors)
				ELSE
					buf[p] := b; INC(p);
					IF p = numb THEN
						m.keys := {};
						IF 2 IN buf[0] THEN INCL(m.keys, 1) END;
						IF 1 IN buf[0] THEN INCL(m.keys, 2) END;
						IF 0 IN buf[0] THEN INCL(m.keys, 0) END;
						m.dx := SYSTEM.VAL(LONGINT, buf[1]);
						IF 4 IN buf[0] THEN DEC(m.dx, 256) END;
						m.dy := SYSTEM.VAL(LONGINT, buf[2]);
						IF 5 IN buf[0] THEN DEC(m.dy, 256) END;
						m.dz := SYSTEM.VAL(SHORTINT, buf[3]);
						IF 6 IN buf[0] THEN DEC(m.dz, 256) END;
						p := 0; m.dy := -m.dy;
						AosInputs.mouse.Handle(m)
					END
				END
			ELSE
				INC(ignored)
			END
		END HandleInterrupt;
		
		PROCEDURE HandleTimeout;
		BEGIN {EXCLUSIVE}
			active := TRUE
		END HandleTimeout;
		
		PROCEDURE &Init(rate: LONGINT);

			PROCEDURE SetRate(r: LONGINT);
			BEGIN WriteAck(0F3X);  WriteAck(CHR(r))
			END SetRate;
			
		BEGIN
			active := FALSE; p := 0;
			PollAux;
			SYSTEM.PORTOUT(64H, 0A8X);	(* enable aux *)
				(* enable MS Intellimouse 3rd button *)
			SetRate(200); SetRate(100); SetRate(80); SetRate(rate);
			WriteAck(0F2X);
			IF InAux() # 0X THEN numb := 4 ELSE numb := 3 END;	(* Ident *)
			WriteAck(0E8X);  WriteAck(3X);	(* 8 counts/mm *)
			WriteAck(0E7X);	(* 2:1 scale *)
			PollAux;
			AosActive.InstallHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0+12);
			WriteDev(0F4X);	(* enable aux device *)
			WriteCmd(47X);	(* controller interrupts on *)
			PollAux;
			NEW(timer); AosActive.SetTimeout(timer, SELF.HandleTimeout, 250)	(* ignore bytes in first 1/4s *)
		END Init;
		
		PROCEDURE Remove;
		BEGIN {EXCLUSIVE}
			AosActive.RemoveHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0+12);
			AosActive.CancelTimeout(timer)
		END Remove;
	
	END Aux;

VAR
	errors*, ignored*: LONGINT;	(* diagnostic counters *)
	aux: Aux;

PROCEDURE PollAux;
VAR s: SET; i: LONGINT; t: AosKernel.MilliTimer;
BEGIN
	i := 10;	(* up to 0.2s! *)
	LOOP
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s));
		IF (s * {0,1} = {}) OR (i = 0) THEN EXIT END;
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s));
		IF s * {0,5} = {0,5} THEN SYSTEM.PORTIN(60H, SYSTEM.VAL(CHAR, s)) END;	(* byte avail *)
		AosKernel.SetTimer(t, 20);	(* 20ms *)
		REPEAT UNTIL AosKernel.Expired(t);
		DEC(i)
	END
END PollAux;

PROCEDURE InAux(): CHAR;
VAR s: SET; t: AosKernel.MilliTimer;ch: CHAR; i: SHORTINT; 
BEGIN
	i := 10;	(* up to 0.2s! *)
	REPEAT
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s));
		IF s * {0,5} = {0,5} THEN 	(* byte avail *)
			SYSTEM.PORTIN(60H, ch);
			RETURN ch
		END;
		AosKernel.SetTimer(t, 20);
		REPEAT UNTIL AosKernel.Expired(t);
		DEC(i);
	UNTIL i = 0;
	RETURN 0X
END InAux;
PROCEDURE WriteDev(b: CHAR);
BEGIN
	PollAux; SYSTEM.PORTOUT(64H, 0D4X);	(* aux data coming *)
	PollAux; SYSTEM.PORTOUT(60H, b)
END WriteDev;

PROCEDURE WriteAck(b: CHAR);
VAR s: SET; i: LONGINT; t: AosKernel.MilliTimer;
BEGIN
	WriteDev(b); i := 10;	(* up to 0.2s! *)
	LOOP
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s));
		IF (s * {0,5} = {0,5}) OR (i = 0) THEN EXIT END;
		AosKernel.SetTimer(t, 20);	(* 20ms *)
		REPEAT UNTIL AosKernel.Expired(t);
		DEC(i)
	END;
	IF i # 0 THEN SYSTEM.PORTIN(60H, SYSTEM.VAL(CHAR, s)) END	(* byte avail *)
END WriteAck;

PROCEDURE WriteCmd(b: CHAR);
BEGIN
	PollAux; SYSTEM.PORTOUT(64H, 60X);
	PollAux; SYSTEM.PORTOUT(60H, b)
END WriteCmd;

PROCEDURE ConfigMouse;
VAR i, rate: LONGINT; s: ARRAY 16 OF CHAR;
BEGIN
	errors := 0; ignored := 0;
	AosBoot.GetConfig("MouseRate", s);
	i := 0; rate := AosBoot.StrToInt(i, s);
	IF (rate <= 0) OR (rate > 150) THEN rate := 100 END;
	NEW(aux, rate)
END ConfigMouse;

PROCEDURE Install*;
BEGIN
	IF aux = NIL THEN ConfigMouse END
END Install;

PROCEDURE Remove*;
BEGIN
	IF aux # NIL THEN aux.Remove(); aux := NIL END
END Remove;

BEGIN
	AosModules.InstallTermHandler(Remove);
	aux := NIL; Install
END AosMousePS2.
