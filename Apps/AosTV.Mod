MODULE AosTV;	(** AUTHOR "fr@felix.shacknet.nu", PURPOSE "AOS TV application"; *)

IMPORT AosKernel, AosMemory, AosOut, WM := WMWindowManager, AosCommands, AosIO
, Utilities,
	AosTVDriver, WMRectangles, Graphics := WMGraphics, Messages := WMMessages, AosFS, 
	 SYSTEM, AosTexts, DynamicStrings, Base := WMComponents,  Out := AosOut,
	Standard := WMStandardComponents, XMLScanner, XMLParser, XML, XMLObjects;

CONST
	F = FALSE;
	T = TRUE;

	DEBUG = F;
	VtPageSize = 40*24;
(*	VtPageSize = 1000;*)

	Red = 0FF0000FFH;
	Green = 0FF00FFH;
	Blue = 0FFFFH;
	Yellow = 0FFFF00FFH;
	Magenta = 0FF00FFFFH;
	Cyan = 0FFFFFFH;
	White = 0FFFFFFFFH;
	Black = 0010101FFH;

	ChannelFile = "AosTVchannels.XML";

TYPE
	TVChannel* = OBJECT
	VAR
		name*: ARRAY 33 OF CHAR;
		freq*: LONGINT;
	END TVChannel;

	ChannelArray = POINTER TO ARRAY OF TVChannel;
	
	(** Generic Lockable Object List. *)
	ChannelList* = OBJECT 
		VAR
			list : ChannelArray;
			count : LONGINT;
			readLock : LONGINT;
		
		PROCEDURE &New*();
		BEGIN NEW(list, 8); readLock := 0
		END New;
		
		(** return the number of objects in the list. If count is used for indexing elements (e.g. FOR - Loop) in a multi-process 
			situation, the process calling the GetCount method should call Lock before GetCount and Unlock after the
			last use of an index based on GetCount *)
		PROCEDURE GetCount*():LONGINT;
		BEGIN
			RETURN count
		END GetCount;
		
		PROCEDURE Grow;
		VAR old: ChannelArray;
				i : LONGINT;
		BEGIN
			old := list;
			NEW(list, LEN(list)*2);
			FOR i := 0 TO count-1 DO list[i] := old[i] END
		END Grow;
		
		(** Add an object to the list. Add may block if number of calls to Lock is bigger than the number of calls to Unlock *)
		PROCEDURE Add*(x : TVChannel);
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			IF count = LEN(list) THEN Grow END;
			list[count] := x;
			INC(count)
		END Add;
		
		(** atomic replace x by y *)
		PROCEDURE Replace*(x, y : TVChannel);
		VAR i : LONGINT;
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			i := IndexOf(x);
			IF i >= 0 THEN list[i] := y END
		END Replace;
		
		(** return the index of an object. In a multi-process situation, the process calling the IndexOf method should 
			call Lock before IndexOf and Unlock after the last use of an index based on IndexOf.
			If the object is not found, -1 is returned *)
		PROCEDURE IndexOf *(x: TVChannel) : LONGINT;
		VAR i : LONGINT;
		BEGIN
			i := 0 ; WHILE i < count DO IF list[i] = x THEN RETURN i END; INC(i) END;
			RETURN -1
		END IndexOf;
		
		(** Remove an object from the list. Remove may block if number of calls to Lock is bigger than the number of calls to Unlock *)
		PROCEDURE Remove*(x : TVChannel);
		VAR i : LONGINT;
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			i:=0; WHILE (i<count) & (list[i]#x) DO INC(i) END;
			IF i<count THEN 
				WHILE (i<count-1) DO list[i]:=list[i+1]; INC(i) END;
				DEC(count);
				list[count]:=NIL
			END
		END Remove;
		
		(** Removes all objects from the list. Clear may block if number of calls to Lock is bigger than the number of calls to Unlock *)
		PROCEDURE Clear*;
		VAR i : LONGINT;
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			FOR i := 0 TO count - 1 DO list[i] := NIL END;
			count := 0
		END Clear;
		
		(** return an object based on an index. In a multi-process situation, GetItem is only safe in a locked region Lock / Unlock *)
		PROCEDURE GetItem*(i:LONGINT) : TVChannel;
		BEGIN
			ASSERT((i >= 0) & (i < count), 101);
			RETURN list[i]	
		END GetItem;
		
		(** Lock prevents modifications to the list. All calls to Lock must be followed by a call to Unlock. Lock can be nested*)
		PROCEDURE Lock*;
		BEGIN {EXCLUSIVE}
			INC(readLock); ASSERT(readLock > 0)
		END Lock;
		
		(** Unlock removes one modification lock. All calls to Unlock must be preceeded by a call to Lock. *)
		PROCEDURE Unlock*;
		BEGIN {EXCLUSIVE}
			DEC(readLock); ASSERT(readLock >= 0)
		END Unlock;
	END ChannelList;

TYPE
	ChannelSeeker = OBJECT
	VAR
		dead: BOOLEAN;
		seeking: BOOLEAN;
		stepSize: LONGINT;
		tuner: AosTVDriver.TVTuner;
		sigFound, sigLost: LONGINT;
		
		PROCEDURE &Init(tuner: AosTVDriver.TVTuner);
		BEGIN
			SELF.tuner := tuner;
			dead := FALSE;
			seeking := FALSE;
		END Init;
		
		PROCEDURE SetStepSize(stepSize: LONGINT);
		BEGIN {EXCLUSIVE}
			SELF.stepSize := stepSize;
		END SetStepSize;
		
		PROCEDURE StartSeeking;
		BEGIN {EXCLUSIVE}
			seeking := TRUE;
		END StartSeeking;

		PROCEDURE StopSeeking;
		BEGIN {EXCLUSIVE}
			seeking := FALSE;
		END StopSeeking;
		
		PROCEDURE SeekChannel;
		BEGIN {EXCLUSIVE}
			audio.SetAudioMute;
			(* first get rid of old channel *)
			REPEAT
				tuner.SetTVFrequency(tuner.GetFrequency() + stepSize);
			UNTIL ~seeking OR dead OR ~tuner.IsLocked();
			(* find next channel, save first contact *)
			REPEAT
				tuner.SetTVFrequency(tuner.GetFrequency() + stepSize);
			UNTIL ~seeking OR dead OR tuner.IsLocked();
			sigFound := tuner.GetFrequency();
			(* find point where channel dissapears *)
			REPEAT
				tuner.SetTVFrequency(tuner.GetFrequency() + stepSize);
			UNTIL ~seeking OR dead OR ~tuner.IsLocked();
			sigLost := tuner.GetFrequency();
			(* choose average for new frequency *)
			tuner.SetTVFrequency((sigFound + sigLost) DIV 2);
			seeking := FALSE;
			audio.SetAudioUnmute;
		END SeekChannel;
		
		PROCEDURE Release;
		BEGIN {EXCLUSIVE}
			dead := TRUE;
		END Release;
		
	BEGIN {ACTIVE}
		BEGIN {EXCLUSIVE}
			REPEAT
				AWAIT(dead OR seeking);
				IF ~dead THEN
					SeekChannel;
				END;
			UNTIL dead;
		END;
	END ChannelSeeker;

	TeletextSuite* = OBJECT
	VAR
		channel: TVChannel;
		pages- : ARRAY 800 OF TeletextPage;
		next : TeletextSuite;
		
		PROCEDURE &Init();
		VAR
			i : LONGINT;
		BEGIN
			FOR i := 0 TO 799 DO
				NEW(pages[i]);
				pages[i].data := NIL;
				pages[i].next := VbiUndefined;
				pages[i].prev := VbiUndefined;
			END;
		END Init;
				
		PROCEDURE SetPage(pageNum, subPage : LONGINT; data : ARRAY OF CHAR);
		VAR
			i, j : LONGINT;
			page, new : DataPage;
			teletext : TeletextSuite;
			newPage : BOOLEAN;
			chName : ARRAY 17 OF CHAR;
			ch, fg, bg, begin : LONGINT;
			text: ARRAY 41*24 OF AosTexts.Char32;
			fgColor, bgColor: ARRAY 41*24 OF LONGINT;
			forceAlpha, isGraphics, holdGraphics, isDouble, hasDouble : BOOLEAN;
			attr : AosTexts.Attributes;
			cnt: LONGINT;
			newVersion, monitor: BOOLEAN;
		BEGIN {EXCLUSIVE}
			teletext := vbi.currentSuite;
			
			(* ensure the array entry is an instantiated object *)
			IF teletext.pages[pageNum] = NIL THEN
				NEW(teletext.pages[pageNum]);
			END;
			
			(* subPage: ordered double-linked list *)
			IF teletext.pages[pageNum].data = NIL THEN
				NEW(teletext.pages[pageNum].data);
				page := teletext.pages[pageNum].data;
				
				page.nextSub := page;
				page.prevSub := page;
				newPage := TRUE;
			ELSE
				newPage := FALSE;
				
				page := teletext.pages[pageNum].data;
				
				(* search for the appropriate subpage position in the ordered list *)
				IF subPage < page.subPageNo THEN
					(* new subpage is smaller than all others *)
					NEW(new);
					new.nextSub := page;
					new.prevSub := page.prevSub;
					new.prevSub.nextSub := new;
					page.prevSub := new;
					page := new;
					teletext.pages[pageNum].data := page;
				ELSE
					(* traverse the list backwards to find the insertion position *)
					WHILE (page.prevSub.subPageNo > subPage) DO
						page := page.prevSub;
					END;
					
					page := page.prevSub;
					(* page points now either to the subpage with the next lower index or with the same index *)
					
					IF page.subPageNo # subPage THEN
						(* create a new subPage and insert it in the list *)
						NEW(new);
						new.nextSub := page.nextSub;
						new.prevSub := page;
						page.nextSub := new;
						new.nextSub.prevSub := new;					
						page := new;
					END;
				END;
			END;
			(* page points now to the correct datapage *)
			page.pageNumber := pageNum;
			page.subPageNo := subPage;
			
			FOR i := 0 TO 41*24-1 DO
				text[i] := 0;
				fgColor[i] := 0;
				bgColor[i] := 0;
			END;
			
			(* remove unprintable chars at the beginning of a page *)
			FOR i := 0 TO 7 DO
				text[i] := ORD(' ');
			END;
			
				FOR i := 0 TO 23 DO
					isGraphics := FALSE;
					holdGraphics := FALSE;
					isDouble := FALSE;
					hasDouble := FALSE;
					fg := White;
					bg := Black;
					
					FOR j := 0 TO 39 DO
						
						ch := ORD (data[40*i + j]) MOD 128;
						
						(* Write only to empty cells *)
						IF text[i*41 + j] = 0 THEN
							(* Handle 'Set At' Attributes *)
							CASE ch OF
								  9 : 									 (* Steady (not flashing): TO BE DONE *)
							  | 12 : isDouble := FALSE;		(* normal height *)
							  | 24 : 									 (* Conceal display: TO BE DONE *)
							  | 25 : 									 (* Contiguous graphics: always on *)
							  | 26 : 									 (* Separated graphics: TO BE DONE *)
							  | 28 : bg := Black;					(* black background *)
							  | 29 : bg := fg;						 (* new background *)
							  | 30 : holdGraphics := TRUE;	(* hold graphics *)
							ELSE
							END;
							
							forceAlpha := (ch >= 64) & (ch < 96);
							
							(* Replace non-printable characters by a space *)
							IF (ch < 32) THEN
								IF isGraphics & holdGraphics THEN
									(* hold graphics *)
									text[i*41 + j] := text[i*41 + j-1];
								ELSE
									text[i*41 + j] := 32;	(* space *)
								END;
								IF isDouble THEN
									DoubleHeight (text, i*41 + j);
								END;
							ELSIF isGraphics & (~ forceAlpha) THEN
								(* Offset to mosaic graphics section *)
								text [i*41 + j] := ch + 128;
								IF isDouble THEN
									DoubleHeight (text, i*41 + j);
								END
							ELSE
								(* normal text *)
								(* Take care of the language-specific characters *)
								CASE ch OF
									  35 : text [i*41 + j] := vbi.nationals [vbi.lang][0];
								  |   36 : text [i*41 + j] := vbi.nationals [vbi.lang][1];
								  |   64 : text [i*41 + j] := vbi.nationals [vbi.lang][2];
								  |   91 : text [i*41 + j] := vbi.nationals [vbi.lang][3];
								  |   92 : text [i*41 + j] := vbi.nationals [vbi.lang][4];
								  |   93 : text [i*41 + j] := vbi.nationals [vbi.lang][5];
								  |   94 : text [i*41 + j] := vbi.nationals [vbi.lang][6];
								  |   95 : text [i*41 + j] := vbi.nationals [vbi.lang][7];
								  |   96 : text [i*41 + j] := vbi.nationals [vbi.lang][8];
								  | 123 : text [i*41 + j] := vbi.nationals [vbi.lang][9];
								  | 124 : text [i*41 + j] := vbi.nationals [vbi.lang][10];
								  | 125 : text [i*41 + j] := vbi.nationals [vbi.lang][11];
								  | 126 : text [i*41 + j] := vbi.nationals [vbi.lang][12];
								  | 127 : text [i*41 + j] := 127;	(* filled square *)
								ELSE
									text [i*41 + j] := ch;
								END;
								
								IF isDouble THEN
									DoubleHeight (text, i*41 + j);
								END;
							END;
							
							(* Set attributes for the current character *)
							IF fgColor [i*41 + j] = 0 THEN
								fgColor [i*41 + j] := fg;
								bgColor [i*41 + j] := bg;
							END;
							
							(* Handle 'Set After' Attributes *)
							CASE ch OF
								 0 : isGraphics := FALSE; fg := Black;			(* Black alpha, not documented *)
							 |   1 : isGraphics := FALSE; fg := Red;			  (* Red alpha *)
							 |   2 : isGraphics := FALSE; fg := Green;		  (* Green alpha *)
							 |   3 : isGraphics := FALSE; fg := Yellow;		  (* Yellow alpha *)
							 |   4 : isGraphics := FALSE; fg := Blue;			 (* Blue alpha *)
							 |   5 : isGraphics := FALSE; fg := Magenta;	  (* Magenta alpha *)
							 |   6 : isGraphics := FALSE; fg := Cyan;			(* Cyan alpha *)
							 |   7 : isGraphics := FALSE; fg := White;		  (* White alpha *)
							 
							 |   8 : 															 (* Flashing: TO BE DONE *)
							 | 10 : 															 (* End box: TO BE DONE *)
							 | 11 : 															 (* Start box: TO BE DONE *)
							 | 13 : isDouble := TRUE; hasDouble := TRUE; (* Double height *)
							 
							 | 16 : isGraphics := TRUE; fg := Black;			(* Black graphics, not documented *)
							 | 17 : isGraphics := TRUE; fg := Red;			  (* Red graphics *)
							 | 18 : isGraphics := TRUE; fg := Green;		  (* Green graphics *)
							 | 19 : isGraphics := TRUE; fg := Yellow;		  (* Yellow graphics *)
							 | 20 : isGraphics := TRUE; fg := Blue;			 (* Blue graphics *)
							 | 21 : isGraphics := TRUE; fg := Magenta;	  (* Magenta graphics *)
							 | 22 : isGraphics := TRUE; fg := Cyan;			(* Cyan graphics *)
							 | 23 : isGraphics := TRUE; fg := White;		  (* White graphics *)
							 
							 | 27 : 															(* ESC/Switch: TO BE DONE *)
							 | 31 : holdGraphics := FALSE;						(* Release graphics *)
							ELSE
							END;
	(*						Out.String("pos. "); Out.Int(i*41+j, 0);Out.Ln;*)
						END;
					END;
					
					text [i*41 + 40] := AosTexts.NewLineChar;
					
					(* Adjust attributes if the row contained double height chars. *)
					IF (i < 23) & hasDouble THEN
						FOR j := 0 TO 39 DO
							fgColor [i*41 + j+41] := fgColor [i*41 + j];
							bgColor [i*41 + j+41] := bgColor [i*41 + j];
							(* Prevent that any characters on the second line will be visible *)
							IF text [i*41 + j+41] = 0 THEN
								text [i*41 + j+41] := 32
							END;
						END;
					END;
				END;
(*			END;*)
			text[41*24-1] := 0;
			
			(* Extract channel name from first line *)
			IF vbi.extractName THEN
				FOR i := 8 TO 23 DO
					chName[i-8] := CHR(text[i]);
				END;
				vbi.ExtractChannelName (chName);
			END;
			
			NEW (page.formattedText);
			page.formattedText.AcquireWrite;
			page.formattedText.Delete (0, page.formattedText.GetLength());
			page.formattedText.InsertUCS32 (0, text);
			page.formattedText.ReleaseWrite;
			
			monitor := TRUE;
			newVersion := F;
			cnt := 0;
			
			fg := White;
			bg := Black;
			begin := 0;
			FOR i := 0 TO 41*24-1 DO
				IF newVersion & (bgColor[i] # bg) THEN
					(* New background: Apply last attributes *)
					IF (bg # Black) OR (fg # White) THEN
						NEW(attr);
						attr.color := fg;
						attr.bgcolor := bg;
						page.formattedText.AcquireWrite;
						page.formattedText.SetAttributes (begin, i-begin, attr);
						page.formattedText.ReleaseWrite;
						IF monitor THEN
							INC(cnt);
						END;
						fg := fgColor[i];
						bg := bgColor[i];
						begin := i;
					END;
				ELSIF newVersion & (fgColor[i] # fg) & (text[i] # 32) & (text[i] # AosTexts.NewLineChar) THEN
					(* New foreground color: Include all previous whitespaces *)
					j := i-1;
					WHILE (j > 0) & ((text[j] = 32) OR (text[j] = AosTexts.NewLineChar)) & (bgColor[j] = bg) DO
						fgColor[j] := fgColor[i];
						DEC(j);
					END;
					IF j > 0 THEN
						(* Set attributes *)
						NEW(attr);
						attr.color := fg;
						attr.bgcolor := bg;
						page.formattedText.AcquireWrite;
						page.formattedText.SetAttributes (begin, j-begin+1, attr);
						page.formattedText.ReleaseWrite;
						IF monitor THEN
							INC(cnt);
						END;
						begin := j+1;
					END;
				END;
				IF (~newVersion) & (fgColor[i] # fg) OR (bgColor[i] # bg) OR (i = 41*24-1) THEN
					(* Attribute change: set previously defined attributes *)
					NEW (attr);
					attr.color := fg;
					attr.bgcolor := bg;
					page.formattedText.AcquireWrite;
					page.formattedText.SetAttributes (begin, i-begin, attr);
					page.formattedText.ReleaseWrite;
					IF monitor THEN
						INC(cnt);
					END;
					fg := fgColor[i];
					bg := bgColor[i];
					begin := i;
				END;
			END;
			
			IF monitor THEN
				Out.String("Page No. "); Out.Int(pageNum+100, 0);
				Out.String(" contains "); Out.Int(cnt, 0); Out.String(" Attributes"); Out.Ln;
			END;
			
			IF newPage THEN (* this can be optimezed: ==> move it to if / else *)
				(* insert the new page in the double linked list: *)
				(* determine the previous valid page *)
				i := (pageNum - 1);
				WHILE (i >= 0) & (vbi.currentSuite.pages[i].data = NIL) DO
					DEC(i);
				END;
				IF i >= 0 THEN (* oli: Fall 2) oder 4) *)
					(* there exists a valid page with a lower index *)
					IF vbi.currentSuite.pages[i].next # VbiUndefined THEN (* fall 4) *)
						(* it has a successor *)
						vbi.currentSuite.pages[pageNum].next := vbi.currentSuite.pages[i].next;
						vbi.currentSuite.pages[vbi.currentSuite.pages[pageNum].next].prev := pageNum;
					ELSE (* fall 2) *)
						vbi.currentSuite.pages[pageNum].next := VbiUndefined;
					END;
					
					(* link the page with its precessor *)
					vbi.currentSuite.pages[pageNum].prev := i;
					vbi.currentSuite.pages[i].next := pageNum;
				ELSE (* fall 1) oder 3) *)
					vbi.currentSuite.pages[pageNum].prev := VbiUndefined;
					
					(* determine the next valid page *)
					i := pageNum + 1;
					WHILE (i < 800) & (vbi.currentSuite.pages[i].data = NIL) DO
						INC(i);
					END;
					IF i < 800 THEN (* fall 3) *)
						(* valid page found *)
						vbi.currentSuite.pages[pageNum].next := i;
						vbi.currentSuite.pages[i].prev := pageNum;
					ELSE (* fall 1) *)
						vbi.currentSuite.pages[pageNum].next := VbiUndefined;
					END;
				END;
			END;
		END SetPage;
		
		(* Stretch current graphic character to double height. Result will be stored in current and succeeding line *)
		PROCEDURE DoubleHeight (VAR txt : ARRAY OF LONGINT; pos : LONGINT);
		VAR
			c : LONGINT;
		BEGIN
			c := txt [pos];

			(* Graphic symbols are stretched to double height, characters are underlined. *)
			IF ((c >= 160) & (c < 192)) OR ((c >= 224) & (c < 256)) THEN
				(* Graphic symbol: Stretch upper part *)
				CASE (c MOD 16) OF
						0 : txt [pos] := 160;
					|   1 : txt [pos] := 165;
					|   2 : txt [pos] := 170;
					|   3 : txt [pos] := 175;
					|   4 : txt [pos] := 176;
					|   5 : txt [pos] := 181;
					|   6 : txt [pos] := 186;
					|   7 : txt [pos] := 191;
					|   8 : txt [pos] := 224;
					|   9 : txt [pos] := 229;
					| 10 : txt [pos] := 234;
					| 11 : txt [pos] := 239;
					| 12 : txt [pos] := 240;
					| 13 : txt [pos] := 245;
					| 14 : txt [pos] := 250;
					| 15 : txt [pos] := 255
				END;
				
				(* Process lower part on succeeding row; Return if none available *)
				IF pos+41 >= 41*24 THEN
					RETURN
				END;
				
				(* Write lower part of the graphics to the succeeding line *)
				CASE (c DIV 4) OF
					  40 : txt [pos+41] := 160;
					| 41 : txt [pos+41] := 161;
					| 42 : txt [pos+41] := 162;
					| 43 : txt [pos+41] := 163;
					| 44 : txt [pos+41] := 180;
					| 45 : txt [pos+41] := 181;
					| 46 : txt [pos+41] := 182;
					| 47 : txt [pos+41] := 183;
					
					| 56 : txt [pos+41] := 232;
					| 57 : txt [pos+41] := 233;
					| 58 : txt [pos+41] := 234;
					| 59 : txt [pos+41] := 235;
					| 60 : txt [pos+41] := 252;
					| 61 : txt [pos+41] := 253;
					| 62 : txt [pos+41] := 254;
					| 63 : txt [pos+41] := 255
				END;
				
			ELSIF pos+41 < 41*24 THEN
				(* process non-graphic characters *)
				CASE c OF
					  10 : (* Newline character: Do nothing *)
					| 32 : txt [pos+41] := 32;
				ELSE
					(* Underline characters *)
					txt [pos+41] := ORD('=');
					txt [pos+41] := 172;
					txt [pos+41] := 163;
				END;
			END;
		END DoubleHeight;
		
		PROCEDURE LinkPages;
		VAR
			i, lastPage : LONGINT;
		BEGIN
			lastPage := VbiUndefined;
			FOR i := 0 TO 799 DO
				IF vbi.currentSuite.pages[i].data # NIL THEN
					vbi.currentSuite.pages[i].prev := lastPage;
					IF lastPage # VbiUndefined THEN
						vbi.currentSuite.pages[lastPage].next := i;
					END;
					lastPage := i;
				END;
			END;
		END LinkPages;
		
	END TeletextSuite;
	
	TeletextPage = OBJECT	(* rename ??? *)
		VAR
		next-, prev- : LONGINT;
		data- : DataPage;
	END TeletextPage;
	
	DataPage* = OBJECT	(* rename ??? *)
	VAR
		nextSub-, prevSub- : DataPage;
		pageNumber, subPageNo : LONGINT;
		text* : ARRAY 41*24 OF AosTexts.Char32;
		formattedText : AosTexts.Text;	(* => 'text' *)
	END DataPage;

