MODULE AosUsbUhci; (** AUTHOR "cplattner/staubesv"; PURPOSE "USB Universal Host Controller Driver" *)
(**
 *	Bluebottle UHCI USB Host Controller Driver
 *	Implements the AosUsbHcdi host controller driver interface (HCDI)
 *
 *	IMPORTANT NOTE: 
 *	The UHCI specification doesn't specify how to determine the number of downstream port of the root hub. The driver simply
 *	assumes that you have two of these ports. 
 *	In the case you're HC implementation provides more port, you have to adapt the NumberOfPorts constant.
 *
 * Usage:
 *	
 *	AosUsbUhci.Install ~ to load this device driver
 *	S.Free AosUsbUhci ~ unloads it
 *
 * References: 
 *	Universal Host Controller Interface (UHCI) Design Guide, Revision 1.1, http://www.intel.com
 *
 * History:
 *
 *	30.09.2000 	First release (cp)
 *	18.10.2000 	Bugfixes, added new debug support (cp)
 *	20.10.2000 	Memory fragmentation fixed (cp)
 *	22.10.2000 	TD allocation changed, IRQ spread fixed, irq-out bugfix (cp)
 *	10.11.2003 	Introduction of host controller driver interface (HCDI), OOP, new per pipe memory allocation (staubesv)
 * 	20.11.2005 	PCIFindUhci changed to recognize UHCI HC's by their PCI class code, replaced SYSTEM.PUT/GET by SYSTEM.PUTxx/GETxx (staubesv)
 *	13.12.2005	Fixed UhciController.RestartPipe for ShortPacket conditions (staubesv)
 *	15.12.2005	Moved buffer checks to AosUsbHcdi.Mod (staubesv)
 *	05.01.2006	Abort tranfer when number of TDs is too small instead of trapping (staubesv)
 *	03.01.2006	Improved UnLinkTDs & RemoveQH (staubesv)
 *	08.03.2006	Added check in LinkTDs (staubesv)
 *	20.06.2006	Wait until HC has enabled port after setting the PortEnabled bit in procedure ResetPort (staubesv)
 *	28.06.2006 	Use AosOut.Hex instead of AosUsbHcdi.PrintHex (staubesv)
 *	03.07.2006	ResetAndEnablePort instead of two separate procedures (staubesv)
 *	03.08.2006	Adapted to AosUsbHcdi (LinkTDsAllowed) (staubesv)
 *	13.11.2006	UpdatePipeStatus: Set pipe.status to AosUsbdi.Stalled when a stall is detected (staubesv)
 *	05.01.2007	Added Interrupts tracing (staubesv)
 *
 * TODOs
 *	- recognize number of downstream ports automatically
 *	- isochronous transfers
 *	- suspend/resume
 *	- use aligned memory space provided by AosUsbHcdi instead of doing it self
 *)

IMPORT AosOut, AosMemory,  SYSTEM, PCI, AosKernel, AosActive, AosInterrupts, AosModules, AosUsbHcdi, AosUsbdi, Debug := AosUsbDebug;

