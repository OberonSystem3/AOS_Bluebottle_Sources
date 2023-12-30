MODULE WMPerfMonPluginDisks; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor disk transfer rate plugin"; *)
(**
 * History:
 *
 *	16.02.2006	First Release (staubesv)
 *	23.06.2006	Adapted to WMPerfMonPlugins (staubesv)
 *	27.02.2007	Remove plugins when unloading module, distinct bytesRead/bytesWritten (staubesv)
 *	26.03.2007	Added NnofReads, NnofWrites, NnofOthers, NnofErrors, AvgBlockSize (staubesv)
 *)

IMPORT
	WMPerfMonPlugins,
	AosOut, AosDisks, AosBoot, AosPlugins, AosModules;
	
CONST
	PluginName = "DiskDevice";
	ModuleName = "WMPerfMonPluginDisks";
	
TYPE

	DiskParameter = POINTER TO RECORD(WMPerfMonPlugins.Parameter)
		dev : AosDisks.Device;
	END;

	DiskPlugin = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		dev : AosDisks.Device;
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := PluginName; p.description := "Disk device statistics";
			SELF.dev := p(DiskParameter).dev; 
			WMPerfMonPlugins.GetNameDesc(dev, p.devicename); 
			p.modulename := ModuleName;
			p.autoMax := TRUE; p.unit := "KB"; p.perSecond := TRUE; p.minDigits := 5; p.showSum := TRUE;
		
			NEW(ds, 8);
			ds[0].name := "TotalKB";	
			ds[1].name := "ReadKB";	
			ds[2].name := "WrittenKB";
			ds[3].name := "AvgBlockSizeBytes";
			ds[4].name := "NnofReads";
			ds[5].name := "NnofWrites";
			ds[6].name := "NnofOthers";
			ds[7].name := "NnofErrors";
			p.datasetDescriptor := ds;
		END Init;
		
		PROCEDURE UpdateDataset*;
		VAR read, written, nofReads, nofWrites, nofTot, nofErrors : HUGEINT; total : REAL;
		BEGIN
			read := dev.NbytesRead; nofReads := dev.NnofReads;
			written := dev.NbytesWritten; nofWrites := dev.NnofWrites;
			total := AosBoot.AddH(read, written);
			nofErrors := dev.NnofErrors;
			nofTot := nofReads + nofWrites - nofErrors;
			dataset[0] := total / 1024;
			dataset[1] := read / 1024;
			dataset[2] := written / 1024;
			dataset[3] := total / nofTot;
			dataset[4] := nofReads;
			dataset[5] := nofWrites;
			dataset[6] := dev.NnofOthers;
			dataset[7] := nofErrors;
		END UpdateDataset;
				
	END DiskPlugin;
	
PROCEDURE AddPlugin(disk : AosDisks.Device);
VAR par : DiskParameter; plugin : DiskPlugin;
BEGIN {EXCLUSIVE}
	NEW(par); par.dev := disk; NEW(plugin, par);
END AddPlugin;

PROCEDURE RemovePlugin(disk : AosDisks.Device);
VAR devicename : WMPerfMonPlugins.DeviceName;
BEGIN {EXCLUSIVE}
	WMPerfMonPlugins.GetNameDesc(disk, devicename);
	WMPerfMonPlugins.updater.RemoveByName(PluginName, devicename);	
END RemovePlugin;

PROCEDURE EventHandler(event : LONGINT; plugin : AosPlugins.Plugin);
BEGIN
	IF event = AosPlugins.EventAdd THEN
		AddPlugin(plugin (AosDisks.Device))
	ELSIF event = AosPlugins.EventRemove THEN
		RemovePlugin(plugin (AosDisks.Device));
	END;
END EventHandler;
	
PROCEDURE InitPlugins;
VAR table : AosPlugins.Table; i : LONGINT;
BEGIN
	IF AosDisks.Stats THEN
		AosDisks.registry.AddEventHandler(EventHandler, i); (* ignore res *)
		AosDisks.registry.GetAll(table);
		IF table # NIL THEN FOR i := 0 TO LEN(table)-1 DO AddPlugin(table[i] (AosDisks.Device)); END; END;		
	ELSE AosOut.String("WMPerfMonPluginDisks: AosDisks.PerformanceMonitoring is FALSE."); AosOut.Ln;
	END;
END InitPlugins;

PROCEDURE Install*(par : ANY) : ANY;
BEGIN
	RETURN NIL
END Install;

PROCEDURE Cleanup;
VAR ignore : LONGINT;
BEGIN
	IF AosDisks.Stats THEN 
		AosDisks.registry.RemoveEventHandler(EventHandler, ignore); 
		WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);
	END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	InitPlugins;
END WMPerfMonPluginDisks.

WMPerfMonPluginDisks.Install ~ S.Free WMPerfMonPluginDisks ~