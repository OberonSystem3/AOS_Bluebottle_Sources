MODULE TLS;	(** AUTHOR "F.N."; PURPOSE "RFC 2246: Transport Layer Security v1.0"; *)

IMPORT
	AosTCP, AosIO, AosFS, AosIP, AosOut , AosPipes, AosKernel, AosClock, BIT, 
	Ciphers := AosCryptoCiphers, Utils := AosCryptoUtils, HMAC := AosCryptoHMAC, 
	AosCryptoMD5, AosCryptoSHA1, AosCryptoRSA, AosCryptoBigNumbers;
		
CONST
	(* debugging *)
	Trace = TRUE;
	
	(** tlsStates *)
	ServerHandshake* = 12; 
		
	(* server-side handshake states *)
	NotAValidHandshakeState = 200; HandshakeFinished = 215;
	AwaitClientHello = 201; GenerateServerHello = 202; GenerateServerHelloDone = 203; AwaitClientKeyExchange = 204;
	AwaitChangeSpec = 205; AwaitFinished = 206; GenerateChangeCipherSpec = 207; GenerateHelloWithResumption = 210;
	AwaitChangeSpecWithResumption = 211; AwaitFinishedWithResumption = 212;
	
	(** available cipher suites *)
	TlsRsaWithNullMd5* = 0001H; TlsRsaWithNullSha* = 0002H; TlsRsaWithRc4128Md5* = 0004H;
	TlsRsaWithRc4128Sha* = 0005H; TlsRsaWithIdeaCbcSha* = 0007H; TlsRsaWithDesCbcSha* = 0009H;
	TlsRsaWith3DesEdeCbcSha* = 000AH;
	(*	not supported
	TlsDhDssWithDesCbcSha* = 000CH; TlsDhDssWith3DesEdeCbcSha* = 000DH;
	TlsDhRsaWithDesCbcSha* = 000FH; TlsDhRsaWith3DesEdeCbcSha* = 0010H;
	TlsDhAnonWithRc4128Md5* = 0018H; TlsDhAnonWithDesCbcSha* = 001AH; TlsDhAnonWith3DesEdeCbcSha* = 001BH;	
	*)
	
	(** record layer content type *)
	ChangeCipherSpec* = 20; Alert* = 21; Handshake* = 22; ApplicationData* = 23; SSLv2ClientHello* = 128;
	
	(** handshake message types *)
	HelloRequest* = 0; ClientHello* = 1; ServerHello* = 2; Certificate* = 11;
	ServerKeyExchange* = 12; CertificateRequest* = 13; ServerHelloDone* = 14; CertificateVerify* = 15;
	ClientKeyExchange* = 16; Finished* = 20;
	V2ClientHello* = 30;
	
	(* alert levels *)
	Warning = 1; Fatal = 2;
	
	(* alert types *)
	NoError = -1;
	CloseNotify = 0; UnexpectedMessage = 10; BadRecordMac = 20; DecryptionFailed = 21;
	RecordOverflow = 22; DecompressionFailure = 30; HandshakeFailure = 40; NoCertificate = 41; (* only SSL 3.0 *)
	BadCertificate = 42; UnsupportedCertificate = 43; CertificateRevoked = 44; CertificateExpired = 45;
	CertificateUnknown = 46; IllegalParameter = 47; UnknownCA = 48; AccessDenied = 49;
	DecodeError = 50; DecryptError = 51; ExportRestriction = 60; ProtocolVersion = 70;
	InsufficientSecurity = 71; InternalError = 80; UserCancelled = 90; NoRenegotiation = 100;
	
	(** error numbers *)
	Ok* = 0; TLSHandshakeAborted* = 2; 
	
	Suites* = 20;
	Buflen = 18500;
	MaxPHashAosOutput = 1024;
	MaxKeyBlock = 120;
	MaxPHashSeed = 128;
	MaxPlaintextLength = 16384; 	(* 2^14 *)
	MaxCompressedLength = 17408;	(* 2^14 + 2^10 *)
	MaxCiphertextLength = 18432;	(* 2^14 + 2^11 *)
	SessionIdLength = 16;
	SessionHashtableSize = 1023;	(* 256 * 456 *)
	SessionCleanUpInterval = 60;	(* seconds *)
	DefaultSessionLifetime = 3600; (* seconds *)
		

