MODULE AosProfiler;	(** PRK  **)
(*
	Statistical Profiler for Aos
	
	author: P.Reali reali@inf.ethz.ch
*)

IMPORT
		AosBoot, AosInterrupts, AosProcessors, AosModules, Fonts, SYSTEM, Out, Oberon, Texts, Attributes, Objects, Gadgets, Outlines, TextGadgets;


CONST
	(* distance between tab positions*)
	Identation = 15;
	
TYPE
	Range = POINTER TO RangeDesc;
	RangeDesc = RECORD
		name: ARRAY 64 OF CHAR;
		low, hi: LONGINT;
		hits: LONGINT;	(*hits inside this range (local and not)*)
		locals: LONGINT;	(*local hits*)
		dsc, next: Range;
	END;
	
	LessThanProc = PROCEDURE (a, b: Range): BOOLEAN;
	
VAR
	(*
		Trace Format:
		[next_trace][ip0][ip1]....[ipn][next_trace][ip0][ip1]....[ipn].......
		
		next_trace points to the next trace in the list.
	*)

	trace: POINTER TO ARRAY AosBoot.MaxCPU,  8*1024 OF LONGINT;
	tracePos: ARRAY AosBoot.MaxCPU OF LONGINT;
	topM, topP: Range;
	pflag, vflag, nflag, tflag, recDump: BOOLEAN;
	normal, title: Fonts.Font;
	tab: ARRAY 32 OF CHAR;
	StyleCache: ARRAY 32 OF Objects.Object;
	stopEBP: LONGINT;
	
(* ----------- Sort Routines ---------------- *)
PROCEDURE Sort(list: Range; LessThan: LessThanProc): Range;
	VAR res, p, q: Range;
