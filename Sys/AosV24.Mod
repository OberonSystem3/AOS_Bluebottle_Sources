MODULE AosV24; (** AUTHOR "AFI"; PURPOSE "V24/RS-232 driver" *)
(** Supports a maximum of 8 COM serial ports at speeds up to 115'200 BPS.
	No longer compatible with ETH Native Oberon.

	The I/O base address and the IRQ corresponding to each COM port must be
	declared in Aos.Par, except that COM1 and COM2 are declared by default
	with their standard values
		COM1="3F8H,4"
		COM2="2F8H,3"
	and must be specified if these values do not apply to a particular machine.
	Bluebottle operates in 32-bit addressing mode and cannot interrogate
	the base address by accessing the port directly in BIOS.
	
	The ports are numbered in the order of appeareance in Aos.Par, starting from 0
	and are named logically starting from COM1.

	Includes a facility to determine the UART type and a facility to trace the data.

	References:
			Serial and UART Tutorial by Frank Durda
			"http://freebsd.org/doc/en_US.ISO8859-1/articles/serial-uart"

			"http://www.lammertbies.nl/comm/info/RS-232_uart.html"
*
* History:
*	
*	14.06.2006	Adapted to changes in AosSerials.Mod (staubesv)
*	26.06.2006	ClearMC, SetMC & GetMC procedure bodies made exclusive, performance counters implemented (staubesv)
*)

IMPORT AosIO, AosActive, AosBoot, AosInterrupts, AosOut, AosModules, SYSTEM, AosSerials;

CONST

	MaxPortNo = 8;	(* Up to 8 serial ports supported *)
	BufSize = 1024;

	(* Port registers *)
	(* RBR = 0;	 Select with DLAB = 0 - Receive Buffer Register - read only
							Select with DLAB = 1 - Baud Rate Divisor LSB *)
	IER = 1;	(* Select with DLAB = 0 - Interrupt Enable Register -  R/W
						 Select with DLAB = 1 - Baud Rate Divisor MSB *)
	IIR = 2;	(* Interrupt Identification Register - read only *)
	FCR = 2;	(* 16550 FIFO Control Register write only *)
	LCR = 3;	(* Line Control Register -  R/W *)
	MCR = 4;	(* Modem Control Register -  R/W *)
	LSR = 5;	(* Line Status Register -  read only*)
	MSR = 6;	(* Modem Status Register - R/W *)
	SCR = 7;	(* Scratch Register - R/W *)

	(** Modem control lines *)
	DTR* = 0;  RTS* = 1;	(** output *)
	Break* = 2;	(** input/output - Bit 6 in LCR *)
	DSR* = 3;  CTS* = 4;  RI* = 5;  DCD* = 6;	(** input *)

	ModuleName = "AosV24";

	Verbose = TRUE;

