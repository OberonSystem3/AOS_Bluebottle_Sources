(* CAPO - Computational Analysis Platform for Oberon - by Alan Freed and Felix Friedrich. *)
(* Version 1, Update 0 *)

MODULE MathCplx;   (** AUTHOR "adf"; PURPOSE "Complex math functions"; *)

(*	Refs: M. Abramowitz and I. A. Stegun, Handbook of Mathematical Functions with Formulas, Graphs, and Mathematical 
				Tables, National Bureau of Standards, Applied Mathematics Series, Vol. 55, 1964.
			R. V. Churchill, J. W. Brown and R. F. Verhey, Complex Variables and Applications, 3rd ed., McGraw-Hill, 1974.
			P. Midy and Y. Yakovlev, Mathematics and Computers in Simulation, Vol. 33, 1991, 33-49. *)

IMPORT NbrInt, NbrRe, NbrCplx, DataErrors, MathRe;  

VAR 
	ln2, ln2Inv, ln10, ln10Inv: NbrRe.Real;  
	
	(** Returns a pseudo-random number  z = r exp(if)  uniformly distributed over the unit circle,  r N (0,1),  f N (-p,p)). *)
	PROCEDURE Random*( ): NbrCplx.Complex;  
	VAR abs, arg: NbrRe.Real;  z: NbrCplx.Complex;  
	BEGIN 
		abs := MathRe.Sqrt( MathRe.Random() );  arg := NbrRe.Pi * (2 * MathRe.Random() - 1);  
		NbrCplx.Set( abs, arg, z );  RETURN z
	END Random;  

