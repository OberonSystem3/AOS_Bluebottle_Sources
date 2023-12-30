MODULE AosPing; (** AUTHOR "mvt"; PURPOSE "Ping"; *)

IMPORT AosICMP, AosDNS, AosIP, AosNet, AosActive, AosKernel, AosCommands, AosModules, AosIO, AosOut;

CONST
	PingSize = 32; (* default packet data size in bytes *)
	MaxPingSize = 65535-20-8; (* maximum packet data size allowed *)
	PingHdrSize = 4; (* sequence number and identifier *)
	Timeout = 1000; (* default echo reply timeout in ms *)

VAR
	running: BOOLEAN; (* is an echo request (ping) currently running? *)
	timer: AosActive.Timer;
	timeout: LONGINT;
	pingSize: LONGINT;
	ms: LONGINT;
	
(** Ping a host. Call: AosPing.Ping host [pingSize] [timeout] ~ *)
	
PROCEDURE Ping*(par: PTR): PTR;
VAR
	i: LONGINT;
	p: AosCommands.Parameters;
	sr: AosIO.StringReader;
	hostname: AosDNS.Name;
	fip: AosIP.Adr;
	res1, res2: LONGINT;
	data: ARRAY PingHdrSize+MaxPingSize OF CHAR;
	
BEGIN {EXCLUSIVE}
	AWAIT(~running);
	p := par(AosCommands.Parameters);
	NEW(sr, LEN(p.str^));
	sr.Set(p.str^);
	sr.SkipWhitespace;
	
	sr.String(hostname); sr.SkipWhitespace;
	sr.Int(pingSize, FALSE); sr.SkipWhitespace;
	sr.Int(timeout, FALSE); 
		
	IF pingSize = 0 THEN pingSize := PingSize END;
	IF timeout = 0 THEN timeout := Timeout END;
	
	IF pingSize > MaxPingSize THEN
		pingSize := MaxPingSize;
	END;
	
	IF hostname # "" THEN
		AosOut.String("AosPing: Resolving host name: "); AosOut.String(hostname); AosOut.Ln;
		AosDNS.HostByName(hostname, fip, res1);
		IF res1 = AosDNS.Ok THEN
			(* Install Receivers for IPv6 and IPv6 *)
			AosICMP.InstallReceiver(AosICMP.TypeEchoReplyv4, GetReply, res1);
			AosICMP.InstallReceiver(AosICMP.TypeEchoReplyv6, GetReply, res2);
			
			IF (res1 = AosICMP.Ok) & (res2 = AosICMP.Ok) THEN
				FOR i := 0 TO PingHdrSize-1 DO
					data[i] := 0X; (* set sequence number and identifier to zero *)
				END;
				
				FOR i := 0 TO pingSize-1 DO
					data[PingHdrSize+i] := CHR(i MOD 256);
				END;
				AosOut.String("AosPing: Pinging "); AosIP.OutAdr(fip); AosOut.String(" with ");
				AosOut.Int(pingSize, 0); AosOut.String(" bytes..."); AosOut.Ln;
				IF fip.usedProtocol = AosIP.IPv4 THEN
					AosICMP.Send(NIL, fip, data, 0, PingHdrSize+pingSize, AosICMP.TypeEchoRequestv4, 0, AosIP.MaxTTL);
				ELSIF fip.usedProtocol = AosIP.IPv6 THEN
					AosICMP.Send(NIL, fip, data, 0, PingHdrSize+pingSize, AosICMP.TypeEchoRequestv6, 0, AosIP.MaxTTL);
				END;
				
				AosActive.SetTimeout(timer, TimeoutHandler, timeout);
				ms := AosKernel.GetTimer();
				running := TRUE
			ELSE
				AosOut.String("AosPing: Couldn't install receiver in AosICMP, probably reserved by another application."); AosOut.Ln
			END;
		ELSE
			AosOut.String("AosPing: Couldn't resolve host name: "); AosOut.String(hostname); AosOut.Ln
		END;
	ELSE
		AosOut.String("AosPing: Parameter error: No hostname defined!"); AosOut.Ln
	END;
	RETURN NIL
END Ping;

PROCEDURE TimeoutHandler();
VAR res: LONGINT;
BEGIN {EXCLUSIVE}
	IF running THEN
		AosOut.String("AosPing: Timeout! No reply received within "); AosOut.Int(timeout, 0);
		AosOut.String(" ms."); AosOut.Ln;
		running := FALSE;
		AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv4, res);
		AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv6, res);
	ELSE
		(* occurred during GetReply *)
	END;
END TimeoutHandler;

PROCEDURE GetReply(int: AosIP.Interface; type, code: LONGINT; fip, lip: AosIP.Adr; buffer: AosNet.Buffer);
VAR res: LONGINT;
BEGIN {EXCLUSIVE}
	IF running THEN
		AosOut.String("AosPing: Successful! Reply received within "); AosOut.Int(AosKernel.GetTimer() - ms, 0);
		AosOut.String(" ms."); AosOut.Ln;
		running := FALSE;
		AosActive.CancelTimeout(timer);
		AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv4, res);
		AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv6, res);
	ELSE
		(* timeout already occurred *)
	END;
	AosNet.ReturnBuffer(buffer)
END GetReply;

PROCEDURE Cleanup();
VAR res: LONGINT;
BEGIN {EXCLUSIVE}
	IF running THEN
		running := FALSE;
		AosActive.CancelTimeout(timer);
		AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv4, res);
		AosICMP.RemoveReceiver(AosICMP.TypeEchoReplyv6, res);
	END
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	NEW(timer)
END AosPing.

(*
Usage: AosPing.Ping host [pingSize] [timeout] 

"pingSize" is the size of the ping packet data in bytes.
"timeout" is the echo reply timeout in ms.

Aos.Call AosPing.Ping 127.0.0.1~
Aos.Call AosPing.Ping 10.0.0.1 1024~
Aos.Call AosPing.Ping 129.132.98.12~
Aos.Call AosPing.Ping 129.132.250.220~
Aos.Call AosPing.Ping www.ethz.ch 128 100~
System.Free AosPing~
*)
