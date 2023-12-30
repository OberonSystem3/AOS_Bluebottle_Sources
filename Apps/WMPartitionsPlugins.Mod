MODULE WMPartitionsPlugins; (** AUTHOR: "staubesv"; PURPOSE: "Plugins for Partition Tool" *)
(**
 * This module implements some plugins for the WMPartitions tool.
 *
 * Currently available plugins:
 *
 * 	FSTools:			 		Graphical front-end for AosFSTools.Mod
 *	AosPartitionsPlugin:		Graphical front-end for operations provided by AosPartitionsLib and AosFATScavenger (Format)
 *	FATScavenger:			Graphical front-end for AosFATScavenger (Scavenger)
 * 	Bluebottle:				Graphical front-end for Bluebottle specific operations provided by AosPartitionsLib.Mod
 *
 * History:
 *
 *	05.08.2005	Removed unused code / cleanup (staubesv)
 *	25.11.2005	Reasonable default parameter value for several operations (staubesv)
 *	29.11.2005	Set selected dev#part in config editor automatically, resizing of config editor fixed (staubesv)
 *	09.12.2005	Removed procedure Remove (staubesv)
 *	14.12.2005	Added Force R/W option for FAT volumes (staubesv)
 *	16.12.2005	Added "Perform Read Test" option to AosPartitions.BenchPartition (staubesv)
 *	19.12.2005	Treat FAT scavenger as normal operation (staubesv)
 *	03.01.2006	Set default size for boot file to 1024KB in AosPartitionsPlugin.Format (staubesv)
 *	05.01.2006	AosPartitions.BenchPartition: Blocksizes up to 16MB (staubesv)
 *	02.02.2006	Added cachesize & wb cache options for FAT file systems in FSTools plugin (staubesv)
 *	24.02.2006	Open Config Editor window in current view, fixed some typos in GUI (staubesv)
 *	28.02.2006	Added Tests plugin (staubesv)
 *	18.03.2006	Added Tests.WriteZeros, changed parameter 1 of ShowBlocks to non-optional, 
 *				added Bluebottle.InstallBootManager, removed Bluebottle.Install & Bluebottle.Update (staubesv)
 *)
 
IMPORT 
	AosOut, AosIO, AosDisks, AosDiskVolumes, AosFATVolumes, AosISO9660Volumes, AosFS, AosFSTools, AosPartitionsLib, AosDiskBench, AosDiskTests,
	AosTexts, AosModules, AosCommands, Utilities, AosFATScavenger, AosKernel, WMGrids, WMStringGrids, WMWindowManager, 
	WMPartitions, WMComponents, WMStandardComponents, WMEditors, WMRectangles, WMGraphics, WMProperties;

CONST

	(* Prefix for automatically generated mount prefixes. *)
	DefaultPrefix = "Auto";
	
	(* FAT file systems only: default size of cache in KB (as string) *)
	DefaultFatCacheSize = "2048";

	ButtonWidth = WMPartitions.ButtonWidth;
	ButtonHeight = WMPartitions.ButtonHeight;
	ButtonSpacer = WMPartitions.ButtonSpacer;
	
	WindowBg = WMPartitions.WindowBg;
	
	MainPanelMarginH = WMPartitions.MainPanelMarginH;
	MainPanelMarginV = WMPartitions.MainPanelMarginV;
	
	DiskOverviewPanelMarginH = WMPartitions.DiskOverviewPanelMarginH;
	DiskOverviewPanelMarginV = WMPartitions.DiskOverviewPanelMarginV;
	
	(* Config editor constants *)
	CeLabelHeight = 20;
	CeOpPanelHeight = ButtonHeight + 2*DiskOverviewPanelMarginV;
	CeKeyWidth = 100;
	CeMaxStringLength = 1024;
	CeStatusLabelHeight = 20;
	CeEditPanelHeight = 3*ButtonHeight + 2*DiskOverviewPanelMarginV + 2*ButtonSpacer;
	CeCellHeightMinSpacer = 2;
	
	ToFile = 0;
	ToPartition = 1; 

