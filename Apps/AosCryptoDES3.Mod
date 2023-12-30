MODULE AosCryptoDES3;	(** AUTHOR "G.F."; PURPOSE "Triple Data Encryption Standard 3DES"; *)

IMPORT
	S := SYSTEM,	Ciphers := AosCryptoCiphers,	DES := AosCryptoDES,	BIT,	Out := AosOut;
	 
TYPE
	Block = ARRAY 8 OF CHAR;
	
	Cipher* = OBJECT (Ciphers.Cipher)
	VAR
		c1, c2, c3: DES.Cipher;
		iv: Block;
				
		PROCEDURE & Init;  
		BEGIN 
			SetNameAndBlocksize( "3des", 8 ); 
			NEW( c1 );
			NEW( c2 );
			NEW( c3 );
			isKeyInitialized := FALSE
		END Init;
		
		(** initialize DES keys. keybits MUST be equal to 192 *)
		PROCEDURE InitKey*( VAR src: ARRAY OF CHAR;  ofs, keybits: LONGINT );  
		BEGIN 
			ASSERT( keybits = 192 );  
			InitKey^( src, ofs, 64 ); 
			c1.InitKey( src, 0, 64 );
			c2.InitKey( src, 8, 64 );
			c3.InitKey( src, 16, 64 );
			isKeyInitialized := TRUE
		END InitKey;  

		(** set initialization vector for CBC mode *)
		PROCEDURE SetIV*( VAR src: ARRAY OF CHAR;  ofs: LONGINT );  
			VAR i: LONGINT;
		BEGIN
			ASSERT( isKeyInitialized );
			SetIV^( src, ofs ); (* set mode *)
			FOR i := 0 TO 7 DO	iv[ i ] := src[ ofs + i ]	END
		END SetIV;  

		(** encrypt len bytes starting at position ofs. len must be multiple of blockSize *)
		PROCEDURE Encrypt*( VAR buf: ARRAY OF CHAR; ofs, len: LONGINT );
			VAR i: LONGINT;
		BEGIN
			ASSERT( len MOD blockSize = 0 ); (* padding must have been added *)
			IF mode = Ciphers.ECB THEN
				c1.Encrypt( buf, ofs, len );
				c2.Decrypt( buf, ofs, len);
				c3.Encrypt( buf, ofs, len )
			ELSE	(* CBC *)
				i := 0;
				WHILE i < len DO (* for each block *)
					EncryptBlock( buf, ofs+i );
					INC( i, blockSize )
				END
			END
		END Encrypt;
		
		(** decrypt len bytes starting at position ofs. len must be multiple of blockSize *)
		PROCEDURE Decrypt*( VAR buf: ARRAY OF CHAR; ofs, len: LONGINT );
			VAR i: LONGINT;
		BEGIN
			ASSERT( len MOD blockSize = 0 ); (* padding must have been added *)
			IF mode = Ciphers.ECB THEN
				c1.Decrypt( buf, ofs, len );
				c2.Encrypt( buf, ofs, len);
				c3.Decrypt( buf, ofs, len )
			ELSE
				i := 0;
				WHILE i < len DO (* for each block *)
					DecryptBlock( buf, ofs+i );
					INC( i, blockSize )
				END
			END
		END Decrypt;

		(* Encrypt single block starting at position p; use only in CBC mode *)
		PROCEDURE EncryptBlock( VAR data: ARRAY OF CHAR;  ofs: LONGINT );  
			VAR
				b: Block;
				i: LONGINT;
		BEGIN
			IF mode = Ciphers.ECB THEN
				c1.Encrypt( data, ofs, 8 );
				c2.Decrypt( data, ofs, 8 );
				c3.Encrypt( data, ofs, 8 )
			ELSE	(* CBC *)
				FOR i := 0 TO 7 DO	b[ i ] := BIT.CXOR( data[ ofs + i ], iv[ i ] )	END;
				c1.Encrypt( b, 0, 8 );
				c2.Decrypt( b, 0, 8 );
				c3.Encrypt( b, 0, 8 );
				FOR i := 0 TO 7 DO
					data[ ofs + i ] := b[ i ];
					iv[ i ] := b[ i ] 
				END
			END
		END EncryptBlock;  

		(* Decrypt single block starting at position p; use only in CBC mode *)
		PROCEDURE DecryptBlock( VAR data: ARRAY OF CHAR;  ofs: LONGINT );  
			VAR
				b: Block;
				i: LONGINT;
		BEGIN
			IF mode = Ciphers.ECB THEN
				c1.Decrypt( data, ofs, 8 );
				c2.Encrypt( data, ofs, 8 );
				c3.Decrypt( data, ofs, 8 );
			ELSE	(* CBC *)
				FOR i := 0 TO 7 DO	b[ i ] := data[ ofs + i ]	END;
				c1.Decrypt( b, 0, 8 );
				c2.Encrypt( b, 0, 8 );
				c3.Decrypt( b, 0, 8 );
				FOR i := 0 TO 7 DO
					data[ ofs + i ] := BIT.CXOR( data[ ofs + i ], iv[ i ] );
					iv[ i ] := b[ i ]
				END
			END
		END DecryptBlock;  

	END Cipher;  
	
	(** create a new triple-DES cipher object *)
	PROCEDURE NewCipher*( par: PTR ): PTR;  
		VAR c: Cipher;  
	BEGIN 
		NEW( c );		RETURN c
	END NewCipher;  

END AosCryptoDES3.
 

System.Free AosCryptoDES3 ~