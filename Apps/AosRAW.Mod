MODULE AosRAW; (** AUTHOR "dk"; PURPOSE "Printing Raw to Port 9100"; *)	
	IMPORT AosFS, AosIO,  AosIP, AosTCP, AosDNS; 

	CONST
		DefConPort = 9100;
		
		(*Errors*)
		FILENOTFOUND = -1;
		HOSTNOTFOUND = -2; 
		READERNIL = -3;
		OK = 0;
		

	PROCEDURE PrintFile*(printer : ARRAY OF CHAR; fn:  ARRAY OF CHAR; VAR res : LONGINT);
	VAR
		fileReader : AosFS.Reader;
		file : AosFS.File;
	BEGIN
		file := AosFS.Old(fn);
		IF (file # NIL) THEN
		   AosFS.OpenReader(fileReader, file, 0);
		   PrintStream(printer, fileReader, res);
		ELSE
			res := FILENOTFOUND;
		END;
	END PrintFile;


	PROCEDURE PrintStream*(printer : ARRAY OF CHAR; reader : AosIO.Reader; VAR res : LONGINT);
		VAR
			writer: AosIO.Writer;
			buf : ARRAY 10000 OF CHAR;
			conn : AosTCP.Connection;
			fadr: AosIP.Adr;
			connres, len : LONGINT;						
	BEGIN
		 AosDNS.HostByName(printer, fadr, connres);
		IF res = AosDNS.Ok THEN 
			NEW(conn); conn.Open(AosTCP.NilPort, fadr, DefConPort, connres); 
			AosIO.OpenWriter(writer, conn.Send);
			IF connres = AosTCP.Ok THEN
				IF reader # NIL THEN
					WHILE reader.res = AosIO.Ok DO
						reader.Bytes(buf, 0, LEN(buf), len);
						writer.Bytes(buf, 0, len);
					END;
					writer.Update();
					conn.Close();
					res := OK;
				ELSE
					res := READERNIL;
				END;
			ELSE
				res := HOSTNOTFOUND;
			END;
		END;		
		
	END PrintStream;



END AosRAW.


Usage:


PROCEDURE PrintTest1*();
VAR
	res : LONGINT;
BEGIN
	AosRAW.PrintFile("129.132.134.122", "test.ps", res);
	AosOut.String("Printing res : "); AosOut.Int(res, 5); AosOut.Ln;
END PrintTest1;


PROCEDURE PrintTest2*();
VAR
	file : AosFS.File;
	res : LONGINT;
	reader : AosFS.Reader;
BEGIN
	file := AosFS.Old("test.ps");
	AosFS.OpenReader(reader, file, 0);
	AosRAW.PrintStream("129.132.134.122", reader,res);
	AosOut.String("Printing res : "); AosOut.Int(res, 5); AosOut.Ln;
END PrintTest2;
