MODULE AosCPUID; (** AUTHOR: "staubesv"; PURPOSE: "Intel/AMD CPUID Information"; *)
(**
 * The purpose of this module is to dump processor information provided by the CPUID instruction in a human readable format.
 * It is not part (and not intended to be part) of the AOS kernel.
 *
 * Usage:
 *
 *	AosCPUID.Show ~ 	displays the processor name and the most relevant features
 *	AosCPUID.ShowDetailed ~ displays all information provided by CPUID
 *
 *	S.Free AosCPUID ~
 *
 * Notes:
 *	- The CPUID instruction is supported by CPUs >= 80486
 *
 * References:
 *
 *	[1] Intel Processor Identification and the CPUID Instruction, Application Note 485, September 2006
 *	[2] AMD CPUID Specification, Revision 2.18, January 2006
 *
 * Status:
 *	- AMD CPU's: Full implementation
 *	- Intel CPU's: Untested partial implementation
 *
 * History:
 *
 *	20.11.2006	First release (staubesv)
 *)
 
 
IMPORT
	SYSTEM, AosOut;
	
CONST

	(** CpuInformation.type encoding *)
	Intel* = 0;
	Amd* = 1;
	Other* = 2;

	(* CpuInformation.features encoding *)
	PBE* = 21;					(** INTEL: Pending Break Enable *)
	IA64* = 30;					(** INTEL: IA64 Capabilities *)
	TM* = 29;					(** INTEL: Thermal Monitor supported *)
	HTT* = 28;					(** Hyper-Threading Technology *)
	SS* = 27;					(** INTEL: Self-Snoop *)
	SSE2* = 26;					(** SSE2 extensions *)
	SSE* = 25;					(** SSE extensions *)
	FXSR* = 24;					(** FXSAVE and FXRSTOR instructions *)
	MMX* = 23;					(** MMX instructions *)
	ACPI* = 22;					(** INTEL: Thermal Monitor and Software Controlled Clock Facilities supported *)
	DS* = 21;					(** INTEL: Debug Store *)
	CLFLUSH* = 19;				(** CLFLUSH instruction *)
	PSN* = 18;					(** INTEL: Processor serial number is present and enabled *)
	PSE36* = 17;				(** Page-size extension *)
	PAT* = 16;					(** Page attribute table *)
	CMOV* = 15;				(** CMOV & FCMOV conditional move instructions *)
	MCA* = 14;					(** Machine check architecture *)
	PGE* = 13;					(**	Page global extension *)
	MTRR* = 12;				(** Memory-type range registers *)
	SysEnterSysExit* = 11;		(** SYSENTER & SYSEXIT instructions *)
	APIC* = 9;					(** APIC exists and is enabled *)
	CMPXCH8B* = 8;			(** CMPXCHGB8 instruction *)
	MCE* = 7;					(** Machine check exception *)
	PAE* = 6;					(** Physical-address extendions (support for physical addresss > 32b) *)
	MSR* = 5;					(** Model-specific registers with RDMSR & WRMSR instructions *)
	TSC* = 4;					(** Time stamp counter with RDTSC and RDTSCP instruction support *)
	PSE* = 3;					(** Page-size extensions (4MB pages) *)
	DE* = 2;					(** Debugging extensions, I/O breakpoints *)
	VME* = 1;					(** Virtual-mode enhancements *)
	FPU* = 0;					(** Floating point unit on chip *)
	
	(** CpuIformation.features2 encoding *)
	DCA* = 18;					(** INTEL: Direct Access Cache *)
	XTPR* = 14;					(** INTEL: Send Task Priority Messages *)
	CMPXCHG16B* = 13;		(** CMPXCHG16B instruction *)
	CID* = 10;					(** INTEL: Context ID *)
	SSSE3* = 9;					(** INTEL: Supplemental Streaming SIMD Extensions 3 *)
	TM2* = 8;					(** INTEL: Thermal Monitor 2 *)
	EST* = 7;					(** INTEL: Enhanced Intel SpeedStep Technology *)
	VMX* = 5;					(** INTEL: Virtual Machine Extensions *)
	DS_CPL* = 4;				(** INTEL: CPL Qualified Debug Store *)
	MONITOR* = 3;				(** INTEL: Monitor/MWAIT *)
	SSE3* = 0;					(** SSE3 extensions *)
	
	(** CpuInformation.extFeatures encoding (AMD) *)
	Amd3DNow* = 31;			(** AMD: 3DNow! instructions *) 
	Amd3DNowExt* = 32;		(** AMD: AMD extensions to 3DNow! *)
	LM* = 29; 					(** Long Mode supported (64bit support), IA-32e*)
	RDTSCP* = 27;				(** AMD: RDTSCP instruction *)
	FFXSR* = 25;				(** AMD: FXSAVE & FXRSTOR instruction optimizations *)
	MmxExt* = 22;				(** AMD: AMD extensions to MMX instructins *)
	NX* = 20;					(** No-execute page protection *)
	SysCallSysRet* = 11;			(** SYSCALL & SYSRET instructions *)
	(** Bits 24..23, 17..12, 9..0 contain the same information as cpuInfo.features *) 
	
	(** CpuInformation.extFeatures2 encoding (AMD) *)
	AltMovCr8* = 4; 			(** AMD: LOCK MOV CR0 means MOV CR8 *)
	SVM* = 2; 					(** AMD: Secure virtual machine feature *)
	CmpLegacy* = 1; 			(** AMD: Core multi-processing legacy mode *)
	LahfSahf* = 0; 				(** LAHF & SAHF instruction support in 64-bit mode *)
	
	(** CpuInformation.powerManagement encoding (AMD) *)
	AMD7_TscInvariant* = 8;		(** TSC rate is ensured to be invariant across all P-States, C-States and stop-grant transitions *)
	AMD7_STC* = 5;				(** Software Thermal Control is supported *)
	AMD7_TM* = 4;				(** Hardware Thermal Control is supported *)
	AMD7_TTP* = 3;				(** THERMTRIP is supported *)
	AMD7_VID* = 2;				(** Voltage ID control is supported *)
	AMD7_FID* = 1;				(** Frequency ID control is supported *)
	AMD7_TS* = 0;				(** Temperature sensor *)
	
