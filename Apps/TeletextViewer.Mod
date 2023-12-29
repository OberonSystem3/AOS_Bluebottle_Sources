MODULE TeletextViewer;	(** AUTHOR "PK/TF"; PURPOSE "Editor Application based on WMEditorComponents"; *)

IMPORT
	AosOut, AosModules, DynamicStrings, AosCommands, Standard := WMStandardComponents,
	(*Advanced := WMAdvancedComponents, *)WM := WMWindowManager, Base := WMComponents,
	Messages := WMMessages, Graphics := WMGraphics, Editor:= WMEditors, Utilities,
	AosTextUtilities, AosTexts, AosFS, AosTV, TeletextFont;

CONST
	Red = 0FF0000FFH;
	Green = 0FF00FFH;
	Blue = 0FFFFH;
	Yellow = 0FFFF00FFH;
	Magenta = 0FF00FFFFH;
	Cyan = 0FFFFFFH;
	White = 0FFFFFFFFH;
	Black = 0010101FFH;

TYPE
	Window = OBJECT (Base.FormWindow)
	VAR 
		panel, magazines, categories, navi : Standard.Panel;
		back, forward, nextSub, prevSub, channel, refresh : Standard.Button;
		ch: AosTV.TVChannel;
		freq: LONGINT;
		pageNo, subPageNo : LONGINT;
		
		mag : ARRAY 8 OF Standard.Button;
		page10 : ARRAY 9 OF Standard.Button;
		
		nrEditor, teleText: Editor.Editor;
		
		colorScheme : BOOLEAN;
		suite : AosTV.TeletextSuite;
		
		PROCEDURE &New;
		VAR i : LONGINT;
		magCaption : ARRAY 50 OF CHAR;
		BEGIN
			(* add a panel *)
			NEW(panel);
			panel.bounds.SetWidth(700); panel.bounds.SetHeight(473);
			
			(* add a toolbar for navigation *)
			NEW(navi); navi.bounds.SetHeight(25); navi.alignment.Set(Base.AlignTop);

			(* back button *)
			NEW(back); back.bounds.SetHeight(25); back.alignment.Set(Base.AlignLeft);
			back.bounds.SetWidth(30); back.caption.SetAOC("<I");
			back.onClick.Add(OnBack);
			navi.AddContent(back);
			
			(* add an editor for the page number *)
			NEW(nrEditor);
			nrEditor.bounds.SetWidth(100);
			nrEditor.alignment.Set(Base.AlignLeft); nrEditor.multiLine.Set(FALSE);
			nrEditor.onEnter.Add(OnLoad);
			nrEditor.SetAsString("100");
			navi.AddContent(nrEditor);
			
			(* forward button *)
			NEW(forward); forward.bounds.SetHeight(25); forward.alignment.Set(Base.AlignLeft);
			forward.bounds.SetWidth(30); forward.caption.SetAOC("I>");
			forward.onClick.Add(OnForward);
			navi.AddContent(forward);
			
			(* previous subpage button *)
			NEW(prevSub); prevSub.bounds.SetHeight(25); prevSub.alignment.Set(Base.AlignLeft);
			prevSub.bounds.SetWidth(50); prevSub.caption.SetAOC("sub -");
			prevSub.onClick.Add(OnPrevSub);
			navi.AddContent(prevSub);
			
			(* next subpage button *)
			NEW(nextSub); nextSub.bounds.SetHeight(25); nextSub.alignment.Set(Base.AlignLeft);
			nextSub.bounds.SetWidth(50); nextSub.caption.SetAOC("sub +");
			nextSub.onClick.Add(OnNextSub);
			navi.AddContent(nextSub);
			
			(* refresh button *)
			NEW(refresh); refresh.bounds.SetHeight(25); refresh.alignment.Set(Base.AlignLeft);
			refresh.bounds.SetWidth(140); refresh.caption.SetAOC("Refresh Data Cache");
			refresh.onClick.Add(OnRefresh);
			navi.AddContent(refresh);
			
			panel.AddContent(navi);
			
			(* add a toolbar for magazine pages (n*100) *)
			NEW(magazines); magazines.bounds.SetHeight(300); magazines.alignment.Set(Base.AlignLeft);
			magazines.bounds.SetWidth(160);
			magazines.fillColor.Set (000000FFH);
			
			(* magazine buttons *)
			magCaption := "000";
			FOR i := 0 TO 7 DO
				NEW(mag[i]);
				mag[i].bounds.SetHeight(56);
				mag[i].alignment.Set(Base.AlignTop);
				magCaption[0] := CHR((ORD('1') + i));
				mag[i].caption.SetAOC(magCaption);
				mag[i].fillColor.Set(009933FFH);
				mag[i].onClick.Add (OnMagClick);
				magazines.AddContent(mag[i]);
			END;
						
			panel.AddContent(magazines);
			
			(* add viewer for the teletext data *)
			NEW(teleText);
			teleText.alignment.Set(Base.AlignClient);
			teleText.tv.SetWrapMode({});
			teleText.allowScrollbars.Set(FALSE);
			panel.AddContent(teleText);
			
			(* create the form window with panel size *)
			Init(panel.bounds.GetWidth(), panel.bounds.GetHeight(), FALSE);
			SetContent(panel);
