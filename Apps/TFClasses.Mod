MODULE TFClasses; (** AUTHOR "TF"; PURPOSE "Generic helper"; *)

TYPE
	ObjectArray* = POINTER TO ARRAY OF PTR;
	
	(** Generic Lockable Object List. *)
	List* = OBJECT 
		VAR
			list : ObjectArray;
			count : LONGINT;
			readLock : LONGINT;
		
		PROCEDURE &New*();
		BEGIN NEW(list, 8); readLock := 0
		END New;
		
		(** return the number of objects in the list. If count is used for indexing elements (e.g. FOR - Loop) in a multi-process 
			situation, the process calling the GetCount method should call Lock before GetCount and Unlock after the
			last use of an index based on GetCount *)
		PROCEDURE GetCount*():LONGINT;
		BEGIN 
			RETURN count
		END GetCount;
		
		PROCEDURE Grow;
		VAR old: ObjectArray;
				i : LONGINT;
		BEGIN 
			old := list;
			NEW(list, LEN(list)*2);
			FOR i := 0 TO count-1 DO list[i] := old[i] END
		END Grow;
		
		(** Add an object to the list. Add may block if number of calls to Lock is bigger than the number of calls to Unlock *)
		PROCEDURE Add*(x : PTR);
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			IF count = LEN(list) THEN Grow END;
			list[count] := x;
			INC(count)
		END Add;
		
		(** atomic replace x by y *)
		PROCEDURE Replace*(x, y : PTR);
		VAR i : LONGINT;
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			i := IndexOf(x);
			IF i >= 0 THEN list[i] := y END
		END Replace;
		
		(** return the index of an object. In a multi-process situation, the process calling the IndexOf method should 
			call Lock before IndexOf and Unlock after the last use of an index based on IndexOf.
			If the object is not found, -1 is returned *)
		PROCEDURE IndexOf *(x:PTR) : LONGINT;
		VAR i : LONGINT;
		BEGIN 
			i := 0 ; WHILE i < count DO IF list[i] = x THEN RETURN i END; INC(i) END;
			RETURN -1
		END IndexOf;
		
		(** Remove an object from the list. Remove may block if number of calls to Lock is bigger than the number of calls to Unlock *)
		PROCEDURE Remove*(x : PTR);
		VAR i : LONGINT;
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			i:=0; WHILE (i<count) & (list[i]#x) DO INC(i) END;
			IF i<count THEN 
				WHILE (i<count-1) DO list[i]:=list[i+1]; INC(i) END;
				DEC(count);
				list[count]:=NIL
			END
		END Remove;
		
		(** Removes all objects from the list. Clear may block if number of calls to Lock is bigger than the number of calls to Unlock *)
		PROCEDURE Clear*;
		VAR i : LONGINT;
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			FOR i := 0 TO count - 1 DO list[i] := NIL END;
			count := 0
		END Clear;
		
		(** return an object based on an index. In a multi-process situation, GetItem is only safe in a locked region Lock / Unlock *)
		PROCEDURE GetItem*(i:LONGINT) : PTR;
		BEGIN
			ASSERT((i >= 0) & (i < count), 101);
			RETURN list[i]	
		END GetItem;
		
		(** Lock prevents modifications to the list. All calls to Lock must be followed by a call to Unlock. Lock can be nested*)
		PROCEDURE Lock*;
		BEGIN {EXCLUSIVE}
			INC(readLock); ASSERT(readLock > 0)
		END Lock;
		
		(** Unlock removes one modification lock. All calls to Unlock must be preceeded by a call to Lock. *)
		PROCEDURE Unlock*;
		BEGIN {EXCLUSIVE}
			DEC(readLock); ASSERT(readLock >= 0)
		END Unlock;
	END List;	

END TFClasses.
 
System.Free TFClasses ~