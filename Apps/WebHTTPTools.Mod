(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE WebHTTPTools; (** AUTHOR "TF"; PURPOSE "HTTP download tool"; *)

IMPORT
	AosCommands, AosFS, AosTCP, WebHTTP, WebHTTPClient, AosIO, TFLog, AosModules;

VAR log : TFLog.Log;

PROCEDURE StrToIntDef(x: ARRAY OF CHAR; def : LONGINT):LONGINT;
VAR i, v, sgn: LONGINT;
BEGIN
	IF x[0] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END; 
	WHILE (i < LEN(x)) & (x[i] # 0X) DO 
		IF (x[i] >= "0") & (x[i] <= "9") THEN v := v * 10 + (ORD(x[i])-ORD("0")) ELSE RETURN def END;
		INC(i)
	END;
	RETURN sgn * v
END StrToIntDef;

PROCEDURE HexStrToIntDef(x: ARRAY OF CHAR; def : LONGINT):LONGINT;
VAR i, v: LONGINT;
BEGIN
	WHILE (i < LEN(x)) & (x[i] # 0X) DO 
		IF (x[i] >= "0") & (x[i] <= "9") THEN v := v * 16 + (ORD(x[i])-ORD("0")) 
		ELSIF (CAP(x[i]) >= "A") & (CAP(x[i]) <= "F") THEN v := v * 16 + (ORD(CAP(x[i]))-ORD("A") + 10)
		ELSE RETURN def END;
		INC(i)
	END;
	RETURN v
END HexStrToIntDef;

PROCEDURE MatchPrefixI(prefix: ARRAY OF CHAR; VAR str : ARRAY OF CHAR):BOOLEAN;
VAR i: LONGINT;
BEGIN
	i := 0; WHILE (prefix[i] # 0X) & (CAP(prefix[i]) = CAP(str[i])) DO INC(i) END;
	RETURN prefix[i] = 0X
END MatchPrefixI;

PROCEDURE Get*(par: PTR): PTR;
VAR h : WebHTTP.ResponseHeader;
		rh : WebHTTP.RequestHeader;
		in : AosIO.Reader;
		res, i, j, cl, cs : LONGINT;
		ch : CHAR; token : ARRAY 16 OF CHAR;
		name : ARRAY 32 OF CHAR;
		s: AosCommands.Parameters;
		url : ARRAY 256 OF CHAR;
		file : AosFS.File;
		fw : AosFS.Writer;
		con : AosTCP.Connection;
BEGIN
	s := par(AosCommands.Parameters);
	WHILE (s.str[i] # " ") & (s.str[i] # 0X) & (i < LEN(url) - 1) DO url[i] := s.str[i]; INC(i) END; url[i] := 0X;
	WHILE (s.str[i] = " ") DO INC(i) END;	
	WHILE (s.str[i] # " ") & (s.str[i] # 0X) & (j < LEN(name) - 1) DO name[j] := s.str[i]; INC(i); INC(j) END; name[j] := 0X;
	
	log.Enter; log.TimeStamp; log.String("GET "); log.String(url); log.String(" to "); log.String(name); log.Exit;
	rh.useragent := "WebHTTPTool/0.1"; 
	WebHTTPClient.Get(url, rh, con, h, in, res);
	IF res = WebHTTPClient.Ok THEN
		file := AosFS.New(name);
		AosFS.OpenWriter(fw, file, 0);
		IF (h.transferencoding # "") & MatchPrefixI("chunked", h.transferencoding) THEN 
			in.SkipSpaces(); in.Token(token); cs := HexStrToIntDef(token, 0); in.SkipLn();
			WHILE cs # 0 DO 
				FOR i := 0 TO cs - 1 DO in.Char(ch); fw.Char( ch) END;
				 in.SkipLn;in.SkipSpaces; in.Token(token); cs := HexStrToIntDef(token, 0); in.SkipLn;
			END;
			IF fw.res = AosIO.Ok THEN log.Enter; log.TimeStamp; log.String("GET "); log.String(url); log.String(" - OK"); log.Exit
			ELSE log.Enter; log.TimeStamp; log.String("GET "); log.String(url); log.String(" - failed"); log.Exit
			END
		ELSE 	
			IF h.contentlength >= 0 THEN
				FOR i := 0 TO h.contentlength - 1 DO in.Char(ch);  fw.Char(ch) END;
				IF fw.res = AosIO.Ok THEN log.Enter; log.TimeStamp; log.String("GET "); log.String(url); log.String(" - OK"); log.Exit
				ELSE log.Enter; log.TimeStamp; log.String("GET "); log.String(url); log.String(" - failed"); log.Exit
				END
			ELSE
				WHILE in.res = AosIO.Ok DO in.Char(ch); fw.Char(ch) END;
				log.Enter; log.TimeStamp; log.String("GET "); log.String(url); log.String(" - OK"); log.Exit
			END	
		END;
		fw.Update;
		AosFS.Register(file);
		con.Close
	ELSE 
		log.Enter; log.TimeStamp; log.String("GET "); log.String(url); log.String(" - "); log.Int(h.statuscode, 5);  
		log.String(h.reasonphrase); log.Exit
	END;
	RETURN NIL
END Get;

PROCEDURE Head*(par: PTR): PTR;
VAR h : WebHTTP.ResponseHeader;
	res : LONGINT;
	s: AosCommands.Parameters;
	url : ARRAY 256 OF CHAR;
	i : LONGINT;
	con : AosTCP.Connection;
BEGIN
	s := par(AosCommands.Parameters);
	WHILE (s.str[i] # " ") & (s.str[i] # 0X) & (i < LEN(url) - 1) DO url[i] := s.str[i]; INC(i) END; url[i] := 0X;
	WebHTTPClient.Head(url, con, h, res);
	IF res = WebHTTPClient.Ok THEN
		WebHTTP.LogResponseHeader(log, h)
	ELSE log.Enter; log.String("Head not done."); log.Exit
	END;
	RETURN NIL
END Head;

PROCEDURE CleanUp;
BEGIN
	log.Close
END CleanUp;

BEGIN
	NEW(log, "WebHTTPTools");
	AosModules.InstallTermHandler(CleanUp)
END WebHTTPTools.
 

Aos.Call WebHTTPTools.Get http://www.enigon.com/ test.html~
Aos.Call WebHTTPTools.Get http://212.254.73.92/ test.html~
Aos.Call WebHTTPTools.Get http://www.nzz.ch/ test.html~
Aos.Call WebHTTPTools.Head http://212.254.73.92/~
Aos.Call WebHTTPTools.Head http://www.microsoft.com~
Aos.Call WebHTTPTools.Head http://slashdot.org~ (* whats wrong with slashdot ? telnet worked... *)

WebHTTP.Mod
Configuration.DoCommands

System.Free WebHTTPTools
WebHTTPClient WebWormWatch WebHTTPServer WebHTTP~
Aos.Call WebHTTPServer.Start~
Aos.Call WebWormWatch.Install~
~
