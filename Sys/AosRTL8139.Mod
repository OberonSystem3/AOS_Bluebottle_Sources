MODULE AosRTL8139; (** AUTHOR "TF"; PURPOSE "Realtek RTL8139 ethernet driver"; *)

(* references : 
	RTL 8139C(L) Preliminary, REALTEK Semiconductor Corp., Rev 1.1 1999/11/4
	RTL 8139(a/B) Programming guide (V0.1) 1999/1/15
	
	This driver is not optimized for speed. It has been tested on Chipset8139 and Chipset8139C. Please report success / failure with
	other 8139 compatible chipsets.
*)

IMPORT
		SYSTEM, AosKernel, AosInterrupts, AosMemory, PCI, AosActive, AosModules, AosPlugins, AosNet, AosOut
		, AosFS;

CONST
	Name = "RTL8139#";
	Desc = "RealTek 8139 ethernet driver";
	Model8139 = 0;  Model8139CB = 1; ModelSMC1211TX = 2; ModelDELTA8139 = 3; ModelADDTRON8139 = 4; ModelDFE528TX = 5;
	Model8129 = 7; MaxModel = 8;
	
	Chipset8139 = 0; Chipset8139K = 1; Chipset8139A = 2; Chipset8139B = 3; Chipset8130 = 4; Chipset8139C = 5;
	NofChipsets = 6;

	HasPwrDn = 0; HasLWake = 1;
	
	DebugFind = TRUE; DebugInit = TRUE; DebugCleanup = TRUE; DebugTransmit = FALSE; DebugReceive = FALSE;

	RegisterInAosNet = TRUE; CallAosNetReceiver = TRUE; Min60BytePacket = TRUE;
	
	ReceiveAll = FALSE;
	
	RxBufLenIdx = 2;
	RxBufLen = ASH(8192, RxBufLenIdx) ;
	RxBufPad = 16;
	RxBufWrapPad = 2048;
	RxBufSize = RxBufLen + RxBufPad + RxBufWrapPad;
	MaxETHFrameSize = 1514;
	MaxPacketsPerIRQ = 10;
	
VAR
	installed: LONGINT;	(* number of installed devices *)
	logtime: AosKernel.MilliTimer;
	
TYPE
	ChipsetSpecific = RECORD
		name: ARRAY 32 OF CHAR;
		version: LONGINT;
		configSet, flags: SET;
	END;
	
VAR
	chipsetInfo: ARRAY MaxModel OF ChipsetSpecific;

	(* Interrupt statistics (only with one adapter) *)
	nPCIError, nTimeOut, nCableLengthChg, nFifoOverflow, nPUnOrLnkChg, 
	nRxBufferOverflow, nTxError, nTxOk, nRxError, nRxOk :LONGINT;
	nofInstalled: LONGINT;
	
	logging : BOOLEAN;
	log :AosFS.Rider;
