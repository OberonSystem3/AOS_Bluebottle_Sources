MODULE AosUsbDebug; (** AUTHOR "staubesv"; PURPOSE "USB Debug Code Control"; *)
(** 
 * This module provides a central access point to the USB core system debug and trace options. 
 *
 * Notes: 
 * 	-	In case you want to boot from USB storage devices, you should set On, Trace and StrongChecks to FALSE to 
 *		keep the bootfile small
 *	-	If you are developing USB software, it is recommended to set all constants to TRUE. You can use AosUsbInfo.Mod 
 *		to selectively enable/disable trace options
 *
 * History:
 *
 *	06.02.2006	First release (staubesv)
 *	24.02.2006 	Added traceCustom trace option / debug levels (staubesv)
 *	05.01.2007	Added traceShortPacket trace option (staubesv)
 *)
 
CONST
	
	(** Show device attachments/removals, driver installation & HCs found *)
	Verbose* = TRUE;

	(** Debug Levels *)
	Default* = 0;			(** For production code. Show just top-level errors (e.g. device could not be connected), not details	*)
	Errors* = 1;				(** Show all errors that will cause malfunction of busses/devices										*)
	Warnings* = 2;			(** Also show warnings and errors that maybe can be recovered from 									*)

	(** Debug Level *)
	Level* = Errors;
			
	(** Enable code related to performance monitoring *)
	PerformanceMonitoring* = TRUE; 
	
	(** Enable statistics code *)
	Stats* = TRUE;
	
	(** Enable ASSERTs that really shouldn't fail *)
	StrongChecks* = TRUE;

	(** Enable trace code. Trace options below can only be used if this constant is set to TRUE *)
	Trace* = TRUE;
	
VAR
	(** Note: Trace must be set to TRUE if you want to use the trace options below 	*)

	(** USB core *)

	(** AosUsb.Mod *)
	traceDm*,						(* Show (un)registering of USB device drivers at DriverManager 			*)
	traceParsing*,					(* Trace parsing of USB standard descriptors 								*)
	traceDeviceStates*,				(* Show USB device state transitions 									*)
	
	(** AosUsbHcdi.Mod *)
	traceControl*,					(* Show control transfers 												*)
	traceControlData*,				(* Show data phase of control transfers 									*)
	traceTransfers*,					(* Trace bulk/interrupt/isochronous transfers 							*)
	traceFailed*,					(* Show trace of transfers that don't result in AosUsbdi.Ok or Shortpacket	*)
	traceShortPackets*,				(* Show trace of transfers that result in AosUsbdi.ShortPacket				*)
	tracePipes*,						(* De-/allocation of USB pipes, pipe.IsHalted, pipe.ClearHalt				*)
	traceCopying*,					(* Show message when data has to be copied (non-zero-copy operation) 	*)
	traceIoc*,						(* Show calls caused by interrupt on completion (IOC)					*)
	
	(** AosUsbUhci.Mod, AosUsbOhci.Mod & AosUsbEhci.Mod *)
	traceInit*,						(* Trace host controller initialization 										*)
	traceInterrupts*, 				(* Show interrupts of host controllers 									*)
	traceQueuing*,					(* Addition/removal of queue heads 										*)
	
	(** AosUsbHubDriver.Mod *)
	traceHubRequests*,				(* Trace hub class-specific requests 										*)
	traceSuspend*,					(* Trace suspend/resume related code 									*)
	traceConnects*,					(* Trace USB device connect/disconnect related code / hub status change	*)
	
	(** USB mass storage driver *)
	
	(* AosUsbStorage.Mod *)
	traceInfo*,						(* Show results of ReadCapacity & Inquiry commands						*)
	traceSensing*,					(* Show sense codes 													*)
	traceScRequests*,				(* Trace mass storage device class-specific requests 						*)
	traceScTransfers*,				(* Trace transfer from storage device class point of view 					*)
	traceCSWs*,					(* Show Command Status Wrappers (CSW)								*)
	traceCBWs*,					(* Show Command Block Wrappers (CBW)								*)
	traceScInit*,					(* Trace init of mass storage devices 										*)
	
	(** Custom trace option *)
	traceCustom*					(* The Bluebottle release won't contain custom traces. Use this for your	*)
									(* own purposes.														*)
	: BOOLEAN;

END AosUsbDebug.
