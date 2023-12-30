MODULE AosUsbRS232;  (** AUTHOR "staubesv"; PURPOSE "MCT USB-RS232 Converter Driver"; *)
(**
 *	This module implements a AosSerials.Port object. It is a Linux port of mct-u232.c, mct-u232.h.
 *
 * Usage:
 *
 *	AosUsbRS232.Install ~ loads this driver
 *	S.Free AosUsbRS232 ~ 
 *
 * Status: BETA
 *
 * Licence: GPL
 *	
 * References: 
 
 *	mct_u232.c Linux USB device driver
 *	mct-u232.h contains some documentation 
 *
 * History:
 *
 *	20.01.2006	First Release (staubesv)
 *	14.06.2006	Adapted to changes in AosSerials.Mod (staubesv)
 *	05.07.2006	Adapted to AosUsbdi (staubesv)
 *	05.01.2007	Introduced Port.Send procedure for better performance (staubesv)
 *
 * Todo:
 *	- Cleanup mess with constants
 *	- testing
 *)

IMPORT SYSTEM, AosKernel, AosOut, AosModules, AosSerials, AosUsbdi;

CONST

	Name = "UsbRs232";	
	Description = "USB-RS232 Interface Converter Driver";
	Priority = 0; 
	
	BufSize = 1024;
		
	TraceSend = {0};				(* Display sent characters *)
	TraceReceive = {1};			(* Display received characters *)
	TraceCommands = {2};
	TraceReceiveData = {3};
	TraceReceiveStatus = {4};
	TraceAll = {0..31};
	TraceNone = {};
	
	Trace = TraceNone;

	Debug = TRUE;
	Verbose = TRUE;
	
	ModuleName = "AosUsbRS232";

	(* Expected endpoints *)
	EpBulkOut = 02H; 			(* Used to send data *)
	EpInterruptInData = 082H; 	(* Used to receive data *)
	EpInterruptInStatus = 081H; 	(* Signals exception conditions *)
	
	IdVendorMct = 0711H; 		(* Magic Control Technology *)
	IdProductU232P9 = 230H; 	(* MCT U232-P9 *)
	IdProductU232P25 = 210H; 	(* MCT U232-P25 *)
	IdProductDUH3SP = 200H;	(* D-Link DU-H3SP USB Bay *)
	
	IdVendorBelkin = 50DH; 		(* Belkin *)
	IdProductF5U109 = 109H; 	(* Belkin F5U109 *)
	
	(* Vendor specific requests *)
	MctGetModemStatus = 2; 	(* Get modem status register (MSR) *)
	MctSetBaudrate = 5; 		(* Set baudrate divisor *)
	MctGetLineCtrl = 6; 			(* Get line control register (LCR) *)
	MctSetLineCtrl = 7; 			(* Set line control register (LCR) *)
	MctSetModemCtrl = 10; 		(* Set modem control register (MCR)*)
	MctSetUnknown1 = 11; 		(* Both requests are sent after SetBaudrate requests by windows driver *)
	MctSetUnknown2 = 12;
	
	(* line control register (LCR) *)
	MctLcrSetBreak = 6;
	MctData5 = {};
	MctData6 = {0};
	MctData7 = {1};
	MctData8 = {0,1};
	MctParityNone = {};
	MctParityEven = {3, 4};
	MctParityOdd = {3};
	MctParityMark = {3, 5};
	MctParitySpace = {3,4,5};
	MctStop1= {};
	MctStop2 = {2}; (* 1.5 stop bits for 5 data bits, 2 stop bits for 6, 7 & 8 data bits *)
	
	(* Modem control register (MCR) *)
	MctMcrRts = 1; 		(* Activate RTS *)
	MctMcrDtr = 0; 		(* Activate DTR *)
	MctMcrOut2 = 3; 	(* Activate Out2 *)
	
	(* Modem status register (MSR) *)
	MctMsrCd = 7; 		(* current CD *)
	MctMsrRi = 6; 		(* current RI *)
	MctMsrDsr = 5;		(* current DSR *)
	MctMsrCts = 4; 		(* current CTS *)
	MctMsrDcd = 3; 		(* delta CD, unused *)
	MctMsrDri = 2; 		(* delta RI, unused *)
	MctMsrDdsr = 1; 	(* delta DSR, unused *)
	MctMsrDcts = 0; 	(* delta CTS, unused *)
	
	(* Line status register (LSR) *)
	MctLsrErr = 7; 		(*  PE / FE / BI, unused *)
	MctLsrTemt = 6; 		(* transmit register empty *)
	MctLsrThre = 5; 		(* transmit holding register empty *)
	MctLsrBi = 4; 		(* break indicator *)
	MctLsrFe = 3; 		(* framing error *)
	MctLsrPe = 2; 		(* parity error *)
	MctLsrOe = 1; 		(* overrun error *)
	MctLsrDr = 0; 		(* receive data ready *)
	
