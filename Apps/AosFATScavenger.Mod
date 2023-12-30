MODULE AosFATScavenger; (** AUTHOR: "staubesv"; PURPOSE: "Scavenger and format for FAT file systems" *)
(*
 * FAT Scavenger
 *
 *	checks implemented: (d)etect, (f)ix
 *	
 *	- long entries:
 *	    - corresponding shortEntry existent (d)
 *		- checksum matches shortEntry checksum  (d)
 *		- order correct and terminated with 0x40 mask (d)
 *		- longname contains only legal characters (d)
 *		- terminated longnames are padded (d)
 *		
 *	- short entries
 *		- name contains only legal characters (d) 
 *		- fileSize > number of cluster in chain - 1 (d)
 *		- dot and dot dot point to current rsp. parent folder (d)
 * 		
 *	- FAT
 *		- all FATs are equal (d)
 *		- crosslink (d)
 *		- lost clusters (d+f)
 *			- lost cluster is crosslinked to valid cluster (d+f) 
 *	
 *	- volume:
 *		- bad clusters (d+f)
 *			
 *	Reference:
 *	[1] Microsoft Extensible Firmware Initiative: FAT32 File System Specification, Veriosn 1.03, December 6, 2000
 *
 * History:
 *
 *	05.08.2005	Cleanup (staubesv)
 *	12.12.2005	Don't open/close AosDisks.Device here, it's now done in AosPartitionsLib.Operation (staubesv)
 *	19.12.2005	Enable write access for scavenger, scavenger cleanup (staubesv)
 *)	

IMPORT 
	AosOut, AosIO, AosFS, AosFATVolumes, AosActive, AosDisks, SYSTEM, AosFATFiles, UTF8Strings,
 	AosKernel, AosPlugins, Utilities, AosPartitionsLib, AosClock, WMPartitions;
		
CONST
	
	Trace = FALSE; 
	Details = FALSE;
	
	OK = AosDisks.Ok;
	
	LongName = 15;
	
	(* directory entry marks *)
	EntryFree = 0E5X; 
	EntryFreeLast = 0X;

	(* FAT entry marks *)
	FREE = AosFATVolumes.FREE;
	EOC = AosFATVolumes.EOC;
	BAD = AosFATVolumes.BAD;
	
	(* constants for FStype *)
	FAT12* = 0; FAT16* = 1; FAT32* = 2;
	
	(* volume dirty flags *)
	fat32CleanShutdown = {27};
	fat32IOError	= {26};
	fat16CleanShutdown = {15};
	fat16IOError	= {14};
	
	SectorSize = 512;
	BufferSize =  512; (* in nbr of sectors per FAT; used in CompareFATs; default:=512KByte per FAT *)
	BitmapSize = 65536; (* nbr of 32bit entries in one block of the bitmap *)
	
	BS = AosPartitionsLib.BS;
	
	(* BIOS Parameter Block offsets (sector 0 of FAT Volumes) (ALL FAT FS) *)
	(* signature : BootSec[510] = 055X; BootSec[511] = 0AAX; *)
	BsJmpBoot = 0; 
	BsOEMName = 3;
	BpbBytsPerSec = 11; 
	BpbSecPerClus = 13; 
	BpbRsvdSecCnt = 14; 
	BpbNumFATs = 16; 
	BpbRootEntCnt = 17;
	BpbTotSec16 = 19;
	BpbMedia = 21;
	BpbFATSz16 = 22;
	BpbSecPerTrk = 24;
	BpbNumHeads = 26;
	BpbHiddSec = 28;
	BpbTotSec32 = 32;
	
	(* Beginning from offset 36 the different FAT types differ *)
	(* FAT12/FAT16 *)
	BsDrvNum = 36;
	BsReserved1 = 37;
	BsBootSig = 38;
	BsVolID = 39;
	BsVolLab = 43;
	BsFilSysType = 54;
	
	(* FAT32 *)
	BpbFATSz32 = 36;
	BpbExtFlags = 40;
	BpbFSVer = 42;
	BpbRootClus = 44;
	BpbFSInfo = 48;
	BpbBkBootSec = 50;
	BpbReserved = 52;
	Bs32DrvNum = 64;
	Bs32Reserved1 = 65;
	Bs32BootSig = 66;
	Bs32VolID = 67;
	Bs32VolLab = 71;
	Bs32FilSysType = 82;
	
	(* FAT32 only: FSInfo sector structure *)
	FsiLeadSig = 0;
	FsiReserved1 = 4;
	FsiStrucSig = 484;
	FsiFreeCount = 488;
	FsiNxtFree = 492;
	FsiReserved2 = 496;
	FsiTrailSig = 508;
	
