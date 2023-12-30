MODULE AosCryptoDSA;	(** AUTHOR "G.F."; PURPOSE "Digital Signature Algorithm DSA"; *)

IMPORT
	B := AosCryptoBigNumbers,	SHA1 := AosCryptoSHA1,	P := AosCryptoPrimes,	BIT;  

TYPE 
	Number = B.BigNumber;  

	Signature* = POINTER TO RECORD 
		r* : Number;
		s* : Number;
	END;  

	Key* = POINTER TO RECORD 
		p* : Number;
		q* : Number;
		g* : Number;
		pub* : Number;	
		priv, inv, r: Number;
	END;  
			
VAR
	one: Number;	(* constant *)
	
	PROCEDURE Init*( VAR key: Key );  
	BEGIN 
		NEW( key ); 
		B.Init( key.p );
		B.Init( key.q );
		B.Init( key.g );
		B.Init( key.pub );
		B.Init( key.priv );
		B.Init( key.inv );
	END Init;  
	
	PROCEDURE GenParams*( dsa: Key;  bits: INTEGER;  seed: ARRAY OF CHAR );  
	VAR
		randomseed, pfound: BOOLEAN;
		i, k, n, count: INTEGER;
		test, W, r0: Number;
		sbuf, buf, buf2, md: ARRAY 20 OF CHAR;
		h: SHA1.Hash;
	BEGIN 
		B.InitSize( W, 2*(bits DIV 8) );
		B.InitSize( r0, 2*(bits DIV 8) ); 
		IF bits < 512 THEN
			bits := 512;
		ELSE
			bits := (bits + 63) DIV 64 * 64;
		END;
		randomseed := LEN( seed ) < 20;
		IF ~randomseed THEN  
			FOR i := 0 TO 19 DO
				sbuf[i] := seed[i];
			END;
		END;
		B.Assign( test, 1 );
		B.Shift( test, bits - 1 );
		NEW( h );
		pfound := FALSE;
		LOOP (* find q and p *)
			REPEAT (* find q *)
				IF randomseed THEN
					B.RandomBytes( sbuf, 0, 20 );
				END;
				buf := sbuf;
				buf2 := sbuf;
				(* precompute "SEED + 1" *)
				REPEAT
					DEC( i );
					buf[i] := CHR( ORD( buf[i] ) + 1);
				UNTIL (i = 0) OR (buf[i] # 0X );
				h.Initialize;
				h.Update( sbuf, 0, 20 );
				h.GetHash( md, 0 );
				h.Initialize;
				h.Update( buf, 0, 20 );
				h.GetHash( buf2, 0 );
				FOR i := 0 TO 19 DO (* md := md xor buf2*)
					(* original:	md[i] := CHR( S.VAL( LONGINT,  S.VAL( SET, ORD( md[i] ) ) / S.VAL( SET, ORD( buf2[i] ) ) ) ); *)
					md[ i ] := BIT.CXOR( md[ i ], buf2[ i ] );
				END;
				IF ORD( md[0] ) < 128 THEN
					md[0] := CHR( ORD( md[0] ) + 128 );
				END;
				IF ~ODD( ORD( md[19] ) ) THEN
					md[19] := CHR( ORD( md[19] ) + 1 );
				END;
				B.AssignBin( dsa.q, md, 0, 20 );
			UNTIL P.IsPrime( dsa.q, 50, randomseed );
			count := 0;  n := bits  DIV 160; 
			LOOP (* find p *)
				B.Assign( W, 0 );
				(* now 'buf' contains "SEED + offset - 1" *)
				FOR k := 0 TO n  DO  
					(* obtain "SEED + offset + k" by incrementing: *)
					i := 20;
					REPEAT
						DEC( i );
						buf[i] := CHR( ORD( buf[i] ) + 1)
					UNTIL (i = 0) OR (buf[i] # 0X );
					h.Initialize;
					h.Update( buf, 0, 20 );
					h.GetHash( md, 0 );
					B.AssignBin( r0, md, 0, 20 );
					B.Shift( r0, 160*k );  B.Add( W, r0, W ); 
				END;
				B.Mask( W, bits - 1);
				B.Add( W, test, W );
				B.Copy( dsa.q, r0 );
				B.Shift( r0, 1 );
				B.Mod( W, r0, r0 );
				B.Dec( r0 );
				B.Sub( W, r0, dsa.p );
				IF B.Cmp( dsa.p, test ) >= 0 THEN  
					IF P.IsPrime( dsa.p, 50, TRUE ) THEN
						pfound := TRUE;
						EXIT;
					END;
				END;
				INC( count );
				IF count >= 4096 THEN
					EXIT;
				END;
			END; (* find p *)
			IF pfound THEN
				EXIT;
			END;
		END; (* find q and p *)
		
		B.Copy( dsa.p, test );
		B.Dec( test );
		B.Div( test, dsa.q, r0 );	(*  r0 := (p-1)/q *)
		B.Assign( test, 2 );
		LOOP (* g := test ^ r0 mod p *)
			dsa.g := B.ModExp( test, r0, dsa.p );
			IF B.Cmp( dsa.g, one ) # 0 THEN
				EXIT;
			END;
			B.Inc( test );
		END;
	END GenParams;  
	
	PROCEDURE GenKeys*( dsa: Key );
	BEGIN 
		IF B.Zero( dsa.p ) OR B.Zero( dsa.q ) OR B.Zero( dsa.g ) THEN
			HALT( 101 );
		END;
		REPEAT
			B.NewRandRange( dsa.priv, dsa.q )
		UNTIL ~B.Zero( dsa.priv );
		dsa.pub := B.ModExp( dsa.g, dsa.priv, dsa.p );
		B.Assign( dsa.inv, 0 );  B.Assign( dsa.r, 0 );  
	END GenKeys;

	PROCEDURE Sign*( dsa: Key;  digest: ARRAY OF CHAR;  len: INTEGER;  VAR sig: Signature );  
	VAR
		m, xr: Number;
	BEGIN 
		IF B.Zero( dsa.p ) OR B.Zero( dsa.q ) OR B.Zero( dsa.g ) THEN
			HALT( 101 );
		END;
		IF (len > dsa.q.len*4 ) OR (len > 50) THEN
			HALT( 102 );
		END;
		IF B.Zero( dsa.priv ) OR B.Zero( dsa.pub ) THEN
			GenKeys( dsa );
		END;
		IF B.Zero( dsa.inv ) OR B.Zero( dsa.r ) THEN  
			B.Mod( dsa.pub, dsa.q, dsa.r );	(* r := (g ^ k mod p) mod q *)
			B.ModInverse( dsa.priv, dsa.q, dsa.inv )	(* part of 's := inv( k ) * (m + x*r) mod q' *)
		END;
		NEW( sig );  sig.r := dsa.r;
		B.AssignBin( m, digest, 0, len );
		B.Mul( dsa.priv, dsa.r, xr );
		B.Add( xr, m, sig.s );	(* s := inv( k ) * (m + x*r) mod q *)
		IF B.Cmp( sig.s, dsa.q ) > 0 THEN
			B.Sub( sig.s, dsa.q, sig.s );
		END;
		B.ModMul( sig.s, dsa.inv, dsa.q, sig.s );
	END Sign;  

	PROCEDURE Verify*( dsa: Key;  sig: Signature;  VAR digest: ARRAY OF CHAR;  len: INTEGER ): BOOLEAN;  
	VAR
		u, v, w, t1, t2: Number;
	BEGIN 
		IF B.Cmp( sig.r, dsa.q ) >= 0 THEN
			RETURN FALSE;
		END;
		IF B.Cmp( sig.s, dsa.q ) >= 0 THEN
			RETURN FALSE;
		END;
		(* w = inv( s ) mod q *)
		B.ModInverse( sig.s, dsa.q, w );
		(* v = m * w mod q *)
		B.AssignBin( v, digest, 0, len );
		B.ModMul( v, w, dsa.q, v );
		(* u = r * w mod q *)
		B.ModMul( sig.r, w, dsa.q, u );
		(* v = (g^v * y^u mod p) mod q *)
		t1 := B.ModExp( dsa.g, v, dsa.p );
		t2 := B.ModExp( dsa.pub, u, dsa.p);
		B.ModMul( t1, t2, dsa.p, v );
		B.Mod( v, dsa.q, v );
		RETURN B.Cmp( v, sig.r ) = 0;
	END Verify;  

BEGIN  
	B.Assign( one, 1 );
	
END AosCryptoDSA.
 

System.Free AosCryptoDSA ~