(** Power Functions *)
	PROCEDURE Sqrt*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR abs, arg, im, re: NbrRe.Real;  sqrt: NbrCplx.Complex;  
	BEGIN 
		im := NbrCplx.Im( z );  
		IF im = 0 THEN 
			re := NbrCplx.Re( z );  
			(* Handle the branch cut along the negative real axis. *)
			IF re < 0 THEN NbrCplx.Set( 0, MathRe.Sqrt( -re ), sqrt )
			ELSIF re = 0 THEN sqrt := 0
			ELSE NbrCplx.Set( MathRe.Sqrt( re ), 0, sqrt )
			END 
		ELSE abs := NbrCplx.Abs( z );  arg := NbrCplx.Arg( z );  NbrCplx.SetPolar( MathRe.Sqrt( abs ), arg / 2, sqrt )
		END;  
		RETURN sqrt
	END Sqrt;  

	PROCEDURE IntPower*( z: NbrCplx.Complex;  n: NbrInt.Integer ): NbrCplx.Complex;  
	VAR abs, arg: NbrRe.Real;  power: NbrCplx.Complex;  
	BEGIN 
		IF n = 0 THEN 
			IF z # 0 THEN power := 1 ELSE DataErrors.Error( "Both argument and exponent cannot be zero." );  power := 0 END 
		ELSIF z = 0 THEN 
			IF n > 0 THEN power := 0 
			ELSE DataErrors.IntError( n, "Exponent cannot be negative when argument is zero." );  power := 0
			END 
		ELSE 
			abs := MathRe.IntPower( NbrCplx.Abs( z ), n );  arg := n * NbrCplx.Arg( z );  
			NbrCplx.SetPolar( abs, arg, power )
		END;  
		RETURN power
	END IntPower;  

	PROCEDURE LnMod( z: NbrCplx.Complex ): NbrRe.Real;  
	(* Algorithm of Midy and Yakovlev. *)
	VAR r, r2, im, im2, lower, upper, result: NbrRe.Real;  
	BEGIN 
		lower := 0.82;  upper := 1.22;  r := NbrRe.Abs( NbrCplx.Re( z ) );  r2 := r * r;  
		im := NbrRe.Abs( NbrCplx.Im( z ) );  im2 := im * im;  
		IF r > im THEN 
			IF (2 * im2 < r2) & (lower < r) & (r < upper) THEN 
				result := MathRe.Ln( r ) + MathRe.ArcTanh( im2 / (2 * r2 + im2) )
			ELSE result := MathRe.Ln( r2 + im2 ) / 2
			END 
		ELSE 
			IF (2 * r2 < im2) & (lower < im) & (im < upper) THEN 
				result := MathRe.Ln( im ) + MathRe.ArcTanh( r2 / (2 * im2 + r2) )
			ELSE result := MathRe.Ln( r2 + im2 ) / 2
			END 
		END;  
		RETURN result
	END LnMod;  

	PROCEDURE RealPower*( z: NbrCplx.Complex;  x: NbrRe.Real ): NbrCplx.Complex;  
	VAR abs, arg: NbrRe.Real;  power: NbrCplx.Complex;  
	BEGIN 
		abs := NbrCplx.Abs( z );  
		IF x = 0 THEN 
			IF abs > 0 THEN power := 1 ELSE DataErrors.Error( "Both argument and exponent cannot be zero." );  power := 0 END 
		ELSIF abs = 0 THEN 
			IF x > 0 THEN power := 0 
			ELSE DataErrors.ReError( x, "Exponent cannot be negative when argument is zero." );  power := 0
			END 
		ELSE abs := MathRe.Exp( x * LnMod( z ) );  arg := x * NbrCplx.Arg( z );  NbrCplx.SetPolar( abs, arg, power )
		END;  
		RETURN power
	END RealPower;  

	PROCEDURE Power*( zc, ze: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR abs, absC, absE, arg, im, lnRho, phi, re: NbrRe.Real;  power: NbrCplx.Complex;  
		(* Formula listed in Midy and Yakovlev. *)
	BEGIN 
		absC := NbrCplx.Abs( zc );  absE := NbrCplx.Abs( ze );  
		IF absE = 0 THEN 
			IF absC > 0 THEN power := 1 
			ELSE DataErrors.Error( "Both argument and exponent cannot be zero." );  power := 0
			END 
		ELSIF absC = 0 THEN power := 0
		ELSE 
			re := NbrCplx.Re( ze );  im := NbrCplx.Im( ze );  lnRho := LnMod( zc );  phi := NbrCplx.Arg( zc );  
			abs := MathRe.Exp( lnRho * re - phi * im );  arg := lnRho * im + phi * re;  NbrCplx.SetPolar( abs, arg, power )
		END;  
		RETURN power
	END Power;  
	
	(** Logarithmic Functions *)
(** Exp(z) = Exp(z 1 2pi), i.e., it is periodic with imaginary period  2pi. *)
	PROCEDURE Exp*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR coef, re, real, im, imag: NbrRe.Real;  exp: NbrCplx.Complex;  
	BEGIN 
		(* Euler's formula *)
		re := NbrCplx.Re( z );  im := NbrCplx.Im( z );  coef := MathRe.Exp( re );  real := coef * MathRe.Cos( im );  
		imag := coef * MathRe.Sin( im );  NbrCplx.Set( real, imag, exp );  RETURN exp
	END Exp;  

	PROCEDURE Exp2*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	BEGIN 
		RETURN Exp( ln2 * z )
	END Exp2;  

	PROCEDURE Exp10*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	BEGIN 
		RETURN Exp( ln10 * z )
	END Exp10;  

(** Ln(z) returns its principal value where Im(Ln(z)) N [-p, p]. *)
	PROCEDURE Ln*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR re, im: NbrRe.Real;  ln: NbrCplx.Complex;  
	BEGIN 
		re := LnMod( z );  im := NbrCplx.Arg( z );  NbrCplx.Set( re, im, ln );  RETURN ln
	END Ln;  

	PROCEDURE Log2*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR log: NbrCplx.Complex;  
	BEGIN 
		log := ln2Inv * Ln( z );  RETURN log
	END Log2;  

	PROCEDURE Log*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR log: NbrCplx.Complex;  
	BEGIN 
		log := ln10Inv * Ln( z );  RETURN log
	END Log;  
	
	(* Using the Exp and Ln functions from above to define all functions below
		implies that they will return principal value(s) in their periodic component(s). *)
	
(** Trigonometric Functions *)
	PROCEDURE Sin*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR sin: NbrCplx.Complex;  
	BEGIN 
		sin := (Exp( NbrCplx.I * z ) - Exp( -NbrCplx.I * z )) / (2 * NbrCplx.I);  RETURN sin
	END Sin;  

	PROCEDURE Cos*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR cos: NbrCplx.Complex;  
	BEGIN 
		cos := (Exp( NbrCplx.I * z ) + Exp( -NbrCplx.I * z )) / 2;  RETURN cos
	END Cos;  

	PROCEDURE Tan*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	(* Algorithm of Midy and Yakovlev. *)
	VAR d, w, w2, x, x2, y, y2, re, real, im, imag, four, limit: NbrRe.Real;  tan: NbrCplx.Complex;  
	BEGIN 
		limit := 0.65;  re := NbrCplx.Re( z );  im := NbrCplx.Im( z );  x := MathRe.Tan( re );  x2 := x * x;  
		IF NbrRe.Abs( im ) < limit THEN 
			y := MathRe.Tanh( im );  y2 := y * y;  d := 1 + x2 * y2;  real := x * (1 - y2) / d;  imag := y * (1 + x2) / d
		ELSE 
			four := 4;  y := MathRe.Exp( MathRe.Ln( four ) - 2 * NbrRe.Abs( im ) );  w := y / four;  w2 := w * w;  
			d := 1 + 2 * w + w2 + (1 - 2 * w + w2) * x2;  real := x * y / d;  
			imag := NbrRe.Sign( im ) * (1 - w2) * (1 + x2) / d
		END;  
		NbrCplx.Set( real, imag, tan );  RETURN tan
	END Tan;  

	PROCEDURE ArcSin*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR asin: NbrCplx.Complex;  
	BEGIN 
		IF NbrCplx.Im( z ) = 0 THEN asin := MathRe.ArcSin( NbrCplx.Re( z ) ) 
		ELSE asin := -NbrCplx.I * Ln( NbrCplx.I * z + Sqrt( 1 - z * z ) )
		END;  
		RETURN asin
	END ArcSin;  

	PROCEDURE ArcCos*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR acos: NbrCplx.Complex;  
	BEGIN 
		IF NbrCplx.Im( z ) = 0 THEN acos := MathRe.ArcCos( NbrCplx.Re( z ) ) 
		ELSE acos := -NbrCplx.I * Ln( z + NbrCplx.I * Sqrt( 1 - z * z ) )
		END;  
		RETURN acos
	END ArcCos;  

	PROCEDURE ArcTan*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR im: NbrRe.Real;  atan: NbrCplx.Complex;  
	BEGIN 
		IF NbrCplx.Re( z ) = 0 THEN 
			(* Address the branch cuts along the imaginary axis. *)
			im := NbrCplx.Im( z );  
			IF NbrRe.Abs( im ) < 1 THEN atan := NbrCplx.I * (MathRe.Ln( (1 + im) / (1 - im) ) / 2) 
			ELSE DataErrors.CplxError( z, "Argument lies outside the admissible range for this function." );  atan := 0
			END 
		ELSE atan := NbrCplx.I * Ln( (NbrCplx.I + z) / (NbrCplx.I - z) ) / 2
		END;  
		RETURN atan
	END ArcTan;  

(** Hyperbolic functions *)
	PROCEDURE Sinh*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR sinh: NbrCplx.Complex;  
	BEGIN 
		sinh := (Exp( z ) - Exp( -z )) / 2;  RETURN sinh
	END Sinh;  

	PROCEDURE Cosh*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR cosh: NbrCplx.Complex;  
	BEGIN 
		cosh := (Exp( z ) + Exp( -z )) / 2;  RETURN cosh
	END Cosh;  

	PROCEDURE Tanh*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR tanh: NbrCplx.Complex;  
	BEGIN 
		tanh := -NbrCplx.I * Tan( NbrCplx.I * z );  RETURN tanh
	END Tanh;  

	PROCEDURE ArcSinh*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR abs, im: NbrRe.Real;  asinh: NbrCplx.Complex;  
	BEGIN 
		IF NbrCplx.Re( z ) = 0 THEN 
			(* Address the branch cut along the imaginary axis. *)
			im := NbrCplx.Im( z );  abs := NbrRe.Abs( im );  
			IF abs < 1 THEN asinh := Ln( z + MathRe.Sqrt( 1 - im * im ) )
			ELSIF abs = 1 THEN asinh := 0
			ELSE DataErrors.CplxError( z, "Argument lies outside the admissible range for this function." );  asinh := 0
			END 
		ELSE asinh := Ln( z + Sqrt( z * z + 1 ) )
		END;  
		RETURN asinh
	END ArcSinh;  

	PROCEDURE ArcCosh*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR acosh: NbrCplx.Complex;  
	BEGIN 
		IF NbrCplx.Im( z ) = 0 THEN acosh := MathRe.ArcCosh( NbrCplx.Re( z ) ) ELSE acosh := Ln( z + Sqrt( z * z - 1 ) ) END;  
		RETURN acosh
	END ArcCosh;  

	PROCEDURE ArcTanh*( z: NbrCplx.Complex ): NbrCplx.Complex;  
	VAR atanh: NbrCplx.Complex;  
	BEGIN 
		IF NbrCplx.Im( z ) = 0 THEN atanh := MathRe.ArcTanh( NbrCplx.Re( z ) ) ELSE atanh := Ln( (1 + z) / (1 - z) ) / 2 END;  
		RETURN atanh
	END ArcTanh;  

BEGIN 
	ln2 := MathRe.Ln( 2 );  ln2Inv := 1/ln2;  ln10 := MathRe.Ln( 10 );  ln10Inv := 1/ln10
END MathCplx.