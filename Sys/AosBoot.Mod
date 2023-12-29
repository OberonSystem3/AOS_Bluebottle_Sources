(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosBoot; (** AUTHOR "pjm"; PURPOSE "Bootstrapping, configuration and machine interface"; *)

(* This must be the first module in the statically linked boot file. *)

IMPORT SYSTEM;

CONST
	Version = "Aos 12.03.2004";
	
	MaxCPU* = 6;	(** maximum number of processors (up to 16) *)
	
	Trace* = FALSE;	(** display trace output during booting *)
	
		(** bits in features variable *)
	MTTR* = 12;  MMX* = 23;  HTT* = 28;

	MaxDisks = 2;	(* maximum number of disks with BIOS parameters *)
	
	HeapAdr = 100000H;
	
	MaxMemTop = 80000000H;
	
	DefaultDMASize = 20;	(* default size of ISA DMA area in KB *)

TYPE
	Vendor* = ARRAY 13 OF CHAR;
	
	IDMap* = ARRAY 16 OF SHORTINT;
	
VAR
	lowTop*: LONGINT;	(** top of low memory *)
	memTop*: LONGINT;	(** top of memory *)
	dmaSize*: LONGINT;	(** size of ISA dma area, above lowTop (for use in Aos.Diskettes) *)
	
	configMP*: LONGINT;	(** MP spec config table physical address (outside reported RAM) *)
	revMP*: CHAR;	(** MP spec revision *)
	featureMP*: ARRAY 5 OF CHAR;	(** MP spec feature bytes 1-5 *)
	
	version*: ARRAY 32 OF CHAR;	(** Aos version *)
	
	SSESupport*: BOOLEAN;
	SSE2Support*: BOOLEAN;
	
	features*: SET;	(** processor features *)
	fcr*: SET;	(** default floating-point control register value (default rounding mode is towards -infinity, for ENTIER) *)
	mhz*: HUGEINT;	(** clock rate of GetTimer() in MHz, or 0 if not known *)

	chs: ARRAY MaxDisks OF RECORD cyls, hds, spt: LONGINT END;
	initRegs: ARRAY 2 OF LONGINT;	(* kernel parameters *)
	config: ARRAY 2048 OF CHAR;	(* config strings *)
	bootFlag: LONGINT;

	idAdr: LONGINT;	(* address of processor ID register *)
	map: IDMap;
	bootID: LONGINT;	(* ID of boot processor (0) *)

(** -- Processor identification -- *)

(** Return current processor ID (0 to MaxNum-1). *)

PROCEDURE ID*(): LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, idAdr
	LEA EBX, map
	MOV EAX, [EAX]
	SHR EAX, 24
	AND EAX, 15
	MOV AL, [EBX][EAX]
END ID;

(** -- Atomic operations -- *)

(** Atomic INC with one parameter. *)

PROCEDURE -Inc*(VAR x: LONGINT);
CODE {SYSTEM.i386}
	POP EAX
	LOCK
	INC DWORD [EAX]
END Inc;

(** Atomic EXCL. *)

PROCEDURE Excl*(VAR s: SET; bit: LONGINT);
CODE {SYSTEM.i386}
	MOV EAX, bit[EBP]
	MOV EBX, s[EBP]
	LOCK
	BTR [EBX], EAX
END Excl;

(** -- Miscellaneous -- *)

(** This procedure should be called in all spin loops as a hint to the processor (e.g. Pentium 4). *)

PROCEDURE -SpinHint*;
CODE {SYSTEM.i386}
	XOR ECX, ECX	; just in case some processor interprets REP this way
	REP NOP	; PAUSE instruction (* NOP on pre-P4 processors, Spin Loop Hint on P4 and after *)
END SpinHint;

(** Fill "size" bytes at "destAdr" with "filler".  "size" must be multiple of 4. *)

PROCEDURE Fill32*(destAdr, size, filler: LONGINT);
CODE {SYSTEM.i386}
	MOV EDI, destAdr[EBP]
	MOV ECX, size[EBP]
	MOV EAX, filler[EBP]
	TEST ECX, 3
	JZ ok
	PUSH 8	; ASSERT failure
	INT 3
ok:
	SHR ECX, 2
	CLD
	REP STOSD
END Fill32;

(** Return timer value of the current processor, or 0 if not available. *)

(* e.g. ARM does not have a fine-grained timer *)

PROCEDURE -GetTimer*(): HUGEINT;
CODE {SYSTEM.Pentium}
	RDTSC	; set EDX:EAX
END GetTimer;

(** Disable interrupts and return old interrupt state. *)

PROCEDURE -DisableInterrupts*(): SET;
CODE {SYSTEM.i386}
	PUSHFD
	CLI
	POP EAX
END DisableInterrupts;

(** Restore interrupt state.  Parameter s must be return value of earlier DisableInterrupts call on same processor. *)

PROCEDURE -RestoreInterrupts*(s: SET);
CODE {SYSTEM.i386}
	POPFD
END RestoreInterrupts;

(** Return TRUE iff interrupts are enabled on the current processor. *)

PROCEDURE -InterruptsEnabled*(): BOOLEAN;
CODE {SYSTEM.i386}
	PUSHFD
	POP EAX
	SHR EAX, 9
	AND AL, 1
END InterruptsEnabled;

(** -- HUGEINT operations -- *)

(** Return -h. *)

PROCEDURE -NegH*(h: HUGEINT): HUGEINT;
CODE {SYSTEM.i386}
	POP EAX
	POP EDX
	NEG EAX
	ADC EDX, 0
	NEG EDX
END NegH;

(** Return h+g. *)

PROCEDURE -AddH*(h, g: HUGEINT): HUGEINT;
CODE {SYSTEM.i386}
	POP EBX
	POP ECX
	POP EAX
	POP EDX
	ADD EAX, EBX
	ADC EDX, ECX
END AddH;

(** Return h-g. *)

PROCEDURE -SubH*(h, g: HUGEINT): HUGEINT;
CODE {SYSTEM.i386}
	POP EBX
	POP ECX
	POP EAX
	POP EDX
	SUB EAX, EBX
	SBB EDX, ECX
END SubH;

(** Return h*g. *)

PROCEDURE -MulH*(h, g: HUGEINT): HUGEINT;
CODE {SYSTEM.i386, SYSTEM.FPU}
	FILD QWORD 8[ESP]
	FILD QWORD [ESP]
	FMULP
	FISTP QWORD 8[ESP]
	WAIT
	POP EAX
	POP EAX
	POP EAX
	POP EDX
END MulH;

(** Return h DIV g.  Rounding and division by zero behaviour is currently undefined. *)

PROCEDURE -DivH*(h, g: HUGEINT): HUGEINT;
CODE {SYSTEM.i386, SYSTEM.FPU}
	FILD QWORD 8[ESP]
	FILD QWORD [ESP]
	FDIVP	; simply use current floating-point rounding mode
	FISTP QWORD 8[ESP]
	WAIT
	POP EAX
	POP EAX
	POP EAX
	POP EDX
END DivH;

(** Return ASH(h, n). *)

PROCEDURE -ASHH*(h: HUGEINT; n: LONGINT): HUGEINT;
CODE {SYSTEM.i386}
	POP ECX
	POP EAX
	POP EDX
	CMP ECX, 0
	JL right
	AND ECX, 63	; limit count, like ASH
	JZ exit
ll:
	SHL EAX, 1
	RCL EDX, 1
	DEC ECX
	JNZ ll
	JMP exit
right:
	AND ECX, 63	; limit count, like ASH
	JZ exit
lr:
	SAR EDX, 1
	RCR EAX, 1
	DEC ECX
	JNZ lr
exit:
END ASHH;

(** Return h > g. *)

PROCEDURE -GreaterH*(h, g: HUGEINT): BOOLEAN;
CODE {SYSTEM.i386}
	POP EBX
	POP ECX
	POP EAX
	POP EDX
	CMP EDX, ECX
	JNE g1
	CMP EAX, EBX
	SETA AL	; unsigned
	JMP exit
g1:
	SETG AL	; signed
exit:
END GreaterH;

(** Return h = g. *)

PROCEDURE -EqualH*(h, g: HUGEINT): BOOLEAN;
CODE {SYSTEM.i386}
	POP EBX
	POP ECX
	POP EAX
	POP EDX
	CMP ECX, EDX
	SETE CL
	CMP EAX, EBX
	SETE AL
	AND AL, CL
END EqualH;

(** Return i as a HUGEINT (sign extended). *)

PROCEDURE -LIntToHInt*(i: LONGINT): HUGEINT;
CODE {SYSTEM.i386}
	POP EAX
	XOR EDX, EDX
	TEST EAX, EAX	; test sign
	SETS DL	; 0 or 1
	NEG EDX	; 0 or -1
END LIntToHInt;

(** Return a HUGEINT composed of high and low. *)

PROCEDURE -LInt2ToHInt*(high, low: LONGINT): HUGEINT;
CODE {SYSTEM.i386}
	POP EAX
	POP EDX
END LInt2ToHInt;

(** Return h converted to a LONGINT (MOD 100000000H). *)

PROCEDURE -HIntToLInt*(h: HUGEINT): LONGINT;
CODE {SYSTEM.i386}
	POP EAX
	POP EDX
END HIntToLInt;

(** Return h as a LONGREAL, with possible loss of precision. *)

PROCEDURE -HIntToLReal*(h: HUGEINT): LONGREAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	FILD QWORD [ESP]
	WAIT
	ADD ESP, 8
END HIntToLReal;

(** -- Processor initialization -- *)

PROCEDURE -SetFCR(s: SET);
CODE {SYSTEM.i386, SYSTEM.FPU}
	FLDCW [ESP]	; parameter s
	POP EAX
END SetFCR;

PROCEDURE -FCR(): SET;
CODE {SYSTEM.i386, SYSTEM.FPU}
	PUSH 0
	FNSTCW [ESP]
	FWAIT
	POP EAX
END FCR;

PROCEDURE -InitFPU;
CODE {SYSTEM.i386, SYSTEM.FPU}
	FNINIT
END InitFPU;

(** Setup FPU control word of current processor. *)

PROCEDURE SetupFPU*;
BEGIN
	InitFPU; SetFCR(fcr)
END SetupFPU;

(* Set up flags (3, p. 20)
	Bit
	1,3,5,15,19..31 - no change
	0,2,4,6..7,11 - CF,PF,AF,ZF,SF,OF off
	8 - TF off
	9 - IF off (no interrupts)
	10 - DF off
	12..13 - IOPL = 3
	14 - NT off (no Windows)
	16 - RF off (no Interference)
	17- VM off (no virtual 8086 mode)
	18 - AC off (no 486 alignment checks) *)

PROCEDURE -SetupFlags;
CODE {SYSTEM.i386}
	PUSHFD
	AND DWORD [ESP], 0FFF8802AH
	OR DWORD [ESP], 3000H
	POPFD
END SetupFlags;

(* Set up various 486-specific flags (3, p. 23)
	1. Enable exception 16 on math errors.
	2. Disable supervisor mode faults on write to read-only pages 
		(386-compatible for stack checking).
	3. Enable the Alignment Check field in EFLAGS *)

PROCEDURE -Setup486Flags;
CODE {SYSTEM.i386, SYSTEM.Privileged}
	MOV EAX, CR0
	OR EAX, 00040020H
	AND EAX, 0FFFEFFFFH
	MOV CR0, EAX
END Setup486Flags;

(* Set up 586-specific things *)

PROCEDURE -Setup586Flags;
CODE {SYSTEM.Pentium, SYSTEM.Privileged}
	MOV EAX, CR4
	BTR EAX, 2	; clear TSD
	MOV CR4, EAX
END Setup586Flags;

(* setup SSE and SSE2 extension *)

PROCEDURE SetupSSE2Ext;
CONST
	FXSRFlag = 24;
	SSEFlag = 25;
	SSE2Flag = 26;
BEGIN
	SSE2Support := FALSE;
	(* checking for SSE support *)
	IF SSEFlag IN features THEN
		SSESupport := TRUE;
		(* checking for SSE2 support *)
		IF SSE2Flag IN features THEN
			SSE2Support := TRUE;
		END;
		(* checking for support for the FXSAVE and FXRSTOR instruction *)
		IF FXSRFlag IN features THEN
			InitSSE();
		END;
	END;
END SetupSSE2Ext;

PROCEDURE -InitSSE;
CODE {SYSTEM.Pentium, SYSTEM.Privileged}
	MOV	EAX, CR4
	OR	EAX, 00000200H	(* set bit 9 (OSFXSR) *)
	AND	EAX, 0FFFFFBFFH	(* delete bit 10 (OSXMMEXCPT) *)
	MOV	CR4, EAX
END InitSSE;

(* Disable exceptions caused by math in new task.  (1, p. 479) *)

PROCEDURE -DisableMathTaskEx;
CODE {SYSTEM.i386, SYSTEM.Privileged}
	MOV EAX,CR0
	AND AL, 0F5H
	MOV CR0, EAX
END DisableMathTaskEx;

(* Disable math emulation (1, p. 479) , bit 2 of CR0 *)

PROCEDURE -DisableEmulation;
CODE {SYSTEM.i386, SYSTEM.Privileged}
	MOV EAX, CR0
	AND AL, 0FBH
	MOV CR0, EAX
END DisableEmulation;

(** CPU identification. *)

PROCEDURE CPUID*(VAR vendor: Vendor;  VAR version: LONGINT;  VAR features: SET);
CODE {SYSTEM.i386, SYSTEM.Pentium}
	MOV EAX, 0
	CPUID
	CMP EAX, 0
	JNE ok
	
	MOV ESI, vendor[EBP]
	MOV [ESI], AL	; AL = 0
	MOV ESI, version[EBP]
	MOV [ESI], EAX	; EAX = 0
	MOV ESI, features[EBP]
	MOV [ESI], EAX
	JMP end

ok:
	MOV ESI, vendor[EBP]
	MOV [ESI], EBX
	MOV 4[ESI], EDX
	MOV 8[ESI], ECX
	MOV BYTE 12[ESI], 0
	
	MOV EAX, 1
	CPUID
	
	MOV ESI, version[EBP]
	MOV [ESI], EAX
	MOV ESI, features[EBP]
	MOV [ESI], EDX

end:
END CPUID;

(** Initialise current processor.  Must be called by every processor. *)

PROCEDURE InitProcessor*;
BEGIN
	SetupFlags;
	Setup486Flags;
	Setup586Flags;
	DisableMathTaskEx;
	DisableEmulation;
	SetupFPU;
	SetupSSE2Ext
END InitProcessor;

(** Initialize APIC ID address. *)

PROCEDURE InitAPICIDAdr*(adr: LONGINT; m: IDMap);
VAR s: SET;
BEGIN
	s := DisableInterrupts();
	idAdr := adr; map := m;
	RestoreInterrupts(s)
END InitAPICIDAdr;

PROCEDURE Init;
VAR i, version: LONGINT; u: ARRAY 8 OF CHAR; vendor: Vendor;
BEGIN
	CPUID(vendor, version, features);	(* set features - assume all processors same as boot processor *)
	InitFPU;
	fcr := (FCR() - {0,2,3,10,11}) + {0..5,8,9};	(* default FCR RC=00B *)
	bootID := 0; map[0] := 0;
	idAdr := SYSTEM.ADR(bootID);
		(* allow user to specify GetTimer() rate, for tracing purposes *)
	GetConfig("MHz", u);
	i := 0; i := StrToInt(i, u);
	mhz := LIntToHInt(i)
END Init;

(** -- Configuration and bootstrapping -- *)

(** Return the value of the configuration string specified by parameter name in parameter val.  Returns val = "" if the string was not found, or has an empty value. *)

PROCEDURE GetConfig*(name: ARRAY OF CHAR;  VAR val: ARRAY OF CHAR);
VAR i, src: LONGINT;  ch: CHAR;
BEGIN
	ASSERT(name[0] # "=");	(* no longer supported, use GetInit instead *)
	src := 0;
	LOOP
		ch := config[src];
		IF ch = 0X THEN EXIT END;
		i := 0;
		LOOP
			ch := config[src];
			IF (ch # name[i]) OR (name[i] = 0X) THEN EXIT END;
			INC(i);  INC(src)
		END;
		IF (ch = 0X) & (name[i] = 0X) THEN	(* found: (src^ = 0X) & (name[i] = 0X) *)
			i := 0;
			REPEAT
				INC(src);  ch := config[src];  val[i] := ch; INC(i);
				IF i = LEN(val) THEN val[0] := 0X; RETURN END	(* val too short *)
			UNTIL ch = 0X;
			val[i] := 0X; RETURN
		ELSE
			WHILE ch # 0X DO	(* skip to end of name *)
				INC(src);  ch := config[src]
			END;
			INC(src);
			REPEAT	(* skip to end of value *)
				ch := config[src];  INC(src)
			UNTIL ch = 0X
		END
	END;
	val[0] := 0X
END GetConfig;

(** Get CHS parameters of first two BIOS-supported hard disks. *)

PROCEDURE GetDiskCHS*(d: LONGINT;  VAR cyls, hds, spt: LONGINT);
BEGIN
	cyls := chs[d].cyls;  hds := chs[d].hds;  spt := chs[d].spt
END GetDiskCHS;

(** Get parameter values from Init string.  If n = 0, return val = ASH(bx, 16) + ax, and if n = 1, return val = ASH(dx, 16) + cx, where ax, bx, cx, dx are the register values after the OBL boot loader or noboot.exe have executed the 16-bit x86 code in the Init string. *)

PROCEDURE GetInit*(n: LONGINT;  VAR val: LONGINT);
BEGIN
	val := initRegs[n]
END GetInit;

(** Convert a string to an integer.  Parameter i specifies where in the string scanning should begin (usually 0 in the first call).  Scanning stops at the first non-valid character, and i returns the updated position.  Parameter s is the string to be scanned.  The value is returned as result, or 0 if not valid.  Syntax: number = ["-"] digit {digit} ["H" | "h"] .  digit = "0" | ... "9" | "A" .. "F" | "a" .. "f" .  If the number contains any hexdecimal letter, or if it ends in "H" or "h", it is interpreted as hexadecimal. *)

PROCEDURE StrToInt*(VAR i: LONGINT;  VAR s: ARRAY OF CHAR): LONGINT;
	VAR vd, vh, sgn, d: LONGINT;  hex: BOOLEAN;
BEGIN
	vd := 0;  vh := 0;  hex := FALSE;
	IF s[i] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END;
	LOOP
		IF (s[i] >= "0") & (s[i] <= "9") THEN d := ORD(s[i])-ORD("0")
		ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN d := ORD(CAP(s[i]))-ORD("A")+10; hex := TRUE
		ELSE EXIT
		END;
		vd := 10*vd + d;  vh := 16*vh + d;
		INC(i)
	END;
	IF CAP(s[i]) = "H" THEN hex := TRUE; INC(i) END;	(* optional H *)
	IF hex THEN vd := vh END;
	RETURN sgn * vd
END StrToInt;

(* Delay for IO *)

PROCEDURE -Wait;
CODE {SYSTEM.i386}
	JMP 0
	JMP 0
	JMP 0
END Wait;

(* Reset processor by causing a double fault. *)

PROCEDURE Reboot;
CODE {SYSTEM.i386, SYSTEM.Privileged}
	PUSH 0
	PUSH 0
	LIDT [ESP]
	INT 3
END Reboot;

(** Shut down the system.  If parameter reboot is set, attempt to reboot the system. *)

PROCEDURE Shutdown*(reboot: BOOLEAN);
VAR i: LONGINT;
BEGIN
	SYSTEM.CLI();
	IF reboot THEN	(* attempt reboot *)
		SYSTEM.PORTOUT(70H, 8FX);	(* Reset type: p. 5-37 AT Tech. Ref. *)
		Wait;  SYSTEM.PORTOUT(71H, 0X);	(* Note: soft boot flag was set in InitMemory *)
		Wait;  SYSTEM.PORTOUT(70H, 0DX);
		Wait;  SYSTEM.PORTOUT(64H, 0FEX);	(* reset CPU *)
		FOR i := 1 TO 10000 DO END;
		Reboot
	END;
	LOOP END
END Shutdown;

(* Get hard disk parameters. *)

PROCEDURE GetPar(p: LONGINT;  ofs: LONGINT): LONGINT;
VAR ch: CHAR;
BEGIN
	SYSTEM.GET(p+12+ofs, ch);
	RETURN ORD(ch)
END GetPar;

(* Read boot table. *)

PROCEDURE ReadBootTable(bt: LONGINT);
	VAR i, j, d, p, type, addr, size, heapSize: LONGINT;  ch: CHAR;
BEGIN
	heapSize := 0;  lowTop := 0;
	p := bt;  d := 0;
	LOOP
		SYSTEM.GET(p, type);
		IF type = -1 THEN
			EXIT	(* end *)
		ELSIF type = 3 THEN	(* boot memory/top of low memory *)
			SYSTEM.GET(p+8, addr);  SYSTEM.GET(p+12, size);
			lowTop := addr+size
		ELSIF type = 4 THEN	(* free memory/extended memory size *)
			SYSTEM.GET(p+8, addr);  SYSTEM.GET(p+12, size);
			IF addr = HeapAdr THEN heapSize := size END
		ELSIF type = 5 THEN	(* HD config *)
			IF d < MaxDisks THEN
				chs[d].cyls := GetPar(p, 0) + 100H*GetPar(p, 1);
				chs[d].hds := GetPar(p, 2);  chs[d].spt := GetPar(p, 14);
				INC(d)
			END
		ELSIF type = 8 THEN	(* config strings *)
			i := p+8;  j := 0;	(* copy the config strings over *)
			LOOP
				SYSTEM.GET(i, ch);  config[j] := ch;  INC(i);  INC(j);
				IF ch = 0X THEN EXIT END;
				REPEAT SYSTEM.GET(i, ch);  config[j] := ch;  INC(i);  INC(j) UNTIL ch = 0X;	(* end of name *)
				REPEAT SYSTEM.GET(i, ch);  config[j] := ch;  INC(i);  INC(j) UNTIL ch = 0X	(* end of value *)
			END
		END;
		SYSTEM.GET(p+4, size);  INC(p, size)
	END;
	ASSERT((heapSize # 0) & (lowTop # 0));
	memTop := HeapAdr+heapSize
END ReadBootTable;

(** Read a byte from the non-volatile setup memory. *)

PROCEDURE GetNVByte*(ofs: LONGINT): CHAR;
	VAR c: CHAR;
BEGIN
	SYSTEM.PORTOUT(70H, CHR(ofs));  Wait;  SYSTEM.PORTIN(71H, c);
	RETURN c
END GetNVByte;

(** Write a byte to the non-volatile setup memory. *)

PROCEDURE PutNVByte*(ofs: LONGINT;  val: CHAR);
BEGIN
	SYSTEM.PORTOUT(70H, CHR(ofs));  Wait;  SYSTEM.PORTOUT(71H, val)
END PutNVByte;

(** Compute a checksum for the Intel SMP spec floating pointer structure. *)

PROCEDURE ChecksumMP*(adr, size: LONGINT): LONGINT;
	VAR sum, x: LONGINT;  ch: CHAR;
BEGIN
	sum := 0;
	FOR x := adr TO adr+size-1 DO
		SYSTEM.GET(x, ch);
		sum := (sum + ORD(ch)) MOD 256
	END;
	RETURN sum
END ChecksumMP;

(* Search for MP floating pointer structure. *)

PROCEDURE SearchMem(adr, size: LONGINT): LONGINT;
	VAR x, len: LONGINT;  ch: CHAR;
BEGIN
	WHILE size > 0 DO
		SYSTEM.GET(adr, x);
		IF x = 05F504D5FH THEN	(* "_MP_" found *)
			SYSTEM.GET(adr+8, ch);  len := ORD(ch)*16;
			IF len > 0 THEN
				SYSTEM.GET(adr+9, ch);
				IF (ch = 1X) OR (ch >= 4X) THEN	(* version 1.1 or 1.4 or higher *)
					IF ChecksumMP(adr, len) = 0 THEN
						RETURN adr	(* found *)
					END
				END
			END
		END;
		INC(adr, 16);  DEC(size, 16)
	END;
	RETURN -1	(* not found *)
END SearchMem;

(* Search for MP spec info. *)

PROCEDURE SearchMP;
	VAR adr: LONGINT;
BEGIN
	adr := 0;
	SYSTEM.GET(040EH, SYSTEM.VAL(INTEGER, adr));	(* EBDA address *)
	adr := adr*16;
	IF adr < 100000H THEN adr := SearchMem(adr, 1024)	(* 1. look in EBDA *)
	ELSE adr := -1 
	END;
	IF adr < 0 THEN	(* 2. look in last kb of base memory *)
		adr := SearchMem(lowTop + (-lowTop) MOD 10000H - 1024, 1024);
		IF adr < 0 THEN	(* 3. look at top of physical memory *)
			adr := SearchMem(memTop - 1024, 1024);
			IF adr < 0 THEN	(* 4. look in BIOS ROM space *)
				adr := SearchMem(0E0000H, 20000H)
			END
		END
	END;
	IF adr < 0 THEN
		revMP := 0X;  configMP := -1
	ELSE
		SYSTEM.GET(adr+9, revMP);
		SYSTEM.MOVE(adr+11, SYSTEM.ADR(featureMP[0]), 5);	(* feature bytes *)
		SYSTEM.GET(adr+4, configMP);	(* physical address outside reported RAM (spec 1.4 p. 4-2) *)
		IF configMP = 0 THEN configMP := -1 END
	END
END SearchMP;

(* Allocate area for ISA DMA. *)

PROCEDURE AllocateDMA;
VAR old: LONGINT;
BEGIN
	old := lowTop;
	dmaSize := DefaultDMASize*1024;
	ASSERT((dmaSize >= 0) & (dmaSize <= 65536));
	IF (lowTop-dmaSize) DIV 65536 # (lowTop-1) DIV 65536 THEN	(* crosses 64KB boundary *)
		DEC(lowTop, lowTop MOD 65536)	(* round down to 64KB boundary *)
	END;
	DEC(lowTop, dmaSize);	(* allocate memory *)
	dmaSize := old - lowTop	(* how much was allocated (including rounding) *)
END AllocateDMA;

(* Check if the specified address is RAM. *)

PROCEDURE IsRAM(adr: LONGINT): BOOLEAN;
CONST Pattern1 = 0BEEFC0DEH;  Pattern2 = 0AA55FF00H;
VAR save, x: LONGINT;  ok: BOOLEAN;
BEGIN
	ok := FALSE;
	SYSTEM.GET(adr, save);
	SYSTEM.PUT(adr, Pattern1);	(* attempt 1st write *)
	x := Pattern2;	(* write something else *)
	SYSTEM.GET(adr, x);	(* attempt 1st read *)
	IF x = Pattern1 THEN	(* first test passed *)
		SYSTEM.PUT(adr, Pattern2);	(* attempt 2nd write *)
		x := Pattern1;	(* write something else *)
		SYSTEM.GET(adr, x);	(* attempt 2nd read *)
		ok := (x = Pattern2)
	END;
	SYSTEM.PUT(adr, save);
	RETURN ok
END IsRAM;

(* Check amount of memory available and update memTop. *)

PROCEDURE CheckMemory;
CONST M = 100000H;  ExtMemAdr = M;  Step = M;
VAR s: ARRAY 16 OF CHAR; adr, i: LONGINT;
BEGIN
	GetConfig("ExtMemSize", s);	(* in MB *)
	IF s[0] # 0X THEN	(* override detection *)
		i := 0; memTop := ExtMemAdr + StrToInt(i, s) * M
	ELSE
		IF memTop >= 15*M THEN	(* search for more memory (ignore aliasing) *)
			adr := memTop-4;
			WHILE (SYSTEM.LSH(memTop, -12) < SYSTEM.LSH(MaxMemTop, -12)) & IsRAM(adr) DO
				memTop := adr+4;
				INC(adr, Step)
			END
		END
	END
END CheckMemory;

(* Init code called from OBL.  EAX = boot table offset.  ESI, EDI=initRegs.  2k stack is available.  No trap handling. *)

BEGIN
	SYSTEM.GETREG(SYSTEM.EAX, bootFlag);	(* EAX from bootstrap loader *)
	SYSTEM.GETREG(6, initRegs[0]);  SYSTEM.GETREG(7, initRegs[1]);	(* initRegs0 & initRegs1 *)
	SYSTEM.PUT(0472H, 01234H);	(* soft boot flag, for when we reboot *)
	ReadBootTable(bootFlag);
	CheckMemory;
	SearchMP;
	AllocateDMA;	(* must be called after SearchMP, as lowTop is modified *)
	version := Version;
	Init;
	InitProcessor
END AosBoot.

(*
03.03.1998	pjm	First version
30.06.1999	pjm	ProcessorID moved to AosProcessor
*)

(**
Notes

This module defines an interface to the boot environment of the system.  The facilities provided here are only intended for the lowest levels of the system, and should never be directly imported by user modules (exceptions are noted below).  They are highly specific to the system hardware and firmware architecture.

Typically a machine has some type of firmware that performs initial testing and setup of the system.  The firmware initiates the operating system bootstrap loader, which loads the boot file.  This module is the first module in the statically linked boot file that gets control.

There are two more-or-less general procedures in this module: GetConfig and StrToInt.  GetConfig is used to query low-level system settings, e.g., the location of the boot file system.  StrToInt is a utility procedure that parses numeric strings.

Config strings:

ExtMemSize	Specifies size of extended memory (above 1MB) in MB.  This value is not checked for validity.  Setting it false may cause the system to fail, possible after running for some time.  The memory size is usually detected automatically, but if the detection does not work for some reason, or if you want to limit the amount of memory detected, this string can be set.  For example, if the machine has 64MB of memory, this value can be set as ExtMemSize="63".
*)

(*
to do:
o rename to AosMachine
*)
