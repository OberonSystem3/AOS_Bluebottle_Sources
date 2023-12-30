(** AUTHOR "rg"; PURPOSE "Memory reader"; *)

MODULE AosMemoryReader;

IMPORT SYSTEM, AosIO;

CONST
	DefaultReaderSize = 64;
	
TYPE
	Reader* = OBJECT (AosIO.Reader)
		VAR
			memoryAdr, available : LONGINT;

		PROCEDURE Receive(VAR buf: ARRAY OF CHAR; ofs, size, min : LONGINT; VAR len, res: LONGINT);
		BEGIN
			ASSERT(ofs+size <= LEN(buf));
			IF available # 0 THEN
				IF size >= available THEN len := available
				ELSE len := size END;
				SYSTEM.MOVE(memoryAdr, SYSTEM.ADR(buf[0])+ofs, len);
				INC(memoryAdr, len);
				DEC(available, len);
				res := AosIO.Ok
			ELSE
				len := 0;
				res := AosIO.EOF
			END
		END Receive;
	
		PROCEDURE &InitMemoryReader(memoryAdr, length : LONGINT);
		BEGIN
			SELF.memoryAdr := memoryAdr;
			available := length;
			InitReader(Receive, DefaultReaderSize);
		END InitMemoryReader;
	END Reader;
	
	PROCEDURE OpenReader(VAR r: Reader; memoryAdr, length : LONGINT);
	BEGIN
		NEW(r, memoryAdr, length)
	END OpenReader;

END AosMemoryReader.