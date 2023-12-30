MODULE AosUsbGarminGPS18;  (** AUTHOR "staubesv"; PURPOSE "Garmin GPS 18 USB Driver"; *)
(**
 * Status:
 *	
 *	14.12.2005: Device works, delivered data is valid.  No interface for clients implemented so far.
 *
 * Usage:
 *
 *	AosUsbGarminGPS18.Install ~ loads this driver
 *	S.Free AosUsbGarminGPS18 ~ unloads it
 *
 * Note: The GPS needs several minutes until it receives PVT (position, velocity, time) data.
 *
 * References:
 *	
 *	GARMIN GPS Interface Specification USB Addendum (Rev. 3)
 * 	
 * History:
 *
 *	01.12.2005 	History started (staubesv)
 *	14.12.2005 	Fixed PVT data parsing, some cleanup (staubesv)
 *	05.07.2006	Adapted to AosUsbdi (staubesv)
 *)
 
IMPORT SYSTEM, AosOut, AosModules, AosKernel, Utilities, AosUsbdi;

CONST

	Name = "UsbGps";	
	Description = "Garmin GPS 18 USB";
	
	Debug = TRUE;
	
	TraceEvents = {1};
	TracePackets = {2};
	TraceDeviceInfo = {3};
	TraceData = {4};
	TraceSatelliteInfo = {5};
	TracePVTData = {6};
	TraceAll = {0..31};
	TraceNone = {};
	
	Trace = TracePVTData + TraceSatelliteInfo;
	
	(* Packet format: 														*)
	(*																		*)
	(* Byte 0 : 		PacketType (Transport Layer = 0, Application Layer = 20)	*)
	(* Byte 1-3 : 	Reserved (must be 0)									*)
	(* Byte 4-5 : 	PacketID												*)
	(* Byte 6-7 : 	Reserved (must be 0)									*)
	(* Byte 4-11: 	DataSize												*)
	(* Byte 12+  :	Data													*)
	PacketTransport = 0;
	PacketApplication = 20;

	(* Transport layer packets *)
	TlPidDataAvailable = 2;
	TlPidStartSession = 5; 	(* host-to-device: start session *)
	TlPidSessionStarted = 6; 	(* device-to-host: session started *)
	
	(* Application layer packets *)	
	AlPidAck = 6;
	AlPidNak = 21;
	AlPidSatelliteData = 114;
	AlPidProtocolArray = 253;
	AlPidProductRequest = 254;
	AlPidProductData = 255;
	
	GPS18UnitID = 18;
	
	(* Link Protocol L001 *)
	PidL1CommandData = 10;
	PidL1XferCmplt = 12;
	PidL1DateTimeData = 14;
	PidL1PositionData = 17;
	PidL1PrxWptData = 19;
	PidL1Records = 27;
	PidL1RteHdr = 29;
	PidL1RteWptData = 30;
	PidL1AlamancData = 31;
	PidL1TrkData = 34;
	PidL1WptData = 35;
	PidL1PvtData = 51;
	PidL1RteLinkData = 98;
	PidL1TrkHdr = 99;
	PidL1FlightbookRecord = 134; 		(* packet with Flightbook data *)
	PidL1Lap = 149; 						(* part of Forerunner data *)
	
	(* Device Command Protocol A10 *)
	CmdA10AbortTransfer = 0; 			(* abort current transfer *)
	CmdA10TransferAlm = 1; 			(* transfer almanac *)
	CmdA10TransferPosn = 2; 			(* transfer position *)
	CmdA10TransferPrx = 3; 				(* transfer proximity waypoints *)
	CmdA10TransferRte = 4; 				(* transfer routes *)
	CmdA10TransferTime =5; 			(* transfer time *)
	CmdA10TransferTrk = 6; 				(* transfer track log *)
	CmdA10TransferWpt = 7; 			(* transfer waypoints *)
	CmdA10TurnOffPwr = 8; 				(* turn off power *)
	CmdA10StartPvtData = 49; 			(* start transmitting PVT data *)
	CmdA10StopPvtData = 50; 			(* stop transmitting PVT data *)
	CmdA10FlightbookTransfer = 92;		(* start transferring flight records *)
	CmdA10TransferLaps = 117; 			(* transfer laps *)
	
	(* GPS18-specific commands *)
	CmdGps18MeasurementOn = 110;	(* Receiver Measurement Record On *)
	CmdGps18MeasurementOff = 111; 	(* Receiver Measurement Record On *)
	
	(* Coding of D800PVT.fix field *)
	FixUnusable = 0;
	FixInvalid = 1;
	Fix2D = 2;
	Fix3D = 3;
	Fix2DDiff = 4;
	Fix3DDiff = 5;
	
	pi = 3.14159265358979323846E0;
	
