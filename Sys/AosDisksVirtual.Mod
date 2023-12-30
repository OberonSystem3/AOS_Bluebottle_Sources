MODULE AosDisksVirtual; (** AUTHOR: "staubesv"; PURPOSE: "Virtual disk driver"; *)
(**
 * The virtual disk driver installs disk images as virtual disk drives.
 *
 * Usage:
 *
 *	AosDisksVirtual.Create filename nbrOfBlocks [blocksize] ~ creates an empty virtual disk 
 *
 *	AosDisksVirtual.Install diskname filename [blocksize] ~
 *	AosDisksVirtual.Uninstall diskname ~
 *
 *	S.Free AosDisksVirtual ~
 *
 * History:
 *
 *	11.08.2006 	Created (staubesv)
 *	04.01.2007	Added procedure Create, error handling improved, user specifies disk names (staubesv)
 *	26.03.2007	Added NnofReads, NnofWrites, NnofOthers and NnofErrors (staubesv)
 *)
 
IMPORT
	AosOut, AosBoot, AosCommands, AosPlugins, AosModules, AosIO, AosDisks, AosFS, Utilities;
	
CONST
	BlockNumberInvalid* = 101;
	ShortTransfer* = 102;
		
	DefaultBlocksize = 512;
	
	ModuleName = "AosDisksVirtual";

