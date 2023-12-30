MODULE AosUsbStorageBot; (** AUTHOR: "staubesv"; PURPOSE: "Bulk-Only transport layer of USB mass storage driver"; *)
(**
 * References:
 *
 * 	-	Universal Serial Bus Mass Storage Class Bulk-Only Transport, Revision 1.0, September 31, 1999
 *		www.usb.org
 *
 * History:
 *	
 *	09.02.2006	First release (staubesv)
 *	05.07.2006	Adapted to AosUsbi (staubesv)
 *)
 
IMPORT
	AosOut, SYSTEM,
	AosUsbdi, Base := AosUsbStorageBase, Debug := AosUsbDebug;

TYPE

	(* USB mass storage class bulk only transport layer *)
	BulkOnlyTransport* = OBJECT(Base.StorageDriver)
	VAR
		CBWbuffer : AosUsbdi.BufferPtr;
		CSWbuffer : AosUsbdi.BufferPtr;
		seqNbr : LONGINT;
		
		(* Perform reset recovery, i.e. send Bulk-Only Mass Storage Reset command via default control pipe and 	*)
		(* then clear the EndpointHalt feature of the bulk in and bulk out endpoints of the USB device. The request 	*)
		(* shall ready the device for the next CBW from the host. See [2], pages 7 & 16								*)
		PROCEDURE Reset*(timeout : LONGINT) : LONGINT;
		VAR critical : BOOLEAN; status : AosUsbdi.Status;
		BEGIN
			IF Debug.Trace & Debug.traceScRequests THEN AosOut.String("AosUsbStorage: Doing reset recovery ... "); END;
			(* Mass storage devices request: Bulk-Only Mass Storage Reset *)
			status := device.Request(AosUsbdi.ToDevice + AosUsbdi.Class + AosUsbdi.Interface, 255, 0, interface.bInterfaceNumber, 0, AosUsbdi.NoData);
			IF (status = AosUsbdi.Disconnected) THEN
				RETURN Base.ResDisconnected;
			ELSIF status # AosUsbdi.Ok THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: Mass storage reset failed."); AosOut.Ln; END;
				RETURN Base.ResFatalError;
			END;
			IF bulkInPipe.IsHalted() THEN critical := ~bulkInPipe.ClearHalt(); END;
			IF bulkOutPipe.IsHalted() THEN critical := critical OR ~bulkOutPipe.ClearHalt(); END;
			IF critical THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: Failure on BulkOnly reset ClearHalt"); AosOut.Ln; END;
				RETURN Base.ResFatalError;
			END; 
			IF Debug.Trace & Debug.traceScRequests THEN AosOut.String("AosUsbStorage: Reset recovery succeeded."); AosOut.Ln; END;	
			RETURN Base.ResOk;
		END Reset;
		
		(* The Get Max LUN device request is used to determine the number of logical units supported by the device *)
		PROCEDURE GetMaxLun*(VAR maxlun : LONGINT): LONGINT;
		VAR buffer : AosUsbdi.BufferPtr;  status : AosUsbdi.Status;
		BEGIN
			IF Debug.Trace & Debug.traceScRequests THEN AosOut.String("AosUsbStorage: GetMaxLUN.... "); END;
			NEW(buffer, 1);
			status := device.Request(AosUsbdi.ToHost + AosUsbdi.Class + AosUsbdi.Interface, 254, 0, interface.bInterfaceNumber, 1, buffer^); 
			IF status = AosUsbdi.Ok THEN
				maxlun := ORD(buffer[0]);
				IF Debug.Trace & Debug.traceScRequests THEN AosOut.String("MaxLUN is: "); AosOut.Int(maxlun, 0); AosOut.Ln; END;	
				RETURN Base.ResOk;
			ELSIF status = AosUsbdi.Stalled THEN (* Devices that do not suppoert multiple LUNs may stall this command *)
				maxlun := 0;
				IF Debug.Trace & Debug.traceScRequests THEN AosOut.String("MaxLUN request not supported (STALL)"); AosOut.Ln; END;	
				RETURN Base.ResOk;
			ELSIF status = AosUsbdi.Disconnected THEN
				RETURN Base.ResDisconnected;
			ELSE
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: GetMaxLUN request failed."); AosOut.Ln; END;
				RETURN Base.ResFatalError;
			END;
		END GetMaxLun;
		
		(* Process a bulk-only transfer. A three stage protocol is used:												*)
		(* 	1. Send command block wrapper (CBW) to device														*)
		(*	2. Dataphase (optional)																				*)
		(*	3. Receive command status word (CSW) from device 													*)
		PROCEDURE Transport*(cmd : ARRAY OF CHAR; cmdlen : LONGINT; dir :  SET;
			VAR buffer : ARRAY OF CHAR; ofs, bufferlen : LONGINT; VAR tlen : LONGINT; timeout : LONGINT) : LONGINT;
		VAR status : AosUsbdi.Status; i, residual : LONGINT;
		BEGIN (* No concurrency allowed *)
			ASSERT((cmdlen > 0) & (cmdlen <= 16)); (* [2], page 14 *)
			(* set up dCBWSignature *)
			CBWbuffer[0] := 55X; CBWbuffer[1] := 53X; CBWbuffer[2] := 42X; CBWbuffer[3] := 43X;
			(* set up dCBWTag - will be echoed by the device *)
			INC(seqNbr);
			CBWbuffer[4] := CHR(seqNbr); 
			CBWbuffer[5] := CHR(SYSTEM.LSH(seqNbr, -8)); 
			CBWbuffer[6] := CHR(SYSTEM.LSH(seqNbr, -16)); 
			CBWbuffer[7] := CHR(SYSTEM.LSH(seqNbr, -24)); 
			(* set up dCBWDataTransferLength *)
			CBWbuffer[8] := CHR(bufferlen);
			CBWbuffer[9] := CHR(SYSTEM.LSH(bufferlen, -8));
			CBWbuffer[10] := CHR(SYSTEM.LSH(bufferlen, -16));
			CBWbuffer[11] := CHR(SYSTEM.LSH(bufferlen, -24));
			(* set up bmCBWFlags *)
			IF dir = Base.DataIn THEN CBWbuffer[12] := 80X; ELSE CBWbuffer[12] := 0X; END;
			(* set bCBWLUN *)
			CBWbuffer[13] := CHR(SYSTEM.VAL(LONGINT, SYSTEM.LSH(SYSTEM.VAL(SET, ORD(cmd[1])) * {5..7}, -5)));
			(*set bCBWCBLength *)
			CBWbuffer[14] := CHR(cmdlen);
			FOR i := 15 TO 30 DO CBWbuffer[i] := 0X; END;
			(* copy CBWCB *)
			FOR i := 0 TO cmdlen-1 DO CBWbuffer[15+i] := cmd[i]; END;
			IF Debug.Trace & Debug.traceCBWs THEN
				AosOut.String("Sending CBW: "); FOR i := 0 TO LEN(CBWbuffer)-1 DO AosOut.Hex(ORD(CBWbuffer[i]), -2); AosOut.Char(" "); END; AosOut.Ln;
			END;
			
			(* send the CBW *)
			IF Base.performance = AosUsbdi.MaxPerformance THEN bulkOutPipe.mode := AosUsbdi.MaxPerformance; ELSE bulkOutPipe.mode := AosUsbdi.MinCpu; END;
			status := bulkOutPipe.Transfer(31, 0, CBWbuffer^);
			IF (status = AosUsbdi.Disconnected) THEN
				RETURN Base.ResDisconnected;
			ELSIF status # AosUsbdi.Ok THEN (* sending the CBW failed -> Perform reset recovery [2], page 15 *)
				RETURN Base.ResFatalError;
			END;
					
			(* If there is data to send, enter the data stage *)
			IF bufferlen # 0 THEN	
				IF Debug.Trace & Debug.traceScTransfers THEN
					AosOut.String("AosUsbStorage: Data Phase: Transfering "); AosOut.Int(bufferlen, 0); AosOut.String(" Bytes to ");
					IF dir = Base.DataIn THEN AosOut.String("Host Controller"); ELSIF dir = Base.DataOut THEN  AosOut.String("Device");	ELSE HALT(301); END;
					AosOut.Ln;
				END;
				IF dir = Base.DataIn THEN
					IF Base.performance = AosUsbdi.MaxPerformance THEN bulkInPipe.mode := AosUsbdi.Normal; ELSE bulkInPipe.mode := AosUsbdi.MinCpu; END;
					bulkInPipe.SetTimeout(timeout);
					status := bulkInPipe.Transfer(bufferlen, ofs, buffer);
					tlen := bulkInPipe.GetActLen();
				ELSIF dir = Base.DataOut THEN
					bulkOutPipe.SetTimeout(timeout);
					IF Base.performance = AosUsbdi.MaxPerformance THEN bulkOutPipe.mode := AosUsbdi.Normal; ELSE bulkOutPipe.mode := AosUsbdi.MinCpu; END;
					status := bulkOutPipe.Transfer(bufferlen, ofs, buffer);
					tlen := bulkOutPipe.GetActLen();
				ELSE HALT(303);
				END;
				
				(* clear halt if STALL occured, but do not abort!!! *)
				IF status = AosUsbdi.Stalled THEN
					IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbStorage: Stall on BulkOnly data phase"); AosOut.Ln; END;
					(* only abort if clear halt fails *)
					 IF ((dir = Base.DataIn) & (~bulkInPipe.ClearHalt())) OR ((dir = Base.DataOut) & (~bulkOutPipe.ClearHalt())) THEN
						IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: Failure on BulkOnly clear halt"); AosOut.Ln; END;
						RETURN Base.ResFatalError; 
					END; 
				ELSIF status = AosUsbdi.InProgress THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: Timeout on BulkOnly data phase"); AosOut.Ln; END;
					RETURN Base.ResTimeout;
				ELSIF status = AosUsbdi.Disconnected THEN
					RETURN Base.ResDisconnected;
				ELSIF status = AosUsbdi.Error THEN
					(* allow short packets and stalls !!! *)
					IF Debug.Level >= Debug.Errors  THEN AosOut.String("AosUsbStorage: Failure on BulkOnly data phase"); AosOut.Ln; END;
					RETURN Base.ResFatalError;
				END;
			ELSE
				tlen := 0;
			END;

			(* enter the status phase - Get the CSW *)
			IF Debug.Trace & Debug.traceScTransfers THEN AosOut.String("AosUsbStorage: Getting BulkOnly CSW"); AosOut.Ln; END;
			IF Base.performance = AosUsbdi.MaxPerformance THEN bulkInPipe.mode := AosUsbdi.MaxPerformance;  ELSE bulkInPipe.mode := AosUsbdi.MinCpu; END;
			bulkInPipe.SetTimeout(timeout);
			status := bulkInPipe.Transfer(13, 0, CSWbuffer^);
					
			IF status = AosUsbdi.InProgress THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: Timeout in CSW phase"); AosOut.Ln; END;
				RETURN Base.ResFatalError 
			ELSIF status = AosUsbdi.Disconnected THEN
				RETURN Base.ResDisconnected;
			ELSIF status # AosUsbdi.Ok THEN
				IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbStorage: Could not get CSW, must retry CSW phase"); AosOut.Ln; END;
				IF (status = AosUsbdi.Stalled) & ~bulkInPipe.ClearHalt() THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: Failure on BulkOnly clear halt"); AosOut.Ln; END;
					RETURN Base.ResFatalError; 
				END; 
				(* Host shall retry to get CSW ([2], page 19) *)
				IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbStorage: Retrying BulkOnly CSW"); AosOut.Ln; END;
				status := bulkInPipe.Transfer(13, 0, CSWbuffer^);
				IF (status = AosUsbdi.Disconnected) THEN
					RETURN Base.ResDisconnected;
				ELSIF status # AosUsbdi.Ok THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: 2nd try to get CSW failed"); AosOut.Ln; END;
					RETURN Base.ResFatalError;
				END;
			END;
			
			IF Debug.Trace & Debug.traceCSWs THEN
				AosOut.String("Received CSW: "); FOR i := 0 TO 12 DO AosOut.Hex(ORD(CSWbuffer[i]), -2); AosOut.Char(" "); END; AosOut.Ln;
			END;
			
			(* Check whether the CSW is valid. If it's not, perform a reset recovery ([2], page 18) *)
			(* Validity: Check CSW signature *)
			IF (CSWbuffer[0] # 55X) OR (CSWbuffer[1] # 53X) OR (CSWbuffer[2] # 42X) OR (CSWbuffer[3] # 53X) THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: Device did not send a valid CSW! (wrong signature)"); AosOut.Ln; END;
				RETURN Base.ResFatalError; 
			END;
			(* Validity: check the dCSWTag *)
			IF (CSWbuffer[4] # CBWbuffer[4]) OR (CSWbuffer[5] # CBWbuffer[5]) OR (CSWbuffer[6] # CBWbuffer[6]) OR (CSWbuffer[7] # CBWbuffer[7]) THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorage: Device sent wrong tag in CSW"); AosOut.Ln; END;
				RETURN Base.ResFatalError;
			END;	
			
			(* Check whether the CSW is meaningful *)
			residual := ORD(CSWbuffer[8]) + 10H*ORD(CSWbuffer[9]) + 100H*ORD(CSWbuffer[10]) + 1000H*ORD(CSWbuffer[11]);
			
			(* Meaning: bCSWStatus *)
			IF (CSWbuffer[12] = 0X) & (residual <= bufferlen) THEN (* CSW meaningful; Command Passed *)
				IF residual # 0 THEN
					tlen := bufferlen - residual;
					RETURN Base.ResShortTransfer;
				ELSE
					RETURN Base.ResOk;
				END;
			ELSIF (CSWbuffer[12] = 1X) & (residual <= bufferlen)  THEN (* CSW meaningful; Command Error *)
				IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbStorage: CSW reports Error"); AosOut.Ln; END;
				RETURN Base.ResError;
			ELSIF CSWbuffer[12] = 2X THEN (* Phase Error: Perform reset recovery [2], page 16*) 
				IF Debug.Trace & Debug.Trace  & Debug.traceCSWs THEN AosOut.String("AosUsbStorage: CSW reports Phase Error"); AosOut.Ln; END;
				RETURN Base.ResFatalError;
			ELSE (* CSW not meaningful -> Perform reset recovery  *)
				IF Debug.Trace THEN AosOut.String("AosUsbStorage: CSW not meaningful"); AosOut.Ln; END;
				RETURN Base.ResFatalError;
			END;			
		END Transport;
		
		PROCEDURE &Init;
		BEGIN
			Init^; NEW(CBWbuffer, 31); NEW(CSWbuffer, 13); seqNbr := 0;
		END Init;

	END BulkOnlyTransport;

END AosUsbStorageBot.
