MODULE AosUsbHidParserExt; (** AUTHOR "ottigerm"; PURPOSE "HID Items parser with error codes" *)
(**
 * Bluebottle USB HID Items Module
 *
 * This module providing item parsing outputs, it is used for debugging or tracing
 *
 * Overview:
 *
 *	Main Items		As described on page 28
 *	Global Items	As described on page 35
 *	Local Items		As described on page 39

 * 
 * History:
 *
 *	29.09.2006	Version 1.0 (ottigerm)
 *)
 
IMPORT AosOut, AosUsbHidUP, SYSTEM;

CONST
	(*enum for global item parsing*)
	ParseIDUsagePage*					=   0;
	ParseIDLogicalMinimum*			=   1;
	ParseIDLogicalMaximum	*			=   2;
	ParseIDPhysicalMinimum* 			=   3;
	ParseIDPhysicalMaximum* 			=   4;
	ParseIDUnitExponent*				=   5;
	ParseIDUnit*						=   6;
	ParseIDReportSize*					=   7;
	ParseIDReportID*					=   8;
	ParseIDReportCount*				=   9;
	ParseIDPush*						= 10;
	ParseIDPop*						= 11;
	
	
	(*enum for local item parsing*)
	ParseIDUsage*						=   0;
	ParseIDUsageMinimum*				=   1;
	ParseIDUsageMaximum*			=   2;
	ParseIDDesignatorIndex*			=   3;
	ParseIDDesignatorMinimum*		=   4;
	ParseIDDesignatorMaximum*		=   5;
	ParseIDStringIndex* 				=   7;
	ParseIDStringMinimum*				=   8;
	ParseIDStringMaximum*			=   9;
	ParseIDDelimiter*					= 10;
	
	(*Main state*)
	
	ParseIDDataConstant*				=  0;
	ParseIDArrayVariable*				=  1;
	ParseIDAbsoluteRelative*			=  2;
	ParseIDNoWrapWrap*				=  3;
	ParseIDLinearNonLinear	*			=  4; 
	ParseIDPreferdStateNoPreferd*		=  5;
	ParseIDNoNullPositionNullState*	=  6;
	ParseIDNonVolatileVolatile*			=  7;
	ParseIDBitFieldBufferedByte*		=  8;
	
(* print out eight empty spaces
 * 	param: 	level		the number of times to print out 8 empty spaces
 *)	
PROCEDURE PrintLevel(level:LONGINT);
VAR i : LONGINT;
BEGIN
	IF(level > 0) THEN
		FOR i:=0 TO (level - 1) DO
			AosOut.String("        ");
		END;
	END;
END PrintLevel;

(* print main item
 * 	param: 	bTag		tag 
 *			bSize		size to read data
 *			data		data appended to tag
 *			itemNr		number of items already parsed + 1
 *			depth		the depth's subcollection (recursively)
 *)
