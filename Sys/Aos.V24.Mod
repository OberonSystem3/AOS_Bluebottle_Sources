MODULE V24; (** AUTHOR "AFI"; PURPOSE "Backward compatibility module" *)

(* Ensures the further validity of the earlier Aos.V24.Mod (object module V24.Obx)
	authored by "pjm".
	Most of the port control is now displaced to the new driver module
	AosV24.Obx module (Source AosV24.Mod *)

IMPORT AosSerials, SYSTEM;

CONST	(* Needed for compatibility *)
	(** Port aliases (check with NumberOfPorts) *)
	COM1* = 1;  COM2* = 2;  COM3* = 3;  COM4* = 4;
	COM5* = 5;  COM6* = 6;  COM7* = 7;  COM8* = 8;
	
	(** Parity *)
	ParNo* = AosSerials.ParNo;  ParOdd* = AosSerials.ParOdd;  ParEven* = AosSerials.ParEven;
	ParMark* = AosSerials.ParMark;  ParSpace* = AosSerials.ParSpace;

	(** Stop bits *)
	Stop1* = AosSerials.Stop1;  Stop2* = AosSerials.Stop2;  Stop1dot5* = AosSerials.Stop1dot5;

	(** Modem control lines *)
	DTR* = AosSerials.DTR;  RTS* = AosSerials.RTS;	(** output *)
	Break* = AosSerials.Break;	(** input/output - Bit 6 in LCR *)
	DSR* = AosSerials.DSR;  CTS* = AosSerials.CTS;  RI* = AosSerials.RI;  DCD* = AosSerials.DCD;	(** input *)

	(** Receive error diagnostic *)
	OE* = AosSerials.OverrunError;
	PE* = AosSerials.ParityError;
	FE* = AosSerials.FramingError;
	BI* = AosSerials.BreakInterrupt;
	termination* = AosSerials.Closed;	(* Indicates that the port is being closed *)

	Ok* =  AosSerials.Ok; PortInUse* =  AosSerials.PortInUse; NoSuchPort* =  AosSerials.NoSuchPort;
	WrongBPS* =  AosSerials.WrongBPS; WrongData* =  AosSerials.WrongData; WrongParity* =  AosSerials.WrongParity;
	WrongStop* =  AosSerials.WrongStop;

VAR ports: ARRAY AosSerials.MaxPorts + 1 OF AosSerials.Port; (* ports[0] is unused *)

(** NumberOfPorts - Return number of ports available. *)
PROCEDURE NumberOfPorts*(): LONGINT;
BEGIN
	RETURN AosSerials.MaxPorts;
END NumberOfPorts;

(** Start - Open a serial port (numbered from 0) connection.  bps is the required bits per second.
	data is the number of bits per communication unit.  parity is the parity mode (Par
	values above).  stop is the number of stop bits (Stop values above).  res returns 0
	if ok, or error code on error.  1 means port already in use.  2 means no such port.
	3 means bad bps value.  4 means bad data/parity/stop.   DTR and RTS are enabled. *)
PROCEDURE Start*(portNo, bps, data, parity, stop: LONGINT; VAR res: LONGINT);
VAR port : AosSerials.Port;
BEGIN
	res := NoSuchPort;
	port := AosSerials.GetPort(portNo);
	IF port # NIL THEN
		ports[portNo] := port;
		ports[portNo].Open(bps, data, parity, stop, res)
	END;
END Start;

(** Stop - Close the connection of the specified port. Effect on Modem Control lines is undefined. *)
PROCEDURE Stop*(portNo: LONGINT);
BEGIN
	ports[portNo].Close()
END Stop;

(** Send - Send a byte to the specified port. Waits until buffer space is available. res = Ok iff ok. *)
(**  Antediluvian: Kept for compatibility. - Use Writer... instead. *)
PROCEDURE Send*(portNo: LONGINT; x: SYSTEM.BYTE; VAR res: LONGINT);
BEGIN
	ports[portNo].SendChar(CHR(x), res);
END Send;

(** SendBytes - Send n bytes to the specified port. Waits until buffer space is available. res = Ok iff all ok. *)
(**  Antediluvian: Kept for compatibility. - Use Writer... instead. *)
PROCEDURE SendBytes*(portNo: LONGINT; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT; VAR res: LONGINT);
VAR i: LONGINT;
BEGIN
	i := 0;  res := AosSerials.Ok;
	WHILE (i # n) & (res = AosSerials.Ok) DO
		Send(portNo, x[i], res);  INC(i)
	END
END SendBytes;

(** Receive - Read one byte from the specified port. Waits until a byte is available. res = Ok iff ok. *)
PROCEDURE Receive*(portNo: LONGINT; VAR x: SYSTEM.BYTE; VAR res: LONGINT);
VAR ch: CHAR;
BEGIN
	ports[portNo].ReceiveChar(ch, res);
	x := ch
END Receive;

(** ReceiveBytes - Read n bytes from the specified port. Waits until n bytes are available. res = Ok iff ok.
		In case of error, the reception ends immediately at the first character in error. More data may be left in the buffer. *)
PROCEDURE ReceiveBytes*(portNo: LONGINT; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT; VAR res: LONGINT);
VAR i: LONGINT;
BEGIN
	i := 0;  res := AosSerials.Ok;
	WHILE (i # n) & (res = AosSerials.Ok) DO
		Receive(portNo, x[i], res);  INC(i)
	END
END ReceiveBytes;

(** ClearMC - Clear the specified modem control lines.  s may contain DTR, RTS & Break. *)
PROCEDURE ClearMC*(portNo: LONGINT; s: SET);
BEGIN
	ports[portNo].ClearMC(s)
END ClearMC;

(** SetMC - Set the specified modem control lines.  s may contain DTR, RTS & Break. *)
PROCEDURE SetMC*(portNo: LONGINT; s: SET);
BEGIN
	ports[portNo].SetMC(s)
END SetMC;

(** GetMC - Return the state of the specified modem control lines.  s contains
	the current state of DSR, CTS, RI, DCD & Break. *)
PROCEDURE GetMC*(portNo: LONGINT; VAR s: SET);
BEGIN
	ports[portNo].GetMC(s)
END GetMC;

(** Available - Return the number of bytes available in the specified port's buffer. *)
PROCEDURE Available*(portNo: LONGINT): LONGINT;
BEGIN
	RETURN ports[portNo].Available()
END Available;

END V24.

System.Free V24 ~
