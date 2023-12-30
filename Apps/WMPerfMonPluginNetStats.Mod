MODULE WMPerfMonPluginNetStats; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor network statistics plugin"; *)
(**
 * History:
 *
 *	26.02.2007	First release (staubesv)
 *)

IMPORT
	WMPerfMonPlugins, AosModules, AosIP, AosTCP, AosUDP, AosDNS, AosICMP, AosIPv4, AosOut;

CONST
	ModuleName = "WMPerfMonPluginIP";

TYPE

	IPStatistics* = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosIP"; p.description := "AosIP statistics"; p.modulename := ModuleName;
			p.autoMax := TRUE;
			p.minDigits := 9; p.fraction := 0; p.unit := "";
			
			NEW(ds, 20);
			ds[0].name := "NIPSentToSubnet";
			ds[1].name := "NIPSentToGateway";
			ds[2].name := "NIPSentBroadcast";
			ds[3].name := "NIPCantFragment";
			ds[4].name := "NIPRcvTotal";
			ds[5].name := "NIPTooSmall";
			ds[6].name := "NIPBadVersion";
			ds[7].name := "NIPOptions";
			ds[8].name := "NIPBadChecksum";
			ds[9].name := "NIPBadLength";
			ds[10].name := "NIPTrim";
			ds[11].name := "NIPBadHdrLen";
			ds[12].name := "NIPNotForUs";
			ds[13].name := "NIPCantReassemble";
			ds[14].name := "NIPSrcIsBroadcast";
			ds[15].name := "NIPDelivered";
			ds[16].name := "NIPNoReceiver";
			ds[17].name := "NIPForwarded";
			ds[18].name := "NIPSentLocalLoopback";
			ds[19].name := "NIPSentPointToPoint";
			p.datasetDescriptor := ds;
		END Init;
				
		PROCEDURE UpdateDataset*;
		BEGIN 
			dataset[0] := AosIP.NIPSentToSubnet;
			dataset[1] := AosIP.NIPSentToGateway;
			dataset[2] := AosIP.NIPSentBroadcast;
			dataset[3] := AosIP.NIPCantFragment;
			dataset[4] := AosIP.NIPRcvTotal;
			dataset[5] := AosIP.NIPTooSmall;
			dataset[6] := AosIP.NIPBadVersion;
			dataset[7] := AosIP.NIPOptions;			
			dataset[8] := AosIP.NIPBadChecksum;
			dataset[9] := AosIP.NIPBadLength;
			dataset[10] := AosIP.NIPTrim;
			dataset[11] := AosIP.NIPBadHdrLen;
			dataset[12] := AosIP.NIPNotForUs;
			dataset[13] := AosIP.NIPCantReassemble;
			dataset[14] := AosIP.NIPSrcIsBroadcast;
			dataset[15] := AosIP.NIPDelivered;			
			dataset[16] := AosIP.NIPNoReceiver;
			dataset[17] := AosIP.NIPForwarded;
			dataset[18] := AosIP.NIPSentLocalLoopback;
			dataset[19] := AosIP.NIPSentPointToPoint;
		END UpdateDataset;
	
	END IPStatistics;
	