TYPE
	LinkDevice = OBJECT (AosNet.LinkDevice)
		VAR ctrl: Controller;

		PROCEDURE Linked*(): LONGINT;
			BEGIN
			IF ctrl.Linked() THEN
				RETURN AosNet.LinkLinked;
			ELSE
				RETURN AosNet.LinkNotLinked;
			END;
		END Linked;
		
		PROCEDURE DoSend*(dst: AosNet.LinkAdr; type: LONGINT; VAR l3hdr, l4hdr, data: ARRAY OF CHAR;  h3len, h4len, dofs, dlen: LONGINT);
		VAR i, bufAdr:LONGINT; txState:LONGINT; txs:SET; t, totlen:LONGINT;
		BEGIN {EXCLUSIVE}
			(* Disable IRQ *)
			SYSTEM.PUT16(ctrl.base + 3CH, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(SYSTEM.GET16(ctrl.base + 3CH)))-{0..6, 13..15}));
			
			bufAdr:=SYSTEM.ADR(ctrl.txBuffers[ctrl.nextTxBuffer]^[0]);
			SYSTEM.MOVE(SYSTEM.ADR(dst[0]), bufAdr, 6);
			SYSTEM.MOVE(SYSTEM.ADR(local[0]), bufAdr+6, 6);
			SYSTEM.PUT16(bufAdr+12, SYSTEM.ROT(SYSTEM.VAL(INTEGER, SHORT(type)), 8));
			i:=14;
			IF h3len > 0 THEN SYSTEM.MOVE(SYSTEM.ADR(l3hdr[0]),  bufAdr+i, h3len); INC(i, h3len) END;
			IF h4len > 0 THEN SYSTEM.MOVE(SYSTEM.ADR(l4hdr[0]),  bufAdr+i, h4len); INC(i, h4len) END;
			IF i + dlen < MaxETHFrameSize THEN 
				SYSTEM.MOVE(SYSTEM.ADR(data[0]) + dofs,  bufAdr + i, dlen); INC(i, dlen);
			END;	
			
			IF Min60BytePacket THEN WHILE i<60 DO ctrl.txBuffers[ctrl.nextTxBuffer]^[i] := CHR(0); INC(i) END END;
			totlen := i;
			IF DebugTransmit THEN 
				AosOut.Enter; AosOut.String("[TRANSMIT] Packet length:"); AosOut.Int(i, 5); AosOut.String(" data ..."); AosOut.Ln;
				AosOut.Buffer(ctrl.txBuffers[ctrl.nextTxBuffer]^, 0, i);
				AosOut.Exit;
			END;
			IF i <= MaxETHFrameSize THEN
				SYSTEM.PUT32(ctrl.base + 20H+4*ctrl.nextTxBuffer, bufAdr); (* set Transmit Start Address *)
				txState:=8*32*2048; (* threshold 256 *) 
				txState:=txState+i;
				SYSTEM.PUT32(ctrl.base + 10H+4*ctrl.nextTxBuffer, txState); (* send *)
				i:=0; WHILE (i<10000000) & (SYSTEM.VAL(SET, SYSTEM.GET32(ctrl.base+10H+4*ctrl.nextTxBuffer)) * {14, 15, 30} = {}) DO
					INC(i) 
				END;

				IF i=10000000 THEN AosOut.Enter; AosOut.String("MegaError !!!"); AosOut.Exit; ctrl.Reset END; 
				
				IF DebugTransmit THEN 
					AosOut.Enter;
					IF i<10000000 THEN  
						txs:=SYSTEM.VAL(SET, SYSTEM.GET32(ctrl.base+10H+4*ctrl.nextTxBuffer));
						IF 13 IN txs THEN AosOut.String(" DMA Completed ") END;
						IF 14 IN txs THEN AosOut.String(" Fifo underrun ") END;
						IF 15 IN txs THEN AosOut.String(" Transmit OK ") END;
						IF 30 IN txs THEN AosOut.String(" Transmit ABORTED ") END
					ELSE AosOut.String("Transmit timed out ");
						 AosOut.Bits(SYSTEM.VAL(SET, SYSTEM.GET32(ctrl.base+10H+4*ctrl.nextTxBuffer)), 0, 32)
					END;
					AosOut.Exit
				END;
				INC(sendCount);
				 ctrl.nextTxBuffer :=  (ctrl.nextTxBuffer + 1) MOD 4 
			END
			;
			(* Enable IRQ *)
			SYSTEM.PUT16(ctrl.base + 3CH, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(SYSTEM.GET16(ctrl.base + 3CH)))+{0..6, 13..15}));
			IF logging THEN
				t := AosKernel.Elapsed(logtime);
				AosFS.WriteLInt(log, t DIV 1000);  
				AosFS.WriteLInt(log, (t MOD 1000)*1000+1);
				AosFS.WriteLInt(log, totlen);  AosFS.WriteLInt(log, totlen);
				log.file.WriteBytes(log, ctrl.txBuffers[ctrl.nextTxBuffer]^, 0, totlen)
			END
		END DoSend;
		
		PROCEDURE Finalize(connected: BOOLEAN);
		BEGIN
			ctrl.Finalize;
			Finalize^(connected);
		END Finalize;
		
	END LinkDevice;
	
	
	Controller = OBJECT
		VAR
			next: Controller;
			base, irq: LONGINT;
			dev: LinkDevice;
			model, chipset: LONGINT;
			media: SET;
			rxBufPos: LONGINT;
			timer: AosKernel.Timer;
			eepromAdrLen:LONGINT;
			
			devAdr:ARRAY 3 OF LONGINT;
			
			rxBuffer: POINTER TO ARRAY OF CHAR; (* ring buffer *)
			rxAdr: LONGINT; (* ring buffer physical adr *) 
			nextTxBuffer: LONGINT;
			txBuffers: ARRAY 4 OF POINTER TO ARRAY OF CHAR; 
			
			rcvAdr, rcvSize:LONGINT;
		
		PROCEDURE FlushWrite8(reg, val:LONGINT);
		BEGIN
			SYSTEM.PUT8(base + reg, val); (* force flush *) val := SYSTEM.GET8(base + reg) 
		END FlushWrite8;
		
	PROCEDURE Reset;
	VAR i, dp, dummy:LONGINT; val:SET;
	BEGIN	nextTxBuffer:=0;
				;AosOut.Enter; AosOut.String("Softreset"); AosOut.Exit;
			(* soft reset *)
			SYSTEM.PUT8(base + 37H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 37H)))) + {4})); (* command register: 4 soft reset *)
			dp:=0;
			LOOP INC(dp); timer.Sleep(1); IF (SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 37H)))) * {4} = {})  OR (dp=100) THEN EXIT END END;
			
			(* assert PIO and MMIO enabled *)
			val := SYSTEM.VAL(SET, SYSTEM.GET8(base + 52H));
			IF val * {3} = {} THEN AosOut.String("MMIO is disabled."); HALT(1000) END;
			IF val * {2} = {} THEN AosOut.String("IO mapping is disabled."); HALT(1000) END;
			
			(* enable Tx / Rx *)
			FlushWrite8(37H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 37H))))* {1, 5, 6, 7} + {2 , 3}));

			(* initialize the rxBuffer *)
			SYSTEM.PUT32(base + 30H, SYSTEM.ADR(rxBuffer[0]));
			rxBufPos:=0; SYSTEM.PUT16(base+38H, rxBufPos-16); dummy:=SYSTEM.GET16(base + 38H);
		
			(* initialize packet types *)