TYPE 

	(*
	 * The File System Tools (FSTools) is basically a graphical front-end for the operations provided by AosFSTools.Mod.
	 * It can be used to mount / unmount volumes and display a overview (free/total memory) of volumes. If the file system type
	 * of the selected partition is recognize, the plugin will automatically set the correct parameters for the mount command, including
	 * a generate mount prefix.
	 *)
	FSTools = OBJECT(WMPartitions.PartitionsPlugin);
	VAR
		(* mount command *)
		mount : WMStandardComponents.Button;
		prefixEditor, fsEditor : WMEditors.Editor;
		mountPanel : WMStandardComponents.Panel;
		
		(* FatFS specific settings - will only be visible if selected partition contains FAT volume*)
		forceRWlabel, enableWBlabel, cacheSizeLabel : WMStandardComponents.Label;
		forceRW, enableWB : WMStandardComponents.Button;		
		cacheSizeEditor : WMEditors.Editor;
		parForceRW, parEnableWB : BOOLEAN;
		
		(* unmount command *)
		unmount, force : WMStandardComponents.Button;
		parForce : BOOLEAN;
		
		(* disk info panel *)
		info : WMPartitions.BorderLabel;
		
		prefixUsed : ARRAY 128 OF BOOLEAN; (* used by GenPrefix() *)
		
		PROCEDURE Resized*(width, height : LONGINT);
		BEGIN
			panel.bounds.SetExtents(width, height);
			mountPanel.bounds.SetExtents(width - ButtonWidth, ButtonHeight); 
			info.bounds.SetExtents(width - ButtonWidth - ButtonHeight - 2*ButtonSpacer - 40, ButtonHeight);
		END Resized;
		
		PROCEDURE SelectionUpdated*(selection:  WMPartitions.Selection): LONGINT;
		VAR
			caption, temp : ARRAY 128 OF CHAR;
			fs : AosFS.FileSystem;
			fstype : LONGINT;
			doClose : BOOLEAN;
			result, res : LONGINT;
		BEGIN
			SELF.selection := selection;
			IF IsValid(selection) THEN
				
				fstype := 0; (* invalid *)
				
				IF (selection.disk.isDiskette) & (selection.disk.res = AosDisks.Ok) THEN
					(* special case: floppy disk *)
					doClose := FALSE;
					IF (selection.disk.device.openCount < 1) THEN
						doClose := TRUE;
						selection.disk.device.Open(res); (* ignore res *)
					END;
					IF AosPartitionsLib.DisketteInserted(selection.disk.device) THEN
						fstype := AosPartitionsLib.DetectFS(selection.disk.device, selection.partition);
					END;
				ELSE
					fstype := DetectFS(selection.disk.device, selection.partition);
				END;
				
				temp := "";
				CASE fstype OF
					0 :  result := WMPartitions.SelectionInvalid;
					|1 : temp := "NatFS"; result := WMPartitions.SelectionValid;
					|2 : temp := "AosFS"; result := WMPartitions.SelectionValid;
					|3 : temp := "AosFS"; result := WMPartitions.SelectionValid;
					|4 : temp := "FatFS"; result := WMPartitions.SelectionValid;
				END;
				
				IF (selection.disk.isDiskette) & doClose & (selection.disk.device.openCount > 0) THEN
					selection.disk.device.Close(res); (* ignore res *)
				END;
				
				(* If device is not partitioned, assume CDROM or floppy drive *)
				IF ((result = WMPartitions.SelectionInvalid) & (LEN(selection.disk.table) = 1)) THEN
					result := WMPartitions.SelectionMaybe;
					temp := "IsoFS";
				END;
				
				IF fstype = 4 THEN (* FatFS specific settings *)				
					parForceRW := FALSE; forceRW.caption.SetAOC("");
					IF Utilities.Match("USB*", selection.disk.device.name) THEN (* enable wb caching for USB devices *)
						parEnableWB := TRUE; enableWB.caption.SetAOC("X"); 
					ELSE
						parEnableWB := FALSE; enableWB.caption.SetAOC("");
					END;
					forceRWlabel.visible.Set(TRUE); forceRW.visible.Set(TRUE);
					cacheSizeEditor.visible.Set(TRUE); cacheSizeLabel.visible.Set(TRUE);
					enableWB.visible.Set(TRUE); enableWBlabel.visible.Set(TRUE);
				ELSE
					forceRWlabel.visible.Set(FALSE); forceRW.visible.Set(FALSE);
					cacheSizeEditor.visible.Set(FALSE); cacheSizeLabel.visible.Set(FALSE);
					enableWB.visible.Set(FALSE); enableWBlabel.visible.Set(FALSE);
				END;
				
				fsEditor.SetAsString(temp); (* file system *)
				prefixEditor.SetAsString(GenPrefix());
				IF (selection.disk.fs # NIL) & (selection.partition <LEN(selection.disk.fs)) & (selection.disk.fs[selection.partition] # NIL) THEN (* we have a reference to the FS *)
					fs := selection.disk.fs[selection.partition];
					caption := " File System Info:  "; Utilities.Append(caption, fs.prefix); Utilities.Append(caption, ": ");
					Utilities.Append(caption, fs.desc); Utilities.Append(caption, " on ");
					Utilities.Append(caption, selection.disk.device.name); 
					Utilities.Append(caption, "#"); Utilities.IntToStr(selection.partition, temp); Utilities.Append(caption, temp);
					IF fs.vol # NIL THEN 
						IF AosFS.ReadOnly IN fs.vol.flags THEN Utilities.Append(caption, " (read-only)") END;
						IF AosFS.Removable IN fs.vol.flags THEN Utilities.Append(caption, " (removable)") END;
						IF AosFS.Boot IN fs.vol.flags THEN Utilities.Append(caption, " (boot)") END;
						Utilities.Append(caption, ", ");
						WriteK(ENTIER(fs.vol.Available()/1024.0D0 * fs.vol.blockSize), caption);  Utilities.Append(caption, " of ");
						WriteK(ENTIER(fs.vol.size/1024.0D0 * fs.vol.blockSize), caption);  Utilities.Append(caption, " free");
					END;
					info.caption.Set(Utilities.NewString(caption));
				ELSE
					info.caption.Set(Utilities.NewString(" File System Info: n/a"));
				END;
			ELSE
				result := WMPartitions.SelectionInvalid;
			END;
			RETURN result;
		END SelectionUpdated; 
		
		PROCEDURE WriteK(k: LONGINT; VAR string : ARRAY OF CHAR);
		VAR suffix: ARRAY 3 OF CHAR; temp : ARRAY 32 OF CHAR;
		BEGIN
			IF k < 10*1024 THEN COPY("Ki", suffix)
			ELSIF k < 10*1024*1024 THEN COPY("Mi", suffix); k := k DIV 1024
			ELSE COPY("Gi", suffix); k := k DIV (1024*1024)
			END;
			Utilities.IntToStr(k , temp); Utilities.Append(string, temp); Utilities.Append(string, suffix); Utilities.Append(string, "B");
		END WriteK;
		
		(* Generate a mount prefix by appending a number to the string represented by the constant DefaultPrefix. *)
		PROCEDURE GenPrefix() : AosFS.Prefix;
		VAR prefix : AosFS.Prefix; temp : ARRAY 12 OF CHAR; i : LONGINT;
		BEGIN {EXCLUSIVE}
			WHILE prefixUsed[i] & (i < LEN(prefixUsed)-1) DO INC(i); END; 
			ASSERT(i < LEN(prefixUsed)); 
			prefix := ""; Utilities.Append(prefix, DefaultPrefix); Utilities.IntToStr(i, temp); Utilities.Append(prefix, temp);
			RETURN prefix;	
		END GenPrefix;
		
		PROCEDURE SetPrefixUsed(prefix : ARRAY OF CHAR);
		VAR nbr : LONGINT;		
		BEGIN (* will not be concurrently called with GenPrefix *)
			nbr := GetPrefixNbr(prefix);
			IF nbr#-1 THEN prefixUsed[nbr] := TRUE; END;
		END SetPrefixUsed;
		
		PROCEDURE GetPrefixNbr(iprefix : ARRAY OF CHAR) : LONGINT;
		VAR
			match : BOOLEAN;
			temp : ARRAY 32 OF CHAR;
			default, prefix : Utilities.String;
			i, j, result : LONGINT;
		BEGIN
			prefix := Utilities.NewString(iprefix);
			default := Utilities.NewString(DefaultPrefix);
			result := -1; (* invalid *)
			IF LEN(prefix) > LEN(default) THEN 
				match := TRUE;
				FOR i := 0 TO LEN(default)-2 (* ignore 0X *) DO
					IF prefix[i]#default[i] THEN match := FALSE; END;
				END;
				IF match THEN 
					temp := ""; j := 0; i := LEN(default)-1;
					WHILE i < LEN(prefix) DO temp[j] := prefix[i]; INC(j); INC(i); END;
					Utilities.StrToInt(temp, result);
					IF (result < 0) OR (result >= LEN(prefixUsed)) THEN result := -1; END;
				END;
			END;
			RETURN result;
		END GetPrefixNbr;
		
		(* Appends FatFS specific parameters to command string *)
		PROCEDURE AppendFATspecific(VAR str : ARRAY OF CHAR);
		VAR string : ARRAY 128 OF CHAR; cachesize : LONGINT;
		BEGIN
			IF parForceRW THEN Utilities.Append(str, " ,X"); END;
			cacheSizeEditor.GetAsString(string); Utilities.StrToInt(string, cachesize);
			IF (cachesize > 0) THEN
				cachesize := (1024 * cachesize) DIV AosPartitionsLib.BS; (* cachesize in 512B blocks *)
				IF parEnableWB THEN cachesize := -cachesize; END;
				Utilities.IntToStr(cachesize, string);
				Utilities.Append(str, ",C:"); Utilities.Append(str, string);
			END;
		END AppendFATspecific;
		
		(** prefix [hashSize] [cachesize] alias [volpar] ["|" fspar] ~ *)
		PROCEDURE Mount(sender, data : PTR);
		VAR
			temp, prefix : ARRAY 128 OF CHAR;
			ignore : PTR;
			cmd : AosCommands.Parameters;
			result : Utilities.String;
		BEGIN
			NEW(result, 128); Utilities.Append(result^, "Mount Status: ");
			IF IsValid(selection) THEN 
				IF selection.disk.table[selection.partition].flags  * {AosDisks.Mounted} = {} THEN
					(** cmd: prefix [hashSize] [cachesize] alias [volpar] ["|" fspar] ~ *)
					NEW(cmd); NEW(cmd.str, 256);
					prefixEditor.GetAsString(prefix);
					IF prefix # "" THEN 
						Utilities.Append(cmd.str^, prefix); Utilities.Append(cmd.str^, " ");
						fsEditor.GetAsString(temp); (* alias *)
						IF temp # "" THEN 
							Utilities.Append(cmd.str^, temp); Utilities.Append(cmd.str^, " ");
							Utilities.Append(cmd.str^, selection.disk.device.name); Utilities.Append(cmd.str^, "#");
							Utilities.IntToStr(selection.partition, temp); Utilities.Append(cmd.str^, temp);
							AppendFATspecific(cmd.str^);
							ignore := AosFSTools.Mount(cmd);
							IF selection.disk.device.table[selection.partition].flags * {AosDisks.Mounted} # {} THEN 
								Utilities.Append(result^, prefix); Utilities.Append(result^, " "); Utilities.Append(result^, "mounted");
								INCL(selection.disk.table[selection.partition].flags, AosDisks.Mounted);
								SetPrefixUsed(prefix);
							ELSIF LEN(selection.disk.table) = 1 THEN (* unpartitioned device *)
   								Utilities.Append(result^, prefix); Utilities.Append(result^, " "); Utilities.Append(result^, "mounted");
								INCL(selection.disk.table[selection.partition].flags, AosDisks.Mounted);
								SetPrefixUsed(prefix);
							ELSE
								Utilities.Append(result^, "failed");
							END;
							owner.UpdateDisk(selection.disk);
							owner.RefreshSelection;
						ELSE Utilities.Append(result^, "Failed: No alias specified");
						END;
					ELSE Utilities.Append(result^, "Failed: No prefix specified");
					END;
				ELSE Utilities.Append(result^, "Failed: Volume already mounted");
				END;
			ELSE Utilities.Append(result^, "Failed: No volume selected");
			END;
			owner.UpdateStatusLabel(result);
		END Mount;
		
		(* Force parameter of the unmount command *)
		PROCEDURE Force(sender, data : PTR);
		BEGIN
			IF parForce THEN parForce := FALSE; force.caption.Set(Utilities.NewString(""));
			ELSE parForce := TRUE; force.caption.Set(Utilities.NewString("X"));
			END;
		END Force;
		
		(* FatFS only: Force R/W mountng *)
		PROCEDURE ForceRW(sender, data : PTR);
		BEGIN
			IF parForceRW THEN parForceRW := FALSE; forceRW.caption.Set(Utilities.NewString(""));
			ELSE parForceRW := TRUE; forceRW.caption.Set(Utilities.NewString("X"));
			END;
		END ForceRW;
		
		(* FatFS only: Enable/disable write back caching *)
		PROCEDURE EnableWB(sender, data : PTR);
		BEGIN
			IF parEnableWB THEN parEnableWB := FALSE; enableWB.caption.SetAOC("");
			ELSE parEnableWB := TRUE; enableWB.caption.SetAOC("X");
			END;
		END EnableWB;

		(* parameters : dev#part [/f] *)
		PROCEDURE Unmount(sender, data : PTR);
		VAR 
			dev : AosDisks.Device;
			fs: AosFS.FileSystem; ft: AosFS.FileSystemTable;
			vol : AosDiskVolumes.Volume; volFAT: AosFATVolumes.Volume;
			volISO : AosISO9660Volumes.Volume;
			fsStart : LONGINT;
			found : BOOLEAN;
			result  : Utilities.String;
			i : LONGINT;
		BEGIN			
			NEW(result, 128); Utilities.Append(result^, "Unmount Status: ");
			IF IsValid(selection) THEN 
				(* for unpartitioned devices we also try to unmount when AosDisks.Mounted is not set *)
				IF (LEN(selection.disk.table) = 1) OR (selection.disk.device.table[selection.partition].flags * {AosDisks.Mounted} # {}) THEN
					AosFS.GetList(ft);
					IF ft # NIL THEN
						i := 0; found := FALSE;
						LOOP
							fs := ft[i];
							IF fs.vol # NIL THEN
								IF fs.vol IS AosDiskVolumes.Volume THEN 
									vol := fs.vol (AosDiskVolumes.Volume);
									dev := vol.dev; fsStart := vol.startfs;
								ELSIF fs.vol IS AosFATVolumes.Volume THEN
									volFAT := fs.vol (AosFATVolumes.Volume);
									dev := volFAT.dev; fsStart := volFAT.start;
								ELSIF fs.vol IS AosISO9660Volumes.Volume THEN
									volISO := fs.vol (AosISO9660Volumes.Volume);
									dev := volISO.dev; fsStart := 512; (* dummy value *)
								ELSE
									dev := NIL;
								END;
								IF (dev#NIL) & (dev = selection.disk.device) &
							           ((selection.disk.isDiskette) OR
								    (fsStart >= dev.table[selection.partition].start) &
								    (fsStart < dev.table[selection.partition].start + dev.table[selection.partition].size))
								 THEN
									found := TRUE;	
									IF (fs.vol = NIL) OR parForce OR ~(AosFS.Boot IN fs.vol.flags) THEN
										AosFS.Remove(fs);
										EXCL(selection.disk.table[selection.partition].flags, AosDisks.Mounted);
										selection.disk.fs[selection.partition] := NIL;
										Utilities.Append(result^, fs.prefix); Utilities.Append(result^, " unmounted");
										owner.UpdateDisk(selection.disk);
										owner.UpdateContent;
										owner.RefreshSelection;
									ELSE
										Utilities.Append(result^, " can't unmount boot volume. Use \f parameter to force unmounting.");
									END;
									EXIT;
								END;
							END;
						INC(i);
						IF found OR (i > LEN(ft)-1) THEN EXIT; END;
						END;
						IF ~found THEN Utilities.Append(result^, "Failed: Volume not found"); END;
					ELSE Utilities.Append(result^, "Failed: Volume not found");
					END;
				ELSE Utilities.Append(result^, "Failed: Volume is not mounted");
				END;
			ELSE Utilities.Append(result^, "Failed: Selection Invalid");
			END;
			owner.UpdateStatusLabel(result);
		END Unmount;
		
		(* Check if an Oberon or FAT  file system is present on a partition. Returns 0 if no Oberon or FAT file system found, 
		1 for a Native file system, 2 for an old Aos file system and 3 for a new Aos file system, 4 for FAT file system (from Partitions.Mod) *)
		PROCEDURE DetectFS(dev: AosDisks.Device; part: LONGINT): LONGINT;
		VAR 
			block: POINTER TO ARRAY  OF CHAR;
			type : LONGINT;
			res, fs: LONGINT;
		BEGIN
			IF (dev.table=NIL) OR (part >= LEN(dev.table)) THEN RETURN 0; END;
			type := dev.table[part].type; 			
			fs := 0; 			
			IF (type = 01H ) OR (type = 04H) OR (type = 06H) OR (type = 0BH) OR (type = 0CH) OR (type = 0EH) THEN (* FAT Filesystems *)
				NEW(block, dev.blockSize);
				dev.Transfer(AosDisks.Read, dev.table[part].start, 1, block^, 0, res);
				IF (res = AosDisks.Ok) & (block[510]=055X) & (block[511]=0AAX) THEN 
					fs := 4;
				END;
			ELSIF (type = 4CH) OR (type =  04FH) OR (type = 050H) THEN (* Aos/NativeOveron *)
				IF dev.blockSize = AosPartitionsLib.BS THEN
					fs := AosPartitionsLib.DetectFS(dev, part);
				END;
			END;
			RETURN fs
		END DetectFS;
		
		PROCEDURE Finalize*;
		BEGIN
			(* do nothing *)
		END Finalize;
		
		PROCEDURE &Init;
		VAR label : WMStandardComponents.Label; spacer : WMStandardComponents.Panel;
		BEGIN
			SetName("FSTools"); desc := "Mount/Unmount File Systems";
		
			NEW(panel);
			panel.bounds.SetLeft(0); panel.bounds.SetTop(0);	 panel.fillColor.Set(WindowBg);
			
			NEW(mount);
			mount.bounds.SetExtents(ButtonWidth, ButtonHeight); mount.bounds.SetLeft(0); mount.bounds.SetTop(0);
			mount.onClick.Add(Mount); mount.SetCaption("Mount");
			panel.AddContent(mount);			
			
			NEW(mountPanel);
			mountPanel.bounds.SetLeft(MainPanelMarginH + ButtonWidth); mountPanel.bounds.SetTop(0);
			mountPanel.fillColor.Set(WindowBg);

			NEW(label);
			label.bounds.SetWidth(32); label.bounds.SetHeight(ButtonHeight); label.alignment.Set(WMComponents.AlignLeft);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("Prefix"));
			mountPanel.AddContent(label);
			
			NEW(prefixEditor);
			prefixEditor.bounds.SetWidth(40); prefixEditor.bounds.SetHeight(ButtonHeight); prefixEditor.alignment.Set(WMComponents.AlignLeft);
			prefixEditor.multiLine.Set(FALSE); prefixEditor.fillColor.Set(0FFFFFFFFH);
			prefixEditor.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); prefixEditor.tv.showBorder.Set(TRUE);
			mountPanel.AddContent(prefixEditor);
			
			NEW(label);
			label.bounds.SetWidth(64); label.bounds.SetHeight(ButtonHeight); label.alignment.Set(WMComponents.AlignLeft);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString(" FileSystem"));
			mountPanel.AddContent(label);
			
			NEW(fsEditor);
			fsEditor.bounds.SetWidth(40); fsEditor.bounds.SetHeight(20); fsEditor.alignment.Set(WMComponents.AlignLeft);
			fsEditor.multiLine.Set(FALSE); fsEditor.fillColor.Set(0FFFFFFFFH);
			fsEditor.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); fsEditor.tv.showBorder.Set(TRUE);
			mountPanel.AddContent(fsEditor);
			
			NEW(spacer); spacer.bounds.SetWidth(2*ButtonSpacer); spacer.alignment.Set(WMComponents.AlignLeft); spacer.fillColor.Set(WindowBg);
			mountPanel.AddContent(spacer);			
				
			NEW(cacheSizeLabel);
			cacheSizeLabel.bounds.SetWidth(83); cacheSizeLabel.bounds.SetHeight(ButtonHeight); cacheSizeLabel.alignment.Set(WMComponents.AlignLeft);
			cacheSizeLabel.fillColor.Set(WindowBg); cacheSizeLabel.caption.Set(Utilities.NewString("CacheSize (KB)")); cacheSizeLabel.visible.Set(FALSE);
			mountPanel.AddContent(cacheSizeLabel);
			
			NEW(cacheSizeEditor);
			cacheSizeEditor.bounds.SetWidth(40); cacheSizeEditor.bounds.SetHeight(ButtonHeight); cacheSizeEditor.alignment.Set(WMComponents.AlignLeft);
			cacheSizeEditor.multiLine.Set(FALSE); cacheSizeEditor.fillColor.Set(0FFFFFFFFH); cacheSizeEditor.SetAsString(DefaultFatCacheSize);
			cacheSizeEditor.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); cacheSizeEditor.tv.showBorder.Set(TRUE); cacheSizeEditor.visible.Set(FALSE);
			mountPanel.AddContent(cacheSizeEditor);		
			
			NEW(spacer); spacer.bounds.SetWidth(2*ButtonSpacer); spacer.alignment.Set(WMComponents.AlignLeft); spacer.fillColor.Set(WindowBg);
			mountPanel.AddContent(spacer);			
				
			NEW(enableWB);
			enableWB.bounds.SetExtents(ButtonHeight, ButtonHeight); enableWB.alignment.Set(WMComponents.AlignLeft);
			enableWB.bounds.SetLeft(ButtonWidth + ButtonSpacer); enableWB.bounds.SetTop(ButtonHeight + ButtonSpacer);
			enableWB.onClick.Add(EnableWB); enableWB.SetCaption(""); enableWB.visible.Set(FALSE);
			mountPanel.AddContent(enableWB);
			
			NEW(enableWBlabel);
			enableWBlabel.bounds.SetWidth(70); enableWBlabel.bounds.SetHeight(ButtonHeight); enableWBlabel.alignment.Set(WMComponents.AlignLeft);
			enableWBlabel.fillColor.Set(WindowBg); enableWBlabel.caption.SetAOC(" Writeback"); enableWBlabel.visible.Set(FALSE);
			mountPanel.AddContent(enableWBlabel);

			NEW(forceRW);
			forceRW.bounds.SetExtents(ButtonHeight, ButtonHeight); forceRW.alignment.Set(WMComponents.AlignLeft);
			forceRW.bounds.SetLeft(ButtonWidth + ButtonSpacer); forceRW.bounds.SetTop(ButtonHeight + ButtonSpacer);
			forceRW.onClick.Add(ForceRW); forceRW.SetCaption(""); forceRW.visible.Set(FALSE);
			mountPanel.AddContent(forceRW);
			
			NEW(forceRWlabel);
			forceRWlabel.bounds.SetWidth(160); forceRWlabel.bounds.SetHeight(ButtonHeight); forceRWlabel.alignment.Set(WMComponents.AlignLeft);
			forceRWlabel.fillColor.Set(WindowBg); forceRWlabel.caption.Set(Utilities.NewString(" Force R/W"));
			forceRWlabel.visible.Set(FALSE);
			mountPanel.AddContent(forceRWlabel);			
			
			panel.AddContent(mountPanel);
			
			NEW(unmount);
			unmount.bounds.SetExtents(ButtonWidth, ButtonHeight); 
			unmount.bounds.SetLeft(0); unmount.bounds.SetTop(ButtonHeight + ButtonSpacer);
			unmount.onClick.Add(Unmount);	unmount.SetCaption("Unmount");
			panel.AddContent(unmount);
			
			NEW(force);
			force.bounds.SetExtents(ButtonHeight, ButtonHeight);
			force.bounds.SetLeft(ButtonWidth + ButtonSpacer); force.bounds.SetTop(ButtonHeight + ButtonSpacer);
			force.onClick.Add(Force); force.SetCaption("");
			panel.AddContent(force);

			NEW(label);
			label.bounds.SetExtents(40, ButtonHeight);
			label.bounds.SetLeft(ButtonWidth + ButtonHeight + 2*ButtonSpacer); label.bounds.SetTop(ButtonHeight + ButtonSpacer);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("Force"));
			panel.AddContent(label);
			
			NEW(info);
			info.bounds.SetLeft(ButtonWidth + ButtonHeight + 2*ButtonSpacer + 40); info.bounds.SetTop(ButtonHeight + ButtonSpacer);
			info.fillColor.Set(WindowBg); info.caption.Set(Utilities.NewString(" File System Info: n/a"));
			panel.AddContent(info);			
		END Init;
		
	END FSTools;

