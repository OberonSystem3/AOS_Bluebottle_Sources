(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE WebDefaultSSMP; (** AUTHOR "TF"; PURPOSE "Default SSMP plugin (system info)"; *)

IMPORT
	AosBoot, AosIO, AosModules, WebSSMPPlugin, AosClock, WebHTTP, 
	WebHTTPServer, AosPerformance, AosTrap, AosKernel;

CONST Samples = 60;

TYPE 
	TimeSampleQueryMethod = PROCEDURE {DELEGATE} () : LONGINT;
	
	TimeSampler = OBJECT
	VAR
		hits : POINTER TO ARRAY OF LONGINT;
		pos : LONGINT;
		timer : AosKernel.Timer;
		query : TimeSampleQueryMethod;
		interval, nofSamples : LONGINT;
		alive : BOOLEAN;
		
		PROCEDURE &Init(queryMethod : TimeSampleQueryMethod; interval, samples : LONGINT);
		BEGIN
			NEW(timer); SELF.interval := interval; SELF.nofSamples := samples; SELF.query := queryMethod; NEW(hits, samples)
		END Init;
		
		PROCEDURE Step;
		BEGIN {EXCLUSIVE}
			hits^[pos] := query(); 
			INC(pos); pos := pos MOD nofSamples
		END Step;
		
		PROCEDURE QuerySamples(VAR x : ARRAY OF LONGINT);
		VAR i : LONGINT;
		BEGIN {EXCLUSIVE}
			FOR i := 0 TO nofSamples - 1 DO 
				x[i] := hits[(pos + i) MOD nofSamples]
			END
		END QuerySamples;
		
		PROCEDURE Kill;
		BEGIN 
			alive := FALSE; timer.Wakeup; timer.Wakeup
		END Kill;
		
	BEGIN {ACTIVE}
		alive := TRUE; pos := 0;
		
		WHILE alive DO 
			Step; IF alive THEN timer.Sleep(interval) END
		END
	END TimeSampler;
	
VAR hitSampler : TimeSampler;
(** samples are values 0..100*)
PROCEDURE HTMLBarChartVertical(VAR out : AosIO.Writer; samples : ARRAY OF LONGINT; start, end : LONGINT; 
							chartheight, barwidth, border, color: LONGINT);
VAR i, v : LONGINT;
BEGIN
	IF chartheight <= 0 THEN chartheight := 100 END;
	IF barwidth <= 0 THEN barwidth := 20 END;
	out.String('<table border="'); out.Int(border, 0); 
	out.String('" height="'); out.Int(chartheight, 0); out.String('">'); out.Ln;
	
	out.String('<tr valign="bottom">'); out.Ln;
	
	FOR i := start TO end DO 
		out.String('<td><table border="0" cellspacing="0" width="');
		out.Int(barwidth, 0);  
		out.String('" height="');
		v := (samples[i] * chartheight) DIV 100; (*IF v = 0 THEN v := 1 END;*)
		out.Int(v, 0);  
		out.String('" bgcolor="#'); out.Hex(color, 6); 
		out.String('" ><tr><td></td></tr></table></td>');
		out.Ln;
	END;
	out.String('</tr>'); out.Ln;
	out.String('</table>'); out.Ln
	
END HTMLBarChartVertical;

PROCEDURE ServerNofRequests(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
BEGIN
	out.Int(WebHTTPServer.GetRequests(), 5)
END ServerNofRequests;

PROCEDURE ServerRPMChart(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
VAR values : ARRAY 60 OF LONGINT; max: LONGINT; i : LONGINT;
BEGIN
	hitSampler.QuerySamples(values);
	FOR i := 0 TO 60 - 1 DO IF max < values[i] THEN max := values[i] END END;
	IF max = 0 THEN max := 1 END;
	FOR i := 0 TO 60 - 1 DO values[i] := values[i] * 100 DIV max END;
	HTMLBarChartVertical(out, values, 0, 60-1, 100, 5, 0, 0FF0000H)
END ServerRPMChart;

PROCEDURE ServerNofRequestsPerMinute(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
BEGIN
	out.Int(WebHTTPServer.requestsPerMinute, 5)
END ServerNofRequestsPerMinute;

PROCEDURE SystemTime(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
VAR time, date: LONGINT;
BEGIN
	AosClock.Get(time, date); out.Date822(time, date, AosClock.tz);
END SystemTime;

PROCEDURE SystemStartTime(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
BEGIN
	out.Date822(AosClock.starttime, AosClock.startdate, AosClock.tz)
END SystemStartTime;

PROCEDURE SystemLoad(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
VAR x, i: LONGINT;
BEGIN
	FOR i := 0 TO 2 DO
		x := ENTIER(AosPerformance.load[i]*100 + 0.5);
		out.Int(x DIV 100, 3); out.Char(".");
		out.Int(x DIV 10 MOD 10, 1); out.Int(x MOD 10, 1)
	END
END SystemLoad;

PROCEDURE SystemIdle(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
VAR i: LONGINT;
BEGIN
	i := 0; 
	WHILE (i < LEN(AosPerformance.idle)) & (AosPerformance.idle[i] > - 1) DO
		out.Int(AosPerformance.idle[i], 3); out.Char("%"); out.Char(" ");
		INC(i)
	END
END SystemIdle;

PROCEDURE SystemVersion(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
BEGIN
	out.String(AosBoot.version)
END SystemVersion;

PROCEDURE ReadName(VAR b: AosIO.Reader; VAR s: ARRAY OF CHAR);
VAR j, max: LONGINT; ch: CHAR;
BEGIN
	j := 0; max := LEN(s)-1;
	LOOP
		ch := b.Peek();
		IF ~(((CAP(ch) >= "A") & (CAP(ch) <= "Z")) OR ((ch >= "0") & (ch <= "9"))) OR (b.res # AosIO.Ok) THEN EXIT END;
		IF j < max THEN s[j] := ch; INC(j) END;
		ch := b.Get()
	END;
	s[j] := 0X
END ReadName;

PROCEDURE SystemState(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
VAR name: ARRAY 32 OF CHAR;
BEGIN
	in.SkipWhitespace; ReadName(in, name);
	(*out.String("System.State ");
	out.String(name); out.Ln;*)
	AosTrap.ModuleState(out, AosModules.ModuleByName(name))	(* no error message *)
END SystemState;

PROCEDURE SystemGet(VAR request : WebHTTP.RequestHeader; VAR in : AosIO.Reader; VAR out : AosIO.Writer);
VAR v: AosTrap.Variable; col: LONGINT; mod, var: ARRAY 32 OF CHAR;
BEGIN
	in.SkipWhitespace;
	ReadName(in, mod);
	IF in.Peek() = "." THEN
		in.Char(var[0]);	(* skip *)
		ReadName(in, var);
		IF AosTrap.FindVar(AosModules.ModuleByName(mod), var, v) THEN
			AosTrap.WriteVar(out, v, col)
		ELSE
			out.String("System.Get "); out.String(mod); out.Char("."); 
			out.String(var); out.String(": variable not found")
		END
	ELSE
		out.String("usage: System.Get module.variable")
	END
END SystemGet;

PROCEDURE Install*(p:PTR):PTR;
BEGIN
	WebSSMPPlugin.RegisterMethod("Server.NofRequests", ServerNofRequests);
	WebSSMPPlugin.RegisterMethod("Server.NofRequestsPerMinute", ServerNofRequestsPerMinute);
	WebSSMPPlugin.RegisterMethod("System.Time", SystemTime);
	WebSSMPPlugin.RegisterMethod("System.StartTime", SystemStartTime);
	WebSSMPPlugin.RegisterMethod("System.Load", SystemLoad);
	WebSSMPPlugin.RegisterMethod("System.Idle", SystemIdle);
	WebSSMPPlugin.RegisterMethod("System.Version", SystemVersion);
	WebSSMPPlugin.RegisterMethod("Server.RPMChart", ServerRPMChart);
	WebSSMPPlugin.RegisterMethod("System.State", SystemState);
	WebSSMPPlugin.RegisterMethod("System.Get", SystemGet);
	RETURN NIL
END Install;

PROCEDURE Cleanup;
BEGIN
	hitSampler.Kill;
	WebSSMPPlugin.UnregisterMethod("Server.NofRequests");
	WebSSMPPlugin.UnregisterMethod("Server.NofRequestsPerMinute");
	WebSSMPPlugin.UnregisterMethod("System.Time");
	WebSSMPPlugin.UnregisterMethod("System.StartTime");
	WebSSMPPlugin.UnregisterMethod("System.Load");
	WebSSMPPlugin.UnregisterMethod("System.Idle");
	WebSSMPPlugin.UnregisterMethod("System.Version");
	WebSSMPPlugin.UnregisterMethod("Server.RPMChart");
	WebSSMPPlugin.UnregisterMethod("System.State");
	WebSSMPPlugin.UnregisterMethod("System.Get")
END Cleanup;

PROCEDURE QueryRPM():LONGINT;
BEGIN
	RETURN WebHTTPServer.requestsPerMinute
END QueryRPM;

BEGIN
	NEW(hitSampler, QueryRPM, 10000, 60);
	AosModules.InstallTermHandler(Cleanup);
END WebDefaultSSMP.
 

EditTools.OpenUnix public.info.ssmp
EditTools.OpenUnix public.test.ssmp

System.Free WebDefaultSSMP~

Aos.Call WebDefaultSSMP.Install~
