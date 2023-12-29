MODULE AosUsbUhci; (** AUTHOR "cplattner"; PURPOSE "Intel UHCI driver" *)
(**
	Aos Intel UHCI USB Host Controller Driver
	Implements the AosUsbHcdi host controller driver interface (HCDI)

	Reference: Universal Host Controller Interface (UHCI) Design Guide, Revision 1.1, http://www.intel.com

	30.09.2000 cp  first release
	18.10.2000 cp  bugfixes, added new debug support
	20.10.2000 cp  memory fragmentation fixed
	22.10.2000 cp  TD allocation changed, IRQ spread fixed, irq-out bugfix
	10.11.2003 sst  Introduction of a host controller driver interface (HCDI), OOP
*)

IMPORT AosOut, SYSTEM, PCI, AosKernel, AosActive, AosInterrupts, AosModules, AosUsbHcdi, AosPlugins;

CONST

	Name = "UsbHc";
	Description = "UHCI USB Host Controller";

	Debug = FALSE;
	
	(* if DebugMask # {} then show the data structure of all USB transfers whose status includes all flags which are
	included in DebugMask AND whose req.endpoint field matches DebugEndPoint AND whose req.device.address matches
	DebugAddress (if not set to -1) *)
	DebugMask = {};
	DebugEndPoint = 81H; (* must include direction flag *)
	DebugAddress = 1;

	MaxTDPerController = 1000000; (* 1 TD is 16 Byte of RAM - we need 24576 TD's for 12Mbit/s *)
	MaxGCEntries = 3;

	(* Offsets of USB registers from base io-address according UHCI design guide *)
	UsbCmd = 0H;	   (* command register*)
	UsbSts = 2H;         (* status register*)
	UsbIntr = 4H;	    (* interupt enable*)
	FrNum = 6H;	     (* frame number *)
	FlBaseAdr = 8H;    (* frame list base address *)
	SofMod = 0CH;	  (* start of frame modify *)
	PortSc1 = 10H;	  (* port 1 status / control *)
	PortSc2 = 12H;	  (* port 2 status / control *)

	(* Bits of the USB Command (UsbCmd) Register *)
	CmdMaxPacket = { 7 };
	CmdConfigureFlag = { 6 };
	CmdSoftwareDebug = { 5 };
	CmdForceGlobalResume = { 4 };
	CmdEnterGlobalSuspend = { 3 };
	CmdGlobalReset = { 2 };
	CmdHostControllerReset = { 1 };
	CmdRunStop = { 0 };
	
	(* Bits of the USB Status (UsbSts) Register *)
	StatusHChalted = { 5 };
	StatusProcessError = { 4 };
	StatusSystemError = { 3 };
	StatusResumeDetect = { 2 };
	StatusErrorInt = { 1 };
	StatusInt = { 0 };

	(* Bits of the USB Interrupt Enable (UsbIntr) Register *)
	IntShortPacket = { 3 };
	IntIOC = { 2 };
	IntResume = { 1 };
	IntTimeoutCRC = { 0 };

	(* Bits of the USB Port Status and Control (PortSc) Register *)
	PortSuspend = { 12 };
	PortReset = { 9 };
	PortLowSpeed = { 8 };
	PortResumeDetect = { 6 };
	PortLineStatus = { 4,5 };
	PortEnabledChange = { 3 };
	PortEnabled = { 2 };
	PortConnectStatusChange = { 1 };
	PortCurrentConnectStatus = { 0 };

	(* Bits of the TD Link Pointer DWORD*)
	TDTerminate = { 0 };
	TDQHSelect = { 1 };
	TDDepthFirst = { 2 };
						
	(* Bits of the TD Control and Status DWORD *)
	TDBitStuff = { 17 };
	TDCrcTimeout = { 18 };
	TDNak = { 19 };
	TDBabble = { 20 };
	TDDataBuffer = { 21 };
	TDStalled = { 22 };
	TDActive = { 23 };
	TDIOC = { 24 };
	TDIOS = { 25 };
	TDLS = { 26 };
	TDERR0 = {}; TDERR1 = { 27 }; TDERR2 = { 28 }; TDERR3 = { 27, 28 };
	TDSPD = { 29 };
				
	(* Bits of the TD Token DWORD *)
	TDDataToggle = { 19 };

	(* TD Token Packet Identification (PID) field *)
	PidOut = 0E1H;
	PidIn = 069H;
	PidSetup = 02DH;
	
	(* timer used by procedure DoSchedule *)
	SleepTime = 1;

TYPE

	UhciFrameList = POINTER TO RECORD
		index : LONGINT;
		framelistbase : LONGINT;
		field : ARRAY 2*1024 OF LONGINT; (* hack: double it, so that we pass a 4K page boundary; field must be 4K aligned *)
	END;

	UhciTDList = POINTER TO RECORD
		index : LONGINT;
		tdlistbase : LONGINT; 
		field : ARRAY ((MaxTDPerController + 1) * 4) OF LONGINT; (* plus one, for the 16byte boundary alignment*)
		freelist : ARRAY MaxTDPerController OF LONGINT;
		first, last : LONGINT; (* indicies of the first and the last entry of the freelist *)
	END;

	UhciController = OBJECT (AosUsbHcdi.Hcd)                         
	VAR
		(* host controller configuration data *)
		iobase: LONGINT;
		irq : INTEGER;
		portCount : INTEGER;
		ports : POINTER TO ARRAY OF LONGINT;  (* addresses of the Port Status Control registers relative to iobase *)
		
		(* UHCI data structures specific *)
		framelist : UhciFrameList;
		tdlist : UhciTDList;
		controlTD : LONGINT;
		bulkTD : LONGINT;
		isochronousTD : LONGINT;
		interruptTD : ARRAY 11 OF LONGINT;
		gcQueueList : ARRAY MaxGCEntries OF LONGINT;
		gcQueueTimestamp :  ARRAY MaxGCEntries OF INTEGER;
		
		(* interrupt handling related fields *)
		running : BOOLEAN;	(* controller is active and has been started *)
		status : SET;				
		interruptCounter : LONGINT;
		intHandlers : AosUsbHcdi.UsbTReq;  (* list of UsbTReqs with interrupt handler procedures *)
		
		(* used by Wait() *)
		timer : AosKernel.Timer;
												
		(** Enable port number <port> on this root hub *)
		PROCEDURE EnablePort*(port : INTEGER);
		(* not reentrant !! *)
		BEGIN 
			(* reset port *)
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, PortReset)); Wait (10);
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, 0)); Wait ( 1 ); (* HMMMMMMMMMM MASSIVE HACK *) 
			(* enable port *)
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, PortEnabled)); Wait ( 50 );
		END EnablePort;

		(** Disables port number <port> on this root hub *)
		PROCEDURE DisablePort*(port : INTEGER);
		BEGIN
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, 0));
		END DisablePort;
		
		(** Get the status of the port <port> of this root hub. Registers which indicate changes are reset by GetPortStatus *)
		PROCEDURE GetPortStatus*(port : INTEGER):SET;
		VAR
			status, s : SET;
		BEGIN
			SYSTEM.PORTIN(ports[port], SYSTEM.VAL(INTEGER, s));
			status := {};
			IF (s * PortCurrentConnectStatus) # {} THEN status := status + AosUsbHcdi.PortStatusDevicePresent END;             
			IF (s * PortEnabled) # {} THEN status := status + AosUsbHcdi.PortStatusEnabled END;
			IF (s * PortLowSpeed) # {} THEN status := status + AosUsbHcdi.PortStatusLowSpeed END;
			IF (s * PortConnectStatusChange) # {} THEN status := status + AosUsbHcdi.PortStatusConnectChange; END;
	
			(* reset the PortEnabledChande and the PortConnectStatusChange bit *)
			IF (s * (PortEnabledChange + PortConnectStatusChange)) # {} THEN
				SYSTEM.PORTOUT(ports[port], SHORT(SYSTEM.VAL(LONGINT, s * (PortEnabled + PortEnabledChange + PortConnectStatusChange)))); (* PortEnabled *)
			END;
			RETURN status;
		END GetPortStatus;

		(** Returns the number of ports of this root hub *)
		PROCEDURE GetPortCount*():INTEGER;
		BEGIN
			RETURN portCount;
		END GetPortCount;

		(* Returns the current frame number; the frame number is incremented by the Host Controller at the end of each frame time;
		GetFrameNumber() is used for time stamps *)
		PROCEDURE GetFrameNumber() : INTEGER;
		VAR
			frameNumber : INTEGER;
		BEGIN
			SYSTEM.PORTIN(iobase + FrNum, frameNumber);
			frameNumber := SHORT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, frameNumber) * {0..10}));
			RETURN frameNumber;
		END GetFrameNumber;
					
		(* Returns the address of the first free TD in the TD freelist. If the TD freelist is empty, some TD's are freed up if possible *)
		PROCEDURE AllocTD():LONGINT;
		VAR
			retval : LONGINT;
			timenow, i : INTEGER;
			needwait, entryfound : BOOLEAN;
		BEGIN {EXCLUSIVE}
	
			IF (tdlist.first = tdlist.last) THEN (* TD freelist is empty. Need to free up at least one TD *)
	
				timenow := GetFrameNumber(); needwait := FALSE; entryfound := FALSE;
	
				FOR i:= 0 TO MaxGCEntries - 1 DO
					IF gcQueueList[i] # 1 THEN (* ok, entry found *)
						IF (timenow # gcQueueTimestamp[i]) THEN (* good, entry can be free'd NOW *)
							FreeDeadQHChain(gcQueueList[i]);
							gcQueueList[i] := 1;
							needwait := FALSE; entryfound := TRUE;
						ELSE
							IF entryfound = FALSE THEN needwait := TRUE; END; (* only wait for this entry if there is no other *)
						END;
					END;
				END;
	
				IF needwait THEN
					WHILE (GetFrameNumber() = timenow) DO (* nothing *) END; (* wait until the host controller has processed this queue *)
					(* we can do the following, since in Native Oberon there wont be any new entries, there is no concurrency;
						staubesv: should work, because AllocTD() is EXCLUSIVE, but: performance ??? *)			
					FOR i:= 0 TO MaxGCEntries - 1 DO
						IF gcQueueList[i] # 1 THEN FreeDeadQHChain(gcQueueList[i]); gcQueueList[i] := 1; END;
					END;
				END;
				
				IF (tdlist.first = tdlist.last) THEN (* ERROR: Couldn't free up any TD's. No TD's available *)
					AosOut.String("AosUsbUhci: No more free TD's. Please increase the TD count in AosUsbUhci.Mod"); AosOut.Ln;
					RETURN -1;
				END;
			END;
	
			retval := tdlist.freelist[tdlist.first];
			tdlist.first := (tdlist.first + 1) MOD MaxTDPerController;
	
			RETURN retval;
		END AllocTD;

		PROCEDURE FreeTDX(addr : LONGINT);
		BEGIN {EXCLUSIVE}
			FreeTD(addr);
		END FreeTDX;
		
		(* Inserts the TD at address addr into the tdlist.freelist *)
		PROCEDURE FreeTD(addr : LONGINT);
		BEGIN
			ASSERT((addr >= tdlist.tdlistbase) OR (addr <= (tdlist.tdlistbase + MaxTDPerController*16))); 
				  ASSERT( (SYSTEM.VAL(SET, addr) * {0..3}) = {} );  (* TD's have to be 16-byte aligned *)
			tdlist.last := (tdlist.last + 1) MOD MaxTDPerController;
			ASSERT(tdlist.first # tdlist.last);  (* something is REALLY going wrong, freeing something but nothing allocated?? *)
			tdlist.freelist[tdlist.last] := addr;
		END FreeTD;

		PROCEDURE FreeDeadQHChainX(addr : LONGINT);
		BEGIN {EXCLUSIVE}
			FreeDeadQHChain(addr);
		END FreeDeadQHChainX;
		
		(* Frees up all TD's in a queue. addr is the address of the queue head of the queue which shall be cleaned up. 
    	The dead version is very fast, since it knows that the UHCI does not access this queue (=> dead)  *)
		PROCEDURE FreeDeadQHChain(addr : LONGINT);
		VAR
			nexttd : LONGINT;
		BEGIN
			(* Get address of the first TD in the queue head with address addr *)
			SYSTEM.GET(addr + 8, SYSTEM.VAL(LONGINT, nexttd)); (* nexttd := queue element link pointer *)
	
			FreeTD(addr);
	
			(* Free all the TDs in the chain *)
			LOOP
				(* bit 0 is a flag that indicates whether the link pointer of the TD is valid. If it's set, this TD is the last TD of the queue *)
				IF (SYSTEM.VAL(SET, nexttd) * {0}) # {} THEN (* last TD in queue *) EXIT; END; 
				addr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, nexttd) * {4..31}); (* addr := physical addr of nexttd; 16-byte aligned *)
				SYSTEM.GET(addr, SYSTEM.VAL(LONGINT, nexttd)); (* nexttd := link pointer of td at addr *)
				FreeTD(addr);
			END;
		END FreeDeadQHChain;

			(* Frees up all TD's in the queue whose queue head is found at address addr. Live meaning: The UHCI does perhaps still access this queue, 
		so we must be careful when we free some element of the queue. We do this by using a waitqueue. *)
		PROCEDURE FreeLiveQHChain(addr : LONGINT);
		VAR
			nexttd : LONGINT;
			timenow, i, freeentry : INTEGER;
		BEGIN {EXCLUSIVE}
			timenow := GetFrameNumber(); freeentry := -1;
	
			FOR i:= 0 TO MaxGCEntries - 1 DO
				IF gcQueueList[i] = 1 THEN (* found a free entry to use *)
						freeentry := i; 
				ELSIF gcQueueTimestamp[i] # timenow THEN (* host controller has already processed this queue -> it's dead *)
						FreeDeadQHChain(gcQueueList[i]);
						gcQueueList[i] := 1;
						freeentry := i; (* found a free entry to use *)
				END;
			END;
			
			IF freeentry # -1 THEN
				gcQueueList[freeentry] := addr;
				gcQueueTimestamp[freeentry] := timenow;
			ELSE
				(* THIS IS VERY UNLIKELY *)
				IF Debug THEN AosOut.String("AosUsbUhci: Bad luck, GCqueue full"); AosOut.Ln; END;
				WHILE (GetFrameNumber() = timenow) DO (* nothing *) END; (* wait until the queue has been processed by the host controller *)
				FreeDeadQHChain(addr);
				(* we can do the following, since in Native Oberon there wont be any new entries, there is no concurrency *)
				FOR i:= 0 TO MaxGCEntries - 1 DO
					IF gcQueueList[i] # 1 THEN FreeDeadQHChain(gcQueueList[i]); gcQueueList[i] := 1; END;
				END;
			END; 
		END FreeLiveQHChain;

		(* transaction schedules *)
		PROCEDURE DoSchedule(req : AosUsbHcdi.UsbTReq; qh : LONGINT);
		VAR
		   queue : LONGINT; 
			timer : AosKernel.Timer;
			sleeps, rest : LONGINT; (* req.timeout = x*sleeps + rest *)
			expired : BOOLEAN;
			status : SET;
		BEGIN
			queue := InsertQH(req, qh);
			
			NEW(timer); 
	
			IF req.timeout = -1 THEN (* infinite timeout, wait until transfer completed *)
				LOOP
					status := GetQueueStatus(req, qh);
					IF (status * AosUsbHcdi.ResInProgress) = {} THEN EXIT END;
					timer.Sleep(SleepTime);
				END;
				
			ELSE
			(*	LOOP
					status := GetQueueStatus(req,qh);
					IF (status * AosUsbHcdi.ResInProgress) = {} THEN EXIT END;
				END;
			*)
				
				expired := FALSE;
				sleeps := req.timeout DIV SleepTime;
				rest := req.timeout MOD SleepTime;
				
				LOOP
					status := GetQueueStatus(req, qh);
					IF expired OR ((status * AosUsbHcdi.ResInProgress) = {}) THEN EXIT END;
					
					DEC(sleeps);
					
					IF sleeps>0 THEN 
						timer.Sleep(SleepTime); DEC(sleeps);
					ELSIF rest>0 THEN 
						timer.Sleep(rest);
						rest := 0;
					ELSE
						expired := TRUE;
					END;
				END;    
				
			END; 
	
			req.status := status;
			
			IF (DebugMask#{}) & (req.conSpec#NIL) & (req.endpoint=DebugEndPoint) THEN 
			(* advanced debugging: show the data structure of the transfer *)
				IF (DebugAddress#(-1)) & (DebugAddress=req.device.address) THEN
					IF (DebugMask*req.status = DebugMask) THEN 
						AosOut.String("AosUsbUhci: Debug mask matched: Showing tranfer"); AosOut.Ln;
						AosOut.String("   Endpoint: ");PrintHex(req.endpoint);
						AosOut.String("  Address: "); AosOut.Int(req.device.address,0);
						AosOut.String("  TransferSize: "); AosOut.Int(req.bufferLen,0); AosOut.Ln;
						HumanQH(req.conSpec.qh); 
						AosOut.Ln;AosOut.String("FULL SCHEULDE::::"); AosOut.Ln;
					END;
				END;
			END;
			DeleteQH(req, queue, qh); 

			IF Debug THEN AosOut.String("AosUsbUhci: Blocking transfer finished"); AosOut.Ln; END;
		END DoSchedule;
		
		(** Updates the req.status field *)
		PROCEDURE ProbeTransfer*(req : AosUsbHcdi.UsbTReq);
		VAR
			spec : AosUsbHcdi.ConSpec;
		BEGIN 
			IF req.conSpec = NIL THEN
				AosOut.String("AosUsbUhci: Warning, trying to probe blocking transfer"); AosOut.Ln;
				req.status := AosUsbHcdi.ResInternal;
				RETURN;
			END;
			spec := req.conSpec (AosUsbHcdi.ConSpec);
			req.status := GetQueueStatus(req, spec.qh); 
		END ProbeTransfer;

		(** Removes the USB transfer request <req> from the host controller schedule *)
		PROCEDURE DeleteTransfer*(req :AosUsbHcdi.UsbTReq);
		VAR
			spec : AosUsbHcdi.ConSpec;
		BEGIN 
			IF req.conSpec = NIL THEN
				AosOut.String("AosUsbUhci: Warning, trying to delete trans again"); AosOut.Ln;
				RETURN
			END;
	
			spec := req.conSpec (AosUsbHcdi.ConSpec);
			DeleteQH(req, spec.queue, spec.qh);
			FreeLiveQHChain(spec.qh);
			req.conSpec := NIL; 
	
			IF Debug THEN AosOut.String("AosUsbUhci: request deleted"); AosOut.Ln; END;	
		END DeleteTransfer;

		(** Restarts (reactivates) the interrupt transfer <req> *)
		PROCEDURE RestartInterrupt*(req : AosUsbHcdi.UsbTReq);
		VAR
			spec : AosUsbHcdi.ConSpec;
		BEGIN 
			ASSERT(req.typ=AosUsbHcdi.TransferInterrupt);
			IF Debug THEN AosOut.String("AosUsbUhci: got request for restarting interrupt"); AosOut.Ln; END;
	
			IF req.conSpec = NIL THEN
				AosOut.String("AosUsbUhci: Warning, trying to restart blocking interrupt"); AosOut.Ln;		
				req.status := AosUsbHcdi.ResInternal;
				RETURN;
			END;
	
			IF (req.status * AosUsbHcdi.ResInProgress) # {} THEN (* don't restart allready started transfers *) RETURN END;
	
			spec := req.conSpec (AosUsbHcdi.ConSpec);
			req.status := AosUsbHcdi.ResInProgress;
			RestartInterruptQH(req, spec.qh); 
		END RestartInterrupt;

		PROCEDURE RestartInterruptQH(req : AosUsbHcdi.UsbTReq; qh : LONGINT);
		VAR
			tdtmp, val, pid : LONGINT;
			status : SET; 
			datatoggle : BOOLEAN;
		BEGIN
			SYSTEM.GET(qh + 8, SYSTEM.VAL(LONGINT, tdtmp));
	
			(* modify the data0/1 bit *)
			SYSTEM.GET(tdtmp + 8, SYSTEM.VAL(LONGINT, val));
			pid := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {0..7});
			status := SYSTEM.VAL(SET, val);
	
			IF pid = PidOut THEN
				datatoggle := req.device.dataToggleOut[req.endpoint MOD 16];
				req.device.dataToggleOut[req.endpoint MOD 16] := ~datatoggle;
			ELSIF pid = PidIn THEN
				datatoggle := req.device.dataToggleIn[req.endpoint MOD 16];
				req.device.dataToggleIn[req.endpoint MOD 16] := ~datatoggle;
			ELSE
				AosOut.String("AosUsbUhci:RestartInterrupt:pid error");AosOut.Ln;
				HALT(303);
			END;
	
			IF datatoggle THEN
				status := status + TDDataToggle;
			ELSE
				status := status - TDDataToggle;
			END;
			SYSTEM.PUT(tdtmp + 8, SYSTEM.VAL(LONGINT, status));	
	
			(* reactivate it *)
			SYSTEM.GET(tdtmp + 4, SYSTEM.VAL(LONGINT, val));
			status := SYSTEM.VAL(SET, val) + TDActive + TDERR3;
			SYSTEM.PUT(tdtmp + 4, SYSTEM.VAL(LONGINT, status));
	
			(* set the queue element pointer so that the uhci will execute the element again *)
			SYSTEM.PUT(qh + 4, SYSTEM.VAL(LONGINT, tdtmp));
		END RestartInterruptQH;
		
		(* Insert the queue head qh into the appropriate queue *)
		PROCEDURE InsertQH(req : AosUsbHcdi.UsbTReq; qh : LONGINT) : LONGINT; 
		VAR
			qhtmp, queue : LONGINT;
			slots : LONGINT; 
			index, queueslots : INTEGER;
		BEGIN {EXCLUSIVE}
		
			IF req.typ = AosUsbHcdi.TransferControl THEN
				queue := controlTD
			ELSIF req.typ = AosUsbHcdi.TransferBulk THEN
				queue := bulkTD
			ELSIF req.typ = AosUsbHcdi.TransferInterrupt THEN
				slots := 1024 DIV req.irqInterval;
				index := 0; queueslots := 1024;
				LOOP
					IF queueslots = 0 THEN index := 10; EXIT; END;
					IF slots >= queueslots THEN EXIT END;
					queueslots := queueslots DIV 2; INC (index)
				END;
				queue := interruptTD[index]
			ELSE 
				AosOut.String("AosUsbUhci:InsertQH: transfer type not supported"); AosOut.Ln;
				HALT(303); 
			END;
			
			(* inserts queue head <qh> into the queue *)
			SYSTEM.GET(queue, SYSTEM.VAL(LONGINT, qhtmp));  (* qhtmp:= queue head link pointer of queue head <queue> *)
			SYSTEM.PUT(qh, SYSTEM.VAL(LONGINT, qhtmp));		(* queue head link pointer of <qh> := qhtmp  (hasn't been used before) *)
			SYSTEM.PUT(queue, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, qh) + {1} )); (* queue head link pointer of <queue> := pointer to <qh> *)
	
			RETURN queue
		END InsertQH;

		(* delete the queue head <qh> in the queue <queue> *)
		PROCEDURE DeleteQH(req : AosUsbHcdi.UsbTReq; queue, qh : LONGINT); 
		VAR
			qhtmp, delthis : LONGINT;
		BEGIN {EXCLUSIVE}
		
			delthis := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, qh) + {1} );
	
			LOOP
				SYSTEM.GET(queue, SYSTEM.VAL(LONGINT, qhtmp));
				IF qhtmp = 1 THEN
					AosOut.String("AosUsbUhci: Fatal error, DeleteQH cannot find qh entry in queue"); AosOut.Ln;
					HALT(303)
				END;
				IF qhtmp = delthis THEN (* delete qh *)
					SYSTEM.GET(qh, SYSTEM.VAL(LONGINT, qhtmp));
					SYSTEM.PUT(queue, SYSTEM.VAL(LONGINT, qhtmp));
					EXIT;
				END;
				queue := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, qhtmp) - {1} )
			END
		END DeleteQH;

		PROCEDURE ScheduleInterrupt(req : AosUsbHcdi.UsbTReq) : SET;
		VAR
			qh, td, firsttd, lasttd : LONGINT;
			status : SET; 
			datatoggle : BOOLEAN;
			spec : AosUsbHcdi.ConSpec; 
			pid : INTEGER;
		BEGIN 
			IF Debug THEN AosOut.String("AosUsbUhci: got request for interrupt transfer"); AosOut.Ln; END;
			(* the specs say that values  0 < x < 256 are ok, but since the controller supports it, we allow for higher values *)
			(* perhaps needed for special usb driver test code *)
			IF (req.irqInterval < 0) OR (req.irqInterval > 1000) THEN RETURN AosUsbHcdi.ResInternal; END;
		
			status := TDActive + TDIOC + TDERR3;
			IF req.device.lowSpeed THEN status := status + TDLS; END;
		
			IF (SYSTEM.VAL(SET, req.endpoint) * {7}) = {} THEN
				datatoggle := req.device.dataToggleOut[req.endpoint MOD 16];
				IF req.bufferLen < req.device.maxPacketSizeOut[req.endpoint MOD 16] THEN
					RETURN AosUsbHcdi.ResInternal;
				END;
				pid := PidOut;
			ELSE
				datatoggle := req.device.dataToggleIn[req.endpoint MOD 16];
				IF req.bufferLen < req.device.maxPacketSizeIn[req.endpoint MOD 16] THEN
					RETURN AosUsbHcdi.ResInternal;
				END;
				status := status + TDSPD;
				pid := PidIn;
			END;
		
			qh := AllocTD();
			IF (qh = -1) THEN (* ERROR: Couldn't allocate a free TD *) RETURN AosUsbHcdi.ResInternal; END;
		
			td := AllocTD();
			IF (td = -1) THEN (* ERROR: Couldn't allocate a free TD *) 
				FreeTDX(qh);
				RETURN AosUsbHcdi.ResInternal;
			END;
		
			firsttd := td; lasttd := td;
		
			BuildTDLinkPointer(td, TDTerminate, 0);
			BuildTDControlStatus(td, status);
			BuildTDToken(td, pid, req.device.address, req.endpoint MOD 16, datatoggle, req.bufferLen);
			SYSTEM.PUT(td + 12, SYSTEM.VAL(LONGINT, req.buffer));
		
			(* Build qh *)
			BuildTD(qh, 1, firsttd, firsttd, lasttd);
		
			req.status := AosUsbHcdi.ResInProgress;
		
			IF req.timeout # 0 THEN
				IF Debug THEN AosOut.String("AosUsbUhci: starting interrupt transfer"); AosOut.Ln; END;	
				DoSchedule(req, qh);
				FreeLiveQHChain(qh);
				req.conSpec := NIL;
			ELSE
				IF Debug THEN AosOut.String("AosUsbUhci: starting nonblocking interrupt transfer"); AosOut.Ln; END;		
				NEW(spec); spec.qh := qh; req.conSpec := spec;
				spec.queue := InsertQH(req, qh);
			END;
			
			RETURN req.status;
		END ScheduleInterrupt;

		PROCEDURE ScheduleControl(req : AosUsbHcdi.UsbTReq) : SET;
		VAR
			qh, td, tdnext, firsttd, lasttd, pretd : LONGINT;
			pid : INTEGER;
			curlen, restlen, databuff : LONGINT;
			datatoggle : BOOLEAN;
			status : SET;
			spec : AosUsbHcdi.ConSpec;
		BEGIN 
			IF Debug THEN
				AosOut.String("AosUsbUhci: request for control transfer for controller "); AosOut.String(name); AosOut.Ln;
				AosOut.String("AosUsbUhci: details:");
				AosOut.String(" address "); AosOut.Int(req.device.address, 0);
				AosOut.String(" endpoint "); AosOut.Int(req.endpoint, 0);
				AosOut.String(" len: "); AosOut.Int(req.bufferLen, 0); AosOut.Ln;
			END;
		
			qh := AllocTD();
			IF (qh = -1) THEN (* ERROR: Couldn't allocate a free TD *) RETURN AosUsbHcdi.ResInternal; END;
		
			td := AllocTD();
			IF (td = -1) THEN (* ERROR: Couldn't allocate a free TD *)
				FreeTDX(qh);
				RETURN AosUsbHcdi.ResInternal;
			END;
		
			firsttd := td;
		
			(* Build Setup td *)
			tdnext := AllocTD();
			IF (tdnext = -1) THEN (* ERROR: Couldn't allocate a free TD *) RETURN AosUsbHcdi.ResInternal; END;
		
			status := TDActive + TDERR3;
			IF req.device.lowSpeed THEN status := status + TDLS; END;	
		
			BuildTDLinkPointer(td, TDDepthFirst, tdnext);
			BuildTDControlStatus(td, status);
			BuildTDToken(td, PidSetup, req.device.address, req.endpoint MOD 16, FALSE, 8);
			SYSTEM.PUT(td + 12, SYSTEM.VAL(LONGINT, req.controlMessage));
			
			(* Build Data TD's, if any are needed *)	
			IF req.bufferLen # 0 THEN (* need some TDs to transmit data *)
		
				datatoggle := TRUE;
				restlen := req.bufferLen;
				databuff := req.buffer;
		
				IF (SYSTEM.VAL(SET, req.endpoint) * {7}) = {} THEN pid := PidOut; ELSE pid := PidIn; status := status + TDSPD; END;
		
				WHILE restlen >  0 DO
				
					pretd := td;
					td := tdnext;
					tdnext := AllocTD();
					IF (tdnext = -1) THEN (* ERROR: Couldn't allocate a free TD *)
						BuildTDLinkPointer(pretd, TDTerminate, 0);
						BuildTD(qh, 1, firsttd, firsttd, pretd);
						FreeDeadQHChainX(qh);
						RETURN AosUsbHcdi.ResInternal;
					END;
			
					IF restlen > req.device.bMaxPacketSize0 THEN
						curlen := req.device.bMaxPacketSize0
					ELSE
						curlen := restlen;
					END; 
		
					BuildTDLinkPointer(td, TDDepthFirst, tdnext);
					BuildTDControlStatus(td, status);
					BuildTDToken(td, pid, req.device.address, req.endpoint MOD 16, datatoggle, curlen);
					SYSTEM.PUT(td + 12, SYSTEM.VAL(LONGINT, databuff));
				
					datatoggle := ~ datatoggle;
								
					databuff := databuff + curlen;
					restlen := restlen - curlen;
				END;
			END;
		
			td := tdnext;
				
			(* build the last TD in chain *)
			IF ((SYSTEM.VAL(SET, req.endpoint) * {7}) = {} ) OR (req.bufferLen = 0) THEN pid := PidIn; ELSE pid := PidOut; END;
			
			status := (status - (TDSPD + TDERR3)); 
			
			BuildTDLinkPointer(td, TDTerminate, 0);
			BuildTDControlStatus(td, status );	
			BuildTDToken(td, pid, req.device.address, req.endpoint MOD 16, TRUE, 0);
			SYSTEM.PUT(td + 12, SYSTEM.VAL(LONGINT, 0));
		
			lasttd := td;
			
			(* Build qh *)
			BuildTD(qh, 1, firsttd, firsttd, lasttd);
	
			req.status := AosUsbHcdi.ResInProgress;
			
			IF req.timeout # 0 THEN
				IF Debug THEN AosOut.String("AosUsbUhci: starting control transfer"); AosOut.Ln; END;
				DoSchedule(req, qh);
				FreeLiveQHChain(qh);
				req.conSpec := NIL;
			ELSE
				IF Debug THEN AosOut.String("AosUsbUhci: starting nonblocking control transfer"); AosOut.Ln; END;
				NEW(spec); spec.qh := qh; req.conSpec := spec;
				spec.queue := InsertQH(req, qh);
			END;
		
			RETURN req.status;
		END ScheduleControl;

		PROCEDURE ScheduleBulk(req : AosUsbHcdi.UsbTReq) : SET;
		VAR
			qh, td, tdnext, firsttd, lasttd, pretd : LONGINT;
			pid, pipesize : INTEGER;
			curlen, restlen, databuff : LONGINT;
			datatoggle : BOOLEAN;
			status : SET;
			spec : AosUsbHcdi.ConSpec;
		BEGIN
			qh := AllocTD();
			IF (qh = -1) THEN (* ERROR: Couldn't allocate a free TD *) RETURN AosUsbHcdi.ResInternal; END;
		
			td := AllocTD();
			IF (td = -1) THEN (* ERROR: Couldn't allocate a free TD *)
				FreeTDX(qh);
				RETURN AosUsbHcdi.ResInternal;
			END;
		
			firsttd := td;
			tdnext := td;
		
			status := TDActive + TDERR3;
			IF req.device.lowSpeed THEN status := status + TDLS; END;	
		
			restlen := req.bufferLen;
			databuff := req.buffer;
		
			IF (SYSTEM.VAL(SET, req.endpoint) * {7}) = {} THEN
				datatoggle := req.device.dataToggleOut[req.endpoint MOD 16];
				pipesize := req.device.maxPacketSizeOut[req.endpoint MOD 16];
				pid := PidOut;
			ELSE
				datatoggle := req.device.dataToggleIn[req.endpoint MOD 16];
				pipesize := req.device.maxPacketSizeIn[req.endpoint MOD 16];	
				pid := PidIn;
				status := status + TDSPD;
			END;
			
			LOOP
					pretd := td;
					td := tdnext;
			
					IF restlen > pipesize THEN
						curlen := pipesize;
						tdnext := AllocTD();
						IF (tdnext = -1) THEN  (* ERROR: Couldn't allocate a free TD *)
							BuildTDLinkPointer(pretd, TDTerminate, 0);
							BuildTD(qh, 1, firsttd, firsttd, pretd);
							FreeDeadQHChainX(qh);
							RETURN AosUsbHcdi.ResInternal;
						END;
						BuildTDLinkPointer(td, TDDepthFirst, tdnext);
					ELSE
						curlen := restlen;
						BuildTDLinkPointer(td, TDTerminate, 0);
					END;
			
					BuildTDControlStatus(td, status);
			
					BuildTDToken(td, pid, req.device.address, req.endpoint MOD 16, datatoggle, curlen);
					SYSTEM.PUT(td + 12, SYSTEM.VAL(LONGINT, databuff));
					
					datatoggle := ~datatoggle;
						
					databuff := databuff + curlen;
					restlen := restlen - curlen;
			
					IF restlen = 0 THEN
						BuildTDControlStatus(td, status); 
						EXIT;
					END;
			END;
		
			lasttd := td;
		
			IF pid = PidOut THEN
				req.device.dataToggleOut[req.endpoint MOD 16] := datatoggle;
			ELSE
				req.device.dataToggleIn[req.endpoint MOD 16] := datatoggle;
			END;
		
			(* Build qh *)
			BuildTD(qh, 1, firsttd, firsttd, lasttd);
			
			req.status := AosUsbHcdi.ResInProgress;
		
			IF req.timeout # 0 THEN
				DoSchedule(req, qh);
				FreeLiveQHChain(qh); 
				req.conSpec := NIL;
			ELSE
				IF Debug THEN AosOut.String("AosUsbUhci: starting nonblocking bulk transfer"); AosOut.Ln; END;		
				NEW(spec); spec.qh := qh; req.conSpec := spec;
				spec.queue := InsertQH(req, qh);
			END;
		
			RETURN req.status;
		END ScheduleBulk;
		
		(** Add an interrupt handler. The handler is called, when a IOC interrupt occurs and the req.status field is changed *)
		PROCEDURE AddIntHandler*(req: AosUsbHcdi.UsbTReq);
		VAR
			temp, handler: AosUsbHcdi.UsbTReq;
		BEGIN {EXCLUSIVE}
			ASSERT((req#NIL) & (req.intHandler#NIL));
			
			IF intHandlers=NIL THEN
				intHandlers:=req;	
			ELSIF intHandlers = req THEN (* handler already installed *) 
					AosOut.String("AosUsbUhci: warning: procedure was already registered as interrupt handler"); AosOut.Ln;
					RETURN; 
			ELSE
				 temp:=intHandlers;
				 WHILE(temp.next#NIL) & (temp.next#req) DO temp:=temp.next; END;
				 IF temp.next=NIL THEN temp.next:=req;  END;
			END;
		END AddIntHandler;
		
		(** Remove an interrupt handler *)
		PROCEDURE RemoveIntHandler*(req: AosUsbHcdi.UsbTReq);
		VAR
			temp : AosUsbHcdi.UsbTReq;	
		BEGIN {EXCLUSIVE} 
			ASSERT(req#NIL);
			
			IF intHandlers#NIL THEN 
				IF intHandlers=req THEN 
					intHandlers:=intHandlers.next; 
				ELSE
					temp:=intHandlers;
					WHILE(temp.next#NIL) & (temp.next#req) DO temp:=temp.next; END;
					IF temp.next#NIL THEN temp.next:=temp.next.next; END;
				END;
			END;
		END RemoveIntHandler;

		PROCEDURE InterruptHandler;
		VAR
			s, prevStatus : SET;
			temp : AosUsbHcdi.UsbTReq;
		BEGIN (* should be EXCLUSIVE *)
		
			IF active THEN (* controller is active -> handle interrupts *)
				INC(interruptCounter);
				SYSTEM.PORTIN(iobase + UsbSts, SYSTEM.VAL(INTEGER, s));
				status:=s;
				
				IF s # {} THEN
					IF (s * StatusHChalted) # {} THEN AosOut.String("AosUsbUhci: Error: Host Controller halted"); AosOut.Ln; running := FALSE; END;
					IF (s * StatusProcessError) # {} THEN AosOut.String("AosUsbUhci: Host Controller process error"); AosOut.Ln; END;
					IF (s * StatusSystemError) # {} THEN AosOut.String("AosUsbUhci: Host system error"); AosOut.Ln; END;
					IF (s * StatusErrorInt) # {} THEN AosOut.String("AosUsbUhci: USB transaction failed"); AosOut.Ln; END; 
					
					IF (s * StatusInt) # {} THEN (* USB Interrupt occured: can be IOC or ShortPacketInt *)
					
						(* call installed interrupt handlers *)
						temp:=intHandlers;
						WHILE (temp#NIL) DO 
							ProbeTransfer(temp);
							IF temp.active & (temp.status*AosUsbHcdi.ResInProgress = {}) THEN temp.active := FALSE; temp.intHandler; END;
  						  temp:=temp.next; 
						END; 		
					END;	
					(* reset the USB status register *)
					SYSTEM.PORTOUT(iobase + UsbSts, SYSTEM.VAL(INTEGER, s));
				END;
		
			END;
		END InterruptHandler;

		(* the host controller writes the number of actually transfered bytes into the ActLen field of each executed TD.
			The GetTransferredLen procedure builds the sum of all TD.ActLen fields of all executed TD's in the queue <qh> and then
			writes this value into the req.bufferLen field *)
		PROCEDURE GetTransferredLen(req : AosUsbHcdi.UsbTReq; qh : LONGINT);
		VAR
			td, addr, actlen, thislen, val : LONGINT;
			s : SET;
		BEGIN
			actlen := 0;
		
			SYSTEM.GET(qh + 8, SYSTEM.VAL(LONGINT, td)); (* get first element of queue *)
		
			LOOP
				IF (SYSTEM.VAL(SET, td) * {0}) # {} THEN (* TD link pointer not valid (last TD was the last TD in queue) *) EXIT; END;
				addr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, td) * {4..31}); (* addr := physical addr of td *)
		
				SYSTEM.GET(addr+4, SYSTEM.VAL(LONGINT, val)); (* get 4 bytes - td control and status *)
				s := SYSTEM.VAL(SET, val);
		
				IF (s * TDActive) # {} THEN (* this TD has not yet been executed *) EXIT; END;
		
				thislen := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {0..10}); (* access the ActLen field of the TD *)
				IF thislen = 7FFH THEN thislen := 0; ELSE thislen := thislen +1; END;
				SYSTEM.GET(addr+8, SYSTEM.VAL(LONGINT, val)); (* get 4 bytes - td token*)
				IF SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {0..7}) # PidSetup THEN actlen := actlen + thislen; END;
		
				IF (s * (TDCrcTimeout + TDDataBuffer + TDStalled + TDBitStuff + TDBabble + TDNak)) # {} THEN EXIT END;
				SYSTEM.GET(addr, SYSTEM.VAL(LONGINT, td)); (* td := link pointer of td at addr *)
			END;
			req.bufferLen := actlen;
		END GetTransferredLen;

		PROCEDURE GetQueueStatus(req : AosUsbHcdi.UsbTReq; qh : LONGINT) : SET;
		VAR
			val, td, addr, actlen, maxlen, pid : LONGINT;
			status, s : SET; datatoggle : BOOLEAN;
			last : BOOLEAN;
		BEGIN
			(* be aware of the fact the the USB host controller is concurrently accessing AND modifying this datastructure !! *)

			(* test if the queue was finished *)
			SYSTEM.GET(qh+4, SYSTEM.VAL(LONGINT, td)); (* get queue head element link pointer *)
	
			IF td = 1 THEN (* yes, fetch status of last td in queue (queue head element link pointer is not valid) *)
				SYSTEM.GET(qh + 12, SYSTEM.VAL(LONGINT, td)); last := TRUE;
			ELSE
				td := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, td) * {4..31});
			END;
	
			addr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, td) * {4..31}); (* addr := physical addr of td *)
	
			SYSTEM.GET(addr+4, SYSTEM.VAL(LONGINT, val)); (* get 4 bytes - TD control and status *)
			s := SYSTEM.VAL(SET, val);
			(* the USB host controller could already have changed the status of the TD at this time *)	
		
			status := {}; 
	
			(* NAK occured? Set it, it is not an error - we can still be in progress *)
			IF (s * TDNak) # {} THEN status := status + AosUsbHcdi.ResNAK END;
			
			IF (s * TDActive) # {} THEN RETURN status + AosUsbHcdi.ResInProgress; END;
	
			SYSTEM.GET(addr+8, SYSTEM.VAL(LONGINT, val)); (* get 4 bytes - td token*)
			maxlen := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, ASH(val, -21) + 1) * {0..10});
			pid := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {0..7});
			IF (SYSTEM.VAL(SET, val) * TDDataToggle) # {} THEN datatoggle := TRUE ELSE datatoggle := FALSE END;
	
			IF (s * (TDCrcTimeout + TDDataBuffer + TDStalled + TDBitStuff + TDBabble)) # {} THEN (* marginal speed up *)
				IF (s * TDCrcTimeout) # {} THEN status := status + AosUsbHcdi.ResCRCTimeout END;
				IF (s * TDDataBuffer) # {} THEN status := status + AosUsbHcdi.ResDataBuffer END;
				IF (s * TDStalled) # {} THEN status := status + AosUsbHcdi.ResStalled END;
				IF (s * TDBitStuff) # {} THEN status := status + AosUsbHcdi.ResBitStuff END;
				IF (s * TDBabble) # {} THEN status := status + AosUsbHcdi.ResBabble END;
			END;
			
			IF ~last & (status={}) THEN RETURN AosUsbHcdi.ResInProgress; END;
			
			(* Test for errors *)
			actlen := req.bufferLen; GetTransferredLen(req, qh); 
			
			IF req.bufferLen < actlen THEN status := status + AosUsbHcdi.ResShortPacket END;

			IF status = {} THEN status := AosUsbHcdi.ResOK; END;
			
			bytesTransfered := bytesTransfered + actlen; (* for performance monitoring *)
	
			IF (req.typ = AosUsbHcdi.TransferBulk) OR (req.typ = AosUsbHcdi.TransferInterrupt) THEN
	
				(* if we receive an ACK, do the toggle *)
				IF (status = AosUsbHcdi.ResOK) OR (status = AosUsbHcdi.ResShortPacket) THEN
					datatoggle := ~datatoggle;
				END;
	
				(* write the toggle back *)
				IF pid = PidOut THEN
					req.device.dataToggleOut[req.endpoint MOD 16] := datatoggle;
				ELSIF pid = PidIn THEN
					req.device.dataToggleIn[req.endpoint MOD 16] := datatoggle;
				ELSE
					AosOut.String("AosUsbUhci:GetQueueStatus: pid error"); AosOut.Ln;
					HALT(303);
				END;
			END;
			RETURN status;
		END GetQueueStatus;
		
		(* UHCI Transfer Descriptor (TD) Format          
                                                                              
			Offset:         Value:                                                                                                                    
			
			00			  Link Pointer[31:4]                                                                                                   
			04  		    Flags - Status - Actlen                                                                                           
			08 			 MaxLen - D Toggle - EndPt - Device Address - PID                                             
			12 			 Buffer Pointer                                                                                                         
																																					
			For more details see Intel UHCI Design Guide v1.1, p. 20-25      
			
		    UHCI queue head format                                                                                                   
		
			  Offset:	  Value:                                                                                                                
		  	 00  	 	Queue Head Link Pointer                                                                                                 
			   04  	 	Queue Element Link Pointer                                                                                            
			   08   		[Oberon specific]  Original Queue Element Link Pointer  (= first TD in queue)              
			   12   		[Oberon specific]  Pointer to last TD in queue                                                                 
		*)

		(* builds a TD. Is also used to build queue heads *)
		PROCEDURE BuildTD(td, f1, f2, f3, f4 : LONGINT);
		BEGIN
			SYSTEM.PUT(td, SYSTEM.VAL(LONGINT, f1));         (* TD link pointer field*)
			SYSTEM.PUT(td+4, SYSTEM.VAL(LONGINT, f2));    (* TDcontrol & status field*)
			SYSTEM.PUT(td+8, SYSTEM.VAL(LONGINT, f3));    (* TD token field *)
			SYSTEM.PUT(td+12, SYSTEM.VAL(LONGINT, f4));  (* TD buffer pointer field *)
		END BuildTD;

		PROCEDURE BuildTDLinkPointer (VAR td:LONGINT; flags : SET; LinkPointer : LONGINT);
		BEGIN
			ASSERT( SYSTEM.VAL( SET, LinkPointer) * {0..3} = {} );
			SYSTEM.PUT(td, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LinkPointer) + flags));
		END BuildTDLinkPointer;

		PROCEDURE BuildTDControlStatus (VAR td:LONGINT; status : SET);
		BEGIN
			status := status + {0..10};
			SYSTEM.PUT(td+4, SYSTEM.VAL(LONGINT, status));
		END BuildTDControlStatus;

		PROCEDURE BuildTDToken (VAR td:LONGINT; PID, DeviceAddress, EndPoint : LONGINT; DataToggle : BOOLEAN; maxLength : LONGINT);
		VAR
			s : SET;
		BEGIN
			(* maxLength specifies the maximum number of data bytes allowed for the transfer,
				allowed values: 0x000-0x4FF (1-1280 bytes) and 0x7FF (0 bytes)   *)
			ASSERT(((maxLength>=0000H) & (maxLength<=04FFH)) OR (maxLength=07FFH));
			
			IF maxLength = 0 THEN maxLength := 07FFH;       (* 0 bytes = Null Data packet *)
								ELSE maxLength := maxLength - 1;  (* maxLength==0 -> 1 Byte *)
								END;
			s := {};
			IF DataToggle THEN s := s + TDDataToggle END;
			SYSTEM.PUT(td + 8, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET,
			PID + ASH(DeviceAddress, 8) + ASH(EndPoint, 15) + ASH(maxLength, 21)) + s));
		END BuildTDToken;
		
		(* Initializes the host controller and builds up the basics of the UHCI data structures *)
		PROCEDURE Init(base: LONGINT; IRQ : INTEGER) : BOOLEAN;
			VAR
			i, k, j : LONGINT;
		BEGIN
			iobase:=base;
			irq := IRQ;

			(* configure the ports;  no more documented in the specs, but 3-4 possible *)
			portCount := 2; 
			NEW(ports, portCount);

			(* calculate offset from iobase of the port status/controll register for each port *)
			FOR i := 0 TO portCount - 1 DO
				ports[ i ] := iobase + PortSc1 + i*2;
			END;
	
			NEW(timer);
			NEW(framelist); NEW(tdlist);             
	
			(* setup the free td list, a little bit of own memory managment, since we don't like memory fragmentation *)
			tdlist.tdlistbase := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.ADR(tdlist.field[0]) + 15) * {4..31});  (* TD's have to be 16-byte aligned *)
		
			FOR i:=0 TO MaxTDPerController - 1 DO
				tdlist.freelist[ i ] := tdlist.tdlistbase + i*16
			END;
	
			tdlist.first := 0;
			tdlist.last := MaxTDPerController - 1;
	
			FOR i := 0 TO MaxGCEntries - 1 DO
				gcQueueList[i] := 1; (* 1 = no entry *)
			END;
	
			(* calculate the address of the 4K boundary contained in the 8K buffe (framelist base address has to be 4KB aligned) *)
			framelist.framelistbase := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.ADR(framelist.field[0]) + 1024*4 - 1) * {12..31});
	
			(* calculate the index which points to the element positioned at the 4K boundary *)
			framelist.index := ( framelist.framelistbase - SYSTEM.ADR(framelist.field[0]) ) DIV 4;
		
			(* set up the frame list pointer skeleton *)
			controlTD := AllocTD();             
			bulkTD := AllocTD();
			isochronousTD := AllocTD();
	
			IF (controlTD = -1) OR (bulkTD = -1) OR (isochronousTD = -1) THEN (* ERROR: Couldn't allocate a free TD. This really should not happen. *) 
				AosOut.String("AosUsbUhci: couldn't allocate TD when initializing host controller"); AosOut.Ln; RETURN FALSE;
			END;
	
			FOR i := 0 TO 10 DO
				interruptTD[i] := AllocTD();     
				IF interruptTD[i] = -1 THEN (* ERROR: Couldn't allocate a free TD. This really should not happen. *) 
					AosOut.String("AosUsbUhci: couldn't allocate TD when initializing host controller"); AosOut.Ln; RETURN FALSE; 
				END;
			END;
	
			(* build queue heads for bulk-, control- and interupt transfers *)
			BuildTD(bulkTD, 1, 1, 0, 0);
			BuildTD(controlTD, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, bulkTD) + {1} ), 1, 0, 0);
			BuildTD(interruptTD[0], SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, controlTD) + {1} ), 1, 0, 0);
	
			FOR i:=1 TO 10 DO
				BuildTD(interruptTD[i], SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, interruptTD[i-1]) + {1} ), 1, 0, 0);
			END;
			(* => end of queue 10 points to 9, end of 8 points to 7 , ..., end of 1 points to 0 *)
			(* => if we start at queue 10, then we will pass all others too; if we start at 9 then we will pass all queues < 9, too etc.*)
			
			(* queue 0 executes 1024x, queue 1 executes 512x, queue 2 executes 256x,  queue 3 executes 128x*)
			(* queue 4 executes 64x, queue 5 executes 32x, queue 6 executes 16x,  queue 7 executes 8x*)
			(* queue 8 executes 4x, queue 9 executes 2x, queue 10 executes 1x *)
	
			(* What does the following mean? => We count the 1's (starting at lsb) until we pass a zero *)
			(* This count gives the queue number for a given slot *)
	
			FOR i := 0 TO 1023 DO (* i is slot number, we want to calc the queue number (k) for this slot *)
				k := 0; j := i;
				LOOP
					IF (SYSTEM.VAL(SET, j) * {0}) = {} THEN EXIT; END;
					INC(k); j := j DIV 2;
				END;
				framelist.field[framelist.index + i] := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, interruptTD[k]) + {1} );
			END;
	
			status := {};
			running := FALSE;
	
			Reset; (* Reset the host controller *)
	
			(* try to start the host controller *)
			IF Start() = FALSE THEN (* ERROR: Couldn't start the host controller. Controller was probably not correctly initialized. *)
				Reset; AosOut.String("AosUsbUhci: Couldn't start controller."); AosOut.Ln; RETURN FALSE; 
			END; 
	
			active := TRUE;	
			AosActive.InstallHandler(InterruptHandler, AosInterrupts.IRQ0+irq);
	
			RETURN TRUE;
		END Init;

		(** The Host Controller sends the global reset signal on the USB and then resets all its logic, including the internal 
		 hub registers. The hub registers are reset to their power on state. *)
		PROCEDURE Reset;
		BEGIN {EXCLUSIVE}
			(* do a global reset for 50ms, disconnect all devices *)
			SYSTEM.PORTOUT(iobase + UsbCmd, SYSTEM.VAL(INTEGER, CmdGlobalReset) ); Wait (50);
			SYSTEM.PORTOUT(iobase + UsbCmd, SYSTEM.VAL(INTEGER, 0) ); Wait (10);
		END Reset;
		
		PROCEDURE Wait(ms : LONGINT);
			(* wait is not reentrant !!! *)
		BEGIN
			timer.Sleep(ms)
		END Wait;								

		(* Resets and then starts the host controller. As soon as the host controller is started, it processes the schedule *)
		PROCEDURE Start():BOOLEAN;
		VAR
			t : LONGINT;
			s : SET;
		BEGIN
			(* do a Host Controller reset *)
			SYSTEM.PORTOUT(iobase + UsbCmd, SYSTEM.VAL(INTEGER, CmdHostControllerReset) );

			(* the Host Controller will clear the CmdHostControllerReset Bit after about 64 bit times *)
			t := 10000;
			REPEAT
				SYSTEM.PORTIN(iobase + UsbCmd, SYSTEM.VAL(INTEGER, s) );
				DEC( t );
			UNTIL ((t = 0) OR (  ~ ( 1 IN s)));

			IF t = 0 THEN (* ERROR: Host Controller should have cleared the Bit !! *) RETURN FALSE END;  

			(* enable all interrupts, but remember: perhaps they are not being routed by the PIIX4 *)
			SYSTEM.PORTOUT(iobase + UsbIntr, SYSTEM.VAL(INTEGER, IntShortPacket + IntIOC + IntResume + IntTimeoutCRC) );

			(* we start at frame 0 and also set the framelistbase address *)
			SYSTEM.PORTOUT(iobase + FrNum, SYSTEM.VAL(INTEGER, 0) ); (* 16 bit! *)
			SYSTEM.PORTOUT(iobase + FlBaseAdr, SYSTEM.VAL(LONGINT, framelist.framelistbase));

			(* start the controller, set max-packet size (64byte) and set the pseudo-semaphore which we don't need *)
			SYSTEM.PORTOUT(iobase + UsbCmd, SYSTEM.VAL(INTEGER, CmdRunStop + CmdConfigureFlag + CmdMaxPacket) );
			
			running := TRUE;
			RETURN TRUE;
		END Start;
		
		(* for debugging: display diagnostics of this host controller to KernelLog *)
		PROCEDURE Diag;  
		VAR
			s: SET;
			framenum : LONGINT;
			i : INTEGER;
		BEGIN
			SYSTEM.PORTIN (iobase + FrNum, SYSTEM.VAL(INTEGER, framenum));
			framenum := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, framenum) * {0..10});
			
			AosOut.String("Diagnostics of ");
			AosOut.String(name); AosOut.String(" ("); AosOut.String(desc); AosOut.String(")"); AosOut.Ln;

			SYSTEM.PORTIN (iobase + UsbSts, SYSTEM.VAL(INTEGER, s));
			AosOut.String ("    base 0"); PrintHex(iobase); AosOut.String("H, Irq ");
			AosOut.Int (irq, 0); AosOut.String(", frame 0"); PrintHex(framenum); AosOut.String("H, Int Counter:");
			AosOut.Int(interruptCounter,0);AosOut.Ln;

			s := status;
			AosOut.String("    LastStatus:");
			IF (s # {}) THEN
				IF (s * StatusHChalted) # {} THEN AosOut.String (" [HChalted]"); END;
				IF (s * StatusProcessError) # {} THEN AosOut.String (" [Process Error]"); END;
				IF (s * StatusSystemError) # {} THEN AosOut.String (" [System Error]"); END;
				IF (s * StatusResumeDetect) # {} THEN AosOut.String (" [Resume Detect]"); END;
				IF (s * StatusErrorInt) # {} THEN AosOut.String (" [ErrorInt]"); END;
				IF (s * StatusInt) # {} THEN AosOut.String (" [Int]"); END;
				AosOut.Ln;
			ELSE
				AosOut.String(" [ok]"); AosOut.Ln;
			END;
			
			AosOut.String ("    IRQ enable status:");
			SYSTEM.PORTIN (iobase + UsbIntr, SYSTEM.VAL(INTEGER, s));
			IF (s * IntShortPacket) # {} THEN AosOut.String(" [Short Packet]"); END;
			IF (s * IntIOC) # {} THEN AosOut.String (" [IOC]"); END;
			IF (s * IntResume) # {} THEN AosOut.String (" [Resume]"); END;
			IF (s * IntTimeoutCRC) # {} THEN AosOut.String (" [Timeout/CRC]"); END;
			AosOut.Ln;

			(* List status of all ports of the root hub *)
			FOR i:=0 TO portCount -1 DO
				SYSTEM.PORTIN (iobase + PortSc1 + i*2, SYSTEM.VAL(INTEGER, s));
				AosOut.String ("    Port "); AosOut.Int(i+1, 0); AosOut.String(" status:");
				IF (s * PortEnabled) # {} THEN AosOut.String(" [enabled]"); ELSE AosOut.String(" [disabled]"); END;
				IF (s * PortSuspend) # {} THEN AosOut.String (" [suspended]"); END;
				IF (s * PortLowSpeed) # {} THEN AosOut.String (" [lowspeed]"); END;
				IF (s * PortCurrentConnectStatus) # {} THEN AosOut.String (" [device present]"); END;
				AosOut.Ln;
			END;
		END Diag;
		
		(* debug: gives you an idea of about how many TD's are free. Isn't exact. *)
		PROCEDURE MemUsage;
		VAR
			i : LONGINT;
			first, last : LONGINT;
			nbrOfFreeTDs : LONGINT;
		BEGIN
			first := tdlist.first; last := tdlist.last;
			IF first>last THEN 
				nbrOfFreeTDs := (first - last) DIV 2; (* TD has 2 byte size *)
			ELSE
				nbrOfFreeTDs := (last - first) DIV 2; 
			END;
			AosOut.String("TD allocation statistics of "); AosOut.String(name); AosOut.String("("); AosOut.String(desc); AosOut.String(")"); AosOut.Ln;
			AosOut.String("   Maximum number of TD's: "); AosOut.Int(MaxTDPerController,0); 
			AosOut.String("("); AosOut.Int((MaxTDPerController*16) DIV (1024*1024), 0); AosOut.String(" MBytes)"); AosOut.Ln;
			AosOut.String("   TD's in freelist: "); AosOut.Int(nbrOfFreeTDs,0);
			AosOut.String("("); AosOut.Int((nbrOfFreeTDs*16) DIV (1024*1024), 0); AosOut.String(" Mbytes)"); AosOut.Ln;
		END MemUsage;
	END UhciController;

VAR
	controllerCount : LONGINT;  (* used for naming the host controllers *)
	
(* debug: displays the information in the queue head qh and all TD's in that queue 
	the queue is traversed only horizontally *)
PROCEDURE HumanQH(qh : LONGINT);
VAR
	val,addr : LONGINT;
	s : SET;
BEGIN
	AosOut.String("QH at address: "); PrintHex(qh); AosOut.Ln;
	
	(* first show the information of the Queue Head Link pointer (QHLP) *)
	SYSTEM.GET(qh, SYSTEM.VAL(LONGINT, val));
	s:=SYSTEM.VAL(SET,val);
	
	AosOut.String("   QH link pointer: "); 
	IF (s * TDQHSelect) # {} THEN AosOut.String(" [QH]"); ELSE AosOut.String(" [TD]"); END;
	IF (s * TDTerminate) # {} THEN AosOut.String(" [Terminate]"); END;
	
	val:=SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {4..31});
	addr := val; (* addr := queue head link pointer *)

	AosOut.String("[PTR val: "); PrintHex(val); AosOut.String("]");
	AosOut.Ln;
	
	(* second show the information of the Queue Element Link Pointer (QELP) *)
	SYSTEM.GET(qh+4, SYSTEM.VAL(LONGINT, val));
	s:=SYSTEM.VAL(SET,val);
	
	AosOut.String("   QH Element Link Pointer: ");
	IF (s * TDQHSelect) # {} THEN AosOut.String(" [QH]"); ELSE AosOut.String(" [TD]"); END;
	IF (s * TDTerminate) # {} THEN AosOut.String(" [Terminate]"); END;
	
	val:=SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {4..31});
	
	AosOut.String("[PTR val: "); PrintHex(val); AosOut.String("]");
	AosOut.Ln;

	(* third show the queued TDs in this queue *)
	IF (s * TDTerminate) = {} THEN (* there are some queued TDs or QHs - show them *)

		IF (s * TDQHSelect) # {} THEN (* is a Queue Head *)
			HumanQH(val);
		ELSE (* it's a TD *)
			HumanTD(val); 
		END;
		
	END;
	
	IF addr#0 THEN (* there are other queue heads in the queue *)
		AosOut.String("next queue head in queue:"); AosOut.Ln; AosOut.Ln;
		HumanQH(addr);
	END;

END HumanQH;

(* debug: displays the information in the TD nexttd and displays it *)
PROCEDURE HumanTD(nexttd: LONGINT);
VAR
	addr, val : LONGINT;
	s : SET;
BEGIN
	LOOP
		addr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, nexttd) * {4..31});
		
		AosOut.String("TD at address: "); PrintHex(addr); AosOut.Ln;

		SYSTEM.GET(addr, SYSTEM.VAL(LONGINT, val));
		s := SYSTEM.VAL(SET, val);	
		AosOut.String("   LInkPTR:");
		IF (s * TDDepthFirst) # {} THEN AosOut.String(" [Depthfirst]"); END;
		IF (s * TDQHSelect) # {} THEN AosOut.String(" [QH]"); ELSE AosOut.String(" [TD]"); END;
		IF (s * TDTerminate) # {} THEN AosOut.String(" [Terminate]"); END;
		AosOut.String(" [PTR Val: "); PrintHex((val DIV 16) * 16 ); AosOut.String(" ]");
		AosOut.Ln;

		SYSTEM.GET(addr+4, SYSTEM.VAL(LONGINT, val));
		s := SYSTEM.VAL(SET, val);	
		AosOut.String("   ControlStatus:");
		IF (s * TDActive) # {} THEN AosOut.String(" [Active]"); END;
		IF (s * TDIOC) # {} THEN AosOut.String(" [IOC]"); END;
		IF (s * TDIOS) # {} THEN AosOut.String(" [IOS]"); END;
		IF (s * TDLS) # {} THEN AosOut.String(" [LowSpeed]"); END;
		IF (s * TDERR1) # {} THEN AosOut.String(" [Err1]"); END;
		IF (s * TDERR2) # {} THEN AosOut.String(" [Err2]"); END;
		IF (s * TDSPD) # {} THEN AosOut.String(" [SPD]"); END;
		IF (s * TDCrcTimeout) # {} THEN AosOut.String(" [CRC/Timeout]"); END;
		IF (s * TDNak) # {} THEN AosOut.String(" [NAK]"); END;
		IF (s * TDDataBuffer) # {} THEN AosOut.String(" [DataBuffer]"); END;
		IF (s * TDStalled) # {} THEN AosOut.String(" [Stalled]"); END;
		IF (s * TDBitStuff) # {} THEN AosOut.String(" [BitStuff]"); END;
		IF (s * TDBabble) # {} THEN AosOut.String(" [Babble]"); END;
		AosOut.String (" [Actlen: ");
		val := SYSTEM.VAL(LONGINT, s * {0..10});
		IF val = 07FFH THEN val := 0; ELSE INC(val); END;
		AosOut.Int(val, 0); AosOut.String(" ]"); 
		AosOut.String(" [MaxLen: ");
		SYSTEM.GET(addr+8, SYSTEM.VAL(LONGINT,val));
		val := SYSTEM.LSH(val, -21); IF val = 7FFH THEN val := 0; ELSE INC(val); END;
		AosOut.Int(val, 0);
		AosOut.String(" ]"); AosOut.Ln;
		AosOut.String("   PID: "); 
		SYSTEM.GET(addr+8, SYSTEM.VAL(LONGINT,val)); val := val MOD 256;
		CASE val OF
			PidOut : AosOut.String("OUT");
			| PidIn : AosOut.String("IN");
			| PidSetup : AosOut.String("SETUP");
		ELSE
			AosOut.String("Unkown ("); PrintHex(val); AosOut.String("H)");
		END;
		AosOut.String(" DataToggle: "); 
		SYSTEM.GET(addr+8, SYSTEM.VAL(LONGINT,val)); 
		s := SYSTEM.VAL(SET,val);
		IF s*TDDataToggle # {} THEN AosOut.String("DATA1"); ELSE AosOut.String("DATA0"); END;
		AosOut.Ln;
		

		SYSTEM.GET(addr, SYSTEM.VAL(LONGINT, nexttd));
		IF (SYSTEM.VAL(SET, nexttd) * {0}) # {} THEN EXIT; END;
	END;