TYPE	
	VpsInfo = OBJECT
	VAR
		chName : ARRAY 9 OF CHAR;
		namePos : LONGINT;
		
		PROCEDURE &Init;
		BEGIN
			namePos := 0;
		END Init;
		
		PROCEDURE Decode(data : ARRAY OF CHAR);
		BEGIN
(*			Out.String("namePos :="); Out.Int(namePos, 0); Out.Ln;*)
			IF (SYSTEM.VAL(SET, LONG(ORD(data[3]))) * {7}) # {} THEN
				chName[namePos] := 0X;
				IF namePos = 8 THEN
(*					(*Aos*)Out.String("##Oli: Channel Name: ");
					(*Aos*)Out.Ln;
					(*Aos*)Out.String(chName);
					(*Aos*)Out.Ln;*)
(*					namePos := 0;*)
					END;
(*				namePos := 0; *)(* stimmt gemaess bsd-treiber *)
			END;
			chName[namePos] := CHR(ORD(data[3]) MOD 128);
			INC(namePos);
			IF namePos = 9 THEN
				namePos := 0;
			END;
		END Decode;
		
	END VpsInfo;
	
	(* VTpage is supposed to be a local type in VbiDecoder, but the current AOS compiler (Builder.Compile)
		does not understand this *)
	VTpage = OBJECT
	VAR
