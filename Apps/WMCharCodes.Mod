MODULE WMCharCodes; (** AUTHOR "TF"; PURPOSE "Convert encoded byte arrays to UTF8 arrays"; *)
(* quick and dirty implementation to test GB2312 in the webbrowser *)


IMPORT
	Utilities, UTF8Strings, AosFS, AosIO, AosOut;

TYPE
	ToUTF8Array = PROCEDURE (from : Utilities.String) : Utilities.String;
	
VAR
	gb2312Table : ARRAY 65536 OF LONGINT;
	
PROCEDURE GB2312ToUTF8*(from : Utilities.String) : Utilities.String;
VAR buf : Utilities.Buffer;
	w : AosIO.Writer;
	temp : ARRAY 8 OF CHAR;
	i, code, len : LONGINT;
BEGIN
	NEW(buf, LEN(from) * 2);
	w := buf.GetWriter();
	i := 0;
	WHILE i < LEN(from) - 1 DO 
		code := ORD(from[i]) * 256 + ORD(from[i + 1]);
		INC(i, 2);
		IF UTF8Strings.EncodeChar(gb2312Table[code MOD 10000H], temp, len) THEN
			w.String(temp)
		ELSE
			w.Char("*")
		END;		
	END;
	RETURN buf.GetString()
	
END GB2312ToUTF8;

(*
PROCEDURE MakeCodePage*(par : ANY) : ANY;
VAR f : AosFS.File;
	r : AosFS.Reader;
	codeS, unicodeS : ARRAY 8 OF CHAR;
	code, unicode, res : LONGINT;
BEGIN
	f := AosFS.Old("gb2312.txt");
	AosFS.OpenReader(r, f, 0);
	WHILE r.res = 0 DO
		IF r.Peek() = "#" THEN r.SkipLn 
		ELSE
			IF r.Peek() = "0" THEN
				r.Token(codeS); r.SkipWhitespace; r.Token(unicodeS); r.SkipLn;
				Utilities.Delete(codeS, 0, 2);
				Utilities.HexStrToInt(codeS, code, res);
				Utilities.Delete(unicodeS, 0, 2);
				Utilities.HexStrToInt(unicodeS, unicode, res);
			END;
		END;
	END;
END MakeCodePage;
*)

PROCEDURE LoadGBTable;
VAR f : AosFS.File;
	r : AosFS.Reader;
	codeS, unicodeS : ARRAY 8 OF CHAR;
	code, unicode, res : LONGINT;
BEGIN
	f := AosFS.Old("gb2312.txt");
	AosFS.OpenReader(r, f, 0);
	WHILE r.res = 0 DO
		IF r.Peek() = "#" THEN r.SkipLn 
		ELSE
			IF r.Peek() = "0" THEN
				r.Token(codeS); r.SkipWhitespace; r.Token(unicodeS); r.SkipLn;
				Utilities.Delete(codeS, 0, 2);
				Utilities.HexStrToInt(codeS, code, res);
				Utilities.Delete(unicodeS, 0, 2);
				Utilities.HexStrToInt(unicodeS, unicode, res);
				gb2312Table[code MOD 10000H] := unicode;
			ELSE r.SkipLn;
			END;
		END;
	END;
END LoadGBTable;

BEGIN
	LoadGBTable;

END WMCharCodes.

WMCharCodes.MakeCodePage ~

S.Free WMCharCodes ~

