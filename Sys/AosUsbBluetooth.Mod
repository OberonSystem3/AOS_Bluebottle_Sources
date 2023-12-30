MODULE  AosUsbBluetooth; (** AUTHOR: "staubesv"; PURPOSE: "USB device driver for USB bluetooth dongles" *)
(**
 * This Module implements 
 *	a) A USB bluetooth dongle driver
 *	b) Bluetooth USB Transport Layer
 *
 * Usage:
 *	AosUsbBluetooth.Install ~ loads this driver
 *	S.Free AosUsbBluetooth ~ unloads it
 *
 * History:
 *
 *	01.12.2005	Adapted to new USB system software, renamed procedure Init to Install, removed obsolete imports  (staubesv)
 *	12.12.2005	Adapted to new USBDI (staubesv)
 *	05.07.2006	Adapted to AosUsbdi (staubesv)
 *)
 
IMPORT AosOut, AosModules, Bluetooth, AosUsbdi;

CONST

	Name = "UsbBluetooth";
	Description = "USB bluetooth dongle driver";

	(* endpoint addresses suggested by Bluetooth Specification 1.0B, p. 765 *)
	EpControlOut = 0;
	EpInterruptIn = 129;  (* 0x81H *)
	EpBulkIn = 130;  (* 0x82H *)
	EpBulkOut = 2;
	
	EpIsoIn = 131;  (* 0x83H, not needed *)
	EpIsoOut = 3;  (* 0x03H, not needed *)
	
	Debug = FALSE;

TYPE

	Handler = PROCEDURE {DELEGATE} (packet : AosUsbdi.Buffer; actLen : LONGINT);	

