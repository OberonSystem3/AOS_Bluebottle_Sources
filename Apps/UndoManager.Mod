MODULE UndoManager;

IMPORT
	AosOut, AosTexts, AosTextUtilities;	


CONST
	None = 99;
	CStyle = 100;
	PStyle = 101;	
	Attribute = 102;
	SpecialPiece = 103;

	AdvancedUndoStrategy = TRUE;

	TYPE UndoManager*= OBJECT(AosTexts.UndoManager)
		VAR 
			text: AosTexts.Text;
			undoQu, redoQu: Buffer;
			objUpdate: StyleUpdateInfo;
			nrUndoUpdates-, nrRedoUpdates-: LONGINT;
			nrUndoListener*, nrRedoListener*: PROCEDURE{DELEGATE}(nrUndos: LONGINT);
			redo: BOOLEAN;
			actualPos-: LONGINT;			
			
		PROCEDURE & New(memorySize: LONGINT; redo: BOOLEAN);
		BEGIN
			SELF.redo := redo;
			IF memorySize <= 0 THEN
				memorySize := 1001
			END;
			
			NEW(undoQu, memorySize);
			
			IF redo THEN
				NEW(redoQu, memorySize)
			END
		END New;
		
		PROCEDURE IncNrUndo;
		BEGIN
			INC(nrUndoUpdates);
			IF nrUndoListener # NIL THEN nrUndoListener(nrUndoUpdates) END
		END IncNrUndo;
				
		PROCEDURE DecNrUndo;
		BEGIN
			DEC(nrUndoUpdates);
			IF nrUndoListener # NIL THEN nrUndoListener(nrUndoUpdates) END
		END DecNrUndo;
		
		PROCEDURE IncNrRedo;
		BEGIN
			INC(nrRedoUpdates);
			IF nrRedoListener # NIL THEN nrRedoListener(nrRedoUpdates) END
		END IncNrRedo;
				
		PROCEDURE DecNrRedo;
		BEGIN
			DEC(nrRedoUpdates);
			IF nrRedoListener # NIL THEN nrRedoListener(nrRedoUpdates) END
		END DecNrRedo;
		
		PROCEDURE ResetRedo;
		BEGIN
			nrRedoUpdates := 0;
			IF nrRedoListener # NIL THEN nrRedoListener(nrRedoUpdates) END;
			redoQu.Clear()
		END ResetRedo;		
				
		PROCEDURE NextOperation(u: UpdateInfo);
		VAR ui: UpdateInfo;
		BEGIN
			IF undoQu.IsFull() THEN
				ui := undoQu.RemoveOldest();				
				DecNrUndo;
			END;			
			
			undoQu.Push(u);
				
			IncNrUndo;
		END NextOperation;
		
		PROCEDURE SaveOperation(u: UpdateInfo);
		BEGIN
			IF ~redo THEN RETURN END;
			redoQu.Push(u);
			IncNrRedo;
		END SaveOperation;
		
		
		
		PROCEDURE InsertText*(pos: LONGINT; text: AosTexts.Text);
		VAR i: InsertUpdateInfo; char: ARRAY 7 OF CHAR; u:UpdateInfo; tr: AosTexts.TextReader; ucs32: LONGINT;
		BEGIN					
			ResetRedo;
			text.AcquireRead;				
			IF ~(undoQu.IsEmpty()) & (undoQu.Peek()  IS InsertUpdateInfo) & (text.GetLength() = 1) THEN
				u := undoQu.Peek();
				i := u(InsertUpdateInfo);				
				IF (~u.sealed) & (i.pos + i.len = pos) THEN
					i.t.AcquireWrite;
					i.t.CopyFromText(text, 0, text.GetLength(), i.len);
					i.len := i.len + text.GetLength();
					i.t.ReleaseWrite;

					NEW(tr, text);
					tr.ReadCh(ucs32);
					IF IsSeparator(ucs32) THEN i.sealed := TRUE END;
					text.ReleaseRead;
					
					RETURN					
				END
			END;
			text.ReleaseRead;
			NEW(i, pos, text);
			NextOperation(i);
		END InsertText;

		PROCEDURE DeleteText*(pos: LONGINT; text: AosTexts.Text);
		VAR d: DeleteUpdateInfo; char: ARRAY 2 OF CHAR;
			str: POINTER TO ARRAY OF CHAR; u: UpdateInfo;			
		BEGIN
			ResetRedo;
			text.AcquireRead;
			IF (~ undoQu.IsEmpty()) & (undoQu.Peek() IS DeleteUpdateInfo) & (text.GetLength() = 1) THEN
				u := undoQu.Peek();
				d := u(DeleteUpdateInfo);
				IF (d.pos = pos) THEN (* Delete key *)
					d.t.AcquireWrite;
					d.t.CopyFromText(text, 0, text.GetLength(),d.len);
					d.len := d.len + text.GetLength();
					d.t.ReleaseWrite;
					RETURN
				ELSIF (d.pos - 1 = pos) THEN (* Backspace key *)	
					d.t.AcquireWrite;
					d.t.CopyFromText(text, 0, text.GetLength(), 0);
					d.pos := pos;
					d.len := d.len + text.GetLength();
					d.t.ReleaseWrite;
					RETURN					
				END;
			END;
			text.ReleaseRead;
			
			NEW(d, pos, text);
			NextOperation(d);			
		END DeleteText;
		
		PROCEDURE BeginObjectChange*(pos: LONGINT);
		BEGIN
			NEW(objUpdate, pos);
		END BeginObjectChange;
						
		PROCEDURE ObjectChanged*(pos, len, type: LONGINT; obj: ANY);
		BEGIN			
			objUpdate.Append(pos, len, obj, type)
		END ObjectChanged;
		
		PROCEDURE EndObjectChange(len, type: LONGINT; to: ANY);
		BEGIN
			ResetRedo;
			objUpdate.len := len;
			objUpdate.type := type;
			objUpdate.new := to;
			NextOperation(objUpdate);
			objUpdate := NIL			
		END EndObjectChange;
		
		PROCEDURE SetText*(text: AosTexts.Text);
		BEGIN
			SELF.text := text;
		END SetText;		
		
		PROCEDURE Undo*;
		VAR temp: AosTexts.Text; ui: UpdateInfo;
		BEGIN
			temp := SELF.text;
			IF temp # NIL THEN
				temp.AcquireWrite;
				IF ~ undoQu.IsEmpty() THEN				
					ui := undoQu.Pop();
					temp.SetUndoManager(NIL); (* Disable recording *)
					ui.Undo(temp);
					temp.SetUndoManager(SELF); (* Re-enable recording *)
					DecNrUndo;																				
					SaveOperation(ui);					
					actualPos := ui.pos;
				END;
				temp.ReleaseWrite
			END
		END Undo;									
		
		PROCEDURE Redo*;
		VAR temp: AosTexts.Text; ui: UpdateInfo;
		BEGIN
			IF ~redo THEN RETURN END;
			temp := SELF.text;
			IF temp # NIL THEN
				temp.AcquireWrite;
				IF ~ redoQu.IsEmpty() THEN				
					ui := redoQu.Pop();
					temp.SetUndoManager(NIL); (* Disable recording *)
					ui.Redo(temp);
					temp.SetUndoManager(SELF); (* Re-enable recording *)
					DecNrRedo;
					NextOperation(ui);
					actualPos := ui.pos;
				END;
				temp.ReleaseWrite
			END
		END Redo;									
					
	END UndoManager;	

	Buffer = OBJECT
		VAR head, num: LONGINT; buffer: POINTER TO ARRAY OF UpdateInfo;
		
		PROCEDURE Push*(x: UpdateInfo);
		BEGIN
			ASSERT(num <= LEN(buffer));
			buffer[(head+num) MOD LEN(buffer)] := x;
			INC(num)
		END Push;

		PROCEDURE RemoveOldest*(): UpdateInfo;
		VAR x: UpdateInfo;
		BEGIN
			x := buffer[head];
			head := (head+1) MOD LEN(buffer);
			DEC(num);
			RETURN x
		END RemoveOldest;
					
		PROCEDURE Peek*(): UpdateInfo;
		BEGIN
			RETURN buffer[((head+num - 1) MOD LEN(buffer))]
		END Peek;				
		
		PROCEDURE Pop*(): UpdateInfo;
		VAR x: UpdateInfo;
		BEGIN
			x := buffer[((head+num - 1) MOD LEN(buffer))];			
			DEC(num);
			RETURN x
		END Pop;
		
		
		PROCEDURE IsFull*(): BOOLEAN;
		BEGIN
			RETURN num = LEN(buffer)
		END IsFull;
		
		PROCEDURE IsEmpty*(): BOOLEAN;
		BEGIN
			RETURN num = 0
		END IsEmpty;
		
		
		PROCEDURE Clear*;
		BEGIN
			head := 0; num := 0;
		END Clear;
					

		PROCEDURE &Init(n: LONGINT);
		BEGIN
			head := 0; num := 0; NEW(buffer, n)
		END Init;
		
	END Buffer;
	
	UpdateInfo= OBJECT	
		VAR
			pos : LONGINT;
			sealed*: BOOLEAN;
					
		PROCEDURE Undo(text: AosTexts.Text);
		BEGIN
			
		END Undo;
			
		PROCEDURE Redo(text: AosTexts.Text);
		BEGIN
			
		END Redo;

														
	END UpdateInfo;
			

	InsertUpdateInfo= OBJECT(UpdateInfo)
		VAR 
			len: LONGINT;
			t: AosTexts.Text;
			
		PROCEDURE &New(pos: LONGINT; text: AosTexts.Text);
		BEGIN
			SELF.pos := pos;
			SELF.t := text;
			t.AcquireRead;
			SELF.len := t.GetLength();
			t.ReleaseRead;			
		END New;
		
		PROCEDURE Undo(text: AosTexts.Text);
		BEGIN
			t.AcquireRead;
			text.Delete(pos, t.GetLength());
			t.ReleaseRead;
		END Undo;
						
		PROCEDURE Redo(text: AosTexts.Text);
		BEGIN
			t.AcquireRead;
			text.CopyFromText(t, 0, t.GetLength(), pos);
			t.ReleaseRead;
		END Redo;
		
	END InsertUpdateInfo;
	
	DeleteUpdateInfo= OBJECT(UpdateInfo)
		VAR
			pos, len: LONGINT; 
			t: AosTexts.Text;
			
		PROCEDURE &New(pos: LONGINT; text: AosTexts.Text);
		BEGIN
			SELF.pos := pos;
			SELF.t := text;		
			t.AcquireRead;
			SELF.len := t.GetLength();
			t.ReleaseRead;				
		END New;
		
		PROCEDURE Undo(text: AosTexts.Text);
		BEGIN
			t.AcquireRead;
			text.CopyFromText(t, 0, t.GetLength(), pos);
			t.ReleaseRead;
		END Undo;
		
		PROCEDURE Redo(text: AosTexts.Text);
		BEGIN
			t.AcquireRead;
			text.Delete(pos, t.GetLength());
			t.ReleaseRead;
		END Redo;
						
	END DeleteUpdateInfo;
	
	
	ObjectUpdateInfo= OBJECT(UpdateInfo)
		VAR 
			n: AosTexts.Piece;
		
		PROCEDURE &New(pos: LONGINT; n: AosTexts.Piece);
		BEGIN
			SELF.pos := pos;
			SELF.n := n;
		END New;
		
		PROCEDURE Undo(text: AosTexts.Text);
		BEGIN
			IF n # NIL THEN 	text.Delete(pos, n.len) END;
		END Undo;
					
	END ObjectUpdateInfo;
	
	
	StyleInfo= POINTER TO RECORD
		next: StyleInfo;
		pos, len: LONGINT;
		style: ANY;			
		type: LONGINT;
	END;
	
	
	StyleUpdateInfo= OBJECT(UpdateInfo)
		VAR 
			len, type: LONGINT;
			new: ANY;
			old: StyleInfo;			
						
		PROCEDURE &New(pos: LONGINT);
		BEGIN
			SELF.pos := pos;
		END New;
		
		PROCEDURE Append(pos, len: LONGINT; style: ANY; type: LONGINT);
		VAR ai: StyleInfo;		
		BEGIN
			NEW(ai);
			ai.next := old;
			ai.pos := pos;
			ai.len := len;
			ai.style := style;
			ai.type := type;
			old := ai						
		END Append;		
		
		PROCEDURE SetObject(new: ANY);
		BEGIN
			SELF.new := new;
		END SetObject;
		
		PROCEDURE SetLen(len: LONGINT);
		BEGIN
			SELF.len := len;
		END SetLen;
		
		PROCEDURE SetStyle*(textpos, len: LONGINT; style: ANY);
		BEGIN
		END SetStyle;
		
		PROCEDURE Undo(text: AosTexts.Text);
		VAR cur: StyleInfo;
		BEGIN
			cur := old;
			WHILE cur # NIL DO
				CASE cur.type OF
					Attribute:
						IF cur.style # NIL THEN
							text.SetAttributes(cur.pos, cur.len, cur.style(AosTexts.Attributes))
						ELSE
							text.SetAttributes(cur.pos, cur.len, NIL)
						END
					| CStyle:
						IF cur.style # NIL THEN
							text.SetCharacterStyle(cur.pos, cur.len, cur.style(AosTexts.CharacterStyle))
						ELSE
							text.SetCharacterStyle(cur.pos, cur.len, NIL)
						END
					| PStyle:
						IF cur.style # NIL THEN
							text.SetParagraphStyle(cur.pos, cur.len, cur.style(AosTexts.ParagraphStyle))
						ELSE
							text.SetParagraphStyle(cur.pos, cur.len, NIL)
						END
				END;
				cur := cur.next;					
			END;
		END Undo;
		
		PROCEDURE Redo(text: AosTexts.Text);
		VAR cur: StyleInfo;
		BEGIN
			CASE type OF
				Attribute:
					IF new # NIL THEN
						text.SetAttributes(pos, len, new(AosTexts.Attributes))
					ELSE
						text.SetAttributes(pos, len, NIL)
					END
				| CStyle:
					IF new # NIL THEN
						text.SetCharacterStyle(pos, len, new(AosTexts.CharacterStyle))
					ELSE
						text.SetCharacterStyle(pos, len, NIL)
					END
				| PStyle:
					IF new # NIL THEN
						text.SetParagraphStyle(pos, len, new(AosTexts.ParagraphStyle))
					ELSE
						text.SetParagraphStyle(pos, len, NIL)
					END
			END
		END Redo;
						
	END StyleUpdateInfo;	
	
	
PROCEDURE IsSeparator(uc: AosTexts.Char32): BOOLEAN;
BEGIN
	CASE uc OF
		 AosTexts.NewLineChar: RETURN TRUE
		 | AosTexts.TabChar: IF AdvancedUndoStrategy THEN RETURN TRUE ELSE RETURN FALSE END
		 | AosTexts.SpaceChar: IF AdvancedUndoStrategy THEN RETURN TRUE ELSE RETURN FALSE END
	ELSE
		RETURN FALSE;
	END
END IsSeparator;
	
END UndoManager.
