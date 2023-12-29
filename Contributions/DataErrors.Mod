(* CAPO - Computational Analysis Platform for Oberon - by Alan Freed and Felix Friedrich. *)
(* Version 1, Update 0 *)

MODULE DataErrors;   (** AUTHOR "adf, fof"; PURPOSE "For reporting runtime warnings & errors into file Error.Log"; *)

(**  Error.Log is an error log file that can be viewed with any ASCII editor, and is overwritten with each session. 
	If no errors or warnings were logged, the file will be empty.  File Error.Log is automatically opened/closed whenever 
	module DataErrors.Mod is loaded-into/freed-from the system.  The Error.Log file from the previous session is saved in 
	file Error.Log.Bak. 
	
	Logging the first error or warning message of a session produces an audible SOS beep to inform the user to check this file. 
	
	Errors are for catostropic events, e.g., division by zero. 
	Warnings are for non-optimal events, e.g., a series did not converge. *)

IMPORT SYSTEM, AosKernel, AosModules, AosFS, AosBeep, NbrInt, NbrRat, NbrRe, NbrCplx;  

VAR 
	beeped: BOOLEAN;  F: AosFS.File;  W: AosFS.Writer;  

	PROCEDURE Beep;  
	VAR i: NbrInt.Integer;  timer: AosKernel.Timer;  
	BEGIN 
		NEW( timer );  
		FOR i := 1 TO 3 DO AosBeep.Beep( 125 );  timer.Sleep( 100 );  AosBeep.Beep( 0 );  timer.Sleep( 100 ) END;  
		FOR i := 1 TO 3 DO AosBeep.Beep( 100 );  timer.Sleep( 350 );  AosBeep.Beep( 0 );  timer.Sleep( 150 ) END;  
		FOR i := 1 TO 3 DO AosBeep.Beep( 125 );  timer.Sleep( 100 );  AosBeep.Beep( 0 );  timer.Sleep( 100 ) END 
	END Beep;  

(* From antsPortability *)
	PROCEDURE IdentifyCaller( VAR m: AosModules.Module;  VAR pc: NbrInt.Integer );  
	VAR ebp, eip, reg: NbrInt.Integer;  
	BEGIN 
		IF ~beeped THEN beeped := TRUE;  Beep END;  
		SYSTEM.GETREG( SYSTEM.EBP, reg );  
		SYSTEM.GET( reg, ebp );   (* stack frame of caller *)
		SYSTEM.GET( ebp + 4, eip );   (* return address from caller *)
		m := AosModules.ThisModuleByAdr( eip );  
		IF m # NIL THEN pc := eip - SYSTEM.ADR( m.code[0] ) ELSE pc := MAX( LONGINT ) END 
	END IdentifyCaller;  

(* From AosTrap *)
	PROCEDURE GetNum( refs: AosModules.Bytes;  VAR i, num: NbrInt.Integer );  
	VAR n, s: NbrInt.Integer;  x: CHAR;  
	BEGIN 
		s := 0;  n := 0;  x := refs[i];  NbrInt.Inc( i );  
		WHILE ORD( x ) >= 128 DO 
			INC( n, ASH( ORD( x ) - 128, s ) );  INC( s, 7 );  x := refs[i];  NbrInt.Inc( i ) 
		END;  
		num := n + ASH( ORD( x ) MOD 64 - 64 * (ORD( x ) DIV 64), s )
	END GetNum;  

