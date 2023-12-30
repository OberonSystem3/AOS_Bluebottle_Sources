MODULE CRC; (** AUTHOR "prk/TF"; PURPOSE "CRC utilities"; *)
(**
 * History:
 *	
 *	28.09.2000	added CRC32 support -- TF 
 *	08.01.2007	added SetCRC procedures to enable other initial values (staubesv)
 *)

IMPORT
	SYSTEM, AosIO;

CONST
	Init16 = -1;	(* initial CRC16 value *)
	Init32 = 0FFFFFFFFH;  (* initial CRC32 value *)

TYPE
	CRC16Stream* = OBJECT(AosIO.Writer)
	VAR
		crc* : INTEGER;
	
		PROCEDURE  &InitStream;
		BEGIN
			crc := Init16;
			InitWriter(Send, 256)
		END InitStream;
		
		PROCEDURE Send*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
			VAR fcs, idx: SET; addr, i, k: LONGINT;  
		BEGIN 
			fcs := SYSTEM.VAL( SET, crc ) * SYSTEM.VAL( SET, 0FFFFH );  
			FOR i := ofs TO ofs + len - 1 DO 
				idx := SYSTEM.VAL( SET, SYSTEM.VAL( LONGINT, fcs ) DIV 256 ) / SYSTEM.VAL( SET, LONG( ORD( buf[i] ) ) );
				fcs := CRC16Table[SYSTEM.VAL( LONGINT, idx) MOD 256] / SYSTEM.VAL( SET, SYSTEM.VAL( LONGINT, fcs ) * 256 )
			END;  
			crc := SHORT( SYSTEM.VAL( LONGINT, fcs * SYSTEM.VAL( SET, 0FFFFH ) ) );
			res := AosIO.Ok		
		END Send;
		
		PROCEDURE SetCRC*(crc : INTEGER);
		BEGIN
			Update();
			SELF.crc := crc;
		END SetCRC;
		
		PROCEDURE GetCRC*(): INTEGER;
		BEGIN
			Update();
			RETURN crc
		END GetCRC;		
		
	END CRC16Stream;

	CRC32Stream* = OBJECT(AosIO.Writer)
	VAR
		crc : LONGINT;
	
		PROCEDURE  &InitStream;
		BEGIN
			crc := Init32;
			InitWriter(Send, 256)
		END InitStream;
		
		PROCEDURE Reset*;
		BEGIN
			Update();
			crc := Init32
		END Reset;
		
		PROCEDURE Send*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		VAR idx: LONGINT;  
		BEGIN
			WHILE len > 0 DO
				idx := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, crc) / SYSTEM.VAL(SET, LONG(ORD(buf[ofs])))) MOD 100H;
				crc := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, CRC32Table[idx])/SYSTEM.VAL(SET, SYSTEM.LSH(crc, -8)));
				DEC(len); INC(ofs)
			END;
			res := AosIO.Ok		
		END Send;
		
		PROCEDURE SetCRC*(crc : LONGINT);
		BEGIN
			Update();
			SELF.crc := crc;
		END SetCRC;
		
		PROCEDURE GetCRC*():LONGINT;
		BEGIN
			Update();
			RETURN SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, crc)/{0..31})
		END GetCRC;
		
		PROCEDURE GetUninvertedCRC*():LONGINT;
		BEGIN
			Update();
			RETURN crc
		END GetUninvertedCRC;
	END CRC32Stream;

VAR
	CRC16Table, CRC32Table: ARRAY 256 OF SET;  

	PROCEDURE InitTable16;
	VAR fcs, t: SET;  d, addr, i, k: LONGINT;
	BEGIN
		FOR i := 0 TO 255 DO
			fcs := { };  d := i*256;
			FOR k := 0 TO 7 DO
				t := fcs;  fcs := SYSTEM.VAL( SET, SYSTEM.VAL( LONGINT, fcs ) * 2 );
				IF (t / SYSTEM.VAL( SET, d )) * SYSTEM.VAL( SET, 8000H ) # {} THEN  fcs := fcs / SYSTEM.VAL( SET, 1021H ) END;
				d := d * 2
			END;
			CRC16Table[i] := fcs * SYSTEM.VAL( SET, 0FFFFH )
		END
	END InitTable16; 	

	PROCEDURE InitTable32;
	CONST poly = 0EDB88320H;
	VAR n, c, k: LONGINT;
	BEGIN
		FOR n := 0 TO 255 DO
			c := n;
			FOR k := 0 TO 7 DO
				IF ODD(c) THEN c := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, poly) / SYSTEM.VAL(SET, SYSTEM.LSH(c, -1)))
				ELSE c := SYSTEM.LSH(c, -1)
				END
			END;
			CRC32Table[n] := SYSTEM.VAL(SET, c)
		END
	END InitTable32;

BEGIN
	InitTable16;
	InitTable32
END CRC.

S.Free CRC ~
