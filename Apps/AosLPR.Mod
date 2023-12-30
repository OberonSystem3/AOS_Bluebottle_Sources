MODULE AosLPR; (* AUTHOR "ejz"; PURPOSE "RFC 1179" *)
	
	IMPORT AosFS, AosIO,  AosTCP, AosDNS, AosIP, AosConfig, Utilities; 

	CONST
		DefConPort = 515;
		BegLocPort = 721;
		EndLocPort = 731;
		LF = 0AX;
		CR = 0DX;
		DefaultEmail = "oberonuser@ethz.ch";

		(*Errors*)
		OK = 0;
		FILENOTFOUND = -1;
		HOSTNOTFOUND = -2; 
		READERNIL = -3;
		SENDCONTROLFILEFAILED = -4;
		RECEIVECONTROLFILEFAILED = -5;
		SENDDATAFILEFAILED= -6;
		RECEIVEDATAFILEFAILED= -7;
		RECEIVEPRINTJOBFAILED= -8;
		NOTCONNECTED=-9;
		
		
	VAR
		jobNr: INTEGER;





	PROCEDURE Print*(host, queue, docName, email: ARRAY OF CHAR; banner, mail: BOOLEAN; data : AosIO.Reader;  size: LONGINT;  VAR res : LONGINT);
		VAR
			dataFile, controlFile: ARRAY 64 OF CHAR;
			nrStr: ARRAY 8 OF CHAR;
			state: CHAR;
			controlfile : Utilities.Buffer;
			controlfileWriter : AosIO.Writer;
			reader: AosIO.Reader; 
			writer: AosIO.Writer;
			fadr: AosIP.Adr;
			locport: INTEGER;
			connres, len : LONGINT;
			conn: AosTCP.Connection; 
			buf : ARRAY 10000 OF CHAR;
	BEGIN
		AosDNS.HostByName(host, fadr, connres);
		IF connres = AosDNS.Ok THEN 
			locport := BegLocPort;
			REPEAT
				NEW(conn); conn.Open(locport, fadr, DefConPort, connres); 
				INC(locport)
			UNTIL (connres = AosTCP.Ok) OR (locport > EndLocPort);
			IF connres = AosTCP.Ok THEN
				IF data # NIL THEN
					AosIO.OpenReader(reader, conn.Receive);
					AosIO.OpenWriter(writer, conn.Send);
					INC(jobNr);
					IF jobNr >= 1000 THEN
						jobNr := 100
					END;
					Utilities.IntToStr(jobNr, nrStr);
					COPY("dfA",dataFile);
					Utilities.Append(dataFile, nrStr);
					Utilities.Append(dataFile, host);
					COPY("cfA", controlFile);
					Utilities.Append(controlFile, nrStr);
					Utilities.Append(controlFile, host);
					
					
					writer.Char(02X); writer.String(queue);writer.Char(LF);(* receive a print job *)
					writer.Update();
					state := 0FFX; state := reader.Get();
					IF (state = 0X) & (reader.res = AosIO.Ok) THEN
					
						Utilities.IntToStr(size + 1, nrStr);				
						writer.Char( 03X); writer.String(nrStr); writer.Char(" "); writer.String(dataFile); writer.Char(LF);(* receive data file *)
						writer.Update();
						state := 0FFX; state := reader.Get();
						IF (state = 0X) & (reader.res = AosIO.Ok) THEN
							WHILE data.res = AosIO.Ok DO
								data.Bytes(buf, 0, LEN(buf), len);
								writer.Bytes(buf, 0, len);
							END;
							writer.Char(LF); writer.Char(0X);
							writer.Update();
							state := 0FFX; state := reader.Get();
							IF (state = 0X)& (reader.res = AosIO.Ok) THEN
					
								NEW(controlfile,100000);
								controlfileWriter := controlfile.GetWriter();
								
								controlfileWriter.Char("H");controlfileWriter.String(host); controlfileWriter.Char(LF);
								
								controlfileWriter.Char("P"); controlfileWriter.String(email); controlfileWriter.Char(LF);(* user identification *)
								
								IF mail THEN (* send mail when job has finished *)
									controlfileWriter.Char("M"); controlfileWriter.String(email); controlfileWriter.Char(LF);(* user identification *) (* user identification *)
								END;
								
								IF docName # 0X THEN 
									controlfileWriter.Char("J");controlfileWriter.String(docName);controlfileWriter.Char(LF);(* job name *)
								END;
								
								IF banner THEN
									controlfileWriter.Char("L"); controlfileWriter.String(email); controlfileWriter.Char(LF);(* banner page *)
								END;
								
								controlfileWriter.Char("l");controlfileWriter.String(dataFile);controlfileWriter.Char(LF);(* print file direct *)
								
								controlfileWriter.Char("U");controlfileWriter.String(dataFile);controlfileWriter.Char(LF);(* unlink data file *)
								
								controlfileWriter.Char("N");controlfileWriter.String(docName);controlfileWriter.Char(LF);(* name of source file *)
						
								
								Utilities.IntToStr(controlfile.GetLength(), nrStr);
								writer.Char( 02X); writer.String(nrStr); writer.Char( " "); writer.String(controlFile);writer.Char( LF);(* receive control file *)
								writer.Update();
								state := 0FFX; state := reader.Get();
								IF (state = 0X) & (reader.res = AosIO.Ok)  THEN
									controlfile.Write(writer); writer.Char(0X);
									writer.Update();
									conn.Close();
									state := 0FFX; state := reader.Get();
									IF (state = 0X)  THEN
										res := OK;
									ELSE
										res := SENDCONTROLFILEFAILED;								
									END							
								ELSE
									res := RECEIVECONTROLFILEFAILED;
								END
							ELSE
								res := SENDDATAFILEFAILED;						
							END
						ELSE
							res :=  RECEIVEDATAFILEFAILED;	
						END
					ELSE
						res := RECEIVEPRINTJOBFAILED										
					END;
				ELSE
					res := READERNIL;
				END;
			ELSE
				res := NOTCONNECTED;
			END;
		ELSE
			res := HOSTNOTFOUND;
		END;						
	END Print;



