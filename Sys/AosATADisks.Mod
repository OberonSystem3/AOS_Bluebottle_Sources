MODULE AosATADisks; (** AUTHOR: "ml"; PURPOSE: "ATA/ATAPI disk driver"; *)
(* 
 * Version based on AosDisks and AosATADisks
 *
 * Aos ATA/ATAPI-6 disk driver with Busmaster suppport.
 *
 * Boot string parameters:
 *
 *	ATADetect:
 *
 *		Default			-> Searches for PCI devices with classcodes for IDE, SATA
 *		"legacy" 		-> Uses controller at addrss 1F0 and 170. No busmaster support.
 *		"default" 		-> Searches for PCI devices with spezial vendor and device ID
 *		"raid"			-> Searches for PCI devices with classcodes for IDE, SATA, RAID
 *		"other"			-> Searches for PCI devices with classcodes for IDE, SATA, OTHER
 *		"raid+other"	-> Searches for PCI devices with classcodes for IDE, SATA, RAID, OTHER
 *
 *	ATAForcePIO: 	Forces PIO mode for ATA devices if set to "1"
 *	ATAPIForcePIO:	Forces PIO mode for ATAPI devices if set to "1"
 *
 *	ATATrace:		Enable particular trace options, e.g. ATATrace=5 enables TraceInit, ATATrace=012345 enables all trace options
 *					See TraceXXX constants below.
 *		
 *	dev=nodma		Disable DMA transfers for the specified device, e.g. IDE0=nodma
 *		
 * History:
 *
 *  	05.04.2006	Made trace options accessible using config strings (staubesv)
 *	02.06.2006	Adapted to CD recorder software
 *	26.03.2007	Added NnofReads, NnofWrites, NnofOthers and NnofErrors statistics (staubesv)
 *)

IMPORT SYSTEM, AosBoot, AosOut, AosMemory, AosModules, AosInterrupts, AosKernel, AosActive, AosPlugins, AosDisks, PCI;

CONST
	Name = "IDE";
	
	MaxControllers 	= 10;
	MaxDevicesC 		= 2;
	MaxDevices 		= MaxDevicesC*MaxControllers;
	MaxTries 			= 5;
	MaxTriesDMA		= 3;
	
	(* Enable compilation of trace/debug code? *)
	Trace = TRUE;
	
	(* Caution: If changing the constants value, adapt procedure GetOptions *)
	TraceCommands 	= {0};	(* trace commands *)
	TraceErrors			= {1};	(* show error details *)
	TraceAtapi			= {2};	(* trace atapi commands *)
	TraceSense			= {3};	(* show atapi sense results *)
	TraceBuffer			= {4};
	TraceInit			= {5};
	
	TryReset			= TRUE;
	InitDevices			= TRUE;		(* used for ATA-4 or older *)
	AllowManualEject	= TRUE;		(* Should manual media eject be allowed for devices that are open? *)

	SelectTimeout 		= 500;		(* ms *)
	IOTimeout* 		= 10000;	(* ms *)
	IdentifyTimeout 		= 2000;		(* ms *)
	ResetTimeout 		= 30000;	(* ms *)
	ATAPITimeout* 		= 5000;		(* ms *)
	
	BS 					= 512;
	DMABufferSize		= 256 * 2048;	(* 512 kB *)
	MaxPRD 			= 32;			(* <= 32 *)

	(* According "CF+ and CompactFlash Specification Version 1.4" by CompactFlash Association*)
	CompactFlashSignature = 848AH; (*CF*)
	PageSize = 4096;
	
	AtapiBit = 0; RemovableBit = 1; DMABit* = 2; LBABit = 3; RMSNBit = 4; Packet16Bit = 5; LBA48Bit = 6; FlushBit = 7;
	CompactFlash = 9; (*CF*)

	ATAPI_DirectAccess = 0; ATAPI_SequentialAccess = 1; ATAPI_Printer = 2; ATAPI_Processor = 3; ATAPI_WriteOnce = 4;
	ATAPI_CDRom = 5; ATAPI_Scanner = 6; ATAPI_OpticalMemory = 7; ATAPI_MediumChanger = 8; ATAPI_Communications = 9;
	
	Protocol_DMABit = 7; Protocol_No = {}; Protocol_NonData = {1}; Protocol_PIO = {2}; Protocol_PacketPIO* = {3}; Protocol_DeviceReset = {6};
	Protocol_DMA = Protocol_PIO + {Protocol_DMABit}; 
	Protocol_PacketDMA* = Protocol_PacketPIO + {Protocol_DMABit};

	Device_DEV = 4; Device_LBA = 6;
	Status_ERR = 0; Status_DRQ = 3; Status_DRDY = 6; Status_BSY = 7;
	Control_nIEN = 1; Control_SRST = 2;
	DMA_Start = 0; DMA_Read = 3; DMA_ERR = 1; DMA_IRQ = 2; DMA_Busy = 0;
	Ofs_Features = 1; Ofs_Error = 1; Ofs_Device = 6; Ofs_Status = 7; Ofs_Cmd = 7;
	Ofs_SectorCount = 2; Ofs_SectorNumber = 3; Ofs_CylinderLow = 4; Ofs_CylinderHigh = 5;
	Ofs_LBALow = 3; Ofs_LBAMid = 4; Ofs_LBAHigh = 5;
	Ofs_CountLow = 4; Ofs_CountHigh = 5;
	Ofs_AltStatus = 6; Ofs_Control = 6;
	Ofs_BMCmd = 0; Ofs_BMStatus = 2; Ofs_BMPRDT = 4;
	ATAPI_DMA* = 0;
	ATAPISig = 0EBX;
	Res_OK = 0; Res_Err = 1; Res_Timeout = 2;
	
	WriteAndVerify* = 3; (* AosDisks.Read = 1, AosDisks.Read = 2 *)
TYPE
	LoadMsg* = RECORD (AosDisks.Message) END;	(** load the media *)
	GetSenseMsg* = RECORD (AosDisks.Message) sense*, asc*, ascq*: LONGINT; fieldPointer*: ARRAY 3 OF CHAR; END;
	TestUnitReadyMsg* = RECORD (AosDisks.Message) enable*: BOOLEAN; END;
	WriteCacheMsg* = RECORD (AosDisks.Message) enable*: BOOLEAN; END;

	CHS = RECORD
		cyls, hds, spt: LONGINT
	END;
	
	ID* = RECORD
		type*: SET;
		ver, devtype: LONGINT;
		model: ARRAY 44 OF CHAR;
		dmamode, maxdmamode: LONGINT;
		majorVersion: LONGINT;
	END;
	
	PRDT = POINTER TO RECORD
		prd: ARRAY MaxPRD OF RECORD	(* aligned on 32-byte boundary, see Intel 290550-002 sec. 2.7.3 *)
			physAdr, size: LONGINT
		END
	END;
	
	Command = OBJECT
	VAR
		dev, cmd, bufAdr*, count*, size*, features: LONGINT;
		read*, buffered: BOOLEAN;
		protocol*: SET;
		prdtPhysAdr: LONGINT;
		prdt: PRDT;
		getResult: BOOLEAN;
	END Command;

	CommandCHS = OBJECT(Command)
	VAR
		sector, head, cylinder: LONGINT;
	END CommandCHS;

	CommandLBA = OBJECT(Command)
	VAR
		lba: LONGINT;
	END CommandLBA;

	CommandLBA48 = OBJECT(Command)
	VAR
		lbaHigh, lbaLow: LONGINT;
	END CommandLBA48;

	CommandPacket* = OBJECT(Command)
	VAR
		packet*: Packet;
		features*: SET;
		sense, packetLen: LONGINT;
	END CommandPacket;

	Packet = ARRAY 16 OF CHAR;
		
