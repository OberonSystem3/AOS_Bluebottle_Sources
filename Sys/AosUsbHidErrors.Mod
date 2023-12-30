MODULE AosUsbHidErrors; (** AUTHOR "ottigerm"; PURPOSE "HID Items parser with error codes" *)
(**
 * Bluebottle USB HID Error Handling Module
 *
 * This module handles the errors when parsing usb hid items
 *
 * Overview:
 *	HID Parser Error Checking	HID Parser Error Codes, Version 1.0  01/30/98
 * 
 * History:
 *
 *	17.07.2006	Version 1.0
 *)
 
IMPORT AosOut;
	
(*THESE CONSTANTS DEFINE THE ERROR CODES PROVIDED BY THE HID PARSER*)
CONST

	(* Unknown Items *)
	UnknownItem* = 											00H;
	(* Global Items *)
	GlobalItemUsagePage* = 									04H;
	GlobalItemLogicalMinimum* = 								14H;
	GlobalItemLogicalMaximum* = 								24H;
	GlobalItemPhysicalMinimum* = 								34H;
	GlobalItemPhysicalMaximum* = 								44H;
	GlobalItemUnitExponent* = 									54H;
	GlobalItemUnit* = 											64H;
	GlobalItemReportSize* = 									74H;
	GlobalItemReportID* = 										84H;
	GlobalItemReportCount* = 									94H;
	GlobalItemPush* = 											00A4H;
	GlobalItemPop* = 											00B4H;
	GlobalItemGeneral* = 										00F4H;
	(* Local Items *)
	LocalItemUsage* = 											08H;
	LocalItemUsageMinimum* = 									18H;
	LocalItemUsageMaximum* = 								28H;
	LocalItemDesignatorIndex* = 								38H;
	LocalItemDesignatorMinimum* = 							48H;
	LocalItemDesignatorMaximum* = 							58H;
	LocalItemStringIndex* = 									78H;
	LocalItemStringMinimum* = 									88H;
	LocalItemStringMaximum* = 								98H;
	LocalItemDelimiter* = 										00A8H;
	(* Main Items *)
	MainItemInput* = 											80H;
	MainItemOutput* = 											90H;
	MainItemFeature* = 										00B0H;
	MainItemCollection* = 										00A0H;
	MainItemEndCollection* = 									00C0H;
	
