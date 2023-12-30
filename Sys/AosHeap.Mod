(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE AosHeap; (** AUTHOR "pjm/Luc Bläser"; PURPOSE "Heap management and garbage collector"; *)

(* This module contains lots of low-level memory manipulations, which are best read together with the memory management data structure documentation. *)

(* 
	Garbage collector using a marking stack with overflow handling, 
	References:
		Jones, Lins, Garbage Collection, Section 4.2, Algorithm 4.1
		Knuth, The Art of Computer Programming, Volume 1, Section 2.3.5, Algorithm C
  *)

IMPORT SYSTEM, AosBoot, AosLocks, AosOut, AosMemory;

CONST
	DebugValue = 0DEADDEADH;	(* set non-0 to clear free storage to this value *)
	Trace = TRUE;	(* include trace code *)
	Stats* = TRUE;	(* maintain statistical counters *)
	
	HeapMin = 50;	(* "minimum" heap size as percentage of total memory size *)
	HeapMax = 95;	(* maximum heap size as percentage of total memory size *)
	ExpandRate = 1;	(* always extend heap with at least this percentage of total memory size *)
	Threshold = 10;	(* periodic GC initiated when this percentage of total memory size bytes has "passed through" NewBlock *)
	
	MaxTries = 16;	(* max number of times to try and allocate memory, before trapping *)
	InitialHeapIncrement = 4096;
	
	BlockSize* = 32;	(* power of two, <= 32 for RegisterCandidates *)
	
	FreeLists = 9;
	MaxCandidates = 1024;
	
	MarkStackSize = 1024; (* maximum stack size for temporary marking *)
	
	MarkBit = 0;  ArrayBit = 1;  FreeBit = 2;	(* in tag *)
	SubObjBit = 3;	(* in tag or ptr => indirect tag present *)
	ProtObjBit* = 4;	(* in ptr => direct tag and ProtOfs sized header present *)
	ProtOfs* = BlockSize+16;	(* protected object offset (32n+16) (MOD 8=0, ~SubObjBit IN ProtOfs, MOD 32#0) *)
	
	ProtTypeBit* = 31;	(** flags in TypeDesc, RoundUp(log2(MaxTags)) low bits reserved for extLevel *)
	
	ModOfs* = 16;	(* moduleAdr offset in TypeDesc *)
	TypeNameOfs = 20;	(* type name offset in TypeDesc *)
	ModNameOfs = 8;	(* module name offset in ModuleDesc *)
	
	FlagBits* = {MarkBit, ArrayBit, FreeBit, SubObjBit, ProtObjBit};

	MinPtrOfs = -40000000H;	(* sentinel offset for ptrOfs *)
	
	NilVal* = 0;
	
TYPE
	PtrElemRec = RECORD	(* has same type descriptor as element of ARRAY OF POINTER *)
		placeholder: PTR	(* field not used directly, but must be declared as pointer *)
	END;

	RootObject* = OBJECT	(* ref. AosLinker0 *)
		VAR placeholder: LONGINT;	(* for linking root objects during GC (used implicitly in Mark) *)
		PROCEDURE FindRoots*;	(** abstract *)
		BEGIN HALT(301) END FindRoots;
	END RootObject;
	
	Finalizer* = PROCEDURE {DELEGATE} (obj: PTR);
	
	FinalizerNode* = POINTER TO RECORD
		objWeak* [UNTRACED]: PTR;	(* weak reference to checked object *)
		markAdr: LONGINT;	(* address of type tag of object *)
		nextFin: FinalizerNode;	(* in finalization list *)
		objStrong*: PTR;	(* strong reference to object to be finalized *)
		finalizer*: Finalizer	(* finalizer, if any *)
	END;

VAR
	GC*: PROCEDURE;	(** activate the garbage collector *)
	beginAdr, endAdr: LONGINT;	(* page boundaries of heap *)
	beginBlockAdr-, endBlockAdr-: LONGINT;	(** block boundaries of heap, exported for AosInfo. *)
	initBlock: PTR;	(* anchor for init calls *)
	freeList: ARRAY FreeLists+1 OF LONGINT;	(* array of freelists *)
	lastFreeListAdr: LONGINT;
	markStack: ARRAY MarkStackSize OF LONGINT; (* temporary marking stack *)
	lowestForgotten: LONGINT; (* lowest forgotten block due to mark stack overflow *)
	markStackHeight: LONGINT; (* current free position in mark stack *) 
	candidates: ARRAY MaxCandidates OF LONGINT;	(* procedure stack pointer candidates *)
	numCandidates: LONGINT;
	rootList: LONGINT;	(* list of root objects during GC *)
	newSum, gcThreshold, expandMin, heapMinKB, heapMaxKB: LONGINT;
	checkRoot: FinalizerNode;	(* list of checked objects (contains weak references to the checked objects) *)
	finalizeRoot: FinalizerNode;	(* objects scheduled for finalization (contains references to scheduled objects) *)
	traceHeap*: SET;	(* exported for testing *)

	(** Statistics. Will only be maintained if Stats = TRUE *)

	(** Memory allocation statistics *)
	Nnew- : LONGINT;			(** Number of times NewBlock has been called since system startup *)
	NnewBytes- : HUGEINT;		(** Number of bytes allocated by NewBlock since system startup *)
	
	(** Garbage collection statistics *)
	Ngc- : LONGINT; 			(** Number of GC cycles since system startup *)
	
	(** Statistics considering the last GC cyle *)
	Nmark-, Nmarked-, Nsweeped-, NfinalizeAlive-, NfinalizeDead-: LONGINT;
	NgcCyclesMark-, NgcCyclesSweep-, NgcCyclesLastRun-, NgcCyclesMax-, NgcCyclesAllRuns- : HUGEINT;

(* ug *) (*  allCandidates : ARRAY 5000 OF LONGINT; *)
(* ug *) (* noCandidates : LONGINT; *)

PROCEDURE MarkInitialBlock(p: PTR);
VAR block, pTagAdr, tag, pTDescAdr, tdIndirectTag, tdEffectiveTag, ptrOfs: LONGINT;
BEGIN
	block := SYSTEM.VAL(LONGINT, p);
	IF (block < beginBlockAdr) OR (block >= endBlockAdr) THEN RETURN (* temporary (buffers?) *) END;
	
	(* -- compute tag adress -- *)
	IF ~(SubObjBit IN SYSTEM.VAL(SET, block)) THEN
		IF ~(ProtObjBit IN SYSTEM.VAL(SET, block)) THEN (* RecBlk, ArrBlk *)
			pTagAdr := block-4
		ELSE (* ProtRecBlk *)
			pTagAdr := block-(ProtOfs+4)
		END
	ELSE (* SysBlk, SysBlkArray, TypeDesc *)
		SYSTEM.GET(block-4, pTagAdr); (* indirect tag *)
		ASSERT(SYSTEM.VAL(SET, pTagAdr) * {MarkBit} = {}); (* mark bit must not be set *)
		pTagAdr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, pTagAdr) - {ArrayBit}) - 4 
			(* remove array bit because of array SysBlks in module block *)
	END;
	
	(* -- set mark for block -- *)
	SYSTEM.GET(pTagAdr, tag);
	IF ~(MarkBit IN SYSTEM.VAL(SET, tag)) THEN
		SYSTEM.PUT(pTagAdr, SYSTEM.VAL(SET, tag) + {MarkBit}); (* mark block *)
	
		IF ~(SubObjBit IN SYSTEM.VAL(SET, block)) THEN (* RecBlk, ArrBlk, ProtRecBlk have a type descriptor *)
			(* -- get address of type descriptor -- *)
			SYSTEM.GET(block-4, pTDescAdr);
			pTDescAdr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, pTDescAdr) - {MarkBit, ArrayBit}); 
				(* mask out mark and array bit *)
	
			(* -- set mark for type descriptor of block -- *)
			SYSTEM.GET(pTDescAdr-4, tdIndirectTag);
			tdIndirectTag := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tdIndirectTag) - {MarkBit}) - 4;
				(* mask out MarkBit because block may be a TypeDesc start pointer *)
			ASSERT(SYSTEM.VAL(SET, tdIndirectTag) * {ArrayBit} = {}); (* array bit must not be set *)
			SYSTEM.GET(tdIndirectTag, tdEffectiveTag);
			SYSTEM.PUT(tdIndirectTag, SYSTEM.VAL(SET, tdEffectiveTag) + {MarkBit}); (* mark type desc *)
			IF (SubObjBit IN SYSTEM.VAL(SET, pTDescAdr)) & 
					(SYSTEM.GET32(pTDescAdr-8) = SYSTEM.TYPECODE(RootObject)) THEN (* root object detected *)
				SYSTEM.PUT(block, rootList); rootList := block (* link root list *)
			END;
		
			ASSERT(markStackHeight = 0);
			(* -- determine whether block is not atomic, i.e. has outgoing references -- *)
			SYSTEM.GET(pTDescAdr+4, ptrOfs);
			IF ~(ptrOfs < MinPtrOfs) THEN (* not atomic *)
				(* -- Push block on mark stack -- *)
				IF markStackHeight # MarkStackSize THEN 
					markStack[markStackHeight] := block; INC(markStackHeight)
				ELSE (* overflow *)
					(* lowestForgotten points to the beginning of the block *)
					IF pTagAdr < lowestForgotten THEN lowestForgotten := pTagAdr END 
					(* remember lowest forgotten block for later rescan *)
				END
			END
		END
	END
