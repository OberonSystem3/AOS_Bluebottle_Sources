(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosTestNet; (** AUTHOR "pjm, mvt"; PURPOSE "Module for testing network device drivers"; *)

IMPORT SYSTEM, AosKernel, AosModules, AosOut, AosPlugins, AosNet, Texts, Oberon, In;

CONST
	TestSendType = 0DEADH;
	TestReplyType = 0BEEFH;
	
VAR
	w: Texts.Writer;
	dev, dev2: AosNet.LinkDevice;
	replies: LONGINT;
	received: LONGINT;
	peer: AosNet.LinkAdr;
	nofpkt: LONGINT;
	startTime: LONGINT;
	
(** Show all registered link devices. *)

PROCEDURE ShowDevices*;
VAR table: AosPlugins.Table; dev: AosNet.LinkDevice; i: LONGINT; s: ARRAY 32 OF CHAR;
BEGIN
	AosNet.registry.GetAll(table);
	IF table # NIL THEN
		FOR i := 0 TO LEN(table)-1 DO
			dev := table[i](AosNet.LinkDevice);
			Texts.WriteString(w, dev.name);
			IF dev.type = AosNet.TypeEthernet THEN
				Texts.WriteString(w, " Ethernet ");
			ELSIF dev.type = AosNet.TypePointToPoint THEN
				Texts.WriteString(w, " Point-to-point ")
			ELSE
				Texts.WriteString(w, " Unknown ")
			END;
			AosNet.LinkAdrToStr(dev.local, dev.adrSize, s);
			Texts.WriteString(w, s); Texts.Write(w, " ");
			AosNet.LinkAdrToStr(dev.broadcast, dev.adrSize, s);
			Texts.WriteString(w, s); Texts.Write(w, " ");
			Texts.WriteInt(w, dev.mtu, 1); Texts.Write(w, " ");
			
			(* does not work with HUGEINT:
			Texts.WriteInt(w, dev.sendCount, 1); Texts.Write(w, " ");
			Texts.WriteInt(w, dev.recvCount, 1);
			*)
			
			Texts.WriteLn(w);
			Texts.Append(Oberon.Log, w.buf)
		END
	END
END ShowDevices;

PROCEDURE FindDevice(name: ARRAY OF CHAR): AosNet.LinkDevice;
VAR table: AosPlugins.Table; i: LONGINT;
BEGIN
	AosNet.registry.GetAll(table);
	IF table # NIL THEN
		FOR i := 0 TO LEN(table)-1 DO
			IF table[i].name = name THEN RETURN table[i](AosNet.LinkDevice) END
		END
	END;
	RETURN NIL
END FindDevice;

PROCEDURE Receiver(dev: AosNet.LinkDevice; type: LONGINT; buf: AosNet.Buffer);
VAR s: ARRAY 32 OF CHAR;
BEGIN
(*
	AosOut.Enter; AosOut.Hex(type, 9); AosOut.Char(" ");
	AosNet.LinkAdrToStr(buf.src, dev.adrSize, s); AosOut.String(s); AosOut.Ln;
	AosOut.Memory(SYSTEM.ADR(buf.data[buf.ofs]), buf.len);
	AosOut.Exit;
*)
	IF type = TestSendType THEN
		IF ~ODD(ORD(buf.src[0])) THEN	(* reply to unicast sources *)
			INC(received);
			dev.Send(buf.src, TestReplyType, buf.data, buf.data, buf.data, 0, 0, buf.ofs, buf.len, FALSE)
		END
	ELSIF type = TestReplyType THEN
		INC(replies); peer := buf.src;
		IF replies >= nofpkt THEN
			AosOut.String("Finished. ms="); AosOut.Int(AosKernel.GetTimer()-startTime, 0); AosOut.Ln;
		END;
	END;
	AosNet.ReturnBuffer(buf);
END Receiver;

(** Set the test device. *)

PROCEDURE SetDevice*;	(** devname ~ *)
VAR name: ARRAY 32 OF CHAR;
BEGIN
	In.Open; In.String(name);
	IF In.Done THEN
		dev := FindDevice(name);
		IF dev # NIL THEN
			Texts.WriteString(w, name); Texts.WriteString(w, " is now the test device");
			Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf);
			dev.InstallReceiver(TestSendType, Receiver);
			dev.InstallReceiver(TestReplyType, Receiver)
		ELSE
			Texts.WriteString(w, name); Texts.WriteString(w, " not found");
			Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf)
		END
	END
END SetDevice;

(** Set the 2nd test device. *)

PROCEDURE SetDevice2*;	(** devname ~ *)
VAR name: ARRAY 32 OF CHAR;
BEGIN
	In.Open; In.String(name);
	IF In.Done THEN
		dev2 := FindDevice(name);
		IF dev2 # NIL THEN
			Texts.WriteString(w, name); Texts.WriteString(w, " is now the 2nd test device");
			Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf);
			dev2.InstallReceiver(TestSendType, Receiver);
			dev2.InstallReceiver(TestReplyType, Receiver)
		ELSE
			Texts.WriteString(w, name); Texts.WriteString(w, " not found");
			Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf)
		END
	END
END SetDevice2;

(** Broadcast a test packet. *)

PROCEDURE SendBroadcast*;
VAR i: LONGINT; data: ARRAY 100 OF CHAR;
BEGIN
	IF dev # NIL THEN
		replies := 0;
		nofpkt := 1;
		startTime := AosKernel.GetTimer();
		FOR i := 0 TO LEN(data)-1 DO data[i] := CHR(i MOD 100H) END;
		dev.Send(dev.broadcast, TestSendType, data, data, data, 0, 0, 0, LEN(data), FALSE)
	END
END SendBroadcast;

(** Send test packets to peer. *)

PROCEDURE SendTest*;	(* n ~ *)
VAR i, n: LONGINT; data: ARRAY 1500 OF CHAR;
BEGIN
	In.Open; In.LongInt(n);
	IF (dev # NIL) & In.Done THEN
		replies := 0;
		nofpkt := n;
		startTime := AosKernel.GetTimer();
		FOR i := 0 TO LEN(data)-1 DO data[i] := CHR(i MOD 100H) END;
		FOR i := 0 TO n-1 DO
			data[0] := CHR(i DIV 100H);
			data[1] := CHR(i MOD 100H);
			dev.Send(peer, TestSendType, data, data, data, 0, 0, 0, LEN(data), FALSE);
		END
	END
END SendTest;

PROCEDURE Cleanup;
BEGIN
	IF dev # NIL THEN
		dev.RemoveReceiver(TestSendType);
		dev.RemoveReceiver(TestReplyType);
	END;
	IF dev2 # NIL THEN
		dev2.RemoveReceiver(TestSendType);
		dev2.RemoveReceiver(TestReplyType);
	END;
END Cleanup;

BEGIN
	Texts.OpenWriter(w);
	dev := NIL;
	AosModules.InstallTermHandler(Cleanup);
END AosTestNet.

(* History:
21.10.2003	mvt	Changed for new AosNet interface
21.11.2003	mvt	Added support for 2nd (reply) device
*)

AosTestNet.ShowDevices
AosTestNet.SetDevice "3Com90x#0"
AosTestNet.SetDevice2 "3Com90x#1"
AosTestNet.SendBroadcast  AosTestNet.SendTest ^ 1 10 100 1000 10000

System.Free AosTestNet~