TYPE

	Interrupt = OBJECT
	VAR
		int: LONGINT;
		interrupt, timeout: BOOLEAN;
		clock: AosActive.Timer;
	
		PROCEDURE HandleInterrupt;
		BEGIN {EXCLUSIVE}
			interrupt := TRUE;
			INC(irqCount);
		END HandleInterrupt;
		
		PROCEDURE HandleTimeout;
		BEGIN {EXCLUSIVE}
			timeout := TRUE;
		END HandleTimeout;
		
		PROCEDURE Wait(ms: LONGINT): BOOLEAN;
		BEGIN {EXCLUSIVE}
			timeout := FALSE;
			AosActive.SetTimeout(clock, SELF.HandleTimeout, ms); (* set or reset timeout *)
			AWAIT(interrupt OR timeout);
			AosActive.CancelTimeout(clock);
			INC(expectedCount);
			interrupt := FALSE;
			RETURN ~timeout
		END Wait;
		
		PROCEDURE Reset;
		BEGIN
			interrupt := FALSE
		END Reset;
		
		PROCEDURE &Init(irq: LONGINT);
		BEGIN
			interrupt := FALSE; int := AosInterrupts.IRQ0 + irq;
			NEW(clock);
			AosActive.InstallHandler(SELF.HandleInterrupt, int)
		END Init;
		
		PROCEDURE Finalize();
		BEGIN
			AosActive.RemoveHandler(HandleInterrupt, int);
			AosActive.CancelTimeout(clock);
		END Finalize;
		
	END Interrupt;

	Controller = OBJECT
	VAR
		cmdbase, cnlbase, bmbase, irq: LONGINT;
		interrupt: Interrupt;
		ctrlID, state: LONGINT;
		nIEN: LONGINT;
		prdtPhysAdr: LONGINT;
		prdt: PRDT;
		buffer: POINTER TO ARRAY OF CHAR;
		bufferAdr: LONGINT;
          	
		PROCEDURE ExecuteCommand*(command: Command; ms: LONGINT; VAR status: SET): LONGINT;
		CONST
			PIO = SYSTEM.VAL(LONGINT, Protocol_PIO);
			DMA = SYSTEM.VAL(LONGINT, Protocol_DMA);
			PacketPIO = SYSTEM.VAL(LONGINT, Protocol_PacketPIO);
			PacketDMA = SYSTEM.VAL(LONGINT, Protocol_PacketDMA);
			DeviceReset = SYSTEM.VAL(LONGINT, Protocol_DeviceReset);
			NonData = SYSTEM.VAL(LONGINT, Protocol_NonData);
		VAR
			res: LONGINT;
			ch: CHAR;
			dma: BOOLEAN;
		BEGIN {EXCLUSIVE}
			IF state = 1 THEN
				SYSTEM.PORTIN(cmdbase+Ofs_Status, ch); status := SYSTEM.VAL(SET, LONG(ORD(ch)));
				IF ~(Status_BSY IN status) THEN
					state := 0;
				ELSE
					RETURN Res_Err;
				END;
			END;
		
			dma := Protocol_DMABit IN command.protocol;
			
			IF Trace & (trace * TraceCommands # {}) THEN
				AosOut.String(Name); AosOut.Int(ctrlID*MaxDevicesC + command.dev, 1);
				AosOut.String(" Issue: "); AosOut.Hex(command.cmd, -3);
				IF command IS CommandPacket THEN
					AosOut.String(", "); AosOut.Hex(ORD(command(CommandPacket).packet[0]), -2);
				END;
				AosOut.Ln;
			END;
			IF interrupt # NIL THEN
				interrupt.Reset;
			END;
			res := ProtIssueCommand(command, ms);
			IF res # Res_OK THEN
				(*IF dma THEN
					StopDMA();
				END;*)
				SYSTEM.PORTIN(cmdbase+Ofs_Status, ch); status := SYSTEM.VAL(SET, LONG(ch));
				IF Trace & (trace * TraceErrors # {}) THEN
					AosOut.String(Name); AosOut.Int(ctrlID*MaxDevicesC + command.dev, 1);
					AosOut.String(" Error (issue): Command "); AosOut.Hex(command.cmd, -2);
					IF command IS CommandPacket THEN
						AosOut.String(", "); AosOut.Hex(ORD(command(CommandPacket).packet[0]), -2);
					END;
					AosOut.String(", Status = "); AosOut.Hex(ORD(ch), -2); AosOut.Ln;
				END;
				(*IF status * {Status_BSY, Status_DRQ} # {} THEN
					ignore := ProtSwReset(ResetTimeout);
				END;*)
				RETURN res;
			END;
			IF dma THEN
				res := SetupDMA(command);
				IF res # Res_OK THEN RETURN res; END;
				StartDMA();
			END;			
			CASE SYSTEM.VAL(LONGINT, command.protocol) OF
			| NonData:		res := ProtNonData(ms, status);
			| PIO:			IF command.read THEN res := ProtPIOIn(command.bufAdr, command.count, ms, status);
							ELSE res := ProtPIOOut(command.bufAdr, command.count, ms, status); END;
			| DMA:			res := ProtDMA(ms, status);
			| DeviceReset:	res := ProtDeviceReset(ms, status);
			| PacketPIO:	res := ProtPacketPIO(command(CommandPacket), command.read, command.bufAdr, command.size, ms, status);
			| PacketDMA:	res := ProtPacketDMA(command(CommandPacket), ms, status);
			ELSE
				Show("Error invalid protocol"); AosOut.Int(res, 0); AosOut.Ln;
			END;
			IF dma THEN
				StopDMA();
			END;
			IF command.getResult THEN
				Show("Returning results not yet implemented"); AosOut.Ln;
				HALT(AosDisks.Unsupported);
			END;
			IF res # Res_OK THEN
				SYSTEM.PORTIN(cmdbase+Ofs_Status, ch); status := SYSTEM.VAL(SET, LONG(ch));
				IF Trace & (trace * TraceErrors # {}) THEN
					AosOut.String(Name); AosOut.Int(ctrlID*MaxDevicesC + command.dev, 1);
					AosOut.String(" Error (protocol): Command "); AosOut.Hex(command.cmd, -2);
					IF command IS CommandPacket THEN
						AosOut.String(", "); AosOut.Hex(ORD(command(CommandPacket).packet[0]), -2);
					END;
					AosOut.String(", Protocol = "); AosOut.Hex(SYSTEM.VAL(LONGINT, command.protocol), -2);
					AosOut.String(", Result = ");AosOut.Int(res, 0);
					AosOut.String(", Status = "); AosOut.Hex(ORD(ch), -2);
					IF Status_ERR IN status THEN
						SYSTEM.PORTIN(cmdbase+Ofs_Error, ch);
						AosOut.String(", Error = "); AosOut.Hex(ORD(ch), -2);
					END;
					AosOut.Ln;
				END;
				(*IF status * {Status_BSY, Status_DRQ} # {} THEN
					ignore := ProtSwReset(ResetTimeout);
				END;*)
			END;
			
			IF command.buffered THEN
				SYSTEM.MOVE(bufferAdr, command.bufAdr, command.size);
			END;
			RETURN res;
		END ExecuteCommand;
		
		PROCEDURE Reset(): LONGINT;
		BEGIN {EXCLUSIVE}
			RETURN ProtSwReset(ResetTimeout);
		END Reset;
		
		PROCEDURE SetupPRD(command: Command): LONGINT;
		VAR
			i, bufAdr, physAdr, size, left, tmp: LONGINT;
		BEGIN
			IF Trace & (trace * TraceBuffer # {}) THEN
				AosOut.String("bufAdr = "); AosOut.Hex(command.bufAdr, 0);
				IF ~GetPhysAdr(command.bufAdr, command.size, tmp) THEN
					AosOut.String(", Split buffer");
				END;
				AosOut.Ln;
			END;
		
			(* create prdt *)
			command.prdt := prdt;
			command.prdtPhysAdr := prdtPhysAdr;
			(*IF ~GetPRDAdr(command) THEN AosOut.String("Create PRD failed (GetPRDAdr)"); AosOut.Ln; RETURN Res_Err; END;*)

			IF ODD(command.bufAdr) THEN
				command.buffered := TRUE;
				bufAdr := bufferAdr;
			ELSE
				bufAdr := command.bufAdr;
			END;
			size := command.size;
			i := 0;
			LOOP
				IF Trace & (trace * TraceBuffer # {}) THEN AosOut.String("    "); AosOut.Hex(bufAdr, 0); END;
				IF ~GetPhysAdr(bufAdr, 1, physAdr) THEN Show("Setup PRD failed (GetPhysAdr)"); AosOut.Ln; RETURN Res_Err; END;
				command.prdt.prd[i].physAdr := physAdr;
				IF Trace & (trace * TraceBuffer # {}) THEN AosOut.String(", "); AosOut.Hex(physAdr, 0); END;
				left := 65536 - physAdr MOD 65536;	(* should not cross 64k boundary (sec. 3.5.3) *)
				IF Trace & (trace * TraceBuffer # {})THEN AosOut.String(", ("); AosOut.Hex(left, 0); END;
				
				(* Calculate the max. contiguous physical memory *)
				WHILE ~GetPhysAdr(bufAdr, left, tmp) & (left > 0) DO
					(*left := (left-1) - ((left-1) MOD PageSize);*)
					DEC(left, PageSize);
					IF Trace & (trace * TraceBuffer # {})THEN AosOut.String(", "); AosOut.Hex(left, 0); END;
				END;
				IF Trace & (trace * TraceBuffer # {})THEN
					IF GetPhysAdr(bufAdr, left+1, tmp) THEN
						AosOut.String("+");
					END;
					AosOut.String("), "); AosOut.Hex(left, 0);
				END;
				IF (left = 0) & (size > 0) THEN Show("Setup PRD failed"); AosOut.Ln; RETURN Res_Err; END;
				IF left > size THEN left := size END;
				IF Trace & (trace * TraceBuffer # {})THEN AosOut.String(", "); AosOut.Hex(left, 0); AosOut.Ln; END;
				DEC(size, left);
				IF size = 0 THEN
					command.prdt.prd[i].size := 80000000H + left; (* end marker *)
					EXIT
				END;
				command.prdt.prd[i].size := left;
				INC(bufAdr, left);
				INC(physAdr, left); INC(i);
				IF i = LEN(command.prdt.prd) THEN Show("Setup PRD failed (out of bounds)"); AosOut.Ln; RETURN Res_Err; END;
			END;
			RETURN Res_OK;
		END SetupPRD;
		
		PROCEDURE SetupDMA(command: Command): LONGINT;
		VAR
			ch: CHAR;
			s: SET;
			res: LONGINT;
		BEGIN
			(* Clear Interrupt & Errror *)
			SYSTEM.PORTIN(bmbase + Ofs_BMStatus, ch); s := SYSTEM.VAL(SET, LONG(ORD(ch)));
			s := s * {1..7};
			SYSTEM.PORTOUT(bmbase + Ofs_BMStatus, CHR(SYSTEM.VAL(LONGINT, s)));

			res := SetupPRD(command);
			IF res # Res_OK THEN RETURN res; END;
		
			(* Write address of PRDT *)
			SYSTEM.PORTOUT(bmbase + Ofs_BMPRDT, command.prdtPhysAdr);
		
			(* Set direction *)
			IF command.read THEN
				ch := CHR(ASH(1, DMA_Read));
			ELSE
				ch := 0X;
			END;
			SYSTEM.PORTOUT(bmbase + Ofs_BMCmd, ch);
			RETURN Res_OK;
		END SetupDMA;
		
		PROCEDURE StartDMA();
		VAR ch: CHAR; s: SET;
		BEGIN
			(* START DMA *)
			SYSTEM.PORTIN(bmbase + Ofs_BMCmd, ch);
			s := SYSTEM.VAL(SET, LONG(ch));
			INCL(s, DMA_Start);
			SYSTEM.PORTOUT(bmbase + Ofs_BMCmd, CHR(SYSTEM.VAL(LONGINT, s)));
		END StartDMA;
		
		PROCEDURE StopDMA();
		VAR ch: CHAR; s: SET;
		BEGIN
			(* Stop DMA *)
			SYSTEM.PORTIN(bmbase + Ofs_BMCmd, ch);
			s := SYSTEM.VAL(SET, LONG(ch));
			EXCL(s, DMA_Start);
			SYSTEM.PORTOUT(bmbase + Ofs_BMCmd, CHR(SYSTEM.VAL(LONGINT, s)));
			
			(* Clear Interrupt & Errror *)
			SYSTEM.PORTIN(bmbase + Ofs_BMStatus, ch); s := SYSTEM.VAL(SET, LONG(ORD(ch)));
			s := s * {1..7};
			SYSTEM.PORTOUT(bmbase + Ofs_BMStatus, CHR(SYSTEM.VAL(LONGINT, s)));
		END StopDMA;
		
		PROCEDURE WaitStatus(mask, expect, bad: SET; ms: LONGINT; VAR status: SET): LONGINT;
		VAR t: AosKernel.MilliTimer; ch: CHAR;
		BEGIN
			ASSERT(Status_BSY IN mask);
			AosKernel.SetTimer(t, ms);
			LOOP
				SYSTEM.PORTIN(cmdbase+Ofs_Status, ch); status := SYSTEM.VAL(SET, LONG(ORD(ch)));
				IF ~(Status_BSY IN status) THEN
					IF status * mask = expect THEN EXIT; END;
				END;
				IF AosKernel.Expired(t) THEN RETURN Res_Timeout; END;
			END;
			IF status * bad # {} THEN RETURN Res_Err; END;
			RETURN Res_OK;
		END WaitStatus;
		
		(*	Software reset protocol 
			States: HSR0(ISet_SRST), HSR1 (Clear_wait), HSR2 (Check_Status) *)
		PROCEDURE ProtSwReset(ms: LONGINT): LONGINT;
		VAR
			t: AosKernel.MilliTimer;
			status: SET;
			res: LONGINT;
		BEGIN
			IF state = 1 THEN RETURN Res_Err; END;
			(* HSR0 *)
			SYSTEM.PORTOUT(cnlbase+Ofs_Control, CHR(ASH(1, Control_SRST))); (* reset controller *)
			AosKernel.SetTimer(t, 1); REPEAT UNTIL AosKernel.Expired(t);	(* wait > 4.8us *)
			(* HSR1 *)
			SYSTEM.PORTOUT(cnlbase+Ofs_Control, 0);
			AosKernel.SetTimer(t, 3); REPEAT UNTIL AosKernel.Expired(t);	(* wait ~2ms *)
			(* HSR0 *)
			res := WaitStatus({Status_BSY}, {}, {Status_ERR}, ms, status);
			IF res # Res_OK THEN state := 1; END;
			RETURN res;
		END ProtSwReset;
		
		(*	Bus idle protocol 
			States: HI0(Host_Idle), HI1 (Check_Status), HI2 (Device_Select), HI3 (Write_parameters), HI4(Write_command) *)
		PROCEDURE ProtIssueCommand(cmd: Command; ms: LONGINT): LONGINT;
		VAR
			cmdCHS: CommandCHS;
			cmdLBA: CommandLBA;
			cmdLBA48: CommandLBA48;
			cmdPacket: CommandPacket;
			ch: CHAR;
			status, devReg: SET;
			res: LONGINT;
		BEGIN
			(* HI1 *)
			res := WaitStatus({Status_BSY, Status_DRQ}, {}, {}, ms, status);
			(*res := WaitStatus({Status_BSY}, {}, {}, ms, status);*)
			(*IF res # Res_OK THEN RETURN res; END;*)
			res := Res_OK;
			IF cmd.dev = 1 THEN devReg := {Device_DEV} ELSE devReg := {}; END;
			SYSTEM.PORTIN(cmdbase+Ofs_Device, ch);
			(* Change device? *)
			IF ((SYSTEM.VAL(SET, LONG(ch)) * {Device_DEV}) # devReg)
			(* OR (Status_BSY IN status)*) THEN
				IF Trace & (trace * TraceCommands # {}) THEN
					AosOut.String(Name); AosOut.Int(ctrlID*MaxDevicesC + cmd.dev, 1);
					AosOut.String(" Select device"); AosOut.Ln;
				END;
				SetInterrupt(FALSE);
				(* HI2 *)	
				SYSTEM.PORTOUT(cmdbase+Ofs_Device, CHR(SYSTEM.VAL(LONGINT, devReg)));
				(* HI1 *)
				res := WaitStatus({Status_BSY, Status_DRQ}, {}, {}, SelectTimeout, status);
				IF res # Res_OK THEN RETURN res; END;
				SetInterrupt(TRUE);
			END;
			(* HI3 *)
			IF cmd IS CommandCHS THEN
				cmdCHS := cmd(CommandCHS);
				SYSTEM.PORTOUT(cmdbase+Ofs_Features, CHR(cmdCHS.features));
				SYSTEM.PORTOUT(cmdbase+Ofs_SectorCount, CHR(cmdCHS.count));
				SYSTEM.PORTOUT(cmdbase+Ofs_SectorNumber, CHR(cmdCHS.sector));
				SYSTEM.PORTOUT(cmdbase+Ofs_CylinderLow, CHR(cmdCHS.cylinder MOD 100H));
				SYSTEM.PORTOUT(cmdbase+Ofs_CylinderHigh, CHR(cmdCHS.cylinder DIV 100H));
				devReg := devReg + SYSTEM.VAL(SET, cmdCHS.head MOD 10H);
				SYSTEM.PORTOUT(cmdbase+Ofs_Device, CHR(SYSTEM.VAL(LONGINT, devReg)));
			ELSIF cmd IS CommandLBA THEN
				cmdLBA := cmd(CommandLBA);
				SYSTEM.PORTOUT(cmdbase+Ofs_Features, CHR(cmdLBA.features));
				SYSTEM.PORTOUT(cmdbase+Ofs_SectorCount, CHR(cmdLBA.count));
				SYSTEM.PORTOUT(cmdbase+Ofs_LBALow, CHR(cmdLBA.lba MOD 100H));
				SYSTEM.PORTOUT(cmdbase+Ofs_LBAMid, CHR((ASH(cmdLBA.lba, -8) MOD 100H)));
				SYSTEM.PORTOUT(cmdbase+Ofs_LBAHigh, CHR((ASH(cmdLBA.lba, -16) MOD 100H)));
				INCL(devReg, Device_LBA);
				devReg := devReg + SYSTEM.VAL(SET, ASH(cmdLBA.lba, -24) MOD 10H);
				SYSTEM.PORTOUT(cmdbase+Ofs_Device, CHR(SYSTEM.VAL(LONGINT, devReg)));
			ELSIF cmd IS CommandLBA48 THEN
				cmdLBA48 := cmd(CommandLBA48);
				(* Previous *)
				SYSTEM.PORTOUT(cmdbase+Ofs_SectorCount, CHR(ASH(cmdLBA48.count, -8) MOD 100H));
				SYSTEM.PORTOUT(cmdbase+Ofs_LBALow, CHR((ASH(cmdLBA48.lbaLow, -24) MOD 100H)));
				SYSTEM.PORTOUT(cmdbase+Ofs_LBAMid, CHR((cmdLBA48.lbaHigh MOD 100H)));
				SYSTEM.PORTOUT(cmdbase+Ofs_LBAHigh, CHR((ASH(cmdLBA48.lbaHigh, -8) MOD 100H)));
				(* Current *)
				SYSTEM.PORTOUT(cmdbase+Ofs_SectorCount, CHR(cmdLBA48.count));
				SYSTEM.PORTOUT(cmdbase+Ofs_LBALow, CHR(cmdLBA48.lbaLow MOD 100H));
				SYSTEM.PORTOUT(cmdbase+Ofs_LBAMid, CHR((ASH(cmdLBA48.lbaLow, -8) MOD 100H)));
				SYSTEM.PORTOUT(cmdbase+Ofs_LBAHigh, CHR((ASH(cmdLBA48.lbaLow, -16) MOD 100H)));
				INCL(devReg, Device_LBA);
				SYSTEM.PORTOUT(cmdbase+Ofs_Device, CHR(SYSTEM.VAL(LONGINT, devReg)));
			ELSIF cmd IS CommandPacket THEN
				cmdPacket := cmd(CommandPacket);
				SYSTEM.PORTOUT(cmdbase+Ofs_Features, CHR(SYSTEM.VAL(LONGINT, cmdPacket.features)));	(* OVL, DMA *)
				SYSTEM.PORTOUT(cmdbase+Ofs_SectorCount, 0X);	(* tag 0 *)
				SYSTEM.PORTOUT(cmdbase+Ofs_CountLow, 0FEX);	(* byte count limit *)
				SYSTEM.PORTOUT(cmdbase+Ofs_CountHigh, 0FFX);
				SYSTEM.PORTOUT(cmdbase+Ofs_Device, CHR(SYSTEM.VAL(LONGINT, devReg)));
			END;
			
			(* HI4 *)
			SYSTEM.PORTOUT(cmdbase+Ofs_Cmd, CHR(cmd.cmd));
			RETURN res;
		END ProtIssueCommand;
		
		(*	Non-data protocol 
			States: HND0 (INTRQ_wait), HND1 (Check_Status) *)
		PROCEDURE ProtNonData(ms: LONGINT; VAR status: SET): LONGINT;
		BEGIN
			IF nIEN = 0 THEN
				(* HND0 *);
				IF ~interrupt.Wait(ms) THEN RETURN Res_Timeout; END;
			ELSE
				(* Wait 400ns when entering HND1 form state other than HND0 *)	
				NanoDelay(400);
			END;
			(* HND1 *);
			RETURN WaitStatus({Status_BSY}, {}, {Status_ERR}, ms, status);
		END ProtNonData;
		
		(*	PIO data-in protocol 
			States: HPIOI0 (INTRQ_wait), HPIOI1 (Check_Status), HPIOI2 (Transfer_Data) *)
		PROCEDURE ProtPIOIn(bufAdr, num: LONGINT; ms: LONGINT; VAR status: SET): LONGINT;
		VAR state, res: LONGINT; ch: CHAR;
		BEGIN
			res := Res_OK;
			IF nIEN = 1 THEN
				state := 1;
				(* Wait 400ns when entering HPIOI1 *)	
				NanoDelay(400);
			END;
			
			REPEAT
				CASE state OF
				(* HPIOI0 *)
				| 0: BEGIN
						IF ~interrupt.Wait(ms) THEN RETURN Res_Timeout; END;
						state := 1;
					END;
				(* HPIOI1 *)
				| 1: BEGIN
						res := WaitStatus({Status_BSY}, {}, {Status_ERR}, ms, status);
						IF res # Res_OK THEN RETURN res; END;
						IF Status_DRQ IN status THEN
							state:= 2;
						ELSE
							RETURN Res_Err;
						END;
					END;
				(* HPIOI2 *)
				| 2: BEGIN
						RepInWord(cmdbase, bufAdr, BS DIV 2);
						INC(bufAdr, BS); DEC(num);
						IF num <= 0 THEN
							SYSTEM.PORTIN(cmdbase+Ofs_Status, ch); status := SYSTEM.VAL(SET, LONG(ORD(ch)));
							IF Status_ERR IN status THEN res := Res_Err; END;
							state := -1;
						ELSIF nIEN = 0 THEN
							state := 0;
						ELSE
							state := 1;
							(* Wait 1 PIO transfer cycle when entering HPIOI1 from HPIOI2 *)	
							SYSTEM.PORTIN(cnlbase+Ofs_AltStatus, ch);
						END;
					END;
				END;
			UNTIL state = -1;
			RETURN res;
		END ProtPIOIn;
		
		(*	PIO data-out Protocol 
			States: HPIOO0 (Check_Status), HPIOO1 (Transfer_Data), HPIOO2 (INTRQ_wait) *)
		PROCEDURE ProtPIOOut(bufAdr, num: LONGINT; ms: LONGINT; VAR status: SET): LONGINT;
		VAR
			state, res: LONGINT;
			ch: CHAR;
		BEGIN
			state := 0;
			REPEAT
				CASE state OF
				(* HPIOO0 *)
				| 0: BEGIN
						res := WaitStatus({Status_BSY}, {}, {Status_ERR}, ms, status);
						IF res # Res_OK THEN RETURN res; END;
						IF Status_DRQ IN status THEN
							state:= 1;
						ELSE
							state := -1;
						END;
					END;
				(* HPIOO1 *)
				| 1: BEGIN
						RepOutWord(cmdbase, bufAdr, BS DIV 2);
						INC(bufAdr, BS); DEC(num);
						IF nIEN = 0 THEN
							state := 2;
						ELSE
							state := 0;
							(* Wait 1 PIO transfer cycle when entering HPIOI1 from HPIOI2 *)	
							SYSTEM.PORTIN(cnlbase+Ofs_AltStatus, ch);
						END;
					END;
				(* HPIOO2 *)
				| 2: BEGIN
						IF ~interrupt.Wait(ms) THEN RETURN Res_Timeout; END;
						state := 0;
					END;
				END;
			UNTIL state = -1;
			RETURN res;
		END ProtPIOOut;
		
		(*	DMA Protocol 
			States: HDMA0 (Check_Status), HDMA1 (Transfer_Data), HDMA2 (INTRQ_wait) *)
		PROCEDURE ProtDMA(ms: LONGINT; VAR status: SET): LONGINT;
		VAR
			ch: CHAR;
			t: AosKernel.MilliTimer;
			s: SET;
		BEGIN
			(* Wait 400ns when entering HDMA0 *)	
			NanoDelay(400);
			AosKernel.SetTimer(t, ms);
			REPEAT
				IF nIEN = 0 THEN
					IF ~interrupt.Wait(ms) THEN (*RETURN Res_Timeout;*) END;
				END;
				SYSTEM.PORTIN(bmbase + Ofs_BMStatus, ch); s := SYSTEM.VAL(SET, LONG(ch));
			(*UNTIL (s * {DMA_ERR, DMA_IRQ} # {}) OR AosKernel.Expired(t);*)
			UNTIL ~(DMA_Busy IN s) OR AosKernel.Expired(t);
			IF DMA_ERR IN s THEN RETURN Res_Err; END;
			(*IF AosKernel.Expired(t) THEN RETURN Res_Timeout; END;*)
			REPEAT
				SYSTEM.PORTIN(cmdbase+Ofs_Status, ch); status := SYSTEM.VAL(SET, LONG(ORD(ch)));
				IF ~(Status_BSY IN status) THEN
					IF Status_ERR IN status THEN RETURN Res_Err; END;
					IF ~(Status_DRQ IN status) THEN RETURN Res_OK; END;
				END;
				(* Wait 1 PIO transfer cycle when entering HDMA0 *)	
				SYSTEM.PORTIN(cnlbase+Ofs_AltStatus, ch);
			UNTIL AosKernel.Expired(t);
			RETURN Res_Timeout;
		END ProtDMA;
		
		(*	Packet PIO Protocol 
			States: HP0(Check_Status_A), HP1 (Send_Packet), HP2 (Check_Status_B), HP3 (INTRQ_wait), HP4 (Transfer_Data) *)
		PROCEDURE ProtPacketPIO(command: CommandPacket; read: BOOLEAN; bufAdr, size: LONGINT; ms: LONGINT; VAR status: SET): LONGINT;
		VAR
			res, count: LONGINT;
			ch: CHAR;
		BEGIN
			(* Wait 400ns *)	
			NanoDelay(400);
			(* HP0 *)
			res := WaitStatus({Status_BSY, Status_DRQ}, {Status_DRQ}, {Status_ERR}, ms, status);
			IF res # Res_OK THEN	RETURN res; END;
			(* HP1 *)
			RepOutWord(cmdbase, SYSTEM.ADR(command.packet[0]), command.packetLen DIV 2);
			IF nIEN = 0 THEN
				(* HP3 *)
				(*IF ~interrupt.Wait(ms) THEN RETURN Res_Timeout; END;*)
			ELSE
				(* Wait 1 PIO transfer cycle when entering HP2 from HP1 *)	
				SYSTEM.PORTIN(cnlbase+Ofs_AltStatus, ch);
			END;
			LOOP
				(* HP2 *)
				res := WaitStatus({Status_BSY}, {}, {Status_ERR}, ms, status);
				IF res # Res_OK THEN EXIT; END;
				IF ~(Status_DRQ IN status) THEN EXIT; END;
				IF size = 0 THEN EXIT; END;
				(* HP4 *)
				SYSTEM.PORTIN(cmdbase+Ofs_CountLow, ch);
				count := ORD(ch);
				SYSTEM.PORTIN(cmdbase+Ofs_CountHigh, ch);
				INC(count, ASH(ORD(ch), 8));
				IF count > size THEN count := size END;
				(* IF count <= 0 THEN AosOut.String("count <= 0, size = "); AosOut.Int(size, 0); AosOut.Ln; EXIT; END; *)
				IF read THEN
					RepInWord(cmdbase, bufAdr, count DIV 2);
				ELSE
					RepOutWord(cmdbase, bufAdr, count DIV 2);
				END;
				INC(bufAdr, count); DEC(size, count);
				IF nIEN = 0 THEN
					(* HP3 *)
					IF ~interrupt.Wait(ms) THEN RETURN Res_Timeout; END;
				END;		
			END;
			IF (res = Res_OK) & (size > 0) THEN res := Res_Err; END;
			RETURN res;
		END ProtPacketPIO;
		
		(*	Packet DMA Protocol 
			States: HPD0(Check_Status_A), HPD1 (Send_Packet), HPD2 (Check_Status_B), HPD3 (INTRQ_wait), HPD4 (Transfer_Data) *)
		PROCEDURE ProtPacketDMA(command: CommandPacket; ms: LONGINT; VAR status: SET): LONGINT;
		VAR
			res: LONGINT;
			ch: CHAR;
			s: SET;
			t: AosKernel.MilliTimer;
		BEGIN
			(* Wait 400ns *)	
			NanoDelay(400);
			(* HPD0 *)
			res := WaitStatus({Status_BSY, Status_DRQ}, {Status_DRQ}, {Status_ERR}, ms, status);
			IF res # Res_OK THEN RETURN res; END;
			(* HPD1 *)
			RepOutWord(cmdbase, SYSTEM.ADR(command.packet[0]), command.packetLen DIV 2);
			IF nIEN = 0 THEN
				(* HPD3 *)
				AosKernel.SetTimer(t, ms+2);
				REPEAT
					IF ~interrupt.Wait(ms) THEN (*AosOut.String("***");*) (*RETURN Res_Timeout;*) END;
					SYSTEM.PORTIN(bmbase + Ofs_BMStatus, ch); s := SYSTEM.VAL(SET, LONG(ch));
				UNTIL (s * {DMA_ERR, DMA_IRQ} # {}) OR AosKernel.Expired(t);
				(* UNTIL ~(DMA_Busy IN s) OR AosKernel.Expired(t); *)
				IF DMA_ERR IN s THEN RETURN Res_Err; END;
				IF AosKernel.Expired(t) THEN RETURN Res_Timeout; END;
			ELSE
				(* Wait 1 PIO transfer cycle when entering HPD2 from HPD1 *)	
				SYSTEM.PORTIN(cnlbase+Ofs_AltStatus, ch);
			END;
			(* HPD2 *)
			res := WaitStatus({Status_BSY, Status_DRQ}, {}, {Status_ERR}, ms, status);
			RETURN res;
		END ProtPacketDMA;
		
		(*	Device reset protocol 
			States: HDR0 (Wait), HDR1 (Check_Status) *)
		PROCEDURE ProtDeviceReset(ms: LONGINT; VAR status: SET): LONGINT;
		BEGIN
			(* HDR0 *);
			NanoDelay(400);
			(* HDR1 *);
			RETURN WaitStatus({Status_BSY}, {}, {Status_ERR}, ms, status);
		END ProtDeviceReset;
		
		PROCEDURE SetInterrupt(enable: BOOLEAN);
		VAR i : LONGINT;
		BEGIN
			(* Set nIEN *)
			IF enable & (interrupt # NIL) THEN nIEN := 0; ELSE nIEN := 1; END;
			i := ASH(nIEN, Control_nIEN);
			SYSTEM.PORTOUT(cnlbase+Ofs_Control, CHR(i));
		END SetInterrupt;
		
		PROCEDURE CreateDevice(devNum: LONGINT): LONGINT;
		VAR status: SET;
			res: LONGINT; dev, devATA: Device; devATAPI: DeviceATAPI; ch: CHAR;
			buf: ARRAY BS DIV 2 OF INTEGER;
			command: Command;
			devReg: SET;
			c1, c2: CHAR;
		BEGIN
			(* Select device *)
			IF devNum = 1 THEN devReg := {Device_DEV} ELSE devReg := {}; END;
			SYSTEM.PORTOUT(cmdbase+Ofs_Device, CHR(SYSTEM.VAL(LONGINT, devReg)));
			res := WaitStatus({Status_BSY, Status_DRQ}, {}, {}, SelectTimeout, status);
			IF res # Res_OK THEN 
				Show("Could not select device"); AosOut.Ln;
			END;

			(* Check if registers are valid. FAST DETECTION  *)
			SYSTEM.PORTOUT(cmdbase+Ofs_CountLow, 055X);
			NanoDelay(400);
			SYSTEM.PORTIN(cmdbase+Ofs_CountLow, c1);
			SYSTEM.PORTOUT(cmdbase+Ofs_CountLow, 0AAX);
			NanoDelay(400);
			SYSTEM.PORTIN(cmdbase+Ofs_CountLow, c2);
			IF (c1 # 055X) OR (c2 # 0AAX) THEN
				IF Trace & (trace * (TraceErrors + TraceInit) # {})  THEN
					AosOut.String(", device "); AosOut.Int(devNum, 0); AosOut.String(" not present"); 
					AosOut.String(" "); AosOut.Hex(ORD(c1), -2); AosOut.Hex(ORD(c2), -3);
				END;
				RETURN Res_Err;
			END;

			IF Trace & (trace * TraceInit # {})  THEN
				AosOut.String("Identify Device "); AosOut.Int(devNum,1); AosOut.Ln;
			END;
			NEW(command);
			command.dev := devNum; command.cmd := 0ECH; (* identify device *)
			command.protocol := Protocol_PIO; command.read := TRUE;
			command.bufAdr := SYSTEM.ADR(buf[0]); command.count := 1;
			res := ExecuteCommand(command, IdentifyTimeout, status);
			
			IF Trace & (trace * TraceInit # {}) THEN
				AosOut.Ln;
				Show("Identify device commands, res: "); AosOut.Int(res, 0); AosOut.String(", status: "); AosOut.Bits(status, 0, 32); 
				AosOut.Ln;
			END;
			
			(*IF ~(Status_DRDY IN status) THEN RETURN Res_Err; END;*)
			IF ~(Status_ERR IN status) THEN
				IF res # Res_OK THEN RETURN res; END;
				(* ATA device *)
				NEW(devATA, SELF, devNum, buf); 
				dev := devATA;
			ELSE
				SYSTEM.PORTIN(cmdbase+Ofs_LBAHigh, ch);	(* signature byte *)
				IF ch # ATAPISig THEN RETURN Res_Err; END;
				(* ATAPI device *)
				NEW(command);
				command.dev := devNum; command.cmd := 0A1H; (* identify packet device *)
				command.protocol := Protocol_PIO; command.read := TRUE;
				command.bufAdr := SYSTEM.ADR(buf[0]); command.count := 1;
				res := ExecuteCommand(command, IdentifyTimeout, status);
				IF Trace & (trace * TraceInit # {}) THEN
					Show("Identify packet device command, res: "); AosOut.Int(res, 0); AosOut.String(", status: "); AosOut.Bits(status, 0, 32);  
				END;
				IF res # Res_OK THEN RETURN res; END;
				NEW(devATAPI, SELF, devNum, buf);
				dev := devATAPI;
			END;
			RETURN res;
		END CreateDevice;

		PROCEDURE InitController();
		VAR p, res: LONGINT; status: SET;
		BEGIN
			res := ProtSwReset(IdentifyTimeout);
			(*IF res # Res_OK THEN
				AosOut.String(", reset failed");
				SetInterrupt(FALSE);
				RETURN; 
			END;*)
			
			IF bmbase # 0 THEN AosOut.String(", Bus-master enabled"); END;

			(* Identify Devices *)
			FOR p:=0 TO MaxDevicesC-1 DO
				SetInterrupt(TRUE);
				res := CreateDevice(p);
				SetInterrupt(res = Res_OK);
			END;
				
			(* Select drive 0 if drive 1 is not present *)
			IF (device[ctrlID*MaxDevicesC] # NIL) & (device[ctrlID*MaxDevicesC + 1] = NIL) THEN
				IF Trace & (trace * TraceCommands # {}) THEN
					AosOut.String(Name); AosOut.Int(ctrlID*MaxDevicesC, 1);
					AosOut.String(".."); AosOut.Int((ctrlID+1)*MaxDevicesC-1, 1);
					AosOut.String(" Select device 0"); AosOut.Ln;
				END;
				SYSTEM.PORTOUT(cmdbase+Ofs_Device, 0X);
				res := WaitStatus({Status_BSY, Status_DRQ}, {}, {}, SelectTimeout, status);
				IF res # Res_OK THEN AosOut.String("Select device 0 failed"); AosOut.Ln; END;
				SetInterrupt(TRUE);
			END;				
		END InitController;
		
		PROCEDURE &Create(cmd_ba, cnl_ba, bm_ba, airq: LONGINT);
		VAR
			try: LONGINT;
		BEGIN
			cmdbase := cmd_ba; cnlbase := cnl_ba; bmbase := bm_ba; irq := airq;
			state := 0;

			(* init interrupt *)
			interrupt := NIL;
			IF (irq > 0) & (irq <= 15) THEN
				NEW(interrupt, irq);
			ELSE
				AosOut.Ln; Show("Invalid IRQ assigned"); AosOut.Ln;
			END;
			SetInterrupt(TRUE);
			
			(* create buffer *)
			NEW(buffer, DMABufferSize + 1);
			bufferAdr := SYSTEM.ADR(buffer[0]);
			INC(bufferAdr, 1-(bufferAdr+1) MOD 2);

			(* create PRDT *)
			try := 3;
			REPEAT
				NEW(prdt);	(* must not cross page boundary, see Intel 290550-002 sec. 2.7.3 *)
				prdtPhysAdr := AosMemory.PhysicalAdr(SYSTEM.ADR(prdt.prd[0]), MaxPRD*8);
				DEC(try);
			UNTIL (try = 0) OR ((prdtPhysAdr # AosMemory.NilAdr) & 
				(prdtPhysAdr DIV PageSize = (prdtPhysAdr+MaxPRD*8-1) DIV PageSize));
			IF ~((prdtPhysAdr # AosMemory.NilAdr) & (prdtPhysAdr DIV PageSize = (prdtPhysAdr+MaxPRD*8-1) DIV PageSize)) THEN
				AosOut.Ln; Show("Create PRD failed (GetPRDAdr)"); AosOut.Ln;
				bmbase := 0;
			END;
		END Create;
		
		PROCEDURE Finalize;
		VAR i: LONGINT;
		BEGIN
			FOR i := 0 TO MaxDevices-1 DO
				IF (device[i] # NIL) & (device[i].controller = SELF) THEN
					device[i].Finalize;
					device[i] := NIL;
				END
			END;
			IF interrupt # NIL THEN
				interrupt.Finalize;
			END;
		END Finalize;
		
	END Controller;

	Device* = OBJECT (AosDisks.Device)
	VAR
		controller*: Controller;
		dev: LONGINT;	(* 0 or 1 *)
		size: LONGINT;	(* total size *)
		maxTransfer: LONGINT;
		chs: CHS;			(* for conversion LBA -> CHS *)
		getpar: CHS;		(* for GetParams *)
		id*: ID;
		init: BOOLEAN;	(* initialized? *)
		cmdCHS: CommandCHS;
		cmdLBA: CommandLBA;
		cmdLBA48: CommandLBA48;
		
		PROCEDURE Transfer*(op, block, num: LONGINT; VAR data: ARRAY OF CHAR; ofs: LONGINT; VAR res: LONGINT);
		VAR
			bufAdr, num1, try, ignore: LONGINT;
			dma: BOOLEAN;
		BEGIN
			bufAdr := SYSTEM.ADR(data[ofs]);
			IF (block >= 0) & (num >= 0) & (block < size) & (block+num <= size) THEN
				ASSERT(num*blockSize <= LEN(data)-ofs);	(* range check *)
				WHILE (res = Res_OK) & (num > 0) DO
					try := MaxTries;
					dma := DMABit IN id.type;
					num1 := maxTransfer; 
					IF num1 > num THEN num1 := num; END;
					REPEAT
						res := TransferEx(op, block, num1, bufAdr, dma);
						DEC(try);
						IF (res = AosDisks.WriteProtected) OR (res = AosDisks.MediaMissing) OR (res = AosDisks.Unsupported) THEN
							try := 0;
						ELSIF (res # Res_OK) & (try = MaxTriesDMA) & dma THEN
							dma := FALSE; 
							Show(name); AosOut.String(" PIO fallback"); AosOut.Ln;
						ELSIF (res # Res_OK) & (try = 0) & TryReset THEN
							ignore := Reset();
						END;
					UNTIL (res = Res_OK) OR (try = 0);
					
					IF AosDisks.Stats THEN 
						BEGIN {EXCLUSIVE}
							IF op = AosDisks.Read THEN
								NnofReads := AosBoot.AddH(NnofReads, 1);
								IF (res = Res_OK) THEN NbytesRead := AosBoot.AddH(NbytesRead, num1 * blockSize); 
								ELSE NnofErrors := AosBoot.AddH(NnofErrors, 1);
								END;
							ELSIF op = AosDisks.Write THEN
								NnofWrites := AosBoot.AddH(NnofWrites, 1);
								IF (res = Res_OK) THEN NbytesWritten := AosBoot.AddH(NbytesWritten, num1 * blockSize); 
								ELSE NnofErrors := AosBoot.AddH(NnofErrors, 1);
								END;
							ELSE
								NnofOthers := AosBoot.AddH(NnofOthers, 1);
							END;
						END;
					END;
					
					INC(block, num1); DEC(num, num1); INC(bufAdr, num1*blockSize);
				END;
			ELSE
				Show("ATA: out of range ");
				AosOut.Int(block, 1); AosOut.Char(" "); AosOut.Int(num, 1); AosOut.Char(" ");
				AosOut.Int(size, 1); AosOut.Char(" "); AosOut.String(name);
				res := 2826	(* transfer out of range *)
			END;
		END Transfer;
		
		PROCEDURE GetSize*(VAR size, res: LONGINT);
		BEGIN
			size := SELF.size;
			res := AosDisks.Ok;
		END GetSize;
		
		PROCEDURE Handle*(VAR msg: AosDisks.Message; VAR res: LONGINT);
		BEGIN
			res := AosDisks.Unsupported;
			IF msg IS AosDisks.GetGeometryMsg THEN
				WITH msg: AosDisks.GetGeometryMsg DO
					msg.cyls := getpar.cyls; msg.hds := getpar.hds; msg.spt := getpar.spt
				END;
				res := AosDisks.Ok
			ELSIF msg IS AosDisks.LockMsg THEN
				IF (RemovableBit IN id.type) & ~AllowManualEject THEN
					IF MediaLock(TRUE) = Res_OK THEN res := Res_OK; END;
				END;
			ELSIF (msg IS AosDisks.UnlockMsg) THEN
				IF (RemovableBit IN id.type) THEN
					IF MediaLock(FALSE) = Res_OK THEN res := Res_OK; END;
				END
			ELSIF (msg IS AosDisks.EjectMsg) THEN
				IF (RemovableBit IN id.type) THEN
					IF MediaEject(TRUE, FALSE) = Res_OK THEN res := Res_OK; END;
				END
			ELSIF (msg IS LoadMsg) THEN
				IF (RemovableBit IN id.type) THEN
					IF MediaEject(TRUE, TRUE) = Res_OK THEN res := Res_OK; END;
				END
			ELSIF (msg IS AosDisks.SavePowerMsg) THEN
				IF Powersave() = Res_OK THEN res := Res_OK; END;
			ELSIF (msg IS WriteCacheMsg) THEN
				IF SetWriteCache(msg(WriteCacheMsg).enable) THEN res := Res_OK; END;
			END;
		END Handle;
		
		PROCEDURE SetWriteCache(enable: BOOLEAN): BOOLEAN;
		VAR cmd: Command; status: SET;
		BEGIN {EXCLUSIVE}
			cmd := NewCommand(0EFH, Protocol_NonData);
			IF enable THEN
				cmd.features := 2;
			ELSE
				cmd.features := 82H;
			END;
			RETURN controller.ExecuteCommand(cmd, IOTimeout, status) = Res_OK;
		END SetWriteCache;
		
		PROCEDURE TransferEx(op: LONGINT; lba: HUGEINT; num, bufAdr: LONGINT; dma: BOOLEAN): LONGINT;
		VAR command: Command; status: SET;
		BEGIN {EXCLUSIVE}
			IF (op # AosDisks.Read) & (op # AosDisks.Write) THEN RETURN AosDisks.Unsupported; END;
			IF (op = AosDisks.Write) & (AosDisks.ReadOnly IN flags) THEN RETURN AosDisks.WriteProtected; END;
			command := NewCommandTransfer(op, lba, num, bufAdr, dma);
			RETURN controller.ExecuteCommand(command, IOTimeout, status);
		END TransferEx;
		
		PROCEDURE Reset(): LONGINT;
		VAR res: LONGINT;
		BEGIN
			IF Trace & (trace * TraceCommands # {})  THEN Show(name); AosOut.String(" reset controller"); AosOut.Ln; END;
			res := controller.Reset();
			IF (Trace & (trace * TraceErrors # {})) & (res # Res_OK) THEN
				AosOut.String(name); AosOut.String(" reset failed"); AosOut.Ln;
			ELSIF Trace THEN
				AosOut.String(name); AosOut.String(" reset done"); AosOut.Ln;
			END;
			RETURN res;
		END Reset;
		
		(* Only for ATA 4 or older *)
		PROCEDURE InitDevice(): LONGINT; 
		VAR command: CommandCHS; status: SET;
		BEGIN
			command := cmdCHS;
			command.dev := dev; command.cmd := 91H; command.protocol := Protocol_NonData;
			command.sector := chs.spt;
			command.head := chs.hds;
			RETURN controller.ExecuteCommand(command, IOTimeout, status);
		END InitDevice;

		PROCEDURE Flush(): LONGINT;
		VAR res: LONGINT;
		BEGIN
			res := AosDisks.Unsupported;
			IF FlushBit IN id.type THEN
				res := SendATACommand(0E7H, IOTimeout);
			END;
			RETURN res;
		END Flush;
		
		PROCEDURE MediaEject(immediate, load: BOOLEAN): LONGINT;
		BEGIN {EXCLUSIVE}
			IF ~(RemovableBit IN id.type) THEN RETURN AosDisks.Unsupported; END;
			RETURN SendATACommand(0EDH, IOTimeout); (* media eject *)
		END MediaEject;		
		
		PROCEDURE MediaLock(lock: BOOLEAN): LONGINT;
		VAR
			command: CommandLBA;
			res: LONGINT;
			status: SET;
		BEGIN {EXCLUSIVE}
			IF RMSNBit IN id.type THEN
				command := NewCommandLBA(0EFH, 0, 0); (* set features *)
				IF lock THEN
					command.features := 95H; (* enable RMSN *)
				ELSE
					command.features := 31H; (* disable RMSN *)
				END;
				res := controller.ExecuteCommand(command, IOTimeout, status);
			ELSE
				IF lock THEN
					res := SendATACommand(0DEH, IOTimeout); (* media lock *)
				ELSE
					res := SendATACommand(0DFH, IOTimeout); (* media unlock *)
				END;
			END;
			RETURN res;
		END MediaLock;
		
		PROCEDURE Powersave(): LONGINT;
		BEGIN
			RETURN SendATACommand(0E0H, IOTimeout); (* standby immediate *)
		END Powersave;		
		
		PROCEDURE SendATACommand(cmd, ms: LONGINT): LONGINT;
		VAR command: Command; status: SET;
		BEGIN {EXCLUSIVE}
			command := NewCommand(cmd, Protocol_NonData);
			RETURN controller.ExecuteCommand(command, ms, status);
		END SendATACommand;
		
		PROCEDURE NewCommand(cmd: LONGINT; protocol: SET): Command;
		VAR command: Command;
		BEGIN
			command := cmdLBA;
			ResetCommand(command);
			command.dev := dev; command.cmd := cmd; command.protocol := protocol;
			RETURN command;
		END NewCommand;
		
		PROCEDURE NewCommandTransfer(op: LONGINT; lba: HUGEINT; count, bufAdr: LONGINT; dma: BOOLEAN): Command;
		VAR
			CMD: ARRAY 8 OF LONGINT;
			idx: LONGINT;
			command: Command;
		BEGIN
			(*	mode	std		ext		dma	dma ext
				write	30		34		CA		35
				read	20		24		C8		25 
			*)
			CMD[0] := 30H; CMD[1] := 34H; CMD[2] := 0CAH; CMD[3] := 35H;
			CMD[4] := 20H; CMD[5] := 24H; CMD[6] := 0C8H; CMD[7] := 25H;
			
			IF op = AosDisks.Read THEN
				INC(idx, 4);
			ELSIF op = AosDisks.Write THEN
			ELSE
				HALT(AosDisks.Unsupported);
			END;
			IF dma THEN
				INC(idx, 2);
			END;
			
			IF LBA48Bit IN id.type THEN
				INC(idx, 1);
				command := NewCommandLBA48(CMD[idx], lba, count);
			ELSIF LBABit IN id.type THEN
				command := NewCommandLBA(CMD[idx], SHORT(lba), count);
			ELSE
				command := NewCommandCHS(CMD[idx], SHORT(lba), count);
			END;
			command.read := op = AosDisks.Read;
			command.bufAdr := bufAdr;
			command.size := count*blockSize;
			IF dma THEN
				command.protocol := Protocol_DMA;
			ELSE
				command.protocol := Protocol_PIO;
			END;
			RETURN command;
		END NewCommandTransfer;
		
		PROCEDURE NewCommandCHS(cmd, lba, count: LONGINT): CommandCHS;
		VAR x: LONGINT; command: CommandCHS;
		BEGIN
			command := cmdCHS;
			ResetCommand(command);
			command.dev := dev; command.cmd := cmd;
			command.count := count;
			command.sector := lba MOD chs.spt + 1; x := lba DIV chs.spt;
			command.head := x MOD chs.hds; command.cylinder := x DIV chs.hds;
			ASSERT((command.sector < 100H) & (command.cylinder < 10000H) & (command.head < 10H));
			RETURN command;
		END NewCommandCHS;
		
		PROCEDURE NewCommandLBA(cmd, lba, count: LONGINT): CommandLBA;
		VAR command: CommandLBA;
		BEGIN
			command := cmdLBA;
			ResetCommand(command);
			command.dev := dev; command.cmd := cmd;
			command.lba := lba; command.count := count;
			RETURN command;
		END NewCommandLBA;
		
		PROCEDURE NewCommandLBA48(cmd: LONGINT; lba: HUGEINT; count: LONGINT): CommandLBA48;
		VAR command: CommandLBA48;
		BEGIN
			command := cmdLBA48;
			ResetCommand(command);
			command.dev := dev; command.cmd := cmd;
			command.lbaHigh := SHORT(AosBoot.ASHH(lba, -32));command.lbaLow := SHORT(lba); command.count := count;
			RETURN command;
		END NewCommandLBA48;
		
		(* Identify an ATA device. *)
		PROCEDURE IdentifyDevice(buf: ARRAY OF INTEGER): LONGINT;
		VAR res, size1, hsize: LONGINT;
		BEGIN
			(* ATA 4 or older *)
			chs.cyls := LONG(buf[1]) MOD 10000H;
			chs.hds := LONG(buf[3]) MOD 10000H;
			chs.spt := LONG(buf[6]) MOD 10000H;
			size := chs.cyls * chs.hds * chs.spt;

			maxTransfer := 256;
	
			IF IdentifyMajorVersion(buf, id) # Res_OK THEN RETURN Res_Err; END;
			(* LBA *)
			IF 9 IN SYSTEM.VAL(SET, buf[49]) THEN
				size1 := ASH(LONG(buf[61]) MOD 10000H, 16) + LONG(buf[60]) MOD 10000H;
				IF size < size1 THEN size := size1 END;
				INCL(id.type, LBABit);
			ELSE
				AosOut.String(", LBA not supported");
			END;
			(* LBA 48 *)
			IF 10 IN SYSTEM.VAL(SET, buf[83]) THEN
				hsize := ASH(LONG(buf[103]) MOD 10000H, 16) + LONG(buf[102]) MOD 10000H;
				size1 := ASH(LONG(buf[101]) MOD 10000H, 16) + LONG(buf[100]) MOD 10000H;
				IF hsize > 0 THEN res := 2826; END; (* size only 32-bit *)
				IF size < size1 THEN size := size1 END;
				maxTransfer := 65536;
				INCL(id.type, LBA48Bit);
			END;
			getpar := chs;
			IF size > 16383*16*63 THEN
				getpar.cyls := size DIV (getpar.hds*getpar.spt);
			END;

			(* DMA support mandatory since ATA 4 except for CF *)
			IF ~ataForcePio & (8 IN SYSTEM.VAL(SET, buf[49])) THEN
				INCL(id.type, DMABit);
				res := IdentifyDMA(buf, id);
			ELSE
				AosOut.String(", DMA not supported");
			END;

			IF SYSTEM.VAL(SET, LONG(buf[0])) * {6,7} = {7} THEN
				INCL(id.type, RemovableBit);
				IF (4 IN SYSTEM.VAL(SET, LONG(buf[83]))) OR (0 IN SYSTEM.VAL(SET, LONG(buf[127]))) THEN INCL(id.type, RMSNBit) END;
			END;
			(* flush cache *)
			IF 12 IN SYSTEM.VAL(SET, buf[83]) THEN
				INCL(id.type, FlushBit);
			END;
			IF LONG(buf[0]) MOD 10000H = CompactFlashSignature THEN  (*CF*)
				INCL(id.type, CompactFlash);
				AosOut.String(", Compact Flash"); AosOut.Ln;
			END;
	
			GetATAString(buf, 27, 46, id.model);
			IF (buf[80] # -1) & (buf[81] # -1) THEN
				id.ver := ASH(LONG(buf[80]) MOD 10000H, 16) + LONG(buf[81]) MOD 10000H
			END;
			IF ~(LBABit IN id.type) & ~((chs.hds <= 16) & (chs.spt <= 255)) THEN
				AosOut.String("2825 identify ata geometry bad"); AosOut.Ln;
				res := 2825;
			END;
			IF maxTransfer > DMABufferSize DIV BS THEN maxTransfer := DMABufferSize DIV BS; END;
			RETURN res
		END IdentifyDevice;

		PROCEDURE ShowDevice();
		VAR
			i: LONGINT;
		BEGIN
			AosOut.String(name); AosOut.String(": ");

			AosOut.Int(size DIV (1024*1024 DIV blockSize), 1); AosOut.String("MB");
			IF LBABit IN id.type THEN
				IF LBA48Bit IN id.type THEN AosOut.String(", LBA48") ELSE AosOut.String(", LBA") END;
			ELSE
				AosOut.String(", "); ShowCHS(chs);
				IF (getpar.cyls # chs.cyls) OR (getpar.hds # chs.hds) OR (getpar.spt # chs.spt) THEN
					AosOut.String(", ("); ShowCHS(getpar); AosOut.Char(")")
				END
			END;
			IF CompactFlash IN id.type THEN AosOut.String(", CompactFlash") END; (*CF*)
			IF RemovableBit IN id.type THEN AosOut.String(", removable") END;
			IF RMSNBit IN id.type THEN AosOut.String(" (RMSN)") END;
			IF id.majorVersion > 0 THEN AosOut.String(", ATA/ATAPI-"); AosOut.Int(id.majorVersion, 0); END;
			IF DMABit IN id.type THEN
				(*IF id.maxdmamode < 10 THEN
					AosOut.String(", MW DMA "); AosOut.Int(id.maxdmamode, 1);
				ELSE
					AosOut.String(", Ultra DMA "); AosOut.Int(id.maxdmamode-10, 1);
				END;*)
				IF id.dmamode < 10 THEN
					AosOut.String(", MW DMA "); AosOut.Int(id.dmamode, 1);
				ELSE
					AosOut.String(", Ultra DMA "); AosOut.Int(id.dmamode-10, 1);
				END;
			ELSE
				AosOut.String(", no DMA")
			END;
			AosOut.String(", "); AosOut.String(id.model);
			IF id.ver # 0 THEN
				AosOut.String(", ver ");
				i := 30; WHILE (i # 16) & ~ODD(ASH(id.ver, -i)) DO DEC(i) END;
				AosOut.Int(i-16, 1);AosOut.Char(".");
				AosOut.Int(id.ver MOD 10000H, 1)
			END;
			AosOut.Ln;
		END ShowDevice;

		PROCEDURE &Create(acontroller: Controller; adev: LONGINT; identifyDevice: ARRAY OF INTEGER);
		VAR
			name: AosPlugins.Name;
			str: ARRAY 32 OF CHAR;
			i, res: LONGINT;
		BEGIN
			name := Name;
			i := 0; WHILE name[i] # 0X DO INC(i) END;
			name[i] := CHR(48 + acontroller.ctrlID*MaxDevicesC + adev); name[i+1] := 0X;
			SetName(name);
			
			controller := acontroller; dev := adev; init := FALSE;
			NEW(cmdCHS); NEW(cmdLBA); NEW(cmdLBA48);
			blockSize := BS;
			
			res := IdentifyDevice(identifyDevice);
			COPY(id.model, desc);

			AosBoot.GetConfig(name, str);
			IF (controller.bmbase = 0) OR (str="nodma") THEN
				EXCL(id.type, DMABit);
			END;
			IF str="CHS" THEN
				EXCL(id.type, LBABit);
				EXCL(id.type, LBA48Bit);
			END;
			IF InitDevices & (res = Res_OK) & (id.type * {LBABit, AtapiBit} = {}) (*& (id.majorVersion > 0)*) & (id.majorVersion <= 4) THEN
				res := InitDevice();
				AosOut.Ln; Show("InitDevice, res: "); AosOut.Int(res, 0);
			END;
			
			device[acontroller.ctrlID*MaxDevicesC + adev] := SELF;
			(* register device *)
			flags := {};
			IF RemovableBit IN id.type THEN INCL(flags, AosDisks.Removable) END;
			IF str="ro" THEN INCL(flags, AosDisks.ReadOnly); END;
			IF res # Res_OK THEN INCL(flags, AosDisks.ReadOnly); AosOut.Ln; Show("Error RO"); END;
			AosDisks.registry.Add(SELF, res);
			ASSERT(res = AosPlugins.Ok);
		END Create;

		PROCEDURE Finalize();
		VAR res: LONGINT;
		BEGIN
			(* unregister device *)
			AosDisks.registry.Remove(SELF);
			res := Flush();
			device[controller.ctrlID*MaxDevicesC + dev] := NIL;
		END Finalize;

	END Device;

TYPE

	DeviceATAPI* = OBJECT (Device)
	VAR
		sense, asc, ascq: LONGINT;
		fieldPointer: ARRAY 3 OF CHAR;
		cmdPacket: CommandPacket;

		(* for writing audio tracks block size needs being set explicitely to 2352 *)
		PROCEDURE SetBlockSize*(size: LONGINT);
		BEGIN
			blockSize := size;
		END SetBlockSize;
		
		(* ReadCapacity returns 1 for empty disks *)
		PROCEDURE SetCapacity*(cap: LONGINT);
		BEGIN
			size := cap;
		END SetCapacity;
		
		PROCEDURE GetSize*(VAR asize, res: LONGINT);
		BEGIN
			res := Res_OK;
			IF RemovableBit IN id.type THEN
				BEGIN {EXCLUSIVE}
					res := WaitUntilReady();
					(*IF res # Res_OK THEN ProcessSense(res); RETURN; END;*)
					res := ReadCapacity(blockSize, size);
					IF (res = Res_OK) & (id.devtype = ATAPI_CDRom) & (blockSize # 2048) THEN blockSize := 2048 END;	(* user data field only *)
					ProcessSense(res);
				END;
			END;
			IF res = Res_OK THEN
				GetSize^(asize, res);
			END;
		END GetSize;
		
		PROCEDURE Handle*(VAR msg: AosDisks.Message; VAR res: LONGINT);
		BEGIN
			res := AosDisks.Unsupported;
			IF msg IS AosDisks.GetGeometryMsg THEN
			ELSIF msg IS GetSenseMsg THEN
				ProcessSense(res);
				WITH msg: GetSenseMsg DO
					msg.sense := sense; msg.asc := asc; msg.ascq := ascq;
					COPY(fieldPointer, msg.fieldPointer);
				END;
				sense := -1;
			ELSIF msg IS TestUnitReadyMsg THEN
				res := TestUnitReady();
				ProcessSense(res);
			ELSE
				Handle^(msg, res);
			END
		END Handle;
		
		PROCEDURE ExecuteCommand*(read: BOOLEAN; VAR packet, data: ARRAY OF CHAR; ofs, size: LONGINT; dma: BOOLEAN): LONGINT;
		VAR
			command: CommandPacket;
			i, res: LONGINT;
			status: SET;
		BEGIN {EXCLUSIVE}
			ASSERT(LEN(packet) <= LEN(command.packet));
			ASSERT(size <= LEN(data)-ofs);	(* range check *)
			command := cmdPacket;
			command.packetLen := LEN(packet);
			command.dev := dev; command.cmd := 0A0H;

			IF dma THEN
				command.protocol := Protocol_PacketDMA;
			ELSE
				command.protocol := Protocol_PacketPIO;
			END;
			command.read := read;
			command.bufAdr := SYSTEM.ADR(data[ofs]);
			command.size := size;

			FOR i:= 0 TO LEN(command.packet)-1 DO
				command.packet[i] := packet[i];
			END;
			res := controller.ExecuteCommand(command, ATAPITimeout, status);
			sense := -1;
			ProcessSense(res);
			RETURN res;
		END ExecuteCommand;
		
		PROCEDURE ProcessSense(VAR res: LONGINT);
		BEGIN
			IF res = Res_OK THEN
				sense := 0; asc := 0; ascq := 0;
			ELSIF res # Res_OK THEN
				res := 2831;
				IF sense <= 0 THEN
					IF RequestSense() = Res_OK THEN END;
				END;
				IF sense > 0 THEN
					res := 2832;
					IF (asc = 27H) THEN res := AosDisks.WriteProtected;
					ELSIF (asc = 28H) & (ascq = 0) THEN res := AosDisks.MediaChanged;
					ELSIF (asc = 3AH) THEN res := AosDisks.MediaMissing; END;
				END;
			END;
		END ProcessSense;

		PROCEDURE TransferEx*(op: LONGINT; lba: HUGEINT; num, bufAdr: LONGINT; dma: BOOLEAN): LONGINT;
		VAR
			command: Command;
			res, timeout: LONGINT;
			status: SET;
		BEGIN {EXCLUSIVE}
			IF (op # AosDisks.Read) & (op # AosDisks.Write) & (op # WriteAndVerify) THEN RETURN AosDisks.Unsupported; END;
			IF ((op = AosDisks.Write) OR (op = WriteAndVerify)) & (AosDisks.ReadOnly IN flags) THEN RETURN AosDisks.WriteProtected; END;
			res := WaitUntilReady();
			command := NewCommandPacketTransfer(op, lba, num, bufAdr, num*blockSize, dma);
			IF op = AosDisks.Read THEN
				timeout := IOTimeout;
			ELSE
				(* first write needs more time on some drives *)
				 timeout := 4*IOTimeout;
			END;
			res := controller.ExecuteCommand(command, timeout, status);
			sense := -1;
			ProcessSense(res);
			RETURN res;
		END TransferEx;
		
		PROCEDURE WaitUntilReady(): LONGINT;
		VAR res: LONGINT; retry: BOOLEAN;
		BEGIN
			REPEAT
				retry := FALSE;
				res := TestUnitReady();
				IF res # Res_OK THEN
				(*IF res = Res_Err THEN*)
					IF RequestSense() = Res_OK THEN
						retry := (asc = 29H) OR ((asc = 4) & (ascq = 1)) OR ((asc = 28H) & (ascq = 0));
					END;
					IF retry THEN AosActive.Yield(); END;
				END;
			UNTIL ~retry;
			res := Res_OK;
			RETURN res;
		END WaitUntilReady;
		
	(* ATAPI funtions *)
	
		PROCEDURE Reset(): LONGINT;
		VAR
			i, res : LONGINT;
			status: SET;
			command: Command;
		BEGIN
			IF Trace & (trace * (TraceCommands + TraceAtapi) # {}) THEN
				AosOut.String(name); AosOut.String(" device reset"); AosOut.Ln;
			END;
			command := NewCommand(8, Protocol_DeviceReset); (* Device Reset *)
			res := controller.ExecuteCommand(command, ResetTimeout, status); (* reset packet device *)
			sense := -1;
			IF Trace THEN
				IF (trace * TraceErrors # {})  & (res # Res_OK) THEN
					AosOut.String(name); AosOut.String(" reset failed"); AosOut.Ln;
				ELSIF (trace * (TraceCommands + TraceAtapi) # {}) THEN
					AosOut.String(name); AosOut.String(" done"); AosOut.Ln;
				END;
			END;
			IF RequestSense() # Res_OK THEN
				IF res # Res_OK THEN res := Reset^(); END;
			END;
			IF res # Res_OK THEN RETURN 2816; END;
			GetSize(i, i);
			(*undocumented: the first command after Reset Device shall be a PACKET command, other
			   commands like Set Features otherwise abort.*)
			RETURN Res_OK;
		END Reset;
		
		PROCEDURE RequestSense*(): LONGINT;
		VAR
			command: CommandPacket;
			buf: ARRAY 18 OF CHAR;
			res: LONGINT;
			status: SET;
		BEGIN
			IF Trace & (trace * (TraceCommands + TraceAtapi) # {}) THEN
				 Show(name); AosOut.String(" request sense"); AosOut.Ln;
			END;
			sense := -1;
			command := NewCommandPacket(03H);
			command.protocol := Protocol_PacketPIO;
			command.read := TRUE;
			command.bufAdr := SYSTEM.ADR(buf[0]);
			command.size := LEN(buf);
			command.packet[4] := CHR(LEN(buf));
			res := controller.ExecuteCommand(command, ATAPITimeout, status);

			IF Trace & (trace * (TraceErrors + TraceSense) # {}) & (res # Res_OK) THEN
				Show(name); AosOut.String(" request sense failed"); AosOut.Ln;
			END;
			IF res # Res_OK THEN RETURN res; END;
			sense := ORD(buf[2]) MOD 10H;
			asc := ORD(buf[12]);
			ascq := ORD(buf[13]);
			fieldPointer[0] := buf[15]; fieldPointer[1] := buf[16]; fieldPointer[2] := buf[17];
			IF Trace & (trace * TraceSense # {}) THEN
				AosOut.String(name); AosOut.String(" request sense: ");
				AosOut.Hex(sense, -2); AosOut.String(", ");
				AosOut.Hex(asc, -2); AosOut.String(", ");
				AosOut.Hex(ascq, -2);
				AosOut.String(", "); AosOut.Int(res, 0);
				AosOut.Ln;
			END;
			RETURN Res_OK;
		END RequestSense;
		
		PROCEDURE TestUnitReady*(): LONGINT;
		VAR
			command: CommandPacket;
			res: LONGINT;
			status: SET;
		BEGIN
			IF Trace & (trace * (TraceCommands + TraceAtapi) # {}) THEN
				 Show(name); AosOut.String(" test unit ready");AosOut.Ln;
			END;
			command := NewCommandPacket(00H);
			command.protocol := Protocol_PacketPIO;
			command.read := TRUE;
			res := controller.ExecuteCommand(command, ATAPITimeout, status);
			sense := -1;
			IF Trace & (trace * TraceErrors # {}) & (res # Res_OK) THEN
				AosOut.String(name); AosOut.String(" not ready "); AosOut.Int(res, 0); AosOut.Ln;
			END;
			RETURN res;
		END TestUnitReady;	
	
		PROCEDURE Flush(): LONGINT;
		BEGIN
			RETURN Flush^();
		END Flush;
		
		PROCEDURE MediaEject*(immediate, load: BOOLEAN): LONGINT;
		VAR
			command: CommandPacket;
			res, timeout: LONGINT;
			status: SET;
		BEGIN {EXCLUSIVE}
			command := NewCommandPacket(1BH); (* start/stop unit *)
			command.protocol := Protocol_PacketPIO;
			IF immediate THEN
				command.packet[1] := 1X;	(* return immediately *)
				timeout := ATAPITimeout;
			ELSE
				timeout := 4*ATAPITimeout;
			END;
			IF load THEN
				command.packet[4] := 3X;	(* load medium *)
			ELSE
				command.packet[4] := 2X;	(* eject medium *)
			END;
			res := controller.ExecuteCommand(command, timeout, status);
			sense := -1;
			(*IF res # Res_OK THEN
				res := MediaEject^(load);
			END;*)
			ProcessSense(res);
			RETURN res;
		END MediaEject;

		PROCEDURE MediaLock*(lock: BOOLEAN): LONGINT;
		VAR
			command: CommandPacket;
			res: LONGINT;
			status: SET;
		BEGIN {EXCLUSIVE}
			command := NewCommandPacket(1EH); (* prevent/allow medium removal *)
			command.protocol := Protocol_PacketPIO;
			IF lock THEN
				command.packet[4] := 1X;	(* 1: lock medium, 0: unlock medium *)
			END;
			res := controller.ExecuteCommand(command, ATAPITimeout, status);
			sense := -1;
			ProcessSense(res);
			RETURN res;
		END MediaLock;
		
		PROCEDURE Powersave(): LONGINT;
		VAR
			command: CommandPacket;
			res: LONGINT;
			status: SET;
		BEGIN {EXCLUSIVE}
			command := NewCommandPacket(1BH); (* start/stop unit *)
			command.protocol := Protocol_PacketPIO;
			command.packet[1] := 1X;	(* return immediately *)
			command.packet[4] := 0X;	(* stop medium *)
			res := controller.ExecuteCommand(command, ATAPITimeout, status);
			sense := -1;
			ProcessSense(res);
			RETURN res;
		END Powersave;		

		PROCEDURE ReadCapacity*(VAR blkSize, size: LONGINT): LONGINT;
		VAR 
			buf: ARRAY 2 OF LONGINT;  res, sense: LONGINT;
			command: CommandPacket; status: SET;
		BEGIN
			IF Trace & (trace * (TraceCommands + TraceAtapi + TraceInit) # {}) THEN
				 Show(name); AosOut.String(" read capacity");AosOut.Ln;
			END;
			command := NewCommandPacket(25H);
			command.protocol := Protocol_PacketPIO;
			command.read := TRUE;
			command.bufAdr := SYSTEM.ADR(buf[0]);
			command.size := 8;
			res := controller.ExecuteCommand(command, ATAPITimeout, status);
			sense := -1;
			IF Trace & (trace * (TraceErrors + TraceInit) # {}) & (res # Res_OK) THEN
				Show(name); AosOut.String(" read capacity failed "); AosOut.Int(res, 0); AosOut.Ln;
			END;
			
			IF res # Res_OK THEN RETURN res; END;
			size := buf[0]; blkSize := buf[1];
			Swap(size); Swap(blkSize);
			INC(size);	(*read capacity returns the last sector*)
			IF Trace & (trace * (TraceCommands + TraceAtapi + TraceInit) # {}) THEN
				Show(name); AosOut.String(" read capacity ");
				AosOut.Int(size*blkSize, 4); AosOut.String(" Bytes"); AosOut.Ln;
			END;
			RETURN res
		END ReadCapacity;

		PROCEDURE NewCommandPacketTransfer(op: LONGINT; lba: HUGEINT; count, bufAdr, size: LONGINT; dma: BOOLEAN): CommandPacket;
		VAR
			command: CommandPacket;
			i, lbaLow, lbaHigh: LONGINT;
		BEGIN
			command := cmdPacket;
			ResetCommand(command);
			FOR i:= 0 TO LEN(command.packet)-1 DO
				command.packet[i] := 0X;
			END;

			command.packetLen := 12;
			command.dev := dev; command.cmd := 0A0H;
			command.read := (op = AosDisks.Read);
			command.count := count;
			command.bufAdr := bufAdr;
			command.size := size;
			IF dma THEN
				command.protocol := Protocol_PacketDMA;
				INCL(command.features, ATAPI_DMA);
			ELSE
				command.protocol := Protocol_PacketPIO;
			END;
			CASE op OF
				  AosDisks.Read: command.packet[0] := 28X; (* 0A8X *)
				| AosDisks.Write : 	command.packet[0] := 2AX; (* 0AAX *)
				| WriteAndVerify: command.packet[0] := 2EX; 
				ELSE HALT(AosDisks.Unsupported);
			END;
			
			lbaLow := SHORT(lba);
			lbaHigh := SHORT(AosBoot.ASHH(lba, -32));
			ASSERT((lbaHigh = 0) OR (lbaHigh = -1)); (* negative value possible for raw writing *)
			command.packet[2] := CHR(ASH(lbaLow, -24) MOD 100H);
			command.packet[3] := CHR(ASH(lbaLow, -16) MOD 100H);
			command.packet[4] := CHR(ASH(lbaLow, -8) MOD 100H);
			command.packet[5] := CHR(lbaLow MOD 100H);

			(* 28, 2A *)
			command.packet[7] := CHR(ASH(count, -8) MOD 100H);
			command.packet[8] := CHR(count MOD 100H);

			(* A8, AA *)
			(*command.packet[6] := CHR(ASH(count, -24) MOD 100H);
			command.packet[7] := CHR(ASH(count, -16) MOD 100H);
			command.packet[8] := CHR(ASH(count, -8) MOD 100H);
			command.packet[9] := CHR(count MOD 100H);*)

			RETURN command;
		END NewCommandPacketTransfer;
		
		PROCEDURE NewCommandPacket*(cmd: LONGINT): CommandPacket;
		VAR
			command: CommandPacket;
			i: LONGINT;
		BEGIN
			command := cmdPacket;
			ResetCommand(command);
			FOR i:= 0 TO LEN(command.packet)-1 DO
				command.packet[i] := 0X;
			END;
			
			command.packetLen := 12;
			command.dev := dev; command.cmd := 0A0H;
			command.packet[0] := CHR(cmd);
			RETURN command;
		END NewCommandPacket;
		
		PROCEDURE IdentifyDevice(buf: ARRAY OF INTEGER): LONGINT;
		VAR res : LONGINT;
		BEGIN
			maxTransfer := 65535;

			IF 7 IN SYSTEM.VAL(SET, LONG(buf[0])) THEN	(* removable *)
				INCL(id.type, RemovableBit);
				(* RMSN *)
				IF (4 IN SYSTEM.VAL(SET, LONG(buf[83]))) OR (0 IN SYSTEM.VAL(SET, LONG(buf[127]))) THEN INCL(id.type, RMSNBit) END;
			END;
			IF 0 IN SYSTEM.VAL(SET, LONG(buf[0])) THEN
				(* packet 16 byte *)
				INCL(id.type, Packet16Bit);
			END;
			IF ~atapiForcePio & ( 8 IN SYSTEM.VAL(SET, LONG(buf[49]))) THEN
				(* DMA *)
				INCL(id.type, DMABit);
				res := IdentifyDMA(buf, id);
			END;

			(* flush cache *)
			IF 12 IN SYSTEM.VAL(SET, buf[83]) THEN
				INCL(id.type, FlushBit);
			END;
			IF LONG(buf[0]) MOD 10000H = CompactFlashSignature THEN INCL(id.type, CompactFlash) END; (*CF*)

			GetATAString(buf, 27, 46, id.model);
			id.devtype := ASH(buf[0], -8) MOD 20H;
			IF (buf[80] # -1) & (buf[81] # -1) THEN
				id.ver := ASH(LONG(buf[80]) MOD 10000H, 16) + LONG(buf[81]) MOD 10000H
			END;
	
			IF Packet16Bit IN id.type THEN
				Show("2833 ATAPI: unsupported packet size"); AosOut.Ln;
				res := 2833;
			ELSE
				res := Res_OK;
			END;
			IF maxTransfer > DMABufferSize DIV 2048 THEN maxTransfer := DMABufferSize DIV 2048; END;
			RETURN res
		END IdentifyDevice;

		PROCEDURE ShowDevice();
		VAR i: LONGINT;
		BEGIN
			AosOut.String(name); AosOut.String(": ");
			
			AosOut.String("ATAPI");
			IF Packet16Bit IN id.type THEN AosOut.String(" (16bit)") END;
			ShowDevType(id.devtype);

			IF CompactFlash IN id.type THEN AosOut.String(", CompactFlash") END; (*CF*)
			IF RemovableBit IN id.type THEN AosOut.String(", removable") END;
			IF RMSNBit IN id.type THEN AosOut.String(" (RMSN)") END;
			IF id.majorVersion > 0 THEN AosOut.String(", ATA/ATAPI-"); AosOut.Int(id.majorVersion, 0); END;
			IF DMABit IN id.type THEN
				(*IF id.maxdmamode < 10 THEN
					AosOut.String(", MW DMA "); AosOut.Int(id.maxdmamode, 1);
				ELSE
					AosOut.String(", Ultra DMA "); AosOut.Int(id.maxdmamode-10, 1);
				END;*)
				IF id.dmamode < 10 THEN
					AosOut.String(", MW DMA ");AosOut.Int(id.dmamode, 1);
				ELSE
					AosOut.String(", Ultra DMA "); AosOut.Int(id.dmamode-10, 1);
				END;
			ELSE
				AosOut.String(", no DMA")
			END;
			AosOut.String(", "); AosOut.String(id.model);
			IF id.ver # 0 THEN
				AosOut.String(", ver ");
				i := 30; WHILE (i # 16) & ~ODD(ASH(id.ver, -i)) DO DEC(i) END;
				AosOut.Int(i-16, 1); AosOut.Char(".");
				AosOut.Int(id.ver MOD 10000H, 1)
			END;
			AosOut.Ln;
		END ShowDevice;

		PROCEDURE &Create(acontroller: Controller; adev: LONGINT; identifyDevice: ARRAY OF INTEGER);
		VAR res: LONGINT;
		BEGIN
			INCL(id.type, AtapiBit);
			NEW(cmdPacket);
			Create^(acontroller, adev, identifyDevice);
			(* CD_ROM by default ReadOnly *)
			IF id.devtype = ATAPI_CDRom THEN INCL(flags, AosDisks.ReadOnly); END;
			res := Reset();
			init := TRUE;
		END Create;

		PROCEDURE Finalize();
		BEGIN
			Finalize^();
		END Finalize;
				
	END DeviceATAPI;

VAR
	controller: ARRAY MaxControllers OF Controller;
	device: ARRAY MaxDevices OF Device;
	nofControllers: LONGINT;
	installed: BOOLEAN;
	irqCount, expectedCount: LONGINT;
	
	(* Options that can be set using boot config strings *)
	ataForcePio : BOOLEAN;
	atapiForcePio : BOOLEAN;
	trace* : SET;

(* Block port input instruction. *)

PROCEDURE -RepInWord(port, bufAdr, len: LONGINT);
CODE {SYSTEM.i386}
	POP ECX
	POP EDI
	POP EDX
	CLD
	REP INSW
END RepInWord;

(* Block port out instruction. *)

PROCEDURE -RepOutWord(port, bufAdr, len: LONGINT);
CODE {SYSTEM.i386}
	POP ECX
	POP ESI
	POP EDX
	CLD
	REP OUTSW
END RepOutWord;

PROCEDURE -SIZEOF(o: ANY): LONGINT;
CODE {SYSTEM.i386}
	POP	EAX
	MOV	EAX, -4[EAX]
	MOV	EAX, 0[EAX]
END SIZEOF;

PROCEDURE ResetCommand(cmd: Command);
VAR
	s: LONGINT;
BEGIN
	ASSERT(cmd # NIL);
	s := SIZEOF(cmd);
	ASSERT(s MOD 4 = 0);
	AosBoot.Fill32(SYSTEM.VAL(LONGINT, cmd), s, 0);
END ResetCommand;

PROCEDURE GetPhysAdr(bufAdr, size: LONGINT; VAR physAdr: LONGINT): BOOLEAN;
BEGIN
	physAdr := AosMemory.PhysicalAdr(bufAdr, size);
	RETURN physAdr # AosMemory.NilAdr
END GetPhysAdr;

(*PROCEDURE GetPRDAdr(VAR c: Command): BOOLEAN;
VAR p: LONGINT;
BEGIN
	NEW(c.prdt);	(* must not cross page boundary, see Intel 290550-002 sec. 2.7.3 *)
	p := AosMemory.PhysicalAdr(SYSTEM.ADR(c.prdt.prd[0]), MaxPRD*8);
	c.prdtPhysAdr := p;
	RETURN (p # AosMemory.NilAdr) & (p DIV PageSize = (p+MaxPRD*8-1) DIV PageSize)
END GetPRDAdr;*)

(* NanoDelay - Delay at least ns nanoseconds. *)
PROCEDURE NanoDelay(ns: LONGINT);
BEGIN
	ns := ns*4;
	WHILE ns > 0 DO DEC(ns) END
END NanoDelay;

(* Swap a longint *)
PROCEDURE Swap(VAR a: ARRAY OF SYSTEM.BYTE);
VAR x: SYSTEM.BYTE;
BEGIN
	x := a[0]; a[0] := a[3]; a[3] := x;
	x := a[1]; a[1] := a[2]; a[2] := x;
END Swap;

PROCEDURE AosOutHex(x, j, w: LONGINT);
VAR i: LONGINT; buf: ARRAY 10 OF CHAR;
BEGIN
	IF j = 0 THEN
		IF w >= 0 THEN j := 8 ELSE j := 2; w := -w END;
	END;
	FOR i := j+1 TO w DO AosOut.Char(" ") END;
	FOR i := j-1 TO 0 BY -1 DO
		buf[i] := CHR(x MOD 10H + 48);
		IF buf[i] > "9" THEN
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
		END;
		x := x DIV 10H
	END;
	buf[j] := 0X;
	AosOut.String(buf)
END AosOutHex;

(* Convert an ATA identify string to a readable format. *)
PROCEDURE GetATAString(VAR buf: ARRAY OF INTEGER; from, to: LONGINT; VAR s: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	FOR i := from TO to DO
		s[2*(i-from)] := CHR(buf[i] DIV 100H MOD 100H);
		s[2*(i-from)+1] := CHR(buf[i] MOD 100H)
	END;
	s[2*(to-from+1)] := 0X;
	i := 0; j := 0;
	WHILE s[i] # 0X DO
		IF (s[i] >= 20X) & (s[i] <= 7EX) THEN s[j] := s[i]; INC(j) END;
		INC(i);
		IF (j # 0) & (s[j-1] = 20X) THEN
			WHILE s[i] = 20X DO INC(i) END
		END
	END;
	IF (j # 0) & (s[j-1] = 20X) THEN DEC(j) END;
	s[j] := 0X
END GetATAString;

PROCEDURE IdentifyMajorVersion(buf: ARRAY OF INTEGER; VAR id: ID): LONGINT;
VAR
	a, i: LONGINT;
BEGIN
	a := 0;
	IF buf[80] # -1 THEN
		i := 3;
		WHILE i < 15 DO
			IF i IN SYSTEM.VAL(SET, buf[80]) THEN a := i; END;
			INC(i);
		END;
	END;
	id.majorVersion := a; 
	RETURN Res_OK;
END IdentifyMajorVersion;

PROCEDURE IdentifyDMA(buf: ARRAY OF INTEGER; VAR id: ID): LONGINT;
VAR a, i: LONGINT;
BEGIN
	(* Determine the maximum Multiword DMA mode supported *)
	a := -1; i := 0;
	WHILE i < 3 DO
		IF i IN SYSTEM.VAL(SET, buf[63]) THEN INC(a); END;
		INC(i);
	END;
	id.maxdmamode := a; 

	(* Determine the currently selected Multiword DMA mode *)
	a:= -1; i := 8;
	WHILE i < 11 DO
		IF i IN SYSTEM.VAL(SET, buf[63]) THEN a := i-8; END;
		INC(i);
	END;
	id.dmamode := a; 
	
	(* Are the fields reported in word 88 valid? *)
	IF 2 IN SYSTEM.VAL(SET, buf[53]) THEN
		(* Determine the maximum Ultra DMA mode supported *)
		a := -1; i := 0;
		WHILE i < 8 DO
			IF i IN SYSTEM.VAL(SET, buf[88]) THEN INC(a); END;
			INC(i);
		END;
		IF a >= 0 THEN
			id.maxdmamode := 10+a;
		END;

		(* Determine the currntly seleccted Ultra DMA mode *)
		a:= -1; i := 8;
		WHILE i < 16 DO
			IF i IN SYSTEM.VAL(SET, buf[88]) THEN a := i-8; END;
			INC(i);
		END;
		IF a >= 0 THEN
			id.dmamode := 10+a;
		END;
	END;
	RETURN Res_OK;
END IdentifyDMA;

PROCEDURE ShowCHS(chs: CHS);
BEGIN
	AosOut.Int(chs.cyls, 1);
	AosOut.Char("*");
	AosOut.Int(chs.hds, 1);
	AosOut.Char("*");
	AosOut.Int(chs.spt, 1)
END ShowCHS;

PROCEDURE ShowDevType(t: LONGINT);
BEGIN
	CASE t OF
	| 0:  AosOut.String(" direct access")
	| 1:  AosOut.String(" sequential access")
	| 2:  AosOut.String(" printer")
	| 3:  AosOut.String(" processor")
	| 4:  AosOut.String(" write-once")
	| 5:  AosOut.String(" cd-rom")
	| 6:  AosOut.String(" scanner")
	| 7:  AosOut.String(" optical memory")
	| 8:  AosOut.String(" medium changer")
	| 9:  AosOut.String(" communications")
	ELSE AosOut.String(" type "); AosOut.Int(t, 1)
	END;
	AosOut.String(" device")
END ShowDevType;

PROCEDURE ShowDevices();
VAR i : LONGINT; dev: Device;
BEGIN
	FOR i := 0 TO MaxDevices-1 DO
		dev := device[i];
		IF dev # NIL THEN
			dev.ShowDevice();
		END
	END;
END ShowDevices;

PROCEDURE AddController*(ctrl: Controller);
VAR
	i, c: LONGINT;
BEGIN {EXCLUSIVE}
	IF ctrl = NIL THEN RETURN; END;
	c := -1;
	FOR i:=0 TO nofControllers-1 DO
		IF controller[i] # NIL THEN
			IF ctrl.cmdbase = controller[i].cmdbase THEN
				Show("Resource conflict for controller "); AosOut.Int(i, 0); AosOut.Ln;
				c := i;
			END;
		END;
	END;
	IF c = -1 THEN
		Show("Adding controller ");
	ELSE
		controller[c].Finalize;
		Show("Replacing controller ");
	END;
	AosOutHex(ctrl.cmdbase, 4, 0); AosOut.String(", ");
	AosOutHex(ctrl.cnlbase, 4, 0); AosOut.String(", ");
	AosOutHex(ctrl.bmbase, 4, 0); AosOut.String(", ");
	AosOut.String("IRQ: "); AosOut.Int(ctrl.irq, 0);

    (* Add Controller *)
	IF ctrl.cmdbase = 1F0H THEN
		i := 0;
    ELSIF ctrl.cmdbase = 170H THEN
		i := 1;
	ELSE
		IF c = -1 THEN
			i := nofControllers;
			INC(nofControllers);
		ELSE
			i := c;
		END;
	END;
	controller[i] := ctrl;
	ctrl.ctrlID := i;
	AosOut.String(": ");
	AosOut.String(Name); AosOut.Int(i*MaxDevicesC, 1);
	AosOut.String(".."); AosOut.Int((i+1)*MaxDevicesC-1, 1);

    (* Init Controller *)
	ctrl.InitController();
	AosOut.Ln;
END AddController;

PROCEDURE IdentifyController*(bus, dev, fkt: LONGINT);
VAR res, pcmd_ba, pcnl_ba, scmd_ba, scnl_ba, bm_ba, irq: LONGINT; s: SET;
	c: Controller;
BEGIN
	res := PCI.ReadConfigDword(bus, dev, fkt,  PCI.Adr0Reg, pcmd_ba);
	IF ~((res = PCI.Done) & (ODD(pcmd_ba) OR (pcmd_ba = 0))) THEN RETURN; END; (* I/O mapped or leagacy *)
	DEC(pcmd_ba, pcmd_ba MOD 8);
	
	res := PCI.ReadConfigDword(bus, dev, fkt,  PCI.Adr1Reg, pcnl_ba);
	IF ~((res = PCI.Done) & (ODD(pcnl_ba) OR (pcnl_ba = 0))) THEN RETURN; END; (* I/O mapped or leagacy *)
	DEC(pcnl_ba, pcnl_ba MOD 8);
	
	res := PCI.ReadConfigDword(bus, dev, fkt,  PCI.Adr2Reg, scmd_ba);
	IF ~((res = PCI.Done) & (ODD(scmd_ba) OR (scmd_ba = 0))) THEN RETURN; END; (* I/O mapped or leagacy *)
	DEC(scmd_ba, scmd_ba MOD 8);
	
	res := PCI.ReadConfigDword(bus, dev, fkt,  PCI.Adr3Reg, scnl_ba);
	IF ~((res = PCI.Done) & (ODD(scnl_ba) OR (scnl_ba = 0))) THEN RETURN; END; (* I/O mapped or leagacy *)
	DEC(scnl_ba, scnl_ba MOD 8);
	
	IF PCI.ReadConfigDword(bus, dev, fkt,  PCI.Adr4Reg, bm_ba) # PCI.Done THEN RETURN; END;
	IF ~((res = PCI.Done) & (ODD(bm_ba) OR (bm_ba = 0))) THEN RETURN; END; (* I/O mapped or no BM *)
	DEC(bm_ba, bm_ba MOD 10H);
	
	IF bm_ba # 0 THEN
		(* InitBusMaster *)
		IF PCI.ReadConfigWord(bus, dev, fkt, PCI.CmdReg, SYSTEM.VAL(LONGINT, s)) # PCI.Done THEN RETURN; END;
		IF s*{2,0} = {0} THEN
			INCL(s, 2);
			IF PCI.WriteConfigWord(bus, dev, fkt, PCI.CmdReg, SYSTEM.VAL(LONGINT, s)) # PCI.Done THEN RETURN; END;
		END;
		IF s*{2,0} # {2,0} THEN bm_ba := 0; END;
	END;
	
	IF PCI.ReadConfigByte(bus, dev, fkt,  PCI.IntlReg, irq) # PCI.Done THEN RETURN; END;
	IF ~((res = PCI.Done)) THEN RETURN; END;

	(* Primary Controller *)
	IF (pcmd_ba = 0) OR ((pcmd_ba = 1F0H) & (pcnl_ba = 3F0H)) THEN
		NEW(c, 1F0H, 3F0H, bm_ba, 14);
	ELSE
		NEW(c, pcmd_ba, pcnl_ba, bm_ba, irq);
	END;
	AddController(c);
	
	(* Secondary Controller *)
	IF bm_ba # 0 THEN
		bm_ba := bm_ba+8;
	END;
	IF (scmd_ba = 0) OR ((scmd_ba = 170H) & (scnl_ba = 370H)) THEN
		NEW(c, 170H, 370H, bm_ba, 15);
	ELSE
		NEW(c, scmd_ba, scnl_ba, bm_ba, irq);
	END;
	AddController(c);
END IdentifyController;

PROCEDURE ScanPCI(vendor, id: LONGINT);
VAR idx, bus, dev, fkt: LONGINT;
BEGIN
	idx := 0;
	WHILE PCI.FindPCIDevice(id, vendor, idx, bus, dev, fkt) = PCI.Done DO
		Show("Found PCI device "); AosOutHex(vendor, 4, 0); AosOut.String(":"); AosOutHex(id, 4, 0); AosOut.Ln;
		IdentifyController(bus, dev, fkt);
		INC(idx);
	END;
END ScanPCI;

PROCEDURE ScanPCIClass(class: LONGINT);
VAR idx, bus, dev, fkt: LONGINT;
BEGIN
	idx := 0;
	WHILE PCI.FindPCIClassCode(class, idx, bus, dev, fkt) = PCI.Done DO
		Show("Found PCI device on bus "); AosOut.Int(bus, 0); AosOut.String(", device "); AosOut.Int(dev, 0);
		AosOut.String(", function "); AosOut.Int(fkt, 0); AosOut.Ln;
		IdentifyController(bus, dev, fkt);
		INC(idx);
	END;
END ScanPCIClass;

PROCEDURE IdentifyControllers;
VAR
	class: LONGINT;
	str: ARRAY 32 OF CHAR;
	c: Controller;
BEGIN
	nofControllers := 2;
	AosBoot.GetConfig("ATADetect", str);
	IF str = "default" THEN
		Show("Scanning PCI bus for known ATA controllers..."); AosOut.Ln;
		(* Intel *)
		ScanPCI(8086H, 24DBH);		(* ICH5 IDE *)
		ScanPCI(8086H, 24D1H);		(* ICH5 SATA (82801EB) *)
		ScanPCI(8086H, 24DFH);		(* ICH5R SATA (82801ER) *)
		ScanPCI(8086H, 7111H);		(* PIIX/4 EIDE, VMWare *)
		ScanPCI(8086H, 7010H);		(* PIIX/3 (82371SB) *)
		ScanPCI(8086H, 2411H); 		(* 8xx Chipset IDE *)
		ScanPCI(8086H, 2421H);		(* IDE (82801AB) *)
		ScanPCI(8086H, 244BH);		(* IDE (82801E, U100) *)
		ScanPCI(8086H, 24CAH);		(* ICH4-M (82801DBM) *)
		ScanPCI(8086H, 248AH);		(* ICH3-M (82801CAM) *)
		ScanPCI(8086H, 2641H);		(* ICH6-M (82801FBM) *)
		ScanPCI(8086H, 2651H); 	(* ICH6-W (82801 FB/FW SATA) *)
		ScanPCI(8086H, 266FH);		(* ICH6 (82801 FB/FBM/FR/FW/FRW SATA *)
		(* Others *)
		ScanPCI(1106H, 0571H);		(* Asus A7V IDE *)
		ScanPCI(105AH, 0D30H);		(* Asus A7V Promise *)
		ScanPCI(1078H, 0102H);		(* Cyrix IDE *)
		ScanPCI(1166H, 0211H);		(* Serverworks *)
 	ELSIF str = "legacy" THEN
 		Show("Scanning PCI bus for legacy ATA controllers..."); AosOut.Ln;
		NEW(c, 1F0H, 3F0H, 0, 14);
		AddController(c);
		NEW(c, 170H, 370H, 0, 15);
		AddController(c);
	ELSE
		Show("Scanning PCI bus for IDE & SATA class devices ..."); AosOut.Ln;
		FOR class := 010100H TO 0101FFH DO ScanPCIClass(class); END;	(* IDE *)
		FOR class := 010600H TO 0106FFH DO ScanPCIClass(class); END;	(* SATA *)
		IF (str = "raid") OR (str = "raid+other") THEN
			Show("Scanning PCI bus for RAID class devices..."); AosOut.Ln;
			FOR class := 010400H TO 0104FFH DO ScanPCIClass(class); END;	(* RAID *)
		END;
		IF (str = "other") OR (str = "raid+other") THEN
			Show("Scanning PCI bus for PCI mass storage class devices..."); AosOut.Ln;
			FOR class := 018000H TO 0180FFH DO ScanPCIClass(class); END;	(* Mass Storage *)
		END;
	END;
END IdentifyControllers;

PROCEDURE GetOptions;
VAR str : ARRAY 32 OF CHAR;

	PROCEDURE CharacterInString(ch : CHAR; string : ARRAY OF CHAR) : BOOLEAN;
	VAR i : LONGINT;
	BEGIN
		FOR i := 0 TO LEN(string)-1 DO
			IF string[i] = ch THEN RETURN TRUE; END;
		END;
		RETURN FALSE;
	END CharacterInString;
	
BEGIN
	AosBoot.GetConfig("ATATrace", str);
	IF str # "" THEN
		Show("Trace option string: "); AosOut.String(str); AosOut.Ln;
		IF CharacterInString("0", str) THEN trace := trace + TraceCommands; END;
		IF CharacterInString("1", str) THEN trace := trace + TraceErrors; END;
		IF CharacterInString("2", str) THEN trace := trace + TraceAtapi; END;
		IF CharacterInString("3", str) THEN trace := trace + TraceSense; END;
		IF CharacterInString("4", str) THEN trace := trace + TraceBuffer; END;
		IF CharacterInString("5", str) THEN trace := trace + TraceInit; END;
	END;

	AosBoot.GetConfig("ATAForcePIO", str);
	IF str = "1" THEN
		ataForcePio := TRUE;
		Show("Force PIO mode for ATA devices"); AosOut.Ln;
	END;

	AosBoot.GetConfig("ATAPIForcePIO", str);
	IF str = "1" THEN
		atapiForcePio := TRUE;
		Show("Force PIO mode for ATAPI devices"); AosOut.Ln;
	END;
END GetOptions;

PROCEDURE Install*(par: ANY): ANY;
BEGIN
	IF ~installed THEN
		IF AosBoot.Trace THEN AosOut.Enter; AosOut.String("AosATA6Disks"); AosOut.Exit END;
		installed := TRUE;
		GetOptions;
		IdentifyControllers;
		IF AosBoot.Trace THEN AosOut.Enter; AosOut.String("installed"); AosOut.Exit END;
		ShowDevices();
	ELSE
		ShowDevices();
	END;
	RETURN NIL;
END Install;

PROCEDURE ShowCounter*(p: ANY): ANY;
BEGIN
	Show("IRQs: "); AosOut.Int(irqCount, 0); AosOut.Ln;
	AosOut.String("IRQ-Waits: "); AosOut.Int(expectedCount, 0); AosOut.Ln;
	RETURN NIL;
END ShowCounter;

PROCEDURE ResetCounter*(p: ANY): ANY;
BEGIN
	Show("Reset Counter"); AosOut.Ln;
	irqCount := 0;
	expectedCount := 0;
	RETURN NIL;
END ResetCounter;

PROCEDURE Show(string : ARRAY OF CHAR);
BEGIN
	AosOut.String("AosATADisks: "); AosOut.String(string);
END Show;

(* Clean up unloaded module. *)
PROCEDURE Cleanup;
VAR i: LONGINT; d: Device;
BEGIN
	(*AosOut.Ln;*)
	(*IF AosModules.shutdown = AosModules.None THEN*)
		FOR i := 0 TO MaxDevices-1 DO
			d := device[i];
			IF d # NIL THEN
				(*AosOut.String("Finalize "); AosOut.String(d.name); AosOut.Ln;*)
				d.Finalize
			END
		END;
		FOR i := 0 TO MaxControllers-1 DO
			IF (controller[i] # NIL) THEN
				(*AosOut.String("Finalize "); AosOutHex(controller[i].cmdbase, 4, 0); AosOut.Ln;*)
				controller[i].Finalize();
				controller[i] := NIL
			END
		END
	(*END*)
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	IF Install(NIL) = NIL THEN END;
END AosATADisks.

Error codes
2801	device select failed before issueing
2802	device select failed after issueing
2807	dma transfer timeout
2808	dma transfer failed
2809	dma transfer error
2812	identify atapi failed
2813	size 0 device
2814	identify failed
2815	bad controller port
2816	atapi reset failed
2817	ata set parameters failed
2819	pio read timeout
2820	pio read error
2821	pio read error
2822	pio write error
2823	pio write timeout
2824	pio write error
2825	identify ata geometry bad
2826	transfer out of range
2827	ATA: removable with no RMSN support
2828	ATAPI: removable with no RMSN support
2829	ATAPI: packet command failed
2830	ATAPI: transfer packet error (did not complete)
2831	ATAPI: transfer failed (no sense data)
2832	ATAPI: transfer failed (sense data available)
2833	ATAPI: unsupported packet size
2834	ATAPI: could not enable RMSN
2835	ATAPI: could not disable RMSN
2836	RMSN: get media status failed
2837	Eject failed
2838	Lock failed
2839	Unlock failed

AosATADisk.Install ~		S.Free AosATADisks ~

ATAErrors.Text
