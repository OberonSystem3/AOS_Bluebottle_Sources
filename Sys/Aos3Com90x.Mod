(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE Aos3Com90x; (** AUTHOR "rstrobl/jaco/prk/pjm/mvt"; PURPOSE "3Com 3C90X ethernet driver"; *)

(*
Aos driver for 3Com EtherLink XL ethernet adapter.
Auto-select not yet supported: configure the card using the 3Com-supplied utility.

Based on Native Oberon driver by Reto Strobl, Jaco Geldenhuys, Patrik Reali, Pieter Muller.
Reference: 3Com, "3C90x Network Interface Cards Technical Reference: 3Com EtherLink XL NICs".

Config strings:
	3C90xMedia =
		1 -> 10Base-T
		2 -> 10 Mbps AU
		4 -> 10Base2
		5 -> 100Base-TX
		6 -> 100Base-FX
		7 -> MII
		9 -> Auto (3C90xB only)
	3C90xDuplex =
		0 -> read duplex setting from EPROM
		1 -> half-duplex
		2 -> full-duplex
*)

IMPORT SYSTEM, AosBoot, AosOut, AosMemory, AosInterrupts, AosModules, AosActive, 
	PCI, AosPlugins, AosNet, AosKernel;

CONST
	Name = "3Com90x#";
	Desc = "3Com Etherlink XL ethernet driver";
	
	MaxPkt = 1514;
	MTU = MaxPkt-14;
	
	EarlyThresh = MAX(LONGINT);

	ReceiveBuffers = 128;
	
	SendTimeout = 5*1000;	(* ms *)
	
	NewTries = 32;
	
		(* Media Types *)
	MediaMask = {20..23};
	Base10T = {}; (*AUI = {20};*) Base10Coax = {21, 20}; (*Base100TX = {22};*)
	(*Base100FX = {22, 20};*) MII = {22, 21}; Auto = {23};

		(* Controller flags *)
	Eprom230 = 0; InvertMIIPower = 1;

		(* models *)
	Model90x = 0; Model90xB = 1; Model90xC = 2;

TYPE
	MemRangeArray = ARRAY 2 OF AosMemory.Range;

	DPD = POINTER TO RECORD	(* p. 6-1 *)
			(* start fixed-layout *)
		nextPhysAdr: LONGINT;	(* 00H *)
		status: SET;	(* 04 *)
		frag: ARRAY 5 OF RECORD
			dataPhysAdr: LONGINT;	(* 08H, 10H, 18H, 20H, 28H *)
			dataLen: LONGINT	(* 0CH, 14H, 1CH, 24H, 2CH *)
		END;
		dst, src: ARRAY 6 OF CHAR;
		type: INTEGER;
			(* end fixed-layout *)
		physAdr: LONGINT;	(* assume physical address of dpd^ will not change *)
	END;

	UPD = POINTER TO RECORD	(* p. 7-1 *)
			(* start fixed-layout *)
		nextPhysAdr: LONGINT;	(* 00H *)
		status: SET;	(* 04 *)
		frag: ARRAY 3 OF RECORD
			dataPhysAdr: LONGINT;	(* 08H, 10H, 18H *)
			dataLen: LONGINT	(* 0CH, 14H, 1CH *)
		END;
		dst, src: ARRAY 6 OF CHAR;
		type: INTEGER;
			(* end fixed-layout *)
		physAdr: LONGINT;	(* assume physical address of upd^ will not change *)
		buffer: AosNet.Buffer;
		next: UPD;
	END;
	
VAR
	installed: LONGINT;	(* number of installed devices *)
	NdnTxReclaimError, NdnTxStatusOverflow, NdnMaxCollisions, NdnTxUnderrun, NdnTxJabber, NnewRetry,
		NspuriousComplete, NupOverrun, NupRuntFrame, NupAlignmentError, NupCrcError, NupOversizedFrame,
		NupOverflow, NbadSize, Ninterrupt, NintHostError, NintTxComplete, NintRxEarly, NintRequested, 
		NintUpdateStats, NintLinkEvent, NintDnComplete, NintUpComplete, NstatCarrierLost, 
		NstatSqeErrors, NstatMultipleCollisions, NstatSingleCollisions, NstatLateCollisions, NstatRxOverruns,
		NstatFramesXmittedOk, NstatFramesRcvdOk, NstatFramesDeferred, NstatBytesRcvdOk, 
		NstatBytesXmittedOk, NstatBadSSD, NupCompleteLoops, NsendTimeouts: LONGINT;

TYPE
	Timer = OBJECT (AosKernel.Timer)
		VAR
			ms: LONGINT;
			c: Controller;
			quit: BOOLEAN;
		
		PROCEDURE &Init2(c: Controller);
		BEGIN
			SELF.c := c; SELF.quit := FALSE; SELF.ms := 1;
			Init
		END Init2;
		
	BEGIN {ACTIVE}
		WHILE ~quit DO
			c.HandleInterrupt();
			Sleep(ms);
		END
	END Timer;

	Controller* = OBJECT
		VAR
			base, irq*: LONGINT;
			dev: LinkDevice;
			flags: SET;
			model: LONGINT;
			media: SET;
			dpd: DPD;
			upd: UPD;
			
			bus, pdev, fct: LONGINT;
			interrupted: BOOLEAN;
			timer: Timer;
		
		PROCEDURE HandleInterrupt();
		VAR type, len: LONGINT; status: SET; int: INTEGER; ch: CHAR; buf: AosNet.Buffer;
		BEGIN
			interrupted := TRUE;
			AosKernel.AtomicInc(Ninterrupt);
			SYSTEM.PORTIN(base+0EH, SYSTEM.VAL(INTEGER, status));	(* IntStatus (p. 8-3) *)
			IF 1 IN status THEN	(* hostError *)
				AosKernel.AtomicInc(NintHostError)
				(* to do: reset *)
			END;
			IF 2 IN status THEN	(* txComplete *)
				AosKernel.AtomicInc(NintTxComplete);
				SYSTEM.PORTOUT(base+1BH, 0X)	(* TxStatus (p. 6-23) *)
			END;
			IF 5 IN status THEN	(* rxEarly *)
				AosKernel.AtomicInc(NintRxEarly)
			END;
			IF 6 IN status THEN	(* intRequested (or Countdown expiry) *)
				AosKernel.AtomicInc(NintRequested)
			END;
			IF 7 IN status THEN	(* updateStats *)
				AosKernel.AtomicInc(NintUpdateStats);
				SetWindow(base, 6);
				SYSTEM.PORTIN(base+0, ch); AosKernel.AtomicAdd(NstatCarrierLost, ORD(ch));
				SYSTEM.PORTIN(base+1, ch); AosKernel.AtomicAdd(NstatSqeErrors, ORD(ch));
				SYSTEM.PORTIN(base+2, ch); AosKernel.AtomicAdd(NstatMultipleCollisions, ORD(ch));
				SYSTEM.PORTIN(base+3, ch); AosKernel.AtomicAdd(NstatSingleCollisions, ORD(ch));
				SYSTEM.PORTIN(base+4, ch); AosKernel.AtomicAdd(NstatLateCollisions, ORD(ch));
				SYSTEM.PORTIN(base+5, ch); AosKernel.AtomicAdd(NstatRxOverruns, ORD(ch));
				SYSTEM.PORTIN(base+6, ch); AosKernel.AtomicAdd(NstatFramesXmittedOk, ORD(ch));
				SYSTEM.PORTIN(base+7, ch); AosKernel.AtomicAdd(NstatFramesRcvdOk, ORD(ch));
				SYSTEM.PORTIN(base+9, ch);	(* UpperFramesOk *)
				AosKernel.AtomicAdd(NstatFramesXmittedOk, ORD(ch) DIV 16 MOD 16 * 100H);
				AosKernel.AtomicAdd(NstatFramesRcvdOk, ORD(ch) MOD 16 * 100H);
				SYSTEM.PORTIN(base+8, ch); AosKernel.AtomicAdd(NstatFramesDeferred, ORD(ch));
				SYSTEM.PORTIN(base+0AH, int); AosKernel.AtomicAdd(NstatBytesRcvdOk, LONG(int) MOD 10000H);
				SYSTEM.PORTIN(base+0CH, int); AosKernel.AtomicAdd(NstatBytesXmittedOk, LONG(int) MOD 10000H);
				SetWindow(base, 4);
				SYSTEM.PORTIN(base+0CH, ch); AosKernel.AtomicAdd(NstatBadSSD, ORD(ch));
				SYSTEM.PORTIN(base+0DH, ch);	(* UpperBytesOk *)
				AosKernel.AtomicAdd(NstatBytesXmittedOk, ORD(ch) DIV 16 MOD 16 * 10000H);
				AosKernel.AtomicAdd(NstatBytesRcvdOk, ORD(ch) MOD 16 * 10000H)
					(* now back in window 4 *)
			END;
			IF 8 IN status THEN	(* linkEvent *)
				AosKernel.AtomicInc(NintLinkEvent)
				(* to do: read AutoNegExpansion via MII *)
			END;
			IF 9 IN status THEN
				AosKernel.AtomicInc(NintDnComplete)
			END;
			IF 10 IN status THEN	(* upComplete *)
				AosKernel.AtomicInc(NintUpComplete);
				IF 15 IN upd.status THEN	(* upComplete (p. 7-3) *)
					REPEAT
						AosKernel.AtomicInc(NupCompleteLoops);
						IF upd.status * {14,16..20,24} = {} THEN	(* no error *)
							len := SYSTEM.VAL(LONGINT, upd.status * {0..12}) - 14;
							IF (len >= 60-14) & (len <= MTU) THEN
								buf := upd.buffer;
								IF buf # NIL THEN
									(* get buffer from UPD for upcall *)
									buf := upd.buffer;
									type := LONG(SYSTEM.ROT(upd.type, 8)) MOD 10000H;
									buf.ofs := 0;
									buf.len := len;
									buf.calcChecksum := {};
									buf.src := SYSTEM.VAL(AosNet.LinkAdr, upd.src);
									dev.QueueBuffer(buf, type);
								ELSE
									AosKernel.AtomicInc(NupOverflow); (* no more upcall buffers available *)
								END;
								(* get new empty buffer for UPD *)
								BufferToUPD(AosNet.GetNewBuffer(), upd);
							ELSE
								AosKernel.AtomicInc(NbadSize)
							END
						ELSE
							ASSERT((14 IN upd.status) & (upd.status * {16..20,24} # {}));
							IF 16 IN upd.status THEN AosKernel.AtomicInc(NupOverrun) END;
							IF 17 IN upd.status THEN AosKernel.AtomicInc(NupRuntFrame) END;
							IF 18 IN upd.status THEN AosKernel.AtomicInc(NupAlignmentError) END;
							IF 19 IN upd.status THEN AosKernel.AtomicInc(NupCrcError) END;
							IF 20 IN upd.status THEN AosKernel.AtomicInc(NupOversizedFrame) END;
							IF 24 IN upd.status THEN AosKernel.AtomicInc(NupOverflow) END
						END;
						upd.status := {}; upd := upd.next;
						SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 3001H))	(* UpUnstall (p. 10-8) *)
					UNTIL ~(15 IN upd.status)
				ELSE
					AosKernel.AtomicInc(NspuriousComplete)
				END
			END;
			IF status * {0, 5, 6, 9, 10} # {} THEN
				SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, SHORT(6800H + 
						SYSTEM.VAL(LONGINT, status * {0, 5, 6, 9, 10}))))	(* AcknowledgeInterrupt 10 (p. 10-9) *)
			END
		END HandleInterrupt;

		(* Initialize the controller. *)
		
		PROCEDURE &Init(dev: LinkDevice; base, irq, model: LONGINT; flags, media: SET);
		VAR res, i: LONGINT;
		BEGIN
			SELF.interrupted := FALSE;
			SELF.base := base; SELF.irq := irq;  SELF.dev := dev; SELF.model := model; SELF.media := media;
			SELF.flags := flags;
			dev.ctrl := SELF;
			InitDPD(dpd);
			InitUPD(upd);
			InitAddress(dev);	(* sets dev.local and dev.broadcast *)
			SYSTEM.MOVE(SYSTEM.ADR(dev.local[0]), SYSTEM.ADR(dpd.src[0]), 6);
			InitInterface(SELF);
			InitRegisters(SELF);
			IF (irq >= 1) & (irq <= 15) THEN
				AosOut.Enter; AosOut.String("Install Handler IRQ = "); AosOut.Hex(irq, -3); AosOut.Exit;
				AosActive.InstallHandler(SELF.HandleInterrupt, AosInterrupts.IRQ0+irq)
			END;
			AosNet.registry.Add(dev, res);
			ASSERT(res = AosPlugins.Ok);
			INC(installed);
			SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 6000H));	(* RequestInterrupt (p. 10-9) *)
			i := 0;
			WHILE (i < 100) & ~interrupted DO
				AosActive.Yield;
				INC(i)
			END;
			IF ~interrupted THEN	(* interrupt handler not called, install timer *)
				AosOut.Enter; AosOut.String("Install Timer"); AosOut.Exit;
				NEW(timer, SELF)
			ELSE
				AosOut.Enter; AosOut.String("No need for Timer"); AosOut.Exit
			END
		END Init;
		
		PROCEDURE Finalize;
		VAR item: UPD;
		BEGIN {EXCLUSIVE}
			IF timer # NIL THEN
				AosOut.Enter; AosOut.String("Remove Timer"); AosOut.Exit;
				timer.quit := TRUE
			END;
			ResetTx(base);
			ResetRx(SELF, FALSE);
			AosActive.RemoveHandler(HandleInterrupt, AosInterrupts.IRQ0+irq);
			AosNet.registry.Remove(dev);
			dev.ctrl := NIL; dev := NIL;
			(* return buffers attached to UPD *)
			item := upd;
			REPEAT
				AosNet.ReturnBuffer(item.buffer);
				item.buffer := NIL; (* in case of concurrent interrupt *)
				item := item.next;
			UNTIL item = upd;
		END Finalize;
		
	END Controller;

