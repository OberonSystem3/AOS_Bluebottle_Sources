MODULE AosCryptoBigNumbers;  (* g.f.	2001.10.07 *)

(* 2002.08.12	g.f.	added neg. numbers, GCD and ModInverse  *)
(* 2002.09.24	g.f.	inceased digit size from 8 bit to 32 bit *)
(* 2002.10.04	g.f.	faster version of ModExp (uses montgomery multiplications now) *)
(* 2006.10.13	g.f.	bugfix in procedure mul *)

(**  Computing big numbers up to 1024 hex digits.
		
		WARNING:
		The procedures are not reentrant for efficiency reasons. If you use them
		in a threaded environment they have to be locked by a mutex!
 *)

IMPORT
	AosOut,	AosIO,	AosFS,	S := SYSTEM, AosKernel, AosRandom;

CONST
	BNFlag = 0F0F0F0F0H;
	BufferPoolSize = 16;

TYPE 
	digits* = POINTER TO ARRAY OF LONGINT;  
	BigNumber* = RECORD 
		len-: INTEGER;  (** number of significant LONGINTS *)
		neg-: BOOLEAN;
		d-: digits;
		magic: LONGINT;
	END;  
			
	dig2 = ARRAY 2 OF LONGINT;
	dig3 = ARRAY 3 OF LONGINT;
	
	Montgomery = OBJECT
		VAR
			bits: INTEGER;	(* of R *)
			r, n, t1, t2: BigNumber;
			
		PROCEDURE Init( VAR x: BigNumber );  
		BEGIN 
			Copy( x, n );
			bits := x.len*32;
			Assign( r, 1 );
			Shift( r, bits );	(* r := R *)
			ModInverse( n, r, t1 );
			Sub( r, t1, r );   (* r := R - (1/n)  (mod R) *)
			InitSize( t1, 2*bits );
			InitSize( t2, 2*bits );
		END Init;  
				
		PROCEDURE Convert( VAR val: BigNumber ); 	(* val := val ^ R mod n *)
			VAR i: LONGINT;  
		BEGIN 
			FOR i := 0 TO bits - 1 DO
				Shift( val, 1 );  
				IF ucmp( val, n ) >= 0 THEN
					Sub( val, n, val )
				END 
			END 
		END Convert;  

		PROCEDURE Reduce( VAR val: BigNumber ); 	(* val := val ^ (1/R) mod n *)
		BEGIN 
			Copy( val, t1 );
			Mask( t1, bits - 1 ); 	(* val mod R *)
			mul( t1.d, r.d, t2.d, t1.len, r.len, t2.len );
			Mask( t2, bits - 1 ); 	(* mod R *)
			mul( t2.d, n.d, t1.d, t2.len, n.len, t1.len );  
			add( t1.d, val.d, val.d, t1.len, val.len, val.len );
			Shift( val, -bits ); 	(* div R *)
			IF ucmp( val, n ) >= 0 THEN
				sub( val.d, n.d, val.d, val.len, n.len, val.len )
			END  
		END Reduce;  
				
		PROCEDURE Mult( VAR a, b, c: BigNumber ); 	
		BEGIN 
			mul( a.d, b.d, c.d, a.len, b.len, c.len );
			Reduce( c )
		END Mult;

	END  Montgomery;
		
VAR

	bufferPool: ARRAY BufferPoolSize OF BigNumber;
	nextFreeBuffer: LONGINT;
	(*
	adds: BigNumber;
	mulp, mulp2: BigNumber;	(* temp. variable for mul *)
	divt, divs, divq: BigNumber;	(* temp. variales for div *)
	expe, expv: BigNumber;	(* temp. variales for exp *)
	mmp: BigNumber;	(* temp. variale for ModMull *)
	dummy: BigNumber;	(* receiver for unneeded values *)
	*)

	M: Montgomery;
	
	randomgenerator: AosRandom.Generator;

	PROCEDURE max( a, b: INTEGER ): INTEGER;  
	BEGIN 
		IF a >= b THEN
			RETURN a
		ELSE
			RETURN b
		END
	END max;  

	PROCEDURE Less( x, y: LONGINT ): BOOLEAN;  
	VAR
		a, b: LONGINT;  
	BEGIN 
		a := S.LSH( x, -1 );
		b := S.LSH( y, -1 );  
		IF a = b THEN
			RETURN x MOD 2 < y MOD 2
		ELSE  
			RETURN a < b
		END 
	END Less;  

	PROCEDURE LessEq( x, y: LONGINT ): BOOLEAN;  
	VAR
		a, b: LONGINT;
	BEGIN 
		IF x = y THEN
			RETURN TRUE 
		ELSE
			a := S.LSH( x, -1 );
			b := S.LSH( y, -1 );
			IF a = b THEN
				RETURN x MOD 2 < y MOD 2
			ELSE
				RETURN a < b
			END
		END
	END LessEq;  

	PROCEDURE RandomBytes*( VAR buf: ARRAY OF CHAR;  p: LONGINT;  n: INTEGER );  
	VAR
		i, r: LONGINT;  
	BEGIN 
