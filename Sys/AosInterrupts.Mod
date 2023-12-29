(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosInterrupts; (** AUTHOR "pjm"; PURPOSE "Low-level interrupt handling"; *)

IMPORT SYSTEM, AosBoot, AosLocks, AosOut, AosHeap(*NEW*);

CONST
		(** pre-defined interrupts 0-31, used with InstallHandler *)
	DE* = 0;  DB* = 1;  NMI* = 2;  BP* = 3;  OVF* = 4;  BR* = 5;  UD* = 6;  NM* = 7;
	DF* = 8;  TS* = 10;  NP* = 11;  SSF* = 12;  GP* = 13;  PF* = 14;  MF*= 16;  AC*= 17;  MC* = 18;
	
	IRQ0* = 32;  IRQ15 = 47;	(* {IRQ0 MOD 8 = 0} *)
	IRQ2 = IRQ0+2;  IRQ7 = IRQ0+7;  IRQ8 = IRQ0+8;
	MaxIRQ* = IRQ15;	(** hardware interrupt numbers *)
	
	MPKC* = 49;	(** SMP: kernel call *)
	SoftInt* = 58;	(** temporary software interrupt *)
	MPIPCLocal* = 59;	(** SMP: local interprocessor interrupt *)
	MPTMR* = 60;	(** SMP: timer interrupt *)
	MPIPC* = 61;	(** SMP: interprocessor interrupt *)
	MPERR* = 62;	(** SMP: error interrupt *)
	MPSPU* = 63;	(** SMP: spurious interrupt {MOD 16 = 15} *)

	IDTSize = 64;
	
	TraceSpurious = FALSE;	(* print a message on spurious hardware interrupts *)
	HandleSpurious = TRUE OR TraceSpurious;	(* do not trap on spurious interrupts *)
	
	IntA0 = 020H;	IntA1 = 021H;	(* Interrupt Controller 1 *)
	IntB0 = 0A0H;	IntB1 = 0A1H;	(* Interrupt Controller 2 *)

		(* memory management *)
	KernelCodeSel = 1*8;	(* selector 1 in gdt, RPL 0 *)
	UserCodeSel = 3*8 + 3;	(* selector 3 in gdt, RPL 3 *)
	
		(** EFLAGS bits *)
	IFBit* = 9; VMBit* = 17;

	KernelLevel* = 0;  UserLevel* = 3;	(** CS MOD 4 *)

TYPE
		(** processor state *)
	State* = RECORD	(* offsets used in FieldInterrupt, FieldIRQ and AosActive.RestoreState *)
		EDI*, ESI*, ERR*, ESP0*, EBX*, EDX*, ECX*, EAX*: LONGINT;	(** ESP0 = ADR(s.INT) *)
		INT*, EBP*, EIP*, CS*: LONGINT;	(* EBP and ERR are exchanged by glue code, for procedure link *)
		EFLAGS*: SET;
		ESP*, SS*: LONGINT;	(** only valid if (VMBit IN s.EFLAGS) OR (CS() MOD 4 < s.CS MOD 4) *)
		ES*, DS*, FS*, GS*: LONGINT;	(** only valid if (VMBit IN s.EFLAGS) *)
	END;
	
		(** exception state *)
	ExceptionState* = RECORD
		halt*: LONGINT;	(** halt code *)
		pf*: LONGINT;	(** page fault address *)
		locks*: SET;	(** active locks *)
		ESP*: LONGINT;	(** actual ESP value at time of interrupt *)
		SS*, ES*, DS*, FS*, GS*: LONGINT;	(** segment registers *)
		CR*: ARRAY 5 OF LONGINT;	(** control registers *)
		DR*: ARRAY 8 OF LONGINT;	(** debug registers *)
		FPU*: ARRAY 7 OF SET	(** floating-point state *)
	END;

	Handler* = PROCEDURE {DELEGATE} (VAR state: State);
	HandlerList = POINTER TO RECORD	(* offsets used in FieldInterrupt *)
		next: HandlerList;	(* offset 0 *)
		handler: Handler	(* offset 4 *)
	END;
	
	GateDescriptor = RECORD
		offsetBits0to15: INTEGER;
		selector: INTEGER;
		gateType: INTEGER;
		offsetBits16to31: INTEGER
	END;
	IDT = ARRAY IDTSize OF GateDescriptor;

VAR
	idt: IDT;	(* interrupt descriptor table *)
	glue: ARRAY IDTSize OF ARRAY 15 OF CHAR;	(* code *)
	intHandler: ARRAY IDTSize OF HandlerList;
	stateTag: LONGINT;
	default: HandlerList;

(*
	traceInterruptIn*, traceInterruptOut*: PROCEDURE (int: LONGINT);
*)
	
(* Unexpected - Default interrupt handler *)

PROCEDURE Unexpected(VAR state: State);
VAR int: LONGINT;  isr, irr: CHAR;
BEGIN
	int := state.INT;
	IF HandleSpurious & ((int >= IRQ0) & (int <= MaxIRQ) OR (int = MPSPU)) THEN	(* unexpected IRQ, get more info *)
		IF (int >= IRQ8) & (int <= IRQ15) THEN
			SYSTEM.PORTOUT(IntB0, 0BX);  SYSTEM.PORTIN(IntB0, isr);
			SYSTEM.PORTOUT(IntB0, 0AX);  SYSTEM.PORTIN(IntB0, irr)
		ELSIF (int >= IRQ0) & (int <= IRQ7) THEN
			SYSTEM.PORTOUT(IntA0, 0BX);  SYSTEM.PORTIN(IntA0, isr);
			SYSTEM.PORTOUT(IntA0, 0AX);  SYSTEM.PORTIN(IntA0, irr)
		ELSE
			isr := 0X;  irr := 0X
		END;
		IF TraceSpurious THEN
			AosOut.Enter; AosOut.String("INT"); AosOut.Int(int, 1);
			AosOut.Hex(ORD(isr), -3); AosOut.Hex(ORD(irr), -2); AosOut.Exit
		END
	ELSE
		AosOut.Enter;
		AosOut.String("Unexpected interrupt"); AosOut.Ln;
		AosOut.Memory(SYSTEM.ADR(state), SIZE(State)-4*4);	(* exclude last 4 fields *)
		IF int = 3 THEN	(* was a HALT or ASSERT *)
			(* It seems that no trap handler is installed (AosTrap not linked), so wait endlessly, while holding trace lock.  This should quiten down the system, although other processors may possibly still run processes. *)
			LOOP END
		ELSE
			AosOut.Exit;
			SYSTEM.PUTREG(SYSTEM.EAX, int);
			HALT(1801)	(* unexpected interrupt *)
		END
	END
END Unexpected;

(* InEnableIRQ - Enable a hardware interrupt (caller must hold module lock). *)

PROCEDURE -InEnableIRQ(int: LONGINT);
CODE {SYSTEM.i386}
	POP EBX
	CMP EBX, IRQ7
	JG cont2
	IN AL, IntA1
	SUB EBX, IRQ0
	BTR EAX, EBX
	OUT IntA1, AL
	JMP end
cont2:
	IN AL, IntB1
	SUB EBX, IRQ8
	BTR EAX, EBX
	OUT IntB1, AL
end:
END InEnableIRQ;

(* InDisableIRQ - Disable a hardware interrupt (caller must hold module lock). *)

PROCEDURE -InDisableIRQ(int: LONGINT);
CODE {SYSTEM.i386}
	POP EBX
	CMP EBX, IRQ7
	JG cont2
	IN AL, IntA1
	SUB EBX, IRQ0
	BTS EAX, EBX
	OUT IntA1, AL
	JMP end
cont2:
	IN AL, IntB1
	SUB EBX, IRQ8
	BTS EAX, EBX
	OUT IntB1, AL
end:
END InDisableIRQ;

(** EnableIRQ - Enable a hardware interrupt (also done automatically by InstallHandler). *)

PROCEDURE EnableIRQ*(int: LONGINT);
BEGIN
	ASSERT((int >= IRQ0) & (int <= IRQ15) & (int # IRQ2));
	AosLocks.Acquire(AosLocks.AosInterrupts);	(* protect interrupt mask register *)
	InEnableIRQ(int);
	AosLocks.Release(AosLocks.AosInterrupts)
END EnableIRQ;

(** DisableIRQ - Disable a hardware interrupt. *)

PROCEDURE DisableIRQ*(int: LONGINT);
BEGIN
	ASSERT((int >= IRQ0) & (int <= IRQ15) & (int # IRQ2));
	AosLocks.Acquire(AosLocks.AosInterrupts);	(* protect interrupt mask register *)
	InDisableIRQ(int);
	AosLocks.Release(AosLocks.AosInterrupts)
END DisableIRQ;

(** InstallHandler - Install interrupt handler & enable IRQ if necessary.
	On entry to h interrupts are disabled and may be enabled with SYSTEM.STI().  After handling the interrupt
	the state of interrupts are restored.  The acknowledgement of a hardware interrupt is done automatically.
	IRQs are mapped from IRQ0 to MaxIRQ. *)

PROCEDURE InstallHandler*(h: Handler;  int: LONGINT);
VAR n: HandlerList;
BEGIN
	ASSERT(default # NIL);	(* initialized *)
	ASSERT(int # IRQ2);	(* IRQ2 is used for cascading and remapped to IRQ9 *)
	NEW(n);	(* outside locked region, to allow gc *)
	AosLocks.Acquire(AosLocks.AosInterrupts);
		(* FieldInterrupt may traverse list while it is being modified *)
	n.handler := h;  n.next := intHandler[int];  intHandler[int] := n;
	IF n.next = default THEN n.next := NIL;
		IF (int >= IRQ0) & (int <= IRQ15) THEN InEnableIRQ(int) END
	END;
	AosLocks.Release(AosLocks.AosInterrupts)
END InstallHandler;

(** RemoveHandler - Uninstall interrupt handler & disable IRQ if necessary *)

PROCEDURE RemoveHandler*(h: Handler;  int: LONGINT);
VAR p, c: HandlerList;
BEGIN
	ASSERT(default # NIL);	(* initialized *)
	AosLocks.Acquire(AosLocks.AosInterrupts);
	IF (intHandler[int].next = NIL) & (int >= IRQ0) & (int <= IRQ15) THEN InDisableIRQ(int) END;
		(* FieldInterrupt may traverse list while it is being modified *)
	p := NIL;  c := intHandler[int];
	WHILE c.handler # h DO p := c;  c := c.next END;
	IF p = NIL THEN
		IF c.next = NIL THEN intHandler[int] := default ELSE intHandler[int] := c.next END
	ELSE
		p.next := c.next
	END;
	AosLocks.Release(AosLocks.AosInterrupts)
END RemoveHandler;

(* Get control registers. *)

PROCEDURE GetCR0to4(VAR cr: ARRAY OF LONGINT);
CODE {SYSTEM.Pentium, SYSTEM.Privileged}
	MOV EDI, cr[EBP]
	MOV EAX, CR0
	XOR EBX, EBX	; CR1 is not documented
	MOV ECX, CR2
	MOV EDX, CR3
	MOV [EDI], EAX
	MOV 4[EDI], EBX
	MOV 8[EDI], ECX
	MOV 12[EDI], EDX
	MOV EAX, CR4	; Pentium only
	MOV 16[EDI], EAX
END GetCR0to4;

(* GetDR0to7 - Get debug registers. *)

PROCEDURE GetDR0to7(VAR dr: ARRAY OF LONGINT);
CODE {SYSTEM.i386, SYSTEM.Privileged}
	MOV EDI, dr[EBP]
	MOV EAX, DR0
	MOV EBX, DR1
	MOV ECX, DR2
	MOV EDX, DR3
	MOV [EDI], EAX
	MOV 4[EDI], EBX
	MOV 8[EDI], ECX
	MOV 12[EDI], EDX
	XOR EAX, EAX	; DR4 is not documented
	XOR EBX, EBX	; DR5 is not documented
	MOV ECX, DR6
	MOV EDX, DR7
	MOV 16[EDI], EAX
	MOV 20[EDI], EBX
	MOV 24[EDI], ECX
	MOV 28[EDI], EDX
END GetDR0to7;

(* GetSegments - Get segment registers. *)

PROCEDURE GetSegments(VAR ss, es, ds, fs, gs: LONGINT);
CODE {SYSTEM.i386}
	XOR EAX, EAX
	MOV EBX, ss[EBP]
	MOV AX, SS
	MOV [EBX], EAX
	MOV EBX, es[EBP]
	MOV AX, ES
	MOV [EBX], EAX
	MOV EBX, ds[EBP]
	MOV AX, DS
	MOV [EBX], EAX
	MOV EBX, fs[EBP]
	MOV AX, FS
	MOV [EBX], EAX
	MOV EBX, gs[EBP]
	MOV AX, GS
	MOV [EBX], EAX
END GetSegments;

(* CLTS - Clear task-switched flag. *)

PROCEDURE -CLTS;
CODE {SYSTEM.i386, SYSTEM.Privileged}
	CLTS
END CLTS;

(* GetFPU - Store floating-point environment (28 bytes) and mask all floating-point exceptions. *)

PROCEDURE -GetFPU(adr: LONGINT);
CODE {SYSTEM.i386, SYSTEM.FPU}
	POP EBX
	FNSTENV [EBX]	; also masks all exceptions
	FWAIT
END GetFPU;

(* CR2 - Get page fault address. *)

PROCEDURE -CR2(): LONGINT;
CODE {SYSTEM.i386, SYSTEM.Privileged}
	MOV EAX, CR2
END CR2;

(** GetExceptionState - Get exception state from interrupt state (and switch on interrupts). *)

PROCEDURE GetExceptionState*(VAR int: State;  VAR exc: ExceptionState);
VAR id: LONGINT;  level0: BOOLEAN;
BEGIN
		(* save all state information while interrupts are still disabled *)
	exc.locks := AosLocks.BreakAll();
	exc.halt := -int.INT;  id := AosBoot.ID();
	IF int.INT = PF THEN exc.pf := CR2() ELSE exc.pf := 0 END;
	GetCR0to4(exc.CR);
	GetDR0to7(exc.DR);
	CLTS;	(* ignore task switch flag *)
	IF int.INT = MF THEN
		GetFPU(SYSTEM.ADR(exc.FPU[0]));
		int.EIP := SYSTEM.VAL(LONGINT, exc.FPU[3]);	(* modify EIP according to FPU info *)
			(* set halt code according to FPU info *)
		IF 2 IN exc.FPU[1] THEN exc.halt := -32	(* division by 0 *)
		ELSIF 3 IN exc.FPU[1] THEN exc.halt := -33	(* overflow *)
		ELSIF 0 IN exc.FPU[1] THEN exc.halt := -34	(* operation invalid *)
		ELSIF 6 IN exc.FPU[1] THEN exc.halt := -35	(* stack fault *)
		ELSIF 1 IN exc.FPU[1] THEN exc.halt := -36	(* denormalized *)
		ELSIF 4 IN exc.FPU[1] THEN exc.halt := -37	(* underflow *)
		ELSIF 5 IN exc.FPU[1] THEN exc.halt := -38	(* precision loss *)
		ELSE (* {exc.halt = -16} *)
		END
	ELSE
		AosBoot.Fill32(SYSTEM.ADR(exc.FPU[0]), LEN(exc.FPU)*SIZE(SET), 0)
	END;
	AosBoot.SetupFPU;
		(* now allow interrupts *)
	SYSTEM.STI();
	level0 := (int.CS MOD 4 = KernelLevel);
	IF int.INT = BP THEN	(* breakpoint (HALT) *)
		IF level0 THEN
			exc.halt := int.ESP	(* get halt code *)
			(* if HALT(MAX(INTEGER)), leave halt code on stack when returning, but not serious problem.*)
		ELSE
			SYSTEM.GET(int.ESP, exc.halt);	(* get halt code from outer stack *)
			IF exc.halt >= MAX(INTEGER) THEN INC(int.ESP, 4) END	(* pop halt code from outer stack *)
		END;
		IF exc.halt < MAX(INTEGER) THEN DEC(int.EIP) END;	(* point to the INT 3 instruction (assume 0CCX, not 0CDX 3X) *)
	ELSIF int.INT = OVF THEN	(* overflow *)
		DEC(int.EIP)	(* point to the INTO instruction (assume 0CEX, not 0CDX 4X) *)
	ELSIF int.INT = PF THEN	(* page fault *)
		IF int.EIP = 0 THEN	(* reset EIP to return address of indirect CALL to 0 *)
			IF level0 THEN int.EIP := int.ESP (* ret adr *) ELSE SYSTEM.GET(int.ESP, int.EIP) END
		END
	END;
		(* get segment registers *)
	GetSegments(exc.SS, exc.ES, exc.DS, exc.FS, exc.GS);
	IF level0 THEN	(* from same level, no ESP, SS etc. on stack *)
		exc.ESP := SYSTEM.ADR(int.ESP)	(* stack was here when interrupt happened *)
	ELSE	(* from outer level *)
		exc.ESP := int.ESP;  exc.SS := int.SS
	END
END GetExceptionState;

(* FieldInterrupt and FieldIRQ *)

(*
	At entry to a Handler procedure the stack is as follows:
		72	--	.GS
		68	--	.FS
		64	--	.DS
		60	--	.ES	; or haltcode
		-- if (VMBit IN .EFLAGS) --
		56	--	.SS
		52	--	.ESP	; or haltcode
		-- (VMBit IN .EFLAGS) OR (CS MOD 4 < .CS MOD 4) --
		48	--	.EFLAGS
		44	--	.CS
		40	--	.EIP	; rest popped by IRETD
		36	--	.ERR/EBP	; pushed by processor or glue code, popped by POP EBP
		32	--	.INT	<-- .ESP0	; pushed by glue code, popped by POP EBP
		28	--	.EAX
		24	--	.ECX
		20	--	.EDX
		16	--	.EBX
		12	--	.ESP0
		08	--	.EBP/ERR	; exchanged by glue code
		04	--	.ESI
		00	24	.EDI	<--- state: State
		--	20	ptr
		--	16	object pointer for DELEGATE
		--	12	TAG(state)
		--	08	ADR(state)
		--	04	EIP'	(RET to FieldInterrupt)
		--	00	EBP'	<-- EBP
		--	--	locals	<-- ESP
*)

PROCEDURE FieldInterrupt;
CODE {SYSTEM.i386}	(* 3 bytes implicit code skipped: PUSH EBP;  MOV EBP, ESP *)
entry:
	PUSHAD	; save all registers (EBP = error code)
	LEA EBP, 36[ESP]	; procedure link (for correct tracing of interrupt procedures)
	
	MOV EBX, 32[ESP]	; EBX = int number
	LEA EAX, intHandler
	MOV EAX, [EAX][EBX*4]

loop:	; call all handlers for the interrupt
	MOV ECX, ESP
	PUSH EAX	; save ptr for linked list
	PUSH stateTag	; TAG(state)
	PUSH ECX	; ADR(state)
	MOV EBX, 8[EAX]
	CMP EBX, 0
	JE nodelegate
	PUSH EBX	; object pointer for DELEGATE
nodelegate:
	CALL DWORD 4[EAX]	; call handler
	CLI	; handler may have re-enabled interrupts
	POP EAX
	MOV EAX, [EAX]
	CMP EAX, 0
	JNE loop

	POPAD	; now EBP = error code
	POP EBP	; now EBP = INT
	POP EBP	; now EBP = caller EBP
	IRETD
END FieldInterrupt;

PROCEDURE FieldIRQ;
CODE {SYSTEM.i386}	(* 3 bytes implicit code skipped: PUSH EBP;  MOV EBP, ESP *)
entry:
	PUSHAD	; save all registers (EBP = error code)
	LEA EBP, 36[ESP]	; procedure link (for correct tracing of interrupt procedures)

;	PUSH 32[ESP]	; int number
;	CALL traceInterruptIn
	
	MOV EBX, 32[ESP]	; EBX = int number
	LEA EAX, intHandler
	MOV EAX, [EAX][EBX*4]
	
loop:	; call all handlers for the interrupt
	MOV ECX, ESP
	PUSH EAX	; save ptr for linked list
	PUSH stateTag	; TAG(state)
	PUSH ECX	; ADR(state)
	MOV EBX, 8[EAX]
	CMP EBX, 0
	JE nodelegate
	PUSH EBX	; object pointer for DELEGATE
nodelegate:
	CALL DWORD 4[EAX]	; call handler
	CLI	; handler may have re-enabled interrupts
	POP EAX
	MOV EAX, [EAX]
	CMP EAX, 0
	JNE loop

;	PUSH 32[ESP]	; int number
;	CALL traceInterruptOut

; ack interrupt
	MOV AL, 20H	; undoc PC ed. 2 p. 1018
	CMP BYTE 32[ESP], IRQ8
	JB irq0
	OUT IntB0, AL	; 2nd controller
irq0:
	OUT IntA0, AL	; 1st controller

	POPAD	; now EBP = error code
	POP EBP	; now EBP = INT
	POP EBP	; now EBP = caller EBP
	IRETD
END FieldIRQ;

(*
flat priority experiment
CONST IRQ0Neg = -IRQ0;  IRQ8Neg = -IRQ8;
	CMP EBX, IRQ8
	JAE irq8

; disable and ack irq 0-7
	LEA ECX, IRQ0Neg[EBX]
	IN AL, IntA1
	BTS EAX, ECX
	OUT IntA1, AL
	
	MOV AL, 20H
	OUT IntA0, AL
	JMP dispatch
	
; disable and ack irq 8-15
irq8:
	LEA ECX, IRQ8Neg[EBX]
	IN AL, IntB1
	BTS EAX, ECX
	OUT IntB1, AL
	
	MOV AL, 20H
	OUT IntB0, AL
	OUT IntA0, AL	; undoc PC ed. 2 p. 1018

dispatch:
	STI
*)

(* LoadIDT - Load interrupt descriptor table *)

PROCEDURE LoadIDT(base, size: LONGINT);
CODE {SYSTEM.i386, SYSTEM.Privileged}
	SHL size[EBP], 16
	MOV EBX, 2
	LIDT size[EBP][EBX]
END LoadIDT;

(** Init - Initialize interrupt handling.  Called once during initialization.  Uses NEW. *)

(*
	The glue code is:
	entry0:	; entry point for interrupts without error code
		PUSH 0	; fake error code
	entry1:	; entry point for interrupts with error code
		XCHG [ESP], EBP	; exchange error code and caller EBP
		PUSH int	; interrupt number
		JMP FieldInterrupt:entry
*)

PROCEDURE Init*;
VAR a: LONGINT;  o, i: LONGINT;  p: PROCEDURE;  mask: SET;
BEGIN
	stateTag := SYSTEM.TYPECODE(State);
		(* initialise 8259 interrupt controller chips *)
	SYSTEM.PORTOUT(IntA0, 11X);  SYSTEM.PORTOUT(IntA1, CHR(IRQ0));
	SYSTEM.PORTOUT(IntA1, 4X);  SYSTEM.PORTOUT(IntA1, 1X);  SYSTEM.PORTOUT(IntA1, 0FFX);
	SYSTEM.PORTOUT(IntB0, 11X);  SYSTEM.PORTOUT(IntB1, CHR(IRQ8));
	SYSTEM.PORTOUT(IntB1, 2X);  SYSTEM.PORTOUT(IntB1, 1X);  SYSTEM.PORTOUT(IntB1, 0FFX);
		(* enable interrupts from second interrupt controller, chained to line 2 of controller 1 *)
	SYSTEM.PORTIN(IntA1, SYSTEM.VAL(CHAR, mask));
	EXCL(mask, IRQ2-IRQ0);
	SYSTEM.PORTOUT(IntA1, SYSTEM.VAL(CHAR, mask));
	
	NEW(default);  default.next := NIL;  default.handler := Unexpected;
	FOR i := 0 TO IDTSize-1 DO	(* set up glue code *)
		intHandler[i] := default;  o := 0;
			(* PUSH error code, int num & regs *)
		glue[i][o] := 6AX; INC(o); glue[i][o] := 0X; INC(o);	(* PUSH 0 ; {o = 2} *)
		glue[i][o] := 87X; INC(o); glue[i][o] := 2CX; INC(o); glue[i][o] := 24X; INC(o);	(* XCHG [ESP], EBP *)
		glue[i][o] := 6AX; INC(o); glue[i][o] := CHR(i); INC(o);	(* PUSH i *)
		IF (i >= IRQ0) & (i <= IRQ15) THEN p := FieldIRQ ELSE p := FieldInterrupt END;
		a := SYSTEM.VAL(LONGINT, p)+3 - (SYSTEM.ADR(glue[i][o])+5);
		glue[i][o] := 0E9X; INC(o);	(* JMP FieldInterrupt.entry *)
		SYSTEM.PUT(SYSTEM.ADR(glue[i][o]), a);
	
			(* set up IDT entry *)
		IF (i > 31) OR ~(i IN {8, 10..14, 17}) THEN a := SYSTEM.ADR(glue[i][0])	(* include PUSH 0 *)
		ELSE a := SYSTEM.ADR(glue[i][2])	(* skip PUSH 0, processor supplies error code *)
		END;
		idt[i].offsetBits0to15 := SHORT(a MOD 10000H);
			(* IRQ0 must be at level 0 because time slicing in AosActive needs to set interrupted process' ESP *)
			(* all irq's are handled at level 0, because of priority experiment in AosActive.FieldIRQ *)
		IF TRUE (*(i < IRQ0) OR (i > IRQ15) OR (i = IRQ0) OR (i = IRQ0+1)*) THEN
			idt[i].selector := KernelCodeSel;	(* gdt[1] -> non-conformant segment => level 0 *)
			idt[i].gateType := SYSTEM.VAL(INTEGER, 0EE00H)	(* present, DPL 3, system, 386 interrupt *)
		ELSE	(* {IRQ0..IRQ15} - {IRQ0+1} *)
			idt[i].selector := UserCodeSel;	(* gdt[3] -> conformant segment => level 0 or 3 *)
			idt[i].gateType := SYSTEM.VAL(INTEGER, 08E00H)	(* present, DPL 0, system, 386 interrupt *)
		END;
		idt[i].offsetBits16to31 := SHORT(a DIV 10000H)
	END
END Init;

(** Start - Start handling interrupts.  Every processor calls this once during initialization. *)

PROCEDURE Start*;
BEGIN
	ASSERT(default # NIL);	(* initialized *)
	LoadIDT(SYSTEM.ADR(idt[0]), SIZE(IDT)-1);
	SYSTEM.STI()
END Start;

(*
PROCEDURE Dummy(int: LONGINT);
BEGIN
END Dummy;
*)

BEGIN
	(*traceInterruptIn := Dummy;  traceInterruptOut := Dummy;*)
	default := NIL	(* initialized later *)
END AosInterrupts.

(*
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

(*
03.03.1998	pjm	First version
05.05.1998	pjm	Handle spurious interrupts
25.11.1998	pjm	Multiple handlers per interrupt
28.05.1999	pjm	EnableIRQ, DisableIRQ
16.05.1999	pjm	AckIRQ
23.05.1999	pjm	AckIRQ experiment failed
23.05.1999	pjm	Swapped ERR and EBP to make procedure link correct over FieldInterrupt also (e.g. Trap)
09.10.2003	mvt	Bugfix in procedure InEnableIRQ: ASM instruction BTC replaced by BTR
09.10.2003	mvt	Changed Handler type to DELEGATE, modified FieldIRQ and FieldInterrupt
*)
