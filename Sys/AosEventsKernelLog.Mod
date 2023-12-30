MODULE AosEventsKernelLog; (** AUTHOR "staubesv"; PURPOSE "Log system events to kernel log"; *)
(**
 * Log system events to kernel log
 *
 * History:
 *
 *	07.03.2007	First release (staubesv)
 *)
 
IMPORT
	AosOut, AosModules, AosEvents, AosEventsUtils, AosIO;
	
CONST
	Verbose = TRUE;
	
	(* System event classification (AosEventClasses.XML) *)
	Class = 1;		(* Events *)
	Subclass = 2;	(* Logging *)
	
	ModuleName = "AosEventsKernelLog";
	
TYPE

	EventLogger = OBJECT(AosEvents.Sink)
	VAR w : AosIO.Writer;

		PROCEDURE Handle*(event : AosEvents.Event);
		BEGIN
			AosEventsUtils.ToStream(w, event);
		END Handle;
		
		PROCEDURE &Init;
		BEGIN
			name := ModuleName;
			NEW(w, AosOut.Send, 1024);
		END Init;
		
	END EventLogger;
	
VAR
	eventLogger- : EventLogger;

PROCEDURE Install*(par : ANY) : ANY;
BEGIN
	RETURN NIL
END Install;

PROCEDURE Cleanup;
BEGIN
	AosEvents.AddEvent(ModuleName, AosEvents.Information, Class, Subclass, 0, "Kernel log event logger shut down", Verbose);
	AosEvents.Unregister(eventLogger);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	NEW(eventLogger);
	AosEvents.Register(eventLogger);
	AosEvents.AddEvent(ModuleName, AosEvents.Information, Class, Subclass, 0, "Started kernel log event logger", Verbose);
END AosEventsKernelLog.

AosEventsKernelLog.Install ~		S.Free AosEventsKernelLog ~
