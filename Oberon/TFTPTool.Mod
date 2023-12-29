MODULE TFTPTool;	(** be  **)

IMPORT In, Out, AosIP, TFTP;

PROCEDURE Send*;
VAR fnl, fnr: ARRAY 128 OF CHAR; fipstr: ARRAY 64 OF CHAR; fip: AosIP.Adr;
BEGIN
	In.Open; In.String(fnl); In.String(fnr); In.String(fipstr);
	IF In.Done THEN
		fip := AosIP.StrToAdr(fipstr);
		IF (fip # AosIP.NilAdr) THEN
			Out.String("Sending '"); Out.String(fnl); Out.String("' to "); Out.String(fipstr); Out.String("...");
			IF TFTP.Send(fnl, fnr, fip) THEN Out.String(" success.")
			ELSE Out.String("error; check kernel log.")
			END
		ELSE Out.String("Invalid IP")
		END
	ELSE Out.String('Invalid parameters. Syntax: TestTFTP.Send "<localfilename>" "<remotefilename>" "<ip>"')
	END;
	Out.Ln
END Send;

PROCEDURE Receive*;
VAR fnl, fnr: ARRAY 128 OF CHAR; fipstr: ARRAY 64 OF CHAR; fip: AosIP.Adr;
BEGIN
	In.Open; In.String(fnr); In.String(fnl); In.String(fipstr);
	IF In.Done THEN
		fip := AosIP.StrToAdr(fipstr);
		IF (fip # AosIP.NilAdr) THEN
			Out.String("Receiving '"); Out.String(fnl); Out.String("' from "); Out.String(fipstr); Out.String("...");
			IF TFTP.Receive(fnr, fnl, fip) THEN Out.String(" success.")
			ELSE Out.String("error; check kernel log.")
			END
		ELSE Out.String("Invalid IP")
		END
	ELSE Out.String('Invalid parameters. Syntax: TestTFTP.Receive "<remotefilename>" "<localfilename>" "<ip>"')
	END;
	Out.Ln
END Receive;

END TFTPTool.
 

System.Free TestTFTP TFTP ~

TFTP.TraceLevel1
TFTP.TraceLevel2
TFTP.TraceLevel3

TFTPTool.Send "AOS:AosOberon.zip" "FAT:/AosOberon.zip" "10.0.0.4" ~
TFTPTool.Receive "FAT:/AosOberon.zip" "AOS:AosOberon.zip" "10.0.0.4" ~
