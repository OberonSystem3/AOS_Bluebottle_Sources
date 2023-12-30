MODULE AosCryptoMD5;	(** AUTHOR "G.F."; PURPOSE "MD5"; *)

IMPORT
	S := SYSTEM,	Hashes := AosCryptoHashes;  

TYPE 
	Buffer = ARRAY 16 OF LONGINT;
	LI = LONGINT;
	
	Hash* = OBJECT (Hashes.Hash)
	VAR
		A, B, C, D: LONGINT;
		N: LONGINT;
		X: Buffer;
		cb: ARRAY 4 OF LONGINT;

		PROCEDURE & Init;  
		BEGIN 
			SetNameAndSize( "md5", 16 );
			initialized := FALSE
		END Init;  

		PROCEDURE Initialize*;  
		BEGIN 
			N := 0;
			(* Initialize chaining values *)
			A := 67452301H;  B := 0EFCDAB89H;  C := 098BADCFEH;  D := 10325476H;
			initialized := TRUE
		END Initialize;  
				
		PROCEDURE Write( ch: CHAR );  
			VAR i: LONGINT;
		BEGIN 
			i := N MOD 4;  cb[i] := ORD( ch );
			IF i = 3 THEN  X[N DIV 4 MOD 16] := ((cb[3]*256 + cb[2])*256 + cb[1])*256 + cb[0]  END;  
			INC( N );
			IF N MOD 64 = 0 THEN MD5( X, A, B, C, D ) END;
		END Write;
				
		(** data: value to be hashed *)
		PROCEDURE Update*( VAR data: ARRAY OF CHAR;  pos, len: LONGINT );  
			VAR i: LONGINT;
		BEGIN
			ASSERT( initialized );
			FOR i := pos TO pos + len - 1 DO
				(* The following code equals ' Write(data[i]) '. It was copied here for better performance *)
				cb[ N MOD 4 ] := ORD( data[ i ] );
				IF N MOD 4 = 3 THEN  X[ N DIV 4 MOD 16 ] := ( ( cb[ 3 ] * 256 + cb[ 2 ] ) * 256 + cb[ 1 ] ) * 256 + cb[ 0 ]  END;  
				INC( N );
				IF N MOD 64 = 0 THEN MD5( X, A, B, C, D ) END;
			END
		END Update;  

		(** get the hashvalue of length SELF.size *)
		PROCEDURE GetHash*( VAR buf: ARRAY OF CHAR;  pos: LONGINT );  
			VAR n: LONGINT;  

			PROCEDURE out( x: LONGINT );  
			BEGIN 
				buf[pos] := CHR( x MOD 256 );  x := x DIV 256;  INC( pos );
				buf[pos] := CHR( x MOD 256 );  x := x DIV 256;  INC( pos );
				buf[pos] := CHR( x MOD 256 );  x := x DIV 256;  INC( pos );
				buf[pos] := CHR( x MOD 256 );  INC( pos );
			END out;  

		BEGIN
		(* Append padding *)
			n := N*8;
			Write( 80X ); (* 1000 0000 *)
			WHILE N MOD 64 # 56 DO
				Write( 0X )	(* 0000 0000 *)
			END;
			(* 64-bit representation of b mod 2^64 *)
			Write( CHR( n MOD 256 ) );  n := n DIV 256;  Write( CHR( n MOD 256 ) );  n := n DIV 256;  
			Write( CHR( n MOD 256 ) );  n := n DIV 256;  Write( CHR( n MOD 256 ) );  
			Write( 0X );  Write( 0X );  Write( 0X );  Write( 0X );  
		
			out( A );  out( B );  out( C );  out( D )
		END GetHash;  

	END Hash;

(*-----------------------------------------------------------------------------------*)

