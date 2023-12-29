MODULE AosUsbHcdi; (** AUTHOR: "staubesv"; PURPOSE "Host controller driver interface (HCDI) for USB host controllers" *)

IMPORT AosOut, AosPlugins, AosModules;

CONST

	(** USB 1.1 transfer types *)
	TransferControl* = 1;
	TransferInterrupt* = 2;
	TransferBulk* = 3;
	TransferIsochronous* = 4; (** not zet implemented *)
	
	(** Result codes for the status field of the USB transfer requests (UsbTReq) *)
	ResOK* = {0};
	ResNAK* = {1};
	ResCRCTimeout* = {2};
	ResBitStuff* = {3};
	ResStalled* = {4};
	ResDataBuffer* = {5};
	ResBabble* = {6};
	ResShortPacket* = {7};
	ResInProgress* = {8};
	ResInternal* = {9};
	ResDisconnect* = {10};
	
	(** Aos USB driver specific hub port status bits *)
	PortStatusDevicePresent* = {0};
	PortStatusEnabled* = {1};
	PortStatusLowSpeed* = {2};
	PortStatusHighSpeed* = {3};
	PortStatusReset* = {4};
	PortStatusError* = {5};
	PortStatusConnectChange* = {6};    (* indicates a change of PortStatusDevicePresent *)

TYPE

	(** USB transfer request *)
 	UsbTReq* = POINTER TO RECORD
		device* : DevSpec;  
		endpoint* : INTEGER;
		typ* : INTEGER;
		status* : SET;
		buffer* : LONGINT;
		bufferLen* : LONGINT;
		controlMessage* : LONGINT;
		irqInterval* : INTEGER;
		timeout* : LONGINT;
		conSpec* : ConSpec; 
		intHandler* : IntHandler;
		active* : BOOLEAN;    (* intHandler is only called when active = TRUE *)
		next* : UsbTReq;
	END; 
	
	(* USB device specific data *)
	DevSpec* = POINTER TO RECORD
			address* : LONGINT;
		lowSpeed* : BOOLEAN;
		highSpeed* : BOOLEAN;
		dataToggleIn* : ARRAY 16 OF BOOLEAN;
		dataToggleOut* : ARRAY 16 OF BOOLEAN;
		maxPacketSizeIn* : ARRAY 16 OF INTEGER;
		maxPacketSizeOut* : ARRAY 16 OF INTEGER;
		bMaxPacketSize0* : INTEGER;
	END;

	(* host controller specific fields *)
	ConSpec* = POINTER TO RECORD
			qh* : LONGINT;		
			queue* : LONGINT;
	END; 

	(* interrupt handler *)
	IntHandler* = PROCEDURE {DELEGATE};

TYPE

	(** host controller driver object *)
	Hcd* = OBJECT (AosPlugins.Plugin)
	VAR
		(* used by the USB driver *)
		adrRange : ARRAY 128 OF BOOLEAN;
		
		active* : BOOLEAN;    (* controller has been initialized *)
		
		(* performance monitoring *)
		bytesTransfered* : HUGEINT;
	
		(** Operations concerning the root hub of this controller *)
		
		PROCEDURE EnablePort*(port : INTEGER);
		BEGIN
			HALT(301);  (* abstract *)
		END EnablePort;
		
		PROCEDURE DisablePort*(port: INTEGER);
		BEGIN
			HALT(301);  (* abstract *)
		END DisablePort;
		
		PROCEDURE GetPortStatus*(port : INTEGER):SET;
		BEGIN
			HALT(301);  (* abstract *)
		END GetPortStatus;
		
		PROCEDURE GetPortCount*():INTEGER;
		BEGIN
			HALT(301);  (* abstract *)
		END GetPortCount;

		(** Returns a unused address and marks it as used; address 0 is the host controller itself *)
		PROCEDURE GetFreeAddress*() : LONGINT;
		VAR
			adr : INTEGER;
		BEGIN
			FOR adr:= 1 TO 127 DO
				IF adrRange[adr] = FALSE THEN
					adrRange[adr] := TRUE;
					RETURN adr;
				END;
			END;
			RETURN 0;
		END GetFreeAddress;
	
		(** Marks the address <adr> as free *)
		PROCEDURE FreeAddress*(adr : LONGINT);
		BEGIN
			adrRange[adr] := FALSE;
		END FreeAddress;
	
		(** Operations concerning USB transfers *)	
		
			PROCEDURE ScheduleControl*(req : UsbTReq): SET;
		BEGIN
			HALT(301);  (* abstract *)
		END ScheduleControl;
			
			PROCEDURE ScheduleBulk*(req : UsbTReq): SET;
		BEGIN
			HALT(301);  (* abstract *)
		END ScheduleBulk;
	
		PROCEDURE ScheduleIsochronous*(req : UsbTReq): SET;
		BEGIN
			HALT(301);  (* abstract *)
		END ScheduleIsochronous;
			
		PROCEDURE ScheduleInterrupt*(req : UsbTReq):SET ;
		BEGIN
			HALT(301);  (* abstract *)
		END ScheduleInterrupt;

		(** Updates the status field of the USB transfer request <req> *)
			PROCEDURE ProbeTransfer*(req: UsbTReq);
		BEGIN
			HALT(301);  (* abstract *)
		END ProbeTransfer;
			
		(** Remove the USB transfer request <req> from the schedule of the host controller *)
			PROCEDURE DeleteTransfer*(req: UsbTReq);
		BEGIN
			HALT(301);  (* abstract *)
		END DeleteTransfer;
			
		(** Reactivate the interrupt transfer <req> (set the active bit in the transfer descriptors) *)
			PROCEDURE RestartInterrupt*(req: UsbTReq);
		BEGIN
			HALT(301);  (* abstract *)
		END RestartInterrupt;
		
		(** Interrupt handling *)					
			PROCEDURE AddIntHandler*(req: UsbTReq);
		BEGIN
			HALT(301); (* abstract *)
		END AddIntHandler;
			
			PROCEDURE RemoveIntHandler*(req: UsbTReq);
		BEGIN
			HALT(301); (* abstract *)
		END RemoveIntHandler;
		
	END Hcd;

VAR 
	controllers* : AosPlugins.Registry;
	
	(* used to build unique Plugin.name for host controller plugins *)
	controllerCount* : LONGINT;

PROCEDURE Cleanup;
BEGIN
	AosPlugins.main.Remove(controllers);
END Cleanup; 

BEGIN
	controllerCount:=0;
	AosModules.InstallTermHandler(Cleanup);
	NEW(controllers, "AosHcdi","USB host controller drivers"); 
END AosUsbHcdi.