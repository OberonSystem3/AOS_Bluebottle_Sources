MODULE RMSMTP; (** AUTHOR "retmeier"; PURPOSE "A SMTP client"; *)

IMPORT
	AosSMTPClient, AosCommands, AosOut, Utilities, AosIO, Classes := TFClasses, IMAPClient, IMAPUtilities;
	
CONST
	DEBUG = TRUE;
	CR = 0DX; LF = 0AX;
	PORT = 25;
	
	OK* = 0;
	CONNECTIONERROR* = 1;
	FROMERROR* = 2;
	TOERROR* = 3;
	CCERROR* = 4;
	BCCERROR* = 5;
	DATAERROR* = 6;
	FINISHERROR* = 7;
	
TYPE
	String* = Utilities.String;
	

PROCEDURE Send*(par: ANY):ANY;
VAR
	message: IMAPClient.Message;
	params: AosCommands.Parameters;
	server, thisHost: ARRAY 1024 OF CHAR;
	len: LONGINT;
	reader: AosIO.StringReader;
	ret: LONGINT;
BEGIN
	(* parse the message from the input string *)
	params := par(AosCommands.Parameters);
	len := Utilities.Length(params.str^);
	NEW(reader, len);
	reader.Set(params.str^);
	reader.Token(server);
	reader.SkipWhitespace();
	reader.Token(thisHost);

	NEW(message);
	parse(reader, message);
	
	message.header.date := IMAPUtilities.getRFC822Date();
	ret := SendMessage(message, server, thisHost);

	RETURN NIL;
	
END Send;

PROCEDURE SendMessage*(message: IMAPClient.Message; server, thisHost: ARRAY OF CHAR): LONGINT;
VAR
	smtp: AosSMTPClient.SMTPSession;
	i, res: LONGINT;
	returnValue: LONGINT;
	w: AosIO.Writer;
	p: PTR;
	s: String;
	address: IMAPUtilities.Address;
