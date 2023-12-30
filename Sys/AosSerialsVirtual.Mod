MODULE AosSerialsVirtual; (** AUTHOR: "staubesv"; PURPOSE: "Virtual serial port driver"; *)
(**
 * This driver creates two virtual serial port instances that are linked using a virtual null-modem cable, i.e. the data sent to one
 * port is received by the other and vice versa.
 * Idea: One of the ports can be used by the application under development and the other is used to send data to this application, for example, 
 * simulated output of a serial port device.
 *
 * Usage:
 *
 *	AosSerialsVirtual.Install ~ creates two virtual serial port instances that are cross-linked and registers them at AosSerials
 *
 *	AosSerialsVirtual.SendFile portNbr filename [Loop] ~ 	sends the content of the specified file to the specified virtual serial port.  
 *														The data is then received by its companion port.
 *	AosSerialsVirtual.StopSendFile portNbr ~				stops sending a file for the specified port 
 *
 *	AosSerialsVirtual.InstallSniffer ~ installs a virtal serial port that acts as proxy for the specified port
 *
 *	S.Free AosSerialsVirtual ~ Unregisters virtual serial ports at AosSerials
 *
 * History:
 *	
 *	20.06.2006	Created (staubesv)
 *	26.06.2006	Speed emulation (staubesv)
 *	27.06.2006	Implemented PortSniffer (staubesv)
 *)
 
IMPORT
	AosOut, Utilities, AosModules, AosCommands, AosIO, AosFS, AosKernel,
	AosSerials;
	
CONST

	Verbose = TRUE;
	
	BufferSize = 1024;
	
	(* If TRUE, the SendChar procedure is artificially slowed down to the speed approx. bps *)
	EnableSendSpeedLimitation = TRUE;
	
	ModuleName = "AosSerialsVirtual";
	