TYPE

	TCPStatistics* = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosTCP"; p.description := "AosTCP statistics"; p.modulename := ModuleName;
			p.autoMax := TRUE;
			p.minDigits := 9; p.fraction := 0; p.unit := "";
			
			NEW(ds, 42);
			ds[0].name := "NTCPConnectAttempt";
			ds[1].name := "NTCPPersistTimer";
			ds[2].name := "NTCPFinWait2Timer";
			ds[3].name := "NTCPSendProbe";
			ds[4].name := "NTCPReXmtPack";
			ds[5].name := "NTCPReXmtByte";
			ds[6].name := "NTCPSendPack";
			ds[7].name := "NTCPSendByte";
			ds[8].name := "NTCPAcks";
			ds[9].name := "NTCPSendCtrl";
			ds[10].name := "NTCPSendUrg";
			ds[11].name := "NTCPSendWinUp";
			ds[12].name := "NTCPSegsTimed";
			ds[13].name := "NTCPSendTotal";
			ds[14].name := "NTCPKeepTimer";
			ds[15].name := "NTCPKeepProbe";
			ds[16].name := "NTCPReXmtTimer";
			ds[17].name := "NTCPRcvTotal";
			ds[18].name := "NTCPRcvOptions";
			ds[19].name := "NTCPCacheMiss";
			ds[20].name := "NTCPPredAck";
			ds[21].name := "NTCPAckPack";
			ds[22].name := "NTCPAckByte";
			ds[23].name := "NTCPPredData";
			ds[24].name := "NTCPRcvPackFast";
			ds[25].name := "NTCPRcvByteFast";
			ds[26].name := "NTCPConnects";
			ds[27].name := "NTCPRcvWinProbe";
			ds[28].name := "NTCPDrops";
			ds[29].name := "NTCPRcvWinUpd";
			ds[30].name := "NTCPRTTUpdated";
			ds[31].name := "NTCPDelAck";
			ds[32].name := "NTCPConnDrops";
			ds[33].name := "NTCPClosed";
			ds[34].name := "NTCPSplitBuffer";
			ds[35].name := "NTCPRcvPackSlow";
			ds[36].name := "NTCPRcvByteSlow";
			ds[37].name := "NTCPNewBufs";
			ds[38].name := "NTCPTimeWaitTimer";
			ds[39].name := "NTCPUnacceptable";
			ds[40].name := "NTCPAccepts";
			ds[41].name := "NTCPPersistDrop";
			p.datasetDescriptor := ds;
		END Init;

		PROCEDURE UpdateDataset*;
		BEGIN 
			dataset[0] := AosTCP.NTCPConnectAttempt;
			dataset[1] := AosTCP.NTCPPersistTimer;
			dataset[2] := AosTCP.NTCPFinWait2Timer;
			dataset[3] := AosTCP.NTCPSendProbe;
			dataset[4] := AosTCP.NTCPReXmtPack;
			dataset[5] := AosTCP.NTCPReXmtByte;
			dataset[6] := AosTCP.NTCPSendPack;
			dataset[7] := AosTCP.NTCPSendByte;			
			dataset[8] := AosTCP.NTCPAcks;
			dataset[9] := AosTCP.NTCPSendCtrl;
			dataset[10] := AosTCP.NTCPSendUrg;
			dataset[11] := AosTCP.NTCPSendWinUp;
			dataset[12] := AosTCP.NTCPSegsTimed;
			dataset[13] := AosTCP.NTCPSendTotal;
			dataset[14] := AosTCP.NTCPKeepTimer;
			dataset[15] := AosTCP.NTCPKeepProbe;			
			dataset[16] := AosTCP.NTCPReXmtTimer;
			dataset[17] := AosTCP.NTCPRcvTotal;
			dataset[18] := AosTCP.NTCPRcvOptions;
			dataset[19] := AosTCP.NTCPCacheMiss;
			dataset[20] := AosTCP.NTCPPredAck;
			dataset[21] := AosTCP.NTCPAckPack;
			dataset[22] := AosTCP.NTCPAckByte;
			dataset[23] := AosTCP.NTCPPredData;
			dataset[24] := AosTCP.NTCPRcvPackFast;
			dataset[25] := AosTCP.NTCPRcvByteFast;
			dataset[26] := AosTCP.NTCPConnects;
			dataset[27] := AosTCP.NTCPRcvWinProbe;
			dataset[28] := AosTCP.NTCPDrops;
			dataset[29] := AosTCP.NTCPRcvWinUpd;
			dataset[30] := AosTCP.NTCPRTTUpdated;
			dataset[31] := AosTCP.NTCPDelAck;
			dataset[32] := AosTCP.NTCPConnDrops;
			dataset[33] := AosTCP.NTCPClosed;
			dataset[34] := AosTCP.NTCPSplitBuffer;
			dataset[35] := AosTCP.NTCPRcvPackSlow;
			dataset[36] := AosTCP.NTCPRcvByteSlow;
			dataset[37] := AosTCP.NTCPNewBufs;
			dataset[38] := AosTCP.NTCPTimeWaitTimer;
			dataset[39] := AosTCP.NTCPUnacceptable;
			dataset[40] := AosTCP.NTCPAccepts;
			dataset[41] := AosTCP.NTCPPersistDrop;
		END UpdateDataset;

	END TCPStatistics;