CONST

	Description = "UHCI USB Host Controller";

	(* Number of ports the host controller's root hub provide *)
	NumberOfPorts = 2;
		
	(* Offsets of USB registers from base io-address according UHCI design guide *)
	UsbCmd = 0H;	(* command register*)
	UsbSts = 2H;  	(* status register*)
	UsbIntr = 4H;	(* interupt enable*)
	FrNum = 6H;	(* frame number *)
	FlBaseAdr = 8H;	(* frame list base address *)
	SofMod = 0CH;	(* start of frame modify *)
	PortSc1 = 10H;	(* port 1 status / control *)
	PortSc2 = 12H;	(* port 2 status / control *)

	(* Bits of the USB Command (UsbCmd) Register *)
	CmdMaxPacket = {7};
	CmdConfigureFlag = {6};
	CmdSoftwareDebug = {5};
	CmdForceGlobalResume = {4};
	CmdEnterGlobalSuspend = {3};
	CmdGlobalReset = {2};
	CmdHostControllerReset = {1};
	CmdRunStop = {0};
	
	(* Bits of the USB Status (UsbSts) Register *)
	StatusHChalted = {5};
	StatusProcessError = {4};
	StatusSystemError = {3};
	StatusResumeDetect = {2};
	StatusErrorInt = {1};
	StatusInt = {0};

	(* Bits of the USB Interrupt Enable (UsbIntr) Register *)
	IntShortPacket = {3};
	IntIOC = {2};
	IntResume = {1};
	IntTimeoutCRC = {0};

	(* Bits of the USB Port Status and Control (PortSc) Register *)
	PortSuspend = {12};
	PortReset = {9};
	PortLowSpeed = {8};
	PortResumeDetect = {6};
	PortLineStatus = {4,5};
	PortEnabledChange = {3};
	PortEnabled = {2};
	PortConnectStatusChange = {1};
	PortCurrentConnectStatus = {0};
	PortChangeMask = {1,3};
	
	(* Offsets of Queue Heads QH *)
	QhLinkPointer = 0;
	QhElementLinkPointer = 4;
	
	(* Fields of QhLinkPointer & QhElementLinkPointer *)
	QhTerminate = {0}; 
	QhTdSelect = {1};
	
	(* Offsets of 16byte transfer descriptors TDs *)
	TDLinkPointer = 0;
	TDControlStatus = 4;
	TDToken = 8;
	TDBufferPointer = 12;

	(* Bits of the TD Link Pointer DWORD*)
	TDTerminate = {0};
	TDQHSelect = {1};
	TDDepthFirst = {2};
						
	(* Bits of the TD Control and Status DWORD *)
	TDBitStuff = {17};
	TDCrcTimeout = {18};
	TDNak = {19};
	TDBabble = {20};
	TDDataBuffer = {21};
	TDStalled = {22};
	TDActive = {23};
	TDIOC = {24};
	TDIOS = {25};
	TDLS = {26};
	TDERR0 = {}; TDERR1 = {27}; TDERR2 = {28}; TDERR3 = {27,28};
	TDSPD = {29};
				
	(* Bits of the TD Token DWORD *)
	TDDataToggle = {19};

	(* TD Token Packet Identification (PID) field *)
	PidOut = 0E1H;
	PidIn = 069H;
	PidSetup = 02DH;
	
	(* 3: control-,bulk- and isochronousTD;  11: interruptTD[0..11];  1: alignment  *)
	TdListSize = 3 + 11 + 1;  
	
	(* How many Queue Heads should the debug procedure ShowSchedule() show; useful if the schedule data structure is corrupted *)
	ShowScheduleMaxQH = 25;
	
TYPE

	UhciFrameList = POINTER TO RECORD
		index : LONGINT;
		framelistbase : LONGINT;
		field : ARRAY 2*1024 OF LONGINT; (* hack: double it, so that we pass a 4K page boundary; field must be 4K aligned *)
	END;

	UhciController = OBJECT (AosUsbHcdi.Hcd)                         
	VAR
		(* Serial Bus Specification Release Number (for PCI config space)*)
		bcdUSB : LONGINT;
		
		(* UHCI data structures specific *)
		framelist : UhciFrameList;
		
		(* queue heads; only exported for debug purposes *)
		controlTD : LONGINT;
		bulkTD : LONGINT;
		isochronousTD : LONGINT;
		interruptTD : ARRAY 11 OF LONGINT;
		
		(* This array will provide the 16byte aligned TD's for controlTD, bulkTD, isochronousTD and interruptTD[] *)
		tdlist : POINTER TO ARRAY OF CHAR;
		tdlistbase : LONGINT; (* first 16byte aligned TD in tdlist *)
		
		(** Enable power for the specified port *)
		PROCEDURE EnablePortPower*(port : LONGINT);
		BEGIN
			(* Do nothing: Port power is always provided by UHCI host controllers *)
		END EnablePortPower;
		
		(** Disable power of the specified port *)
		PROCEDURE DisablePortPower*(port : LONGINT);
		BEGIN
			(* Do nothing: Port power is always provided by UHCI host controllers *)
		END DisablePortPower;
						
		(** Reset and enable the specified port *)
		PROCEDURE ResetAndEnablePort*(port : LONGINT) : BOOLEAN;
		VAR status : INTEGER; mtimer : AosKernel.MilliTimer;
		BEGIN
			(* reset port *)
			SYSTEM.PORTIN(ports[port], SYSTEM.VAL(INTEGER, status));
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, status) + PortReset - PortChangeMask)); 					
			Wait(AosUsbHcdi.PortResetTime); (* at least 10ms [USB2.0spec, 11.5.1.5 Resetting] *)
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, status) - PortReset - PortChangeMask));
			Wait(2); (* Nowhere specified, but doesn't work without *) 
			SYSTEM.PORTIN(ports[port], SYSTEM.VAL(INTEGER, status));
			IF SYSTEM.VAL(SET, status) * PortReset # {} THEN RETURN FALSE; END;		
			(* enable port *)
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, status) + PortEnabled - PortChangeMask));
			AosKernel.SetTimer(mtimer, AosUsbHcdi.PortEnableTimeout);
			REPEAT
				SYSTEM.PORTIN(ports[port], SYSTEM.VAL(INTEGER, status));
			UNTIL (SYSTEM.VAL(SET, status) * PortEnabled # {}) OR AosKernel.Expired(mtimer);
			
			(* The HC will set PortConnectStatusChange & PortEnabledChange, clear it *)
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, status) + PortChangeMask));
			
			RETURN SYSTEM.VAL(SET, status) * PortEnabled # {};
		END ResetAndEnablePort;

		(** Disables port number <port> on this root hub *)
		PROCEDURE DisablePort*(port : LONGINT);
		VAR status : INTEGER; mtimer : AosKernel.MilliTimer;
		BEGIN
			SYSTEM.PORTIN(ports[port], SYSTEM.VAL(INTEGER, status));
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, status) - PortEnabled - PortChangeMask));
			AosKernel.SetTimer(mtimer, AosUsbHcdi.PortEnableTimeout);
			REPEAT
				SYSTEM.PORTIN(ports[port], SYSTEM.VAL(INTEGER, status));
			UNTIL (SYSTEM.VAL(SET, status) * PortEnabled = {}) OR AosKernel.Expired(mtimer);
			
			(* The HC will set PortConnectStatusChange & PortEnabledChange, clear it *)
			SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, status) + PortChangeMask));
		END DisablePort;
		
		(** 
		 * Get the status of the port <port> of this root hub. 
		 * Registers which indicate changes are reset by GetPortStatus if ack = TRUE;
		 *)
		PROCEDURE GetPortStatus*(port : LONGINT; ack : BOOLEAN):SET;
		VAR status, s : SET;
		BEGIN
			SYSTEM.PORTIN(ports[port], SYSTEM.VAL(INTEGER, s));

			(* reset the PortEnabledChange and the PortConnectStatusChange bit *)
			IF ack & (s * PortChangeMask # {}) THEN SYSTEM.PORTOUT(ports[port], SYSTEM.VAL(INTEGER, s)); END;

			status := AosUsbHcdi.PortStatusPowered; (* UHCI root hub ports are always powered *)
			IF s * PortCurrentConnectStatus	# {} THEN status := status + AosUsbHcdi.PortStatusDevicePresent END;             
			IF s * PortConnectStatusChange 	# {} THEN status := status + AosUsbHcdi.PortStatusConnectChange; END;
			IF s * PortEnabled 				# {} THEN status := status + AosUsbHcdi.PortStatusEnabled END;
			IF s * PortEnabledChange 		# {} THEN status := status + AosUsbHcdi.PortStatusEnabledChange; END;
			IF s * PortReset					# {} THEN status := status + AosUsbHcdi.PortStatusReset; END;
			IF s * PortSuspend 				# {} THEN status := status + AosUsbHcdi.PortStatusSuspended; END;
			IF s * PortLowSpeed				# {} THEN 
				status := status + AosUsbHcdi.PortStatusLowSpeed;
			ELSE
				status := status + AosUsbHcdi.PortStatusFullSpeed;
			END;
			RETURN status;
		END GetPortStatus;

		(* Since UHCI host controllers do not support port change notification via interrupts, they must be polled *)
		PROCEDURE SetStatusChangeHandler*(handler : AosUsbHcdi.StatusChangeHandler) : BOOLEAN;
		BEGIN
			RETURN FALSE;
		END SetStatusChangeHandler;
		
		(** The Host Controller sends the global reset signal on the USB and then resets all its logic, including the internal 
		 hub registers. The hub registers are reset to their power on state. *)
		PROCEDURE Reset;
		BEGIN {EXCLUSIVE}
			(* do a global reset for 50ms, disconnect all devices *)
			SYSTEM.PORTOUT(iobase + UsbCmd, SYSTEM.VAL(INTEGER, CmdGlobalReset) ); Wait (50);
			SYSTEM.PORTOUT(iobase + UsbCmd, SYSTEM.VAL(INTEGER, 0) ); Wait (10);
		END Reset;

		(* Returns the current frame number; the frame number is incremented by the Host Controller at the end of each frame time;
		 * GetFrameNumber() is used for time stamps *)
		PROCEDURE GetFrameNumber*() : LONGINT;
		VAR frameNumber : INTEGER;
		BEGIN
			SYSTEM.PORTIN(iobase + FrNum, frameNumber);   
			frameNumber := SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, frameNumber) * {0..10});
			RETURN SYSTEM.VAL(LONGINT, frameNumber);
		END GetFrameNumber;
				
		(** Removes the USB transfer request <req> from the host controller schedule *)
		PROCEDURE UnlinkTDs*(pipe : AosUsbHcdi.Pipe);
		BEGIN  {EXCLUSIVE}
			UnlinkTDsInternal(pipe);
		END UnlinkTDs;

		(** Removes the USB transfer request <req> from the host controller schedule *)
		PROCEDURE UnlinkTDsInternal*(pipe : AosUsbHcdi.Pipe);
		VAR td : LONGINT; dword : SET; timer : AosKernel.Timer;
		BEGIN
			IF pipe.firstTD = 0 THEN RETURN END; (* pipe has not yet been used *)
			(* deactivate all TDs in list *)
			td := pipe.firstTD; 
			ASSERT(SYSTEM.VAL(SET, td) * {0..3} = {}); (* 16byte alignment *)
			WHILE td < pipe.lastTD DO
				dword := SYSTEM.VAL(SET, SYSTEM.GET32(td + TDControlStatus));
				SYSTEM.PUT32(td + TDControlStatus, dword - TDActive);
				td := td + 16;
			END;
			NEW(timer); timer.Sleep(10); (* > 1ms to be sure that the HC doesn't access the tds anymore *)		
			SYSTEM.PUT32(pipe.qh + QhElementLinkPointer, QhTerminate); (* Unlink TD list *)
		END UnlinkTDsInternal;
		
		(* Set the QhTerminate bit in the Queue Head Element Link Pointer to unchain TDs *)
		PROCEDURE ClearHalt*(pipe : AosUsbHcdi.Pipe);
		VAR dword : SET;
		BEGIN
			ASSERT((pipe # NIL) & (pipe.qh # 0));
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + QhElementLinkPointer));
			ASSERT(dword * QhTdSelect = {}); (* We don't allow a QH to be queued in another QH, UHCI does, though *)
			dword := dword + QhTerminate;
			SYSTEM.PUT32(pipe.qh + QhElementLinkPointer, dword);
		END ClearHalt;
				
		(* Insert the queue head qh into the appropriate queue *)
		PROCEDURE InsertQH*(pipe : AosUsbHcdi.Pipe) : BOOLEAN; 
		VAR qhtmp, slots, index, queueslots : LONGINT;
		BEGIN (* only call from exclusive regions *)
			(* build qh. Both link and queue head link pointer are invalid *)
			ASSERT((pipe # NIL) & (pipe.qh # 0) & (SYSTEM.VAL(SET, pipe.qh) * {0..3} = {}));
			BuildQH(pipe.qh, 3, 1, pipe, 0); (* 3: select QH (2) + Terminate (1) *) 
			CASE pipe.type OF (* in which queue should we insert the pipe ? *)
				AosUsbHcdi.PipeControl : pipe.queue := controlTD;
				| AosUsbHcdi.PipeBulk : pipe.queue := bulkTD;
				| AosUsbHcdi.PipeIsochronous : pipe.queue := isochronousTD;
				| AosUsbHcdi.PipeInterrupt : 
					BEGIN
						slots := 1024 DIV pipe.irqInterval;
						index := 0; queueslots := 1024;
						LOOP
							IF queueslots = 0 THEN index := 10; EXIT; END;
							IF slots >= queueslots THEN EXIT END;
							queueslots := queueslots DIV 2; INC (index)
						END;
						pipe.queue := interruptTD[index]
					END;
			ELSE
				RETURN FALSE;
			END;
			(* insert the pipe's queue head into the queue *)
			qhtmp := SYSTEM.GET32(pipe.queue); (* qhtmp:= queue head link pointer of queue head <queue> *)
			SYSTEM.PUT32(pipe.qh, qhtmp); (* queue head link pointer of <qh> := qhtmp  (hasn't been used before) *)
			SYSTEM.PUT32(pipe.queue, SYSTEM.VAL(SET, pipe.qh) + {1}); (* queue head link pointer of <queue> := pointer to <qh> *)	
			RETURN TRUE;
		END InsertQH;
		
		(* Delete the queue head <qh> in the queue <queue> *)
		PROCEDURE RemoveQH*(pipe : AosUsbHcdi.Pipe);
		VAR qhtmp, queue, delthis : LONGINT; timer : AosKernel.Timer;
		BEGIN (* caller must hold obj lock *)
			UnlinkTDsInternal(pipe);
		
			delthis := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, pipe.qh) + {1});
			queue := pipe.queue;
	
			LOOP (* traverse list of queue heads *)
				qhtmp := SYSTEM.GET32(queue);
				IF qhtmp = 1 THEN (* end of list but not found ? *)
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbUhci: Fatal error, DeleteQH cannot find qh entry in queue"); AosOut.Ln; END;
					EXIT;
				END;
				IF qhtmp = delthis THEN (* delete qh *)
					qhtmp := SYSTEM.GET32(pipe.qh);
					SYSTEM.PUT32(queue, qhtmp);
					EXIT;
				END;
				queue := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, qhtmp) - {1})
			END;
			NEW(timer); timer.Sleep(10); (* > 1ms to be sure that HC is not operating on this QH *)
		END RemoveQH;
		
		(** Checks whether TDs may be linked to the pipe's QH *)
		PROCEDURE LinkTDsAllowed*(pipe : AosUsbHcdi.Pipe) : BOOLEAN;
		BEGIN {EXCLUSIVE}
			RETURN TRUE;
		END LinkTDsAllowed;		
		
		(* Insert the TD list <td> into the queue <queue> *)
		PROCEDURE LinkTDs*(pipe : AosUsbHcdi.Pipe; td : LONGINT); 
		BEGIN {EXCLUSIVE}		
			ASSERT(SYSTEM.VAL(SET, td) * {0..3} = {}); (* 16byte alignment of TDs *)
			SYSTEM.PUT32(pipe.qh + QhElementLinkPointer, td); (* queue element link pointer ::= pointer to td *)
		END LinkTDs;

		PROCEDURE ScheduleControl*(pipe : AosUsbHcdi.Pipe; direction : LONGINT; msg : AosUsbHcdi.ControlMessage;  bufferLen : LONGINT;  VAR buffer : AosUsbdi.Buffer);
		VAR td, pid, databuffer, restlen, curlen : LONGINT; tdStatus : SET;
		BEGIN
		 	(* Control transfers use a three stage protocol:	*)
			(*	stage1: control setup transaction				*)
			(*	stage2: optional data stage					*)
			(*	stage3: status transaction         				*)

			(* stage1: setup stage *)					
			pipe.firstTD := pipe.tdBase; td := pipe.tdBase;
			IF Debug.StrongChecks THEN DoStrongChecks(pipe, bufferLen, 0, buffer); END;

			tdStatus := TDActive + TDERR3;		
			IF pipe.speed = AosUsbHcdi.LowSpeed THEN tdStatus := tdStatus + TDLS; END;	
						
			(* build the setup TD *)
			BuildTDLinkPointer(td, TDDepthFirst, td + 16);
			BuildTDControlStatus(td, tdStatus);
			BuildTDToken(td, PidSetup, pipe.address, pipe.endpoint  MOD 16, FALSE, 8); (* dataToggle = FALSE *)
			SYSTEM.PUT32(td + TDBufferPointer, SYSTEM.ADR(msg[0]));
			
			(* setup phase always starts with dataToggle = FALSE, so now it must be TRUE *)
			pipe.dataToggle := TRUE; 
			
			(* stage 2: (optional) data stage *)
			IF bufferLen # 0 THEN
				
				IF direction = AosUsbHcdi.In THEN pid := PidIn; ELSE pid := PidOut; END;

				databuffer := pipe.physBufferAdr; (* offset included *)
				
				restlen := bufferLen;

				WHILE restlen > 0 DO (* build TD chain *) 
				
					td := td + 16;
						
					IF restlen > pipe.maxPacketSize THEN 
						curlen := pipe.maxPacketSize;
					ELSE
						curlen := restlen;
					END;	
						
					(* Build TD *)
					BuildTDLinkPointer(td, TDDepthFirst, td + 16);
					BuildTDControlStatus(td, tdStatus);
					BuildTDToken(td, pid, pipe.address, pipe.endpoint  MOD 16, pipe.dataToggle, curlen);
					SYSTEM.PUT32(td + TDBufferPointer, databuffer);
					
					pipe.dataToggle := ~pipe.dataToggle;			
					databuffer := databuffer + curlen;
					restlen := restlen - curlen;
				END;
			END;
			
			(* stage 3: status *)
			tdStatus := tdStatus - TDSPD; 
			IF pipe.ioc THEN tdStatus := tdStatus + TDIOC; END; (* enable interrupt on completion for this TD *)
			IF (direction = AosUsbHcdi.Out) OR (bufferLen = 0) THEN 
				pid := PidIn; 
			ELSE
				pid := PidOut;
			END;
			
			td := td + 16;
			
			(* build status TD *)
			BuildTDLinkPointer(td, TDTerminate, 0);
			BuildTDControlStatus(td, tdStatus);
			BuildTDToken(td, pid, pipe.address, pipe.endpoint MOD 16, TRUE, 0); (* dataToggle always TRUE in status stage *)
			SYSTEM.PUT32(td + TDBufferPointer, 0);
			pipe.lastTD := td;
		END ScheduleControl;
		
		PROCEDURE Schedule*(pipe : AosUsbHcdi.Pipe; bufferLen, offset: LONGINT; VAR buffer: AosUsbdi.Buffer);
		VAR td, pid, restlen, curlen, databuffer : LONGINT; tdStatus : SET;
		BEGIN					
			pipe.firstTD :=  pipe.tdBase;
			IF Debug.StrongChecks THEN DoStrongChecks(pipe, bufferLen, offset, buffer); END;
			
			(* enough TD's to support transfer of bufferLen bytes? *)
			IF pipe.firstTD + 16*((pipe.transferLen DIV pipe.maxPacketSize) +1) > SYSTEM.ADR(pipe.tdBuffer[pipe.tdBufferLen-1]) THEN
				AosOut.String("AosUsbUhci: TD buffer too small to support requested tranfer size."); AosOut.Ln;
				pipe.status := AosUsbdi.Error; pipe.errors := AosUsbHcdi.OutOfTDs;
				RETURN;
			END;

			tdStatus := TDActive + TDERR3;	
			IF pipe.speed = AosUsbHcdi.LowSpeed THEN tdStatus := tdStatus + TDLS; END;	
			IF pipe.direction = AosUsbHcdi.In THEN 
				tdStatus := tdStatus + TDSPD; 
				pid := PidIn;
			ELSE
				pid := PidOut;
			END;
		
			restlen := bufferLen;
			databuffer := pipe.physBufferAdr; (* offset already added *)
			
			td := pipe.firstTD - 16;  
			
			WHILE restlen > 0 DO (* build TD chain *) 
				
				td := td + 16; 	
				
				IF restlen > pipe.maxPacketSize THEN
					curlen := pipe.maxPacketSize; 				
					BuildTDLinkPointer(td, TDDepthFirst, td + 16);
				ELSE (* last TD in chain *)
					curlen := restlen;
					IF restlen < pipe.maxPacketSize THEN tdStatus := tdStatus - TDSPD; ELSE tdStatus := tdStatus + TDSPD; END; (* disable shortPacket detection *)
					IF pipe.ioc THEN tdStatus := tdStatus + TDIOC; ELSE tdStatus := tdStatus - TDIOC; END; (* enable interrupt on completion for this TD *)
					BuildTDLinkPointer(td, TDTerminate, 0);
				END;
				
				BuildTDControlStatus(td, tdStatus);
				BuildTDToken(td, pid, pipe.address, pipe.endpoint  MOD 16, pipe.dataToggle, curlen);
				SYSTEM.PUT32(td + TDBufferPointer, databuffer);
	
				pipe.dataToggle := ~ pipe.dataToggle;	
				databuffer := databuffer + curlen;
				restlen := restlen - curlen;
			END;	
			pipe.lastTD := td;
		END Schedule;
		
		PROCEDURE InterruptHandler;
		VAR s : SET;
		BEGIN (* works without being exclusive *)
			IF Debug.Stats THEN INC(NnofInterrupts); END;
			IF state >= AosUsbHcdi.Initialized THEN (* controller is active -> handle interrupts *)				
				SYSTEM.PORTIN(iobase + UsbSts, SYSTEM.VAL(INTEGER, s));							
				IF s # {} THEN
					IF Debug.Stats THEN INC(NnofInterruptsHandled); END;
					IF Debug.Trace & Debug.traceInterrupts THEN ShowInterrupts(s); END;
					(* reset the USB status register *)
					SYSTEM.PORTOUT(iobase + UsbSts, SYSTEM.VAL(INTEGER, s));
					IF s * StatusHChalted # {} THEN AosOut.String("AosUsbUhci: Error: Host Controller halted"); AosOut.Ln; SetState(AosUsbHcdi.Halted); END;
					IF s * StatusProcessError # {} THEN AosOut.String("AosUsbUhci: Host Controller process error"); AosOut.Ln; END;
					IF s * StatusSystemError # {} THEN AosOut.String("AosUsbUhci: Host system error"); AosOut.Ln; END;
					IF s * (StatusErrorInt + StatusInt) # {} THEN 
						NotifyCompletionHandlers;
					END;	
				END;
			END;
		END InterruptHandler;

		(* the host controller writes the number of actually transfered bytes into the ActLen field of each executed TD.
		 * The GetTransferredLen procedure builds the sum of all TD.ActLen fields of all executed TD's in the queue <qh> and then
		 * writes this value into the req.bufferLen field *)
		PROCEDURE GetTransferredLen(pipe : AosUsbHcdi.Pipe; VAR errors : SET); 
		VAR td, addr, thislen, actlen, maxlen, val : LONGINT; s : SET;
		BEGIN
			actlen := 0; addr := pipe.firstTD;
			LOOP
				val := SYSTEM.GET32(addr + TDControlStatus);

				s := SYSTEM.VAL(SET, val);
				IF s * TDActive # {} THEN (* this TD has not yet been executed *) EXIT; END;
				
				thislen := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val+1) * {0..10}); (* access the ActLen field of the TD *)
			
				val := SYSTEM.GET32(addr + TDToken); 
				IF SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {0..7}) # PidSetup THEN actlen := actlen + thislen; END;
				
				maxlen := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, ASH(val, -21) + 1) * {0..10});
				IF thislen < maxlen THEN 
					errors := errors + AosUsbHcdi.ShortPacket;
				END;
	
				IF s * (TDCrcTimeout + TDDataBuffer + TDStalled + TDBitStuff + TDBabble + TDNak) # {} THEN EXIT END;
				
				td := SYSTEM.GET32(addr + TDLinkPointer);
				IF SYSTEM.VAL(SET, td) * {0} # {} THEN (* TD link pointer not valid (last TD was the last TD in queue) *) EXIT; END;
				
				addr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, td) * {4..31}); (* addr := physical addr of td *)
			END;
			pipe.actLen := actlen;
		END GetTransferredLen;
		
		PROCEDURE UpdatePipeStatus*(pipe : AosUsbHcdi.Pipe);
		VAR
			val, td, addr, pid : LONGINT;
			errors, s : SET; 
			datatoggle : BOOLEAN;
			last : BOOLEAN;
		BEGIN
			(* be aware of the fact the the USB host controller is concurrently accessing AND modifying this datastructure !! *)
			(* test if the queue was finished *)
			td := SYSTEM.GET32(pipe.qh + QhElementLinkPointer); (* get queue head element link pointer *)
	
			IF td = 1 THEN (* yes, fetch status of last td in queue (queue head element link pointer is not valid) *)
				td := pipe.lastTD;
			ELSE
				td := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, td) * {4..31});
			END;
			
			IF td = pipe.lastTD THEN last := TRUE; END;
	
			addr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, td) * {4..31}); (* addr := physical addr of td *)
	
			val := SYSTEM.GET32(addr + TDControlStatus);
			s := SYSTEM.VAL(SET, val);
			(* the USB host controller could already have changed the status of the TD at this time *)	
		
			errors := AosUsbHcdi.NoErrors;
			
			IF s * TDActive # {} THEN RETURN; END;
			IF s * TDNak # {} THEN errors := errors + AosUsbHcdi.Nak; END; (* Actually, this is not really an error -> flow control *)
	
			val := SYSTEM.GET32(addr + TDToken); 
			
			pid := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {0..7});
			IF SYSTEM.VAL(SET, val) * TDDataToggle # {} THEN datatoggle := TRUE ELSE datatoggle := FALSE END;
			
			IF (s * (TDCrcTimeout + TDDataBuffer + TDStalled + TDBitStuff + TDBabble)) # {} THEN (* marginal speed up *)
				IF s * TDCrcTimeout # {} THEN errors := errors + AosUsbHcdi.CrcTimeout; END;
				IF s * TDDataBuffer # {} THEN errors := errors + AosUsbHcdi.Databuffer; END;
				IF s * TDStalled # {} THEN errors := errors + AosUsbHcdi.Stalled; END;
				IF s * TDBitStuff # {} THEN errors := errors + AosUsbHcdi.BitStuff; END;
				IF s * TDBabble # {} THEN errors := errors + AosUsbHcdi.Babble; END;
			END;
			
			IF ~last & (errors - AosUsbHcdi.Nak = {}) THEN RETURN; END;
						
			td := SYSTEM.GET32(pipe.qh + QhElementLinkPointer); (* get queue head element link pointer *)
	
			(* Test for errors *)
			GetTransferredLen(pipe, errors); 
			
			pipe.errors := errors;
				
			IF errors = AosUsbHcdi.NoErrors THEN 
				pipe.status := AosUsbdi.Ok; 
			ELSIF errors = AosUsbHcdi.ShortPacket THEN
				pipe.status := AosUsbdi.ShortPacket;
			ELSE 
				IF errors * AosUsbHcdi.Stalled # {} THEN
					pipe.status := AosUsbdi.Stalled;
				ELSE
					pipe.status := AosUsbdi.Error;
				END;
			END;

			IF (pipe.type = AosUsbHcdi.PipeBulk) OR (pipe.type = AosUsbHcdi.PipeInterrupt) THEN
				(* if we receive an ACK, do the toggle *)
				IF (pipe.status = AosUsbdi.Ok) OR (pipe.status = AosUsbdi.ShortPacket) THEN
					pipe.dataToggle  := ~datatoggle;
				END;	
			END;
		END UpdatePipeStatus; 

			
		(*	UHCI queue head format                                                                                                   
		 *
		 *	Offset:	Value:                                                                                                                
		 *	00  	 	Queue Head Link Pointer                                                                                                 
		 *	04  	 	Queue Element Link Pointer                                                                                            
		 *	08   	[Oberon specific]  Pointer to PipePolicy
		 *	12   	[Oberon specific]  Pointer to last TD in queue                                                                 
		 *)
		PROCEDURE BuildQH(td, f1, f2: LONGINT; f3 : ANY;  f4 : LONGINT);
		BEGIN
			SYSTEM.PUT32(td, f1);		(* QH queue head  link pointer field		*)
			SYSTEM.PUT32(td + 4, f2);	(* QH queue element link pointer field	*)
			SYSTEM.PUT32(td + 8, f3);	(* QH pointer to pipepolicy 				*)
			SYSTEM.PUT32(td + 12, f4);  	(* QH pointer to last TD in queue		*)
		END BuildQH;

		(*	UHCI Transfer Descriptor (TD) Format          
		 *                                                               
		 *	Offset:	Value:                                                                                                                    
		 *	00		Link Pointer[31:4]                                                                                                   
		 *	04  		Flags - Status - Actlen                                                                                           
		 *	08 		MaxLen - D Toggle - EndPt - Device Address - PID                                             
		 *	12 		Buffer Pointer                                                                                                         
		 *																																			
		 * For more details see Intel UHCI Design Guide v1.1, p. 20-25      
		 * builds a TD. Is also used to build queue heads *)
		PROCEDURE BuildTD(td, f1, f2, f3, f4 : LONGINT);
		BEGIN
			SYSTEM.PUT32(td + TDLinkPointer, f1);
			SYSTEM.PUT32(td + TDControlStatus, f2);
			SYSTEM.PUT32(td + TDToken, f3);
			SYSTEM.PUT32(td + TDBufferPointer, f4);
		END BuildTD;

		PROCEDURE BuildTDLinkPointer (VAR td : LONGINT; flags : SET; LinkPointer : LONGINT);
		BEGIN
			ASSERT( SYSTEM.VAL( SET, LinkPointer) * {0..3} = {});
			SYSTEM.PUT32(td, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, LinkPointer) + flags));
		END BuildTDLinkPointer;

		PROCEDURE BuildTDControlStatus (VAR td : LONGINT; status : SET);
		BEGIN
			status := status + {0..10}; SYSTEM.PUT32(td + TDControlStatus, status);
		END BuildTDControlStatus;

		PROCEDURE BuildTDToken (VAR td:LONGINT; PID, DeviceAddress, EndPoint : LONGINT; DataToggle : BOOLEAN; maxLength : LONGINT);
		VAR s : SET;
		BEGIN
			(* maxLength specifies the maximum number of data bytes allowed for the transfer,
			 * allowed values: 0x000-0x4FF (1-1280 bytes) and 0x7FF (0 bytes) *)
			ASSERT(((maxLength>=0000H) & (maxLength<=04FFH)) OR (maxLength=07FFH));
			IF maxLength = 0 THEN maxLength := 07FFH; (* 0 bytes = Null Data packet *)
			ELSE maxLength := maxLength - 1;  (* maxLength==0 -> 1 Byte *)
			END;
			s := {}; IF DataToggle THEN s := s + TDDataToggle END;
			SYSTEM.PUT32(td + TDToken, SYSTEM.VAL(SET, PID + ASH(DeviceAddress, 8) + ASH(EndPoint, 15) + ASH(maxLength, 21)) + s);
		END BuildTDToken;
		
		(* Initializes the host controller and builds up the basics of the UHCI data structures *)
		PROCEDURE Init(base: LONGINT; IRQ : LONGINT) : BOOLEAN;
		VAR i, k, j : LONGINT; dword : SET;
		BEGIN
			iobase := base; irq := IRQ; DMAchaining := FALSE;
			(* Configure the ports;  no more documented in the specs, but 3-4 possible *)
			portCount := NumberOfPorts; NEW(ports, portCount);
			(* Calculate offset from iobase of the port status/controll register for each port *)
			FOR i := 0 TO portCount - 1 DO ports[i] := iobase + PortSc1 + i*2; END;
									
			(* Build the emulated hub descriptor *)
			NEW(hubDescriptor, 8);
			hubDescriptor[0] := CHR(7);
			hubDescriptor[1] := CHR(29H); (* Hub Descriptor *)
			hubDescriptor[2] := CHR(portCount);
			dword := dword + {1};  	(* UHCI root hubs don't implement port power switching *)
			dword := dword + {4}; 	(* UHCI root hubs don't implement overcurrent detection *)
			hubDescriptor[3] := CHR(SYSTEM.VAL(LONGINT, dword));
			hubDescriptor[4] := CHR(0); (* Reserved *)
			hubDescriptor[5] := CHR(10); (* 20ms Power on to power good *)
			hubDescriptor[6] := CHR(0); (* Root hubs don't draw current from the USB *)
	
			NEW(framelist);
			(* Calculate the address of the 4K boundary contained in the 8K buffe (framelist base address has to be 4KB aligned) *)
			framelist.framelistbase := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.ADR(framelist.field[0]) + 1024*4 - 1) * {12..31});
			(* Calculate the index which points to the element positioned at the 4K boundary *)
			framelist.index := ( framelist.framelistbase - SYSTEM.ADR(framelist.field[0]) ) DIV 4;
			
			(* Okay... now allocate the 16byte aligned Queue Heads ... *)	
			NEW(tdlist, 16*TdListSize);  
			tdlistbase := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.ADR(tdlist[0])+15) * {4..31});
			ASSERT(SYSTEM.VAL(SET, tdlistbase) * {0..3} = {}); 
			ASSERT((tdlistbase >= SYSTEM.ADR(tdlist[0])) & (tdlistbase < SYSTEM.ADR(tdlist[16*TdListSize-1])));
			
			(* Set up the frame list pointer skeleton *)
			controlTD := tdlistbase;             
			bulkTD := tdlistbase + 16;
			isochronousTD := tdlistbase + 32;
	
			FOR i := 0 TO 10 DO
				ASSERT(tdlistbase + 48 + i*16 <= SYSTEM.ADR(tdlist[16*TdListSize-1]));
				interruptTD[i] := tdlistbase + 48 + i*16;
			END;
				
			(* Build queue heads for bulk-, control- and interupt transfers *)
			BuildTD(bulkTD, 1, 1, 0, 0);
			BuildTD(controlTD, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, bulkTD) + {1} ), 1, 0, 0);
			BuildTD(isochronousTD, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, controlTD) + {1}), 1, 0, 0);
			BuildTD(interruptTD[0], SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, isochronousTD) + {1} ), 1, 0, 0);
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
				
			Reset; (* Reset the host controller *)
	
			(* try to start the host controller *)
			IF Start() = FALSE THEN (* ERROR: Couldn't start the host controller. Controller was probably not correctly initialized. *)
				Reset; AosOut.String("AosUsbUhci: Couldn't start controller."); AosOut.Ln; RETURN FALSE; 
			END; 
	
			AosActive.InstallHandler(InterruptHandler, AosInterrupts.IRQ0+irq);			
			
			RETURN TRUE;
		END Init;

		(* Resets and then starts the host controller. As soon as the host controller is started, it processes the schedule *)
		PROCEDURE Start():BOOLEAN;
		VAR t : LONGINT; s : SET;
		BEGIN
			(* Perform host controller reset *)
			SYSTEM.PORTOUT(iobase + UsbCmd, SYSTEM.VAL(INTEGER, CmdHostControllerReset) );

			(* The host controller will clear the CmdHostControllerReset Bit after about 64 bit times *)
			t := 10000;
			REPEAT
				SYSTEM.PORTIN(iobase + UsbCmd, SYSTEM.VAL(INTEGER, s));
				DEC( t );
			UNTIL ((t = 0) OR ( ~(1 IN s)));

			IF t = 0 THEN (* ERROR: Host Controller should have cleared the Bit !! *) RETURN FALSE END;  

			(* Enable all interrupts, but remember: perhaps they are not being routed by the PIIX4 *)
			SYSTEM.PORTOUT(iobase + UsbIntr, SYSTEM.VAL(INTEGER, IntShortPacket + IntIOC + IntResume + IntTimeoutCRC) );

			(* We start at frame 0 and also set the framelistbase address *)
			SYSTEM.PORTOUT(iobase + FrNum, SYSTEM.VAL(INTEGER, 0) ); (* 16 bit! *)
			SYSTEM.PORTOUT(iobase + FlBaseAdr, SYSTEM.VAL(LONGINT, framelist.framelistbase));

			(* Start the controller, set max-packet size (64byte) and set the pseudo-semaphore which we don't need *)
			SYSTEM.PORTOUT(iobase + UsbCmd, SYSTEM.VAL(INTEGER, CmdRunStop + CmdConfigureFlag + CmdMaxPacket) );
			
			SetState(AosUsbHcdi.Operational);
			RETURN TRUE;
		END Start;
		
		PROCEDURE Cleanup;
		BEGIN
			IF state >= AosUsbHcdi.Initialized THEN AosActive.RemoveHandler(InterruptHandler, AosInterrupts.IRQ0 + irq); END;
			Cleanup^;
			Reset;
		END Cleanup;
	
		PROCEDURE ShowPipe*(pipe : AosUsbHcdi.Pipe);
		BEGIN
			HumanTD(pipe.firstTD);
		END ShowPipe;
						
		(** Displays the host controller's data struture on KernelLog *)
		PROCEDURE ShowSchedule*;
		BEGIN
			IF Debug.Trace THEN
			AosOut.String("Host Controller Data Structures of "); 
			AosOut.String(name); AosOut.String(" ("); AosOut.String(desc); AosOut.String("):"); AosOut.Ln;
			HumanQH(controlTD, SELF);
			HumanQH(interruptTD[10], SELF);
			END;
		END ShowSchedule;		
		
		PROCEDURE DoStrongChecks(pipe : AosUsbHcdi.Pipe; len, ofs : LONGINT; VAR buffer : AosUsbdi.Buffer);
		VAR i : LONGINT;
		BEGIN
			IF len > 0 THEN 
				i := AosMemory.PhysicalAdr(SYSTEM.ADR(buffer[0]), len);
				IF i = -1 THEN 
					AosOut.String("AosUsbUhci: Buffers must be physically contiguoues"); AosOut.Ln; 
					HALT(99)
				END;
			END;		
			IF pipe.type = AosUsbHcdi.PipeControl THEN
				ASSERT((pipe.firstTD + 16*((pipe.transferLen DIV pipe.maxPacketSize) +3)) <= SYSTEM.ADR(pipe.tdBuffer[pipe.tdBufferLen-1])); (* enough TDs *)
			ELSE
				ASSERT((pipe.firstTD + 16*((pipe.transferLen DIV pipe.maxPacketSize) +1)) <= SYSTEM.ADR(pipe.tdBuffer[pipe.tdBufferLen-1])); (* enough TDs *)
			END;
		END DoStrongChecks;
		
		(* for debugging: display diagnostics of this host controller to KernelLog *)
		PROCEDURE Diag;  
		VAR s : SET; 	framenum : LONGINT;
		BEGIN
			IF Debug.Trace THEN
			Diag^;
			SYSTEM.PORTIN (iobase + FrNum, SYSTEM.VAL(INTEGER, framenum));
			framenum := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, framenum) * {0..10});			
			AosOut.String("  Frame 0"); AosOut.Hex(framenum, 8);
			AosOut.String("    LastStatus: ");
			SYSTEM.PORTIN (iobase + UsbSts, SYSTEM.VAL(INTEGER, s));
			IF s # {} THEN
				IF s * StatusHChalted # {} THEN AosOut.String ("[HChalted]"); END;
				IF s * StatusProcessError # {} THEN AosOut.String ("[Process Error]"); END;
				IF s * StatusSystemError # {} THEN AosOut.String ("[System Error]"); END;
				IF s * StatusResumeDetect # {} THEN AosOut.String ("[Resume Detect]"); END;
				IF s * StatusErrorInt # {} THEN AosOut.String ("[ErrorInt]"); END;
				IF s * StatusInt # {} THEN AosOut.String ("[Int]"); END;
				AosOut.Ln;
			ELSE
				AosOut.String("[ok]"); AosOut.Ln;
			END;			
			AosOut.String ("    IRQ enable status: ");
			SYSTEM.PORTIN (iobase + UsbIntr, SYSTEM.VAL(INTEGER, s));
			IF s * IntShortPacket # {} THEN AosOut.String("[Short Packet]"); END;
			IF s * IntIOC # {} THEN AosOut.String ("[IOC]"); END;
			IF s * IntResume # {} THEN AosOut.String ("[Resume]"); END;
			IF s * IntTimeoutCRC # {} THEN AosOut.String ("[Timeout/CRC]"); END;
			AosOut.Ln;
			END;
		END Diag;
		
	END UhciController;

VAR
	qhCounter : LONGINT; (* used by HumanQH; only for debug puposes *)
	
(* Debug: displays the information in the queue head qh and all TD's in that queue the queue is traversed only horizontally *)
PROCEDURE HumanQH(qh : LONGINT; controller : UhciController);
VAR val,addr : LONGINT; s : SET; pipe : AosUsbHcdi.Pipe; ptr : ANY;
BEGIN
	IF Debug.Trace THEN
	IF qhCounter > ShowScheduleMaxQH THEN 
		AosOut.String("AosUsbUhci: HumanQH: AosUsbUhci.ShowScheduleMaxQH showed... aborting."); AosOut.Ln;
		RETURN; 
	ELSE
		INC(qhCounter);
	END;
	AosOut.String("QH at address: "); AosOut.Hex(qh, 8); AosOut.String("H");
	IF qh = controller.controlTD THEN  AosOut.String(" (Controller Control Queue)");
	ELSIF qh = controller.bulkTD THEN AosOut.String(" (Controller Bulk Queue)");
	ELSIF qh = controller. isochronousTD THEN AosOut.String(" (Controller Isochronous Queue)");
	ELSIF qh = controller. interruptTD[0] THEN AosOut.String(" (Controller 1ms-Interrupt Queue)");
	ELSIF qh = controller. interruptTD[1] THEN AosOut.String(" (Controller 2ms-Interrupt Queue)");
	ELSIF qh = controller. interruptTD[2] THEN AosOut.String(" (Controller 4ms-Interrupt Queue)");
	ELSIF qh = controller. interruptTD[3] THEN AosOut.String(" (Controller 8ms-Interrupt Queue)");
	ELSIF qh = controller. interruptTD[4] THEN AosOut.String(" (Controller 16ms-Interrupt Queue)");
	ELSIF qh = controller. interruptTD[5] THEN AosOut.String(" (Controller 32ms-Interrupt Queue)");
	ELSIF qh = controller.interruptTD[6] THEN AosOut.String(" (Controller 64ms-Interrupt Queue)");
	ELSIF qh = controller.interruptTD[7] THEN AosOut.String(" (Controller 128ms-Interrupt Queue)");
	ELSIF qh = controller.interruptTD[8] THEN AosOut.String(" (Controller 256ms-Interrupt Queue)");
	ELSIF qh = controller.interruptTD[9] THEN AosOut.String(" (Controller 512ms-Interrupt Queue)");
	ELSIF qh = controller.interruptTD[10] THEN AosOut.String(" (Controller 1024ms-Interrupt Queue)");
	ELSE
		ptr := SYSTEM.VAL(ANY, SYSTEM.GET32(qh + 8)); (* should be a pointer to a pipe *)
		IF ptr # NIL THEN 
			pipe := ptr (AosUsbHcdi.Pipe);
			CASE pipe.type OF
				AosUsbHcdi.PipeBulk : AosOut.String(" (Bulk");
				|AosUsbHcdi.PipeControl : AosOut.String(" (Control");
				|AosUsbHcdi.PipeInterrupt : AosOut.String(" (Interrupt");
				|AosUsbHcdi.PipeIsochronous : AosOut.String(" (Isochronous");
			ELSE
				AosOut.String(" (Unknown");
			END;
			AosOut.String(" Pipe Adr: "); AosOut.Int(pipe.address, 0);
			AosOut.String(" Ep: "); AosOut.Int(pipe.endpoint, 0);
			AosOut.String(")"); AosOut.Ln;
		ELSE
			AosOut.String("(unknown)");
		END;
	END;
	AosOut.Ln;
	
	(* first show the information of the Queue Head Link pointer (QHLP) *)
	AosOut.String("   QH link pointer: "); 
	val := SYSTEM.GET32(qh); s := SYSTEM.VAL(SET, val);	
	IF s * TDQHSelect # {} THEN AosOut.String(" [QH]"); ELSE AosOut.String(" [TD]"); END;
	IF s * TDTerminate # {} THEN AosOut.String(" [Terminate]"); END;
	val := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {4..31});
	addr := val; (* addr := queue head link pointer *)
	AosOut.String("[PTR val: "); AosOut.Hex(val, 8); AosOut.String("H]"); AosOut.Ln;
	
	(* second show the information of the Queue Element Link Pointer (QELP) *)
	AosOut.String("   QH Element Link Pointer: ");
	val := SYSTEM.GET32(qh + 4); s := SYSTEM.VAL(SET,val);	
	IF s * TDQHSelect # {} THEN AosOut.String(" [QH]"); ELSE AosOut.String(" [TD]"); END;
	IF s * TDTerminate # {} THEN AosOut.String(" [Terminate]"); END;	
	val := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, val) * {4..31});
	AosOut.String("[PTR val: "); AosOut.Hex(val, 8); AosOut.String("G]"); AosOut.Ln;

	(* third show the queued TDs in this queue *)
	IF s * TDTerminate = {} THEN (* there are some queued TDs or QHs - show them *)
		IF s * TDQHSelect # {} THEN (* is a Queue Head *)
			HumanQH(val, controller);
		ELSE (* it's a TD *)
			HumanTD(val); 
		END;
	END;
	IF addr # 0 THEN (* there are other queue heads in the queue *)
		AosOut.String("next queue head in queue:"); AosOut.Ln; AosOut.Ln;
		HumanQH(addr, controller);
	END;
	(* reset qhCounter *)
	qhCounter := 0;
	END;
END HumanQH;

(* Debug: displays the information of the  Transfer Descriptor nexttd and all linked TD's and displays it *)
PROCEDURE HumanTD(nexttd: LONGINT);
VAR addr, val : LONGINT; s : SET;
BEGIN
	IF Debug.Trace THEN
	LOOP
		addr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, nexttd) * {4..31}); (* TD's are 16byte aligned *)
		AosOut.String("TD at address: "); AosOut.Hex(addr, 8); AosOut.Ln;
		(* link pointer information *)
		val := SYSTEM.GET32(addr); s := SYSTEM.VAL(SET, val);	
		AosOut.String("   LinkPTR:");
		IF s * TDDepthFirst # {} THEN AosOut.String(" [Depthfirst]"); ELSE AosOut.String("[BreathFirst]"); END;
		IF s * TDQHSelect # {} THEN AosOut.String(" [QH]"); ELSE AosOut.String(" [TD]"); END;
		IF s * TDTerminate # {} THEN AosOut.String(" [Terminate]"); END;
		AosOut.String(" [PTR Val: "); AosOut.Hex((val DIV 16) * 16, 8); AosOut.String("H]");
		AosOut.Ln;
		(* control & status field information *)
		val := SYSTEM.GET32(addr + 4); s := SYSTEM.VAL(SET, val);	
		AosOut.String("   Control&Status:");
		IF s * TDActive # {} THEN AosOut.String(" [Active]"); END;
		IF s * TDIOC # {} THEN AosOut.String(" [IOC]"); END;
		IF s * TDIOS # {} THEN AosOut.String(" [IOS]"); END;
		IF s * TDLS # {} THEN AosOut.String(" [LowSpeed]"); END;
		IF s * TDERR1 # {} THEN AosOut.String(" [Err1]"); END;
		IF s * TDERR2 # {} THEN AosOut.String(" [Err2]"); END;
		IF s * TDSPD # {} THEN AosOut.String(" [SPD]"); END;
		IF s * TDCrcTimeout # {} THEN AosOut.String(" [CRC/Timeout]"); END;
		IF s * TDNak # {} THEN AosOut.String(" [NAK]"); END;
		IF s * TDDataBuffer # {} THEN AosOut.String(" [DataBuffer]"); END;
		IF s * TDStalled # {} THEN AosOut.String(" [Stalled]"); END;
		IF s * TDBitStuff # {} THEN AosOut.String(" [BitStuff]"); END;
		IF s * TDBabble # {} THEN AosOut.String(" [Babble]"); END;
		AosOut.String (" [Actlen: "); val := SYSTEM.VAL(LONGINT, s * {0..10}); 
		IF val = 07FFH THEN val := 0; ELSE INC(val); END; AosOut.Int(val, 0); AosOut.String(" ]"); 
		AosOut.String(" [MaxLen: "); val := SYSTEM.GET32(addr + 8);
		val := SYSTEM.LSH(val, -21); IF val = 7FFH THEN val := 0; ELSE INC(val); END;
		AosOut.Int(val, 0); AosOut.String(" ]"); AosOut.Ln;
		
		AosOut.String("   PID: "); 
		val := SYSTEM.GET32(addr + 8); val := val MOD 256;
		CASE val OF
			PidOut : AosOut.String("OUT");
			| PidIn : AosOut.String("IN");
			| PidSetup : AosOut.String("SETUP");
		ELSE
			AosOut.String("Unkown ("); AosOut.Hex(val, 8); AosOut.String("H)");
		END;
		AosOut.String(" DataToggle: "); 
		val := SYSTEM.GET32(addr + 8); 
		s := SYSTEM.VAL(SET,val);
		IF s * TDDataToggle # {} THEN AosOut.String("DATA1"); ELSE AosOut.String("DATA0"); END;
		
		AosOut.String(" Device Adr: "); AosOut.Int(SYSTEM.LSH(SYSTEM.VAL(LONGINT, s * {8..14}), -8),0);
		AosOut.String(" Endpoint: "); AosOut.Int(SYSTEM.LSH(SYSTEM.VAL(LONGINT, s * {15..18}), -15),0);
		AosOut.Ln;

		nexttd := SYSTEM.GET32(addr);
		IF SYSTEM.VAL(SET, nexttd) * {0} # {} THEN EXIT; END;
		IF nexttd = 0 THEN AosOut.String("ERROR! Terminate was not set but address is 0"); AosOut.Ln; EXIT; END;
	END;
	END;
END HumanTD;

PROCEDURE ShowInterrupts(s : SET);
BEGIN
	AosOut.String("AosUsbUhci: Interrupt: ");
	IF s * StatusHChalted # {} THEN AosOut.String("[HcHalted]");  END;
	IF s * StatusProcessError # {} THEN AosOut.String("[ProcessError]"); END;
	IF s * StatusSystemError # {} THEN AosOut.String("[SystemError]"); END;
	IF s * StatusErrorInt # {} THEN AosOut.String("[ErrorInt]"); END; 
	IF s * StatusInt # {} THEN AosOut.String("[Int]"); END;
	AosOut.Ln;
END ShowInterrupts;  

(* Scan all PCI busses for UHCI compliant host controllers *)
PROCEDURE PCIFindUhci;
CONST
	UhciClassCode = 0C0300H;
VAR
	hostController : UhciController;
	bus, device, function : LONGINT;
	iobase, irqline : LONGINT;
	index : LONGINT;
	res : LONGINT;
BEGIN
	index := 0;
	WHILE PCI.FindPCIClassCode(UhciClassCode, index, bus, device, function) = PCI.Done DO
		(* Get IRQ line - should be set by BIOS *)
		res := PCI.ReadConfigByte(bus, device, function, PCI.IntlReg, irqline); ASSERT(res = PCI.Done);
		res := PCI.ReadConfigDword(bus, device, function, PCI.Adr4Reg, iobase); ASSERT(res = PCI.Done);
		iobase := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, iobase) * {1..31});
		IF irqline # 0 THEN
			res := PCI.WriteConfigWord(bus, device, function, 0C0H, 2000H); (* disable legacy emulation *)
			IF res = PCI.Done THEN
				NEW(hostController, bus, device, function);
				IF hostController.Init(iobase, irqline) THEN (* host controller has been initialized and started successfully *)	
					res := PCI.ReadConfigByte(bus, device, function, 60H, hostController.bcdUSB); (* ignore res *)
					IF Debug.Verbose THEN 
						AosOut.Enter;
						AosOut.String("AosUsbUhci: Initialised USB UHCI controller at base 0"); AosOut.Hex(iobase, 8); 
						AosOut.String("H, Irq: "); AosOut.Int(irqline, 0); 
						AosOut.String("  USB version: "); AosOut.Hex(SYSTEM.LSH(hostController.bcdUSB, -4), -2); AosOut.Char("."); 
						AosOut.Hex(hostController.bcdUSB MOD 10H, -2);
						AosOut.Exit;
					END;
					AosUsbHcdi.RegisterHostController(hostController, Description);
				ELSE
					AosOut.Enter;
					AosOut.String("AosUsbUhci: ERROR: Cannot init USB UHCI controller at base 0"); AosOut.Hex(iobase, 8); 
					AosOut.String("H, Irq: "); AosOut.Int(irqline, 0);
					AosOut.Exit;
				END;
			ELSE AosOut.String("AosUsbUhci: Error when accessing PCI configuration space (2)"); AosOut.Ln;
			END;
		ELSE
			AosOut.Enter;
			AosOut.String("AosUsbUhci: Please enable USB-Interrupt in BIOS for UHCI host controller at base 0");
			AosOut.Hex(iobase, 8); AosOut.Char("H"); AosOut.Ln;
			AosOut.Exit;
		END;
		INC(index);
	END;
END PCIFindUhci;

(** Scan the PCI bus(ses) for UHCI compliant USB host controllers and start them *)
PROCEDURE Install*(ptr : PTR): PTR;
BEGIN (* Load module *)
	RETURN NIL;
END Install;

PROCEDURE Cleanup();
BEGIN
	AosUsbHcdi.UnRegisterHostControllers(Description); 
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup); 
	(* Find, init and start all compatible UHCI USB host controllers and register them in the AosUsbHcdi.controllers registry *)
	PCIFindUhci;
END AosUsbUhci.

AosUsbUhci.Install ~  S.Free AosUsbUhci ~


