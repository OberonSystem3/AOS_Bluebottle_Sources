MODULE AosSerials; (** AUTHOR: "afi"; PURPOSE: "Generic serial communication ports driver"; *)
(** 
 * Designed to support serial communication via the conventional RS232-type serial communication ports COM1 to COM8 and
 * via a USB port with a USB to serial adapter. Hot plug-in of the device is possible. For that reason, devices  are registered/unregistered 
 * by procedures located in this module. 
 *
 * Usage:
 *
 *	AosSerials.Show ~	displays a list of all available serial ports
 *
 *	AosSerials.CloseAllPorts ~ forces closing all serials ports
 *
 * History:
 *
 *	20.01.2006	First Release (afi)
 *	14.06.2006	Fixed Port.Send, introduced result value for Port.SendChar, implemented termination handler, cleanup (staubesv)
 *	26.06.2006	Added charactersSent, characterReceived for tracking (staubesv)
 *	04.08.2006	Removed SetPortState from Port interface (staubesv)
 *)
 
IMPORT AosIO, AosModules, AosOut;

CONST
	Verbose = TRUE;

	MaxPorts* = 16;

	(** Parity *)
	ParNo* = 0;  ParOdd* = 1;  ParEven* = 2;  ParMark* = 3;  ParSpace* = 4;

	(** Stop bits *)
	Stop1* = 1;  Stop2* = 2;  Stop1dot5* = 3;

	(** Modem control lines *)
	DTR* = 0;  RTS* = 1;	(** output *)
	Break* = 2;	(** input/output - Bit 6 in LCR *)
	DSR* = 3;  CTS* = 4;  RI* = 5;  DCD* = 6;	(** input *)

	(** Receive error diagnostic *)
	OverrunError* = 10;
	ParityError* = 11;	
	FramingError* = 12;
	BreakInterrupt* = 13;

	(** Error conditions *)
	Ok* =  0; 
	Closed* = -1;
	TransportError* = -2;  (** Error on transport layer, e.g. USB error in RS-232 over USB *)

	(** Errors for Port.Open procedure *)
	PortInUse* =  1; NoSuchPort* =  2; WrongBPS* =  3; WrongData* =  4; WrongParity* =  5; WrongStop* =  6;

