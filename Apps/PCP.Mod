(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE PCP; (** AUTHOR "prk"; PURPOSE "Parallel Compiler: parser"; *)

IMPORT
	SYSTEM, AosKernel, AosBoot,
	StringPool, AosOut,
	PCM, PCS, PCT, PCB, PCC;

CONST
	(* The Tokens 
	ProgTools.Enum PCS
		null
		times slash div mod and 
		plus minus or eql neq  lss leq gtr geq in is 
		arrow period comma
		colon upto rparen rbrak rbrace
		of then do to by
		lparen lbrak lbrace
		not
		becomes
		number nil true false string
		ident semicolon bar end else
		elsif until if case while
		repeat for loop with exit passivate return
		refines implements
		array definition object record pointer begin code
		const type var procedure import
		module eof
		~
*)
	null = PCS.null; times = PCS.times; slash = PCS.slash; div = PCS.div; 
	mod = PCS.mod; and = PCS.and; plus = PCS.plus; minus = PCS.minus; 
	or = PCS.or; eql = PCS.eql; neq = PCS.neq; lss = PCS.lss; leq = PCS.leq; 
	gtr = PCS.gtr; geq = PCS.geq; in = PCS.in; is = PCS.is; arrow = PCS.arrow; 
	period = PCS.period; comma = PCS.comma; colon = PCS.colon; upto = PCS.upto; 
	rparen = PCS.rparen; rbrak = PCS.rbrak; rbrace = PCS.rbrace; of = PCS.of; 
	then = PCS.then; do = PCS.do; to = PCS.to; by = PCS.by; lparen = PCS.lparen; 
	lbrak = PCS.lbrak; lbrace = PCS.lbrace; not = PCS.not; becomes = PCS.becomes; 
	number = PCS.number; nil = PCS.nil; true = PCS.true; false = PCS.false; 
	string = PCS.string; ident = PCS.ident; semicolon = PCS.semicolon; 
	bar = PCS.bar; end = PCS.end; else = PCS.else; elsif = PCS.elsif; 
	until = PCS.until; if = PCS.if; case = PCS.case; while = PCS.while; 
	repeat = PCS.repeat; for = PCS.for; loop = PCS.loop; with = PCS.with; 
	exit = PCS.exit; passivate = PCS.passivate; return = PCS.return; 
	refines = PCS.refines; implements = PCS.implements; array = PCS.array; 
	definition = PCS.definition; object = PCS.object; record = PCS.record; 
	pointer = PCS.pointer; begin = PCS.begin; codeToken = PCS.code; const = PCS.const; 
	type = PCS.type; var = PCS.var; procedure = PCS.procedure; import = PCS.import; 
	module = PCS.module; eof = PCS.eof; 


	(*local constants, implementations restrictions*)
	MaxIdentDef = 128;		(*maximal number of IdentDef in a VarDecl*)

TYPE
	IdentDefDesc = RECORD name: PCS.Name; vis: SET END;	(*
		name = (parsed name) OR ("")
		vis = (parsed vis) OR (PCT.Internal)
	*)

VAR
		(** Assembler Plugin *)
	Assemble*: PROCEDURE (scanner: PCS.Scanner;  scope: PCT.Scope;  exported, inlined: BOOLEAN): PCM.Attribute;
	
		(* cached string constants used by the parser*)
	noname, self, untraced, delegate, overloading,
	exclusive, active, safe, priority,
	deltype, hiddenptr, procfld, ptrfld: StringPool.Index;
	
	NModules, NObjects, NDefinitions, NArrays, NRecords, NPointers, NDelegates, NProcedureTypes,
	NExclusive, NExclusiveMain, NActive,
	NSyncsCount: LONGINT;	(* statistical counters *)

(* ============================================================== *)
(* ------------- The Parser Object ---------------------------------- *)
TYPE
		(* Synchronize a thread with its child processes, await till all left the monitor or timeout *)
	Barrier = OBJECT (AosKernel.Timer)
		VAR
			timeout: LONGINT;
			started, ended: LONGINT;
			
			PROCEDURE & SInit(timeout: LONGINT);
			BEGIN started := 0; ended := 0; SELF.timeout := timeout*1000; Init;
			END SInit;
			
			PROCEDURE Enter;
			BEGIN
				AosBoot.Inc(started);
				AosBoot.Inc(NSyncsCount);
			END Enter;
			
			PROCEDURE Exit;
			BEGIN
				AosBoot.Inc(ended);
				IF started = ended THEN Wakeup END
			END Exit;
			
			PROCEDURE Await;
			BEGIN Sleep(timeout)
			END Await;
			
			PROCEDURE Stats(VAR started, inside: LONGINT);
			BEGIN started := SELF.started; inside := SELF.started - SELF.ended
			END Stats;
	END Barrier;
	
	
	Parser* = OBJECT
	
		VAR
			sync: Barrier;
			sym: PCS.Token;
			scanner: PCS.Scanner;
			scope, codescope: PCT.Scope;		(*codescope is the scope where the code is defined, where a WITH is used*)
			looplevel, scopelevel: SHORTINT;	(*copy of scope(ProcScope).level or 0 (rec/mod)*)
			forcount: SHORTINT;	(*nested for-loops inside a LOOP-statement, used to remove the temp for-counters*)
			curloop: PCB.LoopInfo;
			code: PCC.Code;
			inline: BOOLEAN;
			locked: BOOLEAN;	(*parser inside a locked statement block, set by StatementBlock*)
			unlockOnExit: BOOLEAN;	(* EXCLUSIVE block nested in a LOOP, must unlock when exit is called *)
			die: BOOLEAN;	(*kill the parser*)
			notifyScope: BOOLEAN;	(*notify the parent of current scope that the body mode is available*)
			isRecord: BOOLEAN;	(*cached: scope IS PCT.RecScope*)
			
			forwardPtr: ARRAY 128 OF RECORD  ptr: PCT.Pointer; name: PCS.Name  END;
			nofForwardPtr: LONGINT;
			
		(* --------------------------------------------------------- *)
		(* Parser utilities *)
		
		PROCEDURE Error(n, pos: LONGINT);
		BEGIN PCM.Error(n, pos, "")
		END Error;

		PROCEDURE Check(x: PCS.Token);
		BEGIN
			IF sym = x THEN scanner.Get(sym) ELSE PCM.Error(x, scanner.errpos, "") END;
		END Check;
		
		(* --------------------------------------------------------- *)
		(* Active Oberon Language Productions *)
		(* Declaration Section *)
		
		PROCEDURE TypeModifier(VAR flags: SET;  default, allowed: SET);
			VAR right: SHORTINT;
		BEGIN
			flags := default;
			IF (sym = lbrak) OR (sym = lbrace) THEN
				IF sym = lbrak THEN right := rbrak ELSE right := rbrace END;
				scanner.Get(sym);
				IF sym # ident THEN
					Error(ident, scanner.errpos)
				ELSIF scanner.name = untraced THEN
					flags := {PCM.Untraced}; scanner.Get(sym)
				ELSIF scanner.name = delegate THEN
					flags := {}; scanner.Get(sym)
				ELSIF scanner.name = overloading THEN
					flags := {PCT.Overloading}; scanner.Get(sym)
				ELSE
					Error(0, scanner.errpos); scanner.Get(sym)
				END;
				IF (flags - allowed # {}) THEN  flags := default; Error(200, scanner.errpos)  END;
				Check(right)
			END;
			IF  (flags = {PCM.Untraced}) & ~scope.module.sysImported  THEN  Error(135, scanner.errpos)  END;
		END TypeModifier;
		
		PROCEDURE IdentDef (VAR i: IdentDefDesc;  allowRO: BOOLEAN);			(* IdentDef = ident ["*"|"-"]. *)
		BEGIN
			i.vis := PCT.Internal;
			IF sym = ident THEN
				i.name := scanner.name; scanner.Get(sym)
			ELSE
				i.name := PCT.Anonymous;
				Error(ident, scanner.errpos)
			END;
			IF sym = times THEN
				i.vis := PCT.Public;  scanner.Get(sym)
			ELSIF sym = minus THEN
				IF allowRO THEN
					i.vis := PCT.Internal + {PCT.PublicR}
				ELSE
					i.vis := PCT.Public;  Error(47, scanner.errpos)
				END;
				scanner.Get(sym)
			END;
		END IdentDef;
		
		PROCEDURE OperatorDef(VAR i: IdentDefDesc; allowRO: BOOLEAN);
		VAR opName: PCS.Name;
		BEGIN
			i.vis:= PCT.Internal;
			StringPool.GetIndex(scanner.str, opName);
			i.name := opName;
			IF ~scanner.IsOperatorValid() THEN
				PCM.Error(142, scanner.errpos, "");
			END;
			scanner.Get(sym);
			IF sym = times THEN
				i.vis := PCT.Public; 
				scanner.Get(sym)
			ELSIF sym = minus THEN
				IF allowRO THEN
					i.vis := PCT.Internal + {PCT.PublicR}
				ELSE
					i.vis := PCT.Public;  Error(47, scanner.errpos)
				END;
				scanner.Get(sym)
			END;
		END OperatorDef;
		
		PROCEDURE FPSection(scope: PCT.ProcScope);
			VAR name: ARRAY 32 OF PCS.Name; i, n, res: LONGINT; VarPar: BOOLEAN;
				pos: ARRAY 32 OF LONGINT; t: PCT.Struct;
		BEGIN
			IF (sym = var) OR (sym = ident) THEN
				VarPar := sym = var;
				IF VarPar THEN scanner.Get(sym) END;
				n := 0;
				LOOP
					pos[n] := scanner.errpos;
					name[n] := scanner.name; INC(n);
					Check(ident);
					IF sym # comma THEN EXIT END;
					scanner.Get(sym)
				END;
				Check(colon); Type(t, noname);
				i := 0;
				WHILE i < n DO
					scope.CreatePar(PCT.Internal, VarPar, name[i], {}, t, res);
					IF res # PCT.Ok THEN PCM.ErrorN(res, pos[i], name[i]) END;
					INC(i)
				END
			END
		END FPSection;
			
		PROCEDURE FormalPars(scope: PCT.ProcScope; VAR rtype: PCT.Struct);
			VAR o: PCT.Symbol;
		BEGIN
			rtype := PCT.NoType;
			IF sym = lparen THEN
				scanner.Get(sym); FPSection(scope);
				WHILE sym = semicolon DO
					scanner.Get(sym); FPSection(scope)
				END;
				Check(rparen);
				IF sym = colon THEN
					scanner.Get(sym);
					IF sym = object THEN
						rtype := PCT.Ptr;
						scanner.Get(sym)
					ELSIF sym = array THEN
						scanner.Get(sym);
						ArrayType(rtype);
					ELSE
						Qualident(o);
						IF (o IS PCT.Type) THEN
							rtype := o.type
						ELSE
							Error(52, scanner.errpos);
							rtype := PCT.UndefType
						END
					END
				END
			END
		END FormalPars;
		
		PROCEDURE CheckOperator(scope: PCT.ProcScope; name: PCS.Name; rtype: PCT.Struct; pos: LONGINT);
		VAR
			opStr: ARRAY PCS.MaxStrLen OF CHAR;
			p: PCT.Parameter;
		
			PROCEDURE CheckCardinality(nofparam: LONGINT): BOOLEAN;
			BEGIN
				CASE opStr[0] OF
				| "+", "-": RETURN (nofparam = 1) OR (nofparam = 2)	
				| "~": RETURN (opStr[1] = 0X) & (nofparam = 1)
				ELSE RETURN nofparam = 2
				END;
			END CheckCardinality;
		
		BEGIN
			StringPool.GetString(name, opStr);
			IF ~CheckCardinality(scope.parCount) THEN
				Error(143, pos);	(* invalid number of formal parameters *)
			END;
			IF opStr = ":=" THEN
				IF rtype # PCT.NoType THEN
					Error(147, pos);	(* operator ":=" has no return value *)
				END;
				IF ~scope.firstPar.ref THEN
					Error(148, pos);	(* first parameter of ":=" must be VAR *)
				END;
				IF (scope.firstPar.type = scope.firstPar.nextPar.type) THEN
					PCM.Warning(-1, pos, "Warning: both parameters of identical type");
				END	
			ELSE
				IF rtype = PCT.NoType THEN
					Error(141, pos);	(* all other operators must have a return value *)
				END
			END;
			p := scope.firstPar;
			WHILE (p # NIL) & PCT.IsBasic(p.type) DO
				p := p.nextPar;
			END;
			IF p = NIL THEN
				Error(146, pos);	(* at least one parameter must not be a basic type *)
			END;
		END CheckOperator;
		
		PROCEDURE RecordType(VAR t: PCT.Struct;  pointed: BOOLEAN);
			VAR recstruct: PCT.Record; ptr: PCT.Pointer; recscope: PCT.RecScope; recparser: RecordParser; bpos, res: LONGINT;
				intf: ARRAY 32 OF PCT.Interface;
		BEGIN
			t := PCT.NoType;
			IF sym = lparen THEN scanner.Get(sym); bpos := scanner.errpos; Type(t, noname); Check(rparen) END;
			NEW(recscope); PCT.InitScope(recscope, scope, {PCT.SuperclassAvailable}, FALSE);
			IF pointed THEN
				ptr := PCT.NewClass(t, intf, recscope, FALSE, res);
				IF res # PCT.Ok THEN Error(res, bpos) END;
				recstruct := ptr.baseR;
				t := ptr
			ELSE
				recstruct := PCT.NewRecord(t, recscope, {}, FALSE, res);
				IF res # PCT.Ok THEN Error(res, bpos) END;
				t := recstruct
			END;
			PCT.AddRecord(scope, recstruct);
			NEW(recparser, sync, recscope, scanner, sym);	(* let the record parser take care of this *)
			SkipScope;
		END RecordType;
		
		PROCEDURE Interface(): PCT.Interface;
		VAR o: PCT.Symbol; p: PCT.Pointer;
		BEGIN
			Qualident(o);
			IF (o # NIL) & (o IS PCT.Type) & (o.type IS PCT.Pointer) THEN
				p := o.type(PCT.Pointer);
				IF (p.baseR # NIL) & (PCT.interface IN p.baseR.mode) THEN
					RETURN p
				END
			END;
			PCM.Error(200, scanner.errpos, "not a definition");
			RETURN NIL
		END Interface;
				
		PROCEDURE ObjectType(VAR t: PCT.Struct;  name: StringPool.Index);
			VAR recstruct: PCT.Record; ptr: PCT.Pointer; recscope: PCT.RecScope; parser: ObjectParser; bpos, res, i: LONGINT;
				intf: ARRAY 32 OF PCT.Interface;
				
		BEGIN
			t := PCT.NoType;
			IF sym = lparen THEN scanner.Get(sym); bpos := scanner.errpos; Type(t, noname); Check(rparen) END;
			IF sym = implements THEN
				INCL(PCM.codeOptions, PCM.UseDefinitions);	(* type declaration -> interface registration *)
				INCL(PCM.codeOptions, PCM.ExportDefinitions);
				scanner.Get(sym);
				i := 1;
				intf[0] := Interface();
				WHILE sym = comma DO
					scanner.Get(sym); intf[i] := Interface(); INC(i)
				END
			END;
			NEW(recscope); PCT.InitScope(recscope, scope, {PCT.SuperclassAvailable}, FALSE);
			ptr := PCT.NewClass(t, intf, recscope, FALSE, res);
			IF res # PCT.Ok THEN Error(res, bpos) END;
			recstruct := ptr.baseR;
			t := ptr;
			PCT.AddRecord(scope, recstruct);
			NEW(parser, sync, recscope, scanner, sym);	(* let the record parser take care of this *)
			SkipScope;
			IF name # noname THEN
				IF sym # ident THEN
					PCM.ErrorN(ident, scanner.errpos, name)
				ELSIF  name # scanner.name THEN
					PCM.ErrorN(4, scanner.errpos, name);  scanner.Get(sym)
				ELSE
					scanner.Get(sym)
				END
			END
		END ObjectType;
		
		PROCEDURE DefinitionType(pos: LONGINT;  VAR t: PCT.Struct;  name: StringPool.Index);
		VAR  intf: ARRAY 1 OF PCT.Interface; parser: InterfaceParser; recscope: PCT.RecScope; int: PCT.Interface; res: LONGINT;
		BEGIN
			INCL(PCM.codeOptions, PCM.ExportDefinitions);
			IF sym = refines THEN
				scanner.Get(sym);
				intf[0] := Interface()
			END;
			Check(semicolon);
			NEW(recscope); PCT.SetOwner(recscope); PCT.InitScope(recscope, scope, {PCT.SuperclassAvailable}, FALSE);
			int := PCT.NewInterface(intf, recscope, FALSE, res);
			IF res # PCT.Ok THEN Error(res, pos) END;
			t := int;
			PCT.AddRecord(scope, int.baseR);
			NEW(parser, sync, recscope, scanner, sym);
			WHILE sym # end DO  scanner.Get(sym)  END;
			scanner.Get(sym);
			IF name # noname THEN
				IF sym # ident THEN
					PCM.ErrorN(ident, scanner.errpos, name)
				ELSIF  name # scanner.name THEN
					PCM.ErrorN(4, scanner.errpos, name);  scanner.Get(sym)
				ELSE
					scanner.Get(sym)
				END
			END
		END DefinitionType;

		PROCEDURE ArrayType (VAR t: PCT.Struct);
		VAR	index: PCB.Expression;  array: PCT.Array;  pos0, pos, res: LONGINT; base: PCT.Struct;
		BEGIN
			pos0 := scanner.errpos;
			IF sym = of THEN
				scanner.Get(sym); pos := scanner.errpos; Type(base, noname);
				NEW(array); t := array;
				PCT.InitOpenArray(array, base, res);
				IF res # PCT.Ok THEN Error(res, pos) END
			ELSE
				SimpleExpr(index);
				IF sym = of THEN
					scanner.Get(sym); pos := scanner.errpos; Type(base, noname)
				ELSIF sym = comma THEN
					scanner.Get(sym); pos := scanner.errpos; ArrayType(base)
				ELSE
					Error(of, scanner.errpos);  t := PCT.UndefType;
					RETURN
				END;
				IF ~PCT.IsCardinalType(index.type) THEN
					Error(51, pos); t := PCT.UndefType
				ELSIF index IS PCB.Const THEN
					NEW(array); t := array;
					PCT.InitStaticArray(array, index(PCB.Const).con.int, base, res)
				ELSE
					t := PCB.NewDynSizedArray(index, base, res)
				END;
				IF res # PCT.Ok THEN Error(res, pos) END
			END
		END ArrayType;
		
		PROCEDURE PointerType(VAR t: PCT.Struct;  name: StringPool.Index);
			VAR pos, pos1, res: LONGINT; id: PCS.Name; o: PCT.Symbol; ptr: PCT.Pointer;
		BEGIN
			IF sym = record THEN
				scanner.Get(sym);  RecordType(t, TRUE)
			ELSIF sym # ident THEN
				pos1:=scanner.errpos;
				Type(t, noname);
				NEW(ptr); PCT.InitPointer(ptr, t, res); t := ptr;
				IF res # PCT.Ok THEN Error(res, pos1) END
			ELSE	(* ident own handling, because of forwards *)
				id := scanner.name;
				scanner.Get(sym);
				IF sym = period THEN	(* Mod.Type *)
					o := PCT.Find(scope, scope, id, PCT.structdeclared, TRUE);
					IF o = NIL THEN
						Error(0, scanner.errpos);
						o := PCB.unknownObj
					ELSIF o IS PCT.Module THEN
						scanner.Get(sym);
						IF sym = ident THEN
							o := PCT.Find(scope, o(PCT.Module).scope, scanner.name, PCT.complete, TRUE);
							scanner.Get(sym);
							IF o = NIL THEN  Error(0, scanner.errpos); o := PCB.unknownObj  END
						ELSE
							Error(ident, scanner.errpos);
							o := PCB.unknownObj
						END
					END
				ELSE	(* Type *)
					o := PCT.Find(scope, scope, id, PCT.local, TRUE);
				END;
				IF o = NIL THEN
					NEW(ptr);
					forwardPtr[nofForwardPtr].ptr := ptr;
					forwardPtr[nofForwardPtr].name := id;
					INC(nofForwardPtr);
					t := ptr
				ELSIF o IS PCT.Type THEN
					NEW(ptr); PCT.InitPointer(ptr, o.type, res); t := ptr;
					IF res # PCT.Ok THEN Error(res, pos) END
				ELSE
					Error(52, scanner.errpos);  t := PCT.UndefType
				END
			END
		END PointerType;
		
		PROCEDURE Type (VAR t: PCT.Struct;  name: StringPool.Index);
			VAR ptr: PCT.Pointer; o: PCT.Symbol; procscope: PCT.ProcScope;  pos, pos1, res: LONGINT; id: PCS.Name;
				proc: PCT.Delegate; sf: SET;
		BEGIN
			pos := scanner.errpos;
			IF sym = array THEN
				AosBoot.Inc(NArrays);
				scanner.Get(sym);  ArrayType(t)
			ELSIF sym = record THEN
				AosBoot.Inc(NRecords);
				scanner.Get(sym);  RecordType(t, FALSE);
			ELSIF sym = pointer THEN
				AosBoot.Inc(NPointers);
				scanner.Get(sym); Check(to); PointerType(t, noname);
			ELSIF sym = object THEN
				scanner.Get(sym);
				IF (sym = semicolon) OR (sym = rparen) THEN
					t := PCT.Ptr	(* generic OBJECT *)
				ELSE
					AosBoot.Inc(NObjects);
					ObjectType(t, name)
				END
			ELSIF sym = definition THEN
				AosBoot.Inc(NDefinitions);
				scanner.Get(sym);
				DefinitionType(pos, t, name)
			ELSIF sym = procedure THEN
				AosBoot.Inc(NProcedureTypes);
				scanner.Get(sym);
				TypeModifier(sf, {PCT.StaticMethodsOnly}, {PCT.StaticMethodsOnly});
				IF sf = {} THEN AosBoot.Inc(NDelegates) END;
				NEW(procscope); PCT.InitScope(procscope, scope, {}, FALSE); PCT.SetOwner(procscope);
				FormalPars (procscope, t);
				NEW(proc); PCT.InitDelegate(proc, t, procscope, sf, res);
				IF res # PCT.Ok THEN Error(res, pos) END;
				t := proc
			ELSE
				Qualident(o);
				IF (o IS PCT.Type) THEN
					t := o.type
				ELSE
					Error(52, scanner.errpos);  t := PCT.UndefType
				END
			END
		END Type;
		
		PROCEDURE VarDecl;
			VAR id: ARRAY MaxIdentDef OF IdentDefDesc;  c, n, res: LONGINT;  t: PCT.Struct;  flag: ARRAY MaxIdentDef OF SET;
		BEGIN n := 1;
			IdentDef (id[0], TRUE);
			TypeModifier(flag[0], {}, {PCM.Untraced});
			WHILE sym = comma DO
				scanner.Get(sym); IdentDef (id[n], TRUE);
				TypeModifier(flag[n], {}, {PCM.Untraced});
				INC(n)
			END;
			Check(colon); Type(t, noname);
			c := 0;
			WHILE c < n DO
				scope.CreateVar(id[c].name, id[c].vis, flag[c], t, res); INC(c);
				IF res # PCT.Ok THEN PCM.ErrorN(res, scanner.errpos, id[c-1].name) END
			END
		END VarDecl;
		
		PROCEDURE TypeDecl;
			VAR i: IdentDefDesc; pos, res: LONGINT; t: PCT.Struct;
		BEGIN
			pos := scanner.errpos;
			IdentDef(i, FALSE); Check(eql); Type(t, i.name);
			scope.CreateType(i.name, i.vis, t, res);
			IF res # PCT.Ok THEN PCM.ErrorN(res, pos, i.name) END;
		END TypeDecl;
		
		PROCEDURE ConstDecl;
			VAR i: IdentDefDesc; x: PCB.Const; pos, res: LONGINT;
		BEGIN
			pos := scanner.errpos;
			IdentDef(i, FALSE);  Check(eql);  ConstExpr(x);
			scope.CreateValue(i.name, i.vis, x.con, res);
			IF res # PCT.Ok THEN PCM.ErrorN(res, pos, i.name) END
		END ConstDecl;
		
		PROCEDURE FixForwards;
		VAR obj: PCT.Symbol; state: SHORTINT; res: LONGINT;
		BEGIN
			state := PCT.structallocated;
			IF isRecord THEN state := PCT.structdeclared END;
			WHILE nofForwardPtr > 0 DO
				DEC(nofForwardPtr);
				obj := PCT.Find(scope, scope, forwardPtr[nofForwardPtr].name, state, TRUE);
				IF obj = NIL THEN
					PCM.ErrorN(128, scanner.errpos, forwardPtr[nofForwardPtr].name); obj := PCB.unknownObj
				END;
				PCT.InitPointer(forwardPtr[nofForwardPtr].ptr, obj.type, res);
				IF res # PCT.Ok THEN Error(res, scanner.errpos) END
			END
		END FixForwards;
		
		PROCEDURE ListOf(parse: PROCEDURE);
		BEGIN
			scanner.Get(sym);
			WHILE sym = ident DO
				parse;
				REPEAT Check(semicolon) UNTIL sym # semicolon
			END
		END ListOf;
		
		PROCEDURE DeclSeq;
		VAR t: PCT.Struct; name: PCS.Name; pos, res: LONGINT;
		BEGIN
			WHILE sym = definition DO
				pos := scanner.errpos;
				scanner.Get(sym);
				name := scanner.name;
				Check(ident);
				DefinitionType(pos, t, name);
				Check(semicolon);
				scope.CreateType(name, PCT.Public, t, res);
				IF res # PCT.Ok THEN PCM.ErrorN(res, pos, name) END
			END;
			LOOP
				IF sym = const THEN
					scanner.Get(sym);
					WHILE sym = ident DO
						ConstDecl;
						REPEAT Check(semicolon) UNTIL sym # semicolon
					END
				ELSIF sym = type THEN
					scanner.Get(sym);
					WHILE sym = ident DO
						TypeDecl;
						REPEAT Check(semicolon) UNTIL sym # semicolon
					END
				ELSIF sym = var THEN
					scanner.Get(sym);
					WHILE sym = ident DO
						VarDecl;
						REPEAT Check(semicolon) UNTIL sym # semicolon
					END
				ELSE
					EXIT
				END
			END;
			FixForwards;
			PCT.ChangeState(scope, PCT.structdeclared, scanner.errpos);
			PCT.ChangeState(scope, PCT.structallocated, scanner.errpos);
			WHILE sym = procedure DO
				scanner.Get(sym); ProcDecl;
				IF sym # end THEN Check(semicolon) END
			END;
			PCT.ChangeState(scope, PCT.procdeclared, scanner.errpos)
		END DeclSeq;
		

		(* --------------------------------------------------------- *)
		(* Active Oberon Language Productions *)
		(* Implementation Section *)
		
		PROCEDURE Qualident (VAR o: PCT.Symbol);		(*Qualident = [ident "."] ident*)
			(* returns the object or unknownObj *)
			VAR pos: LONGINT;
		BEGIN
			IF sym = ident THEN
				IF scanner.name = self THEN
					o := PCT.Find(scope, scope, PCT.SelfName, PCT.procdeclared,  TRUE)
				ELSIF scope.state >= PCT.procdeclared THEN	(*parsing code*)
					o := PCT.Find(scope, scope, scanner.name, PCT.procdeclared, TRUE)
				ELSIF isRecord THEN
					o := PCT.Find(scope, scope, scanner.name, PCT.structdeclared, TRUE)	(*break scope <-> recordscope cycle*)
				ELSE
					o := PCT.Find(scope, scope, scanner.name, PCT.structallocated, TRUE)
				END;
				pos := scanner.errpos; scanner.Get(sym);
				IF o = NIL THEN
					Error(0, pos); o := PCB.unknownObj
				ELSIF (sym = period) & (o IS PCT.Module) THEN		(*semantic check needed because of language design*)
					scanner.Get(sym);
					IF sym = ident THEN
						o := PCT.Find(scope, o(PCT.Module).scope, scanner.name, PCT.procdeclared(*PCT.complete*), TRUE);
						scanner.Get(sym);
						IF o = NIL THEN Error(0, scanner.errpos);  o := PCB.unknownObj  END;
					ELSE Error(ident, scanner.errpos); 
					END
				END
			ELSE o := PCB.unknownObj; Error(ident, scanner.errpos);
			END;
		END Qualident;
		
		PROCEDURE GetModule(VAR o: PCT.Symbol);
		BEGIN
			IF sym = ident THEN
				o := PCT.Find(scope, scope, scanner.name, PCT.structallocated, TRUE);	
			ELSE
				o := PCB.unknownObj; Error(ident, scanner.errpos);
			END;
		END GetModule;
		
		PROCEDURE ExprList(VAR x: PCB.ExprList);
			VAR y: PCB.Expression;
		BEGIN
			Expr(y);  x.Append(y);
			WHILE sym = comma DO
				scanner.Get(sym); Expr(y);  x.Append(y)
			END
		END ExprList;
		
		PROCEDURE GetGuard(search: PCT.Scope; symbol: PCT.Symbol): PCT.Symbol;
		BEGIN
			WHILE search # NIL DO
				IF search IS PCT.WithScope THEN
					IF search(PCT.WithScope).withSym = symbol THEN
						RETURN search(PCT.WithScope).withGuard;
					END;
				END;
				search := search.parent;
			END;
			RETURN NIL;
		END GetGuard;
		
		PROCEDURE Designator(VAR x: PCB.Designator);
			VAR o: PCT.Symbol;  exp: PCB.Expression; y: PCB.Designator;
				guard: PCT.Symbol;
		BEGIN
			LOOP
				IF x IS PCB.Var THEN
					guard := GetGuard(scope, x(PCB.Var).obj);
					IF guard # NIL THEN
						x := PCB.NewGuard(scanner.errpos, x, guard, FALSE);
					END;
				ELSIF x IS PCB.Field THEN
					guard := GetGuard(scope, x(PCB.Field).field);
					IF guard # NIL THEN
						x := PCB.NewGuard(scanner.errpos, x, guard, FALSE);
					END
				END;
				IF sym = period THEN
					scanner.Get(sym);
					IF sym = ident THEN
						x := PCB.NewField(codescope, x, scanner.name, scanner.errpos);  scanner.Get(sym)	
					ELSE
						Error(ident, scanner.errpos)
					END	
				ELSIF sym = lbrak THEN
					scanner.Get(sym);
					LOOP
						Expr(exp);  x := PCB.NewIndex(scanner.errpos, x, exp);
						IF sym # comma THEN EXIT END;
						scanner.Get(sym)
					END;
					Check(rbrak)
				ELSIF sym = arrow THEN
					x := PCB.NewDeref(scanner.errpos, x);
					scanner.Get(sym)
				ELSIF (sym = lparen) & PCB.IsInterface(x) THEN
					INCL(PCM.codeOptions, PCM.UseDefinitions);	(* use lookup and call *)
					scanner.Get(sym);
					Qualident(o);
					y := PCB.MakeNode(scanner.errpos, codescope, o);
					Designator(y);
					Check(rparen);
					x := PCB.Interface(x, y)
				ELSIF (sym = lparen) & ~x.IsCallable() & (scope.state >= PCT.procdeclared) THEN			(*needs semantic check because of ambiguous language design*)
																															(*in declaration phase only expressions make sense!*)
					scanner.Get(sym); Qualident (o); Check(rparen);
					x:=PCB.NewGuard(scanner.errpos, x, o, FALSE)
				ELSE
					EXIT (* -> ENDLOOP *)
				END;
			END (* LOOP *)
		END Designator;
		
		PROCEDURE Element(VAR x: PCB.Expression);
			VAR y: PCB.Expression; pos: LONGINT;
		BEGIN
			Expr(x);
			IF sym = upto THEN
				pos:=scanner.errpos;
				scanner.Get(sym); Expr(y); x:=PCB.NewDOp(pos, PCC.setfn, x, y)	(*this operator cannot be overwritten*)
			ELSE
				x := PCB.NewMOp(scanner.errpos, NIL, PCC.setfn, x);	(*this operator cannot be overwritten*)
			END
		END Element;
		
		PROCEDURE Set(VAR x: PCB.Expression);
			VAR y: PCB.Expression; pos: LONGINT;
		BEGIN
			scanner.Get(sym);
			IF sym # rbrace THEN
				Element(x);
				WHILE sym = comma DO
					pos:=scanner.errpos;
					scanner.Get(sym); Element(y);  x := PCB.NewDOp(pos, plus, x, y);
				END
			ELSE
				x := PCB.NewSetValue(scanner.errpos, {})
			END;
			Check(rbrace)
		END Set;
		
		PROCEDURE Factor(VAR x: PCB.Expression);
		VAR el: PCB.ExprList;  d: PCB.Designator;  o: PCT.Symbol;
			pos: LONGINT;
			mod: PCT.Symbol;
		BEGIN
			pos := scanner.errpos;
			IF sym = number THEN
				CASE scanner.numtyp OF
				| PCS.char:	x := PCB.NewIntValue(scanner.errpos, scanner.intval, PCT.GetCharType(scanner.intval))
				| PCS.integer:	x := PCB.NewIntValue(scanner.errpos, scanner.intval, PCT.GetIntType(scanner.intval))
				| PCS.longinteger:	x := PCB.NewLongIntValue(scanner.errpos, scanner.longintval)
				| PCS.real:	x := PCB.NewFloatValue(scanner.errpos, scanner.realval, PCT.Float32)
				| PCS.longreal:	x := PCB.NewFloatValue(scanner.errpos, scanner.lrlval, PCT.Float64)
				END;
				scanner.Get(sym)
			ELSIF sym = string THEN
				x := PCB.NewStrValue(scanner.errpos, scanner.str);  scanner.Get(sym)
			ELSIF sym = nil THEN
				x:=PCB.NewNILValue(scanner.errpos); scanner.Get(sym)
			ELSIF sym = true THEN
				x := PCB.NewBoolValue(scanner.errpos, TRUE);  scanner.Get(sym)
			ELSIF sym = false THEN
				x := PCB.NewBoolValue(scanner.errpos, FALSE);  scanner.Get(sym)
			ELSIF sym = lbrace THEN	(*Set*)
				Set(x)
			ELSIF sym = lparen THEN	(*Subexpression*)
				scanner.Get(sym); Expr(x) ; Check(rparen)
			ELSIF (sym=not) THEN
				scanner.Get(sym);
				IF (sym = lbrak) & ~(PCM.NoOpOverloading IN PCM.parserOptions) THEN
					scanner.Get(sym);
					GetModule(mod);
					scanner.Get(sym);
					Check(rbrak);
				END;
				Factor(x);
				IF (PCM.NoOpOverloading IN PCM.parserOptions) OR PCT.IsBasic(x.type) THEN
					x := PCB.NewMOp(scanner.errpos, scope, not, x)
				ELSE
					x := CallMOperator(not, mod, x, pos);
				END;
			ELSIF (sym = ident) THEN
				Qualident(o);
				IF o IS PCT.Value THEN x := PCB.NewValue(scanner.errpos, o)
				ELSE d := PCB.MakeNode(scanner.errpos, codescope, o); Designator(d);
					IF (sym = lparen)  THEN
						el:=PCB.NewExprList(scanner.errpos, d);
						scanner.Get(sym);
						IF sym # rparen THEN ExprList(el) END;
						Check(rparen);
						x := PCB.NewFuncCall(scanner.errpos, d, el, scopelevel)
					ELSE x := d
					END
				END
			ELSE
				Error(13, scanner.errpos); x:=PCB.InvalidExpr;  scanner.Get(sym)
			END
		END Factor;
		
		PROCEDURE Term(VAR x: PCB.Expression);
			VAR
				y, xTmp: PCB.Expression;  op: PCS.Token; pos: LONGINT;
				mod: PCT.Symbol;
		BEGIN
			Factor(x); 
			WHILE (sym >= times) & (sym <= and) DO
				pos:=scanner.errpos;  op := sym;  scanner.Get(sym);
				mod := NIL;
				IF (sym = lbrak) & ~((PCM.NoOpOverloading IN PCM.parserOptions) OR PCT.IsBasic(x.type)) THEN
					scanner.Get(sym);
					GetModule(mod);
					scanner.Get(sym);
					Check(rbrak);
				END;
				Factor(y);
				
				IF (PCM.NoOpOverloading IN PCM.parserOptions) OR (PCT.IsBasic(x.type) & PCT.IsBasic(y.type)) THEN
					x := PCB.NewDOp(pos, op, x, y)
				ELSE
					x := CallDOperator(op, mod, x, y, pos);
				END
			END
		END Term;

		PROCEDURE CallAssignmentOp(op: PCS.Token; mod: PCT.Symbol; p1: PCB.Designator; p2: PCB.Expression; pos: LONGINT; suppress: BOOLEAN);
		VAR
			pars: ARRAY 2 OF PCT.Struct;
			name: PCS.Name; o: PCT.Symbol; d: PCB.Designator; el: PCB.ExprList;
			i: LONGINT;
			parents: BOOLEAN;
			searchScope: PCT.Scope;
		BEGIN
			PCS.GetOpName(op, name);
			IF (mod # NIL) & (mod IS PCT.Module) THEN
				searchScope := mod(PCT.Module).scope;
				parents := FALSE;
			ELSE
				searchScope := scope;
				parents := TRUE;
			END;
			(* o := GetOperator(name, pars^, pos); *)
			pars[0] := p1.type; pars[1] := p2.type;
			o := PCT.FindOperator(scope, searchScope, parents, name, pars, pos);
			
			IF o = NIL THEN
				(* Error(137, pos);	(* operator not defined *) *)
				PCB.Assign(code, suppress, p1, p2);
			ELSE
				d := PCB.MakeNode(pos, codescope, o);
				Designator(d);
				el := PCB.NewExprList(pos, d);
				el.Append(p1);
				el.Append(p2);
				(* RETURN PCB.NewFuncCall(pos, d, el, scopelevel); *)
				PCB.CallProc(code, suppress, d, el,scopelevel);
			END;
		END CallAssignmentOp;
			
		PROCEDURE CallMOperator(op: PCS.Token; mod: PCT.Symbol; p1: PCB.Expression; pos: LONGINT): PCB.Expression;
		VAR
			pars1: ARRAY 1 OF PCT.Struct;
			name: PCS.Name; o: PCT.Symbol; d: PCB.Designator; el: PCB.ExprList;
			parents: BOOLEAN;
			searchScope: PCT.Scope;
		BEGIN
			PCS.GetOpName(op, name);
			IF (mod # NIL) & (mod IS PCT.Module) THEN
				searchScope := mod(PCT.Module).scope;
				parents := FALSE;
			ELSE
				searchScope := scope;
				parents := TRUE;
			END;
			pars1[0] := p1.type;
			o := PCT.FindOperator(scope, searchScope, parents, name, pars1, pos);
			IF o = NIL THEN
				(* Error(137, pos);	(* operator not defined *) *)
				RETURN PCB.NewMOp(pos, scope, op, p1);
			END;
			d := PCB.MakeNode(pos, codescope, o);
			Designator(d);
			el := PCB.NewExprList(pos, d);
			el.Append(p1);
			RETURN PCB.NewFuncCall(pos, d, el, scopelevel);
		END CallMOperator;
				
		PROCEDURE CallDOperator(op: PCS.Token; mod: PCT.Symbol; p1, p2: PCB.Expression; pos: LONGINT): PCB.Expression;
		VAR
			pars2: ARRAY 2 OF PCT.Struct;
			name: PCS.Name; o: PCT.Symbol; d: PCB.Designator; el: PCB.ExprList;
			parents: BOOLEAN;
			searchScope: PCT.Scope;
		BEGIN
			PCS.GetOpName(op, name);
			IF (mod # NIL) & (mod IS PCT.Module) THEN
				searchScope := mod(PCT.Module).scope;
				parents := FALSE;
			ELSE
				searchScope := scope;
				parents := TRUE;
			END;
			pars2[0] := p1.type; pars2[1] := p2.type;
			o := PCT.FindOperator(scope, searchScope, parents, name, pars2, pos);
			
			IF o = NIL THEN
				(* Error(137, pos);	(* operator not defined *) *)
				RETURN PCB.NewDOp(pos, op, p1, p2);
			END;
			d := PCB.MakeNode(pos, codescope, o);
			Designator(d);
			el := PCB.NewExprList(pos, d);
			el.Append(p1);
			el.Append(p2);
			RETURN PCB.NewFuncCall(pos, d, el, scopelevel);
		END CallDOperator;
				
		PROCEDURE SimpleExpr(VAR x: PCB.Expression); 
			VAR y: PCB.Expression;  op: PCS.Token;  pos: LONGINT;
				mod: PCT.Symbol;
		BEGIN
			IF (sym = plus) OR (sym = minus) THEN
				pos := scanner.errpos;
				op := sym;  scanner.Get(sym);
				IF (sym = lbrak) & ~(PCM.NoOpOverloading IN PCM.parserOptions) THEN
					scanner.Get(sym);
					GetModule(mod);
					scanner.Get(sym);
					Check(rbrak);
				END;
				Term(x);
				IF (PCM.NoOpOverloading IN PCM.parserOptions) OR PCT.IsBasic(x.type) THEN
					x := PCB.NewMOp(pos, scope, op, x)
				ELSE		
					x := CallMOperator(op, mod, x, pos);
				END
			ELSE
				Term(x)
			END;
			WHILE (sym >= plus) & (sym <= or) DO
				pos:=scanner.errpos;
				op := sym;  scanner.Get(sym);
				mod := NIL;
				IF (sym = lbrak) & ~((PCM.NoOpOverloading IN PCM.parserOptions) OR PCT.IsBasic(x.type)) THEN
					scanner.Get(sym);
					GetModule(mod);
					scanner.Get(sym);
					Check(rbrak);
				END;
				Term(y);
				IF (PCM.NoOpOverloading IN PCM.parserOptions) OR (PCT.IsBasic(x.type) & PCT.IsBasic(y.type)) THEN
					x := PCB.NewDOp(pos, op, x, y)
				ELSE
					x := CallDOperator(op, mod, x, y, pos);
				END
			END
		END SimpleExpr;
		
		PROCEDURE Expr(VAR x: PCB.Expression);
			VAR y: PCB.Expression;  op: PCS.Token; pos: LONGINT;
				mod: PCT.Symbol;
		BEGIN
			SimpleExpr(x);
			IF (sym >= eql) & (sym <= is) THEN
				pos:=scanner.errpos;
				op := sym;  scanner.Get(sym);
				IF (sym = lbrak) & ~((PCM.NoOpOverloading IN PCM.parserOptions) OR PCT.IsBasic(x.type)) THEN
					scanner.Get(sym);
					GetModule(mod);
					scanner.Get(sym);
					Check(rbrak);
				END;
				SimpleExpr(y);
				IF (PCM.NoOpOverloading IN PCM.parserOptions) OR (PCT.IsBasic(x.type) & PCT.IsBasic(y.type)) THEN
					x := PCB.NewDOp(pos, op, x, y)
				ELSE
					x := CallDOperator(op, mod, x, y, pos);
				END
			END
		END Expr;
		
		PROCEDURE ConstExpr(VAR x: PCB.Const);
			VAR pos: LONGINT; y: PCB.Expression;
		BEGIN
			pos := scanner.errpos;
			Expr(y);
			x := PCB.ConstExpression(pos, y)
		END ConstExpr;
		
		PROCEDURE Case(suppress: BOOLEAN;  VAR  caseinfo: PCB.CaseInfo);
			VAR x, y: PCB.Const; firstline: BOOLEAN;
		BEGIN
			firstline := TRUE;
			LOOP
				ConstExpr(x);  y := x;
				IF sym = upto THEN
					scanner.Get(sym); ConstExpr(y);
				END;
				PCB.CaseLine(code, suppress, caseinfo, x, y, firstline);
				firstline := FALSE;
				IF sym # comma THEN EXIT END;
				scanner.Get(sym)
			END;
			Check(colon);
			StatementSeq(suppress)
		END Case;
		
		PROCEDURE If(suppress: BOOLEAN);
			VAR cond: PCB.Expression; info: PCB.LoopInfo;  ifsuppress, elsifclause: BOOLEAN;
		BEGIN
			(* if/elsif already checked *)
			elsifclause := FALSE;
			LOOP
				Expr(cond); Check(then);
				ifsuppress := PCB.If(code, suppress, info, cond, elsifclause);
				StatementSeq(suppress OR ifsuppress);
				IF sym # elsif THEN EXIT END;
				elsifclause := TRUE;
				scanner.Get(sym);
			END;
			IF sym = else THEN
				scanner.Get(sym);
				ifsuppress := PCB.Else(code, suppress, info);
				StatementSeq(suppress OR ifsuppress)
			END;
			PCB.EndIf(code, info);
			Check(end)
		END If;
		
		PROCEDURE BlockModifier(allowBody: BOOLEAN; VAR locked: BOOLEAN);
			VAR x: PCB.Const; c, res: LONGINT;
		BEGIN
			IF sym = lbrace THEN
				scanner.Get(sym);
				locked := FALSE;
				LOOP
					IF sym = ident THEN
						IF scanner.name = exclusive  THEN
							AosBoot.Inc(NExclusive);
							IF allowBody THEN AosBoot.Inc(NExclusiveMain) END;
							PCT.SetMode(scope, PCT.exclusive, res);
							scanner.Get(sym);
							locked := TRUE
						ELSIF allowBody & (scanner.name = active)  THEN
							AosBoot.Inc(NActive);
							PCT.SetMode(scope, PCT.active, res);
							scanner.Get(sym)
						ELSIF allowBody & (scanner.name = safe)  THEN
							PCT.SetMode(scope, PCT.safe, res);
							scanner.Get(sym)
						ELSIF allowBody & (scanner.name = priority)  THEN
							scanner.Get(sym);
							IF sym = lparen THEN
								scanner.Get(sym); ConstExpr(x); Check(rparen);
								IF ~PCT.IsCardinalType(x.type) THEN
									c:=0;  Error(51, scanner.errpos)
								ELSIF x.type # PCT.Int8 THEN
									c := 0; Error(220, scanner.errpos)
								ELSE
									c := x.con.int
								END
							ELSE
								c:=0
							END;
							IF isRecord THEN
								scope.parent(PCT.RecScope).owner.prio := c
							ELSE
								PCM.Error(200, scanner.errpos, "priority only for records")
							END
						ELSE  Error(0, scanner.errpos); scanner.Get(sym) (*skip the ident, probably a typo*)
						END;
						IF res # PCT.Ok THEN Error(res, scanner.errpos); res := 0 END
					END;
					IF sym # comma THEN EXIT END;
					scanner.Get(sym)
				END;
				Check(rbrace)
			END
		END BlockModifier;
		
		PROCEDURE StatementBlock(body, suppress: BOOLEAN);
		VAR  lock: BOOLEAN;
		BEGIN
			(*sym = begin*)
			scanner.Get(sym);
			BlockModifier(body, lock);
			IF body & notifyScope THEN  PCT.ChangeState(scope.parent, PCT.modeavailable, scanner.errpos)  END;	(*NEW waits for it*)
			IF lock THEN
				IF locked THEN  Error(246, scanner.errpos) END;
				locked := TRUE;
				unlockOnExit := looplevel > 0;
				PCB.Lock(code, scope, scanner.errpos, TRUE);
				StatementSeq(suppress);
				PCB.Lock(code, scope, scanner.errpos, FALSE);
				unlockOnExit := FALSE;
				locked := FALSE
			ELSE
				StatementSeq(suppress)
			END;
			Check(end)
		END StatementBlock;
		
		PROCEDURE StatementSeq(suppress: BOOLEAN);
			VAR  d, d1: PCB.Designator; x, y: PCB.Expression; c: PCB.Const; o, o1: PCT.Symbol;
				param: PCB.ExprList;  pos, res: LONGINT;
				oldscope: PCT.Scope; s: PCT.WithScope; loopinfo: PCB.LoopInfo;  caseinfo: PCB.CaseInfo;
				first, ifsuppress, oldUnlockOnExit: BOOLEAN;
				oldforcount: SHORTINT;
				mod: PCT.Symbol;
				oldWith: BOOLEAN; oldWithGuard: PCT.Symbol; oldWithScope: PCT.Scope;
		BEGIN
			LOOP
				IF (sym < ident) THEN
					Error(ident, scanner.errpos);
					REPEAT  scanner.Get(sym)  UNTIL  sym >= ident
				END;
				pos:=scanner.errpos;
				PCC.NewInstr(code, pos);
				CASE sym OF
				| ident:
						Qualident(o);
						d := PCB.MakeNode(scanner.errpos, codescope, o); Designator(d);
						IF sym = becomes THEN
							scanner.Get(sym);  
							mod := NIL;
							IF (sym = lbrak) & ~((PCM.NoOpOverloading IN PCM.parserOptions) OR PCT.IsBasic(d.type)) THEN
								scanner.Get(sym);
								GetModule(mod);
								scanner.Get(sym);
								Check(rbrak);
							END;
							Expr(y);
							IF (PCM.NoOpOverloading IN PCM.parserOptions) OR (PCT.IsBasic(d.type) & PCT.IsBasic(y.type)) THEN
								PCB.Assign(code, suppress, d, y);
							ELSE
								CallAssignmentOp(becomes, mod, d, y, scanner.errpos, suppress)
							END
						ELSE
							param:=PCB.NewExprList(scanner.errpos, d);
							IF sym = lparen THEN
								scanner.Get(sym);
								IF sym # rparen THEN  ExprList(param)  END;
								Check(rparen)
							END;
							PCB.CallProc(code, suppress, d, param, scopelevel)
						END (* if -> proccall *)
				| if:
						scanner.Get(sym); If(suppress)
				| with:
						first := TRUE;
						REPEAT
							IF (sym = bar) & first THEN
								PCM.Error(end, scanner.errpos, "Oberon-2 WITH not supported");
								first := FALSE
							END;
							scanner.Get(sym);	(*skip with or bar *)
							IF sym = ident THEN
								Qualident(o);
								IF o = NIL THEN  Error(0,  scanner.errpos);  o := PCB.unknownObj  END;
								d:=PCB.MakeNode(scanner.errpos, codescope, o); 
							ELSE
								Error(ident, scanner.errpos);  d:=PCB.InvalidDesig
							END;
							Check(colon); Qualident(o1);  d1:=PCB.MakeNode(scanner.errpos, codescope, o1);
							NEW(s); PCT.InitScope(s, scope, {}, FALSE); PCT.SetOwner(s);
							IF (o # NIL) & (o IS PCT.Variable) THEN
									s.withSym := o;
									s.withGuard := o1;
							ELSE
								Error(130, pos);
							END;
							oldscope := scope;  scope := s;
							PCT.ChangeState(s, PCT.complete, scanner.errpos);
							Check(do);
							ifsuppress := PCB.If(code, suppress, loopinfo, PCB.NewMOp(scanner.errpos, NIL, not, PCB.NewDOp(scanner.errpos, is, d, d1)), FALSE);
							PCB.Trap(code, suppress OR ifsuppress, PCM.WithTrap);
							ifsuppress := PCB.Else(code, suppress, loopinfo);
							StatementSeq(suppress OR ifsuppress);
							PCB.EndIf(code, loopinfo);		
							scope := oldscope;
						UNTIL sym # bar;
						IF sym = else THEN
							IF first THEN PCM.Error(end, scanner.errpos, "Oberon-2 WITH not supported") END;
							scanner.Get(sym);
							StatementSeq(TRUE)
						END;
						Check(end)
				| case:
						scanner.Get(sym); Expr(x); Check(of);
						PCB.Case(code, suppress, caseinfo, x);
						LOOP
							IF sym < bar THEN Case(suppress, caseinfo) END;
							IF sym = bar THEN scanner.Get(sym) ELSE EXIT END
						END;
						PCB.CaseElse(code, suppress, caseinfo);
						IF sym = else THEN
							scanner.Get(sym); StatementSeq(suppress)
						ELSE
							PCB.Trap(code, suppress, PCM.CaseTrap)
						END;
						PCB.CaseEnd(code, suppress, caseinfo);
						Check(end);
				| while:
						scanner.Get(sym); Expr(x); pos := scanner.errpos; Check(do);
						PCB.While(code, suppress, loopinfo, x);
						StatementSeq(suppress); Check(end);
						PCB.EndLoop(code, suppress, loopinfo);
				| repeat:
						PCB.BeginLoop(code, loopinfo);
						scanner.Get(sym); StatementSeq(suppress);  Check(until); Expr(x);
						PCB.Repeat(code, suppress, loopinfo, x);
				| for:
						scanner.Get(sym);
						IF sym = ident THEN
							o:=PCT.Find(scope, scope, scanner.name, PCT.structallocated, TRUE);
							IF o = NIL THEN  Error(0, scanner.errpos);  o := PCB.unknownObj  END;
							d:=PCB.MakeNode(scanner.errpos, codescope, o); scanner.Get(sym)
						ELSE
							Error(ident, scanner.errpos);  d:=PCB.InvalidDesig
						END;
						Check(becomes); Expr(x);
						Check(to); Expr(y);
						IF sym = by THEN  scanner.Get(sym); ConstExpr(c)  ELSE  c:=PCB.NewIntValue(scanner.errpos, 1, PCT.Int8)(*PCB.One*)  END;
						PCB.BeginFor(code, suppress, pos, d, x, y, c, loopinfo);
						INC(forcount);
						Check(do); StatementSeq(suppress); Check(end);
						DEC(forcount);
						PCB.EndFor(code, suppress, pos, d, c, loopinfo)
				| loop:
						oldforcount := forcount; forcount := 0;
						loopinfo := curloop;  INC(looplevel);
						oldUnlockOnExit := unlockOnExit; unlockOnExit := FALSE;
						PCB.BeginLoop(code, curloop);
						scanner.Get(sym); StatementSeq(suppress); Check(end);
						PCB.EndLoop(code, suppress, curloop);
						unlockOnExit := oldUnlockOnExit;
						curloop := loopinfo;  DEC(looplevel);
						forcount := oldforcount
				| exit:
						pos:=scanner.errpos; scanner.Get(sym);
						IF looplevel = 0 THEN
							Error(exit, scanner.errpos)
						ELSE
							IF unlockOnExit THEN
								PCB.Lock(code, scope, scanner.errpos, FALSE);
							END;
							PCB.Exit(code, suppress, curloop, forcount);
							suppress := TRUE
						END
				| return:
						scanner.Get(sym);
						IF sym < semicolon THEN  Expr(x);  ELSE  x := NIL  END;
						PCB.Return(code, suppress, codescope, pos, x, locked);		(*use the declaration scope!*)
						suppress := TRUE
				| passivate:
						scanner.Get(sym);
						Expr(x);
						PCB.Await(code, suppress, scope, pos, x)
				| begin:
						StatementBlock(FALSE, suppress)
				ELSE
					(* Error(end) *)
				END;
				
				IF sym = semicolon THEN scanner.Get(sym)
				ELSIF (sym <= ident) OR (if <= sym) & (sym <= return) THEN Error(semicolon, scanner.errpos)
				ELSE EXIT
				END
			END (*loop*)
		END StatementSeq;
		
		PROCEDURE Body;
		VAR
			name: ARRAY 32 OF CHAR;
			export: BOOLEAN;
		BEGIN
			IF sym = begin THEN
				PCT.GetScopeName(scope, name);
				IF inline THEN  Error(200, scanner.errpos)  END;
				code := PCB.Enter(scope);
				StatementBlock(TRUE, FALSE);
				PCB.Leave(code, scope, FALSE)
			ELSIF sym = codeToken THEN
				export := (scope IS PCT.ModScope) OR 
					((scope IS PCT.ProcScope) & (PCT.Public * scope(PCT.ProcScope).ownerO.vis # {}));
				IF Assemble = NIL THEN	(*no assembler installed*)
					PCM.Error(0, scanner.errpos, "no assembler available")
				ELSIF inline THEN
					scope.code := Assemble(scanner, scope, export, TRUE)
				ELSE
					code := PCB.Enter(scope);
					PCB.Inline(code, Assemble(scanner, scope, export, FALSE));
					PCB.Leave(code, scope, TRUE)
				END;
				REPEAT scanner.Get(sym) UNTIL (sym = end) OR (sym = eof);
				Check(end)
			ELSE
				code := PCB.Enter(scope);
				PCB.Leave(code, scope, FALSE);
				IF (sym = var) OR (sym = const) OR (sym = type) THEN
					PCM.Error(43, scanner.errpos, "data decl after proc decl")
				ELSIF (sym # end) THEN
					Error(43, scanner.errpos)
				ELSE
					scanner.Get(sym)
				END
			END;
		END Body;
		
		PROCEDURE ProcDecl;
		VAR	procparser: ProcedureParser; procscope: PCT.ProcScope; pos, res: LONGINT;
			i: IdentDefDesc; flags: SET; rtype: PCT.Struct; forward, suppress: BOOLEAN;
			opName: PCS.Name;
		BEGIN
			flags := {}; forward := FALSE;
			CASE sym OF
			| minus:
				flags := {PCT.Inline}; scanner.Get(sym)
			| and:
				flags := {PCT.Constructor};  scanner.Get(sym)
			| times:
				(*compatibility with Ceres, ignore*)
				scanner.Get(sym)
			| arrow:
				forward := TRUE; scanner.Get(sym)
			ELSE
			END;
			pos:=scanner.errpos;
			IF PCM.NoOpOverloading IN PCM.parserOptions THEN
				IF (sym = string) OR (sym = number) & (scanner.numtyp = PCS.char) THEN
					suppress := TRUE;
					PCM.Error(200, scanner.errpos, "operators not supported")
				END;
				IdentDef(i, FALSE);
			ELSE
				IF (sym = string) OR (sym = number) & (scanner.numtyp = PCS.char) THEN
					OperatorDef(i, FALSE);
					INCL(flags, PCT.Operator);
					IF scope IS PCT.RecScope THEN
						PCM.Error(140, scanner.errpos, "");
					END;
				ELSE
					IdentDef(i, FALSE);
				END;
			END;
			
			NEW(procscope); PCT.InitScope(procscope, scope, {PCT.AutodeclareSelf}, FALSE);
			PCT.SetOwner(procscope);
			FormalPars(procscope, rtype);
			IF PCT.Operator IN flags THEN CheckOperator(procscope, i.name, rtype, pos) END;
			IF forward THEN RETURN END;	(*don't register this procedure, just ignore it*)
			Check(semicolon);
			scope.CreateProc(i.name, i.vis, flags, procscope, rtype, res);
			IF res # PCT.Ok THEN PCM.ErrorN(res, pos, i.name) END;
			NEW(procparser, sync, procscope, PCT.Inline IN flags, scanner, sym);	(*parse the rest of scope*)
			SkipScope;	(* skip the record scope, the other parser is parsing it *)
			IF suppress THEN
				scanner.Get(sym)				
			ELSIF (sym = string) OR (sym = number) & (scanner.numtyp = PCS.char) THEN
				StringPool.GetIndex(scanner.str, opName);
				IF opName # i.name THEN PCM.ErrorN(4, scanner.errpos, i.name) END;
				scanner.Get(sym);
			ELSIF sym = ident THEN
				IF scanner.name # i.name THEN PCM.ErrorN(4, scanner.errpos, i.name) END;	(*[S8;1;2]*)
				scanner.Get(sym)
			ELSE PCM.ErrorN(ident, scanner.errpos, i.name)
			END
		END ProcDecl;
		
		PROCEDURE SkipScope;
		VAR cnt: LONGINT;
		BEGIN
			(*skip decl section*)
			WHILE (sym # eof) & (sym # begin) & (sym # end) & (sym # codeToken) DO
				IF (sym = record) THEN
					scanner.Get(sym); SkipScope
				ELSIF (sym = object) THEN
					scanner.Get(sym);
					IF (sym # semicolon) & (sym # rparen) THEN SkipScope END
				ELSIF sym = procedure THEN
					scanner.Get(sym);
					IF (sym = and) OR (sym = minus) THEN scanner.Get(sym) END;
					IF (sym = ident) OR (sym = string) OR (sym =  number) & (scanner.numtyp = PCS.char) THEN SkipScope END
				ELSE
					scanner.Get(sym)
				END
			END;
			(*skip statseq *)
			IF sym = begin THEN
				scanner.Get(sym); cnt := 1;
				WHILE cnt > 0 DO
					IF (sym = if) OR (sym = case) OR (sym = while) OR (sym = for) OR (sym = loop) OR (sym = with) OR (sym = begin) THEN
						INC(cnt)
					ELSIF sym = end THEN
						DEC(cnt)
					ELSIF sym = eof THEN
						cnt := 0
					END;
					scanner.Get(sym)
				END
			ELSIF sym = codeToken THEN
				REPEAT scanner.Get(sym) UNTIL (sym = end) OR (sym = eof);
				scanner.Get(sym)
			ELSIF sym = end THEN
				scanner.Get(sym);
			END;
		END SkipScope;

	BEGIN {ACTIVE}
		IF die THEN  sync.Exit;  RETURN  END;
		PCT.SetOwner(scope);
		DeclSeq;
		Body;
		PCT.ChangeState(scope, PCT.complete, scanner.errpos);
		sync.Exit
	END Parser;

	ObjectParser = OBJECT (Parser)

		PROCEDURE Body;	(*override Parser.Body*)
		VAR bodyscope: PCT.ProcScope; old: PCT.Scope; res: LONGINT;
		BEGIN
			IF sym = begin THEN
				old := scope;
				NEW(bodyscope); PCT.InitScope(bodyscope, scope, {PCT.AutodeclareSelf}, FALSE); PCT.SetOwner(bodyscope);
				scope.CreateProc(PCT.BodyName, PCT.Public, {}, bodyscope, PCT.NoType, res); ASSERT(res = PCT.Ok);
				(*PCT.ChangeState(scope, PCT.complete);	don't know if active yet!*)
				PCT.ChangeState(bodyscope, PCT.procdeclared, scanner.errpos);
				scope := bodyscope; codescope := scope;
				notifyScope := TRUE;
				Body^;
				PCT.ChangeState(bodyscope, PCT.complete, scanner.errpos);
				scope := old; codescope := scope
			ELSE
				IF (sym = var) OR (sym = const) OR (sym = type) THEN
					PCM.Error(43, scanner.errpos, "data decl after proc decl")
				ELSIF (sym # end) THEN
					Error(43, scanner.errpos)
				ELSE
					scanner.Get(sym)
				END
			END
		END Body;
		
		PROCEDURE DeclSeq;	(* vars and procs are allowed, no const and types *)
		BEGIN
			LOOP
				(* allow ident w/o var, to minimize the misleading err 83 in the rest of the module *)
				IF (sym = var) OR (sym = ident) THEN
					IF sym = var THEN scanner.Get(sym) ELSE PCM.Error(end, scanner.errpos, "or maybe VAR") END;
					WHILE sym = ident DO
						VarDecl;
						IF sym # end THEN
							REPEAT Check(semicolon) UNTIL sym # semicolon
						END;
					END
				ELSIF sym = semicolon THEN  scanner.Get(sym)
				ELSE EXIT
				END
			END;
			FixForwards;
			PCT.ChangeState(scope, PCT.structdeclared, scanner.errpos);
			PCT.ChangeState(scope, PCT.structallocated, scanner.errpos);
			WHILE sym = procedure DO
				scanner.Get(sym); ProcDecl;
				IF sym # end THEN Check(semicolon) END
			END;
			(* -> complete state set in body *)
		END DeclSeq;
		
		PROCEDURE & InitRec(sync: Barrier; recscope: PCT.RecScope; s: PCS.Scanner; sym: PCS.Token);
		BEGIN
			sync.Enter; SELF.sync := sync;
			isRecord := TRUE;
			scope := recscope; codescope := recscope; SELF.sym := sym; scopelevel := 0; looplevel := 0;
			scanner := PCS.ForkScanner(s);
		END InitRec;
	END ObjectParser;
	
	
	RecordParser = OBJECT (Parser)
		
		PROCEDURE Body;
		BEGIN
			Check(end)
		END Body;
		
		PROCEDURE DeclSeq;	(* the DeclSeq of a record is a simplified DeclSeq, but nevertheless different *)
		BEGIN
			LOOP
				IF sym = semicolon THEN scanner.Get(sym)
				ELSIF sym = ident THEN VarDecl
				ELSE EXIT
				END
			END;
			FixForwards;	(*anonymous declaration possible!*)
			PCT.ChangeState(scope, PCT.procdeclared, scanner.errpos)
		END DeclSeq;
	
		PROCEDURE & InitRec(sync: Barrier; recscope: PCT.RecScope; s: PCS.Scanner; sym: PCS.Token);
		BEGIN
			sync.Enter; SELF.sync := sync;
			isRecord := TRUE;
			scope := recscope; codescope := recscope; SELF.sym := sym; scopelevel := 0; looplevel := 0;
			scanner := PCS.ForkScanner(s);
		END InitRec;
	END RecordParser;

	InterfaceParser = OBJECT (Parser)

		PROCEDURE Body;
		BEGIN
			Check(end)
		END Body;
		
		PROCEDURE DeclSeq;
			VAR name: PCS.Name; procscope: PCT.ProcScope;  t: PCT.Struct; pos, res: LONGINT;
		BEGIN
			WHILE sym = procedure DO
				pos := scanner.errpos;
				scanner.Get(sym);
				name := scanner.name;
				Check(ident);
				NEW(procscope); PCT.InitScope(procscope, scope, {PCT.AutodeclareSelf}, FALSE); PCT.SetOwner(procscope);
				FormalPars (procscope, t);
				scope.CreateProc(name, PCT.Public, {}, procscope, t, res);
				IF res # PCT.Ok THEN PCM.ErrorN(res, pos, name) END;
				Check(semicolon);
				PCT.ChangeState(procscope, PCT.structdeclared, scanner.errpos)
			END;
			PCT.ChangeState(scope, PCT.procdeclared, scanner.errpos)
		END DeclSeq;
	
		PROCEDURE & InitRec(sync: Barrier; recscope: PCT.RecScope; s: PCS.Scanner; sym: PCS.Token);
		BEGIN
			sync.Enter; SELF.sync := sync;
			isRecord := TRUE;
			scope := recscope; codescope := recscope; SELF.sym := sym; scopelevel := 0; looplevel := 0;
			scanner := PCS.ForkScanner(s);
		END InitRec;
	END InterfaceParser;


	(* Parse a procedure, beginning from the parameters to the END. This only fills the scope,
	the symbol has to be inserted by the caller *)
	ProcedureParser =  OBJECT (Parser)

		PROCEDURE & InitProc(sync: Barrier; procscope: PCT.ProcScope; inline: BOOLEAN;  VAR s: PCS.Scanner;  sym: PCS.Token);
		BEGIN
			sync.Enter; SELF.sync := sync;
			SELF.inline := inline;
			scope := procscope; codescope := procscope; scanner := s; SELF.sym := sym;
			scopelevel := procscope.ownerO.level; looplevel := 0;
			scanner := PCS.ForkScanner(s)
		END InitProc;
		
	END ProcedureParser;


	ModuleParser = OBJECT (Parser)
		VAR modscope: PCT.ModScope;	(*cached value*)
		
		PROCEDURE ImportList;
			VAR alias, name: StringPool.Index; new: PCT.Module; res: LONGINT;
		BEGIN
			LOOP
				IF sym # ident THEN Error(ident, scanner.errpos); EXIT END;
				alias := scanner.name;
				scanner.Get(sym);
				IF sym = becomes THEN
					scanner.Get(sym);
					IF sym = ident THEN
						name := scanner.name;
					ELSIF sym = string THEN
						name := StringPool.GetIndex1(scanner.str)	(*scanner.str is read-only and GetIndex has a VAR....*)
					ELSE
						Error(ident, scanner.errpos); EXIT
					END;
					scanner.Get(sym)
				ELSE
					name := alias;
				END;
				PCT.Import(modscope.owner, new, name);
				IF new = NIL THEN
					PCM.ErrorN(152, scanner.errpos, name)
				ELSE
					IF new # PCT.System THEN
						modscope.owner.AddDirectImp(new);
					END;
					modscope.AddModule(alias, new, res);	(*must create copy, otherwise list fields get overwritten*)
					IF res # PCT.Ok THEN PCM.ErrorN(res, scanner.errpos, alias) END
				END;
				IF sym = comma THEN scanner.Get(sym)
				ELSE EXIT
				END
			END;
			Check(semicolon)
		END ImportList;
		
		PROCEDURE ParseInterface;
		VAR  mod: PCT.Module; sf, flags: SET; name: PCS.Name;
		BEGIN
			IF sym = module THEN scanner.Get(sym);
				IF sym = ident THEN
					name := scanner.name;
					scanner.Get(sym);
					TypeModifier(sf, {}, {PCT.Overloading});
					PCT.InitScope(scope, NIL, sf, FALSE);
					mod := PCT.NewModule(name, FALSE, flags, modscope);
					Check(semicolon);
					IF sym = import THEN scanner.Get(sym);  ImportList END
				ELSE Error(ident, scanner.errpos)
				END
			ELSE Error(16, scanner.errpos)
			END;
			die := PCM.error
		END ParseInterface;
		
		PROCEDURE Await*;
		VAR count, inside: LONGINT;
		BEGIN
			sync.Await;
			sync.Stats(count, inside);
			IF inside > 0 THEN
				PCM.LogWStr(" ("); PCM.LogWNum(inside); PCM.LogW("/"); PCM.LogWNum(count); PCM.LogWStr(")")
			END;
			PCM.error := PCM.error OR (inside > 0)
		END Await;
			
		PROCEDURE & InitModule(modscope: PCT.ModScope; s: PCS.Scanner);
			VAR recscope: PCT.RecScope; rec: PCT.Record; res: LONGINT;
		BEGIN
			AosBoot.Inc(NModules);
			NEW(sync, 5(*timeout*)); sync.Enter;
			scope := modscope;  codescope := modscope;  scanner := s;  s.Get(sym);  scopelevel := 0;  looplevel := 0;
			PCT.SetOwner(scope);
			SELF.modscope := modscope;
			(*predefined variables*)
			scope.CreateVar(PCT.SelfName, PCT.Internal, {PCM.Untraced}, PCT.Ptr, res);	(*module self, used for module locking*)
			ASSERT(res = PCT.Ok);
			ParseInterface;
			IF ~die THEN
				(*predefined types*)
				NEW(recscope); PCT.InitScope(recscope, scope, {PCT.SuperclassAvailable}, FALSE); PCT.SetOwner(recscope);
				rec := PCT.NewRecord(PCT.NoType, recscope, {PCT.SystemType}, FALSE, res); ASSERT(res = PCT.Ok);
				scope.CreateType(deltype, PCT.Internal, rec, res); ASSERT(res = PCT.Ok);
				recscope.CreateVar(procfld, PCT.Internal, {}, PCT.Int32, res); ASSERT(res = PCT.Ok);
				recscope.CreateVar(self, PCT.Internal, {}, PCT.Ptr, res); ASSERT(res = PCT.Ok);
				PCT.ChangeState(recscope, PCT.complete, scanner.errpos);
				PCC.delegate := rec;
				
				NEW(recscope); PCT.InitScope(recscope, scope, {PCT.SuperclassAvailable}, FALSE); PCT.SetOwner(recscope);
				rec := PCT.NewRecord(PCT.NoType, recscope, {PCT.SystemType}, FALSE, res); ASSERT(res = PCT.Ok);
				scope.CreateType(hiddenptr, PCT.Internal, rec, res); ASSERT(res = PCT.Ok);
				recscope.CreateVar(ptrfld, PCT.Internal, {}, PCT.Ptr, res); ASSERT(res = PCT.Ok);
				PCT.ChangeState(recscope, PCT.complete, scanner.errpos);
				PCC.hdptr := rec;
				PCC.topscope := modscope;
			END
		END InitModule;
		
	END ModuleParser;
	
	PROCEDURE ParseModule*(scope: PCT.ModScope; s: PCS.Scanner);
		VAR parser: ModuleParser; name: StringPool.Index; sym: PCS.Token;
	BEGIN
		(* note: can use s directly instead of parser.scanner, because the module parser uses the same scanner *)
		NEW(parser, scope, s);
		parser.Await;
		IF ~parser.die THEN
			name := scope.owner.name;
			IF parser.sym = ident THEN
				IF s.name # name THEN PCM.ErrorN(4, s.errpos, name) END;
				s.Get(sym);
				IF sym = period THEN s.Get(sym) ELSE PCM.Error(period, s.errpos, "") END;
			ELSE PCM.ErrorN(ident, s.errpos, name)
			END
		END
	END ParseModule;
	

	PROCEDURE CreateString(VAR idx: StringPool.Index;  str: ARRAY OF CHAR);	(*to insert string constants*)
	BEGIN  StringPool.GetIndex(str, idx)
	END CreateString;

BEGIN
	CreateString(untraced, "UNTRACED");
	CreateString(delegate, "DELEGATE");
	CreateString(overloading, "OVERLOADING");
	CreateString(self, "SELF");
	CreateString(exclusive, "EXCLUSIVE");
	CreateString(active, "ACTIVE");
	CreateString(safe, "SAFE");
	CreateString(priority, "PRIORITY");
	CreateString(deltype, "@Delegate");
	CreateString(hiddenptr, "@HdPtrDesc");
	CreateString(procfld, "proc");
	CreateString(ptrfld, "ptr");
	noname := -1
END PCP.

(*
	24.06.03	prk	Check that name after END is the same as declared after MODULE
	21.07.02	prk	EXIT in an exclusive block must release lock
	05.02.02	prk	PCT.Find cleanup
	11.12.01	prk	problem parsing invalid WITH syntax fixed
	22.11.01	prk	improved flag handling
	19.11.01	prk	definitions
	17.11.01	prk	more flexible type handling of integer constants
	16.11.01	prk	constant folding of reals done with maximal precision
	16.11.01	prk	improved error message when operators and Oberon-2 WITH found
	01.11.01	prk	improved error handling for OBJECT without VAR
	14.09.01	prk	PRIORITY modifier, error messages improved
	29.08.01	prk	PCT functions: return "res" instead of taking "pos"
	27.08.01	prk	PCT.Insert removed, use Create procedures instead
	27.08.01	prk	scope.unsorted list removed; use var, proc, const and type lists instead
	17.08.01	prk	overloading
	09.08.01	prk	Symbol Table Loader Plugin
	11.07.01	prk	support for fields and methods with same name in scope
	06.07.01	prk	mark object explicitly
	05.07.01	prk	import interface redesigned
	04.07.01	prk	SkipScope, seek for END in CODE bodies, ignore other keywords
	04.07.01	prk	scope flags added, remove imported
	02.07.01	prk	access flags, new design
	27.06.01	prk	StringPool cleaned up
	27.06.01	prk	ProcScope.CreatePar added
	21.06.01	prk	using stringpool index instead of array of char
	15.06.01	prk	support for duplicate scope entries
	14.06.01	prk	type descs for dynamic arrays of ptrs generated by the compiler
	12.06.01	prk	Interfaces
	30.05.01	prk	destination (\d) compiler-option to install the back-end
	17.05.01	prk	Delegates
	10.05.01	prk	remove temporary for-counter when EXIT inside a for-loop
	08.05.01	prk	PCT interface cleanup. Use InitX instead of New*, allows type extension
	26.04.01	prk	separation of RECORD and OBJECT in the parser
	29.03.01	prk	Java imports
*)