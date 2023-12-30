MODULE WMPicView;	(** AUTHOR "tf"; PURPOSE "Open a window with a picture..."; *)

IMPORT
	AosCommands, AosIO, Utilities, AosCodecs, AosOut, Raster, AosFS,
	WM := WMWindowManager;

PROCEDURE Open*(par: PTR): PTR; (** filename ~ *)
VAR fn, name : AosFS.FileName;
	pw : WM.BufferWindow;
	res, w, h, x : LONGINT;
	dec : AosCodecs.ImageDecoder;
	rdr : AosIO.Reader;
	ext : ARRAY 16 OF CHAR;
	sr : AosIO.StringReader;
BEGIN
	AosCommands.PosPar(par, sr);
	AosCommands.GetTok(sr, fn);
	Utilities.Trim(fn, '"');
	Utilities.GetExtension(fn, name, ext);
	Utilities.UpperCase(ext);
	dec := AosCodecs.GetImageDecoder(ext);
	IF dec = NIL THEN
		AosOut.String("WMPicView: No decoder found for "); AosOut.String(ext); AosOut.Ln;
		RETURN NIL
	END;
	rdr := AosCodecs.OpenInputStream(fn);
	IF rdr # NIL THEN
		dec.Open(rdr, res);
		IF res = 0 THEN
			dec.GetImageInfo(w, h, x, x);
			NEW(pw, w, h, TRUE);
			dec.Render(pw.img);
			WM.DefaultAddWindow(pw);
		ELSE
			AosOut.String("WMPicView: Could not open decoder for file "); AosOut.String(fn); AosOut.Ln;
		END;
	ELSE
		AosOut.String("WMPicView: Could not open inputstream for file "); AosOut.String(fn); AosOut.Ln;
	END;
	RETURN NIL
END Open;

PROCEDURE Convert*(par: PTR): PTR;
VAR fni, fno,
	inName, outName : AosFS.FileName;
	res : LONGINT;
	dec : AosCodecs.ImageDecoder;
	enc : AosCodecs.ImageEncoder;
	img : Raster.Image;
	rdr : AosIO.Reader;
	outX, inX : ARRAY 16 OF CHAR;
	f : AosFS.File;
	w : AosFS.Writer;
	sr : AosIO.StringReader;
BEGIN
	AosCommands.PosPar(par, sr);
	sr.String(fni);
	Utilities.GetExtension(fni, inName, inX);
	Utilities.UpperCase(inX);

	AosCommands.GetTok(sr, fno);
	Utilities.GetExtension(fno, outName, outX);
	Utilities.UpperCase(outX);

	dec := AosCodecs.GetImageDecoder(inX);
	IF dec = NIL THEN
		AosOut.String("No decoder found for "); AosOut.String(inX); AosOut.Ln;
		RETURN NIL
	END;

	enc := AosCodecs.GetImageEncoder(outX);
	IF enc = NIL THEN
		AosOut.String("No encoder found for "); AosOut.String(outX); AosOut.Ln;
		RETURN NIL
	END;

	rdr := AosCodecs.OpenInputStream(fni);
	IF rdr # NIL THEN
		dec.Open(rdr, res);
		IF res = 0 THEN
			dec.GetNativeImage(img);

			f := AosFS.New(fno);
			AosFS.OpenWriter(w, f, 0);
			enc.Open(w);
			enc.WriteImage(img, res);
			IF res = 0 THEN
				AosFS.Register(f);
				AosOut.String("Done");
			ELSE
				AosOut.String("Not converted");
			END
		END
	END;
	RETURN NIL
END Convert;

END WMPicView.

S.Free WMPicView ~
WMPicView.Open  	errorpos.png ~
WMPicView.Convert BluebottlePic0.png temp.gif ~