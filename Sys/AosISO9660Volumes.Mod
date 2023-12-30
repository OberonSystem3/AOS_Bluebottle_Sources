(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosISO9660Volumes;	(* AUTHOR "?/be"; PURPOSE "ISO 9660 volume (ported from Native Oberon)" *)

(** non-portable *)

	IMPORT
		AosOut, AosPlugins, AosDisks, AosFS;
	
	CONST
		debug = FALSE; getBlockDebug = FALSE;
		
	CONST	(* svr *)
		SS = 2048;	(* sector size *)
		MaxRetries = 10;
		
	TYPE
		Volume* = OBJECT (AosFS.Volume)
		VAR
			dev-: AosDisks.Device;
			bpc: LONGINT;	(* bytes per sector *)
			spc: LONGINT;	(* sectors per cluster *)
			
			PROCEDURE Finalize*;
			VAR res: LONGINT; ptable : AosDisks.PartitionTable;
			BEGIN {EXCLUSIVE}
				IF debug THEN LogString("Entering OFSISO9660Volumes.Finalize"); LogLn END;
				EXCL(dev.flags, AosDisks.Mounted);
				dev.Close(res)
			END Finalize;
		
			PROCEDURE Available*(): LONGINT;
			BEGIN
				RETURN 0
			END Available;
				
			PROCEDURE GetBlock(adr: LONGINT; VAR blk: ARRAY OF CHAR);
			VAR res, i: LONGINT;
			BEGIN {EXCLUSIVE}
				ASSERT(dev # NIL, 101);
				i := 0;
				REPEAT
					dev.Transfer(AosDisks.Read, adr, 1, blk, 0, res);
					INC(i)
				UNTIL (res = 0) OR (i >= MaxRetries);
				IF getBlockDebug & (i > 1) THEN LogString("GetBlock; "); LogInt(i); LogString(" retries"); LogLn END;
				ASSERT(res = 0, 102)
			END GetBlock;
			
			PROCEDURE AllocBlock(hint: AosFS.Address; VAR adr: AosFS.Address);
			BEGIN HALT(301)
			END AllocBlock;
			
			PROCEDURE FreeBlock(adr: AosFS.Address);
			BEGIN HALT(301)
			END FreeBlock;
			
			PROCEDURE MarkBlock(adr: AosFS.Address);
			BEGIN HALT(301)
			END MarkBlock;
			
			PROCEDURE Marked(adr: AosFS.Address): BOOLEAN;
			BEGIN HALT(301)
			END Marked;
		END Volume;
		
	(* debug procedures *)
	
	PROCEDURE LogString(s: ARRAY OF CHAR);
	BEGIN
		AosOut.String(s)
	END LogString;

	PROCEDURE LogInt(i: LONGINT);
	BEGIN
		AosOut.Int(i, 0)
	END LogInt;

	PROCEDURE LogLn;
	BEGIN
		AosOut.Ln
	END LogLn;
	
PROCEDURE GetISO9660Volume(p: AosFS.Parameters; dev: AosDisks.Device);
VAR vol: Volume; b: ARRAY SS OF CHAR;
BEGIN
	NEW(vol); vol.flags := {}; vol.dev := dev;
	INCL(vol.flags, AosFS.ReadOnly); INCL(vol.flags, AosFS.Removable);
	vol.bpc := SS; vol.spc := 1;
	vol.GetBlock(16, b); (* dummy; necessary after disc change *)
	COPY(vol.dev.name, vol.name);
	vol.blockSize := vol.bpc;
	IF debug THEN
		LogString("GetISO9660Volume"); LogLn;
		LogString("  spc="); LogInt(vol.spc); LogString("  bpc="); LogInt(vol.bpc); LogLn
	END;
	p.vol := vol
END GetISO9660Volume;
	
(** Generate a new ISO9660 volume object. AosFS.Par: device [# part (ignored)] *)
PROCEDURE New*(par: PTR): PTR;
VAR
	name: AosPlugins.Name;  i, j, res: LONGINT; p: AosFS.Parameters;
	table: AosPlugins.Table; dev: AosDisks.Device;
BEGIN
	p := par(AosFS.Parameters); p.vol := NIL;

	j := 0; WHILE p.str[j] = " " DO INC(j) END;
	i := 0;
	WHILE (p.str[j] > " ") & (p.str[j] # "#") & (p.str[j] # ",") DO name[i] := p.str[j]; INC(i); INC(j) END;
	name[i] := 0X;
	
	IF (name # "") THEN
		AosDisks.registry.GetAll(table);
		IF (table # NIL) THEN
			LogString("AosISO9660Volumes: Device ");  LogString(name);
			
			i := 0; WHILE (i # LEN(table)) & (table[i].name # name) DO INC(i) END;
			IF (i < LEN(table)) THEN
				dev := table[i](AosDisks.Device);
				dev.Open(res);
				IF (res = AosDisks.Ok) THEN
					IF ~(AosDisks.Mounted IN dev.table[0].flags) THEN
						GetISO9660Volume(p, dev);
					ELSE LogString(" already mounted")
					END;
						
					IF (p.vol = NIL) THEN 
						dev.Close(res) (* close again - ignore res *)
					END	
				ELSE LogString(" cannot open device")
				END
			ELSE LogString(" not found")
			END;
			LogLn
		END
	END;
	p.str[0] := 0X;
	RETURN NIL
END New;
	
END AosISO9660Volumes.

OFSTools.Mount TEST "IDE1.0" OFSISO9660Volumes.New OFSN2KFiles.NewFS
OFSTools.Mount A "Diskette0" OFSISO9660Volumes.New OFSN2KFiles.NewFS
OFSTools.Unmount ^ TEST A


System.Free OFSISO9660Volumes ~