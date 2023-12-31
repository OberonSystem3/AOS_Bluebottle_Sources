MODULE WebHTTPServer;	(** AUTHOR "pjm/tf/be"; PURPOSE "HTTP/1.1 Server";*)

IMPORT AosOut, AosActive, AosKernel, WebHTTP, AosLog := TFLog, AosModules, AosIO, AosFS,
	AosIP, AosTCP, AosTCPServices, Classes := TFClasses, AosClock, AosCommands, Utilities;

CONST
	FileBufSize = 4096;
	URLLen = 1024;
	Major* = 1; Minor* = 1;
	ServerVersion* = "Aos HTTP Server/0.3";
	DocType = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">';
	Tab = 09X;
	
	Timeout = 300*1000; 	(* [ms] timeout for keep-alive *)
	
	MaxErrors = 10;
	
	Log = FALSE;
	
TYPE
	Name* = ARRAY 64 OF CHAR;

	(** abstract HTTP plugin *)
	HTTPPlugin* = OBJECT
		VAR
			name*: Name;
	
		PROCEDURE &Init(name: Name);
		BEGIN COPY(name, SELF.name)
		END Init;
		
		(** if CanHandle returns TRUE, the Handler procedure will be called *)
		PROCEDURE CanHandle* (host: Host; VAR header : WebHTTP.RequestHeader) : BOOLEAN;
		BEGIN HALT(301)
		END CanHandle;

		(** default LocateResource method *)
		PROCEDURE LocateResource*(host: Host; VAR header: WebHTTP.RequestHeader; VAR reply: WebHTTP.ResponseHeader; VAR f: AosFS.File);
		VAR name, ext: AosFS.FileName; i, d, t: LONGINT; modsince: ARRAY 32 OF CHAR;
		
			PROCEDURE Add(VAR s: ARRAY OF CHAR);
			VAR j, k: LONGINT; ch: CHAR;
			BEGIN
				j := 0; k := 0;
				LOOP
					IF i = LEN(name) THEN reply.statuscode := WebHTTP.RequestURITooLong; EXIT END;
					ch := s[j];
					IF ch = "." THEN k := 0 END;
					name[i] := ch; ext[k] := ch;
					IF ch = 0X THEN EXIT END;
					INC(i); INC(j); INC(k)
				END;
			END Add;
		
		BEGIN
			i := 0; reply.statuscode := WebHTTP.OK;
			Add(host.prefix); Add(header.uri);
			IF (reply.statuscode = WebHTTP.OK) THEN
				f := AosFS.Old(name);
				IF (f # NIL) & (AosFS.Directory IN f.flags) THEN (* do not send directory offals *)
					Utilities.Concat("http://", header.host, reply.location); 
					Utilities.Append(reply.location, header.uri); 
					Utilities.Append(reply.location, "/");
					reply.statuscode := WebHTTP.ObjectMoved
				ELSE
					IF (name[i-1] = "/") THEN
						Utilities.Concat("http://", header.host, reply.contentlocation); 
						Utilities.Append(reply.contentlocation, header.uri);
						Utilities.Append(reply.contentlocation, host.default);
						Add(host.default)
					END;
					
					IF (reply.statuscode = WebHTTP.OK) THEN
						f := AosFS.Old(name);
						IF f # NIL THEN
							f.GetDate(t, d); 
							Utilities.FormatDateTime(WebHTTP.DateTimeFormat, Utilities.OberonToDateTime(d, t), reply.lastmodified);
							IF WebHTTP.GetAdditionalFieldValue(header.additionalFields, "If-Modified-Since", modsince) & 
								(modsince = reply.lastmodified) 
							THEN
								reply.statuscode := WebHTTP.NotModified;
								f := NIL
							ELSE
								(* TODO: move to AosConfig.XML / separate plugins *)
								IF ext = ".html" THEN COPY("text/html", reply.contenttype)
								ELSIF ext = ".txt" THEN COPY("text/plain", reply.contenttype)
								ELSIF ext = ".css" THEN COPY("text/css", reply.contenttype)
								ELSIF ext = ".gif" THEN COPY("image/gif", reply.contenttype)
								ELSIF ext = ".jpg" THEN COPY("image/jpeg", reply.contenttype)
								ELSIF ext = ".pdf" THEN COPY("application/pdf", reply.contenttype)
								ELSE COPY("application/octet-stream", reply.contenttype)
								END
							END
						ELSE
							reply.statuscode := WebHTTP.NotFound; COPY("text/html", reply.contenttype);
							f := AosFS.Old(host.error);
						END
					END
				END
			END
		END LocateResource;
		
		(* handles a HTTP request *)
		PROCEDURE Handle*(host: Host; VAR request: WebHTTP.RequestHeader; VAR reply: WebHTTP.ResponseHeader; 
			VAR in: AosIO.Reader; VAR out: AosIO.Writer);
		BEGIN HALT(301)
		END Handle;
	END HTTPPlugin;
	
	(* default plugin for all hosts. Each host has this default plugin *)
	DefaultPlugin = OBJECT(HTTPPlugin)
		PROCEDURE CanHandle(host : Host; VAR header: WebHTTP.RequestHeader): BOOLEAN;
		BEGIN RETURN TRUE
		END CanHandle;
		
		PROCEDURE Handle* (host: Host; VAR request: WebHTTP.RequestHeader; VAR reply: WebHTTP.ResponseHeader; 
			VAR in: AosIO.Reader; VAR out: AosIO.Writer);
		VAR f: AosFS.File; fr: AosFS.Reader; c: WebHTTP.ChunkedOutStream; r: AosIO.Reader; w: AosIO.Writer;
		BEGIN
			IF (request.method IN {WebHTTP.GetM, WebHTTP.HeadM}) THEN
				LocateResource(host, request, reply, f);
				IF Log THEN
					WebHTTP.LogRequestHeader(log, request);
					WebHTTP.LogResponseHeader(log, reply)
				END;
				
				IF (reply.statuscode = WebHTTP.OK) OR (reply.statuscode = WebHTTP.NotFound) THEN
					IF (f # NIL) THEN 
						reply.contentlength := f.Length();
						WebHTTP.SendResponseHeader(reply, out);
						IF (request.method = WebHTTP.GetM) THEN
							AosFS.OpenReader(fr, f, 0);
							SendData(fr, out)
						END
					ELSE
						NEW(c, w, out, request, reply);
						reply.statuscode := WebHTTP.NotFound;
						WebHTTP.SendResponseHeader(reply, out);
						
						IF (request.method = WebHTTP.GetM) THEN						
							w.String(DocType); w.Ln();
							w.String("<html><head><title>404 - Not Found</title></head>");
							w.String("<body>HTTP 404 - File Not Found<hr><address>");
							w.String(ServerVersion); w.String( "</address></body></html>");
							w.Ln();
							w.Update();
							c.Close()
						END
					END
				ELSIF (reply.statuscode = WebHTTP.NotModified) THEN
					WebHTTP.SendResponseHeader(reply, out)
				ELSIF (reply.statuscode = WebHTTP.ObjectMoved) THEN
					NEW(c, w, out, request, reply);
					WebHTTP.SendResponseHeader(reply, out);
					
					IF (request.method = WebHTTP.GetM) THEN						
						w.String(DocType); w.Ln();
						w.String("<html><head><title>Document Moved</title></head>"); w.Ln();
						w.String('<body><h1>Document Moved</h1>This document may be found <a href="http://');
						w.String(request.uri); w.String(">here</a>.<hr><address>");
						w.String(ServerVersion); w.String("</address></body></html>"); w.Ln();
						w.Update();
						c.Close()
					END
				END
			ELSE
				reply.statuscode := WebHTTP.NotImplemented;
				WebHTTP.WriteStatus(reply, out)
			END
		END Handle;
	END DefaultPlugin;
	
	Statistics = OBJECT
	VAR
		bucket : LONGINT;
		secondBuckets: ARRAY 60 OF LONGINT;
		timer : AosKernel.Timer;
		avg : LONGINT;
		alive : BOOLEAN;
		count : LONGINT;
		statLog : AosLog.Log;
		logCounter: LONGINT;
		
		PROCEDURE Hit;
		BEGIN {EXCLUSIVE}
			INC(secondBuckets[bucket]);
			INC(nofRequests)
		END Hit;
		
		PROCEDURE Update;
		BEGIN {EXCLUSIVE}
			avg := avg + secondBuckets[bucket];
			bucket := (bucket + 1) MOD 60;
			avg := avg - secondBuckets[bucket];
			secondBuckets[bucket] := 0;
			requestsPerMinute := avg;
			
			logCounter := (logCounter + 1) MOD 40H;
			IF (logCounter = 0) THEN
				FlushW3CLog
			END
		END Update;
		
		PROCEDURE Kill;
		BEGIN
			alive := FALSE;
			timer.Wakeup
		END Kill;
	
	BEGIN {ACTIVE}
		NEW(timer); alive := TRUE;
		WHILE alive DO 
			timer.Sleep(1000);
			Update
		END;
	END Statistics;
	
	HostList* = OBJECT
	VAR 
		host*: Host;
		next*: HostList;
	END HostList;
	
	Host* = OBJECT
	VAR
		name-: Name;
		plugins : Classes.List;
		prefix-, default-, error-: AosFS.FileName;
		
		PROCEDURE &Init(name: ARRAY OF CHAR);
		BEGIN
			COPY(name, SELF.name);
			COPY("", prefix);
			COPY("index.html", default);
			COPY("error.html", error);
			
			NEW(plugins);
			(* install default plugin *)
			plugins.Add(defaultPlugin)
		END Init;
		
		PROCEDURE AddPlugin*(pi : HTTPPlugin);
		BEGIN {EXCLUSIVE}
			IF plugins.IndexOf(pi) >= 0 THEN log.Enter; log.String("Plugin already plugged in"); log.Exit
			ELSE
				plugins.Add(pi)
			END	
		END AddPlugin;
		
		PROCEDURE RemovePlugin*(pi : HTTPPlugin);
		BEGIN {EXCLUSIVE}
			plugins.Remove(pi)
		END RemovePlugin;
		
		PROCEDURE SetPrefix*(Prefix: ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			COPY(Prefix, prefix)
		END SetPrefix;
		
		PROCEDURE SetDefault*(Default: ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			COPY(Default, default)
		END SetDefault;
		
		PROCEDURE SetError*(Error: ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			COPY(Error, error)
		END SetError;
		
		PROCEDURE Handle*(VAR request: WebHTTP.RequestHeader; VAR reply: WebHTTP.ResponseHeader; VAR in: AosIO.Reader; VAR out: AosIO.Writer);
		VAR i: LONGINT; pi: HTTPPlugin; p: PTR; exit: BOOLEAN;
		BEGIN
			BEGIN {EXCLUSIVE}
				exit := FALSE;
				i := plugins.GetCount()-1; 
				WHILE (i >= 0) & (~exit) DO 
					p := plugins.GetItem(i);
					IF p(HTTPPlugin).CanHandle(SELF, request) THEN pi := p(HTTPPlugin); exit := TRUE END;
					DEC(i);
				END;
			END;
			IF pi # NIL THEN 
				IF Log THEN
					log.String("request handled by "); log.String(pi.name); log.Ln
				END;
				pi.Handle(SELF, request, reply, in, out)
			ELSE HALT(99)
			END;
		END Handle;
	END Host;
	
	HTTPAgent = OBJECT (AosTCPServices.Agent)
		VAR
			res, len, method, maj, min: LONGINT; 
			body, huga: BOOLEAN;
			f: AosFS.File; out: AosIO.Writer; in, inR: AosIO.Reader;
			o : PTR;
			h, th : Host;
			i, count, status : LONGINT;
			request : WebHTTP.RequestHeader;
			reply: WebHTTP.ResponseHeader;
			value: ARRAY 128 OF CHAR;
			timeout: AosActive.Timer;
			dechunk: WebHTTP.ChunkedInStream;
			consecutiveErrors: LONGINT;
			
		PROCEDURE HandleTimeout;
		BEGIN client.Close
		END HandleTimeout;
	
	BEGIN {ACTIVE}
		NEW(timeout);
			(* open streams *)
		AosIO.OpenReader(in, client.Receive);
		AosIO.OpenWriter(out, client.Send);
		AosKernel.AtomicInc(nofConnects);
		
			(* read request *)
		request.fadr := client.fip;
		request.fport := client.fport;
		
		consecutiveErrors := 0;
		
		REPEAT
			AosActive.SetTimeout(timeout, HandleTimeout, Timeout);
			WebHTTP.ParseRequest(in, request, res, log);
			AosActive.CancelTimeout(timeout);
		
			IF (client.state = AosTCP.Established) THEN
				IF (Utilities.Pos("hunked", request.transferencoding) > 0) THEN
					NEW(dechunk, in, inR)
				ELSE
					inR := in
				END;
				
					(* handle request *)
				GetDefaultResponseHeader(request, reply);
				len := 0; body := FALSE;
				hitStat.Hit;
				IF (res = WebHTTP.OK) THEN
					i := 0; WHILE (request.host[i] # 0X) & (request.host[i] # ":") DO INC(i) END;
					request.host[i] := 0X;
					h := defaultHost;
					hosts.Lock;
					i := hosts.GetCount()-1;
					WHILE (i >= 0) DO 
						o := hosts.GetItem(i); th := o(Host); 
						IF Utilities.Match(th.name, request.host) THEN h := th; i := 0 END;
						DEC(i)
					END;
					hosts.Unlock;
					IF Log THEN
						log.String(request.uri); log.String(" handled by ");
						IF (h.name = "") THEN log.String(" default host")
						ELSE log.String(h.name)
						END;
						log.Ln
					END;
					h.Handle(request, reply, inR, out)
				ELSE
					reply.statuscode := res;
					WebHTTP.WriteStatus(reply, out)
				END;
				IF logEnabled THEN W3CLog(request, reply) END;
	
				IF WebHTTP.GetAdditionalFieldValue(request.additionalFields, "Connection", value) THEN
					huga := Utilities.Pos("lose", value) > 0
				ELSE
					huga := FALSE
				END;
				
				IF (reply.statuscode >= 400) THEN
					INC(consecutiveErrors);
					IF (consecutiveErrors = MaxErrors) THEN client.Close END
				ELSE
					consecutiveErrors := 0
				END;
				
				out.Update()	(* ignore out.res *)
			END
		UNTIL huga OR ((request.maj = 1) & (request.min = 0)) OR (client.state # AosTCP.Established);
		Terminate
	END HTTPAgent;

VAR
	http: AosTCPServices.Service;
	hosts : Classes.List;
	log : AosLog.Log;
	hitStat : Statistics;
	nofRequests* : LONGINT; 
	requestsPerMinute* : LONGINT;
	nofConnects* : LONGINT;
	defaultHost : Host;
	defaultPlugin: DefaultPlugin;
	
	logEnabled : BOOLEAN;
	logWriter : AosIO.Writer;
	logFile : AosFS.File;

PROCEDURE GetRequests*():LONGINT;
BEGIN
	RETURN nofRequests
END GetRequests;

PROCEDURE NewHTTPAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
VAR a: HTTPAgent;
BEGIN
	NEW(a, c, s); RETURN a
END NewHTTPAgent;

PROCEDURE OpenW3CLog(fn: ARRAY OF CHAR);
VAR w : AosFS.Writer;
BEGIN
	logFile := AosFS.Old(fn);
	IF logFile = NIL THEN 
		logFile := AosFS.New(fn); AosFS.Register(logFile);
		AosFS.OpenWriter(w, logFile, 0);
		w.String("#Version: 1.0"); w.Ln();
		w.String("#Fields: date"); w.Char(Tab);
		w.String("time"); w.Char(Tab);
		w.String("cs-method"); w.Char(Tab);
		w.String("cs(host)"); w.Char(Tab);	
		w.String("cs-uri"); w.Char(Tab);
		w.String("x-result"); w.Char(Tab);
		w.String("c-ip"); w.Char(Tab);	
		w.String("cs(user-agent)"); w.Char(Tab);	
		w.String("cs(referer)"); w.Ln()
	ELSE
		AosFS.OpenWriter(w, logFile, logFile.Length())
	END;	
	logWriter := w;
	logEnabled := TRUE
END OpenW3CLog;

PROCEDURE W3CLog(request : WebHTTP.RequestHeader; reply: WebHTTP.ResponseHeader);
VAR time, date: LONGINT; s: ARRAY 36 OF CHAR;
BEGIN {EXCLUSIVE}
	AosClock.Get(time, date);
	logWriter.Date( -1, date); logWriter.Char(Tab);
	logWriter.Date(time, -1); logWriter.Char(Tab);
	CASE request.method OF
		WebHTTP.GetM : logWriter.String("GET")
		| WebHTTP.HeadM : logWriter.String("HEAD")
		| WebHTTP.PutM : logWriter.String("PUT")
		| WebHTTP.PostM : logWriter.String("POST")
		| WebHTTP.OptionsM : logWriter.String("OPTIONS")
	ELSE
		logWriter.String("???")
	END; logWriter.Char(Tab);
	IF request.host # "" THEN logWriter.String(request.host) ELSE logWriter.String("-") END; logWriter.Char(Tab);
	IF request.uri # "" THEN logWriter.String(request.uri) ELSE logWriter.String("-") END; logWriter.Char(Tab);
	logWriter.Int(reply.statuscode, 1); logWriter.Char(Tab);
	AosIP.AdrToStr(request.fadr, s); logWriter.String(s); logWriter.Char(Tab);
	IF request.useragent # "" THEN logWriter.String(request.useragent) ELSE logWriter.String("-") END; logWriter.Char(Tab);
	IF request.referer # "" THEN  logWriter.String(request.referer) ELSE logWriter.String( "-") END; logWriter.Char(Tab);
	logWriter.Ln()
END W3CLog;

PROCEDURE FlushW3CLog*;
BEGIN
	IF logEnabled THEN
		logWriter.Update(); logFile.Update
	END
END FlushW3CLog;

PROCEDURE GetDefaultResponseHeader*(VAR r: WebHTTP.RequestHeader; VAR h: WebHTTP.ResponseHeader);
VAR a: WebHTTP.AdditionalField;
BEGIN
	h.maj := r.maj; h.min := r.min;
	COPY(ServerVersion, h.server);
	h.statuscode := WebHTTP.OK;
	Utilities.FormatDateTime(WebHTTP.DateTimeFormat, Utilities.Now(), h.date);
	h.location := ""; h.contenttype := ""; h.contentlocation := ""; h.transferencoding := ""; 
	h.contentlength := -1; h.lastmodified := "";
	h.additionalFields := NIL
END GetDefaultResponseHeader;

(** Sends all availabe data from src to dst *)
PROCEDURE SendData*(src: AosIO.Reader; dst: AosIO.Writer);
VAR len: LONGINT; buf: ARRAY FileBufSize OF CHAR;
BEGIN
	WHILE (src.res = AosIO.Ok) DO
		src.Bytes(buf, 0, FileBufSize, len);
		dst.Bytes(buf, 0, len)
	END
END SendData;

(** Add a new virtual host *)
PROCEDURE AddHost*(host: Host);
BEGIN {EXCLUSIVE}
	hosts.Add(host)
END AddHost;

(** get a list of matching hosts (wildcards permitted, "*" returns all hosts) *)
PROCEDURE FindHosts*(host: ARRAY OF CHAR): HostList;
VAR i: LONGINT; o: PTR; l, p, old: HostList;
BEGIN {EXCLUSIVE}
	NEW(l);
	IF (host = "") THEN l.host := defaultHost;
	ELSE
		p := l; old := NIL;
		FOR i := 0 TO hosts.GetCount()-1 DO
			o := hosts.GetItem(i);
			IF Utilities.Match(host, o(Host).name) THEN 
				p.host := o(Host); NEW(p.next); old := p; p := p.next 
			END
		END;
		IF (old # NIL) THEN old.next := NIL END
	END;
	IF (l.host = NIL) THEN l := NIL END;
	RETURN l
END FindHosts;

(** remove the virtual host given by name *)
PROCEDURE RemoveHost*(host : ARRAY OF CHAR);
VAR i : LONGINT; o, h : PTR;
BEGIN {EXCLUSIVE}
	hosts.Lock;
	FOR i := 0 TO hosts.GetCount() - 1 DO 
		o := hosts.GetItem(i); IF o(Host).name= host THEN h := o(Host) END;
	END;
	hosts.Unlock;
	IF h # NIL THEN hosts.Remove(h) END
END RemoveHost;

(** Start the basic Server functionality. *)
PROCEDURE Start*(root, logFile: ARRAY OF CHAR);
BEGIN {EXCLUSIVE}
	IF http = NIL THEN
		Utilities.Trim(root, " "); defaultHost.SetPrefix(root);
		IF (logFile # "") THEN OpenW3CLog(logFile) END;
		
		AosTCPServices.OpenService(http, WebHTTP.HTTPPort, NewHTTPAgent);
		IF Log THEN log.Enter; log.TimeStamp; log.String("Started"); log.Exit END
	END
END Start;

(** Stop the server *)
PROCEDURE Stop*(par: PTR): PTR;
BEGIN {EXCLUSIVE}
	IF http # NIL THEN
		AosTCPServices.CloseService(http);
		defaultHost.SetPrefix("");
		IF Log THEN log.Enter; log.TimeStamp; log.String("Stopped"); log.Exit END
	END;
	RETURN NIL
END Stop;

(** enumerate all installed hosts to AosOut *)
PROCEDURE ShowHosts*;
VAR i : LONGINT; o : PTR;

	PROCEDURE PrintHost(h: Host);
	VAR p: PTR; i: LONGINT;
	BEGIN
		AosOut.String("Host: "); 
		IF (h.name = "") THEN AosOut.String("default host")
		ELSE AosOut.String(h.name)
		END;
		AosOut.String("; root: '"); AosOut.String(h.prefix); AosOut.String("'; default: '"); AosOut.String(h.default); 
		AosOut.String("'; error = '"); AosOut.String(h.error); AosOut.Char("'"); AosOut.Ln;
		h.plugins.Lock;
		FOR i := 0 TO h.plugins.GetCount()-1 DO
			p := h.plugins.GetItem(i);
			AosOut.String("   plugin: "); AosOut.String(p(HTTPPlugin).name); AosOut.Ln
		END;
		h.plugins.Unlock		
	END PrintHost;
	
BEGIN {EXCLUSIVE}
	hosts.Lock;
	PrintHost(defaultHost);
	FOR i := 0 TO hosts.GetCount() - 1 DO 
		o := hosts.GetItem(i); 
		PrintHost(o(Host))
	END;
	hosts.Unlock
END ShowHosts;

PROCEDURE Cleanup;
VAR dummy: PTR; t: AosKernel.Timer;
BEGIN
	hitStat.Kill;
	dummy := Stop(NIL);
	hosts := NIL; defaultHost := NIL;
	FlushW3CLog;
	IF Log THEN log.Close END;
	NEW(t); t.Sleep(100) (* avoid trap in Statistics; replace with AosKernel.AwaitDeath *)
END Cleanup;

BEGIN
	IF Log THEN 
		NEW(log, "HTTP Server"); 
		log.SetLogToOut(TRUE)
	END;
	
	NEW(hosts); NEW(hitStat);
	NEW(defaultPlugin, "Default-Plugin");
	NEW(defaultHost, "");
	http := NIL;
	AosModules.InstallTermHandler(Cleanup)
END WebHTTPServer.

(** INFO

The HTTP server is always listening to port 80. By default all requests are handled by the default host. 
Content-Types are currently coded directly in HTTPPlugin.LocateResource (Types for .html .ssmp .txt .gif .jpg .pdf are known)

The server can be used for multi-hosting (several different domain names resolve to the same ip number but return
different pages for different domains). If a host is unknown or the request is not HTTP/1.1 compatible the default host is called.
Known host-names can be dynamically added and removed. See the HTTPServerTools.Mod for a multi-host setup.

Each host can support a number of "Plugins" that can handle special URIs like Form-Post / dynamically generated pages.
See WebWormWatch.Mod for some example plugins.

There is another (experimental) method for dynamically generated pages: "Server Side Modified Pages". Documents with
the name extension ".ssmp" are modified by the server. The patterns "&&"<methodName>" "[<Parameters>] are replaced
by the result of the respective method. See WebWormWatch.Mod WebHTTPServer.Mod WebDefaultSSMP.Mod for examples of SSMP methods. 
See public.info.ssmp as an example of a ".ssmp" page.

(currently unavailable:)
There is a helper module that allows to use url-encoded form posts. See TFHTTPServerExample.Mod for a form-post example.
public.form.html contains the form.

The interfaces in all these modules may change. 
*)

COMPILE THE SERVER AND EXAMPLES
Compiler.Compile \s TFLog.Mod WebHTTP.Mod WebHTTPServer.Mod WebSSMPPlugin.Mod WebDefaultSSMP.Mod
	WebWormWatch.Mod~
	
	TFPostParser.Mod TFHTTPServerExample.Mod~

START THE SERVER
Configuration.DoCommands
Aos.Call WebHTTPServerTools.Start \r:FAT:/httproot \l:FAT:/httproot/WebHTTP.Log~
	Aos.Call WebHTTPServerTools.AddHost livepc.inf.ethz.ch \r:FAT:/httproot/test~
Aos.Call WebSSMPPlugin.Install~
Aos.Call WebDefaultSSMP.Install~
Aos.Call WebHTTPServerTools.ListHosts~
~

Aos.Call WebHTTPServerTools.Stop~

FREE THE SERVER
System.Free WebHTTPServerTools WebDefaultSSMP WebSSMPPlugin WebHTTPServer  WebHTTP~

System.State WebHTTPServer~

FILES
TFLog.Mod WebHTTP.Mod WebSSMPPlugin.Mod WebDefaultSSMP.Mod WebHTTPServer.Mod TFPostParser.Mod TFHTTPServerExample.Mod WebWormWatch.Mod public.form.html public.info.ssmp~

Statistics.Log

W3C Log File

#Version: 1.0
#Fields: date	time	cs-method	cs(host)	cs-uri	c-ip	cs(user-agent)	cs(referer)
WebHTTPServer.FlushW3CLog
EditTools.OpenAscii HTTP.Log ~
System.DeleteFiles HTTP.Log~
