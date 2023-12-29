MODULE RFC865Client;	(** AUTHOR "TF"; PURPOSE "Get a quote from a RFC865 compliant server"; *)

IMPORT
	AosOut, AosCommands, AosIP, AosDNS, AosTCP, AosIO;
	
CONST QuotePort = 17;

PROCEDURE GetQuote*(par : PTR) : PTR;
VAR s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	connection : AosTCP.Connection;
	serverName : ARRAY 32 OF CHAR;
	line : ARRAY 513 OF CHAR;
	serverIP, res : LONGINT;
	reader : AosIO.Reader;
BEGIN
	(* open a reader stream on the command parameters *)
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	(* read the name of the server *)
	sr.Token(serverName);
	
	(* perform a DNS lookup *)
	AosDNS.HostByName(serverName, serverIP, res);
	IF res # 0 THEN (* If the result is not 0, the DNS lookup has failed *)
		AosOut.String("Host not found."); AosOut.Ln;
		RETURN NIL
	END;
	
	(* Print the IP address ... *)
	AosIP.AdrToStr(serverIP, line); 
	AosOut.String("Server found at "); AosOut.String(line); AosOut.Ln;
	
	(* Open a connection to the serverIP *)	
	NEW(connection);
	(* Set the local port to AosIP.NilPort because we dont care.
	The system will fill in an available local port *)
	connection.Open(AosTCP.NilPort, serverIP, QuotePort, res);
	IF res # 0 THEN (* If the result is not 0, the connection failed *)
		AosOut.String("Could not connect to host."); AosOut.Ln;
		RETURN NIL
	END;
	
	(* Open a reader stream on the connection receiver *)
	AosIO.OpenReader(reader, connection.Receive);
	REPEAT
		reader.Ln(line);
		AosOut.String(line); AosOut.Ln
	UNTIL reader.res # 0;
	connection.Close;
	RETURN NIL
END GetQuote;

END RFC865Client.
 

System.Free RFC865Client ~
System.OpenKernelLog
Aos.Call RFC865Client.GetQuote bluebottle.ethz.ch ~