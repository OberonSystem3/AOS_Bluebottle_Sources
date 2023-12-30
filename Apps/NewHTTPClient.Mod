MODULE NewHTTPClient; (** AUTHOR "TF"; PURPOSE "HTTP 1.1 client"; *)

IMPORT
	AosIO, WebHTTP, AosIP, AosDNS, AosTCP, Utilities, TFLog, AosModules, AosOut;


CONST
	ErrIllegalURL* = -1;
	ErrNotConnected* = -2;
	ErrIllegalResponse* = -3;
	
TYPE 
	LimitedInStream* = OBJECT
	VAR inR: AosIO.Reader;
		remain: LONGINT;
		
		PROCEDURE &Init(VAR inR, outR: AosIO.Reader; size : LONGINT);
		BEGIN
			SELF.inR := inR;	remain := size;
			AosIO.OpenReader(outR, Receiver);
		END Init;	
		
		PROCEDURE Receiver(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		VAR l, m: LONGINT;		
		BEGIN 
			IF remain > 0 THEN
				ASSERT((size > 0) & (min <= size) & (min >= 0));
				res := AosIO.Ok;
				l := size; IF l > remain THEN l := remain END;
				inR.Bytes(buf, ofs, l, len); 
				DEC(remain, len);
(*				AosOut.String("remain= "); AosOut.Int(remain, 0); AosOut.Ln; *)
			ELSE res := AosIO.EOF
			END
		END Receiver;
	END LimitedInStream;	


	HTTPConnection* = OBJECT
	VAR host, referer, useragent, accept : ARRAY 128 OF CHAR;
		port : LONGINT;
		http11 : BOOLEAN;
		con : AosTCP.Connection;
		requestHeader*: WebHTTP.RequestHeader;
		responseHeader*: WebHTTP.ResponseHeader; 		
		
		PROCEDURE &New;
		BEGIN
			requestHeader.referer := "";
			requestHeader.useragent := "BimBrowser (BimbOS 2004)";
		END New;

		PROCEDURE Open;
		VAR 
			fadr: AosIP.Adr;
			res : LONGINT;
			
		BEGIN
			IF (con # NIL) & (con.state = AosTCP.Established) THEN RETURN END;
			AosDNS.HostByName(host, fadr, res);
			IF res = AosDNS.Ok THEN 
				NEW(con); con.Open(AosTCP.NilPort, fadr, port, res);
				IF res # AosTCP.Ok THEN con := NIL END
			END
		END Open;
		
		PROCEDURE Close*;
		BEGIN
			IF con # NIL THEN con.Close; con := NIL END;
		END Close;
		
		PROCEDURE Get*(url : ARRAY OF CHAR; http11 : BOOLEAN; VAR out : AosIO.Reader; VAR res : LONGINT);
		VAR w : AosIO.Writer; r : AosIO.Reader;
			x : WebHTTP.AdditionalField;
			host : ARRAY 128 OF CHAR;
			path : ARRAY 2048 OF CHAR;
			port : LONGINT;
			dechunk: WebHTTP.ChunkedInStream;
			lin : LimitedInStream;
		BEGIN
			requestHeader.maj := 1;
			IF http11 THEN requestHeader.min := 1 ELSE requestHeader.min := 0 END;

			IF WebHTTP.SplitHTTPAdr(url, host, path, port) THEN 
				IF (host # SELF.host) OR (port # SELF.port) THEN Close END;
				COPY(host, SELF.host);
				SELF.port := port;

				IF path = "" THEN path := "/" END;
				(* (re)establish the connection *)
				Open;
				IF con = NIL THEN res := ErrNotConnected; RETURN END;
				AosIO.OpenWriter(w, con.Send); AosIO.OpenReader(r, con.Receive);
				
				WebHTTP.WriteRequestLine(w, requestHeader.maj, requestHeader.min, WebHTTP.GetM, path, host); 
				
				IF requestHeader.referer # "" THEN w.String("Referer: "); w.String(requestHeader.referer); w.Ln() END;
				IF requestHeader.useragent # "" THEN w.String("User-Agent: "); w.String(requestHeader.useragent); w.Ln() END;
				IF requestHeader.accept # "" THEN w.String("Accept: "); w.String(requestHeader.accept); w.Ln() END;
				x := requestHeader.additionalFields;
				WHILE x # NIL DO
					w.String(x.key);  w.Char(" "); w.String(x.value);w.Ln();

					x := x.next
				END;
				w.Ln(); w.Update();
					
				WebHTTP.ParseReply(r, responseHeader, res, log);
				
				IF (Utilities.Pos("hunked", responseHeader.transferencoding) > 0) THEN NEW(dechunk, r, out)
				ELSIF responseHeader.contentlength >= 0 THEN NEW(lin, r, out, responseHeader.contentlength)
				ELSE out := r
				END;

(*				WebHTTP.LogResponseHeader(log, responseHeader);*)
				res := 0;
				x := responseHeader.additionalFields;
				WHILE x # NIL DO
					x := x.next
				END;


			ELSE
				res := ErrIllegalURL
			END	
			
		END Get;
		
	END HTTPConnection;
	
VAR log : TFLog.Log;		

PROCEDURE CleanUp;
BEGIN
	log.Close
END CleanUp;


PROCEDURE Test*(par : ANY) : ANY;
VAR h : HTTPConnection;
	r : AosIO.Reader;
	res : LONGINT;
BEGIN
	NEW(h);
	h.Get("http://www.bimbodot.org", TRUE, r, res);
	AosOut.String("res= "); AosOut.Int(res, 0); AosOut.Ln; 
	WHILE r.res = 0 DO AosOut.Char(r.Get()) END;
	AosOut.String("Loop finished"); 
	h.Close;
	RETURN NIL
END Test;


PROCEDURE TestGoogle*(par : ANY) : ANY;
VAR h : HTTPConnection;
	r : AosIO.Reader;
	res : LONGINT;
	af1, af2, af3, af4, af5: WebHTTP.AdditionalField;
BEGIN
	NEW(h);
	
	(* Mit Mozilla als User Agent kriegt man UTF-8 *)
	h.requestHeader.useragent := "Mozilla/5.0";
	
	(* Mit BimBrowser ISO-8859-1 *)
	(* h.requestHeader.useragent := "BimBrowser (bluebottle.ethz.ch)"; *)
	
	(* ... auch wenn man UTF-8 anfordert ... *)
	(*h.requestHeader.useragent := "BimBrowser (bluebottle.ethz.ch)";
	NEW(af1);
	af1.key := "Accept-Charset:";
	af1.value := "utf-8";
	h.requestHeader.additionalFields := af1;*)

	(* ... auch wenn sonst alles identisch ist, wie bei Mozilla: *)
	(*h.requestHeader.useragent := "BimBrowser (bluebottle.ethz.ch)";
	h.requestHeader.accept := "text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,image/jpeg,image/gif;q=0.2,*/*;q=0.1";
	NEW(af1); NEW(af2); NEW(af3); NEW(af4); NEW(af5);
	af1.key := "Accept-Language:";
	af1.value := "de,en-us;q=0.7,en;q=0.3";
	af1.next := af2;
	af2.key := "Accept-Encoding:";
	af2.value := ""; (* af2.value := "gzip,deflate"; *)
	af2.next := af3;
	af3.key := "Accept-Charset:";
	af3.value := "utf-8,ISO-8859-1;q=0.7,*;q=0.7"; (* habe utf-8 und ISO vertauscht *)
	af3.next := NIL;
	af4.key := "Keep-Alive:";
	af4.value := "300";
	af4.next := af5;
	af5.key := "Connection:";
	af5.value := "keep-alive";
	h.requestHeader.additionalFields := af1;*)

	h.Get("http://www.google.ch", TRUE, r, res);
	AosOut.String("res= "); AosOut.Int(res, 0); AosOut.Ln; 
	WHILE r.res = 0 DO AosOut.Char(r.Get()) END;
	AosOut.String("Loop finished"); 
	h.Close;
	RETURN NIL
END TestGoogle;

BEGIN
	NEW(log, "HTTP Client");
	log.SetLogToOut(TRUE);
	AosModules.InstallTermHandler(CleanUp)	
END NewHTTPClient.

S.Free NewHTTPClient ~
NewHTTPClient.Test ~
NewHTTPClient.TestGoogle ~
