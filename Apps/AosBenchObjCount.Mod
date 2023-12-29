(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosBenchObjCount;	(* pjm *)

(* Test how many active objects can be created. *)

IMPORT AosOut, AosMemory, AosKernel, AosProcessors;

TYPE
	Tester = OBJECT
		VAR next: Tester; stop: BOOLEAN;
		
		PROCEDURE Stop;
		BEGIN {EXCLUSIVE}
			stop := TRUE
		END Stop;
		
		PROCEDURE &Init;
		BEGIN
			stop := FALSE
		END Init;
		
	BEGIN {ACTIVE, EXCLUSIVE}
		AWAIT(stop)
	END Tester;

PROCEDURE Report(msg: ARRAY OF CHAR; n, time: LONGINT);
BEGIN
	AosOut.Enter;
	AosOut.Int(n, 1); AosOut.String(" threads "); AosOut.String(msg); AosOut.String(", ");
	AosOut.Int(time, 1); AosOut.String("ms");
	IF n # 0 THEN
		AosOut.String(", "); AosOut.Int(ENTIER(time/n*1000), 1); AosOut.String("us/thread")
	END;
	AosOut.Exit
END Report;

PROCEDURE Max*;
VAR n, total, low, high, time: LONGINT; root, t: Tester;
BEGIN
	n := AosKernel.GetTimer();
	REPEAT time := AosKernel.GetTimer() UNTIL time # n;
	
	n := 0; root := NIL;
	LOOP
		AosMemory.GetFreeK(total, low, high);
		IF low+high < 1024 THEN EXIT END;
		NEW(t); t.next := root; root := t;
		INC(n)
	END;
	time := ENTIER((AosKernel.GetTimer() - time)/AosKernel.second*1000);
	Report("created", n, time);
	
	time := AosKernel.GetTimer();
	WHILE root # NIL DO root.Stop(); t := root; root := root.next; t.next := NIL END;
	time := ENTIER((AosKernel.GetTimer() - time)/AosKernel.second*1000);
	Report("stopped", n, time);
	
	time := AosKernel.GetTimer();
	AosProcessors.GlobalGC;
	time := ENTIER((AosKernel.GetTimer() - time)/AosKernel.second*1000);
	Report("collected", n, time);	(* not accurate, because interrupts currently disabled during GC *)
	
	time := AosKernel.GetTimer();
	(*AosHeap.CallFinalizers;*)	(* safe, if we are in an Oberon command *)
	time := ENTIER((AosKernel.GetTimer() - time)/AosKernel.second*1000);
	Report("finalized", n, time)
END Max;

END AosBenchObjCount.

System.Free AosBenchObjCount ~

System.State AosMemory ~

System.OpenKernelLog

Configuration.DoCommands
AosBenchObjCount.Max
System.Time start
System.Collect
System.Time lap
System.Watch
~