TYPE

	SendProcedure = PROCEDURE {DELEGATE} (ch : CHAR; VAR res : LONGINT);

	(** Virtual serial port the can be linked to other virtual serial port *)
	VirtualPort = OBJECT (AosSerials.Port)
	VAR
		buffer : ARRAY BufferSize OF CHAR;
		head, tail : LONGINT;
	
		open : BOOLEAN;
		bps, data, parity, stop : LONGINT;
		mc : SET;
		
		sender : SendProcedure;
		
		(* Send speed emulation fields *)
		eachNCharacters, waitForMs : LONGINT;
		timer : AosKernel.Timer;
		
		(** Virtual Port Interface *)
		
		PROCEDURE PutChar*(ch : CHAR; VAR res : LONGINT);
		VAR n : LONGINT;
		BEGIN {EXCLUSIVE}
			IF ~open THEN 
				res := AosSerials.Closed;
			ELSE
				AWAIT(((tail + 1) MOD BufferSize # head) OR ~open); (* Wait until buffer is not full *)
				IF open THEN 
					buffer[tail] := ch;
					tail := (tail + 1) MOD BufferSize;
					res := AosSerials.Ok;
				ELSE
					res := AosSerials.Closed;
				END;
			END;
		END PutChar;
		
		(** Serial Port Interface *)

		PROCEDURE Open* (bps, data, parity, stop : LONGINT; VAR res: LONGINT);
		BEGIN {EXCLUSIVE}
			IF open THEN
				IF Verbose THEN ShowModule; AosOut.String(name); AosOut.String(" already open"); AosOut.Ln; END;
				res := AosSerials.PortInUse;
				RETURN
			END;
			SetPortState(bps, data, parity, stop, res);
			IF res = AosSerials.Ok THEN
				open := TRUE; head := 0; tail := 0;
				charactersSent := 0; charactersReceived := 0;
				IF Verbose THEN ShowModule; AosOut.String(name); AosOut.String(" opened"); AosOut.Ln; END;
			END;
		END Open;
		
		PROCEDURE Close* ();
		BEGIN {EXCLUSIVE}
			open := FALSE;
			tail := -1;
			IF Verbose THEN ShowModule; AosOut.String(name); AosOut.String(" closed"); AosOut.Ln; END;
		END Close;
		
		PROCEDURE SendChar* (ch: CHAR; VAR res : LONGINT);
		BEGIN {EXCLUSIVE}
			IF ~open THEN res := AosSerials.Closed; END;
			IF sender # NIL THEN
				sender(ch, res);
				INC(charactersSent);
				IF EnableSendSpeedLimitation & (waitForMs # 0) & (charactersSent MOD eachNCharacters = 0) THEN
					timer.Sleep(waitForMs);
				END;
			END;
		END SendChar;
		
		(** Wait for the next character is received in the input buffer. The buffer is fed by HandleInterrupt *)
		PROCEDURE ReceiveChar*(VAR ch: CHAR; VAR res: LONGINT);
		BEGIN {EXCLUSIVE}
			IF ~open THEN res := AosSerials.Closed; RETURN END;
			AWAIT((tail # head) OR ~open);
			IF ~open OR (tail = -1) THEN
				res := AosSerials.Closed;
			ELSE
				ch := buffer[head]; head := (head+1) MOD BufferSize;
				INC(charactersReceived);
				res := AosSerials.Ok;
			END
		END ReceiveChar;

		PROCEDURE Available*(): LONGINT;
		BEGIN {EXCLUSIVE}
			RETURN (tail - head) MOD BufferSize
		END Available;
		
		(* Set the port state: speed in bps, no. of data bits, parity, stop bit length. *)
		PROCEDURE SetPortState(bps, data, parity, stop : LONGINT; VAR res: LONGINT);
		BEGIN
			SELF.bps := bps; SELF.data := data; SELF.parity := parity; SELF.stop := stop;
			res := AosSerials.Ok;
			IF EnableSendSpeedLimitation THEN
				GetSlowdownValues(bps, eachNCharacters, waitForMs, res);
			END;
		END SetPortState;

		(** Get the port state: state (open, closed), speed in bps, no. of data bits, parity, stop bit length. *)
		PROCEDURE GetPortState*(VAR openstat : BOOLEAN; VAR bps, data, parity, stop : LONGINT);
		BEGIN {EXCLUSIVE}
			openstat := open;
			bps := SELF.bps; data := SELF.data; parity := SELF.parity; stop := SELF.stop;
		END GetPortState;

		(** Clear the specified modem control lines.  s may contain DTR, RTS & Break. *)
		PROCEDURE ClearMC*(s: SET);
		BEGIN {EXCLUSIVE}
			mc := mc - s;
		END ClearMC;

		(** Set the specified modem control lines.  s may contain DTR, RTS & Break. *)
		PROCEDURE SetMC*(s: SET);
		BEGIN {EXCLUSIVE}
			mc := mc + s;
		END SetMC;

		(** Return the state of the specified modem control lines.  s contains
			the current state of DSR, CTS, RI, DCD & Break Interrupt. *)
		PROCEDURE GetMC*(VAR s: SET);
		BEGIN {EXCLUSIVE}
			s := mc;	
		END GetMC;
		
		PROCEDURE &Init;
		BEGIN
			NEW(timer);
		END Init;

	END VirtualPort;
	
TYPE

	(* Note: If logging to the Kernel Log, be sure that associated real serial port is not the one which AosOut uses *)
	PortSniffer = OBJECT(AosSerials.Port)
	VAR
		port : AosSerials.Port;
		in, out : AosIO.Writer;

		PROCEDURE Open* (bps, data, parity, stop : LONGINT; VAR res: LONGINT);
		BEGIN {EXCLUSIVE}
			port.Open(bps, data, parity, stop, res);
			IF res = AosSerials.Ok THEN
				charactersSent := 0; charactersReceived := 0;
			END;
		END Open;
		
		PROCEDURE Close* ();
		BEGIN {EXCLUSIVE}
			port.Close;
		END Close;
		
		PROCEDURE SendChar* (ch: CHAR; VAR res : LONGINT);
		BEGIN {EXCLUSIVE}
			port.SendChar(ch, res);
			IF res = AosSerials.Ok THEN
				IF out # NIL THEN
					out.Char(ch); out.Update;
				ELSE
					IF Verbose THEN AosOut.Char(ch); END;
				END;
				INC(charactersSent);
			ELSE
				IF Verbose THEN 
					ShowModule; AosOut.String("Error while sending '"); AosOut.Char(ch); AosOut.String("': ");
					AosOut.Int(res, 0); AosOut.Ln;
				END;
			END;
		END SendChar;
		
		(** Wait for the next character is received in the input buffer. The buffer is fed by HandleInterrupt *)
		PROCEDURE ReceiveChar*(VAR ch: CHAR; VAR res: LONGINT);
		BEGIN {EXCLUSIVE}
			port.ReceiveChar(ch, res);
			IF res = AosSerials.Ok THEN 
				IF in # NIL THEN
					in.Char(ch); in.Update;
				ELSE
					IF Verbose THEN AosOut.Char(ch); END;
				END;
				INC(charactersReceived);
			ELSE
				IF Verbose THEN ShowModule; AosOut.String("Error while receiving: "); AosOut.Int(res, 0); AosOut.Ln; END;
			END;
		END ReceiveChar;

		PROCEDURE Available*(): LONGINT;
		BEGIN {EXCLUSIVE}
			RETURN port.Available();
		END Available;
		
		(** Get the port state: state (open, closed), speed in bps, no. of data bits, parity, stop bit length. *)
		PROCEDURE GetPortState*(VAR openstat : BOOLEAN; VAR bps, data, parity, stop : LONGINT);
		BEGIN {EXCLUSIVE}
			port.GetPortState(openstat, bps, data, parity, stop);
		END GetPortState;

		(** Clear the specified modem control lines. s may contain DTR, RTS & Break. *)
		PROCEDURE ClearMC*(s: SET);
		BEGIN {EXCLUSIVE}
			port.ClearMC(s);
		END ClearMC;

		(** Set the specified modem control lines. s may contain DTR, RTS & Break. *)
		PROCEDURE SetMC*(s: SET);
		BEGIN {EXCLUSIVE}
			port.SetMC(s);
		END SetMC;

		(** Return the state of the specified modem control lines. s contains the current state of DSR, CTS, RI, DCD & Break Interrupt. *)
		PROCEDURE GetMC*(VAR s: SET);
		BEGIN {EXCLUSIVE}
			port.GetMC(s);
		END GetMC;
		
		PROCEDURE &Init(port : AosSerials.Port; in, out : AosIO.Writer);
		BEGIN
			ASSERT(port # NIL);
			SELF.port := port; SELF.in := in; SELF.out := out;
		END Init;
		
	END PortSniffer;
		
VAR
	active : ARRAY AosSerials.MaxPorts+1 OF BOOLEAN;

PROCEDURE ShowModule;
BEGIN
	AosOut.String(ModuleName); AosOut.String(": ");
END ShowModule;

PROCEDURE GetSlowdownValues(bps : LONGINT; VAR eachNCharacters, waitForMs, res : LONGINT);
BEGIN
	res := AosSerials.Ok;
	waitForMs := 1;
	IF bps = 0 THEN waitForMs := 0; (* Don't limit speed *)
	ELSIF bps = 300 THEN eachNCharacters := 1; waitForMs := 4;
	ELSIF bps = 600 THEN eachNCharacters := 1; waitForMs := 2;
	ELSIF bps = 1200 THEN eachNCharacters := 1;
	ELSIF bps = 2400 THEN eachNCharacters := 2;
	ELSIF bps = 4800 THEN eachNCharacters := 4;
	ELSIF bps = 9600 THEN eachNCharacters := 8;
	ELSIF bps = 19200 THEN eachNCharacters := 16;
	ELSIF bps = 38400 THEN eachNCharacters := 32;
	ELSIF bps = 115200 THEN eachNCharacters := 100;
	ELSE
		res := AosSerials.WrongBPS;
	END;
END GetSlowdownValues;

PROCEDURE GetPortNumber(par : PTR; VAR r : AosIO.StringReader) : LONGINT;
VAR p : AosCommands.Parameters; portNbr : LONGINT;
BEGIN
	p := par (AosCommands.Parameters);
	NEW(r, LEN(p.str)); r.Set(p.str^);
	r.SkipWhitespace; r.Int(portNbr, FALSE);
	IF (r.res # AosIO.Ok) OR (portNbr < 1) OR (portNbr > AosSerials.MaxPorts) THEN
		portNbr := -1;
		ShowModule; AosOut.String("Expected portNbr parameter"); AosOut.Ln;
	END;
	RETURN portNbr;
END GetPortNumber;

PROCEDURE SendFileIntern(portNbr : LONGINT; filename : ARRAY OF CHAR; loop : BOOLEAN);
VAR
	port : AosSerials.Port;
	file : AosFS.File;
	len, res : LONGINT;
	in : AosFS.Reader; out : AosIO.Writer;
	buffer : ARRAY BufferSize OF CHAR;
BEGIN
	BEGIN {EXCLUSIVE}
		IF active[portNbr] THEN 
			ShowModule; AosOut.String("Port is already used for data generation"); AosOut.Ln;
			RETURN;
		ELSE
			active[portNbr] := TRUE;
		END;
	END;
	port := AosSerials.GetPort(portNbr);
	IF port # NIL THEN
		file := AosFS.Old(filename);
		IF file # NIL THEN
			port.Open(600, 8, 2, 2, res);
			IF res = AosSerials.Ok THEN
				ShowModule; AosOut.String("Sending file "); AosOut.String(filename); AosOut.String(" to serial port "); AosOut.Int(portNbr, 0); 
				IF loop THEN AosOut.String(" [LOOP MODE]"); END; AosOut.String("... ");
				NEW(out, port.Send, BufferSize);
				AosFS.OpenReader(in, file, 0);
				REPEAT
					in.Bytes(buffer, 0, BufferSize, len); out.Bytes(buffer, 0, len); out.Update;
					IF loop & (in.res = AosIO.EOF) THEN AosFS.OpenReader(in, file, 0); END;
				UNTIL (in.res # AosIO.Ok) OR (out.res # AosIO.Ok) OR (active[portNbr] = FALSE);
				AosOut.String("done."); AosOut.Ln;
			ELSE ShowModule; AosOut.String("Could not open port "); AosOut.Int(portNbr, 0); AosOut.String(", res: "); AosOut.Int(res, 0); AosOut.Ln;
			END;
			port.Close;
		ELSE ShowModule; AosOut.String("Could not open file "); AosOut.String(filename); AosOut.Ln;
		END;
	ELSE ShowModule; AosOut.String("Could not get serial port "); AosOut.Int(portNbr, 0); AosOut.Ln;
	END;
	BEGIN {EXCLUSIVE} 
		IF active[portNbr] THEN active[portNbr] := FALSE; END;
	END;
END SendFileIntern;

(** Send the content of the specified file to the specified serial port. If the Loop parameter is used, the file is sent
	in a endless loop. Sending can be stopped using the StopSendFile commands *)
PROCEDURE SendFile*(par : ANY) : ANY; (** portNbr filename [Loop] ~ *)
VAR r : AosIO.StringReader; portNbr : LONGINT; filename, parString : ARRAY AosFS.NameLength OF CHAR; loop : BOOLEAN;
BEGIN
	portNbr := GetPortNumber(par, r);
	IF (r.res = AosIO.Ok) & (portNbr # -1) THEN
		r.SkipWhitespace; r.String(filename);
		IF r.res = AosIO.Ok THEN
			r.SkipWhitespace; r.String(parString);
			IF (r.res = AosIO.Ok) & Utilities.Match(parString, "Loop") THEN loop := TRUE; END;
			SendFileIntern(portNbr, filename, loop);
		ELSE ShowModule; AosOut.String("Expected portNbr filename parameters. Could not read filename."); AosOut.Ln;
		END;
	END;
	RETURN NIL
END SendFile;

(** Stop sending a file for the specified port *)
PROCEDURE StopSendFile*(par : ANY) : ANY; (** portNbr ~ *)
VAR r : AosIO.StringReader; portNbr : LONGINT;
BEGIN
	portNbr := GetPortNumber(par, r);
	IF portNbr # -1 THEN
		BEGIN {EXCLUSIVE} 
			IF active[portNbr] THEN
				active[portNbr] := FALSE; 
				ShowModule; AosOut.String("Stopped generator on port "); AosOut.Int(portNbr, 0); AosOut.Ln;
			ELSE
				ShowModule; AosOut.String("No generator running on port "); AosOut.Int(portNbr, 0); AosOut.Ln;
			END;
		END;
	END;	
	RETURN NIL
END StopSendFile;

(** Installs two virtual serial ports which are linked to each other. Data sent by one port is received by the other and vice versa *)
PROCEDURE Install*(par : ANY) : ANY; (** ~ *)
VAR port1, port2 : VirtualPort; description : ARRAY 128 OF CHAR;
BEGIN
	NEW(port1); NEW(port2); 
	port1.sender := port2.PutChar;
	port2.sender := port1.PutChar;
	
	description := "Virtual Serial Port";
	AosSerials.RegisterPort(port1, description);
	
	Utilities.Append(description, " (Linked to "); Utilities.Append(description, port1.name); Utilities.Append(description, ")");
	AosSerials.RegisterPort(port2, description);
	
	RETURN NIL
END Install;

(** Install a virtual sniffer port as proxy for the specified serial port *)
PROCEDURE InstallSniffer*(par : ANY) : ANY; (** [portNbr] ~ *)
VAR 
	r : AosIO.StringReader;
	portSniffer : PortSniffer; port : AosSerials.Port;
	portNbr : LONGINT;
	description : ARRAY 128 OF CHAR;
BEGIN
	portNbr := GetPortNumber(par, r);
	IF portNbr = -1 THEN RETURN NIL; END;
	
	port := AosSerials.GetPort(portNbr);
	IF port # NIL THEN
		NEW(portSniffer, port, NIL, NIL);
		description := "Virtual Serial Port (Sniffer linked to ";
		Utilities.Append(description, port.name); Utilities.Append(description, ")"); 
		AosSerials.RegisterPort(portSniffer, description);
	ELSE
		ShowModule; AosOut.String("Port "); AosOut.Int(portNbr, 0); AosOut.String(" not found."); AosOut.Ln;
	END;
	RETURN NIL
END InstallSniffer;

PROCEDURE Cleanup;
VAR portNbr : LONGINT;
BEGIN
	FOR portNbr := 1 TO AosSerials.MaxPorts DO
		active[portNbr] := FALSE;
	END;	
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END AosSerialsVirtual.
