(* CAPO - Computational Analysis Platform for Oberon - by Alan Freed and Felix Friedrich. *)
(* Version 1, Update 0 *)

MODULE CalcFn;   (** AUTHOR "adf"; PURPOSE "Defines procedure types used in the suite of Calc modules"; *)

IMPORT NbrRe, NbrCplx;  

(** Functions that can appear as arguments of integration or differentiation are of the following types. *)
TYPE 
	ReArg* = PROCEDURE ( x: NbrRe.Real ): NbrRe.Real;  
	
	Re2Arg* = PROCEDURE ( x1, x2: NbrRe.Real ): NbrRe.Real;  
	
	CplxArg* = PROCEDURE ( z: NbrCplx.Complex ): NbrCplx.Complex;  
	
	Cplx2Arg* = PROCEDURE ( z1, z2: NbrCplx.Complex ): NbrCplx.Complex;  
	
	MixedArg* = PROCEDURE ( x: NbrRe.Real;  z: NbrCplx.Complex ): NbrCplx.Complex;  

BEGIN 
END CalcFn.
