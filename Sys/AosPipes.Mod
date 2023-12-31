(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosPipes; (** AUTHOR "pjm"; PURPOSE "Simple pipe object"; *)
(* 2003.07.23 no tricks variant but working *)
IMPORT SYSTEM;

CONST
	Ok = 0;
	Closed = 4301;

TYPE
		(** A pipe is a bounded buffer that can be used as an AosIO Reader and Writer.  Everything sent to the sink can be read from the source. *)
	Pipe* = OBJECT
		VAR
			head, num: LONGINT;
			buffer: POINTER TO ARRAY OF CHAR;
		
		PROCEDURE Send*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate : BOOLEAN; VAR res: LONGINT);
		BEGIN 
			ASSERT(len >= 0);
			LOOP 
				BEGIN {EXCLUSIVE}
					IF len = 0 THEN res := Ok; EXIT END;
					AWAIT(num # LEN(buffer));
					IF num = -1 THEN res := Closed; EXIT END;
					buffer[(head+num) MOD LEN(buffer)] := buf[ofs];
					INC(ofs); INC(num); DEC(len)
				END
			END
		END Send;
		
		PROCEDURE Receive*(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		BEGIN 
			ASSERT((size > 0) & (min <= size) & (min >= 0));
			len := 0;
			LOOP
				BEGIN {EXCLUSIVE}
					IF min # 0 THEN AWAIT(num # 0) END;	(* wait until some data available *)
					IF num > 0 THEN
						IF num = -1 THEN res := Closed; EXIT END;
						buf[ofs] := buffer[head];
						head := (head + 1) MOD LEN(buffer);
						DEC(num); INC(ofs); INC(len); DEC(min); DEC(size);
					END;
					IF num = -1 THEN res := Closed; EXIT END;
					IF (num = 0) & (min <= 0) OR (size = 0) THEN res := Ok; EXIT END;
				END
			END
		END Receive;
		
		PROCEDURE &Init*(size: LONGINT);
		BEGIN
			head := 0; num := 0; NEW(buffer, size)	
		END Init;
		
		PROCEDURE Close*;
		BEGIN {EXCLUSIVE}
			num := -1
		END Close;
		
	END Pipe;
	
END AosPipes.

(*
What's wrong with this

(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosPipes; (** AUTHOR "pjm"; PURPOSE "Simple pipe object"; *)

IMPORT SYSTEM;

CONST
	Ok = 0;
	Closed = 4301;

TYPE
		(** A pipe is a bounded buffer that can be used as an AosIO Reader and Writer.  Everything sent to the sink can be read from the source. *)
	Pipe* = OBJECT
		VAR
			head, tail: LONGINT;	(* buffer[head..(tail-1) MOD LEN] contains data (circular).  one character is reserved. *)
			buffer: POINTER TO ARRAY OF CHAR;
		
		PROCEDURE Send*(VAR buf: ARRAY OF CHAR; ofs, len: LONGINT; propagate : BOOLEAN; VAR res: LONGINT);
		VAR n: LONGINT;
		BEGIN {EXCLUSIVE}
			ASSERT(len >= 0);
			LOOP
				IF len = 0 THEN res := Ok; EXIT END;
				AWAIT((tail+1) MOD LEN(buffer) # head);	(* some free space available *)
				IF head = -1 THEN res := Closed; EXIT END;
				IF tail >= head THEN n := LEN(buffer)-tail ELSE n := head-tail END;	(* contiguous free space *)
				IF n > len THEN n := len END;
				ASSERT(tail+n <= LEN(buffer));	(* index check *)
				SYSTEM.MOVE(SYSTEM.ADR(buf[ofs]), SYSTEM.ADR(buffer[tail]), n);
				tail := (tail+n) MOD LEN(buffer);
				INC(ofs, n); DEC(len, n)
			END
		END Send;
		
		PROCEDURE Receive*(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		VAR n: LONGINT;
		BEGIN {EXCLUSIVE}
			ASSERT((size > 0) & (min <= size) & (min >= 0));
			len := 0;
			LOOP
				IF min # 0 THEN AWAIT(head # tail) END;	(* wait until some data available *)
				IF head = -1 THEN res := Closed; EXIT END;
				IF tail >= head THEN n := tail-head ELSE n := LEN(buffer)-head END;	(* contiguous data *)
				IF n > size THEN n := size END;
				ASSERT(ofs+n <= LEN(buf));	(* index check *)
				SYSTEM.MOVE(SYSTEM.ADR(buffer[head]), SYSTEM.ADR(buf[ofs]), n);
				head := (head+n) MOD LEN(buffer);
				INC(ofs, n); INC(len, n); DEC(size, n);
				IF len >= min THEN res := Ok; EXIT END
			END
		END Receive;
		
		PROCEDURE &Init*(size: LONGINT);
		BEGIN
			head := 0; tail := 0; NEW(buffer, size+1)	(* reserve one character to distinguish full and empty buffer *)
		END Init;
		
		PROCEDURE Close*;
		BEGIN {EXCLUSIVE}
			head := -1
		END Close;
		
	END Pipe;
	
END AosPipes.



*)
