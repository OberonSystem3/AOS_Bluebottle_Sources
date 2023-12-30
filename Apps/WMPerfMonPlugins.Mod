MODULE WMPerfMonPlugins; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor plugin framework"; *)
(**
 * The idea behind the Peformance Monitor plugin framework is to facilitate simple performance monitoring / measurement tasks by
 * providing some commonly used services as:
 *	- Sampling (incl. averaging, simple statistics, configurable sampling intervals and sample buffers)
 *	- Visualization of the sampled values / statistics 
 *	- Managing self-describing Performance Monitor plugins  and providing access to them
 *
 * This module provides:
 *	- Plugin interface implemented by actual Performance Monitor plugins
 *	- Helper objects that provide access to sampled value to multiple plugins
 *	- Updater object that performs the actual sampling in a single loop for all active Plugins
 *
 * Usage:	WMPerfMonPlugins.Show ~ displays a list of all registered plugins	S.Free WMPerfMonPlugins ~
 *
 * Possible improvements:
 *	-	Use low-level timer (AosBoot.GetTimer) everywhere since AosActive.ticks is inaccurate/not reliable
 *
 * History:
 *
 *	16.02.2006	First Release (staubesv)
 *	23.06.2006 	Adapted to WMDiagramComponents, support for multidimensional data visualization (staubesv)
 *	19.07.2006	Added EstimateCpuClockrate procedure, load MessagesPlugin per default, plugins can optionally bypass supersampling (staubesv)
 *	24.07.2006 	Added CyclesToMs, MsToString procedures (staubesv)
 *	28.07.2006	Moved GUI-related code to WMPerfMonComponents (staubesv)
 *	16.01.2006	Updater.SetIntervals also clears screenTimer to force appliation of new value, no upper bounds for sample interval, 
 *				only consider valid samples when averaging (staubesv)
 *	26.02.2007	Added Updater.RemoveByModuleName, generate colors for datasets with more than 3 datas, configuration in config file  (staubesv)
 *)
 
IMPORT
	SYSTEM, 
	AosOut, AosBoot, AosMemory, AosActive, AosKernel, AosModules, AosHeap, AosPlugins, 
	AosConfig, Utilities, WMDiagramComponents, WMGraphics, AosEvents,
	XML, XMLObjects;

CONST 

	EventPluginsChanged* = 0;		(** Plugins have been added, removed, activated or deactivated *)
	EventPerfUpdate* = 1;			(** Updater performance has been updated *)
	EventParametersChanged* = 2;	(** Sampling parameters have changed *)
	EventSampleLoopDone* = 3;		(** All plugin values have been updated *)

	(* How many samples should be used for averaging? *)
	DefaultSampleBufferSize = 10; 	(* samples *)
	DefaultSampleInterval = 50; 		(* ms *)
	DefaultScreenRefresh = 500; 	(* ms *)
	
	(* Display registering/unregistering of plugins *)
	Verbose = FALSE;
	
	(* Event system classifications *)
	EventClass = 4;

TYPE 

	Name* = ARRAY 32 OF CHAR;
	Description* = ARRAY 128 OF CHAR;
	DeviceName* = ARRAY 128 OF CHAR;
	Dataset* = WMDiagramComponents.Dataset;
	DatasetDescriptor* = WMDiagramComponents.DatasetDescriptor;

