MODULE WMPerfMonPluginLocks; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor plugin for lock statistics"; *)
(** 
 * History:
 *
 *	27.02.2007	First release (staubesv)
 *)
 
IMPORT
	AosOut, WMPerfMonPlugins, AosBoot, AosLocks, AosModules, Utilities;

CONST
	ModuleName = "WMPerfMonPluginLocks";
	
TYPE

	LockStatsParameter = POINTER TO RECORD(WMPerfMonPlugins.Parameter)
		lockNbr : LONGINT
	END;

	LockStats= OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		lockNbr : LONGINT;
		nbrOfCpus : LONGINT;

		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR cpuNbr : LONGINT; cpuString, temp: ARRAY 8 OF CHAR; ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			ASSERT(p IS LockStatsParameter);
			lockNbr := p(LockStatsParameter).lockNbr;
			
			p.name := "AosLocks"; Utilities.Append(p.name, GetLockName(lockNbr));
			p.description := "AosLocks statistics for "; Utilities.Append(p.description, GetLockName(lockNbr)); Utilities.Append(p.description, " lock level");			
			p.modulename := ModuleName;
			p.autoMin := FALSE; p.autoMax := TRUE; p.minDigits := 7;
			
			nbrOfCpus := WMPerfMonPlugins.GetNbrOfCpus();
			
			NEW(ds, nbrOfCpus * 8);
			FOR cpuNbr := 0 TO nbrOfCpus-1 DO
				Utilities.IntToStr(cpuNbr, temp);
				cpuString := " (P"; Utilities.Append(cpuString, temp); Utilities.Append(cpuString, ")");
				ds[cpuNbr + 0].name := "startTime"; Utilities.Append(ds[cpuNbr + 0].name, cpuString);
				ds[cpuNbr + 1].name := "acquireTime"; Utilities.Append(ds[cpuNbr + 1].name, cpuString);
				ds[cpuNbr + 2].name := "sumHeldTime"; Utilities.Append(ds[cpuNbr + 2].name, cpuString);
				ds[cpuNbr + 3].name := "maxHeldTime"; Utilities.Append(ds[cpuNbr + 3].name, cpuString);
				ds[cpuNbr + 4].name := "sumWaitTime"; Utilities.Append(ds[cpuNbr + 4].name, cpuString);
				ds[cpuNbr + 5].name := "sumSqrWaitTime"; Utilities.Append(ds[cpuNbr + 5].name, cpuString);
				ds[cpuNbr + 6].name := "maxWaitTime"; Utilities.Append(ds[cpuNbr + 6].name, cpuString);
				ds[cpuNbr + 7].name := "numReleases"; Utilities.Append(ds[cpuNbr + 7].name, cpuString);
			END;
			p.datasetDescriptor := ds;
		END Init;
		
		TYPE Str16 = ARRAY 16 OF CHAR;
		PROCEDURE GetLockName(lockNbr : LONGINT) : Str16;
		VAR name : Str16;
		BEGIN
			CASE lockNbr OF
				|AosLocks.AosOutLow: name := "AosOutLow";
				|AosLocks.AosMemory: name := "AosMemory";
				|AosLocks.AosHeap: name := "AosHeap";
				|AosLocks.AosInterrupts: name := "AosInterrupts";
				|AosLocks.AosModules: name := "AosModules";
				|AosLocks.AosActive: name := "AosActive";
				|AosLocks.AosProcessors: name := "AosProcessors";
				|AosLocks.AosOutHigh: name := "AosOutHigh";
			ELSE
				name := "Unknown";
			END;
			RETURN name;
		END GetLockName;

		PROCEDURE UpdateDataset*;
		VAR lockStats : ARRAY AosBoot.MaxCPU OF AosLocks.LockStats; cpuNbr : LONGINT;
		BEGIN
			(* copy lock stats. THIS OPERATION IS NOT SYNCHRONIZED!!! *)
			FOR cpuNbr := 0 TO nbrOfCpus-1 DO
				lockStats[cpuNbr] := AosLocks.lock[lockNbr].stats[cpuNbr];
			END;
			
			FOR cpuNbr := 0 TO nbrOfCpus-1 DO
				dataset[cpuNbr + 0] := lockStats[cpuNbr].startTime;
				dataset[cpuNbr + 1] := lockStats[cpuNbr].acquireTime;
				dataset[cpuNbr + 2] := lockStats[cpuNbr].sumHeldTime;
				dataset[cpuNbr + 3] := lockStats[cpuNbr].maxHeldTime;
				dataset[cpuNbr + 4] := lockStats[cpuNbr].sumWaitTime;
				dataset[cpuNbr + 5] := lockStats[cpuNbr].sumSqrWaitTime;
				dataset[cpuNbr + 6] := lockStats[cpuNbr].maxWaitTime;
				dataset[cpuNbr + 7] := lockStats[cpuNbr].numReleases;
			END;
		END UpdateDataset;
				
	END LockStats;

PROCEDURE Install*(par : ANY) : ANY; (** ~ *)
BEGIN
	RETURN NIL;
END Install;

PROCEDURE InitPlugins;
VAR par : LockStatsParameter; lockStats : LockStats; i : LONGINT;
BEGIN
	IF AosLocks.Stats THEN
		FOR i := 0 TO 7 DO
			NEW(par); par.lockNbr := i;
			NEW(lockStats, par);	
		END;
	ELSE
		AosOut.String(ModuleName); AosOut.String(": AosLocks.Stats is FALSE. Cannot install plugin."); AosOut.Ln;
	END;
END InitPlugins;

PROCEDURE Cleanup;
BEGIN
	IF AosLocks.Stats THEN 
		WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);
	END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	InitPlugins;
END WMPerfMonPluginLocks.

WMPerfMonPluginLocks.Install ~   S.Free WMPerfMonPluginLocks ~
