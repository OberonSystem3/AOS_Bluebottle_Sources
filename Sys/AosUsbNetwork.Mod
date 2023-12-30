MODULE AosUsbNetwork; (** AUTHOR: "staubesv"; PURPOSE: "USB network device driver framework"; *)
(**
 * History:
 *
 *	03.11.2006	First release (staubesv)
 *)
 
IMPORT
	AosOut, AosUsbdi, AosCommands, AosIO, AosNet, AosPlugins;
	
CONST

	Ok* = 0;
	Error* = 1;
	Unsupported* = 2;
	
	MinEthernetFrameSize* = 60;
	MaxEthernetFrameSize* = 1514;
	EthernetHeaderSize* = 14;
	
	Name = "UsbNet#";
	Description = "USB Link Device";
	
	ModuleName = "AosUsbNetwork";
	
	AddressSize = 6;
	
	RegisterAtAosNet = TRUE;
	
TYPE

	UsbLinkDevice = OBJECT (AosNet.LinkDevice)
	VAR
		controller : UsbNetworkController;

		PROCEDURE Linked*(): LONGINT;
		BEGIN
			RETURN controller.linkStatus;
		END Linked;
		
		PROCEDURE DoSend*(dst: AosNet.LinkAdr; type: LONGINT; VAR l3hdr, l4hdr, data: ARRAY OF CHAR;  h3len, h4len, dofs, dlen: LONGINT);
		BEGIN
			controller.SendFrame(dst, type, l3hdr, l4hdr, data, h3len, h4len, dofs, dlen);
		END DoSend;
		
		PROCEDURE Finalize(connected: BOOLEAN);
		BEGIN
			controller.Finalize;
			Finalize^(connected);
		END Finalize;
		
		PROCEDURE Diag*;
		BEGIN
			Show(" Diagnostics:"); AosOut.Ln;
			IF controller # NIL THEN controller.Diag;
			ELSE AosOut.String("No controller available."); AosOut.Ln;
			END;
		END Diag;
		
		PROCEDURE Show*(string : ARRAY OF CHAR);
		BEGIN
			AosOut.String(name); AosOut.String(" ("); AosOut.String(desc); AosOut.String("): "); AosOut.String(string);
		END Show;

	END UsbLinkDevice;
	
