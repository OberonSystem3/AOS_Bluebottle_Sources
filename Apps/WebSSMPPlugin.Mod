(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE WebSSMPPlugin; (** AUTHOR "tf/be"; PURPOSE "SSMP: Server-Side Modified Pages"; *)

(* HTTPPlugin for ServerSide Modified Pages *)

IMPORT
		AosIO, AosCommands, AosOut, Classes := TFClasses, Utilities, AosFS, WebHTTP, WebHTTPServer;
		
CONST 
	MaxServiceNameSize* = 32;
	PluginName = "SSMP-Plugin";

TYPE 
	SSMPMethod* = PROCEDURE {DELEGATE}(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);

	ServiceInfo = OBJECT
	VAR
		name : ARRAY MaxServiceNameSize OF CHAR; 
		service : SSMPMethod;
	END ServiceInfo;
	
	SSMPPlugin = OBJECT(WebHTTPServer.HTTPPlugin)
		PROCEDURE &Init(name: WebHTTPServer.Name);
		BEGIN
			Init^(PluginName)
		END Init;
		
		PROCEDURE CanHandle(host: WebHTTPServer.Host; VAR request: WebHTTP.RequestHeader; secure : BOOLEAN): BOOLEAN;
		VAR name, ext: ARRAY 16 OF CHAR;
		BEGIN
			AosFS.SplitExtension(request.uri, name, ext);
			Utilities.UpperCase(ext);
			RETURN (ext = "SSMP") & ((request.method = WebHTTP.GetM) OR (request.method = WebHTTP.HeadM))
		END CanHandle;
		
		PROCEDURE Handle*(host: WebHTTPServer.Host; VAR request: WebHTTP.RequestHeader; VAR reply: WebHTTP.ResponseHeader; 
			VAR in: AosIO.Reader; VAR out: AosIO.Writer);
		VAR f: AosFS.File; chunker: WebHTTP.ChunkedOutStream; w: AosIO.Writer;
		BEGIN
			WebHTTP.SetAdditionalFieldValue(request.additionalFields, "If-Modified-Since", " ");
			LocateResource(host, request, reply, f);
			WebHTTPServer.GetDefaultResponseHeader(request, reply);
			NEW(chunker, w, out, request, reply);
			IF (f # NIL) THEN
				WebHTTP.SendResponseHeader(reply, out);
				IF (request.method = WebHTTP.GetM) THEN
					WriteFile(request, w, f);
					chunker.Close
				END
			ELSE
				reply.statuscode := WebHTTP.NotFound;
				WebHTTP.SendResponseHeader(reply, out);
				IF (request.method = WebHTTP.GetM) THEN
					w.String("<html><head><title>404 - Not Found</title></head>");
					w.String("<body>HTTP 404 - File Not Found<hr><address>");
					w.String(WebHTTPServer.ServerVersion); w.String("</address></body></html>");
					w.Ln; w.Update;
					chunker.Close
				END
			END
		END Handle;
	END SSMPPlugin;

VAR services : Classes.List;

PROCEDURE ExecuteService(VAR name : ARRAY OF CHAR; VAR request : WebHTTP.RequestHeader; in : AosIO.Reader; out : AosIO.Writer);
VAR i : LONGINT;
	o : PTR; info : ServiceInfo;
BEGIN
	services.Lock;
	FOR i := 0 TO services.GetCount() - 1 DO 
		o := services.GetItem(i); info := o(ServiceInfo);
		IF info.name = name THEN info.service(request, in, out); services.Unlock; RETURN END;
	END;
	services.Unlock;
	out.String("<B>Service not available ("); out.String(name); out.String(")</B>")
END ExecuteService;

PROCEDURE WriteFile*(VAR request: WebHTTP.RequestHeader; VAR s: AosIO.Writer; f: AosFS.File);
VAR r: AosFS.Reader; len: LONGINT; ch, pch : CHAR; serviceName: ARRAY MaxServiceNameSize OF CHAR;
BEGIN
	AosFS.OpenReader(r, f, 0);
	LOOP
		ch := r.Get();
		IF r.res # 0 THEN EXIT END;
		IF ch = "&" THEN 
			IF r.Peek() = "&" THEN 
				ch := r.Get();
				r.Token(serviceName);
				ExecuteService(serviceName, request, r, s)
			ELSE s.Char(ch)
			END
		ELSE s.Char(ch)
		END	
	END;
	s.Update
END WriteFile;

PROCEDURE RegisterMethod*(name: ARRAY OF CHAR; handler : SSMPMethod);
VAR new : ServiceInfo;
BEGIN {EXCLUSIVE}
	NEW(new); COPY(name, new.name); new.service := handler; services.Add(new)
END RegisterMethod;

PROCEDURE UnregisterMethod*(name: ARRAY OF CHAR);
VAR i : LONGINT; o, h : PTR;
BEGIN {EXCLUSIVE}
	services.Lock;
	FOR i := 0 TO services.GetCount() - 1 DO 
		o := services.GetItem(i); IF o(ServiceInfo).name = name THEN h := o(ServiceInfo) END;
	END;
	services.Unlock;
	IF h # NIL THEN services.Remove(h) END
END UnregisterMethod;

PROCEDURE Install*(par: PTR): PTR; (** [{host}]. Host may include wildcards. *)
VAR p: AosCommands.Parameters; r: AosIO.StringReader; host: ARRAY 1024 OF CHAR; 
	hl: WebHTTPServer.HostList; ssmpPlugin: SSMPPlugin;
BEGIN
	p := par(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^);

	NEW(ssmpPlugin, PluginName);
	
	REPEAT
		r.String(host);
		Utilities.Trim(host, " ");
		
		hl := WebHTTPServer.FindHosts(host);
		IF (hl # NIL) THEN
			WHILE (hl # NIL) DO
				hl.host.AddPlugin(ssmpPlugin);
				AosOut.String(PluginName); AosOut.String(" added to "); 
				IF (hl.host.name = "") THEN AosOut.String("default host")
				ELSE AosOut.String(hl.host.name)
				END;
				AosOut.Ln;
				hl := hl.next
			END		
		ELSE
			AosOut.String("Host '"); AosOut.String(host); AosOut.String("' not found."); AosOut.Ln
		END
	UNTIL (r.res # AosIO.Ok);
	RETURN NIL
END Install;

BEGIN
	NEW(services)
END WebSSMPPlugin.
 

System.Free WebSSMPPlugin ~

Aos.Call WebSSMPPlugin.Install eth20853 ~
Aos.Call WebSSMPPlugin.Uninstall ~ TODO