(*		t := AosKernel.GetTimer();
		d := AosKernel.GetTimer();
		Rand.InitSeed( S.VAL( LONGINT, S.VAL( SET, ENTIER( Rand.Uniform()*1000000 ) ) / 
															 S.VAL( SET, t ) / S.VAL( SET, d ) ) );  
		FOR i := 0 TO n - 1 DO buf[p + i] := CHR( ENTIER( Rand.Uniform()*256 ) ) END 
		*)
		(* XXX RP. assume LONGINT=32bit *)
		i:=0;
		LOOP
			IF i=(p+n) THEN EXIT; END;
			r:=randomgenerator.Integer();
			buf[p+i]:=CHR(r MOD 256); r:=ASH(r, -8); INC(i);
			IF i=(p+n) THEN EXIT; END;
			buf[p+i]:=CHR(r MOD 256); r:=ASH(r, -8); INC(i);
			IF i=(p+n) THEN EXIT; END;
			buf[p+i]:=CHR(r MOD 256); r:=ASH(r, -8); INC(i);
			IF i=(p+n) THEN EXIT; END;
			buf[p+i]:=CHR(r MOD 256); r:=ASH(r, -8); INC(i);
		END;
	END RandomBytes;  
	
	PROCEDURE it( VAR x: BigNumber ): BOOLEAN;  (* test if x has been initialized *)
	BEGIN 
		RETURN (x.magic = BNFlag) & (x.d # NIL)
	END it;  

	PROCEDURE new( VAR d: digits; len: INTEGER );  
	VAR n: INTEGER; 
	BEGIN 
		n := 16;
		WHILE n < len DO  INC( n, 16)  END;
		NEW( d, n );  
	END new;  

	PROCEDURE Init*( VAR b: BigNumber );  
	BEGIN 
		IF ~it( b ) THEN  new( b.d, 16 );  b.magic := BNFlag  END;  
		b.len := 0;  b.neg := FALSE
	END Init;  
	
	(** initializes the size of b *)
	PROCEDURE InitSize*( VAR b: BigNumber;  bits: LONGINT );  
		VAR n: INTEGER;
	BEGIN 
		n := SHORT( (bits + 31) DIV 32 );
		IF ~it( b ) THEN  new( b.d, n );  b.magic := BNFlag  ELSE  adjust( b.d, b.len, n )  END;  
		b.len := 0;  b.neg := FALSE
	END InitSize;  
	
	(* enlarges d if d is smaller that len. dl is the actual length of d's content *)
	PROCEDURE adjust( VAR d: digits;  dl, len: INTEGER );  
		VAR n, i: INTEGER;  nd: digits;
	BEGIN 
		ASSERT( d # NIL );
		n := 16;
		WHILE n < len DO  INC( n, 16)  END;
		IF LEN( d ) < n THEN 
			NEW( nd, n );
			FOR i := 0 TO dl - 1 DO nd[i] := d[i] END;
			d := nd
		END;
	END adjust;
	
	(** random number with len 'bits' *)
	PROCEDURE NewRand*( VAR b: BigNumber;  bits: INTEGER;  top, bottom: SHORTINT );
		VAR n, topbit: INTEGER;  topword: SET;  buf: ARRAY 4096 OF CHAR;
	BEGIN 
		n := (bits + 7) DIV 8; 
		RandomBytes( buf, 0, n );  AssignBin( b, buf, 0, n );
		topbit := (bits - 1)  MOD 32;  topword := S.VAL( SET, b.d[b.len - 1] ) * {0..topbit};
		IF top > 0 THEN INCL( topword, topbit ) END;
		b.d[b.len - 1] := S.VAL( LONGINT, topword );
		IF (bottom > 0) & ~ODD( b.d[0] ) THEN  INC( b.d[0] )  END;
	END NewRand;  
	
	(** 0 < b < range DIV 2 - 1*)
	PROCEDURE NewRandRange*( VAR b, range: BigNumber );
	BEGIN 
		NewRand( b, BitSize( range ) - 1, 0, 0 );  Dec( b );
	END NewRandRange;  

	PROCEDURE fixlen( VAR d: digits;  VAR len: INTEGER );  
	BEGIN 
		WHILE (len > 0) & (d[len - 1] = 0) DO  DEC( len )  END;  
	END fixlen;  

	PROCEDURE h2i( c: CHAR ): LONGINT;  
		VAR v: LONGINT;  
	BEGIN 
		CASE c OF 
		| '0'..'9':  v := ORD( c ) - ORD( '0' )
		| 'a'..'f':   v := ORD( c ) - ORD( 'a' ) + 10
		| 'A'..'F':  v := ORD( c ) - ORD( 'A' ) + 10
		ELSE  
			HALT( 99 )
		END;  
		RETURN v
	END h2i;  

	(** Assigns the value of a hex string of length len to BigNumber b *)
	PROCEDURE AssignHex*( VAR b: BigNumber;  hex: ARRAY OF CHAR;  len: INTEGER );  
		VAR n, w, pos: LONGINT;  
	BEGIN 
		ASSERT( len <= LEN( hex ) - 1);  
		InitSize( b, 4*len );  b.len := (4*len + 31) DIV 32;
		n := b.len - 1;  w := 0;  pos := 0;
		WHILE len > 0 DO  
			w := w*16 + h2i( hex[pos] );  INC( pos );  DEC( len ); 
			IF len MOD 8 = 0 THEN  b.d[n] := w;  w := 0;  DEC( n )  END;
		END;  
		fixlen( b.d, b.len )
	END AssignHex;  
	
	(** Assigns the value of a binary string to b *)
	PROCEDURE AssignBin*( VAR b: BigNumber;  VAR buf: ARRAY OF CHAR;  pos, len: LONGINT );  
		VAR n, w: LONGINT;  
	BEGIN 
		ASSERT( (pos + len) <= LEN( buf ) );  
		InitSize( b, 8*len );  b.len := SHORT( (8*len + 31) DIV 32 );
		n := b.len - 1;  w := 0;
		WHILE len > 0 DO  
			w := w*256 + ORD( buf[pos] );  INC( pos );  DEC( len ); 
			IF len MOD 4 = 0 THEN  b.d[n] := w;  w := 0;  DEC( n )  END;
		END;  
		fixlen( b.d, b.len )
	END AssignBin;
	
	(** Returns the value of b as a binary string 'data' starting at ofs. The Length of 'data' must be longer or equal to 4*b.len + ofs.
		Author: FN *)
	PROCEDURE GetBinaryValue*( VAR b: BigNumber; VAR data: ARRAY OF CHAR; ofs: LONGINT );
		VAR j, n, tmp: LONGINT;
	BEGIN
		ASSERT( LEN( data ) >= 4 * b.len + ofs );
		FOR n := b.len-1 TO 0 BY -1 DO
			tmp := b.d[n];
			FOR j := 3 TO 0 BY - 1 DO
				data[ ofs + j ] := CHR( tmp MOD 256 );
				tmp := tmp DIV 256
			END;
			INC( ofs, 4 )
		END
	END GetBinaryValue;
	
	(** Assigns the value of val to b *)
	PROCEDURE Assign*( VAR b: BigNumber;  val: LONGINT );  
	BEGIN 
		Init( b );
		IF val < 0 THEN  b.neg := TRUE;  val := ABS( val ) END;
		IF val # 0 THEN  b.len := 1;  b.d[0] := val  ELSE  b.len := 0   END
	END Assign;  

	PROCEDURE cmpd( VAR a, b: digits;  len: INTEGER ): SHORTINT;   
	VAR i: INTEGER;  
	BEGIN 
		i := len - 1;  
		WHILE (i >= 0) & (a[i] = b[i]) DO  DEC( i )  END;  
		IF i < 0 THEN  RETURN 0
		ELSE 
			IF Less( b[i], a[i] ) THEN  RETURN 1  ELSE  RETURN -1  END
		END 
	END cmpd;  

	(* 1: |a| > |b|;  0: a = b;  -1:  |a| < {b| *)
	PROCEDURE ucmp( VAR a, b: BigNumber ): SHORTINT;
	BEGIN 
		IF a.len > b.len THEN  RETURN 1
		ELSIF a.len < b.len THEN  RETURN -1
		ELSE  RETURN cmpd( a.d, b.d, a.len )
		END 
	END ucmp;  

	(** 1: a > b;  0: a = b;  -1:  a < b *)
	PROCEDURE Cmp*( VAR a, b: BigNumber ): SHORTINT;
	BEGIN 
		IF a.neg # b.neg THEN 
			IF a.neg THEN  RETURN -1  ELSE  RETURN 1  END 
		ELSIF a.neg THEN  RETURN ucmp( a, b ) * (-1)
		ELSE  RETURN ucmp( a, b )
		END 
	END Cmp;  
	
	PROCEDURE copy( a, b: digits;  len: INTEGER );   
	VAR i: INTEGER;  
	BEGIN
		FOR i := 0 TO len - 1 DO  b[i] := a[i]  END
	END copy;  

	(** b := a *)
	PROCEDURE Copy*( VAR a, b: BigNumber );
	BEGIN 
		ASSERT( it( a ) );  
		IF S.ADR( a ) # S.ADR( b ) THEN  InitSize( b, a.len*32 );  copy( a.d, b.d, a.len );  b.len := a.len  END
	END Copy;  

	PROCEDURE Invert( x: LONGINT ): LONGINT;  
	BEGIN 
		RETURN S.VAL( LONGINT, -S.VAL( SET, x ) )
	END Invert;  

	PROCEDURE add( a, b, c: digits;  al, bl: INTEGER;  VAR cl: INTEGER );  
	VAR i: INTEGER;  A, B, x: LONGINT;  carry: BOOLEAN;
	BEGIN 
		cl := max( al, bl );  carry := FALSE;  
		FOR i := 0 TO cl - 1 DO 
			IF i >= al THEN  A := 0  ELSE  A := a[i]  END;  
			IF i >= bl THEN  B := 0  ELSE  B := b[i]  END;  
			x := A + B;
			IF carry THEN  INC( x );  carry := LessEq( Invert( A ), B )  ELSE  carry := Less( x, B )  END;
			c[i]:= x	;
		END;  
		IF carry  THEN  c[cl] := 1;  INC( cl )  END;  
	END add;  

	PROCEDURE sub( a, b, c: digits;  al, bl: INTEGER;  VAR cl: INTEGER );  
	VAR i: INTEGER;  A, B, x: LONGINT;  borrow: BOOLEAN;
	BEGIN 
		cl := max( al, bl );  borrow := FALSE;  
		FOR i := 0 TO cl - 1 DO 
			IF i >= al THEN  A := 0  ELSE  A := a[i]  END;  
			IF i >= bl THEN  B := 0  ELSE  B := b[i]  END;  
			x := A - B;
			IF borrow THEN  DEC( x );  borrow := LessEq( A, B )  ELSE  borrow := Less( A, B )  END;
			c[i]:= x
		END;  
		ASSERT( ~borrow );
		WHILE (cl > 0) & (c[cl - 1] = 0) DO  DEC( cl )  END;
	END sub;  

	(** c := a + b *)
	PROCEDURE Add*( VAR a, b, c: BigNumber );
		VAR 
			sd: digits;  
			l, sl: INTEGER;
			bn: BigNumber;
	BEGIN 
		ASSERT( it( a ) & it( b ) );  l := max( a.len, b.len ) + 1;
		IF (S.ADR( c ) # S.ADR( a )) & (S.ADR( c ) # S.ADR( b )) THEN  c.len := 0;  InitSize( c, l*32 );  sd := c.d
		ELSIF LEN( c.d^ ) < l THEN  
			bn := GetBuffer( );
			sd := bn.d;  adjust( sd, 0, l )  
		ELSE sd := c.d
		END;
		IF a.neg = b.neg THEN  add( a.d, b.d, sd, a.len, b.len, sl );  c.neg := a.neg
		ELSE 
			IF ucmp( a, b ) >= 0 THEN  sub( a.d, b.d, sd, a.len, b.len, sl );  c.neg :=  a.neg
			ELSE  sub( b.d, a.d, sd, b.len, a.len, sl );  c.neg := ~a.neg
			END
		END;
		IF sd # c.d THEN  adjust( c.d, 0, sl );  copy( sd, c.d, sl )  END;
		c.len := sl;
		IF Zero( c ) THEN  c.neg := FALSE  END;
		RecycleBuffer( bn )
	END Add;  

	(** c := a - b *)
	PROCEDURE Sub*( VAR a, b, c: BigNumber ); 
		VAR 
			sd: digits;  
			l, sl: INTEGER;
			bn: BigNumber;
	BEGIN 
		ASSERT( it( a ) & it( b ) );  l := max( a.len, b.len ) + 1;
		IF (S.ADR( c ) # S.ADR( a )) & (S.ADR( c ) # S.ADR( b )) THEN  c.len := 0;  InitSize( c, l*32 );  sd := c.d
		ELSIF LEN( c.d^ ) < l THEN  
			bn := GetBuffer( );
			sd := bn.d;  adjust( sd, 0, l )  
		ELSE sd := c.d
		END;
		IF a.neg # b.neg THEN  add( a.d, b.d, sd, a.len, b.len, sl );  c.neg := a.neg
		ELSE 
			IF ucmp( a, b ) >= 0  THEN  sub( a.d, b.d, sd, a.len, b.len, sl );  c.neg :=  a.neg
			ELSE  sub( b.d, a.d, sd, b.len, a.len, sl );  c.neg := ~a.neg
			END
			END;
		IF sd # c.d THEN  adjust( c.d, 0, sl );  copy( sd, c.d, sl )  END;
		c.len := sl;
		IF Zero( c ) THEN  c.neg := FALSE  END;
		RecycleBuffer( bn )
	END Sub;  
	
	(* high | low := b * c *)
	PROCEDURE LongMult( VAR high, low: LONGINT;  b, c: LONGINT );
	VAR bh, bl, ch, cl, u, t: LONGINT;  
	BEGIN 
		bh := S.LSH( b, -16 );  bl := b MOD 10000H;  ch := S.LSH( c, -16 );  cl := c MOD 10000H;  
		low := bl*cl;  t := ch*bl;  u := cl*bh;  high := bh*ch;  
		INC( t, u );  
		IF Less( t, u ) THEN  INC( high, 10000H )  END;  
		u := t*10000H;  INC( low, u );  
		IF Less( low, u ) THEN  INC( high )  END;  
		INC( high, S.LSH( t, -16 ) )
	END LongMult;  
	
	(* c := a*b *)
	PROCEDURE mul( a, b, c: digits;  al, bl: INTEGER;  VAR cl: INTEGER );
	VAR high, low, prod, sum, tmp, mulc: LONGINT;  addc: BOOLEAN;  i, j: INTEGER;  pl: INTEGER;  p: digits;  bn: BigNumber;
	BEGIN
		pl := 0;  bn := GetBuffer( ); adjust(bn.d, 0, al + bl + 2); p := bn.d;
		FOR i := 0 TO al + bl + 2 DO  p[i] := 0  END;	(* clear acc *)
		FOR i := 0 TO bl - 1 DO  mulc := 0;  addc := FALSE;  pl := i;  
			FOR j := 0 TO al - 1 DO   tmp := p[pl];
				LongMult( high, low, a[j], b[i] );  prod := low + mulc;
				IF Less( prod, low ) THEN  INC( high )  END;
				mulc := high;  sum := prod + tmp;  
				IF addc THEN  INC( sum );  addc := LessEq( Invert( prod ), tmp )  ELSE  addc := Less( sum, tmp )  END;
				p[pl] := sum;  INC( pl );  
			END;  
			IF addc OR (mulc # 0) THEN  
				IF addc THEN  INC( mulc )  END;
				p[pl] := mulc;  INC( pl )
			END;
		END;
		copy( p, c, pl );  cl := pl;  fixlen( c, cl );
		RecycleBuffer( bn )
	END mul;  
	
	(* c := a*b *)
	PROCEDURE muls( a: digits;  b: LONGINT; c: digits;  al: INTEGER;  VAR cl: INTEGER ); 
		VAR high, low, tmp, carry: LONGINT;  i: INTEGER;  
	BEGIN 
		carry := 0;  cl := al;
		FOR i := 0 TO al - 1 DO 
			LongMult( high, low, a[i], b );  tmp := low + carry;
			IF Less( tmp, low ) THEN  INC( high )  END;
			carry := high;  c[i] := tmp
		END;  
		IF carry # 0 THEN  c[cl] := carry;  INC( cl )  END
	END muls;  
	
	(** c := a * b *)
	PROCEDURE Mul*( VAR a, b, c: BigNumber );
		VAR pd: digits;  l, pl: INTEGER; bn: BigNumber;
	BEGIN 
		ASSERT( it( a ) & it( b ) ); 
		IF (a.len = 0) OR (b.len = 0) THEN Assign( c, 0 );  RETURN END;  
		l := a.len + b.len;
		IF (S.ADR( c ) # S.ADR( a )) & (S.ADR( c ) # S.ADR( b )) THEN  c.len := 0;  InitSize( c, l*32 );  pd := c.d
		ELSIF LEN( c.d^ ) < l THEN  bn := GetBuffer( ); pd := bn.d;  adjust( pd, 0, l )  
		ELSE pd := c.d
		END;
		IF a.len >= b.len THEN  mul( a.d, b.d, pd, a.len, b.len, pl )
		ELSE  mul( b.d, a.d, pd, b.len, a.len, pl )
		END;  
		IF pd # c.d THEN  adjust( c.d, 0, pl );  copy( pd, c.d, pl )  END;
		c.len := pl;  c.neg := a.neg # b.neg;
		RecycleBuffer( bn )
	END Mul;  
	
	(* a DIV b *)
	PROCEDURE div64( VAR a: dig2;  VAR b: LONGINT ): LONGINT; 
		VAR bit: INTEGER;  q, r: LONGINT;  overflow: BOOLEAN;
	BEGIN 
		IF a[1] = 0 THEN 
			IF (a[0] >= 0) & (b >= 0 ) THEN  RETURN a[0] DIV b 
			ELSIF Less( a[0], b ) THEN  RETURN 0
			ELSIF a[0] = b THEN  RETURN 1
			END;
			bit := 31
		ELSIF a[1] = b THEN  RETURN -1
		ELSE bit := 63
		END; 
		q := 0;  r := 0;  
		WHILE (bit >= 0) & ~(bit MOD 32 IN S.VAL( SET, a[bit DIV 32]) ) DO  DEC( bit )  END;
		WHILE bit >= 0 DO  
			overflow := r < 0;  r := ASH( r, 1 );
			IF bit MOD 32 IN S.VAL( SET, a[bit DIV 32] ) THEN  INC( r )  END;
			IF overflow OR LessEq( b, r ) THEN  r := r - b; 
				IF bit < 32 THEN  INCL( S.VAL( SET, q ), bit )  ELSE  q := -1  END;
			END;
			DEC( bit )
		END;
		RETURN q
	END div64;  
	
	(* a DIV b *)
	PROCEDURE div96( VAR a: dig3;  VAR b: dig2 ): LONGINT; 
	VAR bit: INTEGER;  r: dig2;  q: LONGINT;  overflow, borrow: BOOLEAN;
	
		PROCEDURE ge( VAR a, b: dig2 ): BOOLEAN;
		BEGIN 	
			IF a[1] = b[1] THEN  RETURN ~Less( a[0], b[0] )  ELSE  RETURN ~Less( a[1], b[1] )  END
		END ge;
		
		PROCEDURE shift( VAR x: dig2 );
		BEGIN 	
			overflow := x[1] < 0;  x[1] := ASH( x[1], 1 );
			IF x[0] < 0 THEN  INC( x[1] )  END;
			x[0] := ASH( x[0], 1 );
		END shift; 

	BEGIN 
		IF a[2] = 0 THEN 
			IF Less( a[1], b[1] ) THEN  RETURN 0  END;
			bit := 63
		ELSE  bit := 95
		END; 
		q := 0;  r[0] := 0;  r[1] := 0;  
		WHILE (bit >= 0) & ~(bit MOD 32 IN S.VAL( SET, a[bit DIV 32]) ) DO  DEC( bit )  END;
		WHILE bit >= 0 DO  
			shift( r );	(* r := r*2 *)
			IF bit MOD 32 IN S.VAL( SET, a[bit DIV 32] ) THEN  INC( r[0] )  END;
			IF overflow OR ge( r, b ) THEN  
				borrow := LessEq( r[0], b[0] );  r[0] := r[0] - b[0];  r[1] := r[1] - b[1];
				IF borrow  THEN  DEC( r[1] )  END;
				IF bit < 32 THEN  INCL( S.VAL( SET, q ), bit )  ELSE  q := -1  END;
			END;
			DEC( bit )
		END;
		RETURN q
	END div96;  
	
	(** q := a DIV b;  r := a MOD b *)
	PROCEDURE Div2*( VAR a, b, q, r: BigNumber ); 
	VAR x: LONGINT;  td, sd, bd, qd: digits;  i, tail, bl, tl, sl, ql, qi: INTEGER;  aq, ar: LONGINT;
		t3: dig3;  t2, d0: dig2; bn1, bn2, divq: BigNumber;
	BEGIN 
		aq := S.ADR( q );   ar := S.ADR( r );  
		ASSERT( it( a ) & it( b ) & ~Zero( b ) & ~b.neg & (aq # ar) );
		IF (aq # S.ADR( a )) & (aq # S.ADR( b )) THEN  InitSize( q, a.len*32 );  qd := q.d  ELSE divq := GetBuffer( ); qd := divq.d  END;
		
		x := ucmp( a, b );  
		IF x < 0 THEN  Assign( q, 0 );  Copy( a, r )
		ELSIF x = 0 THEN  Assign( q, 1 );  Assign( r, 0 )
		ELSE  
			bn1 := GetBuffer( ); 
			td := bn1.d;  
			bn2 := GetBuffer( );
			sd := bn2.d;  
			bd := b.d;  
			bl := b.len;  
			d0[1] := bd[bl - 1];
			IF bl > 1 THEN  d0[0] := bd[bl - 2]  ELSE  d0[0] := 0  END;
			FOR i := 1 TO bl DO  td[bl - i] := a.d[a.len - i]  END; 
			tl := bl;  tail := a.len - bl;  ql := tail + 1;  qi := ql;
			LOOP 
					IF tl < bl THEN  x := 0; 
					ELSE i := tl  - 1;
						IF d0[0] = 0 THEN  
							IF tl > bl THEN  t2[1] := td[i];  DEC( i )  ELSE  t2[1] := 0  END;
							t2[0] := td[i];
							x := div64( t2, d0[1] );
						ELSE  
							IF tl > bl THEN  t3[2] := td[i];  DEC( i )  ELSE  t3[2] := 0  END;
							t3[1] := td[i];  
							IF i > 0 THEN  t3[0] := td[i - 1]  ELSE  t3[0] := 0   END;
							x := div96( t3, d0 ); 
						END
					END;
					IF x # 0 THEN  muls( bd, x, sd, bl, sl );  
						WHILE (sl > tl) OR ((sl = tl) & (cmpd( sd, td, sl ) > 0)) DO 
							sub( sd, bd, sd, sl, bl, sl );  DEC( x ); 
						END;  
						sub( td, sd, td, tl, sl, tl ); 
					END;
					IF (qi = ql) & (x = 0) THEN  DEC( ql );  DEC( qi )  ELSE  DEC( qi );  qd[qi] := x  END;
					IF tail = 0 THEN  EXIT  END;
					DEC( tail );
					FOR i := tl TO 1 BY -1 DO  td[i] := td[i - 1]  END;  td[0] := a.d[tail];  INC( tl ); 
			END;  
			IF qd # q.d THEN  InitSize( q, ql*32 );  copy( qd, q.d, ql )  END;
			q.len := ql;
			InitSize( r, tl*32 );  copy( td, r.d, tl );  r.len := tl
		END;
		IF q.len = 0 THEN  q.neg := FALSE  ELSE  q.neg := a.neg  END;
		IF (r.len # 0) & a.neg THEN  Dec( q );  Sub( b, r, r )  END;
		RecycleBuffer( bn1 );
		RecycleBuffer( bn2 );
		RecycleBuffer( divq );
	END Div2;  
	
	(**  a MOD b *)
	PROCEDURE ModWord*( VAR a: BigNumber;  b: LONGINT ): LONGINT; 
	VAR x: LONGINT;  td, sd, bd: digits; tail, tl, sl, bl: INTEGER;  t2: dig2; bn1, bn2, bn3: BigNumber;
	BEGIN 
		ASSERT( it( a ) );
		bn1 := GetBuffer( );
		td := bn1.d;  
		bn2 := GetBuffer( );
		sd := bn2.d;  
		bn3 := GetBuffer( );
		bd := bn3.d;
		bd[0] := b;  bl := 1;  td[0] := a.d[a.len - 1];  tl := 1;  tail := a.len - 1; 
		LOOP 
				IF tl > 1 THEN  t2[1] := td[1]  ELSE  t2[1] := 0  END;
				t2[0] := td[0];
				x := div64( t2, b );
				IF x # 0 THEN  muls( bd, x, sd, bl, sl );  
					WHILE (sl > tl) OR ((sl = tl) & (cmpd( sd, td, sl ) > 0)) DO 
						sub( sd, bd, sd, sl, bl, sl );  DEC( x ); 
					END;  
					sub( td, sd, td, tl, sl, tl ); 
				END;
				IF tail <= 0 THEN  EXIT  END;
				DEC( tail );
				IF td[0] = 0 THEN  tl := 1  ELSE td[1] := td[0];  tl := 2  END;
				td[0] := a.d[tail]; 
		END;  
		RecycleBuffer( bn1 );
		RecycleBuffer( bn2 );
		RecycleBuffer( bn3 );
		RETURN td[0]
	END ModWord;  
	
	(**  q := a DIV b *)
	PROCEDURE Div*( VAR a, b, q: BigNumber ); 
		VAR dummy: BigNumber;
	BEGIN
		dummy := GetBuffer( );
		Div2( a, b, q, dummy );
		RecycleBuffer( dummy )
	END Div;
	
	(**  r := a MOD b *)
	PROCEDURE Mod*( VAR a, b, r: BigNumber ); 
		VAR dummy: BigNumber;
	BEGIN
		dummy := GetBuffer( );
		Div2( a, b, dummy, r );
		RecycleBuffer( dummy )
	END Mod;
	
	PROCEDURE BitSize*( VAR b: BigNumber ): INTEGER;  
	VAR n, t: LONGINT;
	BEGIN 
		IF b.len = 0 THEN  RETURN 0
		ELSE  n := (b.len - 1) * 32
		END;
		t := b.d[b.len - 1];
		WHILE t # 0 DO  INC( n );  t := S.LSH( t, -1 )  END;
		RETURN SHORT( n )
	END BitSize;  
	
	PROCEDURE BitSet*( VAR b: BigNumber; n: LONGINT ): BOOLEAN;  
	VAR w, bit: LONGINT;
	BEGIN 
		w := n DIV 32;  bit := n MOD 32; 
		IF w >= b.len THEN  RETURN FALSE
		ELSE  RETURN  bit IN S.VAL( SET, b.d[w] )
		END
	END BitSet;  
	
	(** c := a ^ b *)
	PROCEDURE Exp*( VAR a, b, c: BigNumber );
	VAR e, v: digits; i: LONGINT; vl, el: INTEGER; bn1, expv: BigNumber;
	BEGIN 
		IF (c.d = a.d) OR (c.d = b.d) THEN  bn1 := GetBuffer( ); e := bn1.d  ELSE  e := c.d  END;
		expv := GetBuffer( ); v := expv.d;  copy( a.d, v, a.len );  vl := a.len;
		IF ODD( b.d[0] ) THEN  copy( a.d, e, a.len );  el := a.len  ELSE  el := 1; e[0] := 1  END;
		FOR i := 1 TO BitSize( b ) - 1 DO  mul( v, v, v, vl, vl, vl ); 
			IF BitSet( b, i ) THEN   mul( v, e, e, vl, el, el )  END;
		END;
		IF c.d # e THEN  adjust( c.d, 0, el );  copy( e, c.d, el )  END;
		c.len := el;  fixlen( c.d, c.len );
		RecycleBuffer( bn1 );
		RecycleBuffer( expv )
	END Exp;  
	
	(** r := (a * b) mod m *)
	PROCEDURE ModMul*( VAR a, b, m, r: BigNumber );
		VAR mmp: BigNumber;
	BEGIN {EXCLUSIVE}
		mmp := GetBuffer( );
		Mul( a, b, mmp );  
		Mod( mmp, m, r );
		RecycleBuffer( mmp )
	END ModMul;  
	
	PROCEDURE wbits( exp: BigNumber ): INTEGER;  
	VAR b, w: INTEGER;
	BEGIN 
		(* window bits for exponent size,  for sliding window ModExp functions *)
		b := BitSize( exp );
		IF b <= 23 THEN  w := 1
		ELSIF b <= 79 THEN  w := 3
		ELSIF b <= 239 THEN  w := 4
		ELSIF b <= 671 THEN  w := 5
		ELSE  w := 6
		END;
		RETURN w
	END wbits;  
	
	(** a ^ b MOD m *)
	PROCEDURE ModExp*( VAR a, b, m: BigNumber ): BigNumber;
		VAR 
			a0: ARRAY 32 OF BigNumber;
			d, r: BigNumber;
			wsize, v, wstart, e, i, j, tsize: LONGINT;
	BEGIN
		ASSERT( it( a ) & it( b ) & it( m ) );  
		IF Zero( b ) THEN 
			IF Zero( a ) THEN HALT( 100 ) END;  
			Assign( r, 1 );  RETURN r
		END;  
		IF Zero( m ) THEN  HALT( 101 )  END;  
		IF m.neg THEN  HALT( 102 )  END; 
		
		tsize := (2*m.len+1)*32;  InitSize( r, tsize );
		Mod( a, m, a0[0] );  M.Init( m );  M.Convert( a0[0] );  wsize := wbits( b ); 
		
		IF wsize > 1 THEN  (* precompute window multipliers *)
			InitSize( d, tsize );  M.Mult( a0[0], a0[0], d );  j := ASH( 1, wsize - 1 );
			FOR i := 1 TO j -1 DO  InitSize( a0[i], tsize );  M.Mult( a0[i - 1], d, a0[i] )  END;
		END;
		
		Copy( a0[0], r );  wstart := BitSize( b ) - 2; 
		WHILE wstart >= 0 DO  M.Mult( r, r, r );
			IF BitSet( b, wstart ) THEN  v := 1;  e := 0;  i := 1;
				WHILE (i < wsize) & (wstart - i >= 0) DO 
					IF BitSet( b, wstart - i ) THEN  v := ASH( v, i - e ) + 1;  e := i  END;
					INC( i )
				END;
				FOR i := 1 TO e DO  M.Mult( r, r, r )  END;
				M.Mult( r, a0[v DIV 2], r );	(*  v will be an odd number < 2^wsize *)
				DEC( wstart, e + 1 ); 
			ELSE DEC( wstart )
			END
		END;
		M.Reduce( r );
		RETURN r
	END ModExp;  
	
	PROCEDURE Zero*( VAR x: BigNumber ): BOOLEAN;
	BEGIN 
		RETURN (x.len = 0) OR ((x.len = 1) & (x.d[0] = 0))
	END Zero;
	
	PROCEDURE Dec*( VAR x: BigNumber );
	VAR i: INTEGER;
	BEGIN 
		i := 0;
		IF Zero( x ) THEN  x.len := 1;  x.neg := TRUE;  x.d[0] := 1
		ELSIF x.neg THEN  
			WHILE (x.d[i] = -1) & (i < x.len) DO  x.d[i] := 0;  INC( i )  END;
			IF i = x.len THEN  x.d[i] := 1;  INC( x.len )  ELSE  INC( x.d[i] )  END
		ELSE  
			WHILE x.d[i] = 0 DO  x.d[i] := -1;  INC( i )  END;
			DEC( x.d[i] );  fixlen( x.d, x.len )
		END
	END Dec;
	
	PROCEDURE Inc*( VAR x: BigNumber );
	VAR i: INTEGER;
	BEGIN 
		i := 0;
		IF ~x.neg THEN  
			WHILE (x.d[i] = -1) & (i < x.len) DO  x.d[i] := 0;  INC( i )  END;
			IF i = x.len THEN  x.d[i] := 1;  INC( x.len )  ELSE  INC( x.d[i] )  END
		ELSE  
			WHILE x.d[i] = 0 DO  x.d[i] := -1;  INC( i )  END;
			DEC( x.d[i] );  fixlen( x.d, x.len );
			IF x.len = 0 THEN  x.neg := FALSE  END
		END
	END Inc;
	
	PROCEDURE Mask*( VAR x: BigNumber; bits: INTEGER );
	VAR w, b: INTEGER;  
	BEGIN 
		w := bits DIV 32;  b := bits MOD 32;  x.len := w;
		IF b # 0 THEN  INC( x.len );  
			x.d[w] := S.VAL( LONGINT,  S.VAL( SET, x.d[w] ) * {0..b} )
		END
	END Mask;

	(** r := gcd( a, b ) *)
	PROCEDURE GCD*( VAR a, b, r: BigNumber );
	VAR x, y: BigNumber;
	BEGIN 
		ASSERT( ~a.neg & ~b.neg );
		Copy( a, x );  Copy( b, y );
		LOOP
			IF Cmp( x, y ) > 0 THEN  Mod( x, y, x ); 
				IF Zero( x ) THEN  Copy( y, r );  RETURN  END
			ELSE  Mod( y, x, y ) ;
				IF Zero( y ) THEN  Copy( x, r );  RETURN  END
			END;
		END;
	END GCD;
	
	(** Return x so that (x * a) mod m = 1 *)
	PROCEDURE ModInverse*( VAR a, m, x: BigNumber );
	VAR 
		q, t: BigNumber;
		g, v: ARRAY 3 OF BigNumber;
		p, i, s, tmp, n: LONGINT;
	BEGIN
		FOR i := 0 TO 2 DO
			Assign( g[i], 0 ); 
			Assign( v[i], 0 ) 
		END;
		Copy( a, g[0] );  
		Copy( m, g[1] ); 
		Assign( v[0], 1 );  
		Assign( v[1], 0 );
		p := 0;  
		i := 1;  
		s := 2;  
		n := 0;
		LOOP 
			Div2( g[p], g[i], q, g[s] );  
			Mul( q, v[i],  t );  
			Add( v[p], t, v[s] );  
			INC( n );
			IF Zero( g[s] ) THEN  
				EXIT  
			END;
			tmp := p;  
			p := i;  
			i := s;  
			s := tmp;  
		END;
		IF (g[i].len = 1 ) & (g[i].d[0] = 1) THEN  
			IF ODD( n ) THEN  
				Sub( m, v[i], v[i] )  
			END;
			Mod( v[i], m, x )
		ELSE  
			Assign( x, 0 )
		END
	END ModInverse;
	
	PROCEDURE Shift*( VAR x: BigNumber;  n: INTEGER );
	VAR
		right: BOOLEAN;  
		w, bits, i, l: INTEGER;  
		a, b: LONGINT;
	BEGIN
		IF x.len = 0 THEN  
			RETURN  
		END;
		IF n < 0 THEN  
			right := TRUE;  
			n := ABS( n )  
		ELSE  
			right := FALSE  
		END;
		w := n DIV 32;  
		bits := n MOD 32; 
		IF ~right THEN  
			adjust( x.d, x.len, x.len + w + 1 );
			IF w > 0 THEN
				FOR i := x.len - 1 TO 0 BY -1 DO  
					x.d[i + w] := x.d[i]  
				END;
				FOR i := 0 TO w - 1 DO  
					x.d[i] := 0  
				END;
				INC( x.len, w )
			END;
			IF bits > 0 THEN  x.d[x.len] := 0;  
				FOR i := x.len TO 0 BY -1 DO  
					a := x.d[i];
					IF i > 0 THEN  
						b := x.d[i - 1]  
					ELSE  
						b := 0  
					END;
					x.d[i] := S.LSH( a, bits ) + S.LSH( b, -32 + bits )
				END;
				IF x.d[x.len] # 0 THEN  
					INC( x.len )  
				END;
			END
		ELSE
			IF w > 0 THEN
				FOR i := 0 TO x.len - w - 1 DO  
					x.d[i] := x.d[i + w]  
				END;
				DEC( x.len, w )
			END;
			IF bits > 0 THEN  l := x.len;  
				FOR i := 0 TO  l - 1 DO  a := x.d[i];  
					IF i < l - 1 THEN  
						b := x.d[i + 1]  
					ELSE  
						b := 0  
					END;
					x.d[i] := S.LSH( a, -bits ) + S.LSH( b, 32 - bits ) 
				END;
				IF x.d[l - 1] = 0 THEN  
					DEC( x.len )  
				END;
			END
		END;
	END Shift;
	
	(** x := -x *)
	PROCEDURE Neg*( VAR x: BigNumber );
	BEGIN
		x.neg := ~x.neg
	END Neg;
	
	(*--------------------------- Text I/O ---------------------------------*)

	(** writes a hexadecimal representation of b to Writer w *)
	PROCEDURE TextWrite*( VAR w: AosIO.Writer;  VAR b: BigNumber );  
		VAR i: LONGINT;
	BEGIN 
		IF b.neg THEN w.String( "-" ) END;
		IF b.len = 0 THEN
			w.String( " 00000000" ) 
		ELSE
			i := b.len;
			WHILE i > 0 DO
				DEC( i );
				w.Hex( b.d[i], 2 ); 
				IF i > 0 THEN  
					IF i MOD 6 = 0 THEN
						w.Ln
					ELSE
						w.String( "  " ) 
					END
				END
			END 
		END;
		w.Char( '.' );
		w.Update
	END TextWrite;
	
	(** writes a hexadecimal representation of b to the standard output *)
	PROCEDURE Print*( VAR b: BigNumber );
		VAR i: LONGINT;
	BEGIN
		IF b.neg THEN AosOut.String( "-" ) END;
		IF b.len = 0 THEN
			AosOut.String( " 00000000" ) 
		ELSE
			i := b.len;
			WHILE i > 0 DO
				DEC( i );
				AosOut.Hex( b.d[i], 2 ); 
				IF i > 0 THEN  
					IF i MOD 6 = 0 THEN
						AosOut.Ln
					ELSE
						AosOut.String( "  " ) 
					END
				END
			END 
		END;
		AosOut.Char( '.' );
		AosOut.Ln
	END Print;
	
	PROCEDURE nibble( VAR r: AosIO.Reader ): CHAR;  
		VAR c: CHAR;  
	BEGIN 
		REPEAT 
			REPEAT
				r.Char( c )
			UNTIL (c > ' ') OR (r.Available() = 0);  
		UNTIL (r.Available() = 0) OR (c >= '0') & (c <= '9') OR (c >= 'A') & (c <= 'F') OR (c >= 'a') & (c <= 'f') OR (c = '.');  
		RETURN c
	END nibble;  

	PROCEDURE TextRead*( r: AosIO.Reader;  VAR b: BigNumber ); 
	VAR
		buf: ARRAY 2048 OF CHAR;
		i: INTEGER; 
		n: CHAR;
	BEGIN 
		i := 0;
		n := nibble( r );  
		WHILE n # '.' DO
			buf[i] := n;
			INC( i );
			n := nibble( r )
		END;  
		AssignHex( b, buf, i )
	END TextRead;
	
	(** Dumps the given BigNumber to the given Writer *)
	PROCEDURE Dump*( str: ARRAY OF CHAR;  VAR b: BigNumber; w: AosIO.Writer );  
	BEGIN 
		w.String( str );
		TextWrite( w, b );
		w.Ln;
		w.Update( )
	END Dump;  
	
	(*--------------------------- File I/O ---------------------------------*)

	PROCEDURE FileRead*( VAR r: AosFS.Reader ; VAR b: BigNumber );
		VAR i, j: INTEGER;
	BEGIN
		r.RawInt( j );
		InitSize( b, 32 * j );
		b.len := j; 
		FOR i := 0 TO j-1 DO  r.RawLInt( b.d[ i ] )  END
	END FileRead;
	
	PROCEDURE FileWrite*( VAR r: AosFS.Writer;  VAR b: BigNumber );
		VAR i, j: INTEGER;
	BEGIN
		j := b.len;
		r.RawInt( j );
		FOR i := 0 TO j - 1 DO  r.RawLInt( b.d[ i ] )  END
	END FileWrite;
	
	(* ------------ buffer pooling to make this module thread-save (F.N.) -----------------------*)
	
	PROCEDURE GetBuffer(): BigNumber;
		VAR bn: BigNumber;
	BEGIN {EXCLUSIVE}
		IF nextFreeBuffer > -1 THEN
			bn := bufferPool[ nextFreeBuffer ];
			DEC( nextFreeBuffer )
		ELSE
			InitSize( bn, 4096 )
		END;
		RETURN bn
	END GetBuffer;
	
	PROCEDURE RecycleBuffer( bn: BigNumber );
	BEGIN {EXCLUSIVE}
		IF bn.d = NIL THEN RETURN END;
		IF nextFreeBuffer < BufferPoolSize - 1 THEN
			INC( nextFreeBuffer );
			bufferPool[ nextFreeBuffer ] := bn
		END
	END RecycleBuffer;

	PROCEDURE InitRandomgenerator();
	BEGIN
			NEW(randomgenerator);
			randomgenerator.InitSeed(AosKernel.GetTimer());
	END InitRandomgenerator;

BEGIN 
	ASSERT( S.VAL( LONGINT, {0}) = 1 );
	NEW( M );
	FOR nextFreeBuffer := 0 TO BufferPoolSize-1 DO
		InitSize( bufferPool[ nextFreeBuffer ], 4096 )
	END;
	nextFreeBuffer := BufferPoolSize-1;
	(*
	InitSize( adds, 2048 );
	InitSize( mulp, 4096 );
	InitSize( mulp2, 4096 ); 
	InitSize( divt, 2048 );
	InitSize( divs, 2048 );
	InitSize( divq, 2048 ); 
	InitSize( expe, 2048 );
	InitSize( expv, 2048 );  
	InitSize( mmp, 1600);
	InitSize( dummy, 2048);
	*)

	InitRandomgenerator();
END AosCryptoBigNumbers.


System.Free AosCryptoUtils AosCryptoBigNumbers ~