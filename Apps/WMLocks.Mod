MODULE WMLocks;	(** AUTHOR "TF"; PURPOSE "Highlevel locks (recursive, reader writer)"; *)

IMPORT
		AosOut, AosActive, SYSTEM, AosIO, AosTrap, AosKernel;

TYPE
	(** Implements a recursive lock *)
	RecursiveLock* = OBJECT
	VAR
		lockLevel : LONGINT;
		lockedBy : PTR;
		
		PROCEDURE &New;
		BEGIN
			lockLevel := 0; lockedBy := NIL
		END New;
		
		PROCEDURE WriteLock(me : PTR);
		VAR w : AosIO.Writer;
		BEGIN
			AosOut.String("Lock held by : "); 
			IF lockedBy = NIL THEN AosOut.String("nobody")
			ELSE
				AosIO.OpenWriter(w, AosOut.Send);
				AosTrap.WriteType(w, SYSTEM.GET32(SYSTEM.VAL(LONGINT, lockedBy)- 4)); 
				w.String(" New Acquire by : ");
				AosTrap.WriteType(w, SYSTEM.GET32(SYSTEM.VAL(LONGINT, me)-4)); 
				w.Update
			END;	
			AosOut.Ln;
		END WriteLock;
		
		(** acquire a lock on the object *)
		PROCEDURE Acquire*;
		VAR me : PTR;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			IF lockedBy = me THEN
				ASSERT(lockLevel # -1);	(* overflow *)
				INC(lockLevel);
			ELSE
				AWAIT(lockedBy = NIL);
				lockedBy := me; lockLevel := 1
			END;
		END Acquire;
		
		(** Make sure, the calling process has this lock *)
		PROCEDURE Check*;
		BEGIN
			IF lockedBy = NIL THEN AosOut.String("NO lock !!"); AosOut.Ln END;
			ASSERT(lockedBy = AosActive.ActiveObject(), 3000);	(* must hold lock *)
		END Check;
		
		(** release the read/write lock on the object *)
		(** MUST hold lock *)
		PROCEDURE Release*;
		BEGIN 
			BEGIN {EXCLUSIVE}
				Check;
				DEC(lockLevel);
				IF lockLevel = 0 THEN lockedBy := NIL END
			END
		END Release;
	END RecursiveLock;
	
(** Reader/Writer Lock *)
	LockReleasedHandler* = PROCEDURE {DELEGATE} ;
	
	ReaderLockInfo = RECORD
		owner : PTR;
		lockLevel : LONGINT
	END;
	
	ReaderLockList = POINTER TO ARRAY OF ReaderLockInfo;
	(** Implements a Reader/Writer lock that can be taken by many readers at the same time, as long as no
	writer lock was taken. Only one writer lock is possible at one time. (MREW = Multi Read, Exclusive Write) 
	Writers can starve. Possible remedies : 
		simple : Don't let new readers in if a writer made an acquire.  
		more complicated: Q all acquires and handle in order (optimizing readers)
		Readers trying to get a Writer lock result in a trap. Currently no upgrade.
	*)
	RWLock* = OBJECT
	VAR
		lockLevel : LONGINT;
		lockedBy : ANY; (* writer *)
		lastReader : ANY;
		nofReaders : LONGINT;
		readers : ReaderLockList;
		wlReleaseHandler : LockReleasedHandler;
		nofReadLocks, nofWriteLocks : LONGINT;
		HUGA*, DEADLOCK:BOOLEAN;
		
		PROCEDURE &New;
		BEGIN
			lockLevel := 0; lockedBy := NIL; lastReader := NIL;
			NEW(readers, 4);
			RegisterLock(SELF);
		END New;
		
		PROCEDURE WriteLock*;
		VAR w : AosIO.Writer;
		BEGIN
			AosOut.String("Lock held by : "); 
			IF lockedBy = NIL THEN AosOut.String("nobody")
			ELSE
				AosIO.OpenWriter(w, AosOut.Send);
				AosTrap.WriteType(w, SYSTEM.GET32(SYSTEM.VAL(LONGINT, lockedBy)- 4)); 
				w.String(" New Acquire by : ");
				AosTrap.WriteType(w, SYSTEM.GET32(SYSTEM.VAL(LONGINT, AosActive.ActiveObject())-4)); 
				w.Update
			END;	
			AosOut.Ln;
		END WriteLock;
		
		PROCEDURE WriteStats*;
		BEGIN {EXCLUSIVE}
			AosOut.String("nofReadLocks : "); AosOut.Int(nofReadLocks, 4); AosOut.Ln;
			AosOut.String("nofWriteLocks : "); AosOut.Int(nofWriteLocks, 4); AosOut.Ln;
			AosOut.String("current readers : "); AosOut.Int(nofReaders, 4); AosOut.Ln;
			AosOut.String("current writer : "); IF lockedBy # NIL THEN AosOut.String(" not NIL") ELSE AosOut.String("is NIL") END;
		END WriteStats;
		
		PROCEDURE SetDeadLock*;
		BEGIN	{EXCLUSIVE}
			DEADLOCK := TRUE
		END SetDeadLock;
		
		(** acquire a write-lock on the object *)
		PROCEDURE AcquireWrite*;
		VAR me : ANY;
		BEGIN {EXCLUSIVE}
			INC(nofWriteLocks);
			me := AosActive.ActiveObject();
			IF lockedBy = me THEN (* recursive use *)
				INC(lockLevel);
				ASSERT(lockLevel # -1)	(* overflow *)
			ELSE
				(* wait until no other writer and no reader has the lock *)
				ASSERT(~(lockedBy = me) & ~InternalHasReadLock(), 3001);
				AWAIT(DEADLOCK OR (lockedBy = NIL) & (nofReaders = 0));
				IF DEADLOCK THEN HALT(123000) END;
				lockedBy := me; lockLevel := 1
			END
		END AcquireWrite;
		
		(** Returns the locklevel of the write lock. [Must hold write lock] *)
		PROCEDURE GetWLockLevel*() : LONGINT;
		BEGIN
			ASSERT(HasWriteLock(), 3000);
			RETURN lockLevel
		END GetWLockLevel;
		
		PROCEDURE SetLockReleasedHandler*(handler : LockReleasedHandler);
		BEGIN
			wlReleaseHandler := handler
		END SetLockReleasedHandler;
		
		(** release the write-lock on the object. MUST hold lock *)
		PROCEDURE ReleaseWrite*;
		VAR inform : BOOLEAN;
		BEGIN 
			inform := FALSE;
			BEGIN {EXCLUSIVE}
				ASSERT(HasWriteLock(), 3000);
				DEC(lockLevel);
				IF lockLevel = 0 THEN lockedBy := NIL; inform := TRUE END
			END;
			(* inform interested parties *)
			IF inform THEN IF wlReleaseHandler # NIL THEN wlReleaseHandler END END	
		END ReleaseWrite;
		
(*		(** release the write-lock and transform into a read-lock if the lock-level becomes 0 
			returns TRUE if the write-lock is transformed into a readlock *)
		PROCEDURE ReleaseWriteAcquireRead*():BOOLEAN;
		BEGIN {EXCLUSIVE}
			ASSERT(HasWriteLock(), 3000);
			DEC(lockLevel);
			IF lockLevel = 0 THEN lockedBy := NIL;
				InternalAcquireRead;
				RETURN TRUE
			ELSE
				RETURN FALSE	
			END
		END ReleaseWriteAcquireRead; *)
		
		(** Make sure, the calling process has this write-lock *)
		PROCEDURE HasWriteLock*(): BOOLEAN;
		BEGIN
			RETURN lockedBy = AosActive.ActiveObject()
		END HasWriteLock;
		
		(** acquire a read-lock on the object *)
		PROCEDURE AcquireRead*;
		BEGIN {EXCLUSIVE}
			InternalAcquireRead;
		END AcquireRead;
		
		PROCEDURE InternalAcquireRead;
		VAR me : PTR; i : LONGINT; found : BOOLEAN; t : ReaderLockList;
		BEGIN 
			INC(nofReadLocks);
			me := AosActive.ActiveObject();
			AWAIT(DEADLOCK OR (lockedBy = NIL) OR (lockedBy = me));  (* write owner may acquire a read *)
			lastReader := me;
			IF DEADLOCK THEN HALT(123001) END;
			found := FALSE;
			i := 0; WHILE (i < nofReaders) & ~found DO 
				IF readers[i].owner = me THEN found := TRUE; INC(readers[i].lockLevel); ASSERT(readers[i].lockLevel # -1) END;
				INC(i)
			END;
			IF ~found THEN
				IF nofReaders = LEN(readers) THEN
					NEW(t, nofReaders * 2); FOR i := 0 TO nofReaders - 1 DO t[i] := readers[i] END; readers := t;
				END;
				readers[nofReaders].owner := me; readers[nofReaders].lockLevel := 1;
				INC(nofReaders);
			END
		END InternalAcquireRead;
		
		(** release the read lock on the object. MUST hold lock *)
		PROCEDURE ReleaseRead*;
		VAR me : PTR; i : LONGINT; found : BOOLEAN;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			found := FALSE;
			i := 0; WHILE (i < nofReaders) & ~found DO 
				IF readers[i].owner = me THEN found := TRUE; DEC(readers[i].lockLevel); 
					IF readers[i].lockLevel = 0 THEN
						DEC(nofReaders);
						WHILE i < nofReaders DO readers[i] := readers[i + 1]; INC(i) END;
						readers[nofReaders].owner := NIL; (* for GC *)
						lastReader := readers[0].owner
					END;
				END;	
				INC(i)
			END;
			ASSERT(found)
		END ReleaseRead;
		
		(** Make sure, the calling process has a read lock. A write lock implicitly holds the read lock *)
		PROCEDURE HasReadLock*() : BOOLEAN;
		VAR me : ANY;
		BEGIN
			me := AosActive.ActiveObject();
			IF (lockedBy = me) OR (lastReader = me) THEN RETURN TRUE END; (* WriteLock has implicit ReadLock *) 
			BEGIN {EXCLUSIVE}
				RETURN InternalHasReadLock()
			END
		END HasReadLock;
		
		PROCEDURE InternalHasReadLock(): BOOLEAN;
		VAR me : ANY; i : LONGINT;  
		BEGIN 
			me := AosActive.ActiveObject();
			i := 0; WHILE (i < nofReaders) DO 
				IF readers[i].owner = me THEN RETURN TRUE END;	
				INC(i)
			END;
			RETURN FALSE
		END InternalHasReadLock;
		
		(** Remove all locks owned by the caller *)
		PROCEDURE Reset*;
		VAR i, j : LONGINT;
			me : PTR;
		BEGIN {EXCLUSIVE}
			me := AosActive.ActiveObject();
			AosOut.String("!!! LOCK RESET !!!");
			IF lockedBy = me THEN 
				FOR i := 0 TO nofReaders - 1 DO readers[i].owner := NIL END; nofReaders := 0;
				lockLevel := 0; lockedBy := NIL;
				AosOut.String(" --> Removed all locks ");
			ELSIF lockedBy = NIL THEN (* only remove locks owned by the caller *)
				FOR i := 0 TO nofReaders - 1 DO 
					IF readers[i].owner = me THEN 
						FOR j := i TO nofReaders - 2 DO readers[j] := readers[j+1] END; 
						DEC(nofReaders); readers[nofReaders].owner:= NIL;
			    		AosOut.String(" --> Removed a readlock");
					 END;
				END	
			END	
		END Reset;
	END RWLock;
	
VAR
	locks : AosKernel.FinalizedCollection;

PROCEDURE RegisterLock(x : PTR);
BEGIN
	locks.Add(x, NIL);
END RegisterLock;

PROCEDURE DL(obj: PTR; VAR cont: BOOLEAN);
BEGIN
	obj(RWLock).SetDeadLock; cont := TRUE;
END DL;

PROCEDURE DeadLock*;
BEGIN
	locks.Enumerate(DL);
END DeadLock;

BEGIN
	NEW(locks);
END WMLocks.
 

