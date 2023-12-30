MODULE WMPerfMonPluginMemory; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor memory utilization plugin"; *)
(*
 * History:
 *
 *	16.02.2006	First Release (staubesv)
 *	23.06.2006	Adapted to WMPerfMonPlugins (staubesv)
 *	19.07.2006	Added BlocksHelper and Blocks/BlockSizes  & GcRuns plugins (staubesv)
 *	25.07.2006	Added NewBlockCalls & BytesAllocated plugins (staubesv)
 *	27.02.2007	HeapSize, HeapFree and HeapLargest merged into HeapStats, added AosMemoryStats plugin (staubesv)
 *)

IMPORT
	SYSTEM, AosOut, AosModules,
	WMPerfMonPlugins, WMGraphics,
	AosLocks, AosHeap, AosBoot, AosMemory;
	
CONST
	ModuleName = "WMPerfMonPluginMemory";

	(* HeapBlocksHelper *)
	ArrayBit = 1; FreeBit = 2; SubObjBit = 3;
	BlockSize = AosHeap.BlockSize;

TYPE

	(* AosHeap.GetHeapInfo is a slow operation. HeapHelper provides its results to multiple plugins *)
	HeapHelper = OBJECT(WMPerfMonPlugins.Helper)
	VAR
		free-, total-, largest- : LONGINT;
		
		PROCEDURE Update*;
		BEGIN
			AosHeap.GetHeapInfo(total, free, largest);			
		END Update;
	
	END HeapHelper;
	
TYPE

	HeapStats = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		h : HeapHelper; 
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "Heap"; p.description := "Heap statistics"; p.modulename := ModuleName;
			p.autoMax := TRUE; p.unit := "KB"; p.minDigits := 7;
			p.helper := heapHelper; h := heapHelper;
			NEW(ds, 3);
			ds[0].name := "Size";
			ds[1].name := "Free";
			ds[2].name := "LargestBlock";
			p.datasetDescriptor := ds;
		END Init;
						
		PROCEDURE UpdateDataset*;
		BEGIN 
			dataset[0] := h.total DIV 1024;
			dataset[1] := h.free DIV 1024;
			dataset[2] := h.largest DIV 1024;
		END UpdateDataset;
		
	END HeapStats;
	
TYPE

	StackSize = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		h : HeapHelper;
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		BEGIN
			p.name := "StackSize"; p.description := "Approximate size of stack"; p.modulename := ModuleName;
			p.autoMax := TRUE; p.unit := "KB"; p.minDigits := 6;
			p.helper := heapHelper; h := heapHelper;
		END Init;
		
		PROCEDURE UpdateDataset*;
		VAR current, totMem, lowFree, highFree : LONGINT;
		BEGIN
			AosMemory.GetFreeK(totMem, lowFree, highFree);
			current := ((totMem - lowFree - highFree) - (h.total DIV 1024));
			dataset[0] := current;
		END UpdateDataset;
		
	END StackSize;
	
TYPE

	MemoryLoad* = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		h : HeapHelper;
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR total, lowFree, highFree : LONGINT;
		BEGIN
			p.name := "MemoryUsage"; p.description := "Stack & Heap memory usage"; p.modulename := ModuleName;
			AosMemory.GetFreeK(total, lowFree, highFree);
			p.max := total DIV 1024; p.autoMax := FALSE; p.unit := "MB"; p.showPercent := TRUE;
			p.scale := 1024; p.minDigits := 7; p.fraction := 0; p.statsUnit := "KB";
			p.helper := heapHelper; h := heapHelper;
		END Init;
						
		PROCEDURE UpdateDataset*;
		VAR current, totMem, lowFree, highFree : LONGINT;
		BEGIN 
			AosMemory.GetFreeK(totMem, lowFree, highFree);
			(* Memory mapped for heap and stack - free memory on heap *)
			current := ((totMem - lowFree - highFree) - (h.free DIV 1024));
			dataset[0] := current / 1024;			
		END UpdateDataset;
	
	END MemoryLoad;

