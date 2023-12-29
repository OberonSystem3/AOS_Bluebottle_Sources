(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosTools; (** AUTHOR "pjm"; PURPOSE "Aos toolbox"; *)

(* FreeDownTo command is dynamically called by Aos.System on shutdown. *)

IMPORT AosOut, AosModules, AosKernel, AosCommands;	(* must not import any Oberon modules *)

CONST
	Trace = FALSE;

TYPE
	Module = POINTER TO RECORD
		next: Module;
		checked, imports: BOOLEAN;
		m: AosModules.Module
	END;

PROCEDURE Find(root: Module; m: AosModules.Module): Module;
BEGIN
	WHILE (root # NIL) & (root.m # m) DO root := root.next END;
	RETURN root
END Find;

PROCEDURE CopyModules(): Module;
VAR first, last, c: Module; m: AosModules.Module;
BEGIN
	NEW(first); first.next := NIL; last := first;
	m := AosModules.root;
	WHILE m # NIL DO
		NEW(c); c.checked := FALSE; c.imports := FALSE; c.m := m;
		c.next := NIL; last.next := c; last := c;
		m := m.next
	END;
	RETURN first.next
END CopyModules;

PROCEDURE Imports(root, m: Module; name: ARRAY OF CHAR): BOOLEAN;
VAR i: LONGINT;
BEGIN
	IF ~m.checked THEN
		IF m.m.name # name THEN
			i := 0;
			WHILE i # LEN(m.m.module) DO
				IF (m.m.module[i].name = name) OR Imports(root, Find(root, m.m.module[i]), name) THEN
					m.imports := TRUE; i := LEN(m.m.module)
				ELSE
					INC(i)
				END
			END
		ELSE
			m.imports := TRUE
		END;
		m.checked := TRUE
	END;
	RETURN m.imports
END Imports;

PROCEDURE LockOberon;
VAR m: AosModules.Module; c: AosModules.CommandProc;
BEGIN
	m := AosModules.ModuleByName("Kernel");
	IF m # NIL THEN
		c := AosModules.ThisCommand(m, "LockOberon");
		IF c # NIL THEN c END
	END
END LockOberon;

PROCEDURE UnlockOberon;
VAR m: AosModules.Module; c: AosModules.CommandProc;
BEGIN
	m := AosModules.ModuleByName("Kernel");
	IF m # NIL THEN
		c := AosModules.ThisCommand(m, "UnlockOberon");
		IF c # NIL THEN c END
	END
END UnlockOberon;

(* Free all modules that import basemodule (transitively). *)

PROCEDURE FreeDownTo*(par: PTR): PTR;	(** basemodule *)
VAR
	s: AosCommands.Parameters; root, m: Module; res: LONGINT;
	timer: AosKernel.Timer; msg: ARRAY 64 OF CHAR;
BEGIN
	s := par(AosCommands.Parameters);
	LockOberon;
	NEW(timer); timer.Sleep(200);	(* temporary workaround for race with System.FreeOberon *)
	root := CopyModules();
	
(*
	AosOut.String(s^); AosOut.String(" is imported by:");
	m := root;
	WHILE m # NIL DO
		IF Imports(root, m, s^) THEN
			AosOut.Char(" "); AosOut.String(m.m.name)
		END;
		m := m.next
	END;
	AosOut.Ln;
	
	AosOut.String(s^); AosOut.String(" is not imported by:");
	m := root;
	WHILE m # NIL DO
		IF ~Imports(root, m, s^) THEN
			AosOut.Char(" "); AosOut.String(m.m.name)
		END;
		m := m.next
	END;
	AosOut.Ln;
*)
	
	m := root;
	WHILE m # NIL DO
		IF Imports(root, m, s.str^) THEN
			IF Trace THEN
				AosOut.Enter; AosOut.String(m.m.name); AosOut.Exit
			END;
			AosModules.FreeModule(m.m.name, res, msg);
			IF res # 0 THEN
				AosOut.Enter; AosOut.String(msg); AosOut.Exit
			END
		END;
		m := m.next
	END;
	UnlockOberon;	(* in case Oberon still running *)
	RETURN NIL
END FreeDownTo;

PROCEDURE Reboot*(par: PTR): PTR;
BEGIN
	AosModules.Shutdown(AosModules.Reboot);
	RETURN NIL
END Reboot;

PROCEDURE PowerDown*(par: PTR): PTR;
BEGIN
	AosModules.Shutdown(AosModules.PowerDown);
	RETURN NIL
END PowerDown;

END AosTools.

System.Free AosTools ~

Aos.Call AosTools.FreeDownTo Objects

Aos.Call AosTools.FreeDownTo Kernel
Aos.Call AosTools.FreeDownTo Modules
Aos.Call AosTools.FreeDownTo Oberon
Aos.Call AosTools.FreeDownTo Files
Aos.Call AosTools.FreeDownTo Display3
