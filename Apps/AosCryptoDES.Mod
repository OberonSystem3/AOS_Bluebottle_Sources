MODULE AosCryptoDES;	(** AUTHOR "G.F."; PURPOSE "Data Encryption Standard DES"; *)

IMPORT
	S := SYSTEM,	Ciphers := AosCryptoCiphers,	Out := AosOut,	AosIO,	AosFS,	BIT;
	
CONST 
	datafile = "AosCryptoDESTables.Data";

TYPE
	Block = ARRAY 2 OF SET;
	KeyBlock = ARRAY 32 OF SET;
	Ind4 = ARRAY 4 OF INTEGER;
	
	Cipher* = OBJECT (Ciphers.Cipher)
	VAR
		encryptionKeys, decryptionKeys: KeyBlock;
		iv: Block;

		PROCEDURE &Init;
		BEGIN
			SetNameAndBlocksize( "des", 8 );
			isKeyInitialized := FALSE
		END Init;

		(** initialize DES key *)
		PROCEDURE InitKey*( VAR src: ARRAY OF CHAR;  pos, keybits: LONGINT );  
		BEGIN
			ASSERT( keybits = 64 );  
			InitKey^( src, pos, keybits );  
			InitKeys( src, pos, TRUE, encryptionKeys );
			InitKeys( src, pos, FALSE, decryptionKeys );
			isKeyInitialized := TRUE 
		END InitKey;  
		
		(** set initialization vector for CBC mode *)
		PROCEDURE SetIV*( VAR src: ARRAY OF CHAR;  p: LONGINT );  
		BEGIN
			SetIV^( src, p ); (* set mode to CBC*)
			BytesToBlock( src, p, iv )
		END SetIV;  

		(** Encrypt a byte stream *)
		PROCEDURE Encrypt*( VAR buf: ARRAY OF CHAR; ofs, len: LONGINT );
			VAR i: LONGINT;
		BEGIN
			ASSERT( isKeyInitialized );
			ASSERT( len MOD blockSize = 0 ); (* padding must have been added *)
			i := 0;
			WHILE i < len DO (* for each block *)
				EncryptBlock( buf, ofs+i );
				INC( i, blockSize ); 
			END
		END Encrypt;

		(** Decrypt a byte stream *)
		PROCEDURE Decrypt*( VAR buf: ARRAY OF CHAR; ofs, len: LONGINT );
			VAR i: LONGINT;
		BEGIN
			ASSERT( isKeyInitialized );
			ASSERT( len MOD blockSize = 0 ); (* padding must have been added *)
			i := 0;
			WHILE i < len DO (* for each block *)
				DecryptBlock(buf, ofs+i );
				INC( i, blockSize ); 
			END;
		END Decrypt;

		(* Encrypt single block starting at position p *)
		PROCEDURE EncryptBlock( VAR buf: ARRAY OF CHAR;  p: LONGINT );  
			VAR b: Block;
		BEGIN
			BytesToBlock( buf, p, b );
			IF mode = Ciphers.CBC THEN
				b[0] := b[0] / iv[0];
				b[1] := b[1] / iv[1];
			END;
			Crypt( b, encryptionKeys );  
			BlockToBytes( b, buf, p );
			IF mode = Ciphers.CBC THEN	iv := b	END
		END EncryptBlock;  

		(* Decrypt single block starting at position p *)
		PROCEDURE DecryptBlock( VAR buf: ARRAY OF CHAR;  p: LONGINT );  
			VAR b0, b: Block;
		BEGIN 
			BytesToBlock( buf, p, b );
			IF mode = Ciphers.CBC THEN	b0 := b	END;
			Crypt( b, decryptionKeys );  
			IF mode = Ciphers.CBC THEN 
				b[0] := b[0] / iv[0];
				b[1] := b[1] / iv[1];
				iv := b0
			END;
			BlockToBytes( b, buf, p )
		END DecryptBlock;
		
	END Cipher;
	