VAR 
	T: ARRAY 65 OF LONGINT;  
	
	(** get an instance of MD5 *)
	PROCEDURE NewHash*( par: PTR ): PTR;  
		VAR h: Hash;
	BEGIN 
		NEW( h );		RETURN h
	END NewHash; 

	PROCEDURE F1( VAR a: LONGINT;  b, c, d, x, s, t: LONGINT );  
		VAR f: LONGINT;
	BEGIN 
		f := S.VAL( LI, (S.VAL( SET, b ) * S.VAL( SET, c )) + ((-S.VAL( SET, b )) * S.VAL( SET, d )) );
		a := S.ROT( a + f + x + t, s ) + b 
	END F1;  

	PROCEDURE F2( VAR a: LONGINT;  b, c, d, x, s, t: LONGINT );  
		VAR f: LONGINT;
	BEGIN 
		f := S.VAL( LI, (S.VAL( SET, b ) * S.VAL( SET, d )) + (S.VAL( SET, c ) * (-S.VAL( SET, d ))) );
		a := S.ROT( a + f + x + t, s ) + b 
	END F2;  

	PROCEDURE F3( VAR a: LONGINT;  b, c, d, x, s, t: LONGINT );  
		VAR f: LONGINT;
	BEGIN 
		f := S.VAL( LI, S.VAL( SET, b ) / S.VAL( SET, c ) / S.VAL( SET, d ) );
		a := S.ROT( a + f + x + t, s ) + b 
	END F3;  

	PROCEDURE F4( VAR a: LONGINT;  b, c, d, x, s, t: LONGINT );  
		VAR f: LONGINT;
	BEGIN 
		f := S.VAL( LI, S.VAL( SET, c ) / (S.VAL( SET, b ) + (-S.VAL( SET, d ))) );
		a := S.ROT( a + f + x + t, s ) + b 
	END F4;  

	PROCEDURE MD5( VAR X: Buffer; VAR A, B, C, D: LONGINT );  
		VAR  a, b, c, d: LONGINT; 
	BEGIN 
		a := A;  b := B;  c := C;  d := D;  
		
		F1(  a, b, c, d,  X[00], 07, T[01] );	F1(  d, a, b, c,  X[01], 12, T[02] );  
		F1(  c, d, a, b,  X[02], 17, T[03] );	F1(  b, c, d, a,  X[03], 22, T[04] );  
		F1(  a, b, c, d,  X[04], 07, T[05] );	F1(  d, a, b, c,  X[05], 12, T[06] );  
		F1(  c, d, a, b,  X[06], 17, T[07] );	F1(  b, c, d, a,  X[07], 22, T[08] );  
		F1(  a, b, c, d,  X[08], 07, T[09] );	F1(  d, a, b, c,  X[09], 12, T[10] );  
		F1(  c, d, a, b,  X[10], 17, T[11] );	F1(  b, c, d, a,  X[11], 22, T[12] );  
		F1(  a, b, c, d,  X[12], 07, T[13] );	F1(  d, a, b, c,  X[13], 12, T[14] );  
		F1(  c, d, a, b,  X[14], 17, T[15] );	F1(  b, c, d, a,  X[15], 22, T[16] );  
		
		F2(  a, b, c, d,  X[01], 05, T[17] );	F2(  d, a, b, c,  X[06], 09, T[18] );  
		F2(  c, d, a, b,  X[11], 14, T[19] );	F2(  b, c, d, a,  X[00], 20, T[20] );  
		F2(  a, b, c, d,  X[05], 05, T[21] );	F2(  d, a, b, c,  X[10], 09, T[22] );  
		F2(  c, d, a, b,  X[15], 14, T[23] );	F2(  b, c, d, a,  X[04], 20, T[24] );  
		F2(  a, b, c, d,  X[09], 05, T[25] );	F2(  d, a, b, c,  X[14], 09, T[26] );  
		F2(  c, d, a, b,  X[03], 14, T[27] );	F2(  b, c, d, a,  X[08], 20, T[28] );  
		F2(  a, b, c, d,  X[13], 05, T[29] );	F2(  d, a, b, c,  X[02], 09, T[30] );  
		F2(  c, d, a, b,  X[07], 14, T[31] );	F2(  b, c, d, a,  X[12], 20, T[32] );  
		
		F3(  a, b, c, d,  X[05], 04, T[33] );	F3(  d, a, b, c,  X[08], 11, T[34] );  
		F3(  c, d, a, b,  X[11], 16, T[35] );	F3(  b, c, d, a,  X[14], 23, T[36] );  
		F3(  a, b, c, d,  X[01], 04, T[37] );	F3(  d, a, b, c,  X[04], 11, T[38] );  
		F3(  c, d, a, b,  X[07], 16, T[39] );	F3(  b, c, d, a,  X[10], 23, T[40] );  
		F3(  a, b, c, d,  X[13], 04, T[41] );	F3(  d, a, b, c,  X[00], 11, T[42] );  
		F3(  c, d, a, b,  X[03], 16, T[43] );	F3(  b, c, d, a,  X[06], 23, T[44] );  
		F3(  a, b, c, d,  X[09], 04, T[45] );	F3(  d, a, b, c,  X[12], 11, T[46] );  
		F3(  c, d, a, b,  X[15], 16, T[47] );	F3(  b, c, d, a,  X[02], 23, T[48] );  
		
		F4(  a, b, c, d,  X[00], 06, T[49] );	F4(  d, a, b, c,  X[07], 10, T[50] );  
		F4(  c, d, a, b,  X[14], 15, T[51] );	F4(  b, c, d, a,  X[05], 21, T[52] );  
		F4(  a, b, c, d,  X[12], 06, T[53] );	F4(  d, a, b, c,  X[03], 10, T[54] );  
		F4(  c, d, a, b,  X[10], 15, T[55] );	F4(  b, c, d, a,  X[01], 21, T[56] );  
		F4(  a, b, c, d,  X[08], 06, T[57] );	F4(  d, a, b, c,  X[15], 10, T[58] );  
		F4(  c, d, a, b,  X[06], 15, T[59] );	F4(  b, c, d, a,  X[13], 21, T[60] );  
		F4(  a, b, c, d,  X[04], 06, T[61] );	F4(  d, a, b, c,  X[11], 10, T[62] );  
		F4(  c, d, a, b,  X[02], 15, T[63] );	F4(  b, c, d, a,  X[09], 21, T[64] );  
		
		INC( A, a );  INC( B, b );  INC( C, c );  INC( D, d );  
	END MD5;  

