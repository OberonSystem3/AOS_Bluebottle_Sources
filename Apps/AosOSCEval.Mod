MODULE AosOSCEval;

IMPORT AosOSC, AosOSCNet, AosOSCService, AosOSCRegistry, AosIP, AosUDP, AosTCP, AosOut, Utilities := AosOSCUtilities, AosTCPServices,
AosNet;

CONST

	ServerIP = "129.132.134.164";
	ServerPort = 1234;

VAR
	registry: AosOSCRegistry.OSCRegistry;
	sampleservice: AosOSCService.OSCService;
	udps: AosOSCNet.OSCUDPServer;
	tcps: AosOSCNet.OSCTCPServer;
	
	ackmessage: AosOSC.OSCMessage;
	nackmessage: AosOSC.OSCMessage;
	udpclient: AosOSCNet.OSCUDPClient;
	tcpclient: AosOSCNet.OSCTCPClient;
	
TYPE
	udpread = OBJECT
		VAR
			stopping: BOOLEAN;
			s: AosUDP.Socket;
			buffer: POINTER TO ARRAY OF CHAR;
			receivefip: AosIP.Adr;
			receivefport: LONGINT;
			got, res: LONGINT;
			fip: AosIP.Adr;
		PROCEDURE &Init();
		VAR
			res: LONGINT;
		BEGIN
			stopping := FALSE;
			NEW(buffer, 10000H);
			NEW(s, ServerPort, res);
			IF(res # AosUDP.Ok) THEN stopping := TRUE; END;
			fip := AosIP.StrToAdr(ServerIP);
		END Init;
		PROCEDURE Stop;
		BEGIN 
			stopping := TRUE;
		END Stop;
			
	BEGIN {ACTIVE}
		WHILE ~ stopping DO
			s.Receive(buffer^, 0, LEN(buffer), 1000, receivefip, receivefport, got, res);
			IF res = AosUDP.Ok THEN
				s.Send(fip, receivefport, buffer^, 0, 8, res); 
			END;
		END;	
		s.Close;
	END udpread;
	
	tcpagent = OBJECT(AosTCPServices.Agent);
		VAR
			newpacket: AosOSC.OSCPacket;
			res, len: LONGINT;
			buffer: POINTER TO ARRAY OF CHAR;
			sizebuf: ARRAY 4 OF CHAR;
			packetsize: LONGINT;
			
		PROCEDURE &StartOSCAgent(c: AosTCP.Connection; s: AosTCPServices.Service);
		BEGIN
			Start(c,s);
		END StartOSCAgent;
		
	BEGIN { ACTIVE }
		client.Receive(sizebuf, 0, LEN(sizebuf), 4, len, res);
		IF res # AosTCP.Ok THEN Terminate; RETURN; END;
		ASSERT(len = 4);
		packetsize := AosNet.GetNet4(sizebuf, 0);
		(* allocate new buffer *)
		IF (packetsize < 0) OR (packetsize > 10000H) THEN
			AosOut.String('AosOSCTCPAgent: Packet too big: '); AosOut.Hex(packetsize, 10); AosOut.Ln;
			Terminate; RETURN;
		END;
		NEW(buffer, packetsize);
		client.Receive(buffer^, 0, packetsize, packetsize, len, res);
		IF res # AosTCP.Ok THEN Terminate; RETURN; END;
		client.Send(buffer^, 0, 8, FALSE, res);
		Terminate;
	END tcpagent;
	
	tcpread = OBJECT
		VAR
			tcpservice: AosTCPServices.Service;
			
		(* starts the server: registers the OSCService s and creates the AosTCPServices.Service, which listens for connections *)
		PROCEDURE &InitTCPServer();
		VAR
			res: LONGINT;
		BEGIN
			NEW(tcpservice, ServerPort, newAgent, res);
		END InitTCPServer;
	
		(* This function is called by tcpservice to create a new agent *)
		PROCEDURE newAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
			VAR agent: tcpagent;
		BEGIN
			NEW(agent, c, s); 
			RETURN agent;
		END newAgent;
		
		(* Stops the OSCTCPServer. Closes the listening socket and all established connections *)
		PROCEDURE Stop;
		BEGIN
			tcpservice.Stop;
		END Stop;
		
	END tcpread;

	
VAR
		udpr: udpread;
		tcpr: tcpread;

	
PROCEDURE StartUDPRead*(ptr: PTR): PTR;
BEGIN
	NEW(udpr);
	RETURN NIL;
END StartUDPRead;

PROCEDURE StopUDPRead*(ptr: PTR): PTR;
BEGIN
	IF udpr # NIL THEN udpr.Stop; udpr := NIL; END;
	RETURN NIL;
END StopUDPRead;

PROCEDURE StartTCPRead*(ptr: PTR): PTR;
BEGIN
	NEW(tcpr);
	RETURN NIL;
END StartTCPRead;

PROCEDURE StopTCPRead*(ptr: PTR): PTR;
BEGIN
	IF udpr # NIL THEN tcpr.Stop; tcpr := NIL; END;
	RETURN NIL;
END StopTCPRead;
	
PROCEDURE MessageTest1(m: AosOSC.OSCMessage);
VAR
	res: LONGINT;
BEGIN
	(* This Test should receive an empty OSC message *)
	IF (m.argumentcount = 0) & (~ m.noTypeTagString) THEN
		AosOut.String('MessageTest1: success'); AosOut.Ln;
		res := m.Return(ackmessage);
		RETURN;
	END;
	res := m.Return(nackmessage);
	AosOut.String('MessageTest1: failed'); AosOut.Ln;
END MessageTest1;

PROCEDURE SendMsg1*(ptr: PTR): PTR;
VAR
	m: AosOSC.OSCMessage;
	res: LONGINT;
BEGIN
	NEW(m, Utilities.NewString('/tests/M1'));
	IF udpclient # NIL THEN res := udpclient.Send(m); END;
	IF tcpclient # NIL THEN res := tcpclient.Send(m); END;
	AosOut.String('Sent message1'); AosOut.Ln;
	RETURN NIL;
END SendMsg1;

PROCEDURE MessageTest2(m: AosOSC.OSCMessage);
VAR
	res: LONGINT;
	param: AosOSC.OSCParamObject;
BEGIN
	(* This Test should receive an OSC message with one Integer (47) *)
	IF (m.argumentcount = 1) & (~ m.noTypeTagString) THEN
		IF m.arguments[0] IS AosOSC.OSCParamInteger THEN
			param := m.arguments[0];
			WITH param: AosOSC.OSCParamInteger DO
				IF param.integer = 47 THEN
					AosOut.String('MessageTest2: success'); AosOut.Ln;
					res := m.Return(ackmessage);
					RETURN;
				END;
			END;
		END;
	END;
	res := m.Return(nackmessage);
	AosOut.String('MessageTest2: failed'); AosOut.Ln;
END MessageTest2;

PROCEDURE SendMsg2*(ptr: PTR): PTR;
VAR
	m: AosOSC.OSCMessage;
	i: AosOSC.OSCParamInteger;
	res: LONGINT;
BEGIN
	NEW(m, Utilities.NewString('/tests/M2'));
	NEW(i, 47); m.AddArgument(i);
	IF udpclient # NIL THEN res := udpclient.Send(m); END;
	IF tcpclient # NIL THEN res := tcpclient.Send(m); END;
	AosOut.String('Sent message2'); AosOut.Ln;
	RETURN NIL;
END SendMsg2;

PROCEDURE MessageTest3(m: AosOSC.OSCMessage);
VAR
	res: LONGINT;
	param: AosOSC.OSCParamObject;
BEGIN
	(* This Test should receive an OSC message with one Float (8.25) *)
	IF (m.argumentcount = 1) & (~ m.noTypeTagString) THEN
		IF m.arguments[0] IS AosOSC.OSCParamFloat THEN
			param := m.arguments[0];
			WITH param: AosOSC.OSCParamFloat DO
				IF param.float = 8.25 THEN
					AosOut.String('MessageTest3: success'); AosOut.Ln;
					res := m.Return(ackmessage);
					RETURN;
				END;
			END;
		END;
	END;
	res := m.Return(nackmessage);
	AosOut.String('MessageTest3: failed'); AosOut.Ln;
END MessageTest3;

PROCEDURE SendMsg3*(ptr: PTR): PTR;
VAR
	m: AosOSC.OSCMessage;
	p: AosOSC.OSCParamFloat;
	res: LONGINT;
BEGIN
	NEW(m, Utilities.NewString('/tests/M3'));
	NEW(p, 8.25); m.AddArgument(p);
	IF udpclient # NIL THEN res := udpclient.Send(m); END;
	IF tcpclient # NIL THEN res := tcpclient.Send(m); END;
	AosOut.String('Sent message3'); AosOut.Ln;
	RETURN NIL;
END SendMsg3;

PROCEDURE MessageTest4(m: AosOSC.OSCMessage);
VAR
	res: LONGINT;
	param: AosOSC.OSCParamObject;
	ok: BOOLEAN; i: LONGINT;
BEGIN
	(* This Test should receive an OSC message with one Blob (01 02 03 ... 20) *)
	IF (m.argumentcount = 1) & (~ m.noTypeTagString) THEN
		IF m.arguments[0] IS AosOSC.OSCParamBlob THEN
			param := m.arguments[0];
			WITH param: AosOSC.OSCParamBlob DO
				IF param.size = 32 THEN
					ok := TRUE;
					FOR i:=0 TO 31 DO
						IF param.blob[i] # CHR(i+1) THEN ok := FALSE; END;
					END;
					IF ok THEN
						AosOut.String('MessageTest4: success'); AosOut.Ln;
						res := m.Return(ackmessage);
						RETURN;
					END;
				END;
			END;
		END;
	END;
	res := m.Return(nackmessage);
	AosOut.String('MessageTest5: failed'); AosOut.Ln;
END MessageTest4;

PROCEDURE SendMsg4*(ptr: PTR): PTR;
VAR
	m: AosOSC.OSCMessage;
	p: AosOSC.OSCParamBlob;
	data: AosOSC.Blob; i: LONGINT;
	res: LONGINT;
BEGIN
	NEW(data, 32);
	FOR i:=0 TO 31 DO data[i] := CHR(i+1); END;
	NEW(m, Utilities.NewString('/tests/M4'));
	NEW(p, data, 32); m.AddArgument(p);
	IF udpclient # NIL THEN res := udpclient.Send(m); END;
	IF tcpclient # NIL THEN res := tcpclient.Send(m); END;
	AosOut.String('Sent message4'); AosOut.Ln;
	RETURN NIL;
END SendMsg4;


PROCEDURE MessageTest5(m: AosOSC.OSCMessage);
VAR
	res: LONGINT;
	param: AosOSC.OSCParamObject;
BEGIN
	(* This Test should receive an OSC message with one String (TEST5)^5 *)
	IF (m.argumentcount = 1) & (~ m.noTypeTagString) THEN
		IF m.arguments[0] IS AosOSC.OSCParamString THEN
			param := m.arguments[0];
			WITH param: AosOSC.OSCParamString DO
				IF param.string^ = 'TEST5TEST5TEST5TEST5TEST5' THEN
					AosOut.String('MessageTest5: success'); AosOut.Ln;
					res := m.Return(ackmessage);
					RETURN;
				END;
			END;
		END;
	END;
	res := m.Return(nackmessage);
	AosOut.String('MessageTest5: failed'); AosOut.Ln;
END MessageTest5;

PROCEDURE SendMsg5*(ptr: PTR): PTR;
VAR
	m: AosOSC.OSCMessage;
	p: AosOSC.OSCParamString;
	res: LONGINT;
BEGIN
	NEW(m, Utilities.NewString('/tests/M5'));
	NEW(p, Utilities.NewString('TEST5TEST5TEST5TEST5TEST5')); m.AddArgument(p);
	m.dump(0); AosOut.Ln;
	IF udpclient # NIL THEN res := udpclient.Send(m); END;
	IF tcpclient # NIL THEN res := tcpclient.Send(m); END;
	AosOut.String('Sent message5'); AosOut.Ln;
	RETURN NIL;
END SendMsg5;

PROCEDURE SendBundle1*(ptr: PTR): PTR;
VAR
	b: AosOSC.OSCBundle;
	tt: AosOSC.OSCTimeTag;
	res: LONGINT;
BEGIN
	NEW(tt); tt.SetImmediately; 
	NEW(b, tt, NIL, 0);
	IF udpclient # NIL THEN res := udpclient.Send(b); END;
	IF tcpclient # NIL THEN res := tcpclient.Send(b); END;
	AosOut.String('Sent bundle1'); AosOut.Ln;
	RETURN NIL;
END SendBundle1;

PROCEDURE SendBundle2*(ptr: PTR): PTR;
VAR
	m: AosOSC.OSCMessage;
	b: AosOSC.OSCBundle;
	tt: AosOSC.OSCTimeTag;
	i: AosOSC.OSCParamInteger;
	res: LONGINT;
BEGIN
	NEW(tt); tt.SetImmediately;
	NEW(m, Utilities.NewString('/tests/M2'));
	NEW(i, 47); m.AddArgument(i);
	NEW(b, tt, NIL, 0); b.AddPacket(m);
	IF udpclient # NIL THEN res := udpclient.Send(b); END;
	IF tcpclient # NIL THEN res := tcpclient.Send(b); END;
	AosOut.String('Sent bundle2'); AosOut.Ln;
	RETURN NIL;
END SendBundle2;

PROCEDURE SendBundle3*(ptr: PTR): PTR;
VAR
	m: AosOSC.OSCMessage;
	b: AosOSC.OSCBundle;
	tt: AosOSC.OSCTimeTag;
	i: AosOSC.OSCParamInteger;
	res: LONGINT;
BEGIN
	NEW(tt); tt.SetImmediately;
	NEW(m, Utilities.NewString('/tests/M2'));
	NEW(i, 47); m.AddArgument(i);
	NEW(b, tt, NIL, 0);
	FOR res:=0 TO 49 DO
		 b.AddPacket(m);
	END;
	IF udpclient # NIL THEN res := udpclient.Send(b); END;
	IF tcpclient # NIL THEN res := tcpclient.Send(b); END;
	AosOut.String('Sent bundle3'); AosOut.Ln;
	RETURN NIL;
END SendBundle3;

PROCEDURE Echo(m: AosOSC.OSCMessage);
VAR
	res: LONGINT;
BEGIN
	IF ~ m.noTypeTagString THEN
		res := m.Return(ackmessage);
	ELSE
		res := m.Return(nackmessage);
	END;
END Echo;

PROCEDURE Ret(m: AosOSC.OSCMessage);
VAR
	res: LONGINT;
BEGIN
	IF ~ m.noTypeTagString THEN
		res := m.Return(m);
	ELSE
		res := m.Return(nackmessage);
	END;
END Ret;


PROCEDURE StartEvalService*(ptr: PTR): PTR;
VAR
	res: LONGINT;
BEGIN
	NEW(registry);
	registry.AddMethod(Utilities.NewString('/tests/M1'), MessageTest1);
	registry.AddMethod(Utilities.NewString('/tests/M2'), MessageTest2);
	registry.AddMethod(Utilities.NewString('/tests/M3'), MessageTest3);
	registry.AddMethod(Utilities.NewString('/tests/M4'), MessageTest4);
	registry.AddMethod(Utilities.NewString('/tests/M5'), MessageTest5);
	registry.AddMethod(Utilities.NewString('/echo'), Echo);
	registry.AddMethod(Utilities.NewString('/ret'), Ret);
	NEW(sampleservice, registry);
	NEW(tcps, sampleservice, ServerPort, res);
	NEW(udps, sampleservice, ServerPort, res);
	RETURN NIL;
END StartEvalService;

PROCEDURE StopEvalService*(ptr: PTR): PTR;
BEGIN
	AosOut.String('Stopping OSCTCP ');
	tcps.Stop;
	AosOut.String('Stopping OSCUDP ');
	udps.Stop;
	AosOut.String('Stopping OSCService ');
	sampleservice.Stop;
	AosOut.String(' done'); AosOut.Ln;
	RETURN NIL;
END StopEvalService;

PROCEDURE StartUDPClient*(ptr: PTR): PTR;
VAR
	res: LONGINT;
BEGIN
	NEW(udpclient, AosIP.StrToAdr(ServerIP), ServerPort, AosUDP.NilPort, res);
	IF res # AosUDP.Ok THEN
		AosOut.String('creation failed'); AosOut.Ln;
		udpclient := NIL;
		RETURN NIL;
	END;
	AosOut.String('Started UDP client'); AosOut.Ln;
	RETURN NIL;
END StartUDPClient;

PROCEDURE StopUDPClient*(ptr: PTR): PTR;
BEGIN
	IF udpclient # NIL THEN
		udpclient.Close;
		udpclient := NIL;
		AosOut.String('Stopped UDP client'); AosOut.Ln;
	END;
	RETURN NIL;
END StopUDPClient;

PROCEDURE StartTCPClient*(ptr: PTR): PTR;
VAR
	res: LONGINT;
BEGIN
	NEW(tcpclient, AosIP.StrToAdr(ServerIP), ServerPort, AosTCP.NilPort, res);
	IF res # AosTCP.Ok THEN
		AosOut.String('creation failed'); AosOut.Ln;
		udpclient := NIL;
		RETURN NIL;
	END;
	AosOut.String('Started TCP client'); AosOut.Ln;
	RETURN NIL;
END StartTCPClient;

PROCEDURE StopTCPClient*(ptr: PTR): PTR;
BEGIN
	IF tcpclient # NIL THEN
		tcpclient.Close;
		tcpclient := NIL;
		AosOut.String('Stopped TCP client'); AosOut.Ln;
	END;
	RETURN NIL;
END StopTCPClient;

BEGIN
	NEW(ackmessage, Utilities.NewString('/OK'));
	NEW(nackmessage, Utilities.NewString('/NOK'));
END AosOSCEval.

PC0.Compile AosOSCUtilities.Mod AosOSC.Mod AosOSCRegistry.Mod AosOSCQueue.Mod AosOSCService.Mod AosOSCNet.Mod AosOSCEval.Mod ~
S.Free AosOSCEval AosOSCTest AosOSCNet AosOSCService AosOSCQueue AosOSCRegistry AosOSC AosOSCUtilities ~

AosOSCEval.StartEvalService ~
AosOSCEval.StopEvalService ~

AosOSCEval.StartUDPClient ~
AosOSCEval.StopUDPClient ~

AosOSCEval.StartTCPClient ~
AosOSCEval.StopTCPClient ~

AosOSCEval.SendMsg1 ~
AosOSCEval.SendMsg2 ~
AosOSCEval.SendMsg3 ~
AosOSCEval.SendMsg4 ~
AosOSCEval.SendMsg5 ~
AosOSCEval.SendBundle1 ~
AosOSCEval.SendBundle2 ~
AosOSCEval.SendBundle3 ~

AosOSCEval.StartUDPRead ~
AosOSCEval.StopUDPRead ~

AosOSCEval.StartTCPRead ~
AosOSCEval.StopTCPRead ~