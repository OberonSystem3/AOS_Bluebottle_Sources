MODULE DiffLib; (** AUTHOR "Florian Negele"; PURPOSE "The difference is in the text-file!"; *)

IMPORT
	AosOut, AosTexts, AosTextUtilities, AosIO, AosCommands, Utilities;
		
CONST
	lineBufferSize = 1000;
	maxLineSize = 256;
	
	dirNone = 0;
	dirLeft = 1;
	dirUp = 2;
	dirRight = 4;
	dirDown = 5; 
	dirDiag = 6;

VAR
	separator: BOOLEAN;
	
TYPE
	LineBuffer = POINTER TO RECORD
		lines: ARRAY lineBufferSize OF LONGINT;
		next: LineBuffer;
		size: LONGINT;
	END;
	
	Element = RECORD
		val: LONGINT;
		dir: LONGINT;
	END;
	
	Handler* = PROCEDURE {DELEGATE} (pos, line: LONGINT; string: Utilities.String);
	EmptyHandler* = PROCEDURE {DELEGATE};
	SetupHandler* = PROCEDURE {DELEGATE} (nofLines: LONGINT);

	PROCEDURE GetLinePos (lineBuffer: LineBuffer; offset: LONGINT): LONGINT;
	BEGIN
		WHILE offset >= lineBuffer.size DO
			DEC (offset, lineBuffer.size);
			lineBuffer := lineBuffer.next;
		END;
		RETURN lineBuffer.lines[offset];
	END GetLinePos;

	PROCEDURE GetLineBuffer (reader: AosTexts.TextReader; VAR size: LONGINT): LineBuffer;
	VAR
		first, current: LineBuffer;
		ch: LONGINT;
	BEGIN
		NEW (first);
		current := first;
		current.size := 0;
		size := 0;
		
		REPEAT
			IF (current.size = lineBufferSize) THEN
				NEW (current.next);
				current := current.next;
				current.size := 0;
			END;
			current.lines[current.size] := reader.GetPosition ();
			INC (current.size);
			INC (size);
			REPEAT
				reader.ReadCh (ch);
			UNTIL reader.eot OR (ch = AosTexts.NewLineChar);
		UNTIL reader.eot;
		RETURN first;	
	END GetLineBuffer;
	
	PROCEDURE ReadLine (pos: LONGINT; reader: AosTexts.TextReader): Utilities.String;
	VAR
		ch, i: LONGINT;
		string: Utilities.String;
	BEGIN
		reader.SetPosition (pos);
		i := 0;
		NEW (string, maxLineSize + 1);
		LOOP
			reader.ReadCh (ch);
			IF reader.eot OR (ch = AosTexts.NewLineChar) OR (i = maxLineSize) THEN
				EXIT
			ELSE
				string[i] := CHR (ch);
				INC (i);
			END;
		END;
		string[i] := 0X;
		RETURN string;			
	END ReadLine;
	
	PROCEDURE Diff* (leftFile, rightFile: ARRAY OF CHAR; setup: SetupHandler; leftDiff, rightDiff, leftEqual, rightEqual: Handler; emptyLeft, emptyRight: EmptyHandler);
	VAR
		leftText, rightText: AosTexts.Text;
		leftReader, rightReader: AosTexts.TextReader;
		format, res: LONGINT;
		leftBuffer, rightBuffer, left, right: LineBuffer;
		width, height : LONGINT;
		table: POINTER TO ARRAY OF ARRAY OF Element;
		x, y: LONGINT;
		
		PROCEDURE CompareLines (left, right: LONGINT): BOOLEAN;
		VAR
			leftCh, rightCh: LONGINT;
		BEGIN
			leftReader.SetPosition (GetLinePos (leftBuffer, left));
			rightReader.SetPosition (GetLinePos (rightBuffer, right));

			LOOP
				leftReader.ReadCh (leftCh);
				rightReader.ReadCh (rightCh);
				
				IF leftReader.eot & rightReader.eot THEN RETURN TRUE END;
			
				IF leftCh # rightCh THEN RETURN FALSE END;
				
				IF (leftCh = AosTexts.NewLineChar) OR (rightCh = AosTexts.NewLineChar) THEN
					RETURN leftCh = rightCh;
				END;
			END;
		END CompareLines;
	
	BEGIN
		NEW (leftText);
		AosTextUtilities.LoadAuto(leftText, leftFile, format, res);
		leftText.AcquireRead;
		NEW (leftReader, leftText);
		leftReader.SetPosition (0);

		NEW (rightText);
		AosTextUtilities.LoadAuto(rightText, rightFile, format, res);
		rightText.AcquireRead;
		NEW (rightReader, rightText);
		rightReader.SetPosition (0);
		
		leftBuffer := GetLineBuffer (leftReader, width);
		rightBuffer := GetLineBuffer (rightReader, height);
		IF setup # NIL THEN setup(width + height); END;

		NEW (table, width + 1, height + 1);

		table[0, 0].val := 0;
		table[0, 0].dir := 0;

		FOR x := 1 TO width DO
			table[x, 0].val := 0;
			table[x, 0].dir := dirLeft;
		END;

		FOR y := 1 TO height DO
			table[0, y].val := 0;
			table[0, y].dir := dirUp;
		END;

		left := leftBuffer;
		right := rightBuffer;

		FOR y := 1 TO height DO
			FOR x := 1 TO width DO
				IF CompareLines (x - 1, y - 1) THEN
					table[x, y].val := table[x - 1, y - 1].val + 1;
					table[x, y].dir := dirDiag;
				ELSE
					format := table[x - 1, y].val;
					res := table[x, y - 1].val;
					IF format > res THEN
						table[x, y].val := format;
						table[x, y].dir := dirLeft;
					ELSE
						table[x, y].val := res;
						table[x, y].dir := dirUp;
					END;
				END;
			END;
		END;
		
		(* DEC (x); DEC (y); *)
		x := width; y := height;

		WHILE (x # 0) OR (y # 0) DO
			CASE table[x, y].dir OF
			dirUp:
				DEC (y); table[x, y].val := dirDown;
			| dirLeft:
				DEC (x); table[x, y].val := dirRight;
			| dirDiag:
				DEC (x); DEC (y); table[x, y].val := dirDiag;
			END
		END;
		
		WHILE (x # width) OR (y # height) DO
			CASE table[x, y].val OF
			dirDown:
				INC (y); Handle (y, rightReader, rightBuffer, rightDiff); IF emptyLeft # NIL THEN emptyLeft; END;
			| dirRight:
				INC (x); Handle (x, leftReader, leftBuffer, leftDiff); IF emptyRight # NIL THEN emptyRight; END;
			| dirDiag:
				INC (x); Handle (x, leftReader, leftBuffer, leftEqual);
				INC (y); Handle (y, rightReader, rightBuffer, rightEqual);
			END
		END;
	END Diff;
		
	PROCEDURE Handle (line: LONGINT; reader: AosTexts.TextReader; buffer: LineBuffer; handler: Handler);
	VAR
		pos: LONGINT;
	BEGIN
		IF handler # NIL THEN
			pos := GetLinePos (buffer, line - 1);
			handler (pos, line, ReadLine (pos, reader));
		END
	END Handle;
	
	PROCEDURE Left (pos, line: LONGINT; string: Utilities.String);
	BEGIN
		AosOut.String (		"< ("); AosOut.Int (line, 0); AosOut.Char (':');
		AosOut.Int (pos, 0); AosOut.String (") "); AosOut.String (string^); AosOut.Ln;
		separator := TRUE;
	END Left;
	
	PROCEDURE Right (pos, line: LONGINT; string: Utilities.String);
	BEGIN
		AosOut.String ("> ("); AosOut.Int (line, 0); AosOut.Char (':');
		AosOut.Int (pos, 0); AosOut.String (") "); AosOut.String (string^); AosOut.Ln;
		separator := TRUE;
	END Right;
	
	PROCEDURE Equal (pos, line: LONGINT; string: Utilities.String);
	BEGIN
		IF separator THEN AosOut.Ln; separator := FALSE END
	END Equal;
		
	PROCEDURE Compare* (par: PTR): PTR;
	VAR
		S: AosIO.StringReader; s: AosCommands.Parameters;
		left, right: ARRAY 64 OF CHAR;
	BEGIN
		s := par (AosCommands.Parameters);
		NEW(S, LEN(s.str^));
		S.Set(s.str^);

		S.SkipWhitespace;
		S.String (left);

		S.SkipWhitespace;
		S.String (right);
		
		AosOut.String ("< "); AosOut.String (left); AosOut.Ln;
		AosOut.String ("> "); AosOut.String (right); AosOut.Ln;
		AosOut.Ln;
		
		separator := FALSE;
		
		Diff (left, right, NIL, Left, Right, Equal, Equal, NIL, NIL);
		RETURN NIL;
	END Compare;

END DiffLib.

S.Free DiffLib~
DiffLib.Compare DiffTest1.Text DiffTest2.Text~

DiffLib.Compare AosConfig.XML AosConfig.XML.Bk ~
