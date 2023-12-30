MODULE ExampleTextWriter;	(** AUTHOR "TF"; PURPOSE "Template/Example  for component windows"; *)

(** This program shows the implementation of a multi instance component containing window *)

IMPORT
	Utilities, WMGraphics, WMComponents, WMWindowManager, 
	WMEditors, AosTextUtilities, AosIO, Math;

TYPE
	Window* = OBJECT (WMComponents.FormWindow)
	VAR editor : WMEditors.Editor;
		
		PROCEDURE &New();
		BEGIN
			NEW(editor);  editor.bounds.SetExtents(800, 700);
			editor.fillColor.Set(WMGraphics.White);

			Init(editor.bounds.GetWidth(), editor.bounds.GetHeight(), FALSE);
			SetContent(editor);
			
			 WMWindowManager.DefaultAddWindow(SELF);
			SetTitle(Utilities.NewString("TextWriter Example"));

			WriteToEditor;
		END New;

		PROCEDURE WriteToEditor;
		VAR 
			tw : AosTextUtilities.TextWriter;
			w : AosIO.Writer;
			i : LONGINT;
			buffer : ARRAY 256 OF CHAR;
		BEGIN
			NEW(tw, editor.text);
			w := tw.GetWriter();
			
			tw.SetFontSize(20);
			w.String("This is a simple text. Count from 0 to 10 : "); w.Ln;
			FOR i := 0 TO 10 DO w.Int(i, 5) END; w.Ln;

			tw.SetFontStyle({WMGraphics.FontBold});
			w.String("This is bold. ");

			tw.SetFontStyle({WMGraphics.FontItalic});
			w.String("This is italic."); 
			
			tw.SetFontStyle({WMGraphics.FontBold});
			tw.SetFontColor(WMGraphics.Red);
			w.String("This is bold red."); w.Ln;
			
			tw.SetBgColor(WMGraphics.Black);
			tw.SetFontColor(WMGraphics.White);
			w.String("This is bold white on black"); 
			w.Ln;
			
			tw.SetFontStyle({});
			tw.SetBgColor(WMGraphics.White);
			tw.SetFontColor(WMGraphics.Black);
			
			buffer := "This is a bit fancy! It modulates the vertical offset with a cosine function and fades out.";
			i := 0;
			tw.SetFontStyle({WMGraphics.FontBold});
			WHILE buffer[i] # 0X DO
				tw.SetFontColor(WMGraphics.RGBAToColor(i * 2, i * 2, i * 2, 0FFH));
				tw.SetVerticalOffset(ENTIER(15 * Math.cos(i/4)));
				w.Char(buffer[i]); 
				INC(i)
			END
		END WriteToEditor;
		
	END Window;

PROCEDURE Open*(par : ANY) : ANY;
VAR inst, i2 : Window;
BEGIN
	NEW(inst);
	NEW(i2);
	i2.editor.SetText(inst.editor.text);
	RETURN NIL
END Open;

END ExampleTextWriter.

S.Free ExampleTextWriter ~
ExampleTextWriter.Open 
 