TYPE

	Block = AosPartitionsLib.Block;

	String = AosPartitionsLib.String;

	(* data structure to track progress *)
	Node = POINTER TO RECORD
		cluster, offset : LONGINT;
		parent, first : LONGINT; (* parent: first cluster of parent folder; first: first cluster of clusterchain containing this cluster *)
		next : Node;
	END;
	
	(* Stack for Node elements*)
	STACK = OBJECT
	VAR
		head : Node;
		
		PROCEDURE PushCluster*(cluster : Cluster);
		VAR
			temp : Node;
		BEGIN
			ASSERT(cluster#NIL);
			NEW(temp);
			temp.cluster:=cluster.cluster; temp.offset:=cluster.GetPos(); 
			temp.first:=cluster.first; temp.parent:=cluster.parent;
			temp.next:=head.next; head.next:=temp; 
			(* the fields temp.first and temp.parent are initializes in ProcessHead if necessary *)
		END PushCluster; 
		
		PROCEDURE Push*(node : Node);
		BEGIN
			ASSERT(node#NIL);
			node.next:=head.next; head.next:=node;
		END Push;
		
		PROCEDURE ReplaceTop*(cluster : Cluster);
		BEGIN
			ASSERT((cluster#NIL) & (~Empty()));
			head.next.cluster:=cluster.cluster;
			head.next.offset:=cluster.GetPos();
		END ReplaceTop;
		
		PROCEDURE RemoveTop*; BEGIN ASSERT(~Empty()); head.next:=head.next.next;  END RemoveTop;
		PROCEDURE GetTop*():Node; BEGIN ASSERT(~Empty()); RETURN head.next; END GetTop;		
		PROCEDURE Empty*():BOOLEAN;	BEGIN RETURN (head.next=NIL); END Empty;
		
		PROCEDURE &Init;
		BEGIN
			NEW(head); head.next:=NIL;
		END Init;
		
	END STACK;
	
TYPE
	
	LongEntryList = OBJECT
	VAR
		head, current : LongEntry;
			
		PROCEDURE Insert*(entry: LongEntry);
		BEGIN
			entry.next:=head.next; head.next:=entry;
		END Insert;
		
		PROCEDURE GetNext*():LongEntry;  
		VAR
			result : LongEntry;
		BEGIN
			ASSERT((head.next#NIL) & (current#NIL));
			result:=current; current:=current.next;
			RETURN result;
		END GetNext;

		PROCEDURE SetCurrent*; BEGIN current:=head.next; END SetCurrent;
		PROCEDURE HasNext*():BOOLEAN; BEGIN RETURN (current#NIL); END HasNext;
		PROCEDURE Clear*; BEGIN head.next:=NIL; current:=NIL; END Clear;
		
		PROCEDURE &Init;
		BEGIN
			NEW(head); head.next:=NIL; current:=NIL;
		END Init;
		
	END LongEntryList;
	
TYPE
	
	(* abstract data type for FAT directory entry *)
	Entry = OBJECT 
	VAR
		(* if errors are found when checking this short entry, the checker fills
		the data field <correctedEntry> with the corrected version of the orginal data (rawEntry) *)
		rawEntry, correctedEntry : ARRAY 32 OF CHAR; 																	    		
		
		(* This entry is located at cluster number <cluster> at <offset>*32Bytes *)
		cluster : AosFS.Address;
		offset : LONGINT; 
		
		PROCEDURE ParseRawEntry*;
		BEGIN
			HALT(99); (* abstract *)
		END ParseRawEntry;
	
		(* Debug: prints the information contained in rawEntry in human readable form to the KernelLog *)
		PROCEDURE Print*;
		BEGIN
			HALT(99); (* abstract *)
		END Print;
	END Entry;
	
	ShortEntry = OBJECT(Entry)
	VAR 	 						
		(* FAT FS directory entry fields *)
		shortName: ARRAY 12 OF CHAR; (* 11 byte from directory entry + 1 byte 0X for string termination*)
		attr : SET;
		(* NTRes : CHAR; ignored *)
		(* CrtTimeTenth : CHAR; ignored *)
		crtTime, crtDate : LONGINT;
		lstAccDate : LONGINT;
		firstCluster : LONGINT;
		wrtTime, wrtDate : LONGINT;
		fileSize : LONGINT;
		
		directory : BOOLEAN; (* is this ShortEntry a folder? *)
						
		PROCEDURE ParseRawEntry*;
		VAR i : LONGINT;
		BEGIN		
		
			(* get shortname *)
			IF rawEntry[0]=05X THEN (* special case: if the first character is 0x05 then the character 0xE5 (marks entry as free ) is meant *)
				shortName[0]:=0E5X 
			ELSE 
				shortName[0]:=rawEntry[0]; 
			END;
			FOR i:=1 TO 10 DO shortName[i]:=rawEntry[i]; END;
			shortName[11]:=0X;
 							
			(* get attributes *)
			attr:=SYSTEM.VAL(SET, LONG(ORD(rawEntry[11])));
			IF (AosFATFiles.faDirectory IN attr) THEN directory:=TRUE; ELSE directory:=FALSE; END;
 							
			(* get creation time and date *)
			crtTime:=AosFATFiles.TimeFAT2Oberon(AosFATVolumes.GetUnsignedInteger(rawEntry,14),ORD(rawEntry[13]));
			crtDate:=AosFATFiles.DateFAT2Oberon(AosFATVolumes.GetUnsignedInteger(rawEntry,16));
							
			(* get last access date *)
			lstAccDate:=AosFATFiles.DateFAT2Oberon(AosFATVolumes.GetUnsignedInteger(rawEntry, 18));
 							
			(* get first cluster *)
			firstCluster:=AosFATVolumes.GetUnsignedInteger(rawEntry, 26);
			IF fsType2=FAT32 THEN firstCluster:=firstCluster+10000H*AosFATVolumes.GetUnsignedInteger(rawEntry,20); END;

			(* get time and date of last write access *)
			wrtTime:=AosFATFiles.TimeFAT2Oberon(AosFATVolumes.GetUnsignedInteger(rawEntry,22),0);
			wrtDate:=AosFATFiles.DateFAT2Oberon(AosFATVolumes.GetUnsignedInteger(rawEntry,24));
 							
			(* get filesize *)
			fileSize:=AosFATVolumes.GetLongint(rawEntry,28);						
			
			(* update correctedRawEntry *)
			COPY(rawEntry, correctedEntry);
		END ParseRawEntry;
		
		(* calculates a checksum for the shortName field which must match the checksum-field of long directory entries *)
		PROCEDURE GetChecksum*(): LONGINT;		
		VAR
			checksum, i : LONGINT;
		BEGIN
			checksum:=0;
			FOR i:=0 TO 10 DO
				IF ODD(checksum) THEN checksum := 80H + checksum DIV 2 ELSE checksum := checksum DIV 2 END;
				checksum := (checksum + ORD(shortName[i])) MOD 100H
			END;
			RETURN checksum;
		END GetChecksum;
 						
		(* debug: display content of this short entry to KernelLog *)
		PROCEDURE Print*;
		BEGIN
			AosOut.String(shortName);
			IF AosFATFiles.faReadOnly IN attr THEN AosOut.String("   R"); ELSE AosOut.String("   r"); END;
			IF AosFATFiles.faHidden IN attr THEN AosOut.String("H"); ELSE AosOut.String("h"); END;
			IF AosFATFiles.faSystem IN attr THEN AosOut.String("S"); ELSE AosOut.String("s"); END;
			IF AosFATFiles.faArchive IN attr THEN AosOut.String("A"); ELSE AosOut.String("a"); END;
			IF AosFATFiles.faDirectory IN attr THEN AosOut.String("D"); ELSE AosOut.String("d"); END;
			IF AosFATFiles.faVolumeID IN attr THEN AosOut.String("V   "); ELSE AosOut.String("v   "); END;
			AosOut.String("1st: "); AosOut.Int(firstCluster,10);
			AosOut.String("  size: "); AosOut.Int(fileSize,10);
			AosOut.Ln;
		END Print;		
	
	END ShortEntry;
	              
	LongEntry = OBJECT(Entry)
	VAR
		(* FAT Long Directory Entry Structure *) 
		order : INTEGER;   (* in cluster chain *)
		name: ARRAY 13 OF LONGINT;  (* unicode *)		
		type : INTEGER;
		chksum : LONGINT;
		FstClusLO : LONGINT;
		
		next : LongEntry;  (* link to next longentry; used by LongEntryList *)							
		last : BOOLEAN; (* last cluster in longname cluster chain *)

		PROCEDURE ParseRawEntry*;
		VAR
			i,j : INTEGER;
		BEGIN
			(* last cluster in the chain ? *)
			IF AosFATVolumes.AND(40H, ORD(rawEntry[0])) = 40H THEN 
				last:=TRUE; 
				order:=ORD(rawEntry[0]) MOD 40H;
			ELSE
				order:=ORD(rawEntry[0]);
			END;
			
    			chksum:=ORD(rawEntry[13]);
										 
			(* read in long name component *)
			j:=0;
			FOR i:=0 TO 4 DO name[j]:=AosFATVolumes.GetUnsignedInteger(rawEntry,1+2*i); INC(j); END;
			FOR i:=0 TO 5 DO name[j]:=AosFATVolumes.GetUnsignedInteger(rawEntry,14+2*i); INC(j); END;
			FOR i:=0 TO 1 DO name[j]:=AosFATVolumes.GetUnsignedInteger(rawEntry,28+2*i); INC(j); END;
										 
			type:=ORD(rawEntry[12]);
			FstClusLO:=AosFATVolumes.GetUnsignedInteger(rawEntry,26);
			
			(* initialize correctedEntry field *)
			COPY(rawEntry, correctedEntry);
		END ParseRawEntry;
									
		PROCEDURE Print*;
		VAR longname : ARRAY 256 OF CHAR;
		BEGIN
			AosOut.String("Long: "); 	AosOut.String("order: "); AosOut.Int(order,3); AosOut.String("   ");
			UTF8Strings.UnicodetoUTF8(name, longname); AosOut.String(longname);
			AosOut.Ln;
		END Print;

		PROCEDURE &Init;
		BEGIN
			last:=FALSE; next:=NIL;
		END Init;									
		
	END LongEntry;

TYPE
	
	Bitmap = POINTER TO ARRAY OF SET;

	ClusterBitmap = OBJECT
	VAR
		maxClusters : LONGINT;
	
		bitmaps : POINTER TO ARRAY OF Bitmap;
		bitmapsPos, bmPos, bmOffset: LONGINT;

		PROCEDURE &Init(MaxClusters : LONGINT);
		VAR
			size : LONGINT;
		BEGIN
			maxClusters:=MaxClusters;
			size:=maxClusters DIV BitmapSize*MAX(SET);
			IF maxClusters MOD BitmapSize*MAX(SET)>0 THEN INC(size); END;
			NEW(bitmaps, size);
			ASSERT(bitmaps#NIL);
		END Init;	
			
		PROCEDURE CalcAddress(pos: LONGINT);
		VAR
			bitmapSize : LONGINT;
		BEGIN
			ASSERT((pos<=maxClusters+1) & (pos>1));	
		 	bitmapSize:=BitmapSize*(MAX(SET)+1);
			bitmapsPos:=pos DIV bitmapSize;
			bmPos := ( pos MOD bitmapSize )  DIV  (MAX(SET)+1);
			bmOffset := ( pos MOD bitmapSize ) MOD (MAX(SET)+1); 
			ASSERT((bmOffset <= MAX(SET)) & (bmPos<BitmapSize));
		END CalcAddress;
		
		PROCEDURE SetBit*(pos : LONGINT; VAR collision: BOOLEAN);
		VAR
			bitmap : Bitmap;
		BEGIN
			ASSERT((pos<=maxClusters+1) & (pos>1));
			
			CalcAddress(pos);
			
			IF bitmaps[bitmapsPos]=NIL THEN (* create Bitmap if not yet done *)
				NEW(bitmap, BitmapSize);
				ASSERT(bitmap#NIL);
				bitmaps[bitmapsPos]:=bitmap;
			END;	
			
			bitmap:=bitmaps[bitmapsPos];
			
			IF bmOffset IN bitmap[bmPos] THEN (* ERROR: report collision, FAT entry already used *)
				collision:=TRUE; 
			ELSE
				INCL(bitmap[bmPos], bmOffset); collision:=FALSE;
			END;
		END SetBit;
			
		(* returns true if the bit at position <pos> is set, false otherwise *)
		PROCEDURE IsSet*(pos : LONGINT):BOOLEAN;
		BEGIN
			CalcAddress(pos);
			RETURN bmOffset IN bitmaps[bitmapsPos][bmPos];
		END IsSet;
	END ClusterBitmap;
								
	Cluster = OBJECT
	VAR
		cluster : LONGINT; (* FAT32: address of the cluster; FAT1216: if rootDir t-...... *)
		parent, first : LONGINT; (* parent: first cluster of parent folder; first: first cluster of this foldes *)
		clusterSize : LONGINT;
		currentEntry, maxEntries: LONGINT;
		data : POINTER TO ARRAY OF CHAR;
  					
		next : LONGINT; (* cluster number of next cluster of this foldes, 0: none*)
			   									
		PROCEDURE &Init(csize :LONGINT);
		BEGIN
			clusterSize:=csize; maxEntries:=clusterSize DIV 32; 
			NEW(data, clusterSize);
			next:=0;
		END Init;
		
		PROCEDURE SetPos*(pos: LONGINT);
		BEGIN
			ASSERT((pos<=maxEntries) & (pos >= 0)); (* position can be one greater than allowed. will be checked *)
			currentEntry:=pos;
		END SetPos;
		
		PROCEDURE GetPos*(): LONGINT;
		BEGIN
			ASSERT(currentEntry<=maxEntries); (* can be bigger than maxEntries-1 *)
			RETURN currentEntry;
		END GetPos;
		
		PROCEDURE GetNext*():Entry;
		VAR
			result : Entry; 
			shortEntry : ShortEntry;
			longEntry : LongEntry;
			i ,j : LONGINT;
			type: LONGINT;
		BEGIN
			ASSERT(currentEntry<=maxEntries-1);
			type:=AosFATVolumes.AND(3FH, ORD(data[currentEntry*32+11])); (*loads lower 6 bits from attr field *)
										
			IF (data[currentEntry*32]#EntryFree) & (data[currentEntry*32]#EntryFreeLast) THEN (* entry not free *)
			
				IF (type=LongName) THEN (* long directory entry or invalid entry *)
					NEW(longEntry); result:=longEntry;						
				ELSE (* short directory entry, volumeID entry or invalid entry *)		
					NEW(shortEntry);  result:=shortEntry;  
				END;		

				j:=0;
				FOR i:=currentEntry*32 TO currentEntry*32+31 DO result.rawEntry[j]:=data[i];INC(j); END;
				result.offset:=currentEntry;
				
				result.ParseRawEntry; (* evaluate the result.rawEntry[] data *)

			ELSE (* free entry *)
				result:=NIL;
			END;
  							
			currentEntry:=currentEntry+1;					
			RETURN result;
		END GetNext;
   					
		PROCEDURE HasNext*():BOOLEAN;
		BEGIN
			RETURN (currentEntry <= maxEntries - 1);  
		END HasNext;					
		
	END Cluster; 
	
TYPE
	
	PathName = POINTER TO RECORD
		name : POINTER TO ARRAY OF CHAR;
		next : PathName;
	END;
	
	Path = OBJECT
	VAR
		head : PathName;
		prefix : AosFS.Prefix;
			
		PROCEDURE &Init(prefix : AosFS.Prefix);
		BEGIN
			NEW(head); head.next:=NIL;
			SELF.prefix := prefix; (* prefix of the mounted volume *)
		END Init;
		
		PROCEDURE Append*(dirname : ARRAY OF CHAR);
		VAR temp, new : PathName; i : INTEGER;
		BEGIN
			NEW(new); NEW(new.name,LEN(dirname));
			i:=0;
			WHILE i<LEN(dirname) DO 
				IF dirname[i]#" " THEN new.name[i] :=dirname[i];END;
				INC(i);
			END;
			temp:=head; WHILE temp.next#NIL DO temp:=temp.next; END;
			temp.next:=new;
		END Append;
		
		PROCEDURE RemoveLast*;
		VAR temp : PathName;
		BEGIN
			ASSERT(head.next#NIL);
			temp:=head; WHILE(temp.next.next#NIL) DO temp:=temp.next; END;
			temp.next:=NIL; (* last node removed *)
		END RemoveLast;
		
		(* get the current path as string *)
		PROCEDURE Get() : ARRAY OF CHAR;
		VAR
			temp : PathName;
			writer : AosIO.StringWriter;
			result : ARRAY 256 OF CHAR;
		BEGIN
			NEW(writer, 2048);
			temp := head;
			writer.String(prefix);
			writer.String(":");
			WHILE (temp.next#NIL) DO
				temp := temp.next;
				writer.String(temp.name^);
				writer.String(AosFS.PathDelimiter);
			END;
			writer.Get(result);
			RETURN result;
		END Get;
		
		PROCEDURE Print*;
		VAR temp : PathName;
		BEGIN
			ASSERT(head.next#NIL);
			AosOut.String(prefix); AosOut.String(":");
			temp:=head;
			WHILE(temp.next#NIL) DO
				temp:=temp.next;
				AosOut.String(temp.name^); AosOut.String(AosFS.PathDelimiter);
			END;
			AosOut.Ln;
		END Print;
	END Path;
	
	LostCluster = POINTER TO RECORD
		cluster, link : LONGINT;
		next : LostCluster;
		chain : LostCluster;
		terminated, crosslink : BOOLEAN;
	END;
	
	ClusterList = OBJECT
	VAR
		head, tail, previous, current : LostCluster;
		size : LONGINT;
		currentDeleted : BOOLEAN;
	
		(* can be used to reset list *)
		PROCEDURE &Init*; 
		BEGIN
			IF(head=NIL) THEN NEW(head); END;
			head.next:=NIL; tail:=NIL;
			previous:=head; current:=head;
			size:=0; currentDeleted:=FALSE;
		END Init;
		
		PROCEDURE Insert*(lost : LostCluster);				
		BEGIN
			IF head.next=NIL THEN 
				lost.next:=NIL;
				head.next:=lost; tail:=lost; 
			ELSE
				lost.next:=head.next;
				head.next:=lost;
			END;
			INC(size);
		END Insert;
		
		PROCEDURE Append*(lost : LostCluster);
		BEGIN
			lost.next:=NIL;
			IF head.next=NIL THEN
				head.next:=lost; tail:=lost;
			ELSE
				tail.next:=lost; tail:=lost;
			END;
			INC(size);
		END Append;
		
		PROCEDURE SetCurrent*;
		BEGIN
			current:=head; previous:=head;
		END SetCurrent;
		
		PROCEDURE GetNext(): LostCluster;
		BEGIN
			ASSERT((head.next#NIL) & (current#NIL));
			IF currentDeleted THEN  
				currentDeleted:=FALSE; 
				current:=previous.next;
			ELSE	
				previous:=current;
				current:=current.next;
			END;
			RETURN current;
		END GetNext;
		
		PROCEDURE HasNext():BOOLEAN;
		BEGIN
			RETURN current.next#NIL;
		END HasNext;
		
		PROCEDURE RemoveCurrent; (* continuing iteration via GetNext() and HasNext() is allowed *)
		BEGIN
			ASSERT((current#NIL) & (previous#NIL) & ~Empty() & (current#head));
			IF current=tail THEN tail:=previous; END;
			previous.next:=current.next;
			currentDeleted:=TRUE;
			DEC(size);
		END RemoveCurrent;
		
		PROCEDURE Empty():BOOLEAN;
		BEGIN
			RETURN head.next=NIL;
		END Empty;
		
		PROCEDURE Print*;
		VAR
			temp : LostCluster;
		BEGIN
			temp:=head;
			AosOut.String("*** lost cluster list ***"); AosOut.Ln;
			WHILE temp.next#NIL DO 
				temp:=temp.next; 
				AosOut.Int(temp.cluster,10); AosOut.Int(temp.link,10); AosOut.Ln;
			END;
	   END Print;
	END ClusterList;
	
TYPE

	FATScavenger*=  OBJECT(AosPartitionsLib.Operation);
	VAR
		(* parameters: operations to be done *)
		doSurfaceScan, doCompareFATs, doLostClusters, doWrite : BOOLEAN;
		
		(* popup window *)
		popup : WMPartitions.PopupWindow;
		param : WMPartitions.Parameters;
		selection : WMPartitions.Selection;
		
		(* scavenger information *)
		filesScanned-, directoriesScanned- : LONGINT;
		longEntriesScanned-, shortEntriesScanned-, emptyEntriesScanned- : LONGINT;
		freeClusters-, badClusters-, lostClusters-, lostClusterChains- : LONGINT;
		(* fragmentation infos *)
		nbrFreeFragments : LONGINT;
		errorsFound: LONGINT; 
		ioError : BOOLEAN;
		
		curOp, maxOp : LONGINT;
		
		vol : AosFATVolumes.Volume; dev : AosDisks.Device;
		path : Path;
	
		cluster, baseCluster : Cluster;
		processStack : STACK;
		longList : LongEntryList;
		lostList, lostErrorList, fileList, xlinkedList : ClusterList;
	 
		fsType : LONGINT;
		FAT1216rootDir : Cluster;
		
		clusterBitmap : ClusterBitmap;
		
		(* fields of fsinfo block *)
		fsinfo : ARRAY AosFATVolumes.BS OF CHAR;
		fsinfoAddress : LONGINT;	
		fsInfoLoaded : BOOLEAN;
		
		(* external updated fields *)
		deleted : LONGINT;
		
		PROCEDURE SetParameters*(doSurfaceScan, doCompareFATs, doLostClusters, doWrite : BOOLEAN);
		BEGIN
			SELF.doSurfaceScan := doSurfaceScan; SELF.doCompareFATs := doCompareFATs; SELF.doLostClusters := doLostClusters;
			SELF.doWrite := doWrite;
			IF doWrite THEN locktype := AosPartitionsLib.WriterLock ELSE locktype := AosPartitionsLib.ReaderLock; END;
			curOp := 0; maxOp := 1; 
			IF doSurfaceScan THEN INC(maxOp); END; IF doCompareFATs THEN INC(maxOp); END;
			IF doLostClusters THEN INC(maxOp); END;
		END SetParameters;
		
		PROCEDURE ValidParameters*() : BOOLEAN;
		BEGIN
			dev := disk.device;
			IF dev = NIL THEN ReportError("Could not access device"); RETURN FALSE; END;
			IF ~AosPartitionsLib.IsFatType(disk.table[partition].type) & ~disk.isDiskette THEN
				ReportError("Scavenger only supports FAT formatted partitions"); RETURN FALSE; 
			END;
			RETURN TRUE;
		END ValidParameters;
		
		PROCEDURE DoOperation*;
		VAR
			string, str : String; 
			collision : BOOLEAN;  
			vdf, clnShutdown, ioError : SET; (* Volume dirty flags (FAT16/32) *)
			bpb : Block;
			res : LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("FATScavenger started on "); END;
			SetStatus(state.status, "Scavenger starting...", 0, 0, 0, FALSE);
			
			(* Get FAT volume *)
			dev.Transfer(AosDisks.Read, disk.table[partition].start, 1, bpb, 0, res);
			IF res # AosDisks.Ok THEN
				ReportError(AosPartitionsLib.GetErrorMsg("Could not load boot sectors", res));
				RETURN;
			END;
			
			vol := GetVolume(dev, partition, bpb);
			IF vol = NIL THEN
				ReportError("Could not get FAT volume");
				RETURN;
			ELSE
				info.String("FAT volume type: ");
				IF vol IS AosFATVolumes.FAT12Volume THEN 
					fsType := FAT12; info.String("FAT12"); 
				ELSIF vol IS AosFATVolumes.FAT16Volume THEN 
					fsType := FAT16; info.String("FAT16");
				ELSIF vol IS AosFATVolumes.FAT32Volume THEN 
					fsType := FAT32; info.String("FAT32");
				ELSE 
					ReportError("Only FAT12, FAT16 and FAT32 volumes are supported"); 
					info.String("No FAT (Error)");
					RETURN;
				END;
				info.Ln;			
			END;
				
			fsType2 := fsType;
	
			NEW(clusterBitmap, vol.maxClusters); NEW(cluster, vol.clusterSize);	 
			NEW(path, "");	
			
			(* evaluate volume dirty flags on FAT16/FAT32 volumes *)
			IF (fsType = FAT16) OR (fsType = FAT32) THEN
				vol.unsafe := TRUE;
				vdf := SYSTEM.VAL(SET, vol.ReadFATEntry(1));
				vol.unsafe := FALSE;
				
				IF fsType = FAT16 THEN
					clnShutdown := fat16CleanShutdown; ioError := fat16IOError; 
				ELSE
					clnShutdown := fat32CleanShutdown; ioError := fat32IOError; 
				END;
					
				IF vdf * ioError # ioError THEN (* I/O error *)
					info.String("Device reports I/O error"); info.Ln;
					IF ~doSurfaceScan THEN
						NEW(popup, 200, 100, FALSE); param := NIL;
						popup.SetTextAsString("Device reports I/O errors. A surface scan is recommended. Do surface scan? ");
						selection.disk := disk; selection.partition := partition;
						popup.SetParameters("Do surface scan on ", selection, param);
						popup.Popup(100, 100, res);
						IF res = WMPartitions.ResOk THEN 
							doSurfaceScan := TRUE; (* will be done later *)
						END;
					END;
				END;
				
				IF vdf * clnShutdown # clnShutdown THEN (* volume has not been unmounted properly *)
					info.String("The volume has not been properly unmounted last time"); info.Ln;
				END;
				
				(* write back the volume dirty flags *)
				IF doWrite THEN 
					IF vdf * (clnShutdown + ioError) # (clnShutdown + ioError) THEN 
						vdf := vdf + clnShutdown + ioError;
						vol.unsafe := TRUE;
						vol.WriteFATEntry(1, SYSTEM.VAL(LONGINT, vdf), res);
						vol.unsafe := FALSE;
						IF res # AosDisks.Ok THEN
							ReportError(AosPartitionsLib.GetErrorMsg("Could not write back volume dirty flags ", res));
						ELSE
							info.String("Corrected: Cleared volume dirty flag"); info.Ln;
						END;
					END;
				END;
			END;
			
			(* scan the disk surface for BAD clusters *)
			IF alive & doSurfaceScan THEN SurfaceScan; END;
			
			(* compare all FATs *)
			IF alive & doCompareFATs THEN CompareFATs; END;
			
			IF alive THEN 
				(* setup data structures for ProcessHead *)
				(* load root cluster *)
				CASE fsType OF 
						
					 FAT12..FAT16: BEGIN 
					   					(* load root directory into memory. Requires a maximum of 2MByte *)
					   					NEW(FAT1216rootDir,vol(AosFATVolumes.FAT1216Volume).numRootSectors*AosFATVolumes.BS);
					   					ASSERT(FAT1216rootDir#NIL);
			             						dev.Transfer(AosDisks.Read, vol.start + vol(AosFATVolumes.FAT1216Volume).firstRootSector, 
			             						vol(AosFATVolumes.FAT1216Volume).numRootSectors, FAT1216rootDir.data^,0,res);
			             						IF res # AosDisks.Ok THEN 
			             							ReportTransferError("Critical: Couldn't load FAT1216 root directoy", 
			             							AosDisks.Read, vol.start + vol(AosFATVolumes.FAT1216Volume).firstRootSector, res);
			             							alive := FALSE; 
			             						END;
										baseCluster := cluster; (* I don't want the cluster to be collected *)
										cluster := FAT1216rootDir;
										cluster.next := EOC; 
										cluster.first := 1; cluster.parent := 1; cluster.cluster := 1;  (* used to identify FAT1216rootDir *)
									END;
				
					| FAT32: 		BEGIN
										cluster.cluster := vol(AosFATVolumes.FAT32Volume).rootCluster;
										vol(AosFATVolumes.FAT32Volume).ReadCluster(cluster.cluster, cluster.data^, res);
										IF res # AosDisks.Ok THEN 
			             							ReportError(AosPartitionsLib.GetErrorMsg("Critical: Couldn't load FAT32 root directory, res:", res));
			             							alive := FALSE; 
			             						END;
										cluster.first := cluster.cluster;
										clusterBitmap.SetBit(cluster.cluster, collision); (* collision is not possible, ignore *)
									 END;
				END;
		
				cluster.SetPos(0); processStack.PushCluster(cluster);
				path.Append(AosFS.PathDelimiter); (* root directory path string*)
			
				(* traverse the FAT directory structure *)
				IF alive THEN ProcessHead; END;
			END;
			
			(* check clusterbitmap for lost clusters *)
			IF alive & doLostClusters THEN 
				NEW(lostList); NEW(lostErrorList);
		
				TraverseFAT;
			
				IF ~lostList.Empty() & alive THEN (* lost clusters were found... analyze them !! *) 
					CheckLostClusters;  
					IF doWrite & alive THEN 
						NEW(popup, 200, 200, FALSE); param := NIL;
						string := "Found "; Utilities.IntToStr(lostClusters, str); Utilities.Append(string, str); 
						Utilities.Append(string, " lost cluster in "); Utilities.IntToStr(lostClusterChains, str);
						Utilities.Append(string, str); Utilities.Append(string, " chains. Delete lost cluster chains?");
						popup.SetTextAsString(string);
						selection.disk := disk; selection.partition := partition;
						popup.SetParameters("Delete lost clusters on ", selection, param);
						popup.Popup(100, 100, res);
						IF res = WMPartitions.ResOk THEN 
							DeleteLostClusters; (* WARNING: WRITE ACCESS *) 
						END;
					END;
				END;
			END;
		
			IF alive THEN 
				result.String("Scavenger on "); result.String(diskpartString); result.String(" finished ");
				IF state.status * AosPartitionsLib.StatusError = {} THEN
					result.String("without errors");
				ELSE
					result.String("width "); result.Int(state.errorCount, 0); result.String(" errors");
				END;		   	
				BuildInfo;
	          	END;
			IF Trace THEN IF ~alive THEN AosOut.String("Scanner aborted."); ELSE AosOut.String("Scanner finished."); AosOut.Ln; END; END;
		END DoOperation;
		
		PROCEDURE &Init(disk : AosPartitionsLib.Disk; partition : LONGINT; log : BOOLEAN);
		BEGIN
			Init^(disk, partition, log);
			name := "FATScavenger"; desc := "Scavenger for FAT file systems"; locktype := AosPartitionsLib.WriterLock;
			NEW(longList); NEW(processStack); NEW(xlinkedList);			
		END Init;
		
		PROCEDURE BuildInfo;
		BEGIN
			info.String("Volume Information: "); info.String(diskpartString); info.Ln;
			info.String("Clusters: "); info.Int(vol.maxClusters, 3); info.String(" ClusterSize: "); info.Int(vol.clusterSize, 3); info.String("B");
			info.Ln; 
			info.String("Files: "); info.Int(filesScanned, 3); info.String(" Directories: "); info.Int(directoriesScanned, 3);
			info.Ln;
			info.String("Short Entries: "); info.Int(shortEntriesScanned, 3);
			info.String(" Long Entries: "); info.Int(longEntriesScanned, 3);
			info.String(" Empty Entries: "); info.Int(emptyEntriesScanned, 3);
			info.Ln;
			IF errorsFound > 0 THEN 
				info.Int(lostClusters, 4); info.String(" lost clusters found in "); info.Int(lostClusterChains, 3); info.String(" chains."); info.Ln;
			END;
		END BuildInfo;
		
		PROCEDURE GetFSInfo(VAR freeCount, nextFree : LONGINT) : BOOLEAN;
		VAR
			bootsector : ARRAY AosFATVolumes.BS OF CHAR;
			res : LONGINT;
		BEGIN
			(* load the boot sector to get address of FSinfo block *)
			dev.Transfer(AosDisks.Read, vol.start, 1, bootsector, 0, res);
			IF res # OK THEN 
				ReportTransferError("Could not load FSinfo block (", AosDisks.Read, vol.start + vol.startFAT, res);
				RETURN FALSE; 
			END;
		
			(* Get address & FAT32 file system version check; version exspected to be 0:0;  *)
			IF (bootsector[42] # 0X) OR (bootsector[43] # 0X) THEN
				ReportError("Couldn't not load FSInfo block (Wrong FAT32 FS verion)");
				RETURN FALSE;
			END;
			fsinfoAddress := AosFATVolumes.GetUnsignedInteger(bootsector, 48);
		
			(* load the file system info block *)
			dev.Transfer(AosDisks.Read, vol.start + fsinfoAddress, 1, fsinfo, 0, res);
			IF res # OK THEN 
				ReportTransferError("Couldn't load FSinfo block (", AosDisks.Read, vol.start + fsinfoAddress, res);
				RETURN FALSE;
			END;
			
			(* get freeCount & nextFree information from FSinfo block *)
			IF (AosFATVolumes.GetLongint(fsinfo, 0) = 041615252H) & (* lead signature *)
				(AosFATVolumes.GetLongint(fsinfo, 508) = 0AA550000H) & (* structure signature *)
				(AosFATVolumes.GetLongint(fsinfo, 484) = 061417272H) (* trail signature *)
			THEN
				(* it's the FSinfo block *)
				fsInfoLoaded := TRUE;
				freeCount := AosFATVolumes.GetLongint(fsinfo, 488);
				nextFree := AosFATVolumes.GetLongint(fsinfo, 492);
			ELSE
				ReportError("Signature of FSinfo block if wrong"); 
				RETURN FALSE;
			END;
			RETURN TRUE;
		END GetFSInfo;
		
		PROCEDURE SetFSInfo(freeCount, nextFree : LONGINT);
		VAR res : LONGINT;
		BEGIN
			IF fsInfoLoaded THEN 
				AosFATVolumes.PutLongint(fsinfo, 488, freeCount); (* - deleted + created *)
				AosFATVolumes.PutLongint(fsinfo, 492, nextFree);
				IF doWrite THEN 
					dev.Transfer(AosDisks.Write, vol.start + fsinfoAddress, 1, fsinfo, 0, res);
					IF res # OK THEN 
						ReportTransferError("Could not store FSinfo block (", AosDisks.Write, vol.start+ fsinfoAddress, res);
					END;
				END;
			ELSE ReportError("FSinfo block is not loaded");
			END;
		END SetFSInfo;
			
		(* Compares the n FATs on the volume *)
		PROCEDURE CompareFATs;
		CONST UpdateRate = 3;
		VAR
			buffer : POINTER TO ARRAY OF CHAR; 
			buffersize, reads : LONGINT;
			operation : String;
			i, j, k, res : LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("Comparing FATs... "); END;
			INC(curOp); operation := GetString(curOp, maxOp, "", "Comparing FAT structures");
			SetStatus(state.status, operation, 0, 0, vol.fatSize, TRUE);
		
			(* allocate read buffer *)
			buffersize := BufferSize * AosFATVolumes.BS; (* buffersize: in bytes; BufferSize: number of sectors *)
			NEW(buffer, buffersize * vol.numFATs);
			ASSERT(buffer # NIL);
			
			(* reads*BufferSize*AosFATVolumes.BS + (vol.fatSize MOD BufferSize) bytes will be read from each FAT and then compared to FAT1 *)
			reads := vol.fatSize DIV BufferSize;
			k := 0;
			WHILE k < reads DO
			
				INC(k);
				(* special case: IF (fatSize DIV BufferSize) buffers are read, load & compare (fatSize MOD BufferSize) bytes *)
				IF (k = reads) & ((vol.fatSize MOD BufferSize) # 0) THEN
					buffersize := (vol.fatSize MOD BufferSize) * AosFATVolumes.BS; 
				END;
			
		   		(* read BufferSize sectors from each FAT *)
		   		FOR i := 0 TO vol.numFATs-1 DO
					dev.Transfer(AosDisks.Read, vol.start + vol.startFAT+ i*vol.fatSize, BufferSize, buffer^, i*buffersize, res);
					IF res # OK THEN 
						ReportTransferError("CompareFATs: IO error (", AosDisks.Read, vol.start + vol.startFAT+ i*vol.fatSize, res);
						(* continue *)
					END;
				END; 
				
				(* compare entries of numFATs FATs *)
				FOR i := 0 TO buffersize-1 DO 
					FOR j := 1 TO vol.numFATs-1 DO
						IF buffer[i + j*buffersize] # buffer[i] THEN 
							ReportError("CompareFATs: SERIOUS ERROR: File allocation tables are not equal");
							alive := FALSE; 
						END;
					END; 
				END; 
				
				IF (k MOD UpdateRate = 0) OR (k >= reads) THEN
					SetCurrentProgress(k * BufferSize);
				END;
				
				IF ~alive THEN IF Trace THEN AosOut.String("aborted."); AosOut.Ln; END; RETURN; END;
			END; 
			IF alive THEN info.String("Comparing FATs succeeded."); info.Ln; END;
			IF Trace & alive THEN AosOut.String("done."); AosOut.Ln;END;
		END CompareFATs;
		
		PROCEDURE TraverseFAT;
		CONST
			UpdateRate = 10000;
		VAR
			collision, lastFree : BOOLEAN;
			lost : LostCluster;
			cluster, link, firstFree : LONGINT;
			operation, string : String;
		BEGIN
			IF Trace THEN AosOut.String("Building up cluster bitmap... "); END;
			ASSERT((clusterBitmap # NIL) & (lostList # NIL));
			INC(curOp); operation := GetString(curOp, maxOp, "", "Analyzing FAT: ");
			string := operation; Utilities.Append(string,  GetString(0, vol.maxClusters+1, "Cluster", ""));
			SetStatus(state.status, string, 0, 0, vol.maxClusters, TRUE);
		
			lastFree := FALSE; firstFree := -1;
		 
			FOR cluster:=2 TO vol.maxClusters+1 DO
				
				link := vol.ReadFATEntry(cluster);
				
				CASE link OF
							 	  
					|FREE:	BEGIN 									
								IF firstFree=-1 THEN firstFree:=cluster; END;
								INC(freeClusters); 
								IF ~lastFree THEN INC(nbrFreeFragments); END;	
								lastFree:=TRUE;
							 END;
								   
					|BAD:	 BEGIN 
								lastFree:=FALSE;
								INC(badClusters);
								clusterBitmap.SetBit(cluster, collision);
								IF collision THEN (* ERROR: file contains bad cluster *)
									INC(errorsFound);
									collision := FALSE;
									info.String("Cannot fix: File contains bad cluster."); info.Ln;
									AosOut.String("error: bad cluster in file"); AosOut.Ln; (* TODO: fix *)
								END;
							 END;
				ELSE 
				
					lastFree := FALSE;
						
					IF ~clusterBitmap.IsSet(cluster) THEN (* ERROR: lost cluster found *)
						INC(errorsFound);
						NEW(lost); lost.cluster:=cluster; lost.link:=link;
						IF (link # EOC) & clusterBitmap.IsSet(link) THEN (* ERROR: lost cluster crosslinked to a valid cluster*)
							lostErrorList.Append(lost);
						ELSE
							lostList.Append(lost); 
						END; 
						INC(lostClusters);
					END;
				END;
				
				IF (cluster MOD UpdateRate = 0) OR (cluster = vol.maxClusters+1) THEN
					string := operation; Utilities.Append(string, GetString(cluster, vol.maxClusters+1, "Cluster", ""));
					SetStatus(state.status, string, 0, cluster - 1, state.max, TRUE);
				END;
					
				IF ~alive THEN IF Trace THEN AosOut.String("aborted."); END; RETURN; END;				
			END;
			
			(* check the free cluster count of the fsinfo field and the pointer to the first free cluster (FAT32 only) *)
			(* TODO: does not yet work correctly 
			 
			IF (vol IS AosFATVolumes.FAT32Volume) THEN
				ASSERT(fsinfo#NIL);
				IF fsinfo.freeCount#info.freeClusters THEN (* ERROR: wrong free cluster count in fsinfo block *)
					AosOut.String("ERROR: FSINFO wrong freecount"); AosOut.Ln;
					fsinfo.freeCount:=info.freeClusters; fsinfo.modified:=TRUE;
				END;
				IF fsinfo.nextFree#firstFree THEN (* ERROR: pointer to first free cluster of volume is wrong *)
					AosOut.String("ERROR: FSINFO wrong nextfree"); fsinfo.modified:=TRUE; AosOut.Ln;
					fsinfo.nextFree:=firstFree;
				END;
				IF doWrite THEN fsinfo.Store; END;  (* WARNING!! *****************);
				END;
			 *)
			IF Trace THEN AosOut.String("done."); AosOut.Ln; END;
		END TraverseFAT;

		PROCEDURE SurfaceScan;
		CONST
			UpdateRate = 99; 
		VAR
			data : ARRAY vol.clusterSize OF CHAR;
			newBadClusters, cluster, link : LONGINT;
			operation, string, temp : String;
			address : AosFS.Address;
			res : LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("Surface scan started..."); END;
			INC(curOp); operation := GetString(curOp, maxOp, "", "Surface scan: ");
			string := operation; Utilities.Append(string, GetString(0, vol.maxClusters, "Cluster", ""));
			SetStatus(state.status, string, 0, 0, vol.maxClusters, TRUE);

			newBadClusters := 0;  (* number of known bad clusters already in info.badClusters *)
			
			FOR cluster := 2 TO vol.maxClusters+1 DO
			
				link := vol.ReadFATEntry(cluster);
				address := vol.startData + (cluster * vol.sectorsPC);
				dev.Transfer(AosDisks.Read, address, vol.sectorsPC, data, 0, res);  
				IF res#OK THEN
					string := "Cluster "; Utilities.IntToStr(cluster, temp); Utilities.Append(string, temp); Utilities.Append(string, " is bad");
					Utilities.Append(string, AosPartitionsLib.GetErrorMsg(", res: ", res));
					ReportError(string);
					IF link#BAD THEN (* mark cluster as bad cluster *)
						IF link=FREE THEN INC(deleted); END;
						INC(newBadClusters);
		 	 			IF doWrite THEN vol.WriteFATEntry(cluster, BAD, res); 
							IF res # OK THEN 
								string := "Failed to mark cluster "; Utilities.Append(string, temp); Utilities.Append(string, " as bad");
								Utilities.Append(string, AosPartitionsLib.GetErrorMsg(", res: ", res));
								ReportError(string);
							ELSE
								string := "Cluster"; Utilities.Append(string, temp); Utilities.Append(string, " marked as bad");
								info.String(string); info.Ln;
							END;            
						END;
					END;
					(* continue *)
				END;
				
				IF (cluster MOD UpdateRate = 0) OR (cluster = vol.maxClusters+1) THEN 
					string := operation; Utilities.Append(string, GetString(cluster, vol.maxClusters+1, "Cluster", ""));
					SetStatus(state.status, string, 0, cluster, vol.maxClusters, TRUE);
				END;

				IF ~alive THEN IF Trace THEN AosOut.String("aborted."); AosOut.Ln; END; RETURN; END;
			END;
			info.String("Surface scan: "); info.Int(newBadClusters, 0); info.String(" bad sectors found."); info.Ln;
			IF Trace THEN AosOut.Int(newBadClusters,6); AosOut.String(" new bad sectors found...");AosOut.String("done."); AosOut.Ln; END;
		END SurfaceScan;
		
		PROCEDURE DeleteLostClusters;
		VAR
			temp, temp2 : LostCluster;
			string : String;
			counter, res : LONGINT;
		BEGIN	
			IF Trace THEN AosOut.String("Deleting lost clusters... "); END;
			ASSERT((lostErrorList#NIL) & (fileList#NIL));
			counter := 0;
			(* delete lost clusters which are crosslinked to valid clusters *)
			lostErrorList.SetCurrent;
			WHILE lostErrorList.HasNext() DO 
				temp := lostErrorList.GetNext();
				IF doWrite THEN vol.WriteFATEntry(temp.cluster, FREE, res); INC(counter); END; 
				IF res # OK THEN 
					string := ""; Utilities.Append(string, AosPartitionsLib.GetErrorMsg("Critical: Could not delete lost clusters (", res)); Utilities.Append(string, ")");
					ReportError(string);
					RETURN;
				END;		
			END;
			
			(* delete lost cluster chains *)
			fileList.SetCurrent;
			WHILE fileList.HasNext() DO
				temp := fileList.GetNext(); 
				IF doWrite THEN vol.WriteFATEntry(temp.cluster, FREE, res);  INC(counter); END;
				IF res # OK THEN 
					string := ""; Utilities.Append(string, AosPartitionsLib.GetErrorMsg("Critical2: Could not delete lost clusters (", res)); Utilities.Append(string, ")");
					ReportError(string);
					RETURN;
				END;		
			 	temp2 := temp.chain;
			    	WHILE temp2 # NIL DO 
			    		IF doWrite THEN vol.WriteFATEntry(temp2.cluster, FREE, res); INC(counter); END; 
					IF res # OK THEN 
						string := ""; Utilities.Append(string, AosPartitionsLib.GetErrorMsg("Critical3: Could not delete lost clusters (", res)); Utilities.Append(string, ")");
						ReportError(string);
						RETURN;
					END;		
			    		temp2 := temp2.next;
			    	END;
			END;
			
			(* update values in fsinfo block (FAT32only) *)
			IF vol IS AosFATVolumes.FAT32Volume THEN INC(deleted); END;
			
			info.Int(counter, 0); info.String(" lost clusters deleted"); info.Ln;
			IF Trace THEN AosOut.String("Deleted "); AosOut.Int(counter, 0); AosOut.String("clusters, done."); AosOut.Ln; END;
		END DeleteLostClusters;
		
		(* tries to find cluster chains in the lost cluster list *)
		PROCEDURE CheckLostClusters;
		VAR
			tempList : ClusterList;
			tempCluster, tempLink : LONGINT; (* address of the first cluster in list; link of the last cluster in list; *)
			lost, temp : LostCluster;
			found : BOOLEAN;
			xlink, collision, terminated: BOOLEAN;
		BEGIN
			IF Trace THEN AosOut.String("Processing lost cluster list... "); END;
			ASSERT(lostList#NIL);
			
			NEW(fileList); (* list of cluster chains *)
			NEW(tempList);   
			
			(* find cluster chains in lost cluster list *)
			WHILE ~lostList.Empty() DO		
					found:=TRUE;
					
					WHILE found=TRUE DO
						lostList.SetCurrent;
						found:=FALSE;
		
								WHILE(lostList.HasNext()) DO
									lost:=lostList.GetNext();
									
									IF tempList.Empty() THEN 
										lostList.RemoveCurrent; lost.next:=NIL;
										tempList.Insert(lost); 
										tempCluster:=lost.cluster; tempLink:=lost.link;
										found:=TRUE;
									END;
									
									IF lost.cluster=tempLink THEN (* last cluster of tempList linked to this one -> append cluster to cluster chain *)
										lostList.RemoveCurrent; lost.next:=NIL;
										tempList.Append(lost);
										tempLink:=lost.link;
										found:=TRUE;
									ELSIF lost.link=tempCluster THEN (* linked to first cluster of tempList -> insert cluster into cluster chain *)
										lostList.RemoveCurrent; lost.next:=NIL;
										tempList.Insert(lost);
										tempCluster:=lost.cluster;
										found:=TRUE;
									END;
								END;
					END;
					
					IF found=FALSE THEN (* no more clusters of lostList belong to currently processed cluster chain *)
		
						(* store found cluster chain in file list *)
						tempList.SetCurrent;
						ASSERT(~tempList.Empty()); 
						lost:=tempList.GetNext(); (* first element of tempList *)
						lost.chain:=lost.next; lost.next:=NIL;
						fileList.Append(lost);
						fileList.SetCurrent;
						lost:=fileList.GetNext();
						tempList.Init;  (* clear list *)		
					END;			
			END;
			(* check lost cluster chains againt crosslinks to other lost cluster chains. Crosslinks to valid cluster were already
				checked in TraverseFAT.  
				check also wether the lost cluster chains are terminated with EOC *)
			
			fileList.SetCurrent;
			WHILE fileList.HasNext() DO (* for each lost cluster chain... *)
				lost:=fileList.GetNext();
				clusterBitmap.SetBit(lost.cluster,collision); xlink:=collision; terminated:=(lost.chain=NIL) & (lost.link=EOC);
				temp:=lost.chain;
				WHILE(temp#NIL) DO (* ... and each lost cluster of that chains *)
					clusterBitmap.SetBit(temp.cluster, collision); 
					IF collision THEN xlink:=TRUE; END;
					IF (temp.next=NIL) & (temp.link=EOC) THEN terminated:=TRUE; END;
					temp:=temp.next;
				END;
				lost.terminated:=terminated;
				lost.crosslink:=xlink;
			END;
	
			lostClusterChains := fileList.size;		  	
			IF Trace THEN AosOut.String(" done."); AosOut.Ln; END;
		END CheckLostClusters;
		
		(* check the long entries which are associated with this shortentry; FIX: delete incorrect entries *)
		PROCEDURE CheckLongEntries(shortEntry : ShortEntry);
		VAR
			chksum : LONGINT;
			temp : LongEntry;
			order : INTEGER;
			longName : ARRAY 256 OF CHAR;  (*  maximum length of a long file name: 255 characters + NUL *)
			unicode : ARRAY 256 OF LONGINT;
			lastFound : BOOLEAN;
			padding : BOOLEAN; firstPadding : INTEGER;
			i : INTEGER;
		BEGIN
			IF Details THEN AosOut.String("CheckLongEntries of "); AosOut.String(shortEntry.shortName); AosOut.String("..."); END;
			chksum := shortEntry.GetChecksum(); order := 0; lastFound := FALSE;
			
			longList.SetCurrent();
						
			WHILE (longList.HasNext()) & (order<20) & (~lastFound) DO (* no more than 20 long entires *)
				INC(order);
				temp:=longList.GetNext();
				
				IF temp.order#order THEN (* ERROR: wrong sequence number *)  
					AosOut.String("Cannot fix: Long entry order mismatch"); AosOut.Ln; (* TODO: fix *)
					info.String("Cannot fix: Long entry order mismatch."); info.Ln;
				END;
			
				IF temp.chksum#chksum THEN (* ERROR: checksum doesn't match *) 
					AosOut.String("Cannot fix: Long entry chksum mismatch"); AosOut.Ln;  (* TODO: fix *)
					info.String("Cannot fix: Long enty chksum mismatch."); info.Ln;
				END;
				
		   	 	FOR i:=0 TO 12 DO unicode[(order-1)*13+i]:=temp.name[i]; END; 
				IF temp.last THEN lastFound:=TRUE; unicode[order*13]:=0; END; 
				
			END;
	
	  		IF (order#0) & (~lastFound) THEN (* ERROR: wrong long entries *) 
	  			AosOut.String("Cannot fix: Last entry of long entry sequence not found."); AosOut.Ln; (* TODO: fix *)
	  			info.String("Cannot fix: Last entry of long entry sequence not found."); info.Ln;
			ELSE (* okay: got long name. Is it valid ? *)
			
					UTF8Strings.UnicodetoUTF8(unicode,longName);
				 
					 (* check padding *)
				    	padding:=FALSE; firstPadding:=0;
				    	FOR i:=0 TO order*13-1 DO
						IF (padding=TRUE) &  (unicode[i]#0FFFFH) THEN (* ERROR: padding with 0FFFFH not correct *)
							AosOut.String("Cannot fix: Incorrect padding in long entry."); AosOut.Ln;  (* TODO: fix *);
							info.String("Cannot fix: Incorrect padding in long entry.");  info.Ln;
						END;
						IF (unicode[i]=0) & (padding=FALSE) THEN padding:=TRUE; firstPadding:=i;END;
					END;
				
					(* check characters*)
					IF firstPadding=0 THEN firstPadding:=order*13-1; END;
					FOR i:=0 TO firstPadding-1 DO 
						IF ~ValidLongChar(longName[i]) THEN (* invalid char in long name *)
							AosOut.String("Cannot fix: Invalid char in long name"); AosOut.Ln; (* TODO: fix *)
							info.String("Cannot fix: Invalid char in long name."); info.Ln;
						END;
					END;
			END; 
			IF longList.HasNext() THEN (* error: the remaining long entries have no correspondig short entry *)
				AosOut.String("Cannot fix: Remaing long entries are orphans"); AosOut.Ln; (* TODO: fix *)
				info.String("Cannot fix: Remaining long entries are orphans."); info.Ln;
			END;
						
			longList.Clear(); (* remove long entries from list *)	
			IF Details THEN AosOut.String(" done."); AosOut.Ln; END;
		END CheckLongEntries;
	
		PROCEDURE CheckDotDot(shortEntry : ShortEntry);
		VAR 
			rootDir : LONGINT;
		BEGIN
			(* possible input shortEntrys are all which satisfy shortEntry.shortName[0]="." *)
			ASSERT(shortEntry.shortName[0]=".");
			
			IF shortEntry.shortName=".          " THEN 
		 		IF shortEntry.firstCluster#cluster.first THEN (* ERROR: dot entry does not point to this directory *)
					AosOut.String("Cannot fix: dot entry points wrong."); AosOut.Ln; (* TODO: fix *) 
					info.String("Cannot fix: Dot entry points wrong."); info.Ln;
				END;			
			ELSIF shortEntry.shortName="..         " THEN 
				IF shortEntry.firstCluster=0 THEN (* parent is rootDirectory *)
					CASE fsType OF
						FAT12..FAT16 : rootDir:=1;
						|FAT32 : rootDir:=vol(AosFATVolumes.FAT32Volume).rootCluster;
					END;
					
					IF cluster.parent#rootDir THEN (* ERROR: dot dot points to rootDir but shouldn't *)
						AosOut.String("Warning: dot dot points to root but should not"); (* TODO: fix *)
						info.String("Cannot fix: Dot dot point to root but should not."); info.Ln;
					END;
				
				ELSIF shortEntry.firstCluster#cluster.parent THEN (* ERROR: dot dot entry doesn't point to parent folder *)
					AosOut.String("ERROR: dot dot entry points wrong:"); AosOut.Int(shortEntry.firstCluster,10);
					AosOut.String(" parent is :"); AosOut.Int(cluster.parent,10); AosOut.Ln; 
					info.String("Cannot fix: Dot dot entry wrong."); info.Ln;
				END;
			ELSE
				(* ERROR: this is no valid dot entry; Invalid shortEntry or invalid short name *)
				AosOut.String("Cannot fix: Invalid shortEntry (starts with .)"); AosOut.Ln; (* TODO: fix *)
				info.String("Cannot fix: Invalid short entry (name starts with . )"); info.Ln;
			END;
		END CheckDotDot;
		
		PROCEDURE ProcessShortEntry(shortEntry: ShortEntry);
		VAR
			counter : SHORTINT;
			clusterCount : LONGINT;
			link, oldlink : LONGINT;
			fragments : LONGINT;
			collision : BOOLEAN;
			xlinked : LostCluster;
		BEGIN
			(* the input shortEntry is either a file, a VolumeID or a invalid shortEntry *)
			IF Details THEN shortEntry.Print; END;
			(* check whether the short name is valid *)
			FOR counter := 0 TO 10 DO
				IF ~ValidShortChar(shortEntry.shortName[counter]) THEN (* ERROR: invalid short name *) 	
					AosOut.String("Invalid short name: "); AosOut.String(shortEntry.shortName);  AosOut.Ln;
					info.String("Invalid short name: "); info.String(shortEntry.shortName); info.Ln;
				END;
			END;
		
			IF AosFATFiles.faVolumeID IN shortEntry.attr THEN (* it's a VolumeID *)
				DEC(filesScanned);  (* already counted in ProcessHead *)
			ELSE (* it's a file *)
				(* check the corresponding long entries *)
				CheckLongEntries(shortEntry);
			
					(* check cluster chain against fileSize *)
					fragments:=1; collision:=FALSE;
					clusterCount:=1; link:=shortEntry.firstCluster; 
					WHILE (link>1) & ((clusterCount-1)*vol.clusterSize<=shortEntry.fileSize) DO            
						oldlink:=link;
						link:=vol.ReadFATEntry(link);
						INC(clusterCount);
						IF link#oldlink+1 THEN INC(fragments); END;
						
						clusterBitmap.SetBit(oldlink, collision); ASSERT(collision=FALSE);
						IF collision THEN (* ERROR : crosslinked files *)
							collision:=FALSE; AosOut.String("Warning: PSE:crosslink detected!"); AosOut.Ln;
							NEW(xlinked); xlinked.cluster:=oldlink; xlinked.link:=link;
							xlinkedList.Append(xlinked);
						END;
						
					END; 
					
					(*inffo.FileFrag(fragments, clusterCount); *)
			
					IF (shortEntry.fileSize>0) & (link#EOC) THEN (* ERROR: file size wrong *)
						AosOut.String("Cannot fix: Wrong file size"); (* TODO: fix *)
						info.String("Cannot fix: Wrong file size: "); info.String(shortEntry.shortName); info.Ln;
					END; 
			END;
		END ProcessShortEntry;
		
		PROCEDURE ProcessHead*;
		VAR
			temp: Node;
			operation, string, tempStr : String;
			entry : Entry; shortEntry : ShortEntry;
			dirFragments, dirClusters : LONGINT;
			collision : BOOLEAN;
			res : LONGINT;
		BEGIN
			IF Trace THEN AosOut.String("Scanning FAT directory structure... "); END;
			INC(curOp); operation := GetString(curOp, maxOp, "", "Scanning FAT directory: ");  
			string := operation; Utilities.Append(string, path.Get());
			SetStatus(state.status, string, 0, 0, 0, FALSE);
			
			dirFragments:=1; dirClusters:=1;
			
			WHILE(~processStack.Empty()) DO
			
				IF ~alive THEN IF Trace THEN AosOut.String("aborted."); AosOut.Ln; END; RETURN; END;
				
				(* get next Node to process *)
				temp:=processStack.GetTop();      
				
			    (* special case: get FAT1216rootDir object if it's the next cluster to be processed *)
			    IF (fsType<=FAT16) & (temp.cluster=1) & (temp.parent=1) & (temp.first=1) THEN 
			    	cluster.cluster:=1; (* invalid address invalidates the old cluster object (forces reload) *)
			    	cluster:=FAT1216rootDir;
			    END;
			    
			    (* reload cluster if necessary *)
			    IF cluster.cluster # temp.cluster THEN
					IF Details THEN 
						AosOut.String("(re)load cluster: "); AosOut.Int(temp.cluster,8); AosOut.String("  offset: "); AosOut.Int(temp.offset,4); AosOut.Ln;
					END;
					ASSERT(temp.cluster>1);
					vol.ReadCluster(temp.cluster, cluster.data^, res);   
					IF res#OK THEN 
						string := "ProcessHead: Could not read cluster "; Utilities.IntToStr(temp.cluster, tempStr); Utilities.Append(string, tempStr);
						Utilities.Append(string, AosPartitionsLib.GetErrorMsg(" (res: ", res));
						ReportError(string);
						AosOut.String(" load failed!!"); (* to do: fix *) 
					END;
					cluster.cluster:=temp.cluster;
					cluster.first:=temp.first;
					cluster.parent:=temp.parent;
					cluster.SetPos(temp.offset);   
				END;
				
				IF (cluster.HasNext()) THEN 
							entry:=cluster.GetNext();
		
							IF entry#NIL THEN  (* entry not free *)
							(* entry.Print; *)
		
									IF (entry IS LongEntry) THEN (* long directory entry, push it on stack *)
									
											INC(longEntriesScanned);
											longList.Insert(entry(LongEntry));

									ELSE (* short entry *)
									
											INC(shortEntriesScanned);
											shortEntry:=entry(ShortEntry);
										
											IF (shortEntry.directory=FALSE)  THEN (* file, volumeID or invalid entry *)
		
												ProcessShortEntry(shortEntry); 
				 				   				INC(filesScanned); 
			 			   	
											ELSE  (* if it's a folder, it will be "opened" and processed as next *)
							
											    	IF (shortEntry.shortName[0]=".")  THEN   (* dot or dotdot or invalid entry *)
									    				CheckDotDot(shortEntry);
									   		 	ELSE
													path.Append(shortEntry.shortName);
													string := operation; Utilities.Append(string, path.Get());
													SetStatus(state.status, string, 0, 0, 0, FALSE);
		
													CheckLongEntries(shortEntry);
													IF Details THEN 
														AosOut.String("open directory "); AosOut.String(entry(ShortEntry).shortName); AosOut.Ln; path.Print;
													END;
		          				      	        	    			INC(dirClusters); INC(dirFragments); INC(directoriesScanned);
													processStack.ReplaceTop(cluster); (* save state of currently processed cluster object, will continue later at stored offset *)
								
													NEW(temp); temp.cluster:=entry(ShortEntry).firstCluster; temp.offset:=0; 
													temp.parent:=cluster.first; temp.first:=temp.cluster;
												
													IF cluster=FAT1216rootDir THEN (* need normal cluster object for processing entry *)
														cluster:=baseCluster; 
														cluster.cluster:=1; (* invalid address forces reloading ! *)
													END;
												
													clusterBitmap.SetBit(temp.cluster, collision);
													processStack.Push(temp); 
												
												END;
											
											END;  
									END;
							ELSE (* entry is free *)	
								INC(emptyEntriesScanned);
								(*	processStack.ReplaceTop(cluster); (* updates the Node.offset fields which was changed by temp:=cluster.GetNext() *) *)
							END;
					  
				ELSE (* all entries in this cluster were scanned. If this was not the last cluster in the cluster chain, load the next! *)
			
					ASSERT(cluster.currentEntry=cluster.maxEntries);
					processStack.RemoveTop; (* cluster completely scanned -> remove from process list*)
	
					(* get address of next cluster; FAT1216rootDir.next is always set to EOC *)
					IF cluster # FAT1216rootDir THEN cluster.next := vol.ReadFATEntry(cluster.cluster); END;

					IF  (cluster.next # EOC) & (cluster.next # FREE) & (cluster.next # BAD) THEN 
						(* next directory entry contained in next cluster *)
						INC(dirClusters);
						IF cluster.next # cluster.cluster+1 THEN INC(dirFragments);END;

						NEW(temp);  
						temp.cluster:=cluster.next; temp.offset:=0; 
						temp.first:=cluster.first; temp.parent:=cluster.parent;
						processStack.Push(temp); (* process this cluster as next *)
						
						clusterBitmap.SetBit(temp.cluster,collision);
					ELSE
						path.RemoveLast; 
       				END;
		   		END;
			END;
			IF Trace THEN AosOut.String(" done."); AosOut.Ln; END;
		END ProcessHead;
	
		PROCEDURE WriteEntry(entry: Entry);
		VAR
			temp : Cluster;
			temp2 : Entry;
			test : BOOLEAN;
			address : AosFS.Address;
			offset, res : LONGINT;
		BEGIN
			ASSERT((entry # NIL) & (vol # NIL) & (dev # NIL));
			test:=TRUE;
			(* Reload cluster if necessary*)
			IF cluster.cluster # entry.cluster THEN
				IF (vol IS AosFATVolumes.FAT1216Volume) &  (entry.cluster=1) THEN (* special case: FAT1216 root directory *)
					ASSERT(FAT1216rootDir#NIL); cluster:=FAT1216rootDir;
				ELSE
					(* normal cluster, load with vol.ReadCluster() *)
					vol.ReadCluster(entry.cluster, temp.data^, res);  (* ignore res, handled in AosFATVolumes *)
				END;
			END;
			
			(* optional: check correctness of cluster *)            (* do it *)
			temp.SetPos(entry.offset);
			ASSERT(cluster.HasNext());
			temp2:=cluster.GetNext();
			ASSERT(Equals(temp2.rawEntry, entry.rawEntry));  
			
		(*	cluster.ReplaceEntry(entry); *)
			
			(* determine address of the sector which contains the entry *)
			IF (fsType <= FAT16) & (entry.cluster = 1) THEN (* special case: FAT1216 root directory *)
				address := vol.startData + vol(AosFATVolumes.FAT1216Volume).firstRootSector + (entry.offset DIV SectorSize);
				offset := entry.offset MOD SectorSize;
			ELSE
				address := vol.startData+ (entry.cluster*vol.sectorsPC) + (entry.offset DIV SectorSize);   (* sectorsize consistent with FATVoluemes!!!!!*)
				offset := entry.offset MOD SectorSize;
			END;
			ASSERT( (address>vol.endFAT) & (address<(vol.maxClusters+1)*vol.sectorsPC));

			(* write cluster back to disk *)
			IF doWrite THEN vol.WriteCluster(entry.cluster, cluster.data^, res); END;			
		END WriteEntry;
	
		(* helper procedures *)
		
		(* string := [unit " "] cur "of" max [": " status] *)
		PROCEDURE GetString(cur, max : LONGINT; unit, status : ARRAY OF CHAR) :  String;
		VAR string : String; temp : ARRAY 16 OF CHAR;
		BEGIN
			string := ""; 
			IF unit#"" THEN Utilities.Append(string, unit); Utilities.Append(string, " "); END;
			Utilities.IntToStr(cur, temp); Utilities.Append(string, temp); Utilities.Append(string, " of ");
			Utilities.IntToStr(max, temp); Utilities.Append(string, temp); 
			IF status#"" THEN Utilities.Append(string, ": "); Utilities.Append(string, status); END;
			RETURN string;
		END GetString;
		
		PROCEDURE ReportTransferError(name : ARRAY OF CHAR; op, adr, res : LONGINT);
		BEGIN
			Utilities.Append(name, " (");
			Utilities.Append(name, AosPartitionsLib.GetTransferError(dev, op, adr, res)); 
			Utilities.Append(name, ")"); 
			ioError := TRUE; ReportError(name);
		END ReportTransferError;
		
		PROCEDURE ValidShortChar(ch : CHAR): BOOLEAN;
		BEGIN
		RETURN ((ch>=020X) & (ch#022X) & (ch#02AX) & (ch#02BX) & (ch#02CX) & (ch#02EX) & (ch#02FX) & (ch#03AX) &
				(ch#03BX) & (ch#03CX) & (ch#03DX) & (ch#03EX) & (ch#03FX) & (ch#05BX) & (ch#05CX) & (ch#05DX) & (ch#07CX));	
		END ValidShortChar;		

		PROCEDURE ValidLongChar(ch: CHAR): BOOLEAN;
		BEGIN
			RETURN (ch >= 20X) & (ch # "\") & (ch # "/") & (ch # ":") & (ch # "*") & (ch # "?") & (ch # '"') & (ch # "<") & (ch # ">") & (ch # "|");
		END ValidLongChar;

		(* compares the two arrays op1 and op2; returns TRUE if op1=op2 *)
		PROCEDURE Equals(op1, op2 : ARRAY OF CHAR): BOOLEAN;
		VAR
			i : LONGINT;
		BEGIN
			ASSERT( (LEN(op1)#0) & (LEN(op2)#0) );
			IF LEN(op1)#LEN(op2) THEN 
				RETURN FALSE; 
			ELSE 
				WHILE i < LEN(op1) DO
					IF op1[i]#op2[i] THEN RETURN FALSE; END;
				END;
				RETURN TRUE;
			END;
		END Equals;
				
	END FATScavenger;

TYPE
	
	(* Format a partition with a FAT file system *)
	FormatPartition* = OBJECT(AosPartitionsLib.Operation);
	VAR
		(* parameters: *)
		quickFormat : BOOLEAN; volumeName : Utilities.String;
	
		fs  : LONGINT; 
		(* internal values; Initialized to default values in Init *)
		oemName  : ARRAY 9 OF CHAR; 
		rsvdSecCnt1216, rsvdSecCnt32 : LONGINT; (* Reserved sector count *)
		numFATs : LONGINT;
		rootEntCnt : LONGINT; (* FAT1216: count of 32-byte directory entries in root directory *)
		fatsize : LONGINT; (* 16bit count of sectors occupied by one FAT *)
		volLab : ARRAY 12 OF CHAR; (* volume label *)
		rootCluster32 : LONGINT; (* FAT32 only: Cluster number of first cluster in root directory *)
		fsinfo : LONGINT; (* FAT32 only: Sector number of FSINFO structure in the reserved area *)
		backupBoot : LONGINT; (* FAT32 only: Sector number of copy of the boot record in reserved area *)
		
		(* quickFormat: IF TRUE, only FATs & root directory will be cleared *)
		PROCEDURE SetParameters*(volumeName : Utilities.String; quickFormat : BOOLEAN);
		BEGIN
			SELF.volumeName := volumeName; SELF.quickFormat := quickFormat; 
		END SetParameters;
		
		PROCEDURE ValidParameters*() : BOOLEAN;
		BEGIN
			IF disk.device.blockSize # BS THEN ReportError("Blocksize not supported"); RETURN FALSE END;
			IF ~AosPartitionsLib.IsFatType(disk.table[partition].type) & ~disk.isDiskette THEN 
				ReportError("Partition type is not FAT"); RETURN FALSE;
			END;
			RETURN TRUE;
		END ValidParameters;
	
		PROCEDURE DoOperation*; 
		VAR 
			vol : AosFATVolumes.Volume;
			block : Block;
			null : POINTER TO ARRAY OF CHAR;
			rootDirSectors, firstDataSector : LONGINT;
			freeCount, firstFree, media: LONGINT;
			spc, type : LONGINT; (* sectors per cluster *)
			i, res : LONGINT;
		BEGIN 
			type := disk.table[partition].type;
			IF (type = 1) OR disk.isDiskette THEN fs := FAT12; info.String("Formating FAT12 volume");
			ELSIF (type = 4) OR (type = 6) OR (type = 0EH)  THEN fs := FAT16; info.String("Formating FAT16 volume");
			ELSE fs := FAT32; info.String("Formating FAT32 volume");
			END;
		
			(* first calculate the sectors per cluster value *)
			SetStatus(state.status, "Formating...", 0, 0, 0, FALSE);
			spc := GetSectorPerCluster(disk.table[partition].size);
			info.String(" (clusterSize: "); info.Int(spc * disk.device.blockSize, 0); info.String("B)"); info.Ln;
			IF spc # -1 THEN 
				(* calculate the FAT size *)
				fatsize := GetFatSize(spc);
				
				(* build BIOS parameter block *)
				block := BuildBPB(spc);
				
				ASSERT((disk.table[partition].start#0) OR (disk.isDiskette)); (* protect MBR *)
				disk.device.Transfer(AosDisks.Write, disk.table[partition].start, 1, block, 0, res);
				IF res # AosDisks.Ok THEN 
					ReportError(AosPartitionsLib.GetErrorMsg("Format failed: Could not write boot sector", res));
				ELSE
					IF fs = FAT32 THEN 
						rootDirSectors := 0;
						firstDataSector := rsvdSecCnt32 + (numFATs * fatsize) + rootDirSectors;
					ELSE (* FAT12 or FAT16 *)
						rootDirSectors := ((rootEntCnt * 32) + (disk.device.blockSize -1)) DIV disk.device.blockSize;
						firstDataSector := rsvdSecCnt1216 + (numFATs * fatsize) + rootDirSectors;
					END;
					
					vol := GetVolume(disk.device, partition, block);
					IF vol#NIL THEN
			
						IF quickFormat THEN (* clear root directory and FATS only *)
							ClearSectors(2, firstDataSector -1);
							IF fs = FAT32 THEN (* also clear first cluster of root directory *)
								NEW(null, spc*disk.device.blockSize);
								FOR i := 0 TO LEN(null)-1 DO null[i] := 0X; END;
								vol.WriteCluster(rootCluster32, null^, res);
								IF res # AosDisks.Ok THEN
									ReportError(AosPartitionsLib.GetErrorMsg("Could not clear root cluster", res));
								END;
							END;
						ELSE
							ClearSectors(2, disk.table[partition].size - 1);
						END;
	
						vol.unsafe := TRUE; (* access to FAT[0]&FAT[1] needed *)
						(* set FAT[0] media byte (removable: 0F0H, else : 0F8H, all other bits are set to 1) *)
						IF AosDisks.Removable IN disk.device.flags THEN media := 0FFFFFF0H; ELSE media := 0FFFFFF8H; END;
						vol.WriteFATEntry(0, media, res);
						IF res # AosDisks.Ok THEN ReportError(AosPartitionsLib.GetErrorMsg("Could not set media byte", res)); END;
						
						(* set FAT[1] EOC mark *)
						vol.unsafe := TRUE;
						vol.WriteFATEntry(1, 0FFFFFFFFH, res);
						IF res # AosDisks.Ok THEN ReportError(AosPartitionsLib.GetErrorMsg("Could not set EOC mark", res)); END;
						vol.unsafe := FALSE; 
										
						IF fs = FAT32 THEN
							(* set the FAT entry of the first cluster of the root directory to EOC *)
							vol.unsafe := TRUE;
							vol.WriteFATEntry(rootCluster32, 0FFFFFFFH, res);
							vol.unsafe := FALSE;
							IF res # AosDisks.Ok THEN ReportError(AosPartitionsLib.GetErrorMsg("Could not set FAT entry of root cluster", res)); END;
							(* make sure that the cluster number 0x0FFFFFF7 is not used by the file system driver. This is because the
							value 0x0FFFFFF7 is used as BAD CLUSTER mark, so if a FAT entry contains this value, the cluster is 
							considered to be BAD. Only relevant for FAT32 volumes *)
							IF freeCount + 3 >= 0FFFFFF7H THEN
								vol.WriteFATEntry(0FFFFFF7H, 0FFFFFF7H, res);					
								IF res # AosDisks.Ok THEN ReportError(AosPartitionsLib.GetErrorMsg("Could not set EOC mark", res)); END;
							END;
						END;
					ELSE ReportError("Could not get volume object");
					END;
					
					(* TODO: create volume label entry *)
					IF fs = FAT12 THEN
					ELSIF fs = FAT16 THEN
					ELSIF fs = FAT32 THEN
					END;
					
					IF fs = FAT32 THEN (* write backup boot sector & FSInfo block *)
						disk.device.Transfer(AosDisks.Write, disk.table[partition].start + backupBoot, 1, block, 0, res);
						IF res = AosDisks.Ok THEN 
							freeCount := ((disk.table[partition].size - (rsvdSecCnt32 + (numFATs*fatsize))) DIV spc) + 1;
							(* the first two clusters are unusable because FAT[0]&FAT[1] are for reserved use only, 1 cluster is used for the 
							root directory on FAT32, so we subtract 3 clusters *)
							freeCount := freeCount - 3;
							IF rootCluster32 = 2 THEN firstFree := 3; ELSE firstFree := 2; END;
							block := BuildFSInfo(freeCount, firstFree); 
							disk.device.Transfer(AosDisks.Write, disk.table[partition].start + fsinfo, 1, block, 0, res);
							IF res # AosDisks.Ok THEN 
								ReportError(AosPartitionsLib.GetErrorMsg("Could not write FSInfo sector", res));
							END;
						ELSE ReportError(AosPartitionsLib.GetErrorMsg("Could not write backup boot sector", res));
						END;
					END;
					
					result.String("Formatted "); result.String(diskpartString); result.String(" as ");
					IF fs = FAT12 THEN result.String("FAT12 ");
					ELSIF fs = FAT16 THEN result.String("FAT16 ");
					ELSIF fs = FAT32 THEN result.String("FAT32 ");
					END;
					IF state.status * AosPartitionsLib.StatusError = {} THEN
						result.String("without errors");
					ELSE
						result.String("with "); result.Int(state.errorCount, 0); result.String(" errors");
					END;
				END;
			END;
		END DoOperation;
		
		(* write zeros to area *)
		(* start, end : sector addresses relative to first sector of partition *)
		PROCEDURE ClearSectors(from, to : LONGINT);
		CONST BufSize = 1024; 
		VAR	
			buf : POINTER TO ARRAY OF CHAR;
			ofs, num : LONGINT; 
			res : LONGINT;
		BEGIN
			ASSERT(from < to); 
			ASSERT((disk.table[partition].start#0) OR (disk.isDiskette)); (* protect MBR *)

			NEW(buf, BufSize*BS);
			num := (to - from + 1) DIV BufSize;
			ofs := from;
			SetStatus(state.status, "Formating...", from, from, to - from + 1, TRUE);
			WHILE (num > 0) DO
				ASSERT(ofs + BufSize  - 1<= disk.table[partition].size );
				disk.device.Transfer(AosDisks.Write, disk.table[partition].start + ofs, BufSize, buf^, 0, res);
				IF res # AosDisks.Ok THEN 
					ReportError(AosPartitionsLib.GetTransferError(disk.device, AosDisks.Write, disk.table[partition].start + ofs, res));
				END;
				SetCurrentProgress(from + ofs);
				DEC(num); INC(ofs, BufSize);
			END; 
			
			num := (to - from) MOD BufSize;
			WHILE (num > 0) DO
				ASSERT(ofs <= disk.table[partition].size);
				disk.device.Transfer(AosDisks.Write, disk.table[partition].start + ofs, 1, buf^, 0, res);
				IF res # AosDisks.Ok THEN 
					ReportError(AosPartitionsLib.GetTransferError(disk.device, AosDisks.Write, disk.table[partition].start + ofs, res));
				END;
				SetCurrentProgress(from + ofs);
				DEC(num); INC(ofs);
			END; 
		END ClearSectors;
		
		PROCEDURE BuildBPB(secPerClus : LONGINT) : Block;
		VAR
			b : Block;
			temp : ARRAY 9 OF CHAR;
			i, t, d: LONGINT;
		BEGIN
			ASSERT(disk.device.blockSize = BS);
			(* Jump instruction to boot code *)
			b[BsJmpBoot] := 0E9X; b[BsJmpBoot+1] := 0X; b[BsJmpBoot+2] := 0X;
			(* OEM name (MSWIN4.1 for compatibility reasons) *)
			FOR i := 0 TO 7 DO b[BsOEMName + i] := oemName[i]; END;
			(* Bytes per sector *)
			AosPartitionsLib.Put2(b, BpbBytsPerSec, disk.device.blockSize);
			(* Sectors per cluster *)
			b[BpbSecPerClus] := CHR(secPerClus);
			(* Number of reserved sectors in the Reserved region *)
			IF (fs = FAT12) OR (fs = FAT16) THEN (* 1 for maximum compatibility *) b[BpbRsvdSecCnt] := CHR(rsvdSecCnt1216); 
			ELSE (* FAT32: typically 32 *)  b[BpbRsvdSecCnt] := CHR(rsvdSecCnt32); 
			END;
			(* Number of FAT data structures (should be 2 for maximum compability) *)
			b[BpbNumFATs] := CHR(numFATs);
			(* Number of 32-byte directory entries in root directory (FAT12/16) *)
			IF (fs = FAT12) OR (fs = FAT16) THEN AosPartitionsLib.Put2(b, BpbRootEntCnt, rootEntCnt);
			ELSE (* FAT32: must be 0 *) AosPartitionsLib.Put2(b, BpbRootEntCnt, 0);
			END;
			(* Total sector count 16bit *)
			IF ((fs = FAT12) OR ((fs = FAT16) & (disk.table[partition].size  < 10000H))) THEN AosPartitionsLib.Put2(b, BpbTotSec16, disk.table[partition].size);
			ELSIF (fs = FAT32) THEN  (* FAT32: must be 0, FAT1216: of totsec does not fit *) AosPartitionsLib.Put2(b, BpbTotSec16, 0);
			END;
			(* Media field: fixed media = 0xF8, removable media = 0xF0; must be same as low byte of FAT[0] *)
			IF AosDisks.Removable IN disk.device.flags THEN b[BpbMedia] := CHR(0F0H); ELSE b[BpbMedia] := CHR(0F8H); END;
			(* FAT size: 16bit count of sectors occupied by one FAT *)
			IF (fs = FAT12) OR (fs = FAT16) THEN AosPartitionsLib.Put2(b, BpbFATSz16, fatsize); 
			ELSE (* FAT32: must be 0 *) AosPartitionsLib.Put2(b, BpbFATSz16, 0);
			END;
			AosPartitionsLib.Put2(b, BpbSecPerTrk, disk.geo.spt); (* sectors per track *)
			AosPartitionsLib.Put2(b, BpbNumHeads, disk.geo.hds); (* number of heads *)
			(* Hidden sectors; should be zero for non-partitioned media, 63 else *)
			IF ((disk.device.table=NIL) OR (LEN(disk.device.table)=1)) THEN (* non-partitioned *) AosPartitionsLib.Put4(b, BpbHiddSec, 0); ELSE AosPartitionsLib.Put4(b, BpbHiddSec, 63) END;
			(* Total sector count 32bit *)
			IF ((fs = FAT12) OR ((fs = FAT16) & (disk.table[partition].size < 10000H))) THEN AosPartitionsLib.Put4(b, BpbTotSec32, 0); (* value in BpbTotSec16 *)
			ELSE (* FAT32: must be 0, FAT1216: of totsec does not fit *) AosPartitionsLib.Put4(b, BpbTotSec32, disk.table[partition].size);
			END;
			IF (fs = FAT12) OR (fs = FAT16) THEN
				b[BsDrvNum] := AosPartitionsLib.GetDriveNum(disk.device); (* Int13 driver number *)
				b[BsReserved1] := 0X; (* Reserved *)
				b[BsBootSig] := CHR(29H); (* Extended boot signature; 0x29 indicates the presence of the following three fields *)
				AosClock.Get(t,d); AosPartitionsLib.Put4(b, BsVolID, i); (* volume serial number *)
				FOR i := 0 TO 10 DO b[BsVolLab + i] := volLab[i]; END; (* volume label *)
				IF fs = FAT12 THEN temp := "FAT12   "; ELSIF fs = FAT16 THEN temp := "FAT16   "; END;
				FOR i := 0 TO 7 DO b[BsFilSysType + i] := temp[i]; END;
			ELSE (* fs = FAT32 *)
				AosPartitionsLib.Put4(b, BpbFATSz32, fatsize); (* 32bit count of sectors occupied by one FAT *)
				AosPartitionsLib.Put2(b, BpbExtFlags, 0); (* FAT is mirrored at runtime into all FATs *)
				AosPartitionsLib.Put2(b, BpbFSVer, 0); (* FAT FS version: 0:0 *)
				AosPartitionsLib.Put4(b, BpbRootClus, rootCluster32); (* cluster number of the first cluster of the root directory *)
				AosPartitionsLib.Put2(b, BpbFSInfo, fsinfo); (* sector number of FSInfo structure in reserved region *)
				AosPartitionsLib.Put2(b, BpbBkBootSec, backupBoot); (* sector number of copy of the boot record in reserved region *)
				FOR i := 0 TO 11 DO b[BpbReserved] := 0X; END; (* reserved *)
				b[Bs32DrvNum] := AosPartitionsLib.GetDriveNum(disk.device); (* Int13 driver number *)
				b[Bs32Reserved1] := 0X; (* Reserved *)
				b[Bs32BootSig] := CHR(29H); (* Extended boot signature; 0x29 indicates the presence of the following three fields *)
				AosClock.Get(t,d); AosPartitionsLib.Put4(b, Bs32VolID, i); (* volume serial number *)
				FOR i := 0 TO 10 DO b[Bs32VolLab + i] := volLab[i]; END; (* volume label *)
				IF fs = FAT32 THEN temp := "FAT32   "; END; FOR i := 0 TO 7 DO b[BsFilSysType + i] := temp[i]; END;
			END;
			b[510] := 055X; b[511] := 0AAX; (* boot sector signature *)
			RETURN b;
		END BuildBPB;
		
		PROCEDURE BuildFSInfo(freecount, nextfree : LONGINT) : Block;
		VAR b : Block; i : LONGINT;
		BEGIN
			AosPartitionsLib.Put4(b, FsiLeadSig, 41615252H); (* Lead signature *)
			FOR i := 0 TO 479 DO b[FsiReserved1] := 0X; END; (* Reserved *)
			AosPartitionsLib.Put4(b, FsiStrucSig, 61417272H); (* Structure signature *)
			AosPartitionsLib.Put4(b, FsiFreeCount, freecount); (* last known free cluster count on volume *)
			AosPartitionsLib.Put4(b, FsiNxtFree, nextfree); (* Hint: "next" free cluster known *)
			FOR i := 0 TO 11 DO b[FsiReserved2] := 0X; END; (* Reserved *)
			AosPartitionsLib.Put4(b, FsiTrailSig, 0AA550000H); (* Trail signature *)
			RETURN b;
		END BuildFSInfo;
		
		(* Calculates the size of one FAT See [1], p. 21 *)
		PROCEDURE GetFatSize(sectorPerCluster : LONGINT) : LONGINT;
		VAR
			rootDirSectors, rootEntCnt, bytsPerSec, rsvdSecCnt : LONGINT;
			tmpVal1, tmpVal2 : LONGINT;
		BEGIN
			IF disk.isDiskette THEN 
				RETURN 9;
			ELSE
				IF fs = FAT32 THEN rootEntCnt := 0; rsvdSecCnt := rsvdSecCnt32; ELSE rootEntCnt := SELF.rootEntCnt; rsvdSecCnt := rsvdSecCnt1216; END;
				bytsPerSec := disk.device.blockSize;
				
				rootDirSectors := ((rootEntCnt * 32) + (bytsPerSec -1)) DIV bytsPerSec;
				tmpVal1 := disk.table[partition].size - (rsvdSecCnt + rootDirSectors);
				tmpVal2 := (256 * sectorPerCluster) + numFATs;
				
				IF fs = FAT32 THEN tmpVal2 := tmpVal2 DIV 2; END;
				RETURN  (tmpVal1 + (tmpVal2 - 1)) DIV tmpVal2;	
			END;
		END GetFatSize;
		
		(* Uses table from [1]; Return -1 in error case *)
		PROCEDURE GetSectorPerCluster(disksize : LONGINT) : LONGINT; 
		VAR spc : LONGINT;
		BEGIN
			ASSERT((disk.device.blockSize = 512) & (rsvdSecCnt1216 = 1) & (numFATs = 2));
			ASSERT((fs = FAT12) OR (rootEntCnt = 512)); (* so that table works *) 
			IF fs = FAT12 THEN
				spc := 1;
			ELSIF fs = FAT16 THEN 
				IF disksize <= 8400 THEN spc := -1; ReportError("FAT16 volumes must be bigger than 4,1MB");
				ELSIF disksize <= 32680 THEN spc := 2; (* 1K cluster *)
				ELSIF disksize <= 262144 THEN spc := 4; (* 2K cluster *) 
				ELSIF disksize <= 524288 THEN spc := 8; (* 4K cluster *) 
				ELSIF disksize <= 1048576 THEN spc := 16; (* 8K cluster *)
				(* to following entries are only used when FAT16 is forced *)
				ELSIF disksize <= 2097152 THEN spc := 32; (* 16K cluster *) 
				ELSIF disksize <= 4194304 THEN spc := 64; (* 32K cluster *) 
				ELSE spc := -1; ReportError("FAT16 volumes can't be bigger than 2GB");
				END;
			ELSIF fs = FAT32 THEN 
				IF disksize <= 66600 THEN spc := -1; ReportError("FAT32 volumes must be bigger than 32,5MB");
				ELSIF disksize <= 532480 THEN spc := 1; (* 0.5K cluster *) 
				ELSIF disksize <= 16777216 THEN spc := 8; (* 4K cluster *) 
				ELSIF disksize <= 33554432 THEN spc := 16; (* 8K cluster *) 
				ELSIF disksize <= 67108864 THEN spc := 32;(* 16K cluster *) 
				ELSE spc := 64; (* 32K cluster *) 
				END;
			ELSE
				HALT(301);
			END;
			RETURN spc;
		END GetSectorPerCluster;
		
		PROCEDURE ValidClusterSize(clusterSize : LONGINT):BOOLEAN;
		BEGIN
			RETURN ((clusterSize=512) OR (clusterSize=1024) OR (clusterSize=2048) OR (clusterSize=4096) OR
					(clusterSize=8192) OR (clusterSize=16384) OR (clusterSize=32768));
		END ValidClusterSize;
		
		PROCEDURE &Init(disk : AosPartitionsLib.Disk; partition : LONGINT; log : BOOLEAN);
		BEGIN
			Init^(disk, partition, log);
			name := "FormatFAT"; desc := "Format a partition with FAT file system"; locktype := AosPartitionsLib.WriterLock;
			oemName := "MSWIN4.1"; (* 8 bytes; default for max compatibility *)
			rsvdSecCnt1216 := 1; (* 2 bytes; default = 1 for max compatibility *)
			rsvdSecCnt32 := 32; (* 2 bytes *);
			IF disk.isDiskette THEN rootEntCnt := 224; ELSE rootEntCnt := 512; END;
			numFATs := 2; (* 1 byte; default = 2 for max compability *)
			volLab := "NO NAME    "; (* 11 bytes *)
			rootCluster32 := 2; (* 4 byte value; default = 2 for max compatibility *)
			fsinfo := 1; (* 2 byte *)
			backupBoot := 6; (* 2 byte; default = 6 is recommended *)
		END Init;
		
	END FormatPartition;
	
VAR
	fsType2 : LONGINT;
	
PROCEDURE GetVolume(dev : AosDisks.Device; partIdx : LONGINT; bpb : Block) : AosFATVolumes.Volume;
CONST CacheSize = 65563; (* in sectors *)
VAR
	vol : AosFATVolumes.Volume; vol12: AosFATVolumes.FAT12Volume; vol16: AosFATVolumes.FAT16Volume; vol32: AosFATVolumes.FAT32Volume; 
	fatSize, numSectors, numClusters, reserved, numFATs, rootEntryCount, sectPC, fat : LONGINT;
BEGIN 
	IF (LEN(bpb) = 512) & (bpb[510] = 055X) & (bpb[511] = 0AAX) THEN (* boot sector signature ok *)
		(* determine FAT type *)
		fatSize := AosFATVolumes.GetUnsignedInteger(bpb, BpbFATSz16);
		IF (fatSize = 0) THEN fatSize := AosFATVolumes.GetLongint(bpb, BpbFATSz32) END;
		numSectors := AosFATVolumes.GetUnsignedInteger(bpb, BpbTotSec16);
		IF (numSectors = 0) THEN numSectors := AosFATVolumes.GetLongint(bpb, BpbTotSec32) END;
		reserved := AosFATVolumes.GetUnsignedInteger(bpb, BpbRsvdSecCnt);
		numFATs := ORD(bpb[BpbNumFATs]);
		rootEntryCount := AosFATVolumes.GetUnsignedInteger(bpb, BpbRootEntCnt);
		sectPC := ORD(bpb[BpbSecPerClus]);
		
		numClusters := (numSectors - (reserved + (numFATs * fatSize) + (rootEntryCount * 32 + BS - 1) DIV BS)) DIV sectPC;
		
		IF (numClusters < 4085) THEN NEW(vol12); vol := vol12; fat := 12
		ELSIF (numClusters < 65525) THEN NEW(vol16); vol := vol16; fat := 16
		ELSE NEW(vol32); vol := vol32; fat := 32
		END;
		
		IF ~vol.InitLowLevel(bpb, numClusters, dev, dev.table[partIdx].start, dev.table[partIdx].size, BS) THEN 
			vol := NIL; 
		ELSE
			vol.SetCache(AosFATVolumes.Data, CacheSize, FALSE);
			EXCL(vol.flags, AosFS.ReadOnly);
		END;
	END;
	RETURN vol;
END GetVolume;
						
END AosFATScavenger.