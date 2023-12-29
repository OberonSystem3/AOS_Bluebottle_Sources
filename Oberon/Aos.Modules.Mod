(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE Modules;
(** AUTHOR "pjm"; PURPOSE "Oberon for Aos module loader"; *)

IMPORT AosOut, AosModules, Kernel;

TYPE
	Command* = AosModules.CommandProc;
	Module* = AosModules.Module;
	ModuleName* = AosModules.Name;
	
VAR
	res*: INTEGER;
	resMsg*: ARRAY 256 OF CHAR;
	extension*: ARRAY 8 OF CHAR;
	
PROCEDURE FindMod*(name: ARRAY OF CHAR): Module;
BEGIN
	RETURN AosModules.ModuleByName(name)
END FindMod;

PROCEDURE ThisMod*(name: ARRAY OF CHAR): Module;
VAR m: Module;  r: LONGINT;
BEGIN
	m := AosModules.ThisModule(name, r, resMsg);
	res := SHORT(r);
	(*Kernel.modules := AosModules.root;*)
	RETURN m
END ThisMod;

PROCEDURE ThisCommand*(mod: Module;  name: ARRAY OF CHAR): Command;
VAR c: Command;
BEGIN
	c := AosModules.ThisCommand(mod, name);
	IF c = NIL THEN
		COPY(mod.name, resMsg);  AosModules.Append(".", resMsg);  AosModules.Append(name, resMsg);
		AosModules.Append(" not found", resMsg);
		res := 5
	ELSE
		res := 0;  resMsg := ""
	END;
	RETURN c
END ThisCommand;

PROCEDURE Free*(name: ARRAY OF CHAR; all: BOOLEAN);
VAR r: LONGINT;
BEGIN
	ASSERT(~all);	(* not implemented *)
	AosModules.FreeModule(name, r, resMsg);
	res := SHORT(r)
END Free;

PROCEDURE InstallTermHandler*(h: AosModules.TerminationHandler);
BEGIN
	AosModules.InstallTermHandler(h)
END InstallTermHandler;

BEGIN
	(*AosOut.String("Modules");  AosOut.Ln;*)
	COPY(AosModules.extension[0], extension)	(* hack for Compiler to recognize Aos *)
END Modules.

(*
26.05.98	pjm	Started
*)
