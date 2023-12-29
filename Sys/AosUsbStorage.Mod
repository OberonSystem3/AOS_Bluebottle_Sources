MODULE AosUsbStorage; (** AUTHOR "cplattner"; PURPOSE "Generic USB storage driver"; *)
(*
	Aos USB Mass Storage Device Driver

	Reference: http://www.usb.org
	
	SCSI commands borrowed from SCSI.Mod

	30.09.2000 cp first release
	20.10.2000 cp many improvements (BulkOnly, UTS)
	
	Overview:
	
	StorageDevice = OBJECT(AosDisks.Device);     
	
	UsbStorageDriver = OBJECT(AosUsb.UsbDriver);       (* Transport() and Reset() are abstract *)
	
		BulkOnlyTransport = OBJECT(UsbStorageDriver);   (* implements bulk only transport layer *)
		CBITransport = OBJECT(UsbStorageDriver)			 (* implements CBI and CB transport layer *)
		SCMTransport = OBJECT(CBITransport)                    (* implements SCM transport layer, inherits Reset() from CBITransport) *)
		
	DiskManager = OBJECT;   (* does the naming and (un)registers StorageDevices at AosDisks.registry *)
*)

IMPORT SYSTEM, AosModules, AosUsb, AosOut, AosKernel, Disks := AosDisks, AosPlugins;

CONST

	Trace = FALSE;  (* to see whats happening *)
	Debug = TRUE; (* show errors *)
	SenseDebug = TRUE; (* displays results of the sense requests to KernelLog *)
	
	(* name and description of the driver *)
	Name = "UsbStorage";
	Description = "Usb Storage Device Driver";
	
	NoData = {};
	DataIn = {1};
	DataOut = {2};
	
	TransportDone = {1};
	TransportError = {2};
	TransportFatal = {3};
	TransportTimeout = {4};
	TransportSenseError = {5};
	TransportShort = {6};
	
	MethodCBI = 1;
	MethodCB = 2;
	MethodBulkOnly = 3;
	MethodSCMShuttle = 4;
	
	ProtocolUFI = 100;  (* UFI = *)
	ProtocolUTS = 101; (* USB TRANSPARENT SCSI => UTS (plattner definition) *)
	ProtocolRBC = 102; (* RBC = reduced block commands, often used for flash devices *)
	Protocol8020 = 103; (* ATAPI for CDROM *)
	Protocol8070 = 104; (* ATAPI for floppy drives and similar devices *)
	ProtocolQIC157 = 105; (* QIC, meaning the tape company. Typically used by tape devices *)
	
	(* These are the error codes for the Disks module. It allows to send custom errors (> 0) *)
	ErrorDiskFail = 30; (* the catch all code... *)
	ErrorShortTransfer = 31;
	
	(* Constans for the SCM USB-ATAPI Shuttle device *)
	ScmATA = 40X; ScmISA = 50X;
	
	(* data registers *)
	ScmUioEpad = 80X; ScmUioCdt = 40X; ScmUio1 = 20X; ScmUio0 = 10X;
	
	(* user i/o enable registers *)
	ScmUioDrvrst = 80X; ScmUioAckd = 40X; ScmUioOE1 = 20X; ScmUioOE0 = 10X;
	
	(* disk manager object *)
	DmTrace = TRUE;
	
