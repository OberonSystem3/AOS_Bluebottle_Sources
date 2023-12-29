(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosFido; (** AUTHOR "pjm"; PURPOSE "Watchdog debugging"; *)

IMPORT SYSTEM, AosOut, AosHeap, AosModules, AosTrap, AosActive, AosKernel, AosIO;

TYPE
	Bytes = AosModules.Bytes;
	
TYPE
	Watchdog* = OBJECT
		VAR
			timer: AosKernel.Timer; delay: LONGINT; time: AosKernel.MilliTimer; alive, done: BOOLEAN;
			name: ARRAY 32 OF CHAR;
		
		PROCEDURE Cleanup;
		BEGIN {EXCLUSIVE}
			timer.Wakeup;
			alive := FALSE;
			AWAIT(done)
		END Cleanup;
		
		PROCEDURE Done;
		BEGIN {EXCLUSIVE}
			done := TRUE
		END Done;
		
		PROCEDURE Reset*;
		BEGIN {}
			AosKernel.SetTimer(time, delay)
		END Reset;
		
		PROCEDURE &Init(name: ARRAY OF CHAR; delay: LONGINT);
		BEGIN
			COPY(name, SELF.name); SELF.delay := delay;
			alive := TRUE; done := FALSE;
			NEW(timer)
		END Init;
		
	BEGIN {ACTIVE}
		LOOP
			timer.Sleep(delay);
			IF ~alive THEN EXIT END;
			IF AosKernel.Expired(time) THEN
				AosOut.String("Watchdog "); AosOut.String(name); AosOut.Ln;
				Action
			END
		END;
		Done
	END Watchdog;

VAR
	watchdog: Watchdog;

PROCEDURE Action*;
TYPE
	ProcessList = POINTER TO RECORD
		next: ProcessList;
		thread: AosActive.Process
	END;
VAR
	sorted, p, n, c: ProcessList; t: AosActive.Process; mode, adr: LONGINT;
	writer: AosIO.Writer;
BEGIN
	AosIO.OpenWriter(writer, AosOut.Send);
	AosActive.snapshotEnabled := TRUE;
	AosHeap.GC;
	WHILE AosActive.snapshot # NIL DO
			(* remove a node from snapshot list *)
		t := AosActive.snapshot; AosActive.snapshot := t.link; t.link := NIL;
			(* insert in sorted list *)
		NEW(n); n.thread := t; p := NIL; c := sorted;
		WHILE (c # NIL) & (c.thread.id < t.id) DO p := c; c := c.next END;
		IF p = NIL THEN sorted := n ELSE p.next := n END;
		n.next := c
	END;
		(* display the threads *)
	WHILE sorted # NIL DO
		t := sorted.thread; sorted := sorted.next;
		AosOut.Int(t.id, 4); AosOut.Char(" ");
		mode := t.mode;
		CASE mode OF
			AosActive.Ready: AosOut.String("rdy")
			|AosActive.Running: AosOut.String("run")
			|AosActive.AwaitingLock: AosOut.String("awl")
			|AosActive.AwaitingCond: AosOut.String("awc")
			|AosActive.AwaitingEvent: AosOut.String("awe")
			|AosActive.Terminated: AosOut.String("rip")
			ELSE AosOut.Int(mode, 3)
		END;
		AosOut.Int(t.procID, 2); AosOut.Int(t.priority, 2);
		(*AosOut.Hex(SYSTEM.VAL(LONGINT, t)); AosOut.Char("H");*)
		adr := SYSTEM.VAL(LONGINT, t.obj);
		IF adr # 0 THEN
			AosOut.Hex(adr, 9); AosOut.Char("H");
			SYSTEM.GET(adr-4, adr); AosOut.Char(":"); AosHeap.WriteType(adr)
		ELSE
			AosOut.String(" SYSTEM")
		END;
		(*AosOut.Hex(t.state.EIP); AosOut.Char("H");*)
		IF mode = AosActive.AwaitingLock THEN
			adr := SYSTEM.VAL(LONGINT, t.waitingOn);
			AosOut.Hex(adr, 9); AosOut.Char("H");
			IF adr # 0 THEN
				SYSTEM.GET(adr-4, adr); AosOut.Char(":"); AosHeap.WriteType(adr)
			END
		ELSIF mode = AosActive.AwaitingCond THEN
			AosOut.Char(" ");
			AosTrap.WriteProc(writer, SYSTEM.VAL(LONGINT, t.condition)); writer.Update;
			(*AosOut.Hex(SYSTEM.VAL(LONGINT, t.condition)); AosOut.Char("H");*)
			(*AosOut.Hex(t.condFP); AosOut.Char("H")*)
		ELSIF mode IN {AosActive.Running, AosActive.Ready, AosActive.AwaitingEvent} THEN
			AosOut.Char(" ");
			AosTrap.WriteProc(writer, t.state.EIP); writer.Update
		END;
		IF AosActive.Restart IN t.flags THEN AosOut.String(" rst") END;
		IF AosActive.Resistant IN t.flags THEN AosOut.String(" res") END;
		IF AosActive.PleaseStop IN t.flags THEN AosOut.String(" stp") END;
		IF AosActive.PleaseHalt IN t.flags THEN AosOut.String(" hlt") END;
		IF mode = AosActive.AwaitingLock THEN
			AosOut.Char(" ");
			AosTrap.WriteProc(writer, t.state.EIP); writer.Update
		END;
		AosOut.Ln
	END
END Action;

PROCEDURE Allocate;
BEGIN {EXCLUSIVE}
	IF watchdog = NIL THEN NEW(watchdog, "Default", 5000) END
END Allocate;

PROCEDURE Reset*;
BEGIN
	IF watchdog = NIL THEN Allocate END;
	watchdog.Reset
END Reset;

PROCEDURE Cleanup;
BEGIN
	IF watchdog # NIL THEN watchdog.Cleanup END
END Cleanup;

BEGIN
	watchdog := NIL;
	AosModules.InstallTermHandler(Cleanup)
END AosFido.

AosFido.Reset

System.Free AosFido ~
