MODULE AosQuoteServer; (** AUTHOR "be"; PURPOSE "Quote of the day server"; *)
(**
 * Quote of the Day (RFC 865) TCP service for Aos. 
 *
 * History:
 *
 *	28.02.2007	Don't start quote server when loading module, name of quote file as parameter (staubesv)
 *)

IMPORT AosModules, AosKernel, AosOut, AosCommands, AosTCP, AosTCPServices, AosIO, AosFS;

CONST
	QuotePort = 17;
	
	Ok = AosTCP.Ok;
	CR = 0DX;
	LF = 0AX;
	
	DefaultQuoteFile = "AosQuotes.txt";	
	MaxQuoteLen = 511;
	
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

PROCEDURE NewQuoteAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
VAR q: QuoteAgent;
BEGIN
	NEW(q, c, s); RETURN q
END NewQuoteAgent;

PROCEDURE NextQuote(): Quote;
BEGIN {EXCLUSIVE}
	quotes := quotes.next;
	RETURN quotes
END NextQuote;

PROCEDURE ReadQuotesX(filename : ARRAY OF CHAR);
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
	
BEGIN
	AosOut.String("AosQuoteServer: Reading quotes from file "); AosOut.String(filename); AosOut.String("... ");
	f := AosFS.Old(filename);
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
		AosOut.String("file not found ("); AosOut.String(filename); AosOut.Char(")")
	END;
	AosOut.Ln;
END ReadQuotesX;

PROCEDURE StartService;
VAR res : LONGINT;
BEGIN
	IF (NnofQuotes > 0) THEN
		NEW(quoteService, QuotePort, NewQuoteAgent, res);
		IF (quoteService # NIL) THEN
			Nrequests := 0;
			AosOut.String("AosQuoteServer: Service installed.")
		ELSE
			AosOut.String("AosQuoteServer: Port not available. System.Free AosQuoteServer ~ and try again.")
		END
	ELSE AosOut.String("AosQuoteServer: No quotes available, service not installed.")
	END;
	AosOut.Ln
END StartService;

PROCEDURE ReadQuotes*(par : ANY) : ANY; (** filename ~ *)
VAR r : AosIO.StringReader; filename : ARRAY 256 OF CHAR;
BEGIN {EXCLUSIVE}
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(filename);
	IF (r.res = AosIO.Ok) & (filename # "") THEN
		ReadQuotesX(filename);
	ELSE
		AosOut.String("AosQuoteServer: Expected filename parameter."); AosOut.Ln;
	END;
	RETURN NIL
END ReadQuotes;

PROCEDURE Open*(par: PTR): PTR; (** [filename] ~ *)
VAR r : AosIO.StringReader; filename : ARRAY 256 OF CHAR;
BEGIN {EXCLUSIVE}
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(filename);
	IF (r.res # AosIO.Ok) OR (filename = "") THEN filename := DefaultQuoteFile; END;
	IF quoteService = NIL THEN
		IF quotes = NIL THEN
			ReadQuotesX(filename);
		END;
		StartService;
	ELSE
		AosOut.String("AosQuoteServer: Server already running."); AosOut.Ln;
	END;
	RETURN NIL
END Open;

PROCEDURE Close*(par: PTR): PTR; (** ~ *)
BEGIN
	Cleanup;
	RETURN NIL
END Close;

PROCEDURE Cleanup;
BEGIN  {EXCLUSIVE}
	IF quoteService # NIL THEN
		quoteService.Stop; quoteService := NIL;
	END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup)
END AosQuoteServer.

AosQuoteServer.Open ~ 	S.Free AosQuoteServer ~ 	PET.Open AosQuotes.txt ~
AosQuoteServer.Open AosQuotes.txt ~
AosQuoteServer.ReadQuotes AosQuotes.txt ~