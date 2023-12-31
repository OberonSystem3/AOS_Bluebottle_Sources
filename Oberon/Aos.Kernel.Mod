(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE Kernel;
(** AUTHOR "pjm"; PURPOSE "Oberon for Aos kernel"; *)

IMPORT SYSTEM, AosBoot, AosOut, AosInterrupts, AosActive, AosKernel, AosTrap, AosClock;

CONST
	LittleEndian* = TRUE;	(** byte order of basic types *)
	LsbIs0* = TRUE;	(** bit order of SET type *)

(*
CONST
		(* timer *)
	TimeUnit* = AosKernel.Second;	(* timer ticks per second, returned by GetTimer *)	(* not a constant! *)
*)

TYPE
	(*Name* = AosModules.Name;	(* module name *)
	Proc* = AosModules.TerminationHandler;
	Cmd* = AosModules.Command;
	Module* = AosModules.Module;	(* module descriptor *)
	ModuleDesc* = AosModules.ModuleDesc;*)

	(*TrapHandler* = PROCEDURE (err, fp, pc, pf: LONGINT);*)

	Finalizer* = PROCEDURE (obj: SYSTEM.PTR);
	
	(*MilliTimer* = AosKernel.MilliTimer;*)

	OberonFinalizer = OBJECT
		VAR fin: Finalizer; next: OberonFinalizer; obj: SYSTEM.PTR;
		
		PROCEDURE Finalize(obj: SYSTEM.PTR);
		BEGIN	(* assume only one finalization thread, so don't need to protect globals here *)
			DEC(NfinalizeAlive); INC(NfinalizeDead);
			SELF.obj := obj;	(* anchor object *)
			next := finalizeRoot; finalizeRoot := SELF	(* add to list, to be called by Oberon *)
		END Finalize;
	
	END OberonFinalizer;

VAR
		(* exported variables *)
	version*: ARRAY 32 OF CHAR;
	(*break* : BOOLEAN;*)	(** has ctrl-break been pressed? *)	(* for Input *)
	(*inGC*: BOOLEAN;*)	(* executing inside GC? *)	(* for Input *)
	(*copro*: BOOLEAN;*)	(* is a coprocessor present? *)	(* for Reals *)
	(*modules* : AosModules.Module;*)	(** fake list of modules *)	(* for Compiler *)
	(*shutdown*: LONGINT;*)
(*
	(*StackOrg* : LONGINT;*)	(** highest address on stack (single-process system) *)
	(*bt*: LONGINT;*)	(** boot table *)
	(*tspeed*: LONGINT;*)	(** =0: no tracing, >0: tspeed = speed of com output, <0: -tspeed = screen segment *)
	(*tbase*: INTEGER;*)	(** trace base port, 3F8H=com1, 2F8H=com2, etc. *)
	(*EnableGC*, DisableGC*: Proc;*)	(** Enable or Disable the GC *)
	(*timer*: Proc;*)	(** for internal use *)
	(*runtime*: ARRAY 5 OF LONGINT;*)	(** for internal use *)
*)
	lockedBy: PTR;
	level: LONGINT;
	oberon: PTR;
	finalizeRoot: OberonFinalizer;	(* finalizers that have to be executed by Oberon *)
	NfinalizeAlive, NfinalizeDead: LONGINT;
	finalizers: AosKernel.FinalizedCollection;	(* collection for all Oberon finalizers *)

(** -- Low-level tracing support -- *)

(** WriteChar - Write a character to the trace output *)

PROCEDURE WriteChar*(c: CHAR);
BEGIN
	AosOut.Char(c)
END WriteChar;

(** WriteString - Write a string *)

PROCEDURE WriteString*(s: ARRAY OF CHAR);
BEGIN
	AosOut.String(s)
END WriteString;

(** WriteLn - Skip to the next line on trace output *)

PROCEDURE WriteLn*;
BEGIN
	AosOut.Ln
END WriteLn;

(** WriteInt - Write "x" as a decimal number.  "w" is the field width. *)

PROCEDURE WriteInt*(x, w: LONGINT);
BEGIN
	AosOut.Int(x, w)
END WriteInt;

(** WriteHex - Write "x" as a hexadecimal number. The absolute value of "w" is the field width.  If "w" is negative, two hex digits are printed (x MOD 100H), otherwise 8 digits are printed. *)

PROCEDURE WriteHex*(x, w: LONGINT);
BEGIN
	AosOut.Hex(x, w)
END WriteHex;

(** WriteMemory - Display a block of memory. *)

PROCEDURE WriteMemory*(adr, size: LONGINT);
BEGIN
	AosOut.Memory(adr, size)
END WriteMemory;

(* -- Trap handling -- *)

(*(** GetMod - Return the loaded module that contains code address pc. *)

PROCEDURE GetMod*(pc : LONGINT): Module;
BEGIN
	RETURN AosModules.ModuleByAdr(pc)
END GetMod;*)

(*(** InstallTrap - Install the trap handler *)

PROCEDURE InstallTrap*(p: TrapHandler);
BEGIN
	handler := p
END InstallTrap;*)

(*(** InstallLoop - Install procedure to which control is transferred after a trap *)

PROCEDURE InstallLoop*(p: Proc);
BEGIN
	loop := p
END InstallLoop;*)

(*(** -- Interrupt handling -- *)*)

(*(** InstallIP - Install interrupt handler & enable IRQ if necessary.
	"p" must be defined as a normal "PROCEDURE p;".  On entry to p interrupts
	are disabled and may be enabled with SYSTEM.STI().  At exit from p the
	state of interrupts are restored.  The acknowledgement of a hardware interrupt 
	is done by the Kernel.  No end-of-interrupt has to be signalled explicitly in 
	procedure p.  IRQs are mapped starting at interrupt Kernel.IRQ.

	At entry to procedure p the stack is as follows:
		56	EFLAGS''
		52	CS''
		48	EIP''	(IRETD from glue code)
		44	errorcode
		40	intnum	<-- ESP'
		36	EAX
		32	ECX
		28	EDX
		24	EBX
		20	ESP'
		16	EBP
		12	ESI
		08	EDI
		04	EIP'	(RET from p)
		00	EBP'	<-- EBP
		xx	locals	<-- ESP

	Interrupt priorities (highest to lowest):
	
	IRQ	Common use
	00	Timer
	01	Keyboard
	08	RT clock
	09	EGA/VGA retrace
	10	Ethernet or other card
	11	card
	12	PS/2 mouse or card
	13	DMA/copro
	14	Hard disk
	15	card or IRQ error
	03	COM2/4
	04	COM1/3
	05	card
	06	Diskette
	07	LPT1 or IRQ error
*)

PROCEDURE InstallIP*(p: Proc;  i: INTEGER);
BEGIN
END InstallIP;*)

(*(** RemoveIP - Uninstall interrupt handler & disable IRQ if necessary *)

PROCEDURE RemoveIP*(p: Proc;  i: INTEGER);
BEGIN
END RemoveIP;*)

(** -- Memory/Object management -- *)

(*
(** Available - Return the size in bytes of the remaining free heap space *)

PROCEDURE Available*(): LONGINT;
BEGIN
	RETURN 0
END Available;

(** LargestAvailable - Return the size in bytes of the largest free available memory block. 
Allocating objects with a size greater than this size will cause the memory allocation to fail. *) 

PROCEDURE LargestAvailable*(): LONGINT;
BEGIN
	RETURN 0
END LargestAvailable;
*)

(** Used - Return the size in bytes of the amount of memory currently in use in the heap (not implemented on Aos). *) 

PROCEDURE Used*(): LONGINT;
BEGIN
	RETURN 0
END Used;

(** GC - Immediately activate the garbage collector (on Aos, call the Oberon-based finalizers). *)

PROCEDURE GC*;
VAR of: OberonFinalizer;
BEGIN
	CheckOberonLock;	(* must hold Oberon lock *)
	WHILE finalizeRoot # NIL DO
		of := finalizeRoot; finalizeRoot := of.next; DEC(NfinalizeDead);
		of.fin(of.obj)	(* call Oberon finalizer *)
	END
END GC;

(*(** NewDMA - Allocate memory correctly aligned for byte or word DMA in device drivers.
"adr" returns the virtual and "phys" the physical address of the memory.  To deallocate,
call with size = -(size of block) and adr = virtual address of block.  Max size=64k. *)

PROCEDURE NewDMA*(size: LONGINT;  VAR adr, phys: LONGINT);
BEGIN
END NewDMA;*)

(*
(** MapPhysical - Map a physical memory area into the virtual address space. {physAdr, size MOD PS = 0} *)

PROCEDURE MapPhysical*(physAdr, size: LONGINT;  VAR virtAdr: LONGINT);
BEGIN
	AosMemory.MapPhysical(physAdr, size, virtAdr)
END MapPhysical;
*)

(*
(** DisableTracing - Disable the GC tracing of a record field of the specified type.  For internal use only. *)

PROCEDURE DisableTracing*(recadr, fldadr: LONGINT);
BEGIN
	(*AosOut.String("DisableTracing");  AosOut.Hex(recadr, 9);  AosOut.Hex(fldadr, 9);
	AosOut.Ln*)
END DisableTracing;
*)

(** RegisterObject - Register a record for finalization.  basic = FALSE *)

PROCEDURE RegisterObject*(obj: SYSTEM.PTR; fin: Finalizer; basic: BOOLEAN);
VAR of: OberonFinalizer;
BEGIN
	NEW(of); of.fin := fin; INC(NfinalizeAlive);
	finalizers.Add(obj, of.Finalize);
		(* when obj unreachable, Aos GC calls of.Finalizer, which will enqueue obj for calling by GC in this module, which is called by Oberon.Collect and periodically by the Oberon loop *)
END RegisterObject;

(*
(** InstallTermHandler - Install a procedure to execute when a module is freed.  Normally used to uninstall
interrupt handlers or tasks and perform other cleanup duties. *)

PROCEDURE InstallTermHandler* (h: AosModules.TerminationHandler);
BEGIN
	AosModules.InstallTermHandler(h)
END InstallTermHandler;
*)

(** -- Clock/Timer -- *)

(** GetClock - Return current time and date *)

PROCEDURE GetClock*(VAR time, date: LONGINT);
BEGIN
	AosClock.Get(time, date)
END GetClock;

(** SetClock - Set current time and date *)

PROCEDURE SetClock*(time, date: LONGINT);
BEGIN
	AosClock.Set(time, date)
END SetClock;

(*
(** GetTimer - Return "ticks" since initialisation (Kernel.TimeUnit ticks per second) *)

PROCEDURE GetTimer*(): LONGINT;
BEGIN
	RETURN AosKernel.GetTimer()
END GetTimer;

(** SetTimer - Set timer to expire in approximately "ms" milliseconds. *)
PROCEDURE SetTimer*(VAR t: MilliTimer;  ms: LONGINT);
BEGIN
	AosKernel.SetTimer(t, ms)
END SetTimer;

(** Expired - Test if a timer has expired.  Interrupts must be on. *)
PROCEDURE Expired*(VAR t: MilliTimer): BOOLEAN;
BEGIN
	RETURN AosKernel.Expired(t)
END Expired;
*)

(** -- Miscellaneous -- *)

(** GetConfig - Return value of configuration string.  Returns empty val if name not found. *)

PROCEDURE GetConfig*(name: ARRAY OF CHAR;  VAR val: ARRAY OF CHAR);
BEGIN
	AosBoot.GetConfig(name, val)
END GetConfig;

(*
(* ------------------------------------------------------------------------------------------------*)
(* Shutdown - Terminate Oberon after executing all module terminators.  If code = 1, perform an APM power-down, if code = 2, perform a soft reboot, or else just switch off interrupts and loop endlessly. *)

PROCEDURE Shutdown*(code: LONGINT);
BEGIN
	shutdown := code;
	AosModules.Shutdown(code)
END Shutdown;
*)

(*
(** Idle - Called when system is idle. *)

PROCEDURE Idle*(code: LONGINT);	(* code currently unused *)
BEGIN
	AosActive.Yield
END Idle;
*)

PROCEDURE TerminateInLock;
BEGIN
	BEGIN {EXCLUSIVE}
		IF lockedBy = AosActive.ActiveObject() THEN	(* if we held it, release the lock *)
			lockedBy := NIL; level := 0	(* allow Oberon.Loop to re-acquire lock *)
		END
	END;
	AosActive.Terminate	(* fixme: should really call CurrentProcess().restartEIP *)
END TerminateInLock;

(* Handle exception that occurred while holding Oberon lock. *)

PROCEDURE ExceptionInLock(p: AosActive.Process; VAR int: AosInterrupts.State; VAR exc: AosInterrupts.ExceptionState; VAR return: BOOLEAN);
VAR proc: PROCEDURE;
BEGIN
	IF p.obj # oberon THEN	(* similar to AosTrap.Exception *)
		AosTrap.Show(p, int, exc, TRUE);
		INCL(int.EFLAGS, AosInterrupts.IFBit);	(* enable interrupts on return *)
		int.EBP := 0; int.ESP := p.restartSP;	(* reset stack *)
		proc := TerminateInLock; int.EIP := SYSTEM.VAL(LONGINT, proc);	(* terminate *)
		return := TRUE	(* return to TerminateInLock procedure at user level *)
	ELSE
		lockedBy := NIL; level := 0	(* Oberon.Loop will re-acquire lock *)
	END
END ExceptionInLock;

(** Acquire the Oberon lock (and replace exception handler). *)

PROCEDURE LockOberon*;
VAR me: PTR;
BEGIN {EXCLUSIVE}
	me := AosActive.ActiveObject();
	IF lockedBy = me THEN
		ASSERT(level # -1);	(* overflow *)
		INC(level)
	ELSE
		AWAIT(lockedBy = NIL);
		lockedBy := me; level := 1;
		AosActive.SetExceptionHandler(ExceptionInLock)	(* assume no other exception handler is present *)
	END
END LockOberon;

(** Release the Oberon lock (and remove exception handler). *)

PROCEDURE UnlockOberon*;
BEGIN {EXCLUSIVE}
	ASSERT(lockedBy = AosActive.ActiveObject());	(* must hold lock *)
	DEC(level);
	IF level = 0 THEN
		AosActive.SetExceptionHandler(NIL);
		lockedBy := NIL
	END
END UnlockOberon;

(** Check if the oberon lock is held by the current process. *)

PROCEDURE CheckOberonLock*;
VAR me: PTR; ok: BOOLEAN;
BEGIN
	BEGIN {EXCLUSIVE}
		me := AosActive.ActiveObject();
		ok := (me = oberon) OR (lockedBy = me);
	END;
	IF ~ok THEN (* HALT(MAX(INTEGER)+1) *) 
		AosOut.String("Oberon has been called before from an outside process. Don't do that!"); AosOut.Ln;
	END	(* to do: halt here *)
END CheckOberonLock;

BEGIN
	oberon := AosActive.ActiveObject();
	lockedBy := NIL; level := 0; finalizeRoot := NIL; NEW(finalizers);
	COPY(AosBoot.version, version);
	(*shutdown := 0;*)
	AosOut.Enter; WriteString("ETH Oberon / ");  WriteString(version); AosOut.Exit;
	(*AosScope.Init;*)
	(*modules := NIL;*)
	(*break := FALSE;  inGC := TRUE;*)	(* set inGC = TRUE to disable hard break *)
	(*copro := TRUE;*)
END Kernel.

(*
28.04.98	pjm	First version
*)
