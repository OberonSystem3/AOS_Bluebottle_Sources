MODULE AosUsbInfo; (** AUTHOR "staubesv"; PURPOSE "USB topology info" *)
(**
 * This Module doesn't add any functionality to the USB system software. Its purpose is to represent the current state of
 * the USB system software and to control trace options.
 *
 * Usage:
 *
 *	(* Information *)
 *	AosUsbInfo.Show ~ will display the current USB topology
 *	AosUsbInfo.Show details ~ will display the current USB topology with all available information (descriptors, configurations,...)
 *	AosUsbInfo.ShowDrivers ~ will display information about registered USB device drivers and their instances
 *	AosUsbInfo.ShowHc ~ will display all registered USB host controllers
 *	AosUsbInfo.ShowHc details ~ will display diagnostic information of all registered USB host controllers
 * 	AosUsbInfo.ShowHc schedule ~ will display the scheduling data structures of all host controllers
 *	AosUsbInfo.ShowHc pipes ~ will display all allocated pipes
 *	AosUsbInfo.ShowHc pipemore ~ will display all allocated pipes including their QH/TDs
 *	AosUsbInfo.ShowHc all ~ will display both the HC diagnostic information and its scheduling data structures
 *
 *	(* Trace options *)
 *	AosUsbInfo.TraceAll ~ enables all trace options
 *	AosUsbInfo.TraceNone ~ disables all trace options
 *	AosUsbInfo.TraceShow ~ show state of trace options 
 * 
 *	(* See AosUsbDebug.Mod for a description of the individual trace optinos *)
 *	AosUsbInfo.TraceOn Dm~ 			AosUsbInfo.TraceOff  Dm~
 *	AosUsbInfo.TraceOn Parsing~ 		AosUsbInfo.TraceOff  Parsing~
 *	AosUsbInfo.TraceOn DeviceStates~	AosUsbInfo.TraceOff  DeviceStates~
 *	AosUsbInfo.TraceOn Control~ 		AosUsbInfo.TraceOff  Control~
 *	AosUsbInfo.TraceOn ControlData~ 	AosUsbInfo.TraceOff  ControlData~
 *	AosUsbInfo.TraceOn Transfers~ 		AosUsbInfo.TraceOff  Transfers~
 *	AosUsbInfo.TraceOn Failed~ 			AosUsbInfo.TraceOff  Failed~
 *	AosUsbInfo.TraceOn ShortPackets ~	AosUsbInfo.TraceOff  ShortPackets ~
 *	AosUsbInfo.TraceOn Pipes~ 			AosUsbInfo.TraceOff  Pipes~
 *	AosUsbInfo.TraceOn Copying~ 		AosUsbInfo.TraceOff  Copying~
 *	AosUsbInfo.TraceOn Ioc~ 			AosUsbInfo.TraceOff  Ioc~
 *	AosUsbInfo.TraceOn Init~ 			AosUsbInfo.TraceOff  Init~
 *	AosUsbInfo.TraceOn Interrupts~ 		AosUsbInfo.TraceOff  Interrupts~
 *	AosUsbInfo.TraceOn Queuing~ 		AosUsbInfo.TraceOff  Queuing~
 *	AosUsbInfo.TraceOn HubRequests~ 	AosUsbInfo.TraceOff  HubRequests~
 *	AosUsbInfo.TraceOn Suspend~		AosUsbInfo.TraceOff  Suspend~
 *	AosUsbInfo.TraceOn Connects~		AosUsbInfo.TraceOff  Connects~
 *	AosUsbInfo.TraceOn Info~ 			AosUsbInfo.TraceOff  Info~
 *	AosUsbInfo.TraceOn Sensing~		AosUsbInfo.TraceOff  Sensing~
 *	AosUsbInfo.TraceOn ScRequests~ 	AosUsbInfo.TraceOff  ScRequests~
 *	AosUsbInfo.TraceOn ScTransfers~ 	AosUsbInfo.TraceOff  ScTransfers~
 *	AosUsbInfo.TraceOn CSWs~ 			AosUsbInfo.TraceOff  CSWs~
 *	AosUsbInfo.TraceOn CBWs~ 			AosUsbInfo.TraceOff  CBWs~
 *	AosUsbInfo.TraceOn ScInit~		 	AosUsbInfo.TraceOff  ScInit~
 *	AosUsbInfo.TraceOn Custom~		AosUsbInfo.TraceOff Custom~
 *
 *	AosUsbInfo.TraceOn Info Sensing ScRequests ScTransfers CSWs CBWs ScInit~ turns on all mass storage device related trace options
 *	AosUsbInfo.TraceOff Info Sensing ScRequests ScTransfers CSWs CBWs ScInit~ turns off ...
 *
 *	AosUsbInfo.TraceOn Dm Parsing DeviceStates Failed Pipes Init HubRequests Connects Info ~ is interesting when connecting devices
 *
 *	S.Free AosUsbInfo ~
 * 
 * History:
 *
 *	17.11.2005	Created (staubesv)
 *	12.12.2005	Added schedule, pipes & all parameter to ShowHc (staubesv)
 *	01.02.2006	Adapted ShowHc to AosUsbHcdi changes (staubesv)
 *	06.02.2006	Added trace option control (staubesv)
 *	26.02.2006	Added Custom trace option (staubesv)
 *	28.06.2006	Adapted to modified AosUsb.GetRootHubs procedure (staubesv)
 *	04.07.2006	Added ShowHc pipemore (staubesv)
 *	05.01.2007	Added ShortPackets trace option, call ShowConfiguration in ShowDevice (staubesv)
 *)

