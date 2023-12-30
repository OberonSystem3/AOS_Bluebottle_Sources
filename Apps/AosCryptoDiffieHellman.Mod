MODULE AosCryptoDiffieHellman;	(** AUTHOR "G.F."; PURPOSE "Diffie-Hellman Key-Establishment"; *)

IMPORT
	B := AosCryptoBigNumbers,	Out := AosOut,	AosIO,	AosFS;  

CONST
	datafile = "AosCryptoDHPrimes.Data";  

TYPE 
	DH* = OBJECT	
		VAR 
			p, g: B.BigNumber;  (* modulus, generator *)
			private-: B.BigNumber;

		PROCEDURE & Init*( prkeybits: INTEGER;  pname: ARRAY OF CHAR );  
		BEGIN 
			ASSERT( (prkeybits > 0) OR (pname # "") );
			B.Init( p );  B.Init( g );  
			IF pname # "" THEN 
				GetDHPrime( pname, p, g );  B.NewRandRange( private, p )
			END;
			IF prkeybits > 0 THEN  B.NewRand( private, prkeybits, 1, 0 ) END;  
		END Init;  

		PROCEDURE GetDHPrime( name: ARRAY OF CHAR;  VAR p, g: B.BigNumber );  
			VAR
				r: AosFS.Reader;
				f: AosFS.File;
				token: ARRAY 64 OF CHAR;
		BEGIN
			f := AosFS.Old( datafile );	(* open existing file *)
			IF f = NIL THEN Out.String( "File '");  Out.String( datafile );  Out.String( "' not found" );  Out.Ln; HALT( 99 ) END;
			AosFS.OpenReader(r, f, 0);	(* open a buffer on the file *)

			r.SkipWhitespace;
			r.Token( token );
			WHILE token # name DO
				IF r.res # AosIO.Ok THEN
					Out.String( "Diffie Hellman prime '" );  Out.String( name );  
					Out.String( "' not found in file: '" );  Out.String( datafile );  Out.Char( "'" );  Out.Ln;  
						HALT( 99 )
				END;
				Out.Int( r.Pos(), 8 );
				r.SkipWhitespace;
				r.Token( token )
			END;
			B.TextRead( r, p );  B.TextRead( r, g )
		END GetDHPrime;  

		PROCEDURE SetPrime*( VAR p, g: B.BigNumber );  
		BEGIN 
			B.Copy( p, SELF.p );  		B.Copy( g, SELF.g )
		END SetPrime;  		
		
		PROCEDURE SetPrivateKey*( VAR key: B.BigNumber );  
		BEGIN 
			B.Copy( key, private )
		END SetPrivateKey;  

		PROCEDURE GeneratePublicKey*(  ): B.BigNumber;  
			VAR pub: B.BigNumber;
		BEGIN 
			pub := B.ModExp( g, private, p );
			RETURN pub
		END GeneratePublicKey;  

		PROCEDURE ComputeSharedKey*( VAR pub: B.BigNumber ): B.BigNumber;
			VAR key: B.BigNumber;
		BEGIN 
			key := B.ModExp( pub, private, p );
			RETURN key
		END ComputeSharedKey; 

	END DH;

END AosCryptoDiffieHellman.
 

System.Free AosCryptoDiffieHellman~