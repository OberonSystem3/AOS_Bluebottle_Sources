MODULE AosUsbOhci; (** AUTHOR "staubesv"; PURPOSE "USB Open Host Controller Driver" *)
(**
 *	Bluebottle USB Open Host Controller Driver
 *	Implements the AosUsbHcdi host controller driver interface (HCDI)
 *
 * Usage:
 *
 *	AosUsbOhci.Install ~ loads this device driver
 *	S.Free AosUsbOhci ~ unloads it
 *
 * References: 
 *
 *	OpenHCI Open Host Controller Interface Specification for USB, Release 1.0a
 *	
 * History:
 *
 *	01.12.2005	History started (staubesv)
 *	07.12.2005	Removed shadow registers, improved HC initialization (staubesv)
 *	15.12.2005	Moved buffer checks to AosUsbHcdi.Mod (staubesv)
 *	11.01.2006	Implemented H/W scatter/gather support (staubesv)
 *	16.01.2006	FlushPCI added (staubesv)
 *	25.01.2006	Make sure HCCA does not cross page boundary (staubesv)
 *	01.03.2006	Fixed critical bug in OpenHostController.CreateTDlist (staubesv)
 *	08.03.2006	LinkTDs: Allow linking TDs to a halted ED (staubesv)
 *	28.06.2006	Use AosOut.Hex instead of AosUsbHcdi.PrintHex (staubesv)
 *	03.08.2006	Adapted to AosUsbHcdi, Unlink TDs from ED if ED halted in UpdatePipeStatus, Fixed datatoggle for control transfer > 1TD,
 *				correctly calclulate actLen in case of short packets (staubesv)
 *	11.08.2006	Cleaner handling of root hub port status register operations (staubesv)
 *	13.11.2006	UpdatePipeStatus: Set pipe.status to AosUsbdi.Stalled when a stall is detected (staubesv)
 *
 * TODOs:
 *	- isochronous transfers
 *	- deactivate tds in UnlinkTDs
 *)

IMPORT AosOut, AosMemory, SYSTEM, PCI, AosKernel, AosActive, AosInterrupts, AosModules, AosUsbHcdi, AosUsbdi, Debug := AosUsbDebug;

