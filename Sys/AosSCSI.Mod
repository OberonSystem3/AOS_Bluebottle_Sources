MODULE AosSCSI; (** AUTHOR "prk"; PURPOSE "Generic SCSI driver"; *)

(*
	Based on Native Oberon module SCSI.Mod by Patrik Reali
*)


IMPORT
		SYSTEM, AosBoot, AosOut, AosPlugins, AosDisks;

CONST
(** Debugging: Trace bits for "SCSIDebug" config string *)
	TraceSense* = 0;	(** 01H *)
	TraceDetection* = 1;	(** 02H *)

(** SCSI Commands*)	(*taken from scsi.h -> "http://lxr.linux.no/source/include/scsi/scsi.h" *)
	TestUnitReady* = 0X;
	RezeroUnit* = 1X;
	RequestSense* = 3X;
	Format* = 4X;
	ReadBlockLimits* = 5X;
	ReassignBlocks* = 7X;
	Read6* = 8X;
	Write6* = 0AX;
	Seek6* = 0BX;
	ReadReverse* = 0FX;
	WriteFilemarks* = 10X;
	Space* = 11X;
	Inquiry* = 12X;
	RecoverBufferedData* = 14X;
	ModeSelect* = 15X;
	Reserve* = 16X;
	Release* = 17X;
	Copy* = 18X;
	Erase* = 19X;
	ModeSense* = 1AX;
	StartStop* = 1BX;
	ReceiveDiagnostic* = 1CX;
	SendDiagnostic* = 1DX;
	AllowMediumRemoval* = 1EX;
	SetWindow* = 24X;
	ReadCapacity* = 25X;
	Read10* = 28X;
	Write10* = 2AX;
	Seek10* = 2BX;
	WriteVerify* = 2EX;
	Verify* = 2FX;
	SearchHigh* = 30X;
	SearchEqual* = 31X;
	SearchLow* = 32X;
	SetLimits* = 33X;
	PreFetch* = 34X;
	ReadPosition* = 34X;
	SynchronizeCache* = 35X;
	LockUnlockCache* = 36X;
	ReadDefectData* = 37X;
	MediumScan* = 38X;
	Compare* = 39X;
	CopyVerify* = 3AX;
	WriteBuffer* = 3BX;
	ReadBuffer* = 3CX;
	UpdateBlock* = 3DX;
	ReadLong* = 3EX;
	WriteLong* = 3FX;
	ChangeDefinition* = 40X;
	WriteSame* = 41X;
	ReadToc* = 43X;
	LogSelect* = 4CX;
	LogSense* = 4DX;
	ModeSelect10* = 55X;
	ModeSense10* = 05AX;
	Read12* = 0A8X;
	Write12* = 0AAX;
	WriteVerify12* = 0AEX;
	SearchHigh12* = 0B0X;
	SearchEqual12* = 0B1X;
	SearchLow12* = 0B2X;
	ReadElementStatus* = 0B8X;
	SendVolumeTag* = 0B6X;
	WriteLong2* = 0EAX;

(** SCSI Messages / 1 Byte *)
	MsgCmdComplete* = 00X;
	MsgExtended* = 01X;
	MsgSaveDataPointer* = 02X;
	MsgRestorePointers* = 03X;
	MsgDisconnect* = 04X;
	MsgInitiatorDetErr* = 05X;
	MsgAbort* = 06X;
	MsgMessageReject* = 07X;
	MsgNoop* = 08X;
	MsgParityError* = 09X;
	MsgLinkCmdComplete* = 0AX;
	MsgLinkCmdCompleteF* = 0BX;
	MsgBusDevReset* = 0CX;
	MsgAbortTag* = 0DX;
	MsgClearQueue* = 0EX;
	MsgInitRecovery* = 0FX;
	MsgRelRecovery* = 10X;
	MsgTermIOProc* = 11X;
	
(**SCSI Messages / 2 Bytes*)
	MsgSimpleQTag* = 20X;
	MsgHeadOfQTag* = 21X;
	MsgOrderedQTag* = 22X;
	MsgIgnoreWideResidue* = 23X;
	
	MsgIdentifyFlag* = 80X;
		