END MarkInitialBlock;

(** Mark - Mark an object and its decendents.  Used by findRoots. *)
(* Mark is best read together with the heap data structures diagram. *)
PROCEDURE Mark*(p: PTR);
VAR orgBlock, orgPTagAdr, orgTag, orgPTDescAdr, orgTdIndirectTag, orgTdEffectiveTag, orgPtrOfs: LONGINT;
		currentPtrOfsPos: LONGINT; isArrayBlock: BOOLEAN; currentArrayElemAdr, lastArrayElemAdr, arrayElemSize: LONGINT;
		refBlock, refPTagAdr, refTag, refPTDescAdr, refTdIndirectTag, refTdEffectiveTag, refPtrOfs: LONGINT;
BEGIN
	IF Stats THEN INC(Nmark) END;
	markStackHeight := 0; (* clear mark stack *)
	lowestForgotten := endBlockAdr; (* sentinel: no overflow has happened *)
	MarkInitialBlock(p);
	LOOP
		WHILE markStackHeight # 0 DO
			DEC(markStackHeight); orgBlock := markStack[markStackHeight]; (* pop marked block *)
			ASSERT(~(SubObjBit IN SYSTEM.VAL(SET, orgBlock))); (* must be RecBlk, ArrBlk or ProtRecBlk *)
			SYSTEM.GET(orgBlock-4, orgPTDescAdr);
			isArrayBlock := ArrayBit IN SYSTEM.VAL(SET, orgPTDescAdr);
			orgPTDescAdr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, orgPTDescAdr) - {MarkBit, ArrayBit});
			SYSTEM.GET(orgPTDescAdr+4, orgPtrOfs); currentPtrOfsPos := 0;
			ASSERT(~(orgPtrOfs < MinPtrOfs)); (* must not be atomic *)
			IF isArrayBlock THEN
				SYSTEM.GET(orgBlock+8, currentArrayElemAdr); (* currentArrayElemAdr becomes firstArrayElemAdr *)
				SYSTEM.GET(orgBlock, lastArrayElemAdr);
				SYSTEM.GET(orgPTDescAdr, arrayElemSize);
				IF currentArrayElemAdr > lastArrayElemAdr THEN HALT(100) (* array must not be empty *) END
			END;
			
			(* -- visit all outgoing references -- *)
			REPEAT
				IF isArrayBlock THEN SYSTEM.GET(currentArrayElemAdr + orgPtrOfs, refBlock)
				ELSE SYSTEM.GET(orgBlock + orgPtrOfs, refBlock)
				END;
								
				(* -- inspect referenced block -- *)
				IF refBlock # NilVal THEN
					IF (refBlock >= beginBlockAdr) & (refBlock < endBlockAdr) THEN
						(* -- compute tag adress -- *)
						IF ~(SubObjBit IN SYSTEM.VAL(SET, refBlock)) THEN
							IF ~(ProtObjBit IN SYSTEM.VAL(SET, refBlock)) THEN (* RecBlk, ArrBlk *)
								refPTagAdr := refBlock-4
							ELSE (* ProtRecBlk *)
								refPTagAdr := refBlock-(ProtOfs+4)
							END
						ELSE (* SysBlk, SysBlkArray, TypeDesc *)
							SYSTEM.GET(refBlock-4, refPTagAdr); (* indirect tag *)
							ASSERT(SYSTEM.VAL(SET, refPTagAdr) * {MarkBit} = {}); (* mark bit must not be set *)
							refPTagAdr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, refPTagAdr) - {ArrayBit}) - 4; 
								(* remove array bit because of array SysBlks in module block *)
							ASSERT(SYSTEM.VAL(SET, SYSTEM.GET32(refPTagAdr)) - {MarkBit} = SYSTEM.VAL(SET, refPTagAdr+4))
						END;
						SYSTEM.GET(refPTagAdr, refTag);
						
						IF ~(MarkBit IN SYSTEM.VAL(SET, refTag)) THEN (* referenced block is not yet marked *)
							(* -- set mark for referenced block -- *)
							SYSTEM.PUT(refPTagAdr, SYSTEM.VAL(SET, refTag) + {MarkBit});
							IF ~(SubObjBit IN SYSTEM.VAL(SET, refBlock)) THEN (* RecBlk, ArrBlk, ProtRecBlk have a type descriptor *)
								(* -- get address of type descriptor for referenced block -- *)
								SYSTEM.GET(refBlock-4, refPTDescAdr);
								refPTDescAdr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, refPTDescAdr) - {MarkBit, ArrayBit}); 
		
								(* -- set mark for type descriptor of referenced block -- *)
								SYSTEM.GET(refPTDescAdr-4, refTdIndirectTag);
								refTdIndirectTag := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, refTdIndirectTag) - {MarkBit}) - 4;
									(* mask out MarkBit because block may be a TypeDesc start pointer *)
								ASSERT(SYSTEM.VAL(SET, refTdIndirectTag) * {ArrayBit} = {}); (* array bit must not be set *)
								SYSTEM.GET(refTdIndirectTag, refTdEffectiveTag);
								SYSTEM.PUT(refTdIndirectTag, SYSTEM.VAL(SET, refTdEffectiveTag) + {MarkBit}); (* mark type desc *)
								IF (SubObjBit IN SYSTEM.VAL(SET, refPTDescAdr)) & 
										(SYSTEM.GET32(refPTDescAdr-8) = SYSTEM.TYPECODE(RootObject)) THEN (* root object detected *)
									SYSTEM.PUT(refBlock, rootList); rootList := refBlock (* link root list *)
								END;
													
								(* -- determine whether referenced block is not atomic, i.e. has outgoing references -- *)
								SYSTEM.GET(refPTDescAdr+4, refPtrOfs);
								IF ~(refPtrOfs < MinPtrOfs) THEN (* not atomic *)
									(* -- Push block on mark stack -- *)
									IF markStackHeight # MarkStackSize THEN 
										markStack[markStackHeight] := refBlock; INC(markStackHeight)
									ELSE (* overflow *)
										(* lowestForgotten points to the beginning of the block *)
										IF refPTagAdr < lowestForgotten THEN lowestForgotten := refPTagAdr END 
											(* remember lowest forgotten block for later rescan *)
									END
								END
							END
						END
					END
				END;

				(* -- advance to next pointer -- *)
				INC(currentPtrOfsPos, 4);
				SYSTEM.GET(orgPTDescAdr + 4 + currentPtrOfsPos, orgPtrOfs);
				IF isArrayBlock & (orgPtrOfs < MinPtrOfs) & (currentArrayElemAdr # lastArrayElemAdr) THEN 
					(* advance to next array element *)
					INC(currentArrayElemAdr, arrayElemSize);
					SYSTEM.GET(orgPTDescAdr+4, orgPtrOfs); currentPtrOfsPos := 0;
					ASSERT(~(orgPtrOfs < MinPtrOfs)); (* must not be atomic *)
				END
			UNTIL (orgPtrOfs < MinPtrOfs)
		END;
		(* mark stack is empty *)
		IF lowestForgotten = endBlockAdr THEN EXIT END;
		FindForgottenBlock;
		(* must continue *)
		IF Trace & (12 IN traceHeap) THEN
			AosOut.Enter;
			AosOut.String("Overflow handling lowestForgotten="); AosOut.Int(lowestForgotten, 0); 
			AosOut.String (" endBlockAdr="); AosOut.Int(endBlockAdr, 0); AosOut.Ln;
			AosOut.Exit
		END		
	END;
	ASSERT(markStackHeight = 0)
END Mark;
				
(* Only used for handling overflows of the marking stack *)
PROCEDURE FindForgottenBlock;
VAR block, size, pTagAdr, tag, pTDescAdr, ptrOfs, lastArrayElemAdr, tmp, arrayElemSize, currentArrayElemAdr, 
	refBlock, currentPtrOfsPos, refPTagAdr, refTag: LONGINT; isNormalBlock, isPtrArray, isMarkStackEntry: BOOLEAN;
BEGIN
	pTagAdr := SYSTEM.VAL(LONGINT, lowestForgotten);
	ASSERT(pTagAdr MOD BlockSize = BlockSize-4);
	WHILE pTagAdr # endBlockAdr DO
		ASSERT(pTagAdr MOD BlockSize = BlockSize-4);
		SYSTEM.GET(pTagAdr, tag);
		SYSTEM.GET(tag - tag MOD 8, size); (* record size, excluding tag *)
		IF ArrayBit IN SYSTEM.VAL(SET, tag) THEN
			SYSTEM.GET(pTagAdr+4, lastArrayElemAdr); 
			arrayElemSize := size;
			size := lastArrayElemAdr + size - pTagAdr; (* size of array including tag *)
			isPtrArray := TRUE;
		ELSE
			INC(size, 4); (* include tag *)
			isPtrArray := FALSE
		END;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));	(* round up *)
		ASSERT(size MOD BlockSize = 0);
		
		isNormalBlock := FALSE;
		IF tag - tag MOD 8 = pTagAdr+4 THEN (* SysBlk, FreeBlk, TypeDesc, ProtRecBlk *)
			IF ~(FreeBit IN SYSTEM.VAL(SET, tag)) THEN
				SYSTEM.GET(pTagAdr + (4+20), tmp); (* tag or awaitingCond.head *)
				IF tmp # pTagAdr+4 THEN (* ProtRecBlk or TypeDesc *)
					SYSTEM.GET(pTagAdr+12, tmp); (* self address of typedesc or lockCount *)
					IF (tmp > pTagAdr + 24) & (tmp < pTagAdr + size) & (tmp MOD 16 = 8) THEN
						(* potential indirect address *)
						SYSTEM.GET(tmp-4, tmp); 
						IF tmp - tmp MOD 8 # pTagAdr+4 THEN (* ProtRecBlk *)
							isNormalBlock := TRUE; block := pTagAdr + (4 + ProtOfs)
						END
					ELSE
						isNormalBlock := TRUE; block := pTagAdr + (4 + ProtOfs)
					END
				END
			END
		ELSE
			isNormalBlock := TRUE; block := pTagAdr + 4
		END;
				
		(* -- look for non atomic and already marked block pointing to not yet marked blocks -- *)
		isMarkStackEntry := FALSE;
		IF isNormalBlock THEN (* RecBlk, ArrBlk, ProtRecBlk and block is defined *)
			IF MarkBit IN SYSTEM.VAL(SET, tag) THEN (* marked *)
				SYSTEM.GET(block-4, pTDescAdr);
				pTDescAdr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, pTDescAdr) - {MarkBit, ArrayBit});
				
				SYSTEM.GET(pTDescAdr+4, ptrOfs); currentPtrOfsPos := 0;
				IF ~(ptrOfs < MinPtrOfs) THEN (* not atomic *)
					IF isPtrArray THEN 
						SYSTEM.GET(block + 8, currentArrayElemAdr); (* firstElem *)
					END;
					REPEAT
						IF isPtrArray THEN SYSTEM.GET(currentArrayElemAdr + ptrOfs, refBlock)
						ELSE SYSTEM.GET(block + ptrOfs, refBlock)
						END;
						
						IF refBlock # NilVal THEN
							IF (refBlock >= beginBlockAdr) & (refBlock < endBlockAdr) THEN
								(* compute tag address *)
								IF ~(SubObjBit IN SYSTEM.VAL(SET, refBlock)) THEN
									IF ~(ProtObjBit IN SYSTEM.VAL(SET, refBlock)) THEN (* RecBlk, ArrBlk *)
										refPTagAdr := refBlock-4
									ELSE (* ProtRecBlk *)
										refPTagAdr := refBlock-(ProtOfs+4)
									END
								ELSE (* SysBlk, SysBlkArray, TypeDesc *)
									SYSTEM.GET(refBlock-4, refPTagAdr); (* indirect tag *)
									ASSERT(SYSTEM.VAL(SET, refPTagAdr) * {MarkBit} = {}); (* mark bit must not be set *)
									refPTagAdr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, refPTagAdr) - {ArrayBit}) - 4; 
										(* remove array bit because of array SysBlks in module block *)
									ASSERT(SYSTEM.VAL(SET, SYSTEM.GET32(refPTagAdr)) - {MarkBit} = SYSTEM.VAL(SET, refPTagAdr+4))
								END;
								SYSTEM.GET(refPTagAdr, refTag);
								IF ~(MarkBit IN SYSTEM.VAL(SET, refTag)) THEN (* referenced block is not marked *)
									isMarkStackEntry := TRUE
								END
							END
						END;
						
						(* advance to next pointer *)
						INC(currentPtrOfsPos, 4);
						SYSTEM.GET(pTDescAdr + 4 + currentPtrOfsPos, ptrOfs);
						IF isPtrArray & (ptrOfs < MinPtrOfs) & (currentArrayElemAdr # lastArrayElemAdr) THEN
							(* advance to next array element *)
							INC(currentArrayElemAdr, arrayElemSize);
							SYSTEM.GET(pTDescAdr + 4, ptrOfs); currentPtrOfsPos := 0;
							ASSERT(~(ptrOfs < MinPtrOfs)); (* must not be atomic *)
						END
					UNTIL isMarkStackEntry OR (ptrOfs < MinPtrOfs)
				END;
				
				IF isMarkStackEntry THEN
					(* forgotten block *)
					IF markStackHeight # MarkStackSize THEN
						markStack[markStackHeight] := block; INC(markStackHeight)
					ELSE (* overflow *)
						RETURN (* ! continue with mark process, lowestForgotten = pTagAdr < endBlockAdr *)
					END
				END
			END
		END;
		
		(* advance to next block *)
		INC(pTagAdr, size); lowestForgotten := pTagAdr
	END
	(* lowestForgotten = endBlockAdr *)
END FindForgottenBlock;

(** WriteType - Write a type name (for tracing only). *)

PROCEDURE WriteType*(t: LONGINT);	(* t is tdesc *)
VAR m, i: LONGINT;  ch: CHAR;  name: ARRAY 32 OF CHAR;
BEGIN
	SYSTEM.GET(t-4, t);
	SYSTEM.GET(t+ModOfs, m);	(* m is only a hint *)
	IF m # 0 THEN	(* could be a type without module, e.g. a Java class *)
		i := 0;  SYSTEM.GET(m+ModNameOfs+i, ch);
		WHILE (ch >= "0") & (ch <= "z") & (i # 32) DO
			AosOut.Char(ch);
			INC(i);  SYSTEM.GET(m+ModNameOfs+i, ch)
		END
	ELSE
		AosOut.String("NIL")
	END;
	AosOut.Char(".");
	SYSTEM.MOVE(t+TypeNameOfs, SYSTEM.ADR(name[0]), 32);
	IF name[0] = 0X THEN AosOut.String("-")
	ELSE AosOut.String(name)
	END
END WriteType;

(* Sweep phase. *)

PROCEDURE Sweep;
VAR p, tag, size, t, i, lastP, lastSize, live, dead: LONGINT;  lastA: ARRAY FreeLists+1 OF LONGINT;
BEGIN
	i := 0;
	WHILE i <= FreeLists DO
		freeList[i] := NilVal;  lastA[i] := SYSTEM.ADR(freeList[i]);  INC(i)
	END;
	p := beginBlockAdr;  lastSize := 0;  live := 0;  dead := 0;
	WHILE p # endBlockAdr DO
		SYSTEM.GET(p, tag);
		SYSTEM.GET(tag - tag MOD 8, size);	(* record size, excluding tag *)
		IF ArrayBit IN SYSTEM.VAL(SET, tag) THEN
			SYSTEM.GET(p+4, t);	(* lastElemToMark *)
			size := t + size - p	(* size of array, including tag *)
		ELSE
			INC(size, 4)	(* include tag *)
		END;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));	(* round up *)
		IF MarkBit IN SYSTEM.VAL(SET, tag) THEN	(* don't collect *)
			IF Stats THEN INC(Nmarked) END;
			SYSTEM.PUT(p, SYSTEM.VAL(SET, tag) - {MarkBit});	(* unmark *)
			IF lastSize > 0 THEN	(* enter last free block in free list *)
				i := lastSize DIV BlockSize;
				IF i > FreeLists THEN i := FreeLists END;
					(* freeblk *)
				SYSTEM.PUT(lastP, lastP + (4 + ASH(1, FreeBit)));	(* tag *)
				SYSTEM.PUT(lastP+4, lastSize-4);	(* size *)
				SYSTEM.PUT(lastP+8, NIL);	(* next *)
				SYSTEM.PUT(lastA[i], lastP);
				lastA[i] := lastP+8;	(* ADR(next) *)
				lastSize := 0
			END;
			INC(live)
		ELSE	(* collect *)
			IF Stats THEN INC(Nsweeped) END;
				(* append to free block *)
			IF lastSize = 0 THEN lastP := p END;
			INC(lastSize, size);
				(* tracing *)
			IF Trace & (traceHeap * {3..5, 8..9, 11} # {}) THEN
				INC(dead);
				IF ArrayBit IN SYSTEM.VAL(SET, tag) THEN	(* array *)
					IF 4 IN traceHeap THEN
						AosOut.String("[DA");  AosOut.Hex(p+4, 9);
						SYSTEM.GET(p+16, t);	(* dim0 *)
						AosOut.Char(" ");  AosOut.Int(t, 1);  AosOut.Char(" ");
						WriteType(tag - tag MOD 8);  AosOut.Char("]")
					END
				ELSIF tag - tag MOD 8 = p+4 THEN	(* sysblk or freeblk or protblk *)
					IF FreeBit IN SYSTEM.VAL(SET, tag) THEN	(* freeblk *)
						IF 8 IN traceHeap THEN
							AosOut.String("[FB");  AosOut.Hex(p+4, 9);
							SYSTEM.GET(p+4, t);	(* size *)
							AosOut.Char(" ");  AosOut.Int(t, 1);  AosOut.Char("]")
						END
					ELSE	(* sysblk or protblk *)
						SYSTEM.GET(p+(4+20), t);	(* tag or awaitingCond.head *)
						IF t = p+4 THEN	(* sysblk *)
							IF 5 IN traceHeap THEN
								SYSTEM.GET(p+4, t);	(* size *)
								AosOut.String("[DS");  AosOut.Hex(p+(4+24), 9);  AosOut.Char(" ");  AosOut.Int(t, 1);  AosOut.Char("]")
							END
						ELSE	(* protblk *)
							IF 9 IN traceHeap THEN
								SYSTEM.GET(p+(4+44), t);	(* tag *)
								AosOut.String("[DP");  AosOut.Hex(p+(4+ProtOfs), 9);  AosOut.Char(" ");  WriteType(t);  AosOut.Char("]")
							END
						END
					END
				ELSE	(* recblk *)
					IF 3 IN traceHeap THEN
						AosOut.String("[DR");  AosOut.Hex(p+4, 9);  AosOut.Char(" ");  WriteType(tag);  AosOut.Char("]")
					END
				END
			END
		END;
		INC(p, size)
	END;
	IF lastSize > 0 THEN	(* enter last free block in free list *)
		i := lastSize DIV BlockSize;
		IF i > FreeLists THEN i := FreeLists END;
			(* freeblk *)
		SYSTEM.PUT(lastP, lastP + (4 + ASH(1, FreeBit)));	(* tag *)
		SYSTEM.PUT(lastP+4, lastSize-4);	(* size *)
		SYSTEM.PUT(lastP+8, NIL);	(* next *)
		SYSTEM.PUT(lastA[i], lastP)
	END;
	IF Trace & (11 IN traceHeap) THEN
		AosOut.String("[");  AosOut.Int(live, 1);  AosOut.String(" live, ");
		AosOut.Int(dead, 1);  AosOut.String(" dead, ");
		AosOut.Int(live+dead, 1);  AosOut.String(" total]")
	END
END Sweep;

(* Clear free blocks for debugging purposes. *)

PROCEDURE DebugClear;
VAR i, size, ptr: LONGINT;
BEGIN
	IF DebugValue # 0 THEN
		i := 0;
		WHILE i <= FreeLists DO
			ptr := freeList[i];
			WHILE ptr # NilVal DO
				IF SYSTEM.GET32(ptr+12) # DebugValue THEN
					SYSTEM.GET(ptr+4, size);	(* size of free block, excluding tag *)
					AosBoot.Fill32(ptr+12, size-8, DebugValue)	(* content of free block *)
				ELSE
					(* assume block is already cleared, to save time *)
				END;
				SYSTEM.GET(ptr+8, ptr)	(* next *)
			END;
			INC(i)
		END
	END
END DebugClear;

(* CheckCandidates - Check which candidates could be pointers, and mark them. *)

PROCEDURE CheckCandidates;
VAR i, j, h, p, block, t, size: LONGINT;
BEGIN	(* {numCandidates > 0} *)
		(* first sort them in increasing order using shellsort *)
	h := 1;  REPEAT h := h*3 + 1 UNTIL h > numCandidates;
	REPEAT
		h := h DIV 3;  i := h;
		WHILE i < numCandidates DO
			p := candidates[i];  j := i;
			WHILE (j >= h) & (candidates[j-h] > p) DO
				candidates[j] := candidates[j-h];  j := j-h;
			END;
			candidates[j] := p;  INC(i)
		END
	UNTIL h = 1;
		(* sweep phase *)
	block := beginBlockAdr;  i := 0;
	p := candidates[i];	(* p is candidate, with lower 2 bits signalling candidate type *)
	LOOP
		IF p <= block + (4 + 3) THEN	(* next candidate *)
			IF p - p MOD 4 = block + 4 THEN	(* candidate passed *)
				CASE p MOD 4 OF
					0:	(* type 0 - RecBlk *)
						Mark(SYSTEM.VAL(PTR, p))
					|2:	(* type 2 - ProtRecBlk *)
						Mark(SYSTEM.VAL(PTR, p + (ProtOfs - 2)))
					|3:	(* type 3 - SysBlk *)
						Mark(SYSTEM.VAL(PTR, p + (24-3)))
				END
			ELSE (* candidate failed, skip *)
			END;
			INC(i);
			IF i = numCandidates THEN EXIT END;
			p := candidates[i]
		ELSE	(* next block *)
			SYSTEM.GET(block, t);	(* tag *)
			SYSTEM.GET(t - t MOD 8, size);	(* record size, excluding tag *)
			IF ArrayBit IN SYSTEM.VAL(SET, t) THEN
				SYSTEM.GET(block+4, t);	(* lastElemToMark *)
				size := t + size - block	(* size of array, including tag *)
			ELSE
				INC(size, 4)	(* include tag *)
			END;
				(* round up, and step to next block  *)
			INC(block, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1)));
			IF block = endBlockAdr THEN EXIT END
		END
	END;
	numCandidates := 0