TYPE
	
	BluetoothDriver* = OBJECT (AosUsbdi.Driver)
	VAR
		eventIn, aclIn, aclOut, defaultpipe : AosUsbdi.Pipe;
		hciEvent : AosUsbdi.BufferPtr;
		aclData : AosUsbdi.BufferPtr;  
		eventHandler, aclHandler : Handler;
		status : AosUsbdi.Status;
		
		PROCEDURE Connect*():BOOLEAN;
		BEGIN
			(* get the USB pipes *)
			defaultpipe := device.GetPipe(0);
			IF defaultpipe = NIL THEN
				IF Debug THEN AosOut.String("AosUsbBluetooth: Error: Couldn't get default control pipe."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			eventIn := device.GetPipe(EpInterruptIn);
			IF eventIn = NIL THEN
				IF Debug THEN AosOut.String("AosUsbBluetooth: Error: Couldn't get interrupt in pipe."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			aclIn := device.GetPipe(EpBulkIn);
			aclOut := device.GetPipe(EpBulkOut);
			IF (aclIn = NIL) OR (aclOut = NIL) THEN 
				IF Debug THEN AosOut.String("AosUsbBluetooth: Error: Couldn't get bulk in/out pipes."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			(* register pipe handlers and setup IN transfers *)		
			eventIn.SetCompletionHandler(HciEventHandler);
			eventIn.SetTimeout(0);
			status := eventIn.Transfer(16, 0, hciEvent^); 
			
			aclIn.SetCompletionHandler(ReadACL);
			aclIn.SetTimeout(0); (* non-blocking *)
			status := aclIn.Transfer(64, 0, aclData^); 
			
			RETURN TRUE;
		END Connect;
		
		PROCEDURE Disconnect*;
		BEGIN
			AosOut.String("USB Blueetooth dongle "); AosOut.String(name); AosOut.String(" disconnected."); AosOut.Ln;
		END Disconnect;
			
		PROCEDURE SendACL*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; VAR res : LONGINT);
		VAR
			buffer : AosUsbdi.BufferPtr;
			status : AosUsbdi.Status;
			i : LONGINT;
		BEGIN
			NEW(buffer, len); FOR i:=0 TO len-1 DO	buffer[i] := buf[i]; END;
			status := aclOut.Transfer(len, ofs, buffer^);
			IF (status = AosUsbdi.Ok) OR (status = AosUsbdi.ShortPacket) THEN res := 0; ELSE res := 1; END;
		END SendACL;
		
		PROCEDURE ReadACL*(status : AosUsbdi.Status; actLen : LONGINT);
		BEGIN
			IF Debug THEN AosOut.String("AosUsbBluetooth: Received data ACL In Pipe."); AosOut.Ln;END;
			IF (status = AosUsbdi.Ok) OR ((status = AosUsbdi.ShortPacket) & (actLen > 0)) THEN (* received ACL data *)
				IF aclHandler # NIL THEN aclHandler(aclData^, actLen); END;
				status := aclIn.Transfer(64, 0, aclData^); (* ignore result *)
			END;
		END ReadACL;
		
		PROCEDURE SendCommand*(buf: ARRAY OF CHAR; ofs, len: LONGINT; VAR res: LONGINT);
		VAR
			buffer : AosUsbdi.BufferPtr;
			status : AosUsbdi.Status;
			i : LONGINT;
		BEGIN		
			NEW(buffer, len); FOR i:=0 TO len-1 DO buffer[i] := buf[i]; END;
			status :=defaultpipe.Request(AosUsbdi.ToDevice  + AosUsbdi.Class + AosUsbdi.Endpoint, 0, 0, 0, len, buffer^);
			IF (status = AosUsbdi.Ok) OR (status = AosUsbdi.ShortPacket) THEN res := 0; ELSE res := 1; END;
		END SendCommand;
		
		PROCEDURE SetEventHandler*(proc : Handler);
		BEGIN
			eventHandler:=proc;
		END SetEventHandler;
		
		PROCEDURE SetAclHandler*(proc: Handler);
		BEGIN
			aclHandler:=proc;
		END SetAclHandler;
		
		PROCEDURE HciEventHandler(status : AosUsbdi.Status; actLen : LONGINT);
		BEGIN
			IF (status = AosUsbdi.Ok) OR ((status = AosUsbdi.ShortPacket) & (actLen > 0)) THEN
				IF eventHandler # NIL THEN eventHandler(hciEvent^, actLen); END;
				status := eventIn.Transfer(16, 0, hciEvent^); 
			ELSE
				IF Debug THEN AosOut.String("AosUsbBluetooth: HCI Event Handling: Error."); AosOut.Ln; END;
			END;
		END HciEventHandler;
		
		PROCEDURE &Init;
		BEGIN
			NEW(hciEvent, 16);
			NEW(aclData, 64);
		END Init;
	
	END BluetoothDriver;

PROCEDURE Probe(dev : AosUsbdi.UsbDevice; id : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR driver : BluetoothDriver;
BEGIN
	(* check whether the probed device is a supported USB bluetooth dongle *)
	IF id.bInterfaceClass # 224 THEN RETURN NIL END;
	IF id.bInterfaceSubClass # 1 THEN RETURN NIL END;
	IF id.bInterfaceProtocol # 1 THEN RETURN NIL END;
	IF id.bNumEndpoints # 3 THEN RETURN NIL; END;
	
	(* parse endpoints *)
	IF (id.endpoints[0].bEndpointAddress # EpInterruptIn) OR 
		(id.endpoints[1].bEndpointAddress # EpBulkOut) OR 
		(id.endpoints[2].bEndpointAddress # EpBulkIn) THEN (* not compatible *) RETURN NIL; END;
	AosOut.String("USB bluetooth dongle found."); AosOut.Ln;
	NEW(driver);		
	RETURN driver;
END Probe;
	
PROCEDURE Install*(ptr : PTR) : PTR;
BEGIN (* load module *)
  RETURN NIL;
END Install;						

PROCEDURE Cleanup;
BEGIN
	AosUsbdi.drivers.Remove(Name);
END Cleanup;

BEGIN
	AosUsbdi.drivers.Add(Probe, Name, Description,10);
	AosModules.InstallTermHandler(Cleanup);
END AosUsbBluetooth.