(* Paco, Copyright 2002, Patrik Reali, ETH Zurich *)

MODULE AosInterfaces; (** AUTHOR "prk"; PURPOSE "Runtime support for interfaces"; *)

IMPORT
	SYSTEM, AosKernel, AosModules;

(*
	Interface
	Interface Implementation
		td => Interface
		+00: => Class TD
		+04: method0
		+08: method1
		....
	
	Internal organization:
		Hash Table (with double hashing)

*)

CONST
	TableSize = 8191; (* largest prime number < 8192; !!= (2<<13)-1!! *)
	TableSize1m  = TableSize - 1;
			
VAR
	table-: ARRAY TableSize OF PTR;
	
	(*statistic counters*)
	Nentries, Nlookups, NlookupsRep: LONGINT;
	Ncollisions: ARRAY 10 OF LONGINT;


PROCEDURE GetClass(p: PTR): LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, p[EBP]
	MOV EAX, 0[EAX]
END GetClass;

PROCEDURE GetInterface(p: PTR): LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, p[EBP]
	MOV EAX, -4[EAX]
	MOV EAX, -8[EAX]
END GetInterface;

PROCEDURE HashA*(val1, val2: LONGINT): LONGINT;
VAR x: LONGINT;
BEGIN	
	x := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, ASH(val1,1)) / SYSTEM.VAL(SET, val2));
	RETURN x MOD TableSize
END HashA;

PROCEDURE HashB*(val1, val2: LONGINT): LONGINT;
VAR val: LONGINT;
BEGIN	
	val := ASH(val2,1);	
	RETURN SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) / SYSTEM.VAL(SET, val2)) MOD (TableSize-1) + 1
END HashB;

PROCEDURE Register(vt: PTR);
	VAR class, intf, hash, step, count: LONGINT; q: PTR;
BEGIN {EXCLUSIVE}
	ASSERT(Nentries < TableSize, 1000);
	class := GetClass(vt);
	intf := GetInterface(vt);
	hash := HashA(class, intf);
	step := HashB(class, intf);
	WHILE table[hash] # NIL DO
		q := table[hash];
		ASSERT((GetClass(q) # class) OR (GetInterface(q) # intf), 1001);
		INC(count);
		INC(hash, step);
		IF hash >= TableSize THEN DEC(hash, TableSize) END
	END;
	table[hash] := vt;
	IF count >= LEN(Ncollisions) THEN count := LEN(Ncollisions)-1 END;
	INC(Nentries);
	INC(Ncollisions[count])
END Register;

PROCEDURE Lookup(class, intf: LONGINT): PTR;
	VAR vt: PTR; hash, step: LONGINT;
BEGIN	(* can run concurrent with Register *)
	AosKernel.AtomicInc(Nlookups);
	hash := HashA(class, intf);
	vt := table[hash];
	IF (vt # NIL) & ((GetClass(vt) # class) OR (GetInterface(vt) # intf)) THEN
		step := HashB(class, intf);
		AosKernel.AtomicInc(NlookupsRep);
		REPEAT
			INC(hash, step);
			IF hash >= TableSize THEN DEC(hash, TableSize) END;
			vt := table[hash]
		UNTIL (vt = NIL) OR ((GetClass(vt) = class) & (GetInterface(vt) = intf))
	END;
	RETURN vt;
END Lookup;

PROCEDURE Cleanup;
BEGIN
	AosModules.kernelProc[8] := 0;	(*245*)
	AosModules.kernelProc[9] := 0;	(*244*)
END Cleanup;

PROCEDURE Init;
VAR i: LONGINT; lookup: PROCEDURE(class, intf: LONGINT): PTR; register: PROCEDURE(vt: PTR);
BEGIN
	FOR i := 0 TO TableSize-1 DO  table[i] := NIL  END;
	register := Register; lookup := Lookup;
	AosModules.InstallTermHandler(Cleanup);
	AosModules.kernelProc[8] := SYSTEM.VAL(LONGINT, lookup);	(*245*)
	AosModules.kernelProc[9] := SYSTEM.VAL(LONGINT, register);	(*244*)
END Init;

BEGIN
	Init
END AosInterfaces.

System.State AosInterfaces ~

(*
ToDo:
	Remove interface when a module is freed

Log:
	30.10.2001	prk	Fine tuning
	05.10.2001	prk	First Version
*)