TYPE

	BlocksHelper = OBJECT(WMPerfMonPlugins.Helper)
	VAR
		blocks-,
		recblks-, sysblks-, arrblks-, typedescs-, protrecblks-, freeblks-, unknowns- : LONGINT;
		blockssize-,
		recblksize-, sysblksize-, arrblksize-, typedescsize-, protrecblksize-, freeblksize-, unknownsize-, heapsize- : LONGINT;
		
		PROCEDURE Update*;
		VAR p, tag, size, t : LONGINT; flag : INTEGER;
		BEGIN
			blocks := 0; recblks := 0; sysblks := 0; arrblks := 0;
			typedescs := 0; protrecblks := 0; freeblks := 0; unknowns := 0;
			blockssize := 0; recblksize := 0; sysblksize := 0; arrblksize := 0;
			typedescsize := 0; protrecblksize := 0; freeblksize := 0; unknownsize := 0;
			AosLocks.Acquire(AosLocks.AosHeap);
			p := AosHeap.beginBlockAdr;
			WHILE p # AosHeap.endBlockAdr DO
				SYSTEM.GET(p, tag);
				SYSTEM.GET(tag - tag MOD 8, size);	(* record size, excluding tag *)
				INC(blocks); INC(blockssize, size);
				IF FreeBit IN SYSTEM.VAL(SET, tag) THEN
					INC(freeblks); INC(freeblksize, size);
				ELSIF ArrayBit IN SYSTEM.VAL(SET, tag) THEN
					INC(arrblks); INC(arrblksize, size);
				ELSIF SubObjBit IN SYSTEM.VAL(SET, tag) THEN
					INC(recblks); INC(recblksize, size);
				ELSIF tag = p+4 THEN
					SYSTEM.GET(p+4+10, flag);
					IF flag = -1 THEN
						INC(protrecblks); INC(protrecblksize, size);
					ELSIF flag = 0 THEN
						INC(sysblks); INC(sysblksize, size);	(* or arrsysblks, or typedescs *)
					ELSE
						INC(typedescs); INC(typedescsize, size);
					END
				ELSE
					INC(unknowns); INC(unknownsize, size)
				END;
				IF ArrayBit IN SYSTEM.VAL(SET, tag) THEN
					SYSTEM.GET(p+4, t);	(* lastElemToMark *)
					size := t + size - p; (* size of array, including tag *)
				ELSE
					INC(size, 4);	(* include tag *)
				END;
				size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (BlockSize-1)) - SYSTEM.VAL(SET, BlockSize-1)); (* round up *)
				INC(p, size);
			END;
			heapsize := AosHeap.endBlockAdr-AosHeap.beginBlockAdr;
			AosLocks.Release(AosLocks.AosHeap);
		END Update;
	
	END BlocksHelper;
	
TYPE

	Blocks* = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		h : BlocksHelper;
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "Blocks"; p.description := "Number and types of blocks on the heap"; p.modulename := ModuleName;
			p.autoMax := TRUE; p.noSuperSampling := TRUE; (* since expensive *)
			p.minDigits := 9; p.fraction := 0;
			p.helper := blocksHelper; h := blocksHelper;
			
			NEW(ds, 8);
			ds[0].name := "blocks"; ds[0].color := WMGraphics.White;
			ds[1].name := "recblocks"; ds[1].color := WMGraphics.Green;
			ds[2].name := "sysblocks"; ds[2].color := WMGraphics.Red;
			ds[3].name := "arrblocks"; ds[3].color := WMGraphics.Blue;
			ds[4].name := "typedescs"; ds[4].color := WMGraphics.Cyan;
			ds[5].name := "protrecblocks"; ds[5].color := WMGraphics.Magenta;
			ds[6].name := "freeblocks"; ds[6].color := WMGraphics.Yellow;
			ds[7].name := "unknown"; ds[7].color := WMGraphics.Black;
			p.datasetDescriptor := ds;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN 
			dataset[0] := h.blocks;
			dataset[1] := h.recblks;
			dataset[2] := h.sysblks;
			dataset[3] := h.arrblks;
			dataset[4] := h.typedescs;
			dataset[5] := h.protrecblks;
			dataset[6] := h.freeblks;
			dataset[7] := h.unknowns;			
		END UpdateDataset;
	
	END Blocks;
	
TYPE

	BlockSizes* = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		h : BlocksHelper;
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "BlockSizes"; p.description := "Sizes of blocks on the heap"; p.modulename := ModuleName;
			p.autoMax := TRUE; p.noSuperSampling := TRUE; (* since expensive *)
			p.minDigits := 9; p.fraction := 0; p.unit := "KB";
			p.helper := blocksHelper; h := blocksHelper;
			
			NEW(ds, 8);
			ds[0].name := "blocks"; ds[0].color := WMGraphics.White;
			ds[1].name := "recblocks"; ds[1].color := WMGraphics.Green;
			ds[2].name := "sysblocks"; ds[2].color := WMGraphics.Red;
			ds[3].name := "arrblocks"; ds[3].color := WMGraphics.Blue;
			ds[4].name := "typedescs"; ds[4].color := WMGraphics.Cyan;
			ds[5].name := "protrecblocks"; ds[5].color := WMGraphics.Magenta;
			ds[6].name := "freeblocks"; ds[6].color := WMGraphics.Yellow;
			ds[7].name := "unknown"; ds[7].color := WMGraphics.Black;
			p.datasetDescriptor := ds;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN 
			dataset[0] := h.blockssize;
			dataset[1] := h.recblksize;
			dataset[2] := h.sysblksize;
			dataset[3] := h.arrblksize;
			dataset[4] := h.typedescsize;
			dataset[5] := h.protrecblksize;
			dataset[6] := h.freeblksize;
			dataset[7] := h.unknownsize;			
		END UpdateDataset;
	
	END BlockSizes;
	
