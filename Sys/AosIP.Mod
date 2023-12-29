(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosIP; (** AUTHOR "pjm, mvt"; PURPOSE "IP and ARP protocols"; *)

IMPORT SYSTEM, AosBoot, AosOut, AosKernel, AosClock, AosModules, AosNet;

(*
	IP Packet Header
	
	00	08	version & header length
		07..04	version = IPv4 (4)
		03..00	header length (4-byte units)
	01	08	type of service
	02	16	total length (bytes)
	04	16	identification
	06	16	fragmentation
		15..15	flag = 0
		14..14	DF - don't fragment
		13..13	MF - more fragments
		12..00	fragment offset (8-byte units)
	08	08	TTL
	09	08	protocol (1=ICMP, 6=TCP, 17=UDP)
	10	16	header checksum
	12	32	source address
	16	32	destination address
	20	--	options (0-40 bytes)
	--	--	data
	
	ARP Request/Reply Packet
	
	00	16	hardware type = 1 (ethernet)
	02	16	protocol type = 800H (IP)
	04	08	hardware length = 6
	05	08	protocol length = 4
	06	16	operation = 1 (request) or operation = 2 (reply)
	08	48	sender ethernet address
	14	32	sender ip address
	18	48	target ethernet address
	24	32	target ip address
	28	--	end
	
	Notes:
	o Bit numbers above are Intel bit order.
	o Avoid use of SET because of PPC bit numbering issues.
	o Always access fields as 8-, 16- or 32-bit values and use DIV, MOD, ASH, ODD for bit access.
*)

CONST
	(** Error codes *)
	Ok* = 0;
	DeviceAlreadyUsed* = 3901;
	DuplicateInterfaceName* = 3902;
	NoInterfaceName* = 3903;
	GatewayNotInSubnet* = 3904;

	MaxNofDNS* = 10; (** maximum number of DNS servers per interface *)
	
	(* ARP *)
	ARPHdrLen = 8;
	ARPPktLen = 28;
	EtherTypeARP = 806H;
	MinARPTime = 1000; (* minimum time between ARP requests in ms *)
	ARPMonitor = FALSE; (* monitor all ARP packets *)
	ARPHashSize = 256; (* size of ARP hash table *)
	
	(* IP *)
	MaxTTL* = 255; (** maximum time-to-live on outgoing datagrams *)
	TOS = 10X; (* type-of-service on outgoing datagrams *)
	IPv4 = 4; (* IP version for outgoing datagrams *)
	MinIPHdrLen = 20;
	MaxIPHdrLen = 60;
	EtherTypeIP = 800H;
	
	(** IP address constants *)
	NilAdr* = 0;
	BroadcastAdr* = 0FFFFFFFFH;

TYPE
	Adr* = LONGINT;	(** IP address type, stored in network byte order! *)
	
	Name* = ARRAY 128 OF CHAR; (** Name type for interface name *)
	
	ARPEntry = POINTER TO RECORD
		next: ARPEntry;
		ip: Adr;
		ether: AosNet.LinkAdr;
		sendTime, updateTime, updateDate: LONGINT;
		complete: BOOLEAN;
		buf: POINTER TO ARRAY OF CHAR; (* buffer for a packet waiting to be sent, NIL if none *)
	END;

TYPE
	(** IP interface. See note at the end of the module. *)
	
	Interface* = OBJECT
		VAR
			(** IP addresses of this interface *)
			localAdr-, maskAdr-, gatewayAdr-, subnetAdr-, broadAdr-: Adr;
			
			name-: Name; (** name of the interface *)
			
			(** Device that the interface belongs to *)
			dev-: AosNet.LinkDevice;
			
			(** DNS server list - can be used by DNS, not used in AosIP itself *)
			DNS-: ARRAY MaxNofDNS OF Adr; (* DNS server list *)
			DNScount-: LONGINT; (* number of DNS servers in list *)
			
			(* is interface already closed? *)
			closed-: BOOLEAN;
			
			(* ARP hash table *)
			table: ARRAY ARPHashSize OF ARPEntry;
			NARPEntries: LONGINT;
			
			next: Interface; (* next pointer for interface list *)
			
		(** Constructor - Open an IP interface and add it to the IP configuration.
			"name" must be a unique name for this interface (tested in "AddInterface").
			"dev" must be a AosNet.LinkDevice that is not used in other interfaces (tested in "AddInterface").
		*)
		PROCEDURE &Constr(name: Name; dev: AosNet.LinkDevice; VAR res: LONGINT);
		VAR
			i: LONGINT;
		BEGIN
			ASSERT(dev # NIL);
			SELF.dev := dev;
			
			(* set name *)
			IF name = "" THEN
				res := NoInterfaceName;
				RETURN;
			END;
			COPY(name, SELF.name);
			
			(* init addresses *)
			localAdr := NilAdr;
			maskAdr := NilAdr;
			gatewayAdr := NilAdr;
			subnetAdr := NilAdr;
			broadAdr := NilAdr;
			
			(* init ARP *)
			FOR i := 0 TO ARPHashSize-1 DO
				table[i] := NIL;
			END;
			NARPEntries := 0;
			
			(* init DNS *)
			DNScount := 0;
			
			closed := FALSE;
			AddInterface(SELF, res);
			
			IF res = Ok THEN
				(* install receivers *)
				dev.InstallReceiver(EtherTypeIP, IPInput);
				dev.InstallReceiver(EtherTypeARP, ARPInput);
			ELSE
				closed := TRUE;
			END;
		END Constr;
		
		(** Set addresses. Is normally called just after instanciation, but can also be called later, e.g. by DHCP.
			If "gatewayAdr" is "NilAdr", the subnet is considered to have no gateway, else it must be in the same
			subnet as the "localAdr".
			"domain" can be an empty string. It is normally used by a DNS implementation. It is not used in AosIP directly.
		*)
		
		PROCEDURE SetAdrs*(localAdr, maskAdr, gatewayAdr: Adr; VAR res: LONGINT);
		VAR maskSet: SET;
		BEGIN {EXCLUSIVE}
			(* set addresses *)
			SELF.localAdr := localAdr;
			SELF.maskAdr := maskAdr;
			SELF.gatewayAdr := gatewayAdr;
			
			(* compute other addresses *)
			maskSet := SYSTEM.VAL(SET, maskAdr);
			subnetAdr := SYSTEM.VAL(Adr, SYSTEM.VAL(SET, localAdr) * maskSet);
			broadAdr := SYSTEM.VAL(Adr, SYSTEM.VAL(SET, subnetAdr) + (-maskSet));
			
			IF (gatewayAdr # NilAdr) & ~SameSubnet(gatewayAdr, localAdr, maskAdr) THEN
				res := GatewayNotInSubnet;
			ELSE
				res := Ok;
			END;
		END SetAdrs;
		
		(** Add a domain name server to the interface. *)
		
		PROCEDURE DNSAdd*(adr: Adr);
		VAR i: LONGINT;
		BEGIN {EXCLUSIVE}
			(* concurrent lookup is consistent *)
			ASSERT(DNScount < MaxNofDNS);
			i := 0;
			WHILE i < DNScount DO
				IF DNS[i] = adr THEN RETURN END;
				INC(i)
			END;
			DNS[DNScount] := adr;
			INC(DNScount);
		END DNSAdd;
		
		(** Remove a domain name server from the interface. *)
		
		PROCEDURE DNSRemove*(adr: Adr);
		VAR i: LONGINT;
		BEGIN {EXCLUSIVE}
			(* concurrent lookup could result in a duplicate address in worst-case *)
			(* this happends hardly ever and is harmless for DNS anyway *)
			i := 0;
			WHILE (i < DNScount) & (DNS[i] # adr) DO
				INC(i)
			END;
			IF i < DNScount THEN
				INC(i);
				WHILE i < DNScount DO
					DNS[i-1] := DNS[i];
					INC(i);
				END;
				DEC(DNScount);
			END;
		END DNSRemove;

		(** Remove all domain name servers from the interface. *)
		
		PROCEDURE DNSRemoveAll*();
		BEGIN {EXCLUSIVE}
			DNScount := 0;
		END DNSRemoveAll;

		(** Send an IP packet on this interface. *)

		PROCEDURE Send*(type: LONGINT; fip: Adr; VAR l4hdr, data: ARRAY OF CHAR; h4len, dofs, dlen, TTL: LONGINT);
		VAR
			l3hdr: ARRAY MaxIPHdrLen OF CHAR;
		BEGIN
			IF closed THEN RETURN END; (* just in case of concurrent Send/Close *)
			
			(* set IP header *)
			l3hdr[0] := CHR(IPv4*10H + MinIPHdrLen DIV 4); (* IP version and header length *)
			l3hdr[1] := TOS; (* type-of-service *)
			AosNet.PutNet2(l3hdr, 2, MinIPHdrLen+h4len+dlen); (* total packet length *)
			AosNet.PutNet2(l3hdr, 4, GetNextID()); (* identification *)
			AosNet.Put2(l3hdr, 6, 0); (* fragmentation *)
			l3hdr[8] := CHR(TTL); (* time-to-live *)
			l3hdr[9] := CHR(type); (* IP type code *)
			AosNet.Put4(l3hdr, 12, localAdr); (* set local address *)
			AosNet.Put4(l3hdr, 16, fip); (* set foreign address *)
			AosNet.Put2(l3hdr, 10, 0); (* checksum := 0 *)
			IF ~(AosNet.ChecksumIP IN dev.calcChecksum) THEN
				AosNet.Put2(l3hdr, 10, Checksum2(l3hdr, 0, MinIPHdrLen, 0)); (* calculate checksum *)
			END;
			(* perform sending *)
			DoSend(fip, l3hdr, l4hdr, data, MinIPHdrLen, h4len, dofs, dlen);
		END Send;
		
		(* Internal procedure to perform the rest of the send operation. Used by "Send" and for IP forwarding. *)
		
		PROCEDURE DoSend(fip: Adr; VAR l3hdr, l4hdr, data: ARRAY OF CHAR; h3len, h4len, dofs, dlen: LONGINT);
		VAR
			dst: AosNet.LinkAdr;
		BEGIN
			IF h3len+h4len+dlen <= dev.mtu THEN
				IF dev.type = AosNet.TypeEthernet THEN
					IF fip = localAdr THEN
						(* send local loopback *)
						AosKernel.AtomicInc(NIPSentLocalLoopback);
						dev.Send(dst, EtherTypeIP, l3hdr, l4hdr, data, h3len, h4len, dofs, dlen, TRUE);
					ELSIF IsBroadcast(fip) (* (fip = broadAdr) OR  OR (fip = BroadcastAdr) OR (fip = OldBroadcastAdr)  *) THEN
						(* send broadcast *)
						AosKernel.AtomicInc(NIPSentBroadcast);
						dev.Send(dev.broadcast, EtherTypeIP, l3hdr, l4hdr, data, h3len, h4len, dofs, dlen, FALSE);
					ELSIF IsMulticast(fip) THEN
						(* Drop Multicast packet, NIY *)
					ELSE
						IF (gatewayAdr # NilAdr) & ~SameSubnet(fip, subnetAdr, maskAdr) THEN
							AosKernel.AtomicInc(NIPSentToGateway);
							fip := gatewayAdr;
						ELSE
							AosKernel.AtomicInc(NIPSentToSubnet);
						END;
						IF ARPLookup(fip, dst) THEN
							dev.Send(dst, EtherTypeIP, l3hdr, l4hdr, data, h3len, h4len, dofs, dlen, FALSE);
						ELSE
							ARPQueue(fip, l3hdr, l4hdr, data, h3len, h4len, dofs, dlen);
						END;
					END;
				ELSE
					(* AosNet.TypePointToPoint *)
					AosKernel.AtomicInc(NIPSentPointToPoint);
					dev.Send(dst, EtherTypeIP, l3hdr, l4hdr, data, h3len, h4len, dofs, dlen, (fip = localAdr));
				END;
			ELSE
				AosKernel.AtomicInc(NIPCantFragment);
			END;
		END DoSend;
		
		(* Receive an IP packet *)

		PROCEDURE IPInput(dev: AosNet.LinkDevice; type: LONGINT; buffer: AosNet.Buffer);
		VAR
			hlen, tlen, frag: LONGINT;
			src, dst: Adr;
			receiver: Receiver;
			int: Interface;
		BEGIN
			ASSERT(type = EtherTypeIP);
			ASSERT(dev = SELF.dev);
			AosKernel.AtomicInc(NIPRcvTotal);
			IF buffer.len >= MinIPHdrLen THEN
				IF SYSTEM.LSH(ORD(buffer.data[buffer.ofs]), -4) = IPv4 THEN
					hlen := ORD(buffer.data[buffer.ofs]) MOD 10H * 4;
					IF (hlen >= MinIPHdrLen) & (hlen <= MaxIPHdrLen) THEN
						IF (AosNet.ChecksumIP IN buffer.calcChecksum) OR (Checksum2(buffer.data, buffer.ofs, hlen, 0) = 0) THEN
							tlen := AosNet.GetNet2(buffer.data, buffer.ofs+2);
							IF (tlen >= hlen) & (tlen <= buffer.len) THEN
								IF tlen < buffer.len THEN
									(* size not used *)
									AosKernel.AtomicInc(NIPTrim);
									buffer.len := tlen;
								END;
								frag := AosNet.GetNet2(buffer.data, buffer.ofs+6);
								IF (frag = 0) OR (frag = 4000H) THEN (* not a fragment *)
									IF hlen # MinIPHdrLen THEN
										(* process options here *)
										AosKernel.AtomicInc(NIPOptions);
									END;
									src := AosNet.Get4(buffer.data, buffer.ofs+12);
									dst := AosNet.Get4(buffer.data, buffer.ofs+16);
									IF ~IsBroadcast(src) & ~IsMulticast(src) THEN
										IF (dst = localAdr) OR IsBroadcast(dst) (* (dst = broadAdr) OR
											(dst = BroadcastAdr) OR (dst = OldBroadcastAdr) *) THEN
											(* packet is for us *)
											type := ORD(buffer.data[buffer.ofs+9]);
											receiver := receivers[type];
											IF receiver # NIL THEN
												(* do receiver upcall *)
												buffer.l3ofs := buffer.ofs;
												INC(buffer.ofs, hlen);
												DEC(buffer.len, hlen);
												receiver(SELF, type, src, dst, buffer);
												AosKernel.AtomicInc(NIPDelivered);
												(* Exit here w/o returning buffer because it is passed to a receiver *)
												RETURN;
											ELSE
												AosKernel.AtomicInc(NIPNoReceiver);
											END;
										ELSIF IsMulticast(dst) THEN
											(* Drop multicast packet, NIY *)
										ELSIF IPForwarding THEN
											int := InterfaceByDstIP(dst);
											IF int # NIL THEN
												int.DoSend(dst, buffer.data, buffer.data, buffer.data, 0, 0, buffer.ofs, buffer.len);
												AosKernel.AtomicInc(NIPForwarded)
											ELSE
												AosKernel.AtomicInc(NIPNotForUs)
											END;
										ELSE
											AosKernel.AtomicInc(NIPNotForUs)
										END
									ELSE
										AosKernel.AtomicInc(NIPSrcIsBroadcast)
									END
								ELSE
									AosKernel.AtomicInc(NIPCantReassemble)
								END
							ELSE
								AosKernel.AtomicInc(NIPBadLength)
							END
						ELSE
							AosKernel.AtomicInc(NIPBadChecksum)
						END
					ELSE
						AosKernel.AtomicInc(NIPBadHdrLen)
					END
				ELSE
					AosKernel.AtomicInc(NIPBadVersion)
				END
			ELSE
				AosKernel.AtomicInc(NIPTooSmall)
			END;
			(* Exit and return buffer here because it is no longer used *)
			AosNet.ReturnBuffer(buffer);
		END IPInput;

		(* Receive an ARP packet *)

		PROCEDURE ARPInput(dev: AosNet.LinkDevice; type: LONGINT; buffer: AosNet.Buffer);
		VAR src, dst: Adr; forus: BOOLEAN;
		BEGIN
			AosKernel.AtomicInc(NARPRcvTotal);
			IF buffer.len >= ARPPktLen THEN
				IF AosNet.Equal(buffer.data, arpProto, buffer.ofs, 0, ARPHdrLen-1) THEN
					src := AosNet.Get4(buffer.data, buffer.ofs+14);
					dst := AosNet.Get4(buffer.data, buffer.ofs+24);
					IF src = localAdr THEN
						(* duplicate source address! *)
						AosKernel.AtomicInc(NARPRcvDuplicate);
						AosOut.Enter;
						AosOut.String("AosIP: Address "); OutAdr(src); AosOut.String(" hijacked by ");
						AosNet.OutLinkAdr(SYSTEM.VAL(AosNet.LinkAdr, buffer.data[buffer.ofs+8]), dev.adrSize); AosOut.Ln;
						AosOut.Exit;
					ELSIF (buffer.data[buffer.ofs+7] = 1X) OR (buffer.data[buffer.ofs+7] = 2X) THEN
						(* request or reply *)
						IF ~ODD(LONG(ORD(buffer.data[buffer.ofs+8]))) & (src # NilAdr) THEN
							forus := (dst = localAdr);
							ARPEnter(src, SYSTEM.VAL(AosNet.LinkAdr, buffer.data[buffer.ofs+8]), forus);
							IF (buffer.data[buffer.ofs+7] = 1X) & forus THEN
								(* request for us *)
								ARPReply(buffer.data, buffer.ofs);
							END;
						ELSE
							(* nil IP address or non-unicast ethernet address supplied *)
							AosKernel.AtomicInc(NARPBadAddr)
						END
					ELSE
						AosKernel.AtomicInc(NARPRcvIgnored)
					END
				ELSE
					AosKernel.AtomicInc(NARPRcvIgnored)
				END
			ELSE
				AosKernel.AtomicInc(NARPRcvTooSmall)
			END;
			(* Return the buffer *)
			AosNet.ReturnBuffer(buffer);
		END ARPInput;
		
		(* Send an ARP reply. Assume arp/ofs contains a valid ARP request packet. *)
		
		PROCEDURE ARPReply(VAR arp: ARRAY OF CHAR; ofs: LONGINT);
		BEGIN
			AosKernel.AtomicInc(NARPReply);
			arp[ofs+7] := 2X;	(* reply operation *)
			AosNet.Copy(arp, arp, ofs+8, ofs+18, 6+4); (* target := sender *)
			AosNet.Copy(dev.local , arp, 0, ofs+8, 6); (* sender ethernet address *)
			AosNet.Put4(arp, ofs+14, localAdr); (* sender ip address *)
			dev.Send(SYSTEM.VAL(AosNet.LinkAdr, arp[18]), EtherTypeARP, arp, arp, arp, 0, 0, ofs, ARPPktLen, FALSE);
		END ARPReply;

		(* Send an ARP request *)
		
		PROCEDURE ARPRequest(ip: Adr);
		VAR
			i: LONGINT;
			arp: ARRAY ARPPktLen OF CHAR;
		BEGIN
			AosKernel.AtomicInc(NARPRequest);
			AosNet.Copy(arpProto, arp, 0, 0, ARPHdrLen);
			arp[7] := 1X; (* request operation *)
			AosNet.Copy(dev.local, arp, 0, 8, 6); (* sender ethernet address *)
			AosNet.Put4(arp, 14, localAdr); (* sender ip address *)
			(* target ethernet address *)
			FOR i:= 18 TO 23 DO
				arp[i] := 0X;
			END;
			AosNet.Put4(arp, 24, ip); (* target ip address *)
			dev.Send(dev.broadcast, EtherTypeARP, arp, arp, arp, 0, 0, 0, ARPPktLen, FALSE);
		END ARPRequest;
		
		(* Look for the ethernet address matching the specified ip address. *)
		
		PROCEDURE ARPLookup(ip: Adr; VAR ether: AosNet.LinkAdr): BOOLEAN;
		VAR p: ARPEntry; c: BOOLEAN;
		BEGIN
			p := table[ARPHash(ip)];
			LOOP
				IF p = NIL THEN RETURN FALSE END;
				IF p.ip = ip THEN
					c := p.complete; (* to allow concurrent "Enter" *)
					ether := p.ether;
					RETURN c;
				END;
				p := p.next
			END
		END ARPLookup;

		(** Enumerate all ARP table entries. *)
		
		PROCEDURE ARPEnumerate*(handle: ARPHandler);
		VAR p: ARPEntry; i: LONGINT;
		BEGIN
			FOR i := 0 TO ARPHashSize-1 DO
				p := table[i];
				WHILE p # NIL DO
					handle(p.ip, p.complete, p.ether, 6, p.sendTime, p.updateTime, p.updateDate, i);
					p := p.next
				END
			END
		END ARPEnumerate;
		
		(* Update or add an ARP entry. *)
		
		PROCEDURE ARPEnter(ip: Adr; ether: AosNet.LinkAdr; forus: BOOLEAN);
		VAR
			p, q: ARPEntry;
			n: LONGINT;
			
			(* Create a new entry at the front of the hash list *)
			PROCEDURE NewEntry;
			BEGIN
				NEW(p);
				p.ip := ip;
				p.buf := NIL;
				p.sendTime := AosKernel.GetTimer() - minARPTime;
				p.complete := FALSE;
				p.next := table[n];
				table[n] := p;
				AosKernel.AtomicInc(NARPEntries);
			END NewEntry;
			
		BEGIN {EXCLUSIVE}
			n := ARPHash(ip);
			p := table[n];
			WHILE (p # NIL) & (p.ip # ip) DO
				p := p.next;
			END;
			IF (p = NIL) & (ARPMonitor OR forus) THEN
				NewEntry();
			END;
			IF p # NIL THEN	(* update address *)
				IF ARPMonitor & p.complete & ~AosNet.Equal(ether, p.ether, 0, 0, 6) THEN
					(* mapping changed! *)
					q := p.next;
					WHILE (q # NIL) & (~AosNet.Equal(ether, q.ether, 0, 0, 6) OR (q.ip # ip)) DO
						q := q.next
					END;
					IF q # NIL THEN (* we had this changed mapping before *)
						p := q; (* update it *)
					ELSE
						(* insert new mapping at front *)
						AosOut.Enter;
						AosOut.String("AosIP: Address for "); OutAdr(p.ip);
						AosOut.String(" changed from "); AosNet.OutLinkAdr(p.ether, 6);
						AosOut.String(" to "); AosNet.OutLinkAdr(ether, 6);
						AosOut.Exit;
						NewEntry();
					END;
				END;
				(* send queued packet *)
				IF p.buf # NIL THEN
					dev.Send(ether, EtherTypeIP, p.buf^, p.buf^, p.buf^, 0, 0, 0, LEN(p.buf^), FALSE);
					p.buf := NIL; (* 26.02.04 : fixes the resend bug *)
				END;
				(* update entry *)
				p.ether := ether;
				p.complete := TRUE;
				AosClock.Get(p.updateTime, p.updateDate);
			END
		END ARPEnter;

		(* Queue an IP packet awaiting an ARP reply. *)
		
		PROCEDURE ARPQueue(dst: Adr; VAR l3hdr, l4hdr, data: ARRAY OF CHAR; h3len, h4len, dofs, dlen: LONGINT);
		VAR p: ARPEntry; n: LONGINT;
		BEGIN {EXCLUSIVE}
			AosKernel.AtomicInc(NARPPut);
			n := ARPHash(dst);
			p := table[n];
			WHILE (p # NIL) & (p.ip # dst) DO
				p := p.next
			END;
			IF p = NIL THEN
				(* not found, create a new incomplete entry *)
				NEW(p);
				p.complete := FALSE;
				p.ip := dst;
				p.sendTime := AosKernel.GetTimer() - minARPTime;
				(* store one packet with the incomplete entry *)
				NEW(p.buf, h3len+h4len+dlen);
				AosNet.Copy(l3hdr, p.buf^, 0, 0, h3len);
				AosNet.Copy(l4hdr, p.buf^, 0, h3len, h4len);
				AosNet.Copy(data, p.buf^, dofs, h3len+h4len, dlen);
				(* publish the incomplete entry *)
				p.next := table[n];
				table[n] := p;
				AosKernel.AtomicInc(NARPEntries);
			END;
			IF p.complete THEN
				(* address arrived in the mean-time, so send the packet *)
				dev.Send(p.ether, EtherTypeIP, l3hdr, l4hdr, data, h3len, h4len, dofs, dlen, FALSE);
			ELSE
				(* (re-)send ARP request *)
				IF AosKernel.GetTimer() - p.sendTime >= minARPTime THEN
					ARPRequest(dst);
					p.sendTime := AosKernel.GetTimer();
				ELSE
					AosKernel.AtomicInc(NARPSkipped);
				END
			END
		END ARPQueue;
		
		(** Close and deactivate the interface, i.e. remove it from the configuration. *)
		
		PROCEDURE Close*();
		BEGIN {EXCLUSIVE}
			ASSERT(~closed);
			closed := TRUE;
			(* remove receivers *)
			dev.RemoveReceiver(EtherTypeIP);
			dev.RemoveReceiver(EtherTypeARP);
			RemoveInterface(SELF);
		END Close;
		
		(** Check if adr is a broadcast address *)
		
		PROCEDURE IsBroadcast*(adr: Adr) : BOOLEAN;
		BEGIN
			RETURN (adr = broadAdr) OR (adr = subnetAdr) OR (adr = BroadcastAdr)
		END IsBroadcast;
		
		(** Check if adr is a multicast address *)
		
		PROCEDURE IsMulticast*(adr: Adr) : BOOLEAN;
		VAR arr: ARRAY 4 OF CHAR;
		BEGIN
			AdrToArray(adr, arr, 0, FALSE);
			RETURN (ORD(arr[0]) >= 224) & (ORD(arr[0]) < 240)
		END IsMulticast;
		
	END Interface;

TYPE
	Receiver* = PROCEDURE {DELEGATE} (int: Interface; type: LONGINT; fip, lip: Adr; buffer: AosNet.Buffer);
	
	(** Handler for ARPPool.Enumerate. *)
	ARPHandler* = PROCEDURE {DELEGATE} (ip: Adr; complete: BOOLEAN; link: AosNet.LinkAdr; size, sendTime, updateTime, updateDate, hash: LONGINT);

	InterfaceHandler* = PROCEDURE {DELEGATE} (int: Interface);

VAR
	(* turn on/off IP forwarding *)
	IPForwarding*: BOOLEAN;
	
	(* Module variables *)
	i: LONGINT;
	nextID: INTEGER;
	s: ARRAY 3 OF CHAR; (* temporary string used in module body *)
	
	(* IP *)
	receivers: ARRAY 256 OF Receiver; (* registered receivers - array position is IP packet type code *)
	interfaces: Interface; (* list of all installed interfaces *)
	
	(* ARP *)
	arpProto: ARRAY ARPHdrLen OF CHAR;
	minARPTime: LONGINT;	(* minimum time between ARP requests in ticks *)

	(* IP counters *)
	NIPSentToSubnet, NIPSentToGateway, NIPSentBroadcast, NIPCantFragment,
	NIPRcvTotal, NIPTooSmall, NIPBadVersion, NIPOptions, NIPBadChecksum, 
	NIPBadLength, NIPTrim, NIPBadHdrLen, NIPNotForUs, NIPCantReassemble, NIPSrcIsBroadcast,
	NIPDelivered, NIPNoReceiver, NIPForwarded, NIPSentLocalLoopback, NIPSentPointToPoint: LONGINT;

	(* ARP counters *)
	NARPPut, NARPRcvTotal, NARPRcvTooSmall, NARPRcvIgnored, NARPRcvDuplicate, NARPBadAddr,
	NARPRequest, NARPReply, NARPSkipped: LONGINT;

(* Inline hash function for ARP hash table *)

PROCEDURE -ARPHash(ip: Adr): LONGINT;
CODE {SYSTEM.i386}
	(* hash := ip MOD ARPHashSize; *)
	POP EAX
	; Convert IP to host byte order
	XCHG AL, AH
	ROL EAX, 16
	XCHG AL, AH
	; MOD operation
	MOV EBX, ARPHashSize
	XOR EDX, EDX
	DIV EBX
	MOV EAX, EDX
END ARPHash;
		
(* Return a unique datagram ID *)

PROCEDURE GetNextID(): INTEGER;
BEGIN {EXCLUSIVE}
	INC(nextID);
	RETURN nextID;
END GetNextID;

(* Return TRUE if "adr1" and "adr2" are in the same subnet defined by "mask". *)

PROCEDURE -SameSubnet(adr1, adr2, mask: Adr): BOOLEAN;
CODE {SYSTEM.i386}
	POP ECX
	POP EBX
	POP EAX
	AND EAX, ECX
	AND EBX, ECX
	CMP EAX, EBX
	SETZ AL
END SameSubnet;

(* Add the interface to the IP configuration. *)

PROCEDURE AddInterface(int: Interface; VAR res: LONGINT);
VAR item: Interface;
BEGIN {EXCLUSIVE}
	(* Perform tests *)
	item := interfaces;
	WHILE item # NIL DO
		IF item.dev = int.dev THEN
			(* only one interface per device allowed *)
			res := DeviceAlreadyUsed;
			RETURN;
		END;
		IF item.name = int.name THEN
			res := DuplicateInterfaceName;
			RETURN;
		END;
		item := item.next;
	END;
	(* Add interface *)
	int.next := interfaces;
	interfaces := int;
	res := Ok;
END AddInterface;

(* Remove the interface from the IP configuration. *)

PROCEDURE RemoveInterface(int: Interface);
VAR item: Interface;
BEGIN {EXCLUSIVE}
	item := interfaces;
	IF item = NIL THEN
		(* empty list *)
	ELSIF item = int THEN
		(* remove first item *)
		interfaces := interfaces.next;
	ELSE
		WHILE item.next # int DO
			item := item.next;
		END;
		IF item.next # NIL THEN
			item.next := item.next.next;
		ELSE
			(* not found *)
		END;
	END;
END RemoveInterface;

(** Convert a dotted-decimal string to an ip address. Return NilAdr on failure. *)

PROCEDURE StrToAdr*(s: ARRAY OF CHAR): Adr;
VAR
	i, j, x: LONGINT;
	adr: ARRAY 4 OF CHAR;
	ok: BOOLEAN;
BEGIN
	i := 0; j := 0; x := -1; ok := FALSE;
	LOOP
		IF (s[i] = ".") OR (s[i] = 0X) THEN
			IF (x < 0) OR (x > 255) OR (j = 4) THEN EXIT END;
			adr[j] := CHR(x);
			IF s[i] = 0X THEN ok := (j = 3); EXIT END;
			x := -1; INC(i); INC(j)
		ELSIF (s[i] >= "0") & (s[i] <= "9") THEN
			IF x = -1 THEN x := 0 END;
			x := x*10 + (ORD(s[i])-ORD("0"));
			INC(i)
		ELSE
			EXIT
		END
	END;
	IF ok THEN
		RETURN SYSTEM.VAL(Adr, adr);
	ELSE
		RETURN NilAdr;
	END
END StrToAdr;

(** Convert an IP address to a dotted-decimal string (up to 16 characters). *)

PROCEDURE AdrToStr*(adr: Adr; VAR s: ARRAY OF CHAR);
VAR
	i, j, x: LONGINT;
	a: ARRAY 4 OF CHAR;
BEGIN
	ASSERT(LEN(s) >= 16);	(* enough space for largest result *)
	AosNet.Put4(a, 0, adr);
	i := 0;
	FOR j := 0 TO 3 DO
		x := ORD(a[j]);
		IF x >= 100 THEN s[i] := CHR(ORD("0")+x DIV 100); INC(i) END;
		IF x >= 10 THEN s[i] := CHR(ORD("0")+x DIV 10 MOD 10); INC(i) END;
		s[i] := CHR(ORD("0")+x MOD 10); INC(i);
		IF j = 3 THEN s[i] := 0X ELSE s[i] := "." END;
		INC(i)
	END
END AdrToStr;

(** Convert a 4-byte IP address from an array [ofs..ofs+3] to an Adr-type variable.
	If the LSB (least significant byte) is stored the the beginning [ofs], LSBfirst must be set to TRUE.
	(address "a.b.c.d" is stored as [d,c,b,a])
	If the LSB is stored at the end [ofs+3], LSBfirst must be set to FALSE.
	(address "a.b.c.d" is stored as [a,b,c,d])
*)
PROCEDURE ArrayToAdr*(VAR array: ARRAY OF CHAR; ofs: LONGINT; LSBfirst: BOOLEAN): Adr;
VAR adr: Adr;
BEGIN
	ASSERT(ofs+4 <= LEN(array)); (* index check *)
	SYSTEM.MOVE(SYSTEM.ADR(array[ofs]), SYSTEM.ADR(adr), 4);
	IF LSBfirst THEN
		SwapEndian(adr);
	END;
	RETURN adr;
END ArrayToAdr;

(** Convert an Adr-type variable as a 4-byte IP address into an array [ofs..ofs+3].
	If the LSB (least significant byte) should be stored the the beginning [ofs], LSBfirst must be set to TRUE.
	(address "a.b.c.d" is stored as [d,c,b,a])
	If the LSB should be stored at the end [ofs+3], LSBfirst must be set to FALSE.
	(address "a.b.c.d" is stored as [a,b,c,d])
*)
PROCEDURE AdrToArray*(adr: Adr; VAR array: ARRAY OF CHAR; ofs: LONGINT; LSBfirst: BOOLEAN);
BEGIN
	ASSERT(ofs+4 <= LEN(array)); (* index check *)
	IF LSBfirst THEN
		SwapEndian(adr);
	END;
	SYSTEM.MOVE(SYSTEM.ADR(adr), SYSTEM.ADR(array[ofs]), 4);
END AdrToArray;

(* Swap internal representation of an IP address from big to little endian or vice versa. *)

PROCEDURE -SwapEndian(VAR adr: Adr);
CODE {SYSTEM.i386}
	POP EAX
	MOV ECX, [EAX]
	XCHG CL, CH
	ROL ECX, 16
	XCHG CL, CH
	MOV [EAX], ECX
END SwapEndian;

(** Write an IP address. *)

PROCEDURE OutAdr*(adr: Adr);
VAR s: ARRAY 16 OF CHAR;
BEGIN
	AdrToStr(adr, s); AosOut.String(s);
END OutAdr;

(** Aos command: Output the configuration of all installed interfaces. *)

PROCEDURE IPConfig*(par: PTR): PTR;
BEGIN
	Enumerate(OutInterface);
	RETURN NIL;
END IPConfig;

(** Output the configuration of the specified interface. Can be used as Handler in Enumerate(). *)

PROCEDURE OutInterface*(int: Interface);
VAR i: LONGINT;
BEGIN
	IF int.closed THEN
		AosOut.Enter;
		AosOut.String("AosIP.OutInterface: Error: Interface already closed!"); AosOut.Ln;
		AosOut.Exit;
	ELSE
		AosOut.Enter; AosOut.Ln;
		AosOut.String("=== Interface ==="); AosOut.Ln;
		AosOut.String("Interface name: "); AosOut.String(int.name); AosOut.Ln;
		AosOut.String("Attached device: "); AosOut.String(int.dev.name);
		IF int.dev.Linked() = AosNet.LinkLinked THEN
			AosOut.String(" (LinkLinked)"); AosOut.Ln;
		ELSIF int.dev.Linked() = AosNet.LinkNotLinked THEN
			AosOut.String(" (LinkNotLinked)"); AosOut.Ln;
		ELSE
			AosOut.String(" (LinkUnknown)"); AosOut.Ln;
		END;
		AosOut.String("Local address: "); OutAdr(int.localAdr); AosOut.Ln;
		AosOut.String("Netmask: "); OutAdr(int.maskAdr); AosOut.Ln;
		AosOut.String("Gateway address: "); OutAdr(int.gatewayAdr); AosOut.Ln;
		AosOut.String("Subnet: "); OutAdr(int.subnetAdr); AosOut.Ln;
		AosOut.String("Net broadcast: "); OutAdr(int.broadAdr); AosOut.Ln;
		IF int.DNScount > 0 THEN
			FOR i:= 0 TO int.DNScount-1 DO
				AosOut.String("DNS server: "); OutAdr(int.DNS[i]); AosOut.Ln;
			END;
		ELSE
			AosOut.String("DNS server: none"); AosOut.Ln;
		END;
		AosOut.Exit;
	END;
END OutInterface;

(** First part of a split checksum operation. len must be non-zero and even. chk1 must be 0 at the beginning. The result can be passed to a following call to Checksum1(). The last chk1 result must be passed to Checksum2, which sums the data following sequentially on the data summed by this operation. Carries from bit 15 are accumulated in the top 16 bits, so at most 65535 words can be summed by Checksum1 and Checksum2 together. *)

PROCEDURE Checksum1*(VAR data: ARRAY OF CHAR; ofs, len, chk1: LONGINT): LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, chk1[EBP]
	MOV EBX, data[EBP]
	ADD EBX, ofs[EBP]
	MOV ECX, len[EBP]
	SHR ECX, 1
	JNC sloop
	PUSH 8	; ASSERT(~ODD(len))
	INT 3
sloop:
	MOVZX EDX, WORD 0[EBX]
	ADD EAX, EDX
	ADD EBX, 2
	DEC ECX
	JNZ sloop
END Checksum1;

(** Continue a checksum operation. len can be zero or odd. chk1 can be the result of Checksum1 for the immediately preceding data, or 0 for contiguous data. *)

PROCEDURE Checksum2*(VAR data: ARRAY OF CHAR; ofs, len, chk1: LONGINT): INTEGER;
CODE {SYSTEM.i386}
	MOV EAX, chk1[EBP]
	MOV EBX, data[EBP]
	ADD EBX, ofs[EBP]
	MOV ECX, len[EBP]
	SHR ECX, 1
	JZ eloop
sloop:
	MOVZX EDX, WORD 0[EBX]
	ADD EAX, EDX
	ADD EBX, 2
	DEC ECX
	JNZ sloop
eloop:
	TEST len[EBP], 1	; check for odd length
	JZ even
	MOVZX EDX, BYTE 0[EBX]	; add last byte
	ADD EAX, EDX
even:
	MOV ECX, EAX	; now add in all the carries
	SHR ECX, 16
	AND EAX, 0FFFFH
	ADD EAX, ECX
	MOV ECX, EAX	; add in additional carry
	SHR ECX, 16
	ADD EAX, ECX	; result is in low 16 bits of EAX
	NOT EAX
END Checksum2;

(** Return the interface on which packets with "dst" address should be sent. Return NIL if no interface matches. *)

PROCEDURE InterfaceByDstIP*(dst: Adr): Interface;
VAR item, gw: Interface;
BEGIN
	gw := NIL;
	item := interfaces;
	LOOP
		IF item = NIL THEN EXIT END;
		IF (item.localAdr # NilAdr) & (item.dev.Linked() # AosNet.LinkNotLinked) THEN
			IF SameSubnet(dst, item.subnetAdr, item.maskAdr) THEN
				EXIT;
			ELSIF (gw = NIL) & (item.subnetAdr # NilAdr) THEN
				gw := item;
			END;
		END;
		item := item.next;
	END;
	IF item # NIL THEN
		RETURN item;
	ELSE
		RETURN gw;
	END;
END InterfaceByDstIP;

(** Return the reference to an installed interface by its name.
	NIL is returned if no interface with this name was found.
*)
PROCEDURE InterfaceByName*(name: ARRAY OF CHAR): Interface;
VAR item: Interface;
BEGIN
	item := interfaces;
	WHILE (item # NIL) & (item.name # name) DO
		item := item.next;
	END;
	RETURN item;
END InterfaceByName;

(** Return the reference to an installed interface by its device.
	NIL is returned if no interface with this device was found.
*)
PROCEDURE InterfaceByDevice*(dev: AosNet.LinkDevice): Interface;
VAR item: Interface;
BEGIN
	item := interfaces;
	WHILE (item # NIL) & (item.dev # dev) DO
		item := item.next;
	END;
	RETURN item;
END InterfaceByDevice;

(** Enumerate all installed interfaces *)

PROCEDURE Enumerate*(handler: InterfaceHandler);
VAR item: Interface;
BEGIN
	item := interfaces;
	WHILE item # NIL DO
		handler(item);
		item := item.next;
	END;
END Enumerate;

(** Install a receiver for this type *)

PROCEDURE InstallReceiver*(type: LONGINT; r: Receiver);
BEGIN {EXCLUSIVE}
	ASSERT(r # NIL);
	ASSERT((type >=0) & (type <= 255));
	ASSERT(receivers[type] = NIL);
	receivers[type] := r;
END InstallReceiver;

(** Remove the currently installed receiver for this type *)

PROCEDURE RemoveReceiver*(type: LONGINT);
BEGIN {EXCLUSIVE}
	ASSERT((type >=0) & (type <= 255));
	ASSERT(receivers[type] # NIL);
	receivers[type] := NIL;
END RemoveReceiver;

PROCEDURE Cleanup();
BEGIN
	(* Remove all interfaces *)
	WHILE interfaces # NIL DO
		interfaces.Close();
	END;
END Cleanup;

BEGIN
	(* Get IPForwarding value. Default value is FALSE. *)
	AosBoot.GetConfig("IPForwarding", s);
	IPForwarding := (s = "1");
	(* Init ARP variables *)
	minARPTime := MinARPTime * AosKernel.second DIV 1000;
	arpProto[0] := 0X; arpProto[1] := 1X; (* hardware type ethernet *)
	arpProto[2] := CHR(EtherTypeIP DIV 100H); (* protocol type IP *)
	arpProto[3] := CHR(EtherTypeIP MOD 100H);
	arpProto[4] := 6X; arpProto[5] := 4X; (* lengths *)
	arpProto[6] := 0X; arpProto[7] := 0X; (* no operation *)
	(* Init receiver list *)
	FOR i:= 0 TO 255 DO
		receivers[i] := NIL;
	END;
	(* Init inteface list *)
	interfaces := NIL;
	nextID := 0;
	AosModules.InstallTermHandler(Cleanup);	
END AosIP.

(*
History:
11.10.2003	mvt	Changed for new AosNet interface
21.10.2003	mvt	Moved ICMP implementation to new AosICMP module
26.10.2003	mvt	Complete redesign to allow multiple interfaces
01.11.2003	mvt	Changed Adr type to be stored internally in network byte order (performance)
16.11.2003	mvt	Added support for checksum calclulation by the device.
25.11.2003	mvt	Added handling of AosNet.Buffer.l3hdr.
25.11.2003	mvt	Added TTL parameter in Send method.
17.12.2003	mvt	Changed reading from dev.linked to call to dev.Linked().
17.12.2003	mvt	Added procedures ArrayToAdr and AdrToArray.

How to use AosIP (mvt):
The module is loaded as soon as it is used first. It needn't to be loaded explicitly at startup. It can also be unloaded and reloaded without reboot.
At the beginning, no interfaces are defined. Do the following steps to add an interface:

1. NEW(int, "uniquename", dev, res);
Create a new instance of an interface and add it to the IP configuration.
"int" is of type "Interface". "dev" must be an instance of "AosNet.LinkDevice".
The name of the interface must be unique, i.e. not used by another interface.
The device must not be used by another Interface, too.
Test "res" whether any errors occurred, i.e. if the interface could be added successfully.

2. int.SetAdrs(localAdr, maskAdr, gatewayAdr);
Set the IP addresses/mask of the interface. See comment of "SetAdrs" method for details.

3. Optional: int.DNSAdd(DNSServer);

Normally, step 2 is done immedialtely after step 1. In some cases (e.g. DHCP), there is a bigger timespan between these two steps. During this time, the IP addresses are set to "NilAdr", i.e. the interface can only receive broadcast packets and it is ignored by the "InterfaceByDstIP" procedure.
Step 3 can be done multiple times for each DNS server to be added.

An interface can be closed and removed from the IP configuration by calling its "Close" method. This can be necessary if the device has been unplugged or uninstalled.

Notes (pjm):
o Touch header fields as little as possible (0 or 1 time).
o Common lookup functions should execute non-exclusively.
o Use hash tables for lookups.
o Avoid overuse of protocol constants. Often an unnamed constant with a comment is better to avoid code bloat.
o Sequential tests should be ordered according to probability of occurance.
o Identification field is only needed for fragmentation and is not important for small datagrams (< 576 bytes). For large datagrams, it should be identical for retransmitted datagrams.
o Terminology: A datagram may be fragmented into many packets.

Remark to the ARP implementation:
For parallelism, operations that traverse the hash table, but do not modify it, are not declared EXCLUSIVE. This means that operations modifying the table should be carefully programmed for this potential concurrent access to the .next pointers and the table pointers. Specifically, .next of a deleted node must not be set to NIL, because a traversal may be "looking" at this deleted node at the same time. This also means a deleted node may still be "found" if a concurrent search is in progress. All search functions should be considered as "hints" only, i.e. they should be followed by a call to an EXCLUSIVE procedure to confirm the result, if required. When moving a node to the front of a list, the correct order is: 1: prev.next := this.next; 2: this.next := root; 3: root := this. Between statements 1 and 3 the node is deleted temporarily, and a search operation might fail. A search visiting the node between statements 2 and 3 may re-search the part of the list before "this". Memory model issues should also be considered.

Testing from Linux
o ICMP reply: ping meadow
o Checksum odd length: ping meadow -s 1
o Unreachable port ICMP reply from UDP: traceroute meadow

BOOTP/DHCP - RFC951.Text, RFC2131.Text, RFC2132.Text
Router discovery - RFC1256.Text
*)
