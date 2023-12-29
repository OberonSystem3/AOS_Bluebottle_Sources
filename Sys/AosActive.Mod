(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosActive; (** AUTHOR "pjm"; PURPOSE "Active object runtime support"; *)

IMPORT SYSTEM, AosBoot, AosLocks, AosOut, AosMemory, AosHeap, AosInterrupts, AosModules;

CONST
		(** Process flags (first one defined by compiler in OPC.CallRecBody) *)
	Restart* = 0;	(* Restart/Destroy process on exception *)
	Preempted* = 27;	(* Has been preempted. *)
	Resistant* = 28;	(* Can only be destroyed by itself *)
	PleaseHalt* = 30;	(* Process requested to Halt itself soon *)
	PleaseStop* = 31;	(* Process requested to Terminate or Halt itself soon *)

		(** Process modes *)
	Unknown* = 0; Ready* = 1; Running* = 2; AwaitingLock* = 3;
	AwaitingCond* = 4; AwaitingEvent* = 5; Terminated* = 6;
	
	MinIRQ = AosInterrupts.IRQ0;
	NumIRQ = AosInterrupts.MaxIRQ-MinIRQ+1;

		(** Process priorities *)
	MinPriority = 0;	(* only system idle processes run at this priority level *)
	Low* = 1; Normal* = 2; High* = 3;	(* "user" priorities *)
	Realtime* = 4; (* reserved for interrupt handling and realtime apps *)
	NumPriorities = 5;	(* number of priority levels *)
	
	Second* = 1000;	(* frequency of ticks increments in Hz *)
	
	Stats = FALSE;	(* maintain statistical counters *)
	Trace = FALSE;	(* write out verbose trace info *)
	StrongChecks = FALSE;	(* strong sanity checks *)
	VeryConservative = FALSE;	(* temp - be very conservative about stack-based pointers *)
	ObjectLock = TRUE;	(* use object-level fine-grained locks *)
	YieldTrick = FALSE;	(* avoid yield when no ready process available *)
	HandleInvPriority = FALSE;
	
TYPE
	ProtectedObject = POINTER TO RECORD END;	(* protected object (10000) *)
	ObjectHeader = POINTER TO RECORD	(* header of a protected object (0000X) - cf. AosHeap.NewType *)
			(* should not be used as global variable or record field, because of AosHeap.Mark *)
		size, sentinel: LONGINT;	(* null TypeDesc for GC *)
		count: SHORTINT;	(* -1 => exclusive lock, 0 => unlocked, (later: > 0 => number of shared locks) *)
		locked: BOOLEAN;
		filler: INTEGER;	(* set to -1 for AosInfo.Objects *)
		awaitingLock: ProcessQueue;	(* processes blocked awaiting lock *)
		awaitingCond: ProcessQueue;	(* processes blocked awaiting condition *)
		lockedBy: Process;	(* object is (exclusive) locked by this process *)
		decInvCnt: BOOLEAN;			(* >0: the priInvCnt of the process holding the lock has been *)
		checkP: Process; (*debug*)	(* incremented by a process in a waiting queue of this object *)
	END;							
	
	SSEState = ARRAY (512+16) OF CHAR;

	ProcessQueue = RECORD
		head, tail: Process
	END;
	
	Body = PROCEDURE (typetag: LONGINT; self: ProtectedObject);
	Condition = PROCEDURE (slink: LONGINT): BOOLEAN;

	EventHandler* = PROCEDURE {DELEGATE};
	
	Timer* = OBJECT
		VAR 
			tnext, tprev, inext: Timer;
			trigger: LONGINT;
			handler: EventHandler;
	END Timer;
	
	TimerList = POINTER TO RECORD
		tnext, tprev: TimerList;
		trigger: LONGINT;
		handler: EventHandler
	END;
	
	InterruptList = POINTER TO RECORD
		inext: InterruptList;
		handler: EventHandler
	END;
	
	
TYPE
(** All exported fields and variables should be considered read-only. *)

TYPE
	Process* = OBJECT (AosHeap.RootObject)
		VAR
			next: Process;	(* in some ProcessQueue *)
			prev: Process;
			link*: Process;	(** for snapshot list *)
			obj*: ProtectedObject;	(** associated active object *)
			state*: AosInterrupts.State;	(** processor state of suspended process *)
			sse: SSEState;	(* fpu and sse state of preempted process (only valid if Preempted IN flag) *)
			sseAdr: LONGINT;
			condition*: Condition;	(** awaited process' condition *)
			condFP*: LONGINT;	(** awaited process' condition's context *)
			mode*: LONGINT;	(** process state *)	(* only changed inside AosActive lock ??? *)
			procID*: LONGINT;	(** processor ID where running *)
			waitingOn*: ProtectedObject;	(** obj this process is waiting on (for lock or condition) *)
			id*: LONGINT;	(** unique process ID for tracing *)
			flags*: SET;	(** process flags *)
			priority*: LONGINT;	(** process priority *)	(* exported for AosExceptions *)
			currPri: LONGINT;
			stack*: AosMemory.Stack;	(** user-level stack of process *)
			handler-: ExceptionHandler;	(** user-level exception handler (e.g. for Jaos) *)
			restartPC-: LONGINT;	(** entry point of body, for SAFE exception recovery *)
			restartSP-: LONGINT;	(** stack level at start of body, for SAFE exception recovery *)
			perfCyc*: ARRAY AosBoot.MaxCPU OF HUGEINT;
			priInvCnt: LONGINT; (* counts the nummber of object locks hold that increased currPri of the process *)
	
		PROCEDURE FindRoots;	(* override *)
		VAR esp: LONGINT; id, mode: LONGINT;
		BEGIN
			id := SELF.id; mode := SELF.mode;	(* debugging *)
				(* process snapshot *)
			IF traceProcess # NIL THEN traceProcess(SELF) END;
			IF snapshotEnabled THEN link := snapshot; snapshot := SELF END;
				(* stack garbage collection *)
			IF VeryConservative THEN
				(*AosOut.String("[ST"); AosOut.Hex(stack.adr, 9); AosOut.Hex(stack.high, 9); AosOut.Char("]");*)
				AosHeap.RegisterCandidates(stack.adr, stack.high-stack.adr)
			ELSE
				esp := state.ESP;	(* cf. Enter *)
				IF esp # 0 THEN
					IF AosMemory.ValidStack(stack, esp) THEN
						AosHeap.RegisterCandidates(esp, stack.high - esp)
					ELSE
						(* no need for AosOut.Enter, because this is only called from garbage collector *)
(*
						AosOut.String(" Invalid stack:");
						AosOut.Int(mode, 2); AosOut.Int(id, 4);
						AosOut.Hex(esp, 9); AosOut.Hex(stack.high, 9); 
						AosOut.Char(" "); AosOut.Int(stack.high-esp, 1); AosOut.Ln
*)
					END
				ELSE
					AosOut.String("[AosActive.FindRoots esp=0]")
				END
			END
		END FindRoots;
		
	END Process;

	TraceProcess* = PROCEDURE(p: Process);

	ExceptionHandler* = PROCEDURE(p: Process; VAR int: AosInterrupts.State; VAR exc: AosInterrupts.ExceptionState; VAR return: BOOLEAN);

TYPE
	Idle = OBJECT
	BEGIN {ACTIVE, SAFE, PRIORITY(-1)}	(* negative priority equivalent to MinPriority *)
		LOOP
			REPEAT
				IF ProcessorHLT # NIL THEN ProcessorHLT	(* UP *)
				ELSE AosBoot.SpinHint	(* MP *)
				END
			UNTIL maxReady > MinPriority;
			Yield
		END
	END Idle;

TYPE
	Clock = OBJECT
		VAR h: Timer;
	BEGIN {ACTIVE, SAFE, PRIORITY(High)}
		SetPriority(Realtime);
		LOOP
			AosLocks.Acquire(AosLocks.AosActive);
			LOOP
				h := event.tnext;
				IF (h = event) OR (h.trigger - ticks > 0) THEN EXIT END;
				event.tnext := h.tnext; event.tnext.tprev := event;	(* unlink *)
				h.tnext := NIL; h.tprev := NIL;
				AosLocks.Release(AosLocks.AosActive);
				h.handler();	(* assume handler will return promptly *)
				AosLocks.Acquire(AosLocks.AosActive)
			END;
			ASSERT(timer = NIL);	(* temp strong check *)
			timer := running[AosBoot.ID()];
			timer.mode := AwaitingEvent;
			SwitchToNew
		END
	END Clock;
	
TYPE
	Interrupter = OBJECT (ProtectedObject)	(* to do: like Timer *)
	END Interrupter;
	
VAR
	ready: ARRAY NumPriorities OF ProcessQueue;
	maxReady: LONGINT;	(* for all i : MinPriority <= maxReady < i < NumPriorities : Empty(ready[i]) *)
		(* exported for AosExceptions. *)
	running-: ARRAY AosBoot.MaxCPU OF Process;	(** processes currently running. *)
	nextProcessID: LONGINT;
	interrupt: ARRAY NumIRQ OF RECORD
		root: InterruptList;
		process: Process
	END;
	event: Timer;	(* list of events *)
	timer: Process;	(* suspended timer process *)
	ticks*: LONGINT;	(** timer ticks *)	(* temporarily defined here until timing moved up to AosKernel *)
	terminate, trap: PROCEDURE;
	snapshotEnabled*: BOOLEAN;	(** for System.ShowTasks *)
	snapshot*: Process;	(** for System.ShowTasks *)
	stats: BOOLEAN;	(* enable statistical counters *)
	Nlock, Nunlock, Nawait, NawaitNoIF, NawaitTrue, Ncreate, Nterminate, 
		Ncondition, Ncondition1True, Ncondition2, Ncondition2True, 
		Ntimeslice, NtimesliceTaken, NtimesliceNothing, NtimesliceIdle, 
		NtimesliceKernel, NtimesliceV86, NtimesliceCritical, 
		Npreempt, NpreemptTaken, NpreemptNothing, 
		NpreemptKernel, NpreemptV86, NpreemptCritical, 
		Nenter, NenterHigherRunningPriority, NenterHigherCurrentPriority, 
		NenterHigherIdlePriority: LONGINT;
	ProcessorHLT*: PROCEDURE;	(** installable procedure to halt the current processor while idle *)
	entry: LONGINT;
	init: Process;
	traceProcess*: TraceProcess;	(** for debugging purposes (see AosInfo.Active) *)
	idlecount*: ARRAY AosBoot.MaxCPU OF LONGINT;	(** count of idle process timeslice interrupts *)
	perfTsc: ARRAY AosBoot.MaxCPU OF HUGEINT;

(* Get a process from a queue (NIL if none).  Caller must hold lock for specific queue. *)

PROCEDURE Get(VAR queue: ProcessQueue; VAR new: Process);
VAR t: Process;
BEGIN
	t := queue.head;
	IF t = NIL THEN	(* zero elements in queue *)
		(* skip *)
	ELSIF t = queue.tail THEN	(* one element in queue *)
		queue.head := NIL; queue.tail := NIL	(* {(t.next = NIL) & (t.prev = NIL)} *)
	ELSE	(* more than one element in queue *)
		queue.head := t.next; t.next := NIL; queue.head.prev := NIL
	END;
	ASSERT((t = NIL) OR (t.next = NIL) & (t.prev = NIL));	(* temp strong check *)
	new := t
END Get;

(* Put a process in a queue.  Caller must hold lock for specific queue. *)
(* If t was running, be careful to protect Put and the subsequent SwitchTo with the ready lock. *)

PROCEDURE Put(VAR queue: ProcessQueue; t: Process);
BEGIN	(* {t # NIL & t.next = NIL} *)
	ASSERT((t.next = NIL) & (t.prev = NIL));
	IF queue.head = NIL THEN	(* queue empty *)
		queue.head := t
	ELSE	(* queue not empty *)
		queue.tail.next := t; t.prev := queue.tail
	END;
	queue.tail := t
END Put;

PROCEDURE PutSorted(VAR queue: ProcessQueue; t: Process);
VAR i, p: Process;
BEGIN	(* {t # NIL & t.next = NIL} *)
	ASSERT((t.next = NIL) & (t.prev = NIL));
	IF queue.head = NIL THEN	(* queue empty *)
		queue.head := t;
		queue.tail := t
	ELSIF queue.head.currPri < t.currPri THEN (* insert as first element *)
		t.next := queue.head;
		queue.head.prev := t;
		queue.head := t
	ELSE
		i := queue.head;
		WHILE (i # NIL) & (i.currPri >= t.currPri) DO p := i; i := i.next END; (* {p # NIL} *)
		p.next := t;
		t.next := i;
		IF i = NIL THEN queue.tail := t ELSE i.prev := t END;
		t.prev := p
	END
END PutSorted;

(* Select a process of at least the specified priority to run next on current processor (returns NIL if none).  Caller must hold ready lock. *)

PROCEDURE Select(VAR new: Process; priority: LONGINT);
BEGIN
	LOOP
		IF maxReady < priority THEN new := NIL; EXIT END;
		Get(ready[maxReady], new);
		IF (new # NIL) OR (maxReady = MinPriority) THEN EXIT END;
		DEC(maxReady)
	END
END Select;

(* Enter a process in the ready queue.  Caller must hold ready lock. *)
(* If t was running, be careful to make Enter and the subsequent SwitchTo atomic, as the process could be grabbed by another process while it is still running. *)

PROCEDURE Enter(t: Process);
VAR i: LONGINT;
BEGIN
	IF Stats & stats THEN AosBoot.Inc(Nenter) END;
	t.mode := Ready;
	Put(ready[t.currPri], t);
	IF t.currPri > maxReady THEN
		IF Stats & stats THEN	(* possibly low-performance stats code *)
			IF maxReady = MinPriority THEN
				AosBoot.Inc(NenterHigherIdlePriority)
			ELSE
				i := AosBoot.ID();	(* current processor's running entry can never be NIL *)
				IF t.currPri > running[i].currPri THEN
					AosBoot.Inc(NenterHigherCurrentPriority)
				ELSE
						(* running process can not change, as we are holding lock *)
					i := 0;
					LOOP
						IF t.currPri > running[i].currPri THEN
							AosBoot.Inc(NenterHigherRunningPriority);
							EXIT
						END;
						INC(i);
						IF (i = LEN(running)) OR (running[i] = NIL) THEN EXIT END
					END
				END
			END
		END;
		maxReady := t.currPri	(* to do: re-establish global priority invariant *)
	END
END Enter;

(* Remove a process from a queue that contains it.  Caller must hold lock for specific queue. *)
(* Not intended for frequent use. *)

PROCEDURE Remove(VAR queue: ProcessQueue; t: Process);
VAR p, c: Process;
BEGIN
	IF t.prev # NIL THEN t.prev.next := t.next END;
	IF t.next # NIL THEN t.next.prev := t.prev END;
	IF t = queue.head THEN queue.head := t.next END;
	IF t = queue.tail THEN queue.tail := t.prev END;
	ASSERT((queue.head = NIL) OR (queue.head.prev = NIL) & (queue.tail.next = NIL));
	t.prev := NIL;
	t.next := NIL
END Remove;

(* Return return address of current procedure. *)

PROCEDURE -CallerEIP(): LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 4[EBP]
END CallerEIP;

(* Return CS. *)

PROCEDURE -CS(): LONGINT;
CODE {SYSTEM.i386}
	XOR EAX, EAX
	MOV AX, CS
END CS;

(* Save minimal FPU state (for synchronous process switches). *)
(* saving FPU state takes 108 bytes memory space, no alignment required *)

PROCEDURE -FPUSaveMin(VAR state: SSEState);
CODE {SYSTEM.i386, SYSTEM.FPU}
	POP EAX
	FNSTCW [EAX]	; control word is at state[0]
	FWAIT
END FPUSaveMin;

(* Restore minimal FPU state. *)

PROCEDURE -FPURestoreMin(VAR state: SSEState);
CODE {SYSTEM.i386, SYSTEM.FPU}
	POP EAX
	FLDCW [EAX]	; control word is at state[0]
END FPURestoreMin;

(* Save full FPU state (for asynchronous process switches). *)

PROCEDURE -FPUSaveFull(VAR state: SSEState);
CODE {SYSTEM.i386, SYSTEM.FPU}
	POP EAX
	FSAVE [EAX]
END FPUSaveFull;

(* Restore full FPU state. *)

PROCEDURE -FPURestoreFull(VAR state: SSEState);
CODE {SYSTEM.i386, SYSTEM.FPU}
	POP EAX
	FRSTOR [EAX]
END FPURestoreFull;

(* stateAdr must be the address of a 16-byte aligned memory area of at least 512 bytes *)
PROCEDURE -SSESaveFull(stateAdr: LONGINT);
CODE {SYSTEM.i386, SYSTEM.FPU, SYSTEM.SSE2}
	POP EAX
	FXSAVE [EAX]
	FWAIT
	FNINIT
END SSESaveFull;

PROCEDURE -SSERestoreFull(stateAdr: LONGINT);
CODE {SYSTEM.i386, SYSTEM.FPU, SYSTEM.SSE2}
	POP EAX
	FXRSTOR [EAX] 
END SSERestoreFull;

PROCEDURE -SSESaveMin(stateAdr: LONGINT);
CODE {SYSTEM.i386, SYSTEM.FPU, SYSTEM.SSE2}
	POP EAX
	FNSTCW [EAX]
	FWAIT
	STMXCSR 24[EAX]
END SSESaveMin;

PROCEDURE -SSERestoreMin(stateAdr: LONGINT);
CODE {SYSTEM.i386, SYSTEM.FPU, SYSTEM.SSE2}
	POP EAX
	FLDCW [EAX]
	LDMXCSR 24[EAX]
END SSERestoreMin;

(* Helper functions for SwitchTo. *)

PROCEDURE -PushState(EFLAGS: SET; CS, EIP, EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI: LONGINT);
CODE {SYSTEM.i386}
END PushState;

PROCEDURE -JumpState;
CODE {SYSTEM.i386}
	POPAD
	IRETD
END JumpState;

(* this does not withstand bones testing (spot the deliberate mistake)
PROCEDURE -PushState(EFLAGS: SET; CS, EIP: LONGINT; AdrEDI: LONGINT; VAR FPU: FPUState);
CODE {SYSTEM.i386}
END PushState;

PROCEDURE -PopState;
CODE {SYSTEM.i386, SYSTEM.FPU}
	POP EAX	; ADR(FPU)
	FRSTOR [EAX]
	POP EAX	; AdrEDI
	MOV EBP, 36[EAX]	; offsets from AosInterrupts.State
	MOV EDI, [EAX]
	MOV ESI, 4[EAX]
	MOV EBX, 16[EAX]
	MOV EDX, 20[EAX]
	MOV ECX, 24[EAX]
	MOV EAX, 28[EAX]
	IRETD
END PopState;
*)

PROCEDURE -AssignSPtoFP;
CODE {SYSTEM.i386}
	MOV EBP, ESP
END AssignSPtoFP;

(* Switch to the specified process.  Caller must hold ready lock.  Return may be on different processor! *)

PROCEDURE SwitchTo(VAR running: Process; new: Process);	(* parameters used in SwitchToState, TerminateThis, New *)
VAR id: LONGINT;
BEGIN
		(* save current state *)
	ASSERT(CS() MOD 4 = AosInterrupts.UserLevel);	(* registers hold user state *)
	id := AosBoot.ID();
	running.perfCyc[id] := AosBoot.AddH(AosBoot.SubH(AosBoot.GetTimer(), perfTsc[id]), running.perfCyc[id]);
	SYSTEM.GETREG(SYSTEM.ESP, running.state.ESP);	(* for GC *)
	SYSTEM.GETREG(SYSTEM.EBP, running.state.EBP);	(* save state *)
	IF AosBoot.SSESupport THEN SSESaveMin(running.sseAdr) 
	ELSE FPUSaveMin(running.sse)
	END;
	running := new; new.mode := Running;
	IF Preempted IN new.flags THEN
		ASSERT(new.state.CS MOD 4 = AosInterrupts.UserLevel);	(* switching to user mode *)
		EXCL(new.flags, Preempted);
		SYSTEM.PUTREG(SYSTEM.ESP, new.state.ESP);	(* for UpdateState - run on new stack (EBP on old) *)
			(* to do: is this really the new stack? *)
(*
		PushState(new.state.EFLAGS, new.state.CS, new.state.EIP, SYSTEM.ADR(new.state.EDI), new.fpu);
*)
		PushState(new.state.EFLAGS, new.state.CS, new.state.EIP, 
			new.state.EAX, new.state.ECX, new.state.EDX, new.state.EBX, 
			0, new.state.EBP, new.state.ESI, new.state.EDI);
		IF AosBoot.SSESupport THEN SSERestoreFull(new.sseAdr)
		ELSE FPURestoreFull(new.sse)
		END;
		perfTsc[id] := AosBoot.GetTimer();
		AosLocks.Release(AosLocks.AosActive);	(* UpdateState race! - probably no race, as we are on new stack. it is ok for another processor to use our old stack. *)
(*
		PopState
*)
		JumpState
	ELSE
		IF AosBoot.SSESupport THEN SSERestoreMin(new.sseAdr)
		ELSE FPURestoreMin(new.sse)
		END;
			(* UpdateState can not be called, because we hold the lock, and GC acquires all locks. *)
		SYSTEM.PUTREG(SYSTEM.ESP, new.state.EBP);	(* run on new stack *)
			(* to do: is this really the new stack? *)
		perfTsc[id] := AosBoot.GetTimer();
		AosLocks.Release(AosLocks.AosActive);
		(* what if interrupt happens here? should be ok, as we are on new stack *)
		(* to do: what if preemption happens here?  EBP still points to old stack! *)
			(* now old stack can be rescheduled on another processor => local variables and parameters no longer available *)
		AssignSPtoFP	(* MOV EBP, ESP *)
	END
(*
	MOV ESP, EBP	; exit code generated by compiler
	POP EBP
	RET 8
*)
END SwitchTo;

(* Select a new process to run and switch to it.  Caller must hold ready lock. *)

PROCEDURE SwitchToNew;
VAR new: Process;
BEGIN
	Select(new, MinPriority);	(* will return at least an Idle process *)
	new.procID := AosBoot.ID();
	SwitchTo(running[new.procID], new)
END SwitchToNew;

(** Relinquish control. *)

PROCEDURE Yield*;
VAR r, new: Process;
BEGIN
	IF ~YieldTrick OR (maxReady > MinPriority) THEN
		r := SYSTEM.VAL(Process, AosMemory.GetProcessPtr());
		AosLocks.Acquire(AosLocks.AosActive);
		Select(new, r.currPri);
		IF new # NIL THEN	(* found another process *)
			r.state.EIP := CallerEIP();	(* for tracing *)
			Enter(r);
			new.procID := AosBoot.ID();
			SwitchTo(running[new.procID], new)
		ELSE	(* stay with same process *)
			AosLocks.Release(AosLocks.AosActive)
		END
	END
END Yield;

(*
PROCEDURE Yield*;
VAR id: LONGINT; new: Process;
BEGIN
	AosLocks.Acquire(AosLocks.AosActive);
	id := AosBoot.ID();
	Select(new, running[id].currPri);
	IF new # NIL THEN	(* found another process *)
		running[id].state.EIP := CallerEIP();	(* for tracing *)
		Enter(running[id]);
		new.procID := id;
		SwitchTo(running[id], new)
	ELSE	(* stay with same process *)
		AosLocks.Release(AosLocks.AosActive)
	END
END Yield;
*)

PROCEDURE CopyState(VAR from, to: AosInterrupts.State);
BEGIN
	to.EDI := from.EDI; to.ESI := from.ESI;
	to.EBX := from.EBX; to.EDX := from.EDX;
	to.ECX := from.ECX; to.EAX := from.EAX;
	to.EBP := from.EBP; to.EIP := from.EIP;
	to.CS := from.CS; to.EFLAGS := from.EFLAGS;
	to.ESP := from.ESP
END CopyState;

PROCEDURE SwitchToState(new: Process; VAR state: AosInterrupts.State);
BEGIN
		(* simulate return from SwitchTo - MOV ESP, EBP; POP EBP; RET 8 *)
	state.ESP := new.state.EBP+16;	(* +16 is effect of POP, RET *)
	state.EBP := SYSTEM.GET32(new.state.EBP);	(* effect of POP *)
	state.EIP := SYSTEM.GET32(new.state.EBP+4);	(* effect of RET *)
(*
	EXCL(state.EFLAGS, AosInterrupts.IFBit)	(* disable interrupts, as it was before call to SwitchTo *)
*)
END SwitchToState;

(*
PROCEDURE TraceInterrupt(n, eip, id: LONGINT);
VAR m: AosModules.Module;
BEGIN
	AosOut.String("Timeslice "); AosOut.Int(n, 1);
	AosOut.Char(" "); AosOut.Int(AosLocks.proc[id].preemptCount, 1);
	AosOut.Hex(SYSTEM.VAL(LONGINT, AosLocks.proc[id].locksHeld), 9);
	AosOut.Char(" ");
	m := AosModules.ThisModuleByAdr(eip);
	IF m # NIL THEN
		AosOut.String(m.name); AosOut.String(" PC = ");
		AosOut.Int(eip - SYSTEM.ADR(m.code[0]), 1)
	ELSE
		AosOut.Hex(eip, 8)
	END;
	AosOut.Ln
END TraceInterrupt;
*)

(** Preempt the current process. *)

PROCEDURE Timeslice*(VAR state: AosInterrupts.State);
VAR id: LONGINT; new: Process;
BEGIN (* {interrupts on & interrupts were on in "user" mode, because timeslice interrupt happened} *)
		(* handle a timer tick *)
	AosLocks.Acquire(AosLocks.AosActive);
	IF Stats & stats THEN AosBoot.Inc(Ntimeslice) END;
	id := AosBoot.ID();
	IF (id = 0) & (event.tnext.trigger - ticks <= 0) THEN	(* next event due *)
		IF event.tnext # event THEN	(* not dummy event *)
			IF timer # NIL THEN
				ASSERT(timer.mode = AwaitingEvent);	(* temp strong check *)
				Enter(timer); timer := NIL
			END
		ELSE	(* reset dummy event *)
			event.trigger := ticks + MAX(LONGINT) DIV 2	(* ignore overflow *)
		END
	END;
		(* pre-empt the current process *)
	IF AosLocks.PreemptCount(id) = 1 THEN	(* check against 1, because we are holding one lock *)
		IF ~(AosInterrupts.VMBit IN state.EFLAGS) THEN	(* not V86 mode *)
			IF state.CS MOD 4 = AosInterrupts.UserLevel THEN	(* not kernel mode (used during initialization or interrupts) *)
				IF running[id].priority # MinPriority THEN	(* idle processes are not timesliced *)
					Select(new, running[id].currPri);
					IF new # NIL THEN
						ASSERT(CS() MOD 4 = AosInterrupts.KernelLevel);	(* otherwise we can not change state.ESP *)
						running[id].perfCyc[id]:= AosBoot.AddH(AosBoot.SubH(AosBoot.GetTimer(), perfTsc[id]), running[id].perfCyc[id]);
						IF Stats & stats THEN AosBoot.Inc(NtimesliceTaken) END;	(* timeslices taken *)
						INCL(running[id].flags, Preempted);
						CopyState(state, running[id].state);
						IF AosBoot.SSESupport THEN SSESaveFull(running[id].sseAdr)
						ELSE FPUSaveFull(running[id].sse)	(* to do: floating-point exception possible / AosBoot.SetupFPU *)
						END;
						Enter(running[id]);
						running[id] := new;
						new.mode := Running; new.procID := id;
						IF Preempted IN new.flags THEN
							EXCL(new.flags, Preempted);
							CopyState(new.state, state);
							IF AosBoot.SSESupport THEN SSERestoreFull(new.sseAdr)
							ELSE FPURestoreFull(new.sse)
							END
						ELSE
							SwitchToState(new, state);
							IF AosBoot.SSESupport THEN SSERestoreMin(new.sseAdr) 
							ELSE FPURestoreMin(new.sse)
							END
						END;
						perfTsc[id] := AosBoot.GetTimer()
					ELSE
						IF Stats & stats THEN AosBoot.Inc(NtimesliceNothing) END	(* nothing available *)
					END
				ELSE
					INC(idlecount[id]);
					IF Stats & stats THEN AosBoot.Inc(NtimesliceIdle) END	(* idle process *)
				END
			ELSE
				(*TraceInterrupt(3, state.EIP, id);*)
				(* can not interrupt kernel mode, because SwitchTo would not switch back to it *)
				IF Stats & stats THEN AosBoot.Inc(NtimesliceKernel) END	(* kernel mode, e.g. during page fault or FieldIRQ *)
			END
		ELSE
			IF Stats & stats THEN AosBoot.Inc(NtimesliceV86) END	(* V86 mode *)
		END
	ELSE
		(*IF NtimesliceCritical MOD 200 = 0 THEN TraceInterrupt(5, state.EIP, id) END;*)
		IF Stats & stats THEN AosBoot.Inc(NtimesliceCritical) END	(* not preemptable *)
	END;
	AosLocks.Release(AosLocks.AosActive)
END Timeslice;

(*
(** Return current process. (DEPRECATED, use ActiveObject) *)

PROCEDURE CurrentProcess*(): Process;
VAR pid: LONGINT; t: Process;
BEGIN
	pid := AosLocks.AcquirePreemption();
	t := running[pid];
	AosLocks.ReleasePreemption;
	RETURN t
END CurrentProcess;
*)

PROCEDURE -PUSHFD;
CODE {SYSTEM.i386}
	PUSHFD
END PUSHFD;

PROCEDURE -POPFD;
CODE {SYSTEM.i386}
	POPFD
END POPFD;

(** Return the active object currently executing. *)

PROCEDURE ActiveObject*(): PTR;
VAR r: Process;
BEGIN
	r := SYSTEM.VAL(Process, AosMemory.GetProcessPtr());
	RETURN r.obj
END ActiveObject;

(*
PROCEDURE ActiveObject*(): PTR;
VAR pid: LONGINT; t: PTR;
BEGIN
	(*pid := AosLocks.AcquirePreemption();*)
	PUSHFD; SYSTEM.CLI();	(* hack to check performance improvement of WM recursive locks *)
	pid := AosBoot.ID();
	t := running[pid].obj;
	POPFD;
	(*AosLocks.ReleasePreemption;*)
	RETURN t
END ActiveObject;
*)

(** Set the current process' priority. *)

PROCEDURE SetPriority*(priority: LONGINT);
VAR id: LONGINT;
BEGIN
	ASSERT((priority >= Low) & (priority <= Realtime));	(* priority in bounds *)
	id := AosLocks.AcquirePreemption();
	running[id].priority := priority;
	running[id].currPri := priority;
	AosLocks.ReleasePreemption
	(* to do: re-establish global priority invariant *)
END SetPriority;

(** Set the current process' exception handler (NIL to disable).  The exception handler gets called in kernel mode when an exception occurs, in the context of the faulting process.  It may modify the PC, FP and SP values in the passed interrupt state and set return = TRUE to restart the process causing the exception.  If it sets return = FALSE, the default handler is invoked (restart the object body or terminate the process). *)

PROCEDURE SetExceptionHandler*(h: ExceptionHandler);
VAR id: LONGINT;
BEGIN
	id := AosLocks.AcquirePreemption();
	running[id].handler := h;
	AosLocks.ReleasePreemption
END SetExceptionHandler;

(** Return TRUE iff the specified protected object is locked exclusive to the current process. *)

PROCEDURE LockedByCurrent*(obj: PTR): BOOLEAN;
VAR hdr: ObjectHeader; id: LONGINT; res: BOOLEAN;
BEGIN
	ASSERT(SYSTEM.VAL(SET, obj) * AosHeap.FlagBits = {AosHeap.ProtObjBit});	(* protected object *)
	hdr := SYSTEM.VAL(ObjectHeader, SYSTEM.VAL(LONGINT, obj)-AosHeap.ProtOfs);
	IF ObjectLock THEN
		id := AosLocks.AcquirePreemption();
		AosLocks.AcquireObject(hdr.locked)
	ELSE
		AosLocks.Acquire(AosLocks.AosActive);
		id := AosBoot.ID()
	END;
	res := (hdr.lockedBy = running[id]);
	IF ObjectLock THEN
		AosLocks.ReleaseObject(hdr.locked);
		AosLocks.ReleasePreemption
	ELSE
		AosLocks.Release(AosLocks.AosActive)
	END;
	RETURN res
END LockedByCurrent;

(** Return number of ready and running processes, excluding idle processes. *)

PROCEDURE NumReady*(): LONGINT;
VAR i, n: LONGINT; p: Process;
BEGIN
	n := 0;
	AosLocks.Acquire(AosLocks.AosActive);
	FOR i := MinPriority+1 TO NumPriorities-1 DO
		p := ready[i].head; WHILE p # NIL DO INC(n); p := p.next END
	END;
	FOR i := 0 TO AosBoot.MaxCPU-1 DO
		IF (running[i] # NIL) & (running[i].priority > MinPriority) THEN INC(n) END
	END;
	AosLocks.Release(AosLocks.AosActive);
	RETURN n
END NumReady;

(* Handle hardware interrupt and route it to an interrupt handler process. *)

PROCEDURE FieldIRQ(VAR state: AosInterrupts.State);
VAR t: Process; id: LONGINT; new: Process; preempt: BOOLEAN;
BEGIN
	SYSTEM.STI();	(* avoid AosProcessors.StopAll deadlock when waiting for locks below (remove this) *)
	AosInterrupts.DisableIRQ(state.INT);	(* do this before acknowledging irq *)
	AosLocks.Acquire(AosLocks.AosActive);
	t := interrupt[state.INT-MinIRQ].process;
	IF StrongChecks THEN ASSERT(t.mode = AwaitingEvent) END;
	id := AosBoot.ID();
	preempt := (t.currPri > maxReady) & (maxReady # MinPriority) & (t.currPri > running[id].currPri);	(* experiment *)
	Enter(t);
	IF preempt THEN	(* set to FALSE to disable experiment *)
		IF Stats & stats THEN AosBoot.Inc(Npreempt) END;
			(* pre-empt the current process *)
		IF AosLocks.PreemptCount(id) = 1 THEN	(* check against 1, because we are holding one lock *)
			IF ~(AosInterrupts.VMBit IN state.EFLAGS) THEN	(* not V86 mode *)
				IF state.CS MOD 4 = AosInterrupts.UserLevel THEN	(* not kernel mode (used during initialization or interrupts) *)
					Select(new, running[id].currPri+1);
					IF new # NIL THEN
						ASSERT(CS() MOD 4 = AosInterrupts.KernelLevel);	(* otherwise we can not change state.ESP *)
						running[id].perfCyc[id] :=
							AosBoot.AddH(AosBoot.SubH(AosBoot.GetTimer(), perfTsc[id]), running[id].perfCyc[id]);
						IF Stats & stats THEN AosBoot.Inc(NpreemptTaken) END;	(* preempts taken *)
						INCL(running[id].flags, Preempted);
						CopyState(state, running[id].state);
						IF AosBoot.SSESupport THEN SSESaveFull(running[id].sseAdr)
						ELSE FPUSaveFull(running[id].sse)	(* to do: floating-point exception possible / AosBoot.SetupFPU *)
						END;
						Enter(running[id]);
						running[id] := new;
						new.mode := Running; new.procID := id;
						IF Preempted IN new.flags THEN
							EXCL(new.flags, Preempted);
							CopyState(new.state, state);
							IF AosBoot.SSESupport THEN SSERestoreFull(new.sseAdr)
							ELSE FPURestoreFull(new.sse)
							END
						ELSE
							SwitchToState(new, state);
							IF AosBoot.SSESupport THEN SSERestoreMin(new.sseAdr) 
							ELSE FPURestoreMin(new.sse)
							END
						END;
						perfTsc[id] := AosBoot.GetTimer()
					ELSE
						IF Stats & stats THEN AosBoot.Inc(NpreemptNothing) END	(* nothing available *)
					END
				ELSE
					(* can not interrupt kernel mode, because SwitchTo would not switch back to it *)
					IF Stats & stats THEN AosBoot.Inc(NpreemptKernel) END	(* kernel mode, e.g. during page fault or FieldIRQ *)
				END
			ELSE
				IF Stats & stats THEN AosBoot.Inc(NpreemptV86) END	(* V86 mode *)
			END
		ELSE
			IF Stats & stats THEN AosBoot.Inc(NpreemptCritical) END	(* not preemptable *)
		END
	END;
	AosLocks.Release(AosLocks.AosActive)
END FieldIRQ;

(* Process scheduled to handle an interrupt.  First parameter is usually the type, but is used as int index here. *)

PROCEDURE InterruptProcess(int: LONGINT; self: ProtectedObject);
VAR h: InterruptList; t: Process;
BEGIN
	t := interrupt[int-MinIRQ].process;
	LOOP
		h := interrupt[int-MinIRQ].root;	(* concurrent updates allowed in InstallHandler and RemoveHandler *)
		WHILE h # NIL DO h.handler(); h := h.inext END;
		AosLocks.Acquire(AosLocks.AosActive);
		ASSERT(running[AosBoot.ID()] = t);	(* strong check *)
		t.mode := AwaitingEvent;
		AosInterrupts.EnableIRQ(int);
		SwitchToNew
	END
END InterruptProcess;

(** Install interrupt handler. *)

PROCEDURE InstallHandler*(h: EventHandler; int: LONGINT);
VAR t: Process; new: BOOLEAN; ih: Interrupter; n: InterruptList;
BEGIN
	ASSERT((int >= MinIRQ) & (int-MinIRQ < NumIRQ));	(* range check *)
	IF interrupt[int-MinIRQ].process = NIL THEN	(* first handler for this irq *)
			(* allocate process outside lock region, to avoid GC lock problems. *)
			(* hack: use type parameter to pass int index & set obj to h, for System.ShowProcesses *)
		NEW(ih);	(* temp *)
		NewProcess(InterruptProcess, int, {Resistant}, ih, t);
		t.priority := Realtime;
		t.currPri := Realtime
	END;
	NEW(n); n.handler := h;
	AosLocks.Acquire(AosLocks.AosActive);
	(* comment out for AosTestInt2 test *)
	(*ASSERT(h.int = 0);*)	(* interrupt handler may only be installed once (maybe too strict, but otherwise a race is possible with RemoveHandler and InterruptProcess) *)
	IF interrupt[int-MinIRQ].process = NIL THEN	(* still first handler for this irq *)
		t.id := nextProcessID; INC(nextProcessID);
		t.mode := AwaitingEvent;
		interrupt[int-MinIRQ].process := t;
		new := TRUE
	ELSE
		new := FALSE
	END;
	(*h.int := int;*)
(*
	h.inext := interrupt[int-MinIRQ].root;	(* can be concurrent with loop in InterruptProcess *)
	interrupt[int-MinIRQ].root := h;
*)
	n.inext := interrupt[int-MinIRQ].root;	(* can be concurrent with loop in InterruptProcess *)
	interrupt[int-MinIRQ].root := n;
	AosLocks.Release(AosLocks.AosActive);
	IF new THEN AosInterrupts.InstallHandler(FieldIRQ, int) END	(* do outside lock region to avoid NEW/GC deadlock *)
END InstallHandler;

(** Remove interrupt handler. *)

PROCEDURE RemoveHandler*(h: EventHandler; int: LONGINT);
VAR p, c: InterruptList;
BEGIN
	ASSERT((int >= MinIRQ) & (int-MinIRQ < NumIRQ));	(* range check *)
	AosLocks.Acquire(AosLocks.AosActive);
	p := NIL; c := interrupt[int-MinIRQ].root;
	WHILE (c.handler # h) & (c # NIL) DO p := c; c := c.inext END;
	IF c.handler = h THEN	(* handler found *)
		IF p = NIL THEN
			interrupt[int-MinIRQ].root := c.inext;
	(*
			IF c.inext = NIL THEN	(* this was the last handler *)
				AosInterrupts.RemoveHandler(FieldIRQ, int)
				(* to do: synchronize with FieldIRQ and InterruptProcess *)
			END
	*)
		ELSE
			p.inext := c.inext
		END
	ELSE
		HALT(99)	(* handler not found *)
	END;
		(* can not clear c.next field, because InterruptProcess may be traversing it. *)
	AosLocks.Release(AosLocks.AosActive)
END RemoveHandler;

(** Set (or reset) an event handler object's timeout value. *)

PROCEDURE SetTimeout*(t: Timer; h: EventHandler; ms: LONGINT);
VAR e: Timer; trigger: LONGINT;
BEGIN
	ASSERT(Second= 1000);	(* assume milliseconds for now *)
	IF ms < 1 THEN ms := 1 END;
	AosLocks.Acquire(AosLocks.AosActive);
	trigger := ticks + ms;	(* ignore overflow *)
	IF t.tnext # NIL THEN	(* cancel previous timeout *)
		t.tnext.tprev := t.tprev; t.tprev.tnext := t.tnext
	END;
	t.trigger := trigger; t.handler := h;
	e := event.tnext;	(* performance: linear search! *)
	WHILE (e # event) & (e.trigger - trigger <= 0) DO e := e.tnext END;
	t.tprev := e.tprev; e.tprev := t; t.tnext := e; t.tprev.tnext := t;
	(*AosOut.String("SetTimeout"); AosOut.Hex(SYSTEM.VAL(LONGINT, t), 9);
	AosOut.Char(" "); AosOut.Int(trigger, 1); AosOut.Ln;*)
	AosLocks.Release(AosLocks.AosActive)
END SetTimeout;

(** Cancel an event handler object's timeout, if any.  It is possible that the timer has expired, but not yet been scheduled to run. *)

PROCEDURE CancelTimeout*(t: Timer);
BEGIN
	AosLocks.Acquire(AosLocks.AosActive);
	ASSERT(t # event);
	IF t.tnext # NIL THEN
		t.tnext.tprev := t.tprev; t.tprev.tnext := t.tnext;
		t.tnext := NIL; t.tprev := NIL
	END;
	AosLocks.Release(AosLocks.AosActive)
END CancelTimeout;

(** Terminate the current process and switch to next process. *)

PROCEDURE Terminate*;	(* exported for AosLinker *)
VAR id: LONGINT;
BEGIN
	IF Stats & stats THEN AosBoot.Inc(Nterminate) END;
	AosLocks.Acquire(AosLocks.AosActive);
	id := AosBoot.ID();
	(*running[id].state.EIP := CallerEIP();*)	(* for tracing *)
	running[id].mode := Terminated;	(* a process can also be "terminated" if the queue containing it is garbage collected *)
	SwitchToNew;
	HALT(2201)	(* process resurrected *)
END Terminate;

(* Induced halt. *)

PROCEDURE Halt;
CODE {SYSTEM.i386}
	POP EBP
	PUSH 2202	(* process halted *)
	INT 3
END Halt;

(** Attempt to terminate a specific process (mostly ignoring its locks). DEPRECATED *)

PROCEDURE TerminateThis*(t: Process; halt: BOOLEAN);
VAR hdr: ObjectHeader;
BEGIN
	IF ~(Resistant IN t.flags) THEN
		AosLocks.Acquire(AosLocks.AosActive);
		IF Trace THEN
			AosOut.String(" Kill "); AosOut.Int(t.id, 1); AosOut.Char(" "); AosOut.Int(t.mode, 1)
		END;
		CASE t.mode OF
			Ready, Running:
				INCL(t.flags, PleaseStop);
				IF halt THEN INCL(t.flags, PleaseHalt) END
			|AwaitingLock, AwaitingCond:
				ASSERT(SYSTEM.VAL(SET, t.waitingOn) * AosHeap.FlagBits = {AosHeap.ProtObjBit});
				hdr := SYSTEM.VAL(ObjectHeader, SYSTEM.VAL(LONGINT, t.waitingOn)-AosHeap.ProtOfs);
				IF ObjectLock THEN
					AosLocks.AcquireObject(hdr.locked)	(* potential deadlock, because of AosActive lock order *)
				END;
				IF t.mode = AwaitingLock THEN Remove(hdr.awaitingLock, t)
				ELSE Remove(hdr.awaitingCond, t)
				END;
				t.waitingOn := NIL;
				IF ObjectLock THEN
					AosLocks.ReleaseObject(hdr.locked)
				END;
				IF halt THEN
					SYSTEM.PUT(t.state.EBP+4, trap);	(* modify SwitchTo return address *)
					Enter(t)
				ELSE
					t.mode := Terminated
				END
			|Terminated, AwaitingEvent, Unknown:	(* skip *)
		END;
		AosLocks.Release(AosLocks.AosActive)
	END
END TerminateThis;

(* Finalize a process. *)

PROCEDURE FinalizeProcess(t: SYSTEM.PTR);
BEGIN
(*
	AosOut.Enter; AosOut.String("Process "); AosOut.Int(t(Process).id, 1);
	AosOut.Char(" "); AosOut.Int((t(Process).stack.high - t(Process).stack.adr) DIV 1024, 1);
	AosOut.String("KB stack freed"); AosOut.Exit;
*)
	AosMemory.DisposeStack(t(Process).stack)
END FinalizeProcess;

(* Allocate a new process associated with "obj".  Must be outside lock region, because of potential GC. *)

PROCEDURE NewProcess(body: Body; type: LONGINT; flags: SET; obj: ProtectedObject; VAR new: Process);
VAR t: Process; sp, id: LONGINT; fn: AosHeap.FinalizerNode;
BEGIN
	NEW(t); NEW(fn);	(* implicit call AosHeap.NewRec *)
	t.next := NIL; t.prev := NIL; t.waitingOn := NIL; t.flags := flags;
	t.obj := obj; t.mode := Unknown; t.handler := NIL;
		(* initialize the stack *)
	AosMemory.NewStack(t.stack, t, sp);
	IF VeryConservative THEN
		AosBoot.Fill32(t.stack.adr, sp-t.stack.adr, 0D0D0DEADH)
	END;
	SYSTEM.PUT(sp-4, type);	(* typetag parameter for body *)
	SYSTEM.PUT(sp-8, obj);	(* self parameter for body *)
	SYSTEM.PUT(sp-12, terminate);	(* return address for body *)
		(* the following will be popped by SwitchTo exit code or AosMemory.JumpToUserLevel *)
	(*SYSTEM.PUT(sp-16, NIL);*)	(* parameter for SwitchTo (ADR(running)) *)
	(*SYSTEM.PUT(sp-20, NIL);*)	(* parameter for SwitchTo (new) *)
	SYSTEM.PUT(sp-24, body);	(* return address for SwitchTo (body entry point) *)
	SYSTEM.PUT(sp-28, NIL);	(* end of dynamic link list (FP value at entry to body) *)
	t.sseAdr := SYSTEM.ADR(t.sse) + ((-SYSTEM.ADR(t.sse)) MOD 16);
	IF AosBoot.SSESupport THEN SSESaveMin(t.sseAdr)
	ELSE FPUSaveMin(t.sse)	(* inherit FPU state of caller *)
	END;
	t.state.EBP := sp-28;
	t.state.ESP := t.state.EBP;
		(* set up exception handling *)
	IF Restart IN flags THEN	(* restart object body *)
		t.restartPC := SYSTEM.VAL(LONGINT, body);
		t.restartSP := sp-12	(* 2 parameters and return address of body *)
	ELSE	(* terminate process *)
		t.restartPC := SYSTEM.VAL(LONGINT, terminate);
		t.restartSP := sp
	END;
	fn.finalizer := FinalizeProcess;
	AosHeap.AddFinalizer(t, fn);
		(* return *)
	IF Trace THEN
		AosOut.Enter; AosOut.String("NewStack"); AosOut.Hex(t.stack.adr, 9);
		AosOut.Hex(t.stack.high, 9); AosOut.Exit
	END;
	FOR id := 0 TO AosBoot.MaxCPU-1 DO t.perfCyc[id] := 0 END;
	new := t
END NewProcess;

(* Create the process associated with an active object (kernel call). *)

PROCEDURE CreateProcess(body: Body; priority: LONGINT; flags: SET; obj: ProtectedObject);
VAR t: Process; type: LONGINT;
BEGIN
	IF Trace THEN
		AosOut.Enter; AosOut.String("CreateProcess"); AosOut.Hex(entry, 9); AosOut.Char(" ");
		AosOut.Int(priority, 1); AosOut.Hex(SYSTEM.VAL(LONGINT, flags), 9);
		AosOut.Hex(SYSTEM.VAL(LONGINT, obj), 9); AosOut.Exit
	END;
	IF Stats & stats THEN AosBoot.Inc(Ncreate) END;
	ASSERT(SYSTEM.VAL(SET, obj) * AosHeap.FlagBits = {AosHeap.ProtObjBit});	(* protected object *)
	SYSTEM.GET(SYSTEM.VAL(LONGINT, obj)-4, type);	(* type tag *)
	IF Restart IN flags THEN INCL(flags, Resistant) END;	(* SAFE => Restart & Resistant *)
	NewProcess(body, type, flags, obj, t);
	AosLocks.Acquire(AosLocks.AosActive);
	t.id := nextProcessID; INC(nextProcessID);
	IF priority = 0 THEN	(* no priority specified *)
		t.priority := running[AosBoot.ID()].priority	(* inherit priority of creator *)
	ELSIF priority > 0 THEN	(* positive priority specified *)
		t.priority := priority
	ELSE	(* negative priority specified (only for Idle process) *)
		t.priority := MinPriority
	END;
	t.currPri := t.priority;
	t.state.EIP := SYSTEM.VAL(LONGINT, body);	(* for tracing *)
	Enter(t);
	AosLocks.Release(AosLocks.AosActive)
END CreateProcess;

(* Lock a protected object (kernel call). *)

PROCEDURE Lock(obj: ProtectedObject; exclusive: BOOLEAN);
VAR hdr, h: ObjectHeader; r, p: Process; id: LONGINT; o: ProtectedObject;
BEGIN	(* {called from user level} *)
	IF Stats & stats THEN AosBoot.Inc(Nlock) END;
	IF StrongChecks THEN
		ASSERT(SYSTEM.VAL(SET, obj) * AosHeap.FlagBits = {AosHeap.ProtObjBit});	(* protected object *)
		ASSERT(exclusive)	(* shared not implemented yet *)
	END;
	hdr := SYSTEM.VAL(ObjectHeader, SYSTEM.VAL(LONGINT, obj)-AosHeap.ProtOfs);
	PUSHFD; SYSTEM.CLI();
	AosLocks.AcquireObject(hdr.locked);
	IF hdr.count = 0 THEN	(* not locked *)
		hdr.count := -1; hdr.lockedBy := SYSTEM.VAL(Process, AosMemory.GetProcessPtr());	(* set exclusive lock *)
		AosLocks.ReleaseObject(hdr.locked);
		POPFD
	ELSE	(* locked (to do: on multiprocessors, perhaps spin here for a while, if lockedBy.mode = running) *)
		id := AosLocks.AcquirePreemption();
		POPFD;
		r := SYSTEM.VAL(Process, AosMemory.GetProcessPtr());
		IF hdr.lockedBy = r THEN AosLocks.ReleaseObject(hdr.locked); 
			ASSERT(hdr.lockedBy # r, 2203);	(* nested locks not allowed *)
		END;	
		ASSERT(r.waitingOn = NIL);
		r.waitingOn := obj; r.mode := AwaitingLock;
		AosLocks.Acquire(AosLocks.AosActive); (* could be moved after the LOOP, but make sure r is put in the right hrd *)
		IF HandleInvPriority THEN
			PutSorted(hdr.awaitingLock, r);
			LOOP	(* priority inversion handling, traverse lock dependence chain *)
				p := hdr.lockedBy;
				o := p.waitingOn;
				IF o = NIL THEN EXIT END;
				h := SYSTEM.VAL(ObjectHeader, SYSTEM.VAL(LONGINT, o)-AosHeap.ProtOfs);
				AosLocks.AcquireObject(h.locked);
				IF (p.currPri >= r.currPri) OR (p.waitingOn = NIL) THEN
					AosLocks.ReleaseObject(h.locked);
					EXIT
				ELSIF h.count = 0 THEN
					AosLocks.ReleaseObject(h.locked);
					r.state.EIP := CallerEIP();	(* for tracing only *)
					AosLocks.ReleaseObject(hdr.locked);	(* lock release order? *)
					AosLocks.ReleasePreemption;
					SwitchToNew;
					RETURN
				END;
				p.currPri := r.currPri;
				IF ~hdr.decInvCnt THEN INC(p.priInvCnt); hdr.decInvCnt := TRUE; hdr.checkP := p END;
				AosLocks.ReleaseObject(hdr.locked);
				hdr := h;
			END;
			IF p.currPri < r.currPri THEN (* priority inversion handling *)
				IF p.mode = Ready THEN Remove(ready[p.currPri], p) END;
				p.currPri := r.currPri;
				IF ~hdr.decInvCnt THEN INC(p.priInvCnt); hdr.decInvCnt := TRUE; hdr.checkP := p END;
				IF p.mode = Ready THEN Enter(p) END
			END;
		ELSE
			Put(hdr.awaitingLock, r)
		END;
		r.state.EIP := CallerEIP();	(* for tracing only *)
		AosLocks.ReleaseObject(hdr.locked);	(* lock release order? *)
		AosLocks.ReleasePreemption;
		SwitchToNew
	END
END Lock;

(*
PROCEDURE Lock(obj: ProtectedObject; exclusive: BOOLEAN);
VAR hdr: ObjectHeader; r: Process; id: LONGINT;
BEGIN	(* {called from user level} *)
	IF Trace THEN
		AosOut.Enter; AosOut.String("Lock"); AosOut.Hex(SYSTEM.VAL(LONGINT, obj), 9);
		AosOut.Int(SYSTEM.VAL(SHORTINT, exclusive), 2);
		AosOut.Hex(SYSTEM.VAL(LONGINT, running[AosBoot.ID()]), 9);
		AosOut.Exit
	END;
	IF Stats & stats THEN AosBoot.Inc(Nlock) END;
	IF StrongChecks THEN
		ASSERT(SYSTEM.VAL(SET, obj) * AosHeap.FlagBits = {AosHeap.ProtObjBit});	(* protected object *)
		ASSERT(exclusive)	(* shared not implemented yet *)
	END;
	hdr := SYSTEM.VAL(ObjectHeader, SYSTEM.VAL(LONGINT, obj)-AosHeap.ProtOfs);
	IF ObjectLock THEN
		id := AosLocks.AcquirePreemption()
	ELSE
		AosLocks.Acquire(AosLocks.AosActive);
		id := AosBoot.ID()
	END;
	r := running[id];
	IF PleaseStop IN r.flags THEN
		IF ObjectLock THEN
			AosLocks.ReleasePreemption
		ELSE
			AosLocks.Release(AosLocks.AosActive)
		END;
		IF PleaseHalt IN r.flags THEN Halt ELSE Terminate END;
		HALT(2206)	(* never reached *)
	END;
	IF ObjectLock THEN
		AosLocks.AcquireObject(hdr.locked)
	END;
	IF hdr.count = 0 THEN	(* not locked *)
		hdr.count := -1; hdr.lockedBy := r;	(* set exclusive lock *)
		IF ObjectLock THEN
			AosLocks.ReleaseObject(hdr.locked);
			AosLocks.ReleasePreemption
		ELSE
			AosLocks.Release(AosLocks.AosActive)
		END
	ELSE	(* locked (to do: on multiprocessors, perhaps spin here for a while, if lockedBy.mode = running) *)
		ASSERT(hdr.lockedBy # r, 2203);	(* nested locks not allowed *)
		IF ObjectLock THEN	(* not acquired yet *)
			AosLocks.Acquire(AosLocks.AosActive)	(* Put and SwitchTo must be protected *)
		END;
		ASSERT(r.waitingOn = NIL);
		r.waitingOn := obj; r.mode := AwaitingLock;
		Put(hdr.awaitingLock, r);
		r.state.EIP := CallerEIP();	(* for tracing only *)
		IF ObjectLock THEN
			AosLocks.ReleaseObject(hdr.locked);	(* lock release order? *)
			AosLocks.ReleasePreemption
		END;
		SwitchToNew
	END
END Lock;
*)

(* Find the first true condition from the queue and remove it.  Assume the object is currently locked. *)

PROCEDURE FindCondition(VAR q: ProcessQueue): Process;
VAR first, cand: Process;
BEGIN
	IF Stats & stats THEN AosBoot.Inc(Ncondition) END;
	Get(q, first);
	IF first.condition(first.condFP) THEN
		IF Stats & stats THEN AosBoot.Inc(Ncondition1True) END;
		RETURN first
	END;
	Put(q, first);
	WHILE q.head # first DO
		IF Stats & stats THEN AosBoot.Inc(Ncondition2) END;
		Get(q, cand);
		IF cand.condition(cand.condFP) THEN
			IF Stats & stats THEN AosBoot.Inc(Ncondition2True) END;
			RETURN cand
		END;
		Put(q, cand)
	END;
	RETURN NIL
END FindCondition;

(* Unlock a protected object (kernel call). *)

PROCEDURE Unlock(obj: ProtectedObject; dummy: LONGINT);
VAR hdr: ObjectHeader; t, c, r: Process; hlp: LONGINT;
BEGIN
	IF Stats & stats THEN AosBoot.Inc(Nunlock) END;
	IF StrongChecks THEN
		ASSERT(SYSTEM.VAL(SET, obj) * AosHeap.FlagBits = {AosHeap.ProtObjBit})	(* protected object *)
	END;
	hdr := SYSTEM.VAL(ObjectHeader, SYSTEM.VAL(LONGINT, obj)-AosHeap.ProtOfs);
	ASSERT(hdr.count = -1);	(* exclusive locked *)
	IF hdr.awaitingCond.head # NIL THEN	(* evaluate the waiting conditions *)
			(* we are holding the lock, so the queue can not change (to do: except in TerminateThis) *)
		c := FindCondition(hdr.awaitingCond)	(* interrupts should be on during this call *)
	ELSE
		c := NIL
	END;
	PUSHFD; SYSTEM.CLI();
	AosLocks.AcquireObject(hdr.locked);
	r := running[AosBoot.ID()];
	IF HandleInvPriority THEN
		IF hdr.decInvCnt THEN (* priority inversion, reset priority *)
			ASSERT((hdr.checkP = r) & (r.priInvCnt > 0));
			DEC(r.priInvCnt); hdr.decInvCnt := FALSE;
			IF r.priInvCnt = 0 THEN r.currPri := r.priority END
		END
	END;
	IF StrongChecks THEN
		ASSERT(hdr.lockedBy = r)
	END;
	IF c = NIL THEN	(* no true condition found, check the lock queue *)
		Get(hdr.awaitingLock, t);
		IF t # NIL THEN
			IF StrongChecks THEN
				ASSERT((t.mode = AwaitingLock) & (t.waitingOn = obj))
			END;
			hdr.lockedBy := t; t.waitingOn := NIL
		ELSE
			hdr.lockedBy := NIL; hdr.count := 0
		END
	ELSE	(* true condition found, transfer the lock *)
		IF HandleInvPriority THEN
			IF hdr.awaitingLock.head # NIL THEN (* priority inversion handling *)
				hlp := hdr.awaitingLock.head.currPri;
				IF hlp > c.currPri THEN c.currPri := hlp; INC(c.priInvCnt); hdr.decInvCnt := TRUE; hdr.checkP := c END;
			END;
		END;
		c.waitingOn := NIL; hdr.lockedBy := c;
		t := NIL
	END;
	AosLocks.ReleaseObject(hdr.locked);
	IF (c # NIL) OR (t # NIL) THEN
		IF AosLocks.AcquirePreemption() = 0 THEN END;	(* required? *)
		POPFD;
		AosLocks.Acquire(AosLocks.AosActive);
		IF c # NIL THEN Enter(c) END;
		IF t # NIL THEN Enter(t) END;
		AosLocks.Release(AosLocks.AosActive);
		AosLocks.ReleasePreemption()
	ELSE
		POPFD
	END
END Unlock;

(*
PROCEDURE Unlock(obj: ProtectedObject; dummy: LONGINT);
VAR id: LONGINT; hdr: ObjectHeader; t, c: Process;
BEGIN
	IF Trace THEN
		AosOut.Enter; AosOut.String("Unlock"); AosOut.Hex(SYSTEM.VAL(LONGINT, obj), 9);
		AosOut.Int(dummy, 2); AosOut.Exit
	END;
	IF Stats & stats THEN AosBoot.Inc(Nunlock) END;
	IF StrongChecks THEN
		ASSERT(SYSTEM.VAL(SET, obj) * AosHeap.FlagBits = {AosHeap.ProtObjBit})	(* protected object *)
	END;
	hdr := SYSTEM.VAL(ObjectHeader, SYSTEM.VAL(LONGINT, obj)-AosHeap.ProtOfs);
	ASSERT(hdr.count = -1);	(* exclusive locked *)
	IF hdr.awaitingCond.head # NIL THEN	(* evaluate the waiting conditions *)
			(* we are holding the lock, so the queue can not change (to do: except in TerminateThis) *)
		c := FindCondition(hdr.awaitingCond)	(* interrupts should be on during this call *)
	ELSE
		c := NIL
	END;
	IF ObjectLock THEN
		id := AosLocks.AcquirePreemption();
		AosLocks.AcquireObject(hdr.locked)
	ELSE
		AosLocks.Acquire(AosLocks.AosActive);
		id := AosBoot.ID()
	END;
	IF StrongChecks THEN
		ASSERT(hdr.lockedBy = running[id])
	END;
	IF c = NIL THEN	(* no true condition found, check the lock queue *)
		Get(hdr.awaitingLock, t);
		IF t # NIL THEN
			IF StrongChecks THEN
				ASSERT((t.mode = AwaitingLock) & (t.waitingOn = obj))
			END;
			hdr.lockedBy := t; t.waitingOn := NIL
		ELSE
			hdr.lockedBy := NIL; hdr.count := 0
		END
	ELSE	(* true condition found, transfer the lock *)
		c.waitingOn := NIL; hdr.lockedBy := c;
		t := NIL
	END;
	IF ObjectLock THEN
		AosLocks.ReleaseObject(hdr.locked)
	END;
	IF (c # NIL) OR (t # NIL) THEN
		IF ObjectLock THEN
			AosLocks.Acquire(AosLocks.AosActive)
		END;
		IF c # NIL THEN Enter(c) END;
		IF t # NIL THEN Enter(t) END;
		IF ObjectLock THEN
			AosLocks.Release(AosLocks.AosActive)
		END
	END;
	IF ObjectLock THEN
		AosLocks.ReleasePreemption()
	ELSE
		AosLocks.Release(AosLocks.AosActive)
	END
END Unlock;
*)

(* Await a condition (kernel call). *)

PROCEDURE Await(cond: Condition; slink: LONGINT; obj: ProtectedObject; flags: SET);
VAR hdr: ObjectHeader; r, t: Process; id: LONGINT;
BEGIN
	IF Trace THEN
		AosOut.Enter; AosOut.String("Await"); AosOut.Hex(SYSTEM.VAL(LONGINT, cond), 9);
		AosOut.Hex(slink, 9); AosOut.Hex(SYSTEM.VAL(LONGINT, obj), 9);
		AosOut.Hex(SYSTEM.VAL(LONGINT, flags), 9); AosOut.Exit
	END;
	IF Stats & stats THEN AosBoot.Inc(Nawait) END;
	IF 1 IN flags THEN	(* compiler did not generate IF *)
		IF Stats & stats THEN AosBoot.Inc(NawaitNoIF) END;
		IF cond(slink) THEN
			IF Stats & stats THEN AosBoot.Inc(NawaitTrue) END;
			RETURN	(* condition already true *)
		END
	END;
	IF StrongChecks THEN
		ASSERT(SYSTEM.VAL(SET, obj) * AosHeap.FlagBits = {AosHeap.ProtObjBit})	(* protected object *)
	END;
	hdr := SYSTEM.VAL(ObjectHeader, SYSTEM.VAL(LONGINT, obj)-AosHeap.ProtOfs);
	IF ObjectLock THEN
		id := AosLocks.AcquirePreemption();
		AosLocks.AcquireObject(hdr.locked)	(* must acquire object lock before other locks *)
	ELSE
		AosLocks.Acquire(AosLocks.AosActive);
		id := AosBoot.ID()
	END;
	r := running[id];
	IF hdr.lockedBy = r THEN	(* current process holds exclusive lock *)
		IF StrongChecks THEN ASSERT(hdr.count = -1) END;	(* exclusive locked *)
		IF HandleInvPriority THEN
			IF hdr.decInvCnt THEN (* priority inversion, reset priority *)
				ASSERT((hdr.checkP = r) & (r.priInvCnt > 0));
				DEC(r.priInvCnt); hdr.decInvCnt := FALSE;
				IF r.priInvCnt = 0 THEN r.currPri := r.priority END
			END;
		END;	
		Get(hdr.awaitingLock, t);
		IF t = NIL THEN	(* none waiting - remove lock *)
			hdr.count := 0; hdr.lockedBy := NIL
		ELSE	(* transfer lock to first waiting process *)
			IF StrongChecks THEN ASSERT(t.mode = AwaitingLock) END;
			t.waitingOn := NIL;
			hdr.lockedBy := t;
			(*Enter(t)*)
		END
	ELSE	(* no lock, or some other process may hold the lock, but that's the user's indaba (may be monotonic condition) *)
		HALT(2204)	(* await must be exclusive region *)
	END;
	IF ObjectLock THEN
		AosLocks.Acquire(AosLocks.AosActive)	(* Put and SwitchTo must be protected *)
	END;
	IF t # NIL THEN Enter(t) END;
	IF StrongChecks THEN ASSERT(r.waitingOn = NIL) END;
	r.condition := cond; r.condFP := slink;
	r.waitingOn := obj; r.mode := AwaitingCond;
	Put(hdr.awaitingCond, r);
	r.state.EIP := CallerEIP();	(* for tracing *)
	IF ObjectLock THEN
		AosLocks.ReleaseObject(hdr.locked);
		AosLocks.ReleasePreemption()
	END;
		(* reschedule *)
	SwitchToNew;
	IF StrongChecks THEN
		(*ASSERT(r = running[AosBoot.ID()]);*)	(* id variable no longer valid *)
		ASSERT(cond(slink));
		ASSERT(hdr.lockedBy = r)	(* lock held again *)
	END
END Await;

(** Update the state snapshot of the current process for GC.  (for AosProcessors) *)

PROCEDURE UpdateState*(eip: LONGINT);
VAR t: Process;
BEGIN (* interrupts off *)
	t := running[AosBoot.ID()];
	IF t # NIL THEN
		t.state.EIP := eip;	(* for tracing *)
		AosMemory.GetUserStack(t.state.ESP)
	ELSE
		(* This can happen during startup.  Another processor has initiated the garbage collector before we have had a chance to start running processes, most likely because of the AosOut.Enter lock in AosProcessors.StartMP . *)
	END
END UpdateState;

(** Start executing user processes.  Every processor calls this during initialization. *)

PROCEDURE Start*;
VAR id: LONGINT; idle: Idle; new: Process;
BEGIN	(* running at kernel level (not preemptable) *)
	id := AosBoot.ID();	(* preemption not enabled yet, because we are running at kernel level *)
	NEW(idle);	(* create process with MinPriority *)
	AosLocks.Acquire(AosLocks.AosActive);
	Get(ready[MinPriority], new);	(* can not use Select here, as it might return a preempted process *)
	ASSERT(~(Preempted IN new.flags));	(* will at least get the Idle process just created *)
	AosLocks.Release(AosLocks.AosActive);
	running[id] := new;	(* schedule new process *)
	new.mode := Running; new.procID := id;
	IF AosBoot.SSESupport THEN SSERestoreMin(new.sseAdr)
	ELSE FPURestoreMin(new.sse)
	END;
	AosMemory.JumpToUserLevel(new.state.EBP)
END Start;

(* Initialize module. *)

PROCEDURE Init;	(* can not use NEW *)
VAR
	lock: PROCEDURE (obj: ProtectedObject; exclusive: BOOLEAN);
	unlock: PROCEDURE (obj: ProtectedObject; dummy: LONGINT);
	await: PROCEDURE (cond: Condition; slink: LONGINT; obj: ProtectedObject; flags: SET);
	create: PROCEDURE (body: Body; priority: LONGINT; flags: SET; obj: ProtectedObject);
	i: LONGINT;
BEGIN
	ProcessorHLT := NIL; stats := TRUE;
	FOR i := 0 TO NumPriorities-1 DO
		ready[i].head := NIL; ready[i].tail := NIL
	END;
	maxReady := High;	(* scan all queues at start *)
	FOR i := 0 TO AosBoot.MaxCPU-1 DO running[i] := NIL END;
	nextProcessID := 0; ticks := 0;
	snapshot := NIL; snapshotEnabled := FALSE; traceProcess := NIL;
	lock := Lock; unlock := Unlock; await := Await; create := CreateProcess;
	AosModules.kernelProc[3] := SYSTEM.VAL(LONGINT, create);	(* 250 *)
	AosModules.kernelProc[4] := SYSTEM.VAL(LONGINT, await);	(* 249 *)
	AosModules.kernelProc[6] := SYSTEM.VAL(LONGINT, lock);	(* 247 *)
	AosModules.kernelProc[7] := SYSTEM.VAL(LONGINT, unlock);	(* 246 *)
	terminate := Terminate; trap := Halt
END Init;

PROCEDURE InitEventHandling;
VAR i: LONGINT; t: Clock;
BEGIN
	FOR i := 0 TO NumIRQ-1 DO
		interrupt[i].root := NIL; interrupt[i].process := NIL
	END;
	NEW(event); event.tnext := event; event.tprev := event;
	event.trigger := ticks + MAX(LONGINT) DIV 2;
	timer := NIL; NEW(t)
END InitEventHandling;

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

(** Clear statistical counters. *)

PROCEDURE ClearCounters*;
BEGIN
	IF Stats THEN
		Nlock := 0; Nunlock := 0; Nawait := 0; NawaitNoIF := 0; NawaitTrue := 0; 
		Ncreate := 0; Nterminate := 0; Ncondition := 0; Ncondition1True := 0; 
		Ncondition2 := 0; Ncondition2True := 0;
		Ntimeslice := 0; NtimesliceTaken := 0; NtimesliceNothing := 0; 
		NtimesliceIdle := 0; NtimesliceKernel := 0; NtimesliceV86 := 0; NtimesliceCritical := 0; 
		Npreempt := 0; NpreemptTaken := 0; NpreemptNothing := 0; 
		NpreemptKernel := 0; NpreemptV86 := 0; NpreemptCritical := 0; 
		Nenter := 0; NenterHigherRunningPriority := 0; NenterHigherIdlePriority := 0
	END
END ClearCounters;

PROCEDURE UpdatePerf*;
VAR id: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosActive);
	id := 0;
	WHILE (running[id] # NIL) & (id < AosBoot.MaxCPU) DO
		running[id].perfCyc[id] := AosBoot.AddH(AosBoot.SubH(AosBoot.GetTimer(), perfTsc[id]), running[id].perfCyc[id]);
		perfTsc[id] := AosBoot.GetTimer();
		INC(id)
	END;
	AosLocks.Release(AosLocks.AosActive)
END UpdatePerf;

BEGIN
	IF AosBoot.Trace THEN AosOut.Enter; AosOut.String("AosActive"); AosOut.Exit END;
	Init;
		(* initialize memory management *)
	AosMemory.UpdateState;	(* for gc *)
	AosHeap.CollectGarbage(AosModules.root);	(* still in single-processor mode *)
		(* now NEW can be used *)
	AosInterrupts.Init; AosInterrupts.Start;	(* initialize interrupts *)
	InitEventHandling;
		(* create a process for rest of init code, which runs at user level *)
	SYSTEM.GETREG(SYSTEM.EBP, entry);
	SYSTEM.GET(entry+4, entry);	(* return address into linker-generated call table *)
	NewProcess(SYSTEM.VAL(Body, entry), 0, {Resistant}, NIL, init);	(* create init process *)
	init.priority := High;
	init.currPri := High;
	AosLocks.Acquire(AosLocks.AosActive);
	init.id := -1; Enter(init); init := NIL;
	AosLocks.Release(AosLocks.AosActive);
	Start	(* start it *)
		(* linker call table will end with a call to Terminate.  So after executing all module bodies, 
		the init process will terminate and other processes created during init will continue running. *)
END AosActive.

(*
24.03.1998	pjm	Started
06.05.1998	pjm	CreateProcess init process, page fault handler
06.08.1998	pjm	Moved exception interrupt handling here for current process
17.08.1998	pjm	FindRoots method
02.10.1998	pjm	Idle process
06.11.1998	pjm	snapshot
25.03.1999	pjm	Scope removed
28.05.1999	pjm	EventHandler object
01.06.1999	pjm	Fixed InterruptProcess lock error
16.06.1999	pjm	Flat IRQ priority model to avoid GC deadlock
23.06.1999	pjm	Flat IRQ priority experiment failed, rather do STI in FieldIRQ to avoid GC deadlock
29.06.1999	pjm	Timeout in EventHandler object
13.01.2000	pjm	Overed (Interrupt Objects, Event Handlers, Process ID, Process state, Process mode, Process stack, Await)
17.10.2000	pjm	Priorities
22.10.2003	mib	SSE2 extension
24.10.2003	phk	Priority inversion / cycle counters

Stack invariant for GC:
o if process is running, the processor registers contain its state
o if process is not running, at least state.ESP is valid, and between stack.adr and stack.high (for GC)

o when releasing the Ready lock, make sure the process state is up to date 
*)

(*
Location	Stack
Lock	Current process
  SwitchTo.A	Current process
  SwitchTo.B	
*)

(*
to do:
o use delegates instead of EventHandler?
*)
