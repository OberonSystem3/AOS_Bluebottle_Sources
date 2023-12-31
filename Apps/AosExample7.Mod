(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosExample7;	(* pjm *)

(*
Recursive locks.  The critical regions protected by these locks may be re-entered by the process holding them.

Usage:

VAR lock: RecursiveLock;

	NEW(lock);
	...
	lock.Acquire();
	... (* critical section (without AWAIT) *)
	lock.Release()
*)

IMPORT AosActive;

TYPE
	RecursiveLock* = OBJECT
		VAR lockedBy: PTR; level: LONGINT;
		
		PROCEDURE Acquire*;
		VAR me: PTR;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			IF lockedBy = me THEN
				ASSERT(level # -1);	(* overflow *)
				INC(level)
			ELSE
				AWAIT(lockedBy = NIL);
				lockedBy := me; level := 1
			END
		END Acquire;
		
		PROCEDURE Release*;
		BEGIN {EXCLUSIVE}
			ASSERT(lockedBy = AosActive.ActiveObject());	(* must hold lock *)
			DEC(level);
			IF level = 0 THEN lockedBy := NIL END
		END Release;
		
		PROCEDURE &Init;
		BEGIN
			lockedBy := NIL; level := 0
		END Init;
		
	END RecursiveLock;

END AosExample7.