BEGIN
	(* start communication with server *)
	NEW(smtp);
	smtp.Open(server, thisHost, PORT, res);
	IF res # AosSMTPClient.Ok THEN
		AosOut.String("Failure: it wasn't possible to connect to server: ");	AosOut.String(server); AosOut.Ln();
		RETURN CONNECTIONERROR;
	END;
	
	(* send MAIL FROM command *)
	IF (message.header.from # NIL) & (message.header.from.GetCount() > 0) THEN
		p := message.header.from.GetItem(0);
		address := p(IMAPUtilities.Address);
		AddressToSMTPString(address, s);
	ELSE
		NEW(s, Utilities.Length(thisHost)+1);
		Utilities.Copy(thisHost, 0, Utilities.Length(thisHost), s^);
	END;
	
	IF DEBUG THEN
		AosOut.String("MAIL FROM: "); AosOut.String(s^); AosOut.Ln();
	END;
	
	IF ~smtp.StartMailFrom(s^) THEN
		AosOut.String("Error occured while trying to send the Command: MAIL FROM. Maybe no from header-field was specified or it was errorous"); AosOut.Ln();
		smtp.Close();
		RETURN FROMERROR;
	END;
	
	(* send RCPT TO Commands *)
	IF message.header.to # NIL THEN
		i := 0;
		WHILE i < message.header.to.GetCount() DO
			p := message.header.to.GetItem(i);
			address := p(IMAPUtilities.Address);
			AddressToSMTPString(address, s);
			IF DEBUG THEN
				AosOut.String("RCPT: "); AosOut.String(s^); AosOut.Ln();
			END;
			
			IF ~smtp.SendTo(s^) THEN
				AosOut.String("Error occured while trying to send the Command: RCPT TO for the receivers specified in To"); AosOut.Ln();
				smtp.Close();
				RETURN TOERROR;
			END;
			INC(i);
		END;
	END;
	IF message.header.cc # NIL THEN
		i := 0;
		WHILE i < message.header.cc.GetCount() DO
			p := message.header.cc.GetItem(i);
			address := p(IMAPUtilities.Address);
			AddressToSMTPString(address, s);
			
			IF ~smtp.SendTo(s^) THEN
				AosOut.String("Error occured while trying to send the Command: RCPT TO for the receivers specified in Cc"); AosOut.Ln();
				smtp.Close();
				RETURN CCERROR;
			END;
			INC(i);
		END;
	END;
	IF message.header.bcc # NIL THEN
		i := 0;
		WHILE i < message.header.bcc.GetCount() DO
			p := message.header.bcc.GetItem(i);
			address := p(IMAPUtilities.Address);
			AddressToSMTPString(address, s);
			
			IF ~smtp.SendTo(s^) THEN
				AosOut.String("Error occured while trying to send the Command: RCPT TO for the receivers specified in Bcc"); AosOut.Ln();
				smtp.Close();
				RETURN BCCERROR;
			END;
			INC(i);
		END;
	END;
	
	(* start sending the message data *)
	IF ~smtp.StartData() THEN
		AosOut.String("Error occured while trying to send the Command: DATA"); AosOut.Ln();
		smtp.Close();
		RETURN DATAERROR;
	END;
	
	s := message.ToString();
	
	w := smtp.w;
	w.String(s^);
	w.Ln(); w.String("."); w.Ln();
	
	IF smtp.FinishSendRaw() THEN
		IF DEBUG THEN
			AosOut.String("send was sucessful"); AosOut.Ln();
		END;
		returnValue := OK;
	ELSE
		AosOut.String("send failed"); AosOut.Ln();
		returnValue := FINISHERROR;
	END;
	
	smtp.Close();
	
	RETURN returnValue;
END SendMessage;

PROCEDURE parse*(VAR reader: AosIO.StringReader; VAR message: IMAPClient.Message);
VAR
	token: ARRAY 128 OF CHAR;
	buffer: Utilities.Buffer;
	string: String;
	w: AosIO.Writer;
	c: CHAR;
	headerDone : BOOLEAN;
	pos: LONGINT;
	addresses: Classes.List;
	header: IMAPClient.HeaderElement;
BEGIN
	(* process header of the message *)
	NEW(header);
	
	reader.SkipWhitespace();
	headerDone := FALSE;
	WHILE ~headerDone DO
		pos := reader.Pos();
		reader.Token(token);
		
		Utilities.UpperCase(token);
		
		IF token = "TO:" THEN
			reader.SkipSpaces();
			string := readRestOfLine(reader);
			IMAPUtilities.ParseAddresses(string, addresses);
			header.to := addresses;		
		ELSIF token = "CC:" THEN
			reader.SkipSpaces();
			string := readRestOfLine(reader);
			IMAPUtilities.ParseAddresses(string, addresses);
			header.cc := addresses;		
		ELSIF token = "BCC:" THEN
			reader.SkipSpaces();
			string := readRestOfLine(reader);
			IMAPUtilities.ParseAddresses(string, addresses);
			header.bcc := addresses;
		ELSIF token = "FROM:" THEN
			reader.SkipSpaces();
			string := readRestOfLine(reader);
			IMAPUtilities.ParseAddresses(string, addresses);
			header.from := addresses;
		ELSIF token = "SENDER:" THEN
			reader.SkipSpaces();
			string := readRestOfLine(reader);
			IMAPUtilities.ParseAddresses(string, addresses);
			header.sender := addresses;
		ELSIF token = "SUBJECT:" THEN
			reader.SkipSpaces();
			string := readRestOfLine(reader);
			header.subject := string;
		ELSIF token = "DATE:" THEN
			reader.SkipSpaces();
			string := readRestOfLine(reader);
			header.date := string;
		ELSE
			headerDone := TRUE;
		END;
		
	END;
	message.header := header;
	
	(* process message Body *)
	reader.SetPos(pos);
	
	NEW(buffer, 16);
	w := buffer.GetWriter();
	
	reader.Char(c);
	WHILE c # 0X DO
		w.Char(c);
		reader.Char(c);
	END;
	
	string := buffer.GetString();
	
	message.message := string;
END parse;

PROCEDURE readRestOfLine*(reader: AosIO.StringReader): String;
VAR
	string: String;
	buffer: Utilities.Buffer;
	w: AosIO.Writer;
	c: CHAR;
BEGIN
	NEW(buffer, 16);
	w := buffer.GetWriter();
	reader.Char(c);
	WHILE(c # 0X) & (c # LF) & (c # CR) DO
		w.Char(c);
		reader.Char(c);
	END;
	IF c = CR THEN
		c := reader.Peek();
		IF c = LF THEN
			c := reader.Get();
		END;
	END;
	string := buffer.GetString();
	RETURN string;
END readRestOfLine;

PROCEDURE AddressToSMTPString(address: IMAPUtilities.Address; VAR string: String);
VAR buffer: Utilities.Buffer; w: AosIO.Writer;
BEGIN
	NEW(buffer, 16);
	w := buffer.GetWriter();
	IF DEBUG THEN
		AosOut.String("In AddressToSMPTString namePart: "); AosOut.String(address.namePart^); 
		AosOut.String(" domainPart: "); AosOut.String(address.domainPart^); AosOut.Ln();
	END;
	w.String(address.namePart^);
	w.String("@");
	w.String(address.domainPart^);

	string := buffer.GetString();
END AddressToSMTPString;

END RMSMTP.