CONST

	Description = "USB Open Host Controller";
	
	ScatterGatherListSize = 4000;
	PageSize = 4096;
	
	(* Operational register offsets from io base address; OHCI Spec. 1.0 *)
	HcRevision = 0H;
	HcControl = 4H;
	HcCommandStatus = 8H;
	HcInterruptStatus = 0CH;
	HcInterruptEnable = 10H;
	HcInterruptDisable = 14H;
	HcHCCA = 18H;
	HcPeriodCurrentED = 1CH;
	HcControlHeadED = 20H;
	HcControlCurrentED = 24H;
	HcBulkHeadED = 28H;
	HcBulkCurrentED = 2CH;
	HcDoneHead = 30H;
	HcFmInterval = 34H;
	HcFmRemaining = 38H;
	HcFmNumber = 3CH;
	HcPeriodicStart = 40H;
	HcLSThreshold = 44H;
	HcRhDescriptorA = 48H;
	HcRhDescriptorB = 4CH;
	HcRhStatus = 50H;
	HcRhPortStatus1 = 54H;
	(* HcRhPortStatus[n] = n * 4 +54; *)
	
	(* HcRevision Register *)
	HcRevRevision = {0..7};
	HcRevLegacySupport = {8};
	
	(* Legacy Support Registers (only available if Bit 8 is set in the register HcRevision *)
	HceControl = 100H;
	HceInput = 104H;
	HceOutput = 108H;
	HceStatus = 10CH;
	
	(* HcControl register *)
	HcConControlBulkServiceRatio = {0..1};
	HcConPeriodicListEnable = {2};
	HcConIsochronousEnable = {3};
	HcConControlListEnable = {4};
	HcConBulkListEnable = {5};
	HcConHcFunctionalState = {6..7};
	HcConInterruptRouting = {8};
	HcConRemoteWakeupConnected = {9};
	HcConRemoteWakeupEnable = {10};
	HcConReserved = {11..31};  (* do not alter *)
	
	(* HcControl HcConFunctionalState coding *)
	UsbReset = 0;
	UsbResume = 1;
	UsbOperational = 2;
	UsbSuspend = 3;

	(* HcCommandStatus register *)
	HcCmdHostControllerReset = {0};
	HcCmdControlListFilled = {1};
	HcCmdBulkListFilled = {2};
	HcCmdOwnershipChangeRequest = {3};
	HcCmdSchedulingOverrunCount = {16,17};
	
	(* HcInterruptStatus register *)
	HcIntSchedulingOverrun = {0};
	HcIntWriteBackDoneHead = {1};
	HcIntStartOfFrame = {2};
	HcIntResumeDetected = {3};
	HcIntUnrecoverableError = {4};
	HcIntFrameNumberOverflow = {5};
	HcIntRootHubStatusChange =  {6};
	HcIntReserved = {7..29} + {31}; (* Bit 31 has alwalys to be 0 (OHCIspec) *)
	HcIntOwnerShipChange = {30};
	
	(* HcInterruptEnable / HciInterruptDisable register; Write 1: set / clear; Write 0: leave unchanged *)
	IntSchedulingOverrun = {0};
	IntHcDoneHeadWriteback = {1};
	IntStartOfFrame = {2};
	IntResumeDetect = {3};
	IntUnrecoverableError = {4};
	IntFrameNumberOverflow = {5};
	IntRootHubStatusChange = {6};
	IntOwnerShipChange = {30};
	IntMasterInterruptEnable = {31};
	IntReservedMask = {7..29};
	
	(* HcFmInterval register (R/W) *)
	HcFmiFrameInterval = {0..13};
	HcFmiFsLargestDataPacket = {16..30};
	HcFmiFrameIntervalToggle = {31};
	HcFmiReserved = {14,15};
	
	(* HcPeriodicStart register (R/W) *)
	HcPerPeriodicStart = {0..13};
	HcPerReserved = {14..31};
		
	(* HcRhDescriptorA register (R) *)
	HcRhaNumberDownstreamPorts = {0..7};
	HcRhaNoPowerSwitching = {9};
	HcRhaPowerSwitchingMode = {8};
	HcRhaDeviceType = {10}; (* should be zero *)
	HcRhaOverCurrentProtectionMode = {11};
	HcRhaNoOverCurrentProtection = {12};
	HcRhaPowerOnToPowerGoodTime = {24..31};  (* unit of time is 2ms *)

	(* HcRhDescriptorB register (R/W)*)
	HcRhbDeviceRemovable = {1..15};
	HcRhbPortPowerControlMask = {17..31};
	HcRhbReserved = {0,16}; 
	
	(* HcRhStatus register (R/W) *)
	HcRhsLocalPowerStatus = {0};
	HcRhsOverCurrentIndicator = {1};
	HcRhsDeviceRemoteWakeupEnable = {15};
	HcRhsLocalPowerStatusChange = {16};
	HcRhsOverCurrentIndicatorChange = {17};
	HcRhsClearRemoteWakeupEnable = {31};
	HcRhsReservedMask = {2..14} + {18..30};  (* reserved bits should always be written '0' *)
	(* HcRhStatus register when written '1' *)
	HcRhsClearGlobalPower = {0};
	HcRhsSetRemoteWakeupEnable = {15};
	HcRhsSetGlobalPower = {16};
	
	(* Writing zeros to RhPortStatus register has no effect *)
	(* HcRhPortStatus register (R) *)
	HcPsCurrentConnectStatus = {0};
	HcPsPortEnableStatus = {1};
	HcPsPortSuspendStatus = {2};
	HcPsPortOverCurrentIndicator = {3};
	HcPsPortResetStatus = {4};
	HcPsPortPowerStatus = {8};
	HcPsLowSpeedDeviceAttached = {9};
	(* HcRhPortStatusRegister (W) *)
	HcPsClearPortEnable = {0};
	HcPsSetPortEnable = {1};
	HcPsSetPortSuspend = {2};
	HcPsClearSuspendStatus = {3};
	HcPsSetPortReset = {4};
	HcPsSetPortPower = {8};
	HcPsClearPortPower = {9};
	
	(* Write Clear *)	
	HcPsConnectStatusChange = {16};
	HcPsPortEnableStatusChange = {17};
	HcPsSuspendStatusChange = {18};
	HcPsOverCurrentIndicatorChange = {19};
	HcPsPortResetStatusChange = {20};
	
	HcPsReserved = {5..7} + {10..15} + {21..31};  (* reserved bits should always be written '0' *)
	HcPsChangeMask = {16..20};
	
	(* Endpoint Descriptor Format (16byte structure, must be 16byte aligned) *)
	(* I use a 32 byte data structure. See below *)
	(* Offsets: *)
	EdControlStatus = 0;
	EdTailP = 4;
	EdHeadP = 8;
	EdNextEdP = 12;
	
	(* Dword 0 *)
	EdFunctionAddress = {0..6};
	EdEndpointNumber = {7..10};
	EdDirection = {11..12};
	EdSpeed = {13};
	EdSkip = {14};
	EdFormat = {15};
	EdMaximumPacketSize = {16..26};
	(* Dword 2 *)
	EdHalted = {0};
	EdToggleCarry = {1};
	
	(* Used in ED's and TD's to describe the transfers direction *)
	PidSetup = 0; (* get direction from TD *)
	PidOut = 1;
	PidIn = 2;
	
	(* Transfer Descriptor Format (16byte structure, must be 16byte aligned) *)
	(* Offsets: *)
	TdCommand = 0;
	TdCurrentBufferP = 4;
	TdNextTdP = 8;
	TdBufferEndP = 12;
	(* Dword 0 *)
	TdTransferSize = {0..17};  (* bluebottle specific: how many bytes should have been transfered by this TD *)
	TdBufferRounding = {18};
	TdDirectionPid = {19..20};
	TdDelayInterrupt = {21..23};
	TdDataToggle = {24};
	TdDataToggleFromTd = {25};
	TdErrorCount = {26..27};
	TdConditionCode = {28..31};
	(* Dword 1 *)
	TdCurrentBufferPointer = {0..31};
	(* Dword 2 *)
	TdNextTd = {4..31};
	(* Dword 3 *)
	TdBufferEnd = {0..31};
	
	(* TD Completion Codes *)
	TdNoError = 0;
	TdCrc = 1;
	TdBitStuffing = 2;
	TdDataToggleMismatch = 3;
	TdStall = 4;
	TdDeviceNotResponding = 5;
	TdPidCheckFailure = 6;
	TdUnexpectedPid = 7;
	TdDataOverrun = 8;
	TdDataUnderrun = 9;
	(* bits 10 & 11 are reserved *)
	TdBufferOverrun = 12;
	TdBufferUnderrun = 13;
	TdNotAccessed1 = 14;
	TdNotAccessed2 = 15;
	(* 1110 & 1111 : not accessed & init value *)
	
	(* static, disqabled endpoint descriptor to build basic data structure in the HCCA *)
	(* 3: control-,bulk- and isochronousTD;  6: interruptTD[0..5];  1: NullQueue 1: alignment   *)
	TdListSize = 3 + 6 + 1 + 1;  
	
	(* HCCA :  hcca.data[base+offset] *)
	HccaInterruptTable = 0;
	HccaFrameNumber = 32; (* lower 16 bits *)
	HccaDoneHead = 36;
	
	(* how many Queue Heads should the debug procedure ShowSchedule() show... *)
	(* useful if the schedule data structure is corrupted *)
	ShowScheduleMaxQH = 1000;
	
	(* constants used for hc initialization *)
	HccFSLargestDataPacket =  1000*8 ; (* in bits *)
	HccFrameInterval = 2EDFH; 
	HccPeriodicStart = 3E67H;
	
TYPE
	
	OpenHostController = OBJECT (AosUsbHcdi.Hcd)                         
	VAR
		(* Host Controller Communication Area (HCCA) *)
		hcca : AosUsbHcdi.AlignedMemSpace;
		
		(* host controller revision (HcRevision Register 0..7), BCD coded  *)
		revision : LONGINT;
		legacySupport : BOOLEAN;
		
		(* queue heads *)
		controlED : LONGINT;
		bulkED : LONGINT;
		isochronousED : LONGINT;
		interruptED : POINTER TO ARRAY 6 OF LONGINT;
	
		nullTD : LONGINT; 
		
		(* this array will provide the 16byte aligned TD's for controlTD, bulkTD, isochronousTD and interruptTD[] *)
		tdlist : AosUsbHcdi.AlignedMemSpace;
						
		globalPowerSwitching : BOOLEAN;

		(** Enable power for the specified port *)
		PROCEDURE EnablePortPower*(port : LONGINT);
		BEGIN
			IF ~globalPowerSwitching THEN 
				SYSTEM.PUT32(ports[port], HcPsSetPortPower);
			ELSE
				SYSTEM.PUT32(iobase + HcRhStatus, HcRhsSetGlobalPower);
			END;
			FlushPCI;
		END EnablePortPower;
		
		(** Disable power for the specified port *)
		PROCEDURE DisablePortPower*(port : LONGINT);
		BEGIN
			IF ~globalPowerSwitching THEN 
				SYSTEM.PUT32(ports[port], HcPsClearPortPower);
			ELSE
				(* Disables power for all ports! *)
				SYSTEM.PUT32(iobase + HcRhStatus, HcRhsClearGlobalPower);
			END;
			FlushPCI;
		END DisablePortPower;
														
		(** Reset and enable specified port *)
		PROCEDURE ResetAndEnablePort*(port : LONGINT) : BOOLEAN;
		VAR status : SET; mtimer : AosKernel.MilliTimer;
		BEGIN 		
			SYSTEM.PUT32(ports[port], HcPsSetPortReset); FlushPCI;
			Wait(AosUsbHcdi.PortResetTime); (* >= 10ms, USBspec *)			
			AosKernel.SetTimer(mtimer, AosUsbHcdi.PortEnableTimeout);
			REPEAT
				status := SYSTEM.VAL(SET, SYSTEM.GET32(ports[port]));		
			UNTIL (status * HcPsPortEnableStatus # {}) OR AosKernel.Expired(mtimer);
			RETURN status * HcPsPortEnableStatus # {};
		END ResetAndEnablePort;

		(** Disables port number <port> on this root hub *)
		PROCEDURE DisablePort*(port : LONGINT);
		BEGIN
			SYSTEM.PUT32(ports[port], HcPsClearPortEnable); FlushPCI;
			SYSTEM.PUT32(ports[port], HcPsChangeMask); FlushPCI;
		END DisablePort;
		
		(** Get the status of the port <port> of this root hub. Registers which indicate changes are reset by GetPortStatus *)
		PROCEDURE GetPortStatus*(port : LONGINT; ack : BOOLEAN):SET;
		VAR status, s : SET;
		BEGIN
			s := SYSTEM.VAL(SET, SYSTEM.GET32(ports[port]));
			(* clear all bits that reported a change event *)
			IF ack & ((s * HcPsChangeMask) # {}) THEN SYSTEM.PUT32(ports[port], HcPsChangeMask * s); FlushPCI; END;  
			status := {};
			IF s * HcPsCurrentConnectStatus # {} THEN status := status + AosUsbHcdi.PortStatusDevicePresent; END;
			IF s * HcPsPortEnableStatus # {} THEN status := status + AosUsbHcdi.PortStatusEnabled END;
			IF s * HcPsPortSuspendStatus # {} THEN status := status + AosUsbHcdi.PortStatusSuspended END;
			IF s * HcPsPortOverCurrentIndicator # {} THEN status := status + AosUsbHcdi.PortStatusOverCurrent END;
			IF s * HcPsPortResetStatus # {} THEN status := status + AosUsbHcdi.PortStatusReset END;
			IF s * HcPsPortPowerStatus # {} THEN status := status + AosUsbHcdi.PortStatusPowered END;
			IF s * HcPsConnectStatusChange # {} THEN status := status + AosUsbHcdi.PortStatusConnectChange END;
			IF s * HcPsPortEnableStatusChange # {} THEN status := status + AosUsbHcdi.PortStatusEnabledChange END;
			IF s * HcPsSuspendStatusChange # {} THEN status := status + AosUsbHcdi.PortStatusSuspendChange END;
			IF s * HcPsOverCurrentIndicatorChange # {} THEN status := status + AosUsbHcdi.PortStatusOverCurrentChange END;
			IF s * HcPsPortResetStatusChange # {} THEN status := status + AosUsbHcdi.PortStatusResetChange END;
			IF s * HcPsLowSpeedDeviceAttached # {} THEN 
				status := status + AosUsbHcdi.PortStatusLowSpeed;
			ELSE
				status := status + AosUsbHcdi.PortStatusFullSpeed;
			END;
			RETURN status;
		END GetPortStatus;
		
		(* Returns the current frame number; the frame number is incremented by the Host Controller at the end of each frame time *)
		PROCEDURE GetFrameNumber*() : INTEGER;
		BEGIN
			RETURN SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, hcca.data[hcca.base + HccaFrameNumber]) * {0..15});
		END GetFrameNumber;

		(* Build and then insert the endpoint descriptor of the pipe into the host controller schedule *)
		PROCEDURE InsertQH*(pipe : AosUsbHcdi.Pipe) : BOOLEAN; 
		VAR nextED : LONGINT; dword : SET; 
		BEGIN (* only call from exclusive regions *)
			ASSERT((pipe#NIL) & (pipe.qh#0) & (SYSTEM.VAL(SET, pipe.qh) * {0..3} = {})); (* 16byte alignment *) 
			ASSERT((pipe.maxPacketSize > 0)); 
			CASE pipe.type OF (* in which queue should we insert the pipe ? *)
				| AosUsbHcdi.PipeControl : pipe.queue := controlED;
				| AosUsbHcdi.PipeBulk : pipe.queue := bulkED;
				| AosUsbHcdi.PipeIsochronous : pipe.queue := isochronousED;
				| AosUsbHcdi.PipeInterrupt : 
					BEGIN
						IF pipe.irqInterval = 1 THEN (* 1ms queue *)
							pipe.queue := interruptED[0];
						ELSIF pipe.irqInterval < 4 THEN (* 2ms queue *)
							pipe.queue := interruptED[1];
						ELSIF pipe.irqInterval < 8 THEN (* 4ms queue *)
							pipe.queue := interruptED[2]; 
						ELSIF pipe.irqInterval < 16 THEN (* 8ms queue *)
							pipe.queue := interruptED[3];
						ELSIF pipe.irqInterval < 32 THEN (* 16ms queue *)
							pipe.queue := interruptED[4];
						ELSE
							pipe.queue := interruptED[5]; (* 32 ms queue *)
						END;
					END;
			ELSE
				RETURN FALSE;
			END;
			
			(* build the pipe's endpoint descriptor *)
			(* dword0:  0..6: function address; 7..10: endpoint number; 11..12: direction; 13: Speed; 14: Skip; 15: Format; 16..26: maximum packet size; 27..31: available *)
			dword := SYSTEM.VAL(SET, pipe.address) * EdFunctionAddress + (SYSTEM.VAL(SET, SYSTEM.LSH(pipe.endpoint, 7)) * EdEndpointNumber); 
			IF pipe.type = AosUsbHcdi.PipeControl THEN (* get direction from TD *)
				(* bit 11&12 both zero *)
			ELSE (* get direction from ED *)
				IF pipe.direction = AosUsbHcdi.In THEN 
					INCL(dword, 12); (* PidIn *)
				ELSIF pipe.direction = AosUsbHcdi.Out THEN
					INCL(dword, 11); (* PidOut *)
				ELSE
					HALT(90);
				END;
			END;
				
			IF pipe.speed = AosUsbHcdi.LowSpeed THEN dword := dword + EdSpeed; END;
			IF pipe.type = AosUsbHcdi.PipeIsochronous THEN dword := dword + EdFormat; END;
			dword := dword + (SYSTEM.VAL(SET, SYSTEM.LSH(pipe.maxPacketSize, 16)) * EdMaximumPacketSize);
			dword := dword + EdSkip; (* HC should not (yet) process this ED *)

			SYSTEM.PUT32(pipe.qh + EdControlStatus, dword);			
			(* dword1: 0..3: available; 4..31: TailP *)
			SYSTEM.PUT32(pipe.qh + EdTailP , nullTD);			
			(* dword2: 0: halted; 1: dataToggle; 2..3: 00; 4..31: HeadP *)
			SYSTEM.PUT32(pipe.qh + EdHeadP , nullTD);			
			(* dword3: NextED pointer (Physical Address!!) *)
			nextED := SYSTEM.GET32(pipe.queue + EdNextEdP);  (* get NextED field of the queue; nextED contains physical address *)
			SYSTEM.PUT32(pipe.qh + EdNextEdP, SYSTEM.VAL(SET, nextED) * {4..31}); 
			SYSTEM.PUT32(pipe.queue + EdNextEdP, pipe.qh); 
			RETURN TRUE; 
		END InsertQH;
		
		(* Delete the queue head <qh> in the queue <queue> *)
		PROCEDURE RemoveQH*(pipe : AosUsbHcdi.Pipe);
		VAR prev, temp : LONGINT; dword : SET;
		BEGIN (* caller must hold obj lock *)
			(* REMEMBER: The Host Controller is concurrently accessing dword1-3 of the ED's *)
			(* set EdSkip flag (HC shall not process the ED) *)
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh)) + EdSkip;
			SYSTEM.PUT32(pipe.qh, dword);
			
			(* search to ED that points to the ED of the pipe *)
			prev := pipe.queue;
			LOOP
				temp := SYSTEM.GET32(prev + EdNextEdP);
				IF (temp = pipe.qh) OR (temp = 0) THEN EXIT; END;
				prev := temp; 
				ASSERT(SYSTEM.VAL(SET, prev) * {0..3} = {});
			END;			

			IF temp = 0 THEN 
				IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbOhci: DeleteQH: Pipe not found."); AosOut.Ln; END;
				RETURN;
			END;
			
			(* remove pipe.qh from EDList *)
			SYSTEM.PUT32(prev + EdNextEdP, SYSTEM.GET32(pipe.qh + EdNextEdP));
			
			(* the ED is not any more in the EDList, but it is possible the HC is processing the ED right now... *)
			(* We disable the list processing for the list that contained the deleted ED *)
			CASE pipe.type OF
				| AosUsbHcdi.PipeControl:
					dword := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcControl)) - HcConControlListEnable;
					SYSTEM.PUT32(iobase + HcControl, dword); FlushPCI;
					temp := SYSTEM.GET32(iobase + HcControlCurrentED);
					IF temp = pipe.qh THEN (* deleted ED currently in process... update *)
						SYSTEM.PUT32(iobase + HcControlCurrentED, 0); FlushPCI;
					END;
					(* re-enable list processing of the control list *)
					dword := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcControl)) + HcConControlListEnable;
					SYSTEM.PUT32(iobase + HcControl, dword); FlushPCI;
				| AosUsbHcdi.PipeBulk :
					dword := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcControl)) - HcConBulkListEnable; 
					SYSTEM.PUT32(iobase + HcControl, dword); FlushPCI;
					temp := SYSTEM.GET32(iobase + HcBulkCurrentED);
					IF temp = pipe.qh THEN (* deleted ED currently in process... update *)
						SYSTEM.PUT32(iobase + HcBulkCurrentED, 0); FlushPCI;
					END;
					(* re-enable list processing of the control list *)
					dword := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcControl))+HcConBulkListEnable;
					SYSTEM.PUT32(iobase + HcControl, dword); FlushPCI;
			ELSE
			END;
		END RemoveQH;
		
		(** Checks whether TDs may be linked to the pipe's QH *)
		PROCEDURE LinkTDsAllowed*(pipe : AosUsbHcdi.Pipe) : BOOLEAN;
		VAR headP, tailP : SET;
		BEGIN {EXCLUSIVE}
			headP := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdHeadP)) * {4..31};
			tailP := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdTailP)) * {4..31};
			IF headP # tailP THEN (* There are TDs linked to this ED *)
				pipe.status := AosUsbdi.Error; pipe.errors := pipe.errors + AosUsbHcdi.LinkTDsFailed;
				RETURN FALSE;
			ELSE
				RETURN TRUE;
			END;
		END LinkTDsAllowed;
		
		(* Insert the TD list <td> into the queue (ED) <queue> *)
		PROCEDURE LinkTDs*(pipe : AosUsbHcdi.Pipe;  td : LONGINT); 
		VAR dword : SET;
		BEGIN {EXCLUSIVE}		
			(* endpoint should not be processed by the HC ... *)
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdControlStatus)) + EdSkip;
			SYSTEM.PUT32(pipe.qh + EdControlStatus, dword); 
						
			(* inserts the tdlist <td> into the queue *)
			SYSTEM.PUT32(pipe.qh + EdTailP, nullTD); (* TailP ::= pointer to td *)
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdHeadP)); (* we need to preserve the lower 4 bits *)
			SYSTEM.PUT32(pipe.qh + EdHeadP, SYSTEM.VAL(SET, td) * {4..31} + dword * {1..3}); (* HeadPointer :: = td; Clear Halt bit if set *)
			
			(* enable pipe *)
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdControlStatus));
			SYSTEM.PUT32(pipe.qh + EdControlStatus, dword - EdSkip); 
									
			IF pipe.type = AosUsbHcdi.PipeControl THEN (* Set ControlListFilled Bit... bits written 0 remain unchanged *)
				SYSTEM.PUT32(iobase + HcCommandStatus, HcCmdControlListFilled);
			ELSIF pipe.type = AosUsbHcdi.PipeBulk THEN (* Set BulkListFilled Bit... bits written 0 remain unchanged *)
				SYSTEM.PUT32(iobase + HcCommandStatus, HcCmdBulkListFilled);
			END;
			FlushPCI;
		END LinkTDs;
		
		(** Remove all transfer descriptors from the pipe's endpoint descriptor *)
		PROCEDURE UnlinkTDs*(pipe : AosUsbHcdi.Pipe);
		VAR dword : SET;
		BEGIN {EXCLUSIVE}
			IF pipe.firstTD = 0 THEN RETURN END; (* pipe has not yet been used *)
			(* disable processing for this endpoint descriptor *)
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdControlStatus));
			SYSTEM.PUT32(pipe.qh + EdControlStatus, dword + EdSkip);
			(* remove TD list *)
			SYSTEM.PUT32(pipe.qh+ EdTailP, nullTD); (* TailP ::= pointer to td *)
			SYSTEM.PUT32(pipe.qh + EdHeadP, nullTD); (* HeadPointer :: = td *)
		END UnlinkTDs;

		(* Clears the EdHalted bit in the Endpoint descriptor and sets the EdSkip bit to prevent processing by the HC *)
		PROCEDURE ClearHalt*(pipe : AosUsbHcdi.Pipe);
		VAR dword : SET; temp : SET;
		BEGIN
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdHeadP));	
			IF dword * EdHalted # {} THEN
				temp := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdControlStatus));
				temp := temp + EdSkip;
				SYSTEM.PUT32(pipe.qh + EdControlStatus, temp);
				dword := dword - EdHalted - EdToggleCarry;
				SYSTEM.PUT32(pipe.qh + EdHeadP, dword);
			ELSE
				IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbOhci: ClearHalt: Pipe is not halted."); AosOut.Ln; END;
			END;
		END ClearHalt;
		
		PROCEDURE ScheduleControl*(pipe : AosUsbHcdi.Pipe; direction : LONGINT; msg : AosUsbHcdi.ControlMessage;  bufferLen : LONGINT; VAR buffer : AosUsbdi.Buffer);
		VAR ranges : ARRAY ScatterGatherListSize OF AosMemory.Range; 	td, numRanges : LONGINT; dword : SET; 
		BEGIN
			(* control transfers use a three stage protocol:
			 *	stage1: control setup transaction
			 *	stage2: optional data stage
			 *	stage3: status transaction         *)
			pipe.firstTD := pipe.tdBase; td := pipe.tdBase;
					
			(* stage1: control setup transaction: build the setup TD *)				
			(* dword0: no IOC; EdDirection = EdPidSetup; DataToggle in TDs; DataToggle = Data0; ErrorCount = 0; CC = not accessed *)
			SYSTEM.PUT32(td + TdCommand, TdDelayInterrupt + TdDataToggleFromTd + {29,30,31}); 
			SYSTEM.PUT32(td + TdNextTdP, td + 16);
			
			AosMemory.TranslateVirtual(SYSTEM.ADR(msg[0]), 8, numRanges, ranges);			
			IF numRanges = 0 THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbOhci: Scatter/Gather list too small."); AosOut.Ln; END;
				pipe.status := AosUsbdi.Error; pipe.errors := AosUsbHcdi.TransferTooLarge; RETURN;
			END;
			
			SYSTEM.PUT32(td + TdCurrentBufferP, ranges[0].adr);
			IF numRanges = 1 THEN
				SYSTEM.PUT32(td + TdBufferEndP, ranges[0].adr + 8 - 1);
			ELSE
				SYSTEM.PUT32(td + TdBufferEndP, ranges[1].adr + ranges[1].size - 1);
			END;
			ASSERT(SYSTEM.GET32(td + TdBufferEndP) - SYSTEM.GET32(td + TdCurrentBufferP) + 1 = 8); (* 8 byte control message *)
			
		
			(* setup phase always starts with dataToggle = FALSE, so now it must be TRUE *)
			pipe.dataToggle := TRUE; 

			(* stage 2: (optional) data stage *)
			IF bufferLen # 0 THEN
				IF ~CreateTDList(pipe, direction, bufferLen, 0, buffer, td + 16, td, TRUE) THEN	
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbOhci: Scatter/Gather list too small."); AosOut.Ln; END;
					pipe.status := AosUsbdi.Error; pipe.errors := pipe.errors + AosUsbHcdi.TransferTooLarge; RETURN;
				END;
			END;
							
			td := td + 16;
			IF td + 15 > SYSTEM.ADR(pipe.tdBuffer[pipe.tdBufferLen-1]) THEN
				IF Debug.Level >= Debug.Errors  THEN AosOut.String("AosUsbOhci: TD buffer too small"); AosOut.Ln; END;
				pipe.status := AosUsbdi.Error; pipe.errors := pipe.errors + AosUsbHcdi.OutOfTDs; RETURN;
			END;
		
			(* stage 3: status: build status TD *)
			dword := TdDataToggle + TdDataToggleFromTd + {29,30,31}; (* dataToggle always TRUE and set ind TD in status stage; CC = not accessed *)
			
			IF (direction = AosUsbHcdi.Out) OR (bufferLen = 0) THEN 
				INCL(dword, 20); (* PidIn *)
			ELSE
				INCL(dword, 19); (* PidOut *)
			END;
			
			IF pipe.ioc THEN (* enable interrupt on completion for this TD *)
				(* okay, but ...  optimization possible : DelayInterrupt  *)
			ELSE
				dword := dword + TdDelayInterrupt; (* no IOC *)
			END; 
			
			SYSTEM.PUT32(td + TdCommand, dword);
			SYSTEM.PUT32(td + TdCurrentBufferP, 0); (* no data *)
			SYSTEM.PUT32(td + TdNextTdP, nullTD);
			SYSTEM.PUT32(td + TdBufferEndP, 0);
			pipe.lastTD := td;
		END ScheduleControl;
				
		PROCEDURE Schedule*(pipe : AosUsbHcdi.Pipe; bufferLen, offset: LONGINT; VAR buffer: AosUsbdi.Buffer);
		VAR dword : SET;
		BEGIN
			pipe.firstTD :=  pipe.tdBase;
			
			IF ~CreateTDList(pipe, pipe.direction, bufferLen, offset, buffer, pipe.firstTD, pipe.lastTD, FALSE) THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbOhci: Scatter/Gather list too small."); AosOut.Ln; END;
				pipe.status := AosUsbdi.Error; pipe.errors := pipe.errors + AosUsbHcdi.TransferTooLarge; RETURN;
			END;
			
			SYSTEM.PUT32(pipe.lastTD + TdNextTdP, nullTD);
			IF pipe.ioc THEN
				dword := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.lastTD + TdCommand));
				dword := dword - TdDelayInterrupt; (* Enable IOC by delaying interrupts for zero frames *)
				SYSTEM.PUT32(pipe.lastTD + TdCommand, dword);
			END;
		END Schedule;
		
		PROCEDURE CreateTDList(pipe : AosUsbHcdi.Pipe; direction, len, ofs : LONGINT; VAR buffer : AosUsbdi.Buffer; firstTD : LONGINT; VAR lastTD : LONGINT; tdToggle : BOOLEAN) : BOOLEAN;
		VAR
			restlen, curlen : LONGINT;
			numRanges, idx, offset : LONGINT;
			td, temp : LONGINT;
			dword : SET;
		BEGIN
			AosMemory.TranslateVirtual(SYSTEM.ADR(buffer[ofs]), len, numRanges, pipe.sgList^);
			IF numRanges = 0 THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbOhci: Scatter/Gather list too small."); AosOut.Ln; END;
				pipe.status := AosUsbdi.Error; pipe.errors := AosUsbHcdi.TransferTooLarge; RETURN FALSE;
			END;
			
			td := firstTD - 16;
			restlen := len; idx := 0; offset := 0;
			
			WHILE restlen > 0 DO (* build TD chain *) 
				
				td := td + 16; 	
				IF td + 15 > SYSTEM.ADR(pipe.tdBuffer[pipe.tdBufferLen-1]) THEN
					pipe.errors := pipe.errors + AosUsbHcdi.OutOfTDs;
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbOhci: TD buffer too small"); AosOut.Ln; END;
					RETURN FALSE;
				END;
								
				(* Each TD can have at maximum 8KB buffer space. The buffer must be virtually contiguous. The buffer may, however, 		*)
				(* spawn across one page boundary. When the HC detects a page crossing, it will use the 20 msb bits of the TdBufferEndP  	*)
				(* pointer to get the next page frame number. 																			*)
				
				(* dword1: current buffer pointer *)
				SYSTEM.PUT32(td + TdCurrentBufferP, pipe.sgList[idx].adr + offset); (* Adding offset is okay since adr is page aligned or offset is zero *)

				curlen := PageSize - ((pipe.sgList[idx].adr + offset) MOD PageSize);
				IF curlen >= restlen THEN (* no page crossing, last TD in chain *)
					curlen := restlen; restlen := 0; 
					SYSTEM.PUT32(td + TdBufferEndP, pipe.sgList[idx].adr + offset + curlen - 1);
				ELSE (* Page crossing; will still have room for 4096 Bytes in this TD *)
					restlen := restlen - curlen; offset := 0; INC(idx);
					ASSERT(idx < numRanges); 
					(* The special thing here is, that, curlen must be a multiple of pipe.maxPacketSize if this is not the last TD in the chain. 	*)
					(* Otherwise we would ask/sent for less data than device exspects to send/receive. 									*)
					temp := PageSize - ((curlen + PageSize) MOD pipe.maxPacketSize); (* max amount of data that fits into second buffer *)
					IF restlen > temp THEN (* Not last TD *)
						(* There will be more TDs. *)
						curlen := curlen + temp; offset := temp; restlen := restlen - temp;
						SYSTEM.PUT32(td + TdBufferEndP, pipe.sgList[idx].adr + temp - 1);
						IF offset = PageSize THEN INC(idx); offset := 0; 
						ELSE (* Same page (idx) will be filled in first buffer pointer of next TD in chain *)
						END;
					ELSE (* Last TD in chain *)
						curlen := curlen + restlen; 
						SYSTEM.PUT32(td + TdBufferEndP, pipe.sgList[idx].adr + restlen - 1);
						restlen := 0;
					END;
				END;
				ASSERT(curlen <= 8192);
				
				SYSTEM.PUT32(td + TdNextTdP, td + 16);
				
				dword := {29,30,31} + TdDelayInterrupt + TdBufferRounding ; (* CC = not accessed; no IOC *)
				dword := dword + SYSTEM.VAL(SET, curlen) * TdTransferSize;

				IF tdToggle THEN 
					dword := dword + TdDataToggleFromTd; 
					IF pipe.dataToggle THEN dword := dword + TdDataToggle; END;
					
					(* Calculate datatoggle value for next TD *)
					IF (curlen DIV pipe.maxPacketSize) MOD 2 # 0 THEN
						pipe.dataToggle := ~pipe.dataToggle;
					END;
				END; 

				IF direction = AosUsbHcdi.In THEN
					INCL(dword, 20);
				ELSIF direction = AosUsbHcdi.Out THEN
					INCL(dword, 19); 
				END; 
				
				SYSTEM.PUT32(td + TdCommand, dword);					
			END;							
			lastTD := td;
			RETURN TRUE;				
		END CreateTDList;
		
		PROCEDURE InterruptHandler;
		VAR s : SET;
		BEGIN (* works without being exclusive *)
			IF Debug.Stats THEN INC(NnofInterrupts); END;
			IF state >= AosUsbHcdi.Initialized THEN
				s := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcInterruptStatus));
				IF s # {} THEN
					IF Debug.Stats THEN INC(NnofInterruptsHandled); END;
					(* Reset interrupt status register *)
					SYSTEM.PUT32(iobase + HcInterruptStatus, s - HcIntReserved); FlushPCI;

					IF s * HcIntSchedulingOverrun # {} THEN  AosOut.String("AosUsbOhci: HcIntSchedulingOverrun"); AosOut.Ln; END;
					IF s * HcIntResumeDetected # {} THEN AosOut.String("AosUsbOhci: HcIntResumeDetected"); AosOut.Ln; END;
					IF s * HcIntUnrecoverableError # {} THEN AosOut.String("AosUsbOhci: HcIntUnrecoverableError"); AosOut.Ln; END; 
					IF s * HcIntFrameNumberOverflow # {} THEN (* AosOut.String("AosUsbOhci: HcIntFrameNumberOverflow");  AosOut.Ln; *)END;
					IF s * HcIntRootHubStatusChange # {} THEN 
						IF statusChangeHandler # NIL THEN statusChangeHandler(0, 0); END;
					END;
					IF s * HcIntOwnerShipChange # {} THEN AosOut.String("AosUsbOhci: HcIntOwnerShipChange"); AosOut.Ln; END; 
					IF s * HcIntWriteBackDoneHead # {} THEN 
						NotifyCompletionHandlers;
					END;
				END; 
			END;
		END InterruptHandler;

		(* re-evaluate the status of the pipe's qh (endpoint descriptor) and its TD list *)
		PROCEDURE UpdatePipeStatus*(pipe : AosUsbHcdi.Pipe);
		CONST 
			MaxLoops = 10000;
		VAR
			tailP, headP : SET;
			td : LONGINT;
			currentBufferP, bufferEndP : LONGINT;
			dword, errors : SET;
			cc : LONGINT;
			actLen, len : LONGINT;
			loop : LONGINT;
		BEGIN
			IF SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdControlStatus)) * EdSkip # {} THEN RETURN; END;
			tailP := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdTailP));
			headP := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdHeadP));  
			
			IF headP * EdHalted # {} THEN (* some error occured when processing this TD list ... *)			
				
				td := pipe.firstTD; loop := 0; actLen := 0; errors := AosUsbHcdi.NoErrors;
				LOOP
					ASSERT(SYSTEM.VAL(SET, td) * {0..3} = {});
					(* evaluate condition codes (CC)*)
					dword := SYSTEM.VAL(SET, SYSTEM.GET32(td + TdCommand));
					cc := SYSTEM.LSH(SYSTEM.VAL(LONGINT, dword * TdConditionCode), -28);
					CASE cc OF
						| TdNoError : (* only AosUsbdi.ResOK if all TD's do not have errors *)
						| TdCrc : errors := errors + AosUsbHcdi.Crc;
						| TdBitStuffing : errors := errors + AosUsbHcdi.BitStuff;
						| TdDataToggleMismatch : errors :=  errors + AosUsbHcdi.DataToggleMismatch;
						| TdStall : errors := errors + AosUsbHcdi.Stalled;
						| TdDeviceNotResponding : errors := errors + AosUsbHcdi.DeviceNotResponding;
						| TdPidCheckFailure : errors := errors + AosUsbHcdi.PidCheckFailure;
						| TdUnexpectedPid :	errors := errors + AosUsbHcdi.UnexpectedPid;
						| TdDataOverrun : errors :=  errors + AosUsbHcdi.Babble;
						| TdDataUnderrun : errors := errors + AosUsbHcdi.ShortPacket;
						| TdBufferOverrun : errors := errors + AosUsbHcdi.Databuffer;
						| TdBufferUnderrun : errors := errors + AosUsbHcdi.Databuffer;
					ELSE 
						(* there's something wrong ... either the TD has not been accessed (which is not possible since the information in the ED) *)
						errors := errors + AosUsbHcdi.Internal;
					END;
										
					IF pipe.transferLen > 0 THEN (* data had to be transfered... *)
						
						(* len bytes should have been transfered for this TD *)
						len := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.GET32(td + TdCommand)) * TdTransferSize);
				
						currentBufferP := SYSTEM.GET32(td + TdCurrentBufferP);
						
						IF currentBufferP = 0 THEN (* all bytes transfered *)
							actLen := actLen + len;
						ELSE (* short packet *)
							bufferEndP := SYSTEM.GET32(td + TdBufferEndP);
							actLen := actLen + len - (bufferEndP - currentBufferP + 1); 
							errors := errors + AosUsbHcdi.ShortPacket;
						END;
					END;
					
					IF errors - AosUsbHcdi.ShortPacket # {} THEN EXIT; END;
					IF td = pipe.lastTD THEN EXIT; END;
					
					td := td + 16;
					IF loop > MaxLoops THEN EXIT; END;
					INC(loop);
				END; (* end loop *)
				
				pipe.actLen := actLen; pipe.errors := errors;
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
				
				dword := SYSTEM.VAL(SET, SYSTEM.GET32(pipe.qh + EdControlStatus));
				SYSTEM.PUT32(pipe.qh + EdControlStatus, dword + EdSkip);
				(* Unlink TDs from ED *)
				SYSTEM.PUT32(pipe.qh+ EdTailP, nullTD);
				SYSTEM.PUT32(pipe.qh + EdHeadP, nullTD);
				
			ELSIF (headP * {4..31} = tailP * {4..31}) THEN	(* no errors occured *)
				pipe.actLen := pipe.transferLen;
				pipe.status := AosUsbdi.Ok;
				pipe.errors := errors;
			ELSE (* TD still active *)
				(* do nothing *)
			END;			
		END UpdatePipeStatus;
		
		(* Set HC functional state to UsbReset. This causes the root hub and its downstream port to be reset and possible powered off (the latter) *)
		PROCEDURE HardwareReset() : BOOLEAN;
		VAR timer : AosKernel.Timer;
		BEGIN
			SYSTEM.PUT32(iobase + HcControl, SYSTEM.LSH(UsbReset, 6));	 FlushPCI;		
			NEW(timer); timer.Sleep(AosUsbHcdi.RootHubResetTime);
			RETURN TRUE;
		END HardwareReset;
			
		(* HC moves to UsbSuspend state und almost all operational registers are reset.
  		 * Does not affect the root hub and its downstream ports *)
		PROCEDURE SoftwareReset() : BOOLEAN;
		VAR millitimer : AosKernel.MilliTimer; dword : SET;
		BEGIN 
			SYSTEM.PUT32(iobase + HcCommandStatus, HcCmdHostControllerReset); FlushPCI;
			AosKernel.SetTimer(millitimer, 10);
			LOOP (* OpenHCI Spec.: Controller must clear this bit within 10 microseconds. We allow 10ms  *)
				dword := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcCommandStatus));
				IF (HcCmdHostControllerReset * dword = {}) OR AosKernel.Expired(millitimer) THEN EXIT END;
			END;
			RETURN HcCmdHostControllerReset * dword = {};
		END SoftwareReset;
		
		(* initialization of the data structures of the Host Controller Communication Area; Only useb by Init(...) *)
		PROCEDURE InitHcca(): BOOLEAN;
		VAR i, k, j : LONGINT;
		BEGIN
			(* HCCA needs to be 256-byte aligned *)
			hcca := AosUsbHcdi.GetAlignedMemSpace(256, 4096);  (* May not cross page boundary *)
			
			(* okay... now allocate memory for the 16byte aligned queue heads ... *)	
			tdlist := AosUsbHcdi.GetAlignedMemSpace(16*TdListSize, 16);
			
			NEW(interruptED); FOR i := 0 TO 5 DO interruptED[i] := SYSTEM.ADR(tdlist.data[tdlist.base]) + i*16; END;
			
			isochronousED := interruptED[5] + 16;
			controlED :=  isochronousED + 16;    
			bulkED := controlED +16;
			
			(* if the HeadP and the TailP pointers of a ED both points to nullQueue, there are no TDs in that ED TD list *)
			nullTD := bulkED + 16;
					
			(* set the Skip Flags, HeadP and TailP fields of all 66 ED's (63 interrupt + bulk + control + iso) *)
			FOR i := 0 TO 8 DO
				tdlist.data[tdlist.base + i*4 + (EdControlStatus DIV 4)] := SYSTEM.VAL(LONGINT, EdSkip); 
				tdlist.data[tdlist.base + i*4 + (EdTailP DIV 4)] := nullTD; 
				tdlist.data[tdlist.base + i*4 + (EdHeadP DIV 4)] := nullTD;
				tdlist.data[tdlist.base + i*4 + (EdNextEdP DIV 4)] := 0; 
			END;
			
			(* tree structure:
			    The host controller uses the lower 5 bits of the framenumber as index into an 32 entry head pointer table in the HCCA.
			    We want them to point to 32 interrupt endpoint descriptors. These are schedule all 32ms. 
			    
			    interrupt[0]: 1ms
			    interrupt[1]: 2ms
			    interrupt[2]: 4ms
			    interrupt[3]: 8ms
			    interrupt[4]: 16ms
			    interrupt[5]: 32ms
			  *)
			 
			FOR i := 5 TO 1 BY -1 DO
				SYSTEM.PUT32(interruptED[i] + EdNextEdP, interruptED[i-1]);
			END; 
		
			(* interrupt TD for 1ms points to isochronousTD *)
			SYSTEM.PUT32(interruptED[0] + EdNextEdP, isochronousED);
		
			FOR i := 0 TO 31 DO (* i is slot number, we want to calc the queue number (k) for this slot *)
				k := 0; j := i;
				LOOP (* k: counts '1' in j from the lsb until the first '0' *)
					IF (SYSTEM.VAL(SET, j) * {0}) = {} THEN EXIT; END;
					INC(k); j := j DIV 2;
				END;
				hcca.data[hcca.base + i] := interruptED[k];
			END;
			
			RETURN TRUE;
		END InitHcca;

		(* Initializes the host controller and builds up the  data structures of the HCCA *)
		PROCEDURE Init(virtualbase,  IRQ :  LONGINT) : BOOLEAN;
		CONST MaxOwnershipChangeRequests = 100;  
		VAR
			needUsbReset, ignore : BOOLEAN;
			dword, hcRhDescriptorA, hcRhDescriptorB : SET;
			timer : AosKernel.Timer; 
			hcControl, temp, lstate, i : LONGINT;
		BEGIN
			IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Starting host controller initialization..."); AosOut.Ln; END;
			iobase := virtualbase; irq := IRQ;
			DMAchaining := TRUE; sgListSize := ScatterGatherListSize;
			
			(* get revision of the open host controller : Bit 0..7 of the HcRevision register *)
			temp := SYSTEM.GET32(iobase + HcRevision);
			revision:= SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, temp) * HcRevRevision);
			IF revision #10H THEN 
				AosOut.String("AosUsbOhci: Revision of OHCI Programming Interface not supported."); AosOut.Ln;
				RETURN FALSE;
			END;
					
			(* check whether the controller does have legacy support registers : Bit 8 of HcRevision register  *) 
			IF SYSTEM.VAL(SET, temp) * HcRevLegacySupport # {} THEN 
				legacySupport := TRUE; 
				(* diable legacy emulation if enabled *)
				temp := SYSTEM.GET32(iobase + HceControl);
				IF SYSTEM.VAL(SET, temp) * {0} # {} THEN 
					(* disable legacy emulation *)
					SYSTEM.PUT32(iobase + HceControl, 0); FlushPCI;
					IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Disabled legacy emulation."); AosOut.Ln; END;				
				END;
			ELSE 
				legacySupport := FALSE; 
			END;
				
			(* Host controller already in use by other instances (SMM/BIOS driver) ?  *)
			(* We now determine whether a a transition to the UsbReset state is  necessary... if not, we just do a SoftReset. *)
			needUsbReset := FALSE;
			hcControl := SYSTEM.GET32(iobase + HcControl);
			
			IF (SYSTEM.VAL(SET, hcControl) * HcConInterruptRouting) # {}  THEN (* Interrupts routed to SMI -> SMM driver active *)
			
				IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Host Controller initialization: SMM driver found"); AosOut.Ln; END;
				SYSTEM.PUT32(iobase + HcCommandStatus, HcCmdOwnershipChangeRequest); FlushPCI;
				
				NEW(timer);
				(* the SMM driver should clear the OwnershipChangeRequest bit *)
				i := 0;
				LOOP
					temp := SYSTEM.GET32(iobase + HcControl);
					IF SYSTEM.VAL(SET, temp) * HcConInterruptRouting = {} THEN EXIT; END;
					INC(i);
					IF i > MaxOwnershipChangeRequests THEN EXIT; END;
					timer.Sleep(1); 
				END;
				hcControl := temp;
				(* OwnerShipChange successful ? *)
				IF SYSTEM.VAL(SET, temp) * HcConInterruptRouting # {} THEN
					IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Host Controller initialization: SMM driver did not response to OwnerShipChangeRequest."); AosOut.Ln; END;
					needUsbReset := TRUE;
				ELSE
					IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Host Controller initialization: OwnerShipChangeRequest succeeded."); AosOut.Ln; END;
					needUsbReset := FALSE;
				END;
				
			ELSIF SYSTEM.VAL(SET, hcControl) * HcConHcFunctionalState # {} THEN (* USB state not UsbReset -> BIOS driver active *)
			
				IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Controller initialization: BIOS driver found"); AosOut.Ln; END;
				lstate := SYSTEM.LSH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, hcControl) * HcConHcFunctionalState), -6);
				
				IF lstate # UsbOperational THEN 
					needUsbReset := TRUE;
				ELSE (* state is UsbSuspend or UsbResume *)
					needUsbReset := TRUE;
				END;
			
			ELSE (* neither SMM driver nor BIOS driver were active -> cold start *)
				IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Controller initialization: Cold start..."); AosOut.Ln; END;
				needUsbReset := TRUE;
			END;
			
			IF needUsbReset THEN
				IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Host Controller Initialization: USB Reset."); AosOut.Ln; END;
				IF ~HardwareReset() THEN 
					RETURN FALSE;
				END;
			END;
			
			(* Resets most registers. After a software reset, the HC is in mode UsbSuspend.  *)
			IF ~SoftwareReset() THEN RETURN FALSE; END; (* needed? *)
			
			(* determine the number of ports the root hub provides *)
			hcRhDescriptorA := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcRhDescriptorA));
			
			portCount := SYSTEM.VAL(LONGINT, hcRhDescriptorA * HcRhaNumberDownstreamPorts);
			IF (portCount < 1) OR (portCount > 15) THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbOhci: Host Controller Initialization failed (port count error)."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			NEW(ports, portCount);
			(* Calculate offset from iobase of the port status/controll register for each port *)
			FOR i := 0 TO portCount-1 DO ports[ i ] := iobase + HcRhPortStatus1 + i*4; END;

			(* Build the emulated hub descriptor *)
			NEW(hubDescriptor, 8);
			hubDescriptor[0] := CHR(7);
			hubDescriptor[1] := CHR(29H); (* Hub Descriptor *)
			hubDescriptor[2] := CHR(portCount);

			IF hcRhDescriptorA * HcRhaNoPowerSwitching # {} THEN (* Power switchting not supported *)
				dword := dword + {1}; 
			ELSIF hcRhDescriptorA * HcRhaPowerSwitchingMode # {} THEN (* Per port power switching *)
				dword := dword + {0};
				hcRhDescriptorB := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcRhDescriptorB)); (* preserve reserved bits ... *)
				hcRhDescriptorB := hcRhDescriptorB + HcRhbPortPowerControlMask; 
				SYSTEM.PUT32(iobase + HcRhDescriptorB, hcRhDescriptorB - HcRhbDeviceRemovable); FlushPCI; 	
			ELSE (* Ganged power switching *)
				globalPowerSwitching := TRUE;
			END;

			IF hcRhDescriptorA * HcRhaNoOverCurrentProtection # {} THEN (* Overcurrent protection not supported *)
				dword := dword + {4};
			ELSIF hcRhDescriptorA * HcRhaOverCurrentProtectionMode # {} THEN (* Per port overcurrent protection *)
					dword := dword + {3}; 
			ELSE (* Global overcurrent protection *)
				(* do nothing *)
			END;
			hubDescriptor[3] := CHR(SYSTEM.VAL(LONGINT, dword));
			hubDescriptor[4] := CHR(0); (* Reserved *)
			hubDescriptor[5] := CHR(SYSTEM.VAL(LONGINT, SYSTEM.LSH(hcRhDescriptorA * HcRhaPowerOnToPowerGoodTime, -24))); 
			hubDescriptor[6] := CHR(0); (* Root hubs don't draw current from the USB *)
			
			(* HC now in UsbSuspend state... if we do not change the HC functional state to UsbOperational within 2ms, we need to go into UsbResume... *);			
			
			IF ~InitHcca() THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbOhci: Initialization of HCCA failed."); AosOut.Ln; END;
				RETURN FALSE;
			END;  
									
			(* try to start the host controller *)
			IF Start() = FALSE THEN (* ERROR: Couldn't start the host controller. Controller was probably not correctly initialized. *)
				ignore := SoftwareReset(); AosOut.String("AosUsbOhci: Couldn't start host controller."); AosOut.Ln; RETURN FALSE; 
			END; 
			
			RETURN TRUE; 
		END Init;

		(* Resets and then starts the host controller. As soon as the host controller is started, it processes the schedule *)
		PROCEDURE Start():BOOLEAN;
		VAR dword : SET;
		BEGIN
			IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Starting host controller..."); END;			
			(* set base address of the HCCA *)
			SYSTEM.PUT32(iobase + HcHCCA, SYSTEM.ADR(hcca.data[hcca.base]));
			
			(* set the bulk list and the control list  head pointers *)
			SYSTEM.PUT32(iobase + HcControlHeadED,  controlED);
			SYSTEM.PUT32(iobase + HcBulkHeadED,  bulkED);
			SYSTEM.PUT32(iobase + HcControlCurrentED,  0);
			SYSTEM.PUT32(iobase + HcBulkCurrentED,  0); 
			FlushPCI;
			
			(* Go to operational state *)
			SYSTEM.PUT32(iobase + HcControl,  {7}); FlushPCI;
			
			(* save contents from HcFmInterval register ... *)
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcFmInterval)); 
			dword := dword * HcFmiReserved; (* preserve reserved bits *)
			dword := dword + (SYSTEM.VAL(SET, HccFrameInterval) * HcFmiFrameInterval);
			dword := dword + (SYSTEM.LSH(SYSTEM.VAL(SET, HccFSLargestDataPacket), 16) * HcFmiFsLargestDataPacket);
			dword := dword + HcFmiFrameIntervalToggle; (* tell the HC that we updated the field *)
			SYSTEM.PUT32(iobase + HcFmInterval, dword); 
			
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcPeriodicStart)); (* we need to preserve reserved bits... *)
			dword := dword - HcPerPeriodicStart + (SYSTEM.VAL(SET, HccPeriodicStart) * HcPerPeriodicStart);
			SYSTEM.PUT32(iobase + HcPeriodicStart, dword);
			
			SetState(AosUsbHcdi.Initialized);
			AosActive.InstallHandler(InterruptHandler, AosInterrupts.IRQ0+irq); 
			(* enable all interrupts *)
			dword := IntMasterInterruptEnable + IntHcDoneHeadWriteback + IntFrameNumberOverflow + IntUnrecoverableError + IntOwnerShipChange + IntRootHubStatusChange;
			SYSTEM.PUT32(iobase + HcInterruptEnable, dword); FlushPCI;		
			
			(* Set HcControl Register: Start the controller by set the hc functional state to UsbOperational *)
			(* ControlBulkServiceRatio = 1:1 (Bit0&Bit1: 00); Enable List Processing; UsbOperational (Bit 7) *)
			dword := HcConPeriodicListEnable (*+ HcConIsochronousEnable *) +  HcConControlListEnable + HcConBulkListEnable + {7};
			SYSTEM.PUT32(iobase + HcControl, dword); FlushPCI;
					
			SetState(AosUsbHcdi.Operational);
			IF Debug.Trace & Debug.traceInit THEN AosOut.String("done."); AosOut.Ln; END;
			RETURN TRUE;
		END Start;
		
		(* PCI writes may be posted. A read forces posted writes to be flushed before the read transaction is proceeded. *)
		PROCEDURE FlushPCI;
		VAR ignore : LONGINT;
		BEGIN
			ignore := SYSTEM.GET32(iobase + HcControl)
		END FlushPCI;
		
		PROCEDURE Cleanup;
		BEGIN
			IF state >= AosUsbHcdi.Initialized THEN AosActive.RemoveHandler(InterruptHandler, AosInterrupts.IRQ0 + irq);END;
			Cleanup^;
			IF ~HardwareReset() THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbOhci: Host controller reset failed."); AosOut.Ln; END;
			END;
			IF ~SoftwareReset() THEN
				IF Debug.Level >= Debug.Errors  THEN AosOut.String("AosUsbOhci: Software reset failed.");  AosOut.Ln; END;
			END;
			(* Unmap the HC's operational registers *)
			AosMemory.UnmapPhysical(iobase, 4096); 
		END Cleanup;
		
		(** Displays the host controller's data struture on KernelLog *)
		PROCEDURE ShowSchedule*;
		BEGIN
			IF Debug.Trace THEN
			AosOut.String("Host Controller Data Structures for ");
			AosOut.String(name); AosOut.String(" ("); AosOut.String(desc); AosOut.String("):"); AosOut.Ln;
			HumanSchedule(SELF);
			END;
		END ShowSchedule;		
		
		PROCEDURE ShowPipe*(pipe : AosUsbHcdi.Pipe);
		BEGIN
			HumanED(pipe.qh, SELF, 4, FALSE, FALSE);
			HumanTD(pipe.firstTD, pipe.lastTD, nullTD, 8); 
		END ShowPipe;
		
		(* for debugging: display diagnostics of this host controller to KernelLog *)
		PROCEDURE Diag*;  
		VAR s : SET; i, temp : LONGINT;
		BEGIN
			IF Debug.Trace THEN
			Diag^;
			(* display information of the HcRevision register *)
			temp := SYSTEM.GET32(iobase+HcRevision);
			AosOut.String("   HcRevision: "); 			
			AosOut.Hex(SYSTEM.VAL(LONGINT, SYSTEM.LSH(SYSTEM.VAL(SET, temp) * {4..7}, -4)), -2); AosOut.String(".");
			AosOut.Hex(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, temp) * {0..3}), -2);
			AosOut.String("   Legacy support: ");
			IF HcRevLegacySupport * SYSTEM.VAL(SET, temp) # {}  THEN 
				AosOut.String("Yes");
				AosOut.String(" [HceControl: "); temp := SYSTEM.GET32(iobase+HceControl); AosOut.Hex(temp, 8); AosOut.String("H]");
				AosOut.String(" [HceStatus: "); temp := SYSTEM.GET32(iobase+HceStatus); AosOut.Hex(temp, 8); AosOut.String("H]");
				AosOut.String(" [HceInput: "); temp := SYSTEM.GET32(iobase+HceInput); AosOut.Hex(temp, 8); AosOut.String("H]");
				AosOut.String(" [HceOutput: "); temp := SYSTEM.GET32(iobase+HceOutput); AosOut.Hex(temp, 8); AosOut.String("H]");				
			ELSE 
				AosOut.String("No"); 
			END;
			AosOut.Ln;
			(* display information of the HcControl register *)
			AosOut.String("   HcControl: State: ");
			temp := SYSTEM.GET32(iobase + HcControl);
			s := SYSTEM.VAL(SET, temp);
			CASE SYSTEM.VAL(LONGINT, SYSTEM.LSH(s*HcConHcFunctionalState, -6)) OF
				UsbReset : AosOut.String("UsbReset");
				| UsbResume : AosOut.String("UsbResume");
				| UsbOperational : AosOut.String("UsbOperational");
				| UsbSuspend : AosOut.String("UsbSuspend");
			ELSE 
				AosOut.Int(SYSTEM.VAL(LONGINT, SYSTEM.LSH(s*HcConHcFunctionalState,-6)),0);
			END;
			AosOut.String(" C/B-Ratio: "); 
			temp := SYSTEM.VAL(LONGINT, s * HcConControlBulkServiceRatio);
			AosOut.Int(i+1, 0); AosOut.String(": 1,"); 
			AosOut.String(" Flags: ");
			IF s * HcConPeriodicListEnable # {} THEN AosOut.String(" [PeriodicListEnabled]"); END;
			IF s * HcConControlListEnable # {} THEN AosOut.String(" [ControlListEnabled]"); END;
			IF s * HcConBulkListEnable # {} THEN AosOut.String(" [BulkListEnabled]"); END;
			IF s * HcConIsochronousEnable # {} THEN AosOut.String(" [IsochronousEnabled]"); END;
			IF s * HcConInterruptRouting # {} THEN AosOut.String(" [InterruptRouting]"); END;
			IF s * HcConRemoteWakeupConnected # {} THEN AosOut.String(" [RemoteWakeupConnected]"); END;
			IF s * HcConRemoteWakeupEnable # {} THEN AosOut.String(" [RemoteWakeupEnabled]"); END;
			AosOut.Ln;
			(* display information from HcCommandStatus register *)
			AosOut.String("   HcCommandStatus: SchedulingOverrungCount: ");
			 AosOut.Int(SYSTEM.VAL(LONGINT, SYSTEM.LSH(s * HcCmdSchedulingOverrunCount,16)), 0);
			AosOut.String(", Flags: ");
			temp := SYSTEM.GET32(iobase + HcCommandStatus);
			s := SYSTEM.VAL(SET, temp);
			IF s * HcCmdHostControllerReset # {}  THEN AosOut.String("[Reset]"); END;
			IF s * HcCmdControlListFilled # {} THEN AosOut.String("[ControlListFilled]"); END;
			IF s * HcCmdBulkListFilled # {} THEN AosOut.String("[BulkListFilled]"); END;
			IF s * HcCmdOwnershipChangeRequest # {} THEN AosOut.String("[OwnerShipRequest]"); END;
			AosOut.Ln;
			(* HcInterruptEnable register *)
			temp := SYSTEM.GET32(iobase + HcInterruptEnable);
			s := SYSTEM.VAL(SET, temp);
			AosOut.String("   Interrupts Enabled: ");
			IF s * IntMasterInterruptEnable # {} THEN AosOut.String("[MasterInterrupt]"); END;
			IF s * IntSchedulingOverrun # {} THEN AosOut.String("[SchedulingOverflow]"); END;
			IF s * IntHcDoneHeadWriteback # {} THEN AosOut.String("[WBDoneHead]"); END;
			IF s * IntStartOfFrame # {} THEN AosOut.String("[SOF]"); END;
			IF s * IntResumeDetect # {} THEN AosOut.String("[ResumeDetect]"); END;
			IF s * IntUnrecoverableError # {} THEN AosOut.String("[Error]"); END;
			IF s * IntFrameNumberOverflow # {} THEN AosOut.String("[FmOverflow]"); END;
			IF s * IntRootHubStatusChange # {} THEN AosOut.String("[RHStatusChange]"); END;
			IF s * IntOwnerShipChange # {} THEN AosOut.String("[OwnerShipChange]"); END;
			AosOut.Ln;
			(* display information from HcInterruptStatus register *)
			temp := SYSTEM.GET32(iobase + HcInterruptStatus);
			s := SYSTEM.VAL(SET, temp);
			AosOut.String("   HcInterruptStatus: ");
			IF s # {} THEN
				IF s * HcIntSchedulingOverrun # {} THEN AosOut.String("[SchedulingOverrun]"); END;
				IF s * HcIntWriteBackDoneHead # {} THEN AosOut.String("[WriteBackDoneHead]"); END;
				IF s * HcIntStartOfFrame # {} THEN AosOut.String("[StartOfFrame]"); END;
				IF s * HcIntResumeDetected # {} THEN AosOut.String("[ResumeDetected]"); END;
				IF s * HcIntUnrecoverableError # {} THEN AosOut.String("[UnrecoverableError]"); END;
				IF s * HcIntFrameNumberOverflow # {} THEN AosOut.String("[FrameNumberOverflow]"); END;
				IF s * HcIntRootHubStatusChange # {} THEN AosOut.String("[RooHubStatusChange]"); END;
				IF s * HcIntOwnerShipChange # {} THEN AosOut.String("[IntOwnerShipChange]"); END;
			ELSE
				AosOut.String(" [ok]");
			END;
			AosOut.Ln;
			(* display current framenumber *)
			temp := SYSTEM.GET32(iobase + HcFmNumber);                               
			AosOut.String("   Frame: Nbr: "); AosOut.Hex(temp, 8); 
			s := SYSTEM.VAL(SET, SYSTEM.GET32(iobase + HcFmInterval));
			AosOut.String("  FmInterval: "); AosOut.Int(SYSTEM.VAL(LONGINT, s * HcFmiFrameInterval), 0);
			AosOut.String("  FSMaxPacketSize: "); AosOut.Int(SYSTEM.LSH(SYSTEM.VAL(LONGINT, s * HcFmiFsLargestDataPacket),-16), 0); AosOut.String(" Bits, ");
			AosOut.String("  FmiToggle: ");
			IF s * HcFmiFrameIntervalToggle # {} THEN AosOut.String("Set"); ELSE AosOut.String("Not Set"); END;	
			temp := SYSTEM.GET32(iobase + HcPeriodicStart); AosOut.String(" PeriodicStart: "); AosOut.Hex(temp, 8);
			temp := SYSTEM.GET32(iobase + HcPeriodCurrentED); AosOut.String(" PeriodicCurrentED: "); AosOut.Hex(temp, 8);
			AosOut.Ln;		
			(* display list head addresses *)
			temp := SYSTEM.GET32(iobase + HcControlHeadED); AosOut.String("   ControlHeadED: "); AosOut.Hex(temp, 8); 
			temp := SYSTEM.GET32(iobase + HcControlCurrentED); AosOut.String("  CurrentControlED: "); AosOut.Hex(temp, 8);
			temp := SYSTEM.GET32(iobase + HcBulkHeadED); AosOut.String("  BulkHeadED: "); AosOut.Hex(temp, 8);
			temp := SYSTEM.GET32(iobase + HcBulkCurrentED); AosOut.String("  CurrentBulkED: "); AosOut.Hex(temp, 8);
			AosOut.Ln;
			END;
		END Diag;
				
	END OpenHostController;

