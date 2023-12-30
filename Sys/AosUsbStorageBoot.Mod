MODULE AosUsbStorageBoot; (** AUTHOR: "staubesv"; PURPOSE: "USB mass storage boot driver"; *)
(**
 * This modules was built to support a smaller USB mass storage device driver to keep to boot file small. It registers
 * the USB mass storage bulk-only device driver at the USB driver manager.
 *
 * History:
 *	
 *	09.02.2006	First release (staubesv)
 *	07.04.2006	Added option to specifiy USB boot device using a config string (staubesv)
 *	05.07.2006 	Adapted to AosUsbdi (staubesv)
 *	02.08.2006	Adapted to AosUsbdi (staubesv)
 *)
 
IMPORT
	SYSTEM, AosBoot, AosOut, AosDisks, AosPlugins, AosUsbdi, Base := AosUsbStorageBase, BOT := AosUsbStorageBot;

CONST

	Name = "UsbStorageBoot";
	Description = "USB Mass Storage Boot Driver";
	Priority = 10;

	(* This driver blocks until a device named DefaultBootDevice is made accessible (put into AosDisks.registry).	*)
	(* The default setting can be overriden using the UsbBootDevice config string.								*)
	DefaultBootDevice = "USB0";
	
VAR
	(* Driver should only be assigned to one device *)
	assigned : BOOLEAN;

PROCEDURE Probe(dev : AosUsbdi.UsbDevice; id : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR
	protocol, i : LONGINT;
	bulkInEndpoint, bulkOutEndpoint  : LONGINT;
	bot : BOT.BulkOnlyTransport;
	description : AosUsbdi.Description;
	driver : Base.StorageDriver;
BEGIN
	IF assigned THEN RETURN NIL; END;

	(* Is it a bulk-only transport USB Mass Storage Class device ? *)
	IF id.bInterfaceClass # 8 THEN RETURN NIL END;
	IF id.bInterfaceProtocol # 50H THEN RETURN NIL; END;

	CASE id.bInterfaceSubClass OF
		1 : protocol := Base.ProtocolRBC; description := "Usb Reduced Block Command Drive";
		|2 : protocol := Base.Protocol8020; description := "Usb SFF8020i ATAPI device";
		|3 : protocol := Base.ProtocolQIC157; description := "Usb QIC-157 Tape device";
		|4 : protocol := Base.ProtocolUFI; description := "Usb UFI Floppy drive"; 
		|5 : protocol := Base.Protocol8070; description := "Usb SFF8070i ATAPI device";
		|6 : protocol := Base.ProtocolUTS; description := "Usb Transparent SCSI device";
	ELSE
		RETURN NIL; (* Protocol not supported *)
	END;
	
	(* now parse all endpoints *)
	IF (id.bNumEndpoints # 2) & (id.bNumEndpoints # 3) THEN RETURN NIL END;

	FOR i := 0 TO id.bNumEndpoints - 1 DO
		IF id.endpoints[i].type = AosUsbdi.BulkOut THEN
			bulkOutEndpoint := id.endpoints[i].bEndpointAddress;
		ELSIF id.endpoints[i].type = AosUsbdi.BulkIn THEN
			bulkInEndpoint := id.endpoints[i].bEndpointAddress;
		END;
	END;

	IF (bulkInEndpoint = 0) OR (bulkOutEndpoint = 0) THEN RETURN NIL END;

	NEW(bot); driver := bot;

	driver.bulkIn := bulkInEndpoint;
	driver.bulkOut := bulkOutEndpoint;
	driver.transportProtocol := protocol;
	driver.transportMethod := Base.MethodBulkOnly;
	driver.description := description;
	assigned := TRUE;
	RETURN driver;
END Probe;	

(* Block until storage device BootDev has been added to AosDisks.registry if booting from USB storage device *)
PROCEDURE WaitForBootDevice;
VAR ignore : AosPlugins.Plugin; bootDevice : ARRAY 32 OF CHAR;
BEGIN
	AosBoot.GetConfig("UsbBootDevice", bootDevice);
	IF bootDevice = "" THEN bootDevice := DefaultBootDevice; END;
	AosOut.Enter; AosOut.String("AosUsbStorage: Booting from USB. Awaiting device "); AosOut.String(bootDevice); AosOut.String("..."); AosOut.Exit;
	ignore :=  AosDisks.registry.Await(bootDevice);
	AosOut.Enter; AosOut.String("AosUsbStorage: Boot device "); AosOut.String(bootDevice); AosOut.String(" connected."); AosOut.Exit;
END WaitForBootDevice;

PROCEDURE Install*(ptr : PTR) : PTR;
BEGIN
	RETURN NIL;
END Install;

BEGIN
	AosUsbdi.drivers.Add(Probe, Name, Description, Priority);
	WaitForBootDevice;
END AosUsbStorageBoot.

AosUsbStorageBoot.Install ~  S.Free AosUsbStorageBoot ~
