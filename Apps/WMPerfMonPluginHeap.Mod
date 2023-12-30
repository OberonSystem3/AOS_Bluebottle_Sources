MODULE WMPerfMonPluginHeap; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor plugin for AosHeap statistics"; *)
(** 
 * History:
 *
 *	27.02.2007	First release (staubesv)
 *)
 
IMPORT
	AosOut, WMPerfMonPlugins, AosHeap, AosModules;

CONST
	ModuleName = "WMPerfMonPluginHeap";
	
TYPE

	HeapStats= OBJECT(WMPerfMonPlugins.Plugin)

		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosHeap"; p.description := "AosHeap statistics";
			p.modulename := ModuleName;
			p.autoMin := FALSE; p.autoMax := TRUE; p.minDigits := 7;
			
			NEW(ds, 13);
			ds[0].name := "Nnew";
			ds[1].name := "NnewBytes";
			ds[2].name := "Ngc";
			ds[3].name := "Nmark";
			ds[4].name := "Nmarked";
			ds[5].name := "Nsweeped";
			ds[6].name := "NfinalizeAlive";
			ds[7].name := "NfinalizeDead";
			ds[8].name := "NgcCyclesMark";
			ds[9].name := "NgcCyclesSweep";
			ds[10].name := "NgcCyclesLastRun";
			ds[11].name := "NgcCyclesMax";
			ds[12].name := "NgcCyclesAllRuns";
			p.datasetDescriptor := ds;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosHeap.Nnew;
			dataset[1] := AosHeap.NnewBytes;
			dataset[2] := AosHeap.Ngc;
			dataset[3] := AosHeap.Nmark;
			dataset[4] := AosHeap.Nmarked;
			dataset[5] := AosHeap.Nsweeped;
			dataset[6] := AosHeap.NfinalizeAlive;
			dataset[7] := AosHeap.NfinalizeDead;
			dataset[8] := AosHeap.NgcCyclesMark;
			dataset[9] := AosHeap.NgcCyclesSweep;
			dataset[10] := AosHeap.NgcCyclesLastRun;
			dataset[11] := AosHeap.NgcCyclesMax;
			dataset[12] := AosHeap.NgcCyclesAllRuns;
		END UpdateDataset;
				
	END HeapStats;

PROCEDURE Install*(none : ANY) : ANY; (** ~ *)
BEGIN
	RETURN NIL;
END Install;

PROCEDURE InitPlugin;
VAR par : WMPerfMonPlugins.Parameter; stats : HeapStats;
BEGIN
	IF AosHeap.Stats THEN
		NEW(par); NEW(stats, par);	
	ELSE
		AosOut.String(ModuleName); AosOut.String(": AosHeap.Stats is FALSE. Cannot install plugin."); AosOut.Ln;
	END;
END InitPlugin;

PROCEDURE Cleanup;
BEGIN
	IF AosHeap.Stats THEN
		WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);
	END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	InitPlugin;
END WMPerfMonPluginHeap.

WMPerfMonPluginHeap.Install ~   S.Free WMPerfMonPluginHeap ~
