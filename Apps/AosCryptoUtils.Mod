MODULE AosCryptoUtils;	(** AUTHOR "G.F."; PURPOSE "Crypto Utilities"; *)

IMPORT
	Rand := AosRandom,	S := SYSTEM,	AosOut,	AosKernel,	B := AosCryptoBigNumbers;
	
VAR 
	hexd: ARRAY 17 OF CHAR;	(* constant *)
	debug-: SET;		(* bits: 
										0: verbose
										transport level:
										1: trace protocol, 
										2: trace protocol more detailed
										3: show I/O packets (type only)
										4: show I/O packets (with contents)
										....
									*)

	PROCEDURE error( msg: ARRAY OF CHAR );  
	BEGIN 
		HALT( 99 );
	END error;  

	(** convert 2*len hex nibbles into len bytes *)
	PROCEDURE Hex2Bin*( VAR hex: ARRAY OF CHAR;  hp: LONGINT;  VAR bin: ARRAY OF CHAR;  bp, len: LONGINT );
	VAR
		h, b, i: LONGINT; 
		c: CHAR;
	BEGIN 
		i := 0;  
		WHILE i < 2*len DO 		(* parse one nibble at a time *)
			c := hex[hp + i];
			IF (c >= '0') & (c <= '9') THEN h := ORD( c ) - ORD( '0' );
			ELSIF (c >= 'a') & (c <= 'f') THEN h := ORD( c ) - ORD( 'a' ) + 10;
			ELSIF (c >= 'A') & (c <= 'F') THEN h := ORD( c ) - ORD( 'A' ) + 10;
			ELSIF c = 0X THEN error( "hex source too short" ) 
			ELSE error( "format error in hex string" )
			END;
			IF ODD( i ) THEN bin[bp] := CHR( b + h );  INC( bp )
			ELSE b :=  h * 16
			END;
			INC( i )
		END
	END Hex2Bin;
	
	(** convert len bytes  into 2*len hex nibbles *)
	PROCEDURE Bin2Hex*( VAR bin: ARRAY OF CHAR; bp: LONGINT; VAR hex: ARRAY OF CHAR; hp, len: LONGINT );
	VAR
		i, c: LONGINT;  
	BEGIN 
		FOR i := 0 TO len - 1 DO
			c := ORD( bin[ bp + i] ); 
			hex[hp] := hexd[ c DIV 16];
			INC( hp );
			hex[hp] := hexd[ c MOD 16];
			INC( hp );
		END
	END Bin2Hex;
	
	(** fill len pseudo-random bytes into buf, starting at posistion ofs *)
	PROCEDURE RandomBytes*( VAR buf: ARRAY OF CHAR;  ofs, len: LONGINT );  
	VAR
		i: LONGINT;  
		rg: Rand.Generator;
	BEGIN
		NEW( rg );
		rg.InitSeed( AosKernel.GetTimer( ) );  
		FOR i := 0 TO len - 1 DO buf[ ofs + i ] := CHR( ENTIER( rg.Uniform()*256 ) ) END 
	END RandomBytes;  
	
	(** print a binary buf as a hex *)
	PROCEDURE OutHex*( VAR buf: ARRAY OF CHAR;  p, n: LONGINT );  
		VAR ch, i: LONGINT;  
	BEGIN 
		FOR i := 0 TO n - 1 DO 
			IF i MOD 4 = 0 THEN
				IF i MOD 24 = 0 THEN AosOut.Ln  END;
				AosOut.String( "   " )
			END;
			ch := ORD( buf[p + i] );
			AosOut.Char( hexd[ch DIV 10H] );  AosOut.Char( hexd[ch MOD 10H] );
		END 
	END OutHex;  

	(** convert 4 chars starting at position p into a longint *)
	PROCEDURE Int*( VAR buf: ARRAY OF CHAR;  p: LONGINT ): LONGINT;  
	BEGIN 
		RETURN ASH( LONG( ORD( buf[ p ] ) ), 24 ) + ASH( LONG( ORD( buf[ p + 1 ] ) ), 16 ) + 
				    ASH( LONG( ORD( buf[ p + 2 ] ) ), 8 ) + ORD( buf[ p + 3 ] );  
	END Int;  

	(** store a longint as 4 chars in buf, starting at position p *)
	PROCEDURE StoreInt*( v: LONGINT;  VAR buf: ARRAY OF CHAR;  VAR p: LONGINT );  
		VAR i: LONGINT;  
	BEGIN 
		FOR i := 3 TO 0 BY -1 DO buf[p + i] := CHR( v MOD 256 );  v := v DIV 256 END;
		INC( p, 4 )
	END StoreInt;
	
	PROCEDURE StoreArray*( VAR arr: ARRAY OF CHAR;  ap, len: LONGINT;  VAR buf: ARRAY OF CHAR;  VAR bp: LONGINT );  
		VAR i: LONGINT;  
	BEGIN 
		StoreInt( len, buf, bp );  
		FOR i := 0 TO len -1 DO buf[bp] := arr[ap + i];  INC( bp )  END 
	END StoreArray; 
	
	PROCEDURE StoreString*( str: ARRAY OF CHAR;  VAR buf: ARRAY OF CHAR;  VAR pos: LONGINT );  
		VAR i, len: LONGINT;  
	BEGIN 
		len := 0;
		WHILE (len < LEN(str)) & (str[len] # 0X) DO INC( len ) END;
		StoreInt( len, buf, pos );  
		FOR i := 0 TO len -1 DO buf[pos] := str[i];  INC( pos )  END ;
	END StoreString; 
	
	PROCEDURE LoadString*( VAR str: ARRAY OF CHAR;  VAR buf: ARRAY OF CHAR;  VAR pos: LONGINT );  
		VAR i, len: LONGINT;  
	BEGIN 
		len := Int( buf, pos ); INC( pos, 4 );
		FOR i := 0 TO len -1 DO str[i] := buf[pos];  INC( pos )  END;
		str[len] := 0X
	END LoadString; 
	
	PROCEDURE StoreBigNum*( VAR b: B.BigNumber;  VAR buf: ARRAY OF CHAR;  VAR p: LONGINT );  
		VAR i, j, len: LONGINT;  tmp: ARRAY 1024 OF CHAR;
	BEGIN
		len := 0;
		FOR i := b.len-1 TO 0 BY -1 DO  StoreInt( b.d[ i ], tmp, len )  END;
		j := 0;
		WHILE tmp[j] = 0X DO  INC( j );  DEC( len )  END;
		IF ORD( tmp[j] ) >= 128 THEN  StoreInt( len + 1, buf, p );  buf[p] := 0X;  INC( p )
		ELSE  StoreInt( len, buf, p );  
		END;
		FOR i := 0 TO len - 1 DO  buf[p] := tmp[j + i];  INC( p )  END;
	END StoreBigNum;  

	PROCEDURE OutString*( VAR buf: ARRAY OF CHAR;  pos: LONGINT );  
		VAR i, len: LONGINT;  
	BEGIN 
		len := Int( buf, pos );  INC( pos, 4 );
		FOR i := 0 TO len - 1 DO AosOut.Char( buf[pos + i] )  END 
	END OutString; 

	PROCEDURE ShowPackage*( VAR buf: ARRAY OF CHAR;  len: LONGINT );  
		VAR i: LONGINT;  c: CHAR;
	BEGIN 
		FOR i := 0 TO len - 1 DO 
			IF i MOD 24 = 0 THEN AosOut.Ln END;
			IF i MOD 4 = 0 THEN AosOut.String( ' ' ) END;
			c := buf[i];
			AosOut.Char( hexd[ ORD( c ) DIV 16] );  
			AosOut.Char( hexd[ ORD( c ) MOD 16] ); 
		END;
		AosOut.Ln
	END ShowPackage;
	
BEGIN 
	hexd := "0123456789ABCDEF";
END AosCryptoUtils.


System.Free AosCryptoUtils ~