TYPE

	(** Plugin parameters.  																			*)
	(** A parameter object must be passed as argument for the plugin object's constructor. The fields	*)
	(** may be set later in the Init procedure but shall not be modified after the Init procedure.		*)
	
	Parameter* = POINTER TO RECORD;
	
		(** Name and description of the plugin														*)
		name* : Name; description* : Description;
		
		(** Name of the monitored device if applicable. Default = "" (not applicable)					*)
		devicename* : DeviceName;
	
		(** Module where counter is implemented													*)
		modulename* : ARRAY 128 OF CHAR;
		
		(**	Describes names and colors of sampled values											*)
		datasetDescriptor* : WMDiagramComponents.DatasetDescriptor;
		
		(** If TRUE, the plugin will only be sampled when a screen update occurs. If FALSE, the plugin	*)
		(* will be sampled at the sample rate specified by the Updater object. The average of all 		*)
		(* samples in the sample buffer will then be displayed											*)
		(* Default: FALSE																			*)
		noSuperSampling* : BOOLEAN;
		
		(** Minimum and maximum value the UpdateCounter procedure will return					*)
		(** Defaults: min = 0; max = 0 (no max)														*)
		min*, max* : LONGINT;					
		
		(** Should the diagram panel automatically detect a min/max value? 						*)
		(** Defaults: autoMin = FALSE; autoMax = FALSE												*)
		autoMin*, autoMax* : BOOLEAN;	
		
		(** Unit of the counter ("/s" will be appended automatically if the field 'perSecond' is TRUE) 	*)
		(** Default: "" (None)																		*)
		unit* : ARRAY 16 OF CHAR;
		
		(** Shall the counter be interpreted as change per second? Default: FALSE					*)
		perSecond* : BOOLEAN;
		
		(** Statistic gathering related parameters *)
		
		(** The stats value will be computed as UpdateCounter() * scale								*)
		(** Default: 0.0 (is interpreted as 1.0 -> don't scale) 											*)
		scale* : REAL;
		
		(** Minimum number of digits, number of fraction digits										*)
		(** Defaults: minDigits = 0; fraction = 0;														*)
		minDigits*, fraction* : LONGINT;
		
		(** Unit of the statistics values ("/s" will be appended automatically if 'perSecond' is TRUE)	*)
		(** Default: "" (None)																		*)
		statsUnit* : ARRAY 16 OF CHAR;
		
		(** If TRUE and 'max' # 0, the statistics values will also be shown as percent of 'max'			*)
		(** Default: FALSE																			*)
		showPercent* : BOOLEAN;
		
		(** If TRUE and ~perSecond, the sum of all values will be displayed. Default: FALSE				*)
		showSum* : BOOLEAN;
		
		(** Shall the counter be hidden/excluded  from updater.GetPlugins & SelectionWindow? 		*)
		(** Default: FALSE																			*)
		hide* : BOOLEAN;
		
		(** Optional list of helper objects															*)
		helper* : Helper;
		
	END;
		
TYPE

	Plugin* = OBJECT
	VAR	
		(** Plugins update this data set in the UpdateDataset procedure *)
		dataset- : Dataset;

		(** Parameters mustn't be changed after a plugin instance is created  *)
		p- : Parameter;
		
		datamodel- : WMDiagramComponents.MultiPointModel;

		active : BOOLEAN; (* Update counter / display? *)
		ownedByGraph*, ownedByGrid* : BOOLEAN; (* Owned (displayed) by a window? *)

		nbrOfClients : LONGINT;

		currentDataset : Dataset; (* Most recent  averaged values *)
		sample, nbrOfSamples, nbrOfValidSamples : LONGINT;
		samples : POINTER TO ARRAY OF Dataset;
		
		timeStamp, lastTimeStamp : LONGINT;
		lastDataset, temp : Dataset; 
		
		dimensions : LONGINT;
		
		link : Plugin;
		
		(** Plugin interface to be implemented *)
		
		(** Update Plugin.dataset value(s) *)
		PROCEDURE UpdateDataset*; 
		BEGIN
			HALT(301); (* abstract *)
		END UpdateDataset;
		
		(* Called by constructor after panel has been created for plugin specific initialization *)
		PROCEDURE Init*(p : Parameter);
		BEGIN
			HALT(301); (* abstract *)
		END Init;
		
		PROCEDURE IncNbrOfClients*;
		BEGIN {EXCLUSIVE}
			IF (nbrOfClients = 0) THEN
				IF ~IsActive() THEN 
					SetActive(TRUE); 
				END;
			END;
			INC(nbrOfClients);
		END IncNbrOfClients;
		
		PROCEDURE DecNbrOfClients*;
		BEGIN {EXCLUSIVE}
			DEC(nbrOfClients);
			IF nbrOfClients < 0 THEN	
				AosOut.String("WMPerfMonPlugins: Warning: NbrOfClients < 0"); AosOut.Ln;
				nbrOfClients := 0;
			END;
			IF (nbrOfClients = 0) THEN
				IF IsActive() THEN 
					SetActive(FALSE); 
				END;
			END;
		END DecNbrOfClients;
		
		(** Active sampling for this plugin *)
		PROCEDURE SetActive*(active : BOOLEAN);
		BEGIN
			IF active THEN
				UpdateDataset;
				CopyDataset(dataset, lastDataset);
				SELF.active := TRUE;
			ELSE
				SELF.active := FALSE;
			END;
			updater.NotifyListeners({EventPluginsChanged}, 0);
		END SetActive;
		
		(** Is sampling activated for this plugin? *)
		PROCEDURE IsActive*() : BOOLEAN;
		BEGIN
			RETURN active;
		END IsActive;
		
		(** Reset data model *)
		PROCEDURE Reset*;
		BEGIN
			datamodel.Acquire; datamodel.Reset; datamodel.Release;
		END Reset;
				
		PROCEDURE SetSampleBufferSize*(size : LONGINT);
		VAR i : LONGINT;
		BEGIN (* no concurrency allowed, Plugin.Update may not called at the same time *)
			IF p.noSuperSampling THEN size := 1; END;
			sample := 0; nbrOfValidSamples := 0;
			nbrOfSamples := size;
			NEW(samples, nbrOfSamples);
			FOR i := 0 TO nbrOfSamples-1 DO NEW(samples[i], dimensions); END;
		END SetSampleBufferSize;
		
		PROCEDURE Finalize*;
		BEGIN
			updater.RemovePlugin(SELF);
		END Finalize;
		
		PROCEDURE Update;
		VAR i, dim, dTime : LONGINT; sum: REAL;
		BEGIN
			timeStamp := AosKernel.GetTimer();
			
			UpdateDataset;
			
			IF lastTimeStamp # 0 THEN
				dTime := timeStamp - lastTimeStamp;				
				IF p.perSecond & (dTime # 0) THEN
					FOR dim := 0 TO dimensions-1 DO				
						temp[dim] := (dataset[dim] - lastDataset[dim]) * (AosActive.Second / dTime);					
						lastDataset[dim] := dataset[dim]; dataset[dim] := temp[dim];
					END;
				END;
				
				IF nbrOfValidSamples < nbrOfSamples THEN INC(nbrOfValidSamples); END;

				FOR dim := 0 TO dimensions-1 DO
					samples[sample][dim] := dataset[dim]; 
					sum := 0;
					FOR i := 0 TO nbrOfValidSamples-1 DO sum := sum + samples[i][dim]; END;
					currentDataset[dim] := sum / nbrOfValidSamples;				
				END;				
				sample := (sample + 1) MOD nbrOfSamples;
			END;
			lastTimeStamp := timeStamp;
		END Update;		
		
		PROCEDURE UpdateScreen;
		BEGIN
			datamodel.Acquire; datamodel.PutValues(currentDataset); datamodel.Release; 	
		END UpdateScreen;
		
		PROCEDURE CopyDataset(source : Dataset; VAR target : Dataset);
		VAR dim : LONGINT;
		BEGIN
			FOR dim := 0 TO dimensions-1 DO target[dim] := source[dim]; END;
		END CopyDataset;
	
		PROCEDURE Show;
		BEGIN
			AosOut.String(p.name); AosOut.String(" ("); AosOut.String(p.description); AosOut.String(")");
			IF p.devicename # "" THEN AosOut.String(" on "); AosOut.String(p.devicename); END;	
			IF p.modulename # "" THEN AosOut.String(" defined in "); AosOut.String(p.modulename); END; AosOut.Char(" "); 
			IF active THEN AosOut.String("[active]"); END;
			IF ownedByGraph THEN AosOut.String("[graph]"); END;
			IF ownedByGrid THEN AosOut.String("[grid]"); END;
			IF p.hide THEN AosOut.String("[hidden]"); END;
		END Show;
		
		PROCEDURE EvaluateParameter(p : Parameter);
		CONST Decrement = 35;
		VAR r, g, b, a, i, round : LONGINT;
		BEGIN
			IF (p.scale = 0) & (p.statsUnit = "")  THEN COPY(p.unit, p.statsUnit); END;
			IF p.scale = 0 THEN p.scale := 1.0; END;
			IF p.datasetDescriptor = NIL THEN
				NEW(p.datasetDescriptor, 1);
				p.datasetDescriptor[0].name := "Default";
				p.datasetDescriptor[0].color := WMGraphics.Red;
				dimensions := 1;
			ELSE
				IF (LEN(p.datasetDescriptor) > 0) & (p.datasetDescriptor[0].color = 0) THEN p.datasetDescriptor[0].color := WMGraphics.Yellow; END;
				IF (LEN(p.datasetDescriptor) > 1) & (p.datasetDescriptor[1].color = 0) THEN p.datasetDescriptor[1].color := WMGraphics.Green; END;
				IF (LEN(p.datasetDescriptor) > 2) & (p.datasetDescriptor[2].color = 0) THEN p.datasetDescriptor[2].color := WMGraphics.Red; END;
				IF (LEN(p.datasetDescriptor) > 3) THEN
					round := 0;
					r := 255; g := 255; b := 255; a := 200;
					FOR i := 3 TO LEN(p.datasetDescriptor)-1 DO						
						IF round = 0 THEN
							p.datasetDescriptor[i].color := WMGraphics.RGBAToColor(r, g, b, a);
						ELSIF round = 1 THEN
							p.datasetDescriptor[i].color := WMGraphics.RGBAToColor(g, r, b, a);
						ELSE
							p.datasetDescriptor[i].color := WMGraphics.RGBAToColor(b, g, r, a);
						END;
						IF (r - Decrement > 0) THEN DEC(r, Decrement);
						ELSIF (g - 2*Decrement > 0) THEN DEC(g, Decrement);
						ELSIF (b - 3*Decrement > 0) THEN DEC(b, Decrement);
						ELSE
							INC(round);
							r := 255; g := 255; b := 255;
						END;
					END;
				END;
				dimensions := LEN(p.datasetDescriptor);
			END;
			NEW(datamodel, 1024, dimensions);
			datamodel.SetDatasetDescriptor(p.datasetDescriptor);
		END EvaluateParameter;
						
		PROCEDURE &New(p : Parameter);
		BEGIN
			ASSERT(p # NIL); SELF.p := p; active := FALSE;
			Init(p); 
			EvaluateParameter(p);
			NEW(temp, dimensions);
			NEW(dataset, dimensions); NEW(lastDataset, dimensions); NEW(currentDataset, dimensions);
			updater.AddPlugin(SELF);
		END New;
		
	END Plugin;
	
TYPE
	
	(** 
	 * Plugins may optionally use helper objects. Idea: If the sampling of a value is expensive in terms of 
	 * required computational power/memory, and this value is used by multiple plugins, the plugins may share
	 * a single implementation/instance of the updater for this value.
	 * The value will be only sampled once in an entire update loop.
	 *)
	Helper* = OBJECT
	VAR
		next : Helper;
		updated : BOOLEAN;
	
		PROCEDURE Update*;
		BEGIN
			HALT(301); (* abstract *)
		END Update;
		
	END Helper;
			
TYPE
	
	(* Notifies listener about current CPU time usage of updater thread and changes of the plugin list *)
	Notifier = PROCEDURE {DELEGATE} (events : SET; perf : REAL);

	Notifiers = POINTER TO RECORD
		events : SET;
		proc : Notifier;
		owner : ANY;
		next : Notifiers;
	END;

	PluginArray* = POINTER TO ARRAY OF Plugin;

	(* This object...
	 * 	- maintains a list of all plugin instances 
	 *	- updates all plugins periodically (value/screen at separate update intervals) & manages size of sampling buffers
	 *	- is a singleton 
	 *)
	 Updater = OBJECT
	 VAR	 	
	 	sampleInterval- : LONGINT; (* ms *)
	 	sampleBufferSize- : LONGINT; (* samples *)
	 	screenInterval- : LONGINT; (* ms *)
	 	
	 	plugins : Plugin;
	 	notifiers : Notifiers;

	 	(* Fields related to CPU time consumption calculation of the Updater obj *)
	 	lastCycles, lastTimestamp : HUGEINT;
	 	sample : LONGINT; sampleBuffer : POINTER TO ARRAY OF REAL;
	 	me : AosActive.Process; (* Process associated to this active object *)
	 	
		timestamp, timediff, left : LONGINT;
		screenTimer : AosKernel.MilliTimer;
		alive, dead : BOOLEAN;
		timer : AosKernel.Timer;
		
		PROCEDURE AddListener*(events : SET; owner : ANY; proc : Notifier);
		VAR nr : Notifiers;
		BEGIN {EXCLUSIVE}
			ASSERT((owner # NIL) & (proc # NIL));
			NEW(nr); nr.owner := owner; nr.proc := proc; nr.events := events;
			nr.next := notifiers.next; notifiers.next := nr;
		END AddListener;
		
		PROCEDURE RemoveListener*(owner : ANY; proc : Notifier);
		VAR n : Notifiers;
		BEGIN {EXCLUSIVE}
			n := notifiers; 
			WHILE n.next # NIL DO 
				IF (n.next.owner = owner) & (n.next.proc = proc) THEN 
					n.next := n.next.next; 
				ELSE
					n := n.next;
				END;
			END;
		END RemoveListener;
		
		PROCEDURE NotifyListeners*(events : SET; perf : REAL);
		VAR n : Notifiers;
		BEGIN
			n := notifiers.next;
			WHILE n # NIL DO 
				IF n.events * events # {} THEN
					n.proc(events, perf); 
				END;
				n := n.next; 
			END;
		END NotifyListeners;
		
		PROCEDURE GetByFullname*(fullname : ARRAY OF CHAR; VAR index : LONGINT; VAR msg : ARRAY OF CHAR) : Plugin;
		VAR plugin : Plugin; sa : Utilities.StringArray; name : Name; i : LONGINT;
		BEGIN {EXCLUSIVE}
			msg := "";
			sa := Utilities.Split(fullname, ".");
			IF LEN(sa) = 2 THEN
				COPY(sa[0]^, name);
				plugin := GetByNameX(name, "");
				IF plugin # NIL THEN
					i := 0; WHILE (i < LEN(plugin.p.datasetDescriptor)) & (plugin.p.datasetDescriptor[i].name # sa[1]^)  DO INC(i); END;
					IF (i < LEN(plugin.p.datasetDescriptor)) THEN
						index := i;
					ELSE
						plugin := NIL;
						msg := "Data not found";
					END;
				ELSE
					msg := "Plugin not found";
				END;
			ELSE
				msg := "Incorrect fullname";
			END;
			RETURN plugin;
		END GetByFullname;
		
		PROCEDURE GetByName*(name : Name; devicename : DeviceName) : Plugin;
		BEGIN {EXCLUSIVE}
			RETURN GetByNameX(name, devicename);
		END GetByName;
						
		PROCEDURE GetByNameX(name : Name; devicename : DeviceName) : Plugin;
		VAR p : Plugin;
		BEGIN
			p := plugins;	
			WHILE p # NIL DO
				IF (p.p.name = name) & (p.p.devicename = devicename) THEN 
					RETURN p;
				END;
				p := p.link;
			END;
			RETURN NIL;
		END GetByNameX;
		
		PROCEDURE RemoveByName*(name : Name; devicename : DeviceName);
		VAR p : Plugin;
		BEGIN {EXCLUSIVE}
			p := plugins; WHILE (p # NIL) & ~((p.p.name = name) & (p.p.devicename = devicename)) DO p := p.link; END;
			IF p # NIL THEN RemovePluginIntern(p);
			ELSE AosOut.String("WMCounters: Could not remove plugin "); AosOut.String(name); AosOut.Ln; 
			END;
		END RemoveByName;
		
		(** Removes all plugins whose modulename parameter matches the specified modulename *)
		PROCEDURE RemoveByModuleName*(modulename : ARRAY OF CHAR);
		VAR p : Plugin; removed : BOOLEAN;
		BEGIN {EXCLUSIVE}
			LOOP
				removed := FALSE;
				p := plugins; WHILE (p # NIL) & ~(p.p.modulename = modulename) DO p := p.link; END;
				IF p # NIL THEN 
					removed := TRUE;
					RemovePluginIntern(p);
				END;
				IF removed = FALSE THEN EXIT; END;
			END;
		END RemoveByModuleName;
		
		(** Removes all plugins whose hide field is set to true *)
		PROCEDURE RemoveAllHidden*;
		VAR p : Plugin; removed : BOOLEAN;
		BEGIN {EXCLUSIVE}
			LOOP
				removed := FALSE;
				p := plugins; WHILE (p # NIL) & ~(p.p.hide) DO p := p.link; END;
				IF p # NIL THEN
					removed := TRUE;
					RemovePluginIntern(p);
				END;
				IF removed = FALSE THEN EXIT; END;
			END;
		END RemoveAllHidden;
		
		PROCEDURE RemovePlugin(p : Plugin);
		BEGIN {EXCLUSIVE}
			RemovePluginIntern(p);
		END RemovePlugin;
		
		PROCEDURE RemovePluginIntern(p : Plugin);
		VAR temp : Plugin; removed : BOOLEAN;
		BEGIN
			IF Verbose THEN AosOut.String("WMPerfMon: Removing counter "); p.Show;AosOut.Ln; END;
			IF plugins = p THEN 
				plugins := plugins.link; removed := TRUE;
			ELSE
				temp := plugins; WHILE(temp # NIL) & (temp.link # p) DO temp := temp.link; END;
				IF temp # NIL THEN 
					temp.link := temp.link.link; 
					removed := TRUE;
				END;
			END;
			IF removed THEN
				NotifyListeners({EventPluginsChanged}, 0);
				DEC(NnofPlugins);
				IF p.p.datasetDescriptor # NIL THEN
					DEC(NnofValues, LEN(p.p.datasetDescriptor));
				ELSE
					DEC(NnofValues);
				END;
			END;
		END RemovePluginIntern;
		
		(** Will not return hidden plugins *)
		PROCEDURE GetPlugins*() : PluginArray;
		VAR p : Plugin; nbrOfPlugins, i : LONGINT; ca : PluginArray;
		BEGIN {EXCLUSIVE}
			IF plugins # NIL THEN
				(* determine size of array *)
				p := plugins; nbrOfPlugins := 0;
				WHILE p # NIL DO 
					IF ~p.p.hide THEN INC(nbrOfPlugins); END;
					p := p.link; 
				END;
				(* fill array *)
				NEW(ca, nbrOfPlugins);
				p := plugins; i := 0;
				WHILE p # NIL DO 
					IF ~p.p.hide THEN ca[i] := p; INC(i); END;
					p := p.link; 
				END;	
			END;
			RETURN ca;
		END GetPlugins;
		
		(** Clear statistics of all plugins *)
		PROCEDURE ClearAll*;
		VAR p : Plugin;
		BEGIN {EXCLUSIVE}
			p := plugins; WHILE p # NIL DO p.Reset; p := p.link; END;
		END ClearAll;
				
		PROCEDURE Show;
		VAR p : Plugin;
		BEGIN {EXCLUSIVE}
			AosOut.String("WMPerfMon: ");
			IF plugins = NIL THEN
				AosOut.String("No counters installed."); AosOut.Ln;
			ELSE
				AosOut.Ln;
				p := plugins; WHILE p # NIL DO p.Show; AosOut.Ln; p := p.link; END;
			END;
		END Show;
		
		PROCEDURE SetIntervals*(VAR sampleInterval, sampleBufferSize, screenInterval : LONGINT);
		VAR p : Plugin;
		BEGIN {EXCLUSIVE}
			IF sampleInterval < 1 THEN sampleInterval := 1; END;
			IF screenInterval < sampleInterval THEN screenInterval := sampleInterval; END;		
			
			IF sampleBufferSize < screenInterval DIV sampleInterval THEN
				sampleBufferSize := screenInterval DIV sampleInterval;
			END;						
			ASSERT(sampleBufferSize > 0);

			SELF.sampleInterval := sampleInterval;
			SELF.screenInterval := screenInterval;
			IF sampleBufferSize # SELF.sampleBufferSize THEN
				SELF.sampleBufferSize := sampleBufferSize;
				p := plugins; WHILE p # NIL DO p.SetSampleBufferSize(sampleBufferSize); p := p.link; END;	
				NEW(sampleBuffer, sampleBufferSize);
			END;
			NotifyListeners({EventParametersChanged}, 0);
			AosKernel.SetTimer(screenTimer, 1);
			timer.Wakeup;
		END SetIntervals;
		
		PROCEDURE AddPlugin(p : Plugin);
		BEGIN {EXCLUSIVE}
			IF Verbose THEN AosOut.String("WMPerfMon: Adding counter "); p.Show; AosOut.Ln; END;
			p.link := plugins; plugins := p; p.SetSampleBufferSize(sampleBufferSize);
			INC(NnofPlugins);
			IF p.p.datasetDescriptor # NIL THEN
				INC(NnofValues, LEN(p.p.datasetDescriptor));
			ELSE
				INC(NnofValues);
			END;
			NotifyListeners({EventPluginsChanged}, 0);
		END AddPlugin;
		
		PROCEDURE UpdatePlugin(p : Plugin);
		BEGIN
			IF p.p.helper # NIL THEN UpdateHelpers(p.p.helper); END;
			p.Update; 
		END UpdatePlugin;

		(* Updates plugin counter values / screen representation *)
		PROCEDURE UpdatePlugins(screen : BOOLEAN);
		VAR p : Plugin;
		BEGIN {EXCLUSIVE}
			p := plugins;
			WHILE alive & (p # NIL) DO
				IF p.active THEN
					IF screen THEN
						IF p.p.noSuperSampling THEN
							UpdatePlugin(p);				
						END;
						p.UpdateScreen;
					ELSE
						IF ~p.p.noSuperSampling THEN
							UpdatePlugin(p);
						END;
					END;
				END;
				p := p.link;
			END;
		END UpdatePlugins;
				
		PROCEDURE UpdateHelpers(h : Helper);
		BEGIN (* Caller holds obj lock *)
			WHILE alive & (h # NIL) DO 
				IF ~h.updated THEN h.Update; h.updated := TRUE; END;
				h := h.next; 
			END;
		END UpdateHelpers;
		
		(* Sets the update field of all helpers to FALSE *)
		PROCEDURE ResetHelpers;
		VAR p : Plugin; h : Helper;
		BEGIN
			p := plugins;
			WHILE p # NIL DO
				h := p.p.helper;
				WHILE h # NIL DO
					h.updated := FALSE;
					h := h.next;
				END;
				p := p.link;
			END;
		END ResetHelpers;
		
		(* Calculates % CPU time consumed by this process. Updates field perf *)
		PROCEDURE UpdatePerf;
		VAR timestamp, cycles : HUGEINT; i : LONGINT; value, sum : REAL;
		BEGIN {EXCLUSIVE}
			timestamp := AosBoot.GetTimer();
			IF lastTimestamp # 0 THEN
				FOR i := 0 TO AosBoot.MaxCPU-1 DO cycles := AosBoot.AddH(me.perfCyc[i], cycles); END;
				value := SHORT(100.0 * AosBoot.HIntToLReal(AosBoot.SubH(cycles, lastCycles)) / AosBoot.HIntToLReal(AosBoot.SubH(timestamp, lastTimestamp)));
				sampleBuffer[sample MOD sampleBufferSize] := value; INC(sample);
				lastCycles := cycles;				
				FOR i := 0 TO sampleBufferSize-1 DO sum := sum + sampleBuffer[i]; END;
				value := sum / sampleBufferSize;
				NotifyListeners({EventPerfUpdate}, value); 
			END;
			lastTimestamp := timestamp;	
		END UpdatePerf;
		
		PROCEDURE Terminate;
		BEGIN
			alive := FALSE; timer.Wakeup;
			BEGIN {EXCLUSIVE} AWAIT(dead); END;
		END Terminate;
		
		PROCEDURE &New;
		BEGIN
			NEW(timer); alive := TRUE; dead := FALSE;
			sampleInterval := DefaultSampleInterval;
			sampleBufferSize := DefaultSampleBufferSize;
			screenInterval := DefaultScreenRefresh;
			NEW(sampleBuffer, sampleBufferSize);
			NEW(notifiers); (* head of list *)
		END New;
				
	 BEGIN {ACTIVE, PRIORITY(AosActive.High)}
		me := GetCurrentProcess();
		AosKernel.SetTimer(screenTimer, screenInterval);
		WHILE alive DO 
			timestamp := AosKernel.GetTimer();

			(* plugin  update *)
			UpdatePlugins(FALSE);
			ResetHelpers;
						
			timediff := sampleInterval - (AosKernel.GetTimer() - timestamp);
			
			(* screen refresh *)
			left := AosKernel.Left(screenTimer);
			IF left <= timediff THEN
				IF left > 0 THEN timer.Sleep(left); END;			
				AosKernel.SetTimer(screenTimer, screenInterval);
				UpdatePlugins(TRUE);
			END;
			
			NotifyListeners({EventSampleLoopDone}, 0);
			
			UpdatePerf;
						
			timediff := sampleInterval - (AosKernel.GetTimer() - timestamp);
			IF alive & (timediff > 0) THEN timer.Sleep(timediff); END;
		END;
		BEGIN {EXCLUSIVE} dead := TRUE; END;
	END Updater;

VAR
	updater- : Updater;
	
	(* statistics *)
	NnofPlugins-, NnofValues- : LONGINT;

(** Return the number of CPUs *)
PROCEDURE GetNbrOfCpus*() : LONGINT;
VAR nbrOfCpus, cpuNbr : LONGINT;
BEGIN
	(* Determine number of CPUs *)
	nbrOfCpus := 0;
	FOR cpuNbr := 0 TO AosBoot.MaxCPU-1 DO
		IF ~AosBoot.EqualH(AosActive.idleCycles[cpuNbr], 0) THEN 
			(* TODO: Improve number of CPU detection *)
			INC(nbrOfCpus);
		END;
	END;	
	RETURN nbrOfCpus;
END GetNbrOfCpus;
	
(**	Estimate the processors clock rate.
	This is done by measuring the number of clock cycles within a time interval of 1 second.
	Note: While the GC is running, all interrupts are masked. Therefore, also AosActive.ticks is
	not updated which makes the measurement unaccurate.
	@param clockrate: Estimated clockrate in MHz
	@return: TRUE, if the estimation can be considered accurate, FALSE otherwise
*)
PROCEDURE EstimateCpuClockrate*(VAR clockrate : LONGINT) : BOOLEAN;
VAR 
	timer : AosKernel.Timer; milliTimer : AosKernel.MilliTimer;
	startTime, endTime, timeDiff : HUGEINT;
	nbrOfGcRuns : LONGINT;
BEGIN
	NEW(timer); nbrOfGcRuns := AosHeap.Ngc;
	AosKernel.SetTimer(milliTimer, 1000);
	startTime := AosBoot.GetTimer();
	WHILE ~AosKernel.Expired(milliTimer) DO
		timer.Sleep(1);
		IF nbrOfGcRuns # AosHeap.Ngc THEN RETURN FALSE; END;
	END;
	endTime := AosBoot.GetTimer();
	IF nbrOfGcRuns # AosHeap.Ngc THEN RETURN FALSE; END; 
	timeDiff := AosBoot.SubH(endTime, startTime);
	clockrate := AosBoot.HIntToLInt(AosBoot.DivH(timeDiff, 1000*1000));
	RETURN TRUE;
END EstimateCpuClockrate;

(** Convert number of cycles (high-res timer) to milliseconds
	@param cycles: Number of cycles
	@param mhz: CPU clockrate in MHz
	@return: Number of milliseconds
*)
PROCEDURE CyclesToMs*(cycles : HUGEINT; mhz : LONGINT) : LONGINT;
BEGIN
	RETURN AosBoot.HIntToLInt(AosBoot.DivH(cycles, 1000*mhz));
END CyclesToMs;

(** Convert number of milliseconds into string of the form d:h:m:s if m >= 1 or x.xxxs if m < 1*)
PROCEDURE MsToString*(ms : LONGINT; VAR string : ARRAY OF CHAR);
CONST Day=24*60*60*1000; Hour = 60*60*1000; Minute = 60*1000; Second = 1000; Millisecond = 1;
	
	PROCEDURE Append(divisor : LONGINT; unit : ARRAY OF CHAR);
	VAR nbr : ARRAY 16 OF CHAR; val : LONGINT;
	BEGIN
		val := ms DIV divisor; ms := ms MOD divisor;
		Utilities.IntToStr(val, nbr); Utilities.Append(string, nbr); Utilities.Append(string, unit);
	END Append;	

BEGIN
	string := "";
	IF ms >= Minute THEN (* d:h:m:s *)
		IF ms >= Day THEN Append(Day, "d "); END;
		IF ms >= Hour THEN Append(Hour, "h "); END;
		IF ms >= Minute THEN Append(Minute, "m "); END;
		IF ms >= Second THEN Append(Second, "s"); END;
	ELSE (* x.xxxs *)
		Append(Second, "."); Append(100, ""); Append(10, ""); Append(Millisecond, "s");
	END;
END MsToString;

PROCEDURE GetNameDesc*(plugin : AosPlugins.Plugin; VAR devicename : DeviceName);
BEGIN
	COPY(plugin.name, devicename); 
	Utilities.Append(devicename, " ("); Utilities.Append(devicename, plugin.desc); Utilities.Append(devicename, ")");
END GetNameDesc;

(** Show all currently installed performance counters *)
PROCEDURE Show*(par : ANY) : ANY;
BEGIN
	updater.Show;
	RETURN NIL;
END Show;

PROCEDURE GetCurrentProcess() : AosActive.Process;
BEGIN 
	RETURN SYSTEM.VAL(AosActive.Process, AosMemory.GetProcessPtr());
END GetCurrentProcess;

PROCEDURE LoadPlugin(name : ARRAY OF CHAR);
VAR 
	m: AosModules.Module; c: AosModules.CommandParProc;
	ignore : LONGINT; ptr : PTR;
	msg : AosEvents.Message;    
BEGIN
	m:= AosModules.ThisModule(name, ignore, msg);
	IF m # NIL THEN
		c := AosModules.ThisCommandPar(m, "Install");
		IF c # NIL THEN
			IF Verbose THEN AosOut.String("WMPerfMon: Plugin "); AosOut.String(name); AosOut.String(" loaded."); AosOut.Ln; END; 
			ptr := c(NIL);
		ELSE 
			msg := "Could not load plugin "; Utilities.Append(msg, name); Utilities.Append(msg, " - Install command not found");
			AosEvents.AddEvent("WMPerfMonPlugins", AosEvents.Error, 2, 1, 0, msg, TRUE);
		END;
	ELSE AosOut.String("WMPerfMon: Plugin "); AosOut.String(name); AosOut.String(" already loaded."); AosOut.Ln;
	END;
END LoadPlugin;

PROCEDURE LoadConfiguration;
VAR elem : XML.Element; enum : XMLObjects.Enumerator; ptr : PTR; string : XML.String;
BEGIN
	elem := AosConfig.GetNamedElement(AosConfig.config.GetRoot(), "Section", "Applications");
	IF elem # NIL THEN
		elem := AosConfig.GetNamedElement(elem, "Section", "Performance Monitor");
		IF elem # NIL THEN
			elem := AosConfig.GetNamedElement(elem, "Section", "Plugins");
			IF elem # NIL THEN
				enum := elem.GetContents(); enum.Reset();
				WHILE enum.HasMoreElements() DO
					ptr := enum.GetNext();
					IF ptr IS XML.Element THEN
						string := ptr(XML.Element).GetAttributeValue("value");
						IF (string # NIL) THEN
							IF Utilities.Match("TRUE", string^) THEN
								string := ptr(XML.Element).GetAttributeValue("name");
								IF (string # NIL) THEN
									LoadPlugin(string^);
								END;
							END;
						END;
					END;
				END;
			ELSE AosOut.String("WMPerfMon: Warning: Section 'Applications.Performance Monitor.Plugins' not found in config file."); AosOut.Ln;
			END;
		ELSE AosOut.String("WMPerfMon: Warning: 'Performance Monitor' section not found in section 'Applications' in config file."); AosOut.Ln;
		END;
	ELSE AosOut.String("WMPerfMon: Warning: 'Applications' section not found in config file."); AosOut.Ln;
	END;
END LoadConfiguration;

PROCEDURE Cleanup;
BEGIN
	updater.Terminate;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	NEW(updater);
	LoadConfiguration;
END WMPerfMonPlugins.