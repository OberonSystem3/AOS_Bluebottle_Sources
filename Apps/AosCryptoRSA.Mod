MODULE AosCryptoRSA;	(** AUTHOR "G.F."; PURPOSE "RSA"; *)

(* Excerpt of Crypt.Mod  jm 23.8.95.*)

IMPORT
	B := AosCryptoBigNumbers, MD5 := AosCryptoMD5, AosFS, Ciphers := AosCryptoCiphers, AosClock;  

CONST 
	chinese = TRUE;  

TYPE 
	Number* = B.BigNumber;
	Buffer = ARRAY 16 OF CHAR;

	Certificate* = OBJECT
		VAR
			authority*: ARRAY 128 OF CHAR;   (** Certifying authority.  *)
			signature*: Number;   (** Signature of key. *)
			next*: Certificate;
	END Certificate;  
	
	Key* = OBJECT
		VAR 
			name-: ARRAY 128 OF CHAR;   (** Owner of this key. *)
			private-: BOOLEAN;   (** Is this a private key? then the exponent is encrypted *)
			size-: INTEGER;
			exponent*, modulus*: Number;  
			p, q, u: Number;   (* for chinese remainder theorem *)
			check: LONGINT;   (* least significant LONGINT of unencrypted exponent *)
			time-, date-: LONGINT;  
			certificates*: Certificate;  
			next*: Key;
	END Key;  

