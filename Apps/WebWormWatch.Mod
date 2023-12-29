(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE WebWormWatch; (** AUTHOR "TF"; PURPOSE "HTTP plugin to catch worms"; *)

IMPORT
		AosIO, WebHTTP, AosLog := TFLog, AosFS, WebHTTPServer, AosModules, AosClock, 
		AosIP, AosDNS, AosKernel, AosMail, AosSMTPClient;

CONST
	ShowWormOffals = FALSE;

	(* virus capture files *)
	CodeRedVar = "Virus.CodeRedVar.Bin";
	UnknownWorm = "Virus.Unknown.Bin";
	NimdaWorm = "Virus.Nimda.Bin";
	
	WormLog = "Virus.Log";	(* ASCII log file *)
	WormCache = "Virus.Cache";	(* binary cache file storing virus name and source address *)
	
		(* mail parameters *)
	ToName1 = "Thomas Frey";  ToAddr1 = "frey@inf.ethz.ch";
	FromName = "Worm Watch";  FromAddr = "frey@inf.ethz.ch";
	SMTPServer = "lillian.inf.ethz.ch";
	SMTPClient = "eth20853.ethz.ch";
	LocalPrefix = "129.132.";
	
VAR log : AosLog.Log;
	nofNimda*, nofCodeRedVar*:LONGINT;
	lastWormIP*, lastWormName*, lastWormOrigin*: ARRAY 64 OF CHAR;

TYPE 	
	CodeRedPlugin = OBJECT(WebHTTPServer.HTTPPlugin)
		
		PROCEDURE CanHandle(host: WebHTTPServer.Host; VAR h : WebHTTP.RequestHeader): BOOLEAN;
		VAR i : LONGINT;
		BEGIN
			WHILE (h.uri[i] # 0X) & (i < LEN(h.uri)) DO INC(i) END;
			RETURN (i>100)
		END CanHandle;
	
		PROCEDURE Handle(host: WebHTTPServer.Host; VAR request: WebHTTP.RequestHeader; VAR reply: WebHTTP.ResponseHeader; 
			VAR in: AosIO.Reader; VAR out: AosIO.Writer);
		VAR fn, vn : ARRAY 32 OF CHAR;
		BEGIN
			IF MyMatch(request.uri, "/default.ida") THEN
				vn := "Code Red variant"; fn := CodeRedVar; INC(nofCodeRedVar)
			ELSE
				vn := "Unknown"; fn := UnknownWorm
			END;
			MyHandle(vn, fn, in, out, request, reply)
		END Handle;
	END CodeRedPlugin;
	
TYPE
	NimdaPlugin = OBJECT(WebHTTPServer.HTTPPlugin)
		
		PROCEDURE CanHandle(host: WebHTTPServer.Host; VAR h : WebHTTP.RequestHeader): BOOLEAN;
		BEGIN
			RETURN h.uri = "/scripts/root.exe"
		END CanHandle;
		
		PROCEDURE Handle(host: WebHTTPServer.Host; VAR request: WebHTTP.RequestHeader; VAR reply: WebHTTP.ResponseHeader; 
			VAR in: AosIO.Reader; VAR out: AosIO.Writer);
		BEGIN
			INC(nofNimda);
			MyHandle("Nimda", NimdaWorm, in, out, request, reply)
		END Handle;
	
	END NimdaPlugin;

VAR
	crp : CodeRedPlugin;
	np : NimdaPlugin;
	
PROCEDURE MyMatch(VAR uri :ARRAY OF CHAR;  y: ARRAY OF CHAR) : BOOLEAN;
VAR i : LONGINT;
BEGIN
	WHILE (i < LEN(uri)) & (i < LEN(y)) & (uri[i] = y[i]) &(y[i] # 0X) DO INC(i) END;
	RETURN  (i < LEN(uri)) & (i < LEN(y)) & (y[i] = 0X)
END MyMatch;

PROCEDURE Cached(vn, adr: ARRAY OF CHAR): BOOLEAN;
VAR f: AosFS.File; n: ARRAY 64 OF CHAR; a: ARRAY 16 OF CHAR; r: AosFS.Reader; w: AosFS.Writer; cached: BOOLEAN;
BEGIN {EXCLUSIVE}
	cached := FALSE;
	f := AosFS.Old(WormCache);
	IF f = NIL THEN f := AosFS.New(WormCache) END;
	IF f # NIL THEN	(* search cache *)
		AosFS.OpenReader(r, f, 0);
		LOOP
			r.RawString(n); r.RawString(a);
			IF r.res # 0 THEN EXIT END;
			IF (n = vn) & (a = adr) THEN cached := TRUE; EXIT END
		END;
		IF ~cached THEN	(* add to cache *)
			AosFS.OpenWriter(w, f, f.Length());
			w.RawString(vn); w.RawString(adr);
			w.Update;
			AosFS.Register(f)
		END
	END;
	RETURN cached
END Cached;

PROCEDURE MyHandle(vn, fn: ARRAY OF CHAR; VAR in: AosIO.Reader; VAR out: AosIO.Writer; 
	VAR header : WebHTTP.RequestHeader; VAR reply: WebHTTP.ResponseHeader);
VAR
	f: AosFS.File; w : AosFS.Writer; res, i, time, date: LONGINT;
	ch :CHAR;
	md : ARRAY 32 OF CHAR;
	origin : ARRAY 64 OF CHAR;
	ipstr:ARRAY 16 OF CHAR;
	timer : AosKernel.Timer;
	msg : AosMail.Message;
	smtpSession: AosSMTPClient.SMTPSession;
	str: AosIO.StringWriter;
BEGIN
	AosIP.AdrToStr(header.fadr, ipstr);
	AosDNS.HostByNumber(header.fadr, origin, res);
	COPY(ipstr, lastWormIP); COPY(origin, lastWormOrigin); COPY(vn, lastWormName);
	log.Enter; log.TimeStamp; log.String("Worm Alert : "); log.String(vn); log.String(" ");
	log.String(ipstr); IF res = AosDNS.Ok THEN log.String("("); log.String(origin); log.String(")") END;
	
	IF Cached(vn, ipstr) THEN
		log.Enter; log.TimeStamp;
		log.String("Worm Cache : "); log.String(vn); log.String(" "); log.String(ipstr);
		log.Exit;
		RETURN
	END;
	
	IF MyMatch(ipstr, LocalPrefix) THEN	(* ETH infection: send a Mail *)
		log.Ln; i := 0 ;
		NEW(msg);
		msg.AddTo(ToName1, ToAddr1);
		msg.SetFrom(FromName, FromAddr);
		NEW(str, 64);
		AosClock.Get(time, date); str.Date822(time, date, 0);
		str.Get(md); msg.SetDate(md);
		msg.SetSubject("Worm Infection report");
		AosIP.AdrToStr(header.fadr, ipstr);
		msg.AddLine("Infected IP");
		msg.AddLine(ipstr);
		msg.AddLine(origin);
		msg.AddLine(vn);
		NEW(smtpSession);
		smtpSession.Open(SMTPServer, SMTPClient, 25, res);
		IF res = AosSMTPClient.Ok THEN
			smtpSession.Send(msg, res)
		END;
		smtpSession.Close
	END;
	f := AosFS.New(fn); AosFS.OpenWriter(w, f, 0);
	NEW(timer);
	WHILE in.Available() > 0 DO
		ch := in.Get(); 
		IF ShowWormOffals THEN log.Hex(ORD(ch), -3); INC(i); IF i MOD 16 = 0 THEN log.Ln END END;
		IF in.Available() = 0 THEN timer.Sleep(2000) END;
		w.Char(ch);
	END;
	w.Update;
	AosFS.Register(f);
	log.Exit;
	IF header.method IN {WebHTTP.GetM, WebHTTP.HeadM} THEN
		WebHTTP.WriteStatus(reply, out);
		out.String("Content-Type: "); out.String("text/html"); out.Ln;
		out.Ln;
		IF (header.method = WebHTTP.GetM) THEN 
			out.String("<HTML>");
			out.String("Your request seems to be a worm attack. Failed."); out.Ln;
			out.String("</HTML>");
			out.Ln
		END	
	ELSE
		reply.statuscode := WebHTTP.NotImplemented;
		WebHTTP.WriteStatus(reply, out)
	END;
	out.Update
END MyHandle;

PROCEDURE Install*(par: PTR): PTR;
VAR hl: WebHTTPServer.HostList;
BEGIN
	IF crp = NIL THEN 
		NEW(crp, "CodeRed-Plugin");
		NEW(np, "Nimda-Plugin");
		hl := WebHTTPServer.FindHosts("*");
		WHILE (hl # NIL) DO
			hl.host.AddPlugin(crp);
			hl.host.AddPlugin(np);
			hl := hl.next
		END;
		log.Enter; log.String("Worm Watch Plugin installed"); log.Exit;
	 ELSE
		log.Enter; log.String("Worm Watch Plugin already installed"); log.Exit;
	END;	
	RETURN NIL
END Install;

PROCEDURE Close;
VAR h: WebHTTPServer.HostList;
BEGIN
	IF crp # NIL THEN 
		h := WebHTTPServer.FindHosts("*");
		WHILE (h # NIL) DO
			h.host.RemovePlugin(crp);
			h.host.RemovePlugin(np);
			h := h.next
		END;
		log.Enter; log.String("Worm Watch Plugin removed"); log.Exit; log.Close;
		crp := NIL; np := NIL;
	END
END Close;

BEGIN
	lastWormOrigin := "No last worm origin";
	lastWormIP := "No last worm IP";
	lastWormName := "No last worm name";
	NEW(log, "Worm Watch");
	log.SetLogFile(WormLog);
	AosModules.InstallTermHandler(Close)
END WebWormWatch.
 

System.Free WebWormWatch ~
Aos.Call WebWormWatch.Install ~
