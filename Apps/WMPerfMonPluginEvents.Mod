MODULE WMPerfMonPluginEvents; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor plugin for event system"; *)
(**
 * History:
 *
 *	03.03.2007	First Release (staubesv)
 *)

IMPORT
	AosModules,
	WMPerfMonPlugins, AosEvents;
	
CONST
	ModuleName = "WMPerfMonPluginEvents";
		
TYPE

	EventStats* = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN	
			p.name := "AosEvents"; p.description := "Event log statistics";
			p.modulename := ModuleName;
			p.autoMin := FALSE; p.autoMax := TRUE; p.minDigits := 5;
			
			NEW(ds, 12);
			ds[0].name := "NnofEvents";
			ds[1].name := "NnofDiscarded";
			ds[2].name := "NnofEventsHandled";
			ds[3].name := "NnofEventsNotHandled";
			ds[4].name := "NnofUnknown";
			ds[5].name := "NnofUndefined";
			ds[6].name := "NnofInformation";
			ds[7].name := "NnofWarning";
			ds[8].name := "NnofError";
			ds[9].name := "NnofCritical";
			ds[10].name := "NnofFailure";
			ds[11].name := "NnofListeners";
			p.datasetDescriptor := ds;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosEvents.NnofEvents;
			dataset[1] := AosEvents.NnofDiscarded;
			dataset[2] := AosEvents.NnofEventsHandled;
			dataset[3] := AosEvents.NnofEventsNotHandled;
			dataset[4] := AosEvents.NnofUnknown;
			dataset[5] := AosEvents.NnofUndefined;
			dataset[6] := AosEvents.NnofInformation;
			dataset[7] := AosEvents.NnofWarning;
			dataset[8] := AosEvents.NnofError;
			dataset[9] := AosEvents.NnofCritical;
			dataset[10] := AosEvents.NnofFailure;
			dataset[11] := AosEvents.NnofListeners;
		END UpdateDataset;
	
	END EventStats;

PROCEDURE Install*(par : ANY) : ANY;
BEGIN
	RETURN NIL
END Install;

PROCEDURE InitPlugin;
VAR par : WMPerfMonPlugins.Parameter; plugin : EventStats;
BEGIN
	NEW(par); NEW(plugin, par);	
END InitPlugin;

PROCEDURE Cleanup;
BEGIN
	WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	InitPlugin;
END WMPerfMonPluginEvents.

WMPerfMonPluginEvents.Install ~	S.Free WMPerfMonPluginEvents ~