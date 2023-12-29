(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosUDP; (** AUTHOR "pjm, mvt"; PURPOSE "UDP protocol"; *)

(*
	UDP Header
	
	00	16	source port
	02	16	destination port
	04	16	UDP length (header and data)
	06	16	UDP checksum (pseudo-header, header and data)
	08	--	optional data
	
	UDP Pseudo-header (for checksum calculation)
	
	00	32	source address
	04	32	destination address
	08	08	zero = 0
	09	08	protocol = 17
	10	16	UDP length (duplicate)
	
	Notes:
	o Bit numbers above are Intel bit order.
	o Avoid use of SET because of PPC bit numbering issues.
	o Always access fields as 8-, 16- or 32-bit values and use DIV, MOD, ASH, ODD for bit access.
*)

IMPORT SYSTEM, AosModules, AosKernel, AosActive, AosNet, AosIP, AosICMP;

CONST
	(** Error codes *)
	Ok* = 0;
	PortInUse* = 3501;
	Timeout* = 3502;
	BufferOverflow* = 3503;
	NoInterface* = 3504;
	
	NilPort* = 0;
	
	IPTypeUDP = 17; (* UDP type code for IP packets *)
	UDPHdrLen = 8;
	PseudoHdrLen = 12;
	MaxUDPDataLen = 10000H-UDPHdrLen;
	
	MinEphemeralPort = 1024;
	MaxEphemeralPort = 5000;
	
	QueueSize = 40; (* size (number of packets) of receive queue per socket *)
	HashTableSize = 128; (* size of connection lookup hash table *)
	
TYPE
	(** Socket. Stores the state of a UDP communication endpoint. *)
	
	Socket* = OBJECT
		VAR
			next: Socket; (* link for socket pool *)
			lport: LONGINT; (* local port *)
			
			hdr: ARRAY UDPHdrLen OF CHAR; (* UDP prototype header for sending *)
			pseudoHdr: ARRAY PseudoHdrLen OF CHAR; (* pseudo header for calculating checksum *)
			
			(* Receive queue (ring buffer) *)
			queue: ARRAY QueueSize OF AosNet.Buffer;
			queueFirst: LONGINT; (* index where the new items are queued *)
			queueLast: LONGINT; (* index where the items are removed from the queued *)

			(* Variables for handling timeout *)
			timer: AosActive.Timer;
			timeout: BOOLEAN;
	
		(** Constructor *)
		
		PROCEDURE &Open(lport: LONGINT; VAR res: LONGINT);
		BEGIN
			ASSERT((lport >= 0) & (lport < 10000H));
			SELF.lport := lport;
			IF pool.AddSocket(SELF) THEN
				(* set first part of UDP header *)
				AosNet.PutNet2(hdr, 0, SELF.lport);
				(* set up buffering and blocking *)
				queueFirst := 0;
				queueLast := 0;
				NEW(timer);
				res := Ok;
			ELSE
				res := PortInUse;
			END
		END Open;

		(** Send a UDP datagram to the foreign address specified by "fip" and "lport". 
			The data is in "data[ofs..ofs+len-1]".  In case of concurrent sends the datagrams are serialized.
		*)
		PROCEDURE Send*(fip: AosIP.Adr; fport: LONGINT; VAR data: ARRAY OF CHAR; ofs, len: LONGINT; VAR res: LONGINT);
		VAR
			int: AosIP.Interface;
		BEGIN {EXCLUSIVE}
			ASSERT((fport >= 0) & (fport < 10000H));
			ASSERT((len >= 0) & (len <= MaxUDPDataLen));
			int := AosIP.InterfaceByDstIP(fip);
			IF int # NIL THEN
				DoSend(int, fip, fport, data, ofs, len);
				res := Ok;
			ELSE
				res := NoInterface;
			END;
		END Send;
		
		(** Send a broadcast UDP datagram via interface "int" to port "lport". Normally only used by DHCP.
			The data is in "data[ofs..ofs+len-1]".  In case of concurrent sends the datagrams are serialized.
		*)
		PROCEDURE SendBroadcast*(int: AosIP.Interface; fport: LONGINT; VAR data: ARRAY OF CHAR; ofs, len: LONGINT);
		BEGIN {EXCLUSIVE}
			ASSERT((fport >= 0) & (fport < 10000H));
			ASSERT((len >= 0) & (len <= MaxUDPDataLen));
			DoSend(int, AosIP.BroadcastAdr, fport, data, ofs, len);
		END SendBroadcast;
		
		(** Receive a UDP datagram.  If none is available, wait up to the specified timeout for one to arrive.
		"data[ofs..ofs+size-1]" is the data buffer to hold the returned datagram.
		"ms" is a wait timeout value in milliseconds, 0 means "don't wait", -1 means "infinite wait".
		On return, "fip" and "fport" hold the foreign address and port.
		"len" returns the actual datagram size and "data[ofs..ofs+len-1]" returns the data.
		"res" returns "Timeout" in case of a timeout and "BufferOverflow" if the received datagram was too big.
		*)
		PROCEDURE Receive*(VAR data: ARRAY OF CHAR; ofs, size, ms: LONGINT; VAR fip: AosIP.Adr; VAR fport, len, res: LONGINT);
		VAR buffer: AosNet.Buffer;
		BEGIN {EXCLUSIVE}
			IF queueFirst = queueLast THEN
				(* queue empty *)
				IF ms > 0 THEN
					timeout := FALSE;
					AosActive.SetTimeout(timer, DoTimeout, ms);
					AWAIT((queueFirst # queueLast) OR timeout);
					IF timeout THEN
						res := Timeout;
						RETURN;
					ELSE
						AosActive.CancelTimeout(timer);
						(* now we can continue *)
					END;
				ELSIF ms = -1 THEN
					(* infinite wait *)
					AWAIT(queueFirst # queueLast);
				ELSE
					res := Timeout;
					RETURN;
				END;
			END;
			(* Here we can get a packet from the queue *)
			buffer := queue[queueLast];
			queueLast := (queueLast + 1) MOD QueueSize;
			
			fip := buffer.int; (* IP address of origin is stored in "int" field of buffer type *)
			fport := AosNet.GetNet2(buffer.data, buffer.ofs);
			len := buffer.len - UDPHdrLen;
			IF len > size THEN
				(* packet too big for receive buffer *)
				res := BufferOverflow;
			ELSE
				AosNet.Copy(buffer.data, data, buffer.ofs+UDPHdrLen, ofs, len);
				res := Ok;
			END;
			AosNet.ReturnBuffer(buffer);
		END Receive;
		
		(* Internal send operation. Called from "Send" and "SendBroadcast". *)

		PROCEDURE DoSend(int: AosIP.Interface; fip: AosIP.Adr; fport: LONGINT; VAR data: ARRAY OF CHAR; ofs, len: LONGINT);
		VAR sum: LONGINT;
		BEGIN
			(* set UDP header *)
			AosNet.PutNet2(hdr, 2, fport); (* foreign port *)
			AosNet.PutNet2(hdr, 4, len+UDPHdrLen); (* UPD length *)
			AosNet.Put2(hdr, 6, 0); (* checksum := 0 *)
			
			IF ~(AosNet.ChecksumUDP IN int.dev.calcChecksum) THEN
				(* set pseudo header *)
				AosNet.Put4(pseudoHdr, 0, int.localAdr); (* local IP address *)
				AosNet.Put4(pseudoHdr, 4, fip); (* foreign IP address *)
				AosNet.PutNet2(pseudoHdr, 8, IPTypeUDP); (* IP type code of UDP *)
				AosNet.PutNet2(pseudoHdr, 10, len+UDPHdrLen); (* UPD length *)
				
				sum := AosIP.Checksum1(pseudoHdr, 0, PseudoHdrLen, 0);
				sum := AosIP.Checksum1(hdr, 0, UDPHdrLen, sum);
				sum := AosIP.Checksum2(data, ofs, len, sum);
				
				AosNet.Put2(hdr, 6, sum); (* checksum := sum *)
			END;
			
			int.Send(IPTypeUDP, fip, hdr, data, UDPHdrLen, ofs, len, AosIP.MaxTTL);
		END DoSend;
		
		(* Handle timeout call from AosActive *)
		
		PROCEDURE DoTimeout();
		BEGIN {EXCLUSIVE}
			timeout := TRUE;
		END DoTimeout;

		(* Input a datagram on this socket. *)
		
		PROCEDURE Input(fip: AosIP.Adr; buffer: AosNet.Buffer);
		BEGIN {EXCLUSIVE}
			IF (queueLast - queueFirst) MOD QueueSize = 1 THEN
				(* queue full - discard packet and return buffer *)
				AosKernel.AtomicInc(NUDPQueueOverflow);
				AosNet.ReturnBuffer(buffer);
			ELSE
				(* use the "int" field of the buffer type to store the IP address of the origin *)
				buffer.int := fip;
				queue[queueFirst] := buffer;
				queueFirst := (queueFirst + 1) MOD QueueSize;
				AosKernel.AtomicInc(NUDPQueued);
			END;
		END Input;
		
		(** Close the Socket, freeing its address for re-use. *)
		
		PROCEDURE Close*();
		BEGIN {EXCLUSIVE}
			pool.RemoveSocket(SELF);
			AosActive.CancelTimeout(timer);
			(* return all queued buffers *)
			WHILE queueFirst # queueLast DO
				AosNet.ReturnBuffer(queue[queueLast]);
				queueLast := (queueLast + 1) MOD QueueSize;
			END;
			(* do not touch any other fields, as instance may still be in use via pool.Lookup. *)
		END Close;
		
	END Socket;
	
	(* Socket pool *)
	
	SocketPool = OBJECT
		VAR
			table: ARRAY HashTableSize OF Socket;
			eport: LONGINT;
		
		(* Initialize the pool. *)
		
		PROCEDURE &Init;
		VAR i: LONGINT;
		BEGIN
			FOR i := 0 TO HashTableSize-1 DO
				table[i] := NIL;
			END;
			eport := MinEphemeralPort;
		END Init;
		
		(* Look for the specified Socket *)
		
		PROCEDURE Lookup(lport: LONGINT): Socket;
		VAR item: Socket;
		BEGIN
			item := table[HashPool(lport)];
			WHILE (item # NIL) & (item.lport # lport) DO
				item := item.next;
			END;
			RETURN item;
		END Lookup;

		(* Add a socket to the pool. If lport is NilPort, an ephemeral port is assigned. *)
		
		PROCEDURE AddSocket(p: Socket): BOOLEAN;
		VAR
			item: Socket;
			ok: BOOLEAN;
			i, sport: LONGINT;
		BEGIN {EXCLUSIVE}
			IF p.lport = NilPort THEN
				(* find an unused ephemeral port *)
				sport := eport; (* store port where the search started *)
				REPEAT
					p.lport := eport;
					(* check if port is in use *)
					ok := (Lookup(eport) = NIL);
					INC(eport);
					IF eport > MaxEphemeralPort THEN
						eport := MinEphemeralPort;
					END;
				UNTIL ok OR (eport = sport);
				(* ok is TRUE here if the port is not used yet *)
			ELSE
				(* ensure port is not in use *)
				ok := (Lookup(p.lport) = NIL);
			END;
			IF ok THEN
				i := HashPool(p.lport);
				p.next := table[i];
				table[i] := p;
			END;
			RETURN ok;
		END AddSocket;
		
		(* Remove the Socket from the pool, making its address re-usable. *)
		
		PROCEDURE RemoveSocket(p: Socket);
		VAR
			i: LONGINT;
			item: Socket;
		BEGIN {EXCLUSIVE}
			i := HashPool(p.lport);
			IF table[i] = NIL THEN
				(* not found *)
			ELSIF table[i] = p THEN
				table[i] := table[i].next;
			ELSE
				item := table[i];
				WHILE (item.next # NIL) & (item.next # p) DO
					item := item.next;
				END;
				IF item.next # NIL THEN
					item.next := item.next.next;
				END;
			END;
			(* do not clear p.next, because Lookup may be looking at it *)
		END RemoveSocket;
		
		(* Close all sockets that are registered in pool *)
		
		PROCEDURE CloseAll();
		VAR i: LONGINT;
		BEGIN
			FOR i := 0 TO HashTableSize-1 DO
				WHILE table[i] # NIL DO
					table[i].Close();
				END;
			END;
		END CloseAll;

	END SocketPool;
	
VAR
	(* Module variables *)
	pool: SocketPool;
	
	(* Statistic variables *)
	NUDPRcvTotal, NUDPTooSmall, NUDPBadChecksum, NUDPRcvBroadcast, NUDPUnknownPort,
	NUDPQueued, NUDPQueueOverflow, NUDPTrim, NUDPBadHdrLen: LONGINT;

(* Send an ICMP "port unreachable" error message *)

PROCEDURE SendICMPError(fip: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	IPHdrLen: LONGINT; (* length of IP header to copy *)
	icmpMsg: ARRAY 72 OF CHAR; (* unused (4) + MaxIPHdrLen (60) + UDPHdrLen (8) *)
BEGIN
	IPHdrLen := buffer.ofs - buffer.l3ofs;
	AosNet.Put4(icmpMsg, 0, 0); (* unused *)
	AosNet.Copy(buffer.data, icmpMsg, buffer.l3ofs, 4, IPHdrLen + UDPHdrLen); (* IP header UDP header *)
	AosICMP.Send(fip, icmpMsg, 0, 4+IPHdrLen+UDPHdrLen, AosICMP.TypeDstUnreachable, 3, AosIP.MaxTTL);
END SendICMPError;

(* Receive a UDP datagram. *)

PROCEDURE Input(int: AosIP.Interface; type: LONGINT; fip, lip: AosIP.Adr; buffer: AosNet.Buffer);
VAR
	(* pseudo header for calculating checksum *)
	pseudoHdr: ARRAY PseudoHdrLen OF CHAR;
	sum, tlen: LONGINT;
	s: Socket;
BEGIN
	AosKernel.AtomicInc(NUDPRcvTotal);
	IF buffer.len >= UDPHdrLen THEN
		tlen := AosNet.GetNet2(buffer.data, buffer.ofs+4);
		IF (tlen >= UDPHdrLen) & (tlen <= buffer.len) THEN
			IF tlen < buffer.len THEN
				(* size not used *)
				AosKernel.AtomicInc(NUDPTrim);
				buffer.len := tlen;
			END;
			IF AosNet.ChecksumUDP IN buffer.calcChecksum THEN
				sum := 0;
			ELSE
				sum := AosNet.Get2(buffer.data, buffer.ofs+6); (* get checksum from header *)
			END;
			IF sum # 0 THEN
				(* calculate checksum *)
				(* set pseudo header *)
				AosNet.Put4(pseudoHdr, 0, fip); (* foreign IP address *)
				AosNet.Put4(pseudoHdr, 4, lip); (* local IP address *)
				AosNet.PutNet2(pseudoHdr, 8, IPTypeUDP); (* IP type code of UDP *)
				AosNet.PutNet2(pseudoHdr, 10, buffer.len); (* UPD length *)
				sum := AosIP.Checksum1(pseudoHdr, 0, PseudoHdrLen, 0);
				sum := AosIP.Checksum2(buffer.data, buffer.ofs, tlen, sum);
			END;
			IF sum = 0 THEN
				s := pool.Lookup(AosNet.GetNet2(buffer.data, buffer.ofs+2));
				IF s # NIL THEN
					s.Input(fip, buffer);
					(* Exit here w/o returning buffer because it is passed to Socket.Input *)
					RETURN;
				ELSIF ~int.IsBroadcast(lip) (* fip # AosIP.BroadcastAdr *)THEN
					AosKernel.AtomicInc(NUDPUnknownPort);
					SendICMPError(fip, buffer); 
				END;
			ELSE
				AosKernel.AtomicInc(NUDPBadChecksum);
			END;
		ELSE
			AosKernel.AtomicInc(NUDPBadHdrLen);
		END;
	ELSE
		AosKernel.AtomicInc(NUDPTooSmall);
	END;
	(* Exit and return buffer here because it is no longer used *)
	AosNet.ReturnBuffer(buffer);
END Input;

(* Hash function for SocketPool. *)

PROCEDURE -HashPool(lport: LONGINT): LONGINT;
CODE {SYSTEM.i386}
	(* hash := lport MOD HashTableSize; *)
	POP EAX
	; MOD operation
	MOV EBX, HashTableSize
	XOR EDX, EDX
	DIV EBX
	MOV EAX, EDX
END HashPool;

PROCEDURE Cleanup();
BEGIN
	AosIP.RemoveReceiver(IPTypeUDP);
	pool.CloseAll();
END Cleanup;

BEGIN
	NEW(pool);
	AosIP.InstallReceiver(IPTypeUDP, Input);
	AosModules.InstallTermHandler(Cleanup);	
END AosUDP.

(*
History:
27.10.2003	mvt	Complete internal redesign for new interfaces of AosNet and AosIP.
22.11.2003	mvt	Changed SocketPool to work with a hash table.
*)