TYPE

	ConfigEntry* = RECORD
		key*, value* : Utilities.String;
	END;
	
	ConfigTable* = POINTER TO ARRAY OF ConfigEntry;

	ConfigEditor = OBJECT(WMComponents.FormWindow);
	VAR
		config : AosPartitionsLib.Configuration;
		configTable : ConfigTable;
		popup : WMPartitions.PopupWindow;
	
		mainpanel  : WMStandardComponents.Panel;
		titlelabel : WMPartitions.BorderLabel;
		
		(* config grid *)
		grid : WMPartitions.NoWheelGrid;
		gridContainer : WMStandardComponents.Panel;
		gridPanel : WMPartitions.BevelPanel;
		selectedRow : LONGINT;
		cellHeight : LONGINT;
		scrollbarY : WMStandardComponents.Scrollbar;
		
		(* edit panel *)
		editPanel : WMPartitions.BevelPanel;
		editorKey, editorValue : WMEditors.Editor;
		add, delete, replace, clear, moveup, movedown : WMStandardComponents.Button;
		
		(* operation panel *)
		opPanel : WMPartitions.BevelPanel;
		set, get : WMStandardComponents.Button;
		toFile, toPartition : WMStandardComponents.Button; (* check boxes *)
		editorFile, editorPartition : WMEditors.Editor;
		target : LONGINT; (* ToFile | ToPartition *)
		fileLeft : LONGINT; (* left offset from editorFile *)
		
		statusLabel : WMStandardComponents.Label;
		
		hex : ARRAY 32 OF CHAR;
	
		PROCEDURE LoadFromPartition(devpart : ARRAY OF CHAR) : BOOLEAN;
		VAR
			getConfig : AosPartitionsLib.GetConfig;
			selection : AosPartitionsLib.Selection;
			caption : ARRAY 128 OF CHAR;
			fs, res : LONGINT;
		BEGIN
			IF AosPartitionsLib.diskModel.GetDisk(devpart, selection, FALSE) THEN 
				fs := AosPartitionsLib.DetectFS(selection.disk.device, selection.partition);
				IF fs = 3 THEN (* new AosFS *)
					NEW(getConfig, selection.disk, selection.partition, FALSE);
					getConfig.SetBlockingStart;
					IF getConfig.state.status * AosPartitionsLib.StatusError = {} THEN
						config.table := getConfig.GetTable();
						ParseTable;
						caption := " Configuration string loaded from partition "; Utilities.Append(caption, getConfig.diskpartString); 
						statusLabel.caption.Set(Utilities.NewString(caption));
						caption := ""; Utilities.Append(caption, getConfig.diskpartString); 
						Utilities.Append(caption, "("); Utilities.Append(caption, selection.disk.device.desc); Utilities.Append(caption, ")");
						titlelabel.caption.Set(Utilities.NewString(caption));
						RETURN TRUE;
					ELSE
						caption := " Error: Could not load configuration from partition ";
						Utilities.Append(caption, AosPartitionsLib.GetErrorMsg(getConfig.diskpartString, res));
						statusLabel.caption.Set(Utilities.NewString(caption));
					END;
				ELSE
					caption := " Error: Could not load configuration from partition (Filesystem is not AosFS) ";
					statusLabel.caption.Set(Utilities.NewString(caption));
				END;
			ELSE
				caption := " Error: Could not load configuration from partition (Could not get disk)";
				statusLabel.caption.Set(Utilities.NewString(caption));
			END;
			RETURN FALSE;
		END LoadFromPartition;
		
		PROCEDURE StoreToPartition(devpart : ARRAY OF CHAR);
		VAR
			setConfig : AosPartitionsLib.SetConfig;
			selection : AosPartitionsLib.Selection;
			caption : ARRAY 128 OF CHAR;
			params : WMPartitions.Parameters;
			string : Utilities.String;
			res : LONGINT; 
		BEGIN
			IF AosPartitionsLib.diskModel.GetDisk(devpart, selection, FALSE) THEN
				string := GetAsString();
				IF string # NIL THEN 
					NEW(popup, 200, 100, FALSE); params := NIL; 
					popup.SetTextAsString("Are you sure?");
					popup.SetParameters("Write config to ", selection, params);
					popup.Popup(100, 100, res);
					IF res = WMPartitions.ResOk THEN
						NEW(setConfig, selection.disk, selection.partition, FALSE);
						setConfig.SetParameters(string, 0);
						setConfig.SetBlockingStart;
						IF setConfig.state.status * AosPartitionsLib.StatusError = {} THEN
							caption := "Configuration loaded from "; Utilities.Append(caption, setConfig.diskpartString);
							statusLabel.caption.Set(Utilities.NewString(caption));
						ELSE 
							caption := ""; Utilities.Append(caption, setConfig.GetResult()); 
							statusLabel.caption.Set(Utilities.NewString(caption));
						END;
					END;
					popup := NIL;
				ELSE statusLabel.caption.Set(Utilities.NewString("Could not get config string"));
				END;
			ELSE
				caption := " Error: Could not load configuration from partition (Could not get disk) ";
				statusLabel.caption.Set(Utilities.NewString(caption));
			END;
		END StoreToPartition;
		
		PROCEDURE LoadFromFile(filename : ARRAY OF CHAR);
		VAR
			f : AosFS.File; r: AosFS.Reader;
			caption, temp : ARRAY 128 OF CHAR;
			buffer : POINTER TO ARRAY OF CHAR; 
			len : LONGINT;
		BEGIN
			f := AosFS.Old(filename);
			IF f # NIL THEN
				NEW(buffer, f.Length()); NEW(r, f, 0);
				r.Bytes(buffer^, 0, f.Length(), len);
				IF (r.res = AosIO.Ok) & (len =  f.Length()) THEN 
					IF ParseFile(buffer^) THEN 
						caption := " Configuration string loaded from "; Utilities.Append(caption, filename);
						statusLabel.caption.Set(Utilities.NewString(caption));
						titlelabel.caption.Set(Utilities.NewString(filename));
					ELSE
						statusLabel.caption.Set(Utilities.NewString("Parse error"));
					END;
					UpdateGrid; 
				ELSE
					caption := " Error: Could not load configuration from file (res: ";
					Utilities.IntToStr(r.res, temp); Utilities.Append(caption, temp); Utilities.Append(caption, ")");
					statusLabel.caption.Set(Utilities.NewString(caption));
				END;
			ELSE
				caption := " Error: Could not load configuration from file (";
				Utilities.Append(caption, filename); Utilities.Append(caption, " not found)");
				statusLabel.caption.Set(Utilities.NewString(caption));
			END;
		END LoadFromFile;
	
		PROCEDURE StoreToFile(filename : ARRAY OF CHAR);
		VAR
			f : AosFS.File; w : AosFS.Writer;
			caption : ARRAY 128 OF CHAR;
			string : Utilities.String;
		BEGIN
			IF config.table # NIL THEN 
				IF LEN(config.table) <= AosPartitionsLib.MaxConfig + 48 THEN 
					string := GetAsString();
					ASSERT(string#NIL);
					f := AosFS.New(filename);
					IF f#NIL THEN
						AosFS.OpenWriter(w, f, 0); w.String(string^); w.Update;
						IF w.res = AosIO.Ok THEN 
							AosFS.Register(f); f.Update;
							caption := " Configuration string stored to "; Utilities.Append(caption, filename);
							statusLabel.caption.Set(Utilities.NewString(caption));
						ELSE 
							statusLabel.caption.Set(Utilities.NewString("Write to file failed"));
						END;
					ELSE
						caption := " Error: Could not store configuration to file (Could not open ";
						Utilities.Append(caption, filename); Utilities.Append(caption, ")");
						statusLabel.caption.Set(Utilities.NewString(caption));
					END;
				ELSE statusLabel.caption.Set(Utilities.NewString(" Error: Configuration string is longer than MaxConfig"));
				END;
			ELSE statusLabel.caption.Set(Utilities.NewString(" Error: Cannot store empty configuration"));
			END;
		END StoreToFile;
			
		PROCEDURE ParseFile(buf : ARRAY OF CHAR) : BOOLEAN;
		VAR
			r : AosIO.StringReader;
			temp : ARRAY 1024 OF CHAR; ch : CHAR;
			entry : ConfigEntry;
			error : BOOLEAN;
			i : LONGINT;
		BEGIN
			configTable := NIL;
			NEW(r, LEN(buf)); r.SetRaw(buf, 0 , LEN(buf)); error := FALSE; i := 0;
			LOOP
				r.SkipWhitespace; 
				ch := r.Peek();
				IF ch = "~" THEN (* end of configuration string *)
				 	EXIT;
				END;
				(* read key *)
				r.String(temp); 
				IF r.res = AosIO.Ok THEN 
					Utilities.Trim(temp, " ");
					entry.key := Utilities.NewString(temp);
				ELSE error := TRUE; EXIT;
				END;
				r.SkipWhitespace;
				r.Char(ch);
				IF (r.res # AosIO.Ok) OR (ch # "=") THEN error := TRUE; EXIT; END;
				r.SkipWhitespace;
				(* read value *)
				r.String(temp);
				IF r.res = AosIO.Ok THEN 
					Utilities.Trim(temp, " ");
					entry.value := Utilities.NewString(temp);
				ELSE error := TRUE; EXIT;
				END;
				r.SkipSpaces;
				IF ~r.EOLN() THEN error := TRUE; EXIT; END;
				AddEntry(i, entry); INC(i);
			END;
			RETURN ~error;
		END ParseFile;
		
		(* builds up configTable from config.table*)
		PROCEDURE ParseTable;
		VAR
			entry : ConfigEntry;
			key, value : ARRAY CeMaxStringLength OF CHAR;
			ch : CHAR;
			i, j, pos : LONGINT;
		BEGIN
			configTable := NIL;
			IF config.table # NIL THEN
				i := config.FindEntry(0, 8);
				IF i >= 0 THEN
					pos := 0;
					INC(i, 8);
					WHILE config.table[i] # 0X DO
						key := ""; j := 0;
						REPEAT (* get key *)
							key[j] := config.table[i]; INC(i); INC(j);
						UNTIL config.table[i] = 0X;
						key[j] := 0X;
						entry.key := Utilities.NewString(key);
						
						value := ""; j := 0;
						LOOP (* get value *)
							INC(i); ch := config.table[i];
							IF ch = 0X THEN EXIT END;
							IF (ch >= " ") & (ch < 7FX) THEN
								value[j] := config.table[i];
							ELSE
								value[j] := "%"; INC(j); 
								value[j] :=  hex[ORD(ch) DIV 10H]; INC(j);
								value[j] :=  hex[ORD(ch) MOD 10H]; 
							END;
							INC(j);
						END;
						value[j] := 0X;
						entry.value := Utilities.NewString(value);
						AddEntry(pos, entry); (* append entry *) 
						INC(i); INC(pos);
					END
				END;
			END;
		END ParseTable;
		
		PROCEDURE GetAsString() : Utilities.String;
		VAR
			string : ARRAY AosPartitionsLib.MaxConfigString OF CHAR;
			w : AosIO.StringWriter;
			i : LONGINT;
		BEGIN
			NEW(w, AosPartitionsLib.MaxConfigString);
			FOR i := 0 TO LEN(configTable)-1 DO
				w.String(configTable[i].key^); w.String(" = "); w.Char(22X); w.String(configTable[i].value^); w.Char(22X); w.Ln;
				IF w.res # AosIO.Ok THEN 
					RETURN NIL;
				END;
			END;
			w.Char("~"); w.Get(string);
			RETURN Utilities.NewString(string);
		END GetAsString;
		
		PROCEDURE AddEntry(pos : LONGINT; entry : ConfigEntry);
		VAR
			newTable : ConfigTable;
			i, j : LONGINT;
		BEGIN
			ASSERT(pos >=0);
			IF configTable = NIL THEN 
				NEW(configTable, 1); configTable[0] := entry;
			ELSE
				 ASSERT(pos < LEN(configTable)+1);
				NEW(newTable, LEN(configTable)+1);
				i := 0; j := 0;
				LOOP
					IF i = pos THEN
						newTable[i] := entry;
					ELSE
						newTable[i] := configTable[j];
						INC(j);
					END;
					INC(i); IF i >= LEN(newTable) THEN EXIT END;
				END;
				configTable := newTable;
			END;
		END AddEntry;
		
		PROCEDURE RemoveEntry(entry : LONGINT);
		VAR
			newTable : ConfigTable;
			i, j : LONGINT;
		BEGIN 
			IF configTable#NIL THEN
				IF LEN(configTable) = 1 THEN 
					configTable := NIL;
				ELSE
					NEW(newTable, LEN(configTable) -1);
					j := 0;
					FOR i := 0 TO LEN(configTable) - 1 DO 
						IF  i # entry THEN 
							newTable[j] := configTable[i]; INC(j);
						END;
					END;
					configTable := newTable;
				END;
			END;
		END RemoveEntry;
		
		PROCEDURE SwapEntries(i, j : LONGINT);
		VAR temp : ConfigEntry;
		BEGIN
			IF (i >= 0) & (i < LEN(configTable)) & (j >= 0) & (j < LEN(configTable)) THEN 
				temp := configTable[i];
				configTable[i] := configTable[j];
				configTable[j] := temp;
			END;
		END SwapEntries;
		
		PROCEDURE SetSelection*(selection : WMPartitions.Selection) : BOOLEAN;
		VAR string, diskpartStr : ARRAY 128 OF CHAR; temp : ARRAY 4 OF CHAR; res : LONGINT;
		BEGIN
			diskpartStr := "";
			Utilities.Append(diskpartStr, selection.disk.device.name); 
			Utilities.Append(diskpartStr, "#"); Utilities.IntToStr(selection.partition, temp); Utilities.Append(diskpartStr, temp);			
			editorPartition.SetAsString(diskpartStr);
			string := " ";
			Utilities.Append(string, diskpartStr);
			Utilities.Append(string, " ("); Utilities.Append(string, selection.disk.device.desc); Utilities.Append(string, ")");
			titlelabel.caption.Set(Utilities.NewString(string));
			config.GetTable(selection.disk.device, selection.partition, res);
			ParseTable;
			UpdateGrid;
			RETURN res = AosDisks.Ok;
		END SetSelection;
		
		PROCEDURE WheelMove*(dz : LONGINT);
		CONST	Multiplier = 30;
		VAR pos : LONGINT;
		BEGIN
			IF scrollbarY.visible.Get() THEN
				pos := scrollbarY.pos.Get() + Multiplier*dz;
				IF pos < scrollbarY.min.Get() THEN pos := scrollbarY.min.Get(); END;
				IF pos > scrollbarY.max.Get() THEN pos := scrollbarY.max.Get(); END;
				scrollbarY.pos.Set(pos);
			END;
		END WheelMove; 
		
		PROCEDURE ButtonHandler(sender, data : PTR);
		VAR
			button : WMStandardComponents.Button;
			entry : ConfigEntry;
			string : ARRAY 1024 OF CHAR;
		BEGIN
			button := sender (WMStandardComponents.Button);
			IF button = add THEN 
				editorKey.GetAsString(string); entry.key := Utilities.NewString(string);
				editorValue.GetAsString(string); entry.value := Utilities.NewString(string);
				AddEntry(selectedRow, entry);
				UpdateGrid;
			ELSIF button = delete THEN
				RemoveEntry(selectedRow);
				UpdateGrid;
			ELSIF button = replace THEN
				editorKey.GetAsString(string); configTable[selectedRow].key := Utilities.NewString(string);
				editorValue.GetAsString(string); configTable[selectedRow].value := Utilities.NewString(string);
				UpdateGrid;
			ELSIF button = clear THEN 
				editorKey.SetAsString("");
				editorValue.SetAsString("");
			ELSIF button = moveup THEN
				SwapEntries(selectedRow, selectedRow -1);
				IF selectedRow > 0 THEN 
					grid.Acquire; grid.SetSelection(0, selectedRow - 1, 0, selectedRow-1);grid.Release;
					selectedRow := selectedRow - 1;
				END;
				UpdateGrid;
			ELSIF button = movedown THEN 
				SwapEntries(selectedRow, selectedRow + 1);
				IF selectedRow < LEN(configTable)-1 THEN 
					grid.Acquire; grid.SetSelection(0, selectedRow + 1, 0, selectedRow +1); grid.Release;
					selectedRow := selectedRow + 1;
				END;
				UpdateGrid;
			ELSIF button = get THEN
				IF target = ToFile THEN
					editorFile.GetAsString(string);
					LoadFromFile(string);
				ELSIF target = ToPartition THEN
					editorPartition.GetAsString(string);
					IF LoadFromPartition(string) THEN UpdateGrid; END;
				ELSE
					HALT(397);
				END;
			ELSIF button = set THEN 
				IF target = ToFile THEN
					editorFile.GetAsString(string);
					StoreToFile(string);
				ELSIF target = ToPartition THEN
					editorPartition.GetAsString(string);
					StoreToPartition(string);
				ELSE
					HALT(397);
				END;
			ELSE
				HALT(398);
			END;
		END ButtonHandler;
		
		PROCEDURE ScrollY(sender, data : PTR);
		VAR y : WMProperties.Int32Property;
		BEGIN
			y := data (WMProperties.Int32Property);
			grid.bounds.SetTop(-y.Get()); 
		END ScrollY;
		
		PROCEDURE CheckboxHandler(sender, data : PTR);
		VAR button : WMStandardComponents.Button;
		BEGIN
			button := sender (WMStandardComponents.Button);
			toFile.caption.Set(Utilities.NewString(""));
			toPartition.caption.Set(Utilities.NewString(""));
			IF button = toFile THEN 
				target := ToFile; toFile.caption.Set(Utilities.NewString("X"));
			ELSIF button = toPartition THEN 
				target := ToPartition; toPartition.caption.Set(Utilities.NewString("X"));
			ELSE
				HALT(398);
			END;
		END CheckboxHandler;

		PROCEDURE GridClicked(sender, data : ANY);
		VAR grid : WMPartitions.NoWheelGrid; ignore, row : LONGINT; string : Utilities.String;
		BEGIN
			grid := sender (WMPartitions.NoWheelGrid); 
			grid.GetSelection(ignore, row, ignore, ignore);	
			selectedRow := row;
			grid.Acquire;
			grid.model.Acquire;
			string := grid.model.GetCellText(0, row); editorKey.SetAsString(string^);
			string := grid.model.GetCellText(1, row); editorValue.SetAsString(string^);
			grid.model.Release;
			grid.Release;  
		END GridClicked;
		
		PROCEDURE UpdateGrid;
		VAR row, height : LONGINT; spacings : WMGrids.Spacings;
		BEGIN
			IF configTable # NIL THEN 
				grid.Acquire;
				grid.model.Acquire;
				grid.model.SetNofRows(LEN(configTable));
				FOR row := 0 TO LEN(configTable)-1 DO
					grid.model.SetCellText(0, row, configTable[row].key);
					grid.model.SetCellText(1, row, configTable[row].value);
					height := height + cellHeight + CeCellHeightMinSpacer + 1;
				END;
				NEW(spacings, LEN(configTable));
				FOR row := 0 TO LEN(configTable)-1 DO spacings[row] := cellHeight + CeCellHeightMinSpacer; END;
				grid.SetRowSpacings(spacings);
				grid.model.Release;
				grid.Release;
				grid.bounds.SetExtents(2000, height);
			ELSE
				grid.Acquire;
				grid.model.Acquire;
				grid.model.SetNofRows(1);
				grid.model.SetCellText(0, row, Utilities.NewString(""));
				grid.model.SetCellText(1, row, Utilities.NewString("No config loaded"));
				NEW(spacings, 1); spacings[0] := cellHeight + CeCellHeightMinSpacer; grid.SetRowSpacings(spacings);
				grid.model.Release;
				grid.Release;
				grid.bounds.SetExtents(2000, spacings[0]+1);
			END;
			UpdateLayout(SELF.bounds.r - SELF.bounds.l, SELF.bounds.b - SELF.bounds.t);
		END UpdateGrid;
		
		PROCEDURE UpdateLayout(width, height : LONGINT);
		VAR gridHeight : LONGINT;
		BEGIN
			DisableUpdate; 
			mainpanel.bounds.SetExtents(width, height);
			titlelabel.bounds.SetExtents(width - 2*MainPanelMarginH, CeLabelHeight);
			gridPanel.bounds.SetExtents(width - 2*MainPanelMarginH, height - CeLabelHeight - CeStatusLabelHeight- CeOpPanelHeight - CeEditPanelHeight - 5*MainPanelMarginV);
			gridContainer.bounds.SetExtents(gridPanel.bounds.GetWidth() - 2*DiskOverviewPanelMarginH, gridPanel.bounds.GetHeight() - 2*DiskOverviewPanelMarginV);
			IF configTable # NIL THEN 
				gridHeight := LEN(configTable)*(cellHeight + CeCellHeightMinSpacer + 1); 
			END;
			scrollbarY.bounds.SetLeft(gridContainer.bounds.GetWidth() - scrollbarY.bounds.GetWidth());
			scrollbarY.bounds.SetHeight(gridContainer.bounds.GetHeight());
			
			IF gridHeight > gridContainer.bounds.GetHeight() THEN 
				scrollbarY.pos.Set(ENTIER(1.0*scrollbarY.pos.Get()*(1.0*(gridHeight-gridContainer.bounds.GetHeight()) / scrollbarY.max.Get())));
				scrollbarY.max.Set(gridHeight-gridContainer.bounds.GetHeight());
				scrollbarY.visible.Set(TRUE);
			ELSE
				scrollbarY.visible.Set(FALSE);
			END;
			editPanel.bounds.SetTop(height - CeOpPanelHeight - CeEditPanelHeight - CeStatusLabelHeight - 2*MainPanelMarginV);
			editPanel.bounds.SetExtents(width - 2*MainPanelMarginH, CeEditPanelHeight);
			editorValue.bounds.SetWidth(width - CeKeyWidth - 2*MainPanelMarginH - 2*DiskOverviewPanelMarginH);
			opPanel.bounds.SetExtents(width - 2*MainPanelMarginH, CeOpPanelHeight);
			opPanel.bounds.SetTop(height - CeStatusLabelHeight - CeOpPanelHeight - MainPanelMarginV);
			editorFile.bounds.SetWidth(width - fileLeft - 2*MainPanelMarginH - DiskOverviewPanelMarginH);
			statusLabel.bounds.SetExtents(width, CeStatusLabelHeight);
			statusLabel.bounds.SetTop(height - CeStatusLabelHeight);
			EnableUpdate; 
			CSChanged;
		END UpdateLayout;
		
		PROCEDURE Close;
		BEGIN
			Close^; IF popup # NIL THEN popup.Close; END;
		END Close;
		
		PROCEDURE Resized*(width, height : LONGINT);
		BEGIN
			Resized^(width, height);
			UpdateLayout(width, height);
		END Resized;
		
		PROCEDURE &Init(width, height : LONGINT; alpha : BOOLEAN);
		VAR
			left, ignore : LONGINT;
			spacings : WMGrids.Spacings;
			font : WMGraphics.Font;
			label : WMStandardComponents.Label;
		BEGIN
			Init^(width, height, alpha); scaling := FALSE; hex := "0123456789ABCDEF";
			NEW(config);
			
			NEW(mainpanel); mainpanel.bounds.SetLeft(0); mainpanel.bounds.SetTop(0); mainpanel.fillColor.Set(WindowBg);
			
			NEW(titlelabel); titlelabel.bounds.SetLeft(MainPanelMarginH); titlelabel.bounds.SetTop(MainPanelMarginV);
			mainpanel.AddContent(titlelabel);
			
			NEW(gridPanel); gridPanel.bounds.SetLeft(MainPanelMarginH); gridPanel.bounds.SetTop(CeLabelHeight + 2*MainPanelMarginV);
			mainpanel.AddContent(gridPanel);
			
			NEW(gridContainer); gridContainer.bounds.SetLeft(DiskOverviewPanelMarginH); gridContainer.bounds.SetTop(DiskOverviewPanelMarginV);
			gridPanel.AddContent(gridContainer);
		
			NEW(grid);
			grid.fixedCols.Set(1); 
			grid.onClick.Add(GridClicked); grid.SetSelectionMode(WMGrids.GridSelectSingleRow); 
			grid.alwaysShowScrollX.Set(FALSE); grid.showScrollX.Set(FALSE);  
			grid.alwaysShowScrollY.Set(FALSE); grid.showScrollY.Set(FALSE);		
			grid.allowColResize.Set(TRUE); grid.allowRowResize.Set(FALSE);
			NEW(spacings, 2); spacings[0] := CeKeyWidth; spacings[1] := 2000; (* since allowColResize *)
			grid.Acquire;
			grid.model.Acquire;
			grid.model.SetNofCols(2); grid.SetColSpacings(spacings);		
			grid.model.Release;
			grid.Release;
			gridContainer.AddContent(grid);
			
			NEW(scrollbarY);
			scrollbarY.vertical.Set(TRUE); scrollbarY.bounds.SetHeight(gridContainer.bounds.GetHeight());
			scrollbarY.bounds.SetTop(0); scrollbarY.bounds.SetLeft(gridContainer.bounds.GetWidth() - scrollbarY.bounds.GetWidth());
			scrollbarY.min.Set(0); scrollbarY.onPositionChanged.Add(ScrollY);
			gridContainer.AddContent(scrollbarY); 
			
			font := grid.GetFont(); font.GetStringSize("TestString", ignore, cellHeight);
			
			NEW(editPanel); editPanel.bounds.SetLeft(MainPanelMarginH);
			editPanel.bounds.SetTop(height - CeEditPanelHeight - CeStatusLabelHeight - CeOpPanelHeight - 2*MainPanelMarginV);
			mainpanel.AddContent(editPanel);
			
			NEW(editorKey);
			editorKey.bounds.SetExtents(CeKeyWidth, ButtonHeight); 
			editorKey.bounds.SetLeft(DiskOverviewPanelMarginH); editorKey.bounds.SetTop(DiskOverviewPanelMarginV);
			editorKey.multiLine.Set(FALSE); editorKey.fillColor.Set(0FFFFFFFFH);
			editorKey.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); editorKey.tv.showBorder.Set(TRUE);
			editPanel.AddContent(editorKey);

			NEW(editorValue);
			editorValue.bounds.SetExtents(width - CeKeyWidth - 2*MainPanelMarginH - 2*DiskOverviewPanelMarginH, ButtonHeight); 
			editorValue.bounds.SetLeft(CeKeyWidth + DiskOverviewPanelMarginH); editorValue.bounds.SetTop(DiskOverviewPanelMarginV);
			editorValue.multiLine.Set(FALSE); editorValue.fillColor.Set(0FFFFFFFFH);
			editorValue.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); editorValue.tv.showBorder.Set(TRUE);
			editPanel.AddContent(editorValue);
			
			NEW(add); left := DiskOverviewPanelMarginH;
			add.bounds.SetExtents(ButtonWidth, ButtonHeight);
			add.bounds.SetLeft(left); add.bounds.SetTop(DiskOverviewPanelMarginV + ButtonHeight + ButtonSpacer);
			add.onClick.Add(ButtonHandler); add.caption.Set(Utilities.NewString("Add"));
			editPanel.AddContent(add);
			
			NEW(delete); left := left + ButtonWidth + ButtonSpacer;
			delete.bounds.SetExtents(ButtonWidth, ButtonHeight);
			delete.bounds.SetLeft(left); delete.bounds.SetTop(DiskOverviewPanelMarginV + ButtonHeight + ButtonSpacer);
			delete.onClick.Add(ButtonHandler); delete.caption.Set(Utilities.NewString("Delete"));
			editPanel.AddContent(delete);
		
			NEW(replace); left := left + ButtonWidth + ButtonSpacer;
			replace.bounds.SetExtents(ButtonWidth, ButtonHeight);
			replace.bounds.SetLeft(left); replace.bounds.SetTop(DiskOverviewPanelMarginV + ButtonHeight + ButtonSpacer);
			replace.onClick.Add(ButtonHandler); replace.caption.Set(Utilities.NewString("Replace"));
			editPanel.AddContent(replace);
		
			NEW(clear); left := left + ButtonWidth + ButtonSpacer;
			clear.bounds.SetExtents(ButtonWidth, ButtonHeight);
			clear.bounds.SetLeft(left); clear.bounds.SetTop(DiskOverviewPanelMarginV + ButtonHeight + ButtonSpacer);
			clear.onClick.Add(ButtonHandler); clear.caption.Set(Utilities.NewString("Clear"));
			editPanel.AddContent(clear);
			
			NEW(moveup); left := left + ButtonWidth + ButtonSpacer;
			moveup.bounds.SetExtents(ButtonWidth, ButtonHeight);
			moveup.bounds.SetLeft(left); moveup.bounds.SetTop(DiskOverviewPanelMarginV + ButtonHeight + ButtonSpacer);
			moveup.onClick.Add(ButtonHandler); moveup.caption.Set(Utilities.NewString("Up"));
			editPanel.AddContent(moveup);

			NEW(movedown); 
			movedown.bounds.SetExtents(ButtonWidth, ButtonHeight);
			movedown.bounds.SetLeft(left); movedown.bounds.SetTop(DiskOverviewPanelMarginV + 2*ButtonHeight + 2*ButtonSpacer);
			movedown.onClick.Add(ButtonHandler); movedown.caption.Set(Utilities.NewString("Down"));
			editPanel.AddContent(movedown);
			
			NEW(opPanel);
			opPanel.bounds.SetExtents(width - 2*MainPanelMarginH, CeOpPanelHeight);
			opPanel.bounds.SetLeft(MainPanelMarginH); opPanel.bounds.SetTop(height - CeStatusLabelHeight - CeOpPanelHeight - MainPanelMarginV);
			mainpanel.AddContent(opPanel);
				
			NEW(get); left := DiskOverviewPanelMarginH;
			get.bounds.SetExtents(ButtonWidth, ButtonHeight);
			get.bounds.SetLeft(left); get.bounds.SetTop(DiskOverviewPanelMarginV);
			get.onClick.Add(ButtonHandler); get.caption.Set(Utilities.NewString("GetConfig"));
			opPanel.AddContent(get);
				
			NEW(set); left := left + ButtonWidth + ButtonSpacer;
			set.bounds.SetExtents(ButtonWidth, ButtonHeight);
			set.bounds.SetLeft(left); set.bounds.SetTop(DiskOverviewPanelMarginV);
			set.onClick.Add(ButtonHandler); set.caption.Set(Utilities.NewString("SetConfig"));
			opPanel.AddContent(set);
			
			target := ToPartition;
			NEW(toPartition); left := left + ButtonWidth + ButtonSpacer;
			toPartition.bounds.SetExtents(ButtonHeight, ButtonHeight);
			toPartition.bounds.SetLeft(left); toPartition.bounds.SetTop(DiskOverviewPanelMarginV);
			toPartition.onClick.Add(CheckboxHandler); toPartition.caption.Set(Utilities.NewString("X"));
			opPanel.AddContent(toPartition);
			
			NEW(label); left := left + ButtonHeight + ButtonSpacer;
			label.bounds.SetExtents(50, ButtonHeight); label.bounds.SetLeft(left); label.bounds.SetTop(DiskOverviewPanelMarginV);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("Partition:"));
			opPanel.AddContent(label);
			
			NEW(editorPartition); left := left + 50;
			editorPartition.bounds.SetExtents(50, ButtonHeight); 
			editorPartition.bounds.SetLeft(left); editorPartition.bounds.SetTop(DiskOverviewPanelMarginV);
			editorPartition.multiLine.Set(FALSE); editorPartition.fillColor.Set(0FFFFFFFFH);
			editorPartition.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); editorPartition.tv.showBorder.Set(TRUE);
			opPanel.AddContent(editorPartition);
			
			NEW(toFile); left := left + 50 + ButtonSpacer;
			toFile.bounds.SetExtents(ButtonHeight, ButtonHeight); 
			toFile.bounds.SetLeft(left); toFile.bounds.SetTop(DiskOverviewPanelMarginV);
			toFile.onClick.Add(CheckboxHandler); toFile.caption.Set(Utilities.NewString(""));
			opPanel.AddContent(toFile);
			
			NEW(label); left := left + ButtonHeight + ButtonSpacer;
			label.bounds.SetExtents(22, ButtonHeight); label.bounds.SetLeft(left); label.bounds.SetTop(DiskOverviewPanelMarginV);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("File:"));
			opPanel.AddContent(label);
			
			NEW(editorFile); left := left + 22 + ButtonSpacer; fileLeft := left; 
			editorFile.bounds.SetExtents(width - fileLeft - MainPanelMarginH - DiskOverviewPanelMarginH, ButtonHeight); 
			editorFile.bounds.SetLeft(left); editorFile.bounds.SetTop(DiskOverviewPanelMarginV);
			editorFile.multiLine.Set(FALSE); editorFile.fillColor.Set(0FFFFFFFFH);
			editorFile.tv.borders.Set(WMRectangles.MakeRect(3, 3, 1, 1)); editorFile.tv.showBorder.Set(TRUE);
			editorFile.SetAsString("Config.Bin"); (* default file name *)
			opPanel.AddContent(editorFile);
			
			NEW(statusLabel);
			statusLabel.bounds.SetLeft(0); statusLabel.bounds.SetTop(height - CeStatusLabelHeight);
			statusLabel.fillColor.Set(WMGraphics.Blue); statusLabel.textColor.Set(WMGraphics.Yellow);
			statusLabel.caption.Set(Utilities.NewString("Ready"));
			mainpanel.AddContent(statusLabel);
			
			SetTitle(Utilities.NewString("Configuration Editor"));
			SetContent(mainpanel);
			
			WMWindowManager.ExtAddWindow (SELF, 100, 100, {WMWindowManager.FlagFrame});
			manager := WMWindowManager.GetDefaultManager();
			manager.SetFocus(SELF);
			
			UpdateLayout(width, height);
		END Init;
		
	END ConfigEditor;

	(*
	 * The Partitions plugin is a graphical front-end for partitioning operations provided by AosPartitionsLib.Mod.
	 *)
	AosPartitionsPlugin = OBJECT (WMPartitions.PartitionsPlugin);
	VAR
		show, eject, checkPartition, activeBit, format, changeType, 
		delete, create, partitionToFile, fileToPartition, writeMBR, bench : WMStandardComponents.Button;	
		
		(** called whenever the size of the plugin panel changes *)
		PROCEDURE Resized*(width, height : LONGINT);
		BEGIN
			panel.bounds.SetExtents(width, height);
		END Resized;
		
		(** This procedure is called everytime when the selection has been updated *)
		(** Return value: SelectionValid, SelectionInvalid, SelectionMaybe *)
		PROCEDURE SelectionUpdated*(selection : WMPartitions.Selection) : LONGINT;
		VAR result : LONGINT;
		BEGIN
			SELF.selection := selection;
			IF IsValid(selection) THEN 
				IF AosDisks.Boot IN selection.disk.table[selection.partition].flags THEN
					activeBit.caption.Set(Utilities.NewString("Deactivate"));
				ELSE
					activeBit.caption.Set(Utilities.NewString("Activate"));
				END;
				result := WMPartitions.SelectionMaybe;		
			ELSE
				result := WMPartitions.SelectionInvalid;
			END;
			RETURN result;
		END SelectionUpdated;
		
		(* Create a new extended or primary partition. *)
		PROCEDURE Create(sender, data : PTR);
		VAR
			create : AosPartitionsLib.CreatePartition;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) & ~selection.disk.isDiskette THEN 
				NEW(param, 2);
				param[0].description := "Size"; param[0].type := WMPartitions.ParInteger; param[0].width := 0;
				param[0].optional := FALSE; param[0].default := FALSE;
				param[1].description := "Type"; param[1].type := WMPartitions.ParInteger; param[1].width := 0;
				param[1].optional := FALSE; param[1].default := FALSE;
				NEW(popup, 220, 160, FALSE); 
				popup.SetTextAsString("Enter size [MB] and type of the partition to be created. To create an extended partition, select type 5.");
				popup.SetParameters("Create a new partition on", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					ASSERT(param[0].valid);
					NEW(create, selection.disk, selection.partition, FALSE);
					create.SetParameters(param[0].resInteger, param[1].resInteger);
					create.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection Invalid")); 
			END;
		END Create;

		(* Delete the selected partition. *)
		PROCEDURE Delete(sender, data : PTR);
		VAR
			delete : AosPartitionsLib.DeletePartition;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF  ~selection.disk.isDiskette & IsValid(selection) & 
			    (selection.disk.device # NIL) & (selection.partition < LEN(selection.disk.device.table)) 
			    THEN 
				NEW(popup, 200, 100, FALSE);
				popup.SetTextAsString("Delete partition?"); 
				param := NIL;
				popup.SetParameters("Delete partition", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					NEW(delete, selection.disk, selection.partition, FALSE);
					delete.SetParameters(selection.disk.table[selection.partition].type);
					delete.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection invalid")); 
			END;
		END Delete;
		
		(* Write a MBR to the selected device *)
		PROCEDURE WriteMBR(sender, data : PTR);
		VAR
			writeMBR : AosPartitionsLib.WriteMBR;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF (selection.disk.device # NIL) & (selection.partition = 0) & (selection.disk.table # NIL) & ~selection.disk.isDiskette THEN 
				NEW(popup, 200, 150, FALSE);
				popup.SetTextAsString("Write MBR to partition?"); 
				NEW(param, 2);
				param[0].description := "MBR file"; param[0].type := WMPartitions.ParString; param[0].optional := FALSE; 
				param[0].width := 0; param[0].default := TRUE; param[0].resString := "OBEMBR.BIN";
				param[1].description := "Preserve Table"; param[1].type := WMPartitions.ParBoolean;
				param[1].default := TRUE; param[1].resBoolean := TRUE;
				popup.SetParameters("Write MBR to", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					NEW(writeMBR, selection.disk, selection.partition, FALSE);
					writeMBR.SetParameters(param[0].resString, param[1].resBoolean);
					writeMBR.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection invalid")); 
			END;
		END WriteMBR;

		(* Format the selected partition. *)
		PROCEDURE Format (sender, data : PTR);
		VAR
			formatAOS : AosPartitionsLib.FormatPartition;
			formatFAT : AosFATScavenger.FormatPartition;
			volumelabel : Utilities.String;
			popup : WMPartitions.PopupWindow; params : WMPartitions.Parameters;
			cancel, doClose : BOOLEAN;
			fs : LONGINT;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) & ((selection.disk.table[selection.partition].flags * {AosDisks.Valid} # {}) OR selection.disk.isDiskette) THEN
			
				(* If a floppy drive is selected, check whether it contains a diskette *)
				cancel := FALSE; doClose := FALSE;
				IF selection.disk.isDiskette & (selection.disk.device.openCount < 1) THEN
					doClose := TRUE;
					selection.disk.device.Open(res);
					IF res = AosDisks.MediaMissing THEN
						cancel := TRUE;
						owner.UpdateStatusLabel(Utilities.NewString("No diskette inserted"));
					ELSIF res # AosDisks.Ok THEN
						cancel := TRUE;
						owner.UpdateStatusLabel(Utilities.NewString("Cannot open floppy device"));
					END;
				END;
				
				IF selection.disk.isDiskette THEN (* let the user choose the file system *)
					NEW(params, 1);
					params[0].description := "File System (FatFS or AosFS)"; params[0].type := WMPartitions.ParString;
					params[0].optional := FALSE; params[0].width := 0;
					NEW(popup, 250, 200, FALSE);
					popup.SetTextAsString("Format the selected diskette with the specified file system");
					popup.SetParameters("Format diskette", selection, params);
					popup.Popup(100,100,res);
					IF res = WMPartitions.ResOk THEN
						IF params[0].valid THEN
							IF params[0].resString = "FatFS" THEN
								fs := 2;
							ELSIF params[0].resString = "AosFS" THEN
								fs := 1;
							ELSE
								fs := 0; (* invalid paramter *)
							END;
						END;
					ELSE
						cancel := TRUE; (* user abort *)
					END;
				ELSE (* use file system that matches the partition type *)
					IF AosPartitionsLib.IsNativeType(selection.disk.table[selection.partition].type) THEN
						fs := 1;
					ELSIF AosPartitionsLib.IsFatType(selection.disk.table[selection.partition].type) THEN
						fs := 2;
					ELSE
						fs := 0; (* not supported *)
						owner.UpdateStatusLabel(Utilities.NewString("Only FatFS or AosFS supported"));
					END;
				END;
				
				IF cancel THEN
					(* do nothing *)
				ELSIF fs = 1 THEN 
					NEW(params, 4);
					params[0].description := "File System"; params[0].type := WMPartitions.ParString; 
					params[0].optional := FALSE; params[0].width := 0; params[0].resString := "AosFS"; params[0].default := TRUE;
					params[1].description := "[Bootfile]"; params[1].type := WMPartitions.ParString; 
					params[1].optional := TRUE;  params[1].width := 0; params[1].resString := "AosIDE.Bin"; params[1].default := TRUE;
					params[2].description := "[fsRes (KB)]"; params[2].type := WMPartitions.ParInteger; params[2].default := TRUE;
					params[2].optional := TRUE; params[2].width := 0; params[2].resInteger := 640;
					params[3].description := "[flags]"; params[3].type := WMPartitions.ParInteger; params[3].default := TRUE;
					params[3].optional := TRUE;  params[3].width := 0; params[3].resInteger := 0;
					NEW(popup, 250, 200, FALSE);
					popup.SetTextAsString("Enter parameters");
					popup.SetParameters("Format partition ", selection, params);
					popup.Popup(100,100, res);
					IF res = WMPartitions.ResOk THEN 
						IF params[1].valid = FALSE THEN params[1].resString := ""; END;
						(* filesystem [bootfilename] [fsres] [flags] *)
						NEW(formatAOS, selection.disk, selection.partition, FALSE);
						formatAOS.SetParameters(params[0].resString, params[1].resString, params[2].resInteger, params[3].resInteger);
						formatAOS.SetStart;
					END;
				ELSIF fs = 2 THEN 
					NEW(params, 2);
					params[0].description := "Volume label"; params[0].type := WMPartitions.ParString; 
					params[0].optional := TRUE; params[0].width := 0; params[0].default := FALSE;
					params[1].description := "Quickformat"; params[1].type := WMPartitions.ParBoolean; 
					params[1].optional := TRUE; params[1].width := 30; params[1].default := TRUE;
					params[1].resBoolean := FALSE;
					NEW(popup, 250, 150, FALSE);
					popup.SetTextAsString("Enter parameters");
					popup.SetParameters("Format partition ", selection, params);
					popup.Popup(100,100, res);
					IF res = WMPartitions.ResOk THEN 
						IF params[0].valid THEN volumelabel := Utilities.NewString(params[0].resString);
						ELSE volumelabel := Utilities.NewString("");
						END;
						NEW(formatFAT, selection.disk, selection.partition, FALSE);
						formatFAT.SetParameters(volumelabel, params[0].resBoolean);
						formatFAT.SetStart;
					END;
				ELSE owner.UpdateStatusLabel(Utilities.NewString("Can't format partition of this type"));
				END;
				
				IF selection.disk.isDiskette & doClose & (selection.disk.device.openCount > 0) THEN
					selection.disk.device.Close(res); (* ignore res *)
				END;
				
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END;
		END Format;

		(* Change the type of the selected partition. *)
		PROCEDURE ChangeType(sender, data : PTR);
		VAR
			changeType : AosPartitionsLib.ChangePartType;
			oldtype, newtype : LONGINT;
			popup : WMPartitions.PopupWindow; 
			param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) & (selection.disk.table[selection.partition].flags * {AosDisks.Valid} # {}) THEN
				NEW(param, 1);
				param[0].description := "New Type"; param[0].type := WMPartitions.ParInteger; param[0].optional := FALSE;
				param[0].width := 30; param[0].default := FALSE;
				NEW(popup, 200, 130, FALSE);
				popup.SetParameters("Change type of ", selection, param); popup.SetTextAsString("Enter new type");
				popup.Popup(100,100, res);
				IF res = WMPartitions.ResOk THEN 
					ASSERT(param[0].valid);
					NEW(changeType, selection.disk, selection.partition, FALSE);
					newtype := param[0].resInteger;
					oldtype := selection.disk.table[selection.partition].type;
					changeType.SetParameters(oldtype, newtype);
					changeType.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END;
		END ChangeType;
		
		(* Set the active bit for the selected partition. *)
		PROCEDURE ActiveBit(sender, data : PTR);
		VAR
			setFlags : AosPartitionsLib.SetFlags;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			string : ARRAY 64 OF CHAR;
			on : BOOLEAN;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) & (AosDisks.Valid IN selection.disk.table[selection.partition].flags) & ~selection.disk.isDiskette THEN 
				on := AosDisks.Boot IN selection.disk.table[selection.partition].flags;
				NEW(popup, 200, 100, FALSE);
				IF on THEN 
					string := "Deactivate partition";
				ELSE
					string := "Activate partition"; 
				END;
				param := NIL;
				popup.SetParameters(string, selection, param); popup.SetTextAsString("Are you sure?"); 
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					NEW(setFlags, selection.disk, selection.partition, FALSE);
					setFlags.SetParameters(~on);
					setFlags.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END;
		END ActiveBit;
		
		PROCEDURE FileToPartition(sender, data : PTR);
		VAR
			fileToPartition : AosPartitionsLib.FileToPartition;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			block, numblocks, res : LONGINT;
		BEGIN
			IF IsValid(selection) THEN
				NEW(param, 3);
				param[0].description := "Filename"; param[0].type := WMPartitions.ParString; param[0].optional := FALSE;
				param[0].width := 0; param[0].default := FALSE;
				param[1].description := "Offset"; param[1].type := WMPartitions.ParInteger; param[1].optional := TRUE;
				param[1].width := 0; param[1].default := FALSE;
				param[2].description := "Numblocks"; param[2].type := WMPartitions.ParInteger; param[2].optional := TRUE;
				param[2].width := 0; param[2].default := FALSE;
				NEW(popup, 200, 180, FALSE);
				popup.SetTextAsString("Write file <Filename> to the specified partition, starting at bock <Offset>, <Numblocks> blocks ");
				popup.SetParameters("FileToPartition on", selection, param);
				popup.Popup(100,100, res);
				IF res = WMPartitions.ResOk THEN 
					ASSERT(param[0].valid);
					NEW(fileToPartition, selection.disk, selection.partition, FALSE);
					IF param[1].valid THEN block := param[1].resInteger; ELSE block := -1; END;
					IF param[2].valid THEN numblocks := param[2].resInteger; ELSE numblocks := -1; END;
					fileToPartition.SetParameters(param[0].resString, block, numblocks); (* filename [block numblocks] *)
					fileToPartition.SetStart;
				END;
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END;
		END FileToPartition;
		
		PROCEDURE PartitionToFile(sender, data : PTR);
		VAR
			partitionToFile : AosPartitionsLib.PartitionToFile;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			block, numblocks, res : LONGINT;
		BEGIN
			IF IsValid(selection) THEN
				NEW(param, 3);
				param[0].description := "Filename"; param[0].type := WMPartitions.ParString; param[0].optional := FALSE;
				param[0].width := 0; param[0].default := FALSE;
				param[1].description := "Offset"; param[1].type := WMPartitions.ParInteger; param[1].optional := TRUE;
				param[1].width := 0; param[1].default := FALSE;
				param[2].description := "Numblocks"; param[2].type := WMPartitions.ParInteger; param[2].optional := TRUE;
				param[2].width := 0; param[2].default := FALSE;
				NEW(popup, 200, 180, FALSE);
				popup.SetTextAsString("Write partition to file <Filename>, starting at block <Offset>, <Numblocks> blocks. ");
				popup.SetParameters("PartitionToFile on ", selection, param);
				popup.Popup(100,100, res);
				IF res = WMPartitions.ResOk THEN 
					ASSERT(param[0].valid);
					IF param[1].valid THEN block := param[1].resInteger; ELSE block := -1; END;
					IF param[2].valid THEN numblocks := param[2].resInteger; ELSE numblocks := -1; END;
					NEW(partitionToFile, selection.disk, selection.partition, FALSE);
					partitionToFile.SetParameters(param[0].resString, block, numblocks); (* filename [block numblocks] *)
					partitionToFile.SetStart; 
				END;
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END;
		END PartitionToFile;
		
		(* Will be registered as callback at AosPartitionsLib.ShowBlocks *)
		PROCEDURE ShowCallback(text : AosTexts.Text);
		VAR window : WMPartitions.ReportWindow;
		BEGIN
			NEW(window, text, 560, 240, FALSE); window.Show;
		END ShowCallback;
		
		PROCEDURE Show(sender, data : PTR);
		VAR
			showBlocks : AosPartitionsLib.ShowBlocks;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			block, numblocks, res : LONGINT;
		BEGIN
			IF IsValid(selection) THEN
				NEW(param, 2);
				param[0].description := "Block"; param[0].type := WMPartitions.ParInteger; param[0].optional := FALSE;
				param[0].width := 0; param[0].default := FALSE;
				param[1].description := "Numblocks"; param[1].type := WMPartitions.ParInteger; param[1].optional := FALSE;
				param[1].width := 0; param[1].default := FALSE;
				NEW(popup, 200, 160, FALSE);
				popup.SetTextAsString("Show <numblocks> blocks of partition starting at block <block>");
				popup.SetParameters("Showblocks on", selection, param);
				popup.Popup(100,100, res);
				IF res = WMPartitions.ResOk THEN 
					ASSERT(param[0].valid);
					NEW(showBlocks, selection.disk, selection.partition, FALSE);
					block := param[0].resInteger; 
					numblocks := param[1].resInteger;
					showBlocks.SetParameters(block, numblocks); (* block [numblocks] *)
					showBlocks.SetCallback(ShowCallback);
					showBlocks.SetStart;
				END;
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END;
		END Show;
		
		PROCEDURE Eject(sender, data : PTR);
		VAR
			result : ARRAY 128 OF CHAR;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters; 
			eject : BOOLEAN;
			res : LONGINT;
		BEGIN
			IF (selection.disk.device # NIL) & (~selection.disk.isDiskette) THEN
				IF (AosDisks.Removable IN selection.disk.device.flags) THEN 
					eject := TRUE;
					IF selection.disk.device.openCount > 0 THEN 
						param := NIL;
						popup.SetParameters("Eject disk", selection,  param);
						NEW(popup, 200, 100, FALSE); 
						popup.SetTextAsString("Device is open. Do you really want to eject its media? ");
						popup.Popup(100,100, res);
						IF res # WMPartitions.ResOk THEN eject := FALSE; END;
					END;
					IF eject THEN 
						result := ""; Utilities.Append(result, AosPartitionsLib.Eject(selection.disk.device));
						owner.UpdateStatusLabel(Utilities.NewString(result));
					END;
				ELSE owner.UpdateStatusLabel(Utilities.NewString("Device not removable"));
				END;
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END;
		END Eject;
		
		PROCEDURE CheckPartition(sender, data : PTR);
		VAR checkPartition : AosPartitionsLib.CheckPartition;
		BEGIN
			IF IsValid(selection) THEN 
				NEW(checkPartition, selection.disk, selection.partition, FALSE);
				checkPartition.SetStart;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END;
		END CheckPartition;
		
		PROCEDURE BenchPartition(sender, data : PTR);
		VAR
			benchPartition : AosDiskBench.DiskBench;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			blocksizes : SET;
			i, blocksize, res : LONGINT;			
			string : ARRAY 128 OF CHAR;
		BEGIN
			IF IsValid(selection) & (selection.disk.device # NIL) THEN 
				NEW(popup, 300, 625, FALSE);
				popup.SetTextAsString("Benchmark Configuration");
				
				NEW(param, 21);
				param[0].description := "Perform Random Block Tests"; param[0].type := WMPartitions.ParBoolean;
				param[0].optional := TRUE; param[0].width := 0; param[0].default := TRUE;  param[0].resBoolean := TRUE;

				param[1].description := "NbrOfBlock for random test"; param[1].type := WMPartitions.ParInteger;
				param[1].optional := FALSE; param[1].width := 0; param[1].default := TRUE;  param[1].resInteger := 1000;

				param[2].description := "Perform Sequential Block Tests"; param[2].type := WMPartitions.ParBoolean;
				param[2].optional := TRUE; param[2].width := 0; param[2].default := TRUE;  param[2].resBoolean := TRUE;
				
				param[3].description := "Perform Read Tests"; param[3].type := WMPartitions.ParBoolean;
				param[3].optional := TRUE; param[3].width := 0; param[3].default := TRUE;  param[3].resBoolean := TRUE;
				
				param[4].description := "Perform Write Tests (DANGEROUS)"; param[4].type := WMPartitions.ParBoolean;
				param[4].optional := TRUE; param[4].width := 0; param[4].default := TRUE;  param[4].resBoolean := FALSE;
				
				blocksize := 512;
				FOR i := 1 TO 16 DO
					string := ""; Utilities.Append(string, WriteK(blocksize)); Utilities.Append(string, " Blocks");
					COPY(string, param[4+i].description);
					param[4+i].type := WMPartitions.ParBoolean;
					param[4+i].optional := TRUE; param[4+i].width := 0; param[4+i].default := TRUE; param[4+i].resBoolean := TRUE;
					blocksize := blocksize * 2;
				END;
				
				popup.SetParameters("Partition Benchmark", selection, param);
				popup.Popup(100,100, res);
				IF res = WMPartitions.ResOk THEN
					blocksizes := {};
					FOR i := 1 TO 16 DO
						IF param[4+i].resBoolean THEN INCL(blocksizes, i-1); END;
					END;
					NEW(benchPartition, selection.disk, selection.partition, FALSE);
					benchPartition.SetParameters(param[0].resBoolean, param[2].resBoolean, param[3].resBoolean, param[4].resBoolean, param[1].resInteger, blocksizes);
					benchPartition.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END;
		END BenchPartition;
		
		TYPE Str32 = ARRAY 32 OF CHAR;
		PROCEDURE WriteK*(k: LONGINT) : Str32;
		VAR suffix: ARRAY 3 OF CHAR; string : Str32;
		BEGIN
			IF k < 1024 THEN suffix := "B";
			ELSE k := k DIV 1024; suffix := "KB";
			END;
			Utilities.IntToStr(k, string); Utilities.Append(string, suffix); 
			RETURN string;
		END WriteK;

		(** This procedure is called when the WMPartitions Window is closed *)
		PROCEDURE Finalize*;
		BEGIN
		END Finalize;
		
		PROCEDURE &Init;
		VAR left : LONGINT;
		BEGIN
			SetName("Partitions"); desc := "Partitioning and Formatting Tool";
		
			NEW(panel);
			panel.bounds.SetLeft(0); panel.bounds.SetTop(0);	panel.fillColor.Set(WMPartitions.WindowBg);
			
			(* upper row of buttons *)
			NEW(create); left := 0;
			create.bounds.SetExtents(ButtonWidth, ButtonHeight); create.bounds.SetLeft(left); create.bounds.SetTop(0);
			create.onClick.Add(Create); create.SetCaption("Create");
			panel.AddContent(create);		
		
			NEW(format); left := left + ButtonWidth + ButtonSpacer; 
			format.bounds.SetExtents(ButtonWidth, ButtonHeight); format.bounds.SetLeft(left);  format.bounds.SetTop(0);
			format.onClick.Add(Format); format.SetCaption("Format");
			panel.AddContent(format);		

			NEW(fileToPartition); left := left + ButtonWidth + ButtonSpacer; 
			fileToPartition.bounds.SetExtents(ButtonWidth, ButtonHeight); fileToPartition.bounds.SetLeft(left); fileToPartition.bounds.SetTop(0);
			fileToPartition.onClick.Add(FileToPartition); fileToPartition.SetCaption("FromFile");
			panel.AddContent(fileToPartition);		
			
			NEW(activeBit); left := left + ButtonWidth + ButtonSpacer;
			activeBit.bounds.SetExtents(ButtonWidth, ButtonHeight); activeBit.bounds.SetLeft(left);  activeBit.bounds.SetTop(0);
			activeBit.onClick.Add(ActiveBit); activeBit.SetCaption("Activate");
			panel.AddContent(activeBit);		

			NEW(show); left := left + ButtonWidth + ButtonSpacer;
			show.bounds.SetExtents(ButtonWidth, ButtonHeight); show.bounds.SetLeft(left);  show.bounds.SetTop(0);
			show.onClick.Add(Show); show.SetCaption("ShowBlocks");
			panel.AddContent(show);		
			
			NEW(writeMBR); left := left + ButtonWidth + ButtonSpacer;
			writeMBR.bounds.SetExtents(ButtonWidth, ButtonHeight); writeMBR.bounds.SetLeft(left); writeMBR.bounds.SetTop(0);
			writeMBR.onClick.Add(WriteMBR); writeMBR.SetCaption("WriteMBR"); 
			panel.AddContent(writeMBR);		
			
			(* 2nd row of buttons *)
			NEW(delete); left := 0;
			delete.bounds.SetExtents(ButtonWidth, ButtonHeight); delete.bounds.SetLeft(left); delete.bounds.SetTop(ButtonHeight + ButtonSpacer);
			delete.onClick.Add(Delete); delete.SetCaption("Delete");
			panel.AddContent(delete);		
			
			NEW(changeType); left := left + ButtonWidth + ButtonSpacer;
			changeType.bounds.SetExtents(ButtonWidth, ButtonHeight); changeType.bounds.SetLeft(left); changeType.bounds.SetTop(ButtonHeight + ButtonSpacer);
			changeType.onClick.Add(ChangeType); changeType.SetCaption("ChangeType");
			panel.AddContent(changeType);		

			NEW(partitionToFile); left := left + ButtonWidth + ButtonSpacer;
			partitionToFile.bounds.SetExtents(ButtonWidth, ButtonHeight); partitionToFile.bounds.SetLeft(left); partitionToFile.bounds.SetTop(ButtonHeight + ButtonSpacer);
			partitionToFile.onClick.Add(PartitionToFile); partitionToFile.SetCaption("ToFile");
			panel.AddContent(partitionToFile);		
			
			NEW(eject); left := left + ButtonWidth + ButtonSpacer;
			eject.bounds.SetExtents(ButtonWidth, ButtonHeight); eject.bounds.SetLeft(left); eject.bounds.SetTop(ButtonHeight + ButtonSpacer);
			eject.onClick.Add(Eject); eject.SetCaption("Eject");
			panel.AddContent(eject);		
			
			NEW(checkPartition); left := left + ButtonWidth + ButtonSpacer;
			checkPartition.bounds.SetExtents(ButtonWidth, ButtonHeight); checkPartition.bounds.SetLeft(left); checkPartition.bounds.SetTop(ButtonHeight + ButtonSpacer);
			checkPartition.onClick.Add(CheckPartition); checkPartition.SetCaption("Check");
			panel.AddContent(checkPartition);		
			
			NEW(bench); left := left + ButtonWidth + ButtonSpacer;
			bench.bounds.SetExtents(ButtonWidth, ButtonHeight); bench.bounds.SetLeft(left); bench.bounds.SetTop(ButtonHeight + ButtonSpacer);
			bench.onClick.Add(BenchPartition); bench.SetCaption("Benchmark");
			panel.AddContent(bench);
		END Init;
		
	END AosPartitionsPlugin; 
	
TYPE

	Bluebottle = OBJECT(WMPartitions.PartitionsPlugin);
	VAR
		config, updateLoader, updateBoot, bootManagerBtn : WMStandardComponents.Button;
		popup : WMPartitions.PopupWindow;
	
		PROCEDURE Config(sender, data : PTR);
		VAR configEditor : ConfigEditor; doClose : BOOLEAN; res : LONGINT;
		BEGIN
			IF IsValid(selection) & 
			    ((AosDisks.Valid IN selection.disk.table[selection.partition].flags) OR (selection.disk.isDiskette)) THEN
				IF selection.disk.device.blockSize = AosPartitionsLib.BS THEN 
					(* special handling for diskette drives *)
					IF selection.disk.isDiskette & (selection.disk.device.openCount < 1) THEN
						doClose := TRUE;
						selection.disk.device.Open(res); (* ignore res *)
					END;
					IF AosPartitionsLib.DetectFS(selection.disk.device, selection.partition) = 3 THEN (* new AosFS *)
						NEW(configEditor, 800, 600, FALSE);
						IF configEditor.SetSelection(selection) THEN
							owner.UpdateStatusLabel(Utilities.NewString("Configuration Editor started")); 
						ELSE
							owner.UpdateStatusLabel(Utilities.NewString("Could not load configuration")); 
						END;
					ELSE owner.UpdateStatusLabel(Utilities.NewString("Partitions does not contain a AosFS volume")); 
					END;
					IF selection.disk.isDiskette & doClose & (selection.disk.device.openCount > 0) THEN
						selection.disk.device.Close(res); (* ignore res *)
					END;
				ELSE owner.UpdateStatusLabel(Utilities.NewString("Error: Blocksize not supported")); 
				END;
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection Invalid")); 
			END;
		END Config;
	
		PROCEDURE UpdateLoader(sender, data : PTR);
		VAR
			updateLoader : AosPartitionsLib.UpdateBootLoader;
			param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) & 
			    ((AosDisks.Valid IN selection.disk.table[selection.partition].flags) OR (selection.disk.isDiskette)) THEN
				NEW(popup, 200, 140, FALSE);
				NEW(param, 1); param[0].description:=  "Bootloader name"; param[0].type := WMPartitions.ParString; 
				param[0].optional := FALSE; param[0].resString := "OBL.Bin"; param[0].default := TRUE;
				popup.SetTextAsString("Enter filename of boot loader");
				popup.SetParameters("Update bootloader on", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					NEW(updateLoader, selection.disk, selection.partition, FALSE);
					updateLoader.SetParameters(param[0].resString);
					updateLoader.SetStart;
				END;
				popup := NIL;
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection Invalid")); 
			END;
		END UpdateLoader;

		PROCEDURE UpdateBoot(sender, data : PTR);
		VAR
			updateBoot : AosPartitionsLib.UpdateBootFile;
			param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) & 
			    ((AosDisks.Valid IN selection.disk.table[selection.partition].flags) OR (selection.disk.isDiskette)) THEN
				NEW(popup, 200, 140, FALSE);
				NEW(param, 1); param[0].description:=  "filename"; param[0].type := WMPartitions.ParString; 
				param[0].optional := FALSE; param[0].resString := "AosIDE.Bin"; param[0].default := TRUE;
				popup.SetTextAsString("Enter filename of boot file");
				popup.SetParameters("Update bootfile on", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					NEW(updateBoot, selection.disk, selection.partition, FALSE);
					updateBoot.SetParameters(param[0].resString);
					updateBoot.SetStart;
				END;
				popup := NIL;
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection Invalid")); 
			END;
		END UpdateBoot;
		
		PROCEDURE InstallBootManager(sender, data : PTR);
		VAR
			installBootManager : AosPartitionsLib.InstallBootManager;
			param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) & ((AosDisks.Valid IN selection.disk.table[selection.partition].flags) OR (selection.disk.isDiskette)) THEN
				NEW(popup, 300, 200, FALSE);
				NEW(param, 2); 
				param[0].description:=  "MBR boot manager filename"; param[0].type := WMPartitions.ParString; 
				param[0].optional := FALSE; param[0].resString := "BootManMBR.Bin"; param[0].default := TRUE;
				param[1].description:=  "MBR boot manager filename"; param[1].type := WMPartitions.ParString; 
				param[1].optional := FALSE; param[1].resString := "BootManRest.Bin"; param[1].default := TRUE;
				popup.SetTextAsString("Enter names of boot manager files");
				popup.SetParameters("Install boot manager  on", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					NEW(installBootManager, selection.disk, selection.partition, FALSE);
					installBootManager.SetParameters(param[0].resString, param[1].resString);
					installBootManager.SetStart;
				END;
				popup := NIL;
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection Invalid")); 
			END;
		END InstallBootManager;
		
		PROCEDURE Finalize*;
		BEGIN
			IF popup # NIL THEN popup.Close; popup := NIL END;
		END Finalize;
	
		PROCEDURE Resized*(width, height : LONGINT);
		BEGIN
			panel.bounds.SetExtents(width, height);
			panel.bounds.SetLeft(0); panel.bounds.SetTop(0);
		END Resized;

		PROCEDURE SelectionUpdated*(selection : WMPartitions.Selection) : LONGINT;
		VAR result : LONGINT;
		BEGIN
			SELF.selection := selection;
			IF IsValid(selection) & (AosDisks.Valid IN selection.disk.table[selection.partition].flags) OR selection.disk.isDiskette THEN
				result := WMPartitions.SelectionMaybe;
			ELSE
				result := WMPartitions.SelectionInvalid;
			END;
			RETURN result;
		END SelectionUpdated;
		
		PROCEDURE &Init;
		VAR  left : LONGINT;
		BEGIN
			SetName("Bluebottle"); desc := "Bluebottle specific operations";

			NEW(panel); panel.bounds.SetLeft(0); panel.bounds.SetTop(0); panel.fillColor.Set(WindowBg);
			
			(* upper row of buttons *)

			NEW(config); left := 0;
			config.bounds.SetExtents(ButtonWidth, ButtonHeight);
			config.bounds.SetLeft(left); config.bounds.SetTop(0);
			config.onClick.Add(Config); config.SetCaption("Config");
			panel.AddContent(config);		

			NEW(updateLoader); left := left + ButtonWidth + ButtonSpacer;
			updateLoader.bounds.SetExtents(2*ButtonWidth, ButtonHeight);
			updateLoader.bounds.SetLeft(left); updateLoader.bounds.SetTop(0);
			updateLoader.onClick.Add(UpdateLoader); updateLoader.SetCaption("UpdateBootLoader");
			panel.AddContent(updateLoader);		

			NEW(updateBoot); left := left +2* ButtonWidth + ButtonSpacer;
			updateBoot.bounds.SetExtents(2*ButtonWidth, ButtonHeight);
			updateBoot.bounds.SetLeft(left); updateBoot.bounds.SetTop(0);
			updateBoot.onClick.Add(UpdateBoot); updateBoot.SetCaption("UpdateBootFile");
			panel.AddContent(updateBoot);		

			NEW(bootManagerBtn); left := left +2* ButtonWidth + ButtonSpacer;
			bootManagerBtn.bounds.SetExtents(2*ButtonWidth, ButtonHeight);
			bootManagerBtn.bounds.SetLeft(left); bootManagerBtn.bounds.SetTop(0);
			bootManagerBtn.onClick.Add(InstallBootManager); bootManagerBtn.SetCaption("Install BootManager");
			panel.AddContent(bootManagerBtn);		
		END Init;
		
	END Bluebottle;
	
TYPE

	FATScavenger = OBJECT(WMPartitions.PartitionsPlugin);
	VAR
		start, doSurfaceScan, doCompareFats, doLostClusters, doWrite : WMStandardComponents.Button;
			
		(* object polls scavenger status *)
		surfaceScan, compareFats, lostClusters, write : BOOLEAN;
		alive, dead : BOOLEAN;
		timer : AosKernel.Timer;
			
		PROCEDURE Resized*(width, height : LONGINT);
		BEGIN
			panel.bounds.SetExtents(width, height);
		END Resized;
	
		PROCEDURE SelectionUpdated*(selection : WMPartitions.Selection) : LONGINT;
		VAR result : LONGINT;
		BEGIN
			SELF.selection := selection;
			IF IsValid(selection) & (AosDisks.Valid IN selection.disk.table[selection.partition].flags) THEN
				IF AosPartitionsLib.IsFatType(selection.disk.table[selection.partition].type) THEN (* FAT Filesystems *)
					result := WMPartitions.SelectionValid;
				ELSE (* only FAT file systems are supported *)
					result := WMPartitions.SelectionInvalid;
				END;
			ELSE
				result := WMPartitions.SelectionInvalid;
			END;
			RETURN result;
		END SelectionUpdated;
	
		PROCEDURE StartScan(sender, data : PTR);
		VAR scavenger : AosFATScavenger.FATScavenger;
		BEGIN 
			IF IsValid(selection) & (AosPartitionsLib.IsFatType(selection.disk.table[selection.partition].type) OR selection.disk.isDiskette) THEN
				NEW(scavenger, selection.disk, selection.partition, FALSE);
				scavenger.SetParameters(surfaceScan, compareFats, lostClusters, write);
				scavenger.SetStart;
				owner.UpdateStatusLabel(Utilities.NewString("Scavenger started"));
			ELSE owner.UpdateStatusLabel(Utilities.NewString("Selection invalid"));
			END; 
		END StartScan;
		
		PROCEDURE CheckboxHandler(sender, data : PTR);
		VAR
			button : WMStandardComponents.Button;
			mark : BOOLEAN;
			ch : ARRAY 2 OF CHAR;
		BEGIN
			button := sender (WMStandardComponents.Button);
			IF button = doSurfaceScan THEN
				surfaceScan := ~surfaceScan; mark := surfaceScan;
			ELSIF button = doCompareFats THEN
				compareFats := ~compareFats; mark := compareFats;
			ELSIF button = doLostClusters THEN
				lostClusters := ~lostClusters; mark := lostClusters;
			ELSIF button = doWrite THEN 
				write := ~write; mark := write;
			END;
			IF mark THEN ch := "X" ELSE ch := "" END;
			button.caption.Set(Utilities.NewString(ch));
		END CheckboxHandler;
		
		PROCEDURE &Init;
		VAR 
			label : WMStandardComponents.Label;
			left : LONGINT;
		BEGIN
			SetName("Scavenger"); desc := "Scavenger for FAT file systems";
			NEW(timer); alive := TRUE; dead := FALSE;
			surfaceScan := FALSE; compareFats := TRUE; lostClusters := TRUE; write := FALSE;
		
			NEW(panel);
			panel.bounds.SetLeft(0); panel.bounds.SetTop(0);
			panel.fillColor.Set(WindowBg);
			
			NEW(start);
			start.bounds.SetExtents(ButtonWidth, ButtonHeight);
			start.bounds.SetLeft(0); start.bounds.SetTop(0);
			start.onClick.Add(StartScan); start.SetCaption("Start");
			panel.AddContent(start);
			
			NEW(doSurfaceScan); left := ButtonWidth + ButtonSpacer;
			doSurfaceScan.bounds.SetExtents(ButtonHeight, ButtonHeight);
			doSurfaceScan.bounds.SetLeft(left); doSurfaceScan.bounds.SetTop(0);
			doSurfaceScan.onClick.Add(CheckboxHandler); doSurfaceScan.SetCaption("");
			panel.AddContent(doSurfaceScan);
			
			NEW(label); left := left + ButtonHeight + ButtonSpacer;
			label.bounds.SetExtents(70, ButtonHeight); label.bounds.SetLeft(left); label.bounds.SetTop(0);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("Surface Scan"));
			panel.AddContent(label);
			
			NEW(doCompareFats); left := left + 70 + ButtonSpacer;
			doCompareFats.bounds.SetExtents(ButtonHeight, ButtonHeight);
			doCompareFats.bounds.SetLeft(left); doCompareFats.bounds.SetTop(0);
			doCompareFats.onClick.Add(CheckboxHandler); doCompareFats.SetCaption("X");
			panel.AddContent(doCompareFats);
			
			NEW(label); left := left + ButtonHeight + ButtonSpacer;
			label.bounds.SetExtents(80, ButtonHeight); label.bounds.SetLeft(left); label.bounds.SetTop(0);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("Compare FATs"));
			panel.AddContent(label);

			NEW(doLostClusters); left := left + 80 + ButtonSpacer;
			doLostClusters.bounds.SetExtents(ButtonHeight, ButtonHeight);
			doLostClusters.bounds.SetLeft(left); doLostClusters.bounds.SetTop(0);
			doLostClusters.onClick.Add(CheckboxHandler); doLostClusters.SetCaption("X");
			panel.AddContent(doLostClusters);
			
			NEW(label); left := left + ButtonHeight + ButtonSpacer;
			label.bounds.SetExtents(100, ButtonHeight); label.bounds.SetLeft(left); label.bounds.SetTop(0);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("Scan cluster chains"));
			panel.AddContent(label);
			
			NEW(doWrite); left := left + 100 + ButtonSpacer;
			doWrite.bounds.SetExtents(ButtonHeight, ButtonHeight);
			doWrite.bounds.SetLeft(left); doWrite.bounds.SetTop(0);
			doWrite.onClick.Add(CheckboxHandler); doWrite.SetCaption("");
			panel.AddContent(doWrite);
			
			NEW(label); left := left + ButtonHeight + ButtonSpacer;
			label.bounds.SetExtents(100, ButtonHeight); label.bounds.SetLeft(left); label.bounds.SetTop(0);
			label.fillColor.Set(WindowBg); label.caption.Set(Utilities.NewString("Correct Errors"));
			panel.AddContent(label);
		END Init;
		
		PROCEDURE Finalize;
		BEGIN
			(* do nothing *)
		END Finalize;
		
	END FATScavenger;

TYPE

	(* Graphical front-end for AosDiskTests.Mod operations *)
	TestsPlugin = OBJECT (WMPartitions.PartitionsPlugin);
	VAR
		writeDataBtn, testPartitionBtn, verifyDataBtn, writeZerosBtn  : WMStandardComponents.Button;
		
		PROCEDURE Resized*(width, height : LONGINT);
		BEGIN
			panel.bounds.SetExtents(width, height);
		END Resized;
		
		PROCEDURE SelectionUpdated*(selection : WMPartitions.Selection) : LONGINT;
		VAR result : LONGINT;
		BEGIN
			SELF.selection := selection;
			IF IsValid(selection) THEN result := WMPartitions.SelectionValid;
			ELSE result := WMPartitions.SelectionInvalid;
			END;
			RETURN result;
		END SelectionUpdated;
		
		PROCEDURE WriteTestData(sender, data : PTR);
		VAR
			testDataWriter : AosDiskTests.TestDataWriter;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) THEN 
				NEW(param, 1);
				param[0].description := "SectorsPerTransfer"; param[0].type := WMPartitions.ParInteger; param[0].width := 0;
				param[0].optional := FALSE; param[0].default := TRUE; param[0].resInteger := 1;
				NEW(popup, 220, 160, FALSE); 
				popup.SetTextAsString("Writing test data to a partition will DESTROY ITS CONTENTS!!");
				popup.SetParameters("Write test data to", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					ASSERT(param[0].valid);
					NEW(testDataWriter, selection.disk, selection.partition, FALSE);
					testDataWriter.SetParameters(param[0].resInteger);
					testDataWriter.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection Invalid")); 
			END;
		END WriteTestData;
		
		PROCEDURE WriteZeros(sender, data : PTR);
		VAR
			zeroWriter : AosDiskTests.ZeroWriter;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) THEN 
				NEW(param, 1);
				param[0].description := "SectorsPerTransfer"; param[0].type := WMPartitions.ParInteger; param[0].width := 0;
				param[0].optional := FALSE; param[0].default := TRUE; param[0].resInteger := 1;
				NEW(popup, 220, 160, FALSE); 
				popup.SetTextAsString("Writing zeros to the partition will DESTROY ITS CONTENTS!!");
				popup.SetParameters("Write zeros to ", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					ASSERT(param[0].valid);
					NEW(zeroWriter, selection.disk, selection.partition, FALSE);
					zeroWriter.SetParameters(param[0].resInteger);
					zeroWriter.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection Invalid")); 
			END;
		END WriteZeros;
			
		PROCEDURE TestPartition(sender, data : PTR);
		VAR 
			diskTest : AosDiskTests.DiskTest;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) THEN
				NEW(param, 4);
				param[0].description := "Number of Tests"; param[0].type := WMPartitions.ParInteger; param[0].width := 0;
				param[0].optional := FALSE; param[0].default := TRUE; param[0].resInteger := -1;
				param[1].description := "Max. Sectors per Transfer"; param[1].type := WMPartitions.ParInteger; param[1].width := 0;
				param[1].optional := FALSE; param[1].default := TRUE; param[1].resInteger := 200;				
				param[2].description := "Max. Offset into Client Buffer"; param[2].type := WMPartitions.ParInteger; param[2].width := 0;
				param[2].optional := FALSE; param[2].default := TRUE; param[2].resInteger := 0;				
				param[3].description := "Verify Test Data"; param[3].type := WMPartitions.ParBoolean; param[3].width := 0;
				param[3].optional := FALSE; param[3].default := TRUE; param[3].resBoolean := FALSE;				
				NEW(popup, 220, 260, FALSE); 
				popup.SetTextAsString("To run the test endlessly, specified a negative number of tests. ");
				popup.SetParameters("Run DiskTest on partition ", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					NEW(diskTest, selection.disk, selection.partition, FALSE);
					diskTest.SetParameters(TRUE, FALSE, param[3].resBoolean, param[0].resInteger, param[1].resInteger, param[2].resInteger);
					diskTest.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection Invalid")); 
			END;
		END TestPartition;

		PROCEDURE VerifyTestData(sender, data : PTR);
		VAR
			testDataChecker : AosDiskTests.TestDataChecker;
			popup : WMPartitions.PopupWindow; param : WMPartitions.Parameters;
			res : LONGINT;
		BEGIN
			IF IsValid(selection) THEN 
				NEW(param, 1);
				param[0].description := "SectorsPerTransfer"; param[0].type := WMPartitions.ParInteger; param[0].width := 0;
				param[0].optional := FALSE; param[0].default := TRUE; param[0].resInteger := 1;
				NEW(popup, 220, 160, FALSE); 
				popup.SetTextAsString("Verify test data");
				popup.SetParameters("Verify test data on", selection, param);
				popup.Popup(100, 100, res);
				IF res = WMPartitions.ResOk THEN
					ASSERT(param[0].valid);
					NEW(testDataChecker, selection.disk, selection.partition, FALSE);
					testDataChecker.SetParameters(param[0].resInteger);
					testDataChecker.SetStart;
				END;
			ELSE
				owner.UpdateStatusLabel(Utilities.NewString("Selection invalid")); 
			END;
		END VerifyTestData;

		PROCEDURE Finalize*;
		BEGIN
			(* do nothing *)
		END Finalize;
		
		PROCEDURE &Init;
		VAR left : LONGINT;
		BEGIN
			SetName("Tests"); desc := "Partition Test Tool";
		
			NEW(panel); panel.bounds.SetLeft(0); panel.bounds.SetTop(0);	panel.fillColor.Set(WMPartitions.WindowBg);
			
			(* upper row of buttons *)
			NEW(writeDataBtn); left := 0;
			writeDataBtn.bounds.SetExtents(ButtonWidth + 20, ButtonHeight); writeDataBtn.bounds.SetLeft(left); writeDataBtn.bounds.SetTop(0);
			writeDataBtn.onClick.Add(WriteTestData); writeDataBtn.SetCaption("Write Test Data");
			panel.AddContent(writeDataBtn);		
		
			NEW(testPartitionBtn); left := left + ButtonWidth + 20 + ButtonSpacer; 
			testPartitionBtn.bounds.SetExtents(ButtonWidth + 20, ButtonHeight); testPartitionBtn.bounds.SetLeft(left);  testPartitionBtn.bounds.SetTop(0);
			testPartitionBtn.onClick.Add(TestPartition); testPartitionBtn.SetCaption("Test Partition");
			panel.AddContent(testPartitionBtn);		
			
			(* 2nd row of buttons *)
			NEW(verifyDataBtn); left := 0;
			verifyDataBtn.bounds.SetExtents(ButtonWidth + 20, ButtonHeight); verifyDataBtn.bounds.SetLeft(left);  verifyDataBtn.bounds.SetTop(ButtonHeight + ButtonSpacer);
			verifyDataBtn.onClick.Add(VerifyTestData); verifyDataBtn.SetCaption("Verify Test Data");
			panel.AddContent(verifyDataBtn);					

			NEW(writeZerosBtn); left := left + ButtonWidth + 20 + ButtonSpacer; 
			writeZerosBtn.bounds.SetExtents(ButtonWidth + 20, ButtonHeight); writeZerosBtn.bounds.SetLeft(left);  writeZerosBtn.bounds.SetTop(ButtonHeight + ButtonSpacer);
			writeZerosBtn.onClick.Add(WriteZeros); writeZerosBtn.SetCaption("Write Zeros");
			panel.AddContent(writeZerosBtn);		

		END Init;
		
	END TestsPlugin; 
	
VAR
	fsTools : FSTools; 
	aosPartitions : AosPartitionsPlugin; 
	fatScavenger : FATScavenger;
	bluebottle : Bluebottle;
	tests : TestsPlugin;

PROCEDURE InstallPlugins;
VAR ignore : LONGINT; 
BEGIN
	(* install default plugins *)
	NEW(fsTools); WMPartitions.plugins.Add(fsTools, ignore);
	NEW(aosPartitions); WMPartitions.plugins.Add(aosPartitions, ignore);
	NEW(fatScavenger);	WMPartitions.plugins.Add(fatScavenger, ignore);
	NEW(bluebottle); WMPartitions.plugins.Add(bluebottle, ignore);
	NEW(tests); WMPartitions.plugins.Add(tests, ignore);
END InstallPlugins;

PROCEDURE Install*(ptr : PTR) : PTR;
BEGIN
	RETURN NIL;
END Install;

PROCEDURE Cleanup;
BEGIN
	WMPartitions.plugins.Remove(fsTools);
	WMPartitions.plugins.Remove(aosPartitions);
	WMPartitions.plugins.Remove(fatScavenger);
	fatScavenger.Finalize;
	WMPartitions.plugins.Remove(bluebottle);
	WMPartitions.plugins.Remove(tests);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	InstallPlugins; 
END WMPartitionsPlugins.

WMPartitionsPlugins.Install ~  S.Free WMPartitionsPlugins ~ 
