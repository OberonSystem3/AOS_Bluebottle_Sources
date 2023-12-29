MODULE WebHTTP; (** AUTHOR "tf/be"; PURPOSE "HTTP parsing"; *)
(* 02.04.2003 es, additional result codes, WebDAV methods. *)
(* 12.04.2003 es, WebDAV result codes. *)

IMPORT AosIP, TFLog, AosIO, Utilities;

CONST
	HTTPPort* = 80;
	
	(** HTTP Result Codes *)
	(*     Informational      *)
	Continue* = 100;
	SwitchingProtocols* = 101;
	Processing* = 102; (* RFC 2518 *)
	(*         Successful        *)
	OK* = 200;
	Created* = 201;
	Accepted*= 202;
	NonAuthoritativeInformation*= 203;
	NoContent*= 204;
	ResetContent*= 205;
	PartialContent*= 206;
	MultiStatus* = 207; (* RFC 2518 *)
	(*	Redirection	*)
	MultipleChoices*= 300;
	ObjectMoved* = 301; (* moved permananently *)
	ObjectMovedTemporarily* = 302;  (* found *)
	SeeOther*= 303;
	NotModified* = 304;
	UseProxy*= 305;
	TemporaryRedirect*= 307;
	(*	Client Error	*)
	BadRequest* = 400;
	Unauthorized* = 401;
	PaymentRequired*= 402;
	Forbidden* = 403;
	NotFound* = 404;
	MethodNotAllowed*= 405;
	NotAcceptable*= 406;
	ProxyAuthenticationRequested*= 407;
	RequestTimeout*= 408;
	Conflict* = 409;
	Gone*= 410;
	LengthRequired* = 411;
	PreconditionFailed* = 412;
	RequestEntityTooLarge*= 413;
	RequestURITooLong* = 414;
	UnsupportedMediaType*= 415;
	RequestedRangeNotSatisfiable*= 416;
	ExpectationFailed*= 417;
	UnprocessableEntity* = 422; (* RFC 2518 *)
	Locked* = 423; (* RFC 2518 *)
	FailedDependency*= 424; (* RFC 2518 *)
	(*      Server Error     *)
	InternalServerError* = 500;
	NotImplemented* = 501;
	BadGateway*= 502;
	ServiceUnavailable*= 503;
	GatewayTimeout*= 504;
	VersionNotSupported* = 505;
	InsufficientStorage* = 507; (* RFC 2518 *)
	
	(** HTTP methods RFC 2616 Section 5.1.1*)
	UnknownM* = 0; GetM* = 1; HeadM* = 2; PutM* = 3; PostM* = 4; OptionsM* = 5; 
	TraceM* = 6; DeleteM* = 7; ConnectM* = 8;

	(** new HTTP methods RFC 2518 Section 8: HTTP Extensions for Distributed Authoring -- WebDAV *)
	PropfindM* = 10; ProppatchM* = 11; MkcolM* = 12; CopyM* = 13; MoveM* = 14; LockM* = 15; UnlockM* = 16;

	(** new HTTP methods RFC 3253 Versioning Extensions to  WebDAV *)
	VersionControlM* = 17; ReportM* = 18; CheckoutM* = 19; CheckinM* = 20; UncheckoutM* = 21;
	MkworkspaceM* = 22; UpdateM* = 23; LabelM* = 24; MergeM* = 25; BaselineControlM* = 26; MkactivityM* = 27;
	
	(** HTTP date & time format *)
	DateTimeFormat* = "www, dd mmm yyyy hh:nn:ss GMT";
	
	(* Chunker stuff *)
	BufSize = 400H;
	TokenSize = 10H;
	

