(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE HTMLTables;	(** portable *) (* ejz,   *)
	IMPORT Display, Texts, HTMLDocs;

(** HTML 3.0 Table support.
	[HTMLTags]
	CAPTION=HTMLTables.NewCAPTION
	TABLE=HTMLTables.NewTABLE
	TD=HTMLTables.NewTD
	TH=HTMLTables.NewTH
	TR=HTMLTables.NewTR *)

	PROCEDURE *TABLE(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		(*HTMLDocs.HorzRule(S.page, Display.Width, 1)*)
	END TABLE;

	PROCEDURE *TR(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		IF on THEN
			HTMLDocs.WriteLn(S.page)
		END
	END TR;

	PROCEDURE *TH(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		IF ~on THEN
			Texts.Write(S.page.W, 09X)
		END
	END TH;

	PROCEDURE *TD(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		IF ~on THEN
			Texts.Write(S.page.W, 09X)
		END
	END TD;

	PROCEDURE *CAPTION(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
	BEGIN
		IF on THEN
			HTMLDocs.HorzRule(S.page, Display.Width, 1);
			HTMLDocs.WriteLn(S.page)
		END
	END CAPTION;

	PROCEDURE *Dummy(P: HTMLDocs.Page);
	BEGIN
	END Dummy;

	PROCEDURE NewTABLE*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := TABLE;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewTABLE;

	PROCEDURE NewTR*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := TR;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewTR;

	PROCEDURE NewTH*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := TH;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewTH;

	PROCEDURE NewTD*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := TD;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewTD;

	PROCEDURE NewCAPTION*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := CAPTION;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewCAPTION;

END HTMLTables.

"http://home.mcom.com:80/assist/net_sites/table_sample.html"
