MODULE AosUsbStorageCbi;  (** AUTHOR "cplattner/staubesv"; PURPOSE " CB/I transport layer of USB mass storage driver"; *)
(**
 * References:
 *
 *	- 	[1] Universal Serial Bus Mass Storage Class Control/Bulk/Interrupt (CBI) Transport, Revision 1.1, June 23, 2003
 *		www.usb.org
 *
 * History:
 *	
 *	09.02.2006	First release (staubesv)
 *	05.07.2006	Adapted to AosUsbdi (staubesv)
 *	07.08.2006	Cleanups, improved error case in transport, fixed transfer offset ignored  (staubesv)
 *)
 
IMPORT
	AosOut,
	Base := AosUsbStorageBase, AosUsbdi, Debug := AosUsbDebug;
	
CONST

	(* Interrupt Data Block coding, 3.4.3.1.1 in [1] *)
	Pass = 0;
	Fail = 1;
	PhaseError = 2;
	PersistentFailure = 3;

TYPE

	(** USB Mass Storage Class Control/Bulk/Interrupt (CBI) and Control/Bulk (CB) transport layer *)
	CBITransport* = OBJECT(Base.StorageDriver)
	
		(** 
		 * The Accept Device-Specific Command class-specific request is uses by the CBI Command Transport
		 * Protocol to send a command block from a host to a device.
		 * @param cmdLen Length of the command
		 * @param cmd Command 
		 * @param timeout in milliseconds
		 * @return transport status of command block
		 *)
		PROCEDURE  AcceptCommand(cmd : AosUsbdi.Buffer; cmdlen, timeout : LONGINT) : AosUsbdi.Status;
		BEGIN
			ASSERT(LEN(cmd) >= cmdlen);
			defaultPipe.SetTimeout(timeout);
			RETURN device.Request(AosUsbdi.ToDevice + AosUsbdi.Class + AosUsbdi.Interface, 0, 0, interface.bInterfaceNumber, cmdlen, cmd);
		END AcceptCommand;
	
		PROCEDURE Reset*(timeout : LONGINT) : LONGINT;
		VAR buffer, interruptData : AosUsbdi.BufferPtr; status : AosUsbdi.Status; i : LONGINT; 
		BEGIN
			IF Debug.Trace & Debug.traceScRequests THEN AosOut.String("AosUsbStorageCbi: Sending CB/I reset ControlTransfer"); AosOut.Ln; END;
			NEW(buffer, 12);
			buffer[0] := CHR(1DH); 
			buffer[1] := CHR(4);
			FOR i := 2 TO 11 DO buffer[i] := CHR(255) END;
			status := AcceptCommand(buffer^, 12, timeout);
			IF (status = AosUsbdi.Disconnected) THEN
				RETURN Base.ResDisconnected;
			ELSIF (status # AosUsbdi.Ok) THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Failure on TransportCB/I-Reset Control"); AosOut.Ln; END;
				RETURN Base.ResFatalError;
			END;
			IF transportMethod = Base.MethodCBI THEN
				IF Debug.Trace & Debug.traceScRequests THEN AosOut.String("AosUsbStorageCbi: Sending CB/I reset InterruptTransfer"); AosOut.Ln; END;
				NEW(interruptData, 8);
				interruptPipe.SetTimeout(timeout);
				status := interruptPipe.Transfer(2, 0, interruptData^);	
				IF status = AosUsbdi.Stalled THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Stall on TransportCB/I-Reset Interrupt"); AosOut.Ln; END;
					IF ~interruptPipe.ClearHalt() THEN RETURN Base.ResError END;
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Failure on TransportCB/I-Reset clear halt on Interruptpipe"); AosOut.Ln; END;
					RETURN Base.ResFatalError;
				ELSIF status = AosUsbdi.InProgress THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Timeout on TransportCB/I-Reset Interrupt"); AosOut.Ln; END;
					RETURN Base.ResTimeout;
				ELSIF status = AosUsbdi.Disconnected THEN
					RETURN Base.ResDisconnected;
				ELSIF status # AosUsbdi.Ok THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Failure on TransportCB/I-Reset Interrupt"); AosOut.Ln; END;
					RETURN Base.ResFatalError;
				END;
			END;
			(* After a Command Block Reset, the Stall condition and data toggle of the device's endpoints are undefined (2.2 in [1]) *)
			IF ~bulkInPipe.ClearHalt() OR ~bulkOutPipe.ClearHalt() THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Failure on CB/I reset ClearHalt"); AosOut.Ln; END;
				RETURN Base.ResFatalError;
			END;
			IF Debug.Trace & Debug.traceScRequests THEN AosOut.String("AosUsbStorageCbi: CB/I reset OK"); AosOut.Ln; END;
			RETURN Base.ResOk;
		END Reset;
		
		PROCEDURE Transport*(cmd : ARRAY OF CHAR; cmdlen : LONGINT; dir : SET;
			VAR buffer : ARRAY OF CHAR; ofs, bufferlen : LONGINT; VAR tlen : LONGINT; timeout : LONGINT) : LONGINT;
		VAR status : AosUsbdi.Status;	 interruptData : AosUsbdi.BufferPtr; blockStatus : LONGINT;
		BEGIN
			IF Debug.Trace & Debug.traceScTransfers THEN AosOut.String("AosUsbStorageCbi: Sending TransportCB/I Control"); AosOut.Ln; END;	
			status := AcceptCommand(cmd, cmdlen, timeout);
			IF status = AosUsbdi.Stalled THEN
				IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbStorageCbi: Stall on TransportCB/I Control"); AosOut.Ln; END;
				RETURN Base.ResError; (* sense device *)
			ELSIF status = AosUsbdi.InProgress THEN
				IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbStorageCbi: Timeout on TransportCB/I Control"); AosOut.Ln; END;
				RETURN Base.ResTimeout;
			ELSIF status = AosUsbdi.Disconnected THEN
				RETURN Base.ResDisconnected;
			ELSIF status # AosUsbdi.Ok THEN
				IF Debug.Level >= Debug.Warnings THEN 
					AosOut.String("AosUsbStorageCbi: Failure on TransportCB/I Control, status :"); AosOut.Int(status, 0); AosOut.Ln; 
				END;
				RETURN Base.ResError; (* sense device *)
			END; 
		
			IF (bufferlen # 0) THEN
			
				IF dir = Base.DataIn THEN
					IF Debug.Trace & Debug.traceScTransfers THEN 
						AosOut.String("AosUsbStorageCbi: Get "); AosOut.Int(bufferlen, 0); AosOut.String(" bytes from device"); AosOut.Ln; 
					END;
					bulkInPipe.SetTimeout(timeout);
					status := bulkInPipe.Transfer(bufferlen, ofs, buffer);
					tlen := bulkInPipe.GetActLen();
				ELSIF dir = Base.DataOut THEN
					IF Debug.Trace & Debug.traceScTransfers THEN 
						AosOut.String("AosUsbStorageCbi: Send "); AosOut.Int(bufferlen, 0); AosOut.String(" bytes to device"); AosOut.Ln; 
					END;
					bulkOutPipe.SetTimeout(timeout);
					status := bulkOutPipe.Transfer(bufferlen, ofs, buffer);
					tlen := bulkOutPipe.GetActLen();		
				ELSE HALT(303);
				END;
			
				IF status = AosUsbdi.Stalled THEN
					IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbStorageCbi: Stall on TransportCB/I Bulk"); AosOut.Ln; END;
					IF ((dir = Base.DataIn) & ~bulkInPipe.ClearHalt()) OR ((dir = Base.DataOut) & ~bulkOutPipe.ClearHalt()) THEN
						IF Debug.Level >= Debug.Warnings THEN AosOut.String("UsbStorage: Failure on TransportCB/I clear halt on Bulkpipe"); AosOut.Ln; END;
						RETURN Base.ResFatalError
					END;
					RETURN Base.ResError; (* sense device *)
				ELSIF status = AosUsbdi.InProgress THEN
					IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbStorageCbi: Timeout on TransportCB/I Bulk"); AosOut.Ln; END;
					RETURN Base.ResTimeout;
				ELSIF status = AosUsbdi.Disconnected THEN
					RETURN Base.ResDisconnected;
				ELSIF status # AosUsbdi.Ok THEN
					IF Debug.Level >= Debug.Warnings THEN AosOut.String("AosUsbStorageCbi: Failure on TransportCB/I Bulk"); AosOut.Ln; END;
					RETURN Base.ResError; (* sense device *)
				END;
			ELSE
				tlen := 0;
			END;

			IF transportMethod = Base.MethodCBI THEN
				IF Debug.Trace & Debug.traceScRequests THEN AosOut.String("AosUsbStorageCbi: Sending TransportCB/I Interrupt"); AosOut.Ln; END;
				
				NEW(interruptData, 2);
				interruptPipe.SetTimeout(timeout);
				status := interruptPipe.Transfer(2, 0, interruptData^);
				
				IF status = AosUsbdi.Stalled THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Stall on TransportCB/I Interrupt"); AosOut.Ln; END;
					IF interruptPipe.ClearHalt() THEN RETURN Base.ResError END;
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Failure on TransportCB/I clear halt on Interruptpipe"); AosOut.Ln; END;
					RETURN Base.ResFatalError 
				ELSIF status = AosUsbdi.InProgress THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Timeout on TransportCB/I Interrupt"); AosOut.Ln; END;
					RETURN Base.ResTimeout;
				ELSIF status = AosUsbdi.Disconnected THEN
					RETURN Base.ResDisconnected;
				ELSIF status # AosUsbdi.Ok THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: Failure on TransportCB/I Interrupt"); AosOut.Ln; END;
					RETURN Base.ResFatalError;
				END;
		
				IF (transportProtocol = Base.ProtocolUFI) THEN
					IF (cmd[0] = 12X) OR (cmd[0] = 03X) THEN
						(* UFI Inquiry + Sense do not change the sense data, so we cannot be sure that those commands succeded!!! *)
						(* just go on and hope the best! *)
					ELSIF (interruptData[0] # 0X) THEN
						IF Debug.Level >= Debug.Errors THEN
							AosOut.String("AosUsbStorageCbi: Error on CBI/UFI, asc = "); AosOut.Hex(ORD(interruptData[0]), 0);
							AosOut.String(" ascq = "); AosOut.Hex(ORD(interruptData[1]), 0); AosOut.Ln;
						END;
						RETURN Base.ResSenseError; (* just retry *)
					END;
					(* go on *)
				ELSIF interruptData[0] # 0X THEN
					IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbStorageCbi: CBI returned invalid interupt data block"); AosOut.Ln; END;
					RETURN Base.ResSenseError; (* try to recover by manual sensing *)
				ELSE 
					(* Command completion interrupt. Error handling according 3.4.3.1.1. in [1] *)
					blockStatus := ORD(interruptData[1]) MOD 4;
					CASE blockStatus OF
						|Pass: (* command status ok *)
						|Fail: RETURN Base.ResError; 
						|PhaseError: RETURN Base.ResFatalError; (* reset device *)
						|PersistentFailure: RETURN Base.ResSenseError; (* request sense *)
					ELSE
						HALT(99);
					END;
				END;
			END;
			IF tlen # bufferlen THEN RETURN Base.ResShortTransfer; END;
			RETURN Base.ResOk;
		END Transport;
		
		PROCEDURE &Init;
		BEGIN
			Init^;
		END Init;
	
	END CBITransport;

END AosUsbStorageCbi.
