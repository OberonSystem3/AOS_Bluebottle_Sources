(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosTCPServices; (** AUTHOR "pjm"; PURPOSE "Abstract TCP services"; *)

IMPORT AosOut, AosIP, AosTCP;

CONST
	Ok = AosTCP.Ok;
	
	Trace = FALSE;

TYPE
	Service* = OBJECT	(** TCP service object - handles opening and closing of connections *)
		VAR res: LONGINT; service, client: AosTCP.Connection; root, agent: Agent; new: NewAgent;
		
		(** Start is called indirectly by OpenService. *)
		
		PROCEDURE &Start(port: LONGINT; new: NewAgent; VAR res: LONGINT);
		BEGIN
			NEW(service); service.Open(port, AosIP.NilAdr, AosTCP.NilPort, res);
			IF res = Ok THEN
				NEW(root, NIL, NIL); root.next := NIL;
				SELF.new := new
			ELSE
				service := NIL
			END;
			IF Trace THEN
				AosOut.Enter; AosOut.String("Service "); AosOut.Int(port, 1);
				AosOut.String(" open "); AosOut.Int(res, 1); AosOut.Exit
			END
		END Start;
		
		PROCEDURE Remove(a: Agent);
		VAR p: Agent;
		BEGIN {EXCLUSIVE}
			p := root;
			WHILE (p.next # NIL) & (p.next # a) DO p := p.next END;
			IF p.next = a THEN p.next := a.next END
		END Remove;
		
		PROCEDURE Stop;
		VAR p, c: Agent;
		BEGIN {}	(* traversal can run concurrently with Remove and may see removed elements *)
			service.Close();
			p := root.next;
			WHILE p # NIL DO
				c := p; p := p.next;	(* p.next is modified by Remove *)
				c.Stop()
			END;
			BEGIN {EXCLUSIVE}
				AWAIT(root.next = NIL);	(* wait for all agents to remove themselves *)
				AWAIT(new = NIL)	(* wait for service to terminate *)
			END
		END Stop;
		
	BEGIN {ACTIVE}
		IF service # NIL THEN
			LOOP
				service.Accept(client, res);
				IF res # Ok THEN EXIT END;
				agent := new(client, SELF);
				BEGIN {EXCLUSIVE}
					agent.next := root.next; root.next := agent
				END
			END;
			IF Trace THEN
				AosOut.Enter; AosOut.String("Service "); AosOut.Int(service.lport, 1);
				AosOut.String(" result "); AosOut.Int(res, 1); AosOut.Exit
			END
		END;
		BEGIN {EXCLUSIVE}
			new := NIL	(* signal to Stop *)
		END
	END Service;

TYPE
	Agent* = OBJECT	(** abstract TCP agent object - should be extended with an active body using "client". *)
		VAR
			client-: AosTCP.Connection;	(** TCP connection to the client *)
			next: Agent; s: Service;
		
		(** Start is called indirectly by the Service object. *)
		
		PROCEDURE &Start(c: AosTCP.Connection; s: Service);
		VAR str: ARRAY 32 OF CHAR;
		BEGIN
			SELF.client := c; SELF.s := s;
			IF Trace & (c # NIL) THEN
				AosIP.AdrToStr(c.fip, str);
				AosOut.Enter; AosOut.String("Agent "); AosOut.Int(c.lport, 1);
				AosOut.String(" connected to "); AosOut.String(str);
				AosOut.Char(" "); AosOut.Int(c.fport, 1); AosOut.Exit
			END
		END Start;
		
		PROCEDURE Stop;	(* called from outside to stop an agent *)
		BEGIN
			client.Close()
		END Stop;
		
		(** Terminate is called by the body of the extended object to terminate itself. *)
		
		PROCEDURE Terminate*;
		BEGIN
			client.Close();
			s.Remove(SELF)
		END Terminate;
		
	END Agent;

		(** A "factory" procedure for agent extensions.  Used by a service object. *)
	NewAgent* = PROCEDURE (c: AosTCP.Connection; s: Service): Agent;

(** Open a new service.  The service parameter returns the new service object, or NIL on failure.  The port parameter specifies the TCP port number of the service.  The new parameter specifies a factory procedure for agent objects to handle the connection. *)
  
PROCEDURE OpenService*(VAR service: Service; port: LONGINT; new: NewAgent);
VAR res: LONGINT;
BEGIN
	IF service = NIL THEN
		NEW(service, port, new, res);
		IF res # Ok THEN service := NIL END
	END
END OpenService;

(** Close a service.  The service parameter returns NIL. *)

PROCEDURE CloseService*(VAR service: Service);
BEGIN
	IF service # NIL THEN service.Stop(); service := NIL END
END CloseService;

END AosTCPServices.

(**
Notes

This module provides a framework for TCP services utilizing active objects as agents.  A Service object is responsible for managing incoming connections from clients.  It creates one (active) Agent object instance per client, to provide the actual service.

A user of this module should extend the Agent object with an active body.  The body can use the client field to access its client connection.  The client field is a TCP connection object with the Send and Receive methods for sending and receiving data.  When the connection is closed by the client, the Receive method will return an error code (res # 0).  In this case the Agent object must call the Terminate method in its base record, to signal to the Service object that it is terminating.

Because the Service object needs to create arbitrary Agent extension objects, it needs a "factory procedure" to allocate such agent extensions.  The factory procedure is passed to the Service object when it is allocated, and it is called by the Service object every time it needs to create a new agent, i.e., every time a new client connection arrives.  The factory procedure should allocate the extended object instance, and return it.  This is perhaps best illustrated by an example.

The following agent implements the TCP discard service.  This service accepts connections, and discards everything that arrives on the connection, until it is closed by the client.

TYPE
	DiscardAgent = OBJECT (AosTCPServices.Agent)
		VAR len, res: LONGINT; buf: ARRAY 4096 OF CHAR;
		
	BEGIN {ACTIVE}
		REPEAT
			client.Receive(buf, 0, LEN(buf), LEN(buf), len, res)
		UNTIL res # Ok;
		Terminate
	END DiscardAgent;

PROCEDURE NewDiscardAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
VAR a: DiscardAgent;
BEGIN
	NEW(a, c, s); RETURN a
END NewDiscardAgent;

To open the discard service:
	VAR discard: AosTCPServices.Service;
	AosTCPServices.OpenService(discard, 9, NewDiscardAgent);	(* use TCP port 9 *)

This creates a Service object, which waits actively for TCP connections on port 9.  Every time a connection arrives, it calls NewDiscardAgent to allocate a DiscardAgent active object.  The DiscardAgent accesses the client connection through the client field.

Currently there is no limit to the number of connections that can be accepted by a Service object.  A simple denial-of-service attack would be to open many connections to an existing port.

To close the discard service:
	AosTCPServices.CloseService(discard);
*)

(*
to do:
o limit number of client connections
o re-use agents?
o clean up "dead" clients periodically (user-specified timeout?)
*)
