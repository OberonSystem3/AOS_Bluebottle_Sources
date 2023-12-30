MODULE AosInitNet; (** AUTHOR "mvt"; PURPOSE "IP interface initialization and configuration"; *)

IMPORT AosBoot, AosFS, AosOut, AosModules, AosPlugins, Utilities, XML, XMLObjects, XMLScanner, 
		 XMLParser,
		 AosNet, AosIP, AosICMP, AosUDP, AosDNS, AosTCP, AosDHCP, AosIPv4, AosIPv6; (* load all *)

CONST
	(** Error Codes *)
	Ok* = 0;
	NotFound* = 4001;
	NoConfigFile* = 4002;
	ConfigFileNotValid* = 4003;
	
	MaxNofInterfaces* = 10; (** Interface numbers vom 0 to 9 are accepted in AosBoot config *)


TYPE
	(* Interface and router config *)
	Config = POINTER TO RECORD
		interfaceConfigs: InterfaceConfig;
		routerConfigs: AosIPv6.RouterConfig;
		IPForwarding: BOOLEAN;
		EchoReply: BOOLEAN;
		PreferredProtocol: LONGINT;
		AutoNetConfigV4: BOOLEAN;
		AutoNetConfigV6: BOOLEAN;
		AutoNetConfigV6DNS: ARRAY AosDNS.MaxNofServer OF AosIP.Adr;
	END;
	
		
	(* A configuraton of a interface *)
	InterfaceConfig = POINTER TO RECORD
		Device: AosPlugins.Name;
		Protocol: LONGINT;
		Name: AosIP.Name;
		Domain: Utilities.String;
		DHCP: BOOLEAN;
		LocalAdr: AosIP.Adr;
		Gateway: AosIP.Adr;
		Netmask: AosIP.Adr;
		Prefix: AosIP.Adr;
		DNS: ARRAY AosDNS.MaxNofServer OF AosIP.Adr;
		next: InterfaceConfig;
	END;
	
