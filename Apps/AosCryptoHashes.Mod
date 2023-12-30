MODULE AosCryptoHashes;	(** AUTHOR "G.F."; PURPOSE "Empty Hash"; *)

IMPORT
	AosModules, AosOut;

TYPE
	Hash* = OBJECT
		VAR
			name-: ARRAY 64 OF CHAR;
			size-: LONGINT;
			initialized*: BOOLEAN;
			
		PROCEDURE &Init*;
		BEGIN
			initialized := FALSE
		END Init;

		PROCEDURE Initialize*;
		BEGIN
			HALT(301) (* force overwriting *)
		END Initialize;
			
		(** this method is invoked by subclasses *)
		PROCEDURE SetNameAndSize*(name: ARRAY OF CHAR; size: LONGINT);
		BEGIN
			COPY(name, SELF.name);
			SELF.size := size
		END SetNameAndSize;
		
		(** data: value to be hashed; when Update is invoked several times before GetHash or Initialize
			is invoked, the concatenation of all data-parameters is hashed *)
		PROCEDURE Update*( VAR data: ARRAY OF CHAR; ofs, len: LONGINT );
		BEGIN
			HALT(301) (* force overwriting *)
		END Update;
		
		(** get the hashvalue of length SELF.size *)
		PROCEDURE GetHash*(VAR buffer: ARRAY OF CHAR; position: LONGINT);
		BEGIN
			HALT(301) (* force overwriting *)
		END GetHash;

	END Hash;

	(** get a new hash from module 'modname' *)
	PROCEDURE NewHash*( modname: ARRAY OF CHAR ): Hash;  
	VAR
		myProc: AosModules.CommandParProc;
		newHash: PTR;
		tempString: ARRAY 64 OF CHAR;
	BEGIN 
		ASSERT( LEN( modname ) < 57 );
		myProc := GetCommand( modname, "NewHash" );
		newHash := myProc( NIL );
		RETURN newHash( Hash )
	END NewHash;
	
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
	
END AosCryptoHashes.


System.Free AosCryptoHashes~