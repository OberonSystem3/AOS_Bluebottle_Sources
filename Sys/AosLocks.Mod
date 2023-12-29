(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosLocks; (** AUTHOR "pjm"; PURPOSE "Fine-grained kernel locks"; *)

IMPORT SYSTEM, AosBoot;

CONST
	StrongChecks = FALSE;	(* perform strong checks *)
	Stats = FALSE;	(* acquire statistics *)
	TimeCount = 0	(* 100000 *);	(* number of lock tries before checking timeout - 0 to disable *)
	
CONST
		(** standard lock levels (in order) *)	(* also refer to AosTrap.Show *)
	AosOutLow* = 0;	(* Trace output *)
	AosMemory* = 1;	(* Virtual memory management, stack and page allocation *)
	AosHeap* = 2;	(* Storage allocation and Garbage collection *)
	AosInterrupts* = 3;	(* Interrupt handling. *)
	AosModules* = 4;	(* Module list *)
	AosActive* = 5;	(* Ready queue *)
	AosProcessors* = 6;	(* Interprocessor interrupts *)
	AosOutHigh* = 7;	(* Atomic output *)
	(** highest level is all object locks *)
	
	Preemption* = 31;	(** flag for BreakAll() *)
	
	MaxLocks = 8;	(* { <= 32 } *)

	LowestLock = 0;  HighestLock = MaxLocks-1;
	
TYPE
	LockStats* = RECORD
		startTime-: HUGEINT;	(** last time lock acquire was started *)
		acquireTime-: HUGEINT;	(** last time lock was acquired *)
		sumHeldTime-: HUGEINT;	(** sum of time lock was held *)
(*		sumSqrHeldTime-: HUGEINT;	(** sum of sqr of time lock was held *) *) (* gone due to MulH using FPU during Taskswitch --> state change *)
		maxHeldTime-: HUGEINT;	(** max time lock was held *)
		sumWaitTime-: HUGEINT;	(** sum of time lock was waited for *)
		sumSqrWaitTime-: HUGEINT;	(** sum of sqr of time lock was waited for *)
		maxWaitTime-: HUGEINT;	(** max time lock was waited for *)
		numReleases-: LONGINT	(** number of times lock was released *)
		(* padding this structure to 2^N does not give measurable performance improvement *)
	END;

	Lock* = RECORD
		locked: BOOLEAN;	(* protects the count field, and the external shared data structure *)
		stats-: ARRAY AosBoot.MaxCPU OF LockStats	(** per-processor statistics *)
	END;

VAR
(*
Every element in the proc array belongs to one processor.  It is therefore sufficient to disable interrupts to protect the consistency of these elements.  Race conditions with interrupts handled on the same processor are avoided by disabling interrupts for the entire time that a lock is held (using locksHeld & state).  The stats field in the Lock record also separate the locks out on cache lines of their own, to avoid false sharing.
*)
	lock-: ARRAY MaxLocks OF Lock;	(** all locks *)
	proc-, trapState-: ARRAY AosBoot.MaxCPU OF RECORD
		locksHeld-: SET;	(** locks held by a processor *)
		state-: SET;	(** processor flags (interrupt state) at entry to its first lock *)
		preemptCount-: LONGINT;	(** if 0, preemption is allowed *)
		stats-: LockStats	(** preemption lock statistics *)
		(* padding this structure to 2^N does not give measurable performance improvement *)
	END;
	trapLocksBusy-: SET;
	maxTime: LONGINT;
	stats: BOOLEAN;
	(*nestEIP: ARRAY 32 OF LONGINT;
	nestLen: LONGINT;*)

(* Initialize locks. *)

PROCEDURE InitLocks;
VAR i: LONGINT; s: ARRAY 12 OF CHAR;
BEGIN
	stats := TRUE;
	IF TimeCount # 0 THEN
		AosBoot.GetConfig("LockTimeout", s);
		i := 0; maxTime := AosBoot.StrToInt(i, s);
		IF maxTime > MAX(LONGINT) DIV 1000000 THEN
			maxTime := MAX(LONGINT)
		ELSE
			maxTime := maxTime * 1000000
		END
	END;
	FOR i := 0 TO AosBoot.MaxCPU-1 DO
		proc[i].locksHeld := {}; proc[i].preemptCount := 0
	END;
	FOR i := 0 TO MaxLocks-1 DO
		lock[i].locked := FALSE
	END
END InitLocks;

(* Return flags state. *)

PROCEDURE -GetFlags(): SET;
CODE {SYSTEM.i386}
	PUSHFD
	POP EAX
END GetFlags;

(* Set flags state. *)

PROCEDURE -SetFlags(s: SET);
CODE {SYSTEM.i386}
	POPFD
END SetFlags;

PROCEDURE -PUSHFD;
CODE {SYSTEM.i386}
	PUSHFD
END PUSHFD;

PROCEDURE -POPFD;
CODE {SYSTEM.i386}
	POPFD
END POPFD;

PROCEDURE ComputeStats(VAR stats: LockStats);
VAR time: HUGEINT;
BEGIN
	(* held time *)
	time := AosBoot.SubH(AosBoot.GetTimer(), stats.acquireTime);
	IF AosBoot.GreaterH(time, stats.maxHeldTime) THEN
		stats.maxHeldTime := time
	END;
	stats.sumHeldTime := AosBoot.AddH(stats.sumHeldTime, time);
(*   stats.sumSqrHeldTime := AosBoot.AddH(stats.sumSqrHeldTime, AosBoot.MulH(time, time));  *)
		(* wait time *)
	time := AosBoot.SubH(stats.acquireTime, stats.startTime);
	IF AosBoot.GreaterH(time, stats.maxWaitTime) THEN
		stats.maxWaitTime := time
	END;
	stats.sumWaitTime := AosBoot.AddH(stats.sumWaitTime, time);
(*	stats.sumSqrWaitTime := AosBoot.AddH(stats.sumSqrWaitTime, AosBoot.MulH(time, time));  *)
	INC(stats.numReleases) 
END ComputeStats;

(** Disable preemption on the current processor (increment the preemption counter).  Returns the current processor ID as side effect. *)

PROCEDURE AcquirePreemption*(): LONGINT;
VAR id: LONGINT;
BEGIN
	PUSHFD; SYSTEM.CLI();
	id := AosBoot.ID();
	IF Stats & (proc[id].preemptCount = 0) THEN
		proc[id].stats.startTime := AosBoot.GetTimer();
		proc[id].stats.acquireTime := AosBoot.GetTimer()
	END;
	INC(proc[id].preemptCount);
	POPFD;
	RETURN id
END AcquirePreemption;

(** Enable preemption on the current processor (decrement the preemption counter). *)

PROCEDURE ReleasePreemption*;
VAR id: LONGINT;
BEGIN
	PUSHFD; SYSTEM.CLI();
	id := AosBoot.ID();
	IF StrongChecks THEN
		ASSERT(proc[id].preemptCount > 0)
	END;
	DEC(proc[id].preemptCount);
	IF Stats & (proc[id].preemptCount = 0) THEN
		ComputeStats(proc[id].stats)
	END;
	POPFD
END ReleasePreemption;

(** Return the preemption counter of the current processor (specified in parameter). *)

PROCEDURE PreemptCount*(id: LONGINT): LONGINT;
BEGIN
	IF StrongChecks THEN
		(*ASSERT(~(9 IN GetFlags()));*)	(* interrupts off *)	(* commented out because check is too strong *)
		ASSERT(id = AosBoot.ID())	(* caller must specify current processor *)
	END;
	RETURN proc[id].preemptCount
END PreemptCount;

(* Spin waiting for a lock.  Return AL = 1X iff timed out. *)

PROCEDURE AcquireSpinTimeout(VAR locked: BOOLEAN; count: LONGINT; flags: SET): CHAR;
CODE {SYSTEM.i386}
	MOV ESI, flags[EBP]	; ESI := flags
	MOV EDI, count[EBP]	; EDI := count
	MOV EBX, locked[EBP]	; EBX := ADR(locked)
	MOV AL, 1	; AL := 1
	CLI	; switch interrupts off before acquiring lock
	
test:
	CMP [EBX], AL	; locked? { AL = 1 }
	JE wait	; yes, go wait
	XCHG [EBX], AL	; set and read the lock atomically.  LOCK prefix implicit.
	CMP AL, 1	; was locked?
	JNE exit	; no, we have it now, interrupts are off, and AL # 1

wait:
; ASSERT(AL = 1)
	XOR ECX, ECX	; just in case some processor interprets REP this way
	REP NOP	; PAUSE instruction (* see AosBoot.SpinHint *)
	
	TEST ESI, 200H	; bit 9 - IF
	JZ intoff
	STI	; restore interrupt state quickly to allow pending interrupts (e.g. AosProcessors.StopAll/Broadcast)
	NOP	; NOP required, otherwise STI; CLI not interruptable
	CLI	; disable interrupts
intoff:

	DEC EDI	; counter
	JNZ test	; not timed out yet
	OR EDI, count[EBP]	; re-fetch original value & set flags
	JZ test	; if count = 0, retry forever
; timed out (AL = 1)

exit:
END AcquireSpinTimeout;

(*
PROCEDURE -CallerEIP(): LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 4[EBP]
END CallerEIP;

PROCEDURE AddNest(eip: LONGINT);
VAR i: LONGINT;
BEGIN
	IF nestLen # LEN(nestEIP) THEN
		i := 0; WHILE (i # nestLen) & (nestEIP[i] # eip) DO INC(i) END;
		IF i = nestLen THEN	(* new *)
			nestEIP[i] := eip; INC(nestLen)
		END
	END
END AddNest;
*)

(** Acquire a spin-lock and disable interrupts. *)

PROCEDURE Acquire*(level: LONGINT);
VAR id, i: LONGINT; flags: SET; start: HUGEINT;
BEGIN
	id := AcquirePreemption();
	flags := GetFlags();	(* store state of interrupt flag *)
	IF StrongChecks THEN
		ASSERT(~(9 IN flags) OR (proc[id].locksHeld = {}));	(* interrupts enabled => no locks held *)
		ASSERT(~(level IN proc[id].locksHeld))	(* recursive locks not allowed *)
	END;
	(*IF proc[id].locksHeld # {} THEN AddNest(CallerEIP()) END;*)
	IF Stats & stats THEN
		lock[level].stats[id].startTime := AosBoot.GetTimer()
	END;
	IF (TimeCount = 0) OR (maxTime = 0) THEN
		IF AcquireSpinTimeout(lock[level].locked, 0, flags) = 0X THEN END;	(* {interrupts off} *)
	ELSE
		start := AosBoot.GetTimer();
		WHILE AcquireSpinTimeout(lock[level].locked, TimeCount, flags) = 1X DO
			IF AosBoot.GreaterH(AosBoot.SubH(AosBoot.GetTimer(), start), AosBoot.LIntToHInt(maxTime)) THEN
				trapState := proc;
				trapLocksBusy := {};
				FOR i := 0 TO MaxLocks-1 DO
					IF lock[i].locked THEN INCL(trapLocksBusy, i) END
				END;
				HALT(1301)	(* Lock timeout - see AosTrap *)
			END
		END
	END;
	IF Stats & stats THEN
		lock[level].stats[id].acquireTime := AosBoot.GetTimer()
	END;
	IF proc[id].locksHeld = {} THEN
		proc[id].state := flags
	END;
	INCL(proc[id].locksHeld, level);	(* we now hold the lock *)
	IF StrongChecks THEN	(* no lower-level locks currently held by this processor *)
		ASSERT((level = 0) OR (proc[id].locksHeld * {0..level-1} = {}))
	END
END Acquire;

(** Release a spin-lock.  Switch on interrupts when last lock released. *)

PROCEDURE Release*(level: LONGINT);
VAR id: LONGINT; flags: SET;
BEGIN	(* {interrupts off} *)
	id := AosBoot.ID();
	IF StrongChecks THEN
		ASSERT(~(9 IN GetFlags()));	(* {interrupts off} *)
		ASSERT(lock[level].locked);
		ASSERT(level IN proc[id].locksHeld)
	END;
	EXCL(proc[id].locksHeld, level);
	IF proc[id].locksHeld = {} THEN
		flags := proc[id].state ELSE flags := GetFlags()
	END;
	lock[level].locked := FALSE;
	IF Stats & stats THEN
		ComputeStats(lock[level].stats[id])
	END;
	SetFlags(flags);
	ReleasePreemption
END Release;

(** Acquire all locks.  Only for exceptional cases.  *)

PROCEDURE AcquireAll*;
VAR lock: LONGINT;
BEGIN
	FOR lock := HighestLock TO LowestLock BY -1 DO Acquire(lock) END
END AcquireAll;

(** Release all locks.  Reverse of AcquireAll. *)

PROCEDURE ReleaseAll*;
VAR lock: LONGINT;
BEGIN
	FOR lock := LowestLock TO HighestLock DO Release(lock) END
END ReleaseAll;

(** Break all locks held by current processor (for exception handling).  Returns levels released. *)

PROCEDURE BreakAll*(): SET;
VAR id, level: LONGINT; released: SET;
BEGIN
	id := AcquirePreemption();
	PUSHFD; SYSTEM.CLI();
	released := {};
	FOR level := 0 TO MaxLocks-1 DO
		IF level IN proc[id].locksHeld THEN
			lock[level].locked := FALSE;	(* break the lock *)
			EXCL(proc[id].locksHeld, level);
			INCL(released, level)
		END
	END;
	IF proc[id].preemptCount > 1 THEN INCL(released, Preemption) END;
	proc[id].preemptCount := 0;	(* clear preemption flag *)
	POPFD;
	RETURN released
END BreakAll;

(** Acquire a fine-grained lock on an active object. *)

PROCEDURE AcquireObject*(VAR locked: BOOLEAN);
CODE {SYSTEM.i386}
	MOV EBX, locked[EBP]	; EBX := ADR(locked)
	MOV AL, 1
test:
	CMP [EBX], AL	; locked? { AL = 1 }
	JNE try
	XOR ECX, ECX	; just in case some processor interprets REP this way
	REP NOP	; PAUSE instruction (* see AosBoot.SpinHint *)
	JMP test
try:
	XCHG [EBX], AL	; set and read the lock atomically.  LOCK prefix implicit.
	CMP AL, 1	; was locked?
	JE test	; yes, try again
END AcquireObject;

(** Release an active object lock. *)

PROCEDURE ReleaseObject*(VAR locked: BOOLEAN);
CODE {SYSTEM.i386}
	MOV EBX, locked[EBP]	; EBX := ADR(locked)
	MOV BYTE [EBX], 0
END ReleaseObject;

PROCEDURE ClearStats(VAR stats: LockStats);
BEGIN
	IF Stats THEN
		stats.sumHeldTime := AosBoot.LIntToHInt(0);
(*		stats.sumSqrHeldTime := AosBoot.LIntToHInt(0); *)
		stats.maxHeldTime := AosBoot.LIntToHInt(0);
		stats.numReleases := 0
	END
END ClearStats;

(** Switch on statistics gathering. *)

PROCEDURE StatsOn*;
BEGIN
	IF Stats THEN stats := TRUE END
END StatsOn;

(** Switch off statistics gathering. *)

PROCEDURE StatsOff*;
BEGIN
	IF Stats THEN stats := FALSE END
END StatsOff;

(** Clear lock statistic counters. *)

PROCEDURE ClearLockStats*;
VAR i, j: LONGINT;
BEGIN
	IF Stats THEN
		FOR j := 0 TO AosBoot.MaxCPU-1 DO
			ClearStats(proc[j].stats);
			FOR i := 0 TO MaxLocks-1 DO
				ClearStats(lock[i].stats[j])
			END
		END
	END
END ClearLockStats;

BEGIN
	InitLocks;
	ClearLockStats
END AosLocks.

(*
03.03.1998	pjm	First version finalized
31.03.1998	pjm	Interrupts disabled while lock held & interrupts polled when Acquire'ing lock the first time
05.05.1998	pjm	Timeout
21.01.1999	pjm	Locks renamed to module names, order fixed
13.01.2000	pjm	Overed
13.09.2000	pjm	Removed Timeout
04.10.2000	pjm	DisablePreemption, etc.
30.05.2001	pjm	Removed nesting of locks on same processor
*)

AosTestLocks.Mod

(**
Notes

Accesses to the lock statistical counters are not synchronized.  Therefore the counters may contain stale values when read.

Once a lock is acquired, interrupts are disabled.

Critical regions are normally short.
*)
