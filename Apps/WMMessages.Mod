MODULE WMMessages;	(** AUTHOR "TF"; PURPOSE "Support for messages and events"; *)

IMPORT
	Utilities, AosOut, AosActive, AosModules, AosKernel, Locks := WMLocks;
	
CONST	
	MsgQSize = 128;
	(** Predefined Messages *)
	MsgPointer* = 0; MsgKey* = 2; MsgClose* = 3; MsgStyleChanged* = 4; 
	MsgFocus* = 5; MsgExt* = 6; MsgDrag* = 7;
	MsgInvokeEvent* = 8; MsgInvokeGenerator* = 9; 
	MsgResized* = 10;

	MsgSubPointerMove* = 0; MsgSubPointerDown* = 1; MsgSubPointerUp* = 2; MsgSubPointerLeave* = 3;
	MsgSubFocusGot* = 0; MsgSubFocusLost* = 1; MsgSubMasterFocusGot* = 2; MsgSubMasterFocusLost* = 3;
	MsgDragOver* = 0; MsgDragDropped* = 1; 

	
TYPE
	(** Generic Component Command *)
	CompCommand* = PROCEDURE  { DELEGATE } (sender, par : PTR);
	String* = Utilities.String;
	
	(** Generic message structure *)
	Message* = RECORD
		originator*, (** the originator if # NIL passes information about the view that directly or indirectely lead to the msg *)
		sender* : PTR; (** is the sender component. If the message is originated form a component *)
		token* : AsyncToken; 
		event* : CompCommand;
		generator* : AosModules.CommandParProc;
		msgType*, msgSubType* : LONGINT; (** generic message type *)
		x*, y*, z*, dx*, dy*, dz* : LONGINT; (** in keyboard messages : ucs value in x, keysym in y *)
		flags* : SET; (** in pointer messages : keys in flags *)
		ext* : PTR; (** extended message *)
	END;
	
	MessageExtension* = OBJECT END MessageExtension;

	(** AsyncToken can be used to synchronize asynchronous method invocation *)
	AsyncToken* = OBJECT
	VAR ready : BOOLEAN;
		result* : PTR;
		
		(** Reset is called in case the token was recycled *)
		PROCEDURE Reset*;
		BEGIN {EXCLUSIVE}
			ready := FALSE;
		END Reset;
		
		(** wait until the result is completed *)
		PROCEDURE AwaitCompletion*();
		BEGIN {EXCLUSIVE}
			AWAIT(ready)
		END AwaitCompletion;
		
		(** Return if the result is completed *)
		PROCEDURE IsCompleted*():BOOLEAN;
		BEGIN {EXCLUSIVE}
			RETURN ready
		END IsCompleted;
		
		(** Called by the asynchronous process to indicate the result is available *)
		PROCEDURE Completed*;
		BEGIN {EXCLUSIVE}
			ready := TRUE
		END Completed;
	END AsyncToken;
	
	(* element of list of EventListeners *)
	CompCommandLink = POINTER TO RECORD
		event : CompCommand;
		string : String;
		next : CompCommandLink;
	END;
	
	(** EventListenerFinder searches an EventListener by string in its context and returns the EventListener or NIL *)
	CompCommandFinder* = PROCEDURE { DELEGATE } (str : String) : CompCommand;
	
(*	(** Event info class. CompCommand can be registered and unregistered to/from this class. *)
	EventInfo* = OBJECT
	VAR
		listeners : CompCommandLink;
		name- : String;
		owner : PTR;
		finder : CompCommandFinder;
		
		(** create an EventInfo for a component owner. Report name as the name of this event *)
		PROCEDURE &New*(owner : PTR; name : String; finder : CompCommandFinder);
		BEGIN
			SELF.owner := owner; SELF.name := name; SELF.finder := finder
		END New;
		
		(** Set the owner of the event *)
		PROCEDURE SetOwner*(owner : PTR);
		BEGIN {EXCLUSIVE}
			SELF.owner := owner
		END SetOwner;
		
		(** Set the event finder method. *)
		PROCEDURE SetFinder*(finder : CompCommandFinder);
		BEGIN {EXCLUSIVE}
			SELF.finder := finder
		END SetFinder;
		
		(** Add a command to this event. Commands can be added more then once. *)
		PROCEDURE Add*(event : CompCommand);
		VAR new : CompCommandLink;
		BEGIN {EXCLUSIVE}
			NEW(new); new.event := event; new.next := listeners; listeners := new
		END Add;
		
		(** Add an listener to this event. The listener is found by findig the component referenced in the string and then
			querying the component for the listener. Listeners can be added more then once.
			The dereferencing is done on demant at the first call. If the EventListener can not be found, the call to the
			respective listener is ignored. On each call, the EventListener is searched again *)
		PROCEDURE AddByString*(link : String);
		VAR new : CompCommandLink;
		BEGIN {EXCLUSIVE}
			NEW(new); new.string := link; new.next := listeners; listeners := new
		END AddByString;
		
		(** Remove the first found entry of event *)
		PROCEDURE Remove*(event : CompCommand);
		VAR cur : CompCommandLink;
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
		VAR cur : CompCommandLink;
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
		VAR cur : CompCommandLink;
		BEGIN {EXCLUSIVE}
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
	END EventInfo;
	*)
	(** Message handler that can be called from the sequencer *)
	MessageHandler* = PROCEDURE {DELEGATE} (VAR msg : Message);
	
	(** The TrapHandler must return TRUE if the process should restart. Otherwise the process is stopped *)
	TrapHandler* = PROCEDURE {DELEGATE} () : BOOLEAN;
	
(** Message sequencer *)
	MsgSequencer* = OBJECT
		VAR
			msgQHead, msgQTail : LONGINT;
			msgQ : ARRAY MsgQSize OF Message;
			alive, continue, hadOverflow : BOOLEAN;
			msg : Message;
			result : PTR;
			handler : MessageHandler;
			originator : PTR;
			me : PTR; (* Thread for caller identification *)
			lock* : Locks.RWLock;
			th, traphandler : TrapHandler;
			name* : String;
			trapOnOverflow* : BOOLEAN;
		
		PROCEDURE &New(handler : MessageHandler);
		BEGIN
			NEW(lock);
			SELF.handler := handler; alive := FALSE; continue := TRUE; hadOverflow := FALSE;
		END New;
		
		(** Add a trap handler for this process. This handler only decides whether to continue or to abort the process.
			If continued, the lock will be reset *)
		PROCEDURE SetTrapHandler*(th : TrapHandler);
		BEGIN {EXCLUSIVE}
			traphandler := th
		END SetTrapHandler;
		
		(** Return true if called from (this) sequencer *)
		PROCEDURE IsCallFromSequencer*() : BOOLEAN;
		BEGIN
			RETURN AosActive.ActiveObject() = me
		END IsCallFromSequencer;
		
		(** RETURN the originator (view) of the message that lead directly or indirectly to this request.
			Returns NIL if the call is not from the sequencer  *)
		PROCEDURE GetOriginator*() : PTR;
		BEGIN
			IF AosActive.ActiveObject() = me THEN RETURN originator
			ELSE RETURN NIL
			END
		END GetOriginator;
		
		(** Add a message to a queue. Discards the message if the queue is full *)
		PROCEDURE Add*(VAR msg : Message) : BOOLEAN;
		VAR i:LONGINT;
		BEGIN {EXCLUSIVE}
			IF (msg.msgType = MsgPointer) & (msg.msgSubType = MsgSubPointerMove) & (msgQHead # msgQTail)THEN  (* reduce pointer moves in buffer *)
				i := (msgQTail + MsgQSize - 1) MOD MsgQSize; 
				IF (msgQ[i].msgType = MsgPointer) & (msg.msgSubType = MsgSubPointerMove) & (msgQ[i].flags = msg.flags) THEN 
					msgQ[i].x := msg.x; msgQ[i].y := msg.y;  RETURN TRUE
				END
			END;
			IF (msgQTail + 1) MOD MsgQSize # msgQHead THEN
				msgQ[msgQTail] := msg; msgQTail := (msgQTail + 1) MOD MsgQSize;
				RETURN TRUE
			ELSE
				IF ~hadOverflow THEN IF name # NIL THEN AosOut.String(name^); AosOut.String(" : ") END;
					IF trapOnOverflow THEN HALT(123456) END;
				AosOut.String("Message queue overflow "); AosOut.Ln; hadOverflow := TRUE END;
				RETURN FALSE
			END
		END Add;
		
		PROCEDURE Handle(VAR msg : Message) : BOOLEAN;
		BEGIN
			(* if asynchronous call --> synchronize *)
			IF ~IsCallFromSequencer() THEN RETURN Add(msg)
			ELSE
				IF msg.msgType = MsgInvokeEvent THEN (* MsgInvokeEvent *)
					IF msg.event # NIL THEN 
						msg.event(msg.sender, msg.ext); 
						IF msg.token # NIL THEN msg.token.Completed END
					END
				ELSIF msg.msgType = MsgInvokeGenerator THEN (* MsgInvokeGenerator *)
					IF msg.generator # NIL THEN 
						result := msg.generator(msg.ext);
						IF msg.token # NIL THEN msg.token.result := result; msg.token.Completed END
					END
				ELSE handler(msg) (* Generic message *)
				END;
				RETURN TRUE
			END
		END Handle;
		
(*		(** Call an event on behalf of the sequencer thread. Waits until the event has been delivered by the sequencer *)
		PROCEDURE InvokeEvent*(event : CompCommand; sender, par : PTR); (** FINAL *)
		VAR invokeMsg : Message; 
		BEGIN
			invokeMsg.msgType := MsgInvokeEvent;
			invokeMsg.sender := sender; invokeMsg.ext := par;
			invokeMsg.event := event;
	(*		invokeMsg.token := GetAsyncToken();
			ASSERT(Handle(invokeMsg)); (* if the invoke is not scheduled, AwaitCompletion can take VERY long *)
			invokeMsg.token.AwaitCompletion;
			RecycleAsyncToken(invokeMsg.token) *)
		END InvokeEvent; *)
		
(*		(** Call an event on behalf of the sequencer thread. Returns as soon as the event is scheduled in the sequencer.
			Returns a token that can be used to block until the event is executed.
			P.S. It would be nice if you could throw the token into the RecycleAsyncToken recycle bin to relieve the GC. 
			But make sure it is really no longer used.	
		*)
		PROCEDURE InvokeEventAsync*(event : CompCommand; sender, par : PTR) : AsyncToken; (** FINAL *)
		VAR invokeMsg : Message;
		BEGIN
			invokeMsg.msgType := MsgInvokeEvent;
			invokeMsg.sender := sender; invokeMsg.ext := par;
			invokeMsg.event := event;
			invokeMsg.token := GetAsyncToken();
			IF ~Handle(invokeMsg) THEN invokeMsg.token := NIL END; (* if the invoke is not scheduled... *)
			RETURN invokeMsg.token
		END InvokeEventAsync; *)
		
		(* put event into message queue *)
		PROCEDURE ScheduleEvent*(event : CompCommand; sender, par : PTR);
		VAR invokeMsg : Message;
		BEGIN
			invokeMsg.msgType := MsgInvokeEvent;
			invokeMsg.sender := sender; invokeMsg.ext := par;
			invokeMsg.event := event;
			IF ~Handle(invokeMsg) THEN END
		END ScheduleEvent;
		
		(** Call a generator procedure with parameter par, returning an object. Waits until the result is ready *)
		PROCEDURE InvokeGenerator*(generator : AosModules.CommandParProc; par : PTR) : PTR; (** FINAL *)
		VAR invokeMsg : Message; result : PTR;
		BEGIN
			invokeMsg.msgType := MsgInvokeGenerator;
			invokeMsg.ext := par;
			invokeMsg.generator := generator;
			invokeMsg.token := GetAsyncToken();
			ASSERT(Handle(invokeMsg)); (* if the invoke is not scheduled, AwaitCompletion can take VERY long *)
			invokeMsg.token.AwaitCompletion;
			result := invokeMsg.token.result;
			RecycleAsyncToken(invokeMsg.token);
			RETURN result
		END InvokeGenerator;
		
		(** Call a generator method on behalf of the sequencer thread. Returns as soon as the call is scheduled in the sequencer.
			Returns a token that can be used to block until the result is ready in token.result.
			P.S. It would be nice if you could throw the token into the RecycleAsyncToken recycle bin to relieve the GC. 
			But make sure it is really no longer used.
		*)
		PROCEDURE InvokeGeneratorAsync*(generator : AosModules.CommandParProc; par : PTR) : AsyncToken; (** FINAL *)
		VAR invokeMsg : Message; result : PTR;
		BEGIN
			invokeMsg.msgType := MsgInvokeGenerator;
			invokeMsg.ext := par;
			invokeMsg.generator := generator;
			invokeMsg.token := GetAsyncToken();
			ASSERT(Handle(invokeMsg)); (* if the invoke is not scheduled, AwaitCompletion can take VERY long *)
			RETURN invokeMsg.token
		END InvokeGeneratorAsync;
		
		(** Stop the message sequencer. Must be called if the queue is no longer needed *)
		PROCEDURE Stop*;
		BEGIN {EXCLUSIVE}
			alive := FALSE
		END Stop;
		
		(* Remove a message from the queue. Block if no message is available but awake if queue is terminated by call to Stop *)
		(* return if alive *)
		PROCEDURE Get(VAR msg : Message) : BOOLEAN;
		BEGIN {EXCLUSIVE}
			IF hadOverflow THEN AosOut.String(" - Recovered"); hadOverflow := FALSE END;
			AWAIT((msgQHead # msgQTail) OR ~alive);
			IF ~alive THEN RETURN FALSE END;
			msg := msgQ[msgQHead]; msgQHead := (msgQHead+1) MOD MsgQSize;
			originator := msg.originator;
			RETURN TRUE
		END Get;
		
	BEGIN {ACTIVE, SAFE}
		(* trap occured *)
		IF alive THEN 
			th := traphandler; AosOut.String("[TRAP]");
			IF th # NIL THEN continue := th() ELSE continue := FALSE END;
			IF continue THEN lock.Reset ELSE RETURN END;
		END;

		alive := TRUE; me := AosActive.ActiveObject();
		(* Message processing loop *)
		WHILE Get(msg) DO 
			lock.AcquireWrite;
			IF ~Handle(msg) THEN AosOut.String("A msg was not handled... "); AosOut.Ln END;
			lock.ReleaseWrite
		END
	END MsgSequencer; 

VAR
	 tokenCache* : AosKernel.FinalizedCollection;
	 ttoken : AsyncToken;

PROCEDURE TokenEnumerator(obj: PTR; VAR cont: BOOLEAN);
BEGIN
	cont := FALSE; ttoken := obj(AsyncToken)
END TokenEnumerator;

(** Get an AsyncToken from the pool. Create a new one if the pool is empty *)
PROCEDURE GetAsyncToken*() : AsyncToken;
BEGIN {EXCLUSIVE}
	ttoken := NIL;
	tokenCache.Enumerate(TokenEnumerator);
	IF ttoken = NIL THEN NEW(ttoken) 
	ELSE tokenCache.Remove(ttoken)
	END;
	ttoken.Reset;
	RETURN ttoken
END GetAsyncToken;

(** Recycle an AsyncToken. Must be unused. (is only used to disburden the garbage collector) *)
PROCEDURE RecycleAsyncToken*(t : AsyncToken);
BEGIN
	(* only recycle the token if the result is complete *)
	IF t.IsCompleted() THEN tokenCache.Add(t, NIL) END;
END RecycleAsyncToken;

BEGIN
	NEW(tokenCache)
END WMMessages.
 