MODULE WMMessages; (** AUTHOR "TF"; PURPOSE "Support for messages and events"; *)
(**
 * History:
 *
 *	17.07.2006	Added message statistics (staubesv)
 *)

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
	
	(** Gather statistics about added/discarded messages? *)
	Statistics* = TRUE;
	MsgTypeMax* = 11;
	
TYPE
	(** Generic Component Command *)
	CompCommand* = PROCEDURE  { DELEGATE } (sender, par : ANY);
	String* = Utilities.String;
	
	(** Generic message structure *)
	Message* = RECORD
		originator*, (** the originator if # NIL passes information about the view that directly or indirectely lead to the msg *)
		sender* : ANY; (** is the sender component. If the message is originated form a component *)
		token* : AsyncToken; 
		event* : CompCommand;
		generator* : AosModules.CommandParProc;
		msgType*, msgSubType* : LONGINT; (** generic message type *)
		x*, y*, z*, dx*, dy*, dz* : LONGINT; (** in keyboard messages : ucs value in x, keysym in y *)
		flags* : SET; (** in pointer messages : keys in flags *)
		ext* : ANY; (** extended message *)
	END;
	
	MessageExtension* = OBJECT END MessageExtension;

	(** AsyncToken can be used to synchronize asynchronous method invocation *)
	AsyncToken* = OBJECT
	VAR ready : BOOLEAN;
		result* : ANY;
		
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
	

	(** Message handler that can be called from the sequencer *)
	MessageHandler* = PROCEDURE {DELEGATE} (VAR msg : Message);
	
	(** The TrapHandler must return TRUE if the process should restart. Otherwise the process is stopped *)
	TrapHandler* = PROCEDURE {DELEGATE} () : BOOLEAN;
	
(** Message sequencer *)
	MsgSequencer* = OBJECT
		VAR
			head, num : LONGINT;
			msgQ : ARRAY MsgQSize OF Message;
			alive, continue, hadOverflow : BOOLEAN;
			msg : Message;
			result : ANY;
			handler : MessageHandler;
			originator : ANY;
			me : ANY; (* Thread for caller identification *)
			lock* : Locks.RWLock;
			th, traphandler : TrapHandler;
			name* : String;
			trapOnOverflow* : BOOLEAN;
		
		PROCEDURE &New(handler : MessageHandler);
		BEGIN
			NEW(lock);
			num := 0; head := 0;
			SELF.handler := handler; alive := FALSE; continue := TRUE; hadOverflow := FALSE
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
		PROCEDURE GetOriginator*() : ANY;
		BEGIN
			IF AosActive.ActiveObject() = me THEN RETURN originator
			ELSE RETURN NIL
			END
		END GetOriginator;
		
		(** Add a message to a queue. Discards the message if the queue is full *)
		PROCEDURE Add*(VAR msg : Message) : BOOLEAN;
		VAR i:LONGINT;
		BEGIN {EXCLUSIVE}
			IF (msg.msgType = MsgPointer) & (num > 0) THEN  (* reduce pointer moves in buffer *)
				i := num - 1;
				WHILE i >= 0 DO
					IF (msgQ[(head + i) MOD MsgQSize].msgType = MsgPointer) & (msg.msgSubType = MsgSubPointerMove) & (msgQ[(head + i) MOD MsgQSize].flags = msg.flags) THEN 
						msgQ[(head + i) MOD MsgQSize].x := msg.x;
						msgQ[(head + i) MOD MsgQSize].y := msg.y;
						msgQ[(head + i) MOD MsgQSize].z := msg.z;
						RETURN TRUE
					END;
					DEC(i)	
				END
			END;
			IF num < MsgQSize THEN
				IF Statistics THEN
					INC(messagesAdded);
					IF (msg.msgType >= 0) & (msg.msgType < MsgTypeMax) THEN
						INC(messagesAddedByType[msg.msgType]);
					END;
				END;
				msgQ[(head + num) MOD MsgQSize] := msg; INC(num);
				RETURN TRUE
			ELSE
				IF Statistics THEN INC(messagesDiscarded); END;
				IF ~hadOverflow THEN IF name # NIL THEN AosOut.String(name^); AosOut.String(" : ") END;
					IF trapOnOverflow THEN HALT(123456) END;
				(*AosOut.String("Message queue overflow "); AosOut.Ln; *) hadOverflow := TRUE END;
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
		
		(* put event into message queue *)
		PROCEDURE ScheduleEvent*(event : CompCommand; sender, par : ANY);
		VAR invokeMsg : Message;
		BEGIN
			invokeMsg.msgType := MsgInvokeEvent;
			invokeMsg.sender := sender; invokeMsg.ext := par;
			invokeMsg.event := event;
			IF ~Handle(invokeMsg) THEN END
		END ScheduleEvent;
		
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
			AWAIT((num # 0) OR ~alive);
			IF ~alive THEN RETURN FALSE END;
			msg := msgQ[head]; head := (head + 1)  MOD MsgQSize;
			DEC(num);
			originator := msg.originator;
			RETURN TRUE
		END Get;
		
	BEGIN {ACTIVE, SAFE}
		(* trap occured *)
		IF alive THEN 
			th := traphandler; AosOut.String("WMMessages: [TRAP]"); AosOut.Ln;
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
	 
	 (* Statistics *)
	 messagesAddedByType- : ARRAY MsgTypeMax OF LONGINT;
	 messagesAdded- : LONGINT;
	 messagesDiscarded- : LONGINT;
	 
PROCEDURE TokenEnumerator(obj: ANY; VAR cont: BOOLEAN);
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
