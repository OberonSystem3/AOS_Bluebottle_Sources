(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosATADisks; (** AUTHOR "pjm/prk"; PURPOSE "ATA disk driver (ATAPI part by prk)"; *)

(* 
Version based on AosDisks

Aos ATA disk driver with Intel 82371SB (PIIX3) bus-mastering support (e.g. 440FX chipset).
Based on Native Oberon driver by Christian Plattner, Patrik Reali and Pieter Muller

References:
	1. T13/1153D Rev. 17, AT Attachment with Packet Interface Extension (ATA/ATAPI-4).
	2. SFF-8020i Rev. 2.6 (Proposed), ATA Packet Interface for CD-ROMs.
*)

IMPORT SYSTEM, AosBoot, AosOut, AosMemory, AosModules, AosInterrupts, AosKernel, AosActive, AosPlugins, AosDisks, PCI;

CONST
	Name = "IDE";
	
	MaxControllers = 2;	(* <= 10 *)
	MaxDevices = 2*MaxControllers;
	MaxTries = 5;
	
	BMEnabled = TRUE;	(* check for bus-master chipset *)
	OverrideBIOS = TRUE;	(* enable bus-master even if BIOS did not *)
	PrimaryEnabled = TRUE;	(* disable for testing *)
	SecondaryEnabled = TRUE;	(* disable for testing *)
	UseConfigParams = TRUE;	(* disable for testing *)
	TraceStatus = TRUE;	(* show error information *)
	TraceIdentify = FALSE;	(* show identify information *)
	SelectWait = FALSE;	(* wait before select *)
	EarlyBug = TRUE;	(* temporary workaround for early interrupts *)
	TraceAtapi = FALSE;	(* show atapi commands *)
	TraceSense = FALSE;	(* show atapi sense results *)
	TraceRMSN = FALSE;	(* show RMSN commands *)
	FlushATAPISense = TRUE;	(* flush ATAPI sense buffer on start-up *)

	SelectTimeout = 5000;	(* ms *)
	IOTimeout = 10000;	(* ms *)
	IdentifyTimeout = 500;	(* ms *)
	ResetTimeout = 1000;	(* ms *)
	
	MaxTransfer = 256;	(* <= 256 (128KB) *)
	MaxPRD = 3;	(* <= 4 *)
	BS = 512;
	MinLBA = 8000000;	(* (> 0) if reported size larger than this, use LBA mode *)
	
	PageSize = 4096;
	
	AtapiBit = 0; RemovableBit = 1; DMABit = 2; LBABit = 3; RMSNBit = 4; Packet16Bit = 5;
	ERR = 0;  DRQ = 3;  DRDY = 6;  BSY = 7;
	
TYPE
	CHS = RECORD
		cyls, hds, spt: LONGINT
	END;
	
	ID = RECORD
		type: SET;
		ver, devtype: LONGINT;
		model: ARRAY 44 OF CHAR
	END;
	
	Packet = ARRAY 16 OF CHAR;
	
TYPE
	Device = OBJECT (AosDisks.Device)
		VAR
			controller: Controller;
			dev: LONGINT;	(* 0 or 1 *)
			size: LONGINT;	(* total size *)
			chs: CHS;	(* for controller *)
			getpar: CHS;	(* for GetParams *)
			id: ID;
			init: BOOLEAN;	(* initialized? *)
		
		PROCEDURE Transfer(op, block, num: LONGINT; VAR data: ARRAY OF CHAR; ofs: LONGINT; VAR res: LONGINT);
		BEGIN
			ASSERT((op = AosDisks.Read) OR (op = AosDisks.Write));
			controller.Transfer(SELF, op = AosDisks.Read, block, num, data, ofs, res)
		END Transfer;
		
		PROCEDURE GetSize(VAR size, res: LONGINT);
		BEGIN
			res := AosDisks.Unsupported;
			IF (RemovableBit IN id.type) & (AtapiBit IN id.type) THEN
				controller.GetATAPISize(SELF, blockSize, SELF.size, res);
				size := SELF.size
			ELSE
				size := SELF.size; res := AosDisks.Ok
			END
		END GetSize;
		
		PROCEDURE Handle(VAR msg: AosDisks.Message; VAR res: LONGINT);
		BEGIN
			res := AosDisks.Unsupported;
			IF msg IS AosDisks.GetGeometryMsg THEN
				IF ~(AtapiBit IN id.type) THEN
					WITH msg: AosDisks.GetGeometryMsg DO
						msg.cyls := getpar.cyls; msg.hds := getpar.hds; msg.spt := getpar.spt
					END;
					res := AosDisks.Ok
				END
			ELSE
				controller.Handle(SELF, msg, res)
			END
		END Handle;
		
	END Device;

TYPE
	Interrupt = OBJECT
		VAR
			timer: AosKernel.MilliTimer;
			int: LONGINT;
			interrupt, timeout: BOOLEAN;
			clock: AosActive.Timer;
		
		PROCEDURE HandleInterrupt;
		BEGIN {EXCLUSIVE}
			interrupt := TRUE
		END HandleInterrupt;
		
		PROCEDURE HandleTimeout;
		VAR ms: LONGINT;
		BEGIN {EXCLUSIVE}
			ms := AosKernel.Left(timer);
			IF ms <= 0 THEN
				timeout := TRUE
			ELSE
				AosOut.Enter; AosOut.String("ATA: Timer early "); AosOut.Int(ms, 1); AosOut.Exit;
				AosActive.SetTimeout(clock, SELF.HandleTimeout, ms)
			END
		END HandleTimeout;
		
		PROCEDURE Wait(ms: LONGINT): BOOLEAN;
		BEGIN {EXCLUSIVE}
			AosKernel.SetTimer(timer, ms);
			AosActive.SetTimeout(clock, SELF.HandleTimeout, ms);	(* set or reset timeout *)
			timeout := FALSE;
			AWAIT(interrupt OR timeout);
			interrupt := FALSE;
			RETURN ~timeout
		END Wait;
		
		PROCEDURE Reset;
		BEGIN
			IF interrupt THEN INC(Nunexpected) END;
			interrupt := FALSE
		END Reset;
		
		PROCEDURE &Init(irq: LONGINT);
		BEGIN
			interrupt := FALSE; int := AosInterrupts.IRQ0 + irq;
			NEW(clock);
			AosActive.InstallHandler(SELF.HandleInterrupt, int)
		END Init;
		
	END Interrupt;

TYPE
	PRDT = POINTER TO RECORD
		prd: ARRAY MaxPRD OF RECORD	(* aligned on 32-byte boundary, see Intel 290550-002 sec. 2.7.3 *)
			physAdr, size: LONGINT
		END
	END;
	
	Controller = OBJECT
		VAR
			port, port2, irq, bmbase: LONGINT;
			interrupt: Interrupt;
			prdtPhysAdr: LONGINT;
			prdt: PRDT;

		PROCEDURE Transfer(dev: Device; read: BOOLEAN; lba, num: LONGINT; VAR data: ARRAY OF CHAR; ofs: LONGINT; VAR res: LONGINT);
		VAR ctrl: Controller; bufAdr, num1, try, sense, physAdr: LONGINT; pkt: Packet;
		BEGIN {EXCLUSIVE}
			ctrl := SELF; bufAdr := SYSTEM.ADR(data[ofs]);
			IF (lba >= 0) & (num >= 0) & (lba < dev.size) & (lba+num <= dev.size) THEN
				ASSERT(num*dev.blockSize <= LEN(data)-ofs);	(* range check *)
				res := SelectDevice(ctrl.port, dev.dev, SelectTimeout);
				IF (res = 0) & ~dev.init THEN	(* initialize *)
					res := InitDevice(ctrl.port, ctrl.port2, dev.dev, dev.id.type, dev.chs);
					dev.init := res = 0
				END;
				WHILE (res = 0) & (num > 0) DO
					try := MaxTries; num1 := MaxTransfer;
					IF num1 > num THEN num1 := num END;
					REPEAT
						IF AtapiBit IN dev.id.type THEN
							IF read THEN
								ATAPIComposePacket(pkt, 28X, lba, num)
							ELSE
								ATAPIComposePacket(pkt, 2AX, lba, num)
							END;
							res := ATAPISubmit(port, port2, pkt, read, bufAdr, num*dev.blockSize, sense)
						ELSIF (ctrl.bmbase # 0) & ~ODD(bufAdr) & GetPhysAdr(bufAdr, num1*BS, physAdr) THEN
							res := TransferDMA(dev, read, lba, num1, physAdr)
						ELSE
							IF read THEN res := ReadPIO(dev, lba, num1, bufAdr)
							ELSE res := WritePIO(dev, lba, num1, bufAdr)
							END
						END;
						DEC(try)
					UNTIL (res = 0) OR (try = 0);
					INC(lba, num1); DEC(num, num1); INC(bufAdr, BS*num1)
				END
			ELSE
				AosOut.Enter; AosOut.String("ATA: out of range ");
				AosOut.Int(lba, 1); AosOut.Char(" "); AosOut.Int(num, 1); AosOut.Char(" ");
				AosOut.Int(dev.size, 1); AosOut.Char(" "); AosOut.String(dev.name); AosOut.Exit;
				res := 2826	(* transfer out of range *)
			END
		END Transfer;
		
		(* GetATAPISize - query Device size from the controller, Removable+ATAPI only because size cannot be detected during installation *)
		
		PROCEDURE GetATAPISize(dev: Device; VAR blockSize, size, res: LONGINT);
			VAR type: SET;
		BEGIN {EXCLUSIVE}
			type := dev.id.type;
			ASSERT((RemovableBit IN type) & (AtapiBit IN type));
			res := SelectDevice(port, dev.dev, SelectTimeout);
			IF res = 0 THEN
				res := ATAPITestReady(port, port2);
				IF res = 0 THEN
					res := ATAPIReadCapacity(port, port2, blockSize, size);
					IF (res = 0) & (dev.id.devtype = 5) & (blockSize # 2048) THEN  blockSize := 2048  END;	(* user data field only *)
				END
			END
		END GetATAPISize;
		
		(* Handle - Handle messages that require a communication with the controller, others are handled directly by the device *)
		
		PROCEDURE Handle(dev: Device; VAR msg: AosDisks.Message; VAR res: LONGINT);
			VAR type: SET;
		BEGIN {EXCLUSIVE}
			type := dev.id.type;
			res := SelectDevice(port, dev.dev, SelectTimeout);
			IF res = 0 THEN
				res := AosDisks.Unsupported;
				IF msg IS AosDisks.LockMsg THEN
					IF (RemovableBit IN type) THEN
						IF (RMSNBit IN type) THEN
							res := RMSNEnable(port);
							IF (res = 0) & (AtapiBit IN type) THEN	(* flush messages *)
								ATAPIFlushSenses(port, port2)
							END
						ELSIF ~(AtapiBit IN type) THEN
							res := 2838;
							IF ExecuteATACommand(port, port2, 0DEX) THEN res := 0 END	(* media lock *)
						END
					END
				ELSIF (msg IS AosDisks.UnlockMsg) THEN
					IF (RemovableBit IN type) THEN
						IF (RMSNBit IN type) THEN
							res := RMSNDisable(port)
						ELSIF ~(AtapiBit IN type) THEN
							res := 2839;
							IF ExecuteATACommand(port, port2, 0DFX) THEN res := 0 END	(* media unlock *)
						END
					END
				ELSIF (msg IS AosDisks.EjectMsg) THEN
					IF (RemovableBit IN type) THEN
						res := EjectMedia(port, port2, AtapiBit IN type)
					END
				END
			END
		END Handle;
		
	END Controller;

VAR
	controller: ARRAY MaxControllers OF Controller;
	device: ARRAY MaxDevices OF Device;
	Nunexpected: LONGINT;	(* number of unexpected interrupts *)

PROCEDURE GetPhysAdr(bufAdr, size: LONGINT; VAR physAdr: LONGINT): BOOLEAN;
BEGIN
	physAdr := AosMemory.PhysicalAdr(bufAdr, size);
	RETURN physAdr # AosMemory.NilAdr
END GetPhysAdr;

PROCEDURE WriteStatus(msg: ARRAY OF CHAR; port: LONGINT);
VAR ch: CHAR; t: LONGINT;
BEGIN
	IF TraceStatus THEN
		AosOut.String(msg); AosOut.String(" ctrl="); AosOut.Hex(port, 8);
		SYSTEM.PORTIN(port+6, ch);
		AosOut.String(" drv="); AosOut.Int(ORD(ch) DIV 10H MOD 2, 1);
		IF ODD(ORD(ch) DIV 40H) THEN
			AosOut.String(" lba=");
			t := ASH(ORD(ch) MOD 10H, 24);
			SYSTEM.PORTIN(port+5, ch); INC(t, ASH(ORD(ch), 16));
			SYSTEM.PORTIN(port+4, ch); INC(t, ASH(ORD(ch), 8));
			SYSTEM.PORTIN(port+3, ch); INC(t, ORD(ch));
			AosOut.Int(t, 1)
		ELSE
			AosOut.String(" hd="); AosOut.Int(ORD(ch) MOD 10H, 1);
			SYSTEM.PORTIN(port+3, ch);
			AosOut.String(" sec="); AosOut.Int(ORD(ch), 1);
			SYSTEM.PORTIN(port+5, ch); t := ASH(ORD(ch), 8);
			SYSTEM.PORTIN(port+4, ch); INC(t, ORD(ch));
			AosOut.String(" cyl="); AosOut.Int(t, 1)
		END;
		SYSTEM.PORTIN(port+1, ch);
		AosOut.String(" err="); AosOut.Hex(ORD(ch), -2);
		SYSTEM.PORTIN(port+7, ch);
		AosOut.String(" stat="); AosOut.Hex(ORD(ch), -2)
	END
END WriteStatus;

(* Wait for specified value of controller status bits. *)

PROCEDURE WaitStatus(port: LONGINT; mask, expect, bad: SET; ms: LONGINT): BOOLEAN;
VAR t: AosKernel.MilliTimer; s: SET; ch: CHAR;
BEGIN
	AosKernel.SetTimer(t, ms);
	REPEAT
		SYSTEM.PORTIN(port+7, ch); s := SYSTEM.VAL(SET, LONG(ORD(ch)))
	UNTIL (s * mask = expect) OR (s * bad # {}) OR AosKernel.Expired(t);
	IF TraceStatus & ((s * bad # {}) OR (s * mask # expect)) THEN
		ms := AosKernel.Elapsed(t);
		WriteStatus("ATA: Status", port);
		AosOut.String(" s="); AosOut.Hex(SYSTEM.VAL(LONGINT, s), -2);
		AosOut.String(" m="); AosOut.Hex(SYSTEM.VAL(LONGINT, mask), -2);
		AosOut.String(" e="); AosOut.Hex(SYSTEM.VAL(LONGINT, expect), -2);
		AosOut.String(" b="); AosOut.Hex(SYSTEM.VAL(LONGINT, bad), -2);
		AosOut.String(" ms="); AosOut.Int(ms, 1);
		AosOut.Ln
	END;
	RETURN (s * mask = expect) & (s * bad = {})
END WaitStatus;

(* Wait for specified value of controller status bits using the alternate status bits (don't clear interrupts). *)

PROCEDURE WaitAltStatus(port, port2: LONGINT; mask, expect, bad: SET; ms: LONGINT): BOOLEAN;
VAR t: AosKernel.MilliTimer; s: SET; ch: CHAR;
BEGIN
	AosKernel.SetTimer(t, ms);
	REPEAT
		SYSTEM.PORTIN(port2, ch); s := SYSTEM.VAL(SET, LONG(ORD(ch)));
	UNTIL (s * mask = expect) OR (s * bad # {}) OR AosKernel.Expired(t);
	IF TraceStatus & ((s * bad # {}) OR (s * mask # expect)) THEN
		ms := AosKernel.Elapsed(t);
		AosOut.String("ATA: s="); AosOut.Hex(SYSTEM.VAL(LONGINT, s), -2);
		AosOut.String(" m="); AosOut.Hex(SYSTEM.VAL(LONGINT, mask), -2);
		AosOut.String(" e="); AosOut.Hex(SYSTEM.VAL(LONGINT, expect), -2);
		AosOut.String(" b="); AosOut.Hex(SYSTEM.VAL(LONGINT, bad), -2);
		AosOut.String(" ms="); AosOut.Int(ms, 1);
		AosOut.Ln
	END;
	RETURN (s * mask = expect) & (s * bad = {})
END WaitAltStatus;

(* NanoDelay - Delay at least ns nanoseconds. *)

PROCEDURE NanoDelay(ns: LONGINT);
BEGIN
	ns := ns DIV 2;	(* 400MHz clock => 2.5ns cycle *)
	WHILE ns > 0 DO DEC(ns) END
END NanoDelay;

(* Select device for next command (0 or 1).  Section 9.6. *)

PROCEDURE SelectDevice(port, d, timeout: LONGINT): LONGINT;
VAR res: LONGINT;
BEGIN
	IF ~SelectWait OR WaitStatus(port, {DRQ,BSY}, {}, {}, timeout) THEN
		SYSTEM.PORTOUT(port+6, CHR(ASH(d, 4)));
		NanoDelay(400);
		IF WaitStatus(port, {DRQ,BSY}, {}, {}, timeout) THEN res := 0 ELSE res := 2802 END
	ELSE
		res := 2801
	END;
	RETURN res
END SelectDevice;

(* Issue a command to the controller. *)

PROCEDURE Command(d: Device; cmd: CHAR; lba, num: LONGINT);
VAR port, sector, cylinder, head, x: LONGINT;
BEGIN
	port := d.controller.port;
	ASSERT((num > 0) & (num <= 100H));
	SYSTEM.PORTOUT(port+2, CHR(num MOD 100H));	(* 0 means 256 *)
	IF LBABit IN d.id.type THEN
		ASSERT((lba >= 0) & (lba < 10000000H));
		SYSTEM.PORTOUT(port+3, CHR(lba MOD 100H));
		SYSTEM.PORTOUT(port+4, CHR(ASH(lba, -8) MOD 100H));
		SYSTEM.PORTOUT(port+5, CHR(ASH(lba, -16) MOD 100H));
		SYSTEM.PORTOUT(port+6, CHR((40H + ASH(d.dev, 4) + ASH(lba, -24) MOD 10H)))
	ELSE
		sector := lba MOD d.chs.spt + 1; x := lba DIV d.chs.spt;
		head := x MOD d.chs.hds; cylinder := x DIV d.chs.hds;
		ASSERT((sector < 100H) & (cylinder < 10000H) & (head < 10H));
		SYSTEM.PORTOUT(port+3, CHR(sector));
		SYSTEM.PORTOUT(port+4, CHR(cylinder MOD 100H));
		SYSTEM.PORTOUT(port+5, CHR(cylinder DIV 100H));
		SYSTEM.PORTOUT(port+6, CHR((ASH(d.dev, 4) + head)))
	END;
	SYSTEM.PORTOUT(port+7, cmd)
END Command;

PROCEDURE ExecuteATACommand(port, port2: LONGINT;  cmd: CHAR): BOOLEAN;
VAR ok: BOOLEAN; x: CHAR;
BEGIN
	ok := FALSE;
	SYSTEM.PORTOUT(port+7, cmd);
	NanoDelay(400);
	IF WaitStatus(port, {BSY}, {}, {ERR}, IOTimeout) THEN
		SYSTEM.PORTIN(port2, x);	(* ensure status is valid *)
		ok := TRUE
	END;
	RETURN ok
END ExecuteATACommand;

(* Swap a longint *)

PROCEDURE Swap(VAR a: ARRAY OF SYSTEM.BYTE);
VAR x: SYSTEM.BYTE;
BEGIN
	x := a[0]; a[0] := a[3]; a[3] := x;
	x := a[1]; a[1] := a[2]; a[2] := x;
END Swap;

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

PROCEDURE WaitNotBusy(port2: LONGINT);
VAR x: CHAR; t: AosKernel.MilliTimer;
BEGIN
	SYSTEM.PORTIN(port2, x);
	IF 7 IN SYSTEM.VAL(SET, LONG(ORD(x))) THEN
		AosOut.String("ATA: early "); AosOut.Hex(ORD(x), -3);
		(*AosOut.Char(8X);*)
		AosKernel.SetTimer(t, 10);
		REPEAT
			SYSTEM.PORTIN(port2, x)
		UNTIL ~(7 IN SYSTEM.VAL(SET, LONG(ORD(x))));
		REPEAT UNTIL AosKernel.Expired(t);
		SYSTEM.PORTIN(port2, x); AosOut.Hex(ORD(x), -3); AosOut.Ln
	END
END WaitNotBusy;

(* Read blocks using PIO protocol. *)

PROCEDURE ReadPIO(d: Device; lba, num, bufAdr: LONGINT): LONGINT;
VAR port, port2, res: LONGINT; x: CHAR; s: SET; c: Controller;
BEGIN
	res := 0; c := d.controller; port := c.port; port2 := c.port2;
	c.interrupt.Reset();
	Command(d, 20X, lba, num);	(* read sectors *)
	REPEAT
		IF c.interrupt.Wait(IOTimeout) THEN
			IF EarlyBug THEN WaitNotBusy(c.port2) END;
			SYSTEM.PORTIN(port+7, x); s := SYSTEM.VAL(SET, LONG(ORD(x)));
			IF ~(ERR IN s) THEN
				RepInWord(port, bufAdr, BS DIV 2);
				INC(bufAdr, BS); DEC(num)
			ELSE
				res := 2820
			END
		ELSE
			res := 2819
		END
	UNTIL (num = 0) OR (res # 0);
	SYSTEM.PORTIN(port2, x);	(* according to spec *)
	SYSTEM.PORTIN(port+7, x); s := SYSTEM.VAL(SET, LONG(ORD(x)));
	IF (res = 0) & (ERR IN s) THEN res := 2821 END;
	IF TraceStatus & (res # 0) THEN WriteStatus("ReadPIO", port); AosOut.Ln END;
	RETURN res
END ReadPIO;

(* Write blocks using PIO protocol. *)

PROCEDURE WritePIO(d: Device; lba, num, bufAdr: LONGINT): LONGINT;
VAR port, port2, res: LONGINT; x: CHAR; s: SET; c: Controller;
BEGIN
	res := 0; c := d.controller; port := c.port; port2 := c.port2;
	c.interrupt.Reset();
	Command(d, 30X, lba, num);	(* write sectors *)
	IF WaitAltStatus(port, port2, {DRQ,BSY}, {DRQ}, {ERR}, IOTimeout) THEN
		REPEAT
			RepOutWord(port, bufAdr, BS DIV 2);
			INC(bufAdr, BS); DEC(num);
			IF c.interrupt.Wait(IOTimeout) THEN
				IF EarlyBug THEN WaitNotBusy(c.port2) END;
				SYSTEM.PORTIN(port+7, x); s := SYSTEM.VAL(SET, LONG(ORD(x)));
				IF ERR IN s THEN res := 2824 END
			ELSE
				res := 2823
			END
		UNTIL (num = 0) OR (res # 0)
	ELSE
		res := 2822
	END;
	IF res # 0 THEN
		IF TraceStatus THEN WriteStatus("WritePIO", port); AosOut.Ln END;
		SYSTEM.PORTIN(port+7, x)	(* clear interrupt *)
	END;
	RETURN res
END WritePIO;

(* Transfer blocks using DMA. *)

PROCEDURE TransferDMA(d: Device; read: BOOLEAN; lba, num, physAdr: LONGINT): LONGINT;
VAR port, res, bmbase, i, size, left: LONGINT; s: SET; c: Controller; x: CHAR;
BEGIN
	ASSERT(~ODD(physAdr));	(* transfer must be word-aligned *)
	ASSERT((num > 0) & (num <= MaxTransfer));
	res := 0; c := d.controller;
	port := c.port; bmbase := c.bmbase; ASSERT(bmbase # 0);
		(* init prdt *)
	i := 0; size := num*BS;
	LOOP
		c.prdt.prd[i].physAdr := physAdr;
		left := 65536 - physAdr MOD 65536;	(* should not cross 64k boundary (sec. 3.5.3) *)
		IF left > size THEN left := size END;
		DEC(size, left);
		IF size = 0 THEN
			c.prdt.prd[i].size := 80000000H + left;	(* end marker *)
			EXIT
		ELSE
			c.prdt.prd[i].size := left;
			INC(physAdr, left); INC(i)
		END
	END;
		(* init dma *)
	SYSTEM.PORTOUT(bmbase+4, c.prdtPhysAdr);
	IF read THEN s := {3} ELSE s := {} END;
	SYSTEM.PORTOUT(bmbase, SYSTEM.VAL(CHAR, s));	(* set direction *)
	SYSTEM.PORTIN(bmbase+2, x);
	s := SYSTEM.VAL(SET, LONG(ORD(x)));
	SYSTEM.PORTOUT(bmbase+2, CHR(SYSTEM.VAL(LONGINT, s + {1,2})));	(* clear error, interrupt by writing *)
		(* init transfer *)
	c.interrupt.Reset();
	IF read THEN x := 0C8X ELSE x := 0CAX END;	(* read dma or write dma *)
	Command(d, x, lba, num);
	SYSTEM.PORTIN(bmbase, x);
	s := SYSTEM.VAL(SET, LONG(ORD(x)));
	SYSTEM.PORTOUT(bmbase, CHR(SYSTEM.VAL(LONGINT, s + {0})));	(* start bm *)
	IF c.interrupt.Wait(IOTimeout) THEN
		IF EarlyBug THEN WaitNotBusy(c.port2) END;
		SYSTEM.PORTIN(bmbase+2, x);	(* check dma status *)
		s := SYSTEM.VAL(SET, LONG(ORD(x)));
		IF 1 IN s THEN res := 2808 END
	ELSE
		res := 2807
	END;
	SYSTEM.PORTIN(bmbase, x);
	s := SYSTEM.VAL(SET, LONG(ORD(x)));
	SYSTEM.PORTOUT(bmbase, CHR(SYSTEM.VAL(LONGINT, s - {0})));	(* stop bm *)
	SYSTEM.PORTIN(port+7, x);	(* clear interrupt *)
	s := SYSTEM.VAL(SET, LONG(ORD(x)));
	IF (res = 0) & (ERR IN s) THEN res := 2809 END;
	RETURN res
END TransferDMA;

(* Initialize/Reset the selected device. *)

PROCEDURE InitDevice(port, port2, dev: LONGINT; type: SET; chs: CHS): LONGINT;
VAR x: CHAR; sector, head, res: LONGINT;
BEGIN
	IF AtapiBit IN type THEN
		res := 0
	ELSE
		sector := chs.spt;
		head := chs.hds;
		SYSTEM.PORTOUT(port+2, CHR(sector));
		SYSTEM.PORTOUT(port+3, 0X);
		SYSTEM.PORTOUT(port+4, 0X);
		SYSTEM.PORTOUT(port+5, 0X);
		SYSTEM.PORTOUT(port+6, CHR((ASH(dev, 4) + (head-1) MOD 10H)));
		SYSTEM.PORTOUT(port+7, 091X);	(* initialize device parameters *)
		SYSTEM.PORTIN(port2, x);
		IF ~WaitStatus(port, {BSY}, {}, {ERR}, ResetTimeout) THEN
			IF LBABit IN type THEN
				AosOut.String("ATA: using LBA mode, init dev param ignored");
				AosOut.Ln
			ELSE
				res := 2817
			END
		END
	END;
	RETURN res
END InitDevice;

(* Compose packet command, atapi only *)

PROCEDURE ATAPIComposePacket(VAR pkt: Packet;  cmd: CHAR;  lba, num: LONGINT);
BEGIN
	pkt[0] := cmd;
	pkt[1] := 0X;
	pkt[2] := CHR(ASH(lba, -24) MOD 100H);
	pkt[3] := CHR(ASH(lba, -16) MOD 100H);
	pkt[4] := CHR(ASH(lba, -8) MOD 100H);
	pkt[5] := CHR(lba MOD 100H);
	pkt[6] := 0X;
	pkt[7] := CHR(ASH(num, -8) MOD 100H);
	pkt[8] := CHR(num MOD 100H);
	pkt[9] := 0X;  pkt[10] := 0X;  pkt[11] := 0X;
	pkt[12] := 0X;  pkt[13] := 0X;  pkt[14] := 0X;  pkt[15] := 0X;
END ATAPIComposePacket;

(* Transfer a packet and read/write data *)

PROCEDURE ATAPIPacket(port, port2: LONGINT; pkt: Packet; read: BOOLEAN; bufAdr, size: LONGINT; VAR sense: BOOLEAN): LONGINT;
VAR res, len, avail: LONGINT; low, high, x: CHAR;
BEGIN
	IF TraceAtapi THEN AosOut.String("SendPacket"); AosOut.Hex(ORD(pkt[0]), -3); AosOut.Ln END;
	SYSTEM.PORTOUT(port+1, 0X);	(* no OVL, no DMA *)
	SYSTEM.PORTOUT(port+2, 0X);	(* tag 0 *)
	SYSTEM.PORTOUT(port+4, 0FEX);	(* byte count limit *)
	SYSTEM.PORTOUT(port+5, 0FFX);
	(*SYSTEM.PORTOUT(port+6, CHR(ASH(d.dev, 4)));	(*device*) done by SelectDevice*)
	SYSTEM.PORTOUT(port+7, 0A0X);	(* packet *)
	NanoDelay(400);
	IF WaitStatus(port, {DRQ,BSY}, {DRQ}, {}, SelectTimeout) THEN
		len := 6;
		(*IF Packet16Bit IN d.id.type THEN len := 8 END;*)
		RepOutWord(port, SYSTEM.ADR(pkt[0]), len);
		SYSTEM.PORTIN(port2, x);	(* ensure status is valid *)
		res := 0
	ELSE
		res := 2829
	END;
	WHILE (res = 0) & (size > 0) DO
		IF WaitStatus(port, {DRQ,BSY}, {DRQ}, {ERR}, IOTimeout) THEN
			SYSTEM.PORTIN(port+4, low); SYSTEM.PORTIN(port+5, high);
			avail := LONG(ORD(low)) + LONG(ORD(high))*100H;
			IF avail > size THEN avail := size END;
			IF read THEN
				RepInWord(port, bufAdr, avail DIV 2)
			ELSE
				RepOutWord(port, bufAdr, avail DIV 2)
			END;
			INC(bufAdr, avail); DEC(size, avail)
		ELSE 
			res := 2831
		END
	END;
	IF res # 0 THEN
		(*skip*)
	ELSIF WaitStatus(port, {BSY, DRDY}, {DRDY}, {}, IOTimeout) THEN
		SYSTEM.PORTIN(port+7, x);
		sense :=  ODD(ORD(x)) & ((ORD(x) DIV 10H) # 0)
	ELSE
		res := 2830
	END;
	RETURN res
END ATAPIPacket;

(* Perform a SCSI Sense Command *)

PROCEDURE ATAPISense(port, port2: LONGINT): LONGINT;
VAR pkt: Packet;  sense, res: LONGINT; buf: ARRAY 18 OF CHAR; dummy: BOOLEAN;
BEGIN
	ATAPIComposePacket(pkt, 03X, 0, 0);	(* Request Sense *)
	pkt[4] := 12X;	(* buffer size *)
	res := ATAPIPacket(port, port2, pkt, TRUE, SYSTEM.ADR(buf[0]), 18, dummy);
	sense := ORD(buf[12])*100H + ORD(buf[13]);
	IF res # 0 THEN
		IF TraceSense THEN AosOut.String("sense failed = "); AosOut.Hex(sense, 0); AosOut.Ln END;
		sense := -1
	END;
	RETURN sense
END ATAPISense;

(* Submit an ATAPI command, check for errors and if needed resubmit *)

PROCEDURE ATAPISubmit(port, port2: LONGINT;  pkt: Packet;  read: BOOLEAN;  bufAdr, size: LONGINT; VAR sense: LONGINT): LONGINT;
VAR retry, doSense: BOOLEAN; res: LONGINT; x: CHAR;
BEGIN
	REPEAT
		retry := FALSE; sense := 0;
		res := ATAPIPacket(port, port2, pkt, read, bufAdr, size, doSense);
		IF ((res = 0) & doSense) OR (res = 2831) THEN
			res := 2832;
			sense := ATAPISense(port, port2);
			IF TraceSense THEN
				AosOut.String("ATADisks: ATAPI sense = ");
				AosOut.Hex(sense, 0); AosOut.Ln
			END;
			IF (sense DIV 100H) = 29H THEN	(*attention + power on, ignore*)
				retry := TRUE
			ELSIF (sense = 0401H) THEN	(*failed because getting ready, repeat*)
				NanoDelay(1000);	(*wait a little*)
				retry := TRUE
			ELSIF (sense = 2800H) THEN	(*not ready, (medium change) repeat*)
				res := AosDisks.MediaChanged
			ELSIF (sense = 3A00H) THEN
				res := AosDisks.MediaMissing
			END
		END
	UNTIL ~retry;
	RETURN res
END ATAPISubmit;

(* Send Read Capacity command *)

PROCEDURE ATAPIReadCapacity(port, port2: LONGINT;  VAR blkSize, size: LONGINT): LONGINT;
VAR pkt: Packet; buf: ARRAY 2 OF LONGINT;  res, sense: LONGINT;
BEGIN
	ATAPIComposePacket(pkt, 25X, 0, 0);	(* read capacity *)
	res := ATAPISubmit(port, port2, pkt, TRUE, SYSTEM.ADR(buf[0]), 8, sense);
	IF res = 0 THEN
		size := buf[0]; blkSize := buf[1];
		Swap(size); Swap(blkSize);
		INC(size);	(*read capacity returns the last sector*)
		IF TraceSense THEN
			AosOut.String("ATADisks: read capacity ");
			AosOut.Int(size, 4); AosOut.String(" / ");
			AosOut.Int(blkSize, 4); AosOut.Ln
		END
	ELSIF TraceSense THEN
		AosOut.String("Read Capacity failed with sense "); AosOut.Hex(sense, 0); AosOut.Ln
	END;
	RETURN res
END ATAPIReadCapacity;

PROCEDURE ATAPITestReady(port, port2: LONGINT): LONGINT;
VAR pkt: Packet; res, sense: LONGINT;
BEGIN
	ATAPIComposePacket(pkt, 0X, 0, 0);
	res := ATAPISubmit(port, port2, pkt, TRUE, 0, 0, sense);
	IF res # 0 THEN
		(*AosOut.String("TestReady Failed "); AosOut.Int(res, 4); AosOut.Hex(sense, 10); AosOut.Ln*)
	END;
	RETURN res
END ATAPITestReady;

(* flush sense messages *)

PROCEDURE ATAPIFlushSenses(port, port2: LONGINT);
VAR res, p: LONGINT;
BEGIN
	p := 5;
	res := ATAPISense(port, port2);	(*remove pending messages*)
	WHILE (res > 0) & (p > 0) DO
		DEC(p);
		res := ATAPISense(port, port2);
	END
END ATAPIFlushSenses;

(* Eject media *)

PROCEDURE EjectMedia(port, port2: LONGINT;  atapi: BOOLEAN): LONGINT;
VAR pkt: Packet; sense, res: LONGINT;
BEGIN
	IF atapi THEN
		ATAPIComposePacket(pkt, 1BX, 0, 0);	(* read capacity *)
		pkt[4] := 2X;	(* eject media *)
		res := ATAPISubmit(port, port2, pkt, TRUE, 0, 0, sense)
	ELSIF ExecuteATACommand(port, port2, 0EDX) THEN	(* media eject *)
		res := 0
	ELSE
		res := 2837
	END;
	RETURN res
END EjectMedia;
(*
(* Get the RMSN Status *)

PROCEDURE RMSNStatus(port: LONGINT; VAR status: SET): LONGINT;
VAR res: LONGINT; x: CHAR;
BEGIN
	(*device is already selected*)
	SYSTEM.PORTOUT(port+7, 0DAX);	(* get media status *)
	IF WaitStatus(port, {BSY}, {}, {}, ResetTimeout) THEN
		SYSTEM.PORTIN(port+1, x);
		status := SYSTEM.VAL(SET, LONG(ORD(x)));
		IF TraceRMSN THEN AosOut.String("RMSN Status = "); AosOut.Hex(ORD(x), -3); AosOut.Ln END
	ELSE
		res := 2836
	END;
	RETURN res
END RMSNStatus;
*)
PROCEDURE RMSNEnable(port: LONGINT): LONGINT;
VAR res: LONGINT; x: CHAR;
BEGIN
	res := 0;
	SYSTEM.PORTOUT(port+1, 95X);	(*enable RMSN*)
	SYSTEM.PORTOUT(port+2, 0X);
	SYSTEM.PORTOUT(port+3, 0X);
	SYSTEM.PORTOUT(port+4, 0X);
	SYSTEM.PORTOUT(port+5, 0X);
	SYSTEM.PORTOUT(port+7, 0EFX);	(* set features *)
	NanoDelay(400);
	IF WaitStatus(port, {BSY}, {}, {ERR}, ResetTimeout) THEN
		SYSTEM.PORTIN(port+5, x);
		IF TraceRMSN THEN AosOut.String("RMSN Enable = "); AosOut.Hex(ORD(x), -3); AosOut.Ln END
	ELSE
		res := 2834
	END;
	RETURN res
END RMSNEnable;

PROCEDURE RMSNDisable(port: LONGINT): LONGINT;
VAR res: LONGINT; x: CHAR;
BEGIN
	res := 0;
	SYSTEM.PORTOUT(port+1, 31X);	(*enable RMSN*)
	SYSTEM.PORTOUT(port+4, 0X);
	SYSTEM.PORTOUT(port+5, 0X);
	SYSTEM.PORTOUT(port+7, 0EFX);	(* set features *)
	NanoDelay(400);
	IF WaitStatus(port, {BSY}, {}, {ERR}, ResetTimeout) THEN
		SYSTEM.PORTIN(port+5, x);
		IF TraceRMSN THEN AosOut.String("RMSN Disable = "); AosOut.Hex(ORD(x), -3); AosOut.Ln END
	ELSE
		res := 2835
	END;
	RETURN res
END RMSNDisable;

(* Initialize controller parameters. *)

PROCEDURE ParseControllerConfig(num, dirq, dc: LONGINT);
VAR s: ARRAY 32 OF CHAR; id: ARRAY 8 OF CHAR; p, c, r, irq: LONGINT;
BEGIN
	id := "IDE#"; id[3] := CHR(ORD("0") + num);
	AosBoot.GetConfig(id, s);
	IF (num = 0) & (s = "") THEN AosBoot.GetConfig("IDE", s) END;
	IF UseConfigParams & (s # "") THEN
		p := 0; c := 0; r := 0;
		irq := AosBoot.StrToInt(p, s);
		IF (irq # 0) & (s[p] = ",") THEN
			INC(p); c := AosBoot.StrToInt(p, s);
			IF s[p] = "," THEN
				INC(p); r := AosBoot.StrToInt(p, s)
			END;
			IF c = 0 THEN c := dc END;
			IF (r = 0) & (c > 0) THEN r := c + 206H END
		END
	ELSE
		irq := dirq; c := dc; r := c + 206H
	END;
	IF c > 0 THEN
		NEW(controller[num]);
		controller[num].port := c; controller[num].port2 := r; controller[num].irq := irq;
		controller[num].bmbase := 0;	(* BM disabled *)
		controller[num].interrupt := NIL
	END
END ParseControllerConfig;

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

(* Identify an Atapi packet device. *)

PROCEDURE IdentifyAtapi(port, port2: LONGINT; VAR blkSize, size: LONGINT; VAR id: ID): LONGINT;
VAR res: LONGINT; x: CHAR; buf: ARRAY BS DIV 2 OF INTEGER;
BEGIN
	SYSTEM.PORTOUT(port+7, 0A1X);	(* identify ATAPI device *)
	SYSTEM.PORTIN(port2, x);	(* ensure status ok *)
	IF WaitStatus(port, {BSY}, {}, {}, IdentifyTimeout) THEN
		INCL(id.type, AtapiBit);
		RepInWord(port, SYSTEM.ADR(buf[0]), BS DIV 2);
		IF 7 IN SYSTEM.VAL(SET, LONG(buf[0])) THEN
			INCL(id.type, RemovableBit);
			IF (4 IN SYSTEM.VAL(SET, LONG(buf[83]))) OR (0 IN SYSTEM.VAL(SET, LONG(buf[127]))) THEN INCL(id.type, RMSNBit) END;
		END;
		IF 0 IN SYSTEM.VAL(SET, LONG(buf[0])) THEN INCL(id.type, Packet16Bit) END;
		IF 8 IN SYSTEM.VAL(SET, LONG(buf[49])) THEN INCL(id.type, DMABit) END;
		GetATAString(buf, 27, 46, id.model);
		id.devtype := ASH(buf[0], -8) MOD 20H;
		IF (buf[80] # -1) & (buf[81] # -1) THEN
			id.ver := ASH(LONG(buf[80]) MOD 10000H, 16) + LONG(buf[81]) MOD 10000H
		END;
		IF Packet16Bit IN id.type THEN
			res := 2833
(*
		ELSIF id.type * {RemovableBit, RMSNBit} = {RemovableBit} THEN
			res := 2828
*)
		ELSIF ~(RemovableBit IN id.type) THEN
			res := ATAPIReadCapacity(port, port2, blkSize, size)
		ELSE
			res := 0
		END
	ELSE
		res := 2812
	END;
	RETURN res
END IdentifyAtapi;

(* Identify an ATA device. *)

PROCEDURE IdentifyATA(port: LONGINT; VAR chs: CHS; VAR size: LONGINT; VAR id: ID): LONGINT;
VAR res, size1: LONGINT; buf: ARRAY BS DIV 2 OF INTEGER;
BEGIN
	RepInWord(port, SYSTEM.ADR(buf[0]), BS DIV 2);
	(*AosOut.Memory(SYSTEM.ADR(buf[0]), BS);*)
	chs.cyls := LONG(buf[1]) MOD 10000H;
	chs.hds := LONG(buf[3]) MOD 10000H;
	chs.spt := LONG(buf[6]) MOD 10000H;
	
	size := ASH(LONG(buf[61]) MOD 10000H, 16) + LONG(buf[60]) MOD 10000H;
	IF size >= MinLBA THEN INCL(id.type, LBABit) END;
	size1 := chs.cyls * chs.hds * chs.spt;
	
	IF size < size1 THEN size := size1 END;
	IF SYSTEM.VAL(SET, LONG(buf[0])) * {6,7} = {7} THEN
		INCL(id.type, RemovableBit);
		IF (4 IN SYSTEM.VAL(SET, LONG(buf[83]))) OR (0 IN SYSTEM.VAL(SET, LONG(buf[127]))) THEN INCL(id.type, RMSNBit) END;
	END;
	INCL(id.type, DMABit);	(* DMA support mandatory in ATA/ATAPI-4 *)
	GetATAString(buf, 27, 46, id.model);
	IF (buf[80] # -1) & (buf[81] # -1) THEN
		id.ver := ASH(LONG(buf[80]) MOD 10000H, 16) + LONG(buf[81]) MOD 10000H
	END;
	IF ~((chs.hds <= 16) & (chs.spt <= 255)) THEN
		res := 2825
	ELSIF id.type * {RemovableBit, RMSNBit} = {RemovableBit} THEN
		res := 2827
	ELSE
		res := 0
	END;
	RETURN res
END IdentifyATA;

(* Identify a device. *)

PROCEDURE IdentifyDevice(controller: Controller; dev: LONGINT; VAR chs: CHS; VAR blkSize, size: LONGINT; VAR id: ID): LONGINT;
VAR res, port, port2: LONGINT; x: CHAR; t: AosKernel.MilliTimer;
BEGIN
	id.type := {}; id.ver := 0; chs.cyls := 0; chs.hds := 0; chs.spt := 0; size := 0;
	port := controller.port; port2 := controller.port2;
	IF port # 0 THEN
		AosKernel.SetTimer(t, 50); REPEAT UNTIL AosKernel.Expired(t);
		res := SelectDevice(port, dev, IdentifyTimeout);
		IF res = 0 THEN
			controller.interrupt.Reset();
			SYSTEM.PORTOUT(port+7, 0ECX);	(* identify device *)
			IF controller.interrupt.Wait(IdentifyTimeout) THEN
				IF EarlyBug THEN WaitNotBusy(controller.port2) END;
				SYSTEM.PORTIN(port+5, x);	(* signature byte *)
				IF x = 0EBX THEN
					res := IdentifyAtapi(port, port2, blkSize, size, id)
				ELSE
					res := IdentifyATA(port, chs, size, id);
					blkSize := BS;
					IF (res = 0) & (size = 0) THEN res := 2813 END
				END
			ELSE
				res := 2814
			END
		END;
		AosKernel.SetTimer(t, 50); REPEAT UNTIL AosKernel.Expired(t);
		SYSTEM.PORTOUT(port+6, 0X);	(* select device 0 again *)
		NanoDelay(400)
	ELSE
		res := 2815
	END;
	RETURN res
END IdentifyDevice;

(* Clean up unloaded module. *)

PROCEDURE Cleanup;
VAR i: LONGINT; d: Device;
BEGIN
	IF AosModules.shutdown = AosModules.None THEN
		FOR i := 0 TO MaxDevices-1 DO
			d := device[i];
			IF d # NIL THEN AosDisks.registry.Remove(d) END
		END;
		FOR i := 0 TO MaxControllers-1 DO
			IF (controller[i] # NIL) & (controller[i].interrupt # NIL) THEN
				AosActive.RemoveHandler(controller[i].interrupt.HandleInterrupt, controller[i].interrupt.int);
				controller[i] := NIL
			END
		END
	END
END Cleanup;

(* Initialization. *)

PROCEDURE IdentifyControllers;
VAR i: LONGINT;
BEGIN
	FOR i := 0 TO MaxControllers-1 DO controller[i] := NIL END;
	IF PrimaryEnabled THEN ParseControllerConfig(0, 14, 01F0H) END;
	IF SecondaryEnabled THEN ParseControllerConfig(1, 15, 0170H) END;
	IF MaxControllers > 2 THEN	(* compile-time expression *)
		FOR i := 2 TO MaxControllers-1 DO ParseControllerConfig(i, 0, 0) END
	END
END IdentifyControllers;

PROCEDURE ResetController(ctrl: Controller): BOOLEAN;
VAR t: AosKernel.MilliTimer;
BEGIN
	SYSTEM.PORTOUT(ctrl.port2, 4X);	(* reset controller *)
	AosKernel.SetTimer(t, 1); REPEAT UNTIL AosKernel.Expired(t);	(* wait > 4.8us *)
	SYSTEM.PORTOUT(ctrl.port2, 8X);
	AosKernel.SetTimer(t, 3); REPEAT UNTIL AosKernel.Expired(t);	(* wait ~2ms *)
	RETURN WaitStatus(ctrl.port, {BSY}, {}, {}, ResetTimeout)
END ResetController;

PROCEDURE IdentifyDevices;
VAR
	p, q, a, n, i, res, blkSize, size: LONGINT; ctrl: Controller; dev: Device; chs: CHS; id: ID; x: CHAR;
	name: AosPlugins.Name; s: ARRAY 16 OF CHAR; useBIOS: BOOLEAN;
BEGIN
	AosBoot.GetConfig("ATABIOS", s);
	useBIOS := s[0] = "1";
	IF useBIOS THEN
		AosOut.String("Using BIOS geometry");  AosOut.Ln
	END;
		(* identify all devices *)
	a := 0; n := 0;
	FOR p := 0 TO MaxDevices-1 DO
		ctrl := controller[p DIV 2];
		IF ctrl # NIL THEN
			name := Name;
			i := 0; WHILE name[i] # 0X DO INC(i) END;
			name[i] := CHR(48 + p); name[i+1] := 0X;
			res := IdentifyDevice(ctrl, p MOD 2, chs, blkSize, size, id);
			IF res = 0 THEN
				NEW(dev); dev.SetName(name);
				dev.controller := ctrl; dev.dev := p MOD 2; dev.init := FALSE;
				dev.id := id; dev.size := size; dev.chs := chs; dev.getpar := dev.chs;
				COPY(id.model, dev.desc);
				IF AtapiBit IN id.type THEN
					SYSTEM.PORTOUT(ctrl.port+6, CHR(ASH(dev.dev, 4)));
					SYSTEM.PORTOUT(ctrl.port+7, 8X);	(* reset packet device *)
					SYSTEM.PORTIN(ctrl.port2, x);
					IF ~WaitStatus(ctrl.port, {BSY}, {}, {}, ResetTimeout) THEN
						res := 2816; AosOut.String(name); AosOut.String(": reset failed"); AosOut.Ln;
					ELSE
						IF FlushATAPISense THEN ATAPIFlushSenses(ctrl.port, ctrl.port2) END;
						res := ATAPITestReady(ctrl.port, ctrl.port2)
						(*undocumented: the first command after Reset Device shall be a PACKET command, other
							commands like Set Features otherwise abort.*)
					END
				ELSE
					dev.blockSize := blkSize;
					IF (p < 2) & useBIOS THEN	(* override CHS *)
						AosBoot.GetDiskCHS(p, dev.getpar.cyls, dev.getpar.hds, dev.getpar.spt)
					END;
					IF dev.size > 16383*16*63 THEN
						dev.getpar.cyls := dev.size DIV (dev.getpar.hds * dev.getpar.spt)
					END
				END;
				device[q] := dev; INC(q)
			ELSE (* skip *)
			END;
			IF TraceIdentify THEN
				AosOut.String(name); AosOut.String(": Identify = ");
				AosOut.Int(res, 1); AosOut.Ln
			END;
			IF AtapiBit IN id.type THEN	(* Ref 2, 5.18.2 (p. 46): Atapi shall not use SRST *)
				AosOut.String(name); AosOut.String(": no reset"); AosOut.Ln
			ELSIF ~ResetController(ctrl) THEN
				AosOut.String(name); AosOut.String(": reset failed"); AosOut.Ln
			ELSIF TraceIdentify THEN
				AosOut.String(name); AosOut.String(": reset ok"); AosOut.Ln
			END
		END
	END;
	WHILE q # MaxDevices DO device[q] := NIL;  INC(q) END
END IdentifyDevices;

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

PROCEDURE ShowDevices;
VAR i, j: LONGINT; dev: Device;
BEGIN
	FOR i := 0 TO MaxDevices-1 DO
		dev := device[i];
		IF dev # NIL THEN
			AosOut.String(dev.name); AosOut.String(": ");
			IF AtapiBit IN dev.id.type THEN
				AosOut.String("packet");
				IF Packet16Bit IN dev.id.type THEN AosOut.String(" (16bit)") END;
				ShowDevType(dev.id.devtype)
			ELSE
				AosOut.Int(dev.size DIV 2048, 1); AosOut.String("MB");
				AosOut.String(", "); ShowCHS(dev.chs);
				IF (dev.getpar.cyls # dev.chs.cyls) OR (dev.getpar.hds # dev.chs.hds) OR (dev.getpar.spt # dev.chs.spt) THEN
					AosOut.String(", ("); ShowCHS(dev.getpar); AosOut.Char(")")
				END
			END;
			IF RemovableBit IN dev.id.type THEN AosOut.String(", removable") END;
			IF ~(DMABit IN dev.id.type) THEN AosOut.String(", no DMA") END;
			IF LBABit IN dev.id.type THEN AosOut.String(", LBA") END;
			IF RMSNBit IN dev.id.type THEN AosOut.String(", RMSN") END;
			AosOut.String(", "); AosOut.String(dev.id.model);
			IF dev.id.ver # 0 THEN
				AosOut.String(", ver ");
				j := 30; WHILE (j # 16) & ~ODD(ASH(dev.id.ver, -j)) DO DEC(j) END;
				AosOut.Int(j-16, 1); AosOut.Char(".");
				AosOut.Int(dev.id.ver MOD 10000H, 1)
			END;
			AosOut.Ln
		END
	END
END ShowDevices;

PROCEDURE InitControllers;
VAR i: LONGINT; ctrl: Controller;
BEGIN
	FOR i := 0 TO MaxControllers-1 DO
		ctrl := controller[i];
		AosOut.String("IDE"); AosOut.Int(i*2, 1);
		AosOut.String(".."); AosOut.Int(i*2+1, 1); AosOut.String(": ");
		IF ctrl # NIL THEN
			AosOut.Int(ctrl.irq, 1); AosOut.Hex(ctrl.port, 9); AosOut.Hex(ctrl.port2, 9);
			AosOut.Char(" ");
			IF ResetController(ctrl) THEN
				AosOut.String("reset ok"); AosOut.Ln;
				NEW(ctrl.interrupt, ctrl.irq)
			ELSE
				controller[i] := NIL;
				IF ~TraceStatus THEN
					AosOut.String("reset failed"); AosOut.Ln
				END
			END
		ELSE
			AosOut.String(" disabled"); AosOut.Ln
		END
	END
END InitControllers;

PROCEDURE GetPRDAdr(c: Controller): BOOLEAN;
VAR p: LONGINT;
BEGIN
	NEW(c.prdt);	(* must not cross page boundary, see Intel 290550-002 sec. 2.7.3 *)
	p := AosMemory.PhysicalAdr(SYSTEM.ADR(c.prdt.prd[0]), MaxPRD*8);
	c.prdtPhysAdr := p;
	RETURN (p # AosMemory.NilAdr) & (p DIV PageSize = (p+MaxPRD*8-1) DIV PageSize)
END GetPRDAdr;

PROCEDURE InitBusMaster;
VAR bus, dev, fkt, i, bmbase, iobase: LONGINT; s: SET; str: ARRAY 8 OF CHAR;

	PROCEDURE FindDevice(id, vendor: LONGINT): BOOLEAN;	(* set bus, dev, fkt as side-effect *)
	VAR res: LONGINT;
	BEGIN
		res := PCI.FindPCIDevice(id, vendor, 0, bus, dev, fkt);
		RETURN res = PCI.Done
	END FindDevice;
	
	PROCEDURE ReadDWord(adr: LONGINT; VAR s: SET);
	VAR res: LONGINT;
	BEGIN
		res := PCI.ReadConfigDword(bus, dev, fkt, adr, SYSTEM.VAL(LONGINT, s));
		IF res # PCI.Done THEN s := {} END
	END ReadDWord;

	PROCEDURE WriteByte(adr: LONGINT; s: SET);
	VAR res: LONGINT;
	BEGIN
		res := PCI.WriteConfigByte(bus, dev, fkt, adr, SYSTEM.VAL(LONGINT, s));
		(* ignore res *)
	END WriteByte;

BEGIN
	IF BMEnabled THEN
		AosBoot.GetConfig("ATABM", str);
		IF str[0] # "0" THEN
			IF FindDevice(7010H, 8086H) OR FindDevice(7111H, 8086H) OR 
				FindDevice(2411H, 8086H) OR FindDevice(2421H, 8086H) OR 
				FindDevice(244BH, 8086H) OR FindDevice(24CAH, 8086H) OR
				FindDevice(24DBH, 8086H) OR FindDevice(0211H, 1166H) (* Serverworks *)
				OR FindDevice(24D1H, 8086H) 
			THEN
				ReadDWord(PCI.CmdReg, s);
				IF OverrideBIOS & (s * {0,2} = {0}) THEN	(* override BIOS-disabled BM setting *)
					(*AosOut.String("Overriding BIOS bus-master setting"); AosOut.Ln;*)
					WriteByte(PCI.CmdReg, s + {2});
					ReadDWord(PCI.CmdReg, s)
				END;
				IF s * {0,2} = {0,2} THEN	(* ports & BM enabled *)
					ReadDWord(20H, s);	(* BMIBA *)
					bmbase := SYSTEM.VAL(LONGINT, s * {4..15});
					IF bmbase # 0 THEN
						ReadDWord(40H, s);	(* IDETIM *)
						FOR i := 0 TO 1 DO	(* primary and secondary controller *)
							IF i = 0 THEN iobase := 1F0H ELSE iobase := 170H END;	(* standard ports *)
							IF (15 IN s) & (controller[i] # NIL) & (controller[i].port = iobase) & GetPRDAdr(controller[i]) THEN
								AosOut.String("IDE"); AosOut.Int(i*2, 1);
								AosOut.String(".."); AosOut.Int(i*2+1, 1);
								AosOut.String(": Bus-master enabled"); AosOut.Ln;
								controller[i].bmbase := bmbase + 8*i
							END;
							s := SYSTEM.LSH(s, -16)
						END
					ELSE
						AosOut.String("Bus-master ports disabled (BIOS)"); AosOut.Ln
					END
				ELSE
					AosOut.String("Bus-master disabled"); AosOut.Ln
				END
			ELSE
				AosOut.String("Bus-master chipset not detected"); AosOut.Ln
			END
		END
	END
END InitBusMaster;

PROCEDURE Register;
VAR i, res: LONGINT; dev: Device;
BEGIN
	FOR i := 0 TO MaxDevices-1 DO
		dev := device[i];
		IF dev # NIL THEN
			dev.blockSize := BS; dev.flags := {};
			IF RemovableBit IN dev.id.type THEN INCL(dev.flags, AosDisks.Removable) END;
			AosDisks.registry.Add(dev, res);
			ASSERT(res = AosPlugins.Ok)
		END
	END
END Register;

(** The install command has no effect, as all ATA devices are installed when the module is loaded. *)
PROCEDURE Install*;
END Install;

BEGIN
	IF AosBoot.Trace THEN AosOut.Enter; AosOut.String("AosATADisks"); AosOut.Exit END;
	AosModules.InstallTermHandler(Cleanup);
	IdentifyControllers;
	InitControllers;
	IdentifyDevices;
	ShowDevices;
	InitBusMaster;
	Register
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

AosATADisk.Install

ATAErrors.Text