END CheckCandidates;


(** RegisterCandidates - Register a block of pointer candidates.  {(adr,size) MOD 4 = 0} *)

PROCEDURE RegisterCandidates*(adr, size: LONGINT);
VAR end, p, tag, tag0: LONGINT; s: SET;
BEGIN
	(* current processor must hold AosHeap lock *)
	end := adr + size;
	WHILE adr # end DO
		SYSTEM.GET(adr, p);
		IF (p > beginBlockAdr) & (p < endBlockAdr) THEN
			CASE p MOD BlockSize OF
				0:	(* RecBlk or ArrBlk candidate *)
					SYSTEM.GET(p-4, s);
					IF s * {MarkBit, FreeBit, SubObjBit} = {SubObjBit} THEN
						candidates[numCandidates] := p;	(* 00000 - type 0 *)
						INC(numCandidates);
						IF numCandidates = LEN(candidates) THEN CheckCandidates END
					END
				|16:	(* ProtRecBlk candidate *)
					SYSTEM.GET(p-4, s);
					IF s * {MarkBit, ArrayBit, FreeBit, SubObjBit} = {SubObjBit} THEN
						SYSTEM.GET(p-(ProtOfs+4), tag);
						IF tag = p-ProtOfs THEN
							candidates[numCandidates] := p - ProtOfs + 2;	(* 00010 - type 2 *)
							INC(numCandidates);
							IF numCandidates = LEN(candidates) THEN CheckCandidates END
						END
					END
				|24:	(* SysBlk candidate *)
					SYSTEM.GET(p-4, tag);
					IF (tag MOD BlockSize = 0) & (tag > beginBlockAdr) & (tag < endBlockAdr) THEN
						SYSTEM.GET(tag-4, tag0);
						IF tag0 = tag THEN
							IF tag0+24 = p THEN
								candidates[numCandidates] := p - 24 + 3;	(* 00011 - type 3 *)
								INC(numCandidates);
								IF numCandidates = LEN(candidates) THEN CheckCandidates END
							END
						END
					END
				ELSE (* skip - all other live heap block types (SubObj, TypeDesc) must be rooted  *)
			END	(* CASE *)
		END;
		INC(adr, 4)
	END
