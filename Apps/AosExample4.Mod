(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosExample4;	(* pjm *)

(*
Buffer allocator.
Ref: C.A.R. Hoare, "Monitors: An Operating System Structuring Concept", CACM 17(10), 1974
*)

TYPE
	Buffer* = OBJECT VAR next: Buffer; END Buffer;	(** must be extended by client *)
	
	BufferPool* = OBJECT
		VAR root: Buffer;
		
		PROCEDURE Acquire*(VAR buf: Buffer);	(** take a buffer from the pool *)
		BEGIN {EXCLUSIVE}
			AWAIT(root # NIL);
			buf := root; root := root.next
		END Acquire;

		PROCEDURE Release*(buf: Buffer);	(** add a buffer to the pool *)
		BEGIN {EXCLUSIVE}
			buf.next := root; root := buf
		END Release;

		PROCEDURE &Init;
		BEGIN
			root := NIL
		END Init;
		
	END BufferPool;

END AosExample4.
