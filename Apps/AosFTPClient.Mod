MODULE AosFTPClient;	(** AUTHOR "TF"; PURPOSE "FTP client services"; *)

IMPORT AosIO, AosKernel, AosActive, AosIP, AosDNS, AosTCP, Utilities, AosOut;

CONST
	ResOk = 0;
	ResFailed = 1;
	ResAlreadyOpen = 2;
	ResServerNotFound = 3;
	ResNoConnection = 4;
	ResUserPassError = 5;
	ResServerNotReady = 6;
	ResServerFailed = 7;

	FileActionOk = 250; CommandOk = 200; DataConnectionOpen = 125; FileStatusOk = 150; 
	EnterPassword = 330; NeedPassword = 331; PathNameCreated = 257; UserLoggedIn = 230; 
	
	ActvTimeout = 60 * 1000; 


TYPE
	(** FTP client object must be used by a single process *)
	FTPClient* = OBJECT
	VAR
		open : BOOLEAN;
		busy : BOOLEAN;
		connection : AosTCP.Connection; (* control connection to the server *)
		dataCon : AosTCP.Connection;
		dataIP : AosIP.Adr;
		dataPort : LONGINT;
		w : AosIO.Writer; (* writer oo the control connection *)
		r : AosIO.Reader; (* reader on the control connection *)
		msg- : ARRAY 256 OF CHAR;
		code : LONGINT;
		passiveTransfer : BOOLEAN;
		actvListener : AosTCP.Connection;
		actvTimeout : AosActive.Timer;
		
		PROCEDURE &Init;
		BEGIN
			NEW(actvTimeout)
		END Init;
		
		
		PROCEDURE Open*(host, user, password : ARRAY OF CHAR; port : LONGINT; VAR res : LONGINT);
		VAR fadr : AosIP.Adr;
		BEGIN {EXCLUSIVE}
			res := 0;
			busy := FALSE; open := FALSE;
			IF open THEN res := ResAlreadyOpen; RETURN END;
			AosDNS.HostByName(host, fadr, res);
			IF res = AosDNS.Ok THEN 
				NEW(connection); 
				connection.Open(AosTCP.NilPort, fadr, port, res);
				IF res = AosTCP.Ok THEN 
					AosIO.OpenWriter(w, connection.Send);
					AosIO.OpenReader(r, connection.Receive);
					ReadResponse(code, msg);
					IF (code >= 200) & (code < 300) THEN
						IF Login(user, password) THEN open := TRUE;
							(* Set binary transfer mode - anything else seems useless *)
							w.String("TYPE I"); w.Ln; w.Update;
							ReadResponse(code, msg);
							IF code # CommandOk THEN res := ResServerFailed END
						ELSE res := ResUserPassError
						END
					ELSE res := ResServerNotReady
					END
				ELSE res := ResNoConnection			
				END;
				IF ~open THEN connection.Close(); w := NIL; r := NIL END
			ELSE res := ResServerNotFound
			END
		END Open;
		
		PROCEDURE Login(user, password : ARRAY OF CHAR) : BOOLEAN;
		BEGIN
			w.String("USER "); w.String(user); w.Ln; w.Update;
			ReadResponse(code, msg);
			IF (code = EnterPassword) OR (code = NeedPassword) THEN
				w.String("PASS "); w.String(password); w.Ln; w.Update;
				ReadResponse(code, msg);
				IF (code = UserLoggedIn) OR (code = EnterPassword) (* why ? *) THEN 
					RETURN TRUE
				ELSE 
					RETURN FALSE
				END	
			ELSIF code = UserLoggedIn THEN RETURN TRUE
			ELSE RETURN FALSE
			END
		END Login;
		
		PROCEDURE ReadResponse(VAR code : LONGINT; VAR reply : ARRAY OF CHAR);
		VAR t : LONGINT;
		BEGIN
			r.Int(code, FALSE);
			IF r.Peek() = "-" THEN (* multi line response *)
				REPEAT
					r.SkipLn;
					r.Int(t, FALSE)
				UNTIL (t = code) OR (r.res # 0)
			END;
			r.Ln(reply)
		END ReadResponse;
		
		PROCEDURE Close*(VAR res : LONGINT);
		BEGIN 
			w.String("QUIT"); w.Ln; w.Update;
			ReadResponse(code, msg);
			IF (code >= 200) & (code < 300) THEN res := 0 ELSE res := code END;	
			connection.Close; w := NIL; r := NIL;
			open := FALSE
		END Close;
		
		PROCEDURE IsNum(ch : CHAR) : BOOLEAN;
		BEGIN
			RETURN (ch >= '0') & (ch <='9')
		END IsNum;
		
		PROCEDURE GetDataConnection( VAR res : LONGINT);
		VAR ch : CHAR; i, j : LONGINT; ipstr : ARRAY 16 OF CHAR; p0, p1, port : LONGINT;
			str : ARRAY 32 OF CHAR;
			
			PROCEDURE Fail;
			BEGIN
				res := -1; r.SkipLn
			END Fail;
			
		BEGIN
			IF passiveTransfer THEN
				w.String("PASV"); w.Ln; w.Update;
				r.Int(code, FALSE);
				AosOut.String("PASV"); 
				AosOut.String("code = "); AosOut.Int(code, 0); AosOut.Ln; 
			END;	
	
			IF passiveTransfer & (code >= 200) & (code < 300) THEN
				(* search for a number *)
				REPEAT ch := r.Get() UNTIL IsNum(ch) OR (r.res # 0);
				IF r.res # 0 THEN Fail; RETURN END;
				(* read ip adr *)
				j := 0; i := 0;
				WHILE (r.res = 0) & (j < 4) DO
					IF ch = "," THEN ch := "."; INC(j) END;
					AosOut.Char(ch); 
					IF j < 4 THEN ipstr[i] := ch; INC(i); ch := r.Get()  END
				END;
				ipstr[i] := 0X; 
				AosOut.String("ipstr = "); AosOut.String(ipstr); AosOut.Ln; 
				IF r.res # 0 THEN Fail; RETURN END;
				
				(* read the port *)
				r.Int(p0, FALSE); ch := r.Get();
				IF ch # "," THEN Fail; RETURN END;
				r.Int(p1, FALSE); 
				r.SkipLn;
				port := p0 * 256 + p1;
				AosOut.String(ipstr); AosOut.Ln;
				AosOut.Int(port, 0); AosOut.Ln; 
				dataIP := AosIP.StrToAdr(ipstr);
				dataPort := port;
			ELSE
				IF passiveTransfer THEN r.SkipLn END; (* skip the negative reply message to PASV *)
				passiveTransfer := FALSE;
				(* trying to find an unused local tcp port within the limits of FTP *)
				NEW(actvListener);
				actvListener.Open(AosTCP.NilPort, AosIP.NilAdr, AosTCP.NilPort, res);
				AosIP.AdrToStr(connection.int.localAdr, str); 
				i := 0; WHILE (str[i] # 0X) DO IF (str[i] = ".") THEN str[i] := "," END; INC(i) END;
				str[i] := ","; str[i+1] := 0X;
				w.String("PORT ");
				w.String(str);
				w.Int(actvListener.lport DIV 100H, 0);
				w.Char(",");
				w.Int(actvListener.lport MOD 100H, 0);
				w.Ln; w.Update;
				ReadResponse(code, msg);
				AosOut.String("code = "); AosOut.Int(code, 0); AosOut.Ln; 
				AosOut.String("msg = "); AosOut.String(msg); AosOut.Ln; 			
			END
		END GetDataConnection;
		
		PROCEDURE ActvTimeoutHandler;
		BEGIN 
			actvListener.Close
		END ActvTimeoutHandler;
		
		PROCEDURE WaitEstablished(c: AosTCP.Connection);
		VAR t: AosKernel.MilliTimer;
		BEGIN
			IF (c.state # AosTCP.Established) THEN
				AosKernel.SetTimer(t, 500);
				WHILE (c.state # AosTCP.Established) & ~AosKernel.Expired(t) DO
					AosActive.Yield
				END
			END
		END WaitEstablished;
	
		PROCEDURE OpenDataConnection(VAR connection : AosTCP.Connection; VAR res : LONGINT);
		BEGIN;
			IF passiveTransfer THEN
				NEW(connection); 	connection.Open(AosTCP.NilPort, dataIP, dataPort, res)
			ELSE
				AosActive.SetTimeout(actvTimeout, ActvTimeoutHandler, ActvTimeout);
				actvListener.Accept(connection, res);
				AosOut.String("res = "); AosOut.Int(res, 0); AosOut.Ln; 
				AosActive.CancelTimeout(actvTimeout);
				actvListener.Close;
				WaitEstablished(connection);
				AosOut.String("Active connection established"); AosOut.Ln; 
			END	
		END OpenDataConnection;
		
		PROCEDURE OpenPut*(remoteName : ARRAY OF CHAR; VAR outw : AosIO.Writer; VAR res : LONGINT);
		BEGIN 
			IF ~open OR busy THEN res := -2; RETURN END;
			busy := TRUE;
			GetDataConnection(res);
			IF res # 0 THEN RETURN END;

			w.String("STOR "); w.String(remoteName); w.Ln; w.Update;
			ReadResponse(code, msg);
			AosOut.String("code = "); AosOut.Int(code, 0); AosOut.Ln; 
			AosOut.String("msg = "); AosOut.String(msg); AosOut.Ln; 
			IF (code = FileStatusOk) OR (code = FileActionOk) OR (code = DataConnectionOpen)  THEN
				OpenDataConnection(dataCon, res);
				AosOut.String("ODC");  AosOut.String("res = "); AosOut.Int(res, 0); AosOut.Ln; 
				IF res = 0 THEN
					AosIO.OpenWriter(outw, dataCon.Send)
				END
			ELSE res := -1
			END
		END OpenPut;
		
		PROCEDURE ClosePut*(VAR res : LONGINT);
		BEGIN 
			busy := FALSE;
			IF dataCon # NIL THEN
				dataCon.Close;
				dataCon := NIL
			END;
			ReadResponse(code, msg);
			IF (code >= 200) & (code < 300) THEN res := 0 ELSE res := code END;	
			AosOut.String("Result after close put"); AosOut.Ln; 
			AosOut.String("code = "); AosOut.Int(code, 0); AosOut.Ln; 
			AosOut.String("msg = "); AosOut.String(msg); AosOut.Ln 
		END ClosePut;

		PROCEDURE OpenGet*(remoteName : ARRAY OF CHAR; VAR r : AosIO.Reader; VAR res : LONGINT);
		BEGIN 
			IF ~open OR busy THEN res := -2; RETURN END;
			busy := TRUE;
			GetDataConnection(res);
			IF res # 0 THEN RETURN END;

			w.String("RETR "); w.String(remoteName); w.Ln; w.Update;
			ReadResponse(code, msg);
			AosOut.String("code = "); AosOut.Int(code, 0); AosOut.Ln; 
			AosOut.String("msg = "); AosOut.String(msg); AosOut.Ln; 
			IF (code = FileStatusOk) OR (code = FileActionOk) OR (code = DataConnectionOpen)  THEN
				OpenDataConnection(dataCon, res);
				AosOut.String("ODC");  AosOut.String("res = "); AosOut.Int(res, 0); AosOut.Ln; 
				IF res = 0 THEN
					AosIO.OpenReader(r, dataCon.Receive)
				END
			ELSE res := -1
			END
		END OpenGet;
		
		PROCEDURE CloseGet*(VAR res : LONGINT);
		BEGIN 
			IF dataCon # NIL THEN
				dataCon.Close;
				dataCon := NIL
			END;
			busy := FALSE;
			ReadResponse(code, msg);
			IF (code >= 200) & (code < 300) THEN res := 0 ELSE res := code END;	
			AosOut.String("Result after close get"); AosOut.Ln; 
			AosOut.String("code = "); AosOut.Int(code, 0); AosOut.Ln; 
			AosOut.String("msg = "); AosOut.String(msg); AosOut.Ln 
		END CloseGet;
		
		PROCEDURE DeleteFile*(remoteName : ARRAY OF CHAR; VAR res : LONGINT);
		BEGIN 
			IF ~open OR busy THEN res := -2; RETURN END;
			w.String("DELE "); w.String(remoteName); w.Ln; w.Update;
			ReadResponse(code, msg);
			IF (code >= 200) & (code <300) THEN res := ResOk ELSE res := ResFailed END
		END DeleteFile;
	
		PROCEDURE ChangeDir*(dir : ARRAY OF CHAR; VAR res : LONGINT);
		BEGIN 
			IF ~open OR busy THEN res := -2; RETURN END;
			w.String("CWD "); w.String(dir); w.Ln; w.Update;
			ReadResponse(code, msg);
			IF (code >= 200) & (code <300) THEN res := ResOk ELSE res := ResFailed END
		END ChangeDir;

		PROCEDURE MakeDir*(dir : ARRAY OF CHAR; VAR res : LONGINT);
		BEGIN 
			IF ~open OR busy THEN res := -2; RETURN END;
			w.String("MKD "); w.String(dir); w.Ln; w.Update;
			ReadResponse(code, msg);
			IF (code >= 200) & (code <300) THEN res := ResOk ELSE res := ResFailed END
		END MakeDir;
		
		PROCEDURE RemoveDir*(dir : ARRAY OF CHAR; VAR res : LONGINT);
		BEGIN
			IF ~open OR busy THEN res := -2; RETURN END;
			w.String("RMD "); w.String(dir); w.Ln; w.Update;
			ReadResponse(code, msg);
			IF (code >= 200) & (code <300) THEN res := ResOk ELSE res := ResFailed END
		END RemoveDir;
		
		PROCEDURE RenameFile*(currentName, newName : ARRAY OF CHAR; VAR res : LONGINT);
		BEGIN 
			IF ~open OR busy THEN res := -2; RETURN END;
			w.String("RNFR "); w.String(currentName); w.Ln; w.Update;
			ReadResponse(code, msg);
			IF (code = 350) THEN 
				w.String("RNTO "); w.String(newName); w.Ln; w.Update;
				ReadResponse(code, msg);
				IF code = 250 THEN res := ResOk 
				ELSE res := ResFailed 
				END
			ELSE res := ResFailed 
			END
		END RenameFile;
		
		PROCEDURE EnumerateDir*;
		VAR  res : LONGINT;
			r : AosIO.Reader; s, filename : ARRAY 256 OF CHAR;
			flags : ARRAY 11 OF CHAR;
			type : ARRAY 4 OF CHAR;
			user, group, size : ARRAY 9 OF CHAR;
			d0, d1, d2: ARRAY 13 OF CHAR;
			sr : AosIO.StringReader;
			
			PROCEDURE FixLengthStr(r : AosIO.Reader; len : LONGINT; VAR s : ARRAY OF CHAR);
			VAR i : LONGINT;
			BEGIN
				WHILE (len > 0) & (r.res = 0) DO
					s[i] := r.Get();
					DEC(len); INC(i)
				END;
				s[i] := 0X
			END FixLengthStr;
			
			
			
		BEGIN
			IF ~open OR busy THEN res := -2; RETURN END;
			AosOut.String("Enumerate Dir"); AosOut.Ln; 
			GetDataConnection(res);
			IF res # 0 THEN RETURN END;
			w.String("LIST");  w.Ln; w.Update;
			ReadResponse(code, msg);
			AosOut.String("code = "); AosOut.Int(code, 0); AosOut.Ln; 
			AosOut.String("msg = "); AosOut.String(msg); AosOut.Ln; 
			IF (code = FileStatusOk) OR (code = FileActionOk) OR (code = DataConnectionOpen)  THEN
				AosOut.String("Open data connection"); AosOut.Ln; 
				OpenDataConnection(dataCon, res);
				AosOut.String("ODC");  AosOut.String("res = "); AosOut.Int(res, 0); AosOut.Ln; 
				IF res = 0 THEN
					AosIO.OpenReader(r, dataCon.Receive);
					NEW(sr, 256);
					REPEAT
						r.Ln(s);
						IF r.res = 0 THEN
							sr.Set(s);
							AosOut.String("s = "); AosOut.String(s); AosOut.Ln; 
							
(*							FixLengthStr(sr, 10, flags); sr.SkipBytes(1);
							FixLengthStr(sr, 3, type); sr.SkipBytes(1);
							FixLengthStr(sr, 8, user); sr.SkipBytes(1);
							FixLengthStr(sr, 8, group); sr.SkipBytes(1);
							FixLengthStr(sr, 8, size); sr.SkipBytes(1);
							FixLengthStr(sr, 12, date); sr.SkipBytes(1); *)
							sr.Token(flags); sr.SkipWhitespace;
							sr.Token(type); sr.SkipWhitespace;
							sr.Token(user); sr.SkipWhitespace;
							sr.Token(group); sr.SkipWhitespace;
							sr.Token(size); sr.SkipWhitespace;
							sr.Token(d0); sr.SkipWhitespace;
							sr.Token(d1); sr.SkipWhitespace;
							sr.Token(d2); sr.SkipWhitespace;
							
							sr.Ln(filename);
							
							AosOut.String("flags = "); AosOut.String(flags); AosOut.Ln; 
							AosOut.String("type = "); AosOut.String(type); AosOut.Ln; 
							AosOut.String("user = "); AosOut.String(user); AosOut.Ln; 
							AosOut.String("group = "); AosOut.String(group); AosOut.Ln; 
							AosOut.String("size = "); AosOut.String(size); AosOut.Ln; 
							AosOut.String("date = "); AosOut.String(d0); AosOut.String(d1);AosOut.String(d2);AosOut.Ln; 
							AosOut.String("filename = "); AosOut.String(filename); AosOut.Ln; 
							AosOut.Ln; 
						END	
					UNTIL r.res # 0
				END;
				dataCon.Close;
				
				ReadResponse(code, msg);
				AosOut.String("Result after Dir"); AosOut.Ln; 
				AosOut.String("code = "); AosOut.Int(code, 0); AosOut.Ln; 
				AosOut.String("msg = "); AosOut.String(msg); AosOut.Ln; 
			ELSE res := ResFailed 
			END;
			dataCon := NIL
		END EnumerateDir;
		
		
		PROCEDURE GetCurrentDir*(VAR dir : ARRAY OF CHAR; VAR res : LONGINT);
		VAR p : LONGINT;
		BEGIN 
			IF ~open OR busy THEN res := -2; RETURN END;
			w.String("PWD "); w.Ln; w.Update;
			ReadResponse(code, msg);
			AosOut.String("msg = "); AosOut.String(msg); AosOut.Ln; 
			IF code = PathNameCreated THEN 
				COPY(msg, dir);
				p := Utilities.Pos('"', dir);
				IF p >= 0 THEN
					Utilities.Delete(dir, 0, p + 1);
					p := Utilities.Pos('"', dir); Utilities.Delete(dir, p, Utilities.Length(dir) - p)
				ELSE
					p := Utilities.Pos(' ', dir); Utilities.Delete(dir, p, Utilities.Length(dir) - p)
				END
			ELSE COPY("", dir); res := ResFailed
			END;
		END GetCurrentDir;
	
	END FTPClient;

END AosFTPClient.

Color Codes
Highlight
Types and Procedures
Lock Acquire / Lock Release
Preferred notation (comment)
Unsafe / Temporary / Stupid / requires attention
Permanent Comment 
Assertion
Debug