END RegisterCandidates;

PROCEDURE CheckPointer*(p: LONGINT): BOOLEAN;
VAR ret: BOOLEAN; tag, tag0: LONGINT; s: SET;
BEGIN
	ret := FALSE;
	IF (p > beginBlockAdr) & (p < endBlockAdr) THEN
		CASE p MOD BlockSize OF
			0:	(* RecBlk or ArrBlk candidate *)
				SYSTEM.GET(p-4, s);
				IF (s * {MarkBit, FreeBit, SubObjBit} = {SubObjBit}) OR (s * {MarkBit, FreeBit, SubObjBit} = {MarkBit, SubObjBit}) THEN
					ret := TRUE	
				END
		   |16:	(* ProtRecBlk candidate *)
				SYSTEM.GET(p-4, s);
				IF (s * {MarkBit, ArrayBit, FreeBit, SubObjBit} = {SubObjBit}) THEN
					SYSTEM.GET(p-(ProtOfs+4), tag);
					s := SYSTEM.VAL(SET, tag);
					IF MarkBit IN s THEN EXCL(s, MarkBit); tag := SYSTEM.VAL(LONGINT, s) END;
					IF tag = p-ProtOfs THEN
						ret := TRUE
					END
				END
		   |24:	(* SysBlk candidate *)
				SYSTEM.GET(p-4, tag);
				IF (tag MOD BlockSize = 0) & (tag > beginBlockAdr) & (tag < endBlockAdr) THEN
					SYSTEM.GET(tag-4, tag0);
					s := SYSTEM.VAL(SET, tag0);
					IF MarkBit IN s THEN EXCL(s, MarkBit); tag0:= SYSTEM.VAL(LONGINT, s) END;
					IF tag0 = tag THEN
						IF tag0+24 = p THEN
							ret := TRUE
						END
					END
				END
		ELSE (* skip - all other live heap block types (SubObj, TypeDesc) must be rooted  *)
		END	(* CASE *)		
	END;
	RETURN ret