(*		next : VTpage;*)
		number : LONGINT;
		subPage : LONGINT;
		page : ARRAY VtPageSize OF CHAR;
		flags : SET;
		
		PROCEDURE &Init(page, sub : LONGINT);
		BEGIN
			number := page;
			subPage := sub;
(*			next := NIL;*)
			flags := {};
		END Init;
		
		(* Remove any non-printable characters from the channel name *)
		PROCEDURE SkipBlanks(VAR name : ARRAY OF CHAR; VAR startPos : LONGINT);
		VAR
			i : LONGINT;
		BEGIN
			i := startPos;
			WHILE (i < LEN(name)-1) & ((name[i] < '0') OR (name[i] > 07FX)) DO
				name[i] := ' ';
				INC(i);
			END;
			startPos := i;
		END SkipBlanks;
		
		PROCEDURE IsNumber(ch : CHAR) : BOOLEAN;
		BEGIN
			RETURN (ch >= '0') & (ch <='9');
		END IsNumber;
		
		(* remove the page number from the channel name *)
		PROCEDURE SkipPageNum(VAR name : ARRAY OF CHAR; VAR startPos : LONGINT);
		VAR
			i : LONGINT;
			index1, index2 : LONGINT;
		BEGIN
			i := startPos;
			IF IsNumber(name[i]) & IsNumber(name[i+1]) & IsNumber(name[i+2]) & (name[i+3] = ' ') THEN
				FOR i := startPos TO startPos + 2 DO
					name[i] := ' ';
				END;
				startPos := startPos + 4;
			ELSIF (name[i] = 'P') & IsNumber(name[i+1]) & IsNumber(name[i+2]) & IsNumber(name[i+3]) & (name[i+4] = ' ')THEN
				FOR i := startPos TO startPos + 3 DO
					name[i] := ' ';
				END;
				startPos := startPos + 5;
			END;
		END SkipPageNum;
		
		PROCEDURE Write();
		BEGIN
			vbi.currentSuite.SetPage (number-100, subPage, page);
		END Write;
		
		PROCEDURE SetLine(data : ARRAY OF CHAR; pos, line : LONGINT);
		VAR
			c, i : LONGINT;
		BEGIN
			IF line = 0 THEN
				c := LONG(ORD(vbi.UnHam(data[pos+4], data[pos+5])));
				flags := SYSTEM.VAL(SET, LONG(ORD(vbi.UnHam(data[pos+2], data[pos+3])))) * {7}; 
				(* flags continued.......... *)
			END;
			IF line < 24 THEN
				FOR i := 0 TO 39 DO
					page[40*line + i] := data[pos + i];
				END;
			END;
			IF line = 23 THEN
				Write();
			END;
			IF (line = 0) & (vbi.extractName) THEN
				Write();
			END;
		END SetLine;
		
	END VTpage;
	
	VbiDecoder = OBJECT
	VAR
		chName : ARRAY 17 OF CHAR;
		extractName : BOOLEAN;
		dead : BOOLEAN;
		flags : SET;
		discardPage: BOOLEAN;
(*		field : INTEGER;*)
		line : LONGINT;
(*		vcbuf : ARRAY 20 OF CHAR;*)
(*		vc2buf : ARRAY 20 OF CHAR;*)
		off, thresh : LONGINT;
		spos : LONGINT;
		vtPage : VTpage;
		packs: SET;
		lastPack : LONGINT;
		lang: LONGINT;
		vpsi : VpsInfo;
		freq : REAL;
		vtstep, vcstep, vpsstep : LONGINT;
		norm : LONGINT;
		pnum : LONGINT;	(* this comes from DecodeVt *)
		unHamTab : ARRAY 256 OF LONGINT;
		nationals : ARRAY 8 OF ARRAY 13 OF LONGINT;
		currentSuite : TeletextSuite;
		
		PROCEDURE &Init;
		BEGIN
			InitUnhamTab;
			InitNationals;
			extractName := FALSE;
			flags := VbiVT + VbiVPS;
			SetFreq(0, 0);
			NEW(vpsi);
		END Init;
		
		PROCEDURE Adump(data : ARRAY OF CHAR; start, len : LONGINT);
		VAR
			i : LONGINT;
			c : CHAR;
		BEGIN
			FOR i := start TO start+len-1 DO
				c := CHR(ORD(data[i]) MOD 128);
				IF c < 20X THEN
					c := '.';
				END;
				AosOut.Char(c);
			END;
		END Adump;
		
		(* unham 2 bytes into 1, report 2 bit errors but ignore them *)
		PROCEDURE UnHam(ch1, ch2 : CHAR) : CHAR;
		VAR
			s1, s2 : SET;
			v1, v2: LONGINT;
		BEGIN
(*			s1 := SYSTEM.VAL(SET, LONG(ORD(unHamTab[ORD(ch1)])));
			s2 := SYSTEM.VAL(SET, LONG(ORD(unHamTab[ORD(ch2)])));
			
			IF ((s1 + s2) * { 6 }) # {} THEN
				AosOut.String("Bad Hamming Code!"); AosOut.Ln;
			END;
			RETURN CHR((SYSTEM.VAL(LONGINT, s2) * 16 + SYSTEM.VAL(LONGINT, s1 * { 0 .. 3 })) MOD 256);*)
			v1 := unHamTab [ORD (ch1)];
			v2 := unHamTab [ORD (ch2)];
			
			IF (v1 = -1) OR (v2 = -1) THEN
				AosOut.String("{ AosTV } Bad Hamming Code !"); AosOut.Ln;
				RETURN 0FFX;
			ELSE
				RETURN (CHR(16*v2 + v1))
			END;
		END UnHam;
		
		PROCEDURE Filter(VAR name : ARRAY OF CHAR; len : INTEGER);
		VAR
			i : INTEGER;
			c : CHAR;
			mod: BOOLEAN;
			hex : ARRAY 25 OF CHAR;
		BEGIN
			FOR i := 0 TO len-1 DO
				c := name[i];
				c := CHR(ORD(c) MOD 128);
				CASE c OF
						'/' : c := '/';
(*					| 23X : c := 1X;
					| 24X : c := 1X;
					| 40X : c := 1X;*)
(*					| 5BX : c := 'Ä';	c := CHR(91);
					| 5CX : c := 'Ö';	c := CHR(92);
					| 5DX : c := 'Ü';	c := CHR(94);*)
(*					| 5EX : c := 1X;
					| 5FX : c := 1X;
					| 60X : c := 1X;*)
(*					| 7BX : c := 'ä';	c := CHR(123);
					| 7CX : c := 'ö';	c := CHR(124);
(*					| 7DX : c := 'ü';	c := CHR(126);*)
					| 7EX : c := 'ß';	c := 's';	c := CHR(126);
					| 8AX : c := ' '; *)
(*					| 0AX : c := ' ';*)
				ELSE
				END;
				name[i] := c;
			END;
		END Filter;
		
		(* Extract channel name from the first teletext line *)
		PROCEDURE ExtractChannelName (rawName : ARRAY OF CHAR);
		CONST
			db = FALSE;
		VAR
			tmp: ARRAY 17 OF CHAR;
			i, j, begin, end: LONGINT;
			done : BOOLEAN;
			
			PROCEDURE Is3Digits (pos: LONGINT) : BOOLEAN;
			BEGIN
				IF pos > 14 THEN RETURN FALSE END;
				IF (rawName[pos] < '0') OR (rawName[pos] > '9') THEN RETURN FALSE END;
				IF (rawName[pos+1] < '0') OR (rawName[pos+1] > '9') THEN RETURN FALSE END;
				IF (rawName[pos+2] < '0') OR (rawName[pos+2] > '9') THEN RETURN FALSE END;
				IF (rawName[pos+3] > ' ') THEN RETURN FALSE END;