TYPE
	LinkDevice* = OBJECT (AosNet.LinkDevice)
		VAR
			hdr: ARRAY AosNet.MaxPacketSize OF CHAR; (* internal buffer for eventual header copy in DoSend *)
			ctrl*: Controller;
		
		PROCEDURE DoSend(dst: AosNet.LinkAdr; type: LONGINT; VAR l3hdr, l4hdr, data: ARRAY OF CHAR; h3len, h4len, dofs, dlen: LONGINT);
		VAR
			dpd: DPD;
			t: AosKernel.MilliTimer;
			h3n, h4n, dn, hn, hlen, len, base, i: LONGINT;
			h3phys, h4phys, dphys, hphys: MemRangeArray;
			
			PROCEDURE PutToDPD(n: LONGINT; VAR phys: MemRangeArray);
			VAR j: LONGINT;
			BEGIN
				FOR j := 0 TO n-1 DO
					dpd.frag[i].dataPhysAdr := phys[j].adr;
					dpd.frag[i].dataLen := phys[j].size;
					INC(i);
				END;
			END PutToDPD;

		BEGIN {EXCLUSIVE}
			base := ctrl.base; dpd := ctrl.dpd;
			
			(* set up ethernet header *)
			SYSTEM.MOVE(SYSTEM.ADR(dst[0]), SYSTEM.ADR(dpd.dst[0]), 6);
			dpd.type := SYSTEM.ROT(SHORT(type), 8);
			
			(* set up the download *)
			IssueCommand(base, 3002H);	(* DnStall (p. 10-4) *)
			CheckTransmission(base);
			
			(* set up the DPD *)
			AosMemory.TranslateVirtual(SYSTEM.ADR(l3hdr[0]), h3len, h3n, h3phys);
			AosMemory.TranslateVirtual(SYSTEM.ADR(l4hdr[0]), h4len, h4n, h4phys);
			AosMemory.TranslateVirtual(SYSTEM.ADR(data[dofs]), dlen, dn, dphys);
			
			(* max. 2 fragments allowed (all packets smaller than one 4K page) *)
			ASSERT(h3n <= 2);
			ASSERT(h4n <= 2);
			ASSERT(dn <= 2);
			i := 1; (* start at fragment index 1 in DPD *)
			
			IF h3n + h4n + dn > 4 THEN
				(* max. number of fragments exceeded - occurs very rarely! only handled to avoid eventual packet loss *)
				(* copy l3hdr and l4hdr to hdr to reduce fragments *)
				AosNet.Copy(l3hdr, hdr, 0, 0, h3len);
				AosNet.Copy(l4hdr, hdr, 0, h3len, h4len);
				hlen := h3len + h4len;
				AosMemory.TranslateVirtual(SYSTEM.ADR(hdr[0]), hlen, hn, hphys); 
				PutToDPD(hn, hphys);
			ELSE
				(* this is the normal case *)
				PutToDPD(h3n, h3phys);
				PutToDPD(h4n, h4phys);
			END;
			(* put data *)
			PutToDPD(dn, dphys);
			(* set "end" marker *)
			INC(dpd.frag[i-1].dataLen, 80000000H);

			len := h3len + h4len + len +14;	(* now len is total packet length including headers *)
			ASSERT((len >= 14) & (len <= MaxPkt));	(* packet size *)
			dpd.status := SYSTEM.VAL(SET, len);
			SYSTEM.PORTOUT(base+24H, dpd.physAdr);	(* DnListPtr (p. 6-17) *)
			SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 3003H));	(* DnUnstall (p. 10-5) *)
			
			(* wait for download to finish, so that buffer is free afterwards *)
			AosKernel.SetTimer(t, SendTimeout);
			REPEAT
				SYSTEM.PORTIN(base+24H, i)	(* downloading finished *)
			UNTIL (i = 0) OR AosKernel.Expired(t);
			IF i # 0 THEN AosKernel.AtomicInc(NsendTimeouts) END;
			INC(sendCount)
		END DoSend;

		PROCEDURE Finalize(connected: BOOLEAN);
		BEGIN
			ctrl.Finalize;
			Finalize^(connected);
		END Finalize;
		
	END LinkDevice;

