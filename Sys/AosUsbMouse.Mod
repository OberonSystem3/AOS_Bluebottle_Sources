MODULE AosUsbMouse;  (** AUTHOR "staubesv"; PURPOSE "USB Mouse Driver"; *)
(**	
 * Bluebottle USB Mouse Driver (HID boot protocol)
 *
 * Usage:
 *	AosUsbMouse.Install ~ loads this driver
 *	S.Free AosUsbMouse ~ unloads this driver
 *		
 *	The HID boot protocol for USB mice supports 3 buttons and 2 axes. 
 *
 * References:
 *	Device Class Definition for Human Interface Devices (HID), Version 1.11, 27.06.2001, www.usb.org
 *
 * History:
 *	01.12.2005	Added MouseSpeed & MouseAcceleration (staubesv)
 *	10.10.2006	Adapted to AosUsbHid (staubesv)
 *	28.02.2007	Removed mouse wheel hack since new HID driver can correctly handle it (staubesv)
 *)

IMPORT SYSTEM, AosOut, AosModules, AosInputs, AosUsbdi, AosUsbHid;

CONST

	Name = "UsbMouse";	
	Description = "HID boot protocol mouse driver";
	
	(* Mouse Configuration *)
	MouseSpeed = 50;
	MouseAcceleration = 0;
	
	Debug = TRUE;

TYPE

	MouseDriver= OBJECT (AosUsbHid.HidDriver)
	VAR
		buffer : AosUsbdi.BufferPtr;
		pipe : AosUsbdi.Pipe;
		
		lastDx, lastDy : LONGINT;
		accelX, accelY : REAL;
	
		PROCEDURE HandleEvent(status : AosUsbdi.Status; actLen : LONGINT);
		VAR mm : AosInputs.MouseMsg; dx, dy : LONGINT;
		BEGIN
			IF (status = AosUsbdi.Ok) OR ((status = AosUsbdi.ShortPacket) & (actLen >= 3))  THEN
				dx := SYSTEM.VAL(SHORTINT, buffer[1]); 
				dy := SYSTEM.VAL(SHORTINT, buffer[2]);
				
				accelX := 1.0 + ABS(dx - lastDx) / 128 * MouseAcceleration;
				accelY := 1.0 + ABS(dy - lastDy) / 128 * MouseAcceleration; 
				
				lastDx := dx; 
				lastDy := dy;
								
				mm.dx :=ENTIER(MouseSpeed / 50.0 *  dx * accelX);
				mm.dy := ENTIER(MouseSpeed / 50.0 * dy * accelY);
				
				IF (SYSTEM.VAL(SET, buffer[0]) * {0}) # {} THEN mm.keys := mm.keys + {0}; END;
				IF (SYSTEM.VAL(SET, buffer[0]) * {1}) # {} THEN mm.keys := mm.keys + {2}; END;
				IF (SYSTEM.VAL(SET, buffer[0]) * {2}) # {} THEN mm.keys := mm.keys + {1}; END;
				
				AosInputs.mouse.Handle(mm);
				status := pipe.Transfer(pipe.maxPacketSize, 0, buffer^);
			ELSE 
				IF status = AosUsbdi.Stalled THEN
					IF pipe.ClearHalt() THEN
						IF Debug THEN AosOut.String("AosUsbMouse: Stall on Interrupt Pipe cleared."); AosOut.Ln; END;
						status := pipe.Transfer(pipe.maxPacketSize, 0, buffer^); (* ignore status *)
					ELSE
						IF Debug THEN AosOut.String("AosUsbMouse: Couldn't clear stall on interrupt pipe. Abort."); AosOut.Ln; END;
						device.FreePipe(pipe); 
					END;
				END;
			END;
		END HandleEvent;
	
		PROCEDURE Connect*() : BOOLEAN;
		VAR endpoint, i : LONGINT; status : AosUsbdi.Status;
		BEGIN
			(* Set the HID boot protocol *)
			IF SetProtocol(AosUsbHid.BootProtocol) = FALSE THEN
				IF Debug THEN AosOut.String("AosUsbMouse: Error: Cannot set boot protocol."); AosOut.Ln; END;
				RETURN FALSE
			END;	
						
			(* Look for the first interrupt IN endpoint of this device *)
			LOOP
				IF i >= LEN(interface.endpoints) THEN EXIT; END;
				IF interface.endpoints[i].type = AosUsbdi.InterruptIn THEN
					endpoint := interface.endpoints[i].bEndpointAddress;
					EXIT;
				END;		
				INC(i);			
			END;
			
			IF endpoint = 0 THEN
				IF Debug THEN AosOut.String("AosUsbMouse: No interrupt IN endpoint found."); AosOut.Ln; END;
				RETURN FALSE;
			END;
						
			pipe := device.GetPipe(endpoint);
			IF pipe = NIL THEN RETURN FALSE END;
			
			NEW(buffer, pipe.maxPacketSize);
			
			pipe.SetTimeout(0);
			pipe.SetCompletionHandler(HandleEvent);
			
			status := pipe.Transfer(pipe.maxPacketSize, 0, buffer^); (* ignore res *) 
			RETURN TRUE;
		END Connect;
	
		PROCEDURE Disconnect*;
		BEGIN
			AosOut.String("USB mouse disconnected."); AosOut.Ln;
		END Disconnect;
		
	END MouseDriver;

PROCEDURE Probe(dev : AosUsbdi.UsbDevice; id : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR driver : MouseDriver;
BEGIN
	IF id.bInterfaceClass # 3 THEN RETURN NIL END; (* HID class *)
	IF id.bInterfaceSubClass # 1 THEN RETURN NIL END; (* Boot protocol subclass *)
	IF id.bInterfaceProtocol # 2 THEN RETURN NIL END; (* Mouse *)
	NEW(driver); RETURN driver;
END Probe;
		
PROCEDURE Install*(ptr : PTR): PTR;
BEGIN
	RETURN NIL;
END Install;

PROCEDURE Cleanup;
BEGIN
	AosUsbdi.drivers.Remove(Name);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	AosUsbdi.drivers.Add(Probe, Name, Description, 10)
END AosUsbMouse.

AosUsbMouse.Install ~  S.Free AosUsbMouse ~ 