TYPE

	TCPErrors* = OBJECT(WMPerfMonPlugins.Plugin)

		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosTCPErrors"; p.description := "AosTCP error statistics"; p.modulename := ModuleName;
			p.autoMax := TRUE;
			p.minDigits := 9; p.fraction := 0; p.unit := "";
			
			NEW(ds, 36);
			ds[0].name := "NbrOfErrors";
			ds[1].name := "ConnectionRefused";
			ds[2].name := "ConnectionReset";
			ds[3].name := "WrongInterface";
			ds[4].name := "TimedOut";
			ds[5].name := "NotConnected";
			ds[6].name := "NoInterface";
			ds[7].name := "InterfaceClosed";
			ds[8].name := "BroadcastReceived";
			ds[9].name := "InvalidParameter";
			ds[10].name := "AllPortsInUse";
			ds[11].name := "AddressInUse";
			ds[12].name := "DuplicateSegment";
			ds[13].name := "DuplicatePartialSegment";
			ds[14].name := "DuplicateSegmentPAWS";
			ds[15].name := "DataBeyondWindow1";
			ds[16].name := "DataBeyondWindow2";
			ds[17].name := "DataBeyondWindow3";
			ds[18].name := "BadChecksum";
			ds[19].name := "DuplicateAck";
			ds[20].name := "OutOfRangeAck";
			ds[21].name := "TimeOutKeepAlive";
			ds[22].name := "TimeoutEstablished";
			ds[23].name := "SegmentTooBig";
			ds[24].name := "SegmentTooSmall";
			ds[25].name := "BadHeaderLength";
			ds[26].name := "ConnectionGone";
			ds[27].name := "NIYNewIncarnation";
			ds[28].name := "NIYOutOfBand";
			ds[29].name := "NIYMSS";
			ds[30].name := "ConnectionAborted";
			ds[31].name := "NotInitialized";
			ds[32].name := "DataDuplicatePrevComplete";
			ds[33].name := "DataDuplicatePrevPartial";
			ds[34].name := "DataDuplicateNextComplete";
			ds[35].name := "DataDuplicateNextPartial";
			p.datasetDescriptor := ds;
			
			IF LEN(AosTCP.NTCPError) # 36 THEN
				AosOut.String("WMPerfMonPluginNetStats: Warning: Different number of TCP errors expected."); AosOut.Ln;
			END;
		END Init;
		
		PROCEDURE UpdateDataset*;
		VAR i : LONGINT;
		BEGIN
			FOR i := 0 TO LEN(AosTCP.NTCPError)-1 DO
				dataset[i] := AosTCP.NTCPError[i];
			END;
		END UpdateDataset;
	
	END TCPErrors;

TYPE
	
	UDPStatistics* = OBJECT(WMPerfMonPlugins.Plugin)

		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosUDP"; p.description := "AosUDP statistics"; p.modulename := ModuleName;
			p.autoMax := TRUE;
			p.minDigits := 9; p.fraction := 0; p.unit := "";
			
			NEW(ds, 9);
			ds[0].name := "NUDPRcvTotal";
			ds[1].name := "NUDPTooSmall";
			ds[2].name := "NUDPBadChecksum";
			ds[3].name := "NUDPRcvBroadcast";
			ds[4].name := "NUDPUnknownPort";
			ds[5].name := "NUDPQueued";
			ds[6].name := "NUDPQueueOverflow";
			ds[7].name := "NUDPTrim";
			ds[8].name := "NUDPBadHdrLen";
			p.datasetDescriptor := ds;
		END Init;
		
		PROCEDURE UpdateDataset*;
		BEGIN 
			dataset[0] := AosUDP.NUDPRcvTotal;
			dataset[1] := AosUDP.NUDPTooSmall;
			dataset[2] := AosUDP.NUDPBadChecksum;
			dataset[3] := AosUDP.NUDPRcvBroadcast;
			dataset[4] := AosUDP.NUDPUnknownPort;
			dataset[5] := AosUDP.NUDPQueued;
			dataset[6] := AosUDP.NUDPQueueOverflow;
			dataset[7] := AosUDP.NUDPTrim;
			dataset[8] := AosUDP.NUDPBadHdrLen;
		END UpdateDataset;
	
	END UDPStatistics;
	
TYPE
	
	DNSStatistics* = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosDNS"; p.description := "AosDNS statistics"; p.modulename := ModuleName;
			p.autoMax := TRUE;
			p.minDigits := 9; p.fraction := 0; p.unit := "";
			
			NEW(ds, 4);
			ds[0].name := "NDNSReceived";
			ds[1].name := "NDNSSent";
			ds[2].name := "NDNSMismatchID";
			ds[3].name := "NDNSError";
			p.datasetDescriptor := ds;
		END Init;

		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosDNS.NDNSReceived;
			dataset[1] := AosDNS.NDNSSent;
			dataset[2] := AosDNS.NDNSMismatchID;
			dataset[3] := AosDNS.NDNSError;
		END UpdateDataset;
	
	END DNSStatistics;
	
