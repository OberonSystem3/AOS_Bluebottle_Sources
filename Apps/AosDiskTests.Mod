MODULE AosDiskTests; (** AUTHOR: "staubesv"; PURPOSE: "Simple block device tests" *)
(**
 * Usage:
 *
 *	AosDiskTests.WriteTestData dev#part ~ fills the specified partition with test data
 *	AosDiskTests.VerifyTestData dev#part ~ checks whether the test data can be correctly read
 *	AosDiskTests.WriteZeros dev#part ~ fills the specifed partition with zeros
 *	AosDiskTests.Test dev#part ~ tests the specified partition
 *	AosDiskTests.TransferBlocks dev#part "READ"|"WRITE" block numblocks ~  (TUI only)
 *
 *	WMPartitions.Open ~ opens the graphical front-end
 *
 * History:
 *
 *	28.02.2006	First release (staubesv)
 *)

IMPORT
	SYSTEM, AosMemory, AosIO, AosRandom, AosOut, AosKernel, AosDisks, AosPartitions, Lib := AosPartitionsLib, Utilities, AosBoot;	
	
TYPE

	TestDataBase = OBJECT(Lib.Operation);
	VAR
		buffer : POINTER TO ARRAY OF CHAR;
		sectorsPerTransfer : LONGINT;
	
		PROCEDURE SetParameters*(sectorsPerTransfer : LONGINT);
		BEGIN
			SELF.sectorsPerTransfer := sectorsPerTransfer;
		END SetParameters;
				
		PROCEDURE ValidParameters*() : BOOLEAN;
		BEGIN
			IF sectorsPerTransfer < 1 THEN ReportError("SectorsPerTransfer must be >= 1"); RETURN FALSE; END;
			IF disk.device.blockSize MOD 256 # 0 THEN ReportError("Device blocksize MOD 256 MUST BE 0"); RETURN FALSE; END;
			RETURN TRUE;
		END ValidParameters;
		
	END TestDataBase;

TYPE

	(** Fills partition with test data *)
	TestDataWriter* = OBJECT(TestDataBase);
	
		PROCEDURE FillWithTestData(VAR buffer : ARRAY OF CHAR);
		VAR i : LONGINT;
		BEGIN
			FOR i := 0 TO LEN(buffer) - 1 DO buffer[i] := CHR(i MOD 256); END;
		END FillWithTestData;

		PROCEDURE DoOperation*;
		VAR pos, num, nbrOfBlocks, blocksWritten, res : LONGINT;
		BEGIN
			SetStatus(state.status, "Writing test data...", 0, 0, disk.table[partition].size, TRUE);
			NEW(buffer, disk.device.blockSize * sectorsPerTransfer);
			FillWithTestData(buffer^);
			pos := disk.table[partition].start; num := sectorsPerTransfer; nbrOfBlocks := disk.table[partition].size;
			LOOP
				IF num > nbrOfBlocks - blocksWritten THEN num := nbrOfBlocks - blocksWritten; END;
				IF ~alive OR (num = 0) THEN EXIT; END;
				disk.device.Transfer(AosDisks.Write, pos, num, buffer^, 0, res);
				IF res # AosDisks.Ok THEN ReportError(Lib.GetTransferError(disk.device, AosDisks.Write, pos, res)); END;
				INC(pos, num); INC(blocksWritten, num);
				SetCurrentProgress(blocksWritten);
			END;
			IF alive THEN 
				result.String("Test data written to partition "); result.String(diskpartString);
			ELSE
				result.String("Operation aborted");
			END;
		END DoOperation;
		
		PROCEDURE &Init(disk :Lib.Disk; partition : LONGINT; log : BOOLEAN);
		BEGIN
			Init^(disk, partition, log);
			name := "WriteTestData"; desc := "Write test data"; locktype := Lib.WriterLock;
		END Init;		
		
	END TestDataWriter;
	