IMPORT 
	SYSTEM,
	AosOut, AosIO, AosCommands, AosPlugins, Utilities,
	AosUsbHcdi, AosUsb, AosUsbdi, Debug := AosUsbDebug;

(* Shows device descriptor / qualifier information and all configurations including its interfaces and endpoints. *)
PROCEDURE ShowDevice(dev : AosUsb.UsbDevice; indent : LONGINT; details : BOOLEAN);
VAR a, c, e, i : LONGINT;
BEGIN
	IF dev.hubFlag THEN 
		IF dev.parent = SELF THEN AosOut.String("Root "); END;
		AosOut.String("Hub with "); AosOut.Int(dev.nbrOfPorts, 0); AosOut.String(" ports: "); 
	END;
	dev.ShowName;
	IF ~details OR (dev.hubFlag & (dev.parent = dev)) THEN RETURN END;
	AosOut.String("(S/N: ");
	IF dev.descriptor(AosUsb.DeviceDescriptor).sSerialNumber # NIL THEN AosOut.String(dev.descriptor(AosUsb.DeviceDescriptor).sSerialNumber^); AosOut.String(")");
	ELSE AosOut.String("Not available)");
	END;
	AosOut.Ln;
	Indent(indent+4);
	AosOut.String("Address: "); AosOut.Int(dev.address, 0); AosOut.String(" ");
	IF dev.speed = AosUsbHcdi.LowSpeed THEN AosOut.String(" [LowSpeed]");
	ELSIF dev.speed = AosUsbHcdi.FullSpeed THEN AosOut.String(" [FullSpeed]");
	ELSIF dev.speed = AosUsbHcdi.HighSpeed THEN AosOut.String(" [HighSpeed]");
	ELSE AosOut.String(" [UnknownSpeed!!!]");
	END;
	AosOut.Ln;
	Indent(indent+4); AosOut.String("Device descriptor information: ");
	AosOut.Ln; 
	ShowDescriptor(dev.descriptor (AosUsb.DeviceDescriptor), indent+8);
	(* List all configurations *)
	FOR c := 0 TO dev.descriptor.bNumConfigurations-1 DO
		Indent(indent+12);
		AosOut.String("Configuration "); AosOut.Int(c, 0); AosOut.String(":");  
		IF dev.configurations[c](AosUsb.ConfigurationDescriptor).sConfiguration # NIL THEN  AosOut.String(dev.configurations[c](AosUsb.ConfigurationDescriptor).sConfiguration^); END;
		IF dev.actConfiguration = dev.configurations[c] THEN AosOut.String(" [active]"); END; AosOut.Ln;
		ShowConfiguration(dev.configurations[c](AosUsb.ConfigurationDescriptor), indent + 16);
		AosOut.Ln;
		(* List all interfaces *)
		FOR i := 0 TO dev.configurations[c].bNumInterfaces - 1 DO
			AosOut.Ln; Indent(indent+16);
			AosOut.String("Interface "); AosOut.Int(i, 0); AosOut.String(": "); AosOut.Ln;
			ShowInterface(dev.configurations[c].interfaces[i] (AosUsb.InterfaceDescriptor), indent+20); AosOut.Ln;
			(* List all endpoints *)
			FOR e := 0 TO dev.configurations[c].interfaces[i].bNumEndpoints-1 DO
				ShowEndpoint(dev.configurations[c].interfaces[i].endpoints[e] (AosUsb.EndpointDescriptor), indent+24);
			END;
			(* List alternate interface if available *)
			Indent(indent+16);
			AosOut.String("Alternate interface: ");
			IF dev.configurations[c].interfaces[i].numAlternateInterfaces = 0 THEN AosOut.String("n/a");  AosOut.Ln;
			ELSE
				AosOut.Ln;
				FOR a := 0 TO dev.configurations[c].interfaces[i].numAlternateInterfaces-1 DO
					Indent(indent+20); AosOut.String("Alternate Interface "); AosOut.Int(a, 0); AosOut.String(": ");
					ShowInterface(dev.configurations[c].interfaces[i].alternateInterfaces[a] (AosUsb.InterfaceDescriptor), indent+20); AosOut.Ln;
					(* List all endpoints *)
					FOR e := 0 TO dev.configurations[c].interfaces[i].bNumEndpoints-1 DO
						ShowEndpoint(dev.configurations[c].interfaces[i].alternateInterfaces[a].endpoints[e] (AosUsb.EndpointDescriptor), indent+24);
					END;
				END;
			END;
		END;
	END;
	AosOut.Ln;
	Indent(indent+4);
	AosOut.String("Device qualifier information: ");
	IF dev.qualifier = NIL THEN AosOut.String("n/a"); AosOut.Ln;
	ELSE
		AosOut.Ln;
		ShowDescriptor(dev.qualifier (AosUsb.DeviceDescriptor), indent + 8);
		FOR c := 0 TO dev.qualifier.bNumConfigurations-1 DO
			Indent(indent+12);
			AosOut.String("Other-Speed Configuration "); AosOut.Int(c, 0); AosOut.String(":");  
			IF dev.otherconfigurations[c](AosUsb.ConfigurationDescriptor).sConfiguration#NIL THEN  AosOut.String(dev.configurations[c](AosUsb.ConfigurationDescriptor).sConfiguration^); END;
			(* List all interfaces *)
			FOR i := 0 TO dev.otherconfigurations[c].bNumInterfaces - 1 DO
				AosOut.Ln; Indent(indent+16);
				AosOut.String("Interface "); AosOut.Int(i, 0); AosOut.String(": "); AosOut.Ln;
				ShowInterface(dev.otherconfigurations[c].interfaces[i] (AosUsb.InterfaceDescriptor), indent+20); AosOut.Ln;
				(* List all endpoints *)
				FOR e := 0 TO dev.otherconfigurations[c].interfaces[i].bNumEndpoints-1 DO
					ShowEndpoint(dev.otherconfigurations[c].interfaces[i].endpoints[e] (AosUsb.EndpointDescriptor), indent+24);
				END;
				(* List alternate interface if available *)
				Indent(indent+16);
				AosOut.String("Alternate interface: ");
				IF dev.otherconfigurations[c].interfaces[i].numAlternateInterfaces = 0 THEN AosOut.String("n/a");  AosOut.Ln;
				ELSE
					FOR a := 0 TO dev.otherconfigurations[c].interfaces[i].numAlternateInterfaces-1 DO
						AosOut.String("Alternate Interface "); AosOut.Int(a, 0); AosOut.String(": "); AosOut.Ln;
						ShowInterface(dev.otherconfigurations[c].interfaces[i].alternateInterfaces[a] (AosUsb.InterfaceDescriptor), indent+20); AosOut.Ln;
						(* List all endpoints *)
						FOR e := 0 TO dev.otherconfigurations[c].interfaces[i].bNumEndpoints-1 DO
							ShowEndpoint(dev.otherconfigurations[c].interfaces[i].alternateInterfaces[a].endpoints[e] (AosUsb.EndpointDescriptor), indent+24);
						END;
					END;
				END;
			END;
		END;
	END;
