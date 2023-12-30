MODULE AosUsbPrinter;  (** AUTHOR "staubesv"; PURPOSE: "USB Printing Device Class Driver"; *)
(**
 * This is the Bluebottle implementation of the USB Printing Device Class driver. Note that this driver is mainly 
 * for transport data between the host and a USB printer device. You will need approriate Page Description Language (PDL)
 * Printer Control Protocol (PCP) support to be able to actually print anything. 
 *
 * Usage:
 *	AosUsbPrinter.Install ~ loads this driver
 *	S.Free AosUsbPrinter ~ unloads it
 *
 * References: 
 *	Universal Serial Bus Device Class Definition for Printing Devices 1.0, www.usb.org
 *
 * History:
 *	01.12.2005 	First release (staubesv)
 *	09.01.2006	Adapted to AosUsb.Mod changes (staubesv)
 *	05.07.2006	Adapted to AosUsbdi (staubesv)
 *)

IMPORT SYSTEM, AosOut, AosModules, AosUsbdi;

CONST

	Name = "UsbPrinter";	
	Description = "USB Printing Device Class Driver";
	Priority = 10; 
	
	Debug = TRUE;
	Trace = TRUE;
	
	StatusPaperEmpty = {5};
	StatusSelected = {4};
	StatusNoError = {3};
	
	(* Printing devices class specific request codes *)
	PrGetDeviceId = 0;
	PrGetPortStatus = 1;
	PrSoftReset = 2;
	
	(* Printer interface type *)
	PitUnidirectional = 01H;
	PitBidirectional = 02H;
	Pit1284 = 03H; (* IEEE 1284.4 compatible bi-directional interface *)
	PitVendorSpecific = 0FFH;

