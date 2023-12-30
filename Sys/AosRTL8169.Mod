MODULE AosRTL8169;
(*
Aos driver for RealTek RTL8169 Ethernet Controllers

Reference: RealTek, "RealTek Gigabit Ethernet Media Access Controller
	with Power Management RTL8169S/RTL8110S Registers"
Revision 1.0, March 2003

Author: Roger Keller (kellerog), ETH Zuerich
*)
IMPORT
	SYSTEM, AosKernel, AosInterrupts, AosMemory, PCI, 
	AosActive, AosModules, AosPlugins, AosNet, AosOut;

CONST
	Name = "RTL8169#";
	Description = "RealTek 8169 Gigabit ethernet driver";

	MaxETHFrameSize = 1514;
	TxMaxSize = 1600; (* Max size of tx buffers *)
	RxMaxSize = 600H; (* Max size for received frames = 1536 bytes *)
	RxRingSize = 1024; (* Rx Ring of 116 buffers *)
	TxRingSize = 1024; (* Tx Ring of 116 buffers *)

	SizeOfRxTxFDHdr = 16; (* size of Rx / Tx Descriptor Header *)
	
	InterruptMask = {0, 1, 2, 3, 4, 5, 6, 7, 15}; (* interrupts to handle *)
	Promisc = FALSE; (* enable Promiscuous mode *)
	
	UnknownHW = 0;
	RTL8169 = 1;
	RTL8169S = 2;
	
	DebugFind = 0;
	DebugInit = 1;
	DebugConfigs = 2;
	DebugHWVer = 3;
	DebugMAC = 4;
	DebugStatus = 5;
	DebugRxRing = 6;
	DebugTxRing = 7;
	DebugReceive = 8;
	DebugTransmit = 9;
	DebugInterrupt = 10;
	DebugCleanup = 31;
	Debug = {DebugFind, DebugInit, DebugTxRing, DebugCleanup};

VAR
	installed: LONGINT; (* number of installed devices *)