TYPE

	UsbRs232Driver = OBJECT (AosUsbdi.Driver)
	VAR
		port : Port;
		controlPipe : AosUsbdi.Pipe;
		interruptInData, interruptInStatus : AosUsbdi.Pipe;
		bulkOut : AosUsbdi.Pipe;
		data1, data4, data64 : AosUsbdi.BufferPtr; (* datax -> ARRAY x OF CHAR *)
		status2 : AosUsbdi.BufferPtr;
		diagnostics : SET;
		msr : SET; (* Modem Status Register: Updated by UpdateStatus() & GetMSR *)
		lsr : SET;   (* Line Status Register: Updated by UpdateStatus() *)
		mcr : SET; (* Modem Control Register *)
		lcr : SET;   (* Line Control Register *)
		mc : SET; (*  AosSerials.DTR, AosSerials.RTS, AosSerials.DSR, AosSerials.CTS, AosSerials.RI, AosSerials.DCD & AosSerials.BI (Break Interrupt) *)
			
		PROCEDURE Connect*() : BOOLEAN;
		VAR ignore : AosUsbdi.Status;
		BEGIN
			(* Get default control pipe *)
			controlPipe := device.GetPipe(0); 
			IF controlPipe = NIL THEN 
				IF Debug THEN ShowModule("Couldn't get default control pipe."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			(* Get both interrupt pipes *)
			interruptInData := device.GetPipe(EpInterruptInData);
			interruptInStatus := device.GetPipe(EpInterruptInStatus);
			IF (interruptInData = NIL) OR (interruptInStatus = NIL) THEN
				IF Debug THEN ShowModule("Couldn't get interrupt in pipes."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			(* Get bulk out pipe *)
			bulkOut := device.GetPipe(EpBulkOut);
			IF bulkOut = NIL THEN 
				IF Debug THEN ShowModule("Couldn't get bulk out pipe."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			(* the interrupt pipe for endpoint EpInterruptStatus is used to asynchronously receive status information... set up the USB transfers. *)
			interruptInStatus.SetTimeout(0);
			interruptInStatus.SetCompletionHandler(UpdateStatus);
			ignore := interruptInStatus.Transfer(2, 0, status2^);
			
			interruptInData.SetTimeout(0);
			interruptInData.SetCompletionHandler(UpdateData);
			ignore := interruptInData.Transfer(64, 0, data64^);
			
			(* Get Modem Status Register (MSR) *)
			IF ~GetMSR(msr) THEN 
				IF Debug THEN ShowModule("GetMSR failed during connect."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			(* Register port at AosSerials *)
			NEW(port); NEW(port.data1, 1); port.driver := SELF;
			AosSerials.RegisterPort(port, Description); 
			RETURN TRUE;
		END Connect;
	
		PROCEDURE Disconnect*;
		BEGIN
			AosSerials.UnRegisterPort(SELF.port); 
		END Disconnect;
		
		(* Interrupt on Completion - Handler for EpInterruptInData; data contained in variable data64 *)
		PROCEDURE UpdateData(status : AosUsbdi.Status; actLen : LONGINT);
		VAR ignore : AosUsbdi.Status; i : LONGINT;
		BEGIN
			IF Trace * TraceReceiveData # {} THEN 
				ShowModule("UpdateData: Received "); AosOut.Int(actLen, 0); AosOut.String(" Bytes:"); 
				FOR i := 0 TO actLen - 1 DO AosOut.Char(" "); AosOut.Int(ORD(data64[i]), 0); END;
				AosOut.Ln; 
			END;
			IF (status = AosUsbdi.Ok) OR (status = AosUsbdi.ShortPacket) THEN
				port.HandleData(data64^, actLen);
				ignore := interruptInData.Transfer(64, 0, data64^);
			ELSE
				IF Debug THEN ShowModule("UpdateData failed."); AosOut.Ln; END;
			END;
		END UpdateData;
		
		(* Interrupt on Completion - Handler for EpInterruptInStatus; data contained in variable status2 *)
		PROCEDURE UpdateStatus(status : AosUsbdi.Status; actLen : LONGINT);
		VAR ignore : AosUsbdi.Status;
		BEGIN
			IF Trace * TraceReceiveStatus # {} THEN ShowModule("UpdateStatus: Received "); AosOut.Int(actLen, 0); AosOut.String(" Bytes: ");  END;
			IF (status = AosUsbdi.Ok) OR (status = AosUsbdi.ShortPacket) THEN
				IF actLen>=1 THEN
					msr := SYSTEM.VAL(SET, status2[0]); (* status2[0] is the MSR *)
					IF MctMsrRi IN msr THEN INCL(mc, AosSerials.RI); ELSE EXCL(mc, AosSerials.RI); END;
					IF MctMsrDsr IN msr THEN INCL(mc, AosSerials.DSR); ELSE EXCL(mc, AosSerials.DSR); END;
					IF MctMsrCts IN msr THEN INCL(mc, AosSerials.CTS); ELSE EXCL(mc, AosSerials.CTS); END;
					IF MctMsrCd IN msr THEN INCL(mc,  AosSerials.DCD); ELSE EXCL(mc, AosSerials.DCD); END;
					IF Trace * TraceReceiveStatus # {} THEN
						IF AosSerials.RI IN mc THEN AosOut.String("[RI]"); END;
						IF AosSerials.DSR IN mc THEN AosOut.String("[DSR]"); END;
						IF AosSerials.CTS IN mc THEN AosOut.String("[CTS]"); END;
						IF AosSerials.DCD IN mc THEN AosOut.String("[DCD]"); END;
					END;
				END;
				IF actLen>=2 THEN (* okay... I was expecting 2 bytes of data *)
					lsr := SYSTEM.VAL(SET, status2[1]); (* status2[1] is the LSR *)
					diagnostics := {};
					IF MctLsrOe IN lsr THEN INCL(diagnostics, AosSerials.OverrunError); END;
					IF MctLsrPe IN lsr THEN INCL(diagnostics, AosSerials.ParityError); END;
					IF MctLsrFe IN lsr THEN INCL(diagnostics, AosSerials.FramingError); END;
					IF MctLsrBi IN lsr THEN 
						INCL(mc, AosSerials.BreakInterrupt); INCL(diagnostics, AosSerials.BreakInterrupt);
					ELSE 
						EXCL(mc, AosSerials.BreakInterrupt);
					END;
					IF Trace * TraceReceiveStatus # {} THEN
						IF AosSerials.BreakInterrupt IN mc THEN AosOut.String("[BI]"); END;
						AosOut.String(" Errors: ");
						IF diagnostics = {} THEN AosOut.String("none");
						ELSE
							IF AosSerials.OverrunError IN diagnostics THEN AosOut.String("[Overrun]"); END;
							IF AosSerials.ParityError IN diagnostics THEN AosOut.String("[Parity]"); END;
							IF AosSerials.FramingError IN diagnostics THEN AosOut.String("[Framing]"); END;
							IF AosSerials.BreakInterrupt IN diagnostics THEN AosOut.String("BreakInterrupt]"); END;
						END;
					END;
				END;					
				ignore := interruptInStatus.Transfer(2, 0, status2^);
			ELSE
				IF Debug THEN ShowModule("UpdateStatus failed."); AosOut.Ln; END;
			END;
			IF Trace * TraceReceiveStatus # {} THEN AosOut.Ln; END;
		END UpdateStatus;
		
		(* Set baudrate divisor; returns TRUE if operation succeeded, FALSE otherwise *)
		PROCEDURE SetBaudrate(baudrate : LONGINT) : BOOLEAN;
		VAR divisor : LONGINT; status : AosUsbdi.Status;
		BEGIN
			IF Trace * TraceCommands # {} THEN ShowModule("SetBaudrate to "); AosOut.Int(baudrate, 0); AosOut.String(" bps."); AosOut.Ln; END;
			port.portbps := 0; (* indicates invalid value *)
			
			IF ((device.descriptor.idVendor = IdVendorMct) & (device.descriptor.idProduct = IdProductU232P25)) OR 
			   ((device.descriptor.idVendor = IdVendorMct) & (device.descriptor.idProduct = IdProductU232P9)) THEN (* use one-byte coded value ... *)
				IF baudrate = 300 THEN divisor := 01H
				ELSIF baudrate = 600 THEN divisor := 02H; 
				ELSIF baudrate = 1200 THEN divisor := 03H; 
				ELSIF baudrate = 2400 THEN divisor := 04H;
				ELSIF baudrate = 4800 THEN divisor := 06H;
				ELSIF baudrate = 9600 THEN divisor := 08H;
				ELSIF baudrate = 19200 THEN divisor := 09H;
				ELSIF baudrate = 38400 THEN divisor := 0AH;
				ELSIF baudrate = 57600 THEN divisor := 0BH; 
				ELSIF baudrate = 115200 THEN divisor := 0CH;   
				ELSE
					IF Debug THEN ShowModule("SetBaudrate: Wrong baud rate selected."); AosOut.Ln; END;
					RETURN FALSE; 
				END;	
				
				data1[0] := CHR(divisor);
				status := device.Request(AosUsbdi.ToDevice + AosUsbdi.Vendor + AosUsbdi.Device, MctSetBaudrate, 0, 0, 1, data1^);

			ELSE (* standart UART way ... *)
				IF (115200 MOD baudrate) # 0 THEN 
					IF Debug THEN ShowModule("SetBaudrate: Wrong baud rate selected."); AosOut.Ln; END;
					RETURN FALSE;
				ELSE
					divisor := 115200 DIV baudrate;
				END;  

				data4[0] := CHR(divisor);
				data4[1] := CHR(SYSTEM.LSH(divisor, -8));
				data4[2] := CHR(SYSTEM.LSH(divisor, -16));
				data4[3] := CHR(SYSTEM.LSH(divisor, -24));				
				status := device.Request(AosUsbdi.ToDevice + AosUsbdi.Vendor + AosUsbdi.Device, MctSetBaudrate, 0, 0, 4, data4^);
			END;
									
			IF status # AosUsbdi.Ok THEN 
				IF Debug THEN ShowModule("SetBaudrate failed (MctSetBaudrate)"); AosOut.Ln; END;
				RETURN FALSE;
			END; 
			
			(* don't known what the following two vendor-specific requests are good for ... just imitating the windows driver *)
			data1[0] := CHR(0);
			
			status := device.Request(AosUsbdi.ToDevice + AosUsbdi.Vendor + AosUsbdi.Device, MctSetUnknown1, 0, 0, 1, data1^);
			IF status # AosUsbdi.Ok THEN 
				IF Debug THEN ShowModule("SetBaudrate failed (MctSetUnknown1). "); AosOut.Ln; END;
				RETURN FALSE;
			END;
		
			status := device.Request(AosUsbdi.ToDevice + AosUsbdi.Vendor + AosUsbdi.Device, MctSetUnknown2, 0, 0, 1, data1^);
			IF status # AosUsbdi.Ok THEN 
				IF Debug THEN ShowModule("SetBaudrate failed (MctSetUnknown1). "); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			port.portbps := baudrate;
			RETURN TRUE;
		END SetBaudrate;
		
		(* Vendor-specific request: Used to set the Line Control Register (LCR) *)
		PROCEDURE SetLCR(set : SET) : BOOLEAN;
		VAR status : AosUsbdi.Status;
		BEGIN
			data1[0] := SYSTEM.VAL(CHAR, set);
			status := device.Request(AosUsbdi.ToDevice + AosUsbdi.Vendor + AosUsbdi.Device, MctSetLineCtrl, 0, 0, 1, data1^);
			IF status # AosUsbdi.Ok THEN 
				IF Debug THEN ShowModule("SetLCR failed."); AosOut.Ln; END;
				RETURN FALSE;
			ELSE
				lcr := set;
				RETURN TRUE;
			END;
		END SetLCR;

		(* vendor-specific request: Used to get the Line Control Register (LCR) *)
		PROCEDURE GetLCR(VAR lcr : SET) : BOOLEAN;
		VAR status : AosUsbdi.Status;
		BEGIN
			status := device.Request(AosUsbdi.ToHost + AosUsbdi.Vendor + AosUsbdi.Device, MctGetLineCtrl, 0, 0, 1, data1^);
			IF status # AosUsbdi.Ok THEN 
				IF Debug THEN ShowModule("GetLCR failed."); AosOut.Ln; END;
				RETURN FALSE;
			ELSE
				lcr := SYSTEM.VAL(SET, data1[0]);
				RETURN TRUE;
			END;
		END GetLCR;
		
		(* Vendor-specific request: used to set RTS & DTR Bits of the Modem Control Register (MCR) *)
		(* Updates DTR&RTS in mc *)
		PROCEDURE SetMCR(set : SET) : BOOLEAN;
		VAR status : AosUsbdi.Status;
		BEGIN
			IF AosSerials.DTR IN set THEN INCL(mcr, MctMcrDtr); ELSE EXCL(mcr, MctMcrDtr); END;
			IF AosSerials.RTS IN set THEN INCL(mcr, MctMcrRts); ELSE EXCL(mcr, MctMcrRts); END;
			INCL(mcr, MctMcrOut2); (* Always enable Out2 *) 
			
			data1[0] := CHR(SYSTEM.VAL(LONGINT, mcr));
			
			status := device.Request(AosUsbdi.ToDevice + AosUsbdi.Vendor + AosUsbdi.Device, MctSetModemCtrl, 0, 0, 1, data1^);
			IF status # AosUsbdi.Ok THEN 
				IF Debug THEN ShowModule("SetMCR failed: "); AosOut.Ln; END;
				RETURN FALSE;
			ELSE
				IF AosSerials.DTR IN set THEN INCL(mc, AosSerials.DTR) ELSE EXCL(mc, AosSerials.DTR) END;
				IF AosSerials.RTS IN set THEN INCL(mc, AosSerials.RTS) ELSE EXCL (mc, AosSerials.RTS) END;
				RETURN TRUE;
			END;	
		END SetMCR;
				
		(* Updates the msr & mc variable *)
		PROCEDURE GetMSR(VAR value : SET) : BOOLEAN;
		VAR status : AosUsbdi.Status;
		BEGIN
			status := device.Request(AosUsbdi.ToHost + AosUsbdi.Vendor + AosUsbdi.Device, MctGetModemStatus, 0, 0, 1, data1^);
			IF status # AosUsbdi.Ok THEN 
				IF Debug THEN ShowModule("GetMSR failed."); AosOut.Ln; END;
				RETURN FALSE;
			ELSE
				IF Trace * TraceCommands # {} THEN ShowModule("GetMSR succeeded (value: "); AosOut.Bits(SYSTEM.VAL(SET, data1[0]), 0, 8); AosOut.String(")");  AosOut.Ln; END;
				msr := SYSTEM.VAL(SET, data1[0]);
				IF MctMsrRi IN msr THEN INCL(mc, AosSerials.RI); ELSE EXCL(mc, AosSerials.RI); END;
				IF MctMsrDsr IN msr THEN INCL(mc, AosSerials.DSR); ELSE EXCL(mc, AosSerials.DSR); END;
				IF MctMsrCts IN msr THEN INCL(mc, AosSerials.CTS); ELSE EXCL(mc, AosSerials.CTS);  END;
				IF MctMsrCd IN msr THEN INCL(mc, AosSerials.DCD); ELSE EXCL(mc, AosSerials.DCD); END;
				value := msr;
				RETURN TRUE;
			END;	
		END GetMSR;
		
		PROCEDURE &Init;
		BEGIN
			NEW(data1, 1); NEW(data4, 4); NEW(data64, 64); NEW(status2, 2);
			msr := {}; lsr := {}; mcr := {}; lcr := {};
		END Init;
		
	END UsbRs232Driver;
	
TYPE

	Port = OBJECT(AosSerials.Port)
	VAR
		driver : UsbRs232Driver;
		portbps : LONGINT;
		data1 : AosUsbdi.BufferPtr; (* datax -> ARRAY x OF CHAR *)
		buf: ARRAY BufSize OF CHAR;
		head, tail: LONGINT;
		open: BOOLEAN;
		diagnostic: LONGINT;

		PROCEDURE Open*(bps, data, parity, stop : LONGINT; VAR res: LONGINT);
		BEGIN {EXCLUSIVE}
			IF open THEN
				IF Verbose THEN ShowModule(name); AosOut.String(" already open"); AosOut.Ln; END;
				res := AosSerials.PortInUse; 
				RETURN; 
			END;
			SetPortState(bps, data, parity, stop, res);
			IF res = AosSerials.Ok THEN
				open := TRUE;
				head := 0; tail:= 0;
				IF Verbose THEN ShowModule(name); AosOut.String("opened"); AosOut.Ln; END;
			END
		END Open;
		
		(** Send len characters from buf to output, starting at ofs. res is non-zero on error. *)
		PROCEDURE Send*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		VAR status : AosUsbdi.Status;
		BEGIN {EXCLUSIVE}
			IF ~open THEN res := AosSerials.Closed; RETURN; END;
			IF Trace * TraceSend # {} THEN ShowModule("Sending "); AosOut.Int(len, 0); AosOut.String(" bytes"); AosOut.Ln; END;
			status := driver.bulkOut.Transfer(len, ofs, buf);
			IF status = AosUsbdi.Ok THEN
				res := AosSerials.Ok;
				charactersSent := charactersSent + len;
			ELSE
				res := AosSerials.TransportError;
				IF Debug THEN ShowModule("Transmission failed, res: "); AosOut.Int(status, 0); AosOut.Ln; END;
			END;
		END Send;

		(** Send a single character to the UART. *)
		PROCEDURE SendChar*(ch: CHAR; VAR res : LONGINT);
		VAR status : AosUsbdi.Status;
		BEGIN {EXCLUSIVE}
			IF ~open THEN res := AosSerials.Closed; RETURN; END;
			data1[0] := ch;
			IF Trace * TraceSend # {} THEN ShowModule("Sending character ORD: "); AosOut.Int(ORD(data1[0]), 0); AosOut.Ln; END;
			status := driver.bulkOut.Transfer(1, 0, data1^);
			IF status # AosUsbdi.Ok THEN
				res := AosSerials.Ok;
				INC(charactersSent);
			ELSE
				res := AosSerials.TransportError;
				IF Debug THEN ShowModule("Transmission of character failed."); AosOut.Ln; END;
			END;
		END SendChar;

		(** Wait for the next character is received in the input buffer. The buffer is fed by HandleData *)
		PROCEDURE ReceiveChar*(VAR ch: CHAR; VAR res: LONGINT);
		BEGIN {EXCLUSIVE}
			IF ~open THEN res := AosSerials.Closed; RETURN; END;
			AWAIT(tail # head);
			IF tail = -1 THEN
				res := AosSerials.Closed;
			ELSE
				ch := buf[head]; head := (head+1) MOD BufSize;
				res := diagnostic
			END 
		END ReceiveChar;

		(** On detecting an interupt request, transfer the characters from the UART buffer to the input buffer *)
		PROCEDURE HandleData(data :  AosUsbdi.Buffer; actLen : LONGINT);
		VAR n, i : LONGINT; 	ch : CHAR;
		BEGIN {EXCLUSIVE}
			charactersReceived := charactersReceived + actLen;
			i := 0;
			LOOP
				IF i >= actLen THEN EXIT; END;
				ch := data[i];
				n := (tail + 1) MOD BufSize;
				IF n # head THEN 
					buf[tail] := ch; tail := n 
				ELSE
					IF Debug THEN AosOut.String("Port: HandleData: Buffer overflow detected."); AosOut.Ln; END;
				END;
				INC(i);
				diagnostic := SYSTEM.VAL(LONGINT, driver.diagnostics); (* includes AosSerials.OE, AosSerials.PE, AosSerials.FE & AosSerials.BI *)
			END;
		END HandleData;

		PROCEDURE Available*(): LONGINT;
		BEGIN {EXCLUSIVE}
			RETURN (tail - head) MOD BufSize 
		END Available;

		PROCEDURE SetPortState(bps, data, parity, stop : LONGINT; VAR res: LONGINT);
		VAR s : SET;
		BEGIN
			IF (bps > 0) & (115200 MOD bps = 0) THEN
			
				IF (data >= 5) & (data <= 8) & (parity >= AosSerials.ParNo) & (parity <= AosSerials.ParSpace) & (stop >= AosSerials.Stop1) & (stop <= AosSerials.Stop1dot5) THEN
					
					IF ~driver.SetBaudrate(bps) THEN
						res := AosSerials.WrongBPS; RETURN;
					END;

					(* Prepare parameters destined to LCR data, stop, parity *)
					CASE data OF	(* word length *)
						   5: s := MctData5;
						| 6: s := MctData6;
						| 7: s := MctData7;
						| 8: s := MctData8;
					END;
															
					CASE parity OF
						   AosSerials.ParNo: 		s := s + MctParityNone;
						| AosSerials.ParOdd: 	s := s + MctParityOdd;
						| AosSerials.ParEven: 	s := s + MctParityEven;
						| AosSerials.ParMark: 	s := s + MctParityMark;
						| AosSerials.ParSpace: 	s := s + MctParitySpace;
					END;
					
					IF (stop = AosSerials.Stop1dot5) & (data # 5) THEN res := AosSerials.WrongStop; RETURN; END;					
					IF stop # AosSerials.Stop1 THEN s := s + MctStop2;  END;
										
					(* Finalize the LCR *)
					IF ~driver.SetLCR(s) THEN
						res := AosSerials.WrongData;RETURN;
					END;
					
					(* Set DTR, RTS in the MCR *)
					s := {}; INCL(s, AosSerials.DTR); INCL(s, AosSerials.RTS); 
					IF ~driver.SetMCR(s) THEN
						res := AosSerials.WrongData; RETURN;
					END;
					res := AosSerials.Ok
				ELSE 
					res := AosSerials.WrongData (* bad data/parity/stop *)
				END
			ELSE 
				res := AosSerials.WrongBPS (* bad BPS *)
			END;
		END SetPortState;

		(** Get the port state: speed, no. of data bits, parity, no. of stop bits *)
		PROCEDURE GetPortState*(VAR openstat : BOOLEAN; VAR bps, data, parity, stop : LONGINT);
		VAR set : SET; res : BOOLEAN;
		BEGIN 
			(* get parameters *)
			openstat := open;			
			bps := portbps;
			
			res := driver.GetLCR(set);
			IF set * {0, 1} = MctData8 THEN data := 8;
			ELSIF set * {0, 1} = MctData7 THEN data := 7;
			ELSIF set * {0, 1} = MctData6 THEN data := 6;
			ELSE data := 5;
			END;
			
			IF set * MctStop2 # {} THEN
				IF set * {0, 1} = MctData5 THEN stop := AosSerials.Stop1dot5; 	ELSE stop := AosSerials.Stop2; END;
			ELSE 
				stop := AosSerials.Stop1;
			END;
			
			IF set * {3..5} = MctParitySpace THEN parity := AosSerials.ParSpace;
			ELSIF set * {3..5} = MctParityMark THEN parity := AosSerials.ParMark;
			ELSIF set * {3..5} = MctParityEven THEN parity := AosSerials.ParEven;
			ELSIF set * {3..5} = MctParityOdd THEN parity := AosSerials.ParOdd;
			ELSE parity := AosSerials.ParNo;
			END; 
			IF Trace * TraceCommands # {} THEN 
				ShowModule("GetPortState of port "); AosOut.String(name); AosOut.String(":");
				IF res THEN 
					AosOut.String(" State: "); IF open THEN AosOut.String("Open"); ELSE AosOut.String("Closed"); END;
					AosOut.String(" DataBits: "); AosOut.Int(data, 0); 
					AosOut.String(" StopBits: "); IF stop=3 THEN AosOut.String("1.5"); ELSE AosOut.Int(stop, 0); END;
					AosOut.String(" Parity: ");
					CASE parity OF
						0 : AosOut.String("None");
						|1 : AosOut.String("Odd"); 
						|2 : AosOut.String("Even");
						|3 : AosOut.String("Mark");
						|4 : AosOut.String("Space");
					ELSE
						AosOut.String("Unknown");
					END;
					AosOut.String(" Bps: "); AosOut.Int(bps, 0); AosOut.Ln;
				ELSE
					AosOut.String("Status request failed."); AosOut.Ln;
				END;
			END;
		END GetPortState;

		(** ClearMC - Clear the specified modem control lines.  s may contain DTR, RTS & Break. *)
		PROCEDURE ClearMC*(s: SET);
		VAR  temp : SET; ignore : BOOLEAN;
		BEGIN {EXCLUSIVE}
			IF s * {AosSerials.DTR, AosSerials.RTS} # {} THEN
				temp := driver.mcr;
				IF s * {AosSerials.DTR} # {} THEN EXCL(temp, AosSerials.DTR); END;
				IF s * {AosSerials.RTS} # {} THEN EXCL(temp, AosSerials.RTS); END;
				ignore := driver.SetMCR(temp);				
			END;
			IF AosSerials.Break IN s THEN				
				ignore := driver.GetLCR(temp);
				EXCL(temp, AosSerials.Break);
				ignore := driver.SetLCR(temp);				
			END; 	
		END ClearMC;

		(** SetMC - Set the specified modem control lines.  s may contain DTR, RTS & Break. *)
		PROCEDURE SetMC*(s: SET);
		VAR ignore : BOOLEAN;
		BEGIN {EXCLUSIVE}	
			IF s * {AosSerials.DTR, AosSerials.RTS} # {} THEN ignore := driver.SetMCR(s * {AosSerials.DTR, AosSerials.RTS}); END;
			IF AosSerials.Break IN s THEN
				ignore := driver.SetLCR({AosSerials.Break});
			END; 
		END SetMC;

		(** GetMC - Return the state of the specified modem control lines. s contains the current state of DSR, CTS, RI, DCD & Break Interrupt. *)
		PROCEDURE GetMC*(VAR s: SET);
		BEGIN {EXCLUSIVE}
			s := driver.msr; (* Inlcudes CTS, DSR, RI, CD *)
			IF MctLsrBi IN driver.lsr THEN INCL(s, AosSerials.Break); END; 
		END GetMC;

		PROCEDURE Close*;
		VAR timer : AosKernel.Timer; counter : LONGINT;
		BEGIN {EXCLUSIVE}
			IF ~open THEN
				IF Verbose THEN ShowModule(name); AosOut.String(" not open"); AosOut.Ln; END;
				RETURN;
			ELSE
				IF ~(MctLsrTemt IN driver.lsr) THEN (* wait for last byte to leave *)
					NEW(timer); counter := 0;
					REPEAT	
						timer.Sleep(1);
						INC(counter);
					UNTIL (MctLsrTemt IN driver.lsr) OR (counter>100); (* No remaining word in the FIFO or transmit shift register *) 
				END;
				tail := -1; (* Force a pending Receive to terminate in error. *)
				open := FALSE;
				IF Verbose THEN ShowModule(name); AosOut.String(" closed"); AosOut.Ln END;
			END;
		END Close;
		
	END Port;

PROCEDURE ShowModule(string : ARRAY OF CHAR);
BEGIN
	AosOut.String(ModuleName); AosOut.String(": "); AosOut.String(string);
END ShowModule;

PROCEDURE Probe(dev : AosUsbdi.UsbDevice; id : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR driver : UsbRs232Driver;
BEGIN
	IF ((dev.descriptor.idVendor = IdVendorMct) & (dev.descriptor.idProduct = IdProductU232P9)) THEN (* MCT U232-P9 *)
	ELSIF ((dev.descriptor.idVendor = IdVendorMct) & (dev.descriptor.idProduct = IdProductU232P25)) THEN (* MCT U232-P25 *)		
	ELSIF ((dev.descriptor.idVendor = IdVendorMct) & (dev.descriptor.idProduct = IdProductDUH3SP)) THEN (* D-Link USB Bay *)
	ELSIF ((dev.descriptor.idVendor = IdVendorBelkin) & (dev.descriptor.idProduct = IdProductF5U109)) THEN (* Belkin F5U109 *)
	ELSE (* device not supported *)
		RETURN NIL; 
	END;
	NEW(driver);
	RETURN driver;
END Probe;
		
PROCEDURE Cleanup;
BEGIN
	AosUsbdi.drivers.Remove(Name);
END Cleanup;

PROCEDURE Install*(ptr : PTR): PTR;
BEGIN
	RETURN NIL;
END Install;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	AosUsbdi.drivers.Add(Probe, Name, Description, Priority)
END AosUsbRS232.

AosUsbRS232.Install ~   S.Free AosUsbRS232 ~