END ShowDevice;

(* Display textual respresenation of device descriptor or device qualifier *)
PROCEDURE ShowDescriptor(d : AosUsb.DeviceDescriptor;  indent : LONGINT);
BEGIN
	Indent(indent);
	AosOut.String("USB Version: "); PrintHex(SYSTEM.LSH(d.bcdUSB, -8)); AosOut.Char("."); PrintHex(d.bcdUSB MOD 100H); 
	AosOut.String(", Device Class: "); PrintHex(d.bDeviceClass);
	AosOut.String("H, Subclass: "); PrintHex(d.bDeviceSubClass);
	AosOut.String("H, Protocol: "); PrintHex(d.bDeviceProtocol); AosOut.String("H");
	AosOut.Ln;
	Indent(indent);
	AosOut.String("MaxPacketSize0: "); AosOut.Int(d.bMaxPacketSize0, 0); AosOut.String(" Bytes"); AosOut.Ln;
	Indent(indent);
	AosOut.String("idVendor: "); PrintHex(d.idVendor);
	AosOut.String("H,  idProduct: "); PrintHex(d.idProduct);
	AosOut.String("H,  Device Version: "); PrintHex(SYSTEM.LSH(d.bcdDevice, -8)); AosOut.Char("."); PrintHex(d.bcdDevice MOD 100H); 
	AosOut.Ln;
