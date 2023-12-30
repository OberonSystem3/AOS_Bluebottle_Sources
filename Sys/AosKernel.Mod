(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosKernel; (** AUTHOR "pjm"; PURPOSE "Implementation-independent kernel interface"; *)

IMPORT SYSTEM, AosBoot, AosOut, AosHeap, AosMemory, AosActive, AosProcessors, AosLocks;

CONST
	TraceFin = TRUE;	(* show memory stats when finalizing *)

	TimerFree = 0; TimerSleeping = 1; TimerWoken = 2; TimerExpired = 3;	(* Timer state *)
	
TYPE
	(** Finalizer for FinalizedCollection.Add. *)
	Finalizer* = AosHeap.Finalizer;	(** PROCEDURE (obj: PTR) *)
	
	(** Enumerator for FinalizedCollection.Enumerate. *)
	Enumerator* = PROCEDURE {DELEGATE} (obj: PTR; VAR cont: BOOLEAN);
	
	FinalizerNode = POINTER TO RECORD (AosHeap.FinalizerNode)
		nextObj [UNTRACED]: FinalizerNode;	(* in Collection c *)
		c: FinalizedCollection;	(* collection containing object *)
	END;
	
	(** Polling timer. *)
	MilliTimer* = RECORD start, target: LONGINT END;

TYPE
	(** Delay timer. *)
	Timer* = OBJECT
		VAR timer: AosActive.Timer; state: SHORTINT;
		
		PROCEDURE HandleTimeout;
		BEGIN {EXCLUSIVE}
			IF state # TimerFree THEN state := TimerExpired END
		END HandleTimeout;
		
		(** Delay the calling process the specified number of milliseconds or until Wakeup is called.  Only one process may sleep on a specific timer at a time. *)
		
		PROCEDURE Sleep*(ms: LONGINT);
		BEGIN {EXCLUSIVE}
			ASSERT(state = TimerFree);	(* only one process may sleep on a timer *)
			state := TimerSleeping;
			AosActive.SetTimeout(timer, HandleTimeout, ms);
			AWAIT(state # TimerSleeping);
			IF state # TimerExpired THEN AosActive.CancelTimeout(timer) END;
			state := TimerFree
		END Sleep;
		
		(** Wake up the process sleeping on the timer, if any. *)
		
		PROCEDURE Wakeup*;
		BEGIN {EXCLUSIVE}
			IF state = TimerSleeping THEN state := TimerWoken END
		END Wakeup;
		
		(** Initializer. *)
		
		PROCEDURE &Init;
		BEGIN
			state := TimerFree; NEW(timer)
		END Init;
		
	END Timer;
	
TYPE
	(** A collection of objects that are finalized automatically by the garbage collector. *)
	FinalizedCollection* = OBJECT
		VAR root: FinalizerNode;	(* weak list of contents linked by nextObj *)
		
		(** Add obj to collection.  Parameter fin specifies finalizer, or NIL if not required. *) (* may be called multiple times *)
		
		PROCEDURE Add*(obj: PTR; fin: Finalizer);
		VAR n: FinalizerNode;
		BEGIN
			NEW(n); n.c := SELF; n.finalizer := fin;
			AosHeap.AddFinalizer(obj, n);
			BEGIN {EXCLUSIVE}
				n.nextObj := root.nextObj; root.nextObj := n	(* add to collection *)
			END
		END Add;
		
		(** Remove one occurrence of obj from collection. *)
		
		PROCEDURE Remove*(obj: PTR);
		VAR p, n: FinalizerNode;
		BEGIN {EXCLUSIVE}
			p := root; n := p.nextObj;
			WHILE (n # NIL) & (n.objWeak # obj) DO
				p := n; n := n.nextObj
			END;
			IF n # NIL THEN p.nextObj := n.nextObj END;
			(* leave in global finalizer list *)
		END Remove;
	
		(** Remove all occurrences of obj from collection. *)
		
		PROCEDURE RemoveAll*(obj: PTR);
		VAR p, n: FinalizerNode;
		BEGIN {EXCLUSIVE}
			p := root; n := p.nextObj;
			WHILE n # NIL DO
				IF n.objWeak = obj THEN p.nextObj := n.nextObj END;
				p := n; n := n.nextObj
			END
		END RemoveAll;

		(** Enumerate all objects in the collection (Enumerator may not call Remove, Add, Enumerate or Clear). *)
		
		PROCEDURE Enumerate*(enum: Enumerator);
		VAR fn, next: FinalizerNode; cont: BOOLEAN;
		BEGIN {EXCLUSIVE}
			fn := root.nextObj; cont := TRUE;
			WHILE fn # NIL DO
				next := fn.nextObj;	(* current (or other) object may be removed by enum call *)
				enum(fn.objWeak, cont);
				IF cont THEN fn := next ELSE fn := NIL END
			END
		END Enumerate;
		(** Enumerate all objects in the collection not being finalized (Enumerator may not call Remove, Add, Enumerate or Clear). *)
		
		PROCEDURE EnumerateN*( enum: Enumerator );
		VAR fn, next: FinalizerNode;  cont: BOOLEAN;  obj: PTR;
		BEGIN {EXCLUSIVE}
			fn := root.nextObj;  cont := TRUE;
			WHILE fn # NIL DO
				next := fn.nextObj;   (* current (or other) object may be removed by enum call *)
				obj := NIL;
				
				AosLocks.Acquire( AosLocks.AosProcessors );   (* prevent GC from running *)
				
				IF (fn.objWeak # NIL ) & (fn.objStrong = NIL ) THEN  (* object is not yet on the finalizers list  *)
					obj := fn.objWeak;   (* now object is locally referenced, will therefore not be GCed *)
				END;
				
				AosLocks.Release(AosLocks.AosProcessors);
				
				IF obj # NIL THEN enum( obj, cont );  END;
				IF cont THEN fn := next ELSE fn := NIL END
			END
		END EnumerateN;
		
		(** Initialize new collection.  May also be called to clear an existing collection. *)
		
		PROCEDURE &Clear;
		BEGIN {EXCLUSIVE}
			NEW(root); root.nextObj := NIL	(* head *)
		END Clear;
		
	END FinalizedCollection;

TYPE
	FinalizerCaller = OBJECT	(* separate active object that calls finalizers *)
		VAR n: AosHeap.FinalizerNode; activated: BOOLEAN;
		
		PROCEDURE &Init;
		BEGIN
			activated := FALSE
		END Init;
		
		PROCEDURE Activate;
		BEGIN {EXCLUSIVE}
			activated := TRUE
		END Activate;
		
	BEGIN {ACTIVE, SAFE, PRIORITY(AosActive.High)}
		LOOP
			BEGIN {EXCLUSIVE}
				AWAIT(activated); activated := FALSE
			END;
			LOOP
				n := AosHeap.GetFinalizer();
				IF n = NIL THEN EXIT END;
				IF n IS FinalizerNode THEN
					n(FinalizerNode).c.RemoveAll(n.objStrong)	(* remove it if it is not removed yet *)
				END;
				IF n.finalizer # NIL THEN
					n.finalizer(n.objStrong)	(* may acquire locks *)
				END
			END;
			IF TraceFin & (AosHeap.traceHeap # {}) THEN Watch END
		END
	END FinalizerCaller;

VAR
	second*: LONGINT;	(** number of timer counts per second (Hz) *)
	finalizer: FinalizerCaller;

(* help procedures *)

PROCEDURE Watch;
VAR free, total1, total2, largest, low, high: LONGINT;
BEGIN
	IF TraceFin THEN
		AosHeap.GetHeapInfo(total1, free, largest);
		total1 := (total1+512) DIV 1024;
		free := (free+512) DIV 1024;
		largest := (largest+512) DIV 1024;
		AosMemory.GetFreeK(total2, low, high);
		AosOut.Enter;
		AosOut.String("Heap: ");
		AosOut.Int(total1, 1); AosOut.String(" total, ");
		AosOut.Int(free, 1); AosOut.String(" free, ");
		AosOut.Int(largest, 1); AosOut.String(" largest, Mem: ");
		AosOut.Int(total2, 1); AosOut.String(" total, ");
		AosOut.Int(low, 1); AosOut.String(" low, ");
		AosOut.Int(high, 1); AosOut.String(" high");
		AosOut.Exit
	END
END Watch;

(** -- Garbage collection -- *)

(** Activate the garbage collector immediately. *)

PROCEDURE GC*;
BEGIN
	AosProcessors.GlobalGC;
	IF ~AosMemory.WorkingOnKernelStack() THEN (* exclusive lock of Activate can only be performed with a user stack *)
		finalizer.Activate	(* finalizers will be called by seperate process *)
	ELSE
		 AosOut.String("GC working on kernel stack"); AosOut.Ln
	END
END GC;

(** -- Timers -- *)

(** Get the current timer count.  Timer increment rate is stored in "second" variable in Hz. *)

PROCEDURE GetTimer*(): LONGINT;
BEGIN
	RETURN AosActive.ticks
END GetTimer;

(** Set timer to expire in approximately "ms" milliseconds. *)

PROCEDURE SetTimer*(VAR t: MilliTimer;  ms: LONGINT);
BEGIN
	IF AosActive.Second # 1000 THEN	(* convert to ticks *)
		ASSERT((ms >= 0) & (ms <= MAX(LONGINT) DIV AosActive.Second));
		ms := ms * AosActive.Second DIV 1000
	END;
	IF ms < 5 THEN INC(ms) END;	(* Nyquist adjustment *)
	t.start := AosActive.ticks;
	t.target := t.start + ms
END SetTimer;

(** Test whether a timer has expired. *)

PROCEDURE Expired*(VAR t: MilliTimer): BOOLEAN;
BEGIN
	RETURN AosActive.ticks - t.target >= 0
END Expired;

(** Return elapsed time on a timer in milliseconds. *)

PROCEDURE Elapsed*(VAR t: MilliTimer): LONGINT;
BEGIN
	RETURN (AosActive.ticks - t.start) * (1000 DIV AosActive.Second)
END Elapsed;

(** Return time left on a timer in milliseconds. *)

PROCEDURE Left*(VAR t: MilliTimer): LONGINT;
BEGIN
	RETURN (t.target - AosActive.ticks) * (1000 DIV AosActive.Second)
END Left;

(** -- Atomic operations -- *)

(** Atomic INC(x). *)

PROCEDURE -AtomicInc*(VAR x: LONGINT);
CODE {SYSTEM.i386}
	POP EAX
	LOCK
	INC DWORD [EAX]
END AtomicInc;

(** Atomic INC(x, y). *)

PROCEDURE -AtomicAdd*(VAR x: LONGINT; y: LONGINT);
CODE {SYSTEM.i386}
	POP EBX
	POP EAX
	LOCK
	ADD DWORD [EAX], EBX
END AtomicAdd;

(** Atomic test-and-set.  Set x = TRUE and return old value of x. *)

PROCEDURE -AtomicTestSet*(VAR x: BOOLEAN): BOOLEAN;
CODE {SYSTEM.i386}
	POP EBX
	MOV AL, 1
	XCHG [EBX], AL
END AtomicTestSet;

BEGIN
	ASSERT(1000 MOD AosActive.Second = 0);	(* for Elapsed *)
	second := AosActive.Second;
	NEW(finalizer);	(* activate finalizer object *)
	AosHeap.GC := GC	(* switch to GC procedure with finalization *)
END AosKernel.

(**
Notes:
o The FinalizedCollection object implements collections of finalized objects.
o Objects added to a finalized collection (with Add) are removed automatically by the garbage collector when no references to them exist any more.  They can also be removed explicitly with Remove.
o All the objects currently in a collection can be enumerated by Enumerate, which takes an enumerator procedure as parameter.  The enumerator can also be a method in an object, which is useful when state information is required during the enumeration.  The enumerator may not call other methods of the same collection.
o An object in a finalized collection can have an finalizer procedure associated with it, which gets called by a separate process when there are no references left to the object any more.  A finalizer is usually used for some cleanup functions, e.g. releasing external resources. It is executed exactly once per object.  During the next garbage collector cycle the object is finally removed.
*)

(*
to do:
o cancel finalizer when removing object
o fix module free race: module containing finalizer is freed.  although the finalizer list is cleared, the FinalizerCaller has already taken a reference to a finalizer, but hasn't called it yet.
o consider: a module has a FinalizedCollection, without finalizers (NIL).  when the module is freed, the objects are still in the finalization list, and will get finalized in the next garbage collection.  The FinalizedCollection will survive the first collection, as the objects all have references to it through their c field.  After all objects have been finalized, the FinalizedCollection itself is collected.  No dangling pointers occur, except the untraced module field references from the type descriptors, which are only used for tracing purposes.
o check cyclic dependencies between finalized objects.
o GetTime(): LONGINT - return current time in ms
o Delay(td: LONGINT) - wait td ms
o AwaitTime(t: LONGINT) - wait at least until time t
o Wakeup(obj: PTR) - wake up object that is waiting
*)
