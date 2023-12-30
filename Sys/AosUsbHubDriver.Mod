MODULE AosUsbHubDriver; (** AUTHOR: "staubesv"; PURPOSE: "USB 2.0 Hub Driver"; *)
(**
 * Bluebottle USB 2.0 Hub Driver
 *
 * The hub driver is actually part of the USB Bus Driver and has direct access to the functionality offered by AosUsb.Mod.
 *
 * Usage: 
 *	
 *	AosUsbHubDriver.Install ~ will load this device driver
 *	S.Free AosUsbHubDriver ~ unloads it
 *
 * Overview:
 *
 *	HubDriverInterface(AosUsbdi.Driver)		Abstract class defining the interface to USB hub devices and USB root hubs
 *	HubDriver(HubDriverInterface)			Actual hub driver for both USB hub devices and USB root hubs, 
 * 											based on HubDriverInterface
 *	UsbHubDriver(HubDriver)				Implements HubDriverInterface for USB hub devices		
 *	UsbRootHubDriver(HubDriver)			Implements HubDriverInterface for USB root hubs
 *
 * References:
 *	
 *	Universal Serial Bus Specification, Revision 2.0 (available at www.usb.org)
 *
 * History:
 *
 *	24.11.2005	First release (staubesv)
 *	12.12.2005	Force check port status for USB hub devices to enumerate attached devices, use exception handling (staubesv)
 *	29.06.2006	Show overcurrent conditions on kernel log (staubesv)
 *	30.06.2006	Made HubDriver.Wait procedure EXCLUSIVE to protect timer from concurrent use (staubesv)
 *	03.07.2006	Bugfix: Correct address and port of transaction translator for low-/fullspeed devices connected to high-speed busses (staubesv)
 *	04.07.2006	UsbHubDriver.GetPortStatus: First ackknowledge change bits then evaluate port status (staubesv)
 *	02.08.2006	Bugfix in HubDriver.HandlePortStatusChange, adaptions to AosUsbdi (staubesv)
 *
 * TODOs:
 *	- power management/saving
 *	- overcurrent handling
 *	- correct TT support 
 *	- device driver connect procedure blocks HubDriver.HandlePortStatus change -> shouldn't do that,
 *		hubdriver should call connect itself, not as sideeffect of installing a driver via driver manager
 *)

IMPORT SYSTEM, AosOut, AosUsb, AosUsbHcdi, AosUsbdi, AosKernel, AosModules, Debug := AosUsbDebug;

CONST

	(* Name and description of the integrated USB (root) hub driver *)
	Name = "UsbHub";
	Description = "USB Hub Driver";
	
	AllowSuspend = FALSE;
	
	(* Interval in milliseconds the root hubs are polled when interrupt notification is not supported. *)
	PollingInterval = 200;

	(* Hub class port status bits *)
	PsCurrentConnectStatus = {0};
	PsPortEnabled = {1};
	PsSuspend = {2};
	PsOverCurrent = {3};
	PsReset = {4};
	PsPortPower = {8};
	PsLowSpeed = {9}; (* IF status * {9, 10} = {} THEN Fullspeed *)
	PsHighSpeed = {10};
	PsPortTestMode = {11};
	PsPortIndicators = {12};
	PsConnectStatusChange = {16};
	PsPortEnabledChange = {17};
	PsSuspendChange = {18};
	PsOvercurrentChange = {19};
	PsResetChange = {20};
	PsChangeMask = {16..20};
	
	(* Hub class hub status bit *)
	HsLocalPowerLost = {0};
	HsOvercurrent = {1};
	HsLocalPowerSourceChange = {16};
	HsOvercurrentChange = {17};
	
	(* Hub Class Request Codes (USB2.0, p. 421) *)
	GetStatus = 0;
	ClearFeature = 1;
	SetFeature = 3;
	GetDescriptor = 6;
	SetDescriptor = 7;
	ClearTtBuffer = 8;
	ResetTt = 9;
	GetTtState = 10;
	StopTt = 11;
	
	(* Hub Class Feature Selectors (USB2.0, p 421- 422) *)
	HubLocalPowerChange = 0; 
	HubOverCurrentChange = 1; 
	PortConnection = 0; 
	PortEnable = 1;
	PortSuspend = 2;
	PortOverCurrent = 3;
	PortReset = 4;
	PortPower = 8;
	PortLowSpeed = 9;
	PortConnectionChange = 16;
	PortEnableChange = 17;
	PortSuspendChange = 18;
	PortOverCurrentChange = 19;
	PortResetChange = 20;
	PortTest = 21;
	PortIndicator =22;	

	(* Descriptor types *)
	DescriptorHub = 29H;
	DescriptorDevice = 1;
	
	(* UsbHubDriver.powerSwitching & UsbHubDriver.ocProtection values *)
	NotAvailable = AosUsbHcdi.NotAvailable; (* MUST be 0 *)
	Global = AosUsbHcdi.Global; (* MUST be 1 *)
	PerPort = AosUsbHcdi.PerPort; (* MUST be 2 *) 
	
	(* Format of Setup Data *)
	ToDevice = AosUsbdi.ToDevice;
	ToHost = AosUsbdi.ToHost; 
	Class = AosUsbdi.Class;
	Device = AosUsbdi.Device;
	Other = AosUsbdi.Other;
	
	(* HubDriver.EnablePortPower parameter *)
	AllPorts = -1;
	
	(* Device attachement/removal *)
	DeviceAttached = 0;
	DeviceRemoved = 1;
	
	(* Number of times the status pipe of USB hub devices is tried to be restarted when errors occur *)
	StatusPipeMaxRetries = 5;

TYPE
	
	(* Interface to be implemented for both USB hub devices and USB root hubs *)
	HubInterface = OBJECT(AosUsbdi.Driver)
	VAR
	
		(** Note: Port numbers: 0..nbrOfPorts-1 *)

		(*
		 * This hub class specific request returns the hub descriptor.
		 * @param type: Descriptor type
		 * @param index: Descriptor index
		 * @param length: Number of bytes to load
		 * @param buffer: Buffer where to put the descriptor in (at offset 0)
		 * @return TRUE, if request succeeded, FALSE otherwise 
		 *)
		PROCEDURE GetHubDescriptor(type, index, length : LONGINT; VAR buffer : AosUsbdi.Buffer) : BOOLEAN;
		BEGIN HALT(301); RETURN FALSE; END GetHubDescriptor; (* abstract *)
		
		(*
		 * This hub class specific request overrides the hub descriptor.
		 * Note that this request is optional. It will be stalled by the USB hub device is not supported. As all USB
		 * device descriptors, its first byte is its length in bytes and its second bytes the descriptor type.
		 * @param type: Descriptor type
		 * @param index: Descriptor index
		 * @return TRUE, if request succeeded, FALSE otherwise
		 *)
		 PROCEDURE SetHubDescriptor(type, index : LONGINT; buffer : AosUsbdi.Buffer) : BOOLEAN;
		 BEGIN HALT(301); RETURN FALSE; END SetHubDescriptor; (* abstract *)
		 
		(*
		 * This hub class request resets a value reported in the hub status.
		 * @param feature: Feature selector (HubLocalPower or HubOvercurrent)
		 * @return TRUE, if request succeeded, FALSE otherwise
		 *)
		PROCEDURE ClearHubFeature(feature : LONGINT) : BOOLEAN;
		BEGIN HALT(301); RETURN FALSE; END ClearHubFeature; (* abstract *)
		
		(*
		 * This hub class request sets a value reported in the hub status.
		 * @param feature: Feature selector (HubLocalPowerChange or HubOvercurrentChange)
		 * @return TRUE, if request succeeded, FALSE otherwise
		 *)
		PROCEDURE SetHubFeature(feature : LONGINT) : BOOLEAN;
		BEGIN HALT(301); RETURN FALSE; END SetHubFeature; (* abstract *)		 	
		
		(*
		 * This hub class request resets a value reported in the port status.
		 * @param feature: Feature to be reset
		 * @port: Port number
		 * @return TRUE, if request succeeded, FALSE otherwise
		 *)
		PROCEDURE ClearPortFeature(feature, port,  selector : LONGINT) : BOOLEAN;
		BEGIN HALT(301); RETURN FALSE; END ClearPortFeature; (* abstract *)
		
		(*
		 * This hub class request sets a value reported in the hub status.
		 * @param port Port number
		 * @param feature Feature to be resetted (HubLocalPower or HubOvercurrent)
		 * @param selector 
		 * @return Status of the control transfer
		 *)
		PROCEDURE SetPortFeature(feature, port, selector : LONGINT) : BOOLEAN;
		BEGIN HALT(301); RETURN FALSE; END SetPortFeature; (* abstract *)
		
		(* 
		 * This hub class request returns the current hub status and the states that have change since the 
		 * previous acknowledgment.
		 * @param hubstatus
		 * @return TRUE, if status request succeeded, FALSE otherwise.
		 *)
		PROCEDURE GetHubStatus(VAR hubstatus : SET) : BOOLEAN;
		BEGIN HALT(301); RETURN FALSE; END GetHubStatus; (* abstract *)
		
		(*
		 * This hub class request returns the current port status and the current value of the port status
		 * change bits.
		 * @param port Port number
		 * @param ack Acknowledge status change bits
		 * @return Status of the specified port
		 *)
		PROCEDURE GetPortStatus(port : LONGINT; ack : BOOLEAN) : SET;
		BEGIN HALT(301); RETURN {}; END GetPortStatus; (* abstract *)
		
		(* 
		 * Transaction Translator (TT) control.
		 * High-speed capable USB hub devices can operate at full- or highspeed. When connected to a highspeed host
		 * controller, the communication between the hub device and the host is always at highspeed. When low- or fullspeed
		 * USB devices are attached to a USB hub device operating at highspeed, the split transaction protocol is used.
		 * The low-/fullspeed USB transactions are sent at highspeed from the host  to the hub device, which has one (single-TT) 
		 * or more (multi-TT) transaction tranlators. These translate the transaction into a low-/fullspeed transaction. 
		 *)
		
		(*
		 * This hub class specific request clears the state of the Transaction Translator (TT) bulk/control transfer after
		 * it has been left in a busy state due to high-speed errors. This request is only defined for non-periodic endpoints.
		 * @param dev : Low-/Fullspeed USB device 
		 * @param endpoint : Endpoint number
		 * @param port: If the hub supports a TT per port, this is the port number of the TT that encountered the high-speed errors.
		 * @return TRUE, if request succeeded, FALSE otherwiese
		 *)
		PROCEDURE ClearTTBuffer(dev : AosUsb.UsbDevice; endpoint, port : LONGINT) : BOOLEAN;
		BEGIN 
			RETURN FALSE;
		END ClearTTBuffer;
		
		(*
		 * This hub class specific request returns the internal state of the Transaction Translator (TT) in a vendor specific format.
		 * A TT receiving this request must have first been stopped using the StopTTRequest.
		 * @flags Vendor specific usage
		 * @port If the hub supports multiple TTs, specify the port number of the TT that will return TT_State. Must be one for single-TT hubs.
		 * @return TRUE, if the request succeeded, FALSE otherwise
		 *)
		PROCEDURE GetTTState(flags, port, len : LONGINT; VAR buffer : AosUsbdi.Buffer) : BOOLEAN;
		BEGIN
			RETURN FALSE;
		END GetTTState;
		
		(*
		 * This hub class specific request returns the Transaction Translator (TT) in a hub to a known state.
		 * After the reset is completed, the TT can resume its normal operation.
		 * @param port: If the hub supports multiple TTs, specify the port number of the TT that is to be reset (Must be 1 for single-TT hubs).
		 * @return TRUE, if the request succeeded, FALSE otherwise
		 *)
		 PROCEDURE ResetTT(port : LONGINT) : BOOLEAN;
		 BEGIN		 
			RETURN FALSE;
		 END ResetTT;
		 
		(*
		 * This hub class specific request stops the normal execution of the Transaction Translator (TT) so that the internal
		 * state can be retrieved via GetTTState. This request is provided for debugging purposes.
		 * @param port: If the hub supports multiple TTs, the port number of the TT that is being stopped must be specified (1 for single-TT hubs).
		 * @return TRUE, if request succeeded, FALSE otherwise
		 *)
		PROCEDURE StopTT(port : LONGINT) : BOOLEAN;
		BEGIN
			RETURN FALSE;
		END StopTT;
		
		(* 
		 * Perform initialization of USB hub device or root hub 
		 * @return TRUE, if initialization succeeded, FALSE otherwise
		 *)
		PROCEDURE Initialize() : BOOLEAN;
		BEGIN HALT(301); RETURN FALSE; END Initialize; (* abstract *)

	END HubInterface;

