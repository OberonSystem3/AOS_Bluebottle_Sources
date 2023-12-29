MODULE AosUsb;  (** AUTHOR "cplattner","staubesv"; PURPOSE "USB 1.1 driver"; *)
(**
		Aos USB driver

		Reference: http://www.usb.org

		30.09.2000 cp  first release
		17.10.2000 cp  Removed the oberon task (=> Import of Oberon and Input module not needed anymore)
		                         Usb.Connect will now be called from an other module periodically
		18.10.2000 cp  add new result code and two arrays for easier&faster access to the pipes maxpacketsizes,
		                         Usb.Info: some cosmetic changes (no long lines for Kernel.Log)
		20.10.2000 cp  modified "handy" helper procedures, so that they don't invite people to fragment the memory
        		                 (one has to pass an (empty) TReq record, this is not anymore allocated on the fly by Usb.Mod)
		10.11.2003 sst Changed driver model (added DriverManager), change style to OOP, new USB driver interface (USBDI)
*)

IMPORT SYSTEM, AosOut, AosKernel, AosMemory, AosUsbHcdi, AosPlugins, AosModules, UTF8Strings;

CONST

	(* status returned by transfer.GetStatus() and transfer.ProbeStatus() *)
	ResOK* = AosUsbHcdi.ResOK;
	ResNAK* = AosUsbHcdi.ResNAK;
	ResCRCTimeout* = AosUsbHcdi.ResCRCTimeout;
	ResBitStuff* = AosUsbHcdi.ResBitStuff;
	ResStalled* = AosUsbHcdi.ResStalled;
	ResDataBuffer* = AosUsbHcdi.ResDataBuffer;
	ResBabble* = AosUsbHcdi.ResBabble;
	ResShortPacket* = AosUsbHcdi.ResShortPacket;
	ResInProgress* = AosUsbHcdi.ResInProgress;
	ResInternal* = AosUsbHcdi.ResInternal;
	ResDisconnect* = AosUsbHcdi.ResDisconnect;


	(** Descriptor types for GetDescriptor & SetDesciptor USB standard requests *)
	DescriptorDevice* = 1;
	DescriptorConfiguration* = 2;	
	DescriptorString* = 3;
	DescriptorInterface* = 4;
	DescriptorEndpoint* = 5;
	
	DescriptorHub* = 29H;
	
	(** Recipients for GetFeature & SetFeature USB standard requests *)
	RecipientDevice* = 0;
	RecipientInterface* = 1;
	RecipientEndpoint* = 2;

	(** Standard feature selectors for GetFeature & SetFeature USB standard requests *)
	FeatureDeviceRemoteWakeup* = 1;
	FeatureEndpointHalt* = 0;
	
	(* name and description of the integrated USB (root) hub driver *)
	DriverName = "UsbHub";
	DriverDescription = "integrated USB hub driver";
	
	NameRootHub = "UsbRootHub";
	DescriptionRootHub = "integrated USB root hub driver";
	
	(* Constants for the bRequest field of the USB device standard requests, see USB Specification Rev 1.1, p. 187 *)
	CommandGetStatus = 0;
	CommandClearFeature = 1;
	CommandSetFeature = 3;
	CommandSetAddress = 5;
	CommandGetDescriptor = 6;
	CommandSetDescriptor = 7;
	CommandGetConfiguration = 8;
	CommandSetConfiguration = 9;
	CommandGetInterface = 10;
	CommandSetInterface = 11;
	CommandSynchFrame = 12;
	
	(* LANGID codes used by string descriptors, see HID page on www.usb.org *)
	IdUserDefault = 0400H;
	IdSystemDefault = 0800H;
	IdEnglishUS = 0409H;
	IdEnglishUK = 0809H;

	(* send buffers *)
	BufferSize = 64 * 1024;
	
	(* intervall in ms between ConnectHub calls for UsbRootHubDriver objects *) 
	PollingInterval = 100;
	MaxPortStatusErrors = 10;
	
	Debug = TRUE;
	
	(* driver manager constants *)
	DmMaxPriorities = 12; 
	
	(* enable debug infos for driver manager object *)
	DmTrace = TRUE; 

	ShowStrings = TRUE;
	
TYPE

	Name* = AosPlugins.Name;
	Description* = AosPlugins.Description;
	
