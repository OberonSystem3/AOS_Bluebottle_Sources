MODULE AosCryptoPrimes;	(** AUTHOR "G.F."; PURPOSE "Prime Number Library"; *)

(*	2002.9.11	g.f.	based on 'bn_prime.c'
		
		Copyright of the original:     <-- middle click here
*)

IMPORT
	B := AosCryptoBigNumbers,	Out := AosOut;

CONST
	N = 2048;  	
	
TYPE 
	Number = B.BigNumber;
	
VAR 
	one: Number;
	primes: ARRAY N OF LONGINT;

	PROCEDURE NewPrime*( VAR p: Number;  bits: INTEGER;  safe: BOOLEAN );
	VAR checks, i: INTEGER;  t: Number; 
	BEGIN 
		checks := Checks( bits ); i := 1;
		LOOP
			ProbablePrime( p, bits );
			Out.Char( '.' );
			IF IsPrime( p, checks, FALSE ) THEN
				Out.String( "Prime number generated" );
				IF ~safe THEN  Out.Ln;  RETURN 
				ELSE 
					Out.Int( i, 0 );  
					INC( i );
					(* for "safe prime" generation, check that (p-1)/2 is prime. *)
					B.Copy( p, t );  B.Shift( t, -1 );
					IF IsPrime( t, checks, FALSE ) THEN  Out.Ln;  RETURN  END;
					Out.String( " not safe" ); Out.Ln;
				END
			END
		END
	END NewPrime;
	
	PROCEDURE NewDHPrime*( VAR p: Number;  bits: INTEGER;  safe: BOOLEAN;  VAR add, rem: Number );
	VAR checks: INTEGER;  t: Number;
	BEGIN 
		checks := Checks( bits );
		LOOP
			IF safe THEN  ProbableDHPrimeSafe( p, bits, add, rem )
			ELSE ProbableDHPrime( p, bits, add, rem )
			END;
			IF IsPrime( p, checks, FALSE ) THEN
				IF ~safe THEN  RETURN 
				ELSE  (* for "safe prime" generation, check that (p-1)/2 is prime. *)
					B.Copy( p, t );  B.Shift( t, -1 );
					IF IsPrime( t, checks, FALSE ) THEN  RETURN  END
				END
			END
		END
	END NewDHPrime;
	
	PROCEDURE Checks( b: LONGINT ): INTEGER;
	(* number of Miller-Rabin iterations for an error rate  of less than 2^-80
		for random 'b'-bit input, b >= 100 (taken from table 4.4 in the Handbook
		of Applied Cryptography [Menezes, van Oorschot, Vanstone; CRC Press 1996]
	*)
	VAR t: INTEGER;
	BEGIN
		ASSERT( b >= 100 );
		IF b >= 1300 THEN t := 2
		ELSIF b >= 850 THEN t := 3
		ELSIF b >= 650 THEN t := 4
		ELSIF b >= 550 THEN t := 5
		ELSIF b >= 450 THEN t := 6
		ELSIF b >= 400 THEN t := 7
		ELSIF b >= 350 THEN t := 8
		ELSIF b >= 300 THEN t := 9
		ELSIF b >= 250 THEN t := 12
		ELSIF b >= 200 THEN t := 15
		ELSIF b >= 150 THEN t := 18
		ELSE  t := 27
		END;
		RETURN t
	END Checks;

	PROCEDURE Int( VAR a: Number ): LONGINT;
	BEGIN (* BitSize( a ) < 32 *)
		IF a.len = 0 THEN    RETURN  0
		ELSE  RETURN  a.d[0] 
		END
	END Int;
	
	PROCEDURE ProbablePrime( VAR p: Number;  bits: INTEGER );
		VAR d, t, r: Number;  delta, i: LONGINT;
			mods: ARRAY N OF LONGINT;
	BEGIN
		LOOP
			B.NewRand( p, bits, 1, 1 ); 
			FOR i := 0 TO N - 1 DO  mods[i] := B.ModWord( p, primes[i] )  END;
			(* check that p is not a prime and also that gcd( p-1, primes) = 1 (except for 2) *)
			i := 0;  delta := 0;
			LOOP
				INC( i );
				IF i >= N THEN  B.Assign( t, delta );  B.Add( p, t, p );  RETURN  END;
				IF (mods[i] + delta) MOD primes[i] <= 1 THEN  
					INC( delta, 2 );  i := 0; 
					IF delta < 0 THEN  (* overfow! try new random *)  EXIT  END;
				END;
			END 
		END 
	END ProbablePrime;
	
	PROCEDURE ProbableDHPrime( VAR p: Number;  bits: INTEGER;  VAR add, rem: Number );
		VAR d, r: Number;  i: LONGINT;
	BEGIN
		B.NewRand( p, bits, 0, 1 ); 
			
		(* we need (p - rem) mod add = 0 *)
		B.Mod( p, add, r );  B.Sub( p, r, p );
		IF B.Zero( rem ) THEN  B.Inc( p )  ELSE  B.Add( p, rem, p )  END;
		
		(* we now have a random number 'p' to test. *)
		i := 0;  
		LOOP
			INC( i );  IF i >= N THEN  RETURN  END;
			B.Assign( d, primes[i] );  B.Mod( p, d, r ); 
			IF B.Zero( r ) THEN  B.Add( p, add, p );  i := 0  END;
		END 
	END ProbableDHPrime;
	
	PROCEDURE ProbableDHPrimeSafe( VAR p: Number;  bits: INTEGER; VAR padd, rem: Number );
		VAR d, q, r, qr, qadd: Number;  i: LONGINT;
	BEGIN
		B.Copy( padd, qadd );  B.Shift( qadd, -1 );
		B.NewRand( q, bits, 0, 1 ); 
			
		B.Mod( q, qadd, r );  B.Sub( q, r, q );
		IF B.Zero( rem ) THEN  B.Inc( q )  
		ELSE  B.Copy( rem, r );  B.Shift( r, -1 );  B.Add( q, r, q )  
		END;
		
		(* we now have a random number  to test. *)
		B.Copy( q, p );  B.Shift( p, 1 );  B.Inc( p );
		
		i := 0;  
		LOOP
			INC( i );  IF i >= N THEN  RETURN  END;
			B.Assign( d, primes[i] );  B.Mod( p, d, r );  B.Mod( q, d, qr ); 
			IF B.Zero( r ) OR B.Zero( qr ) THEN  
				B.Add( p, padd, p );  B.Add( q, qadd, q );  i := 0
			END;
		END 
	END ProbableDHPrimeSafe;
	
	PROCEDURE IsPrime*( VAR a: Number;  checks: INTEGER;  doTrialDiv: BOOLEAN ): BOOLEAN;
		VAR i, k: INTEGER;  q, r, A, A1, A1odd, check: Number;
	BEGIN 
		IF checks = 0 THEN  checks := Checks( B.BitSize( a ) )  END;
		IF ~ODD( a.d[0] ) THEN  RETURN FALSE  END;
		IF doTrialDiv THEN 
			FOR i := 1 TO N - 1 DO 
				IF B.ModWord( a, primes[i] ) = 0 THEN  RETURN FALSE  END
			END
		END;
		B.Copy( a, A );
		IF A.neg THEN  B.Neg( A )  END;
		B.Copy( A, A1 );  B.Dec( A1 );
		IF B.Zero( A1 ) THEN  RETURN FALSE  END;
		
		(* write  A1  as  A1odd * 2^k *)
		k := 1;  WHILE ~B.BitSet( A1, k ) DO  INC( k )  END;
		B.Copy( A1, A1odd );  B.Shift( A1odd, -k );
		
		FOR i := 1 TO checks DO 
			B.NewRand( check,  B.BitSize( A1 ), 0, 0 );
			IF B.Cmp( check, A1 ) >= 0 THEN  B.Sub( check, A1, check )  END;
			B.Inc( check );
			(* now 1 <= check < A *)
			IF ~witness( check, A, A1, A1odd, k ) THEN  RETURN FALSE  END
		END;
		RETURN TRUE
	END IsPrime;
	
	PROCEDURE witness( VAR w, a, a1, a1odd: Number;  k: INTEGER): BOOLEAN;
	BEGIN 
		w := B.ModExp( w, a1odd, a );
		IF B.Cmp( w, one ) = 0 THEN  (* probably prime *)  RETURN TRUE  END;
		IF B.Cmp( w, a1 ) = 0 THEN   RETURN TRUE  END;
				(* w = -1 (mod a), a is probably prime *) 
		WHILE k > 0 DO 
			B.ModMul( w, w, a, w );  (* w = w^2 mod a *)
			IF B.Cmp( w, one ) = 0 THEN  RETURN FALSE  END;
					(* a is composite, otherwise a previous w would  have been = -1 (mod a) *)
			IF B.Cmp( w, a1 ) = 0 THEN  RETURN TRUE  END;
					(* w = -1 (mod a), a is probably prime *)  
			DEC( k )
		END;
		(* If we get here, w is the (a-1)/2-th power of the original w,
			and it is neither -1 nor +1 -- so a cannot be prime *)
		RETURN FALSE
	END witness;	
	
	PROCEDURE Init;
		VAR sieve: ARRAY N OF SET; i, j, p, n: LONGINT;
	BEGIN 
		(* compute the first N small primes *)
		FOR i := 0 TO N - 1 DO sieve[i] := {0..31} END;
		primes[0] := 2;  n := 1;  i := 1; 
		WHILE n < N DO
			IF i MOD 32 IN sieve[i DIV 32] THEN  
				p := 2*i + 1;  primes[n] := p;  INC( n );  j := i;
				WHILE j DIV 32 < N DO  EXCL( sieve[j DIV 32], j MOD 32 );  INC( j, p )  END;
			END;
			INC( i )
		END;
	END Init;
	
BEGIN
	Init;  
	B.Assign( one, 1 )
END AosCryptoPrimes.