TYPE
	SecurityParameters = OBJECT
		VAR
			cipherSuite, cipherKeySize: LONGINT;	(* size in bytes *)
			clientRandom, serverRandom: ARRAY 32 OF CHAR;
	END SecurityParameters;
		
	ConnectionState = OBJECT
		VAR
			cipher: Ciphers.Cipher;
			mac: HMAC.HMac;
			recordSeq: DoubleLong;
			cipherKey: ARRAY 24 OF CHAR;
			iv: ARRAY 8 OF CHAR;
			macSecret: ARRAY 20 OF CHAR;
				
		PROCEDURE & Init;
		BEGIN
			NEW( recordSeq)
		END Init;
	END ConnectionState;
		
	DoubleLong = OBJECT	(* 64-bit number, the initial value is -1 *)	
		VAR num -: ARRAY 2 OF LONGINT;	(* 64 bits, msb: num[ 0 ] *)
		
		PROCEDURE & Init;
		BEGIN
			num[ 0 ] := 0;	num[ 1 ] := -1
		END Init;
		
		PROCEDURE Inc;
		BEGIN
			ASSERT( ( num[ 0 ] < MAX( LONGINT ) ) OR ( num[ 1 ] < MAX( LONGINT ) ) );
			IF num[ 1 ] < MAX( LONGINT ) THEN
				INC( num[ 1 ] );
				RETURN
			ELSE
				num[ 1 ] := 0;
				INC( num[ 0 ] )
			END
		END Inc;
			
		(* write the current value of num in big-endian to data starting at ofs *)
		PROCEDURE GetBytes( VAR data: ARRAY OF CHAR; ofs: LONGINT );
		BEGIN
			ASSERT( ofs < LEN( data ) - 7 );
			data[ ofs ] := CHR( num[ 0 ] DIV ( 256*256*256 ) );
			data[ ofs + 1 ] := CHR( num[ 0 ] DIV ( 256*256 ) );
			data[ ofs + 2 ] := CHR( num[ 0 ] DIV 256 );
			data[ ofs + 3 ] := CHR( num[ 0 ] );
			data[ ofs + 4 ] := CHR( num[ 1 ] DIV ( 256*256*256 ) );
			data[ ofs + 5 ] := CHR( num[ 1 ] DIV ( 256*256 ) );
			data[ ofs + 6 ] := CHR( num[ 1 ] DIV 256 );
			data[ ofs + 7 ] := CHR( num[ 1 ] )
		END GetBytes;
	END DoubleLong;

	(* data expansion function as defined in rfc2246, section 5 *)
	PHash = OBJECT
		VAR hMac: HMAC.HMac;
			
		(* initialization of a PHash object using h as internal hashing-function *)
		PROCEDURE & Init( hashname: ARRAY OF CHAR );
		BEGIN
			NEW( hMac, hashname );
		END Init;
		
		PROCEDURE Expand( VAR secret, seed, outbuf: ARRAY OF CHAR; secretLen, seedLen, outLen: LONGINT );
			VAR
				a: ARRAY 2 * MaxPHashSeed OF CHAR;
				i, iterations: LONGINT;
		BEGIN
			ASSERT( seedLen <= ( MaxPHashSeed  ) );
			ASSERT( outLen <= ( MaxPHashAosOutput ) );
			hMac.Initialize( secret, secretLen );
			hMac.Update( seed, 0, seedLen );
			hMac.GetMac( a, 0 );	(* a( 1 ) *)
					FOR i := 0 TO seedLen-1 DO		a[ hMac.size + i ] := seed[ i ]		END;	(* concatenate seed to a( 1 ) *)
			iterations := ( outLen DIV hMac.size ) + 1;
			(* iteration *)
			FOR i := 0 TO iterations - 1 DO
				hMac.Initialize( secret, secretLen );
				hMac.Update( a, 0, hMac.size+seedLen );
				hMac.GetMac( outbuf, i*hMac.size );
				(* increment a *)
				hMac.Initialize( secret, secretLen );
				hMac.Update( a, 0, hMac.size );
				hMac.GetMac( a, 0 )
			END
		END Expand;
	END PHash;

	(* pseudorandom stream as defined in rfc2246, section 5 *)
	PRF = OBJECT
		VAR pMD5, pSHA: PHash;
	
		PROCEDURE & Init;
		BEGIN
			NEW( pMD5, "AosCryptoMD5" );	NEW( pSHA, "AosCryptoSHA1" )
		END Init;
		
		PROCEDURE GetBytes( VAR secret, seed, outbuf: ARRAY OF CHAR; label: ARRAY OF CHAR; secretLen, seedLen, outLen: LONGINT );
			VAR
				md5Result, shaResult: ARRAY MaxKeyBlock OF CHAR;
				pSeed, s1, s2: ARRAY 128 OF CHAR;
				i, j, l: LONGINT;
		BEGIN
			(* pseed := label::seed *)
			l :=  LEN( label ) - 1;
			FOR i := 0 TO l-1 DO	pSeed[ i ] := label[ i ]	END;
			FOR i := 0 TO seedLen-1 DO	pSeed[ l + i ] := seed[ i ]	END;
			
			j := secretLen DIV 2 + secretLen MOD 2;	(* j := ceil( secretLen / 2 ) *)
			FOR i := 0 TO j-1 DO			s1[ i ] := secret[ i ]			END;
			FOR i := secretLen-j TO secretLen-1 DO		s2[ i+j-secretLen ] := secret[ i ]		END;
			
			pMD5.Expand( s1, pSeed, md5Result, j, seedLen+l, outLen );
			pSHA.Expand( s2, pSeed, shaResult, j, seedLen+l, outLen );
			
			FOR i := 0 TO outLen-1 DO	outbuf[ i ] := BIT.CXOR( md5Result[ i ], shaResult[ i ] )	END
		END  GetBytes;
	END PRF;
						
	Policy* = OBJECT
		VAR
			cipherSuites -: ARRAY Suites OF LONGINT;
			nofCipherSuites -: LONGINT;	(** number of enabled cipher-suites *)
			sessionResumptionEnabled -: BOOLEAN;
			sessionLifetime -: LONGINT; (** seconds *)
				
		PROCEDURE &Init;
		BEGIN
			(* set default values *)
			sessionResumptionEnabled := TRUE;
			sessionLifetime := DefaultSessionLifetime
		END Init;
				
		(** set n negotiable cipher suites in order of preference*)
		PROCEDURE SetCipherSuites*( VAR s: ARRAY OF LONGINT; n: LONGINT );
			VAR i: LONGINT;
		BEGIN
			ASSERT( n <= Suites ); 
			FOR i := 0 TO n-1 DO cipherSuites[ i ] := s[ i ] END;
			nofCipherSuites := n
		END SetCipherSuites;
			
		(** Returns TRUE if the cipher-suite s is supported by this policy *)
		PROCEDURE IsSupported*( s: LONGINT ): BOOLEAN;
			VAR i: LONGINT;
		BEGIN
			FOR i := 0 TO nofCipherSuites - 1 DO
				IF cipherSuites[ i ] = s THEN RETURN TRUE END
			END;
			RETURN FALSE
		END IsSupported;
			
		(** set whether sessions may be resumed; default is TRUE *)
		PROCEDURE EnableSessionResumption*( enable: BOOLEAN );
		BEGIN	sessionResumptionEnabled := enable
		END EnableSessionResumption;

		(** lifetime of a session in seconds; default: 3600s *)	
		PROCEDURE SetSessionLifetime*( t: LONGINT );
		BEGIN
			ASSERT( t >= 0 );
			sessionLifetime := t
		END SetSessionLifetime;
		
	END Policy;
		
	Session = OBJECT
		VAR
			id : ARRAY 32 OF CHAR;
			idLength : LONGINT;
			resumable : BOOLEAN;
			cipherSuite : LONGINT;
			preMasterSecret, masterSecret -: ARRAY 48 OF CHAR;
			lifetime: LONGINT;	(* seconds *)
			timer: AosKernel.Timer;
			next: Session;
								
		(** initialize a session.
			If caching is FALSE, no session-id will associated with the new session.
			if cache is TRUE and len is zero, a session id will be randomly generated.
			if cache is TRUE and len is non-zero, a session-id will be read from data *)
		PROCEDURE & Init( caching: BOOLEAN; VAR data: ARRAY OF CHAR; ofs, len, lifetime: LONGINT );
			VAR i: LONGINT;
		BEGIN
			ASSERT( ofs > -1 );	ASSERT( len > -1 );	ASSERT( ofs + len <= LEN( data ) );	ASSERT( lifetime > 0 );
			resumable := caching;
			IF caching THEN
				IF len = 0 THEN	(* server-side: session-id has to be generated *)
					idLength := SessionIdLength;
					Utils.RandomBytes( id, 0, SessionIdLength )
				ELSE	(* client-side: session-id has been generated by server *)
					idLength := len;
				FOR i := 0 TO len - 1 DO		id[ i ] := data[ ofs + i ]		END
				END
			END;
			cipherSuite := 0;
			SELF.lifetime := lifetime
		END Init;
			
		(** Marks this Session as not resumable for future Connections *)
		PROCEDURE Invalidate;
		BEGIN
			resumable := FALSE
		END Invalidate;
		
		(** Sets the PreMasterSecret contained in data, starting at ofs. The lenght of the PreMasterSecret is always 48 bytes *)
		PROCEDURE SetPreMasterSecret( data: ARRAY OF CHAR; ofs: LONGINT );
			VAR i: LONGINT;
		BEGIN
			ASSERT( LEN(data) >= ofs + 48 );
			FOR i := 0 TO 47 DO		preMasterSecret[ i ] := data[ ofs + i ]		END
		END SetPreMasterSecret;
			
	BEGIN { ACTIVE }
		NEW( timer );
		timer.Sleep( 1000 * lifetime );
		Invalidate( )
		
	END Session;
		
	Context* = OBJECT
		VAR
			policy-: Policy;
			rsaCertificate: ARRAY 10000 OF CHAR;
			rsaPrivateKey: AosCryptoRSA.Key;
			lengthOfRsaCertificate: LONGINT;
			sessionCache: ARRAY SessionHashtableSize OF Session;
			timer: AosKernel.Timer;
			active: BOOLEAN;
		
		PROCEDURE & Init*( p: Policy );
		BEGIN
			policy := p;
		NEW( timer );
				active := TRUE
		END Init;
		
		PROCEDURE Dispose*;
			BEGIN
			active := FALSE
		END Dispose;
		
		(** Loads the rsa-certificate specified with filename. The certificate must be DER-formatted *)
		PROCEDURE LoadRsaCertificate*( filename: ARRAY OF CHAR ): LONGINT;
			VAR
				f: AosFS.File;
				r: AosFS.Reader;
				i: LONGINT;
		BEGIN
			f := AosFS.Old(filename);	(* open an old file *)
			IF f # NIL THEN
				AosFS.OpenReader( r, f, 0);	(* open a buffer on the file *)
				i := 0;
				WHILE r.res # AosIO.EOF DO
					rsaCertificate[ i + 6 ] := r.Get( );	(* first six bytes are length-fields of the certificate *)
					INC( i )
				END;
				lengthOfRsaCertificate := i-1;
				IF Trace THEN PrintRsaCertificate( ) END;
				(* length-fields *)
				rsaCertificate[ 0 ] := CHR( ( lengthOfRsaCertificate + 3 ) DIV ( 256 * 256 ) );
				rsaCertificate[ 1 ] := CHR( ( lengthOfRsaCertificate + 3 ) DIV 256 MOD 256 );
				rsaCertificate[ 2 ] := CHR( ( lengthOfRsaCertificate + 3 ) MOD 256 );
				rsaCertificate[ 3 ] := CHR( ( lengthOfRsaCertificate ) DIV ( 256 * 256 ) );
				rsaCertificate[ 4 ] := CHR( ( lengthOfRsaCertificate ) DIV 256 MOD 256 );
				rsaCertificate[ 5 ] := CHR( ( lengthOfRsaCertificate ) MOD 256 );
				INC( lengthOfRsaCertificate, 6 );
				RETURN Ok
			ELSE
				AosOut.String("RSA Certificate file not found"); AosOut.Ln;
				RETURN -1;
			END
		END LoadRsaCertificate;
			
		(** Loads the material needed to establish an rsa private key. Parameters p and q are two big prime numbers,
			e is the public exponent of the public key of the rsa certificate to be used. p, q and e have to be hexadecimal strings.
			pLen, qLen and eLen are the lengths of the hex strings *)
		PROCEDURE LoadRsaPrivateKey*( pHex, qHex, eHex: ARRAY OF CHAR; pLen, qLen, eLen: INTEGER );
			VAR
				p, q, e: AosCryptoBigNumbers.BigNumber;
				dummy: AosCryptoRSA.Key;
		BEGIN
			AosCryptoBigNumbers.AssignHex( p, pHex, pLen );
			AosCryptoBigNumbers.AssignHex( q, qHex, qLen );
			AosCryptoBigNumbers.AssignHex( e, eHex, eLen );
			NEW( SELF.rsaPrivateKey );	NEW( dummy );
			AosCryptoRSA.GetKeys( p, q, e, "AosTLS", "password", dummy, SELF.rsaPrivateKey );
			IF Trace THEN
				AosOut.String("RSA-key loaded"); AosOut.Ln;
				AosOut.String("   prime p:"); AosOut.Ln;
				AosCryptoBigNumbers.Print( p );
				AosOut.String("   prime q:"); AosOut.Ln;
				AosCryptoBigNumbers.Print( q );
				AosOut.String("   public exponent:"); AosOut.Ln;
				AosCryptoBigNumbers.Print( e );
				AosOut.String("   modulus:"); AosOut.Ln;
				AosCryptoBigNumbers.Print( SELF.rsaPrivateKey.modulus );
				AosOut.String("   private exponent:"); AosOut.Ln;
				AosCryptoBigNumbers.Print( SELF.rsaPrivateKey.exponent );
			END
		END LoadRsaPrivateKey;
			
		PROCEDURE  PrintRsaCertificate*;
		BEGIN
			AosOut.String("Certificate [");AosOut.Int(lengthOfRsaCertificate,3);AosOut.String("]");AosOut.Ln;
			AosOut.Buffer(rsaCertificate, 6, lengthOfRsaCertificate )
		END PrintRsaCertificate;
			
		(** A new server-side Session-object is created and returned according to the policy settings *)
		PROCEDURE GetNewServerSession*( ): Session;
			VAR
				dummy: ARRAY 1 OF CHAR;
				s: Session;
		BEGIN
			NEW( s, policy.sessionResumptionEnabled, dummy, 0, 0, policy.sessionLifetime );
			RETURN s
		END GetNewServerSession;
		
		(** look up the session cache for a stored cache associated with the session-id of length len,
			starting at ofs in data. If no session is found, NIL is returned. This method is invoked by a TLS-server. *)
		PROCEDURE FindSessionByID*( VAR data: ARRAY OF CHAR; ofs, idLen: LONGINT ): Session;
			VAR 
				i: LONGINT;
				current, previous: Session;	(* fork search *)
		BEGIN
			ASSERT( idLen = SessionIdLength );	
			ASSERT( idLen < 33 );	ASSERT( idLen >= 2  );	ASSERT( ofs > -1 );	ASSERT( LEN( data )  >= ofs + idLen ); 
			IF ~policy.sessionResumptionEnabled THEN RETURN NIL END;
			i := ( ORD( data[ ofs ] ) + 256 * ORD( data[ ofs + 1 ] ) ) MOD SessionHashtableSize;
			current := sessionCache[ i ];
			previous := sessionCache[ i ];
			WHILE current # NIL DO
				IF EqualSessionID( current.id, data, 0, ofs, idLen ) THEN
					IF current.resumable THEN
						IF current # previous THEN	(* if current is NOT the first element in the list *)
							previous.next := current.next;
							current.next := sessionCache[ i ];
							sessionCache[ i ] := current
						END;
						RETURN current
					ELSE 
						RETURN NIL 
					END
				ELSE
					previous := current;
					current := current.next
				END
			END;
			RETURN NIL
		END FindSessionByID;
			
		(* stores a given Session-object in the session-cache *)
		PROCEDURE StoreSession( s: Session );
			VAR i: LONGINT;
		BEGIN
			ASSERT( s.resumable );
			i := ORD( s.id[ 0 ] ) + 256 * ORD( s.id[ 1 ] );
			i := i MOD SessionHashtableSize;
			s.next := sessionCache[ i ];
			sessionCache[ i ] := s
		END StoreSession;
			
		(* returns TRUE iff data1 and data2 contain the same string of length len starting at different offsets *)
		PROCEDURE EqualSessionID( VAR data1, data2: ARRAY OF CHAR; ofs1, ofs2, len: LONGINT ): BOOLEAN;
			VAR i: LONGINT;
		BEGIN
			FOR i := 0 TO len - 1 DO
				IF data1[ ofs1 + i ] # data2[ ofs2 + i ] THEN RETURN FALSE END;
			END;
			RETURN TRUE
		END EqualSessionID;
			
		(* recursive function *)
		PROCEDURE DeleteUnresumableSessions( s: Session ): Session;
		BEGIN
			IF s = NIL THEN RETURN NIL END;	(* end of recursion *)
			IF s.resumable THEN
				s.next := DeleteUnresumableSessions( s.next );
				RETURN s
			ELSE
				RETURN DeleteUnresumableSessions( s.next )
			END
		END DeleteUnresumableSessions;
			
		(* delete unresumable sessions *)
		PROCEDURE CleanUpSessionCache;
			VAR i: LONGINT;
		BEGIN
			FOR i := 0 TO SessionHashtableSize - 1 DO
				sessionCache[ i ] := DeleteUnresumableSessions( sessionCache[ i ] )
			END
		END CleanUpSessionCache;
		
	BEGIN { ACTIVE }
		WHILE active DO
			timer.Sleep( SessionCleanUpInterval * 1000 );
			CleanUpSessionCache( )
		END
		
	END Context;
	
	Connection* = OBJECT ( AosTCP.Connection )
		VAR
			conn: AosTCP.Connection;
			in: AosIO.Reader;
			out, appDataWriter: AosIO.Writer;
			appDataReader: AosIO.Reader;
			applicationDataPipe: AosPipes.Pipe;
			context: Context;
			session: Session;
			tlsErrorCause -: LONGINT;	(** alert type that lead to failure *)
			handshakeState: LONGINT;
			outbuf, inbuf: ARRAY Buflen OF CHAR; (* buffers for outgoing and incoming messages *)
			hsMD5send, hsMD5verify: AosCryptoMD5.Hash;	(* handshake hash functions; to be used in the Finished messages *)
			hsSHAsend, hsSHAverify: AosCryptoSHA1.Hash;	(* handshake hash functions; to be used in the Finished messages *)
			pendingSecurityParameters: SecurityParameters;
			currentWriteState, pendingWriteState, currentReadState, pendingReadState: ConnectionState;
			
		PROCEDURE &Init*;
		BEGIN
			state := AosTCP.Unused;
			tlsErrorCause := NoError;
			(* establish application-data-out-buffer *)
			NEW( applicationDataPipe, 4096 ); (* is this a good size? *)
			AosIO.OpenWriter( appDataWriter, applicationDataPipe.Send );
			AosIO.OpenReader( appDataReader, applicationDataPipe.Receive );
			NEW( hsMD5send );	NEW( hsSHAsend );
			NEW( hsMD5verify );	NEW( hsSHAverify );
			NEW( pendingWriteState );	NEW( currentWriteState );
			NEW( pendingReadState );	NEW( currentReadState );
			NEW( pendingSecurityParameters );
		END Init;
			
		

		PROCEDURE AwaitStateNotEqual*(s : LONGINT);
		BEGIN { EXCLUSIVE}
			AWAIT(state # s);
		END AwaitStateNotEqual;	

		PROCEDURE AwaitStateEqual*(s : LONGINT);
		BEGIN { EXCLUSIVE}
			AWAIT(state = s);
		END AwaitStateEqual;	

		PROCEDURE SetState*(s : SHORTINT);
		BEGIN { EXCLUSIVE}
			state := s;
		END SetState;	
			
		PROCEDURE ChangeWriteState;
		BEGIN
			currentWriteState := pendingWriteState;
			NEW( pendingWriteState )
		END ChangeWriteState;
			
		PROCEDURE ChangeReadState;
		BEGIN
			currentReadState := pendingReadState;
			NEW( pendingReadState )
		END ChangeReadState;
		
		(** Must be called before Open *)
		PROCEDURE SetContext*( cxt: Context  );
		BEGIN
			ASSERT( conn = NIL );
			context := cxt
		END SetContext;
			
		(** open a TLS connection (only use once per Connection instance). Use AosIP.NilPort for lport to automatically assign
		an unused local port. Use AosIP.NilAdr for fip to open a passive connection. *)
		PROCEDURE Open*(  lport: LONGINT; fip: AosIP.Adr; fport: LONGINT; VAR res: LONGINT );
		BEGIN
			ASSERT( AosIP.IsNilAdr(fip) );	(* only server-side is implemented *)
			ASSERT( context # NIL );	(* context must be set before calling Open *)
			ASSERT( conn = NIL );	(* invoke this method only once per instance *)
			IF Trace THEN AosOut.String("Connection.Open");AosOut.Ln END;
			(* open AosTCPConnection *)
			NEW( SELF.conn );
			SELF.conn.Open( lport, fip, fport, res );	
			IF res # AosTCP.Ok THEN RETURN END;
			SetState(conn.state);
			res := Ok;
			ASSERT( conn # NIL )
		END Open;
			
		(* set a TCP Connection for communication; this method should only be invoked by the Accept-method *)
		PROCEDURE SetConnection*( c: AosTCP.Connection );
		BEGIN
			ASSERT( conn = NIL );	ASSERT( State()= AosTCP.Unused );
			conn := c;
			AosIO.OpenReader( in, SELF.conn.Receive );	AosIO.OpenWriter( out, SELF.conn.Send );
			SetState(ServerHandshake);
			handshakeState := AwaitClientHello
		END SetConnection;
			
		(** Call this method only on a passive (listenig server-side) TLS.Connection. Non blocking *)
		PROCEDURE Accept*( VAR client: AosTCP.Connection; VAR res: LONGINT );
			VAR
				newTLSConn: Connection;
				newTCPConn: AosTCP.Connection;
		BEGIN
			ASSERT( State() = AosTCP.Listen ); 
			ASSERT ( SELF.conn # NIL );
			SELF.conn.Accept( newTCPConn, res );
			IF res # AosTCP.Ok THEN RETURN END;
			NEW( newTLSConn );
			newTLSConn.SetContext( SELF.context );
			newTLSConn.SetConnection( newTCPConn );
			client := newTLSConn;
			res := Ok
		END Accept;
			
		(** Close this TLS.Connection *)
		PROCEDURE Close*;
		BEGIN
			IF Trace THEN AosOut.String("Close"); AosOut.Ln; END;
			ASSERT( SELF.conn # NIL );
			IF ( State() = AosTCP.Established ) OR ( State() = ServerHandshake ) THEN
				SendWarning( CloseNotify )
			END;
			conn.Close();
			applicationDataPipe.Close();
			handshakeState := NotAValidHandshakeState;
			SetState(AosTCP.Closed);
		END Close;
		
		(** Send secured data *)
		PROCEDURE Send*( VAR data: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT );
			VAR i, size: LONGINT;
		BEGIN {EXCLUSIVE}
			AWAIT((state = AosTCP.Established) OR (state = AosTCP.Closed));
			IF state = AosTCP.Established THEN
				WHILE len > 0 DO
					IF Trace THEN AosOut.String("S  >  C Application Data");AosOut.Ln END;
					size := len;
					IF size > MaxPlaintextLength THEN		size := MaxPlaintextLength		END;
					FOR i := 0 TO size-1 DO
						outbuf[ i ] := data[ ofs + i ]
					END;
					SendRecord( outbuf, ApplicationData, 0, size );
					INC( ofs, size );
					DEC( len, size )
				END
			ELSE
				res := AosIO.EOF;
			END;
		END Send;
		
		(** Receive secured data *)		
		PROCEDURE Receive*( VAR data: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT );
		BEGIN
			applicationDataPipe.Receive(data, ofs, size, min, len ,res);
		END Receive;
			
		(* Generates the MasterSecret for the current session as described in rfc 2246, section 8 *)
		PROCEDURE GenerateMasterSecret;
			VAR
				prf: PRF;
				seed: ARRAY 64 OF CHAR;
				i: LONGINT;
		BEGIN
			FOR i := 0 TO 31 DO
				seed[ i ] := SELF.pendingSecurityParameters.clientRandom[ i ];
				seed[ i + 32 ] := SELF.pendingSecurityParameters.serverRandom[ i ]
			END;
			NEW( prf );
			prf.GetBytes( SELF.session.preMasterSecret, seed, SELF.session.masterSecret, "master secret", 48, 64, 48 );
			(* discard preMasterSecret *)
			FOR i := 0 TO 47 DO	SELF.session.preMasterSecret[ i ] := CHR( 0 )	END
		END GenerateMasterSecret;
			
		(* Generates key-material for the pending state *)
		PROCEDURE GenerateKeys;
			VAR
				prf: PRF;
				keyBlock: ARRAY 104 OF CHAR;
				seed: ARRAY 64 OF CHAR;
				i, keyBlockLen, ofs, macSecretSize, cipherKeySize, cipherBlockSize: LONGINT;
		BEGIN
			(* calculate the needed amount of key-material *)
			macSecretSize := SELF.pendingWriteState.mac.size;
			cipherKeySize := SELF.pendingSecurityParameters.cipherKeySize;
			cipherBlockSize := SELF.pendingWriteState.cipher.blockSize;
			keyBlockLen := 2 * macSecretSize + 2 * cipherKeySize;
			IF cipherBlockSize > 1 THEN	(* if a blockcipher is used, initialization vectors are needed *)
			INC( keyBlockLen, 2 * cipherBlockSize )
			END;
			ASSERT( keyBlockLen <= 104 );	(* 3DES-EDE-CBC-SHA needs 104 bytes of keymaterial. all others need less *)
			FOR i := 0 TO 31 DO
				seed[ i ] := SELF.pendingSecurityParameters.serverRandom[ i ];
				seed[ i + 32 ] := SELF.pendingSecurityParameters.clientRandom[ i ]
			END;
			NEW( prf );
			prf.GetBytes( SELF.session.masterSecret, seed, keyBlock, "key expansion", 48, 64, keyBlockLen );
			(* mac secret *)
			FOR i := 0 TO macSecretSize - 1 DO
				SELF.pendingReadState.macSecret[ i ] := keyBlock[ i ];
				SELF.pendingWriteState.macSecret[ i ] := keyBlock[ macSecretSize + i ]
			END;
			(* keys for encryption and decription *)
			ofs := 2 * macSecretSize;
			FOR i := 0 TO cipherKeySize - 1 DO
			SELF.pendingReadState.cipherKey[ i ] := keyBlock[ ofs + i ];
				SELF.pendingWriteState.cipherKey[ i ] := keyBlock[ ofs + cipherKeySize + i ]
			END;
			(* initialization vectors *)
			IF cipherBlockSize > 1 THEN
				ofs := 2 * macSecretSize + 2 * cipherKeySize;
				FOR i := 0 TO cipherBlockSize - 1 DO
					SELF.pendingReadState.iv[ i ] := keyBlock[ ofs + i ];
					SELF.pendingWriteState.iv[ i ] := keyBlock[ ofs + cipherBlockSize + i ]
				END
			END
		END GenerateKeys;
			
		(* initializes a given ConnectionState with the key material contained in the ConnectionState and in
			the given SecurityParameters *)
		PROCEDURE InitializeConnectionState( state: ConnectionState; sp: SecurityParameters );
		BEGIN
			state.cipher.InitKey( state.cipherKey, 0, 8 * sp.cipherKeySize );
			IF state.cipher.blockSize > 0 THEN
				state.cipher.SetIV( state.iv, 0 )
			END
		END InitializeConnectionState;
			
		PROCEDURE PrepareConnectionState( state: ConnectionState; cipherSuite: LONGINT ; VAR res : LONGINT);
		BEGIN
			ASSERT( cipherSuite # 0 );
			res := Ok;
			CASE cipherSuite OF
				| TlsRsaWithNullMd5:
					NEW( state.mac, "AosCryptoMD5" );
					state.cipher := NIL;
				| TlsRsaWithNullSha:
					NEW( state.mac, "AosCryptoSHA1" );
					state.cipher := NIL;
				| TlsRsaWithRc4128Md5:
					NEW( state.mac, "AosCryptoMD5" );
					state.cipher := Ciphers.NewCipher( "AosCryptoARC4" );
				| TlsRsaWithRc4128Sha:
					NEW( state.mac, "AosCryptoSHA1" );
					state.cipher := Ciphers.NewCipher( "AosCryptoARC4" );
				| TlsRsaWithIdeaCbcSha:
					NEW( state.mac, "AosCryptoSHA1" );
					state.cipher := Ciphers.NewCipher( "AosCryptoIDEA" );
				| TlsRsaWithDesCbcSha:
					NEW( state.mac, "AosCryptoSHA1" );
					state.cipher := Ciphers.NewCipher( "AosCryptoDES" );
				| TlsRsaWith3DesEdeCbcSha:
					NEW( state.mac, "AosCryptoSHA1" );
					state.cipher := Ciphers.NewCipher( "AosCryptoDES3" );
				ELSE
					res := -1;
			END;
		END PrepareConnectionState;
			
		PROCEDURE PrepareSecurityParameters( sp: SecurityParameters; cipherSuite: LONGINT ; VAR res : LONGINT);
		BEGIN
			ASSERT( cipherSuite # 0 );
			res := Ok;
			sp.cipherSuite := cipherSuite;
			CASE cipherSuite OF
				| TlsRsaWithNullMd5:
					sp.cipherKeySize := 0;
				| TlsRsaWithNullSha:
					sp.cipherKeySize := 0;
				| TlsRsaWithRc4128Md5:
					sp.cipherKeySize := 16;
				| TlsRsaWithRc4128Sha:
					sp.cipherKeySize := 16;
				| TlsRsaWithIdeaCbcSha:
					sp.cipherKeySize := 16;
				| TlsRsaWithDesCbcSha:
					sp.cipherKeySize := 8;
				| TlsRsaWith3DesEdeCbcSha:
					sp.cipherKeySize := 24;
			ELSE
				res := -1
			END;
		END PrepareSecurityParameters;
			
	(* ********************************************************************************** 
		RECORD LAYER 
		********************************************************************************** *)
	
		PROCEDURE SendRecord( VAR data: ARRAY OF CHAR; contentType, ofs, len: LONGINT );
			VAR
				macInput: ARRAY 13 OF CHAR;
				i, length, padLen, blocksize: LONGINT;
		BEGIN
			ASSERT( len <= MaxPlaintextLength );
			(* increment the number of sent records *)
			currentWriteState.recordSeq.Inc( );
			length := len;
			(* data compression: no other algo than NULL is implemented *)
			(* mac *)
			IF currentWriteState.mac # NIL THEN
				currentWriteState.recordSeq.GetBytes( macInput, 0 );
				macInput[ 8 ] := CHR( contentType );
				macInput[ 9 ] := version[ 0 ];
				macInput[ 10 ] := version[ 1 ];
				macInput[ 11 ] := CHR( len DIV 256 );
				macInput[ 12 ] := CHR( len );
				currentWriteState.mac.Initialize( currentWriteState.macSecret, currentWriteState.mac.size );
				currentWriteState.mac.Update( macInput, 0, 13 );
				currentWriteState.mac.Update( data, ofs, len );
				currentWriteState.mac.GetMac( data, ofs+len );
				INC( length, currentWriteState.mac.size )
			END;
			(* encryption *)
			IF currentWriteState.cipher # NIL THEN	(* encryption has to be done *)
				blocksize := currentWriteState.cipher.blockSize;
				IF blocksize > 1 THEN	(* padding for encryption has to be added *)
					padLen := ( blocksize - ( ( length + 1 ) MOD blocksize ) ) MOD blocksize;	(* padLen = [ 0, blocksize-1 ] *)
					IF padLen > 0 THEN
						FOR i := 0 TO padLen - 1 DO		data[ ofs + length + i ] := CHR( padLen )		END
					END;
					data[ ofs + length + padLen ] := CHR( padLen );
					length := length + padLen + 1
				END;
				currentWriteState.cipher.Encrypt( data, ofs, length )
			END;
			(* record header *)
			out.Char( CHR( contentType ) );
			out.Char( CHR( 3 ) );
			out.Char( CHR( 1 ) );
			out.Char( CHR( length DIV 256 ) );
			out.Char( CHR( length ) );
			out.Bytes( data, ofs, length );
			out.Update
		END SendRecord;
			
		(* receive one record *)
		PROCEDURE ReceiveRecord;
			VAR
				macInput: ARRAY 13 OF CHAR;
				verify: ARRAY 20 OF CHAR;
				i, length, len, type, macSize, res, major, minor: LONGINT;
		BEGIN
			(* increment the number of received records *)
			currentReadState.recordSeq.Inc( );
			(* record header *)
			IF Trace THEN
				AosOut.String("Receiving Record No. ");AosOut.Int(currentReadState.recordSeq.num[ 1 ], 2);AosOut.Ln;
				AosOut.String("Currently available: ");AosOut.Int(in.Available(), 8);AosOut.Ln
			END;
			type := ORD( in.Get( ) );	(* content type *) 
			IF Trace THEN AosOut.String("  contentType: ");AosOut.Int(type, 6);AosOut.Ln END;
			IF type = 128 THEN (* SSLv2-compatible ClientHello *)
				len := ORD( in.Get() );
				in.Bytes( inbuf, 0, len, length );
				IF len = length THEN
					ReceiveV2Handshake( inbuf, 0, len );
					RETURN
				ELSE
					SendError( InternalError );
					RETURN
				END
			END;
			major := ORD( in.Get() );	minor := ORD( in.Get() );
			IF ( major # 3 ) OR ( minor # 1) THEN  END;	(* version control *) 
			IF Trace THEN AosOut.String("  version: ");AosOut.Int(major, 6);AosOut.String(".");AosOut.Int(minor, 6);AosOut.Ln END;
			len := 256 * ORD( in.Get() ) + ORD( in.Get() );	(* length of payload *)
			IF Trace THEN AosOut.String( "  length: " ); AosOut.Int( len, 5 );AosOut.Ln END;
			IF len > MaxCiphertextLength THEN		
				SendError( RecordOverflow );
				RETURN
			END;
			(* payload *)
			in.Bytes( inbuf, 0, len, length );
			IF in.res # AosIO.Ok THEN	
				IF Trace THEN AosOut.String("Can't read record: supposed to read:"); AosOut.Int(len, 7); AosOut.String(" read: "); AosOut.Int(length,7);END;	
				RETURN 
			END;
			(* records with unknown client protocol type are ignored; type=128: SSLv2-compatible ClientHello *)
			IF ( type = 128 ) OR ( type < 20 ) OR ( type > 23 ) THEN	RETURN	END;
			IF length # len THEN
				SendError( IllegalParameter );
				RETURN 
			END;
			(* decryption *)
			IF currentReadState.cipher # NIL THEN
				currentReadState.cipher.Decrypt( inbuf, 0, len  );
				IF res # Ciphers.Ok THEN
					IF Trace THEN AosOut.String("There was a Problem while decrypting record.");AosOut.Ln END;
					SendError( InternalError );
					RETURN	
				END;
				IF currentReadState.cipher.blockSize > 1 THEN	(* padding has to be removed *)
					len := len - ORD( inbuf[ len ] ) - 1;
				END
			END;
			(* mac verification *)
			IF currentReadState.mac # NIL THEN
				macSize := currentReadState.mac.size;
				len := len - macSize;
				currentReadState.recordSeq.GetBytes( macInput, 0 );
				macInput[ 8 ] := CHR( type );
				macInput[ 9 ] := CHR( major );
				macInput[ 10 ] := CHR( minor );
				macInput[ 11 ] := CHR( len DIV 256 );
				macInput[ 12 ] := CHR( len );
				currentReadState.mac.Initialize( currentReadState.macSecret, macSize );
				currentReadState.mac.Update( macInput, 0, 13 );
				currentReadState.mac.Update( inbuf, 0, len );
				currentReadState.mac.GetMac( verify, 0 );
				FOR i := 0 TO macSize - 1 DO
					IF inbuf[ len + i ] # verify[ i ] THEN
						 SendError( BadRecordMac );
						 RETURN
					END
				END
			END;
			(* data compression: no other algo than NULL is implemented *)
			(* dispatching *)
			CASE type OF
				| Handshake:
					ReceiveHandshake( inbuf, 0, len )
				| ApplicationData:
					IF Trace THEN AosOut.String("C  >  S Application Data");AosOut.Ln END;
					appDataWriter.Bytes( inbuf, 0, len );
					appDataWriter.Update;
				| Alert:
					ASSERT( len = 2 );
					ReceiveAlert( inbuf, 0, len )
				| ChangeCipherSpec:
					ASSERT( len = 1 );
					Transition( inbuf, ChangeCipherSpec, 0, 0, len )
			END;
		END ReceiveRecord;
		
	(* **********************************************************************************
		CHANGE CIPHER SPEC PROTOCOL
		********************************************************************************** *)
	
		PROCEDURE SendChangeCipherSpec;
		BEGIN
			IF Trace THEN AosOut.String("S > C  ChangeCipherSpec: ");AosOut.Ln END;
			outbuf[ 0 ] := CHR( 1 );
			SendRecord( outbuf, ChangeCipherSpec, 0, 1 );
			ChangeWriteState( )
		END SendChangeCipherSpec;
		
		PROCEDURE ReceiveChangeCipherSpec( VAR data: ARRAY OF CHAR; ofs: LONGINT );
		BEGIN
			IF Trace THEN AosOut.String("C > S  ChangeCipherSpec");AosOut.Ln END;
			IF ORD( data[ ofs ] ) # 1 THEN (* wrong content of ChangeCipherSpec *)
				SendError( IllegalParameter )
			ELSE
				ChangeReadState( )
			END
		END ReceiveChangeCipherSpec;
						
	(* **********************************************************************************
		HANDSHAKE PROTOCOL
		********************************************************************************** *)

		PROCEDURE SendHandshake( VAR data: ARRAY OF CHAR; hsType, ofs, len: LONGINT );
			VAR l: LONGINT;
		BEGIN
			IF Trace THEN
				AosOut.String("S > C  Handshake");AosOut.Ln;
				AosOut.String("  length: ");AosOut.Int(len, 4);AosOut.Ln
			END;
			ASSERT( len < 256 * 256 * 256 );
			l := len;
			data[ ofs ] := CHR( hsType );
			data[ ofs + 3 ] := CHR( l MOD 256 );	l := l DIV 256;
			data[ ofs + 2 ] := CHR( l MOD 256 );	l := l DIV 256;
			data[ ofs + 1 ] := CHR( l MOD 256 );
			IF hsType # HelloRequest THEN
				(* update the digests used in the finished-messages *)
				IF hsType # Finished THEN (* Finished-msg doesn't contain digest of itself *)
					hsMD5send.Update( data, ofs, len + 4 );
					hsSHAsend.Update( data, ofs, len + 4 )
				END;
				hsMD5verify.Update( data, ofs, len + 4 );
				hsSHAverify.Update( data, ofs, len + 4 )
			END;
			SendRecord( data, Handshake, ofs, len + 4 );
		END SendHandshake;
			
		(* receives one or more handshake messages *)
		PROCEDURE ReceiveHandshake( VAR data: ARRAY OF CHAR; ofs, len: LONGINT );
			VAR msgLen, hsType, ptr: LONGINT;
		BEGIN
			ASSERT( LEN( data ) >= ofs + len );
			IF Trace THEN AosOut.String("C > S  Handshake");AosOut.Ln END;
			ptr := ofs;
			WHILE ptr < ofs + len DO	(* for each handshake message *)
				hsType := ORD( data[ ptr ] );	(* handshake type *)
				msgLen := 256 * 256 * ORD( data[ ptr + 1 ] ) + 256 * ORD( data[ ptr + 2 ] ) + ORD( data[ ptr + 3 ] );
				IF Trace THEN AosOut.String("  msg length: ");AosOut.Int(msgLen,5);AosOut.Ln END;
				IF hsType = ClientHello THEN	(* new handshake begin *)
					hsMD5send.Initialize( );	hsSHAsend.Initialize( );
					hsMD5verify.Initialize( );	hsSHAverify.Initialize( )
				END;
				(* update the digests used in the finished-messages *)
				hsMD5send.Update( data, ptr, msgLen + 4 );
				hsSHAsend.Update( data, ptr, msgLen + 4 );
				IF hsType # Finished THEN (* Finished-msg doesn't contain digest of itself *) 
					hsMD5verify.Update( data, ptr, msgLen + 4 );
					hsSHAverify.Update( data, ptr, msgLen + 4 )
				END;
				Transition( data, Handshake, hsType, ptr + 4, msgLen );
				ptr := ptr + 4 + msgLen
			END
		END ReceiveHandshake;
		
		PROCEDURE ReceiveV2Handshake( VAR data: ARRAY OF CHAR; ofs, len: LONGINT );
		BEGIN
			ASSERT( data[ofs] = CHR( 1 ) );	(* v2ClientHello *)
			(* re-initialize hashes *)
			hsMD5send.Initialize( );	hsSHAsend.Initialize( );
			hsMD5verify.Initialize( );	hsSHAverify.Initialize( );
			(* update the digests used in the finished-messages *)
			hsMD5send.Update( data, ofs, len );
			hsSHAsend.Update( data, ofs, len );
			hsMD5verify.Update( data, ofs, len );
			hsSHAverify.Update( data, ofs, len );
			Transition( data, Handshake, V2ClientHello, ofs, len );
		END ReceiveV2Handshake;
			
		PROCEDURE ReceiveClientHello( VAR data: ARRAY OF CHAR; ofs, len: LONGINT ): LONGINT;
			VAR
				nofSuites, i, idLen, idPos, pos, cipherSuite, major, minor, res: LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("C > S  ClientHello");AosOut.Ln END;
			pos := ofs;
			(* version check *)
			major := ORD( data[ pos ] );	minor := ORD( data[ pos + 1 ] );
			IF Trace THEN AosOut.String("  version: ");AosOut.Int(major,1);AosOut.String(".");AosOut.Int(minor,1);AosOut.Ln END;
			IF ( major < 3  ) OR ( minor < 1 ) THEN (* fatal error: protocol version not supported *)
				SendError( ProtocolVersion );
				RETURN -1
			END;
			INC( pos, 2 );
			(* 32 bytes client random *)
			FOR i := 0 TO 31 DO		pendingSecurityParameters.clientRandom[ i ] := data[ pos + i ]		END;
			INC( pos, 32 );
			(* session id *)
			idLen := ORD( data[ pos ] );
			idPos := pos + 1;
			INC( pos, idLen + 1 );
			(* cipher-suites *)
			nofSuites := 256 * ORD( data[ pos ] ) + ORD( data[ pos + 1 ] ); (* number of cipher-suites supported by the client *)
			INC( pos, 2 );
			
			IF idLen = SessionIdLength THEN	(* client attempted session resumption *)
				session := context.FindSessionByID( data, idPos, idLen );
				IF session # NIL THEN
					(* check: is the resumed session's cipher-suite contained by the client-hello ? *)
					FOR i := 0 TO nofSuites - 1 DO
						cipherSuite := 256 * ORD( data[ pos + 2 * i ] ) + ORD( data[ pos + 2 * i + 1 ] );
						IF cipherSuite = session.cipherSuite THEN	(* session resumption *)
							pendingSecurityParameters.cipherSuite := session.cipherSuite;
							IF Trace THEN AosOut.String("ciphersuite: ");AosOut.Int(pendingSecurityParameters.cipherSuite, 8 );AosOut.Ln END;
							RETURN GenerateHelloWithResumption		
						END
					END
				END
			END;
			(* establish new session *)
			session := context.GetNewServerSession( );
			(* choose cipher-suite *)
			i := 0;
			LOOP
				cipherSuite := 256 * ORD( data[ pos + 2 * i ] ) + ORD( data[ pos + 2 * i + 1 ] );
				IF context.policy.IsSupported( cipherSuite ) THEN
					EXIT
				END;
				INC( i );
				IF i = nofSuites THEN EXIT END
			END;
			IF cipherSuite = 0 THEN	(* no compatible cipher-suite found *)
				SendError( HandshakeFailure );
				RETURN -1
			END;
			SELF.session.cipherSuite := cipherSuite;
			PrepareSecurityParameters( pendingSecurityParameters, cipherSuite, res );
			IF res < 0 THEN
				SendError( HandshakeFailure );
				RETURN -1			
			END;
			PrepareConnectionState( pendingWriteState, cipherSuite, res );
			IF res < 0 THEN
				SendError( HandshakeFailure );
				RETURN -1			
			END;			
			PrepareConnectionState( pendingReadState, cipherSuite, res );
			IF res < 0 THEN
				SendError( HandshakeFailure );
				RETURN -1			
			END;			
			(* ignore compression method *)
			RETURN GenerateServerHello
		END ReceiveClientHello;
		
		PROCEDURE ReceiveV2ClientHello( VAR data: ARRAY OF CHAR; ofs, len: LONGINT ): LONGINT;
			VAR nofSuites, idLen, challengeLen, i, cipherSuite, res: LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("C > S  SSLv2.0 ClientHello");AosOut.Ln END;
			nofSuites := ( 256 * ORD(data[ofs+3]) + ORD(data[ofs+4]) ) DIV 3;
			idLen := 256 * ORD(data[ofs+5]) + ORD(data[ofs+6]);
			challengeLen := 256 * ORD(data[ofs+7]) + ORD(data[ofs+8]);
			(* if an SSLv2.0-ClientHello is received, a new session has to be established, because a client sends an TLSv1.0-ClientHello when resuming a session *)
			session := context.GetNewServerSession( );
			(* choose cipher-suite *)
			INC( ofs, 9);
			i := 0;
			LOOP
				cipherSuite := 256*256*ORD( data[ ofs + 3 * i ] ) + 256 * ORD( data[ ofs + 3 * i + 1 ] ) + ORD( data[ ofs + 3 * i + 2 ] );
				IF context.policy.IsSupported( cipherSuite ) THEN
					EXIT
				END;
				INC( i );
				IF (i = nofSuites) OR (ofs + 3 * i + 2 >= LEN(data)) THEN EXIT END
			END;
			IF cipherSuite = 0 THEN	(* no compatible cipher-suite found *)
				SendError( HandshakeFailure );
				RETURN -1
			END;
			SELF.session.cipherSuite := cipherSuite;
			PrepareSecurityParameters( pendingSecurityParameters, cipherSuite, res );
			IF res < 0 THEN
				SendError( HandshakeFailure );
				RETURN -1
			END;
			PrepareConnectionState( pendingWriteState, cipherSuite, res );
			IF res < 0 THEN
				SendError( HandshakeFailure );
				RETURN -1
			END;			
			PrepareConnectionState( pendingReadState, cipherSuite, res );
			IF res < 0 THEN
				SendError( HandshakeFailure );
				RETURN -1
			END;			
			INC( ofs, nofSuites * 3 );
			(* session id *)
			IF idLen = SessionIdLength THEN	(* client attempted session resumption *)
				session := context.FindSessionByID( data, ofs, idLen );
				IF session # NIL THEN
					RETURN GenerateHelloWithResumption		
				END
			END;
			INC( ofs, idLen );
			(* 32 bytes client random *)
			FOR i := 0 TO 31-challengeLen DO		pendingSecurityParameters.clientRandom[ i ] := CHR(0)		END;
			FOR i := 0 TO challengeLen-1 DO		pendingSecurityParameters.clientRandom[ 32-challengeLen + i ] := data[ ofs + i ]		END;
			RETURN GenerateServerHello
		END ReceiveV2ClientHello;
		
		PROCEDURE SendServerHello( VAR data: ARRAY OF CHAR; ofs: LONGINT );
			VAR i, pos: LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("S > C  ServerHello");AosOut.Ln END;
			ASSERT( ofs > 3 );
			pos := ofs;
			(* server version *)
			data[ pos ] := version[ 0 ];	data[ pos + 1 ] := version[ 1 ];	(* only 3.1 is supported *)
			INC( pos, 2 );
			(* server random bytes generation*)
			Create32RandomBytes( pendingSecurityParameters.serverRandom );
			FOR i := 0 TO 31 DO	data[ pos + i ] := pendingSecurityParameters.serverRandom[ i ]	END;	(* copy random to outbuf *)
			INC( pos, 32 );
			(* session-id *)
			data[ pos ] := CHR( session.idLength );
			INC( pos );
			FOR i := 0 TO session.idLength - 1 DO		data[ pos + i ] := session.id[ i ]		END;	(* copy session-id to data *)
			INC( pos, session.idLength );
			(* cipher-suite *)
			data[ pos ] := CHR( pendingSecurityParameters.cipherSuite DIV 250 );
			data[ pos + 1 ] := CHR( pendingSecurityParameters.cipherSuite MOD 250 );
			INC( pos, 2 );
			(* compression-method *)
			data[ pos ] := CHR( 0 );
			INC( pos );
			SendHandshake( data, ServerHello, ofs-4, pos-ofs )
		END SendServerHello;
			
		PROCEDURE ReceiveClientKeyExchange( data: ARRAY OF CHAR; ofs, len: LONGINT );
			VAR
				encryptedPremasterSecret, premasterSecret: AosCryptoBigNumbers.BigNumber;
				res: BOOLEAN;
				tmp: ARRAY 512 OF CHAR;
				i: LONGINT;
		BEGIN
			INC( ofs, 2 ); DEC( len, 2 );	(* the two first bytes have to be ignored *)
			IF Trace THEN
				AosOut.String("ClientKeyExchange");AosOut.Ln;
				AosOut.String("   EncryptedPreMasterSecret [" );AosOut.Int( len, 3);AosOut.String("]");
				Utils.OutHex(data, ofs, len );AosOut.Ln
			END;
			(* decryption of the PreMasterSecret *)
			AosCryptoBigNumbers.AssignBin( encryptedPremasterSecret, data, ofs, len );
			res := AosCryptoRSA.Decrypt( SELF.context.rsaPrivateKey, "password", encryptedPremasterSecret, premasterSecret );
			IF ~res THEN
				IF Trace THEN AosOut.String("Decryption of PreMasterSecret was NOT successful!");AosOut.Ln END;
				SendError( IllegalParameter )
			END;
			AosCryptoBigNumbers.GetBinaryValue( premasterSecret, tmp, 0 );
			(* pkcs#1 block type 2 has to be used *)
			IF ( tmp[ 0 ] # CHR( 0 ) ) OR ( tmp[ 1 ] # CHR( 2 ) )THEN	SendError( IllegalParameter )	END; 
			i := 10;	(* there are at least 8 padding bytes *)
			WHILE tmp[ i ] # CHR( 0 ) DO	INC( i )	END;	(* padding ends with a zero-byte *)
			INC( i );
			SELF.session.SetPreMasterSecret( tmp, i );
			IF Trace THEN
				AosOut.String("PreMasterSecret [48]");
				Utils.OutHex(SELF.session.preMasterSecret, 0, 48);AosOut.Ln
			END;
			GenerateMasterSecret( );
			GenerateKeys( );
			InitializeConnectionState( SELF.pendingWriteState, SELF.pendingSecurityParameters );
			InitializeConnectionState( SELF.pendingReadState, SELF.pendingSecurityParameters )	
		END ReceiveClientKeyExchange;
		
		PROCEDURE SendCertificate( VAR data: ARRAY OF CHAR; ofs: LONGINT );
			VAR i: LONGINT;
		BEGIN
			ASSERT( ofs > 3 );
			IF Trace THEN AosOut.String("S > C  Certificate");AosOut.Ln END;
			FOR i := 0 TO context.lengthOfRsaCertificate-1 DO
				data[ ofs + i ] := context.rsaCertificate[ i ];
			END;
			SendHandshake( data, Certificate, ofs-4, context.lengthOfRsaCertificate );
		END SendCertificate;
		
		PROCEDURE SendServerHelloDone( VAR data: ARRAY OF CHAR; ofs: LONGINT );
		BEGIN
			ASSERT( ofs > 3 );
			IF Trace THEN AosOut.String("S > C  ServerHelloDone");AosOut.Ln END;
			SendHandshake( data, ServerHelloDone, ofs-4, 0 )
		END SendServerHelloDone;
			
		PROCEDURE SendFinished( VAR data: ARRAY OF CHAR; ofs: LONGINT );
			VAR
				seed: ARRAY 36 OF CHAR;
				verifyData: ARRAY 12 OF CHAR;
				i: LONGINT;
				prf: PRF;
		BEGIN
			IF Trace THEN AosOut.String("S > C  Finished");AosOut.Ln END;
			ASSERT( ofs > 3 );
			hsMD5send.GetHash( seed, 0 );	hsSHAsend.GetHash( seed, 16 );	(* concatenate md5 and sha output *)
			NEW( prf );
			prf.GetBytes( SELF.session.masterSecret, seed, verifyData, "server finished", 48, 36, 12 );
			FOR i := 0 TO 11 DO
				data[ ofs + i ] := verifyData[ i ] 
			END;
			SendHandshake( data, Finished, ofs-4, 12 )
		END SendFinished;
			
		PROCEDURE ReceiveFinished( data: ARRAY OF CHAR; ofs, len: LONGINT );
			VAR
				seed: ARRAY 36 OF CHAR;
				verifyData: ARRAY 12 OF CHAR;
				prf: PRF;
				i: LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("C > S  Finished"); AosOut.Ln END;
			ASSERT( len = 12 );
			hsMD5verify.GetHash( seed, 0 );	hsSHAverify.GetHash( seed, 16 );	(* concatenate md5 and sha output *)
			NEW( prf );
			prf.GetBytes( SELF.session.masterSecret, seed, verifyData, "client finished", 48, 36, 12 );
			FOR i := 0 TO 11 DO
				IF verifyData[ i ] # data[ ofs + i ] THEN
					SendError( DecryptError );
					RETURN
				END
			END
		END ReceiveFinished;
		
	(* **********************************************************************************
		ALERT PROTOCOL
		********************************************************************************** *)
	
		PROCEDURE ReceiveAlert( VAR data: ARRAY OF CHAR; ofs, len: LONGINT );
			VAR level, description, ptr: LONGINT;
		BEGIN
			ptr := ofs;
			WHILE ptr < ofs + len DO	(* for each Alert-message *)
				level := ORD( data[ ptr ] );
				description := ORD( data[ ptr + 1 ] );
				IF level = Warning THEN
					ReceiveWarning( description )
				ELSIF level = Fatal THEN
					ReceiveError( description )
				ELSE	(* illegal level *)
					SendError( IllegalParameter )
				END;
				INC( ptr, 2 )
			END
		END ReceiveAlert;
			
		PROCEDURE ReceiveWarning( desc: LONGINT);
		BEGIN
			(* always send an error; this could be more sophisticated *)
			tlsErrorCause := desc;
			SendError( CloseNotify )
		END ReceiveWarning;

		PROCEDURE ReceiveError( alertType: LONGINT);
		BEGIN
			(*IF Trace THEN*)
				AosOut.String("C > S  Error");AosOut.Ln;
				AosOut.String("  alertType: ");AosOut.Int(alertType, 3);AosOut.Ln;
			(*END;*)
			IF session # NIL THEN 		SELF.session.Invalidate( )		END;
			SELF.conn.Close( );
			applicationDataPipe.Close();
			SetState(AosTCP.Closed);
		END ReceiveError;

		PROCEDURE SendWarning( alertType: LONGINT );
		BEGIN
			IF Trace THEN
				AosOut.String("S > C  Warning");AosOut.Ln;
				AosOut.String("  alertType: ");AosOut.Int(alertType, 3);AosOut.Ln;
			END;
			outbuf[ 0 ] := CHR( 1 );	(* level: warning *)
			outbuf[ 1 ] := CHR( alertType );
			SendRecord( outbuf, Alert, 0, 2 );
		END SendWarning;
			
		PROCEDURE SendError( alertType: LONGINT );
		BEGIN
			(*IF Trace THEN*)
				AosOut.String("S > C  Error");AosOut.Ln;
				AosOut.String("  alertType: ");AosOut.Int(alertType, 3);AosOut.Ln;
			(*END;*)
			outbuf[ 0 ] := CHR( 2 );	(* level: fatal *)
			outbuf[ 1 ] := CHR( alertType );
			SendRecord( outbuf, Alert, 0, 2 );
			IF session # NIL THEN		SELF.session.Invalidate( )		END;
			SELF.conn.Close( );
			applicationDataPipe.Close();
			SetState(AosTCP.Closed);
		END SendError;
			
	(* **********************************************************************************
		FINITE STATE MACHINE
		********************************************************************************** *)

		PROCEDURE Transition( VAR data: ARRAY OF CHAR; action, subAction, ofs, len: LONGINT );
			VAR dummy: ARRAY 1 OF CHAR;
				res : LONGINT;
		BEGIN
			IF action = ChangeCipherSpec THEN
				CASE handshakeState OF
					| AwaitChangeSpec:
						ReceiveChangeCipherSpec( data, ofs );
						handshakeState := AwaitFinished
					| AwaitChangeSpecWithResumption:
						ReceiveChangeCipherSpec( data, ofs );
						handshakeState := AwaitFinishedWithResumption
				ELSE
					SendError( UnexpectedMessage )
				END
			ELSIF action = Handshake THEN
				IF State()= ServerHandshake THEN
					CASE handshakeState OF
						| AwaitClientHello:
							IF subAction = ClientHello THEN
								handshakeState := ReceiveClientHello( data, ofs, len );
								Transition( dummy, Handshake, 0, 0, 0 )
							ELSIF subAction = V2ClientHello THEN
								handshakeState := ReceiveV2ClientHello( data, ofs, len );
								Transition( dummy, Handshake, 0, 0, 0 )
							ELSE	 (* fatal error *)
								SendError( UnexpectedMessage )
							END
						| GenerateServerHello:	(* establish new session *)
							SendServerHello( outbuf, 4 );
							SendCertificate( outbuf, 4 );
							handshakeState := GenerateServerHelloDone;
							Transition( dummy, Handshake, 0, 0, 0 )
						| GenerateServerHelloDone:
							SendServerHelloDone( outbuf, 4 );
							handshakeState := AwaitClientKeyExchange;
						| AwaitClientKeyExchange:
							IF subAction = ClientKeyExchange THEN
								ReceiveClientKeyExchange( data, ofs, len );
								handshakeState := AwaitChangeSpec;
							ELSE (* fatal error *)
								SendError( UnexpectedMessage )
							END
						| AwaitFinished:
							IF subAction = Finished THEN
								ReceiveFinished( data, ofs, len );
								handshakeState := GenerateChangeCipherSpec;
								Transition( dummy, Handshake, 0, 0, 0 )
							ELSE (* fatal error *)
								SendError( UnexpectedMessage )
							END
						| GenerateChangeCipherSpec:
							SendChangeCipherSpec;
							SendFinished( outbuf, 4 );
							handshakeState := HandshakeFinished;
							SetState(AosTCP.Established);
							IF SELF.context.policy.sessionResumptionEnabled THEN
								SELF.context.StoreSession( SELF.session )
							END
						| GenerateHelloWithResumption:	(* session resumption *)
							SendServerHello( outbuf, 4 );
							PrepareSecurityParameters( pendingSecurityParameters, pendingSecurityParameters.cipherSuite, res );
							IF res < 0 THEN
								SendError( UnexpectedMessage )
							END;
							PrepareConnectionState( pendingWriteState, pendingSecurityParameters.cipherSuite,res );
							IF res < 0 THEN
								SendError( HandshakeFailure );	
							END;							
							PrepareConnectionState( pendingReadState, pendingSecurityParameters.cipherSuite, res );
							IF res < 0 THEN
								SendError( HandshakeFailure );	
							END;							
							GenerateKeys( );
							InitializeConnectionState( SELF.pendingWriteState, SELF.pendingSecurityParameters );
							InitializeConnectionState( SELF.pendingReadState, SELF.pendingSecurityParameters );
							SendChangeCipherSpec;
							SendFinished( outbuf, 4 );
							handshakeState := AwaitChangeSpecWithResumption
						| AwaitFinishedWithResumption:
							IF subAction = Finished THEN
								ReceiveFinished( data, ofs, len );
								handshakeState := HandshakeFinished;
								SetState(AosTCP.Established);
							ELSE (* fatal error *)
								SendError( UnexpectedMessage )
							END
					END (* CASE *)
				ELSIF State() = AosTCP.Established THEN
					IF subAction = ClientHello THEN (* the only handshake msg a server should receive after a finished handshake *)
						SetState(ServerHandshake);
						handshakeState := ReceiveClientHello( data, ofs, len );
						Transition( dummy, Handshake, 0, 0, 0 )
					ELSE (* fatal error *)
						SendError( UnexpectedMessage )
					END
				END
			END;
		END Transition;
		
	(* **********************************************************************************
		UTILITIES
		********************************************************************************** *)

		PROCEDURE Create32RandomBytes( VAR data: ARRAY OF CHAR );
			VAR i, time, date, timestamp: LONGINT;
		BEGIN
			ASSERT( LEN( data ) >  31 );
			(* 4 bytes timestamp *)
			AosClock.Get( date, time );
			timestamp := BIT.LXOR( date, time );
			FOR i := 3 TO 0 BY -1 DO
				data[ i ] := CHR( timestamp );
				timestamp := timestamp DIV 256
			END;
			(* 28 random bytes *)
			Utils.RandomBytes( data, 4, 28 )
		END Create32RandomBytes;
		
		
	BEGIN { ACTIVE }
		AwaitStateNotEqual(AosTCP.Unused);
		IF State() # AosTCP.Listen THEN
			(* listen for incoming messages *)
			REPEAT
				ReceiveRecord( )
			UNTIL (State() = AosTCP.Closed) OR (in.res # AosIO.Ok);
			Close();
		END;
	END Connection;
		
VAR
	version: ARRAY 2 OF CHAR;
		
BEGIN
	version[ 0 ] := CHR( 3 ); (* this implementation supports only TLS 1.0 = SSL 3.1 *)
	version[ 1 ] := CHR( 1 );
END TLS.


System.Free WebHTTPServerTools WebHTTPServer TLSServices TLS ~
Aos.Call WebHTTPServerTools.Start~