(*			IF ReceiveAll THEN SYSTEM.PUT32(base + 44H, SYSTEM.VAL(SET, SYSTEM.GET32(base + 44H)) - {24..27, 13..15} + {24(*..27, 13..15*), 12, 8..10, 7, 0..4})
			ELSE SYSTEM.PUT32(base + 44H, SYSTEM.VAL(SET, SYSTEM.GET32(base + 44H)) - {24..27, 13..15} + {24(*..27, 13..15*), 12, 8..10, 7, 1..4})
			END; *)
			
			IF ReceiveAll THEN 
				SYSTEM.PUT32(base + 44H, 
					SYSTEM.VAL(SET, SYSTEM.GET32(base + 44H)) * chipsetInfo[chipset].configSet + {24(*..27, 13..15*), 12, 8..10, 7, 0..4})
			ELSE 
				SYSTEM.PUT32(base + 44H, 
					SYSTEM.VAL(SET, SYSTEM.GET32(base + 44H))  * chipsetInfo[chipset].configSet  + {24(*..27, 13..15*), 12, 8..10, 7, 1..4})
			END;
			
			dummy:=SYSTEM.GET32(base + 44H); (* flush *)
			(* Set MAC address *)
			SYSTEM.PUT32(base, AosNet.Get4(dev.local, 0)); dummy:=SYSTEM.GET32(base);
			SYSTEM.PUT32(base + 4, AosNet.Get4(dev.local, 4));dummy:=SYSTEM.GET32(base + 4);
		
			(* enable Tx interrupt for testing *)
		(*	SYSTEM.PUT16(base + 3CH, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(SYSTEM.GET16(base + 3CH)))+{2, 0, 4}));*)
			SYSTEM.PUT16(base + 3CH, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(SYSTEM.GET16(base + 3CH)))+{0..6, 13..15}));
			
			(* Set Max DMA Burst Size*)
			SYSTEM.PUT32(base + 40H, SYSTEM.VAL(SET, SYSTEM.GET32(base + 40H))+{9, 10});
	
	END Reset;
		
		PROCEDURE &Init(dev: LinkDevice; base, irq, model: LONGINT);
		VAR res, dp, ver, i, dummy: LONGINT;
			val, nval: SET; data: ARRAY 100 OF CHAR;
		BEGIN
			SELF.next:=installedControllers; installedControllers:=SELF;
			NEW(timer);
			
			SELF.base := base; SELF.dev := dev; SELF.model := model; SELF.media := media; SELF.irq := irq;
			dev.ctrl := SELF;
			
			(* chipset:=Chipset8139; (*uncomment this line if the driver does not work. Maybe it will then still not work ;-) *) *)
			
			(* enable high power mode *)
			IF HasPwrDn IN chipsetInfo[chipset].flags THEN
				FlushWrite8(50H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 50H)))) + {7, 6})); (* config write enable *)
				SYSTEM.PUT8(base + 52H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 52H)))) - {0, 1})); (* config 1: 0 pwrdn, 1 sleep *)
				FlushWrite8(50H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 50H)))) - {7, 6})); (* config write disable *)
			ELSE
				val := SYSTEM.VAL(SET, SYSTEM.GET8(base + 52H)); nval := val;
				IF (HasLWake IN chipsetInfo[chipset].flags) & (1 IN val) THEN nval:=nval - {1} END;
				nval := nval + {0}; (* cfg1 pm enable *)
				IF nval # val THEN 
					FlushWrite8(50H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 50H)))) + {7, 6})); (* config write enable *)
					SYSTEM.PUT8(base + 52H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 52H)))) - {0, 1})); (* config 1: 0 pwrdn, 1 sleep *)
					FlushWrite8(50H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 50H)))) - {7, 6})) (* config write disable *)
				END;
				IF (HasLWake IN chipsetInfo[chipset].flags) THEN 
					SYSTEM.PUT8(base + 5AH, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 5AH)))) - {2})) (* config 4: 2 lwptn *)
				END
			END;
			
			(* soft reset *)
			SYSTEM.PUT8(base + 37H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 37H)))) + {4})); (* command register: 4 soft reset *)
			dp:=0;
			LOOP INC(dp); timer.Sleep(1); IF (SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 37H)))) * {4} = {})  OR (dp=100) THEN EXIT END END;
			
			(* assert PIO and MMIO enabled *)
			val := SYSTEM.VAL(SET, SYSTEM.GET8(base + 52H));
			IF val * {3} = {} THEN AosOut.String("MMIO is disabled."); HALT(1000) END;
			IF val * {2} = {} THEN AosOut.String("IO mapping is disabled."); HALT(1000) END;
			
			(* get version *)
				chipset:=-1;
			ver := SYSTEM.GET8(base + 43H);
			i := 0; WHILE i < NofChipsets DO IF chipsetInfo[i].version = ver THEN chipset := i; i:=NofChipsets ELSE INC(i) END END;
			IF chipset = -1 THEN chipset:=Chipset8139; AosOut.Enter; AosOut.String("chipset version unknown... assuming RTL-8139"); AosOut.Exit END;
			
			IF DebugInit THEN AosOut.String("Chip version is: "); AosOut.Hex(ver, 2); AosOut.String(" "); AosOut.String(chipsetInfo[chipset].name); AosOut.Ln END;
			
			(* Install Interrupt handler *)
			IF DebugInit THEN AosOut.String("Install IRQ Handler: "); AosOut.Int(irq, 5); AosOut.Ln END;
			IF (irq >= 1) & (irq <= 15) THEN AosActive.InstallHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0+irq) END;
			
			NEW(rxBuffer, RxBufSize);
			
			(* enable Tx / Rx *)
			FlushWrite8(37H, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 37H))))* {1, 5, 6, 7} + {2 , 3}));

			(* initialize the rxBuffer *)
			SYSTEM.PUT32(base + 30H, SYSTEM.ADR(rxBuffer[0]));
			rxBufPos:=0; SYSTEM.PUT16(base+38H, rxBufPos-16); dummy:=SYSTEM.GET16(base + 38H);
		
			(* initialize packet types *)
	(*		IF ReceiveAll THEN SYSTEM.PUT32(base + 44H, SYSTEM.VAL(SET, SYSTEM.GET32(base + 44H)) - {24..27, 13..15} + {24(*..27, 13..15*), 12, 8..10, 7, 0..4})
			ELSE SYSTEM.PUT32(base + 44H, SYSTEM.VAL(SET, SYSTEM.GET32(base + 44H)) - {24..27, 13..15} + {24(*..27, 13..15*), 12, 8..10, 7, 1..4})
			END; *)
			IF ReceiveAll THEN 
				SYSTEM.PUT32(base + 44H, 
					SYSTEM.VAL(SET, SYSTEM.GET32(base + 44H)) * chipsetInfo[chipset].configSet + {24(*..27, 13..15*), 12, 8..10, 7, 0..4})
			ELSE 
				SYSTEM.PUT32(base + 44H, 
					SYSTEM.VAL(SET, SYSTEM.GET32(base + 44H))  * chipsetInfo[chipset].configSet  + {24(*..27, 13..15*), 12, 8..10, 7, 1..4})
			END;
			
			dummy:=SYSTEM.GET32(base + 44H); (* flush *)
			
			
			FOR i:=0 TO 3 DO NEW(txBuffers[i], MaxETHFrameSize) END;
			FOR i := 0 TO 5 DO dev.broadcast[i] := 0FFX END;
			
			eepromAdrLen:=8; IF ReadEEPROM(0)#8129H THEN eepromAdrLen:=6 END;
			FOR i:=0 TO 2 DO devAdr[i]:=ReadEEPROM(7+i); 
				dev.local[i*2]:=CHR(devAdr[i] MOD 256);dev.local[i*2+1]:=CHR(devAdr[i] DIV 256 MOD 256)
			END;
			
			dev.adrSize := 6;
			
			(* Set MAC address *)
			SYSTEM.PUT32(base, AosNet.Get4(dev.local, 0)); dummy:=SYSTEM.GET32(base);
			SYSTEM.PUT32(base + 4, AosNet.Get4(dev.local, 4));dummy:=SYSTEM.GET32(base + 4);
		
			(* enable Tx interrupt for testing *)
		(*	SYSTEM.PUT16(base + 3CH, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(SYSTEM.GET16(base + 3CH)))+{2, 0, 4}));*)
			SYSTEM.PUT16(base + 3CH, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(SYSTEM.GET16(base + 3CH)))+{1..6, 13..15}));
			
			(* Set Max DMA Burst Size*)
			SYSTEM.PUT32(base + 40H, SYSTEM.VAL(SET, SYSTEM.GET32(base + 40H))+{9, 10});

			
			(* Register with AosNet *)
			IF RegisterInAosNet THEN 
				AosNet.registry.Add(dev, res);
				ASSERT(res = AosPlugins.Ok);
				INC(installed)
			END
		END Init;
		
		PROCEDURE ReadEEPROM(loc:LONGINT):LONGINT;
		VAR readCMD, data:SET; dummy, i:LONGINT;
		BEGIN
			readCMD := SYSTEM.VAL(SET, loc);
			IF eepromAdrLen = 6 THEN readCMD:=readCMD+{1+6, 2+6} ELSE readCMD:=readCMD+{1+8, 2+8} END;
			(* base+50H bit 3: EEPROM chip select; bit 2 EEPROM clock shift *)
			
			(* enable EEPROM access *)				
			SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR, {7})); SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR, {7, 3})); 
			dummy:=SYSTEM.GET32(base+50H); (* delay *)
			
			(* setup read adress *)
			i := 4 + eepromAdrLen; 
			WHILE i >= 0 DO 
				IF i IN readCMD THEN SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR, {7, 3, 1})) ELSE SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR,{7, 3})) END; 
				dummy:=SYSTEM.GET32(base+50H); (* delay *)
				IF i IN readCMD THEN SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR,{7, 3, 2, 1})) ELSE SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR,{7, 3, 2})) END;  (* clock shift *)
				dummy:=SYSTEM.GET32(base+50H); (* delay *)
				DEC(i) 
			END;
			
			(* enb, chip select  *)
			SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR, {7, 3})); 
			dummy:=SYSTEM.GET32(base+50H); (* delay *)
			
			(* read 16 bit *)
			data:={};
			FOR i:=15 TO 0 BY -1 DO 
				SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR,{7, 3, 2})); (* shift clock *)
				dummy:=SYSTEM.GET32(base+50H); (* delay *)
				
				IF SYSTEM.VAL(SET, LONG(LONG(SYSTEM.GET8(base + 50H)))) * {0} = {0} THEN INCL(data, i) END;
				
				SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR, {7, 3})); (* ~shift clock *)
				dummy:=SYSTEM.GET32(base+50H) (* delay *)
			END;
			
			(* disable EEPROM *)
			SYSTEM.PUT8(base+50H, SYSTEM.VAL(CHAR, -{3}));  
			dummy:=SYSTEM.GET32(base+50H); (* delay *)			
			
			RETURN SYSTEM.VAL(LONGINT, data)
		END ReadEEPROM;

		PROCEDURE ReadPacket;
		VAR rxInfo, pSize, pStart, dummy, i, type, hSize  :LONGINT; handler: AosNet.Receiver; t:LONGINT;
			buf : AosNet.Buffer;
		BEGIN
			i:=0;
			WHILE (i<MaxPacketsPerIRQ) &  ~(0 IN SYSTEM.VAL(SET, SYSTEM.GET8(base + 37H))) DO 
				rxInfo := AosNet.Get4(rxBuffer^, rxBufPos);
				pSize := (rxInfo DIV 65536) MOD 65536 - 4;
				pStart := rxBufPos + 4;
				IF DebugReceive THEN AosOut.Enter; AosOut.String("[RECEIVE] PSize is:"); AosOut.Int(pSize, 4); AosOut.Exit END;
				IF pSize # 0FFF0H THEN 
					IF pSize < MaxETHFrameSize THEN 
						IF DebugReceive THEN
							AosOut.Enter;
							AosOut.String("Read Packet ("); AosOut.Int(pSize, 4); AosOut.String(")"); AosOut.Ln;
							AosOut.Buffer(rxBuffer^, rxBufPos + 4, pSize);
							AosOut.Exit
						END;	
						IF logging THEN
							t := AosKernel.Elapsed(logtime);
							AosFS.WriteLInt(log, t DIV 1000);  
							AosFS.WriteLInt(log, (t MOD 1000)*1000+1);
							AosFS.WriteLInt(log, pSize);  AosFS.WriteLInt(log, pSize);
							log.file.WriteBytes(log, rxBuffer^, rxBufPos + 4, pSize);
						END;
						
						type := AosNet.GetNet2(rxBuffer^, pStart + 6 + 6);
						IF DebugReceive THEN AosOut.Enter; AosOut.String("packet type:"); AosOut.Hex(type, 2); AosOut.Exit END;
						