VAR 
	skb: ARRAY 8, 64 OF SET; (* loaded with values from file 'datafile' during initialization *)
	T: ARRAY 8, 64 OF SET; (* loaded with values from file 'datafile' during initialization *)
	
	(** create a new DES cipher object *)
	PROCEDURE NewCipher*( par: PTR ): PTR;  
		VAR c: Cipher;  
	BEGIN 
		NEW( c );	RETURN c
	END NewCipher;  
	
	PROCEDURE BytesToSet( VAR buf: ARRAY OF CHAR;  p: LONGINT; VAR s: SET );  (* LSB first *)
	BEGIN 
		s := S.VAL( SET,
					ASH( LONG( ORD( buf[p + 3] ) ), 24 ) + 
					ASH( LONG( ORD( buf[p + 2] ) ), 16 ) + 
					ASH( LONG( ORD( buf[p + 1] ) ), 8 ) + 
					ORD( buf[p] ) );
	END BytesToSet;
	
	PROCEDURE BytesToBlock( VAR buf: ARRAY OF CHAR;  p: LONGINT;  VAR b: Block );  
	VAR
		i, j, v: LONGINT;
	BEGIN 
		FOR i := 0 TO 1 DO  j := p + 4*i;
			v := ASH( LONG( ORD( buf[j + 3] ) ), 24 ) + 
				  ASH( LONG( ORD( buf[j + 2] ) ), 16 ) + 
				  ASH( LONG( ORD( buf[j + 1] ) ), 8 ) + 
				  ORD( buf[j] );
			b[i] := S.VAL( SET, v )
		END 
	END BytesToBlock;  

	PROCEDURE BlockToBytes(  VAR b: Block;  VAR buf: ARRAY OF CHAR;  p: LONGINT );  
	VAR
		i, j, v: LONGINT;
	BEGIN 
		FOR i := 0 TO 1 DO 
			v := S.VAL( LONGINT, b[i] );  j := p + 4*i;
			buf[j + 0] := CHR( v MOD 100H );  v := v DIV 100H;
			buf[j + 1] := CHR( v MOD 100H );  v := v DIV 100H;
			buf[j + 2] := CHR( v MOD 100H );  v := v DIV 100H;
			buf[j + 3] := CHR( v MOD 100H )
		END
	END BlockToBytes;  
	
	PROCEDURE Hperm( VAR a: SET );
		VAR t: SET;
	BEGIN
		t := ( S.LSH( a, 18 ) / a) * S.VAL( SET, 0CCCC0000H );
		a := a / t / S.LSH( t, -18 )
	END Hperm;

	PROCEDURE Sm( s: SET;  n, m: LONGINT ): INTEGER;
	BEGIN
		RETURN SHORT( S.VAL( LONGINT, S.LSH( s, n ) * S.VAL( SET, m ) ) )
	END Sm;

	PROCEDURE InitKeys( VAR src: ARRAY OF CHAR;  p: LONGINT;  encrypting: BOOLEAN;  VAR keys: KeyBlock ); 
	VAR
		c, d, t, s: SET;
		shifts: LONGINT;
		i, j: INTEGER;
	BEGIN
		BytesToSet( src, p, c );
		BytesToSet( src, p + 4, d );
		Perm( d, c, 4,  0F0F0F0FH );
		Hperm( c );
		Hperm( d );
		Perm( d, c, 1, 55555555H );
		Perm( c, d, 8, 00FF00FFH );
		Perm( d, c, 1, 55555555H );
		
		d := S.LSH( d*{0..7} , 16 ) + d*{8..15} + S.LSH( d, -16 )*{0..7} + S.LSH( c, -4 )*{24..27};
		c := c * {0..27};
		
		shifts := 07EFCH;
		FOR i := 0 TO 15 DO
			IF ODD( shifts ) THEN  
				c := (S.LSH( c, -2 ) + S.LSH( c, 26 ))*{0..27};
				d := (S.LSH( d, -2 ) + S.LSH( d, 26 ))*{0..27};
			ELSE  
				c := (S.LSH( c, -1 ) + S.LSH( c, 27 ))*{0..27};
				d := (S.LSH( d, -1 ) + S.LSH( d, 27 ))*{0..27};
			END;
			shifts := shifts DIV 2;
			s := 
				skb[ 0, Sm( c, 0, 3FH )] + 
				skb[ 1, Sm( c, -6, 03H ) + Sm( c, -7, 3CH )] +
				skb[ 2, Sm( c, -13, 0FH ) + Sm( c, -14, 30H )] +
				skb[ 3, Sm( c, -20, 01H ) + Sm( c, -21, 06H ) + Sm( c, -22, 38H )];
			t :=
				skb[4, Sm( d, 0, 3FH )] +
				skb[5, Sm( d, -7, 3H ) + Sm( d, -8, 3CH )] +
				skb[6, Sm( d, -15, 3FH )] +
				skb[7, Sm( d, -21, 0FH ) + Sm( d, -22, 30H )];
				
			IF encrypting THEN
				j := 2*i;
			ELSE
				j := 30 - 2*i;
			END;
			keys[j] := S.LSH( t, 16 ) + s*{0..15};
			s := S.LSH( s, -16 ) + t*{16..31};
			keys[j+ 1] := S.LSH( s, 4 ) + S.LSH( s, -28 );
		END;
	END InitKeys; 
	
	PROCEDURE Perm( VAR a, b: SET;  n, m: LONGINT );
		VAR t: SET;
	BEGIN
		t := (S.LSH( a, -n ) / b) * S.VAL( SET, m );
		b := b / t;  a := a / S.LSH( t, n )
	END Perm;

	PROCEDURE Split( s: SET;  VAR i: Ind4  );  (* split set into 4 index values *)  
		VAR l: LONGINT;
	BEGIN 
		l := S.VAL( LONGINT, s );
		i[0] := SHORT( l MOD 40H );
		l := l DIV 100H;
		i[1] := SHORT( l MOD 40H );
		l := l DIV 100H;
		i[2] := SHORT( l MOD 40H );
		l := l DIV 100H;
		i[3] := SHORT( l MOD 40H )
	END Split;  

	PROCEDURE  Crypt( VAR block: Block;  VAR keys: KeyBlock );  
	VAR
		r, l, t: SET;
		i, j: LONGINT;
		a, b: Ind4;
	BEGIN 
		l := block[0];
		r := block[1];
		
		Perm( r, l,   4, 0F0F0F0FH );
		Perm( l, r, 16, 0000FFFFH );
		Perm( r, l,   2, 33333333H );
		Perm( l, r,   8, 00FF00FFH );
		Perm( r, l,   1, 55555555H );
		
		t := S.ROT( r, 1 );
		r := S.ROT( l, 1 );
		l := t;

		FOR i := 0 TO 7 DO
			j := 4*i;
			Split( r / keys[j], b );
			Split( S.ROT( r / keys[j + 1], -4 ), a );  
			l := l / (T[1, a[0]] + T[3, a[1]] + T[5, a[2]] + T[7, a[3]] + T[0, b[0]] + T[2, b[1]] + T[4, b[2]] + T[6, b[3]] );
			
			Split( l / keys[j + 2], b );
			Split( S.ROT( l / keys[j + 3], -4 ), a );  
			r := r / (T[1, a[0]] + T[3, a[1]] + T[5, a[2]] + T[7, a[3]] + T[0, b[0]] + T[2, b[1]] + T[4, b[2]] + T[6, b[3]] );
		END;
		
		l := S.ROT( l, -1 );
		r := S.ROT( r, -1 );

		Perm( r, l,  1, 55555555H );
		Perm( l, r,  8, 00FF00FFH );
		Perm( r, l,  2, 33333333H );  
		Perm( l, r, 16, 0000FFFFH );
		Perm( r, l,  4, 0F0F0F0FH );

		block[0] := l;
		block[1] := r
	END Crypt;

	
	PROCEDURE Init;
	VAR
		f: AosFS.File; 
		r: AosFS.Reader; 
		token: ARRAY 64 OF CHAR;
		i, j, x: LONGINT;
	
		PROCEDURE FError;  
		BEGIN 
			Out.String( "Format error in " );  Out.String( datafile );  
			Out.String( ",  pos  " ); Out.Int( r.Pos(), 1 ); Out.Ln
		END FError;  

	BEGIN
		f := AosFS.Old( datafile );	(* open an existing file *)
		IF f = NIL THEN
			Out.String( "File '");  Out.String( datafile );  Out.String( "' not found" );  Out.Ln;
		END;
		AosFS.OpenReader(r, f, 0);	(* open a buffer on the file *)
		r.SkipWhitespace;
		r.SkipWhitespace;
		r.Token( token );

		IF token # "des.skb:" THEN  FError;  RETURN  END;
		r.SkipWhitespace;
		Out.Ln;
		FOR i := 0 TO 7 DO 
			FOR j := 0 TO 63 DO 
				r.Int( x, TRUE );
				IF r.res # AosIO.Ok THEN	FError;	RETURN	END;
				skb[ i, j ] := S.VAL( SET, x );
				r.SkipWhitespace;
			END
		END;

		r.Token( token );
		IF token # "des.SPtrans:" THEN	FError;	RETURN	END;
		r.SkipWhitespace;
		
		FOR i := 0 TO 7 DO 
			FOR j := 0 TO 63 DO 
				r.Int( x, TRUE );
				IF r.res # AosIO.Ok THEN	FError;	RETURN	END;
				T[ i, j ] := S.VAL( SET, x );
				r.SkipWhitespace
			END
		END
	END Init;

BEGIN
	ASSERT( S.VAL( LONGINT, {0} ) = 1 );
	Init
END AosCryptoDES.
 

System.Free AosCryptoDES ~
