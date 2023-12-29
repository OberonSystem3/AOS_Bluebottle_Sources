(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosDisplayWM;	(* pjm *)
(** AUTHOR "pjm"; PURPOSE "Aos display driver for WM window"; *)

(* Based on Window.Display.Mod and OberonWindow.Mod of tf. *)

IMPORT SYSTEM, AosBoot, AosIO, AosCommands, AosDisplays, AosInputs, Raster, WMWindowManager, Rect := WMRectangles;

CONST
	DefaultDisplayName = "Oberon";
	DefaultWidth = 1024;
	DefaultHeight = 768;

	AlphaCursor = 128;
	
	KeyBufSize = 64;	
	
	SHIFT* = 0;  CTRL* = 1;  ALT* = 2;	(** for KeyState *)

	Flip = FALSE;
	
	Cache = TRUE;
	
VAR
	nilpix: Raster.Pixel;

TYPE
	OberonWindow = OBJECT (WMWindowManager.BufferWindow)
		VAR
			input: OberonInput;	(* initialized from outside *)
		
			curKeys:SET;
			curX, curY:LONGINT;
	
			keyhead, keytail: LONGINT;
			keybuf: ARRAY KeyBufSize OF CHAR;	
			
			keys: SET;
			break: BOOLEAN;
			fixMM : BOOLEAN;
			lastCtrl : BOOLEAN;
			
		PROCEDURE Mouse(VAR x, y: INTEGER; VAR keys:SET);
		BEGIN {EXCLUSIVE}
			keys := {};
			IF 0 IN curKeys THEN INCL(keys, 2) END;
			IF 1 IN curKeys THEN INCL(keys, 1) END;
			IF 2 IN curKeys THEN INCL(keys, 0) END;
			x := SHORT(curX);
			y := SHORT(curY)
		END Mouse;
		
		PROCEDURE PointerMove(x, y:LONGINT; keys:SET);
		BEGIN {EXCLUSIVE}
			curX := x; curY := y; curKeys := keys;
			IF fixMM &lastCtrl THEN INCL(curKeys, 1) END;
			IF input # NIL THEN input.timer.Wakeup END	(* have to check, because upcalls to us can start immediately *)
		END PointerMove;
		
		PROCEDURE PointerUp(x, y:LONGINT; keys:SET);
		BEGIN {EXCLUSIVE}
			curX := x; curY := y; curKeys := keys;
			IF input # NIL THEN input.timer.Wakeup END
		END PointerUp;

			(* Keyboard handling *)
		PROCEDURE InsertKey(ch:CHAR; keysym: LONGINT; flags:SET);
		BEGIN
			keys := {};
			IF flags * AosInputs.Shift # {} THEN INCL(keys, SHIFT) END;
			IF flags * AosInputs.Ctrl # {} THEN INCL(keys, CTRL) END;
			IF flags * AosInputs.Alt # {} THEN INCL(keys, ALT) END;
			IF ch # 0X THEN
				IF (keytail+1) MOD KeyBufSize # keyhead THEN
					keybuf[keytail] := ch; keytail := (keytail+1) MOD KeyBufSize
				END;
				(*timer.WakeUp*)	(* always do wakeup because of race with Sleep *)
			ELSIF keysym = AosInputs.KsBreak THEN	(* Break *)
				break := TRUE
				(*timer.WakeUp *)
			ELSE
				(* skip *)
			END 
		END InsertKey;	
		
		PROCEDURE Close;
		BEGIN {EXCLUSIVE}
			InsertKey(0FFX, 0, {})
		END Close;

		PROCEDURE KeyEvent(ucs:LONGINT; flags:SET; keysym: LONGINT);
		BEGIN {EXCLUSIVE}
			IF fixMM & ((flags * AosInputs.Ctrl # {}) # lastCtrl)  THEN
				lastCtrl := flags * AosInputs.Ctrl # {};
				IF lastCtrl THEN INCL(curKeys, 1) ELSE EXCL(curKeys, 1) END;
				IF input # NIL THEN input.timer.Wakeup END
			ELSE
				InsertKey(CHR(ucs), keysym, flags);
				IF input # NIL THEN input.timer.Wakeup END
			END;
		END KeyEvent;
		
		PROCEDURE Read(VAR ch: CHAR; VAR b: BOOLEAN);
		BEGIN {EXCLUSIVE}
			AWAIT(keyhead # keytail);
			ch := keybuf[keyhead]; keyhead := (keyhead+1) MOD KeyBufSize;
			b := break; break := FALSE
		END Read;
	
		PROCEDURE Available(VAR num: INTEGER; VAR b: BOOLEAN);
		BEGIN {EXCLUSIVE}
			num := SHORT((keytail-keyhead) MOD KeyBufSize);
			b := break; break := FALSE
		END Available;
	
		PROCEDURE KeyState(VAR k: SET);
		BEGIN {EXCLUSIVE}
			k := keys
		END KeyState; 
		
	END OberonWindow;

TYPE
	OberonInput = OBJECT (AosInputs.OberonInput)
		VAR window: OberonWindow;
		
		PROCEDURE Mouse(VAR x, y: INTEGER; VAR keys:SET);
		BEGIN
			window.Mouse(x, y, keys)
		END Mouse;
		
		PROCEDURE Read(VAR ch: CHAR; VAR b: BOOLEAN);
		BEGIN
			window.Read(ch, b)
		END Read;
		
		PROCEDURE Available(VAR num: INTEGER; VAR b: BOOLEAN);
		BEGIN
			window.Available(num, b)
		END Available;

		PROCEDURE KeyState(VAR k: SET);
		BEGIN
			window.KeyState(k)
		END KeyState;

	END OberonInput;
	
TYPE
	Display* = OBJECT (AosDisplays.Display)	(* custom display object only accessed by Oberon (no EXCLUSIVE) *)
		VAR
			disp: OberonWindow;
			inp: OberonInput;
			bufimg: Raster.Image;
			mode, mode1: Raster.Mode;
			ml, mt, mr, mb: LONGINT;
			
		PROCEDURE LocalAddDirty(l, t, r, b: LONGINT);
		BEGIN
			IF Cache THEN
				IF l < ml THEN ml := l END;	(* enlarge dirty rectangle *)
				IF t < mt THEN mt := t END;
				IF r > mr THEN mr := r END;
				IF b > mb THEN mb := b END
			ELSE
				disp.Invalidate(Rect.MakeRect(l, t, r, b))
			END
		END LocalAddDirty;
		
		PROCEDURE Update;
		BEGIN
			IF Cache & (ml # MAX(LONGINT)) THEN
				disp.Invalidate(Rect.MakeRect(ml, mt, mr, mb));	(* updated dirty rectangle *)
				ml := MAX(LONGINT); mt := MAX(LONGINT); mr := MIN(LONGINT); mb := MIN(LONGINT)
			END
		END Update;
		
		PROCEDURE Transfer*(VAR buf: ARRAY OF CHAR; ofs, stride, x, y, w, h, op: LONGINT);
		BEGIN
			Raster.InitMode(mode, Raster.srcCopy);
			IF Flip THEN
				Raster.Init(bufimg, w, h, disp.img.fmt, -stride, SYSTEM.ADR(buf[ofs]) + (h-1)*stride);
				IF op = AosDisplays.get THEN 
					Raster.Copy(disp.img, bufimg, x, height-y-h, x+w, height-y, 0, 0, mode)
				ELSIF op = AosDisplays.set THEN
					Raster.Copy(bufimg, disp.img, 0, 0, w, h, x, height-y-h, mode);
					LocalAddDirty(x, height-y-h, x+w, height-y)
				ELSE (* skip *)
				END
			ELSE
				Raster.Init(bufimg, w, h, disp.img.fmt, stride, SYSTEM.ADR(buf[ofs]));
				IF op = AosDisplays.get THEN 
					Raster.Copy(disp.img, bufimg, x, y, x+w, y+h, 0, 0, mode)
				ELSIF op = AosDisplays.set THEN
					Raster.Copy(bufimg, disp.img, 0, 0, w, h, x, y, mode);
					LocalAddDirty(x, y, x+w, y+h)
				ELSE (* skip *)
				END
			END
		END Transfer;
		
		PROCEDURE Fill*(col, x, y, w, h: LONGINT);
		BEGIN
			IF Flip THEN
				Fill^(col, x, y, w, h)	(* supermethod not exclusive *)
			ELSE
				Raster.InitMode(mode, Raster.srcCopy);
				IF ASH(col, 1) < 0 THEN	(* invert *)
					Raster.InitMode(mode, Raster.InvDst);
					Raster.Fill(disp.img, x, y, x+w, y+h, nilpix, mode)
				ELSE
					Raster.InitMode(mode, Raster.srcCopy);
					Raster.Fill(disp.img, x, y, x+w, y+h, SYSTEM.VAL(Raster.Pixel, SYSTEM.VAL(SET, col) + {24..31}), mode)
				END;
				LocalAddDirty(x, y, x+w,  y+h)
			END
		END Fill;
		
		PROCEDURE Dot*(col, x, y: LONGINT);
		BEGIN
			IF Flip THEN
				Dot^(col, x, y)	(* supermethod not exclusive *)
			ELSE
				IF ASH(col, 1) < 0 THEN	(* invert *)
					Raster.InitMode(mode, Raster.InvDst);
					Raster.Put(disp.img, x, y, nilpix, mode)
				ELSE
					Raster.InitMode(mode, Raster.srcCopy);
					Raster.Put(disp.img, x, y, SYSTEM.VAL(Raster.Pixel, SYSTEM.VAL(SET, col) + {24..31}), mode)
				END;
				LocalAddDirty(x, y, x+1, y+1)
			END
		END Dot;
		
		PROCEDURE Mask*(VAR buf: ARRAY OF CHAR; bitofs, stride, fg, bg, x, y, w, h: LONGINT);
		VAR p, i, y0, h0: LONGINT; s: SET; fgp, bgp: Raster.Pixel;
		BEGIN
			IF Flip THEN
				Mask^(buf, bitofs, stride, fg, bg, x, y, w, h)	(* supermethod not exclusive *)
			ELSE
				IF (w > 0) & (h > 0) THEN
					i := SYSTEM.ADR(buf[0]) MOD 4;
					INC(bitofs, i * 8);
					p := SYSTEM.ADR(buf[0])-i + bitofs DIV 32 * 4;	(* p always aligned to 32-bit boundary *)
					bitofs := bitofs MOD 32; stride := stride*8;
					IF ASH(fg, 1) < 0 THEN	(* invert *)
						Raster.InitMode(mode, Raster.InvDst)
					ELSE
						Raster.InitMode(mode, Raster.srcCopy);
						fgp := SYSTEM.VAL(Raster.Pixel, SYSTEM.VAL(SET, fg) + {24..31})
					END;
					IF ASH(bg, 1) < 0 THEN	(* invert *)
						Raster.InitMode(mode1, Raster.InvDst)
					ELSE
						Raster.InitMode(mode1, Raster.srcCopy);
						bgp := SYSTEM.VAL(Raster.Pixel, SYSTEM.VAL(SET, bg) + {24..31})
					END;
					y0 := y; h0 := h;
					LOOP
						SYSTEM.GET(p, s); i := bitofs;
						LOOP
							IF (i MOD 32) IN s THEN
								IF fg >= 0 THEN Raster.Put(disp.img, x+i-bitofs, y, fgp, mode) END
							ELSE
								IF bg >= 0 THEN Raster.Put(disp.img, x+i-bitofs, y, bgp, mode1) END
							END;
							INC(i);
							IF i-bitofs = w THEN EXIT END;
							IF i MOD 32 = 0 THEN SYSTEM.GET(p+i DIV 8, s) END
						END;
						DEC(h);
						IF h = 0 THEN EXIT END;
						INC(y); INC(bitofs, stride);
						IF (bitofs >= 32) OR (bitofs < 0) THEN	(* moved outside s *)
							INC(p, bitofs DIV 32 * 4); bitofs := bitofs MOD 32
						END
					END;
					LocalAddDirty(x, y0, x+w, y0+h0)
				END
			END
		END Mask;
		
		PROCEDURE Copy*(sx, sy, w, h, dx, dy: LONGINT);
		BEGIN
			IF Flip THEN
				Copy^(sx, sy, w, h, dx, dy)	(* supermethod not exclusive *)
			ELSE
				Raster.InitMode(mode, Raster.srcCopy);
				Raster.Copy(disp.img, disp.img, sx, sy, sx+w, sy+h, dx, dy, mode);
				LocalAddDirty(dx, dy, dx+w,  dy+h)
			END
		END Copy;
		
		PROCEDURE &Init(name: ARRAY OF CHAR; w, h: LONGINT);
		VAR res: LONGINT; ptr: WMWindowManager.PointerInfo; pixel: Raster.Pixel; mode: Raster.Mode;
			manager : WMWindowManager.WindowManager;
			s : ARRAY 16 OF CHAR;
		BEGIN
			ml := MAX(LONGINT); mt := MAX(LONGINT); mr := MIN(LONGINT); mb := MIN(LONGINT);
			width := w; height := h; offscreen := 0; unit := 10000;
			NEW(bufimg);
			NEW(disp, w, h, FALSE);
			AosBoot.GetConfig("MB", s);
			disp.fixMM := (s = "2") OR (s = "-2");
			NEW(inp);
			inp.window := disp; disp.input := inp;	(* "multiple inheritance" *)
			CASE disp.img.fmt.code OF
				Raster.d8: format := AosDisplays.index8
				|Raster.bgr565: format := AosDisplays.color565
				|Raster.bgr888: format := AosDisplays.color888
				|Raster.bgra8888: format := AosDisplays.color8888
			END;
			IF ~Flip THEN
				NEW(ptr); ptr.hotX := 2; ptr.hotY := 2;
				NEW(ptr.img); Raster.Create(ptr.img, 4, 4, Raster.BGRA8888);
				Raster.SetRGBA(pixel, 255, 255, 255, AlphaCursor);
				Raster.InitMode(mode, Raster.srcCopy);
				Raster.Fill(ptr.img, 0, 0, 4, 4, pixel, mode);
				Raster.SetRGBA(pixel, 0, 0, 0, AlphaCursor);
				Raster.Fill(ptr.img, 1, 1, 3, 3, pixel, mode);
				disp.SetPointerInfo(ptr)
			END;
			IF Flip THEN
				disp.SetTitle(WMWindowManager.NewString("Oberon for Bluebottle down under"))
			ELSE
				disp.SetTitle(WMWindowManager.NewString("Oberon for Bluebottle"))
			END;
			WMWindowManager.ExtAddWindow(disp, 0, 0, {WMWindowManager.FlagFrame});
				(* register display *)
			SELF.desc := "WM virtual display driver";
			SELF.SetName(name);
			AosDisplays.registry.Add(SELF, res);
			ASSERT(res = 0);
				(* register input *)
			inp.desc := "WM virtual input driver";
			inp.SetName(name);
			AosInputs.oberonInput.Add(inp, res);
			ASSERT(res = 0)
		END Init;
		
		PROCEDURE Finalize;
		BEGIN
			IF disp = NIL THEN RETURN END;
			AosInputs.oberonInput.Remove(inp);
			AosDisplays.registry.Remove(SELF);
			disp.manager.Remove(disp);	(* close window *)
			bufimg := NIL; disp := NIL; inp := NIL;	(* cause further drawing calls to trap *)
			IF main = SELF THEN main := NIL END
		END Finalize;
		
	END Display;

VAR
	main: Display;

PROCEDURE Install*(par: PTR): PTR;	(** name width height ~ (separated by single spaces) *)
VAR w, h: LONGINT; p: AosCommands.Parameters; r: AosIO.StringReader; name: ARRAY 32 OF CHAR;
BEGIN
	IF main = NIL THEN
		w := 0; h := 0; name := "";
		IF par # NIL THEN
			p := par(AosCommands.Parameters);
			NEW(r, LEN(p.str^)); r.Set(p.str^);
			r.SkipSpaces; r.Token(name);
			r.SkipSpaces; r.Int(w, FALSE);
			r.SkipBytes(1); r.Int(h, FALSE)	(* skip "x" or single space *)
		END;
		IF name = "" THEN name := DefaultDisplayName END;
		IF w <= 0 THEN w := DefaultWidth END;
		IF h <= 0 THEN h := DefaultHeight END;
		NEW(main, name, w, h)
	END;
	RETURN NIL
END Install;

PROCEDURE Remove*(par: PTR): PTR;
BEGIN
	IF main # NIL THEN main.Finalize END;
	RETURN NIL
END Remove;

PROCEDURE SwitchToWM*;
BEGIN
	IF main # NIL THEN 
		(* send magic key to Oberon (assume Oberon.Loop will read it) *)
		main.disp.InsertKey(0FEX, AosInputs.KsNil, {})
	END 
END SwitchToWM;


BEGIN
	main := NIL
END AosDisplayWM.

AosDisplayWM.Install

System.Free TempDisplayTests TempDisplay AosDisplayWM ~

TempDisplayTests.Mod
TempDisplay.Mod

(*
o mode set every time?
o clean up at exit
o optimization: remove exclusive, factor out all modes (src, dst, mode combinations) [what about finalize?]
*)