END HumanTD;

(* called when this module is unloaded *)
PROCEDURE Cleanup();
VAR
	i: LONGINT;
	controllers : AosPlugins.Table;
	controller : UhciController;
BEGIN
	(* reset all UHCI USB host controllers and remove them from the AosUsbHcdi.controllers registry *)
	AosUsbHcdi.controllers.GetAll(controllers);
	
	IF controllers#NIL THEN
		i:=0;
		WHILE i <= LEN(controllers^)-1 DO
			IF controllers[i].desc="UHCI USB host controller" THEN 
				controller:=controllers[i](UhciController);
				IF controller.active THEN AosActive.RemoveHandler(controller.InterruptHandler, AosInterrupts.IRQ0 + controller.irq);END;
				controller.Reset;
				AosUsbHcdi.controllers.Remove(controller);
			END;
			INC(i);
		END;
	END;		
	
END Cleanup;

(** Displays status of all registred UHCI USB host controllers (for debugging) *)
PROCEDURE Diag*;
VAR
	i : INTEGER;
	controllers : AosPlugins.Table;
BEGIN
	AosUsbHcdi.controllers.GetAll(controllers);

	IF controllers#NIL THEN
		i:=0;
		WHILE i <= LEN(controllers^)-1 DO
			IF controllers[i].desc="UHCI USB host controller" THEN 
				controllers[i](UhciController).Diag; 
			END;
			INC(i);
		END;
	END;		
