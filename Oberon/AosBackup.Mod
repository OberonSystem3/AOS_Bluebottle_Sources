(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE AosBackup;	(* pjm *)

(* Based on NetBackup.Mod (protocol compatible). *)

IMPORT AosOut, AosKernel, AosIO, AosFS, AosIP, AosDNS, AosTCP, Kernel, Texts, Oberon;

CONST
	Port = 5007;	(* server port *)
	
	BufSize = 16384;
	
	CloseTimeout = 10*1000;	(* ms timeout on connection close *)
	
	FileNotFound = 1;
	ReadError = 2;

TYPE
	List = POINTER TO RECORD
		next: List;
		local, remote: AosFS.FileName;
		time, date, size: LONGINT
	END;

TYPE
	Sender = OBJECT
		VAR
			root: List; files, bytes, time: LONGINT; c: AosTCP.Connection; timer: AosKernel.MilliTimer;
			out: AosIO.Writer; buf: POINTER TO ARRAY OF CHAR;
		
		PROCEDURE &Init(list: List; server: ARRAY OF CHAR; port: LONGINT; VAR res: LONGINT);
		VAR ip: AosIP.Adr;
		BEGIN
			AosOut.String("Looking up "); AosOut.String(server); AosOut.Ln;
			AosDNS.HostByName(server, ip, res);
			IF res = 0 THEN
				AosOut.String("Connecting to "); AosIP.OutAdr(ip); AosOut.Ln;
				NEW(c); c.Open(AosTCP.NilPort, ip, port, res);
				IF res = 0 THEN
					AosIO.OpenWriter(out, c.Send);
					root := list
				ELSE
					AosIP.OutAdr(ip); AosOut.String(" connect error "); AosOut.Int(res, 1); AosOut.Ln
				END
			ELSE
				AosOut.String("DNS lookup error "); AosOut.Int(res, 1); AosOut.Ln
			END;
			IF res # 0 THEN c := NIL END
		END Init;
		
		PROCEDURE SendFile(VAR local, remote: ARRAY OF CHAR): BOOLEAN;
		VAR f: AosFS.File; r: AosFS.Rider; len, num: LONGINT; data: ARRAY 4 OF CHAR;
		BEGIN
			IF out.res = 0 THEN
				f := AosFS.Old(local);
				IF f # NIL THEN
					f.Set(r, 0); len := f.Length();
					out.RawString(remote);
					out.Char(CHR(ASH(len, -24) MOD 100H)); out.Char(CHR(ASH(len, -16) MOD 100H));
					out.Char(CHR(ASH(len, -8) MOD 100H)); out.Char(CHR(len MOD 100H));
					LOOP
						IF len > BufSize THEN num := BufSize ELSE num := len END;
						f.ReadBytes(r, buf^, 0, num); DEC(num, r.res);	(* num is how many bytes read now *)
						IF num = 0 THEN EXIT END;
						out.Bytes(buf^, 0, num);
						DEC(len, num)
					END;
					IF len # 0 THEN out.res := ReadError END;
					IF out.res = 0 THEN
						out.Update;	(* make sure server sees everything *)
						c.Receive(data, 0, 4, 4, num, out.res);	(* read result code from server *)
						IF out.res = 0 THEN
							out.res := ASH(ORD(data[0]), 24) + ASH(ORD(data[1]), 16) + ASH(ORD(data[2]), 8) + ORD(data[3])
						END
					END
				ELSE
					out.res := FileNotFound
				END
			END;
			RETURN out.res = 0
		END SendFile;

	BEGIN {ACTIVE}
		IF c # NIL THEN
			NEW(buf, BufSize);
			files := 0; AosKernel.SetTimer(timer, 0);
			WHILE (root # NIL) & SendFile(root.local, root.remote) DO
				INC(files); root := root.next
			END;
			out.RawString(""); out.Update;
			c.Close();
			IF out.res = 0 THEN
				c.AwaitState(AosTCP.ClosedStates, {}, CloseTimeout, out.res)
			END;
			time := AosKernel.Elapsed(timer);
			Kernel.LockOberon;
			IF out.res = 0 THEN
				bytes := out.sent;
				Texts.WriteString(w, "Backup completed"); Texts.WriteLn(w);
				Texts.WriteInt(w, files, 1); Texts.WriteString(w, " files sent, ");
				Texts.WriteInt(w, bytes, 1); Texts.WriteString(w, " bytes sent, ");
				Texts.WriteLongRealFix(w, time/1000.0D0, 1, 1, 0); Texts.WriteString(w, " s");
				IF time # 0 THEN
					Texts.WriteString(w, ", ");
					Texts.WriteInt(w, ENTIER((bytes/1024.0D0)/(time/1000.0D0)), 1);
					Texts.WriteString(w, "KB/s, ");
					Texts.WriteLongRealFix(w, (bytes/(1024.0D0/8*1024))/(time/1000.0D0), 1, 2, 0);
					Texts.WriteString(w, "Mb/s")
				END;
				Texts.WriteLn(w)
			ELSE
				Texts.WriteString(w, "Backup error "); Texts.WriteInt(w, out.res, 1); Texts.WriteLn(w)
			END;
			Texts.Append(Oberon.Log, w.buf);
			Kernel.UnlockOberon;
			buf := NIL
		END
	END Sender;
	
VAR
	sender: Sender;
	w: Texts.Writer;

PROCEDURE Busy(): BOOLEAN;
BEGIN
	(* to do: sync with sender and clear it when done *)
	RETURN sender # NIL
END Busy;

PROCEDURE OpenScanner(VAR S: Texts.Scanner);
VAR beg, end, time: LONGINT; text: Texts.Text;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN
		time := -1; text := NIL;
		Oberon.GetSelection(text, beg, end, time);
		IF (text # NIL) & (time >= 0) THEN
			Texts.OpenScanner(S, text, beg); Texts.Scan(S)
		END
	END
END OpenScanner;

PROCEDURE ScanPair(VAR S: Texts.Scanner; VAR name1, name2: ARRAY OF CHAR): BOOLEAN;
BEGIN
	WHILE ~(S.class IN {Texts.Name, Texts.String}) & ((S.class # Texts.Char) OR (S.c # "~")) & ~S.eot DO
		Texts.Scan(S)
	END;
	IF S.class IN {Texts.Name, Texts.String} THEN
		COPY(S.s, name1);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "=") THEN
			Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = ">") THEN
				Texts.Scan(S);
				IF S.class IN {Texts.Name, Texts.String} THEN
					COPY(S.s, name2);
					Texts.Scan(S);
					RETURN TRUE
				END
			END
		ELSE
			COPY(name1, name2);
			RETURN TRUE
		END
	END;
	RETURN FALSE
END ScanPair;

PROCEDURE StartSend(server: ARRAY OF CHAR; root: List): BOOLEAN;
VAR res: LONGINT;
BEGIN
	NEW(sender, root, server, Port, res);
	IF res = 0 THEN Texts.WriteString(w, "Sending...")
	ELSE Texts.WriteString(w, "Send error "); Texts.WriteInt(w, res, 1)
	END;
	Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf);
	RETURN res = 0
END StartSend;

PROCEDURE SendFiles*;	(** server { file [=> file] } ~ *)
VAR root, last, new: List; server: ARRAY 64 OF CHAR; S: Texts.Scanner;
BEGIN
	IF ~Busy() THEN
		OpenScanner(S);
		IF S.class IN {Texts.Name, Texts.String} THEN
			COPY(S.s, server); Texts.Scan(S);
			NEW(root); root.next := NIL; last := root;
			LOOP
				NEW(new); new.next := NIL;
				IF ~ScanPair(S, new.local, new.remote) THEN EXIT END;
				last.next := new; last := new
			END;
			IF StartSend(server, root.next) THEN END
		END
	END
END SendFiles;

(*
PROCEDURE ReceiveFiles*;	(** server { file [=> file] } ~ *)
CONST BufSize = 1024;
VAR
	res: INTEGER;  f: Files.File;  r: Files.Rider;  len, num: LONGINT;
	c: AosTCP.Connection;  name1, name2: ARRAY 64 OF CHAR;  ip: NetSystem.IPAdr;
	buf: ARRAY BufSize OF CHAR;  tnum, tlen, time: LONGINT;
	S: Texts.Scanner;
BEGIN
	OpenScanner(S);
	IF S.class IN {Texts.Name, Texts.String} THEN
		Texts.WriteString(W, "Looking up ");  Texts.WriteString(W, S.s);  Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		NetSystem.GetIP(S.s, ip);  Texts.Scan(S);
		NetSystem.OpenConnection(c, NetSystem.anyport, ip, Port, res);
		IF res # NetSystem.done THEN HALT(99) END;
		tnum := 0;  tlen := 0;  time := Input.Time();
		LOOP
			IF tnum MOD CollectFreq = 0 THEN Oberon.Collect END;
			IF ~ScanPair(S, name1, name2) THEN EXIT END;
			Texts.WriteString(W, name1);
			IF name2 # name1 THEN
				Texts.WriteString(W, " => ");  Texts.WriteString(W, name2)
			END;
			Texts.Append(Oberon.Log, W.buf);
			WriteString(c, name1);  NetSystem.WriteLInt(c, -1);
			NetSystem.ReadLInt(c, len);
			IF (c.res # NetSystem.done) OR (len < 0) THEN res := c.res;  HALT(99) END;
			Texts.Write(W, " ");  Texts.WriteInt(W, len, 1);
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
			f := Files.New(name2);  IF f = NIL THEN HALT(99) END;
			Files.Set(r, f, 0);
			LOOP
				IF len > BufSize THEN num := BufSize ELSE num := len END;
				IF num = 0 THEN
					EXIT
				ELSE
					NetSystem.ReadBytes(c, 0, num, buf);
					IF c.res # NetSystem.done THEN res := c.res;  HALT(99) END;
					Files.WriteBytes(r, buf, num);
					IF r.res # 0 THEN res := SHORT(r.res);  HALT(99) END;
					DEC(len, num);
					INC(tlen, num)
				END
			END;
			Files.Register(f);
			NetSystem.WriteLInt(c, 0);	(* result *)
			INC(tnum)
		END;
		WriteString(c, "");
		NetSystem.CloseConnection(c);
		time := Input.Time() - time;
		Texts.WriteString(W, "Files received: ");  Texts.WriteInt(W, tnum, 1);  Texts.WriteLn(W);
		Texts.WriteString(W, "Bytes received: ");  Texts.WriteInt(W, tlen, 1);  Texts.WriteLn(W);
		IF time DIV Input.TimeUnit > 1 THEN
			Texts.WriteInt(W, time DIV Input.TimeUnit, 1);
			Texts.WriteString(W, " seconds.");  Texts.WriteLn(W);
			IF tlen > MAX(LONGINT) DIV Input.TimeUnit THEN
				Texts.WriteInt(W, tlen DIV (time DIV Input.TimeUnit), 1)
			ELSE
				Texts.WriteInt(W, tlen*Input.TimeUnit DIV time, 1)
			END;
			Texts.WriteString(W, " bytes per second.");  Texts.WriteLn(W)
		END;
		Texts.Append(Oberon.Log, W.buf)
	END
END ReceiveFiles;
*)

(* Read the log: { name [time date size] } *)

PROCEDURE ReadLog(name: ARRAY OF CHAR;  VAR root: List);
VAR s: Texts.Scanner;  t: Texts.Text;  new: List;
BEGIN
	root := NIL;
	NEW(t);  Texts.Open(t, name);
	IF t.len # 0 THEN
		Texts.OpenScanner(s, t, 0);  Texts.Scan(s);
		WHILE s.class = Texts.Name DO
			NEW(new);
			COPY(s.s, new.local);
			Texts.Scan(s);
			IF s.class = Texts.Int THEN
				new.time := s.i;
				Texts.Scan(s);  ASSERT(s.class = Texts.Int);
				new.date := s.i;
				Texts.Scan(s);  ASSERT(s.class = Texts.Int);
				new.size := s.i;
				Texts.Scan(s)
			ELSE
				new.time := 0;  new.date := 0;  new.size := -1
			END;
			new.next := root;  root := new
		END
	END
END ReadLog;

PROCEDURE Inc(send: BOOLEAN);
VAR
	log, list, last: List;
	s: Texts.Scanner; logtext: Texts.Text; enum: AosFS.Enumerator; time, date, size: LONGINT;
	name: AosFS.FileName; server: ARRAY 64 OF CHAR; flags: SET;
	
	PROCEDURE AddFile(name: ARRAY OF CHAR; time, date, size: LONGINT);
	VAR p, n: List; add: BOOLEAN;
	BEGIN
		p := NIL;  n := log;  WHILE (n # NIL) & (name # n.local) DO p := n; n := n.next END;
		IF n = NIL THEN	(* not found in old log *)
			NEW(n);  COPY(name, n.local);	(* new file *)
			add := TRUE
		ELSE	(* found in old log *)
			IF p = NIL THEN log := log.next ELSE p.next := n.next END;	(* delete n from log *)
			add := (n.time # time) OR (n.date # date) OR (n.size # size)
		END;
		COPY(n.local, n.remote);	(* from/to same *)
		n.time := time;  n.date := date;  n.size := size;	(* update stamp *)
		Texts.WriteString(w, n.local);  Texts.Write(w, 9X);
		Texts.WriteInt(w, n.time, 1);  Texts.Write(w, 9X);
		Texts.WriteInt(w, n.date, 1);  Texts.Write(w, 9X);
		Texts.WriteInt(w, n.size, 1);  Texts.WriteLn(w);
		IF add THEN
			last.next := n;  n.next := NIL;  last := n
		END
	END AddFile;

BEGIN
	IF ~Busy() THEN
		log := NIL; list := NIL; last := NIL; logtext := NIL;
		Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(s);
		IF ~send OR (s.class IN {Texts.Name, Texts.String}) THEN
			IF send THEN COPY(s.s, server); Texts.Scan(s) END;
			IF s.class = Texts.Name THEN
				ReadLog(s.s, log);
				NEW(logtext); Texts.Open(logtext, "");
				NEW(list); list.next := NIL; last := list;
				NEW(enum); enum.Open("", {AosFS.EnumSize, AosFS.EnumTime});
				WHILE enum.GetEntry(name, flags, time, date, size) DO
					AddFile(name, time, date, size)
				END;
				Texts.Append(logtext, w.buf);
				enum.Close;
				IF ~send OR StartSend(server, list.next) THEN
					Oberon.OpenText(s.s, logtext, 400, 400)
				END
			END
		END
	END
END Inc;

PROCEDURE Incremental*;	(** server logtext *)
BEGIN
	Inc(TRUE)
END Incremental;

PROCEDURE LogSnapshot*;	(** logtext *)
BEGIN
	Inc(FALSE)
END LogSnapshot;

BEGIN
	Texts.OpenWriter(w)
END AosBackup.

AosBackup.SendFiles lillian t1 t2 ~
AosBackup.ReceiveFiles lillian t1=>t2 ~

!System.DeleteFiles Incremental.Log ~	# for full backup
cd ~/backup/meadow;nohup ~/c/bsrv >../backup.log &	# on lillian
AosBackup.Incremental lillian Incremental.Log ~	# store the log text if ok!
!AosBackup.LogSnapshot Incremental.Log ~	# update log without backup