TYPE

	GcRuns = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		BEGIN
			p.name := "GcRuns"; p.description := "Number of times the GC has been run since system start"; p.modulename := ModuleName;
			p.noSuperSampling := TRUE;
			p.autoMax := TRUE; p.minDigits := 5;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosHeap.Ngc;
		END UpdateDataset;
		
	END GcRuns;
	
TYPE

	NewBlockCalls = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		BEGIN
			p.name := "NewBlocks"; p.description := "Number of times AosHeap.NewBlock has been called since system startup"; 
			p.modulename := ModuleName;
			p.noSuperSampling := TRUE;
			p.autoMax := TRUE; p.minDigits := 5;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosHeap.Nnew;
		END UpdateDataset;
		
	END NewBlockCalls;
	
TYPE

	BytesAllocated = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		BEGIN
			p.name := "KBAllocated"; p.description := "KBytes allocated since system start"; p.modulename := ModuleName;
			p.noSuperSampling := TRUE; p.unit := "KB";
			p.autoMax := TRUE; p.minDigits := 5;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosBoot.DivH(AosHeap.NnewBytes, 1024);
		END UpdateDataset;
		
	END BytesAllocated;
	
TYPE
	
	AosMemoryStats = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosMemory"; p.description := "AosMemory statistics"; p.modulename := ModuleName;
			p.noSuperSampling := TRUE; p.unit := "";
			p.autoMax := TRUE; p.minDigits := 7;
			NEW(ds, 9);
			ds[0].name := "Nbigskips";	
			ds[1].name := "Nfilled";	
			ds[2].name := "NnewStacks";	
			ds[3].name := "NnewStackLoops";	
			ds[4].name := "NnewStackInnerLoops";	
			ds[5].name := "NdisposeStacks";	
			ds[6].name := "NlostPages";	
			ds[7].name := "NreservePagesUsed";	
			ds[8].name := "NmaxUserStacks";
			p.datasetDescriptor := ds;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosMemory.Nbigskips;
			dataset[1] := AosMemory.Nfilled;
			dataset[2] := AosMemory.NnewStacks;
			dataset[3] := AosMemory.NnewStackLoops;
			dataset[4] := AosMemory.NnewStackInnerLoops;
			dataset[5] := AosMemory.NdisposeStacks;
			dataset[6] := AosMemory.NlostPages;
			dataset[7] := AosMemory.NreservePagesUsed;
			dataset[8] := AosMemory.NmaxUserStacks;
		END UpdateDataset;

	END AosMemoryStats;

VAR
	heapHelper : HeapHelper;
	blocksHelper : BlocksHelper;
	
PROCEDURE InitPlugins;
VAR 
	par : WMPerfMonPlugins.Parameter;
	hs : HeapStats; ml : MemoryLoad;
	ss : StackSize;
	blocks : Blocks; blockSizes : BlockSizes;
	gcRuns : GcRuns;
	newBlockCalls : NewBlockCalls; bytesAllocated : BytesAllocated;
	memstats : AosMemoryStats;
BEGIN
	NEW(par); NEW(hs, par);
	NEW(par); NEW(ml, par);
	NEW(par); NEW(ss, par);
	NEW(par); NEW(blocks, par);
	NEW(par); NEW(blockSizes, par);
	NEW(par); NEW(gcRuns, par);
	NEW(par); NEW(newBlockCalls, par);
	NEW(par); NEW(bytesAllocated, par);
	IF AosMemory.Stats THEN
		NEW(par); NEW(memstats, par);
	ELSE
		AosOut.String(ModuleName); AosOut.String(": AosMemory.Stats is FALSE. AosMemory plugin not installed."); AosOut.Ln;
	END;
END InitPlugins;

PROCEDURE Install*(par : ANY) : ANY;
BEGIN
	RETURN NIL
END Install;

PROCEDURE Cleanup;
BEGIN
	WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);	
END Cleanup;

BEGIN
	NEW(heapHelper); NEW(blocksHelper);
	InitPlugins;
	AosModules.InstallTermHandler(Cleanup);
END WMPerfMonPluginMemory.

WMPerfMonPluginMemory.Install ~	S.Free WMPerfMonPluginMemory ~