TYPE
	
	CpuInformation* = RECORD
	
		cputype- : LONGINT; (* Intel, Amd or Other *)
		
		(** Standard Function 0: Processor Vendor and Largest Standard Function *)
		largestStandardFunction- : LONGINT;
		vendor- : ARRAY 12 OF CHAR;
		
		(** Standard Function 1: Family, Model, Stepping Identifiers *)
		family-, model-, stepping- : LONGINT;	
		type- : LONGINT; (* INTEL *)

		features-, features2- : SET;

		localApicId-, logicalProcessorCount- : LONGINT;
		clflushSize- : LONGINT; (* specifies the size of a cache line flushed by the CLFLUSH instruction [in bytes] *)
		brandId- : LONGINT;

		(** Extended Function 0: Largest Extended Function *)
		largestExtendedFunction- : LONGINT;
		
		(** Extended Function 1: Features *)
		extFeatures-, extFeatures2- : SET;
		
		(** Extended Function 2-4: Processor name *)	
		processorName- : ARRAY 48 OF CHAR;
		
		
		(** AMD-Specific *)
		
		(** Level 1 Cache and TLB *)
		
		(** L1 2M/4M pages TLB associativity & size *)
		l1DataTlbAssociativity2M4M- : LONGINT;
		l1DataTlbSize2M4M- : LONGINT;
		l1InstrTlbAssociativity2M4M- : LONGINT;
		l1InstrTlbSize2M4M- : LONGINT;
		
		(** L1 4K pages TLB associativity & size *)
		l1DataTlbAssociativity4K- : LONGINT;
		l1DataTlbSize4K- : LONGINT;
		l1InstrTlbAssociativity4K- : LONGINT;
		l1InstrTlbSize4K- : LONGINT;
		
		(** L1 data cache characteristics *)
		l1DcSize- : LONGINT; (* KB *)
		l1DcAssociativity- : LONGINT; 
		l1DcLinesPerTag- : LONGINT; (* AMD *)
		l1DcLineSize- : LONGINT;		

		(** L1 instruction  cache characteristics *)
		l1IcSize- : LONGINT; (* KB *)
		l1IcAssociativity- : LONGINT; 
		l1IcLinesPerTag- : LONGINT; (* AMD *)
		l1IcLineSize- : LONGINT;
		
		(** Level 2 Cache and TLB *)
		
		unifiedTlb- : BOOLEAN; (* if TRUE, one TLB for all  4K/2M/4M pages *)
		
		(** L2 2M/4M pages TLB associativity & size *)
		l2DataTlbAssociativity2M4M- : LONGINT;
		l2DataTlbSize2M4M- : LONGINT;
		l2InstrTlbAssociativity2M4M- : LONGINT;
		l2InstrTlbSize2M4M- : LONGINT;
		
		(** L2 4K pages TLB associativity & size *)
		l2DataTlbAssociativity4K- : LONGINT;
		l2DataTlbSize4K- : LONGINT;
		l2InstrTlbAssociativity4K- : LONGINT;
		l2InstrTlbSize4K- : LONGINT;
		
		l2CacheSize- : LONGINT; (* KB *)
		l2Associativity- : LONGINT; (* encoded *)
		l2LinesPerTag- : LONGINT; (* AMD *)
		l2LineSize- : LONGINT;
		
		(** Extended function 7: Advanced Power Management Information *)
		powerManagement- : SET; (* AMD *)
		
		(** Extended function 8: Long Mode Address Size Identifiers *)
		linAddrSize- : LONGINT; (* maximum linear byte address size in bits *)
		physAddrSize- : LONGINT; (* maximum physical byte address size in bits *)
		apicIdCoreIdSize- : LONGINT; (* AMD *)
		numberOfCores- : LONGINT; (* AMD *)
		
		(** Extended function A: SVM Revision and Feature Identification *)
		svmRev- : LONGINT; (* AMD *)
		nasid- : LONGINT; (** AMD: Number of address space identifiers *)
		
	END;
	
(** CPU identification *)
PROCEDURE CPUID(function : LONGINT; VAR eax, ebx, ecx, edx : SET);
CODE {SYSTEM.i386, SYSTEM.Pentium}
	MOV EAX, function[EBP]	; CPUID function parameter
	CPUID					; execute CPUID
	MOV ESI, eax[EBP]		; copy EAX into eax
	MOV [ESI], EAX
	MOV ESI, ebx[EBP]		; copy EBX into ebx
	MOV [ESI], EBX
	MOV ESI, ecx[EBP]		; copy ECX into ecx
	MOV [ESI], ECX
	MOV ESI, edx[EBP]		; copy EDX into edx
	MOV [ESI], EDX
END CPUID;

(* If the CPUID instruction is supported, the ID flag (bit 21) of the EFLAGS register is r/w *)
PROCEDURE CpuIdSupported() : BOOLEAN;
CODE {SYSTEM.i386}	
	PUSHFD					; save EFLAGS
	POP EAX				; store EFLAGS in EAX
	MOV EBX, EAX			; save EBX for later testing
	XOR EAX, 00200000H	; toggle bit 21
	PUSH EAX				; push to stack
	POPFD					; save changed EAX to EFLAGS
	PUSHFD					; push EFLAGS to TOS
	POP EAX				; store EFLAGS in EAX
	CMP EAX, EBX			; see if bit 21 has changed
	SETNE AL;				; return TRUE if bit 21 has changed, FALSE otherwise
END CpuIdSupported;

(* Standard Function 0: Processor Vendor and Largest Standard Function Number *)
PROCEDURE StandardFunction0(VAR cpuInfo: CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	CPUID(0H, eax, ebx, ecx, edx);
	cpuInfo.largestStandardFunction := SYSTEM.VAL(LONGINT, eax);
	GetString(cpuInfo.vendor, 0, ebx);
	GetString(cpuInfo.vendor, 4, edx);
	GetString(cpuInfo.vendor, 8, ecx);
	IF cpuInfo.vendor = "GenuineIntel" THEN cpuInfo.cputype := Intel;
	ELSIF cpuInfo.vendor = "AuthenticAMD" THEN cpuInfo.cputype := Amd;
	ELSE cpuInfo.cputype := Other;
	END;
END StandardFunction0;

(* Standard Function 1: Family, Model, Stepping Identifiers *)
PROCEDURE StandardFunction1(VAR cpuInfo : CpuInformation);
CONST 
	ExtendedFamily = {20..27}; ExtendedModel = {16..19};
	BaseFamily = {8..11}; BaseModel = {4..7}; BaseStepping = {0..3};
	LocalApicId = {24..31}; LogicalProcessorCount = {16..23}; CLFlush = {8..15}; BrandId = {0..7};
VAR 
	eax, ebx, ecx, edx : SET;
BEGIN		
	CPUID(1H, eax, ebx, ecx, edx);
	(* EAX *)
	cpuInfo.stepping := SYSTEM.VAL(LONGINT, eax * BaseStepping);
	cpuInfo.model := SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * BaseModel, -4));
	cpuInfo.family := SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * BaseFamily, -8));
	IF cpuInfo.family < 0FH THEN
		cpuInfo.family := cpuInfo.family + SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * ExtendedFamily, -20));
		cpuInfo.model := cpuInfo.model + SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * ExtendedModel, -12));
	END;
	(* EBX *)
	cpuInfo.localApicId := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ebx * LocalApicId, -24));
	cpuInfo.logicalProcessorCount := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ebx * LogicalProcessorCount, - 16));
	cpuInfo.clflushSize := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ebx * CLFlush, -8)) * 8;
	cpuInfo.brandId := SYSTEM.VAL(LONGINT, ebx * BrandId);
	(* ECX *)
	cpuInfo.features2 := ecx;
	(* EDX *)
	cpuInfo.features := edx;
	
	IF cpuInfo.cputype = Intel THEN
		cpuInfo.type := SYSTEM.VAL(LONGINT, SYSTEM.LSH(edx * {12..13}, -12));
	END;
