(* Patrick Stuedi, 30.08.01 *)

MODULE RfsConnection; (** AUTHOR "pstuedi"; PURPOSE "Remote File System connections"; *)

IMPORT AosTCP, AosDNS, AosIP, SYSTEM, AosOut;

CONST 
	MaxNameLen = 64;
	OpenTimeout = 10000;
	

TYPE
	(** Wrapper for AosTCP.Connection so that AosTCP.Connection shouldn't Trap **)
	Connection* = OBJECT 
		VAR 
			rpcConn: AosTCP.Connection;
			host: ARRAY MaxNameLen OF CHAR; 
			port: INTEGER;
						
		PROCEDURE &Init*(host: ARRAY OF CHAR; port: INTEGER);
			VAR len: LONGINT;
		BEGIN			
			len := Len(host);	
			CopyBuffer(host, len + 1, SELF.host, 0);
			SELF.host[len] := 0X;
			SELF.port := port;
			NEW(rpcConn);
	END Init;
		
		(** res = 0 if Connection opened *)
		PROCEDURE Open*(VAR res: LONGINT);
			VAR ip: LONGINT;
		BEGIN
			IF rpcConn.state = AosTCP.Unused THEN
				AosDNS.HostByName(host, ip, res);
				IF res # AosDNS.Ok THEN
					AosOut.String("Connection->konnte DNS nicht aufloesen");
					AosOut.Ln;
				ELSE
					rpcConn.Open(AosTCP.NilPort, ip, port, res);
					IF res # AosTCP.Ok THEN
						AosOut.String("Connection->error in Opening, res: ");
						AosOut.Int(res, 12);
					ELSE
						AwaitState(AosTCP.OpenStates, AosTCP.ClosedStates, OpenTimeout, res);
						IF res # AosTCP.Ok THEN
							AosOut.String("Connection->bad state ");
							AosOut.Int(res, 6);
							AosOut.Ln;
						ELSE
							AosOut.String("Connection->connection Opened");
							AosOut.Ln;
						END;
					END;
				END;			
			ELSE
				res := AosTCP.NotConnected;
				AosOut.String("Connection->connection used");
				AosOut.Ln;
			END;
		END Open;
		
		PROCEDURE Close*();
		BEGIN
			rpcConn.Close;
		END Close;
				
		(** If Connection down, Receive tries to connect again **)
		PROCEDURE Receive*(VAR buf: ARRAY OF CHAR; off, len: LONGINT; VAR received, res: LONGINT);
			VAR counter: LONGINT;
		BEGIN{EXCLUSIVE}
			received := 0;
			res := AosTCP.NotConnected;
			IF off < 0 THEN
				AosOut.String("Connection->receive: off not valid");
				AosOut.Ln;
				RETURN;
			ELSIF len < 0 THEN
				AosOut.String("Connection->receive: len not valid");
				AosOut.Ln;
				RETURN;
			ELSIF off + len > LEN(buf) THEN
				AosOut.String("Connection->bufferspace to small");
				AosOut.Ln;				
				RETURN;
			END;			
			rpcConn.Receive(buf, off, len, len, received, res);
		END Receive;
		
		(** if the connection is down Send tries to connect again **)
		PROCEDURE Send*(VAR buf: ARRAY OF CHAR; off, len: LONGINT; VAR res: LONGINT);
			VAR counter: LONGINT;
		BEGIN{EXCLUSIVE}
			res := AosTCP.NotConnected;
			IF off < 0 THEN
				AosOut.String("Connection->send: off not valid");
				AosOut.Ln;
				RETURN;
			ELSIF len < 0 THEN
				AosOut.String("Connection->send: len not valid");
				AosOut.Ln;
				RETURN;
			ELSIF off + len > LEN(buf) THEN
				AosOut.String("Connection->send: not enough bufferspace");
				AosOut.Ln;
				RETURN;
			END;
			rpcConn.Send(buf, off, len, FALSE, res);
		END Send;
		
		PROCEDURE AwaitState*(good, bad: SET; ms: LONGINT; VAR res: LONGINT);
		BEGIN
			rpcConn.AwaitState(good, bad, ms, res);
		END AwaitState;
		
		PROCEDURE Reset*();
		BEGIN
			Close();
			NEW(rpcConn);
		END Reset;
		
	END Connection;
	

PROCEDURE Len(VAR x: ARRAY OF CHAR): LONGINT;
	VAR j: LONGINT;
BEGIN
	j := 0;
	WHILE x[j] # 0X DO
		INC(j);
	END;
	RETURN j;
END Len;

(*copy buf1 of Size len into offset of buf2 *)
PROCEDURE CopyBuffer(VAR buf1: ARRAY OF CHAR; len: LONGINT; VAR buf2: ARRAY OF CHAR; off: LONGINT);
BEGIN
	SYSTEM.MOVE(SYSTEM.ADR(buf1[0]), SYSTEM.ADR(buf2[off]), len);
END CopyBuffer;

END RfsConnection.