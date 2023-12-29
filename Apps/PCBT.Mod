(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE PCBT; (** AUTHOR "prk / be"; PURPOSE "Parallel Compiler: back-end common structures"; *)

IMPORT
		SYSTEM, PCM;

CONST
	(*static buffer for constants*)
	ConstSize = 16*1024;
	

	(** system calls *)
	DefaultNofSysCalls* = 11;
	newrec* = 0;  newarr* = 1;  newsys* = 2;  casetable* = 3;  procaddr* = 4;
	lock* = 5;  unlock* = 6;  start* = 7;  passivate* = 8; interfacelookup* = 9;
	registerinterface* = 10;

	(** Fixup, last address in a fixup chain *)
	FixupSentinel* = 0FFFFH;
	UndefEntryNo* = -1;	(** GlobalVariable.EntryNo *)
	
	(** Calling Conventions *)
	OberonCC* = 1;  OberonPassivateCC* = 2;

VAR
	init: BOOLEAN;
	
TYPE
	ConstArray* = POINTER TO ARRAY OF CHAR;
	
	(** ----------- Size - type related information -------------- *)

	Size* = POINTER TO RECORD (PCM.Attribute)
		size*: LONGINT;	(** size in bytes, used for allocation*)
		align*: LONGINT;	(** on which boundary should this type be aligned *)
		type*: SHORTINT;	(** Back-End Type *)
		signed*: BOOLEAN;
		containPtrs*: BOOLEAN;
	END;
	
	RecSize* = POINTER TO RECORD (Size)
		td*: GlobalVariable;
		level*: LONGINT;
		nofMethods*, nofLocalMethods*: LONGINT;
	END;

	
	
	(** ----------- Address - allocation related information ------- *)
	
	(** Fixup - offset to be patched at a later time *)
	Fixup* = POINTER TO RECORD
		offset-: LONGINT;
		next-: Fixup
	END;

	Variable* = POINTER TO RECORD (PCM.Attribute)
		offset*: LONGINT
	END;

	GlobalVariable* = OBJECT (Variable)
		VAR
			owner-: Module;
			entryNo*: INTEGER;	(** object-file information set by PCOF *)
			
			link-: Fixup;	(** occourencies of var in code *)
			next-: GlobalVariable;	(** next GVar in the list *)
		
		PROCEDURE AddFixup(offset: LONGINT);
			VAR l: Fixup;
		BEGIN
			NEW(l); l.offset := offset; l.next := link; link := l
		END AddFixup;
		
		(** Init - Initialize structure *)
		
		PROCEDURE & Init(owner: Module);
		BEGIN
			SELF.owner := owner;
			entryNo := UndefEntryNo;
			ASSERT((owner # NIL) OR (SELF = sentinel));
		END Init;
	END GlobalVariable;

	Procedure* = OBJECT (PCM.Attribute)
		VAR
			owner-: Module;
			public-: BOOLEAN;
			locsize*: LONGINT;	(* local variables size *)
			parsize*: LONGINT;	(* parameters size incl. self/sl, return addr and dynamic link *)
			codeoffset-: LONGINT;	(* entry point relative to code base of owner*)
			entryNr*, fixlist*: LONGINT;	(* set/used by PCOF *)
			next-: Procedure;	(* entrylist *)
			
			link-: Fixup;
		
		PROCEDURE AddFixup(offset: LONGINT);
			VAR l: Fixup;
		BEGIN
			NEW(l); l.offset := offset; l.next := link; link := l
		END AddFixup;
		
		PROCEDURE & Init(owner: Module;  public: BOOLEAN);
		BEGIN
			ASSERT((owner # NIL) OR init);
			SELF.owner := owner;
			SELF.public := public;
			fixlist := FixupSentinel;
		END Init;
		
	END Procedure;

	Method* = POINTER TO RECORD (Procedure)
		mthNo*: LONGINT
	END;
	
	Module* = OBJECT (PCM.Attribute)
		VAR
			locsize*: LONGINT;	(** data section size*)
			constsize*: INTEGER;	(** const section size*)
			nr*: INTEGER;
	
			const*: ConstArray;
			
			OwnProcs-: Procedure;		(** this module's procedures; terminated by psentinel *)
			ExtProcs-: Procedure;			(** external procedures used; terminated by psentinel *)
			
			OwnVars-: GlobalVariable;	(** this module's used variables; terminated by sentinel *)
			ExtVars-: GlobalVariable;	(** external used variables; terminated by sentinel *)
			
			syscalls-: POINTER TO ARRAY OF Fixup;	(** syscalls' fixup lists *)
		
		PROCEDURE & Init;
		BEGIN
			NEW(syscalls, NofSysCalls);
			NEW(const, 128);
			ResetLists;
			constsize := 0;
			nr := 0;
		END Init;
		
		(** ResetLists - remove entries from OwnVars, ExtVars, OwnProcs, ExtProcs *)
		
		PROCEDURE ResetLists*;
			VAR i: LONGINT;
			
			PROCEDURE KillPList(VAR root: Procedure);
				VAR p, q: Procedure;
			BEGIN
				p := root; root := psentinel;
				WHILE p # NIL DO
					q := p;
					p := p.next;
					q.link := NIL;
					q.next := NIL
				END;
			END KillPList;
			
			PROCEDURE KillVList(VAR root: GlobalVariable);
				VAR p, q: GlobalVariable;
			BEGIN
				p := root; root := sentinel;
				WHILE p # NIL DO
					q := p;
					p := p.next;
					q.entryNo := UndefEntryNo;
					q.link := NIL;
					q.next := NIL;
				END;
			END KillVList;

		BEGIN
			KillPList(OwnProcs); KillPList(ExtProcs);
			KillVList(OwnVars); KillVList(ExtVars);
			FOR i := 0 TO NofSysCalls-1 DO  syscalls[i] := NIL  END;
		END ResetLists;
		
		(** NewConst - Create a new constant *)
		
		PROCEDURE NewConst*(VAR a: ARRAY OF SYSTEM.BYTE;  len: LONGINT): LONGINT;
		VAR  base: LONGINT; c: ConstArray;
		BEGIN {EXCLUSIVE}
			ASSERT(len <= LEN(a));
			base := constsize;
			ASSERT(base+len < ConstSize);
			IF base+len > LEN(const^) THEN
				NEW(c, LEN(const) + 256);
				SYSTEM.MOVE(SYSTEM.ADR(const[0]), SYSTEM.ADR(c[0]), LEN(const));
				const := c
			END;
					
			IF PCM.bigEndian THEN
				IF len = 8 THEN (* const is 64 bits (e.g. HUGEINT, LONGREAL)-> swap low and high 4-byte words separately *)
					PCM.SwapBytes(a, 0, 4); PCM.SwapBytes(a, 4, 4);
				ELSE
					PCM.SwapBytes(a, 0, len);
				END;
			END;

			SYSTEM.MOVE(SYSTEM.ADR(a[0]), SYSTEM.ADR(const[base]), len);
			INC(constsize, SHORT(len + (-len) MOD 4));
			RETURN base
		END NewConst;
		
		(** NewStringConst - Create a new string constant; used for big endian: do not change endianness
				of string constants *)

		PROCEDURE NewStringConst*(VAR a: ARRAY OF SYSTEM.BYTE;  len: LONGINT): LONGINT;
		VAR  base: LONGINT; c: ConstArray;
		BEGIN {EXCLUSIVE}
			ASSERT(len <= LEN(a));
			base := constsize;
			ASSERT(base+len < ConstSize);
			IF base+len > LEN(const^) THEN
				NEW(c, LEN(const) + 256);
				SYSTEM.MOVE(SYSTEM.ADR(const[0]), SYSTEM.ADR(c[0]), LEN(const));
				const := c
			END;
		
			SYSTEM.MOVE(SYSTEM.ADR(a[0]), SYSTEM.ADR(const[base]), len);
	
			INC(constsize, SHORT(len + (-len) MOD 4));
			RETURN base
		END NewStringConst;

		(** UseVar - insert a fixup, add to ExtVars or OwnVars *)
		
		PROCEDURE UseVariable*(v: GlobalVariable; offset: LONGINT);
		BEGIN
			v.AddFixup(offset);
			IF v.next = NIL THEN
				IF v.owner = SELF THEN
					v.next := OwnVars; OwnVars := v
				ELSE
					v.next := ExtVars; ExtVars := v
				END
			END
		END UseVariable;
		
		(** AddOwnProc - Insert local procedure into OwnProcs list *)
		
		PROCEDURE AddOwnProc*(p: Procedure; codeOffset: LONGINT);
		BEGIN (*{EXCLUSIVE}*)
			ASSERT(p.owner = context, 500);	(* must be local *)
			ASSERT((p.next = NIL), 501);			(* not inserted yet *)
			p.next := OwnProcs; OwnProcs := p;
			p.codeoffset := codeOffset
		END AddOwnProc;
		
		(** UseProcedure - insert a fixup entry, add to ExtProcs list (if external) *)
		
		PROCEDURE UseProcedure*(p: Procedure; offset: LONGINT);
		BEGIN
			p.AddFixup(offset);
			IF (p.owner # SELF) & (p.next = NIL) THEN
				BEGIN {EXCLUSIVE}
					p.next := ExtProcs; ExtProcs := p
				END
			END
		END UseProcedure;
		
		(** UseSyscall - Add a syscall fixup *)
		
		PROCEDURE UseSyscall*(syscall, offset: LONGINT);
			VAR l: Fixup;
		BEGIN
			NEW(l); l.offset := offset;
			l.next := syscalls[syscall]; syscalls[syscall] := l
		END UseSyscall;
	END Module;


VAR
	NofSysCalls-: LONGINT;
	sentinel-: GlobalVariable;	(*last element of the VarEntries list *)
	psentinel-: Procedure;	(** last element of the OwnProcs list *)
	context*: Module;
	

(** --------------- Miscellaneous ------------------ *)

PROCEDURE SetNumberOfSyscalls*(nofsyscalls: LONGINT);
BEGIN
	ASSERT(nofsyscalls >= DefaultNofSysCalls, 100);
	NofSysCalls := nofsyscalls
END SetNumberOfSyscalls;

(** ------------ Resource Allocation ----------------- *)

PROCEDURE AllocateTD*(size: RecSize);	(** td => record.td *)
VAR  zero: LONGINT; ga: GlobalVariable;
BEGIN {EXCLUSIVE}
	IF size.td = NIL THEN
		zero := 0;
		NEW(ga, context);
		ga.offset := context.NewConst(zero, 4);
		size.td := ga;
	END
END AllocateTD;

BEGIN
	init := TRUE;
	NEW(sentinel, NIL);
	NEW(psentinel, NIL , FALSE);
	NofSysCalls := DefaultNofSysCalls;
	init := FALSE;
END PCBT.

(*
	18.03.02	prk	PCBT code cleanup and redesign
	11.08.01	prk	Fixup and use lists for procedures in PCBT cleaned up
	10.08.01	prk	PCBT.Procedure: imported: BOOLEAN replaced by owner: Module
	10.08.01	prk	PCBT.Module.imported removed
	09.08.01	prk	Symbol Table Loader Plugin
	06.08.01	prk	make code generator and object file generator indipendent
	29.05.01    be	syscall structures moved to backend (PCLIR & code generators)
	07.05.01	prk	Installable code generators moved to PCLIR; debug function added
	03.05.01	be	Installable code generators
	26.04.01	prk	separation of RECORD and OBJECT in the parser
*)

(**

PCBT use:

1. Procedure Entry Points
	When a procedure implemented in the compilation unit is emitted, it must register itself as an entry point using
		PCBT.context.AddOwnProc(procaddr, codeoffset)
	procaddr is added to the entries list, procaddr.codeoffset is set.



Invariants:
	mod.entries:
		- all entries have owner = mod
		- list terminated by PCBT.psentinel
		
	mod.ExtProcs:
		- all procs have owner # mod
		- list terminated by PCBT.psentinel
*)