TYPE

	VirtualDisk = OBJECT(AosDisks.Device)
	VAR
		file : AosFS.File;
		size : LONGINT;
		rider : AosFS.Rider;
		next : VirtualDisk;
	
		PROCEDURE Transfer*(op, block, num: LONGINT; VAR data: ARRAY OF CHAR; ofs: LONGINT; VAR res: LONGINT);
		BEGIN {EXCLUSIVE}
			IF (block < 0) OR (num < 1) OR (block + num > size) THEN res := BlockNumberInvalid; RETURN; END;

			file.Set(rider, block * blockSize);
			IF rider.res # AosFS.Ok THEN res := BlockNumberInvalid; RETURN; END;
			
			IF op = AosDisks.Read THEN
				file.ReadBytes(rider, data, ofs, num * blockSize);
				IF rider.res # 0 THEN res := ShortTransfer; ELSE res := AosDisks.Ok; END;
			ELSIF op = AosDisks.Write THEN
				file.WriteBytes(rider, data, ofs, num * blockSize);	
				IF rider.res # 0 THEN res := ShortTransfer; ELSE res := AosDisks.Ok; END;
			ELSE
				res := AosDisks.Unsupported;
			END;
			
			IF AosDisks.Stats THEN
				IF op = AosDisks.Read THEN
					NnofReads := AosBoot.AddH(NnofReads, 1);
					IF (res = AosDisks.Ok) THEN NbytesRead := AosBoot.AddH(NbytesRead, num * blockSize); 
					ELSE NnofErrors := AosBoot.AddH(NnofErrors, 1);
					END;
				ELSIF op = AosDisks.Write THEN
					NnofWrites := AosBoot.AddH(NnofWrites, 1);
					IF (res = AosDisks.Ok) THEN NbytesWritten := AosBoot.AddH(NbytesWritten, num * blockSize); 
					ELSE NnofErrors := AosBoot.AddH(NnofErrors, 1);
					END;
				ELSE
					NnofOthers := AosBoot.AddH(NnofOthers, 1);
				END;
			END;
		END Transfer;
		
		PROCEDURE GetSize*(VAR size, res: LONGINT);
		BEGIN
			size := SELF.size;	res := AosDisks.Ok;
		END GetSize;
		
		PROCEDURE Handle*(VAR msg : AosDisks.Message; VAR res : LONGINT);
		BEGIN
			res := AosDisks.Unsupported;
		END Handle;
		
		PROCEDURE &New(file : AosFS.File; diskname, filename : ARRAY OF CHAR; blockSize : LONGINT);
		BEGIN
			ASSERT(file # NIL);
			ASSERT(file.Length() MOD blockSize = 0);
			SELF.file := file; 
			SELF.blockSize := blockSize;
			SELF.size := file.Length() DIV blockSize;
			SetName(diskname);
			desc := "Virtual Disk for file "; Utilities.Append(desc, filename);
		END New;
		
	END VirtualDisk;
	
VAR 
	disks : VirtualDisk; (* to enable cleanup when unloading module *)
	
PROCEDURE Show(string : ARRAY OF CHAR);
BEGIN
	AosOut.String(ModuleName); AosOut.String(": "); AosOut.String(string);
END Show;

PROCEDURE ShowUsage;
BEGIN
	Show("Expected usage: "); AosOut.String(ModuleName); AosOut.String(" diskname filename [blocksize]"); AosOut.Ln;
END ShowUsage;

PROCEDURE AddDisk(vd : VirtualDisk);
BEGIN {EXCLUSIVE}
	vd.next := disks; disks := vd;		
END AddDisk;

PROCEDURE RemoveDisk(vd : VirtualDisk);
VAR d : VirtualDisk;
BEGIN {EXCLUSIVE}
	IF disks = vd THEN disks := disks.next;
	ELSE
		d := disks; WHILE (d # NIL) & (d.next # vd) DO d := d.next; END;
		IF (d # NIL) THEN d.next := d.next.next; END;
	END;
END RemoveDisk;

PROCEDURE IsMounted(dev: AosDisks.Device): BOOLEAN;
VAR i: LONGINT;
BEGIN
	IF dev.table # NIL THEN
		FOR i := 0 TO LEN(dev.table)-1 DO
			IF AosDisks.Mounted IN dev.table[i].flags THEN RETURN TRUE END
		END
	END;
	RETURN FALSE
END IsMounted;

(** Create an empty virtual disk *)
PROCEDURE Create*(par : ANY) : ANY; (** filename nbrOfBlocks [blockSize] *)
VAR 
	r : AosIO.StringReader; filename : ARRAY 256 OF CHAR; nbrOfBlocks, blocksize : LONGINT; 
	file : AosFS.File; rider : AosFS.Rider;
	buffer : POINTER TO ARRAY OF CHAR;
	i : LONGINT;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(filename);
	r.SkipWhitespace; r.Int(nbrOfBlocks, FALSE);
	r.SkipWhitespace; r.Int(blocksize, FALSE);
	IF (filename # "") THEN
		IF (nbrOfBlocks > 0) THEN
			IF blocksize = 0 THEN blocksize := DefaultBlocksize; END;
			file := AosFS.New(filename);
			IF file # NIL THEN
				Show("Creating virtual disk '"); AosOut.String(filename); AosOut.String("' ... ");
				NEW(buffer, nbrOfBlocks);
				file.Set(rider, 0);
				FOR i := 0 TO nbrOfBlocks - 1 DO
					file.WriteBytes(rider, buffer^, 0, blocksize);
					IF rider.res # 0 THEN
						Show("Error: Could not write bytes to file"); AosOut.Ln;
						RETURN NIL;
					END;
				END;	
				AosFS.Register(file);	
				AosOut.String("done."); AosOut.Ln;
			ELSE Show("Could not create file '"); AosOut.String(filename); AosOut.String("'"); AosOut.Ln;
			END;
		ELSE Show("nbrOfBlocks parameter expected."); AosOut.Ln;
		END;
	ELSE Show("filename parameter expected."); AosOut.Ln;
	END;
	RETURN NIL
END Create;

(** Add file as virtual disk *)	
PROCEDURE Install*(par : ANY) : ANY; (** diskname filename [blocksize]  ~ *)
VAR 
	r : AosIO.StringReader;
	diskname, filename : ARRAY 256 OF CHAR; 
	blocksize, res : LONGINT;
	file : AosFS.File;
	vd : VirtualDisk;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(diskname);
	r.SkipWhitespace; r.String(filename);
	r.SkipWhitespace; r.Int(blocksize, FALSE);
	
	IF (diskname = "") OR (filename = "") THEN ShowUsage; RETURN NIL; END;
	IF (blocksize = 0) THEN blocksize := DefaultBlocksize; END;
	
	file := AosFS.Old(filename);
	IF file # NIL THEN
		IF file.Length() MOD blocksize # 0 THEN
			Show("File size must be multiple of blocksize"); AosOut.Ln;
			RETURN NIL;
		END;	
		NEW(vd, file, diskname, filename, blocksize);
		AosDisks.registry.Add(vd, res);
		IF res = AosPlugins.Ok THEN
			AddDisk(vd);
			Show("Disk "); AosOut.String(diskname); AosOut.String(" registered."); AosOut.Ln;
		ELSE
			Show("Could not register disk, res: "); AosOut.Int(res, 0); AosOut.Ln;
		END;
	ELSE
		Show("File ");  AosOut.String(filename); AosOut.String(" not found"); AosOut.Ln;
	END;
	RETURN NIL
END Install;

(** Remove virtual disk *)
PROCEDURE Uninstall*(par : ANY) : ANY; (** diskname ~ *)
VAR r : AosIO.StringReader; diskname : AosPlugins.Name; plugin : AosPlugins.Plugin;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(diskname);
	plugin := AosDisks.registry.Get(diskname);
	IF plugin # NIL THEN
		IF ~IsMounted(plugin(VirtualDisk)) THEN
			AosDisks.registry.Remove(plugin);
			RemoveDisk(plugin (VirtualDisk));
			Show(diskname); AosOut.String(" removed"); AosOut.Ln;
		ELSE
			Show(diskname); AosOut.String(" is mounted."); AosOut.Ln;
		END;
	ELSE
		Show(diskname); AosOut.String(" not found"); AosOut.Ln;
	END;
	RETURN NIL
END Uninstall;

PROCEDURE Cleanup;
BEGIN {EXCLUSIVE}
	WHILE (disks # NIL) DO
		AosDisks.registry.Remove(disks);
		disks := disks.next;
	END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END AosDisksVirtual.

AosDisksVirtual.Create Test.Dsk 16384 ~

AosDisksVirtual.Install VDISK0 Test.Dsk 512 ~
AosDisksVirtual.Uninstall VDISK0 ~

AosDisksVirtual.Install AosCD.iso 2048 ~

S.Free AosDisksVirtual ~
