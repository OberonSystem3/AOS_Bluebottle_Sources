MODULE AosEventsMemoryLog; (** AUTHOR "staubesv"; PURPOSE "Log system events in memory"; *)
(**
 * History:
 *
 *	14.03.2007	First release (staubesv)
 *)
 
IMPORT
	AosModules, AosEvents, AosEventsUtils;
	
CONST

	(* Logsize = MaxNofWrapper * EventsPerWrapper events *)
	MaxNofWrapper = 16;
	EventsPerWrapper = 256;
	
TYPE

	EventLogger = OBJECT(AosEvents.Sink)
	VAR
		events : AosEventsUtils.EventContainer;
			
		PROCEDURE Handle*(event : AosEvents.Event);
		BEGIN
			IF ~events.IsFull() THEN
				events.Handle(event);
			END;
		END Handle;
		
		PROCEDURE &Init;
		BEGIN
			name := "EventLog";
			NEW(events, MaxNofWrapper, EventsPerWrapper);
		END Init;
		
	END EventLogger;
	
VAR 
	eventLog- : EventLogger;
	
PROCEDURE GetEvents*() : AosEventsUtils.EventContainer;
BEGIN
	RETURN eventLog.events;
END GetEvents;
	
PROCEDURE Clear*(par : ANY) : ANY;
BEGIN
	eventLog.events.Clear;
	RETURN NIL
END Clear;

PROCEDURE Cleanup;
BEGIN
	AosEvents.Unregister(eventLog);
END Cleanup;
	
BEGIN
	AosModules.InstallTermHandler(Cleanup);
	NEW(eventLog);
	AosEvents.Register(eventLog);
END AosEventsMemoryLog.