(*						IF CallAosNetReceiver THEN 
							dev.GetReceiver(type, handler, hSize);	(* base method call *)
							IF hSize > pSize THEN hSize := pSize END;
							rcvAdr := SYSTEM.ADR(rxBuffer[pStart + 14 + hSize]);
							rcvSize := pSize - hSize - 14;
							INC(dev.recvCount);
							handler(dev, SYSTEM.VAL(AosNet.RecvHdr, rxBuffer[pStart+14]), pSize-14, type, 
								SYSTEM.VAL(AosNet.LinkAdr, rxBuffer[pStart+6]));
						END;	*)
						buf := AosNet.GetNewBuffer();
						IF buf # NIL THEN
							buf.ofs := 0;
							buf.len := pSize - 14;
							buf.src := SYSTEM.VAL(AosNet.LinkAdr, rxBuffer[pStart + 6]);
							buf.calcChecksum := {};
							AosNet.Copy(rxBuffer^, buf.data, pStart + 14, 0, pSize - 14);
							dev.QueueBuffer(buf, type);
						ELSE
							(* no more upcall buffers available *)
						END
												
						(* write buffer pos was here *)
					END
				END; (* ELSE DMA is still in action for this packet (Info: BSD-driver) *)

						(* write buffer *)
				rxBufPos:=(rxBufPos+pSize+8+3); rxBufPos:=(rxBufPos - (rxBufPos MOD 4)) MOD RxBufLen; 
				SYSTEM.PUT16(base+38H, rxBufPos-16); dummy:=SYSTEM.GET16(base + 38H);
				INC(i)
			END;
			
			
		END ReadPacket;		
		
		PROCEDURE HandleInterrupt;
		VAR status, ack:SET; dummy:LONGINT;
		BEGIN
			ack:={0};
			status:=SYSTEM.VAL(SET, LONG(SYSTEM.GET16(base + 3EH)));
			 (* System Error: PCI bus error *)
			 IF 15 IN status THEN
				AosKernel.AtomicInc(nPCIError)
			END; 
			
			(* TimeOut: TCTR reaches value of TimerInt register *)
			IF 14 IN status THEN 
				AosKernel.AtomicInc(nTimeOut); INCL(ack, 14); 
			END;
			
			(* Cable length changed *)
			IF 13 IN status THEN 
				AosKernel.AtomicInc(nCableLengthChg); INCL(ack, 13)
			END;
			
			(* Rx FIFO overflow *)
			IF 6 IN status THEN 
				INCL(ack, 4); INCL(ack, 6); INCL(ack, 0);
				AosKernel.AtomicInc(nFifoOverflow);
			END;
			
			(* Packet underrun or link changed  *)
			IF 5 IN status THEN Reset;
				AosKernel.AtomicInc(nPUnOrLnkChg); INCL(ack, 5)
			END;
			
			(* Rx buffer overflow  *)
			IF 4 IN status THEN (* Reset; *)
				AosKernel.AtomicInc(nRxBufferOverflow);
				INCL(ack, 0); INCL(ack, 4);
			END;
			
			(* Transmit error: packet transmission aborted (too many collisions)  *)
			IF 3 IN status THEN 
				AosKernel.AtomicInc(nTxError); INCL(ack, 3)
			END;
			
			(* Transmit ok  *)
			IF 2 IN status THEN 
				AosKernel.AtomicInc(nTxOk); 
				INCL(ack, 2)
			END;
			
			(* Receive Error: CRC error or alignment error *)
			IF 1 IN status THEN 
				AosKernel.AtomicInc(nRxError); INCL(ack, 1)
			END;
			
			(* receive ok *)
			IF 0 IN status THEN 
				AosKernel.AtomicInc(nRxOk);
				ReadPacket;
				INCL(ack, 0);
			END;
			SYSTEM.PUT16(base + 3EH, SYSTEM.VAL(LONGINT, ack));
			dummy:=SYSTEM.GET16(base + 3EH);
		END HandleInterrupt;
		
		PROCEDURE Finalize;
		BEGIN
			(* disable all interrupts *)
			SYSTEM.PUT16(base + 3CH, 0);	
			timer.Sleep(1000); (* hope the interrupt will be over, then *)
			IF DebugCleanup THEN AosOut.String("Remove IRQ Handler.");  AosOut.Ln END;
			AosActive.RemoveHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0+irq);
			IF RegisterInAosNet THEN AosNet.registry.Remove(dev) END
		END Finalize;
	
		PROCEDURE Linked(): BOOLEAN;
		BEGIN
			RETURN ~(2 IN SYSTEM.VAL(SET, SYSTEM.GET8(base + 58H)));
		END Linked;
		
	END Controller;

 VAR
	installedControllers: Controller;

