MODULE AosQuoteServer; (** AUTHOR "be"; PURPOSE "Quote of the day server"; *)

(* Quote of the Day (RFC 865) TCP service for Aos. *)

IMPORT AosModules, AosKernel, AosOut, AosTCP, AosTCPServices, AosIO, AosFS;

CONST
	QuotePort = 17;
	
	Ok = AosTCP.Ok;
	CR = 0DX;
	LF = 0AX;
	
	QuoteFile = "AosQuotes.txt";	
	MaxQuoteLen = 511;
	
	Trace = TRUE;

TYPE
	QuoteAgent = OBJECT (AosTCPServices.Agent)
		VAR q: Quote; w: AosIO.Writer;
	
	BEGIN {ACTIVE}
		AosKernel.AtomicInc(Nrequests);
		q := NextQuote();
		ASSERT(q # NIL);
		AosIO.OpenWriter(w, client.Send);
		w.String(q.msg); w.Update;
		Terminate
	END QuoteAgent;

	Quote = POINTER TO RECORD
		msg: ARRAY MaxQuoteLen OF CHAR;
		len: LONGINT;
		next: Quote;
	END;
		
VAR
	quoteService: AosTCPServices.Service;	
	quotes: Quote;
	NnofQuotes-, Nrequests-: LONGINT;

PROCEDURE Open*(par: PTR): PTR;
BEGIN RETURN NIL
END Open;

PROCEDURE Initialize;
BEGIN
	AosOut.String("AosQuoteServer:"); AosOut.Ln;
	ReadQuotes;
	IF (NnofQuotes > 0) THEN
		AosTCPServices.OpenService(quoteService, QuotePort, NewQuoteAgent);
		IF (quoteService # NIL) THEN
			Nrequests := 0;
			AosOut.String(" service installed.")
		ELSE
			AosOut.String(" port not available. System.Free AosQuoteServer ~ and try again.")
		END
	ELSE AosOut.String(" no quotes available, service not installed.")
	END;
	AosOut.Ln
END Initialize;

PROCEDURE Finalize;
BEGIN 
	AosTCPServices.CloseService(quoteService)
END Finalize;

PROCEDURE Close*(par: PTR): PTR;
BEGIN
	Finalize;
	RETURN NIL
END Close;

PROCEDURE NewQuoteAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
VAR q: QuoteAgent;
BEGIN
	NEW(q, c, s); RETURN q
END NewQuoteAgent;

PROCEDURE ReadQuotes*;
VAR 
	f: AosFS.File; r: AosFS.Reader; str: ARRAY MaxQuoteLen OF CHAR;
	q: Quote; pos: LONGINT;

	PROCEDURE Skip;
	BEGIN
		WHILE (str[0] = "#") & (r.res = Ok) DO r.Ln(str) END
	END Skip;
	
	PROCEDURE Append;
	VAR i: LONGINT;
	BEGIN
		WHILE (pos < MaxQuoteLen-2) & (str[i] # 0X) DO q.msg[pos] := str[i]; INC(pos); INC(i) END;
		q.msg[pos] := CR; INC(pos);
		q.msg[pos] := LF; INC(pos)
	END Append;
	
BEGIN {EXCLUSIVE}
	AosOut.String(" reading quotes...");
	f := AosFS.Old(QuoteFile);
	quotes := NIL; NnofQuotes := 0;
	IF (f # NIL) THEN
		AosFS.OpenReader(r, f, 0);
		r.Ln(str);
		Skip;
		WHILE (r.res = Ok) DO
			INC(NnofQuotes);
			NEW(q); q.next := quotes; quotes := q;
			q.msg := ""; pos := 0;
			REPEAT
				Append;
				r.Ln(str)
			UNTIL (str[0] = "#") OR (r.res # Ok);
			Skip
		END;
		IF (quotes # NIL) THEN (* form a ring *)
			q := quotes;
			WHILE (q.next # NIL) DO q := q.next END;
			q.next := quotes
		END;
		AosOut.Int(NnofQuotes, 0); AosOut.String(" quotes read.")
	ELSE 
		AosOut.String("file not found ("); AosOut.String(QuoteFile); AosOut.Char(")")
	END;
	AosOut.Ln
END ReadQuotes;

PROCEDURE NextQuote(): Quote;
BEGIN {EXCLUSIVE}
	quotes := quotes.next;
	RETURN quotes
END NextQuote;

BEGIN
	Initialize;
	AosModules.InstallTermHandler(Finalize)
END AosQuoteServer.


AosQuoteServer.Open
S.Free AosQuoteServer ~

PET.Open AosQuotes.txt ~