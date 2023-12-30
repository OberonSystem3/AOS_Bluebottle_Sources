MODULE AosHotKeysCommands; (** AUTHOR: "staubesv"; PURPOSE: "Useful hot key commands"; *)
(**
 * This modules contains some commands considered being useful for execution via hot keys.
 *
 * Overview/Usage:
 *
 *	AosHotKeysCommands.SimulateMouse MouseX|MouseY|MouseButtons|MouseWheel value ~ generates mouse messages
 *
 *	AosHotKeysCommands.EnterCommand ~ opens a window that queries a command string that is executed on enter
 *	AosHotKeysCommands.ClearLog ~ clears the kernel log
 *	
 *	AosHotKeysCommands.ToggleFullscreen ~ toggles minimized/fullscreen mode of the window that currently owns the focus
 *	AosHotKeysCommands.CloseWindow ~ closes the window that currently owns the focus (without warning!!!)
 *	AosHotKeysCommands.SetViewportRange x y [w h ["s"]["d"]] ~ sets the range of the default view port
 *
 * History:
 *
 *	30.11.2006	First release (staubesv)
 *)
 
IMPORT
	SYSTEM,
	AosOut, AosModules, AosCommands, AosIO, AosPlugins, AosDisplays, Utilities,
	AosInputs, WMLog,
	WMWindowManager, WMComponents, WMStandardComponents, WMEditors, WMGraphics;
	
CONST
	(* Command window constants *)
	DefaultWidth = 400; DefaultHeight = 40;
	DefaultTextColor =  WMGraphics.White;
	DefaultTextBgColor =  00008080H;

	(* Mouse simulator constants *)
	MouseX = "MouseX";
	MouseY = "MouseY";
	MouseButtons = "MouseButtons";
	MouseWheel = "MouseWheel";
		
TYPE

	(* Window that queries a command string and executes it when pressing enter. Pressing the escape key closes the window. The
	 * window is also closed when it looses the focus *)
	Window = OBJECT (WMComponents.FormWindow)
	VAR
		editor : WMEditors.Editor;
		
		PROCEDURE HandleEnter(sender, data : ANY);
		VAR commandString : ARRAY 4096 OF CHAR; msg : ARRAY 128 OF CHAR; res : LONGINT;
		BEGIN
			editor.GetAsString(commandString);
			IF commandString # "" THEN
				AosCommands.Call(commandString, {}, res, msg);
				IF res # AosCommands.Ok THEN
					AosOut.String("AosHotKeysCommands: Failed to execute '"); AosOut.String(commandString);
					AosOut.String("', res: "); AosOut.Int(res, 0);
					AosOut.String(" ("); AosOut.String(msg); AosOut.String(")");
					AosOut.Ln;
				END;
			END;
			Close;
		END HandleEnter;
		
		PROCEDURE HandleEscape(sender, data : ANY);
		BEGIN
			Close;
		END HandleEscape;
	
		PROCEDURE FocusLost*;
		BEGIN
			Close;
		END FocusLost;
		
		PROCEDURE Close*;
		BEGIN
			Close^; window := NIL;
		END Close;
		
		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		BEGIN
			NEW(editor);
			editor.alignment.Set(WMComponents.AlignClient);
			editor.onEnter.Add(HandleEnter);
			editor.onEscape.Add(HandleEscape);
			editor.allowScrollbars.Set(FALSE);
			editor.multiLine.Set(FALSE);
			editor.tv.defaultTextColor.Set(DefaultTextColor);
			editor.tv.defaultTextBgColor.Set(0); 
			editor.fillColor.Set(DefaultTextBgColor);
			RETURN editor;
		END CreateForm;
			
		PROCEDURE &New;
		VAR manager : WMWindowManager.WindowManager;
		BEGIN
			Init(DefaultWidth, DefaultHeight, TRUE);
			SetContent(CreateForm());
			SetTitle(Utilities.NewString("Enter command: "));
			WMWindowManager.ExtAddWindow(SELF, (width DIV 2) - (DefaultWidth DIV 2), (height DIV 2) - (DefaultHeight DIV 2), {});
			manager := WMWindowManager.GetDefaultManager();
			manager.SetFocus(SELF);
			editor.SetFocus;
		END New;

	END Window;

VAR
	window : Window;
	
	(* Default window manager and view port *)
	manager : WMWindowManager.WindowManager; 
	viewport : WMWindowManager.ViewPort;
	
	(* display information *)
	width, height : LONGINT;

(** Generate mouse message *)
PROCEDURE SimulateMouse*(par : ANY) : ANY; (** MouseX|MouseY|MouseButtons|MouseWheel value ~ *)
VAR 
	r : AosIO.StringReader; 
	string : ARRAY 32 OF CHAR; value : LONGINT;
	msg : AosInputs.MouseMsg;
	doHandle : BOOLEAN;
BEGIN
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(string);
	IF r.res = AosIO.Ok THEN
		r.SkipWhitespace; r.Int(value, FALSE);
		IF (r.res = AosIO.Ok) THEN
			doHandle := TRUE;
			IF Utilities.Match(string, MouseX) THEN msg.dx := value;
			ELSIF Utilities.Match(string, MouseY) THEN msg.dy := value;
			ELSIF Utilities.Match(string, MouseWheel) THEN msg.dz := value;
			ELSIF Utilities.Match(string, MouseButtons) THEN msg.keys := SYSTEM.VAL(SET, value);
			ELSE
				doHandle := FALSE;
			END;		
			IF doHandle THEN AosInputs.mouse.Handle(msg); END;
		END;
	END;
	RETURN NIL;
