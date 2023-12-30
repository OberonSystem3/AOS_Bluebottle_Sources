MODULE AosUsbHid; (** AUTHOR: "staubesv"; PURPOSE: "HID device class specific requests"; *)
(**
 * Base class for HID class driver.
 * Implements the HID class-specific requests and parsing of the HID descriptor.
 *
 * References:
 *	Device Class Definition for Human Interface Devices (HID), version 1.11, 27.06.2001, www.usb.org
 *
 * History:
 *
 *	20.11.2005	First Release (staubesv)
 *	09.01.2006	Adapted to AosUsb.Mod changes (staubesv)
 *	05.07.2006	Adapted to AosUsbdi (staubesv)
 *	23.11.2006	Removed interfaceNumber parameter, added GetHidDescriptor, cleanup (staubesv)
 *)
 
IMPORT AosOut, AosUsbdi;

CONST 

	(** HID Descriptors Types *)
	DescriptorHID* = 21H;
	DescriptorReport* = 22H;
	DescriptorPhysical* = 23H;	

	(** HID Report Types *)
	ReportInput* =  01H; 
	ReportOutput* = 02H;
	ReportFeature* = 03H;	

	(** HID Protocol Types *)
	BootProtocol* = 0;
	ReportProtocol* = 1;	
		
	(* USB HID Class Specific Request Codes, HID p. 51 *)
	HrGetReport = 01H;
	HrGetIdle = 02H;
	HrGetProtocol = 03H;
	HrSetReport = 09H;
	HrSetIdle = 0AH;
	HrSetProtocol = 0BH;
	SrGetDescriptor = 6;
	
	HidSetRequest = AosUsbdi.ToDevice + AosUsbdi.Class + AosUsbdi.Interface;
	HidGetRequest = AosUsbdi.ToHost + AosUsbdi.Class + AosUsbdi.Interface;
	
TYPE
	
	(* HID descriptor according to the Device Class Definition for HID, p. 22 *)
	HidDescriptor* = POINTER TO RECORD
		bLength- : LONGINT;				
		bDescriptorType- : LONGINT;	   
		bcdHID- : LONGINT;					 
		bCountryCode- : LONGINT;		  
		bNumDescriptors- : LONGINT;	 
		bClassDescriptorType- : LONGINT;	   
		wDescriptorLength- : LONGINT;
		optionalDescriptors- : POINTER TO ARRAY OF OptionalDescriptor;   
	END;

	OptionalDescriptor* = RECORD
		bDescriptorType- : LONGINT;	   
		wDescriptorLength- : LONGINT;   
	END;
	
