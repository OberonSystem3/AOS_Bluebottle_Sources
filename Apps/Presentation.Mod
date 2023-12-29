MODULE Presentation; (** AUTHOR "TF"; PURPOSE "Dia-Show"; *)

IMPORT AosCommands, AosOut, WM := WMWindowManager, Graphics := WMGraphics, AosFS;

TYPE
	Slide = POINTER TO RECORD 
		img : Graphics.Image;
		next, prev : Slide;
	END;	
	
	PWin = OBJECT (WM.BufferWindow)
	VAR	
		current : Slide;
		
		PROCEDURE &New;
		BEGIN
		(*	Init(view.range.r - view.range.l, view.range.b - view.range.t, FALSE); *)
			Init(1280, 1024, FALSE);
			manager := WM.GetDefaultManager();
			SetPointerInfo(manager.pointerNull)
		END New;
		
		PROCEDURE Start;
		BEGIN 
			current := head.next;
			IF current = tail THEN AosOut.String("not correctly inserted"); RETURN END;
			manager := WM.GetDefaultManager();
			manager.Add(0, 0, SELF, {}); manager.SetFocus(SELF);			
			DrawImg
		END Start;
		
		PROCEDURE DrawImg;
		VAR w, h : LONGINT;
		BEGIN
			IF current = NIL THEN AosOut.String("current is nil"); RETURN; END;
			IF (current # tail) & (current # head) THEN 
				canvas.DrawImage(0, 0, current.img, Graphics.ModeCopy);
				Invalidate(Graphics.MakeRectangle(0, 0, img.width, img.height))
			END;
		END DrawImg;
		
		PROCEDURE Next;
		BEGIN
			IF current.next # tail THEN current := current.next END;
			DrawImg
		END Next;
		
		PROCEDURE Prev;
		BEGIN 
			IF current.prev # head THEN current := current.prev END;
			DrawImg
		END Prev;
		
		PROCEDURE KeyEvent(ucs : LONGINT; flags:SET; keySym:LONGINT);
		BEGIN
			IF (keySym = 0FF53H) OR (keySym = 0FF0DH) OR (keySym = 00020H) THEN Next
			ELSIF keySym = 0FF51H THEN Prev 
			ELSIF keySym = 0FF1BH THEN manager.Remove(SELF)
			END
		END KeyEvent;
		
	END PWin;
	
VAR head, tail:Slide;

PROCEDURE Clear*(par: PTR): PTR;	
BEGIN{EXCLUSIVE}
	head.next:=tail; tail.prev:=head;
	RETURN NIL
END Clear;

PROCEDURE AddSlide(name : ARRAY OF CHAR);
VAR new : Slide;
		dx, dy, w, h : LONGINT;
		img : Graphics.Image;
BEGIN
	img := Graphics.LoadImage(name, TRUE);
	AosOut.String(name); AosOut.String(" ");
	IF img # NIL THEN 	
		NEW(new);
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
		AddSlide(name);
		INC(i)
	END;
	RETURN NIL
END LoadSlides;

PROCEDURE Load*(par : PTR) : PTR;
VAR p : AosCommands.Parameters;		
		name : ARRAY 256 OF CHAR;
		ch : CHAR;
		pf : AosFS.File; pr : AosFS.Rider;
		i : LONGINT;
BEGIN {EXCLUSIVE}
	head.next:=tail; tail.prev:=head; (* empty slides *)
	p := par(AosCommands.Parameters);
	WHILE (p.str[i] # " ") & (p.str[i] # 0X) & (i < LEN(name) - 1) DO name[i] := p.str[i]; INC(i) END;
	pf := AosFS.Old(name);
	IF pf # NIL THEN 
		pf.Set(pr, 0);
		REPEAT 
			REPEAT
				pf.Read(pr, ch)
			UNTIL (ch # " ") & (ch # 0AX) & (ch # 0DX) & (ch # 9X);
			i := 0;
			WHILE (ch  #" ") & (ch # 0X) & (ch # '~') & (~pr.eof) & (ch # 0AX) & (ch # 0DX) & (ch # 9X) DO
				name[i] := ch; INC(i); pf.Read(pr, ch)
			END;
			name[i] := 0X;
			IF i # 0 THEN AddSlide(name) END
		UNTIL pr.eof OR (i = 0)
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

System.Free Presentation ~

(RembrandtDoc)
ImageDocs.Open ^

Aos.Call Presentation.LoadSlides Bart.Pict ~

Aos.Call Presentation.Go~

Aos.Call Presentation.Clear~

ET.OpenAscii Aos.txt ~

Aos.Call Presentation.Load Aos.txt ~

