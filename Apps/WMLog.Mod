MODULE WMLog;	(** AUTHOR "TF"; PURPOSE "Display the kernel log"; *)

IMPORT
	SYSTEM, AosOut, AosIO, AosTexts, AosTextUtilities, AosKernel, AosModules;

CONST
	BufSize = 8192 * 16; (* Kernel buffer size *)
	UpdateInterval = 200;	(* ms *)
	LocalBuf = 4096 * 2;

VAR buf : POINTER TO ARRAY OF CHAR;
	kernelLog- : AosTexts.Text;

TYPE
	(* periodically poll the kernel log buffer *)
	Logger = OBJECT
	VAR  
		timer : AosKernel.Timer; 
		alive, dead, added : BOOLEAN; 
		buf : ARRAY LocalBuf OF CHAR;
		bufPos : LONGINT;
		ch : CHAR;
		tw : AosTextUtilities.TextWriter;
		w : AosIO.Writer;

		PROCEDURE &Open;
		BEGIN
			dead := FALSE; alive := TRUE;
			NEW(timer);
			NEW(tw, kernelLog);
			w := tw.GetWriter()
		END Open;

		PROCEDURE Close;
		BEGIN {EXCLUSIVE}
			AosOut.CloseBuffer;
			alive := FALSE; timer.Wakeup;
			AWAIT(dead)
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

	BEGIN {ACTIVE}
		(* pre loading the fonts so traps can be displayed even when the disk is causing the trap *)
		tw.SetFontName("Courier"); w.String("Log started"); 
		tw.SetFontName("Oberon"); w.Ln;
		WHILE alive DO
			bufPos := 0; added := FALSE;
			LOOP
				ch := Get();
				IF ch # 0X THEN 
					IF ch = 0EX THEN tw.SetFontName("Courier"); tw.SetFontColor(0800000FFH)
					ELSIF ch = 0FX THEN tw.SetFontName("Oberon"); tw.SetFontColor(0FFH)
					ELSE w.Char(ch); added := TRUE;
					END;
				END;	(* 0X (end), 0DX (CR), 0AX (LF), 0EX (FixedFont), 0FX (NormalFont) *)
				IF (ch = 0X) OR ~alive THEN EXIT END;
			END;
			IF added THEN w.Update END;
			timer.Sleep(UpdateInterval)
		END;
		BEGIN {EXCLUSIVE} dead := TRUE END;
		logger := NIL
	END Logger;

VAR logger : Logger;

PROCEDURE Start*(par : PTR) : PTR;
VAR mod : AosModules.Module; 
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
	NEW(kernelLog);
	IF Start(NIL) = NIL THEN END;
	AosModules.InstallTermHandler(Cleanup)
END WMLog.

WMLog.Start ~
WMLog.Stop ~
S.Free LogWindow WMLog ~
