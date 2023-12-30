MODULE WMPerfMonPluginActive; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor plugin for AosActive statistics"; *)
(** 
 * History:
 *
 *	27.02.2007	First release (staubesv)
 *)
 
IMPORT
	AosOut, WMPerfMonPlugins, AosActive, AosModules;

CONST
	ModuleName = "WMPerfMonPluginActive";
	
TYPE

	ActiveStats= OBJECT(WMPerfMonPlugins.Plugin)

		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosActive"; p.description := "AosActive statistics";
			p.modulename := ModuleName;
			p.autoMin := FALSE; p.autoMax := TRUE; p.minDigits := 7;
			
			NEW(ds, 28);
			ds[0].name := "Nlock";
			ds[1].name := "Nunlock";
			ds[2].name := "Nawait";
			ds[3].name := "NawaitNoIF";
			ds[4].name := "NawaitTrue";
			ds[5].name := "Ncreate";
			ds[6].name := "Nterminate";
			ds[7].name := "Ncondition";
			ds[8].name := "Ncondition1True";
			ds[9].name := "Ncondition2";
			ds[10].name := "Ncondition2True";
			ds[11].name := "Ntimeslice";
			ds[12].name := "NtimesliceTaken";
			ds[13].name := "NtimesliceNothing";
			ds[14].name := "NtimesliceIdle";
			ds[15].name := "NtimesliceKernel";
			ds[16].name := "NtimesliceV86";
			ds[17].name := "NtimesliceCritical";
			ds[18].name := "Npreempt";
			ds[19].name := "NpreemptTaken";
			ds[20].name := "NpreemptNothing";
			ds[21].name := "NpreemptKernel";
			ds[22].name := "NpreemptV86";
			ds[23].name := "NpreemptCritical";
			ds[24].name := "Nenter";
			ds[25].name := "NenterHigherRunningPriority";
			ds[26].name := "NenterHigherCurrentPriority";
			ds[27].name := "NenterHigherIdlePriority";
			p.datasetDescriptor := ds;
		END Init;

		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosActive.Nlock;
			dataset[1] := AosActive.Nunlock;
			dataset[2] := AosActive.Nawait;
			dataset[3] := AosActive.NawaitNoIF;
			dataset[4] := AosActive.NawaitTrue;
			dataset[5] := AosActive.Ncreate;
			dataset[6] := AosActive.Nterminate;
			dataset[7] := AosActive.Ncondition;
			dataset[8] := AosActive.Ncondition1True;
			dataset[9] := AosActive.Ncondition2;
			dataset[10] := AosActive.Ncondition2True;
			dataset[11] := AosActive.Ntimeslice;
			dataset[12] := AosActive.NtimesliceTaken;
			dataset[13] := AosActive.NtimesliceNothing;
			dataset[14] := AosActive.NtimesliceIdle;
			dataset[15] := AosActive.NtimesliceKernel;
			dataset[16] := AosActive.NtimesliceV86;
			dataset[17] := AosActive.NtimesliceCritical;
			dataset[18] := AosActive.Npreempt;
			dataset[19] := AosActive.NpreemptTaken;
			dataset[20] := AosActive.NpreemptNothing;
			dataset[21] := AosActive.NpreemptKernel;
			dataset[22] := AosActive.NpreemptV86;
			dataset[23] := AosActive.NpreemptCritical;
			dataset[24] := AosActive.Nenter;
			dataset[25] := AosActive.NenterHigherRunningPriority;
			dataset[26] := AosActive.NenterHigherCurrentPriority;
			dataset[27] := AosActive.NenterHigherIdlePriority;
		END UpdateDataset;
				
	END ActiveStats;

PROCEDURE Install*(none : ANY) : ANY; (** ~ *)
BEGIN
	RETURN NIL;
END Install;

PROCEDURE InitPlugin;
VAR par : WMPerfMonPlugins.Parameter; stats : ActiveStats;
BEGIN
	IF AosActive.Stats THEN 
		NEW(par); NEW(stats, par);	
	ELSE
		AosOut.String(ModuleName); AosOut.String(": AosActive.Stats is FALSE. Cannot install plugin."); AosOut.Ln;
	END;
END InitPlugin;

PROCEDURE Cleanup;
BEGIN
	IF AosActive.Stats THEN
		WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);
	END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	InitPlugin;
END WMPerfMonPluginActive.

WMPerfMonPluginActive.Install ~   S.Free WMPerfMonPluginActive ~
