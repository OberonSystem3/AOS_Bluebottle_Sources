MODULE AosExampleOberon;	(* pjm *)
(** AUTHOR "pjm"; PURPOSE "How to use Oberon modules from an active object"; *)

IMPORT AosKernel, Texts, Oberon, Kernel;

TYPE
	Example = OBJECT
		VAR i: LONGINT; w: Texts.Writer; t: Texts.Text; timer: AosKernel.Timer;
	BEGIN {ACTIVE}
		NEW(timer);
		Kernel.LockOberon;
		Texts.OpenWriter(w);
		NEW(t); Texts.Open(t, "");
		Oberon.OpenText("Example", t, 200, 200);
		Kernel.UnlockOberon;
		FOR i := 1 TO 10 DO
			Kernel.LockOberon;
			Texts.WriteString(w, "Example "); Texts.WriteInt(w, i, 1); Texts.WriteLn(w);
			Texts.Append(t, w.buf);
			Kernel.UnlockOberon;
			timer.Sleep(1000)
		END
	END Example;

PROCEDURE Test*(par: PTR): PTR;
VAR e: Example;
BEGIN
	NEW(e);
	RETURN NIL
END Test;

END AosExampleOberon.

System.Free AosExampleOberon ~

Aos.Call AosExampleOberon.Test