TYPE

	RS232Port = OBJECT (AosSerials.Port)
		VAR
			baseaddr, irq, maxbps: LONGINT;
			buf: ARRAY BufSize OF CHAR;
			head, tail: LONGINT;
			open, ox16: BOOLEAN;
			diagnostic: LONGINT;

		PROCEDURE &Init(basespec, irqspec : LONGINT);
		BEGIN
			baseaddr := basespec;
			irq := irqspec;
			open := FALSE; ox16 := CheckOX16PCI954(basespec);
			IF ox16 THEN
				maxbps := 460800
			ELSE
				maxbps := 115200
			END
		END Init;

		PROCEDURE Open*(bps, data, parity, stop : LONGINT; VAR res: LONGINT);
		BEGIN {EXCLUSIVE}
			IF open THEN
				IF Verbose THEN ShowModule; AosOut.String(name); AosOut.String(" already open"); AosOut.Ln; END;
				res := AosSerials.PortInUse;
				RETURN
			END;
			SetPortState(bps, data, parity, stop, res);
			IF res = AosSerials.Ok THEN
				open := TRUE;
				head := 0; tail:= 0;
				charactersSent := 0; charactersReceived := 0;
				(* install interrupt handler *)
				AosActive.InstallHandler(HandleInterrupt, AosInterrupts.IRQ0 + irq);
				SYSTEM.PORTOUT(baseaddr + IER, 01X);	(* Enable receive interrupts *)
				IF Verbose THEN ShowModule; AosOut.String(name); AosOut.String(" opened"); AosOut.Ln END;
			END
		END Open;

		(** Send a single character to the UART. *)
		PROCEDURE SendChar*(ch: CHAR; VAR res : LONGINT);
		VAR s: SET;
		BEGIN {EXCLUSIVE}
			IF ~open THEN res := AosSerials.Closed; RETURN; END;
			res := AosSerials.Ok;
			REPEAT	(* wait for room in Transmitter Holding Register *)
				SYSTEM.PORTIN(baseaddr + LSR, SYSTEM.VAL(CHAR, s))	(* now send that character *)
			UNTIL 5 IN s;
			SYSTEM.PORTOUT(baseaddr, ch);
			INC(charactersSent);
		END SendChar;

		(** Wait for the next character is received in the input buffer. The buffer is fed by HandleInterrupt *)
		PROCEDURE ReceiveChar*(VAR ch: CHAR; VAR res: LONGINT);
		BEGIN {EXCLUSIVE}
			IF ~open THEN res := AosSerials.Closed; RETURN END;
			AWAIT(tail # head);
			IF tail = -1 THEN
				res := AosSerials.Closed;
			ELSE
				ch := buf[head]; head := (head+1) MOD BufSize;
				res := diagnostic;
			END
		END ReceiveChar;

		(** On detecting an interupt request, transfer the characters from the UART buffer to the input buffer *)
		PROCEDURE HandleInterrupt;
		VAR n: LONGINT; ch: CHAR; s: SET;
		BEGIN {EXCLUSIVE}
			LOOP	(* transfer all the data available in the UART buffer to buf *) 
				SYSTEM.PORTIN(baseaddr + IIR, ch);
				IF ODD(ORD(ch)) THEN EXIT END;	(* nothing pending *)
				diagnostic := 0;
				SYSTEM.PORTIN(baseaddr + LSR, SYSTEM.VAL(CHAR, s));	(* Inspect if error *)
				IF (7 IN s) OR (1 IN s) THEN	(* Establish a diagnostic of the error *)
					IF (1 IN s) THEN diagnostic := AosSerials.OverrunError;
					ELSIF (2 IN s) THEN diagnostic := AosSerials.ParityError
					ELSIF (3 IN s) THEN diagnostic := AosSerials.FramingError
					ELSIF (4 IN s) THEN diagnostic := AosSerials.BreakInterrupt
					END;
				END;
				SYSTEM.PORTIN(baseaddr, ch);	(* Receive a character from the UART - baseaddr points to RBR *)
				n := (tail+1) MOD BufSize;
				IF n # head THEN buf[tail] := ch; tail := n END;
				INC(charactersReceived);
			END;
		END HandleInterrupt;

		PROCEDURE Available*(): LONGINT;
		BEGIN {EXCLUSIVE}
			RETURN (tail - head) MOD BufSize
		END Available;
		
		(* Set the port state: speed in bps, no. of data bits, parity, stop bit length. *)
		PROCEDURE SetPortState(bps, data, parity, stop : LONGINT; VAR res: LONGINT);
		CONST TCR = 2;
		VAR s: SET; tcr: LONGINT;
		BEGIN
			IF (bps > 0) & (maxbps MOD bps = 0) THEN
				IF (data >= 5) & (data <= 8) & (parity >= AosSerials.ParNo) & (parity <= AosSerials.ParSpace) &
						(stop >= AosSerials.Stop1) & (stop <= AosSerials.Stop1dot5) THEN
					IF ox16 THEN
						IF bps <= 115200 THEN
							tcr := 0
						ELSE
							tcr := 115200*16 DIV bps;
							ASSERT((tcr >= 4) & (tcr < 16));
							bps := 115200
						END;
						IF ReadICR(baseaddr, TCR) # CHR(tcr) THEN
							WriteICR(baseaddr, TCR, CHR(tcr))
						END
					END;
					bps := 115200 DIV bps;
					(* disable interrupts *)
					SYSTEM.PORTOUT(baseaddr+LCR, 0X);	(* clear DLAB *)
					SYSTEM.PORTOUT(baseaddr+IER, 0X);	(* Disable all interrupts *)
					(* clear latches *)
					SYSTEM.PORTIN(baseaddr+LSR, SYSTEM.VAL(CHAR, s));
					SYSTEM.PORTIN(baseaddr+IIR, SYSTEM.VAL(CHAR, s));
					SYSTEM.PORTIN(baseaddr+MSR, SYSTEM.VAL(CHAR, s));

					SYSTEM.PORTOUT(baseaddr+FCR, 0C1X);	(* See if one can activate the FIFO *)
					SYSTEM.PORTIN(baseaddr+IIR, SYSTEM.VAL(CHAR, s));	(* Read how the chip responded in bits 6 & 7 of IIR *)
					IF s * {6,7} = {6,7} THEN	(* FIFO enabled on 16550 chip and later ones *)
						SYSTEM.PORTOUT(baseaddr + FCR, 47X)	(* 16550 setup: EnableFifo, CLRRX, CLRTX, SIZE4 *)
					ELSIF s * {6,7} = {} THEN	(* Bits 6 and 7 are always zero on 8250 / 16450 chip *)
						SYSTEM.PORTOUT(baseaddr + FCR, 0X)
					ELSE AosOut.String("Not prepared to deal with this COM port situation");	(* This case should not exist *)
					END;
					(* set parameters *)
					SYSTEM.PORTOUT(baseaddr + LCR, 80X);	(* Set the Divisor Latch Bit - DLAB = 1 *)
					SYSTEM.PORTOUT(baseaddr, CHR(bps));	(* Set the Divisor Latch LSB *)
					SYSTEM.PORTOUT(baseaddr+1, CHR(bps DIV 100H));	(* Set the Divisor Latch MSB *)
					(* Prepare parameters destined to LCR data, stop, parity *)
					CASE data OF	(* word length *)
						   5: s := {}
						| 6: s := {0}
						| 7: s := {1}
						| 8: s := {0,1}
					END;
					IF stop # AosSerials.Stop1 THEN INCL(s, 2) END;
					CASE parity OF
						   AosSerials.ParNo:
						| AosSerials.ParOdd: INCL(s, 3)
						| AosSerials.ParEven: s := s + {3,4}
						| AosSerials.ParMark: s := s + {3,5}
						| AosSerials.ParSpace: s := s + {3..5}
					END;
					(* Finalize the LCR *)
					SYSTEM.PORTOUT(baseaddr+LCR, SYSTEM.VAL(CHAR, s));	(* DLAB is set = 0 at the same time *)
					(* Set DTR, RTS, OUT2 in the MCR *)
					SYSTEM.PORTOUT(baseaddr+MCR, SYSTEM.VAL(CHAR, {DTR,RTS,3}));
(*					SYSTEM.PORTOUT(baseaddr+IER, 01X);	*)
					res := AosSerials.Ok
				ELSE res := AosSerials.WrongData (* bad data/parity/stop *)
				END
			ELSE res := AosSerials.WrongBPS (* bad BPS *)
			END
		END SetPortState;

		(** Get the port state: state (open/closed), speed in bps, no. of data bits, parity, top bit length. *)
		PROCEDURE GetPortState*(VAR openstat : BOOLEAN; VAR bps, data, parity, stop : LONGINT);
		CONST TCR = 2;
		VAR savset, set: SET; ch: CHAR;
		BEGIN {EXCLUSIVE}
			(* get parameters *)
			openstat := open;
			SYSTEM.PORTIN(baseaddr + LCR, SYSTEM.VAL(CHAR, savset));
			set := savset + {7};
			SYSTEM.PORTOUT(baseaddr + LCR, SYSTEM.VAL(CHAR, set));	(* INCL the Divisor Latch Bit - DLAB = 1 *)
			SYSTEM.PORTIN(baseaddr+1, ch);
			bps := ORD(ch);
			SYSTEM.PORTIN(baseaddr, ch);
			IF (bps = 0 ) & (ch = 0X) THEN
			ELSE
				bps := 115200 DIV (100H*bps + ORD(ch))
			END;
			IF ox16 THEN
				ch := ReadICR(baseaddr, TCR);
				IF (ch >= 04X) & (ch < 16X) THEN
					bps := bps*16 DIV ORD(ch)
				END
			END;
			SYSTEM.PORTOUT(baseaddr+LCR, savset);	(* Reset the Divisor Latch Bit - DLAB = 0 *)
			SYSTEM.PORTIN(baseaddr+LCR, SYSTEM.VAL(CHAR, set));
			IF set * {0, 1} = {0, 1} THEN data := 8
			ELSIF set * {0, 1} = {1} THEN data := 7
			ELSIF set * {0, 1} = {0} THEN data := 6
			ELSE data := 5
			END;
			IF 2 IN set THEN
				IF set * {0, 1} = {} THEN stop := 3
				ELSE stop := 2
				END;
			ELSE stop := 1
			END;
			IF set * {3..5} = {3..5} THEN parity := 4
			ELSIF set * {3,5} = {3,5} THEN parity := 3
			ELSIF set * {3,4} = {3,4} THEN parity := 2
			ELSIF set * {3} = {3} THEN parity := 1
			ELSE parity := 0
			END;
		END GetPortState;

		(** Clear the specified modem control lines.  s may contain DTR, RTS & Break. *)
		PROCEDURE ClearMC*(s: SET);
		VAR t: SET;
		BEGIN {EXCLUSIVE}
			IF s * {DTR, RTS} # {} THEN
				SYSTEM.PORTIN(baseaddr + MCR, SYSTEM.VAL(CHAR, t));
				t := t - (s * {DTR, RTS});	(* modify only bits 0 & 1 *)
				SYSTEM.PORTOUT(baseaddr + MCR, SYSTEM.VAL(CHAR, t))
			END;
			IF Break IN s THEN
				SYSTEM.PORTIN(baseaddr + LCR, SYSTEM.VAL(CHAR, t));
				EXCL(t, 6);	(* break off *)
				SYSTEM.PORTOUT(baseaddr + LCR, SYSTEM.VAL(CHAR, t))
			END
		END ClearMC;

		(** Set the specified modem control lines.  s may contain DTR, RTS & Break. *)
		PROCEDURE SetMC*(s: SET);
		VAR t: SET;
		BEGIN {EXCLUSIVE}
			IF s * {DTR, RTS} # {} THEN
				SYSTEM.PORTIN(baseaddr + MCR, SYSTEM.VAL(CHAR, t));
				t := t + (s * {DTR, RTS});	(* modify only bits 0 & 1 *)
				SYSTEM.PORTOUT(baseaddr + MCR, SYSTEM.VAL(CHAR, t))
			END;
			IF Break IN s THEN
				SYSTEM.PORTIN(baseaddr + LCR, SYSTEM.VAL(CHAR, t));
				INCL(t, 6);	(* break on *)
				SYSTEM.PORTOUT(baseaddr + LCR, SYSTEM.VAL(CHAR, t))
			END
		END SetMC;

		(** Return the state of the specified modem control lines.  s contains the current state of DSR, CTS, RI, DCD & Break Interrupt. *)
		PROCEDURE GetMC*(VAR s: SET);
		VAR t: SET;
		BEGIN {EXCLUSIVE}
			s := {};
			SYSTEM.PORTIN(baseaddr + MSR, SYSTEM.VAL(CHAR, t));	(* note: this clears bits 0-3 *)
			IF 4 IN t THEN INCL(s, CTS) END;
			IF 5 IN t THEN INCL(s, DSR) END;
			IF 6 IN t THEN INCL(s, RI) END;
			IF 7 IN t THEN INCL(s, DCD) END;
			SYSTEM.PORTIN(baseaddr + LSR, SYSTEM.VAL(CHAR, t));	(* note: this clears bits 1-4 *)
			IF 4 IN t THEN INCL(s, Break) END
		END GetMC;

		PROCEDURE Close*;
		VAR s: SET;
		BEGIN {EXCLUSIVE}
			IF ~open THEN
				IF Verbose THEN ShowModule; AosOut.String(name); AosOut.String(" not open"); AosOut.Ln; END;
				RETURN
			END;
			REPEAT	(* wait for last byte to leave *)
				SYSTEM.PORTIN(baseaddr+LSR, SYSTEM.VAL(CHAR, s))
			UNTIL 6 IN s;	(* No remaining word in the FIFO or transmit shift register *)
			tail := -1;	(* Force a pending Receive to terminate in error. *)
			(* disable interrupts *)
			SYSTEM.PORTOUT(baseaddr + IER, 0X);
			(* remove interrupt handler *)
			AosActive.RemoveHandler(HandleInterrupt, AosInterrupts.IRQ0 + irq);
			open := FALSE;
			IF Verbose THEN ShowModule; AosOut.String(name); AosOut.String(" closed"); AosOut.Ln; END;
		END Close;

	END RS232Port;
	
PROCEDURE ReadICR(baseaddr, index: LONGINT): CHAR;
	CONST SPR = 7; ICR = 5; ICREnable = 6;
	VAR ch: CHAR;
BEGIN
	SYSTEM.PORTOUT(baseaddr + SPR, 0X);
	SYSTEM.PORTOUT(baseaddr + ICR, SYSTEM.VAL(CHAR, {ICREnable}));
	SYSTEM.PORTOUT(baseaddr + SPR, CHR(index));
	SYSTEM.PORTIN(baseaddr + ICR, ch);
	SYSTEM.PORTOUT(baseaddr + SPR, 0X);
	SYSTEM.PORTOUT(baseaddr + ICR, 0X);
	RETURN ch
END ReadICR;

PROCEDURE WriteICR(baseaddr, index: LONGINT; ch: CHAR);
	CONST SPR = 7; ICR = 5;
BEGIN
	SYSTEM.PORTOUT(baseaddr + SPR, CHR(index));
	SYSTEM.PORTOUT(baseaddr + ICR, ch)
END WriteICR;

PROCEDURE CheckOX16PCI954(baseaddr: LONGINT): BOOLEAN;
	CONST ID1 = 8; ID2 = 9; ID3 = 10; REV = 11;
BEGIN
	RETURN (baseaddr >= 1000H) & (ReadICR(baseaddr, ID1) = 016X) & (ReadICR(baseaddr, ID2) = 0C9X) &
		(ReadICR(baseaddr, ID3) = 050X) & (ReadICR(baseaddr, REV) = 001X)
END CheckOX16PCI954;

PROCEDURE ShowModule;
BEGIN
	AosOut.String(ModuleName); AosOut.String(": ");
END ShowModule;

(** Scan the installed serial ports and determine the chip type used *)
PROCEDURE Scan*(par: PTR): PTR;
VAR i: LONGINT; port: RS232Port; serialPort : AosSerials.Port; portstatus: SET; found : BOOLEAN;

	PROCEDURE DetectChip(baseaddr: LONGINT);
	VAR ch: CHAR;
	BEGIN
		AosOut.String("  Detected UART  ");
		SYSTEM.PORTOUT(baseaddr + FCR, 0C1X);	(* See if one can activate the FIFO *)
		SYSTEM.PORTIN(baseaddr + IIR, ch);	(* Read how the chip responded in the 2 most significant bits of IIR *)
		SYSTEM.PORTOUT(baseaddr + FCR, 00X);	(* Deactivate the FIFO *)
		CASE ASH(ORD(ch), -6) OF
		   0:  SYSTEM.PORTOUT(baseaddr + SCR, 0FAX);	(* See if one can write in the SCR *)
				SYSTEM.PORTIN(baseaddr + SCR, ch);
				IF ch = 0FAX THEN
					SYSTEM.PORTOUT(baseaddr + SCR, 0AFX);
					SYSTEM.PORTIN(baseaddr + SCR, ch);
					IF ch = 0AFX THEN
						AosOut.String("16450, 8250A")
					ELSE
						AosOut.String("8250, 8250-B, (has flaws)")
					END
				ELSE	(* No SCR present *)
					AosOut.String("8250, 8250-B, (has flaws)")
				END
		| 1: AosOut.String("Unknown chip")
		| 2: AosOut.String("16550, non-buffered (has flaws)")
		| 3: IF CheckOX16PCI954(baseaddr) THEN
					AosOut.String("OX16PCI954")
				ELSE
					AosOut.String("16550A, buffer operational")
				END
		END
	END DetectChip;

BEGIN
	ShowModule; AosOut.String("Serial port detection and inspection:"); AosOut.Ln;
	found := FALSE;
	FOR i := 1 TO AosSerials.MaxPorts DO
		serialPort := AosSerials.GetPort(i);
		IF (serialPort # NIL) & (serialPort IS RS232Port) THEN
			port := serialPort (RS232Port); found := TRUE;
			IF port.baseaddr # 0 THEN (* Port has a valid base address *)
				AosOut.String(port.name); AosOut.String(": "); AosOut.Hex(port.baseaddr, 10); AosOut.Char("H"); AosOut.Int(port.irq, 4);
				DetectChip(port.baseaddr);
				port.GetMC(portstatus);
				IF CTS IN portstatus THEN AosOut.String(" - CTS signals the presence of a DCE / Modem") END;
				AosOut.Ln
			END
		END;
	END;
	IF ~found THEN AosOut.String("No COM port found."); AosOut.Ln; END;
	RETURN NIL
END Scan;

(** Set the essential port operating parameters as specified in Aos.Par
		If omitted, default standard values are assigned to COM1 and COM2 *)
PROCEDURE Install*(ptr: PTR): PTR;
VAR i, p : LONGINT; name, s: ARRAY 16 OF CHAR; BASE, IRQ: LONGINT; port : RS232Port;
BEGIN
	FOR i := 0 TO MaxPortNo-1 DO
		COPY("COM ", name);
		name[3] := CHR(ORD("1") + i);
		AosBoot.GetConfig(name, s);
		p := 0;
		BASE := AosBoot.StrToInt(p, s);
		IF s[p] = "," THEN
			INC(p); IRQ := AosBoot.StrToInt(p, s)
		END;
		IF (i = 0) & (BASE = 0) THEN BASE := 3F8H; IRQ := 4 END;	(* COM1 port default values *)
		IF (i = 1) & (BASE = 0) THEN BASE := 2F8H; IRQ := 3 END;	(* COM2 port default values *)
		IF BASE # 0 THEN
			NEW(port, BASE, IRQ);

			(* Check the presence of a UART at the specified base address *)
			SYSTEM.PORTIN(port.baseaddr + MCR, s[0]);
			IF ORD(s[0]) < 32 THEN	(* Bits 7..5 of the MCR are always 0 when a UART is present *)
				(* Register this RS232Port with an identical index in AosSerials.registeredSerials array *)
				AosSerials.RegisterOnboardPort (i+1, port, name, "Onboard UART");	
			ELSE
				ShowModule; AosOut.String("No UART present at address specified for ");
				AosOut.String(name);
				AosOut.Ln
			END
		END
	END;
	RETURN NIL
END Install;

END AosV24.

AosV24.Install ~		S.Free AosV24 ~
AosV24.Scan ~

Example Aos.Par information (typical values usually assigned to the 4 first serial ports)

  COM1="3F8H,4"
  COM2="2F8H,3"
  COM3="3E8H,6"
  COM4="2E8H,9"
~

In Bluebottle, the generalization of the serial port support lead to the following adjustments:

New low-level module

AosV24.Mod -> AosV24.Obx is completely new.
	A new object-oriented driver supporting up to 8 serial ports (COM1 .. COM8) at speeds up to
	115'200 BPS. No longer compatible with ETH Native Oberon.

	The I/O base address and the IRQ corresponding to each COM port must be declared in Aos.Par,
	which contains configuration data, except that COM1 and COM2 are declared by default
	with their standard values, as used on most machines
		COM1="3F8H,4"
		COM2="2F8H,3"
	These two ports must be declared only in the case that the indicated standard do not apply.
	Bluebottle operates in 32-bit addressing mode and it is not possible to interrogate the base address
	by accessing the port directly in BIOS.
	
	The port information is registered in the order of appearance in Aos.Par and the ports are:
	- named from the user's viewpoint starting from COM1 by name and 1 by number and
	- numbered internally starting from 0

	The module includes the facilities
	- to verify that the ports declared in Aos.Par exist effectively
	- to determine the UART chip type used by the ports
	- to detect the presence of a modem
	- to trace the data stream (in the next update round)
	Error detection and handling during the reception have been improved, but the reception is
	not error prone anyway.

Very low-level module using a serial port

AosOut.Mod -> AosOut.Obx
	Offers the possibility of tracing the boot process on another machine connected via a serial port
	without the assistance of any other V24 support mentioned in this context.
	Like AosV24.Mod, it collects the base address of the available serial ports from Aos.Par
	and the port is selected from this list by reading the TracePort value in Aos.Par
	In the original version the port base address was hard-coded in the module.
	The module produces only an outgoing data stream.

Modified low-level module

Aos.V24.Mod -> V24.Obx
	In the earlier Bluebottle versions, this module offered the low-level serial port support.
	It is now an application module exploiting AosV24.Obx. Consequently, it is much simpler
	although it offers all the functionality of its predecessor.
	Backward compatibility with the original version is thus provided for client modules.
	New developments should avoid using it and make use of the enhanced AosV24.Obx.
