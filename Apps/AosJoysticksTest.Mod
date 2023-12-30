MODULE AosJoysticksTest; (** AUTHOR: "staubesv"; PURPOSE: "Joystick simulator for testing purposes"; *)
(**
 * Usage:
 *
 *	AosJoysticksTest.CreateJoystick [nbrOfButtons] ~ creates a new simulated joystick 
 *	S.Free AosJoysticksTest ~	unload module, unregisters all simulated joysticks at AosJoysticks.registry
 *
 * History:
 *
 *	28.11.2006	First release (staubesv)
 *)

IMPORT
	AosOut, AosModules, AosKernel, AosPlugins, AosCommands, AosIO, AosRandom, AosJoysticks;
	
CONST
	DefaultNbrOfButtons = 2;
	
	MaxSimulatedJoysticks = 16;
	
	MinAxisValueX = -255;
	MaxAxisValueX = 255;
	
	MinAxisValueY = 0;
	MaxAxisValueY = 1024;
	
	MinAxisValueSlider1 = -16384;
	MaxAxisValueSlider1 = 16384;
	
	MinAxisDefaultValue = -1024;
	MaxAxisDefaultValue = 1024;

	MinSleepTime = 200;
	MaxSleepTime = 1500;
	
TYPE

	SimulatedJoystick = OBJECT(AosJoysticks.Joystick)
	VAR 
		msg : AosJoysticks.JoystickDataMessage; 
		random : AosRandom.Generator;
		timer : AosKernel.Timer;
		alive, dead : BOOLEAN;
		i, minValue, maxValue : LONGINT;
	
		PROCEDURE Stop;
		BEGIN {EXCLUSIVE}
			alive := FALSE; timer.Wakeup;
			AWAIT(dead);
		END Stop;
		
		PROCEDURE &Init(nbrOfButtons  : LONGINT);
		BEGIN
			Init^(nbrOfButtons);
			alive := TRUE; dead := FALSE;
			NEW(timer);
			NEW(random);
		END Init;
	
	BEGIN {ACTIVE}
		WHILE alive DO
			FOR i := 0 TO nbrOfButtons-1 DO
				IF random.Dice(2) = 1 THEN
					INCL(msg.buttons, i);
				ELSE
					EXCL(msg.buttons, i);
				END;
			END;
			FOR i := 0 TO AosJoysticks.MaxNbrOfAxis - 1 DO
				IF i IN implementedAxis THEN
					CASE i OF
						| AosJoysticks.AxisX: minValue := MinAxisValueX; maxValue := MaxAxisValueX;
						| AosJoysticks.AxisY: minValue := MinAxisValueY; maxValue := MaxAxisValueY;
						| AosJoysticks.Slider1: minValue := MinAxisValueSlider1; maxValue := MaxAxisValueSlider1;
					ELSE
						minValue := MinAxisDefaultValue; maxValue := MaxAxisDefaultValue;
					END;
					msg.axis[i] := random.Dice(maxValue - minValue) + 1 + minValue;
				END;
			END;
			FOR i := 0 TO nbrOfCoolieHats-1 DO
				EXCL(msg.coolieHat[i], random.Dice(4));
				EXCL(msg.coolieHat[i], random.Dice(4));
				INCL(msg.coolieHat[i], random.Dice(4));
			END;
			Handle(msg);
			timer.Sleep(random.Dice(MaxSleepTime - MinSleepTime) + MinSleepTime);
		END;
		BEGIN {EXCLUSIVE} dead := TRUE; END;
	END SimulatedJoystick;

VAR
	joysticks : ARRAY MaxSimulatedJoysticks OF SimulatedJoystick; 
	nbrOfJoysticks : LONGINT;

PROCEDURE CreateJoystick*(par : ANY) : ANY; (* [nbrOfButtons] ~ *)
VAR joystick : SimulatedJoystick; r : AosIO.StringReader; nbrOfButtons, nbrOfAxis, res : LONGINT;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace;
	r.Int(nbrOfButtons, FALSE);
	r.SkipWhitespace;
	r.Int(nbrOfAxis, FALSE);
	IF nbrOfButtons <= 0 THEN nbrOfButtons := DefaultNbrOfButtons; END;
	IF nbrOfJoysticks < LEN(joysticks) THEN
		NEW(joystick, nbrOfButtons);
		joystick.AddAxis(AosJoysticks.AxisX, MinAxisValueX, MaxAxisValueX);
		joystick.AddAxis(AosJoysticks.AxisY, MinAxisValueY, MaxAxisValueY);
		joystick.AddAxis(AosJoysticks.Slider1, MinAxisValueSlider1, MaxAxisValueSlider1);
		joystick.AddCoolieHat;
		joystick.AddCoolieHat;
		joystick.desc := "Simulated Joystick";
		joysticks[nbrOfJoysticks] := joystick;
		INC(nbrOfJoysticks);
		AosJoysticks.registry.Add(joystick, res);
		IF res = AosPlugins.Ok THEN
			AosOut.String("Joystick created."); AosOut.Ln;
		ELSE
			AosOut.String("Could not add joystick to registry, res: "); AosOut.Int(res, 0); AosOut.Ln;
		END;
	ELSE
		AosOut.String("Maximum number of joysticks exceeded."); AosOut.Ln;
	END;
	RETURN NIL
END CreateJoystick;

PROCEDURE Cleanup;
VAR i : LONGINT;
BEGIN
	FOR i := 0 TO MaxSimulatedJoysticks - 1 DO
		IF joysticks[i] # NIL THEN
			joysticks[i].Stop;
			AosJoysticks.registry.Remove(joysticks[i]);
			joysticks[i] := NIL;
		END;
	END;	
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END AosJoysticksTest.

AosJoysticks.Show ~

AosJoysticksTest.CreateJoystick ~

S.Free WMJoysticks AosJoysticksTest AosJoysticks ~

WMJoysticks.Open ~