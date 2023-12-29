(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE PCV; (** AUTHOR "prk / be"; PURPOSE "Parallel Compiler: symbol allocation"; *)


IMPORT
		StringPool, AosOut,
		PCM, PCT, PCBT, PCLIR;


CONST
	Trace = FALSE;

		(*procedure parameters*)
	RecVarParSize = 8;
	VarParSize = 4;
	
		(* Procedure Parameter Offsets *)
	ProcOff = 8;
	ProcOffSL = 12;
	
		(* back-end types *)
	Signed = TRUE; Unsigned = FALSE;
	
VAR
	ptrsize, procsize, delegsize: PCBT.Size;	(*used by TypeSize*)

	AAllocPar, AAllocParSize,	(*allocated parameters, parameters that required TypeSize*)
	AfieldAllocated, 					(*allocating an already allocated field*)
	ArecursiveAlloc: LONGINT;	(*record size recursively allocated*)
	
PROCEDURE VarOffset(VAR offset, varOffset: LONGINT;  var: PCT.Variable);
VAR size: LONGINT;
BEGIN
	size := var.type.size(PCBT.Size).size;
	INC(offset, size);
	IF size >= 4 THEN  INC(offset, (-offset) MOD 4)
	ELSIF size = 2 THEN  INC(offset, (-offset) MOD 2)
	END;
	varOffset := -offset
END VarOffset;

PROCEDURE ParOffset(VAR offset, varOffset: LONGINT;  par: PCT.Parameter);
VAR size: LONGINT; open: BOOLEAN;
BEGIN
	size := par.type.size(PCBT.Size).size;
	open := (par.type IS PCT.Array) & (par.type(PCT.Array).mode = PCT.open);
	IF par.ref & ~open THEN
		IF par.type IS PCT.Record THEN  size := RecVarParSize
		ELSE  size := VarParSize
		END
	END;
	INC(offset, size);
	INC(offset, (-offset) MOD 4);
	varOffset := offset;
END ParOffset;

PROCEDURE FieldOffset(VAR offset: LONGINT;  size, align: LONGINT;  p: PCT.Symbol);
VAR  adr: PCBT.Variable;
BEGIN
	IF p.adr # NIL THEN
		INC(AfieldAllocated)
	ELSE
		NEW(adr); p.adr := adr;
		IF align = 4 THEN  INC(offset, (-offset) MOD 4)
		ELSIF align = 2 THEN  INC(offset, (-offset) MOD 2)
		ELSIF align # 1 THEN  HALT(99)
		END;
		adr.offset := offset
	END;
(*
;PCM.LogWLn; PCM.LogWStr("FieldOffset "); PCM.LogWStr(p.name); PCM.LogWNum(offset);
PCM.LogWNum(size); PCM.LogWNum(align);
*)
	INC(offset, size)
END FieldOffset;


PROCEDURE TypeSize(type: PCT.Struct);
VAR  size, fsize: PCBT.Size; recsize, brecsize: PCBT.RecSize; p: PCT.Parameter; t: PCT.Struct; redo: BOOLEAN;
		f: PCT.Variable; s: PCT.RecScope;
		name, namef: ARRAY 256 OF CHAR; 
BEGIN
	IF type.size = NIL THEN
		PCT.GetTypeName(type, name);
		IF Trace THEN
			PCM.LogWLn; PCM.LogWStr("PCV.TypeSize "); PCM.LogWStr(name)
		END;
		IF type IS PCT.Basic THEN
			PCT.PrintString(type.owner.name); AosOut.Ln;
			HALT(99)
		ELSIF type IS PCT.Pointer THEN
			WITH type: PCT.Pointer DO
				NEW(size); type.size := size;
				size.size := 4; size.align := 4; size.type := PCLIR.Address;
				size.containPtrs := TRUE;
				IF type.baseR # NIL  (* IS PCT.Record *) THEN s := type.baseR.scope END;
				IF (s = NIL) OR ~(PCT.CanSkipAllocation IN s.flags) THEN
(*
				IF (s = NIL) OR (PCM.GetProcessID() = s.ownerID) OR ~(PCT.CanSkipAllocation IN s.flags) THEN
				IF (s = NIL) OR (s.state >= PCT.structallocated) OR ~(PCT.CanSkipAllocation IN s.flags) THEN
*)
					TypeSize(type.base)
				END
			END
		ELSIF type IS PCT.Record THEN
			WITH type: PCT.Record DO
				IF PCM.GetProcessID() # type.scope.ownerID THEN
					type.scope.Await(PCT.structallocated);
					ASSERT(type.size # NIL, 500)
				ELSE
					NEW(recsize);  recsize.type := PCLIR.NoSize; recsize.level := 0;
					IF type.brec # NIL THEN
						TypeSize(type.brec); brecsize := type.brec.size(PCBT.RecSize);
						recsize.size := brecsize.size;
						recsize.level := brecsize.level+1;
						recsize.containPtrs := brecsize.containPtrs;
						IF ~type.imported & type.brec.imported THEN PCBT.AllocateTD(brecsize) END
					END;
					redo := FALSE;
					f := type.scope.firstVar;
					WHILE f # NIL DO
						StringPool.GetString(f.name, namef);
						t := f.type;
						IF t.size # NIL THEN
							fsize := t.size(PCBT.Size)
						ELSIF (t IS PCT.Pointer) THEN	(*avoid recursion, can cause deadlock*)
							fsize := ptrsize;
							redo := TRUE;
						ELSIF (t IS PCT.Delegate) THEN	(*avoid recursion, can cause deadlock*)
							IF PCT.StaticMethodsOnly IN t.flags THEN fsize := procsize ELSE fsize := delegsize END;
							redo := TRUE;
						ELSE
							TypeSize(t);
							IF type.size # NIL THEN  INC(ArecursiveAlloc); RETURN  END;
							fsize := t.size(PCBT.Size);
						END;
						recsize.containPtrs := recsize.containPtrs OR fsize.containPtrs;
(*
PCM.LogWLn; PCM.LogWStr("TypeSize/rec/field/"); PCM.LogWStr(f.name);
PCM.LogWNum(recsize.size);
*)
						FieldOffset(recsize.size, fsize.size, fsize.align, f);
						f := f.nextVar
					END;
					INC(recsize.size, (-recsize.size) MOD 4);
					recsize.align := 4;
					type.size := recsize;
					IF ~type.imported & ~(PCT.SystemType IN type.flags) THEN PCBT.AllocateTD(recsize) END;
					IF redo THEN
						f := type.scope.firstVar;
						WHILE f # NIL DO
							StringPool.GetString(f.name, namef);
							TypeSize(f.type);
							f := f.nextVar
						END;
					END
				END
			END
		ELSIF type IS PCT.Array THEN
			WITH type: PCT.Array DO
				NEW(size); size.type := PCLIR.Address;
				IF type.mode = PCT.open THEN
					size.size := type.opendim * 4 + 4;
					size.align := 4;
					size.containPtrs := FALSE;
					type.size := size;
					TypeSize(type.base);
				ELSIF type.mode = PCT.static THEN
					TypeSize(type.base);
					fsize := type.base.size(PCBT.Size);
					size.size := fsize.size * type.len;
					size.align := fsize.align;
					size.containPtrs := fsize.containPtrs;
					type.size := size;
				ELSE
					HALT(98)
				END
			END
		ELSIF type IS PCT.Delegate THEN
			WITH type: PCT.Delegate DO
				IF PCT.StaticMethodsOnly IN type.flags THEN
					size := procsize
				ELSE
					size := delegsize
				END;
				type.size := size;
				ASSERT(size.size > 0, 999);
				p := type.scope.firstPar;
				WHILE p # NIL DO
					TypeSize(p.type);
					(*
					IF type.scope.imported THEN  TypeSize(p.type)  ELSE  ASSERT(p.type.size # NIL, 502)  END;
						size = NIL is possible when TypeSize is called for a type use in a record but declared outside.
					*)
					p := p.nextPar
				END;
				TypeSize(type.return)
			END
		ELSIF type = PCT.String THEN	(*skip*)
		ELSE
			PCM.LogWLn;
			PCM.LogWType(type);
			HALT(97)
		END
	END
END TypeSize;

PROCEDURE AllocateParameters(p: PCT.Proc);
VAR  adr: PCBT.Variable;  offset: LONGINT;  par: PCT.Parameter;
BEGIN
	par := p.scope.firstPar;
	offset := 0;
	WHILE (par # NIL) DO
		INC(AAllocPar);
		IF par.type.size = NIL THEN  TypeSize(par.type); INC(AAllocParSize) END;
		ASSERT(par.type.size # NIL);	(* p.scope.parent >= allocated *)
		NEW(adr); par.adr := adr;
		ParOffset(offset, adr.offset , par);
		par := par.nextPar
	END;
	INC(offset, ProcOff);
	IF p.level # 0 THEN  INC(offset, ProcOffSL-ProcOff)  END;
	par := p.scope.firstPar;
	WHILE (par # NIL) DO
		par.adr(PCBT.Variable).offset := offset - par.adr(PCBT.Variable).offset;
		par := par.nextPar
	END;
	p.adr(PCBT.Procedure).parsize := offset;
END AllocateParameters;

PROCEDURE AllocateTypes(t: PCT.Type; v: PCT.Variable);
BEGIN
	WHILE t # NIL DO
		TypeSize(t.type); t := t.nextType
	END;
	WHILE v # NIL DO
		TypeSize(v.type); v := v.nextVar
	END;
END AllocateTypes;

PROCEDURE AllocateLocals(var: PCT.Variable; VAR size: LONGINT);
	VAR offset: LONGINT; ladr: PCBT.Variable;
BEGIN
	offset := 0;
	WHILE var # NIL DO
		TypeSize(var.type);
		NEW(ladr); var.adr := ladr;
		VarOffset(offset, ladr.offset , var);
		var := var.nextVar
	END;
	INC(offset, (-offset) MOD 4);
	size := offset;
END AllocateLocals;

PROCEDURE AllocateGlobals(var: PCT.Variable; mod: PCBT.Module; setOffset: BOOLEAN; VAR size: LONGINT);
	VAR offset: LONGINT; gadr: PCBT.GlobalVariable;
BEGIN
	offset := 0;
	WHILE var # NIL DO
		TypeSize(var.type);
		NEW(gadr, mod); var.adr := gadr;
		IF setOffset THEN VarOffset(offset, gadr.offset , var) END;
		var := var.nextVar
	END;
	INC(offset, (-offset) MOD 4);
	size := offset;
END AllocateGlobals;

(** PreAllocate - called on scope creation, creates PCBT.Address struct *)

PROCEDURE PreAllocate*(context, scope: PCT.Scope);
VAR proc: PCT.Proc; adr: PCBT.Procedure; madr: PCBT.Method; 
	gadr: PCBT.GlobalVariable; zero: LONGINT; imported, visible: BOOLEAN;
	mod: PCBT.Module; isEntry: BOOLEAN;
BEGIN
	IF (scope IS PCT.ProcScope) THEN
		WITH scope: PCT.ProcScope DO
			mod := scope.module.adr(PCBT.Module);
			proc := scope.ownerO;
			visible := (PCT.PublicR IN proc.vis);
			ASSERT(proc.adr = NIL);
			IF proc IS PCT.Method THEN
				NEW(madr, mod, visible);
				proc.adr := madr
			ELSE
				NEW(adr, mod, visible);
				proc.adr := adr
			END
		END
	ELSIF scope IS PCT.ModScope THEN
		WITH scope: PCT.ModScope DO
			imported := scope # context;
			NEW(mod); scope.owner.adr := mod;
			IF ~imported THEN
				(*PCM.LogWLn; PCM.LogWStr("PCV.PreAllocate: New PCBT.context");*)
				PCBT.context := mod;
				IF (scope.firstVar # NIL) & (scope.firstVar.name = PCT.SelfName) THEN
					NEW(gadr, PCBT.context); scope.firstVar.adr := gadr;
					gadr.offset := PCBT.context.NewConst(zero, 4);
				END
			END
		END
	END
END PreAllocate;


(** Allocate - scope declarations (var/types) parsed *)

PROCEDURE Allocate*(context, scope: PCT.Scope);
	VAR proc: PCT.Proc; madr: PCBT.Module; globals: PCT.Variable;
BEGIN
	IF scope IS PCT.RecScope THEN
		TypeSize(scope(PCT.RecScope).owner)
	ELSIF scope IS PCT.ProcScope THEN
		WITH scope: PCT.ProcScope DO
			proc := scope.ownerO;
			AllocateParameters(proc);
			AllocateTypes(scope.firstType, scope.firstVar);
			AllocateLocals(scope.firstVar, proc.adr(PCBT.Procedure).locsize)
		END
	ELSIF scope IS PCT.ModScope THEN
		WITH scope: PCT.ModScope DO
			madr := scope.owner.adr(PCBT.Module);
			AllocateTypes(scope.firstType, scope.firstVar);
			globals := scope.firstVar;
(*
			ASSERT((scope.imported) OR (globals.name = PCT.SelfName));
*)
			IF (globals # NIL) & (globals.name = PCT.SelfName) THEN globals := globals.nextVar END;
			AllocateGlobals(globals, madr, context = scope, madr.locsize)
		END
	(* ELSE
			ignore WITH scope *)	
	END
END Allocate;


(** PostAllocate - scope procedures parsed *)

PROCEDURE PostAllocate*(context, scope: PCT.Scope);
VAR  p, q: PCT.Symbol; rec: PCT.Record; recsize: PCBT.RecSize;
BEGIN
	IF scope IS PCT.RecScope THEN
		WITH scope: PCT.RecScope DO
			rec := scope.owner;
			recsize := rec.size(PCBT.RecSize);
			IF rec.brec # NIL THEN
				rec.brec.scope.Await(PCT.procdeclared);
				recsize.nofMethods := rec.brec.size(PCBT.RecSize).nofMethods
			END;
			p := scope.sorted;
			WHILE p # NIL DO
				IF p IS PCT.Method THEN
					WITH p: PCT.Method DO
						INC(recsize.nofLocalMethods);
						IF p.super = NIL THEN
							p.adr(PCBT.Method).mthNo := recsize.nofMethods;
							INC(recsize.nofMethods)
						ELSE
							p.adr(PCBT.Method).mthNo := p.super.adr(PCBT.Method).mthNo
						END
					END
				END;(*if Method*)
				p := p.sorted
			END
		END(*WITH RecScope*)
	END
END PostAllocate;

PROCEDURE BasicSize(type: PCT.Struct; size, align: LONGINT; BEsize: PCLIR.Size; signed: BOOLEAN);
VAR adr: PCBT.Size;
BEGIN
	NEW(adr); type.size := adr; adr.size := size; adr.align := align; adr.type := BEsize; adr.signed := signed;
	adr.containPtrs := type = PCT.Ptr
END BasicSize;

PROCEDURE Install*;
BEGIN
	PCT.PreAllocate := PreAllocate;
	PCT.Allocate := Allocate;
	PCT.PostAllocate := PostAllocate
END Install;

BEGIN
	IF Trace THEN PCM.LogWLn; PCM.LogWStr("PCV.Trace on") END;
	BasicSize(PCT.NoType, -1, 1, PCLIR.NoSize, Unsigned);
	BasicSize(PCT.UndefType, -1, 1, PCLIR.NoSize, Unsigned);
	BasicSize(PCT.Bool, 1, 1, PCLIR.Int8, Unsigned);
	BasicSize(PCT.Byte, 1, 1, PCLIR.Int8, Unsigned);
	BasicSize(PCT.Char8, 1, 1, PCLIR.Int8, Unsigned);
	IF PCM.LocalUnicodeSupport THEN
		BasicSize(PCT.Char16, 2, 2, PCLIR.Int16, Unsigned);
		BasicSize(PCT.Char32, 4, 4, PCLIR.Int32, Unsigned);
	END;
	BasicSize(PCT.Int8, 1, 1, PCLIR.Int8, Signed);
	BasicSize(PCT.Int16, 2, 2, PCLIR.Int16, Signed);
	BasicSize(PCT.Int32, 4, 4, PCLIR.Int32, Signed);
	BasicSize(PCT.Int64, 8, 4, PCLIR.Int64, Signed);
	BasicSize(PCT.Float32, 4, 4, PCLIR.Float32, Signed);
	BasicSize(PCT.Float64, 8, 4, PCLIR.Float64, Signed);
	BasicSize(PCT.Set, 4, 4, PCLIR.Int32, Unsigned);
	BasicSize(PCT.NilType, 4, 4, PCLIR.Address, Unsigned);
	BasicSize(PCT.Ptr, 4, 4, PCLIR.Address, Unsigned);
	ptrsize := PCT.Ptr.size(PCBT.Size);
	NEW(procsize);
	procsize.size := 4; procsize.align := 4; procsize.type := PCLIR.Address; procsize.containPtrs := FALSE;
	NEW(delegsize);
	delegsize.size := 8; delegsize.align := 4; delegsize.type := PCLIR.Address; delegsize.containPtrs := TRUE;
END PCV.

(*
	18.03.02	prk	PCBT code cleanup and redesign
	22.02.02	prk	unicode support
	11.12.01	prk	problem parsing invalid WITH syntax fixed
	28.11.01	prk	explicitly install PCV, avoid depending on the import list sequence
	05.09.01	prk	CanSkipAllocation flag for record scopes
	27.08.01	prk	scope.unsorted list removed; use var, proc, const and type lists instead
	17.08.01	prk	overloading
	13.08.01	prk	fixed bug in allocation size of delegates used in a record but decalred outside
	11.08.01	prk	Fixup and use lists for procedures in PCBT cleaned up
	10.08.01	prk	PCBT.Procedure: imported: BOOLEAN replaced by owner: Module
	09.08.01	prk	Symbol Table Loader Plugin
	02.07.01	prk	access flags, new design
	27.06.01	prk	StringPool cleaned up
	14.06.01	prk	type descs for dynamic arrays of ptrs generated by the compiler
	06.06.01	prk	use string pool for object names
	17.05.01	prk	Delegates
	07.05.01	be	register sign information added in the back-end
	25.03.01	prk	limited HUGEINT implementation (as abstract type)
	22.02.01	prk	delegates
*)