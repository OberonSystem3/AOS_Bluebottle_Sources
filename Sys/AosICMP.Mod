MODULE AosICMP; (** AUTHOR "mvt"; PURPOSE "ICMP protocol"; *)

(*
	ICMP Header
	
	00	08	type
	01	08	code
	02	16	checksum of icmp header and data
	04	--	contents
	
	ICMP Echo Request/Reply Packet
		
	00	08	type = 8 (request) or type = 0 (reply)
	01	08	code = 0
	02	16	checksum of icmp header and data
	04	16	identifier
	06	16	sequence number
	08	--	optional data
	
	Notes:
	o Bit numbers above are Intel bit order.
	o Avoid use of SET because of PPC bit numbering issues.
	o Always access fields as 8-, 16- or 32-bit values and use DIV, MOD, ASH, ODD for bit access.
*)

IMPORT AosBoot, AosKernel, AosActive, AosModules, AosIP, AosNet;

CONST
	(** Error codes *)
	Ok* = 0;
	AlreadyInstalled* = 3501;
	NeverInstalled* = 3502;
	
	(** ICMP types *)
	TypeEchoReply* = 0;
	TypeDstUnreachable* = 3;
	TypeSourceQuench* = 4;
	TypeRedirect* = 5;
	TypeEchoRequest* = 8;
	TypeTimeExceeded* = 11;
	
	IPTypeICMP = 1; (* ICMP type code for IP packets *)
	ICMPHdrLen = 4; (* length of ICMP header *)

TYPE
	Receiver* = PROCEDURE {DELEGATE} (int: AosIP.Interface; type, code: LONGINT; fip, lip: AosIP.Adr; buffer: AosNet.Buffer);
	
VAR
	receivers: ARRAY 256 OF Receiver; (* registered receivers - array position is ICMP packet type *)
	
	(* Statistic variables *)
	NICMPRcvTotal, NICMPTooSmall, NICMPBadChecksum, NICMPNoReceiver, NICMPDelivered,
	NICMPEchoRequest, NICMPSend: LONGINT;
	
	s: ARRAY 3 OF CHAR; (* temporary string used in module body *)
	res: LONGINT;
	
(* Receive an ICMP packet *)

PROCEDURE Input(int: AosIP.Interface; type: LONGINT; fip, lip: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	code: LONGINT;
	receiver: Receiver;
BEGIN
	ASSERT(type = IPTypeICMP);
	AosKernel.AtomicInc(NICMPRcvTotal);
	IF buffer.len >= ICMPHdrLen THEN
		IF AosIP.Checksum2(buffer.data, buffer.ofs, buffer.len, 0) = 0 THEN
			type := ORD(buffer.data[buffer.ofs]);
			code := ORD(buffer.data[buffer.ofs+1]);
			receiver := receivers[type];
			IF receiver # NIL THEN
				(* do receiver upcall *)
				buffer.l4ofs := buffer.ofs;
				INC(buffer.ofs, ICMPHdrLen);
				DEC(buffer.len, ICMPHdrLen);
				receiver(int, type, code, fip, lip, buffer);
				AosKernel.AtomicInc(NICMPDelivered);
				(* Exit here w/o returning buffer because it is passed to a receiver *)
				RETURN;
			ELSE
				AosKernel.AtomicInc(NICMPNoReceiver);
			END;
		ELSE
			AosKernel.AtomicInc(NICMPBadChecksum);
		END;
	ELSE
		AosKernel.AtomicInc(NICMPTooSmall);
	END;
	(* Exit and return buffer here because it is no longer used *)
	AosNet.ReturnBuffer(buffer);
END Input;

(** Send an ICMP packet. The variables "type" and "code" must conatin the ICMP type and code information. *)

PROCEDURE Send*(fip: AosIP.Adr; VAR data: ARRAY OF CHAR; ofs, len, type, code, TTL: LONGINT);
VAR
	hdr: ARRAY ICMPHdrLen OF CHAR;
	int: AosIP.Interface;
BEGIN
	int := AosIP.InterfaceByDstIP(fip);
	IF int # NIL THEN
		AosKernel.AtomicInc(NICMPSend);
		(* Set ICMP header *)
		hdr[0] := CHR(type);
		hdr[1] := CHR(code);
		AosNet.Put2(hdr, 2, AosIP.Checksum2(data, ofs, len, AosIP.Checksum1(hdr, 0, 2, 0)));
		int.Send(IPTypeICMP, fip, hdr, data, ICMPHdrLen, ofs, len, TTL);
	END;
END Send;

(** Install a receiver for this type *)

PROCEDURE InstallReceiver*(type: LONGINT; r: Receiver; VAR res: LONGINT);
BEGIN {EXCLUSIVE}
	ASSERT(r # NIL);
	ASSERT((type >=0) & (type <= 255));
	IF receivers[type] # NIL THEN
		res := AlreadyInstalled;
	ELSE
		receivers[type] := r;
		res := Ok;
	END;
END InstallReceiver;

(** Remove the currently installed receiver for this type *)

PROCEDURE RemoveReceiver*(type: LONGINT; VAR res: LONGINT);
BEGIN {EXCLUSIVE}
	ASSERT((type >=0) & (type <= 255));
	IF receivers[type] = NIL THEN
		res := NeverInstalled;
	ELSE
		res := Ok;
		receivers[type] := NIL;
	END;
END RemoveReceiver;

(** Standard receiver that replies echo requests *)

PROCEDURE ReplyEcho*(int: AosIP.Interface; type, code: LONGINT; fip, lip: AosIP.Adr; buffer: AosNet.Buffer);
BEGIN
	AosKernel.AtomicInc(NICMPEchoRequest);
	IF ~int.IsBroadcast(lip) THEN
		Send(fip, buffer.data, buffer.ofs, buffer.len, TypeEchoReply, 0, AosIP.MaxTTL);
	END;	
	AosNet.ReturnBuffer(buffer);
END ReplyEcho;

PROCEDURE Cleanup();
BEGIN
	AosIP.RemoveReceiver(IPTypeICMP);
END Cleanup;

BEGIN
	(* Get EchoReply value. Default value is TRUE. *)
	AosBoot.GetConfig("EchoReply", s);
	IF (s # "0") THEN
		(* install internal echoRequest receiver *)
		InstallReceiver(TypeEchoRequest, ReplyEcho, res);
		ASSERT(res = Ok);
	END;
	AosIP.InstallReceiver(IPTypeICMP, Input);
	AosModules.InstallTermHandler(Cleanup);
END AosICMP.

(*
History:
21.10.2003	mvt	Created and moved the ICMP impelementation from the AosIP module to this one.
26.10.2003	mvt	Adapted to new design of AosIP.
*)