TYPE
	ErrorItem = POINTER TO RECORD
		itemPosition	:		LONGINT;
		errorTag* 		: 		LONGINT;
		errorSubcode*	:		LONGINT;
		next*			:		ErrorItem;
	END;

	ErrorManager* = OBJECT

	(* Print errors as described in HID Parser Error Codes, Version 1.0, 30.01.1998 *)
	PROCEDURE PrintError*(errorTag, errorSubcode:LONGINT);
	BEGIN
		CASE errorTag OF
			UnknownItem:
				CASE errorSubcode OF
					3FH:AosOut.String("UUnknownOrReservedItem ");
					|3EH:AosOut.String("ULongItemDefined ");
					ELSE ErrorNotFound;
				END;
	
		(* Global Items *)
			|GlobalItemUsagePage:
				CASE errorSubcode OF
					00H:AosOut.String("DataFieldMustBeNonZero");
					|01H:AosOut.String("DataFieldGreaterThan0xFFFF");
					|02H:AosOut.String("MustBeDefPriorToAnyIOFeatItems");
					ELSE ErrorNotFound;
				END;
					
			|GlobalItemLogicalMinimum:
				CASE errorSubcode OF
					00H:AosOut.String("MustBeWithinBoundsOfReportSize ");
					|01H:AosOut.String("MustBeDefPriorToAnyIOFeatItems");
					|02H:AosOut.String("MustEq1IfArrayFlagIsSetInMI ");
					ELSE ErrorNotFound;
				END;
					
			|GlobalItemLogicalMaximum:
				CASE errorSubcode OF
					00H:AosOut.String("MustBeWithinBoundsOfReportSize ");
					|01H:AosOut.String("MustBeDefPriorToAnyIOFeatItems");
					|02H:AosOut.String("MustEqNODefUsagsIfArFlagSetInMI ");
					ELSE ErrorNotFound;
				END;
				
			|GlobalItemPhysicalMinimum:
				IF (errorSubcode=00H) THEN
					AosOut.String("MustHaveCorrespPhysicalMax");
				ELSE 
					ErrorNotFound;
				END;
				
			|GlobalItemPhysicalMaximum:
				IF (errorSubcode=00H) THEN
					AosOut.String("MustHaveCorrespPhysicalMin");
				ELSE 
					ErrorNotFound;
				END;
				
			|GlobalItemUnitExponent:
				ErrorNotFound;
							
			|GlobalItemUnit:
				ErrorNotFound;
				
			|GlobalItemReportSize:
				IF (errorSubcode=01H) THEN
					AosOut.String("MustBeDefPriorToAnyIOFeatIt");
				ELSE
					ErrorNotFound;
				END;
				
			|GlobalItemReportID:
				CASE errorSubcode OF
					00H:AosOut.String("MustBeNonZero ");
					|01H:AosOut.String("MustBeLessOrEqual255");
					|02H:AosOut.String("MustBeDefPriorToAnyIOFeatIt ");
					|03H:AosOut.String("CantSpanTopLevelApplCollBounds ");
					|04H:AosOut.String("MSCnstCantBeDefOutsATopLevColl");
					ELSE ErrorNotFound;
				END;
				
			|GlobalItemReportCount:
				IF (errorSubcode=00H) THEN
					AosOut.String("MustBeNonZero");
				ELSE 
					ErrorNotFound;
				END;
			
			|GlobalItemPush:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveCorrespondingPop");
					|01H:AosOut.String("DataFieldSizeMustBeZero");
					ELSE ErrorNotFound;
				END;
			
			|GlobalItemPop:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveCorrespondingPush");
					|01H:AosOut.String("DataFieldSizeMustBeZero");
					ELSE ErrorNotFound;
				END;
				
			|GlobalItemGeneral:
				IF(errorSubcode=00H) THEN
					AosOut.String("GlobalItemRedundantlyDeclared");
				ELSE 
					ErrorNotFound;
				END;
			
		(* Local Items *)
			|LocalItemUsage:
				IF (errorSubcode=00H) THEN	
					AosOut.String("MustBeDefPriorToAnyIOFeatIt ");
				ELSE 
					ErrorNotFound;
				END;
			
			|LocalItemUsageMinimum:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveACorrespondingUsageMax ");
					|01H:AosOut.String("MustBeLessOrEqualToUsageMax ");
					|03H:AosOut.String("UPOfExtUsgMinMustMatchMax ");
					ELSE ErrorNotFound;
				END;
			
			|LocalItemUsageMaximum:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveACorrespondingUsageMin ");
					|01H:AosOut.String("MustBeGreaterOrEqualToMinimum");
					|02H:AosOut.String("UPOfExtUsgMaxMustMatchMin ");
					ELSE ErrorNotFound;
				END;
			
			|LocalItemDesignatorIndex:
				ErrorNotFound;
				
			|LocalItemDesignatorMinimum:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveACorrespondingDesigMax ");
					|01H:AosOut.String("MustBeLessOrEqualToMaximum ");
					ELSE ErrorNotFound;
				END;
			
			|LocalItemDesignatorMaximum:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveACorrespondingDesigMin ");
					|01H:AosOut.String("MustBeGreaterOrEqualToMinimum ");
					ELSE ErrorNotFound;
				END;
			
			|LocalItemStringIndex:
				ErrorNotFound;
				
			|LocalItemStringMinimum:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveACorrespondingStringMax ");
					|01H:AosOut.String("MustBeLessOrEqualToMaximum ");
					ELSE ErrorNotFound;
				END;
			
			|LocalItemStringMaximum:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveACorrespondingStringMin ");
					|01H:AosOut.String("MustBeGreaterOrEqualToMinimum ");
					ELSE ErrorNotFound;
				END;
			
			|LocalItemDelimiter:
				CASE errorSubcode OF
					00H:AosOut.String("MustBeOpenOrClose");
					|01H:AosOut.String("NoNestingOfDelimitedSets ");
					|02H:AosOut.String("MustBeCorrespondingOpenAndClose");
					|03H:AosOut.String("MustOnlyContUsgMinAndUsgMaxLI");
					|04H:AosOut.String("MayNotBeDeclForTopLevelAppColl");
					ELSE ErrorNotFound;
				END;
			
		(* Main Items *)
			|MainItemInput:
				CASE errorSubcode OF
					00H:AosOut.String("ReqGlobLocalItemsMustBeDef");
					|01H:AosOut.String("CantBeContWithinDelOpADelCl");
					|02H:AosOut.String("LogMinMaxMustBeWithinBndsOfRepS");
					|03H:AosOut.String("LogOrPhysMaxMustBeGrThRespMin");
					ELSE ErrorNotFound;
				END;
			
			|MainItemOutput:
				CASE errorSubcode OF
					00H:AosOut.String("ReqGlobLocalItemsMustBeDef");
					|01H:AosOut.String("CantBeContWithinDelOpenADelClose");
					|02H:AosOut.String("LogMinMaxMustBeWithinBndsOfRepS");
					|03H:AosOut.String("LogOrPhysMaxMustBeGrThRespMin");
					ELSE ErrorNotFound;
				END;
			
			|MainItemFeature:
				CASE errorSubcode OF
					00H:AosOut.String("ReqGlobLocalItemsMustBeDef");
					|01H:AosOut.String("CantBeContWithinDelOpenADelClose");
					|02H:AosOut.String("LogMinMaxMustBeWithinBndsOfRepS");
					|03H:AosOut.String("LogOrPhysMaxMustBeGrThRespMin");
					ELSE ErrorNotFound;
				END;
			
			|MainItemCollection:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveACorrEndColl");
					|01H:AosOut.String("CantBeContWithinSetDelOpACl");
					|02H:AosOut.String("AppCollCanOnlyBeDeclAtTopLev");
					ELSE ErrorNotFound;
				END;
			
			|MainItemEndCollection:
				CASE errorSubcode OF
					00H:AosOut.String("MustHaveACorrespColl");
					|01H:AosOut.String("CantBeContWithinSetDelOpenAClose");
					|02H:AosOut.String("MSCTheFinSizOAllRepMustBeMltf8B");
					ELSE ErrorNotFound;
				END;
			ELSE
				ErrorNotFound;
		END;
		
	END PrintError;
	
	(*used, when error code not defined in PrintError(..) *)
	PROCEDURE ErrorNotFound;
	BEGIN
		AosOut.String("unknown error");
	END ErrorNotFound;

	END ErrorManager;
	
	(*manages the occured errors in a linked list*)
	ErrorList*= OBJECT
	VAR
		firstErrorItem, lastErrorItem	: ErrorItem;
		hidErrorManager 			: ErrorManager;
		
		(* add error at the end of the linked list*)
		PROCEDURE Add*(position, errorTag, errorSubcode : LONGINT);
		BEGIN
			(*detect empty list*)
			IF(firstErrorItem=NIL) THEN
				NEW(firstErrorItem);
				lastErrorItem := firstErrorItem;
			ELSE
				(*when list is not empty*)
				NEW(lastErrorItem.next);
				lastErrorItem := lastErrorItem.next;
			END;
			
			lastErrorItem.itemPosition 	:= position;
			lastErrorItem.errorTag		:= errorTag;
			lastErrorItem.errorSubcode 	:= errorSubcode;
		END Add;
		
		(* print all errors*)
		PROCEDURE PrintAll*;
		VAR
			current : ErrorItem;
		BEGIN
			current := firstErrorItem;
			IF(firstErrorItem#NIL)THEN
				AosOut.String("Hid parser detected following errors for this device"); AosOut.Ln;
				AosOut.String("Item            ErrorTag        ErrorSubcode    Description"); AosOut.Ln;
				
				REPEAT
					AosOut.Int(current.itemPosition, 4); AosOut.String("                  "); AosOut.Hex(current.errorTag, -2);
					AosOut.String("                  "); AosOut.Hex(current.errorSubcode, -2);
					AosOut.String("                      ");hidErrorManager.PrintError(current.errorTag, current.errorSubcode);
					AosOut.Ln;
					current := current.next;
				UNTIL (current=NIL);
			END;
		END PrintAll;
		
	BEGIN
		NEW(hidErrorManager);
	END ErrorList;
	
BEGIN	
	
END AosUsbHidErrors.

S.Free AosUsbHidErrors ~