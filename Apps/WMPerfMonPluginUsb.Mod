MODULE WMPerfMonPluginUsb; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor USB transfer rate plugin"; *)
(**
 * History:
 *
 *	16.02.2006	First Release (staubesv)
 *	23.06.2006	Adapted to WMPerfMonPlugins (staubesv)
 *	27.02.2007	Remove plugins when unloading module (staubesv)
 *	13.03.2007	Added more statistics variables (staubesv)
 *)

IMPORT
	WMPerfMonPlugins,
	AosOut, AosUsbDebug, AosUsbHcdi, AosPlugins, AosModules;
	
CONST
	PluginName = "USB Transfer Rate";
	ModuleName = "WMPerfMonPluginUsb";
		
TYPE

	UsbParameter = POINTER TO RECORD(WMPerfMonPlugins.Parameter)
		controller : AosUsbHcdi.Hcd;
	END;

	UsbTransferRate = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		controller : AosUsbHcdi.Hcd;
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN	
			p.name := PluginName; p.description := "Amount of transfered data";
			SELF.controller := p(UsbParameter).controller;
			WMPerfMonPlugins.GetNameDesc(controller, p.devicename);
			p.modulename := ModuleName;
			p.max := 60*1024; p.autoMax := TRUE; p.minDigits := 5;
			NEW(ds, 9);
			ds[0].name := "NbytesTransfered";
			ds[1].name := "NnofTransfers";
			ds[2].name := "NnofBulkTransfers";
			ds[3].name := "NnofControlTransfers";
			ds[4].name := "NnofInterruptTransfers";
			ds[5].name := "NnofIsochronousTransfers";
			ds[6].name := "NnofUnknownTransfers";
			ds[7].name := "NnofInterrupts";
			ds[8].name := "NnofInterruptsHandled";
			p.datasetDescriptor := ds;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := controller.NbytesTransfered;
			dataset[1] := controller.NnofTransfers;
			dataset[2] := controller.NnofBulkTransfers;
			dataset[3] := controller.NnofControlTransfers;
			dataset[4] := controller.NnofInterruptTransfers;
			dataset[5] := controller.NnofIsochronousTransfers;
			dataset[6] := controller.NnofUnknownTransfers;
			dataset[7] := controller.NnofInterrupts;
			dataset[8] := controller.NnofInterruptsHandled;
		END UpdateDataset;
	
	END UsbTransferRate;
	
PROCEDURE AddPlugin(hcd : AosUsbHcdi.Hcd);
VAR par : UsbParameter; plugin : UsbTransferRate;
BEGIN {EXCLUSIVE}
	NEW(par); par.controller := hcd; NEW(plugin, par);
END AddPlugin;

PROCEDURE RemovePlugin(hcd : AosUsbHcdi.Hcd);
VAR devicename : WMPerfMonPlugins.DeviceName;
BEGIN {EXCLUSIVE}
	WMPerfMonPlugins.GetNameDesc(hcd, devicename);	
	WMPerfMonPlugins.updater.RemoveByName(PluginName, devicename);
END RemovePlugin;

PROCEDURE EventHandler(event : LONGINT; plugin : AosPlugins.Plugin);
BEGIN
	IF event = AosPlugins.EventAdd THEN
		AddPlugin(plugin (AosUsbHcdi.Hcd));
	ELSIF event = AosPlugins.EventRemove THEN
		RemovePlugin(plugin (AosUsbHcdi.Hcd));
	END;
END EventHandler;

PROCEDURE InitPlugins;
VAR table : AosPlugins.Table; i : LONGINT;
BEGIN
	IF AosUsbDebug.PerformanceMonitoring THEN
		AosUsbHcdi.controllers.AddEventHandler(EventHandler, i);
		AosUsbHcdi.controllers.GetAll(table);
		IF table # NIL THEN FOR i := 0 TO LEN(table)-1 DO AddPlugin(table[i] (AosUsbHcdi.Hcd)); END; END;		
	ELSE AosOut.String("WMPerfMonUsbPlugin: Performance counters not enabled in AosUsbHcdi.Mod"); AosOut.Ln;
	END;
END InitPlugins;

PROCEDURE Install*(par : ANY) : ANY;
BEGIN
	RETURN NIL
END Install;

PROCEDURE Cleanup;
VAR ignore : LONGINT;
BEGIN
	IF AosUsbDebug.PerformanceMonitoring THEN 
		AosUsbHcdi.controllers.RemoveEventHandler(EventHandler, ignore); 
		WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);
	END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	InitPlugins;
END WMPerfMonPluginUsb.

WMPerfMonPluginUsb.Install ~	S.Free WMPerfMonPluginUsb ~