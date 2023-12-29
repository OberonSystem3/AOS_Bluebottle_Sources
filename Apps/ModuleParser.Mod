MODULE ModuleParser;	(** mb  **)

IMPORT Utilities, StringPool, PCS, AosOut;

CONST
	(* visibilities *)
	Public* = 1;
	PublicRO* = 2;
	Private* = 3;
	
VAR
	delegate: StringPool.Index;
	name: ARRAY 1024 OF CHAR;

TYPE
	InfoItem* = OBJECT
	VAR
		name*: Utilities.String;
		pos*: LONGINT;
	END InfoItem;

	Node* = OBJECT
	VAR
		next*: Node;
	END Node;
	
	Import* = OBJECT (Node)
	VAR
		ident*, alias*: InfoItem;
	END Import;
	
	Definition* = OBJECT (Node)
	VAR
		ident*: InfoItem;
		refines*: Qualident;
		procs*: ProcHead;
	END Definition;
	
	Type* = OBJECT
	VAR
		qualident*: Qualident;
		array*: Array;
		record*: Record;
		pointer*: Pointer;
		object*: Object;
		procedure*: Procedure;
	END Type;
	
	Array* = OBJECT
	VAR
		open*: BOOLEAN;
		len*: InfoItem;
		base*: Type;
	END Array;
	
	Record* = OBJECT
	VAR
		super*: Qualident;
		fieldList*: FieldDecl;
	END Record;
	
	FieldDecl* = OBJECT (Node)
	VAR
		identList*: IdentList;
		type*: Type;
	END FieldDecl;
	
	Pointer* = OBJECT
	VAR
		type*: Type;
	END Pointer;
	
	Object* = OBJECT
	VAR
		super*, implements*: Qualident;
		declSeq*: DeclSeq;
	END Object;
	
	Procedure* = OBJECT
	VAR
		delegate*: BOOLEAN;
		formalPars*: FormalPars;
	END Procedure;
	
	DeclSeq* = OBJECT (Node)
	VAR
		constDecl*: ConstDecl;
		typeDecl*: TypeDecl;
		varDecl*: VarDecl;
		procDecl*: ProcDecl;
	END DeclSeq;
	
	ConstDecl* = OBJECT (Node)
	VAR
		identDef*: IdentDef;
		constExpr*: Expr;
		expr*: InfoItem;
	END ConstDecl;
	
	TypeDecl* = OBJECT (Node)
	VAR
		identDef*: IdentDef;
		type*: Type;
	END TypeDecl;
	
	VarDecl* = OBJECT (Node)
	VAR
		identList*: IdentList;
		type*: Type;
	END VarDecl;
	
	ProcDecl* = OBJECT (Node)
	VAR
		head*: ProcHead;
		declSeq*: DeclSeq;
	END ProcDecl;
	
	ProcHead* = OBJECT (Node)
	VAR
		sysFlag*: InfoItem;
		constructor*, inline*, operator*: BOOLEAN;
		identDef*: IdentDef;
		formalPars*: FormalPars;
	END ProcHead;
	
	FormalPars* = OBJECT
	VAR
		fpSectionList*: FPSection;
		returnType*: Qualident;
		returnTypeAry*: Array;
		returnTypeObj*: InfoItem;
	END FormalPars;
	
	FPSection* = OBJECT (Node)
	VAR
		var*: BOOLEAN;
		identList*: IdentList;
		type*: Type;
	END FPSection;
	
	Expr* = OBJECT (Node)
	VAR
		simpleExprL*, simpleExprR*: SimpleExpr;
		relation*: InfoItem;
	END Expr;
	
	SimpleExpr* = OBJECT (Node)
	VAR
		sign*: InfoItem;
		termL*, termR*: Term;
		addOp*: AddOp;
	END SimpleExpr;
	
	Term* = OBJECT (Node)
	VAR
		factorL*, factorR*: Factor;
		mulOp*: MulOp;
	END Term;
	
	Factor* = OBJECT (Node)
	VAR
		designator*: Designator;
		number*, string*, nil*, bool*: InfoItem;
		set*: Element;
		expr*: Expr;
		factor*: Factor;
	END Factor;
	
	Designator* = OBJECT (Node)
	VAR
		qualident*: Qualident;
		ident*, arrowUp*: InfoItem;
		exprList*: Expr;
	END Designator;
	
	Qualident* = OBJECT (Node)
	VAR
		ident*: InfoItem;
	END Qualident;
	
	Element* = OBJECT (Node)
	VAR
		expr*, upToExpr*: Expr;
	END Element;
		
	MulOp* = OBJECT (Node)
	VAR
		op*: InfoItem;
	END MulOp;
	
	AddOp* = OBJECT (Node)
	VAR
		op*: InfoItem;
	END AddOp;
		
	IdentDef* = OBJECT
	VAR
		ident*: InfoItem;
		vis*: SHORTINT;
	END IdentDef;
	
	IdentList* = OBJECT (Node)
	VAR
		identDef*: IdentDef;
	END IdentList;
	
	Module* = OBJECT
	VAR
		ident*: InfoItem;
		importList*: Import;
		definitions*: Definition;
		declSeq*: DeclSeq;
		hasError-: BOOLEAN;
	END Module;

	Parser = OBJECT
	VAR
		sym: PCS.Token;
		scanner: PCS.Scanner;
		hasError: BOOLEAN;
		
		PROCEDURE & Init*(scanner: PCS.Scanner);
		BEGIN
			SELF.scanner := scanner;
			hasError := FALSE;
		END Init;
		
		PROCEDURE ModuleP(VAR module: Module);
		VAR
			name: ARRAY 64 OF CHAR;
			modName: PCS.Name;
			definition: Definition;
		BEGIN
			scanner.Get(sym);
			IF sym = PCS.module THEN
				NEW(module);
				scanner.Get(sym);
				IF sym = PCS.ident THEN
					modName := scanner.name;
					StringPool.GetString(scanner.name, name);
					NEW(module.ident);
					module.ident.name := Utilities.NewString(name);
					module.ident.pos := scanner.errpos;
				END;
				scanner.Get(sym);
				IF sym = PCS.lbrace THEN
					WHILE (sym # PCS.semicolon) & (sym # PCS.eof) DO scanner.Get(sym) END;
				END;
				Check(PCS.semicolon);
				IF sym = PCS.import THEN
					NEW(module.importList);
					ImportListP(module.importList);
				END;
				WHILE sym = PCS.definition DO
					NEW(definition);
					DefinitionP(definition);
					IF module.definitions = NIL THEN module.definitions := definition
					ELSE AppendLast(module.definitions, definition)
					END;
				END;
				IF (sym = PCS.const) OR (sym = PCS.type) OR (sym = PCS.var) OR (sym = PCS.procedure) THEN
					NEW(module.declSeq);
					DeclSeqP(module.declSeq);
				END;
				BodyP;
				IF (sym = PCS.ident) & (scanner.name = modName) THEN
					(* correct *)
				ELSE
					(* maybe missing END or wrong module name *)
					hasError := TRUE;
					AosOut.String("err3: "); AosOut.Int(scanner.errpos, 0); AosOut.Ln;
				END;
				module.hasError := hasError;
			END;
		END ModuleP;
			
		PROCEDURE ImportListP(import: Import);
		VAR
			name: ARRAY 64 OF CHAR;
			newImport: Import;
		BEGIN
			scanner.Get(sym);
			WHILE sym = PCS.ident DO
				StringPool.GetString(scanner.name, name);
				NEW(import.ident);
				import.ident.name := Utilities.NewString(name);
				import.ident.pos := scanner.errpos;
				scanner.Get(sym);	(* avoids endless loop *)
				IF sym = PCS.becomes THEN
					scanner.Get(sym);
					IF sym = PCS.ident THEN
						StringPool.GetString(scanner.name, name);
						NEW(import.alias);
						import.alias.name := Utilities.NewString(name);
						import.alias.pos := scanner.errpos;
						scanner.Get(sym);
					ELSE
						(* Error *)
						hasError := TRUE;
						AosOut.String("err2: "); AosOut.Int(scanner.errpos, 0); AosOut.Ln;
					END;
				END;
				IF sym = PCS.comma THEN
					scanner.Get(sym);
				END;
				NEW(newImport);
				import.next := newImport;
				import := newImport;			
			END;
			Check(PCS.semicolon);				
		END ImportListP;
		
		PROCEDURE DefinitionP(definition: Definition);
		VAR
			procHead: ProcHead;
		BEGIN
			IF sym = PCS.definition THEN
				scanner.Get(sym);
				IF sym = PCS.ident THEN
					StringPool.GetString(scanner.name, name);
					NEW(definition.ident);
					definition.ident.name := Utilities.NewString(name);
					definition.ident.pos := scanner.errpos;
					scanner.Get(sym);
				END;
				WHILE sym = PCS.semicolon DO scanner.Get(sym) END;
				IF sym = PCS.refines THEN
					scanner.Get(sym);
					NEW(definition.refines);
					QualidentP(definition.refines);
				END;
				WHILE sym = PCS.procedure DO
					NEW(procHead);
					scanner.Get(sym);
					ProcHeadP(procHead);
					IF definition.procs = NIL THEN definition.procs := procHead
					ELSE AppendLast(definition.procs, procHead)
					END;
					Check(PCS.semicolon);			
				END;
				Check(PCS.end);
				Check(PCS.ident);
				WHILE sym = PCS.semicolon DO scanner.Get(sym) END;
			END;
		END DefinitionP;
			
		PROCEDURE DeclSeqP(declSeq: DeclSeq);
		VAR
			constDecl: ConstDecl;
			typeDecl: TypeDecl;
			varDecl: VarDecl;
			procDecl: ProcDecl;
			
			PROCEDURE CheckEndOrSemicolon();
			BEGIN
				IF sym # PCS.end THEN
					REPEAT Check(PCS.semicolon) UNTIL sym # PCS.semicolon
				END;
			END CheckEndOrSemicolon;
			
		BEGIN
			LOOP
				CASE sym OF
				| PCS.const:
					scanner.Get(sym);
					WHILE sym = PCS.ident DO
						NEW(constDecl);
						ConstDeclP(constDecl);
						IF declSeq.constDecl = NIL THEN declSeq.constDecl := constDecl;
						ELSE AppendLast(declSeq.constDecl, constDecl);
						END;
						CheckEndOrSemicolon();
						(*Check(PCS.semicolon);*)
					END;
				| PCS.type:
					scanner.Get(sym);
					WHILE sym = PCS.ident DO
						NEW(typeDecl);
						TypeDeclP(typeDecl);
						IF declSeq.typeDecl = NIL THEN declSeq.typeDecl := typeDecl;
						ELSE AppendLast(declSeq.typeDecl, typeDecl);
						END;
						CheckEndOrSemicolon();
						(*Check(PCS.semicolon);*)
					END;
				| PCS.var:
					scanner.Get(sym);
					WHILE sym = PCS.ident DO
						NEW(varDecl);
						VarDeclP(varDecl);
						IF declSeq.varDecl = NIL THEN declSeq.varDecl := varDecl;
						ELSE AppendLast(declSeq.varDecl, varDecl);
						END;
						CheckEndOrSemicolon();
						(*Check(PCS.semicolon);*)
					END;
				| PCS.procedure:
					WHILE sym = PCS.procedure DO
						scanner.Get(sym);
						NEW(procDecl);
						ProcDeclP(procDecl);
						IF procDecl.head = NIL THEN
							procDecl := NIL
						ELSE
							IF declSeq.procDecl = NIL THEN declSeq.procDecl := procDecl;
							ELSE AppendLast(declSeq.procDecl, procDecl);
							END;
						END;
						CheckEndOrSemicolon();
						(*Check(PCS.semicolon);*)
					END;
				ELSE
					EXIT;
				END;
			END;
		END DeclSeqP;
		
		PROCEDURE ConstDeclP(const: ConstDecl);
		BEGIN
			NEW(const.identDef);
			IdentDefP(const.identDef);
			Check(PCS.eql);
			(* NEW(const.constExpr);
			ExprP(const.constExpr); *)
			NEW(const.expr);
			ConstExprP(PCS.semicolon, -1, const.expr);
		END ConstDeclP;
		
		PROCEDURE TypeDeclP(type: TypeDecl);
		BEGIN
			NEW(type.identDef);
			IdentDefP(type.identDef);
			Check(PCS.eql);
			NEW(type.type);
			TypeP(type.type);
		END TypeDeclP;
		
		PROCEDURE VarDeclP(var: VarDecl);
		VAR
			identDef: IdentDef;
			identList: IdentList;
		BEGIN
			(*SysFlag;*)
			NEW(var.identList);
			NEW(var.identList.identDef);
			IdentDefP(var.identList.identDef);
			SysFlag;
			WHILE sym = PCS.comma DO
				scanner.Get(sym);	(* avoids endless loop *)
				NEW(identDef);
				IdentDefP(identDef);
				SysFlag;
				NEW(identList);
				identList.identDef := identDef;
				AppendLast(var.identList, identList);
			END;
			Check(PCS.colon);	
			NEW(var.type);
			TypeP(var.type);
		END VarDeclP;
		
		PROCEDURE ProcDeclP(proc: ProcDecl);
		VAR
			declSeq: DeclSeq;
		BEGIN
			NEW(proc.head);
			ProcHeadP(proc.head);
			IF proc.head.identDef = NIL THEN proc.head := NIL; RETURN END;
			Check(PCS.semicolon);
			IF (sym = PCS.const) OR (sym = PCS.var) OR (sym = PCS.type) OR (sym = PCS.procedure) THEN
				NEW(declSeq);
				DeclSeqP(declSeq);
				IF proc.declSeq = NIL THEN proc.declSeq := declSeq;
				ELSE AppendLast(proc.declSeq, declSeq);
				END;
			END;
			BodyP;
			scanner.Get(sym);	(* skip ident *)
		END ProcDeclP;
		
		PROCEDURE ProcHeadP(head: ProcHead);
		VAR name: ARRAY 64 OF CHAR; forward: BOOLEAN;
		BEGIN
			SysFlag;
			CASE sym OF
			| PCS.minus: head.inline := TRUE; scanner.Get(sym);
			| PCS.and: head.constructor := TRUE; scanner.Get(sym);
			| PCS.times: (* ignore *) scanner.Get(sym);
			| PCS.arrow: (* ignore *) scanner.Get(sym); forward := TRUE;
			| PCS.string: head.operator := TRUE;
			| PCS.number: IF scanner.numtyp = PCS.char THEN head.operator := TRUE END;
			ELSE
			END;
			NEW(head.identDef);
			IdentDefP(head.identDef);
			IF sym = PCS. lparen THEN
				NEW(head.formalPars);
				FormalParsP(head.formalPars);
			END;
			IF forward THEN
				head.identDef := NIL;
				head.formalPars := NIL;
			END;
		END ProcHeadP;
		
		PROCEDURE SysFlag;
		BEGIN
			IF sym = PCS.lbrak THEN
				scanner.Get(sym);
				Check(PCS.ident);
				Check(PCS.rbrak);
			END;
		END SysFlag;
		
		PROCEDURE FormalParsP(pars: FormalPars);
		VAR
			fpSection: FPSection;
		BEGIN
			scanner.Get(sym);
			IF (sym = PCS.var) OR (sym = PCS.ident) THEN
				NEW(pars.fpSectionList);
				FPSectionP(pars.fpSectionList);
				WHILE sym = PCS.semicolon DO
					scanner.Get(sym);	(* avoids endless loop *)
					NEW(fpSection);
					FPSectionP(fpSection);
					AppendLast(pars.fpSectionList, fpSection);
				END;
			END;
			Check(PCS.rparen);
			IF sym = PCS.colon THEN
				scanner.Get(sym);
				IF sym = PCS.object THEN
					NEW(pars.returnTypeObj);
					pars.returnTypeObj.name := Utilities.NewString("OBJECT");
					pars.returnTypeObj.pos := scanner.errpos;
					scanner.Get(sym);
				ELSIF sym = PCS.array THEN
					NEW(pars.returnTypeAry);
					scanner.Get(sym);
					ArrayP(pars.returnTypeAry);
				
					(*
					NEW(pars.returnType.ident);
					pars.returnType.ident.name := Utilities.NewString("ARRAY OF ???");
					pars.returnType.ident.pos := scanner.errpos;
					SkipTo(PCS.semicolon);
					*)
				ELSE
					NEW(pars.returnType);
					QualidentP(pars.returnType)
				END;
			END;
		END FormalParsP;
		
		PROCEDURE FPSectionP(fpSection: FPSection);
		VAR
			identDef: IdentDef;
			identList: IdentList;
			name: ARRAY 64 OF CHAR;
		BEGIN
			IF sym = PCS.var THEN
				fpSection.var := TRUE;
				scanner.Get(sym);
			END;
			IF sym = PCS.ident THEN
				(*StringPool.GetString(scanner.name, name);*)
				NEW(fpSection.identList);
				NEW(fpSection.identList.identDef);
				IdentDefP(fpSection.identList.identDef);
				(*
				fpSection.identList.ident.name := Utilities.NewString(name);
				fpSection.identList.ident.pos := scanner.errpos;
				scanner.Get(sym);
				*)
				WHILE sym = PCS.comma DO
					NEW(identList);
					scanner.Get(sym);
					NEW(identList.identDef);
					IdentDefP(identList.identDef);
					AppendLast(fpSection.identList, identList);
					(*
					IF sym = PCS.ident THEN
						StringPool.GetString(scanner.name, name);
						NEW(identDef);
						NEW(identDef.ident);
						identDef.ident.name := Utilities.NewString(name);
						identDef.ident.pos := scanner.errpos;
						AppendLast(fpSection.identlist, identDef);
						scanner.Get(sym);
					END;
					*)
				END;
				Check(PCS.colon);
				NEW(fpSection.type);
				TypeP(fpSection.type);
			END;
		END FPSectionP;
		
		PROCEDURE TypeP(type: Type);
		BEGIN
			CASE sym OF
			| PCS.array: scanner.Get(sym); NEW(type.array); ArrayP(type.array);
			| PCS.record: scanner.Get(sym); NEW(type.record); RecordP(type.record);
			| PCS.pointer: scanner.Get(sym); NEW(type.pointer); PointerP(type.pointer);
			| PCS.object: scanner.Get(sym); NEW(type.object); ObjectP(type.object);
			| PCS.procedure: scanner.Get(sym); NEW(type.procedure); ProcedureP(type.procedure);
			| PCS.ident: NEW(type.qualident); QualidentP(type.qualident);
			ELSE
				(* Error *)
				hasError := TRUE; AosOut.String("err4: "); AosOut.Int(scanner.errpos, 0); AosOut.Ln;
				scanner.Get(sym);	(* ??? *)
			END;
		END TypeP;
		
		PROCEDURE ArrayP(array: Array);
		BEGIN
			SysFlag;
			IF sym = PCS.of THEN
				array.open := TRUE;
				NEW(array.base);
				scanner.Get(sym);
				TypeP(array.base);
			ELSE
				NEW(array.len);
				ConstExprP(PCS.of, PCS.comma, array.len);
				(*
				SimpleExprP(array.len);
				*)
				IF sym = PCS.of THEN
					NEW(array.base);
					scanner.Get(sym);
					TypeP(array.base);
				ELSIF sym = PCS.comma THEN
					NEW(array.base);
					NEW(array.base.array);
					scanner.Get(sym);
					ArrayP(array.base.array)
				ELSE
					(* Error *)
					hasError := TRUE;
					AosOut.String("err1: "); AosOut.Int(scanner.errpos, 0); AosOut.Ln;
				END;
			END;
		END ArrayP;
		
		PROCEDURE RecordP(record: Record);
		BEGIN
			SysFlag;
			IF sym = PCS.lparen THEN
				scanner.Get(sym);
				NEW(record.super);
				QualidentP(record.super);
				Check(PCS.rparen);
			END;
			WHILE sym = PCS.semicolon DO scanner.Get(sym) END;
			IF sym = PCS.ident THEN
				NEW(record.fieldList);
				FieldListP(record.fieldList);
			END;
			Check(PCS.end);
		END RecordP;
		
		PROCEDURE FieldListP(fieldList: FieldDecl);
		VAR fieldDecl: FieldDecl;
		BEGIN
			FieldDeclP(fieldList);
			WHILE sym = PCS.semicolon DO
				scanner.Get(sym);
				NEW(fieldDecl);
				FieldDeclP(fieldDecl);
				AppendLast(fieldList, fieldDecl);
			END;
		END FieldListP;
		
		PROCEDURE FieldDeclP(fieldDecl: FieldDecl);
		VAR
			identDef: IdentDef;
			identList: IdentList;
		BEGIN
			IF sym = PCS.ident THEN
				NEW(fieldDecl.identList);
				NEW(fieldDecl.identList.identDef);
				IdentDefP(fieldDecl.identList.identDef);
				SysFlag;
				WHILE sym = PCS.comma DO
					scanner.Get(sym);
					NEW(identDef);
					IdentDefP(identDef);
					SysFlag;
					NEW(identList);
					identList.identDef := identDef;
					AppendLast(fieldDecl.identList, identList);
				END;
				Check(PCS.colon);
				NEW(fieldDecl.type);
				TypeP(fieldDecl.type);
			END;
		END FieldDeclP;
		
		PROCEDURE PointerP(pointer: Pointer);
		BEGIN
			SysFlag;
			Check(PCS.to);
			NEW(pointer.type);
			TypeP(pointer.type);
		END PointerP;
		
		PROCEDURE ObjectP(object: Object);
		VAR declSeq: DeclSeq;
			pos: LONGINT;
			qualident: Qualident;
		BEGIN
			IF (sym = PCS.semicolon) OR (sym = PCS.rparen) THEN RETURN END;
			SysFlag;
			IF sym = PCS.lparen THEN
				NEW(object.super);
				scanner.Get(sym);
				QualidentP(object.super);
				Check(PCS.rparen);
			END;
			IF sym = PCS.implements THEN
				NEW(object.implements);
				scanner.Get(sym);
				QualidentP(object.implements);
				WHILE sym = PCS.comma DO
					NEW(qualident);
					scanner.Get(sym);
					QualidentP(qualident);
					AppendLast(object.implements, qualident);
				END;
			END;
			pos := -1;
			WHILE (sym # PCS.begin) & (sym # PCS.end) & (sym # PCS.eof) DO
					(* avoid endless-loop *)
				IF pos = scanner.errpos THEN scanner.Get(sym) END;
				pos := scanner.errpos;
				NEW(declSeq);
				DeclSeqP(declSeq);
				IF object.declSeq = NIL THEN object.declSeq := declSeq;
				ELSE AppendLast(object.declSeq, declSeq);
				END;
			END;
			BodyP();
			IF sym = PCS.ident THEN scanner.Get(sym) END;
		END ObjectP;
		
		PROCEDURE ProcedureP(proc: Procedure);
		BEGIN
			SysFlag;
			IF sym = PCS.lbrace THEN
				scanner.Get(sym);
				IF sym # PCS.ident THEN
					(* Error *)
				ELSIF scanner.name = delegate THEN
					proc.delegate := TRUE;
				END;
				scanner.Get(sym);
				Check(PCS.rbrace);
			END;
			IF sym = PCS.lparen THEN
				NEW(proc.formalPars);
				FormalParsP(proc.formalPars);
			END;
		END ProcedureP;
		
		PROCEDURE ConstExprP(delimiter1, delimiter2: PCS.Token; expr: InfoItem);
		VAR
			exprStr, name: ARRAY 64 OF CHAR;
			paren, brace, brak: LONGINT;
		
			PROCEDURE Add(str: ARRAY OF CHAR);
			BEGIN
				Utilities.Append(exprStr, str);
			END Add;
			
		BEGIN
			expr.pos := scanner.errpos;
			IF (sym = delimiter1) OR (sym = delimiter2) THEN RETURN END;
			REPEAT
				CASE sym OF
				| PCS.lparen: INC(paren); Add("(");
				| PCS.rparen: DEC(paren); Add(")");
				| PCS.lbrace: INC(brace); Add("{");
				| PCS.rbrace: DEC(brace); Add("}");
				| PCS.lbrak: INC(brak); Add("[");
				| PCS.rbrak: DEC(brak); Add("]");
				| PCS.number: scanner.GetNumAsString(name); Add(name);
				| PCS.nil: Add("NIL");
				| PCS.true: Add("TRUE");
				| PCS.false: Add("FALSE");
				| PCS.not: Add("~");
				| PCS.period: Add(".");
				| PCS.ident: StringPool.GetString(scanner.name, name); Add(name);
				| PCS.comma: Add(", ");
				| PCS.plus: Add(" + ");
				| PCS.minus: Add(" - ");
				| PCS.times: Add(" * ");
				| PCS.upto: Add(" .. ");
				| PCS.eql: Add(" = ");
				| PCS.neq: Add(" # ");
				| PCS.lss: Add(" < ");
				| PCS.leq: Add(" <= ");
				| PCS.gtr: Add(" > ");
				| PCS.geq: Add(" >= ");
				| PCS.in: Add(" IN "); 
				| PCS.is: Add(" IS ");
				| PCS.div: Add(" DIV ");
				| PCS.mod: Add(" MOD ");
				| PCS.slash: Add(" / ");
				| PCS.and: Add(" & ");
				| PCS.or: Add(" OR ");
				| PCS.string: name[0] := '"'; name[1] := 0X; Add(name); Add(scanner.str); Add(name);
				| PCS.arrow: Add("^");
				ELSE
					(* error *)
					hasError := TRUE;
				END;
				scanner.Get(sym);
					(* urgh, what an ugly condition ... *)
			UNTIL ((sym = delimiter1) OR (sym = delimiter2)) & (paren = 0) & (brace = 0) & (brak = 0) & (sym # PCS.eof);
			expr.name := Utilities.NewString(exprStr);
		END ConstExprP;
			
		PROCEDURE BodyP;
		VAR end: LONGINT;
		BEGIN
			IF sym = PCS.begin THEN
				end := 1;
				REPEAT
					scanner.Get(sym);
					CASE sym OF
					| PCS.if, PCS.case, PCS.begin, PCS.while, PCS.for, PCS.loop, PCS.with: INC(end);
					| PCS.end: DEC(end);
					ELSE
					END;
				UNTIL (end = 0) OR (sym = PCS.eof);
			ELSIF sym = PCS.code THEN
				REPEAT scanner.Get(sym) UNTIL (sym = PCS.end) OR (sym = PCS.eof);
			END;
			scanner.Get(sym);
		END BodyP;
			
		PROCEDURE QualidentP(qualident: Qualident);
		VAR
			name, name2: ARRAY 64 OF CHAR;
			pos: LONGINT;
		BEGIN
			IF sym = PCS.ident THEN
				StringPool.GetString(scanner.name, name);
				pos := scanner.errpos;
				scanner.Get(sym);
				IF sym = PCS.period THEN
					scanner.Get(sym);
					IF sym = PCS.ident THEN
						StringPool.GetString(scanner.name, name2);
						Utilities.Append(name, ".");
						Utilities.Concat(name, name2, name);
						scanner.Get(sym);
					END;
				END;
				NEW(qualident.ident);
				qualident.ident.name := Utilities.NewString(name);
				qualident.ident.pos := pos;
			END;
		END QualidentP;
		
		PROCEDURE IdentDefP(identDef: IdentDef);
		VAR
			name: ARRAY 64 OF CHAR;
		BEGIN
			IF sym = PCS.ident THEN
				StringPool.GetString(scanner.name, name);
				NEW(identDef.ident);
				identDef.ident.name := Utilities.NewString(name);
				identDef.ident.pos := scanner.errpos;
			ELSIF (sym = PCS.string) OR (sym = PCS.number) & (scanner.numtyp = PCS.char) THEN
				NEW(identDef.ident);
				identDef.ident.name := Utilities.NewString(scanner.str);
				identDef.ident.pos := scanner.errpos;
			END;
			scanner.Get(sym);
			IF sym = PCS.times THEN
				identDef.vis := Public;
				scanner.Get(sym);
			ELSIF sym = PCS.minus THEN
				identDef.vis := PublicRO;
				scanner.Get(sym);
			ELSE
				identDef.vis := Private;
			END;
		END IdentDefP;
		
		PROCEDURE Check(token: PCS.Token);
		VAR
			index: StringPool.Index;
			name: ARRAY 64 OF CHAR;
		BEGIN
			IF sym = token THEN
				(* correct *)
			ELSE
				(* error *)
				
				AosOut.String("******* Check error **********  "); 
				AosOut.Int(scanner.errpos, 0);
				AosOut.Ln;
				
				hasError := TRUE;
				(*HALT(33);*)
			END;
			scanner.Get(sym);
		END Check;
		
		PROCEDURE SkipTo(token: PCS.Token);
		BEGIN
			WHILE sym # token DO scanner.Get(sym) END;
		END SkipTo;
				
	END Parser;

PROCEDURE AppendLast(head, node: Node);
VAR n: Node;
BEGIN
	IF head = NIL THEN RETURN END;
	n := head;
	WHILE n.next # NIL DO
		n := n.next;
	END;
	n.next := node;
END AppendLast;

PROCEDURE Parse*(scanner: PCS.Scanner; VAR module: Module);
VAR parser: Parser;
BEGIN
	NEW(parser, scanner);
	parser.ModuleP(module);
END Parse;

PROCEDURE CreateString(VAR idx: StringPool.Index; str: ARRAY OF CHAR);
BEGIN
	StringPool.GetIndex(str, idx);
END CreateString;

BEGIN
	CreateString(delegate, "DELEGATE");
END ModuleParser.

PC.Compile \s ModuleParser.Mod ~
Builder.Compile \s  ModuleParser.Mod ~
System.DeleteFiles ModuleParser.Obx ~
System.Free ModuleParser ~
Decoder.Decode ModuleParser ~
