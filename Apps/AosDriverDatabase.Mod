MODULE AosDriverDatabase; (** AUTHOR: "staubesv"; PURPOSE: "Function-to-driver mapping for PCI & USB functions" *)
(**
 * Both the PCI and the Universal Serial Bus support Plug'n'Play. Besides other mechanisms, this implies the ability to
 * automatically map functions to drivers, i.e. locating an appropriate device driver for a given PCI or USB function. Also, both
 * busses support device-specific as well as class-specific drivers. The latter are adaptive device drivers that can be used for a 
 * device class.
 * Device-specific drivers are mapped using an unique Vendor ID / Device ID pair. Class-specific drivers can be mapped by
 * inspecting the Class/Subclass/Protocol numbers provided by the device. 
 * This module provides function-to-driver mapping for USB and PCI functions. Clients can use the InstallDeviceDriver and 
 * InstallClassDriver procedures to ask the driver database software for installing an appropriate driver for a given device.
 * Actually, it does nothing more than look up a command in the driver database and, if found, exexute it.
 * The actual device driver that is installed via command execution will typically enumerate the bus and look for
 * appropriate devices for itself. This is redundant but has the advantage that the driver database software itself
 * remains a fully optional feature - it's not a must to use it.
 * The driver lookup and install service is only functional if AosDriverDatabase.enabled is TRUE. This field can be controlled
 * by using the exported Enable/Disable commands and the "HardwareDetection" variable in the boot table. This enables the 
 * user to turn off automatic hardware detection if it causes the system to fail booting - just press the scrolllock key to enter to 
 * boot menu and type "HardwareDetection=0" to disable the automatic hardware detection.
 *
 * Interface:
 *	InstallDeviceDriver*(type, vendorID, deviceID, deviceRevision) : BOOLEAN
 *	InstallClassDriver*(type, class, subclass, protocol, revision) : BOOLEN
 *
 * Commands:
 *	AosDriverDatabase.Enable ~					Enable service
 *	AosDriverDatabase.Disable ~				Disable service
 *	AosDriverDatabase.ShowCommandHistory ~	Show list of executed commands since last time Enable has been called (Debug)
 *
 * History:
 *
 *	15.09.2005	First release (staubesv)
 *	07.12.2005	Integrated AosUsbDriverLoader, changed log output (staubesv)
 *)
 
IMPORT
	AosOut, AosFS, AosModules, AosBoot, AosCommands, Utilities, AosUsbDriverLoader,
	XML, XMLScanner, XMLParser, XMLObjects;

CONST
	(** Driver Types *)
	PCI* = 0;
	USB* = 1;
	
	(* Flags *)	
	NonBlocking = 1; 
	Continue = 2;
	
	(* File that contains PCI/USB function->Drivermodule name mappings *)
	DriverDatabase = "AosDriverDatabase.XML"; 
	
	(* Names of XML elements and XML attribtues *)
	XmlPciSection = "PCI";
	XmlUsbSection = "USB";
	XmlDeviceSpecific = "deviceSpecific";
	XmlClassSpecific = "classSpecific";
	
	XmlVendor = "vendor";
	XmlDevice = "device";
	XmlId = "id";
	XmlNumber = "nbr";
	XmlName = "name";

	XmlRevision = "revision";
	XmlClass = "class";
	XmlSubclass = "subclass";
	XmlProtocol = "protocol";
	XmlFlags = "flags";
	
	XmlDontCare = "all";

	ChNonBlocking = "N";
	ChContinue = "C";
	
	(* How many commands may be concatenated using the ";" seperator? *)
	MaxCommandsLen = 5; 
		
	Verbose = TRUE;
	Trace = FALSE;
	
TYPE
	Driver* = POINTER TO RECORD
		commands- : XML.String;
		flags- : SET;
	END;

	DeviceDriver* = POINTER TO RECORD (Driver)
		vendor- : XML.String;
		device- : XML.String;
	END;
	
	ClassDriver* = POINTER TO RECORD (Driver)
		class-, subclass-, protocol- : XML.String;
	END;
	
	CommandHistory = POINTER TO ARRAY OF XML.String;

VAR
	database : XML.Element;
	config : ARRAY 8 OF CHAR;
	enabled- : BOOLEAN; 			(* Are clients allowed to query the driver database? *)
	cmdHistory : CommandHistory; 	(* List of commands that have been executed *)
	cmdIndex : LONGINT; 			(* Next free index of cmdHistory *)

