MODULE AosBenchTCP;	(* pjm *)

IMPORT AosKernel, AosIP, AosOut, AosTCP, AosDNS, Utilities, AosIO, AosCommands;

CONST
	BufSize = 32768;	(* multiple of 1024 *)
	
	CloseTimeout = 10000;	(* ms *)

	EchoPort = 7; DiscardPort = 9; (*ChargenPort = 19;*)
	
	Header = "AosBenchTCP: ";	(* in log *)

TYPE
	Bytes = POINTER TO ARRAY OF CHAR;
	
TYPE
	Sender = OBJECT
		VAR c: AosTCP.Connection; num, num0, res: LONGINT; buf: Bytes; done: BOOLEAN;

		PROCEDURE &Init(c: AosTCP.Connection; buf: Bytes; num: LONGINT);
		BEGIN
			ASSERT(LEN(buf^) >= 1024);
			SELF.c := c; SELF.buf := buf; SELF.num := num;
			done := FALSE
		END Init;
	
		PROCEDURE Join(): LONGINT;
		BEGIN {EXCLUSIVE}
			AWAIT(done);
			RETURN res
		END Join;
		
	BEGIN {ACTIVE}
		res := 0;
		WHILE (res = 0) & (num > 0) DO
			num0 := LEN(buf^) DIV 1024;
			IF num0 > num THEN num0 := num END;
			c.Send(buf^, 0, num0*1024, FALSE, res);
			DEC(num, num0)
		END;
		BEGIN {EXCLUSIVE} done := TRUE END
	END Sender;

TYPE
	Tester = OBJECT
		VAR
			c: AosTCP.Connection; num, num0, res, port, total, len: LONGINT; fip: AosIP.Adr;
			timer: AosKernel.MilliTimer; sender: Sender; server: ARRAY 64 OF CHAR;
		
		PROCEDURE &Init(server: ARRAY OF CHAR; num, port: LONGINT);
		BEGIN
			COPY(server, SELF.server); SELF.num := num; SELF.port := port;
			AosDNS.HostByName(server, fip, res);
			IF res # 0 THEN Message(server, " DNS lookup failed", res) END
		END Init;
		
	BEGIN {ACTIVE}
		IF res = 0 THEN
			Message(server, " opening", 0);
			AosKernel.SetTimer(timer, 0);
			NEW(c); c.Open(AosTCP.NilPort, fip, port, res);
			IF res = 0 THEN
				NEW(sender, c, buf, num);
				IF port = EchoPort THEN
					total := num*2;
					WHILE (res = 0) & (num > 0) DO
						num0 := LEN(buf^) DIV 1024;
						IF num0 > num THEN num0 := num END;
						c.Receive(buf^, 0, num0*1024, num0*1024, len, res);
						DEC(num, num0)
					END
				ELSE
					total := num
				END;
				IF res = 0 THEN res := sender.Join() END;
				c.Close();
				IF res = 0 THEN c.AwaitState(AosTCP.ClosedStates, {}, CloseTimeout, res) END;
				IF res = 0 THEN Report(AosKernel.Elapsed(timer), port, total, server) END
			END;
			IF res # 0 THEN Message(server, " connection failed", res) END
		END
	END Tester;

VAR
	buf: Bytes;


PROCEDURE Message(msg1, msg2: ARRAY OF CHAR; res: LONGINT);
BEGIN
	AosOut.String(Header); AosOut.String(msg1); AosOut.String(msg2);
	IF res # 0 THEN
		AosOut.String(", res="); AosOut.Ln; 
	END;
	AosOut.Ln;
END Message;


PROCEDURE Report(ms, port, total: LONGINT; msg: ARRAY OF CHAR);
VAR
	realStr: ARRAY 128 OF CHAR;
	
BEGIN
	AosOut.String(Header);
	IF port = DiscardPort THEN AosOut.String("Discard ");
	ELSIF port = EchoPort THEN AosOut.String("Echo ");
	ELSE AosOut.String("Chargen ");
	END;
	AosOut.Int(total, 0); AosOut.String("KB, ");
	AosOut.Int(ms, 0); AosOut.String("ms, ");
	IF ms # 0 THEN
		AosOut.Int(ENTIER(total/ms*1000.0), 0); AosOut.String("KB/s,");
		Utilities.FloatToStr(total/1024.0*8/ms*1000.0, 0,0,0,realStr);
		AosOut.String(realStr); AosOut.String("Mb/s");
	ELSE
		AosOut.String(" N/A");
	END;
	AosOut.String(", "); AosOut.String(msg);
	AosOut.Ln;
END Report;


(** server KB *)
PROCEDURE Discard*(par: PTR): PTR;
VAR 
	t: Tester; 
	num: LONGINT; 
	server: ARRAY 64 OF CHAR;
	params: AosCommands.Parameters;
	strReader: AosIO.StringReader;
	
BEGIN
	params := par(AosCommands.Parameters);
	NEW(strReader, LEN(params.str^));
	strReader.Set(params.str^);
	strReader.SkipWhitespace;
	
	strReader.String(server); strReader.SkipWhitespace;
	strReader.Int(num, FALSE); strReader.SkipWhitespace;
	
	NEW(t, server, num, DiscardPort);

	RETURN NIL;
END Discard;


(** server KB *)
PROCEDURE Echo*(par: PTR):PTR;	
VAR 
	t: Tester; 
	num: LONGINT; 
	server: ARRAY 64 OF CHAR;
	params: AosCommands.Parameters;
	strReader: AosIO.StringReader;
	
BEGIN
	params := par(AosCommands.Parameters);
	NEW(strReader, LEN(params.str^));
	strReader.Set(params.str^);
	strReader.SkipWhitespace;
	
	strReader.String(server); strReader.SkipWhitespace;
	strReader.Int(num, FALSE); strReader.SkipWhitespace;

	NEW(t, server, num, EchoPort);

	RETURN NIL;
END Echo;

BEGIN
	NEW(buf, BufSize)
END AosBenchTCP.

AosBenchTCP.Discard 192.168.0.2 1000
AosBenchTCP.Discard portnoy.ethz.ch 10
AosBenchTCP.Discard lillian.ethz.ch 40000
AosBenchTCP.Discard bluebottle.ethz.ch 40

AosBenchTCP.Echo lillian.ethz.ch 40000 ~
AosBenchTCP.Echo bluebottle.ethz.ch 40

AosBenchTCP.Echo FE80::230:1BFF:FEAF:EEF2 100000~
AosBenchTCP.Discard FE80::230:1BFF:FEAF:EEF2 100000~
S.Free AosBenchTCP