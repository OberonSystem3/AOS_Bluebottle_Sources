MODULE AosLoopback;	(** AUTHOR "mvt"; PURPOSE "Virtual local loopback/discard network device"; *)

IMPORT AosNet, AosModules, AosPlugins;

TYPE
	LinkDevice =  OBJECT(AosNet.LinkDevice)

		PROCEDURE &Constr(type, mtu, adrSize: LONGINT);
		VAR res: LONGINT;
		BEGIN
			Constr^(type, mtu, adrSize); (* call inherited constructor first *)
			
			calcChecksum := {AosNet.ChecksumIP, AosNet.ChecksumUDP, AosNet.ChecksumTCP};
			
			(* Add to registry *)
			SetName("Loopback");
			AosNet.registry.Add(SELF, res);
			ASSERT(res = AosPlugins.Ok);
		END Constr;
		
		PROCEDURE Linked*(): LONGINT;
		BEGIN
			RETURN AosNet.LinkLinked;
		END Linked;
		
		PROCEDURE Finalize*(connected: BOOLEAN);
		BEGIN
			(* Remove from registry *)
			AosNet.registry.Remove(SELF);
			Finalize^(connected);
		END Finalize;
		
		PROCEDURE DoSend(dst: AosNet.LinkAdr; type: LONGINT;  VAR l3hdr, l4hdr, data: ARRAY OF CHAR; h3len, h4len, dofs, dlen: LONGINT);
		BEGIN
			(* do nothing, discard packet *)
		END DoSend;

	END LinkDevice;

VAR
	device: LinkDevice;

PROCEDURE Cleanup();
BEGIN
	device.Finalize(TRUE);
END Cleanup;

(** Procedure for initializing the module *)
PROCEDURE Install*(par : PTR) : PTR;
BEGIN
	(* module body is called implicitly *)
	RETURN NIL;
END Install;
	
BEGIN
	NEW(device, AosNet.TypePointToPoint, AosNet.MaxPacketSize, 0);
	AosModules.InstallTermHandler(Cleanup);
END AosLoopback.

(*
History:
11.10.2003	mvt	Created
17.10.2003	mvt	Changed for new initialization and finalization (see AosNet)
17.12.2003	mvt	Changed for new method AosNet.Linked
*)

Aos.Call AosLoopback.Install
System.Free AosLoopback~

Installation
Add AosLoopback.Install to AosConfig.XML, section 'Autostart' to load driver at system startup.
