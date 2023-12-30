MODULE AosCryptoSHA1;	(** AUTHOR "G.F."; PURPOSE "SHA-1"; *)

IMPORT
	S := SYSTEM,	Hashes := AosCryptoHashes;
	
CONST 
	BlockSize = 64;

TYPE
	Hash* = OBJECT (Hashes.Hash)
		VAR
			c: Context;

		PROCEDURE &Init;  
		BEGIN
			SetNameAndSize( "sha1", 20 );
			initialized := FALSE
		END Init;  

		PROCEDURE Initialize*;  
		BEGIN 
			c.h0 := 067452301H;
			c.h1 := 0EFCDAB89H;
			c.h2 := 098BADCFEH;  
			c.h3 := 010325476H;
			c.h4 := 0C3D2E1F0H;  
			c.Nl := 0;
			c.Nh := 0;
			c.n := 0;
			initialized := TRUE
		END Initialize;  

		(** data: value to be hashed *)
		PROCEDURE Update*( VAR data: ARRAY OF CHAR;  pos, len: LONGINT );  
			VAR n, i, l: LONGINT;
		BEGIN
			ASSERT( initialized );
			l := c.Nl + len *8;  
			IF l < c.Nl THEN INC( c.Nh )  (* overflow *)  END;  
			c.Nh := c.Nh + ASH( len, -29 );  c.Nl := l;  
		
			IF c.n > 0 THEN 
				IF c.n + len < BlockSize THEN 
					i := c.n;  INC( c.n, len );  
					WHILE i < c.n  DO c.data[i] := data[pos];  INC( i ); INC( pos ) END;
					RETURN
				ELSE 	
					WHILE c.n < BlockSize  DO c.data[c.n] := data[pos];  INC( c.n );  INC( pos );  DEC( len ) END;
					HashContextBlock( c ); 
				END 
			END;
		
			n := 0;
			WHILE n < len DIV BlockSize  DO HashBlock( c, data, pos );  INC( n ) END;  
			len := len MOD BlockSize;
			WHILE c.n < len  DO c.data[c.n] := data[pos];  INC( c.n );  INC( pos )  END;
		END Update;  

		(** get the hashvalue of length SELF.size *)
		PROCEDURE GetHash*( VAR buf: ARRAY OF CHAR;  pos: LONGINT );  
			VAR p: LONGINT;
		BEGIN
			c.data[c.n] := 80X;  INC( c.n );
			IF c.n > BlockSize - 8 THEN
				WHILE c.n < BlockSize  DO c.data[c.n] := 0X;  INC( c.n ) END;  
				HashContextBlock( c );
			END;
			p := BlockSize - 8; 
			WHILE c.n < p  DO c.data[c.n] := 0X;  INC( c.n ) END;
			int2chars( c.Nh, c.data, p );  int2chars( c.Nl, c.data, p );
		
			HashContextBlock( c );
			int2chars( c.h0, buf, pos );  int2chars( c.h1, buf, pos );  int2chars( c.h2, buf, pos );  
			int2chars( c.h3, buf, pos );  int2chars( c.h4, buf, pos );
		END GetHash;  

	END Hash;

	Context = RECORD 
		h0, h1, h2, h3, h4: LONGINT;	(* state *)
		Nl, Nh: LONGINT;
		data: ARRAY BlockSize OF CHAR;	(* pending data *)
		n: LONGINT	(* number of chars in data *)
	END;  
	
	
	(* PROCEDURES *******************************************************************************)
	
	(** get an instance of SHA1 *)
	PROCEDURE NewHash*( par: PTR ): PTR;  
		VAR h: Hash;
	BEGIN 
		NEW( h );		RETURN h
	END NewHash; 
	
	PROCEDURE chars2set( VAR buf: ARRAY OF CHAR;  VAR p: LONGINT;  VAR s: SET );  
	BEGIN 
		INC( p, 4 );  
		s := S.VAL( SET,  ASH( LONG( ORD( buf[p - 4] ) ), 24 ) + 
								  ASH( LONG( ORD( buf[p - 3] ) ), 16 ) + 
								  ASH( LONG( ORD( buf[p - 2] ) ), 8 ) + 
								  ORD( buf[p - 1] ) );  
	END chars2set;  
	
	PROCEDURE int2chars( v: LONGINT;  VAR buf: ARRAY OF CHAR;  VAR p: LONGINT );  
	VAR i: LONGINT;
	BEGIN 
		INC( p, 4 );  
		FOR i := 1 TO 4 DO buf[p - i] := CHR( v MOD 256);  v := v DIV 256 END
	END int2chars;  

	PROCEDURE F1( b, c, d: LONGINT ): LONGINT;  
	BEGIN 
		RETURN S.VAL( LONGINT, ((S.VAL( SET, c ) / S.VAL( SET, d )) * S.VAL( SET, b )) / S.VAL( SET, d ) )
	END F1;  

	PROCEDURE F2( b, c, d: LONGINT ): LONGINT;  
	BEGIN 
		RETURN S.VAL( LONGINT, S.VAL( SET, b ) / S.VAL( SET, c ) / S.VAL( SET, d ) )
	END F2;  

	PROCEDURE F3( b, c, d: LONGINT ): LONGINT;  
	BEGIN 
		RETURN S.VAL( LONGINT, (S.VAL( SET, b ) * S.VAL( SET, c )) + ((S.VAL( SET, b ) + S.VAL( SET, c )) * S.VAL( SET, d )) )
	END F3;

	PROCEDURE tr0019( a: LONGINT; VAR b: LONGINT; c, d, e: LONGINT; VAR  f: LONGINT; x: SET );  
	BEGIN 
		f := S.VAL( LONGINT, x ) + e + 5A827999H + S.ROT( a, 5 ) + F1( b, c, d );  
		b := S.ROT( b, 30 );  
	END tr0019;  

	PROCEDURE tr2039( a: LONGINT;  VAR b: LONGINT;  c, d, e: LONGINT;  VAR f: LONGINT;  x: SET );  
	BEGIN 
		f := S.VAL( LONGINT, x ) + e + 6ED9EBA1H + S.ROT( a, 5 ) + F2( b, c, d );  
		b := S.ROT( b, 30 );  
	END tr2039;  

	PROCEDURE tr4059( a: LONGINT;  VAR b: LONGINT;  c, d, e: LONGINT;  VAR f: LONGINT;  x: SET);
	BEGIN 
		f := S.VAL( LONGINT, x ) + e + 8F1BBCDCH + S.ROT( a, 5 ) + F3( b, c, d );  
		b := S.ROT( b, 30 )
	END tr4059;  

	PROCEDURE tr6079( a: LONGINT;  VAR b: LONGINT;  c, d, e: LONGINT;  VAR f: LONGINT;  x: SET );  
	BEGIN 
		f := S.VAL( LONGINT, x ) + e + 0CA62C1D6H + S.ROT( a, 5 ) + F2( b, c, d );  
		b := S.ROT( b, 30 );  
	END tr6079;

	PROCEDURE HashBlock( VAR c: Context;  VAR buf: ARRAY OF CHAR;  VAR pos: LONGINT );  
	VAR A, B, C, D, E, T: LONGINT;  
		x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15: SET;
	BEGIN 
		A := c.h0;  B := c.h1;  C := c.h2;  D := c.h3;  E := c.h4;  
		
		chars2set( buf, pos, x0 );    tr0019( A, B, C, D, E, T, x0 );    chars2set( buf, pos, x1 );    tr0019( T, A, B, C, D, E, x1 );
		chars2set( buf, pos, x2 );    tr0019( E, T, A, B, C, D, x2 );    chars2set( buf, pos, x3 );    tr0019( D, E, T, A, B, C, x3 );
		chars2set( buf, pos, x4 );    tr0019( C, D, E, T, A, B, x4 );    chars2set( buf, pos, x5 );    tr0019( B, C, D, E, T, A, x5 );
		chars2set( buf, pos, x6 );    tr0019( A, B, C, D, E, T, x6 );    chars2set( buf, pos, x7 );    tr0019( T, A, B, C, D, E, x7 );
		chars2set( buf, pos, x8 );    tr0019( E, T, A, B, C, D, x8 );    chars2set( buf, pos, x9 );    tr0019( D, E, T, A, B, C, x9 );
		chars2set( buf, pos, x10 );  tr0019( C, D, E, T, A, B, x10 );  chars2set( buf, pos, x11 );  tr0019( B, C, D, E, T, A, x11 );
		chars2set( buf, pos, x12 );  tr0019( A, B, C, D, E, T, x12 );  chars2set( buf, pos, x13 );  tr0019( T, A, B, C, D, E, x13 );
		chars2set( buf, pos, x14 );  tr0019( E, T, A, B, C, D, x14 );  chars2set( buf, pos, x15 );  tr0019( D, E, T, A, B, C, x15 );

		x0   := S.ROT( x0 / x2 / x8 / x13, 1 );      tr0019( C, D, E, T, A, B, x0 );    
		x1   := S.ROT( x1 / x3 / x9 / x14, 1 );      tr0019( B, C, D, E, T, A, x1 );  
		x2   := S.ROT( x2 / x4 / x10 / x15, 1 );    tr0019( A, B, C, D, E, T, x2 );  
		x3   := S.ROT( x3 / x5 / x11 / x0, 1 );      tr0019( T, A, B, C, D, E, x3 );  

		x4   := S.ROT( x4 / x6 / x12 / x1, 1 );      tr2039( E, T, A, B, C, D, x4 );    
		x5   := S.ROT( x5 / x7 / x13 / x2, 1 );      tr2039( D, E, T, A, B, C, x5 );  
		x6   := S.ROT( x6 / x8 / x14 / x3, 1 );      tr2039( C, D, E, T, A, B, x6 );    
		x7   := S.ROT( x7 / x9 / x15 / x4, 1 );      tr2039( B, C, D, E, T, A, x7 );  
		x8   := S.ROT( x8 / x10 / x0 / x5, 1 );      tr2039( A, B, C, D, E, T, x8 );    
		x9   := S.ROT( x9 / x11 / x1 / x6, 1 );      tr2039( T, A, B, C, D, E, x9 );  
		x10 := S.ROT( x10 / x12 / x2 / x7, 1 );    tr2039( E, T, A, B, C, D, x10 );  
		x11 := S.ROT( x11 / x13 / x3 / x8, 1 );    tr2039( D, E, T, A, B, C, x11 );  
		x12 := S.ROT( x12 / x14 / x4 / x9, 1 );    tr2039( C, D, E, T, A, B, x12 );  
		x13 := S.ROT( x13 / x15 / x5 / x10, 1 );  tr2039( B, C, D, E, T, A, x13 );  
		x14 := S.ROT( x14 / x0 / x6 / x11, 1 );    tr2039( A, B, C, D, E, T, x14 );  
		x15 := S.ROT( x15 / x1 / x7 / x12, 1 );    tr2039( T, A, B, C, D, E, x15 );  
		x0   := S.ROT( x0 / x2 / x8 / x13, 1 );      tr2039( E, T, A, B, C, D, x0 );    
		x1   := S.ROT( x1 / x3 / x9 / x14, 1 );      tr2039( D, E, T, A, B, C, x1 );  
		x2   := S.ROT( x2 / x4 / x10 / x15, 1 );    tr2039( C, D, E, T, A, B, x2 );  
		x3   := S.ROT( x3 / x5 / x11 / x0, 1 );      tr2039( B, C, D, E, T, A, x3 );  
		x4   := S.ROT( x4 / x6 / x12 / x1, 1 );      tr2039( A, B, C, D, E, T, x4 );    
		x5   := S.ROT( x5 / x7 / x13 / x2, 1 );      tr2039( T, A, B, C, D, E, x5 );  
		x6   := S.ROT( x6 / x8 / x14 / x3, 1 );      tr2039( E, T, A, B, C, D, x6 );    
		x7   := S.ROT( x7 / x9 / x15 / x4, 1 );      tr2039( D, E, T, A, B, C, x7 );  
	
		x8   := S.ROT( x8 / x10 / x0 / x5, 1 );      tr4059( C, D, E, T, A, B, x8 );    
		x9   := S.ROT( x9 / x11 / x1 / x6, 1 );      tr4059( B, C, D, E, T, A, x9 );  
		x10 := S.ROT( x10 / x12 / x2 / x7, 1 );    tr4059( A, B, C, D, E, T, x10 );  
		x11 := S.ROT( x11 / x13 / x3 / x8, 1 );    tr4059( T, A, B, C, D, E, x11 );  
		x12 := S.ROT( x12 / x14 / x4 / x9, 1 );    tr4059( E, T, A, B, C, D, x12 );  
		x13 := S.ROT( x13 / x15 / x5 / x10, 1 );  tr4059( D, E, T, A, B, C, x13 );  
		x14 := S.ROT( x14 / x0 / x6 / x11, 1 );    tr4059( C, D, E, T, A, B, x14 );  
		x15 := S.ROT( x15 / x1 / x7 / x12, 1 );    tr4059( B, C, D, E, T, A, x15 );  
		x0   := S.ROT( x0 / x2 / x8 / x13, 1 );      tr4059( A, B, C, D, E, T, x0 );    
		x1   := S.ROT( x1 / x3 / x9 / x14, 1 );      tr4059( T, A, B, C, D, E, x1 );  
		x2   := S.ROT( x2 / x4 / x10 / x15, 1 );    tr4059( E, T, A, B, C, D, x2 );  
		x3   := S.ROT( x3 / x5 / x11 / x0, 1 );      tr4059( D, E, T, A, B, C, x3 );  
		x4   := S.ROT( x4 / x6 / x12 / x1, 1 );      tr4059( C, D, E, T, A, B, x4 );    
		x5   := S.ROT( x5 / x7 / x13 / x2, 1 );      tr4059( B, C, D, E, T, A, x5 );  
		x6   := S.ROT( x6 / x8 / x14 / x3, 1 );      tr4059( A, B, C, D, E, T, x6 );    
		x7   := S.ROT( x7 / x9 / x15 / x4, 1 );      tr4059( T, A, B, C, D, E, x7 );  
		x8   := S.ROT( x8 / x10 / x0 / x5, 1 );      tr4059( E, T, A, B, C, D, x8 );    
		x9   := S.ROT( x9 / x11 / x1 / x6, 1 );      tr4059( D, E, T, A, B, C, x9 );  
		x10 := S.ROT( x10 / x12 / x2 / x7, 1 );    tr4059( C, D, E, T, A, B, x10 );  
		x11 := S.ROT( x11 / x13 / x3 / x8, 1 );    tr4059( B, C, D, E, T, A, x11 );

		x12 := S.ROT( x12 / x14 / x4 / x9, 1 );    tr6079( A, B, C, D, E, T, x12 );  
		x13 := S.ROT( x13 / x15 / x5 / x10, 1 );  tr6079( T, A, B, C, D, E, x13 );  
		x14 := S.ROT( x14 / x0 / x6 / x11, 1 );    tr6079( E, T, A, B, C, D, x14 );  
		x15 := S.ROT( x15 / x1 / x7 / x12, 1 );    tr6079( D, E, T, A, B, C, x15 );  
		x0   := S.ROT( x0 / x2 / x8 / x13, 1 );      tr6079( C, D, E, T, A, B, x0 );    
		x1   := S.ROT( x1 / x3 / x9 / x14, 1 );      tr6079( B, C, D, E, T, A, x1 );  
		x2   := S.ROT( x2 / x4 / x10 / x15, 1 );    tr6079( A, B, C, D, E, T, x2 );
		x3   := S.ROT( x3 / x5 / x11 / x0, 1 );      tr6079( T, A, B, C, D, E, x3 );
		x4   := S.ROT( x4 / x6 / x12 / x1, 1 );      tr6079( E, T, A, B, C, D, x4 );    
		x5   := S.ROT( x5 / x7 / x13 / x2, 1 );      tr6079( D, E, T, A, B, C, x5 );  
		x6   := S.ROT( x6 / x8 / x14 / x3, 1 );      tr6079( C, D, E, T, A, B, x6 );    
		x7   := S.ROT( x7 / x9 / x15 / x4, 1 );      tr6079( B, C, D, E, T, A, x7 );  
		x8   := S.ROT( x8 / x10 / x0 / x5, 1 );      tr6079( A, B, C, D, E, T, x8 );    
		x9   := S.ROT( x9 / x11 / x1 / x6, 1 );      tr6079( T, A, B, C, D, E, x9 );  
		x10 := S.ROT( x10 / x12 / x2 / x7, 1 );    tr6079( E, T, A, B, C, D, x10 );  
		x11 := S.ROT( x11 / x13 / x3 / x8, 1 );    tr6079( D, E, T, A, B, C, x11 );  
		x12 := S.ROT( x12 / x14 / x4 / x9, 1 );    tr6079( C, D, E, T, A, B, x12 );  
		x13 := S.ROT( x13 / x15 / x5 / x10, 1 );  tr6079( B, C, D, E, T, A, x13 );  
		x14 := S.ROT( x14 / x0 / x6 / x11, 1 );    tr6079( A, B, C, D, E, T, x14 );  
		x15 := S.ROT( x15 / x1 / x7 / x12, 1 );    tr6079( T, A, B, C, D, E, x15 );  

		c.h0 := c.h0 + E;  c.h1 := c.h1 + T;  c.h2 := c.h2 + A;  c.h3 := c.h3 + B;  c.h4 := c.h4 + C;  
	END HashBlock;  

	PROCEDURE HashContextBlock( VAR c: Context );  
	VAR p: LONGINT;
	BEGIN 
		p := 0;  HashBlock( c, c.data, p );  c.n := 0
	END HashContextBlock;

END AosCryptoSHA1.