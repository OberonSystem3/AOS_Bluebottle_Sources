MODULE AosEventsUtils; (** AUTHOR "staubesv"; PURPOSE "System events utilities"; *)
(**
 * History:
 *
 *	07.03.2007	First release (staubesv)
 *)
 
IMPORT
	AosCommands, AosEvents, AosIO, AosFS, Utilities;
	
CONST

	(** Result codes for system event operations *)
	Ok* = 0;
	Error* = 1;
	Uncomplete* = 3;

	DateTimeFormat = "dd.mm.yyyy hh:nn:ss"; (* don't change or adapt DateTimeFromStream *)

TYPE

	EventWrapper* = POINTER TO RECORD
		nextIndex- : LONGINT; (* index of next free place in events array *)
		events- : POINTER TO ARRAY OF AosEvents.Event;
		next- : EventWrapper;
	END;
	
TYPE
	
	EventContainer* = OBJECT(AosEvents.Sink)
	VAR
		nofWrappers, nofEvents : LONGINT;
	
		(* stamps *)
		lastCleared, lastAdded : LONGINT;
	
		events, current : EventWrapper;
		maxNofWrappers, eventsPerWrapper : LONGINT;
		
		(* for polling *)
		PROCEDURE GetStamp*() : LONGINT;
		BEGIN
			RETURN lastAdded;
		END GetStamp;
		
		PROCEDURE GetEvents*(VAR nofEvents : LONGINT; VAR full : BOOLEAN; VAR lastCleared : LONGINT) : EventWrapper;
		BEGIN {EXCLUSIVE}
			nofEvents := SELF.nofEvents;
			full := nofEvents = maxNofWrappers * eventsPerWrapper;
			RETURN events;
		END GetEvents;
		
		PROCEDURE IsFull*() : BOOLEAN;
		BEGIN {EXCLUSIVE}
			RETURN nofEvents = maxNofWrappers * eventsPerWrapper;
		END IsFull;
		
		PROCEDURE Clear*;
		BEGIN {EXCLUSIVE}
			events.next := NIL; events.nextIndex := 0;
			current := events;
			nofWrappers := 1; nofEvents := 0;
			INC(lastCleared); INC(lastAdded);
		END Clear;		
		
		(** Returns the maximum number of event records this container can hold *)
		PROCEDURE GetSize*() : LONGINT;
		BEGIN
			RETURN maxNofWrappers * eventsPerWrapper;
		END GetSize;
		
		PROCEDURE Handle*(event : AosEvents.Event);
		VAR wrapper : EventWrapper;
		BEGIN {EXCLUSIVE}
			IF nofEvents = maxNofWrappers * eventsPerWrapper THEN RETURN; END;

			IF (current.nextIndex >= LEN(current.events)) THEN
				NEW(wrapper); NEW(wrapper.events, eventsPerWrapper); wrapper.nextIndex := 0;
				current.next := wrapper;
				current := wrapper;		
				INC(nofWrappers);
			END;
			
			current.events[current.nextIndex] := event;
			INC(current.nextIndex);
			INC(nofEvents);
			INC(lastAdded);
		END Handle;
		
		PROCEDURE &Init(maxNofWrappers, eventsPerWrapper : LONGINT);
		BEGIN
			SELF.maxNofWrappers := maxNofWrappers; 
			SELF.eventsPerWrapper:= eventsPerWrapper;
			NEW(events); NEW(events.events, eventsPerWrapper); events.nextIndex := 0;
			current := events;
			nofWrappers := 1; nofEvents := 0;
		END Init;
	
	END EventContainer;
	
PROCEDURE LoadFromFile*(filename : ARRAY OF CHAR; VAR events : EventContainer; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
VAR file : AosFS.File; r : AosFS.Reader; event : AosEvents.Event; nofEvents : LONGINT;
BEGIN
	file := AosFS.Old(filename);
	IF file # NIL THEN
		AosFS.OpenReader(r, file, 0);
		NEW(events, 1024, 1024);
		nofEvents := 0;
		WHILE (r.Available() > 0) & (r.res = AosIO.Ok) DO
			FromStream(r, event, msg, res);
			IF res = Ok THEN
				INC(nofEvents);
				events.Handle(event);
			ELSE
				IF (nofEvents = 0) THEN 
					res := Error; 
				ELSE
					res := Uncomplete;
				END;
				RETURN;
			END;
		END;
		res := Ok;
	ELSE
		msg := "File not found"; res := Error;
	END;	
END LoadFromFile;

PROCEDURE StoreToFile*(filename : ARRAY OF CHAR; events : EventContainer; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
VAR 
	file : AosFS.File; w : AosFS.Writer; wrapper : EventWrapper;
	nofEvents, lastCleared, i, idx : LONGINT; full : BOOLEAN;
BEGIN
	file := AosFS.New(filename);
	IF file # NIL THEN
		AosFS.OpenWriter(w, file, 0);
		wrapper := events.GetEvents(nofEvents, full, lastCleared);
		IF nofEvents > 0 THEN
			i := 0;
			WHILE (i < nofEvents) DO
				IF i >= LEN(wrapper.events) THEN wrapper := wrapper.next; END;
				idx := i MOD LEN(wrapper.events);
				ToStream(w, wrapper.events[idx]);
				INC(i);
			END;
			AosFS.Register(file);
			res := Ok;
		ELSE
			msg := "Number of events must be greater than zero"; res := Error;
		END;
	ELSE
		msg := "Could not create file"; res := Error;
	END;	
END StoreToFile;
	
PROCEDURE ToStream*(w : AosIO.Writer; event : AosEvents.Event);
VAR dt : Utilities.TDateTime; str : ARRAY 64 OF CHAR;
BEGIN
	ASSERT(w # NIL);
	dt := Utilities.OberonToDateTime(event.date, event.time);
	Utilities.FormatDateTime(DateTimeFormat, dt, str);
	w.String(str); w.String(" "); 
	w.String(GetTypeString(event.type)); w.String(" ");
	w.String('"'); w.String(event.originator); w.String('"');
	w.String(" ["); w.Int(event.class, 0); w.String(","); w.Int(event.subclass, 0); w.String(","); w.Int(event.code, 0); w.String('] "');
	w.String(event.message); w.String('"'); w.Ln; 
	w.Update;
END ToStream;

PROCEDURE FromStream*(r : AosIO.Reader; VAR event : AosEvents.Event; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
VAR dt : Utilities.TDateTime; str : AosEvents.Message; ch : CHAR; class, subclass, code : LONGINT;

	PROCEDURE IsValid(value : LONGINT) : BOOLEAN;
	BEGIN
		RETURN (0 <= value) & (value <= MAX(SHORTINT));
	END IsValid;	

BEGIN
	ASSERT(r # NIL);
	res := Error;
	r.SkipWhitespace;
	IF r.Available() = 0 THEN res := Ok; RETURN; END;
	(* date & time *)
	IF ~DateTimeFromStream(r, dt) THEN
		ch := r.Peek();
		IF r.res = AosIO.EOF THEN res := Ok; RETURN;
		ELSE
			msg := "Could not read datetime string"; RETURN; 
		END;
	END;
	Utilities.DateTimeToOberon(dt, event.date, event.time);
	(* type *)
	r.SkipWhitespace; r.String(str); IF (r.res # AosIO.Ok) THEN msg := "Could not read type string"; RETURN; END;
	event.type := GetType(str);
	(* originator *)
	r.SkipWhitespace; r.String(event.originator); IF (r.res # AosIO.Ok) THEN msg := "Could not read originator string"; RETURN; END;
	(* class, subclass & code *)
	r.SkipWhitespace; 
	r.Char(ch); IF (r.res # AosIO.Ok) OR (ch # "[") THEN msg := "Expected opening bracket"; RETURN; END;
	r.Int(class, FALSE); IF (r.res # AosIO.Ok) THEN	msg := "Could not parse event class"; RETURN; END;
	r.Char(ch); IF (r.res # AosIO.Ok) OR (ch # ",") THEN msg := "Expected ,"; RETURN; END;
	r.Int(subclass, FALSE); IF (r.res # AosIO.Ok) THEN msg := "Could not parse event subclass"; RETURN; END;
	r.Char(ch); IF (r.res # AosIO.Ok) OR (ch # ",") THEN msg := "Expected ,"; RETURN; END;
	r.Int(code, FALSE); IF (r.res # AosIO.Ok) THEN msg := "Could not parse event code"; RETURN; END;
	r.Char(ch); IF (r.res # AosIO.Ok) OR (ch # "]") THEN msg := "Expected closing bracket"; RETURN; END;
	(* check validity of class/subclass/code *)
	IF ~IsValid(class) THEN msg := "Class must be in [0, 127]"; RETURN; END;
	IF ~IsValid(subclass) THEN msg := "Subclass must be in [0, 127]"; RETURN; END;
	IF ~IsValid(code) THEN msg := "Code must be in [0, 127]"; RETURN; END;
	event.class := SHORT(SHORT(class));
	event.subclass := SHORT(SHORT(subclass));
	event.code := SHORT(SHORT(code));
	(* message *)
	r.SkipWhitespace; r.String(event.message); 
	IF (r.res # AosIO.EOF) & (~r.EOLN()) THEN msg := "Expected end of line"; RETURN; END; 
	res := Ok;
END FromStream;

PROCEDURE DateTimeFromStream(r : AosIO.Reader; VAR dt : Utilities.TDateTime) : BOOLEAN;
VAR ch : CHAR;
BEGIN
	ASSERT(r # NIL);
	r.SkipWhitespace; 
	r.Int(dt.Day, FALSE); 
	r.Char(ch); IF (r.res # AosIO.Ok) OR (ch # ".") THEN RETURN FALSE; END;
	r.Int(dt.Month, FALSE); 
	r.Char(ch); IF (r.res # AosIO.Ok) OR (ch # ".") THEN RETURN FALSE; END;
	r.Int(dt.Year, FALSE); 
	r.Char(ch); IF (r.res # AosIO.Ok) OR (ch # " ") THEN RETURN FALSE; END;
	r.Int(dt.Hour, FALSE);
	r.Char(ch); IF (r.res # AosIO.Ok) OR (ch # ":") THEN RETURN FALSE; END;
	r.Int(dt.Minute, FALSE);
	r.Char(ch); IF (r.res # AosIO.Ok) OR (ch # ":") THEN RETURN FALSE; END;
	r.Int(dt.Second, FALSE);
	IF (r.res # AosIO.Ok) THEN RETURN FALSE; END;
	RETURN Utilities.ValidDateTime(dt);
END DateTimeFromStream;

TYPE String16 = ARRAY 16 OF CHAR; 
PROCEDURE GetTypeString*(type : LONGINT) : String16;
VAR string, nbr : String16;
BEGIN
	CASE type OF
		|AosEvents.Unknown: string := "Unknown";
		|AosEvents.Undefined: string := "Undefined";
		|AosEvents.Information: string := "Information";
		|AosEvents.Warning: string := "Warning";
		|AosEvents.Error: string := "Error";
		|AosEvents.Critical: string := "Critical";
		|AosEvents.Alert: string := "Alert";
		|AosEvents.Failure: string := "Failure";
	ELSE
		string := "Unknown ("; Utilities.IntToStr(type, nbr); Utilities.Append(string, nbr); Utilities.Append(string, ")");
	END;
	RETURN string;
END GetTypeString;

PROCEDURE GetType*(string : ARRAY OF CHAR) : SHORTINT;
VAR type : SHORTINT;
BEGIN
	IF string = "Unknown" THEN type := AosEvents.Unknown;
	ELSIF string = "Undefined" THEN type := AosEvents.Undefined;
	ELSIF string = "Information" THEN type := AosEvents.Information;
	ELSIF string = "Warning" THEN type := AosEvents.Warning;
	ELSIF string = "Error" THEN type := AosEvents.Error;
	ELSIF string = "Critical" THEN type := AosEvents.Critical;
	ELSIF string = "Alert" THEN type := AosEvents.Alert;
	ELSIF string = "Failure" THEN type := AosEvents.Failure;
	ELSE
		type := AosEvents.Unknown;
	END;
	RETURN type;
END GetType;

PROCEDURE GenerateEvent*(par : ANY) : ANY; (** originator type class subclass code message ~ *)
VAR r : AosIO.StringReader; event : AosEvents.Event; value : LONGINT;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(event.originator);
	r.SkipWhitespace; r.Int(value, FALSE); event.type := SHORT(SHORT(value));
	r.SkipWhitespace; r.Int(value, FALSE); event.class := SHORT(SHORT(value));
	r.SkipWhitespace; r.Int(value, FALSE); event.subclass := SHORT(SHORT(value));
	r.SkipWhitespace; r.Int(value, FALSE); event.code := SHORT(SHORT(value));
	r.SkipWhitespace; r.String(event.message);
	AosEvents.Add(event, FALSE);
	RETURN NIL
END GenerateEvent;

END AosEventsUtils.