TYPE
	
	(** Checks whether the test data written by the WriteTestData object can be read back correctly *)
	TestDataChecker* = OBJECT(TestDataBase);
		
		PROCEDURE DoOperation*;
		VAR 
			pos, num, nbrOfBlocks, blocksRead, res : LONGINT; string, nbr : ARRAY 128 OF CHAR;
			expected, found, foundAt : LONGINT;
		BEGIN
			SetStatus(state.status, "Verifying test data...", 0, 0, disk.table[partition].size, TRUE);
			NEW(buffer, disk.device.blockSize * sectorsPerTransfer);
			pos := disk.table[partition].start; num := sectorsPerTransfer; nbrOfBlocks := disk.table[partition].size;
			LOOP
				IF num > nbrOfBlocks - blocksRead THEN num := nbrOfBlocks - blocksRead; END;
				IF ~alive OR (num = 0) THEN EXIT; END;
				disk.device.Transfer(AosDisks.Read, pos, num, buffer^, 0, res);
				IF res # AosDisks.Ok THEN 
					ReportError(Lib.GetTransferError(disk.device, AosDisks.Read, pos, res)); 
				ELSIF ~TestDataIsCorrect(0, num, disk.device.blockSize, buffer^, expected, found, foundAt) THEN
					string := "Verification of block at pos "; Utilities.IntToStr(pos, nbr); Utilities.Append(string, nbr); 
					Utilities.Append(string, ", Expected value: "); Utilities.IntToStr(expected, nbr); Utilities.Append(string, nbr);
					Utilities.Append(string, ", found: "); Utilities.IntToStr(found, nbr); Utilities.Append(string, nbr);
					Utilities.Append(string, " at index: "); Utilities.IntToStr(foundAt, nbr); Utilities.Append(string, nbr);
					ReportError(string);
				END;
				INC(pos, num); INC(blocksRead, num);
				SetCurrentProgress(blocksRead);
			END;
			IF alive THEN 
				result.String("Test data verified on partition "); result.String(diskpartString); result.String(" - ");
				IF state.errorCount = 0 THEN result.String("No "); END;
				result.String("Errors found.");
			END;
		END DoOperation;
		
		PROCEDURE &Init(disk :Lib.Disk; partition : LONGINT; log : BOOLEAN);
		BEGIN
			Init^(disk, partition, log);
			name := "CheckTestData"; desc := "Write/Verify test data"; locktype := Lib.ReaderLock;
		END Init;		
		
	END TestDataChecker;
	
TYPE
	
	ZeroWriter* = OBJECT(TestDataWriter);
	
		PROCEDURE FillWithTestData*(VAR buffer : ARRAY OF CHAR);
		VAR i : LONGINT;
		BEGIN
			FOR i := 0 TO LEN(buffer) - 1 DO buffer[i] := 0X; END;
		END FillWithTestData;
		
		PROCEDURE Init(disk : Lib.Disk; partition : LONGINT; log : BOOLEAN);
		BEGIN
			Init^(disk, partition, log);
			name := "ZeroWriter"; desc := "Fill partition with zeros"; locktype := Lib.WriterLock;
		END Init;
		
	END ZeroWriter;
	
