(* Copyright 2005-2006, Markus Heule, ETH Zurich *)

MODULE AosOSCExample;  (** AUTHOR "heulemar"; PURPOSE "OpenSoundControl: sampleprogram"; *)

(*
	This module contains a sample oscservice to illustrate the usage of the OSC framework.
	
	1.) (if needed) Compile the whole framework:

	PC0.Compile AosOSCUtilities.Mod AosOSC.Mod AosOSCRegistry.Mod AosOSCQueue.Mod AosOSCService.Mod AosOSCNet.Mod AosOSCExample.Mod ~
	
	2.) Start the service with:
	
	AosOSCExample.StartSampleService ~
	
	3.) Stop the sample service with:

	AosOSCExample.StopSampleService ~
	
	4.) (if needed) Unload the modules from the framework.
	
	S.Free AosOSCExample AosOSCNet AosOSCService AosOSCQueue AosOSCRegistry AosOSC AosOSCUtilities ~
	
*)

IMPORT AosOSC, AosOSCNet, AosOSCService, AosOSCRegistry, AosIP, AosUDP, AosOut, Utilities := AosOSCUtilities;

VAR
	registry: AosOSCRegistry.OSCRegistry;
	sampleservice: AosOSCService.OSCService;
	udps: AosOSCNet.OSCUDPServer;
	tcps: AosOSCNet.OSCTCPServer;
	

(* client procedure, which sends the received packet back to the sender *)
PROCEDURE EchoPacket(p: AosOSC.OSCPacket);
VAR
	res: LONGINT;
BEGIN
	res := p.Return(p);
END EchoPacket;

(* client procedure, which dumps the received packet *)
PROCEDURE DumpPacket(p: AosOSC.OSCMessage);
VAR
	i: LONGINT;
	param: AosOSC.OSCParamObject;
BEGIN
	AosOut.String('Dumping whole packet: '); AosOut.Ln;
	p.dump(1);
	(* this shows how to access parameters *)
	AosOut.String('Dumping each parameter separatly:'); AosOut.Ln;
	FOR i:=0 TO p.argumentcount -1 DO
		param := p.arguments[i];
		IF param IS AosOSC.OSCParamInteger THEN
			WITH param: AosOSC.OSCParamInteger DO
				AosOut.String('Int: '); AosOut.Int(param.integer, 10); 
				AosOut.String('('); AosOut.Hex(param.integer, 1); AosOut.String(')'); AosOut.Ln;
			END;
		END;
	END;
	AosOut.String('Dumping packet done'); AosOut.Ln;
END DumpPacket;

PROCEDURE StartSampleService*(ptr: PTR): PTR;
VAR
	res: LONGINT;
BEGIN
	NEW(registry);	(* creates a new registry *)
	registry.AddMethod(Utilities.NewString('/dumpme'), DumpPacket); (* register a new procedure *)
	registry.AddMethod(Utilities.NewString('/echome'), EchoPacket); (* register another one *)
	NEW(sampleservice, registry); (* creates a new oscservice *)
	NEW(tcps, sampleservice, 57110, res); (* listens on TCP port 57110 for connections from the network *)
	NEW(udps, sampleservice, 57110, res); (* listens on UDP port 57110 for packet from the network *)
	RETURN NIL;
END StartSampleService;

PROCEDURE StopSampleService*(ptr: PTR): PTR;
BEGIN
	AosOut.String('Stopping OSCTCP ');
	tcps.Stop;
	AosOut.String('Stopping OSCUDP ');
	udps.Stop;
	AosOut.String('Stopping OSCService ');
	sampleservice.Stop;
	AosOut.String(' done'); AosOut.Ln;
	RETURN NIL;
END StopSampleService;

PROCEDURE SampleClient*(ptr: PTR): PTR;
VAR
	msg: AosOSC.OSCMessage;
	i: AosOSC.OSCParamInteger;
	f: AosOSC.OSCParamFloat;
	udp: AosOSCNet.OSCUDPClient;
	fip: AosIP.Adr;
	fport: LONGINT;
	res: LONGINT;
	b: AosOSC.OSCBundle;
	tt: AosOSC.OSCTimeTag;
BEGIN
	NEW(msg, Utilities.NewString('/some/method'));
	NEW(i, 4);
	NEW(f, 8.25);
	msg.AddArgument(i);
	msg.AddArgument(f);
	NEW(tt); tt.Set(AosOSC.TTGetSecondsNow(), 0);
	NEW(b, tt, NIL, 0);
	fip := AosIP.StrToAdr('192.168.150.1');
	fport := 1234;
	NEW(udp, fip, fport, AosUDP.NilPort, res);
	IF res # AosUDP.Ok THEN
		AosOut.String('SampleClient: Error creating UDP client');
		RETURN NIL;
	END;
	AosOut.String('SampleClient: Sending message now');
	res := udp.Send(msg);
	res := udp.Send(b);
	AosOut.String(' done'); AosOut.Ln;
	udp.Close;
	RETURN NIL;
END SampleClient;

END AosOSCExample.

PC0.Compile AosOSCUtilities.Mod AosOSC.Mod AosOSCRegistry.Mod AosOSCQueue.Mod AosOSCService.Mod AosOSCNet.Mod AosOSCExample.Mod ~
S.Free AosOSCExample AosOSCNet AosOSCService AosOSCQueue AosOSCRegistry AosOSC AosOSCUtilities ~

AosOSCExample.StartSampleService ~
AosOSCExample.StopSampleService ~

AosOSCExample.SampleClient ~