TYPE

	(* Integrated USB Hub Driver. *)
	HubDriver = OBJECT (HubInterface)
	VAR
	 	(* Associated USB hub device *)
	 	hub : AosUsb.UsbDevice;

		(* Information from hub descriptor *)
		nbrOfPorts : LONGINT;			(* Number of downstream ports *)
	 	pwrOn2pwrGood : LONGINT;	(* Power on to power good wait time [ms] *)
	 	powerSwitching : LONGINT;		(* Supported power switching modes (NotAvailable, Global or PerPort) *)	
	 	isCompound : BOOLEAN; 		(* Is this hub part of a compound device? *)
	 	ocProtection : LONGINT; 		(* Supported overcurrent protection (NotAvailable, Global or PerPort) *)
	 	thinkTime : LONGINT; 			(* 0..4 *)
	 	portIndicators : BOOLEAN; 		(* Is port indicator control support available? *)
	 	ctrlCurrent : LONGINT; 
	 	deviceRemovable : POINTER TO ARRAY OF BOOLEAN;
	 	
		timer : AosKernel.Timer;
				  		
		(* Enable power on the specified port (or on all ports if AllPorts is used as parameter) *)
		PROCEDURE EnablePortPower(port : LONGINT) : BOOLEAN;
		VAR i : LONGINT;
		BEGIN
			IF port = AllPorts THEN (* Only wait for power on to power good once *)
				IF Debug.Trace & Debug.traceHubRequests THEN Show("Enable power on all ports"); AosOut.Ln; END;		
				FOR i := 0 TO nbrOfPorts-1 DO
					IF ~SetPortFeature(PortPower, i, 0) THEN
						IF Debug.Level >= Debug.Errors THEN Show("Could not enable power on port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
						RETURN FALSE;
					END;
				END;
				Wait(pwrOn2pwrGood);			
				RETURN TRUE;	
			ELSE
				IF Debug.Trace & Debug.traceHubRequests THEN Show("Enable power on port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
				IF SetPortFeature(PortPower, port, 0) THEN
					Wait(pwrOn2pwrGood);
					RETURN TRUE;
				END;
			END;
			RETURN FALSE;				
		END EnablePortPower;
		
		(* Disable power on the specified port *)
		PROCEDURE DisablePortPower(port : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Disable power on port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
			RETURN ClearPortFeature(PortPower, port, 0);
		END DisablePortPower;

		(* Enable the specified port *)
		PROCEDURE ResetAndEnablePort(port :LONGINT) : BOOLEAN;
		VAR status : SET; timer : AosKernel.Timer;
		BEGIN
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Enable port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
			IF SetPortFeature(PortReset, port, 0) THEN (* Hub will enable port after reset *)
				NEW(timer); timer.Sleep(100);
				status := GetPortStatus(port, FALSE);
				IF status * AosUsbHcdi.PortStatusError # {} THEN
					IF Debug.Level >= Debug.Errors THEN Show("Cannot get port status after enabling."); AosOut.Ln; END;
					RETURN FALSE;
				ELSIF status * AosUsbHcdi.PortStatusReset # {} THEN
					IF Debug.Level >= Debug.Errors THEN Show("Port still in reset (after 50ms!)"); AosOut.Ln; END;
					RETURN FALSE;
				ELSIF status * AosUsbHcdi.PortStatusEnabled = {} THEN
					IF Debug.Level >= Debug.Errors  THEN Show("Could not enable port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
					RETURN FALSE;
				END;
			ELSE 
				RETURN FALSE;
			END;
			RETURN TRUE;
		END ResetAndEnablePort;
		
		(* Disable the specified port *)
		PROCEDURE DisablePort(port : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Disable port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
			RETURN ClearPortFeature(PortEnable, port, 0);
		END DisablePort;
		
		(* Selectively suspend the specified port *)
		PROCEDURE SuspendPort(port : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.Trace & (Debug.traceHubRequests OR Debug.traceSuspend) THEN Show("Suspend port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
			IF SetPortFeature(PortSuspend, port, 0) THEN
				hub.deviceAtPort[port].SetState(AosUsb.StateSuspended); 
				RETURN TRUE;
			ELSIF Debug.Level >= Debug.Errors THEN Show("Failed to suspend port"); AosOut.Int(port+1, 0); AosOut.Ln;
			END;
			RETURN FALSE;
		END SuspendPort;
		
		(* Resume a selectively suspended port *)
		PROCEDURE ResumePort(port : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.Trace & (Debug.traceHubRequests OR Debug.traceSuspend) THEN Show("Resume port "); AosOut.Int(port+1, 0); AosOut.Ln; END;			
			IF ClearPortFeature(PortSuspend, port, 0) THEN
				hub.deviceAtPort[port].SetState(AosUsb.StateConfigured); 
				RETURN TRUE;
			ELSIF Debug.Level >= Debug.Errors THEN Show("Failed to resume port "); AosOut.Int(port+1, 0); AosOut.Ln;
			END;
			RETURN FALSE;
		END ResumePort;
		
		(* Are there any device drivers associated to the specified device? *)
		PROCEDURE DriversInstalled(dev : AosUsb.UsbDevice) : BOOLEAN;
		VAR intf : AosUsb.InterfaceDescriptor; i : LONGINT;
		BEGIN (* locking? *)
			FOR i := 0 TO LEN(dev.actConfiguration.interfaces)-1 DO
				intf := dev.actConfiguration.interfaces[i] (AosUsb.InterfaceDescriptor);
				IF intf.driver # NIL THEN RETURN TRUE; END;
			END;
			RETURN FALSE;
		END DriversInstalled;

		(* If the hub supports port indicator control, set the port indcator to Automatic, Green, Amber or Off. *)
		PROCEDURE Indicate(port, ledstatus : LONGINT);
		BEGIN
			IF Debug.StrongChecks THEN 
				ASSERT((ledstatus = AosUsbHcdi.Automatic) OR (ledstatus =AosUsbHcdi. Green) OR (ledstatus = AosUsbHcdi.Amber) OR (ledstatus = AosUsbHcdi.Off)); 
			END;
			IF portIndicators THEN (* Port Indicator Control supported *)
				IF Debug.Trace & Debug.traceHubRequests THEN 
					Show("Set port indicator of port "); AosOut.Int(port+1, 0); AosOut.String(" to "); AosOut.Int(ledstatus, 0); AosOut.Ln;
				END;
				IF SetPortFeature(PortIndicator, port, ledstatus) THEN
				ELSIF Debug.Level >= Debug.Errors THEN Show("Could not control port indicator."); AosOut.Ln;
				END;
			END;
		END Indicate;
		
		(* How much current (mA) is available for this hub. *)
		PROCEDURE AvailableCurrent() : LONGINT;
		VAR hubstatus : SET; current : LONGINT;
		BEGIN
			IF GetHubStatus(hubstatus) THEN
				IF hubstatus * HsLocalPowerLost = {} THEN (* Hub is in self-powered mode *)
				ELSE
				END;
			ELSE
			END;
			RETURN current;
		END AvailableCurrent;
		
		(* Hub may report power source changes (self-powered vs. bus-powered) and overcurrent changes (if not reported per port). *)
		PROCEDURE HandleHubStatusChange;
		VAR hubstatus : SET; ignore : BOOLEAN;
		BEGIN
			IF Debug.Trace & Debug.traceConnects THEN Show("Handling hub status change."); AosOut.Ln; END;
			IF GetHubStatus(hubstatus) THEN
				IF hubstatus * HsLocalPowerLost # {} THEN
					IF Debug.Level >= Debug.Default THEN Show("Hub hast lost power supplier"); AosOut.Ln; END;
				END;
				IF hubstatus * HsOvercurrent # {} THEN
					IF Debug.Level >= Debug.Default THEN Show("Hub reports overcurrent condition"); AosOut.Ln END;
				END;
				(* Ackknowledge status changes *)
				IF hubstatus * HsLocalPowerSourceChange # {} THEN
					ignore := ClearHubFeature(HubLocalPowerChange);
				END;
				IF hubstatus * HsOvercurrentChange # {} THEN
					ignore := ClearHubFeature(HubOverCurrentChange);
				END;
			ELSIF Debug.Level >= Debug.Errors THEN Show("Hub status change but could not get hub status."); AosOut.Ln;
			END;			
		END HandleHubStatusChange;
		
		PROCEDURE LookForDevices;
		VAR i : LONGINT; trap : BOOLEAN;
		BEGIN
			IF nbrOfPorts > 0 THEN 
				FOR i := 0 TO nbrOfPorts-1 DO (* Check and handle status of all ports *)
					HandlePortStatusChange(i);
				END;
			END;
		FINALLY
			IF trap & (Debug.Level >= Debug.Warnings) THEN AosOut.String("AosUsbHubDriver: TRAP catched."); AosOut.Ln; END; 
		END LookForDevices;
		
		(* Remove device and its driver instance from the specified port *)
		PROCEDURE RemoveDeviceFromPort(port : LONGINT);
		BEGIN
			IF hub.deviceAtPort[port] # NIL THEN (* remove device and its driver instance from port *)
				hub.deviceAtPort[port].SetState(AosUsb.StateDisconnected);
				hub.deviceAtPort[port].Remove;
				hub.deviceAtPort[port] := NIL;
			END;
		END RemoveDeviceFromPort;
		
		(*	Poll the status of this hub and look for connect changes. If a connect change occured, i.e. a USB device
			has been attached or detached to/from a port, call FindNewDevice or remove the device dependent data structures *)
		PROCEDURE HandlePortStatusChange(port : LONGINT);
		CONST MaxPortStatusErrors = 10;
		VAR dev : AosUsb.UsbDevice; status : SET; i : LONGINT; res : BOOLEAN;
		BEGIN 
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Handling port status change for port "); AosOut.Int(port + 1, 0); AosOut.Ln; END;
			status := GetPortStatus(port, TRUE);				

			IF status * AosUsbHcdi.PortStatusError # {} THEN
				INC(hub.portErrors[port]);
				IF hub.portErrors[port] >= MaxPortStatusErrors THEN 
					IF Debug.Level >= Debug.Errors THEN Show("Error: Could not get status of port "); AosOut.Int(port + 1, 0); AosOut.Ln; END;
					RemoveDeviceFromPort(port);
					Indicate(port, AosUsbHcdi.Amber);
				END;
				RETURN;
			ELSE
				hub.portErrors[port] := 0;
			END;
			
			IF status * AosUsbHcdi.PortStatusOverCurrent # {} THEN
				IF Debug.Level >= Debug.Default THEN Show("Warning: Overcurrent detected on port "); AosOut.Int(port + 1, 0); AosOut.Ln; END;
			END;	
			
			IF status * AosUsbHcdi.PortStatusConnectChange # {} THEN (* Connection Status of port has changed *)
				
				IF status * AosUsbHcdi.PortStatusDevicePresent # {} THEN (* A device has been attached to this port *)

					IF Debug.Trace & Debug.traceConnects THEN Show("Looking at device at port "); AosOut.Int(port + 1, 0); AosOut.Ln; END;
					
					(* I've seen devices that disconnect under error conditions and then reconnect again. Therefore,
					we first check whether the USB system has already an attached device on the port *)
					IF hub.deviceAtPort[port] # NIL THEN
						IF Debug.Level >= Debug.Warnings THEN Show("Device already present. Remove it."); AosOut.Ln; END;
						RemoveDeviceFromPort(port);
					END;
					
					(* Note: PortStatusConnectChange is reset by GetPortStatus() *)
					IF  ~hub.portPermanentDisabled[port] THEN
						(* There mustn't be more than one enabled port with an unaddressed USB device
						connected to a single USB. Otherwise, multiple devices could respond to the default address 0 *)
						Wait(AosUsbHcdi.PortInsertionTime); (* >= 100ms, USBspec *)
						hub.controller.Acquire;
						res := ResetAndEnablePort(port);
						
						IF res THEN (* Try to connect to attached USB device *)
							i := 0; 
							LOOP
								dev := GetAddressedDevice(port);
								IF dev # NIL THEN (* Device found *) EXIT; END;
								IF Debug.Trace & Debug.traceConnects THEN Show("Retrying to connect device."); AosOut.Ln;END;
								res := ResetAndEnablePort(port);
								Wait(100 + i * 50); (* eventually the USB device reacts to slowly *)
								INC(i); 
								IF i >=4 THEN EXIT END;
							END;
	
							IF dev = NIL THEN (* ERROR: USB device attached but not found using GetAddressedDevice *)								
								res := DisablePort(port); (* ignore res *)
								hub.controller.Release;								
								status := GetPortStatus(port, FALSE);								
								IF status * AosUsbHcdi.PortStatusDevicePresent = {} THEN (* Bad timing... device is not present anymore *)
									Indicate(port, AosUsbHcdi.Off);
								ELSE (* There is a device attached but we can't handle it *)
									IF Debug.Level >= Debug.Default THEN 
										Show("Cannot access device. Permanently disabled port "); AosOut.Int(port+1, 0); 
										AosOut.String(". Replug connector of device!"); AosOut.Ln; 
									END;
									hub.portPermanentDisabled[port] := TRUE;
									Indicate(port, AosUsbHcdi.Amber); 
								END;
							ELSE (* New device found & addressed *)
								hub.controller.Release;	
								IF InquiryDevice(dev) THEN
									dev.Register(hub, port);
									IF Debug.Verbose THEN ShowDevice(DeviceAttached, port+1, dev); END;
									(* Try to install an appropriate USB device driver. If a driver is found, its Connect() procedure is called. *)
									AosUsb.drivers.ProbeDevice(dev); 
									IF ~DriversInstalled(dev) THEN 
										(* We don't have a driver for this device. Suspend it. *)
										(* res := SuspendPort(port); *)
									END;
									Indicate(port, AosUsbHcdi.Green);
								ELSE
									IF Debug.Level >= Debug.Default THEN Show("Failed to inquiry addressed device at port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
									IF ~DisablePort(port) THEN (* ignore res *) END;
									Indicate(port, AosUsbHcdi.Amber);
								END;
							END;					
						ELSE (* ERROR: Couldn't enable port  *)
							hub.controller.Release;							
							IF (hub.parent = hub) & hub.controller.isHighSpeed THEN
								(* Lowspeed or fullspeed device connected to highspeed controller root hub? *)
								status := GetPortStatus(port, FALSE);
								IF (status * AosUsbHcdi.PortStatusEnabled = {}) & (status * AosUsbHcdi.PortStatusDevicePresent # {}) THEN
								    	hub.controller.RoutePortToCompanion(port);
								END;
							ELSE	
								IF Debug.Level >= Debug.Default THEN Show("Could not enable port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
								hub.portPermanentDisabled[port] := TRUE;
								Indicate(port, AosUsbHcdi.Amber);
							END; 
						END;	
					ELSE
						IF Debug.Level >= Debug.Default THEN Show("Device connected to permanently disabled port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
					END;
				
				ELSE (* Device has been removed from port *)
					IF hub.deviceAtPort[port] # NIL THEN (* Remove device and its driver instance from port *)
						IF Debug.Verbose THEN ShowDevice(DeviceRemoved, port, hub.deviceAtPort[port]); END;
						RemoveDeviceFromPort(port);
					END;
					res := DisablePort(port); (* ignore res *)
					hub.portPermanentDisabled[port] := FALSE; (* Reset disabled status *) 
					hub.portErrors[port] := 0;
					Indicate(port, AosUsbHcdi.Off);
				END;
			END;
			
			(* sanity checks *)
			
			status := GetPortStatus(port, FALSE);
			IF status * AosUsbHcdi.PortStatusDevicePresent = {} THEN
				IF hub.deviceAtPort[port] # NIL THEN
					IF Debug.Level >= Debug.Warnings THEN Show("Port indicates no device present, but USB driver has one."); AosOut.Ln; END;
					RemoveDeviceFromPort(port);
					hub.portPermanentDisabled[port] := FALSE; (* Reset disabled status *) 					
				END;
			END;
				
			IF status * AosUsbHcdi.PortStatusEnabled # {} THEN (*Port is enabled -> a device should be connected to this port *)
				IF hub.deviceAtPort[port] = NIL THEN
					IF Debug.Level >= Debug.Warnings THEN Show("Port was enabled, but USB software did not know it!"); AosOut.Ln; END;
					RemoveDeviceFromPort(port);
					res := DisablePort(port);
					Indicate(port, AosUsbHcdi.Off);
				END; 
			END;
		END HandlePortStatusChange;
		
		(**	Traverses the bus topology towards the root hub starting at the device associated to the specified pipe. *)
		PROCEDURE GetTransactionTranslator(device : AosUsb.UsbDevice) : BOOLEAN;
		VAR dev : AosUsb.UsbDevice;
		BEGIN
			dev := device;
			IF dev.controller.isHighSpeed & (dev.speed # AosUsb.HighSpeed) THEN
				(* Low-/Fullspeed device connected to high-speed bus via high-speed hub device. Find the high-speed hub device. *)
				WHILE (dev.parent # NIL) & (dev.parent.speed # AosUsb.HighSpeed) DO dev := dev.parent; END;
				IF dev # NIL THEN
					device.ttAddress := dev.parent.address; device.ttPort := dev.port;
					IF Debug.Trace & Debug.traceConnects THEN
						Show("TT Address: "); AosOut.Int(device.ttAddress, 0); AosOut.String(", TT Port: "); AosOut.Int(device.ttPort, 0); AosOut.Ln;
					END;
					RETURN TRUE;
				ELSE
					IF Debug.Level >= Debug.Errors THEN Show("Could not find transaction translator."); AosOut.Ln; END;
					RETURN FALSE;
				END;
			ELSE
				device.ttAddress := 0; device.ttPort := 0;
				RETURN TRUE;
			END;
		END GetTransactionTranslator;
				
		(* 
		 * When entering this procedure, the USB device is already in the default state, i.e. it is attached and powered.
		 * This procedure will assign a USB device address to the device.
		 * @param port where the USB device is attached to
		 * @return USB device in addressed state
		 *)
		PROCEDURE GetAddressedDevice(port : LONGINT) : AosUsb.UsbDevice;
		VAR
			dev : AosUsb.UsbDevice; defaultpipe : AosUsbHcdi.Pipe;
			descriptor : AosUsb.DeviceDescriptor;
			adr : LONGINT;
			status : SET;
		BEGIN
			IF Debug.Trace & Debug.traceConnects THEN Show("Assign address to device at port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
			status := GetPortStatus(port, FALSE);
			IF status * AosUsbHcdi.PortStatusError # {} THEN 
				IF Debug.Level >= Debug.Errors THEN Show("GetAddressedDevice: Cannot get status of port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
				RETURN NIL;
			ELSIF status * AosUsbHcdi.PortStatusDevicePresent = {} THEN 
				IF Debug.Level >= Debug.Errors  THEN Show("GetAddressedDevice: Device no more present ??"); AosOut.Ln; END;
				RETURN NIL; 
			END; 
		
			(* Create a new USB device object*)
			NEW(dev);  NEW(descriptor);
			dev.descriptor := descriptor;
			dev.address := 0; (* Default address, since we did not yet assign an address to the device *)
			dev.controller := hub.controller;
			dev.parent := hub;
			dev.port := port;
			dev.SetState(AosUsb.StateDefault);
			
			IF status * AosUsbHcdi.PortStatusLowSpeed # {} THEN
				dev.speed := AosUsbHcdi.LowSpeed;
			ELSIF status * AosUsbHcdi.PortStatusFullSpeed # {} THEN
				dev.speed := AosUsbHcdi.FullSpeed;
			ELSIF status * AosUsbHcdi.PortStatusHighSpeed # {} THEN
				dev.speed := AosUsbHcdi.HighSpeed;
			ELSE
				IF Debug.Level >= Debug.Errors THEN Show("Device speed error"); AosOut.Ln; END;
				RETURN NIL;
			END;
			
			IF ~GetTransactionTranslator(dev) THEN
				RETURN NIL;
			END;
		
			(* We link the default control pipe of the device that we're installing to the dummy default control pipe provided by the controller *)
			defaultpipe := hub.controller.GetDefaultPipe(dev.speed, dev.ttPort, dev.ttAddress, dev);
			IF defaultpipe = NIL THEN
				IF Debug.Level >= Debug.Errors THEN Show("Couldn't get default pipe."); AosOut.Ln; END;
				RETURN NIL;
			END;
			
			(* Assign a USB device address to the device *)
			adr := hub.controller.GetFreeAddress();
			IF adr = 0 THEN (* Sorry, bus is full *) 
				AosOut.String("AosUsb: Cannot configure device:  No free device addresses. "); AosOut.Ln;
				dev.FreePipe(defaultpipe);
				RETURN NIL; 
			END; 
			
			dev.defaultpipe := defaultpipe;
			(* SetAddress will set dev.address as side-effect *)
			IF ~dev.SetAddress(adr) THEN 
				dev.FreePipe(dev.defaultpipe);
				hub.controller.FreeAll(adr); 
				hub.controller.FreeAddress(adr);
				IF Debug.Level >= Debug.Warnings THEN Show("Address Setup failed."); AosOut.Ln;END;
				RETURN NIL;
			END;
			
			(* Note that device is now in the "address" state. The SetAddress procedure has updated the dev.address field. *) 
			Wait(AosUsbHcdi.AddressRecoveryTime); (* 2ms recovery interval [USB2.0spec, p. 246]  *)
			dev.SetState(AosUsb.StateAddress);
			
			(* We don't need the dummy control pipe anymore... free it up... *)
			dev.FreePipe(dev.defaultpipe); 
			
			RETURN dev;
		END GetAddressedDevice;
		
		(* 
		 * When entering this procedure, the USB device is already in the addressed state, i.e. it is attached, powered and
		 * addressed. This procedure will read in all descriptors of the device and then configure the device, so when this procedure 
		 * is left, the device is in the state configured and can be used by USB device drivers.
		 * @param dev 
		 * @return TRUE, if operation succeeded, FALSE otherwise
		 *)
		PROCEDURE InquiryDevice(dev : AosUsb.UsbDevice) : BOOLEAN;
		VAR 
			defaultpipe, tempPipe : AosUsbHcdi.Pipe;
			buffer : AosUsbdi.BufferPtr;
		BEGIN
			(* Okay. we have to build the default control pipe from the device now... *)
			NEW(defaultpipe, dev.address, 0, dev.controller);
			dev.defaultpipe := defaultpipe;
			dev.defaultpipe.device := dev;
			dev.defaultpipe.completion.device := dev;
			dev.defaultpipe.address := dev.address;
			dev.defaultpipe.maxRetries := 3;
			dev.defaultpipe.type := AosUsbHcdi.PipeControl;
			dev.defaultpipe.maxPacketSize := 8; 	(* Not yet known *)
			dev.defaultpipe.speed := dev.speed;
			dev.defaultpipe.timeout := AosUsb.DefaultTimeout;
		
			IF GetTransactionTranslator(dev) THEN
				dev.defaultpipe.ttAddress := dev.ttAddress;
				dev.defaultpipe.ttPort := dev.ttPort;
			ELSE
				hub.controller.FreeAll(dev.address);
				hub.controller.FreeAddress(dev.address);
				RETURN FALSE;
			END;
			
			(* Register the default control pipe *)
			hub.controller.GetPipe(dev.address, 0, dev.defaultpipe);
			IF dev.defaultpipe = NIL THEN
				IF Debug.Level >= Debug.Errors THEN Show("InquiryDevice: Could not register the default control pipe"); AosOut.Ln; END;
				hub.controller.FreeAll(dev.address);
				hub.controller.FreeAddress(dev.address);
				RETURN FALSE;
			END;
					
			(* We are only allowed to read 8 bytes until now - otherwise there could happen a babble error *)
			NEW(buffer, 8);
			IF ~dev.GetDescriptor(DescriptorDevice, 0, 0, 8, buffer^) THEN
				IF Debug.Level >= Debug.Errors THEN Show("InquiryDevice: Read first 8 bytes of device descriptor failed."); AosOut.Ln; END;
				hub.controller.FreeAll(dev.address);
				hub.controller.FreeAddress(dev.address);
				RETURN FALSE;
			END;
			
			dev.defaultpipe.maxPacketSize := ORD(buffer[7]);
					
			(* We don't need the dummy control pipe anymore... free it up... *)
			tempPipe := dev.defaultpipe;
			dev.FreePipe(dev.defaultpipe); 
			tempPipe.device := dev; (* has been removed by FreePipe *)

			hub.controller.GetPipe(dev.address, 0, tempPipe);
	
			IF tempPipe = NIL THEN
				IF Debug.Level >= Debug.Errors THEN Show("InquiryDevice: Could not register the default control pipe"); AosOut.Ln; END;
				hub.controller.FreeAll(dev.address);
				hub.controller.FreeAddress(dev.address);
				RETURN FALSE;
			END;

			dev.defaultpipe := tempPipe;
			dev.defaultpipe.completion.device := dev;
						
			(* okay, device is in adressed state...  we now parse the device descriptor *)
			IF ~dev.GetDeviceDescriptor() OR ~dev.GetConfigurations()THEN
				hub.controller.FreeAll(dev.address); 
				hub.controller.FreeAddress(dev.address);
				IF Debug.Level >= Debug.Errors THEN Show("Parsing descriptors failed."); AosOut.Ln; END;	
				RETURN FALSE;
			END; 
			
			(* If the attached device is USB2.0 complaint, we also load and parse the Device Qualifier and
		 	the Other Speed Configurations *)
		 	IF dev.descriptor.bcdUSB >= 0200H THEN
		 		IF Debug.Trace & Debug.traceConnects THEN Show("Get device qualifier."); AosOut.Ln; END; 
		 		IF ~dev.GetDeviceQualifier() THEN
		 			IF Debug.Level >= Debug.Errors THEN Show("Couldn't get device qualifier."); AosOut.Ln; END;
		 		ELSIF dev.GetOtherSpeedConfigurations() THEN
		 			IF ~dev.controller.isHighSpeed THEN
		 				AosOut.String("AosUsbHubDriver: Warning: Connected high-speed capable device to low-/full-speed controller."); AosOut.Ln;
		 			END;
		 		ELSE
		 			IF Debug.Level >= Debug.Errors THEN Show("Couldn't get other speed configurations"); AosOut.Ln; END;
		 		END;
		 	END;
		 	
		 	(* Check whether topology constrains are met and enough power is available *)
		 	IF ~ValidTopology(dev, hub) THEN
				hub.controller.FreeAll(dev.address); 
				hub.controller.FreeAddress(dev.address);
				Show("Topology constraints violated. Cannot configure device."); AosOut.Ln;
				RETURN FALSE;
			END;
					 	
		 	IF ~EnoughPower(dev, hub) THEN 
				hub.controller.FreeAll(dev.address); 
				hub.controller.FreeAddress(dev.address);
				Show("Not enough power available. Cannot configure device."); AosOut.Ln;
				RETURN FALSE;
		 	END;
			
			(* Enough bandwidth available? *)
			
			(* Set Configuration *)
			IF ~dev.SetConfiguration(0) THEN
				hub.controller.FreeAll(dev.address); 
				hub.controller.FreeAddress(dev.address);
				IF Debug.Level >= Debug.Errors THEN Show("Could not set configuration"); AosOut.Ln; END;
				RETURN FALSE;
			END;
			dev.SetState(AosUsb.StateConfigured);
			
		(*	IF AllowSuspend THEN (* Enable remote wakeup if supported. *)
				IF ~dev.hubFlag & (dev.descriptor.bDeviceClass # 09H) & dev.actConfiguration(AosUsb.ConfigurationDescriptor).remoteWakeup THEN
					IF ~dev.SetFeature(Device, 0, AosUsb.FsDeviceRemoteWakeup) THEN
						IF Debug THEN Show("Warning: Could not enable remote wakeup."); END;
					END;  
				END;
			END; *)
						
			(* Get sManufacturer, sProduct and sSerialNumber strings & interface/configurations descriptors *)
			 AosUsb.GetStrings(dev); 
			 
			RETURN TRUE;
		END InquiryDevice;
		
		PROCEDURE ParseHubDescriptor(buffer : ARRAY OF CHAR) : BOOLEAN;
		VAR i : LONGINT;
		BEGIN
			IF (LEN(buffer) < 2) OR (ORD(buffer[0]) < 7) OR (ORD(buffer[1]) # DescriptorHub) THEN RETURN FALSE; END;
			nbrOfPorts := ORD(buffer[2]); 
			i := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, ORD(buffer[3])) * {0..1});
			CASE i OF
				0 : powerSwitching := Global; 
				|1 : powerSwitching := PerPort;
			ELSE
				powerSwitching := NotAvailable;
			END;

			IF SYSTEM.VAL(SET, ORD(buffer[3])) * {2} # {} THEN isCompound := TRUE; END;
			IF SYSTEM.VAL(SET, ORD(buffer[3])) * {7} # {} THEN portIndicators := TRUE; END;

			i := SYSTEM.VAL(LONGINT, SYSTEM.LSH(SYSTEM.VAL(SET, ORD(buffer[3])) * {3..4}, -3));
			CASE i OF
				0 : ocProtection := Global; 
				|1 : ocProtection := PerPort;
			ELSE
				ocProtection := NotAvailable;
			END;
		 	
		 	thinkTime := SYSTEM.VAL(LONGINT, SYSTEM.LSH(SYSTEM.VAL(SET, ORD(buffer[3])) * {3..4}, -3));
			pwrOn2pwrGood := ORD(buffer[5]) * 2; (* PowerOn 2 PowerGood measured in 2ms steps *)
		 	ctrlCurrent := ORD(buffer[6]);
		 	
		(* 	IF (ORD(buffer[2]) - 7) > (nbrOfPorts DIV 8 + 1) THEN
		 		NEW(deviceRemovable, nbrOfPorts);
		 		FOR i := 0 TO nbrOfPorts - 1 DO
			 		IF (SYSTEM.VAL(SET, ORD(buffer[7 + i DIV 8])) * SYSTEM.VAL(SET, i MOD 8) = {}) THEN 
			 			deviceRemovable[i] := TRUE; 
			 		END;
			 	END;
		 	END; *)
		 	RETURN TRUE;
		 END ParseHubDescriptor;
		 		
		(* Load and parse the hub descriptor, power on all ports *)
		PROCEDURE Connect*() : BOOLEAN;
		VAR buffer : AosUsbdi.BufferPtr; len : LONGINT;
		BEGIN
			hub := device (AosUsb.UsbDevice);
			
			(* First get the first 8 bytes of the hub descriptor to get its length and then load the full length hub desriptor *)
			NEW(buffer, 2);
			IF ~GetHubDescriptor(DescriptorHub, 0, 2, buffer^) THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbHubDriver: Could not get first two bytes of hub descriptor."); AosOut.Ln; END;
				RETURN FALSE; 
			END;
			
			len := ORD(buffer[0]); NEW(buffer, len);
		 	IF ~GetHubDescriptor(DescriptorHub, 0, SYSTEM.VAL(LONGINT, len), buffer^) THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbHubDriver: Could not get hub descriptor."); AosOut.Ln; END;
				RETURN FALSE; 
			END;
			
			IF ~ParseHubDescriptor(buffer^) THEN
				IF Debug.Level >= Debug.Errors THEN AosOut.String("AosUsbHubDriver: Failed to parse hub descriptor."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
		 	hub.hubFlag := TRUE; 
			hub.nbrOfPorts := nbrOfPorts;
			NEW(hub.deviceAtPort, nbrOfPorts);
			NEW(hub.portPermanentDisabled, nbrOfPorts);
			NEW(hub.portErrors, nbrOfPorts);
						
			IF Debug.Trace & Debug.traceInfo THEN ShowInfo; END;
			
			IF ~EnablePortPower(AllPorts) THEN
				IF Debug.Level >= Debug.Errors THEN Show("Error: Could not enable port power"); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			IF Debug.Verbose THEN Show(""); AosOut.Int(nbrOfPorts, 0); AosOut.String(" ports detected."); AosOut.Ln; END;
			RETURN Initialize();
		END Connect;
		
		PROCEDURE ValidTopology(dev, parent : AosUsb.UsbDevice) : BOOLEAN;
		VAR segments : LONGINT; temp : AosUsb.UsbDevice;
		BEGIN (* Should lock topology !! *)
			IF dev.hubFlag THEN 
				(* Count cable segments between dev and the host *)
				temp := dev;
				WHILE temp.parent # dev DO
					INC(segments);
					temp := temp.parent;
				END;
				(* No more than 6 cable segments allowed between device and host (USB2.0, p ??) *)
				IF segments > 6 THEN
					Show("Bus topology constraint not met: maximum of 6 cable segment between device and host."); AosOut.Ln;
					RETURN FALSE;
				END;
			END;
			RETURN TRUE;
		END ValidTopology;
		
		(* Can the hub parent provide enough power for the device dev ? *)
		PROCEDURE EnoughPower(dev, parent : AosUsb.UsbDevice) : BOOLEAN;		
		VAR status : SET;
		BEGIN
			IF dev.GetStatus(Device, 0, status) THEN
				(* TODO: Implement *)
				
				(* Unfortunately, most hubs claim to be self-powered even when it's not the case... *)
				IF status * AosUsb.SelfPowered # {} THEN
					IF Debug.Trace & Debug.traceConnects THEN Show(""); dev.ShowName; AosOut.String(" is self-powered."); AosOut.Ln; END;
				ELSE
					IF Debug.Trace & Debug.traceConnects THEN Show(""); dev.ShowName; AosOut.String(" is bus-powered."); AosOut.Ln; END;
				END;
			ELSE
				IF Debug.Level >= Debug.Errors THEN Show("GetStatus request failed."); AosOut.Ln; END;
			END;
			RETURN TRUE;
		END EnoughPower;
		
		PROCEDURE Disconnect;
		BEGIN
			IF Debug.Verbose THEN Show(" disconnected."); AosOut.Ln;END;
		END Disconnect;
		
		PROCEDURE Wait(ms : LONGINT);
		BEGIN {EXCLUSIVE}
			timer.Sleep(ms)
		END Wait;
		 
		PROCEDURE &New;
		BEGIN
			NEW(timer); (* Used by Wait *)
		END New;
		
		PROCEDURE ShowDevice(mode, port : LONGINT; dev : AosUsb.UsbDevice);
		BEGIN
			IF Debug.StrongChecks THEN ASSERT((dev # NIL) & ((mode = DeviceAttached) OR (mode = DeviceRemoved))); END;
			AosOut.String("AosUsbHubDriver: ");	dev.ShowName;
			IF mode = DeviceAttached THEN 
				AosOut.String(" attached to "); AosOut.String(hub.controller.name); AosOut.String(" port ");
				AosOut.Int(port, 0); AosOut.String("."); AosOut.Ln;			
			ELSE
				AosOut.String(" has been detached."); AosOut.Ln;
			END;
		END ShowDevice;
		
		PROCEDURE ShowInfo;
		VAR i : LONGINT;
		BEGIN
			IF Debug.Trace THEN
			Show(" Capabilities:"); AosOut.Ln;
			AosOut.String("    Compound device: "); IF isCompound THEN AosOut.String("Yes"); ELSE AosOut.String("No"); END;
			AosOut.String(", Port indicator control: "); IF portIndicators THEN AosOut.String("Yes"); ELSE AosOut.String("No"); END;
			AosOut.String(", Power switching support: ");
			IF powerSwitching = NotAvailable THEN AosOut.String("n/a"); 
			ELSIF powerSwitching = Global THEN AosOut.String("Global"); 
			ELSIF powerSwitching = PerPort THEN AosOut.String("Per port");
			ELSE AosOut.String("Error: "); AosOut.Int(powerSwitching, 0); 
			END;
			AosOut.String(", Overcurrent protection: ");
			IF ocProtection = NotAvailable THEN AosOut.String("n/a"); 
			ELSIF ocProtection = Global THEN AosOut.String("Global"); 
			ELSIF ocProtection = PerPort THEN AosOut.String("Per port");
			ELSE AosOut.String("Error: "); AosOut.Int(ocProtection, 0); 
			END;
			AosOut.Ln;
			AosOut.String("    Power On 2 Power Good: "); AosOut.Int(pwrOn2pwrGood, 0); AosOut.String(" ms");
			AosOut.String(", Control logic current: "); AosOut.Int(ctrlCurrent, 0); AosOut.String(" mA");
			AosOut.String(", Think time: "); AosOut.Int(thinkTime, 0); AosOut.String(" ms"); AosOut.Ln;
			AosOut.String("    Number of downstream ports: "); AosOut.Int(nbrOfPorts, 0); AosOut.Ln;
			FOR i := 0 TO nbrOfPorts-1 DO
				AosOut.String("        Port "); AosOut.Int(i, 0); AosOut.String(": ");
				IF (deviceRemovable # NIL) & deviceRemovable[i] THEN AosOut.String("[Removable]"); END;
				AosUsbHcdi.ShowPortStatus(GetPortStatus(i, FALSE));
				AosOut.Ln;				
			END;
			AosOut.Ln;			
			END;
		END ShowInfo;
		
		(* Displays message containing a description of this hub and the specified text to kernel log *)
		PROCEDURE Show(text : ARRAY OF CHAR);
		BEGIN
			AosOut.String("AosUsbHubDriver: Hub "); hub.ShowName;
			AosOut.String(" attached to "); AosOut.String(hub.controller.name); AosOut.String(" port ");
			AosOut.Int(hub.port + 1, 0); AosOut.String(": "); AosOut.String(text);
		END Show;

	END HubDriver;

TYPE
	
	(* Implementation of the USB hub device specific parts of the Hub Driver *)
	UsbHubDriver = OBJECT(HubDriver)
	VAR
		(* Hub device status pipe for status notifications *)
		statusPipe : AosUsbdi.Pipe;
		statusBuffer : AosUsbdi.BufferPtr;
		statusPipeRetries : LONGINT;
				
		(* This hub class specific request returns the hub descriptor. *)
		PROCEDURE GetHubDescriptor(type, index, length : LONGINT; VAR buffer : AosUsbdi.Buffer) : BOOLEAN;
		BEGIN
			ASSERT(length >= 2);
			RETURN (hub.defaultpipe.Request(ToHost + Class + Device, GetDescriptor, index + type*100H, 0, length, buffer) = AosUsbdi.Ok) &
					 (ORD(buffer[1]) = type);
		END GetHubDescriptor;
		
		(* This hub class specific request overrides the hub descriptor. *)
		 PROCEDURE SetHubDescriptor(type, index : LONGINT; buffer : AosUsbdi.Buffer) : BOOLEAN;
		 BEGIN
			ASSERT((LEN(buffer) >= 2) & (ORD(buffer[0]) = LEN(buffer)) & (ORD(buffer[1]) = type));
		 	RETURN hub.defaultpipe.Request(ToDevice + Class + Device, SetDescriptor, index + type*100H, 0, LEN(buffer), buffer) = AosUsbdi.Ok; 
		 END SetHubDescriptor;
		 
		(* This hub class request resets a value reported in the hub status. *)
		PROCEDURE ClearHubFeature(feature : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.StrongChecks THEN ASSERT((feature = HubLocalPowerChange) OR (feature = HubOverCurrentChange)); END; (* Valid feature selector *)
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Clear hub feature "); AosOut.Int(feature, 0); AosOut.Ln; END;
			RETURN hub.defaultpipe.Request(ToDevice + Class + Device, ClearFeature, feature, 0, 0, AosUsbdi.NoData) = AosUsbdi.Ok;
		END ClearHubFeature;
		
		(* This hub class request sets a value reported in the hub status. *)
		PROCEDURE SetHubFeature(feature : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.StrongChecks THEN ASSERT((feature = HubLocalPowerChange) OR (feature = HubOverCurrentChange)); END; (* Valid feature selector *)
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Set hub feature "); AosOut.Int(feature, 0); AosOut.Ln; END;
			RETURN hub.defaultpipe.Request(ToDevice + Class + Device, SetFeature, feature, 0, 0, AosUsbdi.NoData) = AosUsbdi.Ok;
		END SetHubFeature;		 	
		
		(* This hub class request resets a value reported in the port status. *)
		PROCEDURE ClearPortFeature(feature, port,  selector : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.StrongChecks THEN
				ASSERT(((feature # PortTest) & (feature # PortIndicator)) OR (selector = 0));
				ASSERT((feature > 0) & (feature <= 22) & (feature # PortConnection)); (* Valid feature selector *)
			END;
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Port "); AosOut.Int(port + 1, 0); AosOut.String(": Clear feature "); AosOut.Int(feature, 0); AosOut.Ln; END;
			RETURN hub.defaultpipe.Request(ToDevice + Class + Other, ClearFeature, feature, (port + 1) + SYSTEM.LSH(selector, 8), 0, AosUsbdi.NoData) = AosUsbdi.Ok;
		END ClearPortFeature;
		
		(* This hub class request sets a value reported in the hub status. *)
		PROCEDURE SetPortFeature(feature, port, selector : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.StrongChecks THEN
				ASSERT(((feature = PortTest) OR (feature = PortIndicator)) OR (selector = 0));
				ASSERT((feature > 0) & (feature <= 22) & (feature # PortConnection)); (* Valid feature selector *)
			END;
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Port "); AosOut.Int(port + 1, 0); AosOut.String(": Set feature "); AosOut.Int(feature, 0); AosOut.Ln; END;
			RETURN hub.defaultpipe.Request(ToDevice + Class + Other, SetFeature, feature, (port + 1) + SYSTEM.LSH(selector, 8), 0, AosUsbdi.NoData) = AosUsbdi.Ok;
		END SetPortFeature;
		
		(* This hub class request returns the current hub status and the states that have change since the previous acknowledgment. *)
		PROCEDURE GetHubStatus(VAR hubstatus : SET) : BOOLEAN;
		VAR buffer : AosUsbdi.BufferPtr;
		BEGIN
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Get Hub Status."); AosOut.Ln; END;
			NEW(buffer, 4);
			IF hub.defaultpipe.Request(ToHost + Class + Device, GetStatus, 0, 0, 4, buffer^) = AosUsbdi.Ok THEN
				hubstatus := SYSTEM.VAL(SET, SYSTEM.GET32(SYSTEM.ADR(buffer[0])));
				RETURN TRUE;
			END;
			RETURN FALSE;
		END GetHubStatus;
		
		(* This hub class request returns the current port status and the current value of the port status change bits.  *)
		PROCEDURE GetPortStatus(port : LONGINT; ack : BOOLEAN) : SET;
		VAR buffer : AosUsbdi.BufferPtr; s, portstatus : SET;
		BEGIN
			IF Debug.StrongChecks THEN ASSERT(port >= 0); END;
			IF Debug.Trace & Debug.traceHubRequests THEN 
				Show("Get port status of port "); AosOut.Int(port + 1, 0); IF ack THEN AosOut.String(" (ACK)"); END; AosOut.Ln;
			END;
			NEW(buffer, 4);
			IF hub.defaultpipe.Request(ToHost + Class + Other, GetStatus, 0, port+1, 4, buffer^) = AosUsbdi.Ok THEN
				s := SYSTEM.VAL(SET, SYSTEM.GET32(SYSTEM.ADR(buffer[0])));		
					
				IF ack & (s * PsChangeMask # {}) THEN (* Acknowledge the changes *)
					IF s * PsConnectStatusChange # {} THEN 
						IF ~ClearPortFeature(PortConnectionChange, port, 0) THEN 	
							RETURN AosUsbHcdi.PortStatusError; 
						END;
					END;
					IF s * PsPortEnabledChange # {} THEN 
						IF ~ClearPortFeature(PortEnableChange, port, 0) THEN 
							RETURN AosUsbHcdi.PortStatusError; 
						END;
					END;
					IF s * PsSuspendChange # {} THEN 
						IF ~ClearPortFeature(PortSuspendChange, port, 0) THEN 
							RETURN AosUsbHcdi.PortStatusError; 
						END;
					END;
					IF s * PsOvercurrentChange # {} THEN 
						IF ~ClearPortFeature(PortOverCurrentChange, port, 0) THEN 
							RETURN AosUsbHcdi.PortStatusError; 
						END;
					END;
					IF s * PsResetChange # {} THEN 
						IF ~ClearPortFeature(PortResetChange, port, 0) THEN 
							RETURN AosUsbHcdi.PortStatusError; 
						END;
					END;
				END;		
			
				IF s * PsCurrentConnectStatus # {} THEN
					portstatus := portstatus + AosUsbHcdi.PortStatusDevicePresent;
					IF s * PsPortEnabled # {} THEN
						portstatus := portstatus + AosUsbHcdi.PortStatusEnabled; 
						IF s * PsLowSpeed # {} THEN
							portstatus := portstatus + AosUsbHcdi.PortStatusLowSpeed;
						ELSIF s * PsHighSpeed # {} THEN
							portstatus := portstatus + AosUsbHcdi.PortStatusHighSpeed;
						ELSE
							portstatus := portstatus + AosUsbHcdi.PortStatusFullSpeed;
						END;
					END;
				END;
				
				IF s * PsSuspend # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusSuspended; END;
				IF s * PsOverCurrent # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusOverCurrent; END;
				IF s * PsReset # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusReset; END;
				IF s * PsPortPower # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusPowered; END;
				IF s * PsPortTestMode # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusTestControl; END;
				IF s * PsPortIndicators # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusIndicatorControl; END;
				IF s * PsConnectStatusChange # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusConnectChange; END;
				IF s * PsPortEnabledChange # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusEnabledChange; END;
				IF s * PsSuspendChange # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusSuspendChange; END;
				IF s * PsOvercurrentChange # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusOverCurrentChange; END;
				IF s * PsResetChange # {} THEN portstatus := portstatus + AosUsbHcdi.PortStatusResetChange; END;
				IF Debug.Trace & Debug.traceHubRequests THEN 
					Show("Status of port "); AosOut.Int(port + 1, 0); AosUsbHcdi.ShowPortStatus(portstatus); AosOut.Ln;
				END;
				RETURN portstatus;
			ELSE
				IF Debug.Level >= Debug.Errors THEN Show("Can't get port status of port "); AosOut.Int(port+1, 0); AosOut.Ln; END;
				RETURN AosUsbHcdi.PortStatusError; 
			END;
		END GetPortStatus;
		
		(*
		 * This handler is called when the hub's interrupt IN status pipe reports a change of either
		 * the hub status or the status of a hub port.
		 *)
		PROCEDURE HandleStatusChange(status : AosUsbdi.Status; actLen : LONGINT);
		VAR ignore : AosUsbdi.Status; i, port : LONGINT;
		BEGIN
			IF Debug.Trace & Debug.traceConnects THEN 
				Show("Hub reports status change: "); FOR i := 0 TO LEN(statusBuffer)-1 DO AosOut.Hex(ORD(statusBuffer[i]), -2); END; AosOut.Ln; 
			END;
			IF (status = AosUsbdi.Ok) OR ((status = AosUsbdi.ShortPacket) & (actLen > 0)) THEN
				IF SYSTEM.VAL(SET, statusBuffer[0]) * {0} # {} THEN (* Hub status changed *)
					IF Debug.Trace & Debug.traceConnects THEN Show("Hub status changed."); END;
					statusBuffer[0] := SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, statusBuffer[0]) - {0}); (* Clear hub status change bit *)
					HandleHubStatusChange;
				END;
				(* Look for port status changes *)
				FOR i := 0 TO actLen-1 DO
					FOR port := 0 TO 7 DO
						IF SYSTEM.VAL(SET, statusBuffer[i]) * {port} # {} THEN
							HandlePortStatusChange(port + i * 8 - 1);
						END;
					END;
				END;
				ignore := statusPipe.Transfer(statusPipe.maxPacketSize, 0, statusBuffer^); 
				statusPipeRetries := 0;
			ELSE
				IF statusPipeRetries > StatusPipeMaxRetries THEN
					IF Debug.Level >= Debug.Errors THEN Show("Status pipe error "); AosUsbHcdi.ShowStatus(status); AosOut.Ln; END;
					RETURN; (* give up *)
				END;
				IF (status = AosUsbdi.Stalled) THEN
					IF ~statusPipe.ClearHalt() THEN
						IF Debug.Level >= Debug.Errors THEN Show("Could not recover from status pipe error."); AosOut.Ln; END;
						RETURN;
					END;
				ELSIF (status = AosUsbdi.Disconnected) THEN
					RETURN;
				END;
				ignore := statusPipe.Transfer(statusPipe.maxPacketSize, 0, statusBuffer^);
				INC(statusPipeRetries);
			END;
		END HandleStatusChange;
		
		(* USB hub device specific initialization *)
		PROCEDURE Initialize() : BOOLEAN;
		VAR endpoint : AosUsbdi.EndpointDescriptor; ignore : AosUsbdi.Status;
		BEGIN
			(* Look for the hub's interrupt endpoint which is used to communicate status changes *)
			endpoint := hub.actConfiguration.interfaces[0].endpoints[0];  
			ASSERT(endpoint.type = AosUsbdi.InterruptIn);
			statusPipe := hub.GetPipe(endpoint.bEndpointAddress); 
			IF statusPipe = NIL THEN
				IF Debug.Level >= Debug.Errors THEN Show("Could not establish status pipe."); AosOut.Ln; END;
				RETURN FALSE;
			END;	
			
			NEW(statusBuffer, statusPipe.maxPacketSize);
			statusPipe.SetTimeout(0); (* Non-blocking pipe *)
			statusPipe.SetCompletionHandler(HandleStatusChange); 
			ignore := statusPipe.Transfer(statusPipe.maxPacketSize, 0, statusBuffer^); 
						
			RETURN TRUE;
		END Initialize;
		
		(*
		 * This hub class specific request clears the state of the Transaction Translator (TT) bulk/control transfer after
		 * it has been left in a busy state due to high-speed errors. This request is only defined for non-periodic endpoints.
		 *)
		PROCEDURE ClearTTBuffer(dev : AosUsb.UsbDevice; endpoint, port : LONGINT) : BOOLEAN;
		VAR intf : AosUsb.InterfaceDescriptor; endp : AosUsb.EndpointDescriptor; wValue : SET; i, e : LONGINT; 
		BEGIN 
			IF Debug.StrongChecks THEN ASSERT((dev.speed # AosUsb.HighSpeed) & (dev.parent.speed = AosUsb.HighSpeed)); END;
			(* Get the endpoint *)
			LOOP (* Search all interfaces *)
				IF i > dev.actConfiguration.bNumInterfaces-1 THEN EXIT END;
				intf := dev.actConfiguration.interfaces[i] (AosUsb.InterfaceDescriptor);
				FOR e := 0 TO LEN(intf.endpoints)-1 DO (* Search all endpoints *)
					IF intf.endpoints[e].bEndpointAddress = endpoint THEN (* Endpoint found *)
						endp := intf.endpoints[e] (AosUsb.EndpointDescriptor);
					END;
				END;
				IF endp # NIL THEN EXIT END;	
				INC(i);
			END;
			IF endp = NIL THEN (* Endpoint not found *) RETURN FALSE END;
			IF (endp.bmAttributes * {0,1} # {}) OR (endp.bmAttributes * {0,1} # {1}) THEN 
				IF Debug.Level >= Debug.Warnings THEN Show("ClearTTBuffer error: Only allowed for non-periodic endpoints"); AosOut.Ln; END;
				RETURN FALSE;
			END;
			(* wValue: {0..3}: Endpoint Number, {4..10}: Device Address, {11..12}: Endpoint Type, {13..13}: Reserved, {15}: Endpoint Direction *)
			wValue := SYSTEM.VAL(SET, endp.bEndpointAddress) * {0..3} + SYSTEM.LSH(SYSTEM.VAL(SET, dev.address), 4) * {4..10};
			wValue := wValue + SYSTEM.LSH(endp.bmAttributes ,11) * {11..12} + SYSTEM.LSH(SYSTEM.VAL(SET, endp.bEndpointAddress) * {7}, 8);
			RETURN hub.defaultpipe.Request(ToDevice + Class + Other, ClearTtBuffer, SYSTEM.VAL(LONGINT, wValue), (port + 1), 0, AosUsbdi.NoData) = AosUsbdi.Ok;
		END ClearTTBuffer;
		
		(*
		 * This hub class specific request returns the internal state of the Transaction Translator (TT) in a vendor specific format.
		 * A TT receiving this request must have first been stopped using the StopTTRequest.
		 *)
		PROCEDURE GetTTState(flags, port, len : LONGINT; VAR buffer : AosUsbdi.Buffer) : BOOLEAN;
		BEGIN
			RETURN hub.defaultpipe.Request(ToDevice + Class + Other, GetTtState, flags, (port + 1), len, buffer) = AosUsbdi.Ok;
		END GetTTState;
		
		(*
		 * This hub class specific request returns the Transaction Translator (TT) in a hub to a known state.
		 * After the reset is completed, the TT can resume its normal operation.
		 *)
		 PROCEDURE ResetTT(port : LONGINT) : BOOLEAN;
		 BEGIN		 
		 	RETURN hub.defaultpipe.Request(ToDevice + Class + Other, ResetTt, 0, (port + 1), 0, AosUsbdi.NoData) = AosUsbdi.Ok;
		 END ResetTT;
		 
		(*
		 * This hub class specific request stops the normal execution of the Transaction Translator (TT) so that the internal
		 * state can be retrieved via GetTTState. This request is provided for debugging purposes.
		 *)
		PROCEDURE StopTT(port : LONGINT) : BOOLEAN;
		BEGIN
			RETURN hub.defaultpipe.Request(ToDevice + Class + Other, StopTt, 0, (port + 1), 0, AosUsbdi.NoData) = AosUsbdi.Ok;
		END StopTT;
		  			
	END UsbHubDriver;

TYPE	
	
	(* Implementation of the USB root hub specific parts of the Hub Driver *)
	RootHubDriver = OBJECT (HubDriver)
	VAR
		(* Root hub management *)
		next: RootHubDriver;
		
		(* Active object handling *)
		timerRH : AosKernel.Timer;
		alive, dead, statusChange : BOOLEAN;
		pollingInterval : LONGINT; 
		
		(* Will be true when Connect() returns. Used to synchronize active body *)
		initialized : BOOLEAN;

		(* Get the emulated hub descriptor. Ignore type and index parameters. *)
		PROCEDURE GetHubDescriptor(type, index, length : LONGINT;  VAR buffer : AosUsbdi.Buffer) : BOOLEAN;
		VAR i : LONGINT; hd : AosUsbHcdi.HubDescriptor;
		BEGIN
			IF Debug.StrongChecks THEN ASSERT(LEN(buffer) <= length); END;
			hd := device(AosUsb.UsbDevice).controller.GetHubDescriptor();
			IF hd = NIL THEN RETURN FALSE END;
			IF length > LEN(hd) THEN length := LEN(hd); END;
			FOR i := 0 TO length-1 DO buffer[i] := hd[i]; END;
			RETURN TRUE;
		END GetHubDescriptor;
		
		(* Overwrites the emulated hub descriptor. Ignore type and index paramters. *)
		 PROCEDURE SetHubDescriptor(type, index : LONGINT; buffer : AosUsbdi.Buffer) : BOOLEAN;
		 VAR i : LONGINT; hd : AosUsbHcdi.HubDescriptor;
		 BEGIN
		 	IF Debug.StrongChecks THEN ASSERT((LEN(buffer)>=8) & (ORD(buffer[0])=LEN(buffer)) & (ORD(buffer[1])=type)); END;
		 	NEW(hd, LEN(buffer));
		 	FOR i := 0 TO LEN(buffer)-1 DO hd[i] := buffer[i]; END;
		 	device(AosUsb.UsbDevice).controller.SetHubDescriptor(hd);
		 	RETURN TRUE;
		 END SetHubDescriptor;
		 
		(* Clear a root hub feature. *)
		PROCEDURE ClearHubFeature(feature : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.StrongChecks THEN ASSERT((feature = HubLocalPowerChange) OR (feature = HubOverCurrentChange)); END; (* Valid feature selector *)
			(* TODO: Do nothing? *)
			RETURN TRUE;
		END ClearHubFeature;
		
		(* Set a root hub feature *)
		PROCEDURE SetHubFeature(feature : LONGINT) : BOOLEAN;
		BEGIN
			IF Debug.StrongChecks THEN ASSERT((feature = HubLocalPowerChange) OR (feature = HubOverCurrentChange)); END; (* Valid feature selector *)
			(* TODO: Do nothing? *)
			RETURN TRUE;
		END SetHubFeature;		 	
		
		(* Clear a root hub port feature. *)
		PROCEDURE ClearPortFeature(feature, port, selector : LONGINT) : BOOLEAN;
		VAR res : BOOLEAN;
		BEGIN
			IF Debug.StrongChecks THEN 
				ASSERT((port >= 0) & (port < nbrOfPorts)); 
				ASSERT(((feature # PortTest) & (feature # PortIndicator)) OR (selector = 0));
				ASSERT((feature > 0) & (feature <= 22) & (feature # PortConnection)); (* Valid feature selector *)
			END;
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Port "); AosOut.Int(port + 1, 0); AosOut.String(": Clear feature "); AosOut.Int(feature, 0); AosOut.Ln; END;
			CASE feature OF
				PortEnable : hub.controller.DisablePort(port); res := TRUE;
				| PortSuspend : res := hub.controller.ResumePort(port);
				| PortPower: hub.controller.DisablePortPower(port); res := TRUE;
				| PortIndicator: hub.controller.IndicatePort(port, selector); res := TRUE;
				| PortConnectionChange:
				| PortResetChange:
				| PortEnableChange:
				| PortSuspendChange:
				| PortOverCurrentChange:
			ELSE
				IF Debug.Level >= Debug.Warnings THEN Show("Clearing of Feature "); AosOut.Int(feature, 0); AosOut.String(" not supported"); AosOut.Ln; END;
			END;
			RETURN res;
		END ClearPortFeature;
		
		(* Set a root hub port feature *)
		PROCEDURE SetPortFeature(feature, port, selector : LONGINT) : BOOLEAN;
		VAR res : BOOLEAN;
		BEGIN
			IF Debug.StrongChecks THEN 
				ASSERT((port >= 0) & (port < nbrOfPorts)); 
				ASSERT(((feature = PortTest) OR (feature = PortIndicator)) OR (selector = 0));
				ASSERT((feature > 0) & (feature <= 22) & (feature # PortConnection)); (* Valid feature selector *)
			END;
			IF Debug.Trace & Debug.traceHubRequests THEN Show("Port "); AosOut.Int(port + 1, 0); AosOut.String(": Set feature "); AosOut.Int(feature, 0); AosOut.Ln; END;
			CASE feature OF
				PortEnable : res := hub.controller.ResetAndEnablePort(port);
				| PortSuspend : res := hub.controller.SuspendPort(port);
				| PortPower: hub.controller.EnablePortPower(port); res := TRUE;
				| PortReset: res := hub.controller.ResetAndEnablePort(port);
				| PortTest:
				| PortIndicator: hub.controller.IndicatePort(port, selector); res := TRUE;
				| PortConnectionChange:
				| PortResetChange:
				| PortEnableChange:
				| PortSuspendChange:
				| PortOverCurrentChange:
			ELSE
				IF Debug.Level >= Debug.Warnings THEN Show("Request not supported"); AosOut.Ln; END;
			END;
			RETURN res;
		END SetPortFeature;

		(* Return the root hubs status. Reported: Local power supply good & Overcurrent *)
		PROCEDURE GetHubStatus(VAR hubstatus : SET) : BOOLEAN;
		BEGIN
			(* HsLocalPowerLost and HsLocalPowerSourceChange are never set since root hubs cannot not loose power *)
			hubstatus := {};
			(* TODO: report global overcurrent here *)
			RETURN TRUE;
		END GetHubStatus;
		
		(* Get the status of the specifed root hub port. Note that the HCD is responsible for acknowledging changes. *)
		PROCEDURE GetPortStatus(port : LONGINT; ack : BOOLEAN) : SET;
		BEGIN
			IF Debug.StrongChecks THEN ASSERT((port >= 0) & (port < nbrOfPorts)); END;
			RETURN hub.controller.GetPortStatus(port, ack);
		END GetPortStatus;
		
		(* Root hubs that support interrupt notification for port status changes will call this
		handler when a corresponding interrupt occurs. The parameters are ignored. *)
		PROCEDURE HandleStatusChange*(status : AosUsbdi.Status; actLen : LONGINT);
		BEGIN {EXCLUSIVE}
			statusChange := TRUE;
		END HandleStatusChange;
		
		(* How much current (mA) is available for this hub? *)
		PROCEDURE AvailableCurrent() : LONGINT;
		BEGIN
			RETURN 500; (* High power port delivers 500mA *)
		END AvailableCurrent;
		
		(* Active object control *)
		PROCEDURE Terminate; BEGIN {EXCLUSIVE} alive:=FALSE; timerRH.Wakeup; END Terminate; 
		PROCEDURE SetDead; BEGIN {EXCLUSIVE} dead := TRUE; END SetDead;
		PROCEDURE AwaitDead;	BEGIN {EXCLUSIVE} AWAIT(dead); END AwaitDead;
		
		(* Root hub specific initialization *)
		PROCEDURE Initialize() : BOOLEAN;
		BEGIN
			IF hub.controller.SetStatusChangeHandler(HandleStatusChange) THEN
				(* Root hub driver will be wake up via interrupt notification *)
				pollingInterval := 0; 
			END;
			BEGIN {EXCLUSIVE} initialized := TRUE; END;
			RETURN TRUE;
		END Initialize;
		
		(* Displays message containing a description of this hub and the specified text to kernel log *)
		PROCEDURE Show(text : ARRAY OF CHAR);
		BEGIN
			AosOut.String("AosUsbHubDriver: Root Hub "); hub.ShowName; AosOut.String(": "); AosOut.String(text);
		END Show;
		
		PROCEDURE Disconnect*;
		BEGIN
			Terminate; AwaitDead;
			IF Debug.Verbose THEN Show("Disconnected."); AosOut.Ln; END;
		END Disconnect;
		
		PROCEDURE &New;
		BEGIN
			New^; NEW(timerRH); 
			alive := TRUE; dead := FALSE; initialized := FALSE;
			pollingInterval := PollingInterval;
		END New;
 
		BEGIN {ACTIVE}	
			(* Root hubs use a different way to communicate root hub port status changes. Either, they cannot 			*)
			(* report there changes at all and must be polled (e.g. UHCI host controllers), or they use interrupt driven	*)
			(* global status change notification (e.g. OHCI and EHCI host controllers). 									*)
			BEGIN {EXCLUSIVE} AWAIT(initialized OR ~alive); END;
			WHILE alive DO
				(* The first time we poll the bus (force bus enumeration) *)
				LookForDevices;
				IF pollingInterval = 0 THEN (* Use interrupt handler port status change notification *)
					BEGIN {EXCLUSIVE}
						AWAIT((alive = FALSE) OR (statusChange = TRUE));
						statusChange := FALSE;
					END;
				ELSE (* Use polling *)
					timerRH.Sleep(pollingInterval);
				END;
			END;
			SetDead;			
		END RootHubDriver;

VAR
	(* This is a linked list of all running root hub drivers. It's only used by the module termination handler. *)
	rootHubs : RootHubDriver;

(* This is the Probe procedure of the internal USB hub driver / root hub driver. *)
PROCEDURE Probe(dev : AosUsbdi.UsbDevice; id : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR hubDriver : UsbHubDriver; rootHubDriver : RootHubDriver;
BEGIN
	IF dev.descriptor.bNumConfigurations # 1 THEN RETURN NIL; END;
	IF dev.configurations[0].bNumInterfaces # 1 THEN RETURN NIL; END;

	IF id.bInterfaceClass # 9 THEN RETURN NIL; END;
	IF id.bInterfaceSubClass # 0 THEN RETURN NIL; END;
	IF id.bNumEndpoints # 1 THEN RETURN NIL; END;
	
	IF dev(AosUsb.UsbDevice).parent = dev THEN (* It's a root hub *)
		NEW(rootHubDriver);
		(* Insert at head of root hub driver linked list *)
		rootHubDriver.next := rootHubs; rootHubs := rootHubDriver;
		RETURN rootHubDriver;
	ELSE (* It's a hub device attached to the bus *)
		NEW(hubDriver);
		RETURN hubDriver;
	END;
END Probe; 

PROCEDURE Cleanup;
VAR rh : RootHubDriver;
BEGIN
	rh := rootHubs;
	WHILE(rh # NIL) DO
		IF Debug.Verbose THEN rh.Show("Shutting down... "); AosOut.Ln; END;
		rh.Terminate; rh.AwaitDead;
		rh := rh.next;
	END;
	AosUsbdi.drivers.Remove(Name);
	IF Debug.Verbose THEN AosOut.Enter; AosOut.String("AosUsbHubDriver: Removed hub driver."); AosOut.Exit; END;
END Cleanup;

(** Install the USB Hub Driver *)
PROCEDURE Install*(ptr : PTR) : PTR;
BEGIN
	RETURN NIL;
END Install;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	AosUsbdi.drivers.Add(Probe, Name, Description, 10);
END AosUsbHubDriver.

AosUsbHubDriver.Install ~  S.Free AosUsbHubDriver ~