TYPE

	ReceiverData = RECORD
		cycles : LONGINT; 	(* number of accumulated cycles (unsigned) *)
		pr : LONGREAL; 		(* pseudorange (meters) *)
		phase : LONGINT; 	(* To convert to (0-359.999) multiply by 360.0 and divide by 2048.0 *)
		slipDetect : CHAR;	(* 0 = no cycle slip detected; non-zero: cycle slip detected *)
		snr : CHAR; 			(* signal strenght (db Hz) *)
		svid : CHAR; 		(* Satellite number (0-31 and 119-138 for WAAS); Add 1 to offset to current svid numbers *)
		valid : CHAR; 		(* 0 = information not valid; non-zero: information valid *)
	END;

	ReceiverMeasurement = RECORD
		tow : LONGREAL; 	(* Receiver time of week (seconds) *)
		wn : LONGINT; 		(* Receiver week number *)
		receiverData : ARRAY 12 OF ReceiverData;
	END;
	
	Packet = POINTER TO ARRAY OF CHAR;

	ProtocolDataType = RECORD
		tag : CHAR;
		data : LONGINT;
	END;
	
	SatelliteData = RECORD;
		svid : LONGINT; 		(* space vehicle identification (1-32 and 33-64 for WAAS); (uint8) *)
		snr : LONGINT; 		(* signal-to-noise ratio (uint16) 						*)
		elev : LONGINT; 	(* satellite elevation in degrees (uint8) 				*)
		azmuth : LONGINT; 	(* satellite azmuth in degrees (uint16) 				*)
		(* status bit field:														*)
		(* Bit 1: The unit has ephemeris data for the specified satellite			*)
		(* Bit 2: The unit has a differential correction for the specified satellite		*)
		(* Bit 3: The unit is using this satellite in the solution 						*)
		status : SET;
	END;
	
	SatelliteInfo = OBJECT
	VAR
		info : ARRAY 12 OF SatelliteData;
		valid : BOOLEAN; (* did we already receive the information ?? *)
		
		PROCEDURE Parse(data : ARRAY OF CHAR);
		VAR temp, i : LONGINT;
		BEGIN {EXCLUSIVE}
			IF LEN(data) # 84 THEN RETURN; END; 
			FOR i := 0 TO 11 DO
				info[i].svid := ORD(data[i*7]);
				info[i].snr := ORD(data[i*7+1]) + 256*ORD(data[i*7+2]);
				info[i].elev := ORD(data[i*7+3]);
				info[i].azmuth := ORD(data[i*7+4]) + 256*ORD(data[i*7+5]);
				temp := ORD(data[i*7+6]); (* QBIC broken SYSTEM.VAL() workaround *)
				info[i].status := SYSTEM.VAL(SET, temp);
			END;
			valid := TRUE;
		END Parse;
		
		PROCEDURE Show(details : BOOLEAN);
		CONST SnrThreshold = 100;
		VAR nbrOfSatellites, i : LONGINT; 
		BEGIN {EXCLUSIVE}
			AosOut.String("Satellite Data: "); AosOut.Ln;
			IF valid THEN
				IF details THEN  	
					FOR i := 0 TO 11 DO
						AosOut.String("Info Rec "); AosOut.Int(i, 4); 
						AosOut.String(": Vehicle identification: "); AosOut.Int(info[i].svid, 5);
						AosOut.String(" SNR: "); AosOut.Int(info[i].snr, 5);
						AosOut.String(" elevation: "); AosOut.Int(info[i].elev, 5);
						AosOut.String(" azmuth : "); AosOut.Int(info[i].azmuth, 5);
						AosOut.String(" Status: ");
						IF 0 IN info[i].status THEN AosOut.String("[ephemeris]"); END;
						IF 1 IN info[i].status THEN AosOut.String("[differential correction]"); END;
						IF 2 IN info[i].status THEN AosOut.String("[inUse]"); END;
						AosOut.Ln;
					END;
				ELSE
					nbrOfSatellites := 0;
					FOR i := 0 TO 11 DO IF info[i].snr >= SnrThreshold THEN INC(nbrOfSatellites); END; END;
					AosOut.String(" Satellites: ");  AosOut.Int(nbrOfSatellites, 0); AosOut.Ln;
				END;
			ELSE
				AosOut.String("Information not yet received."); AosOut.Ln;
			END;
		END Show;
		
		PROCEDURE &Init;
		BEGIN
			valid := FALSE;
		END Init;
		
	END SatelliteInfo;
	
