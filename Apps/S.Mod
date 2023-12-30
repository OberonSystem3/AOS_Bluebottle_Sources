MODULE S; (** AUTHOR "TF"; PURPOSE "Access to System Functions"; *)
(**
 * History:
 *
 *	27.09.2006	Added DoCommands, Show & Time procedures (staubesv)
 *	20.12.2006 	Added Ln command (staubesv)
 *	28.02.2007	Added commands Timer, CollectGarbage, IsLoaded and WhoImports, merged AosTools.Mod into this module (staubesv)
 *)
 
IMPORT
	AosOut, AosModules, AosActive, AosHeap, AosCommands, AosKernel, AosIO, Utilities, AosFS;
	
CONST
	MaxTimers = 16;

	DateTimeFormat = "dd.mm.yyyy hh:nn:ss";

	CR = 0DX;  LF = 0AX;  TAB = 9X;
	
	TraceCommands = 1;
	TraceFreeDownTo = 2;
	
	Trace = {};
	
TYPE

	Module = POINTER TO RECORD
		next: Module;
		checked, imports: BOOLEAN;
		m: AosModules.Module
	END;

VAR
	timers : ARRAY MaxTimers OF Utilities.TDateTime;
	
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

PROCEDURE ModuleIsLoaded(name : AosModules.Name) : BOOLEAN;
BEGIN
	RETURN AosModules.ModuleByName(name) # NIL;
END ModuleIsLoaded;

(** Show all modules that import 'basemodule' (transitively) and are currently loaded. *)

PROCEDURE WhoImports*(par : ANY) : ANY; (** basemodule ~ *)
VAR r : AosIO.StringReader; name : AosModules.Name; root, m : Module;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(name);
	IF ModuleIsLoaded(name) THEN
		AosOut.String("Module "); AosOut.String(name); AosOut.String(" is imported by: "); AosOut.Ln;
		root := CopyModules();
		m := root;
		WHILE m # NIL DO
			IF Imports(root, m, name) THEN
				AosOut.String(m.m.name); AosOut.Ln;
			END;
			m := m.next;
		END;
	ELSE
		AosOut.String("Module "); AosOut.String(name); AosOut.String(" is not loaded."); AosOut.Ln;
	END;
	RETURN NIL
END WhoImports;

(** Check whether the specified module is currenlty loaded. *)

PROCEDURE IsLoaded*(par : ANY) : ANY;
VAR r : AosIO.StringReader; name : AosModules.Name;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(name);
	AosOut.String("Module "); AosOut.String(name);
	IF ModuleIsLoaded(name) THEN
		AosOut.String(" is loaded."); 
	ELSE
		AosOut.String(" is not loaded.");
	END;
	AosOut.Ln;
	RETURN NIL
END IsLoaded;

(** Free all modules that import basemodule (transitively). *)
PROCEDURE FreeDownTo*(par: PTR): PTR; (** basemodule ~ *)
VAR
	r : AosIO.StringReader; modulename : ARRAY 128 OF CHAR;
	root, m: Module; res: LONGINT;
	timer: AosKernel.Timer; msg: ARRAY 64 OF CHAR;
	nbrOfUnloadedModules : LONGINT;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(modulename);
	LockOberon;
	NEW(timer); timer.Sleep(200); (* temporary workaround for race with System.FreeOberon *)
	root := CopyModules();

	nbrOfUnloadedModules := 0;
	m := root;
	WHILE m # NIL DO
		IF Imports(root, m, modulename) THEN
			IF TraceFreeDownTo IN Trace  THEN
				AosOut.Enter; AosOut.String(m.m.name); AosOut.Exit
			END;
			AosModules.FreeModule(m.m.name, res, msg);
			IF res # 0 THEN
				AosOut.Enter; AosOut.String(msg); AosOut.Exit
			ELSE
				INC(nbrOfUnloadedModules);
			END
		END;
		m := m.next
	END;
	UnlockOberon; (* in case Oberon still running *)
	AosOut.String("Unloaded "); AosOut.Int(nbrOfUnloadedModules, 0); AosOut.String(" modules."); AosOut.Ln;
	RETURN NIL
END FreeDownTo;

(** Unload modules from memory *)
PROCEDURE Free*(par : ANY) : ANY; (** {modulename} ~ *)
VAR
	s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	name : ARRAY 64 OF CHAR;
	msg : ARRAY 128 OF CHAR;
	res : LONGINT;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	WHILE sr.res = 0 DO
		sr.Token(name); sr.SkipWhitespace;
		IF name # "" THEN
			AosOut.String("Unloading "); AosOut.String(name); AosOut.String("... ");
			AosModules.FreeModule(name, res, msg);
			IF res # 0 THEN AosOut.String(msg)
			ELSE AosOut.String("done.")
			END;
			AosOut.Ln;
		END
	END;
	RETURN NIL
END Free;

PROCEDURE Kill*(par : ANY) : ANY;
TYPE
	ProcessList = POINTER TO RECORD
		next: ProcessList;
		thread: AosActive.Process
	END;
