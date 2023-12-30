MODULE AosPartitions; (** AUTHOR "staubesv"; PURPOSE "Commandline front-end for AosPartitionsLib"; *)
(**
 * This is the commandline front-end for AosPartitionsLib.
 *
 * Command overview:
 *
 * Uncritical operations:
 *
 *	AosPartitions.Show ~  								Show all disk devices and their partition layout
 * 	AosPartitions.Show detail ~							Show detailed information about all disk devices and their partition layout
 *	AosPartitions.ShowAosFSLimits ~ 					Show limitations of the Aos File System
 *	
 * 	AosPartitions.ShowOps~   							Show all pending disk operations
 * 	AosPartitions.ShowOps detail ~						Show detailed information about all pending disk operations
 *
 *	AosPartitions.ShowOp uid ~							Show detailed status of the specified operation
 *	AosPartitions.Abort <opID> ~ 						Abort the disk operation with the specified operation ID
 * 	AosPartitions.Remove <opID> ~						Abort the disk operation with the specified operation ID and remove it from the operation manager
 *
 *	AosPartitions.Check dev#part ~						Perform a read test on the specified partition
 *	AosPartitions.Eject dev ~								Eject medium of the specified device
 *
 * 	AosPartitions.Safe~ 									Disallow extremely critical operations
 * 	AosPartitions.Unsafe~								Allow extermely critical operations
 *
 *	AosPartitions.ShowBlocks dev#part first nbr			Show <nbr> blocks starting at block <first> of the specified partition
 *
 * Critical operations:
 *
 *	AosPartitions.Create dev#part type sizeMB ~			Create a partition
 *	AosPartitions.Delete dev#part type ~					Delete the specified partition
 *	AosPartitions.Activate dev#part ~					Set the active bit (boot) of the specified partition
 *	AosPartitions.Deactivate dev#part ~					Clear the active bit (boot) of the specified partition
 *	AosPartitions.ChangeType dev#part from to ~			Change the type of the specified partition from <from> to <to>
 * 	AosPartitions.Format dev#part fs ~					Format the specified partition with the specified file system (AosFS, FatFS)
 *	AosPartitions.WriteMBR dev#part ~					Write MBR boot code to specified partition (partition table will be untouched)
 *
 *	AosPartitions.PartitionToFile dev#part file f nbr~ 		Write <nbr> blocks starting at block <f> to the specified file.
 *	AosPartitions.FileToPartition dev#part file f nbr~		Write the content of <file> to the specified partition starting at block <f>, <nbr> blocks
 *
 * Bluebottle-specific opertaions
 *
 *	AosPartitions.UpdateBootFile dev#part bootfile		Update the boot file (e.g. AosIDE.Bin) for the specified partition
 *	AosPartitions.UpdateBootLoader dev#part bl			Update the boot loader (e.g. OBL.Bin) for the specified partition
 *
 *	AosPartitions.GetConfig dev#part ~					Get the config string of the specified partition
 * 	AosPartitions.SetConfig dev#part config				Set the config string for the specified partition
 *
 *
 * History:
 *
 * 	05.08.2005	Cleanup (staubesv)
 *	25.11.2005	Added ShowOp procedure (staubesv)
 *	06.01.2006	Small cleanup (staubesv)	
 *	17.01.2006	WriteMBR: Caller can specify "DESTROY" parameter, fixed SetConfig (staubesv)
 *)

IMPORT AosOut, AosTexts, AosTextUtilities, AosDisks, Lib := AosPartitionsLib, AosPlugins, AosCommands, AosIO, Utilities, AosFATScavenger;

CONST

	Trace = FALSE;
	WriterBuffer = 2048; (* chars *)
	
(** Show all currently pending disk operations *)
PROCEDURE ShowOps*(parameter : PTR) : PTR; (** [detail] ~ *)
VAR
	p : AosCommands.Parameters; par : ARRAY 10 OF CHAR;
	r : AosIO.StringReader;
	details : BOOLEAN;	
BEGIN
	p := parameter(AosCommands.Parameters); NEW(r, LEN(p.str^)); r.Set(p.str^); r.String(par);
	details := (r.res = AosIO.Ok) & (par = "detail");
	Lib.operations.Show(details);
	RETURN NIL;
END ShowOps;

(** Show the detailed state of the specified operation *)
PROCEDURE ShowOp*(parameters : PTR) : PTR; (** uid ~ *)
VAR 
	p : AosCommands.Parameters; 
	r : AosIO.StringReader; w : AosIO.StringWriter; result : ARRAY WriterBuffer OF CHAR;
	operation : Lib.Operation;
	uid : LONGINT;
