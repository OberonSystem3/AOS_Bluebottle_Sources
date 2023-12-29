MODULE S;

IMPORT
	AosOut, AosModules, AosActive, AosHeap, AosCommands, AosIO;
	
PROCEDURE Free*(par : ANY) : ANY;
VAR
	s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	name : ARRAY 64 OF CHAR;
	msg : ARRAY 128 OF CHAR;
	res : LONGINT;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	WHILE sr.res = 0 DO
		sr.Token(name); sr.SkipWhitespace;
		IF name # "" THEN
			AosOut.String("Unloading "); AosOut.String(name);
			AosModules.FreeModule(name, res, msg);
			IF res # 0 THEN AosOut.String(msg)
			ELSE AosOut.String(" done.")
			END;
			AosOut.Ln
		END
	END;
	RETURN NIL
END Free;

PROCEDURE Kill*(par : ANY) : ANY;
TYPE
	ProcessList = POINTER TO RECORD
		next: ProcessList;
		thread: AosActive.Process
	END;
VAR
	t: AosActive.Process;
	list, n: ProcessList;

	s : AosCommands.Parameters;
	sr : AosIO.StringReader;
	pid : LONGINT;
BEGIN {EXCLUSIVE}
	AosActive.snapshotEnabled := TRUE;  list := NIL;
	AosHeap.GC;
	WHILE AosActive.snapshot # NIL DO
		t := AosActive.snapshot;  AosActive.snapshot := t.link;  t.link := NIL;
		NEW(n);  n.thread := t;  n.next := list;  list := n
	END;

	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	WHILE sr.res = 0 DO
		sr.SkipWhitespace;
		sr.Int(pid, FALSE);
		n := list;  WHILE (n # NIL) & (n.thread.id # pid) DO n := n.next END;
		AosOut.Int(pid, 0); 
		IF n # NIL THEN
			AosActive.TerminateThis(n.thread, FALSE);
			AosOut.String(" Process killed") 
		ELSE AosOut.String(" Process not found")
		END;
		AosOut.Ln 
	END;
	RETURN NIL
END Kill;


END S.

PED.Open AosTools.Mod



S.Free S 
S.Kill 57  



