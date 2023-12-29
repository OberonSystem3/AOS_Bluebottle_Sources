(* CAPO - Computational Analysis Platform for Oberon - by Alan Freed and Felix Friedrich. *)
(* Version 1, Update 0 *)

MODULE CalcD1;   (** AUTHOR "adf"; PURPOSE "Computes a first-order derivative"; *)

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

	(** Computes  df(x)/dx *)
	PROCEDURE Solve*( f: CalcFn.ReArg;  atX: NbrRe.Real;  differencing: NbrInt.Integer ): NbrRe.Real;  
	VAR h, hOpt, hMin, power, result, temp: NbrRe.Real;  
	BEGIN   
		(*  Select an optimum step size.  See v5.7 on Numerical Derivatives in Press et al., Numerical Recipes. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 3;  
		hOpt := NbrRe.Abs( atX ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		(* Refine h so that  x + h and x differ by an exactly representable number in memory. *)
		temp := atX + h;  DoNothing( temp );  h := temp - atX;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atX + h ); 
			result := (result - f( atX )) / h
		ELSIF differencing = Backward THEN 
			result := f( atX ); 
			result := (result - f( atX - h )) / h
		ELSE  (* differencing = Central *)
			result := f( atX + h );
			result := (result - f( atX - h )) / (2 * h)
		END;  
		RETURN result
	END Solve;  

	(** Computes  df(z)/dz *)
	PROCEDURE SolveCplx*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 3;  
		hOpt := NbrCplx.Abs( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.Set( h, h, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + ch ); 
			result := (result - f( atZ )) / ch
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := (result - f( atZ - ch )) / ch
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := (result - f( atZ - ch )) / (2 * ch)
		END;  
		RETURN result
	END SolveCplx;  
	
	(** Computes  6f(z)/6x,  z = x + i y  *)
	PROCEDURE SolveCplxRe*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 3;  
		hOpt := NbrCplx.Abs( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.Set( h, zero, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + ch ); 
			result := (result - f( atZ )) / ch
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := (result - f( atZ - ch )) / ch
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := (result - f( atZ - ch )) / (2 * ch)
		END;  
		RETURN result
	END SolveCplxRe;  

	(** Computes  6f(z)/6y,  z = x + i y  *)
	PROCEDURE SolveCplxIm*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 3;  
		hOpt := NbrCplx.Abs( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.Set( zero, h, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + ch ); 
			result := (result - f( atZ )) / ch
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := (result - f( atZ - ch )) / ch
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := (result - f( atZ - ch )) / (2 * ch)
		END;  
		RETURN result
	END SolveCplxIm;  
	
	(** Computes  6f(z)/6r,  z = r exp( i f )  *)
	PROCEDURE SolveCplxAbs*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 3;  
		hOpt := NbrCplx.Abs( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.SetPolar( h, zero, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + ch ); 
			result := (result - f( atZ )) / ch
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := (result - f( atZ - ch )) / ch
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := (result - f( atZ - ch )) / (2 * ch)
		END;  
		RETURN result
	END SolveCplxAbs;  

	(** Computes  6f(z)/6f,  z = r exp( i f )  *)
	PROCEDURE SolveCplxArg*( f: CalcFn.CplxArg;  atZ: NbrCplx.Complex;  differencing: NbrInt.Integer ): NbrCplx.Complex;  
	VAR h, hOpt, hMin, power: NbrRe.Real;  ch, result, temp: NbrCplx.Complex;  
	BEGIN   
		(*  Select an optimum step size. *)
		power := 4 / 5;  hMin := MathRe.Power( NbrRe.Epsilon, power );  power := 1 / 3;  
		hOpt := NbrCplx.Arg( atZ ) * MathRe.Power( epsilon, power );  h := NbrRe.Max( hOpt, hMin );  
		NbrCplx.SetPolar( zero, h, ch );  
		(* Refine h so that  z + ch and z differ by an exactly representable number in memory. *)
		temp := atZ + ch;  DoCplxNothing( temp );  ch := temp - atZ;  
		(* Compute an approximate value for the derivative. *)
		IF differencing = Forward THEN 
			result := f( atZ + ch ); 
			result := (result - f( atZ )) / ch
		ELSIF differencing = Backward THEN 
			result := f( atZ ); 
			result := (result - f( atZ - ch )) / ch
		ELSE  (* differencing = Central *)
			result := f( atZ + ch ); 
			result := (result - f( atZ - ch )) / (2 * ch)
		END;  
		RETURN result
	END SolveCplxArg;  

BEGIN 
	epsilon := 100 * NbrRe.Epsilon;  zero := 0
END CalcD1.