MODULE AosPOP3Client;

IMPORT
	AosModules, AosIO, AosFS, AosIP, AosDNS, AosTCP, Utilities, AosOut;

CONST
	StateIdle = 0;
	StateConnected = 1;
	StateAuthenticate = 2;
	StateTransaction = 3;
	
	ResOk = 0;
	ResFailed = 1;
	ResAlreadyOpen = 2;
	ResServerNotFound = 3;
	ResNoConnection = 4;
	ResUserPassError = 5;
	ResServerNotReady = 6;
	ResServerFailed = 7;

TYPE POP3Client = OBJECT
	VAR connection : AosTCP.Connection;
		w : AosIO.Writer; (* writer on the control connection *)
		r : AosIO.Reader; (* reader on the control connection *)
		state : LONGINT;
		message : ARRAY 513 OF CHAR;

		PROCEDURE Connect*(host: ARRAY OF CHAR; port : LONGINT; user, password: ARRAY OF CHAR;  VAR res : LONGINT);
		VAR fadr : AosIP.Adr;
		BEGIN {EXCLUSIVE}
			res := 0;
			IF state # StateIdle THEN res := ResAlreadyOpen; RETURN END;
			AosDNS.HostByName(host, fadr, res);
			IF res = AosDNS.Ok THEN 
				NEW(connection); 
				connection.Open(AosTCP.NilPort, fadr, port, res);
				IF res = AosTCP.Ok THEN 
					AosIO.OpenWriter(w, connection.Send);
					AosIO.OpenReader(r, connection.Receive);
					state := StateConnected;
					IF ReadResponse(message) THEN state := StateAuthenticate;
						IF Login(user, password) THEN state := StateTransaction 
						ELSE res := ResUserPassError
						END
					END
				ELSE res := ResNoConnection
				END;
				IF state = StateIdle THEN connection.Close(); w := NIL; r := NIL END
			ELSE res := ResServerNotFound
			END			
		END Connect;
		
		PROCEDURE Login(user, password : ARRAY OF CHAR) : BOOLEAN;
		BEGIN
			w.String("USER "); w.String(user); w.Ln; w.Update;
			IF ReadResponse(message) THEN 
				w.String("PASS "); w.String(password); w.Ln; w.Update;
				IF ReadResponse(message) THEN 
					RETURN TRUE
				ELSE RETURN FALSE
				END
			ELSE RETURN FALSE	
			END;
		END Login;
		
		PROCEDURE Quit;
		BEGIN {EXCLUSIVE}
			w.String("QUIT"); w.Ln; w.Update;
			IF ReadResponse(message) THEN END;
			state := StateIdle;
			connection.Close;
			w := NIL; r := NIL
		END Quit;
		
		PROCEDURE List;
		VAR nr, len : LONGINT;
		BEGIN {EXCLUSIVE}
			w.String("LIST"); w.Ln; w.Update;
			IF ReadResponse(message) THEN 
				WHILE r.Peek() # "." DO
					r.Int(nr, FALSE); r.SkipWhitespace; r.Int(len, FALSE); r.SkipLn;
					AosOut.String("Message"); AosOut.Int(nr, 2); AosOut.String(" "); AosOut.Int(len, 0);  AosOut.Ln; 
				END;
				r.SkipLn
			END;
		END List;
		
		PROCEDURE GetMessage(nr : LONGINT; filename : ARRAY OF CHAR) : BOOLEAN;
		VAR str : ARRAY 1024 OF CHAR; f : AosFS.File; fw : AosFS.Writer;
		BEGIN {EXCLUSIVE}
			f := AosFS.New(filename);
			IF f # NIL THEN AosFS.OpenWriter(fw, f, 0)
			ELSE RETURN FALSE
			END;
			
			w.String("RETR "); w.Int(nr, 0); w.Ln; w.Update;
			IF ReadResponse(message) THEN 
				REPEAT
					r.Ln(str);
					IF str # "." THEN
						IF str[0] = "." THEN Utilities.Delete(str, 0, 1) END;
						fw.String(str); fw.Ln;
						AosOut.String(str)
					END	
				UNTIL (str = ".") OR (r.res # 0);
				fw.Update;
				AosFS.Register(f);
				RETURN r.res = 0
			ELSE RETURN FALSE	
			END;
		END GetMessage;
		
		PROCEDURE NOOP;
		BEGIN {EXCLUSIVE}
			w.String("LIST"); w.Ln; w.Update;
			IF ReadResponse(message) THEN 
			END
		END NOOP;
		
		PROCEDURE ReadResponse(VAR message : ARRAY OF CHAR) : BOOLEAN;
		VAR ch : CHAR; tok : ARRAY 4 OF CHAR;
		BEGIN
			ch := r.Get(); r.Token(tok); r.SkipWhitespace;  r.Ln(message);
			AosOut.String("message = "); AosOut.String(message); AosOut.Ln; 
			RETURN ch = "+"
		END ReadResponse;
		
		
	END POP3Client;
	
PROCEDURE Test*(par : ANY) : ANY;
VAR client : POP3Client; res : LONGINT;
BEGIN
	NEW(client);
	(* client.Connect("lillian.ethz.ch", 110, "frey", "henmimi456", res); *)
	client.Connect("pop.bluewin.ch", 110, "frey", "nisbe42", res); 
	IF res = 0 THEN
		 client.List;  
		IF client.GetMessage(2, "test.txt") THEN AosOut.String(" download ok ") ELSE AosOut.String("download failed.");   END;
	ELSE AosOut.String("res = "); AosOut.Int(res, 0); AosOut.Ln; 
	END;	
	client.Quit;
	RETURN NIL
END Test;

END AosPOP3Client.

AosPOP3Client.Test 
S.Free AosPOP3Client 

Color Codes
 Highlight
Types and Procedures
Lock Acquire / Lock Release
Preferred notation (comment)
Unsafe / Temporary / Stupid / requires attention
Permanent Comment 
Assertion
Debug

