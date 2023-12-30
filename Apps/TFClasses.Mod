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
	
TYPE
	
	(* CompareMethod defines a Method that compares two Objects. The Methods then returns:
		-1 if the first Object is "smaller" then the second Object
		0 if both Objects are "equal"
		1 if the first Object is "greater" then the second Object *)
	CompareMethod* = PROCEDURE {DELEGATE} (first, second: PTR): LONGINT;
	
	SortedList* = OBJECT(List);
	VAR
		compare: CompareMethod;
			
		PROCEDURE &Init*(m: CompareMethod);
		BEGIN 
			compare := m;
			NEW(list, 8); readLock := 0
		END Init;
		
		PROCEDURE SetCompareMethod*(m:CompareMethod);
		BEGIN
			compare := m;
		END SetCompareMethod;
	
		(** Add an object to the list. Add may block if number of calls to Lock is bigger than the number of calls to Unlock *)
		PROCEDURE Add*(x : PTR);
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			AddUnlocked(x);
		END Add;
		
		(* Does the actual Adding without locking (should already have been done by the caller) *)
		PROCEDURE AddUnlocked(x: PTR);
		VAR i, pos: LONGINT;
		BEGIN
			IF count = LEN(list) THEN Grow END;
		
			pos := FindPosition(x);
			i := count-1;
			WHILE i >= pos DO
				list[i+1] := list[i];
				DEC(i);
			END;
			list[pos] := x;			
			INC(count)
		END AddUnlocked;
		
		PROCEDURE FindPosition(x: PTR): LONGINT;
		VAR
			lowerBound, upperBound: LONGINT;
			middle: LONGINT;
			value: LONGINT;
		BEGIN
			IF count = 0 THEN RETURN 0; END;
			IF compare(list[0], x) >= 1 THEN RETURN 0; END;
			IF compare(list[count-1], x) <= -1 THEN RETURN count; END;
			lowerBound := 0;
			upperBound := count - 1;
			
			WHILE (upperBound - lowerBound) > 1 DO
				middle := (lowerBound + upperBound) DIV 2;
				value := compare(list[middle], x);
				IF value = 0 THEN RETURN middle; END;
				IF value < 0 THEN
					lowerBound := middle;
				ELSE
					upperBound := middle;
				END;
			END;
			
			IF compare(list[lowerBound], x) = 0 THEN
				RETURN lowerBound;
			ELSE
				RETURN upperBound;
			END;
		END FindPosition;
		
		(** Remove an object from the list. Remove may block if number of calls to Lock is bigger than the number of calls to Unlock *)
		PROCEDURE Remove*(x : PTR);
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			RemoveUnlocked(x);
		END Remove;

		(* Does the actual Removing without locking (should already have been done by the caller) *)
		PROCEDURE RemoveUnlocked(x: PTR);
		VAR i : LONGINT;
		BEGIN
			i:=0; WHILE (i<count) & (list[i]#x) DO INC(i) END;
			IF i<count THEN 
				WHILE (i<count-1) DO list[i]:=list[i+1]; INC(i) END;
				DEC(count);
				list[count]:=NIL
			END
		END RemoveUnlocked;

		(** atomic replace x by y. That means that x is removed and y is added to the SortedList *)
		PROCEDURE Replace*(x, y : PTR);
		BEGIN {EXCLUSIVE}
			AWAIT(readLock = 0);
			RemoveUnlocked(x);
			AddUnlocked(y);
		END Replace;
		
		(* searches and returns the PTR to an Object with the same key *)
		PROCEDURE SearchByKey*(x: PTR): PTR;
		VAR pos : LONGINT;
		BEGIN {EXCLUSIVE}
			pos := FindPosition(x);
			IF compare(x, list[pos]) = 0 THEN
				RETURN list[pos];
			ELSE
				RETURN NIL;
			END;
		END SearchByKey;

	END SortedList;

END TFClasses.

System.Free TFClasses ~
S.Free TFClasses~
