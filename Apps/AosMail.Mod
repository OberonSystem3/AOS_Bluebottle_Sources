MODULE AosMail;
(** AUTHOR "TF"; PURPOSE "Mail data structures"; *)

IMPORT Classes := TFClasses;

TYPE 
	MailAddress* = ARRAY 128 OF CHAR;

	Recipient* = OBJECT
		VAR name-, address- : MailAddress;
	END Recipient;
	
	Line *= OBJECT
	VAR data* : POINTER TO ARRAY OF CHAR;
	END Line;
	
	Message* = OBJECT
	VAR
		subject : ARRAY 128 OF CHAR;
		date : ARRAY 64 OF CHAR;
		from, sender : Recipient;
		toList, ccList, bccList, lines, replyToList : Classes.List;
		
		PROCEDURE &Init;
		BEGIN
			NEW(from); NEW(sender); NEW(toList); NEW(ccList); NEW(bccList); NEW(replyToList); NEW(lines)
		END Init;
		
		PROCEDURE SetFrom*(name, address : ARRAY OF CHAR);
		BEGIN COPY(name, from.name);  COPY(address, from.address) 
		END SetFrom;
		
		PROCEDURE GetFrom*(VAR name, address: ARRAY OF CHAR);
		BEGIN COPY(from.name, name);  COPY(from.address, address) 
		END GetFrom;
	
		PROCEDURE SetSender*(name, address : ARRAY OF CHAR);
		BEGIN COPY(name, sender.name);  COPY(address, sender.address) 
		END SetSender;
		
		PROCEDURE GetSender*(VAR name, address: ARRAY OF CHAR);
		BEGIN COPY(sender.name, name);  COPY(sender.address, address) 
		END GetSender;
		
		PROCEDURE SetSubject*(subject: ARRAY OF CHAR);
		BEGIN COPY(subject, SELF.subject) 
		END SetSubject;
		
		PROCEDURE GetSubject*(VAR subject: ARRAY OF CHAR);
		BEGIN COPY(SELF.subject, subject) 
		END GetSubject;
		
		PROCEDURE SetDate*(date: ARRAY OF CHAR);
		BEGIN COPY(date, SELF.date) 
		END SetDate;
		
		PROCEDURE GetDate*(VAR date: ARRAY OF CHAR);
		BEGIN COPY(SELF.date, date) 
		END GetDate;
		
		PROCEDURE AddTo*(name, address:ARRAY OF CHAR);
		VAR new : Recipient;
		BEGIN NEW(new); COPY(name, new.name); COPY(address, new.address); toList.Add(new)
		END AddTo;
		
		PROCEDURE GetNofTo*():LONGINT;
		BEGIN RETURN toList.GetCount()
		END GetNofTo;
		
		PROCEDURE GetTo*(nr : LONGINT; VAR name, address: ARRAY OF CHAR);
		VAR old : Recipient; p : PTR;
		BEGIN 
			ASSERT((nr >= 0) & (nr < toList.GetCount()));
			p := toList.GetItem(nr); old := p(Recipient);
			COPY(old.name, name); COPY(old.address, address)
		END GetTo;
		
		PROCEDURE AddReplyTo*(name, address:ARRAY OF CHAR);
		VAR new : Recipient;
		BEGIN NEW(new); COPY(name, new.name); COPY(address, new.address); replyToList.Add(new)
		END AddReplyTo;
		
		PROCEDURE GetNofReplyTo*():LONGINT;
		BEGIN RETURN replyToList.GetCount()
		END GetNofReplyTo;
		
		PROCEDURE GetReplyTo*(nr : LONGINT; VAR name, address: ARRAY OF CHAR);
		VAR old : Recipient; p : PTR;
		BEGIN 
			ASSERT((nr >= 0) & (nr < replyToList.GetCount()));
			p := replyToList.GetItem(nr); old := p(Recipient);
			COPY(old.name, name); COPY(old.address, address)
		END GetReplyTo;
		
		PROCEDURE AddCc*(name, address:ARRAY OF CHAR);
		VAR new : Recipient;
		BEGIN NEW(new); COPY(name, new.name); COPY(address, new.address); ccList.Add(new)
		END AddCc;
		
		PROCEDURE GetNofCc*():LONGINT;
		BEGIN RETURN ccList.GetCount()
		END GetNofCc;
		
		PROCEDURE GetCc*(nr : LONGINT; VAR name, address:ARRAY OF CHAR);
		VAR old : Recipient; p : PTR;
		BEGIN 			
			ASSERT((nr >= 0) & (nr < ccList.GetCount()));
			p := ccList.GetItem(nr); old := p(Recipient);
			COPY(old.name, name); COPY(old.address, address)
		END GetCc;
		
		PROCEDURE AddBcc*(name, address:ARRAY OF CHAR);
		VAR new : Recipient;
		BEGIN NEW(new); COPY(name, new.name); COPY(address, new.address); bccList.Add(new)
		END AddBcc;
		
		PROCEDURE GetNofBcc*():LONGINT;
		BEGIN RETURN bccList.GetCount()
		END GetNofBcc;
		
		PROCEDURE GetBcc*(nr : LONGINT; VAR name, address:ARRAY OF CHAR);
		VAR old : Recipient; p : PTR;
		BEGIN 			
			ASSERT((nr >= 0) & (nr < bccList.GetCount()));
			p := bccList.GetItem(nr); old := p(Recipient);
			COPY(old.name, name); COPY(old.address, address)
		END GetBcc;
		
		PROCEDURE AddLine*(x: ARRAY OF CHAR);
		VAR l, i : LONGINT; nl : Line;
		BEGIN {EXCLUSIVE}
			l := 0;
			IF LEN(x) > 0 THEN 
				WHILE (l < LEN(x)) & (x[l] # 0X) DO INC(l) END;
				IF x[0] = "." THEN INC(l) END;
			END;
			NEW(nl); 
			IF l > 0 THEN 
				NEW(nl.data, l + 1);
				IF x[0] = "." THEN 
					nl.data[0] := "."; INC(i);
					FOR i := 1 TO l DO nl.data[i] := x[i - 1] END;
				ELSE
					COPY(x, nl.data^)	
				END;
			END;
			lines.Add(nl)
		 END AddLine;
		 
		 PROCEDURE GetNofLines*():LONGINT;
		 BEGIN RETURN lines.GetCount()
		 END GetNofLines;
		 
		 PROCEDURE GetLine*(nr : LONGINT; VAR l : Line);
		 VAR p: PTR; 
		 BEGIN
			ASSERT((nr >= 0) & (nr < lines.GetCount()));
			p := lines.GetItem(nr); l := p(Line)
		 END GetLine;
	
	END Message;
	
TYPE 
	Sender* = OBJECT
		PROCEDURE Send*(m : Message; VAR result : LONGINT);
		BEGIN END Send;
	END Sender;
		
TYPE		
	Receiver = OBJECT
		PROCEDURE GetNofMessages() : LONGINT;
		BEGIN
		END GetNofMessages;
	END Receiver;

END AosMail.
 