TYPE

	Printer= OBJECT (AosUsbdi.Driver)
	VAR
		defaultpipe, bulkInPipe, bulkOutPipe : AosUsbdi.Pipe;
		
		(* Printer info *)
		interfaceType : LONGINT;
		deviceId : ARRAY 256 OF CHAR;
		
		PROCEDURE Connect() : BOOLEAN;
		BEGIN
			defaultpipe := device.GetPipe(0);
			IF defaultpipe = NIL THEN
				IF Debug THEN AosOut.String("AosUsbPrinter: Could not get default pipe."); AosOut.Ln; END;
				RETURN FALSE;
			END;			
			
			bulkOutPipe := device.GetPipe(1);
			IF bulkOutPipe = NIL THEN 
				IF Debug THEN AosOut.String("AosUsbPrinter: Could not get bulk out pipe."); AosOut.Ln; END;
				RETURN FALSE;
			END;

			IF interfaceType # PitUnidirectional THEN
				bulkInPipe := device.GetPipe(82H);
				IF bulkInPipe = NIL THEN
					IF Debug THEN AosOut.String("AosUsbPrinter: Could not get bulk in pipe."); AosOut.Ln; END;
					RETURN FALSE;
				END;
			END;
			
			IF ~GetDeviceId(deviceId, 0,0,0) THEN
				IF Debug THEN AosOut.String("AosUsbPrinter: Could not get device ID."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			RETURN TRUE;
		END Connect;
	
		PROCEDURE Disconnect;
		BEGIN
			AosOut.String("AosUsbPrinter: "); AosOut.String(name); AosOut.String(" disconnected."); AosOut.Ln;
		END Disconnect;
		
		(* 
		 * This class-specific request returns the device ID strings that is compatible with IEEE1284 for
		 * the specified interface.
		 * @param config Zero-based USB device configuration index
		 * @param intf Zero-based USB device interface index
		 * @param alt Zero-based USB device alternate interface index
		 *)
		PROCEDURE GetDeviceId(VAR deviceId : ARRAY OF CHAR; config, intf, alt : LONGINT) : BOOLEAN;
		VAR
			buffer : AosUsbdi.BufferPtr; 
			wValue, wIndex, len, i : LONGINT;
			string : POINTER TO ARRAY OF CHAR;
		BEGIN
			wValue := config; 
			wIndex := SYSTEM.LSH(intf, 8) + alt;
			NEW(buffer, 2);
			(* First we get the length of the device ID string (first 2 bytes) *)
			IF device.Request(AosUsbdi.ToHost + AosUsbdi.Class + AosUsbdi.Interface, PrGetDeviceId, wValue, wIndex, 2, buffer^) = AosUsbdi.Ok THEN
				(* Length is encoded in big endian *)
				len := SYSTEM.VAL(LONGINT, ORD(buffer[0]))*100H + SYSTEM.VAL(LONGINT, ORD(buffer[1]));
				NEW(buffer, len);
				IF device.Request(AosUsbdi.ToHost + AosUsbdi.Class + AosUsbdi.Interface, PrGetDeviceId, wValue, wIndex, len, buffer^) = AosUsbdi.Ok THEN
					NEW(string, len-2);
					FOR i := 0 TO len-3 DO string[i] := buffer[i+2]; END; 
					COPY(string^, deviceId);
					IF Trace THEN AosOut.String("AosUsbPrinter: DeviceID: "); AosOut.String(deviceId); AosOut.Ln; END;
					RETURN TRUE;
				ELSIF Debug THEN AosOut.String("AosUsbPrinter: Could not read device ID."); AosOut.Ln; 
				END;				
			ELSIF Debug THEN AosOut.String("AosUsbPrinter: GetDeviceID's first two bytes  failed."); AosOut.Ln; 
			END; 
			RETURN FALSE; 
		END GetDeviceId;
		
		(*
		 * This class-specific request returns the printer's current status in a format which is compatible with the
		 * status register of a standard parallel port printer.
		 * @param portstatus Will be set to the retrieved status
		 * @return TRUE, if operation succeeded, FALSE otherwise
		 *)
		PROCEDURE GetPortStatus(VAR portstatus : SET) : BOOLEAN;
		VAR buffer : AosUsbdi.BufferPtr;
		BEGIN
			NEW(buffer, 1);
			IF device.Request(AosUsbdi.ToHost + AosUsbdi.Class + AosUsbdi.Interface, PrGetPortStatus, 0, interface.bInterfaceNumber, 1, buffer^) = AosUsbdi.Ok THEN
				portstatus := SYSTEM.VAL(SET, buffer[0]);
				IF Trace THEN ShowPrinterStatus(portstatus); END;
				RETURN TRUE;
			ELSE
				IF Debug THEN AosOut.String("AosUsbPrinter: GetPortStatus failed."); AosOut.Ln; END;
				RETURN FALSE;
			END;
		END GetPortStatus;
		
		(*
		 * This class-specific request flushes all buffers and resets the bulk out and bulk in pipes to their
		 * default states. This request will cleas all stall conditions.
		 * @return TRUE, if operation succeeded, FALSE otherwise
		 *)
		PROCEDURE SoftReset() : BOOLEAN;
		VAR dummy : AosUsbdi.BufferPtr;
		BEGIN
			NEW(dummy, 1);
			IF device.Request(AosUsbdi.ToDevice + AosUsbdi.Class + AosUsbdi.Interface, PrSoftReset, 0, interface.bInterfaceNumber, 0, dummy^) = AosUsbdi.Ok THEN
				IF Trace THEN AosOut.String("AosUsbPrinter: Printer resetted."); AosOut.Ln; END;
				RETURN TRUE;
			ELSE
				IF Debug THEN AosOut.String("AosUsbPrinter: SoftReset failed."); AosOut.Ln; END;
				RETURN FALSE;
			END;
		END SoftReset;
		
	END Printer;

(* Display textual representation of the printer status register *)
PROCEDURE ShowPrinterStatus(status : SET);
BEGIN
	AosOut.String("AosUsbPrinter: Printer status: Paper: "); 
	IF status * StatusPaperEmpty # {} THEN AosOut.String("Empty"); ELSE AosOut.String("Not Empty"); END;
	AosOut.String(", Selected: "); 
	IF status * StatusSelected # {} THEN AosOut.String("Selected"); ELSE AosOut.String("Not Selected"); END;
	AosOut.String(", ");
	IF status * StatusNoError # {} THEN AosOut.String("No Error"); ELSE AosOut.String("Error"); END;
	AosOut.Ln;
END ShowPrinterStatus;

PROCEDURE Probe(dev : AosUsbdi.UsbDevice; id : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR driver : Printer;
BEGIN
	(* check whether the probed device is a supported USB mouse *)
	IF id.bInterfaceClass # 7 THEN RETURN NIL END; (* Base class for Printers *)
	IF id.bInterfaceSubClass # 1 THEN RETURN NIL END; (* Printer *)
	
	NEW(driver); driver.interfaceType := id.bInterfaceProtocol; 
	IF Trace THEN AosOut.String("USB Printer found."); AosOut.Ln; END;
	RETURN driver;
END Probe;
		
PROCEDURE Cleanup;
BEGIN
	AosUsbdi.drivers.Remove(Name);
END Cleanup;

PROCEDURE Install*(ptr : PTR): PTR;
BEGIN
	(* dummy *)
	RETURN NIL;
END Install;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	AosUsbdi.drivers.Add(Probe, Name, Description, Priority)
END AosUsbPrinter.