VAR
	qhCounter : LONGINT; (* used by HumanQH; only for debug puposes *)
	
(* debug: displays the information in the queue head qh and all TD's in that queue 
 * ed : virtual address if first ED in EDList  *)
PROCEDURE HumanSchedule(controller : OpenHostController);
BEGIN
	IF Debug.Trace THEN	
	HumanED(controller.interruptED[5], controller, 4, TRUE, TRUE);
	HumanED(controller.bulkED, controller, 4, TRUE, TRUE);
	HumanED(controller.controlED, controller, 4, TRUE, TRUE);
	(* reset qhCounter *)
	qhCounter := 0;
	END;
END HumanSchedule;

PROCEDURE Indent(spaces : LONGINT);
VAR i : LONGINT;
BEGIN
	FOR i := 1 TO spaces DO AosOut.Char(" "); END;
END Indent;

(* Displays endpoint descriptor information to the kernel log; addr : Physical Address!! *)
PROCEDURE HumanED(ed : LONGINT; controller : OpenHostController; spaces : LONGINT; showTds, showEds : BOOLEAN);
VAR dword : SET; adr, ep : LONGINT; pipe : AosUsbHcdi.Pipe;
BEGIN
	IF Debug.Trace THEN
	(* to avoid endless loops because of (wrong) circular data structures *)
	IF qhCounter > ShowScheduleMaxQH THEN 
		AosOut.String("AosUsbOhci: HumanED: AosUsbOhci.ShowScheduleMaxQH showed... aborting."); AosOut.Ln;
		RETURN; 
	ELSE
		INC(qhCounter);
	END;
	ed := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, ed) * {4..31});
	dword :=SYSTEM.VAL(SET, SYSTEM.GET32(ed + EdControlStatus));
	adr := SYSTEM.VAL(LONGINT, dword * EdFunctionAddress);
	ep := SYSTEM.VAL(LONGINT, SYSTEM.LSH(dword * EdEndpointNumber, -7));
	
	Indent(spaces); AosOut.String("ED at address: "); AosOut.Hex(ed, 8); AosOut.String("H "); 
	IF ed = controller.controlED THEN AosOut.String("(ControlList Head)"); 
	ELSIF ed = controller.bulkED THEN AosOut.String("(BulkList Head)");
	ELSIF ed = controller.isochronousED THEN AosOut.String("(IsochronousList Head)");
	ELSIF ed = controller.interruptED[0] THEN AosOut.String("(1ms Interrupt Head)");
	ELSIF ed = controller.interruptED[1] THEN AosOut.String("(2ms Interrupt Head)");
	ELSIF ed = controller.interruptED[2] THEN AosOut.String("(4ms Interrupt Head)"); 
	ELSIF ed = controller.interruptED[3] THEN AosOut.String("(8ms Interrupt Head)"); 
	ELSIF ed = controller.interruptED[4] THEN AosOut.String("(16ms Interrupt Head)"); 
	ELSIF ed = controller.interruptED[5] THEN AosOut.String("(32ms Interrupt Head)");
	ELSE
		AosOut.String("(USB Pipe)");
	END;
	AosOut.Ln;
	
	(* Display information from EdControlStatus field *)
	Indent(spaces+4);
	AosOut.String("Adr: "); AosOut.Int(adr, 0); AosOut.String(" Ep: "); AosOut.Int(ep, 0);
	IF pipe # NIL THEN
		AosOut.String(" Type: "); 
		CASE pipe.type OF
			AosUsbHcdi.PipeControl : AosOut.String("Control");
			| AosUsbHcdi.PipeBulk : AosOut.String("Bulk");
			| AosUsbHcdi.PipeIsochronous : AosOut.String("Isochronous");
			| AosUsbHcdi.PipeInterrupt : AosOut.String("Interrupt");
		ELSE
			AosOut.String("UNKNOWN!!!");
		END;
	END;
	AosOut.String(" Dir: "); 
	CASE SYSTEM.VAL(LONGINT, SYSTEM.LSH(dword * EdDirection ,-11)) OF
		  PidIn : AosOut.String("In");
		| PidOut : AosOut.String("Out");
	ELSE
		AosOut.String("Specified in TD");
	END;
	AosOut.String(" MaxPacketSize: "); AosOut.Int(SYSTEM.VAL(LONGINT, SYSTEM.LSH(dword * EdMaximumPacketSize, -16)), 0); AosOut.String(" Bytes");
	IF pipe # NIL THEN
		AosOut.String(", LastStatus: "); AosUsbHcdi.ShowStatus(pipe.status);
	END;
	AosOut.String(", Flags: ");
	IF EdSkip * dword # {} THEN AosOut.String("[Skip]"); END;
	IF EdSpeed * dword # {}  THEN AosOut.String("[LowSpeed]"); ELSE AosOut.String("[FullSpeed]"); END;
	IF EdFormat * dword # {} THEN AosOut.String("[Isochronous]"); END;
	
	dword := SYSTEM.VAL(SET, SYSTEM.GET32(ed + EdHeadP));
	IF EdHalted * dword # {} THEN AosOut.String("[Halted]"); END;
	IF EdToggleCarry * dword # {} THEN AosOut.String("[Toggle=DATA1]"); ELSE AosOut.String("[Toggle=DATA0]"); END;
	AosOut.Ln;
	
	Indent(spaces+4); AosOut.String("HeadP: "); 
	dword := SYSTEM.VAL(SET, SYSTEM.GET32(ed + EdHeadP)) * {4..31};
	IF SYSTEM.VAL(LONGINT, dword) = controller.nullTD THEN 
		AosOut.String("NullTD");
	ELSE
		AosOut.Hex(SYSTEM.VAL(LONGINT, dword * {4..31}), 8); AosOut.String("H");
	END;
	AosOut.String(", TailP: "); 
	dword := SYSTEM.VAL(SET, SYSTEM.GET32(ed + EdTailP));
	IF SYSTEM.VAL(LONGINT, dword) = controller.nullTD THEN 
		AosOut.String("NullTD");
	ELSE
		AosOut.Hex(SYSTEM.VAL(LONGINT, dword * {4..31}), 8); AosOut.String("H");
	END;
	dword := SYSTEM.VAL(SET, SYSTEM.GET32(ed + EdNextEdP));
	AosOut.String(", NextED: "); 
	IF dword = {} THEN 
		AosOut.String("None");
	ELSE
		AosOut.Hex(SYSTEM.VAL(LONGINT, dword * {4..31}), 8); AosOut.String("H");
	END;
	AosOut.Ln;
	(* Show TD list of this endpoint descriptor *)
	Indent(spaces+4); AosOut.String("TDList: "); 
	dword := SYSTEM.VAL(SET, SYSTEM.GET32(ed + EdHeadP)) * {4..31};
	IF SYSTEM.VAL(SET, SYSTEM.GET32(ed + EdTailP)) * {4..31} = dword THEN (* HeadP == TailP *)
		AosOut.String("Empty");  AosOut.Ln;
	ELSE (* There are TD's in the list ... show TD list. *)
		AosOut.String("Non_Empty - First TD at "); AosOut.Hex(SYSTEM.VAL(LONGINT, dword * {4..31}), 8); AosOut.Char("H"); AosOut.Ln; AosOut.Ln;
		IF showTds THEN
			AosOut.Ln; HumanTD(SYSTEM.VAL(LONGINT, dword * {4..31}), 0, controller.nullTD, spaces + 4); AosOut.Ln;
		END;
	END;
	(* Show next endpoint descriptor in list *)
	IF showEds THEN
		dword := SYSTEM.VAL(SET, SYSTEM.GET32(ed + EdNextEdP)) * {4..31}; (* get NextED field *)
		IF dword # {} THEN 
			HumanED(SYSTEM.VAL(LONGINT, dword), controller, 4, showTds, showEds);
		END;
	END;
	END;
END HumanED;

(* debug: displays the information of the  Transfer Descriptor nexttd and all linked TD's and displays it *)
(* nextd : Physical Address !!! *)
PROCEDURE HumanTD(nexttd, lasttd, nulltd: LONGINT; spaces : LONGINT);
CONST MaxTDListLength = 200;
VAR val, val2 : LONGINT; dword : SET; iteration : LONGINT;
BEGIN
	IF Debug.Trace THEN
	iteration := 1;
	LOOP
		IF iteration > MaxTDListLength THEN (* for the case that addresses are misinterpreted ... *)
			Indent(spaces); AosOut.String("AosUsbOhci.HumandTD.MaxTDListLength reached... aborting.");
			EXIT;
		END;
		Indent(spaces); AosOut.String("TD at address: "); AosOut.Hex(nexttd, 8); AosOut.String("H"); AosOut.Ln;

		IF SYSTEM.VAL(SET, nexttd) * {0..3} # {} THEN 
			Indent(spaces); AosOut.String("Error: not 16byte aligned!!"); 
			EXIT;				
		ELSIF nexttd = 0 THEN 
			Indent(spaces); AosOut.String("Error: Address = 0 !!!"); AosOut.Ln;
			EXIT;
		ELSE
			(* TD Completion Codes *)
			Indent(spaces+4); AosOut.String("Condition Codes:");
			dword := SYSTEM.VAL(SET, SYSTEM.GET32(nexttd + TdCommand));
			CASE SYSTEM.VAL(LONGINT, SYSTEM.LSH(dword,-28)) OF
				| TdNoError : AosOut.String("[NoError]");
				| TdCrc : AosOut.String("[CRC]");
				| TdBitStuffing : AosOut.String("[BitStuffError]");
				| TdDataToggleMismatch : AosOut.String("[DataToggleMismatch]");
				| TdStall : AosOut.String("[STALL]");
				| TdDeviceNotResponding : AosOut.String("[DeviceNotResponding]");
				| TdPidCheckFailure : AosOut.String("[PidCheckFailure]");
				| TdUnexpectedPid : AosOut.String("[UnexpectedPid]");
				| TdDataOverrun : AosOut.String("[DataOverrun]");
				| TdDataUnderrun : AosOut.String("[DataUnderrun]");
				| TdBufferOverrun : AosOut.String("[BufferOverrun]");
				| TdBufferUnderrun : AosOut.String("[BufferUnderrun]");
				| 14..15: AosOut.String("[NotAccessed]");
			ELSE
				AosOut.String("[ConditionCodesNotValid]");
			END;
			AosOut.Ln;
			
			Indent(spaces+4); AosOut.String("Pid: ");
			CASE SYSTEM.VAL(LONGINT, SYSTEM.LSH(dword * TdDirectionPid, -19)) OF
				PidSetup : AosOut.String("PidSetup");
				| PidIn : AosOut.String("PidIn");
				| PidOut : AosOut.String("PidOut");
				| 3 : AosOut.String("Reserved");
			ELSE
				AosOut.String("Invalid");
			END;

			AosOut.String(", Flags: ");
			IF dword * TdBufferRounding # {} THEN AosOut.String("[BufferRounding]"); END;
			IF 25 IN dword THEN AosOut.String("[ToggleFromTD]"); ELSE AosOut.String("[ToggleFromEd]"); END;
			IF 24 IN dword THEN AosOut.String("[Toggle=DATA1]"); ELSE AosOut.String("[Toggle=DATA0]"); END;
			IF SYSTEM.VAL(LONGINT, SYSTEM.LSH(dword * TdDelayInterrupt, -21)) # 7 THEN (* IOC enabled *)
				AosOut.String("[IOC, MaxDelay: "); AosOut.Int(SYSTEM.VAL(LONGINT, SYSTEM.LSH(dword * TdDelayInterrupt, -21)), 0); AosOut.Char("]");
			END;
			AosOut.String(", Errors: "); AosOut.Int(SYSTEM.VAL(LONGINT, SYSTEM.LSH(dword * TdErrorCount, -26)), 0);
			AosOut.Ln;

			(* CurrentBufferPointer, BufferEndPointer & NextTD *)
			Indent(spaces+4); AosOut.String("CurBufferP: "); 
			val := SYSTEM.GET32(nexttd + TdCurrentBufferP); AosOut.Hex(val, 8); AosOut.String("H");
			AosOut.String(", BufferEnd: "); 
			val2 := SYSTEM.GET32(nexttd + TdBufferEndP); AosOut.Hex(val2, 8); AosOut.String("H");
			AosOut.String(" ("); 
			IF val = 0 THEN AosOut.String("0");
			ELSE AosOut.Int(val2 - val + 1, 0); 
			END;
			AosOut.String(" Bytes)");
			
			val := SYSTEM.GET32(nexttd + TdNextTdP);
			AosOut.String(", NextTD: "); 
			IF val = nulltd THEN AosOut.String("NullTD");
			ELSE AosOut.Hex(val, 8); AosOut.String("H");
			END;
			AosOut.Ln;
			
			IF SYSTEM.GET32(nexttd + TdNextTdP) = nulltd THEN
				Indent(spaces); AosOut.String("NullTD (EOL)"); AosOut.Ln; EXIT;
			ELSIF nexttd = lasttd THEN 
				Indent(spaces); AosOut.String("Pipe.lastTD (EOL)"); AosOut.Ln; EXIT;
			ELSIF nexttd = 0 THEN
				Indent(spaces); AosOut.String("nexttd adr is zero"); AosOut.Ln; EXIT;
			END;
			AosOut.Ln;
			nexttd := nexttd + 16; 	
			INC(iteration);
		END;
	END;
	END;
END HumanTD;

(* Find UHCI controllers on the PCI bus, create correspondig UCHIcontroller object and register them in the UHCI USB host controllers registry; 
	called by FindControllers *)
PROCEDURE PCIFindOhci;
CONST
	OhciClassCode = 0C0310H;
	PCIStatusErrorMask = {24,27,28,29,30,31}; 
VAR 
	hostController : OpenHostController;
	bus, device, function : LONGINT;
	iobasePhys, iobaseVirt, irq : LONGINT;
	pciCmdReg : LONGINT;
	index : LONGINT;
	res: LONGINT;
BEGIN
	index := 0;
	IF Debug.Trace & Debug.traceInit THEN AosOut.String("AosUsbOhci: Looking for PCI Open Host Controllers..."); AosOut.Ln; END;
	(* traverse all USB Open Host Controllers of all PCI busses in the system *)
	WHILE PCI.FindPCIClassCode(OhciClassCode, index, bus, device, function) = PCI.Done DO
		res := PCI.ReadConfigDword(bus, device, function, PCI.CmdReg, pciCmdReg); ASSERT(res = PCI.Done);
		IF SYSTEM.VAL(SET, pciCmdReg) * PCIStatusErrorMask # {} THEN 
			AosOut.String("AosUsbOhci: PCI device is in error state."); AosOut.Ln;
		ELSIF SYSTEM.VAL(SET,pciCmdReg) * {1} = {} THEN 
			AosOut.String("AosUsbOhci: Memory mapping is disabled."); AosOut.Ln;
		ELSIF SYSTEM.VAL(SET,pciCmdReg) * {2} = {} THEN
			AosOut.String("AosUsbOhci: Busmastering is disabled."); AosOut.Ln;
		ELSE 
			res := PCI.ReadConfigByte(bus, device, function, PCI.IntlReg, irq); ASSERT(res = PCI.Done);
			res := PCI.ReadConfigDword(bus, device, function, PCI.Adr0Reg, iobasePhys); ASSERT(res = PCI.Done);
			IF SYSTEM.VAL(SET, iobasePhys) * {0} # {} THEN
				AosOut.String("AosUsbOhci: Error: Operational Register are not memory mapped"); AosOut.Ln;
			ELSIF SYSTEM.VAL(SET, iobasePhys) * {1,2,3} # {} THEN
				AosOut.String("AosUsbOhci: Error: Operational Register are not correctly mapped "); AosOut.Ln;
			ELSIF irq = 0 THEN
				AosOut.String("AosUsbOhci: Error: Please enable interrupts for USB Host Controller."); AosOut.Ln;
			ELSE
				(* OHCI Spec: iobase address are the higher 20 bits *)
				iobasePhys := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, iobasePhys) * {12..31});
				AosMemory.MapPhysical(iobasePhys, 4096, iobaseVirt);
				NEW(hostController, bus, device, function);
				IF hostController.Init(iobaseVirt, irq) THEN (* host controller has been initialized and started successfully *)
					IF Debug.Verbose THEN
						AosOut.Enter;
						AosOut.String("AosOhci: Initialised USB Open Host Controller at base 0"); AosOut.Hex(iobasePhys, 8);
						AosOut.String(", Irq: "); AosOut.Int(irq, 0);
						AosOut.Exit;
					END;
					AosUsbHcdi.RegisterHostController(hostController, Description);				
				ELSE (* ERROR: host controller initialization failed *)
					AosOut.Enter;
					AosOut.String("AosOhci: Cannot init USB Open Host Controller at base 0"); AosOut.Hex(iobasePhys, 8); 
					AosOut.String(", Irq: "); AosOut.Int(irq, 0);
					AosOut.Exit;
				END;   
			END;
		END;
		INC(index);
	END; (* end while loop *)		
END PCIFindOhci;
	
(* called when this module is unloaded *)
PROCEDURE Cleanup;
BEGIN
	AosUsbHcdi.UnRegisterHostControllers(Description);
END Cleanup;

PROCEDURE Install*(ptr : PTR): PTR;
BEGIN (* Load module *)
	RETURN NIL;
END Install;

BEGIN
	AosModules.InstallTermHandler(Cleanup); 
	(* Find, init and start all compatible UHCI USB host controllers and register them in the AosUsbHcdi.controllers registry *)
	PCIFindOhci; 
END AosUsbOhci.

AosUsbOhci.Install ~ System.Free AosUsbOhci ~