BEGIN
	p := parameters(AosCommands.Parameters); NEW(r, LEN(p.str^)); r.Set(p.str^); 
	NEW(w, WriterBuffer);
	r.SkipWhitespace; r.Int(uid, FALSE);
	IF r.res = AosIO.Ok THEN
		operation := Lib.operations.GetByUid(uid);
		IF operation # NIL THEN
			operation.Show(TRUE);; 
		ELSE w.String("Error: Operation UID "); w.Int(uid, 0); w.String(" not found"); w.Ln;
		END;
	ELSE w.String("Exspected parameters: uid"); w.Ln;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END ShowOp;

(** Abort a running operation *)
PROCEDURE Abort*(parameters : PTR) : PTR; (** uid  ~ *)
VAR
	operation : Lib.Operation;
	p : AosCommands.Parameters;
	r : AosIO.StringReader; w : AosIO.StringWriter;
	result : ARRAY WriterBuffer OF CHAR;
	uid : LONGINT;
BEGIN
	p := parameters (AosCommands.Parameters); 
	NEW(r, LEN(p.str^)); r.Set(p.str^); NEW(w, WriterBuffer);
	r.SkipWhitespace; r.Int(uid, FALSE);
	IF r.res = AosIO.Ok THEN
		operation := Lib.operations.GetByUid(uid);
		IF operation # NIL THEN 
			operation.Abort;
			w.String("Operation UID "); w.Int(uid, 0); w.String(" aborted"); w.Ln;
		ELSE w.String("Error: Operation UID "); w.Int(uid, 0); w.String(" not found"); w.Ln;
		END;
	ELSE w.String("Exspected parameters: uid"); w.Ln;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END Abort;

(** Remove (and if necessary abort) operations from the operations registry *)
PROCEDURE Remove*(parameters : PTR) : PTR; (** uid | "all" | "finished" ~*)
VAR
	p : AosCommands.Parameters; par : ARRAY 128 OF CHAR;
	r : AosIO.StringReader; w : AosIO.StringWriter;
	result : ARRAY WriterBuffer OF CHAR;
	uid, num : LONGINT;
BEGIN
	p := parameters (AosCommands.Parameters); 
	NEW(r, LEN(p.str^)); r.Set(p.str^); NEW(w, WriterBuffer);
	r.SkipWhitespace; r.Int(uid, FALSE);
	IF r.res = AosIO.Ok THEN
		IF Lib.operations.RemoveByUid(uid) THEN 
			w.String("Operation UID "); w.Int(uid, 0); w.String(" has been removed"); w.Ln;
		ELSE w.String("Error: Could not remove operation UID "); w.Int(uid, 0); w.Ln;
		END;
	ELSIF r.res = AosIO.FormatError THEN
		r.String(par);
		IF r.res = AosIO.Ok THEN
			Utilities.UpperCase(par);
			IF par = "ALL" THEN
				num := Lib.operations.RemoveAll(TRUE);
				w.Int(num, 0); w.String(" operations have been removed"); w.Ln;
			ELSIF par = "FINISHED" THEN
				w.String("All finished operation have been removed"); w.Ln;
			ELSE w.String("Exspected parameters: uid | all | finished"); w.Ln;
			END;
		ELSE w.String("Exspected parameters: uid | all | finished"); w.Ln;
		END;
	ELSE w.String("Exspected parameters: uid | all | finished"); w.Ln;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END Remove;

