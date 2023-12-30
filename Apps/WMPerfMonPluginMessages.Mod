MODULE WMPerfMonPluginMessages; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor WMMessages statistics plugin"; *)
(**
 * Usage:
 *
 *	WMPerfMonPluginMessages.Install ~ loads the default message statistics plugins (messages added, messages discarded)
 *	WMPerfMonPluginMessages.InstallDetailed ~ loads a message statistics plugin for each message type
 *
 *	S.Free WMPerfMonPluginMessages ~ unloads all plugins
 *
 * History:
 *
 *	17.07.2006	First Release (staubesv)
 *	27.02.2007	Remove plugin when unloading module, single plugin for all message types (staubesv)
 *)

IMPORT
	WMPerfMonPlugins,
	AosOut, WMMessages, AosModules;
	
CONST
	ModuleName = "WMPerfMonPluginMessages";
			
TYPE
	
	MessagesPlugin = OBJECT(WMPerfMonPlugins.Plugin)

		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN	
			p.name := "Messages"; p.description := "WMMessages statistics";
			p.modulename := ModuleName;
			p.autoMax := TRUE; p.perSecond := TRUE; p.minDigits := 5; p.showSum := TRUE;
			
			NEW(ds, 12);
			ds[0].name := "messagesAdded";
			ds[1].name := "messagesDiscarded";
			ds[2].name := "MsgPointer ";
			ds[3].name := "MsgKey ";
			ds[4].name := "MsgClose ";
			ds[5].name := "MsgStyleChanged ";
			ds[6].name := "MsgFocus ";
			ds[7].name := "MsgExt ";
			ds[8].name := "MsgDrag ";
			ds[9].name := "MsgInvokeEvent ";
			ds[10].name := "MsgInvokeGenerator ";
			ds[11].name := "MsgResized ";
			p.datasetDescriptor := ds;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := WMMessages.messagesAdded;
			dataset[1] := WMMessages.messagesDiscarded;
			dataset[2] := WMMessages.messagesAddedByType[WMMessages.MsgPointer];
			dataset[3] := WMMessages.messagesAddedByType[WMMessages.MsgKey];
			dataset[4] := WMMessages.messagesAddedByType[WMMessages.MsgClose];
			dataset[5] := WMMessages.messagesAddedByType[WMMessages.MsgStyleChanged];
			dataset[6] := WMMessages.messagesAddedByType[WMMessages.MsgFocus];
			dataset[7] := WMMessages.messagesAddedByType[WMMessages.MsgExt];
			dataset[8] := WMMessages.messagesAddedByType[WMMessages.MsgDrag];
			dataset[9] := WMMessages.messagesAddedByType[WMMessages.MsgInvokeEvent];
			dataset[10] := WMMessages.messagesAddedByType[WMMessages.MsgInvokeGenerator];
			dataset[11] := WMMessages.messagesAddedByType[WMMessages.MsgResized];
		END UpdateDataset;
	
	END MessagesPlugin;

PROCEDURE Install*(none : ANY) : ANY; (** ~ *)
VAR par : WMPerfMonPlugins.Parameter; plugin : MessagesPlugin;
BEGIN
	IF WMMessages.Statistics THEN
		NEW(par); NEW(plugin, par);
	ELSE AosOut.String("WMPerfMonPluginMessages: WMMessages.Statistics is FALSE. Plugin not installed."); AosOut.Ln;
	END;
	RETURN NIL
END Install;

PROCEDURE Cleanup;
BEGIN
	IF WMMessages.Statistics THEN 
		WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);
	END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END WMPerfMonPluginMessages.

WMPerfMonPluginMessages.Install ~  S.Free WMPerfMonPluginMessages ~