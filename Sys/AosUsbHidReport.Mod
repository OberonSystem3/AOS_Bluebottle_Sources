MODULE AosUsbHidReport; (** AUTHOR "ottigerm"; PURPOSE "generating HID reports" *)
(**
 * Bluebottle USB HID Report Module
 *
 * This is the module generating hid reports
 *
 * 
 * History:
 *
 *	02.06.2006	History started (ottigerm)
 *)
 
IMPORT  AosUsbHidUP, AosOut, SYSTEM;
	

CONST
	Debug*					= FALSE;
	
	UseUsageDictionaryExt*	= TRUE;

	MainTypeInput			=   0;
	MainTypeOutput 		=   1;
	MainTypeFeature		=   2;
	
	UndefinedState*		= -1;

TYPE

	MainType* = LONGINT;
	
	(*for storing collections*)
	HidCollection*= POINTER TO RECORD
		type*:				LONGINT;
		usagePage*:		LONGINT;
		usage*:				LONGINT;
		firstCollection:		HidCollection;
		lastCollection:		HidCollection;
		firstReport*:		HidReport;
		lastReport:			HidReport;
		next:				HidCollection;
	END;	
	
	UsageTuple* = POINTER TO RECORD
		usageID*:			LONGINT;
		usagePage*:		LONGINT;
		usageValue*:		LONGINT;
	END;
	
	UsageDictElement*= RECORD
		firstUsageID*:			LONGINT;
		nofFollowing*:			LONGINT;
		otherUsagePage*:		LONGINT;
	END;
	
	UsageDictionary*= POINTER TO RECORD
		elements*:			POINTER TO ARRAY OF UsageDictElement;
	END;
	
	PtrToUsageTupleArr*= POINTER TO ARRAY OF UsageTuple;

	HidReport* = POINTER TO RECORD
		next*:				HidReport;
		reportID*:			LONGINT;
		
		usagePage*:		LONGINT;
		(*holding usageID and usageValue in each entry*)
		usages*:			PtrToUsageTupleArr;

		mainState*:			LONGINT;
		(*reportOffset*:		LONGINT;		(*bit offset in the report*)
		*)reportSize*:			LONGINT;
		reportCount*:		LONGINT;
		reportType*:		MainType;		(*Input/Output/Feature Item*)
		logicalMinimum*:	LONGINT;
		logicalMaximum*:	LONGINT;
		physicalMinimum*:	LONGINT;
		physicalMaximum*:	LONGINT;
		unitExponent*:		LONGINT;
		unit*:				LONGINT;
		
		(*this field is used, when the device does not send the values for each usage but sends, which usages are used -> when mainState has Array flag set*)
		supportedUsages*:	UsageDictionary;
	END;
	
	HidReportIterator*= POINTER TO RECORD
		report*:				HidReport;
		next*:				HidReportIterator;
	END;
	
	(*used for keeping parent collections, when new Collection found*)
	ParentStackItem= POINTER TO RECORD
		value:				HidCollection;
		next:				ParentStackItem;
	END;
	
	
	(*used for keeping all references, where to store the reports*)
	ReportItem*= POINTER TO RECORD
		(*bit index in the hid report*)
		index:						LONGINT;
		(*reportID*)
		reportID*:					LONGINT;
		(*the size of each usage*)
		reportItemSize*:			LONGINT;
		(*the number of usages to read*)
		reportItemCount*:			LONGINT;
		(*where to store the values*)
		values*:						PtrToUsageTupleArr;
		next*:						ReportItem;
	END;
	
	(*holding reportItems*)
	ReportItemQueue* = POINTER TO RECORD
		first*:						ReportItem;
		bitsAlreadyUsed*:			LONGINT;
	END;
	
	(*stack, holding parent tree of current collection*)
	HIDParentList*=OBJECT
	VAR 
		first : ParentStackItem;
		
		(*to put item on top of the parent stack*)
		PROCEDURE PushFront*(value: HidCollection);
		VAR cur : ParentStackItem;
		BEGIN
			IF (first = NIL) THEN
				NEW(first);
				first.value := value;
			ELSE
				NEW(cur);
				cur.value := value;
				cur.next := first;
				first := cur;
			END;
		END PushFront;
		
		(*to get  the top item from parent stack*)
		PROCEDURE PopFront*(): HidCollection;
		VAR ret : HidCollection;
		BEGIN
			IF(first=NIL) THEN
				ret := NIL;
			ELSE
				ret := first.value;
				first := first.next;
			END;
			RETURN ret;
		END PopFront;
	END HIDParentList;
		

	(*stores the collections with its reports in a n-ary tree*)
	HidReportManager*=OBJECT
	VAR
		rootCollection, current:	HidCollection;
		parentList:				HIDParentList;
		reportItemQueue:		ReportItemQueue;
		reportIterator:			HidReportIterator;
	
		(*appends a collection to the current collection, stores the current collection on the stack and goes to new collection
		* 	param: 	type		like physical, application...
		*			usagePage	the collection's usage page
		*			usage		the collection's usage
		*)
		PROCEDURE BeginCollection*(type, usagePage, usage: LONGINT);
		VAR newCollection : HidCollection;
		BEGIN
			NEW(newCollection);
			newCollection.type 			:= type;
			newCollection.usagePage 	:= usagePage;
			newCollection.usage 		:= usage;
			
			IF(current.firstCollection=NIL) THEN
				current.firstCollection := newCollection;
				current.lastCollection := current.firstCollection;
			ELSE
				current.lastCollection.next := newCollection;
				current.lastCollection := newCollection;
			END;
			parentList.PushFront(current);
			current := newCollection;
		END BeginCollection;
		
		(*closes the current collection
		*)
		PROCEDURE EndCollection*;
		VAR ret : HidCollection;
		BEGIN
			ASSERT(current#rootCollection);
			ret := parentList.PopFront();
			current := ret;
		END EndCollection;
		
		
		(*finds the collection with usagePage and usage from the rootCollection including subnodes
		* 	param: 	usagePage		usagePage to find
		*			usage 			usage to find
		*	return:	hidCollection	with usagePage and usage if found
		*			NIL				ohterwise
		*)
		PROCEDURE GetCollection*(usagePage, usage: LONGINT): HidCollection;
		VAR collIterator, result : HidCollection;
		BEGIN
			ASSERT(rootCollection.firstCollection#NIL);
			collIterator := rootCollection.firstCollection;
			WHILE (collIterator#NIL) DO
				result := FindColl(collIterator, usagePage, usage);
				IF result#NIL THEN
					RETURN result;
				END;
				collIterator := collIterator.next;
			END;
			RETURN NIL;
		END GetCollection;
		
		
		(*finds the collection with usagePage and usage from hidCollection
		* 	param: 	hidColl	collection where to start searching
		*			usagPage		usagePage to find
		*			usage			usage to find
		*	return:	hidCollection 	with usagePage and usage if found
		*			NIL				otherwise
		*)
		PROCEDURE FindColl(hidColl: HidCollection; usagePage, usage: LONGINT): HidCollection;
		VAR rv : HidCollection;
		BEGIN
			IF (hidColl=NIL) THEN RETURN NIL; END;
			rv := NIL;
			IF Debug THEN
				AosOut.String("parsing item: UsagePage"); AosOut.Int(hidColl.usagePage,5); AosOut.String(" Usage("); AosOut.Int(hidColl.usage,0); AosOut.String("):"); AosUsbHidUP.PrintUsagePage(hidColl.usagePage,hidColl.usage); AosOut.Ln;
			END;
			IF ((hidColl.usagePage=usagePage)&(hidColl.usage=usage)) THEN
				rv := hidColl;
			ELSE
				IF (hidColl.firstCollection#NIL) THEN
					rv := FindColl(hidColl.firstCollection, usagePage, usage);
					IF((rv=NIL) & (hidColl.next#NIL)) THEN
						rv := FindColl(hidColl.next, usagePage, usage);
					END;
				END;
			END;
			RETURN rv;
		END FindColl;
		
		(*finds the usage with usagePage in the hidCollection
		* 	param: 	usagPage		usagePage to find
		*			usage			usage to find
		*			hidCollection	from where to find the usage
		*			report			to store the hidReport, where the usage was found. NIL if not found
		*	return:	usageTuple		the reference to the usageTuple with usage and usagePage
		*			NIL				otherwise
		*)
		PROCEDURE GetUsage*(usagePage, usage: LONGINT; hidCollection: HidCollection; VAR report: HidReport): UsageTuple;
		VAR
			cursor		: HidReport;
			usageTuple	: UsageTuple;
			subColl		: HidCollection;
			i,
			tupleLength	: LONGINT;
		BEGIN
			ASSERT(hidCollection#NIL);
			cursor := hidCollection.firstReport;
			WHILE(cursor#NIL) DO
				IF((cursor.usagePage= usagePage) & (cursor.usages#NIL)) THEN
					tupleLength := LEN(cursor.usages);
					FOR i:= 0 TO tupleLength-1 DO
						IF (cursor.usages[i].usageID=usage) THEN
							usageTuple := cursor.usages[i];
							report := cursor;
							RETURN usageTuple;
						END;
					END;
					IF UseUsageDictionaryExt THEN
						IF cursor.supportedUsages # NIL THEN
							FOR i:=0 TO LEN(cursor.supportedUsages.elements)-1 DO
								IF (cursor.supportedUsages.elements[i].firstUsageID<=usage) & 
									(cursor.supportedUsages.elements[i].firstUsageID+
									cursor.supportedUsages.elements[i].nofFollowing>=usage) THEN
									usageTuple := cursor.usages[0];
									report := cursor;
									IF Debug THEN
										AosOut.String("searching in dictionary: firstUsage, lastUsage, val");
										AosOut.Int(cursor.supportedUsages.elements[i].firstUsageID,10);
										AosOut.Int(cursor.supportedUsages.elements[i].nofFollowing+cursor.supportedUsages.elements[i].firstUsageID,10);
										AosOut.Int(usage,10);
									END;
									AosOut.Ln;
									RETURN usageTuple;
								END;
							END;
						END;
					END;
				END;
				cursor := cursor.next;
			END;
			subColl := hidCollection.firstCollection;
			WHILE(subColl#NIL) DO
				usageTuple := GetUsage(usagePage, usage, subColl, report);
				IF (usageTuple#NIL) THEN
					RETURN usageTuple;
				ELSE
					subColl := subColl.next;
				END;
			END;
			RETURN NIL;
		END GetUsage;
		
		(*creates a usageTuple with the id which was found at position index in the dictionary dict
		* DOES NOT RETURN REFERENCE TO ORIGINAL USAGETUPLE
		* 	param: 	index			position to search
		*			dict				where to search
		*	return:	new usageTuple
		*)
		PROCEDURE GetDictKey*(index: LONGINT; dict: UsageDictionary):UsageTuple;
		VAR
			counter, i	: LONGINT;
			rv			: UsageTuple;
		BEGIN
			ASSERT(dict.elements#NIL);
			NEW(rv);
			FOR i:=0 TO LEN(dict.elements)-1 DO
				IF (index>counter+dict.elements[i].nofFollowing) THEN
					IF Debug THEN
						AosOut.String("looking in "); AosOut.Int(dict.elements[i].firstUsageID,0); AosOut.String(".."); 
						AosOut.Int(dict.elements[i].firstUsageID+dict.elements[i].nofFollowing,0);AosOut.Ln;
					END;
					counter := counter + 1 + dict.elements[i].nofFollowing;
				ELSE
					IF Debug THEN
						AosOut.String("found in interval "); AosOut.Int(dict.elements[i].firstUsageID,0); AosOut.String(".."); 
						AosOut.Int(dict.elements[i].firstUsageID+dict.elements[i].nofFollowing,0);AosOut.Ln;
					END;
					rv.usageID := dict.elements[i].firstUsageID+index-counter;
					rv.usagePage := dict.elements[i].otherUsagePage;
					RETURN rv;
				END;
			END;
			RETURN rv;
		END  GetDictKey;
		
		(*calculates the length of a dictionary
		* 	param: 	dict 			dictionary to calculate
		*	return:	length of the dictionary
		*)
		PROCEDURE DictSize*(dict: UsageDictionary):LONGINT;
		VAR sum, i:	LONGINT;
		BEGIN
			ASSERT(dict.elements#NIL);
			FOR i:=0 TO LEN(dict.elements)-1 DO
				sum := sum + 1 + dict.elements[i].nofFollowing;
			END;
			RETURN sum;
		END DictSize;

		(* return true if the current collection is the root collection
		*	return:	TRUE			if the current collection is the root collection
		*			FALSE			otherwise
		*)
		PROCEDURE OnTopLevel*(): BOOLEAN;
		BEGIN
			RETURN current=rootCollection;
		END OnTopLevel;
		
		(*add report to the current collection
		* 	param:	report 	report to add
		*)
		PROCEDURE AddReport*(report : HidReport);
		VAR
			newReportItem:	ReportItem;
		BEGIN
			IF (current.firstReport=NIL) THEN
				current.firstReport:= report;
				current.lastReport:= current.firstReport;
			ELSE
				current.lastReport.next := report;
				current.lastReport := report;
			END;
			
			IF Debug THEN
				AosOut.String("Report added"); AosOut.Ln; 
			END;
			(*generate reportItem*)
			NEW(newReportItem);
			(*newReportItem.index 			:= reportItemQueue.bitsAlreadyUsed;*)
			newReportItem.reportID		:= report.reportID;
			newReportItem.reportItemSize 	:= report.reportSize;
			newReportItem.reportItemCount	:= report.reportCount;
			newReportItem.values 			:= report.usages;
						
			IF Debug THEN
				AosOut.String("Add report:");AosOut.Ln;
				AosOut.String(" index: "); AosOut.Int(newReportItem.index,0); AosOut.Ln;
				AosOut.String(" reportItemSize: "); AosOut.Int(newReportItem.reportItemSize,0); AosOut.Ln;
				AosOut.String(" reportItemCount: "); AosOut.Int(newReportItem.reportItemCount,0); AosOut.Ln;
				AosOut.String(" index: "); AosOut.Int(newReportItem.index,0); AosOut.Ln;

				IF (report.usages=NIL) THEN
					AosOut.String("AosUsbHidReport::HIDReport.AddReport: found empty usageTupleList"); AosOut.Ln;
				ELSE
					AosOut.String("AosUsbHidReport::HIDReport.AddReport: found usageTupleList"); AosOut.Ln;
				END;
			END;
			AddReportItem(newReportItem);
			AddReportIterator(report);
		END AddReport;
		
		(*add report item to reportItemQueue
		* 	param:	reportItem 	record holding the information how, from and to where to store reports.
		*)
		PROCEDURE AddReportItem(reportItem: ReportItem);
		VAR
			cursor:	ReportItem;
			i: 		LONGINT;
		BEGIN
			
			IF (reportItemQueue.first=NIL) THEN
				reportItemQueue.bitsAlreadyUsed:=0;
				reportItemQueue.first := reportItem;
			ELSE
				cursor := reportItemQueue.first;
				WHILE(cursor.next#NIL) DO
					cursor := cursor.next;
				END;
				cursor.next := reportItem;
			END;
			reportItemQueue.bitsAlreadyUsed:= reportItemQueue.bitsAlreadyUsed + (reportItem.reportItemSize*reportItem.reportItemCount);
			IF Debug THEN
				AosOut.String("AosUsbHidReport:HIDReport.AddReportItem: Successfully added report item. Updated bitsAlreadyUsed: ");
				AosOut.Int(reportItemQueue.bitsAlreadyUsed,0); AosOut.Ln;
				cursor := reportItemQueue.first;
				WHILE (cursor.next#NIL) DO
					cursor := cursor.next;
				END;
				IF (cursor.values#NIL) THEN
					FOR i:=0 TO cursor.reportItemCount-1 DO
						AosOut.String("AddReportItem: cursor.values[i].usageID: "); AosOut.Int(cursor.values[i].usageID,0); AosOut.Ln;
					END;
				END;
			END;
		END AddReportItem;
		
		(*add a report to the reportIterator
		*	param: report	report to add
		*)
		PROCEDURE AddReportIterator(report: HidReport);
		VAR cursor:	HidReportIterator;
		BEGIN
			IF(reportIterator=NIL) THEN
				NEW(reportIterator);
				reportIterator.report := report;
			ELSE
				cursor := reportIterator;
				WHILE cursor.next#NIL DO
					cursor := cursor.next;
				END;
				NEW(cursor.next);
				cursor.next.report := report;
			END;
		END AddReportIterator;
		
		(*checks, whether the device sends only parts of reports
		*	return:	TRUE 	if it sends reportIDs
					FALSE 	if it sends always the whole report
		*)
		PROCEDURE UsesReportIDMechanism*(): BOOLEAN;
		VAR cursor:	HidReportIterator;
		BEGIN
			cursor := reportIterator;
			WHILE(cursor#NIL) DO
				IF(cursor.report.reportID#UndefinedState) THEN
					RETURN TRUE;
				END;
				cursor := cursor.next;
			END;
			RETURN FALSE;
		END UsesReportIDMechanism;
		
		(*return reportItemQueue, for parsing the hid report fast and easily
		* 	return:	reportItemQueue
		*)
		PROCEDURE GetReportItemQueue*(): ReportItemQueue;
		BEGIN
			RETURN reportItemQueue;	
		END GetReportItemQueue;
		
		(*prints actual reports*)
		PROCEDURE PrintReportState*;
		BEGIN
			IF rootCollection#NIL THEN
				PrintReport(rootCollection);			
			END;
		END PrintReportState;
		
		(*prints actual reports starting from root collection*)
		PROCEDURE PrintReport(collection:HidCollection);
		VAR
			subCollectionCursor:	HidCollection;
			reportCursor:		HidReport;
			i:					LONGINT;
			mainState:			SET;
		BEGIN
			reportCursor := collection.firstReport;
			WHILE reportCursor#NIL DO
				AosOut.String("+"); 						AosOut.Ln;
				AosOut.String("    reportID: "); 			AosOut.Int(reportCursor.reportID,0); AosOut.Ln;
				AosOut.String("    usagePage("); 		AosOut.Int(reportCursor.usagePage,0);
				AosOut.String("): ");						AosUsbHidUP.PrintUsagePageName(reportCursor.usagePage); AosOut.Ln;
				AosOut.String("    reportSize: "); 			AosOut.Int(reportCursor.reportSize,0); AosOut.Ln;
				AosOut.String("    reportCount: ");		AosOut.Int(reportCursor.reportCount,0); AosOut.Ln;
				AosOut.String("    reportType: ");
				IF reportCursor.reportType=MainTypeInput THEN 
					AosOut.String("MainTypeInput");
				ELSE
					IF reportCursor.reportType=MainTypeOutput THEN 
						AosOut.String("MainTypeOutput");
					ELSE
						IF  reportCursor.reportType=MainTypeFeature THEN 
							AosOut.String("MainTypeFeature");
						ELSE
							AosOut.String("MainTypeUndefined");
						END;
					END;
				END;
				AosOut.Ln;
				mainState:= SYSTEM.VAL(SET,reportCursor.mainState);
				AosOut.String("    mainState: ");			AosOut.Bits(mainState,0,9); AosOut.Ln;
				
				IF (0 IN mainState) THEN AosOut.String("      Constant (no usages!)") 	ELSE AosOut.String("      Data")				END; AosOut.Ln;
				IF (1 IN mainState) THEN AosOut.String("      Variable")				ELSE AosOut.String("      Array")				END; AosOut.Ln;
				IF (2 IN mainState) THEN AosOut.String("      Relative")				ELSE AosOut.String("      Absolute")			END; AosOut.Ln;
				IF (3 IN mainState) THEN AosOut.String("      Wrap") 					ELSE AosOut.String("      No Wrap")			END; AosOut.Ln;
				IF (4 IN mainState) THEN AosOut.String("      Non Linear") 			ELSE AosOut.String("      Linear")			END; AosOut.Ln;
				IF (5 IN mainState) THEN AosOut.String("      No Preferred") 			ELSE AosOut.String("      Preferred State")	END; AosOut.Ln;
				IF (6 IN mainState) THEN AosOut.String("      Null State") 			ELSE AosOut.String("      No Null Position")	END; AosOut.Ln;
				IF (7 IN mainState) THEN AosOut.String("      Volatile") 				ELSE AosOut.String("      Non Volatile") 		END; AosOut.Ln;
				IF (8 IN mainState) THEN AosOut.String("      Buffered Bytes") 		ELSE AosOut.String("      Bit Field"); 			END; AosOut.Ln;
				
				AosOut.String("    logicalMinimum: "); 	AosOut.Int(reportCursor.logicalMinimum,0); 	AosOut.Ln;
				AosOut.String("    logicalMaximum: "); 	AosOut.Int(reportCursor.logicalMaximum,0); 	AosOut.Ln;
				AosOut.String("    physicalMinimum: "); 	AosOut.Int(reportCursor.physicalMinimum,0);	AosOut.Ln;
				AosOut.String("    physicalMaximum: "); 	AosOut.Int(reportCursor.physicalMaximum,0);AosOut.Ln;
				AosOut.String("    unitExponent: "); 		AosOut.Int(reportCursor.unitExponent,0); 	AosOut.Ln;
				AosOut.String("    unit"); 				AosOut.Int(reportCursor.unit,0); 				AosOut.Ln;

				IF(reportCursor.usages#NIL) THEN
					FOR i:=0 TO LEN(reportCursor.usages)-1 DO
						IF(1 IN mainState) THEN
							AosOut.String("     usageID("); AosOut.Int(reportCursor.usages[i].usageID,0); AosOut.String("): "); 
							AosUsbHidUP.PrintUsagePage(reportCursor.usagePage, reportCursor.usages[i].usageID); AosOut.Ln;
							AosOut.String("     usageValue: "); AosOut.Int(reportCursor.usages[i].usageValue,50); AosOut.Ln;
						ELSE
							AosOut.String("     usageID(");
							IF(reportCursor.usages[i].usageValue#0) THEN
								AosUsbHidUP.PrintUsagePage(reportCursor.usagePage, reportCursor.usages[i].usageValue); 
							ELSE
								AosOut.String("0");
							END;
							AosOut.String(") returned"); AosOut.Ln;
						END;
					END;
				END;
				AosOut.Ln;
				reportCursor := reportCursor.next;
			END;
			subCollectionCursor := collection.firstCollection;
			WHILE subCollectionCursor#NIL DO
				PrintReport(subCollectionCursor);
				subCollectionCursor := subCollectionCursor.next;
			END;
		END PrintReport;
		
		PROCEDURE &Init;
		BEGIN
			NEW(rootCollection);
			current := rootCollection;
			NEW(parentList);
			NEW(reportItemQueue);			
		END Init;

	END HidReportManager;
	
END AosUsbHidReport.

S.Free AosUsbHidReport~