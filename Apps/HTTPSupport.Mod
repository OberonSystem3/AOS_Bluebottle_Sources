MODULE HTTPSupport; (** AUTHOR "Luc Blaeser/cs"; PURPOSE "HTTP Webserver Support Module for HTTP-Request Handling"; 
 contains also code parts from "CSHTTPSupport" by "cs" *)

IMPORT WebHTTP, AosIO, Utilities, TFClasses, AosOut;

TYPE
	HTTPVariable* = POINTER TO RECORD
		name*: ARRAY 1024 OF CHAR;
		value*: ARRAY 1024 OF CHAR;
		isUrlEncoded*: BOOLEAN (** true iff url encoded if the HTTP request *)
	END;
	
	(** encapsulates the HTTP request header and the variables from POST ord GET *)
	HTTPRequest* = OBJECT
		VAR 
			header*: WebHTTP.RequestHeader;
			shortUri*: ARRAY 4096 OF CHAR; (** uri without variables *)
			
			variables*: TFClasses.List; (** List of HTTPVariable *)
			
		PROCEDURE &Init(requestHeader: WebHTTP.RequestHeader; bodyReader: AosIO.Reader);
			VAR pos: LONGINT; restLength: LONGINT; uriReader : AosIO.StringReader; uriRest : Utilities.String;
				contentType: ARRAY 40 OF CHAR;
		BEGIN
			NEW(variables);
			header := requestHeader; 
			(* look for variables inURL *)
			pos := Utilities.Pos("?", header.uri);
			IF (pos > 0) THEN
				Utilities.Copy(header.uri, 0, pos, shortUri);
				
				restLength := Utilities.Length(header.uri)-pos;
				NEW(uriRest, restLength);
				Utilities.Copy(header.uri, pos+1, restLength, uriRest^);
				NEW(uriReader, restLength); uriReader.Set(uriRest^);
				ParseVariables(uriReader, TRUE)
			ELSE
				COPY(header.uri, shortUri)
			END;
			(* look for variables in body *)
			IF (requestHeader.method = WebHTTP.PostM) THEN
				IF (WebHTTP.GetAdditionalFieldValue(requestHeader.additionalFields, "Content-Type", contentType)) THEN
					IF (contentType = "application/x-www-form-urlencoded") & (bodyReader # NIL)THEN
						(* look for variables in body *)
						ParseVariables(bodyReader, FALSE)
					END
				END
			END
		END Init;
					
		PROCEDURE ParseVariables(r: AosIO.Reader; isUrlEncoded : BOOLEAN);
			VAR var: HTTPVariable; ch: CHAR; pos, i, size: LONGINT; close: BOOLEAN; s: ARRAY 32 OF CHAR;
				enc: BOOLEAN; (* true iff encoded *)
			
			PROCEDURE Next;
					VAR c0, c1: CHAR; val : LONGINT; 
			BEGIN
				ch := r.Get(); INC(pos); enc := FALSE;
				IF ch = "%" THEN (* next byte is encoded *)
					IF (HasMoreData()) THEN c0 := r.Get(); INC(pos) ELSE c0 := 0X END; 
					IF (HasMoreData()) THEN c1 := r.Get(); INC(pos) ELSE c1 := 0X END; 
					(* first nibble *) 
					val := 0; IF (c0 >='0') & (c0 <='9') THEN val := (ORD(c0) - ORD('0')) * 16 END;
					IF (CAP(c0) >='A') & (CAP(c0) <='F') THEN val := (ORD(CAP(c0)) - ORD('A') + 10) * 16 END;
					(* second nibble *)
					IF (c1 >='0') & (c1 <='9') THEN val := val + ORD(c1) - ORD('0') END;
					IF (CAP(c1) >='A') & (CAP(c1) <='F') THEN val := val + ORD(CAP(c1)) - ORD('A')+10 END;
					ch := CHR(val); enc := TRUE
				ELSIF ch = '+' THEN ch := ' '
				END
			END Next;
			
			PROCEDURE HasMoreData() : BOOLEAN;
			BEGIN
				RETURN ((r.Available() > 0) & close) OR (~close & (pos < size))
			END HasMoreData;

		BEGIN
			pos := 0;
			IF (~isUrlEncoded & WebHTTP.HasAdditionalField(header.additionalFields, "Content-Length")
				& WebHTTP.GetAdditionalFieldValue(header.additionalFields, "Content-Length", s))THEN
				Utilities.StrToInt(s, size); close := FALSE
			ELSE
				close := TRUE
			END;
			WHILE (HasMoreData()) DO
				NEW(var); var.isUrlEncoded := isUrlEncoded;
				i := 0; Next;
				WHILE ((HasMoreData()) & (enc OR (ch # "=")) & (i < LEN(var.name)-1)) DO
					var.name[i] := ch; INC(i); Next
				END;
				IF (i >= LEN(var.name)-1) THEN
					AosOut.String("Variable name too long in HTTP request."); AosOut.Ln;
					WHILE ((HasMoreData()) & (enc OR (ch # "="))) DO Next END
				ELSIF (ch # "=") THEN 
					var.name[i] := ch; INC(i)
				END;
				var.name[i] := 0X; (* Utilities.LowerCase(var.name); What the hell... why case in-sensitive *)
				i := 0; 
				IF (HasMoreData()) THEN Next END;
				WHILE ((HasMoreData()) & (enc OR (ch # "&")) & (i < LEN(var.value)-1)) DO
					var.value[i] := ch; INC(i); Next
				END; 
				IF (i >= LEN(var.value)-1) THEN
					AosOut.String("Variable value too long in HTTP request."); AosOut.Ln;
					WHILE ((HasMoreData()) & (enc OR (ch # "&"))) DO Next END
				ELSIF (ch # "&") THEN
					var.value[i] := ch; INC(i)
				END;
				var.value[i] := 0X;
				variables.Add(var)
			END
		END ParseVariables;
		
		(** returns NIL if variable is not present *)
		PROCEDURE GetVariableByName*(name: ARRAY OF CHAR) : HTTPVariable;
		VAR p: PTR; var: HTTPVariable; i: LONGINT;
		BEGIN
			variables.Lock;
			FOR i := 0 TO variables.GetCount()-1 DO
				p := variables.GetItem(i); var := p(HTTPVariable); (* var # NIL *)
				IF (var.name = name) THEN
					variables.Unlock;
					RETURN var
				END
			END;
			variables.Unlock;
			RETURN NIL
		END GetVariableByName;
		
		PROCEDURE WriteEncodedUri*(encUri: ARRAY OF CHAR);
		VAR encStr: ARRAY 1024 OF CHAR; p: PTR; var: HTTPVariable; i : LONGINT;
		BEGIN
			COPY(shortUri, encUri);
			variables.Lock;
			FOR i := 0 TO variables.GetCount()-1 DO
				p := variables.GetItem(i); var := p(HTTPVariable); (* var # NIL *)
				IF (i = 0) THEN
					Utilities.Append(encUri, "?")
				ELSE
					Utilities.Append(encUri, "&")
				END;
				HTTPEncode(var.name, encStr);
				Utilities.Append(encUri, encStr);
				Utilities.Append(encUri, "=");
				HTTPEncode(var.value, encStr);
				Utilities.Append(encUri, encStr)
			END;
			variables.Unlock
		END WriteEncodedUri;

		
	END HTTPRequest;
	
	PROCEDURE RemoveVariablesFromURI*(olduri: ARRAY OF CHAR; VAR newuri: ARRAY OF CHAR);
	VAR pos: LONGINT;
	BEGIN
		pos := Utilities.Pos("?", olduri);
		IF (pos > 0) THEN
			Utilities.Copy(olduri, 0, pos, newuri)
		ELSE
			COPY(olduri, newuri)
		END
	END RemoveVariablesFromURI;
	
	(** HTTPEncode in by escaping illegal chars , author: "cs" *)
	PROCEDURE HTTPEncode*(in: ARRAY OF CHAR; VAR enc: ARRAY OF CHAR);
	VAR i,o: LONGINT;
		ch: LONGINT;
		
		PROCEDURE ToHex(in: CHAR;VAR c1: CHAR; VAR c2: CHAR);
			VAR i: INTEGER;
		BEGIN
			i := ORD(in) DIV 16;
			IF i < 10 THEN
				c1 := CHR(30H + i)
			ELSE
				c1 := CHR(37H + i)
			END;
			i := ORD(in) MOD 16;
			IF i < 10 THEN
				c2 := CHR(30H + i)
			ELSE
				c2 := CHR(37H + i)
			END
		END ToHex;
		
		BEGIN
			o := 0;
			FOR i:= 0 TO Utilities.Length(in)-1 DO
				ch := ORD(in[i]);
				(* RFC2396 lowalpha *)
				IF (ch >= 61H ) & (ch <= 7AH) OR
					(* RFC2396 upalpha *)
					(ch >= 41H) & (ch <= 5AH) OR
					(* RFC2396 digit *)
					(ch >= 30H) & (ch <= 39H) OR
					(ch = 2DH) OR (* - *)
					(ch = 5FH) OR (* underscore *)
					(ch = 2EH) OR (* . *)
					(ch = 21H) OR (* ! *)
					(ch = 7EH) OR (* ~ *)
					(ch = 2AH) OR (* * *)
					(ch = 27H) OR (* ' *)
					(ch = 28H) OR (* ( *)
					(ch = 29H) (* ) *)
				THEN 
					enc[o]:= CHR(ch); (* transparent *)
					INC(o)
				ELSE (* encode hex *)
					enc[o] := 25X; (* % *)
					ToHex(CHR(ch),enc[o+1],enc[o+2]);
					INC(o,3)
				END
			END;
		enc[o] := 0X
	END HTTPEncode;


END HTTPSupport.

System.Free HTTPSupport ~
