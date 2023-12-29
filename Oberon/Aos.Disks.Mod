(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

 MODULE Disks; (** non-portable *)	(* pjm *)
(** AUTHOR "pjm"; PURPOSE "Oberon for Aos disks"; *)

(** Aos emulation module for Native Oberon applications.  Aos applications should use AosDisks directly. *)

(** Block devices. *)

IMPORT AosPlugins, AosDisks;

CONST
	Read* = AosDisks.Read; Write* = AosDisks.Write;	(** Device.transfer.op *)
	
		(** res parameter *)
	Ok* = AosDisks.Ok;	(** no error *)
	
		(** common errors - a device may also return its own error codes > 0 *)
	MediaChanged* = AosDisks.MediaChanged;	(** media in removable device was changed unexpectedly *)
	WriteProtected* = AosDisks.WriteProtected;	(** write failed because media is write-protected *)
	Unsupported* = AosDisks.Unsupported;	(** operation is currently not supported on this device *)
	DeviceInUse* = AosDisks.DeviceInUse;	(** the device is open (UpdatePartitionTable) *)
	MediaMissing* = AosDisks.MediaMissing;	(** the device media is not present *)

		(** Device.flags *)
	ReadOnly* = AosDisks.ReadOnly;	(** the current media can not be written to *)
	Removable* = AosDisks.Removable;	(** the device has removable media *)
	
		(** Partition.flags *)
	Mounted* = AosDisks.Mounted;	(** a file system is currently mounted on the partition (set by file system implementations) *)
	Primary* = AosDisks.Primary;	(** a primary partition *)
	Boot* = AosDisks.Boot;	(** a bootable partition *)
	Valid* = AosDisks.Valid;	(** media contains a valid partition table. *)

TYPE
	Name* = AosPlugins.Name;
	Description* = AosPlugins.Description;
	
	Message* = AosDisks.Message;

	Device* = POINTER TO DeviceDesc;
	
	Partition* = AosDisks.Partition;
	PartitionTable* = AosDisks.PartitionTable;

	TransferProc* = PROCEDURE (dev: Device; op, block, num: LONGINT; VAR data: ARRAY OF CHAR; ofs: LONGINT; VAR res: LONGINT);
	GetSizeProc* = PROCEDURE (dev: Device; VAR size, res: LONGINT);
	HandleProc* = PROCEDURE (dev: Device; VAR msg: Message; VAR res: LONGINT);

(** The base for block devices. It provides operations on an abstract array of disk blocks of blockSize bytes, 
numbered from 0 to size-1. If applicable, a PC-format partition table starts at block 0, and can be read into 
the table field with Open or UpdatePartitionTable. *)

	DeviceDesc* = RECORD	(** fields read-only, initialized by extender *)
		name*: Name;	(** unique device name *)
		desc*: Description;	(** device description for Partition.Show etc. *)
		blockSize*: LONGINT;	(** in bytes - unit of block, num & size parameters *)
		flags*: SET;	(** ReadOnly, Removable *)
		transfer*: TransferProc;	(** read or write blocks *)
		getSize*: GetSizeProc;	(** get total size of device *)
		handle*: HandleProc;	(** handle optional messages *)
		table*: PartitionTable;	(** cache for partition table *)
		openCount*: LONGINT;	(** number of times device has been opened *)
		real: AosDisks.Device;	(* underlying device *)
	END;
	
	EjectMsg* = AosDisks.EjectMsg;	(** eject the media *)
	LockMsg* = AosDisks.LockMsg;	(** disallow manual ejection *)
	UnlockMsg* = AosDisks.UnlockMsg;	(** allow manual ejection *)
	SavePowerMsg* = AosDisks.SavePowerMsg;	(** spin down the device *)
	GetGeometryMsg* = AosDisks.GetGeometryMsg;	(** return physical geometry *)
	ShutdownMsg* = AosDisks.ShutdownMsg;	(** shut down the device (driver) *)

	DeviceTable* = POINTER TO ARRAY OF Device;

PROCEDURE Update(dev: Device);
BEGIN
	dev.blockSize := dev.real.blockSize; dev.flags := dev.real.flags;
	dev.table := dev.real.table; dev.openCount := dev.real.openCount
END Update;

PROCEDURE Transfer(dev: Device; op, block, num: LONGINT; VAR data: ARRAY OF CHAR; ofs: LONGINT; VAR res: LONGINT);
BEGIN
	dev.real.Transfer(op, block, num, data, ofs, res);
	Update(dev)
END Transfer;

PROCEDURE GetSize(dev: Device; VAR size, res: LONGINT);
BEGIN
	dev.real.GetSize(size, res);
	Update(dev)
END GetSize;

PROCEDURE Handle(dev: Device; VAR msg: Message; VAR res: LONGINT);
BEGIN
	dev.real.Handle(msg, res);
	Update(dev)
END Handle;

(** Get a table of currently registered devices. *)

PROCEDURE GetRegistered*(VAR table: DeviceTable);
VAR i: LONGINT; t: AosPlugins.Table; d: Device;
BEGIN
	AosDisks.registry.GetAll(t);
	IF t # NIL THEN
		NEW(table, LEN(t));
		FOR i := 0 TO LEN(t)-1 DO
			NEW(d);	(* create wrapper device *)
			d.real := t[i](AosDisks.Device);
			d.name := d.real.name; d.desc := d.real.desc;
			d.transfer := Transfer; d.getSize := GetSize; d.handle := Handle;
			Update(d);
			table[i] := d
		END
	ELSE
		table := NIL
	END
END GetRegistered;

(** Read a PC-format partition table starting at block 0 and initialize dev.table. dev.table[0] is a virtual 
partition spanning the entire device, with type = 256. If the device has been opened before, do nothing and 
return DeviceInUse, otherwise return Ok. On any other error dev.table is set NIL. *)

PROCEDURE UpdatePartitionTable*(dev: Device; VAR res: LONGINT);
BEGIN
	AosDisks.UpdatePartitionTable(dev.real, res);
	Update(dev)
END UpdatePartitionTable;

(** Open the device and increment its open count if successful. If the device is opened for the first time, 
lock it and update its partition table. *)
PROCEDURE Open*(dev: Device; VAR res: LONGINT);
BEGIN
	dev.real.Open(res);
	Update(dev)
END Open;

(** Close the device and decrement its open count. Unlock it if the open count has reached 0. *)
PROCEDURE Close*(dev: Device; VAR res: LONGINT);
BEGIN
	dev.real.Close(res);
	Update(dev)
END Close;

END Disks.

(**
o Further Transfer op numbers may be added in future, therefore devices should check explicitly for op = Read or op = Write.
o Positive res numbers are device-specific. Negative res numbers are reserved.
o Block size 512 and LONGINT block number limit us to 1Tb = 1024Gb.
o When the media is changed in a removable device, the next operation (transfer, getSize, handle) will fail 
with res = MediaChanged. After that the new media can be accessed as usual.  [RFC: Perhaps the MediaChanged flag should be sticky until the next LockMsg].
o The ReadOnly flag and blockSize may depend on the current media and is only valid after a successful access 
operation to a drive with removable media (transfer, getSize).
o When receiving a LockMsg, the device should clear the media not present flag. This means clients using Open/Close can treat the MediaChanged error as a real error and don't have to retry any operations.
o When the system is shut down, a ShutdownMsg is sent to every device. The driver has to perform whatever is necessary to clean up. A driver that handles multiple devices must expect one shutdown message per device.
*)
