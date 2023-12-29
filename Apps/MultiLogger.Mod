MODULE MultiLogger;

IMPORT
	AosOut, AosIO, AosPipes, UTF8Strings, AosTexts, 
	WMGraphics, WMWindowManager, WMComponents, WMStandardComponents, WMEditors;
TYPE
	 StreamLogger* = OBJECT
	 VAR
		pipe : AosPipes.Pipe;
		r : AosIO.Reader;
		stream : AosIO.Writer;
		text : AosTexts.UnicodeText;
		alive : BOOLEAN;
		ucspos : LONGINT;
		char : AosTexts.Char32;
		ucs32buf : ARRAY 256 OF AosTexts.Char32;
	 	
		PROCEDURE &New(VAR stream : AosIO.Writer; text : AosTexts.UnicodeText);
		BEGIN
			NEW(pipe, 20000);
			NEW(stream, pipe.Send, 20);
			NEW(r, pipe.Receive, 20);
			SELF.stream := stream;
			SELF.text := text
		END New;
		
		PROCEDURE Kill*;
		BEGIN 
			alive := FALSE;
			pipe.Close
		END Kill;
	 		
		PROCEDURE GetUTF8Char(r : AosIO.Reader; VAR u : AosTexts.Char32) : BOOLEAN;
		VAR ch : ARRAY 8 OF CHAR; i : LONGINT;	
		BEGIN
			ch[0] := r.Get();
			FOR i := 1 TO ORD(UTF8Strings.CodeLength[ORD(ch[0])]) - 1 DO ch[i] := r.Get() END;
			i := 0;
			RETURN UTF8Strings.DecodeChar(ch, i, u)
		END GetUTF8Char;
		
	BEGIN {ACTIVE}
		alive := TRUE;
		WHILE alive DO
			ucspos := 0;
			IF GetUTF8Char(r, char) THEN END; ucs32buf[ucspos] := char; INC(ucspos);
			WHILE (r.Available() > 0) & (r.res = 0) DO
				IF GetUTF8Char(r, char) THEN END; ucs32buf[ucspos] := char; INC(ucspos);
				IF ucspos = 255 THEN
					ucs32buf[ucspos] := 0;
					text.AcquireWrite; text.InsertUCS32(text.GetLength(), ucs32buf); text.ReleaseWrite;
					ucspos := 0
				END	
			END;
			ucs32buf[ucspos] := 0;
			IF ucs32buf[0] # 0 THEN
				text.AcquireWrite; text.InsertUCS32(text.GetLength(), ucs32buf); text.ReleaseWrite 
			END
		END;
	END StreamLogger;
	
TYPE
	LogWindow* = OBJECT (WMComponents.FormWindow)
	VAR 
		panel : WMStandardComponents.Panel;
		out- : WMEditors.Editor;
		logger : StreamLogger;
		open : BOOLEAN;
	
		PROCEDURE &New(title : ARRAY OF CHAR; VAR stream : AosIO.Writer);
		BEGIN
			NEW(panel); panel.bounds.SetExtents(640, 420); panel.fillColor.Set(WMGraphics.RGBAToColor(255, 255, 255, 255));
			NEW(out); out.alignment.Set(WMComponents.AlignClient); out.tv.showBorder.Set(TRUE); panel.AddContent(out);
			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), FALSE);
			SetContent(panel);
			manager := WMWindowManager.GetDefaultManager();
			SetTitle(WMComponents.NewString(title));
			manager.Add(100, 100, SELF, {WMWindowManager.FlagFrame});
			NEW(logger, stream, out.text);
			open := TRUE
		END New;

		PROCEDURE Stop*;
		BEGIN
			logger.Kill
		END Stop;
		
		PROCEDURE Close;
		BEGIN
			logger.Kill;
			Close^
		END Close;
		
	END LogWindow;

END MultiLogger.
