MODULE AosCryptoCiphers;	(** AUTHOR "G.F."; PURPOSE "empty cipher"; *)

IMPORT
	AosModules, AosOut;

CONST
	(** cipher modes *)
	ECB* = 0; (** electronic codebook mode *)
	CBC* = 1; (** cipher-block chaining mode *)
	
	(** error codes *)
	Ok* = 0;

TYPE 
	Cipher* = OBJECT
			VAR
			name-: ARRAY 64 OF CHAR;
			blockSize-: LONGINT;   (** cipher block size (bytes) *)
			isKeyInitialized*: BOOLEAN;
			mode-: SHORTINT;   (** ECB, CBC *)
			len1, len2: INTEGER;

		PROCEDURE & Init;  
		BEGIN 
			mode := ECB;
			isKeyInitialized := FALSE;
			SetNameAndBlocksize( "empty cipher",  8 );
		END Init;
		
		(** this method is invoked by subclasses; blocksize in bytes *)
		PROCEDURE SetNameAndBlocksize*( name: ARRAY OF CHAR;  blocksize: LONGINT );  
		BEGIN 
			COPY( name, SELF.name );
			len1 := 0;
			WHILE name[len1] # 0X DO	INC( len1 )	END;
			len2 := len1;
			SELF.blockSize := blocksize;
		END SetNameAndBlocksize;
		
		(** initialize key for encryption and decryption *)
		PROCEDURE InitKey*( VAR src: ARRAY OF CHAR;  pos: LONGINT;  keybits: LONGINT );  
		BEGIN 
			Appsize( keybits );
			isKeyInitialized := TRUE
		END InitKey;  
			
		(** set initialization vector, change mode to CBC; MUST be invoked AFTER Initkey *)
		PROCEDURE SetIV*( VAR src: ARRAY OF CHAR;  pos: LONGINT );  
		BEGIN 
			ASSERT ( isKeyInitialized ); (* InitKey must have been called before *)
			mode := CBC;
			Appmode( "-cbc" )
		END SetIV;  
		
		(** encrypts len bytes of data; len must be a multiple of blockSize *)	 
		PROCEDURE Encrypt*( VAR data: ARRAY OF CHAR; ofs, len: LONGINT );
		BEGIN
			(* empty Cipher does nothing *)
		END Encrypt;
			
		(** decrypts len bytes of data; len must be a multiple of blockSize *)
		PROCEDURE Decrypt*( VAR data: ARRAY OF CHAR; ofs, len: LONGINT );
		BEGIN
			(* empty Cipher does nothing *)
		END Decrypt;

		(* appends size as a string to the name of the cipher *)
		PROCEDURE Appsize( size: LONGINT );  
			VAR
				i, t, d: LONGINT;
				c: CHAR; 
		BEGIN 
			IF (size = 64) OR (size = 128) THEN	RETURN	END; 
			len2 := len1;
			i := 0;
			t := 10000;
			WHILE t > size DO	t := t DIV 10	END;
			REPEAT
				d := size DIV t MOD 10;
				name[len2] := CHR( 48 + d );
				INC( len2 );	
				t := t DIV 10;
			UNTIL t = 0;
			name[len2] := 0X
		END Appsize; 
				
		(* appends the mode as a string to the name of the cipher *)
		PROCEDURE Appmode( str: ARRAY OF CHAR );  
			VAR
				i, j: INTEGER;
				c: CHAR;
		BEGIN 
			j := len2;
			i := 0;
			REPEAT
				c := str[i];
				INC( i );
				name[j] := c;
				INC( j );
			UNTIL c = 0X
		END Appmode;
				
		(* Encrypt a block starting at 'pos' *)
		PROCEDURE EncryptBlock( VAR buf: ARRAY OF CHAR;  pos: LONGINT );  
		BEGIN 
		END EncryptBlock;  
		
		(* Decrypt a block starting at 'pos' *)
		PROCEDURE DecryptBlock( VAR buf: ARRAY OF CHAR;  pos: LONGINT );  
		BEGIN 
		END DecryptBlock;  
	END Cipher;

	(** create a new cipher object of the subtype given in modname*)
	PROCEDURE NewCipher*( modname: ARRAY OF CHAR ): Cipher;  
	VAR
		myProc: AosModules.CommandParProc;
		newCipher: PTR;
	BEGIN 
		myProc := GetCommand( modname, "NewCipher" );
		newCipher := myProc( NIL );
		RETURN newCipher( Cipher )
	END NewCipher;
	
	PROCEDURE GetCommand(modname, procname : ARRAY OF CHAR) : AosModules.CommandParProc;
		VAR i, n, res: LONGINT; msg: ARRAY 64 OF CHAR; mod: AosModules.Module; proc: AosModules.CommandParProc;
	BEGIN
		mod := AosModules.ThisModule(modname, res, msg);
		IF mod # NIL THEN
			RETURN AosModules.ThisCommandPar( mod, procname )
		ELSE
			AosOut.String("Module '"); AosOut.String(modname);  AosOut.String("' has no command '"); AosOut.String(procname);
			AosOut.String("'"); AosOut.Ln
		END;
		RETURN NIL
	END GetCommand;
	
END AosCryptoCiphers.


System.Free AosCryptoCiphers ~