END StandardFunction1;

PROCEDURE ExtendedFunction0(VAR cpuInfo : CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	eax := {};
	CPUID(80000000H, eax, ebx, ecx, edx);
	(* The largest extended function as value from offset 8000000H. Since we don't have unsigned integers, ignore the MSB *)
	cpuInfo.largestExtendedFunction := SYSTEM.VAL(LONGINT, eax - {31});
	(* ebx, ecx & edx contain the same information as in standard function 0 *)
END ExtendedFunction0;

PROCEDURE ExtendedFunction1(VAR cpuInfo : CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	CPUID(80000001H, eax, ebx, ecx, edx);
	(* eax contains the same information as in standard function 1 *)
	(* ebx: brandid, ignore so far*)
	cpuInfo.extFeatures2 := ecx;
	cpuInfo.extFeatures := edx;
END ExtendedFunction1;

PROCEDURE ExtendedFunction2to4(VAR cpuInfo : CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	CPUID(80000002H, eax, ebx, ecx, edx);
	GetString(cpuInfo.processorName, 0, eax);
	GetString(cpuInfo.processorName, 4, ebx);
	GetString(cpuInfo.processorName, 8, ecx);
	GetString(cpuInfo.processorName, 12, edx);
	IF cpuInfo.largestExtendedFunction < 3 THEN RETURN END;
	CPUID(80000003H, eax, ebx, ecx, edx);
	GetString(cpuInfo.processorName, 16, eax);
	GetString(cpuInfo.processorName, 20, ebx);
	GetString(cpuInfo.processorName, 24, ecx);
	GetString(cpuInfo.processorName, 28, edx);
	IF cpuInfo.largestExtendedFunction < 4 THEN RETURN END;
	CPUID(80000004H, eax, ebx, ecx, edx);
	GetString(cpuInfo.processorName, 32, eax);
	GetString(cpuInfo.processorName, 36, ebx);
	GetString(cpuInfo.processorName, 40, ecx);
	GetString(cpuInfo.processorName, 44, edx);
END ExtendedFunction2to4;

PROCEDURE AmdExtendedFunction5(VAR cpuInfo : CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	CPUID(80000005H, eax, ebx, ecx, edx);
	(* EAX *)
	cpuInfo.l1DataTlbAssociativity2M4M := SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * {24..31}, -24));
	cpuInfo.l1DataTlbSize2M4M := SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * {16..23}, -16));
	cpuInfo.	l1InstrTlbAssociativity2M4M := SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * {8..15}, -8));
	cpuInfo.	l1InstrTlbSize2M4M := SYSTEM.VAL(LONGINT, eax * {0..7});
	(* EBX *)
	cpuInfo.l1DataTlbAssociativity4K := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ebx * {24..31}, -24));
	cpuInfo.l1DataTlbSize4K := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ebx * {16..23}, -16));
	cpuInfo.l1InstrTlbAssociativity4K := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ebx * {8..15}, -8));
	cpuInfo.l1InstrTlbSize4K := SYSTEM.VAL(LONGINT, ebx * {0..7});
	(* ECX *)
	cpuInfo.l1DcSize := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ecx * {24..31}, -24));
	cpuInfo.l1DcAssociativity := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ecx * {16..23}, -16));
	cpuInfo.l1DcLinesPerTag := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ecx * {8..15}, -8));
	cpuInfo.l1DcLineSize := SYSTEM.VAL(LONGINT, ecx * {0..7});
	(* EDX *)
	cpuInfo.l1IcSize := SYSTEM.VAL(LONGINT, SYSTEM.LSH(edx * {24..31}, -24));
	cpuInfo.l1IcAssociativity := SYSTEM.VAL(LONGINT, SYSTEM.LSH(edx * {16..23}, -16));
	cpuInfo.l1IcLinesPerTag := SYSTEM.VAL(LONGINT, SYSTEM.LSH(edx * {8..15}, -8));
	cpuInfo.l1IcLineSize := SYSTEM.VAL(LONGINT, edx * {0..7});
END AmdExtendedFunction5;

(** AMD: L2 Cache and TLB Identifiers *)
PROCEDURE AmdExtendedFunction6(VAR cpuInfo : CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	CPUID(80000006H, eax, ebx, ecx, edx);
	cpuInfo.unifiedTlb := (eax * {16..31} = {}) & (ebx * {16..31} = {});
	
	IF ~cpuInfo.unifiedTlb THEN
		cpuInfo.l2DataTlbAssociativity2M4M := SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * {28..31}, -28));
		cpuInfo.l2DataTlbSize2M4M := SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * {16..27}, -16));
		cpuInfo.l2InstrTlbAssociativity2M4M := SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * {12..15}, -12));
		cpuInfo.l2InstrTlbSize2M4M := SYSTEM.VAL(LONGINT, eax * {0..11});
	END;
			
	cpuInfo.l2DataTlbAssociativity4K := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ebx * {28..31}, -28));
	cpuInfo.l2DataTlbSize4K := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ebx * {16..27}, -16));
	cpuInfo.l2InstrTlbAssociativity4K := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ebx * {12..15}, -12));
	cpuInfo.l2InstrTlbSize4K := SYSTEM.VAL(LONGINT, ebx * {0..11});
	
	cpuInfo.l2CacheSize := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ecx * {16..31}, -16));
	cpuInfo.l2Associativity := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ecx * {12..15}, -12));
	cpuInfo.l2LinesPerTag := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ecx * {8..11}, -8));
	cpuInfo.l2LineSize := SYSTEM.VAL(LONGINT, ecx * {0..7});
END AmdExtendedFunction6;

(* INTEL: Extended L2 Cache Features *)
PROCEDURE IntelExtendedFunction6(VAR cpuInfo : CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	CPUID(80000006H, eax, ebx, ecx, edx);
	cpuInfo.l2CacheSize := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ecx * {16..31}, -16));
	cpuInfo.l2Associativity := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ecx * {12..15}, -12)); 
	cpuInfo.l2LineSize := SYSTEM.VAL(LONGINT, ecx * {0..7});
END IntelExtendedFunction6;