(* Change to the specified register window. *)

PROCEDURE SetWindow(base, window: LONGINT);
BEGIN
	ASSERT((0 <= window) & (window <= 7));
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, SHORT(800H + window)))
END SetWindow;

(* Read a 16-bit value from the EEPROM (chapter 5). *)

PROCEDURE ReadConfig(base, reg: LONGINT; flags: SET; VAR word: INTEGER);
VAR x: INTEGER;
BEGIN
	ASSERT((0 <= reg) & (reg < 64));
	SetWindow(base, 0);
	IF Eprom230 IN flags THEN INC(reg, 230H) ELSE INC(reg, 80H) END;
	SYSTEM.PORTOUT(base+0AH, SYSTEM.VAL(INTEGER, SHORT((*80H + *)reg)));	(* Read Register - 162 us *)
	REPEAT
		SYSTEM.PORTIN(base+0AH, x)
	UNTIL ~(15 IN SYSTEM.VAL(SET, LONG(x)));	(*  Wait till ~eepromBusy *)
	SYSTEM.PORTIN(base+0CH, word)
END ReadConfig;

(* Initialize the local address. *)

PROCEDURE InitAddress(d: LinkDevice);
VAR base, i: LONGINT; flags: SET; word: ARRAY 3 OF INTEGER;
BEGIN
	base := d.ctrl.base;
	flags := d.ctrl.flags;
	ReadConfig(base, 0AH, flags, word[0]);	(* OEM Node Address / word 0 *)
	ReadConfig(base, 0BH, flags, word[1]);	(* OEM Node Address / word 1 *)
	ReadConfig(base, 0CH, flags, word[2]);	(* OEM Node Address / word 2 *)
	SetWindow(base, 2);
	FOR i := 0 TO 2 DO
		word[i] := SYSTEM.ROT(word[i], 8);
		d.local[2*i] := CHR(word[i] MOD 100H);
		d.local[2*i+1] := CHR(word[i] DIV 100H MOD 100H);
		SYSTEM.PORTOUT(base+2*i, word[i]);	(* StationAddress *)
		SYSTEM.PORTOUT(base+6+2*i, SYSTEM.VAL(INTEGER, 0))	(* StationMask *)
	END;
	FOR i := 0 TO 5 DO d.broadcast[i] := 0FFX END
