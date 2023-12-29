MODULE AosFTP;

IMPORT
	AosFTPClient, AosOut, AosCommands, AosIO, AosFS, AosTexts, AosTextUtilities;
	
CONST
	BufSize = 16*1024; (* internal buffer size, used for file transfer *)
	
	LocalFileNotFound = -2;
	
VAR ftp : AosFTPClient.FTPClient;
	
PROCEDURE PutFile(ftp : AosFTPClient.FTPClient; local, remote : ARRAY OF CHAR; VAR res : LONGINT);
VAR buf: ARRAY BufSize OF CHAR; len: LONGINT;
	f : AosFS.File; r : AosFS.Reader;
	w : AosIO.Writer;
BEGIN
	f := AosFS.Old(local);
	IF f = NIL THEN res := LocalFileNotFound; RETURN END;
	AosFS.OpenReader(r, f, 0);
	
	ftp.OpenPut(remote, w, res);
	IF res = 0 THEN
		REPEAT
			r.Bytes(buf, 0, BufSize, len); w.Bytes(buf, 0, len);
		UNTIL r.res # 0;
		w.Update;
		ftp.ClosePut(res);
	END;
END PutFile;

PROCEDURE PutText(ftp : AosFTPClient.FTPClient; local, remote : ARRAY OF CHAR; VAR res : LONGINT);
VAR w : AosIO.Writer;
        text: AosTexts.Text;
        r: AosTexts.TextReader;
        ch: AosTexts.Char32;
        i: LONGINT;
BEGIN
        NEW(text);
        AosTextUtilities.LoadOberonText(text, local, res);
        IF res # 0 THEN res:= LocalFileNotFound; RETURN END;
        text.AcquireRead;
        NEW(r, text);
        ftp.OpenPut(remote, w, res);
        IF res = 0 THEN
		FOR i := 0 TO text.GetLength() - 1 DO
			r.ReadCh(ch);
			IF (ch >= 0) & (ch < 128) THEN w.Char(CHR(ch)) END;
		END;
		w.Update;
		ftp.ClosePut(res)
	END;
	text.ReleaseRead
END PutText;

PROCEDURE GetFile(ftp : AosFTPClient.FTPClient; remote, local : ARRAY OF CHAR; VAR res : LONGINT);
VAR buf: ARRAY BufSize OF CHAR; len: LONGINT;
	f : AosFS.File; w : AosFS.Writer;
	r : AosIO.Reader;
BEGIN
	
	f := AosFS.New(local);
	AosFS.OpenWriter(w, f, 0);
	
	ftp.OpenGet(remote, r, res);
	IF res = 0 THEN
		REPEAT
			r.Bytes(buf, 0, BufSize, len); w.Bytes(buf, 0, len);
		UNTIL r.res # 0;
		w.Update;
		AosFS.Register(f);
		ftp.CloseGet(res)
	END;
END GetFile;

PROCEDURE Open*(par : ANY) : ANY;
VAR s: AosCommands.Parameters;
	sr : AosIO.StringReader;
	host, user, password : ARRAY 256 OF CHAR;
	res : LONGINT;
BEGIN
	IF ftp # NIL THEN 
		AosOut.String("Already open"); AosOut.Ln; 
		RETURN NIL
	END;
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	AosOut.String("s.str^ = "); AosOut.String(s.str^); AosOut.Ln; 
	
	sr.SkipWhitespace; sr.String(host);
	sr.SkipWhitespace; sr.String(user);
	sr.SkipWhitespace; sr.String(password);
	
	AosOut.String("host = "); AosOut.String(host); AosOut.Ln; 
	
	AosOut.String("user = "); AosOut.String(user); AosOut.Ln; 
	AosOut.String("password = "); AosOut.String(password); AosOut.Ln; 
	
	NEW(ftp);
	ftp.Open(host, user, password, 21, res);
	AosOut.String(ftp.msg);
	IF res = 0 THEN
		AosOut.String("Connected"); AosOut.Ln; 
	ELSE
		ftp := NIL;
		AosOut.String("Connecting failed"); AosOut.Ln; 
	END;
	RETURN NIL
END Open;

PROCEDURE PutFiles*(par : ANY) : ANY;
VAR s: AosCommands.Parameters;
	sr : AosIO.StringReader;
	local, path, remote : ARRAY 256 OF CHAR;
	tok : ARRAY 8 OF CHAR;
	res : LONGINT;
