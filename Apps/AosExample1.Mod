(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosExample1;	(* pjm *)

(*
Single resource monitor.
Ref: C.A.R. Hoare, "Monitors: An Operating System Structuring Concept", CACM 17(10), 1974
*)

TYPE
	Semaphore* = OBJECT
		VAR busy: BOOLEAN;
		
		PROCEDURE Acquire*;
		BEGIN {EXCLUSIVE}
			AWAIT(~busy);
			busy := TRUE
		END Acquire;
		
		PROCEDURE Release*;
		BEGIN {EXCLUSIVE}
			busy := FALSE
		END Release;
		
		PROCEDURE &Init;
		BEGIN
			busy := FALSE
		END Init;
		
	END Semaphore;

END AosExample1.