BEGIN 
	T[1] := 0D76AA478H;	T[2] := 0E8C7B756H;	T[3] := 0242070DBH;	T[4] := 0C1BDCEEEH;  
	T[5] := 0F57C0FAFH;	T[6] := 04787C62AH;	T[7] := 0A8304613H;	T[8] := 0FD469501H;  
	T[9] := 0698098D8H;	T[10] := 08B44F7AFH;	T[11] := 0FFFF5BB1H;	T[12] := 0895CD7BEH;  
	T[13] := 06B901122H;	T[14] := 0FD987193H;	T[15] := 0A679438EH;	T[16] := 049B40821H;  
	T[17] := 0F61E2562H;	T[18] := 0C040B340H;	T[19] := 0265E5A51H;	T[20] := 0E9B6C7AAH;  
	T[21] := 0D62F105DH;	T[22] := 02441453H;	T[23] := 0D8A1E681H;	T[24] := 0E7D3FBC8H;  
	T[25] := 021E1CDE6H;	T[26] := 0C33707D6H;	T[27] := 0F4D50D87H;	T[28] := 0455A14EDH;  
	T[29] := 0A9E3E905H;	T[30] := 0FCEFA3F8H;	T[31] := 0676F02D9H;	T[32] := 08D2A4C8AH;  
	T[33] := 0FFFA3942H;	T[34] := 08771F681H;	T[35] := 06D9D6122H;	T[36] := 0FDE5380CH;  
	T[37] := 0A4BEEA44H;	T[38] := 04BDECFA9H;	T[39] := 0F6BB4B60H;	T[40] := 0BEBFBC70H;  
	T[41] := 0289B7EC6H;	T[42] := 0EAA127FAH;	T[43] := 0D4EF3085H;	T[44] := 04881D05H;  
	T[45] := 0D9D4D039H;	T[46] := 0E6DB99E5H;	T[47] := 01FA27CF8H;	T[48] := 0C4AC5665H;  
	T[49] := 0F4292244H;	T[50] := 0432AFF97H;	T[51] := 0AB9423A7H;	T[52] := 0FC93A039H;  
	T[53] := 0655B59C3H;	T[54] := 08F0CCC92H;	T[55] := 0FFEFF47DH;	T[56] := 085845DD1H;  
	T[57] := 06FA87E4FH;	T[58] := 0FE2CE6E0H;	T[59] := 0A3014314H;	T[60] := 04E0811A1H;  
	T[61] := 0F7537E82H;	T[62] := 0BD3AF235H;	T[63] := 02AD7D2BBH;	T[64] := 0EB86D391H; 
	
END AosCryptoMD5.
 ;