PROCEDURE ParseMainItem*(bTag, bSize, data, itemNr, depth: LONGINT);
VAR dataAsSet : SET;
BEGIN
	(*hack for better layout; detect the end collection bTag*)
	IF (bTag=0CH) THEN
		DEC(depth);
	END;
	PrintLevel(depth);
	
	dataAsSet := SYSTEM.VAL(SET, data);
	CASE bTag OF
		8H: AosOut.String("Input (");
			IF (0 IN dataAsSet) THEN AosOut.String("Constant, ")		ELSE AosOut.String("Data, ")			END;
			IF (1 IN dataAsSet) THEN AosOut.String("Variable, ")		ELSE AosOut.String("Array, ")			END;
			IF (2 IN dataAsSet) THEN AosOut.String("Relative, ")		ELSE AosOut.String("Absolute, ")		END;
			IF (3 IN dataAsSet) THEN AosOut.String("Wrap, ") 		ELSE AosOut.String("No Wrap, ")		END;
			IF (4 IN dataAsSet) THEN AosOut.String("Non Linear, ") 	ELSE AosOut.String("Linear, ")			END;
			IF (5 IN dataAsSet) THEN AosOut.String("No Preferred, ") ELSE AosOut.String("Preferred State, ")	END;
			IF (6 IN dataAsSet) THEN AosOut.String("Null State") 	ELSE AosOut.String("No Null Position ")	END;
			IF (7 IN dataAsSet) THEN (*reserved*) 					ELSE (*reserved*) 						END;
			IF bSize > 1 THEN
				IF (8 IN dataAsSet) THEN AosOut.String(", Buffered Bytes"); ELSE AosOut.String(", Bit Field"); END;
				(*As described in USB HidDescription p.28 bits 9-31 are reserved*)
			END;
		|9H: AosOut.String("Output(");
			IF (0 IN dataAsSet) THEN AosOut.String("Constant, ") 	ELSE AosOut.String("Data, ")			END;
			IF (1 IN dataAsSet) THEN AosOut.String("Variable, ") 		ELSE AosOut.String("Array, ") 			END;
			IF (2 IN dataAsSet) THEN AosOut.String("Relative, ") 		ELSE AosOut.String("Absolute, ") 		END;
			IF (3 IN dataAsSet) THEN AosOut.String("Wrap, ") 		ELSE AosOut.String("No Wrap, ");		END;
			IF (4 IN dataAsSet) THEN AosOut.String("Non Linear, ") 	ELSE AosOut.String("Linear, ")			END;
			IF (5 IN dataAsSet) THEN AosOut.String("No Preferred, ") ELSE AosOut.String("Preferred State, ") 	END;
			IF (6 IN dataAsSet) THEN AosOut.String("Null State, ") 	ELSE AosOut.String("No Null Position, ")	END;
			IF (7 IN dataAsSet) THEN AosOut.String("Volatile") 		ELSE AosOut.String("Non Volatile") 		END;
			IF bSize > 1 THEN
				IF (8 IN dataAsSet) THEN AosOut.String(", Buffered Bytes") ELSE AosOut.String(", Bit Field") END;
				(*As described in USB HidDescription p.28 bits 9-31 are reserved*)
			END;
		|0BH: AosOut.String("Feature(");
			IF (0 IN dataAsSet) THEN AosOut.String("Constant, ") 	ELSE AosOut.String("Data, "); 			END;
			IF (1 IN dataAsSet) THEN AosOut.String("Variable, ") 		ELSE AosOut.String("Array, ") 			END;
			IF (2 IN dataAsSet) THEN AosOut.String("Relative, ") 		ELSE AosOut.String("Absolute, ") 		END;
			IF (3 IN dataAsSet) THEN AosOut.String("Wrap, ") 		ELSE AosOut.String("No Wrap, ") 		END;
			IF (4 IN dataAsSet) THEN AosOut.String("Non Linear, ") 	ELSE AosOut.String("Linear, ") 			END;
			IF (5 IN dataAsSet) THEN AosOut.String("No Preferred, ")	ELSE AosOut.String("Preferred State, ") 	END;
			IF (6 IN dataAsSet) THEN AosOut.String("Null State, ") 	ELSE AosOut.String("No Null Position, ") END;
			IF (7 IN dataAsSet) THEN AosOut.String("Volatile") 		ELSE AosOut.String("Non Volatile") 		END;
			IF bSize > 1 THEN
				IF (8 IN dataAsSet) THEN AosOut.String(", Buffered Bytes"); ELSE AosOut.String(", Bit Field") END;
				(*As described in USB HidDescription p.28 bits 9-31 are reserved*)
			END;
		|0AH: AosOut.String("Collection(");
			CASE data OF
				0H: AosOut.String("Physical");
				|1H: AosOut.String("Application");
				|2H: AosOut.String("Logical");
				|3H: AosOut.String("Report");
				|4H: AosOut.String("Named Array");
				|5H: AosOut.String("Usage Switch");
				|6H: AosOut.String("Usage Modifier");
				ELSE
					IF data < 8FH THEN 
						AosOut.String("RESERVED");
					ELSE 
						AosOut.String("Vendor-defined");
						(*non standard is treated as an error*)
					END;
			END;
		|0CH: AosOut.String("End Collection(");
	ELSE 
		AosOut.String("RESERVED(");
	END;
	AosOut.String(")"); 
	AosOut.Ln;
END ParseMainItem;
	
