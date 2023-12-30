(* Copyright 2005-2006, Markus Heule, ETH Zurich *)

MODULE AosOSCNet;  (** AUTHOR "heulemar"; PURPOSE "OpenSoundControl networkplugins (TCP and UDP)"; *)

(*

This modue contains objecttypes for the TCP and UDP implementation of the OSC protocol. For each version, a server 
and a client version is supplied.

The server version uses an AosOSCService as servicebackend. Upon creation of a serverobject, it will 
start listening for connections or packets from the network. When it receives a packet, it parses it and upon successful
parsing, it will hand it over to the corresponding AosOSCService. They can also return packets to the sender of another
packet with the 'Return' function. The services can be stopped with the 'Stop' function.

Note: The TCP version uses the AosTCPServices framework to support multiple concurrent TCP connections.

Example of usage:

VAR
	net: AosOSCNet.OSCUDPServer or AosOSCNet.OSCTCPServer;
	service: AosOSCService.OSCService;
BEGIN
	...
	NEW(net, service, 57110, res); (* server listens now on port 57110 and delivers packets to service *)
	...
	net.Stop; (* stopps the networkplugin *)
	...


The client versions can send OSCPackets to a remote OSCServer. They can also receive replies from the remote OSC server.

Example:

VAR
	client: OSCTCPClient (or OSCUDPClient);
	p, newp: OSCPacket;
	res: LONGINT;
BEGIN
	NEW(client, fip, fport, AosTCP.NilPort, res);
	...
	res := client.Send(p);
	...
	res := client.Receive(newp);	
*)

IMPORT
	AosOSC, AosOSCService, AosIP, AosUDP, AosTCP, AosNet, AosTCPServices, 
	AosActive, AosOut (* Testing *), Utilities := AosOSCUtilities;

CONST
	
	Ok* = 0;
	Timeout* = 4401;
	ParseError* = 4402;
	PacketTooBig* = 4403;
	BadReturnData* = 4404;
	
	MaxUDPPacketLength* = 10000H;
	MaxTCPPacketLength = MaxUDPPacketLength; (* TOOD: What value? *)
	ReceiveTimeout* = 1000; (* ms *)
	
	NotImplemented* = 101;
	
	Trace* = FALSE;
	UDPHack = TRUE;

	