END InitAddress;

(* Get the specified setting for the NIC currently being initialized (indexed by "installed"). *)

PROCEDURE GetSetting(s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT; name, val: ARRAY 32 OF CHAR;
BEGIN
	i := 0; WHILE s[i] # 0X DO name[i] := s[i]; INC(i) END;
	name[i] := CHR(ORD("0") + installed); name[i+1] := 0X;
	AosBoot.GetConfig(name, val);
	IF val[0] = 0X THEN	(* specified setting not found, look for generic one *)
		name[i] := 0X; AosBoot.GetConfig(name, val)
	END;
	i := 0;
	RETURN AosBoot.StrToInt(i, val)
END GetSetting;

(* Initialize the communication interface. *)

PROCEDURE InitInterface(ctrl: Controller);
VAR config: SET; base, media: LONGINT;
BEGIN
	base := ctrl.base;
	SetWindow(base, 3);
	SYSTEM.PORTIN(base, config);	(* InternalConfig (p. 4-9) *)
	media := GetSetting("3C90xMedia");
	IF media # 0 THEN
		ASSERT((media >= 1) & (media <= 9));
		ctrl.media := SYSTEM.VAL(SET, SYSTEM.LSH(media-1, 20)) * MediaMask;
		SYSTEM.PORTOUT(base, config - MediaMask + ctrl.media)
	ELSIF ~(24 IN config) THEN
		ctrl.media := config * MediaMask	(* autoselect off, no changes needed *)
	ELSE
		media := SYSTEM.VAL(LONGINT, ctrl.media);
		SYSTEM.PORTOUT(base, config - MediaMask + ctrl.media);
		AosOut.Enter; AosOut.String(ctrl.dev.name); AosOut.String(" auto-selection not supported"); AosOut.Exit;
		(*HALT(3801)*)	(* auto-selection not yet supported *)
	END
	;AosOut.Enter; AosOut.String("Media = "); AosOut.Hex(media, 0); AosOut.Exit;
END InitInterface;

(* Issue a command and wait for completion. *)

PROCEDURE IssueCommand(base, cmd: LONGINT);
VAR word: INTEGER;
BEGIN
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, SHORT(cmd)));
	REPEAT
		SYSTEM.PORTIN(base+0EH, word)
	UNTIL ~(12 IN SYSTEM.VAL(SET, LONG(word)))
END IssueCommand;