VAR 
	one, two: Number;	(* constants *)
		
	(* converts LONGINT to ARRAY OF CHAR; big endian order *)
	PROCEDURE l2n( l: LONGINT;  VAR buf: Buffer;  pos: LONGINT );
		VAR i: LONGINT;
	BEGIN 
		i := pos + 3;
		WHILE i >= pos DO
			buf[i] := CHR( l MOD 256 );
			l := l DIV 256;
			DEC( i )
		END
	END l2n;
	
	(* converts ARRAY OF CHAR to LONGINT; big endian order *) 
	PROCEDURE n2l( VAR buf: Buffer;  pos: LONGINT ): LONGINT;
		VAR i, l: LONGINT;
	BEGIN 
		i := pos;
		l := 0;
		WHILE i < pos + 4 DO
			l := 256*l + ORD( buf[i] );
			INC( i );
		END;
		RETURN l
	END n2l;
	
	PROCEDURE EncryptNumber( VAR n: Number; c: Ciphers.Cipher );  
		VAR
			i: INTEGER;
			buf: Buffer;
	BEGIN 
		ASSERT( n.len MOD 2 = 0 );
		i := n.len - 1;
		WHILE i > 0 DO  
			l2n( n.d[i], buf, 0 );
			l2n( n.d[i - 1], buf, 4 );
			c.Encrypt( buf, 0, c.blockSize);  
			n.d[i] := n2l( buf, 0 );
			n.d[i - 1] := n2l( buf, 4 ); 
			DEC( i,  2 )
		END
	END EncryptNumber;  
	
	PROCEDURE DecryptNumber( VAR n: Number; c: Ciphers.Cipher );  
	VAR
		i: INTEGER;
		buf: Buffer;
	BEGIN 
		ASSERT( n.len MOD 2 = 0 );
		i := n.len - 1;
		WHILE i > 0 DO 
			l2n( n.d[i], buf, 0 );
			l2n( n.d[i - 1], buf, 4 );
			c.Decrypt( buf, 0, c.blockSize ); 
			n.d[i] := n2l( buf, 0 );
			n.d[i - 1] := n2l( buf, 4 ); 
			DEC( i,  2 )
		END
	END DecryptNumber; 

	(** Generate public and private keys out of the large primes p and q.
		The private key's exponent will be enrypted with IDEA and key passwd *)
	PROCEDURE MakeKeys*( VAR p, q: Number;  name, passwd: ARRAY OF CHAR;  pub, priv: Key );  
	VAR 
		len: LONGINT;
		n, p1, q1, x, d, e, gcd: Number;
		digest: Buffer;  
		cipher: Ciphers.Cipher;
		md5: MD5.Hash;		
	BEGIN 
		ASSERT( B.Cmp( p, q ) # 0 );
		B.Mul( p, q, n );
		B.Copy( p, p1 );
		B.Dec( p1 );
		B.Copy( q, q1 );
		B.Dec( q1 );
		B.Mul( p1, q1, x );

		B.Assign( e, 3 );  
		LOOP 
			B.GCD( e, x, gcd );  
			IF B.Cmp( gcd, one ) = 0 THEN
				EXIT;
			END;  
			B.Add( e, two, e );
		END;  
		
		B.ModInverse( e, x, d );  

		pub.modulus := n;
		priv.modulus := n;
		pub.exponent := e;
		priv.exponent := d;  
		pub.size := p.len*32;
		priv.size := p.len*32;
		pub.private := FALSE;
		priv.private := TRUE;  
		
		priv.check := priv.exponent.d[0];   (* remember LSL for checking pw *) 
		len := 0;
		WHILE passwd[len] # 0X DO
			INC( len );
		END;
		NEW( md5 );
		md5.Initialize;
		md5.Update( passwd, 0, len );
		md5.GetHash( digest, 0 );
		cipher := Ciphers.NewCipher("AosCryptoIDEA");
		cipher.InitKey( digest, 0, 128 );
		EncryptNumber( priv.exponent, cipher );  
		
		(* Add stuff needed for the chinese remainder theorem to the private key *)
		IF B.Cmp( p, q ) < 0 THEN  (* p < q *)
			B.Copy( p, priv.p );
			B.Copy( q, priv.q );  
			B.ModInverse( priv.p, priv.q, priv.u );  
			EncryptNumber( priv.p, cipher );
			EncryptNumber( priv.q, cipher );
			EncryptNumber( priv.u, cipher  );  
		ELSE 
			B.Copy( q, priv.p );
			B.Copy( p, priv.q );  
			B.ModInverse( priv.p, priv.q, priv.u );  
			EncryptNumber( priv.p, cipher );
			EncryptNumber( priv.q, cipher );
			EncryptNumber( priv.u, cipher );  
		END;  
		
		AosClock.Get( pub.time, pub.date );
		priv.time := pub.time;
		priv.date := pub.date;  
		COPY( name, pub.name );
		COPY( name, priv.name );  
	END MakeKeys;
	
	(** Generate public and private keys out of the large primes p and q, using the specified public exponent e.
		The private key's exponent will be enrypted with IDEA and key passwd *)
	PROCEDURE GetKeys*( VAR p, q, e: Number;  name, passwd: ARRAY OF CHAR;  pub, priv: Key );  
	VAR 
		len: LONGINT;
		n, p1, q1, x, d, gcd: Number;
		digest: Buffer;  
		cipher: Ciphers.Cipher;
		md5: MD5.Hash;		
	BEGIN 
		ASSERT( B.Cmp( p, q ) # 0 );
		B.Mul( p, q, n );
		B.Copy( p, p1 );
		B.Dec( p1 );
		B.Copy( q, q1 );
		B.Dec( q1 );
		B.Mul( p1, q1, x );

		B.ModInverse( e, x, d );  

		pub.modulus := n;
		priv.modulus := n;
		pub.exponent := e;
		priv.exponent := d;  
		pub.size := p.len*32;
		priv.size := p.len*32;
		pub.private := FALSE;
		priv.private := TRUE;  
		
		priv.check := priv.exponent.d[0];   (* remember LSL for checking pw *) 
		len := 0;
		WHILE passwd[len] # 0X DO
			INC( len );
		END;
		NEW( md5 );
		md5.Initialize;
		md5.Update( passwd, 0, len );
		md5.GetHash( digest, 0 );
		cipher := Ciphers.NewCipher("AosCryptoIDEA");
		cipher.InitKey( digest, 0, 128 );
		EncryptNumber( priv.exponent, cipher );  
		
		(* Add stuff needed for the chinese remainder theorem to the private key *)
		IF B.Cmp( p, q ) < 0 THEN  (* p < q *)
			B.Copy( p, priv.p );
			B.Copy( q, priv.q );  
			B.ModInverse( priv.p, priv.q, priv.u );  
			EncryptNumber( priv.p, cipher );
			EncryptNumber( priv.q, cipher );
			EncryptNumber( priv.u, cipher  );  
		ELSE 
			B.Copy( q, priv.p );
			B.Copy( p, priv.q );  
			B.ModInverse( priv.p, priv.q, priv.u );  
			EncryptNumber( priv.p, cipher );
			EncryptNumber( priv.q, cipher );
			EncryptNumber( priv.u, cipher );  
		END;  
		
		AosClock.Get( pub.time, pub.date );
		priv.time := pub.time;
		priv.date := pub.date;  
		COPY( name, pub.name );
		COPY( name, priv.name );  
	END GetKeys;
	
	(** returns a new public key with exponent e and modulus m *)
	PROCEDURE PubKey*( VAR e, m: Number ): Key;
		VAR rsa: Key;
	BEGIN 
		NEW( rsa );
		rsa.name := "unkown";
		rsa.private := FALSE;
		B.Copy( e, rsa.exponent );
		B.Copy( m, rsa.modulus );
		RETURN rsa
	END PubKey;
	
	PROCEDURE ChineseRemainder( VAR result, msg, d, p, q, u: Number );  
	(* 
		d: secret exponent
		p, q: prime factors of n
		u = (1/p)  (mod q)
		Precondition: p < q 
	*)
	VAR
		temp1, temp2, p2, q2: Number;  
	BEGIN 
		ASSERT( B.Cmp( p, q ) < 0, 100 );  
		
		(* p2 := [(msg mod p) ^ (d mod (p-1))] mod p *)
		B.Sub( p, one, temp1 );  
		B.Mod( d, temp1, temp2 );   (* temp2 := d mod (p-1)) *)
		B.Mod( msg, p, temp1 );   (* temp1 := msg mod p *)
		p2 := B.ModExp( temp1, temp2, p );  
		
		(* q2 := [(msg mod q) ^ (d mod (q-1))] mod q *)
		B.Sub( q, one, temp1 );  
		B.Mod( d, temp1, temp2 );   (* temp2 := d mod (q-1)) *)
		B.Mod( msg, q, temp1 );   (* temp1 := msg mod q *)
		q2 := B.ModExp( temp1, temp2, q );  
		
		IF B.Cmp( q2, p2 ) = 0 THEN  (* msg < p *)
			B.Copy( p2, result );
		ELSE 
			WHILE B.Cmp( q2, p2 ) < 0 DO
				B.Add( q2, q, q2 )
			END;  
			B.Sub( q2, p2, q2 );
			B.Mul( q2, u, temp1 );
			B.Mod( temp1, q, temp2 );
			B.Mul( p, temp2, temp1 );  
			B.Add( temp1, p2, result );
		END 
	END ChineseRemainder;  

	PROCEDURE Encrypt*( publicKey: Key;  VAR msg: Number ): Number;  
	BEGIN 
		ASSERT( ~publicKey.private );  
		RETURN B.ModExp( msg, publicKey.exponent, publicKey.modulus );
	END Encrypt;  

	PROCEDURE Decrypt*( privateKey: Key;  passwd: ARRAY OF CHAR;  VAR msg, result: Number ): BOOLEAN;  
	VAR
		d, p, q, u: Number;
		digest: Buffer;
		len: INTEGER;
		cipher: Ciphers.Cipher;
		md5: MD5.Hash;
	BEGIN 
		ASSERT( privateKey.private );
		B.Copy( privateKey.exponent, d );
		len := 0;
		WHILE passwd[len] # 0X DO
			INC( len )
		END;
		NEW( md5 );
		md5.Initialize;
		md5.Update( passwd, 0, len );
		md5.GetHash( digest, 0 );
		cipher := Ciphers.NewCipher("AosCryptoIDEA");
		cipher.InitKey( digest, 0, 128 );
		DecryptNumber( d, cipher );  
		
		IF d.d[0] = privateKey.check THEN 
			IF chinese THEN    (* Using chinese remainder: *)
				B.Copy( privateKey.p, p );  DecryptNumber( p, cipher );  
				B.Copy( privateKey.q, q );  DecryptNumber( q, cipher );  
				B.Copy( privateKey.u, u );  DecryptNumber( u, cipher );  
				ChineseRemainder( result, msg, d, p, q, u )
			ELSE
				result := B.ModExp( msg, d, privateKey.modulus );
			END;  
			RETURN TRUE;
		ELSE
			RETURN FALSE;  (* wrong password *)
		END
	END Decrypt;  

	PROCEDURE Sign*( key: Key;  VAR pwd, digest: ARRAY OF CHAR;  dlen: INTEGER;  VAR signature: Number ): BOOLEAN;  
		VAR msg: Number;  
	BEGIN 
		B.AssignBin( msg, digest, 0, dlen );
		RETURN Decrypt( key, pwd, msg, signature )
	END Sign;  

	PROCEDURE Verify*( rsa: Key;  VAR digest: ARRAY OF CHAR;  dlen: INTEGER;  VAR signature: Number ): BOOLEAN;  
		VAR
			msg: Number;
			i, l: INTEGER;
			buf: Buffer;
	BEGIN 
		ASSERT( dlen >= 16 );
		msg := Encrypt( rsa, signature );
		l := msg.len;
		FOR i := 0 TO 3 DO		l2n( msg.d[l - 1 - i], buf, 4*i )		END;
		FOR i := 0 TO 15 DO 
			IF buf[i] # digest[i] THEN		RETURN FALSE		END;  
		END;
		RETURN TRUE
	END Verify;  
	
	PROCEDURE ReadKey*( VAR r: AosFS.Reader;  k: Key );
	VAR
		s: ARRAY 128 OF CHAR;
		c, l: Certificate;
	BEGIN
		r.String( k.name );
		r.RawBool( k.private );
		r.RawInt( k.size );
		B.FileRead( r, k.exponent );
		B.FileRead( r, k.modulus );
		r.RawLInt( k.check );
		r.RawLInt( k.time );
		r.RawLInt( k.date );
		IF k.private THEN
			B.FileRead( r, k.p );
			B.FileRead( r, k.q );
			B.FileRead( r, k.u );
		END;
		l := NIL;
		r.String( s );
		WHILE s # "EOC" DO
			NEW( c );
			COPY( s, c.authority );
			B.FileRead( r, c.signature );
			IF l = NIL THEN	k.certificates := c
			ELSE	l.next := c	END;
			l := c;
			r.String( s )
		END;
	END ReadKey;

	PROCEDURE WriteKey*( VAR w: AosFS.Writer;  k: Key );
		VAR
			c: Certificate;
			s: ARRAY 4 OF CHAR;
	BEGIN
		w.String( k.name );
		w.RawBool( k.private );
		w.RawInt( k.size );
		B.FileWrite( w, k.exponent );
		B.FileWrite( w, k.modulus );
		w.RawLInt( k.check );
		w.RawLInt( k.time );
		w.RawLInt( k.date );
		IF k.private THEN
			B.FileWrite( w, k.p );
			B.FileWrite( w, k.q );
			B.FileWrite( w, k.u );	
		END;
		c := k.certificates;
		WHILE c # NIL DO
			w.String( c.authority );
			B.FileWrite( w, c.signature );
			c := c.next;
		END;
		s := "EOC";
		w.String( s ) 
	END WriteKey;

BEGIN 
	B.Assign( one, 1 );
	B.Assign( two, 2 );
	
END AosCryptoRSA.

System.Free AosCryptoRSA ~