END ShowDescriptor;

(* Display textual respresentation of a USB device configuration *)
PROCEDURE ShowConfiguration(c : AosUsb.ConfigurationDescriptor; indent : LONGINT);
BEGIN
	Indent(indent); AosOut.String("ConfigurationValue: "); AosOut.Int(c.bConfigurationValue, 0); AosOut.Ln;
	Indent(indent); AosOut.String ("MaxPower: "); AosOut.Int(c.bMaxPower, 0); AosOut.String(" mA  "); AosOut.Ln;
	Indent(indent); AosOut.String("Power support: "); 
	IF c.bmAttributes * {6} # {} THEN AosOut.String("Self-Powered"); ELSE AosOut.String("Bus-Powered"); END;
	AosOut.Ln;
	Indent(indent); AosOut.String("Remote Wake-up support: ");
	IF c.bmAttributes * {5} # {} THEN AosOut.String("Yes"); ELSE AosOut.String("No"); END;
END ShowConfiguration;

(* Display textual representation of a USB device interface *)
PROCEDURE ShowInterface(i : AosUsb.InterfaceDescriptor; indent : LONGINT);
VAR drv : AosUsbdi.Driver;
BEGIN
	Indent(indent);
	IF i.sInterface # NIL THEN AosOut.String(i.sInterface^); AosOut.String(": "); END;
	AosOut.String("[Class: "); PrintHex(i.bInterfaceClass);
	AosOut.String("H Subclass: "); PrintHex(i.bInterfaceSubClass);
	AosOut.String("H Protocol: "); PrintHex(i.bInterfaceProtocol);
	AosOut.String("H #Endpoints: "); AosOut.Int(i.bNumEndpoints, 0);
	AosOut.String("]"); AosOut.Ln;
	Indent(indent);
	drv := i.driver;
	AosOut.String("Driver: ");
	IF drv # NIL THEN
		AosOut.String("["); AosOut.String(drv.name); 
		AosOut.String("("); AosOut.String(drv.desc); AosOut.String(")]");
	ELSE AosOut.String("[No driver installed for this interface]");
	END;
END ShowInterface;