TYPE

	RadianType* = RECORD
		lat-, long- : LONGREAL;
	END;

	D800PVT* = RECORD;
		alt- : REAL; 				(* altitude above WGS 84 ellipsoid (meters) *)
		epe- : REAL; 				(* estimated position error, 2 sigma (meters) *)
		eph-, epv- : REAL; 		(* epe, but horizontal rsp. vertical only (meters) *)
		fix- : INTEGER; 			(* type of position fix: 0 = no fix; 1 = no fix; 2 = 2D; 3 = 3D; 4 = 2D differential, 5 = 3D differential *)
		tow- : LONGREAL; 		(* time of week (seconds) *)
		posn- : RadianType;  		(* latitude and longitude (radians) *)
		east-, north-, up- : REAL; 	(* velocity east, north & up (meters per second) *)
		mslHeight- : REAL; 		(* height of WGS 84 ellipsoid above MSL (meters) *)
		leapSeconds- : INTEGER; 	(* difference between GPS and UTC *)
		wnDays- : LONGINT; 		(* week number days *)
	END;
	
	(* Note: Consider the D800PVT.fix field for information about which fields are valid *)
	PvtInfo = OBJECT
	VAR
		pvtData : D800PVT;
		valid : BOOLEAN;
		
		PROCEDURE Parse(data : ARRAY OF CHAR);
		BEGIN {EXCLUSIVE}
			IF LEN(data) # 64 THEN RETURN END;
			SYSTEM.GET(SYSTEM.ADR(data[0]), pvtData.alt);
			SYSTEM.GET(SYSTEM.ADR(data[4]), pvtData.epe);
			SYSTEM.GET(SYSTEM.ADR(data[8]), pvtData.eph);
			SYSTEM.GET(SYSTEM.ADR(data[12]), pvtData.epv);
			SYSTEM.GET(SYSTEM.ADR(data[16]), pvtData.fix);
			SYSTEM.GET(SYSTEM.ADR(data[18]), pvtData.tow);
			SYSTEM.GET(SYSTEM.ADR(data[26]), pvtData.posn.lat);
			SYSTEM.GET(SYSTEM.ADR(data[34]), pvtData.posn.long);
			SYSTEM.GET(SYSTEM.ADR(data[42]), pvtData.east);
			SYSTEM.GET(SYSTEM.ADR(data[46]), pvtData.north);
			SYSTEM.GET(SYSTEM.ADR(data[50]), pvtData.up);
			SYSTEM.GET(SYSTEM.ADR(data[54]), pvtData.mslHeight);
			SYSTEM.GET(SYSTEM.ADR(data[59]), pvtData.leapSeconds);
			SYSTEM.GET(SYSTEM.ADR(data[60]), pvtData.wnDays);
			valid := TRUE;
		END Parse;
		
		PROCEDURE GetPVTdata() : D800PVT;
		BEGIN {EXCLUSIVE}
			RETURN pvtData;
		END GetPVTdata;
		
		PROCEDURE Show(details : BOOLEAN);
		VAR string : ARRAY 32 OF CHAR; temp : REAL;
		BEGIN {EXCLUSIVE}
			AosOut.String("GPS18: Position Info: "); AosOut.Ln;
			IF valid THEN
				AosOut.String("Position: ");
				AosOut.String("Latitude: "); 
				string := ""; Utilities.FloatToStr(RadianToDegree(pvtData.posn.lat), 5, 4, 0, string); AosOut.String(string); AosOut.String("N degree, ");
				AosOut.String("Longitude: ");  
				string := ""; Utilities.FloatToStr(RadianToDegree(pvtData.posn.long), 5, 4, 0, string); AosOut.String(string); AosOut.String("E degree");
				AosOut.Ln;
				AosOut.String("Altitude: "); 
				temp := pvtData.alt + pvtData.mslHeight;
				string := ""; Utilities.FloatToStr(temp, 5, 2, 0, string); AosOut.String(string); AosOut.String("m (MSL)"); 
				AosOut.String(", alt: "); string := ""; Utilities.FloatToStr(pvtData.alt, 5, 2, 0, string); AosOut.String(string); AosOut.String("m, "); 
				AosOut.String(", msl: "); string := ""; Utilities.FloatToStr(pvtData.mslHeight, 5, 2, 0, string); AosOut.String(string); AosOut.String("m, "); 
				AosOut.Ln;
				AosOut.String("Estimated Position Error: "); 
				string := ""; Utilities.FloatToStr(pvtData.epe, 5, 2, 0, string); AosOut.String(string); AosOut.String("m (");
				AosOut.String("Horizontal: "); string := ""; Utilities.FloatToStr(pvtData.eph, 5, 2, 0, string); AosOut.String(string); AosOut.String("m, ");
				AosOut.String("Vertical: "); string := ""; Utilities.FloatToStr(pvtData.epv, 5, 2, 0, string); AosOut.String(string); AosOut.String("m)");
				AosOut.Ln;				
				AosOut.String("Velocity: ");
				AosOut.String("E: "); string := ""; Utilities.FloatToStr(pvtData.east, 5, 2, 0, string); AosOut.String(string); AosOut.String("m/s, ");
				AosOut.String("N: ");  string := ""; Utilities.FloatToStr(pvtData.north, 5, 2, 0, string); AosOut.String(string); AosOut.String("m/s, ");
				AosOut.String("Up: ");  string := ""; Utilities.FloatToStr(pvtData.up, 5, 2, 0, string); AosOut.String(string); AosOut.String("m/s, ");
				AosOut.Ln;
				AosOut.String("Fix: "); ShowFix(pvtData.fix); AosOut.Ln;
				AosOut.String("WeekNbrDays: "); AosOut.Int(pvtData.wnDays, 0); AosOut.Ln;
			ELSE
				AosOut.String("No position info available"); 
			END;
			AosOut.Ln;
		END Show;
		
		PROCEDURE ShowFix(fix : LONGINT);
		BEGIN
			CASE fix OF
				FixUnusable: AosOut.String("unusable");
				|FixInvalid:  AosOut.String("invalid");
				|Fix2D: AosOut.String("2D");
				|Fix3D: AosOut.String("3D");
				|Fix2DDiff: AosOut.String("2D differential");
				|Fix3DDiff: AosOut.String("3D differential");
			ELSE
				AosOut.String("unknown("); AosOut.Int(fix, 0); AosOut.String(")");
			END;
		END ShowFix;
		
		PROCEDURE &Init;
		BEGIN
			valid := FALSE;
		END Init;
		
	END PvtInfo;

