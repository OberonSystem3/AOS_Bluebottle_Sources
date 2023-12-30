MODULE CATServer; (** AUTHOR "TF"; PURPOSE "Cluster Administration Tool server"; *)

IMPORT
	AosModules, AosIO, AosFS, AosIP, AosTCP,  AosTCPServices, AosLog := TFLog, AosPerformance;


CONST CATPort = 9999;
TYPE
	CATAgent = OBJECT (AosTCPServices.Agent)
		VAR in: AosIO.Reader; out: AosIO.Writer;
			token : ARRAY 16 OF CHAR;
			x : LONGINT;
	BEGIN {ACTIVE}
		(* open streams *)
		AosIO.OpenReader(in, client.Receive);
		AosIO.OpenWriter(out, client.Send);
		LOOP
			in.Token(token); in.SkipLn; IF in.res # 0 THEN EXIT END;
			IF token = "getOS" THEN out.String("Aos"); out.Ln; out.Update
			ELSIF token = "getLoad" THEN 		
				x := ENTIER(AosPerformance.load[0] * 100 + 0.5);
				out.Int(x DIV 100, 3); out.Char(".");out.Int(x DIV 10 MOD 10, 1); out.Int(x MOD 10, 1);
				out.Ln; out.Update
			ELSE out.String("not implemented"); out.Ln; out.Update
			END;
			IF out.res # 0 THEN EXIT END
		END;
		Terminate
	END CATAgent;

VAR cat : AosTCPServices.Service;
		log : AosLog.Log;
		
PROCEDURE NewCATAgent(c: AosTCP.Connection; s: AosTCPServices.Service): AosTCPServices.Agent;
VAR a: CATAgent;
BEGIN
	NEW(a, c, s); RETURN a
END NewCATAgent;


PROCEDURE Start*(par: PTR): PTR;
VAR 
	res : LONGINT;
BEGIN
	IF cat = NIL THEN
		NEW(cat, CATPort, NewCATAgent, res);
		log.Enter; log.TimeStamp; log.String("Started"); log.Exit
	END;	
	RETURN NIL
END Start;

PROCEDURE Stop*(par: PTR): PTR;
BEGIN
	IF cat # NIL THEN
		cat.Stop; cat := NIL;
		log.Enter; log.TimeStamp; log.String("Stopped"); log.Exit
	END;
	RETURN NIL
END Stop;

PROCEDURE Cleanup;
BEGIN
	IF Stop(NIL) = NIL THEN END;
	log.Close()
END Cleanup;

BEGIN
	NEW(log, "CAT Server"); log.SetLogToOut(TRUE);
	AosModules.InstallTermHandler(Cleanup)
END CATServer.
 

Aos.Call CATServer.Start~
System.Free CATServer ~