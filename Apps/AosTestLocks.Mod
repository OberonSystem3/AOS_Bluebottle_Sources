MODULE AosTestLocks;	(* pjm *)

(* Test module for AosLocks. *)

IMPORT SYSTEM, AosBoot, AosLocks, AosOut;

(* Display locking state. *)

PROCEDURE ShowState(msg: ARRAY OF CHAR);
VAR id: LONGINT; ints: BOOLEAN;
BEGIN
	ints := AosBoot.InterruptsEnabled();
	AosOut.String(msg); AosOut.String(": ");
	id := AosBoot.ID();
	AosOut.String("Processor "); AosOut.Int(id, 1);
	AosOut.String(", interrupts are ");
	IF ints THEN AosOut.String("on") ELSE AosOut.String("off") END;
	AosOut.Ln
END ShowState;

(** Acquire and release a single lock. *)

PROCEDURE Single*;
BEGIN
	AosLocks.Acquire(AosLocks.AosOutHigh);
	ShowState("Single");
	AosLocks.Release(AosLocks.AosOutHigh);
END Single;

(** Same as Single, but switch on interrupts. *)

PROCEDURE SingleInt*;
BEGIN
	AosLocks.Acquire(AosLocks.AosOutHigh);
	SYSTEM.STI;	(* nested lock in write will switch off interrupts again *)
	ShowState("SingleInt1");
	ShowState("SingleInt2");
	AosLocks.Release(AosLocks.AosOutHigh);
END SingleInt;

(** Hold a lock for a long time, to test interrupt interaction. *)

PROCEDURE Long*;
VAR i: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosOutHigh);
	FOR i := 0 TO 100000000 DO END;
	ShowState("Long");
	AosLocks.Release(AosLocks.AosOutHigh);
END Long;

(** Same as Long, but switch on interrupts. *)

PROCEDURE LongInt*;
VAR i: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosOutHigh);
	SYSTEM.STI;
	FOR i := 0 TO 100000000 DO END;
	SYSTEM.CLI;
	ShowState("LongInt");
	AosLocks.Release(AosLocks.AosOutHigh);
END LongInt;

(** Acquire and release all locks. *)

PROCEDURE All*;
BEGIN
	AosLocks.AcquireAll;
	(*ShowState("All");*)
	AosLocks.ReleaseAll
END All;

(** Attempt to acquire a lock recursively (allowed in old model). *)

PROCEDURE Recursive*;
BEGIN
	AosLocks.Acquire(AosLocks.AosOutHigh);
	AosLocks.Acquire(AosLocks.AosOutHigh);
	ShowState("Recursive");
	AosLocks.Release(AosLocks.AosOutHigh);
	AosLocks.Release(AosLocks.AosOutHigh);
END Recursive;

(** Acquire a lock out of order (not allowed). *)

PROCEDURE OutOfOrder*;
BEGIN
	AosLocks.Acquire(AosLocks.AosOutLow);
	AosLocks.Acquire(AosLocks.AosOutHigh);
	ShowState("OutOfOrder");
	AosLocks.Release(AosLocks.AosOutHigh);
	AosLocks.Release(AosLocks.AosOutLow)
END OutOfOrder;

(*
(** Acquire special lock. *)

PROCEDURE Special*;
BEGIN
	SYSTEM.CLI();
	ShowState("Special1");
	AosLocks.AcquireSpecial(AosLocks.AosOutHigh);
	ShowState("Special2");
	AosLocks.Release(AosLocks.AosOutHigh);
	ShowState("Special3");
	SYSTEM.STI
END Special;
*)

END AosTestLocks.

System.OpenKernelLog

AosTestLocks.Single
AosTestLocks.SingleInt	(should trap if StrongChecks are on)
AosTestLocks.Long	(runs for a few seconds)
AosTestLocks.LongInt
AosTestLocks.All
AosTestLocks.Recursive	(should trap or hang)
AosTestLocks.OutOfOrder	(should trap or hang)
AosTestLocks.Special
