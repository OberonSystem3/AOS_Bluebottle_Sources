MODULE AosICMP; (** AUTHOR "mvt"; PURPOSE "ICMP protocol"; *)

(*
	ICMPv4 Header
	
	00	08	type
	01	08	code
	02	16	checksum of icmp header and data
	04	--	contents
	
	ICMPv4 Echo Request/Reply Packet
		
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

IMPORT SYSTEM, AosKernel, AosModules, AosOut, AosIP, AosIPv6, AosNet, Utilities;

CONST
	(* DEBUG *)
	DEBUG = FALSE;

	(** Error codes *)
	Ok* = 0;
	AlreadyInstalled* = 3501;
	NeverInstalled* = 3502;
	
	(* ICMP type exported *)
	ICMPDstUnreachable* = 1;
	
	(** ICMPv4 types *)
	TypeEchoReplyv4* = 0;
	TypeDstUnreachablev4 = 3;
	TypeSourceQuenchv4 = 4;
	TypeRedirectv4 = 5;
	TypeEchoRequestv4* = 8;
	TypeTimeExceededv4* = 11;
	
	(* ICMPv6 error types *)
	TypeDstUnreachablev6 = 1;
	TypePacketTooBigv6 = 2;
	TypeTimeExceededv6* = 3;
	TypeParamProbv6 = 4;
	
	(* ICMPv6 informal messages types *)
	TypeEchoRequestv6* = 128;
	TypeEchoReplyv6* = 129;
	
	(* Neighbor Discovery *)
	TypeNeighborSolicitation = 135;
	TypeNeighborAdvertisement = 136;
	TypeRouterSolicitation = 133;
	TypeRouterAdvertisement = 134;
	
	IPTypeICMPv4 = 1; (* ICMPv4 type code for IP packets *)
	IPTypeICMPv6 = 58; (* ICMPv6 type code for IP packets *)
	ICMPHdrLen = AosIP.ICMPHdrLen; (* length of ICMP header *)
	
	MaxPseudoHdrLen = 40;  (* IPv6: 40 *)
	PrefixOptHdrLen = 4;	(* 4 * 8-byte block *)
	MTUOptHdrLen = 1;		(* 1 * 8-byte block *)
	RtrAdvHdrLen = 12;		(* Router advertisement header length *)
	TimeExcHdrLen = 4;		(* ICMPv6 time exceeded header length *)
	ParamExcHdrLen = 4;	(* ICMPv6 parameter problem header length *)

TYPE
	Receiver* = PROCEDURE {DELEGATE} (int: AosIP.Interface; type, code: LONGINT; fip, lip: AosIP.Adr; buffer: AosNet.Buffer);
	
VAR
	receivers: ARRAY 256 OF Receiver; (* registered receivers - array position is ICMP packet type *)
	
	(* Statistic variables *)
	NICMPRcvTotal-, NICMPTooSmall-, NICMPBadChecksum-, NICMPNoReceiver-, NICMPDelivered-,
	NICMPEchoRequest-, NICMPSend-: LONGINT;
	
	res: LONGINT;
	
(* Receive an ICMP (v4 and v6) packet *)
PROCEDURE Input(int: AosIP.Interface; type: LONGINT; fip, lip: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	code: LONGINT;
	receiver: Receiver;
	checksumOk: BOOLEAN;
	sum: LONGINT;
	pseudoHdrLen: LONGINT;
	pseudoHdr: ARRAY MaxPseudoHdrLen OF CHAR; (* pseudo header for calculating checksum *)
	reassembledLength: LONGINT;
	fragmentBuffer: AosNet.Buffer;
	
BEGIN
	IF DEBUG THEN
		ASSERT ((type = IPTypeICMPv6) OR (type = IPTypeICMPv4));
	END;
				
	AosKernel.AtomicInc(NICMPRcvTotal);
	IF buffer.len >= ICMPHdrLen THEN				
		(* Checksum calculation of ICMPv4 and ICMPv6 is different! In ICMPv6 another pseudo header is used *)
		IF int.protocol = AosIP.IPv4 THEN
			checksumOk := AosIP.Checksum2(buffer.data, buffer.ofs, buffer.len, 0) = 0;
		ELSIF int.protocol = AosIP.IPv6 THEN
			(* Get checksum from header *)
			sum := AosNet.GetNet2(buffer.data, buffer.ofs + 2);

			IF sum # 0 THEN
				(* calculate checksum *)
				(* set pseudo header *)
				reassembledLength := 0;
				fragmentBuffer := buffer;
				WHILE fragmentBuffer # NIL DO
					INC(reassembledLength, fragmentBuffer.len);
					fragmentBuffer := fragmentBuffer.nextFragment;
				END;			
				
				pseudoHdrLen := int.WritePseudoHeader(pseudoHdr, fip, lip, IPTypeICMPv6, reassembledLength);
				sum := AosIP.Checksum1(pseudoHdr, 0, pseudoHdrLen, 0);
				
				IF buffer.nextFragment # NIL THEN
					(* fragmented packets *)
					fragmentBuffer := buffer;
					WHILE fragmentBuffer.nextFragment # NIL DO
						sum := AosIP.Checksum1(fragmentBuffer.data, fragmentBuffer.ofs, fragmentBuffer.len, sum);						
						fragmentBuffer := fragmentBuffer.nextFragment;
					END;
					
					sum := AosIP.Checksum2(fragmentBuffer.data, fragmentBuffer.ofs, fragmentBuffer.len, sum);
				ELSE			
					sum := AosIP.Checksum2(buffer.data, buffer.ofs, buffer.len, sum);
				END;
			END;
			checksumOk := sum = 0;
		ELSE
			IF DEBUG THEN
				ASSERT(TRUE);
			END;
			(* interface with unknown protocol *)
			checksumOk := FALSE;
		END;
		
		IF checksumOk THEN					
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


(** Send an ICMP packet. The variables "type" and "code" must conatin the ICMP type and code information.
	interface can be set to send the ICMP message on a specific interface otherwise it is automatically slected. *)
PROCEDURE Send*(interface: AosIP.Interface; fip: AosIP.Adr; VAR data: ARRAY OF CHAR; ofs, len, type, code, TTL: LONGINT);
VAR
	hdr: ARRAY ICMPHdrLen OF CHAR;
	pseudoHdrLen: LONGINT;
	pseudoHdr: ARRAY MaxPseudoHdrLen OF CHAR; (* pseudo header for calculating checksum *)
	sum: LONGINT;
	
BEGIN;		
	(* IF no interface was given choose one *)
	IF interface = NIL THEN
		interface := AosIP.InterfaceByDstIP(fip);				
	END;
	
	IF interface # NIL THEN			
		AosKernel.AtomicInc(NICMPSend);
		(* Set ICMP header *)
		hdr[0] := CHR(type);
		hdr[1] := CHR(code);
		IF fip.usedProtocol = AosIP.IPv4 THEN			
			AosNet.Put2(hdr, 2, AosIP.Checksum2(data, ofs, len, AosIP.Checksum1(hdr, 0, 2, 0)));
			interface.Send(IPTypeICMPv4, fip, hdr, data, ICMPHdrLen, ofs, len, TTL);
		ELSIF fip.usedProtocol = AosIP.IPv6 THEN
			(* Use pseudo header for checksum calculation *)
			(* set pseudo header *)			
			pseudoHdrLen := interface.WritePseudoHeader(pseudoHdr, interface.localAdr, fip, IPTypeICMPv6, len+ICMPHdrLen);

			sum := AosIP.Checksum1(pseudoHdr, 0, pseudoHdrLen, 0);
			sum := AosIP.Checksum1(hdr, 0, ICMPHdrLen, sum);
			sum := AosIP.Checksum2(data, ofs, len, sum);
			AosNet.Put2(hdr, 2, sum); (* checksum := sum *)				
			interface.Send(IPTypeICMPv6, fip, hdr, data, ICMPHdrLen, ofs, len, TTL);			
		END;
	END;
END Send;


(** Send an ICMP packet. The variables "type" and "code" must conatin the ICMP type and code information.
	interface must be set. The ICMPv6 packet is directly send without cache lookups etc. *)
PROCEDURE SendDirectly*(interface: AosIPv6.Interface; linkDst: AosNet.LinkAdr; fip: AosIP.Adr; VAR data: ARRAY OF CHAR; ofs, len, type, code, TTL: LONGINT);
VAR
	hdr: ARRAY ICMPHdrLen OF CHAR;
	pseudoHdrLen: LONGINT;
	pseudoHdr: ARRAY MaxPseudoHdrLen OF CHAR; (* pseudo header for calculating checksum *)
	sum: LONGINT;
	
BEGIN
	IF DEBUG THEN
		ASSERT (interface # NIL);
		ASSERT (fip.usedProtocol = AosIP.IPv6);
	END;
	
	IF interface # NIL THEN
		AosKernel.AtomicInc(NICMPSend);
		(* Set ICMP header *)
		hdr[0] := CHR(type);
		hdr[1] := CHR(code);
		(* Use pseudo header for checksum calculation *)
		(* set pseudo header *)
		pseudoHdrLen := interface.WritePseudoHeader(pseudoHdr, interface.localAdr, fip, IPTypeICMPv6, len+ICMPHdrLen);

		sum := AosIP.Checksum1(pseudoHdr, 0, pseudoHdrLen, 0);
		sum := AosIP.Checksum1(hdr, 0, ICMPHdrLen, sum);
		sum := AosIP.Checksum2(data, ofs, len, sum);
		AosNet.Put2(hdr, 2, sum); (* checksum := sum *)

		interface.SendDirectly(linkDst, IPTypeICMPv6, fip, hdr, data, ICMPHdrLen, ofs, len, TTL);			
	END;
END SendDirectly;


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
VAR
	longData: POINTER TO ARRAY OF CHAR;
	fragmentBuffer: AosNet.Buffer;
	fragmentLen: LONGINT;
	i: LONGINT;
	
BEGIN
	AosKernel.AtomicInc(NICMPEchoRequest);
	IF ~int.IsBroadcast(lip) THEN
		IF fip.usedProtocol = AosIP.IPv4 THEN
			Send(int, fip, buffer.data, buffer.ofs, buffer.len, TypeEchoReplyv4, 0, AosIP.MaxTTL);

		ELSIF fip.usedProtocol = AosIP.IPv6 THEN
			IF buffer.nextFragment = NIL THEN
				Send(int, fip, buffer.data, buffer.ofs, buffer.len, TypeEchoReplyv6, 0, AosIP.MaxTTL);
			ELSE
				(* packet is fragmented *)
				NEW(longData, AosIPv6.MaxFragPacketSize);
				fragmentBuffer := buffer;
				fragmentLen := 0;
				WHILE fragmentBuffer # NIL DO
					FOR i := 0 TO fragmentBuffer.len - 1 DO
						longData^[fragmentLen + i] := fragmentBuffer.data[fragmentBuffer.ofs + i];
					END;
					INC(fragmentLen, fragmentBuffer.len);					
					
					fragmentBuffer := fragmentBuffer.nextFragment;
				END;
										
				Send(int, fip, longData^, 0, fragmentLen, TypeEchoReplyv6, 0, AosIP.MaxTTL);
			END;
		ELSE
			IF DEBUG THEN
				ASSERT(TRUE);
			END;
			(* Unknown protocol *)
		END
	END;	
	AosNet.ReturnBuffer(buffer);
END ReplyEcho;


(* Send a ICMP message *)
PROCEDURE SendICMP* (type: LONGINT; fip: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	IPHdrLen: LONGINT; (* length of IP header to copy *)
	icmpMsg: ARRAY 72 OF CHAR; (* unused (4) + MaxIPHdrLen (60) + UDPHdrLen (8) *)
	
BEGIN {EXCLUSIVE}
	CASE type OF
		ICMPDstUnreachable:
			IPHdrLen := buffer.ofs - buffer.l3ofs;
			AosNet.Put4(icmpMsg, 0, 0); (* unused *)
			(* 8: first 8 bytes of the original datagram-s dataIP header UDP header *)
			AosNet.Copy(buffer.data, icmpMsg, buffer.l3ofs, 4, IPHdrLen + 8); 
			Send(NIL, fip, icmpMsg, 0, 4+IPHdrLen+8, TypeDstUnreachablev4, 3, AosIP.MaxTTL);
		ELSE
			IF DEBUG THEN
				ASSERT(TRUE);
			END;				
	END;
END SendICMP;


(* Send a Neighbor Advertisement message *)
PROCEDURE SendNeighborAdvertisement*(interface: AosIPv6.Interface; linkDst: AosNet.LinkAdr; dstAdr: AosIP.Adr; solicited: BOOLEAN);
VAR
	nsData: ARRAY AosIPv6.NeighborHdrLen + AosIPv6.LLAdrOptionLen OF CHAR; 
	nsDataLen: LONGINT;
	i: LONGINT;
	flagsSet: SET;
	
BEGIN
	flagsSet := {};
	
	(* routerFlag *)
	IF interface.isRouter THEN
		flagsSet := flagsSet + {31};
	END;
	
	(* solicited flag *)
	IF solicited THEN
		flagsSet := flagsSet + {30};
	END;
	
	(* override flag is true *)
	flagsSet := flagsSet + {29};
	
	AosNet.PutNet4(nsData, 0, SYSTEM.VAL(LONGINT, flagsSet));	(* flags & reserved *)
	
	FOR i := 0 TO 3 DO		(* Target address 16 byte *)
		AosNet.Put4(nsData, 4+(i*4), AosNet.Get4(interface.localAdr.ipv6Adr, i * 4));
	END;
	
	IF ~AosIP.IsNilAdr(dstAdr) THEN
		(* Add a Source Link-Layer Address option *)
		nsDataLen := AosIPv6.NeighborHdrLen + AosIPv6.LLAdrOptionLen;
		nsData[20] := 2X;	(* Type = 2 *)
		nsData[21] := 1X;	(* Length = 1 : Ethernet MAC Address (6bytes) *)
		FOR i := 0 TO 5 DO	(* Link-Layer Address *)
			nsData[22+i] := interface.dev.local[i];
		END;
	ELSE
		nsDataLen := 20;
	END;
	
	(* Send packet directly without Neighbor Cache lookup etc. *)
	IF solicited THEN
		SendDirectly (interface, linkDst, dstAdr, nsData, 0, nsDataLen, TypeNeighborAdvertisement, 0, AosIP.MaxTTL);
	ELSE
		SendDirectly (interface, AosIPv6.linkMulticastAllNodesAdr, dstAdr, nsData, 0, nsDataLen, TypeNeighborAdvertisement, 0, AosIP.MaxTTL);
	END;
END SendNeighborAdvertisement;


(* Send a Neighbor Solicitation message *)
PROCEDURE SendNeighborSolicitation*(interface: AosIPv6.Interface; linkDst: AosNet.LinkAdr; dstAdr: AosIP.Adr; multicast: BOOLEAN);
VAR
	nsData: ARRAY AosIPv6.NeighborHdrLen + AosIPv6.LLAdrOptionLen OF CHAR;
	nsDataLen: LONGINT;
	solicitedNodeDstAdr: AosIP.Adr;
	i: LONGINT;
	
BEGIN
	AosNet.Put4(nsData, 0, 0);	(* Reserved *)
	
	FOR i := 0 TO 3 DO		(* Target address 16 byte *)
		AosNet.Put4(nsData, 4+(i*4), AosNet.Get4(dstAdr.ipv6Adr, i * 4));
	END;
	
	IF ~AosIP.IsNilAdr(dstAdr) THEN
		(* Add a Source Link-Layer Address option *)
		nsDataLen := AosIPv6.NeighborHdrLen + AosIPv6.LLAdrOptionLen;
		nsData[20] := 1X;	(* Type = 1 *)
		nsData[21] := 1X;	(* Length = 1 : Ethernet MAC Address (6bytes) *)
		FOR i := 0 TO 5 DO	(* Link-Layer Address *)
			nsData[22+i] := interface.dev.local[i];
		END;
	ELSE
		nsDataLen := 20;
	END;
			
	(* Send packet directly without Neighbor Cache lookup etc. *)	
	IF multicast THEN
		solicitedNodeDstAdr := AosIPv6.linkLocalMulticastNodeAdr;
		FOR i := 13 TO 15 DO
			solicitedNodeDstAdr.ipv6Adr[i] := dstAdr.ipv6Adr[i];
		END;
		solicitedNodeDstAdr.ipv6Adr[11] := 1X;
		solicitedNodeDstAdr.ipv6Adr[12] := 0FFX;
		SendDirectly (interface, linkDst, solicitedNodeDstAdr, nsData, 0, nsDataLen, TypeNeighborSolicitation, 0, AosIP.MaxTTL);
	ELSE
		SendDirectly (interface, linkDst, dstAdr, nsData, 0, nsDataLen, TypeNeighborSolicitation, 0, AosIP.MaxTTL);
	END;
END SendNeighborSolicitation;


(* Send a Router Solicitation message *)
PROCEDURE SendRouterSolicitation(interface: AosIPv6.Interface);
VAR
	rsData: ARRAY AosIPv6.RouterSolHdrLen + AosIPv6.LLAdrOptionLen OF CHAR; 
	rsDataLen: LONGINT;
	i: LONGINT;
	
BEGIN
	AosNet.Put4(rsData, 0, 0); (* Reserved *)
	
	(* Add a source link-layer option *)	
	rsDataLen := AosIPv6.RouterSolHdrLen + AosIPv6.LLAdrOptionLen;
	rsData[4] := 1X;	(* Type = 1 *)
	rsData[5] := 1X; (* Length = 1: Ethernet MAC Address (6 bytes) *)
	FOR i := 0 TO 5 DO	(* Link-Layer Address *)
		rsData[6+i] := interface.dev.local[i];
	END;
	
	SendDirectly (interface, AosIPv6.linkMulticastAllRoutersAdr, AosIPv6.linkLocalMulticastRouterAdr, rsData, 0, rsDataLen, TypeRouterSolicitation, 0, AosIP.MaxTTL);
END SendRouterSolicitation;


(* Send a Router Advertisement message *)
PROCEDURE SendRouterAdvertisement(interface: AosIPv6.Interface; dstAdr: AosIP.Adr; dstLinkAdr: AosNet.LinkAdr; routerConfig: AosIPv6.RouterConfig);
VAR
	raData: POINTER TO ARRAY OF CHAR;
	raDataLen: LONGINT;
	nbrOfPrefixes: LONGINT;
	prefixConfigItem: AosIPv6.PrefixConfig;
	flags: SET;
	offset: LONGINT;
	i: LONGINT;
	
BEGIN
	(* Count number of prefix options *)
	nbrOfPrefixes := 0;
	prefixConfigItem := routerConfig.Prefixes;
	WHILE prefixConfigItem # NIL DO
		prefixConfigItem := prefixConfigItem.next;
		INC(nbrOfPrefixes);
	END;
	
	INC(raDataLen, nbrOfPrefixes * 8 * PrefixOptHdrLen);	(* prefix options header len is written in number of 8-bytes block *)
	
	(* Source link-layer address option *)
	INC(raDataLen, AosIPv6.LLAdrOptionLen);
	
	(* MTU option *)
	IF routerConfig.LinkMTU # 0 THEN
		INC(raDataLen, MTUOptHdrLen * 8);
	END;
	
	INC(raDataLen, RtrAdvHdrLen);
	
	NEW(raData, raDataLen);

	(* Fill packet *)
	raData^[0] := CHR(routerConfig.CurrentHopLimit);	(* Current hop limit *)
	
	(* Managed address configuration, other stateful configuration and home agent flag 
	    Home flag is always zero. *)
	flags := {};
	IF routerConfig.ManagedAddressConfig THEN
		flags := flags + {7};
	END;
	IF routerConfig.OtherStatefulConfig THEN
		flags := flags + {6};
	END;
	
	raData^[1] := SYSTEM.VAL(CHAR, flags);
	
	AosNet.PutNet2(raData^, 2, routerConfig.Lifetime);
	AosNet.PutNet4(raData^, 4, routerConfig.ReachableTime);
	AosNet.PutNet4(raData^, 8, routerConfig.RetransTimer);
	
	offset := 12;
	
	(* Add a source link-layer option *)
	raData^[offset] := 1X;	(* Type = 1 *)
	raData^[offset + 1] := 1X; (* Length = 1: Ethernet MAC Address (6 bytes) *)
	FOR i := 0 TO 5 DO	(* Link-Layer Address *)
		raData^[offset + 2 + i] := interface.dev.local[i];
	END;
	INC(offset, AosIPv6.LLAdrOptionLen);
	
	(* LinkMTU option *)
	IF routerConfig.LinkMTU # 0 THEN
		raData^[offset] := 5X;
		raData^[offset+1] := 1X;
		AosNet.Put2(raData^, offset + 2, 0);
		AosNet.PutNet4(raData^, offset + 4, routerConfig.LinkMTU);
		
		INC(offset, 8);
	END;
	
	(* Prefixes *)
	prefixConfigItem := routerConfig.Prefixes;
	WHILE prefixConfigItem # NIL DO
		raData^[offset] := 3X;
		raData^[offset + 1] := 4X;
		raData^[offset + 2] := CHR(prefixConfigItem.Prefix.data);
		
		(* flags *)
		flags := {};
		IF prefixConfigItem.OnLink THEN
			flags := flags + {7};
		END;
		IF prefixConfigItem.Autonomous THEN
			flags := flags + {6};
		END;
		(* router address flag is always zero: Mobility support is disabled *)
		IF prefixConfigItem.IsSitePrefix THEN
			flags := flags + {4};
		END;
		raData^[offset + 3] := SYSTEM.VAL(CHAR, flags);
		
		AosNet.PutNet4(raData^, offset + 4, prefixConfigItem.ValidLifetime);
		AosNet.PutNet4(raData^, offset + 8, prefixConfigItem.PreferredLifetime);
		AosNet.Put4(raData^, offset + 12, 0);
		
		IF prefixConfigItem.IsSitePrefix THEN
			raData^[offset + 15] := CHR(prefixConfigItem.Prefix.data);
		END;
		
		FOR i := 0 TO 15 DO
			raData^[offset + 16 + i] := prefixConfigItem.Prefix.ipv6Adr[i];
		END;
	
		INC(offset, 8 * PrefixOptHdrLen);
		prefixConfigItem := prefixConfigItem.next;
	END;	
	SendDirectly (interface, dstLinkAdr, dstAdr, raData^, 0, raDataLen, TypeRouterAdvertisement, 0, AosIP.MaxTTL);
END SendRouterAdvertisement;


(** Send a ICMPv6 time exceeded message *)
PROCEDURE SendICMPv6TimeExceeded(interface: AosIPv6.Interface; discardedPacket: AosNet.Buffer; srcAdr: AosIP.Adr; code: LONGINT);
VAR
	(* Max size of a ICMPv6 time exceeded packet including portion of discarded packet is 1280 *)
	teData: ARRAY TimeExcHdrLen + 1280 - AosIPv6.MaxIPHdrLen - ICMPHdrLen OF CHAR; 
	teDataLen: LONGINT;
	i: LONGINT;
	
BEGIN
	AosNet.Put4(teData, 0, 0); (* Unused *)
	
	(* add portion of discarded packet *)	
	teDataLen := Utilities.Min(TimeExcHdrLen + 1280 - AosIPv6.MaxIPHdrLen - ICMPHdrLen, TimeExcHdrLen + discardedPacket.len);
	FOR i := TimeExcHdrLen TO teDataLen - 1 DO
		teData[i] := discardedPacket.data[i - TimeExcHdrLen];
	END;
	
	Send(interface, srcAdr, teData, 0, teDataLen, TypeTimeExceededv6, code, interface.curHopLimit);
END SendICMPv6TimeExceeded;


(** Send a ICMPv6 parameter problem message *)
PROCEDURE SendICMPv6ParamProb(interface: AosIPv6.Interface; discardedPacket: AosNet.Buffer; srcAdr: AosIP.Adr; probPointer: LONGINT; code: LONGINT);
VAR
	(* Max size of a ICMPv6 parameter problem packet including portion of discarded packet is 1280 *)
	ppData: ARRAY ParamExcHdrLen + 1280 - AosIPv6.MaxIPHdrLen - ICMPHdrLen OF CHAR; 
	ppDataLen: LONGINT;
	i: LONGINT;
	
BEGIN
	AosNet.Put4(ppData, 0, probPointer);
	
	(* add portion of discarded packet *)	
	ppDataLen := Utilities.Min(ParamExcHdrLen + 1280 - AosIPv6.MaxIPHdrLen - ICMPHdrLen, ParamExcHdrLen + discardedPacket.len);
	FOR i := ParamExcHdrLen TO ppDataLen - 1 DO
		ppData[i] := discardedPacket.data[i - ParamExcHdrLen];
	END;
	
	Send(interface, srcAdr, ppData, 0, ppDataLen, TypeParamProbv6, code, interface.curHopLimit);
END SendICMPv6ParamProb;

(* Receive a neighbor Soliciation message *)
PROCEDURE ReceiveNeighborSolicitation (interface: AosIP.Interface; type, code: LONGINT; srcAdr, dstAdr: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	ipv6Interface: AosIPv6.Interface;
	
BEGIN
	IF interface IS AosIPv6.Interface THEN
		(* Only IPv6 *)
		ipv6Interface := interface (AosIPv6.Interface);
		ipv6Interface.ReceiveNeighborSolicitation(srcAdr, dstAdr, buffer);
		
	ELSE
		IF DEBUG THEN
			ASSERT(TRUE);
		END;
		AosNet.ReturnBuffer(buffer);
	END;
END ReceiveNeighborSolicitation;


(* Receive a neighbor Advertisement message *)
PROCEDURE ReceiveNeighborAdvertisement (interface: AosIP.Interface; type, code: LONGINT; srcAdr, dstAdr: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	ipv6Interface: AosIPv6.Interface;
	
BEGIN
	IF interface IS AosIPv6.Interface THEN
		(* Only IPv6 *)
		ipv6Interface := interface (AosIPv6.Interface);
		ipv6Interface.ReceiveNeighborAdvertisement (srcAdr, dstAdr, buffer);
		
	ELSE
		IF DEBUG THEN
			ASSERT(TRUE);
		END;
		AosNet.ReturnBuffer(buffer);
	END;
END ReceiveNeighborAdvertisement;


(* Receive a router solicitation message *)
PROCEDURE ReceiveRouterSolicitation(interface: AosIP.Interface; type, code: LONGINT; srcAdr, dstAdr: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	ipv6Interface: AosIPv6.Interface;
	
BEGIN
	IF interface IS AosIPv6.Interface THEN
		(* Only IPv6 *)
		ipv6Interface := interface (AosIPv6.Interface);
		ipv6Interface.ReceiveRouterSolicitation();
	ELSE
		IF DEBUG THEN
			ASSERT(TRUE);
		END;		
	END;

AosOut.Enter;AosOut.Ln; AosOut.String("************************");AosOut.Ln;
AosOut.String("Received a router advertisement");
AosOut.String("");
AosOut.Ln; AosOut.String("************************");AosOut.Ln;AosOut.Exit;	
	
	AosNet.ReturnBuffer(buffer);
END ReceiveRouterSolicitation;


(* Receive a router advertisement message *)
PROCEDURE ReceiveRouterAdvertisement (interface: AosIP.Interface; type, code: LONGINT; srcAdr, dstAdr: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	ipv6Interface: AosIPv6.Interface;
	
BEGIN
	IF interface IS AosIPv6.Interface THEN
		(* Only IPv6 *)
		ipv6Interface := interface (AosIPv6.Interface);
		ipv6Interface.ReceiveRouterAdvertisement(srcAdr, buffer);
	ELSE
		IF DEBUG THEN
			ASSERT(TRUE);
		END;
		AosNet.ReturnBuffer(buffer);
	END;
END ReceiveRouterAdvertisement;


(* Receive a packet too big message *)
PROCEDURE ReceivePacketTooBig (interface: AosIP.Interface; type, code: LONGINT; srcAdr, dstAdr: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	ipv6Interface: AosIPv6.Interface;
	
BEGIN
	IF interface IS AosIPv6.Interface THEN
		(* Only IPv6 *)
		ipv6Interface := interface(AosIPv6.Interface);
		ipv6Interface.ReceivePacketTooBig(srcAdr, buffer);
	ELSE
		IF DEBUG THEN
			ASSERT(TRUE);
		END;
		AosNet.ReturnBuffer(buffer);
	END;
END ReceivePacketTooBig;


(** Reads Source or Target Link-Layer address option. Buffer.ofs has to be set to the Type byte*)
PROCEDURE LinkLayerAdrOption (VAR buffer: AosNet.Buffer; VAR linkAdr: AosNet.LinkAdr);
VAR
	i: LONGINT;
	
BEGIN
	IF DEBUG THEN
		(* Type is Source or Target Link *)
		ASSERT ((buffer.data[buffer.ofs] = 1X) OR (buffer.data[buffer.ofs] = 2X));
	END;

	FOR i := 0 TO 5 DO
		linkAdr[i] := buffer.data[buffer.ofs + i + 2];
	END;
	linkAdr[6] := 0X;
	linkAdr[7] := 0X;
	
	DEC(buffer.len, 8 * ORD(buffer.data[buffer.ofs + 1]));
	INC(buffer.ofs, 8 * ORD(buffer.data[buffer.ofs + 1]));					
END LinkLayerAdrOption;


(* Reads ICMP prefix information option *)
PROCEDURE PrefixInfoOption(VAR buffer: AosNet.Buffer; 
							   VAR onLink: BOOLEAN;
							   VAR autonomous: BOOLEAN;
							   VAR routerAddress: BOOLEAN;
							   VAR sitePrefix: BOOLEAN;
							   VAR validLifetime: LONGINT;
							   VAR preferredLifetime: LONGINT;
							   VAR sitePrefixLength: LONGINT;
							   VAR prefix: AosIP.Adr);
VAR
	flags: SET;
	i: LONGINT;
	
BEGIN
	prefix.data := ORD(buffer.data[buffer.ofs + 2]);
	
	flags := SYSTEM.VAL(SET, buffer.data[buffer.ofs + 3]);

	onLink := 7 IN flags;
	autonomous := 6 IN flags;
	routerAddress := 5 IN flags;
	sitePrefix := 4 IN flags;
	
	validLifetime := AosNet.GetNet4(buffer.data, buffer.ofs + 4);
	preferredLifetime := AosNet.GetNet4(buffer.data, buffer.ofs + 8);
	sitePrefixLength := ORD(buffer.data[buffer.ofs + 15]);
	
	prefix.usedProtocol := AosIP.IPv6;
	FOR i := 0 TO 15 DO
		prefix.ipv6Adr[i] := buffer.data[buffer.ofs + 16 + i]
	END;

	DEC(buffer.len, 8 * ORD(buffer.data[buffer.ofs + 1]));
	INC(buffer.ofs, 8 * ORD(buffer.data[buffer.ofs + 1]));	(* Length field times 8 bytes*)
END PrefixInfoOption;


(* Reads ICMP redirect header option *)
PROCEDURE RedirectHdrOption(VAR buffer: AosNet.Buffer);
BEGIN
	DEC(buffer.len, 8 * ORD(buffer.data[buffer.ofs + 1]));
	INC(buffer.ofs, 8 * ORD(buffer.data[buffer.ofs + 1]));	(* Length field times 8 bytes*)
END RedirectHdrOption;


(* Reads ICMP MTU option *)
PROCEDURE MTUOption(VAR buffer: AosNet.Buffer; VAR MTU: LONGINT);
BEGIN
	MTU := AosNet.GetNet4(buffer.data, buffer.ofs + 4);
	
	DEC(buffer.len, 8 * ORD(buffer.data[buffer.ofs + 1]));
	INC(buffer.ofs, 8 * ORD(buffer.data[buffer.ofs + 1]));	(* Length field times 8 bytes*)
END MTUOption;


(* Reads ICMP advertisement interval option *)
PROCEDURE AdvIntervalOption(VAR buffer: AosNet.Buffer);
BEGIN
	DEC(buffer.len, 8 * ORD(buffer.data[buffer.ofs + 1]));
	INC(buffer.ofs, 8 * ORD(buffer.data[buffer.ofs + 1]));	(* Length field times 8 bytes*)
END AdvIntervalOption;


(* Reads ICMP home agent information option *)
PROCEDURE HomeAgentInfoOption(VAR buffer: AosNet.Buffer);
BEGIN
	DEC(buffer.len, 8 * ORD(buffer.data[buffer.ofs + 1]));
	INC(buffer.ofs, 8 * ORD(buffer.data[buffer.ofs + 1]));	(* Length field times 8 bytes*)
END HomeAgentInfoOption;


(* Reads ICMP route information option *)
PROCEDURE RouteInfoOption(VAR buffer: AosNet.Buffer);
BEGIN
	DEC(buffer.len, 8 * ORD(buffer.data[buffer.ofs + 1]));
	INC(buffer.ofs, 8 * ORD(buffer.data[buffer.ofs + 1]));	(* Length field times 8 bytes*)
END RouteInfoOption;


PROCEDURE Cleanup();
VAR
	res: LONGINT;
	
BEGIN
	AosIPv6.sendNeighborSolicitation := NIL;
	AosIPv6.sendNeighborAdvertisement := NIL;
	AosIPv6.sendRouterSolicitation := NIL;
	AosIPv6.sendRouterAdvertisement := NIL;
	AosIPv6.icmpLinkLayerAdrOption := NIL;
	AosIPv6.icmpPrefixInfoOption := NIL;
	AosIPv6.icmpRedirectHdrOption := NIL;
	AosIPv6.icmpMTUOption := NIL;
	AosIPv6.icmpAdvIntervalOption := NIL;
	AosIPv6.icmpHomeAgentInfoOption := NIL;
	AosIPv6.icmpRouteInfoOption := NIL;
	
	(* Remove ICMP receivers *)
	RemoveReceiver(TypeEchoRequestv4, res);
	IF DEBUG THEN ASSERT (res = Ok) END;
	RemoveReceiver(TypeEchoRequestv6, res);
	IF DEBUG THEN ASSERT (res = Ok) END;
	RemoveReceiver(TypeNeighborSolicitation, res);
	IF DEBUG THEN ASSERT (res = Ok) END;
	RemoveReceiver(TypeNeighborAdvertisement, res);
	IF DEBUG THEN ASSERT (res = Ok) END;
	RemoveReceiver(TypeRouterAdvertisement, res);
	IF DEBUG THEN ASSERT (res = Ok) END;
	RemoveReceiver(TypeRouterSolicitation, res);
	IF DEBUG THEN ASSERT (res = Ok) END;
	RemoveReceiver(TypePacketTooBigv6, res);
	IF DEBUG THEN ASSERT (res = Ok) END;
	
	(* Remove IP receivers *)
	AosIP.RemoveReceiver(IPTypeICMPv4);
	AosIP.RemoveReceiver(IPTypeICMPv6);
END Cleanup;


PROCEDURE InitDelegates*();
BEGIN
	(* set delegates in AosIPv6 *)
	AosIPv6.sendNeighborSolicitation := SendNeighborSolicitation;
	AosIPv6.sendNeighborAdvertisement := SendNeighborAdvertisement;
	AosIPv6.sendRouterAdvertisement := SendRouterAdvertisement;
	AosIPv6.sendRouterSolicitation := SendRouterSolicitation;
	AosIPv6.sendICMPv6TimeExceeded := SendICMPv6TimeExceeded;
	AosIPv6.sendICMPv6ParamProb := SendICMPv6ParamProb;
	AosIPv6.icmpLinkLayerAdrOption := LinkLayerAdrOption;
	AosIPv6.icmpPrefixInfoOption := PrefixInfoOption;
	AosIPv6.icmpRedirectHdrOption := RedirectHdrOption;
	AosIPv6.icmpMTUOption := MTUOption;
	AosIPv6.icmpAdvIntervalOption := AdvIntervalOption;
	AosIPv6.icmpHomeAgentInfoOption := HomeAgentInfoOption;
	AosIPv6.icmpRouteInfoOption := RouteInfoOption;
END InitDelegates;


BEGIN	
	IF (AosIP.EchoReply) THEN
		(* install internal echoRequest receiver *)
		InstallReceiver(TypeEchoRequestv4, ReplyEcho, res);
		IF DEBUG THEN ASSERT (res = Ok) END;
		InstallReceiver(TypeEchoRequestv6, ReplyEcho, res);
		IF DEBUG THEN  ASSERT (res = Ok) END;
		
		(* Install neighbor discovery reiceivers *)
		InstallReceiver(TypeNeighborSolicitation, ReceiveNeighborSolicitation, res);
		IF DEBUG THEN ASSERT (res = Ok) END;
		InstallReceiver(TypeNeighborAdvertisement, ReceiveNeighborAdvertisement, res);
		IF DEBUG THEN ASSERT (res = Ok) END;
		
		(* Router Advertisement *)
		InstallReceiver(TypeRouterAdvertisement, ReceiveRouterAdvertisement, res);
		IF DEBUG THEN ASSERT (res = Ok) END;
		
		(* Router Solicitation *)
		InstallReceiver(TypeRouterSolicitation, ReceiveRouterSolicitation, res);
		IF DEBUG THEN ASSERT (res = Ok) END;
		
		(* Packet too big *)
		InstallReceiver(TypePacketTooBigv6, ReceivePacketTooBig, res);
		IF DEBUG THEN ASSERT (res = Ok) END;
	END;
	AosIP.InstallReceiver(IPTypeICMPv4, Input);
	AosIP.InstallReceiver(IPTypeICMPv6, Input);
	AosModules.InstallTermHandler(Cleanup);
END AosICMP.

(*
History:
21.10.2003	mvt	Created and moved the ICMP impelementation from the AosIP module to this one.
26.10.2003	mvt	Adapted to new design of AosIP.
02.05.2005	eb	IPv6 (Neighbor Discovery / EchoRequest / EchoReply
*)
