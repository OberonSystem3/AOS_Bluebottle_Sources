MODULE WMPerfMonPluginNetwork; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor network performance plugin"; *)
(**
 * History:
 *
 *	16.02.2006	First Release (staubesv)
 *	23.06.2006	Adapted to WMPerfMonPlugins (staubesv)
 *)

IMPORT
	WMPerfMonPlugins,
	AosNet, AosPlugins, AosModules;
	
CONST
	PluginNameSend = "NetSend";
	PluginNameReceive = "NetReceive";
	
	ModuleName = "WMPerfMonPluginNetwork";
	
TYPE

	NetParameter* = POINTER TO RECORD (WMPerfMonPlugins.Parameter);
		device* : AosNet.LinkDevice;
	END;

TYPE

	NetSend* = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		l : AosNet.LinkDevice;
			
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		BEGIN
			p.name := PluginNameSend; p.description := "Network Send Performance";
			SELF.l := p(NetParameter).device; 
			WMPerfMonPlugins.GetNameDesc(l, p.devicename);
			p.modulename := ModuleName;
			p.autoMax := TRUE; p.unit := "KB"; p.perSecond := TRUE; p.showSum := TRUE; p.minDigits := 5;
		END Init;
						
		PROCEDURE UpdateDataset*;
		BEGIN 
			dataset[0] := l.sendCount / 1024;
		END UpdateDataset;
		
	END NetSend;
	
TYPE
	
	NetReceive* = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		l : AosNet.LinkDevice;
			
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		BEGIN
			p.name := PluginNameReceive; p.description := "Network Receive Performance";			
			SELF.l := p(NetParameter).device; 
			WMPerfMonPlugins.GetNameDesc(l, p.devicename);
			p.modulename := ModuleName;
			p.autoMax := TRUE; p.unit := "KB"; p.perSecond := TRUE; p.showSum := TRUE; p.minDigits := 5;
		END Init;
						
		PROCEDURE UpdateDataset*;
		BEGIN 
			dataset[0] := l.recvCount / 1024;
		END UpdateDataset;
		
	END NetReceive;
	
PROCEDURE AddPlugin(dev :AosNet.LinkDevice);
VAR nr : NetReceive; ns : NetSend; npar : NetParameter;
BEGIN {EXCLUSIVE}
	NEW(npar); npar.device := dev; NEW(ns, npar);
	NEW(npar); npar.device := dev; NEW(nr, npar);
END AddPlugin;

PROCEDURE RemovePlugin(dev : AosNet.LinkDevice);
VAR devicename : WMPerfMonPlugins.DeviceName;
BEGIN {EXCLUSIVE}
	WMPerfMonPlugins.GetNameDesc(dev, devicename);
	WMPerfMonPlugins.updater.RemoveByName(PluginNameSend, devicename);	
	WMPerfMonPlugins.updater.RemoveByName(PluginNameReceive, devicename);	
END RemovePlugin;

PROCEDURE EventHandler(event : LONGINT; plugin : AosPlugins.Plugin);
BEGIN
	IF event = AosPlugins.EventAdd THEN
		AddPlugin(plugin (AosNet.LinkDevice))
	ELSIF event = AosPlugins.EventRemove THEN
		RemovePlugin(plugin (AosNet.LinkDevice));
	END;
END EventHandler;

PROCEDURE InitPlugins;
VAR table : AosPlugins.Table; i : LONGINT;
BEGIN
	AosNet.registry.AddEventHandler(EventHandler, i);
	AosNet.registry.GetAll(table);
	IF table # NIL THEN FOR i := 0 TO LEN(table)-1 DO AddPlugin(table[i] (AosNet.LinkDevice)); END; END;
END InitPlugins;
	
PROCEDURE Install*(ptr : PTR) : PTR;
BEGIN
	RETURN NIL;
END Install;

PROCEDURE Cleanup;
VAR ignore : LONGINT;
BEGIN
	AosNet.registry.RemoveEventHandler(EventHandler, ignore);
	WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	InitPlugins;
END WMPerfMonPluginNetwork.

WMPerfMonPluginNetwork.Install ~  S.Free WMPerfMonPluginNetwork ~