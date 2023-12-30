MODULE Presentation; (** AUTHOR "TF"; PURPOSE "Dia-Show"; *)

IMPORT AosCommands, AosOut, WM := WMWindowManager, Graphics := WMGraphics, AosFS, Raster, WMTransitions,
	Utilities, WMDialogs;

TYPE
	Slide = POINTER TO RECORD 
		img : Graphics.Image;
		text, keywords : Utilities.String;
		next, prev : Slide;
	END;	
	
	PWin = OBJECT (WM.BufferWindow)
	VAR	
		current : Slide;
		transition : WMTransitions.TransitionFade;
		fadeImage : Raster.Image;
		bigPointer : WM.PointerInfo;
		showPointer : BOOLEAN;
		
		PROCEDURE &New;
		BEGIN
			Init(1024, 768, FALSE);
			NEW(fadeImage); Raster.Create(fadeImage, 1024, 768, Raster.BGR565);
			NEW(transition);
			manager := WM.GetDefaultManager();
			SetPointerInfo(manager.pointerNull);
			WM.LoadCursor("pointer.png", 0, 0, bigPointer);
			showPointer := FALSE;
		END New;
		
		PROCEDURE Start;
		BEGIN 
			current := head.next;
			IF current = tail THEN AosOut.String("not correctly inserted"); RETURN END;
			manager := WM.GetDefaultManager();
			manager.Add(0, 0, SELF, {}); manager.SetFocus(SELF);			
			DrawImg(FALSE)
		END Start;
		
		PROCEDURE TogglePointer;
		BEGIN
			IF showPointer THEN 
				SetPointerInfo(manager.pointerNull);
				showPointer := FALSE
			ELSE
				SetPointerInfo(bigPointer);
				showPointer := TRUE
			END
		END TogglePointer;
		
		
		PROCEDURE DrawImg(fade : BOOLEAN);
		VAR w, h, i : LONGINT;
		BEGIN
			IF current = NIL THEN AosOut.String("current is nil"); RETURN; END;
			IF (current # tail) & (current # head) THEN 
				IF fade THEN 
					FOR i := 1 TO 14 DO
						IF current.prev # head THEN 
							transition.CalcImage(current.prev.img, current.img, fadeImage, i * 18);
							canvas.DrawImage(0, 0, fadeImage, Graphics.ModeCopy);
							Invalidate(Graphics.MakeRectangle(0, 0, img.width, img.height))					
						END;
					END;
				END;
				canvas.DrawImage(0, 0, current.img, Graphics.ModeCopy);
				IF (current.text # NIL) & (current.text^ # "") THEN
					canvas.SetColor(Graphics.White);
					canvas.DrawString(10, 750, current.text^);
				END;
				Invalidate(Graphics.MakeRectangle(0, 0, img.width, img.height))
			END;
		END DrawImg;
		
		PROCEDURE Next(fade : BOOLEAN);
		BEGIN
			IF current.next # tail THEN current := current.next END;
			DrawImg(fade)
		END Next;
		
		PROCEDURE Prev;
		BEGIN 
			IF current.prev # head THEN current := current.prev END;
			DrawImg(FALSE)
		END Prev;
		
		PROCEDURE Search;
		VAR mini : WMDialogs.MiniStringInput;
			c : Slide;
			searchtext : ARRAY 32 OF CHAR;
		BEGIN
			NEW(mini);
			IF mini.Show(200, 200, searchtext) = WMDialogs.ResOk THEN
				c := head.next;
				WHILE (c # tail) & (c.text # NIL) & (Utilities.Pos(searchtext, c.text^) < 0) &
					(c.keywords # NIL) & (Utilities.Pos(searchtext, c.keywords^) < 0) DO c := c.next END;
				IF c # tail THEN current := c; DrawImg(FALSE) END;
			END;
		END Search;
		
		PROCEDURE KeyEvent(ucs : LONGINT; flags:SET; keySym:LONGINT);
		BEGIN
			IF (keySym = 0FF53H) OR (keySym = 0FF0DH) THEN Next(FALSE)
			ELSIF (keySym = 00020H) THEN Next(TRUE)
			ELSIF keySym = 0FF51H THEN Prev 
			ELSIF keySym = 0FF1BH THEN manager.Remove(SELF)
			ELSIF keySym = 0FFC0H THEN Search
			ELSIF keySym = 0FFBEH THEN TogglePointer
			END
		END KeyEvent;
		
	END PWin;
	
VAR head, tail:Slide;

PROCEDURE Clear*(par: PTR): PTR;	
BEGIN{EXCLUSIVE}
	head.next:=tail; tail.prev:=head;
	RETURN NIL
END Clear;

PROCEDURE AddSlide(name, text, keywords : ARRAY OF CHAR);
VAR new : Slide;
		dx, dy, w, h : LONGINT;
		timg, img : Graphics.Image;
		bc : Graphics.BufferCanvas;
BEGIN
	timg := Graphics.LoadImage(name, TRUE);
	NEW(img); Raster.Create(img, 1024, 768, Raster.BGR565);
	NEW(bc, img);
	bc.DrawImage(0, 0, timg, Graphics.ModeCopy);
	AosOut.String(name); AosOut.String(" ");
	IF img # NIL THEN 	
		NEW(new);
		new.text := Utilities.NewString(text); 
		new.keywords := Utilities.NewString(keywords); 
		new.prev := tail.prev; tail.prev.next := new; new.next := tail; tail.prev := new;
		new.img := img
	ELSE AosOut.String(" not loaded!"); AosOut.Ln;
	END;
END AddSlide;

PROCEDURE LoadSlides*(par : PTR) : PTR;	
VAR p : AosCommands.Parameters;		
		name:ARRAY 256 OF CHAR;
		i, j:LONGINT;
BEGIN {EXCLUSIVE}
	p := par(AosCommands.Parameters);
	WHILE (i < LEN(p.str^)) & (p.str[i] # 0X) DO 
		j := 0;
		WHILE (p.str[i] # " ") & (p.str[i] # 0X) & (i < LEN(name)-1) DO name[j] := p.str[i]; INC(i); INC(j) END;
		name[j]:=0X;	
		AddSlide(name, "", "");
		INC(i)
	END;
	RETURN NIL
END LoadSlides;

PROCEDURE Load*(par : PTR) : PTR;
VAR p : AosCommands.Parameters;		
		name, text, keywords : ARRAY 256 OF CHAR;
		ch : CHAR;
		pf : AosFS.File; r : AosFS.Reader;
		i : LONGINT;
BEGIN {EXCLUSIVE}
	head.next:=tail; tail.prev:=head; (* empty slides *)
	p := par(AosCommands.Parameters);
	WHILE (p.str[i] # " ") & (p.str[i] # 0X) & (i < LEN(name) - 1) DO name[i] := p.str[i]; INC(i) END;
	pf := AosFS.Old(name);
	IF pf # NIL THEN 
		AosFS.OpenReader(r, pf, 0);
		WHILE r.res = 0 DO 
			r.String(name); r.SkipWhitespace;
			r.String(text);r.SkipWhitespace;
			r.String(keywords); r.SkipLn;
			IF i # 0 THEN AddSlide(name, text, keywords) END
		END;
	END;
	RETURN NIL
END Load;

PROCEDURE Go*(par: PTR): PTR;
VAR pw : PWin;		
BEGIN {EXCLUSIVE}
	NEW(pw);
	pw.Start;
	RETURN NIL
END Go;

BEGIN
	NEW(head); NEW(tail); head.next:=tail; head.prev:=head; tail.prev:=head; tail.next:=tail
END Presentation.

S.Free Presentation ~

(RembrandtDoc)
ImageDocs.Open ^

Presentation.LoadSlides Bart.Pict ~

Presentation.Go~

Presentation.Clear~

Presentation.Load Aos.txt ~