(* Compare the specified XML attritbute value to the specified integer value *)
PROCEDURE Matches(driver : XML.Element; attribute : ARRAY OF CHAR; value : LONGINT) : BOOLEAN;
VAR string : XML.String; number, res : LONGINT;
BEGIN
	ASSERT(driver # NIL);
	string := driver.GetAttributeValue(attribute);
	IF string # NIL THEN
		IF ~Utilities.Match(string^, XmlDontCare) THEN
			Utilities.HexStrToInt(string^, number, res);
			IF res = Utilities.Ok THEN
				RETURN number = value;
			END;
		ELSE
			RETURN TRUE;
		END;
	END;
	RETURN FALSE;
END Matches;

PROCEDURE GetFlags(driver : XML.Element) : SET;
VAR flags : SET; string : XML.String; i : LONGINT;
BEGIN
	ASSERT(driver # NIL);
	string := driver.GetAttributeValue(XmlFlags);
	IF string # NIL THEN
		LOOP
			IF string[i] = ChNonBlocking THEN INCL(flags, NonBlocking) 
			ELSIF string[i] = ChContinue THEN INCL(flags, Continue);
			END;
			INC(i);
			IF i > LEN(string) - 1 THEN EXIT; END;
		END;
	END;
	RETURN flags;	
END GetFlags;

(* Returns NIL if module name not found *)
PROCEDURE GetCommands(driver : XML.Element) :  XML.String;
VAR enumerator : XMLObjects.Enumerator; string : XML.String; ptr : PTR;
BEGIN
	enumerator := driver.GetContents();
	WHILE enumerator.HasMoreElements() DO
		ptr := enumerator.GetNext();
		IF ptr IS XML.ArrayChars THEN 
			string := ptr(XML.ArrayChars).GetStr();
			IF string # NIL THEN
				Utilities.Trim(string^, ' ');
			END;
		END;
	END;
	RETURN string;
END GetCommands;

PROCEDURE GetName(element : XML.Element) : XML.String;
VAR attr : XML.Attribute; string : XML.String;
BEGIN
	IF element # NIL THEN
		attr := element.GetAttribute(XmlName);
		IF attr # NIL THEN
			string := attr.GetValue();
		END;		
	END;
	RETURN string;
END GetName;

PROCEDURE GetSection(type : LONGINT) : XML.Element;
BEGIN
	IF database # NIL THEN
		IF type = PCI THEN RETURN GetSubSection(database, XmlPciSection, "", 0);
		ELSIF type = USB THEN RETURN GetSubSection(database, XmlUsbSection, "", 0);
		ELSE
		END;
	END;
	RETURN NIL;
END GetSection;

(** Find a XML element with the name <elemName> that has <parent> as parent. If attrName # "", the XML element must
	have the attribute <attrName> and its value must match <attrValue> (number). *)
PROCEDURE GetSubSection(parent : XML.Element; elemName, attrName : ARRAY OF CHAR; attrValue : LONGINT) : XML.Element;
VAR element : XML.Element; enumerator : XMLObjects.Enumerator; string : XML.String; p : PTR;
BEGIN
	IF parent # NIL THEN
		enumerator := parent.GetContents();
		WHILE enumerator.HasMoreElements() DO
			p := enumerator.GetNext();
			IF p IS XML.Element THEN
				element := p (XML.Element); string := element.GetName();
				IF (string # NIL) & (string^ = elemName) THEN
					IF (attrName = "") OR Matches(element, attrName, attrValue) THEN
						RETURN element;
					END;
				END;
			END;
		END;
	END;
	RETURN NIL;	
END GetSubSection;

PROCEDURE ResizeCmdHistory;
VAR temp : CommandHistory; i : LONGINT;
BEGIN (* Must hold module lock *)
	NEW(temp, 2*LEN(cmdHistory));
	FOR i := 0 TO cmdIndex-1 DO
		temp[i] := cmdHistory[i];
	END;
	cmdHistory := temp;
END ResizeCmdHistory;

PROCEDURE HasBeenExecuted(cmd : XML.String) : BOOLEAN;
VAR i : LONGINT; result : BOOLEAN;
BEGIN (* Must hold module lock *)
	IF cmdIndex > 0 THEN 
		LOOP
			IF (cmd # NIL) & (cmdHistory[i] # NIL) & Utilities.Match(cmd^, cmdHistory[i]^) THEN 
				result := TRUE;
				EXIT;
			END;
			INC(i);
			IF (i >= cmdIndex) OR (i >= LEN(cmdHistory)) THEN EXIT; END;
		END;
	END;
	RETURN result;		
END HasBeenExecuted;

PROCEDURE LoadDriver(driver : Driver) : BOOLEAN;
VAR 
	commands : Utilities.StringArray;
	m : AosModules.Module; proc : AosModules.CommandParProc;
	flags : SET; msg : ARRAY 256 OF CHAR; res : LONGINT;
	i : LONGINT;
BEGIN {EXCLUSIVE}
	res := -1;
	IF (driver # NIL) & (driver.commands # NIL) THEN
		commands := Utilities.Split(driver.commands^, ";");
		IF (driver.flags * {NonBlocking} = {}) OR (LEN(commands) > 1) THEN flags := {AosCommands.Wait} ELSE flags := {} END;
		i := 0;
		LOOP
			Utilities.TrimWS(commands[i]^);
			IF (commands[i]^ # "") & ~HasBeenExecuted(commands[i]) THEN
				(* Add command to execution history *)
				IF cmdIndex >= LEN(cmdHistory) THEN ResizeCmdHistory; END;
				cmdHistory[cmdIndex] := commands[i]; INC(cmdIndex);
				(* Execute command *)
				AosCommands.Call(commands[i]^, flags, res, msg);
				IF res # 0 THEN
					AosOut.Enter; AosOut.String("Could not load driver "); AosOut.String(driver.commands^);
					AosOut.String(" (res: "); AosOut.Int(res, 0); AosOut.String(", "); AosOut.String(msg); AosOut.String(")"); AosOut.Exit;
					IF driver.flags * {Continue} = {} THEN EXIT END; (* Abort execution of command list *)
				ELSIF Trace THEN
					AosOut.Enter; AosOut.String("Executing "); AosOut.String(driver.commands^); AosOut.String(" ");
					IF driver.flags * {NonBlocking} # {} THEN AosOut.String("[Non-Blocking]"); ELSE AosOut.String("[Blocking]"); END; AosOut.Exit;
				END;
			END;
			INC(i);
			IF i >= LEN(commands) THEN EXIT END;
		END;
	END;
	RETURN res = 0;
END LoadDriver;

PROCEDURE GetDeviceSpecific*(type, vendorId, deviceId, revision : LONGINT) : DeviceDriver;
VAR section, deviceSpecific, vendor, device : XML.Element; dd : DeviceDriver;
BEGIN
	section := GetSection(type);
	IF section # NIL THEN
		deviceSpecific := GetSubSection(section, XmlDeviceSpecific, "", 0);
		IF deviceSpecific # NIL THEN
			vendor := GetSubSection(deviceSpecific, XmlVendor, XmlId, vendorId);
			IF vendor # NIL THEN
				device := GetSubSection(vendor, XmlDevice, XmlId, deviceId);
				IF device # NIL THEN
					IF Matches(device, XmlRevision, revision) THEN
						NEW(dd);
						dd.vendor := GetName(vendor); dd.device := GetName(device);
						dd.commands := GetCommands(device); dd.flags := GetFlags(device);
					END;
				END;
			END;
		END;
	END;
	RETURN dd;
END GetDeviceSpecific;

PROCEDURE GetClassSpecific*(type, classNbr, subclassNbr, protocolNbr, revision : LONGINT) : ClassDriver;
VAR section, classSpecific, class, subclass, protocol : XML.Element; cd : ClassDriver;
BEGIN
	section := GetSection(type);
	IF section # NIL THEN
		classSpecific := GetSubSection(section, XmlClassSpecific, "", 0);
		IF classSpecific # NIL THEN
			class := GetSubSection(classSpecific, XmlClass, XmlNumber, classNbr);
			IF class # NIL THEN
				subclass := GetSubSection(class, XmlSubclass, XmlNumber, subclassNbr);
				IF subclass # NIL THEN
					protocol := GetSubSection(subclass, XmlProtocol, XmlNumber, protocolNbr);
					IF protocol # NIL THEN
						IF Matches(protocol, XmlRevision, revision) THEN
							NEW(cd);
							cd.class := GetName(class); cd.subclass := GetName(subclass); cd.protocol := GetName(protocol);
							cd.commands := GetCommands(protocol); cd.flags := GetFlags(protocol);
						END;
					END;
				END;
			END;
		END;
	END;
	RETURN cd;
END GetClassSpecific;

(** Look for a device driver of the specified type. If found, install it. *)
PROCEDURE InstallDeviceDriver*(type, vendorID, deviceID, revision : LONGINT) : BOOLEAN;
VAR dd : DeviceDriver;
BEGIN
	IF ~enabled THEN RETURN FALSE; END;
	dd := GetDeviceSpecific(type, vendorID, deviceID, revision);	
	IF dd # NIL THEN
		IF Verbose THEN
			AosOut.Enter;
			AosOut.String("AosDriverDatabase: Loading ");
			IF type = PCI THEN AosOut.String("PCI");
			ELSIF type = USB THEN AosOut.String("USB");
			ELSE AosOut.String("UNKNOWN");
			END;
			AosOut.String(" device driver for ");
			IF (dd.vendor # NIL) OR (dd.device # NIL) THEN
				IF dd.vendor # NIL THEN AosOut.String(dd.vendor^); AosOut.Char(" "); END;
				IF dd.device # NIL THEN AosOut.String(dd.device^); END;
			ELSE
				AosOut.String("Unnamed Device");
			END;
			AosOut.Exit;
		END;
		IF ~LoadDriver(dd) THEN dd := NIL; END;
	END;
	RETURN dd # NIL;	
END InstallDeviceDriver;

(** Look for a class driver of the specified type. If found, install it. *)
PROCEDURE InstallClassDriver*(type, class, subclass, protocol, revision : LONGINT) : BOOLEAN;
VAR cd : ClassDriver;
BEGIN
	IF ~enabled THEN RETURN FALSE; END;
	cd := GetClassSpecific(type, class, subclass, protocol, revision);
	IF cd # NIL THEN
		IF Verbose THEN
			AosOut.Enter;
			AosOut.String("AosDriverDatabase: Loading ");
			IF type = PCI THEN AosOut.String("PCI class driver for ");
				IF (cd.class # NIL) OR (cd.subclass # NIL) OR (cd.protocol # NIL) THEN
					IF cd.class # NIL THEN AosOut.String(cd.class^); END;
					IF cd.subclass # NIL THEN AosOut.String(", "); AosOut.String(cd.subclass^); END;
					IF cd.protocol # NIL THEN AosOut.String(", "); AosOut.String(cd.protocol^); END;					
				ELSE
					AosOut.String("Unnamed Class");
				END;
			ELSIF type = USB THEN 
				AosOut.String("USB ");
				IF cd.class # NIL THEN AosOut.String(cd.class^); ELSE AosOut.String("Unknown"); END;
				AosOut.String(" class driver");
			ELSE AosOut.String("UNKNOWN class driver");
			END;
			AosOut.Exit;
		END;
		IF ~LoadDriver(cd) THEN cd := NIL; END;
	END;
	RETURN cd # NIL;	
END InstallClassDriver;

(* Returns NIL in error case *)
PROCEDURE LoadDriverDatabase() : XML.Element;
VAR 
	scanner : XMLScanner.Scanner; parser : XMLParser.Parser; document : XML.Document;
	in : AosFS.Reader; f : AosFS.File; 
BEGIN
	f := AosFS.Old(DriverDatabase);
	IF f # NIL THEN 
		AosFS.OpenReader(in, f, 0);
		IF in # NIL THEN
			NEW(scanner, in); NEW(parser, scanner); 
			document := parser.Parse();
			IF document # NIL THEN
				RETURN document.GetRoot();
			END;
		END;		
	END; 
	AosOut.String("AosDriverDatabase: Could not load driver database "); AosOut.String(DriverDatabase); AosOut.Ln;
	RETURN NIL;
END LoadDriverDatabase;

(** Exported commands *)

(** Enable driver lookup/installation service *)
PROCEDURE Enable*(par : ANY) : ANY;
BEGIN {EXCLUSIVE}
	database := LoadDriverDatabase(); (* force reloading *)
	IF database # NIL THEN 
		NEW(cmdHistory, 10); cmdIndex := 0;
		AosUsbDriverLoader.SetLoaders(InstallDeviceDriver, InstallClassDriver);
		enabled := TRUE; 
		IF Verbose THEN AosOut.String("AosDriverDatabase: Enabled driver lookup service."); AosOut.Ln; END;
	END;
	RETURN NIL
END Enable;

(** Disable driver lookup/installation service *)
PROCEDURE Disable*(par : ANY) : ANY;
BEGIN {EXCLUSIVE}
	AosUsbDriverLoader.SetLoaders(NIL, NIL);
	enabled := FALSE;
	IF Verbose THEN AosOut.String("AosDriverDatabase: Disabled driver lookup service."); AosOut.Ln; END;
	RETURN NIL
END Disable;

(** Show list of all executed commands in order of their execution *)
PROCEDURE ShowCommandHistory*(ptr : PTR) : PTR;
VAR i : LONGINT;
BEGIN {EXCLUSIVE}
	AosOut.String("Driver Database command execution history:"); AosOut.Ln;
	IF (cmdHistory # NIL) & (cmdIndex > 0)  THEN
		FOR i := 0 TO cmdIndex-1 DO
			AosOut.Int(i+1, 2); AosOut.String(": "); AosOut.String(cmdHistory[i]^); AosOut.Ln;
		END;		
	ELSE
		AosOut.String("No commands executed."); AosOut.Ln;
	END;
	RETURN NIL;
END ShowCommandHistory;

BEGIN
	AosBoot.GetConfig("HardwareDetection", config);
	IF (config = "") OR (config[0] = "1") THEN
		database := LoadDriverDatabase();
		IF database # NIL THEN
			NEW(cmdHistory, 10); cmdIndex := 0;
			AosUsbDriverLoader.SetLoaders(InstallDeviceDriver, InstallClassDriver);
			enabled := TRUE;
		END;
	ELSE
		AosOut.String("AosDriverDatabase: Hardware detection is disabled."); AosOut.Ln;
	END;
END AosDriverDatabase.