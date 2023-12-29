MODULE WPM; (** AUTHOR "TF"; PURPOSE "WebPageMaker"; *)

IMPORT
	AosIO, AosCommands, Texts := AosTexts, TextUtils := AosTextUtilities, UTF8Strings, AosOut, Utilities;
	
TYPE Text = Texts.Text;
	Char32 = LONGINT;

CONST
	contentBegin = "<!-- start -->";
	contentEnd = "<!-- stop -->";
	titleBegin = "<title>"; 
	titleEnd = "</title>";
	
	titlePlace = "%title%";
	contentPlace = "%content%";
	changedatePlace = "%changedate%";
	
VAR template : Text;

PROCEDURE ReplaceString(text : Text; search : ARRAY OF CHAR; replace : Text; sfrom, slen : LONGINT);
VAR pos, len : LONGINT;
	xs : ARRAY 128 OF LONGINT;
BEGIN
	text.AcquireWrite;
	pos := 0; UTF8Strings.UTF8toUnicode(search, xs, pos);
	len := TextUtils.UCS32StrLength(xs);
	REPEAT
		pos := TextUtils.Pos(xs, 0, text);
		IF pos >= 0 THEN text.Delete(pos, len); replace.CopyToText(sfrom, slen, text, pos) END	
	UNTIL pos < 0;
	text.ReleaseWrite
END ReplaceString;

PROCEDURE UTFUCS(src : ARRAY OF CHAR; VAR dst : ARRAY OF LONGINT);
VAR pos : LONGINT;
BEGIN
	pos := 0; UTF8Strings.UTF8toUnicode(src, dst, pos)
END UTFUCS;

PROCEDURE MergeWithTemplate(template, src, date : Text; VAR dst : Text);
VAR tb, te, cb, ce, pos : LONGINT; str : ARRAY 32 OF LONGINT;
BEGIN
	NEW(dst);
	template.AcquireRead; src.AcquireRead; dst.AcquireWrite;
	
	(* copy template to dst *)
	template.CopyToText(0, template.GetLength(), dst, 0);
	
	(* find title *)
	UTFUCS(titleBegin, str); tb := TextUtils.Pos(str, 0, src); IF tb > 0 THEN INC(tb, TextUtils.UCS32StrLength(str)) END;
	UTFUCS(titleEnd, str); te := TextUtils.Pos(str, 0, src);
	IF (tb >= 0) & (tb < te) THEN ReplaceString(dst, titlePlace, src, tb, te - tb) END;
	
	(* find content *)
	UTFUCS(contentBegin, str); cb := TextUtils.Pos(str, 0, src); IF cb > 0 THEN INC(cb, TextUtils.UCS32StrLength(str)) END;
	UTFUCS(contentEnd, str); ce := TextUtils.Pos(str, 0, src);
	IF (cb >= 0) & (cb < ce) THEN ReplaceString(dst, contentPlace, src, cb, ce - cb) END;
	
	IF date # NIL THEN date.AcquireRead; ReplaceString(dst, changedatePlace, date, 0, date.GetLength()); date.ReleaseRead END;
	template.ReleaseRead; src.ReleaseRead; dst.ReleaseWrite; 
END MergeWithTemplate;

(** template srcdir dstdir name {name} *)
PROCEDURE Replace*(par : PTR) : PTR; 
VAR srcdir, dstdir, src, dst, name, template, tdate : ARRAY 128 OF CHAR;
	s: AosCommands.Parameters;
	sr : AosIO.StringReader;
	templateT, srcT, dstT, dateT : Text;
	res : LONGINT;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.Token(template); sr.SkipWhitespace; sr.Token(srcdir); sr.SkipWhitespace; sr.Token(dstdir); sr.SkipWhitespace;
	NEW(templateT);
	TextUtils.LoadUTF8(templateT, template, res); ASSERT(res = 0);
	Utilities.DateToStr(Utilities.Now(), tdate); NEW(dateT); TextUtils.StrToText(dateT, 0, tdate);
	sr.Token(name); sr.SkipWhitespace;
	WHILE sr.res = 0 DO
		AosOut.String("Processing "); AosOut.String(name); 
		NEW(srcT); NEW(dstT);
		
		COPY(srcdir, src); Utilities.Append(src, name);
		COPY(dstdir, dst); Utilities.Append(dst, name);
		TextUtils.LoadUTF8(srcT, src, res);
		IF res = 0 THEN 
			MergeWithTemplate(templateT, srcT, dateT, dstT);
			TextUtils.ExportUTF8(dstT, dst, res); ASSERT(res = 0);
			AosOut.String(" --> "); AosOut.String(dst); AosOut.String(" done."); AosOut.Ln;
		ELSE
			AosOut.String('"'); AosOut.String(src); AosOut.String('"'); AosOut.String(" not found."); AosOut.Ln
		END;
		sr.Token(name); sr.SkipWhitespace
	END;	
	RETURN NIL;
END Replace;

END WPM.
 

System.Free WPM AosTextUtilities AosTexts ~
