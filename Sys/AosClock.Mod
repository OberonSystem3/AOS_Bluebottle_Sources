(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosClock; (** AUTHOR "pjm"; PURPOSE "Real-time clock driver"; *)

IMPORT SYSTEM, AosBoot, AosOut, AosInterrupts, AosKernel, AosActive;

CONST
	Trace = FALSE;
	
TYPE
	Clock = OBJECT
		VAR
			clockmode: LONGINT;
			second, minute, hour, day, month, year: INTEGER;
		
		PROCEDURE ReadClock;
		BEGIN
			second := ORD(AosBoot.GetNVByte(0));  minute := ORD(AosBoot.GetNVByte(2));
			hour := ORD(AosBoot.GetNVByte(4));  day := ORD(AosBoot.GetNVByte(7));
			month := ORD(AosBoot.GetNVByte(8));  year := ORD(AosBoot.GetNVByte(9))
		END ReadClock;

		PROCEDURE HandleInterrupt;
		BEGIN {EXCLUSIVE}
			INC(Nints);
			IF clockmode = 0 THEN
				IF 4 IN SYSTEM.VAL(SET, LONG(ORD(AosBoot.GetNVByte(0CH)))) THEN ReadClock
				ELSE INC(Nmissed)
				END
			ELSE
				ReadClock
			END
		END HandleInterrupt;

		PROCEDURE Get(VAR time, date: LONGINT);
		VAR y, o, d, h, m, s: LONGINT;
		BEGIN {EXCLUSIVE}
			IF clockmode = 1 THEN	(* poll, ref p. 750 of undocumented pc *)
				REPEAT	(* until same clock value read twice in a row *)
					REPEAT UNTIL ~(7 IN SYSTEM.VAL(SET, LONG(ORD(AosBoot.GetNVByte(0AH)))));	(* no update in progress *)
					ReadClock;
					h := hour;  m := minute;  s := second;  y := year;  o := month;  d := day;
					ReadClock
				UNTIL (h = hour) & (m = minute) & (s = second) & (y = year) & (o = month) & (d = day)
			ELSE
				h := hour;  m := minute;  s := second;  y := year;  o := month;  d := day
			END;
			h := BCDToInt(h); m := BCDToInt(m); s := BCDToInt(s);
			y := BCDToInt(y);	(* returns 0..99, or possibly 0..165 on "fixed" clocks *)
			IF y < 90 THEN INC(y, 100) END;	(* if 0..89, modify it to 100..189 *)
			(* now y is 90..189, i.e. 1990..2089 *)
			o := BCDToInt(o); d := BCDToInt(d);
			time := h*4096 + m*64 + s;
			date := y*512 + o*32 + d
		END Get;

		PROCEDURE Set(time, date: LONGINT);
		BEGIN {EXCLUSIVE}
			AosBoot.PutNVByte(0BH, 82X);	(* disable clock & interrupt *)
			second := IntToBCD(time MOD 64);
			minute := IntToBCD(time DIV 64 MOD 64);
			hour := IntToBCD(time DIV 4096 MOD 32);
			day := IntToBCD(date MOD 32);
			month := IntToBCD(date DIV 32 MOD 16);
			year := IntToBCD(date DIV 512 MOD 100);
			AosBoot.PutNVByte(0, CHR(second));
			AosBoot.PutNVByte(2, CHR(minute));
			AosBoot.PutNVByte(4, CHR(hour));
			AosBoot.PutNVByte(7, CHR(day));
			AosBoot.PutNVByte(8, CHR(month));
			AosBoot.PutNVByte(9, CHR(year));
			AosBoot.PutNVByte(0BH, 12X)	(* 24 hour mode & 1 second interrupt *)
		END Set;
		
		PROCEDURE GetSecond(): LONGINT;
		BEGIN {EXCLUSIVE}
			RETURN second
		END GetSecond;
		
		PROCEDURE &InitClock;
		CONST Delay = 3;
		VAR p: LONGINT;  timer: AosKernel.MilliTimer;  s: ARRAY 8 OF CHAR;
		BEGIN
			second := -1;  p := 0;
			AosBoot.GetConfig("ClockMode", s);
			clockmode := AosBoot.StrToInt(p, s);	(* mode 0 - interrupt with test, mode 1 - poll, mode -1 - interrupt without test *)
			IF clockmode # 1 THEN
				AosActive.InstallHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0+8);
				AosBoot.PutNVByte(0BH, 12X);	(* 24 hour mode & 1 second interrupt *)
				AosKernel.SetTimer(timer, Delay*1000);	(* wait up to 3 seconds *)
				REPEAT UNTIL (GetSecond() # -1) OR AosKernel.Expired(timer)	(* wait for first update *)
			END;
			IF second = -1 THEN	(* clock interrupt not functioning *)
				second := 0;  minute := 0;  hour := 0;  day := 0;  month := 0;  year := 0;
				IF clockmode # 1 THEN
					AosActive.RemoveHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0+8)
				END;
				clockmode := 1	(* poll *)
			END;
			IF Trace THEN
				AosOut.String("AosClock: ClockMode = ");  AosOut.Int(clockmode, 1);  AosOut.Ln
			END
		END InitClock;

	END Clock;

VAR
	tz*: LONGINT;	(** system time zone offset in minutes (from -720 to 720) *)
	starttime*, startdate*: LONGINT;	(** time this module was loaded (usually boot time) *)
	clock: Clock;
	Nmissed, Nints: LONGINT;

(* BCDToInt/IntToBCD - Decode/Encode 2 BCD digits *)

PROCEDURE BCDToInt(x: LONGINT): LONGINT;
BEGIN
	RETURN (x DIV 16) * 10 + x MOD 16
END BCDToInt;

PROCEDURE IntToBCD(x: LONGINT): INTEGER;
BEGIN
	RETURN SHORT((x DIV 10) * 16 + x MOD 10)
END IntToBCD;

(** Return the current time and date in Oberon format. *)

PROCEDURE Get*(VAR time, date: LONGINT);
BEGIN
	clock.Get(time, date)
END Get;

(** Set the current time and date in Oberon format. *)

PROCEDURE Set*(time, date: LONGINT);
BEGIN
	clock.Set(time, date)
END Set;

BEGIN
	IF AosBoot.Trace THEN AosOut.Enter; AosOut.String("AosClock"); AosOut.Exit END;
	tz := 2*60;	(* fixme: configurable *)
	NEW(clock); Get(starttime, startdate)
END AosClock.

(*
23.08.1999	pjm	Split from Aos.Kernel
*)

(**
Notes

The time and date are that of the real-time clock of the system, which may be set to universal time, or to some local time zone.

The tz variable indicates the system time zone offset from universal time in minutes.  It may be updated at any time due to daylight savings time.  E.g. MET DST is 2 * 60 = 120.

The time and date are each represented in an encoded LONGINT.

Converting from year, month, day, hour, minute, second to time, date:
	time := hour*4096 + minute*64 + second;
	date := (year-1900)*512 + month*32 + day;

Converting from time to hour, minute, second:
	hour := time DIV 4096 MOD 32;
	minute := time DIV 64 MOD 64;
	second := time MOD 64;

Converting from date to year, month, day:
	year = 1900+date DIV 512;
	month = date DIV 32 MOD 16;
	day = date MOD 32;

All years in the current millenium can be represented.  The 1900 offset is a historical artefact from the Oberon system.

Time and date values (respectively) can be compared with the normal Oberon operators <, <=, =, >=, >, #.  Overflow at midnight has to be handled separately.
*)
