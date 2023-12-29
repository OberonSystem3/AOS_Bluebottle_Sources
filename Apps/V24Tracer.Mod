MODULE V24Tracer; (** AUTHOR "TF/AFI"; PURPOSE "Man in the middle attack for Serial Ports" *)

IMPORT
	AosCommands, AosIO, AosModules, AosOut, AosV24, Utilities;

TYPE
	SerialPortTracer = OBJECT
	VAR
		port : AosV24.Port;
		seq : LONGINT;	(* Sequence number of this serial port tracer *)
		ch : CHAR;
		V24writer : AosIO.Writer;	(* Writer used by this serial port tracer *)
		alive : BOOLEAN;
		res : LONGINT;
	
	PROCEDURE &Init(seqNo, portNo, bps : LONGINT);
	BEGIN
		port := AosV24.GetPort(portNo);
		port.Open(bps, 8, AosV24.ParNo, AosV24.Stop1, res);
		IF res = 0 THEN
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
			IF res = 0 THEN
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
			ELSIF res = AosV24.termination THEN
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
END V24Tracer.

Use: 
	1. Add the device to be traced to serialport 0 
	2. Add the machine that knows the device to serialport 1 (eg. Windows/Linux/Unix/... with driver)
	3. Start the tracer, guessing the connection settings eg. baud rate (coarse mode is better in many cases)
	4. Start using the device
	5. Look at the data in the kernel log
	6. If output looks strange, disable the tracer, reguess the connection settings and goto 3

Aos.Call V24Tracer.Enable 0 1 9600 ~ InPort OutPort bps
Aos.Call V24Tracer.SetMode coarse
Aos.Call V24Tracer.SetMode fine
Aos.Call V24Tracer.Disable
System.Free V24Tracer ~

Color Codes used:
 Highlight
Types and Procedures
Lock Acquire / Lock Release
Preferred notation (comment)
Unsafe / Temporary / Stupid / requires attention
Permanent Comment
Assertion
Debug