TYPE

	UsbNetworkController* = OBJECT (AosUsbdi.Driver)
	VAR
		bulkInPipe-, bulkOutPipe-, interruptInPipe- : AosUsbdi.Pipe;
		
		rxBuffer-, interruptInBuffer- : AosUsbdi.BufferPtr;
		
		linkDevice- : UsbLinkDevice;
		linkStatus* : LONGINT;
		
		(** Interface to be implemented by actual network controller driver *)
		
		PROCEDURE SendFrame*(dst: AosNet.LinkAdr; type: LONGINT; VAR l3hdr, l4hdr, data: ARRAY OF CHAR;  h3len, h4len, dofs, dlen: LONGINT); (* abstract *)
		BEGIN {EXCLUSIVE} HALT(301); END SendFrame;

		PROCEDURE GetLinkAddress*(VAR linkAddress : AosNet.LinkAdr; VAR res : LONGINT); (* abstract *)
		BEGIN HALT(301); END GetLinkAddress;
		
		PROCEDURE SetLinkAddress*(linkAddress : AosNet.LinkAdr; VAR res : LONGINT); (* abstract *)
		BEGIN HALT(301); END SetLinkAddress;
		
		PROCEDURE HandleInterrupt*(status : AosUsbdi.Status; actLen : LONGINT); (* abstract *)
		BEGIN HALT(301); END HandleInterrupt;
		
		PROCEDURE HandleBulkIn*(status : AosUsbdi.Status; actLen : LONGINT); (* abstract *)
		BEGIN HALT(301); END HandleBulkIn;
		
		PROCEDURE InitController*(VAR rxBuffer : AosUsbdi.BufferPtr) : BOOLEAN; (* abstract *)
		BEGIN HALT(301); END InitController;
		
		PROCEDURE Finalize*; (* abstract *)
		BEGIN HALT(301); END Finalize;

		PROCEDURE Diag*;
		BEGIN
			AosOut.String("Diagnostics of "); AosOut.String(name);
			AosOut.String(" ("); AosOut.String(desc); AosOut.String(")"); AosOut.Ln;
		END Diag;
		
		PROCEDURE InitLinkDevice() : BOOLEAN;
		VAR name : AosPlugins.Name; nofDevices, i, res : LONGINT;
		BEGIN
			NEW(linkDevice, AosNet.TypeEthernet, 1000, AddressSize);
			
			linkDevice.controller := SELF;
			
			nofDevices := GetNofDevices();
			name := Name;
			i := 0; WHILE name[i] # 0X DO INC(i) END;
			IF nofDevices > 9 THEN
				name[i] := CHR(ORD("A") + nofDevices - 10);
			ELSE
				name[i] := CHR(ORD("0") + nofDevices);
			END;
			name[i+1] := 0X;
			linkDevice.SetName(name);
			linkDevice.desc := Description;
			
			(* Set ethernet broadcast address: FF-FF-FF-FF-FF-FF *)
			FOR i := 0 TO 5 DO linkDevice.broadcast[i] := 0FFX; END; 

			GetLinkAddress(linkDevice.local, res);
			IF res # Ok THEN
				Show("Could not get link address, res: "); AosOut.Int(res, 0); AosOut.Ln;
				RETURN FALSE;
			END;
			
			IF ~RegisterAtAosNet THEN RETURN TRUE; END;
			
			AosNet.registry.Add(linkDevice, res);
			ASSERT(res = AosPlugins.Ok);
			IncNofDevices;

			RETURN TRUE;
		END InitLinkDevice;		
		
		PROCEDURE GetPipes(VAR bulkInPipe, bulkOutPipe, interruptInPipe : AosUsbdi.Pipe);
		VAR i : LONGINT; bulkInEndpoint, bulkOutEndpoint, interruptInEndpoint : LONGINT;
		BEGIN
			FOR i := 0 TO LEN(interface.endpoints)-1 DO
				IF interface.endpoints[i].type = AosUsbdi.BulkIn THEN
					bulkInEndpoint := interface.endpoints[i].bEndpointAddress;
				ELSIF interface.endpoints[i].type = AosUsbdi.BulkOut THEN
					bulkOutEndpoint := interface.endpoints[i].bEndpointAddress;
				ELSIF interface.endpoints[i].type = AosUsbdi.InterruptIn THEN
					interruptInEndpoint := interface.endpoints[i].bEndpointAddress;
				END;
			END;	
			IF bulkInEndpoint # 0 THEN bulkInPipe := device.GetPipe(bulkInEndpoint); END;
			IF bulkOutEndpoint # 0 THEN bulkOutPipe := device.GetPipe(bulkOutEndpoint); END;
			IF interruptInEndpoint # 0 THEN interruptInPipe := device.GetPipe(interruptInEndpoint); END;
		END GetPipes;
		
		PROCEDURE Connect*() : BOOLEAN;
		VAR status : AosUsbdi.Status;
		BEGIN
			linkStatus := AosNet.LinkUnknown;			
			
			GetPipes(bulkInPipe, bulkOutPipe, interruptInPipe); 
			
			IF (bulkInPipe = NIL) OR (bulkOutPipe = NIL) OR (interruptInPipe = NIL) THEN
				Show("Device endpoints not found."); AosOut.Ln;
				RETURN FALSE;
			END;
		
			IF ~InitController(rxBuffer) THEN
				Show("Controller initialization failed."); AosOut.Ln;
				RETURN FALSE;
			END;
			
			bulkInPipe.SetTimeout(0);
			bulkInPipe.SetCompletionHandler(HandleBulkIn);
			
			status := bulkInPipe.Transfer(bulkInPipe.maxPacketSize, 0, rxBuffer^); (* ignore status *) 

			(* setup status pipe *)
			NEW(interruptInBuffer, interruptInPipe.maxPacketSize);
			
			interruptInPipe.SetTimeout(0);
			interruptInPipe.SetCompletionHandler(HandleInterrupt);
			
			status := interruptInPipe.Transfer(interruptInPipe.maxPacketSize, 0, interruptInBuffer^); (* ignore status *)

			IF ~InitLinkDevice() THEN
				Show("Link device initialization failed."); AosOut.Ln;
				RETURN FALSE;
			END;
						
			RETURN TRUE;
		END Connect;
	
		PROCEDURE Disconnect*;
		BEGIN
			IF ~RegisterAtAosNet THEN RETURN; END;
			AosNet.registry.Remove(linkDevice);
		END Disconnect;
		
	END UsbNetworkController;
	
VAR
	nofDevices : LONGINT;

(** Show diagnostics of the specified link device *)
PROCEDURE Diag*(par : ANY) : ANY; (** linkdevice ~ *)
VAR plugin : AosPlugins.Plugin; name : ARRAY 128 OF CHAR; r : AosIO.StringReader;
BEGIN
	AosCommands.PosPar(par, r);
	r.String(name);
	plugin := AosNet.registry.Get(name);
	IF plugin # NIL THEN
		IF plugin IS UsbLinkDevice THEN
			plugin(UsbLinkDevice).Diag;
		ELSE
			Show("Link device "); AosOut.String(name); AosOut.String(" is not a USB link device."); AosOut.Ln;
		END;
	ELSE
		Show("Link device "); AosOut.String(name); AosOut.String(" not found."); AosOut.Ln;
	END;
	RETURN NIL
END Diag;

PROCEDURE IncNofDevices;
BEGIN {EXCLUSIVE}
	INC(nofDevices);
END IncNofDevices;

PROCEDURE GetNofDevices() : LONGINT;
BEGIN {EXCLUSIVE}
	RETURN nofDevices;
END GetNofDevices;
	
PROCEDURE Show(string : ARRAY OF CHAR);
BEGIN
	AosOut.String(ModuleName); AosOut.String(": "); AosOut.String(string);
END Show;

END AosUsbNetwork.

AosUsbNetwork.Diag UsbNet#0 ~
AosUsbNetwork.Diag UsbNet#1 ~
AosUsbNetwork.Diag UsbNet#2 ~

S.Free AosUsbNetwork ~