(* Scan the PCI bus for the specified card. *)

PROCEDURE ScanPCI(vendor, device, model: LONGINT);
VAR index, bus, dev, fct, res, base, irq, i: LONGINT; d: LinkDevice; c: Controller; name: AosPlugins.Name;
BEGIN
	index := 0;
	WHILE (PCI.FindPCIDevice(device, vendor, index, bus, dev, fct) = PCI.Done) & (installed < 10) DO
		res := PCI.ReadConfigDword(bus, dev, fct, PCI.Adr1Reg, base); ASSERT(res = PCI.Done);
		ASSERT(~ODD(base)); 	(* memory mapped *)
		DEC(base, base MOD 16);
		AosMemory.MapPhysical(base, 0FFH, base);
		
		res := PCI.ReadConfigByte(bus, dev, fct, PCI.IntlReg, irq); ASSERT(res = PCI.Done);
		NEW(d, AosNet.TypeEthernet, MaxETHFrameSize - 14, 6);
		name := Name;
		i := 0; WHILE name[i] # 0X DO INC(i) END;
		name[i] := CHR(ORD("0") + installed);
		name[i+1] := 0X;
		d.SetName(name);
		d.desc := Desc;
		
		IF DebugFind THEN AosOut.String("Found model nr :"); AosOut.Int(model, 4); AosOut.Ln END;
		
		NEW(c, d, base, irq, model);	(* increments "installed" when successful *)
		INC(index)
	END
