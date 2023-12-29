MODULE AosCleanup;	(** prk / pjm **)

(* Find duplicate files on mounted file systems. *)

IMPORT
	AosFS, Texts, Oberon;

TYPE
	FileName = AosFS.FileName;
	Node = POINTER TO RECORD
		name, full: FileName;
		time, date, size: LONGINT;
		found: BOOLEAN;
		next: Node
	END;

CONST
	Color = TRUE;

VAR
	root: Node;
	w: Texts.Writer;

PROCEDURE Insert(VAR name: FileName; time, date, size: LONGINT; t: Texts.Text);
VAR prefix: FileName;  n, p: Node;  col: SHORTINT;
BEGIN
	NEW(n);
	COPY(name, n.full);
	AosFS.SplitName(name, prefix, n.name);
	n.time := time; n.date := date; n.size := size;
	p := root;
	WHILE (p.next # NIL) & (p.next.name < n.name) DO
		p := p.next
	END;
	IF (p.next # NIL) & (p.next.name = n.name) THEN
		IF ~p.next.found THEN
			p.next.found := TRUE;
			Texts.WriteString(w, p.next.full); Texts.WriteDate(w, p.next.time, p.next.date);
			Texts.Write(w, " "); Texts.WriteInt(w, p.next.size, 1); Texts.Write(w, " ");
			Texts.WriteString(w, name);
			IF (time # p.next.time) OR (date # p.next.date) OR (size # p.next.size) THEN
				Texts.WriteDate(w, time, date);
				IF Color & (size # p.next.size) THEN col := w.col; Texts.SetColor(w, 3) END;
				Texts.Write(w, " "); Texts.WriteInt(w, size, 1);
				IF Color & (size # p.next.size) THEN Texts.SetColor(w, col) END
			END;
			Texts.WriteLn(w)
		END
	ELSE
		n.next := p.next; p.next := n
	END
END Insert;

PROCEDURE FindDuplicates*;
VAR enum: AosFS.Enumerator; time, date, size: LONGINT; continue: BOOLEAN; name: FileName; t: Texts.Text; flags: SET;
BEGIN
	root.next := NIL;
	NEW(enum);
	enum.Open("", {AosFS.EnumSize, AosFS.EnumTime});
	continue := TRUE;
	WHILE enum.GetEntry(name, flags, time, date, size) DO
		Insert(name, time, date, size, t)
	END;
	enum.Close;
	NEW(t); Texts.Open(t, "");
	Texts.Append(t, w.buf);
	Oberon.OpenText("", t, 400, 400);
	root.next := NIL
END FindDuplicates;

BEGIN
	Texts.OpenWriter(w);
	NEW(root)
END AosCleanup.

AosCleanup.FindDuplicates

System.CopyFiles USER:AosRelease.Tool => AOS:AosRelease.Tool ~