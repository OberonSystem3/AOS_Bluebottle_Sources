(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosProcessors; (** AUTHOR "pjm"; PURPOSE "Multiple processor handling"; *)

(* Set MaxProcs to maximum number of processors for testing. *)

IMPORT
	SYSTEM, AosBoot, AosLocks, AosOut, AosMemory, AosHeap, AosInterrupts, AosModules, AosActive;

CONST
	Self* = 0; FrontBarrier* = 1; BackBarrier* = 2;	(** Broadcast flags. *)
	
	MPIPCLocal = AosInterrupts.MPIPCLocal; MPKC = AosInterrupts.MPKC;

	Trace = FALSE;
	TraceApic = FALSE;
	TraceProcessor = FALSE;	(* remove this hack! *)
	
	ClockRateDelay = 50;	(* ms - delay when timing bus clock rate *)
	
	TimerClock = 1193180;	(* timer clock is 1.19318 MHz *)

TYPE
	EventHandler* = PROCEDURE (id: LONGINT; VAR state: AosInterrupts.State);
	
	Message* = POINTER TO RECORD END;	(** Broadcast message. *)
	BroadcastHandler* = PROCEDURE (id: LONGINT; VAR state: AosInterrupts.State; msg: Message);
	
	TimeArray = ARRAY AosBoot.MaxCPU OF HUGEINT;

VAR
	ipcBusy, ipcFlags, ipcFrontBarrier, ipcBackBarrier: SET;
	ipcHandler: BroadcastHandler;
	ipcMessage: Message;
	gcBarrier: SET;
	numProcessors: LONGINT;	(* number of processors we attempted to boot (some may have failed) *)
	maxProcessors: LONGINT;	(* max number of processors we are allowed to boot (-1 for uni) *)
	allProcessors: SET;	(* IDs of all successfully booted processors *)
	localAPIC: LONGINT;	(* address of local APIC, 0 if not present *)
	apicVer: ARRAY AosBoot.MaxCPU OF LONGINT;	(* APIC version *)
	started: ARRAY AosBoot.MaxCPU OF BOOLEAN;	(* CPU started successfully / CPU halted *)
	busHz0, busHz1: ARRAY AosBoot.MaxCPU OF LONGINT;	(* unrounded and rounded bus speed in Hz *)
	timer: EventHandler;
	timerRate: LONGINT;	(* Hz - rate at which CPU timers run - for timeslicing and profiling *)
	stopped: BOOLEAN;	(* StopAll was called *)
	idMap: AosBoot.IDMap;
	revIDmap: ARRAY AosBoot.MaxCPU OF SHORTINT;
	time: TimeArray;
	eventCount, eventMax: LONGINT;
	event: AosInterrupts.Handler;
	traceProcessorProc*: EventHandler;	(** temp tracing *)
	traceProcessor: BOOLEAN;

(* Write a value to the APIC. *)

PROCEDURE ApicPut(ofs: LONGINT; val: SET);
BEGIN
	IF TraceApic THEN
		AosOut.Hex(ofs, 8); AosOut.String(" := "); AosOut.Hex(SYSTEM.VAL(LONGINT, val), 9); AosOut.Ln
	END;
	SYSTEM.PUT(localAPIC+ofs, val)
END ApicPut;

(* Read a value from the APIC. *)

PROCEDURE ApicGet(ofs: LONGINT): SET;
VAR val: SET;
BEGIN
	SYSTEM.GET(localAPIC+ofs, val);
	IF TraceApic THEN
		AosOut.String(" ("); AosOut.Hex(ofs, 8); AosOut.String(" = ");
		AosOut.Hex(SYSTEM.VAL(LONGINT, val), 9); AosOut.String(")")
	END;
	RETURN val
END ApicGet;

(* Handle interprocessor interrupt.  During upcall interrupts are off and processor is at kernel level. *)

PROCEDURE HandleIPC(VAR state: AosInterrupts.State);
VAR id: LONGINT;
BEGIN
	id := AosBoot.ID();
	IF ~TraceProcessor OR (id IN allProcessors) THEN
		IF FrontBarrier IN ipcFlags THEN
			AosBoot.Excl(ipcFrontBarrier, id);
			WHILE ipcFrontBarrier # {} DO AosBoot.SpinHint END	(* wait for all *)
		END;
		ipcHandler(id, state, ipcMessage);	(* interrupts off and at kernel level *)
		IF BackBarrier IN ipcFlags THEN
			AosBoot.Excl(ipcBackBarrier, id);
			WHILE ipcBackBarrier # {} DO AosBoot.SpinHint END	(* wait for all *)
		END;
		AosBoot.Excl(ipcBusy, id)	(* ack - after this point we do not access shared variables for this broadcast *)
	END;
	IF state.INT = AosInterrupts.MPIPC THEN
		ApicPut(0B0H, {})	(* EOI (not needed for NMI or local call, see 7.4.10.6) *)
	END
END HandleIPC;

(* Handle MP error interrupt. *)

PROCEDURE HandleError(VAR state: AosInterrupts.State);
VAR esr: SET; int: LONGINT;
BEGIN
	int := state.INT; esr := ApicGet(280H);
	ApicPut(0B0H, {});	(* EOI *)
	HALT(2302)	(* SMP error *)
END HandleError;

PROCEDURE -CallLocalIPC;
CODE {SYSTEM.i386}
	INT MPIPCLocal
END CallLocalIPC;

(* Interprocessor broadcasting.  Lock level SMP. *)

PROCEDURE LocalBroadcast(h: BroadcastHandler; msg: Message; flags: SET);
BEGIN
	IF Self IN flags THEN ipcBusy := allProcessors
	ELSE ipcBusy := allProcessors - {AosBoot.ID()}
	END;
	ipcFrontBarrier := ipcBusy; ipcBackBarrier := ipcBusy;
	ipcHandler := h; ipcMessage := msg; ipcFlags := flags;
	IF numProcessors > 1 THEN	(* ICR: Fixed, Physical, Edge, All Excl. Self, INT IPC *)
		ApicPut(300H, {18..19} + SYSTEM.VAL(SET, AosInterrupts.MPIPC));
		(*REPEAT UNTIL ~(12 IN ApicGet(300H))*)	(* wait for send to finish *)
	END;
	IF Self IN flags THEN CallLocalIPC END;	(* "send" to self also *)
	WHILE ipcBusy # {} DO AosBoot.SpinHint END;	(* wait for all to ack before we release locks *)
	ipcHandler := NIL; ipcMessage := NIL	(* no race, because we have IPC lock *)
END LocalBroadcast;

(** Broadcast an operation to all processors. *)

PROCEDURE Broadcast*(h: BroadcastHandler; msg: Message; flags: SET);
BEGIN
	AosLocks.Acquire(AosLocks.AosProcessors);
	LocalBroadcast(h, msg, flags);
	AosLocks.Release(AosLocks.AosProcessors)
END Broadcast;

(* Start all halted processors. *)	(* Lock level AosProcessors. *)

PROCEDURE StartAll;
BEGIN
	AosLocks.Acquire(AosLocks.AosProcessors);	(* wait for any pending Stops to finish, and disallow further Stops *)
	ASSERT(stopped & (ipcBusy = {}));
	ipcBusy := allProcessors - {AosBoot.ID()};
	stopped := FALSE;
	WHILE ipcBusy # {} DO AosBoot.SpinHint END;	(* wait for all to ack *)
	AosLocks.Release(AosLocks.AosProcessors)
END StartAll;

(*
PROCEDURE HandleStop(VAR state: AosInterrupts.State; id: LONGINT; msg: Message);
BEGIN (* interrupts off *)
	AosMemory.UpdateState;	(* for garbage collection *)
	AosActive.UpdateState(state.EIP);	(* for garbage collection *)
	AosBoot.Excl(ipcBusy, id);	(* ack for LocalBroadcast in StopAll *)
	WHILE stopped DO AosBoot.SpinHint END
END HandleStop;

(** Stop all other processors. *)	(* Lock level ALL. *)

PROCEDURE StopAll*;
BEGIN
		(* fixme: is this still needed, as interrupts are disabled during locks? *)
	AosLocks.AcquireAll;	(* ensure that we do not stop a processor holding a lock *)
	IF AosBoot.ID() = 0 THEN	(* testing *)
		ASSERT(~stopped);
		stopped := TRUE;
		LocalBroadcast(HandleStop, NIL, {})	(* can not use message as GC not neccessarily ready yet *)
	END;
	AosLocks.ReleaseAll
END StopAll;

PROCEDURE HandleSnapshot(VAR state: AosInterrupts.State; id: LONGINT; msg: Message);
VAR dummy: AosInterrupts.ExceptionState;
BEGIN
	AosTrap.Show(state, dummy, FALSE)	(* must do short dump, because long one chokes on entry/exit code *)
END HandleSnapshot;

(** Produce a snapshot on all processors.  For tracing purposes. *)

PROCEDURE SnapshotAll*;
BEGIN
	HALT(99);	(* currently broken, because AosTrap.Show reschedules (timeslices) *)
	AosLocks.AcquireAll;	(* acquire all locks for tracing in the interrupt handler *)
	LocalBroadcast(HandleSnapshot, NIL, {Self});
	AosLocks.ReleaseAll
END SnapshotAll;
*)

PROCEDURE HandleFlushTLB(id: LONGINT; VAR state: AosInterrupts.State; msg: Message);
CODE {SYSTEM.i386, SYSTEM.Privileged}
	MOV EAX, CR3
	MOV CR3, EAX
END HandleFlushTLB;

(** Flush the TLBs on all processors (multiprocessor-safe). *)

PROCEDURE GlobalFlushTLB*;
BEGIN
	AosLocks.Acquire(AosLocks.AosProcessors);
	LocalBroadcast(HandleFlushTLB, NIL, {Self, FrontBarrier, BackBarrier});
	AosLocks.Release(AosLocks.AosProcessors)
END GlobalFlushTLB;

PROCEDURE HandleFlushCache(id: LONGINT; VAR state: AosInterrupts.State; msg: Message);
CODE {SYSTEM.Pentium, SYSTEM.Privileged}
	WBINVD	; write back and invalidate internal cache and initiate write back and invalidation of external caches
END HandleFlushCache;

(** Flush the caches on all processors (multiprocessor-safe). *)

PROCEDURE GlobalFlushCache*;
BEGIN
	AosLocks.Acquire(AosLocks.AosProcessors);
	LocalBroadcast(HandleFlushCache, NIL, {Self, FrontBarrier, BackBarrier});
	AosLocks.Release(AosLocks.AosProcessors)
END GlobalFlushCache;

PROCEDURE -HLT;
CODE {SYSTEM.i386, SYSTEM.Privileged}
	STI	; (* required according to ACPI 2.0 spec section 8.2.2 *)
	HLT
END HLT;

(* Activate the garbage collector in single-processor mode.  Lock level ALL. *)

PROCEDURE HandleKernelCall(VAR state: AosInterrupts.State);
BEGIN	(* level 0 *)
	IF AosInterrupts.IFBit IN state.EFLAGS THEN
		SYSTEM.STI()	(* re-enable interrupts *)
	END;
	CASE state.EAX OF	(* see KernelCall* *)
		|2:	(* HLT *)
			IF AosInterrupts.IFBit IN state.EFLAGS THEN
				HLT
			END
	END
END HandleKernelCall;

(* Kernel mode upcall to perform global processor halt. *)

PROCEDURE KernelCallHLT;
CODE {SYSTEM.i386}
	MOV EAX, 2
	INT MPKC
END KernelCallHLT;

PROCEDURE HandleGC(id: LONGINT; VAR state: AosInterrupts.State; msg: Message);
BEGIN
	AosMemory.UpdateState;
	AosActive.UpdateState(state); (* ug *)
	AosBoot.Excl(gcBarrier, id);
	WHILE gcBarrier # {} DO AosBoot.SpinHint END;	(* wait for all *)
	IF id = 0 THEN	(* only boot processor performs GC *)
		IF AosActive.snapshotEnabled THEN AosActive.snapshot := NIL END;
		AosHeap.CollectGarbage(AosModules.root);
		AosActive.snapshotEnabled := FALSE;
	END
	(* all other processors wait in barrier after returning *)
END HandleGC;

(** Activate the garbage collector immediately (multiprocessor-safe). *)

PROCEDURE GlobalGC*;
BEGIN
	AosLocks.Acquire(AosLocks.AosProcessors);
	gcBarrier := allProcessors;
	LocalBroadcast(HandleGC, NIL, {Self, BackBarrier});
	AosLocks.Release(AosLocks.AosProcessors);
END GlobalGC;

PROCEDURE HandleGetTimestamp(id: LONGINT; VAR state: AosInterrupts.State; msg: Message);
BEGIN
	time[id] := AosBoot.GetTimer()
END HandleGetTimestamp;

(** Get timestamp on all processors (for testing). *)

PROCEDURE GlobalGetTimestamp*;
VAR t: TimeArray; i: LONGINT; mean, var, n: HUGEINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosProcessors);
	LocalBroadcast(HandleGetTimestamp, NIL, {Self, FrontBarrier});
	LocalBroadcast(HandleGetTimestamp, NIL, {Self, FrontBarrier});
	t := time;
	AosLocks.Release(AosLocks.AosProcessors);
	AosOut.Enter;
	FOR i := 0 TO numProcessors-1 DO AosOut.HIntHex(t[i], 17) END;
	IF numProcessors > 1 THEN
		mean := AosBoot.LIntToHInt(0);
		n := AosBoot.LIntToHInt(numProcessors);
		FOR i := 0 TO numProcessors-1 DO
			mean := AosBoot.AddH(mean, t[i])
		END;
		mean := AosBoot.DivH(mean, n);
		var := AosBoot.LIntToHInt(0);
		FOR i := 0 TO numProcessors-1 DO
			n := AosBoot.SubH(t[i], mean);
			var := AosBoot.AddH(var, AosBoot.MulH(n, n))
		END;
		var := AosBoot.DivH(var, AosBoot.LIntToHInt(numProcessors-1));
		AosOut.String(" mean="); AosOut.HIntHex(mean, 16);
		AosOut.String(" var="); AosOut.HIntHex(var, 16);
		AosOut.String(" var="); AosOut.Int(AosBoot.HIntToLInt(var), 1);
		AosOut.String(" diff:");
		FOR i := 0 TO numProcessors-1 DO
			AosOut.Int(AosBoot.HIntToLInt(AosBoot.SubH(t[i], mean)), 1); AosOut.Char(" ")
		END
	END;
	AosOut.Exit
