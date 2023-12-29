MODULE V24; (** AUTHOR "AFI"; PURPOSE "Backward compatibility module" *)

(* Ensures the further validity of the earlier Aos.V24.Mod (object module V24.Obx)
	authored by "pjm".
	Most of the port control is now displaced to the new driver module
	AosV24.Obx module (Source AosV24.Mod *)

IMPORT AosV24, SYSTEM;

CONST	(* Needed for compatibility *)
	(** Port aliases (check with NumberOfPorts) *)
	COM1* = 0;  COM2* = 1;  COM3* = 2;  COM4* = 3;
	COM5* = 4;  COM6* = 5;  COM7* = 6;  COM8* = 7;
	
	(** Parity *)
	ParNo* = AosV24.ParNo;  ParOdd* = AosV24.ParOdd;  ParEven* = AosV24.ParEven;
	ParMark* = AosV24.ParMark;  ParSpace* = AosV24.ParSpace;

	(** Stop bits *)
	Stop1* = AosV24.Stop1;  Stop2* = AosV24.Stop2;  Stop1dot5* = AosV24.Stop1dot5;

	(** Modem control lines *)
	DTR* = AosV24.DTR;  RTS* = AosV24.RTS;	(** output *)
	Break* = AosV24.Break;	(** input/output - Bit 6 in LCR *)
	DSR* = AosV24.DSR;  CTS* = AosV24.CTS;  RI* = AosV24.RI;  DCD* = AosV24.DCD;	(** input *)

	(** Receive error diagnostic *)
	OE* = AosV24.OE;	(** Overrun Error *)
	PE* = AosV24.PE;	(** Parity Error *)
	FE* = AosV24.FE;	(** Framing Error *)
	BI* = AosV24.BI;	(** Break Interrupt *)
	termination* = AosV24.termination;	(* Indicates that the port is being closed *)

	Ok* =  AosV24.Ok; PortInUse* =  AosV24.PortInUse; NoSuchPort* =  AosV24.NoSuchPort;
	WrongBPS* =  AosV24.WrongBPS; WrongData* =  AosV24.WrongData; WrongParity* =  AosV24.WrongParity;
	WrongStop* =  AosV24.WrongStop;

VAR ports: ARRAY 8 OF AosV24.Port;

(** NumberOfPorts - Return number of ports available. *)
PROCEDURE NumberOfPorts*(): LONGINT;
BEGIN
	RETURN AosV24.noOfPorts
END NumberOfPorts;

(** Start - Open a serial port (numbered from 0) connection.  bps is the required bits per second.
	data is the number of bits per communication unit.  parity is the parity mode (Par
	values above).  stop is the number of stop bits (Stop values above).  res returns 0
	if ok, or error code on error.  1 means port already in use.  2 means no such port.
	3 means bad bps value.  4 means bad data/parity/stop.   DTR and RTS are enabled. *)
PROCEDURE Start*(portNo, bps, data, parity, stop: LONGINT; VAR res: LONGINT);
BEGIN
	ports[portNo] := AosV24.GetPort(portNo);
	ports[portNo].Open(bps, data, parity, stop, res)
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
	ports[portNo].SendChar(CHR(x));
	res := AosV24.Ok
END Send;

(** SendBytes - Send n bytes to the specified port. Waits until buffer space is available. res = Ok iff all ok. *)
(**  Antediluvian: Kept for compatibility. - Use Writer... instead. *)
PROCEDURE SendBytes*(portNo: LONGINT; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT; VAR res: LONGINT);
VAR i: LONGINT;
BEGIN
	i := 0;  res := AosV24.Ok;
	WHILE (i # n) & (res = AosV24.Ok) DO
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
	i := 0;  res := AosV24.Ok;
	WHILE (i # n) & (res = AosV24.Ok) DO
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
BEGIN
END V24.

System.Free V24 ~