BEGIN
	IF ftp = NIL THEN 	
		AosOut.String("not connected"); AosOut.Ln; 
		RETURN NIL
	END;
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	REPEAT
		sr.SkipWhitespace;
		sr.String(local);
		
		AosFS.SplitPath(local, path, remote);
		sr.SkipWhitespace;
		IF sr.Peek() = "=" THEN
			sr.Token(tok);
			IF tok # "=>" THEN
				AosOut.String("=> expected");
				RETURN NIL
			END;
			sr.SkipWhitespace;
			sr.String(remote)
		END;
		IF (local # "") & (remote # "") THEN
			PutFile(ftp, local, remote, res);
			IF res = 0 THEN AosOut.String(local); AosOut.String(" copied to "); AosOut.String(remote); AosOut.Ln
			ELSIF res = LocalFileNotFound THEN	AosOut.String("Local file "); AosOut.String(local); AosOut.String(" not found ");  AosOut.Ln
			ELSE AosOut.String("upload failed on remote file "); AosOut.String(remote); AosOut.Ln
			END;
		END	
	UNTIL sr.res # 0;
	RETURN NIL
END PutFiles;

PROCEDURE PutTexts*(par : ANY) : ANY;
VAR s: AosCommands.Parameters;
	sr : AosIO.StringReader;
	local, path, remote : ARRAY 256 OF CHAR;
	tok : ARRAY 8 OF CHAR;
	res : LONGINT;
BEGIN
	IF ftp = NIL THEN 	
		AosOut.String("not connected"); AosOut.Ln; 
		RETURN NIL
	END;
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	REPEAT
		sr.SkipWhitespace;
		sr.String(local);
		
		AosFS.SplitPath(local, path, remote);
		sr.SkipWhitespace;
		IF sr.Peek() = "=" THEN
			sr.Token(tok);
			IF tok # "=>" THEN
				AosOut.String("=> expected");
				RETURN NIL
			END;
			sr.SkipWhitespace;
			sr.String(remote)
		END;
		IF (local # "") & (remote # "") THEN
			PutText(ftp, local, remote, res);
			IF res = 0 THEN AosOut.String(local); AosOut.String(" copied to "); AosOut.String(remote); AosOut.Ln
			ELSIF res = LocalFileNotFound THEN	AosOut.String("Local file "); AosOut.String(local); AosOut.String(" not found ");  AosOut.Ln
			ELSE AosOut.String("upload failed on remote file "); AosOut.String(remote); AosOut.Ln
			END;
		END	
	UNTIL sr.res # 0;
	RETURN NIL
END PutTexts;

PROCEDURE GetFiles*(par : ANY) : ANY;
VAR s: AosCommands.Parameters;
	sr : AosIO.StringReader;
	local, path, remote : ARRAY 256 OF CHAR;
	tok : ARRAY 8 OF CHAR;
	res : LONGINT;
BEGIN
	IF ftp = NIL THEN 	
		AosOut.String("not connected"); AosOut.Ln; 
		RETURN NIL
	END;
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	REPEAT
		sr.SkipWhitespace;
		sr.String(remote);
		COPY(remote, local);
		
		sr.SkipWhitespace;
		IF sr.Peek() = "=" THEN
			sr.Token(tok);
			IF tok # "=>" THEN
				AosOut.String("=> expected");
				RETURN NIL
			END;
			sr.SkipWhitespace;
			sr.String(local)
		END;
		IF (local # "") & (remote # "") THEN
			GetFile(ftp, remote, local, res);
			IF res = 0 THEN AosOut.String(remote); AosOut.String(" downloaded to "); AosOut.String(local); AosOut.Ln
			ELSE AosOut.String("download failed on remote file "); AosOut.String(remote); AosOut.Ln
			END;
		END	
	UNTIL sr.res # 0;
	RETURN NIL
END GetFiles;

PROCEDURE ChangeDir*(par : ANY) : ANY;
VAR s: AosCommands.Parameters;
	sr : AosIO.StringReader;
	path : ARRAY 256 OF CHAR;
	res : LONGINT;
BEGIN
	IF ftp = NIL THEN 
		AosOut.String("not open"); AosOut.Ln; 
		RETURN NIL
	END;
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.String(path);
	ftp.ChangeDir(path, res);
	IF res = 0 THEN AosOut.String("Directory changed."); AosOut.Ln 
	ELSE AosOut.String("Failed changing directory."); AosOut.Ln
	END;
	
	ftp.GetCurrentDir(path, res);
	IF res = 0 THEN AosOut.String("New remote dir is : "); AosOut.String(path); AosOut.Ln END;
	RETURN NIL
END ChangeDir;

PROCEDURE Directory*(par : ANY) : ANY;
BEGIN
	IF ftp = NIL THEN 
		AosOut.String("not open"); AosOut.Ln; 
		RETURN NIL
	END;
	ftp.EnumerateDir();

	RETURN NIL
END Directory;



PROCEDURE Close*(par : ANY) : ANY;
VAR res : LONGINT;
BEGIN
	IF ftp = NIL THEN 
		AosOut.String("not connected"); AosOut.Ln; 
		RETURN NIL
	END;
	ftp.Close(res);
	AosOut.String("closed."); AosOut.String(ftp.msg); AosOut.Ln; 
	ftp := NIL;
	RETURN NIL
END Close;


END AosFTP.


AosFTP.Open "bluebottle.ethz.ch" "wwwadmin" "c5E9b%5^62"  ~
AosFTP.ChangeDir "bluebottle/downloads/crazy" 
AosFTP.PutFiles 	AosApps.zip AosAppsSrc.zip AosBuild.zip AosBuildSrc.zip AosDocu.zip AosGad.zip AosGadSrc.zip 
AosFTP.PutFiles 	AosOberon.zip AosOberonApps1.zip AosOberonApps2.zip AosOberonAppsSrc.zip AosOberonSrc.zip 
AosFTP.PutFiles 	 AosSrcP.zip AosSys.zip AosSysSrc.zip AosDefs.zip AosInst.Tool Pr3Fonts.zip AosContributions.zip 
AosFTP.PutFiles 	AosContributionsSrc.zip Pr6Fonts.zip AosIDE.Bin AosAda7.Bin AosUSB.Bin 
AosFTP.PutFiles 	AosCD.zip 
AosFTP.PutFiles 	Aos.Par  OBL.Bin WebAos.Text WebAos.html 
~	
AosFTP.Close 

AosFTP.Open portnoy.ethz.ch download oberon 
AosFTP.GetFiles WMGraphics.Mod CharacterLineup.Mod HobbesTool.Mod 




S.Free AosFTP AosFTPClient 
AosFTP.Open "bluebottle.ethz.ch" temp temp  ~
AosFTP.Open "phobos.ethz.ch" "uhbs" "hello"  ~ 
AosFTP.Directory 
AosFTP.Close 