MODULE AosActiveTimers;

IMPORT
	AosActive;

TYPE
	Timer* = OBJECT
		VAR
			timer: AosActive.Timer;
			handler: AosActive.EventHandler;
			timeout, running: BOOLEAN;
		
		PROCEDURE &Init;
		BEGIN
			NEW(timer);
			timeout := FALSE;
			running := TRUE;
		END Init;
		
		PROCEDURE SetTimeout*(h: AosActive.EventHandler; ms: LONGINT);
		BEGIN
			handler := h;
			AosActive.SetTimeout(timer, HandleTimeout, ms)
		END SetTimeout;
		
		PROCEDURE HandleTimeout;
		BEGIN {EXCLUSIVE}
			timeout := TRUE
		END HandleTimeout;
	
		PROCEDURE Finalize;
		BEGIN {EXCLUSIVE}
			AosActive.CancelTimeout(timer);
			running := FALSE
		END Finalize;
	
	BEGIN {ACTIVE}
		WHILE running DO
			LOOP
				BEGIN {EXCLUSIVE}
					AWAIT(timeout OR ~running);
					IF ~running THEN
						EXIT
					END;
					timeout := FALSE
				END;
				handler()
			END
		END
	END Timer;

END AosActiveTimers.