TYPE
	
	ICMPStatistics* = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosICMP"; p.description := "AosICMP statistics"; p.modulename := ModuleName;
			p.autoMax := TRUE;
			p.minDigits := 9; p.fraction := 0; p.unit := "";
			
			NEW(ds, 7);
			ds[0].name := "NICMPRcvTotal";
			ds[1].name := "NICMPTooSmall";
			ds[2].name := "NICMPBadChecksum";
			ds[3].name := "NICMPNoReceiver";
			ds[4].name := "NICMPDelivered";
			ds[5].name := "NICMPEchoRequest";
			ds[6].name := "NICMPSend";
			p.datasetDescriptor := ds;
		END Init;

		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosICMP.NICMPRcvTotal;
			dataset[1] := AosICMP.NICMPTooSmall;
			dataset[2] := AosICMP.NICMPBadChecksum;
			dataset[3] := AosICMP.NICMPNoReceiver;
			dataset[4] := AosICMP.NICMPDelivered;
			dataset[5] := AosICMP.NICMPEchoRequest;
			dataset[6] := AosICMP.NICMPSend;
		END UpdateDataset;
	
	END ICMPStatistics;
	
TYPE

	ARPStatistics* = OBJECT(WMPerfMonPlugins.Plugin)
		
		PROCEDURE Init*(p : WMPerfMonPlugins.Parameter);
		VAR ds : WMPerfMonPlugins.DatasetDescriptor;
		BEGIN
			p.name := "AosIPv4"; p.description := "AosIPv4 ARP statistics"; p.modulename := ModuleName;
			p.autoMax := TRUE;
			p.minDigits := 9; p.fraction := 0; p.unit := "";
			
			NEW(ds, 9);
			ds[0].name := "NARPPut";
			ds[1].name := "NARPRcvTotal";
			ds[2].name := "NARPRcvTooSmall";
			ds[3].name := "NARPRcvIgnored";
			ds[4].name := "NARPRcvDuplicate";
			ds[5].name := "NARPBadAddr";
			ds[6].name := "NARPRequest";
			ds[7].name := "NARPReply";
			ds[8].name := "NARPSkipped";
			p.datasetDescriptor := ds;
		END Init;

		PROCEDURE UpdateDataset*;
		BEGIN
			dataset[0] := AosIPv4.NARPPut;
			dataset[1] := AosIPv4.NARPRcvTotal;
			dataset[2] := AosIPv4.NARPRcvTooSmall;
			dataset[3] := AosIPv4.NARPRcvIgnored;
			dataset[4] := AosIPv4.NARPRcvDuplicate;
			dataset[5] := AosIPv4.NARPBadAddr;
			dataset[6] := AosIPv4.NARPRequest;
			dataset[7] := AosIPv4.NARPReply;
			dataset[8] := AosIPv4.NARPSkipped;
		END UpdateDataset;
	
	END ARPStatistics;

PROCEDURE InitPlugins;
VAR 
	ip : IPStatistics;
	tcp : TCPStatistics;
	tcpErrors : TCPErrors;
	udp : UDPStatistics;
	dns : DNSStatistics;
	icmp : ICMPStatistics;
	arp : ARPStatistics;
	par : WMPerfMonPlugins.Parameter;
BEGIN
	NEW(par); NEW(ip, par);
	NEW(par); NEW(tcp, par);
	NEW(par); NEW(tcpErrors, par);
	NEW(par); NEW(udp, par);
	NEW(par); NEW(dns, par);
	NEW(par); NEW(icmp, par);
	NEW(par); NEW(arp, par);
END InitPlugins;

PROCEDURE Install*(par : ANY) : ANY; (** ~ *)
BEGIN
	RETURN NIL;
END Install;

PROCEDURE Cleanup;
BEGIN
	WMPerfMonPlugins.updater.RemoveByModuleName(ModuleName);	
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	InitPlugins;
END WMPerfMonPluginNetStats.

WMPerfMonPluginNetStats.Install ~  S.Free WMPerfMonPluginNetStats ~