PROCEDURE ResetTx(base: LONGINT);
BEGIN
	IssueCommand(base, 5800H);	(* TxReset (p. 10-4) *)
	SYSTEM.PORTOUT(base+24H, SYSTEM.VAL(LONGINT, 0))	(* DnListPtr (p. 6-17) *)
END ResetTx;

PROCEDURE ResetRx(ctrl: Controller; setThresh: BOOLEAN);
VAR base: LONGINT;
BEGIN
	base := ctrl.base;
	IssueCommand(base, 2800H);	(* RxReset (p. 10-3) *)
	IF setThresh THEN
		IF EarlyThresh DIV 4 > 7FFH THEN
			SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 8FFFH));	(* SetRxEarlyThresh (p. 10-7) *)
			SYSTEM.PORTOUT(base+20H, SYSTEM.VAL(LONGINT, 0H))	(* DmaCtrl (p. 6-14) *)
		ELSE
			SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 8800H + EarlyThresh DIV 4));
			SYSTEM.PORTOUT(base+20H, SYSTEM.VAL(LONGINT, 20H))	(* DmaCtrl (p. 6-14) - upRxEarlyEnable *)
		END
	END;
	SYSTEM.PORTOUT(base+38H, ctrl.upd.physAdr);	(* UpListPtr (p. 7-14) *)
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 8007H))	(* SetRxFilter (p. 10-8) - Individual, Multicast, Broadcast *)
END ResetRx;

(* Check the transmitter and reset it if required. *)

PROCEDURE CheckTransmission(base: LONGINT);
VAR status: SET; enable, reset: BOOLEAN; ch: CHAR;
BEGIN
	enable := FALSE; reset := FALSE;
	LOOP
		SYSTEM.PORTIN(base+1BH, ch);	(* TxStatus (p. 6-23) *)
		status := SYSTEM.VAL(SET, LONG(ORD(ch)));
		IF ~(7 IN status) THEN EXIT END;	(* txComplete *)
		IF 1 IN status THEN AosKernel.AtomicInc(NdnTxReclaimError) END;
		IF 2 IN status THEN AosKernel.AtomicInc(NdnTxStatusOverflow); enable := TRUE END;
		IF 3 IN status THEN AosKernel.AtomicInc(NdnMaxCollisions); enable := TRUE END;
		IF 4 IN status THEN AosKernel.AtomicInc(NdnTxUnderrun); reset := TRUE END;
		IF 5 IN status THEN AosKernel.AtomicInc(NdnTxJabber); reset := TRUE END;
		SYSTEM.PORTOUT(base+1BH, ch)	(* advance *)
	END;
	IF reset THEN IssueCommand(base, 5800H); enable := TRUE END;	(* TxReset (p. 10-4) *)
	IF enable THEN SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 4800H)) END	(* TxEnable (p. 10-6) *)
END CheckTransmission;

(* Allocate a DPD.  Assume the physical address of the record will not change (beware copying GC). *)

PROCEDURE InitDPD(VAR dpd: DPD);
VAR i, n: LONGINT; phys: MemRangeArray;
BEGIN
	i := 0;
	LOOP
		NEW(dpd);
		AosMemory.TranslateVirtual(SYSTEM.ADR(dpd.nextPhysAdr), SIZE(DPD), n, phys);
		IF n = 1 THEN EXIT END;	(* contiguous *)
		INC(i); AosKernel.AtomicInc(NnewRetry);
		IF i = NewTries THEN HALT(3802) END	(* can not allocate contiguous DPD *)
	END;
	ASSERT(phys[0].size = SIZE(DPD));
	dpd.physAdr := phys[0].adr;
	ASSERT(dpd.physAdr MOD 8 = 0);	(* alignment constraint (p. 6-3) *)
	dpd.nextPhysAdr := 0;
		(* entry 0 always points to ethernet header *)
	dpd.frag[0].dataPhysAdr := (SYSTEM.ADR(dpd.dst[0])-SYSTEM.ADR(dpd.nextPhysAdr)) + dpd.physAdr;
	dpd.frag[0].dataLen := 14	(* ethernet header *)
END InitDPD;

(* Allocate the UPD ring. *)

PROCEDURE InitUPD(VAR upd: UPD);
VAR i, j, n: LONGINT; head, tail: UPD; phys: MemRangeArray;
BEGIN
	head := NIL; tail := NIL;
	FOR j := 1 TO ReceiveBuffers DO
		i := 0;
		LOOP
			NEW(upd);
			AosMemory.TranslateVirtual(SYSTEM.ADR(upd.nextPhysAdr), SIZE(UPD), n, phys);
			IF n = 1 THEN EXIT END;	(* contiguous *)
			INC(i); AosKernel.AtomicInc(NnewRetry);
			IF i = NewTries THEN HALT(3803) END	(* can not allocate contiguous UPD *)
		END;
		ASSERT(phys[0].size = SIZE(UPD));
		upd.physAdr := phys[0].adr;
		ASSERT(upd.physAdr MOD 8 = 0);	(* alignment constraint (p. 7-2) *)
		upd.status := {};
			(* entry 0 always points to ethernet header *)
		upd.frag[0].dataPhysAdr := (SYSTEM.ADR(upd.dst[0])-SYSTEM.ADR(upd.nextPhysAdr)) + upd.physAdr;
		upd.frag[0].dataLen := 14;	(* ethernet header *)
		
		(* get new empty buffer and attach it to the UPD *)
		BufferToUPD(AosNet.GetNewBuffer(), upd);
		
			(* link in *)
		IF head # NIL THEN
			upd.next := head; upd.nextPhysAdr := head.physAdr
		ELSE
			upd.next := NIL; upd.nextPhysAdr := 0; tail := upd
		END;
		head := upd
	END;
	tail.next := head; tail.nextPhysAdr := head.physAdr
