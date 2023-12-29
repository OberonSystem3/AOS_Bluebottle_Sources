(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE PCC; (** AUTHOR "prk / be"; PURPOSE "Parallel Compiler: intermediate code generation"; *)

IMPORT
		PCDebug,
		PCM, PCBT, PCLIR, PCS, PCT, SYSTEM;

CONST
	Trace = FALSE;
	Statistics = FALSE;

	(** operators *)
	setfn* = 200;		(** MOp / DOp: convert to set *)
	absfn* = 201;		(** MOp: absolute value *)
	capfn* = 202;		(** MOp: CAP(x) *)
	oddfn* = 203;		(** MOp: ODD(x) *)
	
	ashfn* = 204;		(** DOp: ASH *)
	lshfn* = 205;		(** DOp: LSH *)
	rotfn* = 206;		(** DOp: ROT *)
	
	bitfn* = 207;		(** RelOp: SYSTEM.BIT *)
	
		(*special values*)
	True = 1; False = 0;	(*1-byte constants*)
	Nil = 0;
	
TYPE
(* ===================================================
    mode   description    adr    level   offs    value   breg  comments
-----------------------------------------------------------------------
    Abs    Absolute Var   -      -       off[sb] len (strings only)
    
    Var    Local Var      -      nofSL   off[fp]
	       Value Par
	       
    Ref    Ref Par (ind)  -      nofSL   off[fp]
    
    Const  Constant       -      -       -       value
	
    Reg    Register       regNo  -       -
                          regNo (procAddr)               self   type = procedure
                          lowVal                         HiVal  type = HUGEINT
                          
    RegRel Reg Relative   regNo  -       offset
    
    CC     Condition Code cc     tlist/flist	 R1      R2      cc is the type of the last jump
    
    Proc   Procedure Call
    
    Case   Case Desc      caseAdr tlist=else
   
   
Condition Codes:
	tlist, flist: jmp chains for the true / false threads of control
	
	cc = none => no comparison has to be done, only the chains are set

Procedure/Delegates handling:
	Procedure:
	mode=proc, type=Ptr
	
	Delegate:
	mode=Abs/Ref/Var, type=Proc
	mode=Reg, adr=reg with ProcAddr, breg=reg with SelfAddr, type=Proc
	
    Method() creates a delegate with type=MethodType and 
    
*)
	Item* = RECORD
		mode, level: SHORTINT;
		deref: BOOLEAN;	(* has been dereferenced. For getting the actual type descriptor *) 
		adr, offs, value: LONGINT;
		breg, boffs: LONGINT;	(* pointer to the array bound. Valid only if mode = {RegRel} *)
												(* pointer to self. Valid only if method and self is pointer *)
		tlist, flist: LONGINT;	(* jump list, for CC only *)
		proc: PCBT.Procedure;
		var: PCBT.GlobalVariable;
		type-: PCT.Struct;	(** for testing only! *)
	END;
	
	Label* = LONGINT;
		
CONST
	(* Item Modes ProgTools.Enum 1 Abs Var Ref Const Reg RegRel CC Proc~ *)
	Abs = 1; Var = 2; Ref = 3; Const = 4; Reg = 5; RegRel = 6; 
	CC = 7; Proc = 8; Case = 9;
	
		(* Condition codes ProgTools.Enum 1 ccNone ccAlways ccNever ccEQ ccNE ccGT ccGE ccLT ccLE ccB ccBE ccA ccAE ccF ccNF ~ *)
	ccNone = 0; ccAlways = 1; ccNever = 2; ccEQ = 3; ccNE = 4; ccGT = 5; ccGE = 6; 
	ccLT = 7; ccLE = 8; ccB = 9; ccBE = 10; ccA = 11; ccAE = 12; 
	ccF = 13; ccNF = 14; 

		(*Useful constants*)
	none* = PCLIR.none;
	
		(*Type Descriptor Constants*)
	BaseTypesTable = -8;	(*table with all record extensions*)
	MethodTable = -72;
	IntfMethodTable = 4;
	ArrayFirstElem = 8;	(* first array element *)
	ArrayDimTable = 12;	(* dimension table in dyn arrays *)
	
TYPE
	Code* = PCLIR.Code;

VAR
	(** system types, allocated only when used, set by PCP*)
	delegate*, hdptr*: PCT.Record;
	topscope*: PCT.ModScope;

	CCTab, InvCCTab, SetCCTab: ARRAY 15 OF PCLIR.Opcode;
	InvCC: ARRAY 15 OF SHORTINT;
	
	MethodType: PCT.Delegate;
	
	AParArray, AParBasic, AParProc, AParRec: LONGINT;	(* Parameter Kind Count *)
	AAssBasic, AAssHInt, AAssRec, AAssArray, AAssProc: LONGINT;	(* Assignment Kind Count *)
	ARetBasic, ARetRec, ARetStaticArray, ARetOpenArray, ARetElse: LONGINT;
	
(* ---------- Helper Procedures -------------- *)

(*
PROCEDURE DumpItem(VAR x: Item);
BEGIN
	CASE x.mode OF
	|  Var:
			PCM.LogWStr("Var ["); PCM.LogWStr(x.type.owner.name); PCM.LogWStr("] ");
			PCM.LogWNum(x.offs); PCM.LogWStr("[FP]");
	| Ref:
			PCM.LogWStr("Ref ["); PCM.LogWStr(x.type.owner.name); PCM.LogWStr("] ");
			PCM.LogWNum(x.offs); PCM.LogWStr("[FP]");
	| Const:
			PCM.LogWStr("Const ["); 
			IF x.type = PCT.NilType THEN  PCM.LogWStr("NIL")  ELSE  PCM.LogWStr(x.type.owner.name)  END; 
			PCM.LogWStr("] ");  PCM.LogWNum(x.adr)
	| Reg:
			PCM.LogWStr("Reg ["); PCM.LogWStr(x.type.owner.name); PCM.LogWStr("]  Reg");
			PCM.LogWNum(x.adr)
	ELSE
			PCM.LogWStr("unknown mode "); PCM.LogWNum(x.mode)
	END;
	PCM.LogWLn;
END DumpItem;
*)

PROCEDURE IsString(t: PCT.Struct): BOOLEAN;
BEGIN  RETURN (t = PCT.String) OR (t IS PCT.Array) & (t(PCT.Array).base = PCT.Char8)
END IsString;

(*-----------Register Operation----------------*)

(* GetActivationFrame - return a pointer to the procedure activation frame *)

PROCEDURE GetActivationFrame(code: Code;  level: SHORTINT;  VAR reg: LONGINT);
BEGIN
	ASSERT(level >= 0);
	reg := PCLIR.FP;
	WHILE level > 0 DO
		PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg, 8, reg);
		DEC(level)
	END;
END GetActivationFrame;

PROCEDURE Load*(code: Code;  VAR x: Item);
VAR	tmpReg, frame: LONGINT;  y: Item;  tmpType: PCT.Struct;  size: PCBT.Size; name: ARRAY 32 OF CHAR;
BEGIN
	ASSERT( ~(x.type IS PCT.Record), 210);
	ASSERT(~(x.type IS PCT.Array), 212);
	PCT.GetTypeName(x.type, name);
	size := x.type.size(PCBT.Size);
	IF x.mode = Proc THEN
		PCLIR.EmitLoadAddr(code, x.adr, 0, x.proc);
		PCLIR.EmitLoadConst(code, x.breg, PCLIR.Address, FALSE, 0)
			(* if assigned to a delegate, the self ref is NIL *)
	ELSIF size.type = PCLIR.NoSize THEN
		PCM.LogWLn;
		PCT.GetTypeName(x.type, name); PCM.LogWStr(name);
		PCM.LogWNum(GetStaticSize(x.type));  HALT(99);
	ELSIF x.mode = Reg THEN
		(*already ok*)
	ELSIF (x.type IS PCT.Delegate) & ~(PCT.StaticMethodsOnly IN x.type.flags) THEN
		IF (x.mode = RegRel) OR (x.mode = Abs) OR ((x.mode = Var) & (x.level = 0)) THEN
			tmpType := x.type;
			x.type := PCT.Ptr; y := x;
			Load(code, x);
			INC(y.offs, 4); Load(code, y); x.breg := y.adr;
			x.type := tmpType
		ELSE
			size := PCT.Ptr.size(PCBT.Size);
			LoadAdr(code, x);
			tmpReg := x.adr;
			PCLIR.EmitLoadRelative(code, size.type, size.signed, x.adr, 0, tmpReg);	(*procAddr*)
			PCLIR.EmitLoadRelative(code, size.type, size.signed, x.breg, 4, tmpReg);	(*self*)
		END
	ELSIF x.mode = Var THEN
		GetActivationFrame(code, x.level, frame);
		PCLIR.EmitLoadRelative(code, size.type, size.signed, x.adr, x.offs, frame);
	ELSIF x.mode = Ref THEN
		GetActivationFrame(code, x.level, frame);
		PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, tmpReg, x.offs, frame);
		PCLIR.EmitLoadRelative(code, size.type, size.signed, x.adr, 0, tmpReg);
	ELSIF x.mode = Const THEN
		PCLIR.EmitLoadConst(code, x.adr, size.type, size.signed, x.value);
	ELSIF x.mode = RegRel THEN
		PCLIR.EmitLoadRelative(code, size.type, size.signed, x.adr, x.offs, x.adr);
	ELSIF x.mode = Abs THEN
		PCLIR.EmitLoadAbsolute(code, size.type, size.signed, x.adr, x.offs, x.var)
	ELSIF x.mode = CC THEN
		LoadCC(code, x)
	ELSE
		PCDebug.ToDo(PCDebug.NotImplemented);
	END;
	x.mode := Reg;
	ASSERT(x.mode = Reg, 220);	(*postcondition*)
END Load;