TYPE

	(**
	 * Test a partition 
	 *)
	DiskTest* = OBJECT(Lib.Operation)
	VAR
		(* parameters *)
		doRead, doWrite, testData : BOOLEAN;
		nbrOfTests, maxNbrOfSectors, maxOffset : LONGINT;
			
		start, size : LONGINT; (* First block of partition and size of the partition *)
		offset : LONGINT; (* currently used offset into client buffer *)
		
		(* Coverage information *)
		testCount : LONGINT;
		testedOffsets : POINTER TO ARRAY OF BOOLEAN;
		testedSectors : POINTER TO ARRAY OF BOOLEAN;
		blocksRead : HUGEINT;

		buffer : POINTER TO ARRAY OF CHAR;
		random : AosRandom.Generator;
		
		PROCEDURE SetParameters*(doRead, doWrite,  testData : BOOLEAN; nbrOfTests, maxNbrOfSectors, maxOffset : LONGINT);
		BEGIN
			SELF.doRead := doRead; SELF.doWrite := doWrite; SELF.testData := testData;
			SELF.nbrOfTests := nbrOfTests; SELF.maxNbrOfSectors := maxNbrOfSectors; SELF.maxOffset := maxOffset;
		END SetParameters;

		PROCEDURE ValidParameters*() : BOOLEAN;
		BEGIN 
			IF ~doRead & ~doWrite THEN ReportError("Either read or write tests must be done"); RETURN FALSE; END;
			IF maxNbrOfSectors < 1 THEN ReportError("MaxNbrOfSectors must be >= 1"); RETURN FALSE; END;
			IF maxOffset < 0 THEN ReportError("MaxOffset must be >= 0"); RETURN FALSE; END;
			RETURN TRUE;
		END ValidParameters;
		
		PROCEDURE WriteTestSettings;
		VAR adr : LONGINT;
		BEGIN
			info.String("Test Settings:"); info.Ln;
			info.String("   Number of Tests: "); IF nbrOfTests > 0 THEN info.Int(nbrOfTests, 0); ELSE info.String("Endless Loop Mode"); END; info.Ln;
			info.String("   Read Tests: "); IF doRead THEN info.String("Yes"); ELSE info.String("No"); END; info.Ln;
			info.String("   Write Tests: "); IF doWrite THEN info.String("Yes"); ELSE info.String("No"); END; info.Ln;
			info.String("   Verify Reads using Test Data: "); IF testData THEN info.String("Yes"); ELSE info.String("No"); END; info.Ln;
			info.String("   Max. Sectors per Transfer: "); info.Int(maxNbrOfSectors, 0); info.Ln;
			info.String("   Max. Offset into Client Buffer: "); info.Int(maxOffset, 0); info.Ln;
			info.String("   Physical Address of Client Buffer: "); 
			adr := AosMemory.PhysicalAdr(SYSTEM.ADR(buffer[0]), 1); info.Hex(adr, 0); info.String("H");
			info.Ln;
		END WriteTestSettings;
		
		PROCEDURE WriteSummary;
		VAR i, val : LONGINT;
					
			PROCEDURE WriteB*(b: HUGEINT; w : AosIO.Writer);
			VAR suffix: ARRAY 3 OF CHAR;
			BEGIN
				IF AosBoot.GreaterH(b, 1024*1024*1024) THEN suffix := "GB"; b := AosBoot.DivH(b, 1024*1024*1024);
				ELSIF AosBoot.GreaterH(b, 1024*1024) THEN suffix := "MB"; b := AosBoot.DivH(b, 1024*1024);
				ELSIF AosBoot.GreaterH(b, 1024) THEN suffix := "KB"; b := AosBoot.DivH(b, 1024); 
				ELSE suffix := "B"; 
				END;
				w.Int(SHORT(b), 0); w.String(suffix); 
			END WriteB;
		
		BEGIN
			info.String("Test Summary:"); info.Ln;
			info.String("   "); info.Int(testCount, 0); info.String(" Test Runs done"); info.Ln;
			IF testedOffsets # NIL THEN
				val := 0; FOR i := 0 TO LEN(testedOffsets)-1 DO IF testedOffsets[i] THEN INC(val); END; END;
				info.String("   Offset Coverage: "); info.FloatFix(100.0 * val / LEN(testedOffsets), 5, 2, 0); info.Char("%"); info.Ln;
			END;
			IF testedSectors # NIL THEN
				val := 0; FOR i := 0 TO LEN(testedSectors)-1 DO IF testedSectors[i] THEN INC(val); END; END;
				info.String("   Transfer Sizes Coverage: "); info.FloatFix(100.0 * val / LEN(testedSectors), 5, 2, 0); info.Char("%"); info.Ln;
			END;
			info.String("   Total amount of data read: "); WriteB(AosBoot.MulH(blocksRead, disk.device.blockSize), info); info.Ln;
		END WriteSummary;
		
		PROCEDURE PerformStep;
		VAR pos, num, res, expected, found, foundAt : LONGINT; string, nbr : ARRAY 128 OF CHAR;
		BEGIN
			num := random.Dice(maxNbrOfSectors) + 1;
			IF maxNbrOfSectors > 1 THEN testedSectors[num - 1] := TRUE; END;
			pos := start + random.Dice(size - num);
			disk.device.Transfer(AosDisks.Read, pos, num, buffer^, offset, res);
			IF res # AosDisks.Ok THEN
				ReportError(Lib.GetTransferError(disk.device, AosDisks.Write, pos, res)); 
			ELSE
				blocksRead := AosBoot.AddH(blocksRead, num);
				IF  testData & ~TestDataIsCorrect(offset, num, disk.device.blockSize, buffer^, expected, found, foundAt) THEN
					string := "Data Verification failed (Pos: "; Utilities.IntToStr(pos, nbr); Utilities.Append(string, nbr);
					Utilities.Append(string, ", Num: "); Utilities.IntToStr(num, nbr); Utilities.Append(string, nbr);
					Utilities.Append(string, ", Offset: "); Utilities.IntToStr(offset, nbr); Utilities.Append(string, nbr);
					Utilities.Append(string, ": ");
					Utilities.Append(string, "Expected value: "); Utilities.IntToStr(expected, nbr); Utilities.Append(string, nbr);
					Utilities.Append(string, ", found value: "); Utilities.IntToStr(found, nbr); Utilities.Append(string, nbr);
					Utilities.Append(string, " at index: "); Utilities.IntToStr(foundAt, nbr); Utilities.Append(string, nbr);
					Utilities.Append(string, ")"); 
					ReportError(string);
				END;
			END;
		END PerformStep;
		
		PROCEDURE DoOperation*;
		BEGIN			
			start := disk.table[partition].start; size := disk.table[partition].size;
			NEW(buffer, maxNbrOfSectors * disk.device.blockSize + maxOffset);
			WriteTestSettings;
			IF nbrOfTests > 0 THEN SetStatus(state.status, "Testing...", 0, 0, nbrOfTests, TRUE);
			ELSE SetStatus(state.status, "Testing (loop mode)...", 0, 0, 0, FALSE);
			END;
			IF maxOffset > 0 THEN NEW(testedOffsets, maxOffset + 1); END;
			IF maxNbrOfSectors > 1 THEN NEW(testedSectors, maxNbrOfSectors); END;
			testCount := 0; offset := 0;
			LOOP
				IF ~alive THEN EXIT END;
				IF nbrOfTests > 0 THEN
					SetCurrentProgress(testCount);
					IF testCount >= nbrOfTests THEN EXIT; END;
				END;
				PerformStep;
				IF maxOffset > 0 THEN testedOffsets[offset] := TRUE; offset := (offset + 1) MOD (maxOffset + 1); END;
				INC(testCount);
			END;
			WriteSummary;
			IF alive THEN
				result.String("Finished testing partition "); result.String(diskpartString); result.String(" - ");
				IF state.errorCount = 0 THEN result.String("No "); END;
				result.String("Errors found"); 
			END;
		END DoOperation;
		
		PROCEDURE &Init(disk :Lib.Disk; partition : LONGINT; log : BOOLEAN);
		BEGIN
			Init^(disk, partition, log);
			name := "DiskTester"; desc := "Perform disk test"; locktype := Lib.ReaderLock;
			NEW(random); random.InitSeed(AosKernel.GetTimer());
		END Init;		
		
	END DiskTest;	