(* print global item
* 	param: 	bTag		tag
*			bSize		size to read data
*			data		data appended to tag
*			itemNr		number of items already parsed + 1
*			depth		the depth's subcollection (recursively)
*)
PROCEDURE ParseGlobalItem*( bTag, bSize, data, itemNr, depth: LONGINT);
VAR
BEGIN
	PrintLevel(depth);
	CASE bTag OF
		0H: AosOut.String("Usage Page (");
			CASE data OF
				(*REFERENCE: p. 4 HID Usage Tables*)
				0H: 
					AosOut.String("Undefined");
				|1H: AosOut.String("Generic Desktop Controls");
				|2H: AosOut.String("Simulation Controls");
				|3H: AosOut.String("VR Controls");
				|4H: AosOut.String("Sport Controls ");
				|5H: AosOut.String("Game Controls");
				|6H: AosOut.String("Generic Device Controls");
				|7H: AosOut.String("Keyboard/Keypad");
				|8H: AosOut.String("LEDs");
				|9H: AosOut.String("Button");
				|0AH: AosOut.String("Ordinal");
				|0BH: AosOut.String("Telephony");
				|0CH: AosOut.String("Consumer");
				|0DH: AosOut.String("Digitizer");
				|0EH: AosOut.String("Reserved");
				|0FH: AosOut.String("PID Page");
				|10H: AosOut.String("Unicode");
				(*
				|11H: AosOut.String("Reserved");
				|12H: AosOut.String("Reserved");
				|13H: AosOut.String("Reserved");
				*)
				|14H: AosOut.String("Alphanumeric Display");
				(* from 15h tol 3fH 
				|15H-3fH: AosOut.String("Reserved")*)
				|40: AosOut.String("Medical Instruments");
				(* from 41H tol 7fH 
				|41H-7fH: AosOut.String("Reserved")*)
				|81H: AosOut.String("Monitor pages");
				|82H: AosOut.String("Monitor pages");
				|83H: AosOut.String("Monitor pages");
				|84H: AosOut.String("Power pages");
				|85H: AosOut.String("Power pages");
				|86H: AosOut.String("Power pages");
				|87H: AosOut.String("Power pages");
				(* from 88H tol 8BH 
				|41H-7fH: AosOut.String("Reserved")*)
				|8CH: AosOut.String("Bar Code Scanner page");
				|8DH: AosOut.String("Scale page");
				|8EH: AosOut.String("Magnetic Stripe reading (MSR) Devices");
				|8FH: AosOut.String("Reserved Point of Sale pages");
				ELSE
					 AosOut.String("Reserved("); AosOut.Int(data,0); AosOut.String(")");
			END;
		|1H: AosOut.String("Logical Minimum (");
			AosOut.Int(data,0);
		|2H: AosOut.String("Logical Maximum(");
			AosOut.Int(data,0);
		|3H: AosOut.String("Physical Minimum (");
			AosOut.Int(data,0);
		|4H: AosOut.String("Physical Maximum(");
			AosOut.Int(data,0);
		|5H: AosOut.String("Unit Exponent(");
			AosOut.Int(data,0);
		|6H: AosOut.String("Unit(");
			AosOut.Int(data,0);
		|7H: AosOut.String("Report Size(");
			AosOut.Int(data,0);
		|8H: AosOut.String("Report ID(");
			AosOut.Int(data,0);
		|9H: AosOut.String("Report Count (");
			AosOut.Int(data,0);
		|10: AosOut.String("Push(");
		|11: AosOut.String("Pop (");
		ELSE 
			AosOut.String("Reserved(");
		END;
	AosOut.String(")");
	AosOut.Ln;
END ParseGlobalItem;		
	
(*print local item
 * 	param: 	bTag		tag
 *			bSize		size to read data
 *			data		data appended to tag
 *			itemNr		number of items already parsed + 1
 *			depth		the depth's subcollection (recursively)
 *)
PROCEDURE ParseLocalItem*(bTag, bSize, data,  itemNr, depth, usagePage: LONGINT);
BEGIN
	PrintLevel(depth);
	CASE bTag OF
		0H:	IF (data DIV 10000H>0) THEN
				AosOut.String("UsagePage("); AosUsbHidUP.PrintUsagePageName(data DIV 10000H); AosOut.String(") ");
			END;
			AosOut.String("Usage(");
			AosUsbHidUP.PrintUsagePage(usagePage, data);
		|1H: IF (data DIV 10000H>0) THEN
				AosOut.String("UsagePage("); AosUsbHidUP.PrintUsagePageName(data DIV 10000H); AosOut.String(") ");
			END;
			AosOut.String("Usage Minimum(");
			AosOut.Int(data MOD 10000H,0);
		|2H: IF (data DIV 10000H>0) THEN
				AosOut.String("UsagePage("); AosUsbHidUP.PrintUsagePageName(data DIV 10000H); AosOut.String(") ");
			END;
			AosOut.String("Usage Maximum(");
			AosOut.Int(data MOD 10000H,0);
		|3H: AosOut.String("Designator Index(");
			AosOut.Int(data,0);
		|4H: AosOut.String("Designator Minimum(");
			AosOut.Int(data,0);
		|5H: AosOut.String("Designator Maximum(");
			AosOut.Int(data,0);
		(*|6H: (*RESERVED*)*)
		|7H: AosOut.String("String Index(");
			AosOut.Int(data,0);
		|8H: AosOut.String("String Minimum(");
			AosOut.Int(data,0);
		|9H: AosOut.String("String Maximum(");
			AosOut.Int(data,0);
		|0AH: AosOut.String("Delimiter(");
			CASE data OF
				0: AosOut.String("open set)");
				|1H: AosOut.String("close set)");
				ELSE (*NOT DEFINED*)
			END;
		ELSE AosOut.String("RESERVED");
	END;
	AosOut.String(")");
	AosOut.Ln;
END ParseLocalItem;

END AosUsbHidParserExt.

S.Free AosUsbHidParserExt~