END CheckPointer;

(* Check reachability of finalized objects. *)

PROCEDURE CheckFinalizedObjects;
VAR n, p, t: FinalizerNode;
BEGIN
	n := checkRoot;
	WHILE n # NIL DO	(* move unmarked checked objects to finalize list *)
		IF ~(MarkBit IN SYSTEM.VAL(SET, SYSTEM.GET32(n.markAdr))) THEN
			IF n = checkRoot THEN checkRoot := n.nextFin ELSE p.nextFin := n.nextFin END;
			n.objStrong := n.objWeak;	(* anchor the object for finalization *)
			t := n.nextFin; n.nextFin := finalizeRoot; finalizeRoot := n; n := t;
			IF Stats THEN DEC(NfinalizeAlive); INC(NfinalizeDead) END
		ELSE
			p := n; n := n.nextFin
		END
	END;
		(* now trace the weak references to keep finalized objects alive during this collection *)
	n := finalizeRoot;
	WHILE n # NIL DO
		Mark(n.objStrong); n := n.nextFin
	END
END CheckFinalizedObjects;

(** Return the next scheduled finalizer or NIL if none available.  Called by finalizer object in AosKernel. *)

PROCEDURE GetFinalizer*(): FinalizerNode;
VAR n: FinalizerNode;
BEGIN
	n := NIL;
	IF finalizeRoot # NIL THEN
		AosLocks.Acquire(AosLocks.AosHeap);
		n := finalizeRoot;	(* take one finalizer *)
		IF n # NIL THEN
			finalizeRoot := n.nextFin; (* to do: n.nextFin := NIL *);
			IF Stats THEN DEC(NfinalizeDead) END;
			IF Trace & (10 IN traceHeap) THEN
				AosOut.Enter; AosOut.String("Finalize ");
				WriteType(SYSTEM.GET32(SYSTEM.VAL(LONGINT, n.objWeak)-4));
				AosOut.Hex(SYSTEM.VAL(LONGINT, n.objWeak), 9); AosOut.Exit
			END
		END;
		AosLocks.Release(AosLocks.AosHeap);
	END;
	RETURN n
END GetFinalizer;

