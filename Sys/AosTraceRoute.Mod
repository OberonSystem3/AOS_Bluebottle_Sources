MODULE AosTraceRoute; (** AUTHOR "mvt"; PURPOSE "TraceRoute"; *)

IMPORT AosICMP, AosDNS, AosIP, AosNet, AosActive, AosKernel, AosCommands, AosModules, AosIO, AosOut;

CONST
	PingSize = 32; (* default packet data size in bytes *)
	MaxPingSize = 65535-20-8; (* maximum packet data size allowed *)
	PingHdrSize = 4; (* sequence number and identifier *)
	Timeout = 1000; (* default echo reply timeout in ms *)
	DEBUG = FALSE;

VAR
	running: BOOLEAN; (* is traceroute currently running? *)
	timer: AosActive.Timer;
	timeoutMS: LONGINT; (* timeout in ms *)
	pingSize: LONGINT; (* ping size in bytes *)
	TTL: LONGINT; (* time-to-live for outgoing packets *)
	fip: AosIP.Adr; (* foreign IP address *)
	timeout: BOOLEAN; (* timeout occurred *)
	replyIP: AosIP.Adr; (* If not AosIP.NilAdr, a packet was received with this foreign IP address *)
	replyExceed: BOOLEAN; (* TRUE if packet is an "exceeded" packet, FALSE if it is an "echo reply" packet *)
	
(** Run TraceRoute. Call: AosTraceRoute.TraceRoute host [pingSize] [timeout] ~ *)
	
PROCEDURE TraceRoute*(par: PTR): PTR;
VAR
	p: AosCommands.Parameters;
	sr: AosIO.StringReader;
	hostname: AosDNS.Name;
	res, sent, now: LONGINT;
BEGIN
	BEGIN {EXCLUSIVE}
		AWAIT(~running);
		running := TRUE;
	END;
	p := par(AosCommands.Parameters);
	NEW(sr, LEN(p.str^));
	sr.Set(p.str^);
	sr.SkipWhitespace;
	
	sr.String(hostname); sr.SkipWhitespace;
	sr.Int(pingSize, FALSE); sr.SkipWhitespace;
	sr.Int(timeoutMS, FALSE); 
		
	IF pingSize = 0 THEN pingSize := PingSize END;
	IF timeoutMS = 0 THEN timeoutMS := Timeout END;
	
	IF pingSize > MaxPingSize THEN
		pingSize := MaxPingSize;
	END;
	
	IF hostname # "" THEN
		AosOut.String("AosTraceRoute: Resolving host name: "); AosOut.String(hostname); AosOut.Ln;
		AosDNS.HostByName(hostname, fip, res);
		IF res = AosDNS.Ok THEN
			AosICMP.InstallReceiver(AosICMP.TypeEchoReplyv4, GetReply, res);
			AosICMP.InstallReceiver(AosICMP.TypeEchoReplyv6, GetReply, res);
			IF res = AosICMP.Ok THEN
				AosICMP.InstallReceiver(AosICMP.TypeTimeExceededv4, GetReply, res);
				AosICMP.InstallReceiver(AosICMP.TypeTimeExceededv6, GetReply, res);
			END;
			IF res = AosICMP.Ok THEN
				AosOut.String("AosTraceRoute: Starting traceroute for host "); AosIP.OutAdr(fip); AosOut.String(" with ");
				AosOut.Int(pingSize, 0); AosOut.String(" bytes..."); AosOut.Ln;
				TTL := 1;
				LOOP
					BEGIN {EXCLUSIVE}
						timeout := FALSE;
						replyIP := AosIP.NilAdr;
						sent := AosKernel.GetTimer();
						SendEchoRequest();
						AWAIT(timeout OR (~AosIP.IsNilAdr(replyIP)));
					END;
					IF timeout THEN
						AosOut.String("AosTraceRoute: ["); AosOut.Int(TTL, 0); AosOut.String("] Timeout! No reply received within ");
						AosOut.Int(timeoutMS, 0); AosOut.String("ms."); AosOut.Ln;
						AosOut.String("AosTraceRoute: Finished."); AosOut.Ln;
						AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv4, res);
						AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv6, res);
						AosICMP.RemoveReceiver(AosICMP.TypeTimeExceededv4, res);
						AosICMP.RemoveReceiver(AosICMP.TypeTimeExceededv6, res);
						EXIT;
					ELSE
						now := AosKernel.GetTimer();
						AosActive.CancelTimeout(timer);
						AosOut.String("AosTraceRoute: ["); AosOut.Int(TTL, 0); AosOut.String("] ");
						AosOut.Int(now - sent, 0); AosOut.String("ms, ");
						AosDNS.HostByNumber(replyIP, hostname, res);
						IF res = AosDNS.Ok THEN
							AosOut.String(hostname); AosOut.String(" ["); AosIP.OutAdr(replyIP); AosOut.String("]");
						ELSE
							AosIP.OutAdr(replyIP);
						END;
						AosOut.Ln;
						IF replyExceed THEN
							INC(TTL);
							IF TTL > 255 THEN
								AosOut.String("AosTraceRoute: TTL of 255 reached. Aborted."); AosOut.Ln;
								EXIT;
							END;
						ELSE
							AosOut.String("AosTraceRoute: Finished."); AosOut.Ln;
							AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv4, res);
							AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv6, res);
							AosICMP.RemoveReceiver(AosICMP.TypeTimeExceededv4, res);
							AosICMP.RemoveReceiver(AosICMP.TypeTimeExceededv6, res);
							EXIT;
						END;
					END;
				END;
			ELSE
				AosOut.String("AosTraceRoute: Couldn't install receiver in AosICMP, probably reserved by another application!"); AosOut.Ln
			END;
		ELSE
			AosOut.String("AosTraceRoute: Couldn't resolve host name: "); AosOut.String(hostname); AosOut.Ln
		END;
	ELSE
		AosOut.String("AosTraceRoute: Parameter error: No hostname defined!"); AosOut.Ln
	END;
	BEGIN {EXCLUSIVE}
		ASSERT(running);
		running := FALSE;
	END;
	RETURN NIL
