MODULE BluetoothUSB; (** AUTHOR: "staubesv"; PURPOSE: "HCI USB Transport Layer"; *)
(**
 *
 * History:
 *
 *	01.12.2005 Cleanup (staubesv)
 *)
 
IMPORT AosOut, AosIO, AosPlugins, Bluetooth, AosUsbBluetooth, AosUsb, AosUsbdi;

TYPE

	UsbTransportLayer* = OBJECT(Bluetooth.TransportLayer)
	VAR
		driver : AosUsbBluetooth.BluetoothDriver;
		TraceReceive*, TraceSend*: BOOLEAN;
		
		event : Bluetooth.EventPacket; (* for EventHandler, must be global *)
		
		eventExpectedParams : LONGINT; (* expected length of parameters in bytes *)
		eventParamOffset : LONGINT;
		
		acl: Bluetooth.ACLPacket; 
		aclExpectedParams : LONGINT; (* expected length of parameters in bytes *)
		aclParamOffset : LONGINT;

		PROCEDURE &Init*(name: ARRAY OF CHAR; sender: AosIO.Sender; receiver: AosIO.Receiver);
		VAR plugin : AosPlugins.Plugin;
		BEGIN
			Init^(name,NIL,NIL);
			TraceSend := FALSE; TraceReceive := FALSE; 
			plugin := AosUsb.usbDrivers.Get(name);
			IF plugin = NIL THEN 
				AosOut.String("AosUsbBluetooth: "); AosOut.String(name); AosOut.String(" no found."); AosOut.Ln;
			ELSE
				driver:=plugin(AosUsbBluetooth.BluetoothDriver);
				driver.SetEventHandler(EventHandler);
				driver.SetAclHandler(ReadACL);
			END;
		END Init;
		
		PROCEDURE Init2*(name: ARRAY OF CHAR): BOOLEAN;
		VAR plugin : AosPlugins.Plugin;
		BEGIN
			(* provisorisch *)
			TraceSend:=TRUE; TraceReceive:=TRUE;
			plugin := AosUsb.usbDrivers.Get(name);
			IF plugin=NIL THEN 
				AosOut.String("AosUsbBluetooth: "); AosOut.String(name); AosOut.String(" no found."); AosOut.Ln;
				RETURN FALSE;
			END;
			driver := plugin(AosUsbBluetooth.BluetoothDriver);
			driver.SetEventHandler(EventHandler);
			driver.SetAclHandler(ReadACL);
			RETURN TRUE;
		END Init2;
		
		PROCEDURE Close*;
		BEGIN 
		END Close;
		
		(** receives HCI event packet fragments (each fragment 16 bytes)  and enters them into the event queue *)
		PROCEDURE EventHandler(packet : AosUsbdi.Buffer; actLen : LONGINT);
		VAR 
			i : LONGINT;
			eventQueue : Bluetooth.Queue;

			PROCEDURE DeliverPacket*;
			BEGIN
				ASSERT((event#NIL));
				IF TraceReceive THEN AosOut.String("AosUsbBluetooth: EventHandler: Packet added to event queue."); 
				AosOut.Ln; AosOut.Ln;  
				END;
				eventQueue := sink[Bluetooth.Event]; 
				eventQueue.Add(event);
				eventParamOffset:=0; eventExpectedParams:=0;
				event:=NIL;
			END DeliverPacket;
			
		BEGIN	
			IF TraceReceive THEN 
				AosOut.String("AosUsbBluetooth: ") ; AosOut.String(driver.name);
				AosOut.String(": EventHandler: Incoming: "); AosOut.Int(actLen, 0); AosOut.String(" Byte(s): ");
				AosOut.Ln;
			END; 
			IF event=NIL THEN (* should be the beginning of a new event packet *)

				IF TraceReceive THEN
					AosOut.String("New packet: "); ShowEvent(ORD(packet[0])); 
					AosOut.String(", "); AosOut.Int(ORD(packet[1]), 0); AosOut.String(" Byte(s) params:  ");
					FOR i := 0 TO actLen-1 DO AosOut.Hex(ORD(packet[i]), -2); AosOut.Char(" ") END; 
					(* if the packet contains status information, display it as text ... *)
					i := ORD(packet[0]);
					IF (i = 01H) OR (i=03H) OR ((i >= 05H) & (i<=0DH)) OR (i=0FH) OR (i=12H) OR (i=14H) OR (i=1CH) OR (i=1DH) THEN
						AosOut.String("Status : "); ShowErrorCode(ORD(packet[2])); 
					END;
					AosOut.Ln;
				END;	
				NEW(event);
				event.code:=packet[0];
				event.paramLen := ORD(packet[1]);
				ASSERT(event.paramLen < Bluetooth.MaxEventParamLen);
				IF event.paramLen>14 THEN (* there will be more fragments of this event packet *)
					eventExpectedParams := event.paramLen-14 ;
					ASSERT(actLen=16);
					FOR i:=0 TO 13 DO event.params[i] := packet[2+i]; END;
					eventParamOffset := 16;
			
				ELSE (* cool! parameters fit into this packet *)
					ASSERT(actLen=2+event.paramLen);
					FOR i:=0 TO event.paramLen-1 DO event.params[i]:=packet[2+i]; END;
					DeliverPacket;		
				END;
			
			ELSE (* next fragment of packet *)
			
				IF TraceReceive THEN 
					AosOut.String("Fragment: "); FOR i := 0 TO LEN(packet)-1 DO AosOut.Hex(ORD(packet[i]), -2); AosOut.Char(" ") END;AosOut.Ln;
				END;
				IF eventExpectedParams <= 16 THEN (* fits in this packet *)
					ASSERT(actLen=eventExpectedParams);
					FOR i:=0 TO eventExpectedParams-1 DO event.params[eventParamOffset+i]:=packet[i];END;
					DeliverPacket;
				ELSE (* there will be at least on more packet *)
					ASSERT(actLen=16);
					eventExpectedParams:=eventExpectedParams-16;
					eventParamOffset:=eventParamOffset+16;
					FOR i:=0 TO 15 DO event.params[eventParamOffset+i]:=packet[i]; END;
				END;
			END;
		END EventHandler;
		
		PROCEDURE ReadACL(packet : AosUsbdi.Buffer; actLen : LONGINT);
		VAR  
			queue: Bluetooth.Queue; 
			i: LONGINT; 

			PROCEDURE DeliverPacket*;
			BEGIN
				ASSERT(acl#NIL);
				queue := sink[Bluetooth.ACL]; 
				queue.Add(acl);
				aclParamOffset:=0; aclExpectedParams:=0;
				acl:=NIL;
			END DeliverPacket;
	
		BEGIN
			IF TraceReceive THEN AosOut.String("AosUsbBluetooth: Device "); AosOut.String(name); AosOut.String(" receives ACL: "); END;
			IF acl=NIL THEN (* should be the beginning of a new acl packet *)
					
				NEW(acl);
				i := ORD(packet[0]) + ORD(packet[1])*100H;
				acl.handle := i MOD 1000H;
				acl.PB := (i DIV 1000H) MOD 4;
				acl.BC := (i DIV 4000H) MOD 4;
				acl.len := ORD(packet[2]) + ORD(packet[3])*100H;
				ASSERT(acl.len <= Bluetooth.MaxACLDataLen);
				IF TraceReceive THEN 
					AosOut.String("New Packet: "); AosOut.Int(acl.len, 0); AosOut.String(" Byte(s): ");
					FOR i:=0 TO actLen-1 DO AosOut.Hex(ORD(packet[i]),-2); AosOut.Char(" "); END;
					AosOut.Ln; 
				END;
			
				IF acl.len>60 THEN (* there will be more fragments of this ACL packet *)
					aclExpectedParams := acl.len-60 ;
					ASSERT(actLen=64);
					FOR i:=0 TO 59 DO acl.data[i] := packet[4+i]; END;
					aclParamOffset := 64;
			
				ELSE (* cool. parameters fit into this packet *)
					ASSERT(actLen=4+acl.len);
					FOR i:=0 TO acl.len-1 DO acl.data[i]:=packet[4+i]; END;
					DeliverPacket;		
				END;
			
			ELSE (* next fragment of packet *)

				IF TraceReceive THEN 
					AosOut.String("Fragment: "); FOR i:=0 TO actLen-1 DO AosOut.Hex(ORD(packet[i]),-2); AosOut.Char(" "); END;
					AosOut.Ln; 
				END;
				IF aclExpectedParams <= 64 THEN (* fits in this packet *)
					ASSERT(actLen=aclExpectedParams);
					FOR i:=0 TO aclExpectedParams-1 DO acl.data[aclParamOffset+i]:=packet[i];END;
					DeliverPacket;
				ELSE (* there will be at least on more packet *)
					ASSERT(actLen=64);
					FOR i:=0 TO 63 DO acl.data[aclParamOffset+i]:=packet[i]; END;
					aclExpectedParams:=aclExpectedParams-64;
					aclParamOffset:=aclParamOffset+64;
				END;
			END;
		END ReadACL;
		
		PROCEDURE Send*(type: LONGINT; VAR data: ARRAY OF CHAR; ofs, len: LONGINT; VAR res: LONGINT);
		VAR  i: LONGINT;
		BEGIN {EXCLUSIVE}
			IF TraceSend THEN 
				AosOut.Ln;
				AosOut.String("AosUsbBluetooth: Send: "); AosOut.String(name); AosOut.String(": ");
				AosOut.Hex(type, -2); AosOut.Char(" ");
				FOR i := 0 TO len-1 DO AosOut.Hex(ORD(data[ofs+i]), -2); AosOut.Char(" ") END;
				AosOut.Ln;
			END;
			CASE type OF
				| Bluetooth.Command:   driver.SendCommand(data, ofs, len, res);
				| Bluetooth.ACL: driver.SendACL(data, ofs, len, res);
				(* Bluetooth.Event cannot be send to the host controller; Bluetooth.SCO would require isochronous USB transfers, which
				are not yet implemented *)
			ELSE 
				IF TraceSend THEN AosOut.String("wrong packet type"); AosOut.Ln; END;
				res := Bluetooth.ErrInvalidParameters;		
			END;
		END Send;
		
		PROCEDURE Send1H*(type: LONGINT; VAR hdr: ARRAY OF CHAR; hdrlen: LONGINT; VAR data: ARRAY OF CHAR; ofs, len: LONGINT; VAR res: LONGINT);
		VAR  i: LONGINT; buffer : POINTER TO ARRAY OF CHAR; bufferLen : LONGINT;
		BEGIN
			IF TraceSend THEN 
				AosOut.Ln;
				AosOut.String("AosUsbBluetooth: "); AosOut.String(name); AosOut.String(": Send1H:");
				AosOut.String(" HdrLen: "); AosOut.Int(hdrlen, 0); AosOut.String(" DataLen: "); AosOut.Int(len, 0);
				AosOut.String(" DataOfs: "); AosOut.Int(ofs, 0); AosOut.String(" Type: "); AosOut.Hex(type, -2); 
				AosOut.String(" Hdr: "); FOR i := 0 TO hdrlen-1 DO AosOut.Hex(ORD(hdr[i]), -2); AosOut.Char(" ") END;
				AosOut.String(" Data: "); FOR i := 0 TO len-1 DO AosOut.Hex(ORD(data[ofs+i]), -2); AosOut.Char(" ") END;
				AosOut.Ln
			END;
			bufferLen := hdrlen + len;
			NEW(buffer,bufferLen);
			
			FOR i:=0 TO hdrlen-1 DO buffer[i]:=hdr[i]; END;
			FOR i:=0 TO len-1 DO buffer[i+hdrlen]:=data[ofs+i]; END;
			
			CASE type OF
				| Bluetooth.Command:   driver.SendCommand(buffer^, 0, bufferLen, res);
				| Bluetooth.ACL: driver.SendACL(buffer^, 0, bufferLen, res);
				(* Bluetooth.Event cannot be send to the host controller; Bluetooth.SCO would require isochronous USB transfers, which
				are not yet implemented *)
			ELSE 
				IF TraceSend THEN AosOut.String("wrong packet type"); AosOut.Ln; END;
				res:=Bluetooth.ErrInvalidParameters;
			END;
		END Send1H;
		
		PROCEDURE Send2H*(type: LONGINT; VAR hdr1: ARRAY OF CHAR; hdr1len: LONGINT; 
				VAR hdr2: ARRAY OF CHAR; hdr2len: LONGINT; VAR data: ARRAY OF CHAR; ofs, len: LONGINT; VAR res: LONGINT);
		VAR 
			i: LONGINT;
			buffer : POINTER TO ARRAY OF CHAR;
			bufferLen : LONGINT;
		BEGIN
			IF TraceSend THEN 
				AosOut.String("AosUsbBluetooth: Send2H: "); AosOut.String(name); AosOut.String(": ");
				AosOut.Hex(type, -2); AosOut.Char(" ");
				FOR i := 0 TO hdr1len-1 DO AosOut.Hex(ORD(hdr1[i]), -2); AosOut.Char(" ") END;
				FOR i := 0 TO hdr2len-1 DO AosOut.Hex(ORD(hdr2[i]), -2); AosOut.Char(" ") END;
				FOR i := 0 TO len-1 DO AosOut.Hex(ORD(data[ofs+i]), -2); AosOut.Char(" ") END;
				AosOut.Ln
			END;
			bufferLen:=hdr1len+hdr2len+len;
			NEW(buffer,bufferLen);
			
			FOR i:=0 TO hdr1len-1 DO buffer[i]:=hdr1[i]; END;
			FOR i:=0 TO hdr2len-1 DO buffer[hdr1len+i]:=hdr2[i]; END;
			FOR i:=0 TO len-1 DO buffer[i+hdr1len+hdr2len]:=data[ofs+i]; END;
			
			CASE type OF
				| Bluetooth.Command:   driver.SendCommand(buffer^, 0, bufferLen, res);
				| Bluetooth.ACL: driver.SendACL(buffer^, 0, bufferLen, res);
				(* Bluetooth.Event cannot be send to the host controller; Bluetooth.SCO would require isochronous USB transfers, which
				are not yet implemented *)
			ELSE 
				IF TraceSend THEN AosOut.String("wrong packet type"); AosOut.Ln; END;
				res := Bluetooth.ErrInvalidParameters;
			END;
		END Send2H;
		
	END UsbTransportLayer;

PROCEDURE ShowEvent(event : LONGINT);
BEGIN
	CASE event OF
		 01H: AosOut.String("Inquiry Compete"); 
		|02H: AosOut.String("Inquiry Result");
		|03H: AosOut.String("Connection Complete");
		|04H: AosOut.String("Connection Request");
		|05H: AosOut.String("Disconnection Complete");
		|06H: AosOut.String("Authentication Complete");
		|07H: AosOut.String("Remote Name Request Complete");
		|08H: AosOut.String("Encryption Change");
		|09H: AosOut.String("Change Connection Link Key Complete");
		|0AH: AosOut.String("Master Link Key Complete");
		|0BH: AosOut.String("Read Remote Supported Features Complete");
		|0CH: AosOut.String("Read Remote Version Information Complete");
		|0DH: AosOut.String("QoS Setup Complete");
		|0EH: AosOut.String("Command Complete");
		|0FH: AosOut.String("Command Status");
		|10H: AosOut.String("Hardware Error");
		|11H: AosOut.String("Flush Occured");
		|12H: AosOut.String("Role Change");
		|13H: AosOut.String("Number Of Completed Packets");
		|14H: AosOut.String("Mode Change");
		|15H: AosOut.String("Return Link Keys");
		|16H: AosOut.String("PIN Code Request");
		|17H: AosOut.String("Link Key Request");
		|18H: AosOut.String("Link Key Notification");
		|19H: AosOut.String("Loopback Command");
		|1AH: AosOut.String("Data Buffer Overflow");
		|1BH: AosOut.String("Max Slots Change");
		|1CH: AosOut.String("Read Clock Offset Complete");
		|1DH: AosOut.String("Connection Packet Type Changed");
		|1EH: AosOut.String("QoS Violation");
		|1FH: AosOut.String("Page Scan Mode Change");
		|20H: AosOut.String("Page Scan Repetition Mode Change");
		|0FEH: AosOut.String("Bluetooth Logo Testing");
		|0FFH: AosOut.String("Vendor-specific");
	ELSE
		AosOut.String("Unkown");
	END;
END ShowEvent;

PROCEDURE ShowErrorCode(errorcode : LONGINT);
BEGIN
	CASE errorcode OF
		00H: AosOut.String("OK"); 
		| 01H: AosOut.String("Unknown HCI Command");
		| 02H: AosOut.String("No Connection");
		| 03H: AosOut.String("Hardware Failure");
		| 04H: AosOut.String("Page Timeout");
		| 05H: AosOut.String("Authentication Failure");
		| 06H: AosOut.String("Key Missing");
		| 07H: AosOut.String("Memory Full");
		| 08H: AosOut.String("Connection Timeout");
		| 09H: AosOut.String("Max Number Of Connections");
		| 0AH: AosOut.String("Max Number Of SCO Connection To A Device");
		| 0BH: AosOut.String("ACL Connection Already Exists");
		| 0CH: AosOut.String("Command Disallowed");
		| 0DH: AosOut.String("Host Rejected due to limited resources");
		| 0EH: AosOut.String("Host Rejected due to security reasons");
		| 0FH: AosOut.String("Host Rejected (Remote Device is personal device)");
		| 10H: AosOut.String("Host Timeout");
		| 11H: AosOut.String("Unsupported Feature or Parameter Value");
		| 12H: AosOut.String("Invalid HCI Command Parameters");
		| 13H: AosOut.String("Other End Terminated Connection (User ended connection)");
		| 14H: AosOut.String("Other End Terminated Connection (Low Resources)");
		| 15H: AosOut.String("Other End Terminated Connection (About to Power Off)");
		| 16H: AosOut.String("Connection Terminated by Local Host");
		| 17H: AosOut.String("Repeated Attempts");
		| 18H: AosOut.String("Pairing Not Allowd");
		| 19H: AosOut.String("Unknown LMP PDU");
		| 1AH: AosOut.String("Unsupported Remote Feature");
		| 1BH: AosOut.String("SCO Offset Rejected");
		| 1CH: AosOut.String("SCO Interval Rejected");
		| 1DH: AosOut.String("SCO Airmode Rejected");
		| 1EH: AosOut.String("Invalid LMP Parameters");
		| 1FH: AosOut.String("Unspecified Error");
		| 20H: AosOut.String("Unsupported LMP Parameter Value");
		| 21H: AosOut.String("Role Change Not Allowed");
		| 22H: AosOut.String("LMP Response Timeout");
		| 23H: AosOut.String("LMP Error Transaction Collision");
		| 24H: AosOut.String("LMP PDU Not Allowed");
		| 25H: AosOut.String("Encryption Mode Not Acceptable");
		| 26H: AosOut.String("Unit Key Used");
		| 27H: AosOut.String("QoS is Not Supported");
		| 28H: AosOut.String("Instant Passed");
		| 29H: AosOut.String("Pairing with Unit Key Not Supported");
		| 2AH..0FFH: AosOut.String("Reserved for Future Use");
	ELSE
		AosOut.String("Unknown");
	END;
END ShowErrorCode;
	
END BluetoothUSB.

