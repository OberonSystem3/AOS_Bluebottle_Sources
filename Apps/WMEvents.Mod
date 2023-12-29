MODULE WMEvents;	(** AUTHOR "TF"; PURPOSE "Events"; *)

IMPORT
	Utilities, AosOut;

TYPE
	String = Utilities.String;

	(** Generic Event Listener*)
	EventListener* = PROCEDURE  { DELEGATE } (sender, par : PTR);
	(** EventListenerFinder searches an EventListener by string in its context and returns the EventListener or NIL *)
	CompCommandFinder* = PROCEDURE { DELEGATE } (str : String) : EventListener;
	
	(* element of list of EventListeners *)
	EventListenerLink = POINTER TO RECORD
		event : EventListener;
		string : String;
		next : EventListenerLink;
	END;
	
	(** Event info class. CompCommand can be registered and unregistered to/from this class. *)
	EventSource* = OBJECT
	VAR
		listeners : EventListenerLink;
		name, info : String;
		owner : PTR;
		finder : CompCommandFinder;
		
		(** create an EventInfo for a component owner. Report name as the name of this event *)
		PROCEDURE &New*(owner : PTR; name, info : String; finder : CompCommandFinder);
		BEGIN
			SELF.owner := owner; SELF.name := name; SELF.info := info; SELF.finder := finder
		END New;
		
		PROCEDURE GetName*() : String;
		BEGIN
			RETURN name
		END GetName;
		
		PROCEDURE GetInfo*() : String;
		BEGIN
			RETURN info
		END GetInfo;
		
		(** Add a command to this event. Commands can be added more then once. *)
		PROCEDURE Add*(event : EventListener);
		VAR new : EventListenerLink;
		BEGIN {EXCLUSIVE}
			NEW(new); new.event := event; new.next := listeners; listeners := new
		END Add;
		
		(** Add an listener to this event. The listener is found by findig the component referenced in the string and then
			querying the component for the listener. Listeners can be added more then once.
			The dereferencing is done on demant at the first call. If the EventListener can not be found, the call to the
			respective listener is ignored. On each call, the EventListener is searched again *)
		PROCEDURE AddByString*(link : String);
		VAR new : EventListenerLink;
		BEGIN {EXCLUSIVE}
			NEW(new); new.string := link; new.next := listeners; listeners := new
		END AddByString;
		
		(** Remove the first found entry of event *)
		PROCEDURE Remove*(event : EventListener);
		VAR cur : EventListenerLink;
		BEGIN {EXCLUSIVE}
			IF listeners = NIL THEN RETURN END;
			IF (listeners # NIL) & (listeners.event = event) THEN listeners := listeners.next; RETURN END;
			cur := listeners;
			WHILE cur.next # NIL DO
				IF cur.next.event = event THEN cur.next := cur.next.next; RETURN END;
				cur := cur.next
			END
		END Remove;
		
		(** Remove the first found entry of event, specified as a string *)
		PROCEDURE RemoveByString*(string : String);
		VAR cur : EventListenerLink;
		BEGIN {EXCLUSIVE}
			IF (listeners # NIL) & (listeners.string # NIL) & (listeners.string^ = string^) THEN listeners := listeners.next; RETURN END;
			cur := listeners;
			WHILE cur.next # NIL DO
				IF (cur.next.string # NIL) & ( cur.next.string^ = string^) THEN cur.next := cur.next.next; RETURN END;
				cur := cur.next
			END
		END RemoveByString;
		
		(** Call the event with parameter par. The owner of the EventInfo class will be added in the event's sender parameter *)
		PROCEDURE Call*(par : PTR);
		VAR cur : EventListenerLink;
		BEGIN (* { EXCLUSIVE } *) (* TODO : why does the kernel crash if this is exclusive... need a trace cable *)
			cur := listeners; 
			WHILE cur # NIL DO 
				IF cur.event # NIL THEN cur.event(owner, par) 
				ELSE
					IF (cur.string # NIL) & (finder # NIL) THEN 
						cur.event := finder(cur.string);
						IF cur.event = NIL THEN AosOut.String("Fixup failed"); AosOut.String(cur.string^) END;
						IF cur.event # NIL THEN cur.event(owner, par) END
					END	
				END; 
				cur := cur.next
			END;
		END Call;
		
		(** return true if listeners are installed; Can be used to avoid calculating parameters, if there
		are no listeners *)
		PROCEDURE HasListeners*() : BOOLEAN;
		BEGIN {EXCLUSIVE}
			RETURN listeners # NIL
		END HasListeners;
	END EventSource;
	
TYPE
	EventSourceArray* = POINTER TO ARRAY OF EventSource;
	EventSourceList* = OBJECT
	VAR
		eventSources : EventSourceArray;
		nofEventSources : LONGINT;
		
		PROCEDURE &New ;
		BEGIN
			NEW(eventSources, 4)
		END New;
		
		PROCEDURE Add*(x : EventSource);
		BEGIN {EXCLUSIVE}
			IF nofEventSources = LEN(eventSources) THEN Grow END;
			eventSources[nofEventSources] := x;
			INC(nofEventSources)
		END Add;

		PROCEDURE Remove*(x : EventSource);
		VAR i : LONGINT;
		BEGIN {EXCLUSIVE}
			i := 0; WHILE (i < nofEventSources) & (eventSources[i] # x) DO INC(i) END;
			IF i < nofEventSources THEN 
				WHILE (i < nofEventSources - 1) DO eventSources[i] := eventSources[i + 1]; INC(i) END;
				DEC(nofEventSources);
				eventSources[nofEventSources] := NIL
			END
		END Remove;

		PROCEDURE Grow;
		VAR  new: EventSourceArray;
				i : LONGINT;
		BEGIN 
			NEW(new, LEN(eventSources) * 2);
			FOR i := 0 TO nofEventSources - 1 DO new[i] := eventSources[i] END;
			eventSources := new
		END Grow;
		
		PROCEDURE Enumerate*() : EventSourceArray;
		VAR current : EventSourceArray; i : LONGINT;
		BEGIN {EXCLUSIVE}
			NEW(current, nofEventSources);
			FOR i := 0 TO nofEventSources - 1 DO current[i] := eventSources[i] END;
			RETURN current
		END Enumerate;
		
		PROCEDURE GetEventSourceByName*(name : String) : EventSource;
		VAR i : LONGINT; n : String;
		BEGIN {EXCLUSIVE}
			i := 0; 
			WHILE i < nofEventSources DO
				n := eventSources[i].GetName();
				IF (n # NIL) & (n^ = name^) THEN RETURN eventSources[i] END;
				INC(i)
			END;
			RETURN NIL
		END GetEventSourceByName;

	END EventSourceList;

TYPE 
	EventListenerInfo* = OBJECT
	VAR name, info : String;
		eventListener : EventListener;
		
		PROCEDURE &Init(name, info : String; handler : EventListener);
		BEGIN
			SELF.name := name; SELF.info := info; SELF.eventListener := handler
		END Init;
		
		PROCEDURE GetName*() : String;
		BEGIN
			RETURN name
		END GetName;
		
		PROCEDURE GetInfo*() : String;
		BEGIN
			RETURN info
		END GetInfo;
		
		PROCEDURE GetHandler*() : EventListener;
		BEGIN
			RETURN eventListener
		END GetHandler;
		
	END EventListenerInfo;
	
	EventListenerArray* = POINTER TO ARRAY OF EventListenerInfo;
	EventListenerList* = OBJECT
	VAR
		eventListeners : EventListenerArray;
		nofEventListeners : LONGINT;
		
		PROCEDURE &New ;
		BEGIN
			NEW(eventListeners, 4)
		END New;
		
		PROCEDURE Add*(x : EventListenerInfo);
		BEGIN {EXCLUSIVE}
			IF nofEventListeners = LEN(eventListeners) THEN Grow END;
			eventListeners[nofEventListeners] := x;
			INC(nofEventListeners)
		END Add;

		PROCEDURE Remove*(x : EventListenerInfo);
		VAR i : LONGINT;
		BEGIN {EXCLUSIVE}
			i := 0; WHILE (i < nofEventListeners) & (eventListeners[i] # x) DO INC(i) END;
			IF i < nofEventListeners THEN 
				WHILE (i < nofEventListeners - 1) DO eventListeners[i] := eventListeners[i + 1]; INC(i) END;
				DEC(nofEventListeners);
				eventListeners[nofEventListeners] := NIL
			END
		END Remove;

		PROCEDURE Grow;
		VAR  new: EventListenerArray;
				i : LONGINT;
		BEGIN 
			NEW(new, LEN(eventListeners) * 2);
			FOR i := 0 TO nofEventListeners - 1 DO new[i] := eventListeners[i] END;
			eventListeners := new
		END Grow;
		
		PROCEDURE Enumerate*() : EventListenerArray;
		VAR current : EventListenerArray; i : LONGINT;
		BEGIN {EXCLUSIVE}
			NEW(current, nofEventListeners);
			FOR i := 0 TO nofEventListeners - 1 DO current[i] := eventListeners[i] END;
			RETURN current
		END Enumerate;
		
		PROCEDURE GetHandlerByName*(name : String) : EventListener;
		VAR i : LONGINT; n : String; workaround : EventListener;
		BEGIN {EXCLUSIVE}
			i := 0; 
			WHILE i < nofEventListeners DO
				n := eventListeners[i].GetName();
				IF (n # NIL) & (n^ = name^) THEN 
					RETURN eventListeners[i].GetHandler() 
				END;
				INC(i)
			END;
			workaround := NIL;
			RETURN workaround 
		END GetHandlerByName; 

	END EventListenerList;
	

END WMEvents.
 
