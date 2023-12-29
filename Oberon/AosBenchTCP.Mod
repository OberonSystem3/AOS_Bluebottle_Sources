MODULE AosBenchTCP;	(* pjm *)

IMPORT AosKernel, AosIP, AosTCP, AosDNS, Kernel, Texts, Oberon, In;

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
	w: Texts.Writer;
	buf: Bytes;

PROCEDURE Message(msg1, msg2: ARRAY OF CHAR; res: LONGINT);
BEGIN
	Kernel.LockOberon;
	Texts.WriteString(w, Header); Texts.WriteString(w, msg1); Texts.WriteString(w, msg2);
	IF res # 0 THEN
		Texts.WriteString(w, ", res="); Texts.WriteInt(w, res, 1)
	END;
	Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf);
	Kernel.UnlockOberon
END Message;

PROCEDURE Report(ms, port, total: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	Kernel.LockOberon;
	Texts.WriteString(w, Header);
	IF port = DiscardPort THEN Texts.WriteString(w, "Discard ")
	ELSIF port = EchoPort THEN Texts.WriteString(w, "Echo ")
	ELSE Texts.WriteString(w, "Chargen ")
	END;
	Texts.WriteInt(w, total, 1); Texts.WriteString(w, "KB, ");
	Texts.WriteInt(w, ms, 1); Texts.WriteString(w, "ms, ");
	IF ms # 0 THEN
		Texts.WriteInt(w, ENTIER(total/ms*1000.0), 1); Texts.WriteString(w, "KB/s,");
		Texts.WriteRealFix(w, total/1024.0*8/ms*1000.0, 1, 1, 0); Texts.WriteString(w, "Mb/s")
	ELSE
		Texts.WriteString(w, " N/A")
	END;
	Texts.WriteString(w, ", "); Texts.WriteString(w, msg);
	Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf);
	Kernel.UnlockOberon
END Report;

PROCEDURE Discard*;	(** server KB *)
VAR t: Tester; num: LONGINT; server: ARRAY 64 OF CHAR;
BEGIN
	In.Open; In.String(server); In.LongInt(num);
	IF In.Done & (num > 0) THEN
		NEW(t, server, num, DiscardPort)
	END
END Discard;

PROCEDURE Echo*;	(** server KB *)
VAR t: Tester; num: LONGINT; server: ARRAY 64 OF CHAR;
BEGIN
	In.Open; In.String(server); In.LongInt(num);
	IF In.Done & (num > 0) THEN
		NEW(t, server, num, EchoPort)
	END
END Echo;

BEGIN
	Texts.OpenWriter(w); NEW(buf, BufSize)
END AosBenchTCP.

AosBenchTCP.Discard "192.168.0.2" 1000
AosBenchTCP.Discard portnoy.ethz.ch 10
AosBenchTCP.Discard lillian.ethz.ch 40
AosBenchTCP.Discard bluebottle.ethz.ch 40

AosBenchTCP.Echo lillian.ethz.ch 40
AosBenchTCP.Echo bluebottle.ethz.ch 40