(* From AosTrap *)
	PROCEDURE FindProc( refs: AosModules.Bytes;  modpc: NbrInt.Integer ): NbrInt.Integer;  
	VAR i, m, t, proc: NbrInt.Integer;  ch: CHAR;  
	BEGIN 
		proc := -1;  i := 0;  m := LEN( refs^ );  ch := refs[i];  NbrInt.Inc( i );  
		WHILE (i < m) & ((ch = 0F8X) OR (ch = 0F9X)) DO  (* proc *)
			GetNum( refs, i, t );   (* pofs *)
			IF t > modpc THEN  (* previous procedure was the one *)
				ch := 0X (* stop search *)
			ELSE  (* ~found *)
				IF ch = 0F9X THEN 
					GetNum( refs, i, t );   (* nofPars *)
					INC( i, 3 ) (* RetType, procLev, slFlag *)
				END;  
				proc := i;   (* remember this position, just before the name *)
				REPEAT ch := refs[i];  NbrInt.Inc( i ) UNTIL ch = 0X;   (* pname *)
				IF i < m THEN 
					ch := refs[i];  NbrInt.Inc( i );  
					(* 1X | 3X | 0F8X | 0F9X *)
					WHILE (i < m) & (ch >= 1X) & (ch <= 3X) DO  (* var *)
						ch := refs[i];  NbrInt.Inc( i );   (* type *)
						IF (ch >= 81X) OR (ch = 16X) OR (ch = 1DX) THEN 
							GetNum( refs, i, t ) (* dim/tdadr *)
						END;  
						GetNum( refs, i, t );   (* vofs *)
						REPEAT ch := refs[i];  NbrInt.Inc( i ) UNTIL ch = 0X;   (* vname *)
						IF i < m THEN ch := refs[i];  NbrInt.Inc( i ) END 
					END  (* 1X | 3X | 0F8X | 0F9X *)
				END 
			END 
		END;  
		IF (proc = -1) & (i # 0) THEN proc := i END;   (* first procedure *)
		RETURN proc
	END FindProc;  

	PROCEDURE IdentifyProcedure( VAR m: AosModules.Module;  pc: NbrInt.Integer;  VAR module, type, proc: ARRAY OF CHAR );  
	VAR refs: AosModules.Bytes;  refpos, i: NbrInt.Integer;  ch: CHAR;  
	BEGIN 
		module[0] := 0X;  type[0] := 0X;  proc[0] := 0X;  
		IF m = NIL THEN 
			IF pc = 0 THEN COPY( "NIL", proc ) ELSE COPY( "unknown pointer", proc ) END 
		ELSE 
			COPY( m.name, module );  refs := m.refs;  refpos := FindProc( refs, pc );  
			IF refpos # -1 THEN 
				ch := refs[refpos];  NbrInt.Inc( refpos );  i := 0;  
				WHILE (ch # 0X) DO 
					proc[i] := ch;  ch := refs[refpos];  NbrInt.Inc( refpos );  NbrInt.Inc( i );  
					IF ch = "." THEN ch := refs[refpos];  NbrInt.Inc( refpos );  proc[i] := 0X;  COPY( proc, type );  i := 0 END 
				END;  
				proc[i] := 0X
			ELSE COPY( "unknown", proc )
			END 
		END 
	END IdentifyProcedure;  

	PROCEDURE Location( module, type, proc: ARRAY OF CHAR );  
	BEGIN 
		IF module[0] # 0X THEN W.String( "   module: " );  W.String( module );  W.Ln END;  
		IF type[0] # 0X THEN 
			W.String( "      type: " );  W.String( type );  W.Ln;  
			IF proc[0] # 0X THEN W.String( "         method: " );  W.String( proc );  W.Ln END 
		ELSE 
			IF proc[0] # 0X THEN W.String( "      procedure: " );  W.String( proc );  W.Ln END 
		END 
	END Location;  

(** Log an error message to file Error.Log. *)
	PROCEDURE Error*( message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "An error of:" );  W.Ln;  
			W.String( "   " );  W.String( message );  W.Ln;  W.String( "occurred in:" );  W.Ln;  
			Location( module, type, proc );  W.Ln;  W.Update
		END 
	END Error;  

(** Log an error message to file Error.Log when an error arises from a passed parameter whose value was int. *)
	PROCEDURE IntError*( int: NbrInt.Integer;  message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc, string: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "An ERROR occurred in:" );  
			W.Ln;  Location( module, type, proc );  W.String( "The argument passed that caused this error was: " );  W.Ln;  
			W.String( "   " );  NbrInt.IntToString( int, string );  W.String( string );  W.Ln;  
			W.String( "resulting in the following error message:" );  W.Ln;  W.String( "   " );  W.String( message );  W.Ln;  
			W.Ln;  W.Update
		END 
	END IntError;  

(** Log an error message to file Error.Log when an error arises from a passed parameter whose value was rat. *)
	PROCEDURE RatError*( rat: NbrRat.Rational;  message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc, string: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "An ERROR occurred in:" );  
			W.Ln;  Location( module, type, proc );  W.String( "The argument passed that caused this error was: " );  W.Ln;  
			W.String( "   " );  NbrRat.RatToString( rat, string );  W.String( string );  W.Ln;  
			W.String( "resulting in the following error message:" );  W.Ln;  W.String( "   " );  W.String( message );  W.Ln;  
			W.Ln;  W.Update
		END 
	END RatError;  

(** Log an error message to file Error.Log when an error arises from a passed parameter whose value was re. *)
	PROCEDURE ReError*( re: NbrRe.Real;  message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc, string: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "An ERROR occurred in:" );  
			W.Ln;  Location( module, type, proc );  W.String( "The argument passed that caused this error was: " );  W.Ln;  
			W.String( "   " );  NbrRe.ReToString( re, 15, string );  W.String( string );  W.Ln;  
			W.String( "resulting in the following error message:" );  W.Ln;  W.String( "   " );  W.String( message );  W.Ln;  
			W.Ln;  W.Update
		END 
	END ReError;  

(** Log an error message to file Error.Log when an error arises from a passed parameter whose value was cplx. *)
	PROCEDURE CplxError*( cplx: NbrCplx.Complex;  message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc, string: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "An ERROR occurred in:" );  
			W.Ln;  Location( module, type, proc );  W.String( "The argument passed that caused this error was: " );  W.Ln;  
			W.String( "   " );  NbrCplx.CplxToPolarString( cplx, 15, string );  W.String( string );  W.Ln;  
			W.String( "resulting in the following error message:" );  W.Ln;  W.String( "   " );  W.String( message );  W.Ln;  
			W.Ln;  W.Update
		END 
	END CplxError;  

(** Log a warning message to file Error.Log. *)
	PROCEDURE Warning*( message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "A WARNING of:" );  W.Ln;  
			W.String( "   " );  W.String( message );  W.Ln;  W.String( "occurred in:" );  W.Ln;  
			Location( module, type, proc );  W.Ln;  W.Update
		END 
	END Warning;  

(** Log a warning message to file Error.Log when a warning arises from a passed parameter whose value was int. *)
	PROCEDURE IntWarning*( int: NbrInt.Integer;  message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc, string: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "A WARNING occurred in:" );  
			W.Ln;  Location( module, type, proc );  W.String( "The argument passed that caused this warning was: " );  W.Ln;  
			W.String( "   " );  NbrInt.IntToString( int, string );  W.String( string );  W.Ln;  
			W.String( "resulting in the following error message:" );  W.Ln;  W.String( "   " );  W.String( message );  W.Ln;  
			W.Ln;  W.Update
		END 
	END IntWarning;  

(** Log a warning message to file Error.Log when a warning arises from a passed parameter whose value was rat. *)
	PROCEDURE RatWarning*( rat: NbrRat.Rational;  message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc, string: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "A WARNING occurred in:" );  
			W.Ln;  Location( module, type, proc );  W.String( "The argument passed that caused this warning was: " );  W.Ln;  
			W.String( "   " );  NbrRat.RatToString( rat, string );  W.String( string );  W.Ln;  
			W.String( "resulting in the following error message:" );  W.Ln;  W.String( "   " );  W.String( message );  W.Ln;  
			W.Ln;  W.Update
		END 
	END RatWarning;  

(** Log a warning message to file Error.Log when a warning arises from a passed parameter whose value was re. *)
	PROCEDURE ReWarning*( re: NbrRe.Real;  message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc, string: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "A WARNING occurred in:" );  
			W.Ln;  Location( module, type, proc );  W.String( "The argument passed that caused this warning was: " );  W.Ln;  
			W.String( "   " );  NbrRe.ReToString( re, 15, string );  W.String( string );  W.Ln;  
			W.String( "resulting in the following error message:" );  W.Ln;  W.String( "   " );  W.String( message );  W.Ln;  
			W.Ln;  W.Update
		END 
	END ReWarning;  

(** Log a warning message to file Error.Log when a warning arises from a passed parameter whose value was cplx. *)
	PROCEDURE CplxWarning*( cplx: NbrCplx.Complex;  message: ARRAY OF CHAR );  
	VAR m: AosModules.Module;  pc: NbrInt.Integer;  
		module, type, proc, string: ARRAY 64 OF CHAR;  
	BEGIN {EXCLUSIVE}
		IF W # NIL THEN 
			IdentifyCaller( m, pc );  IdentifyProcedure( m, pc, module, type, proc );  W.String( "A WARNING occurred in:" );  
			W.Ln;  Location( module, type, proc );  W.String( "The argument passed that caused this warning was: " );  W.Ln;  
			W.String( "   " );  NbrCplx.CplxToPolarString( cplx, 15, string );  W.String( string );  W.Ln;  
			W.String( "resulting in the following error message:" );  W.Ln;  W.String( "   " );  W.String( message );  W.Ln;  
			W.Ln;  W.Update
		END 
	END CplxWarning;  

(** Opens the file Error.Log, saving the prior log file to Error.Log.Bak.  
		Error.Log is automatically opened whenever this module is loaded into memory, 
		and it only needs to be reopened manually if you had previously closed it manually. *)
	PROCEDURE Open*;  
	VAR ignor: NbrInt.Integer;  backup, fileName: AosFS.FileName;  
	BEGIN 
		beeped := FALSE;  
		COPY( "Error.Log", fileName );  COPY( "Error.Log.Bak", backup );  AosFS.Delete( backup, ignor );  
		AosFS.Rename( fileName, backup, ignor );  F := AosFS.New( fileName );  AosFS.OpenWriter( W, F, 0 )
	END Open;  

(** Closes the file Error.Log.  
		Error.Log is automatically closed whenever this module is garbage collected.  
		Executing Close forces the file to close immediately. *)
	PROCEDURE Close*;  
	BEGIN 
		IF F # NIL THEN AosFS.Register( F );  W := NIL;  F := NIL END 
	END Close;  

BEGIN 
	Open;  AosModules.InstallTermHandler( Close )
END DataErrors. 

EditTools.OpenAscii  Error.Log ~ 
EditTools.OpenAscii  Error.Log.Bak ~ 
		