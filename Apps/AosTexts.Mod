MODULE AosTexts;	(** AUTHOR "TF"; PURPOSE "Basic Unicode text system"; *)

IMPORT
		AosOut, AosActive, AosKernel, WMEvents, WMLocks, Utilities;

CONST TraceHard = FALSE;

CONST
	OpInsert* = 0;
	OpDelete* = 1;
	OpAttributes* = 2;
	OpMulti* = 3;
	CR = 0DX; LF = 0AX;
	NewLineChar* = 10;
	TabChar* = 9;
	ObjectChar* = -1;
	UsePieceTable = TRUE;
		
TYPE
	UCS32String* = ARRAY OF LONGINT;
	PUCS32String* = POINTER TO UCS32String;
	Char32* = LONGINT;
	
	FontInfo* = OBJECT
	VAR fontcache* : PTR;
		name* : ARRAY 32 OF CHAR;
		size* : LONGINT;
		style* : SET;
		
		PROCEDURE IsEqual*(f : FontInfo): BOOLEAN;
		BEGIN
			RETURN (name = f.name) & (size = f.size) & (style = f.style)
		END IsEqual;
		
		PROCEDURE Clone*() : FontInfo;
		VAR f : FontInfo;
		BEGIN
			NEW(f);
			f.fontcache := fontcache; COPY(name, f.name); f.size := size; f.style := style;
			RETURN f
		END Clone;
	END FontInfo;
	
	Attributes* = OBJECT
	VAR color*, bgcolor* : LONGINT;
		voff* : LONGINT;
		fontInfo* : FontInfo;
			
		PROCEDURE IsEqual*(attr : Attributes) : BOOLEAN;
		BEGIN
			RETURN (attr # NIL) & (color = attr.color) & (bgcolor = attr.bgcolor) & (voff = attr.voff) & 
				( (fontInfo = NIL) & (attr.fontInfo = NIL) OR fontInfo.IsEqual(attr.fontInfo))
		END IsEqual;
		
		PROCEDURE Clone*():Attributes;
		VAR a : Attributes;
		BEGIN
			NEW(a);
			a.color := color; a.bgcolor := bgcolor; a.voff := voff; IF fontInfo # NIL THEN a.fontInfo := fontInfo.Clone() END;
			RETURN a
		END Clone;
	END Attributes;
	
	Piece* = OBJECT
	VAR next*, prev* : Piece;
		len*, startpos* : LONGINT;
		attributes* : Attributes;
		
		(** Return a copy of the piece, prev/next pointers nil and pos 0 *)
		PROCEDURE Clone*() : Piece;
		BEGIN
			HALT(301); (* Abstract *)
		END Clone;
		
		(** Split the UnicodePiece at pos in text position and return right piece *)
		PROCEDURE Split*(pos : LONGINT; VAR right : Piece);
		BEGIN
			HALT(301); (* Abstract *)
		END Split;
		
		(** Merge right to self; return true if ok *)
		PROCEDURE Merge*(right : Piece) : BOOLEAN;
		BEGIN
			HALT(301); (* Abstract *)
		END Merge;
		
	END Piece;
	
	UnicodePiece* = OBJECT(Piece)
		(** index in text position; index and (index + length) must be in the piece *) 
		PROCEDURE GetUCS32Buf*(index : LONGINT; length : LONGINT; VAR ucs : UCS32String; VAR res : LONGINT);
		BEGIN
		END GetUCS32Buf;
		
		(** index in text position; index and (index + length) must be in the piece *) 
		PROCEDURE GetUCS32*(index : LONGINT;  VAR ucs : Char32);
		BEGIN
		END GetUCS32;
	END UnicodePiece;

	MemUnicodePiece* = OBJECT(UnicodePiece)
	VAR
		buffer : PUCS32String;
	
		PROCEDURE SetBuf(VAR buffer : UCS32String);
		VAR i : LONGINT;
		BEGIN
			WHILE buffer[i] # 0 DO INC(i) END; len := i;
			NEW(SELF.buffer, len);
			FOR i := 0 TO len - 1 DO SELF.buffer[i] := buffer[i] END 
		END SetBuf;
		
		(** Return a copy of the piece, prev/next pointers nil and pos 0 *)
		PROCEDURE Clone*() : Piece;
		VAR m : MemUnicodePiece; i : LONGINT;
		BEGIN
			NEW(m);
			m.len := len; IF attributes # NIL THEN m.attributes := attributes.Clone() END;
			NEW(m.buffer, LEN(buffer));
			FOR i := 0 TO LEN(buffer) - 1 DO m.buffer[i] := buffer[i] END;
			RETURN m
		END Clone;
		
		(** index in text position; index and (index + length) must be in the piece *) 
		PROCEDURE GetUCS32Buf*(index : LONGINT; length : LONGINT; VAR ucs : UCS32String; VAR res : LONGINT);
		VAR i, j : LONGINT;
		BEGIN
			i := index - startpos; IF (i < 0) OR (i >= len) THEN ucs[0] := 0; res := -1; RETURN END; 
			j := 0;
			WHILE (j < LEN(ucs)) & (j < length) & (i < len) DO ucs[j] := buffer[i]; INC(i); INC(j) END;
			IF (j < length) & (i >= len) THEN res := -1 ELSE res := 0 END;
			IF (j > LEN(ucs) - 1) THEN j := LEN(ucs) -1 END;
			ucs[j] := 0
		END GetUCS32Buf;
		
		PROCEDURE GetUCS32*(index : LONGINT; VAR ucs : Char32);
		VAR i, j : LONGINT;
		BEGIN
			i := index - startpos; IF (i < 0) OR (i >= len) THEN ucs := 0 ELSE ucs := buffer[i] END; 
		END GetUCS32;
		
		(** Split the UnicodePiece at pos in text position and return right piece *)
		PROCEDURE Split*(pos : LONGINT; VAR right : Piece);
		VAR mp : MemUnicodePiece; i, j : LONGINT;
		BEGIN
			IF pos - startpos < len THEN
				(* create right part *)
				NEW(mp); 
				IF attributes # NIL THEN mp.attributes := attributes.Clone() END; NEW(mp.buffer, len - (pos - startpos)); 
				mp.len := len - (pos - startpos); mp.startpos := pos;
				j := 0; FOR i := pos - startpos TO len - 1 DO mp.buffer[j] := buffer[i]; INC(j) END;
				(* adjust own length *)
				len := (pos - startpos);
				IF len <= 0 THEN
					AosOut.String("BUG BUG BUG BUG BUG BUG BUG BUG"); AosOut.Ln;
				END;
				(* linking *)
				mp.next := next; IF next # NIL THEN next.prev := mp END; mp.prev := SELF; next := mp;
				right := mp
			ELSE right := next
			END
		END Split;
		
		(** Merge right to self; return true if ok *)
		PROCEDURE Merge*(right : Piece) : BOOLEAN;
		VAR temp : PUCS32String;
			i, j : LONGINT;
		BEGIN
			IF right = SELF THEN AosOut.String("Shit happens "); AosOut.Ln END;
			IF (right # NIL) & (right IS MemUnicodePiece) & (right # SELF) &
				((attributes = NIL) & (right.attributes = NIL) OR (attributes # NIL) & attributes.IsEqual(right.attributes)) &
				(len < 1000) THEN
				NEW(temp, len + right.len);
				FOR i := 0 TO len - 1 DO temp[i] := buffer[i] END;
				WITH right : MemUnicodePiece DO
					j := len; FOR i := 0 TO right.len - 1 DO temp[j] := right.buffer[i]; INC(j) END;
				END;	
				buffer := temp;
				len := len + right.len; next := right.next; IF next # NIL THEN next.prev := SELF END;
				RETURN TRUE
			ELSE
				RETURN FALSE	
			END
		END Merge;
		
	END MemUnicodePiece;

	ObjectPiece* = OBJECT(Piece)
	VAR object* : PTR;
	
		PROCEDURE &Init;
		BEGIN
			len := 1
		END Init;
		
		(** Return a copy of the piece, prev/next pointers nil and pos 0 *)
		PROCEDURE Clone*() : Piece;
		VAR p : ObjectPiece;
		BEGIN
			NEW(p);
			p.len := len; IF attributes # NIL THEN p.attributes := attributes.Clone() END;
			p.object := object;
			RETURN p
		END Clone;
		
		PROCEDURE Split*(pos : LONGINT; VAR right : Piece);
		VAR mp : ObjectPiece; p : Piece; i, j : LONGINT;
		BEGIN
			AosOut.String("objpiece split"); AosOut.Ln;
			AosOut.String("Split of a len = 1 piece should never happen"); AosOut.Ln;
			IF pos - startpos < len THEN
				AosOut.String("Should never happen"); AosOut.Ln;
			ELSE right := next; AosOut.String("Huga right is next"); AosOut.Ln;
			END
		END Split;
		
		(** Merge right to self; return true if ok *)
		PROCEDURE Merge*(right : Piece) : BOOLEAN;
		BEGIN
			RETURN FALSE
		END Merge;
	END ObjectPiece;
	
	(** a TextPosition is assigned to a text and positioned with SetPosition. If
		the text is changed after the position was set, the position is updated *)
	TextPosition* = OBJECT
	VAR position : LONGINT;
			data* : PTR;
			text- : UnicodeText;

		PROCEDURE &New*(t : UnicodeText);
		BEGIN
			text := t; text.RegisterPositionObject(SELF)
		END New;
		
		(** Listens for text changes *)
		PROCEDURE Changed*(op, pos, len :  LONGINT);
		BEGIN
			IF TraceHard THEN 
				AosOut.String("TextPosition : ChangeRequest"); AosOut.Int(op, 5); AosOut.Int(pos, 5); AosOut.Int(len, 5);AosOut.Ln;
			END;
			IF (position >= pos) & (op = OpInsert) THEN INC(position, len) 
			ELSIF (position > pos) & (op = OpDelete) THEN DEC(position, len) 
			END
		END Changed;
		
		(** Position in elements from text start.  *)
		PROCEDURE SetPosition*(pos : LONGINT);
		BEGIN
			IF pos < 0 THEN pos := 0 ELSIF pos > text.GetLength() THEN pos := text.GetLength() END;
			position := pos
		END SetPosition;
		
		(** Returns position in elements from the text start *)
		PROCEDURE GetPosition*():LONGINT;
		BEGIN
			RETURN position
		END GetPosition;
	END TextPosition;	
	
	(** a reader may not be shared by processes, must text must be hold by process *)
	TextReader* = OBJECT(TextPosition)
	VAR piece : Piece;
		backwards : BOOLEAN;
		eot- : BOOLEAN;
		voff-, color-, bgcolor- : LONGINT;
		font- : FontInfo;
		attributes- : Attributes;
		object- : PTR;
			
		PROCEDURE &New*(t : UnicodeText);
		BEGIN
			New^(t); backwards := FALSE;
		END New;
		
		(** Listens for text changes *)
		PROCEDURE Changed*(op, pos, len :  LONGINT);
		BEGIN
			Changed^(op, pos, len); piece := NIL
		END Changed;
		
		PROCEDURE ReadCh*(VAR ucs32 : LONGINT); 
		VAR buf : ARRAY 2 OF LONGINT; res : LONGINT;
		BEGIN
			eot := (backwards) & (position = 0) OR (~backwards) & (position = text.GetLength());
			IF eot THEN ucs32 := 0; RETURN END;
			IF (piece = NIL) OR (piece.startpos > position) OR (piece.startpos + piece.len <= position) THEN 
				text.FindPiece(position, piece);
				IF (piece # NIL) & (piece IS ObjectPiece) THEN object := piece(ObjectPiece).object;
				ELSE object := NIL
				END;
				IF piece = NIL THEN res := -1; ucs32 := 0; RETURN END;
				attributes := piece.attributes;
				IF attributes # NIL THEN voff := attributes.voff; color := attributes.color; bgcolor := attributes.bgcolor; font := attributes.fontInfo
				ELSE voff := 0; color := 0FFH; bgcolor := 0; font := NIL
				END;
			END;
			
			IF TraceHard THEN
				IF res # 0 THEN 
					AosOut.String("  piece "); AosOut.Int(piece.startpos, 5); AosOut.String(" piepst :"); AosOut.Int(position, 5); 
					AosOut.Ln;
					HALT(99);
				END;
			END;
			IF piece IS UnicodePiece THEN piece(UnicodePiece).GetUCS32(position, ucs32)
			ELSIF piece IS ObjectPiece THEN ucs32 := ObjectChar
			END;	
			IF backwards THEN DEC(position) ELSE INC(position) END
		END ReadCh;
		
		(** Direction the text is read. dir >= 0 --> forward; dir < 0 --> backwards 
		      Backwards can be very slow depending on the text *)
		PROCEDURE SetDirection*(dir : LONGINT);
		BEGIN
			backwards := dir < 0
		END SetDirection;
	END TextReader;
	
	TextChangeInfo* = OBJECT
	VAR timestamp*, op*, pos*, len* : LONGINT;
	END TextChangeInfo;
	
TYPE
	(** UnicodeText offers an editable unicode text abstraction, basing on UnicodePiece *)
	UnicodeText* = OBJECT
	VAR
		first : Piece;
		length : LONGINT;
		nofPieces : LONGINT;
		
		posObjects : AosKernel.FinalizedCollection;
		pop, ppos, plen : LONGINT;
		timestamp : LONGINT;
		upOp, upPos, upLen : LONGINT;
		onTextChanged* : WMEvents.EventSource;
		lock : WMLocks.RWLock;
		pieceTableOk : BOOLEAN;
		pieceTable : POINTER TO ARRAY OF Piece;
		
		PROCEDURE &New;
		BEGIN
			NEW(lock);
			IF UsePieceTable THEN NEW(pieceTable, 256) END; 
			pieceTableOk := FALSE;
			NEW(posObjects); timestamp := 0;
			upOp := -1; upPos := 0; upLen := 0;
			nofPieces := 0;
			NEW(onTextChanged, SELF, onTextChangedStr, NIL, NIL);
		END New;
		
		(** acquire a write lock on the object *)
		PROCEDURE AcquireWrite*;
		BEGIN
			lock.AcquireWrite
		END AcquireWrite;
		
		(** release the write lock on the object *)
		PROCEDURE ReleaseWrite*;
		VAR removeLock : BOOLEAN;
			op, pos, len, localtimestamp : LONGINT;
		BEGIN 
			removeLock := lock.GetWLockLevel() = 1;
			IF removeLock THEN op := upOp; pos := upPos; len := upLen; localtimestamp := GetTimestamp(); upOp := -1 END;	
			lock.ReleaseWrite;
			IF removeLock & (op >= 0) THEN InformListeners(localtimestamp, op, pos, len) END;
		END ReleaseWrite;
		
		(** acquire a write lock on the object *)
		PROCEDURE AcquireRead*;
		BEGIN
			lock.AcquireRead
		END AcquireRead;
		
		(** release the write lock on the object *)
		PROCEDURE ReleaseRead*;
		BEGIN
			lock.ReleaseRead
		END ReleaseRead;
		
		PROCEDURE InformListeners(timestamp, op, pos, len : LONGINT);
		VAR updateInfo : TextChangeInfo;
		BEGIN
			NEW(updateInfo);
			updateInfo.timestamp := timestamp; updateInfo.op := op; updateInfo.pos := pos; updateInfo.len := len;
			onTextChanged.Call(updateInfo)
		END InformListeners;
		
		PROCEDURE UpdatePieceTable;
		VAR cur : Piece; len, i : LONGINT;
		BEGIN
			IF LEN(pieceTable^) < nofPieces THEN NEW(pieceTable, nofPieces + Utilities.Max(256, nofPieces DIV 2)) END;
			len := LEN(pieceTable^);
			cur := first; i := 0; pieceTable[0] := first;
			WHILE (cur # NIL) & (i < len) DO pieceTable[i] := cur; cur := cur.next; INC(i) END;
			pieceTableOk := i = nofPieces;
			IF ~pieceTableOk THEN 
			AosOut.Int(i, 0); AosOut.String(" vs "); AosOut.Int(nofPieces, 0); AosOut.Ln END;
		END UpdatePieceTable;
		
		(* Return the piece that contains pos or the last piece if pos is not found *)
		PROCEDURE FindPiece(pos : LONGINT; VAR piece : Piece);
		VAR a, b, m : LONGINT;
		BEGIN
			IF UsePieceTable THEN
				IF ~pieceTableOk THEN UpdatePieceTable END
			END;
			IF pieceTableOk THEN
				a := 0; b := nofPieces - 1;
				ASSERT(pieceTable[0] = first);
				WHILE (a < b) DO m := (a + b) DIV 2;
					piece := pieceTable[m];
					IF piece.startpos + piece.len <= pos THEN a := m + 1 ELSE b := m END 
				END;
				piece := pieceTable[a];
				IF piece = NIL THEN RETURN END;
				
				IF ~(piece.startpos + piece.len >= pos) THEN
					AosOut.String("pos = "); AosOut.Int(pos, 0); AosOut.Ln;
					AosOut.String("startpos = "); AosOut.Int(piece.startpos, 0);  AosOut.Ln;
					AosOut.String("len = "); AosOut.Int(piece.len, 0);  AosOut.Ln;
				END;
				
			ELSE
				piece := first; IF piece = NIL THEN RETURN END;
				LOOP
					IF (piece.next = NIL) OR (piece.startpos + piece.len > pos) THEN RETURN END; 
					piece := piece.next
				END
			END
		END FindPiece;
		
		PROCEDURE SendPositionUpdate(obj: PTR; VAR cont: BOOLEAN);
		BEGIN
			cont := TRUE;
			IF obj IS TextPosition THEN 
				obj(TextPosition).Changed(pop, ppos, plen)
			END
		END SendPositionUpdate;
		
		PROCEDURE UpdatePositionObjects(op, pos, len : LONGINT);
		BEGIN
			SELF.pop := op; SELF.ppos := pos; SELF.plen := len;
			posObjects.Enumerate(SendPositionUpdate)
		END UpdatePositionObjects;
		
		PROCEDURE AccumulateChanges(op, pos, len : LONGINT);
		BEGIN
			IF upOp >= 0 THEN upOp := OpMulti
			ELSE upOp := op; upPos := pos; upLen := len
			END;
		END AccumulateChanges;
		
		(** Register a position object on the text. The TextPosition objects are automatically be updated if the text is changed.
			TextPosition objects are automatically unregistred by the garbage collector *)
		PROCEDURE RegisterPositionObject*(po : TextPosition);
		BEGIN
			posObjects.Add(po, NIL)
		END RegisterPositionObject;
		
		(** Split the piece list at pos and return left and right. left or right can be NIL if at end/begin *)
		PROCEDURE GetSplittedPos(pos : LONGINT; VAR left, right: Piece);
		VAR p, r, t : Piece;
		BEGIN
			FindPiece(pos, p);
			IF p = NIL THEN left := NIL; right := NIL; RETURN END;
			IF p.startpos = pos THEN left := p.prev; right := p
			ELSE t := p.next; left := p; p.Split(pos, right); 
				IF right # t THEN 
					pieceTableOk := FALSE; INC(nofPieces) 
				END
			END
		END GetSplittedPos;
		
		(** Insert a piece at position pos into the text. Index in characters/objects *)
		PROCEDURE InsertPiece*(pos : LONGINT; n : Piece);
		VAR l, r, cur : Piece;
			chpos, chlen : LONGINT;
		BEGIN
			ASSERT(lock.HasWriteLock(), 3000);
			INC(timestamp);
			IF pos > length THEN pos := length END;
			
			INC(length, n.len);
			chpos := pos; chlen := n.len;			
			IF first = NIL THEN n.next := NIL; n.prev := NIL; first := n; nofPieces := 1; pieceTableOk := FALSE
			ELSE
				GetSplittedPos(pos, l, r);
				IF l = NIL THEN n.next := first; first.prev := n; first := n
				ELSE l.next := n; n.prev := l; n.next := r; IF r # NIL THEN r.prev := n END
				END;

				INC(nofPieces); 
				IF r = NIL THEN
				(* optimize loading by re-establishing the pieceTable *)
					IF nofPieces < LEN(pieceTable^) THEN pieceTable[nofPieces - 1] := n
					ELSE pieceTableOk := FALSE
					END 
				ELSE pieceTableOk := FALSE
				END;
				cur := n; WHILE cur # NIL DO cur.startpos := pos; INC(pos, cur.len); cur := cur.next END;
				cur := n; IF cur.Merge(cur.next) THEN DEC(nofPieces); pieceTableOk := FALSE END; 
				IF (cur.prev # NIL) & cur.prev.Merge(cur) THEN DEC(nofPieces); pieceTableOk := FALSE END
			END;
			AccumulateChanges(OpInsert, chpos, chlen);
			UpdatePositionObjects(OpInsert, chpos, chlen)
		END InsertPiece;
		
		(** Insert a UCS32 buffer at position pos into the text. Index in characters/objects *)
		PROCEDURE InsertUCS32* (pos : LONGINT; VAR buf : UCS32String);
		VAR n : MemUnicodePiece;
			p : Piece;
		BEGIN 
			ASSERT(lock.HasWriteLock(), 3000);
			IF buf[0] = 0 THEN RETURN END;
			IF pos > GetLength() THEN pos := GetLength() END;
			NEW(n); n.SetBuf(buf); 
			FindPiece(pos, p);
			IF (p # NIL) THEN n.attributes := p.attributes END;
			InsertPiece(pos, n)
		END InsertUCS32;
		
		(** Delete len characters from position pos  *)
		PROCEDURE Delete* (pos, len : LONGINT);
		VAR al, ar, bl, br, cur: Piece;
			p : LONGINT;
		BEGIN 
			ASSERT(lock.HasWriteLock(), 3000);
			INC(timestamp); 
			(* don't do illegal changes *)
			IF (len <= 0) OR (pos < 0) OR (pos + len > length) OR (first = NIL) THEN RETURN END; 
			IF length = 0 THEN first := NIL; nofPieces := 0; pieceTableOk := FALSE
			ELSE
				GetSplittedPos(pos, al, ar);
				GetSplittedPos(pos + len, bl, br);
				IF al # NIL THEN
					cur := al.next; WHILE (cur # NIL) & (cur # br) DO pieceTableOk := FALSE; DEC(nofPieces); cur := cur.next END;
					al.next := br; IF br # NIL THEN br.prev := al END;
					cur := al
				ELSE
					cur := first; WHILE (cur # NIL) & (cur # br) DO pieceTableOk := FALSE; DEC(nofPieces); cur := cur.next END;
					IF br # NIL THEN br.startpos := 0; br.prev := NIL END;
					first := br; cur := first 
				END;
				IF cur # NIL THEN 
					(* update the start positions of all the following pieces *)
					p := cur.startpos; WHILE cur # NIL DO cur.startpos := p; INC(p, cur.len); cur := cur.next END;
					IF (al # NIL) & al.Merge(al.next) THEN DEC(nofPieces) END
				END	
			END;
			DEC(length, len);
			IF (first = NIL) & (length # 0) THEN AosOut.String("ERROR : No text but length > 0 ! "); AosOut.Ln END;
			AccumulateChanges(OpDelete, pos, len);
			UpdatePositionObjects(OpDelete, pos, len)
		END Delete;
		
		(** Copy pos to pos + len to the dest text, starting at destPos. The calling process must have
			acquired both texts [Must hold lock]. If the destitnation text is the same as SELF, then
			the destination position must be outside the source range, otherwise the command returns
			without changing the text *)
		PROCEDURE CopyToText*(from, len : LONGINT; dest : UnicodeText; destPos : LONGINT);
		VAR fromP, toP, curP : Piece; pos : LONGINT;
		BEGIN
			ASSERT(lock.HasReadLock(), 3000);
			(* don't do illegal changes *)
			IF (len <= 0) OR (pos < 0) OR (pos + len > length) OR (first = NIL) THEN RETURN END;
			(* avoid recursive copy *)
			IF (dest = SELF) & (destPos >= from) & (destPos <= from + len) THEN RETURN END;
			GetSplittedPos(from, curP, fromP); GetSplittedPos(from + len, curP, toP);
			curP := fromP; pos := destPos;
			IF curP # NIL THEN
				REPEAT
					dest.InsertPiece(pos, curP.Clone()); INC(pos, curP.len); curP := curP.next
				UNTIL (curP = toP) OR (curP = NIL)
			END	
		END CopyToText;
		
		(** Set piece attributes for charater at position pos to pos + len. [Must hold lock] *)
		PROCEDURE SetAttributes*(pos, len : LONGINT; attr : Attributes);
		VAR al, ar, bl, br, cur : Piece;
		BEGIN
			IF len = 0 THEN RETURN END;
			(* don't do illegal changes *)
			IF (len <= 0) OR (pos < 0) OR (pos + len > length) OR (first = NIL) THEN RETURN END; 
			ASSERT(lock.HasWriteLock(), 3000);
			INC(timestamp);
			GetSplittedPos(pos, al, ar);
			GetSplittedPos(pos + len, bl, br);
			cur := ar;
			WHILE cur # br DO cur.attributes := attr; cur := cur.next END;
			(* try merging *)
			WHILE (cur # NIL) & (cur # al) DO 
				IF cur.prev # NIL THEN 
					IF cur.prev.Merge(cur) THEN DEC(nofPieces); pieceTableOk := FALSE END
				END;	
				cur := cur.prev 
			END;
(*			
			$$$
			cur.attributes := attr;
			IF (al # NIL) & al.Merge(al.next) THEN cur := ar.next; DEC(nofPieces); pieceTableOk := FALSE END; 
			WHILE cur.next # br DO cur.next.attributes := attr; IF cur.Merge(cur.next) THEN  DEC(nofPieces); pieceTableOk:= FALSE END;  cur := cur.next END;
			IF (bl # NIL) & bl.Merge(bl.next) THEN DEC(nofPieces); pieceTableOk := FALSE END; *)
			AccumulateChanges(OpAttributes, pos, len);
			UpdatePositionObjects(OpAttributes, pos, len)
		END SetAttributes;
			
		(** Return length in characters [Must hold lock]*)
		PROCEDURE GetLength* () : LONGINT;
		BEGIN 
			ASSERT(lock.HasReadLock(), 3000);
			RETURN length
		END GetLength;
		
		(** Return the current timestamp [Must hold lock].
		The timestamp can be used to check if an asynchronous change notification reflects the last change. Text
		viewers can use this knowledge to incrementally update the layout. If the notification timestamp # 
		GetTimestamp then a full update is needed *)
		PROCEDURE GetTimestamp*() : LONGINT;
		BEGIN
			ASSERT(lock.HasReadLock(), 3000);
			RETURN timestamp
		END GetTimestamp;
		
		PROCEDURE CheckHealth*;
		VAR cur : Piece;
			pos, i, nof : LONGINT; errors : BOOLEAN;
		BEGIN
			ASSERT(lock.HasReadLock(), 3000);
			nof := 0; pos := 0; cur := first; i := 0; errors := FALSE;
			WHILE cur # NIL DO 
				INC(nof);
				IF cur.startpos # pos THEN
					AosOut.String("Piece #"); AosOut.Int(i, 4); AosOut.String(" has wrong start pos"); AosOut.Ln;
					errors := TRUE
				END;
				IF cur.len = 0 THEN
					AosOut.String("Piece #"); AosOut.Int(i, 4); AosOut.String(" has zero length"); AosOut.Ln;
					errors := TRUE
				END;
				pos := pos + cur.len;
				cur := cur.next; INC(i);
			END;
			
			IF pos # length THEN 
				AosOut.String("Piece-List-Length is inconsistent"); AosOut.Ln; 
				AosOut.String("Measured length "); AosOut.Int(pos, 4); AosOut.Ln;
				AosOut.String("Internal length "); AosOut.Int(length, 4); AosOut.Ln;
				
				errors := TRUE 
			END;
			IF nof # nofPieces THEN errors := TRUE; AosOut.String("ERROR : piece count failed");  AosOut.Ln;
				AosOut.String(" nof = "); AosOut.Int(nof, 0); AosOut.String(" nofPieces = "); AosOut.Int(nofPieces, 0); AosOut.Ln
			END;
			IF ~errors THEN AosOut.String("Piece list is healthy"); AosOut.Ln;
			ELSE AosOut.String("!!! Piece list contains errors !!!!"); AosOut.Ln
			END;
		END CheckHealth;
		
		PROCEDURE DumpPieces*;
		VAR cur : Piece;
			buf : PUCS32String;
			abuf : ARRAY 128 OF CHAR;
			res : LONGINT;
		BEGIN
			cur := first;
			NEW(buf, 128); 
			IF first = NIL THEN AosOut.String("Empty piece list..."); AosOut.Ln END;
			WHILE cur # NIL DO 
				AosOut.String("Piece pos = "); AosOut.Int(cur.startpos, 5); AosOut.String(" len "); AosOut.Int(cur.len, 5);
				IF cur.attributes # NIL THEN 
					AosOut.String(" [Attributes : color = ");AosOut.Hex(cur.attributes.color, 8);
					AosOut.String(", bgcolor = "); AosOut.Hex(cur.attributes.bgcolor, 8); AosOut.String(" ]");
				END;
				IF cur IS UnicodePiece THEN AosOut.String("[unicode]") 
					(* cur(UnicodePiece).GetUCS32(cur.startpos, cur.len, buf^, res); UCS32ToAscii(buf^, abuf); *)
				ELSIF cur IS ObjectPiece THEN AosOut.String("[object]") 
				END;
				 AosOut.Ln;
				cur := cur.next
			END
		END DumpPieces;
	END UnicodeText;
	
	Text* = UnicodeText;
	
VAR clipboard* : UnicodeText;
	onTextChangedStr : Utilities.String;
	
	lastSelText : Text;
	lastSelFrom, lastSelTo : TextPosition;
	
	lastText : Text;
	onLastSelectionChanged-, 
	onLastTextChanged- : WMEvents.EventSource;

PROCEDURE SetLastSelection*(text : Text; from, to : TextPosition);
BEGIN 
	ASSERT((text # NIL) & (from # NIL) & (to # NIL));
	BEGIN {EXCLUSIVE}
		lastSelText := text; lastSelFrom := from; lastSelTo := to
	END;
	onLastSelectionChanged.Call(text)
END SetLastSelection;

PROCEDURE ClearLastSelection*;
BEGIN {EXCLUSIVE}
	lastSelText := NIL; lastSelFrom := NIL; lastSelTo := NIL
END ClearLastSelection;

PROCEDURE GetLastSelection*(VAR text : Text; VAR from, to : TextPosition) : BOOLEAN;
BEGIN {EXCLUSIVE}
	text := lastSelText; from := lastSelFrom; to := lastSelTo;
	RETURN text # NIL
END GetLastSelection;

PROCEDURE SetLastText*(text : Text);
BEGIN 
	BEGIN	{EXCLUSIVE}
		lastText := text
	END;	
	onLastTextChanged.Call(text)
END SetLastText;

PROCEDURE GetLastText*() : Text;
BEGIN {EXCLUSIVE}
	RETURN lastText
END GetLastText;

BEGIN
	NEW(onTextChangedStr, 16); COPY("onTextChanged", onTextChangedStr^);
	NEW(onLastTextChanged, NIL, Utilities.NewString("OnLastTextChanged"), 
		Utilities.NewString("fired when the last selection is changed"), NIL);
	NEW(onLastSelectionChanged, NIL, Utilities.NewString("OnLastSelectionChanged"), 
			Utilities.NewString("fired when the last marked text is changed"), NIL);
	NEW(clipboard)
END AosTexts.

