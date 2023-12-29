(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosRAMVolumes; (** AUTHOR "pjm"; PURPOSE "RAM-based volume"; *)

(* AosFS.Volume implementation in ram. *)

IMPORT SYSTEM, AosBoot, AosFS;

CONST
	DirMark = 9B1EA38DH;	(* for NatFS and AosFS *)
	
TYPE
	Volume* = OBJECT (AosFS.Volume)
		VAR
			data: POINTER TO ARRAY OF POINTER TO ARRAY OF CHAR;
		
		(** Get block from adr [1..size] of volume vol *)
		PROCEDURE GetBlock*(adr: LONGINT; VAR blk: ARRAY OF CHAR);
		VAR i: LONGINT;
		BEGIN
			IF (adr < 1) OR (adr > size) THEN SYSTEM.HALT(15) END;
			ASSERT(LEN(blk) >= blockSize);	(* index check *)
			IF data[adr-1] # NIL THEN
				SYSTEM.MOVE(SYSTEM.ADR(data[adr-1]^[0]), SYSTEM.ADR(blk[0]), blockSize)
			ELSE
				FOR i := 0 TO blockSize-1 DO blk[i] := 0X END
			END
		END GetBlock;
		
		(** Put block to adr [1..size] of volume vol *)
		PROCEDURE PutBlock*(adr: LONGINT; VAR blk: ARRAY OF CHAR);
		BEGIN
			IF (adr < 1) OR (adr > size) THEN SYSTEM.HALT(15) END;
			ASSERT(LEN(blk) >= blockSize);	(* index check *)
			IF data[adr-1] = NIL THEN NEW(data[adr-1], blockSize) END;
			SYSTEM.MOVE(SYSTEM.ADR(blk[0]), SYSTEM.ADR(data[adr-1]^[0]), blockSize)
		END PutBlock;

		PROCEDURE Finalize*;
		BEGIN
			data := NIL;
			Finalize^	(* see note in AosFS *)
		END Finalize;

	END Volume;

VAR
	count: LONGINT;

PROCEDURE GetCount(): LONGINT;
BEGIN {EXCLUSIVE}
	INC(count); RETURN count
END GetCount;

(** Generate a new ram volume object. AosFS.Par: size blocksize .  If size < 0, use as percentage of free memory. *)
PROCEDURE New*(par: PTR): PTR;
VAR vol: Volume; size, vbs, i: LONGINT; p: AosFS.Parameters;
BEGIN
	p := par(AosFS.Parameters);
	p.vol := NIL; i := 0;
	WHILE p.str[i] = " " DO INC(i) END;
	size := AosBoot.StrToInt(i, p.str^);
	WHILE p.str[i] = " " DO INC(i) END;
	vbs := AosBoot.StrToInt(i, p.str^);
	IF (size # 0) & (vbs > 0) THEN
(*
		IF size < 0 THEN	(* use as percentage of free memory *)
			size := Kernel.LargestAvailable() DIV vbs * (-size) DIV 100
		END;
*)
		NEW(vol); NEW(vol.data, size);
		NEW(vol.data[0], vbs);	(* hack: pre-format with empty AosFS *)
		SYSTEM.PUT32(SYSTEM.ADR(vol.data[0]^[0]), DirMark);
		vol.name := "RAM"; AosFS.AppendInt(GetCount(), vol.name);
		vol.blockSize := vbs;
		vol.Init({}, size, 0);
		p.vol := vol; p.str[0] := 0X
	ELSE
		COPY("AosRAMVolumes: bad parameters", p.str^)
	END;
	RETURN NIL
END New;

(*
(* Clean up when module freed. *)
PROCEDURE Cleanup;
VAR fs: AosFS.FileSystem;
BEGIN
	IF AosModules.shutdown = AosModules.None THEN
		REPEAT	(* unmount all file systems using our volume *)
			fs := AosFS.First();	(* look for fs to unmount *)
			WHILE (fs # NIL) & ((fs.vol = NIL) OR ~(fs.vol IS Volume)) DO
				fs := AosFS.Next(fs)
			END;
			IF fs # NIL THEN AosFS.Remove(fs) END
		UNTIL fs = NIL
	END
END Cleanup;
*)

BEGIN
	count := -1
END AosRAMVolumes.
