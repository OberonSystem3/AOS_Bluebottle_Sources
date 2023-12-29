(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosBeep; (** AUTHOR "pjm"; PURPOSE "PC speaker driver"; *)

IMPORT SYSTEM;

CONST
	Rate = 1193180;	(* timer clock is 1.19318 MHz *)

(** Sound the PC speaker continuously at the specified frequency.  Use 0 to switch off the sound.  Not sharable. *)

PROCEDURE Beep*(hz: LONGINT);
VAR s: SET;
BEGIN {EXCLUSIVE}
		(* stop counter *)
	SYSTEM.PORTIN(61H, SYSTEM.VAL(CHAR, s));
	SYSTEM.PORTOUT(61H, CHR(SYSTEM.VAL(LONGINT, s - {0,1})));
	IF hz > 0 THEN
		hz := Rate DIV hz;
			(* init counter for hz *)
		SYSTEM.PORTOUT(43H, 0B6X);	(* timer 2, 16-bit, mode 3, binary *)
		SYSTEM.PORTOUT(42H, CHR(hz MOD 100H));
		SYSTEM.PORTOUT(42H, CHR(hz DIV 100H));
			(* start counter *)
		SYSTEM.PORTIN(61H, SYSTEM.VAL(CHAR, s));
		SYSTEM.PORTOUT(61H, SYSTEM.VAL(CHAR, s + {0,1}))
	END
END Beep;

END AosBeep.