(**SCSI Messages / Extended*)
	MsgExtSdTr* = 01X;  MsgExtSdTrLen* = 03X;
	MsgExtWdTr* = 03X;  MsgExtWdTrLen* = 02X; MsgExtWdTr8Bit* = 0X; MsgExtWdTr16Bit* = 1X;

(**SCSI Sense Keys*)
	NoSense* = 0;  RecoveredError* = 1;  NotReady* = 2;  MediumError* = 3;  HardwareError* = 4;
	IllegalRequest* = 5;  UnitAttention* = 6;  DataProtect* = 7;

(** SCSI.Command, status:  value returned by the scsi status phase *)
	NotGood* = -1;  Good* = 0;  CheckCondition* = 2;  ConditionMet* = 4;  Busy* = 8;  Intermediate* = 10;
	IntermediateConditionMet* = 13;  ReservationConflict* = 18;  CommandTerminated* = 22;
	QueueFull* = 28;
	
(** SCSI.Command, result: additional information if status # Good *)
	OK* = 0;  NoConnect* = 1;  BusBusy* = 2;  TimeOut* = 3;  BadTarget* = 4;  Abort* = 5;
	Parity* = 6;  Error* = 7;  Reset* = 8;  BadIntr* = 9;  PassThrough* = 10;  SoftError* = 11;

(** SCSI Device class*)
	DirectAccess* = 0;  SequentialAccess* = 1; Printer* = 2; Processor* = 3; WriteOnce* = 4; CDRom* = 5;
	Scanner* = 6; Optical* = 7; MediumChanger* = 8; Communication* = 9; Unknown* = 1FH;
	
	DiskDevices = {DirectAccess, CDRom};
	
TYPE
(** SCSI Structures for the common commands *)
	InquiryData* = RECORD
		deviceClass*, ISO*, ECMA*, ANSI*: SHORTINT;
		w32*, w16*, sync*, link*, que*, rmb*: BOOLEAN;
		manufacturer*, product*, rev*: ARRAY 32 OF CHAR;
	END;
	
(** SCSI Command, all driver must accept this structure *)
	Command* = RECORD
		status*, result*: SHORTINT;
		target*, chan*, lun*: SHORTINT;	(**destination*)
		cmd*: ARRAY 12 OF CHAR;  clen*: SHORTINT;	(**command*)
		dataAddr*, dlen*: LONGINT;	(**data*)
		tag*: CHAR;	(*SCSI-II queued command tag*)
	END;

	Bus* = OBJECT
		VAR
			wide*: BOOLEAN;
			name*: ARRAY 6 OF CHAR;	(** "SCSIx" *)
			fullname*: ARRAY 64 OF CHAR;	(** bus adapter name *)
			next: Bus;
		
		PROCEDURE Submit*(VAR c: Command);
		BEGIN	HALT(99)	(*abstract*)
		END Submit;
		
	END Bus;

	EnumProc* = PROCEDURE(b: Bus; VAR stop: BOOLEAN);

	Disk* = OBJECT  (AosDisks.Device)
		VAR
			bus*: Bus;
			target*: SHORTINT;
			inquiry*: InquiryData;
			started: BOOLEAN;
			next*: Disk;
		
		PROCEDURE Transfer*(op, start, num: LONGINT; VAR data: ARRAY OF CHAR; ofs: LONGINT; VAR res: LONGINT);
		VAR  requ: Command;  str: ARRAY 32 OF CHAR;
		BEGIN
			IF (op = AosDisks.Read) OR (op = AosDisks.Write) THEN
				ASSERT(num < 10000H);
				IF op = AosDisks.Read THEN
					MakeCmd10(requ.cmd, Read10, 0, start, num, 0);
					str := "transfer/read"
				ELSE
					MakeCmd10(requ.cmd, Write10, 0, start, num, 0);
					str := "transfer/write"
				END;
				NewCmd(requ, target, 0, 10, SYSTEM.ADR(data[ofs]), num*blockSize);
				SubmitAndSense(bus, requ, 1, str, res);
				IF res = Good THEN
					res := AosDisks.Ok
				ELSE
					(*use internal res*)
				END
			ELSE
				res := AosDisks.Unsupported
			END
		END Transfer;
				
		PROCEDURE GetSize*(VAR size, res: LONGINT);
		VAR  blkSize: LONGINT;
		BEGIN
			DoReadCapacity(bus, target, 0, size, blkSize, res);
			IF size # 0 THEN
				IF blockSize = 0 THEN blockSize := blkSize ELSE  ASSERT(blockSize = blkSize)  END;
				res := AosDisks.Ok  
			END;
		END GetSize;

		PROCEDURE Handle*(VAR msg: AosDisks.Message; VAR res: LONGINT);
		BEGIN
			IF msg IS AosDisks.EjectMsg THEN
				res := AosDisks.Unsupported
			ELSIF msg IS AosDisks.LockMsg THEN
				PreventAllowRemoval(SELF, TRUE, res)
			ELSIF msg IS AosDisks.UnlockMsg THEN
				PreventAllowRemoval(SELF, FALSE, res)
			ELSE
				res := AosDisks.Unsupported
			END
		END Handle;

	END Disk;
	

VAR
	busList: Bus;
	busCount: LONGINT;
	
	diskList: Disk;
	diskCount: LONGINT;
	
	deviceClassName: ARRAY 32, 20 OF CHAR;
	trace: SET;


(* Debug *)

PROCEDURE DumpCmdStatus(stat, res: SHORTINT);
BEGIN
	CASE stat OF
	|  Good: AosOut.String("Good ")
	|  CheckCondition: AosOut.String("CheckCondition ")
	|  ConditionMet: AosOut.String("ConditionMet ")
	|  Busy: AosOut.String("Busy ")
	|  Intermediate: AosOut.String("Intermediate ")
	|  IntermediateConditionMet: AosOut.String("IntermediateConditionMet ")
	|  ReservationConflict: AosOut.String("ReservationConflict ")
	|  CommandTerminated: AosOut.String("CommandTerminated ")
	|  QueueFull: AosOut.String("QueueFull ")
	ELSE AosOut.String("unk"); AosOut.Int(stat, 0)
	END;
	CASE res OF
	| OK: AosOut.String("OK")
	| NoConnect: AosOut.String("NoConnect")
	| BusBusy: AosOut.String("BusBusy")
	| TimeOut: AosOut.String("TimeOut")
	| BadTarget: AosOut.String("BadTarget")
	| Abort: AosOut.String("Abort")
	| Parity: AosOut.String("Parity")
	| Error: AosOut.String("Error")
	| Reset: AosOut.String("Reset")
	| BadIntr: AosOut.String("BadIntr")
	| PassThrough: AosOut.String("PassThrough")
	| SoftError: AosOut.String("SoftError")
	ELSE AosOut.String("unk"); AosOut.Int(res, 0)
	END;
	AosOut.Ln;
END DumpCmdStatus;

PROCEDURE WriteBus(bus: Bus);
BEGIN	AosOut.String(bus.name); AosOut.String(": ")
END WriteBus;

PROCEDURE WriteDisk(disk: Disk);
BEGIN  AosOut.String(disk.name); AosOut.String(": ")
END WriteDisk;

PROCEDURE WriteDisk2(bus: Bus;  target: LONGINT);
BEGIN  AosOut.String(bus.name); AosOut.Char("."); AosOut.Int(target, 0); AosOut.String(": ")
END WriteDisk2;

PROCEDURE WriteConfig(d: Disk; VAR c: InquiryData);
BEGIN
	WriteDisk(d); AosOut.String("Inquiry: "); AosOut.String("SCSI-");
	IF c.ANSI = 0 THEN
		AosOut.Char("1")
	ELSIF c.ANSI = 1 THEN
		AosOut.String("SCC")
	ELSE
		AosOut.Int(c.ANSI, 0)
	END;
	IF c.rmb THEN AosOut.String(" rmb")  END;
	IF c.w32 THEN AosOut.String(" 32bit") END;
	IF c.w16 THEN AosOut.String(" 16bit") END;
	IF c.sync THEN AosOut.String(" sync") END;
	AosOut.Ln
END WriteConfig;


(** Useful SCSI Commands *)

PROCEDURE MakeCmd6(VAR c: ARRAY OF CHAR;  op: CHAR;  lun, lba, len, ctrl: LONGINT);
BEGIN
	ASSERT((0 <= lun) & (lun < 8), 100);
	ASSERT((0 <= lba) & (lba < 200000H), 101);
	ASSERT((0 <= len) & (len < 100H), 102);
	c[0] := op;
	c[1] := CHR(SYSTEM.LSH(lun, 5) + SYSTEM.LSH(lba, -16));
	c[2] := CHR(SYSTEM.LSH(lba, -8));
	c[3] := CHR(lba);
	c[4] := CHR(len);
	c[5] := CHR(ctrl)
END MakeCmd6;

PROCEDURE MakeCmd10(VAR c: ARRAY OF CHAR;  op: CHAR;  lun, lba, len, ctrl: LONGINT);
BEGIN
	ASSERT((0 <= len) & (len < 10000H), 100);
	c[0] := op;
	c[1] := CHR(SYSTEM.LSH(lun, 5));
	c[2] := CHR(SYSTEM.LSH(lba, -24));
	c[3] := CHR(SYSTEM.LSH(lba, -16));
	c[4] := CHR(SYSTEM.LSH(lba, -8));
	c[5] := CHR(lba);
	c[6] := 0X;	(*reserved*)
	c[7] := CHR(SYSTEM.LSH(len, -8));
	c[8] := CHR(len);
	c[9] := CHR(ctrl)
END MakeCmd10;

PROCEDURE MakeCmd12(VAR c: ARRAY OF CHAR;  op: CHAR;  lun, lba, len, ctrl: LONGINT);
BEGIN
	c[0] := op;
	c[1] := CHR(SYSTEM.LSH(lun, 5));
	c[2] := CHR(SYSTEM.LSH(lba, -24));
	c[3] := CHR(SYSTEM.LSH(lba, -16));
	c[4] := CHR(SYSTEM.LSH(lba, -8));
	c[5] := CHR(lba);
	c[6] := CHR(SYSTEM.LSH(len, -24));
	c[7] := CHR(SYSTEM.LSH(len, -16));
	c[8] := CHR(SYSTEM.LSH(len, -8));
	c[9] := CHR(len);
	c[10] := 0X;	(*reserved*)
	c[11] := CHR(ctrl)
END MakeCmd12;

PROCEDURE NewCmd(VAR c: Command; t, l: SHORTINT; cl, da, dl: LONGINT);
BEGIN
	c.clen := SHORT(SHORT(cl));  c.dataAddr := da;  c.dlen := dl;
	c.target := t;  c.lun := l;  c.chan := 0;
END NewCmd;

PROCEDURE DoSense*(b: Bus;  target,  lun: SHORTINT;  VAR key, code, res: LONGINT);
VAR requ: Command; data: ARRAY 36 OF CHAR;
BEGIN
	MakeCmd6(requ.cmd, RequestSense, lun, 0, 36, 0);
	NewCmd(requ, target, lun, 6, SYSTEM.ADR(data), 36);
	b.Submit(requ);
	key := ORD(data[2]) MOD 16;
	code := 100H*ORD(data[12]) + ORD(data[13]);
	IF TraceSense IN trace THEN
		WriteBus(b);  AosOut.String(" RequestSense"); AosOut.Ln;
		AosOut.Memory(SYSTEM.ADR(data[0]), 36); AosOut.Ln
	END;
	res := requ.status
END DoSense;

PROCEDURE SubmitAndSense*(d: Bus;  VAR requ: Command;  maxtry: LONGINT;  msg: ARRAY OF CHAR;  VAR res: LONGINT);
VAR key, code, kind: LONGINT; first: BOOLEAN;
BEGIN
	first := TRUE;
	REPEAT
		d.Submit(requ);
		IF requ.status =  CheckCondition THEN
			DoSense(d, requ.target, requ.lun, key, code, res);
			kind := ASH(code, -8);
			WriteDisk2(d, requ.target); AosOut.String(msg);
			IF (key=6) & (code = 2900H) & first THEN	(*power on, ignore*)
				AosOut.String(" / power on"); AosOut.Ln;
				INC(maxtry);  first := FALSE
			ELSIF code = 0401H THEN	(*lun is in process of becoming ready*)
				AosOut.String(" / getting ready"); AosOut.Ln;
				INC(maxtry);  (*skip*)
			ELSIF kind = 3AH THEN
				res := AosDisks.MediaMissing;
				RETURN
			ELSIF kind = 28H THEN
				res := AosDisks.MediaChanged;
				RETURN 
			ELSIF (key#0) OR (code#0) THEN
				AosOut.String(" / sense -> "); AosOut.Int(key, 3); AosOut.Hex(code, 0); AosOut.Ln;
				res := NotGood;
				RETURN
			ELSE
				AosOut.String(" / no sense"); AosOut.Ln;
				INC(maxtry)
			END
		ELSIF requ.status # Good THEN
			WriteDisk2(d, requ.target);  AosOut.String(msg);  AosOut.String(" / ");
			DumpCmdStatus(requ.status, requ.result);
		END;
		DEC(maxtry);
	UNTIL (requ.status = Good) OR (maxtry <= 0);
	res := requ.status
END SubmitAndSense;

PROCEDURE DoTestUnitReady*(b: Bus;  target, lun: SHORTINT;  VAR res: LONGINT);
VAR requ: Command;
BEGIN
	MakeCmd6(requ.cmd, TestUnitReady, lun, 0, 0, 0);
	NewCmd(requ, target, lun, 6, 0, 0);
	b.Submit(requ);
	res := requ.status
END DoTestUnitReady;

PROCEDURE DoInquiry*(b: Bus;  target, lun: SHORTINT; VAR inq: InquiryData; VAR res: LONGINT);
VAR requ: Command; data: ARRAY 36 OF CHAR; i: LONGINT;
BEGIN
	MakeCmd6(requ.cmd, Inquiry, lun, 0, 36, 0);
	NewCmd(requ, target, 0, 6, SYSTEM.ADR(data), 36);
	b.Submit(requ);
	res := requ.status;
	IF res = Good THEN
		IF TraceDetection IN trace THEN
			WriteBus(b);  AosOut.String("Inquiry"); AosOut.Ln;
			AosOut.Memory(SYSTEM.ADR(data[0]), 36); AosOut.Ln
		END;
		inq.deviceClass := SHORT(ORD(data[0]) MOD 32);
		inq.rmb := 7 IN SYSTEM.VAL(SET, data[1]);
		inq.ANSI := SHORT(ORD(data[2]) MOD 8);
		inq.ECMA := SHORT(SYSTEM.LSH(ORD(data[2]), -3) MOD 8);
		inq.ISO  := SHORT(SYSTEM.LSH(ORD(data[2]), -6) MOD 4);
		inq.w32 := 6 IN SYSTEM.VAL(SET, data[7]);
		inq.w16 := 5 IN SYSTEM.VAL(SET, data[7]);
		inq.sync := 4 IN SYSTEM.VAL(SET, data[7]);
		inq.link := 3 IN SYSTEM.VAL(SET, data[7]);
		inq.que := 1 IN SYSTEM.VAL(SET, data[7]);
		SYSTEM.MOVE(SYSTEM.ADR(data[8]), SYSTEM.ADR(inq.manufacturer), 8); 
		i := 7;  WHILE (i >= 0) & (inq.manufacturer[i] = 20X) DO  DEC(i)  END; inq.manufacturer[i+1]:= 0X;
		SYSTEM.MOVE(SYSTEM.ADR(data[16]), SYSTEM.ADR(inq.product), 16);
		i := 15;  WHILE (i >= 0) & (inq.product[i] = 20X) DO  DEC(i)  END; inq.product[i+1]:= 0X;
		SYSTEM.MOVE(SYSTEM.ADR(data[32]), SYSTEM.ADR(inq.rev), 4);
		i := 3;  WHILE (i >= 0) & (inq.rev[i] = 20X) DO  DEC(i)  END; inq.rev[i+1]:= 0X;
	ELSIF TraceDetection IN trace THEN
		WriteDisk2(b, target);  AosOut.String("Inquiry failed with "); DumpCmdStatus(requ.status, requ.result)
	END
END DoInquiry;

PROCEDURE DoStartStopUnit*(b: Bus;  target, lun: SHORTINT; start: BOOLEAN;  VAR res: LONGINT);
VAR	requ: Command;
BEGIN
	MakeCmd6(requ.cmd, StartStop, 0, 0, 0, 0);
	IF start THEN requ.cmd[4]:= 1X ELSE requ.cmd[4]:= 0X END;
	NewCmd(requ, target, lun, 6, 0, 0);
	b.Submit(requ);
	res := requ.status
END DoStartStopUnit;

PROCEDURE PreventAllowRemoval(d: Disk;  prevent: BOOLEAN;  VAR res: LONGINT);
VAR	requ: Command;
BEGIN
	IF AosDisks.Removable IN d.flags THEN
		MakeCmd6(requ.cmd, AllowMediumRemoval, 0, 0, 0, 0);
		IF prevent THEN  requ.cmd[4]:= 1X  ELSE  requ.cmd[4]:= 0X  END;
		NewCmd(requ, d.target, 0, 6, 0, 0);
		SubmitAndSense(d.bus, requ, 1, "PreventAllowRemoval", res)
	ELSE
		res := AosDisks.Unsupported
	END
END PreventAllowRemoval;

PROCEDURE DoReadCapacity*(b: Bus;  target, lun: SHORTINT;  VAR capacity, blockSize: LONGINT;  VAR res: LONGINT);
VAR  requ: Command;  data: ARRAY 128 OF CHAR;  i: LONGINT;
BEGIN
	capacity := 0;  blockSize := 0;
	IF (b # NIL) THEN
		MakeCmd10(requ.cmd, ReadCapacity, 0, 0, 0, 0);
		NewCmd(requ, target, lun, 10, SYSTEM.ADR(data), 16);
		SubmitAndSense(b, requ, 1, "ReadCapacity", res);
		IF res # Good THEN  RETURN   END;
		FOR i := 0 TO 3 DO
			capacity := capacity*100H + ORD(data[i]);
			blockSize := blockSize*100H + ORD(data[4+i])
		END;
		INC(capacity)
	END
END DoReadCapacity;

PROCEDURE InitDisk(d: Disk);
VAR  requ: Command;  data: ARRAY 128 OF CHAR;  end, i, res: LONGINT; 
BEGIN
	MakeCmd6(requ.cmd, ModeSense, 0, 0, 128, 0);
	NewCmd(requ, d.target, 0, 6, SYSTEM.ADR(data), 128);
	SubmitAndSense(d.bus, requ, 1, "SenseDevice", res);
	IF TraceDetection IN trace THEN
		WriteBus(d.bus);  AosOut.String(": ModeSense"); AosOut.Ln;
		AosOut.Memory(SYSTEM.ADR(data[0]), 64); AosOut.Ln
	END;
	IF (res = Good) & (ORD(data[3]) = 8) THEN
		d.blockSize := ORD(data[4+7]);
		d.blockSize := d.blockSize + SYSTEM.LSH(ORD(data[4+5]), 16);
		d.blockSize := d.blockSize + SYSTEM.LSH(ORD(data[4+6]), 8);
	ELSE
		AosOut.String("Sense failed"); AosOut.Int(res, 3); AosOut.Ln;
		AosOut.Memory(SYSTEM.ADR(data[0]), 128); AosOut.Ln;
		d.blockSize := 0
	END;
END InitDisk;

PROCEDURE TerminateDisk(d: Disk);
VAR  res: LONGINT;
BEGIN
	IF d.started THEN
		DoStartStopUnit(d.bus, d.target, 0, FALSE, res);
	END;
	IF d.inquiry.deviceClass IN DiskDevices THEN  AosDisks.registry.Remove(d)  END;
END TerminateDisk;

PROCEDURE NumToChar(i: LONGINT): CHAR;
VAR  ch: CHAR;
BEGIN
	ASSERT(i >= 0);
	IF i < 10 THEN
		ch := CHR(i + ORD("0"))
	ELSE
		ch := CHR(i + (ORD("A") - 10))
	END;
	RETURN ch
END NumToChar;

(** SCSI Bus Handling *)

PROCEDURE InitBus(bus: Bus);
VAR  i: SHORTINT;  d: Disk; data: InquiryData;  max, j, k, c, res: LONGINT;  name: AosPlugins.Name;
BEGIN
	i := 0;
	IF bus.wide THEN  max := 16  ELSE  max := 8  END;
	WHILE i < max DO
		DoInquiry(bus, i, 0, data, res);
		IF res = Good THEN	(*device detected*)
			NEW(d);
			name := "SCSIx.x";
			name[4] := bus.name[4];  name[6] := NumToChar(i);
			d.SetName(name);
			j := 0;
			WHILE data.manufacturer[j] # 0X DO  d.desc[j] := data.manufacturer[j]; INC(j)  END;
			d.desc[j] := 20X; INC(j);
			k := 0;
			WHILE data.product[k] # 0X DO  d.desc[k+j] := data.product[k];  INC(k)  END;
			d.desc[k+j] := 0X;
			d.flags := {};
			IF data.rmb THEN  INCL(d.flags, AosDisks.Removable)  END;

			d.bus := bus;  d.target := i;  d.inquiry := data;
			InitDisk(d);
			
			WriteDisk(d);
			AosOut.String(data.manufacturer);  AosOut.Char(" ");
			AosOut.String(data.product);  AosOut.String(" [");
			AosOut.String(deviceClassName[data.deviceClass]);  AosOut.String(", ");
			IF data.rmb THEN  AosOut.String("rmb, ")  END;
			AosOut.String("bs=");  AosOut.Int(d.blockSize, 0);
			AosOut.Char("]"); AosOut.Ln;

			IF data.deviceClass IN DiskDevices THEN
				AosDisks.registry.Add(d, res);
				ASSERT(res = AosPlugins.Ok)
			END;
			d.next := diskList;  diskList := d
		END;
		INC(i)
	END
END InitBus;

PROCEDURE RegisterBus*(bus: Bus);
BEGIN
	bus.name := "SCSIx";
	bus.name[4] := NumToChar(busCount);  INC(busCount);
	bus.next := busList; busList := bus;
	InitBus(bus);
END RegisterBus;

PROCEDURE RemoveBus*(b: Bus);
VAR p, q: Bus; s, t: Disk;
BEGIN
		(*remove driver from list*)
	IF busList = NIL THEN RETURN END;
	IF busList = b THEN
		busList := b.next
	ELSE
		q := busList; p := q.next;
		WHILE (p#NIL) & (p#b) DO  q := p; p := p.next  END;
		IF p#NIL  THEN q.next := p.next  END
	END;
		(*invalidate disks*)
	WHILE (diskList # NIL) & (diskList.bus = b) DO
		TerminateDisk(diskList); diskList := diskList.next
	END;
	IF diskList # NIL THEN
		s := diskList; t := s.next;
		WHILE t # NIL DO
			IF t.bus = b THEN  TerminateDisk(t); t := t.next; s.next := t
			ELSE s := t; t := t.next
			END
		END
	END;
END RemoveBus;

PROCEDURE FindBus*(name: ARRAY OF CHAR): Bus;
VAR p: Bus;
BEGIN
	p := busList;
	WHILE (p # NIL) & (p.name # name) DO  p := p.next  END;
	RETURN p
END FindBus;

PROCEDURE EnumerateBus*(proc: EnumProc);
VAR p: Bus; stop: BOOLEAN;
BEGIN
	stop := FALSE; p := busList;
	WHILE ~stop & (p#NIL) DO
		proc(p, stop);
		p := p.next
	END
END EnumerateBus;

(** Install module *)

PROCEDURE Install*;
BEGIN
END Install;

PROCEDURE Init;
VAR  str: ARRAY 32 OF CHAR;  i: LONGINT;
BEGIN
	AosBoot.GetConfig("SCSIDebug", str);
	i := 0;
	trace := SYSTEM.VAL(SET, AosBoot.StrToInt(i, str));
	IF trace # {} THEN
		AosOut.String("SCSIDebug = "); AosOut.Hex(SYSTEM.VAL(LONGINT, trace),0); AosOut.Ln
	END;
END Init;

BEGIN
	AosOut.String("SCSI - 1.0 / prk"); AosOut.Ln;
	diskCount := 0;  diskList := NIL;
	busCount := 0;  busList := NIL;
	Init;
	deviceClassName[DirectAccess] := "direct-access";
	deviceClassName[SequentialAccess] := "sequential-access";
	deviceClassName[Printer] := "printer";
	deviceClassName[Processor] := "processor";
	deviceClassName[WriteOnce] := "write-once";
	deviceClassName[CDRom] := "cd-rom";
	deviceClassName[Scanner] := "scanner";
	deviceClassName[Optical] := "optical";
	deviceClassName[MediumChanger] := "medium changer";
	deviceClassName[Communication] := "communications";
	deviceClassName[Unknown] := "Unknown";
END AosSCSI.

System.Free AosSCSI ~

