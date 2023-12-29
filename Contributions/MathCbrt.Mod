(* CAPO - Computational Analysis Platform for Oberon - by Alan Freed and Felix Friedrich. *)
(* Version 1, Update 0 *)

MODULE MathCbrt;   (** AUTHOR "adf"; PURPOSE "Compute the cube root"; *)

	(* Algorithm is from: J.F. Hart, E.W. Cheney, C.L. Lawson, H.J. Maehly, C.K. Mesztenyi, J.R. Rice, H.G. Thacher, Jr., 
		 and C. Witzgall, "Computer Approximations," in: The SIAM Series in Applied Mathematics, Wiley, New York, 1968. *)

IMPORT NbrInt, NbrRe, NbrCplx, DataErrors, MathReSeries;  

VAR 
	cbrt2: NbrRe.Real;
	(* Whenever NbrRe.Real is a 32-bit real, define the following arrays. *)
	cbrtP, cbrtQ: ARRAY 3 OF NbrRe.Real;  
	(* Or whenever NbrRe.Real is a 64-bit real, define the following arrays. *)
	(*  cbrtP, cbrtQ: ARRAY 5 OF NbrRe.Real;  *)

	PROCEDURE Fn*( x: NbrRe.Real ): NbrRe.Real;  
	VAR isNeg: BOOLEAN;  i, exponent, mod: NbrInt.Integer;  cbrtRadix, cubeRoot, mantissa, ratFn, update: NbrRe.Real;   
	BEGIN  
		IF NbrRe.Radix = 2 THEN cbrtRadix := cbrt2
		ELSIF NbrRe.Radix = 4 THEN cbrtRadix := cbrt2 * cbrt2
		ELSIF NbrRe.Radix = 8 THEN cbrtRadix := 2
		ELSIF NbrRe.Radix = 16 THEN cbrtRadix := 2 * cbrt2
		ELSIF NbrRe.Radix = 32 THEN cbrtRadix := 2 * cbrt2 * cbrt2
		ELSE DataErrors.Error( "Not implemented for this CPU." );  RETURN 0
		END;  
		(* Obtain original mantissa and exponent. *)
		mantissa := NbrRe.Mantissa( x );  exponent := NbrRe.Exponent( x );   
		IF mantissa > 0 THEN isNeg := FALSE ELSE isNeg := TRUE;  mantissa := NbrRe.Abs( mantissa ) END;  
		(* Reduce the input to the range: 1/radix <= x <= 1. *)
		mantissa := mantissa / NbrRe.Radix;  
		(* Initial estimate for cube root, scaled by 1 / cbrtRadix. *)
		ratFn := MathReSeries.TruncatedRationalFunction( cbrtP, cbrtQ, mantissa );   
		IF isNeg THEN mantissa := -ratFn ELSE mantissa := ratFn END;  
		(* Convert back to a real number. *)
		mod := exponent MOD 3;  
		IF mod = 0 THEN cubeRoot := NbrRe.Re( cbrtRadix * mantissa, exponent DIV 3 )
		ELSIF mod = 1 THEN cubeRoot := NbrRe.Re( cbrtRadix * cbrtRadix * mantissa, (exponent + 1) DIV 3 )
		ELSE  cubeRoot := NbrRe.Re( NbrRe.Radix * mantissa, (exponent - 1) DIV 3 )
		END;   
		(* Three Newton iterations to enhance accuracy. *)
		FOR i := 1 TO 3 DO update := cubeRoot - (cubeRoot - x / (cubeRoot * cubeRoot)) / 3;  cubeRoot := update END;   
		RETURN cubeRoot
	END Fn;

	PROCEDURE CplxFn*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR abs, arg, im, re: NbrRe.Real;  cbrt: NbrCplx.Complex;  
	BEGIN 
		im := NbrCplx.Im( z );  
		IF im = 0 THEN 
			re := NbrCplx.Re( z );  
			IF re # 0 THEN NbrCplx.Set( Fn( re ), 0, cbrt ) ELSE cbrt := 0 END 
		ELSE abs := NbrCplx.Abs( z );  arg := NbrCplx.Arg( z );  NbrCplx.SetPolar( Fn( abs ), arg / 3, cbrt )
		END;  
		RETURN cbrt
	END CplxFn;  

BEGIN 
	(* Whenever NbrRe.Real is a 32-bit real, use the following eonstants. *)
	cbrt2 := 1.25992105;   
	(* Constants from Table CBRT 0723 from "Computer Approximations". *)
	cbrtP[0] := 0.17782942E-1;  cbrtP[1] := 0.885812034;  cbrtP[2] := 1.76794059;
	cbrtQ[0] := 0.99419338E-1;  cbrtQ[1] := 1.57522016;  cbrtQ[2] := 1.0
	(* Or, whenever NbrRe.Real is a 64-bit real, use the following eonstants. *)
	(*  cbrt2 := 1.25992104989487316476D0; 
	(* Constants from Table CBRT 0725 from "Computer Approximations". *)
	cbrtP[0] := 5.6235404D-4;  cbrtP[1] := 0.11020808784D0;  cbrtP[2] := 2.0968321394D0;  
	cbrtP[3] := 6.4753110699D0;  cbrtP[4] := 2.6119694699D0;  
	cbrtQ[0] := 4.6449016D-3;  cbrtQ[1] := 0.36413680255D0;  cbrtQ[2] := 3.7287466072D0;  
	cbrtQ[3] := 6.1973781157D0;  cbrtQ[4] := 1.0D0  *)
END MathCbrt.