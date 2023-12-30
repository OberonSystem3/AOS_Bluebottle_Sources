MODULE AosV24Tracer; (** AUTHOR "TF/AFI"; PURPOSE "Man in the middle attack for Serial Ports" *)

IMPORT
	AosCommands, AosIO, AosModules, AosOut, AosSerials, Utilities;

TYPE
	SerialPortTracer = OBJECT
	VAR
		port : AosSerials.Port;
		seq : LONGINT;	(* Sequence number of this serial port tracer *)
		ch : CHAR;
		V24writer : AosIO.Writer;	(* Writer used by this serial port tracer *)
		alive : BOOLEAN;
		res : LONGINT;
	
	PROCEDURE &Init(seqNo, portNo, bps : LONGINT);
	BEGIN
		port := AosSerials.GetPort(portNo);
		IF res = 0 THEN
			port.Open(bps, 8, AosSerials.ParNo, AosSerials.Stop1, res);
			AosIO.OpenWriter(V24writer, port.Send);
			seq := seqNo
		END;
	END Init;	
	
	PROCEDURE Close;
	BEGIN
		alive := FALSE;
		port.Close()
	END Close;

	BEGIN {ACTIVE}
		alive := TRUE;
		WHILE alive DO
			port.ReceiveChar(ch, res);
			IF res = AosSerials.Ok THEN
				IF fine THEN	(* Display the origin of each character, its hex value and its printable value *)
					AosOut.Ln; AosOut.Int(seq, 0); AosOut.String(" --> : ");
					AosOut.Hex(ORD(ch), -2); AosOut.Char("X");
					IF ORD(ch) > 32 THEN AosOut.String("   "); AosOut.Char(ch) END
				ELSE	(* Display a stream of characters with the same origin. In order to obtain this result,
								it is preferable, when a modem is tested, to operate it without echo - use an ATE0 command. *)
					IF seq # activeseq THEN
						activeseq := seq;
						AosOut.Ln; AosOut.Int(seq, 0); AosOut.String(" --> : ")
					END;
					IF ORD(ch) > 32 THEN AosOut.Char(ch)
					ELSIF (ch = " ") OR (ch = 0DX)OR (ch = 0AX) THEN AosOut.Char(" ")
					ELSE IF ch # 0AX THEN AosOut.Hex(ORD(ch), -2); AosOut.Char("X") END
					END;
				END;
				(* Send the character just received to the other port *)
				tracingport[(seq + 1) MOD 2].V24writer.Char(ch);
				tracingport[(seq + 1) MOD 2].V24writer.Update();
			ELSE
				alive := FALSE;
				AosOut.String("Character in error "); AosOut.Char(ch); AosOut.Int(res, 4); AosOut.Ln;
			END;
		END;
		AosOut.String("Tracer "); AosOut.Int(seq, 0); AosOut.String(" terminated."); AosOut.Ln
	END SerialPortTracer;						

VAR running, fine : BOOLEAN;
	tracingport : ARRAY 2 OF SerialPortTracer;
	activeseq : LONGINT;

PROCEDURE SetMode*(par : PTR) : PTR;
VAR
	s: AosCommands.Parameters;
	name : ARRAY 100 OF CHAR;
	sr : AosIO.StringReader;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.Token(name);
	IF name = "fine" THEN fine := TRUE ELSE fine := FALSE END;
	AosOut.String("Tracing mode "); AosOut.String(name); AosOut.Ln;
	RETURN NIL
END SetMode;

PROCEDURE Enable*(par : PTR) : PTR;
VAR
	s: AosCommands.Parameters;
	name : ARRAY 100 OF CHAR;
	sr : AosIO.StringReader; inPort, outPort, baud : LONGINT;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.SkipWhitespace; sr.Int(inPort, FALSE); 
	sr.SkipWhitespace; sr.Int(outPort, FALSE); 
	sr.SkipWhitespace; sr.Int(baud, FALSE); 
	NEW(tracingport[0], 0, inPort, baud);	(* Instantiate 2 active tracers, which will be used in alternance *)
	NEW(tracingport[1], 1, outPort, baud);
	running := TRUE;
	AosOut.String("Tracing active ... "); AosOut.Ln;
	activeseq := -1;
	RETURN NIL
END Enable;

PROCEDURE Finalize;
BEGIN
END Finalize;

PROCEDURE Disable*(par : PTR) : PTR;
BEGIN
	tracingport[0].Close();
	tracingport[1].Close();
	RETURN NIL
END Disable;

BEGIN
	fine := TRUE;	(* Default *)
	AosModules.InstallTermHandler(Finalize)
END AosV24Tracer.

Use: 
	1. Add the device to be traced to serialport 0 
	2. Add the machine that knows the device to serialport 1 (eg. Windows/Linux/Unix/... with driver)
	3. Start the tracer, guessing the connection settings eg. baud rate (coarse mode is better in many cases)
	4. Start using the device
	5. Look at the data in the kernel log
	6. If output looks strange, disable the tracer, reguess the connection settings and goto 3

AosV24Tracer.Enable 0 1 9600 ~ InPort OutPort bps
AosV24Tracer.SetMode coarse ~
AosV24Tracer.SetMode fine ~
AosV24Tracer.Disable ~
S.Free AosV24Tracer ~