END InitUPD;

(* Set buffer as DMA receive buffer in UPD. *)

PROCEDURE BufferToUPD(buffer: AosNet.Buffer; upd: UPD);
VAR
	n, i: LONGINT;
	phys: MemRangeArray;
BEGIN
	ASSERT(upd # NIL);
	IF buffer # NIL THEN
		(* entry 1-2 points to data *)
		AosMemory.TranslateVirtual(SYSTEM.ADR(buffer.data[0]), LEN(buffer.data), n, phys);
		ASSERT(n <= 2);
		FOR i := 1 TO n DO
			upd.frag[i].dataPhysAdr := phys[i-1].adr; upd.frag[i].dataLen := phys[i-1].size
		END;
		INC(upd.frag[n].dataLen, 80000000H); (* end of buffer marker *)
	ELSE
		(* no buffer available at the moment. only header can be received. *)
		upd.frag[0].dataLen := 14; (* ethernet header *)
		INC(upd.frag[0].dataLen, 80000000H); (* end of buffer marker *)
	END;
	upd.buffer := buffer; (* attach buffer reference *)
END BufferToUPD;

(* Initialize the registers. *)

PROCEDURE InitRegisters(ctrl: Controller);
VAR base, duplex, i, dw: LONGINT; word: INTEGER; full: BOOLEAN; ch: CHAR; flags: SET;
BEGIN
	base := ctrl.base;
	flags := ctrl.flags;
	IF InvertMIIPower IN flags THEN
		SetWindow(base, 2);
		SYSTEM.PORTIN(base+0CH, word);
		word := SHORT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LONG(word)) + {14}));
		SYSTEM.PORTOUT(base+0CH, word);
		AosOut.Enter; AosOut.String("Invert MII Power "); AosOut.Hex(word, 0); AosOut.Exit;
	END;
	IF ctrl.media = Base10Coax THEN
		SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 1000H))	(* EnableDcConverter (p. 10-10) *)
	ELSE
		SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 0B800H))	(* DisableDcConverter (p. 10-10) *)
	END;
	duplex := GetSetting("3C90xDuplex");
	IF duplex = 0 THEN
		ReadConfig(base, 0DH, flags, word);	(* Software Information (p. 5-5) *)
		full := (15 IN SYSTEM.VAL(SET, LONG(word)))
	ELSE
		full := (duplex = 2)
	END;
	SetWindow(base, 3);
	IF full THEN
		AosOut.Enter; AosOut.String(ctrl.dev.name); AosOut.String(" full-duplex"); AosOut.Exit;
		SYSTEM.PORTOUT(base+6, SYSTEM.VAL(INTEGER, 20H))	(* MacControl (p. 12-2) *)
	ELSE	(* half-duplex *)
		AosOut.Enter; AosOut.String(ctrl.dev.name); AosOut.String(" half-duplex"); AosOut.Exit;
		SYSTEM.PORTOUT(base+6, SYSTEM.VAL(INTEGER, 0))
	END;
	ResetTx(base);
	ResetRx(ctrl, TRUE);
	SetWindow(base, 7);	(* operating window *)
	IF ctrl.model = Model90x THEN
		SYSTEM.PORTOUT(base+2FH, CHR((MaxPkt+255) DIV 256))	(* TxFreeThresh (p. 6-20) *)
	END;
		(* clear all interrupts & indications *)
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 7FF6H));	(* SetIndicationEnable (p. 10-9) - all *)
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, SYSTEM.VAL(LONGINT, {1, 6, 7, 10}) + 7000H));	(* SetInterruptEnable (p. 10-10, 8-4) *)
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 6F69H));	(* AcknowledgeInterrupt (p. 10-9) - all *)
		(* clear all statistics *)
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 0B000H));	(* StatisticsDisable (p. 10-11) *)
	SetWindow(base, 5);
	SYSTEM.PORTIN(base+0AH, word);
	AosOut.Enter; AosOut.String("IntEnable = "); AosOut.Hex(word, 4); AosOut.Exit;
	SetWindow(base, 6);
	FOR i := 0 TO 9 DO SYSTEM.PORTIN(base+i, ch) END;
	SYSTEM.PORTIN(base+0AH, word);
	SYSTEM.PORTIN(base+0CH, word);
	SetWindow(base, 4);
(*
	SYSTEM.PORTIN(base+0AH, word);
	SYSTEM.PORTOUT(base+0AH, SYSTEM.VAL(INTEGER, SHORT(SYSTEM.VAL(LONGINT,
			SYSTEM.VAL(SET, LONG(word)) - {7}))));	(* MediaStatus: disable linkBeatEnable *)
*)
	SYSTEM.PORTIN(base+0CH, ch);
	SYSTEM.PORTIN(base+0DH, ch);
	SYSTEM.PORTIN(base+6, word);	(* NetworkDiagnostic (p. 9-8) *)
	SYSTEM.PORTOUT(base+6, SYSTEM.VAL(INTEGER, SHORT(SYSTEM.VAL(LONGINT, 
			SYSTEM.VAL(SET, LONG(word)) + {6}))));	(* upperBytesEnable *)
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 0A800H));	(* StatisticsEnable (p. 10-11) *)
		(* start the NIC *)
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 2000H));	(* RxEnable (p. 10-6) *)
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 4800H));	(* TxEnable (p. 10-6) *)
	SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 3001H))	(* UpUnstall (p. 10-8) *)
END InitRegisters;

(* Scan the PCI bus for the specified card. *)