END TraceRoute;

PROCEDURE SendEchoRequest();
VAR
	i: LONGINT;
	data: ARRAY PingHdrSize+MaxPingSize OF CHAR;
BEGIN
	FOR i := 0 TO PingHdrSize-1 DO
		data[i] := 0X; (* set sequence number and identifier to zero *)
	END;
	FOR i := 0 TO pingSize-1 DO
		data[PingHdrSize+i] := CHR(i MOD 256);
	END;
	IF fip.usedProtocol = AosIP.IPv4 THEN
		AosICMP.Send(NIL, fip, data, 0, PingHdrSize+pingSize, AosICMP.TypeEchoRequestv4, 0, TTL);
	ELSIF fip.usedProtocol = AosIP.IPv6 THEN
		AosICMP.Send(NIL, fip, data, 0, PingHdrSize + pingSize, AosICMP.TypeEchoRequestv6, 0, TTL);
	ELSE
		IF DEBUG THEN
			ASSERT(TRUE);
		END;
	END;
	AosActive.SetTimeout(timer, TimeoutHandler, timeoutMS);
END SendEchoRequest;

PROCEDURE TimeoutHandler();
BEGIN {EXCLUSIVE}
	timeout := TRUE;
END TimeoutHandler;

PROCEDURE GetReply(int: AosIP.Interface; type, code: LONGINT; fip, lip: AosIP.Adr; buffer: AosNet.Buffer);
BEGIN {EXCLUSIVE}
	AosActive.CancelTimeout(timer);
	IF (type = AosICMP.TypeTimeExceededv4) OR (type = AosICMP.TypeTimeExceededv6) THEN
		replyIP := fip;
		replyExceed := TRUE;
	ELSIF (type = AosICMP.TypeEchoReplyv4) OR (type = AosICMP.TypeEchoReplyv6) THEN
		replyIP := fip;
		replyExceed := FALSE;
	ELSE
		(* ignore *)
	END;
END GetReply;

BEGIN
	NEW(timer)
END AosTraceRoute.

(*
Usage: AosTraceRoute.TraceRoute host [pingSize] [timeout] 

"pingSize" is the size of the ping packet data in bytes, used by traceroute.
"timeout" is the echo reply timeout in ms.

Aos.Call AosTraceRoute.TraceRoute 127.0.0.1~
Aos.Call AosTraceRoute.TraceRoute 10.0.0.1 1024~
Aos.Call AosTraceRoute.TraceRoute www.google.ch 128 500~
System.Free AosTraceRoute~
*)