PROCEDURE LoadAdr(code: Code; VAR x: Item);
VAR openarr: BOOLEAN;  temp, frame: LONGINT;
BEGIN
	openarr := (x.type IS PCT.Array) & (x.type(PCT.Array).mode # PCT.static);
	IF x.mode = Proc THEN
		PCLIR.EmitLoadAddr(code, x.adr, 0, x.proc)
	ELSIF x.mode = Reg THEN
		PCM.LogWLn; PCM.LogWStr("PCC.LoadAdr, warning: already reg")
	ELSIF (x.mode = Ref) OR (openarr & (x.mode = Var)) THEN
		GetActivationFrame(code, x.level, frame);
		IF openarr THEN
			x.breg := frame;
			x.boffs := x.offs + x.type(PCT.Array).opendim * 4;	(* offset of dim0 *)
		END;
		PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, x.adr, x.offs, frame);
	ELSIF x.mode = Var THEN
		GetActivationFrame(code, x.level, frame);
		PCLIR.EmitLoadConst(code, temp, PCLIR.Address, FALSE, x.offs);
		PCLIR.Emit12(code, PCLIR.add, x.adr, frame, temp)
	ELSIF x.mode = RegRel THEN
		IF (x.offs # 0) OR (x.adr < 0) THEN
			PCLIR.EmitLoadConst(code, temp, PCLIR.Address, FALSE, x.offs);
			PCLIR.Emit12(code, PCLIR.add, x.adr, x.adr, temp);
		END
		
	ELSIF x.mode = Abs THEN
		PCLIR.EmitLoadAddr(code, x.adr, x.offs, x.var)
	ELSE
		HALT(MAX(INTEGER));
		PCM.LogWLn; PCM.LogWStr("LoadAdr, unimplemented mode: "); PCM.LogWNum(x.mode);
		PCDebug.ToDo(PCDebug.NotImplemented);
	END;
	x.mode := Reg;
END LoadAdr;

PROCEDURE GetDelegateSelfReg(code: Code;  x: Item;  modeBeforeLoad: LONGINT): PCLIR.Register;
VAR  reg: PCLIR.Register;
BEGIN
	IF modeBeforeLoad = Const THEN
		reg := x.adr
	ELSIF modeBeforeLoad = Proc THEN 
		PCLIR.EmitLoadConst(code, reg, PCLIR.Address, FALSE, 0)
	ELSIF ~(PCT.StaticMethodsOnly IN x.type.flags) THEN
		reg := x.breg
	ELSE
		HALT(99)
	END;
	RETURN reg
END GetDelegateSelfReg;

PROCEDURE NilCheck(code: Code; VAR x: Item);
VAR zero: PCLIR.Register;
BEGIN
	IF PCM.NilCheck IN PCM.codeOptions THEN
		Load(code, x);
		PCLIR.EmitLoadConst(code, zero, PCLIR.Address, FALSE, 0);
		PCLIR.Emit02C(code, PCLIR.tae, zero, x.adr, -14);
	END
END NilCheck;

(**-----------Item Creation----------------*)

PROCEDURE MakeItem*(VAR x: Item; o: PCT.Symbol;  deltaLevel:  SHORTINT);
BEGIN
	ASSERT(deltaLevel >= 0, 200);
	x.level := deltaLevel;
	x.type := o.type;
	IF o IS PCT.GlobalVar THEN
		x.mode := Abs;
		x.var := o.adr(PCBT.GlobalVariable);
		IF x.var.owner = PCBT.context THEN x.offs := x.var.offset ELSE x.offs := 0 END
	ELSIF (o IS PCT.Parameter) & o(PCT.Parameter).ref THEN
		x.mode := Ref;
		x.offs := o.adr(PCBT.Variable).offset
	ELSIF (o IS PCT.Parameter) OR (o IS PCT.LocalVar) THEN
		x.mode := Var;
		x.offs := o.adr(PCBT.Variable).offset
	ELSIF o IS PCT.Proc THEN
		x.mode := Proc;
		x.proc := o.adr(PCBT.Procedure);
		x.type := PCT.Ptr;
	ELSE
		HALT(99)
	END
END MakeItem;

PROCEDURE MakeStackItem*(VAR x: Item;  type: PCT.Struct);
BEGIN
	x.mode := RegRel; x.adr := PCLIR.SP;  x.offs := 0;  x.type := type
END MakeStackItem;

PROCEDURE MakeConst*(VAR x: Item;  o: PCT.Const;  type: PCT.Struct);
VAR	t: PCT.Struct;  adr: PCBT.GlobalVariable; r: REAL;  lr: LONGREAL; h: HUGEINT;
BEGIN
	x.mode := Const; t := o.type;
	IF (t = PCT.Int8) OR (t = PCT.Int16) OR (t = PCT.Int32) THEN
		x.value := o.int
	ELSIF t = PCT.Bool THEN
		IF o.bool THEN x.value := True ELSE x.value := False END
	ELSIF PCT.IsCharType(t) OR (t = PCT.Byte) THEN
		x.value := o.int
	ELSIF t = PCT.Set THEN
		x.value := SYSTEM.VAL(LONGINT, o.set)
	ELSIF t = PCT.NilType THEN
		x.value := Nil;
	ELSIF PCT.IsFloatType(t) OR (t = PCT.String) OR (t = PCT.Int64) THEN	(*stored in the const section*)
		IF (o.owner = NIL) OR (o.owner.adr = NIL) THEN
			NEW(adr, PCBT.context);
			IF t = PCT.String THEN
				adr.offset := PCBT.context.NewStringConst(o.str^, o.int)
			ELSIF t = PCT.Int64 THEN
				h := o.long;
				adr.offset := PCBT.context.NewConst(h, 8)
			ELSIF t = PCT.Float32 THEN
				r := SHORT(o.real);
				adr.offset := PCBT.context.NewConst(r, 4);
			ELSE
				lr := o.real;
				adr.offset := PCBT.context.NewConst(lr, 8);
			END;
			IF o.owner # NIL THEN  o.owner.adr := adr  END
		ELSE
			adr := o.owner.adr(PCBT.GlobalVariable)
		END;
		x.mode := Abs;  x.var := adr;  x.offs := adr.offset;
		IF t = PCT.String THEN x.value := o.int END;
	ELSE
		PCDebug.ToDo(PCDebug.NotImplemented)
	END;
	x.type := type
END MakeConst;

PROCEDURE MakeIntConst*(VAR x: Item; val: LONGINT; type: PCT.Struct);
BEGIN
	x.mode := Const; x.value := val; x.type := type
END MakeIntConst;

(* Make TD -  Return an item containing the type descriptor of a record *)

PROCEDURE MakeTD*(VAR x: Item;  type: PCT.Record);
VAR size: PCBT.RecSize;
BEGIN
	x.mode := Abs;
	size := type.size(PCBT.RecSize);
	IF size.td = NIL THEN
		PCBT.AllocateTD(size);
		IF PCT.SystemType IN type.flags THEN  PCT.AddRecord(topscope, type)  END;
	END;
	x.var := size.td;
	x.offs := x.var.offset;  x.type := PCT.Ptr
END MakeTD;

(** -----------Type Handling----------------*)

PROCEDURE GetStaticSize*(t: PCT.Struct): LONGINT;
BEGIN  RETURN  t.size(PCBT.Size).size
END GetStaticSize;

PROCEDURE GetArrayBaseSize(code: Code; VAR size: Item; arr: Item);
VAR t: PCT.Struct; len: Item; mode: SHORTINT;  name: ARRAY 32 OF CHAR;
BEGIN
	ASSERT(arr.type IS PCT.Array);
	t := arr.type(PCT.Array).base;
	IF (t IS PCT.Basic) OR (t IS PCT.Record) OR (t IS PCT.Pointer) OR (t IS PCT.Delegate) THEN
		MakeIntConst(size, GetStaticSize(t), PCT.Int32)
	ELSIF t IS PCT.Array THEN
		mode := t(PCT.Array).mode;
		IF mode = PCT.open THEN
			DEC(arr.boffs, 4); arr.type := t;
			len.mode := RegRel; len.adr := arr.breg; len.offs := arr.boffs; len.type := PCT.Int32;
			GetArrayBaseSize(code, size, arr);
			DOp(code, PCS.times, size, len)
		ELSIF mode = PCT.static THEN
			MakeIntConst(size, GetStaticSize(t), PCT.Int32)
		ELSE
			PCDebug.GetTypeName(t, name); HALT(MAX(INTEGER));
			PCDebug.ToDo(PCDebug.NotImplemented);
			MakeIntConst(size, 4, PCT.Int32)
		END
	ELSE
		PCDebug.GetTypeName(t, name); HALT(MAX(INTEGER));
		PCDebug.ToDo(PCDebug.NotImplemented);
		MakeIntConst(size, 4, PCT.Int32)
	END
END GetArrayBaseSize;

(* Get dim-th dimension. t # NIL is type of this dimension if already known *)

PROCEDURE ArrayDim(code: Code;  VAR res,  arr: Item;  dim: LONGINT);
VAR c: LONGINT;  t: PCT.Array;
BEGIN
	IF arr.type = PCT.String THEN
		ASSERT(arr.value # 0	);
		MakeIntConst(res, arr.value, PCT.Int32)
	ELSE
		t := arr.type(PCT.Array); c := dim;
		WHILE c > 0 DO  t := t.base(PCT.Array); DEC(c)  END;
		IF t.mode = PCT.static THEN
			MakeIntConst(res, t.len, PCT.Int32)
		ELSE
			ASSERT(t.mode = PCT.open);
			ASSERT(arr.mode IN {Reg, RegRel});
			res.mode := RegRel; res.adr := arr.breg; res.offs := arr.boffs - dim*4; res.type := PCT.Int32
		END
	END
END ArrayDim;

PROCEDURE GetTD(code: Code;  r: Item;  VAR td: Item;  superclass: BOOLEAN);
VAR  rec: PCT.Record; level: LONGINT; m: PCLIR.Register;
BEGIN
	ASSERT((r.type IS PCT.Record) OR (r.type IS PCT.Pointer) OR (r.type = PCT.Ptr), 110);
	IF (r.type IS PCT.Pointer) THEN
		td := r;
		NilCheck(code, td);
		Load(code, td);
		td.mode := RegRel;  td.offs := -4;  td.type := PCT.Ptr;
		rec := r.type(PCT.Pointer).baseR;
	ELSIF r.type = PCT.Ptr THEN
		td := r;
		NilCheck(code, td);
		Load(code, td);
		td.mode := RegRel;  td.offs := -4;  td.type := PCT.Ptr;
		ASSERT(~superclass, 111);
	ELSIF r.deref THEN	(*this is a dereferenced pointer*)
		td := r;
		LoadAdr(code, td);
		td.mode := RegRel;  td.offs := -4;  td.type := PCT.Ptr;
		rec := r.type(PCT.Record);
	ELSIF r.mode = Ref THEN
		td.mode := Var;  td.level := r.level; td.offs := r.offs+4;  td.type := PCT.Ptr;
		ASSERT(td.level >= 0);
		rec := r.type(PCT.Record)
	ELSE
		MakeTD(td, r.type(PCT.Record));
		rec := r.type(PCT.Record)
	END;
	IF superclass THEN
		level := rec.size(PCBT.RecSize).level;
		ASSERT(level > 0);
		Load(code, td);
		td.mode := RegRel;  td.offs := BaseTypesTable - 4*(level-1);  td.type := PCT.Ptr
	END
END GetTD;

PROCEDURE TypeCheck*(code: Code;  VAR r: Item;  str: PCT.Struct;  trap, equal: BOOLEAN);
VAR  td, ref: Item;  trapNo: LONGINT;  rec: PCT.Record;
BEGIN
	ASSERT((r.type IS PCT.Record) & (str IS PCT.Record) OR PCT.IsPointer(r.type) & (str IS PCT.Pointer), 200);
	IF str IS PCT.Record THEN
		rec := str(PCT.Record)
	ELSE
		rec := str(PCT.Pointer).baseR
	END;
	GetTD(code, r, td, FALSE);  Load(code, td);
	MakeTD(ref, rec);  Load(code, ref);
	IF equal THEN
		trapNo := PCM.TypeEqualTrap;
	ELSE
		td.mode := RegRel;  td.offs := BaseTypesTable - 4 * rec.size(PCBT.RecSize).level;
		Load(code, td);
		trapNo := PCM.TypeCheckTrap
	END;
	IF trap THEN
		PCLIR.Emit02C(code, PCLIR.tne, td.adr, ref.adr, trapNo);
		r.type := str
	ELSE
		InitCC(r, ccEQ, td.adr, ref.adr)
	END
END TypeCheck;

(* Built-In array len *)

PROCEDURE Len*(code: Code; VAR arr, dim: Item);
VAR res: Item;
BEGIN
	ASSERT(arr.type IS PCT.Array, 200);
	IF arr.mode IN {Var, Ref} THEN LoadAdr(code, arr) END;
	IF dim.mode = Const THEN
		ASSERT(PCT.IsCardinalType(dim.type), 201);
		ArrayDim(code, res, arr, dim.value); arr := res
	ELSE
		PCDebug.ToDo(PCDebug.NotImplemented)
	END
END Len;
 
PROCEDURE GenConv(code: Code;  op: PCLIR.Opcode;  VAR x: Item;  size: PCLIR.Size;  signed: BOOLEAN);
VAR srcsize: PCBT.Size;
BEGIN
	srcsize := x.type.size(PCBT.Size);
	IF (srcsize.type # size) (*OR (srcsize.signed # signed)*) THEN
		PCLIR.EmitConv(code, op, x.adr, size, signed, x.adr)
	END;
END GenConv;

(**-----------Stack Handling --------------------*)

(** Enter - create a procedure activation frame, allocate size bytes local variables *)

PROCEDURE Enter*(code: Code; adr: PCM.Attribute);
BEGIN
	PCLIR.EmitEnter(code, PCBT.OberonCC, adr)
END Enter;

(** Leave - remove a procedure activation frame, remove size bytes of parameters *)

PROCEDURE Leave*(code: Code;  proc: PCT.Proc);
VAR size: LONGINT;
BEGIN
	size := 0;
	IF (proc # NIL) THEN
		size :=  proc.adr(PCBT.Procedure).parsize-8;
		IF (proc.type IS PCT.Record) THEN
			INC(size, 8)
		ELSIF (proc.type IS PCT.Array) THEN
			IF proc.type(PCT.Array).mode = PCT.open THEN
				size := 0;
			ELSE
				INC(size, 4);
			END;
		END
	END;
	PCLIR.EmitExit(code, PCBT.OberonCC, size)
END Leave;

(* StackAllocate - allocate size bytes on the stack, return new top of stack *)

PROCEDURE StackAllocate(code: Code; size: LONGINT; VAR tos: Item);
VAR reg: PCLIR.Register;
BEGIN
	INC(size, (-size) MOD 4);	(*align up to 4*)
	PCLIR.EmitLoadConst(code, reg, PCLIR.Address, FALSE, size);
	PCLIR.Emit12(code, PCLIR.sub, tos.adr, PCLIR.SP, reg);
	PCLIR.Emit01(code, PCLIR.loadsp, tos.adr);
	tos.mode := RegRel; tos.adr := PCLIR.SP; tos.offs := 0; tos.type := PCT.Int32
END StackAllocate;

PROCEDURE FreeStack*(code: Code;  type: PCT.Struct);
VAR  size: LONGINT;  reg: PCLIR.Register;
BEGIN
	size := GetStaticSize(type);
	INC(size, (-size) MOD 4);	(*align*)
	PCLIR.EmitLoadConst(code, reg, PCLIR.Address, FALSE, size);
	PCLIR.Emit12(code, PCLIR.add, reg, PCLIR.SP, reg);
	PCLIR.Emit01(code, PCLIR.loadsp, reg);
END FreeStack;

PROCEDURE RemoveArys*(code: Code; aryNbr: LONGINT);
VAR
	reg: PCLIR.Register;
	i: LONGINT;
BEGIN
	ASSERT(aryNbr > 0);
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg, 0, PCLIR.SP);
	FOR i := 0 TO aryNbr-2 DO
		PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg, 0, reg);
	END;
	PCLIR.Emit01(code, PCLIR.loadsp, reg);
END RemoveArys;

(*
	return statement of procedure that returns open array, calls a procedure that itself returns
	either an open or static array
*)
PROCEDURE ReturnProc(code: Code; x: Item; proc: PCT.Proc);
VAR
	size, dim, len: Item;
	aligned: BOOLEAN;
	parSize, offs, staticSize: LONGINT;
	reg, reg2, reg3, src, base, const, mask: PCLIR.Register;
	type, itemType: PCT.Struct;
BEGIN
	parSize := proc.adr(PCBT.Procedure).parsize;
	
	LoadAdr(code, x);
		(* compute size *)
	IF x.type(PCT.Array).mode = PCT.static THEN
		dim.mode := Const; dim.value := x.type(PCT.Array).len;
		GetArrayBaseSize(code, size, x);
		DOp(code, PCS.times, size, dim);
		Load(code, size);
		GenConv(code, PCLIR.convu, size, PCLIR.Address, FALSE);
	ELSE
			(* function returns open array *)
		type := proc.type(PCT.Array).base;
		len.mode := Reg; len.type := PCT.Int32;
		PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, src, 0, PCLIR.SP);
		size.mode := Reg; size.type := PCT.Int32;
		PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, size.adr, -4, src);
		offs := 8;
		WHILE (type # NIL) & (type IS PCT.Array) & (type(PCT.Array).mode = PCT.open) DO
			PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, len.adr, -offs, src);
			DOp(code, PCS.times, size, len);
			type := type(PCT.Array).base;
			INC(offs, 4);
		END;
		staticSize := GetStaticSize(type);
		IF staticSize > 1 THEN
			PCLIR.EmitLoadConst(code, len.adr, PCLIR.Int32, FALSE, staticSize);
			DOp(code, PCS.times, size, len);
		END;
	END;

	aligned := (size.mode = Const) & (size.value MOD 4 = 0);
	
	(* avoid producing wrong code ??? *)
	PCLIR.Emit01(code, PCLIR.push, PCLIR.FP);
	PCLIR.Emit10(code, PCLIR.pop, reg3, PCLIR.Address);
	PCLIR.EmitLoadConst(code, const, PCLIR.Address, FALSE, parSize + 4);
	PCLIR.Emit12(code, PCLIR.add, reg2, reg3, const);
	
		(*allocate*)
	PCLIR.Emit12(code, PCLIR.sub, reg, reg2, size.adr);
	IF ~aligned THEN
		PCLIR.EmitLoadConst(code, mask, PCLIR.Address, FALSE, 0FFFFFFFCH);
		PCLIR.Emit12(code, PCLIR.and, reg, reg, mask);
	END;
	
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, base, parSize, PCLIR.FP);
	PCLIR.Emit01(code, PCLIR.push, base);
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 4, PCLIR.FP);	(* IP *)
	PCLIR.Emit01(code, PCLIR.push, reg3);
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 0, PCLIR.FP); 	(* FP *)
	PCLIR.Emit01(code, PCLIR.push, reg3);
	PCLIR.Emit01(code, PCLIR.push, reg);
	
	itemType := x.type;
	type := proc.type;
	offs := 4;
	WHILE (type # NIL) & (type IS PCT.Array) & (type(PCT.Array).mode = PCT.open) DO
		IF itemType(PCT.Array).mode = PCT.static THEN
			PCLIR.EmitLoadConst(code, reg3, PCLIR.Int32, FALSE, itemType(PCT.Array).len);
		ELSE
			PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, -offs, src);
		END;
		PCLIR.EmitStoreRelative(code, -offs, base, reg3);
		INC(offs, 4);
		itemType := itemType(PCT.Array).base;
		type := type(PCT.Array).base;
	END;
	
	IF x.type(PCT.Array).mode = PCT.open THEN
		offs := 20;
	ELSE
		offs := 16;
	END;
	PCLIR.EmitLoadConst(code, reg3, PCLIR.Int32, FALSE, offs);
	PCLIR.Emit12(code, PCLIR.add, src, PCLIR.SP, reg3);
	
		(*move*)
	PCLIR.Emit12(code, PCLIR.add, src, src, size.adr);
	PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, 1);
	PCLIR.Emit12(code, PCLIR.sub, src, src, const);
	PCLIR.Emit12(code, PCLIR.add, reg, reg, size.adr);
	PCLIR.Emit12(code, PCLIR.sub, reg, reg, const);
	PCLIR.Emit03(code, PCLIR.moveDown, src, reg, size.adr);
	
		(* set FP *)
	PCLIR.Emit10(code, PCLIR.pop, reg, PCLIR.Address);
	PCLIR.EmitLoadConst(code, reg3, PCLIR.Address, FALSE, 12);
	PCLIR.Emit12(code, PCLIR.sub, reg, reg, reg3);
	PCLIR.Emit01(code, PCLIR.loadfp, reg);
	
		(* restore array base, caller's IP and FP *)
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 8, PCLIR.SP);
	PCLIR.EmitStoreRelative(code, 8, PCLIR.FP, reg3);
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 4, PCLIR.SP);
	PCLIR.EmitStoreRelative(code, 4, PCLIR.FP, reg3);
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 0, PCLIR.SP);
	PCLIR.EmitStoreRelative(code, 0, PCLIR.FP, reg3);
	
	PCLIR.Emit01(code, PCLIR.loadsp, PCLIR.FP);