(*				Out.String("Found 3 digits starting at pos "); Out.Int(pos, 0); Out.Ln;*)
				RETURN TRUE;
			END Is3Digits;
			
		BEGIN
			IF db THEN Out.String("Converting "); Out.String(rawName); Out.String(" to "); END;
			COPY (rawName, tmp);
			Utilities.UpperCase (tmp);
			i := 0;
			(* Search for a 3-digit page number, possibly preceeded by a 'P' *)
			REPEAT
				done := TRUE;
				IF Is3Digits (i) THEN
					begin := i;
					end := i + 3;
				ELSIF (tmp[i] = 'P') & Is3Digits (i+1) THEN
					begin := i;
					end := i + 4;
				ELSE
					done := FALSE;
				END;
				
				(* If number is not found, search for the next word *)
				IF ~done THEN
					REPEAT
						INC (i)
					UNTIL (i >= 14) OR (rawName[i] = ' ');
					INC (i)
				END;
			UNTIL done OR (i >= 14);
			
			(* Cut out page number, if possible *)
			IF done THEN
				IF begin < 3 THEN
					WHILE (end < 16) & (tmp[end] = ' ') DO
						INC(end)
					END;
					i := 15;
					WHILE (tmp[i] # ' ') DO
						DEC (i);
					END;
					(* set index back if channel name fills the whole string *)
					IF i < end THEN
						i := 15
					END;
					FOR j := end TO i DO
						(* Special Characters do not conform to ASCII Standard *)
	(*					CASE ORD(rawName[j]) OF
							 91: chName[j-end] := 'Ä';
						 |   92: chName[j-end] := 'Ö';
						 |   94: chName[j-end] := 'Ü';
						 |   96: chName[j-end] := 'é';
						 | 123: chName[j-end] := 'ä';
						 | 124: chName[j-end] := 'ö';
						 | 126: chName[j-end] := 'ü';
						ELSE *)
							chName[j-end] := rawName[j]
						(* END; *)
					END;
					chName[i-end+1] := 0X;
					IF db THEN
						Out.String(chName);
						Out.Ln;
						Out.String("Begin, End, i : ");
						Out.Int(begin, 0); Out.Int(end, 6); Out.Int(i, 6);
					END;
				ELSE
					i := 0;
					WHILE tmp[i] = ' ' DO
						INC(i)
					END;
					FOR j := i TO begin-1 DO
						(* Special Characters do not conform to ASCII Standard *)
		(*				CASE ORD(rawName[j]) OF
							 91: chName[j-i] := 'Ä';
						 |   92: chName[j-i] := 'Ö';
						 |   94: chName[j-i] := 'Ü';
						 |   96: chName[j-i] := 'é';
						 | 123: chName[j-i] := 'ä';
						 | 124: chName[j-i] := 'ö';
						 | 126: chName[j-i] := 'ü';
						ELSE *)
							chName[j-i] := rawName[j]
		(*				END; *)
					END;
					chName[begin] := 0X;
				END;
			END;
			IF db THEN Out.Ln END;
		END ExtractChannelName;
		
		(* decode data in videotext-like packages, like videotext itself, intercast, ... *)
		PROCEDURE DecodeVt(dat : ARRAY OF CHAR);
		VAR
			mag, pack : LONGINT;
			mpag, page : CHAR;
			pTen, pUnit : LONGINT;
			sub1, sub2 : LONGINT;
			udat : ARRAY 4 OF CHAR;
			i, sub : LONGINT;
			flags : LONGINT;
		BEGIN
			mpag := UnHam(dat[3], dat[4]);
			mag := ORD(mpag) MOD 8;
			IF mag = 0 THEN 
				mag := 8;
			END;
			pack := ORD(mpag) DIV 8;
			
			IF pack = 0 THEN
				page := UnHam(dat[5], dat[6]);
				
				pTen := ORD(page) DIV 16;
				pUnit := ORD (page) MOD 16;
				
					IF (page # 0FFX) & ((pTen > 9) OR (pUnit > 9)) THEN
						discardPage := TRUE;
					ELSE
						discardPage := FALSE
					END;
				
				IF page # 0FFX THEN
					sub1 := ORD(UnHam(dat[7], dat[8])) MOD 128;
					sub2 := ORD(UnHam(dat[9], dat[10])) MOD 64;
					sub := sub2*256 + sub1;
					
					(* Note: C1-C6 Control Bits are still missing!!! *)
					flags := ORD (UnHam(dat[11], dat[12]));
					lang := flags DIV 32;
(*					CASE lang OF
						 0: AosOut.String("    Language: English");
					|	1: AosOut.String("    Language: French");
					|	2: AosOut.String("    Language: Swedish/Finnish/Hungarian");
					|	3: AosOut.String("    Language: Czech/Slovak");
					|	4: AosOut.String("    Language: German");
					|	5: AosOut.String("    Language: Portuguese/Spanish");
					|	6: AosOut.String("    Language: Italian");
					|	7: AosOut.String("    Language: <Undefined>");
					END;
					AosOut.Ln;*)
					
(*					pnum := sub * 65536 + mag * 256 + ORD(page);*)
					
(*					IF DEBUG THEN
						IF 7 IN SYSTEM.VAL(SET, sub) THEN
							AosOut.String("DecodeVt : Erase"); AosOut.Ln;
						END;
						IF 14 IN SYSTEM.VAL(SET, sub) THEN
							AosOut.String("DecodeVt : NewsFlash"); AosOut.Ln;
						END;
						IF 15 IN SYSTEM.VAL(SET, sub) THEN
							AosOut.String("DecodeVt : Subtitle"); AosOut.Ln;
						END;
						
						flags := SYSTEM.VAL(SET, UnHam(dat[11], dat[12]));
						IF 0 IN flags THEN
							AosOut.String("DecodeVt : SuppHeader"); AosOut.Ln;
						END;
						IF 1 IN flags THEN
							AosOut.String("DecodeVt : Update"); AosOut.Ln;
						END;
						IF 2 IN flags THEN
							AosOut.String("DecodeVt : ISequ"); AosOut.Ln;
						END;
						IF 3 IN flags THEN
							AosOut.String("DecodeVt : IDisp"); AosOut.Ln;
						END;
						IF 4 IN flags THEN
							AosOut.String("DecodeVt : MagSerial"); AosOut.Ln;
						END;
						AosOut.String("DecodeVt : Charset: ");
						AosOut.Int(SYSTEM.VAL(INTEGER, flags) DIV 32, 0);
						AosOut.Ln;
					END;*)
					IF ~ discardPage THEN
						NEW (vtPage, mag*100 + pTen*10 + pUnit, sub);
						packs := {};
						lastPack := 0;
(*						w.Ln;
						w.String ("Page ");
						w.Int (mag*100 + pTen*10 + pUnit, 0);
						w.String (", SubPage No. ");
						w.Int (sub, 0);
						w.Ln;*)
						vtPage.SetLine(dat, 5, pack);
					END;
				END;
			ELSIF (1 <= pack) & (pack <= 24) THEN
				(* Error detection: Only increasing package numbers allowed. Avoid duplicate packages *)
				IF (pack <= lastPack) OR (pack IN packs) THEN
					discardPage := TRUE
				ELSE
					lastPack := pack;
					packs := packs + {pack}
				END;
				IF (vtPage # NIL) & (~ discardPage) THEN
					vtPage.SetLine(dat, 5, pack);
				ELSE
					IF vtPage = NIL THEN
(*						Out.String("vtPage = NIL");*)
					ELSE
(*						Out.String("discardPage: ");
						Out.Int(mag, 0);
						Out.Int(pTen, 4);
						Out.Int(pUnit, 4);*)
					END;
				END;
			ELSIF pack = 25 THEN
				AosOut.String("## Page = ");
				AosOut.Hex(pnum, 4);
				AosOut.String(", AltHeader : ");
				AosOut.Ln;
				Adump(dat, 5, 40);
				AosOut.Ln;
			ELSIF (26 <= pack) & (pack <= 29) THEN
				(* PDC *)
			ELSIF pack = 30 THEN
(*				AosOut.String("DecodeVt : Packet 30"); AosOut.Ln;*)
			ELSIF pack = 31 THEN
(*				AosOut.String("$$$%%% PACKET 31 RECEIVED %%%$$$");
				AosOut.Ln;*)
(*				AosOut.String("intercast decoder signal detected"); AosOut.Ln;*)
			END;
		END DecodeVt;
		
		PROCEDURE SetFreq(f : REAL; n : LONGINT);
		VAR
			vtfreq : REAL;
			vpsfreq : REAL;
			vcfreq : REAL;
		BEGIN
			IF norm # 0 THEN
				vtfreq := 5.72725;
			ELSE
				vtfreq := 6.9375;
			END;
			
			vpsfreq := 5;
			vcfreq := 0.77;
			norm := n;
			
			(* if no frequency given, use standard ones for Bt848 an PAL/NTSC *)
			IF f = 0 THEN
				IF norm # 0 THEN
					freq := 28.636363;
				ELSE
					freq := 35.468950;
				END;
			ELSE
				freq := f;
			END;
			
			vtstep := ENTIER((freq/vtfreq)*FpFac + 0.5);
			(* VPS is shift encoded, so just sample first "state" *)
			vpsstep := 2*ENTIER((freq/vtfreq)*FpFac + 0.5);
			vcstep := ENTIER((freq/vcfreq)*FpFac + 0.5);
		END SetFreq;
		
		(* primitive automatic gain control to determine the right slicing offset *)
		(*it should suffice to do this once per channel change *)
		PROCEDURE AGC(pos, start, stop, step : LONGINT);
		VAR
			i : LONGINT;
			min, max : LONGINT;
		BEGIN
			min := 255;
			max := 0;
			i := start;
			(* the FOR-loop is not applicable because 'step' is not a constant... *)
			WHILE i < stop DO
				IF ORD(vbiBuffer.data[pos + i]) < min THEN
					min := ORD(vbiBuffer.data[pos + i]);
				END;
				IF ORD(vbiBuffer.data[pos + i]) > max THEN
					max := ORD(vbiBuffer.data[pos + i]);
				END;
				i := i + step;
			END;
			
			thresh := (min + max) DIV 2;
			off := 128 - thresh;
		END AGC;
		
		PROCEDURE Scan(step, pos : LONGINT) : CHAR;
		VAR
			dat : SET;
			j, ord : LONGINT;
		BEGIN
			dat := {};
			FOR j := 7 TO 0 BY -1 DO
				ord := ORD(vbiBuffer.data[pos + (spos DIV FpFac)]) + off;
				IF (ord >= 128) & (ord < 256) THEN
					dat := dat + { (7-j) }
				END;
				spos := spos + step;
			END;
			IF DEBUG THEN
				AosOut.String("AosTV : Scan -- return=");
				AosOut.Char(SYSTEM.VAL(CHAR, dat));
				AosOut.Int(SYSTEM.VAL(LONGINT, dat), 10);
				AosOut.Ln;
			END;
			RETURN SYSTEM.VAL(CHAR, dat);
		END Scan;
		
		PROCEDURE DecodeLine(pos : LONGINT);
		VAR
			i, p : LONGINT;
			data : ARRAY 45 OF CHAR;
		BEGIN
			AGC(pos, 120, 450, 1);
				
			IF flags*VbiVT # {} THEN
				(* search for first 1 bit (VT always starts with 55X 55X 27X !!! *)
				p := 50;
				WHILE (vbiBuffer.data[pos + p] < CHR(thresh)) & (p < 350) DO
					INC(p);
				END;
				spos := p*FpFac + vtstep DIV 2;
				
				(* ignore first bit for now *)
				data[0] := Scan(vtstep, pos);
(*				AosOut.String("ORD(data[0]) = "); AosOut.Int(ORD(data[0]), 0); AosOut.Ln;*)
				
				IF (SYSTEM.VAL(SET, data[0]) * {1..7}) = {2, 4, 6} THEN
					data[1] := Scan(vtstep, pos);
(*					AosOut.String("ORD(data[1]) = "); AosOut.Int(ORD(data[1]), 0); AosOut.Ln;*)
					IF data[1] = 0D5X THEN
						(* oops, missed first 1-bit: backup 2 bits *)
						spos := spos - 2*vtstep;
						data[1] := 55X;
					END;
					IF data[1] = 55X THEN
						data[2] := Scan(vtstep, pos);
(*						AosOut.String("ORD(data[2]) = "); AosOut.Int(ORD(data[2]), 0); AosOut.Ln;*)
						IF data[2] = 0D8X THEN
							(* this shows up on some channels!?!?! *)
							FOR i := 3 TO 44 DO
								data[i] := CHR(ORD(Scan(vtstep, pos)) MOD 128);
							END;
							RETURN;
						ELSIF data[2] =27X THEN
							FOR i := 3 TO 44 DO
								data[i] := CHR(ORD(Scan(vtstep, pos)) MOD 128);
							END;
							DecodeVt(data);
							RETURN;
						END;
					END;
				END;
			END;
(*			AosOut.String("   DATA :"); AosOut.Ln; AosOut.String(data); AosOut.Ln;*)
			
			(* VPS information with channel name, time, VCR programming info, etc. *)
			IF ((flags * VbiVPS) # {}) & (line=9) THEN
				p := 150;
				WHILE ((vbiBuffer.data[pos + p]) < CHR(thresh)) & (p < 260) DO
					INC(p);
				END;
				p := p+2;
				spos := p*FpFac;
				
				data[0] := Scan(vpsstep, pos);
				IF data[0] # 0FFX THEN
(*					RETURN*)
				END;
				
				data[1] := Scan(vpsstep, pos);
				IF data[1] # 05DX THEN
(*					Out.String("return : data[1] = 5D,");Out.Ln;
					RETURN*)
				END;
				
				FOR i := 2 TO 15 DO
					data[i] := Scan(vpsstep, pos);
				END;
				
				vpsi.Decode(data);
			END;
		END DecodeLine;

		PROCEDURE Decode;
		VAR
			readPos, curPos : LONGINT;
		BEGIN
			readPos := vbiBuffer.readPos;
			IF vbiBuffer.vbiSize >= VbiDataSize THEN
				FOR line := 0 TO 2*VbiLines-1 DO
					curPos := readPos + line*VbiLineSize;
					DecodeLine(curPos);
				END;
			END
		END Decode;
		
		PROCEDURE InitNationals;
		BEGIN
			(* english *)
			nationals[0][0] := ORD('L'); nationals[0][1] := ORD('S'); nationals[0][2] := ORD('a'); nationals[0][3] := 60;
			nationals[0][4] := 2; nationals[0][5] := 62; nationals[0][6] := 2; nationals[0][7] := 35;
			nationals[0][8] := 95; nationals[0][9] := 2; nationals[0][10] := 2; nationals[0][11] := 2; nationals[0][12] := 2;
			(* french *)
			nationals[1][0] := 96; nationals[1][1] := ORD('i'); nationals[1][2] := ORD('a'); nationals[1][3] := ORD('e');
			nationals[1][4] := ORD('e'); nationals[1][5] := ORD('u'); nationals[1][6] := ORD('i'); nationals[1][7] := 35;
			nationals[1][8] := ORD('e'); nationals[1][9] := ORD('a'); nationals[1][10] := ORD('o'); nationals[1][11] := ORD('u');
			nationals[1][12] := ORD('c');
			(* swedish/finnish *)
			nationals[2][0] := 35; nationals[2][1] := 36; nationals[2][2] := 64; nationals[2][3] := 91;
			nationals[2][4] := 92; nationals[2][5] := 93; nationals[2][6] := 94; nationals[2][7] := 95;
			nationals[2][8] := 96; nationals[2][9] := 123; nationals[2][10] := 124; nationals[2][11] := 125;
			nationals[2][12] := 126;
			(* czech/slovak *)
			nationals[3][0] := 35; nationals[3][1] := ORD('u'); nationals[3][2] := ORD('c'); nationals[3][3] := ORD('t');
			nationals[3][4] := ORD('z'); nationals[3][5] := ORD('y'); nationals[3][6] := ORD('i'); nationals[3][7] := ORD('r');
			nationals[3][8] := 96; nationals[3][9] := ORD('a');; nationals[3][10] := ORD('e'); nationals[3][11] := ORD('u');
			nationals[3][12] := ORD('s');
			(* german *)
			nationals[4][0] := 35; nationals[4][1] := ORD('S'); nationals[4][2] := 2; nationals[4][3] := 91;
			nationals[4][4] := 92; nationals[4][5] := 94; nationals[4][6] := 2; nationals[4][7] := 95;
			nationals[4][8] := 39; nationals[4][9] := 123; nationals[4][10] := 124; nationals[4][11] := 126;
			nationals[4][12] := ORD('B');
			(* portuguese/spanish *)
			nationals[5][0] := ORD('c'); nationals[5][1] := ORD('S'); nationals[5][2] := ORD('i'); nationals[5][3] := ORD('a');
			nationals[5][4] := 96; nationals[5][5] := ORD('i'); nationals[5][6] := ORD('o'); nationals[5][7] := ORD('u');
			nationals[5][8] := 63; nationals[5][9] := 126; nationals[5][10] := ORD('n'); nationals[5][11] := ORD('e');
			nationals[5][12] := ORD('a');
			(* italian *)
			nationals[6][0] := ORD('L'); nationals[6][1] := ORD('S'); nationals[6][2] := 96; nationals[6][3] := 39;
			nationals[6][4] := ORD('c'); nationals[6][5] := 62; nationals[6][6] := 2; nationals[6][7] := 35;
			nationals[6][8] := ORD('u'); nationals[6][9] := ORD('a'); nationals[6][10] := ORD('o'); nationals[6][11] := ORD('e');
			nationals[6][12] := ORD('i');
			(* default *)
			nationals[7][0] := 35; nationals[7][1] := 36; nationals[7][2] := ORD('a'); nationals[7][3] := 40;
			nationals[7][4] := 47; nationals[7][5] := 41; nationals[7][6] := 2; nationals[7][7] := 95;
			nationals[7][8] := 39; nationals[7][9] := 40; nationals[7][10] := 33; nationals[7][11] := 41; nationals[7][12] := 2;
		END InitNationals;
		
		PROCEDURE InitUnhamTab;
		BEGIN
			unHamTab [0] := -1;	unHamTab [1] := -1;	unHamTab [2] := 1;	unHamTab [3] := 1;
			unHamTab [4] := -1;	unHamTab [5] := 0;	unHamTab [6] := 1;	unHamTab [7] := -1;
			unHamTab [8] := -1;	unHamTab [9] := 2;	unHamTab [10] := 1;	unHamTab [11] := -1;
			unHamTab [12] := 10;	unHamTab [13] := -1;	unHamTab [14] := -1;	unHamTab [15] := 7;
			unHamTab [16] := -1;	unHamTab [17] := 0;	unHamTab [18] := 1;	unHamTab [19] := -1;
			unHamTab [20] := 0;	unHamTab [21] := 0;	unHamTab [22] := -1;	unHamTab [23] := -1;
			unHamTab [24] := 6;	unHamTab [25] := -1;	unHamTab [26] := -1;	unHamTab [27] := 11;
			unHamTab [28] := -1;	unHamTab [29] := 0;	unHamTab [30] := 3;	unHamTab [31] := -1;
			unHamTab [32] := -1;	unHamTab [33] := 12;	unHamTab [34] := 1;	unHamTab [35] := -1;
			unHamTab [36] := 4;	unHamTab [37] := -1;	unHamTab [38] := -1;	unHamTab [39] := 7;
			unHamTab [40] := 6;	unHamTab [41] := -1;	unHamTab [42] := -1;	unHamTab [43] := 7;
			unHamTab [44] := -1;	unHamTab [45] := -1;	unHamTab [46] := 7;	unHamTab [47] := 7;
			unHamTab [48] := 6;	unHamTab [49] := -1;	unHamTab [50] := -1;	unHamTab [51] := 5;
			unHamTab [52] := -1;	unHamTab [53] := 0;	unHamTab [54] := 13;	unHamTab [55] := -1;
			unHamTab [56] := 6;	unHamTab [57] := 6;	unHamTab [58] := -1;	unHamTab [59] := -1;
			unHamTab [60] := 6;	unHamTab [61] := -1;	unHamTab [62] := -1;	unHamTab [63] := 7;
			unHamTab [64] := -1;	unHamTab [65] := 2;	unHamTab [66] := 1;	unHamTab [67] := -1;
			unHamTab [68] := 4;	unHamTab [69] := -1;	unHamTab [70] := -1;	unHamTab [71] := 9;
			unHamTab [72] := 2;	unHamTab [73] := 2;	unHamTab [74] := -1;	unHamTab [75] := -1;
			unHamTab [76] := -1;	unHamTab [77] := 2;	unHamTab [78] := 3;	unHamTab [79] := -1;
			unHamTab [80] := 8;	unHamTab [81] := -1;	unHamTab [82] := -1;	unHamTab [83] := 5;
			unHamTab [84] := -1;	unHamTab [85] := 0;	unHamTab [86] := 3;	unHamTab [87] := -1;
			unHamTab [88] := -1;	unHamTab [89] := 2;	unHamTab [90] := 3;	unHamTab [91] := -1;
			unHamTab [92] := -1;	unHamTab [93] := -1;	unHamTab [94] := 3;	unHamTab [95] := 3;
			unHamTab [96] := 4;	unHamTab [97] := -1;	unHamTab [98] := -1;	unHamTab [99] := 5;
			unHamTab [100] := 4;	unHamTab [101] := 4;	unHamTab [102] := -1;	unHamTab [103] := -1;
			unHamTab [104] := -1;	unHamTab [105] := 2;	unHamTab [106] := 15;	unHamTab [107] := -1;
			unHamTab [108] := 4;	unHamTab [109] := -1;	unHamTab [110] := -1;	unHamTab [111] := 7;
			unHamTab [112] := -1;	unHamTab [113] := -1;	unHamTab [114] := 5;	unHamTab [115] := 5;
			unHamTab [116] := 4;	unHamTab [117] := -1;	unHamTab [118] := -1;	unHamTab [119] := 5;
			unHamTab [120] := 6;	unHamTab [121] := -1;	unHamTab [122] := -1;	unHamTab [123] := 5;
			unHamTab [124] := -1;	unHamTab [125] := 14;	unHamTab [126] := 3;	unHamTab [127] := -1;
			unHamTab [128] := -1;	unHamTab [129] := 12;	unHamTab [130] := 1;	unHamTab [131] := -1;
			unHamTab [132] := 10;	unHamTab [133] := -1;	unHamTab [134] := -1;	unHamTab [135] := 9;
			unHamTab [136] := 10;	unHamTab [137] := -1;	unHamTab [138] := -1;	unHamTab [139] := 11;
			unHamTab [140] := 10;	unHamTab [141] := 10;	unHamTab [142] := -1;	unHamTab [143] := -1;
			unHamTab [144] := 8;	unHamTab [145] := -1;	unHamTab [146] := -1;	unHamTab [147] := 11;
			unHamTab [148] := -1;	unHamTab [149] := 0;	unHamTab [150] := 13;	unHamTab [151] := -1;
			unHamTab [152] := -1;	unHamTab [153] := -1;	unHamTab [154] := 11;	unHamTab [155] := 11;
			unHamTab [156] := 10;	unHamTab [157] := -1;	unHamTab [158] := -1;	unHamTab [159] := 11;
			unHamTab [160] := 12;	unHamTab [161] := 12;	unHamTab [162] := -1;	unHamTab [163] := -1;
			unHamTab [164] := -1;	unHamTab [165] := 12;	unHamTab [166] := 13;	unHamTab [167] := -1;
			unHamTab [168] := -1;	unHamTab [169] := 12;	unHamTab [170] := 15;	unHamTab [171] := -1;
			unHamTab [172] := 10;	unHamTab [173] := -1;	unHamTab [174] := -1;	unHamTab [175] := 7;
			unHamTab [176] := -1;	unHamTab [177] := 12;	unHamTab [178] := 13;	unHamTab [179] := -1;
			unHamTab [180] := -1;	unHamTab [181] := -1;	unHamTab [182] := 13;	unHamTab [183] := 13;
			unHamTab [184] := 6;	unHamTab [185] := -1;	unHamTab [186] := -1;	unHamTab [187] := 11;
			unHamTab [188] := -1;	unHamTab [189] := 14;	unHamTab [190] := 13;	unHamTab [191] := -1;
			unHamTab [192] := 8;	unHamTab [193] := -1;	unHamTab [194] := -1;	unHamTab [195] := 9;
			unHamTab [196] := -1;	unHamTab [197] := -1;	unHamTab [198] := 9;	unHamTab [199] := 9;
			unHamTab [200] := -1;	unHamTab [201] := 2;	unHamTab [202] := 15;	unHamTab [203] := -1;
			unHamTab [204] := 10;	unHamTab [205] := -1;	unHamTab [206] := -1;	unHamTab [207] := 9;
			unHamTab [208] := 8;	unHamTab [209] := 8;	unHamTab [210] := -1;	unHamTab [211] := -1;
			unHamTab [212] := 8;	unHamTab [213] := -1;	unHamTab [214] := -1;	unHamTab [215] := 9;
			unHamTab [216] := 8;	unHamTab [217] := -1;	unHamTab [218] := -1;	unHamTab [219] := 11;
			unHamTab [220] := -1;	unHamTab [221] := 14;	unHamTab [222] := 3;	unHamTab [223] := -1;
			unHamTab [224] := -1;	unHamTab [225] := 12;	unHamTab [226] := 15;	unHamTab [227] := -1;
			unHamTab [228] := 4;	unHamTab [229] := -1;	unHamTab [230] := -1;	unHamTab [231] := 9;
			unHamTab [232] := -1;	unHamTab [233] := -1;	unHamTab [234] := 15;	unHamTab [235] := 15;
			unHamTab [236] := -1;	unHamTab [237] := 14;	unHamTab [238] := 15;	unHamTab [239] := -1;
			unHamTab [240] := 8;	unHamTab [241] := -1;	unHamTab [242] := -1;	unHamTab [243] := 5;
			unHamTab [244] := -1;	unHamTab [245] := 14;	unHamTab [246] := 13;	unHamTab [247] := -1;
			unHamTab [248] := -1;	unHamTab [249] := 14;	unHamTab [250] := 15;	unHamTab [251] := -1;
			unHamTab [252] := 14;	unHamTab [253] := 14;	unHamTab [254] := -1;	unHamTab [255] := -1;
		END InitUnhamTab;
		
	BEGIN {ACTIVE}
		(* Wait until the initial teletext suite is selected *)
		WHILE currentSuite = NIL DO
		END;
		Out.String("vbi is ACTIVE!"); Out.Ln;
(*		BEGIN {EXCLUSIVE}*)
			dead := FALSE;
			REPEAT
				WHILE (~ dead) & (vbiBuffer.vbiSize <= VbiDataSize) DO
(*					AosOut.String("{ AosTV } VbiBuffer is empty"); AosOut.Ln;*)
				END;
(*				AosOut.String("{ AosTV } VbiBufferSize: "); AosOut.Int(vbiBuffer.vbiSize, 0); AosOut.Ln;*)
(*				AosOut.String(", readPos = "); AosOut.Int(vbiBuffer.readPos, 0); AosOut.Ln;*)
(*				AWAIT (dead OR (vbiBuffer.vbiSize > 0));*)
				IF ~dead THEN
					Decode();
					vbiBuffer.readPos := (vbiBuffer.readPos + VbiDataSize) MOD VbiBufferSize;
					vbiBuffer.vbiSize := vbiBuffer.vbiSize - VbiDataSize;
				END;
			UNTIL dead;
(*		END;*)
		Out.String("vbi is DEAD!"); Out.Ln;
	END VbiDecoder;
	
	TvWindow = OBJECT(WM.BufferWindow);
	VAR
		timer: AosKernel.Timer;
		alive: BOOLEAN;
		chnlSeeker: ChannelSeeker;
		newImage : BOOLEAN;
		lastX, lastY : LONGINT;
		dragging : BOOLEAN;
		last :LONGINT;
		
		PROCEDURE &New();
		BEGIN
			Init(640, 481, FALSE);
			SetTitle(WM.NewString("AosTV"));
			NEW(chnlSeeker, tuner)
		END New;
		
		PROCEDURE Close();
		BEGIN
			Close^;
			vcd.VideoClose;
			tuner.Close;
			tuner.CloseVbi();
			alive := FALSE;
			chnlSeeker.Release;
			chnlSeeker := NIL;
		END Close;
		
		PROCEDURE PointerDown*(x, y:LONGINT; keys:SET);
		BEGIN
			lastX := bounds.l+x; lastY:=bounds.t+y; dragging := TRUE
		END PointerDown;
		
		PROCEDURE PointerMove*(x,y:LONGINT; keys:SET);
		VAR dx, dy : LONGINT;
		BEGIN
			IF dragging THEN 
				x := bounds.l + x; y := bounds.t + y; dx := x - lastX; dy := y - lastY;
				lastX := lastX + dx; lastY := lastY + dy;
				IF (dx # 0) OR (dy # 0) THEN manager.SetWindowPos(SELF, bounds.l + dx, bounds.t + dy) END
			END
		END PointerMove;				
		
		PROCEDURE PointerUp*(x, y:LONGINT; Keys:SET);
		BEGIN
			dragging := FALSE
		END PointerUp;
		
		PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
		BEGIN
			Draw^(canvas, w, h, 0)
		END Draw;
		
		PROCEDURE Handle(VAR m : Messages.Message);
		BEGIN
			IF m.msgType = Messages.MsgKey THEN 
				KeyEvent(m.x, m.flags, m.y)
			ELSIF m.msgType = Messages.MsgPointer THEN 
				IF m.msgSubType = Messages.MsgSubPointerMove THEN PointerMove(m.x, m.y, m.flags)
				ELSIF m.msgSubType = Messages.MsgSubPointerDown THEN PointerDown(m.x, m.y, m.flags)
				ELSIF m.msgSubType = Messages.MsgSubPointerUp THEN PointerUp(m.x, m.y, m.flags)
				ELSIF m.msgSubType = Messages.MsgSubPointerLeave THEN PointerLeave
				END
			ELSIF m.msgType = Messages.MsgClose THEN Close
			ELSIF m.msgType = Messages.MsgStyleChanged THEN StyleChanged
			END;
		END Handle;
		
		PROCEDURE KeyEvent(ucs : LONGINT; flags: SET; keySym: LONGINT);
		VAR (*res: BOOLEAN;*)
			ch : CHAR;
		BEGIN
			ch := CHR(ucs);
			IF ch = "+" THEN
				chnlSeeker.StopSeeking;
				chnlSeeker.SetStepSize(5);
				chnlSeeker.StartSeeking;
			ELSIF ch = ' ' THEN
				NEW(vbi);
				vbi.currentSuite := SelectTeletextSuite (tuner.GetFrequency());
				vbi.dead := FALSE;
			ELSIF ch = 'e' THEN
				vbi.dead := TRUE;
			ELSIF ch = "-" THEN
				chnlSeeker.StopSeeking;
				chnlSeeker.SetStepSize(-5);
				chnlSeeker.StartSeeking;
			ELSIF ch = "s" THEN
				chnlSeeker.StopSeeking;
			ELSIF ch = "n" THEN
					tuner.SetChannel(tuner.GetChannel()+1);
					Out.String("New Frequency: "); Out.Int(tuner.GetFrequency(), 0); Out.Ln;
			ELSIF ch = "p" THEN
				tuner.SetChannel(tuner.GetChannel()-1);
			ELSIF ch = "1" THEN
				vcd.StopCaptureContinuous;
				vcd.SetGeometry(320, 260, 1, {});
				vcd.CaptureContinuous;
			ELSIF ch = "2" THEN
				vcd.StopCaptureContinuous;
				vcd.SetGeometry(640, 480, 1, {});
				vcd.CaptureContinuous;
			ELSIF ucs = ORD("m") THEN
				IF audio.IsAudioMute() THEN audio.SetAudioUnmute
				ELSE audio.SetAudioMute
				END
			END;
		END KeyEvent;

		PROCEDURE NewImage;
		VAR t : LONGINT;
		BEGIN {EXCLUSIVE}
			newImage := TRUE;
			t := AosKernel.GetTimer();
(*			IF t - last < 40 THEN AosOut.String("Early."); AosOut.Int(t - last, 5); AosOut.Ln END;*)
			last := t
		END NewImage;
		
	BEGIN {ACTIVE}
		alive := TRUE; NEW(timer);
		IF ~alive THEN
			Out.String("DEAD");
			Out.Ln;
		END;
		WHILE alive DO
			BEGIN {EXCLUSIVE}
				AWAIT(newImage OR ~alive);
				newImage := FALSE
			END;
			Invalidate(WMRectangles.MakeRect(0, 0, img.width, img.height))
		END
	END TvWindow;

CONST
	(*MaxFreq = 3000;*)
	(*MinFreq = 2000;*)
	(*FreqStep = 5;*)
	VbiLines = AosTVDriver.VbiMaxLines;
	VbiLineSize = AosTVDriver.VbiLineSize;
(*	VbiBufferItems = AosTVDriver.VbiBufferItems;*)
	VbiDataSize = AosTVDriver.VbiDataSize;
	VbiBufferSize = AosTVDriver.VbiBufferSize;
	VbiVT = {1};
	VbiVPS = {2};
(*	VbiVC = {3};*)
	VbiUndefined = -1;
	FpFac = 65536;
VAR
	(** Globally accessible list that contains all available channel names together with their frequency *)
	channels*: ChannelList;
	
	(* Linked list that contains the teletext pages for each channel *)
	teletextSuites: TeletextSuite;

	vcd: AosTVDriver.VideoCaptureDevice;
	tuner: AosTVDriver.TVTuner;
	audio: AosTVDriver.Audio;
	vbi : VbiDecoder;
	vbiBuffer : AosTVDriver.VbiBuffer;
	(*frequency: LONGINT;*)
	(*seeking: LONGINT;*)
	(*channel: LONGINT;*)
	noOfNotificationCalls: LONGINT;
	tvWnd: TvWindow;

	ch: TVChannel;
	dbPage: LONGINT;
	dbSub: LONGINT;
	hex: ARRAY 10 OF CHAR;
	Ctrl: BOOLEAN;


	PROCEDURE BuildTeletextSuites;
	VAR
		i: LONGINT;
		suite: TeletextSuite;
	BEGIN
		teletextSuites := NIL;
		FOR i := channels.GetCount()-1 TO 0 BY -1 DO
			NEW(suite);
			suite.channel := channels.GetItem(i);
			suite.next := teletextSuites;
			teletextSuites := suite;
		END;
	END BuildTeletextSuites;

	PROCEDURE SelectTeletextSuite (freq: LONGINT): TeletextSuite;
	VAR
		suite: TeletextSuite;
	BEGIN
		(* traverse the list of teletext suites and find the correct one according to the TV frequency *)
		suite := teletextSuites;
		WHILE (suite # NIL) & ((suite.channel.freq-10 > freq) OR (suite.channel.freq+10 < freq)) DO
			suite := suite.next;
		END;
		IF suite = NIL THEN
			Out.String("WARNING: TELETEXT_SUITE NOT FOUND!!");
			Out.Ln;
			Out.String("BUILDING NEW SUITE :-)"); Out.Ln;
			NEW (suite);
			NEW (suite.channel);
			suite.channel.freq := freq;
			suite.next := teletextSuites;
			teletextSuites := suite;
(*		ELSE
			Out.String("Selected Suite: ");
			Out.String(suite.channel.name);
			Out.Ln;*)
		END;
		RETURN suite
	END SelectTeletextSuite;


PROCEDURE NotificationHandler;
BEGIN
	IF noOfNotificationCalls = 50 THEN
		noOfNotificationCalls := 0;
		IF DEBUG THEN AosOut.String("{AosTV} notification handler was called 50 times."); AosOut.Ln; END;
	ELSE
		INC(noOfNotificationCalls);
	END;
END NotificationHandler;

PROCEDURE HandleSwitch (freq: LONGINT);
VAR
	i: LONGINT;
	ch: TVChannel;
	title: ARRAY 32 OF CHAR;
BEGIN
	(* This procedure makes only sense if there are registered TV channels *)
	IF channels.GetCount() = 0 THEN RETURN END;
	
	(* Find the channel name for the current TV frequency *)
	i := 0;
	REPEAT
		ch := channels.GetItem (i);
		INC (i)
	UNTIL (i = channels.GetCount()) OR ((ch.freq-10 < freq) & (ch.freq + 10 > freq));
	
	(* Set the title of the TV window accordingly *)
	title := "AosTV";
	IF (ch.freq-10 < freq) & (ch.freq + 10 > freq) THEN
		Utilities.Append (title, " - ");
		Utilities.Append (title, ch.name)
	END;
	tvWnd.SetTitle (WM.NewString (title));
	
	(* Redirect VBI output to the appropriate channel *)
	IF vbi # NIL THEN
		(* Get rid of the VBI data of the old TV channel *)
		ResetVbiBuffer;
		
		vbi.currentSuite := SelectTeletextSuite (freq);
		vbi.vtPage := NIL;
		vbi.discardPage := TRUE;
		vbi.chName := ""
	END;
END HandleSwitch;

PROCEDURE ResetVbiBuffer;
BEGIN
	vbiBuffer.readPos := vbiBuffer.insertPos;
	vbiBuffer.vbiSize := 0;
END ResetVbiBuffer;

PROCEDURE BuildChannelTable* (par : PTR): PTR;
BEGIN
	BuildChannelTableImpl;
	RETURN NIL;
END BuildChannelTable;

PROCEDURE BuildChannelTableImpl;
CONST
	Delay = 500;
VAR
	ch, max: LONGINT;
	t, i: LONGINT;
	found: LONGINT;
	tvCh: TVChannel;
	suite: TeletextSuite;
	manager: WM.WindowManager;
	audio: AosTVDriver.Audio;
	timer : AosKernel.Timer;
	f: AosFS.File;
	w: AosFS.Writer;
	filename, fileBak: ARRAY 32 OF CHAR;
	length, res: LONGINT;
BEGIN
	NEW(tvWnd);
	vcd := AosTVDriver.GetDefaultDevice();
	tuner := vcd.GetTuner();
	audio := vcd.GetAudio();
	(* open video device only if it is not already open *)
	IF ~ vcd.IsVideoOpen() THEN
		vcd.VideoOpen();
		vcd.InstallNotificationHandler(tvWnd.NewImage);
		vcd.SetInputDev1;
		tuner := vcd.GetTuner();
		tuner.Open();
		audio.SetAudioIntern;
		audio.SetAudioUnmute;
		vcd.SetVideo(AosMemory.PhysicalAdr(tvWnd.img.adr, 0), tvWnd.img.bpr);
		vcd.SetGeometry(640, 480, 1, {});
		vcd.SetPixelFormat(2);
		IF tuner.OpenVbi() = 0 THEN
			vbiBuffer := vcd.GetVbiData();
		END;
		vcd.CaptureContinuous;
		manager := WM.GetDefaultManager();
		manager.Add(100, 100, tvWnd, {WM.FlagFrame});
		tvWnd.SetPointerInfo(manager.pointerNull);
	END;

	NEW (channels);
	teletextSuites := NIL;
	IF (vbi = NIL) OR (vbi.dead) THEN
		NEW(vbi)
	END;
	vbi.dead := FALSE;
	vbi.extractName := TRUE;
	vbi.chName := "";
	
	max := tuner.GetMaxChannel();
(*	max := 20;*)

	AosOut.String("{AosTV} Automatic channel installation ");
	AosOut.Ln;
	AosOut.String("{AosTV} This will take about ");
	AosOut.Int(max*Delay DIV 1000, 0);
	AosOut.String(" seconds.");
	AosOut.Ln;
	
	found := 0;
	NEW (timer);
	
	FOR ch := 0 TO max-1 DO
		INC (found);
		tuner.SetChannel (ch);
		
		NEW (tvCh);
		tvCh.freq := tuner.GetFrequency();
		channels.Add (tvCh);
		
		NEW (suite);
		suite.channel := tvCh;
		suite.next := teletextSuites;
		teletextSuites := suite;
		
		timer.Sleep (Delay);
		
		FOR i := 0 TO 12 DO
			tvCh.name[i] := vbi.chName[i];
		END;
		HandleSwitch (tvCh.freq);
		
		IF Utilities.Length (tvCh.name) = 0 THEN
			(* Remove this channel from the list *)
			teletextSuites := teletextSuites.next;
			channels.Remove (tvCh);
			DEC (found);
		END;
	END;
	Out.String("Found "); Out.Int(found, 0); Out.String(" channels !");
	Out.Ln;
	
	AosOut.String("{AosTV} Automatic channel installation done.");
	AosOut.Ln;
	
	tuner.InstallChannelSwitchHandler (HandleSwitch);
	vbi.dead := TRUE;
	
	BuildTeletextSuites;
	vbi.extractName := FALSE;
	
	(* Write the table to disk *)
	IF found > 0 THEN
		f := AosFS.Old (ChannelFile);
		IF f # NIL THEN
			(* File existed before: Make Backup *)
			filename := ChannelFile;
			fileBak := ChannelFile;
			length := Utilities.Length (fileBak);
			fileBak[length-3] := 'B';
			fileBak[length-2] := 'a';
			fileBak[length-1] := 'k';
			AosFS.Rename (filename, fileBak, res);
			IF res # 0 THEN
				AosOut.String("{AosTV} Error backin up existing channel file.");
				AosOut.Ln
			END;
			AosOut.String("{AosTV} Original file was backed up to '");
			AosOut.String(fileBak);
			AosOut.String("'");
			AosOut.Ln;
		END;
		
		(* Write file header *)
		f := AosFS.New (ChannelFile);
		AosFS.OpenWriter (w, f, 0);
		w.String ("<!--");
		w.Ln;
		w.String ("AosTV channels; Auto-generated settings.");
		w.Ln;
		w.String ("To edit: EditTools.OpenAscii ");
		w.String (ChannelFile);
		w.Ln;
		w.String ("-->");
		w.Ln;
		w.Ln;
		
		(* Write channel settings *)
		w.String ("<TVChannelList>");
		w.Ln;
		FOR i := 0 TO channels.GetCount() -1 DO
			w.Char (CHR(9));
			w.String ("<Channel name=");
			w.Char (CHR(34));
			tvCh := channels.GetItem(i);
			w.String (tvCh.name);
			w.Char (CHR(34));
			
			w.String (" freq=");
			w.Char (CHR(34));
			tvCh := channels.GetItem(i);
			w.Int (tvCh.freq, 0);
			w.Char (CHR(34));
			
			w.String (" />");
			w.Ln;
		END;
		w.String ("</TVChannelList>");
		w.Update;
		AosFS.Register (f);
	END;
END BuildChannelTableImpl;

PROCEDURE Open*(par : PTR): PTR;
VAR
	manager: WM.WindowManager;
	audio: AosTVDriver.Audio;
	(*temp: LONGINT;*)
BEGIN
	dbPage := -1;
	dbSub := -1;
	NEW(tvWnd);
	vcd := AosTVDriver.GetDefaultDevice();
	tuner := vcd.GetTuner();
	audio := vcd.GetAudio();
	(* open video device only if it is not already open *)
	IF ~ vcd.IsVideoOpen() THEN
		vcd.VideoOpen();
		vcd.InstallNotificationHandler(tvWnd.NewImage);
		vcd.SetInputDev1;
		tuner := vcd.GetTuner();
		tuner.Open();
		tuner.SetChannel(2);
		tuner.InstallChannelSwitchHandler (HandleSwitch);
		ch := channels.GetItem (0);
		tuner.SetTVFrequency(ch.freq); (* inserted by OJ -- set Initial TV Channel to SF 1 *)
		audio.SetAudioIntern;
		audio.SetAudioUnmute;
		vcd.SetVideo(AosMemory.PhysicalAdr(tvWnd.img.adr, 0), tvWnd.img.bpr);
		vcd.SetGeometry(640, 480, 1, {});
		vcd.SetPixelFormat(2);
		IF tuner.OpenVbi() = 0 THEN
			vbiBuffer := vcd.GetVbiData();
			Out.String("press Space to capture Teletext");
			Out.Ln;
			Out.String("EditTools.OpenAscii Teletext.txt ~");
			Out.Ln;
		END;
		vcd.CaptureContinuous;
		manager := WM.GetDefaultManager();
		manager.Add(100, 100, tvWnd, {WM.FlagFrame});
		tvWnd.SetPointerInfo(manager.pointerNull);
	END;
		
	RETURN NIL
END Open;

PROCEDURE Close*(par: PTR): PTR;
VAR m : Messages.Message;
BEGIN
	IF tvWnd # NIL THEN
		m.msgType := Messages.MsgClose;
		IF tvWnd.sequencer # NIL THEN IF tvWnd.sequencer.Add(m) THEN END END	
	END;
	vbi.dead := TRUE;
	tuner := NIL;
	RETURN NIL;
END Close;

PROCEDURE Set*(par : PTR) : PTR;
VAR s : AosCommands.Parameters;
		name : ARRAY 100 OF CHAR;
		freq : LONGINT;
		sr : AosIO.StringReader;
BEGIN
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^);
	sr.SkipWhitespace(); sr.Int(freq, TRUE); sr.Token(name); sr.SkipWhitespace;
	AosOut.String("Setting Channel to "); AosOut.String(name); AosOut.Ln;
	tuner.SetTVFrequency(freq);
	RETURN NIL
END Set;

PROCEDURE Get*(par : PTR) : PTR;
BEGIN
	AosOut.String("Aos.Call AosTV.Set"); AosOut.Char(CHR(9)); (*AosOut.Int(tuner.frequency, 5);*) AosOut.Char(CHR(9)); AosOut.Ln;
	RETURN NIL
END Get;

(** Get Teletext page for the appropriate TV frequency. num must be in range [0..799] *)
PROCEDURE GetTeletextPage* (freq, pageNum, subPage: LONGINT): AosTexts.Text;
VAR
	suite: TeletextSuite;
	tmp, page: DataPage;
BEGIN
	suite := SelectTeletextSuite (freq);
	IF (suite = NIL) OR (pageNum < 0) OR (pageNum >= 800) OR (suite.pages [pageNum].data = NIL) THEN
		Out.String("NIL (oben)");Out.Ln;
		RETURN NIL
	END;
	page := suite.pages [pageNum].data;
	
	(* Search for the requested subpage *)
	IF (page.subPageNo = subPage) OR (subPage = -1) THEN
		RETURN page.formattedText
	ELSE
		tmp := page;
		REPEAT
			page := page.nextSub;
			Out.String("current subPagePage: "); Out.Int(page.subPageNo, 0);Out.Ln;
		UNTIL (tmp = page) OR (page.subPageNo = subPage);
		IF tmp = page THEN
			(* not in data structure *)
			Out.String("NIL (unten)");Out.Ln;
			RETURN NIL
		ELSE
			Out.String("Page found!");Out.Ln;
			RETURN page.formattedText;
		END;
	END;
END GetTeletextPage;

PROCEDURE GetNextTeletextPage* (freq: LONGINT; VAR pageNum, subPage: LONGINT): AosTexts.Text;
VAR
	suite: TeletextSuite;
	next: LONGINT;
BEGIN
	suite := SelectTeletextSuite (freq);
	IF (suite = NIL) OR (pageNum < 0) OR (pageNum >= 800) OR (suite.pages [pageNum].data = NIL) THEN
		Out.String("NIL (oben)");Out.Ln;
		RETURN NIL
	END;
	next := suite.pages [pageNum].next;
	IF next = VbiUndefined THEN
		RETURN NIL
	END;
	pageNum := next;
	subPage := suite.pages [pageNum].data.subPageNo;
	RETURN suite.pages [pageNum].data.formattedText;
END GetNextTeletextPage;

PROCEDURE GetPrevTeletextPage* (freq: LONGINT; VAR pageNum, subPage: LONGINT): AosTexts.Text;
VAR
	suite: TeletextSuite;
	prev: LONGINT;
BEGIN
	suite := SelectTeletextSuite (freq);
	IF (suite = NIL) OR (pageNum < 0) OR (pageNum >= 800) OR (suite.pages [pageNum].data = NIL) THEN
		Out.String("NIL (oben)");Out.Ln;
		RETURN NIL
	END;
	prev := suite.pages [pageNum].prev;
	IF prev = VbiUndefined THEN
		RETURN NIL
	END;
	pageNum := prev;
	subPage := suite.pages [pageNum].data.subPageNo;
	RETURN suite.pages [pageNum].data.formattedText;
END GetPrevTeletextPage;

PROCEDURE GetNextSubPage* (freq: LONGINT; VAR pageNum, subPage: LONGINT): AosTexts.Text;
VAR
	suite: TeletextSuite;
	tmp, page: DataPage;
BEGIN
	suite := SelectTeletextSuite (freq);
	IF (suite = NIL) OR (pageNum < 0) OR (pageNum >= 800) OR (suite.pages [pageNum].data = NIL) THEN
		Out.String("NIL (oben)");Out.Ln;
		RETURN NIL
	END;
	page := suite.pages [pageNum].data;
	
	(* Search for the requested subpage *)
	IF (page.subPageNo = subPage) OR (subPage = -1) THEN
		page := page.nextSub;
		subPage := page.subPageNo;
		RETURN page.formattedText
	ELSE
		tmp := page;
		REPEAT
			page := page.nextSub;
		UNTIL (tmp = page) OR (page.subPageNo = subPage);
		page := page.nextSub;
		subPage := page.subPageNo;
		RETURN page.formattedText
	END;
END GetNextSubPage;

PROCEDURE GetPrevSubPage* (freq: LONGINT; VAR pageNum, subPage: LONGINT): AosTexts.Text;
VAR
	suite: TeletextSuite;
	tmp, page: DataPage;
BEGIN
	suite := SelectTeletextSuite (freq);
	IF (suite = NIL) OR (pageNum < 0) OR (pageNum >= 800) OR (suite.pages [pageNum].data = NIL) THEN
		Out.String("NIL (oben)");Out.Ln;
		RETURN NIL
	END;
	page := suite.pages [pageNum].data;
	
	(* Search for the requested subpage *)
	IF (page.subPageNo = subPage) OR (subPage = -1) THEN
		page := page.prevSub;
		subPage := page.subPageNo;
		RETURN page.formattedText
	ELSE
		tmp := page;
		REPEAT
			page := page.prevSub;
		UNTIL (tmp = page) OR (page.subPageNo = subPage);
		page := page.prevSub;
		subPage := page.subPageNo;
		RETURN page.formattedText
	END;
END GetPrevSubPage;

PROCEDURE GetFreq*():LONGINT;
BEGIN
	RETURN tuner.GetFrequency();
END GetFreq;

PROCEDURE LoadChannelTable (filename: ARRAY OF CHAR);
VAR
	f: AosFS.File;
	scanner: XMLScanner.Scanner;
	parser: XMLParser.Parser;
	xmlChannels : XML.Document;
	enum: XMLObjects.Enumerator;
	e : XML.Element;
	s : XML.String;
	p : PTR;
	ch : TVChannel;
BEGIN
	xmlChannels := NIL;
	f := AosFS.Old (filename);
	IF f # NIL THEN
		NEW(scanner, f);
		NEW(parser, scanner);
		xmlChannels := parser.Parse();
		IF xmlChannels # NIL THEN
			e := xmlChannels.GetRoot();
			enum := e.GetContents();
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS XML.Element THEN
					e := p(XML.Element);
					s := e.GetName();
					IF (s # NIL) & (s^ = "Channel") THEN
						NEW(ch);
						s := e.GetAttributeValue ("name");
						IF s # NIL THEN
							COPY (s^, ch.name);
						END;
						s := e.GetAttributeValue ("freq");
						IF s # NIL THEN
							Utilities.StrToInt (s^, ch.freq);
						END;
						channels.Add (ch);
					END;
				END;
			END;
		END;
	END
END LoadChannelTable;

BEGIN
	NEW(channels);
	LoadChannelTable (ChannelFile);
	IF channels.GetCount() = 0 THEN
		AosOut.String("{AosTV} Could not load channel list.");
		AosOut.Ln;
		BuildChannelTableImpl;
	ELSE
		BuildTeletextSuites
	END;
END AosTV.

System.Free AosTV ~
Aos.Call AosTV.Open
Aos.Call AosTV.Close
Aos.Call AosTV.Get
Aos.Call AosTV.Set	2810	SF1
Aos.Call AosTV.Set	3375	SF2
Aos.Call AosTV.Set	 9332	SFi
Aos.Call AosTV.Set	3264	ARD
Aos.Call AosTV.Set	3488	ZDF
Aos.Call AosTV.Set	2132	ORF 1
Aos.Call AosTV.Set	4166	ORF 2
Aos.Call AosTV.Set	2697	3Sat
Aos.Call AosTV.Set	2924	RTL
Aos.Call AosTV.Set	7668	RTL II
Aos.Call AosTV.Set	8308	Pro7
Aos.Call AosTV.Set	2019	Kabel 1
Aos.Call AosTV.Set	4618	Sat1
Aos.Call AosTV.Set	8692	VOX
Aos.Call AosTV.Set	2584	TeleZueri
Aos.Call AosTV.Set	 8564	BR
Aos.Call AosTV.Set	 8436	n-tv
Aos.Call AosTV.Set	 8052	5 MediaSet
Aos.Call AosTV.Set	 7924	DSF
Aos.Call AosTV.Set	 8819	TV5
Aos.Call AosTV.Set	 8948	BBC Prime
Aos.Call AosTV.Set	 9204	NBC
Aos.Call AosTV.Set	 9588	TSR1
Aos.Call AosTV.Set	 7540	KiKa/ARTE
Aos.Call AosTV.Set	 8692	VOX
Aos.Call AosTV.Set	 9588	TSR2
Aos.Call AosTV.Set	 3146	TSI1
Aos.Call AosTV.Set	 3594	TVE
Aos.Call AosTV.Set	 3706	Live
Aos.Call AosTV.Set	 3834	Franzoesisch??
Aos.Call AosTV.Set	 3946	CNN
Aos.Call AosTV.Set	 4058	BW
Aos.Call AosTV.Set	 4282	Servicekanal
Aos.Call AosTV.Set	 4394	Eurosport
Aos.Call AosTV.Set	 4506	TSI 2
Aos.Call AosTV.Set	 4730	MTV
Aos.Call AosTV.Set	 5242	Swizz
Aos.Call AosTV.Set	 4858	RTP
Aos.Call AosTV.Set	 5114	EuroNews
Aos.Call AosTV.Set	 5370	Cartoon Network
Aos.Call AosTV.Set	 5498	SuperRTL
Aos.Call AosTV.Set	 5754	Franzoesisch??
Aos.Call AosTV.Set	 6138	WDR
Aos.Call AosTV.Set	 6266	MDR

Aos.Call AosTV.Set 3946

(* Balcab Settings *)
Aos.Call AosTV.Open
Aos.Call AosTV.Set	3035		ARD
Aos.Call AosTV.Set	3147		ZDF
Aos.Call AosTV.Set	3259		Südwest
Aos.Call AosTV.Set	3599		SF1
Aos.Call AosTV.Set	3375		TSR 1
Aos.Call AosTV.Set	3824		SF2
Aos.Call AosTV.Set	2697		Sat 1
Aos.Call AosTV.Set	2468		RTL
Aos.Call AosTV.Set	9972		RTL II
Aos.Call AosTV.Set	11764	  StarTV
Aos.Call AosTV.Set	10484	  VOX
Aos.Call AosTV.Set	1908		Pro7
Aos.Call AosTV.Set	13172	  ORF 1
Aos.Call AosTV.Set	13428	  ORF 2
Aos.Call AosTV.Set	8692		VivaSwizz
Aos.Call AosTV.Set	3930		TF1
Aos.Call AosTV.Set	4036		France 2
Aos.Call AosTV.Set	4166		France 3
Aos.Call AosTV.Set	4391		TV5
Aos.Call AosTV.Set	8052		M6
Aos.Call AosTV.Set	9844		ARTE
Aos.Call AosTV.Set	2020		Eurosport
Aos.Call AosTV.Set	7668		DSF
Aos.Call AosTV.Set	4282		Tele Basel
Aos.Call AosTV.Set	8564		Super RTL
Aos.Call AosTV.Set	12404	  Kabel 1

Aos.Call AosTV.Set	11636	  9 Live!
Aos.Call AosTV.Set	12916	  SF Info
Aos.Call AosTV.Set	8180		BBC Prime
Aos.Call AosTV.Set	8436		RaiDue
Aos.Call AosTV.Set	10356	  NTV
Aos.Call AosTV.Set	12148	  BBC World
Aos.Call AosTV.Set	12276	  TCM / Cartoon Network
Aos.Call AosTV.Set	13044	  NBC Europe
Aos.Call AosTV.Set	1796		WDR
Aos.Call AosTV.Set	7284		CNBC
Aos.Call AosTV.Set	2808		3sat
Aos.Call AosTV.Set	2132		mdr
Aos.Call AosTV.Set	2924		BR
Aos.Call AosTV.Set	4618		TVE
Aos.Call AosTV.Set	2584		CNN
Aos.Call AosTV.Set	3706		RaiUno

AosTV.StoreSF1 ~
AosTV.LoadSF1 ~