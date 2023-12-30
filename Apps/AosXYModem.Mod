MODULE AosXYModem; (** AUTHOR "ejz"; PURPOSE "X- and Y-Modem protocol implementation"; *)
(**
 * History:
 *
 *	25.09.2006	Introduced bytesProcessed, yield instead of busy waiting (staubesv)
 *	20.02.2007	Use AosKernel.MilliTimer instead of AosActive.ticks (staubesv)
 *)
 
IMPORT SYSTEM, AosActive, AosKernel, AosIO, AosFS, AosSerials, Utilities, AosCommands, AosOut;

CONST
	SOH = 01X; STX = 02X; EOT = 04X; ACK = 06X; EOF = 1AX; NAK = 15X; CAN = 18X; C = 43X;
	XModem* = 0; XModem1K* = 1; YModem* = 2;
	
	DoYield = TRUE;

TYPE

	Modem* = OBJECT
	VAR
		W: AosIO.Writer; R: AosIO.Reader;
		F: AosFS.File;
		mode: LONGINT; (* XModem, XModem1K, YModem *)
		timeout: LONGINT;
		data: ARRAY 1024 OF CHAR;
		error: ARRAY 64 OF CHAR;
		done, fail: BOOLEAN;
		
		bytesProcessed-, totalBytes- : LONGINT;

		PROCEDURE & Init*(W: AosIO.Writer; R: AosIO.Reader; F: AosFS.File; mode: LONGINT);
		BEGIN
			SELF.W := W; SELF.R := R;
			SELF.F := F; SELF.mode := mode; error := ""; done := FALSE
		END Init;
		
		PROCEDURE IsDone*() : BOOLEAN;
		BEGIN
			RETURN done;
		END IsDone;

		PROCEDURE Await*(VAR err: ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			AWAIT(done); COPY(error, err)
		END Await;

		PROCEDURE AwaitF*(VAR F: AosFS.File; VAR err: ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			ASSERT(mode = YModem);
			AWAIT(done);
			F := SELF.F; COPY(error, err)
		END AwaitF;

		PROCEDURE Stop();
		BEGIN {EXCLUSIVE}
			done := TRUE
		END Stop;

		PROCEDURE Read(VAR ch: CHAR): BOOLEAN;
		VAR n: LONGINT; milliTimer : AosKernel.MilliTimer;
		BEGIN
			AosKernel.SetTimer(milliTimer, timeout);
			REPEAT
				n := R.Available();
				IF DoYield & (n = 0) THEN AosActive.Yield; END;
			UNTIL (n > 0) OR AosKernel.Expired(milliTimer);
			IF n = 0 THEN
				error := "timeout"; ch := 0X; RETURN FALSE
			END;
			R.Char(ch); RETURN R.res = AosIO.Ok
		END Read;
		
	END Modem;
	
TYPE

	Sender* = OBJECT (Modem)
	
		PROCEDURE YHeader(): LONGINT;
		VAR name: AosFS.FileName; len, i, j: LONGINT; ch: CHAR;
		BEGIN
			F.GetName(name); len := F.Length();
			i := 0; j := 0; ch := name[0];
			WHILE ch # 0X DO
				IF ch = ":" THEN j := 0 ELSE data[j] := ch; INC(j) END;
				INC(i); ch := name[i]
			END;
			data[j] := 0X; INC(j);
			Utilities.IntToStr(len, name);
			i := 0; ch := name[0];
			WHILE ch # 0X DO
				data[j] := ch; INC(j); INC(i); ch := name[i]
			END;
			IF j < 128 THEN len := 128 ELSE len := 1024 END;
			ASSERT(j < len);
			WHILE j < len DO data[j] := 0X; INC(j) END;
			RETURN len
		END YHeader;

		PROCEDURE SendFile();
		VAR fR: AosFS.Reader; len, blkn, blk, i, retry: LONGINT; start, ch: CHAR;

			PROCEDURE SendData();
			VAR crc: LONGINT;
			BEGIN
				W.Char(start); W.Char(CHR(blk)); W.Char(CHR(255-blk));
				W.Bytes(data, 0, blkn); crc := CRC16(data, blkn);
				W.Char(CHR(crc DIV 256)); W.Char(CHR(crc MOD 256));
				W.Update();
				IF Read(ch) THEN
					IF ch # ACK THEN
						IF (ch = NAK) & (retry < 5) THEN
							INC(retry)
						ELSE
							fail := TRUE; error := "expected ACK"
						END
					ELSE
						blk := (blk + 1) MOD 256; retry := 0
					END
				ELSE
					fail := TRUE
				END
			END SendData;
			
		BEGIN
			timeout := 5000;
			i := 0; REPEAT INC(i) UNTIL Read(ch) OR (i > 10);
			IF ch = C THEN
				error := ""
			ELSIF ch # 0X THEN
				error := "expected C"; RETURN
			ELSE
				RETURN
			END;
			timeout := 10000;
			IF mode = YModem THEN
				IF YHeader() > 128 THEN start := STX; blkn := 1024 ELSE start := SOH; blkn := 128 END;
				blk := 0; SendData();
				IF ~(Read(ch) & (ch = C)) THEN error := "expected C"; RETURN END
			END;
			AosFS.OpenReader(fR, F, 0); len := F.Length(); totalBytes := len;
			fail := FALSE; retry := 0; blk := 1; start := STX; blkn := 1024;
			REPEAT
				IF retry = 0 THEN
					IF (mode = XModem) OR (len < (1024-128)) THEN start := SOH; blkn := 128 END;
					fR.Bytes(data, 0, blkn, i); DEC(len, blkn); INC(bytesProcessed, i);
					IF (fR.res # AosIO.Ok) OR (i < blkn) THEN
						WHILE i < blkn DO data[i] := EOF; INC(i) END
					END
				END;
				SendData();
			UNTIL (fR.res # AosIO.Ok) OR fail;
			IF ~fail THEN
				W.Char(EOT); W.Update();
				IF mode = YModem THEN
					IF Read(ch) & ((ch = ACK) OR (ch = NAK)) THEN
						W.Char(EOT); W.Update();
						IF Read(ch) & ((ch = ACK) OR (ch = C)) THEN
							IF (ch = C) OR (Read(ch) & (ch = C)) THEN
								start := SOH; blkn := 128; blk := 0;
								i := 0; WHILE i < blkn DO data[i] := 0X; INC(i) END;
								SendData()
							END
						END
					END
				ELSE
					IF Read(ch) & (ch = ACK) THEN END
				END
			ELSE
				W.Char(CAN); W.Update()
			END
		END SendFile;

	BEGIN {ACTIVE}
		SendFile(); Stop()
	END Sender;

	Receiver* = OBJECT (Modem)
	
		PROCEDURE YHeader(len: LONGINT; VAR name: ARRAY OF CHAR; VAR size: LONGINT);
		VAR i, j: LONGINT; str: ARRAY 12 OF CHAR; ch: CHAR;
		BEGIN
			size := MAX(LONGINT);
			i := 0; j := 0; ch := data[0];
			WHILE (i < len) & (ch # 0X) DO
				name[j] := ch; INC(j); INC(i); ch := data[i]
			END;
			name[j] := 0X; INC(i);
			IF (i < len) & IsDigit(data[i]) THEN
				j := 0; ch := data[i];
				WHILE (i < len) & IsDigit(data[i]) DO
					str[j] := ch; INC(j); INC(i); ch := data[i]
				END;
				str[j] := 0X; Utilities.StrToInt(str, size)
			END
		END YHeader;

		PROCEDURE ReceiveFile();
		VAR name: AosFS.FileName; fW: AosFS.Writer; len, blkn, i: LONGINT; ch, ch2: CHAR;
		
			PROCEDURE ReceiveData(): BOOLEAN;
			VAR len, crc, crcr: LONGINT;
			BEGIN
				R.Bytes(data, 0, blkn, len); fail := (R.res # AosIO.Ok) OR (len # blkn);
				IF ~fail THEN
					IF Read(ch) & Read(ch2) THEN
						crcr := 256*LONG(ORD(ch)) + LONG(ORD(ch2));
						crc := CRC16(data, blkn);
						IF crc = crcr THEN
							W.Char(ACK); W.Update(); i := (i + 1) MOD 256;
							RETURN TRUE
						ELSE
							W.Char(NAK); W.Update()
						END
					ELSE
						fail := TRUE
					END
				ELSE
					error := "receive data failed"
				END;
				RETURN FALSE
			END ReceiveData;
			
		BEGIN
			timeout := 5000;
			i := 0; REPEAT W.Char(C); W.Update(); INC(i) UNTIL Read(ch) OR (i > 10);
			IF ch # 0X THEN error := "" END; len := MAX(LONGINT);
			IF F # NIL THEN
				AosFS.OpenWriter(fW, F, 0)
			ELSIF mode # YModem THEN
				error := "invalid file handle"; RETURN
			ELSE
				fW := NIL
			END;
			timeout := 10000;
			fail := FALSE; i := 1;
			WHILE ~fail & ((ch = SOH) OR (ch = STX)) DO
				IF ch = SOH THEN blkn := 128 ELSIF ch = STX THEN blkn := 1024 END;
				IF Read(ch) & Read(ch2) THEN
					IF (i = ORD(ch)) & (ORD(ch) = (255-ORD(ch2))) THEN
						IF fW = NIL THEN
							W.Char(CAN); W.Update();
							error := "invalid file handle"; RETURN
						END;
						IF ReceiveData() THEN
							IF len < blkn THEN blkn := len END;
							fW.Bytes(data, 0, blkn); DEC(len, blkn);
							INC(bytesProcessed, blkn);
						END
					ELSIF (i = 1) & (ch = 0X) & (ch2 = 0FFX) & (mode = YModem) THEN
						IF ReceiveData() THEN
							YHeader(blkn, name, len); W.Char(C); W.Update();
							IF F = NIL THEN F := AosFS.New(name); AosFS.OpenWriter(fW, F, 0) END
						END;
						i := 1
					ELSE
						fail := TRUE; error := "wrong block number"
					END;
					IF ~fail THEN fail := ~Read(ch) END
				ELSE
					fail := TRUE
				END
			END;
			IF ~fail & ((ch = EOT) OR (ch = CAN)) THEN
				IF ch = EOT THEN
					IF mode = YModem THEN
						W.Char(NAK); W.Update();
						IF Read(ch) & (ch = EOT) THEN
							W.Char(ACK); W.Char(C); W.Update();
							IF Read(ch) & (ch = SOH) THEN
								IF Read(ch) & Read(ch2) THEN
									(* end of single file transfer *)
									ASSERT((ch = 0X) & (ch2 = 0FFX));
									blkn := 128; fail := ~ReceiveData();
									ASSERT(data[0] = 0X)
								END
							END
						END
					ELSE
						W.Char(ACK); W.Update()
					END;
					error := ""; fW.Update()
				ELSE
					W.Char(ACK); W.Update();
					error := "transfer aborted"
				END
			ELSE
				W.Char(CAN); W.Update();
				IF error = "" THEN error := "wrong block header" END
			END
		END ReceiveFile;

	BEGIN {ACTIVE}
		ReceiveFile(); Stop()
	END Receiver;

PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
BEGIN
	RETURN (ch >= "0") & (ch <= "9")
END IsDigit;

PROCEDURE CRC16(VAR buf: ARRAY OF CHAR; len: LONGINT): LONGINT;
VAR i, k, crc: LONGINT;
BEGIN
	crc := 0; i := 0;
	WHILE i < len DO
		crc := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, crc) / SYSTEM.VAL(SET, LONG(ORD(buf[i]))*LONG(100H)));
		k := 0;
		WHILE k < 8 DO
			IF (15 IN SYSTEM.VAL(SET, crc)) THEN
				crc := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, crc*2) / SYSTEM.VAL(SET, 1021H))
			ELSE
				crc := crc*2
			END;
			INC(k)
		END;
		INC(i)
	END;
	RETURN crc MOD 10000H
END CRC16;

PROCEDURE GetPars(par: PTR; VAR name: ARRAY OF CHAR; VAR port, bps, parity, stop: LONGINT): BOOLEAN;
VAR p: AosCommands.Parameters; R: AosIO.StringReader;
BEGIN
	port := 0; bps := 115200; parity := AosSerials.ParNo; stop := AosSerials.Stop1;
	p := par(AosCommands.Parameters);
	NEW(R, LEN(p.str)); R.Set(p.str^);
	R.SkipWhitespace(); R.String(name);
	IF IsDigit(name[0]) THEN
		Utilities.StrToInt(name, port);
		R.SkipWhitespace(); R.String(name);
		Utilities.StrToInt(name, bps);
		R.SkipWhitespace(); R.String(name);
		IF name = "odd" THEN
			parity := AosSerials.ParOdd
		ELSIF name = "even" THEN
			parity := AosSerials.ParEven
		ELSIF name = "mark" THEN
			parity := AosSerials.ParMark
		ELSIF name = "space" THEN
			parity := AosSerials.ParSpace
		ELSIF name # "no" THEN
			AosOut.String("wrong parity"); AosOut.Ln();
			RETURN FALSE
		END;
		R.SkipWhitespace(); R.String(name);
		IF name = "1.5" THEN
			stop := AosSerials.Stop1dot5
		ELSIF name = "2" THEN
			stop := AosSerials.Stop2
		ELSIF name # "1" THEN
			AosOut.String("wrong stop bits"); AosOut.Ln();
			RETURN FALSE
		END;
		R.SkipWhitespace(); R.String(name)
	END;
	RETURN TRUE
END GetPars;

PROCEDURE xySend(par: PTR; mode: LONGINT): PTR;
VAR
	name: AosFS.FileName; F: AosFS.File;
	port: AosSerials.Port; portn, bps, parity, stop, res: LONGINT;
	send: Sender; error: ARRAY 64 OF CHAR;
	W: AosIO.Writer; R: AosIO.Reader;
BEGIN
	IF GetPars(par, name, portn, bps, parity, stop) THEN
		AosOut.String(name); AosOut.Ln;
		F := AosFS.Old(name);

		port := AosSerials.GetPort(portn);
		ASSERT(port # NIL);
		port.Open(bps, 8, parity, stop, res);
		ASSERT(res = AosSerials.Ok);
		AosIO.OpenWriter(W, port.Send); AosIO.OpenReader(R, port.Receive);
		NEW(send, W, R, F, mode);
		send.Await(error);
		port.Close();

		IF error # "" THEN
			AosOut.String("  "); AosOut.String(error);
		ELSE
			AosOut.String("  done");
		END;
		AosOut.Ln;
	END;
	RETURN NIL
END xySend;

PROCEDURE XSend*(par: PTR): PTR;
BEGIN
	AosOut.String("XSend ");
	RETURN xySend(par, XModem)
END XSend;

PROCEDURE XSend1K*(par: PTR): PTR;
BEGIN
	AosOut.String("XSend1K ");
	RETURN xySend(par, XModem1K)
END XSend1K;

PROCEDURE YSend*(par: PTR): PTR;
BEGIN
	AosOut.String("YSend ");
	RETURN xySend(par, YModem)
END YSend;

PROCEDURE xyReceive(par: PTR; mode: LONGINT): PTR;
VAR
	name: AosFS.FileName; F: AosFS.File;
	port: AosSerials.Port; portn, bps, parity, stop, res: LONGINT;
	recv: Receiver; error: ARRAY 64 OF CHAR; awaitF: BOOLEAN;
	W: AosIO.Writer; R: AosIO.Reader;
BEGIN
	IF GetPars(par, name, portn, bps, parity, stop) THEN
		AosOut.String(name); AosOut.Ln();
		IF name # "" THEN
			F := AosFS.New(name); awaitF := FALSE
		ELSE
			ASSERT(mode = YModem);
			F := NIL; awaitF := TRUE
		END;

		port := AosSerials.GetPort(portn);
		ASSERT(port # NIL);
		port.Open(bps, 8, parity, stop, res);
		ASSERT(res = AosSerials.Ok);
		AosIO.OpenWriter(W, port.Send); AosIO.OpenReader(R, port.Receive);
		NEW(recv, W, R, F, mode);
		IF ~awaitF THEN
			recv.Await(error)
		ELSE
			recv.AwaitF(F, error)
		END;
		port.Close();

		IF error # "" THEN
			AosOut.String("  "); AosOut.String(error);
		ELSE
			AosFS.Register(F);
			IF awaitF THEN
				F.GetName(name);
				AosOut.String("  "); AosOut.String(name);
			END;
			AosOut.String("  done");
		END;
		AosOut.Ln;
	END;
	RETURN NIL
END xyReceive;

PROCEDURE XReceive*(par: PTR): PTR;
BEGIN
	AosOut.String("XReceive ");
	RETURN xyReceive(par, XModem)
END XReceive;

PROCEDURE YReceive*(par: PTR): PTR;
BEGIN
	AosOut.String("YReceive ");
	RETURN xyReceive(par, YModem)
END YReceive;

END AosXYModem.

Aos.Call AosXYModem.YSend 0 115200 no 1 test.dat ~

Aos.Call AosXYModem.YReceive 0 115200 no 1 test.dat ~

S.Free AosXYModem ~
