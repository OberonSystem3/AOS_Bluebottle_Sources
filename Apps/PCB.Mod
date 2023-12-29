(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE PCB; (** AUTHOR "prk"; PURPOSE "Parallel Compiler: semantic checker"; *)


IMPORT
		SYSTEM, AosOut,
		StringPool, PCDebug, PCM, PCS, PCT, PCC, PCLIR, PCBT;


CONST
	Trace = FALSE;
	TraceEmit = FALSE;
	
	Workaround = TRUE;	(* WITH type problem when the variable is a field *)
	
	(* The Tokens 
	ProgTools.Enum PCS
		times slash div mod
		and plus minus or 
		eql neq  lss leq gtr geq
		in is 
		not
		~
*)
	times = PCS.times;  slash = PCS.slash;  div = PCS.div;  mod = PCS.mod; 
	and = PCS.and;  plus = PCS.plus;  minus = PCS.minus;  or = PCS.or;  eql = PCS.eql;  neq = PCS.neq; 
	lss = PCS.lss;  leq = PCS.leq;  gtr = PCS.gtr;  geq = PCS.geq;  in = PCS.in;  is = PCS.is; 
	not = PCS.not; 

	(** Built-In Procedures IDs *)
(*
	- No Pars
	- 1 Par
	- 2 Par
	- Specials

	ProgTools.Enum 128 *
	
	stifn clifn
	
	sizefn adrfn typecodefn get8fn get16fn get32fn ordfn ord8fn ord16fn ord32fn chrfn chr8fn chr16fn chr32fn
	entierfn entierhfn longfn shortfn 
	maxfn minfn passivatefn shaltfn haltfn
	
	valfn lenfn decfn incfn assertfn
	copyfn exclfn inclfn portinfn portoutfn getregfn putregfn getfn putfn put8fn put16fn put32fn sysnewfn
	
	movefn newfn
	~

	stifn* = 128; clifn* = 129; sizefn* = 130; adrfn* = 131; typecodefn* = 132; get8fn* = 133; 
	get16fn* = 134; get32fn* = 135; ordfn* = 136; ord8fn* = 137; ord16fn* = 138; ord32fn* = 139; 
	chrfn* = 140; chr8fn* = 141; chr16fn* = 142; chr32fn* = 143; entierfn* = 144; entierhfn* = 145; 
	longfn* = 146; shortfn* = 147; maxfn* = 148; minfn* = 149; passivatefn* = 150; shaltfn* = 151; 
	haltfn* = 152; valfn* = 153; lenfn* = 154; bitfn* = 155; decfn* = 156; incfn* = 157; 
	assertfn* = 158; copyfn* = 159; exclfn* = 160; inclfn* = 161; portinfn* = 162; portoutfn* = 163; 
	getregfn* = 164; putregfn* = 165; getfn* = 166; putfn* = 167; put8fn* = 168; put16fn* = 169; 
	put32fn* = 170; sysnewfn* = 171; movefn* = 172; newfn* = 173;
	
*)
	stifn* = 128; clifn* = 129; sizefn* = 130; adrfn* = 131; typecodefn* = 132; 
	get8fn* = 133; get16fn* = 134; get32fn* = 135; ordfn* = 136; ord8fn* = 137; 
	ord16fn* = 138; ord32fn* = 139; chrfn* = 140; chr8fn* = 141; chr16fn* = 142; 
	chr32fn* = 143; entierfn* = 144; entierhfn* = 145; longfn* = 146; 
	shortfn* = 147; maxfn* = 148; minfn* = 149; passivatefn* = 150; shaltfn* = 151; 
	haltfn* = 152; valfn* = 153; lenfn* = 154; decfn* = 155; incfn* = 156; 
	assertfn* = 157; copyfn* = 158; exclfn* = 159; inclfn* = 160; portinfn* = 161; 
	portoutfn* = 162; getregfn* = 163; putregfn* = 164; getfn* = 165; 
	putfn* = 166; put8fn* = 167; put16fn* = 168; put32fn* = 169; sysnewfn* = 170; 
	movefn* = 171; newfn* = 172; 
	

	NoPosition = -1;
	
	
TYPE
	DynSizedArray = OBJECT(PCT.Array)
		VAR
			dlen: Expression;
	END DynSizedArray;

	StringBuf = ARRAY 256 OF CHAR;
	Operator = LONGINT;
	
	SProcInfo = POINTER TO RECORD	(* built-in procedure, additional info for PCT.Symbol.info *)
		nr: LONGINT
	END;

(** ---------- Expressions -------------- *)
	(* an expression represents every kind of value, simple or composed *)
	Expression* = OBJECT (PCT.Node)
		VAR	type-: PCT.Struct;  link: Expression; (*used by ExprList*)
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  pos: LONGINT;
		BEGIN
			pos := SELF.pos;
			HALT(99);	(*abstract*)
		END Emit;
		
		PROCEDURE & Init*(pos: LONGINT; type: PCT.Struct);
		BEGIN  SELF.type := type;  SELF.pos:=pos
		END Init;
	END Expression;
	
	Const* = OBJECT (Expression)
		VAR	con-: PCT.Const;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  pos: LONGINT;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aConst) END;
			IF  type = PCT.NilType THEN
				PCC.MakeIntConst(i, PCM.nilval, PCT.NilType)
			ELSE
				PCC.MakeConst(i, con, type)
			END;
			IF TraceEmit THEN DebugLeave(aConst) END
		END Emit;
		
		PROCEDURE & InitC*(pos: LONGINT; con: PCT.Const);
		BEGIN
			ASSERT(con # NIL);
			Init(pos, con.type); SELF.con := con
		END InitC;
	END Const;

	DOp* = OBJECT (Expression)
		VAR	op: Operator;  lopd, ropd: Expression;
		
		PROCEDURE Emit*(code: PCC.Code; VAR l: PCC.Item);
		VAR	r: PCC.Item;  pos, op: LONGINT;  t1, t2: StringBuf;
		BEGIN
			pos := SELF.pos;  op := SELF.op;
			IF TraceEmit THEN DebugEnter(aDOp) END;
			lopd.Emit(code, l); 
			IF op = PCS.or THEN
				PCC.CondOr(code, l); ropd.Emit(code, r); PCC.Or(code, l, r)
			ELSIF op = PCS.and THEN
				PCC.CondAnd(code, l); ropd.Emit(code, r); PCC.And(code, l, r)
			ELSIF (PCS.eql <= op) & (op <= PCS.geq) OR (op = PCS.in) OR (op = PCC.bitfn) THEN
				IF l.type = PCT.Bool THEN PCC.Load(code, l) END;
				ropd.Emit(code, r); PCC.RelOp(code, op, l, r);
			ELSIF op = lenfn THEN
				IF ropd # NIL THEN ropd.Emit(code, r); ELSE PCC.MakeConst(r, Zero.con, PCT.Int32) END;
				PCC.Len(code, l, r)
			ELSIF op = PCS.is THEN
				PCC.TypeCheck(code, l, ropd.type, FALSE, FALSE);
			ELSE
				IF (lopd IS Index) & (lopd.type IS PCT.Basic) THEN PCC.Load(code, l) END;	(* preload arrays to avoid running out of registers *)
				ropd.Emit(code, r);
				PCC.DOp(code, op, l, r)
			END;
			IF type # l.type THEN
				StringPool.GetString(type.owner.name, t1);
				StringPool.GetString(l.type.owner.name, t2);
				HALT(99)
			END;
			IF TraceEmit THEN DebugLeave(aDOp) END
		END Emit;

		PROCEDURE& InitD*(pos: LONGINT; op: Operator; restype: PCT.Struct; lopd, ropd: Expression);
		BEGIN  
			SELF.op := op;  SELF.lopd := lopd;  SELF.ropd := ropd;
			Init(pos, restype);
		END InitD;
	END DOp;
		
	MOp* = OBJECT (Expression)
		VAR	op: Operator;  opd: Expression;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR tmp: Operator;  pos: LONGINT;  t: PCT.Struct;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aMOp) END;
			tmp := op;
			IF op # typecodefn THEN opd.Emit(code, i) END;
			CASE op OF
			| adrfn:
					PCC.SYSaddress(code, i)
			| get8fn, get16fn, get32fn:
					PCC.GetMemory(code, i, type)
			| typecodefn:
					t := opd.type;
					IF t IS PCT.Pointer THEN
						PCC.MakeTD(i, t(PCT.Pointer).baseR)
					ELSE
						PCC.MakeTD(i, t(PCT.Record))
					END;
					PCC.Convert(code, i, PCT.Int32, TRUE);
			ELSE
				PCC.MOp(code, op, i);
			END;
			ASSERT((type = i.type) OR (op = adrfn) & (type IS PCT.Pointer));
			IF TraceEmit THEN DebugLeave(aMOp) END
		END Emit;

		PROCEDURE& InitM*(pos: Operator; op: Operator;  restype: PCT.Struct; opd: Expression);
		BEGIN  Init(pos, restype);
			SELF.op := op;  SELF.opd := opd;
		END InitM;
	END MOp;
	
	Conversion* = OBJECT (Expression)
		VAR	exp: Expression;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  pos: LONGINT;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aConversion) END;
			exp.Emit(code, i); PCC.Convert(code, i, type, FALSE);
			IF TraceEmit THEN DebugLeave(aConversion) END
		END Emit;
		
		PROCEDURE & InitC*(pos: LONGINT; exp: Expression; type: PCT.Struct);
		BEGIN  Init(pos, type);  SELF.exp := exp;
		END InitC;
	END Conversion;
	
	Projection* = OBJECT (Expression)
		VAR  exp: Expression;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		BEGIN
			exp.Emit(code, i);  PCC.Convert(code, i, type, TRUE)
		END Emit;
		
		PROCEDURE & InitP*(pos: LONGINT; exp: Expression; type: PCT.Struct);
		BEGIN  Init(pos, type);  SELF.exp := exp;
		END InitP;
	END Projection;
	
	ExprList* = OBJECT (PCT.Node)
		VAR
			first*, last: Expression;
			params*, hidden: PCT.Parameter;
			suppress: BOOLEAN;
			parCount, openAryReturns, retDescSize*: LONGINT;
			rType: PCT.Struct;
		
		PROCEDURE ClearStack*(code: PCC.Code);
		BEGIN
			(* if proc returns an open array: stack is cleaned by return statement *)
			IF (openAryReturns > 0) & ((~(rType IS PCT.Array)) OR (rType(PCT.Array).mode # PCT.open)) THEN
				PCC.RemoveArys(code, openAryReturns);
			END;
		END ClearStack;
		
		PROCEDURE DoOpenAryParams*(code: PCC.Code);
		VAR
			p: Expression;
			o: PCT.Parameter;
			i: PCC.Item;
		BEGIN
			openAryReturns := 0;
			p := first; o := params;
			WHILE (p # NIL) & (o # NIL) DO
				IF IsInvalid(p) OR (o = NIL) THEN
					(* skip *)
				ELSIF ~ParameterCompatible(p, o) THEN
					(* skip *)
				ELSIF (p IS FunCall) & (o.type IS PCT.Array) & (o.type(PCT.Array).mode = PCT.open) THEN
					PCC.PrepStack(code, o.type, p.type);
					p(FunCall).Emit(code, i);
					INC(openAryReturns);
				END;
				p := p.link;
				o := o.nextPar;
			END;
		END DoOpenAryParams;
		
		PROCEDURE Emit*(code: PCC.Code);
		VAR p, p0: Expression; i: PCC.Item; pos, cnt, ofs, parSize, rSize, parNbr: LONGINT;  o: PCT.Parameter; vstat: Var;
			str: ARRAY 32 OF CHAR;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aExprList) END;
			
			DoOpenAryParams(code);
			ofs := 0;
			parNbr := openAryReturns;
			PCC.FixRetDesc(code, rType, openAryReturns, ofs);
			
			p := first; o := params; cnt := 0;
			WHILE (p # NIL) & (o # NIL) DO
				IF IsInvalid(p) OR (o = NIL) THEN
					(*skip*)
				ELSIF ~ParameterCompatible(p, o) THEN
(*
					IF (o.nextPar = NIL) & (p.link = NIL) THEN
						PCM.LogWLn;
						PCT.GetTypeName(p.type, str); PCM.LogWStr(str); PCM.LogWStr(" - ");
						PCT.GetTypeName(o.type, str); PCM.LogWStr(str);
						IF p.type = o.type THEN PCM.LogWStr(" equal ") END;
						IF p.type = p.type.owner.type THEN PCM.LogWStr(" p ") END;
(*
						IF o.type = o.type.owner.type THEN PCM.LogWStr(" o ") END;
*)
						IF o.type IS PCT.Record THEN PCM.LogWStr(" o is record ") END;
					END;
*)
					PCM.Error(113, p.pos, "");
				ELSIF (p IS FunCall) & ((p.type IS PCT.Record) OR (o.type IS PCT.Array)) THEN
					IF (o.type IS PCT.Record) OR (o.type(PCT.Array).mode = PCT.static) THEN
						PCC.PushRetDesc1(code, o);
						p.Emit(code, i);
					ELSE
						PCC.PushOpenAryParams(code, o.type, p.type, ofs, parNbr);
						DEC(parNbr);					
					END;							
				ELSE
					p0 := p;
					IF o.name = PCT.SelfName THEN
						IF o.ref & (p0.type IS PCT.Pointer) THEN	(*special case, autodereferentiation*)
							p0 := NewDeref(p0.pos, p0(Designator));
						END
					END;
					IF (p0 IS Var) THEN
						vstat := p0(Var);
						IF (vstat.obj.name = PCT.SelfName) & (vstat.type IS PCT.Record) & (vstat.type(PCT.Record).ptr # NIL) THEN
							IF PCT.IsPointer(o.type) THEN
								p0 := MakeSelf(vstat)
							END
						END
					END;
					IF ~((o.type = PCT.UndefType) OR ~ParameterCompatible(p0, o)) THEN
						IF ~o.ref & (p0.type # o.type) THEN
							p0 := NewConversion(p0.pos, p0, o.type)
						END;
						p0.Emit(code, i);
						PCC.Param(code, i, o.type, o.ref)
					END
				END;

					(* keep track of parameters onto stack *)
				IF (o.type IS PCT.Array) & (o.type(PCT.Array).mode = PCT.open) THEN
					INC(ofs, PCC.GetDims(o.type)*4 + 4);
				ELSE
					IF o.type.size = NIL THEN
						parSize := 4;	(* assume pointer *)
					ELSE
						ASSERT(o.type.size IS PCBT.Size, 334);
						parSize := o.type.size(PCBT.Size).size;
					END;
					INC(ofs, parSize);
					INC(ofs, (-ofs) MOD 4);
				END;
				
				p := p.link; o := o.nextPar; INC(cnt)
			END;	(*while*)

			 ASSERT(parNbr = 0, 335);
			
			IF p # NIL THEN
				PCM.Error(64, p.pos, "")
			ELSIF o # NIL THEN
				PCM.Error(65, pos, "")
			END;
			IF TraceEmit THEN DebugLeave(aExprList) END
		END Emit;
		
		PROCEDURE Append*(stat: Expression);
		BEGIN
			INC(parCount);
			IF stat.type IS PCT.Record THEN  PCT.RecordSizeUsed(stat.type(PCT.Record))  END;	(*Par-> uses size, VarPar -> uses TD *)
			IF first = NIL THEN  first := stat
			ELSE  last.link := stat
			END;
			last := stat;
		END Append;
		
		PROCEDURE GetParList(VAR count: LONGINT;  VAR list: ARRAY OF PCT.Struct);
			VAR p: Expression; i: LONGINT;
		BEGIN
			i := 0;
			p := first;
			WHILE p # NIL DO
				list[i] := p.type; INC(i);
				p := p.link
			END;
			count := i;
			ASSERT(i = parCount);
		END GetParList;
(*		
		PROCEDURE NothingLeft*(): BOOLEAN;
		BEGIN
			RETURN (hidden = NIL)
		END NothingLeft;
*)
		PROCEDURE & InitEL*(pos: LONGINT; rType: PCT.Struct);
		BEGIN  first := NIL; last := NIL; SELF.pos:=pos; SELF.rType := rType;
		END InitEL;
	END ExprList;
	
	BuiltInEl = OBJECT (ExprList)		(*not exported, for internal use only*)
		(*for built-in absfn, capfn, chrfn, entierfn, entierhfn, longfn, oddfn, ordfn,shortfn*)
		VAR
			fnr: LONGINT;	(*functions number*)
			pnr: LONGINT;	(*nof parameters parsed / parameter currently under check*)
			array: PCT.Array;
			usearray: BOOLEAN;
		
		PROCEDURE Append*(stat: Expression);		(*only check the parameters, call created in NewFuncCall, NewProcCall*)
			VAR i: LONGINT; p: PCT.Proc; ff, pp: LONGINT;  t: PCT.Struct; ptr: PCT.Pointer; rec: PCT.Record;  tmparr: PCT.Array;
		BEGIN
			ff := fnr;  pp := pnr;
			INC(pnr);
			IF IsInvalid(stat) THEN  first:=InvalidExpr;  RETURN  END;
			IF pnr=1 THEN
				first:=InvalidExpr;
				CASE fnr OF
				(*functions*)
				| valfn, sizefn, typecodefn:
						IF ~(stat IS Type)  THEN  PCM.Error(115, stat.pos, "");  first  :=  MakeNode(stat.pos, NIL, PCT.Int32.owner) (*NIL -> type is no field!*)
						ELSE  first := stat  END;
						IF (fnr = sizefn) & (stat.type IS PCT.Record) THEN  PCT.RecordSizeUsed(stat.type(PCT.Record)) END;
						IF (fnr = typecodefn) THEN
							t := stat.type;
							IF (t IS PCT.Pointer) THEN  t := t(PCT.Pointer).base  END;
							IF (t IS PCT.Record) THEN PCT.RecordSizeUsed(t(PCT.Record))
							ELSE PCM.Error(53, stat.pos, "")
							END
						END
				| get8fn, get16fn, get32fn:
						IF PCT.IsCardinalType(stat.type) THEN first := NewConversion(stat.pos, stat, PCT.Int32)
						ELSE  PCM.Error(113, stat.pos, "");  first := InvalidExpr
						END
				| PCC.absfn, PCC.capfn, PCC.oddfn, lenfn, PCC.bitfn, PCC.ashfn, PCC.rotfn, PCC.lshfn, adrfn:		(*params are checked in MOp/DOp or any pars*)
						first:=stat
				| chrfn:
						IF PCT.IsCardinalType(stat.type) OR (stat.type = PCT.Byte) THEN
							first:=NewConversion(stat.pos, stat, PCT.Char8)
						ELSE  PCM.Error(115, stat.pos, "") END;
				| chr8fn, chr16fn, chr32fn:
						IF PCT.IsCardinalType(stat.type) THEN
							first:=NewConversion(stat.pos, stat, PCT.CharType[fnr-chr8fn])
						ELSE  PCM.Error(115, stat.pos, "") END;
				| ordfn:
						IF (stat.type=PCT.Char8) OR (stat.type=PCT.Byte) THEN
							first:=NewConversion(stat.pos, stat, PCT.Int16)
						ELSE  PCM.Error(115, stat.pos, "") END;
				| ord8fn, ord16fn, ord32fn:
						IF PCT.IsCharType(stat.type) THEN
							first:=NewConversion(stat.pos, stat, PCT.NumericType[fnr-ord8fn])
						ELSE  PCM.Error(115, stat.pos, "") END
				| entierfn:
						IF PCT.IsFloatType(stat.type) THEN first:=NewConversion(stat.pos, stat, PCT.Int32)
						ELSE  PCM.Error(115, stat.pos, "") END;
				| entierhfn:
						IF PCT.IsFloatType(stat.type) THEN first:=NewConversion(stat.pos, stat, PCT.Int64)
						ELSE  PCM.Error(115, stat.pos, "") END;
				| longfn:
						IF PCM.LocalUnicodeSupport THEN
							i := LEN(PCT.NumericType)-1; REPEAT DEC(i) UNTIL (i = -1) OR (stat.type = PCT.NumericType[i]);
							IF (i = -1) THEN
								i := LEN(PCT.CharType)-1; REPEAT DEC(i) UNTIL (i = -1) OR (stat.type = PCT.CharType[i]);
								IF (i = -1) THEN
									PCM.Error(115, stat.pos, "")
								ELSE
									first := NewConversion(stat.pos, stat, PCT.CharType[i+1])
								END
							ELSE
								first := NewConversion(stat.pos, stat, PCT.NumericType[i+1])
							END
						ELSE
							i:=0;  WHILE (i<LEN(PCT.NumericType))&(stat.type#PCT.NumericType[i]) DO  INC(i)  END;
							IF i<LEN(PCT.NumericType)-1 THEN first:=NewConversion(stat.pos, stat, PCT.NumericType[i+1])
							ELSIF i = LEN(PCT.NumericType)-1 THEN	(*skip: LONG(LONGREAL) = LONGREAL*)
							ELSIF stat.type = PCT.Char8 THEN  first := NewConversion(stat.pos, stat, PCT.Int32)
							ELSE  PCM.Error(115, stat.pos, "")  END
						END
				| shortfn:
						IF PCM.LocalUnicodeSupport THEN
							i := LEN(PCT.NumericType);  REPEAT DEC(i) UNTIL (i = 0) OR (stat.type = PCT.NumericType[i]);
							IF (i = 0) THEN
								i := LEN(PCT.CharType); REPEAT DEC(i) UNTIL (i = 0) OR (stat.type = PCT.CharType[i]);
								IF (i = 0) THEN
									PCM.Error(115, stat.pos, "")
								ELSE
									first := NewConversion(stat.pos, stat, PCT.CharType[i-1])
								END
							ELSE
								first := NewConversion(stat.pos, stat, PCT.NumericType[i-1])
							END
						ELSE
							i:=0;  WHILE (i<LEN(PCT.NumericType))&(stat.type#PCT.NumericType[i]) DO  INC(i)  END;
							IF (i=0)OR (i=LEN(PCT.NumericType)) THEN  PCM.Error(115, stat.pos, "")
							ELSE  first := NewConversion(stat.pos, stat, PCT.NumericType[i-1])  END
						END
				| maxfn, minfn:
						first := stat;
				(*procedures*)
				| assertfn, passivatefn:
						IF stat.type#PCT.Bool THEN  PCM.Error(111, stat.pos, "")
						ELSE first:=stat  END
				| incfn, decfn:
						IF ~IsVariable(stat) THEN PCM.Error(112, stat.pos, "")
						ELSIF ~PCT.IsCardinalType(stat.type) THEN  PCM.Error(111, stat.pos, "")
						ELSE first:=stat  END
				| portinfn, portoutfn:
						IF ~PCT.IsCardinalType(stat.type) THEN  PCM.Error(111, stat.pos, "")
						ELSIF (stat IS Const) & (stat.type = PCT.Int32) THEN  PCM.Error(203, stat.pos, "")
						ELSE  first := NewConversion(stat.pos, stat, PCT.Int16)
						END
				| getfn, putfn, put8fn, put16fn, put32fn, movefn:
						IF ~PCT.IsCardinalType(stat.type) & ~PCT.IsPointer(stat.type) THEN  PCM.Error(111, stat.pos, "")
						ELSE first:=NewConversion(stat.pos, stat, PCT.Int32)  END
				| getregfn, putregfn:
						first := Zero;
						IF ~(stat IS Const) OR ~PCT.IsCardinalType(stat.type) THEN  PCM.Error(51, stat.pos, "")
						ELSE
							i := stat(Const).con.int;
							IF (i < 0) OR (i > SYSTEM.DH) THEN  PCM.Error(220  , stat.pos, "")
							ELSE first:=stat  END
						END
				| inclfn, exclfn:
						IF ~IsVariable(stat) THEN PCM.Error(112, stat.pos, "")
						ELSIF stat.type#PCT.Set THEN  PCM.Error(64, stat.pos, "")
						ELSE first:=stat  END
				| copyfn:
						IF (stat.type=PCT.String) OR (stat.type IS PCT.Array) & (stat.type(PCT.Array).base=PCT.Char8) THEN
							first:=stat
						ELSIF (stat.type = PCT.Char8) & (stat IS Const) THEN
							first := NewConversion(stat.pos, stat, PCT.String)
						ELSE  PCM.Error(115, stat.pos, "")  END
				| shaltfn, haltfn:
						IF ~(stat IS Const) THEN PCM.Error(50, stat.pos, "")
						ELSIF ~PCT.IsCardinalType(stat.type) THEN  PCM.Error(64, stat.pos, "")
						ELSIF (fnr=haltfn) & (stat(Const).con.int < 20) THEN  PCM.Error(218, stat.pos, "")
						ELSE first:=stat  END
				| sysnewfn:
						IF ~IsVariable(stat) THEN PCM.Error(112, stat.pos, "")
						ELSIF ~PCT.IsPointer(stat.type) THEN PCM.Error(111, stat.pos, "")
						ELSE first := stat
						END
				| newfn:
						first := stat; last := stat;
						IF ~IsVariable(stat) THEN PCM.Error(112, stat.pos, "")
						ELSIF stat.type IS PCT.Pointer THEN
							ptr := stat.type(PCT.Pointer);
							IF ptr.baseR # NIL THEN
								usearray := FALSE;
								rec := ptr.baseR;
								PCT.RecordSizeUsed(rec);
								rec.scope.Await(PCT.procdeclared);
								ASSERT(rec.scope.state >= PCT.procdeclared);
								p := rec.scope.initproc;
								IF p#NIL THEN
									params := p.scope.firstPar;
								ELSE
									params := NIL
								END;
								hidden:=params
							ELSIF (ptr.baseA # NIL) THEN
								array := ptr.baseA;
								tmparr := array;
								WHILE tmparr.base IS PCT.Array DO tmparr := tmparr.base(PCT.Array ) END;
								IF tmparr.base IS PCT.Record THEN PCT.RecordSizeUsed(tmparr.base(PCT.Record)) END;
								IF array.mode = PCT.static THEN  array := NIL	(*no params needed*)
								ELSIF ~(array.mode = PCT.open) THEN  array := NIL; PCM.Error(89, stat.pos, "")
								END;
							ELSE PCM.Error(111, stat.pos, ""); array := NIL
							END
						ELSE PCM.Error(111, stat.pos, ""); array := NIL
						END
				ELSE  PCM.Error(64, stat.pos, "")
				END
			ELSIF fnr=newfn THEN
				IF usearray THEN
					IF array = NIL THEN
						array := NIL; PCM.Error(64, stat.pos, "")
					ELSE
						ASSERT(array.mode = PCT.open);
						last.link := stat; last := stat;
						IF (array.base IS PCT.Array) & (array.base(PCT.Array).mode = PCT.open) THEN
							array := array.base(PCT.Array)
						ELSE
							array := NIL
						END
					END;
				ELSE	Append^(stat)
				END
			ELSIF (pnr=2) & (first#NIL) THEN
				CASE fnr OF
				| assertfn:
						IF ~(stat IS Const) THEN PCM.Error(50, stat.pos, "")
						ELSIF ~PCT.IsCardinalType(stat.type) THEN PCM.Error(51, stat.pos, "")
						ELSE first.link:=stat
						END
				| valfn:
						first := Project(stat.pos, stat, first.type)
				| lenfn, PCC.bitfn, PCC.ashfn, PCC.rotfn, PCC.lshfn, portoutfn, putfn:
						first.link:=stat
				| put8fn:
						IF (stat.type = PCT.Int8) OR (stat.type = PCT.Byte) OR (stat.type = PCT.Char8) OR (stat.type = PCT.Bool) THEN
							first.link := stat
						ELSIF PCT.IsCardinalType(stat.type) THEN
							first.link := NewConversion(stat.pos, stat, PCT.Int8)
						ELSE
							PCM.Error(113, stat.pos, ""); first.link := InvalidExpr
						END
				| put16fn:
						IF PCT.IsCardinalType(stat.type) THEN
							first.link := NewConversion(stat.pos, stat, PCT.Int16)
						ELSE
							PCM.Error(113, stat.pos, ""); first.link := InvalidExpr
						END
				| put32fn:
						IF (stat.type = PCT.Int32) OR PCT.IsPointer(stat.type) OR (stat.type = PCT.Set) THEN
							first.link := stat
						ELSIF stat.type IS PCT.Delegate THEN
							first.link := Project(stat.pos, stat, PCT.Int32)
						ELSIF PCT.IsCardinalType(stat.type) THEN
							first.link := NewConversion(stat.pos, stat, PCT.Int32)
						ELSE
							PCM.Error(113, stat.pos, ""); first.link := InvalidExpr
						END
				| incfn, decfn:
						IF ~(stat.type IS PCT.Basic) OR (PCT.BasicTypeDistance(stat.type(PCT.Basic), first.type(PCT.Basic)) < 0) THEN
							PCM.Error(115, stat.pos, "")
						ELSE  first.link:=NewConversion(stat.pos, stat, first.type)  END;
				| putregfn, getregfn:
						IF (fnr = getregfn) & ~IsVariable(stat) THEN PCM.Error(112, stat.pos, "") END;
						i := first(Const).con.int;
						IF (i >= SYSTEM.EAX) & (i <= SYSTEM.EDI) THEN
							IF (stat.type = PCT.Int32) OR (stat.type = PCT.Set) OR (stat.type IS PCT.Pointer) OR (stat.type IS PCT.Delegate) THEN
							ELSIF PCT.IsCardinalType(stat.type) THEN
								stat := NewConversion(stat.pos, stat, PCT.Int32)
							ELSE
								PCM.Error(113, stat.pos, "")
							END
						ELSIF (i >= SYSTEM.AX) & (i <= SYSTEM.DX) THEN
							IF stat.type = PCT.Int8 THEN
								stat := NewConversion(stat.pos, stat, PCT.Int16)
							ELSIF stat.type # PCT.Int16 THEN PCM.Error(113, stat.pos, "")
							END
						ELSIF  (i >= SYSTEM.AL) & (i <= SYSTEM.DH) THEN
							IF stat.type # PCT.Int8 THEN PCM.Error(113, stat.pos, "") END
						END;
						first.link:=stat
				| portinfn, getfn:
						IF ~IsVariable(stat) THEN PCM.Error(112, stat.pos, "")
						ELSE  first.link:=stat  END;
				| inclfn, exclfn, movefn:
						IF ~PCT.IsCardinalType(stat.type) THEN  PCM.Error(113, stat.pos, "")
						ELSE  first.link:=NewConversion(stat.pos, stat, PCT.Int32)  END
				| copyfn:
						IF ~IsVariable(stat) THEN PCM.Error(112, stat.pos, "")
						ELSIF (stat.type IS PCT.Array) & PCT.IsCharType(stat.type(PCT.Array).base) THEN  first.link:=stat
						ELSE  PCM.Error(115, stat.pos, "")  END
				| sysnewfn:
						IF ~PCT.IsCardinalType(stat.type) THEN  PCM.Error(113, stat.pos, "")
						ELSE  first.link:=stat  END
				ELSE  PCM.Error(64, stat.pos, "")
				END
			ELSIF (pnr=3) & (fnr=movefn) THEN
				IF ~PCT.IsCardinalType(stat.type) THEN  PCM.Error(113, stat.pos, "")
				ELSE  first.link.link:=NewConversion(stat.pos, stat, PCT.Int32)  END
			ELSE  PCM.Error(64, stat.pos, "")
			END
		END Append;
		
		PROCEDURE NothingLeft*(): BOOLEAN;
		BEGIN
			IF (fnr = lenfn) & (pnr = 1) THEN	(*add the default dimension*)
				first.link:=NewIntValue(NoPosition, 0, PCT.Int8);
				INC(pnr)
			ELSIF (fnr = assertfn) & (pnr = 1) THEN
				first.link := NewIntValue(NoPosition, PCM.AssertTrap, PCT.Int8);
				INC(pnr)
			ELSIF ((fnr = decfn) OR (fnr = incfn)) & (pnr = 1) THEN
				first.link := NewConversion(first.pos, NewIntValue(NoPosition, 1, PCT.Int8), first.type);
				INC(pnr)
			END;
			RETURN
				(pnr = 0) & (fnr>=stifn) & (fnr<=clifn) OR
				(pnr = 1) & ((fnr>=sizefn) & (fnr<=haltfn) OR (fnr >= PCC.absfn) & (fnr <= PCC.oddfn)) OR
				(pnr = 2) & ((fnr>=valfn) & (fnr<=sysnewfn) OR (fnr >= PCC.ashfn) & (fnr <= PCC.rotfn) OR (fnr = PCC.bitfn)) OR
				(pnr = 3) & (fnr=movefn) OR
				(fnr=newfn) & (~usearray OR (array = NIL))
		END NothingLeft;

		PROCEDURE & Init*(pos: LONGINT; rType: PCT.Struct; fnr: LONGINT);
		BEGIN  InitEL(pos, rType);  SELF.fnr:=fnr; pnr:=0; usearray := TRUE
		END Init;
	END BuiltInEl;

	FunCall* = OBJECT (Expression)
		VAR	proc*: Designator;  params*: ExprList;  curLevel: SHORTINT;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  lev: SHORTINT;  pos: LONGINT;  p: AnyProc;  scope: PCT.Scope;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aFunCall) END;
			PCC.SaveRegisters(code);
			params.Emit(code);
			IF (proc IS AnyProc) THEN
				p := proc(AnyProc); lev := p.proc.level;
				IF lev # 0 THEN  PCC.PushSL(code, curLevel-lev)  END
			END;
			IF (p # NIL) & (PCT.Inline IN p.proc.flags) THEN
				scope := p.proc.scope;
				IF scope.code = NIL THEN scope.Await(PCT.complete) END;
				Inline(code, scope.code)
			ELSE
				proc.Emit(code, i); PCC.Call(code, i);
			END;
			PCC.Result(code, i, type);
			params.ClearStack(code);
			PCC.RestoreRegisters(code);
			IF TraceEmit THEN DebugLeave(aFunCall) END
		END Emit;
		
		PROCEDURE & InitF*(pos: LONGINT; proc: Designator;  params: ExprList;  curLevel: SHORTINT);
		VAR p: PCT.Parameter;  ret: PCT.Struct;
		BEGIN
			IF GetProcedureInfo(proc, p, ret) THEN
				Init(pos, ret)
			ELSE
				HALT(99)
			END;
			SELF.proc := proc;  SELF.params := params;  SELF.curLevel := curLevel
		END InitF;
	END FunCall;

(** ---------- Designators -------------- *)
	(* a designator represents a memory location*)
	Designator* = OBJECT (Expression)
		VAR  readonly-: BOOLEAN;

		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  pos: LONGINT;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aDesignator) END;
			HALT(99);	(*Abstract*)
		END Emit;

		PROCEDURE IsCallable*(): BOOLEAN;
		BEGIN	RETURN (type IS PCT.Delegate) OR (SELF = InvalidDesig)
		END IsCallable;
		
	END Designator;
	
	Temp = OBJECT (Designator)
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		BEGIN  PCC.MakeStackItem(i, type)
		END Emit;
	END Temp;
	
	(** Wrapper - contains a reference to an existing designator. Handy to avoid copies *)
	
	Wrapper* = OBJECT (Designator)
	VAR
		des: Designator;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		BEGIN  des.Emit(code, i)
		END Emit;
	
		PROCEDURE & InitW*(d: Designator);
		BEGIN
			des := d;  readonly := d.readonly;  Init(d.pos, d.type)
		END InitW;
	END Wrapper;
	
	SProc = OBJECT (Designator)
		VAR nr: LONGINT;
		
		PROCEDURE IsCallable*(): BOOLEAN;
		BEGIN	RETURN TRUE
		END IsCallable;
		
		PROCEDURE & SInit(pos, nr: LONGINT);
		BEGIN
			SELF.nr := nr;  Init(pos, PCT.NoType)
		END SInit;
	END SProc;
	
	
	(**basic designators*)
	Var* = OBJECT (Designator)
		VAR obj*: PCT.Variable;  deltaLevel: SHORTINT;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  pos: LONGINT;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aVar) END;
			IF obj = NIL THEN
				PCC.MakeStackItem(i, type)
			ELSE
				PCC.MakeItem(i, obj, deltaLevel)
			END;
			IF type # obj.type THEN  PCC.Convert(code, i, type, TRUE)  END;		(* for WITH *)
			IF TraceEmit THEN DebugLeave(aVar) END
		END Emit;
		
		PROCEDURE & InitD*(pos: LONGINT; obj: PCT.Variable;  curLevel: SHORTINT;  readonly: BOOLEAN);
		BEGIN
			SELF.obj := obj; SELF.readonly := readonly;
			Init(pos, obj.type);
			IF (obj # NIL) & ~(obj IS PCT.GlobalVar) THEN
				deltaLevel := curLevel - obj.level;
				ASSERT(deltaLevel >= 0);
			END
		END InitD;
	END Var;
	
	AnyProc* = OBJECT (Designator)
		VAR
			scope: PCT.Scope;
			o: PCT.Symbol;
			proc: PCT.Proc;
			method: PCT.Method;	(* equal to proc *)
			supercall: BOOLEAN;
			self: Designator;
			resolved: BOOLEAN;
			
		PROCEDURE Emit(code: PCC.Code;  VAR i: PCC.Item);
		BEGIN
			ASSERT(resolved);
			IF self # NIL THEN
				self.Emit(code, i);
				PCC.Method(code, i, i, method, supercall);
			ELSE
				PCC.MakeItem(i, proc, 0)
			END
		END Emit;
		
		PROCEDURE IsCallable*(): BOOLEAN;
		BEGIN RETURN TRUE
		END IsCallable;
		
		PROCEDURE Resolve(el: ExprList;  list: PCT.Parameter);
			VAR count: LONGINT;  parlist: ARRAY 32 OF PCT.Struct; res, selfo: PCT.Symbol;
		BEGIN
			IF ~(PCT.Overloading IN scope.module.scope.flags) & ~(PCT.Operator IN o.flags) THEN
				res := o
			ELSE
				IF el # NIL THEN
					el.GetParList(count, parlist);
				ELSE
					count := 0;
					WHILE list # NIL DO
						parlist[count] := list.type;
						INC(count);
						list := list.nextPar
					END
				END;
				res := PCT.FindProcedure(scope, scope, o.name, count, parlist, (el = NIL), TRUE)
			END;
			IF res = NIL THEN
				PCM.Error(0, pos, "no matching procedure found")
			ELSIF res IS PCT.Method THEN
				WITH res: PCT.Method DO
					IF self = NIL THEN	(*implicit self*)
						selfo := PCT.Find(scope, scope, PCT.SelfName, PCT.procdeclared, TRUE);
						self := MakeNode(pos, scope, selfo)
					END;
					IF supercall & (res.super = NIL) THEN  PCM.Error(74, pos, "")  END;	(*supercall to non-existent method*)
					IF el # NIL THEN  el.Append(self)  END;
					list := res.scope.firstPar;
					type := res.type;
					proc := res;
					method := res
				END
			ELSE
				WITH res: PCT.Proc DO
					list := res.scope.firstPar;
					type := res.type;
					proc := res
				END
			END;
			IF el # NIL THEN  el.params := list  END;
			resolved := TRUE
		END Resolve;
		
		PROCEDURE & InitP(pos: LONGINT;  scope: PCT.Scope;  o: PCT.Symbol;  self: Designator);
		BEGIN
				(* original version *)
			(* Init(pos, PCT.NoType); *)
				(* mb version *)
			(* Init(pos, o.type); *)
				(* special version *)
			IF (PCT.Operator IN o.flags) THEN Init(pos, o.type) ELSE Init(pos, PCT.NoType) END;
			IF scope = NIL THEN
				ASSERT(self # NIL);
				scope := self.type(PCT.Pointer).baseR.scope
			END;
			SELF.scope := scope;
			SELF.o := o; SELF.self := self;
			resolved := FALSE
		END InitP;
	END AnyProc;
	
	Type* = OBJECT (Designator)
		VAR obj: PCT.Type;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  pos: LONGINT;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aType) END;
			PCDebug.ToDo(PCDebug.NotImplemented);
			IF TraceEmit THEN DebugLeave(aType) END
		END Emit;
		
		PROCEDURE & InitD*(pos: LONGINT; obj: PCT.Type);
		BEGIN  SELF.obj := obj;
			Init(pos, obj.type)
		END InitD;
	END Type;
	
	(** ---------- Composed Designators -------------- *)
	Deref* = OBJECT (Designator)
		VAR ptr*: Designator;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  pos: LONGINT;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aDeref) END;
			ptr.Emit(code, i);  PCC.Deref(code, i);
			IF ~Workaround THEN ASSERT(type = i.type) END;
			IF TraceEmit THEN DebugLeave(aDeref) END
		END Emit;
		
		PROCEDURE & InitD*(pos: LONGINT; ptr: Designator; type: PCT.Struct);
		BEGIN
			Init(pos, type); SELF.ptr := ptr
		END InitD;
	END Deref;

	Field* = OBJECT (Designator)
		VAR	rec*: Designator;  field*: PCT.Field;
	
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  pos: LONGINT;
			name0, name1, name2, name3: ARRAY 64 OF CHAR;
		BEGIN
			IF TraceEmit THEN DebugEnter(aField) END;
			pos := SELF.pos;
			rec.Emit(code, i);
			PCC.Field(code, i, field);
			IF ~Workaround THEN
				IF type # i.type THEN
					PCT.GetTypeName(type, name1);
					PCT.GetTypeName(i.type, name2);
					PCT.GetTypeName(field.type, name3);
				END;
				ASSERT(type = i.type)
			END;
			IF TraceEmit THEN DebugLeave(aField) END
		END Emit;
		
		PROCEDURE & InitF*(pos: LONGINT; rec: Designator; field: PCT.Field; readonly: BOOLEAN);
		BEGIN
			Init(pos, field.type);
			SELF.readonly := readonly;  SELF.field := field;  SELF.rec := rec
		END InitF;
	END Field;
	
	Index* = OBJECT (Designator)
		VAR	array*: Designator; index*: Expression; check*: BOOLEAN;
		
		PROCEDURE Emit*(code: PCC.Code; VAR a: PCC.Item);
		VAR  i: PCC.Item;  pos: LONGINT;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aIndex) END;
			index.Emit(code, i); array.Emit(code, a);
			PCC.Index(code, a, i);
			ASSERT(type = a.type);
			IF TraceEmit THEN DebugLeave(aIndex) END
		END Emit;
		
		PROCEDURE & InitI*(pos: LONGINT; array: Designator; index: Expression; check: BOOLEAN);
		BEGIN
			readonly := array.readonly;
			Init(pos, array.type(PCT.Array).base);  SELF.array := array;  SELF.index := index;  SELF.check:=check
		END InitI;
	END Index;
	
	Guard* = OBJECT (Designator)
		VAR des: Designator;  to: PCT.Struct;  equal: BOOLEAN;
		
		PROCEDURE Emit*(code: PCC.Code; VAR i: PCC.Item);
		VAR  pos: LONGINT;
		BEGIN
			pos := SELF.pos;
			IF TraceEmit THEN DebugEnter(aGuard) END;
			des.Emit(code, i);
			PCC.TypeCheck(code, i, to, TRUE, equal);
			ASSERT(type = i.type);
			IF TraceEmit THEN DebugLeave(aGuard) END
		END Emit;
		
		PROCEDURE & InitG*(pos: LONGINT; des: Designator;  type: PCT.Struct; equal: BOOLEAN);
		BEGIN  Init(pos, type);
			SELF.des := des;  to := type;  SELF.equal := equal;
			readonly := des.readonly;
		END InitG;
	END Guard;
	
	LoopInfo* = RECORD
		in, out: PCC.Label;
		true, false: BOOLEAN;	(*result of last test, used for dead code elimination*)
	END;

	CaseRange = POINTER TO RECORD 
		min, max: LONGINT;
		next: CaseRange
	END;
	
	CaseInfo* = RECORD
		range: CaseRange;
		out: PCC.Label;
		ref: PCC.Item;
		type: PCT.Basic;
		first: BOOLEAN;	(*first case line? -> avoid jmp*)
	END;
	
	VAR
	Invalid-: PCT.Node;
	InvalidExpr-: Expression;
	InvalidDesig-: Designator;
	InvalidEL-: ExprList;
	Zero-, One-: Const;
	unknownObj-: PCT.Symbol;
	
	aExpression, aConst, aDOp, aMOp, aConversion, aFunCall, aSFunCall, aExprList, aDesignator, aVar, aProc, aType,
	aDeref, aMethod, aField, aIndex, aGuard, aStatement, aStatSeq, aAssign, aProcCall, aSProcCall, aIf, aWhile,
	aRepeat, aReturn, aCase: LONGINT;
	

(** ---------- Helper Procedures -------------- *)

PROCEDURE DebugEnter(VAR x: LONGINT);
BEGIN {EXCLUSIVE}
	INC(x)
END DebugEnter;

PROCEDURE DebugLeave(VAR x: LONGINT);
BEGIN {EXCLUSIVE}
	DEC(x)
END DebugLeave;

PROCEDURE IsInvalid(n: PCT.Node): BOOLEAN;
BEGIN
	RETURN (n = Invalid) OR (n = InvalidExpr) OR (n = InvalidDesig) OR (n = InvalidEL)
END IsInvalid;

PROCEDURE IsVariable(n: PCT.Node): BOOLEAN;
BEGIN
	WHILE  (n IS Projection)  DO  n := n(Projection).exp  END;
	RETURN (n IS Designator) & ~((n IS AnyProc) OR (n IS Type))
END IsVariable;

PROCEDURE IsCharArray(e: Expression): BOOLEAN;
BEGIN	RETURN (e.type IS PCT.Array) & (e.type(PCT.Array).base = PCT.Char8) OR (e.type = PCT.String)
END IsCharArray;

PROCEDURE IsInterface*(n: Designator): BOOLEAN;
	VAR p: PCT.Pointer; res: BOOLEAN;
BEGIN
	res := FALSE;
	IF n IS Type THEN
		IF n.type IS PCT.Pointer THEN
			p := n.type(PCT.Pointer);
			IF p.baseR # NIL THEN
				res := PCT.interface IN p.baseR.mode
			END
		END
	END;
	RETURN res
END IsInterface;

PROCEDURE GetProcedureInfo(e: Expression;  VAR param: PCT.Parameter;  VAR ret: PCT.Struct): BOOLEAN;
BEGIN
	ret := NIL;
	IF e IS AnyProc THEN
		WITH e: AnyProc DO
			ASSERT(e.resolved);
			IF e.proc # NIL THEN
				param := e.proc.scope.firstPar;
				ret := e.type
			END
		END
	ELSIF e.type IS PCT.Delegate THEN
		param := e.type(PCT.Delegate).scope.firstPar;
		ret := e.type(PCT.Delegate).return
	ELSE
		HALT(99)
	END;
	RETURN ret # NIL
END GetProcedureInfo;

PROCEDURE ConstExpression*(pos: LONGINT; e: Expression): Const;
	VAR c: Const;
BEGIN
	IF e IS Const THEN
		c := e(Const)
	ELSE
		PCM.Error(50, pos, "");
		c := NewIntValue(pos, 0, PCT.Int8)
	END;
	RETURN c
END ConstExpression;

PROCEDURE NewDynSizedArray*(len: Expression; base: PCT.Struct; VAR res: LONGINT): PCT.Array;
	VAR a: DynSizedArray;
BEGIN
	NEW(a);
	PCT.InitOpenArray(a, base, res);
	a.dlen := len;
	a.isDynSized := TRUE;
	RETURN a
END NewDynSizedArray;

(** ---------- Type Compatibility Checks -------------- *)
(* These type checks follow the definitions given in appendix A of the Oberon-2 language report *)

PROCEDURE TypeExtension(base, ext: PCT.Struct): BOOLEAN;
VAR  extr: PCT.Record;
BEGIN
	IF (base = PCT.Ptr) & (ext IS PCT.Pointer) & (ext(PCT.Pointer).baseR # NIL)THEN
		RETURN  TRUE
	END;

	IF (base IS PCT.Pointer) & (ext IS PCT.Pointer) THEN
		base := base(PCT.Pointer).base;
		ext := ext(PCT.Pointer).base
	END;
	IF ~(base IS PCT.Record) OR ~(ext IS PCT.Record) THEN RETURN FALSE END;
	extr := ext(PCT.Record);
	
	WHILE (extr # NIL) & (extr # base) DO  extr := extr.brec  END;
	RETURN extr # NIL
END TypeExtension;

PROCEDURE ArrayCompatible(Ta, Tf: PCT.Struct): BOOLEAN;	(* Ta -> Tf . Should be only called by ParameterCompatible*)
BEGIN
	IF Tf IS PCT.Array THEN
		WITH Tf: PCT.Array DO
			RETURN
			(*rule 1*)					(Ta = Tf) OR
			(*common for 2&3*)	(Tf.mode = PCT.open) &
			(*rule 2*)					((Ta IS PCT.Array) & ArrayCompatible(Ta(PCT.Array).base, Tf.base) OR
			(*rule 3*)					(Tf.base = PCT.Char8) & (Ta = PCT.String) OR
			(*special rule*)			(Tf.base = PCT.Byte))
		END
	ELSE
		RETURN  (Ta = Tf)
	END	
END ArrayCompatible;

PROCEDURE TypeCompatible(e: Expression; Tv: PCT.Struct): BOOLEAN;	(*common checks for Assignment and Parameters*)
	VAR Te: PCT.Struct;   res: BOOLEAN; faulty: PCT.Symbol;
BEGIN
	Te := e.type; res := FALSE;
	(* static checks, rules 1/2/4/5/7*)
	IF	(Te = Tv) THEN			(*rule 1*)
		res := TRUE
	ELSIF (Tv IS PCT.Basic) THEN		(*rule 2*)
		IF (Tv = PCT.Byte) & ((Te = PCT.Int8) OR (Te = PCT.Char8)) THEN res := TRUE
		ELSIF (Tv = PCT.Ptr) & PCT.IsPointer(e.type)  THEN  res := TRUE
		ELSIF (Te IS PCT.Basic) & (PCT.BasicTypeDistance(Te(PCT.Basic), Tv(PCT.Basic)) >= 0) THEN res := TRUE
		ELSE  PCM.Error(113, e.pos, "") END
		
	ELSIF (Tv IS PCT.Pointer) THEN	(*rule 4/5*)
		IF (Te = PCT.NilType) THEN res := TRUE		(*rule 5*)
		ELSIF (Te IS PCT.Pointer) & TypeExtension(Tv, Te) THEN res := TRUE			(*rule 4*)
		ELSE PCM.Error(113, e.pos, "") END
		
	ELSIF (Tv IS PCT.Delegate) THEN	(*rule 5/7*)
		IF (Te = PCT.NilType) THEN res := TRUE		(*rule 5*)
		ELSIF e IS AnyProc THEN
			WITH Tv: PCT.Delegate DO
				WITH e: AnyProc DO
					IF ~e.resolved THEN  e.Resolve(NIL, Tv.scope.firstPar)  END;
					IF e.proc = NIL THEN
						(*fail*)
					ELSIF (e.method # NIL)  & (PCT.StaticMethodsOnly IN Tv.flags) THEN
						PCM.Error(200, e.pos, "destination is no delegate type")
					ELSIF (e.method # NIL) & (e.method.self.type IS PCT.Record) THEN
						PCM.Error(249, e.pos, "")
						
					(**
					ELSIF e.type # Tv.return THEN
(*
						PCT.GetTypeName(e.type, name);
PCM.LogWLn; PCM.LogWStr(name); PCM.LogWHex(SYSTEM.VAL(LONGINT, e.type));
PCM.LogWStr0(e.type.owner.name);
PCM.LogWStr0(e.type.owner.inScope.module.name);
						PCT.GetTypeName(Tv.return, name);
PCM.LogWLn; PCM.LogWStr(name); PCM.LogWHex(SYSTEM.VAL(LONGINT, Tv.return));
PCM.LogWStr0(Tv.return.owner.name);
PCM.LogWStr0(Tv.return.owner.inScope.module.name);
*)

						PCM.Error(117, e.pos, "return type")
											ELSIF ~PCT.ParameterMatch(e.proc.scope.firstPar, Tv.scope.firstPar, faulty) THEN
						IF faulty = NIL THEN PCM.Error(116, e.pos, "") ELSE PCM.ErrorN(115, e.pos, faulty.name) END
					**)
					
					ELSIF ~TypeCompatible0(e.type, Tv.return) THEN
						PCM.Error(117, e.pos, "return type");
						(* parameter types of Tv can be extensions of parameter types of e *)
					ELSIF ~SignatureCompatible(Tv.scope.firstPar, e.proc.scope.firstPar) THEN
						PCM.Error(115, e.pos, "")
					ELSE
						res := TRUE
					END
				END
			END
		ELSIF e.type IS PCT.Delegate THEN
			res := TypeCompatible0(Te, Tv);
			IF ~res THEN PCM.Error(113, e.pos, "") END;
			(* IF Tv # Te THEN PCM.Error(113, e.pos, "") ELSE  res := TRUE  END *)
		ELSE PCM.Error(113, e.pos, "") END
		
	ELSIF (Tv IS PCT.Array) THEN
		WITH Tv: PCT.Array DO
			IF ArrayCompatible(Te, Tv) THEN
				res := TRUE;
			ELSIF Tv.base # PCT.Char8 THEN
				PCM.Error(113, e.pos, "")
			ELSIF Te = PCT.String THEN		(*rule 6*)
				IF Tv.mode = PCT.open THEN  res := TRUE
				ELSIF (Tv.mode = PCT.static) & (Tv.len >= e(Const).con.int) THEN res := TRUE
				ELSE  PCM.Error(114, e.pos, "")  END
			ELSIF (e IS Const) & (Te = PCT.Char8) THEN	(* char consts are equivalent to a string of length 1 *)
				res := TRUE
			ELSE  PCM.Error(113, e.pos, "")  END
		END
	ELSE  PCM.Error(113, e.pos, "") END;
	RETURN res
END TypeCompatible;

PROCEDURE AssignmentCompatible(e: Expression; VAR v: Designator): BOOLEAN;
	VAR Te, Tv: PCT.Struct;
BEGIN
	Te := e.type;  Tv := v.type;
	(*dynamic checks, rules 3*)
	IF (Tv IS PCT.Record) THEN	(*rule 3*)
		IF (Te IS PCT.Record) THEN
			IF TypeExtension(Tv, Te) THEN
				(*only case where the dynamic type can be different from the static type*)
				IF (v IS Var) & (v(Var).obj IS PCT.Parameter) & (v(Var).obj(PCT.Parameter).ref) THEN
					v:=NewGuard(v.pos, v, Tv.owner, TRUE)
				END;
				RETURN TRUE
			ELSE PCM.Error(113, e.pos, "") END
		ELSE  PCM.Error(113, e.pos, "")  END
	ELSE  RETURN TypeCompatible(e, Tv)  END;
	RETURN FALSE
END AssignmentCompatible;

PROCEDURE ParameterCompatible(e: Expression; par: PCT.Parameter):BOOLEAN;
(* can e be assigned to par?*)
VAR res: BOOLEAN;
BEGIN
	res := FALSE;
	IF (par.type IS PCT.Record) & TypeExtension(par.type, e.type) THEN  res := TRUE	(*rule3, true for par and value parms*)
	ELSIF par.ref THEN	(*VAR-Parameter*)
		IF ~IsVariable(e) THEN PCM.Error(122, e.pos, "")
		ELSIF (par.type = PCT.Byte) & ((e.type = PCT.Int8) OR (e.type = PCT.Char8)) THEN res := TRUE
		ELSIF ArrayCompatible(e.type, par.type) THEN  res := TRUE
(*
		ELSIF (par.type = PCT.Ptr) & PCT.IsPointer(e.type) THEN  res := TRUE
*)
		ELSE  PCM.Error(113, e.pos, "")
		END
	ELSE  res := ArrayCompatible(e.type, par.type) OR TypeCompatible(e, par.type)
	END;
	RETURN res
END ParameterCompatible;

PROCEDURE SignatureCompatible(from, to: PCT.Parameter): BOOLEAN;
VAR
	res: BOOLEAN;
BEGIN
	IF ((from = NIL) OR (from.name = PCT.SelfName)) & ((to = NIL) OR (to.name = PCT.SelfName)) THEN RETURN TRUE END;
	res := FALSE;
	WHILE (from # NIL) & (to # NIL) DO
		res := TypeCompatible0(from.type, to.type);
		IF res THEN res := (from.ref = to.ref) END;
		IF ~res THEN RETURN FALSE END;
		from := from.nextPar; to := to.nextPar;
	END;
	RETURN res & ((from = NIL) OR (from.name = PCT.SelfName)) & ((to = NIL) OR (to.name = PCT.SelfName));
END SignatureCompatible;

PROCEDURE TypeCompatible0(from, to: PCT.Struct): BOOLEAN;
VAR res: BOOLEAN;
BEGIN
	res := FALSE;
	IF from = to THEN
		res := TRUE;
	ELSIF to IS PCT.Basic THEN
		IF (to = PCT.Byte) & ((from = PCT.Int8) OR (from = PCT.Char8)) THEN res := TRUE;
		ELSIF (to = PCT.Ptr) & PCT.IsPointer(from) THEN res := TRUE;
		ELSIF (from IS PCT.Basic) & (PCT.BasicTypeDistance(from(PCT.Basic), to(PCT.Basic)) >= 0) THEN res := TRUE;
		END;
	ELSIF (to IS PCT.Pointer) & (from IS PCT.Pointer) & TypeExtension(to, from) THEN res := TRUE;
	ELSE res := ArrayCompatible(from, to);
	END;
	RETURN res;
END TypeCompatible0;

	(** Const utilities: Constructors *)
	PROCEDURE NewValue*(pos: LONGINT; obj: PCT.Symbol): Expression;		(*expr, obj can be a fix*)
		VAR con: Const;
	BEGIN
		ASSERT(obj IS PCT.Value);
		NEW(con, pos, obj(PCT.Value).const); RETURN con
	END NewValue;
	
	PROCEDURE NewIntValue*(pos: LONGINT; i: LONGINT; type: PCT.Struct): Const;
		VAR  con: Const;
	BEGIN
		 NEW(con, pos, PCT.NewIntConst(i, type));  RETURN con
	END NewIntValue;
	
	PROCEDURE NewLongIntValue*(pos: LONGINT; i: HUGEINT): Const;
		VAR  con: Const;
	BEGIN
		 NEW(con, pos, PCT.NewInt64Const(i));  RETURN con
	END NewLongIntValue;
	
	PROCEDURE NewFloatValue*(pos: LONGINT; r: LONGREAL; type: PCT.Struct): Const;
		VAR con: Const;
	BEGIN  NEW(con, pos, PCT.NewFloatConst(r, type));  RETURN con
	END NewFloatValue;
	
	PROCEDURE NewStrValue*(pos: LONGINT; str: PCS.String): Const;
		VAR con: Const;
	BEGIN  NEW(con, pos, PCT.NewStringConst(str));  RETURN con
	END NewStrValue;
	
	PROCEDURE NewBoolValue*(pos: LONGINT; b: BOOLEAN): Const;
		VAR con: Const;
	BEGIN
		IF  b  THEN  NEW(con, pos, PCT.True)  ELSE  NEW(con, pos, PCT.False)  END;
		RETURN con
	END NewBoolValue;
	
	PROCEDURE NewSetValue*(pos: LONGINT; s: SET): Const;
		VAR con: Const;
	BEGIN  NEW(con, pos, PCT.NewSetConst(s)); RETURN con
	END NewSetValue;
	
	PROCEDURE NewNILValue*(pos: LONGINT): Const;
		VAR con: Const;
	BEGIN  con:=NewIntValue(pos, PCM.nilval, PCT.Int32);  con.type:= PCT.NilType;  RETURN con
	END NewNILValue;
	

	PROCEDURE NewConversion(pos: LONGINT; exp: Expression; type: PCT.Struct): Expression;	(*not exported, parser should not check types*)
		VAR  conv: Conversion;  str: PCS.String;  con: PCT.Const; l: LONGINT; ch: CHAR; r: REAL;  lr: LONGREAL;
	BEGIN
		IF IsInvalid(exp) THEN  exp := InvalidExpr
		ELSIF type IS PCT.Delegate THEN
			(*skip, no conversion*)
		ELSIF ~(type IS PCT.Basic) & (exp.type # PCT.Char8) THEN 
			(*skip, no conversion*)
			(* char -> chararray must be converted!*)
		ELSIF exp.type = type THEN 
		ELSIF exp IS Const THEN
			con := exp(Const).con;
			IF PCT.IsCardinalType(exp.type) THEN
				l := con.int;
				IF PCT.IsCardinalType(type) THEN  exp.type := type
				ELSIF PCT.IsCharType(type) THEN	exp := NewIntValue(pos, l, type)
				ELSIF type = PCT.Byte  THEN	exp := NewIntValue(pos, l, PCT.Byte); (*exp.type := PCT.Byte*)
				ELSIF type = PCT.Float32  THEN	exp := NewFloatValue(pos, l, PCT.Float32)
				ELSIF type = PCT.Float64  THEN	exp := NewFloatValue(pos, l, PCT.Float64)
				ELSE  PCM.Error(200, pos, ""); exp := InvalidExpr
				END
			ELSIF  PCT.IsCharType(exp.type)  THEN
				ch := CHR(con.int);
				IF PCT.IsCardinalType(type)  THEN
					exp := NewIntValue(pos, con.int, type)
				ELSIF type = PCT.Byte  THEN
					NEW(conv, pos, exp, type);  exp := conv
				ELSIF ((type IS PCT.Array) & (type(PCT.Array).base = exp.type))
						OR ((type = PCT.String) & (exp.type = PCT.Char8))
				THEN
					str[0] := ch; str[1] := 0X;
					exp := NewStrValue(exp.pos, str)
				ELSIF PCT.IsCharType(type) THEN
					exp.type := type
				ELSIF type # PCT.Char8 THEN PCM.Error(200, pos, "");  exp := InvalidExpr
				END
			ELSIF  exp.type = PCT.Float32  THEN
				r := SHORT(con.real);
				IF PCT.IsCardinalType(type)  THEN
					exp := NewIntValue(pos, ENTIER(r), type)
				ELSIF type = PCT.Float64  THEN	exp := NewFloatValue(pos, r, PCT.Float64)
				ELSE PCM.Error(200, pos, "");  exp := InvalidExpr
				END
			ELSIF  exp.type = PCT.Float64  THEN
				lr := con.real;
				IF type = PCT.Float32  THEN	exp := NewFloatValue(pos, SHORT(lr), PCT.Float32)
				ELSE  PCM.Error(1500, pos, "");  exp := InvalidExpr
				END
			ELSIF  exp.type = PCT.NilType THEN
				(*skip, no convertion from NIL to pointer*)
			ELSE  PCM.Error(1501, pos, ""); exp := InvalidExpr
			END
		ELSE
			NEW(conv, pos, exp, type); exp := conv
		END;
		RETURN exp
	END NewConversion;
	
	PROCEDURE Project(pos: LONGINT; exp: Expression; type: PCT.Struct): Expression;	(*not exported, parser should not check types*)
	VAR  buf: LONGINT;  proj: Projection;  con: PCT.Const; ptr: BOOLEAN;
	BEGIN
		IF IsInvalid(exp) THEN  RETURN InvalidExpr END;
		ptr := PCT.IsPointer(type);
		IF (exp IS Const) & ((type IS PCT.Basic) OR ptr) THEN
			(*extract to buffer*)
			con := exp(Const).con;
			IF PCT.IsCardinalType(exp.type) THEN  buf := con.int
			ELSIF exp.type = PCT.Char8  THEN  buf := con.int
			ELSIF exp.type = PCT.Float32  THEN  buf := SYSTEM.VAL(LONGINT, SHORT(con.real))
			ELSIF exp.type = PCT.Set  THEN  buf := SYSTEM.VAL(LONGINT, con.set)
			ELSIF exp.type = PCT.NilType  THEN  buf := PCM.nilval
			ELSE   PCM.Error(1502, pos, "");  exp := InvalidExpr
			END;
			
			(* create *)
			IF type = PCT.Int8 THEN	exp := NewIntValue(pos, SYSTEM.VAL(SHORTINT, buf), type)
			ELSIF type = PCT.Int16  THEN	 exp := NewIntValue(pos, SYSTEM.VAL(INTEGER, buf), type)
			ELSIF type = PCT.Int32  THEN	exp := NewIntValue(pos, buf, type)
			ELSIF type = PCT.Char8  THEN	exp := NewIntValue(pos, SYSTEM.VAL(SHORTINT, buf), PCT.Char8)
			ELSIF type = PCT.Float32  THEN	exp := NewFloatValue(pos, SYSTEM.VAL(REAL, buf), PCT.Float32)
			ELSIF type = PCT.Float64  THEN	exp := NewFloatValue(pos, SYSTEM.VAL(LONGREAL, buf), PCT.Float64)
			ELSIF type = PCT.Set  THEN	exp := NewSetValue(pos, SYSTEM.VAL(SET, buf))
			ELSIF ptr THEN  exp := NewIntValue(pos, buf, type)
			ELSE   PCM.Error(1503, pos, "");  exp := InvalidExpr
			END
		ELSE
			NEW(proj, pos, exp, type);  exp := proj
		END;
		RETURN exp
	END Project;

	
	PROCEDURE NewFuncCall*(pos: LONGINT; proc: Designator;  params: ExprList;  curlevel: SHORTINT): Expression;
		VAR fc: FunCall; type: PCT.Struct; fnr: LONGINT; first: Expression;
	BEGIN
		IF IsInvalid(proc) OR IsInvalid(params) THEN RETURN InvalidExpr END;
		IF (proc IS SProc) THEN
			IF params(BuiltInEl).NothingLeft() THEN
				fnr := proc(SProc).nr;
				first := params.first; type := first.type;
				CASE  fnr  OF
				|  maxfn:
						IF type=PCT.Char8 THEN RETURN NewIntValue(pos, ORD(MAX(CHAR)), PCT.Char8)
						ELSIF type=PCT.Char16 THEN RETURN NewIntValue(pos, 0FFFFH, PCT.Char16)
						ELSIF type=PCT.Char32 THEN RETURN NewIntValue(pos, 0FFFFFFFFH, PCT.Char32)
						ELSIF type=PCT.Int8 THEN RETURN NewIntValue(pos, MAX(SHORTINT), type)
						ELSIF type=PCT.Int16 THEN RETURN NewIntValue(pos, MAX(INTEGER), type)
						ELSIF type=PCT.Int32 THEN RETURN NewIntValue(pos, MAX(LONGINT), type)
(* > bootstrap 1 *)
						ELSIF type=PCT.Int64 THEN RETURN NewLongIntValue(pos, 7FFFFFFFFFFFFFFFH)
(* < bootstrap 1 *)
						ELSIF type=PCT.Float32 THEN RETURN NewFloatValue(pos, MAX(REAL), PCT.Float32)
						ELSIF type=PCT.Float64 THEN RETURN NewFloatValue(pos, MAX(LONGREAL), PCT.Float64)
						ELSIF type=PCT.Set THEN RETURN NewIntValue(pos, MAX(SET), PCT.Int8)
						ELSE  PCM.Error(64, first.pos, "");  RETURN InvalidExpr  END
				|  minfn:
						IF type=PCT.Char8 THEN RETURN NewIntValue(pos, ORD(MIN(CHAR)), PCT.Char8)
						ELSIF type=PCT.Char16 THEN RETURN NewIntValue(pos, 0H, PCT.Char16)
						ELSIF type=PCT.Char32 THEN RETURN NewIntValue(pos, 0H, PCT.Char32)
						ELSIF type=PCT.Int8 THEN RETURN NewIntValue(pos, MIN(SHORTINT), type)
						ELSIF type=PCT.Int16 THEN RETURN NewIntValue(pos, MIN(INTEGER), type)
						ELSIF type=PCT.Int32 THEN RETURN NewIntValue(pos, MIN(LONGINT), type)
(* > bootstrap 1 *)
						ELSIF type=PCT.Int64 THEN RETURN NewLongIntValue(pos, 8000000000000000H)
(* < bootstrap 1 *)
						ELSIF type=PCT.Float32 THEN RETURN NewFloatValue(pos, MIN(REAL), PCT.Float32)
						ELSIF type=PCT.Float64 THEN RETURN NewFloatValue(pos, MIN(LONGREAL), PCT.Float64)
						ELSIF type=PCT.Set THEN RETURN NewIntValue(pos, MIN(SET), PCT.Int8)
						ELSE  PCM.Error(64, first.pos, "");  RETURN InvalidExpr  END
				|  sizefn .. get32fn,  PCC.absfn .. PCC.oddfn:
						RETURN  NewMOp(pos, NIL, fnr, params.first)
				|  ordfn .. shortfn, valfn:
						RETURN params.first
				|  lenfn, PCC.bitfn, PCC.ashfn .. PCC.rotfn:
						RETURN  NewDOp(pos, fnr, params.first, params.first.link)
				ELSE  PCM.Error(200, pos, "")
				END
			ELSE  PCM.Error(65, proc.pos, "")  END
		ELSIF proc IS AnyProc THEN
			WITH proc: AnyProc DO
				proc.Resolve(params, NIL);
				IF proc.proc # NIL THEN
					NEW(fc, pos, proc, params, curlevel);
					RETURN fc
				END
			END
		ELSIF proc.type IS PCT.Delegate THEN
			NEW(fc, pos, proc, params, curlevel);
			RETURN fc
		ELSE  PCM.Error(121, proc.pos, "")
		END;
		RETURN InvalidExpr
	END NewFuncCall;
	
	
	PROCEDURE NewExprList*(pos: LONGINT; d: Designator): ExprList;
		VAR el: ExprList; bel: BuiltInEl; fnr: LONGINT;
	BEGIN
		IF d IS SProc THEN
			fnr:=d(SProc).nr; NEW(bel, pos, PCT.NoType, fnr);
			el := bel
		ELSIF (d IS AnyProc) THEN
			NEW(el, pos, d(AnyProc).o.type)
		ELSIF (d.type IS PCT.Delegate) THEN
			NEW(el, pos, d.type(PCT.Delegate).return);
			el.params := d.type(PCT.Delegate).scope.firstPar
		ELSIF IsInvalid(d) THEN
			el := InvalidEL
		ELSE
			PCM.Error(121, pos, "");
			el := InvalidEL
		END;
		RETURN el
	END NewExprList;
	
	PROCEDURE NewMOp*(pos: LONGINT; scope: PCT.Scope; op: Operator; opd: Expression): Expression;
		VAR	mop: MOp;
			i: LONGINT; r: REAL; lr: LONGREAL; restyp: PCT.Struct; const: BOOLEAN;  type: PCT.Struct; c: PCT.Const;
	BEGIN
		IF IsInvalid(opd) THEN  RETURN InvalidExpr  END;
		type := opd.type;
		(*check if expression is legal*)
		const := opd IS Const;
		IF const THEN c := opd(Const).con END;
		IF (op = adrfn) THEN
			restyp := PCT.Int32
		ELSIF (op = sizefn) THEN
			type := opd.type;
			IF type.size # NIL THEN
				RETURN  NewIntValue(pos, PCC.GetStaticSize(type), PCT.Int16)
			ELSE
				PCM.Error(200, pos, "");  RETURN InvalidExpr;
			END;
		ELSIF (op = typecodefn) THEN
			restyp := PCT.Int32
		ELSIF (op = get8fn) THEN
			restyp := PCT.Int8
		ELSIF (op = get16fn) THEN
			restyp := PCT.Int16
		ELSIF (op = get32fn) THEN
			restyp := PCT.Int32
		ELSIF op = PCC.setfn THEN
			IF ~PCT.IsCardinalType(type) THEN PCM.Error(111, pos, ""); RETURN InvalidExpr
			ELSIF const THEN
				i := c.int;
				IF (i < 0) OR (i > PCM.MaxSet) THEN  PCM.Error(202, pos, "");  RETURN InvalidExpr  END;
				RETURN  NewSetValue(pos, {i})
			ELSE  restyp := PCT.Set
			END
		ELSIF PCT.IsCardinalType(type) THEN
			IF op = PCS.plus THEN	RETURN opd
			ELSIF const THEN
				i := c.int;
				IF op=PCS.minus THEN RETURN NewIntValue(pos, -i, PCT.GetIntType(-i))
				ELSIF op=PCC.absfn THEN RETURN NewIntValue(pos, ABS(i), PCT.GetIntType(ABS(i)))
				ELSIF op=chrfn THEN RETURN NewIntValue(pos, i, PCT.Char8)
				ELSIF op=PCC.oddfn THEN RETURN NewBoolValue(pos, ODD(i))
				ELSE PCM.Error(111, pos, ""); RETURN InvalidExpr
				END
			ELSIF (op=PCS.minus)OR(op=PCC.absfn) THEN
				restyp := type
			ELSIF (op=chrfn) THEN
				restyp := PCT.Char8
			ELSIF (op=PCC.oddfn) THEN
				restyp := PCT.Bool
			ELSE
				PCM.Error(111, pos, ""); RETURN InvalidExpr
			END
		ELSIF (type = PCT.Float32) OR (type = PCT.Float64) THEN
			IF op = PCS.plus THEN	RETURN opd
			ELSIF const THEN
				lr := c.real;
				IF op=PCS.minus THEN  RETURN NewFloatValue(pos, -lr, type)
				ELSIF op=PCC.absfn THEN  RETURN NewFloatValue(pos, ABS(lr), type)
				ELSE PCM.Error(111, pos, ""); RETURN InvalidExpr
				END
			ELSIF (op=PCS.minus)OR(op=PCC.absfn) THEN
				restyp := type
			ELSE
				PCM.Error(111, pos, ""); RETURN InvalidExpr
			END
		ELSIF type = PCT.Bool THEN
			IF const THEN
				IF op=PCS.not THEN  RETURN NewBoolValue(pos, ~c.bool)
				ELSE PCM.Error(111, pos, ""); RETURN InvalidExpr
				END
			ELSIF (op=PCS.not) THEN
				restyp := type
			ELSE
				PCM.Error(111, pos, ""); RETURN InvalidExpr
			END
		ELSIF type = PCT.Char8 THEN
			IF const THEN
				IF op=PCC.capfn THEN  RETURN NewIntValue(pos, ORD(CAP(CHR(c.int))), PCT.Char8)
				ELSE PCM.Error(111, pos, ""); RETURN InvalidExpr
				END
			ELSIF (op=PCC.capfn) THEN
				restyp := type
			ELSE
				PCM.Error(111, pos, ""); RETURN InvalidExpr
			END
		ELSIF type = PCT.Set THEN
			IF op=PCS.minus THEN
				IF const THEN  RETURN NewSetValue(pos, -c.set)
				ELSE restyp := PCT.Set
				END
			ELSE PCM.Error(111, pos, ""); RETURN InvalidExpr
			END
		ELSE
			PCM.Error(111, pos, ""); RETURN InvalidExpr
		END;
		NEW(mop, pos, op, restyp, opd);  RETURN mop
	END NewMOp;
	
	PROCEDURE FoldConstASH(pos: LONGINT;  l, r: PCT.Const): Expression;
	VAR  shift: LONGINT;  exp: Expression;
	BEGIN
		shift := r.int;
		IF PCT.IsCardinalType(l.type) THEN
			exp := NewIntValue(pos, ASH(l.int, shift), PCT.Int32);
		ELSE
			PCM.Error(200, pos, "");
			exp := InvalidExpr
		END;
		RETURN exp
	END FoldConstASH;
	
	PROCEDURE FoldConstROT(pos: LONGINT;  l, r: PCT.Const): Expression;
	VAR  shift: LONGINT; type: PCT.Struct;
	BEGIN
		shift := r.int; type := l.type;
		IF (type = PCT.Int8) OR (type = PCT.Char8) THEN
			RETURN  NewIntValue(pos, SYSTEM.ROT(SHORT(SHORT(l.int)), shift), type)
		ELSIF (type = PCT.Int16) OR (type = PCT.Char16) THEN
			RETURN  NewIntValue(pos, SYSTEM.ROT(SHORT(l.int), shift), type)
		ELSIF (type = PCT.Int32) OR (type = PCT.Char32) THEN
			RETURN  NewIntValue(pos, SYSTEM.ROT(l.int, shift), type)
		ELSIF type = PCT.Set THEN
			RETURN  NewSetValue(pos, SYSTEM.ROT(l.set, shift))
		ELSE
			PCM.Error(200, pos, ""); RETURN InvalidExpr
		END
	END FoldConstROT;
	
	PROCEDURE FoldConstLSH(pos: LONGINT;  l, r: PCT.Const): Expression;
	VAR  shift: LONGINT; type: PCT.Struct;
	BEGIN
		shift := r.int; type := l.type;
		IF (type = PCT.Int8) OR (type = PCT.Char8) THEN
			RETURN  NewIntValue(pos, SYSTEM.LSH(SHORT(SHORT(l.int)), shift), type)
		ELSIF (type = PCT.Int16) OR (type = PCT.Char16) THEN
			RETURN  NewIntValue(pos, SYSTEM.LSH(SHORT(l.int), shift), type)
		ELSIF (type = PCT.Int32) OR (type = PCT.Char32) THEN
			RETURN  NewIntValue(pos, SYSTEM.LSH(l.int, shift), type)
		ELSIF type = PCT.Set THEN
			RETURN  NewSetValue(pos, SYSTEM.LSH(l.set, shift))
		ELSE
			PCM.Error(200, pos, ""); RETURN InvalidExpr
		END
	END FoldConstLSH;
	
	PROCEDURE ConvertOperands(VAR lo, ro: Expression);
	VAR	lt, rt: PCT.Struct;  ll, rl: LONGINT;
	
		PROCEDURE FindLevel(t: PCT.Struct): LONGINT;
		VAR	i: LONGINT;
		BEGIN
			i := 5;
			WHILE (i >= 0) & (PCT.NumericType[i] # t) DO DEC(i) END;
			RETURN i
		END FindLevel;
		
		PROCEDURE FindCharLevel(t: PCT.Struct): LONGINT;
		VAR	i: LONGINT;
		BEGIN
			i := LEN(PCT.CharType)-1;
			WHILE (i >= 0) & (PCT.CharType[i] # t) DO DEC(i) END;
			RETURN i
		END FindCharLevel;
		
		PROCEDURE HandleSelf(VAR self, other: Expression);
		BEGIN
			IF self IS Var THEN
				IF self.type(PCT.Record).ptr # NIL THEN
					self := MakeSelf(self(Var))
				END
			END;
		END HandleSelf;
		
	BEGIN
		lt := lo.type;  rt := ro.type;
		IF PCT.IsCharType(lt) & PCT.IsCharType(rt) THEN
			ll := FindCharLevel(lt);
			rl := FindCharLevel(rt);
			ASSERT((ll >= 0) & (rl >= 0));
			IF ll > rl THEN ro := NewConversion(ro.pos, ro, PCT.CharType[ll])
			ELSIF ll < rl THEN lo := NewConversion(lo.pos, lo, PCT.CharType[rl])
			END
		ELSIF (lt IS PCT.Basic) & (rt IS PCT.Basic) THEN	(*only basic types supported for build-in ops*)
			ll := FindLevel(lt);  rl := FindLevel(rt);
			IF (ll < 0) OR (rl < 0) THEN RETURN END;
			IF ll > rl THEN	ro := NewConversion(ro.pos, ro, PCT.NumericType[ll]);
			ELSIF ll < rl THEN	lo := NewConversion(lo.pos, lo, PCT.NumericType[rl])
			END
		ELSIF PCT.IsPointer(lt) & (rt IS PCT.Record) THEN
			HandleSelf(ro, lo)
		ELSIF PCT.IsPointer(rt) & (lt IS PCT.Record) THEN
			HandleSelf(lo, ro)
		ELSIF PCT.IsPointer(lt) & (lo IS Designator) & (rt = PCT.String) THEN
			lo := NewDeref(lo.pos, lo(Designator))
		ELSIF PCT.IsPointer(rt) & (ro IS Designator) & (lt = PCT.String) THEN
			ro := NewDeref(ro.pos, ro(Designator))
		END;
	END ConvertOperands;
	
	PROCEDURE NewDOp*(pos: LONGINT;  op: Operator; lopd, ropd: Expression): Expression;
		VAR	dop: DOp;  const: BOOLEAN;  typ, restyp: PCT.Struct;
			lc, rc: PCT.Const;
			i1, i2: LONGINT; r1, r2: REAL; l1, l2: LONGREAL; c1, c2: CHAR; b1, b2: BOOLEAN; s1, s2: SET;
			str: PCS.String; res: Expression;
	BEGIN
		IF IsInvalid(lopd) OR IsInvalid(ropd) THEN  RETURN InvalidExpr  END;
		(*search for operator*)
		const := FALSE;
		IF (lopd IS Const) & (ropd IS Const) THEN
			const := TRUE; lc := lopd(Const).con; rc := ropd(Const).con
		END;
		IF (lopd IS AnyProc) OR (lopd IS Type) THEN
			PCM.Error(126, lopd.pos, ""); RETURN InvalidExpr
		ELSIF ropd IS AnyProc THEN
			PCM.Error(126, ropd.pos, ""); RETURN InvalidExpr
		ELSIF op = PCS.is THEN
			restyp:=PCT.Bool;
			IF  ~TypeExtension(lopd.type, ropd.type) THEN
				PCM.Error(85, pos, "");  RETURN InvalidExpr
			ELSIF ~(ropd IS Type) THEN
				PCM.Error(52, pos, "");  RETURN InvalidExpr
			END
		ELSIF ropd IS Type THEN
			PCM.Error(126, ropd.pos, ""); RETURN InvalidExpr
		ELSIF op = PCS.in THEN
			IF PCT.IsCardinalType(lopd.type) & (ropd.type=PCT.Set) THEN
				IF const THEN RETURN
					NewBoolValue(pos, lc.int IN rc.set)
				ELSE
					IF lopd.type # PCT.Int32 THEN lopd := NewConversion(lopd.pos, lopd, PCT.Int32) END;
					restyp:=PCT.Bool
				END
			ELSE  PCM.Error(111, pos, ""); RETURN InvalidExpr  END
		ELSIF op = lenfn THEN
			IF (ropd IS Const) & PCT.IsCardinalType(ropd.type) THEN
				i1 := ropd(Const).con.int;
				typ := lopd.type;
				IF (typ IS PCT.Pointer) & (lopd IS Designator) THEN  lopd := NewDeref(pos, lopd(Designator));  typ := lopd.type  END;
				IF ~(typ IS PCT.Array) THEN  PCM.Error(131, lopd.pos, ""); RETURN InvalidExpr  END;
				WHILE i1 > 0 DO
					typ := typ(PCT.Array).base;
					IF ~(typ IS PCT.Array) THEN  PCM.Error(131, lopd.pos, ""); RETURN InvalidExpr  END;
					DEC(i1)
				END;
				IF typ(PCT.Array).mode = PCT.static THEN
					i1 := typ(PCT.Array).len;
					RETURN NewIntValue(pos, i1, PCT.GetIntType(i1))	(* should be Int32, but this would break code in the system *)
				ELSE
					restyp := PCT.Int32
				END
			ELSE
				PCM.Error(50, lopd.pos, ""); RETURN InvalidExpr
			END
		ELSIF (op = PCC.bitfn) THEN
			IF ~PCT.IsCardinalType(lopd.type) THEN  PCM.Error(115, lopd.pos, "");  RETURN InvalidExpr
			ELSIF ~PCT.IsCardinalType(ropd.type) THEN  PCM.Error(115, ropd.pos, "");  RETURN InvalidExpr
			END;
			restyp := PCT.Bool
		ELSIF (op = PCC.ashfn) THEN
			IF ~PCT.IsCardinalType(lopd.type) THEN  PCM.Error(113, lopd.pos, ""); RETURN InvalidExpr
			ELSIF ~PCT.IsCardinalType(ropd.type) THEN  PCM.Error(113, ropd.pos, ""); RETURN InvalidExpr
			ELSIF const THEN  RETURN  FoldConstASH(pos, lc, rc)
			ELSIF (lopd.type = PCT.Int8) OR (lopd.type = PCT.Int16) THEN  lopd := NewConversion(lopd.pos, lopd, PCT.Int32)
(*
			ELSIF lopd.type # PCT.Int32 THEN  lopd := NewConversion(lopd.pos, lopd, PCT.Int32)
*)
			END;
			restyp := lopd.type
(*
			restyp := PCT.Int32
*)
		ELSIF (op = PCC.lshfn) OR (op = PCC.rotfn) THEN
			IF ~PCT.IsCardinalType(lopd.type) & ~PCT.IsCharType(lopd.type) & (lopd.type # PCT.Byte) & (lopd.type # PCT.Set) THEN
				PCM.Error(113, lopd.pos, ""); RETURN InvalidExpr
			ELSIF ~PCT.IsCardinalType(ropd.type) THEN  PCM.Error(113, ropd.pos, ""); RETURN InvalidExpr
			ELSIF const THEN
				IF op = PCC.rotfn THEN  RETURN FoldConstROT(pos, lc, rc)
				ELSIF op = PCC.lshfn THEN  RETURN FoldConstLSH(pos, lc, rc)
				END
			END;
			restyp := lopd.type
		ELSIF (lopd.type IS PCT.Delegate) OR (ropd.type IS PCT.Delegate) THEN
			IF lopd.type IS PCT.Delegate THEN
				IF ~IsVariable(lopd) THEN  PCM.Error(56, lopd.pos, ""); RETURN InvalidExpr
				ELSIF ropd.type = PCT.NilType THEN	(*ok*)
				ELSIF (ropd.type = lopd.type) & IsVariable(ropd) THEN	(*ok*)
				ELSE
					PCM.Error(100, ropd.pos, ""); RETURN InvalidExpr
				END
			ELSE (*b2*)
				IF ~IsVariable(ropd) THEN  PCM.Error(56, ropd.pos, ""); RETURN InvalidExpr
				ELSIF (lopd.type # PCT.NilType) & (lopd # ropd) THEN PCM.Error(100, lopd.pos, ""); RETURN InvalidExpr
				END
			END;
			IF (op = PCS.eql) OR (op = PCS.neq) THEN  restyp := PCT.Bool
			ELSE  PCM.Error(111, pos, ""); RETURN InvalidExpr
			END
		ELSIF PCT.IsPointer(lopd.type) OR PCT.IsPointer(ropd.type) THEN
			ConvertOperands(lopd, ropd);
			IF ~PCT.IsPointer(lopd.type) OR ~PCT.IsPointer(ropd.type) THEN PCM.Error((*111*)137, pos, ""); RETURN InvalidExpr
			ELSIF (op # PCS.eql) & (op # PCS.neq) THEN  PCM.Error((*111*)137, pos, ""); RETURN InvalidExpr
			ELSE restyp := PCT.Bool
			END
(*
			ELSIF (lopd.type = PCT.NilType) OR (ropd.type = PCT.NilType)  THEN  restyp := PCT.Bool
			ELSIF TypeExtension(lopd.type, ropd.type) OR TypeExtension(ropd.type, lopd.type) THEN  restyp := PCT.Bool
			ELSE  PCM.Error(111, pos); RETURN InvalidExpr  END
*)
		ELSIF IsCharArray(lopd) OR IsCharArray(ropd) THEN		(* string ops*)
			IF (ropd IS Const) & (ropd.type = PCT.Char8) THEN
				str[0] := CHR(ropd(Const).con.int); str[1]:=0X;
				ropd := NewStrValue(ropd.pos, str)
			ELSIF (lopd IS Const) & (lopd.type = PCT.Char8) THEN
				str[0] := CHR(lopd(Const).con.int); str[1]:=0X;
				lopd := NewStrValue(lopd.pos, str)
			ELSIF IsCharArray(lopd) & IsCharArray(ropd) THEN	(*ok*)
			ELSE
				PCM.Error(111, pos, ""); RETURN InvalidExpr
			END;
			IF (op = PCS.eql) OR (op = PCS.neq) OR (op = PCS.lss) OR (op = PCS.leq) OR (op = PCS.gtr) OR (op = PCS.geq) THEN
				restyp := PCT.Bool
			ELSE
				PCM.Error(111, pos, ""); RETURN InvalidExpr
			END
		ELSE	(* common case numeric ops,  params must have same type*)
			IF lopd.type # ropd.type THEN
				ConvertOperands(lopd, ropd);		(*make the operands of the same type*)
				IF const THEN lc := lopd(Const).con; rc := ropd(Const).con END;
				IF lopd.type # ropd.type THEN  PCM.Error(111, pos, ""); RETURN InvalidExpr  END;
			END;
			IF PCT.IsCardinalType(lopd.type) THEN
				IF (lopd.type = PCT.Int64) & ((op = PCS.div) OR (op = PCS.mod)) THEN
					PCM.Error(111, pos, "64-bit DIV/MOD not implemented yet"); RETURN InvalidExpr
				ELSIF op=PCS.comma THEN
					lopd.link := ropd;  RETURN lopd
				ELSIF (lopd.type # PCT.Int64) & const THEN
					i1 := lc.int;  i2 := rc.int;
					CASE op OF
					|	PCS.plus:	i1 := i1 + i2; res := NewIntValue(pos, i1, PCT.GetIntType(i1))
					|	PCS.minus:	i1 := i1 - i2; res := NewIntValue(pos, i1, PCT.GetIntType(i1))
					|	PCS.times:	i1 := i1 * i2; res := NewIntValue(pos, i1, PCT.GetIntType(i1))
					|	PCS.div:	i1 := i1 DIV i2; res := NewIntValue(pos, i1, PCT.GetIntType(i1))
					|	PCS.mod:	i1 := i1 MOD i2; res := NewIntValue(pos, i1, PCT.GetIntType(i1))
					|	PCS.slash:	res := NewFloatValue(pos, i1 / i2, PCT.Float32)
					|	PCS.eql:	res := NewBoolValue(pos, i1 = i2)
					|	PCS.neq:	res := NewBoolValue(pos, i1 # i2)
					|	PCS.lss:	res := NewBoolValue(pos, i1 < i2)
					|	PCS.leq:	res := NewBoolValue(pos, i1 <= i2)
					|	PCS.gtr:	res := NewBoolValue(pos, i1 > i2)
					|	PCS.geq:	res := NewBoolValue(pos, i1 >= i2)
					|	PCC.setfn:	res := NewSetValue(pos, {i1 .. i2})
					ELSE	PCM.Error(111, pos, ""); res := InvalidExpr
					END;
					RETURN res
				ELSIF (op=PCS.plus)OR(op=PCS.minus)OR(op=PCS.times)OR(op=PCS.div)OR(op=PCS.mod) THEN
					restyp := lopd.type
				ELSIF (op=PCS.slash) THEN
					lopd := NewConversion(lopd.pos, lopd, PCT.Float32);
					ropd := NewConversion(ropd.pos, ropd, PCT.Float32);
					restyp := PCT.Float32
				ELSIF (op=PCS.eql)OR(op=PCS.neq)OR(op=PCS.lss)OR(op=PCS.leq)OR(op=PCS.gtr)OR(op=PCS.geq) THEN
					restyp := PCT.Bool
				ELSIF (op=PCC.setfn) THEN
					restyp := PCT.Set
				ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
				END
			ELSIF (lopd.type = PCT.Float32) OR (lopd.type = PCT.Float64) THEN	(* perform const folding with highest precision available *)
				IF const THEN
					l1 := lc.real;  l2 := rc.real;
					CASE op OF
					|	PCS.plus:	RETURN NewFloatValue(pos, l1 + l2, lopd.type)
					|	PCS.minus:	RETURN NewFloatValue(pos, l1 - l2, lopd.type)
					|	PCS.times:	RETURN NewFloatValue(pos, l1 * l2, lopd.type)
					|	PCS.slash:	RETURN NewFloatValue(pos, l1 / l2, lopd.type)
					|	PCS.eql:	RETURN NewBoolValue(pos, l1 = l2)
					|	PCS.neq:	RETURN NewBoolValue(pos, l1 # l2)
					|	PCS.lss:	RETURN NewBoolValue(pos, l1 < l2)
					|	PCS.leq:	RETURN NewBoolValue(pos, l1 <= l2)
					|	PCS.gtr:	RETURN NewBoolValue(pos, l1 > l2)
					|	PCS.geq:	RETURN NewBoolValue(pos, l1 >= l2)
					ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
					END
				ELSIF (op=PCS.plus)OR(op=PCS.minus)OR(op=PCS.times)OR(op=PCS.slash) THEN
					restyp := lopd.type
				ELSIF (op=PCS.eql)OR(op=PCS.neq)OR(op=PCS.lss)OR(op=PCS.leq)OR(op=PCS.gtr)OR(op=PCS.geq) THEN
					restyp := PCT.Bool
				ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
				END
			ELSIF PCT.IsCharType(lopd.type) THEN
				IF const THEN
					i1 := lc.int;  i2 := rc.int;
					IF (i1 < 0) OR (i2 < 0) THEN
						DEC(i1, 80000000H);
						DEC(i2, 80000000H)
					END;
					CASE op OF
					|	PCS.comma:	lopd.link := ropd;  RETURN lopd			(*only for constants*)
					|	PCS.eql:	res := NewBoolValue(pos, i1 = i2)
					|	PCS.neq:	res := NewBoolValue(pos, i1 # i2)
					|	PCS.lss:	res := NewBoolValue(pos, i1 < i2)
					|	PCS.leq:	res := NewBoolValue(pos, i1 <= i2)
					|	PCS.gtr:	res := NewBoolValue(pos, i1 > i2)
					|	PCS.geq:	res := NewBoolValue(pos, i1 >= i2)
					ELSE	PCM.Error(111, pos, ""); res := InvalidExpr
					END;
					RETURN res
(*
					c1 := CHR(lc.int);  c2 := CHR(rc.int);
					CASE op OF
					|	PCS.comma:	lopd.link := ropd;  RETURN lopd			(*only for constants*)
					|	PCS.eql:	RETURN NewBoolValue(pos, c1 = c2)
					|	PCS.neq:	RETURN NewBoolValue(pos, c1 # c2)
					|	PCS.lss:	RETURN NewBoolValue(pos, c1 < c2)
					|	PCS.leq:	RETURN NewBoolValue(pos, c1 <= c2)
					|	PCS.gtr:	RETURN NewBoolValue(pos, c1 > c2)
					|	PCS.geq:	RETURN NewBoolValue(pos, c1 >= c2)
					ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
					END
*)
				ELSIF (op=PCS.eql)OR(op=PCS.neq)OR(op=PCS.lss)OR(op=PCS.leq)OR(op=PCS.gtr)OR(op=PCS.geq) THEN
					restyp := PCT.Bool
				ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
				END
			ELSIF lopd.type = PCT.Set THEN
				IF const THEN
					s1 := lc.set;  s2 := rc.set;
					CASE op OF
					|	PCS.plus:	RETURN NewSetValue(pos, s1 + s2)
					|	PCS.minus:	RETURN NewSetValue(pos, s1 - s2)
					|	PCS.times:	RETURN NewSetValue(pos, s1 * s2)
					|	PCS.slash:	RETURN NewSetValue(pos, s1 / s2)
					|	PCS.eql:	RETURN NewBoolValue(pos, s1 = s2)
					|	PCS.neq:	RETURN NewBoolValue(pos, s1 # s2)
					ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
					END
				ELSIF (op=PCS.plus)OR(op=PCS.minus)OR(op=PCS.times)OR(op=PCS.slash) THEN
					restyp := lopd.type
				ELSIF (op=PCS.eql)OR(op=PCS.neq) THEN
					restyp := PCT.Bool
				ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
				END
			ELSIF lopd.type = PCT.Bool THEN
				IF const THEN
					b1 := lc.bool;  b2 := rc.bool;
					CASE op OF
					|	PCS.eql:	RETURN NewBoolValue(pos, b1 = b2)
					|	PCS.neq:	RETURN NewBoolValue(pos, b1 # b2)
					|	PCS.and:	RETURN NewBoolValue(pos, b1 & b2)
					|	PCS.or:	RETURN NewBoolValue(pos, b1 OR b2)
					ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
					END
				ELSIF lopd IS Const THEN
					b1 := lopd(Const).con.bool;
					CASE op OF
					|	PCS.eql:	IF b1 THEN  RETURN ropd
											ELSE  RETURN NewMOp(pos, NIL, PCS.not, ropd)  END
					|	PCS.neq:	IF b1 THEN  RETURN NewMOp(pos, NIL, PCS.not, ropd)
											ELSE  RETURN ropd  END
					|	PCS.and:	IF b1 THEN  RETURN ropd  ELSE  RETURN NewBoolValue(pos, FALSE)  END
					|	PCS.or:	IF b1 THEN  RETURN NewBoolValue(pos, TRUE)  ELSE  RETURN ropd  END 
					ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
					END
				ELSIF ropd IS Const THEN
					b2 := ropd(Const).con.bool;
					CASE op OF
					|	PCS.eql:	IF b2 THEN  RETURN lopd  ELSE  restyp := PCT.Bool  END
					|	PCS.neq:	IF b2 THEN  restyp := PCT.Bool  ELSE  RETURN lopd  END
					|	PCS.and:	restyp := PCT.Bool
					|	PCS.or:	IF b2 THEN  RETURN lopd  ELSE  restyp := PCT.Bool  END 
					ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
					END
				ELSIF (op=PCS.eql)OR(op=PCS.neq)OR(op=PCS.and)OR(op=PCS.or) THEN
					restyp := PCT.Bool
				ELSE	PCM.Error(111, pos, ""); RETURN InvalidExpr
				END
			ELSE
				IF PCT.IsRecord(lopd.type) OR PCT.IsRecord(ropd.type) THEN
					PCM.Error(137, pos, "");
				ELSE
					PCM.Error(111, pos, "");
				END;
				RETURN InvalidExpr
			END;
		END;	(* common case, same params *)
		NEW(dop, pos, op, restyp, lopd, ropd);  RETURN dop
	END NewDOp;
	
	PROCEDURE MakeTemp(code: PCC.Code; suppress: BOOLEAN; VAR p: Expression);
	VAR  temp: Temp;  i: PCC.Item;
	BEGIN
		IF ~suppress THEN
			p.Emit(code, i);
			PCC.Param(code, i, p.type, FALSE);
			NEW(temp, -1, p.type);
			p := temp;
		END
	END MakeTemp;
	
	PROCEDURE MakeNode*(pos: LONGINT; scope: PCT.Scope; obj: PCT.Symbol): Designator;
	VAR	v: Var; s: SProc; t: Type; self: Designator; selfo: PCT.Symbol;  level: SHORTINT; d: Designator; ss: PCT.Scope;
		ap: AnyProc;
	BEGIN
		ASSERT((scope IS PCT.ProcScope) OR (scope IS PCT.ModScope));
		d := InvalidDesig;
		IF (obj = unknownObj) OR (obj.type = PCT.UndefType) THEN
			(*default*)
		ELSIF obj IS PCT.Type THEN
			NEW(t, pos, obj(PCT.Type)); d := t
		ELSIF obj IS PCT.Proc THEN
			ss := obj(PCT.Proc).scope.module.scope;
			IF (ss # scope.module.scope) &  ~(obj IS PCT.Method) THEN scope := ss END;
			NEW(ap, pos, scope, obj, NIL); d := ap
		ELSIF (obj IS PCT.Field) THEN	(*meth before proc, field before variable*)
			selfo := PCT.Find(scope, scope, PCT.SelfName, PCT.procdeclared, TRUE);
			ASSERT(selfo # NIL, 1504);
			self := MakeNode(pos, scope, selfo);
			d :=  NewField0(scope, self, obj, pos);
		ELSIF obj IS PCT.Alias THEN
			self := MakeNode(pos, scope, obj(PCT.Alias).obj);
			self.type := obj.type;  d := self
		ELSIF (obj IS PCT.Variable) THEN
			IF scope IS PCT.ProcScope THEN  level := scope(PCT.ProcScope).ownerO.level  END;
			NEW(v, pos, obj(PCT.Variable), level, (obj.inScope.module # scope.module) & ({PCT.PublicW, PCT.ProtectedW} * obj.vis = {}));
(*
			NEW(v, pos, obj(PCT.Variable), level, scope.imported & (obj.vis = PCT.readonly));
*)
			d := v
		ELSIF obj IS PCT.Value THEN
			PCM.Error(56, pos, "")
		ELSIF (obj.info # NIL) & (obj.info IS SProcInfo) THEN
			NEW(s, pos, obj.info(SProcInfo).nr); d := s
		ELSE
			PCM.Error(200, pos, "")
		END;
		RETURN d
	END MakeNode;
	
	PROCEDURE NewDeref*(pos: LONGINT; ptr: Designator): Designator;
		VAR deref: Deref; (*mth: Method;*)
	BEGIN
		IF IsInvalid(ptr) THEN RETURN InvalidDesig END;
(*
		Out.String("Deref @ "); Out.Int(pos, 0); 
		IF ptr IS AnyProc THEN
			Out.String(" --> call "); Out.Ln; 
			ptr(AnyProc).supercall := TRUE; RETURN ptr
		ELSIF ptr.type IS PCT.Pointer THEN
			Out.String(" --> ptr "); Out.Ln; 
			NEW(deref, pos, ptr, ptr.type(PCT.Pointer).base); RETURN deref
*)
		IF ptr.type IS PCT.Pointer THEN
			NEW(deref, pos, ptr, ptr.type(PCT.Pointer).base); RETURN deref
		ELSIF ptr IS AnyProc THEN
			ptr(AnyProc).supercall := TRUE; RETURN ptr
(*
		ELSIF ptr IS Method THEN
			mth := ptr(Method);
			IF mth.method.super # NIL THEN
				mth.supercall := TRUE;  RETURN ptr
			ELSE
				PCM.Error(74, pos, "");
				RETURN ptr	(*error handling*)
			END
*)
		END;
		PCM.Error(200, pos, "");
		RETURN InvalidDesig
	END NewDeref;
	
	PROCEDURE NewField0(scope: PCT.Scope; rec: Designator; fld: PCT.Symbol; pos: LONGINT): Designator;
		VAR	field: Field;  rectyp: PCT.Struct;  res: Designator; ro: BOOLEAN;
	BEGIN
		IF IsInvalid(rec) THEN RETURN InvalidDesig END;
		res := InvalidDesig;
		IF rec.type IS PCT.Pointer THEN  rectyp := rec.type(PCT.Pointer).base  ELSE rectyp := rec.type END;
		IF rectyp IS PCT.Record THEN
			WITH rectyp: PCT.Record DO
				IF fld = NIL THEN PCM.Error(83, pos, "")
				ELSIF fld.type = PCT.UndefType THEN res := InvalidDesig
				ELSIF fld IS PCT.Field THEN
					IF rectyp # rec.type THEN  rec := NewDeref(rec.pos, rec)  END;		(*auto deref*)
					ro := (scope.module # rectyp.scope.module) & ({PCT.PublicW, PCT.ProtectedW} * fld.vis = {});
					NEW(field, pos, rec, fld(PCT.Field), ro); res := field
				ELSE PCM.Error(83, pos, "")
				END
			END
		ELSE
			PCM.Error(53, rec.pos, "")
		END;
		RETURN res
	END NewField0;
	
	PROCEDURE NewField*(current: PCT.Scope; rec: Designator; name: PCS.Name; pos: LONGINT): Designator;
		VAR	fld: PCT.Symbol;  field: Field;  method: AnyProc;  rectyp: PCT.Struct;  res: Designator;
			n: StringBuf; scope: PCT.RecScope; ro: BOOLEAN;
	BEGIN
		IF IsInvalid(rec) THEN RETURN InvalidDesig END;
		res := InvalidDesig;
		IF rec.type IS PCT.Pointer THEN  rectyp := rec.type(PCT.Pointer).base  ELSE rectyp := rec.type END;
		IF rectyp IS PCT.Record THEN
			WITH rectyp: PCT.Record DO
				scope := rectyp.scope;
				(*fld := PCT.Find(scope, scope, name, PCT.procdeclared, TRUE);*)
				fld := PCT.Find(current, scope, name, PCT.procdeclared, TRUE);
				IF fld = NIL THEN PCM.Error(83, pos, "")
				ELSIF fld.type = PCT.UndefType THEN res := InvalidDesig
				ELSIF fld IS PCT.Field THEN
					IF rectyp # rec.type THEN  rec := NewDeref(rec.pos, rec)  END;		(*auto deref*)
					ro := (current.module # rectyp.scope.module) & ({PCT.PublicW, PCT.ProtectedW} * fld.vis = {});
					NEW(field, pos, rec, fld(PCT.Field), ro);
					res := field
				ELSIF fld IS PCT.Method THEN
					NEW(method, pos, NIL, fld, rec);
					res := method
				ELSE PCM.Error(83, pos, "")
				END
			END
		ELSE
			PCT.GetTypeName(rectyp, n);
			PCM.Error(53, rec.pos, n)
		END;
		RETURN res
	END NewField;
	
	PROCEDURE MakeSelf(self: Designator): Expression;	(*make a pointer out of self*)
	VAR type: PCT.Record;  e: Expression;
	BEGIN
		type := self.type(PCT.Record);
		ASSERT(type.ptr # NIL);
		e := NewMOp(self.pos, NIL, adrfn, self);
		e.type := type.ptr;
		RETURN e
	END MakeSelf;
	
	PROCEDURE NewIndex*(pos: LONGINT; array: Designator; index: Expression): Designator;
		VAR idx: Index; type: PCT.Array; ArrayCheck: BOOLEAN; res: Designator;
	BEGIN
		res := InvalidDesig;
		IF ~(IsInvalid(array) OR IsInvalid(index)) THEN
			IF array.type IS PCT.Pointer THEN	array := NewDeref(array.pos, array)	END;		(*auto deref*)
			IF array.type IS PCT.Array THEN
				type := array.type(PCT.Array);
				IF PCT.IsCardinalType(index.type) THEN
					IF index.type # PCT.Int32 THEN  index := NewConversion(index.pos, index, PCT.Int32)  END;
					ArrayCheck := TRUE;
					IF (index IS Const) & (type.mode = PCT.static) THEN (*do size check here*)
						IF index(Const).con.int >= type.len THEN PCM.Error(81, index.pos, "") END;
						ArrayCheck := FALSE;
					END;
					IF type.base # PCT.UndefType THEN
						NEW(idx, pos, array, index, ArrayCheck); res := idx
					END
				ELSE PCM.Error(80, index.pos, "")
				END
			ELSE PCM.Error(82, index.pos, "")
			END
		END;
		RETURN res
	END NewIndex;

	PROCEDURE NewGuard*(pos: LONGINT; des: Designator; type: PCT.Symbol; equal: BOOLEAN): Designator;
		VAR guard: Guard;
	BEGIN
		IF des=InvalidDesig THEN  RETURN des
		ELSIF ~(type IS PCT.Type) THEN
			PCM.Error(52, pos, "")
		ELSE
			WHILE (des # NIL) & (des IS Guard) DO
				des := des(Guard).des;
			END;
			IF (des.type IS PCT.Pointer) OR 
				(des.type IS PCT.Record) & (des IS Var) & (des(Var).obj IS PCT.Parameter) & des(Var).obj(PCT.Parameter).ref THEN
				IF TypeExtension(des.type, type.type) THEN
					NEW(guard, pos, des, type.type, equal);  RETURN guard
				ELSE  PCM.Error(85, pos, "")  END
			ELSIF (des.type = PCT.Ptr) THEN
				IF (type.type IS PCT.Pointer) & (type.type(PCT.Pointer).baseR # NIL) THEN
					NEW(guard, pos, des, type.type, equal);  RETURN guard
				ELSE  PCM.Error(85, pos, "")  END
			ELSE  PCM.Error(220, pos, "")
			END
		END;
		RETURN InvalidDesig
	END NewGuard;
	
(** ---------- Statements -------------- *)

	PROCEDURE Assign*(code: PCC.Code;  suppress: BOOLEAN;  lexpr: Designator;  rexpr: Expression);
	VAR  src, dst: PCC.Item;
	BEGIN
		IF IsInvalid(lexpr) OR IsInvalid(rexpr) THEN  RETURN  END;
		IF (rexpr IS Var) & (rexpr(Var).obj.name = PCT.SelfName) THEN
			IF (rexpr.type IS PCT.Record) & (rexpr.type(PCT.Record).ptr # NIL) THEN
				IF PCT.IsPointer(lexpr.type) THEN
					rexpr := MakeSelf(rexpr(Var))
				END
			END
		END;
		IF lexpr.readonly THEN  PCM.Error(76, lexpr.pos, "")
		ELSIF lexpr IS Type THEN  PCM.Error(126, lexpr.pos, "")
		ELSIF rexpr IS Type THEN  PCM.Error(126, rexpr.pos, "")
		ELSIF AssignmentCompatible(rexpr, lexpr) & ~suppress THEN
			IF (lexpr.type # rexpr.type) THEN
				rexpr := NewConversion(rexpr.pos, rexpr, lexpr.type)
			END;
			IF (rexpr IS FunCall) & ((rexpr.type IS PCT.Record) OR (rexpr.type IS PCT.Array)) THEN
				lexpr.Emit(code, dst);
				PCC.PushRetDesc(code, dst);
				rexpr.Emit(code, src)
			ELSE
				rexpr.Emit(code, src);
				IF (rexpr.type = PCT.Bool) OR ((rexpr IS Index)&(rexpr.type IS PCT.Basic)) THEN PCC.Load(code, src) END;
				lexpr.Emit(code, dst);
				PCC.Assign(code, dst, src)
			END
		ELSIF ~suppress THEN
			PCM.Error(113, rexpr.pos, "")
		END
	END Assign;
	
	PROCEDURE CallSProc(code: PCC.Code;  suppress: BOOLEAN;  pos, fnr: LONGINT;  params: BuiltInEl);
		VAR tmp: Const;
			i, j, k: PCC.Item; l: PCC.Label; type: PCT.Struct;  c, size, openDims: LONGINT;  par0, par1: Expression;
			rec: PCT.Record;  init: PCT.Method; reg: SHORTINT;
			
			PROCEDURE StartBodies(rec: PCT.Record;  self: Expression);
				(* must start the super-class body first! *)
			BEGIN
				IF rec # NIL THEN
					StartBodies(rec.brec, self);
					rec.scope.Await(PCT.modeavailable);	(*ACTIVE flag in the body, known only when record is completed*)
					IF rec.scope.body # NIL THEN
						self.Emit(code, i);
						PCC.SysStart(code, rec.scope.body, i)
					END
				END;
			END StartBodies;
			
	BEGIN
		IF (fnr # newfn) & ~params.NothingLeft() THEN  PCM.Error(65, pos, ""); RETURN 
		ELSIF (fnr = newfn) & (params.first = NIL) THEN  PCM.Error(65, pos, ""); RETURN END;
		IF (fnr = assertfn) & (params.first IS Const) THEN
			tmp := params.first(Const);
			IF (tmp.type # PCT.Bool) THEN PCM.Error(111, tmp.pos, "")
			ELSIF ~tmp.con.bool THEN  PCM.Error(99, tmp.pos, "")  END;
			RETURN
		END;
		IF suppress OR PCM.error THEN  RETURN  END;
		IF params.first # NIL THEN
			par0 := params.first;
			IF par0.link # NIL THEN  par1 := par0.link  END
		END;
		CASE fnr OF
			| movefn:
					par0.Emit(code, i); par1.Emit(code, j); par1.link.Emit(code, k);
					PCC.MoveBlock(code, j, i, k)
			| copyfn:
					par0.Emit(code, i);  par1.Emit(code, j);
					PCC.MoveString(code, i, j)
			| getfn, putfn, put8fn, put16fn, put32fn:
					par0.Emit(code, i);  par1.Emit(code, j);
					PCC.SYScopy(code,  i, j,  fnr = getfn)
			| assertfn: 
					IF PCM.AssertCheck IN PCM.codeOptions THEN
						par0.Emit(code, i);
						l := PCC.none;
						PCC.Jcc(code, l, i);
						PCC.GenTrap(code, par1(Const).con.int);
						PCC.FixJmp(code, l)
					END
			| shaltfn, haltfn:
					PCC.GenTrap(code, par0(Const).con.int)
			| incfn, decfn:
					type := par0.type;
					par0.Emit(code, i);
					IF par1 = NIL THEN
						PCC.MakeConst(j, One.con, type)
					ELSE
						ASSERT(type = par1.type);
						par1.Emit(code, j)
					END;
					IF fnr = incfn THEN PCC.DOp(code, PCS.plus, i, j) ELSE PCC.DOp(code, PCS.minus, i, j) END;
					PCC.Convert(code, i, type, FALSE);
					par0.Emit(code, j);
					PCC.Assign(code, j, i)
			| inclfn, exclfn:
					par0.Emit(code, i);
					IF par1 IS Const THEN
						PCC.MakeIntConst(j, ASH(LONG(LONG(1)), par1(Const).con.int), PCT.Set)
					ELSE
						par1.Emit(code, j);
						PCC.MOp(code, PCC.setfn, j)
					END;
					IF fnr = inclfn THEN PCC.DOp(code, PCS.plus, i, j) ELSE PCC.DOp(code, PCS.minus, i, j) END;
					IF (par0 IS Projection) THEN 	(*EXCL( SYSTEM.VAL(....  *)
						REPEAT
							par1 := par0;
							WHILE par0 IS Projection DO  par0 := par0(Projection).exp  END;
							WHILE par0 IS Conversion DO  par0 := par0(Conversion).exp  END
						UNTIL par1 = par0;
						ASSERT(par0 IS Designator);
						par0.Emit(code, j);	(*this is not a register but a reference to some memory location*)
						PCC.Convert(code, j, PCT.Bool, TRUE)
					ELSE
						par0.Emit(code, j)
					END; 
					PCC.Assign(code, j, i)
			| getregfn, putregfn:
					par1.Emit(code, i);
					reg := SHORT(SHORT(par0(Const).con.int));
					IF (reg >= 0) & (reg <= 7) THEN
						IF i.type = PCT.Int8 THEN INC(reg, 16)
						ELSIF i.type = PCT.Int16 THEN INC(reg, 8)
						END
					ELSE  reg := reg-8
					END;
					IF fnr = getregfn THEN  PCC.GetHWReg(code, i, reg)  ELSE  PCC.SetHWReg(code, i, reg)  END
			| portinfn:
					par0.Emit(code, i); par1.Emit(code, j);
					PCC.ReadHWPort(code, i, j)
			| portoutfn:
					par0.Emit(code, i); par1.Emit(code, j);
					PCC.WriteHWPort(code, i, j)
			| sysnewfn:
					par0.Emit(code, i); par1.Emit(code, j);
					PCC.SysNewBlock(code, i, j)
			| newfn:
					par0.Emit(code, i);
					IF params(BuiltInEl).usearray THEN
						type := par0.type;
						IF type IS PCT.Pointer THEN  type := type(PCT.Pointer).base  END;
						openDims := 0;
						IF par1 # NIL THEN
							par1.Emit(code, j);
							IF j.type # PCT.Int32 THEN  PCC.Convert(code, j, PCT.Int32, FALSE) END;
							PCC.Param(code, j, PCT.Int32, FALSE);	(*save on stack*)
							INC(openDims);
							type := type(PCT.Array).base;  par1 := par1.link;
							WHILE par1 # NIL DO
								par1.Emit(code, k);
								IF k.type # PCT.Int32 THEN  PCC.Convert(code, k, PCT.Int32, FALSE) END;
								PCC.Param(code, k, PCT.Int32, FALSE);	(*save on stack*)
								PCC.DOp(code, PCS.times, j, k);
								INC(openDims);
								type:= type(PCT.Array).base;  par1 := par1.link
							END
						END;
						size := 1;
						WHILE type IS PCT.Array DO
							IF type(PCT.Array).mode # PCT.static THEN
								PCM.Error(65, pos, "");
							END;
							size := size * type(PCT.Array).len;
							type := type(PCT.Array).base
						END;
						IF (par0.link # NIL) & (size # 1) THEN
							PCC.MakeIntConst(k, size, PCT.Int32);
							PCC.DOp(code, PCS.times, j, k);
						ELSIF (size # 1) THEN
							PCC.MakeIntConst(j, size, PCT.Int32)
						END;
						PCC.SysNewArray(code, i, type, j, openDims);
						IF openDims # 0 THEN
							par0.Emit(code, i);
							c := openDims;
							WHILE c > 0 DO
								DEC(c);
								PCC.SetArrayDim(code, i, openDims, c)
							END;
						END
					ELSE
						PCC.SysNewRec(code, i);
						rec := par0.type(PCT.Pointer).baseR;
						init := rec.scope.initproc;
						IF init # NIL THEN
							PCC.SaveRegisters(code);
							params.first := par0.link;	(*get rid of par0 *)
							par0.link := NIL;
							(* NEW(w, par0(Designator));*)
							params.Append(par0);
(*
							IF ~params.NothingLeft() THEN  PCM.Error(65, par0.pos) END;
*)
							params.Emit(code);
							par0.Emit(code, i);
							PCC.Method(code, i, i, init, FALSE);
							PCC.Call(code, i);
							PCC.RestoreRegisters(code)
						ELSIF par1 # NIL THEN
							PCM.Error(64, par1.pos, "no initializer for this object")
						END;
						StartBodies(rec, par0)
					END
		ELSE
			PCM.Error(121, pos, "")
		END
	END CallSProc;
	
	PROCEDURE MakeCall(code: PCC.Code;  proc: Designator;  p: PCT.Proc;  pars: ExprList;  curlevel: SHORTINT);
		VAR scope: PCT.ProcScope;  i: PCC.Item;
	BEGIN
		PCC.SaveRegisters(code);
		pars.Emit(code);
		IF p = NIL THEN
			(*var proc call*)
		ELSIF p.level # 0 THEN
			PCC.PushSL(code, curlevel-p.level)
		END;
		IF (p # NIL) & (PCT.Inline IN p.flags) THEN
			scope := p.scope;
			IF scope.code = NIL THEN scope.Await(PCT.complete) END;
			Inline(code, scope.code)
		ELSE
			proc.Emit(code, i);  PCC.Call(code, i);
			pars.ClearStack(code);
		END;
		PCC.RestoreRegisters(code);
	END MakeCall;
	
	PROCEDURE CallProc*(code: PCC.Code;  suppress: BOOLEAN;  proc: Designator;  params: ExprList;  curlevel: SHORTINT);
	VAR p: PCT.Proc;  ret: PCT.Struct;
	BEGIN
		IF IsInvalid(proc) OR  IsInvalid(params.first) THEN RETURN END;
		IF (proc IS SProc) THEN
			CallSProc(code, suppress, proc.pos, proc(SProc).nr, params(BuiltInEl));
			RETURN
		ELSIF (proc IS AnyProc) THEN
			WITH proc: AnyProc DO
				proc.Resolve(params, NIL);
				p := proc.proc;
				ret := proc.type;
				suppress := suppress OR (p = NIL);
			END
		ELSIF proc.type IS PCT.Delegate THEN
			ret := proc.type(PCT.Delegate).return
		END;
		IF (ret # PCT.NoType) THEN
			PCM.Error(121, proc.pos, "")
		ELSIF ~suppress & ~PCM.error THEN
			MakeCall(code, proc, p, params, curlevel);
		END
	END CallProc;
	
	(** Interface - cast generic object to an interface *)
	
	PROCEDURE Interface*(intf, obj: Designator): Designator;
	BEGIN
		ASSERT(IsInterface(intf));
		IF IsVariable(obj) THEN
			obj.type := intf.type
		ELSE
			PCM.Error(112, obj.pos, "")
		END;
		RETURN obj
	END Interface;
	
	(**--------- Control Structures -----------------*)


	PROCEDURE Trap*(code: PCC.Code;  suppress: BOOLEAN;  nr: LONGINT);
	BEGIN
		IF ~suppress THEN  PCC.GenTrap(code, nr)  END
	END Trap;
	
	(*
		info.in => else chain
		info.out => after endif
	*)
	(** If - Returns if code must be suppressed *)
	PROCEDURE If*(code: PCC.Code;  suppress: BOOLEAN;  VAR info: LoopInfo;  cond: Expression;  elsif: BOOLEAN): BOOLEAN;
	VAR  i: PCC.Item;
	BEGIN
		IF ~elsif THEN
			info.in := PCC.none; info.out := PCC.none;
			info.true := FALSE; info.false := FALSE;
		ELSIF ~(info.false OR info.true OR suppress) THEN	(*no fall through*)
			PCC.Jmp(code, info.out);
			PCC.FixJmp(code, info.in);  info.in := PCC.none;
		END;
		info.false := FALSE;
		IF IsInvalid(cond) THEN
			(*ignore*)
			suppress := TRUE
		ELSIF cond.type # PCT.Bool THEN
			PCM.Error(120, cond.pos, "");
			suppress := TRUE
		ELSIF suppress OR info.true THEN
			suppress := TRUE (*skip*)
		ELSIF ~(cond IS Const) THEN
			cond.Emit(code, i);
			PCC.MOp(code, PCS.not, i);
			PCC.Jcc(code, info.in, i);	(*forw.jump*)
			suppress := FALSE
		ELSIF cond(Const).con = PCT.False THEN
			info.false := TRUE;
			suppress := TRUE
			(*PCC.Jmp(code, info.in);	(*forw.jump*)*)	(*fall through*)
		ELSE
			info.true := TRUE;
			suppress := FALSE
		END;
		RETURN suppress
	END If;
	
	PROCEDURE Else*(code: PCC.Code; suppress: BOOLEAN;   VAR info: LoopInfo): BOOLEAN;
	BEGIN
		IF suppress THEN  RETURN TRUE  END;
		IF ~(info.true OR info.false) THEN PCC.Jmp(code, info.out) END;
		PCC.FixJmp(code, info.in);  info.in := PCC.none;
		RETURN info.true
	END Else;
	
	PROCEDURE EndIf*(code: PCC.Code;  VAR info: LoopInfo);
	BEGIN
		PCC.FixJmp(code, info.in);	(*no else*)
		PCC.FixJmp(code, info.out)
	END EndIf;

	PROCEDURE While*(code: PCC.Code;  suppress: BOOLEAN;  VAR info: LoopInfo;  cond: Expression);
	VAR  i: PCC.Item;
	BEGIN
		PCC.DefLabel(code, info.in);
		info.out := PCC.none;
		IF IsInvalid(cond) THEN
			(*skip*)
		ELSIF cond.type # PCT.Bool THEN
			PCM.Error(120, cond.pos, "")
		ELSIF suppress THEN
			(*skip*)
		ELSIF ~(cond IS Const) THEN
			cond.Emit(code, i);
			PCC.MOp(code, PCS.not, i);
			PCC.Jcc(code, info.out, i)
		ELSIF (cond(Const).con = PCT.False) THEN
			PCC.Jmp(code, info.out)
		(*ELSE
				true=>endless loop*)
		END
	END While;
	
	PROCEDURE Repeat*(code: PCC.Code;  suppress: BOOLEAN;  VAR info: LoopInfo;  cond: Expression);
	VAR  i: PCC.Item;
	BEGIN
		ASSERT(info.out = PCC.none);
		IF IsInvalid(cond) THEN
			(*skip*)
		ELSIF cond.type # PCT.Bool THEN
			PCM.Error(120, cond.pos, "")
		ELSIF suppress THEN 
			(*skip*)
		ELSIF ~(cond IS Const) THEN
			cond.Emit(code, i);
			PCC.MOp(code, PCS.not, i);
			PCC.Jcc(code, info.in, i)
		ELSIF (cond(Const).con = PCT.False)THEN
				PCC.Jmp(code, info.in)	(*always jump*)
		(* ELSE
			cond=true, never jump*)
		END;
	END Repeat;
	
	PROCEDURE BeginFor*(code: PCC.Code;  suppress: BOOLEAN;  pos: LONGINT; var: Designator; from, to, by: Expression;  VAR info: LoopInfo);
	VAR  step: LONGINT;
	BEGIN
		info.out := PCC.none;
		IF ~(IsInvalid(var) OR IsInvalid(by) OR IsInvalid(from) OR IsInvalid(to)) THEN
			IF ~PCT.IsCardinalType(var.type) THEN  PCM.Error(68, var.pos, "")
			ELSIF ~PCT.IsCardinalType(by.type) THEN  PCM.Error(68, by.pos, "")
			ELSE
				step := by(Const).con.int;
				Assign(code, suppress, var, from);
				to := NewConversion(pos, to, var.type);
				MakeTemp(code, suppress, to);
				IF step > 0 THEN
					While(code, suppress, info, NewDOp(pos, leq, var, to))
				ELSIF step < 0 THEN
					While(code, suppress, info, NewDOp(pos, geq, var, to))
				ELSE
					PCM.Error(63, by.pos, "")
				END
			END
		END
	END BeginFor;
	
	PROCEDURE EndFor*(code: PCC.Code;  suppress: BOOLEAN;  pos: LONGINT; var: Designator;  step: Expression;  VAR info: LoopInfo);
	BEGIN
		IF IsInvalid(var) OR IsInvalid(step) THEN  RETURN   END;
		Assign(code, suppress, var, NewDOp(pos, plus, var, step));
		EndLoop(code, suppress, info);
		IF ~suppress THEN PCC.FreeStack(code, var.type) END
	END EndFor;
	
	PROCEDURE BeginLoop*(code: PCC.Code;  VAR info: LoopInfo);
	BEGIN
		PCC.DefLabel(code, info.in);
		info.out := PCC.none;
	END BeginLoop;
	
	PROCEDURE EndLoop*(code: PCC.Code;  suppress: BOOLEAN;  VAR info: LoopInfo);
	BEGIN
		IF ~suppress THEN
			PCC.Jmp(code, info.in);
			PCC.FixJmp(code, info.out)
		END
	END EndLoop;
	
	PROCEDURE Exit*(code: PCC.Code;  suppress: BOOLEAN;  VAR info: LoopInfo; forlevel: LONGINT);
	BEGIN
		IF ~suppress THEN
			WHILE forlevel > 0 DO  PCC.FreeStack(code, PCT.Int32); DEC(forlevel)  END;
			PCC.Jmp(code, info.out)
		END
	END Exit;
	
	PROCEDURE Return*(code: PCC.Code;  suppress: BOOLEAN;  scope: PCT.Scope; pos: LONGINT; expr: Expression;  unlock: BOOLEAN);
	VAR	rtype: PCT.Struct;  i: PCC.Item;  complex: BOOLEAN;  proc: PCT.Proc;  var: Var;
	BEGIN
		IF scope IS PCT.ProcScope THEN  proc := scope(PCT.ProcScope).ownerO  END;
		IF IsInvalid(expr) THEN
		ELSIF (proc # NIL) & (proc.type # PCT.NoType) THEN
			IF expr = NIL THEN
				PCM.Error(124, pos, "missing return expression")
			ELSE
				rtype := proc.type;
				IF (expr IS Var) & (expr.type IS PCT.Record) THEN
					var := expr(Var);
					IF (var.obj.name = PCT.SelfName) & (var.type(PCT.Record).ptr # NIL) & (rtype IS PCT.Pointer) THEN
						expr := MakeSelf(var)
					END
				END;
				IF TypeCompatible(expr, rtype) & ~suppress THEN
					IF (rtype # expr.type) & (expr.type IS PCT.Basic) THEN  expr := NewConversion(expr.pos, expr, rtype)  END;
					IF (rtype IS PCT.Basic) OR (rtype IS PCT.Pointer) OR (rtype IS PCT.Delegate) THEN
						expr.Emit(code, i);
						IF unlock THEN
							PCC.Load(code, i); PCC.SaveRegisters(code); Lock(code, scope, pos, FALSE); PCC.RestoreRegisters(code)
						END;
						PCC.Return(code, i, proc);
						PCC.Leave(code, proc)
					ELSIF expr IS FunCall THEN
						ASSERT((rtype IS PCT.Record) OR (rtype IS PCT.Array));
						IF (rtype IS PCT.Array) & (rtype(PCT.Array).mode = PCT.open) THEN
							IF expr(FunCall).type(PCT.Array).mode = PCT.open THEN
								PCC.PushOpenAryRetDesc(code, rtype);
								expr.Emit(code, i);
								PCC.Return(code, i, proc);
							ELSE
								PCC.PushStatAryRetDesc(code, expr(FunCall).type);
								expr.Emit(code, i);
								PCC.Return(code, i, proc);
							END;
						ELSE
							PCC.PushRetDesc2(code, proc);	(* push own return descriptor. No return needed, value copied directly to the caller *)
							expr.Emit(code, i);
						END;
						
						IF unlock THEN
							PCC.SaveRegisters(code); Lock(code, scope, pos, FALSE); PCC.RestoreRegisters(code)
						END;
						PCC.Leave(code, proc)
					ELSE
						ASSERT((rtype IS PCT.Record) OR (rtype IS PCT.Array));
						expr.Emit(code, i);
						PCC.Return(code, i, proc);
						IF unlock THEN
							PCC.SaveRegisters(code); Lock(code, scope, pos, FALSE); PCC.RestoreRegisters(code)
						END;
						PCC.Leave(code, proc)
					END;
				END
			END
		ELSIF expr#NIL THEN
			PCM.Error(113, pos, "")
		ELSIF ~suppress THEN
			IF unlock THEN	(*saveregs not needed, nothing to return*)
				Lock(code, scope, pos, FALSE)
			END;
			PCC.Leave(code, proc);
		END
	END Return;

	PROCEDURE Await*(code: PCC.Code;  suppress: BOOLEAN;  scope: PCT.Scope;  pos: LONGINT;  cond: Expression);
	VAR  skip: PCC.Label;  adr: PCM.Attribute;  i: PCC.Item;  selfo: PCT.Symbol;  self: Designator;
	BEGIN
		IF cond.type # PCT.Bool THEN
			PCM.Error(120, cond.pos, "")
		ELSIF ~suppress THEN
			skip := PCC.none;  PCC.Jmp(code, skip);
			
			PCC.AwaitEnter(code, adr);
			cond.Emit(code, i);
			PCC.AwaitExit(code, i);
			
			PCC.FixJmp(code, skip);
			selfo := PCT.Find(scope, scope, PCT.SelfName, PCT.procdeclared, TRUE);
			IF selfo = NIL THEN  PCM.Error(999, pos, "");  RETURN  END;
			self := MakeNode(pos, scope, selfo);
			self.Emit(code, i);
			PCC.Await(code, i, adr);
		END;
	END Await;
	
	PROCEDURE Case*(code: PCC.Code;  suppress: BOOLEAN;  VAR info: CaseInfo;  x: Expression);
	VAR  i: PCC.Item;
	BEGIN
		IF IsInvalid(x) THEN RETURN END;
		info.out := PCC.none;
		info.range := NIL;
		info.first := TRUE;
		IF (x.type#PCT.Char8) &  ~PCT.IsCardinalType(x.type) THEN
			info.type := NIL;
			PCM.Error(68, x.pos, "")
		ELSIF ~suppress THEN
			info.type := x.type(PCT.Basic);
			x.Emit(code, i);
			PCC.CaseStat(code, info.ref, i)
		ELSE
			info.type := x.type(PCT.Basic)
		END
	END Case;
	
	PROCEDURE CaseLine*(code: PCC.Code;  suppress: BOOLEAN;  VAR info: CaseInfo;  mine, maxe: Expression;  firstline: BOOLEAN);
	(* Invariant:  p.max < p.next.min *)
	VAR  p, q, r: CaseRange;  min, max: LONGINT;
	
		PROCEDURE Extract(x: Expression;  VAR val: LONGINT): BOOLEAN;
		VAR  con: PCT.Const;
		BEGIN
			IF ~(x IS Const) THEN  PCM.Error(50, x.pos, "");  RETURN FALSE  END;
			con := x(Const).con;
			IF info.type = PCT.Char8 THEN
				IF x.type # PCT.Char8 THEN  PCM.Error(61, x.pos, ""); RETURN FALSE  END;
				val := con.int
			ELSE
				IF PCT.BasicTypeDistance(con.type(PCT.Basic), info.type) < 0 THEN  PCM.Error(61, x.pos, ""); RETURN FALSE  END;
				val := con.int
			END;
			RETURN TRUE
		END Extract;
	
	BEGIN
		IF IsInvalid(mine) OR IsInvalid(maxe) OR (info.type = NIL) THEN RETURN END;
		IF Extract(mine, min) THEN
			IF (mine = maxe) OR Extract(maxe, max) THEN
				IF mine = maxe THEN  max := min END;
				p := info.range; q := NIL;
				
				WHILE (p # NIL) & (min > p.max) DO  q := p; p := p.next  END;
				IF (p # NIL) & (max >= p.min) THEN	(*collision*)
					PCM.Error(62, mine.pos, "")
				ELSE
				
					IF (p # NIL) & (p.min = max+1) THEN
						p.min := min
					ELSIF (q # NIL) & (min+1 = q.max) THEN
						q.max := min
					ELSE
						NEW(r);  r.min := min; r.max := max;
						r.next := p;
						IF q = NIL THEN
							info.range := r
						ELSE
							q.next := r
						END
					END;
					IF suppress THEN RETURN END;
					IF firstline & ~info.first THEN
						PCC.Jmp(code, info.out);
					END;
					info.first := FALSE;
					PCC.CaseLine(code, info.ref, min, max)
				END
			END
		END
	END CaseLine;
	
	PROCEDURE CaseElse*(code: PCC.Code;  suppress: BOOLEAN;  VAR info: CaseInfo);
	BEGIN
		IF info.type = NIL THEN RETURN END;
		IF suppress THEN RETURN END;
		IF ~info.first THEN
			PCC.Jmp(code, info.out);
		END;
		info.first := FALSE;
		PCC.CaseElse(code, info.ref)
	END CaseElse;
	
	PROCEDURE CaseEnd*(code: PCC.Code;  suppress: BOOLEAN;  VAR info: CaseInfo);
	BEGIN
		IF info.type = NIL THEN RETURN END;
		IF suppress THEN RETURN END;
		PCC.FixJmp(code, info.out)
	END CaseEnd;

	(** Lock - lock/unlock the given object *)

	PROCEDURE Lock*(code: PCC.Code;  scope: PCT.Scope;  pos: LONGINT;  lock: BOOLEAN);
	VAR selfo: PCT.Symbol;  self: Designator;  i: PCC.Item;
	BEGIN
		selfo := PCT.Find(scope, scope, PCT.SelfName, PCT.procdeclared, TRUE);
		self := MakeNode(pos, scope, selfo);
		self.Emit(code, i);
		PCC.SysLock(code, i, lock);
	END Lock;
	
	PROCEDURE Inline*(code: PCC.Code; inline: PCM.Attribute);
	BEGIN
		IF (inline # NIL) & (inline IS PCLIR.AsmInline) THEN
			PCC.Inline(code, inline)
		ELSE
			PCDebug.ToDo(PCDebug.NotImplemented)
		END
	END Inline;

	PROCEDURE AllocateArrays(code: PCC.Code; par: PCT.Parameter; var: PCT.Variable);
		VAR i: PCC.Item; arr: PCT.Array; darr: DynSizedArray;
	BEGIN
		WHILE par # NIL DO
			IF par.type IS PCT.Array THEN
				arr := par.type(PCT.Array);
				IF (arr.mode = PCT.open) & ~par.ref THEN PCC.LocalArray(code, par) END
			END;
			par := par.nextPar
		END;
		WHILE var # NIL DO
			IF var.type IS DynSizedArray THEN
				darr := var.type(DynSizedArray);
				darr.dlen(Expression).Emit(code, i);
				PCC.AllocateLocalArray(code, var(PCT.LocalVar), i)
			END;
			var := var.nextVar
		END
	END AllocateArrays;
	
	PROCEDURE InitInterfaces(code: PCC.Code; r, int: PCT.Record);
		VAR i: LONGINT;
	BEGIN
		PCC.InitInterface(code, r, int);
		FOR i := 0 TO LEN(int.intf)-1 DO
			InitInterfaces(code, r, int.intf[i].baseR)
		END;
	END InitInterfaces;
	
	PROCEDURE InitRecords(code: PCC.Code; r: PCT.Record);
	VAR  r0: PCT.Record; i: LONGINT;
	BEGIN
		WHILE r # NIL DO
			r0 := r;
			WHILE r0 # NIL DO
				FOR i := 0 TO LEN(r0.intf)-1 DO InitInterfaces(code, r, r0.intf[i].baseR) END;
				r0 := r0.brec
			END;
			r := r.link
		END
	END InitRecords;
	
	PROCEDURE Enter*(scope: PCT.Scope): PCC.Code;
	VAR  code: PCC.Code; owner: PCT.Proc;
	BEGIN
		NEW(code);
		scope.code := code;
		IF scope IS PCT.ProcScope THEN
			owner := scope(PCT.ProcScope).ownerO;
			StringPool.GetString(owner.name, code.name);	(*debug*)
			PCC.Enter(code, owner.adr);
			AllocateArrays(code, owner.scope.firstPar, scope.firstVar)
		ELSIF scope IS PCT.ModScope THEN
			PCC.Enter(code, NIL);
			InitRecords(code, scope(PCT.ModScope).records);
		ELSE
			HALT(99);
		END;
		RETURN code
	END Enter;

	PROCEDURE DumpCode(code: PCC.Code;  name: ARRAY OF CHAR;  phase: LONGINT);
	BEGIN {EXCLUSIVE}
		PCM.LogW(01X);
		PCM.LogWStr("PROCEDURE ");  PCM.LogWStr(name);  PCM.LogWLn;
		IF phase = 0 THEN
			code.Traverse(PCLIR.DumpCode, FALSE, NIL)
		ELSIF phase = 1 THEN
			code.Traverse(PCLIR.CG.DumpCode, FALSE, NIL)
		END;
		PCM.LogW(02X);
	END DumpCode;

	(** Leave - leave a procedure. Generate a trap for functions (unless noTrap) *)
	
	PROCEDURE Leave*(code: PCC.Code; scope: PCT.Scope;  noTrap: BOOLEAN);
	VAR  owner: PCT.Proc;  name: StringBuf;  dump: BOOLEAN;
	BEGIN
		ASSERT(~(scope IS PCT.RecScope));
		name := "$$";
		IF scope IS PCT.ProcScope THEN
			owner := scope(PCT.ProcScope).ownerO;
			StringPool.GetString(owner.name, name);
		END;
		IF (owner # NIL) & (owner.type # PCT.NoType) & ~noTrap THEN
			PCC.GenTrap(code, PCM.ReturnTrap)
		ELSE
			PCC.Leave(code, owner)
		END;
		dump := (PCM.dump = name) OR (PCM.dump = "*");
		IF dump THEN  DumpCode(code, name, 0)  END;
		PCLIR.CG.Optimize(code);
		IF dump THEN  DumpCode(code, name, 1)  END;
	END Leave;
	
	PROCEDURE Init;
		
		PROCEDURE NewSProc(m: PCT.Module;  name: ARRAY OF CHAR;  nr: LONGINT);
		VAR s: SProcInfo;  n: PCS.Name; res: LONGINT;
		BEGIN
			StringPool.GetIndex(name, n);
			m.scope.CreateSymbol(n, PCT.Public, PCT.NoType, res); ASSERT(res = PCT.Ok);
			NEW(s); s.nr := nr;
			m.scope.last.info := s
		END NewSProc;
		
		PROCEDURE NewConst(m: PCT.Module;  name: ARRAY OF CHAR;  val: LONGINT);
			VAR n: StringPool.Index; res: LONGINT; c: PCT.Const;
		BEGIN
			StringPool.GetIndex(name, n);
			c := PCT.NewIntConst(val, PCT.GetIntType(val));
			m.scope.CreateValue(n, PCT.Public, c, res); ASSERT(res = PCT.Ok)
		END NewConst;
		
		PROCEDURE MakeInline(name: ARRAY OF CHAR; fnr: LONGINT);
		VAR  inline: PCLIR.AsmInline;  code: PCLIR.AsmBlock;  ps: PCT.ProcScope; idx: StringPool.Index; res: LONGINT;
		BEGIN
			NEW(inline); NEW(code); inline.code := code;
			NEW(ps); PCT.InitScope(ps, PCT.System.scope, {}, FALSE);  ps.code := inline; PCT.SetOwner(ps);
			CASE fnr OF
			|  clifn:
					code.code[0] := 0FAX;  code.len := 1;
					StringPool.GetIndex(name, idx);
			|  stifn:
					code.code[0] := 0FBX;  code.len := 1;
					StringPool.GetIndex(name, idx);
			END;
			PCT.System.scope.CreateProc(idx, PCT.Public, {PCT.Inline}, ps, PCT.NoType, res); ASSERT(res = PCT.Ok);
			PCT.ChangeState(ps, PCT.complete, -1)
		END MakeInline;
		
	BEGIN
		(*built-in procedures*)
		IF Trace THEN PCM.LogWLn; PCM.LogWStr("Universe ") END;
		NewSProc(PCT.Universe, "ABS", PCC.absfn);
		NewSProc(PCT.Universe, "ASH", PCC.ashfn);
		NewSProc(PCT.Universe, "ASSERT", assertfn);
		NewSProc(PCT.Universe, "CAP", PCC.capfn);
		NewSProc(PCT.Universe, "CHR", chrfn);
		IF PCM.LocalUnicodeSupport THEN
			NewSProc(PCT.Universe, "CHR8", chr8fn);
			NewSProc(PCT.Universe, "CHR16", chr16fn);
			NewSProc(PCT.Universe, "CHR32", chr32fn)
		END;
		NewSProc(PCT.Universe, "COPY", copyfn);
		NewSProc(PCT.Universe, "ENTIER", entierfn);
		NewSProc(PCT.Universe, "ENTIERH", entierhfn);
		NewSProc(PCT.Universe, "LEN", lenfn);
		NewSProc(PCT.Universe, "LONG", longfn);
		NewSProc(PCT.Universe, "MAX", maxfn);
		NewSProc(PCT.Universe, "MIN", minfn);
		NewSProc(PCT.Universe, "ODD", PCC.oddfn);
		NewSProc(PCT.Universe, "ORD", ordfn);
		IF PCM.LocalUnicodeSupport THEN
			NewSProc(PCT.Universe, "ORD8", ord8fn);
			NewSProc(PCT.Universe, "ORD16", ord16fn);
			NewSProc(PCT.Universe, "ORD32", ord32fn);
		END;

		NewSProc(PCT.Universe, "SHORT", shortfn);
		NewSProc(PCT.Universe, "SIZE", sizefn);
		NewSProc(PCT.Universe, "DEC", decfn);
		NewSProc(PCT.Universe, "EXCL", exclfn);
		NewSProc(PCT.Universe, "HALT", haltfn);
		NewSProc(PCT.Universe, "INC", incfn);
		NewSProc(PCT.Universe, "INCL", inclfn);
		NewSProc(PCT.Universe, "NEW", newfn);
		
		PCT.ChangeState(PCT.Universe.scope, PCT.complete, -1);
		IF Trace THEN PCM.LogWLn; PCM.LogWStr("done ") END;
		
		NewConst(PCT.System, "EAX", 8);  NewConst(PCT.System, "ECX", 9);
		NewConst(PCT.System, "EDX", 10);  NewConst(PCT.System, "EBX", 11);
		NewConst(PCT.System, "ESP", 12);  NewConst(PCT.System, "EBP", 13);
		NewConst(PCT.System, "ESI", 14);  NewConst(PCT.System, "EDI", 15);

		NewConst(PCT.System, "AX", 16);  NewConst(PCT.System, "CX", 17);
		NewConst(PCT.System, "DX", 18);  NewConst(PCT.System, "BX", 19);

		NewConst(PCT.System, "AL", 24);  NewConst(PCT.System, "CL", 25);
		NewConst(PCT.System, "DL", 26);  NewConst(PCT.System, "BL", 27);
		NewConst(PCT.System, "AH", 28);  NewConst(PCT.System, "CH", 29);
		NewConst(PCT.System, "DH", 30);  NewConst(PCT.System, "BH", 31);

		NewSProc(PCT.System, "BIT", PCC.bitfn);
		MakeInline("STI", stifn);
		MakeInline("CLI", clifn);
		NewSProc(PCT.System, "HALT", shaltfn);
		NewSProc(PCT.System, "ADR", adrfn);
		NewSProc(PCT.System, "VAL", valfn);
		NewSProc(PCT.System, "GETREG", getregfn);
		NewSProc(PCT.System, "PUTREG", putregfn);
		NewSProc(PCT.System, "GET", getfn);
		NewSProc(PCT.System, "GET8", get8fn);
		NewSProc(PCT.System, "GET16", get16fn);
		NewSProc(PCT.System, "GET32", get32fn);
		NewSProc(PCT.System, "LSH", PCC.lshfn);
		NewSProc(PCT.System, "MOVE", movefn);
		NewSProc(PCT.System, "NEW", sysnewfn);
		NewSProc(PCT.System, "PUT", putfn);
		NewSProc(PCT.System, "PUT8", put8fn);
		NewSProc(PCT.System, "PUT16", put16fn);
		NewSProc(PCT.System, "PUT32", put32fn);
		NewSProc(PCT.System, "PORTIN", portinfn);
		NewSProc(PCT.System, "PORTOUT", portoutfn);
		NewSProc(PCT.System, "ROT", PCC.rotfn);
		NewSProc(PCT.System, "TYPECODE", typecodefn);
		PCT.ChangeState(PCT.System.scope, PCT.complete, -1);
	END Init;
	
BEGIN
	NEW(Invalid);
	InvalidExpr := NewIntValue(NoPosition, 1, PCT.Int8);
	NEW(InvalidDesig, NoPosition, PCT.UndefType);
	NEW(InvalidEL, NoPosition, PCT.NoType); InvalidEL.suppress := TRUE;
	Zero:=NewIntValue(NoPosition, 0, PCT.Int8);
	One:=NewIntValue(NoPosition, 1, PCT.Int8);
	NEW(unknownObj); PCT.InitSymbol(unknownObj, StringPool.GetIndex1(""), PCT.Public, PCT.UndefType);
	Init;

	IF Trace THEN PCM.LogWLn; PCM.LogWStr("PCB.Trace on") END;
	IF TraceEmit THEN PCM.LogWLn; PCM.LogWStr("PCB.TraceEmit on") END;
END PCB.


(*
	Impossible errors:
	
	1500	Conversion: const LONGREAL to other than REAL
	1501	Conversion of const which is not Cardinal, CHAR, REAL, LONGREAL
	1502	Projection of const which is not Cardinal, CHAR, REAL, SET, NIL
	1503	Projection to const which is not Cardinal, CHAR, REAL, LONGREAL, SET
	1504	MakeNode: field/method cannot be referenced through SELF (SELF not found)

*)

(*
	20.09.03	prk	Preload values from arrays to use less registers (hopefully)
	20.09.03	prk	"/Dcode" compiler option added
	03.08.03	prk	issue error for RETURN without value in a function
	06.04.03	prk	LIR code trace output  adapted to new output model
	25.02.03	prk	do not emit temp handling in FOR when suppress = true (deadcode)
	11.06.02	prk	SYSTEM.BIT implemented
	13.04.02	prk	issue error 64 when NEW has parameters but no initializer available
	05.02.02	prk	PCT.Find cleanup
	10.12.01	prk	ENTIER: rounding mode set to chop, rounding modes caches as globals
	28.11.01	prk	constant folding of monadic integer operations, result type corrected
	28.11.01	prk	copying a too long string causes an error 114 (was 62)
	22.11.01	prk	improved flag handling
	21.11.01	prk	actual parameter's error messages improved
	19.11.01	prk	definitions
	17.11.01	prk	more flexible type handling of integer constants
	16.11.01	prk	constant folding of reals done with maximal precision
	02.11.01	prk	fixed return of a function call with non-primitive type
	01.11.01	prk	improved error handling in case statements
	30.08.01	prk	ASSERT in parameter emission weakened (was trap in emission of non-overloaded procedures when params are incompatible)
	29.08.01	prk	PCT functions: return "res" instead of taking "pos"
	27.08.01	prk	PCT.Insert removed, use Create procedures instead
	27.08.01	prk	scope.unsorted list removed; use var, proc, const and type lists instead
	17.08.01	prk	overloading
	23.07.01	prk	only a PTR is parameter compatible with a VAR PTR formal parameter
	23.07.01	prk	IsVariable fixed; (EXCL(SYS.VAL(SET, LONG(i)), 15) must fail
	11.07.01	prk	in a pointer to array of rec, mark the record in use (to be listed in the use section)
	11.07.01	prk	support for fields and methods with same name in scope
	04.07.01	prk	scope flags added, remove imported
	02.07.01	prk	access flags, new design
	27.06.01	prk	StringPool cleaned up
	15.06.01	prk	support for duplicate scope entries
	06.06.01	prk	use string pool for object names
	28.05.01	prk	allow sets in SYSTEM.PUT32
	17.05.01	prk	Delegates
	10.05.01	prk	remove temporary for-counter when EXIT inside a for-loop
	07.05.01	prk	Installable code generators moved to PCLIR; debug function added
	26.04.01	prk	separation of RECORD and OBJECT in the parser
	11.04.01	prk	Allow SYSTEM.VAL(static array, int const), used in Raster.Mod
	26.03.01	prk	Projection of numeric const to pointer type
*)