END SimulateMouse;

(** Opens a window that queries a command string and executes it on enter *)
PROCEDURE EnterCommand*(par : ANY) : ANY; (** ~ *)
BEGIN {EXCLUSIVE}
	IF window = NIL THEN NEW(window); END;
	RETURN NIL
END EnterCommand;

(** Clear kernel log *)
PROCEDURE ClearLog*(par : ANY) : ANY; (** ~ *)
BEGIN
	WMLog.kernelLog.AcquireWrite;
	WMLog.kernelLog.Delete(0, WMLog.kernelLog.GetLength());
	WMLog.kernelLog.ReleaseWrite;
	RETURN NIL
END ClearLog;

(** Toggle minimized/fullscreen for the window that currently owns the focus *)
PROCEDURE ToggleFullscreen*(par : ANY) : ANY;
VAR window : WMWindowManager.Window; newWidth, newHeight : LONGINT;
BEGIN
	window := manager.GetFocusOwner();
	IF (window.GetWidth() = width) & (window.GetHeight() = height) THEN
		manager.SetWindowPos(window, ENTIER(viewport.range.l) + 100, ENTIER(viewport.range.t) + 100);
		newWidth := window.initialBounds.r - window.initialBounds.l;
		newHeight := window.initialBounds.b - window.initialBounds.t;
	ELSE
		manager.SetWindowPos(window, ENTIER(viewport.range.l), ENTIER(viewport.range.t));
		newWidth := width;
		newHeight := height;
	END;
	manager.SetWindowSize(window, newWidth, newHeight);	 
	window.Resized(newWidth, newHeight);
	RETURN NIL
END ToggleFullscreen;

(** Close the window that currently owns the focus *)
PROCEDURE CloseWindow*(par : ANY) : ANY;
VAR window : WMWindowManager.Window; formWindow : WMComponents.FormWindow;
BEGIN
	window := manager.GetFocusOwner();
	IF window IS WMComponents.FormWindow THEN
		formWindow := window (WMComponents.FormWindow);
		formWindow.Close;
	END;
	RETURN NIL
END CloseWindow;

PROCEDURE Contains(string : ARRAY OF CHAR; ch : CHAR) : BOOLEAN;
VAR i : LONGINT;
BEGIN
	FOR i := 0 TO LEN(string)-1 DO
		IF CAP(string[i]) = CAP(ch) THEN RETURN TRUE; END;
	END;	
	RETURN FALSE;	
END Contains;

(**
 * Set the range of the default view port. Can be used for virtual desktops.
 * Parameters:
 *	x, y : Position of viewport ovservable range (pixel)
 * 	w, h : width and height of viewport observable range (pixel, set to display width/height if omitted)
 *	"s" : show transition to new range
 *	"d": interpret x, y, w and h parameters as multiples of display width/height
 *)
PROCEDURE SetViewportRange*(par : ANY) : ANY; (** x y [w h ["s"]["d"]] ~ *)
VAR r : AosIO.StringReader; x, y, w, h : LONGINT; showTransition : BOOLEAN; string : ARRAY 32 OF CHAR;
BEGIN
	AosCommands.PosPar(par, r);	
	r.SkipWhitespace; r.Int(x, FALSE);
	r.SkipWhitespace; r.Int(y, FALSE);
	r.SkipWhitespace; r.Int(w, FALSE);
	r.SkipWhitespace; r.Int(h, FALSE);
	r.SkipWhitespace; r.String(string);
	
	showTransition := Contains(string, "s");
	IF Contains(string, "d") THEN
		x := x * width; w := w * width;
		y := y * height; h := h * height;
	END;
	
	IF w = 0 THEN w := width; END;
	IF h = 0 THEN h := height; END;
	
	viewport.SetRange(x, y, w, h, showTransition);
	RETURN NIL;
END SetViewportRange;

PROCEDURE Init;
VAR plugin : AosPlugins.Plugin;
BEGIN
	manager := WMWindowManager.GetDefaultManager();
	viewport := WMWindowManager.GetDefaultView();
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
	IF window # NIL THEN window.Close; window := NIL; END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	Init;
END AosHotKeysCommands.

AosHotKeysCommands.ClearLog ~
AosHotKeysCommands.EnterCommand ~
AosHotKeysCommands.SimulateMouse MouseWheel -3 ~

AosHotKeysCommands.SetViewportRange 0 0 ~
AosHotKeysCommands.SetViewportRange -1 0 1 1 sd ~

Example: Four virtual desktops with overview, depended on display resolution

AosHotKeysCommands.SetViewportRange -1 0 1 1 sd ~	(* left desktop *)
AosHotKeysCommands.SetViewportRange 0 0 1 1 sd ~		(* standard desktop *)
AosHotKeysCommands.SetViewportRange -1 -1 1 1 sd ~	(* left/up desktop *)
AosHotKeysCommands.SetViewportRange 0 -1 1 1 sd ~	(* up desktop *)

AosHotKeysCommands.SetViewportRange -1 -1 2 2 sd ~	(* all four desktops *)

AosHotKeysCommands.Test ~

S.Free AosHotKeysCommands ~
