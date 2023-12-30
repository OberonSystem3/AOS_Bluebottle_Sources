MODULE AosUsbTools; (** AUTHOR: "staubesv"; PURPOSE: "USB Tools"; *)
(**
 * Usage:
 *
 *	AosUsbTools.Mount prefix alias [volpar] ["|" fspar] ~ 				Starts a thread that waits for the disk device to become accessible and then mounts it.
 *																	(non-blocking)
 *																	Example: AosUsbTools.Mount USBDrive AosFS USB0#1 ~
 *
 *
 *	AosUsbTools.BlockingMount prefix alias [volpar] ["|" fspar] ~ 		Waits for the disk device to become accessible and then mounts it. Should not be used by a user.
 *																	(blocking)
 *																	Example: AosUsbTools.BlockingMount USBDrive AosFS USB0#1 ~
 *
 *	AosUsbTools.AwaitAndExecute devicename commandlist ~		Starts a thread that waits for the disk device to become accessible and then executes the commands.
 *																	(non-blocking)
 *																	Example: AosUsbTools.AwaitAndExecute USB0 AosFSTools.Mount USBDrive AosFS USB0#1+PET.Open USBDrive:/PET.Mod ~
 *
 *	AosUsbTools.AwaitAndExecute0 devicename commandlist ~		Waits for the disk device to become accessible and then executes the commands. Not for users.
 *																	(blocking)
 *																	Example: AosUsbTools.AwaitAndExecute0 USB0 AosFSTools.Mount USBDrive AosFS USB0#1~
 *
 *	S.Free AosUsbTools ~	
 *
 * History:
 *
 *	28.06.2006	First release (staubesv)
 *)
 
IMPORT
	AosOut, AosIO, AosCommands, AosPlugins,
	AosDisks, AosFSTools;
	
CONST

	CommandSeparator = "+";

(** Starts a thread that first waits until the device to be mounted becomes accessible and then mounts it *)
PROCEDURE Mount*(par : ANY) : ANY; (** prefix alias [volpar] ["|" fspar] ~ *)
VAR msg : ARRAY 8 OF CHAR; res : LONGINT;
BEGIN
	AosCommands.Activate("AosUsbTools.BlockingMount", par (AosCommands.Parameters), {}, res, msg); (* ignore result *)	
	RETURN NIL
END Mount;

(** Waits for the device to be mounted and then try to mount it *)
PROCEDURE BlockingMount*(par : ANY) : ANY; (** prefix alias [volpar] ["|" fspar] ~ *)
VAR 
	p : AosCommands.Parameters; r : AosIO.StringReader;
	plugin : AosPlugins.Plugin;
	devicename, string : ARRAY 128 OF CHAR;
BEGIN
	p := par(AosCommands.Parameters);
	NEW(r, LEN(p.str^)); r.Set(p.str^);
		
	(* Skip the first two parameters *)
	r.String(string); r.SkipWhitespace; r.String(string); r.SkipWhitespace;
	
	(* read dev#part string *)
	r.String(string);	
	
	IF ExtractDevicename(string, devicename) THEN
	
		AosOut.Enter; AosOut.String("AosUsbTools: Waiting for USB device "); AosOut.String(devicename); AosOut.Exit;
		plugin := AosDisks.registry.Await(devicename);
		AosOut.Enter; AosOut.String("AosUsbTools: Device "); AosOut.String(devicename); AosOut.String(" connected."); AosOut.Exit;
		
		IF AosFSTools.Mount(par) = NIL THEN END;
	ELSE
		AosOut.Enter; AosOut.String("AosUsbTools.BlockingMount: Could not extract device name"); AosOut.Exit;
	END;
	RETURN NIL;
END BlockingMount;

(** Waits for the specified disk device and then execute the commands *)
PROCEDURE AwaitAndExecute*(par : ANY) : ANY; (** devicename commandlist ~ *)
VAR msg : ARRAY 8 OF CHAR; res : LONGINT;
BEGIN
	AosCommands.Activate("AosUsbTools.AwaitAndExecute0", par (AosCommands.Parameters), {}, res, msg); (* ignore result *)	
	RETURN NIL
END AwaitAndExecute;

(** Waits for the specified disk device and then execute the commands. Note: Does NOT mount the device. *)
PROCEDURE AwaitAndExecute0*(par : ANY) : ANY; (** devicename commandlist ~ *)
VAR 
	p : AosCommands.Parameters; r : AosIO.StringReader;
	devicename, msg : ARRAY 128 OF CHAR;
	commandList : POINTER TO ARRAY OF CHAR;
	plugin : AosPlugins.Plugin;
	i, size, len, res : LONGINT;
BEGIN
	p := par(AosCommands.Parameters);
	NEW(r, LEN(p.str)); r.Set(p.str^);			
	
	(* read device name *)
	r.SkipWhitespace; r.String(devicename);
	
	AosOut.Enter; AosOut.String("AosUsbTools: Waiting for USB device "); AosOut.String(devicename); AosOut.Exit;
	plugin := AosDisks.registry.Await(devicename);
	AosOut.Enter; AosOut.String("AosUsbTools: Device "); AosOut.String(devicename); AosOut.String(" connected."); AosOut.Exit;
	
	(* read and copy command list *)
	r.SkipWhitespace;
	size := r.Available();
	IF size > 0 THEN
		NEW(commandList, size + 1);
		r.Bytes(commandList^, 0, size, len);
		FOR i := 0 TO size DO IF commandList[i] = CommandSeparator THEN commandList[i] := ";"; END; END;		

		commandList^[size] := 0X;

		AosCommands.Call(commandList^, {}, res, msg);
		IF res # AosCommands.Ok THEN
			AosOut.Enter; 
			AosOut.String("AosUsbTools: AwaitAndExecute: Command execution error, res: "); AosOut.Int(res, 0); 
			AosOut.String(" ("); AosOut.String(msg); AosOut.String(")");
			AosOut.Exit;
		END;
	END;
	
	RETURN NIL;
END AwaitAndExecute0;

PROCEDURE ExtractDevicename(devpart : ARRAY OF CHAR; VAR devicename : ARRAY OF CHAR) : BOOLEAN;
VAR i : LONGINT;
BEGIN
	WHILE (i < LEN(devpart)) & (devpart[i] # "#") & (i < LEN(devicename)) DO
		devicename[i] := devpart[i];
		INC(i);
	END;
	RETURN (i < LEN(devpart)) & (devpart[i] = "#");
END ExtractDevicename;

END AosUsbTools.

AosUsbTools.Mount USB AosFS USB0#1 ~		S.Free AosUsbTools ~