END ScanPCI;

PROCEDURE Install*(par : PTR) :PTR;
BEGIN {EXCLUSIVE}
	IF installed = 0 THEN
		IF DebugFind THEN AosOut.String("Searching devices..."); AosOut.Ln END;
		ScanPCI(10ECH, 8139H, Model8139);
		ScanPCI(10ECH, 8138H, Model8139CB);
		ScanPCI(1113H, 1211H, ModelSMC1211TX);
		ScanPCI(1500H, 1360H, ModelDELTA8139);
		ScanPCI(4033H, 1360H, ModelADDTRON8139);
		ScanPCI(1186H, 1300H, ModelDFE528TX);
		ScanPCI(10ECH, 8129H, Model8129);
		IF DebugFind THEN AosOut.String("Find finished."); AosOut.Ln END;
	END;
	RETURN NIL
END Install;

PROCEDURE StartLog*;
VAR f: AosFS.File; res:LONGINT;
BEGIN
	AosKernel.SetTimer(logtime, 0);
	f := AosFS.New("EtherNet.Log");  f.Set(log, 0); AosFS.Register(f);	(* tcpdump compatible log file *)
	AosFS.WriteLInt(log, 0A1B2C3D4H);  AosFS.WriteInt(log, 2);
	AosFS.WriteInt(log, 4);  AosFS.WriteLInt(log, 0);  AosFS.WriteLInt(log, 0);
	AosFS.WriteLInt(log, 1514);  AosFS.WriteLInt(log, 1);
	logging := TRUE;
	AosOut.Enter; AosOut.String("EtherNet log started --> dumping to EtherNet.Log."); AosOut.Exit
