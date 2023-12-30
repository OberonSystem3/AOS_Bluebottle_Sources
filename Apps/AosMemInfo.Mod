(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosMemInfo; (** AUTHOR "pjm"; PURPOSE "Memory mapping information"; *)

IMPORT SYSTEM, AosOut, AosBoot, AosMemory, AosInterrupts;

CONST
	SoftInt = AosInterrupts.SoftInt;
	
		(* standard multipliers *)
	K = 1024;  M = 100000H;	(* 1K, 1M *)
	
	PS = 4096;
	RS = 4*M;	(* region covered by a page table in bytes *)
	PTEs = RS DIV PS;	(* number of page table/directory entries *)
	
VAR
	kernelPD: LONGINT;
	msrlow, msrhigh: SET;

PROCEDURE GetCR3(VAR state: AosInterrupts.State);
CODE {SYSTEM.i386, SYSTEM.Privileged}
	MOV EAX, CR3
	MOV kernelPD, EAX
END GetCR3;

PROCEDURE -DoSoftInt(eax: LONGINT);
CODE {SYSTEM.i386}
	POP EAX
	INT SoftInt
END DoSoftInt;

(* Display mapped ranges. *)

PROCEDURE DisplayMap*(ptr : PTR) : PTR;
VAR i, j: LONGINT; pt: LONGINT; virt, phys, virt0, phys0, size: LONGINT;
	
	PROCEDURE Page;
	BEGIN
		IF (phys = phys0+size) & (virt = virt0+size) THEN
			INC(size, PS)
		ELSE
			IF size # 0 THEN
				AosOut.Hex(virt0, 9); AosOut.Hex(phys0, 9);
				AosOut.IntSuffix(size, 8, "B"); AosOut.Ln
			END;
			virt0 := virt;  phys0 := phys;  size := PS
		END
	END Page;
	
BEGIN
	AosInterrupts.InstallHandler(GetCR3, SoftInt);	(* ignore race *)
	DoSoftInt(0);
	AosInterrupts.RemoveHandler(GetCR3, SoftInt);
	AosOut.Enter; AosOut.Char(0EX); AosOut.Ln;
	AosOut.String(" Virtual  Physical Size");  AosOut.Ln;
	virt := 0;  virt0 := 0;  phys0 := 0;  size := 0;
	FOR i := 0 TO PTEs-1 DO
		SYSTEM.GET(kernelPD + 4*i, pt);
		IF ODD(pt) THEN	(* present *)
			pt := pt - pt MOD PS;
			FOR j := 0 TO PTEs-1 DO
				SYSTEM.GET(pt, phys);
				IF ODD(phys) THEN
					DEC(phys, phys MOD PS);
					Page
				END;
				INC(pt, 4);  INC(virt, 4*K)
			END
		ELSE
			INC(virt, 4*M)
		END
	END;
	virt := -1;  Page;
	AosOut.Char(0FX); AosOut.Exit;
	RETURN NIL;
END DisplayMap;

PROCEDURE Write64(s: ARRAY OF CHAR; low, high: SET);
BEGIN
	AosOut.String(s);  AosOut.Char("=");
	AosOut.Hex(SYSTEM.VAL(LONGINT, high), 8);
	AosOut.Hex(SYSTEM.VAL(LONGINT, low), 9)
END Write64;

PROCEDURE Bits(s: ARRAY OF CHAR; x: SET; ofs, n: LONGINT);
BEGIN
	AosOut.String(s); AosOut.Char("="); AosOut.Bits(x, ofs, n)
END Bits;

PROCEDURE -RealReadMSR(msr: LONGINT; VAR low, high: SET);
CODE {SYSTEM.Pentium, SYSTEM.Privileged}
	POP EDI
	POP ESI
	POP ECX
	RDMSR
	MOV [ESI], EAX
	MOV [EDI], EDX
END RealReadMSR;

PROCEDURE IntReadMSR(VAR state: AosInterrupts.State);
BEGIN
	RealReadMSR(state.EAX, msrlow, msrhigh)
END IntReadMSR;

PROCEDURE ReadMSR(msr: LONGINT; VAR low, high: SET);
BEGIN
	AosInterrupts.InstallHandler(IntReadMSR, SoftInt);	(* ignore race *)
	DoSoftInt(msr);
	AosInterrupts.RemoveHandler(IntReadMSR, SoftInt);
	low := msrlow; high := msrhigh
END ReadMSR;

PROCEDURE DisplayMTTR*(ptr : PTR) : PTR;
VAR version, i, j, k, vcnt: LONGINT; features, low, high, mask: SET; vendor: AosBoot.Vendor;
BEGIN
	AosOut.Enter;
	AosBoot.CPUID(vendor, version, features);
	AosOut.String("CPU: ");  AosOut.Int(ASH(version, -8) MOD 16, 1);
	AosOut.Char(".");  AosOut.Int(ASH(version, -4) MOD 16, 1);
	AosOut.Char(".");  AosOut.Int(version MOD 16, 1);
	Bits(", features", features, 0, 32);
	AosOut.String(", vendor ");  AosOut.String(vendor);
	AosOut.Ln;
	IF 5 IN features THEN	(* MSR supported *)
		IF 12 IN features THEN	(* MTTR supported *)
			ReadMSR(0FEH, low, high);
			vcnt := SYSTEM.VAL(LONGINT, low) MOD 256;
			AosOut.String("VCNT="); AosOut.Int(vcnt, 1);
			Bits(", FIX", low, 8, 1); Bits(", WC", low, 10, 1);
			AosOut.Ln;
			IF 8 IN low THEN
				ReadMSR(2FFH, low, high);  Write64("DefType", low, high);  AosOut.Ln;
				ReadMSR(250H, low, high);  Write64("Fix64k", low, high);  AosOut.Ln;
				ReadMSR(258H, low, high);  Write64("Fix16k", low, high);  AosOut.Ln;
				ReadMSR(259H, low, high);  Write64("Fix16k", low, high);  AosOut.Ln;
				ReadMSR(268H, low, high);  Write64("Fix4k", low, high);  AosOut.Ln;
				ReadMSR(269H, low, high);  Write64("Fix4k", low, high);  AosOut.Ln;
				ReadMSR(26AH, low, high);  Write64("Fix4k", low, high);  AosOut.Ln;
				ReadMSR(26BH, low, high);  Write64("Fix4k", low, high);  AosOut.Ln;
				ReadMSR(26CH, low, high);  Write64("Fix4k", low, high);  AosOut.Ln;
				ReadMSR(26DH, low, high);  Write64("Fix4k", low, high);  AosOut.Ln;
				ReadMSR(26EH, low, high);  Write64("Fix4k", low, high);  AosOut.Ln;
				ReadMSR(26FH, low, high);  Write64("Fix4k", low, high);  AosOut.Ln;
				FOR i := 0 TO vcnt-1 DO
					AosOut.Int(i, 1);
					ReadMSR(200H+2*i, low, high);  Write64(" base", low, high);
					ReadMSR(200H+2*i+1, low, high);  Write64(", mask", low, high);
					IF 11 IN low THEN	(* valid *)
						mask := SYSTEM.LSH(low, -12);
						FOR j := 0 TO 3 DO
							IF j IN high THEN INCL(mask, 20+j) END
						END;
						j := 0;  WHILE (j # 32) & ~(j IN mask) DO INC(j) END;
						k := 31;  WHILE (k # -1) & ~(k IN mask) DO DEC(k) END;
						IF (k = 23) & (k >= j) & (mask = {j..k}) THEN
							AosOut.String(", ");  AosOut.IntSuffix(SYSTEM.VAL(LONGINT, {j})*4*1024, 1, "B")
						ELSE
							AosOut.String(" discon=");  AosOut.Hex(SYSTEM.VAL(LONGINT, mask), 8)
						END
					END;
					AosOut.Ln
				END
			ELSE
				AosOut.String("Fixed range registers not supported");  AosOut.Ln
			END
		ELSE
			AosOut.String("MTTR not supported");  AosOut.Ln
		END
	ELSE
		AosOut.String("MSR not supported");  AosOut.Ln
	END;
	AosOut.Exit;
	RETURN NIL;
END DisplayMTTR;

(*
PROCEDURE IntSetCache(VAR state: AosInterrupts.State);
VAR res: LONGINT;
BEGIN
	AosMemory.SetLocalCacheProperties(0FA800000H, 800000H, AosMemory.WC, res);
	AosOut.Enter; AosOut.String("SetCache "); AosOut.Int(res, 1); AosOut.Exit
END IntSetCache;

PROCEDURE Test*;
BEGIN
	AosInterrupts.InstallHandler(IntSetCache, SoftInt);	(* ignore race *)
	DoSoftInt(0);
	AosInterrupts.RemoveHandler(IntSetCache, SoftInt)
END Test;

PROCEDURE -SetMTTRphysBase(n: LONGINT; high, low: LONGINT);
CODE {SYSTEM.Pentium, SYSTEM.Privileged}
	POP EAX
	POP EDX
	POP ECX
	SHL ECX, 1
	ADD ECX, 200H	; MTTRphysBase0
	WRMSR
END SetMTTRphysBase;

PROCEDURE -SetMTTRphysMask(n: LONGINT; high, low: LONGINT);
CODE {SYSTEM.Pentium, SYSTEM.Privileged}
	POP EAX
	POP EDX
	POP ECX
	SHL ECX, 1
	ADD ECX, 201H	; MTTRphysMask0
	WRMSR
END SetMTTRphysMask;

(*
1 000000000H 4GB WB
0 0F0000000H 128MB UC
4 0F8000000H 64MB UC
- 0FC000000H 32MB WB (implicit)
3 0FE000000H 32MB UC
2 100000000H 256MB WB

WB 0MB-2048MB 2048MB
WB 2048MB-3072MB 1024MB
WB 3072MB-3584MB 512MB
WB 3584MB-3840MB 256MB
WC 4032MB-4064MB 32MB
WB 4096MB-4352MB 256MB
*)

PROCEDURE IntSetCache2(VAR state: AosInterrupts.State);
BEGIN
	SetMTTRphysBase(3, 0, 0FE000000H);
	SetMTTRphysMask(3, 0FH, 0FE000800H);
	SetMTTRphysBase(4, 0, 0F8000000H);
	SetMTTRphysMask(4, 0FH, 0FC000800H);
	SetMTTRphysBase(0, 0, 0F0000000H);
	SetMTTRphysMask(0, 0FH, 0F8000800H)
END IntSetCache2;

PROCEDURE Test2*;
BEGIN
	AosInterrupts.InstallHandler(IntSetCache2, SoftInt);	(* ignore race *)
	DoSoftInt(0);
	AosInterrupts.RemoveHandler(IntSetCache2, SoftInt)
END Test2;

PROCEDURE Test3*;
VAR res: LONGINT;
BEGIN
	AosProcessors.GlobalSetCacheProperties(0FA800000H, 800000H, AosMemory.WC, res);
	AosOut.Enter; AosOut.String("SetCache "); AosOut.Int(res, 1); AosOut.Exit
END Test3;
*)

END AosMemInfo.

System.Free AosMemInfo ~

AosMemInfo.DisplayMap
AosMemInfo.DisplayMTTR

AosMemInfo.Test
AosMemInfo.Test2
AosMemInfo.Test3

DisplayTests.Mod

PCITools.Scan
