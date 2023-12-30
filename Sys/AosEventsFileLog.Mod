MODULE AosEventsFileLog; (** AUTHOR "staubesv"; PURPOSE "Log system events to files"; *)
(**
 * Log system events to files
 *
 * History:
 *
 *	07.03.2007	First release (staubesv)
 *)
 
IMPORT
	AosOut, AosModules, AosCommands, AosIO, AosFS, AosEvents, AosEventsUtils;
	
CONST

	DefaultLogFile = "AosEventLog.log";
	
	Verbose = TRUE;
		
	(* System event classification *)
	Class = 1; 		(* Events *)
	Subclass = 1;	(* Logging *)

	ModuleName = "AosEventsFileLog";

TYPE

	EventLogger = OBJECT(AosEvents.Sink)
	VAR w : AosFS.Writer;

		PROCEDURE Handle*(event : AosEvents.Event);
		BEGIN
			AosEventsUtils.ToStream(w, event);
		END Handle;
		
		PROCEDURE &Init(file : AosFS.File; append : BOOLEAN);
		VAR ofs : LONGINT;
		BEGIN
			ASSERT(file # NIL);
			IF append THEN ofs := file.Length(); ELSE ofs := 0; END;
			AosFS.OpenWriter(w, file, ofs);
			name := ModuleName;
		END Init;
		
	END EventLogger;
	
VAR
	eventLogger- : EventLogger;
	
PROCEDURE OpenFile(filename : ARRAY OF CHAR; append : BOOLEAN) : AosFS.File;
VAR file : AosFS.File;
BEGIN
	IF append THEN
		file := AosFS.Old(filename);
	ELSE
		file := AosFS.New(filename);
		AosFS.Register(file);
	END;
	RETURN file;	
END OpenFile;

PROCEDURE Start*(par : ANY) : ANY; (** [-append] [filename] ~ *)
VAR 
	r : AosIO.StringReader; 
	filename : ARRAY 256 OF CHAR; append : BOOLEAN;
	file : AosFS.File;
BEGIN {EXCLUSIVE}
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(filename);
	IF filename[0] = "-" THEN
		IF filename = "-append" THEN
			append := TRUE;
			r.SkipWhitespace; r.String(filename);
		ELSE
			Show("Unexpected parameter."); AosOut.Ln;
			RETURN NIL;
		END;
	END;
	IF eventLogger = NIL THEN
		IF filename = "" THEN filename := DefaultLogFile; END;
		file := OpenFile(filename, append);
		IF file # NIL THEN
			NEW(eventLogger, file, append);
			AosEvents.Register(eventLogger);
			AosEvents.AddEvent(ModuleName, AosEvents.Information, Class, Subclass, 0, "Started file log event logger", FALSE);
			Show("Logging system events to file "); AosOut.String(filename); AosOut.Ln;
		ELSE
		END;
	ELSE
		Show("Logger is already running."); AosOut.Ln;
	END;
	RETURN NIL
END Start;

PROCEDURE Stop*(par : ANY) : ANY; (** ~ *)
BEGIN {EXCLUSIVE}
	IF eventLogger # NIL THEN
		AosEvents.Unregister(eventLogger); eventLogger := NIL;
		AosEvents.AddEvent(ModuleName, AosEvents.Information, Class, Subclass, 0, "Stopped file log event logger", FALSE);
		Show("Logger stopped."); AosOut.Ln;
	ELSE
		Show("Logger is not running."); AosOut.Ln;
	END;
	RETURN NIL;
END Stop;

PROCEDURE Show(string : ARRAY OF CHAR);
BEGIN
	AosOut.String(ModuleName); AosOut.String(": "); AosOut.String(string);
END Show;

PROCEDURE Cleanup;
BEGIN
	IF eventLogger # NIL THEN
		AosEvents.AddEvent(ModuleName, AosEvents.Information, Class, Subclass, 0, "File log event logger shut down", Verbose);
		AosEvents.Unregister(eventLogger); eventLogger := NIL;
	END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END AosEventsFileLog.