TYPE
	(* base Rx/Tx descriptor, as described in RTL8169 specs *)
	RxTxDescriptor = RECORD
		flags: SET;
		vLanTag: LONGINT;
		bufAdrLo, bufAdrHi: LONGINT;
	END;
	
	(* buffer for transmission *)
	TxBuffer = POINTER TO RECORD
		data: ARRAY TxMaxSize OF CHAR;
		next: TxBuffer;
	END;
	
	(* wrapper for AosNet.Buffer to be able to form rings *)
	RxBuffer = POINTER TO RECORD
		buf: AosNet.Buffer;
		next: RxBuffer;
	END;
	
	(* LinkDevice: interface to Bluebottle *)
	LinkDevice = OBJECT (AosNet.LinkDevice)
		VAR
			ctrl: Controller;
			hw: LONGINT;

		PROCEDURE Linked*(): LONGINT;
		BEGIN
			RETURN ctrl.linkStatus;
		END Linked;
		
		PROCEDURE DoSend*(dst: AosNet.LinkAdr; type: LONGINT; VAR l3hdr, l4hdr, data: ARRAY OF CHAR;  h3len, h4len, dofs, dlen: LONGINT);
		BEGIN
			ctrl.SendFrame(dst, type, l3hdr, l4hdr, data, h3len, h4len, dofs, dlen);
		END DoSend;
		
		PROCEDURE Finalize(connected: BOOLEAN);
		BEGIN
			ctrl.Finalize;
			Finalize^(connected);
		END Finalize;
	END LinkDevice;
	
	(* Controller: interface to the RTL8169 hardware *)
	Controller = OBJECT
		VAR
			next: Controller; (* next controller in list *)
			base, irq: LONGINT;
			dev: LinkDevice;
			rds: ARRAY RxRingSize OF RxTxDescriptor;
			tds: ARRAY TxRingSize OF RxTxDescriptor;
			curRD, curTD: LONGINT;
			firstRD, firstTD: LONGINT;
			lastRD, lastTD: LONGINT;
			(*rxBuffer, rxLast: TxBuffer;*)
			rxBuffer, rxLast: RxBuffer;
			txBuffer, txLast: TxBuffer;
			
			nofFreeTx: LONGINT; (* number of free tx descriptors *)
			
			nRxOverflow: HUGEINT;
			nTxOverflow: HUGEINT;
			nRxFrames, nTxFrames: LONGINT;
			nRxErrorFrames: LONGINT;
			nTxErrorFrames: LONGINT;
			
			linkStatus: LONGINT;
		
		PROCEDURE &Init(dev: LinkDevice; base, irq: LONGINT);
		VAR
			res, i: LONGINT;
			s: SET;
		BEGIN
			(* update list of installed controllers, insert at head *)
			SELF.next := installedControllers;
			installedControllers := SELF;
			
			SELF.base := base;
			SELF.dev := dev;
			SELF.irq := irq;
			dev.ctrl := SELF;
			nRxOverflow := 0;
			nTxOverflow := 0;
			nRxFrames := 0;
			nTxFrames := 0;
			nRxErrorFrames := 0;
			nTxErrorFrames := 0;
			
			(* tell the system that the nic calculates the checksums for tcp, udp and ip packets *)
			dev.calcChecksum := {AosNet.ChecksumIP, AosNet.ChecksumTCP, AosNet.ChecksumUDP};
			
			(* set ethernet broadcast address: FF-FF-FF-FF-FF-FF *)
			FOR i := 0 TO 5 DO
				dev.broadcast[i] := 0FFX
			END;
			
			(* make sure PIO and MMIO are enabled*)
			s := SYSTEM.VAL(SET, Read8(52H));
			IF ~ (2 IN s) THEN
				AosOut.String("I/O Mapping is disabled!");
				HALT(1000);
			END;
			IF ~ (3 IN s) THEN
				AosOut.String("MMIO is disabled!");
				HALT(1000);
			END;
			
			(* find out if we're on 1GBps *)
			s := SYSTEM.VAL(SET, Read8(6CH));
			(* if not, try to enable 1GBps ... *)
			IF ~ (4 IN s) THEN
				(* reset the hardware and enable 1000baseTx *)	
				HwReset;
				EnableTBI;
			END;
			
			(* read and store MAC address *)
			ReadMACAddress;
			
			(* find out hardware version *)
			GetHardwareVersion;
			
			(* soft reset the chip *)
			ResetNIC;
			
			(* enable Tx and Rx *)
			EnableTxRx(TRUE, TRUE);
			
			(* set Max Transmit Packet Size (MTPS):
			register counts in 32 byte units -> 32H * 32 bytes = 1600 bytes *)
			Write8(0ECH, 32H);
			
			(* set Receive Packet Maximum Size (RMS) *)
			Write16(0DAH, RxMaxSize);
			
			(* set Tx config register:
			let the nic compute CRCs of frames in Tx *)
			s := SYSTEM.VAL(SET, Read32(40H));
			s := (s  - {17..18, 19}) + {8..10, 25};
			Write32(40H, SYSTEM.VAL(LONGINT, s));
			
			(* config c+ command register:
			PCI multiple read/write enable;
			Receive Checksum Offload enable *)
			s := SYSTEM.VAL(SET, Read16(0E0H));
			s := s + {3, 5};
			Write16(0E0H, SYSTEM.VAL(LONGINT, s));
			
			(* setup Tx (normal priority) ring *)
			res := SetupTxRing();
			(* set Transmit Normal Priority Descriptor Start Address (TNPDS) *)
			Write32(20H, res);
			Write32(20H + 4, 0);
			
			(* setup Rx ring *)
			res := SetupRxRing();
			(* set Receive Descriptor Start Address (RDSAR) *)
			Write32(0E4H, res);
			Write32(0E4H + 4, 0);
			
			(* reset Rx missed packet counter *)
			Write32(04CH, 0);
			
			(* configure receiver *)
			ConfigRx;
			
			(* install interrupt handler *)
			IF (irq >= 1) & (irq <= 15) THEN
				AosActive.InstallHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0 + irq)
			END;
			
			(* enable interrupts *)
			Write16(3CH, SYSTEM.VAL(LONGINT, InterruptMask));
			
			UpdateLinkStatus;
			
			(* register device with AosNet *)
			AosNet.registry.Add(dev, res);
			ASSERT(res = AosPlugins.Ok);
			INC(installed);

			IF DebugConfigs IN Debug THEN
				DebugConfig;
			END;
		END Init;
		
		PROCEDURE SendFrame(dst: AosNet.LinkAdr; type: LONGINT; VAR l3hdr, l4hdr, data: ARRAY OF CHAR;  h3len, h4len, dofs, dlen: LONGINT);
		VAR
			im: LONGINT;
			i, txLen, bufBase, offset, type4: LONGINT;
			chksums: SET;
		BEGIN {EXCLUSIVE}
			IF nofFreeTx <= 0 THEN
				AosOut.String("no tx buffers"); AosOut.Ln;
				INC(nTxOverflow);
			END;
			AWAIT(nofFreeTx > 0);
			
			txLen := 14 + h3len + h4len + dlen;
			bufBase := SYSTEM.ADR(txBuffer.data);
			
			(* generate ethernet frame: setup eth header, move data *)
			(* set destination mac address (first 6 bytes of eth frame) *)
			SYSTEM.MOVE(SYSTEM.ADR(dst[0]), bufBase, 6);
			(* set source mac address (6 bytes @ offset 6 of eth frame) *)
			SYSTEM.MOVE(SYSTEM.ADR(dev.local[0]), bufBase + 6, 6);
			(* set upper layer type, bring type from host to network byte order *)
			SYSTEM.PUT16(bufBase + 12, SYSTEM.ROT(SYSTEM.VAL(INTEGER, SHORT(type)), 8));
			
			offset := 14; (* eth header has 14 bytes *)
			(* move layer 3 and layer 4 headers, data *)
			IF h3len > 0 THEN
				SYSTEM.MOVE(SYSTEM.ADR(l3hdr[0]), bufBase + offset, h3len);
				INC(offset, h3len);
			END;
			IF h4len > 0 THEN
				SYSTEM.MOVE(SYSTEM.ADR(l4hdr[0]), bufBase + offset, h4len);
				INC(offset, h4len);
			END;
			IF offset + dlen < MaxETHFrameSize THEN
				SYSTEM.MOVE(SYSTEM.ADR(data[0]) + dofs, bufBase + offset, dlen);
				INC(offset, dlen);
			END;
			
			(* make the frame at least 64 bytes long *)
			WHILE offset < 60 DO
				txBuffer.data[offset] := CHR(0);
				INC(offset);
				INC(txLen);
			END;
			
			IF DebugTransmit IN Debug THEN
				AosOut.String("Sending frame of length ");
				AosOut.Int(txLen, 0);
				AosOut.Ln;
				(*AosOut.Memory(bufBase, txLen);*)
			END;
			
			(* find out which protocols are used;
			let the NIC calc the checksums for IP, TCP and UCP headers *)
			chksums := {};
			IF type = 0800H THEN
				INCL(chksums, 18); (* offload IP checksum *)
				type4 := SYSTEM.VAL(SHORTINT, l3hdr[9]); (* get type if IP data *)
				IF type4 = 6 THEN (* TCP/IP *)
					INCL(chksums, 16); (* offload TCP checksum *)
				ELSIF type4 = 17 THEN
					INCL(chksums, 17); (* offload UDP checksum *)
				END;
			END;
			
			(* update Tx Descriptor:
			set OWN=1, FS=1, LS=1, checksum offloads;
			set size of packet to be transmitted *)
			tds[curTD].flags := tds[curTD].flags * {30}; (* only keep EOR bit *)
			tds[curTD].flags := tds[curTD].flags + {31, 29, 28} + chksums;
			tds[curTD].flags := tds[curTD].flags + (SYSTEM.VAL(SET, txLen) * {0..15});
			
			(* move to next Tx Descriptor, Tx Buffer *)
			INC(curTD);
			IF curTD = TxRingSize THEN
				curTD := firstTD;
			END;
			txBuffer := txBuffer.next;
			
			DEC(nofFreeTx);
			
			(* tell the nic that there's some eth frame waiting to be transmitted (set NPQ=1) *)
			Write8(38H, SYSTEM.VAL(LONGINT, {6}));
		END SendFrame;
		
		PROCEDURE ConfigRx;
		VAR s: SET;
		BEGIN
			(* set Rx config register:
			let the nic check CRCs of frames in Rx;
			accept broadcast, multicast, phys match, all packets with dest addr (IFF Promiscuos mode enabled)
			set no Rx FIFO threshold, set unlimited DMA burst size*)
			s := SYSTEM.VAL(SET, Read32(44H));
			s := (s * {7, 11..12, 17..31}) + {1..3, 9, 14..15, 16};
			IF Promisc THEN
				INCL(s, 0);
			END;
			Write32(44H, SYSTEM.VAL(LONGINT, s));
			
			(* set multicast filter: receive everything *)
			Write32(08H, 0FFFFFFFFH);
			Write32(08H + 4, 0FFFFFFFFH);
		END ConfigRx;
		
		PROCEDURE SetTimer(val: LONGINT);
		BEGIN
			Write32(58H, val);
		END SetTimer;
		
		PROCEDURE GetHardwareVersion;
		VAR s: SET;
		BEGIN
			s := SYSTEM.VAL(SET, Read32(40H));
			s := s * {23, 26..30};
			
			IF DebugHWVer IN Debug THEN
				AosOut.String("Hardware Version: ");
			END;
			IF s = {} THEN
				dev.hw := RTL8169;
				IF DebugHWVer IN Debug THEN
					AosOut.String("RTL8169");
				END;
			ELSIF ((s * {23, 26}) # {}) & ((s * {27..30}) = {}) THEN
				dev.hw := RTL8169S;
				IF DebugHWVer IN Debug THEN
					AosOut.String("RTL8169S/RTL8110S");
				END;
			ELSE
				dev.hw := UnknownHW;
				IF DebugHWVer IN Debug THEN
					AosOut.String("Hardware Version is unknown");
				END;
			END;
			IF DebugHWVer IN Debug THEN
				AosOut.Ln;
			END;
		END GetHardwareVersion;
		
		PROCEDURE ResetNIC;
		VAR s: SET;
		BEGIN
			Write8(37H, SYSTEM.VAL(LONGINT, {4}));
			
			(* wait until reset has finished *)
			REPEAT
				Delay(10);
				s := SYSTEM.VAL(SET, Read8(37H));
			UNTIL ~(4 IN s);
		END ResetNIC;
		
		PROCEDURE EnableTxRx(tx, rx: BOOLEAN);
		VAR s: SET;
		BEGIN
			s := SYSTEM.VAL(SET, Read8(37H));
			s := s * {0..1, 5..7};
			IF tx THEN
				INCL(s, 2);
			END;
			IF rx THEN
				INCL(s, 3);
			END;
			Write8(37H, SYSTEM.VAL(LONGINT, s));
		END EnableTxRx;
		
		PROCEDURE ReadMACAddress;
		VAR
			i: INTEGER;
			res: LONGINT;
		BEGIN
			(* MAC address is in registers 00H - 05H *)
			IF DebugMAC IN Debug THEN
				AosOut.String("MAC address is: ");
			END;
			FOR i := 0 TO 5 DO
				res := Read8(i);
				SYSTEM.PUT8(SYSTEM.ADR(dev.local[i]), res);
				IF DebugMAC IN Debug THEN
					IF i > 0 THEN
						AosOut.String("-");
					END;
					AosOut.Hex(ORD(dev.local[i]), -2);
				END;
			END;
			IF DebugMAC IN Debug THEN
				AosOut.Ln;
			END;
			dev.adrSize := 6;
		END ReadMACAddress;
		
		PROCEDURE Read8(reg: LONGINT): SHORTINT;
		BEGIN
			RETURN SYSTEM.GET8(base + reg);
		END Read8;
		
		PROCEDURE Write8(reg: LONGINT; val: LONGINT);
		BEGIN
			SYSTEM.PUT8(base + reg, SHORT(SHORT(val)));
		END Write8;
		
		PROCEDURE Read16(reg: LONGINT): INTEGER;
		BEGIN
			RETURN SYSTEM.GET16(base + reg);
		END Read16;
		
		PROCEDURE Write16(reg: LONGINT; val: LONGINT);
		BEGIN
			SYSTEM.PUT16(base + reg, SHORT(val));
		END Write16;
		
		PROCEDURE Read32(reg: LONGINT): LONGINT;
		BEGIN
			RETURN SYSTEM.GET32(base + reg);
		END Read32;
		
		PROCEDURE Write32(reg: LONGINT; val: LONGINT);
		BEGIN
			SYSTEM.PUT32(base + reg, val);
		END Write32;
		
		PROCEDURE EnableTBI;
		VAR
			s: SET;
			i: LONGINT;
		BEGIN
			IF 7 IN SYSTEM.VAL(SET, Read8(6CH)) THEN RETURN END;
			
			s := PHYRead(04H) + {5..8};	(* advertise 10 full/half, 100 full/half *);
			PHYWrite(04H, s);
			PHYWrite(09H, {9}); (* advertise 1000 full *)
			
			(* enable and restart auto negotiation *)
			PHYWrite(00H, {9, 12});
			Delay(100);
			
			FOR i := 1 TO 1000 DO
				s := PHYRead(01H);
				IF 5 IN s THEN (* auto negotiation complete *)
					Delay(100);
					IF DebugStatus IN Debug THEN
						PrintStatus;
					END;
					RETURN;
				ELSE
					Delay(100);
				END;
			END;
		END EnableTBI;
		
		PROCEDURE HwReset;
		VAR
			s: SET;
			i: LONGINT;
		BEGIN
			s := PHYRead(00H) + {15};
			PHYWrite(00H, s);
			
			(* wait until reset has been completet *)
			FOR i := 1 TO 50 DO
				IF ~(15 IN PHYRead(00H)) THEN
					RETURN;
				END;
			END;
		END HwReset;
		
		PROCEDURE PHYWrite(regAdr: LONGINT; data: SET);
		VAR
			s: SET;
			i: LONGINT;
		BEGIN
			s := {31};
			s := s + (SYSTEM.VAL(SET, regAdr * 010000H) * {16..20});
			s := s + (data * {0..15});
			Write32(60H, SYSTEM.VAL(LONGINT, s));
			Delay(100);
			
			(* wait until write has been completet *)
			FOR i := 1 TO 2000 DO
				IF SYSTEM.VAL(SET, Read32(60H)) * {31} = {} THEN
					RETURN;
				END;
				Delay(100);
			END;
		END PHYWrite;
		
		PROCEDURE PHYRead(regAdr: LONGINT): SET;
		VAR
			s: SET;
			i: LONGINT;
		BEGIN
			s := SYSTEM.VAL(SET, regAdr * 010000H) * {16..20};
			Write32(60H, SYSTEM.VAL(LONGINT, s));
			Delay(100);
			
			(* wait until read has been completed *)
			FOR i := 1 TO 2000 DO
				s := SYSTEM.VAL(SET, Read32(60H));
				IF 31 IN s THEN
					RETURN (s * {0..15});
				END;
				Delay(100);
			END;
			RETURN {};
		END PHYRead;
					
		PROCEDURE AllocBuffer(VAR buf: TxBuffer);
		BEGIN
			NEW(buf); (* edit: no more alignment necessary, since PTR TO RECORD is already 32 byte aligned *)
		END AllocBuffer;
		
		PROCEDURE SetupRxRing(): LONGINT;
		VAR
			r, adr, physAdr: LONGINT;
			buf, prev: RxBuffer;
		BEGIN
			(* make sure the descriptor ring is 256 byte aligned in physical memory *)
			adr := SYSTEM.ADR(rds[0]);
			adr := AosMemory.PhysicalAdr(adr, SizeOfRxTxFDHdr);
			IF adr MOD 256 = 0 THEN
				firstRD := 0;
			ELSE
				firstRD := 16 - ((adr MOD 256) DIV 16);
			END;
			
			IF DebugRxRing IN Debug THEN
				AosOut.String("Rx descriptor start = ");
				AosOut.Hex(adr, 8);
				AosOut.Ln;
				AosOut.String("first Rx descriptor id = ");
				AosOut.Int(firstRD, 0);
				AosOut.Ln;
			END;
			
			FOR r := firstRD TO RxRingSize - 1 DO
				NEW(buf);
				buf.buf := AosNet.GetNewBuffer();
				ASSERT(buf.buf # NIL);
				
				adr := SYSTEM.ADR(buf.buf.data[0]);
				physAdr := AosMemory.PhysicalAdr(adr, AosNet.MaxPacketSize);
				ASSERT(physAdr # AosMemory.NilAdr);
				
				rds[r].flags := {31};
				rds[r].flags := rds[r].flags + (SYSTEM.VAL(SET, AosNet.MaxPacketSize) * {0..13});
				rds[r].vLanTag := 0;
				rds[r].bufAdrLo := physAdr;
				rds[r].bufAdrHi := 0;
				
				IF prev # NIL THEN
					prev.next := buf;
				ELSE
					(* set first Rx Buffer *)
					rxBuffer := buf;
				END;
				prev := buf;
			END;
			rxLast := buf;
			rxLast.next := rxBuffer;
			
			(* mark last descriptor as EOR (end of descriptor ring) *)
			INCL(rds[RxRingSize - 1].flags, 30);
			
			curRD := firstRD;
			adr := SYSTEM.ADR(rds[firstRD]);
			(* return physical address of first rx descriptor *)
			RETURN AosMemory.PhysicalAdr(adr, SizeOfRxTxFDHdr);
		END SetupRxRing;
		
		PROCEDURE SetupTxRing(): LONGINT;
		VAR
			r, adr, physAdr: LONGINT;
			buf, prev: TxBuffer;
		BEGIN
			(* make sure the descriptor ring is 256 byte aligned in physical memory *)
			adr := SYSTEM.ADR(tds[0]);
			adr := AosMemory.PhysicalAdr(adr, SizeOfRxTxFDHdr);
			IF adr MOD 256 = 0 THEN
				firstTD := 0;
			ELSE
				firstTD := 16 - ((adr MOD 256) DIV 16);
			END;
			lastTD := firstTD;
			nofFreeTx := TxRingSize - firstTD;
			
			IF DebugTxRing IN Debug THEN
				AosOut.String("Tx descriptor start = ");
				AosOut.Hex(adr, -8);
				AosOut.Ln;
				AosOut.String("first Tx descriptor id = ");
				AosOut.Int(firstTD, 0);
				AosOut.Ln;
				AosOut.String("nofFreeTx = ");
				AosOut.Int(nofFreeTx, 0);
				AosOut.Ln;
			END;
			
			FOR r := firstTD TO TxRingSize - 1 DO
				AllocBuffer(buf);

				(* configure TFD *)
				adr := SYSTEM.ADR(buf.data[0]);
				physAdr := AosMemory.PhysicalAdr(adr, TxMaxSize);
				ASSERT(physAdr # AosMemory.NilAdr);
				
				tds[r].flags := {};
				tds[r].vLanTag := 0;
				tds[r].bufAdrLo := physAdr;
				tds[r].bufAdrHi := 0;
				
				IF prev # NIL THEN
					prev.next := buf;
				ELSE
					(* set first Tx Buffer *)
					txBuffer := buf;
				END;
				prev := buf;
			END;
			txLast := buf;
			txLast.next := txBuffer;
			
			(* mark last descriptor as EOR (end of descriptor ring) *)
			INCL(tds[TxRingSize - 1].flags, 30);
			
			curTD := firstTD;
			adr := SYSTEM.ADR(tds[firstTD]);
			(* return physical address of first tx descriptor *)
			RETURN AosMemory.PhysicalAdr(adr, SizeOfRxTxFDHdr);
		END SetupTxRing;
		
		PROCEDURE ReadFrames;
		VAR
			adr, type, size, i: LONGINT;
			dstAdr: AosNet.LinkAdr;
			buf: AosNet.Buffer;
			rx: RxBuffer;
			s: SET;
		BEGIN
			(* read all frames that are marked with OWN = 0*)
			WHILE ~(31 IN rds[curRD].flags) DO
				(* skip error frames *)
				IF (21 IN rds[curRD].flags) THEN
					INC(nRxErrorFrames);
				ELSIF CheckChecksumErrors(rds[curRD]) THEN
					(* find out how many bytes have been received, including CRC *)
					size := SYSTEM.VAL(LONGINT, rds[curRD].flags * {0..13});

					IF DebugReceive IN Debug THEN
						AosOut.String("Received a frame of length ");
						AosOut.Int(size, 0);
						AosOut.Ln;
					END;
					
					adr := SYSTEM.ADR(rxBuffer.buf.data[0]);
					(* copy destination and source addresses, type of packet *)
					dstAdr := SYSTEM.VAL(AosNet.LinkAdr, rxBuffer.buf.data[0]);
					rxBuffer.buf.src := SYSTEM.VAL(AosNet.LinkAdr, rxBuffer.buf.data[6]);
					type := AosNet.GetNet2(rxBuffer.buf.data, 12);
					
					buf := rxBuffer.buf;
					buf.ofs := 14;
					buf.len := size - 14;
					buf.calcChecksum := { AosNet.ChecksumIP, AosNet.ChecksumUDP, AosNet.ChecksumTCP };
					buf.next := NIL;
					buf.prev := NIL;
					IF type = 0DEADH THEN
						(* make sure the frame doesn't bounce between the two cards by adding 1 to the type *)
						SendFrame(buf.src, type + 1, buf.data, buf.data, buf.data, 0, 0, 0, buf.len);
					ELSIF type = 0DEADH + 1 THEN
						(* discard this frame *)
					ELSE
					dev.QueueBuffer(buf, type);
					END;
				
					INC(nRxFrames);
					
					IF (type # 0DEADH) & (type # 0DEADH + 1) THEN
					rxBuffer.buf := AosNet.GetNewBuffer();
					buf := rxBuffer.buf;
					ASSERT(rxBuffer.buf # NIL);
					IF buf # NIL THEN
						rds[curRD].bufAdrLo := AosMemory.PhysicalAdr(SYSTEM.ADR(rxBuffer.buf.data[0]), AosNet.MaxPacketSize);
					END;
					END;
				ELSE
					IF DebugReceive IN Debug THEN
						AosOut.String("Checksum error detected!"); AosOut.Ln;
					END;
					INC(nRxErrorFrames);
				END;
				
				(* mark the buffer to be able to receive again *)
				rds[curRD].flags := {31} + (rds[curRD].flags * {30}) + (SYSTEM.VAL(SET, AosNet.MaxPacketSize) * {0..13});
				rds[curRD].vLanTag := 0;
				s := rds[curRD].flags;
				
				(* advance Rx descriptor, Rx buffer *)
				rxBuffer := rxBuffer.next;
				INC(curRD);
				IF curRD = RxRingSize THEN
					curRD := firstRD;
				END;
			END;
		END ReadFrames;
		
		PROCEDURE CheckChecksumErrors(d: RxTxDescriptor): BOOLEAN;
		VAR proto: SET;
		BEGIN
			proto := d.flags * {17..18};
			IF proto = {} THEN
				RETURN TRUE;	(* no checksum errors since non-ip packet *)
			ELSIF proto = {17} THEN
				(* protocol is TCP/IP so check IP and TCP checksum failures *)
				RETURN d.flags * {14, 16} = {};
			ELSIF proto = {18} THEN
				(* protocol is UDP/IP so check IP and UDP checksum failures *)
				RETURN d.flags * {15, 16} = {};
			ELSE
				(* protocol is IP so check IP checksum failures *)
				RETURN d.flags * {16} = {};
			END;
		END CheckChecksumErrors;
		
		PROCEDURE HandleInterrupt;
		VAR
			status, ack: SET;
		BEGIN
			(* get current interrupt mask, disable all interrupts *)
			Write16(3CH, 0);
			
			ack := {0};
			(* read interrupt status, @ offset 3EH - 3FH *)
			status := SYSTEM.VAL(SET, Read16(3EH));
			
			(* System Error (SERR) *)
			IF (15 IN InterruptMask) & (15 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					AosOut.String("System Error Interrupt"); AosOut.Ln;
				END;
				INCL(ack, 15);
			END;
			
			(* Time Out (TimeOut) *)
			IF (14 IN InterruptMask) & (14 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					AosOut.String("Timeout Interrupt"); AosOut.Ln;
				END;
				INCL(ack, 14);
			END;
			
			IF (8 IN InterruptMask) & (8 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					AosOut.String("Software Interrupt"); AosOut.Ln;
				END;
				INCL(ack, 8);
			END;
			
			IF (7 IN InterruptMask) & (7 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					AosOut.String("Tx Descriptor Unavailable Interrupt"); AosOut.Ln;
				END;
				INCL(ack, 7);
				(*UpdateTxRing;*)
				(*INCL(status, 2); (* let the tx ring be updated *)*)
			END;
			
			(* Rx FIFO Overflow (FOVW) *)
			IF (6 IN InterruptMask) & (6 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					AosOut.String("Rx FIFO Overflow Interrupt"); AosOut.Ln;
				END;
				INC(nRxOverflow);
				INCL(ack, 6);
				(*INCL(ack, 4);*)
				(*INCL(status, 0); (* read the frames *)*)
			END;
			
			(* Link Change (LinkChg) *)
			IF (5 IN InterruptMask) & (5 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					AosOut.String("Link Change Interrupt"); AosOut.Ln;
				END;
				UpdateLinkStatus;
				INCL(ack, 5);
			END;
			
			(* Rx Descriptor Unavailable (RDU) *)
			IF (4 IN InterruptMask) & (4 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					(* CAREFUL: UN-COMMENTING THE NEXT LINE CAN CRASH THE OS *)
					(*AosOut.String("Rx Descriptor Unavailable Interrupt"); AosOut.Ln;*)
				END;
				INCL(ack, 4);
				(*INCL(status, 0); (* read the frames *)*)
			END;
			
			(* Transmit (Tx) Error (TER) *)
			IF (3 IN InterruptMask) & (3 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					AosOut.String("Transmit Error Interrupt"); AosOut.Ln;
				END;
				INCL(ack, 3);
				INC(nTxErrorFrames);
				INCL(status, 2); (* let the tx ring be updated *)
			END;
			
			(* Transmit (Tx) OK (TOK) *)
			IF (2 IN InterruptMask) & (2 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					AosOut.String("Transmit OK Interrupt"); AosOut.Ln;
				END;
				UpdateTxRing;
				INCL(ack, 2);
			END;
			
			(* Receive (Rx) Error (RER) *)
			IF (1 IN InterruptMask) & (1 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					AosOut.String("Receive Error Interrupt"); AosOut.Ln;
				END;
				INCL(ack, 1);
				(*ReadFrames;*)
				INCL(status, 0); (* let the rx ring be updated *)
			END;
			
			(* Receive (Rx) OK (ROK) *)
			IF (0 IN InterruptMask) & (0 IN status) THEN
				IF DebugInterrupt IN Debug THEN
					(* CAREFUL: UN-COMMENTING THE NEXT LINE CAN CRASH THE OS *)
					(*AosOut.String("Receive Ok Interrupt"); AosOut.Ln;*)
				END;
				ReadFrames;
				INCL(ack, 0); (* read the frames *)
			END;
			
			ack := status;
			(* reset interrupt status *)
			Write16(3EH, SYSTEM.VAL(LONGINT, ack));
			
			(* re-enable interrupts *)
			Write16(3CH, SYSTEM.VAL(LONGINT, InterruptMask));
		END HandleInterrupt;
		
		PROCEDURE UpdateLinkStatus;
		BEGIN
			IF 1 IN SYSTEM.VAL(SET, Read8(6CH)) THEN
				linkStatus := AosNet.LinkLinked;
			ELSE
				linkStatus := AosNet.LinkNotLinked;
			END;
		END UpdateLinkStatus;
		
		PROCEDURE UpdateTxRing;
		VAR i: LONGINT;
		BEGIN { EXCLUSIVE }
			i := lastTD;
			WHILE (i # curTD) DO
				IF DebugTransmit IN Debug THEN
					AosOut.String("*** Tx OK ***"); AosOut.Ln;
				END;
				INC(i);
				INC(nTxFrames);
				INC(nofFreeTx);
				IF i = TxRingSize THEN
					i := firstTD;
				END;
				txLast := txLast.next;
			END;
			lastTD := i;
		END UpdateTxRing;
		
		PROCEDURE Finalize;
		VAR
			s: SET;
		BEGIN
			(* cleanup AosNet registry *)
			AosNet.registry.Remove(dev);
			
			(* disable Tx and Rx *)
			s := SYSTEM.VAL(SET, Read8(37H));
			Write8(37H, SYSTEM.VAL(SHORTINT, s - {2, 3}));
			
			(* soft reset *)
			Write8(37H, SYSTEM.VAL(SHORTINT, {4}));
			
			(* disable all interrupts *)
			Write16(3CH, 0);
			
			WHILE (rxBuffer # NIL) & (rxBuffer.buf # NIL) DO
				AosNet.ReturnBuffer(rxBuffer.buf);
				rxBuffer.buf := NIL;
				rxBuffer := rxBuffer.next;
			END;
			
			IF DebugCleanup IN Debug THEN
				AosOut.String("Removing IRQ Handler.");
				AosOut.Ln
			END;
			AosActive.RemoveHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0 + irq);
		END Finalize;
		
		PROCEDURE DebugConfig();
		VAR
			s: SET;
			res: LONGINT;
		BEGIN
			AosOut.String("*** BEGIN OF NIC CONFIGURATION ***"); AosOut.Ln;
			
			s := SYSTEM.VAL(SET, Read16(0E0H));
			AosOut.String("C+ Command:"); AosOut.Ln;
			AosOut.String("  "); AosOut.Bits(s, 0, 16); AosOut.Ln;
			
			AosOut.String("Rx Descriptor base address:"); AosOut.Ln;
			AosOut.String("  ");
			res := Read32(0E4H + 4H);
			AosOut.Hex(res, 8);
			res := Read32(0E4H);
			AosOut.Hex(res, 8);
			AosOut.Ln;
			
			AosOut.String("Tx Normal Priority Descriptor base address:"); AosOut.Ln;
			AosOut.String("  ");
			res := Read32(020H + 4H);
			AosOut.Hex(res, 8);
			res := Read32(020H);
			AosOut.Hex(res, 8);
			AosOut.Ln;
			
			res := Read16(0DAH);
			AosOut.String("Receive Packet Max Size:"); AosOut.Ln;
			AosOut.String("  "); AosOut.Int(res, 0); AosOut.Ln;
			
			res := Read8(0ECH);
			AosOut.String("Max Transmit Packet Size:"); AosOut.Ln;
			AosOut.String("  "); AosOut.Int(res * 32, 0); AosOut.Ln;
			
			s := SYSTEM.VAL(SET, Read32(40H));
			AosOut.String("Transmit Configuration:"); AosOut.Ln;
			AosOut.String("  "); AosOut.Bits(s, 0, 32); AosOut.Ln;
			
			s := SYSTEM.VAL(SET, Read32(44H));
			AosOut.String("Receive Configuration:"); AosOut.Ln;
			AosOut.String("  "); AosOut.Bits(s, 0, 32); AosOut.Ln;
			
			s := SYSTEM.VAL(SET, Read16(3CH));
			AosOut.String("interrupt mask:"); AosOut.Ln;
			AosOut.String("  "); AosOut.Bits(s, 0, 16); AosOut.Ln;
			
			s := SYSTEM.VAL(SET, Read8(37H));
			AosOut.String("command bits:"); AosOut.Ln;
			AosOut.String("  "); AosOut.Bits(s, 0, 8); AosOut.Ln;
			
			AosOut.String("*** END OF NIC CONFIGURATION ***"); AosOut.Ln;
		END DebugConfig;
		
		PROCEDURE PrintStatus();
		VAR
			phyStatus: SET;
		BEGIN
			phyStatus := SYSTEM.VAL(SET, Read8(6CH));

			IF 1 IN phyStatus THEN
				AosOut.String("  Device is linked");
				AosOut.Ln;
			ELSE
				AosOut.String("  Device is NOT linked");
				AosOut.Ln;
			END;

			IF 4 IN phyStatus THEN
				AosOut.String("  Linkspeed is 1GBps Full-Duplex");
				AosOut.Ln;
			ELSE
				IF 3 IN phyStatus THEN
					AosOut.String("  Linkspeed is 100MBps");
					AosOut.Ln;
				ELSIF 2 IN phyStatus THEN
					AosOut.String("  Linkspeed is 10MBps");
					AosOut.Ln;
				END;
				IF 0 IN phyStatus THEN
					AosOut.String("  Device is in FULL-DUPLEX MODE");
					AosOut.Ln;
				ELSE
					AosOut.String("  Device is in Half-Duplex Mode");
					AosOut.Ln;
				END;
			END;
			
			IF 6 IN phyStatus THEN
				AosOut.String("  Transmit Flow Control enabled");
				AosOut.Ln;
			END;
			
			IF 5 IN phyStatus THEN
				AosOut.String("  Receive Flow Control enabled");
				AosOut.Ln;
			END;
			
			AosOut.String("  nRxOverflow = ");
			AosOut.HIntHex(nRxOverflow, 16);
			AosOut.Ln;
			
			AosOut.String("  nTxOverflow = ");
			AosOut.HIntHex(nTxOverflow, 16);
			AosOut.Ln;
			
			AosOut.String("  Rx Missed Packet Counter = ");
			AosOut.Int(Read32(4CH), 0);
			AosOut.Ln;
			
			AosOut.String("  nRxFrames = ");
			AosOut.Int(nRxFrames, 0);
			AosOut.Ln;
			
			AosOut.String("  nTxFrames = ");
			AosOut.Int(nTxFrames, 0);
			AosOut.Ln;
			
			AosOut.String("  nRxErrorFrames = ");
			AosOut.Int(nRxErrorFrames, 0);
			AosOut.Ln;
			
			AosOut.String("  nTxErrorFrames = ");
			AosOut.Int(nTxErrorFrames, 0);
			AosOut.Ln;
		END PrintStatus;
	END Controller;

 VAR
	installedControllers: Controller;

(* Scan the PCI bus for the specified card. *)
PROCEDURE ScanPCI(vendor, device: LONGINT);
VAR index, bus, dev, fct, res, base, irq, i: LONGINT; d: LinkDevice; c: Controller; name: AosPlugins.Name;
BEGIN
	index := 0;
	WHILE (PCI.FindPCIDevice(device, vendor, index, bus, dev, fct) = PCI.Done) & (installed < 16) DO
		res := PCI.ReadConfigDword(bus, dev, fct, PCI.Adr1Reg, base); ASSERT(res = PCI.Done);
		ASSERT(~ODD(base)); (* memory mapped *)
		DEC(base, base MOD 16);
		AosMemory.MapPhysical(base, 0FFH, base);
		
		res := PCI.ReadConfigByte(bus, dev, fct, PCI.IntlReg, irq); ASSERT(res = PCI.Done);
		NEW(d, AosNet.TypeEthernet, MaxETHFrameSize - 14, 6);
		name := Name;
		i := 0; WHILE name[i] # 0X DO INC(i) END;
		IF installed > 9 THEN
			name[i] := CHR(ORD("A") + installed - 10);
		ELSE
			name[i] := CHR(ORD("0") + installed);
		END;
		name[i+1] := 0X;
		IF DebugFind IN Debug THEN
			AosOut.String("Found device: ");
			AosOut.String(name);
			AosOut.String("; IRQ = ");
			AosOut.Int(irq, 0);
			AosOut.Ln;
		END;
		d.SetName(name);
		d.desc := Description;
		
		NEW(c, d, base, irq);	 (* increments "installed" when successful *)
		IF DebugStatus IN Debug THEN
			c.PrintStatus;
		END;
		INC(index)
	END
END ScanPCI;

PROCEDURE Install*(par : PTR) :PTR;
BEGIN {EXCLUSIVE}
	IF DebugFind IN Debug THEN
		AosOut.String("Searching devices...");
		AosOut.Ln
	END;
	IF installed = 0 THEN
		ScanPCI(10ECH, 8169H);	(* Vendor = RealTek, Device = RTL8169 *)
	END;
	IF DebugFind IN Debug THEN
		AosOut.String("Find finished.");
		AosOut.Ln
	END;
	RETURN NIL
END Install;

PROCEDURE DebugStati*(par : PTR) :PTR;
VAR c: Controller;
BEGIN
	c := installedControllers;
	WHILE c # NIL DO
		c.PrintStatus;
		c := c.next;
	END;
	RETURN NIL;
END DebugStati;

PROCEDURE TestDevices*(par : PTR) :PTR;
VAR c: Controller;
BEGIN
	c := installedControllers;
	WHILE c # NIL DO
		TestDevice(c);
		c := c.next;
	END;
	RETURN NIL;
END TestDevices;

PROCEDURE TestDevice(ctrl: Controller);
VAR
	i, start, diff, bytes, times: LONGINT;
	data: ARRAY 1024 OF CHAR;
	bw: REAL;
	dst: AosNet.LinkAdr;
BEGIN
	dst[0] := 000X;
	dst[1] := 030X;
	dst[2] := 04FX;
	dst[3] := 025X;
	dst[4] := 0BBX;
	dst[5] := 0DBX;
	IF ctrl # NIL THEN
		ctrl.nRxFrames := 0;
		ctrl.nTxFrames := 0;
		(* fill the buffer *)
		FOR i := 0 TO LEN(data)-1 DO
			data[i] := CHR(i MOD 100H)
		END;
		
		start := AosKernel.GetTimer();
		times := 1024 * 1024 * 2;
		FOR i := 1 TO times DO
			ctrl.SendFrame(dst, 0DEADH, data, data, data, 0, 0, 0, LEN(data));
			IF i MOD 1024 = 0 THEN
				Delay(1);
			END;
		END;
		diff := AosKernel.GetTimer() - start;
		times := ctrl.nRxFrames * 2;
		bytes := (LEN(data));
		AosOut.String("stats:"); AosOut.Ln;
		AosOut.String("frame size = ");
		AosOut.Int(bytes, 0);
		AosOut.String("; num frames = ");
		AosOut.Int(times, 0);
		AosOut.String("; time = ");
		AosOut.Int(diff, 0); AosOut.String("ms");
		AosOut.String("; bandwidth = ");
		bw := bytes * 1.0 * times / (diff / 1000.0);
		AosOut.Int(ENTIER(bw / 1024), 0); AosOut.String("KB/s, ");
		AosOut.Int(ENTIER(bw * 8 / 1000 / 1000), 0); AosOut.String("Mbps"); AosOut.Ln;
	END
END TestDevice;


PROCEDURE Cleanup;
BEGIN
	WHILE installedControllers # NIL DO
		IF DebugCleanup IN Debug THEN
			AosOut.Ln;
			AosOut.String("Removing ");
			AosOut.String(installedControllers.dev.name);
			AosOut.Ln;
			installedControllers.PrintStatus;
		END;
		installedControllers.Finalize;
		installedControllers := installedControllers.next;
		IF DebugCleanup IN Debug THEN
			AosOut.String("Success!");
			AosOut.Ln;
		END;		
	END;
	installedControllers := NIL;
END Cleanup;

PROCEDURE Delay(ms: LONGINT);
VAR
	t: AosKernel.MilliTimer;
BEGIN
	AosKernel.SetTimer(t, ms);
	REPEAT UNTIL AosKernel.Expired(t);
END Delay;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END AosRTL8169.

(*
MAC address 00-30-4F-25-BB-DB
MAC address 00-08-A1-3C-06-CB

local IP 129.132.134.209

S.Free AosRTL8169 ~
AosRTL8169.Install ~
WMPerfMon.Open ~
AosRTL8169.DebugStati ~

AosIP.IPConfig ~

AosRTL8169.TestDevices~

OFSTools.Mount RAM RamFS 300000 4096 ~

WebFTPServer.AddUser x x -1 rw  AOS:~
WebFTPServer.AddUser anonymous none -1 rw AOS: ~
WebFTPServer.RemoveUser user ~
WebFTPServer.ListUsers


AosTestNet.SetDevice "RTL8169#0" ~
AosTestNet.ShowDevices ~
AosTestNet.SendBroadcast ~
AosTestNet.SendBroadcastVar 1499 ~
AosTestNet.SendTest ^ 1 10 100 1000 ~
*)
