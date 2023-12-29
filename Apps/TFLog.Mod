MODULE TFLog; (** AUTHOR "TF"; PURPOSE "Log utility"; *)

IMPORT AosOut, AosClock, AosIO, AosFS;

CONST
	Unknown* = 0;
	Information* = 1;
	Warning* = 2;
	Error* = 3;

TYPE
	Log* = OBJECT
	VAR
		appName : ARRAY 64 OF CHAR;
		logPos : LONGINT;
		logLine : ARRAY 1024 OF CHAR;
		kind : LONGINT;
		locked : BOOLEAN;
		disableLogToOut : BOOLEAN;
		f : AosFS.File;
		w : AosFS.Writer;
		
		PROCEDURE &Init(logName : ARRAY OF CHAR);
		BEGIN
			COPY(logName, appName)
		END Init;
		
		PROCEDURE SetLogFile*(fn : ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			IF f # NIL THEN AosFS.Register(f) END;
			IF fn = "" THEN f := NIL 
			ELSE
				f := AosFS.Old(fn);
				IF f = NIL THEN f := AosFS.New(fn) END;
				AosFS.OpenWriter(w, f, f.Length())
			END	
		END SetLogFile;
		
		PROCEDURE SetLogToOut*(enabled : BOOLEAN);
		BEGIN {EXCLUSIVE}
			disableLogToOut := ~enabled
		END SetLogToOut;
		
		PROCEDURE SetKind(kind : LONGINT);
		BEGIN {EXCLUSIVE}
			SELF.kind := kind
		END SetKind;
		
		PROCEDURE InternalLn;
		BEGIN 
			logPos := 0; kind := Unknown;
			IF ~disableLogToOut THEN 
				AosOut.Enter;
				IF kind = Information THEN AosOut.String("[I] ") END;
				IF kind = Warning THEN AosOut.String("[W] ") END;
				IF kind = Error THEN AosOut.String("[E] ") END;
				AosOut.String(appName); AosOut.String(" : "); AosOut.String(logLine);
				AosOut.Exit
			END;
			logLine[0] := 0X;
			IF f # NIL THEN w.Ln; w.Update; f.Update() END
		END InternalLn;
		
		PROCEDURE Ln*;
		BEGIN {EXCLUSIVE}
			InternalLn
		END Ln;
		
		PROCEDURE Enter*;
		BEGIN {EXCLUSIVE}
			AWAIT(~locked); locked := TRUE
		END Enter;
		
		PROCEDURE Exit*;
		BEGIN {EXCLUSIVE}
			InternalLn;
			locked := FALSE
		END Exit;
		
		PROCEDURE InternalChar(x: CHAR);
		BEGIN
			IF logPos >= LEN(logLine) - 1 THEN InternalLn END;
			logLine[logPos] := x; logLine[logPos + 1] := 0X; INC(logPos);
			IF f # NIL THEN w.Char(x) END
		END InternalChar;	
		
		PROCEDURE Char*(x: CHAR);
		BEGIN {EXCLUSIVE}
			InternalChar(x)
		END Char;
		
		PROCEDURE InternalString*(VAR x: ARRAY OF CHAR);
		VAR i : LONGINT;
		BEGIN 
			WHILE (i < LEN(x)) & (x[i] # 0X) DO InternalChar(x[i]); INC(i) END
		END InternalString;
		
		PROCEDURE String*(x: ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			InternalString(x)
		END String;
		
		PROCEDURE Hex*(x, w: LONGINT);
		VAR i, j: LONGINT; buf: ARRAY 10 OF CHAR;
		BEGIN {EXCLUSIVE}
			IF w >= 0 THEN j := 8 ELSE j := 2; w := -w END;
			FOR i := j+1 TO w DO InternalChar(" ") END;
			FOR i := j-1 TO 0 BY -1 DO
				buf[i] := CHR(x MOD 10H + 48);
				IF buf[i] > "9" THEN
					buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
				END;
				x := x DIV 10H
			END;
			buf[j] := 0X;
			InternalString(buf)
		END Hex;
		
		PROCEDURE Int*(x, w: LONGINT);
		VAR i, x0: LONGINT; a: ARRAY 12 OF CHAR;
		BEGIN {EXCLUSIVE}
			IF x < 0 THEN
				IF x = MIN(LONGINT) THEN
					DEC(w, 11);
					WHILE w > 0 DO Char(" "); DEC(w) END;
					a := "-2147483648"; InternalString(a);
					RETURN
				ELSE
					DEC(w); x0 := -x
				END
			ELSE
				x0 := x
			END;
			i := 0;
			REPEAT
				a[i] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(i)
			UNTIL x0 = 0;
			WHILE w > i DO InternalChar(" "); DEC(w) END;
			IF x < 0 THEN InternalChar("-") END;
			REPEAT DEC(i); InternalChar(a[i]) UNTIL i = 0
		END Int;
		
		PROCEDURE TimeStamp*;
		TYPE TimeDate = RECORD h, m, s, day,month,year: LONGINT END;
			VAR s : ARRAY 32 OF CHAR;
				now : TimeDate;
		
			PROCEDURE LZ(v, len: LONGINT; VAR s: ARRAY OF CHAR; VAR pos: LONGINT);
			VAR i: LONGINT;
			BEGIN
				FOR i := 1 TO len DO s[pos+len-i] := CHR(ORD("0")+v MOD 10); v := v DIV 10 END;
				INC(pos, len)
			END LZ;
			
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
			
			PROCEDURE TimeDateToStr(dt: TimeDate; VAR s: ARRAY OF CHAR);
			VAR p: LONGINT;
			BEGIN
				LZ(dt.day, 2, s, p); s[p] := "."; INC(p);
				LZ(dt.month, 2, s, p); s[p] := "."; INC(p);
				LZ(dt.year, 2, s, p); s[p] := " "; INC(p);
				LZ(dt.h, 2, s, p); s[p] := ":"; INC(p);
				LZ(dt.m, 2, s, p); s[p] := ":"; INC(p);
				LZ(dt.s, 2, s, p); s[p] := 0X			
			END TimeDateToStr;
			
		BEGIN
			GetTime(now);
			TimeDateToStr(now, s);
			InternalString(s); InternalChar(" ")
		END TimeStamp;
		
		PROCEDURE Close*();
		BEGIN 
			IF f # NIL THEN AosFS.Register(f)
			END
		END Close;
		
	END Log;

END TFLog.
 

System.Free TFLog ~