TYPE
	(* abstract class of all network clients *)
	OSCClient = OBJECT
		PROCEDURE Send*(p: AosOSC.OSCPacket): LONGINT;
		BEGIN HALT(NotImplemented); END Send;
		
		PROCEDURE Receive*(VAR p: AosOSC.OSCPacket): LONGINT;
		BEGIN HALT(NotImplemented); END Receive;
		
		PROCEDURE Close*;
		BEGIN HALT(NotImplemented); END Close;
	END OSCClient;
	
	(* This objecttype is used to store the IP and the Port of the remote client. 
		This information is used when a packet should be returned to a sender. (See SetReturner(..) in OSCUDPServer) *)
	OSCUDPData = OBJECT
		VAR
			fip*: AosIP.Adr;
			fport*: LONGINT;
	END OSCUDPData;
	
	(* UDP Client *)
	OSCUDPClient* = OBJECT(OSCClient)
		VAR 
			s: AosUDP.Socket;
			fip: AosIP.Adr;
			fport: LONGINT;

		(* Creates a new UDPClient which sends packets to fip:fport.
			Supply AosUDP.NilPort for lport, if you don't want to specify a fixed local port for communication.
			In res the returnvalue of the AosUDP.Socket's creations is returned. If res doesn't equal to AosUDP.Ok, the
			client shouldn't be used *)
		PROCEDURE &InitUDP(fip: AosIP.Adr; fport, lport: LONGINT; VAR res: LONGINT);
		BEGIN
			SELF.fip := fip;
			SELF.fport := fport;
			NEW(s, lport, res);
		END InitUDP;

		(* sends an OSCMessage or an OSCBundle to fip:fport. Returns the statuscode of AosUDP.Socket.Send *)
		PROCEDURE Send*(p: AosOSC.OSCPacket): LONGINT;
		BEGIN
			RETURN SendUDP(s, fip, fport, p);
		END Send;
		
		(* receives a packet from the network. Only UDP packets from our partner are considered.
			You can also supply a timeout in miliseconds. Use -1 for a infinite wait.
			Returns Ok, ParseError or an AosUDP returncode (eg:. AosUDP.Timeout) *)
		PROCEDURE Recieve*(VAR p: AosOSC.OSCPacket; timeout (* in ms *): LONGINT): LONGINT;
		VAR
			fip2: AosIP.Adr; fport2: LONGINT;
			size: LONGINT;
			buffer: Utilities.String;
			got, res: LONGINT;
			endticks: LONGINT;
			istimeout: BOOLEAN;
		BEGIN
			IF timeout # -1 THEN
				(* timeout *)
				istimeout := TRUE;
				endticks := AosActive.ticks + timeout;
			END;
			NEW(buffer, MaxUDPPacketLength);
			REPEAT
				IF istimeout THEN timeout := endticks - AosActive.ticks; END;
				s.Receive(buffer^, 0, MaxUDPPacketLength, timeout, fip2, fport2, got, res);
			UNTIL (res # AosUDP.Ok) OR (AosIP.AdrsEqual(fip, fip2) & (fport = fport2));
			IF res # AosUDP.Ok THEN RETURN res; END;
			(* parse packet *)
			size := got;
			p := AosOSC.ParseOSCPacket(buffer^, size);
			IF p = NIL THEN RETURN ParseError; END;
			RETURN Ok;
		END Recieve;
		
		(* closes the clientconnection *)
		PROCEDURE Close*;
		BEGIN
			s.Close();
		END Close;
		
	END OSCUDPClient;

	
	(* UDP Server *)
	OSCUDPServer* = OBJECT
		VAR 
			s: AosUDP.Socket; 
			serror: BOOLEAN;
			oscservice: AosOSCService.OSCService;
			stopping: BOOLEAN; (* flag to stop the service *)
			
			(* inernal variables of 'main'-procedure *)			
			newPacket: AosOSC.OSCPacket;
			newUDPData: OSCUDPData;
			buffer: AosOSC.String; (* ARRAY MaxUDPPacketLength OF CHAR; *)
			receivefip: AosIP.Adr; receivefport: LONGINT;
			got, res: LONGINT;
			
		(* Sets the signal to stop the service *)
		PROCEDURE Stop*;
		BEGIN { EXCLUSIVE }
			stopping := TRUE;
		END Stop;
		
		(* Creates a new UDPServer listening on UDP port lport.. Sends received packets to service.
			If res is not AosUDP.Ok, then the server will immediately quit *)
		PROCEDURE &InitUDPServer(service: AosOSCService.OSCService; lport: LONGINT; VAR res: LONGINT);
		BEGIN
			ASSERT(service # NIL);
			oscservice := service;
			NEW(buffer, MaxUDPPacketLength);
			NEW(s, lport, res);
			IF(res # AosUDP.Ok) THEN serror := TRUE; ELSE serror := FALSE; END;
			stopping := FALSE;
		END InitUDPServer;
		
		(* Returns an OSCMessage or an OSCBundle to the sender specified by data, which is indeed an instance of OSCUDPData *)
		PROCEDURE return(p: AosOSC.OSCPacket; data: OBJECT): LONGINT;
		BEGIN
			IF data IS OSCUDPData THEN
				WITH data: OSCUDPData DO
					IF Trace THEN AosOut.String('AosUDPServer.Return called'); AosOut.Ln;
						AosIP.OutAdr(data.fip); AosOut.String(' Port: '); AosOut.Int(data.fport, 10);
						AosOut.Ln; END;
					RETURN SendUDP(s, data.fip, data.fport, p);
				END;
			ELSE
				IF Trace THEN AosOut.String('AosUDPServer.Return: BadReturnData received'); AosOut.Ln; END;
				RETURN BadReturnData;
			END;
		END return;

	BEGIN { ACTIVE }
		IF (~serror) THEN
			REPEAT
				(* receive packets and parse them *)
				s.Receive(buffer^, 0, MaxUDPPacketLength, ReceiveTimeout, receivefip, receivefport, got, res);
				IF res = AosUDP.Ok THEN
					newPacket := AosOSC.ParseOSCPacket(buffer^, got);
					IF newPacket # NIL THEN 
						NEW(newUDPData); 
						IF Trace THEN		
							AosOut.String('OSCUDPServer: Received Packet from: '); AosOut.Hex(receivefip.ipv4Adr, 10);
							AosOut.Hex(receivefip.usedProtocol, 10);
							AosOut.Hex(receivefip.data, 10);
							AosOut.String(' port: '); AosOut.Int(receivefport, 10); AosOut.Ln;
						END;
						IF UDPHack THEN
							newUDPData.fip := AosIP.StrToAdr('192.168.150.1');
						ELSE
							newUDPData.fip := receivefip;
						END;
						newUDPData.fport := receivefport;
						newPacket.SetReturner(return, newUDPData);
						oscservice.NewPacket(newPacket); 
					END;
				ELSIF res # AosUDP.Timeout THEN
					(* closing service *)
					BEGIN { EXCLUSIVE }
						stopping := TRUE;
					END;
				END;
			UNTIL stopping;
			(* cleanup *)
			s.Close();
		END;
	END OSCUDPServer;

	(* TCP Client *)
	OSCTCPClient* = OBJECT(OSCClient)
		VAR
			connection: AosTCP.Connection;
			
		(* creates a new OSCTCPClient and connects to fip:fport. The user can also specify a local port to use for the outgoing
			connection. If AosTCP.NilPort is used, the operating system assigns a free local port number. If res doesn't euqal to
			AosTCP.Ok then this client shouldn't be used. *)
		PROCEDURE &InitTCP(fip: AosIP.Adr; fport, lport: LONGINT; VAR res: LONGINT);
		BEGIN
			NEW(connection);
			connection.Open(lport, fip, fport, res);
		END InitTCP;
		
		PROCEDURE Close*();
		BEGIN
			connection.Close;
		END Close;

		(* sends a packet to the connected OSCServer. Returns AosTCP.Ok if sent successfully, otherwise an AosTCP.* errorcode is
			returned. *)
		PROCEDURE Send*(p: AosOSC.OSCPacket): LONGINT;
		BEGIN
			RETURN SendTCP(connection, p);
		END Send;

		(* receives a packet from the OSC Server. *)
		PROCEDURE Receive*(VAR p: AosOSC.OSCPacket): LONGINT;
		BEGIN
			RETURN ReceiveTCP(connection, p);
		END Receive;
		
	END OSCTCPClient;


	(* An OSCTCPServer will create for each new connection an OSCTCPAgent object. This object handles all the communication
		with the connected client. It also responsible to return messages to the sender of an OSCPacket.
		Note: The registred return-handler also includes the current SELF-pointer. Therfore, a call to returner(...) in
		AosOSC.OSCPacket will always be delivered to the right agent object *)
	OSCTCPAgent = OBJECT(AosTCPServices.Agent);
		VAR
			oscservice: AosOSCService.OSCService;
			newpacket: AosOSC.OSCPacket;
			res: LONGINT;
			
		PROCEDURE &StartOSCAgent(oscs: AosOSCService.OSCService; c: AosTCP.Connection; s: AosTCPServices.Service);
		BEGIN
			ASSERT(oscs # NIL);
			oscservice := oscs;
			Start(c,s);
		END StartOSCAgent;
		
		(* returns a packet to the current client. data is ignored *)
		PROCEDURE return*(p: AosOSC.OSCPacket; data: OBJECT): LONGINT;
		BEGIN
			IF Trace THEN AosOut.String('AosTCPServer.Return called IP: ');
				AosIP.OutAdr(client.fip); AosOut.String(' Port: '); AosOut.Int(client.fport, 10);
				AosOut.Ln; END;
			RETURN SendTCP(client, p);
		END return;

	BEGIN { ACTIVE }
		LOOP
			res := ReceiveTCP(client, newpacket);
			IF res = Ok THEN
				ASSERT(newpacket # NIL);
				newpacket.SetReturner(return, NIL);
				oscservice.NewPacket(newpacket);
			ELSIF res # ParseError THEN EXIT END; (* Closing Connection on unrecoverableerror *)
		END;
		Terminate;
	END OSCTCPAgent;
	
	(* TCP Server *)
	OSCTCPServer* = OBJECT
		VAR
			tcpservice: AosTCPServices.Service;
			service: AosOSCService.OSCService;
			
		(* starts the server: registers the OSCService s and creates the AosTCPServices.Service, which listens for connections *)
		PROCEDURE &InitTCPServer(s: AosOSCService.OSCService; lport: LONGINT; VAR res: LONGINT);
		BEGIN
			ASSERT(s # NIL);
			service := s;
			NEW(tcpservice, lport, newAgent, res);
		END InitTCPServer;
	
		(* This function is called by tcpservice to create a new agent *)
		PROCEDURE newAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
			VAR agent: OSCTCPAgent;
		BEGIN
			NEW(agent, service, c, s); 
			RETURN agent;
		END newAgent;
		
		(* Stops the OSCTCPServer. Closes the listening socket and all established connections *)
		PROCEDURE Stop*;
		BEGIN
			tcpservice.Stop;
		END Stop;
		
	END OSCTCPServer;
	
	
	
	PROCEDURE SendTCP(client: AosTCP.Connection; p: AosOSC.OSCPacket): LONGINT;
	VAR
		buffer: AosOSC.String;
		size: ARRAY 4 OF CHAR;
		res: LONGINT;
	BEGIN
		ASSERT(p # NIL);
		buffer := p.GetBytes();
		ASSERT(buffer # NIL);
		(* TCP: <size || packet> *)
		AosNet.PutNet4(size, 0, p.GetSize());
		client.Send(size, 0, 4, FALSE, res);
		IF(res # AosTCP.Ok) THEN RETURN res; END;
		client.Send(buffer^, 0, LEN(buffer^), FALSE, res);
		RETURN res;
	END SendTCP;
	
	PROCEDURE ReceiveTCP(client: AosTCP.Connection; VAR p: AosOSC.OSCPacket): LONGINT;
	VAR
		res, len: LONGINT;
		buffer: POINTER TO ARRAY OF CHAR;
		sizebuf: ARRAY 4 OF CHAR;
		packetsize: LONGINT;
	BEGIN
		client.Receive(sizebuf, 0, LEN(sizebuf), 4, len, res);
		IF res # AosTCP.Ok THEN RETURN res END;
		ASSERT(len = 4);
		packetsize := AosNet.GetNet4(sizebuf, 0);
		(* allocate new buffer *)
		IF (packetsize < 0) OR (packetsize > MaxTCPPacketLength) THEN
			IF Trace THEN AosOut.String('AosOSCTCPAgent: Packet too big: '); AosOut.Hex(packetsize, 10); AosOut.Ln; END;
			RETURN PacketTooBig;
		END;
		NEW(buffer, packetsize);
		client.Receive(buffer^, 0, packetsize, packetsize, len, res);
		IF res # AosTCP.Ok THEN RETURN res; END;
		ASSERT(len = packetsize);
		p := AosOSC.ParseOSCPacket(buffer^, packetsize);
		IF p = NIL THEN RETURN ParseError; END;
		RETURN Ok;
	END ReceiveTCP;
	
	PROCEDURE SendUDP(s: AosUDP.Socket; fip: AosIP.Adr; fport: LONGINT; p: AosOSC.OSCPacket): LONGINT;
	VAR
		buffer: AosOSC.String;
		res: LONGINT;
	BEGIN
		ASSERT(p # NIL);
		buffer := p.GetBytes();
		ASSERT(buffer # NIL);
		s.Send(fip, fport, buffer^, 0, LEN(buffer^), res);
		IF Trace THEN AosOut.String('SendUDP: buffer: '); AosOut.Buffer(buffer^, 0, LEN(buffer^)); AosOut.String( ' fip '); AosIP.OutAdr(fip);
			AosOut.String(' fport: '); AosOut.Int(fport, 10); AosOut.Ln; END;
		RETURN res;
	END SendUDP;
	(*
	PROCEDURE RecieveUDP(s: AosUDP.Socket; timeout (* in ms *): LONGINT; 
								VAR fip: AosIP.Adr; VAR fport: LONGINT; VAR p: AosOSC.OSCPacket): LONGINT;
		VAR
			fip2: AosIP.Adr; fport2: LONGINT;
			size: LONGINT;
			buffer: Utilities.String;
			got, res: LONGINT;
		BEGIN
			NEW(buffer, MaxUDPPacketLength);
			ASSERT(buffer # NIL);
			(* if fip = NILAdr, fport = 0 then recive from all, otherwise only from this port *)
			REPEAT
				s.Receive(buffer^, 0, MaxUDPPacketLength, timeout, gotfip, gotfport, res);			
			UNTIL res # Ok
			
			(* Should we only receive from fip - if fip # NILAdr !!!! ???? *)
			s.Receive(buffer^, 0, MaxUDPPacketLength, timeout, fip2, fport2, got, res);
			IF res # AosUDP.Ok THEN RETURN res; END;
			size := got;
			(* parse packet *)
			p := AosOSC.ParseOSCPacket(buffer^, size);
			IF p = NIL THEN RETURN ParseError; END;
			RETURN Ok;
		END Recieve;
*)

	
	(* Testprocedures *)
	
	PROCEDURE TestUDPSend*(ptr: PTR): PTR;
		VAR
			socket: OSCUDPClient;
			p, p2: AosOSC.OSCMessage;
			attri: AosOSC.OSCParamInteger;
			attrs: AosOSC.OSCParamString;
			b: AosOSC.OSCBundle;
			tt: AosOSC.OSCTimeTag;
			ip: AosIP.Adr;
			res: LONGINT;
	BEGIN
		ip := AosIP.StrToAdr('192.168.150.1'); AosOut.Int(res, 4);
		NEW(socket, ip, 57110, 57110, res); AosOut.Int(res, 4);
		NEW(p, Utilities.NewString('/abc/def/ghi'));
		NEW(attri, 01234H); p.AddArgument(attri);
		res := socket.Send(p);
		AosOut.Int(res, 4); AosOut.Ln;
		NEW(p2, Utilities.NewString('/xyz'));
		NEW(attrs, Utilities.NewString('<== This is a stirng in a Message ==>'));
		p2.AddArgument(attrs);
		NEW(tt); tt.SetLow(2005,12,26,18,12,15,999);
		NEW(b, tt, NIL, 0); b.AddPacket(p); b.AddPacket(p2);
		res := socket.Send(b);
		socket.Close;		
		AosOut.String('TestUDPSend done'); AosOut.Ln;
		RETURN NIL;
	END TestUDPSend; 

	PROCEDURE TestTCPSend*(ptr: PTR): PTR;
		VAR
			c: OSCTCPClient;
			p, p2: AosOSC.OSCMessage;
			attri: AosOSC.OSCParamInteger;
			attrs: AosOSC.OSCParamString;
			b: AosOSC.OSCBundle;
			tt: AosOSC.OSCTimeTag;
			ip: AosIP.Adr;
			res: LONGINT;
	BEGIN
		ip := AosIP.StrToAdr('192.168.150.1'); AosOut.Int(res, 4);
		NEW(c, ip, 2009, AosTCP.NilPort, res); AosOut.Int(res, 4);
		NEW(p, Utilities.NewString('/abc/def/ghi'));
		NEW(attri, 01234H); p.AddArgument(attri);
		res := c.Send(p);
		AosOut.Int(res, 4); AosOut.Ln;
		NEW(p2, Utilities.NewString('/xyz'));
		NEW(attrs, Utilities.NewString('<== This is a stirng in a Message ==>'));
		p2.AddArgument(attrs);
		NEW(tt); tt.SetLow(2005,12,26,18,12,15,999);
		NEW(b, tt, NIL, 0); b.AddPacket(p); b.AddPacket(p2);
		res := c.Send(b);
		AosOut.String('TestTCPSend done'); AosOut.Ln;
		c.Close;
		RETURN NIL;
	END TestTCPSend; 
	

END AosOSCNet.

AosOSCNet.TestUDPSend ~
AosOSCNet.TestTCPSend ~
AosOSCNet.TestUDPReceive ~
*)