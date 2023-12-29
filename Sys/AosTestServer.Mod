(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosTestServer; (** AUTHOR "pjm"; PURPOSE "TCP test server (echo, discard, chargen, daytime)"; *)

(* TCP Echo (RFC 862), Discard (RFC 863), Daytime (RFC 867) and Chargen (RFC 864) services for Aos. *)

IMPORT AosModules, AosOut, AosTCP, AosTCPServices, AosIO, AosClock;

CONST
	EchoPort = 7;
	EchoBufSize = 4096;
	
	DiscardPort = 9;
	DiscardBufSize = 4096;
	
	ChargenPort = 19;
	ChargenFirstChar = 32; ChargenNumChars = 95;
	ChargenLineLength = 72; ChargenLineSize = 74;
	CharGenBufSize = ChargenLineSize * ChargenNumChars;
	
	DayTimePort = 13;
	
	Ok = AosTCP.Ok;
	
	Trace = TRUE;

TYPE
	DiscardAgent = OBJECT (AosTCPServices.Agent)
		VAR len, res: LONGINT; buf: ARRAY DiscardBufSize OF CHAR;
		
	BEGIN {ACTIVE}
		REPEAT
			client.Receive(buf, 0, LEN(buf), LEN(buf), len, res)
		UNTIL res # Ok;
		IF Trace THEN
			AosOut.Enter; AosOut.String("Discard result "); AosOut.Int(res, 1); AosOut.Exit
		END;
		Terminate
	END DiscardAgent;

TYPE
	EchoAgent = OBJECT (AosTCPServices.Agent)
		VAR len, res: LONGINT; buf: ARRAY EchoBufSize OF CHAR;
		
	BEGIN {ACTIVE}
		LOOP
			client.Receive(buf, 0, LEN(buf), 1, len, res);
			IF res # Ok THEN EXIT END;
			client.Send(buf, 0, len, FALSE, res);
			IF res # Ok THEN EXIT END
		END;
		IF Trace THEN
			AosOut.Enter; AosOut.String("Echo result "); AosOut.Int(res, 1); AosOut.Exit
		END;
		Terminate
	END EchoAgent;

TYPE
	ChargenAgent = OBJECT (AosTCPServices.Agent)
		VAR res: LONGINT;
		
	BEGIN {ACTIVE}
		LOOP
			client.Send(chargenbuf^, 0, CharGenBufSize, FALSE, res);
			IF res # Ok THEN EXIT END
		END;
		IF Trace THEN
			AosOut.Enter; AosOut.String("Chargen result "); AosOut.Int(res, 1); AosOut.Exit
		END;
		Terminate
	END ChargenAgent;

TYPE
	DayTimeAgent = OBJECT (AosTCPServices.Agent)
		VAR time, date: LONGINT; w: AosIO.Writer;
		
	BEGIN {ACTIVE}
		AosIO.OpenWriter(w, client.Send);
		AosClock.Get(time, date);
		w.Date822(time, date, AosClock.tz);
		w.Ln;
		w.Update;
		Terminate
	END DayTimeAgent;

VAR
	discard, echo, chargen, daytime: AosTCPServices.Service;
	chargenbuf: POINTER TO ARRAY CharGenBufSize OF CHAR;

PROCEDURE InitChargenBuf;
VAR i, j, k: LONGINT;
BEGIN
	k := 0; NEW(chargenbuf);
	FOR i := 1 TO ChargenNumChars DO
		FOR j := 0 TO ChargenLineLength-1 DO
			chargenbuf[k] := CHR(ChargenFirstChar + (i+j) MOD ChargenNumChars); INC(k)
		END;
		chargenbuf[k] := 0DX; chargenbuf[k+1] := 0AX; INC(k, 2)
	END;
	ASSERT(k = CharGenBufSize)
END InitChargenBuf;

PROCEDURE Open*(par: PTR): PTR;
BEGIN
	AosTCPServices.OpenService(discard, DiscardPort, NewDiscardAgent);
	AosTCPServices.OpenService(echo, EchoPort, NewEchoAgent);
	AosTCPServices.OpenService(chargen, ChargenPort, NewChargenAgent);
	AosTCPServices.OpenService(daytime, DayTimePort, NewDayTimeAgent);
	RETURN NIL
END Open;

PROCEDURE Close*(par: PTR): PTR;
BEGIN
	AosTCPServices.CloseService(discard);
	AosTCPServices.CloseService(echo);
	AosTCPServices.CloseService(chargen);
	AosTCPServices.CloseService(daytime);
	RETURN NIL
END Close;

PROCEDURE NewDiscardAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
VAR a: DiscardAgent;
BEGIN
	NEW(a, c, s); RETURN a
END NewDiscardAgent;

PROCEDURE NewEchoAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
VAR a: EchoAgent;
BEGIN
	NEW(a, c, s); RETURN a
END NewEchoAgent;

PROCEDURE NewChargenAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
VAR a: ChargenAgent;
BEGIN
	NEW(a, c, s); RETURN a
END NewChargenAgent;

PROCEDURE NewDayTimeAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
VAR a: DayTimeAgent;
BEGIN
	NEW(a, c, s); RETURN a
END NewDayTimeAgent;

PROCEDURE Cleanup;
BEGIN
	IF Close(NIL) = NIL THEN END
END Cleanup;

BEGIN
	InitChargenBuf;
	discard := NIL; echo := NIL; chargen := NIL; daytime := NIL;
	AosModules.InstallTermHandler(Cleanup)	(* there is still a race with System.Free *)
END AosTestServer.

System.Free AosTestServer ~

System.OpenKernelLog

Aos.Call AosTestServer.Open
Aos.Call AosTestServer.Close
