 (* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosPerformance; (** AUTHOR "pjm"; PURPOSE "Performance measurements"; *)

IMPORT AosOut, AosBoot, AosModules, AosActive, AosKernel, AosRandom, Math;

CONST
	LoadPeriod = 5;	(* load sample interval in seconds *)
	IdlePeriod = 10;	(* idle sample interval in seconds *)
	
	Time0 = 1; Time1 = 5; Time2 = 15;	(* average load accumulates in minutes *)

	Trace = FALSE;

TYPE
	Monitor = OBJECT
		VAR
			period: LONGINT; rand: AosRandom.Generator; timer: AosKernel.Timer;
			loops: LONGINT; state: SHORTINT;
		
		PROCEDURE &Init(period: LONGINT; randomized: BOOLEAN);
		BEGIN
			SELF.period := period; state := 0;
			IF randomized THEN NEW(rand) ELSE rand := NIL END
		END Init;
		
		PROCEDURE Compute(loops: LONGINT);	(* abstract *)
		END Compute;
		
		PROCEDURE Stop;
		BEGIN {EXCLUSIVE}
			IF state = 0 THEN INC(state) END;
			timer.Wakeup;
			AWAIT(state = 2)	(* body terminated *)
		END Stop;
		
	BEGIN {ACTIVE, PRIORITY(AosActive.High)}
		NEW(timer); loops := 0;
		WHILE state = 0 DO
			INC(loops); Compute(loops);
			IF rand # NIL THEN
				timer.Sleep(ENTIER(period*(1000*2)*rand.Uniform()))
			ELSE
				timer.Sleep(period*1000)
			END
		END;
		BEGIN {EXCLUSIVE} INC(state) END
	END Monitor;

TYPE
	LoadMonitor = OBJECT (Monitor)	(* singleton *)
		VAR exp: ARRAY 3 OF REAL;
		
		PROCEDURE &Init(period: LONGINT; randomized: BOOLEAN);
		BEGIN
			Init^(period, randomized);
			load[0] := 0; load[1] := 0; load[2] := 0;
			exp[0] := 1/Math.exp(period/(Time0*60));
			exp[1] := 1/Math.exp(period/(Time1*60));
			exp[2] := 1/Math.exp(period/(Time2*60))
		END Init;
		
		PROCEDURE Compute(loops: LONGINT);
		VAR n: LONGINT;
		BEGIN
			n := AosActive.NumReady() - 1;	(* subtract one for fridge light *)
			UpdateLoad(load[0], exp[0], n);
			UpdateLoad(load[1], exp[1], n);
			UpdateLoad(load[2], exp[2], n);
			IF Trace THEN
				AosOut.Int(loops, 8); AosOut.Int(n, 3);
				WriteLoad(load[0]); WriteLoad(load[1]); WriteLoad(load[2]);
				AosOut.Ln
			END
		END Compute;
		
	END LoadMonitor;

TYPE
	IdleMonitor = OBJECT (Monitor)	(* singleton *)
		VAR time: LONGINT; idlecount: ARRAY AosBoot.MaxCPU OF LONGINT;
		
		PROCEDURE &Init(period: LONGINT; randomized: BOOLEAN);
		VAR i: LONGINT;
		BEGIN
			Init^(period, randomized);
			FOR i := 0 TO AosBoot.MaxCPU-1 DO
				idlecount[i] := AosActive.idlecount[i]; idle[i] := -1
			END;
			time := AosKernel.GetTimer()
		END Init;
		
		PROCEDURE Compute(loops: LONGINT);
		VAR i, ic, id, t, td: LONGINT;
		BEGIN
			t := AosKernel.GetTimer(); td := t - time; time := t;
			IF td = 0 THEN td := 1 END;	(* avoid divide by 0 *)
			FOR i := 0 TO AosBoot.MaxCPU-1 DO
				ic := AosActive.idlecount[i];
				id := ic - idlecount[i]; idlecount[i] := ic;
				IF ic # 0 THEN	(* processor alive, ignore wrap *)
					idle[i] := id*100 DIV td	(* LONGINT assignments are atomic *)
				END
			END;
			IF Trace THEN
				AosOut.Int(loops, 8);
				FOR i := 0 TO AosBoot.MaxCPU-1 DO AosOut.Int(idle[i], 5) END;
				AosOut.Ln
			END
		END Compute;

	END IdleMonitor;

VAR
	load*: ARRAY 3 OF REAL;	(** load estimates *)
	idle*: ARRAY AosBoot.MaxCPU OF LONGINT;	(** idle percentage estimates *)
	loadmon: LoadMonitor;
	idlemon: IdleMonitor;

PROCEDURE UpdateLoad(VAR load: REAL; exp: REAL; n: LONGINT);
BEGIN
	load := load*exp + (1-exp)*n	(* REAL assigments are atomic *)
END UpdateLoad;

PROCEDURE WriteLoad(load: REAL);
VAR x: LONGINT;
BEGIN
	IF Trace THEN
		x := ENTIER(load*100 + 0.5);
		AosOut.Int(x DIV 100, 3); AosOut.Char(".");
		AosOut.Int(x DIV 10 MOD 10, 1); AosOut.Int(x MOD 10, 1)
	END
END WriteLoad;

PROCEDURE Cleanup;
BEGIN
	IF loadmon # NIL THEN loadmon.Stop; loadmon := NIL END;
	IF idlemon # NIL THEN idlemon.Stop; idlemon := NIL END
	(* race with object bodies on Free! *)
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	IF loadmon = NIL THEN NEW(loadmon, LoadPeriod, TRUE) END;
	IF idlemon = NIL THEN NEW(idlemon, IdlePeriod, FALSE) END
END AosPerformance.

(**
Notes:
o "load" is a Unix-like estimate of the average number of ready and running processes over the past 1, 5 and 15 minutes.
o "idle" is an estimate of the percentage of idle time per processor over the last 10 seconds.
o When a processor is not available, its idle estimate is -1.
*)

(*
to do:
o fix idle on single-processor
o adjust idle computation to timeslice rate (currently assumes timeslice rate = AosTimer rate)
o AosKernel.GetTimer and AosActive.idlecount effects can give 101% idle
*)

System.Free AosPerformance ~

System.ShowCommands AosPerformance

System.State AosPerformance