PROCEDURE TestDataIsCorrect*(offset, numblocks, blocksize : LONGINT; VAR buffer : ARRAY OF CHAR; VAR expected, found, foundAt : LONGINT) : BOOLEAN;
VAR i : LONGINT;
BEGIN
	ASSERT(LEN(buffer) >= numblocks * blocksize + offset);
	ASSERT(blocksize MOD 256 = 0); (* Otherwise test data used will not work *)
	FOR i := 0 TO numblocks * blocksize - 1 DO
		IF ORD(buffer[i + offset]) # i MOD 256 THEN
			expected := i MOD 256; found := ORD(buffer[i + offset]); foundAt := i;
			RETURN FALSE;
		END;
	END;
	RETURN TRUE;
END TestDataIsCorrect;

(** Fill partition with test data *)
PROCEDURE WriteTestData*(parameter : PTR) : PTR; (** dev#part ~ *)
VAR selection : Lib.Selection; r : AosIO.StringReader; w : AosIO.StringWriter; testDataWriter : TestDataWriter;
BEGIN
	IF AosPartitions.GetSelection(parameter, FALSE, w, r, selection) THEN 
		NEW(testDataWriter, selection.disk, selection.partition, TRUE);
		testDataWriter.SetParameters(1);
		testDataWriter.SetStart;
	ELSE (* skip; error written to <w> by ScanOpenPart *)
	END;
	RETURN NIL;
END WriteTestData;

(** Fill partition with test data *)
PROCEDURE VerifyTestData*(parameter : PTR) : PTR; (** dev#part ~ *)
VAR selection : Lib.Selection; r : AosIO.StringReader; w : AosIO.StringWriter; testDataChecker : TestDataChecker;
BEGIN
	IF AosPartitions.GetSelection(parameter, FALSE, w, r, selection) THEN 
		NEW(testDataChecker, selection.disk, selection.partition, TRUE);
		testDataChecker.SetParameters(1);
		testDataChecker.SetStart;
	ELSE (* skip; error written to <w> by ScanOpenPart *)
	END;
	RETURN NIL;
END VerifyTestData;

(** Fill partition with zeros *)
PROCEDURE WriteZeros*(parameter : PTR) : PTR; (** dev#part ~ *)
VAR selection : Lib.Selection; r : AosIO.StringReader; w : AosIO.StringWriter; zeroWriter : ZeroWriter;
BEGIN
	IF AosPartitions.GetSelection(parameter, FALSE, w, r, selection) THEN 
		NEW(zeroWriter, selection.disk, selection.partition, TRUE);
		zeroWriter.SetParameters(1);
		zeroWriter.SetStart;
	ELSE (* skip; error written to <w> by ScanOpenPart *)
	END;
	RETURN NIL;
END WriteZeros;

(** Test the specified partition *)
PROCEDURE Test*(parameter : PTR) : PTR; (** dev#part ~ *)
VAR selection : Lib.Selection; r : AosIO.StringReader; w : AosIO.StringWriter; diskTest : DiskTest;
BEGIN
	IF AosPartitions.GetSelection(parameter, FALSE, w, r, selection) THEN 
		NEW(diskTest, selection.disk, selection.partition, TRUE);
		diskTest.SetParameters(TRUE, FALSE, FALSE, 100, 100, 0);
		diskTest.SetStart;
	ELSE (* skip; error written to <w> by ScanOpenPart *)
	END;
	RETURN NIL;
END Test;

(** Read/write the specified number of sectors from/to the specified paritition starting at the specified sector *)
PROCEDURE TransferBlocks*(par : ANY) : ANY; (** dev#part "READ"|"WRITE" block numblocks ~ *)
VAR 
	selection : Lib.Selection; r : AosIO.StringReader; w : AosIO.StringWriter;
	string : ARRAY 32 OF CHAR; dev : AosDisks.Device;
	op, block, numblocks, res : LONGINT;
	buffer : POINTER TO ARRAY OF CHAR;
BEGIN
	IF AosPartitions.GetSelection(par, FALSE, w, r, selection) THEN
		r.SkipWhitespace; r.String(string);
		IF string = "READ" THEN op := AosDisks.Read;
		ELSIF string = "WRITE" THEN op := AosDisks.Write;
		ELSE AosOut.String("AosDiskTests: Expected READ|WRITE parameter."); AosOut.Ln; RETURN NIL;
		END;
	
		r.SkipWhitespace; r.Int(block, FALSE);
		IF (r.res # AosIO.Ok) OR (block < 0) THEN AosOut.String("AosDiskTests: Expected block parameter."); AosOut.Ln; RETURN NIL; END;
	
		r.SkipWhitespace; r.Int(numblocks, FALSE);
		IF (r.res # AosIO.Ok) OR (block < 0) THEN AosOut.String("AosDiskTests: Expected numblocks parameter."); AosOut.Ln; RETURN NIL; END;
	
		dev := selection.disk.device;
		AosOut.String("AosDiskTests: "); 
		IF op = AosDisks.Read THEN AosOut.String("Reading "); ELSE AosOut.String(" Writing "); END;
		AosOut.Int(numblocks, 0); AosOut.String(" blocks at offset "); AosOut.Int(block, 0); 
		IF op = AosDisks.Read THEN AosOut.String(" from "); ELSE AosOut.String(" to "); END;
		AosOut.String(" partition "); AosOut.String(dev.name); AosOut.String("#"); AosOut.Int(selection.partition, 0); AosOut.String("... ");
		dev.Open(res);
		IF res = AosDisks.Ok THEN 
			IF dev.table[selection.partition].size - block < numblocks THEN
				AosOut.String("AosDiskTests: Numblocks too big. Would cross partition. Aborting test."); AosOut.Ln; 
			ELSE
				NEW(buffer, numblocks * dev.blockSize);
				dev.Transfer(op, block, numblocks, buffer^, 0, res); 
				ShowDiskres(res); AosOut.Ln;
			END;
			dev.Close(res); (* ignore res *)
		ELSE AosOut.String("AosDiskTests: Could not open device "); AosOut.String(dev.name); AosOut.String(": "); ShowDiskres(res); AosOut.Ln;
		END;
	ELSE AosOut.String("AosDiskTests: TransferBlocks: Device not found."); AosOut.Ln;
	END;
	RETURN NIL
END TransferBlocks;

PROCEDURE ShowDiskres(res : LONGINT);
BEGIN
	IF res = AosDisks.Ok THEN AosOut.String("Ok");
	ELSIF res = AosDisks.MediaChanged THEN AosOut.String("MediaChanged"); 
	ELSIF res = AosDisks.WriteProtected THEN AosOut.String("WriteProtected");
	ELSIF res = AosDisks.Unsupported THEN AosOut.String("Unsupported");
	ELSIF res = AosDisks.DeviceInUse THEN AosOut.String("DeviceInUse"); 
	ELSIF res = AosDisks.MediaMissing THEN AosOut.String("MediaMissing"); 
	ELSE AosOut.String("Unknown (res: "); AosOut.Int(res, 0); AosOut.String(")");
	END;
END ShowDiskres;

END AosDiskTests.

AosDiskTests.WriteTestData USB0#1 ~  S.Free AosDiskTests ~
AosDiskTests.VerifyTestData USB0#1 ~

AosDiskTests.Test USB0#1 ~

AosDiskTests.TransferBlocks USB0#1 READ 0 6 ~

AosUsbInfo.TraceOn Custom~

AosUsbInfo.TraceNone ~

AosPartitions.ShowOps ~
AosPartitions.ShowOps detail ~

AosPartitions.Abort 1 ~