BEGIN
	WHILE list # NIL DO
		q := list.next;
		IF (res = NIL) OR LessThan(list, res) THEN
			list.next := res; res := list
		ELSE
			p := res;
			WHILE (p.next#NIL) & LessThan(p.next, list) DO	p := p.next	END;
			list.next := p.next;  p.next := list
		END;
		list := q
	END;
	RETURN res
END Sort;

PROCEDURE HitsLT(a, b: Range): BOOLEAN;
BEGIN	RETURN a.hits < b.hits
END HitsLT;

PROCEDURE HitsGT(a, b: Range): BOOLEAN;
BEGIN	RETURN a.hits > b.hits
END HitsGT;

PROCEDURE AlphaLT(a, b: Range): BOOLEAN;
BEGIN	RETURN a.name < b.name
END AlphaLT;

(* ----------- Output Routines --------------- *)
PROCEDURE CreateStyle(at: LONGINT): Objects.Object;
VAR o: TextGadgets.Style;
BEGIN
	IF (at >= LEN(StyleCache)) OR (StyleCache[at] = NIL) THEN
		o := TextGadgets.newStyle();
(*
		o.width := SHORT(o.width - at*Identation);
*)
		o.leftM := SHORT(at*Identation);
		Attributes.SetString(o, "Tabs", tab);
		IF at < LEN(StyleCache) THEN StyleCache[at] := o END;
		RETURN o
	ELSE RETURN StyleCache[at]
	END;
END CreateStyle;

PROCEDURE Write(VAR w: Texts.Writer; name: ARRAY OF CHAR; cnt, tot: LONGINT);
BEGIN
	Texts.WriteString(w, name);
	Texts.Write(w, 9X);
	Texts.WriteInt(w, cnt, 4); Texts.WriteString(w, " / "); Texts.WriteInt(w, tot, 4);
	Texts.WriteLn(w);
END Write;

PROCEDURE DumpHierarchy(top: Range; VAR w: Texts.Writer; level: LONGINT);
(*traverse the structure top and dump the results*)
	VAR tw: Texts.Writer; p: Range; outline: Outlines.Outline; sum: LONGINT;
BEGIN
	IF top = NIL THEN RETURN END;
	Write(w, top.name, top.locals, top.hits);
	top.dsc := Sort(top.dsc, HitsGT);
	
	Texts.WriteObj(w, CreateStyle(level+1));
	IF top.dsc = NIL THEN
		Texts.WriteString(w, "no outgoing calls")
	ELSE
		p := top.dsc;
		WHILE p # NIL DO
			INC(sum, p.hits);
			Write(w, p.name, p.hits, top.hits); p := p.next;
		END;
		Write(w, "local", top.locals, top.hits);
		Texts.OpenWriter(tw);
		Texts.WriteLn(tw);
		p := top.dsc;
		WHILE p # NIL DO
			DumpHierarchy(p, tw, level+1); p := p.next
		END;
		outline := Outlines.MakeOutline(Outlines.close); Texts.WriteObj(tw, outline);
		outline := Outlines.MakeOutline(Outlines.folded);
		outline.buf := tw.buf; outline.len := outline.buf.len;
		Texts.WriteObj(w, outline)
	END;
	Texts.WriteObj(w, CreateStyle(level))
END DumpHierarchy;

PROCEDURE DumpList(top: Range; VAR w: Texts.Writer);
	VAR p: Range;
BEGIN
	IF top = NIL THEN RETURN END;
	Write(w, top.name, top.locals, top.hits);
	Texts.WriteObj(w, CreateStyle(1));
	top.dsc := Sort(top.dsc, HitsGT);
	p := top.dsc;
	WHILE p # NIL DO
		Write(w, p.name, p.locals, p.hits); p := p.next
	END;
	Texts.WriteObj(w, CreateStyle(0))
END DumpList;

(* ------------- Stack related routines -------------- *)
PROCEDURE FindProcedure(pc: LONGINT; VAR low, hi: LONGINT; VAR name: ARRAY OF CHAR);
(*search a procedure in the reference section of the module*)
	VAR i, dummy, refstart, refpos, limit, oldprocstart, procstart: LONGINT; ch: CHAR; mod: AosModules.Module;

	PROCEDURE ReadNum (VAR pos: LONGINT; VAR i: LONGINT);
		VAR n: LONGINT; s: SHORTINT; x: CHAR;
	BEGIN
		s := 0; n := 0; SYSTEM.GET(pos, x); INC(pos);
		WHILE ORD(x) >= 128 DO INC(n, ASH(ORD(x) - 128, s)); INC(s, 7); SYSTEM.GET(pos, x); INC(pos) END;
		i := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64 * 64, s)
	END ReadNum;

