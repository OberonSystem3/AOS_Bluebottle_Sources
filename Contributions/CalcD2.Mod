(* CAPO - Computational Analysis Platform for Oberon - by Alan Freed and Felix Friedrich. *)
(* Version 1, Update 0 *)

MODULE CalcD2;   (** AUTHOR "adf"; PURPOSE "Computes second-order derivatives"; *)

IMPORT NbrInt, NbrRe, NbrCplx, MathRe, CalcFn;  

CONST 
	(** Admissible parameters to be passed for establishing the differencing scheme used to compute a derivative. *)
	Forward* = 9;  Central* = 10;  Backward* = 11;  

VAR
	epsilon, zero: NbrRe.Real; 

	(* Force the argument in and out of addressable memory to minimize round-off error. *)
	PROCEDURE DoNothing( x: NbrRe.Real );  
	BEGIN 
	END DoNothing;  

	PROCEDURE DoCplxNothing( z: NbrCplx.Complex );  
	BEGIN 
	END DoCplxNothing;  

	(** Computes  d2f(x)/dx2 *)
	PROCEDURE Solve*( f: CalcFn.ReArg;  atX: NbrRe.Real;  differencing: NbrInt.Integer ): NbrRe.Real;  
	VAR h, h2, hOpt, hMin, power, result, temp: NbrRe.Real;  
	BEGIN   
		(*  Select an optimum step size.  See v5.7 on Numerical Derivatives in Press et al., Numerical Recipes. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 4;  
		hOpt := NbrRe.Abs( atX ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		(* Refine h so that  x + h and x differ by an exactly representable number in memory. *)
		temp := atX + h;  DoNothing( temp );  h := temp - atX;  h2 := h * h;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atX + 2 * h ); 
			result := result - 2 * f( atX + h ); 
			result := (result + f( atX )) / h2
		ELSIF differencing = Backward THEN 
			result := f( atX ); 
			result := result - 2 * f( atX - h ); 
			result := (result + f( atX - 2 * h )) / h2
		ELSE  (* differencing = Central *)
			result := f( atX + h );
			result := result - 2 * f( atX ); 
			result := (result + f( atX - h )) / h2
		END;  
		RETURN result
	END Solve;  

	(** Computes  d2f(z)/dz2 *)
	PROCEDURE SolveCplx*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, ch2, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 4;  
		hOpt := NbrCplx.Abs( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.Set( h, h, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  ch2 := ch * ch;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + 2 * ch ); 
			result := result - 2 * f( atZ + ch ); 
			result := (result + f( atZ )) / ch2
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := result - 2 * f( atZ - ch ); 
			result := (result + f( atZ - 2 * ch )) / ch2
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := result - 2 * f( atZ ); 
			result := (result + f( atZ - ch )) / ch2
		END;  
		RETURN result
	END SolveCplx;  

	(** Computes 62f(z)/6x2,  z = x + i y  *)
	PROCEDURE SolveCplxRe*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, ch2, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 4;  
		hOpt := NbrCplx.Abs( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.Set( h, zero, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  ch2 := ch * ch;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + 2 * ch ); 
			result := result - 2 * f( atZ + ch ); 
			result := (result + f( atZ )) / ch2
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := result - 2 * f( atZ - ch ); 
			result := (result + f( atZ - 2 * ch )) / ch2
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := result - 2 * f( atZ ); 
			result := (result + f( atZ - ch )) / ch2
		END;  
		RETURN result
	END SolveCplxRe;  

	(** Computes  62f(z)/6y2,  z = x + i y  *)
	PROCEDURE SolveCplxIm*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, ch2, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 4;  
		hOpt := NbrCplx.Abs( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.Set( zero, h, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  ch2 := ch * ch;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + 2 * ch ); 
			result := result - 2 * f( atZ + ch ); 
			result := (result + f( atZ )) / ch2
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := result - 2 * f( atZ - ch ); 
			result := (result + f( atZ - 2 * ch )) / ch2
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := result - 2 * f( atZ ); 
			result := (result + f( atZ - ch )) / ch2
		END;  
		RETURN result
	END SolveCplxIm;  

	(** Computes  62f(z)/6r2,  z = r exp( i f )  *)
	PROCEDURE SolveCplxAbs*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, ch2, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 4;  
		hOpt := NbrCplx.Abs( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.SetPolar( h, zero, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  ch2 := ch * ch;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + 2 * ch ); 
			result := result - 2 * f( atZ + ch ); 
			result := (result + f( atZ )) / ch2
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := result - 2 * f( atZ - ch ); 
			result := (result + f( atZ - 2 * ch )) / ch2
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := result - 2 * f( atZ ); 
			result := (result + f( atZ - ch )) / ch2
		END;  
		RETURN result
	END SolveCplxAbs;  

	(** Computes  62f(z)/6f2,  z = r exp( i f )  *)
	PROCEDURE SolveCplxArg*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, ch2, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 4;  
		hOpt := NbrCplx.Arg( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.SetPolar( zero, h, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  ch2 := ch * ch;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + 2 * ch ); 
			result := result - 2 * f( atZ + ch ); 
			result := (result + f( atZ )) / ch2
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := result - 2 * f( atZ - ch ); 
			result := (result + f( atZ - 2 * ch )) / ch2
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := result - 2 * f( atZ ); 
			result := (result + f( atZ - ch )) / ch2
		END;  
		RETURN result
	END SolveCplxArg;  

BEGIN 
	epsilon := 100 * NbrRe.Epsilon;  zero := 0
END CalcD2.