(* AMD: Advanced Power Management Information *)
PROCEDURE AmdExtendedFunction7(VAR cpuInfo : CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	CPUID(80000007H, eax, ebx, ecx, edx);
	cpuInfo.powerManagement := edx;
END AmdExtendedFunction7;

(* Long Mode Address Size Identifiers *)
PROCEDURE ExtendedFunction8(VAR cpuInfo : CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	CPUID(80000008H, eax, ebx, ecx, edx);
	cpuInfo.linAddrSize := SYSTEM.VAL(LONGINT, SYSTEM.LSH(eax * {8..15}, -8));
	cpuInfo.physAddrSize := SYSTEM.VAL(LONGINT, eax * {0..7});
	IF cpuInfo.cputype = Amd THEN
		cpuInfo.apicIdCoreIdSize := SYSTEM.VAL(LONGINT, SYSTEM.LSH(ecx * {12..15}, -12));
		cpuInfo.numberOfCores := SYSTEM.VAL(LONGINT, ecx * {0..7}) + 1;
	END;
END ExtendedFunction8;

(* AMD: SVM Revision and Feature Identification *)
PROCEDURE AmdExtendedFunctionA(VAR cpuInfo : CpuInformation);
VAR eax, ebx, ecx, edx : SET;
BEGIN
	CPUID(8000000AH, eax, ebx, ecx, edx);
	cpuInfo.svmRev := SYSTEM.VAL(LONGINT, eax * {0..7});
	cpuInfo.nasid := SYSTEM.VAL(LONGINT, ebx);
END AmdExtendedFunctionA;

PROCEDURE GetString(VAR string : ARRAY OF CHAR; offset : LONGINT; register : SET);
BEGIN
	string[offset] :=CHR(SYSTEM.VAL(LONGINT, register * {0..7}));
	string[offset+1] := CHR(SYSTEM.VAL(LONGINT, SYSTEM.LSH(register * {8..15}, -8)));
	string[offset+2] := CHR(SYSTEM.VAL(LONGINT, SYSTEM.LSH(register * {16..23}, -16)));
	string[offset+3] := CHR(SYSTEM.VAL(LONGINT, SYSTEM.LSH(register * {24..31}, -24)));
END GetString;

PROCEDURE GetCpuInformation(VAR cpuInfo : CpuInformation);
BEGIN
	StandardFunction0(cpuInfo);
	IF cpuInfo.largestStandardFunction >= 1 THEN StandardFunction1(cpuInfo); END;
	ExtendedFunction0(cpuInfo);
	IF cpuInfo.largestExtendedFunction >= 1 THEN
		ExtendedFunction1(cpuInfo);
		IF cpuInfo.largestExtendedFunction >= 2 THEN
			ExtendedFunction2to4(cpuInfo);
			IF cpuInfo.largestExtendedFunction >= 5 THEN
				IF cpuInfo.cputype = Amd THEN AmdExtendedFunction5(cpuInfo); END;
				IF cpuInfo.largestExtendedFunction >= 6 THEN
					IF cpuInfo.cputype = Amd THEN 
						AmdExtendedFunction6(cpuInfo); 
					ELSE
						IntelExtendedFunction6(cpuInfo);
					END;
					
					IF cpuInfo.largestExtendedFunction >= 7 THEN
						IF cpuInfo.cputype = Amd THEN AmdExtendedFunction7(cpuInfo); END;
						IF cpuInfo.largestExtendedFunction >= 8 THEN
							ExtendedFunction8(cpuInfo);
							IF cpuInfo.largestExtendedFunction >= 0AH THEN
								IF cpuInfo.cputype = Amd THEN AmdExtendedFunctionA(cpuInfo); END;
							END;
						END;
					END;
				END;
			END;
		END;
	END;
END GetCpuInformation;
	
PROCEDURE ShowExtFeatures2Amd(register : SET);
BEGIN
	IF AltMovCr8 IN register THEN AosOut.String("[AltMovCR8]"); END;
	IF SVM IN register THEN AosOut.String("[SVM]"); END;
	IF CmpLegacy IN register THEN AosOut.String("[CMP legacy]"); END;
	IF LahfSahf IN register THEN AosOut.String("[LahfSahf]"); END;
END ShowExtFeatures2Amd;

PROCEDURE ShowExtFeaturesAmd(register : SET);
BEGIN
	IF Amd3DNow IN register THEN AosOut.String("[3DNow!]"); END;
	IF Amd3DNowExt IN register THEN AosOut.String("[3DNow!Ext]"); END;
	IF LM IN register THEN AosOut.String("[LongMode]"); END;
	IF RDTSCP IN register THEN AosOut.String("[RDTSCP]"); END;
	IF FFXSR IN register THEN AosOut.String("[FFXSR]"); END;
	IF MmxExt IN register THEN AosOut.String("[MMXExt]"); END;
	IF NX IN register THEN AosOut.String("[NX]"); END;
	IF SysCallSysRet IN register THEN AosOut.String("[SysCallSysRet]"); END;
END ShowExtFeaturesAmd;

PROCEDURE ShowPowerManagementAmd(register : SET);
BEGIN
	IF AMD7_TscInvariant IN register THEN AosOut.String("[TSCInvariant]"); END;
	IF AMD7_STC IN register THEN AosOut.String("[STC]"); END;
	IF AMD7_TM IN register THEN AosOut.String("[TM]"); END;
	IF AMD7_TTP IN register THEN AosOut.String("[TTP]"); END;
	IF AMD7_VID IN register THEN AosOut.String("[VID]"); END;
	IF AMD7_FID IN register THEN AosOut.String("[FID]"); END;
	IF AMD7_TS IN register THEN AosOut.String("[TS]"); END;
END ShowPowerManagementAmd;

PROCEDURE ShowLongModeAS(cpuInfo : CpuInformation);
BEGIN
	AosOut.String("   Maximum linear byte address size: "); AosOut.Int(cpuInfo.linAddrSize, 0); AosOut.String(" bits"); AosOut.Ln;
	AosOut.String("   Maximum physical byte address size: "); AosOut.Int(cpuInfo.physAddrSize, 0); AosOut.String(" bits"); AosOut.Ln;
	IF cpuInfo.cputype = Amd THEN
		AosOut.String("   APIC ID Core ID Size: "); AosOut.Int(cpuInfo.apicIdCoreIdSize, 0); AosOut.String(" bits"); AosOut.Ln;
		AosOut.String("   Number of CPU cores: "); AosOut.Int(cpuInfo.numberOfCores, 0);
	END;
END ShowLongModeAS;

PROCEDURE ShowFeatures2(register : SET);
BEGIN
	IF DCA IN register THEN AosOut.String("[DCA]"); END; (* INTEL *)
	IF XTPR IN register THEN AosOut.String("[xTPR]"); END; (* INTEL *)
	IF CMPXCHG16B IN register THEN AosOut.String("[CMPXCHG16B]"); END;
	IF CID IN register THEN AosOut.String("[CID]"); END; (* INTEL *)
	IF SSSE3 IN register THEN AosOut.String("[SSSE3]"); END; (* INTEL *)
	IF TM2 IN register THEN AosOut.String("[TM2]"); END; (* INTEL *)
	IF EST IN register THEN AosOut.String("[EST]"); END; (* INTEL *)
	IF VMX IN register THEN AosOut.String("[VMX]"); END; (* INTEL *)
	IF DS_CPL IN register THEN AosOut.String("[DS_CPL]"); END; (* INTEL *)
	IF MONITOR IN register THEN AosOut.String("[MONITOR]"); END; (* INTEL *)
	IF SSE3 IN register THEN AosOut.String("[SSE3]"); END;
END ShowFeatures2;

PROCEDURE ShowFeatures(register : SET);
BEGIN
	IF PBE IN register THEN AosOut.String("[PBE]"); END; (* INTEL *)
	IF IA64 IN register THEN AosOut.String("[IA64]"); END; (* INTEL *)
	IF TM IN register THEN AosOut.String("[TM]"); END; (* INTEL *)
	IF HTT IN register THEN AosOut.String("[HTT]"); END;
	IF SS IN register THEN AosOut.String("[SelfSnoop]"); END; (* INTEL *)
	IF SSE2 IN register THEN AosOut.String("[SSE2]"); END;
	IF SSE IN register THEN AosOut.String("[SSE]"); END;
	IF FXSR IN register THEN AosOut.String("[FXSR]"); END;
	IF MMX IN register THEN AosOut.String("[MMX]"); END;
	IF ACPI IN register THEN AosOut.String("[ACPI]"); END; (* INTEL *)
	IF DS IN register THEN AosOut.String("[DebugStore]"); END; (* INTEL *)
	IF CLFLUSH IN register THEN AosOut.String("[CLFLUSH]"); END;
	IF PSN IN register THEN AosOut.String("[ProcessorSerialNumber]"); END; (* INTEL *)
	IF PSE36 IN register THEN AosOut.String("[PSE36]"); END;
	IF PAT IN register THEN AosOut.String("[PAT]"); END;
	IF CMOV IN register THEN AosOut.String("[CMOV]"); END;
	IF MCA IN register THEN AosOut.String("[MCA]"); END;
	IF PGE IN register THEN AosOut.String("[PGE]"); END;
	IF MTRR IN register THEN AosOut.String("[MTRR]"); END;
	IF SysEnterSysExit IN register THEN AosOut.String("[SysEnterSysExit]"); END;
	IF APIC IN register THEN AosOut.String("[APIC]"); END;
	IF CMPXCH8B IN register THEN AosOut.String("[CMPXCH8B]"); END;
	IF MCE IN register THEN AosOut.String("[MCE]"); END;
	IF PAE IN register THEN AosOut.String("[PAE]"); END;
	IF MSR IN register THEN AosOut.String("[MSR]"); END;
	IF TSC IN register THEN AosOut.String("[TSC]"); END;
	IF PSE IN register THEN AosOut.String("[PSE]"); END;
	IF DE IN register THEN AosOut.String("[DE]"); END;
	IF VME IN register THEN AosOut.String("[VME]"); END;
	IF FPU IN register THEN AosOut.String("[FPU]"); END;
END ShowFeatures;

PROCEDURE ShowL1Associativity(value : LONGINT);
BEGIN
	IF value = 0 THEN AosOut.String("Reserved");
	ELSIF value = 1 THEN AosOut.String("Direct mapped");
	ELSIF value = 0FFH THEN AosOut.String("Fully associative");
	ELSE
		AosOut.Int(value, 0); AosOut.String("-way associative"); 
	END;
END ShowL1Associativity;

PROCEDURE ShowL2Associativity(value : LONGINT);
BEGIN
	IF value = 0 THEN AosOut.String("disabled");
	ELSIF value = 1 THEN AosOut.String("Direct mapped"); 
	ELSIF value = 2 THEN AosOut.String("2-way associative");
	ELSIF value = 4 THEN AosOut.String("4-way associative");
	ELSIF value = 6 THEN AosOut.String("8-way associative");
	ELSIF value = 8 THEN AosOut.String("16-way associative");
	ELSIF value = 0FH THEN AosOut.String("Fully associative");
	ELSE AosOut.String("unknown");
	END;
END ShowL2Associativity;

PROCEDURE AmdShowL1TlbAndCache(cpuInfo : CpuInformation);
BEGIN
	AosOut.String("   TLB: "); AosOut.Ln;
	AosOut.String("      2M/4M Data TLB: "); AosOut.Int(cpuInfo.l1DataTlbSize2M4M, 0); AosOut.String(" entries, "); 
	ShowL1Associativity(cpuInfo.l1DataTlbAssociativity2M4M);
	AosOut.Ln;
	AosOut.String("      2M/4M Instr TLB: "); AosOut.Int(cpuInfo.l1InstrTlbSize2M4M, 0); AosOut.String(" entries, ");
	ShowL1Associativity(cpuInfo.l1InstrTlbAssociativity2M4M);
	AosOut.Ln;
	AosOut.String("      4K Data TLB: "); AosOut.Int(cpuInfo.l1DataTlbSize4K, 0); AosOut.String(" entries, ");
	ShowL1Associativity(cpuInfo.l1DataTlbAssociativity4K);
	AosOut.Ln;
	AosOut.String("      4K Instr TLB: ");  AosOut.Int(cpuInfo.l1InstrTlbSize4K, 0); AosOut.String(" entries, ");
	ShowL1Associativity(cpuInfo.l1InstrTlbAssociativity4K);
	AosOut.Ln;
	AosOut.String("   Level 1 cache: "); AosOut.Ln;
	AosOut.String("      Data: "); AosOut.Int(cpuInfo.l1DcSize, 0); AosOut.String("KB, "); ShowL1Associativity(cpuInfo.l1DcAssociativity);
	AosOut.String(", Lines per Tag: "); AosOut.Int(cpuInfo.l1DcLinesPerTag, 0); AosOut.String(", Line size: "); AosOut.Int(cpuInfo.l1DcLineSize, 0);
	AosOut.String(" Bytes"); 
	AosOut.Ln;
	AosOut.String("      Instr: "); AosOut.Int(cpuInfo.l1IcSize, 0); AosOut.String("KB, "); ShowL1Associativity(cpuInfo.l1IcAssociativity);
	AosOut.String(", Lines per Tag: "); AosOut.Int(cpuInfo.l1IcLinesPerTag, 0); 
	AosOut.String(", Line size: "); AosOut.Int(cpuInfo.l1IcLineSize, 0); AosOut.String(" Bytes");
END AmdShowL1TlbAndCache;

PROCEDURE AmdShowL2TlbAndCache(cpuInfo : CpuInformation);
BEGIN
	AosOut.String("   TLB: "); AosOut.Ln;
	IF ~cpuInfo.unifiedTlb THEN
		AosOut.String("      2M/4M Data TLB: "); AosOut.Int(cpuInfo.l2DataTlbSize2M4M, 0); AosOut.String(" entries, ");
		ShowL2Associativity(cpuInfo.l2DataTlbAssociativity2M4M);
		AosOut.Ln;
		AosOut.String("      2M/4M Instr TLB: "); AosOut.Int(cpuInfo.l2InstrTlbSize2M4M, 0); AosOut.String(" entries, "); 
		ShowL2Associativity(cpuInfo.l2InstrTlbAssociativity2M4M);
		AosOut.Ln;
	ELSE
		AosOut.String("Unified TLB for 4K/2M/4M: "); AosOut.Ln;
	END;
	AosOut.String("      4K Data TLB: "); AosOut.Int(cpuInfo.l2DataTlbSize4K, 0); AosOut.String(" entries, ");
	ShowL2Associativity(cpuInfo.l2DataTlbAssociativity4K);
	AosOut.Ln;
	AosOut.String("      4K Instr TLB: "); AosOut.Int(cpuInfo.l2InstrTlbSize4K, 0); AosOut.String(" entries, "); 
	ShowL2Associativity(cpuInfo.l2InstrTlbAssociativity4K);
	AosOut.Ln;
	AosOut.String("   Level 2 cache: "); AosOut.Ln;
	AosOut.String("      Size: "); AosOut.Int(cpuInfo.l2CacheSize, 0); AosOut.String("KB, ");
	ShowL2Associativity(cpuInfo.l2Associativity);
	IF cpuInfo.cputype = Amd THEN 
		AosOut.String(", Lines per Tag: "); AosOut.Int(cpuInfo.l2LinesPerTag, 0); 
	END;
	AosOut.String(", Line size: "); AosOut.Int(cpuInfo.l2LineSize, 0); AosOut.String(" Bytes"); 
END AmdShowL2TlbAndCache;

PROCEDURE AmdShowSVM(cpuInfo : CpuInformation);
BEGIN
	AosOut.String("   SVM Revision: "); AosOut.Hex(cpuInfo.svmRev, -2); AosOut.String("H"); AosOut.Ln;
	AosOut.String("   Number of address space identifiers (ASID): "); AosOut.Int(cpuInfo.nasid, 0); AosOut.Ln;
END AmdShowSVM;

PROCEDURE IntelShowCacheDescriptors;
VAR eax, ebx, ecx, edx : SET; i : LONGINT;

	PROCEDURE ShowReg(reg : SET; isEax : BOOLEAN);
	BEGIN
		IF 31 IN reg THEN
			IF ~isEax THEN
				IF reg * {0..7} # {} THEN AosOut.String(GetCacheIntel(SYSTEM.VAL(LONGINT, reg * {0..7}))); AosOut.Ln; END;
			END;
			IF reg * {8..15} # {} THEN AosOut.String(GetCacheIntel(SYSTEM.VAL(LONGINT, reg * {8..15}))); AosOut.Ln; END;
			IF reg * {16..23} # {} THEN AosOut.String(GetCacheIntel(SYSTEM.VAL(LONGINT, reg * {16..23}))); AosOut.Ln; END;
			IF reg * {24..31} # {} THEN AosOut.String(GetCacheIntel(SYSTEM.VAL(LONGINT, reg * {24..31}))); AosOut.Ln; END;
		END;
	END ShowReg;

BEGIN
	CPUID(2H, eax, ebx, ecx, edx);
	ShowReg(eax, TRUE);
	ShowReg(ebx, FALSE);
	ShowReg(ecx, FALSE);
	ShowReg(edx, FALSE);
	
	i := SYSTEM.VAL(LONGINT, eax * {0..7}) - 1;
	
	WHILE (i > 0) DO
		CPUID(2H, eax, ebx, ecx, edx);
		ShowReg(eax, TRUE);
		ShowReg(ebx, FALSE);
		ShowReg(ecx, FALSE);
		ShowReg(edx, FALSE);		
		DEC(i);
	END;
END IntelShowCacheDescriptors;

TYPE Str128 = ARRAY 128 OF CHAR;
PROCEDURE GetCacheIntel*(value : LONGINT) : Str128;
VAR s : Str128;
BEGIN
	CASE value OF
		|00H:	s := "Null";
		|01H:	s := "Instruction TLB: 4KB Pages, 4-way set associative, 32 entries";
		|02H:	s := "Instruction TLB: 4MB Pages, fully associative, 2 entries";
		|03H:	s := "Data TLB: 4KB Pages, 4-way set associative, 64 entries";
		|04H:	s := "Data TLB: 4MB Pages, 4-way set associative, 8 entries";
		|05H:	s := "DataTLB: 4MB Pages, 4-way set associative, 32 entries";
		|06H:	s := "L1 instruction cache, 8KB, 4-way set associative, 32 byte line size";
		|08H:	s := "L1 instruction cache, 16KB, 4-way set associative, 32-byte line size";
		|0AH:	s := "L1 data cache, 8KB, 2-way set associative, 32-byte line size";
		|0CH:	s := "L1 data cache, 16KB, 4-way set associative, 32-byte line size";
		|22H:	s := "L3 cache, 512KB, 4-way set associative, sectored cache, 64-byte line size";
		|23H:	s := "L3 cache, 1MB, 8-way set associative, sectored cache, 64-byte line size";
		|25H:	s := "L3 cache, 2MB, 8-way set associative, sectored cache, 64-byte line size";
		|29H:	s := "L3 cache, 4MB, 8-way set associative, sectored cache, 64-byte line size";
		|2CH:	s := "L1 data cache, 32KB, 8-way set associative, 64-byte line size";
		|30H:	s := "L1 instruction cache, 32KB, 8-way set associative, 64-byte line size";
		|39H:	s := "L2 cache, 128KB, 4-way set associative, sectored cache, 64-byte line size";
		|3AH:	s := "L2 cache, 192KB, 6-way set associative, sectored cache, 64-byte line size";
		|3BH:	s := "L2 cache, 128KB, 2-way set associative, sectored cache, 64-byte line size";
		|3CH:	s := "L2 cache, 256KB, 4-way set associative, sectored cache, 64-byte line size";
		|3DH:	s := "L2 cache, 384KB, 6-way set associative, sectored cache, 64-byte line size";
		|3EH:	s := "L2 cache, 512KB, 4-way set associative, sectored cache, 64-byte line size";
		|40H:	s := "No L2 cache or, if processor contains valid L2 cache, no L2 cache";
		|41H:	s := "L2 cache, 128KB, 4-way set associative, 32-byte line size";
		|42H:	s := "L2 cache, 256KB, 4-way set associative, 32-byte line size";
		|43H:	s := "L2 cache, 512KB, 4-way set associative, 32-byte line size";
		|44H:	s := "L2 cache, 1MB, 4-way set associative, 32-byte line size";
		|45H:	s := "L2 cache, 2MB, 4-way set associative, 32-byte line size";
		|46H:	s := "L3 cache, 4MB, 4-way set associative, 64-byte line size";
		|47H:	s := "L3 cache, 8MB, 8-way set associative, 64-byte line size";
		|49H:	s := "L2 cache, 4MB, 16-way set associative, 64-byte line size";
		|4AH:	s := "L3 cache, 6MB, 12-way set associative, 64-byte line size";
		|4BH:	s := "L3 cache, 8MB, 16-way set associative, 64-byte line size";
		|4CH:	s := "L3 cache, 12MB, 12-way set associative, 64-byte line size";
		|4DH:	s := "L3 cache, 16MB, 16-way set associative, 64-byte line size";
		|50H:	s := "Instruction TLB: 4KB, 2MB or 4MB pages, fully associative, 64 entries";
		|51H:	s := "Instruction TLB: 4KB, 2MB or 4MB pages, fully associative, 128 entries";
		|52H:	s := "Instruction TLB: 4KB, 2MB or 4MB pages, fully associative, 256 entries";
		|56H:	s := "L0 Data TLB: 4MB pages, 4-way set associative, 16 entries";
		|57H:	s := "L0 Data TLB: 4MB pages, 4-way set associative, 16 entries";
		|5BH:	s := "Data TLB: 4KB or 4MB pages, fully associative, 64 entries";
		|5CH:	s := "Data TLB: 4KB or 4MB pages, fully associative, 128 entries";
		|5DH:	s := "Data TLB: 4KB or 4MB pages, fully associative, 256 entries";
		|60H:	s := "L1 data cache, 16KB, 8-way set associative, sectored cache, 64-byte line size";
		|66H:	s := "L1 data cache, 8KB, 4-way set associative, sectored cache, 64-byte line size";
		|67H:	s := "L1 data cache, 16KB, 4-way set associative, sectored cache, 64-byte line size";
		|68H:	s := "L1 data cache, 32KB, 4-way set associative, sectored cache, 64-byte line size";
		|70H:	s := "Trace cache: 12 Kuops, 8-way set associative";
		|71H:	s := "Trace cache: 16 Kuops, 8-way set associative";
		|72H:	s := "Trace cache: 32 Kuops, 8-way set associative";
		|73H:	s := "Trace cache: 64 Kuops, 8-way set associative";
		|78H:	s := "L2 cache, 1MB, 4-way set associative, 64-byte line size";
		|79H:	s := "L2 cache, 128KB, 8-way set associative, sectored cache, 64-byte line size";
		|7AH:	s := "L2 cache, 256KB, 8-way set associative, sectored cache, 64-byte line size";
		|7BH:	s := "L2 cache, 512KB, 8-way set associative, sectored cache, 64-byte line size";
		|7CH:	s := "L2 cache, 1MB, 8-way set associative, sectored cache, 64-byte line size";
		|7DH:	s := "L2 cache, 2MB, 8-way set associative, 64-byte line size";
		|7FH:	s := "L2 cache, 512KB, 2-way set associative, 64-byte line size";
		|82H:	s := "L2 cache, 256KB, 8-way set associative, 32-byte line size";
		|83H:	s := "L2 cache, 512KB, 8-way set associative, 32-byte line size";
		|84H:	s := "L2 cache, 1MB, 8-way set associative, 32-byte line size";
		|85H:	s := "L2 cache, 2MB, 8-way set associative, 32-byte line size";
		|86H:	s := "L2 cache, 512KB, 4-way set associative, 64-byte line size";
		|87H:	s := "L2 cache, 1MB, 8-way set associative, 64-byte line size";
		|0B0H:	s := "Instruction TLB: 4KB Pages, 4-way set associative, 128 entries";
		|0B1H:	s := "Instruction TLB: 2M/4M pages, 4-way set associative, 2M: 4 entries, 4M: 8 entries";
		|0B3H:	s := "Data TLB: 4KB pages, 4-way set associative, 128 entries";
		|0B4H:	s := "Data TLB: 4KB pages, 4-way set associative, 256 entries";		
		|0F0H:	s := "64-byte Prefetching";
		|0F1H:	s := "128-byte Prefetching";		
	ELSE
		s := "Entry not defined";
	END;
	RETURN s;
END GetCacheIntel;

PROCEDURE ShowDetailedCpuInformation(cpuInfo : CpuInformation);
BEGIN
	AosOut.String("Standard Function 0: Processor Vendor and Largest Standard Function: "); AosOut.Ln;
	AosOut.String("   Vendor: "); AosOut.String(cpuInfo.vendor); AosOut.Ln;
	AosOut.String("   Largest Standard Function: "); AosOut.Int(cpuInfo.largestStandardFunction, 0); AosOut.Ln;
	AosOut.Ln;
	IF cpuInfo.largestStandardFunction >= 1 THEN
		AosOut.String("Standard Function 1: Family, Model, Stepping Identifiers: "); AosOut.Ln;
		AosOut.String("   Family: "); AosOut.Int(cpuInfo.family, 0); AosOut.String(", Model: "); AosOut.Int(cpuInfo.model, 0); 
		AosOut.String(", Stepping: "); AosOut.Int(cpuInfo.stepping, 0); 
		IF cpuInfo.cputype = Intel THEN
			AosOut.String(", type: "); AosOut.Int(cpuInfo.type, 0);
			CASE cpuInfo.type OF
				|0: AosOut.String(" (Original OEM processor)");
				|1: AosOut.String(" (OverDrive processor)");
				|2: AosOut.String(" (Dual processor)");
				|3: AosOut.String(" (Intel reserved)");
			ELSE
				AosOut.String(" (Out of range)");
			END;
		END;
		AosOut.Ln;
		AosOut.String("   Local APIC Initial ID: "); AosOut.Int(cpuInfo.localApicId, 0);
		AosOut.String(", Logical processor count: "); AosOut.Int(cpuInfo.logicalProcessorCount, 0); 
		AosOut.Ln;
		AosOut.String("   CLFLUSH line size: "); AosOut.Int(cpuInfo.clflushSize, 0); AosOut.String(" Bytes"); 
		AosOut.String(", BrandId: "); AosOut.Int(cpuInfo.brandId, 0);
		AosOut.Ln;
		AosOut.String("   Features: "); ShowFeatures2(cpuInfo.features2); ShowFeatures(cpuInfo.features); AosOut.Ln;
		AosOut.Ln;
	END;
	
	IF (cpuInfo.largestStandardFunction >= 2) & (cpuInfo.cputype = Intel) THEN
		AosOut.String("Standard Function 2: Cache Descriptors: "); AosOut.Ln;
		IntelShowCacheDescriptors;
	END;
	
	AosOut.String("Extended Function 0: Largest Extended Function: "); AosOut.Ln;
	AosOut.String("   Largest Extended Function: "); AosOut.Int(cpuInfo.largestExtendedFunction, 0); AosOut.Ln;
	AosOut.Ln;
	
	IF cpuInfo.largestExtendedFunction >= 1 THEN
		AosOut.String("Extended Function 1: Features: "); AosOut.Ln;
		AosOut.String("   Extended features: "); ShowExtFeatures2Amd(cpuInfo.extFeatures2); ShowExtFeaturesAmd(cpuInfo.extFeatures); AosOut.Ln;
		AosOut.Ln;		
	END;
	
	IF cpuInfo.largestExtendedFunction >= 2 THEN
		AosOut.String("Extended Function 2-4: Processor Name: "); AosOut.Ln;
		AosOut.String("   Processor Name: "); AosOut.String(cpuInfo.processorName); AosOut.Ln;
		AosOut.Ln;		
	END;
	
	IF cpuInfo.largestExtendedFunction < 5 THEN RETURN; END;
	
	IF cpuInfo.cputype = Amd THEN
		AosOut.String("AMD Extended Function 5: L1 Cache and TLB Identifiers: "); AosOut.Ln;
		AmdShowL1TlbAndCache(cpuInfo); AosOut.Ln;
		AosOut.Ln;
	END;
	
	IF cpuInfo.largestExtendedFunction < 6 THEN RETURN; END;
	
	IF cpuInfo.cputype = Amd THEN
		AosOut.String("AMD Extended Function 6: L2 Cache and TLB Identifiers: "); AosOut.Ln;
		AmdShowL2TlbAndCache(cpuInfo); AosOut.Ln;
		AosOut.Ln;
	END;
	
	IF cpuInfo.largestExtendedFunction < 7 THEN RETURN END;
	
	IF cpuInfo.cputype = Amd THEN
		AosOut.String("AMD Extended Function 7: Advanced Power Management Information: "); AosOut.Ln;
		AosOut.String("   Features: "); ShowPowerManagementAmd(cpuInfo.powerManagement); AosOut.Ln;
		AosOut.Ln;
	END;
	
	IF cpuInfo.largestExtendedFunction < 8 THEN RETURN; END;
	
	IF cpuInfo.cputype = Amd THEN
		AosOut.String("AMD Extended Function 8: Long Mode Address Size Identifiers: "); AosOut.Ln;
		ShowLongModeAS(cpuInfo); AosOut.Ln;
		AosOut.Ln;	
	END;
	
	IF cpuInfo.largestExtendedFunction < 0AH THEN RETURN END;
	
	IF cpuInfo.cputype = Amd THEN
		AosOut.String("AMD Extended Function A: SVM Revision and Feature Identification: "); AosOut.Ln;
		AmdShowSVM(cpuInfo); AosOut.Ln;
		AosOut.Ln;
	END;
	
END ShowDetailedCpuInformation;

PROCEDURE ShowCpuInformation(cpuInfo : CpuInformation);
	
	PROCEDURE ShowFlag(flag : LONGINT; register : SET);
	BEGIN
		IF flag IN register THEN AosOut.String("Yes"); ELSE AosOut.String("No"); END;
	END ShowFlag;	

BEGIN
	IF cpuInfo.largestExtendedFunction >= 2 THEN
		AosOut.String("Prozessor: "); AosOut.String(cpuInfo.processorName); AosOut.Ln;
	END;
	AosOut.String("   Vendor: "); AosOut.String(cpuInfo.vendor);
	IF cpuInfo.largestStandardFunction >= 1 THEN
		AosOut.String(", Family: "); AosOut.Hex(cpuInfo.family, -2); AosOut.Char("H");
		AosOut.String(", Model: "); AosOut.Hex(cpuInfo.model, -2); AosOut.Char("H");
		AosOut.String(", Stepping: "); AosOut.Hex(cpuInfo.stepping, -2); AosOut.Char("H");
		AosOut.Ln;
		IF HTT IN cpuInfo.features THEN
			AosOut.String("Logical processor count: "); AosOut.Int(cpuInfo.logicalProcessorCount, 0); AosOut.Ln;
		END;
		AosOut.String("Features: "); AosOut.Ln;
		AosOut.String("   MMX: "); ShowFlag(MMX, cpuInfo.features);
		AosOut.String(", SSE: "); ShowFlag(SSE, cpuInfo.features);
		AosOut.String(", SSE2: "); ShowFlag(SSE2, cpuInfo.features);
		AosOut.String(", SSE3: "); ShowFlag(SSE3, cpuInfo.features2);
		AosOut.String(", Supplemental SSE3: "); ShowFlag(SSSE3, cpuInfo.features2);
	END;
	AosOut.Ln;
	IF cpuInfo.largestExtendedFunction >= 1 THEN
		AosOut.String("   Extended 3DNow!: "); ShowFlag(Amd3DNowExt, cpuInfo.extFeatures);
		AosOut.String(", 3DNow!: "); ShowFlag(Amd3DNow, cpuInfo.extFeatures);
		AosOut.String(", AMD MMX Extensions: "); ShowFlag(MmxExt, cpuInfo.extFeatures);
		AosOut.Ln;
		AosOut.String("   64bit instructions: "); ShowFlag(LM, cpuInfo.extFeatures);
		AosOut.Ln;
	END;
	IF (cpuInfo.cputype = Amd) & (cpuInfo.largestExtendedFunction >= 8) THEN
		AosOut.String("   Number of CPU cores: "); AosOut.Int(cpuInfo.numberOfCores, 0); AosOut.Ln;
	END;
END ShowCpuInformation;

PROCEDURE ShowDetailed*(par : ANY) : ANY;
VAR cpuInfo : CpuInformation;
BEGIN
	IF CpuIdSupported() THEN
		GetCpuInformation(cpuInfo);
		ShowDetailedCpuInformation(cpuInfo);
	ELSE
		AosOut.String("CPUID instruction is not supported."); AosOut.Ln;
	END;	
	RETURN NIL
END ShowDetailed;
		
PROCEDURE Show*(par : ANY) : ANY;
VAR cpuInfo : CpuInformation;
BEGIN
	IF CpuIdSupported() THEN
		GetCpuInformation(cpuInfo);
		ShowCpuInformation(cpuInfo);		
	ELSE
		AosOut.String("CPUID instruction is not supported."); AosOut.Ln;
	END;
	RETURN NIL
END Show;

END AosCPUID.

S.Free AosCPUID ~

AosCPUID.Show ~
AosCPUID.ShowDetailed ~