(** Check finalizers registered in the specified module, which is about to be freed or shut down.  Remove all finalizer procedures in this module from the finalizer lists so they won't be called any more. *)

PROCEDURE CleanupModuleFinalizers*(codeAdr, codeLen: LONGINT; name: ARRAY OF CHAR);
VAR n, p, t: FinalizerNode; codeEnd: LONGINT; N1, N2: LONGINT;
BEGIN
	codeEnd := codeAdr + codeLen; N1 := 0; N2 := 0;
	AosLocks.Acquire(AosLocks.AosHeap);
	n := checkRoot;
	WHILE n # NIL DO	(* iterate over checked list *)
			(* to do: unsigned! *)
		t := n; n := n.nextFin;
		IF (codeAdr <= SYSTEM.VAL(LONGINT, t.finalizer)) & (SYSTEM.VAL(LONGINT, t.finalizer) <= codeEnd) THEN
			IF t = checkRoot THEN checkRoot := t.nextFin ELSE p.nextFin := t.nextFin END;	(* remove from list *)
			IF Stats THEN DEC(NfinalizeAlive) END;
			IF FALSE (* call *) THEN	(* finalize the object *)
				t.objStrong := t.objWeak;	(* anchor the object for finalization *)
				t.nextFin := finalizeRoot; finalizeRoot := t;
				IF Stats THEN INC(NfinalizeDead) END
			END;
			INC(N1)
		ELSE
			p := t
		END
	END;
	IF TRUE (* ~call*) THEN	(* also remove finalizers from list, so they won't be called *)
		n := finalizeRoot;
		WHILE n # NIL DO	(* iterate over finalized list *)
				(* to do: unsigned! *)
			t := n; n := n.nextFin;
			IF (codeAdr <= SYSTEM.VAL(LONGINT, t.finalizer)) & (SYSTEM.VAL(LONGINT, t.finalizer) <= codeEnd) THEN
				IF t = finalizeRoot THEN finalizeRoot := t.nextFin ELSE p.nextFin := t.nextFin END;	(* remove from list *)
				IF Stats THEN DEC(NfinalizeDead) END;
				INC(N2)
			ELSE
				p := t
			END
		END
	END;
	AosLocks.Release(AosLocks.AosHeap);
	IF (N1 # 0) OR (N2 # 0) THEN
		AosOut.Enter; AosOut.String(name); AosOut.Char(" ");
		AosOut.Int(N1, 1); AosOut.String(" discarded finalizers, ");
		AosOut.Int(N2, 1); AosOut.String(" pending finalizers"); AosOut.Exit
	END
END CleanupModuleFinalizers;

PROCEDURE ShowInt(i: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	IF Trace THEN
		AosOut.Char(" "); AosOut.String(msg); AosOut.Char("="); AosOut.Int(i, 1)
	END
END ShowInt;

PROCEDURE ShowTimeDiff(time1, time2: HUGEINT; msg: ARRAY OF CHAR);
BEGIN
	IF Trace THEN
		IF AosBoot.HIntToLInt(AosBoot.mhz) # 0 THEN
			time1 := AosBoot.DivH(AosBoot.SubH(time2, time1), AosBoot.mhz)
		ELSE
			time1 := AosBoot.SubH(time2, time1)
		END;
		ShowInt(AosBoot.HIntToLInt(time1), msg)
	END
END ShowTimeDiff;

PROCEDURE CollectGarbage*(root : PTR); 
VAR
	tagAdr, i: LONGINT; tag: SET; obj: RootObject;
	stack: ARRAY AosBoot.MaxCPU OF AosMemory.Stack;
	time1, time2, time3, time4, time5, time6: HUGEINT; first: BOOLEAN;
BEGIN
	AosLocks.Acquire(AosLocks.AosHeap);	(* protect from interrupts *)
	IF Stats OR Trace THEN 
		Nmark := 0; Nmarked := 0; Nsweeped := 0;
		INC(Ngc); 
		time1 := AosBoot.GetTimer();
	END;
	IF Trace & (traceHeap - {0,1,2,6} # {}) THEN
		AosOut.String("[P"); AosOut.Int(AosBoot.ID(), 1);
		AosOut.Char("@"); AosOut.Int(AosBoot.HIntToLInt(AosBoot.mhz), 1); AosOut.String("MHz ");
		AosOut.String(" GC");
	END;
	numCandidates := 0; rootList := NilVal;
	Mark(root);
	IF Stats OR Trace THEN time2 := AosBoot.GetTimer(); first := TRUE END;
		(* check kernel stacks *)	
	AosMemory.GetKernelStacks(stack);
	FOR i := 0 TO AosBoot.MaxCPU-1 DO
		RegisterCandidates(stack[i].adr, stack[i].high - stack[i].adr)
	END;
	REPEAT
		REPEAT
			IF rootList # NilVal THEN	(* check root objects *)
				REPEAT
						(* get head object *)
					obj := SYSTEM.VAL(RootObject, rootList);
					tagAdr := rootList-4;
					SYSTEM.GET(rootList, rootList);	(* link to next *)
						(* find roots in object *)
					SYSTEM.GET(tagAdr, tag);	(* save *)
					ASSERT(tag * {ArrayBit, FreeBit, SubObjBit} = {SubObjBit});	(* sanity check *)
					SYSTEM.PUT(tagAdr, tag - {MarkBit});	(* allow type guards & method calls (only as long as not marked again) *)
					obj.FindRoots;	(* will call Mark *)
					SYSTEM.PUT(tagAdr, tag)	(* restore *)
				UNTIL rootList = NilVal
			END;
			IF numCandidates # 0 THEN CheckCandidates END 
		UNTIL (numCandidates = 0) & (rootList = NilVal);
		IF Stats OR Trace  THEN
			IF first THEN first := FALSE; time3 := AosBoot.GetTimer() END	(* total time for finalized objects, with other roots *)
		END;
		CheckFinalizedObjects
	UNTIL rootList = NilVal;
	(*IF rootList # NilVal THEN
		SYSTEM.GET(rootList-4, tagAdr);
		AosOut.String("rootList # NIL "); WriteType(tagAdr); AosOut.Ln
	END;*)
	IF Stats OR Trace THEN time4 := AosBoot.GetTimer() END;
	Sweep;
	IF Stats OR Trace THEN time5 := AosBoot.GetTimer() END;
	IF DebugValue # 0 THEN DebugClear END;
	IF Stats OR Trace THEN time6 := AosBoot.GetTimer(); END;
	IF Trace & (traceHeap - {0,1,2,6} # {}) THEN
		ShowTimeDiff(time1, time6, "tot");
		ShowTimeDiff(time1, time2, "mod");
		ShowTimeDiff(time2, time3, "obj");
		ShowTimeDiff(time3, time4, "fin");
		ShowTimeDiff(time4, time5, "swp");
		ShowTimeDiff(time5, time6, "clr");
		IF Stats THEN
			ShowInt(Nmark, "rts");
			ShowInt(Nmarked, "rch");
			ShowInt(Nsweeped, "fre");
			ShowInt(NfinalizeAlive, "fina");
			ShowInt(NfinalizeDead, "find")
		END;
		IF traceHeap * {3..5, 8..9, 11} # {} THEN AosOut.String(" (with tracing)") END;
		AosOut.String(" CG]");  AosOut.Ln
	END;
	IF Stats THEN
		NgcCyclesLastRun := AosBoot.SubH(time6, time1);
		IF AosBoot.GreaterH(NgcCyclesLastRun, NgcCyclesMax) THEN NgcCyclesMax := NgcCyclesLastRun; END;
		NgcCyclesAllRuns := AosBoot.AddH(NgcCyclesAllRuns, NgcCyclesLastRun);
		NgcCyclesSweep := AosBoot.SubH(time5, time4);
		NgcCyclesMark := AosBoot.SubH(time4, time1);
	END;
	AosLocks.Release(AosLocks.AosHeap)
END CollectGarbage;

(* Try to expand the heap by at least "size" bytes. *)

PROCEDURE ExpandHeap(size: LONGINT);
VAR p: LONGINT; s: SET;
BEGIN
	IF size < expandMin THEN size := expandMin END;
	INC(endAdr, size);
	AosMemory.SetHeapEndAdr(endAdr);	(* in/out parameter *)
	IF endBlockAdr+4 # endAdr THEN	(* heap has grown, init free block *)
		p := endBlockAdr+4; s := SYSTEM.VAL(SET, p) + {FreeBit};
		endBlockAdr := endAdr-4;
		SYSTEM.PUT(p-4, s);	(* tag *)
		SYSTEM.PUT(p, endBlockAdr-p);	(* size *)
		SYSTEM.PUT(p+4, NIL)	(* next *)
	END
END ExpandHeap;

(* Policy decision for heap expansion.  NewBlock for the same block has failed try times. *)

PROCEDURE ExpandNow(try: LONGINT): BOOLEAN;
VAR size: LONGINT;
BEGIN
	size := SYSTEM.LSH(endAdr - beginAdr, -10);	(* heap size in KB *)
	RETURN (~ODD(try) OR (size < heapMinKB)) & (size < heapMaxKB)
END ExpandNow;

(* NewBlock - Allocate a heap block.  {(size MOD BlockSize = 0) & (ret MOD BlockSize = BlockSize-4)}.  Caller must hold Heap lock. *)

PROCEDURE NewBlock(size: LONGINT): LONGINT;
VAR idx, rest, free, ptr, restPtr, try: LONGINT;
BEGIN
	INC(newSum, size);
	IF newSum > gcThreshold THEN	(* call GC every so often to avoid fragmentation *)
		newSum := 0;
		AosLocks.Release(AosLocks.AosHeap);	(* give up control *)
		GC;	(* try to free memory (other processes may also steal memory now) *)
		AosLocks.Acquire(AosLocks.AosHeap)
	END;
	IF Stats THEN INC(Nnew); NnewBytes := AosBoot.AddH(NnewBytes, size); END;
	try := 1;
	LOOP
		idx := size DIV BlockSize;	(* idx negative if size negative *)
		IF idx > FreeLists THEN idx := FreeLists END;
		free := SYSTEM.ADR(freeList[idx])-4;	(* before start freelist *)
		REPEAT
			INC(free, 4); SYSTEM.GET(free, ptr)
		UNTIL (ptr # NilVal) OR (free = lastFreeListAdr);
		IF free = lastFreeListAdr THEN	(* search last list, which has variable-sized entries *)
			LOOP	(* find big enough block *)
				IF ptr = NilVal THEN EXIT END;	(* end of last list *)
				SYSTEM.GET(ptr + 4, rest);	(* free block size *)
				IF rest + 4 >= size THEN EXIT END;	(* block found *)
				free := ptr + 8;	(* prev link *)
				SYSTEM.GET(free, ptr)	(* next free block *)
			END
		END;
		IF ptr # NilVal THEN	(* found a block, remove and split it *)
			SYSTEM.GET(ptr + 8, rest);	(* next free block *)
			SYSTEM.PUT(free, rest);	(* update free list head or previous node in list *)
			SYSTEM.GET(ptr + 4, rest);	(* size *)
			rest := rest + 4 - size;	(* size of remainder *)
			IF rest > 0 THEN	(* add free block *)
				idx := rest DIV BlockSize;
				IF idx > FreeLists THEN idx := FreeLists END;
				restPtr := ptr + size;
				SYSTEM.PUT(restPtr, restPtr + (4 + ASH(1, FreeBit)));	(* tag *)
				SYSTEM.PUT(restPtr + 4, rest - 4);	(* size *)
				SYSTEM.PUT(restPtr + 8, freeList[idx]);	(* next *)
				freeList[idx] := restPtr
			END;
			RETURN ptr
		END;
			(* failed *)
		(*AosOut.String("NBT "); AosOut.Int(try, 1); AosOut.Char(" "); AosOut.Int(size, 1); AosOut.Ln;*)
		IF try = MaxTries THEN SYSTEM.HALT(14) END;	(* out of memory *)
		IF ExpandNow(try) THEN ExpandHeap(size) END;	(* try to extend the heap *)
		AosLocks.Release(AosLocks.AosHeap);	(* give up control *)
		GC;	(* try to free memory (other processes may also steal memory now) *)
		AosLocks.Acquire(AosLocks.AosHeap);
		INC(try)
	END
END NewBlock;

(** NewSys - Implementation of SYSTEM.NEW. *)

PROCEDURE NewSys*(VAR p: PTR;  size: LONGINT);
VAR ptr: LONGINT;
BEGIN
	IF Trace & (2 IN traceHeap) THEN
		AosOut.Enter;  AosOut.String("NS ");  AosOut.Int(size, 1);  AosOut.Exit
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
		(* add space for tag & fake type descriptor and round up to BlockSize *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (4 + 24 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	ptr := NewBlock(size);
	SYSTEM.PUT(ptr, ptr+4);	(* tag *)
	SYSTEM.PUT(ptr+4, size-4);
	SYSTEM.PUT(ptr+8, SYSTEM.VAL(LONGINT, MinPtrOfs-4));
	SYSTEM.PUT(ptr+12, NIL);	(* flag = 0 for AosInfo.Objects *)
	SYSTEM.PUT(ptr+16, NIL);	(* not used *)
	SYSTEM.PUT(ptr+20, {});	(* bit 1 must be 0 to distinguish from array SysBlk *)
	SYSTEM.PUT(ptr+24, ptr+4);	(* SysBlk tag *)
	p := SYSTEM.VAL(PTR, ptr+28);
	AosLocks.Release(AosLocks.AosHeap);
		(* clear can be done outside lock because SysBlks are not traced *)
	AosBoot.Fill32(SYSTEM.VAL(LONGINT, p), size-28, 0)	(* clear everything except header *)
END NewSys;

PROCEDURE -CallerEIP(): LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, 4[EBP]
END CallerEIP;

(** NewRec - Implementation of NEW with a record. *)

PROCEDURE NewRec*(VAR p: PTR;  tag: LONGINT);
VAR size, ptr: LONGINT;
BEGIN
	IF tag = 0 THEN
		tag := SYSTEM.TYPECODE(PtrElemRec);
			(* should not occur any more after compiler update 03.07.01, but old obj files... *)
		AosOut.String("NewRec tag=NIL"); AosOut.Hex(CallerEIP(), 9); AosOut.Ln
	END;
	SYSTEM.GET(tag-4, ptr);	(* will be replaced by direct compiler call of NewProtObj *)
	SYSTEM.GET(ptr+12, ptr);	(* flags *)
	IF ODD(ASH(ptr, -ProtTypeBit)) THEN	(* protected record *)
		NewProtRec(p, tag);
		RETURN
	END;
	SYSTEM.GET(tag, size);
		(* add space for tag and round up to BlockSize *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (4 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	IF Trace & (0 IN traceHeap) THEN
		AosOut.Enter;  AosOut.String("NR ");  WriteType(tag);  AosOut.Exit
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
	ptr := NewBlock(size);
	SYSTEM.PUT(ptr, tag);	(* set the block tag *)
	p := SYSTEM.VAL(PTR, ptr+4);	(* anchor the block *)
		(* clear must be done inside lock to ensure all traced pointer fields are initialized to NIL *)
	AosBoot.Fill32(SYSTEM.VAL(LONGINT, p), size-4, 0);	(* clear everything except tag *)
	AosLocks.Release(AosLocks.AosHeap)
END NewRec;

(** NewProtRec - Implementation of NEW with a protected record. *)

PROCEDURE NewProtRec*(VAR p: PTR;  tag: LONGINT);
VAR size, ptr: LONGINT;
BEGIN
	SYSTEM.GET(tag, size);
		(* add space for tag and header and round up to BlockSize *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (4 + ProtOfs + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	IF Trace & (0 IN traceHeap) THEN
		AosOut.Enter;  AosOut.String("NP ");  WriteType(tag);  AosOut.Exit
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
	ptr := NewBlock(size)+4;
	SYSTEM.PUT(ptr-4, ptr);	(* set the main tag *)
	SYSTEM.PUT(ptr, size-4);	(* size *)
	SYSTEM.PUT(ptr+4, SYSTEM.VAL(LONGINT, MinPtrOfs-4));
	AosBoot.Fill32(ptr+8, ProtOfs-12, 0);	(* clear header *)
	SYSTEM.PUT16(ptr+10, -1);	(* flag = -1 *)
	SYSTEM.PUT(ptr+(ProtOfs-4), tag);	(* set the tag *)
	p := SYSTEM.VAL(PTR, ptr+ProtOfs);
		(* clear must be done inside lock to ensure all traced pointer fields are initialized to NIL *)
	AosBoot.Fill32(SYSTEM.VAL(LONGINT, p), size-(4+ProtOfs), 0);	(* clear everything except tag & header *)
	AosLocks.Release(AosLocks.AosHeap)
END NewProtRec;

(** NewArr - Implementation of NEW with an array containing pointers. *)

PROCEDURE NewArr*(VAR p: PTR;  elemTag, numElems, numDims: LONGINT);
VAR ptr, size, firstElem, elemSize, arrSize, vectSize, ptrOfs: LONGINT;
BEGIN
	IF elemTag = 0 THEN
		elemTag := SYSTEM.TYPECODE(PtrElemRec);
			(* should not occur any more after compiler update 03.07.01, but old obj files... *)
		AosOut.String("NewArr tag=NIL"); AosOut.Hex(CallerEIP(), 9); AosOut.Ln
	END;
	SYSTEM.GET(elemTag, elemSize);
	arrSize := numElems * elemSize;
	IF arrSize = 0 THEN
		IF Trace & (1 IN traceHeap) THEN
			AosOut.Enter;  AosOut.String("NA ");  AosOut.Int(numElems, 1);  AosOut.Char(" ");
			AosOut.Int(numDims, 1);  AosOut.String("->");  AosOut.Exit
		END;
		NewSys(p, numDims * 4 + 12)
	ELSE
		ASSERT(arrSize >= 0);
		vectSize := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, 4 * numDims) + SYSTEM.VAL(SET, 4));	(* => firstElem MOD 8 = 0 *)
		SYSTEM.GET(elemTag+4, ptrOfs);
		IF ptrOfs = MinPtrOfs-4 THEN	(* no pointers in element type *)
			IF Trace & (1 IN traceHeap) THEN
				AosOut.Enter;  AosOut.String("NA ");  AosOut.Int(numElems, 1);  AosOut.Char(" ");
				AosOut.Int(numDims, 1);  AosOut.String("->");  AosOut.Exit
			END;
			size := arrSize + vectSize + 12;
			NewSys(p, size);
			ptr := SYSTEM.VAL(LONGINT, p);
				(* no need to hold Heap lock here, because SysBlk already allocated *)
			SYSTEM.PUT(ptr, SYSTEM.VAL(SET, size + 3) - SYSTEM.VAL(SET, 3));
			SYSTEM.PUT(ptr-8, {ArrayBit});	(* distinguish from normal SysBlk *)
		ELSE	(* allocate a real ArrayBlk *)
			size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, arrSize + vectSize + (16 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
			IF Trace & (1 IN traceHeap) THEN
				AosOut.Enter;  AosOut.String("NA ");  WriteType(elemTag);  AosOut.Char(" ");
				AosOut.Int(numElems, 1);  AosOut.Char(" ");
				AosOut.Int(numDims, 1);  AosOut.Exit
			END;
			AosLocks.Acquire(AosLocks.AosHeap);
			ptr := NewBlock(size);
			firstElem := ptr + 16 + vectSize;
			SYSTEM.PUT(ptr, SYSTEM.VAL(SET, elemTag) + {ArrayBit});	(* tag *)
			SYSTEM.PUT(ptr+4, firstElem + arrSize - elemSize);	(* lastElemToMark *)
			SYSTEM.PUT(ptr+8, NIL);	(* reserved for Mark *)
			SYSTEM.PUT(ptr+12, firstElem);	(* firstElem *)
			p := SYSTEM.VAL(PTR, ptr+4);
			(* clear must be done inside lock to ensure all traced pointer fields are initialized to NIL *)
			AosBoot.Fill32(ptr+16, size-16, 0);
			(* ptr+16..ptr+16 + vectSize-1 initialized by compiler-generated code *)
			AosLocks.Release(AosLocks.AosHeap)
		END
	END
END NewArr;

(** NewType - Allocate a new type descriptor.  Returns pointer to "start" of type desc (AosModules.TypeDesc) *)

PROCEDURE NewType*(VAR p: PTR; recSize, numPtrs, numSlots: LONGINT; name: ARRAY OF CHAR; mod: PTR; flags: SET);
VAR ptr, rootOfs, tdSize, size, i, dst: LONGINT;  flag: INTEGER;  ch: CHAR;
BEGIN
	IF Trace & (6 IN traceHeap) THEN
		AosOut.Enter;  AosOut.String("NT ");  AosOut.Int(recSize, 1);  AosOut.Char(" ");
		AosOut.String(name);  AosOut.Exit
	END;
	IF ProtTypeBit IN flags THEN INC(numPtrs, 5) END;	(* hidden pointers for protected object *)
	AosLocks.Acquire(AosLocks.AosHeap);
	rootOfs := 4*(4+1+numSlots+1) + 32;	(* all fields in TDesc up to recSize, excluding tag *)
	INC(rootOfs, (-rootOfs+8) MOD 16);	(* align as SubObj *)
	tdSize := rootOfs + 4*(1+numPtrs+1);	(* recSize, ptrs & sentinel *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tdSize + (4 + BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));
	ptr := NewBlock(size)+4;
	SYSTEM.PUT(ptr-4, ptr);	(* tag *)
	AosBoot.Fill32(ptr+16, size-(4+16), 0);	(* clear everything except first 4 fields & tag *)
	SYSTEM.PUT(ptr, tdSize);	(* tdSize *)
	SYSTEM.PUT(ptr+4, SYSTEM.VAL(LONGINT, MinPtrOfs-4));	(* sentinel *)
	SYSTEM.PUT(ptr+8, ptr + rootOfs);	(* self *)
	SYSTEM.GET(ptr+10, flag); ASSERT(flag # -1);	(* protected object "flag" for AosInfo.Objects *)
	SYSTEM.PUT(ptr+12, flags);
	SYSTEM.PUT(ptr+16, mod);	(* module hint only, because not traced *)
	i := 0; dst := ptr+20;	(* name *)
	REPEAT ch := name[i];  SYSTEM.PUT(dst, ch);  INC(dst);  INC(i) UNTIL (ch = 0X) OR (i = 31);
	SYSTEM.PUT(dst, 0X);
	(* methods & tags filled in later *)
	SYSTEM.PUT(ptr+rootOfs-4, ptr);	(* indirect tag *)
	SYSTEM.PUT(ptr+rootOfs, recSize);	(* recSize *)
	(* ptrOfs filled in later *)
	IF ProtTypeBit IN flags THEN	(* add ptrOfs for protected object header - cf. AosActive.ObjectHeader *)
		dst := ptr+rootOfs+(numPtrs-5+1)*4;	(* skip over recSize and user's ptrOfs *)
		SYSTEM.PUT32(dst, -36);	(* awaitingLock.head *)
		SYSTEM.PUT32(dst+4, -32);	(* awaitingLock.tail *)
		SYSTEM.PUT32(dst+8, -28);	(* awaitingCond.head *)
		SYSTEM.PUT32(dst+12, -24);	(* awaitingCond.tail *)
		SYSTEM.PUT32(dst+16, -20)	(* lockedBy *)
	END;
	SYSTEM.PUT(ptr+tdSize-4, MinPtrOfs-4*(numPtrs+1));	(* sentinel *)
	p := SYSTEM.VAL(PTR, ptr);
	AosLocks.Release(AosLocks.AosHeap)
END NewType;

(*
replaced by AddFinalizer

(** Register an object for finalization.  For use by system-level modules only.  A finalized object may not be resurrected.  The finalizers will be called by a separate process in AosProcessors.  Oberon finalizers must be installed with Kernel.RegisterObject, which will synchronize the finalizer with the Oberon lock.  When a module is freed or shut down, none of its finalizers are called any more. *)

PROCEDURE RegisterFinalizer*(obj: PTR; fin: Finalizer);
VAR n: FinalizerNode; adr: LONGINT;
BEGIN
	ASSERT(obj # NIL);
	NEW(n);
	n.objWeak := obj; n.finalizer := fin; n.objStrong := NIL;
	adr := SYSTEM.VAL(LONGINT, obj);
	IF SubObjBit IN SYSTEM.VAL(SET, obj) THEN	(* indirect tag *)
		n.markAdr := SYSTEM.GET32(adr-4) - 4
	ELSIF ProtObjBit IN SYSTEM.VAL(SET, obj) THEN	(* protected object *)
		n.markAdr := adr - (ProtOfs + 4)
	ELSE
		n.markAdr := adr - 4
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
	n.nextFin := checkRoot; checkRoot := n;
	IF Stats THEN INC(NfinalizeAlive) END;
	AosLocks.Release(AosLocks.AosHeap)
END RegisterFinalizer;
*)

PROCEDURE AddFinalizer*(obj: PTR; n: FinalizerNode);
VAR adr: LONGINT;
BEGIN
	n.objWeak := obj; n.objStrong := NIL;
	adr := SYSTEM.VAL(LONGINT, obj);
	IF SubObjBit IN SYSTEM.VAL(SET, obj) THEN	(* indirect tag *)
		n.markAdr := SYSTEM.GET32(adr-4) - 4
	ELSIF ProtObjBit IN SYSTEM.VAL(SET, obj) THEN	(* protected object *)
		n.markAdr := adr - (ProtOfs + 4)
	ELSE
		n.markAdr := adr - 4
	END;
	AosLocks.Acquire(AosLocks.AosHeap);
	n.nextFin := checkRoot; checkRoot := n;
	IF Stats THEN INC(NfinalizeAlive) END;
	AosLocks.Release(AosLocks.AosHeap)
END AddFinalizer;

(** Compute total heap size, free space and largest free block size in bytes.  This is a slow operation. *)

PROCEDURE GetHeapInfo*(VAR total, free, largest: LONGINT);
VAR i, size, ptr: LONGINT;
BEGIN
	AosLocks.Acquire(AosLocks.AosHeap);
	total := endBlockAdr-beginBlockAdr;
	free := 0; largest := 0; i := 0;
	WHILE i <= FreeLists DO
		ptr := freeList[i];
		WHILE ptr # NilVal DO
			SYSTEM.GET(ptr+4, size); INC(free, size);
			IF size > largest THEN largest := size END;
			SYSTEM.GET(ptr+8, ptr)	(* next *)
		END;
		INC(i)
	END;
	AosLocks.Release(AosLocks.AosHeap)
END GetHeapInfo;

(*
(** Call this periodically (e.g. a few times a second) to perform cleanup tasks. *)

PROCEDURE PeriodicCleanup*;
BEGIN
	IF newSum > gcThreshold THEN	(* call GC every so often to avoid fragmentation *)
		AosLocks.Acquire(AosLocks.AosHeap);
		newSum := 0;
		AosLocks.Release(AosLocks.AosHeap);
		GC
	END
END PeriodicCleanup;
*)
(* ug *)
PROCEDURE TestGC*(par : ANY): ANY;
BEGIN
	GC;
	RETURN NIL
END TestGC;

(* NilGC - Default garbage collector. *)

PROCEDURE NilGC;
BEGIN
	HALT(301)	(* garbage collector not available yet *)
END NilGC;

(* Init - Initialize the heap. *)

PROCEDURE Init;
VAR p, t, size, freeBlockAdr: LONGINT; s: SET; ch: CHAR; u: ARRAY 32 OF CHAR;
BEGIN
	AosMemory.GetFreeK(size, t, t);	(* size is total memory size in KB *)
	heapMinKB := size*HeapMin DIV 100;
	heapMaxKB := size*HeapMax DIV 100;
	expandMin := size*ExpandRate DIV 100 * 1024;
	IF expandMin < 0 THEN expandMin := MAX(LONGINT) END;
	gcThreshold := size*Threshold DIV 100 * 1024;
	IF gcThreshold < 0 THEN gcThreshold := MAX(LONGINT) END;
	newSum := 0;
		(* initialize globals *)
	GC := NilGC;
	IF Trace THEN
		AosBoot.GetConfig("TraceHeap", u);
		t := 0;  traceHeap := SYSTEM.VAL(SET, AosBoot.StrToInt(t, u))
	END;
	checkRoot := NIL; finalizeRoot := NIL;
		(* dimension heap *)
	AosMemory.GetStaticHeap(beginAdr, endAdr, beginBlockAdr, freeBlockAdr);
	ASSERT(beginBlockAdr MOD BlockSize = BlockSize-4);
	ASSERT(freeBlockAdr MOD BlockSize = BlockSize-4);
	INC(endAdr, InitialHeapIncrement);
	AosMemory.SetHeapEndAdr(endAdr);	(* in/out parameter *)
	endBlockAdr := endAdr-4;
	ASSERT((endBlockAdr - beginBlockAdr) MOD BlockSize = 0);
		(* find last block in static heap (last tag will be NIL - set in AosMemory) *)
	p := beginBlockAdr;  SYSTEM.GET(p, t);	(* get first tag *)
	WHILE t # 0 DO
		SYSTEM.GET(t - t MOD 8, size);
		SYSTEM.GET(p, s);	(* get tag again *)
		IF ArrayBit IN s THEN
			SYSTEM.GET(p+4, t);	(* get lastElemToMark *)
			size := t + size - p	(* size of array, including tag *)
		ELSE
			INC(size, 4)	(* include tag *)
		END;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1));	(* round up *)
		initBlock := SYSTEM.VAL(PTR, p+(4+24));	(* last block so far, as SysBlk *)
		INC(p, size);  SYSTEM.GET(p, t)	(* get next tag *)
	END;
	SYSTEM.GET(initBlock, ch);  ASSERT(ch = 0E8X);	(* call to first module body *)
		(* now initBlock points to last block, i.e. the init calls => they won't be GC'ed *)
	
		(* initial free block *)
	p := freeBlockAdr+4;  s := SYSTEM.VAL(SET, p) + {FreeBit};
	SYSTEM.PUT(p-4, s);	(* tag *)
	SYSTEM.PUT(p, endBlockAdr-p);	(* size *)
	SYSTEM.PUT(p+4, NIL);	(* next *)
		(* the first garbage collect will be done in AosActive, after trap handling installed *)
	lastFreeListAdr := SYSTEM.ADR(freeList[FreeLists])
END Init;

BEGIN
	IF AosBoot.Trace THEN AosOut.Enter; AosOut.String("AosHeap"); AosOut.Exit END;
	Init
END AosHeap.

(*
TraceHeap:
0	1	NR NEW record
1	2	NA/NV NEW array
2	4	NS SYSTEM.NEW
3	8	DR deallocate record #
4	16	DA deallocate array #
5	32	DS deallocate sysblk #
6	64	NT NewType
7	128	
8	256	FB show free blocks #
9	512	DP deallocate protrec #
10	1024	finalizers
11	2048	live/dead #
12 4096 trace mark stack overflows #

# influences timing
*)

(*
20.03.1998	pjm	Started
17.08.1998	pjm	FindRoots method
18.08.1998	pjm	findPossibleRoots removed, use FindRoots method
09.10.1998	pjm	NewRec with page alignment
21.01.1999	pjm	Mark adapted for AosBuffers
26.01.1999	pjm	Incorporated changes for new compiler
10.11.2000	pjm	Finalizers
26.01.2001	pjm	Removed trapReserve, reimplemented NewBlock
11.11.2004	lb	   Garbage collector with marking stack
19.06.2007	ug	Garbage collector using meta data for stack inspection (cf. AosActive)
*)