END Diag;

PROCEDURE PrintHex(was: LONGINT);
VAR z,d,h,i:LONGINT;
BEGIN
	z := 0;
	d := 16*16*16*16*16*16*16; (* what a quick hack, hopefully the compiler is intelligent enough *)
	FOR i:=0 TO 7 DO
		h := (was DIV d) MOD 16;
		IF (z = 1) OR (h # 0) OR (i = 7) THEN
			z := 1;
			IF h < 10 THEN AosOut.Int(h,0); ELSE AosOut.Char(CHR(ORD("A")+h-10)); END;
		END;
		d:=d DIV 16;
	END;
END PrintHex;
	
(* Find UHCI controllers on the PCI bus, create correspondig UCHIcontroller object and register them in the UHCI USB host controllers registry; 
	called by FindControllers *)
PROCEDURE PCIFindUhci(id, vendor: LONGINT);
VAR 
	index, bus, dev, fkt, iobase, IrqRouting, res: LONGINT;
	hostController : UhciController;
	name : AosPlugins.Name;

	PROCEDURE ReadDWord(adr: LONGINT;  VAR s: LONGINT);
	VAR res: LONGINT;
	BEGIN
		res := PCI.ReadConfigDword(bus, dev, fkt, adr, s);
		IF res # PCI.Done THEN s := 0 END
	END ReadDWord;

	PROCEDURE ReadByte(adr: LONGINT;  VAR s: LONGINT);
	VAR res: LONGINT;
	BEGIN
		res := PCI.ReadConfigByte(bus, dev, fkt, adr, s);
		IF res # PCI.Done THEN s := 0 END
	END ReadByte;

	PROCEDURE WriteWord(adr: LONGINT;  s: LONGINT);
	VAR res: LONGINT;
	BEGIN
		res := PCI.WriteConfigWord(bus, dev, fkt, adr, s);
		(* ignore res *)
	END WriteWord;

BEGIN

	index := 0;

	WHILE (PCI.FindPCIDevice(id, vendor, index, bus, dev, fkt) = PCI.Done) DO 
	
		ReadByte(3CH, IrqRouting); (* Register set by PCI Bios *)

		ReadDWord(20H, iobase);
		iobase := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, iobase) * {1..31});

   	 IF (IrqRouting = 0) THEN
			AosOut.String("AosUsbUhci: Please enable USB-IRQ in BIOS for UHCI Controller at base 0");
			PrintHex(iobase); AosOut.Char("H"); AosOut.Ln;
		ELSE
			WriteWord(0C0H, 2000H); (* disable legacy emulation *)
			
			NEW(hostController);
			
			IF hostController.Init(iobase,SHORT(IrqRouting)) THEN (* host controller has been initialized and started successfully *)
			
				AosOut.String("AosUhci: Initialised USB UHCI controller at base 0"); PrintHex(iobase); 
				AosOut.String("H, Irq: "); AosOut.Int(IrqRouting, 0); AosOut.Ln;
				
			   name:="USB";  
			   name[3]:=CHR(controllerCount+48);
			   name[4]:=0X;
			   
   			hostController.SetName(name);
   			hostController.desc:="UHCI USB host controller";
				
				(* register the controller as AosPlugin *)
				AosUsbHcdi.controllers.Add(hostController, res); 
				IF (res#0) THEN (* ERROR: registering the host controller failed, should not happen *) hostController:=NIL; END; 
				
				INC(controllerCount);
				
			ELSE (* ERROR: host controller initialization failed *)
				hostController:=NIL;
				AosOut.String("AosUhci: ERROR: Cannot init USB UHCI controller at base 0"); PrintHex(iobase); 
				AosOut.String("H, Irq: "); AosOut.Int(IrqRouting, 0); AosOut.Ln;
			END;
		END; 
				
		INC(index);
	END;
END PCIFindUhci;

(* Find Intel UHCI compatible controllers and register them. *)
PROCEDURE FindControllers;
BEGIN
	 (* FindControllers should only be called at module loading time *) 
	 IF controllerCount # 0 THEN RETURN END;
	 	 
	PCIFindUhci(7020H, 8086H); (* Intel PIIX3 *)
	PCIFindUhci(7112H, 8086H); (* Intel PIIX4 + PIIX4E *)
	PCIFindUhci(2412H, 8086H); (* Intel 82801 AA *)
	PCIFindUhci(2422H, 8086H); (* Intel 82901 AB *)
	PCIFindUhci(2442H, 8086H); (* seems compatible *)
	PCIFindUhci(2444H, 8086H); (* seems compatible *)
	PCIFindUhci(2482H, 8086H); (* seems compatible *)
	PCIFindUhci(2484H, 8086H); (* seems compatible *)
	PCIFindUhci(2487H, 8086H); (* seems compatible *)
	PCIFindUhci(3038H, 1106H); (* seems compatible *)
	PCIFindUhci(24C2H, 8086H); (* seems compatible *)
	PCIFindUhci(719AH, 8086H); (* 82440MX *)
	PCIFindUhci(24D2H, 8086H); (* unsure *)
	PCIFindUhci(24D4H, 8086H); (* unsure *)
	PCIFindUhci(24D7H, 8086H); (* unsure *)
	PCIFindUhci(24DEH, 8086H); (* unsure *)
END FindControllers;

PROCEDURE Init*(ptr : PTR): PTR;
BEGIN
	(* do nothing *)
	RETURN NIL;
END Init;

BEGIN
	
	controllerCount:=0;

	AosModules.InstallTermHandler(Cleanup); 
 
	(* find, init and start all compatible UHCI USB host controllers and register them in the AosUsbHcdi.controllers registry *)
	FindControllers; 
	
END AosUsbUhci.

(* Init: AosUsbUhci.Init  Diagnostics: AosUsbUhci.Diag *)
AosUsb.Init AosUsb.Info