END GlobalGetTimestamp;

(* Parse processor entry in MP config table. *)

PROCEDURE CPUID1(): LONGINT;
CODE {SYSTEM.i386, SYSTEM.Pentium}
	MOV EAX, 1
	CPUID
	MOV EAX, EBX
END CPUID1;

PROCEDURE ParseProcessor(adr: LONGINT);
VAR id, idx, signature, family, features, ver, log: LONGINT; flags: SET;
BEGIN
	SYSTEM.GET(adr, flags);
	id := ASH(SYSTEM.VAL(LONGINT, flags * {8..15}), -8);
	ver := ASH(SYSTEM.VAL(LONGINT, flags * {16..23}), -16);
	SYSTEM.GET(adr+4, signature);
	family := ASH(signature, -8) MOD 10H;
	SYSTEM.GET(adr+8, features);
	idx := -1;
	IF (family # 0) & (signature MOD 1000H # 0FFFH) & (24 IN flags) & (id < LEN(idMap)) & (idMap[id] = -1) THEN
		IF 25 IN flags THEN idx := 0	(* boot processor *)
		ELSIF numProcessors < maxProcessors THEN idx := numProcessors; INC(numProcessors)
		ELSE (* skip *)
		END
	END;
	IF idx # -1 THEN apicVer[idx] := ver; idMap[id] := SHORT(SHORT(idx)) END;
	AosOut.String("  Processor "); AosOut.Int(id, 1);
	AosOut.String(", APIC"); AosOut.Hex(ver, -3);
	AosOut.String(", ver "); AosOut.Int(family, 1);
	AosOut.Char("."); AosOut.Int(ASH(signature, -4) MOD 10H, 1);
	AosOut.Char("."); AosOut.Int(signature MOD 10H, 1);
	AosOut.String(", features"); AosOut.Hex(features, 9);
	AosOut.String(", ID "); AosOut.Int(idx, 1);
	AosOut.Ln;
	IF AosBoot.HTT IN AosBoot.features THEN
		log := (SYSTEM.LSH(CPUID1(), -16) MOD 256);
		WHILE log > 1 DO
			INC(id); DEC(log);
			IF numProcessors < maxProcessors THEN
				idx := numProcessors; INC(numProcessors);
				apicVer[idx] := ver; idMap[id] := SHORT(SHORT(idx))
			END	
		END
	END
END ParseProcessor;

(* Parse MP configuration table. *)

PROCEDURE ParseMPConfig;
VAR adr, x, i: LONGINT; entries: INTEGER; ch: CHAR; s: SET; str: ARRAY 8 OF CHAR;
BEGIN
	localAPIC := 0; numProcessors := 1; allProcessors := {0};
	FOR i := 0 TO LEN(idMap)-1 DO idMap[i] := -1 END;	(* all unassigned *)
	FOR i := 0 TO AosBoot.MaxCPU-1 DO started[i] := FALSE END;
	adr := AosBoot.configMP;
	AosBoot.GetConfig("MaxProcs", str);
	i := 0; maxProcessors := AosBoot.StrToInt(i, str);
	IF maxProcessors = 0 THEN maxProcessors := AosBoot.MaxCPU END;
	IF (maxProcessors > 0) & (adr > 0) THEN	(* MP config table present, possible multi-processor *)
		AosOut.String("Intel MP Spec "); AosOut.Int(ORD(AosBoot.revMP) DIV 10H + 1, 1);
		AosOut.Char("."); AosOut.Int(ORD(AosBoot.revMP) MOD 10H, 1); AosOut.Ln;
		IF Trace THEN
			IF ODD(ASH(ORD(AosBoot.featureMP[1]), -7)) THEN
				AosOut.String("  PIC mode"); AosOut.Ln
				(* to do: enable SymIO *)
			ELSE
				AosOut.String("  Virtual wire mode"); AosOut.Ln
			END
		END;
		IF AosBoot.featureMP[0] # 0X THEN	(* pre-defined configuration *)
			AosOut.String("  Default config "); AosOut.Int(ORD(AosBoot.featureMP[0]), 1); AosOut.Ln;
			localAPIC := 0FEE00000H;
			apicVer[0] := 0; apicVer[1] := 0
		ELSE	(* configuration defined in table *)
			AosMemory.MapPhysical(adr, 68*1024, adr);	(* 64K + 4K header *)
			SYSTEM.GET(adr, x); ASSERT(x = 504D4350H);	(* check signature *)
			SYSTEM.GET(adr+4, x);	(* length *)
			ASSERT(AosBoot.ChecksumMP(adr, x MOD 10000H) = 0);
			IF Trace THEN
				AosOut.String("  ID: ");
				FOR x := adr+8 TO adr+27 DO
					SYSTEM.GET(x, ch); AosOut.Char(ch);
					IF x = adr+15 THEN AosOut.Char(" ") END
				END;
				AosOut.Ln
			END;
			SYSTEM.GET(adr+36, localAPIC);
			IF Trace THEN AosOut.String("  Local APIC:"); AosOut.Hex(localAPIC, 9); AosOut.Ln END;
			SYSTEM.GET(adr+34, entries);
			INC(adr, 44);	(* skip header *)
			WHILE entries > 0 DO
				SYSTEM.GET(adr, ch);	(* type *)
				CASE ORD(ch) OF
					0:	(* processor *)
						ParseProcessor(adr);
						INC(adr, 20)
					|1:	(* bus *)
						IF Trace THEN
							SYSTEM.GET(adr+1, ch);
							AosOut.String("  Bus "); AosOut.Int(ORD(ch), 1); AosOut.String(": ");
							FOR x := adr+2 TO adr+7 DO SYSTEM.GET(x, ch); AosOut.Char(ch) END;
							AosOut.Ln
						END;
						INC(adr, 8)
					|2:	(* IO APIC *)
						IF Trace THEN
							SYSTEM.GET(adr+1, ch); AosOut.String("  IO APIC ID:"); AosOut.Hex(ORD(ch), -3);
							SYSTEM.GET(adr+2, ch); AosOut.String(", version "); AosOut.Int(ORD(ch), 1);
							SYSTEM.GET(adr, s); IF ~(24 IN s) THEN AosOut.String(" (disabled)") END;
							AosOut.Ln
						END;
						INC(adr, 8)
					|3:	(* IO interrupt assignment *)
						INC(adr, 8)
					|4:	(* Local interrupt assignment *)
						INC(adr, 8)
				END;	(* CASE *)
				DEC(entries)
			END
		END
	END;
	IF localAPIC = 0 THEN	(* single processor *)
		AosOut.String("Single-processor"); AosOut.Ln;
		apicVer[0] := 0
	END;
	started[0] := TRUE;
	FOR i := 0 TO AosBoot.MaxCPU-1 DO revIDmap[i] := -1 END;
	FOR i := 0 TO LEN(idMap)-1 DO
		x := idMap[i];
		IF x # -1 THEN
			ASSERT(revIDmap[x] = -1);	(* no duplicate APIC ids *)
			revIDmap[x] := SHORT(SHORT(i))
		END
	END;
		(* timer configuration *)
	AosBoot.GetConfig("TimerRate", str);
	i := 0; timerRate := AosBoot.StrToInt(i, str);
	IF timerRate = 0 THEN timerRate := 1000 END;
	IF TraceProcessor THEN
		AosBoot.GetConfig("TraceProc", str);
		i := 0; traceProcessor := AosBoot.StrToInt(i, str) # 0
	END
END ParseMPConfig;

(* Return the current average measured bus clock speed in Hz. *)

PROCEDURE GetBusClockRate(): LONGINT;
VAR timer: LONGINT; t: LONGINT;
BEGIN
	t := AosActive.ticks;
	REPEAT UNTIL AosActive.ticks # t;	(* wait for edge *)
	timer := AosActive.ticks + ClockRateDelay;
	ApicPut(380H, SYSTEM.VAL(SET, MAX(LONGINT)));	(* initial count *)
	REPEAT UNTIL timer - AosActive.ticks <= 0;
	t := MAX(LONGINT) - SYSTEM.VAL(LONGINT, ApicGet(390H));	(* current count *)
	IF t <= MAX(LONGINT) DIV 1000 THEN
		RETURN 1000 * t DIV ClockRateDelay
	ELSE
		RETURN t DIV ClockRateDelay * 1000
	END
END GetBusClockRate;

(* Initialize APIC timer for timeslicing. *)

PROCEDURE InitMPTimer;
VAR rate: LONGINT;
BEGIN
	IF timerRate > 0 THEN
		ApicPut(3E0H, {0,1,3});	(* divide by 1 *)
		ApicPut(320H, {16} + SYSTEM.VAL(SET, AosInterrupts.MPTMR));	(* masked, one-shot *)
		rate := GetBusClockRate();
		busHz0[AosBoot.ID()] := rate;
		rate := (rate+500000) DIV 1000000 * 1000000;	(* round to nearest MHz *)
		busHz1[AosBoot.ID()] := rate;
		ApicPut(320H, {17} + SYSTEM.VAL(SET, AosInterrupts.MPTMR));	(* unmasked, periodic *)
		ApicPut(380H, SYSTEM.VAL(SET, rate DIV timerRate))	(* initial count *)
	END
END InitMPTimer;

(* Handle multiprocessor timer interrupt. *)

PROCEDURE HandleMPTimer(VAR state: AosInterrupts.State);
BEGIN (* {interrupts off} *)
	timer(AosBoot.ID(), state);
	ApicPut(0B0H, {});	(* EOI *)
	SYSTEM.STI();	(* enable interrupts before acquiring locks below - to avoid deadlock with StopAll. *)
	AosActive.Timeslice(state)	(* fixme: check recursive interrupt *)
END HandleMPTimer;

(* Handle uniprocessor timer interrupt. *)

PROCEDURE HandleUPTimer(VAR state: AosInterrupts.State);
BEGIN (* {interrupts off} *)
	timer(0, state);
	SYSTEM.STI();	(* enable interrupts before acquiring locks below - to avoid deadlock with StopAll. *)
	AosActive.Timeslice(state)
END HandleUPTimer;

PROCEDURE DummyEvent(id: LONGINT; VAR state: AosInterrupts.State);
END DummyEvent;

(** Install a processor timer event handler. *)

PROCEDURE InstallHandler*(h: EventHandler);
BEGIN
	IF h # NIL THEN timer := h ELSE timer := DummyEvent END
END InstallHandler;

(* Initialize APIC for current processor. *)

PROCEDURE InitAPIC;
BEGIN
		(* enable APIC, set focus checking & set spurious interrupt handler *)
	ASSERT(AosInterrupts.MPSPU MOD 16 = 15);	(* low 4 bits set, p. 7-29 *)
	ApicPut(0F0H, {8} + SYSTEM.VAL(SET, AosInterrupts.MPSPU));
		(* set error interrupt handler *)
	ApicPut(370H, SYSTEM.VAL(SET, AosInterrupts.MPERR));
	InitMPTimer
END InitAPIC;

(* Start processor activity. *)

PROCEDURE StartMP;
VAR id: LONGINT; state: AosInterrupts.State;
BEGIN	(* running at kernel level with interrupts on *)
	InitAPIC;
	id := AosBoot.ID();	(* timeslicing is disabled, as we are running at kernel level *)
	AosOut.String(", P"); AosOut.Int(id, 1); AosOut.String(" running");
	IF TraceProcessor & traceProcessor & (id = numProcessors-1) THEN
		DEC(numProcessors)	(* exclude from rest of activity *)
	ELSE
		INCL(allProcessors, id)
	END;
		(* synchronize with boot processor - end of mutual exclusion *)
	started[id] := TRUE;
	IF TraceProcessor & ~(id IN allProcessors) THEN
		AosOut.Enter; AosOut.String("tracing"); AosOut.Exit;
		LOOP
			IF traceProcessorProc # NIL THEN traceProcessorProc(id, state) END;
			AosBoot.SpinHint
		END
	END;
		(* wait until woken up *)
	WHILE stopped DO AosBoot.SpinHint END;
		(* now fully functional, including storage allocation *)
	AosBoot.Excl(ipcBusy, id);	(* ack *)
	AosOut.Enter; AosOut.String("scheduling"); AosOut.Exit;
	ASSERT(id = AosBoot.ID());	(* still running on same processor *)
	AosActive.Start	(* start running processes *)
END StartMP;

(* Subsequent processors start executing here. *)

PROCEDURE EnterMP;
(* no local variables allowed, because stack is switched. *)
BEGIN	(* running at kernel level with interrupts off *)
	AosBoot.InitProcessor;
	AosMemory.InitMemory;	(* switch stack *)
	AosInterrupts.Start;
	StartMP
END EnterMP;

(* Start another processor. *)

PROCEDURE StartProcessor(phys, apicid: LONGINT; startup: BOOLEAN);
VAR j, k: LONGINT; s: SET; timer: LONGINT;
BEGIN
		(* clear APIC errors *)
	ApicPut(280H, {}); s := ApicGet(280H);
		(* assert INIT *)
	ApicPut(310H, SYSTEM.VAL(SET, ASH(apicid, 24)));	(* set destination *)
	ApicPut(300H, {8, 10, 14, 15});	(* set Dest, INIT, Phys, Assert, Level *)
	timer := AosActive.ticks + 5;		(* > 200us *)
	REPEAT UNTIL timer - AosActive.ticks <= 0;
		(* deassert INIT *)
	ApicPut(310H, SYSTEM.VAL(SET, ASH(apicid, 24)));	(* set destination *)
	ApicPut(300H, {8, 10, 15});	(* set Dest, INIT, Deassert, Phys, Level *)
	IF startup THEN	(* send STARTUP if required *)
		j := 0; k := 2;
		WHILE j # k DO
			ApicPut(280H, {});
			ApicPut(310H, SYSTEM.VAL(SET, ASH(apicid, 24)));	(* set destination *)
				(* set Dest, Startup, Deassert, Phys, Edge *)
			ApicPut(300H, {9, 10} + SYSTEM.VAL(SET, phys DIV 4096 MOD 256));
			timer := AosActive.ticks + 10;	(* ~10ms *)
			REPEAT UNTIL timer - AosActive.ticks <= 0;
			IF ~(12 IN ApicGet(300H)) THEN	(* idle *)
				IF ApicGet(280H) * {0..3, 5..7} = {} THEN k := j	(* ESR success, exit *)
				ELSE INC(j)	(* retry *)
				END
			ELSE INC(j)	(* retry *)
			END
		END
	END
END StartProcessor;

(* Boot other processors, one at a time. *)

PROCEDURE BootMP;
VAR phys, i, page0Adr: LONGINT; timer: LONGINT;
BEGIN
	stopped := TRUE; ipcBusy := {};	(* other processors can be woken with StartAll *)
	AosMemory.InitBootPage(EnterMP, phys);
	AosMemory.MapPhysical(0, 4096, page0Adr);	(* map in BIOS data area *)
	FOR i := 1 TO numProcessors-1 DO
			(* set up booting for old processor types that reset on INIT & don't understand STARTUP *)
		SYSTEM.PUT(page0Adr + 467H, ASH(phys, 16-4));
		AosBoot.PutNVByte(15, 0AX);	(* shutdown status byte *)
			(* attempt to start another processor *)
		AosOut.String("P0 starting P"); AosOut.Int(i, 1);
		StartProcessor(phys, revIDmap[i], apicVer[i] >= 10H);	(* try booting processor i *)
			(* wait for CPU to become active *)
		timer := AosActive.ticks + 5000;	(* ~5s timeout *)
		REPEAT AosBoot.SpinHint UNTIL started[i] OR (timer - AosActive.ticks <= 0);
			(* end of mutual exclusion *)
		IF started[i] THEN
			AosOut.String(", P0 recognized P"); AosOut.Int(i, 1)
		ELSE
			AosOut.String(", P0 timeout on P"); AosOut.Int(i, 1)
		END;
		AosOut.Ln
	END;
	SYSTEM.PUT(page0Adr + 467H, SYSTEM.VAL(LONGINT, 0));
	AosMemory.UnmapPhysical(page0Adr, 4096);
	AosBoot.PutNVByte(15, 0X)	(* restore shutdown status *)
END BootMP;

(* Timer interrupt handler. *)

PROCEDURE InterruptHandler(VAR state: AosInterrupts.State);
BEGIN
	INC(AosActive.ticks);
	DEC(eventCount);
	IF eventCount = 0 THEN
		eventCount := eventMax; event(state)
	END
(*
CODE {SYSTEM.i386}
	INC ticks
	DEC eventCount
	JNZ exit
	MOV EAX, eventMax
	MOV eventCount, EAX
	PUSH 12[EBP]	; TAG(state) (assembler can not compute state+4)
	PUSH state[EBP]	; ADR(state)
	CALL event
exit:
*)
END InterruptHandler;

(* Delay for IO *)

PROCEDURE -Wait;
CODE {SYSTEM.i386}
	JMP 0
	JMP 0
	JMP 0
END Wait;

PROCEDURE Dummy(VAR state: AosInterrupts.State);
END Dummy;

PROCEDURE InitTicks;
CONST Div = (2*TimerClock + AosActive.Second) DIV (2*AosActive.Second);	(* timer clock divisor *)
BEGIN
	eventCount := 0; eventMax := 0; event := Dummy;
		(* initialize timer hardware *)
	ASSERT(Div <= 65535);
	SYSTEM.PORTOUT(43H, 34X);  Wait;	(* mode 2, rate generator *)
	SYSTEM.PORTOUT(40H, CHR(Div MOD 100H));  Wait;
	SYSTEM.PORTOUT(40H, CHR(ASH(Div, -8)));
	AosInterrupts.InstallHandler(InterruptHandler, AosInterrupts.IRQ0)
END InitTicks;

(* Set timer upcall.  The handler procedure will be called at a rate of Second/divisor Hz. *)

PROCEDURE InstallTickHandler(handler: AosInterrupts.Handler; divisor: LONGINT);
BEGIN
	eventMax := divisor; event := handler;
	eventCount := eventMax
END InstallTickHandler;

BEGIN
	IF AosBoot.Trace THEN
		AosOut.Enter; AosOut.String("AosProcessors"); AosOut.Exit
	END;
	traceProcessor := FALSE; traceProcessorProc := NIL;
	ASSERT(AosActive.Second = 1000);	(* use of AosActive.ticks *)
	InitTicks;
	timer := DummyEvent;
	ParseMPConfig;
	AosInterrupts.InstallHandler(HandleIPC, AosInterrupts.MPIPCLocal);
	IF localAPIC # 0 THEN	(* APIC present *)
		AosMemory.InitAPICArea(localAPIC, 4096);
		AosBoot.InitAPICIDAdr(localAPIC+20H, idMap);
		ASSERT(AosInterrupts.MPSPU MOD 16 = 15);	(* use default handler (see 7.4.11.1) *)
		AosInterrupts.InstallHandler(HandleError, AosInterrupts.MPERR);
		AosInterrupts.InstallHandler(HandleMPTimer, AosInterrupts.MPTMR);
		AosInterrupts.InstallHandler(HandleIPC, AosInterrupts.MPIPC);
		InitAPIC;
		IF numProcessors > 1 THEN BootMP END
	ELSE
		IF timerRate > 0 THEN
			InstallTickHandler(HandleUPTimer, AosActive.Second DIV timerRate)
		END
	END;
	AosInterrupts.InstallHandler(HandleKernelCall, MPKC);
	AosMemory.GlobalFlushTLB := GlobalFlushTLB;
	AosHeap.GC := GlobalGC;	(* must be done before starting other processors *)
	IF numProcessors > 1 THEN StartAll
	ELSE AosActive.ProcessorHLT := KernelCallHLT	(* enable waiting for interrupt when idle *)
	END
END AosProcessors.

(*
Note to old version using physOfs:
Booting other processors must be carefully coordinated, because the new processors starting up share memory with the main processor, but in the beginning paging is not yet enabled on these new processors.  Therefore we only boot one processor at a time, and that processor is allowed to modify AosBoot.physOfs to reflect its own memory state.  The processor ID code in AosProcessor also has to be planned carefully to work for the BP and AP in this case.
*)

(*
to do:
o direct cause/effect between AosHeap finalizer list and Finalizer active object here
*)

(*
04.03.1998	pjm	First version
05.05.1998	pjm	Handle error and spurious interrupts
23.06.1999	pjm	NMI is really non-maskable (e.g. interrupted in HandleIPC with IT=00)
30.06.1999	pjm	Moved processor ID stuff to AosProcessor and simplified
18.05.2000	pjm	Added Snapshot
14.09.2000	pjm	Removed Timeout
15.09.2000	pjm	MaxProcs=1 works on multiprocessors, set negative to simulate uniprocessor
20.09.2000	pjm	IpcCache
30.01.2001	pjm	Fixes for >2 processors
*)

(*
MPIPCSelf
*)
