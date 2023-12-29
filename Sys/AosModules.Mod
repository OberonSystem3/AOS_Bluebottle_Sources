(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosModules; (** AUTHOR "pjm"; PURPOSE "Modules and types"; *)

IMPORT SYSTEM, AosBoot, AosLocks, AosOut, AosHeap;

CONST
	MaxTags* = 16;	(* in type descriptor *)
	
		(** type descriptor field offsets relative to root (middle) *)
	Tag0Ofs* = -8;	(** first tag *)
	Mth0Ofs* = Tag0Ofs - 4*MaxTags;	(** first method *)
	Ptr0Ofs* = 4;	(** first pointer offset *)
	
	MaxObjFormats = 5;	(* maximum number of object file formats installed *)
	
		(** flags in TypeDesc, RoundUp(log2(MaxTags)) low bits reserved for extLevel *)
	ProtTypeBit* = AosHeap.ProtTypeBit;
	
	None* = 0; PowerDown* = 1; Reboot* = 2;
	
	ClearCode = TRUE;
	
TYPE
		(* definitions for object-model loader support *)
	Name* = ARRAY 32 OF CHAR;
	
	CommandProc* = PROCEDURE;
	CommandParProc* = PROCEDURE(par: PTR): PTR;
	
	Command* = RECORD
		name*: Name;
		proc*: CommandProc;
		parproc*: CommandParProc
	END;
	
	ExportDesc* = RECORD
		fp*: LONGINT;
		adr*: LONGINT;
		exports*: LONGINT;
		dsc*: ExportArray
	END;
	ExportArray* = POINTER TO ARRAY OF ExportDesc;
	
	Bytes* = POINTER TO ARRAY OF CHAR;
	
	TerminationHandler* = PROCEDURE;	(* to do: change to delegate and update AosLinker. *)
	
	TypeTag* = POINTER TO RECORD	(** pointer to "middle" of type descriptor *)
		(* type: Type *)
		recSize*: LONGINT;
		ptrOfs0*: LONGINT
		(* ptrOfs1: LONGINT *)
		(* ... N ptrOfs values *)
		(* sentinel: LONGINT *)	(* = MPO-4*(N+1) *)
	END;
	
		(* type descriptors *)
	TypeDesc* = POINTER TO RECORD	(** pointer to "start" of type descriptor *)	(* cf. AosHeap.NewType/WriteType *)
		(* tag0: LONGINT *)	(* = SYSTEM.ADR(descSize) *)
		descSize: LONGINT;	(* placeholder *)
		sentinel: LONGINT;	(* placeholder = MPO-4 *)
		tag*: TypeTag;	(* = SYSTEM.ADR(recSize) *)	(** pointer to "middle" of type descriptor. *)
		flags*: SET;	(** low bits reserved for extLevel (see ProtTypeBit). *)
		mod*: Module;	(** hint only, because module may have been freed (at AosHeap.ModOfs). *)
		name*: Name;	(** name of the module. *)
		(* method: ARRAY M OF PROCEDURE(...) *)
		(* baseTag: ARRAY 16 OF TypeTag *)
		(* typeDesc: TypeDesc *)	(* = SYSTEM.ADR(descSize) *)
		(* recSize: LONGINT *)
		(* ptrOfs: ARRAY N OF LONGINT *)
		(* sentinel: LONGINT *)	(* = MPO-4*(N+1) *)
	END;
		
TYPE
	Module* = OBJECT (AosHeap.RootObject)	(* cf. AosLinker0 & AosHeap.WriteType *)
		VAR
			next*: Module;	(** once a module is published, all fields are read-only *)
			name*: Name;
			init, published: BOOLEAN;
			refcnt*, sb*: LONGINT;
			dataSize*, constSize*, codeSize*, refSize*: LONGINT;
			entries*, commands*, modules*, types*, pointers*: LONGINT;
			entry*: POINTER TO ARRAY OF LONGINT;
			command*: POINTER TO ARRAY OF Command;
			ptrAdr*: POINTER TO ARRAY OF LONGINT;
			type*: POINTER TO ARRAY OF TypeTag;	(* traced explicitly in FindRoots *)
			module*: POINTER TO ARRAY OF Module;
			data*, code*, refs*: Bytes;
				(* slim binary support *)
			publics*, privates*: LONGINT;	(* should also be marked (slim binaries?) *)
			imports*: LONGINT;
			import*: POINTER TO ARRAY OF LONGINT;
			nofstrc*: LONGINT;
			struct*: POINTER TO ARRAY OF LONGINT;
			nofreimp*: LONGINT;
			reimp*: POINTER TO ARRAY OF LONGINT;
			export*: ExportDesc;
				(* termination handler *)
			term*: TerminationHandler;
		
		PROCEDURE FindRoots;	(* override *)
		VAR i: LONGINT;  ptr: SYSTEM.PTR;
		BEGIN
			IF published THEN	(* mark global pointers *)
				FOR i := 0 TO LEN(ptrAdr)-1 DO
					SYSTEM.GET(ptrAdr[i], ptr);
					IF ptr # NIL THEN AosHeap.Mark(ptr) END
				END
			END;
			IF type # NIL THEN	(* type ptr array allocated in untraced subblk *)
				FOR i := 0 TO LEN(type)-1 DO
					ptr := type[i];
					IF ptr # NIL THEN AosHeap.Mark(ptr) END
				END
			END
		END FindRoots;
	END Module;

	LoaderProc* = PROCEDURE (name, fileName: ARRAY OF CHAR;  VAR res: LONGINT;  
			VAR msg: ARRAY OF CHAR): Module;	(** load an object file *)

VAR
	extension-: ARRAY MaxObjFormats, 8 OF CHAR;
	loader: ARRAY MaxObjFormats OF LoaderProc;
	numLoaders: LONGINT;
(*
	loadObj*: PROCEDURE (name, fileName: ARRAY OF CHAR;  VAR res: LONGINT;  
			VAR msg: ARRAY OF CHAR): Module;	(** load an object file *)
	extension*: ARRAY 8 OF CHAR;	(* file extension for object files *)
*)
	kernelProc*: ARRAY 10 OF LONGINT;	(** kernel call addresses for loader *)
	
	freeRoot*: Module;	(** list of freed modules (temporary) *)

		(* the following two variables are initialized by AosLinker *)
	root*: Module;	(** list of modules (read-only) *)
	initBlock: SYSTEM.PTR;	(* placeholder - anchor for module init code (initialized by linker) *)
	shutdown*: LONGINT;	(** None, Reboot, PowerDown *)
	trace: BOOLEAN;

(** Register a module loader. *)

PROCEDURE AddLoader*(ext: ARRAY OF CHAR; proc: LoaderProc);
BEGIN
	AosLocks.Acquire(AosLocks.AosModules);
	ASSERT(numLoaders < MaxObjFormats);
	loader[numLoaders] := proc;
	COPY(ext, extension[numLoaders]);
	ASSERT(ext = extension[numLoaders]);	(* no overflow *)
	INC(numLoaders);
	AosLocks.Release(AosLocks.AosModules)
END AddLoader;

(** Remove a module loader. *)

PROCEDURE RemoveLoader*(ext: ARRAY OF CHAR; proc: LoaderProc);
VAR i, j: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosModules);
	i := 0;
	WHILE (i # numLoaders) & ((loader[i] # proc) OR (extension[i] # ext)) DO INC(i) END;
	IF i # numLoaders THEN
		FOR j := i TO numLoaders - 2 DO
			loader[j] := loader[j + 1]; extension[j] := extension[j + 1];
		END;
		loader[numLoaders - 1] := NIL; extension[numLoaders - 1] := "";
		DEC(numLoaders)
	END;
	AosLocks.Release(AosLocks.AosModules)
END RemoveLoader;

(** Append string from to to, truncating on overflow. *)

PROCEDURE Append*(from: ARRAY OF CHAR;  VAR to: ARRAY OF CHAR);
VAR i, j, m: LONGINT;
BEGIN
	j := 0;  WHILE to[j] # 0X DO INC(j) END;
	m := LEN(to)-1;
	i := 0;  WHILE (from[i] # 0X) & (j # m) DO to[j] := from[i];  INC(i);  INC(j) END;
	to[j] := 0X
END Append;

(** Add a module to the pool of accessible modules, or return named module. *)

PROCEDURE Publish*(VAR m: Module;  VAR new: BOOLEAN);
VAR n: Module;  i: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosModules);
	n := root;  WHILE (n # NIL) & (n.name # m.name) DO n := n.next END;
	IF n # NIL THEN	(* module with same name exists, return it and ignore new m *)
		m := n;  new := FALSE
	ELSE
		m.published := TRUE;
		m.next := root;  root := m;
		m.refcnt := 0;
		FOR i := 0 TO m.modules-1 DO INC(m.module[i].refcnt) END;
		new := TRUE
	END;
	AosLocks.Release(AosLocks.AosModules)
END Publish;

(** Return the named module or NIL if it is not loaded yet. *)

PROCEDURE ModuleByName*(name: ARRAY OF CHAR): Module;
VAR m: Module;
BEGIN
	AosLocks.Acquire(AosLocks.AosModules);
	m := root;  WHILE (m # NIL) & (m.name # name) DO m := m.next END;
	AosLocks.Release(AosLocks.AosModules);
	RETURN m
END ModuleByName;

(* Generate a module file name. *)

PROCEDURE GetFileName(name, extension: ARRAY OF CHAR;  VAR fileName: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	i := 0;  WHILE name[i] # 0X DO fileName[i] := name[i];  INC(i) END;
	j := 0;  WHILE extension[j] # 0X DO fileName[i] := extension[j];  INC(i);  INC(j) END;
	fileName[i] := 0X
END GetFileName;

(** Load the module if it is not already loaded. *)	(* Algorithm J. Templ, ETHZ, 1994 *)

PROCEDURE ThisModule*(name: ARRAY OF CHAR;  VAR res: LONGINT;  VAR msg: ARRAY OF CHAR): Module;
TYPE Body = PROCEDURE;
VAR m, p: Module; fileName: ARRAY 64 OF CHAR; body: Body; new: BOOLEAN; i: LONGINT;
BEGIN
	res := 0;  msg[0] := 0X;  m := ModuleByName(name);
	IF m = NIL THEN
		IF trace THEN
			AosOut.Enter; AosOut.String(">"); AosOut.String(name); AosOut.Exit
		END;
		i := 0;
		REPEAT
			GetFileName(name, extension[i], fileName);
			m := loader[i](name, fileName, res, msg);
			INC(i)
		UNTIL (i = numLoaders) OR (m # NIL);
		IF trace THEN
			AosOut.Enter; AosOut.String("?"); AosOut.String(name); AosOut.Exit
		END;
		IF (m # NIL) & ~m.published THEN	(* no race on m.published, as update is done below in Publish *)
			p := m;  Publish(m, new);
			IF new THEN	(* m was successfully published *)
				body := SYSTEM.VAL(Body, SYSTEM.ADR(m.code[0]));
				body;  res := 0;  msg[0] := 0X;
				m.init := TRUE	(* allow ThisCommand *)
			ELSE
				(* m was part of cycle, replaced by existing module *)
			END
		END;
		IF trace THEN
			AosOut.Enter; AosOut.String("<"); AosOut.String(name); AosOut.Exit
		END;
	END;
	RETURN m
END ThisModule;

(** Return the module that contains code address pc or NIL if not found.  Can also return freed modules. *)

PROCEDURE ThisModuleByAdr*(pc: LONGINT): Module;
VAR m: Module; cbase, dbase, i: LONGINT; found: BOOLEAN;
BEGIN
	AosLocks.Acquire(AosLocks.AosModules);
	i := 0; found := FALSE;
	REPEAT
		CASE i OF
			0: m := root
			|1: m := freeRoot
		END;
		WHILE (m # NIL) & ~found DO
			cbase := SYSTEM.ADR(m.code[0]); dbase := SYSTEM.ADR(m.data[0]);
				(* include 1 byte after module in module, therefore <= below *)
			IF (cbase <= pc) & (pc <= cbase + LEN(m.code^)) THEN
				found := TRUE
			ELSIF (dbase <= pc) & (pc <= dbase + LEN(m.data^)) THEN
				found := TRUE
			ELSE
				m := m.next
			END
		END;
		INC(i)
	UNTIL found OR (i = 2);
	AosLocks.Release(AosLocks.AosModules);
	RETURN m
END ThisModuleByAdr;

PROCEDURE FindCommand(m: Module; name: ARRAY OF CHAR; VAR cmd: Command);
VAR i: LONGINT; found: BOOLEAN;
BEGIN
	ASSERT(m.init);	(* module body must have been called (see note at end of module) *)
	AosLocks.Acquire(AosLocks.AosModules);
	i := 0; found := FALSE;
	WHILE ~found & (i # LEN(m.command^)) DO
		IF m.command[i].name = name THEN
			found := TRUE; cmd := m.command[i]
		ELSE
			INC(i)
		END
	END;
	IF ~found THEN cmd.proc := NIL; cmd.parproc := NIL END;
	AosLocks.Release(AosLocks.AosModules)
END FindCommand;

(** Return the named command. *)

PROCEDURE ThisCommand*(m: Module; name: ARRAY OF CHAR): CommandProc;
VAR cmd: Command;
BEGIN
	FindCommand(m, name, cmd);
	RETURN cmd.proc
END ThisCommand;

(** Return the named parameterized command. *)

PROCEDURE ThisCommandPar*(m: Module; name: ARRAY OF CHAR): CommandParProc;
VAR cmd: Command;
BEGIN
	FindCommand(m, name, cmd);
	RETURN cmd.parproc
END ThisCommandPar;

(** Return the CommandParProc of a command given by a string in the format <module>.<command>
	returns NIL if either the Module or the CommandParProc is not found *)
PROCEDURE GetCommandByString*(cmd : ARRAY OF CHAR) : CommandParProc;
VAR i, n, res : LONGINT; msg : ARRAY 64 OF CHAR; mod : Module; proc : CommandParProc;
BEGIN
	i := 0; WHILE (cmd[i] # 0X) & (cmd[i] # ".") DO INC(i) END;
	IF cmd[i] = "." THEN
		cmd[i] := 0X;
		mod := ThisModule(cmd, res, msg);
		IF mod # NIL THEN
			INC(i); n := i; WHILE cmd[i] # 0X DO cmd[i-n] := cmd[i]; INC(i) END;
			cmd[i-n] := 0X; 
			RETURN ThisCommandPar(mod, cmd)
		END
	END;
	RETURN NIL
END GetCommandByString;

(** Return the named type. *)

PROCEDURE ThisType*(m: Module;  name: ARRAY OF CHAR): TypeDesc;
VAR i, k, t: LONGINT;  type: TypeDesc;
BEGIN
	AosLocks.Acquire(AosLocks.AosModules);
	i := 0;  k := LEN(m.type^);
	WHILE i # k DO
		t := SYSTEM.VAL(LONGINT, m.type[i]);
		SYSTEM.GET(t-4, type);
		IF type.name = name THEN k := i ELSE INC(i) END
	END;
	IF k = LEN(m.type) THEN type := NIL END;	(* not found *)
	AosLocks.Release(AosLocks.AosModules);
	RETURN type
END ThisType;

(** Return the type with the specified tag address. (UNSAFE) *)

PROCEDURE ThisTypeByAdr*(adr: LONGINT;  VAR m: Module;  VAR t: TypeDesc);
BEGIN
	IF (adr # 0) & (adr MOD 16 = 8) THEN
		AosLocks.Acquire(AosLocks.AosModules);
		SYSTEM.GET(adr-4, adr);
		t := SYSTEM.VAL(TypeDesc, adr);
		SYSTEM.GET(adr+AosHeap.ModOfs, m);	(* this is only correct if we never free modules *)
		AosLocks.Release(AosLocks.AosModules)
	ELSE
		m := NIL;  t := NIL
	END
END ThisTypeByAdr;

(** create a new object given its type descriptor *)
PROCEDURE NewObj*(t : TypeDesc) : PTR;
VAR x : PTR;
BEGIN
	AosHeap.NewRec(x, SYSTEM.VAL(LONGINT, t.tag));
	RETURN x;
END NewObj;

(** return the type descriptor of an object *)
PROCEDURE TypeOf*(obj : PTR): TypeDesc;
VAR
	m : Module;
	t : TypeDesc;
	adr : LONGINT;	
BEGIN
	SYSTEM.GET(SYSTEM.VAL(LONGINT, obj)-4, adr);
	ThisTypeByAdr(adr ,m,t);
	RETURN t;
END TypeOf;


(** Install procedure to execute when module is freed or shut down.  The handler can distinguish the two cases by checking AosModules.shutdown.  If it is None, the module is being freed, otherwise the system is being shut down or rebooted.  Only one handler may be installed per module.  The last handler installed is active. *)

PROCEDURE InstallTermHandler*(h: TerminationHandler);
VAR m: Module;
BEGIN
	m := ThisModuleByAdr(SYSTEM.VAL(LONGINT, h));
	IF m # NIL THEN
		m.term := h	(* overwrite existing handler, if any *)
	END
END InstallTermHandler;

(** Free a module.  The module's termination handler, if any, is called first.  Then all objects that have finalizers in this module are finalized (even if they are still reachable).  Then the module's data and code are invalidated. *)

PROCEDURE FreeModule*(name: ARRAY OF CHAR;  VAR res: LONGINT;  VAR msg: ARRAY OF CHAR);
VAR p, m: Module;  term: TerminationHandler;  i: LONGINT;
BEGIN
	m := ModuleByName(name);
	IF (m # NIL) & (m.refcnt = 0) THEN	(* will be freed below *)
		IF m.term # NIL THEN	(* call termination handler *)
			term := m.term;  m.term := NIL;  term	(* may trap *)
		END;
		AosHeap.CleanupModuleFinalizers(SYSTEM.ADR(m.code[0]), LEN(m.code), m.name)
	END;
	res := 0;  msg[0] := 0X;
	AosLocks.Acquire(AosLocks.AosModules);
	p := NIL;  m := root;
	WHILE (m # NIL) & (m.name # name) DO p := m;  m := m.next END;
	IF m # NIL THEN
		IF m.refcnt = 0 THEN	(* free the module *)
			FOR i := 0 TO LEN(m.module)-1 DO DEC(m.module[i].refcnt) END;
			m.init := FALSE;	(* disallow ThisCommand *)
			Append("?", m.name);
				(* move module to free list *)
			IF p = NIL THEN root := root.next ELSE p.next := m.next END;
			m.next := freeRoot;  freeRoot := m;
				(* clear global pointers and code *)
			FOR i := 0 TO LEN(m.ptrAdr)-1 DO SYSTEM.PUT(m.ptrAdr[i], NIL) END;
			IF ClearCode THEN
				FOR i := 0 TO LEN(m.code)-1 DO m.code[i] := 0CCX END
			END;
				(* remove references to module data *)
			m.published := FALSE;
			m.entry := NIL; m.command := NIL; m.ptrAdr := NIL;
				(* do not clear m.type or m.module, as old heap block tags might reference type descs indirectly. *)
				(* do not clear m.data or m.code, as they are used in ThisModuleByAdr (for debugging). *)
				(* do not clear m.refs, as they are used in AosTrap (for debugging). *)
			m.import := NIL; m.struct := NIL; m.reimp := NIL; m.export.dsc := NIL
		ELSE
			res := 1901;	(* can not free module in use *)
			COPY(name, msg);  Append(" reference count not zero", msg)
		END
	ELSE
		res := 1902;	(* module not found *)
		COPY(name, msg);  Append(" not found", msg)
	END;
	AosLocks.Release(AosLocks.AosModules)
END FreeModule;

(** Shut down all modules by calling their termination handlers and then call AosBoot.Shutdown. *)

PROCEDURE Shutdown*(code: LONGINT);
VAR m: Module; term: TerminationHandler;
BEGIN
(*
		(* ignore multiple shutdown attempts *)
	AosLocks.Acquire(AosLocks.AosModules);
	IF (shutdown = None) & (code # None) THEN	(* start shutdown *)
		shutdown := code
	ELSE	(* ignore this call, as shutdown already started *)
		code := None
	END;
	AosLocks.Release(AosLocks.AosModules);
*)
	IF code # None THEN
		LOOP
			AosLocks.Acquire(AosLocks.AosModules);
			m := root; WHILE (m # NIL) & (m.term = NIL) DO m := m.next END;
			IF m # NIL THEN term := m.term; m.term := NIL END;
			AosLocks.Release(AosLocks.AosModules);
			IF m = NIL THEN EXIT END;
			IF trace THEN
				AosOut.Enter; AosOut.String("TermHandler "); AosOut.String(m.name); AosOut.Exit
			END;
			term()	(* if this causes exception or hangs, another shutdown call will retry *)
		END;
			(* clean up finalizers *)
		m := root;
		WHILE m # NIL DO
			AosHeap.CleanupModuleFinalizers(SYSTEM.ADR(m.code[0]), LEN(m.code), m.name);
			m := m.next
		END;
		IF trace THEN
			AosOut.Enter; AosOut.String("AosModules.Shutdown finished"); AosOut.Exit
		END;
		AosBoot.Shutdown(code = Reboot)	(* does not return *)
	END
END Shutdown;

(** Return the specified kernel procedure address. *)

PROCEDURE GetKernelProc*(num: LONGINT): LONGINT;
VAR adr: LONGINT;
BEGIN
	adr := kernelProc[253-num];
	ASSERT(adr # 0);
	RETURN adr
END GetKernelProc;

PROCEDURE Init;
VAR
	newArr: PROCEDURE (VAR p: SYSTEM.PTR;  elemTag, numElems, numDims: LONGINT);
	newSys: PROCEDURE (VAR p: SYSTEM.PTR;  size: LONGINT);
	newRec: PROCEDURE (VAR p: SYSTEM.PTR;  tag: LONGINT);
	s: ARRAY 4 OF CHAR;
BEGIN
	(* root and initBlock are initialized by the linker *)
	shutdown := None;
	newArr := AosHeap.NewArr;
	newSys := AosHeap.NewSys;
	newRec := AosHeap.NewRec;
	kernelProc[0] := SYSTEM.VAL(LONGINT, newRec);	(* 253 *)
	kernelProc[1] := SYSTEM.VAL(LONGINT, newSys);	(* 252 *)
	kernelProc[2] := SYSTEM.VAL(LONGINT, newArr);	(* 251 *)
	kernelProc[3] := 0;	(* 250 *)
	kernelProc[4] := 0;	(* 249 *)
	kernelProc[5] := 0;	(* 248 *)
	kernelProc[6] := 0;	(* 247 *)
	kernelProc[7] := 0;	(* 246 *)
	kernelProc[8] := 0;	(* 245 *)
	kernelProc[9] := 0;	(* 244 *)
	numLoaders := 0;
	freeRoot := NIL;
	AosBoot.GetConfig("TraceModules", s);
	trace := (s[0] = "1")
END Init;

BEGIN
	IF AosBoot.Trace THEN AosOut.Enter; AosOut.String("AosModules"); AosOut.Exit END;
	Init
END AosModules.

(*
19.03.1998	pjm	Started
06.10.1998	pjm	FreeModule

Note:
o ThisCommand race: process A calls ThisModule, the module is published, but before its body has finished executing, process B calls ThisCommand, causing the assert (m.init) to fail.  Process B should perhaps wait in this case until the body has executed, or ThisCommand should return NIL (but that will just move the race to the user).
*)

(*
to do:
o metaprogramming riders?
*)
