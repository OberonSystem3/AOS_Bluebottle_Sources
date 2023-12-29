MODULE AosUsbMouse;  (** AUTHOR "staubesv"; PURPOSE "USB Mouse Driver"; *)

(*	
		Aos USB Mouse Driver (HID boot protocol)
		Reference: http://www.usb.org

		12.2003 staubesv: first release
*)

IMPORT SYSTEM, AosOut, AosUsb, AosModules, AosInputs;

CONST

	Name = "UsbMouse";	
	Description = "USB mouse driver";

TYPE

	MouseDriver= OBJECT (AosUsb.UsbDriver)
	VAR
		transfer : AosUsb.UsbTransfer;
		message : ARRAY 64 OF CHAR;
		status : SET;

		PROCEDURE HandleEvent;
		VAR
		  mm : AosInputs.MouseMsg;

		BEGIN
			status := transfer.GetStatus();
			IF ((status * (AosUsb.ResOK + AosUsb.ResShortPacket)) # {}) & (transfer.TransferedBytes() >= 4) THEN
			
				mm.dx := SYSTEM.VAL(SHORTINT, message[1]);
				mm.dy := SYSTEM.VAL(SHORTINT, message[2]);
				mm.dz := - SYSTEM.VAL(SHORTINT, message[3]);
				IF (SYSTEM.VAL(SET, message[0]) * {0}) # {} THEN mm.keys := mm.keys + {0}; END;
				IF (SYSTEM.VAL(SET, message[0]) * {1}) # {} THEN mm.keys := mm.keys + {2}; END;
				IF (SYSTEM.VAL(SET, message[0]) * {2}) # {} THEN mm.keys := mm.keys + {1}; END;
				
				AosInputs.mouse.Handle(mm);

				transfer.Restart 
			END;
		END HandleEvent;
	
		PROCEDURE Connect;
		VAR
				if : AosUsb.UsbDeviceInterface;
			endpoint : INTEGER;			
		BEGIN
			if := device.actConfiguration.interfaces[interface];  
			endpoint := SHORT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, if.endpoints[0].bEndpointAddress) * {0,1,2,3,7}));
			transfer:=device.SendInterrupt(endpoint, message, 0,  device.data.maxPacketSizeIn[endpoint MOD 16],  0, if.endpoints[0].bInterval);
			transfer.SetIntHandler(HandleEvent)
		END Connect;
	
		PROCEDURE Disconnect;
		BEGIN
			AosOut.String("USB mouse disconnected."); AosOut.Ln;
			IF transfer#NIL THEN transfer.Delete END
		END Disconnect;
	END MouseDriver;


PROCEDURE Probe(dev : AosUsb.UsbDevice; intfc : LONGINT):AosUsb.UsbDriver;
VAR
	if : AosUsb.UsbDeviceInterface;
	mouseDriver : MouseDriver;
BEGIN
	(* check whether the probed device is a supported USB mouse *)
	if := dev.actConfiguration.interfaces[intfc];		
	IF if.bInterfaceClass # 3 THEN RETURN NIL END;
	IF if.bInterfaceSubClass # 1 THEN RETURN NIL END;
	IF if.bInterfaceProtocol # 2 THEN RETURN NIL END;

	AosOut.String("USB mouse found."); AosOut.Ln;

	NEW(mouseDriver, dev, intfc);
	
	RETURN mouseDriver
END Probe;

			
PROCEDURE Cleanup;
BEGIN
	AosUsb.drivers.Remove(Name);
END Cleanup;

PROCEDURE Init*(ptr : PTR): PTR;
BEGIN
	(* dummy *)
	RETURN NIL;
END Init;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	AosUsb.drivers.Add(Probe, Name, Description, 9)
END AosUsbMouse.

(** Init: AosUsbMouse.Init **)
