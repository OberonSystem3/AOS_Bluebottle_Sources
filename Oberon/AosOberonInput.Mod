(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosOberonInput;	(* pjm *)
(** AUTHOR "pjm"; PURPOSE "Oberon for Aos standalone input driver"; *)

IMPORT AosOut, AosModules, AosInputs, AosPlugins, AosDisplays;

CONST
	BufSize = 32;
	
TYPE
	DefaultInput = OBJECT (AosInputs.OberonInput)
		VAR
			keyboard: KeyboardObj;
			mouse: MouseObj;
		
		PROCEDURE Mouse(VAR x, y: INTEGER; VAR keys:SET);
		BEGIN
			mouse.Mouse(x, y, keys)
		END Mouse;
		
		PROCEDURE Read(VAR ch: CHAR; VAR break: BOOLEAN);
		BEGIN
			keyboard.Read(ch, break)
		END Read;
		
		PROCEDURE Available(VAR num: INTEGER; VAR break: BOOLEAN);
		BEGIN
			keyboard.Available(num, break)
		END Available;

		PROCEDURE KeyState(VAR k: SET);
		BEGIN
			keyboard.KeyState(k)
		END KeyState;

	END DefaultInput;

TYPE
	KeyboardObj = OBJECT (AosInputs.Sink)
		VAR
			input: AosInputs.OberonInput;
		
			head, tail: LONGINT;
			keys: SET;
			break: BOOLEAN;
			buf: ARRAY BufSize OF CHAR;
		
		PROCEDURE Handle(VAR msg: AosInputs.Message);
		BEGIN {EXCLUSIVE}
			WITH msg: AosInputs.KeyboardMsg DO
				keys := {};
				IF msg.flags * AosInputs.Shift # {} THEN INCL(keys, AosInputs.SHIFT) END;
				IF msg.flags * AosInputs.Ctrl # {} THEN INCL(keys, AosInputs.CTRL) END;
				IF msg.flags * AosInputs.Alt # {} THEN INCL(keys, AosInputs.ALT) END;
				IF msg.ch # 0X THEN
					IF (tail+1) MOD BufSize # head THEN
						buf[tail] := msg.ch; tail := (tail+1) MOD BufSize
					END;
					IF input # NIL THEN input.timer.Wakeup END
				ELSIF msg.keysym = AosInputs.KsBreak THEN	(* Break *)
					break := TRUE;
					IF input # NIL THEN input.timer.Wakeup END
				ELSE
					(* skip *)
					(* fixme: wake up when key state changed? *)
				END
			END
		END Handle;
		
		PROCEDURE Read(VAR ch: CHAR; VAR b: BOOLEAN);
		BEGIN {EXCLUSIVE}
			AWAIT(head # tail);
			ch := buf[head]; head := (head+1) MOD BufSize;
			b := break; break := FALSE
		END Read;
		
		PROCEDURE Available(VAR num: INTEGER; VAR b: BOOLEAN);
		BEGIN {EXCLUSIVE}
			num := SHORT((tail-head) MOD BufSize);
			b := break; break := FALSE
		END Available;
		
		PROCEDURE KeyState(VAR k: SET);
		BEGIN {EXCLUSIVE}
			k := keys
		END KeyState;
		
		PROCEDURE &Init;
		BEGIN
			head := 0; tail := 0; keys := {}; break := FALSE;
			AosInputs.keyboard.Register(SELF)
		END Init;
		
	END KeyboardObj;

TYPE
	MouseObj = OBJECT (AosInputs.Sink)
		VAR
			input: AosInputs.OberonInput;
			curKeys: SET;
			curX, curY: INTEGER;
		
		PROCEDURE Handle(VAR msg: AosInputs.Message);
		BEGIN {EXCLUSIVE}
			WITH msg: AosInputs.PointerMsg DO
				curKeys := {};
				IF 0 IN msg.keys THEN INCL(curKeys, 2) END;
				IF 1 IN msg.keys THEN INCL(curKeys, 1) END;
				IF 2 IN msg.keys THEN INCL(curKeys, 0) END;
				curX := SHORT(msg.x); curY := SHORT(msg.y)
			END;
			IF input # NIL THEN input.timer.Wakeup END
		END Handle;
		
		PROCEDURE Mouse(VAR x, y: INTEGER; VAR keys: SET);
		BEGIN {EXCLUSIVE}
			keys := curKeys; x := curX; y := curY
		END Mouse;
		
		PROCEDURE &Init;
		BEGIN
			AosInputs.pointer.Register(SELF)
		END Init;
		
	END MouseObj;
	
VAR
	default: DefaultInput;

PROCEDURE Install*;
VAR res: LONGINT; p: AosPlugins.Plugin; d: AosDisplays.Display;
BEGIN
	IF default = NIL THEN
		p := AosDisplays.registry.Get("");	(* get first display *)
		IF p # NIL THEN	(* set mouse limits to first physical display (assuming we will use it) *)
			d := p(AosDisplays.Display);
			AosInputs.main.SetLimits(d.width, d.height, 0)
		ELSE
			AosOut.Enter;
			AosOut.String("Display driver must be installed before AosOberonInput");
			AosOut.Exit
		END;
		NEW(default);
		NEW(default.keyboard);
		NEW(default.mouse);
		default.keyboard.input := default; default.mouse.input := default;
		default.desc := "Default Input device";
		AosInputs.oberonInput.Add(default, res);
		ASSERT(res = 0)
	END
END Install;

PROCEDURE Remove*(par: PTR): PTR;
BEGIN
	IF default # NIL THEN AosInputs.oberonInput.Remove(default); default := NIL END;
	RETURN NIL
END Remove;

PROCEDURE SwitchToWM*;
VAR m: AosInputs.KeyboardMsg;
BEGIN
	IF default # NIL THEN
			(* send magic key to Oberon (assume Oberon.Loop will read it) *)
		m.ch := 0FEX; m.flags := {}; m.keysym := AosInputs.KsNil;
		default.keyboard.Handle(m)
	END
END SwitchToWM;

PROCEDURE Cleanup;
BEGIN
	IF Remove(NIL) = NIL THEN END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	default := NIL; Install
END AosOberonInput.
