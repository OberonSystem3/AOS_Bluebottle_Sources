MODULE WMOSD; (** AUTHOR: "staubesv"; PURPOSE: "Simple On Screen Display for messages"; *)
(**
 * Usage:
 *
 *	WMOSD.Open message-string [duration] ~ Show message-string for duration milliseconds
 *	WMOSD.Close ~	
 *
 *	WMOSD.Test ~	Perform endless self-test
 *	S.Free WMOSD ~ 
 *
 * History: 
 *
 *	03.11.2006	First release (staubesv)
 *)
 
IMPORT
	AosOut, AosModules, AosKernel, AosCommands, AosIO, AosDisplays, AosPlugins, AosRandom, Utilities,
	WM := WMWindowManager, WMComponents, WMStandardComponents, WMMessages, WMGraphics;

CONST

	(* Font settings *)
	DefaultFontName = "Oberon";
	DefaultFontSize = 24;
	DefaultFontStyle = {};
	
	DefaultPositionTop = 0;
	DefaultHeight = 100;
	
	DefaultBgFillColor = 00008080H;
	
	DefaultDuration = 1500; (* in millisecond, resolution: TimerResolution ms *)
	TimerResolution = 100;
	
TYPE

	(* Singleton overlay window *)
	Window = OBJECT(WMComponents.FormWindow)
	VAR
		label- : WMStandardComponents.Label;
		
		timer : AosKernel.Timer;
		alive, dead : BOOLEAN;
		
		PROCEDURE Show(message : ARRAY OF CHAR);
		BEGIN
			label.caption.SetAOC(message);
		END Show;
				
		PROCEDURE Stop;
		BEGIN
			alive := FALSE; timer.Wakeup; 
		END Stop;

		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR font : WMGraphics.Font;
		BEGIN
			NEW(label);
			label.alignment.Set(WMComponents.AlignClient); label.fillColor.Set(DefaultBgFillColor);
			label.alignH.Set(WMGraphics.AlignCenter); label.alignV.Set(WMGraphics.AlignCenter);
			label.textColor.Set(WMGraphics.White);

			font := WMGraphics.GetFont(DefaultFontName, DefaultFontSize, DefaultFontStyle);
			IF font # NIL THEN 
				label.SetFont(font);
			ELSE
				AosOut.String("Font "); AosOut.String(DefaultFontName); AosOut.String(" not found."); AosOut.Ln;
			END;			

			RETURN label;
		END CreateForm;
	
		PROCEDURE &New;
		VAR vc : WMComponents.VisualComponent;
		BEGIN
			NEW(timer); alive := TRUE; dead := FALSE;
			vc := CreateForm();			
			Init^(width, DefaultHeight, TRUE);
			SetContent(vc);
			SetTitle(WM.NewString("Overlay Window"));
			WM.ExtAddWindow(SELF, 0, 0, {WM.FlagNoFocus} + {WM.FlagStayOnTop});
		END New;
		
	BEGIN {ACTIVE}
		REPEAT
			timer.Sleep(TimerResolution);		
		UNTIL ~alive OR TimeExpired();
		
		Close;
		
		DecNofWindows;
	END Window;
	
VAR
	window : Window; (* exclusive access only! *)
	width, height : LONGINT;
	timeleft : LONGINT; (* exclusive access only! *)
	nofWindows : LONGINT;
		
	testsRunning : LONGINT; (* exclusive access only! *)
	stopSelftest : BOOLEAN;	
	
PROCEDURE DecNofWindows;
BEGIN {EXCLUSIVE}
	DEC(nofWindows);
END DecNofWindows;
		
PROCEDURE TimeExpired() : BOOLEAN;
BEGIN {EXCLUSIVE}
	DEC(timeleft, TimerResolution);
	RETURN timeleft < 0;
END TimeExpired;
	
PROCEDURE Show*(message : ARRAY OF CHAR; duration : LONGINT);
BEGIN {EXCLUSIVE}
	IF duration <= 0 THEN duration := 500; END;
	IF window # NIL THEN 
		IF timeleft > 0 THEN 
			timeleft := duration;
			window.Show(message);
		ELSE (* too late, window will be closed soon *)
			window.Stop; window := NIL;
			timeleft := duration;
			INC(nofWindows);
			NEW(window); window.Show(message);
		END;
	ELSE
		timeleft := duration;
		INC(nofWindows);
		NEW(window); window.Show(message);
	END;
END Show;
	
(**	Show the specified message. 
	Optionally specified the duration in milliseconds the window is visible. *)
PROCEDURE Open*(par : ANY) : ANY; (** message_string [duration] ~ *)
VAR r : AosIO.StringReader; message : ARRAY 1024 OF CHAR; duration : LONGINT;
BEGIN
	AosCommands.PosPar(par, r);
	r.String(message); r.SkipWhitespace;
	r.Int(duration, FALSE);
	IF (r.res # AosIO.Ok) OR (duration <= 0)  THEN duration := DefaultDuration; END;
	Show(message, duration);
	RETURN NIL
END Open;

(** Close the overlay window if it's open *)
PROCEDURE Close*(par : ANY) : ANY; (** ~ *)
BEGIN {EXCLUSIVE}
	IF window # NIL THEN window.Stop; window := NIL; END;
	RETURN NIL;
END Close;

(** Perform endless self-test. To stop the tests, unload the module. Multiple instances can run simultaneously. *)
PROCEDURE Test*(par : ANY) : ANY; (** ~ *)
CONST MinDuration = 1; MaxDuration = 100000;
VAR 
	random : AosRandom.Generator; timer : AosKernel.Timer;
	number : LONGINT; message : ARRAY 128 OF CHAR;
	ignore : PTR;
BEGIN
	BEGIN {EXCLUSIVE} 
		stopSelftest := FALSE; INC(testsRunning); 
		AosOut.String("Overlay Window test started ("); AosOut.Int(testsRunning, 0); AosOut.String(" instances)"); AosOut.Ln;
	END;
	NEW(random); NEW(timer);
	LOOP
		number := random.Dice(MaxDuration) + MinDuration;
		Utilities.IntToStr(number, message);
		Show(message, number);
		number := random.Dice(2000) + 1;
		timer.Sleep(number);
		IF number MOD 10 = 0 THEN ignore := Close(NIL); END;
		IF stopSelftest THEN EXIT; END;
	END;
	BEGIN {EXCLUSIVE} DEC(testsRunning); END;
	RETURN NIL;
END Test;

PROCEDURE Init;
VAR plugin : AosPlugins.Plugin;
BEGIN
	plugin := AosDisplays.registry.Get("");
	IF plugin # NIL THEN
		width := plugin(AosDisplays.Display).width;
		height := plugin(AosDisplays.Display).height;
	ELSE
		width := 1024;
		height := 768;
	END;
END Init;

PROCEDURE Cleanup;
BEGIN {EXCLUSIVE}
	IF testsRunning > 0 THEN
		stopSelftest := TRUE;
		AWAIT(testsRunning = 0);
	END;
	IF window # NIL THEN window.Stop; AWAIT(nofWindows = 0); END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	Init;
END WMOSD.

WMOSD.Open "Hello World" 10000~
WMOSD.Open "Check this" 1000 ~

WMOSD.Close ~

WMOSD.Test ~

S.Free WMOSD ~
