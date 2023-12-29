MODULE AosInitNet; (** AUTHOR "mvt"; PURPOSE "IP interface initialization and configuration"; *)

IMPORT AosBoot, AosOut, AosModules, AosPlugins, AosNet, AosIP, AosICMP, AosUDP, AosDNS, AosTCP, AosDHCP; (* load all *)

CONST
	(** Error Codes *)
	Ok* = 0;
	NotFound* = 4001;
	
	MaxNofInterfaces* = 10; (** Interface numbers vom 0 to 9 are accepted in AosBoot config *)

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
	autoNetConfig: BOOLEAN; (* automatic network interface configuration (read from AosBoot) *)
	
	(* temporary variables used in module body *)
	res: LONGINT;
	s: ARRAY 3 OF CHAR;

(* Get configuration from AosBoot for the specified device. *)

PROCEDURE GetConfig(VAR devName, intName: ARRAY OF CHAR; VAR DHCP: BOOLEAN;
	VAR localAdr, netmask, gateway: AosIP.Adr; VAR DNS: ARRAY OF AosIP.Adr; VAR DNScount, res: LONGINT);
VAR
	i, j: LONGINT;
	cfgDevName: AosPlugins.Name;
	conf: ARRAY 64 OF CHAR;
	str: ARRAY 17 OF CHAR;
	adr: AosIP.Adr;
BEGIN
	FOR i:= 0 TO MaxNofInterfaces-1 DO
		conf := "IntX.Device";
		conf[3] := CHR(ORD("0") + i);
		AosBoot.GetConfig(conf, cfgDevName);
		IF devName = cfgDevName THEN
			(* configuration entry found for this device *)
			
			conf := "IntX.Name";
			conf[3] := CHR(ORD("0") + i);
			AosBoot.GetConfig(conf, intName);
			
			conf := "IntX.DHCP";
			conf[3] := CHR(ORD("0") + i);
			AosBoot.GetConfig(conf, str);
			DHCP := (str = "1"); (* default := FALSE; *)
			
			conf := "IntX.LocalAdr";
			conf[3] := CHR(ORD("0") + i);
			AosBoot.GetConfig(conf, str);
			localAdr := AosIP.StrToAdr(str);
			
			conf := "IntX.Netmask";
			conf[3] := CHR(ORD("0") + i);
			AosBoot.GetConfig(conf, str);
			netmask := AosIP.StrToAdr(str);
			
			conf := "IntX.Gateway";
			conf[3] := CHR(ORD("0") + i);
			AosBoot.GetConfig(conf, str);
			gateway := AosIP.StrToAdr(str);
			
			conf := "IntX.DNSY";
			DNScount := 0;
			FOR j:= 0 TO AosIP.MaxNofDNS-1 DO
				conf[3] := CHR(ORD("0") + i);
				conf[8] := CHR(ORD("0") + j);
				AosBoot.GetConfig(conf, str);
				adr := AosIP.StrToAdr(str);
				IF adr # AosIP.NilAdr THEN
					DNS[DNScount] := adr;
					INC(DNScount)
				END
			END;
			
			res := 0;
			RETURN
		END
	END;
	IF autoNetConfig THEN
		(* not found, but AutoNetConfig is activated -> set defaults and run DHCP *)
		COPY(devName, intName);
		IF devName = "Loopback" THEN
			DHCP := FALSE;
			localAdr := AosIP.StrToAdr("127.0.0.1");
			netmask := AosIP.StrToAdr("255.255.0.0");
		ELSE
			DHCP := TRUE;
			localAdr := AosIP.NilAdr;
			netmask := AosIP.NilAdr;
		END;
		gateway := AosIP.NilAdr;
		DNScount := 0;
		res := 0
	ELSE
		res := NotFound
	END
END GetConfig;

(* Called for each LinkDevice that was added to the registry. Get config and install the interface. *)

PROCEDURE Added(dev: AosNet.LinkDevice);
VAR
	runnerDHCP: RunnerDHCP;
	int: AosIP.Interface;
	DHCP: BOOLEAN;
	localAdr, netmask, gateway: AosIP.Adr;
	hostName,
	domain,
	intName: AosIP.Name;
	DNS: ARRAY AosIP.MaxNofDNS OF AosIP.Adr;
	DNScount, i: LONGINT;
BEGIN
	AosOut.String("AosInitNet: LinkDevice '"); AosOut.String(dev.name); AosOut.String("' found."); AosOut.Ln;
	GetConfig(dev.name, intName, DHCP, localAdr, netmask, gateway, DNS, DNScount, res);
	AosOut.String("AosInitNet: LinkDevice '"); AosOut.String(dev.name);
	AosOut.String("': Get interface configuration. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
	IF res = Ok THEN
		NEW(int, intName, dev, res);
		IF res = AosIP.Ok THEN
			int.SetAdrs(localAdr, netmask, gateway, res);
			IF res = AosIP.Ok THEN
				FOR i:= 0 TO DNScount-1 DO
					int.DNSAdd(DNS[i]);
				END;
				IF DHCP THEN
					NEW(runnerDHCP, int);
				END;
			END;
		END;
		AosOut.String("AosInitNet: Add interface for LinkDevice '"); AosOut.String(dev.name);
		AosOut.String("'. Error code: "); AosOut.Int(res, 0); AosOut.Ln;
		IF (res = Ok) & ~DHCP THEN
			AosIP.OutInterface(int);
		END;
	END;
END Added;

(* Called for each LinkDevice that was removed from the registry. Remove the according interface. *)

PROCEDURE Removed(dev: AosNet.LinkDevice);
VAR int: AosIP.Interface;
BEGIN
	AosOut.String("AosInitNet: LinkDevice '"); AosOut.String(dev.name); AosOut.String("' removed."); AosOut.Ln;
	int := AosIP.InterfaceByDevice(dev);
	IF int # NIL THEN
		int.Close();
		 AosOut.String("AosInitNet: IP Interface '"); AosOut.String(int.name); AosOut.String("' removed."); AosOut.Ln;
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
	(* Get AutoNetConfig value. Default value is FALSE. *)
	AosBoot.GetConfig("AutoNetConfig", s);
	autoNetConfig := (s = "1");
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
*)
