MODULE AosMinInitNet; (** AUTHOR "eb"; PURPOSE "Minimal IP interface initialization and configuration"; *)

IMPORT AosOut, AosModules, AosPlugins, Utilities, AosNet, AosIP, AosICMP, AosDHCP, AosIPv4, AosIPv6;

CONST
	(** Error Codes *)
	Ok* = 0;
	

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
	(* temporary variables used in module body *)
	res: LONGINT;

	
PROCEDURE Added(dev: AosNet.LinkDevice);
VAR
	int, intSec: AosIP.Interface;	 (* if autoconf = true; there are two ip interfaces (v4 & v6) *)
	runnerDHCP: RunnerDHCP;
	intv4: AosIPv4.Interface;
	intv6: AosIPv6.Interface;
	intName: AosIP.Name; (* if autoconf = true; there are two ip interfaces (v4 & v6) *)
	linkLocalAdr: AosIP.Adr;
	linkLocalPrefix: AosIP.Adr;
	
BEGIN
	AosOut.String("AosInitNet: LinkDevice '"); AosOut.String(dev.name); AosOut.String("' found."); AosOut.Ln;
	AosOut.String("AosInitNet: LinkDevice '"); AosOut.String(dev.name);
	AosOut.String("': Get interface configuration. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
	
	AosIP.preferredProtocol := AosIP.IPv6;
	AosIP.IPForwarding := FALSE;
	AosIP.EchoReply := TRUE;
		
	IF dev.name # "Loopback" THEN
		(* create an ipv4 interface (DHCP on) *)
		Utilities.Concat("v4auto", dev.name, intName);
		NEW(intv4, intName, dev, res);
		int := intv4;
		
		IF res = AosIP.Ok THEN
			NEW(runnerDHCP, int);
			
			AosOut.String("AosInitNet: Add interface for LinkDevice '"); AosOut.String(dev.name);
			AosOut.String("'. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
		END;
	
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
				AosOut.String("AosInitNet: Add interface for LinkDevice '"); AosOut.String(dev.name);
				AosOut.String("'. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
				AosIP.OutInterface(int);	
				
				(* initiate Routers Solicitation for auto-address-configuration *)
				int(AosIPv6.Interface).createStatelessInterface := TRUE;
				int(AosIPv6.Interface).RouterSolicitation;
			END;
		END;
	ELSE
		(* Configure loopbackv4 *)
		intName := "Loopbackv4";
		NEW(intv4, intName, dev, res);
		int := intv4;
		
		IF res = AosIP.Ok THEN
			int.SetAdrs(AosIP.StrToAdr("127.0.0.1"), AosIP.StrToAdr("255.255.0.0"), AosIP.NilAdr, res);
			IF res = AosIP.Ok THEN			
				AosOut.String("AosInitNet: Add interface for LinkDevice '"); AosOut.String(dev.name);
				AosOut.String("'. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
			END;
		END;
		
		(* Configure loopbackv6 *)
		intName := "Loopbackv6";
		NEW (intv6, intName, dev, res);
		int := intv6;
		IF res = AosIP.Ok THEN
			 int.SetAdrs(AosIP.StrToAdr("::1"), AosIP.StrToAdr("::/64"), AosIP.NilAdr, res);
			 IF res = AosIP.Ok THEN
			 	AosOut.String("AosInitNet: Add interface for LinkDevice '"); AosOut.String(dev.name);
				AosOut.String("'. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
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
END AosMinInitNet.

History:
	
	06.03.2006	Procedure Removed: Remove all interfaces associated with the device - not just the first one (staubesv)