(* Format a partition with an N2KFS, AosFS or FatFS. *)
PROCEDURE Format*(parameters : PTR) : PTR; (** dev#part [ "AosFS" | "NatFS" | "NatFS2" [ FSRes [ BootFile [ Flag ] ] ] ] | ["FatFS" ["Quick"]] ~ *)
VAR
	formatAos : Lib.FormatPartition; formatFat : AosFATScavenger.FormatPartition;
	fsname, bootfile, quick : ARRAY 128 OF CHAR;
	fsRes, flags : LONGINT;
	quickFormat : BOOLEAN;
	selection : Lib.Selection;
	r : AosIO.StringReader; w : AosIO.StringWriter;
	result : ARRAY WriterBuffer OF CHAR; 
BEGIN
	IF GetSelection(parameters, TRUE, w, r, selection) THEN 
		r.String(fsname);
		IF r.res = AosIO.Ok THEN
			IF fsname = "FatFS" THEN 
				r.SkipWhitespace; r.String(quick);
				quickFormat := (r.res = AosIO.Ok) & (quick = "Quick");
				NEW(formatFat, selection.disk, selection.partition, TRUE);
				formatFat.SetParameters(Utilities.NewString("no name"), quickFormat);
				formatFat.SetStart;
				w.String("AosPartitions UID "); w.Int(formatFat.uid, 0); w.String(": Started FAT format on "); w.String(formatFat.diskpartString); w.Ln;
			ELSIF (fsname = "AosFS") OR (fsname = "NatFS") OR (fsname = "NatFS1") OR (fsname = "NatFS2") THEN
				bootfile := ""; fsRes := -2; flags := 0;
				r.SkipWhitespace; r.Int(fsRes, FALSE);
				IF r.res = AosIO.Ok THEN 
					r.SkipWhitespace; r.String(bootfile);
					IF r.res = AosIO.Ok THEN
						r.SkipWhitespace; r.Int(flags, FALSE); 
					END;
				END;
				NEW(formatAos, selection.disk, selection.partition, TRUE);
				formatAos.SetParameters(fsname, bootfile, fsRes, flags);
				formatAos.SetStart;			
			ELSE w.String("File system "); w.String(fsname); w.String(" is not supported"); w.Ln;
			END;
		ELSE (* optional parameters not specified *)
			NEW(formatAos, selection.disk, selection.partition, TRUE);
			formatAos.SetParameters("AosFS", "", -2, 0);
			formatAos.SetStart;			
			w.String("AosPartitions UID "); w.Int(formatAos.uid, 0); w.String(": Started format on "); w.String(formatAos.diskpartString); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END Format;

(* Update the boot file in an existing Oberon partition. *)
PROCEDURE UpdateBootFile*(parameters : PTR) : PTR; (** dev#part [ BootFile ] ~ *)
VAR 
	updateBootFile : Lib.UpdateBootFile;
	selection : Lib.Selection;
	filename, temp : ARRAY 128 OF CHAR;
	w : AosIO.StringWriter; r : AosIO.StringReader;
	result : ARRAY WriterBuffer OF CHAR;
BEGIN
	IF GetSelection(parameters, FALSE, w, r, selection) THEN 
		filename := ""; 
		r.SkipWhitespace; r.String(temp);
		IF r.res = AosIO.Ok THEN filename := temp; ELSE filename := ""; END;
		NEW(updateBootFile, selection.disk, selection.partition, TRUE);
		updateBootFile.SetParameters(filename);
		updateBootFile.SetStart;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END UpdateBootFile;

PROCEDURE GetConfig*(parameters : PTR) : PTR;	(** dev#part  *)
CONST MaxSize = 2048;
VAR 
	getConfig : Lib.GetConfig;
	selection : Lib.Selection;
	configuration : Lib.Configuration;
	w, table : AosIO.StringWriter; r : AosIO.StringReader; 
	result : ARRAY WriterBuffer OF CHAR;
	string : ARRAY MaxSize OF CHAR;
	i : LONGINT;
BEGIN
	IF GetSelection(parameters, TRUE, w, r, selection) THEN 
		NEW(getConfig, selection.disk, selection.partition, TRUE);
		getConfig.SetBlockingStart;
		IF getConfig.state.status * Lib.StatusError = {} THEN
			NEW(configuration);
			configuration.table := getConfig.GetTable();
			table := configuration.GetTableAsString();
			table.Get(string);
			(* AosCommands uses the quote character to separate commands *)
			FOR i := 0 TO LEN(string)-1 DO IF string[i] = ";" THEN string[i] := ","; END; END;
			w.String("AosPartitions.SetConfig "); w.String(getConfig.diskpartString); w.Ln;
			w.String(string); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END GetConfig;

(* Write the specified configuration string to the specified partition.							*)
(* Notes:																					*)
(*	- Use the "," character to separate commands 											*)
(*	- After an "#" character, the rest of the line is skipped/ignored							*)
PROCEDURE SetConfig*(parameters : PTR) : PTR; (** dev#part { str = "val" } ~ *)
VAR 
	setConfig : Lib.SetConfig;
	selection : Lib.Selection;
	p : AosCommands.Parameters;
	w : AosIO.StringWriter; r : AosIO.StringReader;
	result : ARRAY WriterBuffer OF CHAR;
	configString : Utilities.String;
	i, j : LONGINT;
BEGIN
	IF GetSelection(parameters, TRUE, w, r, selection) THEN
		p := parameters (AosCommands.Parameters); 
		(* append character "~" to config string *)
		NEW(configString, LEN(p.str) - r.Pos() + 1 + 1); j := 0;
		FOR i := r.Pos() TO LEN(p.str)-1 DO 
			IF p.str[i] = ',' THEN p.str[i]:=";"; END; (* AosCommands uses comma character to separate commands *)
			configString[j] := p.str[i]; INC(j);
		END;
		configString[j-1] := "~"; configString[j] := 0X;
		NEW(setConfig, selection.disk, selection.partition, TRUE);
		setConfig.SetParameters(configString, 0);
		setConfig.SetStart;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END SetConfig;

(** Perform a read check on partition *)
PROCEDURE Check*(parameter : PTR) : PTR; (** dev#part *)
VAR  
 	selection : Lib.Selection;
 	checkPartition : Lib.CheckPartition;
 	r : AosIO.StringReader; w : AosIO.StringWriter;
 	result : ARRAY WriterBuffer OF CHAR;
BEGIN
	IF GetSelection(parameter, FALSE, w, r, selection) THEN 
		NEW(checkPartition, selection.disk, selection.partition, TRUE);
		checkPartition.SetStart;	
		w.String("AosPartitions: UID "); w.Int(checkPartition.uid, 0); w.String(": Started CheckPartition on "); 
		w.String(selection.disk.device.name); w.Char("#"); w.Int(selection.partition, 0); w.Ln;
	ELSE (* skip; error written to <w> by ScanOpenPart *)
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END Check;

(** Change the type of dev#part from oldtype to newtype *)
PROCEDURE ChangeType*(parameters : PTR) : PTR; (** dev#part oldtype newtype ~ *)
VAR 
	change : Lib.ChangePartType;
	oldtype, newtype : LONGINT;
	selection : Lib.Selection;
	w : AosIO.StringWriter; r : AosIO.StringReader; 
	result : ARRAY WriterBuffer OF CHAR;
BEGIN
	IF GetSelection(parameters, TRUE, w, r, selection) THEN 
		IF ~selection.disk.isDiskette THEN
			r.Int(oldtype, FALSE);
			IF (r.res = AosIO.Ok) & (oldtype > 0) & (oldtype < 256) THEN
				r.SkipWhitespace; r.Int(newtype, FALSE);
				IF (r.res = AosIO.Ok) & (newtype > 0) & (newtype < 256) THEN
					NEW(change, selection.disk, selection.partition, TRUE);
					change.SetParameters(oldtype, newtype);
					change.SetStart;
				ELSE w.String("Exspected parameters: dev#part oldtype newtype, failed to parse newtype"); w.Ln;
				END;
			ELSE w.String("Exspected parameters: dev#part oldtype newtype, failed to parse oldtype"); w.Ln;
			END;
		ELSE w.String("Operation not support for floppy disk drives."); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END ChangeType;

(** Delete a partition *)
PROCEDURE Delete*(parameters : PTR) :PTR; (** dev#part type ~ *)
VAR
	delete : Lib.DeletePartition;
	selection : Lib.Selection;
	w : AosIO.StringWriter; r : AosIO.StringReader;
	type : LONGINT; 
	result : ARRAY WriterBuffer OF CHAR;
BEGIN
	IF GetSelection(parameters, FALSE, w, r, selection) THEN 
		IF ~selection.disk.isDiskette THEN
			r.Int(type, FALSE); r.SkipWhitespace;
			IF (r.res = AosIO.Ok) & (type > 0) & (type < 256) THEN 
				NEW(delete, selection.disk, selection.partition, TRUE);
				delete.SetParameters(type);
				delete.SetStart;
			ELSE w.String("Expected parameters: dev#part type sizeMB, error while parsing type"); w.Ln;
			END;
		ELSE w.String("Operation not supported for floppy disks"); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;	
END Delete;

PROCEDURE Create*(parameters : PTR) : PTR; (** dev#part type sizeMB ~ *)
VAR
	create : Lib.CreatePartition;
	selection : Lib.Selection;
	w : AosIO.StringWriter; r : AosIO.StringReader;
	type, size : LONGINT; 
	result : ARRAY WriterBuffer OF CHAR;
BEGIN
	IF GetSelection(parameters, FALSE, w, r, selection) THEN 
		IF ~selection.disk.isDiskette THEN
			r.Int(type, FALSE); r.SkipWhitespace;
			IF (r.res = AosIO.Ok) & (type > 0) & (type < 256) THEN 
				r.Int(size, FALSE);
				IF (r.res = AosIO.Ok) & (size > 0) THEN 
					NEW(create, selection.disk, selection.partition, TRUE);
					create.SetParameters(size, type);
					create.SetStart;
				ELSE w.String("Expected parameters: dev#part type sizeMB, error while parsing size"); w.Ln;
				END;
			ELSE w.String("Expected parameters: dev#part type sizeMB, error while parsing type"); w.Ln;
			END;
		ELSE w.String("Operation not supported on floppy disks"); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;	
END Create;

(** Mark partition as active *)
PROCEDURE Activate*(parameter : PTR) : PTR; (** dev#part ~ *)
BEGIN
	ChangeActiveBit(TRUE, parameter);
	RETURN NIL; 
END Activate;

(** Mark partition as inactive *)
PROCEDURE Deactivate*(parameter : PTR) : PTR; (** dev#part ~ *)
BEGIN
	ChangeActiveBit(FALSE, parameter);
	RETURN NIL;
END Deactivate;

PROCEDURE ChangeActiveBit(active : BOOLEAN; parameter : PTR);
VAR
	setFlags : Lib.SetFlags;
	selection : Lib.Selection;
	w : AosIO.StringWriter; r : AosIO.StringReader; 
	result : ARRAY WriterBuffer OF CHAR; 
BEGIN
	IF GetSelection(parameter, TRUE, w, r, selection) THEN 
		IF ~selection.disk.isDiskette THEN
			NEW(setFlags, selection.disk, selection.partition, TRUE);
			setFlags.SetParameters(active);
			setFlags.SetStart;
			w.String("AosPartitions UID "); w.Int(setFlags.uid, 0); w.String(": Started SetFlags on "); 
			w.String(selection.disk.device.name); w.Char("#"); w.Int(selection.partition, 0); w.Ln;
		ELSE w.String("Operation not supported for floppy disks"); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result); 
END ChangeActiveBit;

(** Write <numblock> sectors from a file to a partition, starting at block <block> *)
PROCEDURE FileToPartition*(parameters : PTR) : PTR; (** dev#part filename [block numblocks] ~ *)
VAR
	fileToPartition : Lib.FileToPartition;
	filename : ARRAY 128 OF CHAR;
	block, numblocks : LONGINT;
	selection : Lib.Selection;
	r : AosIO.StringReader; w : AosIO.StringWriter;
	result : ARRAY WriterBuffer OF CHAR; 
BEGIN
	IF GetSelection(parameters, TRUE, w, r, selection) THEN 
		r.String(filename);
		IF r.res = AosIO.Ok THEN
			r.SkipWhitespace; r.Int(block, FALSE);
			IF r.res = AosIO.Ok THEN 
				r.SkipWhitespace; r.Int(numblocks, FALSE); 
				IF r.res # AosIO.Ok THEN
					w.String("Exspected parameters: dev#part filename [block numblocks], failed to parse numblocks"); w.Ln;
					RETURN NIL;
				END;
			ELSE (* optional parameters not specified *)
				block := -1; numblocks := -1;
			END;
			NEW(fileToPartition, selection.disk, selection.partition, TRUE);
			fileToPartition.SetParameters(filename, block, numblocks);
			fileToPartition.SetStart;
			w.String("AosPartitions UID "); w.Int(fileToPartition.uid, 0); w.String(": Started FileToPartition on "); 
			w.String(fileToPartition.diskpartString); w.Ln;
		ELSE w.String("Exspected parameters: dev#part name [block numblocks], failed to parse filename"); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result); 
	RETURN NIL;
END FileToPartition;

(** Write <numblock> sectors from a partition to a file, starting at block <block>.
	If the optional parameters are not specified, store whole partition into file *)
PROCEDURE PartitionToFile*(parameters : PTR) : PTR; (** dev#part filename [block numblocks] ~ *)
VAR
	partitionToFile : Lib.PartitionToFile;
	filename : ARRAY 128 OF CHAR;
	block, numblocks : LONGINT;
	selection : Lib.Selection;
	r : AosIO.StringReader; w : AosIO.StringWriter;
	result : ARRAY WriterBuffer OF CHAR; 
BEGIN
	IF GetSelection(parameters, TRUE, w, r, selection) THEN 
		r.String(filename);
		IF r.res = AosIO.Ok THEN
			r.SkipWhitespace; r.Int(block, FALSE);
			IF r.res = AosIO.Ok THEN 
				r.SkipWhitespace; r.Int(numblocks, FALSE); 
				IF r.res # AosIO.Ok THEN
					w.String("Exspected parameters: dev#part filename [block numblocks], failed to parse numblocks"); w.Ln;
					RETURN NIL;
				END;
			ELSE (* optional parameters not specified *)
				block := -1; numblocks := -1;
			END;
			NEW(partitionToFile, selection.disk, selection.partition, TRUE);
			partitionToFile.SetParameters(filename, block, numblocks);
			partitionToFile.SetStart;
			w.String("AosPartitions UID "); w.Int(partitionToFile.uid, 0); w.String(": Started PartitionToFile on "); 
			w.String(partitionToFile.diskpartString); w.Ln;
		ELSE w.String("Exspected parameters: dev#part name [block numblocks], failed to parse filename"); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result); 
	RETURN NIL;
END PartitionToFile;

(** Write the specified Master Boot Record (MBR) to the specified partition. The partition table will be preserved 	*)
(*	unless the optional parameter "DESTROY" is specified.														*)
(*	WARNING: Using the DESTROY parameter will render any disk content unusable.								*)	
PROCEDURE WriteMBR*(parameters : PTR) : PTR; (** dev#0 filename ["DESTROY"] ~ *)
VAR
	writeMBR : Lib.WriteMBR;
	filename, destroy : ARRAY 128 OF CHAR;
	selection : Lib.Selection;
	w : AosIO.StringWriter; r : AosIO.StringReader;
	result : ARRAY WriterBuffer OF CHAR;
BEGIN
	IF GetSelection(parameters, FALSE, w, r, selection) THEN 
		IF ~selection.disk.isDiskette THEN
			IF selection.partition = 0 THEN 
				r.String(filename); 
				IF r.res = AosIO.Ok THEN
					NEW(writeMBR, selection.disk, selection.partition, TRUE);
					r.SkipWhitespace; r.String(destroy);
					IF (r.res = AosIO.Ok) & (destroy = "DESTROY") THEN
						writeMBR.SetParameters(filename, FALSE);
					ELSE
						writeMBR.SetParameters(filename, TRUE);
					END;
					writeMBR.SetStart;
				ELSE w.String("Exspected parameters: dev#0 filename, failed to parse filename"); w.Ln;
				END;
			ELSE w.String("Exspected parameters: dev#0 filename, partition is not 0"); w.Ln;
			END;
		ELSE w.String("Operation not supported for floppy disks"); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END WriteMBR;

(** Update the boot loader OBL in an existing AosFS partition, replacing it by the new BBL handling the Init string differently.
The BBL must imperatively have the same size, 4 blocks, as the OBL. The same BBL is applicable to all AosFS partitions. *)
PROCEDURE UpdateBootLoader*(parameters : PTR) : PTR; (** dev#part BootLoader ~ *)
VAR
	updateLoader : Lib.UpdateBootLoader;
	selection : Lib.Selection;
	filename, temp : ARRAY 128 OF CHAR;
	w : AosIO.StringWriter; r : AosIO.StringReader;
	result : ARRAY WriterBuffer OF CHAR;
BEGIN
	IF GetSelection(parameters, FALSE, w, r, selection) THEN 
		filename := ""; r.SkipWhitespace; r.String(temp);
		IF r.res = AosIO.Ok THEN filename := temp; ELSE filename := ""; END;
		NEW(updateLoader, selection.disk, selection.partition, TRUE);
		updateLoader.SetParameters(filename);
		updateLoader.SetStart;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END UpdateBootLoader;

PROCEDURE ShowBlockCallback(text : AosTexts.Text);
VAR string : Utilities.String;
BEGIN
	text.AcquireRead;
	NEW(string, text.GetLength()); AosTextUtilities.TextToStr(text, string^); 
	text.ReleaseRead;
	AosOut.String(string^); AosOut.Ln;
END ShowBlockCallback; 

PROCEDURE ShowBlocks*(parameters : PTR) : PTR; (** dev#part block [numblocks] ~ *)
VAR
	showBlocks : Lib.ShowBlocks;
	block, numblocks : LONGINT;
	selection : Lib.Selection;
	w : AosIO.StringWriter; r : AosIO.StringReader;
	result : ARRAY WriterBuffer OF CHAR;
BEGIN
	IF GetSelection(parameters, FALSE, w, r, selection) THEN
		r.Int(block, FALSE);
		IF r.res = AosIO.Ok THEN
			r.SkipWhitespace; r.Int(numblocks, FALSE);
			IF r.res # AosIO.Ok THEN (* optional parameter not specified *) numblocks := -1; END;
			NEW(showBlocks, selection.disk, selection.partition, TRUE);
			showBlocks.SetParameters(block, numblocks);
			showBlocks.SetCallback(ShowBlockCallback);
			showBlocks.SetStart;
		ELSE w.String("Exspected parameters: dev#part block [numblocks], failed to parse block"); w.Ln;
		END;
	END;
	w.Get(result); AosOut.String(result);
	RETURN NIL;
END ShowBlocks;

(** Eject medium of device dev *)
PROCEDURE Eject*(parameter : PTR) : PTR; (** dev ~ *)
VAR 
	p : AosCommands.Parameters;
	plugin : AosPlugins.Plugin;
	dev : AosDisks.Device; 
	r : AosIO.StringReader; w : AosIO.StringWriter;
	result : ARRAY WriterBuffer OF CHAR;
	name : ARRAY 32 OF CHAR;
BEGIN	
	NEW(w, WriterBuffer);
	p := parameter (AosCommands.Parameters); NEW(r, LEN(p.str^)); r.Set(p.str^);	
	r.SkipWhitespace; r.String(name);
	IF r.res = AosIO.Ok THEN	
		plugin := AosDisks.registry.Get(name);		
		IF plugin # NIL THEN
			dev := plugin (AosDisks.Device);
			w.String(Lib.Eject(dev)); w.Ln;
		ELSE w.String("Device "); w.String(name); w.String(" not found"); w.Ln;
		END;
	ELSE w.String("Exspected parameters: dev"); w.Ln;
	END;
	w.Get(result); AosOut.String(result);	
	RETURN NIL;
END Eject;

PROCEDURE Unsafe*(ptr : PTR) : PTR; (** ~ *)
BEGIN
	Lib.safe := FALSE; AosOut.String("NOW in UNSAFE mode!"); AosOut.Ln;
	RETURN NIL;
END Unsafe;

PROCEDURE Safe*(ptr : PTR) : PTR; (** ~ *)
BEGIN
	Lib.safe := TRUE; AosOut.String("Now in safe mode"); AosOut.Ln;
	RETURN NIL;
END Safe;

(** Show all disk devices and their partition layout. *)
PROCEDURE Show*(parameter : PTR) : PTR ; (** ["detail"] ~ *)
VAR
	diskTable : Lib.Disks; disk : Lib.Disk;
	p : AosCommands.Parameters; par : ARRAY 10 OF CHAR;
	r : AosIO.StringReader; w : AosIO.StringWriter;
	verbose : BOOLEAN;	
	i, res : LONGINT;
	string : ARRAY 2048 OF CHAR;
BEGIN
	p := parameter(AosCommands.Parameters); NEW(r, LEN(p.str^)); r.Set(p.str^);r.String(par);
	verbose := (r.res = AosIO.Ok) & (par = "detail");
	Lib.diskModel.Update;
	Lib.diskModel.Acquire;	
	diskTable := Lib.diskModel.disks;

	NEW(w, WriterBuffer);
	
	IF diskTable # NIL THEN 
		FOR i := 0 TO LEN(diskTable)-1 DO
			disk := diskTable[i]; 
			ShowDevice(w, disk, verbose);
			IF disk.res # AosDisks.MediaMissing THEN
				IF (disk.table # NIL) THEN
					ShowTable(w, disk, disk.table, verbose)
				ELSE
					w.String(Lib.GetErrorMsg("Error", res)); w.Ln; 
				END
			END;
			w.Ln;
		END;
	ELSE
		w.String("No Devices found"); w.Ln;
	END; 
	Lib.diskModel.Release;	
	w.Update; w.Get(string); AosOut.String(string);
	RETURN NIL;
END Show;

PROCEDURE ShowDevice(w: AosIO.Writer; disk: Lib.Disk; verbose: BOOLEAN);
BEGIN
	w.String("Disk: "); w.String(disk.device.name); w.String(", ");
	IF disk.res = AosDisks.Ok THEN
		Lib.WriteK(w, ENTIER(disk.size * 1.0 * disk.device.blockSize / 1024));
		IF verbose THEN
			w.String(" = "); w.Int(disk.size, 1); 
			w.String(" * "); w.Int(disk.device.blockSize,1);
		END
	ELSE
		w.String(Lib.GetErrorMsg("GetSize failed", disk.res));
	END;
	IF AosDisks.Removable IN disk.device.flags THEN w.String(", removable") END;
	IF AosDisks.ReadOnly IN disk.device.flags THEN w.String(", read-only") END;
	IF verbose THEN
		IF disk.res # AosDisks.MediaMissing THEN
			w.String(", ");
			IF disk.gres = AosDisks.Ok THEN
				w.String("CHS: "); w.Int(disk.geo.cyls, 1); w.String("*"); w.Int(disk.geo.hds, 1); w. String("*"); w.Int(disk.geo.spt, 1);
			ELSE
				w.String(Lib.GetErrorMsg("GetCHS: ", disk.gres)); 
			END
		END
	END;
	IF disk.device.desc # "" THEN w.String(", "); w.String(disk.device.desc) END;
	IF verbose THEN	w.String(", mntcnt="); w.Int(disk.device.openCount, 1) END;
	w.Ln;
END ShowDevice;

PROCEDURE ShowTable( w: AosIO.Writer; disk: Lib.Disk; table: AosDisks.PartitionTable; verbose: BOOLEAN);
VAR j: LONGINT; r: LONGREAL; ugly : ARRAY 10 OF CHAR; temp : ARRAY 128 OF CHAR; ignore : LONGINT;
BEGIN
	FOR j := 0 TO LEN(table)-1 DO
		r := (table[j].size * 1.0D0 * disk.device.blockSize) / (1024*1024); (* M *)
		Lib.WritePart(w, disk.device, j);
		IF verbose THEN
			w.Int(table[j].start, 12);
			w.Int(table[j].size, 12)
		END;
		Utilities.FloatToStr(r, 6, 1, 0, ugly);
		IF r < 10 THEN w.String(ugly); 
		ELSE w.Int(ENTIER(r), 6)
		END;
		w.String(" MB ");
		IF (table[j].type >= 1) & (table[j].type <= 255) THEN
			w.Int(table[j].type, 3)
		ELSE
			w.String("---")
		END;
		w.Char(" ");
		IF (j # 0) & ~(AosDisks.Primary IN table[j].flags) THEN w.String( " | ") END; (* logical drive *)
		IF AosDisks.Boot IN table[j].flags THEN w.String(" * ") END; (* bootable *)
		Lib.WriteType(table[j].type, temp, ignore); w.String(temp);
		IF verbose THEN
			IF AosDisks.Mounted IN table[j].flags THEN w.String(" [mounted]") END
		END;
		w.Ln;
	END 
END ShowTable;

(** Display limitations of AosFS *)
PROCEDURE ShowAosFSLimits*(ptr : PTR) : PTR; (** ~ *)
BEGIN
	Lib.ShowAosFSLimits;
	RETURN NIL;
END ShowAosFSLimits;

(* Scan the command line parameters for a device#partition specification. *)
(* The Writer <w> is used to return error messages, <r> contains p.str (dev#part skipped) *)
(* check : IF TRUE, only AosDisks.Valid partitions are returns *)
PROCEDURE GetSelection*(parameters : PTR; check : BOOLEAN; VAR w : AosIO.StringWriter;  VAR r : AosIO.StringReader; VAR selection : Lib.Selection) : BOOLEAN;
VAR 
	p : AosCommands.Parameters; 
	devpart : ARRAY 32 OF CHAR;
BEGIN
	selection.disk.device := NIL; selection.partition := -1; (* invalid *)
	p := parameters (AosCommands.Parameters); 
	NEW(r, LEN(p.str^)); r.Set(p.str^); NEW(w, WriterBuffer);
	r.SkipWhitespace; r.String(devpart);
	IF r.res # AosIO.Ok THEN 
		w.String("Expected parameters: dev#part"); w.Ln;
		RETURN FALSE; 
	END;
	r.SkipWhitespace;
	
	(* special case: diskette *)
	IF Utilities.Match("Diskette*", devpart) THEN
		check := FALSE;
	END;
	IF Lib.diskModel.GetDisk(devpart, selection, check) THEN			
		IF Trace THEN 
			AosOut.String("AosPartitions: Command line selection: "); AosOut.String(selection.disk.device.name); 
			AosOut.Char("#"); AosOut.Int(selection.partition, 0); AosOut.Ln; 
		END;
		RETURN TRUE;
	ELSE w.String("Expected parameters: dev#part"); w.Ln;
	END;
	RETURN FALSE;
END GetSelection;

END AosPartitions.

S.Free WMPartitionsPlugins AosDiskBench AosPartitions ~