TYPE

	(* Base class of HID device drivers. Provides the HID class specific requests. *)
	HidDriver* = OBJECT(AosUsbdi.Driver)

		(** HID class specific device requests *)

		(** 
		 * The SetIdle request silinces a particular report on the Interrupt In pipe until a new event occurs or 
		 * the specified amount of time passes (HID, p.52)
		 * @param interface Related USB device interface	
		 * @param duration: 0: infinite, 1-255: value * 4ms
		 * @reportId 0: idle rate applies to all reports, otherwise it applies only to reports with the corresponding reportId
		 * @return TRUE, if requests succeeds, FALSE otherwise
		 *)
		PROCEDURE SetIdle*(reportId, duration : LONGINT) : BOOLEAN;
		BEGIN
			ASSERT(interface.bInterfaceClass = 3H);
			RETURN device.Request(HidSetRequest, HrSetIdle, reportId + duration*100H, interface.bInterfaceNumber, 0, AosUsbdi.NoData) = AosUsbdi.Ok;
		END SetIdle;
		
		(** 
		 * The GetIdle request reads the current idle rate for a particular input report. See HID p. 52 
		 * @param interface Related USB device interface
		 * @param reportId 
		 * @param idle Idle rate; 0: infinite duration, otherwise: idle rate in milliseconds; Only valid then request succeeded!
		 * @return TRUE, if request succeeded, FALSE otherwise
		 *)
		PROCEDURE GetIdle*(reportId : LONGINT; VAR idle : LONGINT) : BOOLEAN;
		VAR buffer : AosUsbdi.BufferPtr;
		BEGIN
			ASSERT(interface.bInterfaceClass = 3H);
			NEW(buffer, 1);
			IF device.Request(HidGetRequest, HrGetIdle, reportId, interface.bInterfaceNumber, 1, buffer^) = AosUsbdi.Ok THEN
				idle := 4*ORD(buffer[0]); 
				RETURN TRUE;
			END;
			RETURN FALSE;
		END GetIdle;
		
		(** 
		 * The SetProtocol request switches between the boot protocol and the report protocol (HID p. 54).
		 * This request is only supported by devices in the boot subclass. Default is the Report Protocol.
		 * @param interface the request should be applied to
		 * @param protocol 0: Boot Protocol, 1: Report Protocol
		 * @return TRUE, if request succeeded, FALSE otherwise
		 *)
		PROCEDURE SetProtocol*(protocol : LONGINT) : BOOLEAN;
		BEGIN
			ASSERT(interface.bInterfaceClass = 3H);
			ASSERT(((protocol = BootProtocol) OR (protocol = ReportProtocol)) & (interface.bInterfaceSubClass = 1));
			RETURN device.Request(HidSetRequest, HrSetProtocol, protocol, interface.bInterfaceNumber, 0, AosUsbdi.NoData) = AosUsbdi.Ok ;
		END SetProtocol;

		(** 
		 * The Getprotocol requests reads which protocol is currently active (HID, p. 54).
		 * This request is only supported by devices in the boot subclass. 		
		 * @param interface the request should be applied to
		 * @param protocol 0: Boot Protocol, 1: Report Protocol (Only valid if request succeeds!)	
		 * @return TRUE, if request succeeded, FALSE otherwise
		 *)
		PROCEDURE GetProtocol*(VAR protocol : LONGINT) : BOOLEAN;
		VAR buffer : AosUsbdi.BufferPtr;
		BEGIN
			ASSERT((interface.bInterfaceClass = 3H) & (interface.bInterfaceSubClass=  1));
			NEW(buffer, 1);
			IF device.Request(HidGetRequest, HrGetProtocol, 0, interface.bInterfaceNumber, 1, buffer^) = AosUsbdi.Ok THEN
				protocol := ORD(buffer[0]); 
				RETURN TRUE;
			END;
			RETURN FALSE;
		END GetProtocol;
		
		(** 
		 * The SetReport request allows the host to send a report to the device, possibly setting the state of input,
		 * output, or feature controls (HID, p. 52). 
		 * @param interface the request should be applied to
		 * @param type of the report the host sends
		 * @param id of the report the host sends
		 * @param buffer: Buffer containing the report
		 * @param len: Lenght of the report
		 * @return TRUE, if request succeeded, FALSE otherwise
		 *)
		PROCEDURE SetReport*(type, id : LONGINT; VAR buffer: AosUsbdi.Buffer; len : LONGINT) : BOOLEAN;
		BEGIN
			ASSERT(interface.bInterfaceClass = 3H);
			RETURN device.Request(HidSetRequest, HrSetReport, id + type*100H, interface.bInterfaceNumber, len, buffer) = AosUsbdi.Ok;
		END SetReport;

		(** 
		 * The GetReport request allows the host to receive a report via the Control pipe (HID, p.51) 
		 * @param interface the request should be applied to
		 * @param type Type of the report we want
		 * @param id of the report we want
		 * @param buffer: Buffer to put the report into
		 * @param len: Exspected length of the report
		 * @return TRUE, if request succeeded, FALSE otherwise
		*)
		PROCEDURE GetReport*(type, id : LONGINT; VAR buffer: AosUsbdi.Buffer; len : LONGINT) : BOOLEAN;
		BEGIN
			ASSERT(LEN(buffer) >= len);
			ASSERT(interface.bInterfaceClass = 3H);
			RETURN device.Request(HidGetRequest, HrGetReport, id + type*100H, interface.bInterfaceNumber, len, buffer) = AosUsbdi.Ok;
		END GetReport;
				
		(** This request returns the specified descriptor if the descriptor exists *)
		PROCEDURE GetDescriptor*(descriptor, index, wIndex, len : LONGINT; VAR buffer : AosUsbdi.Buffer) : BOOLEAN;
		BEGIN	
			ASSERT(LEN(buffer) >= len);
			RETURN device.Request(AosUsbdi.ToHost + AosUsbdi.Standard + AosUsbdi.Interface, SrGetDescriptor, index + descriptor*100H, wIndex, len, buffer) = AosUsbdi.Ok;
		END GetDescriptor;
		
		(** Returns the HID descriptor of this interface or NIL if not present *)
		PROCEDURE GetHidDescriptor*() : HidDescriptor;
		VAR ud : AosUsbdi.UnknownDescriptor; hidDescriptor : HidDescriptor;
		BEGIN
			ASSERT(interface.bInterfaceClass = 3H);
			(* The HID descriptor is part of the configuration descriptor and therefore already pre-parsed by the USB system *)
			ud := interface.unknown;
			WHILE (ud # NIL) & (ud.bDescriptorType # DescriptorHID) DO ud := ud.next; END;
			IF ud # NIL THEN
				hidDescriptor := ParseHidDescriptor(ud.descriptor);
			END;
			RETURN hidDescriptor;
		END GetHidDescriptor;
		
				
	END HidDriver; 
	
(* Load and parse the HID descriptor correspondig to the drivers interface *)
PROCEDURE ParseHidDescriptor(descriptor : AosUsbdi.BufferPtr) : HidDescriptor;
VAR hid : HidDescriptor;  i : LONGINT;
BEGIN
	IF (descriptor # NIL) & (LEN(descriptor) >= 8) THEN
		NEW(hid);
		hid.bLength := ORD(descriptor[0]);
		hid.bDescriptorType := ORD(descriptor[1]);
		hid.bcdHID := ORD(descriptor[2]) + 100H*ORD(descriptor[3]);
		hid.bCountryCode := ORD(descriptor[4]);
		hid.bNumDescriptors := ORD(descriptor[5]);
		hid.bClassDescriptorType := ORD(descriptor[6]);
		hid.wDescriptorLength := ORD(descriptor[7]);
		
		(* Parse the optional descriptors if there are some *)
		IF hid.bNumDescriptors > 1 THEN
			IF LEN(descriptor) >= (3 * (hid.bNumDescriptors-2)) + 7 THEN
				AosOut.String("AosUsbHid: Warning: HID descriptor too short"); AosOut.Ln;
				RETURN hid;
			END;
			NEW(hid.optionalDescriptors, hid.bNumDescriptors-1);
			FOR i := 0 TO hid.bNumDescriptors-2 DO
				hid.optionalDescriptors[i].bDescriptorType := ORD(descriptor[(3 * i) + 6]);
				hid.optionalDescriptors[i].wDescriptorLength := ORD(descriptor[(3 * i) + 7]);
			END;
		END;
	END;
	RETURN hid;
END ParseHidDescriptor;

PROCEDURE ShowHidDescriptor*(hd : HidDescriptor);
VAR i : LONGINT;
BEGIN
	AosOut.String("HID Descriptor: ");
	IF hd = NIL THEN AosOut.String("NIL"); END; AosOut.Ln;
	AosOut.String("   bLength: "); AosOut.Int(hd.bLength, 0); AosOut.Ln;
	AosOut.String("   bDescriptorType: "); AosOut.Int(hd.bDescriptorType, 0); 
	AosOut.String("   bcdHID: "); AosOut.Hex(hd.bcdHID, 0); AosOut.Char("H"); AosOut.Ln;
	AosOut.String("   bCountryCode: "); AosOut.Hex(hd.bCountryCode, 0); AosOut.Char("H"); AosOut.Ln;
	AosOut.String("   bNumDescriptors: "); AosOut.Int(hd.bNumDescriptors, 0); AosOut.Ln;
	AosOut.String("   bClassDescriptorType: "); AosOut.Int(hd.bClassDescriptorType, 0); AosOut.Ln;
	AosOut.String("   wDescriptorLength: "); AosOut.Int(hd.wDescriptorLength, 0); AosOut.Ln;
	AosOut.String("   Optional descriptors: ");
	IF (hd.optionalDescriptors = NIL) THEN
		AosOut.String("None"); AosOut.Ln;
	ELSE
		FOR i := 0 TO LEN(hd.optionalDescriptors)-1 DO
			AosOut.String("      bDescriptorType: "); AosOut.Int(hd.optionalDescriptors[i].bDescriptorType, 0);
			AosOut.String(", wDescriptorLength: "); AosOut.Int(hd.optionalDescriptors[i].wDescriptorLength, 0); 
			AosOut.Ln;
		END;
	END;
END ShowHidDescriptor;

END AosUsbHid.