PROCEDURE ScanPCI(vendor, device, model: LONGINT; flags, media: SET);
VAR index, bus, dev, fct, res, base, irq, i: LONGINT; d: LinkDevice; c: Controller; name: AosPlugins.Name;
BEGIN
	index := 0;
	WHILE (PCI.FindPCIDevice(device, vendor, index, bus, dev, fct) = PCI.Done) & (installed < 10) DO
		res := PCI.ReadConfigDword(bus, dev, fct, PCI.Adr0Reg, base); ASSERT(res = PCI.Done);
		ASSERT(ODD(base)); DEC(base);	(* I/O mapped *)
		res := PCI.ReadConfigByte(bus, dev, fct, PCI.IntlReg, irq); ASSERT(res = PCI.Done);
(*
		IF irq = 11 THEN
			res := PCI.WriteConfigByte(bus, dev, fct, PCI.IntlReg, 5); ASSERT(res = PCI.Done);
			res := PCI.ReadConfigByte(bus, dev, fct, PCI.IntlReg, irq); ASSERT(res = PCI.Done);
		END;
*)
		NEW(d, AosNet.TypeEthernet, MTU, 6);
		name := Name;
		i := 0; WHILE name[i] # 0X DO INC(i) END;
		name[i] := CHR(ORD("0") + installed);
		name[i+1] := 0X;
		d.SetName(name);
		d.desc := Desc;
		NEW(c, d, base, irq, model, flags, media);	(* increments "installed" when successful *)
		c.bus := bus; c.pdev := dev; c.fct := fct;
		INC(index)
	END
END ScanPCI;

(** Install a driver object for every NIC found. *)

PROCEDURE Install*(par: PTR): PTR;
BEGIN {EXCLUSIVE}
	IF installed = 0 THEN
		ScanPCI(10B7H, 9200H, Model90xC, {}, Auto);
		ScanPCI(10B7H, 6055H, Model90xB, {Eprom230, InvertMIIPower}, MII);	(* check if C model *)
		ScanPCI(10B7H, 9055H, Model90xB, {}, Auto);
		ScanPCI(10B7H, 9056H, Model90xB, {}, MII);
		ScanPCI(10B7H, 9004H, Model90xB, {}, Auto);
		ScanPCI(10B7H, 9005H, Model90xB, {}, Auto);
		ScanPCI(10B7H, 9050H, Model90x, {}, MII);
		ScanPCI(10B7H, 9000H, Model90x, {}, Base10T);
		ScanPCI(10B7H, 9001H, Model90x, {}, Base10T)
	END;
	RETURN NIL
END Install;

(** Remove all device driver objects. *)

PROCEDURE Remove*(par: PTR): PTR;
VAR table: AosPlugins.Table; i: LONGINT;
BEGIN {EXCLUSIVE}
	AosNet.registry.GetAll(table);
	IF table # NIL THEN
		FOR i := 0 TO LEN(table)-1 DO
			IF table[i] IS LinkDevice THEN table[i](LinkDevice).Finalize(TRUE) END
		END
	END;
	installed := 0;
	RETURN NIL
END Remove;

(* Request an interrupt from every controller. *)

PROCEDURE Kick*(par: PTR): PTR;
VAR i, base: LONGINT; table: AosPlugins.Table;
BEGIN
	AosNet.registry.GetAll(table);
	IF table # NIL THEN
		FOR i := 0 TO LEN(table)-1 DO
			IF table[i] IS LinkDevice THEN
				base := table[i](LinkDevice).ctrl.base;
				AosOut.Enter; AosOut.String(table[i].name); AosOut.Exit;
				SYSTEM.PORTOUT(base+0EH, SYSTEM.VAL(INTEGER, 6000H));	(* RequestInterrupt (p. 10-9) *)
			END
		END
	END;
	RETURN NIL
END Kick;

