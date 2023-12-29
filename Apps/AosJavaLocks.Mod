(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosJavaLocks;	(* pjm *)

(*
Java-like locks for Aos.
The timeout case is very ugly, because handling external events is currently difficult.
Ref: The Java Language Specification, section 17.13-17.14
*)

IMPORT AosActive;

TYPE
	JavaLock* = OBJECT
		VAR
			depth, in, out: LONGINT;
			locker: PTR;
		
		PROCEDURE Lock*;
		VAR me: PTR;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			AWAIT((locker = NIL) OR (locker = me));
			INC(depth);
			locker := me
		END Lock;
		
		PROCEDURE Unlock*;
		BEGIN {EXCLUSIVE}
			ASSERT(locker = AosActive.ActiveObject());
			DEC(depth);
			IF depth = 0 THEN locker := NIL END
		END Unlock;
		
		PROCEDURE Wait*;
		VAR ticket, mydepth: LONGINT; me: PTR;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			ASSERT(locker = me);
			mydepth := depth; depth := 0; locker := NIL;
			ticket := in; INC(in);
			AWAIT((ticket - out < 0) & (locker = NIL));
			depth := mydepth; locker := me
		END Wait;
		
		PROCEDURE WaitTime*(ms: LONGINT);
		VAR ticket, mydepth: LONGINT; me: PTR; sleeper: Sleeper;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			ASSERT(locker = me);
			mydepth := depth; depth := 0; locker := NIL;
			ticket := in; INC(in);
			NEW(sleeper, SELF, ms);	(* allocate a sleeper for the current thread *)
			AWAIT((sleeper.done OR (ticket - out < 0)) & (locker = NIL));
			sleeper.Stop;
			depth := mydepth; locker := me
		END WaitTime;
		
		PROCEDURE Notify*;
		BEGIN {EXCLUSIVE}
			ASSERT(locker = AosActive.ActiveObject());
			IF out # in THEN INC(out) END
		END Notify;
		
		PROCEDURE NotifyAll*;
		BEGIN {EXCLUSIVE}
			ASSERT(locker = AosActive.ActiveObject());
			out := in
		END NotifyAll;
		
		PROCEDURE Wakeup;
		BEGIN {EXCLUSIVE}
		END Wakeup;
		
		PROCEDURE &Init;
		BEGIN
			depth := 0; locker := NIL; in := 0; out := 0
		END Init;
		
	END JavaLock;

TYPE
	Sleeper = OBJECT (AosActive.Timer)	(* to do: simplify this *)
		VAR lock: JavaLock; done: BOOLEAN;
		
		PROCEDURE HandleTimeout;
		BEGIN {EXCLUSIVE}
			IF lock # NIL THEN done := TRUE; lock.Wakeup END
		END HandleTimeout;
		
		PROCEDURE Stop;
		BEGIN {EXCLUSIVE}
			lock := NIL; AosActive.CancelTimeout(SELF)
		END Stop;
		
		PROCEDURE &Start(lock: JavaLock; ms: LONGINT);
		BEGIN
			SELF.lock := lock; done := FALSE;
			AosActive.SetTimeout(SELF, SELF.HandleTimeout, ms)
		END Start;
		
	END Sleeper;
	
END AosJavaLocks.
