(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE Math;	(** portable *)
(** AUTHOR "?"; PURPOSE "Math utility module (REAL)"; *)

(* Aos version - requires floating-point instruction support. *)

(**
	Commonly needed Math for REALs.
*)

IMPORT SYSTEM;

CONST
	e* = 2.7182818284590452354E0;
	pi* = 3.14159265358979323846E0;

PROCEDURE -Sin(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 024H 	(* FLD [ESP] *)
	DB 0D9H, 0FEH	(* FSIN *)
	DB 058H	(* POP EAX *)
END Sin;

PROCEDURE -Cos(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 024H	(* FLD [ESP] *)
	DB 0D9H, 0FFH	(* FCOS *)
	DB 058H	(* POP EAX *)
END Cos;

PROCEDURE -Arctan(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 024H	(* FLD [ESP] *)
	DB 0D9H, 0E8H	(* FLD1 *)
	DB 0D9H, 0F3H	(* FPATAN ST(1)/ST(0) *)
	DB 058H	(* POP EAX *)
END Arctan;

PROCEDURE -Sqrt(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 024H	(* FLD [ESP] *)
	DB 0D9H, 0FAH	(* FSQRT ST(0) *)
	DB 058H	(* POP EAX *)
END Sqrt;

PROCEDURE -Ln(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 0E8H	(* FLD1 *)
	DB 0D9H, 0EAH 	(* FLDL2E *)
	DB 0DEH, 0F9H	(* FDIVP ST(1)/ST(0) *)
	DB 0D9H, 004H, 024H	(* FLD [ESP] *)
	DB 0D9H, 0F1H	(* FYL2X *)
	DB 058H	(* POP EAX *)
END Ln;

PROCEDURE -Exp(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 24H	(* FLD [ESP] *)
	DB 0D9H, 0EAH	(* FLDL2E *)
	DB 0DEH, 0C9H	(* FMULP ST(1), ST(0) *)
	DB 0D9H, 0C0H	(* FLD ST(0) *)
	DB 0D9H, 0FCH	(* FRNDINT *)
	DB 0D9H, 0C9H	(* FXCH ST(1), ST(0) *)
	DB 0D8H, 0E1H	(* FSUB ST(0), ST(1) *)
	DB 0D9H, 0F0H	(* F2XM1 *)
	DB 0D9H, 0E8H	(* FLD1 *)
	DB 0DEH, 0C1H	(* FADDP ST(1), ST(0) *)
	DB 0D9H, 0FDH	(* FSCALE *)
	DB 0DDH, 0D9H	(* FSTP ST(1) *)
	DB 058H	(* POP EAX *)
END Exp;

PROCEDURE sin*(x: REAL): REAL;
BEGIN 
	IF x < 0.0 THEN RETURN -Sin(-x) ELSE RETURN Sin(x) END 
END sin;

PROCEDURE cos*(x: REAL): REAL;
BEGIN 
	IF x < 0.0 THEN RETURN Cos(-x) ELSE RETURN Cos(x) END 
END cos;

PROCEDURE arctan*(x: REAL): REAL;
BEGIN 
	RETURN Arctan(x)
END arctan;

PROCEDURE sqrt*(x: REAL): REAL;
BEGIN 
	IF x <= 0 THEN
		IF x = 0 THEN RETURN 0 ELSE HALT(80) END
	ELSE
		RETURN Sqrt(x)
	END
END sqrt;

PROCEDURE ln*(x: REAL): REAL;
BEGIN 
	IF x <= 0 THEN HALT(80)
	ELSE
		RETURN Ln(x)
	END
END ln;

PROCEDURE exp*(x: REAL): REAL;
BEGIN 
	RETURN Exp(x)
END exp;

END Math.
