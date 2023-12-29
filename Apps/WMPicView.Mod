MODULE WMPicView;	(** AUTHOR "tf"; PURPOSE "Open a window with a picture..."; *)
IMPORT
	AosIO, AosCommands, Raster, WM := WMWindowManager, Util := TFClasses, 
	Messages := WMMessages, Rectangles := WMRectangles, AosModules, AosOut;
	
TYPE PW*= OBJECT(WM.BufferWindow)

			PROCEDURE &Init(w, h:LONGINT; alpha:BOOLEAN);
			BEGIN
				Init^(w, h, alpha);
				WM.DefaultAddWindow(SELF)
			END Init;
			
			PROCEDURE Close();
			BEGIN
				Close^;
				openList.Remove(SELF); 
			END Close;
		END PW;
		
VAR openList : Util.List;		
		
PROCEDURE Open*(par: PTR): PTR;
VAR s: AosCommands.Parameters;
		name : ARRAY 100 OF CHAR;
		sr : AosIO.StringReader;
		done : BOOLEAN;
		
		img : Raster.Image;
		mode : Raster.Mode;
		pw : PW;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.String(name);
	
	NEW(img); Raster.Load(img, name, done);
	IF done THEN
		NEW(pw, img.width, img.height, TRUE);
		pw.SetTitle(WM.NewString(name));
		Raster.InitMode(mode, Raster.srcCopy);
		Raster.Copy(img, pw.img, 0, 0, img.width, img.height, 0, 0, mode);
		pw.Invalidate(Rectangles.MakeRect(0, 0, img.width, img.height));
	END;
	RETURN NIL
END Open;

PROCEDURE Cleanup;
VAR p : PTR; m : Messages.Message; has : BOOLEAN;
BEGIN
	m.msgType := Messages.MsgClose;
	REPEAT
		has := openList.GetCount() > 0;
		IF has THEN 
			p := openList.GetItem(0); p(WM.Window).manager.Remove(p(WM.Window));
			openList.Remove(p)
		END	
	UNTIL ~has;
END Cleanup;

BEGIN
	NEW(openList);
	AosModules.InstallTermHandler(Cleanup)
END WMPicView.


S.Free WMPicView~
WMPicView.Open BluebottlePic0.png ~