END ReturnProc;

(*
	procedure returns open array
*)
PROCEDURE ReturnArray(code: Code; x: Item; proc: PCT.Proc);
VAR
	size, dim: Item;
	parSize, offs: LONGINT;
	mask, reg, reg2, reg3, base, const, const2, dimReg: PCLIR.Register;
	begin, end, skipSPSet: Label;
	aligned, skip, smallerStack: BOOLEAN;
	type, itemType: PCT.Struct;
BEGIN
	smallerStack := FALSE;
	parSize := proc.adr(PCBT.Procedure).parsize;
	
	LoadAdr(code, x);
		(* compute size *)
	IF x.type(PCT.Array).mode = PCT.static THEN
		dim.mode := Const; dim.value := x.type(PCT.Array).len;
		IF ~x.deref THEN
			smallerStack := TRUE;
		END;
	ELSE
		dim.mode := RegRel; dim.adr := x.breg; dim.offs := x.boffs; dim.type := PCT.Int32;
	END;
	GetArrayBaseSize(code, size, x);
	
	aligned := (size.mode = Const) & (size.value MOD 4 = 0);
	DOp(code, PCS.times, size, dim);
	skip := (size.mode = Const) & (size.value < 4096);
	Load(code, size);
	GenConv(code, PCLIR.convu, size, PCLIR.Address, FALSE);
	
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, base, parSize, PCLIR.FP);
	PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, GetDims(proc.type)*4 + 4);
	PCLIR.Emit12(code, PCLIR.sub, reg2, base, const);
	
		(*allocate*)
	(* PCLIR.Emit12(code, PCLIR.sub, reg, PCLIR.SP, size.adr); *)
	PCLIR.Emit12(code, PCLIR.sub, reg, reg2, size.adr);
	IF ~aligned THEN
		PCLIR.EmitLoadConst(code, mask, PCLIR.Address, FALSE, 0FFFFFFFCH);
		PCLIR.Emit12(code, PCLIR.and, reg, reg, mask);
	END;
	
	IF ~smallerStack THEN
	
		skipSPSet := code.pc;
		PCLIR.Emit02C(code, PCLIR.jle, PCLIR.SP, reg, -1);
	
		PCLIR.Emit01(code, PCLIR.loadsp, reg);
		IF ~skip THEN
			DefLabel(code, begin);
		
			PCLIR.EmitLoadConst(code, const, PCLIR.Address, FALSE, 1000H);
			PCLIR.Emit12(code, PCLIR.sub, reg2, reg2, const);
		
			end := code.pc;
			PCLIR.Emit02C(code, PCLIR.jb, reg2, PCLIR.SP, -1);
		
			PCLIR.EmitLoadConst(code, const, PCLIR.Int8, FALSE, 1000H);
			PCLIR.EmitStoreRelative(code, 0, reg2, const);
		
			PCLIR.Emit0C(code, PCLIR.jmp, begin);
		
			PCLIR.FixList(code, end, code.pc);
			PCLIR.Emit0C(code, PCLIR.label, 0);
		END;
	
		PCLIR.FixList(code, skipSPSet, code.pc);
		PCLIR.Emit0C(code, PCLIR.label, 0);
	END;

	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, base, parSize, PCLIR.FP);
	PCLIR.Emit01(code, PCLIR.push, base);
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 4, PCLIR.FP);	(* IP *)
	PCLIR.Emit01(code, PCLIR.push, reg3);
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 0, PCLIR.FP); 	(* FP *)
	PCLIR.Emit01(code, PCLIR.push, reg3);
	PCLIR.Emit01(code, PCLIR.push, reg);

	itemType := x.type;
	type := proc.type;
	offs := 0;
	WHILE (type # NIL) & (type IS PCT.Array) & (type(PCT.Array).mode = PCT.open) DO
		IF itemType(PCT.Array).mode = PCT.static THEN
			PCLIR.EmitLoadConst(code, reg3, PCLIR.Int32, FALSE, itemType(PCT.Array).len);
		ELSE
			PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, x.boffs - offs, x.breg);
		END;
		PCLIR.EmitStoreRelative(code, - 4 - offs, base, reg3);
		INC(offs, 4);
		itemType := itemType(PCT.Array).base;
		type := type(PCT.Array).base;
	END;

		(*move*)
	PCLIR.Emit12(code, PCLIR.add, x.adr, x.adr, size.adr);
	PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, 1);
	PCLIR.Emit12(code, PCLIR.sub, x.adr, x.adr, const);
	PCLIR.Emit12(code, PCLIR.add, reg, reg, size.adr);
	PCLIR.Emit12(code, PCLIR.sub, reg, reg, const);
	PCLIR.Emit03(code, PCLIR.moveDown, x.adr, reg, size.adr);
	
		(* set FP *)
	PCLIR.Emit10(code, PCLIR.pop, reg, PCLIR.Address);
	PCLIR.EmitLoadConst(code, reg3, PCLIR.Address, FALSE, 12);
	PCLIR.Emit12(code, PCLIR.sub, reg, reg, reg3);
	PCLIR.Emit01(code, PCLIR.loadfp, reg);
	
		(* restore array base, caller's IP and FP *)
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 8, PCLIR.SP);
	PCLIR.EmitStoreRelative(code, 8, PCLIR.FP, reg3);
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 4, PCLIR.SP);
	PCLIR.EmitStoreRelative(code, 4, PCLIR.FP, reg3);
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg3, 0, PCLIR.SP);
	PCLIR.EmitStoreRelative(code, 0, PCLIR.FP, reg3);
	
	PCLIR.Emit01(code, PCLIR.loadsp, PCLIR.FP);
END ReturnArray;

PROCEDURE GetDims*(t: PCT.Struct): LONGINT;
VAR dims: LONGINT;
BEGIN
	WHILE (t # NIL) & (t IS PCT.Array) & (t(PCT.Array).mode = PCT.open) DO
		INC(dims);
		t := t(PCT.Array).base;
	END;
	RETURN dims;
END GetDims;

(** LocalArray - create a local copy of an array passed as a reference *)

PROCEDURE LocalArray*(code: Code;  par: PCT.Parameter);
VAR  x, size, dim: Item;  reg, mask: PCLIR.Register;  aligned: BOOLEAN;  offs: LONGINT;
	reg2, const: PCLIR.Register; begin, end: Label; skip: BOOLEAN;
BEGIN
	ASSERT(~par.ref);
	MakeItem(x, par, 0);  LoadAdr(code, x);  offs := x.offs;
		(*compute size*)
	dim.mode := RegRel;  dim.adr := x.breg;  dim.offs := x.boffs;  dim.type := PCT.Int32;
	GetArrayBaseSize(code, size, x);
	aligned := (size.mode = Const) & (size.value MOD 4 = 0);
	DOp(code, PCS.times, size, dim);
	skip := (size.mode = Const) & (size.value < 4096);
	Load(code, size);
	GenConv(code, PCLIR.convu, size, PCLIR.Address, FALSE);

	PCLIR.EmitLoadConst(code, const, PCLIR.Address, FALSE, 0);
	PCLIR.Emit12(code, PCLIR.add, reg2, PCLIR.SP, const);
	
		(*allocate*)
	PCLIR.Emit12(code, PCLIR.sub, reg, PCLIR.SP, size.adr);
	IF ~aligned THEN
		PCLIR.EmitLoadConst(code, mask, PCLIR.Address, FALSE, 0FFFFFFFCH);
		PCLIR.Emit12(code, PCLIR.and, reg, reg, mask);
	END;

	PCLIR.Emit01(code, PCLIR.loadsp, reg);
	IF ~skip THEN
	
		DefLabel(code, begin);
		
		PCLIR.EmitLoadConst(code, const, PCLIR.Address, FALSE, 1000H);
		PCLIR.Emit12(code, PCLIR.sub, reg2, reg2, const);
		
		end := code.pc;
		PCLIR.Emit02C(code, PCLIR.jb, reg2, PCLIR.SP, -1);
		
		PCLIR.EmitLoadConst(code, const, PCLIR.Int8, FALSE, 1000H);
		PCLIR.EmitStoreRelative(code, 0, reg2, const);
		
		PCLIR.Emit0C(code, PCLIR.jmp, begin);
		
		PCLIR.FixList(code, end, code.pc);
		PCLIR.Emit0C(code, PCLIR.label, 0);
	
	END;
		(*move*)
	PCLIR.Emit03(code, PCLIR.move, x.adr, reg, size.adr);
		(*store address*)
	PCLIR.EmitStoreRelative(code, offs, PCLIR.FP, PCLIR.SP)
END LocalArray;

(** AllocateLocalArray - create a local dynamic array *)

PROCEDURE AllocateLocalArray*(code: Code;  p: PCT.LocalVar;  size: Item);
VAR x, bsize: Item;  reg, mask: PCLIR.Register;  aligned: BOOLEAN;  offs: LONGINT;
BEGIN
	MakeItem(x, p, 0);  LoadAdr(code, x);  offs := x.offs;
		(*compute size*)
	Load(code, size);
	PCLIR.EmitStoreRelative(code, x.boffs, x.breg, size.adr);	(*set dimension*)
	GetArrayBaseSize(code, bsize, x);
	aligned := (bsize.mode = Const) & (bsize.value MOD 4 = 0);
	DOp(code, PCS.times, size, bsize);
	Load(code, size);
		(*allocate*)
	PCLIR.Emit12(code, PCLIR.sub, reg, PCLIR.SP, size.adr);
	IF ~aligned THEN
		PCLIR.EmitLoadConst(code, mask, PCLIR.Address, FALSE, 0FFFFFFFCH);
		PCLIR.Emit12(code, PCLIR.and, reg, reg, mask)
	END;
	PCLIR.Emit01(code, PCLIR.loadsp, reg);
	PCLIR.EmitStoreRelative(code, offs, PCLIR.FP, PCLIR.SP)
END AllocateLocalArray;

(** PushRetDesc - Push the return descriptor for items with non-primive types *)

PROCEDURE PushRetDesc*(code: Code;  i: Item);
VAR size: LONGINT;  reg: PCLIR.Register;  type: PCT.Struct;
BEGIN
	type := i.type;
	size := GetStaticSize(type);
(*
	ASSERT(size MOD 4 = 0);
*)
	IF type IS PCT.Record THEN
		PCLIR.EmitLoadConst(code, reg, PCLIR.Int32, TRUE, size);
		PCLIR.Emit01(code, PCLIR.push, reg);
	END;
	LoadAdr(code, i);
	PCLIR.Emit01(code, PCLIR.push, i.adr);
END PushRetDesc;

(** PushRetDesc1 - Allocate temporary and push the return descriptor for items with non-primitive types *)

PROCEDURE PushRetDesc1*(code: Code;  fp: PCT.Symbol);
VAR size: LONGINT;  reg, reg2, temp: PCLIR.Register;
BEGIN
	ASSERT((fp IS PCT.Parameter) & ~fp(PCT.Parameter).ref, 500);
	ASSERT((fp.type IS PCT.Record) OR (fp.type IS PCT.Array), 501);
	size := GetStaticSize(fp.type) + ((-GetStaticSize(fp.type)) MOD 4);
	
(*
	ASSERT(size MOD 4 = 0);
*)
	PCLIR.EmitLoadConst(code, reg, PCLIR.Address, FALSE, size);
	PCLIR.Emit12(code, PCLIR.sub, reg2, PCLIR.SP, reg);
	PCLIR.Emit01(code, PCLIR.loadsp, reg2);
	IF fp.type IS PCT.Record THEN
		PCLIR.Emit01(code, PCLIR.push, reg);
		PCLIR.EmitLoadConst(code, temp, PCLIR.Address, FALSE, 4);
		PCLIR.Emit12(code, PCLIR.add, reg, PCLIR.SP, temp);
		PCLIR.Emit01(code, PCLIR.push, reg)
	ELSE
		PCLIR.Emit01(code, PCLIR.push, PCLIR.SP)
	END;
END PushRetDesc1;

(** PushRetDesc2 - Push the current procedure's return descriptor *)

PROCEDURE PushRetDesc2*(code: Code; proc: PCT.Proc);
	VAR parSize: LONGINT; size, dst: Item;
BEGIN
	parSize := proc.adr(PCBT.Procedure).parsize;
	IF proc.type IS PCT.Record THEN
		size.mode := Var; size.offs := parSize+4; size.level := 0; size.type := PCT.Int32;
		dst.mode := Var; dst.offs := parSize; dst.level := 0; dst.type := PCT.Int32;
		Load(code, size); PCLIR.Emit01(code, PCLIR.push, size.adr);
		Load(code, dst); PCLIR.Emit01(code, PCLIR.push, dst.adr)
	ELSIF proc.type IS PCT.Array THEN
		dst.mode := Var; dst.offs := parSize; dst.level := 0; dst.type := PCT.Int32;
		Load(code, dst); PCLIR.Emit01(code, PCLIR.push, dst.adr)
	ELSE
		HALT(99)
	END;
END PushRetDesc2;


(*
	increase stack by number of open dimensions + 1,
	push pointer to base (old SP) onto stack
*)
PROCEDURE PushOpenAryRetDesc*(code: Code; t: PCT.Struct);
VAR
	reg, reg2: PCLIR.Register;
	dims: LONGINT;
BEGIN
	dims := GetDims(t);
	(*
	WHILE (t # NIL) & (t IS PCT.Array) & (t(PCT.Array).mode = PCT.open) DO
		INC(dims);
		t := t(PCT.Array).base;
	END;
	*)
	ASSERT(dims > 0);
	INC(dims);
	PCLIR.EmitLoadConst(code, reg, PCLIR.Address, FALSE, dims*4);
	PCLIR.Emit12(code, PCLIR.sub, reg2, PCLIR.SP, reg);
	PCLIR.Emit01(code, PCLIR.loadsp, reg2);
	
	PCLIR.EmitLoadConst(code, reg, PCLIR.Address, FALSE, dims*4);
	PCLIR.Emit12(code, PCLIR.add, reg2, PCLIR.SP, reg);
	PCLIR.Emit01(code, PCLIR.push, reg2);
END PushOpenAryRetDesc;

PROCEDURE PushStatAryRetDesc*(code: Code; ary: PCT.Struct);
VAR
	size: LONGINT;
	reg, reg2: PCLIR.Register;
BEGIN
	ASSERT(ary IS PCT.Array);
	ASSERT(ary(PCT.Array).mode = PCT.static);
	size := GetStaticSize(ary)  + ((-GetStaticSize(ary)) MOD 4);
	PCLIR.EmitLoadConst(code, reg, PCLIR.Address, FALSE, size);
	PCLIR.Emit12(code, PCLIR.sub, reg2, PCLIR.SP, reg);
	PCLIR.Emit01(code, PCLIR.loadsp, reg2);
	PCLIR.Emit01(code, PCLIR.push, PCLIR.SP);
END PushStatAryRetDesc;

PROCEDURE PushOpenAryParams*(code: Code; formal, actual: PCT.Struct; VAR ofs: LONGINT; parNbr: LONGINT);
VAR
	dims: LONGINT;
	base, const, reg, len: PCLIR.Register;
BEGIN
	PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, ofs);
	PCLIR.Emit12(code, PCLIR.add, base, PCLIR.SP, const);
	WHILE parNbr > 1 DO
		PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, base, 0, base);
		DEC(parNbr);
	END;
	dims := 1;
	WHILE (formal # NIL) & (formal IS PCT.Array) & (formal(PCT.Array).mode = PCT.open) DO
		IF actual(PCT.Array).mode = PCT.static THEN
			PCLIR.EmitLoadConst(code, len, PCLIR.Int32, FALSE, actual(PCT.Array).len);
		ELSE
			PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg, 0, base);
			PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, len, -(4*dims), reg);
		END;
		PCLIR.Emit01(code, PCLIR.push, len);
		
		INC(dims);
		formal := formal(PCT.Array).base;
		actual := actual(PCT.Array).base;
	END;
	PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, 4);
	PCLIR.Emit12(code, PCLIR.add, base, base, const);
	PCLIR.Emit01(code, PCLIR.push, base);
	(* INC(ofs, (dims-1)*4 + 4); *)
