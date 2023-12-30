(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosVNC; (** AUTHOR "pjm/jkreienb"; PURPOSE "VNC client"; *)

(*
VNC viewer for Aos - based on Oberon VNC viewer by Jörg Kreienbühl.
This version is based on the window manager.
	
References:
1. Tristan Richardson and Kenneth R. Wood, "The RFB Protocol: Version 3.3", ORL, Cambridge, January 1998
*)

IMPORT SYSTEM, AosIO, AosOut, AosActive, AosCommands, AosNet, AosIP, AosTCP, AosDNS, AosDES, 
	AosInputs, Raster, WMWindowManager, Rect := WMRectangles, Dialogs := WMDialogs, AosBeep, AosFS;

CONST
	OpenTimeout = 10000;
	CloseTimeout = 2000;
	PollTimeout = 0;	(* set to 0 for old-style polling on every received event *)
	Shared = TRUE;
	
	AlphaCursor = 128;
	
	InBufSize = 8192;	(* network input buffer *)
	OutBufSize = 4096;	(* network output buffer *)
	ImgBufSize = 8192;	(* image buffer for ReceiveRaw *)
	
	BellDelay = 20;	(* ms *)
	BellFreq = 550;	(* Hz *)
	
	Trace = FALSE;
	TraceVisual = TRUE;
	TraceAudio = FALSE;

	Ok = AosTCP.Ok;
	
TYPE
	Connection* = POINTER TO RECORD
		next: Connection;	(* link in connection pool *)
		pcb: AosTCP.Connection;
		w: Window;
		res, id: LONGINT;
		receiver: Receiver;
		sender: Sender;
		nb: Raster.Image;
		fmt: Raster.Format;	(* network transfer format *)
		mode: Raster.Mode;
		bytesPerPixel: LONGINT;	(* network transfer format size *)
		rcvbuf, imgbuf: POINTER TO ARRAY OF CHAR;
		rcvbufpos, rcvbuflen: LONGINT;
		fip: AosIP.Adr
	END;

TYPE
	EnumProc = PROCEDURE (c: Connection);
	
	ConnectionPool = OBJECT
		VAR head, tail: Connection; id: LONGINT;
		
		PROCEDURE Empty(): BOOLEAN;
		BEGIN {}	(* read head pointer atomically *)
			RETURN head = NIL
		END Empty;
		
		PROCEDURE Add(c: Connection);
		BEGIN {EXCLUSIVE}
			c.next := NIL; c.id := id; INC(id);
			IF head = NIL THEN head := c ELSE tail.next := c END;
			tail := c
		END Add;
		
		PROCEDURE Remove(c: Connection);
		VAR p, q: Connection;
		BEGIN {EXCLUSIVE}
			p := NIL; q := head;
			WHILE (q # NIL) & (q # c) DO p := q; q := q.next END;
			IF q = c THEN	(* found *)
				IF p # NIL THEN p.next := q.next ELSE head := NIL; tail := NIL END
			END
		END Remove;
		
		PROCEDURE Enumerate(p: EnumProc);
		VAR c: Connection;
		BEGIN {}	(* may traverse list concurrently with Add and Remove *)
			c := head; WHILE c # NIL DO p(c); c := c.next END
		END Enumerate;
		
		PROCEDURE Find(id: LONGINT): Connection;
		VAR c: Connection;
		BEGIN {}	(* may traverse list concurrently with Add and Remove *)
			c := head; WHILE (c # NIL) & (c.id # id) DO c := c.next END;
			RETURN c
		END Find;
		
		PROCEDURE &Init;
		BEGIN
			head := NIL; tail := NIL; id := 0
		END Init;
		
	END ConnectionPool;

TYPE
	Window = OBJECT (WMWindowManager.BufferWindow)
		VAR sender: Sender;
		
		PROCEDURE PointerDown*(x, y: LONGINT; keys: SET);
		BEGIN
			IF sender # NIL THEN sender.Pointer(x, y, keys) END
		END PointerDown;
		
		PROCEDURE PointerMove*(x, y: LONGINT; keys: SET);
		BEGIN
			IF sender # NIL THEN sender.Pointer(x, y, keys) END
		END PointerMove;

		PROCEDURE WheelMove*(dz : LONGINT);
		BEGIN
			IF sender # NIL THEN sender.Wheel(dz) END
		END WheelMove;
		
		PROCEDURE PointerUp*(x, y: LONGINT; keys: SET);
		BEGIN
			IF sender # NIL THEN sender.Pointer(x, y, keys) END
		END PointerUp;
		
		PROCEDURE KeyEvent*(ucs : LONGINT; flags: SET; keysym: LONGINT);
		BEGIN
			IF (keysym # AosInputs.KsNil) & (sender # NIL) THEN sender.Key(keysym, flags) END
		END KeyEvent;
		
		PROCEDURE Close*();
		BEGIN
			IF sender # NIL THEN CloseVNC(sender.c) END
		END Close;
		
	END Window;

TYPE
	Receiver = OBJECT
		VAR c: Connection; exception, double: BOOLEAN;
		
		PROCEDURE &Init(c: Connection);
		BEGIN
			SELF.c := c; exception := FALSE; double := FALSE
		END Init;
		
	BEGIN {ACTIVE, SAFE}
		IF exception THEN
			IF TRUE OR Trace THEN AosOut.Enter; AosOut.String("Receiver exception"); AosOut.Exit END;
			IF double THEN RETURN END;
			double := TRUE
		ELSE
			exception := TRUE;
			IF Trace THEN AosOut.Enter; AosOut.String("Receiver enter"); AosOut.Exit END;
			REPEAT
				IF (PollTimeout = 0) & (c.sender # NIL) THEN c.sender.HandleTimeout END;
				AwaitResponse(c)
			UNTIL c.res # Ok;
			IF Trace THEN AosOut.Enter; AosOut.String("Receiver exit"); AosOut.Exit END
		END;
		IF c.sender # NIL THEN c.sender.Terminate END;
		IF c.w # NIL THEN
			c.w.manager.Remove(c.w);
			c.w := NIL
		END
	END Receiver;
	
TYPE
	Sender = OBJECT
		VAR
			c: Connection;
			head, middle, tail, res, lx, ly: LONGINT;
			lkeys : SET;
			buf: ARRAY OutBufSize OF CHAR;
			done, poll: BOOLEAN;
			timer: AosActive.Timer;
		
		PROCEDURE Available(): LONGINT;
		BEGIN
			RETURN (head - tail - 1) MOD LEN(buf)
		END Available;
		
		PROCEDURE Put(x: CHAR);
		BEGIN
			ASSERT((tail+1) MOD LEN(buf) # head);
			buf[tail] := x; tail := (tail+1) MOD LEN(buf)
		END Put;
		
		PROCEDURE PutInt(x: LONGINT);
		BEGIN
			Put(CHR(x DIV 100H)); Put(CHR(x MOD 100H))
		END PutInt;
		
		PROCEDURE Pointer(x, y: LONGINT; keys: SET);
		BEGIN {EXCLUSIVE}
			IF (x >= 0) & (x < c.w.img.width) & (y >= 0) & (y < c.w.img.height) & (Available() >= 6) THEN
				IF Trace THEN
					AosOut.Enter; AosOut.String("Ptr "); AosOut.Int(x, 5); AosOut.Int(y, 5); AosOut.Exit
				END;
				Put(5X);	(* PointerEvent (sec. 5.2.6) *)
				Put(CHR(SYSTEM.VAL(LONGINT, keys)));
				PutInt(x); PutInt(y);
				lx := x; ly := y; lkeys := keys
			END
		END Pointer;

		PROCEDURE Wheel(dz : LONGINT);
		VAR keys : SET;
		BEGIN {EXCLUSIVE}
			IF (Available() >= 6) THEN
				IF Trace THEN
					AosOut.Enter; AosOut.String("Wheel "); AosOut.Int(dz, 5); AosOut.Exit
				END;
				Put(5X);	(* PointerEvent (sec. 5.2.6) *)
				keys := lkeys;
				IF dz < 0 THEN INCL(keys, 3) END;
				IF dz > 0 THEN INCL(keys, 4) END;
				Put(CHR(SYSTEM.VAL(LONGINT, keys)));
				PutInt(lx); PutInt(ly)
			END
		END Wheel;
		
		PROCEDURE Key(keysym: LONGINT; flags: SET);
		BEGIN {EXCLUSIVE}
			IF Available() >= 8 THEN
				Put(4X);	(* KeyEvent (sec. 5.2.5) *)
				IF AosInputs.Release IN flags THEN Put(0X) ELSE Put(1X) END;
				PutInt(0); PutInt(0); PutInt(keysym)
			END
		END Key;
		
		PROCEDURE Paste(r: AosIO.Reader);
		VAR key: LONGINT;
		BEGIN {EXCLUSIVE}
			LOOP
				key := ORD(r.Get());
				IF r.res # 0 THEN EXIT END;
				AWAIT(Available() >= 16);
					(* down key *)
				Put(4X);	(* KeyEvent (sec. 5.2.5) *)
				Put(1X); PutInt(0); PutInt(0); PutInt(key);
					(* up key *)
				Put(4X);	(* KeyEvent (sec. 5.2.5) *)
				Put(0X); PutInt(0); PutInt(0); PutInt(key)
			END
		END Paste;
		
		PROCEDURE AwaitEvent;
		BEGIN {EXCLUSIVE}
			AWAIT((head # tail) OR poll OR done);
			IF ~done & (Available() >= 10) THEN
				Put(3X);	(* FramebufferUpdateRequest (sec. 5.2.4) *)
				Put(1X);	(* incremental *)
				PutInt(0); PutInt(0); PutInt(c.w.img.width); PutInt(c.w.img.height)
			END;
			middle := tail; poll := FALSE
		END AwaitEvent;
		
		PROCEDURE SendEvents;
		BEGIN {}
			IF middle >= head THEN
				c.pcb.Send(buf, head, middle-head, FALSE, res)
			ELSE	(* split buffer *)
				c.pcb.Send(buf, head, LEN(buf)-head, FALSE, res);
				IF res = Ok THEN c.pcb.Send(buf, 0, middle, FALSE, res) END
			END;
			head := middle
		END SendEvents;
		
		PROCEDURE Terminate;
		BEGIN {EXCLUSIVE}
			done := TRUE
		END Terminate;
		
		PROCEDURE HandleTimeout;
		BEGIN {EXCLUSIVE}
			poll := TRUE;
			IF (PollTimeout > 0) & ~done THEN
				AosActive.SetTimeout(timer, SELF.HandleTimeout, PollTimeout)
			END
		END HandleTimeout;
		
		PROCEDURE &Init(c: Connection);
		BEGIN
			NEW(timer);
			SELF.c := c; head := 0; middle := 0; tail := 0; res := Ok; done := FALSE
		END Init;
		
	BEGIN {ACTIVE}
		IF Trace THEN AosOut.Enter; AosOut.String("Sender enter"); AosOut.Exit END;
		LOOP
			AwaitEvent;
			IF done THEN EXIT END;
			IF TraceAudio THEN AosBeep.Beep(BellFreq) END;
			IF Trace THEN
				AosOut.Enter; AosOut.String("Events "); AosOut.Int(head, 5); AosOut.Int(middle, 5); AosOut.Exit
			END;
			SendEvents;
			IF TraceAudio THEN AosBeep.Beep(0) END;
			IF res # Ok THEN EXIT END
		END;
		AosActive.CancelTimeout(timer);
		IF Trace THEN AosOut.Enter; AosOut.String("Sender exit"); AosOut.Exit END
	END Sender;

TYPE
	Bell = OBJECT
		VAR timer: AosActive.Timer;
		
		PROCEDURE Ring;
		BEGIN {EXCLUSIVE}
			IF timer = NIL THEN NEW(timer) END;
			AosActive.SetTimeout(timer, SELF.HandleTimeout, BellDelay);	(* ignore race with expired, but unscheduled timer *)
			AosBeep.Beep(BellFreq)
		END Ring;
		
		PROCEDURE HandleTimeout;
		BEGIN {EXCLUSIVE}
			AosBeep.Beep(0)
		END HandleTimeout;
		
	END Bell;

VAR
	pool: ConnectionPool;
	bell: Bell;

PROCEDURE ReceiveBytes(c: Connection; VAR buf: ARRAY OF CHAR; size: LONGINT; VAR len: LONGINT);
VAR dst, n: LONGINT;
BEGIN
	IF c.res = Ok THEN
		dst := 0; len := 0;
		LOOP
			IF size <= 0 THEN EXIT END;
			n := Min(c.rcvbuflen, size);	(* n is number of bytes to copy from buffer now *)
			IF n = 0 THEN	(* buffer empty *)
					(* attempt to read at least size bytes, but at most a full buffer *)
				c.pcb.Receive(c.rcvbuf^, 0, LEN(c.rcvbuf), size, n, c.res);
				IF c.res # Ok THEN EXIT END;
				c.rcvbufpos := 0; c.rcvbuflen := n;
				n := Min(n, size)	(* n is number of bytes to copy from buffer now *)
			END;
			ASSERT(dst+n <= LEN(buf));	(* index check *)
			SYSTEM.MOVE(SYSTEM.ADR(c.rcvbuf[c.rcvbufpos]), SYSTEM.ADR(buf[dst]), n);
			INC(c.rcvbufpos, n); DEC(c.rcvbuflen, n);
			INC(dst, n); DEC(size, n); INC(len, n)
		END
	ELSE
		buf[0] := 0X; len := 0
	END
END ReceiveBytes;

PROCEDURE Receive(c: Connection; VAR ch: CHAR);
VAR len: LONGINT; buf: ARRAY 1 OF CHAR;
BEGIN
	IF c.rcvbuflen > 0 THEN
		ch := c.rcvbuf[c.rcvbufpos]; INC(c.rcvbufpos); DEC(c.rcvbuflen)
	ELSE
		ReceiveBytes(c, buf, 1, len);
		ch := buf[0]
	END
END Receive;

PROCEDURE ReceiveInt(c: Connection; VAR x: LONGINT);
VAR len: LONGINT; buf: ARRAY 2 OF CHAR;
BEGIN
	ReceiveBytes(c, buf, 2, len);
	x := AosNet.GetNet2(buf, 0)
END ReceiveInt;

PROCEDURE ReceiveLInt(c: Connection; VAR x: LONGINT);
VAR len: LONGINT; buf: ARRAY 4 OF CHAR;
BEGIN
	ReceiveBytes(c, buf, 4, len);
	x := AosNet.GetNet4(buf, 0)
END ReceiveLInt;

PROCEDURE ReceiveIgnore(c: Connection; len: LONGINT);
VAR ch: CHAR;
BEGIN
	WHILE (len > 0) & (c.res = Ok) DO Receive(c, ch); DEC(len) END
END ReceiveIgnore;

PROCEDURE Send(c: Connection; x: CHAR);
VAR buf: ARRAY 1 OF CHAR;
BEGIN
	buf[0] := x; c.pcb.Send(buf, 0, 1, FALSE, c.res)
END Send;

PROCEDURE Min(x, y: LONGINT): LONGINT;
BEGIN
	IF x <= y THEN RETURN x ELSE RETURN y END
END Min;

(* Get the server's version number and send our version number. *)

PROCEDURE DoVersion(c: Connection): BOOLEAN;
VAR buf: ARRAY 16 OF CHAR; len: LONGINT;
BEGIN
	ReceiveBytes(c, buf, 12, len);
	IF c.res = Ok THEN
		IF Trace THEN
			buf[11] := 0X;
			AosOut.Enter; AosOut.String("Version="); AosOut.String(buf); AosOut.Exit
		END;
		buf := "RFB 003.003"; buf[11] := 0AX;
		c.pcb.Send(buf, 0, 12, FALSE, c.res)
	END;
	RETURN c.res = Ok
END DoVersion;

(* Authenticate ourself with the server. *)

PROCEDURE DoAuthentication(c: Connection; VAR pwd: ARRAY OF CHAR): BOOLEAN;
VAR x, len, len0: LONGINT; buf: ARRAY 64 OF CHAR; cipher: ARRAY 16 OF CHAR; d: AosDES.DES;
BEGIN
	ReceiveLInt(c, x);
	IF c.res = Ok THEN
		IF Trace THEN
			AosOut.Enter; AosOut.String("Scheme="); AosOut.Int(x, 1); AosOut.Exit
		END;
		IF x = 0 THEN	(* failed *)
			ReceiveLInt(c, len);	(* read reason *)
			WHILE (len > 0) & (c.res = Ok) DO
				len0 := Min(len, LEN(buf));
				ReceiveBytes(c, buf, len0, len0);
				DEC(len, len0)
			END;
			IF Trace & (c.res = Ok) THEN	(* write last part of reason (typically only one part) *)
				IF len0 = LEN(buf) THEN DEC(len0) END;
				buf[len0] := 0X;
				AosOut.Enter; AosOut.String("Reason="); AosOut.String(buf); AosOut.Exit
			END
		ELSIF x = 2 THEN	(* VNC authentication *)
			ReceiveBytes(c, buf, 16, len);	(* challenge *)
			IF c.res = Ok THEN
				NEW(d);
				d.SetKey(pwd);
				d.Encrypt(buf, 0, cipher, 0);	(* Two 8-Byte-Blocks *)
				d.Encrypt(buf, 8, cipher, 8);
				c.pcb.Send(cipher, 0, 16, FALSE, c.res);
				IF c.res = Ok THEN
					ReceiveLInt(c, x);
					IF c.res = Ok THEN
						c.res := x	(* 0=Ok, 1=failed, 2=too-many *)
					END
				END
			END
		ELSE	(* no or unknown authentication *)
			(* skip *)
		END
	END;
	RETURN c.res = Ok
END DoAuthentication;

(* Set up an RFB encodings message.  "code" contains the codes in preferred order.  "len" returns the message length. *)

PROCEDURE PutEncodings(VAR buf: ARRAY OF CHAR; ofs: LONGINT; code: ARRAY OF CHAR; VAR len: LONGINT);
VAR i: LONGINT;
BEGIN
	buf[ofs] := 2X;	(* SetEncodings (sec. 5.2.3) *)
	buf[ofs+1] := 0X;	(* padding *)
	i := 0;
	WHILE code[i] # 0X DO
		AosNet.PutNet4(buf, ofs + 4*(i+1), ORD(code[i])-ORD("0"));
		INC(i)
	END;
	AosNet.PutNet2(buf, ofs+2, i);	(* number-of-encodings *)
	len := 4*(i+1)
END PutEncodings;

(* Initialise the transfer format. *)

PROCEDURE DoInit(c: Connection): BOOLEAN;
VAR len, len0, w, h: LONGINT; buf: ARRAY 64 OF CHAR; pixel: Raster.Pixel; ptr: WMWindowManager.PointerInfo;
		xpos, ypos : LONGINT;
BEGIN
	IF Shared THEN Send(c, 1X) ELSE Send(c, 0X) END;
	IF c.res = Ok THEN
		ReceiveBytes(c, buf, 24, len);	(* initialization message *)
		IF c.res = Ok THEN
			w := AosNet.GetNet2(buf, 0); h := AosNet.GetNet2(buf, 2);
			len := AosNet.GetNet4(buf, 20);
			IF Trace THEN
				AosOut.Enter;
				AosOut.String("Server: width="); AosOut.Int(w, 1);
				AosOut.String(" height="); AosOut.Int(h, 1);
				AosOut.String(" bpp="); AosOut.Int(ORD(buf[4]), 1);
				AosOut.String(" depth="); AosOut.Int(ORD(buf[5]), 1);
				AosOut.String(" bigendian="); AosOut.Int(ORD(buf[6]), 1);
				AosOut.String(" truecolor="); AosOut.Int(ORD(buf[7]), 1); AosOut.Ln;
				AosOut.String(" redmax="); AosOut.Int(AosNet.GetNet2(buf, 8), 1);
				AosOut.String(" greenmax="); AosOut.Int(AosNet.GetNet2(buf, 10), 1);
				AosOut.String(" bluemax="); AosOut.Int(AosNet.GetNet2(buf, 12), 1);
				AosOut.String(" redshift="); AosOut.Int(ORD(buf[14]), 1);
				AosOut.String(" greenshift="); AosOut.Int(ORD(buf[15]), 1);
				AosOut.String(" blueshift="); AosOut.Int(ORD(buf[16]), 1);
				AosOut.String(" len="); AosOut.Int(len, 1);
				AosOut.Exit
			END;
			WHILE (len > 0) & (c.res = Ok) DO
				len0 := Min(len, LEN(buf));
				ReceiveBytes(c, buf, len0, len0);
				DEC(len, len0)
			END;
			IF c.res = Ok THEN
				IF Trace THEN	(* write last part of name (typically only one part) *)
					IF len0 = LEN(buf) THEN DEC(len0) END;
					buf[len0] := 0X;
					AosOut.Enter; AosOut.String("Name="); AosOut.String(buf); AosOut.Exit
				END;
					(* choose our preferred format *)
				Raster.InitMode(c.mode, Raster.srcCopy);
				NEW(c.w, w, h, FALSE);
				
				NEW(ptr); ptr.hotX := 2; ptr.hotY := 2;
				NEW(ptr.img); Raster.Create(ptr.img, 4, 4, Raster.BGRA8888);
				Raster.SetRGBA(pixel, 255, 255, 255, AlphaCursor);
				Raster.Fill(ptr.img, 0, 0, 4, 4, pixel, c.mode);
				Raster.SetRGBA(pixel, 0, 0, 0, AlphaCursor);
				Raster.Fill(ptr.img, 1, 1, 3, 3, pixel, c.mode);
				c.w.SetPointerInfo(ptr);

				WMWindowManager.DefaultAddWindow(c.w);
				
				Raster.SetRGB(pixel, 0, 0, 0);
				Raster.Fill(c.w.img, 0, 0, c.w.img.width, c.w.img.height, pixel, c.mode);
				c.w.Invalidate(Rect.MakeRect(0, 0, c.w.img.width, c.w.img.height));
				NEW(c.nb);
				IF c.w.img.fmt.code IN {Raster.bgr888, Raster.bgra8888} THEN
					c.fmt := Raster.BGRA8888
				ELSE
					c.fmt := Raster.BGR565
				END;
				c.bytesPerPixel := c.fmt.bpp DIV 8;
				ASSERT(ImgBufSize >= w*c.bytesPerPixel);	(* at least one full line will fit buffer *)
				NEW(c.imgbuf, ImgBufSize);
					(* set up client format message *)
				buf[0] := 0X;	(* SetPixelFormat message (sec. 5.2.1) *)
				buf[1] := 0X; buf[2] := 0X; buf[3] := 0X;	(* padding *)
				buf[4] := CHR(c.bytesPerPixel*8);	(* bits-per-pixel (8, 16 or 32) on wire *)
				buf[5] := CHR(c.fmt.bpp);	(* depth (8, 16, 24 or 32) *)
				buf[6] := 0X;	(* big-endian-flag *)
				buf[7] := 1X;	(* true-colour-flag *)
				CASE c.fmt.code OF
					Raster.bgr565:
						AosNet.PutNet2(buf, 8, 31);	(* red-max *)
						AosNet.PutNet2(buf, 10, 63);	(* green-max *)
						AosNet.PutNet2(buf, 12, 31);	(* blue-max *)
						buf[14] := CHR(11);	(* red-shift *)
						buf[15] := CHR(5);	(* green-shift *)
						buf[16] := CHR(0)	(* blue-shift *)
					|Raster.bgra8888:
						AosNet.PutNet2(buf, 8, 255);	(* red-max *)
						AosNet.PutNet2(buf, 10, 255);	(* green-max *)
						AosNet.PutNet2(buf, 12, 255);	(* blue-max *)
						buf[14] := CHR(16);	(* red-shift *)
						buf[15] := CHR(8);	(* green-shift *)
						buf[16] := CHR(0)	(* blue-shift *)
				END;
				PutEncodings(buf, 20, "15420", len);	(* 0=raw, 1=copy rectangle, 2=RRE, 4=CoRRE, 5=hextile *)
				IF Trace THEN
					AosOut.Enter; AosOut.String("Client:"); AosOut.Ln;
					AosOut.Buffer(buf, 0, 20+len); AosOut.Exit
				END;
				c.pcb.Send(buf, 0, 20+len, FALSE, c.res)
			END
		END
	END;
	RETURN c.res = Ok
END DoInit;

(* Send a framebuffer update request. *)

PROCEDURE SendRequest(c: Connection; inc: BOOLEAN; x, y, w, h: LONGINT);
VAR buf: ARRAY 10 OF CHAR;
BEGIN
	IF Trace THEN
		AosOut.Enter; AosOut.String("Req"); AosOut.Int(x, 5); AosOut.Int(y, 5); 
		AosOut.Int(w, 5); AosOut.Int(h, 5);
		IF inc THEN AosOut.String(" inc") END;
		AosOut.Exit
	END;
	buf[0] := 3X;	(* FramebufferUpdateRequest (sec. 5.2.4) *)
	IF inc THEN buf[1] := 1X ELSE buf[1] := 0X END;
	AosNet.PutNet2(buf, 2, x); AosNet.PutNet2(buf, 4, y);
	AosNet.PutNet2(buf, 6, w); AosNet.PutNet2(buf, 8, h);
	c.pcb.Send(buf, 0, 10, FALSE, c.res)
END SendRequest;

(* Update an area of the display. *)

PROCEDURE UpdateDisplay(c: Connection; x, y, w, h: LONGINT);
(*VAR pixel: Raster.Pixel; mode: Raster.Mode;*)
BEGIN
(*
	Raster.SetRGB(pixel, 255, 255, 255);
	Raster.InitMode(mode, Raster.InvDst);
	Raster.Fill(c.w.img, 0, 0, 5, 5, pixel, mode);
	IF (x # 0) OR (y # 0) THEN c.w.AddDirty(0, 0, 10, 10) END;
*)
	c.w.Invalidate(Rect.MakeRect(x, y, x + w, y + h))
END UpdateDisplay;

(* Receive a raw rectangle. *)

PROCEDURE ReceiveRaw(c: Connection; x, y, w, h: LONGINT);
VAR bh, h0, len, i: LONGINT;
BEGIN
	IF Trace THEN
		AosOut.Enter; AosOut.String("Raw"); AosOut.Int(x, 5); AosOut.Int(y, 5); 
		AosOut.Int(w, 5); AosOut.Int(h, 5); AosOut.Exit
	END;
	bh := LEN(c.imgbuf^) DIV (w*c.bytesPerPixel);	(* number of lines that will fit in buffer *)
	Raster.Init(c.nb, w, bh, c.fmt, w*c.bytesPerPixel, SYSTEM.ADR(c.imgbuf[0]));
	WHILE h > 0 DO
		IF h >= bh THEN h0 := bh ELSE h0 := h END;
		len := h0*w*c.bytesPerPixel;
		ReceiveBytes(c, c.imgbuf^, len, len);
		IF c.res # Ok THEN RETURN END;
		IF c.bytesPerPixel = 4 THEN	(* fix alpha values *)
			FOR i := 0 TO len-1 BY 4 DO c.imgbuf[i+Raster.a] := 0FFX END
		END;
		Raster.Copy(c.nb, c.w.img, 0, 0, w, h0, x, y, c.mode);
		DEC(h, h0); INC(y, h0)
	END
END ReceiveRaw;

(* Receive a copy rectangle message. *)

PROCEDURE ReceiveCopyRect(c: Connection; x, y, w, h: LONGINT);
VAR sx, sy: LONGINT;
BEGIN
	ReceiveInt(c, sx);	(* src-x-position *)
	IF c.res = Ok THEN
		ReceiveInt(c, sy);	(* src-y-position *)
		IF c.res = Ok THEN
			IF Trace THEN
				AosOut.Enter; AosOut.String("Copy"); AosOut.Int(x, 5); AosOut.Int(y, 5); 
				AosOut.Int(w, 5); AosOut.Int(h, 5); AosOut.Int(sx, 5); AosOut.Int(sy, 5); AosOut.Exit
			END;
			Raster.Copy(c.w.img, c.w.img, sx, sy, sx+w, sy+h, x, y, c.mode)
		END
	END
END ReceiveCopyRect;

(* Receive a pixel. *)

PROCEDURE ReceivePixel(c: Connection; VAR pixel: Raster.Pixel);
VAR len: LONGINT; buf: ARRAY 4 OF CHAR;
BEGIN
	ReceiveBytes(c, buf, c.bytesPerPixel, len);
	c.fmt.unpack(c.fmt, SYSTEM.ADR(buf[0]), 0, pixel);
	pixel[Raster.a] := 0FFX
END ReceivePixel;

(* Receive an RRE rectangle message. *)

PROCEDURE ReceiveRRE(c: Connection; x, y, w, h: LONGINT);
VAR n, len, sx, sy: LONGINT; pixel: Raster.Pixel; buf: ARRAY 8 OF CHAR;
BEGIN
	IF Trace THEN
		AosOut.Enter; AosOut.String("RRE"); AosOut.Int(x, 5); AosOut.Int(y, 5);
		AosOut.Int(w, 5); AosOut.Int(h, 5); AosOut.Exit
	END;
	ReceiveLInt(c, n);	(* number-of-subrectangles *)
	IF c.res = Ok THEN
		ReceivePixel(c, pixel);
		IF c.res = Ok THEN
			Raster.Fill(c.w.img, x, y, x+w, y+h, pixel, c.mode);
			WHILE n > 0 DO
				ReceivePixel(c, pixel);
				IF c.res # Ok THEN RETURN END;
				ReceiveBytes(c, buf, 8, len);
				IF c.res # Ok THEN RETURN END;
				sx := x+AosNet.GetNet2(buf, 0); sy := y+AosNet.GetNet2(buf, 2);
				Raster.Fill(c.w.img, sx, sy, sx+AosNet.GetNet2(buf, 4), sy+AosNet.GetNet2(buf, 6), pixel, c.mode);
				DEC(n)
			END
		END
	END
END ReceiveRRE;

(* Receive a CoRRE rectangle message. *)

PROCEDURE ReceiveCoRRE(c: Connection; x, y, w, h: LONGINT);
VAR n, len, sx, sy: LONGINT; pixel: Raster.Pixel; buf: ARRAY 4 OF CHAR;
BEGIN
	IF Trace THEN
		AosOut.Enter; AosOut.String("CoRRE"); AosOut.Int(x, 5); AosOut.Int(y, 5); 
		AosOut.Int(w, 5); AosOut.Int(h, 5); AosOut.Exit
	END;
	ReceiveLInt(c, n);	(* number-of-subrectangles *)
	IF c.res = Ok THEN
		ReceivePixel(c, pixel);
		IF c.res = Ok THEN
			Raster.Fill(c.w.img, x, y, x+w, y+h, pixel, c.mode);
			WHILE n > 0 DO
				ReceivePixel(c, pixel);
				IF c.res # Ok THEN RETURN END;
				ReceiveBytes(c, buf, 4, len);
				IF c.res # Ok THEN RETURN END;
				sx := x+ORD(buf[0]); sy := y+ORD(buf[1]);
				Raster.Fill(c.w.img, sx, sy, sx+ORD(buf[2]), sy+ORD(buf[3]), pixel, c.mode);
				DEC(n)
			END
		END
	END
END ReceiveCoRRE;

(* Receive a hextile rectangle message. *)

PROCEDURE ReceiveHextile(c: Connection; x, y, w, h: LONGINT);
CONST
	Raw = 0; BackgroundSpecified = 1; ForegroundSpecified = 2; AnySubrects = 3; SubrectsColoured = 4;
VAR
	row, col, i, tw, th, wmin, hmin, sx, sy, sw, sh: LONGINT;
	bg, fg, pixel: Raster.Pixel; sub: SET; ch: CHAR;
BEGIN
	IF Trace THEN
		AosOut.Enter; AosOut.String("Hex"); AosOut.Int(x, 5); AosOut.Int(y, 5); 
		AosOut.Int(w, 5); AosOut.Int(h, 5); AosOut.Exit
	END;
	wmin := (w-1) MOD 16 + 1; hmin := (h-1) MOD 16 + 1;
	FOR row := 0 TO (h-1) DIV 16 DO
		IF row < (h-1) DIV 16 THEN th := 16 ELSE th := hmin END;
		FOR col := 0 TO (w-1) DIV 16 DO
			IF col < (w-1) DIV 16 THEN tw := 16 ELSE tw := wmin END;
			Receive(c, ch);
			IF c.res # Ok THEN RETURN END;
			sub := SYSTEM.VAL(SET, LONG(ORD(ch)));
			IF Raw IN sub THEN
				ReceiveRaw(c, x + 16*col, y + 16*row, tw, th)
			ELSE
				IF BackgroundSpecified IN sub THEN ReceivePixel(c, bg) END;
				IF ForegroundSpecified IN sub THEN ReceivePixel(c, fg) END;
				Raster.Fill(c.w.img, x + 16*col, y + 16*row, x + 16*col + tw, y + 16*row + th, bg, c.mode);
				IF AnySubrects IN sub THEN
					Receive(c, ch);
					IF c.res # Ok THEN RETURN END;
					FOR i := 1 TO ORD(ch) DO
						IF SubrectsColoured IN sub THEN ReceivePixel(c, pixel) ELSE pixel := fg END;
						Receive(c, ch);
						IF c.res # Ok THEN RETURN END;
						sx := ORD(ch) DIV 16; sy := ORD(ch) MOD 16;
						Receive(c, ch);
						IF c.res # Ok THEN RETURN END;
						sw := ORD(ch) DIV 16 + 1; sh := ORD(ch) MOD 16 + 1;
						Raster.Fill(c.w.img, x + 16*col + sx, y + 16*row + sy, x + 16*col + sx + sw, 
							y + 16*row + sy + sh, pixel, c.mode)
					END
				END
			END
		END;
		IF TraceVisual THEN UpdateDisplay(c, x, y + 16*row, w, th) END
	END
END ReceiveHextile;

(* Receive a rectangle message. *)

PROCEDURE ReceiveRectangle(c: Connection);
VAR len, x, y, w, h: LONGINT; buf: ARRAY 12 OF CHAR;
BEGIN
	ReceiveBytes(c, buf, 12, len);
	x := AosNet.GetNet2(buf, 0); y := AosNet.GetNet2(buf, 2);
	w := AosNet.GetNet2(buf, 4); h := AosNet.GetNet2(buf, 6);
	CASE AosNet.GetNet4(buf, 8) OF	(* encoding-type *)
		0: ReceiveRaw(c, x, y, w, h)
		|1: ReceiveCopyRect(c, x, y, w, h)
		|2: ReceiveRRE(c, x, y, w, h)
		|4: ReceiveCoRRE(c, x, y, w, h)
		|5: ReceiveHextile(c, x, y, w, h)
	END;
	UpdateDisplay(c, x, y, w, h)
END ReceiveRectangle;

(* Receive and react on one message from the server. *)

PROCEDURE AwaitResponse(c: Connection);
VAR len: LONGINT; ch: CHAR;
BEGIN
	Receive(c, ch);
	IF c.res = Ok THEN
		CASE ORD(ch) OF
			0:	(* FramebufferUpdate (sec. 5.3.1) *)
				Receive(c, ch);	(* padding *)
				IF c.res = Ok THEN ReceiveInt(c, len) END;	(* number-of-rectangles *)
				WHILE (c.res = Ok) & (len > 0) DO
					ReceiveRectangle(c); DEC(len)
				END
			|1:	(* SetColourMapEntries (sec. 5.3.2) *)
				Receive(c, ch);	(* padding *)
				IF c.res = Ok THEN ReceiveInt(c, len) END;	(* first-colour *)
				IF c.res = Ok THEN ReceiveInt(c, len) END;	(* number-of-colours *)
				IF (c.res = Ok) & (len > 0) THEN ReceiveIgnore(c, len*6) END
			|2:	(* Bell (sec. 5.3.3) *)
				bell.Ring
			|3:	(* ServerCutText (sec. 5.3.4) *)
				ReceiveIgnore(c, 3);	(* padding *)
				ReceiveLInt(c, len);
				IF (c.res = Ok) & (len > 0) THEN ReceiveIgnore(c, len) END
		END
	END
END AwaitResponse;

(* Open a VNC connection to the specified server and port. *)

PROCEDURE OpenVNC*(c: Connection; server: AosIP.Adr; port: LONGINT; pwd: ARRAY OF CHAR);
BEGIN
	NEW(c.pcb); c.fip := server;
	c.pcb.Open(AosTCP.NilPort, server, port, c.res);
	c.pcb.DelaySend(FALSE);
	IF c.res = Ok THEN
		c.pcb.AwaitState(AosTCP.OpenStates, AosTCP.ClosedStates, OpenTimeout, c.res)
	END;
	IF c.res = Ok THEN
		NEW(c.rcvbuf, InBufSize); c.rcvbufpos := 0; c.rcvbuflen := 0;
		IF DoVersion(c) & DoAuthentication(c, pwd) & DoInit(c) THEN
			SendRequest(c, FALSE, 0, 0, c.w.img.width, c.w.img.height);
			IF c.res = Ok THEN
				NEW(c.receiver, c);
				NEW(c.sender, c);
				c.w.sender := c.sender;
				IF PollTimeout # 0 THEN c.sender.HandleTimeout END	(* start the timer *)
			ELSE
				CloseVNC(c)
			END
		ELSE
			CloseVNC(c)
		END
	END;
	IF Trace & (c # NIL) THEN
		AosOut.Enter; AosOut.String("OpenVNC="); AosOut.Int(c.res, 1); AosOut.Exit
	END
END OpenVNC;

(* Close a VNC connection. *)

PROCEDURE CloseVNC*(VAR c: Connection);
VAR res: LONGINT;
BEGIN
	pool.Remove(c);
	c.pcb.Close();
	c.pcb.AwaitState(AosTCP.ClosedStates, {}, CloseTimeout, res);
	IF Trace THEN
		AosOut.Enter; AosOut.String("CloseVNC="); AosOut.Int(res, 1); AosOut.Exit
	END;
	(*c.pcb := NIL*)
END CloseVNC;

PROCEDURE PrintConnection(c: Connection);
VAR res: LONGINT; name: ARRAY 128 OF CHAR;
BEGIN
	AosOut.Int(c.id, 1);
	CASE c.fmt.code OF
		Raster.bgr565:
			AosOut.String(" 16-bit")
		|Raster.bgra8888:
			AosOut.String(" 32-bit")
	END;
	IF (c.w # NIL) & (c.w.img # NIL) THEN
		AosOut.Char(" "); AosOut.Int(c.w.img.width, 1);
		AosOut.Char("x"); AosOut.Int(c.w.img.height, 1)
	END;
	AosDNS.HostByNumber(c.fip, name, res);
	AosOut.Char(" "); AosOut.String(name);
	AosOut.Ln
END PrintConnection;

PROCEDURE Show*(par: PTR): PTR;
BEGIN
	IF ~pool.Empty() THEN
		AosOut.String("VNC connections"); AosOut.Ln;
		pool.Enumerate(PrintConnection);
	ELSE
		AosOut.String("No open connections"); AosOut.Ln
	END;
	RETURN NIL
END Show;

PROCEDURE ReadString(r: AosIO.Reader; VAR s: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
	i := 0; WHILE (r.res = 0) & (r.Peek() # " ") DO r.Char(s[i]); INC(i) END;
	s[i] := 0X; r.SkipBytes(1)
END ReadString;

PROCEDURE Open*(par: PTR): PTR;	(** [ server port ] *)
VAR
	server: AosIP.Adr; res, port: LONGINT; r: AosIO.StringReader; s: AosCommands.Parameters; ignore: PTR;
	c: Connection; pwd: ARRAY 32 OF CHAR; str, svr, title: ARRAY 128 OF CHAR;
BEGIN
	s := par(AosCommands.Parameters);
	COPY(s.str^, str);

	IF str[0] = 0X THEN
		IF Dialogs.QueryString("Enter VNC Server Port", str) # Dialogs.ResOk THEN RETURN NIL END
		;AosOut.String("<"); AosOut.String(str); AosOut.String(">"); AosOut.Ln;
	END;
	NEW(r, LEN(str)); r.Set(str);
	r.SkipSpaces; ReadString(r, svr); 
	IF (r.Peek() < "0") OR (r.Peek() > "9") THEN ReadString(r, pwd) END;
	r.Int(port, FALSE);
	IF r.res = 0 THEN
		AosDNS.HostByName(svr, server, res);
		IF (res = Ok) & (port # 0) THEN
			IF pwd = "" THEN
				IF Dialogs.QueryPassword("Enter VNC Password", pwd) # Dialogs.ResOk THEN RETURN NIL END
			END;
			IF pwd # "" THEN
				NEW(c);
				OpenVNC(c, server, port, pwd);
				IF c.res = Ok THEN
					pool.Add(c);
					COPY(svr, title); AosFS.AppendStr("  Port ", title); AosFS.AppendInt(port, title); AosFS.AppendStr(" - VNC ", title); AosFS.AppendInt(c.id, title);
					c.w.SetTitle(WMWindowManager.NewString(title)); 
					ignore := Show(NIL)
				ELSE
					AosOut.String(s.str^); AosOut.String(" error ");
					AosOut.Int(c.res, 1); AosOut.Ln
				END
			ELSE
				AosOut.String(s.str^); AosOut.String(" password not found"); AosOut.Ln
			END
		ELSE
			AosOut.String(s.str^); AosOut.String(" not found"); AosOut.Ln
		END
	ELSE
		AosOut.String(s.str^); AosOut.String(" expected server[ pwd] port"); AosOut.Ln
	END;
	RETURN NIL
END Open;

PROCEDURE Paste*(par: PTR): PTR;	(** connection text *)
VAR i: LONGINT; s: AosIO.StringReader; c: Connection;
BEGIN
	NEW(s, LEN(par(AosCommands.Parameters).str^));
	s.Set(par(AosCommands.Parameters).str^);
	s.SkipSpaces(); s.Int(i, FALSE);
	c := pool.Find(i);
	IF (c # NIL) & (c.sender # NIL) THEN
		IF s.Peek() = " " THEN s.SkipBytes(1) END;
		c.sender.Paste(s)
	END;
	RETURN NIL
END Paste;

BEGIN
	NEW(bell); NEW(pool)
END AosVNC.

AosVNC.Open portnoy.ethz.ch 5901 ~
AosVNC.Show
AosVNC.Paste 0 Hello world~

S.Free AosVNC ~
