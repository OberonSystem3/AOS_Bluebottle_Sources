MODULE AosArchives; (** AUTHOR "FN"; PURPOSE "Abstract Archive Object"; *)

IMPORT
	AosModules, AosConfig, Utilities, AosIO;

CONST
	ArchiveNameSize = 128;

TYPE
	StringObject*= OBJECT
	VAR value -: ARRAY 256 OF CHAR;

		PROCEDURE & Init(name : ARRAY OF CHAR);
		VAR i : LONGINT;
		BEGIN
			FOR i := 0 TO LEN(name)-1 DO
				value[i] := name[i];
				IF name[i] = 0X THEN RETURN END
			END
		END Init;

	END StringObject;

	EntryInfo*= OBJECT

		PROCEDURE GetName*() : Utilities.String;
		BEGIN HALT(301)
		END GetName;

		PROCEDURE GetSize*() : LONGINT;
		BEGIN HALT(301)
		END GetSize;

		PROCEDURE GetInfoString*() : Utilities.String;
		BEGIN HALT(301)
		END GetInfoString;

	END EntryInfo;

	Index* = POINTER TO ARRAY OF EntryInfo;

	Archive* = OBJECT
	VAR name -: ARRAY ArchiveNameSize OF CHAR;

		PROCEDURE Acquire*;
		BEGIN HALT(301)
		END Acquire;

		PROCEDURE Release*;
		BEGIN HALT(301)
		END Release;

		PROCEDURE GetIndex*() : Index;
		BEGIN HALT(301)
		END GetIndex;

		PROCEDURE GetEntryInfo*(name : ARRAY OF CHAR) : EntryInfo;
		BEGIN HALT(301)
		END GetEntryInfo;

		PROCEDURE RemoveEntry*(name : ARRAY OF CHAR);
		BEGIN HALT(301)
		END RemoveEntry;

		PROCEDURE RenameEntry*(from, to : ARRAY OF CHAR) : EntryInfo;
		BEGIN HALT(301)
		END RenameEntry;

		PROCEDURE OpenSender*(name : ARRAY OF CHAR) : AosIO.Sender;
		BEGIN HALT(301)
		END OpenSender;

		PROCEDURE OpenReceiver*(name : ARRAY OF CHAR) : AosIO.Receiver;
		BEGIN HALT(301)
		END OpenReceiver;

		PROCEDURE Copy*(name : ARRAY OF CHAR) : Archive;
		BEGIN HALT(301)
		END Copy;

	END Archive;

	(* ----- api ----------------------------------------------------- *)

	PROCEDURE Old*(name, type : ARRAY OF CHAR) : Archive;
	VAR old : AosModules.CommandParProc;
		a : StringObject;
		archive : ANY;
		config, factoryName : ARRAY 128 OF CHAR;
	BEGIN
		NEW(a, name);
		config := "Archives."; Utilities.Append(config, type);
		AosConfig.Get(config, factoryName);
		IF factoryName # "" THEN
			Utilities.Append(factoryName, ".Old");
			old := AosModules.GetCommandByString(factoryName);
			archive := old(a);
			IF archive = NIL THEN
				RETURN NIL
			ELSE
				RETURN archive(Archive)
			END
		ELSE
			RETURN NIL
		END
	END Old;

	PROCEDURE New*(name, type : ARRAY OF CHAR) : Archive;
	VAR old : AosModules.CommandParProc;
		a : StringObject;
		archive : ANY;
		config, factoryName : ARRAY 128 OF CHAR;
	BEGIN
		NEW(a, name);
		config := "Archives."; Utilities.Append(config, type);
		AosConfig.Get(config, factoryName);
		IF factoryName # "" THEN
			Utilities.Append(factoryName, ".New");
			old := AosModules.GetCommandByString(factoryName);
			archive := old(a);
			RETURN archive(Archive)
		ELSE
			RETURN NIL
		END
	END New;

END AosArchives.
