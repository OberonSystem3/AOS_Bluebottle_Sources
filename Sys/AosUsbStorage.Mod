MODULE AosUsbStorage; (** AUTHOR "staubesv"; PURPOSE " USB mass storage driver"; *)
(**
 * This module registers the USB mass storage device driver at the USB driver manager.
 *
 * History:
 *	
 *	09.02.2006	First release (staubesv)
 *	28.06.2006 	Use AosUsbUtilities.Mod (staubesv)
 *	05.07.2006	Adapted to AosUsbdi (staubesv)
 *	02.08.2006	Adapted to AosUsbdi (staubesv)
 *)
 
IMPORT 
	AosOut, SYSTEM, AosModules,
	Base := AosUsbStorageBase,
	CBI := AosUsbStorageCbi, BOT := AosUsbStorageBot, SCM := AosUsbStorageScm, 
	AosUsbdi, AosUsb, Debug := AosUsbDebug, Lib := AosUsbUtilities;

CONST
	
	Name = "UsbStorage";
	Description = "USB Mass Storage Driver";
	Priority = 10;

PROCEDURE Probe(dev : AosUsbdi.UsbDevice; id : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR
	method, protocol : LONGINT;
	bulkInEndpoint, bulkOutEndpoint, interruptEndpoint : LONGINT;
	bulkOnlyTransport : BOT.BulkOnlyTransport;
	cbiTransport : CBI.CBITransport;
	scmTransport : SCM.SCMTransport; 
	description : AosUsbdi.Description;
	driver : Base.StorageDriver;
	i, j, k : LONGINT;
	asciiString : Lib.AsciiString;
	vendor, product, bcd : LONGINT;
	specialInit : BOOLEAN;
BEGIN
	vendor := dev.descriptor.idVendor;
	product := dev.descriptor.idProduct;
	bcd := dev.descriptor.bcdDevice;
	
	IF (vendor = 03EEH) & (product = 0H) & (bcd <= 0245H) THEN (* Override for Mitsumi CD-R/RW driver *) (* UNTESTED !!!!! *)

		method := Base.MethodCBI;
		protocol := Base.Protocol8020;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Mitusmi CD-R/RW Writer (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 03F0H) & (product = 107H) & (bcd = 200H) THEN (* Override for HP CDWriter+ series *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.Protocol8070;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for HP CDWriter+ series (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 03F0H) & (product = 207H) & (bcd = 1H) THEN	(* Override for HP CDWriter 8200e series *) (* BETA !!!! *)

		method := Base.MethodSCMShuttle;
		protocol := Base.Protocol8070;
		specialInit := TRUE;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for HP CDWriter 8200e series (BETA)"); AosOut.Ln; END;

	ELSIF (vendor = 04E6H) & (product = 01H) & (bcd = 200H) THEN (* Override for Matshita LS-120 *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.Protocol8020;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Matshita LS-120 (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 04E6H) & (product = 06H) & (bcd >= 100H) & (bcd <= 200H) THEN (* Override for Shuttle eUSB MMC Adapter *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.ProtocolUTS;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Shuttle eUSB MMC Adapter (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 04E6H) & (product = 07H) & (bcd >= 100H) & (bcd <= 200H) THEN (* Override for Sony Hifd *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.ProtocolUTS;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Sony Hifd (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 04E6H) & (product = 09H) & (bcd = 200H) THEN (* Override for Shuttle eUSB ATAPI Adapter *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.Protocol8020;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Shuttle eUSB ATAPI Adapter (UNTESTED)"); AosOut.Ln;END;

	ELSIF (vendor = 04E6H) & (product = 0AH) & (bcd = 200H) THEN (* Override for Shuttle Compactflash Adapter *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.Protocol8020;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Shuttle Compactflash Adapter (UNTESTED)"); AosOut.Ln;END;

	ELSIF (vendor = 04E6H) & (product = 101H) & (bcd = 200H) THEN (* Override for Shuttle CD-RW Device *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.Protocol8020;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Shuttle CD-RW Device (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 054CH) & (product = 10H) & (bcd >= 106H) & (bcd <= 210H) THEN (* Override for Sony DSC-S30/S70/505V/F505 *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.ProtocolUTS;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Sony DSC-S30/S70/505V/F505 (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 054CH) & (product = 2DH) & (bcd = 100H) THEN (* Override for Sony Memorystick MSAC-US1 *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.ProtocolUTS;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Sony Memorystick MSAC-US1 (UNTESTED)"); AosOut.Ln;END;

	ELSIF (vendor = 057BH) & (product = 0H) & (bcd < 0300H) THEN (* The Y-E Data floppy (The Sony "Vaio" floppy) with rev.number < 3.00) *)
		(* has a bug, must use CB, not CBI *)
		method := Base.MethodCB;
		protocol := Base.ProtocolUFI;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Y-E Data Floppy rev < 3.00"); AosOut.Ln; END;

	ELSIF (vendor = 059FH) & (product = 0A601H) & (bcd = 200H) THEN (* Override for LaCie USB Hard Disk *) (* UNTESTED !!!!! *)
		
		method := Base.MethodCB;
		protocol := Base.ProtocolRBC;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for LaCie USB Hard Disk (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 05ABH) & (product = 31H) & (bcd = 100H) THEN (* Override for In-System USB/IDE bridge (ATAPI) *) (* UNTESTED !!!!! *)

		method := Base.MethodBulkOnly;
		protocol := Base.Protocol8070;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for In-System USB/IDE bridge (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 0644H) & (product = 0H) & (bcd = 100H) THEN	(* Override for Teac floppy drive *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.ProtocolUFI;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Teac Floppy (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 0693H) & (product = 2H) & (bcd = 100H) THEN (* Override for Hagiwara Flashgate Smartmedia *) (* UNTESTED !!!!! *)

		method := Base.MethodBulkOnly;
		protocol := Base.ProtocolUTS;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Hagiwara Smartmedia (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 0693H) & (product = 5H) & (bcd = 100H) THEN (* Override for Hagiwara Flashgate xx? *) (* UNTESTED !!!!! *)

		method := Base.MethodBulkOnly;
		protocol := Base.ProtocolUTS;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Hagiwara Flashgate (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 0781H) & (product = 1H) & (bcd = 200H) THEN	(* Override for Sandisk Imagemate SDDR-05a *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.ProtocolUTS;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Sandisk SDDR-05a (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 0781H) & (product = 100H) & (bcd = 100H) THEN (* Override for Sandisk Imagemate SDDR-12 *) (* UNTESTED !!!!! *)

		method := Base.MethodCB;
		protocol := Base.ProtocolUTS;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Sandisk SDDR-12 (UNTESTED)"); AosOut.Ln; END;

	ELSIF (vendor = 0781H) & (product = 2H) & (bcd = 9H) THEN (* Override for Sandisk Imagemate SDDR-31 *) (* UNTESTED !!!!! *)

		method := Base.MethodBulkOnly;
		protocol := Base.ProtocolUTS;
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: Override for Sandisk SDDR-31 (UNTESTED)"); AosOut.Ln; END;

	ELSE (* generic device detected *)
	
		IF Debug.Trace & Debug.traceScInit THEN AosOut.String("AosUsbStorage: No device specific match... looking for generic USB mass storage devices."); AosOut.Ln; END;

		(* Is it a USB Mass Storage Class device ? *)
		IF id.bInterfaceClass # 8 THEN RETURN NIL END;
	
		CASE id.bInterfaceProtocol OF
			0 :  method := Base.MethodCBI;
			|1 : method := Base.MethodCB;
			|50H : method := Base.MethodBulkOnly;
		ELSE
			RETURN NIL; (* transport method not supported *)
		END;	

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
		
	END;
	
	(* if the USB device does provide string descriptor, we use them as description for the storage device... *)
	IF (dev.descriptor(AosUsb.DeviceDescriptor).sManufacturer#NIL) OR (dev.descriptor(AosUsb.DeviceDescriptor).sProduct#NIL) THEN
		NEW(asciiString, 256); i := 0;
		IF (dev.descriptor(AosUsb.DeviceDescriptor).sManufacturer#NIL) THEN
			LOOP		
				asciiString[i] := dev.descriptor(AosUsb.DeviceDescriptor).sManufacturer[i];
				INC(i); IF (i > LEN(description)-1) OR (i > LEN(dev.descriptor(AosUsb.DeviceDescriptor).sManufacturer)-1) THEN EXIT; END;
			END;
		END;
	
		j := 0;
		IF (dev.descriptor(AosUsb.DeviceDescriptor).sProduct#NIL) OR (i < LEN(description)-1) THEN	
			IF i>=1 THEN asciiString[i-1] := " "; END;
			LOOP
				asciiString[i+j] := dev.descriptor(AosUsb.DeviceDescriptor).sProduct[j];
				INC(j); IF (i+j > LEN(description)-1) OR (j > LEN(dev.descriptor(AosUsb.DeviceDescriptor).sProduct)-1) THEN EXIT; END;
			END;	
			asciiString[i+j-1] := 0X;
		ELSE
			asciiString[i-1] := 0X;
		END;
		
		IF i+j-2 < LEN(description) THEN 
			FOR k := 0 TO i+j-2 DO description[k] := asciiString[k]; END;
			FOR k := i+j-1 TO LEN(description)-1 DO description[k] := 0X; END;
		END;
	END;
	
	(* now parse all endpoints *)
	IF (id.bNumEndpoints # 2) & (id.bNumEndpoints # 3) THEN RETURN NIL END;

	FOR i := 0 TO id.bNumEndpoints - 1 DO
		IF id.endpoints[i].type = AosUsbdi.BulkOut THEN
			bulkOutEndpoint := id.endpoints[i].bEndpointAddress;
		ELSIF id.endpoints[i].type = AosUsbdi.BulkIn THEN
			bulkInEndpoint := id.endpoints[i].bEndpointAddress;
		ELSIF id.endpoints[i].type = AosUsbdi.InterruptIn THEN
			interruptEndpoint := id.endpoints[i].bEndpointAddress;  
		END;
	END;

	(* Create the driver instance *)
	IF method = Base.MethodCBI THEN
			IF (bulkInEndpoint = 0) OR (bulkOutEndpoint = 0) OR (interruptEndpoint = 0) THEN RETURN NIL END;
			NEW(cbiTransport);
			driver := cbiTransport; 
	ELSIF method = Base.MethodCB THEN
			IF (bulkInEndpoint = 0) OR (bulkOutEndpoint = 0) THEN RETURN NIL END;
			NEW(cbiTransport);
			driver := cbiTransport; 
	ELSIF method = Base.MethodBulkOnly THEN
			IF (bulkInEndpoint = 0) OR (bulkOutEndpoint = 0) THEN RETURN NIL END;
			NEW(bulkOnlyTransport);
			driver := bulkOnlyTransport;
	ELSIF method = Base.MethodSCMShuttle THEN
			IF (bulkInEndpoint = 0) OR (bulkOutEndpoint = 0) THEN RETURN NIL END;
			NEW(scmTransport);
			driver := scmTransport; 
	ELSE
		RETURN NIL;
	END;

	(* Special init, if necessary *)
	IF specialInit THEN
		driver.initialize := TRUE;
	END;
	
	driver.bulkIn := bulkInEndpoint;
	driver.bulkOut := bulkOutEndpoint;
	driver.interrupt := interruptEndpoint;
	driver.transportProtocol := protocol;
	driver.transportMethod := method;
	driver.description := description;

	RETURN driver;
END Probe;	

PROCEDURE Install*(par : ANY) : ANY;
BEGIN
	RETURN NIL;
END Install;

PROCEDURE Cleanup();
BEGIN
	AosUsbdi.drivers.Remove(Name); Base.diskManager.RemoveAll;
END Cleanup;

BEGIN
	AosUsbdi.drivers.Add(Probe, Name, Description, Priority);
	AosModules.InstallTermHandler(Cleanup);
END AosUsbStorage.

AosUsbStorage.Install ~ S.Free AosUsbStorage ~

AosUsbStorage.Show ~

PC0.Compile \s AosUsbStorageBase.Mod AosUsbStorageCbi.Mod AosUsbStorageScm.Mod AosUsbStorageBot.Mod
	AosUsbStorageBoot.Mod AosUsbStorage2.Mod ~
	
S.Free AosUsbStorage AosUsbStorageBoot AosUsbStorageBot AosUsbStorageScm AosUsbStorageCbi AosUsbStorageBase ~