(** LPRPrinter.ShowJobs queue@host  Display a list of the waiting jobs in the given queue. *)
PROCEDURE ShowJobs*(out: AosIO.Writer; host, queue : ARRAY OF CHAR; VAR res: LONGINT);
		VAR
			job: ARRAY 64 OF CHAR;
			connres, len : LONGINT;
			conn: AosTCP.Connection; 
			reader: AosIO.Reader; 
			writer: AosIO.Writer;
			fadr: AosIP.Adr;
			locport: INTEGER;
	BEGIN
		AosDNS.HostByName(host, fadr, connres);
		IF connres = AosDNS.Ok THEN 
			locport := BegLocPort;
			REPEAT
				NEW(conn); conn.Open(locport, fadr, DefConPort, connres); 
				INC(locport)
			UNTIL (connres = AosTCP.Ok) OR (locport > EndLocPort);
			IF connres = AosTCP.Ok THEN
				AosIO.OpenReader(reader, conn.Receive);
				AosIO.OpenWriter(writer, conn.Send);
				writer.Char(04X); (* 03X short, 04X long *) writer.String(queue);writer.Char(LF);
				writer.Update();
				WHILE reader.res = AosIO.Ok DO
					reader.Ln(job);
					out.String(job); 
				END;
				res := OK;
				conn.Close();			
			ELSE
				res := NOTCONNECTED;
			END;
		ELSE
			res := HOSTNOTFOUND;
		END;
						
	END ShowJobs;

(** LPRPrinter.RemoveJob queue@host [ job-nr ]
		Remove the specified job or all jobs from queue. *)
	PROCEDURE RemoveJob*(host, queue,  email, job: ARRAY OF CHAR; VAR res : LONGINT);
	VAR
		connres, len : LONGINT;
		conn: AosTCP.Connection; 
		reader: AosIO.Reader; 
		writer : AosIO.Writer;
		fadr: AosIP.Adr;
		locport: INTEGER;
	BEGIN
		AosDNS.HostByName(host, fadr, connres);
		IF connres = AosDNS.Ok THEN 
			locport := BegLocPort;
			REPEAT
				NEW(conn); conn.Open(locport, fadr, DefConPort, connres); 
				INC(locport)
			UNTIL (connres = AosTCP.Ok) OR (locport > EndLocPort);
			IF connres = AosTCP.Ok THEN
				AosIO.OpenReader(reader, conn.Receive);
				AosIO.OpenWriter(writer, conn.Send);
				writer.Char(05X);writer.String(queue); writer.Char(" "); writer.String(email); (* remove jobs *)
				IF job # "" THEN
					writer.Char(" ");
					writer.String(job)
				END;
				writer.Char(LF);		
				writer.Update();
				res := OK;
				conn.Close();
			ELSE
				res := NOTCONNECTED;
			END;
		ELSE
			res := HOSTNOTFOUND;
		END;
	END RemoveJob;


	PROCEDURE PrintFile*(fn : ARRAY OF CHAR; VAR res : LONGINT);
	VAR
		file : AosFS.File;
		fileReader : AosFS.Reader;
		host, queue, email: ARRAY 100 OF CHAR;
		banner, mail : BOOLEAN;
	BEGIN
		file := AosFS.Old(fn);
		IF (file # NIL) THEN
			AosConfig.Get("LPR.host", host);			
			AosConfig.Get("LPR.queue", queue);
			AosConfig.Get("LPR.email", email);
			banner := FALSE;
			mail := FALSE;
			AosFS.OpenReader(fileReader, file, 0);
			Print(host, queue, "Oberon Document", email,  banner, mail, fileReader, file.Length(), res);
		ELSE
			res := FILENOTFOUND;
		END;
	END PrintFile;

BEGIN
	jobNr := 99;
END AosLPR.


Usage:

PROCEDURE PrintTest*;
VAR
	res : LONGINT;
BEGIN
	AosOut.String("Printing....");
	AosLPR.PrintFile("test.ps", res);
	AosOut.Int(res, 5); AosOut.Ln;
END PrintTest;

PROCEDURE PrintTest2*();
VAR
	file : AosFS.File;
	fileReader : AosFS.Reader;
	host, queue, email: ARRAY 100 OF CHAR;
	banner, mail : BOOLEAN;
	res : LONGINT;
BEGIN
	file := AosFS.Old("test.ps");
	IF (file # NIL) THEN
		AosFS.OpenReader(fileReader, file, 0);
		COPY("129.132.134.122", host);
		COPY("dummyQueue", queue);
		COPY("daniel.keller@inf.ethz.ch", email);
		banner := FALSE;
		mail := FALSE;
		AosFS.OpenReader(fileReader, file, 0);
		AosOut.String("Printing....");
		AosLPR.Print(host, queue, "Oberon Document", email,  banner, mail, fileReader, file.Length(), res);
		AosOut.Int(res, 5); AosOut.Ln;
	END;
END PrintTest2;

PROCEDURE ShowJobTest*;
VAR
	out : AosIO.Writer;
	host, queue: ARRAY 100 OF CHAR;
	res : LONGINT;
BEGIN
	AosIO.OpenWriter(out, AosOut.Send);
	AosConfig.Get("LPR.host", host);			
	AosConfig.Get("LPR.queue", queue);
	AosLPR.ShowJobs(out, host, queue, res);
	AosOut.Int(res, 5); AosOut.Ln;
END ShowJobTest;

