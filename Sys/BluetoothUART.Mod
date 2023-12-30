MODULE BluetoothUART;	(** AUTHOR "be"; PURPOSE "HCI UART transport layer"; *)

IMPORT
	AosBoot, AosOut, AosIO, AosKernel, Bluetooth, AosV24, AosActive;
	
(* HCI command packet format (RS-232) 
	| 01X | opcode (2bytes) | total parameter length | par0 | ... | parN |; and opcode = OGF (6bit) || OCF (10bit)
	
	HCI ACL data packet format (RS-232)
	| 02X | 
	
	HCI SCO data packet format (RS-232)
	| 03X | 

	HCI event packet format (RS-232)
	| 04X | Event Code | total parameter length | par0 | ... | parN |
	
	Error message packed format (RS-232)
	| 05X |
	
	Negotiation packet format (RS-232)
	| 06X |
*)

CONST
	
(*
	TraceSend = FALSE;
	TraceReceive = FALSE;
*)

	ModuleName = "[BTUART]";

	uartCommand = 01X;
	uartACLData = 02X;
	uartSCOData = 03X;
	uartEvent = 04X;
	
TYPE

	TransportLayer* = OBJECT(Bluetooth.TransportLayer)

		VAR
			TraceReceive*, TraceSend*: BOOLEAN;	
			dead-: BOOLEAN;
		
		PROCEDURE &Init*(name: ARRAY OF CHAR; sender: AosIO.Sender; receiver: AosIO.Receiver);
		BEGIN
			Init^(name, sender, receiver);
			NEW(out, sender, 512); NEW(in, receiver, 512);
			dead := FALSE;
			TraceReceive := FALSE;	TraceSend := FALSE;
		END Init;
		
		PROCEDURE Close*;
		BEGIN {EXCLUSIVE}
			dead := TRUE
		END Close;
	
		PROCEDURE IsOpen*() :BOOLEAN;
		BEGIN {EXCLUSIVE}
			RETURN ~dead;
		END IsOpen;
	
		PROCEDURE ReadACLPacket() : Bluetooth.Packet;
		VAR acl: Bluetooth.ACLPacket; i : LONGINT;
		BEGIN
			NEW(acl);
			i := ORD(in.Get()) + ORD(in.Get())*100H;
			acl.handle := i  MOD 1000H;
			acl.PB := (i DIV 1000H) MOD 4;
			acl.BC := (i DIV 4000H) MOD 4;
			acl.len := ORD(in.Get()) + ORD(in.Get())*100H;					
			(*ASSERT(acl.len <= Bluetooth.MaxACLDataLen);*)
			IF (acl.len > Bluetooth.MaxACLDataLen) THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.ReadACLPacket: acl.len > Bluetooth.MaxACLDataLen");
				AosOut.Ln;
				AosOut.String("acl.len= "); AosOut.Int(acl.len, 0); 
				AosOut.String("; BluetoothMaxACLDataLen= "); AosOut.Int(Bluetooth.MaxACLDataLen, 0);
				AosOut.String("; in.res= 0x"); AosOut.Hex(in.res, -2);
				AosOut.Ln;
				RETURN NIL;
			END;
			FOR i := 0 TO acl.len-1 DO
				acl.data[i] := in.Get();
			END;
			IF (in.res # 0) THEN 
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.ReadACLPacket: UART failure; in.res= 0x"); AosOut.Hex(in.res, -2);
				AosOut.Ln;
				RETURN NIL;
			END;
			IF TraceReceive THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.ReadACLPacket: reading ACL data"); 
				AosOut.Ln;
				AosOut.String("handle= 0x");AosOut.Hex(acl.handle,-2);
				AosOut.String("; packet boundary= 0x");AosOut.Hex(acl.PB,-2);
				AosOut.String("; broadcast= 0x"); AosOut.Hex(acl.BC,-2);
				AosOut.String("; payload length= 0x"); AosOut.Int(acl.len,0);
				AosOut.String("; acl.data= ");			
				FOR i := 0 TO  acl.len-1 DO
					AosOut.String(" 0x"); AosOut.Hex(ORD(acl.data[i]),-2);				
				END;
				AosOut.Ln;
			END;	
			RETURN acl;
		END ReadACLPacket;
		
		PROCEDURE ReadSCOPacket() : Bluetooth.Packet;
		VAR sco: Bluetooth.SCOPacket; i : LONGINT;
		BEGIN
			AosOut.String(ModuleName);
			AosOut.String("TransportLayer.ReadSCOPacket: uartSCOData received!! continue ....");
			AosOut.Ln;
			NEW(sco);
			i := ORD(in.Get()) + ORD(in.Get())*100H;
			sco.handle := i MOD 1000H;
			sco.len := ORD(in.Get());
			(*ASSERT(sco.len <= Bluetooth.MaxSCODataLen);*)
			IF (sco.len > Bluetooth.MaxSCODataLen) THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.ReadSCOPacket: sco.len > Bluetooth.MaxSCODataLen");
				AosOut.Ln;
				AosOut.String("sco.len= "); AosOut.Int(sco.len, 0); 
				AosOut.String("; BluetoothMaxACLDataLen= "); AosOut.Int(Bluetooth.MaxSCODataLen, 0); 
				AosOut.String("; in.res= 0x"); AosOut.Hex(in.res, -2);
				AosOut.Ln;
				RETURN NIL;
			END;
			FOR i := 0 TO sco.len-1 DO
				sco.data[i] := in.Get();
			END;
			IF (in.res # 0) THEN 
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.ReadSCOPacket: UART failure; in.res= 0x"); AosOut.Hex(in.res, -2);
				AosOut.Ln;
				RETURN NIL;
			END;
			IF TraceReceive THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.ReadSCOPacket: reading SCO data");
				AosOut.Ln;
				AosOut.String("handle= 0x");AosOut.Hex(sco.handle,-2);
				AosOut.String(" payload length= 0x"); AosOut.Int(sco.len,0);
				AosOut.String("; sco.data= ");			
				FOR i := 0 TO sco.len-1 DO
					AosOut.String(" 0x"); AosOut.Hex(ORD(sco.data[i]),-2);				
				END;
				AosOut.Ln;
			END;
			RETURN sco;
		END ReadSCOPacket;
		
		PROCEDURE ReadEventPacket() : Bluetooth.Packet;
		VAR event: Bluetooth.EventPacket; i : LONGINT;
		BEGIN
			NEW(event);
			event.code :=in. Get();
			event.paramLen := ORD(in.Get());
			(*ASSERT(event.paramLen < Bluetooth.MaxEventParamLen);*)
			IF (event.paramLen > Bluetooth.MaxEventParamLen) THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.ReadEventPacket: paramLen > MaxParamLen");
				AosOut.Ln;
				AosOut.String("paramLen= "); AosOut.Int(event.paramLen, 0); 
				AosOut.String("; MaxParamLen= "); AosOut.Int(Bluetooth.MaxEventParamLen, 0);
				AosOut.String("; in.res= 0x"); AosOut.Hex(in.res, -2);
				AosOut.Ln;
			END;
			FOR i := 0 TO event.paramLen-1 DO
				event.params[i] := in.Get();
			END;
			IF (in.res # 0) THEN 
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.ReadEventPacket: UART failure; in.res= 0x"); AosOut.Hex(in.res, -2);
				AosOut.Ln;
				RETURN NIL;
			END;
			IF TraceReceive THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.ReadEventPacket: reading event Data");
				AosOut.Ln; 
				AosOut.String("event.code = 0x"); AosOut.Hex(ORD(event.code),-2);
				AosOut.String("; event.paramLen= "); AosOut.Int(event.paramLen,0);
				AosOut.String("; event.params= ");
				FOR i := 0 TO event.paramLen-1 DO
					AosOut.String(" 0x"); AosOut.Hex(ORD(event.params[i]),-2);
				END;
				AosOut.Ln;
			END;
			RETURN event;
		END ReadEventPacket;
		
		PROCEDURE ReadUnknownPacket() : Bluetooth.Packet;
		VAR unknown: Bluetooth.UnknownPacket; ch : CHAR;
		BEGIN
			AosOut.String(ModuleName);
			AosOut.String("TransportLayer.ReadUnknownPacket: unknown/invalid packet ch= 0x"); AosOut.Hex(ORD(ch),-2);
			AosOut.String("; in.res= 0x"); AosOut.Hex(in.res, -2);
			AosOut.String("; in.Available()= "); AosOut.Int(in.Available(), 0); 
			AosOut.Ln;
			NEW(unknown);
			unknown.len := 0;
			WHILE ((in.Available() > 0) & (in.res = 0)) DO
				IF(unknown.len < Bluetooth.MaxUnknownDataLen) THEN
					unknown.data[unknown.len] := in.Get();
					AosOut.String("unknown.data["); AosOut.Int(unknown.len,0); AosOut.String("]= 0x");
					AosOut.Hex(ORD(unknown.data[unknown.len]),-2);
					AosOut.String("; in.res= 0x"); AosOut.Hex(in.res, -2);
					AosOut.Ln;	
					INC(unknown.len);
				ELSE
					ch := in.Get();
					AosOut.String("discard ch= 0x"); AosOut.Hex(ORD(ch),-2);
					AosOut.String("; in.res= 0x"); AosOut.Hex(in.res, -2);
					AosOut.Ln;
				END;
			END;
			RETURN unknown;
		END ReadUnknownPacket;
		
		
		PROCEDURE Read;
		VAR 
			ch: CHAR; i: LONGINT; 
			queue: Bluetooth.Queue; 	
			packet: Bluetooth.Packet;
		BEGIN
			ch := in.Get();		
			IF (in.res # 0) THEN 
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Read: UART failure in.res= 0x"); AosOut.Hex(in.res, -2);
				AosOut.String("; closing layer");
				AosOut.Ln;
				Close;
				RETURN;
			END;
			IF (ch = uartCommand) THEN 	(* HCI command packet *)
				(*HALT(100)	(* not sent by host controller *)*)
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Read: uartCommand received! closing layer");
				AosOut.Ln;
				Close;
				RETURN;
			ELSIF (ch = uartACLData) THEN	(* HCI ACL data packet *)
				packet := ReadACLPacket();
				queue := sink[Bluetooth.ACL];
			ELSIF (ch = uartSCOData) THEN	(* HCI SCO data packet *)
				packet := ReadSCOPacket();
				queue := sink[Bluetooth.SCO]; 
			ELSIF (ch = uartEvent) THEN		(* HCI event packet *)
				packet := ReadEventPacket();
				queue := sink[Bluetooth.Event]; 
			ELSE 							(* unknown/invalid packet *)
				packet := ReadUnknownPacket();
				queue := sink[Bluetooth.Default]; 
			END;
			IF (packet = NIL) THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Read: error while reading packet; ch= "); AosOut.Char(ch);
				AosOut.String("; in.res= "); AosOut.Int(in.res, 0); 
				AosOut.String("; closing layer");
				AosOut.Ln;
				Close;
				RETURN;
			ELSE
				queue.Add(packet);
			END;
			IF TraceReceive THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Read done.");
				AosOut.String(" in.Available()= "); AosOut.Int(in.Available(), 0);
				AosOut.Ln;
			END;
		END Read;
		
		PROCEDURE GetPacketType(type: LONGINT; VAR c: CHAR): BOOLEAN;
		VAR res: BOOLEAN;
		BEGIN
			res := TRUE;
			CASE type OF
				| Bluetooth.Command: c := uartCommand
				| Bluetooth.ACL: c := uartACLData
				| Bluetooth.SCO: c := uartSCOData
				ELSE res := FALSE
			END;
			RETURN res
		END GetPacketType;
		
		PROCEDURE Send*(type: LONGINT; VAR data: ARRAY OF CHAR; ofs, len: LONGINT; VAR res: LONGINT);
		VAR  pt: CHAR; i: LONGINT;
		BEGIN {EXCLUSIVE}
			IF ~GetPacketType(type, pt) THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Send: wrong packet type= 0x"); AosOut.Hex(type,-2); 
				AosOut.Ln;
				res := Bluetooth.ErrInvalidParameters;
				RETURN
			END;
			IF TraceSend THEN 
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Send: packet type= 0x"); AosOut.Hex(ORD(pt), -2);
				FOR i := 0 TO len-1 DO 
					AosOut.Char(" ");	
					AosOut.Hex(ORD(data[ofs+i]), -2); 
				END;
				AosOut.Ln
			END;
			out.Char(pt); out.Bytes(data, ofs, len); out.Update;
			res := out.res	
		END Send;
		
		PROCEDURE Send1H*(type: LONGINT; VAR hdr: ARRAY OF CHAR; hdrlen: LONGINT; VAR data: ARRAY OF CHAR; ofs, len: LONGINT; VAR res: LONGINT);
		VAR pt: CHAR; i: LONGINT;
		BEGIN
			IF ~GetPacketType(type, pt) THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Send1H: wrong packet type= 0x"); AosOut.Hex(type,-2); 
				AosOut.Ln;
				res := Bluetooth.ErrInvalidParameters;
				RETURN
			END;
			IF TraceSend THEN 
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Send1H: packet type= 0x"); AosOut.Hex(ORD(pt), -2);
				FOR i := 0 TO hdrlen-1 DO 
					 AosOut.Char(" "); AosOut.Hex(ORD(hdr[i]), -2);
				END;
				FOR i := 0 TO len-1 DO 
					AosOut.Char(" "); AosOut.Hex(ORD(data[ofs+i]), -2); 
				END;
				AosOut.Ln
			END;
			out.Char(pt); out.Bytes(hdr, 0, hdrlen); out.Bytes(data, ofs, len); out.Update;
			res := out.res
		END Send1H;
		
		PROCEDURE Send2H*(type: LONGINT; VAR hdr1: ARRAY OF CHAR; hdr1len: LONGINT; 
								VAR hdr2: ARRAY OF CHAR; hdr2len: LONGINT;
								VAR data: ARRAY OF CHAR; ofs, len: LONGINT; VAR res: LONGINT);
		VAR pt: CHAR; i: LONGINT;
		BEGIN
			IF ~GetPacketType(type, pt) THEN
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Send2H: wrong packet type= 0x"); AosOut.Hex(type,-2); 
				AosOut.Ln;
				res := Bluetooth.ErrInvalidParameters;
				RETURN
			END;
			IF TraceSend THEN 
				AosOut.String(ModuleName);
				AosOut.String("TransportLayer.Send2H: packet type= 0x"); AosOut.Hex(ORD(pt), -2);
				FOR i := 0 TO hdr1len-1 DO 
					 AosOut.Char(" "); AosOut.Hex(ORD(hdr1[i]), -2);
				END;
				FOR i := 0 TO hdr2len-1 DO 
					AosOut.Char(" "); AosOut.Hex(ORD(hdr2[ofs+i]), -2); 
				END;
				FOR i := 0 TO len-1 DO 
					AosOut.Char(" "); AosOut.Hex(ORD(data[ofs+i]), -2);
				END;
				AosOut.Ln
			END;
			out.Char(pt); out.Bytes(hdr1, 0, hdr1len); out.Bytes(hdr2, 0, hdr2len); out.Bytes(data, ofs, len); out.Update;
			res := out.res
		END Send2H;

	BEGIN {ACTIVE}
		AosActive.SetPriority(3); 
		REPEAT
			Read;
		UNTIL dead
	END TransportLayer;
	
END BluetoothUART.
