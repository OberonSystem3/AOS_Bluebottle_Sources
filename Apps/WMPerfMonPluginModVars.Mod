MODULE WMPerfMonPluginModVars; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor module variables  plugin"; *)
(**
 * History:
 *
 *	16.02.2006	First Release (staubesv)
 *)

IMPORT
	SYSTEM,
	WMPerfMonPlugins,
	AosOut, AosModules, AosTrap, AosCommands, AosIO, Utilities;

CONST

	ModuleName = "WMPerfMonPluginModVars";
	
	(* Supported module variable types. MUST NOT BE CHANGED *)
	Byte= 1;
	Boolean = 2;
	Char= 3;
	Shortint = 4;
	Integer = 5;
	Longint = 6;
	Set = 9;
	Real = 7;
	Longreal = 13; (* not yet implemented *)
	Ptr = 29;
	
TYPE

	VariableDescriptor* = RECORD
		moduleName* : AosModules.Name;
		variableName* : ARRAY 64 OF CHAR;
	END;
	
	VariableDescriptors* = POINTER TO ARRAY OF VariableDescriptor;


	ModVarParameter = POINTER TO RECORD (WMPerfMonPlugins.Parameter)
		vd : VariableDescriptors;
	END;

TYPE
	
	ModVar = OBJECT(WMPerfMonPlugins.Plugin)
	VAR
		vd : VariableDescriptors;
			
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		BEGIN
			ASSERT((p # NIL) & (p IS ModVarParameter) & (p(ModVarParameter).vd # NIL));
			vd := p(ModVarParameter).vd;
			p.description := "Module variables access adapter";			
			p.modulename := ModuleName;
			p.autoMax := TRUE; p.minDigits := 5;
			p.datasetDescriptor := GetDatasetDescriptor(vd);
		END Init;
						
		PROCEDURE UpdateDataset*;
		VAR module : AosModules.Module; variable : AosTrap.Variable; i : LONGINT; value : LONGREAL;
		BEGIN 
			FOR i := 0 TO LEN(vd)-1 DO
				module := AosModules.ModuleByName(vd[i].moduleName);
				IF module # NIL THEN
					IF AosTrap.FindVar(module, vd[i].variableName, variable) THEN
						IF GetValueOf(variable, value) THEN
							dataset[i] := SHORT(value);
						ELSE
						END;
					ELSE
					END;
				ELSE
				END;	
			END;
		END UpdateDataset;
		
	END ModVar;

PROCEDURE GetValueOf(v: AosTrap.Variable; VAR value : LONGREAL) : BOOLEAN;
VAR short : SHORTINT; int : INTEGER; long : LONGINT; ch : CHAR; real : REAL;
BEGIN
	IF (v.n = 1) THEN (* arrays not supported *)
		CASE v.type OF
			|Byte: SYSTEM.GET(v.adr, ch); value := ORD(ch);
			|Boolean: SYSTEM.GET(v.adr, ch); IF ch = 0X THEN value := 0; ELSE value := 1; END;
			|Char: SYSTEM.GET(v.adr, ch); value := ORD(ch);
			|Shortint: short := SYSTEM.GET8(v.adr); value := short;
			|Integer: int := SYSTEM.GET16(v.adr); value := int;
			|Longint: long := SYSTEM.GET32(v.adr); value := long;
			|Set: long := SYSTEM.GET32(v.adr); value := long;
			|Real: real := SYSTEM.GET32(v.adr); value := real;
			|Longreal:
			|Ptr: long := SYSTEM.GET32(v.adr); value := long;
		ELSE
			RETURN FALSE;
		END;
	ELSE
		RETURN FALSE;
	END;
	RETURN TRUE;
END GetValueOf;
	
PROCEDURE GetDatasetDescriptor(vd : VariableDescriptors) : WMPerfMonPlugins.DatasetDescriptor;
VAR ds : WMPerfMonPlugins.DatasetDescriptor; i : LONGINT;
BEGIN
	ASSERT(vd # NIL);
	NEW(ds, LEN(vd));
	FOR i := 0 TO LEN(vd)-1 DO
		COPY(vd[i].variableName, ds[i].name);
	END;
	RETURN ds;
END GetDatasetDescriptor;
	
PROCEDURE InstallPlugin*(name : WMPerfMonPlugins.Name; vd : VariableDescriptors; VAR msg : ARRAY OF CHAR; res : LONGINT);
VAR par : ModVarParameter; plugin : ModVar;
BEGIN
	ASSERT(vd # NIL);
	NEW(par); par.vd := vd; par.name := name;
	NEW(plugin, par);
END InstallPlugin;

PROCEDURE Add(VAR vd : VariableDescriptors; moduleName, variableName : ARRAY OF CHAR);
VAR new : VariableDescriptors; i : LONGINT;
BEGIN
	IF vd = NIL THEN 
		NEW(vd, 1); 
		COPY(moduleName, vd[0].moduleName);
		COPY(variableName, vd[0].variableName);
	ELSE
		NEW(new, LEN(vd)+1);
		i := 0; WHILE (i < LEN(vd)) DO new[i] := vd[i]; INC(i); END;
		COPY(moduleName, new[i].moduleName);
		COPY(variableName, new[i].variableName);
		vd := new;
	END;
END Add;

PROCEDURE Install*(par : PTR) : PTR; (** pluginname modulename.variablename  {" " modulename.variablename} ~ *)
VAR 
	r : AosIO.StringReader; string : ARRAY 128 OF CHAR; pluginname : WMPerfMonPlugins.Name;
	vd : VariableDescriptors; split : Utilities.StringArray;
	msg : ARRAY 128 OF CHAR; res : LONGINT;
BEGIN
	AosCommands.PosPar(par, r);	
	r.SkipWhitespace; r.String(pluginname);
	REPEAT
		r.SkipWhitespace; r.String(string);
		IF string # "" THEN
			split := Utilities.Split(string, ".");
			IF LEN(split) = 2 THEN
				Add(vd, split[0]^, split[1]^);
			ELSE
				ShowUsage; RETURN NIL;
			END;
		END;
	UNTIL (r.res # AosIO.Ok);
	IF vd # NIL THEN
		InstallPlugin(pluginname, vd, msg, res);
		IF res = 0 THEN
			AosOut.String(ModuleName); AosOut.String(": Plugin installed."); AosOut.Ln;
		ELSE
			AosOut.String(ModuleName); AosOut.String(": Error: "); AosOut.String(msg); AosOut.Ln;
		END;
	ELSE
		ShowUsage;
	END;
	RETURN NIL;
END Install;

PROCEDURE ShowUsage;
BEGIN
	AosOut.String(ModuleName); AosOut.String(": Expected parameters: modulename.variablename"); AosOut.Ln;
END ShowUsage;

PROCEDURE Cleanup;
BEGIN
	WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END WMPerfMonPluginModVars.

S.Free WMPerfMonPluginModVars ~

WMPerfMonPluginModVars.Install ~

WMPerfMonPluginModVars.Install AosNet AosNet.nofBuf ~