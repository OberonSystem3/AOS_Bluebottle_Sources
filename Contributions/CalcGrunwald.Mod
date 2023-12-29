(* CAPO - Computational Analysis Platform for Oberon - by Alan Freed and Felix Friedrich. *)
(* Version 1, Update 0 *)

MODULE CalcGrunwald;   (** AUTHOR "adf"; PURPOSE "Grünwald-Letnikov algorithms for the fractional calculus"; *)

IMPORT NbrInt, NbrRe, MathRe, CalcFn;  

CONST   
	(** Status of integration, i.e., admissible values for the returned parameter 'res'. *)
	OKay* = 0;  MaxSubDivReached* = 1;  Oscillation* = 2;  
	
	(**  Arguments of differ-integration are:
	f	the function being differintegrated,
	x	the argument of f, also the upper limit of differintegration,
	order	(> 0)  the fractional order of differintegration, i.e., a, 
	error	the requested and achieved error tolerances, 
	res	status of the differintegration.
	 *)

VAR
	(** Upper bound for the number of subintervals for integration/differentiation. *)
	MaxIntervals-: NbrInt.Integer;
	
	PROCEDURE Grunwald( f: CalcFn.ReArg;  a, b, order: NbrRe.Real;  VAR error, result: NbrRe.Real;  VAR res: NbrInt.Integer );  
	(* Use Grünwald-Letnikov definition for fractional-order differintegration. Requires  a < b. 
	f	the argument of differintegration,
	a	the lower limit of differintegration,
	b	the upper limit of differintegration,
	order	the fractional order of differintegration, i.e., a,
			if  order > 0  then it is a fractional differentiation
			if  order < 0  then it is a fractional integration 
	error	the requested and achieved error tolerances.
		 *)
	VAR i, im1, ip1, n: NbrInt.Integer;  absError, absX, dx, errorLast, fn, fnm1, last, tol: NbrRe.Real;  
		fns, save: POINTER TO ARRAY OF NbrRe.Real;  
	BEGIN 
		(* Implements the G2 algorithm of K. B. Oldham and J. Spanier, "The Fractional Calculus", 1974, pg. 138. *)
		result := 0;  n := 4;  tol := NbrRe.Max( error, 100 * NbrRe.Epsilon );  NEW( fns, 3 );  dx := (b - a) / 2;  
		FOR i := 0 TO 2 DO fns[i] := f( b - i * dx ) END;  
		error := NbrRe.MaxNbr;  
		LOOP 
			save := fns;  fns := NIL;  NEW( fns, n + 1 );  dx := (b - a) / n;  
			FOR i := 0 TO n DO 
				IF NbrInt.Odd( i ) THEN fns[i] := f( b - i * dx ) ELSE fns[i] := save[i DIV 2] END 
			END;  
			last := result;  result := 0;  
			FOR i := n - 1 TO 1 BY -1 DO 
				im1 := i - 1;  ip1 := i + 1;  
				(* G2 algorithm, pg. 138 in Oldham & Spanier. *)
				fn := order * (fns[ip1] - 2 * fns[i] + fns[im1]) / 2;  fn := order * ((fns[ip1] - fns[im1]) - fn) / 4;  
				fn := fns[i] - fn;  result := (result + fn) * (im1 - order) / i
			END;  
			fnm1 := f( b + dx );  fn := order * (fns[1] - 2 * fns[0] + fnm1) / 2;  fn := order * ((fns[1] - fnm1) - fn) / 4;  
			result := (result + fns[0] - fn) * MathRe.Power( n / b, order );  n := 2 * n;  errorLast := error;  
			absError := NbrRe.Abs( result - last );  absX := NbrRe.Abs( result );  
			IF absX > 1 THEN error := absError / absX ELSE error := NbrRe.Max( absError, 50 * NbrRe.Epsilon * absX ) END;  
			IF error < tol THEN res := OKay;  EXIT END;  
			IF n = MaxIntervals THEN res := MaxSubDivReached;  EXIT END;  
			IF error > errorLast THEN result := last;  res := Oscillation;  EXIT END 
		END 
	END Grunwald;  

	(** Computes a Riemann-Liouville fractional-order derivative. 
			Daf(x) = DnIaf(x) = (1/G(n-a)) dn/dxn x0x (x-y)n-1-a f(y) dy,   n-1 < a # n,  n N @,  a N !+  *)
	PROCEDURE SolveD*( f: CalcFn.ReArg;  x, order: NbrRe.Real;  VAR error: NbrRe.Real;  VAR res: NbrInt.Integer ): NbrRe.Real;  
	VAR result, zero: NbrRe.Real;  
	BEGIN 
		error := 0;  result := 0;  res := OKay;  zero := 0;  
		IF f # NIL THEN 
			IF zero # x THEN 
				IF order < zero THEN order := -order END;  
				IF zero < x THEN Grunwald( f, zero, x, order, error, result, res ) 
				ELSE Grunwald( f, x, zero, order, error, result, res );  result := -result
				END 
			END 
		ELSE result := 0
		END;  
		RETURN result
	END SolveD;  

	(** Computes a Riemann-Liouville fractional-order integral. 
			 Iaf(x) = (1/G(a)) x0x (x-y)a-1 f(y) dy,  a N !+  *)
	PROCEDURE SolveI*( f: CalcFn.ReArg;  x, order: NbrRe.Real;  VAR error: NbrRe.Real;  VAR res: NbrInt.Integer ): NbrRe.Real;  
	VAR result, zero: NbrRe.Real;  
	BEGIN 
		error := 0;  result := 0;  res := OKay;  zero := 0;  
		IF f # NIL THEN 
			IF zero # x THEN 
				IF order > zero THEN order := -order END;  
				IF zero < x THEN Grunwald( f, zero, x, order, error, result, res ) 
				ELSE Grunwald( f, x, zero, order, error, result, res );  result := -result
				END 
			END 
		END;  
		RETURN result
	END SolveI;  

BEGIN 
	MaxIntervals := NbrInt.MaxNbr 
END CalcGrunwald.