TYPE
	
	(** USB device driver interface *)
	UsbDriver* = OBJECT (AosPlugins.Plugin)
	VAR
		device* : UsbDevice;  (* USB device which is controlled by this driver *)
		interface* : LONGINT; (* interface to which this driver instance is bound *)

		(** Connect is called by the USB driver when an instance of the USB device driver is installed *)
		PROCEDURE Connect*;
		BEGIN
			HALT(301);  (*abstract *)
		END Connect;

		(** Disconnect is called by the USB driver when the instance of this driver is de-installed (module unloading or device disconnection) *)
		PROCEDURE Disconnect*;
		BEGIN
			HALT(301);  (* abstract *)
		END Disconnect;
		
		PROCEDURE &Init(dev : UsbDevice; intfc : LONGINT);
		BEGIN
			ASSERT(dev#NIL);
			device := dev;
			interface := intfc;
		END Init;
		
	END UsbDriver;
	
TYPE

	String = ARRAY 256 OF CHAR;
	
TYPE

	(** UsbDeviceDescriptor: As specified in the Universal Serial Bus Specification 1.1/2.0 **)
	UsbDeviceDescriptor = POINTER TO RECORD
		bcdUSB* : INTEGER;
		bDeviceClass* : INTEGER;
		bDeviceSubClass* : INTEGER;
		bDeviceProtocol* : INTEGER;
		bMaxPacketSize0* : INTEGER;
		idVendor* : INTEGER;
		idProduct* : INTEGER;
		bcdDevice* : INTEGER;
		iManufacturer* : INTEGER;
		iProduct* : INTEGER;
		iSerialNumber* : INTEGER;
		bNumConfigurations* : INTEGER;
	END;

TYPE
	
	(** As specified in the Universal Serial Bus Specification 1.1/2.0 **)
	UsbDeviceConfiguration = POINTER TO RECORD
			wTotalLength* : INTEGER;
			bNumInterfaces* : INTEGER;
			bConfigurationValue* : INTEGER;
			iConfiguration* : INTEGER;
			bmAttributes* : SET;
			maxPower* : INTEGER;
			interfaces* : POINTER TO ARRAY OF UsbDeviceInterface;
	END;
	
TYPE
	
	(** UsbDeviceInterface: As specified in the Universal Serial Bus Specification 1.1/2.0
		Oberon Usb addition: "Driver" points to the device driver for this interface, NIL means no driver (yet) attached
		to this interface  **)
	UsbDeviceInterface* = POINTER TO RECORD
			bInterfaceNumber* : INTEGER;
			bAlternateSetting* : INTEGER;
			bNumEndpoints* : INTEGER;
			bInterfaceClass* : INTEGER;
			bInterfaceSubClass* : INTEGER;
			bInterfaceProtocol* : INTEGER;
			iInterface* : INTEGER;
			numAlternateInterfaces*: INTEGER;
			alternateInterfaces*: POINTER TO ARRAY OF UsbDeviceInterface;
			endpoints* : POINTER TO ARRAY OF UsbDeviceEndpoint;
			driver* : UsbDriver;
	END;

TYPE
	
	(** UsbDeviceEndpoint: As specified in the Universal Serial Bus Specification 1.1/2.0 **)
	UsbDeviceEndpoint = POINTER TO RECORD
			bEndpointAddress* : INTEGER;
			bmAttributes* : SET;
			wMaxPacketSize* : INTEGER;
			bInterval* : INTEGER;
	END;

TYPE

	UsbDevice* = OBJECT
	VAR
		(* information reported by string descriptors *)
		 sManufacturer-, sProduct-, sSerialNumber- : String; 

		(* USB device specific *)	
		descriptor* : UsbDeviceDescriptor;
		configurations* : POINTER TO ARRAY OF UsbDeviceConfiguration;
		actConfiguration* : UsbDeviceConfiguration;
		
		(* for internal uses *)
		port : INTEGER;
		parent : UsbDevice;
		hubFlag : BOOLEAN;
		
		(* USB hub specific fields *)
		ports : INTEGER;
		hubTime2Good : INTEGER;
		hubPortDevices : POINTER TO ARRAY OF UsbDevice;
		hubPortPermanentDisabled : POINTER TO ARRAY OF BOOLEAN;
		
		(* this record is used to interface with AosUsbHcdi UsbTReqs (device specific data) *)
		data* : AosUsbHcdi.DevSpec;

		(* private, exported readonly to grant access to bytesTransfered field of the controller *)
		controller* : AosUsbHcdi.Hcd;
		
			(* register this USB device at the USB hub <hub> *)
		PROCEDURE Register(hub: UsbDevice; port : INTEGER);
		BEGIN
			ASSERT(hub.hubFlag); 
			parent := hub;
			hub.hubPortDevices[port] := SELF;
		END Register;
		
		(* remove this device from the hub it is connected to and remove its driver if installed *)
		PROCEDURE Remove;
		VAR
			n : INTEGER;
			res : BOOLEAN;
		BEGIN
			IF hubFlag THEN
				FOR n:=0 TO ports - 1 DO
					IF hubPortDevices[n] # NIL THEN
						hubPortDevices[n].Remove;
						hubPortDevices[n] := NIL;
						IF parent = SELF THEN (* root hub: only disable ports on root hubs *) controller.DisablePort(n); END;  
					END;
				END;
				drivers.RemoveInstance(actConfiguration.interfaces[0].driver.name);
			ELSE
				FOR n:=0 TO actConfiguration.bNumInterfaces - 1 DO
					IF actConfiguration.interfaces[n].driver # NIL THEN (* remove device driver instance *)
						drivers.RemoveInstance(actConfiguration.interfaces[n].driver.name);
						actConfiguration.interfaces[n].driver:=NIL;
					END;
				END; 
			END;
			controller.FreeAddress(data.address);
		END Remove;
		
		(** USB conrtol transfer *)
		
		(** timeout:   -1  :  blocking transfer
								 0  :  non-blocking transfer
								>1 :  blocking transfer with timeout [ms]  *)
								 
		PROCEDURE SendControl*(endpoint : INTEGER; VAR msg : ARRAY OF CHAR; VAR buf : ARRAY OF CHAR; ofs, len, timeout : LONGINT) : UsbTransfer;
		VAR
			ugly0, ugly1 : POINTER TO ARRAY OF CHAR;
			uglyPhys0, uglyPhys1: LONGINT;
			transfer : UsbTransfer;
			req : AosUsbHcdi.UsbTReq;
			i : LONGINT;
		BEGIN 

			IF LEN(buf) < (len + ofs)  THEN
				AosOut.String("AosUsb: SendControl: buffer too short"); AosOut.Ln;
				HALT(303);
			END;
	
			NEW(ugly0, 8); uglyPhys0 := AosMemory.PhysicalAdr(SYSTEM.ADR(ugly0[0]), 8);
			NEW(ugly1, BufferSize); uglyPhys1 := AosMemory.PhysicalAdr(SYSTEM.ADR(ugly1[0]), 1024);
			ASSERT(len <= BufferSize);
			
			SYSTEM.MOVE(SYSTEM.ADR(buf[ofs]), uglyPhys1, len);
			SYSTEM.MOVE(SYSTEM.ADR(msg[0]), uglyPhys0, 8);   
			
			NEW(req);
			req.device := data; 
			req.endpoint := endpoint;
			req.typ := AosUsbHcdi.TransferControl;
			req.buffer := uglyPhys1;  

			req.bufferLen := len;
			req.controlMessage := uglyPhys0; 

			req.timeout := timeout;
	
			IF controller.active THEN 
				req.status:=controller.ScheduleControl(req); 
			ELSE
				req.status:=AosUsbHcdi.ResDisconnect; 
			END; 
	
			SYSTEM.MOVE(uglyPhys1, SYSTEM.ADR(buf[ofs]), len); 
			
			NEW(transfer, controller, SELF, req);
			
			RETURN transfer;
		END SendControl;
		
		(** USB interrupt transfer *)
		PROCEDURE SendInterrupt*(endpoint: INTEGER; VAR buf : ARRAY OF CHAR; ofs, len, timeout : LONGINT; irqintervall : INTEGER) : UsbTransfer;
		VAR	
			req : AosUsbHcdi.UsbTReq;
			transfer : UsbTransfer;
			i : LONGINT;
		BEGIN 
			IF LEN(buf) < (len + ofs)  THEN 
				AosOut.String("AosUsb: SendInterrupt: buffer too short"); AosOut.Ln;
				HALT(303);
			END;
			
			IF len > 1280 THEN (* maximum transfer length for USB 1.1 Host Controllers: 1280 Bytes *)
				AosOut.String("AosUsb: SendInterrupt: Transfers are restricted to a maximum of 1280 Bytes"); AosOut.Ln;
				HALT(303);
			END;
		
			NEW(req); 
			req.device:=data;
			req.endpoint := endpoint;
			req.typ := AosUsbHcdi.TransferInterrupt;
			req.buffer := SYSTEM.ADR(buf[ofs]);
			req.bufferLen := len;
			req.timeout := timeout;
			req.irqInterval := irqintervall;
			
			IF controller.active THEN 
				req.status:=controller.ScheduleInterrupt(req); 
			ELSE
				req.status:=AosUsbHcdi.ResDisconnect 
			END; 
						
			NEW(transfer, controller, SELF, req);
	
			RETURN transfer;
		END SendInterrupt;
		
		(** USB bulk transfer *)
		PROCEDURE SendBulk*(endpoint : INTEGER; VAR buf : ARRAY OF CHAR; ofs, len, timeout : LONGINT) : UsbTransfer;
		VAR
			ugly0, ugly1 : POINTER TO ARRAY OF CHAR;
			uglyPhys0, uglyPhys1: LONGINT;
			req : AosUsbHcdi.UsbTReq;
			transfer : UsbTransfer;
		BEGIN 
	
			IF LEN(buf) < (len + ofs)  THEN
				AosOut.String("AosUsb: SendBulk: buffer too short"); AosOut.Ln;
				HALT(303);
			END;
	
			NEW(ugly1, BufferSize); uglyPhys1 := AosMemory.PhysicalAdr(SYSTEM.ADR(ugly1[0]), 1024);
			ASSERT(len <= BufferSize);
			SYSTEM.MOVE(SYSTEM.ADR(buf[ofs]), uglyPhys1, len);
		
			NEW(req);
			req.device:=data;
			req.endpoint := endpoint;
			req.typ := AosUsbHcdi.TransferBulk;
			req.buffer := uglyPhys1;
			req.bufferLen := len;
			req.timeout := timeout;
			
			IF controller.active THEN 
				req.status:=controller.ScheduleBulk(req); 
			ELSE
				req.status:=AosUsbHcdi.ResDisconnect 
			END; 

			SYSTEM.MOVE(uglyPhys1, SYSTEM.ADR(buf[ofs]), len);
			
			NEW(transfer, controller, SELF, req);
	
			RETURN transfer;
	
		END SendBulk;
		
		(** Calls Clearfeature(FeatureEndpointHalt, RecipientEndpoint, endpoint) and resets dataToggle. Use to clear pipe stalls *)
		PROCEDURE ClearHalt*(endpoint : INTEGER) : BOOLEAN;
		VAR
			message : ARRAY 8 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			IF (SYSTEM.VAL(SET, endpoint) * {7}) = {} THEN
				data.dataToggleOut[endpoint MOD 16] := FALSE;
			ELSE
				data.dataToggleIn[endpoint MOD 16] := FALSE;
			END;
			BuildMessage(2, CommandClearFeature, FeatureEndpointHalt, endpoint, 0, message);
			transfer := SendControl(0, message, message, 0, 0, 500);
			RETURN transfer.ResOK();
		END ClearHalt;
		
		(** Implementation of the USB standard device requests, see USB Specification Rev 1.1, p. 185 *)

		(** This request is used to clear or disable a specific feature *)
		PROCEDURE ClearFeature*(feature, recipient, recipientNumber : LONGINT) : BOOLEAN;  (* UNTESTED *)
		VAR
			message : ARRAY 8 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(recipient, CommandClearFeature, feature, recipientNumber, 0, message);
			transfer := SendControl(0, message, message, 0, 0, 500);
			RETURN transfer.ResOK();
		END ClearFeature;
		
		(** This request is used to set or enable a specific feature *)
		PROCEDURE SetFeature*(feature, recipient, recipientNumber : INTEGER) : BOOLEAN;  (* UNTESTED *)
		VAR
			message : ARRAY 8 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(recipient, CommandSetFeature, feature, recipientNumber, 0, message);
			transfer := SendControl(0, message, message, 0, 0, 500);
			RETURN transfer.ResOK();
		END SetFeature;
		
		(** Sets the address of the USB device dev to adr (should only be used by the USB driver) *)
		PROCEDURE SetAddress*(adr : LONGINT) : BOOLEAN;
		VAR
			message : ARRAY 8 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(0, CommandSetAddress, adr, 0, 0, message);
			transfer := SendControl(0, message, message, 0, 0, 5000);
			IF transfer.ResOK() THEN data.address := adr END;
			RETURN transfer.ResOK();
		END SetAddress;
		
		(** This requests returns the current device configuration value. If the returned value is zero, the device is not configured. *)  
		PROCEDURE GetConfiguration*(VAR conf : LONGINT) : BOOLEAN; (* UNTESTED *)
		VAR
			message : ARRAY 8 OF CHAR;
			buffer : ARRAY 1 OF CHAR;
			i,e, eadr : INTEGER;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(128, CommandGetConfiguration, 0, 0, 1, message);
			transfer := SendControl(128, message, buffer, 0, 0, 500);
			IF transfer.ResOK() THEN conf := ORD(buffer[0]); ELSE conf := -1; END;
			RETURN transfer.ResOK();
		END GetConfiguration;

		(** This requests sets the device configuration *)
		PROCEDURE SetConfiguration*(conf : INTEGER) : BOOLEAN;
		VAR
			message : ARRAY 8 OF CHAR;
			i,e, eadr : INTEGER;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(0, CommandSetConfiguration, configurations[conf].bConfigurationValue, 0, 0, message);
			
			transfer := SendControl(0, message, message, 0, 0, 2000);
		
			IF transfer.ResOK() THEN
				actConfiguration := configurations[conf];
		
				data.maxPacketSizeOut[0] := descriptor.bMaxPacketSize0;
				data.maxPacketSizeIn[0] := descriptor.bMaxPacketSize0;
		
				FOR i := 0 TO actConfiguration.bNumInterfaces - 1 DO
					FOR e:= 0 TO actConfiguration.interfaces[i].bNumEndpoints - 1 DO
						eadr := actConfiguration.interfaces[i].endpoints[e].bEndpointAddress;
						IF SYSTEM.VAL(SET, eadr) * {7} = {} THEN
							data.maxPacketSizeOut[eadr MOD 16] := actConfiguration.interfaces[i].endpoints[e].wMaxPacketSize;
						ELSE
							data.maxPacketSizeIn[eadr MOD 16] := actConfiguration.interfaces[i].endpoints[e].wMaxPacketSize;
						END;
					END;
				END;
			END;
			RETURN transfer.ResOK();
		END SetConfiguration;
		
		(** This request returns the specified descriptor if the descriptor exists *)
			PROCEDURE GetDescriptor*(typ, descriptor, index, wIndex, len : LONGINT; VAR buf : ARRAY OF CHAR) : BOOLEAN;
		VAR
			message : ARRAY 8 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(typ, CommandGetDescriptor, index + descriptor*100H, wIndex, len, message);
			transfer := SendControl(128, message, buf, 0, len, 2000);
			RETURN transfer.ResOK();
		END GetDescriptor;
		
		(** This request may be used to update existing descriptors or new descriptors may be added *)
			PROCEDURE SetDescriptor*(type, index, wIndex, len : LONGINT; VAR buf : ARRAY OF CHAR) : BOOLEAN;
		VAR
			message : ARRAY 8 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(0, CommandGetDescriptor, index + 100H*type, wIndex, len, message);
			transfer := SendControl(0, message, buf, 0, len, 2000);
			RETURN transfer.ResOK();
		END SetDescriptor;
		
		(** This request returns the selected alternate settings for the specified interface *)
		PROCEDURE GetInterface*(interface : LONGINT; VAR setting : LONGINT): BOOLEAN;  (* UNTESTED *)
		VAR 
			message : ARRAY 8 OF CHAR;
			data : ARRAY 1 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(128+1, CommandGetInterface, 0, interface, 1, message);
			transfer := SendControl(128, message, data, 0, 1, 2000);
			IF transfer.ResOK() THEN setting := ORD(data[0]); END;
			RETURN transfer.ResOK();
		END GetInterface; 
		
		(** This requests allows the host to select an alternate setting for the specified interface *)
		PROCEDURE SetInterface*(interface, setting : LONGINT): BOOLEAN;  (* UNTESTED *)
		VAR 
			message : ARRAY 8 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(1, CommandSetInterface, setting, interface, 0, message);
			transfer := SendControl(0, message, message, 0, 0, 2000);
			RETURN transfer.ResOK();
		END SetInterface; 
		
		(** This request returns status for the specified recipient *)
		PROCEDURE GetStatus*(recipient, recipientNumber: LONGINT; VAR setting : LONGINT): BOOLEAN;  (* UNTESTED *)
		VAR 
			message : ARRAY 8 OF CHAR;
			data : ARRAY 2 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(128+recipient, CommandGetStatus, 0, recipientNumber, 2, message);
			transfer := SendControl(128, message, data, 0, 2, 2000);
			IF transfer.ResOK() THEN setting := ORD(data[0]) + ORD(data[1])*100H;  END;
			RETURN transfer.ResOK();
		END GetStatus; 

		(** This request is used to set and then report an endpoint's synchronization frame *)
		PROCEDURE SynchFrame*(endpoint: LONGINT; VAR frameNumber : LONGINT): BOOLEAN;  (* UNTESTED *)
		VAR 
			message : ARRAY 8 OF CHAR;
			data : ARRAY 2 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			BuildMessage(128+2, CommandSynchFrame, 0, endpoint, 2, message);
			transfer := SendControl(128, message, data, 0, 2, 2000);
			IF transfer.ResOK() THEN frameNumber := ORD(data[0]) + ORD(data[1])*100H;  END;
			RETURN transfer.ResOK();
		END SynchFrame; 

		(* For internal use (USB driver). See USB Specification Rev 1.1, p. 183 *)
		PROCEDURE BuildMessage*(bmRequestType, bRequest, wValue, wIndex, wLength : LONGINT; VAR message :  ARRAY OF CHAR);
		BEGIN
			message[0] := CHR(bmRequestType);   
			message[1] := CHR(bRequest);		
			message[2] := CHR(wValue); 
			message[3] := CHR(SYSTEM.LSH(wValue, -8)); 
			message[4] := CHR(wIndex);										  
			message[5] := CHR(SYSTEM.LSH(wIndex,-8));
			message[6] := CHR(wLength); 
			message[7] := CHR(SYSTEM.LSH(wLength, -8));
		END BuildMessage;
		
	END UsbDevice;

TYPE

	ProbeProc = PROCEDURE {DELEGATE} (dev: UsbDevice; intfc : LONGINT): UsbDriver;

TYPE

	UsbTransfer* = OBJECT
	VAR
		controller : AosUsbHcdi.Hcd; 
		device : UsbDevice;
		req : AosUsbHcdi.UsbTReq;
	
		(** Delete this transfer from the host controllers schedule *)
		PROCEDURE Delete*;
		BEGIN
			IF req.intHandler#NIL THEN (* remove interrupt handler at host controller *)
				req.active := FALSE;
				controller.RemoveIntHandler(req);
			END;
			controller.DeleteTransfer(req);
		END Delete;
		
		(** Clears the EndpointHalt feature, i.e. clear a stalled endpoint *)
		PROCEDURE ClearHalt*() : BOOLEAN;
		BEGIN
			RETURN device.ClearHalt(req.endpoint);
		END ClearHalt;

		(** Reactivate an interrupt transfer *)
		PROCEDURE Restart*;
		BEGIN
			ASSERT(req.typ=AosUsbHcdi.TransferInterrupt);
			req.active := TRUE;
			controller.RestartInterrupt(req);
		END Restart;

		(** Probe the status of the transfer and return it *)
		PROCEDURE ProbeStatus*(): SET;
		BEGIN
			controller.ProbeTransfer(req);
			RETURN req.status;
		END ProbeStatus;
		
		(** Return the status of this transfer *)
		PROCEDURE GetStatus*(): SET;
		BEGIN
			RETURN req.status;
		END GetStatus;

		(** Set the status of this transfer *)
		PROCEDURE SetStatus*(status : SET);
	 	BEGIN
 			req.status:= SYSTEM.VAL(SET, status);
		END SetStatus;

		(** TRUE if status is ResOK *)
		PROCEDURE ResOK*():BOOLEAN;
 		BEGIN
 			RETURN req.status = AosUsbHcdi.ResOK;
 		END ResOK;
 		
 		PROCEDURE TransferedBytes*() : LONGINT;
 		BEGIN
 			RETURN req.bufferLen;
 		END TransferedBytes;
 		
		(** Set interrupt handler for this transfer *)
		PROCEDURE SetIntHandler*(proc : AosUsbHcdi.IntHandler);
			BEGIN
			ASSERT((proc#NIL) & (req.intHandler=NIL));   (*   & (req.typ=AosUsbHcdi.TransferInterrupt)); *)
			req.intHandler:=proc;		
			req.active := TRUE;	
			controller.AddIntHandler(req);	
		END SetIntHandler;

		(** Remove interrupt handler for this transfer *)
		PROCEDURE RemoveIntHandler*;
		BEGIN
			ASSERT((req.intHandler#NIL) & (req.typ=AosUsbHcdi.TransferInterrupt));	
			req.intHandler:=NIL;
			controller.RemoveIntHandler(req);
		END RemoveIntHandler;
		
		(** debug: display status information of this USB transfer to KernelLog *)
		PROCEDURE ShowStatus*;
		BEGIN
			AosOut.String("AosUsb.Transfer.ShowStatus: "); AosOut.Ln;
			AosOut.String("  Transfer type: ");
			ASSERT(req#NIL);
			IF req.typ = AosUsbHcdi.TransferInterrupt THEN AosOut.String("Interrupt");
			ELSIF req.typ = AosUsbHcdi.TransferControl THEN AosOut.String("Control");
			ELSIF req.typ = AosUsbHcdi.TransferBulk THEN AosOut.String("Bulk");
			ELSIF req.typ = AosUsbHcdi.TransferIsochronous THEN AosOut.String("Isochronous");
			ELSE AosOut.String("Unknown");
			END;
			AosOut.String("   Endpoint: "); AosOut.Int(req.endpoint MOD 16,0); AosOut.String(" ("); 
			IF (SYSTEM.VAL(SET, req.endpoint) * {7}) = {} THEN AosOut.String("OUT"); ELSE AosOut.String("IN"); END; AosOut.String(")");
			AosOut.Ln;
			AosOut.String("  status: ");
			IF (req.status * AosUsbHcdi.ResOK) # {} THEN AosOut.String("[OK]"); END;
			IF (req.status * ResNAK) # {} THEN AosOut.String("[NAK]"); END;
			IF (req.status * ResCRCTimeout) # {} THEN AosOut.String("[CRC/Timeout]"); END;
			IF (req.status * ResBitStuff) # {} THEN AosOut.String("[BitStuff]"); END;
			IF (req.status * ResStalled) # {} THEN AosOut.String("[Stalled]"); END;
			IF (req.status * ResDataBuffer) # {} THEN AosOut.String("[DataBuffer]"); END;
			IF (req.status * ResBabble) # {} THEN AosOut.String("[Babble]"); END;
			IF (req.status * ResShortPacket) # {} THEN AosOut.String("[ShortPacket]"); END;
			IF (req.status * ResInProgress) # {} THEN AosOut.String("[InProgress]"); END;
			IF (req.status * ResDisconnect) # {} THEN AosOut.String("[DisConnect]"); END;
			AosOut.Ln; 
			AosOut.String("  transfer size: "); AosOut.Int(req.bufferLen,0); AosOut.String(" Bytes"); 
			AosOut.Ln;
		END ShowStatus;
		
			PROCEDURE &Init(con : AosUsbHcdi.Hcd; dev : UsbDevice; transferReq : AosUsbHcdi.UsbTReq);
		BEGIN
			ASSERT((con#NIL) & (transferReq#NIL));
			controller := con;
			req := transferReq;
			device := dev;
		END Init;

	END UsbTransfer;
	
TYPE
	(* only used by the DriverManager *)
	RegisteredDriver = POINTER TO RECORD
			probe : ProbeProc;
		name : AosPlugins.Name;
		desc : AosPlugins.Description;
		usedSuffix : ARRAY 100 OF BOOLEAN;  (* which numbers are used for the unique names *)
		next : RegisteredDriver;
	END;
	
TYPE	
	(* This object manages drivers *)
	DriverManager = OBJECT
	VAR
		(* see USB Common Class Specification, 3.10 Locating USB Drivers *)
		drivers : ARRAY DmMaxPriorities OF RegisteredDriver;
		
		(* For each interface of the USB device <dev> try to install a registered driver; called when a new USB device is found *)
		PROCEDURE ProbeDevice(dev : UsbDevice);
		VAR
			n : INTEGER;
		BEGIN
			FOR n:=0 TO dev.actConfiguration.bNumInterfaces - 1 DO
				IF dev.actConfiguration.interfaces[n].driver = NIL THEN
					(* probe all device drivers and install a driver instance if a driver for the device is registered *)
					Install(dev, n);
				END;
			END;
		END ProbeDevice;

		(* Checks whether an appropriate driver for the USB device <dev> is registred in registredDrivers.
			If yes, a unique AosPlugins.Name is generated and the driver is added to the usbDrivers registry *)
		PROCEDURE Install(dev : UsbDevice; intfc : LONGINT);
		VAR
			temp : RegisteredDriver;
			drv : UsbDriver;
			i, res : LONGINT;
			name : AosPlugins.Name;
			suffix : LONGINT;  (* 0-99;  suffix is used to generate unique names for AosPlugin.Name *)
		BEGIN
		
			(* search a USB device driver for this device (See USB Common Class Specification, 3.10 Locating USB Drivers) *)
			drv:=NIL;
			
			i := 0;
			LOOP
				temp := drivers[i].next;
				LOOP
					IF temp=NIL THEN (* no more drivers available *) EXIT; END;
					drv := temp.probe(dev, intfc);
					IF drv#NIL THEN (* driver found *) EXIT; END;
					temp := temp.next;
				END;
				
				IF (drv#NIL) THEN (* driver found *) EXIT;  END;
				INC(i); IF (i >= DmMaxPriorities) THEN (* no driver available *) EXIT; END;
			END;
			
			IF drv#NIL THEN (* driver found;  generate a unique name for the instance of this driver to be created *)
				
				(* search first unused suffix *)
				i := 0; WHILE (temp.usedSuffix[i]=TRUE) & (i<=99) DO INC(i); END;
				
				IF (i=99) & (temp.usedSuffix[99]=TRUE) THEN
					AosOut.String("AosUsb: no more than 99 instances of a driver supported"); AosOut.Ln;
					RETURN;
				ELSE
					temp.usedSuffix[i] := TRUE;
					suffix := i;
				END;
				
				name := AddSuffix(temp.name, suffix);
				
				drv.SetName(name);
				drv.desc:=temp.desc;
				
				(* add this driver to the usbDrivers registry *)
				usbDrivers.Add(drv, res); 
		
				IF res#AosPlugins.Ok THEN
				
					AosOut.String("AosUsb: Couldn't register USB device driver at usbDrivers"); AosOut.Ln;
					temp.usedSuffix[suffix]:=FALSE;
					
				ELSE (* USB device driver successfully registered *)
				
					dev.actConfiguration.interfaces[intfc].driver:=drv;
	
					IF dev.hubFlag THEN 
						drv(UsbHubDriver).ConnectHub; 
					ELSE 
						drv.Connect;
					END;
	
					IF DmTrace & Debug THEN AosOut.String("AosUsb: Registered USB device driver: "); AosOut.String(name); AosOut.Ln; END;
				END;
			END;
		END Install;
		
		(** Add a USB device driver to the internal registry. Driver names have to be unique and no longer than 30 characters (incl. Null-String) *)
		PROCEDURE Add*(probe : ProbeProc; name: AosPlugins.Name; desc: AosPlugins.Description; priority : LONGINT);
		VAR
			temp, new : RegisteredDriver;
			i : LONGINT;
			
			(* For all USB devices which are attached to any USB root hub in the system the procedure ProbeDeviceChain() is called *)
			PROCEDURE ProbeDrivers;
			VAR
				temp : UsbRootHubDriver;
			BEGIN
				temp:=rootHubs;
				WHILE(temp#NIL) DO
					ProbeDeviceChain(temp.device); 
					temp:=temp.nextRootHub;
				END;
			END ProbeDrivers;
	
			(* Called by ProbeDrivers; calls Install() for all devices which don't already have a driver instance installed *)
			PROCEDURE ProbeDeviceChain(dev : UsbDevice);
			VAR
				n : INTEGER;
			BEGIN
				
				IF dev.hubFlag THEN
					FOR n:=0 TO dev.ports - 1 DO
						IF dev.hubPortDevices[n] # NIL THEN ProbeDeviceChain(dev.hubPortDevices[n]); END;
					END;
				ELSE
					FOR n:=0 TO dev.actConfiguration.bNumInterfaces - 1 DO
							IF dev.actConfiguration.interfaces[n].driver = NIL THEN
								(* probe all device drivers and install a driver instance if a driver for the device is registered *)
								Install(dev, n);
							END;
					END;
				END;
			END ProbeDeviceChain;
			
		BEGIN 
            (* first test whether the parameters passed to Add() are valid *)
            		
			(* name mustn't be longer than 30 characters (including 0X) *)
			i:=0; WHILE (name[i]#0X) & (i<32) DO INC(i); END;
			
			IF (i>29) OR (name="")  THEN 
				AosOut.String("AosUsb: Couldn't add driver (name NULL or longer than 30 characters or not NULL-terminated)"); AosOut.Ln; 
				RETURN; 
			END;
			
			(* priority must be in the interval [0,11] *)
			IF (priority>11) OR (priority<0) THEN 
				AosOut.String("AosUsb: Couldn't add driver (0<=priority<=11 does not hold)"); AosOut.Ln;
				RETURN;
			END;
			
			(* check whether there is no driver with the name <name> registered *)
			FOR i := 0 TO DmMaxPriorities -1 DO
				temp := drivers[i].next;
				WHILE (temp#NIL) DO 
					IF temp.name=name THEN 
						AosOut.String("AosUsb: Couldn't add driver (driver name already registered)"); AosOut.Ln;
						RETURN;
					END;
					temp := temp.next;
				END;
			END;
			
			(* okay, arguments are valid, create RegisteredDriver object and add it to internal registry *)
			NEW(new);
			new.probe := probe;
			new.name := name;
			new.desc := desc;
			new.next := drivers[priority].next;
			
			FOR i:=0 TO 99 DO new.usedSuffix[i]:=FALSE; END;

			drivers[priority].next := new;
			
			(* maybe a USB device is already attached, just waiting for this driver: check! *)
			ProbeDrivers;  
			
			IF DmTrace THEN AosOut.String("AosUsb: Driver "); AosOut.String(name); AosOut.String(" has been added."); AosOut.Ln; END;
		END Add;
		
		(* Removes a device driver instance from usbDriver registry; only used by the USB driver itself*)
		PROCEDURE RemoveInstance(name : AosPlugins.Name);
		VAR
			plugin : AosPlugins.Plugin;
			regname : AosPlugins.Name;
			temp : RegisteredDriver;
			i, suffix : LONGINT;
		BEGIN
			plugin:=usbDrivers.Get(name);
			
			IF plugin#NIL THEN (* uninstall this instance *)
				
					(* get the name of the registered device driver which generates this instances *)
					i := 0; WHILE name[i]#0X DO regname[i]:=name[i]; INC(i); END; 
					regname[i-1] := 0X; regname[i-2] := 0X;
				
					suffix:=GetSuffix(name); 
				
					plugin(UsbDriver).Disconnect;
					usbDrivers.Remove(plugin);				
	
					(* need to update usedSuffix at the registered driver *)
					i := 0;
					LOOP
						temp := drivers[i].next;
						WHILE (temp#NIL) & (temp.name#regname) DO temp:=temp.next; END;
						
						IF temp#NIL THEN (* registered device driver found *)
							temp.usedSuffix[suffix]:=FALSE;
							EXIT;
						END;
						
						INC(i); IF (i >= DmMaxPriorities) THEN (* no driver found *) EXIT; END;
					END;
				
					IF (i = 11) & (temp=NIL) THEN (* registered driver for this instance was not found *)
						 AosOut.String("AosUsb: couldn't find registered driver of the removed driver instance"); AosOut.Ln;
					END;

			ELSE (* no such instance found *)
				AosOut.String("AosUsb: Warning: Couldn't remove driver instance (no instance found)"); AosOut.Ln;
			END;	 	
			
		END RemoveInstance;
		
		(** Calls Disconnect of all instances of the driver. All instances are removed from the usbDrivers registry 
			and the device driver is removed from the internal registry  *)
		PROCEDURE Remove*(name : AosPlugins.Name);
		VAR
			prev, temp : RegisteredDriver; 
			regname : AosPlugins.Name;
			plugin : AosPlugins.Plugin;
			dev : UsbDevice;
			i, j : LONGINT;
		BEGIN
			IF Debug THEN AosOut.String("AosUsb: Removing driver: "); AosOut.String(name); AosOut.Ln; END;
		
			(* remove device driver from internal registry *)
			i := 0;
			LOOP
				prev := drivers[i];
				temp := drivers[i].next;
				WHILE (temp#NIL) & (temp.name#name) DO temp := temp.next; prev := prev.next; END;
				IF temp#NIL THEN (* driver found *) EXIT; END;
				INC(i); IF (i >= DmMaxPriorities) THEN (* no driver available *) EXIT; END;
			END;
			
			(* remove driver from internal registry and remove all its instances *)
			IF temp#NIL THEN 
			
					(* remove driver from internal registry *)
					prev.next := temp.next; 
					
					(* remove all instances of the driver *)
					FOR i:=0 TO 99 DO
							
							IF temp.usedSuffix[i]=TRUE THEN (* driver instance found *)
					
								(* get plugin name *)
								regname := AddSuffix(temp.name, i); 
								plugin := usbDrivers.Get(regname);
						
								IF plugin=NIL THEN 
									AosOut.String("AosUsb: Error while trying to remove driver from usbDrivers registry"); AosOut.Ln;
								ELSE;
									plugin(UsbDriver).Disconnect;
									dev := plugin(UsbDriver).device;
									
												IF dev#NIL THEN (* remove link to driver instance from USB device *)
										FOR j:=0 TO dev.actConfiguration.bNumInterfaces-1 DO
											IF dev.actConfiguration.interfaces[i].driver = plugin(UsbDriver) THEN 
												dev.actConfiguration.interfaces[i].driver := NIL; 
											END;
										END;
									END;
									usbDrivers.Remove(plugin);
									temp.usedSuffix[i]:=FALSE;
								END;
							END;
					END;
			ELSE
				AosOut.String("AosUsb: Warning: Couldn't remove driver ");
				AosOut.String(name); AosOut.Ln;				
			END;
			
		END Remove;

		(* Appends the suffix to name; the suffix is a number between 0-99 which is added as 2 ASCII characters (each 1 bytes) 
			note: name mustn't be longer than 30 characters (incl. Null-Termination)  *)
		PROCEDURE AddSuffix(name: AosPlugins.Name; suffix : LONGINT): AosPlugins.Name;
		VAR
			i : LONGINT;
			newName : AosPlugins.Name;
		BEGIN
			i:=0; WHILE name[i]#0X DO newName[i]:=name[i]; INC(i); END;
				
			(* append suffix to name *)
			IF suffix < 10 THEN 
				newName[i]:="0";
				newName[i+1]:=CHR(suffix+48);
				newName[i+2]:=0X;
			ELSE
				newName[i]:=CHR((suffix DIV 10)+48);
				newName[i+1]:=CHR((suffix MOD 10)+48);
				newName[i+2]:=0X;
			END;
			RETURN newName;
			
		END AddSuffix;
		
		(* returns the suffix of the AosPlugins.Name name *)
		PROCEDURE GetSuffix(name : AosPlugins.Name):LONGINT;
		VAR
			i, suffix : LONGINT;
		BEGIN
			i :=0; WHILE (name[i]#0X) & (i<32) DO INC(i); END;  ASSERT(i<32);
			suffix:= (ORD(name[i-2])-48)*10 + ORD(name[i-1])-48;	
			ASSERT((suffix>=0) & (suffix<=99));
			RETURN suffix;
		END GetSuffix;
		
		PROCEDURE &Init;
		VAR
			i : LONGINT;
			temp : RegisteredDriver;
		BEGIN
			(* allocate list heads *)
			FOR i:=0 TO 11 DO
				NEW(temp);
				drivers[i] := temp;
			END;
		END Init;
		
		(* debug: displays a list of registered drivers *)
		PROCEDURE Show*;
		VAR
			temp : RegisteredDriver;
			i : LONGINT;
		BEGIN
			AosOut.Ln;AosOut.String("AosUsb: Registered USB device drivers: "); AosOut.Ln;
			FOR i :=0 TO DmMaxPriorities - 1 DO
				temp := drivers[i].next;
				IF temp#NIL THEN
					WHILE (temp#NIL) DO
						AosOut.String("   ");
						AosOut.String(temp.name); 
						AosOut.String("( "); AosOut.String(temp.desc); AosOut.String(")"); 
						AosOut.String(" Priority: "); AosOut.Int(i,0);
						AosOut.Ln;
						temp := temp.next;
					END;
				END;
			END;
		END Show;
	END DriverManager;

TYPE

	(* integrated USB hub driver *)
	UsbHubDriver = OBJECT (UsbDriver)
	VAR
		startScanDone : BOOLEAN;
		timer : AosKernel.Timer;
		
		portStatusErrors : LONGINT;   
		
		(* Helper: wait is not reentrant !!! *)
		PROCEDURE Wait(ms : LONGINT);
		BEGIN
			timer.Sleep(ms)
		END Wait;

		(* returns the port status of the hub *)
		PROCEDURE GetPortStatus(port : INTEGER) : SET;
		VAR
			status : SET;
			message : ARRAY 8 OF CHAR;
			buffer : ARRAY 4 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			ASSERT(port < device.ports); 
	
			IF device.parent = device THEN (* it's a root hub *)
				status := device.controller.GetPortStatus(port);
			ELSE
				message[0] := CHR(128+32+3);
				message[1] := CHR(CommandGetStatus);
				message[2] := CHR(0);
				message[3] := CHR(0);
				message[4] := CHR(port + 1);
				message[5] := CHR(0);
				message[6] := CHR(4);
				message[7] := CHR(0);
				
				transfer := device.SendControl( 0+128, message, buffer, 0, 4, 2000);
				IF ~transfer.ResOK() THEN RETURN AosUsbHcdi.PortStatusError; END;
	
				status := {};
				IF SYSTEM.VAL(SET, ORD(buffer[0])) * {0} # {} THEN status := status + AosUsbHcdi.PortStatusDevicePresent; END;
				IF SYSTEM.VAL(SET, ORD(buffer[0])) * {1} # {} THEN status := status + AosUsbHcdi.PortStatusEnabled; END;
				IF SYSTEM.VAL(SET, ORD(buffer[0])) * {4} # {} THEN status := status + AosUsbHcdi.PortStatusReset; END;		
				IF SYSTEM.VAL(SET, ORD(buffer[1])) * {1} # {} THEN status := status + AosUsbHcdi.PortStatusLowSpeed; END;
				IF SYSTEM.VAL(SET, ORD(buffer[2])) * {0} # {} THEN 
				
					status := status + AosUsbHcdi.PortStatusConnectChange; 
					
					(* reset PortStatusConnectChange *)
					message[0] := CHR(32+3);
					message[1] := CHR(CommandClearFeature);
					message[2] := CHR(16);  (* clear port connection *)
					message[3] := CHR(0);
					message[4] := CHR(port+1);
					message[5] := CHR(0);
					message[6] := CHR(0); (*wlength*)
					message[7] := CHR(0);
	
					transfer := device.SendControl(0+128, message, buffer, 0, 0, 2000);
					IF ~transfer.ResOK() THEN RETURN AosUsbHcdi.PortStatusError; END;
					
				END;
			END;
			
			RETURN status;
	
		END GetPortStatus;

		PROCEDURE PowerPort(port : INTEGER) : BOOLEAN;
		VAR
			transfer : UsbTransfer;
			message : ARRAY 8 OF CHAR;
		BEGIN
			IF device.parent = device THEN (* it's a root hub *)
				(*  device.controller.PowerPort(device.controller, port);  not implemented  *)
				RETURN TRUE;
			ELSE
				message[0] := CHR(32+3);
				message[1] := CHR(CommandSetFeature);
				message[2] := CHR(8); (* Power port *)
				message[3] := CHR(0);
				message[4] := CHR(port + 1);
				message[5] := CHR(0);
				message[6] := CHR(0);
				message[7] := CHR(0);
	
				transfer := device.SendControl( 0, message, message, 0, 0, 2000);
	
				IF transfer.ResOK() THEN Wait(device.hubTime2Good); END;
	
				RETURN transfer.ResOK();
			END;
		END PowerPort;
		
		PROCEDURE EnablePort(port : INTEGER):BOOLEAN;
		VAR
			message : ARRAY 8 OF CHAR;
			status : SET;
			transfer : UsbTransfer;
		BEGIN
	
			IF device.parent = device THEN (* it's a root hub *)
				device.controller.EnablePort(port);
				RETURN TRUE;
			END;
	
			message[0] := CHR(32+3);
			message[1] := CHR(CommandSetFeature);
			message[2] := CHR(4); (* Reset port *)
			message[3] := CHR(0);
			message[4] := CHR(port + 1);
			message[5] := CHR(0);
			message[6] := CHR(0);
			message[7] := CHR(0);
			
			transfer := device.SendControl(0, message, message, 0, 0, 2000);
	
			IF ~transfer.ResOK() THEN AosOut.String("Usb: could not enable hub port"); AosOut.Ln; RETURN FALSE; END;
	
			Wait(50);
	
			status := GetPortStatus(port);
	
			IF (status * AosUsbHcdi.PortStatusError) # {} THEN
				AosOut.String("Usb: Fatal cannot get port status after enabling."); AosOut.Ln;
				RETURN FALSE;
			ELSIF (status * AosUsbHcdi.PortStatusReset) # {} THEN
				Wait(50);
				AosOut.String("Usb: Port still in reset (after 50ms!)"); AosOut.Ln;
				RETURN FALSE;
			ELSIF (status * AosUsbHcdi.PortStatusEnabled) = {} THEN
				AosOut.String("Usb: Could not enable hub port"); AosOut.Ln;
				RETURN FALSE;
			END;
			
			RETURN TRUE;
			
		END EnablePort;
		
		PROCEDURE DisablePort(port : INTEGER):BOOLEAN;
		VAR
			message : ARRAY 8 OF CHAR;
			transfer : UsbTransfer;
		BEGIN
			IF device.parent = device THEN (* it's a root hub *)
				device.controller.DisablePort(port);
				RETURN TRUE;
			ELSE
				message[0] := CHR(32+3);
				message[1] := CHR(CommandClearFeature);
				message[2] := CHR(1); (* Clear Enable port *)
				message[3] := CHR(0);
				message[4] := CHR(port + 1);
				message[5] := CHR(0);
				message[6] := CHR(0);
				message[7] := CHR(0);
				
				transfer := device.SendControl( 0, message, message, 0, 0, 2000);
	
				RETURN transfer.ResOK();
			END;
		END DisablePort;
		
		PROCEDURE Connect;
		BEGIN
			(* not needed by internal USB hub driver *)
		END Connect;
		
		PROCEDURE Disconnect;
		BEGIN
			AosOut.String("USB hub "); AosOut.String(name); AosOut.String(" disconnected."); AosOut.Ln;
		END Disconnect;
		
		(* checks all ports of the hub against attached devices. If a device is found, its driver is installed if available *)
		PROCEDURE ConnectHub;
		VAR
			j, i : INTEGER;
			dev : UsbDevice;
			status : SET;
			res : BOOLEAN;
		BEGIN 
	
			FOR j:=0 TO device.ports - 1 DO
		
				status := GetPortStatus(j);
	
				IF (status * AosUsbHcdi.PortStatusError) # {} THEN
				
						INC(portStatusErrors);
						
						IF MaxPortStatusErrors - portStatusErrors < 0 THEN 

							AosOut.String("AosUsb: Error: Could not get port status of "); 
							AosOut.String(name); AosOut.String(" ("); AosOut.String(desc); AosOut.String(")"); AosOut.Ln; 
	
							IF device.hubPortDevices[j] # NIL THEN (* remove device and its driver instance from port j *)
								device.hubPortDevices[j].Remove;
								device.hubPortDevices[j] := NIL;
							END;
							
						END;
	
				ELSIF (status * AosUsbHcdi.PortStatusReset) # {} THEN 
	
						IF Debug THEN AosOut.String("AosUsb: cannot connect to port, port is in reset."); AosOut.Ln;END;
	
				ELSIF ((status * AosUsbHcdi.PortStatusConnectChange) # {}) OR ~startScanDone THEN (* Connection Status of port has changed *)
				
						portStatusErrors := 0;
						
						IF (status * AosUsbHcdi.PortStatusDevicePresent) # {} THEN (* a device has been attached to this port *)

								(* remark: PortStatusConnectChange is reset by GetPortStatus() *)
								
								IF ~device.hubPortPermanentDisabled[ j ] THEN
		
											IF EnablePort(j) THEN (* try to connect to attached USB device *)
												i := 4; 
												LOOP
													dev := FindNewDevice(j);
													IF dev # NIL THEN (* device found *) EXIT; END;
													IF Debug THEN AosOut.String("Usb: Retrying to connect device."); AosOut.Ln;END;
													DEC(i); IF i = 0 THEN EXIT 
													END;
													res := DisablePort(j);
													res := EnablePort(j);
													Wait(200); (* eventually the USB device reacts to slowly *)
												END;
						
												IF dev = NIL THEN (* ERROR: USB device attached but not found via FindNewDevices() *)
													
													status := GetPortStatus(j);
													
													IF (status*AosUsbHcdi.PortStatusDevicePresent) = {} THEN (* bad timing... device is not present anymore *)
			
														IF device.hubPortDevices[j] # NIL THEN (* remove device and its driver instance from port *)
															device.hubPortDevices[j].Remove;
															device.hubPortDevices[j] := NIL;
														END;
								
													res:=DisablePort(j); (*ignore res*)

													ELSE
														AosOut.String("Usb: FATAL, disabling port. Replug connector of device!"); AosOut.Ln;
														res := DisablePort(j);
														IF ~res THEN AosOut.String("Usb: Port disabling failed."); AosOut.Ln; END;
														device.hubPortPermanentDisabled[ j ] := TRUE;
													END;
													
												ELSE
													(* new device detected *)
													dev.port := j;
													dev.Register(device, j);
													drivers.ProbeDevice(dev); (* try to install an appropriate USB device driver *)
												END;					
										
											ELSE (* ERROR: Couldn't enable port because it's permanently disabled *)
											
												AosOut.String("Usb: Could not enable port."); AosOut.Ln;
												device.hubPortPermanentDisabled[ j ] := TRUE;
												
											END;	
								END;
						
					ELSE (* device has been removed from port *)
					
								IF device.hubPortDevices[j] # NIL THEN (* remove device and its driver instance from port *)
									device.hubPortDevices[j].Remove;
									device.hubPortDevices[j] := NIL;
								END;
								
								res:=DisablePort(j); (*ignore res*)
	
								device.hubPortPermanentDisabled[ j ] := FALSE; (* reset disabled status, as soon as user disconnects it *)
					END;
	
			ELSIF (status * AosUsbHcdi.PortStatusEnabled) # {} THEN (* port is enabled -> a device should be connected to this port *)
						
						portStatusErrors := 0;
						
						dev := device.hubPortDevices[j];
						IF dev = NIL THEN
							AosOut.String("Usb: Port was enabled, but usb software did not knew it!"); AosOut.Ln;
							res:=DisablePort(j);
						ELSIF dev.hubFlag THEN (* poll attached hub *)
							dev.actConfiguration.interfaces[0].driver(UsbHubDriver).ConnectHub;
						END;
					END;
			END; 
			
			startScanDone:=TRUE;

		END ConnectHub;
		
		PROCEDURE FindNewDevice(port : INTEGER): UsbDevice;
		VAR
			res : BOOLEAN;
			adr : LONGINT;
			dev : UsbDevice;
			status : SET;
		BEGIN
			adr := device.controller.GetFreeAddress();
		
			IF adr = 0 THEN (* Sorry, bus is full *) 
				AosOut.String("AosUsb: Warning: No free addresses for installing new USB device"); AosOut.Ln;
				RETURN NIL; 
			END; 
		
			NEW(dev); NEW(dev.data);
	
			dev.controller := device.controller;
			dev.data.address := 0; (* default address *)
			dev.data.lowSpeed := FALSE;
			dev.data.highSpeed := FALSE;
	
			status := GetPortStatus(port);
			
			IF (status * AosUsbHcdi.PortStatusError) # {} THEN 
				AosOut.String("AosUsb: Cannot get port status"); AosOut.Ln;
				RETURN NIL;
			END; 
			
			IF (status * AosUsbHcdi.PortStatusDevicePresent) = {} THEN RETURN NIL; END;
	
			IF (status * AosUsbHcdi.PortStatusLowSpeed) # {} THEN
				dev.data.lowSpeed := TRUE; 
			ELSIF (status * AosUsbHcdi.PortStatusHighSpeed) # {} THEN
				dev.data.highSpeed := TRUE;
			END;
			NEW(dev.descriptor);
	
			dev.descriptor.bMaxPacketSize0 := 8; (* temp., until we have read the descriptor *)
			dev.data.bMaxPacketSize0:=8;
	
			res := dev.SetAddress(adr);
	
			IF res # TRUE THEN
				device.controller.FreeAddress(adr);
				AosOut.String("AosUsb: Address Setup failed."); AosOut.Ln;
				RETURN NIL;
			END;
	
			Wait(20); (* let the address settle *)
	
			res := ParseDescriptors(dev);
	
			IF res # TRUE THEN
				device.controller.FreeAddress(adr);
				AosOut.String("AosUsb: Parsing failed."); AosOut.Ln;
				RETURN NIL;
			END;
	
			(* Set Configuration *)
			res := dev.SetConfiguration(0);

			IF res # TRUE THEN
				device.controller.FreeAddress(adr);
				AosOut.String("AosUsb: Cannot set configuration"); AosOut.Ln;
				RETURN NIL;
			END;
			
			(* Get sManufacturer, sProduct and sSerialNumber strings *)
			 GetStrings(dev); 
			 
			 IF ShowStrings THEN 
				AosOut.String("AosUsb: ");
				IF (dev.sManufacturer#"n/a") OR (dev.sProduct#"n/a") THEN 
					IF dev.sManufacturer#"n/a" THEN AosOut.String(dev.sManufacturer); AosOut.Char(" "); END;
					IF dev.sProduct#"n/a" THEN AosOut.String(dev.sProduct); END;
				ELSE
					AosOut.String("unknown device");
				END;
				AosOut.String(" attached to "); AosOut.String(device.controller.name); AosOut.String(" port ");
				AosOut.Int(port,0); AosOut.String("."); AosOut.Ln;
			END;

			RETURN dev;
			
		END FindNewDevice;
		
	BEGIN
		NEW(timer);  (* used by Wait() *)
	END UsbHubDriver;

TYPE
	
	UsbRootHubDriver = OBJECT (UsbHubDriver)
	VAR
		timerRH : AosKernel.Timer;
		alive, dead : BOOLEAN;
		nextRootHub : UsbRootHubDriver;
		
		PROCEDURE Terminate;
		BEGIN {EXCLUSIVE}
			timerRH.Wakeup(); 
			alive:=FALSE
		END Terminate; 
		
		PROCEDURE AwaitDead;
			BEGIN {EXCLUSIVE}
 			AWAIT(dead)
		END AwaitDead;
 	
		PROCEDURE SetDead;
		BEGIN {EXCLUSIVE}
			dead := TRUE
		END SetDead;
 
		BEGIN {ACTIVE}	
			NEW(timerRH);
			alive:=TRUE;
			
			WHILE alive DO
				timerRH.Sleep(PollingInterval);
				ConnectHub	
			END;
			SetDead
			
	END UsbRootHubDriver;

VAR
	usbDrivers* : AosPlugins.Registry;	(* instanciated USB device drivers (linked to a attached USB device) *)
	hubDriver : UsbHubDriver;
	rootHubs : UsbRootHubDriver;   (* all root hubs in the system *)
	drivers* : DriverManager;   (* AosUsb internal registry for installable USB device drivers *)
	
	timer : AosKernel.Timer; (* used by Wait *)

(* Reads StringDescriptors from USBdevice dev if any available *)
PROCEDURE GetStrings(dev : UsbDevice);
VAR
	buffer : ARRAY 256 OF CHAR;
	langid : LONGINT;
	res : BOOLEAN;
	i : LONGINT;

	PROCEDURE GetString(descriptorIndex, langID : LONGINT) : String;
	VAR
		unicode : ARRAY 128 OF LONGINT;
		utf8, ascii : String;
		i : LONGINT;
	BEGIN
		ascii := "n/a";
	
		(* first, get the length of the string descriptor to be loaded... *)
		res := dev.GetDescriptor(128, DescriptorString,  descriptorIndex, langID, 2, buffer);

		IF (res=TRUE) & (ORD(buffer[1])=DescriptorString) & (ORD(buffer[0])>3) & (ORD(buffer[0]) MOD 2 = 0) THEN
		
			(* then load the string descriptor *)
			res := dev.GetDescriptor(128, DescriptorString, descriptorIndex, langID, ORD(buffer[0]), buffer);
			
			IF res#TRUE THEN
				IF Debug THEN AosOut.String("AosUsb: Couldn't load string descriptor"); AosOut.Ln; END;
			ELSE
			
				(* convert ARRAY OF CHAR to ARRAY OF LONGINT *)
				FOR i:=0 TO ((ORD(buffer[0])-2) DIV 2) -1 DO
					unicode[i] := ORD(buffer[(2*i)+2])+ORD(buffer[(2*i)+3])*100H;
				END;
				
				(* convert Unicode to UTF8  *)
				UTF8Strings.UnicodetoUTF8(unicode, utf8);
				
			END;
			
		ELSE
			IF Debug THEN AosOut.String("AosUsb: Couldn't get the first 2 bytes of the string descriptor"); AosOut.Ln; END;
		END;
		RETURN utf8
	END GetString;
	
	(* returns TRUE if the <langid> is supported, FALSE otherwise *)
	PROCEDURE LangIdSupported(langid : LONGINT): BOOLEAN;
	VAR
		supported : BOOLEAN;
		i : LONGINT;
	BEGIN
		(* LANDID code array:  buf[0]=length of code array, buf[1]=DecriptorString, buf[2*i]+buf[2*i+1] : LangID codes *)
		IF ((ORD(buffer[0]) MOD 2)#0) OR (ORD(buffer[0])<4) THEN RETURN FALSE; END;
		
		(* check whether langID is a element of the LANGID code array *)
		FOR i := 2 TO ORD(buffer[0])-2 BY 2 DO
			IF (ORD(buffer[i])+ORD(buffer[i+1])*100H) = langid THEN supported := TRUE; END;
		END;
		
		RETURN supported;
	END LangIdSupported;
	
BEGIN
	(* defaults if no string descriptor is provided or the loading of the string descriptor fails *)
	dev.sManufacturer := "n/a"; dev.sProduct := "Unknown Device"; dev.sSerialNumber := "n/a";
	
	IF (dev.descriptor.iManufacturer=0) & (dev.descriptor.iProduct=0) & (dev.descriptor.iSerialNumber=0) THEN (* no string describtors supported *) 	
		IF Debug THEN AosOut.String("AosUsb: No String Descriptors provided by this device"); AosOut.Ln; END;
	ELSE
		(* first get the length of the LANGID code array *)
		res := dev.GetDescriptor(128, DescriptorString, 0, 0, 2,  buffer);
		
		IF (res#TRUE) OR (ORD(buffer[1])#DescriptorString) THEN 
			IF Debug THEN AosOut.String("AosUsb: Couldn't load the first 2 bytes of StringDescriptor"); AosOut.Ln; END;
			RETURN;		
		END;
		
		(* get the LANDID code array *)
		res := dev.GetDescriptor(128, DescriptorString, 0, 0, ORD(buffer[0]), buffer); 
		
		IF (res#TRUE) OR (ORD(buffer[1])#DescriptorString) THEN
			IF Debug THEN AosOut.String("AosUsb: Couldn't load String Descriptor"); AosOut.Ln; END;
			RETURN;
		END;
		
		(* get a preferred LANGID code *)
		IF LangIdSupported(IdEnglishUS) THEN langid := IdEnglishUS;
		ELSIF LangIdSupported(IdEnglishUK) THEN langid := IdEnglishUK;
		ELSIF LangIdSupported(IdSystemDefault) THEN langid := IdSystemDefault; 
		ELSIF LangIdSupported(IdUserDefault) THEN langid := IdUserDefault;
		ELSE
			IF Debug THEN AosOut.String("AosUsb: Couldn't load string descriptor (no supported language found)"); AosOut.Ln; END;
			RETURN;
		END;
		
		(* get manufacturer string *)
		IF dev.descriptor.iManufacturer#0 THEN 
			dev.sManufacturer := GetString(dev.descriptor.iManufacturer, langid);
		END;
		
		(* get product string *)
		IF dev.descriptor.iProduct#0 THEN
			dev.sProduct := GetString(dev.descriptor.iProduct, langid);
		END;
		
		(* get serial number *)
		IF dev.descriptor.iSerialNumber#0 THEN
			dev.sSerialNumber := GetString(dev.descriptor.iSerialNumber, 0000H); (* 0000H: Language neutral *)
		END;
	END;
	
END GetStrings;


PROCEDURE ParseInterfaces(devconf : UsbDeviceConfiguration; VAR buffer : ARRAY OF CHAR; VAR idx : INTEGER) : BOOLEAN;
VAR
	n, e : INTEGER;
BEGIN

	NEW(devconf.interfaces, devconf.bNumInterfaces); (* always > 0 *)

	FOR n:=0 TO devconf.bNumInterfaces - 1 DO

		IF idx >= devconf.wTotalLength THEN
			AosOut.String("Usb: ParseInterfaces: Out of interface data."); AosOut.Ln;
			RETURN FALSE;
		END;

		(* Search the alternate interface 0 *)
		WHILE (ORD(buffer[idx + 1]) # DescriptorInterface) OR (ORD(buffer[idx + 3]) # 0) DO
			idx := idx + ORD(buffer[idx]);
			IF idx >= devconf.wTotalLength THEN
				AosOut.String("Usb: ParseInterfaces: Interface not found."); AosOut.Ln;
				RETURN FALSE;
			END;
		END;

		IF ORD(buffer[idx + 3]) # 0 THEN
			AosOut.String("Usb: ParseInterfaces: Alternate Interface 0 not found."); AosOut.Ln;
			RETURN FALSE;
		END;

		NEW(devconf.interfaces[n]);

		devconf.interfaces[n].bInterfaceNumber := ORD(buffer[idx + 2]);
		devconf.interfaces[n].bAlternateSetting := ORD(buffer[idx + 3]);
		devconf.interfaces[n].bNumEndpoints := ORD(buffer[idx + 4]);
		devconf.interfaces[n].bInterfaceClass := ORD(buffer[idx + 5]);
		devconf.interfaces[n].bInterfaceSubClass := ORD(buffer[idx + 6]);
		devconf.interfaces[n].bInterfaceProtocol := ORD(buffer[idx + 7]);
		devconf.interfaces[n].iInterface := ORD(buffer[idx + 8]);

		idx := idx + ORD(buffer[idx]);

		(* Collect endpoints for interface 0 *)
		IF devconf.interfaces[n].bNumEndpoints > 0 THEN
			NEW(devconf.interfaces[n].endpoints, devconf.interfaces[n].bNumEndpoints);
		END;
			
		FOR e := 0 TO devconf.interfaces[n].bNumEndpoints - 1 DO
				
			IF idx >= devconf.wTotalLength THEN
				AosOut.String("Usb: ParseInterfaces: Not enough endpoint data."); AosOut.Ln;
				RETURN FALSE;
			END;

			WHILE ORD(buffer[idx + 1]) # DescriptorEndpoint DO
				idx := idx + ORD(buffer[idx]);
				IF idx >= devconf.wTotalLength THEN
					AosOut.String("Usb: ParseInterfaces: Endpoint not found."); AosOut.Ln;
					RETURN FALSE;
				END;
			END;

			NEW(devconf.interfaces[n].endpoints[e]);
				
			devconf.interfaces[n].endpoints[e].bEndpointAddress := ORD(buffer[idx + 2]);
			devconf.interfaces[n].endpoints[e].bmAttributes := SYSTEM.VAL(SET, ORD(buffer[idx + 3]));
			devconf.interfaces[n].endpoints[e].wMaxPacketSize := ORD(buffer[idx + 5])*256 + ORD(buffer[idx + 4]);
			devconf.interfaces[n].endpoints[e].bInterval := ORD(buffer[idx + 6]);

			idx := idx + ORD(buffer[idx]);

		END;			

	END;

	RETURN TRUE;

END ParseInterfaces;

PROCEDURE ParseConfigurations(dev : UsbDevice) : BOOLEAN;
VAR
	c : INTEGER;
	buffer : ARRAY 2048 OF CHAR;
	idx : INTEGER;
	res : BOOLEAN;
BEGIN

	NEW(dev.configurations, dev.descriptor.bNumConfigurations); (* always > 0 *)

	FOR c :=0 TO dev.descriptor.bNumConfigurations - 1 DO

		NEW(dev.configurations[c]);

		(* message um erste 8 byte der c-ten Konfiguration lesen *)
		res := dev.GetDescriptor(128, DescriptorConfiguration, c, 0,  8, buffer);

		IF res # TRUE THEN
			AosOut.String("Usb: Read first 8 bytes of configuration failed"); AosOut.Ln;
			RETURN FALSE;
		END;

		IF ORD(buffer[2])+ 256*ORD(buffer[3]) > 2048 THEN
			AosOut.String("Usb: Configuration too big to fit in buffer!"); AosOut.Ln;
			RETURN FALSE;
		END;

		res := dev.GetDescriptor(128, DescriptorConfiguration, c, 0, ORD(buffer[2])+ 256*ORD(buffer[3]), buffer);

		IF res # TRUE THEN
			AosOut.String("Usb: Get configuration failed."); AosOut.Ln;
			RETURN FALSE;
		END;

		dev.configurations[c].wTotalLength := ORD(buffer[2])+ 256*ORD(buffer[3]);
		dev.configurations[c].bNumInterfaces := ORD(buffer[4]);
		dev.configurations[c].bConfigurationValue := ORD(buffer[5]);
		dev.configurations[c].iConfiguration := ORD(buffer[6]);
		dev.configurations[c].bmAttributes := SYSTEM.VAL(SET, ORD(buffer[7]));
		dev.configurations[c].maxPower := ORD(buffer[8]);

		idx := ORD (buffer[0]); (* idx points to first interface *)

		res := ParseInterfaces(dev.configurations[c], buffer, idx);

		IF res # TRUE THEN
			AosOut.String("AosUsb: ParseInterfaces failed."); AosOut.Ln;
			RETURN FALSE;
		END;

	END;			

	RETURN TRUE;

END ParseConfigurations;

PROCEDURE ParseDescriptors(dev : UsbDevice) : BOOLEAN;
VAR
	buffer : ARRAY 2048 OF CHAR;
	res : BOOLEAN;
BEGIN
	(* message um Device-descriptor von Device zu lesen *)	
	res := dev.GetDescriptor(128, DescriptorDevice, 0, 0, 8, buffer);
	
	(* we are only allowed to read 8 bytes until now - otherwise there could happen a babble error *)
	IF res # TRUE THEN
		AosOut.String("AosUsb: Read first 8 bytes of descriptor failed."); AosOut.Ln;
		RETURN FALSE;
	END;

	dev.descriptor.bMaxPacketSize0 := ORD(buffer[7]);
	dev.data.bMaxPacketSize0:=ORD(buffer[7]);

	res := dev.GetDescriptor(128, DescriptorDevice, 0, 0, 18, buffer);	

	IF res # TRUE THEN
		AosOut.String("Usb: Get descriptor failed."); AosOut.Ln;
		RETURN FALSE;
	END;

	dev.descriptor.bcdUSB := ORD(buffer[3])*256 + ORD(buffer[2]);
	dev.descriptor.bDeviceClass := ORD(buffer[4]);
	dev.descriptor.bDeviceSubClass := ORD(buffer[5]);
	dev.descriptor.bDeviceProtocol := ORD(buffer[6]);
	dev.descriptor.bMaxPacketSize0 := ORD(buffer[7]);
	dev.data.bMaxPacketSize0:=ORD(buffer[7]);
	dev.descriptor.idVendor := ORD(buffer[9])*256 + ORD(buffer[8]);
	dev.descriptor.idProduct := ORD(buffer[11])*256 + ORD(buffer[10]);
	dev.descriptor.bcdDevice := ORD(buffer[13])*256 + ORD(buffer[12]);
	dev.descriptor.iManufacturer := ORD(buffer[14]);
	dev.descriptor.iProduct := ORD(buffer[15]);
	dev.descriptor.iSerialNumber := ORD(buffer[16]);
	dev.descriptor.bNumConfigurations := ORD(buffer[17]);

	res := ParseConfigurations(dev);
	RETURN res;

END ParseDescriptors;

(* for debugging: shows information about all USB devices which are connected to this hub *)
PROCEDURE InfoChain(hub : UsbDevice; spacer : INTEGER);
VAR
	j, n, m, o, p : LONGINT;
	dev : UsbDevice;
	drv : UsbDriver;
	sp  : LONGINT;
	attr : LONGINT;
BEGIN
	ASSERT(hub.hubFlag);

	FOR sp := 0 TO spacer - 1 DO AosOut.Char(" "); END;

	IF hub.parent # hub THEN (* it's NOT a root hub *)
		AosOut.String("Hub at port "); AosOut.Int(hub.port, 0);
	END;

	AosOut.String(" with "); AosOut.Int(hub.ports, 0); AosOut.String(" ports."); AosOut.Ln;
	
	FOR j:=0 TO hub.ports - 1 DO
		dev := hub.hubPortDevices[j];
		IF dev # NIL THEN
			IF dev. hubFlag THEN
				InfoChain(dev, spacer + 2);
			ELSE
				FOR sp := 0 TO spacer+2 DO AosOut.Char(" "); END;
				AosOut.String("Device at port "); AosOut.Int(dev.port, 0); AosOut.String(": ");
				
				IF dev.sManufacturer#"n/a" THEN AosOut.String(dev.sManufacturer); AosOut.Char(" "); END;
				IF dev.sProduct#"n/a" THEN AosOut.String(dev.sProduct); AosOut.Char(" "); END;
				IF dev.sSerialNumber#"n/a" THEN AosOut.String(dev.sSerialNumber); END;
				
				AosOut.String("[Device: Class: "); PrintHex(dev.descriptor.bDeviceClass MOD 10000H);
				AosOut.String("H Subclass: "); PrintHex(dev.descriptor.bDeviceSubClass MOD 10000H);
				AosOut.String("H Protocol: "); PrintHex(dev.descriptor.bDeviceProtocol MOD 10000H);
				AosOut.String("]");
				
				AosOut.Ln;
				FOR sp := 0 TO spacer+2 DO AosOut.Char(" "); END;
				
				AosOut.String("Address: "); AosOut.Int(dev.data.address, 0);
				IF dev.data.lowSpeed THEN
					AosOut.String(" [lowspeed]");
				ELSIF dev.data.highSpeed THEN
					AosOut.String(" [highspeed]");
				ELSE
					AosOut.String(" [fullspeed]");
				END;
				
				AosOut.String (" MaxPower: "); AosOut.Int(dev.actConfiguration.maxPower,0); AosOut.String("mA");
				AosOut.Ln; FOR sp := 0 TO spacer+2 DO AosOut.Char(" "); END;

				AosOut.String("Vendor: "); PrintHex(dev.descriptor.idVendor MOD 10000H); 	   (* printhex wants a longint     *)
				AosOut.String("H Product: "); PrintHex(dev.descriptor.idProduct MOD 10000H);   (* we must be sure that          *)
				AosOut.String("H Bcd: "); PrintHex(dev.descriptor.bcdDevice MOD 10000H); 	   (* that our integer doesnt get *)
				AosOut.String(" Class: "); PrintHex(dev.descriptor.bDeviceClass MOD 10000H);	 (* sign extended                     *)
				AosOut.String("H SubClass: "); PrintHex(dev.descriptor.bDeviceSubClass MOD 10000H); AosOut.Char("H");
				AosOut.Ln;

				(* list all configurations *)
				FOR o:=0 TO dev.descriptor.bNumConfigurations-1 DO
					FOR sp := 0 TO spacer+4 DO AosOut.Char(" "); END;
					AosOut.String("Configuration "); AosOut.Int(o,0);  
					IF dev.actConfiguration=dev.configurations[o] THEN AosOut.String(" [active]"); END; 
					AosOut.String(":"); 
					(* list all interfaces *)
					FOR n:=0 TO dev.configurations[o].bNumInterfaces - 1 DO
						AosOut.Ln; FOR sp := 0 TO spacer+8 DO AosOut.Char(" "); END;
						AosOut.String("Interface "); AosOut.Int(n,0); AosOut.String(": ");
						AosOut.String("[Class: "); PrintHex(dev.configurations[o].interfaces[n].bInterfaceClass);
						AosOut.String("H Subclass: "); PrintHex(dev.configurations[o].interfaces[n].bInterfaceSubClass);
						AosOut.String("H Protocol: "); PrintHex(dev.configurations[o].interfaces[n].bInterfaceProtocol);
						AosOut.String("H #Endpoints: "); AosOut.Int(dev.configurations[o].interfaces[n].bNumEndpoints, 0);
						AosOut.String("]"); AosOut.Ln;
						(* list alternate settings if any exist *)
						IF dev.configurations[o].interfaces[n].numAlternateInterfaces=0 THEN
							FOR sp := 0 TO spacer+8 DO AosOut.Char(" "); END;
							AosOut.String("No alternate interface available."); AosOut.Ln;
						ELSE
							FOR sp := 0 TO spacer+8 DO AosOut.Char(" "); END;
							AosOut.String("Alternate interface(s) found: "); AosOut.Ln;
							FOR p := 0 TO dev.configurations[o].interfaces[n].numAlternateInterfaces-1 DO
								FOR sp := 0 TO spacer+8 DO AosOut.Char(" "); END;
								AosOut.String("Alternate Interface "); AosOut.Int(p,0); AosOut.String(": ");
								AosOut.String("[Class: "); PrintHex(dev.configurations[o].interfaces[n].alternateInterfaces[p].bInterfaceClass);
								AosOut.String("H Subclass: "); PrintHex(dev.configurations[o].interfaces[n].alternateInterfaces[p].bInterfaceSubClass);
								AosOut.String("H Protocol: "); PrintHex(dev.configurations[o].interfaces[n].alternateInterfaces[p].bInterfaceProtocol);
								AosOut.String("H #Endpoints: "); AosOut.Int(dev.configurations[o].interfaces[n].alternateInterfaces[p].bNumEndpoints, 0);
								AosOut.String("]"); AosOut.Ln;
							END;
						END;
						
						(*list all endpoints *)
						FOR m:=0 TO dev.configurations[o].interfaces[n].bNumEndpoints-1 DO
							FOR sp:=0 TO spacer+12 DO AosOut.Char(" ");END;
							AosOut.String("Endpoint "); AosOut.Int(m,0); AosOut.String(": [Address: ");
							PrintHex(dev.configurations[o].interfaces[n].endpoints[m].bEndpointAddress MOD 10000H); AosOut.String("H ");
							AosOut.String("Type: ");
							attr:=SYSTEM.VAL(LONGINT, dev.configurations[o].interfaces[n].endpoints[m].bmAttributes);
							CASE attr OF
								0 : AosOut.String("Control");
								|1 : AosOut.String("Isochronous");
								|2 : AosOut.String("Bulk");
								|3 : AosOut.String("Interrupt");
							ELSE
								AosOut.String("unknown");
							END;
							
							IF (attr#0) & (attr<4) THEN
								AosOut.String("(");
								IF (SYSTEM.VAL(SET, dev.configurations[o].interfaces[n].endpoints[m].bEndpointAddress) * {7}) # {} THEN
									AosOut.String("IN");
								ELSE
									AosOut.String("OUT");
								END;
								AosOut.String(") ");
							ELSE
								AosOut.String(" ");
							END;
							
							AosOut.String("MaxPacketSize: "); AosOut.Int(dev.configurations[o].interfaces[n].endpoints[m].wMaxPacketSize,0);
							AosOut.String(" Bytes IRQinterval: "); AosOut.Int(dev.configurations[o].interfaces[n].endpoints[m].bInterval,0); 
							AosOut.String(" ms]"); AosOut.Ln;
						END;
						
						FOR sp := 0 TO spacer+12 DO AosOut.Char(" "); END;
						drv := dev.configurations[o].interfaces[n].driver;
						AosOut.String("Driver: ");
						IF drv # NIL THEN
							AosOut.String("["); AosOut.String(drv.name);
							AosOut.String("("); AosOut.String(drv.desc); AosOut.String(")]");
						ELSE AosOut.String("[no driver found for this interface]");
						END;
					END;
					AosOut.Ln;
				END;
			END;
		END;
	END;
END InfoChain;

(** Prints information about current usb tree into kernellog (for debugging) *)
PROCEDURE Info*;
VAR
	temp : UsbRootHubDriver;
BEGIN
	AosOut.String("Usb tree:"); AosOut.Ln;
	temp:=rootHubs;
	WHILE temp#NIL DO
			AosOut.String(temp.name); AosOut.String(" ("); AosOut.String(temp.desc); AosOut.String(")");
			InfoChain(temp.device, 0); 
			temp:=temp.nextRootHub;
	END;
END Info;

(** Shows all registered drivers and their instances (for debugging) *)
PROCEDURE ShowDrivers*;
VAR
	instances : AosPlugins.Table;
	i : LONGINT;
BEGIN
	drivers.Show;
	AosOut.Ln; AosOut.String("AosUsb: Instances of registered device drivers: "); AosOut.Ln;
	usbDrivers.GetAll(instances);
	IF instances=NIL THEN
		AosOut.String("no device drivers instances installed"); AosOut.Ln;
	ELSE
		FOR i:=0 TO LEN(instances)-1 DO
			AosOut.String("   ");
			AosOut.String(instances[i].name); AosOut.String(" (");
			AosOut.String(instances[i].desc); AosOut.String(")");
			AosOut.Ln;
		END;
	END;
END ShowDrivers;

(* Helper: Displays the number <was> in hex to the kernel log *)
PROCEDURE PrintHex(was: LONGINT);
VAR z,d,h,i:LONGINT;
BEGIN
	z := 0;
	d := 16*16*16*16*16*16*16; (* what a quick hack *)
	FOR i:=0 TO 7 DO
		h := (was DIV d) MOD 16;
		IF (z = 1) OR (h # 0) OR (i = 7) THEN
			z := 1;
			IF h < 10 THEN AosOut.Int(h,0); ELSE AosOut.Char(CHR(ORD("A")+h-10)); END;
		END;
		d:=d DIV 16;
	END;
END PrintHex;

(* This is the Probe() procedure of the internal USB hub driver *)
PROCEDURE Probe(dev : UsbDevice; if : LONGINT):UsbDriver;
VAR
	buffer : ARRAY 8 OF CHAR;
	intfc : UsbDeviceInterface;
	res : BOOLEAN;
	i : INTEGER;
	hubDriver : UsbHubDriver;  (* driver to be installed *)
BEGIN

	IF dev.descriptor.bNumConfigurations # 1 THEN RETURN NIL; END;
	IF dev.configurations[0].bNumInterfaces # 1 THEN RETURN NIL; END;

	intfc := dev.configurations[0].interfaces[0];

	IF intfc.bInterfaceClass # 9 THEN RETURN NIL; END;
	IF intfc.bInterfaceSubClass # 0 THEN RETURN NIL; END;
	IF intfc.bNumEndpoints # 1 THEN RETURN NIL; END;
	IF intfc.bInterfaceProtocol # 0 THEN RETURN NIL; END;

	res := dev.GetDescriptor(128+32, DescriptorHub, 0, 0, 8, buffer);
	IF res = FALSE THEN RETURN NIL; END;
		
	(* the checked device is a USB hub *)
	dev.ports := ORD(buffer[2]);
	NEW(dev.hubPortDevices, dev.ports);
	NEW(dev.hubPortPermanentDisabled, dev.ports);
	dev.hubTime2Good := ORD(buffer[5]) * 2; (* PowerOn 2 PowerGood measured in 2ms steps *)

	AosOut.String("Usb: Hub with "); AosOut.Int(dev.ports, 0); AosOut.String(" ports detected."); AosOut.Ln;

	dev.hubFlag := TRUE;
		
	NEW(hubDriver, dev, 0);

	FOR i:=0 TO dev.ports - 1 DO
		dev.hubPortDevices[i]:=NIL;
		res:=hubDriver.PowerPort(i);
		(* ignore res *)
	END;
	
	hubDriver.ConnectHub;

	RETURN hubDriver;
END Probe; 

(* installs the drivers for the USB root hubs of all registred USB host controllers *)
PROCEDURE InstallRootHubs;
VAR
	i, j :LONGINT;
	hub : UsbDevice;
	driver,temp : UsbRootHubDriver;
	controllers : AosPlugins.Table;
	name : AosPlugins.Name;
	res : LONGINT;
	installedInstances : LONGINT;
BEGIN
	AosUsbHcdi.controllers.GetAll(controllers);
	
	IF controllers#NIL THEN
	i:=0;
		WHILE i <= LEN(controllers^)-1 DO
			
			(* create a new UsbHub device object*)
			NEW(hub);
			hub.controller:=controllers[i] (AosUsbHcdi.Hcd);
			hub.parent:=hub;
			hub.hubFlag:=TRUE;				
			hub.ports := controllers[i](AosUsbHcdi.Hcd).GetPortCount();
			NEW(hub.hubPortDevices, hub.ports);
			NEW(hub.hubPortPermanentDisabled, hub.ports);
		
			FOR j:=0 TO 127 DO
				controllers[i](AosUsbHcdi.Hcd).FreeAddress(j);
			END;
			
			(* register the hub driver for this root hub *)
			NEW(driver, hub, 0); 
			driver.desc:=DescriptionRootHub;
			name:=drivers.AddSuffix(NameRootHub,i);
			driver.SetName(name);

			usbDrivers.Add(driver,res);
			
			IF res#AosPlugins.Ok THEN AosOut.String("AosUsb: Couldn't register USB root hub at usbDrivers registry"); AosOut.Ln; HALT(301); END;

			(* remember the root hubs internally; until now, only hub drivers for the root hubs are registered in usbDrivers *)
			IF rootHubs=NIL THEN 
				rootHubs:=driver;
			ELSE 
				temp:=rootHubs;
				WHILE temp.nextRootHub#NIL DO temp:=temp.nextRootHub; END;
				temp.nextRootHub:=driver;
			END;

			INC(i);
		END;
	END;
	
	(* register the internal USB root hub driver at the internal drivers registry *)
	drivers.Add(Probe, DriverName, DriverDescription, 10);
	
END InstallRootHubs;

PROCEDURE Cleanup;
VAR
	temp : UsbRootHubDriver;
BEGIN
	temp:=rootHubs;
	WHILE temp#NIL DO 
		temp.Terminate;
		temp.AwaitDead;
		temp:=temp.nextRootHub;
	END;
	AosPlugins.main.Remove(usbDrivers);
END Cleanup; 

PROCEDURE Init*(ptr : PTR) : PTR;
BEGIN
	(* do nothing *)
	RETURN NIL;
END Init;

BEGIN
	
	(* system wide registry for USB device drivers *)
	NEW(usbDrivers, "AosUsb","USB device drivers"); 
	
	(* create internal driver registry *)
	NEW(drivers);

	AosModules.InstallTermHandler(Cleanup);

	(* install USB root hub drivers for all registred USB host controllers *)
	InstallRootHubs; 
	
	AosOut.String("AosUsb: USB driver loaded."); AosOut.Ln;
END AosUsb.

(** Init : AosUsb.Init ~
	  Show installed USB device drivers: AosUsb.ShowDrivers ~
	  Show attached USB devices: AosUsb.Info ~
*)	


		