BEGIN
	i := 0;
	mod := AosModules.ThisModuleByAdr(pc);
	WHILE mod.name[i] # 0X DO  name[i] := mod.name[i]; INC(i) END;
	name[i] := "."; INC(i);
	IF (SYSTEM.VAL(LONGINT, mod.refs) # 0) & (LEN(mod.refs) # 0) THEN
		refstart := 0;  refpos := SYSTEM.ADR(mod.refs[0]);
		procstart := 0;
		limit := refpos + LEN(mod.refs);
		LOOP
			oldprocstart := procstart;
			SYSTEM.GET(refpos, ch); INC(refpos);
			IF refpos >= limit THEN procstart :=  LEN(mod.code);  EXIT END;
			IF ch = 0F8X THEN (* start proc *)
				ReadNum(refpos, procstart);
				IF pc < SYSTEM.ADR(mod.code[0]) + procstart THEN EXIT END;
				refstart := refpos;
				REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
			ELSIF ch = 0F9X THEN (*proc, new format*)
				ReadNum(refpos, procstart);
				IF pc < SYSTEM.ADR(mod.code[0]) + procstart THEN EXIT END;
				INC(refpos, 1+1+1+1);
				refstart := refpos;
				REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
			ELSIF ch < 0F8X THEN (* skip object *)
				INC(refpos);	(* skip typeform *)
				ReadNum(refpos, dummy);	(* skip offset *)
				REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
			END
		END;
		
		refpos := refstart;
		IF refpos # 0 THEN
			SYSTEM.GET(refpos, ch); INC(refpos);
			WHILE ch # 0X DO name[i] := ch; INC(i); SYSTEM.GET(refpos, ch); INC(refpos) END;
			name[i] := 0X;
			low := SYSTEM.ADR(mod.code[0]) + oldprocstart;
			hi := SYSTEM.ADR(mod.code[0]) + procstart;
		END
	END
END FindProcedure;

PROCEDURE Init(top: Range; pc: LONGINT; proc: BOOLEAN);
	VAR m: AosModules.Module;
BEGIN
	IF pc = 0 THEN
		(*skip*)
	ELSIF proc THEN
		FindProcedure(pc, top.low, top.hi, top.name);
		ASSERT(top.low <= pc);
		ASSERT(pc < top.hi);
	ELSE
		m := AosModules.ThisModuleByAdr(pc);
		COPY(m.name, top.name);
		top.low := SYSTEM.ADR(m.code[0]);
		top.hi := top.low + LEN(m.code);
	END;	
END Init;

PROCEDURE Find(top: Range; pc: LONGINT; proc: BOOLEAN): Range;
(*Find/Insert an entry in the list*)
	VAR p, q: Range;
BEGIN
	p := top.dsc;
	IF (p=NIL) OR (pc < p.low) THEN
		NEW(q); Init(q, pc, proc); q.next := top.dsc; top.dsc := q;
		RETURN q
	ELSE
		WHILE (p.next # NIL) & (p.next.low <= pc) DO p := p.next END;
		IF (pc > p.hi) THEN
			NEW(q); Init(q, pc, proc); q.next := p.next; p.next := q;
			RETURN q
		ELSE
			RETURN p
		END
	END
END Find;

PROCEDURE Analyze;
VAR	p, q: Range;  pc, pos, next, i: LONGINT;
BEGIN
	FOR i := 0 TO AosBoot.MaxCPU - 1 DO
		next := 0;
		WHILE next < tracePos[i] DO
			pos := trace[i][next]-1; p := topM; q := topP;
			WHILE pos > next DO
				pc := trace[i][pos];
				(*trace modules*)
				IF (pc < p.low) OR (pc >= p.hi) THEN  p := Find(p, pc, FALSE); INC(p.hits)  END;
				(*trace procedures*)
				q := Find(q, pc, TRUE); INC(q.hits);
				DEC(pos)
			END;
			INC(p.locals);
			INC(q.locals);
			next := trace[i][next];
		END
	END
END Analyze;

PROCEDURE DumpTrace*;
VAR	pc, pos, next, i: LONGINT; low, hi: LONGINT; name: ARRAY 64 OF CHAR; W: Texts.Writer; t: Texts.Text;
BEGIN
	Texts.OpenWriter(W);
	Texts.SetFont(W, Fonts.This("Courier10.Scn.Fnt"));
	FOR i := 0 TO AosBoot.MaxCPU - 1 DO
		next := 0;
		WHILE next < tracePos[i] DO
			Texts.WriteInt(W, next, 4); Texts.WriteString(W, " ------------------"); Texts.WriteLn(W);
			pos := next+1;
			next := trace[i][next];
			WHILE pos < next DO
				pc := trace[i][pos];
				FindProcedure(pc, low, hi, name);
				Texts.WriteInt(W, pos, 4); Texts.WriteString(W, "  "); 
				Texts.WriteHex(W, pc); Texts.WriteHex(W, low); Texts.WriteHex(W, hi);
				Texts.WriteString(W, "  "); Texts.WriteString(W, name);
				Texts.WriteLn(W);
				INC(pos)
			END;
		END
	END;
	NEW(t); Texts.Open(t, ""); Texts.Append(t, W.buf); Oberon.OpenText("", t, 640, 400);
END DumpTrace;

PROCEDURE CollectOverview(root: Range): Range;
	VAR l, p, next, next2, res: Range;
BEGIN
	res := NIL;
	WHILE root # NIL DO
		next := root.next;
		l := CollectOverview(root.dsc);
		root.dsc := NIL;
		(* if this range is already present in the overview of the subtree, the cumulated count should be ignored (don't count range twice) *)
		p := l;
		WHILE (p # NIL) & (p.low # root.low) DO  p := p.next  END;
		IF p # NIL THEN
			INC(p.locals, root.locals);	(*add count, discard root*)
			p.hits := root.hits
		ELSE
			root.next := l;	(*add root to overview*)
			l := root;
		END;
		
		(*merge step*)
		WHILE l # NIL DO	
			p := res; next2 := l.next;
			WHILE (p # NIL) & (p.low # l.low) DO  p := p.next  END;
			IF p # NIL THEN
				INC(p.locals, l.locals);
				INC(p.hits, l.hits)
			ELSE
				l.next := res;
				res := l
			END;
			l := next2
		END;
		root := next
	END;
	RETURN res
END CollectOverview;

PROCEDURE Output(call: ARRAY OF CHAR; times, use: LONGINT);
VAR t: Texts.Text; w: Texts.Writer; i: LONGINT;
BEGIN
	i := 0; WHILE i < LEN(StyleCache) DO StyleCache[i] := NIL; INC(i) END;
	Texts.OpenWriter(w);
	Texts.WriteString(w, "Profiling ["); Texts.WriteString(w, call); Texts.WriteString(w, "]x");
	Texts.WriteInt(w, times,0); Texts.WriteLn(w); Texts.WriteLn(w);
	
	Texts.WriteString(w, "Trace Array usage: "); Texts.WriteRealFix(w, 100* use / LEN(trace, 1), 5, 2, 0);
	Texts.WriteLn(w);  Texts.WriteLn(w);
	
	Texts.SetFont(w, title); Texts.WriteString(w, "Trace of the module calls"); Texts.SetFont(w, normal); Texts.WriteLn(w);
	StyleCache[1] := NIL;		(* Hack!! *)
	tab := "120, 170";
	DumpHierarchy(topM, w, 0); Texts.WriteLn(w);
	
	Texts.SetFont(w, title); Texts.WriteString(w, "Overview of the involved modules"); Texts.SetFont(w, normal); Texts.WriteLn(w);
	topM.dsc := CollectOverview(topM.dsc);
	DumpList(topM, w); Texts.WriteLn(w);

	Texts.SetFont(w, title); Texts.WriteString(w, "Trace of the procedure calls"); Texts.SetFont(w, normal); Texts.WriteLn(w);
	StyleCache[1] := NIL;		(* Hack!! *)
	tab := "180, 230";
	DumpHierarchy(topP, w, 0); Texts.WriteLn(w);
	
	Texts.SetFont(w, title); Texts.WriteString(w, "Overview of the involved procedures"); Texts.SetFont(w, normal); Texts.WriteLn(w);
	topP.dsc := CollectOverview(topP.dsc);
	DumpList(topP, w); Texts.WriteLn(w);	
	
	NEW(t);  Texts.Open(t, "");  Texts.Append(t, w.buf);
	Oberon.OpenText("", t, 640, 400);
	
	topP := NIL; topM := NIL
END Output;

PROCEDURE HandleTimer(id: LONGINT; VAR state: AosInterrupts.State);
VAR	cnt, eip, ebp, pos: LONGINT;
BEGIN
	pos := tracePos[id];
	
	eip := state.EIP; ebp := state.EBP;

	cnt :=pos; INC(pos);
	WHILE (pos < LEN(trace, 1)) & (ebp # 0) & (ebp # stopEBP) DO
		trace[id][pos] := eip; SYSTEM.GET(ebp+4, eip); SYSTEM.GET(ebp, ebp); INC(pos)
	END;
	IF (pos < LEN(trace, 1)) & (ebp = stopEBP) THEN trace[id][cnt] := pos ELSE pos := cnt END;
	tracePos[id] := pos
END HandleTimer;


(** Profile [repetitions] M.P params ~ 
	default repetitions = 1
*)
PROCEDURE Profile*;
VAR times, n, max, i: LONGINT; s: Texts.Scanner; call: ARRAY 256 OF CHAR;
		res: INTEGER;
BEGIN
	(*parse parameters*)
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(s);
	IF s.class = Texts.Int THEN times := s.i; Texts.Scan(s) ELSE times := 1 END;
	
	nflag := FALSE; pflag := FALSE; vflag := FALSE; tflag := FALSE;
	COPY(s.s, call); n := 0;
	WHILE (s.s[n]#0X) & (s.s[n]#".") DO INC(n) END;
	s.s[n] := 0X;
	NEW(topM);
	NEW(topP);
	
	Oberon.Par.pos := Texts.Pos(s);
	
	(* perform *)
	max := 0;  n := times;
	SYSTEM.GETREG(SYSTEM.EBP, stopEBP);
	WHILE n > 0 DO
		FOR i := 0 TO AosBoot.MaxCPU-1 DO tracePos[i] := 0 END;
		AosProcessors.InstallHandler(HandleTimer);
		Oberon.Call(call, Oberon.Par, FALSE, res);
		AosProcessors.InstallHandler(NIL);
		DEC(n);
		FOR i := 0 TO AosBoot.MaxCPU-1 DO 
			IF tracePos[i] > max THEN max := tracePos[i] END;
			IF tracePos[i] > LEN(trace, 1)-20 THEN
				Out.String("trace array was too small!!!!"); Out.Ln;
			END;
		END;
		Analyze
	END;
	topM := topM.dsc;	(*skip self *)
	topP := topP.dsc;
	Output(call, times, max);
END Profile;

PROCEDURE Start*;
	VAR i: LONGINT;
BEGIN
	NEW(topM); topM.low := 0; topM.hi := 0; topM.name := "huga";
	NEW(topP); topP.low := 0; topP.hi := 0; topP.name := "huga";
	FOR i := 0 TO AosBoot.MaxCPU-1 DO tracePos[i] := 0 END;
	stopEBP := 0;
	AosProcessors.InstallHandler(HandleTimer);
END Start;

PROCEDURE Stop*;
	VAR i, max: LONGINT;
BEGIN
	AosProcessors.InstallHandler(NIL);
	FOR i := 0 TO AosBoot.MaxCPU-1 DO 
		IF tracePos[i] > max THEN max := tracePos[i] END;
	END;
	IF max > LEN(trace, 1)-20 THEN Out.String("trace array was too small!!!!"); Out.Ln END;
	Analyze;
(*
	topM := topM.dsc;
	topP := topP.dsc;
*)
	Output("continuous", 0, max);
END Stop;

PROCEDURE Dummy*;
VAR o: Objects.Object;
BEGIN
	(*Output("", 0, 0);*)
	o := CreateStyle(1);
END Dummy;

PROCEDURE Dummy2*;
	VAR i: LONGINT;
BEGIN
	FOR i := 0 TO 20 DO
		Out.Int(i, 0); Out.Ln
	END
END Dummy2;

BEGIN
	normal := Fonts.This("Oberon10.Scn.Fnt");  title := Fonts.This("Oberon12b.Scn.Fnt");
	NEW(trace);
END AosProfiler.


AosProfiler.Profile Compiler.Compile * ~
AosProfiler.Profile 5 Compiler.Compile AosProfiler.Mod ~
AosProfiler.Profile 20  AosProfiler.Dummy ~
AosProfiler.Profile 20000 AosProfiler.Dummy ~
AosProfiler.Profile 20  System.Time ~
AosProfiler.Profile  System.Time ~

AosProfiler.DumpTrace
AosProfiler.Reset

AosProfiler.Test
AosProfiler.Profile 10 Compiler.Compile AosProfiler.Mod ~

System.State AosProfiler ~
System.Free AosProfiler ~
System.Watch
Configuration.DoCommands
AosProfiler.Start
System.Time
System.Time
AosProfiler.Stop
~

