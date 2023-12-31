(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE Diskettes; (** non-portable *)
(** AUTHOR "pjm"; PURPOSE "Diskette device driver"; *)

(* based on Native Oberon. *)

IMPORT SYSTEM, AosBoot, AosMemory, AosInterrupts, AosKernel, AosModules, Kernel, AosPlugins, Disks := AosDisks;

CONST
	MaxDevices = 2;
	BS = 512;
	
	Read = Disks.Read;  Write = Disks.Write;  Format = 2;  Verify = 3;	(* operations *)
	Ready = 0;  Reset = 1;  Recal = 2;	(* states *)
	T0 = 0;  T720 = 1;  T1440 = 2;  T2880 = 3;	(* drive/media types *)
	
	Ok = Disks.Ok;
	
TYPE
	Device* = OBJECT (Disks.Device)
		VAR
			drive: LONGINT;
			locked: BOOLEAN;	(* must be locked before access is allowed *)
			type, media: SHORTINT;	(* drive type & current media *)
				(* current parameters *)
			size, sectors, heads, tracks: LONGINT;
			gap, rate, spec1, spec2, fgap: CHAR;
		
		PROCEDURE Transfer*(op, start, num: LONGINT;  VAR buf: ARRAY OF CHAR;  ofs: LONGINT;  VAR res: LONGINT);
		BEGIN
			Transfer1(SELF, op, start, num, buf, ofs, res)
		END Transfer;
		
		PROCEDURE GetSize*(VAR size, res: LONGINT);
		BEGIN
			GetSize1(SELF, size, res)
		END GetSize;
		
		PROCEDURE Handle*(VAR msg: Disks.Message;  VAR res: LONGINT);
		BEGIN
			Handle1(SELF, msg, res)
		END Handle;
		
	END Device;

VAR
	device: ARRAY MaxDevices OF Device;
	curdrive: LONGINT;
	curtrack: LONGINT;
	state: SHORTINT;
	result: ARRAY 7 OF SET;
	errors: ARRAY 3 OF SET;
	dmabufvirt, dmabufphys, dmabufsize: LONGINT;
	motor, interrupt, installed: BOOLEAN;
	trace: SHORTINT;
	
(* Device driver *)

(* Error - Report an error *)

PROCEDURE Error(msg: ARRAY OF CHAR);
VAR error, reason: ARRAY 32 OF CHAR;  i: SHORTINT;  r0, r1, r2: SET;
BEGIN
	COPY(msg, error);  r0 := errors[0];  r1 := errors[1];  r2 := errors[2];
	IF (0 IN r1) OR (0 IN r2) THEN reason := "Missing address mark"
	ELSIF 1 IN r1 THEN reason := "Write protected"
	ELSIF 2 IN r1 THEN reason := "Sector not found"
	ELSIF 4 IN r1 THEN reason := "Over- or Underrun"
	ELSIF (5 IN r1) OR (5 IN r2) THEN reason := "CRC error"
	ELSIF 7 IN r1 THEN reason := "Sector past end"
	ELSIF (1 IN r2) OR (4 IN r2) THEN reason := "Bad track"
	ELSIF 6 IN r2 THEN reason := "Bad mark"
	ELSIF r0 * {6,7} = {6} THEN reason := "Command not completed"
	ELSIF r0 * {6,7} = {7} THEN reason := "Invalid command"
	ELSE reason := ""
	END;
	Kernel.WriteLn;  Kernel.WriteString("Diskette: ");  Kernel.WriteString(error);  
	Kernel.WriteString(". ");  Kernel.WriteString(reason);  Kernel.WriteLn;
	IF trace > 0 THEN
		FOR i := 0 TO 2 DO Kernel.WriteHex(SYSTEM.VAL(LONGINT, result[i]), 9) END;
		Kernel.WriteLn;
		FOR i := 0 TO 2 DO Kernel.WriteHex(SYSTEM.VAL(LONGINT, errors[i]), 9) END;
		Kernel.WriteLn
	END;
	FOR i := 0 TO 6 DO result[i] := {} END;
	FOR i := 0 TO 2 DO errors[i] := {} END;
	state := Reset
END Error;

(* SetupDMA - Start a DMA operation *)

PROCEDURE SetupDMA(read: BOOLEAN; chan, len: LONGINT);
VAR adr, page, mode: LONGINT;
BEGIN
	adr := dmabufphys;
	ASSERT(len <= dmabufsize);
	IF read THEN
		mode := 44H	(* IO->memory, no autoinit, increment, single mode *)
	ELSE
		mode := 48H	(* memory->IO, no autoinit, increment, single mode *)
	END;
	DEC(len);
	ASSERT((adr > 0) & (adr+len <= 1000000H));
	ASSERT(adr DIV 65536 = (adr+len-1) DIV 65536);	(* same 64KB region *)
	CASE chan OF
		0:  page := 87H
		|1:  page := 83H
		|2:  page := 81H
		|3:  page := 82H
	END;  (* CASE *)
	SYSTEM.PORTOUT(0AH, CHR(chan + 4));	(* disable DMA *)
	SYSTEM.PORTOUT(0CH, 0X);	(* clear flip-flop *)
	SYSTEM.PORTOUT(0BH, CHR(chan + mode));	(* set mode *)
	SYSTEM.PORTOUT(page, CHR(ASH(adr, -16)));	(* set page register *)
	SYSTEM.PORTOUT(chan*2, CHR(adr));	(* set address *)
	SYSTEM.PORTOUT(chan*2, CHR(ASH(adr, -8)));
	SYSTEM.PORTOUT(chan*2+1, CHR(len));	(* set length *)
	SYSTEM.PORTOUT(chan*2+1, CHR(ASH(len, -8)));
	SYSTEM.PORTOUT(0AH, CHR(chan))	(* enable DMA *)
END SetupDMA;

(* PutByte - Send byte to controller *)

PROCEDURE PutByte(b: CHAR);
VAR t: AosKernel.MilliTimer;  s: SET;
BEGIN
	IF state # Reset THEN
		AosKernel.SetTimer(t, 500);	(* 0.5s *)
		REPEAT
			SYSTEM.PORTIN(3F4H, SYSTEM.VAL(CHAR, s));
			IF s * {6,7} = {7} THEN	(* ready for write *)
				SYSTEM.PORTOUT(3F5H, b);
				RETURN	(* done *)
			END
		UNTIL AosKernel.Expired(t);
		state := Reset;  IF trace > 0 THEN Kernel.WriteString("~response ") END
	END
END PutByte;

(* GetResults - Get results from controller, returns length of result *)

PROCEDURE GetResults(): INTEGER;
VAR t: AosKernel.MilliTimer;  s: SET;  i: SHORTINT;
BEGIN
	IF state # Reset THEN
		i := 0;  s := {};
		AosKernel.SetTimer(t, 500);	(* 0.5s *)
		REPEAT
			SYSTEM.PORTIN(3F4H, SYSTEM.VAL(CHAR, s));
			IF s * {4,6,7} = {7} THEN	(* ready for write (end) *)
				IF trace > 0 THEN Kernel.WriteChar("=");  Kernel.WriteInt(i, 1) END;
				RETURN i
			ELSIF s * {6,7} = {6,7} THEN	(* ready for read *)
				SYSTEM.PORTIN(3F5H, SYSTEM.VAL(CHAR, s));  result[i] := s;
				IF i < 3 THEN errors[i] := errors[i] + result[i] END;
				INC(i)
			ELSE (* skip *)
			END
		UNTIL AosKernel.Expired(t);
		state := Reset;  IF trace > 0 THEN Kernel.WriteString("~response ") END
	END;
	RETURN -1
END GetResults;

(* InterruptHandler - Handle floppy interrupt *)

PROCEDURE InterruptHandler(VAR state: AosInterrupts.State);
BEGIN
	SYSTEM.STI();  interrupt := TRUE
END InterruptHandler;

(* WaitInterrupt - Wait for an interrupt *)

PROCEDURE WaitInterrupt;
VAR t: AosKernel.MilliTimer;
BEGIN
	IF state # Reset THEN
		AosKernel.SetTimer(t, 2000);	(* 2s *)
		REPEAT UNTIL interrupt OR AosKernel.Expired(t);
		IF ~interrupt THEN IF trace > 0 THEN Kernel.WriteString("~interrupt ") END; state := Reset END;
		interrupt := FALSE
	END
END WaitInterrupt;

(* SetParams - Set parameters depending on drive type and media *)

PROCEDURE SetParams(p: Device);
BEGIN
	CASE p.media OF
		T720:
			IF trace > 0 THEN Kernel.WriteString("720k ") END;
			p.sectors := 9;  p.heads := 2;  p.tracks := 80;
			p.gap := 1BX;  p.rate := 2X;  (* transfer rate 250k/s *)
			p.spec1 := 0E1X;  (* step rate 4ms, head unload 32ms *)
			p.spec2 := 6X;  (* head load 12ms, DMA mode *)
			p.fgap := 50X	(* format gap size *)
		|T1440:
			IF trace > 0 THEN Kernel.WriteString("1.44M ") END;
			p.sectors := 18;  p.heads := 2;  p.tracks := 80;
			p.gap := 1BX;  p.rate := 0X;  (* transfer rate 500k/s *)
			p.spec1 := 0C1X;  (* step rate 4ms, head unload 16ms *)
			p.spec2 := 6X;  (* head load 6ms, DMA mode *)
			p.fgap := 6CX	(* format gap size *)
	END;
	p.size := p.sectors * p.heads * p.tracks;
	state := Reset
END SetParams;

(* CycleMedia - Skip to next media for a drive *)

PROCEDURE CycleMedia(VAR p: Device);
BEGIN
	CASE p.type OF
		T0: HALT(99)	(* no such drive *)
		|T720:	(* 720k drive can only handle 720k media *)
			CASE p.media OF
				T0: p.media := T720
				|T720: p.media := T0
			END
		|T1440:	(* 1.44M drive first tries 1.44M & then 720k *)
			CASE p.media OF
				T0: p.media := T1440
				|T1440: p.media := T720
				|T720: p.media := T0
			END
		|T2880:	(* 2.88M drive first tries 1.44M & then 720k (2.88M not handled yet) *)
			CASE p.media OF
				T0: p.media := T1440
				|T1440: p.media := T720
				|T720: p.media := T0
			END
	END; (* CASE *)
	IF p.media # T0 THEN SetParams(p) END	(* now set params according to media *)
END CycleMedia;

(* Do - Perform a floppy operation *)

PROCEDURE Do(dev: Device; op, sector, head, track, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE): LONGINT;
CONST MaxLoops = 18;  MaxTries = 3;
VAR s: SET;  i, loops, try: LONGINT;  t: AosKernel.MilliTimer;  ok: BOOLEAN;  media: SHORTINT;
BEGIN
	FOR i := 0 TO 2 DO errors[i] := {} END;
	IF (num < 1) OR (num > 126) THEN Error("Bad number of sectors"); RETURN 1003 END;
	IF (track < 0) OR (track >= dev.tracks) THEN Error("Invalid track"); RETURN 1004 END;
	IF (head < 0) OR (head >= dev.heads) THEN Error("Invalid head"); RETURN 1005 END;
	IF curdrive # dev.drive THEN state := Reset;  curdrive := dev.drive END;
	loops := 0;  try := 0;  media := dev.media;
	LOOP	(* two EXIT's at end of CASE state = Ready *)
		IF trace > 0 THEN
			CASE state OF
				Ready: Kernel.WriteString("Ready ")
				|Reset: Kernel.WriteString("Reset ")
				|Recal: Kernel.WriteString("Recal ")
				ELSE Kernel.WriteString("Unknown ")
			END
		END;
			(* select the drive & send power to the motor *)
		s := {2,3,dev.drive+4} + SYSTEM.VAL(SET, dev.drive);
		SYSTEM.PORTOUT(3F2H, SYSTEM.VAL(CHAR, s));
		IF (op IN {Write, Format}) & ~motor THEN	(* motor was not running, wait for it to spin up *)
			AosKernel.SetTimer(t, 500);	(* 0.5s *)
			REPEAT UNTIL AosKernel.Expired(t)
		END;
		motor := TRUE;  ok := TRUE;
		CASE state OF
			Ready:
				IF trace > 0 THEN
					Kernel.WriteLn;
					CASE op OF
						Read: Kernel.WriteString("Read(")
						|Write: Kernel.WriteString("Write(")
						|Format: Kernel.WriteString("Format(")
						|Verify: Kernel.WriteString("Verify(")
					END;
					Kernel.WriteInt(track, 1);  Kernel.WriteChar(",");
					Kernel.WriteInt(head, 1);  Kernel.WriteChar(",");
					Kernel.WriteInt(sector, 1);  Kernel.WriteChar(",");
					Kernel.WriteInt(num, 1);  Kernel.WriteString(") ")
				END;
				IF curtrack # track THEN	(* seek to right track *)
					PutByte(0FX);  PutByte(CHR(ASH(head, 2) + dev.drive));  PutByte(CHR(track));	(* seek *)
					WaitInterrupt;
					PutByte(8X);  i := GetResults();	(* sense *)
					IF (i < 1) OR (result[0] * {3..7} # {5}) THEN
						IF trace > 0 THEN Kernel.WriteString("~seek ") END;  state := Reset
					ELSE
						curtrack := track
					END
				END;
				IF state # Reset THEN
					CASE op OF
						Read, Verify:
							SetupDMA(TRUE, 2, num*512);
							PutByte(0E6X)
						|Write:
							SYSTEM.MOVE(SYSTEM.ADR(buf[0]), dmabufvirt, num*512);
							SetupDMA(FALSE, 2, num*512);
							PutByte(0C5X)
						|Format:
							FOR i := 0 TO num-1 DO
								SYSTEM.PUT(dmabufvirt+i*4+0, CHR(track));
								SYSTEM.PUT(dmabufvirt+i*4+1, CHR(head));
								SYSTEM.PUT(dmabufvirt+i*4+2, CHR(i+1));
								SYSTEM.PUT(dmabufvirt+i*4+3, CHR(2))
							END;
							SetupDMA(FALSE, 2, num*4);
							PutByte(4DX);  PutByte(CHR(ASH(head, 2) + dev.drive));
							PutByte(2X);  PutByte(CHR(num));
							PutByte(dev.fgap);  PutByte(0F6X)
					END;
					IF op IN {Read, Write, Verify} THEN	(* standard parameters *)
						PutByte(CHR(ASH(head, 2) + dev.drive));  PutByte(CHR(track));	(* drive, head, track *)
						PutByte(CHR(head));  PutByte(CHR(sector));	(* head, sector *)
						PutByte(2X);	(* 512 byte sector *)
						PutByte(CHR(dev.sectors));	(* last sector *)
						PutByte(dev.gap);	(* gap length *)
						PutByte(0FFX)	(* sector size (unused) *)
					END;
					WaitInterrupt;
					IF (GetResults() < 7) OR (result[0] * {6,7} # {}) THEN
						IF trace > 0 THEN Kernel.WriteString("~op ") END;  state := Reset
					END
				END;
				IF state = Reset THEN
					INC(try);  IF trace > 0 THEN Kernel.WriteInt(try, 1);  Kernel.WriteString("-try ") END;
					IF try = MaxTries THEN
						IF op IN {Read, Write} THEN
							try := 0;  CycleMedia(dev);	(* advance to next media type *)
							IF dev.media # T0 THEN
								EXIT	(* EXIT: media type changed *)
							END
						END;
						IF op IN {Read, Verify} THEN Error("Read failed"); RETURN 1006
						ELSE Error("Write failed"); RETURN 1007
						END
					END
				ELSE
					IF op = Read THEN
						SYSTEM.MOVE(dmabufvirt, SYSTEM.ADR(buf[0]), num*512)
					END;
					EXIT	(* EXIT: operation successful *)
				END

			|Reset:
				curtrack := -1;  interrupt := FALSE;  (* reset possible late interrupt *)
				SYSTEM.PORTIN(3F2H, SYSTEM.VAL(CHAR, s));  EXCL(s, 2);
				SYSTEM.PORTOUT(3F2H, SYSTEM.VAL(CHAR, s));
				AosKernel.SetTimer(t, 1); REPEAT UNTIL AosKernel.Expired(t);	(* > 50us *)
				INCL(s, 2);  SYSTEM.PORTOUT(3F2H, SYSTEM.VAL(CHAR, s));
				state := Recal;  WaitInterrupt;
				PutByte(8X);	(* sense *)
				IF GetResults() < 1 THEN Error("Reset failed"); RETURN 1008 END;
				PutByte(3X);	(* specify (step rate, head load/unload) *)
				PutByte(dev.spec1);  PutByte(dev.spec2);
				IF state = Reset THEN Error("Specify failed"); RETURN 1009 END;
				SYSTEM.PORTOUT(3F7H, dev.rate);	(* data rate *)
			
			|Recal:
				PutByte(7X);  PutByte(CHR(dev.drive));	(* recalibrate *)
				WaitInterrupt;
				PutByte(8X);  i := GetResults();	(* sense *)
				IF (i < 1) OR (result[0] * {6..7} # {}) THEN
					(*Error("Recalibrate failed")*)
				ELSE
					state := Ready;  curtrack := 0
				END
				
		END; (* CASE *)
		INC(loops);  IF loops = MaxLoops THEN Error("Too many retries"); RETURN 1010 END;
		IF dev.media # media THEN RETURN Disks.MediaChanged END	(* trying new media type *)
	END;
	IF dev.media = media THEN RETURN Ok ELSE RETURN Disks.MediaChanged END
END Do;

PROCEDURE Transfer0(d: Disks.Device;  op, start, num: LONGINT;  VAR buf: ARRAY OF CHAR;  ofs: LONGINT;  VAR res: LONGINT);
VAR dev: Device; sector, head, track, s, ofs0, n, max, start0, num0: LONGINT;
BEGIN
	dev := d(Device);
	IF dev.locked THEN
		ASSERT((op = Read) OR (op = Write));
		IF dev.type = T0 THEN Error("Invalid drive"); HALT(99) END;
		IF dev.media = T0 THEN CycleMedia(dev) END;
		start0 := start;  num0 := num;  ofs0 := ofs;
		REPEAT
			s := start;  sector := (s MOD dev.sectors) + 1;
			s := s DIV dev.sectors;  head := s MOD dev.heads;
			track := s DIV dev.heads;
			max := dev.sectors - sector + 1;	(* sectors left on track *)
			IF (head = 0) & (dev.heads > 1) THEN
				INC(max, dev.sectors)	(* multi-track *)
			END;
			IF max > dmabufsize DIV BS THEN max := dmabufsize DIV BS END;
			IF num > max THEN n := max ELSE n := num END;
			res := Do(dev, op, sector, head, track, n, buf[ofs]);
			IF res = Ok THEN
				DEC(num, n);  INC(start, n);  INC(ofs, n*512)
			ELSIF res = Disks.MediaChanged THEN	(* media type changed, start over *)
				start := start0;  num := num0;  ofs := ofs0;  res := Ok
			ELSE
				(* skip *)
			END
		UNTIL (num = 0) OR (res # Ok)
	ELSE
		res := Disks.MediaMissing	(* must be locked for transfer *)
	END
END Transfer0;

PROCEDURE Transfer1(d: Disks.Device;  op, start, num: LONGINT;  VAR buf: ARRAY OF CHAR;  ofs: LONGINT;  VAR res: LONGINT);
BEGIN {EXCLUSIVE}
	Transfer0(d, op, start, num, buf, ofs, res)
END Transfer1;

PROCEDURE GetSize1(d: Disks.Device;  VAR size, res: LONGINT);
VAR dev: Device;  buf: ARRAY BS OF CHAR;
BEGIN {EXCLUSIVE}
	dev := d(Device);
	Transfer0(dev, Read, 0, 1, buf, 0, res);
	IF res = Disks.Ok THEN size := dev.size ELSE size := 0 END
END GetSize1;

PROCEDURE Handle1(d: Disks.Device;  VAR msg: Disks.Message;  VAR res: LONGINT);
VAR dev: Device;  buf: ARRAY BS OF CHAR;
BEGIN {EXCLUSIVE}
	dev := d(Device);
	IF msg IS Disks.GetGeometryMsg THEN
		Transfer0(dev, Read, 0, 1, buf, 0, res);
		IF res = Disks.Ok THEN
			WITH msg: Disks.GetGeometryMsg DO
				msg.cyls := dev.tracks;  msg.hds := dev.heads;  msg.spt := dev.sectors
			END
		END
	ELSIF msg IS Disks.LockMsg THEN
		IF ~dev.locked THEN
			dev.locked := TRUE; res := Disks.Ok
		ELSE
			res := 1001	(* already locked *)
		END
	ELSIF msg IS Disks.UnlockMsg THEN
		IF dev.locked THEN
			dev.locked := FALSE; res := Disks.Ok;
			StopMotor(dev.drive)
		ELSE
			res := 1002	(* was not locked *)
		END
	ELSE
		res := Disks.Unsupported
	END
END Handle1;

(** FormatDisk - Low-level format a diskette.  fmt="H" for high density (1.44M), "D" for double (720k) *)

PROCEDURE FormatDisk*(drive: LONGINT;  fmt: CHAR);
VAR
	error: ARRAY 32 OF CHAR;  head, track, i, div: LONGINT;  phys: BOOLEAN;  buf: ARRAY 512 OF CHAR;
	dev: Device;
BEGIN {EXCLUSIVE}
	dev := device[drive];
	error := "Format not supported";
	CASE fmt OF
		"H", "h":	(* 1.44M *)
			IF dev.type < T1440 THEN HALT(99) END;
			dev.media := T1440;
			div := 1
		|"D", "d":	(* 720k *)
			IF dev.type < T720 THEN HALT(99) END;
			dev.media := T720;
			div := 2
	END; (* CASE *)
	phys := (CAP(fmt) = fmt);
		(* format & verify *)
	error := "Format or verify error";
	SetParams(dev);
	FOR track := 0 TO dev.tracks-1 DO
		FOR head := 0 TO dev.heads-1 DO
			IF phys & (Do(dev, Format, 0, head, track, dev.sectors, buf) # Ok) THEN HALT(99) END;
			IF Do(dev, Verify, 1, head, track, dev.sectors, buf) # Ok THEN HALT(99) END
		END
	END;
		(* init boot sector *)
	FOR i := 0 TO 511 DO buf[i] := 0X END;
	buf[0CH] := 2X;	(* 512 bytes per sector *)
	buf[0DH] := 1X;	(* sectors per cluster *)
	buf[0EH] := 1X;	(* reserved sectors *)
	buf[10H] := 2X;	(* number of FAT copies *)
	buf[11H] := CHR(224 DIV div);	(* number of root dir entries *)
	buf[13H] := CHR(dev.size MOD 100H);
	buf[14H] := CHR(dev.size DIV 100H);
	IF div = 2 THEN buf[15H] := 0F9X ELSE buf[15H] := 0F0X END;
	IF div = 2 THEN buf[16H] := 3X ELSE buf[16H] := 9X END;
	buf[18H] := CHR(dev.sectors);
	buf[1AH] := CHR(dev.heads);
		(* write boot sector *)
	IF Do(device[drive], Write, 1, 0, 0, 1, buf) # Ok THEN HALT(99) END
END FormatDisk;

(* StopMotor - Switch off diskette motor *)

PROCEDURE StopMotor(drive: LONGINT);
BEGIN
	device[drive].media := T0;	(* reset media type *)
	SYSTEM.PORTOUT(3F2H, 0CX);	(* all motors off *)
	motor := FALSE
END StopMotor;

PROCEDURE StrToInt(s: ARRAY OF CHAR): LONGINT;
VAR i: SHORTINT;  v: LONGINT;
BEGIN
	v := 0;  i := 0;
	WHILE s[i] # 0X DO v := v*10+(ORD(s[i])-48); INC(i) END;
	RETURN v
END StrToInt;

PROCEDURE Init;
VAR s: ARRAY 12 OF CHAR;  b10, b14: INTEGER;
BEGIN
	Kernel.GetConfig("TraceDiskette", s);
	IF s[0] # 0X THEN trace := SHORT(ORD(s[0])-ORD("0")) ELSE trace := 0 END;
	curdrive := -1;  curtrack := -1;  motor := FALSE;  interrupt := FALSE;  state := Reset;
	Kernel.GetConfig("Diskette", s);
	IF s = "" THEN
		b10 := ORD(AosBoot.GetNVByte(10H));
		b14 := ORD(AosBoot.GetNVByte(14H))
	ELSE
		b10 := SHORT(StrToInt(s) MOD 100H);
		b14 := SHORT(ASH(StrToInt(s), -8))
	END;
	IF trace > 0 THEN
		Kernel.WriteString("Diskette config:");  Kernel.WriteHex(b10, -3);
		Kernel.WriteHex(b14, -3);  Kernel.WriteLn
	END;
		(* look at drive 0 setup *)
	NEW(device[0]);  device[0].drive := 0;
	CASE ASH(b10, -4) OF
		3: device[0].type := T720
		|4: device[0].type := T1440
		|5: device[0].type := T2880
		ELSE device[0].type := T0
	END;
	device[0].media := T0;
		(* look at drive 1 setup, if present *)
	IF ODD(ASH(b14, -6)) THEN
		NEW(device[1]);  device[1].drive := 1;
		CASE b10 MOD 16 OF
			3: device[1].type := T720
			|4: device[1].type := T1440
			|5: device[1].type := T2880
			ELSE device[1].type := T0
		END;
		device[1].media := T0
	(*ELSE device[1].type := T0*)
	END
END Init;

PROCEDURE Register;
VAR i, res: LONGINT; dev: Device; name: AosPlugins.Name;
BEGIN
	FOR i := 0 TO MaxDevices-1 DO
		dev := device[i];
		IF dev # NIL THEN
			name := "Diskette0"; name[8] := CHR(48 + i);
			dev.SetName(name); dev.desc := "Standard Diskette";
			dev.blockSize := BS; dev.flags := {Disks.Removable};
			Disks.registry.Add(dev, res);
			ASSERT(res = AosPlugins.Ok)
		END
	END
END Register;

(** Install the diskette devices.  Automatically executed when the module is loaded. *)
PROCEDURE Install*;
BEGIN {EXCLUSIVE}
	IF ~installed & (dmabufphys # 0) THEN
		Init;
		SYSTEM.PORTOUT(3F2H, 0CX);	(* motors off, select drive 0, clear reset *)
		AosInterrupts.InstallHandler(InterruptHandler, AosInterrupts.IRQ0+6);
		Register;
		installed := TRUE
	END
END Install;

(** Remove the diskette devices.  Automatically executed when the module is unloaded. *)
PROCEDURE Remove*;
VAR i: LONGINT;
BEGIN {EXCLUSIVE}
	IF installed & (AosModules.shutdown = AosModules.None) THEN
		FOR i := 0 TO MaxDevices-1 DO
			IF device[i] # NIL THEN
				Disks.registry.Remove(device[i]);
				StopMotor(device[i].drive);
				device[i] := NIL
			END
		END;
		AosInterrupts.RemoveHandler(InterruptHandler, AosInterrupts.IRQ0+6);
		installed := FALSE
	END
END Remove;

BEGIN
	dmabufsize := AosBoot.dmaSize;
	IF dmabufsize > 0 THEN
		dmabufphys := AosBoot.lowTop;
		AosMemory.MapPhysical(dmabufphys, dmabufsize, dmabufvirt)
	ELSE
		dmabufphys := 0
	END;
	AosModules.InstallTermHandler(Remove);
	installed := FALSE; Install
END Diskettes.

(*
Results
-5	Disks.MediaMissing, transfer attempted on unlocked device
0	Disks.Ok, no error
1001	already locked
1002	was not locked
1003	bad number of sectors
1004	invalid track
1005	invalid head
1006	read failed
1007	write failed
1008	reset failed
1009	specify failed
1010	too many retries

Diskettes.Install
Diskettes.Remove

System.Free Diskettes ~

Partitions.Show

to do:
o should not import Kernel
o name should be AosDiskettes
o clean up Format
*)