END StartLog;

PROCEDURE StopLog*;
BEGIN
	logging:=FALSE;
	AosOut.Enter; AosOut.String("EtherNet log stopped."); AosOut.Exit
END StopLog;

PROCEDURE Cleanup;
BEGIN
	WHILE installedControllers # NIL DO installedControllers.Finalize; installedControllers:=installedControllers.next END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup); 
	
	chipsetInfo[Chipset8139].name := "RTL-8139"; chipsetInfo[Chipset8139].version := 40H; 
	chipsetInfo[Chipset8139].flags := {HasPwrDn}; chipsetInfo[Chipset8139].configSet:={28..31, 17..23, 6};
	
	chipsetInfo[Chipset8139B].name := "RTL-8139B"; chipsetInfo[Chipset8139B].version := 78H; 
	chipsetInfo[Chipset8139B].flags := {HasLWake}; chipsetInfo[Chipset8139B].configSet:={28..31, 17..22, 6};
	
	chipsetInfo[Chipset8139A].name := "RTL-8139A"; chipsetInfo[Chipset8139A].version := 70H; 
	chipsetInfo[Chipset8139A].flags := {}; chipsetInfo[Chipset8139A].configSet:={28..31, 17..26, 6};

	chipsetInfo[Chipset8139C].name := "RTL-8139C"; chipsetInfo[Chipset8139C].version := 74H; 
	chipsetInfo[Chipset8139C].flags := {HasLWake}; chipsetInfo[Chipset8139C].configSet:={28..31, 17..22, 6};

END AosRTL8139.
 

System.Free AosRTL8139 ~
AosRTL8139.Install
System.OpenKernelLog 
AosTestNet.Mod
AosTestNet.SetDevice "RTL8139#0"
