(* CAPO - Computational Analysis Platform for Oberon - by Alan Freed and Felix Friedrich. *)
(* Version 1, Update 0 *)

MODULE NbrInt;   (** AUTHOR "adf"; PURPOSE "Defines a base Integer type for scientific computing."; *)

IMPORT AosIO, NbrInt8, NbrInt16, NbrInt32;  

(** This module hides the type size of the integer implemented.  This makes it a straightforward process for 
	the user to change this one module, and in doing so, change the type size for all integers without having 
	to change any modules that import NbrInt, at least in principle.  That was one of our design goals. *)

TYPE 
	Integer* = NbrInt32.Integer;  

VAR 
	MinNbr-, MaxNbr-: Integer;

(** Basic Functions*)
	PROCEDURE Abs*( i: Integer ): Integer;	(** Except for Abs( MinNbr ) = MinNbr, because -MinNbr is out of range. *)
	BEGIN
		RETURN NbrInt32.Abs( i )	
	END Abs;  

	PROCEDURE Dec*( VAR i: Integer );	(** Except for Dec( MinNbr ), because MinNbr-1 is out of range. *)
	BEGIN  
		NbrInt32.Dec( i )
	END Dec;  

	PROCEDURE Inc*( VAR i: Integer );	(** Except for Inc( MaxNbr ), because MaxNbr+1 is out of range. *)
	BEGIN 
		NbrInt32.Inc( i )
	END Inc;  

	PROCEDURE Odd*( i: Integer ): BOOLEAN;  
	BEGIN 
		RETURN NbrInt32.Odd( i )
	END Odd;
	
	PROCEDURE Max*( x1, x2: Integer ): Integer;  
	BEGIN 
		RETURN NbrInt32.Max( x1, x2 ) 
	END Max;  

	PROCEDURE Min*( x1, x2: Integer ): Integer;  
	BEGIN 
		RETURN NbrInt32.Min( x1, x2 ) 
	END Min;  

	PROCEDURE Sign*( x: Integer ): Integer; 
	VAR sign: NbrInt8.Integer; 
	BEGIN 
		sign := NbrInt32.Sign( x );
		RETURN NbrInt32.Long( NbrInt16.Long( sign ) )
	END Sign;  

(** String conversions.  LEN(string) >= 15 *)
	PROCEDURE StringToInt*( string: ARRAY OF CHAR;  VAR x: Integer );   
	BEGIN 
		NbrInt32.StringToInt( string, x ) 
	END StringToInt;  

	PROCEDURE IntToString*( x: Integer;  VAR string: ARRAY OF CHAR );    
	BEGIN 
		NbrInt32.IntToString( x, string ) 
	END IntToString;  

(** Persistence: file IO *)
	PROCEDURE Load*( R: AosIO.Reader;  VAR x: Integer );    
	BEGIN 
		NbrInt32.Load( R, x )
	END Load;  

	PROCEDURE Store*( W: AosIO.Writer;  x: Integer );    
	BEGIN 
		NbrInt32.Store( W, x )
	END Store;  

BEGIN 
	MinNbr := NbrInt32.MinNbr;  MaxNbr := NbrInt32.MaxNbr
END NbrInt.