TYPE
	AdditionalField* = POINTER TO RECORD
		key* : ARRAY 64 OF CHAR;
		value* : ARRAY 1024 OF CHAR;
		next* : AdditionalField;
	END;
	
	RequestHeader* = RECORD
		fadr* : AosIP.Adr;
		fport* : LONGINT;
		method* : LONGINT;
		maj*, min* : LONGINT;
		uri* : ARRAY 4096 OF CHAR;
		host* : ARRAY 256 OF CHAR;
		referer* : ARRAY 256 OF CHAR;
		useragent* : ARRAY 256 OF CHAR;
		accept* : ARRAY 256 OF CHAR;
		transferencoding* : ARRAY 64 OF CHAR;
		additionalFields* : AdditionalField;
	END;
	
	ResponseHeader* = RECORD
		maj*, min* : LONGINT;
		statuscode* : LONGINT;
		reasonphrase* : ARRAY 256 OF CHAR;
		server* : ARRAY 256 OF CHAR;
		date* : ARRAY 32 OF CHAR;
		location*: ARRAY 1024 OF CHAR;
		contenttype* : ARRAY 64 OF CHAR;
		contentlength* : LONGINT;
		contentlocation*: ARRAY 1024 OF CHAR;
		transferencoding* : ARRAY 64 OF CHAR;
		lastmodified*: ARRAY 32 OF CHAR;
		additionalFields* : AdditionalField;
	END;
	
	ChunkedOutStream* = OBJECT
		VAR (* General vars: *)
			outW: AosIO.Writer;
			buf: ARRAY BufSize OF CHAR;
			bufPos: LONGINT;
			chunked: BOOLEAN;
						
			(* Chunked mode vars *)
			token: ARRAY TokenSize OF CHAR;
			tokLen: INTEGER;
			
		PROCEDURE &Init(VAR inW: AosIO.Writer; outW: AosIO.Writer; VAR request: RequestHeader; VAR reply: ResponseHeader);
		BEGIN
			SELF.outW := outW;
			chunked := Version(request, 1,1);
			IF chunked THEN
				AosIO.OpenWriter(inW, Sender);
				COPY("chunked", reply.transferencoding);
				reply.contentlength := -1
			ELSE
				inW := outW
			END				
		END Init;
				
		PROCEDURE Sender(VAR inBuf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		VAR i: LONGINT;
		BEGIN
			ASSERT(chunked);
			i := ofs;
			WHILE (i < ofs+len) DO
				buf[bufPos] := inBuf[i];
				INC(i);
				INC(bufPos);				
				IF bufPos = BufSize THEN WriteChunked() END;
				IF propagate THEN outW.Update() END
			END
		END Sender;
						
		PROCEDURE WriteChunked;
		BEGIN (* inv: chunked=TRUE *)
			Utilities.IntToHexStr(bufPos, 8, token);
			outW.String(token);
			outW.Ln();
			outW.Bytes(buf, 0, bufPos);
			outW.Ln();
			bufPos := 0
		END WriteChunked;
		
		PROCEDURE Update*;
		BEGIN
			IF chunked THEN WriteChunked() END;
			outW.Update()
		END Update;
						
		PROCEDURE Close*;
		BEGIN
			IF chunked THEN
				IF bufPos > 0 THEN WriteChunked() END;
				outW.Char("0");
				outW.Ln();
				outW.Ln()
			END;
			outW.Update()
		END Close;
	END ChunkedOutStream;
	
	ChunkedInStream* = OBJECT
		VAR (* General vars: *)
			inR: AosIO.Reader;
			remain: LONGINT;
			eof : BOOLEAN;
			(* Chunked mode vars: *)
			chunkSize: LONGINT;
		
		PROCEDURE &Init(VAR inR, outR: AosIO.Reader);
		BEGIN
			SELF.inR := inR;
			AosIO.OpenReader(outR, Receiver);
			eof := FALSE
		END Init;	
		
		PROCEDURE Receiver(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		VAR i: LONGINT; token: ARRAY 16 OF CHAR; ch: CHAR;			
		BEGIN 
			IF ~eof THEN
				ASSERT((size > 0) & (min <= size) & (min >= 0));
				len := 0; i := ofs; res := AosIO.Ok; chunkSize := -1;
				WHILE (chunkSize # 0) & (res = AosIO.Ok) & (len < size) DO
					(* Read the chunk size *)
					IF remain = 0 THEN
						inR.SkipSpaces(); 
						inR.Token(token);
						Utilities.HexStrToInt(token, chunkSize, res);
						inR.SkipLn(); 
						remain := chunkSize
					END;
					(* Fill data into out buffer *)
					WHILE (res = AosIO.Ok) & (len < size) & (remain > 0) DO
						inR.Char(ch);
						res := inR.res; 
						buf[i] := ch;
						INC(len); INC(i); DEC(remain)
					END;
					IF (remain = 0) & (chunkSize > 0) THEN
						inR.SkipLn()
					END
				END;
				IF chunkSize = 0 THEN eof := TRUE END
			ELSE
				res := AosIO.EOF
			END
		END Receiver;
	END ChunkedInStream;	

PROCEDURE EOL(VAR in: AosIO.Reader): BOOLEAN;
BEGIN
	in.SkipSpaces();
	RETURN in.EOLN()
END EOL;

PROCEDURE GetToken(VAR in: AosIO.Reader; VAR token: ARRAY OF CHAR);
BEGIN
	in.SkipSpaces(); in.Token(token)
END GetToken;

PROCEDURE GetInt(VAR i: LONGINT; VAR buf: ARRAY OF CHAR; VAR x: LONGINT);
VAR ch: CHAR;
BEGIN
	x := 0;
	LOOP
		ch := buf[i];
		IF (ch < "0") OR (ch > "9") THEN EXIT END;
		x := x * 10 + (ORD(ch)-ORD("0")); INC(i)
	END
END GetInt;

PROCEDURE Match(VAR buf: ARRAY OF CHAR; with: ARRAY OF CHAR; VAR i: LONGINT): BOOLEAN;
VAR j: LONGINT;
BEGIN
	j := 0; WHILE (with[j] # 0X) & (buf[i] = with[j]) DO INC(i); INC(j) END;
	RETURN with[j] = 0X
END Match;

PROCEDURE EqualsI(VAR buf: ARRAY OF CHAR; with: ARRAY OF CHAR): BOOLEAN;
VAR j: LONGINT;
BEGIN
	j := 0; WHILE (with[j] # 0X) & (CAP(buf[j]) = CAP(with[j])) DO INC(j) END;
	RETURN CAP(with[j]) = CAP(buf[j])
END EqualsI;

(** Currently only for additional fields *)
PROCEDURE HasAdditionalField*(af : AdditionalField; fieldName: ARRAY OF CHAR) : BOOLEAN;
BEGIN
	WHILE (af # NIL) & (~EqualsI(af.key, fieldName)) DO af := af.next END;
	RETURN af # NIL
END HasAdditionalField;

(** Currently only for additional fields *)
PROCEDURE GetAdditionalFieldValue*(af: AdditionalField; fieldName: ARRAY OF CHAR; VAR value : ARRAY OF CHAR) : BOOLEAN;
BEGIN
	WHILE (af # NIL) & (~EqualsI(af.key, fieldName)) DO af := af.next END;
	IF af # NIL THEN
		COPY(af.value, value);
		RETURN TRUE
	ELSE 
		RETURN FALSE
	END
END GetAdditionalFieldValue;

(** return request property as a string *)
PROCEDURE GetRequestPropertyValue*(VAR header : RequestHeader; propertyName : ARRAY OF CHAR; VAR result : ARRAY OF CHAR);
BEGIN
	IF propertyName = "#ip" THEN AosIP.AdrToStr(header.fadr, result)
	ELSIF propertyName = "#port" THEN Utilities.IntToStr(header.fport, result)
	ELSIF propertyName = "#method" THEN 
		CASE header.method OF
			|GetM : COPY("GET", result)
			|HeadM : COPY("HEAD", result)
			|PutM : COPY("PUT", result)
			|PostM : COPY("POST", result)
			|OptionsM : COPY("OPTIONS", result)
		ELSE COPY("unknown", result)
		END
	ELSIF propertyName = "host" THEN COPY(header.host, result)
	ELSIF propertyName = "referer" THEN COPY(header.referer, result)
	ELSIF propertyName = "useragent" THEN COPY(header.useragent, result)
	ELSIF propertyName = "accept" THEN COPY(header.accept, result)
	ELSIF propertyName = "transferencoding" THEN COPY(header.transferencoding, result)
	ELSE
		IF ~GetAdditionalFieldValue(header.additionalFields, propertyName, result) THEN COPY("", result) END
	END
END GetRequestPropertyValue;

(** Currently only for additional fields *)
PROCEDURE SetAdditionalFieldValue*(VAR af: AdditionalField; fieldName, value: ARRAY OF CHAR);
VAR a: AdditionalField;
BEGIN
	IF (af = NIL) THEN NEW(a); af := a
	ELSE
		a := af; WHILE (a.next # NIL) & (a.key # fieldName) DO a := a.next END;
		IF (a.key # fieldName) THEN
			NEW(a.next); a := a.next
		END
	END;
	COPY(fieldName, a.key); COPY(value, a.value)
END SetAdditionalFieldValue;

PROCEDURE GetVersion(VAR ver: ARRAY OF CHAR; VAR maj, min: LONGINT);
VAR i: LONGINT;
BEGIN
	i := 0; maj := 0; min := 0;
	IF Match(ver, "HTTP/", i) THEN
		GetInt(i, ver, maj);
		IF ver[i] = "." THEN INC(i) END;
		GetInt(i, ver, min)
	END
END GetVersion;

(** Version - returns TRUE iff the HTTP version specified in h.maj/h.min is bigger or equal to Maj/Min *)
PROCEDURE Version*(VAR h: RequestHeader; Maj, Min: LONGINT): BOOLEAN;
BEGIN
	RETURN (h.maj > Maj) OR ((h.maj = Maj) & (h.min >= Min))
END Version;

PROCEDURE GetMethod*(VAR s: ARRAY OF CHAR; VAR method: LONGINT);
BEGIN
	IF s = "GET" THEN method := GetM
	ELSIF s = "HEAD" THEN method := HeadM
	ELSIF s = "OPTIONS" THEN method := OptionsM
	ELSIF s = "POST" THEN method := PostM
	ELSIF s = "PUT" THEN method := PutM
	ELSIF s = "DELETE" THEN method := DeleteM
	ELSIF s = "TRACE" THEN method := TraceM
	ELSIF s = "CONNECT" THEN method := ConnectM
	(*	WebDAV	*)
	ELSIF s = "PROPFIND" THEN method := PropfindM
	ELSIF s = "PROPPATCH" THEN method := ProppatchM
	ELSIF s = "MKCOL" THEN method := MkcolM
	ELSIF s = "COPY" THEN method := CopyM
	ELSIF s = "MOVE" THEN method := MoveM
	ELSIF s = "LOCK" THEN method := LockM
	ELSIF s = "UNLOCK" THEN method := UnlockM
	(*	DeltaV	*)
	ELSIF s = "VERSION-CONTROL" THEN method := VersionControlM
	ELSIF s = "REPORT" THEN method := ReportM
	ELSIF s = "CHECKOUT" THEN method := CheckoutM
	ELSIF s = "CHECKIN" THEN method := CheckinM
	ELSIF s = "UNCHECKOUT" THEN method := UncheckoutM
	ELSIF s = "MKWORKSPACE" THEN method := MkworkspaceM
	ELSIF s = "UPDATE" THEN method := UpdateM
	ELSIF s = "LABEL" THEN method := LabelM
	ELSIF s = "MERGE" THEN method := MergeM
	ELSIF s = "BASELINE-CONTROL" THEN method := BaselineControlM
	ELSIF s = "MKACTIVITY" THEN method := MkactivityM
	ELSE method := UnknownM
	END
END GetMethod;

PROCEDURE GetMethodName*(code: LONGINT; VAR name: ARRAY OF CHAR);
BEGIN
	CASE code OF 
		GetM : COPY("GET", name)
		|HeadM : COPY("HEAD", name);
		|OptionsM : COPY("OPTIONS", name);
		|PostM : COPY("POST", name);
		|PutM : COPY("PUT", name);
		|DeleteM : COPY("DELETE", name);
		|TraceM : COPY("TRACE", name);
		|ConnectM : COPY("CONNECT", name);
		(*	WebDAV	*)
		|PropfindM: COPY("PROPFIND", name);
		|ProppatchM: COPY("PROPPATCH", name);
		|MkcolM: COPY("MKCOL", name);
		|CopyM: COPY("COPY", name);
		|MoveM: COPY("MOVE", name);
		|LockM: COPY("LOCK", name);
		|UnlockM: COPY("UNLOCK", name);
		(*	DeltaV	*)
		|VersionControlM: COPY("VERSION-CONTROL", name);
		|ReportM: COPY("REPORT", name);
		|CheckoutM: COPY("CHECKOUT", name);
		|CheckinM: COPY("CHECKIN", name);
		|UncheckoutM: COPY("UNCHECKOUT", name);
		|MkworkspaceM: COPY("MKWORKSPACE", name);
		|UpdateM: COPY("UPDATE", name);
		|LabelM: COPY("LABEL", name);
		|MergeM: COPY("MERGE", name);
		|BaselineControlM: COPY("BASELINE-CONTROL", name);
		|MkactivityM: COPY("MKACTIVITY", name);
		ELSE COPY("UNKOWN", name)
	END;
END GetMethodName;

PROCEDURE ParseRequest*(VAR in: AosIO.Reader; VAR header: RequestHeader; VAR res: LONGINT; log : TFLog.Log);
VAR s: ARRAY 32 OF CHAR; af: AdditionalField; ch :CHAR; 
BEGIN
	header.host[0] := 0X;
	GetToken(in, s); GetMethod(s, header.method);
	GetToken(in, header.uri);	
	GetToken(in, s); GetVersion(s, header.maj, header.min);
	IF EOL(in) & (header.method # UnknownM) & (header.uri # "") THEN
		in.SkipLn();
		IF header.maj >= 1 THEN
			REPEAT
				GetToken(in, s);
				Utilities.TrimRight(s, ":");
				IF s = "Host" THEN in.Char(ch); in.Ln(header.host) 
				ELSIF s = "Referer" THEN in.Char(ch); in.Ln(header.referer) 
				ELSIF s = "User-Agent" THEN in.Char(ch); in.Ln(header.useragent) 
				ELSIF s = "Accept" THEN in.Char(ch); in.Ln(header.accept)
				ELSIF s = "Transfer-Encoding" THEN in.Char(ch); in.Ln( header.transferencoding)
				ELSE 
					NEW(af); COPY(s, af.key); in.Char(ch); in.Ln(af.value);
					af.next := header.additionalFields; header.additionalFields := af
				END;
			UNTIL (in.res # AosIO.Ok) OR in.EOLN();
			in.SkipLn();
			res := OK
		ELSE
			IF log # NIL THEN log.Enter; log.String("Unsupported HTTP version :"); log.Int(header.maj, 5); log.Exit END;
			res := VersionNotSupported
		END
	ELSE
			IF log # NIL THEN log.Enter; log.String("Unsupported HTTP method :"); log.Int(header.method, 5); log.Exit END;
		res := BadRequest
	END
END ParseRequest;

PROCEDURE ParseReply*(VAR in: AosIO.Reader; VAR header: ResponseHeader; VAR res: LONGINT; log : TFLog.Log);
VAR s: ARRAY 32 OF CHAR; af: AdditionalField;
	i :LONGINT; ch :CHAR;
BEGIN
	GetToken(in, s); GetVersion(s, header.maj, header.min);
	GetToken(in, s); i := 0; GetInt(i, s, header.statuscode); in.Ln(header.reasonphrase);
	IF header.maj >= 1 THEN
		REPEAT
			GetToken(in, s);
			Utilities.TrimRight(s, ":");
			IF s = "Server" THEN in.Char(ch); in.Ln(header.server) 
			ELSIF s = "Date"THEN in.Char(ch);in.Ln(header.date) 
			ELSIF s = "Content-Type"THEN in.Char(ch); in.Ln(header.contenttype) 
			ELSIF s = "Content-Length"THEN in.Char(ch); in.Ln(s); Utilities.StrToInt(s, header.contentlength)
			ELSIF s = "Transfer-Encoding"THEN in.Char(ch); in.Ln(header.transferencoding)
			ELSE 
				NEW(af); COPY(s, af.key); in.Char(ch); in.Ln(af.value);
				af.next := header.additionalFields; header.additionalFields := af
			END;
		UNTIL (in.res # AosIO.Ok) OR in.EOLN();
		in.SkipLn();
		res := OK
	ELSE
		IF log # NIL THEN log.Enter; log.String("Unsupported HTTP version :"); log.Int(header.maj, 5); log.Exit END;
		res := VersionNotSupported
	END;
END ParseReply;

PROCEDURE LogRequestHeader*(log : TFLog.Log; VAR header : RequestHeader);
VAR s : ARRAY 32 OF CHAR; x: AdditionalField;
BEGIN
	log.Enter; 
	log.String("BEGIN HTTP-Request Header information ("); log.TimeStamp; log.String(")"); log.Ln;
	log.String(" HTTP request from "); AosIP.AdrToStr(header.fadr, s); log.String(s); log.String(" : "); log.Int(header.fport, 5); log.Ln;
	log.String("Request: ");
	GetMethodName(header.method, s); log.String(s);
	log.String(" "); log.String(header.uri); log.Ln;
	IF header.host # "" THEN log.String("Host: "); log.String(header.host); log.Ln END;
	IF header.referer # "" THEN log.String("Referer: "); log.String(header.referer); log.Ln END;
	IF header.useragent # "" THEN log.String("User-Agent: "); log.String(header.useragent); log.Ln END;
	IF header.accept # "" THEN log.String("Accept: "); log.String(header.accept); log.Ln END;
	x := header.additionalFields;
	WHILE x # NIL DO
		log.String(x.key); log.String(": "); log.String(x.value); log.Ln;
		x := x.next
	END;
	log.String("END HTTP-Request Header information"); log.Ln; log.Ln;
	log.Exit;
END LogRequestHeader;

PROCEDURE LogResponseHeader*(log : TFLog.Log; VAR header : ResponseHeader);
VAR s : ARRAY 16 OF CHAR; x: AdditionalField;
BEGIN
	log.Enter; 
	log.String("BEGIN HTTP-Reply Header information ("); log.TimeStamp; log.String(")"); log.Ln;
	log.String("Status Code: "); log.Int(header.statuscode, 5); log.String(" Reason: "); log.String(header.reasonphrase); log.Ln;
	IF header.server # "" THEN log.String("Server: "); log.String(header.server); log.Ln END;
	IF header.date # "" THEN log.String("Date: "); log.String(header.date); log.Ln END;
	IF header.location # "" THEN log.String("Location: "); log.String(header.location); log.Ln END;
	IF header.contenttype # "" THEN log.String("Content-Type: "); log.String(header.contenttype); log.Ln END;
	IF header.contentlength # 0 THEN log.String("Content-Length: "); log.Int(header.contentlength, 0); log.Ln END;
	IF header.contentlocation # "" THEN log.String("Content-Location: "); log.String(header.contentlocation); log.Ln END;
	IF header.transferencoding # "" THEN log.String("Transfer-Encoding: "); log.String(header.transferencoding); log.Ln END;
	IF header.lastmodified # "" THEN log.String("Last-Modified: "); log.String(header.lastmodified); log.Ln END;
	x := header.additionalFields;
	WHILE x # NIL DO
		log.String(x.key); log.String(": "); log.String(x.value); log.Ln;
		x := x.next
	END;
	log.String("END HTTP-Reply Header information"); log.Ln; log.Ln;
	log.Exit;
END LogResponseHeader;

PROCEDURE WriteRequestLine*(VAR s: AosIO.Writer; maj, min : LONGINT; method : LONGINT; uri, host : ARRAY OF CHAR);
VAR name: ARRAY 32 OF CHAR;
BEGIN
	GetMethodName(method, name);
	IF name = "UNKNOWN" THEN RETURN ELSE s.String(name) END;
	s.String(" "); s.String(uri); s.String(" ");
	s.String("HTTP/"); s.Int(maj, 1); s.String("."); s.Int(min, 1);
	s.Ln();
	IF host # "" THEN s.String("Host: "); s.String(host); s.Ln() END
END WriteRequestLine;

PROCEDURE WriteStatus*(VAR h: ResponseHeader; VAR dst: AosIO.Writer);
VAR s: ARRAY 64 OF CHAR;
BEGIN
	dst.String("HTTP/"); dst.Int(h.maj, 1); dst.String("."); dst.Int(h.min, 1);
	dst.String(" ");dst.Int(h.statuscode, 1); dst.String(" ");
	(*	Informational	*)
	IF (h.statuscode =  Continue) THEN COPY("Continue", h.reasonphrase)
	ELSIF (h.statuscode = SwitchingProtocols) THEN COPY("Switching Protocols", h.reasonphrase)
	ELSIF (h.statuscode =  Processing) THEN COPY("Processing", h.reasonphrase)
	(*	successful	*)
	ELSIF (h.statuscode = OK) THEN COPY("OK", h.reasonphrase);
	ELSIF (h.statuscode = Created) THEN COPY("Created", h.reasonphrase)
	ELSIF (h.statuscode = Accepted) THEN COPY("Accepted", h.reasonphrase)
	ELSIF (h.statuscode = NonAuthoritativeInformation) THEN COPY("Non-Authoritative Information", h.reasonphrase)
	ELSIF (h.statuscode = NoContent) THEN COPY("No Content", h.reasonphrase)
	ELSIF (h.statuscode = ResetContent) THEN COPY("Reset Content", h.reasonphrase)
	ELSIF (h.statuscode = PartialContent) THEN COPY("Partial Content", h.reasonphrase)
	ELSIF (h.statuscode = MultiStatus) THEN COPY("Multi-Status", h.reasonphrase)
	(*	Redirection	*)
	ELSIF (h.statuscode = MultipleChoices) THEN COPY("Multiple Choices", h.reasonphrase)
	ELSIF (h.statuscode = ObjectMoved) THEN COPY("Object moved", h.reasonphrase)
	ELSIF (h.statuscode = ObjectMovedTemporarily) THEN COPY("Object Moved Temporarily", h.reasonphrase)
	ELSIF (h.statuscode = SeeOther) THEN COPY("See Other", h.reasonphrase)
	ELSIF (h.statuscode = NotModified) THEN COPY("Not modified", h.reasonphrase)
	ELSIF (h.statuscode = UseProxy) THEN COPY("Use Proxy", h.reasonphrase)
	ELSIF (h.statuscode = TemporaryRedirect) THEN COPY("Temporary Redirect", h.reasonphrase)
	(*	Client Error	*)
	ELSIF (h.statuscode = BadRequest) THEN COPY("Bad request", h.reasonphrase)
	ELSIF (h.statuscode = Unauthorized) THEN COPY("Unauthorized", h.reasonphrase)
	ELSIF (h.statuscode = PaymentRequired) THEN COPY("Payment Required", h.reasonphrase)
	ELSIF (h.statuscode = Forbidden) THEN COPY("Forbidden", h.reasonphrase)
	ELSIF (h.statuscode = NotFound) THEN COPY("Not found", h.reasonphrase)
	ELSIF (h.statuscode = MethodNotAllowed) THEN COPY("Method Not Allowed", h.reasonphrase)
	ELSIF (h.statuscode = NotAcceptable) THEN COPY("Not Acceptable", h.reasonphrase)
	ELSIF (h.statuscode = ProxyAuthenticationRequested) THEN COPY("Proxy Authentication Requested", h.reasonphrase)
	ELSIF (h.statuscode = RequestTimeout) THEN COPY("Request Timeout", h.reasonphrase)
	ELSIF (h.statuscode = Conflict) THEN COPY("Conflict", h.reasonphrase)
	ELSIF (h.statuscode = Gone) THEN COPY("Gone", h.reasonphrase)
	ELSIF (h.statuscode = LengthRequired) THEN COPY("Length required", h.reasonphrase)
	ELSIF (h.statuscode = PreconditionFailed) THEN COPY("Precondition failed", h.reasonphrase)
	ELSIF (h.statuscode = RequestEntityTooLarge) THEN COPY("Request Entity Too Large", h.reasonphrase)
	ELSIF (h.statuscode = RequestURITooLong) THEN COPY("Request URI too long", h.reasonphrase)
	ELSIF (h.statuscode = UnsupportedMediaType) THEN COPY("Unsupported Media Type", h.reasonphrase)
	ELSIF (h.statuscode = RequestedRangeNotSatisfiable) THEN COPY("Requested Range Not Satisfiable", h.reasonphrase)
	ELSIF (h.statuscode = ExpectationFailed) THEN COPY("Expectation Failed", h.reasonphrase)
	ELSIF (h.statuscode = UnprocessableEntity) THEN COPY("Unprocessable Entity", h.reasonphrase)
	ELSIF (h.statuscode = Locked) THEN COPY("Locked", h.reasonphrase)
	ELSIF (h.statuscode = FailedDependency) THEN COPY("Failed Dependency", h.reasonphrase)
	(*	Server Error	*)
	ELSIF (h.statuscode = InternalServerError) THEN COPY("Internal server error", h.reasonphrase)
	ELSIF (h.statuscode = NotImplemented) THEN COPY("Operation not implemented", h.reasonphrase)
	ELSIF (h.statuscode = BadGateway) THEN COPY("Bad Gateway", h.reasonphrase)
	ELSIF (h.statuscode = ServiceUnavailable) THEN COPY("Service Unavailable", h.reasonphrase)
	ELSIF (h.statuscode = GatewayTimeout) THEN COPY("Gateway Timeout", h.reasonphrase)
	ELSIF (h.statuscode = VersionNotSupported) THEN COPY("HTTP Version not supported", h.reasonphrase)
	ELSIF (h.statuscode = InsufficientStorage) THEN COPY("Insufficient Storage", h.reasonphrase)
	ELSE COPY("Unknown Status Code", h.reasonphrase) (* Was "HTTP server error" *)
	END;
	dst.String(h.reasonphrase); dst.Ln();
	dst.String("Server: "); dst.String(h.server); dst.Ln()
END WriteStatus;

PROCEDURE SendResponseHeader*(VAR h: ResponseHeader; VAR dst: AosIO.Writer);
VAR s: ARRAY 32 OF CHAR; af: AdditionalField;
BEGIN
	WriteStatus(h, dst);
	Utilities.FormatDateTime("www, dd mmm yyyy, hh:nn:ss GMT", Utilities.Now(), s);
	dst.String("Date: "); dst.String(s); dst.Ln();
	IF (h.statuscode # NotModified) THEN
		IF (h.location # "") THEN
			dst.String("Location: "); dst.String(h.location); dst.Ln()
		END;
		dst.String("Content-Type: "); dst.String(h.contenttype); dst.Ln();
		IF (h.contentlength >= 0) THEN
			dst.String("Content-Length: "); dst.Int( h.contentlength, 1); dst.Ln()
		END;
		IF (h.contentlocation # "") THEN
			dst.String("Content-Location: "); dst.String(h.contentlocation); dst.Ln()
		END;
		IF (h.transferencoding # "") THEN
			dst.String("Transfer-Encoding: "); dst.String(h.transferencoding); dst.Ln()
		END;
		IF (h.lastmodified # "") THEN
			dst.String("Last-Modified: ");dst.String(h.lastmodified); dst.Ln()
		END;
		af := h.additionalFields;
		WHILE (af # NIL) DO
			dst.String(af.key); dst.String(": "); dst.String(af.value); dst.Ln();
			af := af.next
		END
	END;
	dst.Ln()
END SendResponseHeader;

PROCEDURE SplitHTTPAdr*(url : ARRAY OF CHAR; VAR host, path: ARRAY OF CHAR; VAR port: LONGINT): BOOLEAN;
VAR i, j : LONGINT;
BEGIN
	port := 80;
	IF LEN(url) < 7 THEN RETURN FALSE END;
	
	IF (url[4] = ":") & (url[5] = "/") & (url[6] = "/") THEN 
		(* get host *)
		i := 7; j := 0;
		WHILE (url[i] # ":") & (url[i] # "/") & (url[i] # 0X) DO 
			IF j < LEN(host) - 1 THEN host[j] := url[i] ELSE RETURN FALSE END;
			 INC(i); INC(j);
			 IF i = LEN(url) THEN RETURN FALSE END
		END;
		host[j] := 0X;
		(* get port *)
		IF url[i] = ":" THEN
			port := 0;
			INC(i);
			WHILE (i < LEN(url)) & (ORD(url[i]) >= ORD("0")) & (ORD(url[i]) <= ORD("9"))  DO 
				port := port * 10 + (ORD(url[i]) - ORD("0"));
				INC(i)	
			END
		END;
		
		j := 0;
		WHILE (i < LEN(url)) & (url[i] # 0X) DO 
			IF j < LEN(host) - 1 THEN path[j] := url[i] ELSE RETURN FALSE END;
			 INC(i); INC(j);
			 IF i = LEN(url) THEN RETURN FALSE END
		END;
		path[j] := 0X;
		RETURN TRUE
	ELSE RETURN FALSE
	END	
END SplitHTTPAdr;

END WebHTTP.

System.Free WebHTTP~