(* Display textual representation of a USB device endpoint *)
PROCEDURE ShowEndpoint(e : AosUsb.EndpointDescriptor; indent : LONGINT);VAR attr : LONGINT;
BEGIN
	Indent(indent);
	AosOut.String("Endpoint "); 	AosOut.Int(e.bEndpointAddress MOD 16, 0); 
	AosOut.String(":"); AosOut.String(" [Type: ");
	attr := SYSTEM.VAL(LONGINT, e.bmAttributes);
	CASE attr OF
		0 : AosOut.String("Control");
		|1 : AosOut.String("Isochronous");
		|2 : AosOut.String("Bulk");
		|3 : AosOut.String("Interrupt");
	ELSE
		AosOut.String("unknown");
	END;
	IF (attr#0) & (attr<4) THEN
		AosOut.String("(");
		IF (SYSTEM.VAL(SET, e.bEndpointAddress) * {7}) # {} THEN	 AosOut.String("IN"); AosOut.String(")");
		ELSE AosOut.String("OUT)");
		END;
	END;
	IF attr = 1 THEN 
		AosOut.String(", Synchronization: ");
		CASE SYSTEM.VAL(LONGINT, SYSTEM.LSH(SYSTEM.VAL(SET, attr) * {2..3}, -2)) OF
			0 : AosOut.String("None");
			|1: AosOut.String("Asynchronous");
			|2: AosOut.String("Adaptive");
			|3: AosOut.String("Synchronous");
		END;
		AosOut.String(", Usage: ");
		CASE SYSTEM.VAL(LONGINT, SYSTEM.LSH(SYSTEM.VAL(SET, attr) * {2..3}, -2)) OF
			0 : AosOut.String("Data");
			|1: AosOut.String("Feedback");
			|2: AosOut.String("Implicit Feedback");
			|3: AosOut.String("Reserved");
		END;
	END;
	AosOut.String(" MaxPacketSize: "); AosOut.Int(e.wMaxPacketSize, 0);
	AosOut.String(" Bytes IRQinterval: "); AosOut.Int(e.bInterval, 0); AosOut.String(" ms]"); 
	AosOut.Ln;
END ShowEndpoint;

(* Display textual representation of the specified device and its descendants *)
PROCEDURE ShowDeviceChain(dev : AosUsb.UsbDevice; indent : LONGINT; details : BOOLEAN);
VAR i, j : LONGINT;
BEGIN
	IF dev = NIL THEN AosOut.String("No device attached");
	ELSIF dev.hubFlag THEN
		ShowDevice(dev, indent, details); AosOut.Ln;
		FOR i := 0 TO dev.nbrOfPorts - 1 DO
			FOR j := 0 TO indent - 1 DO AosOut.Char(" "); END;
			AosOut.String("    Port "); AosOut.Int(i+1, 0); AosOut.String(": "); 
			IF dev.deviceAtPort[i] = NIL THEN AosOut.String("No device attached."); AosOut.Ln;
			ELSIF dev.portPermanentDisabled[i] THEN AosOut.String("Permanent disable (error)"); AosOut.Ln;
			ELSE ShowDeviceChain(dev.deviceAtPort[i], indent+8, details);
			END;
		END;
	ELSE ShowDevice(dev, indent, details); AosOut.Ln;
	END;
END ShowDeviceChain;

(** Prints information about current usb tree *)
PROCEDURE Show*(param : PTR) : PTR;
VAR 
	i : LONGINT; 
	p : AosCommands.Parameters; r : AosIO.StringReader; 
	details : BOOLEAN; pstr : ARRAY 10 OF CHAR;
	rootHubs : AosUsb.RootHubArray;
BEGIN
	p := param(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^); r.String(pstr); 
	IF Utilities.Match("details", pstr) THEN details := TRUE; END;
	AosOut.String("AosUsb: Topology and device information: "); AosOut.Ln;
	AosUsb.GetRootHubs(rootHubs);
	BEGIN {EXCLUSIVE}
		IF rootHubs # NIL THEN
			FOR i := 0 TO LEN(rootHubs)-1 DO
				ShowDeviceChain(rootHubs[i], 0, details);
				rootHubs[i] := NIL; 
			END;
		ELSE AosOut.String("No USB host controllers found."); AosOut.Ln;
		END;
	END;
	RETURN NIL;
END Show;

(** Shows all registered drivers and their instances *)
PROCEDURE ShowDrivers*(ptr : PTR) : PTR;
VAR instances : AosPlugins.Table; i : LONGINT;
BEGIN
	AosUsb.drivers.Show;
	AosOut.Ln; AosOut.String("AosUsb: Instances of registered device drivers: "); AosOut.Ln;
	AosUsb.usbDrivers.GetAll(instances);
	IF instances=NIL THEN
		AosOut.String("no device drivers instances installed"); AosOut.Ln;
	ELSE
		FOR i:=0 TO LEN(instances)-1 DO
			AosOut.String("   ");
			AosOut.String(instances[i].name); AosOut.String(" (");
			AosOut.String(instances[i].desc); AosOut.String(")");
			AosOut.Ln;
		END;
	END;
	RETURN NIL;				
END ShowDrivers;

(** Shows all registered USB host controllers. *)
PROCEDURE ShowHc*(param : PTR) : PTR; (* ["details"|"schedule"|"all"] ~ *)
VAR
	table : AosPlugins.Table; hcd : AosUsbHcdi.Hcd;
	p : AosCommands.Parameters; r : AosIO.StringReader; 
	pstr : ARRAY 10 OF CHAR;
	i : LONGINT;
	
	PROCEDURE ShowPipes(hcd : AosUsbHcdi.Hcd; details : BOOLEAN);
	VAR i, j, k : LONGINT; pipe : AosUsbHcdi.Pipe;
	BEGIN
		FOR i := 0 TO 127 DO (* search all addresses ... *) 
			FOR j := 0 TO 15 DO (* ... and all endpoints for presence of a pipe *)
				FOR k := 0 TO 1 DO
					pipe := hcd.pipes[i][k][j];
					IF pipe # NIL THEN 
						AosOut.String("ADR: "); AosOut.Int(i, 0); AosOut.String(": "); pipe.Show(details);
					END;
				END;
			END;
		END;
	END ShowPipes;
	
BEGIN
	p := param(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^); r.String(pstr); 

	AosUsbHcdi.controllers.GetAll(table);
	IF table # NIL THEN 		
		FOR i := 0 TO LEN(table)-1 DO
			hcd := table[i] (AosUsbHcdi.Hcd);
			AosOut.String("**** "); AosOut.String(hcd.name); AosOut.String(" ("); AosOut.String(hcd.desc); AosOut.String(")"); AosOut.Ln;
			IF Utilities.Match("schedule", pstr) THEN
				IF Debug.Trace THEN hcd.ShowSchedule; ELSE AosOut.String("AosUsbInfo: AosUsbDebug.Trace is FALSE. Cannot show schedule."); AosOut.Ln; END;
			ELSIF Utilities.Match("details", pstr) THEN 
				IF Debug.Trace THEN hcd.Diag; ELSE AosOut.String("AosUsbInfo: AosUsbDebug.Trace is FALSE. Cannot show diagnostics."); AosOut.Ln; END;
			ELSIF Utilities.Match("pipes", pstr) THEN
				ShowPipes(hcd, FALSE);
			ELSIF Utilities.Match("pipemore", pstr) THEN
				ShowPipes(hcd, TRUE);
			ELSIF Utilities.Match("all", pstr) THEN
				IF Debug.Trace THEN hcd.Diag; hcd.ShowSchedule; 
				ELSE
					AosOut.String("AosUsbInfo: AosUsbDebug.Trace is FALSE. Cannot show schedule/diagnostics."); AosOut.Ln;
				END;
				ShowPipes(hcd, TRUE);
			END;
			AosOut.Ln;
		END;
	ELSE
		AosOut.String("AosUsbInfo: No USB host controllers found."); AosOut.Ln;
	END;
	RETURN NIL;
END ShowHc;

(* Helper: Displays the number <was> in hex to the kernel log *)
PROCEDURE PrintHex(was: LONGINT);
VAR z,d,h,i:LONGINT;
BEGIN
	z := 0;
	d := 16*16*16*16*16*16*16; (* what a quick hack *)
	FOR i:=0 TO 7 DO
		h := (was DIV d) MOD 16;
		IF (z = 1) OR (h # 0) OR (i = 7) THEN
			z := 1;
			IF h < 10 THEN AosOut.Int(h,0); ELSE AosOut.Char(CHR(ORD("A")+h-10)); END;
		END;
		d:=d DIV 16;
	END;
END PrintHex;

(* Helper *)
PROCEDURE Indent(indent : LONGINT);
VAR i : LONGINT;
BEGIN
	FOR i := 0 TO indent-1 DO AosOut.Char(" "); END;
END Indent;

(** Trace options interface *)

PROCEDURE TraceAll*(par : ANY) : ANY;
BEGIN
	IF TraceEnabled() THEN
		AosOut.String("AosUsbInfo: All trace options enabled."); AosOut.Ln;
		Debug.traceDm := TRUE;
		Debug.traceParsing := TRUE;
		Debug.traceDeviceStates := TRUE;
		Debug.traceControl := TRUE;
		Debug.traceControlData := TRUE;
		Debug.traceTransfers := TRUE;
		Debug.traceFailed := TRUE;
		Debug.traceShortPackets := TRUE;
		Debug.tracePipes := TRUE;
		Debug.traceCopying := TRUE;
		Debug.traceIoc := TRUE;
		Debug.traceInit := TRUE;
		Debug.traceInterrupts := TRUE;
		Debug.traceQueuing := TRUE;
		Debug.traceHubRequests := TRUE;
		Debug.traceSuspend := TRUE;
		Debug.traceConnects := TRUE;
		Debug.traceInfo := TRUE;
		Debug.traceSensing := TRUE;
		Debug.traceScRequests := TRUE;
		Debug.traceScTransfers := TRUE;
		Debug.traceCSWs := TRUE;
		Debug.traceCBWs := TRUE;
		Debug.traceScInit := TRUE;
		Debug.traceCustom := TRUE;
	END;
	RETURN NIL
END TraceAll;

PROCEDURE TraceNone*(par : ANY) : ANY;
BEGIN
	Debug.traceDm := FALSE;
	Debug.traceParsing := FALSE;
	Debug.traceDeviceStates := FALSE;
	Debug.traceControl := FALSE;
	Debug.traceControlData := FALSE;
	Debug.traceTransfers := FALSE;
	Debug.traceFailed := FALSE;
	Debug.traceShortPackets := FALSE;
	Debug.tracePipes := FALSE;
	Debug.traceCopying := FALSE;
	Debug.traceIoc := FALSE;
	Debug.traceInit := FALSE;
	Debug.traceInterrupts := FALSE;
	Debug.traceQueuing := FALSE;
	Debug.traceHubRequests := FALSE;
	Debug.traceSuspend := FALSE;
	Debug.traceConnects := FALSE;
	Debug.traceInfo := FALSE;
	Debug.traceSensing := FALSE;
	Debug.traceScRequests := FALSE;
	Debug.traceScTransfers := FALSE;
	Debug.traceCSWs := FALSE;
	Debug.traceCBWs := FALSE;
	Debug.traceScInit := FALSE;
	Debug.traceCustom := FALSE;
	AosOut.String("AosUsbInfo: All trace options disabled."); AosOut.Ln;
	RETURN NIL
END TraceNone;

PROCEDURE TraceShow*(par : ANY) : ANY;
	
	PROCEDURE ShowOn(on : BOOLEAN);
	BEGIN
		IF on THEN AosOut.String("On"); ELSE AosOut.String("Off"); END;
	END ShowOn;
	
BEGIN
	AosOut.String("AosUsbInfo: Trace options state: "); AosOut.Ln;
	AosOut.String("AosUsbDebug.Trace: "); ShowOn(Debug.Trace); AosOut.Ln;
	AosOut.String("traceDm: "); ShowOn(Debug.traceDm); AosOut.Ln;	
	AosOut.String("traceParsing: "); ShowOn(Debug.traceParsing); AosOut.Ln;
	AosOut.String("traceDeviceStates: "); ShowOn(Debug.traceDeviceStates); AosOut.Ln;
	AosOut.String("traceControl: "); ShowOn(Debug.traceControl); AosOut.Ln;
	AosOut.String("traceControlData: "); ShowOn(Debug.traceControlData); AosOut.Ln;
	AosOut.String("traceTransfers: "); ShowOn(Debug.traceTransfers); AosOut.Ln;
	AosOut.String("traceFailed: "); ShowOn(Debug.traceFailed); AosOut.Ln;
	AosOut.String("traceShortPackets: "); ShowOn(Debug.traceShortPackets); AosOut.Ln;
	AosOut.String("tracePipes: "); ShowOn(Debug.tracePipes); AosOut.Ln;
	AosOut.String("traceCopying: "); ShowOn(Debug.traceCopying); AosOut.Ln;
	AosOut.String("traceIoc: "); ShowOn(Debug.traceIoc); AosOut.Ln;
	AosOut.String("traceInit: "); ShowOn(Debug.traceInit); AosOut.Ln;
	AosOut.String("traceInterrupts: "); ShowOn(Debug.traceInterrupts); AosOut.Ln;
	AosOut.String("traceQueuing: "); ShowOn(Debug.traceQueuing); AosOut.Ln;
	AosOut.String("traceHubRequests: "); ShowOn(Debug.traceHubRequests); AosOut.Ln;
	AosOut.String("traceSuspend: "); ShowOn(Debug.traceSuspend); AosOut.Ln;
	AosOut.String("traceConnects: "); ShowOn(Debug.traceConnects); AosOut.Ln;
	AosOut.String("traceInfo: "); ShowOn(Debug.traceInfo); AosOut.Ln;
	AosOut.String("traceSensing: "); ShowOn(Debug.traceSensing); AosOut.Ln;
	AosOut.String("traceScRequests: "); ShowOn(Debug.traceScRequests); AosOut.Ln;
	AosOut.String("traceScTransfers: "); ShowOn(Debug.traceScTransfers); AosOut.Ln;
	AosOut.String("traceCSWs: "); ShowOn(Debug.traceCSWs); AosOut.Ln;
	AosOut.String("traceCBWs: "); ShowOn(Debug.traceCBWs); AosOut.Ln;
	AosOut.String("traceScInit: "); ShowOn(Debug.traceScInit); AosOut.Ln;
	AosOut.String("traceCustom: "); ShowOn(Debug.traceCustom); AosOut.Ln;
	RETURN NIL;
END TraceShow;

PROCEDURE TraceOn*(par : ANY) : ANY;
BEGIN
	IF TraceEnabled() THEN TraceOnOff(par, TRUE); END;
	RETURN NIL;
END TraceOn;

PROCEDURE TraceOff*(par : ANY) : ANY;
BEGIN
	TraceOnOff(par, FALSE);
	RETURN NIL;
END TraceOff;

PROCEDURE TraceOnOff(par : ANY; on : BOOLEAN);	
VAR
	p : AosCommands.Parameters; r : AosIO.StringReader; 
	pstr : ARRAY 32 OF CHAR; invalid : BOOLEAN;
BEGIN
	p := par(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^); 
	LOOP
		r.SkipWhitespace; r.String(pstr); invalid := FALSE;
		IF ((r.res # AosIO.Ok) & (r.res # AosIO.EOF)) OR (pstr = "")  THEN EXIT; END;
		IF Utilities.Match("Dm", pstr) THEN Debug.traceDm := on;
		ELSIF Utilities.Match("Parsing", pstr) THEN Debug.traceParsing := on;
		ELSIF Utilities.Match("DeviceStates", pstr) THEN Debug.traceDeviceStates := on;
		ELSIF Utilities.Match("Control", pstr) THEN Debug.traceControl := on;
		ELSIF Utilities.Match("ControlData", pstr) THEN Debug.traceControlData := on;
		ELSIF Utilities.Match("Transfers", pstr) THEN Debug.traceTransfers := on;
		ELSIF Utilities.Match("Failed", pstr) THEN Debug.traceFailed := on;
		ELSIF Utilities.Match("ShortPackets", pstr) THEN Debug.traceShortPackets := on;
		ELSIF Utilities.Match("Pipes", pstr) THEN Debug.tracePipes := on;
		ELSIF Utilities.Match("Copying", pstr) THEN Debug.traceCopying := on;
		ELSIF Utilities.Match("Ioc", pstr) THEN Debug.traceIoc := on;
		ELSIF Utilities.Match("Init", pstr) THEN Debug.traceInit := on;
		ELSIF Utilities.Match("Interrupts", pstr) THEN Debug.traceInterrupts := on;
		ELSIF Utilities.Match("Queuing", pstr) THEN Debug.traceQueuing := on;
		ELSIF Utilities.Match("HubRequests", pstr) THEN Debug.traceHubRequests := on;
		ELSIF Utilities.Match("Suspend", pstr) THEN Debug.traceSuspend := on;
		ELSIF Utilities.Match("Connects", pstr) THEN Debug.traceConnects := on;
		ELSIF Utilities.Match("Info", pstr) THEN Debug.traceInfo := on;
		ELSIF Utilities.Match("Sensing", pstr) THEN Debug.traceSensing := on;
		ELSIF Utilities.Match("ScRequests", pstr) THEN Debug.traceScRequests := on;
		ELSIF Utilities.Match("ScTransfers", pstr) THEN Debug.traceScTransfers := on;
		ELSIF Utilities.Match("CSWs", pstr) THEN Debug.traceCSWs := on;
		ELSIF Utilities.Match("CBWs", pstr) THEN Debug.traceCBWs := on;
		ELSIF Utilities.Match("ScInit", pstr) THEN Debug.traceScInit := on;
		ELSIF Utilities.Match("Custom", pstr) THEN Debug.traceCustom := on;
		ELSE
			AosOut.String("Trace option '"); AosOut.String(pstr); AosOut.String("' not known."); AosOut.Ln;
			invalid := TRUE;
		END;
		IF ~invalid THEN 
			AosOut.String("Trace option '"); AosOut.String(pstr); AosOut.String("' turned ");
			IF on THEN AosOut.String("on."); ELSE AosOut.String("off."); END;
		END;
		AosOut.Ln;
		IF r.res = AosIO.EOF THEN EXIT; END;
	END;
END TraceOnOff;

PROCEDURE TraceEnabled() : BOOLEAN;
BEGIN
	IF ~Debug.Trace THEN AosOut.String("AosUsbInfo: AosUsbDebug.Trace is FALSE. Cannot enable trace options."); AosOut.Ln; END;
	RETURN Debug.Trace;
END TraceEnabled;	

END AosUsbInfo.

AosUsbInfo.Open ~ 
AosUsbInfo.Show ~
AosUsbInfo.Show details ~
AosUsbInfo.ShowDrivers ~
AosUsbInfo.ShowHc ~
AosUsbInfo.ShowHc details ~

S.Free AosUsbInfo ~