(* Dump all registers - may have side effects that influence the device's normal operation *)

PROCEDURE Dump*(par: PTR): PTR;
VAR i, base, win: LONGINT; int: INTEGER; table: AosPlugins.Table;

	PROCEDURE Byte(reg: ARRAY OF CHAR; ofs: LONGINT);
	VAR x: CHAR;
	BEGIN
		AosOut.String(reg); AosOut.Char("=");
		SYSTEM.PORTIN(base+ofs, x);
		AosOut.Hex(ORD(x), -2); AosOut.Char(" ")
	END Byte;
	
	PROCEDURE Word(reg: ARRAY OF CHAR; ofs: LONGINT);
	VAR x: INTEGER;
	BEGIN
		AosOut.String(reg); AosOut.Char("=");
		SYSTEM.PORTIN(base+ofs, x);
		AosOut.Hex(LONG(x) MOD 10000H, 8); AosOut.Char(" ")
	END Word;
	
	PROCEDURE DWord(reg: ARRAY OF CHAR; ofs: LONGINT);
	VAR x: LONGINT;
	BEGIN
		AosOut.String(reg); AosOut.Char("=");
		SYSTEM.PORTIN(base+ofs, x);
		AosOut.Hex(x, 8); AosOut.Char(" ")
	END DWord;
	
	PROCEDURE PCIWord(reg: ARRAY OF CHAR; ofs: LONGINT);
	VAR x, res: LONGINT; ctrl: Controller;
	BEGIN
		ctrl := table[i](LinkDevice).ctrl;
		AosOut.String(reg); AosOut.Char("=");
		res := PCI.ReadConfigWord(ctrl.bus, ctrl.pdev, ctrl.fct, ofs, x);
		AosOut.Hex(x MOD 10000H, 8); AosOut.Char(" ")
	END PCIWord;
	

BEGIN
	AosNet.registry.GetAll(table);
	IF table # NIL THEN
		FOR i := 0 TO LEN(table)-1 DO
			IF table[i] IS LinkDevice THEN
				base := table[i](LinkDevice).ctrl.base;
				AosOut.Enter;
				AosOut.String(table[i].name); AosOut.Char(" ");
					(* current window *)
				SYSTEM.PORTIN(base+0EH, int); win := ASH(int, -13) MOD 8;
				AosOut.String("Window="); AosOut.Int(win, 1); AosOut.Char(" ");
					(* assume 3C90xB *)
				Byte("TxPktId", 18H); Byte("Timer", 1AH); Byte("TxStatus", 1BH);
				(*Word("IntStatusAuto", 1EH);*)	(* reading this would clear InterruptEnable (p. 8-5) *)
				DWord("DmaCtrl", 20H);
				DWord("DnListPtr", 24H); Byte("DnBurstThresh", 2AH);
				Byte("DnPriorityThresh", 2CH); Byte("DnPoll", 2DH);
				DWord("UpPktStatus", 30H); Word("FreeTimer", 34H);
				Word("Countdown", 36H); DWord("UpListPtr", 38H);
				Byte("UpPriorityThresh", 3CH); Byte("UpPoll", 3DH);
				Byte("UpBurstThresh", 3EH); DWord("RealTimeCnt", 40H);
				Word("DnMaxBurst", 78H); Word("UpMaxBurst", 7AH);
					(* output windows *)
				SetWindow(base, 0);
				DWord("0.BiosRomAddr", 4); Byte("0.BiosRomData", 8);
				Word("0.EepromCommand", 0AH); Word("0.EepromData", 0CH);
				Word("0.IntStatus", 0EH);
				SetWindow(base, 1);
				Word("1.IntStatus", 0EH);
				SetWindow(base, 2);
				Word("2.StationAddress-0", 0); Word("2.StationAddress-2", 2); Word("2.StationAddress-4", 4);
				Word("2.StationMask-0", 6); Word("2.StationMask-2", 8); Word("2.StationMask-4", 0AH);
				Word("2.ResetOptions", 0CH); Word("2.IntStatus", 0EH);
				SetWindow(base, 3);
				DWord("3.InternalConfig", 0); Word("3.MaxPktSize", 4);
				Word("3.MacControl", 6); Word("3.MediaOptions", 8);
				Word("3.RxFree", 0AH); Word("3.TxFree", 0CH);
				Word("3.IntStatus", 0EH);
				SetWindow(base, 4);
				Word("4.VcoDiagnostic", 2); Word("4.FifoDiagnostic", 4);
				Word("4.NetworkDiagnostic", 6); Word("4.PhysicalMgmt", 8);
				Word("4.MediaStatus", 0AH); Byte("4.BadSSD", 0CH);
				Byte("4.UpperBytesOk", 0DH); Word("4.IntStatus", 0EH);
				SetWindow(base, 5);
				Word("5.TxStartThresh", 0); Word("5.RxEarlyThresh", 6);
				Byte("5.RxFilter", 8); Byte("5.TxReclaimThresh", 9);
				Word("5.InterruptEnable", 0AH); Word("5.IndicationEnable", 0CH);
				Word("5.IntStatus", 0EH);
				SetWindow(base, 6);
				Byte("6.CarrierLost", 0); Byte("6.SqeErrors", 1);
				Byte("6.MultipleCollisions", 2); Byte("6.SingleCollisions", 3);
				Byte("6.LateCollisions", 4); Byte("6.RxOverruns", 5);
				Byte("6.FramesXmittedOk", 6); Byte("6.FramesRcvdOk", 7);
				Byte("6.FramesDeferred", 8); Byte("6.UpperFramesOk", 9);
				Word("6.BytesRcvdOk", 0AH); Word("6.BytesXmittedOk", 0CH);
				Word("6.IntStatus", 0EH);
				SetWindow(base, 7);
				Word("7.VlanMask", 0); Word("7.VlanEtherType", 4);
				Word("7.PowerMgmtEvent", 0CH); Word("7.IntStatus", 0EH);
				SetWindow(base, win);
				Byte("Timer", 1AH); Byte("TxStatus", 1BH);
				(*Word("IntStatusAuto", 1EH);	Reding this register clears IntEnable *)
				DWord("DMACtrl", 20H); DWord("DnListPtr", 24);
				Byte("DnBurstThresh", 2AH);
				Byte("DnPriorityThresh", 2CH); Byte("DnPoll", 2DH);
				DWord("UpPktStatus", 30H);
				Word("FreeTimer", 34H); Word("Countdown", 36H);
				DWord("UpListPtr", 38H);
				Byte("UpPriorityThresh", 3CH); Byte("UpPoll", 3DH); Byte("UpBurstThresh", 3EH);
				DWord("RealTimeCnt", 40H);
				Word("DnMaxBurst", 78H); Word("UpMaxBurst", 7AH);
				PCIWord("Status", 02H);
				AosOut.Exit
			END
		END
	END;
	RETURN NIL
END Dump; 

PROCEDURE Cleanup;
BEGIN
	IF AosModules.shutdown = AosModules.None THEN	(* module is being freed *)
		IF Remove(NIL) = NIL THEN END
	END
END Cleanup;

BEGIN
	installed := 0;
	AosModules.InstallTermHandler(Cleanup)
END Aos3Com90x.

(*
History:
17.10.2003	mvt	Changed for new AosNet interface
05.11.2003	mvt	Implemented DMA directly to AosNet.Buffer

! System.Free Aos3Com90x ~

Aos.Call Aos3Com90x.Install
Aos.Call Aos3Com90x.Remove

AosTestNet.ShowDevices
AosTestNet.SetDevice "3Com90x#0"
AosTestNet.SendBroadcast
AosTestNet.SendTest 1

System.State Aos3Com90x ~

Aos.Call Aos3Com90x.Kick
Aos.Call Aos3Com90x.Kick2
Aos.Call Aos3Com90x.Dump

Aos.Call Aos3Com90x.TestCount 100000

NetSystem.Start
NetSystem.Stop

ftp://reali@lillian.ethz.ch
*)