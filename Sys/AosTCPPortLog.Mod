MODULE AosTCPPortLog; (** AUTHOR "TF"; PURPOSE "TCP port logger"; *)

IMPORT
	AosClock, AosOut, AosModules, AosNet, AosIP, AosTCP;
		
TYPE
	TimeDate = RECORD h, m, s, day,month,year: LONGINT END;

PROCEDURE GetTime(VAR dt: TimeDate);
BEGIN
	AosClock.Get(dt.h, dt.year);
	dt.s := dt.h MOD 64; dt.h := dt.h DIV 64;
	dt.m := dt.h MOD 64; dt.h := dt.h DIV 64;
	dt.h := dt.h MOD 24;
	dt.day := dt.year MOD 32; dt.year := dt.year DIV 32;
	dt.month := dt.year MOD 16; dt.year := dt.year DIV 16;
	INC(dt.year, 1900)			
END GetTime;

PROCEDURE IntToStr(v, len: LONGINT; VAR s: ARRAY OF CHAR; VAR pos: LONGINT);
VAR i: LONGINT;
BEGIN
	FOR i := 1 TO len DO s[pos+len-i] := CHR(ORD("0")+v MOD 10); v := v DIV 10 END;
	INC(pos, len)
END IntToStr;

PROCEDURE TimeDateToStr(dt: TimeDate; VAR s: ARRAY OF CHAR);
VAR p: LONGINT;
BEGIN
	IntToStr(dt.day, 2, s, p); s[p] := "."; INC(p);
	IntToStr(dt.month, 2, s, p); s[p] := "."; INC(p);
	IntToStr(dt.year, 2, s, p); s[p] := " "; INC(p);
	IntToStr(dt.h, 2, s, p); s[p] := ":"; INC(p);
	IntToStr(dt.m, 2, s, p); s[p] := ":"; INC(p);
	IntToStr(dt.s, 2, s, p); s[p] := 0X			
END TimeDateToStr;

PROCEDURE DumpListener(fip: AosIP.Adr; buffer: AosNet.Buffer);
VAR fport, lport, th, flags: LONGINT; time: TimeDate; adrStr, timeStr: ARRAY 32 OF CHAR;
BEGIN
	GetTime(time); TimeDateToStr(time, timeStr);
	fport := AosNet.GetNet2(buffer.data, buffer.ofs);
	lport := AosNet.GetNet2(buffer.data, buffer.ofs+2);
	flags := ORD(buffer.data[buffer.ofs+13]);
	AosIP.AdrToStr(fip, adrStr);
	AosOut.Enter;  AosOut.String(timeStr); 
	AosOut.String(" Rejected TCP segment to port "); AosOut.Int(lport, 1); AosOut.String(" from "); AosOut.String(adrStr);
	AosOut.String(":"); AosOut.Int(fport, 1); AosOut.String(" {");
	IF ODD(ASH(flags, -7)) THEN AosOut.String(" res7") END;
	IF ODD(ASH(flags, -6)) THEN AosOut.String(" res6") END;
	IF ODD(ASH(flags, -5)) THEN AosOut.String(" URG") END;
	IF ODD(ASH(flags, -4)) THEN AosOut.String(" ACK") END;
	IF ODD(ASH(flags, -3)) THEN AosOut.String(" PSH") END;
	IF ODD(ASH(flags, -2)) THEN AosOut.String(" RST") END;
	IF ODD(ASH(flags, -1)) THEN AosOut.String(" SYN") END;
	IF ODD(flags) THEN AosOut.String(" FIN") END;
	AosOut.String(" } ");
	AosOut.Exit
END DumpListener;

PROCEDURE Install*;
BEGIN
	AosTCP.SetDefaultListener(DumpListener);
	AosOut.Enter; AosOut.String("Default TCP port listener installed"); AosOut.Exit
END Install;

PROCEDURE Remove*;
BEGIN
	AosTCP.SetDefaultListener(NIL);
	AosOut.Enter; AosOut.String("Default TCP port listener removed"); AosOut.Exit
END Remove;

BEGIN
	AosModules.InstallTermHandler(Remove)
END AosTCPPortLog.
 
AosTCPPortLog.Install

