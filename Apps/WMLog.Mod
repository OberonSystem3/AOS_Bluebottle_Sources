MODULE WMLog;	(** AUTHOR "TF"; PURPOSE "Display the kernel log"; *)

IMPORT
	SYSTEM, AosOut, AosBeep, Texts := AosTexts, AosKernel, AosModules, UTF8Strings;

CONST
	Width = 700;
	Height = 800;
	BufSize = 8192 * 16; (* Kernel buffer size *)
	MaxLogLength = 50000; (* keep MaxLogLength characters in the log *)
	UpdateInterval = 200;	(* ms *)
	LocalBuf = 4096 * 2;

VAR buf: POINTER TO ARRAY OF CHAR;
	kernelLog- : Texts.UnicodeText;
	
TYPE
	(* periodically poll the kernel log buffer *)
	Logger = OBJECT
	VAR  
		timer : AosKernel.Timer; 
		alive, dead : BOOLEAN; 
		buf: ARRAY LocalBuf OF CHAR;
		bufPos, ucspos : LONGINT;
		char : Texts.Char32;
		ucs32buf : ARRAY 256 OF Texts.Char32;
		
		PROCEDURE &Open;
		BEGIN
			dead := FALSE; alive := TRUE;
			NEW(timer)
		END Open;
		
		PROCEDURE Close;
		BEGIN {EXCLUSIVE}
			AosOut.CloseBuffer;
			alive := FALSE; timer.Wakeup;
			AWAIT(dead);
		END Close;
		
		PROCEDURE Get() : CHAR;
		VAR res : CHAR;
		BEGIN
			IF (bufPos >= LocalBuf) OR (buf[bufPos] = 0X) THEN 
				bufPos := 0;
				AosOut.GetBuffer(buf)
			END;
			res := buf[bufPos];
			INC(bufPos);
			RETURN res
		END Get;
		
		PROCEDURE GetUTF8Char(VAR u : Texts.Char32) : BOOLEAN;
		VAR ch : ARRAY 8 OF CHAR; i : LONGINT;
		BEGIN
			ch[0] := Get();
			FOR i := 1 TO ORD(UTF8Strings.CodeLength[ORD(ch[0])]) - 1 DO ch[i] := Get() END;
			i := 0;
			RETURN UTF8Strings.DecodeChar(ch, i, u)
		END GetUTF8Char;
		
	BEGIN {ACTIVE}
		WHILE alive DO
			ucspos := 0; bufPos := 0;
			LOOP
				IF GetUTF8Char(char) THEN END;	(* 0X (end), 0DX (CR), 0AX (LF), 0EX (FixedFont), 0FX (NormalFont) *)
				IF (char = 0) OR ~alive THEN EXIT END;
				ucs32buf[ucspos] := char; INC(ucspos);
				IF ucspos = 255 THEN
					ucs32buf[ucspos] := 0;
					kernelLog.AcquireWrite;
					kernelLog.InsertUCS32(kernelLog.GetLength(), ucs32buf);
					kernelLog.ReleaseWrite;
					ucspos := 0
				END;	
			END;
			ucs32buf[ucspos] := 0;
			IF ucs32buf[0] # 0 THEN
				kernelLog.AcquireWrite;
				kernelLog.InsertUCS32(kernelLog.GetLength(), ucs32buf);
				kernelLog.ReleaseWrite 
			END;
			timer.Sleep(UpdateInterval)
		END;
		BEGIN{EXCLUSIVE} dead := TRUE END;
		logger := NIL
	END Logger;

VAR logger : Logger;

PROCEDURE Start*(par : PTR) : PTR;
VAR mod: AosModules.Module; 
	kernelLockOberon, kernelUnlockOberon, systemStopLog : AosModules.CommandProc;
BEGIN {EXCLUSIVE}
	IF logger # NIL THEN AosOut.Enter; AosOut.String("Logger already running! "); AosOut.Exit; RETURN NIL END;

	AosOut.Enter; AosOut.String("Starting logger"); AosOut.Exit;
	NEW(buf, BufSize);
	IF ~AosOut.OpenBuffer(SYSTEM.ADR(buf[0]), LEN(buf)) THEN
		(* Kill Oberon Logger *)
		mod := AosModules.ModuleByName("Kernel");
		IF mod # NIL THEN
			kernelLockOberon := AosModules.ThisCommand(mod, "LockOberon");
			kernelUnlockOberon := AosModules.ThisCommand(mod, "UnlockOberon");
		END;
		mod := AosModules.ModuleByName("System");
		IF mod # NIL THEN
			systemStopLog := AosModules.ThisCommand(mod, "StopLog");
		END;
		IF (kernelLockOberon # NIL) & (kernelUnlockOberon # NIL) &(systemStopLog # NIL) THEN 
			kernelLockOberon; systemStopLog; kernelUnlockOberon;
			AosOut.CloseBuffer; 	IF AosOut.OpenBuffer(SYSTEM.ADR(buf[0]), LEN(buf)) THEN
				AosOut.Enter; AosOut.String("Oberon KernelLog stopped. New buffer installed"); AosOut.Exit
			END
		END;
	END; 
	NEW(logger);
	RETURN NIL
END Start;

PROCEDURE Stop*(par : PTR) : PTR;
BEGIN {EXCLUSIVE}
	IF logger # NIL THEN
		AosOut.Enter; AosOut.String("Stopping logger"); AosOut.Exit;
		logger.Close;
		AosOut.Enter; AosOut.String("Logger stopped"); AosOut.Exit;
	END;	
	RETURN NIL
END Stop;

PROCEDURE Cleanup;
BEGIN
	IF logger # NIL THEN
		AosOut.CloseBuffer;
		logger.Close
	END	
END Cleanup;

BEGIN
	IF Start(NIL) = NIL THEN END;
	NEW(kernelLog);
	AosModules.InstallTermHandler(Cleanup)
END WMLog.


S.Free LogWindow WMLog ~