TYPE

	GarminGPS18= OBJECT (AosUsbdi.Driver)
	VAR
		satelliteInfo : SatelliteInfo;
		pvt : PvtInfo;
		buffer : AosUsbdi.BufferPtr;
		status : AosUsbdi.Status;
		interruptIn, bulkIn, bulkOut : AosUsbdi.Pipe;
		interruptInBuffer : AosUsbdi.BufferPtr;
		started, received : BOOLEAN;
		epMaxSize : LONGINT;
		byteCounter : LONGINT;	(* how many bytes have been received *)

		(* information about the GPS device and its capabilities *)
		unitID : LONGINT;
		productString : Utilities.String;
		productId, softwareVersion : LONGINT;
		protocolDataType : POINTER TO ARRAY OF ProtocolDataType; 
		
		(* packets *)
		startSession, productDataRequest : AosUsbdi.BufferPtr;
		
		(* used by Handleevent *)
		data : POINTER TO ARRAY OF CHAR;
		fragLen, fragOfs, fragType, fragId : LONGINT;
		
		(** Start gathering PVT data *)
		PROCEDURE StartPvtData*() : BOOLEAN;
		VAR command : AosUsbdi.BufferPtr;
		BEGIN
			NEW(command, 2); command[0] := CHR(CmdA10StartPvtData); command[1] := CHR(0);
			RETURN SendPacket(BuildPacket(PacketApplication, PidL1CommandData, command));
		END StartPvtData;
		
		(** Stop gathering PVT data *)
		PROCEDURE StopPvtData*() : BOOLEAN;
		VAR command : AosUsbdi.BufferPtr;
		BEGIN
			NEW(command, 2); command[0] := CHR(CmdA10StopPvtData); command[1] := CHR(0);
			RETURN SendPacket(BuildPacket(PacketApplication, PidL1CommandData, command));
		END StopPvtData;
		
		(** Get most recent PVT data. Consider the field fix for validity of data *)
		PROCEDURE GetPvtData*() : D800PVT;
		BEGIN
			RETURN pvt.GetPVTdata();
		END GetPvtData;
			
		PROCEDURE HandlePacket(type, id : LONGINT; data : ARRAY OF CHAR);
		VAR i : LONGINT;
		BEGIN
			IF Trace * TracePackets # {} THEN AosOut.String("GPS18: packet received: "); ShowPacket(type, id); AosOut.Ln; END;
			IF  type = PacketTransport THEN 
			
				IF id =TlPidSessionStarted THEN
						IF LEN(data) = 4 THEN 
							unitID := Get4(data, 0);
							IF Trace * TraceDeviceInfo # {} THEN AosOut.String("GPS18: Unit ID received: "); AosOut.Hex(unitID, 0); AosOut.Ln; END;
						END;
						started := TRUE; 
				ELSIF id = TlPidDataAvailable THEN
				END;
				
			ELSIF type = PacketApplication THEN 
			
				IF id = AlPidProductData THEN 
					ASSERT(LEN(data) > 4);
					NEW(productString, LEN(data)-4);
					productId := ORD(data[0]) + 256*ORD(data[1]);
					softwareVersion := ORD(data[2]) + 256*ORD(data[3]);
					FOR i :=4 TO LEN(data)-1 DO
						productString[i-4] := data[i]; 
					END;
					IF Trace * TraceDeviceInfo # {} THEN 
						AosOut.String("GPS18: Product ID: "); AosOut.Int(productId, 0);
						AosOut.String(" Software Version: "); AosOut.Int(softwareVersion, 0);
						AosOut.String(" Product description: "); AosOut.String(productString^); 
						AosOut.Ln; 
					END;
					
				ELSIF id = AlPidProtocolArray THEN
					ASSERT(LEN(data)  MOD  3 = 0);
					NEW(protocolDataType, LEN(data) DIV 3);
					IF Trace * TraceDeviceInfo # {} THEN AosOut.String("GPS18: Supported protocols: "); END;
					FOR i := 0 TO (LEN(data) DIV 3) -1 DO
						protocolDataType[i].tag := data[i*3];
						protocolDataType[i].data := ORD(data[i*3+1]) + 256*ORD(data[i*3+2]);
						IF Trace * TraceDeviceInfo # {} THEN AosOut.Char(protocolDataType[i].tag); AosOut.Int(protocolDataType[i].data, 0); AosOut.Char(" "); END;
					END; 
					IF Trace  * TraceDeviceInfo # {}THEN AosOut.Ln; END;
					received := TRUE;
					
				ELSIF id = AlPidSatelliteData THEN
					satelliteInfo.Parse(data);
					IF Trace * TraceSatelliteInfo # {} THEN satelliteInfo.Show(TRUE); END;

				ELSIF id = PidL1PvtData THEN
					pvt.Parse(data); 
					IF Trace * TracePVTData # {} THEN pvt.Show(FALSE); END;
				END;
				
			ELSE
				IF Debug THEN AosOut.String("GPS 18: Unknown packet type. Discarding packet."); AosOut.Ln; END;
			END;
		END HandlePacket;
		
		(* re-assembles fragmented packets and sends them to HandlePacket *)
		PROCEDURE HandleEvent(status : AosUsbdi.Status; actLen : LONGINT);
		VAR
			packetType, packetId : LONGINT;
			dataLen, len, i : LONGINT;
			error : BOOLEAN;
		BEGIN
			error := FALSE;
			IF actLen > 0 THEN byteCounter := byteCounter + actLen; END;
			IF (status = AosUsbdi.Ok) OR (status = AosUsbdi.ShortPacket) THEN
				IF fragLen > 0 THEN (* we exspect a fragment of the lenght fragLen *)
					IF Trace * TraceEvents # {} THEN 
						AosOut.String("GPS18: Handle fragment: "); ShowPacket(fragType, fragId);
						AosOut.String(" fragLen: "); AosOut.Int(fragLen, 0); AosOut.String(" fragOfs: "); AosOut.Int(fragOfs, 0);
						AosOut.String(" actLen: "); AosOut.Int(actLen, 0); AosOut.Ln;
					END;
					IF fragLen > epMaxSize THEN len := epMaxSize; ELSE len := fragLen; END;
					ASSERT(len <= actLen);
					
					FOR i := 0 TO len -1 DO data[fragOfs + i] := interruptInBuffer[i]; END;
				
					IF fragLen > epMaxSize THEN 
						ASSERT(actLen = epMaxSize);
						fragLen := fragLen - epMaxSize;
						fragOfs := fragOfs + epMaxSize;
					ELSE
						fragLen := 0; fragOfs := 0;
						HandlePacket(fragType, fragId, data^);
					END;		
					
				ELSIF actLen >= 11 THEN (* beginning of new packet *)
					ASSERT((interruptInBuffer[1]=CHR(0)) & (interruptInBuffer[2]=CHR(0)) & (interruptInBuffer[3]=CHR(0)));
					packetType := ORD(interruptInBuffer[0]);
					packetId := ORD(interruptInBuffer[4]) + 256*ORD(interruptInBuffer[5]);
					ASSERT((interruptInBuffer[6]=CHR(0)) & (interruptInBuffer[7]=CHR(0)));
					dataLen := Get4(interruptInBuffer^, 8);		
					IF Trace * TraceEvents # {} THEN 
						AosOut.String("GPS18: Handle packet: "); ShowPacket(packetType, packetId);
						AosOut.String(" dataLen: "); AosOut.Int(Get4(interruptInBuffer^,8) ,0); AosOut.String(" actLen: "); AosOut.Int(actLen, 0);
						IF Trace * TraceData # {} THEN AosOut.String(" Data: "); FOR i := 12 TO actLen-1 DO AosOut.Char(interruptInBuffer[i]); END; END;
						AosOut.Ln;
					END;				
					NEW(data, dataLen);
					IF dataLen + 12 > epMaxSize THEN (* packet fragmented *)
						fragLen := dataLen + 12 - epMaxSize; fragOfs := epMaxSize - 12; 
						fragType := packetType; fragId := packetId;
					ELSE 
						fragLen := 0; fragOfs := 0;
					END;
					
					FOR i := 0 TO actLen - 12-1 DO
						data[i] := interruptInBuffer[12 + i];
					END;
					
					IF fragLen = 0 THEN HandlePacket(packetType, packetId, data^); END;
				
				ELSE (* probably the device has been disconneted *)
					IF Debug THEN AosOut.String("GPS18: Serious error encountered..."); AosOut.Ln; END;
					error := TRUE;
				END;
			
				IF ~error THEN status := interruptIn.Transfer(epMaxSize, 0, interruptInBuffer^); (* ignore res *) ELSE device.FreePipe(interruptIn); END;
		
			ELSE 
				IF Debug THEN interruptIn.Show(TRUE); AosOut.Ln; END;
				IF status = AosUsbdi.Stalled THEN
					IF interruptIn.ClearHalt() THEN
						IF Debug THEN AosOut.String("GPS18: Stall on Interrupt Pipe cleared."); AosOut.Ln; END;
						status := interruptIn.Transfer(epMaxSize, 0, interruptInBuffer^); (* ignore res *)
					ELSE
						IF Debug THEN AosOut.String("GPS18: Couldn't clear stall on interrupt pipe. Abort."); AosOut.Ln; END;
						device.FreePipe(interruptIn); 
					END;
				END;
			END;
		END HandleEvent;
		
		PROCEDURE SendPacket(packet : AosUsbdi.BufferPtr) : BOOLEAN;
		VAR status : AosUsbdi.Status;
		BEGIN {EXCLUSIVE}
			ASSERT(LEN(packet) >= 12);
			status := bulkOut.Transfer(LEN(packet), 0, packet^);
			RETURN status = AosUsbdi.Ok;
		END SendPacket;
		
		PROCEDURE BuildPacket(type, id : LONGINT; data : AosUsbdi.BufferPtr) : AosUsbdi.BufferPtr;
		VAR packet : AosUsbdi.BufferPtr; i : LONGINT;
		BEGIN
			IF data=NIL THEN
				NEW(packet, 12);
			ELSE
				NEW(packet, 12 + LEN(data));
				FOR i := 0 TO LEN(data)-1 DO packet[i + 12] := data[i]; END;
			END;
			FOR i := 0 TO 11 DO packet[i] := CHR(0); END;
			IF data # NIL THEN Put4(packet, 8, LEN(data)); END;
			packet[0] := CHR(type); 
			packet[4] := CHR(id);
			RETURN packet;
		END BuildPacket;
	
		PROCEDURE Connect() : BOOLEAN;
		CONST
			MaxWaits = 5000; (* maximum time we wait for the TlSessionStarted packet [ms] *)
		VAR
			epInterruptIn, epBulkOut, epBulkIn, epFound : LONGINT;
			status : AosUsbdi.Status;
			timer : AosKernel.Timer;
			waits : LONGINT;
			i : LONGINT;
		BEGIN
			(* Exspected endpoints: 1 InterruptIn, 1 BulkIn, 1 Bulkout*)
			LOOP
				IF ((i >= LEN(interface.endpoints)) OR (epFound = 3)) THEN EXIT; END;
				IF interface.endpoints[i].type = AosUsbdi.InterruptIn THEN
					epInterruptIn := interface.endpoints[i].bEndpointAddress; epMaxSize := interface.endpoints[i].wMaxPacketSize;
					INC(epFound);
				ELSIF interface.endpoints[i].type = AosUsbdi.BulkIn THEN
					epBulkIn := interface.endpoints[i].bEndpointAddress;
					INC(epFound);
				ELSIF  interface.endpoints[i].type = AosUsbdi.BulkOut THEN
					epBulkOut := interface.endpoints[i].bEndpointAddress;
					INC(epFound);
				END;		
				INC(i);			
			END;
			
			IF ~((epFound = 3) & (epInterruptIn # 0) & (epBulkIn # 0) & (epBulkOut # 0)) THEN 
				IF Debug THEN AosOut.String("GPS18: Error: Exspected endpoints not found."); AosOut.Ln; END;
				RETURN FALSE; 
			END;
			
			interruptIn := device.GetPipe(epInterruptIn);
			IF interruptIn = NIL THEN
				IF Debug THEN AosOut.String("GPS18: Error: Couldn't get interrupt in pipe."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			bulkIn := device.GetPipe(epBulkIn); bulkOut := device.GetPipe(epBulkOut);
			IF (bulkIn = NIL) OR (bulkOut = NIL) THEN 
				IF Debug THEN AosOut.String("GPS18: Error: Couldn't get bulk in/out pipes."); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			NEW(interruptInBuffer, interruptIn.maxPacketSize);
			interruptIn.SetTimeout(0); (* non-blocking *)
			interruptIn.SetCompletionHandler(HandleEvent);
			status := interruptIn.Transfer(interruptIn.maxPacketSize, 0, interruptInBuffer^); (* ignore res *)
			
		(*	NEW(buffer, 64);
			bulkIn.SetTimeout(0);
			bulkIn.SetInterruptHandler(HandleEvent);
			status := bulkIn.Send(64, 0, buffer);*)
			
			(* start session *)
			started := FALSE;
			IF ~SendPacket(BuildPacket(PacketTransport, TlPidStartSession, NIL)) THEN 
				IF Debug THEN AosOut.String("GPS18: Couldn't start session"); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			(* the start session packet should be acknowlegde by a SessionStarted packet... wait for it *)
			NEW(timer); waits := 0;
			LOOP 
				IF started OR (waits >= MaxWaits) THEN EXIT; END; 
				timer.Sleep(1);
			END;
			
			IF ~started THEN 
				IF Debug THEN AosOut.String("GPS18: Timeout: SesssionStarted packet not received"); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			(* A001 Protocol capability protocol - get supported protocols *)
			IF ~SendPacket(BuildPacket(PacketApplication, AlPidProductRequest, NIL)) THEN 
				IF Debug THEN AosOut.String("GPS18: Couldn't get product data"); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			received := FALSE; waits := 0;
			LOOP 
				IF received OR (waits >= MaxWaits) THEN EXIT; END; 
				timer.Sleep(1);
			END;
			
			IF ~received THEN 
				IF Debug THEN AosOut.String("GPS18: Timeout: Product Data packet not received"); AosOut.Ln; END;
				RETURN FALSE;
			END;
			
			IF StartPvtData() THEN 
				AosOut.String("GPS18: PVT data started"); AosOut.Ln; 
			ELSE 
				AosOut.String("GPS18: PVT start command failed."); AosOut.Ln; 
			END;
			
			AosOut.String("Garmin GPS18 connected."); AosOut.Ln;
			RETURN TRUE;
		END Connect;
	
		PROCEDURE Disconnect;
		BEGIN
			AosOut.String("Garmin GPS 18 USB disconnected."); AosOut.Ln; 
			AosOut.String("GPS18: Received bytes: "); AosOut.Int(byteCounter, 0); AosOut.Ln;
		END Disconnect;
		
		PROCEDURE &Init;
		BEGIN
			fragLen := 0; NEW(satelliteInfo); NEW(pvt);
			byteCounter := 0;
		END Init;
				
	END GarminGPS18;
	
PROCEDURE RadianToDegree(radian : LONGREAL) : LONGREAL;
BEGIN
	RETURN radian * (180 / pi);
END RadianToDegree;

PROCEDURE Get4(buf : ARRAY OF CHAR; ofs : LONGINT): LONGINT;
BEGIN
	ASSERT(ofs + 3 < LEN(buf));
	RETURN ORD(buf[ofs]) + SYSTEM.LSH(ORD(buf[ofs+1]), 8) + SYSTEM.LSH(ORD(buf[ofs+2]), 16) + SYSTEM.LSH(ORD(buf[ofs+3]), 24);
END Get4;

PROCEDURE Put4(buf : AosUsbdi.BufferPtr; ofs, value : LONGINT);
BEGIN
	ASSERT(ofs + 3 < LEN(buf));
	buf[ofs] := CHR(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, value) * {0..7}));
	buf[ofs+1] := CHR(SYSTEM.VAL(LONGINT, SYSTEM.LSH(SYSTEM.VAL(SET, value) * {8..15}, -8)));
	buf[ofs+2] := CHR(SYSTEM.VAL(LONGINT, SYSTEM.LSH(SYSTEM.VAL(SET, value) * {16..23}, -16)));
	buf[ofs+3] := CHR(SYSTEM.VAL(LONGINT, SYSTEM.LSH(SYSTEM.VAL(SET, value) * {24..31}, -24)));
END Put4;

PROCEDURE ShowPacket(type, id : LONGINT);
BEGIN
	AosOut.String("Type: ");
	IF type = PacketTransport THEN AosOut.String("Transport");
	ELSIF type = PacketApplication THEN AosOut.String("Application");
	ELSE AosOut.String("Unknown("); AosOut.Int(type, 0); AosOut.String(")");
	END;
	AosOut.String(" id: ");
	CASE id OF
		TlPidDataAvailable: AosOut.String("Data Available"); 
		|TlPidStartSession: AosOut.String("Start Session");
		|AlPidAck:  IF type = PacketTransport THEN AosOut.String("Session Started"); ELSE AosOut.String("Ack"); END; 
		|AlPidNak: AosOut.String("Nak");
		|AlPidProtocolArray: AosOut.String("Protocol array");
		|AlPidProductRequest: AosOut.String("Product request");
		|AlPidProductData: AosOut.String("Product Data");
		|AlPidSatelliteData : AosOut.String("Satellite Data Record");
	ELSE
		AosOut.String("Unkown("); AosOut.Int(id, 0); AosOut.String(")"); 
	END;
END ShowPacket;

PROCEDURE Probe(dev : AosUsbdi.UsbDevice; id : AosUsbdi.InterfaceDescriptor) : AosUsbdi.Driver;
VAR driver : GarminGPS18;
BEGIN
	(* check whether the probed device is a Garmin GPS 18 USB*)
	IF (dev.descriptor.idVendor # 91EH) OR (dev.descriptor.idProduct # 03H) THEN RETURN NIL; END;
	IF Trace * TraceDeviceInfo # {}  THEN AosOut.String("Garmin GPS 18 USB found."); AosOut.Ln; END;
	NEW(driver);
	RETURN driver;
END Probe;
		
PROCEDURE Cleanup;
BEGIN
	AosUsbdi.drivers.Remove(Name);
END Cleanup;

PROCEDURE Install*(ptr : PTR): PTR;
BEGIN
	RETURN NIL;
END Install;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	AosUsbdi.drivers.Add(Probe, Name, Description, 9)
END AosUsbGarminGPS18.

AosUsbGarminGPS18.Install ~  S.Free AosUsbGarminGPS18 ~