VAR
	t: AosActive.Process;
	list, n: ProcessList;
	s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	pid : LONGINT;
BEGIN {EXCLUSIVE}
	AosActive.snapshotEnabled := TRUE;  list := NIL;
	AosHeap.GC;
	WHILE AosActive.snapshot # NIL DO
		t := AosActive.snapshot;  AosActive.snapshot := t.link;  t.link := NIL;
		NEW(n);  n.thread := t;  n.next := list;  list := n
	END;

	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	WHILE sr.res = 0 DO
		sr.SkipWhitespace;
		sr.Int(pid, FALSE);
		n := list;  WHILE (n # NIL) & (n.thread.id # pid) DO n := n.next END;
		AosOut.Int(pid, 0); 
		IF n # NIL THEN
			AosActive.TerminateThis(n.thread, FALSE);
			AosOut.String(" Process killed") 
		ELSE AosOut.String(" Process not found")
		END;
		AosOut.Ln 
	END;
	RETURN NIL
END Kill;

(* Changes the extension, Usage: RenameExtension extFrom extTo~ *)
PROCEDURE RenameExtension*(par: ANY): ANY;
VAR s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	enumerator : AosFS.Enumerator;
	oe, ne, temp: ARRAY 16 OF CHAR;
	name, file, ext : ARRAY 256 OF CHAR; flags : SET; time, date, size, res : LONGINT;
BEGIN
	s := par(AosCommands.Parameters); NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.SkipWhitespace(); sr.Token(oe); sr.SkipWhitespace(); sr.Token(ne);
	NEW(enumerator);
	temp := "*.";
	Utilities.Append(temp, oe);
	enumerator.Open(temp, {});
	temp := ".";
	Utilities.Append(temp, ne);
	AosOut.String("-- Renaming Extension --"); AosOut.Ln;
	WHILE enumerator.HasMoreEntries() DO
		IF enumerator.GetEntry(name, flags, time, date, size) THEN
			Utilities.GetExtension(name, file, ext);
			Utilities.Append(file, temp);
			AosOut.String("Renaming: "); AosOut.String(name); AosOut.String(" to: "); AosOut.String(file);
			AosFS.Rename(name, file, res);
			IF res = 0 THEN AosOut.String("    done"); ELSE AosOut.String("   Error!"); END;
			AosOut.Ln;
		END;
	END;
	AosOut.String("-- all done --"); AosOut.Ln;
	enumerator.Close;
	RETURN NIL;	
END RenameExtension;

PROCEDURE IsDelimiter(ch : CHAR) : BOOLEAN;
BEGIN
	RETURN (ch = " ") OR (ch = CR) OR (ch = LF) OR (ch = TAB) OR (ch = ";") OR (ch = 0X);
END IsDelimiter;		

(** Sequentially execute a list of commands *)
PROCEDURE DoCommands*(parameter : ANY) : ANY; (** command {";" command}  "~" *)
VAR
	p : AosCommands.Parameters; 
	commands : Utilities.StringArray;
	command, parameters : Utilities.String;
	msg : ARRAY 128 OF CHAR;
	i, j, k, res : LONGINT;	
BEGIN
	p := parameter (AosCommands.Parameters);
	commands := Utilities.Split(p.str^, ";");
	NEW(command, LEN(p.str^)); NEW(parameters, LEN(p.str^));
	i := 0;
	LOOP
		Utilities.TrimWS(commands[i]^);
		
		(* extract command *)
		j := 0; k := 0;
		WHILE ~IsDelimiter(commands[i][j])  DO command[k] := commands[i][j]; INC(k); INC(j); END;
		command[k] := 0X;
		IF k = 0 THEN EXIT; END;	(* end of string *)
		
		(* extract parameters *)
		k := 0;
		IF (commands[i][j] # ";") & (commands[i][j] # 0X) THEN
			INC(j); WHILE (commands[i][j] # 0X) & (commands[i][j] # ";") DO parameters[k] := commands[i][j]; INC(k); INC(j); END;
			parameters[k] := 0X;
		END;
		IF k > 0 THEN 
			NEW(p); NEW(p.str, k+1); 
			FOR j := 0 TO k DO p.str[j] := parameters[j]; END; 
		ELSE
			p := NIL;
		END;
		
		IF TraceCommands IN Trace THEN
			AosOut.String("S.DoCommands: Execute command '"); AosOut.String(command^);
			AosOut.String("' parameters: ");
			IF p = NIL THEN AosOut.String("None"); ELSE AosOut.String("'"); AosOut.String(p.str^); AosOut.String("'"); END;
			AosOut.Ln;
		END;
		
		AosCommands.Activate(command^, p, {AosCommands.Wait}, res, msg);
		
		IF res # AosCommands.Ok THEN
			AosOut.String("S.DoCommands: Command: '"); 
			AosOut.String(command^); AosOut.String("', parameters: "); 
			IF p = NIL THEN 
				AosOut.String("None");
			ELSE
				AosOut.String("'"); AosOut.String(p.str^); AosOut.String("'");
			END;
			AosOut.String(" failed: ");
			AosOut.String(msg); AosOut.String(" (res: "); AosOut.Int(res, 0); AosOut.String(")");
			AosOut.Ln;
			EXIT;
		END;
		INC(i);
		IF i >= LEN(commands) THEN EXIT; END;
	END;
	RETURN NIL;
END DoCommands;

(** Time interval measurement
 	- start/starth [number]: Set timer <number> to current time (number = 0 if omitted)
  	- elapsed/elapsedh [number]: Display time difference between timer <number> and the current time (number = 0 if omitted)
	- diff/diffh number1 number2: Display time difference between the two timers
	*)
PROCEDURE Timer*(par : ANY) : ANY; (** [  ["start"["h"] [number]] | ["elapsed"["h"] [number]] | ["diff"["h"] number1 number2]  ] ~ *)
VAR 
	r : AosIO.StringReader; string : ARRAY 128 OF CHAR; nbr1, nbr2 : LONGINT;	
	
	PROCEDURE ShowTime(hours, minutes, seconds : LONGINT);
	BEGIN
		IF hours < 10 THEN AosOut.Char("0"); END; AosOut.Int(hours, 0); AosOut.String(":");
		IF minutes < 10 THEN AosOut.Char("0"); END; AosOut.Int(minutes, 0); AosOut.String(":");
		IF seconds < 10 THEN AosOut.Char("0"); END; AosOut.Int(seconds, 0);
	END ShowTime;
	
	PROCEDURE ShowElapsed(start, end : Utilities.TDateTime);
	VAR hours, minutes, seconds : LONGINT;
	BEGIN
		hours := end.Hour - start.Hour;
		minutes := end.Minute - start.Minute;
		seconds := end.Second - start.Second;
		ShowTime(hours, minutes, seconds);
		IF (end.Year # start.Year) OR (end.Month # start.Month) OR (end.Day # start.Day) THEN
			AosOut.String(" (may be incorrect due to date change)");
		END;
	END ShowElapsed;

	PROCEDURE ShowUsage;
	BEGIN
		AosOut.String('Usage: S.Timer  [  ["start" [number]] | ["elapsed" [number]] | ["diff" number1 number2]  ]');
		AosOut.Ln;
	END ShowUsage;
	
	PROCEDURE Valid(number : LONGINT) : BOOLEAN;
	BEGIN
		RETURN (0 <= number) & (number < MaxTimers);
	END Valid;
	
BEGIN {EXCLUSIVE}
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(string);
	r.SkipWhitespace; r.Int(nbr1, FALSE);
	r.SkipWhitespace; r.Int(nbr2, FALSE);		
	
	IF ~Valid(nbr1) THEN ShowUsage; RETURN NIL; END;
	
	IF (string = "start") THEN
		timers[nbr1] := Utilities.Now();
	ELSIF (string = "elapsed") THEN
		ShowElapsed(timers[nbr1], Utilities.Now());
	ELSIF Valid(nbr2) THEN
		IF (string = "diff") THEN
			ShowElapsed(timers[nbr1], timers[nbr2]);
		ELSE
			ShowUsage;
		END;
	ELSE
		ShowUsage;
	END;
	RETURN NIL;
END Timer;

(** 
 * If no parameter is specified, this command displays the system time on Kernel Log.
 *)
PROCEDURE Time*(par : ANY) : ANY; (** ~ *)
VAR datetime : Utilities.TDateTime; string : ARRAY 32 OF CHAR;
BEGIN
	datetime := Utilities.Now();
	Utilities.FormatDateTime(DateTimeFormat, datetime, string);
	AosOut.String(string);	
	RETURN NIL
END Time;

(** Display a string on kernel log *)
PROCEDURE Show*(par : ANY) : ANY; (** string ~ *)
VAR parameters : AosCommands.Parameters;
BEGIN
	parameters := par (AosCommands.Parameters);
	IF parameters.str # NIL THEN
		Utilities.Trim(parameters.str^, '"');
		AosOut.String(parameters.str^);
	END;		
	RETURN NIL
END Show;

(** Print carriage return on kernel log *)
PROCEDURE Ln*(par : ANY) : ANY; (** ~ *)
BEGIN
	AosOut.Ln;
	RETURN NIL
END Ln;

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

(** Invoke garbage collector *)
PROCEDURE CollectGarbage*(par : ANY) : ANY;
BEGIN
	AosOut.String("Collecting garbage... ");
	AosKernel.GC;
	AosOut.String("done."); AosOut.Ln;
	RETURN NIL
END CollectGarbage;

END S.

S.Free S  ~
S.Kill 57 ~

S.Time ~
S.Show Hello World ~

S.DoCommands
	S.Timer start;
	S.Show "System Time "; S.Time; S.Ln;
	S.Show "System Time again "; S.Time; S.Ln;
	S.Show "Time elapsed: "; S.Timer elapsed; S.Ln;
~

S.CollectGarbage ~