(*			nrEditor.SetDefaultTextColor(0FFH);
			teleText.SetDefaultTextColor(0FFFFFFFFH);*)
			teleText.tv.SetFont(TeletextFont.bimbofont);
(*			teleText.SetHasVScrollbar(FALSE);*)
(*			teleText.SetReadOnly (TRUE);*)
			panel.fillColor.Set(Graphics.RGBAToColor(230, 230, 230, 255));
			panel.fillColor.Set(Graphics.RGBAToColor(0, 0, 0, 255));
			
			(* open the window *)
			manager := WM.GetDefaultManager();
			SetTitle(WM.NewString("Teletext"));
			manager.Add(100, 100, SELF, {WM.FlagFrame});
			
			colorScheme := FALSE;
			
			pageNo := 0;
			subPageNo := -1;
			freq := AosTV.GetFreq();
			
			LoadPage;
		END New;
	
		PROCEDURE Close;
		BEGIN
			FreeWindow;
			Close^
		END Close;
		
		PROCEDURE OnMagClick (sender, data: PTR);
		VAR
			button: Standard.Button;
			buttonNo: LONGINT;
		BEGIN
			button := sender (Standard.Button);
			buttonNo := FindButton (button);
			pageNo := 100*buttonNo;
			subPageNo := -1;
			LoadPage;
		END OnMagClick;
		
		PROCEDURE FindButton (button: Standard.Button): LONGINT;
		VAR i: LONGINT;
		BEGIN
			i := 0;
			WHILE (i < 8) & (mag[i] # button) DO
				INC(i)
			END;
			RETURN i
		END FindButton;
		
		(* page in range 0-799!! *)
		PROCEDURE LoadPage;
		VAR
			nr : ARRAY 4 OF CHAR;
			text: AosTexts.Text;
		BEGIN
			IF (pageNo < 0) OR (pageNo >= 800) THEN
				(* invalid page *)
				SetTitle(WM.NewString("Teletext < Invalid Page >"));
				RETURN
			END;
			
			text := AosTV.GetTeletextPage (freq, pageNo, subPageNo);
			SetText (text);
		END LoadPage;
				
		PROCEDURE OnBack (sender, data : PTR);
		VAR
			text: AosTexts.Text;
		BEGIN
			text := AosTV.GetPrevTeletextPage (freq, pageNo, subPageNo);
			SetText (text);
		END OnBack;
		
		PROCEDURE OnForward (sender, data : PTR);
		VAR
			text: AosTexts.Text;
		BEGIN
			text := AosTV.GetNextTeletextPage (freq, pageNo, subPageNo);
			SetText (text);
		END OnForward;

		PROCEDURE OnLoad (sender, data : PTR);
		VAR
			tmp: LONGINT;
			nr : ARRAY 4 OF CHAR;
		BEGIN
			nrEditor.GetAsString(nr);
			Utilities.StrToInt(nr, tmp);
			tmp := tmp - 100;
			IF AosTV.GetTeletextPage (freq, tmp, -1) # NIL THEN
				pageNo := tmp;
				subPageNo := -1
			END;
			LoadPage;
		END OnLoad;
		
		PROCEDURE OnPrevSub (sender, data : PTR);
		VAR
			text: AosTexts.Text;
		BEGIN
			text := AosTV.GetPrevSubPage (freq, pageNo, subPageNo);
			SetText (text);
		END OnPrevSub;
		
		PROCEDURE OnNextSub (sender, data : PTR);
		VAR
			text: AosTexts.Text;
		BEGIN
			text := AosTV.GetNextSubPage (freq, pageNo, subPageNo);
			SetText (text);
		END OnNextSub;
		
		PROCEDURE OnRefresh (sender, data : PTR);
		BEGIN
		END OnRefresh;
		
		PROCEDURE SetText (text: AosTexts.Text);
		VAR
			title: ARRAY 15 OF CHAR;
			pnum: ARRAY 4 OF CHAR;
		BEGIN
			title := "Teletext - ";
			IF text # NIL THEN
				Utilities.IntToStr (pageNo+100, pnum);
				Utilities.Append (title, pnum);
				teleText.Acquire;
				teleText.SetText(text);
				teleText.Release;
				nrEditor.SetAsString("");
				SetTitle(WM.NewString(title));
			ELSE
				SetTitle(WM.NewString("Teletext < Page does not exist >"));
			END;
		END SetText;
		
		PROCEDURE OnNrClick (sender, data : PTR);
		BEGIN
			nrEditor.SetAsString("");
		END OnNrClick;
		
	END Window;

VAR window: Window;

PROCEDURE FreeWindow;
BEGIN {EXCLUSIVE}
	window := NIL
END FreeWindow;

PROCEDURE Open* (par: PTR): PTR;
BEGIN {EXCLUSIVE}
	NEW(window);
	RETURN NIL
END Open;

PROCEDURE Cleanup;
BEGIN
	IF window # NIL THEN window.Close END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END TeletextViewer.

Aos.Call TeletextViewer.Open ~
System.Free TeletextViewer ~