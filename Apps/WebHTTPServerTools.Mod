(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE WebHTTPServerTools;	(** AUTHOR "be"; PURPOSE "User interface to HTTPServer"; *)

IMPORT AosOut, AosCommands, AosIO, WebHTTPServer;

CONST
	moduleName = "WebHTTPServerTools";
	
PROCEDURE Start*(par: PTR): PTR; (** ["\r:" default root directory] ["\l:" log file] *)
VAR p: AosCommands.Parameters; r: AosIO.StringReader; c, opt: CHAR; str, root, log, tls: ARRAY 1024 OF CHAR; 
BEGIN
	p := par(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^);

	root := ""; log := "";	
	r.SkipWhitespace();
	LOOP
		c := r.Get();
		IF (c # "\") THEN EXIT END;
		
		opt := CAP(r.Get());
		c := r.Get();
		IF (c # ":") THEN EXIT END;
		
		r.SkipWhitespace();
		r.String( str);
		r.SkipWhitespace();
		
		CASE opt OF
		| "R": COPY(str, root)
		| "L": COPY(str, log)
		| "S": COPY(str, tls)
		ELSE EXIT
		END
	END;

	IF tls = "on"  THEN
		WebHTTPServer.StartHTTPS(root, log);
	END;
	WebHTTPServer.StartHTTP(root, log);
	AosOut.String("HTTP server started. Default root directory = '"); AosOut.String(root); AosOut.String("'; logging ");
	IF (log = "") THEN AosOut.String("disabled")
	ELSE AosOut.String("to '"); AosOut.String(log); AosOut.Char("'")
	END;
	AosOut.Ln;
	RETURN NIL
END Start;

PROCEDURE Stop*(par: PTR): PTR;
VAR dummy: PTR;
BEGIN
	dummy := WebHTTPServer.StopHTTP(par);
	dummy := WebHTTPServer.StopHTTPS(par);
	AosOut.String("Server stopped."); AosOut.Ln;
	RETURN NIL
END Stop;

PROCEDURE AddHost*(par: PTR): PTR; (** host ["\r:" root directory] ["\d:" default file] ["\e:" error file] *)
VAR p: AosCommands.Parameters; r: AosIO.StringReader; c, opt: CHAR; str: ARRAY 256 OF CHAR;
	host: WebHTTPServer.Host;
BEGIN
	p := par(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^);
	
	r.String(str); r.SkipWhitespace();
	IF (str # "") THEN
		IF (WebHTTPServer.FindHosts(str) = NIL) THEN
			NEW(host, str);
			LOOP
				c := r.Get();
				IF (c # "\") THEN EXIT END;
				
				opt := CAP(r.Get());
				c := r.Get();
				IF (c # ":") THEN EXIT END;
				
				r.SkipWhitespace();
				r.String(str);
				r.SkipWhitespace();
				
				CASE opt OF
				| "R": host.SetPrefix(str)
				| "D": host.SetDefault(str)
				| "E": host.SetError(str)
				ELSE EXIT
				END
			END;
			
			WebHTTPServer.AddHost(host);
			AosOut.String("Added host '"); AosOut.String(host.name); AosOut.String("'; root = '"); AosOut.String(host.prefix); 
			AosOut.String("'; default = '"); AosOut.String(host.default); AosOut.String("'; error = '"); AosOut.String(host.error); AosOut.Char("'")
		ELSE
			AosOut.String(moduleName); AosOut.String(".AddHost: host '"); AosOut.String(str); AosOut.String("' already present.")
		END
	ELSE
		AosOut.String(moduleName); AosOut.String('.AddHost: expected parameters: host ["\r:" root directory] ["\d:" default file] ["\e:" error file]');
	END;
	AosOut.Ln;
	RETURN NIL
END AddHost;

PROCEDURE RemoveHost*(par: PTR): PTR; (** host *)
VAR p: AosCommands.Parameters; r: AosIO.StringReader; str: ARRAY 256 OF CHAR;
BEGIN
	p := par(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^);
	
	r.String( str); r.SkipWhitespace();
	IF (str # "") THEN
		WebHTTPServer.RemoveHost(str);
		AosOut.String("Host '"); AosOut.String(str); AosOut.String("' removed.")
	ELSE
		AosOut.String(moduleName); AosOut.String(".RemoveHost: expected parameters: host");
	END;
	AosOut.Ln;
	RETURN NIL
END RemoveHost;

PROCEDURE ListHosts*(par: PTR): PTR;
BEGIN
	AosOut.String("Virtual hosts:"); AosOut.Ln;
	WebHTTPServer.ShowHosts;
	RETURN NIL
END ListHosts;

END WebHTTPServerTools.

System.Free WebHTTPServerTools~

Aos.Call WebHTTPServerTools.Start \r:FAT:/httproot \l:FAT:/httproot/HTTP.Log \s:on~
Aos.Call WebHTTPServerTools.Start \r:AOS: \l:web.log~
Aos.Call WebHTTPServerTools.Stop

Aos.Call WebHTTPServerTools.AddHost livepc \r:FAT:/httproot/test~
Aos.Call WebHTTPServerTools.RemoveHost livepc.inf.ethz.ch~
Aos.Call WebHTTPServerTools.ListHosts

Aos.Call WebSSMPPlugin.Install ~
Aos.Call WebDefaultSSMP.Install ~