TYPE
	(* Active object that runs DHCP on the specified interface. *)
	RunnerDHCP = OBJECT
		VAR
			int: AosIP.Interface;
			res: LONGINT;
			
		PROCEDURE &Constr(int: AosIP.Interface);
		BEGIN
			ASSERT(int # NIL);
			SELF.int := int;
		END Constr;
		
	BEGIN {ACTIVE}
		AosDHCP.RunDHCP(int, res);
		IF res = 0 THEN
			AosIP.OutInterface(int);
		END;
	END RunnerDHCP;


VAR
	hasXMLErrors: BOOLEAN;
	
	(* temporary variables used in module body *)
	res: LONGINT;
	s: ARRAY 3 OF CHAR;


(* Error output for XML parser *)
PROCEDURE Error(pos, line, row: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	AosOut.String("Parse error in NetInit.XML at pos "); AosOut.Int(pos, 5); AosOut.String(" in line "); AosOut.Int(line, 5); 
	AosOut.String(" row "); AosOut.Int(row, 5); AosOut.String(" - "); AosOut.String(msg); AosOut.Ln;
	hasXMLErrors := TRUE
END Error;


(**Get interface configurations from NetInit.XML for the specified device. *)
PROCEDURE GetConfig(devName: ARRAY OF CHAR; VAR res:LONGINT): Config;
VAR
	netConfigElem: XML.Element;
	elem: XML.Element;
	elemStr: Utilities.String;
	config: Config;
	interfaceConfig: InterfaceConfig;
	routerConfig: AosIPv6.RouterConfig;
	prefixConfig: AosIPv6.PrefixConfig;
	file: AosFS.File;
	reader: AosFS.Reader;
	scanner: XMLScanner.Scanner;
	parser: XMLParser.Parser;
	doc: XML.Document;
	ipv4Elem: XML.Element;
	ipv6Elem: XML.Element;
	i: LONGINT;
	interfaceElems: XMLObjects.ArrayCollection;
	routerElems: XMLObjects.ArrayCollection;
	prefixElems: XMLObjects.ArrayCollection;
	dnsElems: XMLObjects.ArrayCollection;
	intElem: XML.Element;
	routerElem: XML.Element;
	prefixElem: XML.Element;
	interfaceNbr: LONGINT;
	routerNbr: LONGINT;
	prefixNbr: LONGINT;
	attribute: XML.Attribute;
	p: ANY;
	
	
	(** Get a section with a specific name *)
	PROCEDURE GetSection(elem: XML.Element; sectionName: ARRAY OF CHAR): XML.Element;
	VAR
		enum: XMLObjects.Enumerator;
		attribute: XML.Attribute;
		section: XML.Element;
		p: ANY;
		elemStr: Utilities.String;
		
	BEGIN
		IF elem # NIL THEN
			enum := elem.GetContents();
			(* Search for elements equal "childName"  *)
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS XML.Element THEN
					elemStr := p(XML.Element).GetName();							
					IF (elemStr^ = "Section") THEN
						attribute := p(XML.Element). GetAttribute("name");
						elemStr := attribute.GetValue();
						IF elemStr^ = sectionName THEN
							section := p(XML.Element);
						END;						
					END;
				END;
			END;
		END;
		
		RETURN section;	
	END GetSection;
	
	
	(** Sets a Boolean value from Setting of a section.
		If error is TRUE then hasXMLErrors is set to TRUE if child does not exist. *)
	PROCEDURE GetSettingBool(section: XML.Element; settingName: ARRAY OF CHAR; error: BOOLEAN; VAR bool: BOOLEAN);
	VAR
		nameAttr: XML.Attribute;
		valueAttr: XML.Attribute;
		nameStr: Utilities.String;
		valueStr: Utilities.String;
		elemStr: Utilities.String;
		settingFound: BOOLEAN;
		enum: XMLObjects.Enumerator;
		p: ANY;
		
	BEGIN
		settingFound := FALSE;
		
		IF section # NIL THEN
			enum := section.GetContents();
			(* Search for settings *)
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS (XML.Element) THEN
					elemStr := p(XML.Element).GetName();
					IF (elemStr^ = "Setting") THEN
						nameAttr := p(XML.Element).GetAttribute("name");
						valueAttr := p(XML.Element).GetAttribute("value");
						IF (nameAttr # NIL) & (valueAttr # NIL) THEN
							nameStr := nameAttr.GetValue();
							valueStr := valueAttr.GetValue();
							IF nameStr^ = settingName THEN
								Utilities.StrToBool(valueStr^, bool);
								settingFound := TRUE;
							END;						
						END;
					END;				
				END;
			END;
		ELSIF error THEN
			hasXMLErrors := TRUE;
		END;
		
		IF ~settingFound & error THEN
			hasXMLErrors := TRUE;
		END;
	END GetSettingBool;
	
	
	(** Sets a integer value from Setting of a section.
		If error is TRUE then hasXMLErrors is set to TRUE if child does not exist. *)
	PROCEDURE GetSettingInt(section: XML.Element; settingName: ARRAY OF CHAR; error: BOOLEAN; VAR int : LONGINT);
	VAR
		nameAttr: XML.Attribute;
		valueAttr: XML.Attribute;
		nameStr: Utilities.String;
		valueStr: Utilities.String;
		elemStr: Utilities.String;
		settingFound: BOOLEAN;
		enum: XMLObjects.Enumerator;
		p: ANY;
		
	BEGIN
		settingFound := FALSE;
		
		IF section # NIL THEN
			enum := section.GetContents();
			(* Search for settings *)
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS (XML.Element) THEN
					elemStr := p(XML.Element).GetName();
					IF (elemStr^ = "Setting") THEN
						nameAttr := p(XML.Element).GetAttribute("name");
						valueAttr := p(XML.Element).GetAttribute("value");
						IF (nameAttr # NIL) & (valueAttr # NIL) THEN
							nameStr := nameAttr.GetValue();
							valueStr := valueAttr.GetValue();
							IF nameStr^ = settingName THEN
								Utilities.StrToInt(valueStr^, int);
								settingFound := TRUE;
							END;						
						END;
					END;				
				END;
			END;
		ELSIF error THEN
			hasXMLErrors := TRUE;
		END;
		
		IF ~settingFound & error THEN
			hasXMLErrors := TRUE;
		END;
	END GetSettingInt;
	
	
	(** Sets a character array from Setting of a section.
		If error is TRUE then hasXMLErrors is set to TRUE if child does not exist. *)
	PROCEDURE GetSettingChars(section: XML.Element; settingName: ARRAY OF CHAR; error: BOOLEAN; VAR chars: ARRAY OF CHAR);
	VAR
		nameAttr: XML.Attribute;
		valueAttr: XML.Attribute;
		nameStr: Utilities.String;
		valueStr: Utilities.String;
		elemStr: Utilities.String;
		settingFound: BOOLEAN;
		enum: XMLObjects.Enumerator;
		p: ANY;
		
	BEGIN
		settingFound := FALSE;
		
		IF section # NIL THEN
			enum := section.GetContents();
			(* Search for settings *)
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS (XML.Element) THEN
					elemStr := p(XML.Element).GetName();
					IF (elemStr^ = "Setting") THEN
						nameAttr := p(XML.Element).GetAttribute("name");
						valueAttr := p(XML.Element).GetAttribute("value");
						IF (nameAttr # NIL) & (valueAttr # NIL) THEN
							nameStr := nameAttr.GetValue();
							valueStr := valueAttr.GetValue();
							IF nameStr^ = settingName THEN
								COPY(valueStr^, chars);
								settingFound := TRUE;
							END;						
						END;
					END;				
				END;
			END;
		ELSIF error THEN
			hasXMLErrors := TRUE;
		END;
		
		IF ~settingFound & error THEN
			hasXMLErrors := TRUE;
		END;
	END GetSettingChars;
	
	
	(** Sets a string from Setting of a section.
		If error is TRUE then hasXMLErrors is set to TRUE if child does not exist. *)
	PROCEDURE GetSettingString(section: XML.Element; settingName: ARRAY OF CHAR; error: BOOLEAN; VAR string: Utilities.String);
	VAR
		nameAttr: XML.Attribute;
		valueAttr: XML.Attribute;
		nameStr: Utilities.String;
		valueStr: Utilities.String;
		elemStr: Utilities.String;
		settingFound: BOOLEAN;
		enum: XMLObjects.Enumerator;
		p: ANY;
		
	BEGIN
		settingFound := FALSE;
		
		IF section # NIL THEN
			enum := section.GetContents();
			(* Search for settings *)
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS (XML.Element) THEN
					elemStr := p(XML.Element).GetName();
					IF (elemStr^ = "Setting") THEN
						nameAttr := p(XML.Element).GetAttribute("name");
						valueAttr := p(XML.Element).GetAttribute("value");
						IF (nameAttr # NIL) & (valueAttr # NIL) THEN
							nameStr := nameAttr.GetValue();
							valueStr := valueAttr.GetValue();
							IF nameStr^ = settingName THEN
								string := valueStr;
								settingFound := TRUE;
							END;						
						END;
					END;				
				END;
			END;
		ELSIF error THEN
			hasXMLErrors := TRUE;
		END;
		
		IF ~settingFound & error THEN
			hasXMLErrors := TRUE;
		END;
	END GetSettingString;
	
	
	(** Sets an address from Setting of a section.
		If error is TRUE then hasXMLErrors is set to TRUE if child does not exist. *)
	PROCEDURE GetSettingAdr(section: XML.Element; settingName: ARRAY OF CHAR; error: BOOLEAN; VAR adr: AosIP.Adr);
	VAR
		nameAttr: XML.Attribute;
		valueAttr: XML.Attribute;
		nameStr: Utilities.String;
		valueStr: Utilities.String;
		elemStr: Utilities.String;
		settingFound: BOOLEAN;
		enum: XMLObjects.Enumerator;
		p: ANY;
		
	BEGIN
		settingFound := FALSE;
		
		IF section # NIL THEN
			enum := section.GetContents();
			(* Search for settings *)
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS (XML.Element) THEN
					elemStr := p(XML.Element).GetName();
					IF (elemStr^ = "Setting") THEN
						nameAttr := p(XML.Element).GetAttribute("name");
						valueAttr := p(XML.Element).GetAttribute("value");
						IF (nameAttr # NIL) & (valueAttr # NIL) THEN
							nameStr := nameAttr.GetValue();
							valueStr := valueAttr.GetValue();
							IF nameStr^ = settingName THEN
								adr := AosIP.StrToAdr(valueStr^);
								settingFound := TRUE;
							END;						
						END;
					END;				
				END;
			END;
		ELSIF error THEN
			hasXMLErrors := TRUE;
		END;
		
		IF ~settingFound & error THEN
			hasXMLErrors := TRUE;
		END;
	END GetSettingAdr;
	
	
	(** Get a list of settings with specific name*)
	PROCEDURE GetSettings(elem: XML.Element; settingName: ARRAY OF CHAR): XMLObjects.ArrayCollection;
	VAR
		settingCol: XMLObjects.ArrayCollection;
		enum: XMLObjects.Enumerator;
		p: ANY;
		elemName: Utilities.String;
		nameAttr: XML.Attribute;
		nameStr: Utilities.String;
		
	BEGIN
		IF elem # NIL THEN
			NEW(settingCol);
			enum := elem.GetContents();
			(* Search for settings equal "childName"  *)
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS XML.Element THEN
					elemName := p(XML.Element).GetName();
					IF elemName^ = "Setting" THEN
						nameAttr := p(XML.Element).GetAttribute("name");
						IF nameAttr # NIL THEN
							nameStr := nameAttr.GetValue();
							IF nameStr^ = settingName THEN
								settingCol.Add(p(XML.Element));
							END;
						END;
					END;
				END;
			END;
		END;
		RETURN settingCol;	
	END GetSettings;
	
	
	(** Get a section with a specific name *)
	PROCEDURE GetSections(elem: XML.Element; sectionName: ARRAY OF CHAR): XMLObjects.ArrayCollection;
	VAR
		sectionCol: XMLObjects.ArrayCollection;
		enum: XMLObjects.Enumerator;
		p: ANY;
		elemName: Utilities.String;
		nameAttr: XML.Attribute;
		nameStr: Utilities.String;
		
	BEGIN
		IF elem # NIL THEN
			NEW(sectionCol);
			enum := elem.GetContents();
			(* Search for sections equal "childName"  *)
			WHILE enum.HasMoreElements() DO
				p := enum.GetNext();
				IF p IS XML.Element THEN
					elemName := p(XML.Element).GetName();
					IF elemName^ = "Section" THEN
						nameAttr := p(XML.Element).GetAttribute("name");
						IF nameAttr # NIL THEN
							nameStr := nameAttr.GetValue();
							IF nameStr^ = sectionName THEN
								sectionCol.Add(p(XML.Element));
							END;
						END;
					END;
				END;
			END;
		END;
		RETURN sectionCol;	
	END GetSections;
	
	
	(* Read a IPv4 Interface *)
	PROCEDURE Readv4Interface;
	BEGIN
		interfaceElems := GetSections(ipv4Elem, "Interface");
		IF interfaceElems.GetNumberOfElements() # 0 THEN
			FOR interfaceNbr := 0 TO interfaceElems.GetNumberOfElements() - 1 DO					
				p := interfaceElems.GetElement(interfaceNbr);
				intElem :=p (XML.Element);
				(* init config *)
				NEW(interfaceConfig);
				(*init config *)
				FOR i := 0 TO LEN(interfaceConfig.DNS) - 1 DO
					interfaceConfig.DNS[i] := AosIP.NilAdr;
				END;
				interfaceConfig.Device[0] := 0X;
				interfaceConfig.Protocol := AosIP.IPv4;
				interfaceConfig.Name := "";
				interfaceConfig.Domain := NIL;
				interfaceConfig.DHCP := TRUE;
				interfaceConfig.LocalAdr := AosIP.NilAdr;
				interfaceConfig.Gateway := AosIP.NilAdr;
				interfaceConfig.Netmask := AosIP.NilAdr;
				interfaceConfig.Prefix := AosIP.NilAdr;
				
				(* Device *)
				GetSettingChars(intElem, "Device", TRUE, interfaceConfig.Device);
			
				(* Name *)
				GetSettingChars(intElem, "Name", TRUE, interfaceConfig.Name);
			
				(* Domain *)
				GetSettingString(intElem, "Domain", FALSE, interfaceConfig.Domain);
				
				(* DHCP *)
				GetSettingBool(intElem, "DHCP", FALSE, interfaceConfig.DHCP);
				
				(* LocalAdr *)
				GetSettingAdr(intElem, "LocalAdr", FALSE, interfaceConfig.LocalAdr);
				
				(* Gateway *)
				GetSettingAdr(intElem, "Gateway", FALSE, interfaceConfig.Gateway);
				
				(* Netmask *)
				GetSettingAdr(intElem, "Netmask", FALSE, interfaceConfig.Netmask);
				
				(* DNS *)
				dnsElems := GetSettings(intElem, "DNS");
				FOR i := 0 TO Utilities.Min(dnsElems.GetNumberOfElements(), AosDNS.MaxNofServer) - 1 DO
					p := dnsElems.GetElement(i);
					elem := p(XML.Element);
					attribute := elem.GetAttribute("value");
					IF attribute # NIL THEN
						elemStr := attribute.GetValue();
						IF elemStr # NIL THEN
							interfaceConfig.DNS[i] := AosIP.StrToAdr(elemStr^);
						END;						
					END;
				END;			
				
				(* IF configuration for right device save it *)
				IF (interfaceConfig # NIL) & (interfaceConfig.Device = devName) THEN
					interfaceConfig.next := config.interfaceConfigs;
					config.interfaceConfigs := interfaceConfig;
				END;
			END;
		END;
	END Readv4Interface;
	
	
	(* Read a IPv6 interface *)
	PROCEDURE Readv6Interface;
	BEGIN
		interfaceElems := GetSections(ipv6Elem, "Interface");
		IF interfaceElems.GetNumberOfElements() # 0 THEN
			FOR interfaceNbr := 0 TO interfaceElems.GetNumberOfElements() - 1 DO
				p := interfaceElems.GetElement(interfaceNbr);
				intElem :=p (XML.Element);
				(* init config *)
				NEW(interfaceConfig);
				(*init config *)
				FOR i := 0 TO LEN(interfaceConfig.DNS) - 1 DO
					interfaceConfig.DNS[i] := AosIP.NilAdr;
				END;
				interfaceConfig.Device[0] := 0X;
				interfaceConfig.Protocol := AosIP.IPv6;
				interfaceConfig.Name := "";
				interfaceConfig.Domain := NIL;
				interfaceConfig.DHCP := TRUE;
				interfaceConfig.LocalAdr := AosIP.NilAdr;
				interfaceConfig.Gateway := AosIP.NilAdr;
				interfaceConfig.Netmask := AosIP.NilAdr;
				interfaceConfig.Prefix := AosIP.NilAdr;
				
				(* Device *)
				GetSettingChars(intElem, "Device", TRUE, interfaceConfig.Device);
				
				(* Name *)
				GetSettingChars(intElem, "Name", TRUE, interfaceConfig.Name);
				
				(* Domain *)
				GetSettingString(intElem, "Domain", FALSE, interfaceConfig.Domain);
								
				(* DHCP *)
				GetSettingBool(intElem, "DHCP", FALSE, interfaceConfig.DHCP);
				
				(* LocalAdr *)
				GetSettingAdr(intElem, "LocalAdr", FALSE, interfaceConfig.LocalAdr);
				
				(*Prefix *)
				GetSettingAdr(intElem, "Prefix", FALSE, interfaceConfig.Prefix);
			
				(* DNS *)
				dnsElems := GetSettings(intElem, "DNS");
				FOR i := 0 TO Utilities.Min(dnsElems.GetNumberOfElements(), AosDNS.MaxNofServer) - 1 DO
					p := dnsElems.GetElement(i);
					elem := p(XML.Element);
					attribute := elem.GetAttribute("value");
					IF attribute # NIL THEN
						elemStr := attribute.GetValue();
						IF elemStr # NIL THEN
							interfaceConfig.DNS[i] := AosIP.StrToAdr(elemStr^);
						END;						
					END;
				END;	

				(* IF configuration for right device save it *)
				IF (interfaceConfig # NIL) & (interfaceConfig.Device = devName) THEN
					interfaceConfig.next := config.interfaceConfigs;
					config.interfaceConfigs := interfaceConfig;
				END;
			END;
		END;
	END Readv6Interface;
	
	
	(* Read router configurations *)
	PROCEDURE ReadRouter;
	BEGIN
		routerElems := GetSections(ipv6Elem, "Router");
		IF routerElems.GetNumberOfElements() # 0 THEN
			FOR routerNbr := 0 TO routerElems.GetNumberOfElements() - 1 DO
				p := routerElems.GetElement(routerNbr);
				routerElem :=p (XML.Element);
				(* init router config *)
				NEW(routerConfig);
				
				(* Set defaults *)
				routerConfig.Device := "";
				routerConfig.SendRouterAdvertisements := FALSE;
				routerConfig.ManagedAddressConfig := FALSE;
				routerConfig.OtherStatefulConfig := FALSE;
				routerConfig.LinkMTU := 0;	(* zero means don't send MTU option *)
				routerConfig.ReachableTime := 0;
				routerConfig.RetransTimer := 0;
				routerConfig.CurrentHopLimit := 0; (* unspecified *)
				routerConfig.Lifetime := 3 * 600;	(* seconds *)
				routerConfig.Prefixes := NIL;
				
				(* Device *)
				GetSettingChars(routerElem, "Device", TRUE, routerConfig.Device);
							
				(* SendRouterAdvertisement *)
				GetSettingBool(routerElem, "SendRouterAdvertisements", FALSE, routerConfig.SendRouterAdvertisements);
				
				(* ManagedAddressConfig *)
				GetSettingBool(routerElem, "ManagedAddressConfig", FALSE,  routerConfig.ManagedAddressConfig);
				
				(* OtherStatefulConfig *)
				GetSettingBool(routerElem, "OtherStatefulConfig", FALSE, routerConfig.OtherStatefulConfig);
				
				(* LinkMTU *)
				GetSettingInt(routerElem, "LinkMTU", FALSE, routerConfig.LinkMTU);
				
				(* ReachableTime *)
				GetSettingInt(routerElem, "ReachableTime", FALSE, routerConfig.ReachableTime);
				
				(* RetransTimer *)
				GetSettingInt(routerElem, "RetransTimer", FALSE, routerConfig.RetransTimer);
				
				(* Current Hop Limit *)
				GetSettingInt(routerElem, "CurrentHopLimit", FALSE, routerConfig.CurrentHopLimit);
				
				(* Lifetime *)
				GetSettingInt(routerElem, "Lifetime", FALSE, routerConfig.Lifetime);
				
				(* Parse prefixes *)
				prefixElems := GetSections(routerElem, "Prefix");
				IF prefixElems.GetNumberOfElements() # 0 THEN
					FOR prefixNbr := 0 TO prefixElems.GetNumberOfElements() - 1 DO
						p := prefixElems.GetElement(prefixNbr);
						prefixElem :=p (XML.Element);
						(* init prefix config *)
						NEW(prefixConfig);
			
						(* Set defaults *)
						prefixConfig.Prefix := AosIP.NilAdr;
						prefixConfig.IsSitePrefix := FALSE;
						prefixConfig.ValidLifetime := 2592000; (* in seconds is 30 days *)
						prefixConfig.OnLink := TRUE;
						prefixConfig.PreferredLifetime := 604800; (* in seconds is 7 days *)
						prefixConfig.Autonomous := TRUE;
							
						(* Prefix *)
						GetSettingAdr(prefixElem, "Prefix", TRUE, prefixConfig.Prefix);
						
						(* IsSitePrefix *)
						GetSettingBool(prefixElem, "IsSitePrefix", FALSE, prefixConfig.IsSitePrefix);
						
						(* ValidLifetime *)
						GetSettingInt(prefixElem, "ValidLifetime", FALSE, prefixConfig.ValidLifetime);
						
						(* OnLink *)
						GetSettingBool(prefixElem, "OnLink", FALSE, prefixConfig.OnLink);
						
						(* PreferredLifetime *)
						GetSettingInt(prefixElem, "PreferredLifetime", FALSE, prefixConfig.PreferredLifetime);
						
						(* Autonomous *)
						GetSettingBool(prefixElem, "Autonomous", FALSE, prefixConfig.Autonomous);
						
						prefixConfig.next := routerConfig.Prefixes;
						routerConfig.Prefixes := prefixConfig;
					END;
				END;

				(* IF configuration for right device save it *)
				IF (routerConfig # NIL) & (routerConfig.Device = devName) THEN
					routerConfig.next := config.routerConfigs;
					config.routerConfigs := routerConfig;
				END;
			END;		
		END;
	END ReadRouter;
	
	
BEGIN
	(* init *)
	hasXMLErrors := FALSE;
	res := Ok;
	
	NEW(config);
	config.IPForwarding:= FALSE;	(* defaults *)
	config.EchoReply := TRUE;
	config.AutoNetConfigV4 := TRUE;
	config.AutoNetConfigV6 := TRUE;
	config.PreferredProtocol := AosIP.IPv4;
	
	(* Load NetInit.XML *)
	file := AosFS.Old("AosConfig.XML");
	IF file # NIL THEN
		AosFS.OpenReader(reader, file, 0);
		NEW(scanner, reader);;
		scanner.reportError := Error;
		NEW(parser, scanner);
		parser.reportError := Error;
		doc := parser.Parse();
		netConfigElem := doc.GetRoot();	
		netConfigElem := GetSection(netConfigElem, "NetConfig");

		IF hasXMLErrors THEN
			AosOut.String("Net configuration not loaded"); AosOut.Ln;
			res := ConfigFileNotValid;
			RETURN NIL;
		END;
		
		IF devName = "Loopback" THEN		
			(* Make two loopback configuration (IPv4, IPv6) *)
			NEW(interfaceConfig);
			(*init config for IPv4 *)
			FOR i := 0 TO LEN(interfaceConfig.DNS) - 1 DO
				interfaceConfig.DNS[i] := AosIP.NilAdr;
			END;
			COPY(devName, interfaceConfig.Device);
			interfaceConfig.Protocol := AosIP.IPv4;			
			interfaceConfig.Name := "Loopbackv4";
			interfaceConfig.Domain := NIL;
			interfaceConfig.DHCP := FALSE;
			interfaceConfig.LocalAdr := AosIP.StrToAdr("127.0.0.1");
			interfaceConfig.Gateway := AosIP.NilAdr;
			interfaceConfig.Netmask := AosIP.StrToAdr("255.255.0.0");
			interfaceConfig.Prefix := AosIP.NilAdr;
	
			interfaceConfig.next := config.interfaceConfigs;
			config.interfaceConfigs := interfaceConfig;
			
			(* init config for IPv6 *)
			NEW (interfaceConfig);
				FOR i := 0 TO LEN(interfaceConfig.DNS) - 1 DO
				interfaceConfig.DNS[i] := AosIP.NilAdr;
			END;
			COPY(devName, interfaceConfig.Device);
			interfaceConfig.Protocol := AosIP.IPv6;
			interfaceConfig.Name := "Loopbackv6";
			interfaceConfig.Domain := NIL;
			interfaceConfig.DHCP := FALSE;
			interfaceConfig.LocalAdr := AosIP.StrToAdr("::1");
			interfaceConfig.Gateway := AosIP.NilAdr;
			interfaceConfig.Netmask := AosIP.NilAdr;
			interfaceConfig.Prefix := AosIP.NilAdr;
			interfaceConfig.Prefix.data := 64;
			interfaceConfig.Prefix.usedProtocol := AosIP.IPv6;
			
			interfaceConfig.next := config.interfaceConfigs;
			config.interfaceConfigs := interfaceConfig;
		END;
				
		IF netConfigElem # NIL THEN	
			(* IPForwarding *)
			GetSettingBool(netConfigElem, "IPForwarding", FALSE, config.IPForwarding);
		
			(* EchoReply *)
			GetSettingBool(netConfigElem, "EchoReply", FALSE, config.EchoReply);
			
			(* Preferred protocol *)
			GetSettingInt(netConfigElem, "PreferredProtocol", FALSE, config.PreferredProtocol);

			(* IPv4 *)
			ipv4Elem := GetSection(netConfigElem, "IPv4");

			IF ipv4Elem # NIL THEN						
				(* AutoNetConfig *)
				elem := GetSection(ipv4Elem, "AutoNetConfig");
				IF elem # NIL THEN
					GetSettingBool(elem, "Enabled", TRUE, config.AutoNetConfigV4);
				ELSE
					hasXMLErrors := TRUE;
				END;
				
				Readv4Interface;
				
			ELSE
				hasXMLErrors := TRUE;
			END;
			
			(* IPv6 *)
			ipv6Elem := GetSection(netConfigElem, "IPv6");
			IF ipv6Elem # NIL THEN
				(* AutoNetConfig *)
				elem := GetSection(ipv6Elem, "AutoNetConfig");
				IF elem # NIL THEN
					(* Enabled *)
					GetSettingBool(elem, "Enabled", TRUE, config.AutoNetConfigV6);

					(* DNS *)
					dnsElems := GetSettings(elem, "DNS");
					FOR i := 0 TO Utilities.Min(dnsElems.GetNumberOfElements(), AosDNS.MaxNofServer) - 1 DO
						p := dnsElems.GetElement(i);
						elem := p(XML.Element);
						attribute := elem.GetAttribute("value");
						IF attribute # NIL THEN
							elemStr := attribute.GetValue();
							IF elemStr # NIL THEN
								config.AutoNetConfigV6DNS[i] := AosIP.StrToAdr(elemStr^);
							END;						
						END;
					END;						
				ELSE
					hasXMLErrors := TRUE;
				END;
				Readv6Interface;
				ReadRouter;					
			ELSE
				hasXMLErrors := TRUE;
			END;
		ELSE
			hasXMLErrors := TRUE;
		END;
		
		IF config.interfaceConfigs = NIL THEN
			(* No configuration for this device, deliver config with only IPForwarding, EchoReplay, AutoNetConfig *)
			NEW(interfaceConfig);
			(*init config *)
			FOR i := 0 TO LEN(interfaceConfig.DNS) - 1 DO
				interfaceConfig.DNS[i] := AosIP.NilAdr;
			END;
			interfaceConfig.Device[0] := 0X;
			interfaceConfig.Protocol := 0;
			interfaceConfig.Name := "";
			interfaceConfig.Domain := NIL;
			interfaceConfig.DHCP := TRUE;
			interfaceConfig.LocalAdr := AosIP.NilAdr;
			interfaceConfig.Gateway := AosIP.NilAdr;
			interfaceConfig.Netmask := AosIP.NilAdr;
			interfaceConfig.Prefix := AosIP.NilAdr;
			interfaceConfig.next := NIL;
			config.interfaceConfigs := interfaceConfig;
		END;
		RETURN config;
	ELSE
		AosOut.String("Network configuration file (NetInit.XML) not found"); AosOut.Ln;
		res := NoConfigFile;
		RETURN NIL;
	END;
	RETURN NIL;
END GetConfig;


PROCEDURE Added(dev: AosNet.LinkDevice);
VAR
	config: Config;
	interfaceConfigItem: InterfaceConfig;
	ipv4IntFound: BOOLEAN;
	runnerDHCP: RunnerDHCP;
	int, intSec: AosIP.Interface;	 (* if autoconf = true; there are two ip interfaces (v4 & v6) *)
	intv4: AosIPv4.Interface;
	intv6: AosIPv6.Interface;
	DHCP: BOOLEAN;
	localAdr, netmask, gateway: AosIP.Adr;
	hostName,
	domain,
	intName: AosIP.Name; (* if autoconf = true; there are two ip interfaces (v4 & v6) *)
	DNS: ARRAY AosIP.MaxNofDNS OF AosIP.Adr;
	DNScount, i, res, resSec: LONGINT;
	linkLocalAdr: AosIP.Adr;
	linkLocalPrefix: AosIP.Adr;
	routerConfigItem: AosIPv6.RouterConfig;
	
BEGIN
	AosOut.String("AosInitNet: LinkDevice '"); AosOut.String(dev.name); AosOut.String("' found."); AosOut.Ln;
	config := GetConfig(dev.name, res);
	AosOut.String("AosInitNet: LinkDevice '"); AosOut.String(dev.name);
	AosOut.String("': Get interface configuration. Error code: "); AosOut.Int(res, 0); AosOut.Ln;

	IF res = Ok THEN
		(* auto configuration: an IPv4 interface per device *)
		ipv4IntFound := FALSE;
		
		AosIP.preferredProtocol := config.PreferredProtocol;
		AosIP.IPForwarding := config.IPForwarding;
		AosIP.EchoReply := config.EchoReply;
		
		interfaceConfigItem := config.interfaceConfigs;
	
		WHILE interfaceConfigItem # NIL DO
			(* IPv4 or IPv6 interface? *)
			CASE interfaceConfigItem.Protocol OF
				AosIP.IPv4:
					NEW(intv4, interfaceConfigItem.Name, dev, res);				
					int := intv4;
					
				|AosIP.IPv6:				
					NEW(intv6, interfaceConfigItem.Name, dev, res);
					int := intv6;

				ELSE	
						
			END;	
			IF (int # NIL) & (res = AosIP.Ok) THEN		
				IF int IS AosIPv4.Interface THEN
					ipv4IntFound := TRUE;
					int.SetAdrs(interfaceConfigItem.LocalAdr, interfaceConfigItem.Netmask, interfaceConfigItem.Gateway, res);
				END;
				IF int IS AosIPv6.Interface THEN
					int.SetAdrs(interfaceConfigItem.LocalAdr, interfaceConfigItem.Prefix, interfaceConfigItem.Gateway, res);
				END;
				IF res = AosIP.Ok THEN
					FOR i := 0 TO AosDNS.MaxNofServer - 1 DO
						IF ~AosIP.IsNilAdr(interfaceConfigItem.DNS[i]) THEN
							int.DNSAdd(interfaceConfigItem.DNS[i]);
						END;
					END;
					i := 0;
					
					IF interfaceConfigItem.DHCP THEN
						NEW(runnerDHCP, int);
					END;
					
					AosOut.String("AosInitNet: Add interface for LinkDevice '"); AosOut.String(dev.name);
					AosOut.String("'. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
					IF (res = Ok) & ~interfaceConfigItem.DHCP THEN
					AosIP.OutInterface(int);
					END;
				END;
			END;

			interfaceConfigItem := interfaceConfigItem.next;
		END;
		
		IF config.AutoNetConfigV6 & (dev.name # "Loopback") THEN
			(* create a link-local IPv6 interface *)
			Utilities.Concat("v6link-local", dev.name, intName);
			NEW (intv6, intName, dev, res);
			int := intv6;
			IF res = AosIP.Ok THEN
				int(AosIPv6.Interface).autoconfigurated := TRUE;
			
				linkLocalAdr := AosIP.NilAdr;
				linkLocalPrefix := AosIP.NilAdr;
				linkLocalPrefix.usedProtocol := AosIP.IPv6;
				
				int(AosIPv6.Interface).SetInterfaceID(linkLocalAdr);
				(* write link local prefix and prefix *)
				linkLocalAdr.ipv6Adr[0] := 0FEX;
				linkLocalAdr.ipv6Adr[1] := 80X;
				linkLocalPrefix.ipv6Adr[0] := 0FEX;
				linkLocalPrefix.ipv6Adr[1] := 80X;
				linkLocalPrefix.data := 64;

				int.SetAdrs(linkLocalAdr, linkLocalPrefix, AosIP.NilAdr, res);
				IF res = AosIP.Ok THEN
					FOR i := 0 TO AosDNS.MaxNofServer - 1 DO
						IF ~AosIP.IsNilAdr(config.AutoNetConfigV6DNS[i]) THEN
							int.DNSAdd(config.AutoNetConfigV6DNS[i]);
						END;
					END;
					AosOut.String("AosInitNet: Add interface for LinkDevice '"); AosOut.String(dev.name);
					AosOut.String("'. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
					AosIP.OutInterface(int);	
					
					(* initiate Routers Solicitation for auto-address-configuration *)
					int(AosIPv6.Interface).createStatelessInterface := TRUE;
					int(AosIPv6.Interface).RouterSolicitation;
					
					(* Is this device a router? *)
					routerConfigItem := config.routerConfigs;
					(* search for current device *)
					WHILE (routerConfigItem # NIL) & (routerConfigItem.Device # dev.name) DO
						routerConfigItem := routerConfigItem.next;
					END;
					
					IF routerConfigItem # NIL THEN
						(* found a router configuration *)
						int(AosIPv6.Interface).ConfigAsRouter(routerConfigItem);						
					END;					
				END;
			END;
		END;
		
		IF config.AutoNetConfigV4  & (dev.name # "Loopback") THEN
			(* create automatic IPv4 interface if there is none *)	
			IF ~ipv4IntFound THEN
				(* create an ipv4 interface (DHCP on) *)
				Utilities.Concat("v4auto", dev.name, intName);
				NEW(intv4, intName, dev, res);
				int := intv4;
				
				IF res = AosIP.Ok THEN
					NEW(runnerDHCP, int);
					
					AosOut.String("AosInitNet: Add interface for LinkDevice '"); AosOut.String(dev.name);
					AosOut.String("'. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
				END;
			END;
		END;
	END;
END Added;


(* Called for each LinkDevice that was removed from the registry. Remove the according interfaces. *)
PROCEDURE Removed(dev: AosNet.LinkDevice);
VAR int: AosIP.Interface;
BEGIN
	AosOut.String("AosInitNet: LinkDevice '"); AosOut.String(dev.name); AosOut.String("' removed."); AosOut.Ln;
	int := AosIP.InterfaceByDevice(dev);
	WHILE int # NIL DO
		int.Close();
		AosOut.String("AosInitNet: IP Interface '"); AosOut.String(int.name); AosOut.String("' removed."); AosOut.Ln;
		int := AosIP.InterfaceByDevice(dev);
	END;
END Removed;


(* Handle events of installed/removed devices *)
PROCEDURE EventHandler(event: LONGINT; plugin: AosPlugins.Plugin);
BEGIN
	IF event = AosPlugins.EventAdd THEN
		Added(plugin(AosNet.LinkDevice));
	ELSIF event = AosPlugins.EventRemove THEN
		Removed(plugin(AosNet.LinkDevice));
	ELSE
		(* unknown event *)
	END;
END EventHandler;


(* Handler for Enumerate() *)
PROCEDURE PluginHandler(plugin: AosPlugins.Plugin);
BEGIN
	Added(plugin(AosNet.LinkDevice));
END PluginHandler;


(** Initialize the IP stack and configure all IP interfaces. *)
PROCEDURE Init*(par: PTR):PTR;
BEGIN
	(* init routines are called implicitly *)
	RETURN NIL;
END Init;

PROCEDURE Cleanup();
BEGIN
	AosNet.registry.RemoveEventHandler(EventHandler, res);
	ASSERT(res = AosPlugins.Ok);
END Cleanup;

BEGIN
	AosICMP.InitDelegates();
	
	AosNet.registry.AddEventHandler(EventHandler, res);
	ASSERT(res = AosPlugins.Ok);
	
	AosModules.InstallTermHandler(Cleanup);
	
	(* Handle all previously installed devices *)
	AosOut.String("AosInitNet: Module initialized. Searching for installed devices..."); AosOut.Ln;
	AosNet.registry.Enumerate(PluginHandler);
	AosOut.String("AosInitNet: Finished searching for installed devices."); AosOut.Ln;
END AosInitNet.

(*
History:
01.11.2003	mvt	Created
02.05.2005	eb	Uses AosConfig.XML
06.03.2006	sst	Procedure Removed: remove all interfaces that belong to the device that is removed, not just one
*)