END PushOpenAryParams;

PROCEDURE PrepStack*(code: Code; formal, actual: PCT.Struct);
VAR
	size, dims: LONGINT;
	lenReg, top, topStatic, base, const: PCLIR.Register;
	form, act: PCT.Struct;
BEGIN
	act := actual;
	form := formal;
	dims := 0;
	WHILE (form # NIL) & (form IS PCT.Array) & (form(PCT.Array).mode = PCT.open) DO
		IF act(PCT.Array).mode = PCT.open THEN
			INC(dims);
		END;
		form := form(PCT.Array).base;
		act := act(PCT.Array).base;
	END;
	IF dims > 0 THEN
		PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, dims*4 + 4);
		PCLIR.Emit12(code, PCLIR.sub, top, PCLIR.SP, const);
		PCLIR.Emit01(code, PCLIR.loadsp, top);
		PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, dims*4 + 4);
		PCLIR.Emit12(code, PCLIR.add, base, PCLIR.SP, const);
		PCLIR.Emit01(code, PCLIR.push, base);
	ELSE
		size := GetStaticSize(actual);
		INC(size, (-size) MOD 4);
		PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, size);
		PCLIR.Emit12(code, PCLIR.sub, top, PCLIR.SP, const);
		PCLIR.Emit01(code, PCLIR.loadsp, top);
		PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, size);
		PCLIR.Emit12(code, PCLIR.add, base, PCLIR.SP, const);
		PCLIR.Emit01(code, PCLIR.push, base);
		PCLIR.EmitLoadConst(code, const, PCLIR.Int32, FALSE, 4);
		PCLIR.Emit12(code, PCLIR.add, topStatic, PCLIR.SP, const);
		PCLIR.Emit01(code, PCLIR.push, topStatic);
	END;
END PrepStack;

PROCEDURE FixRetDesc*(code: Code; type: PCT.Struct; openAryParams: LONGINT; VAR ofs: LONGINT);
VAR base, reg: PCLIR.Register;
BEGIN
	IF (openAryParams > 0) & ((type IS PCT.Record) OR (type IS PCT.Array)) THEN
		PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, base, 0, PCLIR.SP);
		WHILE openAryParams > 1 DO
			PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, base, 0, base);
			DEC(openAryParams);
		END;
		IF type IS PCT.Record THEN
			PCLIR.EmitLoadRelative(code, PCLIR.Int32, FALSE, reg, 4, base);	(* size *)
			PCLIR.Emit01(code, PCLIR.push, reg);
			PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg, 0, base);	(* link *)
			PCLIR.Emit01(code, PCLIR.push, reg);
			INC(ofs, 8);
		ELSE
			ASSERT(type IS PCT.Array);
			PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg, 0, base);	(* link *)
			PCLIR.Emit01(code, PCLIR.push, reg);
			INC(ofs, 4);
		END;
	END;
END FixRetDesc;

(**-----------Memory Handling------------------*)

PROCEDURE CopyBlock(code: Code;  VAR dst, src: Item;  size: LONGINT);
VAR reg: PCLIR.Register;
BEGIN
	LoadAdr(code, dst);
	IF ~(src.mode IN {Reg, Const}) THEN
		LoadAdr(code, src); src.mode := RegRel; src.offs := 0
	END;
	IF size = 1 THEN
		src.type := PCT.Int8;
		Load(code, src);
		PCLIR.EmitStoreRelative(code, 0, dst.adr, src.adr)
	ELSIF size = 2 THEN
		src.type := PCT.Int16;
		Load(code, src);
		PCLIR.EmitStoreRelative(code, 0, dst.adr, src.adr)
	ELSIF size = 4 THEN
		src.type := PCT.Int32;
		Load(code, src);
		PCLIR.EmitStoreRelative(code, 0, dst.adr, src.adr)
