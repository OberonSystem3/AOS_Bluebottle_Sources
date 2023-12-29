(* CAPO - Computational Analysis Platform for Oberon - by Alan Freed and Felix Friedrich. *)
(* Version 1, Update 0 *)

MODULE MathGamma;   (** AUTHOR "adf"; PURPOSE "Euler's gamma function:  G(x) =  x0% tx-1 exp(-t) dt  when  x > 0." *)

(* Ref:  J.F. Hart, E.W. Cheney, C.L. Lawson, H.J. Maehly, C.K. Mesztenyi, J.R. Rice, H.G. Thacher, Jr., and C. Witzgall, 
		"Computer Approximations," in: The SIAM Series in Applied MathLematics, Wiley, New York, 1968. *)

IMPORT NbrInt, NbrRe, DataErrors, MathRe, MathReSeries;  

VAR 
	maxIterations, Max-: NbrInt.Integer;  lnSqrt2Pi: NbrRe.Real;  
	(* Whenever NbrRe.Real is a 32-bit real, define the following arrays. *)
	gammaP1, gammaQ1: ARRAY 2 OF NbrRe.Real;  
	gammaP, gammaQ: ARRAY 5 OF NbrRe.Real;  
	(* Or whenever NbrRe.Real is a 64-bit real, define the following arrays. *)
	(*  gammaP1, gammaQ1: ARRAY 3 OF NbrRe.Real;  
	gammaP, gammaQ: ARRAY 7 OF NbrRe.Real;  *)

	PROCEDURE Fn*( x: NbrRe.Real ): NbrRe.Real; 
	VAR i, int, offset: NbrInt.Integer;  gamma, lnGamma, phi, prod, sin: NbrRe.Real;   
	BEGIN 
		(* Range reduction. *)
		offset := 2;  int := NbrRe.Int( x );   (* returns int <= x < int+1 for all x *)
		IF (x = int) & (x > 0) THEN NbrInt.Dec( int ) END;   (* sets int < x <= int+1 for x > 0 *)
		IF int > Max THEN DataErrors.ReError( x, "Arguement is too large. " );  gamma := NbrRe.MaxNbr 
		END;  
		(* Calculate the appropriate gamma funtion approximation. *)
		IF int >= 8 THEN  (* x > 8, LGAM constants. *)  
			phi := MathReSeries.TruncatedRationalFunction( gammaP1, gammaQ1, 1/(x*x) ) / x;
			(* Stirling's asymptotic formula. *)
			lnGamma := (x - 0.5) * MathRe.Ln( x ) - x + lnSqrt2Pi + phi;  gamma := MathRe.Exp( lnGamma )
		ELSIF int > offset THEN  (* x > 3, GAMMA constants. *)
			gamma := MathReSeries.TruncatedRationalFunction( gammaP, gammaQ, x - int );  i := offset;  
			WHILE i < int DO gamma := (x - int + i) * gamma;  NbrInt.Inc( i ) END 
		ELSIF int = offset THEN  (* x > 2, GAMMA constants. *)
			gamma := MathReSeries.TruncatedRationalFunction( gammaP, gammaQ, x - offset )
		ELSIF int >= -8 THEN  (* x >= -8, GAMMA constants. *)
			gamma := MathReSeries.TruncatedRationalFunction( gammaP, gammaQ, x - int );  prod := 1;  i := -offset;  
			WHILE i < -int DO NbrInt.Inc( i );  prod := (x - int - i) * prod END;  
			IF prod = 0 THEN  (* At a pole. *)
				DataErrors.ReError( x, "At a pole - division by zero. " );  gamma := NbrRe.MaxNbr
			END;  
			gamma := gamma / prod
		ELSE  (* x < -8, LGAM constants. *)
			sin := MathRe.Sin( NbrRe.Pi * x );  
			IF sin = 0 THEN  (* At a pole. *)
				DataErrors.ReError( x, "At a pole - division by zero. " );  gamma := NbrRe.MaxNbr
			ELSIF -int < Max THEN  (* Gamma(ABS(x)) *) 
				phi := -MathReSeries.TruncatedRationalFunction( gammaP1, gammaQ1, 1/(x*x) ) / x;  
				(* Stirling's asymptotic formula. *)
				lnGamma := -(x + 0.5) * MathRe.Ln( -x ) + x + lnSqrt2Pi + phi;  gamma := MathRe.Exp( lnGamma );  
				(* Reflection formula. *)
				gamma := -NbrRe.Pi / (x * sin * gamma)
			ELSE gamma := 0
			END 
		END;  
		RETURN gamma
	END Fn; 

(* 
	PROCEDURE CplxFn*( z: NbrCplx.Complex ): NbrCplx.Complex; 
	VAR 
	BEGIN 
	END CplxFn; 
*)


BEGIN 
	maxIterations := 1000;  Max := MathRe.MaxFactorial + 1;  lnSqrt2Pi := MathRe.Ln( 2*NbrRe.Pi ) / 2;  
	(* Whenever NbrRe.Real is a 32-bit real, use the following eonstants. *)
	(* Constants from Table GAMMA 5230 from "Computer Approximations". *)
	gammaP[0] := -1.956928025E2;  gammaP[1] := -6.646644488E1;  gammaP[2] := -3.683093638E1;  
	gammaP[3] := -5.100460567;  gammaP[4] := -1.850729036;  
	gammaQ[0] := -1.956928025E2;  gammaQ[1] := 1.626940306E1;  gammaQ[2] := 3.688489696E1;  
	gammaQ[3] := -1.143218422E1;  gammaQ[4] := 1.0;  
	(* Constants from Table LGAM 5440 from "Computer Approximations". *)
	gammaP1[0] := 2.953078438E-1;  gammaP1[1] := 7.349000574E-2;  
	gammaQ1[0] := 3.543694132;  gammaQ1[1] := 1.0
	(* Or, whenever NbrRe.Real is a 64-bit real, use the following eonstants. *)
	(*  (* Constants from Table GAMMA 5239 from "Computer Approximations". *)
	gammaP[0] := 3.78601050348257245475108D3;  gamma64P[1] := 2.07745979389418732098416D3;  
	gammaP[2] := 8.9358180452374981423868D2;  gammaP[3] := 2.221123961680117948396D2;  
	gammaP[4] := 4.895434622790993805232D1;  gammaP[5] := 6.12606745033608429879D0;  
	gammaP[6] := 0.778079585613300575867D0;  gammaQ[0] := 3.78601050348257187258861D3;  
	gammaQ[1] := 4.7679386050368791516095D2;  gammaQ[2] := -8.6723098753110299445707D2;  
	gammaQ[3] := 8.355005866791976957459D1;  gammaQ[4] := 5.078847532889540973716D1;  
	gammaQ[5] := -1.340041478578134826274D1;  gammaQ[6] := 1.0D0;  
	(* Constants from Table LGAM 5443 from "Computer Approximations". *)
	gammaP1[0] := 0.28811928393554601533D0;  gammaP1[1] := 0.498030766924499634D0;  
	gammaP1[2] := 0.691561607375687D-1;  gammaQ1[0] := 3.4574314072267450698D0;  
	gammaQ1[1] := 6.09161691641660296D0;  gammaQ1[2] := 1.0D0  *)

END MathGamma.