TYPE

	StorageDevice = OBJECT (Disks.Device)
	VAR
		usbDriver : UsbStorageDriver;
		number : LONGINT;
		TransportMethod : INTEGER;
		TransportProtocol : INTEGER;
		next : StorageDevice;

		PROCEDURE Transfer* (op, block, num: LONGINT; VAR data: ARRAY OF CHAR; ofs: LONGINT; VAR diskres: LONGINT);
		VAR
			dir : SET;
			cmd : ARRAY 12 OF CHAR;
			tlen, trans: LONGINT;
			i : LONGINT;
		BEGIN
			FOR i:= 0 TO 11 DO cmd[i] := CHR(0); END;
			
			IF (op = Disks.Read) OR (op = Disks.Write) THEN
				
				IF op = Disks.Read THEN
					cmd[0] := 28X; dir := DataIn;
				ELSE
					cmd[0] := 2AX; dir := DataOut;
				END;
		
				WHILE num > 0 DO
					IF num > 65000 THEN trans := 65000; ELSE trans := num END;
					trans := trans * blockSize;
					cmd[2] := CHR(SYSTEM.LSH(block, -24));
					cmd[3] := CHR(SYSTEM.LSH(block, -16));
					cmd[4] := CHR(SYSTEM.LSH(block, -8));
					cmd[5] := CHR(block);
					cmd[7] := CHR(SYSTEM.LSH(num, -8));
					cmd[8] := CHR(num);
					diskres := usbDriver.InvokeTransport(cmd, 10, dir, data, ofs, trans, tlen, 2000);  (* timeout was set to -1 before *)
					IF diskres # Disks.Ok THEN RETURN; END;
					block := block + trans;
					num := num - trans;
				END;
			ELSE
				diskres := Disks.Unsupported;
			END;
		END Transfer;
		
		PROCEDURE GetSize* (VAR size, diskres: LONGINT);
		VAR
			cmd : ARRAY 12 OF CHAR;
			data : ARRAY 8 OF CHAR;
			tlen : LONGINT;
			i : INTEGER;
		BEGIN
			IF Debug THEN AosOut.String("UsbStorage: Doing GetCapacity command"); AosOut.Ln; END;
			blockSize := 0; size := 0;
			
			(* UFI: Read Capacity command *)
			FOR i:= 0 TO 11 DO cmd[i] := CHR(0); END;
			cmd[0] := CHR(25H);
			
			diskres := usbDriver.InvokeTransport(cmd, 10, DataIn, data, 0, 8, tlen, 10000);
			IF ((diskres # Disks.Ok) & (diskres # ErrorShortTransfer)) OR (tlen < 8) THEN RETURN; END;
		
			FOR i := 0 TO 3 DO
				size := size*100H + ORD(data[i]);
				blockSize := blockSize*100H + ORD(data[4+i])
			END;
		
			INC (size);
			
			diskres := Disks.Ok;
			IF Debug THEN 
				AosOut.String("AosUsbStorage: Disk info: Blocks: "); AosOut.Int(size, 0);
				AosOut.String(" blocksize: "); AosOut.Int(blockSize,0);
				AosOut.String(" size: "); AosOut.Int(size*blockSize,0);
				AosOut.Ln;
			END;
		END GetSize;
		
		PROCEDURE Handle (VAR msg: Disks.Message; VAR diskres: LONGINT);
		VAR
			cmd : ARRAY 12 OF CHAR;
			i : INTEGER;
			tlen : LONGINT;
		BEGIN
			AosOut.String("HANDLE"); AosOut.Ln;
			diskres := Disks.Ok;
		
(*			FOR i:= 0 TO 11 DO cmd[i] := CHR(0); END;
		
			IF msg IS Disks.GetGeometryMsg THEN
				IF TransportProtocol = ProtocolUFI THEN
					WITH msg : Disks.GetGeometryMsg DO msg.spt := 18; msg.hds := 2; msg.cyls := 80; END;
					diskres := Disks.Ok;
				ELSE
					diskres := Disks.Unsupported;
				END;
			ELSIF (msg IS Disks.LockMsg) OR (msg IS Disks.UnlockMsg) THEN
				IF TransportProtocol = ProtocolUFI THEN
					diskres := Disks.Unsupported;
				ELSE
					cmd[0] := 1EX;
					IF msg IS Disks.LockMsg THEN cmd[4] := 1X; ELSE cmd[4] := 0X; END;
					diskres := usbDriver.InvokeTransport(cmd, 6, NoData, cmd, 0, 0, tlen, 5000);
					
					IF (diskres#Disks.Ok) THEN
						IF diskres=Disks.Unsupported THEN
							AosOut.String("AosUsbStorage: Warning: Device does not support the prevent medium removal command."); AosOut.Ln;	
							diskres := Disks.Ok;
						END;
					END;
				END;
			ELSE
				diskres := Disks.Unsupported;
			END;                                                      *)
		END Handle;
			
	END StorageDevice;

TYPE

	UsbStorageDriver = OBJECT (AosUsb.UsbDriver)
	VAR
		sdev : StorageDevice;
		transportProtocol, transportMethod : LONGINT;
		deviceType : LONGINT;  (* set by Inquiry *)
		bulkIn, bulkOut, interrupt : INTEGER; (* adresses of the used endpoints *)
		interruptInterval : INTEGER;
		
		PROCEDURE Reset(timeout : LONGINT) : SET;
		BEGIN
			HALT(301); (* abstract *)
		END Reset;
		
		PROCEDURE Transport(VAR cmd : ARRAY OF CHAR; cmdlen : INTEGER; dir :  SET;
			VAR buffer : ARRAY OF CHAR; ofs, bufferlen : LONGINT; VAR tlen : LONGINT; timeout : LONGINT):SET;
		BEGIN
			HALT(301); (* abstract *)
		END Transport;
		
		PROCEDURE Handle(VAR msg: Disks.Message) : LONGINT;
		BEGIN
			
		END Handle;
		
		PROCEDURE Inquiry() : BOOLEAN;
		VAR
			cmd : ARRAY 12 OF CHAR;
			data : ARRAY 36 OF CHAR;
			tlen, diskres : LONGINT;
			i : LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("AosUsbStorage: Doing inquiry device"); AosOut.Ln; END;

			sdev.flags := {};
		
			FOR i:= 0 TO 11 DO cmd[i] := CHR(0); END;
			cmd[0] := CHR(12H); 
			cmd[4] := CHR(36);
			diskres := InvokeTransport(cmd, 6, DataIn, data, 0, 36, tlen, 10000);
			IF ((diskres # Disks.Ok) & (diskres # ErrorShortTransfer)) OR (tlen < 5) THEN
				IF Debug THEN AosOut.String("UsbStorage: Fatal, inquiry device error"); AosOut.Ln; END;
				RETURN FALSE;
			END;
		
			IF Debug THEN
				AosOut.String("AosUsbStorage: Inquiry info:"); AosOut.Ln;
				AosOut.String("  Device type: "); AosOut.Int(ORD(data[0]) MOD 16, 0); AosOut.Ln;
				AosOut.String("  Ansi version (00): "); AosOut.Int(ORD(data[2]) MOD 8, 0); AosOut.Ln;
				AosOut.String("  Additional lenght: "); AosOut.Int(ORD(data[4]), 0); AosOut.Ln;
			END;
		
			deviceType := ORD(data[0]) MOD 32;
		
			IF transportProtocol = ProtocolRBC THEN
				IF deviceType # 0EH THEN
					IF Debug THEN AosOut.String("AosUsbStorage: RBC device type is not 0EH"); AosOut.Ln; END;
					RETURN FALSE;
				END;
			ELSIF (deviceType # 0) & (deviceType # 5) THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Device is not a storage device"); AosOut.Ln; END;
				RETURN FALSE;
			END;
		
			IF deviceType = 5 THEN sdev.flags := sdev.flags + {Disks.ReadOnly}; END;
		
			IF 7 IN SYSTEM.VAL(SET, data[1]) THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Removable device found"); AosOut.Ln; END;
				sdev.flags := sdev.flags + {Disks.Removable};
			END;
		
			RETURN TRUE;
		
		END Inquiry;

		(* Generic Transport Handler  *)
		PROCEDURE InvokeTransport ( cmd : ARRAY OF CHAR; cmdlen : INTEGER; dir : SET;
			VAR data : ARRAY OF CHAR; ofs, datalen : LONGINT; VAR tlen : LONGINT; timeout : LONGINT) : LONGINT;
		VAR
			res, senseres : SET; retry, i : INTEGER;
			sensecmd : ARRAY 12 OF CHAR;
			sensedata : ARRAY 36 OF CHAR;
			sensecmdlen : INTEGER;
			sensekey, asc, ascq  : CHAR; 
			sensetlen : LONGINT;
		BEGIN
			(* here one could add additional stuff for the different protocols *)
			IF transportProtocol = ProtocolUFI THEN
				cmdlen := 12; sensecmdlen := 12;
			ELSIF (transportProtocol = ProtocolUTS) OR (transportProtocol = ProtocolRBC) THEN
				(* all ok *) sensecmdlen := 6;
			ELSIF (transportProtocol = Protocol8020) OR (transportProtocol = Protocol8070) THEN
				cmdlen := 12; sensecmdlen := 12;
			ELSIF transportProtocol = ProtocolQIC157 THEN
				cmdlen := 12; sensecmdlen := 12;
			END;
		
			retry := 0; (* retries for "power up/reset" and "lun becoming ready" *)
		
			LOOP	
				res := Transport(cmd, cmdlen, dir, data, ofs, datalen, tlen, timeout);
			
				IF (res = TransportFatal) OR (res = TransportTimeout) THEN
					res := Reset(5000);
					RETURN ErrorDiskFail;
				END;
		
				(* shorttransfer: the linux guys do sometimes an auto sense here, but we don't *)
				IF (res = TransportShort) & (transportMethod # MethodCB) THEN
					IF Debug THEN AosOut.String("AosUsbStorage: Had a short read"); AosOut.Ln; END;
					RETURN ErrorShortTransfer;
				END;
		
				(* Do an auto-sense if something was not ok or if we are using the CB (not CBI) transport method *)
				IF (res = TransportDone) & (transportMethod # MethodCB) THEN
					RETURN Disks.Ok;
				END;
		
				(* It makes no sense to auto-sense on Inquiry/Sense on UFI/CB (not CBI)*)
				IF ((res = TransportDone) OR (res = TransportShort)) & (transportMethod = MethodCB)
					& (transportProtocol = ProtocolUFI) & ((cmd[0] = 12X) OR (cmd[0] = 03X)) THEN
					IF res = TransportDone THEN RETURN Disks.Ok; ELSIF res = TransportShort THEN RETURN ErrorShortTransfer;
					ELSE HALT(303); END;
				END;
				
				(* res = TransportError *)
				IF Trace THEN AosOut.String("AosUsbStorage: Doing auto sense"); AosOut.Ln; END;
		
				FOR i:= 0 TO 11 DO sensecmd[i] := CHR(0); END;
				sensecmd[0] := CHR (3); (* operation code: Request Sense Command (03H) *)
				sensecmd[1] := CHR (0); (* lun * 32 *)
				sensecmd[4] := CHR(18); (* allocation length (max. 18 Bytes) *)
		
				senseres := Transport(sensecmd, sensecmdlen, DataIn, sensedata, 0, 18, sensetlen, 2000);
		
				IF senseres = TransportShort THEN
					IF sensetlen < 14 THEN
						IF Debug THEN AosOut.String("AosUsbStorage: Crappy device gives not enough sense data"); AosOut.Ln; END;
						RETURN ErrorDiskFail;
					END;
					(* sense >= 14 is ok *)
				ELSIF (transportProtocol = ProtocolUFI) & (senseres = TransportSenseError) THEN
					IF Debug THEN AosOut.String("AosUsbStorage: UFI autosense TransportSenseError"); AosOut.Ln; END;
					(* thats ok *)
				ELSIF senseres # TransportDone THEN
					IF Debug THEN AosOut.String("AosUsbStorage: Sense error on protocol sense"); AosOut.Ln; END;
					senseres := Reset(5000);
					RETURN ErrorDiskFail;
				END;

				sensekey := CHR(ORD(sensedata[2]) MOD 16); asc := sensedata[12]; ascq := sensedata[13];
		
				IF Debug THEN
					AosOut.String("AosUsbStorage: Sense Key: "); AosOut.Int(ORD(sensekey), 0);
					AosOut.String(" asc: "); AosOut.Hex(ORD(asc), 0);
					AosOut.String(" ascq: "); AosOut.Hex(ORD(ascq), 0);
					AosOut.Ln;
				END;
		
				IF sensekey = 0X THEN (* no sense -> okay *)
				
					IF (res = TransportDone) OR (res = TransportShort) THEN RETURN Disks.Ok; END;
					IF SenseDebug THEN AosOut.String("AosUsbStorage: Device reports error, but auto-sense gives 0X"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 1X) & (asc = 17X) & (ascq = 01X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: Recovered data with retries"); AosOut.Ln; END;
					RETURN Disks.Ok;
					
				ELSIF (sensekey = 1X) & (asc = 18X) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: Recovered data with ECC"); AosOut.Ln; END;
					RETURN Disks.Ok;
		
				ELSIF (sensekey = 2X) & (asc = 4X) & (ascq = 01X) THEN
					IF SenseDebug THEN AosOut.String("AosUsbStorage: Logical drive not ready, becoming ready"); AosOut.Ln; END;
					(* retry *)
					
				ELSIF (sensekey = 2X) & (asc = 4X) & (ascq = 02X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: logical drive not ready - initialization required"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 2X) & (asc = 4X) & (ascq = 04X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: logical unit not ready - format in progress"); AosOut.Ln; END;
					RETURN Disks.DeviceInUse;
					
				ELSIF (sensekey = 2X) & (asc = 4X) & (ascq = 0FFX) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: logical drive not ready - device is busy"); AosOut.Ln; END;
					RETURN Disks.DeviceInUse;
				
				ELSIF (sensekey = 2X) & (asc = 6X) & (ascq = 0X) THEN
					IF SenseDebug THEN AosOut.String("AosUsbStorage: No reference position found"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 2X) & (asc = 8X) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: logical unit communication failure"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 2X) & (asc = 8X) & (ascq = 1X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: logical unit communication timeout"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 2X) & (asc = 8X) & (ascq = 80X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: logical unit communication overrun"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
		
				ELSIF (sensekey = 2X) & (asc = 3AX) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: medium not present"); AosOut.Ln; END;
					RETURN Disks.MediaMissing;
				
				ELSIF (sensekey = 2X) & (asc = 54X) & (ascq = 0X) THEN
					IF SenseDebug THEN AosOut.String("AosUsbStorage: USB to host system interface failure"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 2X) & (asc = 80X) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: insufficient resources"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 2X) & (asc = 0FFX) & (ascq = 0FFX) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: unknown error"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
				ELSIF (sensekey = 3X) & (asc = 2X) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: no seek complete"); AosOut.Ln; END;
					(* retry *)
			
				ELSIF (sensekey = 3X) & (asc = 3X) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: write fault"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
		
				ELSIF (sensekey = 3X) & (asc = 30X) & (ascq = 1X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: cannot read medium - unknown format"); AosOut.Ln; END;
					RETURN Disks.MediaMissing;
				
				ELSIF (sensekey = 3X) & (asc = 31X) & (ascq = 1X) THEN
					IF SenseDebug THEN AosOut.String("AosUsbStorage: format command failed"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 4X) & (asc = 40X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: Diagnostic failure on component"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 5X) & (asc = 20X) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: invalid command operation code"); AosOut.Ln; END;
					RETURN Disks.Unsupported;
					
				ELSIF (sensekey = 5X) & (asc = 21X) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: logical block address out of range"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
					
				ELSIF (sensekey = 5X) & (asc = 24X) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("AosUsbStorage: invalid field in command packet"); AosOut.Ln; END;
					RETURN ErrorDiskFail;
		
				ELSIF (sensekey = 6X) & (asc = 28X) & (ascq = 0X) THEN 
					IF SenseDebug THEN AosOut.String("not ready to ready transition - media changed"); AosOut.Ln; END;
					(* RETURN Disks.MediaChanged; *) (* retry *)
		
				ELSIF (sensekey = 6X) & (asc = 29X) & (ascq = 0X) THEN		
					IF Debug THEN IF retry = 0 THEN AosOut.String("AosUsbStorage: PowerOnReset, retrying"); AosOut.Ln; END; END;
					(* retry *)
					
				ELSIF (sensekey = 7X) & (asc = 27X) & (ascq = 0X) THEN		
					IF Debug THEN AosOut.String("AosUsbStorage: write protected media"); AosOut.Ln; END;
					RETURN Disks.WriteProtected;
					
				ELSE
					RETURN ErrorDiskFail;
				END;
		
				INC(retry);
		
				IF retry = 30 THEN
					IF Debug THEN AosOut.String("AosUsbStorage: Too many protocol retries, giving up"); AosOut.Ln; END;
					EXIT;
				END; 
		
				MilliWait(10); (* try again *)
			END;
		
			RETURN ErrorDiskFail;

		END InvokeTransport;
		
		PROCEDURE Connect;
		BEGIN 
			AosOut.String("USB storage device connected."); AosOut.Ln; 
			diskManager.Add(sdev); 
		END Connect;
		
		PROCEDURE Disconnect;
		BEGIN
			AosOut.String("USB storage device disconnecting."); AosOut.Ln;
			diskManager.Remove(sdev);
		END Disconnect;

	END UsbStorageDriver;

TYPE
	(* USB mass storage class bulk only transport layer *)
	BulkOnlyTransport = OBJECT(UsbStorageDriver)
	VAR
		(* Perform reset recovery, i.e. send Bulk-Only Mass Storage Reset command via default control pipe and
			then clear the EndpointHalt feature if the bulk in and bulk out endpoints of the USB device *)
		PROCEDURE Reset(timeout : LONGINT) : SET;
		VAR
			message : ARRAY 8 OF CHAR;
			transfer : AosUsb.UsbTransfer;
			status : SET;
		BEGIN
			IF Trace THEN AosOut.String("AosUsbStorage: Sending BulkOnlyReset via default control pipe"); AosOut.Ln; END;	
			message[0] := CHR(33);   (* Class specific request (32), Type Interface (1) *)
			message[1] := CHR(255); (* Bulk Only Mass Storage Reset *)
			message[2] := CHR(0);
			message[3] := CHR(0);
			message[4] := CHR(device.actConfiguration.interfaces[interface].bInterfaceNumber);
			message[5] := CHR(0);
			message[6] := CHR(0);
			message[7] := CHR(0);
			
			transfer := device.SendControl(0, message, message, 0, 0, timeout);
			status := transfer.GetStatus();
			
			IF (status * AosUsb.ResStalled) # {} THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Stall on BulkOnlyReset Control"); AosOut.Ln; END;
				IF transfer.ClearHalt() THEN
					RETURN TransportError
				ELSE
					IF Debug THEN AosOut.String("AosUsbStorage: Failure on BulkOnlyReset clear halt on default control pipe"); AosOut.Ln; END;
					RETURN TransportFatal 
				END;
			END;
				
			IF (status * AosUsb.ResInProgress) # {} THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Timeout on BulkOnlyReset Control"); AosOut.Ln; END;
				RETURN TransportTimeout;
				
			ELSIF status # AosUsb.ResOK THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Failure on BulkOnlyReset Control"); AosOut.Ln; END;
				RETURN TransportFatal;
			END;
		
			IF (~device.ClearHalt(bulkIn)) OR (~device.ClearHalt(bulkOut)) THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Failure on BulkOnly reset ClearHalt"); AosOut.Ln; END;
				RETURN TransportFatal;
			END;
			IF Trace THEN AosOut.String("AosUsbStorage: BulkOnlyReset OK"); AosOut.Ln; END;	
			RETURN TransportDone;
		END Reset;
		
		PROCEDURE Transport(VAR cmd : ARRAY OF CHAR; cmdlen : INTEGER; dir :  SET;
			VAR buffer : ARRAY OF CHAR; ofs, bufferlen : LONGINT; VAR tlen : LONGINT; timeout : LONGINT):SET;
		VAR
			CBWbuffer : ARRAY 31 OF CHAR;
			CSWbuffer : ARRAY 13 OF CHAR;
			cswValid : BOOLEAN;
			bulkendpoint : INTEGER;
			transfer : AosUsb.UsbTransfer;
			status : SET; 
			i : LONGINT;
		BEGIN
			(* Three phase protocol: First, the CBW is sent to the device. Then, the data is sent/received (if any). Then the CSW is received. *)
		
			(* set up dCBWSignature *)
			CBWbuffer[0] := 55X; CBWbuffer[1] := 53X; CBWbuffer[2] := 42X; CBWbuffer[3] := 43X;
			(*set up dCBWTag "ETHO"*)
			CBWbuffer[4] := "E"; CBWbuffer[5] := "T"; CBWbuffer[6] := "H"; CBWbuffer[7] := "O";
			(* set up dCBWDataTransferLength *)
			CBWbuffer[8] := CHR(bufferlen);
			CBWbuffer[9] := CHR(SYSTEM.LSH(bufferlen, -8));
			CBWbuffer[10] := CHR(SYSTEM.LSH(bufferlen, -16));
			CBWbuffer[11] := CHR(SYSTEM.LSH(bufferlen, -24));
			(* set up dCBWDataTransferLength *)
			CBWbuffer[8] := CHR(bufferlen);
			CBWbuffer[9] := CHR(SYSTEM.LSH(bufferlen, -8));
			CBWbuffer[10] := CHR(SYSTEM.LSH(bufferlen, -16));
			CBWbuffer[11] := CHR(SYSTEM.LSH(bufferlen, -24));
			(* set up bmCBWFlags *)
			IF dir = DataIn THEN CBWbuffer[12] := 80X; ELSE CBWbuffer[12] := 0X; END;
					(* set bCBWLUN - currently always zero *)
			CBWbuffer[13] := 0X;
			(*set bCBWCBLength *)
			IF (cmdlen > 16) OR (cmdlen = 0) THEN HALT(303) END;
			CBWbuffer[14] := CHR(cmdlen);
	
			(* copy CBWCB *)
			FOR i:=0 TO cmdlen-1 DO CBWbuffer[15+i] := cmd[i]; END;
		
			IF Trace THEN 
				AosOut.String("AosUsbStorage: Sending BulkOnly CBW "); 
				AosOut.String("[cmd: "); ShowUFICmd(cmd[0]); AosOut.String(" ");
				FOR i := 0 TO 11 DO AosOut.Int(ORD(cmd[i]),0); AosOut.String(" "); END; 
				AosOut.String("BufferLen: "); AosOut.Int(bufferlen,0); AosOut.String(" Bytes]");
				AosOut.Ln; 
			END;	
			
			(* send the CBW *)
			transfer := device.SendBulk(bulkOut, CBWbuffer, 0, 31, timeout);
			status:=transfer.GetStatus();
			
			(* exaclty 31 Bytes should have been transmitted *)
			IF transfer.TransferedBytes() # 31 THEN AosOut.String("AosUsbStorage: Transfer of CBW failed"); AosOut.Ln; END;
			
			IF (status * AosUsb.ResStalled) # {} THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Stall on BulkOnly CBW"); AosOut.Ln; END;
				IF transfer.ClearHalt() THEN
					RETURN TransportError
				ELSE
					IF Debug THEN AosOut.String("AosUsbStorage: Failure on BulkOnly clear halt CBW"); AosOut.Ln; END;
					RETURN TransportFatal 
				END;
			END;
			
			IF (status * AosUsb.ResInProgress) # {} THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Timeout on BulkOnly CBW"); AosOut.Ln; END;
				RETURN TransportTimeout;
				
			ELSIF status # AosUsb.ResOK THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Failure on BulkOnly CBW"); AosOut.Ln; END;
				RETURN TransportFatal;
			END;
		
			(* If there is data to send, enter the data stage *)
			IF bufferlen # 0 THEN	
				
				IF dir = DataIn THEN
					IF Trace THEN AosOut.String("AosUsbStorage: Transfering BulkOnly DataIn "); END;
					bulkendpoint := bulkIn;
				ELSIF dir = DataOut THEN
					IF Trace THEN AosOut.String("AosUsbStorage: Transfering BulkOnly DataOut"); END;
					bulkendpoint := bulkOut;
				ELSE HALT(303);
				END;
				IF Trace THEN AosOut.Int(bufferlen,0); AosOut.String(" Bytes Endpoint: "); AosOut.Hex(bulkendpoint,0); AosOut.Ln; END;
		
				transfer := device.SendBulk(bulkendpoint, buffer, ofs, bufferlen, timeout); 
				tlen := transfer.TransferedBytes();
				status:=transfer.GetStatus();

				(* clear halt if STALL occured, but do not abort!!! *)
				IF (status * AosUsb.ResStalled) # {} THEN
					IF Debug THEN AosOut.String("AosUsbStorage: Stall on BulkOnly data phase"); AosOut.Ln; END;
					(* only abort if clear halt fails *)
					IF ~transfer.ClearHalt() THEN
						IF Debug THEN AosOut.String("AosUsbStorage: Failure on BulkOnly clear halt"); AosOut.Ln; END;
						RETURN TransportFatal;
					END;
				END;
		
				IF (status * AosUsb.ResInProgress) # {} THEN
					IF Debug THEN AosOut.String("AosUsbStorage: Timeout on BulkOnly data phase"); AosOut.Ln; END;
					RETURN TransportTimeout;
					
				(* allow short packets and stalls !!! *)
				ELSIF (status - (AosUsb.ResOK + AosUsb.ResStalled + AosUsb.ResShortPacket)) # {} THEN
					IF Debug THEN AosOut.String("AosUsbStorage: Failure on BulkOnly data phase"); AosOut.Ln; END;
					RETURN TransportFatal;
				END;
				
			ELSE
				tlen := 0;
			END;
			
			(* enter the status phase - Get the CSW *)
			IF Trace THEN AosOut.String("AosUsbStorage: Getting BulkOnly CSW"); AosOut.Ln; END;
			transfer := device.SendBulk(bulkIn, CSWbuffer, 0, 13, timeout); 
			status := transfer.GetStatus();
		
			(* clear halt if STALL occured, and try again*)
			IF (status * AosUsb.ResStalled) # {} THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Stall, must retry CSW phase"); AosOut.Ln; END;
				(* only abort if clear halt fails *)
				IF ~transfer.ClearHalt() THEN
					IF Debug THEN AosOut.String("AosUsbStorage: Failure on BulkOnly clear halt"); AosOut.Ln; END;
					RETURN TransportFatal;
				END;
				IF Debug THEN AosOut.String("AosUsbStorage: Retrying BulkOnly CSW"); AosOut.Ln; END;
				transfer := device.SendBulk(bulkIn, CSWbuffer, 0, 13, timeout);
				status:=transfer.GetStatus();
			END;

			(* clear halt if STALL occured, and this time abort *)
			IF (status * AosUsb.ResStalled) # {} THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Stall on BulkOnly CSW phase"); AosOut.Ln; END;
				IF ~transfer.ClearHalt() THEN
					IF Debug THEN AosOut.String("AosUsbStorage: Failure on BulkOnly clear halt"); AosOut.Ln; END;
					RETURN TransportFatal;
				END; 
			ELSIF (status * AosUsb.ResInProgress) # {} THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Timeout on CSW phase"); AosOut.Ln; END;
				RETURN TransportTimeout;
			(* allow not short packet on csw phase, be strict! *)
			ELSIF status # AosUsb.ResOK THEN
				IF Debug THEN AosOut.String("UsbStorage: Failure on CSW phase"); AosOut.Ln; END;
				RETURN TransportFatal;
			END;
			
			cswValid := TRUE;
			
			(* now we have a CSW block, check CSW signature *)
			IF (CSWbuffer[0] # 55X)OR(CSWbuffer[1] # 53X)OR(CSWbuffer[2] # 42X)OR(CSWbuffer[3] # 53X) THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Device did not send a valid CSW! (wrong signature)"); AosOut.Ln; END;
				cswValid := FALSE;
			END;
		
			(* chech dCSWTag *)
			IF (CSWbuffer[4] # "E")OR(CSWbuffer[5] # "T")OR(CSWbuffer[6] # "H")OR(CSWbuffer[7] # "O") THEN
				IF Debug THEN AosOut.String("AosUsbStorage: Device did send wrong tag in CSW!"); AosOut.Ln; END;
				cswValid := FALSE;
			END;
			
			IF ~cswValid OR (cswValid & (CSWbuffer[12] = 02X)) THEN (* perform reset recovery *) 
				IF Debug THEN AosOut.String("AosUsbStorage: Performing reset recovery"); AosOut.Ln; END;
				RETURN Reset(timeout); 
			
			ELSE (* CSW is valid *)
				(* parse status *)
				IF CSWbuffer[12] = 01X THEN (* Command failed *)
					IF Debug THEN AosOut.String("AosUsbStorage: BulkOnly CSW reports error"); AosOut.Ln; END;
					RETURN TransportError;
				ELSIF CSWbuffer[12] # 0X THEN
					IF Debug THEN AosOut.String("AosUsbStorage: BulkOnly CSW reports fatal"); AosOut.Ln; END;
					RETURN TransportFatal;
				END;
			
				(* look at transfered data difference *)
				IF (CSWbuffer[8] # 0X) OR (CSWbuffer[9] # 0X) OR (CSWbuffer[10] # 0X) OR (CSWbuffer[11] # 0X) THEN
					IF Debug THEN AosOut.String("AosUsbStorage: BulkOnly short  transfer"); AosOut.Ln; END;
					IF tlen = bufferlen THEN
						IF Debug THEN AosOut.String("AosUsbStorage: BulkOnly confusion: tlen=bufferlen, but device reports short transfer"); AosOut.Ln; END;
					END;
					RETURN TransportShort;
				END;
				
				RETURN TransportDone;
			END;
		END Transport;

	END BulkOnlyTransport;
	
TYPE
	(* USB Mass Storage Class Control/Bulk/Interrupt (CBI) abd Control/Bulk (CB) transport layer *)
	CBITransport = OBJECT(UsbStorageDriver)
	
		PROCEDURE Reset(timeout : LONGINT) : SET;
			VAR
			message : ARRAY 8 OF CHAR;
			buffer : ARRAY 12 OF CHAR;
			interruptData : ARRAY 8 OF CHAR;
			transfer : AosUsb.UsbTransfer;
			status : SET;
			i : LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("UsbStorage: Sending CB/I reset ControlTransfer"); AosOut.Ln; END;
			message[0] := CHR(33); (* Class specific request (32), Type Interface (1) *)
			message[1] := CHR(0);
			message[2] := CHR(0);
			message[3] := CHR(0);
			message[4] := CHR(device.actConfiguration.interfaces[interface].bInterfaceNumber);
			message[5] := CHR(0);
			message[6] := CHR(12);
			message[7] := CHR(0);
			
			FOR i := 0 TO 11 DO buffer[i] := CHR(255) END;
			buffer[0] := CHR(1DH); 
			buffer[1] := CHR(4);
		
			transfer := device.SendControl( 0, message, buffer, 0, 12, timeout);
			status := transfer.GetStatus();
			
			IF (status * AosUsb.ResStalled) # {} THEN
				IF Debug THEN AosOut.String("UsbStorage: Stall on TransportCB/I-Reset Control"); AosOut.Ln; END;
				IF device.ClearHalt(0) THEN
					RETURN TransportError
				ELSE
					IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I-Reset clear halt on Controlpipe"); AosOut.Ln; END;
					RETURN TransportFatal
				END;
			END;
			
			IF (status * AosUsb.ResInProgress) # {} THEN
				IF Debug THEN AosOut.String("UsbStorage: Timeout on TransportCB/I-Reset Control"); AosOut.Ln; END;
				RETURN TransportTimeout;
			END;
			IF status # AosUsb.ResOK THEN
				IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I-Reset Control"); AosOut.Ln; END;
				RETURN TransportFatal;
			END;
			
			IF transportMethod = MethodCBI THEN (* because this procedure is also used for CB transports *)
		
				IF Trace THEN AosOut.String("UsbStorage: Sending CB/I reset InterruptTransfer"); AosOut.Ln; END;
				transfer := device.SendInterrupt(interrupt, interruptData, 0, 2, timeout, interruptInterval);
				status := transfer.GetStatus();
				
				IF (status * AosUsb.ResStalled) # {} THEN
					IF Debug THEN AosOut.String("UsbStorage: Stall on TransportCB/I-Reset Interrupt"); AosOut.Ln; END;
					IF device.ClearHalt(0) THEN RETURN TransportError END;
					IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I-Reset clear halt on Interruptpipe"); AosOut.Ln; END;
					RETURN TransportFatal;
				END;
				IF (status * AosUsb.ResInProgress) # {} THEN
					IF Debug THEN AosOut.String("UsbStorage: Timeout on TransportCB/I-Reset Interrupt"); AosOut.Ln; END;
					RETURN TransportTimeout;
				END;
				IF status # AosUsb.ResOK THEN
					IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I-Reset Interrupt"); AosOut.Ln; END;
					RETURN TransportFatal;
				END;
				
			END;
			
			IF (~device.ClearHalt(bulkIn)) OR (~device.ClearHalt(bulkOut)) THEN
				IF Debug THEN AosOut.String("UsbStorage: Failure on CB/I reset ClearHalt"); AosOut.Ln; END;
				RETURN TransportFatal;
			END;
			IF Trace THEN AosOut.String("UsbStorage: CB/I reset OK"); AosOut.Ln; END;
			
			RETURN TransportDone;
			
		END Reset;
		
		PROCEDURE Transport(VAR cmd : ARRAY OF CHAR; cmdlen : INTEGER; dir : SET;
			VAR buffer : ARRAY OF CHAR; ofs, bufferlen : LONGINT; VAR tlen : LONGINT; timeout : LONGINT):SET;
		VAR
			message :  ARRAY 8 OF CHAR;
			interruptData : ARRAY 2 OF CHAR;
			transfer : AosUsb.UsbTransfer;
			status : SET;
			bulkendpoint : INTEGER;
		BEGIN
			IF Trace THEN AosOut.String("UsbStorage: Sending TransportCB/I Control"); AosOut.Ln; END;	
			message[0] := CHR(33); (* Class specific request (32), Type Interface (1) *)
			message[1] := CHR(0);
			message[2] := CHR(0);
			message[3] := CHR(0);
			message[4] := CHR(device.actConfiguration.interfaces[interface].bInterfaceNumber);
			message[5] := CHR(0);
			message[6] := CHR(cmdlen);
			message[7] := CHR(SYSTEM.LSH(cmdlen, -8));
		
			transfer := device.SendControl( 0, message, cmd, 0, cmdlen, timeout);
			status := transfer.GetStatus();
			
			IF (status * AosUsb.ResStalled) # {} THEN
				IF Debug THEN AosOut.String("UsbStorage: Stall on TransportCB/I Control"); AosOut.Ln; END;
				IF device.ClearHalt(0) THEN
					RETURN TransportError
				ELSE
					IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I clear halt on Controlpipe"); AosOut.Ln; END;
					RETURN TransportFatal 
				END;
			END;
			IF (status * AosUsb.ResInProgress) # {} THEN
				IF Debug THEN AosOut.String("UsbStorage: Timeout on TransportCB/I Control"); AosOut.Ln; END;
				RETURN TransportTimeout;
			END;
			IF status # AosUsb.ResOK THEN
				IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I Control"); AosOut.Ln; END;
				RETURN TransportFatal;
			END;
		
			IF (bufferlen # 0) THEN
			
				IF dir = DataIn THEN
					IF Trace THEN AosOut.String("UsbStorage: Sending TransportCB/I BulkIn"); AosOut.Ln; END;
					bulkendpoint := bulkIn;
				ELSIF dir = DataOut THEN
					IF Trace THEN AosOut.String("UsbStorage: Sending TransportCB/I BulkOut"); AosOut.Ln; END;
					bulkendpoint := bulkOut;
				ELSE HALT(303);
				END;
				
				transfer := device.SendBulk(bulkendpoint, buffer, ofs, bufferlen, timeout);
				status := transfer.GetStatus();
				tlen := transfer.TransferedBytes();
				
				IF (status * AosUsb.ResStalled) # {} THEN
					IF Debug THEN AosOut.String("UsbStorage: Stall on TransportCB/I Bulk"); AosOut.Ln; END;
					IF device.ClearHalt(bulkendpoint) THEN RETURN TransportError END;
					IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I clear halt on Bulkpipe"); AosOut.Ln; END;
					RETURN TransportFatal
				ELSIF (status * AosUsb.ResInProgress) # {} THEN
					IF Debug THEN AosOut.String("UsbStorage: Timeout on TransportCB/I Bulk"); AosOut.Ln; END;
					RETURN TransportTimeout;
				ELSIF status # AosUsb.ResOK THEN
					IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I Bulk"); AosOut.Ln; END;
					RETURN TransportFatal;
				END;
			ELSE
				tlen := 0;
			END;

			IF transportMethod = MethodCBI THEN
				IF Debug THEN AosOut.String("UsbStorage: Sending TransportCB/I Interrupt"); AosOut.Ln; END;
				
				transfer := device.SendInterrupt(interrupt, interruptData, 0, 2, timeout, interruptInterval);
				status := transfer.GetStatus();
				
				IF (status * AosUsb.ResStalled)  # {} THEN
					IF Debug THEN AosOut.String("UsbStorage: Stall on TransportCB/I Interrupt"); AosOut.Ln; END;
					IF device.ClearHalt(0) THEN RETURN TransportError END;
					IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I clear halt on Interruptpipe"); AosOut.Ln; END;
					RETURN TransportFatal 
				END;
				IF (status * AosUsb.ResInProgress) # {} THEN
					IF Debug THEN AosOut.String("UsbStorage: Timeout on TransportCB/I Interrupt"); AosOut.Ln; END;
					RETURN TransportTimeout;
				END;
				IF status#AosUsb.ResOK THEN
					IF Debug THEN AosOut.String("UsbStorage: Failure on TransportCB/I Interrupt"); AosOut.Ln; END;
					RETURN TransportFatal;
				END;
		
				IF (transportProtocol = ProtocolUFI) THEN
					IF (cmd[0] = 12X) OR (cmd[0] = 03X) THEN
						(* UFI Inquiry + Sense do not change the sense data, so we cannot be sure that those commands succeded!!! *)
						(* just go on and hope the best! *)
					ELSIF (interruptData[0] # 0X) THEN
						IF Debug THEN
							AosOut.String("UsbStorage: asc = "); AosOut.Hex(ORD(interruptData[0]), 0);
							AosOut.String(" ascq = "); AosOut.Hex(ORD(interruptData[1]), 0);
							AosOut.String(" Error on CBI/UFI"); AosOut.Ln;
						END;
						RETURN TransportSenseError;
					END;
					(* go on *)
				ELSIF interruptData[0] # 0X THEN
					IF Debug THEN AosOut.String("UsbStorage: CBI returned invalid interupt data block"); AosOut.Ln; END;
					RETURN TransportSenseError; (* try to recover by manual sensing *)
				ELSE
					status := SYSTEM.VAL(SET, interruptData[1]) * {0,1};
					IF (status = {0,1}) OR (status= {0}) THEN
						IF Debug THEN AosOut.String("UsbStorage: Sense # 0 Error on TransportCB/I"); AosOut.Ln; END;
						RETURN TransportSenseError;
					ELSIF status= {1} THEN
						IF Debug THEN AosOut.String("UsbStorage: Fatal sense on Transport CB/I"); AosOut.Ln; END;
						RETURN TransportFatal;
					END;
				END;
			END;
				
			IF tlen # bufferlen THEN RETURN TransportShort; END;
		
			RETURN TransportDone;
		
		END Transport;
	
	END CBITransport;
	
TYPE
	(* SCM Shuttle Transport Layer  *)
	SCMTransport = OBJECT(CBITransport) (* same Reset procedure as CBITransport -> inherit it *)
	VAR
		i : LONGINT;
		
		PROCEDURE ScmShortPack(p1, p2 : CHAR) : INTEGER;
		BEGIN
			RETURN SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, ORD(p2)*256) + SYSTEM.VAL(SET, ORD(p1)));
		END ScmShortPack;
		
		PROCEDURE ScmSendControl(endpoint : INTEGER; req, reqtyp, value, index : INTEGER;
			VAR buffer : ARRAY OF CHAR; ofs, bufflen, timeout : LONGINT) : SET;
		VAR
			message : ARRAY 8 OF CHAR;
			transfer : AosUsb.UsbTransfer;
			status : SET;
		BEGIN
			IF Trace THEN AosOut.String("AosUsbStorage: Sending SCM Control"); AosOut.Ln; END;
			message[0] := CHR(reqtyp); 
			message[1] := CHR(req);
			message[2] := CHR(value); 
			message[3] := CHR(SYSTEM.LSH(value, -8));
			message[4] := CHR(index); 
			message[5] := CHR(SYSTEM.LSH(index, -8));
			message[6] := CHR(bufflen); 
			message[7] := CHR(SYSTEM.LSH(bufflen, -8));
		
			transfer := device.SendControl(endpoint, message, buffer, ofs, bufflen, timeout);
			status := transfer.GetStatus();
		
			IF (status * AosUsb.ResStalled) # {} THEN
				IF Debug THEN AosOut.String("UsbStorage: Stall on Transport SCM Control"); AosOut.Ln; END;
				IF device.ClearHalt(endpoint) THEN
					RETURN TransportError
				ELSE
					IF Debug THEN AosOut.String("UsbStorage: Failure on Transport SCM clear halt on Controlpipe"); AosOut.Ln; END;
					RETURN TransportFatal 
				END;
			END;
			
			IF (status * AosUsb.ResInProgress) # {} THEN
				IF Debug THEN AosOut.String("UsbStorage: Timeout on Transport SCM Control"); AosOut.Ln; END;
				RETURN TransportTimeout;
			END;
			IF status # AosUsb.ResOK THEN
				IF Debug THEN AosOut.String("UsbStorage: Failure on Transport SCM Control"); AosOut.Ln; END;
				RETURN TransportFatal;
			END;
			RETURN TransportDone;
		END ScmSendControl;
		
		PROCEDURE ScmBulkTransport(dir : SET; VAR buffer : ARRAY OF CHAR; ofs, bufferlen : LONGINT;
			VAR tlen : LONGINT; timeout : LONGINT):SET;
		VAR
			bulkendpoint : INTEGER;
			transfer : AosUsb.UsbTransfer;
			status : SET;
		BEGIN
			tlen := 0;
			IF bufferlen = 0 THEN RETURN TransportDone END;
			
			IF dir = DataIn THEN
				IF Trace THEN AosOut.String("UsbStorage: Transfering SCM DataIn"); AosOut.Ln; END;
				bulkendpoint := bulkIn;
			ELSIF dir = DataOut THEN
				IF Trace THEN AosOut.String("UsbStorage: Transfering SCM DataOut"); AosOut.Ln; END;
				bulkendpoint := bulkOut;
			ELSE HALT(303);
			END;
			
			transfer := device.SendBulk(bulkendpoint, buffer, ofs, bufferlen, timeout);
			status := transfer.GetStatus();
			tlen := transfer.TransferedBytes();
			
			(* clear halt if STALL occured, but do not abort!!! *)
			IF (status * AosUsb.ResStalled) # {} THEN
				IF Debug THEN AosOut.String("UsbStorage: Stall on SCM data phase"); AosOut.Ln; END;
				(* only abort if clear halt fails *)
				IF ~transfer.ClearHalt() THEN
					IF Debug THEN AosOut.String("UsbStorage: Failure on SCM bulk clear halt"); AosOut.Ln; END;
					RETURN TransportFatal;
				END;
			END;
			
			IF (status * AosUsb.ResInProgress) # {} THEN
				IF Debug THEN AosOut.String("UsbStorage: Timeout on SCM data phase"); AosOut.Ln; END;
				RETURN TransportTimeout;
			ELSIF (status - (AosUsb.ResOK  + AosUsb.ResStalled + AosUsb.ResShortPacket)) # {} THEN
				IF Debug THEN AosOut.String("UsbStorage: Failure on SCM bulk"); AosOut.Ln; END;
				RETURN TransportFatal;
			END;
			IF tlen # bufferlen THEN
				IF Debug THEN
					AosOut.String("UsbStorage: ScmBulkTransport short read: ");
					AosOut.Int(bufferlen, 0); AosOut.Char("/"); AosOut.Int(tlen, 0); AosOut.Ln;
				END;
				RETURN TransportShort;
			END;
			RETURN TransportDone;
			END ScmBulkTransport;
		
		PROCEDURE ScmWaitNotBusy(timeout : LONGINT):SET;
		VAR
			res : SET; 
			status : CHAR;
		BEGIN
			LOOP
				res := ScmRead(ScmATA, 17X, status, 1000);
				
				IF res # TransportDone THEN 
					IF res = TransportFatal THEN RETURN res ELSE RETURN TransportError END;
					ELSIF (SYSTEM.VAL(SET, status) * {0}) # {} THEN
						IF Debug THEN AosOut.String("UsbStorage: ScmWaitNotBusy: check condition"); AosOut.Ln; END;
						RETURN TransportError;
					ELSIF (SYSTEM.VAL(SET, status) * {5}) # {} THEN
						IF Debug THEN AosOut.String("UsbStorage: ScmWaitNotBusy: device fault"); AosOut.Ln; END;
						RETURN TransportFatal;
					ELSIF (SYSTEM.VAL(SET, status) * {7}) = {} THEN
						IF Debug THEN AosOut.String("UsbStorage: ScmWaitNotBusy: good"); AosOut.Ln; END;
						RETURN TransportDone;
				END;
				
				IF timeout # -1 THEN
					timeout  := timeout - 10; IF timeout < 0 THEN EXIT END;
				END;
				MilliWait(10);
			END;
			IF Debug THEN AosOut.String("UsbStorage: ScmWaitNotBusy: Timeout"); AosOut.Ln; END;
			RETURN TransportTimeout;
		END ScmWaitNotBusy;
		
		PROCEDURE ScmReadUserIO(VAR dataflags: CHAR; timeout : LONGINT) : SET;
		VAR
			readbuffer : ARRAY 1 OF CHAR; res : SET;
		BEGIN
			res := ScmSendControl(128, 82H, 0C0H, 0, 0, readbuffer, 0, 1, timeout);
			dataflags := readbuffer[0];
			RETURN res;
		END ScmReadUserIO;
		
		PROCEDURE ScmWriteUserIO(enableflags, dataflags: CHAR; timeout : LONGINT) : SET;
		VAR
			dummybuffer : ARRAY 1 OF CHAR;
		BEGIN
			RETURN ScmSendControl(0, 82H, 40H, ScmShortPack(enableflags, dataflags), 0, dummybuffer, 0, 0, timeout);
		END ScmWriteUserIO;
		
		PROCEDURE ScmRead(access, reg : CHAR; VAR content: CHAR; timeout : LONGINT) : SET;
		VAR
			readbuffer : ARRAY 1 OF CHAR; res : SET;
		BEGIN
			res := ScmSendControl(128, ORD(access), 0C0H, ORD(reg), 0, readbuffer, 0, 1, timeout);
			content := readbuffer[0];
			RETURN res;
		END ScmRead;
		
		PROCEDURE ScmWrite(access, reg, content : CHAR; timeout : LONGINT):SET;
		VAR
			dummybuffer : ARRAY 1 OF CHAR;
		BEGIN
			access := SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, access) + {0});
			RETURN ScmSendControl(0, ORD(access), 040H, ScmShortPack(reg, content), 0, dummybuffer, 0, 0, timeout);
		END ScmWrite;
		
		PROCEDURE ScmMultipleWrite(access : CHAR; VAR registers, dataout: ARRAY OF CHAR;
		 	numregs : INTEGER; timeout : LONGINT):SET;
		VAR
			command : ARRAY 8 OF CHAR;
			data : ARRAY 14 OF CHAR;
			res : SET; i : INTEGER; tlen : LONGINT;
		BEGIN
			IF numregs > 7 THEN HALT(303); END;
		
			command[0] := 40X; 
			command[1] := SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, access)+ {0,1,2}));
			command[2] := 0X; 
			command[3] := 0X; 
			command[4] := 0X; 
			command[5] := 0X;
			command[6] := CHR(numregs*2); 
			command[7] := CHR(SYSTEM.LSH(numregs*2, -8));
		
			FOR i:= 0 TO numregs - 1 DO
				data[i*2] := registers[i]; data[(i*2)+1] := dataout[i];
			END;
		
			res := ScmSendControl(0, 80H, 040H, 0, 0, command, 0, 8, timeout);
			IF res # TransportDone THEN RETURN res END;
		
			res := ScmBulkTransport(DataOut, data, 0, numregs*2, tlen, timeout);
			IF res # TransportDone THEN RETURN res END;
		
			RETURN ScmWaitNotBusy(timeout);
		END ScmMultipleWrite;
		
		PROCEDURE ScmReadBlock(access, reg : CHAR; VAR content : ARRAY OF CHAR; ofs, len: LONGINT; VAR tlen : LONGINT; timeout : LONGINT): SET;
		VAR
			command : ARRAY 8 OF CHAR; res : SET;
		BEGIN
			command[0] := 0C0X; 
			command[1] := SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, access)+ {1}));
			command[2] := reg; 
			command[3] := 0X; 
			command[4] := 0X; 
			command[5] := 0X;
			command[6] := CHR(len); 
			command[7] := CHR(SYSTEM.LSH(len, -8));
			
			tlen := 0;
			res := ScmSendControl(0, 80H, 40H, 0, 0, command, 0, 8, timeout);
			IF res # TransportDone THEN RETURN res END;
			res := ScmBulkTransport(DataIn, content, ofs, len, tlen, timeout);
			RETURN res;
		END ScmReadBlock;
		
		PROCEDURE ScmWriteBlock(access, reg : CHAR; VAR content : ARRAY OF CHAR; ofs, len : LONGINT; VAR tlen : LONGINT; timeout : LONGINT): SET;
		VAR
			command : ARRAY 8 OF CHAR; 
			res : SET;
		BEGIN
			command[0] := 40X; 
			command[1] := SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, access)+ {0,1}));
			command[2] := reg; 
			command[3] := 0X; 
			command[4] := 0X; 
			command[5] := 0X;
			command[6] := CHR(len); 
			command[7] := CHR(SYSTEM.LSH(len, -8));
			
			tlen := 0;
			res := ScmSendControl(0, 80H, 40H, 0, 0, command, 0, 8, timeout);
			IF res # TransportDone THEN RETURN res END;
			
			res := ScmBulkTransport(DataOut, content, ofs, len, tlen, timeout);
			IF res # TransportDone THEN RETURN res END;
			RETURN ScmWaitNotBusy(timeout);
		END ScmWriteBlock;
		
		PROCEDURE ScmRWBlockTest(access : CHAR; VAR registers, dataout : ARRAY OF CHAR;
			numregs :INTEGER; datareg, statusreg, atapitimeout, qualifier : CHAR; dir : SET; VAR content : ARRAY OF CHAR;
			ofs, contentlen: LONGINT; VAR tlen : LONGINT; timeout : LONGINT): SET;
		VAR
			command : ARRAY 16 OF CHAR;
			data : ARRAY 38 OF CHAR; tmpreg : CHAR; res : SET;
			status : CHAR; i, msgindex, msglen : INTEGER;
			tmplen : LONGINT;
		BEGIN
			IF numregs > 19 THEN
				AosOut.String("UsbStorage: ScmRWBlockTest too many registers"); AosOut.Ln;
				HALT(303);
			END;
			
			command[0] := 40X; 
			command[1] := SYSTEM.VAL(CHAR, SYSTEM.VAL(SET,access) + {0,1,2});
			command[2] := 7X; 
			command[3] := 17X; 
			command[4] := 0FCX; 
			command[5] := 0E7X; 
			command[6] := CHR(numregs*2); 
			command[7] := CHR(SYSTEM.LSH(numregs*2, -8));
			IF dir = DataOut THEN
				command[8] := 40X; 
				command[9] := SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, access) + {0,2});
			ELSIF dir = DataIn THEN
				command[8] := 0C0X; 
				command[9] := SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, access) + {2});
			ELSE
				HALT(303)
			END;
			command[10] := datareg; 
			command[11] := statusreg; 
			command[12] := atapitimeout;
			command[13] := qualifier; 
			command[14] := CHR(contentlen); 
			command[15] := CHR(SYSTEM.LSH(contentlen, -8));
		
			FOR i:=0 TO numregs -1 DO
				data[i*2] := registers[i]; data[(i*2)+1] := dataout[i];
			END;
		
			tlen := 0;
			
			FOR i:=0 TO 19 DO
			
				IF i = 0 THEN msgindex := 0; msglen := 16 ELSE msgindex := 8; msglen := 8 END;
				
				res := ScmSendControl(0, 80H, 40H, 0, 0, command, msgindex, msglen, 1000);
				IF res # TransportDone THEN
					IF (res = TransportFatal) OR (res = TransportTimeout) THEN RETURN res ELSE RETURN TransportError END;
				END;
				
				IF i = 0 THEN
					res := ScmBulkTransport(DataOut, data, 0, numregs*2, tmplen, 1000);
					IF res # TransportDone THEN
						IF (res = TransportFatal) OR (res = TransportTimeout) THEN RETURN res ELSE RETURN TransportError END;
					END;
				END;
				
				res := ScmBulkTransport(dir, content, 0, contentlen, tlen, timeout);
				IF res = TransportShort THEN
					IF (dir = DataIn) & (i=0) THEN (* hm. makes somehow no sense, but that's life *)
						IF ~device.ClearHalt(bulkOut) THEN
							AosOut.String("UsbStorage: ScmRWBlockTest clear halt failed"); AosOut.Ln;
						END
					END;
					
				IF dir = DataOut THEN tmpreg := 17X; ELSE tmpreg := 0EX; END;
				
				res := ScmRead(ScmATA, tmpreg, status, 1000);
				IF res # TransportDone THEN 
					IF res = TransportFatal THEN RETURN res ELSE RETURN TransportError END;
					ELSIF (SYSTEM.VAL(SET, status) * {0}) # {} THEN
						IF Debug THEN AosOut.String("UsbStorage: ScmRWBlockTest: check condition"); AosOut.Ln; END;
						RETURN TransportError;
					ELSIF (SYSTEM.VAL(SET, status) * {5}) # {} THEN
						IF Debug THEN AosOut.String("UsbStorage: ScmRWBlockTest: device fault"); AosOut.Ln; END;
						RETURN TransportFatal;
					END;
				ELSIF res # TransportDone THEN
					IF (res = TransportFatal) OR (res = TransportTimeout) THEN RETURN res ELSE RETURN TransportError END;
				ELSE
					RETURN ScmWaitNotBusy(timeout);
				END;
			END;
				
			IF Debug THEN AosOut.String("UsbStorage: ScmRWBlockTest failed 20 times!"); AosOut.Ln; END;
				
			RETURN TransportError;
				
		END ScmRWBlockTest;
		
		PROCEDURE ScmSelectAndTestRegisters() : BOOLEAN;
		VAR
			selector : INTEGER; status : CHAR;
		BEGIN
			FOR selector := 0A0H TO 0B0H BY 10H DO (* actually, test 0A0H and 0B0H *)
				IF ScmWrite(ScmATA, 16X, CHR(selector), 1000) # TransportDone THEN RETURN FALSE END;
				IF ScmRead(ScmATA, 17X, status, 1000) # TransportDone THEN RETURN FALSE END;
				IF ScmRead(ScmATA, 16X, status, 1000) # TransportDone THEN RETURN FALSE END;
				IF ScmRead(ScmATA, 14X, status, 1000) # TransportDone THEN RETURN FALSE END;
				IF ScmRead(ScmATA, 15X, status, 1000) # TransportDone THEN RETURN FALSE END;
				IF ScmWrite(ScmATA, 14X, 55X, 1000) # TransportDone THEN RETURN FALSE END;
				IF ScmWrite(ScmATA, 15X, 0AAX, 1000) # TransportDone THEN RETURN FALSE END;
				IF ScmRead(ScmATA, 14X, status, 1000) # TransportDone THEN RETURN FALSE END;
				IF ScmRead(ScmATA, 15X, status, 1000) # TransportDone THEN RETURN FALSE END;
			END;
			RETURN TRUE;
		END ScmSelectAndTestRegisters;
		
		PROCEDURE ScmSetShuttleFeatures(externaltrigger, eppcontrol, maskbyte, testpattern, subcountH, subcountL : CHAR) : BOOLEAN;
		VAR
			command: ARRAY 8 OF CHAR;
		BEGIN
			command[0] := 40X; 
			command[1] := 81X; 
			command[2] := eppcontrol; 
			command[3] := externaltrigger;
			command[4] := testpattern; 
			command[5] := maskbyte; 
			command[6] := subcountL; 
			command[7] := subcountH;
			IF ScmSendControl(0, 80H, 40H, 0, 0, command, 0, 8, 1000) # TransportDone THEN RETURN FALSE; END;
			RETURN TRUE;
		END ScmSetShuttleFeatures;
		
		PROCEDURE TransportSCMShuttleInit() : BOOLEAN;
		VAR
			res : SET;
			status : CHAR;
		BEGIN
			IF Trace THEN AosOut.String("AosUsbStorage: Initializing SCM USB-ATAPI Shuttle... "); END;
			res := ScmWriteUserIO(SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, ScmUioOE0) + SYSTEM.VAL(SET, ScmUioOE1))),
				SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, ScmUioEpad) + SYSTEM.VAL(SET, ScmUio1))), 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 1"); AosOut.Ln; RETURN FALSE; END;
			
			MilliWait(2000);
			
			res := ScmReadUserIO(status, 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 2"); AosOut.Ln; RETURN FALSE; END;
			
			res := ScmReadUserIO(status, 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 3"); AosOut.Ln; RETURN FALSE; END;
			
			res := ScmWriteUserIO(SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, ScmUioDrvrst) + SYSTEM.VAL(SET, ScmUioOE0)
				+ SYSTEM.VAL(SET, ScmUioOE1))), SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, ScmUioEpad)
				+ SYSTEM.VAL(SET, ScmUio1))), 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 4"); AosOut.Ln; RETURN FALSE; END;
			
			res := ScmWriteUserIO(SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, ScmUioOE0) + SYSTEM.VAL(SET, ScmUioOE1)),
				 SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, ScmUioEpad) + SYSTEM.VAL(SET, ScmUio1))), 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 5"); AosOut.Ln; RETURN FALSE; END;
			
			MilliWait(250);
			
			res := ScmWrite(ScmISA, 03FX, 080X, 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 6"); AosOut.Ln; RETURN FALSE; END;
			res := ScmRead(ScmISA, 027X, status, 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 7"); AosOut.Ln; RETURN FALSE; END;
			res := ScmReadUserIO(status, 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 8"); AosOut.Ln; RETURN FALSE; END;
			IF ~ScmSelectAndTestRegisters() THEN
				AosOut.String("UsbStorage: SCM Init error, step 9"); AosOut.Ln; RETURN FALSE;
			END;
			
			res := ScmReadUserIO(status, 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 10"); AosOut.Ln; RETURN FALSE; END;
			
			res := ScmWriteUserIO(SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, ScmUioAckd) + SYSTEM.VAL(SET, ScmUioOE0)
				+ SYSTEM.VAL(SET, ScmUioOE1))), SYSTEM.VAL(CHAR, (SYSTEM.VAL(SET, ScmUioEpad)
				+ SYSTEM.VAL(SET, ScmUio1))), 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 11"); AosOut.Ln; RETURN FALSE; END;
			
			res := ScmReadUserIO(status, 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 12"); AosOut.Ln; RETURN FALSE; END;
			
			MilliWait(1400);
			
			res := ScmReadUserIO(status, 1000);
			IF res # TransportDone THEN AosOut.String("UsbStorage: SCM Init error, step 13"); AosOut.Ln; RETURN FALSE; END;
			IF ~ScmSelectAndTestRegisters() THEN
				AosOut.String("UsbStorage: SCM Init error, step 14"); AosOut.Ln; RETURN FALSE;
			END;
			IF ~ScmSetShuttleFeatures(83X, 0X, 88X, 08X, 15X, 14X) THEN
				AosOut.String("UsbStorage: SCM Init error, step 15"); AosOut.Ln; RETURN FALSE;
			END;
			IF Trace THEN AosOut.String("done."); AosOut.Ln; END;
			RETURN TRUE;
		END TransportSCMShuttleInit;
		
		PROCEDURE Transport(VAR cmd : ARRAY OF CHAR; cmdlen : INTEGER; dir : SET;
			VAR buffer : ARRAY OF CHAR; ofs, bufferlen : LONGINT; VAR tlen : LONGINT; timeout : LONGINT) : SET;
		VAR
			registers, data : ARRAY 32 OF CHAR;
			i : INTEGER; res : SET; status : CHAR;
			atapilen, tmplen, sector, transfered : LONGINT;
		BEGIN
		
			registers[0] := 11X; registers[1] := 12X; registers[2] := 13X; registers[3] := 14X;
			registers[4] := 15X; registers[5] := 16X; registers[6] := 17X;
			data[0] := 0X; data[1] := 0X; data[2] := 0X; data[3] := CHR(bufferlen);
			data[4] := CHR(SYSTEM.LSH(bufferlen, -8)); data[5] := 0B0X; data[6] := 0A0X;
			FOR i:= 7 TO 18 DO
				registers[i] := 010X;
				IF (i - 7) >= cmdlen THEN data[i] := 0X; ELSE data[i] := cmd[i-7]; END;
			END;
		
			tlen := 0;
		
			IF dir = DataOut THEN
				AosOut.String("UsbStorage: SCM DataOut not supported!!!"); AosOut.Ln;
				RETURN TransportError;
			END;
		
			IF bufferlen > 65535 THEN
				IF Debug THEN
					AosOut.String("UsbStorage: Too large request for SCM USB-ATAPI Shuttle"); AosOut.Ln;
				END;
				RETURN TransportError;
			END;
			IF cmd[0] = 28X THEN (* READ 10 command *)
				IF bufferlen < 10000H THEN
					IF Trace THEN AosOut.String("UsbStorage: Doing SCM single read"); AosOut.Ln; END;
					res := ScmRWBlockTest(ScmATA, registers, data, 19, 10X, 17X, 0FDX, 30X, DataIn, buffer, ofs, bufferlen, tlen, timeout);
					RETURN res;
				ELSE
					IF Trace THEN AosOut.String("UsbStorage: Doing SCM multi read"); AosOut.Ln; END;
					tmplen := (65535 DIV sdev.blockSize) * sdev.blockSize;
					sector := SYSTEM.LSH(ScmShortPack(data[10], data[9]), 16) + ScmShortPack(data[12], data[11]);
					transfered := 0;
					WHILE transfered # bufferlen DO
						IF tmplen > (bufferlen - transfered) THEN tmplen := bufferlen - transfered END;
						data[3] := CHR(tmplen); data[4] := CHR(SYSTEM.LSH(tmplen, -8));
						data[9] := CHR(SYSTEM.LSH(sector, -24));
						data[10] := CHR(SYSTEM.LSH(sector, -16));
						data[11] := CHR(SYSTEM.LSH(sector, -8));
						data[12] := CHR(sector);
						data[14] := CHR(SYSTEM.LSH(tmplen DIV sdev.blockSize, -8));
						data[15] := CHR(tmplen DIV sdev.blockSize);
						
						res := ScmRWBlockTest(ScmATA, registers, data, 19, 10X, 17X, 0FDX, 30X, DataIn, buffer, ofs+transfered, tmplen, atapilen, timeout);
						transfered := transfered + atapilen;
						tlen := transfered;
						sector := sector + (tmplen DIV sdev.blockSize);
						IF res # TransportDone THEN RETURN res END;
					END;
					RETURN TransportDone;
				END;
			END;

		IF Trace THEN AosOut.String("UsbStorage: Sending SCM registers"); AosOut.Ln; END;
		res := ScmMultipleWrite(ScmATA, registers, data, 7, 1000);
		IF res # TransportDone THEN
			IF Debug THEN AosOut.String("UsbStorage: SCM register setup failed"); AosOut.Ln; END;
			RETURN TransportError
		END;
		
		IF cmdlen # 12 THEN
			AosOut.String("UsbStorage: SCM command len # 12"); AosOut.Ln;
			HALT(303);
		END;
		
		IF Trace THEN AosOut.String("UsbStorage: Sending SCM command"); AosOut.Ln; END;
		res := ScmWriteBlock(ScmATA, 10X, cmd, 0, 12, tmplen, timeout);
		IF res # TransportDone THEN
			IF Debug THEN AosOut.String("UsbStorage: SCM command transfer failed"); AosOut.Ln; END;
			RETURN TransportError
		END;
		
		IF (bufferlen # 0) & (dir = DataIn) THEN
			IF Trace THEN AosOut.String("UsbStorage: SCM  data transfer"); AosOut.Ln; END;
			res := ScmRead(ScmATA, 014X, status, 1000);
			IF res # TransportDone THEN
				IF Debug THEN AosOut.String("UsbStorage: ScmRead failed"); AosOut.Ln; END;
				RETURN TransportError
			END;
			atapilen := ORD(status);
			IF bufferlen > 255 THEN
				res := ScmRead(ScmATA, 015X, status, 1000);
				IF res # TransportDone THEN
					IF Debug THEN AosOut.String("UsbStorage: ScmRead2 failed"); AosOut.Ln; END;
					RETURN res;
				END;
				atapilen := atapilen + (ORD(status) * 256);
			END;
			IF Trace THEN
				AosOut.String("UsbStorage: Scm Transfer: Want: "); AosOut.Int(bufferlen, 0);
				AosOut.String(" / have: "); AosOut.Int(atapilen, 0); AosOut.Ln;
			END;
			tmplen := atapilen;
			IF atapilen < bufferlen THEN
				IF Debug THEN AosOut.String("UsbStorage: Scm has FEWER bytes in the atapi buffer"); AosOut.Ln; END;
			ELSIF atapilen > bufferlen THEN
				IF Debug THEN AosOut.String("UsbStorage: Scm has MORE bytes in the atapi buffer"); AosOut.Ln; END;
				tmplen := bufferlen;
			END;
			res := ScmReadBlock(ScmATA, 10X, buffer, ofs, tmplen, tlen, timeout);
			IF Trace THEN
				IF (res = TransportDone) OR (res = TransportShort) THEN
					AosOut.String("UsbStorage: wanted: "); AosOut.Int(tmplen, 0);
					AosOut.String(" / got: "); AosOut.Int(tlen, 0); AosOut.Ln;
				END;
			END;
			IF (res = TransportDone) & (atapilen < bufferlen) THEN res := TransportShort END;
			IF (res # TransportDone) & (res # TransportShort) THEN
				IF Debug THEN AosOut.String("UsbStorage: ScmReadBlock failed"); AosOut.Ln; END;
				RETURN res;
			END;
		ELSE
			tlen := 0;
		END;
		
		RETURN TransportDone;
		
		END Transport;

	END SCMTransport;
	
TYPE

	TransportSpecialInitProc = PROCEDURE(sdev : StorageDevice) : BOOLEAN;

TYPE
	
	(* manages a list of all installed USB storage devices and registers/unregisters them at the Disks.registry *)
	DiskManager = OBJECT
	VAR
		storageDeviceList : StorageDevice;
		suffixUsed : ARRAY 100 OF BOOLEAN;
		regName : ARRAY 32 OF CHAR;
		res : LONGINT;
		
		PROCEDURE Add*(dev : StorageDevice);
		VAR
			i : LONGINT;
		BEGIN {EXCLUSIVE}
		
			ASSERT(dev#NIL);
			IF DmTrace THEN 
				AosOut.String("AosUsbStorage: Add device ");
				AosOut.String(dev.name);
				AosOut.String(" ("); AosOut.String(dev.desc); AosOut.String(") to registry ... ");			
			END;
			
			(* add new device *)
			dev.next := storageDeviceList.next;
			storageDeviceList.next := dev;
			
			(* get unused suffix *)
			i:=0; WHILE suffixUsed[i] & (i<100) DO INC(i) END;
			
			IF (i=99) & suffixUsed[99] THEN 
				AosOut.Ln;
				AosOut.String("AosUsbStorage: Can't register device. Maximal 100 devices supported."); AosOut.Ln;
				RETURN;
			END;
				
			(* generate unique device name *)
			suffixUsed[i]:=TRUE;
			dev.number:=i;
			
			i:=1;
			WHILE (dev.name[i]#0X) & (i<32) DO INC(i); END;
			
			IF (dev.name[i]#0X) THEN
				AosOut.Ln;
				AosOut.String("AosUsbStorage: Error: Couldn't register the device ");
				AosOut.String(dev.name);
				AosOut.String(" (device names shall be 2-30 characters long (incl. 0X)"); AosOut.Ln;
				suffixUsed[dev.number]:=FALSE;
				RETURN;
			END;
			
			COPY(dev.name, regName);
			
			IF dev.number < 10 THEN
				regName[i] := CHR(ORD("0") + dev.number); regName[i+1] := 0X;
			ELSIF dev.number < 100 THEN
				regName[i] := CHR(ORD("0") + dev.number DIV 10);
				regName[i+1] := CHR(ORD("0") + dev.number MOD 10); regName[i+2] := 0X;
			END;

			dev.SetName(regName);
			
			Disks.registry.Add(dev, res);
			
			IF res#AosPlugins.Ok THEN 
				AosOut.Ln;
				AosOut.String("AosUsbStorage: Error: Couldn't add device to AosDisks.registry (Error code: ");
				AosOut.Int(res,0); AosOut.String(")"); AosOut.Ln;
				suffixUsed[dev.number]:=FALSE;
				RETURN;
			END;		
			IF DmTrace THEN AosOut.String("done."); AosOut.Ln; END;
		END Add;
		
		PROCEDURE Remove*(dev : StorageDevice);
		VAR
			temp : StorageDevice;
		BEGIN
			IF DmTrace THEN 
				AosOut.String("AosUsbStorage: Remove device ");
				AosOut.String(dev.name);
				AosOut.String(" ("); AosOut.String(dev.desc); AosOut.String(") from registry ...");			
			END;

			temp:=storageDeviceList;
			WHILE (temp.next#NIL) & (temp.next.name#dev.name) DO temp:=temp.next; END;
			
			IF (temp.next=NIL) OR (temp.next.name#dev.name) THEN
				AosOut.Ln; 
				AosOut.String("AosUsbStorage: Warning: Couldn't remove device from registry (device not found)"); AosOut.Ln;
			ELSE
				temp.next := temp.next.next;
				Disks.registry.Remove(dev); 
				suffixUsed[dev.number]:=FALSE;
			END;
			
			IF DmTrace THEN AosOut.String("done."); AosOut.Ln; END;
		END Remove;
		
		(* removes all registered USB storage devices from the AosDisks.registry *)
		PROCEDURE RemoveAll;
		VAR 
			temp : StorageDevice;
		BEGIN
			temp := storageDeviceList.next;
			
			WHILE temp#NIL DO
				Disks.registry.Remove(temp); 
				suffixUsed[temp.number]:=FALSE;
				temp:=temp.next;
			END;
			IF DmTrace THEN AosOut.String("AosUsbStorage: All devices removed from registry."); AosOut.Ln; END;
		END RemoveAll;
		
		(* displays a list of all USB storage devices which are registred at the Drivermanager *)
		PROCEDURE Show;
		VAR
			temp : StorageDevice;
		BEGIN
			AosOut.String("USB Storage Devices registered at AosUsbStorage:"); AosOut.Ln;
			IF storageDeviceList.next=NIL THEN
				AosOut.String("No devices registred."); 
			ELSE
				temp:=storageDeviceList.next;
				WHILE(temp#NIL) DO
					AosOut.String(temp.name); 
					AosOut.String(" ("); AosOut.String(temp.desc); AosOut.String(")"); AosOut.Ln;
					temp:=temp.next;
				END;
				AosOut.Ln;
			END;
		END Show;
		
		PROCEDURE &Init;
		BEGIN
			NEW(storageDeviceList);
		END Init;
	
	END DiskManager;

VAR
	diskManager : DiskManager;
	timer : AosKernel.Timer;
	hackTimer : AosKernel.Timer;
	
(* wait is not reentrant !!! *)
PROCEDURE MilliWait(ms : LONGINT);
BEGIN
	timer.Sleep(ms)
END MilliWait;

PROCEDURE Probe(dev : AosUsb.UsbDevice; intfc : LONGINT) : AosUsb.UsbDriver;
VAR
	if : AosUsb.UsbDeviceInterface;
	stordev : StorageDevice;
	transportMethod, transportProtocol : LONGINT;
	bulkInEndpoint, bulkOutEndpoint, interruptEndpoint, endpoint : INTEGER;
	interruptInterval : INTEGER;
	bulkOnlyTransport : BulkOnlyTransport;
	cbiTransport : CBITransport;
	scmTransport : SCMTransport;
	description : AosUsb.Description;
	name : AosUsb.Name;
	driver : UsbStorageDriver;
	i : LONGINT;
BEGIN
	if := dev.actConfiguration.interfaces[intfc];

	(* Is it a USB Mass Storage Class device ? *)
	IF if.bInterfaceClass # 8 THEN RETURN NIL END;
	
	CASE if.bInterfaceProtocol OF
		0 :  transportMethod := MethodCBI;
		|1 : transportMethod := MethodCB;
		|50H : transportMethod := MethodBulkOnly;
	ELSE
		RETURN NIL; (* transport method not supported *)
	END;	

	CASE if.bInterfaceSubClass OF
		1 : transportProtocol := ProtocolRBC; description := "Usb Reduced Block Command Drive"; name := "USBRBC";
		|2 : transportProtocol := Protocol8020; description := "Usb SFF8020i ATAPI device"; name := "USBATAPI";
		|3 : transportProtocol := ProtocolQIC157; description := "Usb QIC-157 Tape device"; name := "USBQIC";
		|4 : transportProtocol := ProtocolUFI; description := "Usb UFI Floppy drive"; name := "USBUFI";
		|5 : transportProtocol := Protocol8070; description := "Usb SFF8070i ATAPI device"; name := "USBATAPI";
		|6 : transportProtocol := ProtocolUTS; description := "Usb Transparent SCSI device"; name := "USBSCSI";
	ELSE
		RETURN NIL; (* Protocol not supported *)
	END;
	
	(* now parse all endpoints *)
	IF (if.bNumEndpoints # 2) & (if.bNumEndpoints # 3) THEN RETURN NIL END;

	FOR i:= 0 TO if.bNumEndpoints - 1 DO
		endpoint := SHORT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, if.endpoints[i].bEndpointAddress) * {0,1,2,3,7}));
		IF (if.endpoints[i].bmAttributes = {1}) & (SYSTEM.VAL(SET, if.endpoints[i].bEndpointAddress) * {7} = {} ) THEN
			bulkOutEndpoint := endpoint;
		ELSIF  (if.endpoints[i].bmAttributes = {1}) & (SYSTEM.VAL(SET, if.endpoints[i].bEndpointAddress) * {7} # {} ) THEN
			bulkInEndpoint := endpoint;
		ELSIF  (if.endpoints[i].bmAttributes = {0,1}) & (SYSTEM.VAL(SET, if.endpoints[i].bEndpointAddress) * {7} # {} ) THEN
			interruptEndpoint := endpoint; interruptInterval := if.endpoints[i].bInterval; 
		END;
	END;

	(* Create the driver instance *)
	IF transportMethod = MethodCBI THEN
			IF (bulkInEndpoint = 0) OR (bulkOutEndpoint = 0) OR (interruptEndpoint = 0) THEN RETURN NIL END;
			NEW(cbiTransport, dev, intfc);
			driver := cbiTransport;
	ELSIF transportMethod = MethodCB THEN
			IF (bulkInEndpoint = 0) OR (bulkOutEndpoint = 0) THEN RETURN NIL END;
			NEW(cbiTransport, dev, intfc);
			driver := cbiTransport;
	ELSIF transportMethod = MethodBulkOnly THEN
			IF (bulkInEndpoint = 0) OR (bulkOutEndpoint = 0) THEN RETURN NIL END;
			NEW(bulkOnlyTransport, dev, intfc);
			driver := bulkOnlyTransport;
	ELSIF transportMethod = MethodSCMShuttle THEN
			IF (bulkInEndpoint = 0) OR (bulkOutEndpoint = 0) THEN RETURN NIL END;
			NEW(scmTransport, dev, intfc);
			driver := scmTransport;
	ELSE
		RETURN NIL;
	END;
	
(*
	(* Special init, if necessary *)
	IF SpecialInit # NIL THEN
		IF ~(SpecialInit(ProbeDev)) THEN RETURN NIL; END;
	END;
*)
	
	NEW(stordev);
	(* fields from Disk.Mod *)
	stordev.name := name; stordev.desc := description; 
	stordev.blockSize := 0; stordev.flags := {};
	stordev.table := NIL; stordev.openCount := 0;
	(* our fields *)
	stordev.usbDriver := driver;

	driver.sdev := stordev;
	driver.bulkIn := bulkInEndpoint;
	driver.bulkOut := bulkOutEndpoint;
	driver.interrupt := interruptEndpoint;
	driver.interruptInterval := interruptInterval;
	driver.transportProtocol := transportProtocol;
	driver.transportMethod := transportMethod;

	(* test if drive is working and is of mass storage type (important for SCSI devices) *)
	IF ~driver.Inquiry() THEN RETURN NIL; (* should not happen *) END; 
	
	(* override given name if devicetype = 5 (the deviceType field was written by the Inquiry command) *)
	IF driver.deviceType = 5 THEN stordev.name := "USBCD"; END;
	
	RETURN driver;

END Probe;	

(* displays the UFI command to KernelLog *)
PROCEDURE ShowUFICmd(cmd : CHAR) ;
BEGIN
	CASE ORD(cmd) OF
		04H : AosOut.String("Format Unit");
		| 12H :  AosOut.String("Inquiry");
		| 55H : AosOut.String("Mode Select");
		| 5AH : AosOut.String("Mode Sense");
		| 1EH : AosOut.String("Prevent-Allow Media Removal");
		| 28H : AosOut.String("Read(10)");
		| 0A8H : AosOut.String("Read(12)");
		| 25H : AosOut.String("Read Capacity");
		| 23H : AosOut.String("Read Format Capabilities");
		| 03H : AosOut.String("Request Sense");
		| 01H : AosOut.String("Rezero");
		| 2BH : AosOut.String("Seek(10)");
		| 1DH : AosOut.String("Send Diagnostic");
		| 1BH :AosOut.String("Start-Stop Unit");
		| 00H : AosOut.String("Test Unit Ready");
		| 2FH : AosOut.String("Verify");
		| 2AH : AosOut.String("Write(10)");
		| 0AAH : AosOut.String("Write(12)");
		| 2EH : AosOut.String("Write and Verify");
	ELSE
		AosOut.String("Unknown Command("); AosOut.Int(ORD(cmd), 0); AosOut.String(")");
	END;
END ShowUFICmd;


(* shows all devices which are registered at the AosUsbStorage Disk Manager and the AosDisks.registry *)
PROCEDURE Show*;
VAR
	table : AosPlugins.Table;
	i : LONGINT;
BEGIN
	AosOut.Ln;
	(* show all devices which are registered at the AosUsbStorage disk manager *)
	diskManager.Show;
	(* show all devices registered at AosDisks.registry *)
	Disks.registry.GetAll(table);
	AosOut.Ln; AosOut.Ln; AosOut.String("Storage devices registered at AosDisks.registry:"); AosOut.Ln;
	IF LEN(table)=0 THEN 
		AosOut.String("No devices registered."); AosOut.Ln;
	ELSE
		FOR i:=0 TO LEN(table)-1 DO 
			AosOut.String(table[i].name);
			AosOut.String(" ("); AosOut.String(table[i].desc); AosOut.String(")"); AosOut.Ln;
		END;
	END;
END Show;

PROCEDURE Init*(ptr : PTR): PTR;
BEGIN
	(* dummy *)
	RETURN NIL;
END Init;

PROCEDURE Cleanup();
BEGIN
	AosUsb.drivers.Remove(Name);
	diskManager.RemoveAll;
	AosOut.String("All USB storage devices disconnected."); AosOut.Ln;
END Cleanup;

BEGIN
	NEW(timer);
	NEW(diskManager);
	AosUsb.drivers.Add(Probe, Name, Description, 10);
	NEW(hackTimer);
	hackTimer.Sleep(2000);
	AosModules.InstallTermHandler(Cleanup);
END AosUsbStorage.

(** Init: AosUsbStorage.Install **)
System.Free AosUsbStorage~