(*
	ELSIF size = 8 THEN
		src.type := PCT.Int32; src2 := src;
		Load(code, src);
		PCLIR.EmitStoreRelative(code, 0, dst.adr, src.adr);
		src2.offs := 4;
		Load(code, src2);
		PCLIR.EmitStoreRelative(code, 4, dst.adr, src2.adr);
*)
	ELSE
		ASSERT(src.mode IN {Reg, RegRel});	(*don't support const case*)
		src.mode := Reg;	(*undo common case*)
		PCLIR.EmitLoadConst(code, reg, PCLIR.Int32, TRUE, size);
		PCLIR.Emit03(code, PCLIR.move, src.adr, dst.adr, reg)
	END
END CopyBlock;

PROCEDURE MoveBlock*(code: Code;  VAR dstAdr, srcAdr, size: Item);
BEGIN
	ASSERT(dstAdr.type = PCT.Int32);
	ASSERT(srcAdr.type = PCT.Int32);
	ASSERT(size.type = PCT.Int32);
	Load(code, dstAdr); Load(code, srcAdr); Load(code, size);
	PCLIR.Emit03(code, PCLIR.move, srcAdr.adr, dstAdr.adr, size.adr)
END MoveBlock;

PROCEDURE MoveConvertString(code: Code;  VAR src, dst, size: PCLIR.Register; srcSize, dstSize: PCLIR.Size);
	VAR loop, exit: Label; src1, dst1, size1, val, step: PCLIR.Register; 
BEGIN
	IF (srcSize = dstSize) THEN
		PCLIR.Emit03(code, PCLIR.move, src, dst, size)
	ELSE
		PCLIR.Emit01(code, PCLIR.kill, src);
		PCLIR.Emit01(code, PCLIR.kill, dst);
		PCLIR.Emit01(code, PCLIR.kill, size);
		DefLabel(code, loop);
		PCLIR.EmitPhi(code, src, src, none);
		PCLIR.EmitPhi(code, dst, dst, none);
		PCLIR.EmitPhi(code, size, size, none);
		PCLIR.EmitLoadConst(code, step, PCLIR.Int32, TRUE, 0);
		exit := code.pc;
		PCLIR.Emit02C(code, CCTab[ccLE], size, step, -1);
			(* move [dst], [src] with convertion *)
		PCLIR.EmitLoadRelative(code, srcSize, FALSE, val, 0, src);
		PCLIR.EmitConv(code, PCLIR.convu, val, dstSize, FALSE, val);
		PCLIR.EmitStoreRelative(code, 0, dst, val);
			(* inc src pointer *)
		PCLIR.EmitLoadConst(code, step, PCLIR.Address, FALSE, PCLIR.NofBytes(srcSize));
		PCLIR.Emit12(code, PCLIR.add, src1, src, step);
		PCLIR.PatchPhi(code, src, src1);
			(* inc dst pointer *)
		PCLIR.EmitLoadConst(code, step, PCLIR.Address, FALSE, PCLIR.NofBytes(dstSize));
		PCLIR.Emit12(code, PCLIR.add, dst1, dst, step);
		PCLIR.PatchPhi(code, dst, dst1);
			(* dec size *)
		PCLIR.EmitLoadConst(code, step, PCLIR.Address, FALSE, 1);
		PCLIR.Emit12(code, PCLIR.sub, size1, size, step);
		PCLIR.PatchPhi(code, size, size1);
			(* jmp loop *)
		PCLIR.Emit01(code, PCLIR.kill, src1);
		PCLIR.Emit01(code, PCLIR.kill, dst1);
		PCLIR.Emit01(code, PCLIR.kill, size1);
		Jmp(code, loop);
		FixJmp(code, exit)
	END
END MoveConvertString;

PROCEDURE MoveString*(code: Code;  VAR src, dst: Item);	(* copy until 0X *)
(*
	Heuristic: perform move with "LEN(dst)" instead of "LEN(dst)-1", because
	usually array sizes are powers of two (thus move can be optimized)
*)
VAR  srcSize, dstSize, cc, zero: Item;  label, exit: Label; srcElemSize, dstElemSize: PCLIR.Size;
BEGIN
	LoadAdr(code, src);  LoadAdr(code, dst);
	ArrayDim(code, srcSize, src, 0);
	ArrayDim(code, dstSize, dst, 0);
	IF src.type = PCT.String THEN srcElemSize := PCLIR.Int8 ELSE srcElemSize := src.type(PCT.Array).base.size(PCBT.Size).type END;
	IF dst.type = PCT.String THEN dstElemSize := PCLIR.Int8 ELSE dstElemSize := dst.type(PCT.Array).base.size(PCBT.Size).type END;
	IF (srcSize.mode = Const) & (dstSize.mode = Const) THEN	(*static sizes*)
		IF (srcSize.value <= dstSize.value) THEN
			Load(code, srcSize);
			MoveConvertString(code, src.adr, dst.adr, srcSize.adr, srcElemSize, dstElemSize)
(*
			PCLIR.Emit03(code, PCLIR.move, src.adr, dst.adr, srcSize.adr)
*)
		ELSE
			Load(code, dstSize);
			MoveConvertString(code, src.adr, dst.adr, dstSize.adr, srcElemSize, dstElemSize);
(*
			PCLIR.Emit03(code, PCLIR.move, src.adr, dst.adr, dstSize.adr);
*)
			PCLIR.EmitLoadConst(code, zero.adr, PCLIR.Int8, FALSE, 0);
			(* i do not understand why EmitStoreRelative puts the wrong register ??? *)
			IF PCM.bigEndian THEN
				PCLIR.EmitStoreRelative(code, dstSize.value-1, dst.adr, zero.adr)
			ELSE
				PCLIR.EmitStoreRelative(code, -1, dst.adr, zero.adr)
			END
		END
	ELSE
		Load(code, srcSize);  Load(code, dstSize);
		cc := srcSize;
		RelOp(code, PCS.gtr, cc, dstSize); 
		label := -1;  Jcc(code, label, cc);
			(*src <= dst *)
		MoveConvertString(code, src.adr, dst.adr, srcSize.adr, srcElemSize, dstElemSize);
(*
		PCLIR.Emit03(code, PCLIR.move, src.adr, dst.adr, srcSize.adr);
*)
		exit := -1;  Jmp(code, exit);
		FixJmp(code, label);  PCLIR.Emit0C(code, PCLIR.label, 0);
			(* src > dst *)
		MoveConvertString(code, src.adr, dst.adr, dstSize.adr, srcElemSize, dstElemSize);
(*
		PCLIR.Emit03(code, PCLIR.move, src.adr, dst.adr, dstSize.adr);
*)
		(* the same problem as above, but here a fix is not easy, so i leave this as an error in the compiler for
		big endian machines. this means: be careful when using the COPY proc *)
		IF ~PCM.bigEndian THEN
			PCLIR.EmitLoadConst(code, zero.adr, PCLIR.Int8, FALSE, 0);
			PCLIR.EmitStoreRelative(code, -1, dst.adr, zero.adr);
		END;
		FixJmp(code, exit);  PCLIR.Emit0C(code, PCLIR.label, 0);
	END
(*
	IF (dstElemSize # PCLIR.Int8) OR (srcElemSize # PCLIR.Int8) THEN
		Load(code, srcSize);
		MoveConvertString(code, srcSize.adr, src.adr, dst.adr, srcElemSize, dstElemSize)
	ELSE
		IF (srcSize.mode = Const) & (dstSize.mode = Const) THEN	(*static sizes*)
			IF (srcSize.value <= dstSize.value) THEN
				Load(code, srcSize);
				PCLIR.Emit03(code, PCLIR.move, src.adr, dst.adr, srcSize.adr)
			ELSE
				Load(code, dstSize);
				PCLIR.Emit03(code, PCLIR.move, src.adr, dst.adr, dstSize.adr);
				PCLIR.EmitLoadConst(code, zero.adr, PCLIR.Int8, FALSE, 0);
				PCLIR.EmitStoreRelative(code, -1, dst.adr, zero.adr)
			END
		ELSE
			Load(code, srcSize);  Load(code, dstSize);
			cc := srcSize;
			RelOp(code, PCS.gtr, cc, dstSize); 
			label := -1;  Jcc(code, label, cc);
				(*src <= dst *)
			PCLIR.Emit03(code, PCLIR.move, src.adr, dst.adr, srcSize.adr);
			exit := -1;  Jmp(code, exit);
			FixJmp(code, label);  PCLIR.Emit0C(code, PCLIR.label, 0);
				(* src > dst *)
			PCLIR.Emit03(code, PCLIR.move, src.adr, dst.adr, dstSize.adr);
			PCLIR.EmitLoadConst(code, zero.adr, PCLIR.Int8, FALSE, 0);
			PCLIR.EmitStoreRelative(code, -1, dst.adr, zero.adr);
			
			FixJmp(code, exit);  PCLIR.Emit0C(code, PCLIR.label, 0);
		END
	END
*)
END MoveString;

PROCEDURE GetHWReg*(code: Code;  VAR x: Item;  reg: SHORTINT);
BEGIN
	LoadAdr(code,x);
	PCLIR.EmitStoreRelative(code, 0, x.adr, PCLIR.HwReg-reg);
END GetHWReg;

PROCEDURE SetHWReg*(code: Code;  VAR x: Item;  reg: SHORTINT);
BEGIN
	Load(code, x);
	PCLIR.EmitStoreReg(code, PCLIR.HwReg-reg, x.adr);
END SetHWReg;

PROCEDURE GetMemory*(code: Code;  VAR adr: Item;  type: PCT.Struct);
BEGIN
	ASSERT(adr.type = PCT.Int32);
	Load(code, adr);
	adr.mode := RegRel; adr.offs := 0; adr.type := type;
	Load(code, adr);	(* projection could change the type and thus the move width! *)
END GetMemory;

PROCEDURE WriteHWPort*(code: Code;  VAR x, y: Item);	(** Write y to port x *)
BEGIN
	Load(code, x);
	Load(code, y);
	PCLIR.Emit02(code, PCLIR.out, x.adr, y.adr)
END WriteHWPort;

PROCEDURE ReadHWPort*(code: Code;  VAR x, y: Item);	(** Read y from port x *)
VAR  reg: PCLIR.Register; size: PCBT.Size;
BEGIN
	size := y.type.size(PCBT.Size);
	Load(code, x);
	PCLIR.EmitConv(code, PCLIR.in, reg, size.type, size.signed, x.adr);
	LoadAdr(code, y);
	PCLIR.EmitStoreRelative(code, 0, y.adr, reg)
END ReadHWPort;

(**-----------Boolean Expressions----------------*)

(* InitCC - Create condition code item *)

PROCEDURE InitCC(VAR a: Item; cc: LONGINT; r1, r2: PCLIR.Register);
BEGIN
	a.mode := CC;  a.adr := cc;
	a.value := r1; a.breg := r2;
	a.tlist := none;  a.flist := none;
	a.type := PCT.Bool
END InitCC;

(* LoadCC - load condition into a register *)

PROCEDURE LoadCC(code: Code; VAR a: Item);
VAR	t, f, end: LONGINT;
BEGIN
	ASSERT(a.mode = CC, 110);
	IF (a.tlist = none) & (a.flist = none) THEN	(*no jump links*)
		ASSERT(a.adr # 0);
		ASSERT(a.adr # ccAlways);
		PCLIR.Emit12Sized(code, SetCCTab[a.adr], a.adr, PCLIR.Int8, a.value, a.breg)
	ELSE
		IF a.adr # ccNone THEN
			PCLIR.Emit02C(code, InvCCTab[a.adr], a.value, a.breg, a.flist); a.flist := code.pc -1
		END;
		FixJmp(code, a.tlist);
		PCLIR.EmitLoadConst(code, t, PCLIR.Int8, FALSE, True);
		PCLIR.Emit01(code, PCLIR.kill, t);
		end := code.pc;  PCLIR.Emit0C(code, PCLIR.jmp, none);	(*jump to end*)
		FixJmp(code, a.flist);
		PCLIR.EmitLoadConst(code, f, PCLIR.Int8, FALSE, False);
		PCLIR.Emit01(code, PCLIR.kill, f);
		FixJmp(code, end);
		PCLIR.EmitPhi(code, a.adr, t, f)
	END;
	a.mode := Reg
END LoadCC;

(** CondOr - Prepare conditional OR *)

PROCEDURE CondOr*(code: Code; VAR a: Item);
VAR t: LONGINT; jcc: PCLIR.Opcode;
BEGIN
	IF a.mode = CC THEN
		jcc := CCTab[a.adr]
	ELSE
		ASSERT(a.type = PCT.Bool);
		Load(code, a);
		PCLIR.EmitLoadConst(code, t, PCLIR.Int8, FALSE, True);
		InitCC(a, ccEQ, a.adr, t); jcc := PCLIR.je
	END;
	IF a.adr # ccNone THEN
		PCLIR.Emit02C(code, jcc, a.value, a.breg, a.tlist); a.tlist := code.pc -1
	END;
	FixJmp(code, a.flist);
	ASSERT(a.flist = none, 220);
END CondOr;

(** CondOr - Conditional OR *)

PROCEDURE Or*(code: Code; VAR a, b: Item);
VAR t, tlist: LONGINT;
BEGIN
	ASSERT(a.mode = CC);
	ASSERT(a.flist = none, 200);
	tlist := a.tlist;
	IF b.mode # CC THEN
		Load(code, b);
		PCLIR.EmitLoadConst(code, t, PCLIR.Int8, FALSE, True);
		InitCC(a, ccEQ, b.adr, t)
	ELSE
		a := b;
	END;
	a.tlist := PCLIR.MergeList(code, tlist, a.tlist);
END Or;

(** CondAnd - Prepare Conditional AND *)

PROCEDURE CondAnd*(code: Code; VAR a: Item);
VAR t: LONGINT; jcc: PCLIR.Opcode;
BEGIN
	IF a.mode = CC THEN
		jcc := InvCCTab[a.adr]
	ELSE
		ASSERT(a.type = PCT.Bool);
		Load(code, a);
		PCLIR.EmitLoadConst(code, t, PCLIR.Int8, FALSE, True);
		InitCC(a, ccNE, a.adr, t); jcc := PCLIR.jne
	END;
	IF a.adr # ccNone THEN
		PCLIR.Emit02C(code, jcc, a.value, a.breg, a.flist); a.flist := code.pc -1
	END;
	FixJmp(code, a.tlist);
	ASSERT(a.tlist = none, 220);
END CondAnd;

(** And - Conditional AND *)

PROCEDURE And*(code: Code; VAR a, b: Item);
VAR t, flist: LONGINT;
BEGIN
	ASSERT(a.mode = CC);
	ASSERT(a.tlist = none, 200);
	flist := a.flist;
	IF b.mode # CC THEN
		Load(code, b);
		PCLIR.EmitLoadConst(code, t, PCLIR.Int8, FALSE, True);
		InitCC(a, ccEQ, b.adr, t)
	ELSE
		a := b
	END;
	a.flist := PCLIR.MergeList(code, flist, a.flist)
END And;

(**-----------Numeric Expressions----------------*)


PROCEDURE MOp*(code: Code;  f: LONGINT;  VAR a: Item);
VAR  reg: PCLIR.Register;  label: Label;  size: PCBT.Size;
BEGIN
	ASSERT(a.mode # Const, 1000);
	CASE f OF
	|  setfn:
			ASSERT(PCT.IsCardinalType(a.type), setfn*10);
			Load(code, a);
			GenConv(code, PCLIR.convs, a, PCLIR.Int32, FALSE);
			PCLIR.EmitLoadConst(code, reg, PCLIR.Int32, FALSE, 0);
			PCLIR.Emit12(code, PCLIR.bts, a.adr, reg, a.adr);
			a.type := PCT.Set
	|  absfn:
			Load(code, a);
			PCLIR.Emit11(code, PCLIR.abs, a.adr, a.adr)
	|  capfn:
			ASSERT(a.type = PCT.Char8);
			Load(code, a);
			PCLIR.EmitLoadConst(code, reg, PCLIR.Int8, FALSE, 5FH);
			PCLIR.Emit12(code, PCLIR.and, a.adr, a.adr, reg);
	|  oddfn:
			ASSERT(PCT.IsCardinalType(a.type), oddfn);
			size := a.type.size(PCBT.Size);
			Load(code, a);
			PCLIR.EmitLoadConst(code, reg, size.type, size.signed, 1H);
			PCLIR.Emit12(code, PCLIR.and, a.adr, a.adr, reg);
			PCLIR.EmitLoadConst(code, reg, size.type, size.signed, 1H);
			InitCC(a, ccEQ, a.adr, reg);
	| PCS.minus:
			Load(code, a);
			IF PCT.IsCardinalType(a.type) OR PCT.IsFloatType(a.type) THEN
				PCLIR.Emit11(code, PCLIR.neg, a.adr, a.adr)
			ELSIF a.type = PCT.Set THEN
				PCLIR.Emit11(code, PCLIR.not, a.adr, a.adr)
			ELSE
				HALT(99)
			END
	| PCS.not:
			ASSERT(a.type = PCT.Bool);
			IF a.mode = CC THEN
				a.adr := InvCC[a.adr];
				label := a.flist; a.flist := a.tlist; a.tlist := label
			ELSE
				Load(code, a);
				PCLIR.EmitLoadConst(code, reg, PCLIR.Int8, FALSE, False);
				InitCC(a, ccEQ, a.adr, reg)
			END
	END
END MOp;

PROCEDURE DOp*(code: Code;  f: LONGINT;  VAR a, b: Item);
VAR reg: PCLIR.Register;  op: PCLIR.Opcode;  exp: LONGINT;

	PROCEDURE PowerOf2(val: LONGINT;  VAR exp: LONGINT): BOOLEAN;
	BEGIN
		IF val <= 0 THEN  RETURN FALSE END;
		exp := 0;
		WHILE ~ODD(val) DO
			val := val DIV 2;
			INC(exp)
		END;
		RETURN val = 1
	END PowerOf2;
	
BEGIN
	IF (a.mode = Const) & (b.mode = Const) THEN	(*just in case*)
		CASE f OF
		| PCS.minus:  a.value := a.value - b.value
		| PCS.plus: a.value := a.value + b.value
		| PCS.times: a.value := a.value * b.value
		| PCS.div: a.value := a.value DIV b.value
		| PCS.mod: a.value := a.value MOD b.value
		END;
		RETURN
	END;
	CASE f OF
	|  setfn:
			ASSERT(PCT.IsCardinalType(a.type), setfn*10);
			ASSERT(PCT.IsCardinalType(b.type), setfn*10+1);
			IF a.mode = Const THEN
				MakeIntConst(a, SYSTEM.LSH(LONG(LONG(-1)), a.value), PCT.Set);
				Load(code, a)
			ELSE
				IF a.mode # Reg THEN  Load(code, a)  END;
				PCLIR.EmitLoadConst(code, reg, PCLIR.Int32, FALSE, -1);
				GenConv(code, PCLIR.copy, a, PCLIR.Int8, TRUE);
				PCLIR.Emit12(code, PCLIR.bsh, a.adr, reg, a.adr);	(* 11111111 -> 11111100 *)
				a.type := PCT.Set
			END;
			IF b.mode = Const THEN
				MakeIntConst(b, SYSTEM.LSH(LONG(LONG(-1)), b.value-31), PCT.Set);
				Load(code, b)
			ELSE
				IF b.mode # Reg THEN  Load(code, b)  END;
				GenConv(code, PCLIR.copy, b, PCLIR.Int8, TRUE);
				PCLIR.EmitLoadConst(code, reg, PCLIR.Int8, TRUE, 31);
				PCLIR.Emit12(code, PCLIR.sub, b.adr, b.adr, reg);
				PCLIR.EmitLoadConst(code, reg, PCLIR.Int32, FALSE, -1);
				PCLIR.Emit12(code, PCLIR.bsh, b.adr, reg, b.adr);
				b.type := PCT.Set
			END;
			op := PCLIR.and
	|  ashfn:
			Convert(code, b, PCT.Int8, FALSE);
			op := PCLIR.ash
	|  lshfn:
			Convert(code, b, PCT.Int8, FALSE);
			op := PCLIR.bsh
	|  rotfn:
			Convert(code, b, PCT.Int8, FALSE);
			op := PCLIR.rot
	|  PCS.minus:
			IF a.type = PCT.Set THEN
				Load(code, b);
				PCLIR.Emit11(code, PCLIR.not, b.adr, b.adr);
				op := PCLIR.and
			ELSE
				op := PCLIR.sub
			END
	|  PCS.plus:
			IF a.type = PCT.Set THEN
				op := PCLIR.or
			ELSE
				op := PCLIR.add
			END
	|  PCS.times:
			IF a.type = PCT.Set THEN
				op := PCLIR.and
			ELSIF (b.mode = Const) & PowerOf2(b.value, exp) THEN
				IF exp = 0 THEN  RETURN  END;	(* x * 1 *)
				MakeIntConst(b, exp, PCT.Char8);
				op := PCLIR.ash
			ELSIF (a.mode = Const) & PowerOf2(a.value, exp) THEN
				a := b;	(*swap*)
				IF exp = 0 THEN  RETURN  END;
				MakeIntConst(b, exp, PCT.Char8);
				op := PCLIR.ash
			ELSE
				op := PCLIR.mul
			END
	|  PCS.div:
			IF (b.mode = Const) & PowerOf2(b.value, exp) THEN
				IF exp = 0 THEN  RETURN  END;	(* x DIV 1 *)
				MakeIntConst(b, -exp, PCT.Char8);
				op := PCLIR.ash
			ELSE
				op := PCLIR.div
			END
	|  PCS.slash:
			IF a.type = PCT.Set THEN
				op := PCLIR.xor
			ELSE
				op := PCLIR.div
			END
	|  PCS.mod:
			IF (b.mode = Const) & PowerOf2(b.value, exp) THEN
				MakeIntConst(b, b.value-1, a.type);
				op := PCLIR.and
			ELSE
				op := PCLIR.mod
			END
	END;
	IF a.mode # Reg THEN  Load(code, a)  END;
	IF b.mode # Reg THEN  Load(code, b)  END;
	PCLIR.Emit12(code, op, a.adr, a.adr, b.adr)
END DOp;

PROCEDURE StringCmp(code: Code; cc: SHORTINT;  VAR cond: Item;  a, b: Item);
VAR  aval, bval, abase, bbase, abase2, bbase2, zero, one, loop, pc: LONGINT;  cctrue, ccfalse: SHORTINT;
BEGIN
	ASSERT(a.mode # Reg, 200);
	ASSERT(b.mode # Reg, 201);
	ASSERT(cc IN {ccEQ, ccNE, ccB, ccBE, ccA, ccAE}, 202);
	cctrue := 0;  ccfalse := 0;
	CASE  cc  OF
	|  ccB, ccBE:
			cctrue := ccB; ccfalse := ccA
	|  ccA, ccAE:
			cctrue := ccA; ccfalse := ccB
	|  ccEQ:
			ccfalse := ccNE
	|  ccNE:
			cctrue := ccNE
	END;
	
	LoadAdr(code, a);  abase := a.adr;
	LoadAdr(code, b);  bbase := b.adr;
	InitCC(cond, ccNone, none, none);
	
	PCLIR.Emit01(code, PCLIR.kill, abase);
	PCLIR.Emit01(code, PCLIR.kill, bbase);
	DefLabel(code, loop);
	PCLIR.EmitPhi(code, abase, abase, none);
	PCLIR.EmitPhi(code, bbase, bbase, none);
	PCLIR.EmitLoadRelative(code, PCLIR.Int8, FALSE, aval, 0, abase);
	PCLIR.EmitLoadRelative(code, PCLIR.Int8, FALSE, bval, 0, bbase);
	
	IF cctrue # 0 THEN
		cond.tlist := code.pc;
		PCLIR.Emit02C(code, CCTab[cctrue], aval, bval, none);	(* Jcc  true *)
	END;
	IF ccfalse # 0 THEN
		cond.flist := code.pc;
		PCLIR.Emit02C(code, CCTab[ccfalse], aval, bval, none);	(* Jcc  false *)
	END;
	PCLIR.EmitLoadConst(code, zero, PCLIR.Int8, FALSE, 0);
	pc := code.pc;
	IF cc IN {ccEQ, ccAE, ccBE} THEN
		PCLIR.Emit02C(code, CCTab[ccEQ], aval, zero, cond.tlist);	(* JE  true *)
		cond.tlist := pc
	ELSE
		PCLIR.Emit02C(code, CCTab[ccEQ], aval, zero, cond.flist);	(*JE false*)
		cond.flist := pc
	END;
	PCLIR.EmitLoadConst(code, one, PCLIR.Address, FALSE, 1);
	PCLIR.Emit12(code, PCLIR.add, abase2, abase, one);
	PCLIR.EmitLoadConst(code, one, PCLIR.Address, FALSE, 1);
	PCLIR.Emit12(code, PCLIR.add, bbase2, bbase, one);
	PCLIR.PatchPhi(code, abase, abase2);
	PCLIR.PatchPhi(code, bbase, bbase2);
	PCLIR.Emit01(code, PCLIR.kill, abase2);
	PCLIR.Emit01(code, PCLIR.kill, bbase2);
	PCLIR.Emit0C(code, PCLIR.jmp, loop);
END StringCmp;

PROCEDURE RelOp*(code: Code; operand: LONGINT; VAR a, b: Item);
VAR  cc: SHORTINT;  string: BOOLEAN;  list: Label;
BEGIN
	IF operand = bitfn THEN
		Convert(code, a, PCT.Int32, FALSE);
		Load(code, a);
		a.mode := RegRel;
		a.offs := 0;
		Load(code, a);
		Convert(code, b, PCT.Int32, TRUE);
		Load(code, b);
		InitCC(a, ccF, a.adr, b.adr)
	ELSIF operand = PCS.in THEN
		ASSERT(a.type = PCT.Int32);
		Load(code, a); Load(code, b);
		InitCC(a, ccF, b.adr, a.adr)
	ELSIF (a.type IS PCT.Delegate) & (b.type IS PCT.Delegate) & ~(PCT.StaticMethodsOnly IN a.type.flags) & ~(PCT.StaticMethodsOnly IN b.type.flags) THEN
		Load(code, a);
		Load(code, b);
		PCLIR.Emit02C(code, PCLIR.jne, a.adr, b.adr, none); list := code.pc - 1;
		IF operand = PCS.eql THEN
			InitCC(a, ccEQ, a.breg, b.breg); a.flist := list
		ELSE
			ASSERT(operand = PCS.neq);
			InitCC(a, ccNE, a.breg, b.breg); a.tlist := list
		END
	ELSE
		string := IsString(a.type) & IsString(b.type);
		IF PCT.IsCharType(a.type) OR string THEN	(*unsigned compare*)
			CASE operand OF
			| PCS.eql:  cc := ccEQ
			| PCS.neq:  cc := ccNE
			| PCS.lss:  cc := ccB
			| PCS.leq:  cc := ccBE
			| PCS.gtr:  cc := ccA
			| PCS.geq:  cc := ccAE
			ELSE HALT(99)
			END
		ELSE
			CASE operand OF
			| PCS.eql:  cc := ccEQ
			| PCS.neq:  cc := ccNE
			| PCS.lss:  cc := ccLT
			| PCS.leq:  cc := ccLE
			| PCS.gtr:  cc := ccGT
			| PCS.geq:  cc := ccGE
			ELSE HALT(99)
			END
		END;
		IF string THEN
			StringCmp(code, cc, a, a, b)
		ELSE
			Load(code, a); Load(code, b);
			InitCC(a, cc, a.adr, b.adr)
		END
	END;
	a.type := PCT.Bool
END RelOp;

(** Convert x to type. typeOnly: change type but not value (SYSTEM.VAL) *)

PROCEDURE Convert*(code: Code;  VAR x: Item;  type: PCT.Struct;  typeOnly: BOOLEAN);
VAR  size: PCBT.Size;
BEGIN
	size := type.size(PCBT.Size);
	IF x.type = type THEN
		(*nothing to do*)
	ELSIF x.mode = Const THEN
		(*nothing to do*)
	ELSIF typeOnly THEN
		IF x.mode = Reg THEN
			GenConv(code, PCLIR.copy, x, size.type, size.signed)
		END;
		IF type IS PCT.Delegate THEN
			IF x.mode # Reg THEN Load(code, x) END;	(*prepare value for assign*); 
			IF ~(PCT.StaticMethodsOnly IN type.flags) THEN PCLIR.EmitLoadConst(code, x.breg, PCLIR.Address, FALSE, Nil) END
		END
	ELSIF PCT.IsCardinalType(x.type) OR PCT.IsFloatType(x.type) THEN
		IF x.mode # Reg THEN  Load(code, x)  END;
		GenConv(code, PCLIR.convs, x, size.type, size.signed)
	ELSIF PCM.LocalUnicodeSupport & PCT.IsCharType(x.type) THEN
		IF type = PCT.Byte THEN
			(*skip*)
		ELSIF PCT.IsCardinalType(type) OR PCT.IsCharType(type) THEN
			IF x.mode # Reg THEN  Load(code, x)  END;
			GenConv(code, PCLIR.convu, x, size.type, size.signed)
		ELSE
			PCDebug.ToDo(PCDebug.NotImplemented)
		END
	ELSIF ~PCM.LocalUnicodeSupport & (x.type = PCT.Char8) THEN
		IF PCT.IsCardinalType(type) THEN
			IF GetStaticSize(type) > 1 THEN
				IF x.mode # Reg THEN  Load(code, x)  END;
				GenConv(code, PCLIR.convu, x, size.type, size.signed)
			END
		ELSIF type = PCT.Byte THEN
			(*skip*)
		ELSE
			PCDebug.ToDo(PCDebug.NotImplemented)
		END
	ELSIF (x.type = PCT.Byte) THEN
		IF type = PCT.Char8 THEN
			(*skip*)
		ELSIF PCT.IsCardinalType(type) THEN
			IF x.mode # Reg THEN  Load(code, x)  END;
			GenConv(code, PCLIR.convu, x, size.type, size.signed)
		ELSE
			PCDebug.ToDo(PCDebug.NotImplemented)
		END
	ELSIF PCT.IsPointer(x.type)  THEN
		(*nothing to do. PCB checked that the convertion is allowed*)
	ELSE
(*
PCM.LogWLn; PCM.LogWStr("PCC.Convert: ConvFailed "); PCM.LogWStr(x.type.owner.name);
PCM.LogWStr(" -> "); PCM.LogWStr(type.owner.name);
*)
		PCLIR.Emit00(code, PCLIR.nop);
		PCDebug.ToDo(PCDebug.NotImplemented);
	END;
	x.type := type
END Convert;

(**-----------Designators----------------*)
PROCEDURE Deref*(code: Code; VAR x: Item);
VAR ptr: PCT.Pointer; arr: PCT.Array;
BEGIN
	ptr := x.type(PCT.Pointer);
	NilCheck(code, x);
	IF ptr.baseR # NIL (* IS Record *) THEN
		Load(code, x);
		x.mode := RegRel;  x.offs := 0;  x.type := ptr.baseR;
	ELSIF ptr.baseA # NIL (* IS Array *) THEN
			arr := ptr.baseA;
			Load(code, x);
			x.mode := RegRel;
			x.breg := x.adr;
			IF arr.mode = PCT.open THEN
				x.boffs := ArrayFirstElem + arr.opendim * 4;	(*array dimensions*)
			ELSE
				ASSERT(arr.mode = PCT.static);
				x.boffs := ArrayFirstElem + 4;
			END;
			x.offs := x.boffs+4;  INC(x.offs, (-x.offs) MOD 8);	(* x.offs MOD 8 = 0 *)
			x.type := arr;
	ELSE
		PCDebug.ToDo(PCDebug.NotImplemented);
	END;
	x.deref := TRUE
END Deref;

PROCEDURE Index*(code: Code; VAR x, index: Item);
VAR size: Item; type: PCT.Array; mode: SHORTINT;

	PROCEDURE IndexCheck(code: Code; VAR x, index: Item);
	VAR bound: Item;
	BEGIN
		type := x.type(PCT.Array); mode := type.mode;
		IF (mode = PCT.static) THEN
			IF index.mode = Const THEN RETURN END;	(*statically checked*)
			MakeIntConst(bound, type.len, PCT.Int32)
		ELSE
			ASSERT(mode = PCT.open);
			bound.mode := RegRel; bound.adr := x.breg; bound.offs := x.boffs; bound.type := PCT.Int32
		END;
		Load(code, index); Load(code, bound);
		PCLIR.Emit02C(code, PCLIR.tae, index.adr, bound.adr, PCM.IndexCheckTrap)
	END IndexCheck;

BEGIN
	ASSERT(x.type IS PCT.Array, 200);
	ASSERT(index.type = PCT.Int32, 201);
	type := x.type(PCT.Array); mode := type.mode;
	IF mode IN {PCT.static, PCT.open} THEN
		ASSERT(x.mode IN {Abs, Var, Ref, RegRel}, 202);
		
		LoadAdr(code, x);
		IF PCM.ArrayCheck IN PCM.codeOptions THEN IndexCheck(code, x, index) END;
		
		GetArrayBaseSize(code, size, x);
		DOp(code, PCS.times, index, size);
		IF index.mode # Reg THEN  Load(code, index)  END;
		GenConv(code, PCLIR.convu, index, PCLIR.Address, FALSE);	(*assume index is > 0 *)
		PCLIR.Emit12(code, PCLIR.add, x.adr, x.adr, index.adr);
		x.mode := RegRel; x.offs := 0; x.type := type.base;
		DEC(x.boffs, 4);
	ELSE
		PCDebug.ToDo(PCDebug.NotImplemented);
	END;
	x.deref := FALSE;
	ASSERT(x.mode = RegRel, 220);
END Index;

PROCEDURE Field*(code: Code;  VAR x: Item;  fld: PCT.Field);
BEGIN
	LoadAdr(code, x);
	x.mode := RegRel;  x.offs := fld.adr(PCBT.Variable).offset;  x.type := fld.type;
	x.deref := FALSE
END Field;
(*
PROCEDURE Method*(code: Code;  VAR x: Item;  self: Item;  mth: PCT.Method;  supercall: BOOLEAN);
VAR  mthAdr: PCBT.Method; t: PCLIR.Register;
BEGIN
	IF PCT.IsPointer(self.type) THEN
		Load(code, self); t := self.adr
	END;
	GetTD(code, self, x, supercall);
	Load(code, x);
	mthAdr := mth.adr(PCBT.Method);
	x.mode := Reg;
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, x.adr, MethodTable - 4*mthAdr.mthNo, x.adr);
	x.breg := t;
	x.type := MethodType
END Method;
*)
PROCEDURE Method*(code: Code; VAR x: Item; self: Item; mth: PCT.Method; supercall: BOOLEAN);
VAR  mthAdr: PCBT.Method; t: PCLIR.Register; off: LONGINT;
BEGIN
	mthAdr := mth.adr(PCBT.Method);
	IF PCT.IsPointer(self.type) THEN
		Load(code, self); t := self.adr
	END;
	IF PCT.interface IN mth.boundTo.mode THEN
		InterfaceLookup(code, self, mth.boundTo, x);
		off := IntfMethodTable + 4*mthAdr.mthNo
	ELSE
		GetTD(code, self, x, supercall);
		off := MethodTable - 4*mthAdr.mthNo
	END;
	Load(code, x);
	x.mode := Reg;
	PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, x.adr, off, x.adr);
	x.breg := t;
	x.type := MethodType
END Method;

(**-----------System Calls----------------*)

PROCEDURE InterfaceLookup(code: Code; VAR self: Item; intf: PCT.Record; VAR vtable: Item);
	VAR td: Item; reg: PCLIR.Register;
BEGIN
	GetTD(code, self, td, FALSE);
	Load(code, td);
	PCLIR.Emit01(code, PCLIR.push, td.adr);	(* push class descriptor *)
	MakeTD(td, intf);
	Load(code, td);
	PCLIR.Emit01(code, PCLIR.push, td.adr);	(* push interface descriptor *)
	PCLIR.Emit0C(code, PCLIR.syscall, PCBT.interfacelookup);
	vtable.mode := Reg; vtable.type := PCT.Ptr; vtable.proc := NIL;
	PCLIR.Emit10(code, PCLIR.result, vtable.adr, PCLIR.Address(*PCT.Ptr.size(PCBT.Size).size.type*));
END InterfaceLookup;

PROCEDURE SysNewRec*(code: Code;  VAR x: Item);	(* NewRec (VAR p: PTR; td: PTR) *)
VAR  ptr: PCT.Pointer;  type: PCT.Record;  td: Item;
BEGIN
	ASSERT(x.type IS PCT.Pointer, 200);
	ptr := x.type(PCT.Pointer);
	ASSERT(ptr.baseR # NIL  (* IS PCT.Record *), 201);
	type := ptr.baseR;
	LoadAdr(code, x);  PCLIR.Emit01(code, PCLIR.push, x.adr);	(*1st par: VAR p: PRT *)
	MakeTD(td, type);
	Load(code, td);  PCLIR.Emit01(code, PCLIR.push, td.adr);	(* 2nd par: td: PTR *)
	PCLIR.Emit0C(code, PCLIR.syscall, PCBT.newrec);
END SysNewRec;

PROCEDURE SysNewBlock*(code: Code;  x, size: Item);
BEGIN
	Convert(code, size, PCT.Int32, FALSE);
	LoadAdr(code, x);  PCLIR.Emit01(code, PCLIR.push, x.adr);
	Load(code, size);  PCLIR.Emit01(code, PCLIR.push, size.adr);
	PCLIR.Emit0C(code, PCLIR.syscall, PCBT.newsys)
END SysNewBlock;

PROCEDURE SysNewArray*(code: Code;  VAR ptr: Item;  btyp: PCT.Struct;  nofElem: Item;  nofDims: LONGINT);
VAR size, offset, td: Item;  reg: PCLIR.Register; label: Label;
BEGIN
	Convert(code, nofElem, PCT.Int32, FALSE);
	Load(code, nofElem);
	
	(* check array length here, because the allocated size may be > 0 even if the length is < 0, e.g. with SysBlocks *)
	PCLIR.EmitLoadConst(code, reg, PCLIR.Int32, TRUE, -1);
	PCLIR.Emit02C(code, PCLIR.jgt, nofElem.adr, reg, none);
	label := code.pc-1;
	PCLIR.Emit0C(code, PCLIR.trap, PCM.ArraySizeTrap);
	PCLIR.FixList(code, label, code.pc);
	PCLIR.Emit0C(code, PCLIR.label, 0);
	
	IF ~btyp.size(PCBT.Size).containPtrs THEN
		MakeIntConst(size, GetStaticSize(btyp), PCT.Int32);
		DOp(code, PCS.times, size, nofElem);
		MakeIntConst(offset, ArrayDimTable+4+8*(nofDims DIV 2), PCT.Int32);
		DOp(code, PCS.plus, size, offset);
		SysNewBlock(code, ptr, size);
	ELSE
		LoadAdr(code, ptr); PCLIR.Emit01(code, PCLIR.push, ptr.adr);
		IF btyp IS PCT.Record THEN
			MakeTD(td, btyp(PCT.Record))
		ELSIF btyp IS PCT.Delegate THEN
			MakeTD(td, delegate);
		ELSE
			MakeTD(td, hdptr);
(*
			ASSERT(PCT.IsPointer(btyp));
			td.mode := Const; td.value := Nil; td.type := PCT.NilType
*)
		END;
		Load(code, td); PCLIR.Emit01(code, PCLIR.push, td.adr);
		Load(code, nofElem);  PCLIR.Emit01(code, PCLIR.push, nofElem.adr);
		PCLIR.EmitLoadConst(code, reg, PCLIR.Int32, TRUE, nofDims);
		PCLIR.Emit01(code, PCLIR.push, reg);
		PCLIR.Emit0C(code, PCLIR.syscall, PCBT.newarr)
	END;
END SysNewArray;

PROCEDURE SetArrayDim*(code: Code;  VAR ptr: Item;  nofDims, dim: LONGINT);
VAR  offs: LONGINT;  size: PCLIR.Register;
BEGIN
	IF ptr.mode # Reg THEN  Load(code, ptr)  END;
	offs := ArrayDimTable+4*(nofDims-1-dim);
	PCLIR.Emit10(code, PCLIR.pop, size, PCLIR.Int32);
	PCLIR.EmitStoreRelative(code, offs, ptr.adr, size)
END SetArrayDim;

PROCEDURE SysLock*(code: Code;  self: Item;  lock: BOOLEAN);
VAR const: Item;
BEGIN
	IF self.type IS PCT.Record THEN
		LoadAdr(code, self)
	ELSE
		Load(code, self)
	END;
	PCLIR.Emit01(code, PCLIR.push, self.adr);
	MakeIntConst(const, True, PCT.Int32);
	Load(code, const);
	PCLIR.Emit01(code, PCLIR.push, const.adr);
	IF lock THEN
		PCLIR.Emit0C(code, PCLIR.syscall, PCBT.lock)
	ELSE
		PCLIR.Emit0C(code, PCLIR.syscall, PCBT.unlock)
	END
END SysLock;

PROCEDURE SysStart*(code: Code;  body: PCT.Method;  self: Item);
VAR  mth: Item; rec: PCT.Record;  val: LONGINT;  reg, m: PCLIR.Register;
BEGIN
(* Start( bodyAddr: LONGINT;  prio, type: SHORTINT;  self: PTR );
	type: safe => 1
*)
	rec := body.boundTo;
	MakeTD(mth, rec);  Load(code, mth);
	
	mth.mode := RegRel; mth.type := PCT.Ptr(*body.type*);
	mth.offs := MethodTable - 4 * body.adr(PCBT.Method).mthNo;
	Load(code, mth);
	IF PCT.active IN rec.mode THEN
		PCLIR.Emit01(code, PCLIR.push, mth.adr);
		PCLIR.EmitLoadConst(code, reg, PCLIR.Int8, TRUE, rec.prio);
		PCLIR.Emit01(code, PCLIR.push, reg);
		val := 0;
		IF  PCT.safe IN rec.mode THEN  INC(val, 1)  END;
		PCLIR.EmitLoadConst(code, reg, PCLIR.Int8, FALSE, val);
		PCLIR.Emit01(code, PCLIR.push, reg);
		
		ASSERT(self.type IS PCT.Pointer);
		Load(code, self);
		PCLIR.Emit01(code, PCLIR.push, self.adr);
		PCLIR.Emit0C(code, PCLIR.syscall, PCBT.start)
	ELSE
(*
		PCM.LogWLn; PCM.LogWStr("PCC.SysStart: non-active body!");
		PCM.LogWStr(body.name);
		IF rec.owner # NIL THEN PCM.LogWStr(rec.owner.name)
		ELSIF rec.ptr.owner # NIL THEN PCM.LogWStr(rec.ptr.owner.name)
		END;
*)
		Load(code, self);
		PCLIR.EmitLoadRelative(code, PCLIR.Address, FALSE, reg, -4, self.adr);	(*td*)
		PCLIR.Emit01(code, PCLIR.push, reg);
		PCLIR.Emit01(code, PCLIR.push, self.adr);
		PCLIR.Emit01(code, PCLIR.callreg, mth.adr)
	END;
END SysStart;

(**-----------Statements----------------*)

PROCEDURE NewInstr*(code: Code; pos: LONGINT);
BEGIN
	PCLIR.Emit0C(code, PCLIR.label, pos)
END NewInstr;

PROCEDURE Assign*(code: Code; VAR dest, source: Item);
VAR  mode, size: LONGINT;
BEGIN
	IF (dest.type IS PCT.Basic) OR PCT.IsPointer(dest.type) THEN
		IF Statistics THEN INC(AAssBasic) END;
		IF (source.type = PCT.Float32) & (source.mode # Reg) THEN	(*optimize move*)
			dest.type := PCT.Int32; source.type := PCT.Int32
		END;
		IF source.mode = CC THEN  LoadCC(code, source)
		ELSIF source.mode # Reg THEN  Load(code, source)
		END;
		LoadAdr(code, dest);
		PCLIR.EmitStoreRelative(code, 0, dest.adr, source.adr);
	ELSIF dest.type IS PCT.Record THEN
		IF Statistics THEN INC(AAssRec) END;
		PCBT.AllocateTD(dest.type.size(PCBT.RecSize));
		size := GetStaticSize(dest.type);
		CopyBlock(code, dest, source, size)
	ELSIF dest.type IS PCT.Array THEN
		IF Statistics THEN INC(AAssArray) END;
		IF source.type = PCT.String THEN
			CopyBlock(code, dest, source, source.value)
		ELSIF source.type = dest.type THEN
			ASSERT(dest.type(PCT.Array).mode = PCT.static);
			size := GetStaticSize(dest.type);
			CopyBlock(code, dest, source, size);
		ELSE
			PCDebug.ToDo(PCDebug.NotImplemented)
		END;
	ELSIF dest.type IS PCT.Delegate THEN
		IF Statistics THEN INC(AAssProc) END;
		mode := source.mode;
		Load(code, source);
		LoadAdr(code, dest);
		PCLIR.EmitStoreRelative(code, 0, dest.adr, source.adr);
		IF ~(PCT.StaticMethodsOnly IN dest.type.flags) THEN
			PCLIR.EmitStoreRelative(code, 4, dest.adr, GetDelegateSelfReg(code, source, mode))
		END
	ELSE
		PCDebug.ToDo(PCDebug.NotImplemented)
	END
END Assign;

PROCEDURE GenTrap*(code: Code; nr: LONGINT);
BEGIN PCLIR.Emit0C(code, PCLIR.trap, nr)
END GenTrap;

PROCEDURE Return*(code: Code;  x: Item;  proc: PCT.Proc);
VAR  parSize, mode: LONGINT;  size, dst: Item;  type: PCT.Struct;
BEGIN
	type := proc.type;
	mode := x.mode;
	IF (type IS PCT.Basic) OR PCT.IsPointer(type) THEN
		IF Statistics THEN INC(ARetBasic) END;
		Load(code, x);
		PCLIR.Emit01(code, PCLIR.ret, x.adr);
	ELSIF type IS PCT.Record THEN
		IF Statistics THEN INC(ARetRec) END;
		parSize := proc.adr(PCBT.Procedure).parsize;
		size.mode := Var; size.offs := parSize+4; size.level := 0; size.type := PCT.Int32;
		dst.mode := Var; dst.offs := parSize; dst.level := 0; dst.type := PCT.Int32;
		LoadAdr(code, x); x.type := PCT.Int32;
		MoveBlock(code, dst, x, size);
	ELSIF type IS PCT.Array THEN
		IF type(PCT.Array).mode = PCT.open THEN			
			IF Statistics THEN INC(ARetOpenArray) END;
			IF mode = Proc THEN
				ReturnProc(code, x, proc);
			ELSE
				ReturnArray(code, x, proc);
			END;			
		ELSE
			IF Statistics THEN INC(ARetStaticArray) END;
			parSize := proc.adr(PCBT.Procedure).parsize;
			MakeIntConst(size, GetStaticSize(proc.type), PCT.Int32);
			dst.mode := Var; dst.offs := parSize; dst.level := 0; dst.type := PCT.Int32;
			LoadAdr(code, x); x.type := PCT.Int32;
			MoveBlock(code, dst, x, size);
		END
	ELSE
		IF Statistics THEN INC(ARetElse) END;
		mode := x.mode;
		Load(code, x);
		PCLIR.Emit01(code, PCLIR.ret, x.adr);
		IF (type IS PCT.Delegate) & ~(PCT.StaticMethodsOnly IN type.flags) THEN
			PCLIR.Emit01(code, PCLIR.ret2, GetDelegateSelfReg(code, x, mode))
		END
	END
END Return;

PROCEDURE SYScopy*(code: Code;  x, y: Item;  get: BOOLEAN);
BEGIN
	IF x.mode # Reg THEN
		x.type := PCT.Ptr;
		Load(code, x)
	ELSE
		GenConv(code, PCLIR.convu, x, PCLIR.Address, FALSE)
	END;
	x.mode := RegRel;  x.offs := 0;  x.type := y.type;
	IF get THEN
		Assign(code, y, x)
	ELSE
		Assign(code, x, y)
	END
END SYScopy;

PROCEDURE SYSaddress*(code: Code;  VAR x: Item);
BEGIN	LoadAdr(code, x);  x.type := PCT.Int32
END SYSaddress;

PROCEDURE Inline*(code: Code;  VAR x: PCM.Attribute);
BEGIN
	PCLIR.EmitInline(code, x);
END Inline;

(**-----------Passivate----------------*)
(*
AWAIT (cond);
	....
	jmp afterAwait
passivate(StaticLink: LONGINT):
	enter (passivate calling convention: set SL to EBP, avoid scope switch)
	compute cond
	return cond
afterAwait:
	push EBP
	call passivate
	result R
	cmp R, TRUE
	jeq skip
	syscall passivate
skip:
	....
*)

PROCEDURE AwaitEnter*(code: Code;  VAR adr: PCM.Attribute);
VAR padr: PCBT.Procedure;
BEGIN
	NEW(padr, PCBT.context, FALSE);
	PCLIR.EmitEnter(code, PCBT.OberonPassivateCC, padr);
	adr := padr;
END AwaitEnter;

PROCEDURE AwaitExit*(code: Code;  cond: Item);
BEGIN
	Load(code, cond);
	PCLIR.Emit01(code, PCLIR.ret, cond.adr);
	PCLIR.EmitExit(code, PCBT.OberonPassivateCC, 4)
END AwaitExit;

PROCEDURE Await*(code: Code;  self: Item;  adr: PCM.Attribute);
	(* SysAwait (cond, slink, obj, flags) *)
VAR  procAddr: PCBT.Procedure;  res, true: Item;  reg: PCLIR.Register;  label: Label;
BEGIN
	procAddr := adr(PCBT.Procedure);
	PCLIR.Emit01(code, PCLIR.push, PCLIR.FP);	(*static link*)
	PCLIR.EmitCall(code, procAddr);
	Result(code, res, PCT.Bool);
	MakeIntConst(true, True, PCT.Bool);
	RelOp(code, PCS.eql, res, true);
	label := none;
	Jcc(code, label, res);
		(*syscall*)
	PCLIR.EmitLoadAddr(code, reg, 0, procAddr);
	PCLIR.Emit01(code, PCLIR.push, reg);
	PCLIR.Emit01(code, PCLIR.push, PCLIR.FP);
	IF PCT.IsPointer(self.type) THEN
		Load(code, self)
	ELSE
		LoadAdr(code, self)
	END;
	PCLIR.Emit01(code, PCLIR.push, self.adr);
	PCLIR.EmitLoadConst(code, reg, PCLIR.Int32, FALSE, False);
	PCLIR.Emit01(code, PCLIR.push, reg);
	PCLIR.Emit0C(code, PCLIR.syscall, PCBT.passivate);
	FixJmp(code, label);
END Await;

(**-----------Control Flow----------------*)

(** PushSL - push the static link (SL), for local procedures only *)

PROCEDURE PushSL*(code: Code;  deltaLevel: SHORTINT);
VAR  reg: LONGINT;
BEGIN
	ASSERT(deltaLevel >= -1);
	GetActivationFrame(code, deltaLevel+1, reg);
	PCLIR.Emit01(code, PCLIR.push, reg)
END PushSL;

(** SaveRegisters - save registers before a procedure call *)

PROCEDURE SaveRegisters*(code: Code);
BEGIN  PCLIR.Emit00(code, PCLIR.saveregs);
END SaveRegisters;

(** RestoreRegisters - restore registers after a procedure call *)

PROCEDURE RestoreRegisters*(code: Code);
BEGIN  PCLIR.Emit00(code, PCLIR.loadregs);
END RestoreRegisters;

PROCEDURE ParamArray(code: Code;  VAR ap: Item;  formaltype: PCT.Struct;  reference: BOOLEAN);
VAR  aptype: PCT.Struct;  res, res2: Item;  dim: LONGINT;  fptype: PCT.Array;
BEGIN
	fptype := formaltype(PCT.Array);  aptype := ap.type;
	dim := 0;
	IF  (fptype.mode = PCT.open) OR reference THEN	(* prepare "reference" *)
		LoadAdr(code, ap);
		reference := TRUE
	ELSE
		reference := FALSE;
	END;
	
	WHILE (fptype # NIL) & (fptype.mode = PCT.open) DO
		IF fptype.base = PCT.Byte THEN
			IF (aptype = PCT.String) THEN
				MakeIntConst(res, ap.value, PCT.Int32)
			ELSIF (aptype IS PCT.Array) THEN
				ArrayDim(code, res, ap, dim);
				MakeIntConst(res2, GetStaticSize(aptype(PCT.Array).base), PCT.Int32);
				DOp(code, PCS.times, res, res2)
			ELSE
				MakeIntConst(res, GetStaticSize(aptype), PCT.Int32);
			END
		ELSE
			IF aptype # PCT.String THEN
				aptype := aptype(PCT.Array).base
			ELSE
				ASSERT(fptype.base = PCT.Char8)
			END;
			ArrayDim(code, res, ap, dim);  INC(dim)
		END;
		Load(code, res);
		PCLIR.Emit01(code, PCLIR.push, res.adr);
		IF  fptype.base IS PCT.Array  THEN  fptype := fptype.base(PCT.Array)  ELSE  fptype := NIL  END
	END;
	
	IF reference THEN
		PCLIR.Emit01(code, PCLIR.push, ap.adr)
	ELSE
		dim := GetStaticSize(fptype);
		StackAllocate(code, dim, res);
		CopyBlock(code, res, ap, dim)
	END
END ParamArray;


(** Param -  Push actual parameter on the stack *)

PROCEDURE Param*(code: Code; VAR ap: Item;  formaltype: PCT.Struct;  reference: BOOLEAN);
VAR res: Item;  mode, size: LONGINT;  name: ARRAY 32 OF CHAR;
BEGIN
	IF (formaltype IS PCT.Basic) OR (formaltype IS PCT.Pointer) THEN
		IF Statistics THEN INC(AParBasic) END;
		IF (ap.type = PCT.Float32) & (ap.mode # Reg) THEN	(*optimize move*)
			ap.type := PCT.Int32
		END;
		IF reference THEN  LoadAdr(code, ap)  ELSE  Load(code, ap)  END;
		PCLIR.Emit01(code, PCLIR.push, ap.adr)
	ELSIF formaltype IS PCT.Record THEN
		IF Statistics THEN INC(AParRec) END;
		IF reference THEN
			GetTD(code, ap, res, FALSE);  Load(code, res);  PCLIR.Emit01(code, PCLIR.push, res.adr);
			LoadAdr(code, ap);  PCLIR.Emit01(code, PCLIR.push, ap.adr)
		ELSE
			size := GetStaticSize(formaltype);
			StackAllocate(code, size, res);  CopyBlock(code, res, ap, size)
		END
	ELSIF formaltype IS PCT.Array THEN
		IF Statistics THEN INC(AParArray) END;
		ParamArray(code, ap, formaltype, reference)
	ELSIF (formaltype IS PCT.Delegate) THEN
		IF Statistics THEN INC(AParProc) END;
		IF reference THEN
			LoadAdr(code, ap)
		ELSE
			mode := ap.mode;
			Load(code, ap);
			IF ~(PCT.StaticMethodsOnly IN formaltype.flags) THEN
				PCLIR.Emit01(code, PCLIR.push, GetDelegateSelfReg(code, ap, mode))
			END
		END;
		PCLIR.Emit01(code, PCLIR.push, ap.adr)
	ELSE
		PCDebug.GetTypeName(formaltype, name);
		PCM.LogWLn; PCM.LogWStr("PCC.Param, unimplemented ");
		PCM.LogWStr(name);
		PCDebug.ToDo(PCDebug.NotImplemented)
	END
END Param;

(** Call - Call procedure *)

PROCEDURE Call*(code: Code; VAR x: Item);
VAR zero: PCLIR.Register; l: Label;
BEGIN
	IF x.mode = Proc THEN
		PCLIR.EmitCall(code, x.proc)
	ELSIF x.type = MethodType THEN	(*method call: self already pushed*)
		ASSERT(x.mode = Reg, 500);
		PCLIR.Emit01(code, PCLIR.callreg, x.adr)
	ELSIF ~(PCT.StaticMethodsOnly IN x.type.flags) THEN
		Load(code, x);
		PCLIR.EmitLoadConst(code, zero, PCLIR.Address, FALSE, 0);
		l := code.pc;
		PCLIR.Emit02C(code, CCTab[ccEQ], x.breg, zero, none);	(*fwd jmp*)
		PCLIR.Emit01(code, PCLIR.push, x.breg);
		PCLIR.FixList(code, l, code.pc);
		PCLIR.Emit0C(code, PCLIR.label, 0);
		PCLIR.Emit01(code, PCLIR.callreg, x.adr)
	ELSE
		Load(code, x);
		PCLIR.Emit01(code, PCLIR.callreg, x.adr)
	END
END Call;

(** Result - Retrieve a result after a Call *)

PROCEDURE Result*(code: Code; VAR x: Item;  type: PCT.Struct);
VAR  size: PCBT.Size;
BEGIN
	IF (type IS PCT.Array) THEN
		x.mode := Proc; x.type := type
	ELSIF ~(type IS PCT.Record) THEN
		size := type.size(PCBT.Size);
		PCLIR.Emit10(code, PCLIR.result, x.adr, size.type);
		x.mode := Reg; x.type := type; x.proc := NIL;
		IF (type IS PCT.Delegate) & ~(PCT.StaticMethodsOnly IN type.flags) THEN
			PCLIR.Emit10(code, PCLIR.result2, x.breg, PCLIR.Address) 
		END
	END
END Result;

(** Define a label *)

PROCEDURE DefLabel*(code: Code; VAR pc: Label);
BEGIN  pc := code.pc; PCLIR.Emit0C(code, PCLIR.label, 0)
END DefLabel;

(** Jump to label. If label is none, then autodefine *)

PROCEDURE Jmp*(code: Code; VAR pc: Label);
BEGIN
	PCLIR.Emit0C(code, PCLIR.jmp, pc);
	pc := code.pc-1
END Jmp;

(** Conditional Jump to label *)

PROCEDURE Jcc*(code: Code; VAR pc: Label; VAR cond: Item);
VAR	reg, t: LONGINT;
BEGIN
	ASSERT(cond.type = PCT.Bool);
	IF cond.mode # CC  THEN
		IF cond.mode # Reg THEN  Load(code, cond)  END;
		reg := cond.adr;
		PCLIR.EmitLoadConst(code, t, PCLIR.Int8, FALSE, True);
		InitCC(cond, ccEQ, reg, t)
	END;
	ASSERT(cond.mode = CC);
	
	IF pc # none THEN	(*Back. Jmp*)
		PCLIR.FixList(code, cond.tlist, pc);
		IF cond.adr # ccNone THEN PCLIR.Emit02C(code, CCTab[cond.adr], cond.value, cond.breg, pc) END
	ELSIF cond.adr # ccNone THEN
		pc := code.pc;
		PCLIR.Emit02C(code, CCTab[cond.adr], cond.value, cond.breg, cond.tlist)
	ELSE
		pc := cond.tlist
	END;
	FixJmp(code, cond.flist)
END Jcc;

(** Fixup Forward jumps to label *)

PROCEDURE FixJmp*(code: Code; VAR pc: Label);
BEGIN  PCLIR.FixList(code, pc, code.pc); PCLIR.Emit0C(code, PCLIR.label, 0)
END FixJmp;

(** Case Instruction - jump on x *)

PROCEDURE CaseStat*(code: Code;  VAR case: Item;  x: Item);
BEGIN
	case.mode := Case;
	Convert(code, x, PCT.Int32, FALSE);
	Load(code, x);
	PCLIR.EmitCase(code, case.adr, x.adr);
END CaseStat;

PROCEDURE CaseLine*(code: Code;  case: Item;  low, high: LONGINT);
	VAR  i: LONGINT;
BEGIN
	ASSERT(case.mode = Case);
	FOR i := low TO high DO
		PCLIR.EmitCaseLine(code, case.adr, i)
	END
END CaseLine;

PROCEDURE CaseElse*(code: Code;  case: Item);
BEGIN
	ASSERT(case.mode = Case);
	PCLIR.EmitCaseElse(code, case.adr);
END CaseElse;

PROCEDURE InitInterface*(code: Code; rec, intf: PCT.Record);
	VAR x, td, mth, dst: Item; m: PCT.Proc; o: PCT.Symbol;
BEGIN
	ASSERT(intf.ptr # NIL);
	StackAllocate(code, 4, x); x.type := intf.ptr;
	SysNewRec(code, x);
	MakeStackItem(x, PCT.Ptr);
	Load(code, x); x.mode := RegRel; x.offs := 0;
	MakeTD(td, rec);
	Assign(code, x, td);
	
	m := intf.scope.firstProc;
	WHILE m # NIL DO
		o := PCT.FindSameSignature(rec.scope, m.name, m.scope.firstPar, TRUE);
		IF o # NIL THEN	(*checked in PCT*)
			mth := td; mth.mode := RegRel; mth.offs := MethodTable - 4*o.adr(PCBT.Method).mthNo;
			dst := x; dst.mode := RegRel; dst.offs := IntfMethodTable + 4*m.adr(PCBT.Method).mthNo;
			Assign(code, dst, mth)
		END;
		m := m.nextProc
	END;
	PCLIR.Emit0C(code, PCLIR.syscall, PCBT.registerinterface)
(*
	FreeStack(code, PCT.Ptr)
*)
END InitInterface;

(**-----------Module Admin----------------*)

PROCEDURE Init;
VAR size: PCBT.Size;
BEGIN
	NEW(size); size.size := 8; size.align := 4; size.containPtrs := TRUE; size.type := PCLIR.Address;
	NEW(MethodType); MethodType.size := size;
END Init;

(** Cleanup - call after each compilation to unlink global structures for garbage collection *)

PROCEDURE Cleanup*;
BEGIN
	delegate := NIL;
	hdptr := NIL;
	topscope := NIL;
END Cleanup;

BEGIN
	CCTab[ccAlways] := PCLIR.jmp; CCTab[ccNever] := PCLIR.nop;
	CCTab[ccEQ] := PCLIR.je; CCTab[ccNE] := PCLIR.jne;
	CCTab[ccLT] := PCLIR.jlt; CCTab[ccLE] := PCLIR.jle;
	CCTab[ccGT] := PCLIR.jgt; CCTab[ccGE] := PCLIR.jge;
	CCTab[ccB] := PCLIR.jb; CCTab[ccBE] := PCLIR.jbe;
	CCTab[ccA] := PCLIR.ja; CCTab[ccAE] := PCLIR.jae;
	CCTab[ccF] := PCLIR.jf; CCTab[ccNF] := PCLIR.jnf;
	
	InvCCTab[ccAlways] := PCLIR.nop; InvCCTab[ccNever] := PCLIR.jmp;
	InvCCTab[ccEQ] := PCLIR.jne; InvCCTab[ccNE] := PCLIR.je;
	InvCCTab[ccLT] := PCLIR.jge; InvCCTab[ccLE] := PCLIR.jgt;
	InvCCTab[ccGT] := PCLIR.jle; InvCCTab[ccGE] := PCLIR.jlt;
	InvCCTab[ccB] := PCLIR.jae; InvCCTab[ccBE] := PCLIR.ja;
	InvCCTab[ccA] := PCLIR.jbe; InvCCTab[ccAE] := PCLIR.jb;
	InvCCTab[ccF] := PCLIR.jnf; InvCCTab[ccNF] := PCLIR.jf;

	InvCC[ccAlways] := ccNever; InvCC[ccNever] := ccAlways;
	InvCC[ccEQ] := ccNE; InvCC[ccNE] := ccEQ;
	InvCC[ccLT] := ccGE; InvCC[ccLE] := ccGT;
	InvCC[ccGT] := ccLE; InvCC[ccGE] := ccLT;
(*
	InvCC[ccLT] := ccLE; InvCC[ccLE] := ccLT;
	InvCC[ccGT] := ccGE; InvCC[ccGE] := ccGT;
*)
	InvCC[ccB] := ccAE; InvCC[ccBE] := ccA;
	InvCC[ccA] := ccBE; InvCC[ccAE] := ccB;
	InvCC[ccF] := ccNF; InvCC[ccNF] := ccF;
	
	SetCCTab[ccAlways] := PCLIR.nop; SetCCTab[ccNever] := PCLIR.nop;
	SetCCTab[ccEQ] := PCLIR.sete; SetCCTab[ccNE] := PCLIR.setne;
	SetCCTab[ccLT] := PCLIR.setlt; SetCCTab[ccLE] := PCLIR.setle;
	SetCCTab[ccGT] := PCLIR.setgt; SetCCTab[ccGE] := PCLIR.setge;
	SetCCTab[ccB] := PCLIR.setb; SetCCTab[ccBE] := PCLIR.setbe;
	SetCCTab[ccA] := PCLIR.seta; SetCCTab[ccAE] := PCLIR.setae;
	SetCCTab[ccF] := PCLIR.setf; SetCCTab[ccNF] := PCLIR.setnf;
	
	Init;
	
	IF Trace THEN PCM.LogWLn; PCM.LogWStr("PCC.Trace on") END;
	IF Statistics THEN PCM.LogWLn; PCM.LogWStr("PCC.Statistics on") END
END PCC.

(*
	24.06.03	prk	Remove TDMask (no need to mask typedescriptors)
	06.04.03	prk	assigning an static method to a delegate failed (double load, original mode lost); set self to NIL by default
	25.02.03	prk	emit load memory in GetMemory (avoids that SYSTEM.VAL / project changes the size and thus the move)
	28.12.02	prk	touch stack every memory page when copying arrays longer than a memory page
	21.07.02	prk	ODD, reload const to avoid duplicate virtual register use (this seems to confuse the i386 optimizer)
	11.06.02	prk	Access to dimensions in multidimensional dynamic and open arrays corrected
	11.06.02	prk	SYSTEM.BIT implemented
	02.04.02	prk	Fix in LoadAdr (copy hw-register when load addr of 0[reg])
	18.03.02	prk	PCBT code cleanup and redesign
	05.02.02	prk	PCT.Find cleanup
	22.11.01	prk	improved flag handling
	02.11.01	prk	fixed return of a function call with non-primitive type
	01.11.01	prk	unlink untraced pointers explicitly
	16.08.01	prk	keep PCBT.Variable offset, ignore for imported vars
	10.08.01	prk	PCBT.Procedure: imported: BOOLEAN replaced by owner: Module
	23.07.01	be	CAP fix
	23.07.01	prk	PushRetDesc, assert removed (too strong)
	23.07.01	prk	new array with a SYSTEM.PTR must call NewArr instead of NewSys
	05.07.01	prk	optional explicit NIL checks
	14.06.01	prk	type descs for dynamic arrays of ptrs generated by the compiler
	06.06.01	prk	use string pool for object names
	28.05.01	prk	Bug in local dynamic array allocation fixed
	17.05.01	prk	Delegates
	14.05.01	prk	PCLIR.lea removed
	11.05.01	prk	correct handling of operation with hw-regs; PCLIR.loadsp instruction; PCC stack ops fixed
	11.05.01	prk	When freeing stack, use pop instead of add (up to three words)
	07.05.01	be	register sign information added in the back-end
	26.04.01	prk	PCLIR.lea partly removed
	25.04.01	prk	array allocation: if length < 0 then trap PCM.ArraySizeTrap
	20.04.01	prk	CAP fixed, HOTBuiltinCAP1.Mod HOTBuiltinCAP2.Mod passed now
	11.04.01	prk	Allow SYSTEM.VAL(static array, int const), used in Raster.Mod
	25.03.01	prk	limited HUGEINT implementation (as abstract type)
	25.03.01	prk	NewSysBlock, NewArray: force sizes to be LInt
	15.03.01	prk	delegates: return
	14.03.01	prk	improved delegates implementation
	13.03.01	prk	delegates fix (parameters)
	13.03.01	prk	Statistics	
	22.02.01	prk	delegates
*)