TYPE

	Port* = OBJECT (AosIO.Connection)
	VAR
		name- : ARRAY 6 OF CHAR;
		description- : ARRAY 128 OF CHAR;
		
		(** Characters sent/read since port has been opened. Consider these fields read-only! *)
		charactersSent*, charactersReceived* : LONGINT;
				
		PROCEDURE Open* (bps, data, parity, stop : LONGINT; VAR res: LONGINT);
		END Open;
		
		PROCEDURE Close* ;
		END Close;
				
		PROCEDURE SendChar* (ch: CHAR; VAR res : LONGINT);
		END SendChar;

		(** Send len characters from buf to output, starting at ofs. res is non-zero on error. *)
		PROCEDURE Send*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		VAR i : LONGINT;
		BEGIN
			i := 0;
			WHILE i < len DO
				SendChar(buf[ofs + i], res);
				IF res # Ok THEN RETURN END;
				INC(i)
			END
		END Send;
		
		PROCEDURE ReceiveChar* (VAR ch: CHAR; VAR res: LONGINT);
		END ReceiveChar;

		(** Receive size characters into buf, starting at ofs and return the effective number of bytes read in len.
			Wait until at least min bytes (possibly zero) are available. res is non-zero on error. *)
		PROCEDURE Receive*(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		VAR ch: CHAR;
		BEGIN
			len := 0;
			res := Ok;
			WHILE (len < min) DO
				ReceiveChar(ch, res);
				IF res # Ok THEN RETURN END;
				buf[ofs + len] := ch;
				INC(len);
			END;
			WHILE (Available() > 0) & (len < size) DO
				ReceiveChar(ch, res);
				IF res # Ok THEN RETURN END;
				buf[ofs + len] := ch;
				INC(len)
			END;
		END Receive;
		
		PROCEDURE Available*(): LONGINT;
		END Available;
		
		(** Get the port state: state (open, closed), speed in bps, no. of data bits, parity, stop bit length. *)
		PROCEDURE GetPortState*(VAR openstat : BOOLEAN; VAR bps, data, parity, stop : LONGINT);
		END GetPortState;

		(** Clear the specified modem control lines.  s may contain DTR, RTS & Break. *)
		PROCEDURE ClearMC*(s: SET);
		END ClearMC;

		(** Set the specified modem control lines.  s may contain DTR, RTS & Break. *)
		PROCEDURE SetMC*(s: SET);
		END SetMC;

		(** Return the state of the specified modem control lines. s contains
			the current state of DSR, CTS, RI, DCD & Break Interrupt. *)
		PROCEDURE GetMC*(VAR s: SET);
		END GetMC;
		
		PROCEDURE Show*;
		BEGIN
			AosOut.String(name); AosOut.String(" ("); AosOut.String(description); AosOut.String(")");
		END Show;

	END Port;

VAR
	(* 	In this array the RS232-type COM ports are registered in the first 8 array elements.
		USB ports equipped with a USB to serial adapter are registered in the next 8 array elements. *)
	ports : ARRAY MaxPorts OF Port;

(** At the disposal of the USB driver modules for hot plug-in of a device. *)
PROCEDURE RegisterPort* (port : Port; description : ARRAY OF CHAR);
VAR name : ARRAY 6 OF CHAR; portNumber : LONGINT;
BEGIN {EXCLUSIVE}
	ASSERT(port # NIL);
	portNumber := 9;
	WHILE (portNumber < LEN(ports)) & (ports[portNumber-1] # NIL) DO INC(portNumber); END;
	IF portNumber < LEN(ports) THEN
		ports[portNumber-1] := port;
		name := "COM";
		IF portNumber < 10 THEN 
			name[3] := CHR(ORD("0") + portNumber);
		ELSE
			name[3] := CHR(ORD("0") + portNumber DIV 10);
			name[4] := CHR(ORD("0") + portNumber MOD 10);
		END;
		COPY(name, port.name);
		COPY(description, port.description);
		IF Verbose THEN AosOut.String("AosSerials: "); port.Show; AosOut.String(" is now available."); AosOut.Ln; END;
	ELSE
		AosOut.String("AosSerials: Could not register port: No free slots."); AosOut.Ln;
	END;
END RegisterPort;

(** At the disposal of the USB driver modules for hot plug-in of a device. *)
PROCEDURE UnRegisterPort* (port : Port);
VAR i : LONGINT;
BEGIN {EXCLUSIVE}
	i := 0; WHILE (i < LEN(ports)) & (ports[i] # port) DO INC(i); END;
	IF i < LEN(ports) THEN
		ports[i].Close;
		ports[i] := NIL;
		IF Verbose THEN AosOut.String("AosSerials: "); port.Show; AosOut.String(" has been removed."); AosOut.Ln; END;
	ELSE
		AosOut.String("AosSerials: Warning: UnRegisterPort: Port not found."); AosOut.Ln;
	END;
END UnRegisterPort;

(**	COM1 to COM8 are reserved for RS-232 / V24 communication ports. Other ports will be named COM9, COM9 and so on as needed.
	The idea is that the onboard COM ports get the same port numbers as in the BIOS *)
PROCEDURE RegisterOnboardPort*(portNumber : LONGINT; port : Port; name, description : ARRAY OF CHAR);
BEGIN {EXCLUSIVE}
	IF (portNumber >= 1) & (portNumber <= LEN(ports)) & (ports[portNumber-1] = NIL) THEN
		ports[portNumber-1] := port;
		COPY(name, port.name);
		COPY(description, port.description);
	ELSE
		AosOut.String("AosSerials: Warning; Could not register onboard port."); AosOut.Ln;
	END;	
END RegisterOnboardPort;

PROCEDURE GetPort* (portNumber : LONGINT) : Port;
VAR port : Port;
BEGIN {EXCLUSIVE}
	IF (portNumber >= 1) & (portNumber <= LEN(ports)) & (ports[portNumber-1] # NIL) THEN
		port := ports[portNumber-1];
	END;
	RETURN port;	
END GetPort;

PROCEDURE Show*(ptr : PTR) : PTR;
VAR port : Port; noPortsAvailable : BOOLEAN; i : LONGINT;
BEGIN {EXCLUSIVE}
	noPortsAvailable := TRUE;
	AosOut.String("AosSerials: "); AosOut.Ln;
	FOR i := 0 TO LEN(ports)-1 DO
		port := ports[i];;
		IF port # NIL THEN
			noPortsAvailable := FALSE;
			AosOut.String(port.name); AosOut.Char(9X); AosOut.String(port.description); AosOut.Ln;
		END;
	END;
	IF noPortsAvailable THEN AosOut.String("No serial ports found."); END;
	AosOut.Ln;
	RETURN NIL;
END Show;

(** Test serial ports COM1 and if present COM2 with the generic driver *)
PROCEDURE Test*(par : PTR) : PTR;
VAR
	result : LONGINT;
	portgotten : Port;
BEGIN
	portgotten := GetPort (1);
	IF portgotten # NIL THEN
		portgotten.Open (4800, 8, 2, 2, result);
		portgotten.Close ();
		portgotten := GetPort (2);
		IF portgotten # NIL THEN
			portgotten.Open (9600, 8, 2, 2, result);
			portgotten.Close ()
		ELSE
			AosOut.String ("Invalid port number"); AosOut.Ln
		END
	ELSE
		AosOut.String ("Invalid port number"); AosOut.Ln
	END;
	RETURN NIL
END Test;

(** Close all serial ports *)
PROCEDURE CloseAllPorts*(par : ANY) : ANY;
VAR portNbr : LONGINT;
BEGIN {EXCLUSIVE}
	FOR portNbr := 0 TO LEN(ports)-1 DO
		IF ports[portNbr] # NIL THEN
			ports[portNbr].Close;
		END;
	END;	
	RETURN NIL;
END CloseAllPorts;

PROCEDURE Cleanup;
BEGIN 
	IF CloseAllPorts(NIL) = NIL THEN END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END AosSerials.

S.Free AosV24 AosSerials ~

AosV24.Install ~
AosSerials.Test ~
AosSerials.Show ~

