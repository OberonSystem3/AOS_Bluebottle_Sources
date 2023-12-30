(** AUTHOR "rg"; PURPOSE "Decoder for binary executable code"; *)

MODULE AosDecoder;

IMPORT SYSTEM, AosModules, AosIO, AosMemoryReader, Utilities, AosFS, AosOut, AosTextUtilities, AosCommands, WMGraphics,
	WMEditors, WMTextView, WMComponents, WMStandardComponents, WMDialogs, WMBitmapFont, WMRestorable, WMTrees, WMMessages, UTF8Strings,
	WM := WMWindowManager;

CONST
	objFileSuffix = "Obx";
	maxDecoders = 5;

	MaxOpcodeSize = 20; (* enough for IA32 *)
	
	DecoderModeFile = 1;
	DecoderModeModule = 2;
	DecoderModeBytes = 3;
	
	RepresentationModePlain = 0;
	RepresentationModeMeta = 1;
	
	OFFHdrRef = 8CX;
	OFFHdrBodyRef = 0F8X;
	OFFHdrProcRef = 0F9X;
	
	VarModeDirect = 1;
	VarModeIndirect = 3;
	VarRecord = 0;
	VarArray = 1;
	VarType = 2;

	(* prefix *)
	pCS = 2EX; pDS = 3EX; pES = 26X; pFS = 64X; pGS = 65X; pSS = 36X; pREP = 0F3X;
	AdrSize = 67X; OpSize = 66X; none = -1;
	
	(* fp sizes *)
	FPSizeNone = 0;
	FPSizeSingle = 1;
	FPSizeDouble = 2;
	FPSizeExtended = 3;
	FPSizeWord = 4;
	FPSizeShort = 5;
	FPSizeLong = 6;
	FPSizeSmall = 7;
	FPSizeBig = 9;
	FPSizeBCD = 10;
	
	(* representations *)
	RepInt = 0;
	RepHex = 1;
	RepBoth = 2;
	RepRelJmp = 3;
	
	(* argument structure *)
	ArgNone = -2;
	ArgImm = 0;
	ArgReg = 1;
	ArgMem = 2;
	ArgRegReg = 3; (* must be the first constant for a 2 arguments structure *)
	ArgRegImm = 4;
	ArgRegMem = 5;
	ArgMemReg = 6;
	ArgMemImm = 7;
	ArgImmReg = 8;
	ArgImmImm = 9;
	ArgRegRegImm = 10;
	ArgRegMemImm = 11;
	ArgMemRegImm = 12;
	ArgRegRegReg = 13;
	ArgMemRegReg = 14;

	(* i386 Register *)
	EAX = 0; ECX = 1; EDX = 2; EBX = 3; ESP = 4; EBP = 5; ESI = 6; EDI = 7; (* 32 bit register *)
	AX = 0; CX = 1; DX = 2; BX = 3; SP =  4; BP = 5; SI = 6; DI = 7; (* 16 bit register *)
	AL = 0; CL = 1; DL = 2; BL = 3; AH = 4; CH = 5; DH = 6; BH = 7; (* 8 bit register *)
	ES = 20; CS = 21; SS = 22; DS = 23; FS = 24; GS = 25;  (* 6, 7 reserved *) (* Segment register *)
	CR = 0; DR = 8; TR = 16;
	
	(* special registers *)
	SRegTR = 0;
	SRegDR = 1;
	SRegCR = 2;
	SRegFP = 3;
	
	(* i386 Instructions *)
	opAAA = 1;
	opAAD = 2;
	opAAM = 3;
	opAAS = 4;
	opADC = 5;
	opADD = 6;
	opADDPD = 7;
	opADDPS = 8;
	opADDSD = 9;
	opADDSS = 10;
	opAND = 11;
	opANDPD = 12;
	opANDPS = 13;
	opANDNPD = 14;
	opANDNPS = 15;
	opARPL = 16;
	opBOUND = 17;
	opBSF = 18;
	opBSR = 19;
	opBSWAP = 20;
	opBT = 21;
	opBTC = 22;
	opBTR = 23;
	opBTS = 24;
	opCALL = 25;
	opCALLFAR = 26;
	opCBW = 27;
	opCDQ = 28;
	opCLC = 29;
	opCLD = 30;
	opCLFLUSH = 31;
	opCLI = 32;
	opCLTS = 33;
	opCMC = 34;
	opCMOVcc = 35;
	opCMOVO = 36;
	opCMOVNO = 37;
	opCMOVB = 38;
	opCMOVNB = 39;
	opCMOVZ = 40;
	opCMOVNZ = 41;
	opCMOVBE = 42;
	opCMOVNBE = 43;
	opCMOVS = 44;
	opCMOVNS = 45;
	opCMOVP = 46;
	opCMOVNP = 47;
	opCMOVL = 48;
	opCMOVNL = 49;
	opCMOVLE = 50;
	opCMOVNLE = 51;
	opCMP = 52;
	opCMPPD = 53;
	opCMPPS = 54;
	opCMPS = 55;
	opCMPSB = 56;
	opCMPSW = 57;
	opCMPSD = 58;
	opCMPSS = 59;
	opCMPXCHG = 60;
	opCMPXCHG8B = 61;
	opCOMISD = 62;
	opCOMISS = 63;
	opCPUID = 64;
	opCVTDQ2PD = 65;
	opCVTD12PS = 66;
	opCVTD2DQ = 67;
	opCVTPD2PI = 68;
	opCVTPD2PS = 69;
	opCVTPI2PD = 70;
	opCVTPI2PS = 71;
	opCVTPS2DQ = 72;
	opCVTPS2PD = 73;
	opCVTPS2PI = 74;
	opCVTSD2SI = 75;
	opCVTSD2SS = 76;
	opCVTSI2SD = 77;
	opCVTSI2SS = 78;
	opCVTSS2SD = 79;
	opCVTSS2SI = 80;
	opCVTTPD2PI = 81;
	opCVTTPD2DQ = 82;
	opCVTTPS2DQ = 83;
	opCVTTPS2PI = 84;
	opCVTTDS2SI = 85;
	opCVTTSS2SI = 86;
	opCWD = 87;
	opCWDE = 88;
	opDAA = 89;
	opDAS = 90;
	opDEC = 91;
	opDIV = 92;
	opDIVPD = 93;
	opDIVPS = 94;
	opDIVSD = 95;
	opDIVSS = 96;
	opEMMS = 97;
	opENTER = 98;
	opF2XM1 = 99;
	opFABS = 100;
	opFADD = 101;
	opFADDP = 102;
	opFIADD = 103;
	opFBLD = 104;
	opFBSTP = 105;
	opFCHS = 106;
	opFCLEX = 107;
	opFNCLEX = 108;
	opFCMOVcc = 109;
	opFCOM = 111;
	opFCOMP = 112;
	opFCOMPP = 113;
	opFCOMI = 114;
	opFCOMIP = 115;
	opFUCOMI = 116;
	opFUCOMIP = 117;
	opFCOS = 118;
	opFDECSTP = 119;
	opFDIV = 120;
	opFDIVP = 121;
	opFIDIV = 122;
	opFDIVR = 123;
	opFDIVRP = 124;
	opFIDIVR = 125;
	opFFREE = 126;
	opFICOM = 127;
	opFICOMP = 128;
	opFILD = 129;
	opFINCSTP = 130;
	opFINIT = 131;
	opFNINIT = 132;
	opFIST = 133;
	opFISTP = 134;
	opFLD = 135;
	opFLD1 = 136;
	opFLDL2T = 137;
	opFLDL2E = 138;
	opFLDPI = 139;
	opFLDLG2 = 140;
	opFLDLN2 = 141;
	opFLDZ = 142;
	opFLDCW = 143;
	opFLDENV = 144;
	opFMUL = 145;
	opFMULP = 146;
	opFIMUL = 147;
	opFNOP = 148;
	opFPATAN = 149;
	opFPREM = 150;
	opFPREM1 = 151;
	opFPTAN = 152;
	opFRNDINT = 153;
	opFRSTOR = 154;
	opFSAVE = 155;
	opFNSAVE = 156;
	opFSCALE = 157;
	opFSIN = 158;
	opFSINCOS = 159;
	opFSQRT = 160;
	opFST = 161;
	opFSTP = 162;
	opFSTCW = 163;
	opFNSTCW = 164;
	opFSTENV = 165;
	opFNSTENV = 166;
	opFSTSW = 167;
	opFNSTSW = 168;
	opFSUB = 169;
	opFSUBP = 170;
	opFISUB = 171;
	opFSUBR = 172;
	opFSUBRP = 173;
	opFISUBR = 174;
	opFTST = 175;
	opFUCOM = 176;
	opFUCOMP = 177;
	opFUCOMPP = 178;
	opFWAIT = 179;
	opFXAM = 180;
	opFXCH = 181;
	opFXRSTOR = 182;
	opFXSAVE = 183;
	opFXTRACT = 184;
	opFYL2X = 185;
	opFYL2XP1 = 186;
	opHLT = 187;
	opIDIV = 188;
	opIMUL = 189;
	opIN = 190;
	opINC = 191;
	opINS = 192;
	opINSB = 193;
	opINSW = 194;
	opINSD = 195;
	opINT = 196;
	opINTO = 197;
	opINVD = 198;
	opINVLPG = 199;
	opIRET = 200;
	opIRETD = 201;
	opJcc = 202;
	opJO = 203;
	opJNO = 204;
	opJB = 205;
	opJNB = 206;
	opJZ = 207;
	opJNZ = 208;
	opJBE = 209;
	opJNBE = 210;
	opJS = 211;
	opJNS = 212;
	opJP = 213;
	opJNP = 214;
	opJL = 215;
	opJNL = 216;
	opJLE = 217;
	opJNLE = 218;
	opJCXZ = 219;
	opJECXZ = 220;
	opJMP = 221;
	opJMPFAR = 222;
	opLAHF = 223;
	opLAR = 224;
	opLDMXCSR = 225;
	opLDS = 226;
	opLEA = 227;
	opLEAVE = 228;
	opLES = 229;
	opLFENCE = 230;
	opLFS = 231;
	opLGDT = 232;
	opLGS = 233;
	opLLDT = 234;
	opLIDT = 235;
	opLMSW = 236;
	opLOCK = 237;
	opLODS = 238;
	opLODSB = 239;
	opLODSW = 240;
	opLODSD = 241;
	opLOOP = 242;
	opLOOPE = 243;
	opLOOPNE = 244;
	opLOOPcc = 245;
	opLSL = 246;
	opLSS = 247;
	opLTR = 248;
	opMASKMOVDQU = 249;
	opMASKMOVQ = 250;
	opMAXPD = 251;
	opMAXPS = 252;
	opMAXSD = 253;
	opMAXSS = 254;
	opMFENCE = 255;
	opMINPD = 256;
	opMINPS = 257;
	opMINSD = 258;
	opMINSS = 259;
	opMOV = 260;
	opMOVAPD = 261;
	opMOVAPS = 262;
	opMOVD = 263;
	opMOVDQA = 264;
	opMOVDQU = 265;
	opMOVDQ2Q = 266;
	opMOVHLPS = 267;
	opMOVHPD = 268;
	opMOVHPS = 269;
	opMOVLHPS = 270;
	opMOVLPD = 271;
	opMOVLPS = 272;
	opMOVMSKPD = 273;
	opMOVMSKPS = 274;
	opMOVNTDQ = 275;
	opMOVNTI = 276;
	opMOVNTPD = 277;
	opMOVNTPS = 278;
	opMOVNTQ = 279;
	opMOVQ = 280;
	opMOVQ2DQ = 281;
	opMOVS = 282;
	opMOVSB = 283;
	opMOVSW = 284;
	opMOVSD = 285;
	opMOVSS = 286;
	opMOVSX = 287;
	opMOVUPD = 288;
	opMOVUPS = 289;
	opMOVZX = 290;
	opMUL = 292;
	opMULPD = 293;
	opMULPS = 294;
	opMULSD = 295;
	opMULSS = 296;
	opNEG = 297;
	opNOP = 298;
	opNOT = 299;
	opOR = 300;
	opORPD = 301;
	opORPS = 302;
	opOUT = 303;
	opOUTS = 304;
	opOUTSB = 305;
	opOUTSW = 306;
	opOUTSD = 307;
	opPACKSSWB = 308;
	opPACKSSDW = 309;
	opPACKUSWB = 310;
	opPADDB = 311;
	opPADDW = 312;
	opPADDD = 313;
	opPADDQ = 314;
	opPADDSB = 315;
	opPADDSW = 316;
	opPADDUSB = 317;
	opPADDUSW = 318;
	opPAND = 319;
	opPANDN = 320;
	opPAUSE = 321;
	opPAVGB = 322;
	opPAVGW = 323;
	opPCMPEQB = 324;
	opPCMPEQW = 325;
	opPCMPEQD = 326;
	opPCMPGTB = 327;
	opPCMPGTW = 328;
	opPCMPGTD = 329;
	opPEXTRW = 330;
	opPINSRW = 331;
	opPMADDWD = 332;
	opPMAXSW = 333;
	opPMINSW = 334;
	opPMINUB = 335;
	opPMOVMSKB = 336;
	opPMULHUW = 337;
	opPMULHW = 338;
	opPMULLW = 339;
	opPMULUDQ = 340;
	opPOP = 342;
	opPOPWPTR = 343;
	opPOPDWPTR = 344;
	opPOPA = 345;
	opPOPAD = 346;
	opPOPF = 347;
	opPOPFD = 348;
	opPOR = 349;
	opPREFETCHh = 350;
	opPSADBW = 351;
	opPSHUFD = 352;
	opPSHUFHW = 353;
	opPOSHUFLW = 354;
	opPSHUFW = 355;
	opPSLLDQ = 356;
	opPSLLW = 357;
	opPSLLD = 358;
	opPSLLQ = 359;
	opPSRAW = 360;
	opPSRAD = 361;
	opPSRLDQ = 362;
	opPSRLW = 363;
	opPSRLD = 364;
	opPSRLQ = 365;
	opPSUBB = 366;
	opPSUBW = 367;
	opPSUBD = 368;
	opPSUBQ = 369;
	opPSUBSB = 370;
	opPSUBSW = 371;
	opPSUBUSB = 372;
	opPSUBUSW = 373;
	opPUNPCKHBW = 374;
	opPUNPCKHWD = 375;
	opPUNPCKHDQ = 376;
	opPUNPCKHQDQ = 377;
	opPUNPCKLBW = 378;
	opPUNPCKLWD = 379;
	opPUNPCKLDQ = 380;
	opPUNPCKLQDQ = 381;
	opPUSH = 382;
	opPUSHA = 383;
	opPUSHAD = 384;
	opPUSHF = 385;
	opPUSHFD = 386;
	opPXOR = 387;
	opRCL = 388;
	opRCR = 389;
	opROL = 390;
	opROR = 391;
	opRCPPS = 392;
	opRCPSS = 393;
	opRDMSR = 394;
	opRDPMC = 395;
	opRDTSC = 396;
	opREP = 398;
	opREPE = 399;
	opREPZ = 400;
	opREPNE = 401;
	opREPNZ = 402;
	opRET = 403;
	opRETFAR = 404;
	opRSM = 405;
	opRSQRTPS = 406;
	opRSQRTSS = 407;
	opSAHF = 408;
	opSAL = 409;
	opSAR = 410;
	opSHL = 411;
	opSHR = 412;
	opSBB = 413;
	opSCAS = 414;
	opSCASB = 415;
	opSCASW = 416;
	opSCASD = 417;
	opSETcc = 418;
	opSETO = 419;
	opSETNO = 420;
	opSETB = 421;
	opSETNB = 422;
	opSETZ = 423;
	opSETNZ = 424;
	opSETBE = 425;
	opSETNBE = 426;
	opSETS = 427;
	opSETNS = 428;
	opSETP = 429;
	opSETNP = 430;
	opSETL = 431;
	opSETNL = 432;
	opSETLE = 433;
	opSETNLE = 434;
	opSFENCE = 435;
	opSGDT = 436;
	opSHLD = 437;
	opSHRD = 438;
	opSHUFPD = 439;
	opSHUFPS = 440;
	opSIDT = 441;
	opSLDT = 442;
	opSMSW = 443;
	opSQRTPD = 444;
	opSWRTSD = 445;
	opSQRTSS = 446;
	opSTC = 447;
	opSTD = 448;
	opSTI = 450;
	opSTMXCSR = 451;
	opSTOS = 452;
	opSTOSB = 453;
	opSTOSW = 454;
	opSTOSD = 455;
	opSTR = 456;
	opSUB = 457;
	opSUBPD = 458;
	opSUBPS = 459;
	opSUBSD = 460;
	opSUBSS = 461;
	opSYSENTER = 462;
	opSYSEXIT = 463;
	opTEST = 464;
	opUCOMISD = 465;
	opUCOMISS = 466;
	opUD2 = 467;
	opUNPCKHPD = 468;
	opUNPCKHPS = 469;
	opUNPCKLPD = 470;
	opUNPCKLPS = 471;
	opVERR = 472;
	opVERW = 473;
	opWAIT = 474;
	opWBINVD = 475;
	opWRMSR = 476;
	opXADD = 477;
	opXCHG = 478;
	opXLAT = 479;
	opXLATB = 480;
	opXOR = 481;
	opXORPD = 482;
	opXORPS= 483;

TYPE
	Opcode* = OBJECT
		VAR
			instr* : LONGINT; (* instruction code *)
			offset* : LONGINT;
			code* : AosModules.Bytes;
			length : LONGINT;
			decoder : Decoder;
			next : Opcode;
			stream : AosIO.Writer;
			proc- : ProcedureInfo;
			
		PROCEDURE &New (proc : ProcedureInfo; stream : AosIO.Writer);
		BEGIN
			length := 0;
			SELF.proc := proc;
			SELF.stream := stream
		END New;
		
		PROCEDURE PrintOpcodeBytes* (w : AosIO.Writer);
		BEGIN
		END PrintOpcodeBytes;
		
		PROCEDURE PrintInstruction* (w : AosIO.Writer);
		BEGIN
		END PrintInstruction;
		
		PROCEDURE PrintArguments* (w : AosIO.Writer);
		BEGIN
		END PrintArguments;
		
		PROCEDURE PrintVariables* (w : AosIO.Writer);
		BEGIN
		END PrintVariables;
		
		PROCEDURE ToString* () : Utilities.String;
		VAR
			str : ARRAY 255 OF CHAR;
			temp : ARRAY 10 OF CHAR;
		BEGIN
			Utilities.IntToStr(instr, temp);
			Utilities.Append(str, "Opcode: instr = "); Utilities.Append(str, temp);
			Utilities.IntToHexStr(offset, 0, temp);
			Utilities.Append(str, ", offset = "); Utilities.Append(str, temp);
			RETURN Utilities.NewString(str)
		END ToString;

		PROCEDURE WriteHex8* (x : LONGINT; w : AosIO.Writer);
		VAR result : ARRAY 3 OF CHAR;
		BEGIN
			IntToHex(x, 2, result); w.String(result)
		END WriteHex8;
		
		PROCEDURE WriteHex16* (x : LONGINT; w : AosIO.Writer);
		VAR result : ARRAY 5 OF CHAR;
		BEGIN
			IntToHex(x, 4, result); w.String(result)
		END WriteHex16;

		PROCEDURE WriteHex32* (x : LONGINT; w : AosIO.Writer);
		VAR result : ARRAY 10 OF CHAR;
		BEGIN
			IntToHex(x, 8, result); w.String(result)
		END WriteHex32;
	END Opcode;

	IA32Arg = OBJECT
	END IA32Arg;
	
	IA32ImmArg = OBJECT (IA32Arg)
		VAR 
			imm : LONGINT;
			rep : LONGINT;
			width : LONGINT;
			
		PROCEDURE &NEW(imm: LONGINT; rep, width : LONGINT);
		BEGIN
			SELF.imm := imm;
			SELF.rep:= rep;
			SELF.width := width
		END NEW;		
	END IA32ImmArg;
	
	IA32RegArg = OBJECT (IA32Arg)
		VAR
			reg, width : LONGINT;

		PROCEDURE &NEW(reg: LONGINT);
		BEGIN
			width := 4;
			SELF.reg := reg
		END NEW;		
	END IA32RegArg;
	
	IA32SpecialRegArg = OBJECT (IA32RegArg)
		VAR
			specialKind : LONGINT;
		
		PROCEDURE GetRepresentation (w : AosIO.Writer);
		BEGIN
			CASE specialKind OF
				SRegCR : w.String("CR");
				| SRegDR : w.String("DR");
				| SRegTR : w.String("TR");
				| SRegFP : w.String("ST(");
			ELSE
			END;
			w.Char(CHR(48+reg));
			IF specialKind = SRegFP THEN w.Char(')') END
		END GetRepresentation;
	END IA32SpecialRegArg;
		
	IA32MemArg = OBJECT (IA32Arg)
		VAR
			base, index, scale, disp, fpSize : LONGINT;
			bytePtr, wordPtr : BOOLEAN;

		PROCEDURE &NEW(b, i, s, d: LONGINT);
		BEGIN
			fpSize := 0;
			base := b; index := i; scale := s; disp := d;
			bytePtr := FALSE; wordPtr := FALSE
		END NEW;		
	END IA32MemArg;

	IA32Opcode* = OBJECT (Opcode)
	VAR
		op : LONGINT; (* first-byte-value of opcode *)
		prefixes : LONGINT; (* Number of prefixes *)
		prefix : ARRAY 4 OF CHAR;
		adrPrefix, opPrefix : BOOLEAN;
		opcodeBytes : LONGINT;
		opcodeByte : ARRAY 3 OF CHAR;
		argStructure : LONGINT;
		width : LONGINT;
		arg1, arg2, arg3 : IA32Arg;
		
		PROCEDURE &New(proc : ProcedureInfo; stream : AosIO.Writer);
		BEGIN
			New^(proc, stream);
			prefixes := 0;
			opcodeBytes := 0;
			instr := -1;
			argStructure := none
		END New;
		
		PROCEDURE AddOpcodeByte(b : CHAR);
		BEGIN
			ASSERT(opcodeBytes < 3);
			opcodeByte[opcodeBytes] := b;
			INC(opcodeBytes)
		END AddOpcodeByte;
		
		PROCEDURE AddPrefixByte(b : CHAR);
		BEGIN
			ASSERT(prefixes < 4);
			prefix[prefixes] := b;
			INC(prefixes);
			IF b = AdrSize THEN adrPrefix := TRUE
			ELSIF b = OpSize THEN opPrefix := TRUE END
		END AddPrefixByte;		

		PROCEDURE PrintOpcodeBytes(w : AosIO.Writer);
		VAR
			string : ARRAY 100 OF CHAR;
			hexStr : ARRAY 3 OF CHAR;
			i : LONGINT;
		BEGIN
			string := "";
			FOR i := 0 TO prefixes-1 DO
				IntToHex(ORD(prefix[i]), 2, hexStr);
				w.String(hexStr); w.String(" | ")
			END;
			FOR i := prefixes TO LEN(code)-1 DO
				IntToHex(ORD(code[i]), 2, hexStr);
				w.String(hexStr); w.String(" ");
			END
		END PrintOpcodeBytes;
		
		PROCEDURE PrintInstruction(w : AosIO.Writer);
		VAR
			i : LONGINT;
			opStr : ARRAY 20 OF CHAR;
		BEGIN
			(* print prefixes *)
			FOR i := 0 TO prefixes-1 DO
				CASE prefix[i] OF
					| pREP : w.String("REP ");
				ELSE
				END
			END;			
			CASE instr OF
				opAAA: opStr := "AAA"
				| opAAD: opStr := "AAD"
				| opAAM: opStr := "AAM"
				| opAAS: opStr := "AAS"
				| opADC: opStr := "ADC"
				| opADD: opStr := "ADD"
				| opADDPD: opStr := "ADDPD"
				| opADDPS: opStr := "ADDPS"
				| opADDSD: opStr := "ADDSD"
				| opADDSS: opStr := "ADDSS"
				| opAND: opStr := "AND"
				| opANDPD: opStr := "ANDPD"
				| opANDPS: opStr := "ANDPS"
				| opANDNPD: opStr := "ANDNPD"
				| opANDNPS: opStr := "ANDNPS"
				| opARPL: opStr := "ARPL"
				| opBOUND: opStr := "BOUND"
				| opBSF: opStr := "BSF"
				| opBSR: opStr := "BSR"
				| opBSWAP: opStr := "BSWAP"
				| opBT: opStr := "BT"
				| opBTC: opStr := "BTC"
				| opBTR: opStr := "BTR"
				| opBTS: opStr := "BTS"
				| opCALL: opStr := "CALL"
				| opCALLFAR: opStr := "CALLFAR"
				| opCBW: opStr := "CBW"
				| opCDQ: opStr := "CDQ"
				| opCLC: opStr := "CLC"
				| opCLD: opStr := "CLD"
				| opCLFLUSH: opStr := "CLFLUSH"
				| opCLI: opStr := "CLI"
				| opCLTS: opStr := "CLTS"
				| opCMC: opStr := "CMC"
				| opCMOVcc: opStr := "CMOVcc"
				| opCMOVO: opStr := "CMOVO"
				| opCMOVNO: opStr := "CMOVNO"
				| opCMOVB: opStr := "CMOVB"
				| opCMOVNB: opStr := "CMOVNB"
				| opCMOVZ: opStr := "CMOVZ"
				| opCMOVNZ: opStr := "CMOVNZ"
				| opCMOVBE: opStr := "CMOVBE"
				| opCMOVNBE: opStr := "CMOVNBE"
				| opCMOVS: opStr := "CMOVS"
				| opCMOVNS: opStr := "CMOVNS"
				| opCMOVP: opStr := "CMOVP"
				| opCMOVNP: opStr := "CMOVNP"
				| opCMOVL: opStr := "CMOVL"
				| opCMOVNL: opStr := "CMOVNL"
				| opCMOVLE: opStr := "CMOVLE"
				| opCMOVNLE: opStr := "CMOVNLE"
				| opCMP: opStr := "CMP"
				| opCMPPD: opStr := "CMPPD"
				| opCMPPS: opStr := "CMPPS"
				| opCMPS: opStr := "CMPS"
				| opCMPSB: opStr := "CMPSB"
				| opCMPSW: opStr := "CMPSW"
				| opCMPSD: opStr := "CMPSD"
				| opCMPSS: opStr := "CMPSS"
				| opCMPXCHG: opStr := "CMPXCHG"
				| opCMPXCHG8B: opStr := "CMPXCHG8B"
				| opCOMISD: opStr := "COMISD"
				| opCOMISS: opStr := "COMISS"
				| opCPUID: opStr := "CPUID"
				| opCVTDQ2PD: opStr := "CVTDQ2PD"
				| opCVTD12PS: opStr := "CVTD12PS"
				| opCVTD2DQ: opStr := "CVTD2DQ"
				| opCVTPD2PI: opStr := "CVTPD2PI"
				| opCVTPD2PS: opStr := "CVTPD2PS"
				| opCVTPI2PD: opStr := "CVTPI2PD"
				| opCVTPI2PS: opStr := "CVTPI2PS"
				| opCVTPS2DQ: opStr := "CVTPS2DQ"
				| opCVTPS2PD: opStr := "CVTPS2PD"
				| opCVTPS2PI: opStr := "CVTPS2PI"
				| opCVTSD2SI: opStr := "CVTSD2SI"
				| opCVTSD2SS: opStr := "CVTSD2SS"
				| opCVTSI2SD: opStr := "CVTSI2SD"
				| opCVTSI2SS: opStr := "CVTSI2SS"
				| opCVTSS2SD: opStr := "CVTSS2SD"
				| opCVTSS2SI: opStr := "CVTSS2SI"
				| opCVTTPD2PI: opStr := "CVTTPD2PI"
				| opCVTTPD2DQ: opStr := "CVTTPD2DQ"
				| opCVTTPS2DQ: opStr := "CVTTPS2DQ"
				| opCVTTPS2PI: opStr := "CVTTPS2PI"
				| opCVTTDS2SI: opStr := "CVTTDS2SI"
				| opCVTTSS2SI: opStr := "CVTTSS2SI"
				| opCWD: opStr := "CWD"
				| opCWDE: opStr := "CWDE"
				| opDAA: opStr := "DAA"
				| opDAS: opStr := "DAS"
				| opDEC: opStr := "DEC"
				| opDIV: opStr := "DIV"
				| opDIVPD: opStr := "DIVPD"
				| opDIVPS: opStr := "DIVPS"
				| opDIVSD: opStr := "DIVSD"
				| opDIVSS: opStr := "DIVSS"
				| opEMMS: opStr := "EMMS"
				| opENTER: opStr := "ENTER"
				| opF2XM1: opStr := "F2XM1"
				| opFABS: opStr := "FABS"
				| opFADD: opStr := "FADD"
				| opFADDP: opStr := "FADDP"
				| opFIADD: opStr := "FIADD"
				| opFBLD: opStr := "FBLD"
				| opFBSTP: opStr := "FBSTP"
				| opFCHS: opStr := "FCHS"
				| opFCLEX: opStr := "FCLEX"
				| opFNCLEX: opStr := "FNCLEX"
				| opFCMOVcc: opStr := "FCMOVcc"
				| opFCOM: opStr := "FCOM"
				| opFCOMP: opStr := "FCOMP"
				| opFCOMPP: opStr := "FCOMPP"
				| opFCOMI: opStr := "FCOMI"
				| opFCOMIP: opStr := "FCOMIP"
				| opFUCOMI: opStr := "FUCOMI"
				| opFUCOMIP: opStr := "FUCOMIP"
				| opFCOS: opStr := "FCOS"
				| opFDECSTP: opStr := "FDECSTP"
				| opFDIV: opStr := "FDIV"
				| opFDIVP: opStr := "FDIVP"
				| opFIDIV: opStr := "FIDIV"
				| opFDIVR: opStr := "FDIVR"
				| opFDIVRP: opStr := "FDIVRP"
				| opFIDIVR: opStr := "FIDIVR"
				| opFFREE: opStr := "FFREE"
				| opFICOM: opStr := "FICOM"
				| opFICOMP: opStr := "FICOMP"
				| opFILD: opStr := "FILD"
				| opFINCSTP: opStr := "FINCSTP"
				| opFINIT: opStr := "FINIT"
				| opFNINIT: opStr := "FNINIT"
				| opFIST: opStr := "FIST"
				| opFISTP: opStr := "FISTP"
				| opFLD: opStr := "FLD"
				| opFLD1: opStr := "FLD1"
				| opFLDL2T: opStr := "FLDL2T"
				| opFLDL2E: opStr := "FLDL2E"
				| opFLDPI: opStr := "FLDPI"
				| opFLDLG2: opStr := "FLDLG2"
				| opFLDLN2: opStr := "FLDLN2"
				| opFLDZ: opStr := "FLDZ"
				| opFLDCW: opStr := "FLDCW"
				| opFLDENV: opStr := "FLDENV"
				| opFMUL: opStr := "FMUL"
				| opFMULP: opStr := "FMULP"
				| opFIMUL: opStr := "FIMUL"
				| opFNOP: opStr := "FNOP"
				| opFPATAN: opStr := "FPATAN"
				| opFPREM: opStr := "FPREM"
				| opFPREM1: opStr := "FPREM1"
				| opFPTAN: opStr := "FPTAN"
				| opFRNDINT: opStr := "FRNDINT"
				| opFRSTOR: opStr := "FRSTOR"
				| opFSAVE: opStr := "FSAVE"
				| opFNSAVE: opStr := "FNSAVE"
				| opFSCALE: opStr := "FSCALE"
				| opFSIN: opStr := "FSIN"
				| opFSINCOS: opStr := "FSINCOS"
				| opFSQRT: opStr := "FSQRT"
				| opFST: opStr := "FST"
				| opFSTP: opStr := "FSTP"
				| opFSTCW: opStr := "FSTCW"
				| opFNSTCW: opStr := "FNSTCW"
				| opFSTENV: opStr := "FSTENV"
				| opFNSTENV: opStr := "FNSTENV"
				| opFSTSW: opStr := "FSTSW"
				| opFNSTSW: opStr := "FNSTSW"
				| opFSUB: opStr := "FSUB"
				| opFSUBP: opStr := "FSUBP"
				| opFISUB: opStr := "FISUB"
				| opFSUBR: opStr := "FSUBR"
				| opFSUBRP: opStr := "FSUBRP"
				| opFISUBR: opStr := "FISUBR"
				| opFTST: opStr := "FTST"
				| opFUCOM: opStr := "FUCOM"
				| opFUCOMP: opStr := "FUCOMP"
				| opFUCOMPP: opStr := "FUCOMPP"
				| opFWAIT: opStr := "FWAIT"
				| opFXAM: opStr := "FXAM"
				| opFXCH: opStr := "FXCH"
				| opFXRSTOR: opStr := "FXRSTOR"
				| opFXSAVE: opStr := "FXSAVE"
				| opFXTRACT: opStr := "FXTRACT"
				| opFYL2X: opStr := "FYL2X"
				| opFYL2XP1: opStr := "FYL2XP1"
				| opHLT: opStr := "HLT"
				| opIDIV: opStr := "IDIV"
				| opIMUL: opStr := "IMUL"
				| opIN: opStr := "IN"
				| opINC: opStr := "INC"
				| opINS: opStr := "INS"
				| opINSB: opStr := "INSB"
				| opINSW: opStr := "INSW"
				| opINSD: opStr := "INSD"
				| opINT: opStr := "INT"
				| opINTO: opStr := "INTO"
				| opINVD: opStr := "INVD"
				| opINVLPG: opStr := "INVLPG"
				| opIRET: opStr := "IRET"
				| opIRETD: opStr := "IRETD"
				| opJcc: opStr := "Jcc"
				| opJO: opStr := "JO"
				| opJNO: opStr := "JNO"
				| opJB: opStr := "JB"
				| opJNB: opStr := "JNB"
				| opJZ: opStr := "JZ"
				| opJNZ: opStr := "JNZ"
				| opJBE: opStr := "JBE"
				| opJNBE: opStr := "JNBE"
				| opJS: opStr := "JS"
				| opJNS: opStr := "JNS"
				| opJP: opStr := "JP"
				| opJNP: opStr := "JNP"
				| opJL: opStr := "JL"
				| opJNL: opStr := "JNL"
				| opJLE: opStr := "JLE"
				| opJNLE: opStr := "JNLE"
				| opJCXZ: opStr := "JCXZ"
				| opJECXZ: opStr := "JECXZ"
				| opJMP: opStr := "JMP"
				| opJMPFAR: opStr := "JMPFAR"
				| opLAHF: opStr := "LAHF"
				| opLAR: opStr := "LAR"
				| opLDMXCSR: opStr := "LDMXCSR"
				| opLDS: opStr := "LDS"
				| opLEA: opStr := "LEA"
				| opLEAVE: opStr := "LEAVE"
				| opLES: opStr := "LES"
				| opLFENCE: opStr := "LFENCE"
				| opLFS: opStr := "LFS"
				| opLGDT: opStr := "LGDT"
				| opLGS: opStr := "LGS"
				| opLLDT: opStr := "LLDT"
				| opLIDT: opStr := "LIDT"
				| opLMSW: opStr := "LMSW"
				| opLOCK: opStr := "LOCK"
				| opLODS: opStr := "LODS"
				| opLODSB: opStr := "LODSB"
				| opLODSW: opStr := "LODSW"
				| opLODSD: opStr := "LODSD"
				| opLOOP: opStr := "LOOP"
				| opLOOPE: opStr := "LOOPE"
				| opLOOPNE: opStr := "LOOPNE"
				| opLOOPcc: opStr := "LOOPcc"
				| opLSL: opStr := "LSL"
				| opLSS: opStr := "LSS"
				| opLTR: opStr := "LTR"
				| opMASKMOVDQU: opStr := "MASKMOVDQU"
				| opMASKMOVQ: opStr := "MASKMOVQ"
				| opMAXPD: opStr := "MAXPD"
				| opMAXPS: opStr := "MAXPS"
				| opMAXSD: opStr := "MAXSD"
				| opMAXSS: opStr := "MAXSS"
				| opMFENCE: opStr := "MFENCE"
				| opMINPD: opStr := "MINPD"
				| opMINPS: opStr := "MINPS"
				| opMINSD: opStr := "MINSD"
				| opMINSS: opStr := "MINSS"
				| opMOV: opStr := "MOV"
				| opMOVAPD: opStr := "MOVAPD"
				| opMOVAPS: opStr := "MOVAPS"
				| opMOVD: opStr := "MOVD"
				| opMOVDQA: opStr := "MOVDQA"
				| opMOVDQU: opStr := "MOVDQU"
				| opMOVDQ2Q: opStr := "MOVDQ2Q"
				| opMOVHLPS: opStr := "MOVHLPS"
				| opMOVHPD: opStr := "MOVHPD"
				| opMOVHPS: opStr := "MOVHPS"
				| opMOVLHPS: opStr := "MOVLHPS"
				| opMOVLPD: opStr := "MOVLPD"
				| opMOVLPS: opStr := "MOVLPS"
				| opMOVMSKPD: opStr := "MOVMSKPD"
				| opMOVMSKPS: opStr := "MOVMSKPS"
				| opMOVNTDQ: opStr := "MOVNTDQ"
				| opMOVNTI: opStr := "MOVNTI"
				| opMOVNTPD: opStr := "MOVNTPD"
				| opMOVNTPS: opStr := "MOVNTPS"
				| opMOVNTQ: opStr := "MOVNTQ"
				| opMOVQ: opStr := "MOVQ"
				| opMOVQ2DQ: opStr := "MOVQ2DQ"
				| opMOVS: opStr := "MOVS"
				| opMOVSB: opStr := "MOVSB"
				| opMOVSW: opStr := "MOVSW"
				| opMOVSD: opStr := "MOVSD"
				| opMOVSS: opStr := "MOVSS"
				| opMOVSX: opStr := "MOVSX"
				| opMOVUPD: opStr := "MOVUPD"
				| opMOVUPS: opStr := "MOVUPS"
				| opMOVZX: opStr := "MOVZX"
				| opMUL: opStr := "MUL"
				| opMULPD: opStr := "MULPD"
				| opMULPS: opStr := "MULPS"
				| opMULSD: opStr := "MULSD"
				| opMULSS: opStr := "MULSS"
				| opNEG: opStr := "NEG"
				| opNOP: opStr := "NOP"
				| opNOT: opStr := "NOT"
				| opOR: opStr := "OR"
				| opORPD: opStr := "ORPD"
				| opORPS: opStr := "ORPS"
				| opOUT: opStr := "OUT"
				| opOUTS: opStr := "OUTS"
				| opOUTSB: opStr := "OUTSB"
				| opOUTSW: opStr := "OUTSW"
				| opOUTSD: opStr := "OUTSD"
				| opPACKSSWB: opStr := "PACKSSWB"
				| opPACKSSDW: opStr := "PACKSSDW"
				| opPACKUSWB: opStr := "PACKUSWB"
				| opPADDB: opStr := "PADDB"
				| opPADDW: opStr := "PADDW"
				| opPADDD: opStr := "PADDD"
				| opPADDQ: opStr := "PADDQ"
				| opPADDSB: opStr := "PADDSB"
				| opPADDSW: opStr := "PADDSW"
				| opPADDUSB: opStr := "PADDUSB"
				| opPADDUSW: opStr := "PADDUSW"
				| opPAND: opStr := "PAND"
				| opPANDN: opStr := "PANDN"
				| opPAUSE: opStr := "PAUSE"
				| opPAVGB: opStr := "PAVGB"
				| opPAVGW: opStr := "PAVGW"
				| opPCMPEQB: opStr := "PCMPEQB"
				| opPCMPEQW: opStr := "PCMPEQW"
				| opPCMPEQD: opStr := "PCMPEQD"
				| opPCMPGTB: opStr := "PCMPGTB"
				| opPCMPGTW: opStr := "PCMPGTW"
				| opPCMPGTD: opStr := "PCMPGTD"
				| opPEXTRW: opStr := "PEXTRW"
				| opPINSRW: opStr := "PINSRW"
				| opPMADDWD: opStr := "PMADDWD"
				| opPMAXSW: opStr := "PMAXSW"
				| opPMINSW: opStr := "PMINSW"
				| opPMINUB: opStr := "PMINUB"
				| opPMOVMSKB: opStr := "PMOVMSKB"
				| opPMULHUW: opStr := "PMULHUW"
				| opPMULHW: opStr := "PMULHW"
				| opPMULLW: opStr := "PMULLW"
				| opPMULUDQ: opStr := "PMULUDQ"
				| opPOP: opStr := "POP"
				| opPOPWPTR: opStr := "POPWPTR"
				| opPOPDWPTR: opStr := "POPDWPTR"
				| opPOPA: opStr := "POPA"
				| opPOPAD: opStr := "POPAD"
				| opPOPF: opStr := "POPF"
				| opPOPFD: opStr := "POPFD"
				| opPOR: opStr := "POR"
				| opPREFETCHh: opStr := "PREFETCHh"
				| opPSADBW: opStr := "PSADBW"
				| opPSHUFD: opStr := "PSHUFD"
				| opPSHUFHW: opStr := "PSHUFHW"
				| opPOSHUFLW: opStr := "POSHUFLW"
				| opPSHUFW: opStr := "PSHUFW"
				| opPSLLDQ: opStr := "PSLLDQ"
				| opPSLLW: opStr := "PSLLW"
				| opPSLLD: opStr := "PSLLD"
				| opPSLLQ: opStr := "PSLLQ"
				| opPSRAW: opStr := "PSRAW"
				| opPSRAD: opStr := "PSRAD"
				| opPSRLDQ: opStr := "PSRLDQ"
				| opPSRLW: opStr := "PSRLW"
				| opPSRLD: opStr := "PSRLD"
				| opPSRLQ: opStr := "PSRLQ"
				| opPSUBB: opStr := "PSUBB"
				| opPSUBW: opStr := "PSUBW"
				| opPSUBD: opStr := "PSUBD"
				| opPSUBQ: opStr := "PSUBQ"
				| opPSUBSB: opStr := "PSUBSB"
				| opPSUBSW: opStr := "PSUBSW"
				| opPSUBUSB: opStr := "PSUBUSB"
				| opPSUBUSW: opStr := "PSUBUSW"
				| opPUNPCKHBW: opStr := "PUNPCKHBW"
				| opPUNPCKHWD: opStr := "PUNPCKHWD"
				| opPUNPCKHDQ: opStr := "PUNPCKHDQ"
				| opPUNPCKHQDQ: opStr := "PUNPCKHQDQ"
				| opPUNPCKLBW: opStr := "PUNPCKLBW"
				| opPUNPCKLWD: opStr := "PUNPCKLWD"
				| opPUNPCKLDQ: opStr := "PUNPCKLDQ"
				| opPUNPCKLQDQ: opStr := "PUNPCKLQDQ"
				| opPUSH: opStr := "PUSH"
				| opPUSHA: opStr := "PUSHA"
				| opPUSHAD: opStr := "PUSHAD"
				| opPUSHF: opStr := "PUSHF"
				| opPUSHFD: opStr := "PUSHFD"
				| opPXOR: opStr := "PXOR"
				| opRCL: opStr := "RCL"
				| opRCR: opStr := "RCR"
				| opROL: opStr := "ROL"
				| opROR: opStr := "ROR"
				| opRCPPS: opStr := "RCPPS"
				| opRCPSS: opStr := "RCPSS"
				| opRDMSR: opStr := "RDMSR"
				| opRDPMC: opStr := "RDPMC"
				| opRDTSC: opStr := "RDTSC"
				| opREP: opStr := "REP"
				| opREPE: opStr := "REPE"
				| opREPZ: opStr := "REPZ"
				| opREPNE: opStr := "REPNE"
				| opREPNZ: opStr := "REPNZ"
				| opRET: opStr := "RET"
				| opRETFAR: opStr := "RETFAR"
				| opRSM: opStr := "RSM"
				| opRSQRTPS: opStr := "RSQRTPS"
				| opRSQRTSS: opStr := "RSQRTSS"
				| opSAHF: opStr := "SAHF"
				| opSAL: opStr := "SAL"
				| opSAR: opStr := "SAR"
				| opSHL: opStr := "SHL"
				| opSHR: opStr := "SHR"
				| opSBB: opStr := "SBB"
				| opSCAS: opStr := "SCAS"
				| opSCASB: opStr := "SCASB"
				| opSCASW: opStr := "SCASW"
				| opSCASD: opStr := "SCASD"
				| opSETcc: opStr := "SETcc"
				| opSETO: opStr := "SETO"
				| opSETNO: opStr := "SETNO"
				| opSETB: opStr := "SETB"
				| opSETNB: opStr := "SETNB"
				| opSETZ: opStr := "SETZ"
				| opSETNZ: opStr := "SETNZ"
				| opSETBE: opStr := "SETBE"
				| opSETNBE: opStr := "SETNBE"
				| opSETS: opStr := "SETS"
				| opSETNS: opStr := "SETNS"
				| opSETP: opStr := "SETP"
				| opSETNP: opStr := "SETNP"
				| opSETL: opStr := "SETL"
				| opSETNL: opStr := "SETNL"
				| opSETLE: opStr := "SETLE"
				| opSETNLE: opStr := "SETNLE"
				| opSFENCE: opStr := "SFENCE"
				| opSGDT: opStr := "SGDT"
				| opSHLD: opStr := "SHLD"
				| opSHRD: opStr := "SHRD"
				| opSHUFPD: opStr := "SHUFPD"
				| opSHUFPS: opStr := "SHUFPS"
				| opSIDT: opStr := "SIDT"
				| opSLDT: opStr := "SLDT"
				| opSMSW: opStr := "SMSW"
				| opSQRTPD: opStr := "SQRTPD"
				| opSWRTSD: opStr := "SWRTSD"
				| opSQRTSS: opStr := "SQRTSS"
				| opSTC: opStr := "STC"
				| opSTD: opStr := "STD"
				| opSTI: opStr := "STI"
				| opSTMXCSR: opStr := "STMXCSR"
				| opSTOS: opStr := "STOS"
				| opSTOSB: opStr := "STOSB"
				| opSTOSW: opStr := "STOSW"
				| opSTOSD: opStr := "STOSD"
				| opSTR: opStr := "STR"
				| opSUB: opStr := "SUB"
				| opSUBPD: opStr := "SUBPD"
				| opSUBPS: opStr := "SUBPS"
				| opSUBSD: opStr := "SUBSD"
				| opSUBSS: opStr := "SUBSS"
				| opSYSENTER: opStr := "SYSENTER"
				| opSYSEXIT: opStr := "SYSEXIT"
				| opTEST: opStr := "TEST"
				| opUCOMISD: opStr := "UCOMISD"
				| opUCOMISS: opStr := "UCOMISS"
				| opUD2: opStr := "UD2"
				| opUNPCKHPD: opStr := "UNPCKHPD"
				| opUNPCKHPS: opStr := "UNPCKHPS"
				| opUNPCKLPD: opStr := "UNPCKLPD"
				| opUNPCKLPS: opStr := "UNPCKLPS"
				| opVERR: opStr := "VERR"
				| opVERW: opStr := "VERW"
				| opWAIT: opStr := "FWAIT"
				| opWBINVD: opStr := "WBINVD"
				| opWRMSR: opStr := "WRMSR"
				| opXADD: opStr := "XADD"
				| opXCHG: opStr := "XCHG"
				| opXLAT: opStr := "XLAT"
				| opXLATB: opStr := "XLATB"
				| opXOR: opStr := "XOR"
				| opXORPD: opStr := "XORPD"
				| opXORPS: opStr := "XORPS"
			ELSE
				AosOut.String("Unknown instr = "); AosOut.Int(instr, 0); AosOut.String(", op = "); AosOut.Hex(op, -1); AosOut.Ln; 
				opStr := "[unknown]"
			END;
			w.String(opStr)
		END PrintInstruction;
		
		PROCEDURE PrintArguments(w : AosIO.Writer);
		BEGIN
			ASSERT((argStructure < 0) OR (arg1 # NIL)); (* if instr has arguments, arg1 must not be NIL *)
			ASSERT((argStructure < ArgRegReg) OR (arg2 # NIL)); (* if there are 2 args, the second one must not be NIL *)
			(*
			AosOut.String("Decode opcode: "); AosOut.String("op = "); AosOut.Hex(op, 0);
			AosOut.String(", argStructure = "); AosOut.Int(argStructure, 0); AosOut.Ln;
			*)
			CASE argStructure OF
				ArgReg : WriteReg(arg1(IA32RegArg), w)
				| ArgImm : WriteImm(arg1(IA32ImmArg), w)
				| ArgMem : WriteMem(arg1(IA32MemArg), w)
				| ArgRegMem : WriteReg(arg1(IA32RegArg), w); w.String(", "); WriteMem(arg2(IA32MemArg), w)
				| ArgMemReg : WriteMem(arg1(IA32MemArg), w); w.String(", "); WriteReg(arg2(IA32RegArg), w)
				| ArgRegReg: WriteReg(arg1(IA32RegArg), w); w.String(", "); WriteReg(arg2(IA32RegArg), w)
				| ArgRegImm: WriteReg(arg1(IA32RegArg), w); w.String(", "); WriteImm(arg2(IA32ImmArg), w)
				| ArgMemImm: WriteMem(arg1(IA32MemArg), w); w.String(", "); WriteImm(arg2(IA32ImmArg), w)
				| ArgImmReg: WriteImm(arg1(IA32ImmArg), w); w.String(", "); WriteReg(arg2(IA32RegArg), w)
				| ArgImmImm: WriteImm(arg1(IA32ImmArg), w); w.String(", "); WriteImm(arg2(IA32ImmArg), w)
				| ArgRegRegImm: WriteReg(arg1(IA32RegArg), w); w.String(", "); WriteReg(arg2(IA32RegArg), w); w.String(", "); WriteImm(arg3(IA32ImmArg), w)
				| ArgRegMemImm: WriteReg(arg1(IA32RegArg), w); w.String(", "); WriteMem(arg2(IA32MemArg), w); w.String(", "); WriteImm(arg3(IA32ImmArg), w)
				| ArgMemRegImm: WriteMem(arg1(IA32MemArg), w); w.String(", "); WriteReg(arg2(IA32RegArg), w); w.String(", "); WriteImm(arg3(IA32ImmArg), w)
				| ArgRegRegReg: WriteReg(arg1(IA32RegArg), w); w.String(", "); WriteReg(arg2(IA32RegArg), w); w.String(", "); WriteReg(arg3(IA32RegArg), w)
				| ArgMemRegReg: WriteMem(arg1(IA32MemArg), w); w.String(", "); WriteReg(arg2(IA32RegArg), w); w.String(", "); WriteReg(arg3(IA32RegArg), w)
				| ArgNone:
			ELSE
				w.String("{argStructure not specified!}")
			END
		END PrintArguments;
		
		PROCEDURE PrintVariables(w : AosIO.Writer);
		VAR
			numPrints : LONGINT;
			
			PROCEDURE DetectVar (memArg : IA32MemArg);
			VAR
				field : FieldInfo;
			BEGIN
				IF memArg.base = EBP THEN
					field := proc.GetFieldAtOffset(memArg.disp);
					IF field # NIL THEN
						field.AddMarkerPosition(w.Pos());
						IF numPrints > 0 THEN
							w.String(", ")
						END;
						w.String(field.name);
						w.String(": ");
						WriteMem(memArg, w);
						INC(numPrints)
					END
				END
			END DetectVar;
			
		BEGIN
			numPrints := 0;
			IF arg1 # NIL THEN
				IF arg1 IS IA32MemArg THEN
					DetectVar(arg1(IA32MemArg))
				END;
				IF arg2 # NIL THEN
					IF arg2 IS IA32MemArg THEN
						DetectVar(arg2(IA32MemArg))					
					END;
					IF arg3 # NIL THEN
						IF arg3 IS IA32MemArg THEN
							DetectVar(arg3(IA32MemArg))
						END
					END
				END
			END
		END PrintVariables;
		
		PROCEDURE ToString* () : Utilities.String;
		VAR
			str : ARRAY 255 OF CHAR;
			temp : ARRAY 10 OF CHAR;
		BEGIN
			Utilities.IntToHexStr(op, 0, temp);
			Utilities.Append(str, "Opcode: op = "); Utilities.Append(str, temp);
			Utilities.IntToStr(instr, temp);
			Utilities.Append(str, ", instr = "); Utilities.Append(str, temp);
			Utilities.IntToHexStr(offset, 0, temp);
			Utilities.Append(str, ", offset = "); Utilities.Append(str, temp);
			RETURN Utilities.NewString(str)
		END ToString;
		
		PROCEDURE WriteImm(immArg : IA32ImmArg; w : AosIO.Writer);
		VAR
		
			PROCEDURE WriteHex;
			VAR absImm : LONGINT;
			BEGIN
				absImm := immArg.imm;
				IF immArg.rep = RepRelJmp THEN
					(* add opcode position and length of full opcode to immediate argument value *)
					INC(absImm, offset + length)
				END;
				WriteHex32(absImm, w)
			END WriteHex;
			
		BEGIN
			IF immArg.rep = RepInt THEN
				w.Int(immArg.imm, 0)
			ELSIF immArg.rep = RepHex THEN
				WriteHex;
				w.Char('H')
			ELSE
				w.Int(immArg.imm, 0);
				w.String(" (");
				WriteHex;
				w.String("H)")
			END
		END WriteImm;

		PROCEDURE WriteAdrReg(regNr : LONGINT; w : AosIO.Writer);
		BEGIN
			IF adrPrefix THEN
				IF regNr = 0 THEN w.String("AX")
				ELSIF regNr = 1 THEN w.String("CX")
				ELSIF regNr = 2 THEN w.String("DX")
				ELSIF regNr = 3 THEN w.String("BX")
				ELSIF regNr = 4 THEN w.String("SP")
				ELSIF regNr = 5 THEN w.String("BP")
				ELSIF regNr = 6 THEN w.String("SI")
				ELSIF regNr = 7 THEN w.String("DI")
				ELSE HALT(99)
				END
			ELSE
				IF regNr = 0 THEN w.String("EAX")
				ELSIF regNr = 1 THEN w.String("ECX")
				ELSIF regNr = 2 THEN w.String("EDX")
				ELSIF regNr = 3 THEN w.String("EBX")
				ELSIF regNr = 4 THEN w.String("ESP")
				ELSIF regNr = 5 THEN w.String("EBP")
				ELSIF regNr = 6 THEN w.String("ESI")
				ELSIF regNr = 7 THEN w.String("EDI")
				ELSE HALT(99)
				END
			END
		END WriteAdrReg;
	
		PROCEDURE WriteReg (regArg : IA32RegArg; writer : AosIO.Writer);
		VAR
			reg, w : LONGINT;
			oP : BOOLEAN;
		BEGIN
			IF regArg IS IA32SpecialRegArg THEN
				regArg(IA32SpecialRegArg).GetRepresentation(writer); RETURN
			END;
			w := width;
			oP := opPrefix;
			IF ((instr = opIN) & (regArg = arg2)) OR ((instr = opOUT) & (regArg = arg1)) THEN
				(* port in/out uses 16-bit register for port address only *)
				w := 1; oP := TRUE
			END;
			reg := regArg.reg;
			IF reg >= ES (*DS*) THEN 					(*  <<<< MH 15.3.1994 *)
				IF reg = CS THEN writer.String("CS")
				ELSIF reg = DS THEN writer.String("DS")
				ELSIF reg = ES THEN writer.String("ES")
				ELSIF reg = SS THEN writer.String("SS")
				ELSIF reg = FS THEN writer.String("FS")
				ELSIF reg = GS THEN writer.String("GS")
				ELSE HALT(99)
				END
			ELSIF (w = 0) OR (regArg.width = 1) THEN
				IF reg = 0 THEN writer.String("AL")
				ELSIF reg = 1 THEN writer.String("CL")
				ELSIF reg = 2 THEN writer.String("DL")
				ELSIF reg = 3 THEN writer.String("BL")
				ELSIF reg = 4 THEN writer.String("AH")
				ELSIF reg = 5 THEN writer.String("CH")
				ELSIF reg = 6 THEN writer.String("DH")
				ELSIF reg = 7 THEN writer.String("BH")
				ELSE HALT(99)
				END
			ELSIF oP OR (regArg.width = 2) THEN
				IF reg = 0 THEN writer.String("AX")
				ELSIF reg = 1 THEN writer.String("CX")
				ELSIF reg = 2 THEN writer.String("DX")
				ELSIF reg = 3 THEN writer.String("BX")
				ELSIF reg = 4 THEN writer.String("SP")
				ELSIF reg = 5 THEN writer.String("BP")
				ELSIF reg = 6 THEN writer.String("SI")
				ELSIF reg = 7 THEN writer.String("DI")
				ELSE HALT(99)
				END
			ELSE
				IF reg = 0 THEN writer.String("EAX")
				ELSIF reg = 1 THEN writer.String("ECX")
				ELSIF reg = 2 THEN writer.String("EDX")
				ELSIF reg = 3 THEN writer.String("EBX")
				ELSIF reg = 4 THEN writer.String("ESP")
				ELSIF reg = 5 THEN writer.String("EBP")
				ELSIF reg = 6 THEN writer.String("ESI")
				ELSIF reg = 7 THEN writer.String("EDI")
				ELSE HALT(99)
				END
			END
		END WriteReg;
		
		PROCEDURE WriteMem(memArg : IA32MemArg; w : AosIO.Writer);
		VAR
			intStr : ARRAY 20 OF CHAR;
			i : LONGINT;
		BEGIN
			CASE memArg.fpSize OF
				FPSizeSingle : w.String("SINGLE ")
				| FPSizeDouble : w.String("DOUBLE ")
				| FPSizeExtended : w.String("EXTENDED ")
				| FPSizeWord : w.String("WORD ")
				| FPSizeShort : w.String("SHORT ")
				| FPSizeLong : w.String("LONG ")
				| FPSizeSmall : w.String("SMALL ")
				| FPSizeBig : w.String("BIG ")
				| FPSizeBCD : w.String("BCD ")
			ELSE
			END;
			IF memArg.bytePtr THEN
				w.String("BYTE PTR ")
			ELSIF memArg.wordPtr THEN
				w.String("WORD PTR ")
			END;
			(* write segment prefixes *)
			FOR i := 0 TO prefixes-1 DO
				CASE prefix[i] OF
					pCS : w.String("CS:")
					| pDS : w.String("DS:")
					| pES : w.String("ES:") 
					| pFS : w.String("FS:") 
					| pGS : w.String("GS:") 
					| pSS : w.String("SS:")
				ELSE
				END
			END;
			IF memArg.base # none THEN (* register relative *)
				Utilities.IntToStr(memArg.disp, intStr);
				w.String(intStr);
				w.String("[");
				WriteAdrReg(memArg.base, w)
			ELSE (* absolute *)
				w.String("[");
				w.Int(memArg.disp, 0)
			END;
			IF (memArg.index # none) & ~((memArg.index = ESP) & (memArg.base = ESP)) (* !! 15.4.93 Bug? & (base # ESP) *) THEN (* indexed *)
				w.String(" + ");
				WriteAdrReg(memArg.index, w);
				IF memArg.scale = 0 THEN w.String(" * 1")
				ELSIF memArg.scale = 1 THEN w.String(" * 2")
				ELSIF memArg.scale = 2 THEN w.String(" * 4")
				ELSE w.String(" *  8")
				END;
			END;
			w.String("]")
		END WriteMem;
	END IA32Opcode;

	Decoder* = OBJECT
		VAR
			codeBuffer : AosModules.Bytes;
			reader, outputStreamReader : AosIO.Reader;
			outputStreamWriter* : AosIO.Writer;
			firstOpcode, lastOpcode, currentOpcode, nextIteratorOpcode : Opcode;
			completed : BOOLEAN;
			currentBufferPos, currentCodePos, opcodes, iteratorPos, mode : LONGINT;
			currentProc* : ProcedureInfo;
		
		PROCEDURE &New (reader : AosIO.Reader);
		BEGIN
			SELF.reader := reader;
			SELF.mode := mode;
			NEW(codeBuffer, MaxOpcodeSize);  (* limit: maximum # bytes per opcode *)
			currentCodePos := 0;
			opcodes := 0;
			completed := FALSE
		END New;
		
		PROCEDURE Bug* (op, no: LONGINT);
		BEGIN
			AosOut.Ln;  AosOut.String("*** decode error ***; "); AosOut.String("op = "); AosOut.Hex(op, -1); AosOut.String(", no = "); AosOut.Int(no, 0); AosOut.Ln;
			completed := TRUE
		END Bug;
		
		PROCEDURE NewOpcode* () : Opcode;
		VAR
			opcode : Opcode;
		BEGIN 
			NEW(opcode, currentProc, outputStreamWriter);
			RETURN opcode
		END NewOpcode;
		
		PROCEDURE DecodeThis* (opcode : Opcode);
		BEGIN
		END DecodeThis;
		
		PROCEDURE Decode* (proc : ProcedureInfo) : Opcode;
		(*
		VAR
			str : Utilities.String;
		*)
		BEGIN
			currentProc := proc;
			WHILE ~completed DO
				currentBufferPos := 0;
				IF reader.Available() > 0 THEN
					currentOpcode := NewOpcode();
					BEGIN {EXCLUSIVE}
						DecodeThis(currentOpcode);
						IF reader.res = AosIO.Ok THEN
							IF lastOpcode = NIL THEN
								lastOpcode := currentOpcode;
								firstOpcode := currentOpcode;
							ELSE
								lastOpcode.next := currentOpcode;
								lastOpcode := currentOpcode
							END;
							currentOpcode.offset := currentCodePos;
							(*
							str := currentOpcode.ToString();
							AosOut.String(str^); AosOut.Ln;
							*)
							INC(currentOpcode.length);
							(* copy all buffered bytes to the opcode *)
							CopyBufferToOpcode(currentOpcode);
							INC(opcodes)
						END
					END
				ELSE
					completed := TRUE
				END;
				IF reader.res # AosIO.Ok THEN completed := TRUE END;
			END;
			RETURN firstOpcode
		END Decode;

		PROCEDURE CopyBufferToOpcode(opcode : Opcode);
		VAR i : LONGINT;
		BEGIN
			NEW(opcode.code, currentBufferPos);
			FOR i := 0 TO currentBufferPos-1 DO
				opcode.code[i] := codeBuffer[i]
			END;
			opcode.length := currentBufferPos;
			INC(currentCodePos, currentBufferPos)
		END CopyBufferToOpcode;
		
		PROCEDURE InsertBytesAtBufferHead(bytes : AosModules.Bytes);
		VAR i, n : LONGINT;
		BEGIN
			n := LEN(bytes);
			FOR i := currentBufferPos-1 TO 0 BY -1 DO
				codeBuffer[i+n] := codeBuffer[i]
			END;
			FOR i := 0 TO n-1 DO
				codeBuffer[i] := bytes[i]
			END;
			INC(currentBufferPos, n)						
		END InsertBytesAtBufferHead;
		
		PROCEDURE ReadChar* () : CHAR;
		VAR
			ch : CHAR;
		BEGIN
			reader.Char(ch);
			IF reader.res = AosIO.Ok THEN
				codeBuffer[currentBufferPos] := ch;
				INC(currentBufferPos);
			END;
			RETURN ch
		END ReadChar;
		
		PROCEDURE ReadInt* () : INTEGER;
		VAR
			i : INTEGER;
		BEGIN
			reader.RawInt(i);
			IF reader.res = AosIO.Ok THEN
				SYSTEM.MOVE(SYSTEM.ADR(i), SYSTEM.ADR(codeBuffer[currentBufferPos]), 2);
				INC(currentBufferPos, 2)
			END;
			RETURN i
		END ReadInt;
		
		PROCEDURE ReadLInt* () : LONGINT;
		VAR
			l, highByte, base : LONGINT;
			ch : CHAR;
		BEGIN
			ch := ReadChar();
			l := LONG(ORD(ch));
			ch := ReadChar();
			l := l + LONG(ORD(ch)) * 100H;
			ch := ReadChar();
			l := l + LONG(ORD(ch)) * 10000H;
			ch := ReadChar();
			highByte := ORD(ch);
			IF highByte >= 128 THEN base := MIN(LONGINT); DEC(highByte, 128) ELSE base := 0 END;
			l := base + highByte * 1000000H + l;
			RETURN l
		END ReadLInt;		
	END Decoder;
	
	DecoderFactory = PROCEDURE {DELEGATE} (reader : AosIO.Reader) : Decoder;
	
	IA32Decoder* = OBJECT (Decoder)
		VAR
			prefix: CHAR;
			target: SET;
			(* hack to recognize a WAIT in the previous opcode *)
			previousOpcode, opcodeBeforeWait : IA32Opcode;

		PROCEDURE DoPrefixes (VAR opcode : IA32Opcode);
		VAR
			op : CHAR;
			inPrefixSequence : BOOLEAN;
			
			(* reads all prefixes, store them in the prefix array and store the first real opcode in the opcode array *)
		BEGIN
			inPrefixSequence := TRUE;
			WHILE inPrefixSequence DO
				op := ReadChar();
				IF (op = pCS) OR (op = pDS) OR (op = pES) OR (op = pFS) OR (op = pGS) OR (op = pSS)
						OR (op = AdrSize) OR (op = OpSize) OR (op = pREP) THEN
					opcode.AddPrefixByte(op);
				ELSE
					inPrefixSequence := FALSE;
					opcode.AddOpcodeByte(op)
				END
			END
		END DoPrefixes;

		PROCEDURE GetImm (bytes: LONGINT) : LONGINT;
			VAR ch: CHAR; byte: INTEGER;
		BEGIN
			IF bytes = 1 THEN (* 8 bit *)
				ch := ReadChar();
				IF  ORD(ch) >= 128 THEN byte := ORD(ch) - 256 ELSE byte := ORD(ch) END;
				RETURN byte
			ELSIF bytes = 2 THEN (* 16 bit *)
				RETURN ReadInt()
			ELSE (* 32 bit *)
				RETURN ReadLInt()
			END
		END GetImm;

		PROCEDURE ModRm (VAR regArg: IA32RegArg; VAR memOrRegArg: IA32Arg);
		VAR
			byte, mod, base, index, scale, disp : LONGINT;
			newRegArg : IA32RegArg; newMemArg : IA32MemArg;
		BEGIN
			byte := ORD(ReadChar());
			mod := byte DIV 40H;
			NEW(regArg, (byte DIV 8) MOD 8);
			base := byte MOD 8;
			IF mod = 3 THEN (* reg *)
				NEW(newRegArg, base); memOrRegArg := newRegArg
			ELSE
				IF base = 4 THEN (* escape to two bytes *)
					byte := ORD(ReadChar());
					base := byte MOD 8;
					index := (byte DIV 8) MOD 8;
					scale := byte DIV 40H;
				ELSE (* one byte addressing mode *)
					index := none
				END;
				IF mod = 0 THEN (* no displ, or 32 bit address *)
					IF base = 5 THEN (* disp32 *)
						base := none;
						disp := ReadLInt();
					ELSE disp:= 0
					END
				ELSIF mod = 1 THEN (* 8 bit displ *)
					disp := GetImm(1)
				ELSE (* 32 bit displacement *)
					disp := ReadLInt()
				END;
				NEW(newMemArg, base, index, scale, disp); memOrRegArg := newMemArg
			END
		END ModRm;

		PROCEDURE Type1 (opcode: IA32Opcode; baseOp : LONGINT);
		(* type 1: add, or, adc, sbb, and, sub, xor, cmp *)
			VAR
				kind, immWidth : LONGINT;
				regArg : IA32RegArg;
				immArg : IA32ImmArg;
				secondArg : IA32Arg;
		BEGIN
			kind := ORD(opcode.opcodeByte[0]) - baseOp;
			IF kind = 4 THEN
				opcode.argStructure := ArgRegImm; opcode.width:= 0;
				NEW(regArg, AL); opcode.arg1 := regArg;
				NEW(immArg, GetImm(1), RepHex, 1); opcode.arg2 := immArg
			ELSIF kind = 5 THEN
				opcode.argStructure := ArgRegImm; opcode.width := 1;
				NEW(regArg, AX); opcode.arg1 := regArg;
				IF opcode.opPrefix THEN immWidth := 2 ELSE immWidth := 4 END;
				NEW(immArg, GetImm(immWidth), RepHex, immWidth); opcode.arg2 := immArg
			ELSE
				ModRm(regArg, secondArg);
				CASE kind OF
					0: opcode.width := 0; opcode.argStructure := ArgMemReg; opcode.arg1 := secondArg; opcode.arg2 := regArg
				  | 1: opcode.width := 1; opcode.argStructure := ArgMemReg; opcode.arg1 := secondArg; opcode.arg2 := regArg
				  | 2: opcode.width := 0; opcode.argStructure := ArgRegMem; opcode.arg1 := regArg; opcode.arg2 := secondArg
				  | 3: opcode.width := 1; opcode.argStructure := ArgRegMem; opcode.arg1 := regArg; opcode.arg2 := secondArg
				ELSE HALT(99)
				END;
				IF secondArg IS IA32RegArg THEN opcode.argStructure := ArgRegReg END
			END
		END Type1;

(*		PROCEDURE Add(opcode : IA32Opcode);
			VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
		BEGIN
			Type1(opcode,  mode, d, reg, base, inx, scale, disp, imm);
			opcode.instr := opADD
		END Add;
*)
		PROCEDURE Push (opcode: IA32Opcode);
			VAR imm : LONGINT; immArg : IA32ImmArg; regArg : IA32RegArg;
		BEGIN
			opcode.width:= 1;
			IF opcode.op = 60H THEN 
				IF opcode.opPrefix THEN opcode.instr := opPUSHA ELSE opcode.instr := opPUSHAD END;
			ELSIF opcode.op = 68H THEN
				opcode.instr := opPUSH;
				opcode.argStructure := ArgImm;
				IF opcode.opPrefix THEN
					NEW(immArg, ReadInt(), RepInt, 2); HALT(99)
					ELSE
				NEW(immArg, ReadLInt(), RepInt, 4)
			END;
				opcode.arg1 := immArg
			ELSIF opcode.op = 6AH THEN
				opcode.instr := opPUSH;
				opcode.argStructure := ArgImm;
				NEW(immArg, GetImm(1), RepInt, 1);
				opcode.arg1 := immArg
			ELSIF opcode.op = 9CH THEN
				opcode.argStructure := ArgNone;
				IF opcode.opPrefix THEN opcode.instr := opPUSHF ELSE opcode.instr := opPUSHFD END;
			ELSE
				opcode.instr := opPUSH;
				opcode.argStructure := ArgReg;
				CASE opcode.op OF
					6: NEW(regArg, ES)
				  | 0EH: NEW(regArg, CS)
				  | 16H: NEW(regArg, SS)
				  | 1EH: NEW(regArg, DS)
				  | 50H..57H: NEW(regArg, opcode.op - 50H)
				ELSE Bug(opcode.op, 0)
				END;
				opcode.arg1 := regArg
			END
		END Push;
	
		PROCEDURE Mov (opcode: IA32Opcode);
			VAR
				op, disp, immWidth : LONGINT;
				regArg : IA32RegArg;
				immArg : IA32ImmArg;
				memArg : IA32MemArg;
				secondArg : IA32Arg;
				
			PROCEDURE CalcImmWidth;
			BEGIN
				IF opcode.width = 0 THEN immWidth := 1
				ELSIF opcode.opPrefix THEN immWidth := 2
				ELSE immWidth := 4
				END
			END CalcImmWidth;
				
		BEGIN
			op := opcode.op;
			IF (op >= 88H) & (op <= 8BH) THEN
				Type1(opcode, 88H)
			ELSIF (op >= 0B0H) & (op <= 0B7H) THEN
				opcode.argStructure := ArgRegImm; opcode.width := 0;
				NEW(regArg, op - 0B0H); opcode.arg1 := regArg;
				CalcImmWidth;
				NEW(immArg, GetImm(immWidth), RepInt, immWidth); opcode.arg2 := immArg
			ELSIF (op >= 0B8H) & (op <= 0BFH) THEN
				opcode.argStructure := ArgRegImm; opcode.width := 1;
				NEW(regArg, op - 0B8H); opcode.arg1 := regArg;
				CalcImmWidth;
				NEW(immArg, GetImm(immWidth), RepInt, immWidth); opcode.arg2 := immArg
			ELSIF (op >= 0A0H) & (op <= 0A3H) THEN
				IF opcode.adrPrefix THEN
					disp := ReadInt()
				ELSE
					disp := ReadLInt()
				END;
				NEW(memArg, none, none, 1, disp);
				CASE op OF
					0A0H: opcode.width := 0; opcode.argStructure := ArgRegMem; NEW(regArg, AL); opcode.arg1 := regArg; opcode.arg2 := memArg
				  | 0A1H: opcode.width := 1; opcode.argStructure := ArgRegMem; NEW(regArg, AX); opcode.arg1 := regArg; opcode.arg2 := memArg
				  | 0A2H: opcode.width := 0; opcode.argStructure := ArgMemReg; NEW(regArg, AL); opcode.arg1 := memArg; opcode.arg2 := regArg
				  | 0A3H: opcode.width := 1; opcode.argStructure := ArgMemReg; NEW(regArg, AX); opcode.arg1 := memArg; opcode.arg2 := regArg
				END;
			ELSIF op = 8CH THEN (* mov mem, seg *)
				opcode.width := 1;
				opcode.opPrefix:= TRUE;
				ModRm(regArg, secondArg);
				(* change order according to ModRm output *)
				opcode.arg2 := regArg;
				opcode.arg1 := secondArg;
				IF secondArg IS IA32RegArg THEN
					opcode.argStructure := ArgRegReg
				ELSE
					opcode.argStructure := ArgMemReg
				END;
				INC(opcode.arg2(IA32RegArg).reg, ES) (* reg is a segment register *)
			ELSIF op = 8EH THEN (* mov seg, mem *)
				opcode.width := 1;
				opcode.opPrefix:= TRUE;
				ModRm(regArg, secondArg);
				opcode.arg1 := regArg;
				opcode.arg2 := secondArg;
				IF secondArg IS IA32RegArg THEN
					opcode.argStructure := ArgRegReg
				ELSE
					opcode.argStructure := ArgRegMem
				END;
				INC(opcode.arg1(IA32RegArg).reg, ES) (* reg is segment register *)
			ELSIF (op = 0C6H) OR (op = 0C7H) THEN
				IF op = 0C6H THEN opcode.width := 0; immWidth := 1;
				ELSE
					opcode.width := 1;
					IF opcode.opPrefix THEN immWidth := 2; ELSE immWidth := 4 END
				END;
				ModRm(regArg, secondArg);
				IF secondArg = NIL THEN
					opcode.argStructure := ArgRegImm;
					opcode.arg1 := regArg;
				ELSE
					opcode.argStructure := ArgMemImm;
					opcode.arg1 := secondArg;
				END;
				NEW(immArg, GetImm(immWidth), RepInt, immWidth); opcode.arg2 := immArg
			END;
			opcode.instr := opMOV
		END Mov;

		PROCEDURE Mov2 (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
			specialRegArg : IA32SpecialRegArg;
		BEGIN (* Mov2 op codes contains special registers (debug/test/controll) *)
			opcode.instr := opMOV;
			ModRm(regArg, secondArg);
			NEW(specialRegArg, regArg.reg);
			opcode.width := 1;
			CASE opcode.op OF
			 	20H: opcode.argStructure := ArgRegReg; specialRegArg.specialKind := SRegCR; opcode.arg1 := secondArg; opcode.arg2 := specialRegArg
			  | 21H: opcode.argStructure := ArgRegReg; specialRegArg.specialKind := SRegDR; opcode.arg1 := secondArg; opcode.arg2 := specialRegArg
			  | 22H: opcode.argStructure := ArgRegReg; specialRegArg.specialKind := SRegCR; opcode.arg1 := specialRegArg; opcode.arg2 := secondArg
			  | 23H: opcode.argStructure := ArgRegReg; specialRegArg.specialKind := SRegDR; opcode.arg1 := specialRegArg; opcode.arg2 := secondArg
			  | 24H: opcode.argStructure := ArgRegReg; specialRegArg.specialKind := SRegTR; opcode.arg1 := secondArg; opcode.arg2 := specialRegArg
			  | 26H: opcode.argStructure := ArgRegReg; specialRegArg.specialKind := SRegTR; opcode.arg1 := specialRegArg; opcode.arg2 := secondArg
			ELSE Bug(opcode.op, 24)
			END
		END Mov2;

		PROCEDURE Call (opcode : IA32Opcode);
			VAR immArg : IA32ImmArg;
		BEGIN
			IF opcode.op = 0E8H THEN
				opcode.argStructure := ArgImm;
				IF opcode.adrPrefix THEN
					NEW(immArg, GetImm(2), RepRelJmp, 2); opcode.arg1 := immArg
				ELSE
					NEW(immArg, GetImm(4), RepRelJmp, 4); opcode.arg1 := immArg
				END
			END;
			IF opcode.op = 09AH THEN
				HALT(99)
			END;
			opcode.instr := opCALL
		END Call;
			
		PROCEDURE Pop(opcode : IA32Opcode);
			VAR
				regArg : IA32RegArg;
				secondArg : IA32Arg;
		BEGIN
			IF opcode.op = 61H THEN
				opcode.argStructure := ArgNone;
				IF opcode.opPrefix THEN opcode.instr := opPOPA ELSE opcode.instr := opPOPAD END
			ELSIF opcode.op = 8FH THEN
				IF opcode.opPrefix THEN
					opcode.instr := opPOPWPTR
				ELSE
					opcode.instr := opPOPDWPTR
				END;
				ModRm(regArg, secondArg); opcode.arg1 := regArg; opcode.arg2 := secondArg;
				IF secondArg = NIL THEN opcode.argStructure := ArgReg
				ELSE
					ASSERT(secondArg IS IA32MemArg);
					opcode.argStructure := ArgRegMem
				END					
			ELSIF opcode.op = 9DH THEN 
				IF opcode.opPrefix THEN opcode.instr := opPOPF ELSE opcode.instr := opPOPFD END;
				opcode.argStructure := ArgNone
			ELSE
				opcode.instr := opPOP;
				opcode.argStructure := ArgReg;
				opcode.width := 1; (* pop takes only 16 or 32 bit ops *)
				CASE opcode.op OF
					7: NEW(regArg, ES)
				  | 17H: NEW(regArg, SS)
				  | 1FH: NEW(regArg, DS)
				  | 58H..5FH: NEW(regArg, opcode.op-58H)
				 ELSE Bug(opcode.op, 1)
				 END;
				 opcode.arg1 := regArg
			END
		END Pop;

		PROCEDURE Ret (opcode : IA32Opcode);
			VAR
				immArg : IA32ImmArg;
		BEGIN
			IF (opcode.op = 0C2H) OR (opcode.op = 0CAH) THEN
				NEW(immArg, GetImm(2), RepInt, 2);
				opcode.argStructure := ArgImm; opcode.arg1 := immArg; opcode.instr := opRET
			ELSIF (opcode.op = 0CAH) OR (opcode.op = 0CBH) THEN
				opcode.argStructure := ArgNone; opcode.instr := opRETFAR
			ELSE
				opcode.argStructure := ArgNone; opcode.instr := opRET
			END;
		END Ret;
		
		PROCEDURE Bound (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.width := 1;
			ModRm(regArg, secondArg);
			ASSERT(secondArg IS IA32MemArg);
			opcode.instr := opBOUND;
			opcode.argStructure := ArgRegMem;
			opcode.arg1 := regArg;
			opcode.arg2 := secondArg
		END Bound;
	
		PROCEDURE Add (opcode : IA32Opcode);
		BEGIN
			Type1(opcode, 0H);
			opcode.instr := opADD
		END Add;
	
		PROCEDURE Adc (opcode: IA32Opcode);
		BEGIN
			Type1(opcode, 10H);
			opcode.instr := opADC
		END Adc;
	
		PROCEDURE Sbb (opcode: IA32Opcode);
		BEGIN
			Type1(opcode, 18H);
			opcode.instr := opSBB
		END Sbb;
	
		PROCEDURE  And (opcode: IA32Opcode);
		BEGIN
			Type1(opcode, 20H);
			opcode.instr := opAND
		END And;
	
		PROCEDURE Or (opcode: IA32Opcode);
		BEGIN
			Type1(opcode, 8H);
			opcode.instr := opOR
		END Or;
	
		PROCEDURE Sub (opcode: IA32Opcode);
		BEGIN
			Type1(opcode, 28H);
			opcode.instr := opSUB
		END Sub;
	
		PROCEDURE Xor (opcode: IA32Opcode);
		BEGIN
			Type1(opcode, 30H);
			opcode.instr := opXOR
		END Xor;
	
		PROCEDURE Cmp (opcode: IA32Opcode);
		BEGIN
			Type1(opcode, 38H);
			opcode.instr := opCMP
		END Cmp ;
	
		PROCEDURE Inc (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
		BEGIN
			opcode.argStructure := ArgReg;
			NEW(regArg, opcode.op-40H);
			opcode.arg1 := regArg;
			opcode.instr := opINC;
			opcode.width := 1		(* set width to 16/32 bits, bug2 *)
		END Inc;
	
		PROCEDURE Dec (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
		BEGIN
			opcode.argStructure := ArgReg;
			NEW(regArg, opcode.op-48H);
			opcode.arg1 := regArg;
			opcode.instr := opDEC;
			opcode.width := 1;
		END Dec;

		PROCEDURE Test (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
			immArg : IA32ImmArg;
		BEGIN
			IF (opcode.op = 0A8H) OR (opcode.op = 0A9H) THEN
				opcode.argStructure := ArgRegImm;
				IF opcode.op = 0A8H THEN
					opcode.width := 0;
					NEW(regArg, AL)
				ELSE 
					opcode.width := 1;
					NEW(regArg, AX)
				END;
				opcode.arg1 := regArg;
				IF opcode.width = 0 THEN NEW(immArg, GetImm(1), RepInt, 1)
				ELSE
					IF opcode.opPrefix THEN NEW(immArg, GetImm(2), RepInt, 2)
					ELSE NEW(immArg, GetImm(4), RepInt, 4)
					END
				END;
				opcode.arg2 := immArg
			ELSE
				ModRm(regArg, secondArg);
				IF secondArg IS IA32MemArg THEN
					opcode.argStructure := ArgMemReg;
					opcode.arg1 := secondArg;
					opcode.arg2 := regArg
				ELSE
					opcode.argStructure := ArgRegReg;
					opcode.arg1 := secondArg;
					opcode.arg2 := regArg
				END;
				IF opcode.op = 84H THEN opcode.width := 0
				ELSE opcode.width := 1
				END
			END;
			opcode.instr := opTEST
		END Test;
	
		PROCEDURE Lea (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.width := 1;
			opcode.instr := opLEA;
			ModRm(regArg, secondArg);
			ASSERT(secondArg IS IA32MemArg);
			opcode.argStructure := ArgRegMem;
			opcode.arg1 := regArg;
			opcode.arg2 := secondArg;
		END Lea;
	
		PROCEDURE Les (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.width := 1;
			opcode.instr := opLES;
			ModRm(regArg, secondArg);
			ASSERT(secondArg IS IA32MemArg);
			opcode.argStructure := ArgRegMem;
			opcode.arg1 := regArg;
			opcode.arg2 := secondArg;
		END Les;
	
		PROCEDURE Lds (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.width := 1;
			opcode.instr := opLDS;			
			ModRm(regArg, secondArg);
			ASSERT(secondArg IS IA32MemArg);
			opcode.argStructure := ArgRegMem;
			opcode.arg1 := regArg;
			opcode.arg2 := secondArg;
		END Lds;
			
		PROCEDURE Bit (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
			isReg : BOOLEAN;
		BEGIN
			opcode.width := 1;
			ModRm(regArg, secondArg);
			IF secondArg IS IA32RegArg THEN isReg := TRUE ELSE isReg := FALSE END;
			CASE opcode.op OF
				0A3H: opcode.instr := opBT
				| 0ABH: opcode.instr := opBTS
				| 0B3H: opcode.instr := opBTR
				| 0BBH: opcode.instr := opBTC
				| 0BCH: opcode.instr := opBSF
				| 0BDH: opcode.instr := opBSR
			END;
			IF (opcode.op = 0BCH) OR (opcode.op = 0BDH) THEN
				(* change direction *)
				opcode.arg2 := secondArg;
				opcode.arg1 := regArg;
				IF isReg THEN opcode.argStructure := ArgRegReg
				ELSE opcode.argStructure := ArgRegMem
				END
			ELSE
				opcode.arg2 := regArg;
				opcode.arg1 := secondArg;
				IF isReg THEN opcode.argStructure := ArgRegReg
				ELSE opcode.argStructure := ArgMemReg
				END
			END
		END Bit;
	
		PROCEDURE Shift (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
			immArg : IA32ImmArg;
		BEGIN
			ModRm(regArg, secondArg);
			opcode.arg1 := secondArg;
			opcode.arg2 := regArg;
			IF (opcode.op = 0A4H) OR (opcode.op = 0ACH) THEN (* immediate byte *)
				NEW(immArg, GetImm(1), RepInt, 1);
				opcode.arg3 := immArg;
				IF secondArg IS IA32RegArg THEN opcode.argStructure := ArgRegRegImm
				ELSE opcode.argStructure := ArgMemRegImm
				END
			ELSE
				NEW(regArg, CL);
				regArg.width := 1;
				opcode.arg3 := regArg;
				IF secondArg IS IA32RegArg THEN opcode.argStructure := ArgRegRegReg
				ELSE opcode.argStructure := ArgMemRegReg
				END
			END;
			IF (opcode.op = 0A4H) OR (opcode.op = 0A5H) THEN opcode.instr := opSHLD
			ELSIF (opcode.op = 0ACH) OR (opcode.op = 0ADH) THEN opcode.instr := opSHRD
			ELSE Bug(opcode.op, 20)
			END;
			opcode.width := 1
		END Shift;
		
		PROCEDURE Enter (opcode : IA32Opcode);
		VAR
			immArg : IA32ImmArg;
		BEGIN
			opcode.instr := opENTER;
			opcode.argStructure := ArgImmImm;
			NEW(immArg, GetImm(2), RepInt, 2);
			opcode.arg1 := immArg;
			NEW(immArg, GetImm(1), RepInt, 1);
			opcode.arg2 := immArg
		END Enter;
	
		PROCEDURE Jmp (opcode : IA32Opcode);
		VAR
			immArg : IA32ImmArg;
		BEGIN
			IF (opcode.op = 0E9H) OR (opcode.op = 0EAH) THEN 
				NEW(immArg, GetImm(4), RepRelJmp, 4)
			ELSE
				NEW(immArg, GetImm(1), RepRelJmp, 1)
			END;
			IF opcode.op = 0EAH THEN opcode.instr := opJMPFAR ELSE opcode.instr := opJMP END;
			opcode.argStructure := ArgImm;
			opcode.arg1 := immArg
		END Jmp;
		
		PROCEDURE InOut (opcode : IA32Opcode);
			VAR
				port: LONGINT;
				in, dx: BOOLEAN;
				dataRegArg, portRegArg : IA32RegArg;
				portImmArg : IA32ImmArg;
		BEGIN
			in := opcode.op MOD 4 < 2;
			dx := opcode.op MOD 16 >= 8;
			NEW(dataRegArg, EAX);
			IF ~dx THEN
				port := ORD(ReadChar());
				NEW(portImmArg, port, RepInt, 1)
			ELSE
				NEW(portRegArg, DX)
			END;
			IF in THEN opcode.instr := opIN
			ELSE opcode.instr := opOUT
			END;
			IF ODD(opcode.op) THEN opcode.width := 1 ELSE opcode.width := 0 END;
			IF in THEN
				opcode.arg1 := dataRegArg;
				IF dx THEN
					opcode.argStructure := ArgRegReg;
					opcode.arg2 := portRegArg
				ELSE
					opcode.argStructure := ArgRegImm;
					opcode.arg2 := portImmArg
				END
			ELSE
				opcode.arg2 := dataRegArg;
				IF dx THEN
					opcode.argStructure := ArgRegReg;
					opcode.arg1 := portRegArg
				ELSE
					opcode.argStructure := ArgImmReg;
					opcode.arg1 := portImmArg
				END
			END
		END InOut;
	
		PROCEDURE Jcc (opcode : IA32Opcode);
		VAR
			immArg : IA32ImmArg;
		BEGIN
			NEW(immArg, GetImm(1), RepRelJmp, 1);
			IF immArg.imm >= 128 THEN immArg.imm := immArg.imm - 256 END;
			opcode.argStructure := ArgImm;
			opcode.arg1 := immArg;
			CASE opcode.op OF
				70H: opcode.instr := opJO
			  | 71H: opcode.instr := opJNO
			  | 72H: opcode.instr := opJB
			  | 73H: opcode.instr := opJNB
			  | 74H: opcode.instr := opJZ
			  | 75H: opcode.instr := opJNZ
			  | 76H: opcode.instr := opJBE
			  | 77H: opcode.instr := opJNBE
			  | 78H: opcode.instr := opJS
			  | 79H: opcode.instr := opJNS
			  | 7AH: opcode.instr := opJP
			  | 7BH: opcode.instr := opJNP
			  | 7CH: opcode.instr := opJL
			  | 7DH: opcode.instr := opJNL
			  | 7EH: opcode.instr := opJLE
			  | 7FH: opcode.instr := opJNLE
			ELSE Bug(opcode.op, 2)
			END
		END Jcc;
		
		PROCEDURE Jcc2 (opcode : IA32Opcode);
		VAR
			immArg : IA32ImmArg;
		BEGIN
			IF opcode.adrPrefix THEN
				NEW(immArg, GetImm(2), RepRelJmp, 2);
			ELSE
				NEW(immArg, GetImm(4), RepRelJmp, 4);
			END;
			opcode.argStructure := ArgImm;
			opcode.arg1 := immArg;
			CASE opcode.op OF
				80H: opcode.instr := opJO
			  | 81H: opcode.instr := opJNO
			  | 82H: opcode.instr := opJB
			  | 83H: opcode.instr := opJNB
			  | 84H: opcode.instr := opJZ
			  | 85H: opcode.instr := opJNZ
			  | 86H: opcode.instr := opJBE
			  | 87H: opcode.instr := opJNBE
			  | 88H: opcode.instr := opJS
			  | 89H: opcode.instr := opJNS
			  | 8AH: opcode.instr := opJP
			  | 8BH: opcode.instr := opJNP
			  | 8CH: opcode.instr := opJL
			  | 8DH: opcode.instr := opJNL
			  | 8EH: opcode.instr := opJLE
			  | 8FH: opcode.instr := opJNLE
			ELSE Bug(opcode.op, 3)
			END
		END Jcc2;
	
		PROCEDURE Loop (opcode : IA32Opcode);
			VAR immArg: IA32ImmArg;
		BEGIN
			NEW(immArg, GetImm(1), RepInt, 1);
			opcode.argStructure := ArgImm;
			opcode.arg1 := immArg;
			CASE opcode.op OF
				0E0H: opcode.instr := opLOOPNE
			  | 0E1H: opcode.instr := opLOOPE
			  | 0E2H: opcode.instr := opLOOP
			  | 0E3H: IF opcode.adrPrefix THEN opcode.instr := opJCXZ ELSE opcode.instr := opJECXZ END
			ELSE Bug(opcode.op, 4)
			END
		END Loop;

		PROCEDURE Lar (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			ModRm(regArg, secondArg); opcode.arg1 := secondArg;
			ASSERT(secondArg IS IA32MemArg);
			opcode.instr := opLAR
		END Lar;
	
		PROCEDURE Lsl (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			ModRm(regArg, secondArg); opcode.arg1 := secondArg;
			ASSERT(secondArg IS IA32MemArg);
			opcode.instr := opLSL
		END Lsl;

		PROCEDURE Setcc (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.width := 0; (* always 8 bit wide *)
			ModRm(regArg, secondArg);
			opcode.arg1 := secondArg;
			CASE opcode.op OF
				90H: opcode.instr := opSETO
				| 91H: opcode.instr := opSETNO
				| 92H: opcode.instr := opSETB
				| 93H: opcode.instr := opSETNB
				| 94H: opcode.instr := opSETZ
				| 95H: opcode.instr := opSETNZ
				| 96H: opcode.instr := opSETBE
				| 97H: opcode.instr := opSETNBE
				| 98H: opcode.instr := opSETS
				| 99H: opcode.instr := opSETNS
				| 9AH: opcode.instr := opSETP
				| 9BH: opcode.instr := opSETNP
				| 9CH: opcode.instr := opSETL
				| 9DH: opcode.instr := opSETNL
				| 9EH: opcode.instr := opSETLE
				| 9FH: opcode.instr := opSETNLE
			ELSE Bug(opcode.op, 5)
			END;
			IF secondArg IS IA32RegArg THEN
				opcode.argStructure := ArgReg
			ELSE
				opcode.argStructure := ArgReg
			END
		END Setcc;

		PROCEDURE Int (opcode : IA32Opcode);
			VAR immArg : IA32ImmArg;
		BEGIN
			IF opcode.op = 0CDH THEN
				NEW(immArg, GetImm(1), RepInt, 1)
			ELSE NEW(immArg, 3, RepInt, 1)
			END;
			opcode.argStructure := ArgImm;
			opcode.arg1 := immArg;
			opcode.instr := opINT
		END Int;
	
		PROCEDURE Movs (opcode : IA32Opcode);
		BEGIN
			opcode.argStructure := ArgNone;
			IF opcode.op = 0A4H THEN opcode.instr := opMOVSB
			ELSIF (opcode.op = 0A5H) & opcode.opPrefix THEN opcode.instr := opMOVSW
			ELSIF opcode.op  = 0A5H THEN opcode.instr := opMOVSD
			ELSE Bug(opcode.op, 6)
			END
		END Movs;
	
		PROCEDURE Movx(opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
			byteArg : BOOLEAN;
		BEGIN
			byteArg := (opcode.op = 0B6H) OR (opcode.op = 0BEH);
			ModRm(regArg, secondArg);
			opcode.arg1 := regArg; opcode.arg2 := secondArg;
			IF (opcode.op = 0B6H) OR (opcode.op = 0B7H) THEN opcode.instr := opMOVZX;
			ELSE opcode.instr := opMOVSX;
			END;
			opcode.width := 1;
			IF secondArg IS IA32RegArg THEN
				opcode.argStructure := ArgRegReg;
				IF byteArg THEN
					opcode.width := 0
				ELSE
					secondArg(IA32RegArg).width := 2
				END
			ELSE
				opcode.argStructure := ArgRegMem;
				ASSERT(secondArg IS IA32MemArg);
				IF byteArg THEN secondArg(IA32MemArg).bytePtr := TRUE
				ELSE secondArg(IA32MemArg).wordPtr := TRUE
				END
			END 
		END Movx;
	
		PROCEDURE Cmps (opcode : IA32Opcode);
		BEGIN
			opcode.argStructure := ArgNone;
			IF opcode.op = 0A6H THEN opcode.instr := opCMPSB
			ELSIF (opcode.op = 0A7H) & opcode.opPrefix THEN opcode.instr := opCMPSB
			ELSIF opcode.op = 0A7H THEN opcode.instr := opCMPSW
			ELSE Bug(opcode.op, 7)
			END
		END Cmps;
	
		PROCEDURE Stos (opcode : IA32Opcode);
		BEGIN
			opcode.argStructure := ArgNone;
			IF opcode.op = 0AAH THEN opcode.instr := opSTOSB; 
			ELSIF (opcode.op = 0ABH) & opcode.opPrefix THEN opcode.instr := opSTOSW
			ELSIF opcode.op = 0ABH THEN opcode.instr := opSTOSD
			ELSE Bug(opcode.op, 8)
			END
		END Stos;
	
		PROCEDURE Lods (opcode : IA32Opcode);
		BEGIN
			opcode.argStructure := ArgNone;
			IF opcode.op = 0ACH THEN opcode.instr := opLODSB
			ELSIF opcode.op = 0ADH THEN
				IF opcode.opPrefix THEN opcode.instr := opLODSW ELSE opcode.instr := opLODSD END
			ELSE Bug(opcode.op, 9)
			END
		END Lods;
	
		PROCEDURE Scas (opcode : IA32Opcode);
		BEGIN
			opcode.argStructure := ArgNone;
			IF opcode.op = 0AEH THEN opcode.instr := opSCASB
			ELSIF (opcode.op = 0AFH) & opcode.opPrefix THEN opcode.instr := opSCASW
			ELSIF opcode.op = 0AFH THEN opcode.instr := opSCASD
			ELSE Bug(opcode.op, 10)
			END
		END Scas;
	
		PROCEDURE Imul (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
			immArg : IA32ImmArg;
		BEGIN
			opcode.width := 1;
			ModRm(regArg, secondArg);
			opcode.instr := opIMUL;
			opcode.arg1 := regArg;
			opcode.arg2 := secondArg;
			IF opcode.op = 69H THEN
				NEW(immArg, GetImm(4), RepInt, 4);
			ELSIF opcode.op = 6BH THEN NEW(immArg, GetImm(1), RepInt, 2) (* sign extended *)
			END;
			IF opcode.op = 0AFH THEN
				IF secondArg IS IA32RegArg THEN
					opcode.argStructure := ArgRegReg
				ELSIF secondArg IS IA32MemArg THEN
					opcode.argStructure := ArgRegMem
				END				
			ELSE
				IF secondArg IS IA32RegArg THEN
					opcode.argStructure := ArgRegRegImm
				ELSE
					ASSERT(secondArg IS IA32MemArg);
					opcode.argStructure := ArgRegMemImm
				END;
				opcode.arg3 := immArg
			END
		END Imul;

		PROCEDURE Ins (opcode : IA32Opcode);
		BEGIN
			opcode.argStructure := ArgNone;
			IF opcode.op =  6CH THEN opcode.instr := opINSB
			ELSIF opcode.opPrefix THEN opcode.instr := opINSW
			ELSE opcode.instr := opINSD
			END	
		END Ins;
	
		PROCEDURE Outs (opcode : IA32Opcode);
		BEGIN
			opcode.argStructure := ArgNone;
			IF opcode.op = 6EH THEN opcode.instr := opOUTSB
			ELSIF opcode.opPrefix THEN opcode.instr := opOUTSW
			ELSE opcode.instr := opOUTSD
			END
		END Outs;

		PROCEDURE Xchg (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.instr := opXCHG;
			IF (opcode.op >= 91H) & (opcode.op <= 97H) THEN (* xchg .ax, reg *)
				opcode.width := 1;
				opcode.argStructure := ArgRegReg;
				NEW(regArg, EAX);
				opcode.arg1 := regArg;
				NEW(regArg, opcode.op MOD 8);
				opcode.arg2 := regArg;
			ELSE
				ModRm(regArg, secondArg);
				IF opcode.op = 86H THEN opcode.width := 0
				ELSE opcode.width := 1
				END;
				opcode.arg1 := regArg;
				opcode.arg2 := secondArg;
				IF secondArg IS IA32RegArg THEN
					opcode.argStructure := ArgRegReg
				ELSE
					opcode.argStructure := ArgRegMem
				END
			END
		END Xchg;
	
		PROCEDURE MP (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			ModRm(regArg, arg);
			CASE regArg.reg OF
				0 : opcode.instr := opFXSAVE
				| 1 : opcode.instr := opFXRSTOR
				| 2 : opcode.instr := opLDMXCSR
				| 3 : opcode.instr := opSTMXCSR
				| 5 : opcode.instr := opLFENCE
				| 6 : opcode.instr := opMFENCE
				| 7 : opcode.instr := opSFENCE
			END;
			IF arg IS IA32RegArg THEN
				opcode.argStructure := ArgNone
			ELSE
				opcode.argStructure := ArgMem;
				opcode.arg1 := arg;
				IF regArg.reg = 7 THEN opcode.instr := opCLFLUSH END
			END
		END MP;
		
		PROCEDURE Grp1 (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
			immArg : IA32ImmArg;
		BEGIN
			ModRm(regArg, secondArg);
			IF opcode.op = 80H THEN
				opcode.width := 0;
				NEW(immArg, GetImm(1), RepInt, 1);
			ELSIF opcode.op = 81H THEN
				opcode.width := 1;
				IF opcode.opPrefix THEN NEW(immArg, GetImm(2), RepInt, 2) ELSE NEW(immArg, GetImm(4), RepInt, 4) END
			ELSE (* opcode.op = 83H, signed extends *)
				opcode.width := 1;
				NEW(immArg, GetImm(1), RepInt, 1);
			END;
			CASE regArg.reg OF
				0: opcode.instr := opADD
			  | 1: opcode.instr := opOR
			  | 2: opcode.instr := opADC
			  | 3: opcode.instr := opSBB
			  | 4: opcode.instr := opAND
			  | 5: opcode.instr := opSUB
			  | 6: opcode.instr := opXOR
			  | 7: opcode.instr := opCMP
			ELSE Bug(opcode.op, 11)
			END;
			IF secondArg IS IA32RegArg THEN
				opcode.argStructure := ArgRegImm
			ELSIF secondArg IS IA32MemArg THEN
				opcode.argStructure := ArgMemImm
			END;
			opcode.arg1 := secondArg;
			opcode.arg2 := immArg;
			IF (regArg.reg = 1) OR (regArg.reg = 4) OR (regArg.reg = 6) THEN immArg.rep := RepHex END
		END Grp1;

		PROCEDURE Grp2 (opcode : IA32Opcode);
		VAR
			regArg, newRegArg : IA32RegArg;
			arg: IA32Arg;
			immArg : IA32ImmArg;
		BEGIN
			ModRm(regArg, arg); opcode.arg1 := arg;
			CASE opcode.op OF
				0D0H : opcode.width := 0
				| 0D1H : opcode.width := 1
				| 0D2H : opcode.width := 0
				| 0D3H : opcode.width := 1
				| 0C0H : opcode.width := 0
				| 0C1H : opcode.width := 1
			END;
			IF (opcode.op = 0C0H) OR (opcode.op = 0C1H) THEN
				 NEW(immArg, GetImm(1), RepInt, 1); (* only 8 bit possible *)
				 IF arg IS IA32RegArg THEN opcode.argStructure := ArgRegImm
				 ELSE opcode.argStructure := ArgMemImm
				 END;
				 opcode.arg2 := immArg
			ELSE
				IF (opcode.op = 0D0H) OR (opcode.op = 0D1H) THEN
					opcode.argStructure := ArgRegImm;
					NEW(immArg, 1, RepInt, 1);
					opcode.arg2 := immArg;
				ELSIF (opcode.op = 0D2H) OR (opcode.op = 0D3H) THEN
					opcode.argStructure := ArgRegReg;
					NEW(newRegArg, CL);
					newRegArg.width := 1;
					opcode.arg2 := newRegArg
				END
			END;
			CASE regArg.reg OF
				0: opcode.instr := opROL
			  | 1: opcode.instr := opROR
			  | 2: opcode.instr := opRCL
			  | 3: opcode.instr := opRCR
			  | 4: opcode.instr := opSHL
			  | 5: opcode.instr := opSHR
			  | 7: opcode.instr := opSAR
			ELSE Bug(opcode.op, 12)
			END
		END Grp2;
	
		PROCEDURE Grp3 (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
			immArg : IA32ImmArg;
		BEGIN
			ModRm(regArg, secondArg); opcode.arg1 := secondArg;
			IF opcode.op = 0F6H THEN opcode.width := 0
			ELSE opcode.width := 1
			END;
			IF regArg.reg = 0 (* test *) THEN
				IF opcode.width = 0 THEN NEW(immArg, GetImm(1), RepInt, 1)
				ELSE
					IF opcode.opPrefix THEN NEW(immArg, GetImm(2), RepInt, 2)
					ELSE NEW(immArg, GetImm(4), RepInt, 4)
					END
				END;
				opcode.arg2 := immArg;
				IF secondArg IS IA32RegArg THEN opcode.argStructure := ArgRegImm
				ELSE opcode.argStructure := ArgMemImm
				END
			ELSE
				IF secondArg IS IA32RegArg THEN opcode.argStructure := ArgReg
				ELSE opcode.argStructure := ArgMem
				END				
			END;
			CASE regArg.reg OF 
				0: opcode.instr := opTEST
			  | 2: opcode.instr := opNOT
			  | 3: opcode.instr := opNEG
			  | 4: opcode.instr := opMUL
			  | 5: opcode.instr := opIMUL
			  | 6: opcode.instr := opDIV
			  | 7: opcode.instr := opIDIV
			ELSE Bug(opcode.op, 13)
			END;
		END Grp3;
	
		PROCEDURE Grp4 (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.width := 0;
			ModRm(regArg, secondArg); opcode.arg1 := secondArg;
			IF regArg.reg = 0 THEN opcode.instr := opINC
			ELSE opcode.instr := opDEC
			END;
			IF secondArg IS IA32MemArg THEN
				opcode.argStructure := ArgMem;
				secondArg(IA32MemArg).bytePtr := TRUE
			ELSE
				opcode.argStructure := ArgReg
			END
		END Grp4;
	
		PROCEDURE Grp5 (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			opcode.width := 1;
			ModRm(regArg, arg); opcode.arg1 := arg;
			IF regArg.reg = 0 THEN opcode.instr := opINC
			ELSIF regArg.reg = 1 THEN opcode.instr := opDEC
			ELSIF regArg.reg = 2 THEN opcode.instr := opCALL
			ELSIF regArg.reg = 3 THEN opcode.instr := opCALLFAR
			ELSIF regArg.reg = 4 THEN opcode.instr := opJMP
			ELSIF regArg.reg = 5 THEN opcode.instr := opJMPFAR
			ELSIF regArg.reg = 6 THEN opcode.instr := opPUSH
			ELSE Bug(regArg.reg, 14)
			END;
			IF arg IS IA32MemArg THEN
				opcode.argStructure := ArgMem
			ELSE
				opcode.argStructure := ArgReg
			END
		END Grp5;

		PROCEDURE Grp6 (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.width := 1;
			ModRm(regArg, secondArg); opcode.arg1 := secondArg;
			CASE regArg.reg OF
			|  0: opcode.instr := opSLDT
			|  1: opcode.instr := opSTR
			|  2: opcode.instr := opLLDT
			|  3: opcode.instr := opLTR
			|  4: opcode.instr := opVERR
			|  6: opcode.instr := opVERW
			ELSE Bug(opcode.op, 15)
			END;
			IF secondArg IS IA32RegArg THEN opcode.argStructure := ArgReg
			ELSE opcode.argStructure := ArgMem
			END
		END Grp6;
		
		PROCEDURE Grp7 (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.width := 1;
			ModRm(regArg, secondArg); opcode.arg1 := secondArg;
			CASE regArg.reg OF
			|  0: opcode.instr := opSGDT
			|  1: opcode.instr := opSIDT
			|  2: opcode.instr := opLGDT
			|  3: opcode.instr := opLIDT
			|  4: opcode.instr := opSMSW
			|  6: opcode.instr := opLMSW
			|  7: opcode.instr := opINVLPG
			ELSE Bug(opcode.op, 16)
			END;
			IF secondArg IS IA32RegArg THEN opcode.argStructure := ArgReg
			ELSE opcode.argStructure := ArgMem
			END
		END Grp7;
		
		PROCEDURE Grp8 (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
			immArg : IA32ImmArg;
		BEGIN
			opcode.width := 1;
			ModRm(regArg, secondArg); opcode.arg1 := secondArg;
			NEW(immArg, GetImm(1), RepInt, 1); opcode.arg2 := immArg;
			CASE regArg.reg OF
				4: opcode.instr := opBT
			  | 5: opcode.instr := opBTS
			  | 6: opcode.instr := opBTR
			  | 7: opcode.instr := opBTC
			ELSE Bug(opcode.op, 17)
			END;
			IF secondArg IS IA32RegArg THEN opcode.argStructure := ArgRegImm
			ELSE opcode.argStructure := ArgMemImm
			END
		END Grp8;
	
		PROCEDURE Grp9 (opcode: IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			opcode.width := 1;
			ModRm(regArg, secondArg); opcode.arg1 := secondArg;
			ASSERT(secondArg IS IA32MemArg);
			CASE regArg.reg OF
				1: opcode.instr := opCMPXCHG8B
			ELSE Bug(opcode.op, 18)
			END;
			opcode.argStructure := ArgMem
		END Grp9;

		PROCEDURE Float0 (opcode: IA32Opcode); (* op is 0D8H *)
		VAR
			statArg : IA32RegArg;
			secondArg : IA32Arg;
			fpReg : IA32SpecialRegArg;
		BEGIN
			ModRm(statArg, secondArg);
			IF secondArg IS IA32MemArg THEN (* memory *)
				opcode.argStructure := ArgMem;
				opcode.arg1 := secondArg;
				secondArg(IA32MemArg).fpSize := FPSizeSingle;
				CASE statArg.reg OF
					0: opcode.instr := opFADD
				  | 1: opcode.instr := opFMUL
				  | 2: opcode.instr := opFCOM
				  | 3: opcode.instr := opFCOMP
				  | 4: opcode.instr := opFSUB
				  | 5: opcode.instr := opFSUBR
				  | 6: opcode.instr := opFDIV
				  | 7: opcode.instr := opFDIVR
				ELSE Bug(statArg.reg, 25)
				END
			ELSE
				opcode.argStructure := ArgReg;
				NEW(fpReg, secondArg(IA32RegArg).reg);
				fpReg.specialKind := SRegFP;
				CASE statArg.reg OF
					0: opcode.instr := opFADD
				  | 1: opcode.instr := opFMUL
				  | 2: opcode.instr := opFCOM
				  | 3: opcode.instr := opFCOMP
				  | 4: opcode.instr := opFSUB
				  | 5: opcode.instr := opFSUBR
				  | 6: opcode.instr := opFDIV
				  | 7: opcode.instr := opFDIVR
				ELSE Bug(statArg.reg, 26)
				END
			END
		END Float0;

		PROCEDURE Float1 (opcode : IA32Opcode); (* op is 0D9H *)
		VAR
			statArg : IA32RegArg;
			secondArg : IA32Arg;
			stat : LONGINT;
		BEGIN
			ModRm(statArg, secondArg);
			IF secondArg IS IA32MemArg THEN
				opcode.argStructure := ArgMem;
				opcode.arg1 := secondArg;
				CASE statArg.reg OF
					0: opcode.instr := opFLD
				  | 2: opcode.instr := opFST
				  | 3: opcode.instr := opFSTP
				  | 4: opcode.instr := opFLDENV
				  | 5: opcode.instr := opFLDCW
				  | 6: opcode.instr := opFNSTENV
				  | 7: opcode.instr := opFNSTCW
				ELSE Bug(statArg.reg, 23)
				END
			ELSIF statArg.reg = 0 THEN
				opcode.argStructure := ArgReg;
				opcode.arg1 := secondArg;
				opcode.instr := opFLD
			ELSIF statArg.reg = 1 THEN
				opcode.argStructure := ArgReg;
				opcode.arg1 := secondArg;
				opcode.instr := opFXCH
			ELSE
				stat:= statArg.reg * 8 + secondArg(IA32RegArg).reg;
				IF stat = 10H THEN opcode.instr := opFNOP
				ELSE
					CASE stat OF
						20H: opcode.instr := opFCHS
					  | 21H: opcode.instr := opFABS
					  | 24H: opcode.instr := opFTST
					  | 25H: opcode.instr := opFXAM
					  | 28H: opcode.instr := opFLD1
					  | 29H: opcode.instr := opFLDL2T
					  | 2AH: opcode.instr := opFLDL2E
					  | 2BH: opcode.instr := opFLDPI
					  | 2CH: opcode.instr := opFLDLG2
					  | 2DH: opcode.instr := opFLDLN2
					  | 2EH: opcode.instr := opFLDZ
					  | 30H: opcode.instr := opF2XM1
					  | 31H: opcode.instr := opFYL2X
					  | 32H: opcode.instr := opFPTAN
					  | 33H: opcode.instr := opFPATAN
					  | 34H: opcode.instr := opFXTRACT
					  | 35H: opcode.instr := opFPREM1
					  | 36H: opcode.instr := opFDECSTP
					  | 37H: opcode.instr := opFINCSTP
					  | 38H: opcode.instr := opFPREM
					  | 39H: opcode.instr := opFYL2XP1
					  | 3AH: opcode.instr := opFSQRT
					  | 3BH: opcode.instr := opFSINCOS
					  | 3CH: opcode.instr := opFRNDINT
					  | 3DH: opcode.instr := opFSCALE
					  | 3EH: opcode.instr := opFSIN
					  | 3FH: opcode.instr := opFCOS
					ELSE Bug(stat, 23)
					END
				END
			END
		END Float1;

		PROCEDURE Float2 (opcode : IA32Opcode); (* op is 0DAH *)
			VAR stat, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
			setting : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			ModRm(setting, arg);
			IF arg IS IA32MemArg THEN
				opcode.argStructure := ArgMem;
				opcode.arg1 := arg;
				CASE setting.reg OF
					0: opcode.instr := opFIADD
				  | 1: opcode.instr := opFIMUL
				  | 2: opcode.instr := opFICOM
				  | 3: opcode.instr := opFICOMP
				  | 4: opcode.instr := opFISUB
				  | 5: opcode.instr := opFISUBR
				  | 6: opcode.instr := opFIDIV
				  | 7: opcode.instr := opFIDIVR
				ELSE Bug(setting.reg, 27)
				END
			ELSIF setting.reg = 5 THEN
				opcode.argStructure := ArgNone;
				opcode.instr := opFUCOMPP
			ELSE Bug(setting.reg, 27)
			END
		END Float2;
	
		PROCEDURE Float3 (opcode : IA32Opcode); (* op is 0DBH *)
		VAR
			setting : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			ModRm(setting, arg);
			IF arg IS IA32MemArg THEN
				opcode.argStructure := ArgMem;
				opcode.arg1 := arg;
				CASE setting.reg OF
					0: opcode.instr := opFILD
				  | 2: opcode.instr := opFIST
				  | 3: opcode.instr := opFISTP
				  | 5: opcode.instr := opFLD
				  | 7: opcode.instr := opFSTP
				ELSE Bug(setting.reg, 21)
				END
			ELSE
				opcode.argStructure := ArgNone;
				IF arg(IA32RegArg).reg = 2 THEN opcode.instr := opFNCLEX
				ELSIF arg(IA32RegArg).reg = 3 THEN opcode.instr := opFNINIT
				ELSE Bug(arg(IA32RegArg).reg, 22)
				END
			END
		END Float3;

		PROCEDURE Float4 (opcode : IA32Opcode); (* op is 0DCH *)
		VAR
			setting : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			ModRm(setting, arg);
			opcode.arg1 := arg;
			IF arg IS IA32MemArg THEN
				opcode.argStructure := ArgMem;
				CASE setting.reg OF
					0: opcode.instr := opFADD
				  | 1: opcode.instr := opFMUL
				  | 2: opcode.instr := opFCOM
				  | 3: opcode.instr := opFCOMP
				  | 4: opcode.instr := opFSUB
				  | 5: opcode.instr := opFSUBR
				  | 6: opcode.instr := opFDIV
				  | 7: opcode.instr := opFDIVR
				ELSE Bug(setting.reg, 34)
				END
			ELSE
				opcode.argStructure := ArgReg;
				CASE setting.reg OF
					0: opcode.instr := opFADD
				  | 1: opcode.instr := opFMUL
				  | 4: opcode.instr := opFSUBR
				  | 5: opcode.instr := opFSUB
				  | 6: opcode.instr := opFDIVR
				  | 7: opcode.instr := opFDIV
				ELSE Bug(setting.reg, 35)
				END
			END
		END Float4;

		PROCEDURE Float5 (opcode : IA32Opcode);	(* op is 0DDH *)
		VAR
			setting : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			ModRm(setting, arg);
			opcode.arg1:= arg;
			IF arg IS IA32MemArg THEN
				opcode.argStructure := ArgMem;
				CASE setting.reg OF
					0: opcode.instr := opFLD
				  | 2: opcode.instr := opFST
				  | 3: opcode.instr := opFSTP
				  | 4: opcode.instr := opFRSTOR
				  | 6: opcode.instr := opFNSAVE
				  | 7: opcode.instr := opFNSTSW
				ELSE Bug(setting.reg, 29)
				END
			ELSE
				opcode.argStructure := ArgReg;
				CASE setting.reg OF
					0: opcode.instr := opFFREE
				  | 2: opcode.instr := opFST
				  | 3: opcode.instr := opFSTP
				  | 4: opcode.instr := opFUCOM
				  | 5: opcode.instr := opFUCOMP
				ELSE Bug(setting.reg, 30)
				END
			END
		END Float5;

		PROCEDURE Float6(opcode : IA32Opcode); (* op is 0DEH *)
		VAR
			setting : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			ModRm(setting, arg);
			opcode.arg1 := arg;
			IF arg IS IA32MemArg THEN
				opcode.argStructure := ArgMem;
				CASE setting.reg OF
					0: opcode.instr := opFIADD
				  | 1: opcode.instr := opFIMUL
				  | 2: opcode.instr := opFICOM
				  | 3: opcode.instr := opFICOMP
				  | 4: opcode.instr := opFISUB
				  | 5: opcode.instr := opFISUBR
				  | 6: opcode.instr := opFIDIV
				  | 7: opcode.instr := opFIDIVR
				ELSE Bug(setting.reg, 31)
				END
			ELSE
				opcode.argStructure := ArgReg;
				CASE setting.reg OF
					0: opcode.instr := opFADDP
				  | 1: opcode.instr := opFMULP
				  | 3: opcode.instr := opFCOMPP
				  | 4: opcode.instr := opFSUBRP
				  | 5: opcode.instr := opFSUBP
				  | 6: opcode.instr := opFDIVRP
				  | 7: opcode.instr := opFDIVP
				ELSE Bug(setting.reg, 32)
				END;
			END
		END Float6;
		
		PROCEDURE Float7(opcode : IA32Opcode); (* op is 0DFH *)
		VAR
			setting : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			ModRm(setting, arg);
			opcode.arg1 := arg;
			IF arg IS IA32MemArg THEN
				opcode.argStructure := ArgMem;
				CASE setting.reg OF
					0, 5: opcode.instr := opFILD
				  | 2: opcode.instr := opFIST
				  | 3, 7: opcode.instr := opFISTP
				  | 4: opcode.instr := opFBLD
				  | 6: opcode.instr := opFBSTP
				ELSE Bug(setting.reg, 33)
				END
			ELSIF setting.reg = 4 THEN
				opcode.argStructure := ArgReg;
				opcode.arg1(IA32RegArg).reg := AX;
				opcode.arg1(IA32RegArg).width := 2;
				opcode.instr := opFNSTSW
			ELSE Bug(setting.reg, 33)
			END
		END Float7;

	
		PROCEDURE Cmov (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			secondArg : IA32Arg;
		BEGIN
			ModRm(regArg, secondArg);
			opcode.arg1 := regArg;
			opcode.arg2 := secondArg;
			opcode.width := 1;
			IF secondArg IS IA32RegArg THEN opcode.argStructure := ArgRegReg
			ELSE opcode.argStructure := ArgRegMem
			END;
			CASE opcode.op OF
				40H: opcode.instr := opCMOVO
			  | 41H: opcode.instr := opCMOVNO
			  | 42H: opcode.instr := opCMOVB
			  | 43H: opcode.instr := opCMOVNB
			  | 44H: opcode.instr := opCMOVZ
			  | 45H: opcode.instr := opCMOVNZ
			  | 46H: opcode.instr := opCMOVBE
			  | 47H: opcode.instr := opCMOVNBE
			  | 48H: opcode.instr := opCMOVS
			  | 49H: opcode.instr := opCMOVNS
			  | 4AH: opcode.instr := opCMOVP
			  | 4BH: opcode.instr := opCMOVNP
			  | 4CH: opcode.instr := opCMOVL
			  | 4DH: opcode.instr := opCMOVNL
			  | 4EH: opcode.instr := opCMOVLE
			  | 4FH: opcode.instr := opCMOVNLE
			ELSE Bug(opcode.op, 28)
			END
		END Cmov;
		
		PROCEDURE PushPop2 (opcode : IA32Opcode);
		VAR regArg : IA32RegArg; reg : LONGINT;
		BEGIN
			CASE opcode.op OF
				0A0H: opcode.instr := opPUSH; reg := FS
				| 0A1H: opcode.instr := opPOP; reg := FS
				| 0A8H: opcode.instr := opPUSH; reg := GS
				| 0A9H: opcode.instr := opPOP; reg := GS
			ELSE Bug(opcode.op, 35)
			END;
			NEW(regArg, reg);
			opcode.argStructure := ArgReg;
			opcode.arg1 := regArg
		END PushPop2;
		
		PROCEDURE Cmpxchg (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			opcode.instr := opCMPXCHG;
			ModRm(regArg, arg);
			opcode.arg1 := arg;
			opcode.arg2 := regArg;
			IF opcode.op = 0B1H THEN opcode.width := 1
			ELSE opcode.width := 0
			END;
			IF arg IS IA32RegArg THEN
				opcode.argStructure := ArgRegReg
			ELSE
				opcode.argStructure := ArgMemReg
			END
		END Cmpxchg;
		
		PROCEDURE Ldseg (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			arg2 : IA32Arg;
		BEGIN
			ModRm(regArg, arg2);
			IF opcode.op = 0B2H THEN opcode.instr := opLSS
			ELSIF opcode.op = 0B4H THEN opcode.instr := opLFS
			ELSE opcode.instr := opLGS
			END;
			opcode.argStructure := ArgRegMem;
			opcode.arg1 := regArg;
			opcode.arg2 := arg2;
		END Ldseg;
		
		PROCEDURE Xadd (opcode : IA32Opcode);
		VAR
			regArg : IA32RegArg;
			arg : IA32Arg;
		BEGIN
			ModRm(regArg, arg);
			opcode.instr := opXADD;
			opcode.arg1 := arg;
			opcode.arg2 := regArg;
			IF opcode.op = 0C1H THEN opcode.width := 1
			ELSE opcode.width := 0
			END;
			IF arg IS IA32RegArg THEN
				opcode.argStructure := ArgRegReg
			ELSE
				opcode.argStructure := ArgMemReg
			END
		END Xadd;
		
		PROCEDURE Bswap (opcode : IA32Opcode);
		VAR regArg : IA32RegArg;
		BEGIN
			opcode.instr := opBSWAP;
			NEW(regArg, opcode.op-0C8H);
			opcode.argStructure := ArgReg;
			opcode.arg1 := regArg
		END Bswap;
		
		PROCEDURE Escape (opcode : IA32Opcode);
		BEGIN
			opcode.op := ORD(ReadChar());
			CASE opcode.op OF
				0: 
					Grp6(opcode)
			  | 1: 
					Grp7(opcode)
			  | 2: 
					Lar(opcode)
			  | 3:
					Lsl(opcode)
			  | 6: 
			  		opcode.argStructure := ArgNone;
					opcode.instr := opCLTS
			  | 8:
			  		opcode.argStructure := ArgNone;
					opcode.instr := opINVD
			  | 9:
					opcode.instr := opWBINVD
			  | 20H..24H, 26H:
					Mov2(opcode)
			  | 30H:
					opcode.argStructure := ArgNone;
					opcode.instr := opWRMSR
			  | 31H:
			  		opcode.argStructure := ArgNone;
					opcode.instr := opRDTSC
			  | 32H:
			  		opcode.argStructure := ArgNone;
					opcode.instr := opRDMSR
			  | 33H:
			  		opcode.argStructure := ArgNone;
					opcode.instr := opRDPMC
			  | 40H..4FH:
					Cmov(opcode)
			  | 80H..8FH:
					Jcc2(opcode)
			  | 90H..9FH:
					Setcc(opcode)
			  | 0A0H, 0A1H, 0A8H, 0A9H:
					PushPop2(opcode)
			  | 0A2H:
					opcode.argStructure := ArgNone;
					opcode.instr := opCPUID
			  | 0A3H, 0ABH, 0B3H, 0BBH..0BDH:
					Bit(opcode)
			  | 0A4H, 0A5H, 0ACH, 0ADH:
					Shift(opcode)
			  | 0AEH:
			  		MP(opcode)
			  | 0AFH:
					Imul(opcode)
			  | 0B0H,0B1H:
					Cmpxchg(opcode)
			  | 0B2H, 0B4H, 0B5H:
					Ldseg(opcode)
			  | 0B6H, 0B7H, 0BEH, 0BFH:
					Movx(opcode)
			  | 0BAH:
					Grp8(opcode)
			  | 0C0H,0C1H:
					Xadd(opcode)
			  | 0C7H:
					Grp9(opcode)
			  | 0C8H..0CFH:
					Bswap(opcode)
			ELSE Bug(opcode.op, 19)
			END
		END Escape;
	
		PROCEDURE DecodeThis(opcode : Opcode);
		VAR
			op : IA32Opcode;
		BEGIN			
			op := opcode(IA32Opcode);
			DoPrefixes(op);
			op.op := ORD(op.opcodeByte[0]);
			AosOut.String("op.op = "); AosOut.Hex(op.op, 0); AosOut.Ln; 
			CASE op.op OF
				0..5: 
						Add(op);
				  | 6, 0EH, 16H, 1EH: 
						Push(op)
				  | 7, 17H, 1FH:
				 		Pop(op)
				  | 8..0DH:
						Or(op)
				  | 0FH:
						Escape(op)
				  | 10H..15H:
						Adc(op)
				  | 18H..1DH:
						Sbb(op)
				  | 20H..25H:
						And(op)
				  | 27H:
						op.argStructure := ArgNone;
						op.instr := opDAA;
				  | 28H..2DH:
						Sub(op)
				  | 2FH:
						op.argStructure := ArgNone;
						op.instr := opDAS;
				  | 30H..35H:
						Xor(op)
				  | 37H:
						op.argStructure := ArgNone;
						op.instr := opAAA;
				  | 38H..3DH:
						Cmp(op)
				  | 3FH:
						op.argStructure := ArgNone;
						op.instr := opAAS;
				  | 40H..47H:
						Inc(op)
				  | 48H..4FH:
						Dec(op)
				  | 50H..57H, 60H, 68H, 6AH:
						Push(op)
				  | 58H..5FH, 61H:
						Pop(op)
				  | 62H:
						Bound(op)
				  | 69H, 6BH:
						Imul(op)
				  | 6CH, 6DH:
						Ins(op)
				  | 6EH, 06FH:
						Outs(op)
				  | 70H..7FH:
						Jcc(op)
				  | 80H..81H, 83H:
						Grp1(op)
				  | 84H..85H:
						Test(op)
				  | 86H..87H, 91H..97H:
						Xchg(op)
				  | 88H..8CH, 8EH, 0A0H..0A3H, 0B0H..0BFH:
						Mov(op)
				  | 8DH:
						Lea(op)
				  | 8FH, 9DH:
						Pop(op)
				  | 90H:
						op.argStructure := ArgNone;
						op.instr := opNOP;
				  | 98H:
						op.argStructure := ArgNone;
						IF op.opPrefix THEN op.instr := opCBW ELSE op.instr := opCWDE END
				  | 99H:
				  		op.argStructure := ArgNone;
						IF op.opPrefix THEN op.instr := opCWD ELSE op.instr := opCDQ END
				  | 9AH:
						Call(op)
				  | 9BH:
				  		op.argStructure := ArgNone;
						op.instr := opWAIT;
						opcodeBeforeWait := previousOpcode (* WAIT hack *)
				  | 9CH:
						Push(op)
				  | 9EH:
						op.argStructure := ArgNone;
						op.instr := opSAHF;
				  | 9FH:
						op.argStructure := ArgNone;
						op.instr := opLAHF;
				  | 0A4H..0A5H:
						Movs(op)
				  | 0A6H..0A7H:
						Cmps(op)
				  | 0A8H..0A9H:
						Test(op)
				  | 0AAH..0ABH:
						Stos(op)
				  | 0ACH..0ADH:
						Lods(op)
				  | 0AEH..0AFH:
						Scas(op)
				  | 0C0H..0C1H:
						Grp2(op)
				  | 0C2H..0C3H, 0CAH, 0CBH:
						Ret(op)
				  | 0C4H:
						Les(op)
				  | 0C5H:
						Lds(op)
				  | 0C6H..0C7H:
						Mov(op)
				  | 0C8H:
						Enter(op)
				  | 0C9H:
						op.argStructure := ArgNone;
						op.instr := opLEAVE;
				  | 0CCH..0CDH:
						Int(op)
				  | 0CEH:
						op.argStructure := ArgNone;
						op.instr := opINTO;
				  | 0CFH:
						op.argStructure := ArgNone;
						op.instr := opIRET;
				  | 0D0H..0D3H:
						Grp2(op)
				  | 0D4H:
						op.argStructure := ArgNone;
						opcode.instr := opAAM;
				  | 0D5H:
						op.argStructure := ArgNone;
						opcode.instr := opAAD;
				  | 0D7H:
						op.argStructure := ArgNone;
						op.instr := opXLAT;
				  | 0D8H:
						Float0(op)
				  | 0D9H, 0D6H:
						Float1(op)
				  | 0DAH:
						Float2(op)
				  | 0DBH:
						Float3(op)
				  | 0DCH:
						Float4(op)
				  | 0DDH:
						Float5(op)
				  | 0DEH:
						Float6(op)
				  | 0DFH:
						Float7(op)
				  | 0E0H..0E3H:
						Loop(op) (* and jcxz *)
				  | 0E4H..0E7H, 0ECH..0EFH:
						InOut(op)
				  | 0E8H:
						Call(op)
				  | 0E9H..0EBH:
						Jmp(op)
				  | 0F0H:
						op.argStructure := ArgNone;
						op.instr := opLOCK
				  | 0F2H:
						op.argStructure := ArgNone;
						op.instr := opREPNE
				  | 0F4H:
						op.argStructure := ArgNone;
						op.instr := opHLT
				  | 0F5H:
						op.argStructure := ArgNone;
						op.instr := opCMC
				  | 0F6H..0F7H:
						Grp3(op)
				  | 0F8H:
						op.argStructure := ArgNone;
						op.instr := opCLC
				  | 0F9H:
						op.argStructure := ArgNone;
						op.instr := opSTC
				  | 0FAH:
						op.argStructure := ArgNone;
						op.instr := opCLI
				  | 0FBH:
						op.argStructure := ArgNone;
						op.instr := opSTI
				  | 0FCH:
						op.argStructure := ArgNone;
						op.instr := opCLD
				  | 0FDH:
						op.argStructure := ArgNone;
						op.instr := opSTD
				  | 0FEH:
						Grp4(op)
				  | 0FFH:
						Grp5(op)
				ELSE
					AosOut.String("Opcode not recognized: "); AosOut.Hex(ORD(op.opcodeByte[0]), -1); AosOut.Ln;
					completed := TRUE
				END;
				(* WAIT hack *)
				IF (op.instr # opWAIT) & (opcodeBeforeWait # NIL) THEN
					IF (op.instr = opFNCLEX) OR (op.instr = opFNSTSW) OR (op.instr = opFNSTENV) OR
							(op.instr = opFNSTCW) OR (op.instr = opFNSAVE) OR (op.instr = opFNINIT) THEN
						opcodeBeforeWait.next := op; (* remove WAIT opcode *)
						InsertBytesAtBufferHead(previousOpcode.code); (* insert WAIT opcode bytes into this opcode *)
						DEC(op.instr) (* set opFxxx to opFNxxx instead *)
					END;
					opcodeBeforeWait := NIL
				END;
				previousOpcode := op
				(* end of WAIT hack *)
		END DecodeThis;
		
		PROCEDURE NewOpcode() : Opcode;
		VAR
			opcode : IA32Opcode;
		BEGIN
			NEW(opcode, currentProc, outputStreamWriter);
			opcode.decoder := SELF;
			RETURN opcode
		END NewOpcode;
	END IA32Decoder;

	Info = OBJECT
		VAR
			name* : AosModules.Name;
	END Info;
	
	FieldInfo* = OBJECT (Info)
		VAR
			offset, mode, kind, type, dim, tdadr : LONGINT;
			markerPositions, temp : POINTER TO ARRAY OF RECORD
								pos : LONGINT;
								marker : WMTextView.PositionMarker
								END;
			nextMarker, markerSize : LONGINT;
			markersCreated : BOOLEAN;
			procedure : ProcedureInfo;
			
		PROCEDURE WriteType(w : AosIO.Writer);
		BEGIN
			IF mode = VarModeIndirect THEN w.String("VAR ") END;
			IF kind = VarArray THEN w.String("ARRAY "); w.Int(dim, 0); w.String(" OF ") END;
			CASE type OF
				1H : w.String("BYTE")
				| 2H : w.String("BOOLEAN")
				| 3H : w.String("CHAR")
				| 4H : w.String("SHORTINT")
				| 5H : w.String("INTEGER")
				| 6H : w.String("LONGINT")
				| 7H : w.String("REAL")
				| 8H : w.String("LONGREAL")
				| 9H : w.String("SET")
				| 0AH : w.String("?")
				| 0BH : w.String("?")
				| 0CH : w.String("?")
				| 0DH : w.String("PTR")
				| 0EH : w.String("PROC")
				| 0FH : w.String("STRING")
				| 10H : w.String("HUGEINT")
				| 16H : w.String("RECORD")
				| 1DH : w.String("OBJECT")
			ELSE
			END;			
		END WriteType;
			
		PROCEDURE ToString(w : AosIO.Writer);
		BEGIN
			w.String(name);
			w.String(" (");
			WriteType(w);
			w.String(") [");
			w.Int(offset, 0);
			w.String("]")
		END ToString;
		
		PROCEDURE AddMarkerPosition* (pos : LONGINT);
		VAR i : LONGINT;
		BEGIN
			markersCreated := FALSE;
			IF markerPositions = NIL THEN markerSize := 5; NEW(markerPositions, markerSize); nextMarker := 0 END;
			IF nextMarker >= LEN(markerPositions) THEN
				temp := markerPositions;
				markerSize := 2*markerSize;
				NEW(markerPositions, markerSize);
				FOR i := 0 TO nextMarker-1 DO
					markerPositions[i] := temp[i]
				END
			END;
			markerPositions[nextMarker].pos := pos;
			INC(nextMarker)
		END AddMarkerPosition;
		
		PROCEDURE CreateMarkers (tv : WMTextView.TextView);
		VAR i : LONGINT;
		BEGIN
			FOR i := 0 TO nextMarker-1 DO
				markerPositions[i].marker := tv.CreatePositionMarker();
				markerPositions[i].marker.SetPosition(markerPositions[i].pos);
				markerPositions[i].marker.SetVisible(FALSE);
				markerPositions[i].marker.Load("AosDecoderRes.zip://VariablePositionIcon.png")
			END;
			markersCreated := TRUE
		END CreateMarkers;
		
		PROCEDURE ToggleMarkers(enabled : BOOLEAN);
		VAR i : LONGINT;
		BEGIN
			IF markersCreated THEN
				FOR i := 0 TO nextMarker-1 DO
					markerPositions[i].marker.SetVisible(enabled)
				END
			END
		END ToggleMarkers;
	END FieldInfo;
		
	FieldArray = POINTER TO ARRAY OF FieldInfo;
	
	ProcedureInfo* = OBJECT (Info)
		VAR
			codeOffset, codeSize, retType, index : LONGINT;
			fields : FieldArray;
			fieldCount : LONGINT;
			method : BOOLEAN;
			
		PROCEDURE &New (n : AosModules.Name; ofs, idx : LONGINT);
		BEGIN
			name := n;
			codeOffset := ofs;
			index := idx;
			method := FALSE;
			NEW(fields, 5)
		END New;
			
		PROCEDURE AddField (fldInfo : FieldInfo);
		VAR
			oldFlds : FieldArray;
			i, len : LONGINT;
		BEGIN
			IF fieldCount = LEN(fields) THEN
				oldFlds := fields;
				len := LEN(fields);
				NEW(fields, 2 * len);
				FOR i := 0 TO len-1 DO fields[i] := oldFlds[i] END;
			END;
			fields[fieldCount] := fldInfo;
			INC(fieldCount)
		END AddField;
		
		PROCEDURE GetFieldAtOffset*(offset : LONGINT) : FieldInfo;
		VAR
			i : LONGINT;
		BEGIN
			i := 0;
			WHILE i < fieldCount DO
				IF fields[i].offset = offset THEN RETURN fields[i] END;
				INC(i)
			END;
			RETURN NIL
		END GetFieldAtOffset;
	END ProcedureInfo;
	
	ProcedureArray = POINTER TO ARRAY OF ProcedureInfo;
	
	TypeInfo* = OBJECT (Info)
		VAR 
			procedures : ProcedureArray;
			fields : FieldArray;
			procedureCount, fieldCount : LONGINT;
			
		PROCEDURE &New (n : AosModules.Name);
		BEGIN
			name := n;
			procedureCount := 0;
			fieldCount := 0;
			NEW(procedures, 5);
			NEW(fields, 5)
		END New;
	
		PROCEDURE AddProcedure (procInfo : ProcedureInfo);
		VAR
			oldProcs : ProcedureArray;
			i, len : LONGINT;
		BEGIN
			IF procedureCount = LEN(procedures) THEN
				oldProcs := procedures;
				len := LEN(procedures);
				NEW(procedures, 2 * len);
				FOR i := 0 TO len-1 DO procedures[i] := oldProcs[i] END;
			END;
			procedures[procedureCount] := procInfo;
			INC(procedureCount)
		END AddProcedure;

		PROCEDURE AddField (fldInfo : FieldInfo);
		VAR
			oldFields : FieldArray;
			i, len : LONGINT;
		BEGIN
			IF fieldCount = LEN(fields) THEN
				oldFields := fields;
				len := LEN(fields);
				NEW(fields, 2 * len);
				FOR i := 0 TO len-1 DO fields[i] := oldFields[i] END;
			END;
			fields[fieldCount] := fldInfo;
			INC(fieldCount)
		END AddField;
	END TypeInfo;	
	
	TypeArray = POINTER TO ARRAY OF TypeInfo;
	
	ModuleInfo* = OBJECT (Info)
		VAR
			module : AosModules.Module;
			representationMode : LONGINT;
			procedures : ProcedureArray; (* references to all procedures, including methods *)
			procedureCount : LONGINT;
			types : TypeArray;
			typeCount : LONGINT;
			treeView : WMTrees.TreeView;
			tree : WMTrees.Tree;
			treePanel, lastDAssPanel : WMStandardComponents.Panel;
			resizerH : WMStandardComponents.Resizer;
			editor : WMEditors.Editor;
			textWriter : AosTextUtilities.TextWriter;
			currentProcInfo : ProcedureInfo;
			markPC : LONGINT;
			ext : Extension;
			codeScaleCallback: CodeScaleCallback;
		
		PROCEDURE IsExceptionHandled(pc: LONGINT): BOOLEAN;
		VAR
			i: LONGINT;
			entry: AosModules.ExceptionTableEntry;
		BEGIN
			IF (module # NIL) & (module.exTable # NIL) THEN			
				FOR i := 0 TO LEN(module.exTable) - 1 DO
					entry := module.exTable[i];
					IF (entry.pcFrom <= pc) & (entry.pcTo > pc) THEN 							
						RETURN TRUE;
					END
				END
			END;
			RETURN FALSE;
		END IsExceptionHandled;
			
		PROCEDURE GetOpcodes (proc : ProcedureInfo) : Opcode;
		VAR
			reader : AosMemoryReader.Reader;
			ofs : LONGINT;
			decoder : Decoder;
		BEGIN
			ofs := SYSTEM.ADR(module.code[proc.codeOffset]);
			NEW(reader, ofs, proc.codeSize);
			decoder := GetDecoder(ext, reader);
			RETURN decoder.Decode(proc)
		END GetOpcodes;
		
		PROCEDURE AddProcedure (procInfo : ProcedureInfo);
		VAR
			oldProcs : ProcedureArray;
			i, len : LONGINT;
		BEGIN
			IF procedureCount = LEN(procedures) THEN
				oldProcs := procedures;
				len := LEN(procedures);
				NEW(procedures, 2 * len);
				FOR i := 0 TO len-1 DO procedures[i] := oldProcs[i] END
			END;
			procedures[procedureCount] := procInfo;
			INC(procedureCount)
		END AddProcedure;
		
		PROCEDURE FindEntryByOffset (ofs : LONGINT) : LONGINT;
		VAR
			i : LONGINT;
		BEGIN
			i := 0;
			WHILE i < module.entries DO
				IF ofs = module.entry[i] THEN RETURN i END;
				INC(i)
			END;
			RETURN -1
		END FindEntryByOffset;
		
		PROCEDURE GetProcedureByIndex (idx : LONGINT) : ProcedureInfo;
		VAR
			i : LONGINT;
		BEGIN
			i := 0;
			WHILE i < procedureCount DO
				IF idx = procedures[i].index THEN
					RETURN procedures[i]
				END;
				INC(i)
			END;
			RETURN NIL
		END GetProcedureByIndex;
		
		PROCEDURE DecodeRefs(reader : AosIO.Reader);		
		VAR idx, thisIdx : LONGINT;
			procInfo : ProcedureInfo;
			fldInfo : FieldInfo;
			ch : CHAR;
			ofs, prevOfs, retType, entry : LONGINT;
			name : AosModules.Name;
		
		BEGIN
			ASSERT(module.codeSize > 0);
			(* body ref *)
			IF reader.Available() > 0 THEN
				ch := reader.Get();
				ASSERT(ch = OFFHdrBodyRef);
				reader.RawNum(ofs);
				reader.RawString(name);
				ASSERT(name = "$$");
				name := "$$BODY";
				NEW(procInfo, name, 0, module.entries); (* indexes below this are reserved by procedures/methods part of entries *)
				AddProcedure(procInfo);
				fldInfo := DecodeField(reader);
				WHILE fldInfo # NIL DO
					procInfo.AddField(fldInfo);
					fldInfo := DecodeField(reader);
				END
			END;
			idx := module.entries+1; (* start after entries and BODY *)
			ofs := 0;
			WHILE (reader.Available() > 0) & (reader.Peek() = OFFHdrProcRef) DO
				ch := reader.Get();
				prevOfs := ofs;
				reader.RawNum(ofs);
				IF (codeScaleCallback # NIL) THEN codeScaleCallback(ofs) END;
				ASSERT(procInfo # NIL);
				procInfo.codeSize := ofs - prevOfs; (* set size of previous procedure *)
				ch := reader.Get();
				retType := SYSTEM.VAL(LONGINT, reader.Get());
				ch := reader.Get(); ch := reader.Get();
				reader.RawString(name);
				entry := FindEntryByOffset(ofs);
				procInfo := NIL;
				IF entry >= 0 THEN
					procInfo := GetProcedureByIndex(entry);
					thisIdx := entry
				ELSE
					thisIdx := idx;
					INC(idx)
				END;
				IF procInfo = NIL THEN
					NEW(procInfo, name, ofs, thisIdx);
					AddProcedure(procInfo)
				ELSE
					procInfo.name := name
				END;
				procInfo.retType := retType;
				fldInfo := DecodeField(reader);
				WHILE fldInfo # NIL DO
					procInfo.AddField(fldInfo);
					fldInfo := DecodeField(reader);
				END				
			END;
			ASSERT(procInfo # NIL);
			procInfo.codeSize := module.codeSize - ofs; (* set size of last procedure *)
		END DecodeRefs;
		
		PROCEDURE DecodeTypes;
		BEGIN			
		END DecodeTypes;

		PROCEDURE DecodeField(reader : AosIO.Reader) : FieldInfo;
		VAR
			fieldInfo : FieldInfo;
			ch : CHAR;
		BEGIN
			NEW(fieldInfo);
			IF reader.Peek() = 1X THEN
				fieldInfo.mode := VarModeDirect
			ELSIF reader.Peek() = 3X THEN
				fieldInfo.mode := VarModeIndirect
			ELSE
				RETURN NIL (* not a field *)			
			END;
			ch := reader.Get();
			fieldInfo.type := SYSTEM.VAL(LONGINT, reader.Get());
			IF fieldInfo.type <= 10H THEN
				fieldInfo.kind := VarType;
			ELSIF (fieldInfo.type >= 81H) & (fieldInfo.type <= 90H) THEN
				fieldInfo.kind := VarArray;
				DEC(fieldInfo.type, 80H);
				reader.RawNum(fieldInfo.dim)
			ELSE
				ASSERT((fieldInfo.type = 16H) OR (fieldInfo.type = 1DH));
				fieldInfo.kind := VarRecord;
				reader.RawNum(fieldInfo.tdadr)
			END;
			reader.RawNum(fieldInfo.offset);
			reader.RawString(fieldInfo.name);
			RETURN fieldInfo
		END DecodeField;
		
		PROCEDURE FindProcedureFromPC(pc : LONGINT) : ProcedureInfo;
		VAR
			i : LONGINT;
			currentProc : ProcedureInfo;
		BEGIN
			ASSERT(procedures # NIL);
			WHILE i < procedureCount DO
				IF (pc >= procedures[i].codeOffset) & (pc < procedures[i].codeOffset + procedures[i].codeSize) THEN
					RETURN procedures[i]
				END;
				INC(i)
			END;
			RETURN NIL
		END FindProcedureFromPC;
				
		PROCEDURE Init;
		BEGIN
			NEW(module);
			procedureCount := 0;
			markPC := -1;
			NEW(procedures, 5);
			codeScaleCallback := NIL;
			ext := ""
		END Init;
		
		PROCEDURE ClickNode(sender, data : ANY);
		VAR
			d: ANY;
			i : LONGINT;
			procInfo: ProcedureInfo;
			
			PROCEDURE ChangeProcedure(proc : ProcedureInfo);
			BEGIN
				IF editor # NIL THEN lastDAssPanel.RemoveContent(editor) END;
				OutlineProcedure(proc, lastDAssPanel)
			END ChangeProcedure;
			
		BEGIN
			lastDAssPanel.DisableUpdate;
			IF (data # NIL) & (data IS WMTrees.TreeNode) THEN
				tree.Acquire;
				d := tree.GetNodeData(data(WMTrees.TreeNode));
				tree.Release;
				IF d # NIL THEN
					IF d IS ProcedureInfo THEN ChangeProcedure(d(ProcedureInfo))
					ELSIF d IS FieldInfo THEN
						IF (currentProcInfo = NIL) OR (d(FieldInfo).procedure # currentProcInfo) THEN ChangeProcedure(d(FieldInfo).procedure)
						ELSE
							FOR i := 0 TO currentProcInfo.fieldCount-1 DO
								currentProcInfo.fields[i].ToggleMarkers(FALSE)
							END;
						END;
						d(FieldInfo).ToggleMarkers(TRUE);
					ELSIF d IS TypeInfo THEN
						IF editor # NIL THEN lastDAssPanel.RemoveContent(editor) END;
						OutlineType(d(TypeInfo), lastDAssPanel)
					ELSIF d IS ModuleInfo THEN
						IF editor # NIL THEN lastDAssPanel.RemoveContent(editor) END;
						OutlineModule(d(ModuleInfo), lastDAssPanel)
					ELSE
						HALT(99)
					END
				END
			END;
			lastDAssPanel.EnableUpdate;
			lastDAssPanel.Invalidate			
		END ClickNode;
		
		PROCEDURE OutlineNamedProcedure(name : AosModules.Name);
		VAR found : BOOLEAN;
			i : LONGINT;
		BEGIN
			i := 0; found := FALSE;
			WHILE ~found & (i < procedureCount) DO
				IF procedures[i].name = name THEN
					found := TRUE;
					OutlineProcedure(procedures[i], lastDAssPanel)
				END;
				INC(i)
			END;
			IF ~found THEN
				AosOut.String("AosDecoder: ERROR: OutlineNamedProcedure: Procedure not found: "); AosOut.String(name); AosOut.Ln
			END
		END OutlineNamedProcedure;
		
		PROCEDURE OutlinePC (pc : LONGINT);
		VAR proc : ProcedureInfo;
		BEGIN
			proc := FindProcedureFromPC(pc);
			IF proc # NIL THEN
					markPC := pc;
					OutlineProcedure(proc, lastDAssPanel);
					markPC := -1;
			ELSE
				AosOut.String("AosDecoder: ERROR: OutlinePC: Procedure not found at PC: "); AosOut.Hex(pc, 0); AosOut.Ln
			END
		END OutlinePC;
		
		PROCEDURE InitializeOutline (panel : WMStandardComponents.Panel) : AosIO.Writer;
		VAR
			avgTabSize : LONGINT;
			tabStops : WMTextView.CustomTabStops;
			tabPositions : WMTextView.TabPositions;
		BEGIN
			NEW(editor); editor.alignment.Set(WMComponents.AlignClient);
			panel.AddContent(editor);

			panel.Reset(SELF, NIL);
			panel.AlignSubComponents;
			
			NEW(tabPositions, 4);
			avgTabSize := editor.bounds.GetWidth() DIV 14; (* 5 columns, 2 have double width *)
			tabPositions[0] := 2*avgTabSize; tabPositions[1] := 6*avgTabSize; tabPositions[2] := 8*avgTabSize; tabPositions[3] := 11*avgTabSize;
			NEW(tabStops, tabPositions);
			editor.tv.SetTabStops(tabStops);
			editor.tv.SetWrapMode({});

			NEW(textWriter, editor.text);
			RETURN textWriter.GetWriter()
		END InitializeOutline;
		
		PROCEDURE OutlineProcedure (proc : ProcedureInfo; panel : WMStandardComponents.Panel);
			VAR
				s : Utilities.String;
				opcodes : Opcode;
				w : AosIO.Writer;
				nextTab, i, markerPos, opStart, opEnd, pcPos : LONGINT;
				pcMarker : WMTextView.PositionMarker;
		BEGIN
			currentProcInfo := proc;
			w := InitializeOutline(panel);

			textWriter.SetFontStyle({WMGraphics.FontBold});
			w.String(currentProcInfo.name);
			w.String(":"); w.Ln; w.Ln;
			textWriter.SetFontStyle({});
					
			(* output data *)
			opcodes := GetOpcodes(currentProcInfo);
			WHILE opcodes # NIL DO

				IF IsExceptionHandled(opcodes.offset+currentProcInfo.codeOffset) THEN
					textWriter.SetBgColor(0C0D5FFFFH);
				ELSE
					textWriter.SetBgColor(WMGraphics.White);
				END;
			
				textWriter.SetFontColor(WMGraphics.Black);
				NEW(s, 20);
				IntToHex(opcodes.offset, 8, s^);
				Utilities.Append(s^, "H");
				w.String(s^); w.Char(9X);
				(* insert marker for pc if selected *)
				IF markPC >= 0 THEN
					opStart := opcodes.offset+currentProcInfo.codeOffset;
					opEnd := opStart + opcodes.length - 1;
					IF (markPC >= opStart) &	(markPC <= opEnd) THEN
						pcPos := w.Pos() + (markPC-opStart)*3; (* text position within opcode bytes *)
					END
				END;
				opcodes.PrintOpcodeBytes(w); 	w.Char(9X);
				textWriter.SetFontColor(0000099FFH);
				opcodes.PrintInstruction(w);	w.Char(9X);
				opcodes.PrintArguments(w); w.Char(9X);
				textWriter.SetFontColor(0999999FFH);
				opcodes.PrintVariables(w);
				w.Ln;
				opcodes := opcodes.next					
			END;			
			
			w.Update;

			IF markPC >= 0 THEN
				(* insert marker *)
				pcMarker := editor.tv.CreatePositionMarker();
				pcMarker.SetPosition(pcPos);
				pcMarker.SetVisible(TRUE);
				pcMarker.Load ("AosDecoderRes.zip://PCPositionIcon.png");
				editor.tv.cursor.SetPosition(pcPos);
				markPC := -1 (* forget this pc now *)	
			ELSE
				editor.tv.cursor.SetPosition(0)
			END;

			(* set markers to highlight variables *)
			FOR i := 0 TO currentProcInfo.fieldCount-1 DO
				currentProcInfo.fields[i].CreateMarkers(editor.tv);
			END;
			
		END OutlineProcedure;
		
		PROCEDURE OutlineType  (typeInfo : TypeInfo; panel : WMStandardComponents.Panel);
		VAR
			w : AosIO.Writer;
			i : LONGINT;
		BEGIN
			w := InitializeOutline(panel);

			textWriter.SetFontStyle({WMGraphics.FontBold});
			w.String(typeInfo.name);
			w.String(":"); w.Ln; w.Ln;
			textWriter.SetFontStyle({});
			
			(*
			w.String("Fields: "); w.Int(typeInfo.fieldCount, 0); w.Ln;
			
			FOR i := 0 TO typeInfo.fieldCount-1 DO
				w.String(typeInfo.fields[i].name); w.Char(9X);
				typeInfo.fields[i].WriteType(w); w.Char(9X);
				w.String(") ["); w.Int(typeInfo.fields[i].offset, 0); w.String("]")				
			END;
			*)
			w.Update
		END OutlineType;
		
		PROCEDURE OutlineModule  (moduleInfo: ModuleInfo; panel : WMStandardComponents.Panel);
		VAR
			w : AosIO.Writer;
			i : LONGINT;
			proc : ProcedureInfo;
		BEGIN
			w := InitializeOutline(panel);

			w.String(moduleInfo.name);
			w.String(":"); w.Ln; w.Ln;
			
			ASSERT(module # NIL);
			w.String("refSize:"); w.Char(9X); w.Int(module.refSize, 0); w.String(" ("); w.Hex(module.refSize, 0); w.String("H)"); w.Ln;
			w.String("# entries:"); w.Char(9X); w.Int(module.entries, 0); w.Ln;
			w.String("# commands:"); w.Char(9X); w.Int(module.commands, 0); w.Ln;
			w.String("# pointers:"); w.Char(9X); w.Int(module.pointers, 0); w.Ln;
			w.String("# types"); w.Char(9X); w.Int(module.types, 0); w.Ln;
			w.String("# imports"); w.Char(9X); w.Int(module.imports, 0); w.Ln;
			w.String("dataSize:"); w.Char(9X); w.Int(module.dataSize, 0); w.String(" ("); w.Hex(module.dataSize, 0); w.String("H)"); w.Ln;
			w.String("constSize:"); w.Char(9X); w.Int(module.constSize, 0); w.String(" ("); w.Hex(module.constSize, 0); w.String("H)"); w.Ln;
			w.String("codeSize:"); w.Char(9X); w.Int(module.codeSize, 0); w.String(" ("); w.Hex(module.codeSize, 0); w.String("H)"); w.Ln;
			
			w.Ln;
			w.String("Entries:"); w.Ln;
			FOR i := 0 TO module.entries-1 DO
				proc := GetProcedureByIndex(FindEntryByOffset(module.entry[i]));
				w.Hex(module.entry[i], 0); w.Char(9X); 
				IF proc # NIL THEN w.String(proc.name) END;
				w.Ln;
			END;
			
			w.Ln;
			w.String("Exception Handler Table"); w.Ln;
			FOR i := 0 TO module.exTableLen - 1 DO
				w.String("pcFrom= "); w.Hex(module.exTable[i].pcFrom, 0); 
				w.String("H  pcTo= "); w.Hex(module.exTable[i].pcTo, 0); 
				w.String("H pcHandler= "); w.Hex(module.exTable[i].pcHandler, 0); 
				w.String("H");
				w.Ln; 			
			END;
			
			w.Update
		END OutlineModule;

		PROCEDURE Outline (panel : WMStandardComponents.Panel);
			VAR
				moduleNode, fieldNode, typeNode : WMTrees.TreeNode;
				stringWriter : Utilities.Buffer;
				w : AosIO.Writer;
				i, j : LONGINT;
				typeCaption : Utilities.String;
				
			PROCEDURE AddProcedureNode (parent : WMTrees.TreeNode; proc : ProcedureInfo; typeName : AosModules.Name);
			VAR
				procedureNode : WMTrees.TreeNode;
				fieldCaption, procCaption : Utilities.String;
				k : LONGINT;
			BEGIN
				NEW(procedureNode);
				tree.AddChildNode(parent, procedureNode);
				procCaption := Utilities.NewString(proc.name);
				RemoveTypeName(procCaption^, typeName);
				tree.SetNodeCaption(procedureNode, procCaption);
				tree.SetNodeData(procedureNode, proc);
				tree.SetNodeImage(procedureNode, WMGraphics.LoadImage("AosDecoderRes.zip://ProcedureIcon.png", TRUE));
				k := 0;
				WHILE k < proc.fieldCount DO
					proc.fields[k].procedure := proc;
					NEW(fieldCaption, 40);
					NEW(fieldNode);
					tree.AddChildNode(procedureNode, fieldNode);
					proc.fields[k].ToString(w);
					fieldCaption := stringWriter.GetString();
					tree.SetNodeCaption(fieldNode, Utilities.NewString(fieldCaption^));
					tree.SetNodeImage(fieldNode, WMGraphics.LoadImage("AosDecoderRes.zip://VariableIcon.png", TRUE));
					stringWriter.Clear;
					tree.SetNodeData(fieldNode, proc.fields[k]);
					INC(k)
				END				
			END AddProcedureNode;
			
		BEGIN
			lastDAssPanel := panel;
			NEW(stringWriter, 0);
			w := stringWriter.GetWriter();
			
			NEW(treePanel);
			treePanel.alignment.Set(WMComponents.AlignLeft);
			treePanel.bounds.SetWidth(300);
			panel.AddContent(treePanel);

			NEW(resizerH);
			resizerH.bounds.SetWidth(5); resizerH.alignment.Set(WMComponents.AlignRight);
			resizerH.fillColor.Set(0808080FFH);
			treePanel.AddContent(resizerH);

			(* add a tree component *)
			NEW(treeView); treeView.alignment.Set(WMComponents.AlignClient);
			treePanel.AddContent(treeView);
			tree := treeView.GetTree();

			treeView.Initialize;
			treeView.onClickNode.Add(ClickNode);
			panel.Reset(SELF, NIL);
			panel.AlignSubComponents;

			tree.Acquire;
			NEW(moduleNode);
			tree.SetRoot(moduleNode);
			tree.InclNodeState(moduleNode, WMTrees.NodeAlwaysExpanded);
			tree.SetNodeCaption(moduleNode, Utilities.NewString(name));
			tree.SetNodeData(moduleNode, SELF);
			
			i := 0;
			WHILE i < typeCount DO
				NEW(typeNode);
				tree.AddChildNode(moduleNode, typeNode);
				tree.SetNodeCaption(typeNode, Utilities.NewString(types[i].name));
				tree.SetNodeData(typeNode, types[i]);
				tree.SetNodeImage(typeNode, WMGraphics.LoadImage("AosDecoderRes.zip://TypeIcon.png", TRUE));
				j := 0;
				WHILE j < types[i].procedureCount DO
					AddProcedureNode(typeNode, types[i].procedures[j], types[i].name);
					INC(j)
				END;
				INC(i)
			END;
			i := 0;
			WHILE i < procedureCount DO
				IF ~procedures[i].method THEN
					AddProcedureNode(moduleNode, procedures[i], "")
				END;
				INC(i)
			END;
			tree.Release;			
		END Outline;
		
		PROCEDURE Discard(panel : WMStandardComponents.Panel);
		BEGIN
			IF treePanel # NIL THEN
				panel.RemoveContent(treePanel)
			END;
			IF editor # NIL THEN
				panel.RemoveContent(editor)
			END;
			lastDAssPanel := NIL
		END Discard;
		
	END ModuleInfo;
	
	ModuleInfoBytes = OBJECT (ModuleInfo)
	
		PROCEDURE &New(bytes : AosModules.Bytes);
		BEGIN
			Init;
			name := "[UNKNOWN]";
			representationMode := RepresentationModePlain;
			NEW(procedures[0], "[UNKNOWN]", 0, 0);
			procedureCount := 1;
			procedures[0].codeSize := LEN(bytes);
			module.code := bytes
		END New;

		PROCEDURE Outline (panel : WMStandardComponents.Panel);
		BEGIN
			ext := lastExt; (* allows to decode with the decoder the last file was decoded *)
			OutlineProcedure(procedures[0], panel)
		END Outline;
		
	END ModuleInfoBytes;

	CodeScaleCallback* = PROCEDURE(VAR size : LONGINT);

	ModuleInfoObjectFile = OBJECT (ModuleInfo)		
	VAR
		f: AosFS.File;
		r : AosFS.Reader;
		version : LONGINT;
		nofLinks, nofVarConstLinks : LONGINT;
		symSize : LONGINT;
		noProcs : LONGINT; (* ug: temporary *)
	
		PROCEDURE DecodeEntries;
		VAR
			ch : CHAR; i, e : LONGINT;
		BEGIN
			ch := r.Get();
			ASSERT(ch = 82X);
			NEW(module.entry, module.entries);
			FOR i := 0 TO module.entries-1 DO
				r.RawNum(e);
				module.entry[i] := e
			END
		END DecodeEntries;
		
		PROCEDURE SkipCommands;
		VAR
			ch : CHAR;
			i, num : LONGINT;
			n : AosModules.Name;
		BEGIN
			ch := r.Get();
			ASSERT(ch = 83X);
			FOR i := 0 TO module.commands-1 DO
				r.RawString(n); r.RawNum(num)
			END
		END SkipCommands;
		
		PROCEDURE SkipPointers;
		VAR
			ch : CHAR;
			i, num : LONGINT;
		BEGIN
			ch := r.Get();
			ASSERT(ch = 84X);
			FOR i := 0 TO module.pointers-1 DO
				r.RawNum(num)
			END
		END SkipPointers;
		
		PROCEDURE SkipImports;
		VAR
			ch : CHAR;
			i : LONGINT;
			n : AosModules.Name;
		BEGIN
			ch := r.Get();
			ASSERT(ch = 85X);
			FOR i := 0 TO module.imports-1 DO
				r.RawString(n)
			END
		END SkipImports;
		
		PROCEDURE SkipVarConstLinks;
		VAR
			ch : CHAR;
			i, j, num, count : LONGINT;
		BEGIN
			ch := r.Get();
			ASSERT(ch = 8DX);
			FOR i := 0 TO nofVarConstLinks-1 DO
				ch := r.Get();
				r.RawNum(num);
				r.RawLInt(count);
				FOR j := 0 TO count-1 DO
					r.RawNum(num)
				END
			END
		END SkipVarConstLinks;
		
		PROCEDURE SkipLinks;
		VAR
			ch : CHAR;
			i, num : LONGINT;
		BEGIN
			ch := r.Get();
			ASSERT(ch = 86X);
			FOR i := 0 TO nofLinks-1 DO
				r.SkipBytes(2);  (* skip 2 characters *)
				r.RawNum(num)
			END;
			FOR i := 0 TO module.entries-1 DO
				r.RawNum(num)
			END;
			r.RawNum(num)
		END SkipLinks;
		
		PROCEDURE SkipConsts;
		VAR
			ch : CHAR;
		BEGIN
			ch := r.Get();
			ASSERT(ch = 87X);
			r.SkipBytes(module.constSize)
		END SkipConsts;
		
		PROCEDURE SkipExports;
		VAR count: LONGINT; name: AosModules.Name; ch : CHAR;
		
			PROCEDURE LoadScope (level: LONGINT);
			VAR adr, fp, off, i, len, exp: LONGINT; check: POINTER TO ARRAY OF LONGINT;
			BEGIN
				r.RawLInt(exp);
				r.RawNum(fp);
				len := 0;
				IF fp # 0 THEN NEW(check, exp) END;
				WHILE fp # 0 DO
					IF fp = 1 THEN
						r.RawNum(off);
						IF off >= 0 THEN
							INC(count);
							LoadScope (level+1(*1*)) 
						END
					ELSE
						IF level = 0 THEN
							r.RawNum(adr);
							i := 0;
							WHILE i # len DO
								IF check[i] = fp THEN
									r.RawString(name);
									i := len
								ELSE
									INC(i)
								END
							END;
							check[len] := fp; INC(len)
						END
					END;
					r.RawNum(fp)
				END
			END LoadScope;
			
		BEGIN
			ch := r.Get();
			ASSERT(ch = 88X);
			LoadScope (0)
		END SkipExports;
		
		PROCEDURE SkipUse;
		VAR ch : CHAR;

			PROCEDURE ReadUsedModules;
			VAR name : AosModules.Name;

				PROCEDURE ReadEntry;
				VAR
					fp, arg : LONGINT;
					name : AosModules.Name;
				BEGIN
					r.RawNum(fp);
					r.RawString(name);
					r.RawNum(arg);
					IF arg > 0 THEN
						IF r.Peek() = 1X THEN
							ch := r.Get();
							r.RawNum(arg)
						END
					ELSIF arg < 0 THEN
					ELSE
						IF r.Peek() = 1X THEN
							(* read used record *)
							ch := r.Get();
							r.RawNum(arg); (* tdentry *)
							IF r.Peek() # 0X THEN
								r.RawNum(arg); (* FP *)
								r.RawString(name);
								ASSERT(name = "@");
							END;
							ch := r.Get();
							ASSERT(ch = 0X)
						END;
					END
				END ReadEntry;
					
			BEGIN
				WHILE r.Peek() # 0X DO
					r.RawString(name);
					WHILE r.Peek() # 0X DO
						ReadEntry
					END;
					ch := r.Get();
					ASSERT(ch = 0X)
				END
			END ReadUsedModules;
			
		BEGIN
			ch := r.Get();
			ASSERT(ch = 08AX);
			ReadUsedModules;
			ch := r.Get();
			ASSERT(ch = 0X)
		END SkipUse;	
		
		PROCEDURE DecodeTypes;
		VAR
			i, j, size, entry, ptrOfs, tdaddr, moduleBase, nofMethods, nofInhMethods, nofNewMethods, nofPointers, methNr, entryNr : LONGINT;
			name : AosModules.Name; ch : CHAR;
			type : TypeInfo;
			procInfo : ProcedureInfo;
		BEGIN
			ch := r.Get();
			ASSERT(ch = 08BX);
			typeCount := module.types;
			NEW(types, typeCount);
			FOR i := 0 TO module.types-1 DO
				r.RawNum(size);
				r.RawNum(tdaddr);
				(* read Base *)
				r.RawNum(moduleBase); r.RawNum(entry);
				(* read Count *)
				r.RawNum(nofMethods); r.RawNum(nofInhMethods); r.RawNum(nofNewMethods); r.RawLInt(nofPointers);
				r.RawString(name);
				NEW(type, name);
				IF type.name = "" THEN type.name := "[anonymous]" END;
				types[i] := type;
				
				AosOut.String(" - size = "); AosOut.Int(size, 0); AosOut.Ln; 
				AosOut.String(" - tdaddr = "); AosOut.Int(tdaddr, 0); AosOut.Ln; 
				AosOut.String(" - moduleBase = "); AosOut.Int(moduleBase, 0); AosOut.Ln; 
				AosOut.String(" - entry = "); AosOut.Int(entry, 0); AosOut.Ln; 
				AosOut.String(" - nofMethods = "); AosOut.Int(nofMethods, 0); AosOut.Ln; 
				AosOut.String(" - nofInhMethods = "); AosOut.Int(nofInhMethods, 0); AosOut.Ln; 
				AosOut.String(" - nofNewMethods = "); AosOut.Int(nofNewMethods, 0); AosOut.Ln; 
				AosOut.String(" - nofPointers = "); AosOut.Int(nofPointers, 0); AosOut.Ln; 
				AosOut.String(" - Methods:"); AosOut.Ln; 
				
				(* read Methods *)
				type.procedureCount := nofNewMethods;
				NEW(type.procedures, type.procedureCount);
				FOR j := 0 TO type.procedureCount-1 DO
					r.RawNum(methNr); r.RawNum(entryNr);
					NEW(procInfo, "", module.entry[entryNr], entryNr);
					procInfo.method := TRUE;
					AddProcedure(procInfo);
					type.procedures[j] := procInfo;
				END;
				(* read Pointers *)
				FOR j := 0 TO nofPointers-1 DO
					r.RawNum(ptrOfs)
				END
			END;
		END DecodeTypes;		
		
		PROCEDURE DecodeExTable(r: AosIO.Reader);
		VAR
			i: LONGINT;
			tag: CHAR;
			entry: AosModules.ExceptionTableEntry;
		BEGIN
			NEW(module.exTable, module.exTableLen);	
			FOR i := 0 TO module.exTableLen -1 DO
				r.Char(tag);
				ASSERT(tag = 0FEX);
				r.RawNum(module.exTable[i].pcFrom);			
				r.RawNum(module.exTable[i].pcTo);
				r.RawNum(module.exTable[i].pcHandler);								
			END;			
		END DecodeExTable;
		
		PROCEDURE SkipPointerInProc;
		VAR ch : CHAR;
			i, j, codeoffset, beginOffset, endOffset, p, nofptrs : LONGINT;
		BEGIN
			ch := r.Get();
			ASSERT(ch = 8FX);
			FOR i := 0 TO noProcs - 1 DO 
				r.RawNum(codeoffset);
				r.RawNum(beginOffset);
				r.RawNum(endOffset);
				r.RawLInt(nofptrs);
				FOR j := 0 TO nofptrs - 1 DO
					r.RawNum(p)
				END				
			END
		END SkipPointerInProc;
	
		PROCEDURE &New (fileName : ARRAY OF CHAR);
		VAR ch : CHAR; tmp : LONGINT; j, res, extPos : LONGINT; msg : ARRAY 255 OF CHAR;
		BEGIN
			Init;
			extPos := Utilities.Pos(".", fileName) + 1;
			Utilities.Copy(fileName, extPos, Utilities.Length(fileName)-extPos, ext);
			lastExt := ext;
			codeScaleCallback := GetCodeScaleCallback(ext);
			f := AosFS.Old(fileName);
			IF f # NIL THEN
				AosFS.OpenReader(r, f, 0);
				IF r.Get() = 0BBX THEN
					version := ORD(r.Get());
					IF version = 0ADH THEN version := ORD(r.Get()) END;
					r.RawNum(symSize);
					r.SkipBytes(symSize); (* skip symbol file *)
				ELSE
					AosOut.String("AosDecoder: ERROR: Tag not supported or wrong file type!"); AosOut.Ln;
					RETURN
				END;
				r.RawLInt(module.refSize);
				r.RawLInt(module.entries); 
				r.RawLInt(module.commands); 
				r.RawLInt(module.pointers); 
				r.RawLInt(module.types); 
				r.RawLInt(module.imports); 
				r.RawLInt(nofVarConstLinks);
				r.RawLInt(nofLinks);
				r.RawLInt(module.dataSize);
				r.RawLInt(module.constSize); 
				r.RawLInt(module.codeSize); 
				IF (codeScaleCallback # NIL) THEN codeScaleCallback(module.codeSize) END;
				
				(* Sz: Exception handling *)
				r.RawLInt(module.exTableLen);
				
				(* ug: Pointers in procedures, maxPtrs: *)
				r.RawLInt(noProcs);
				r.RawLInt(tmp); (* skip *)
				
				r.RawString(name);
				(* skip to code block *)
				DecodeEntries;
				SkipCommands;
				SkipPointers;
				SkipImports;
				SkipVarConstLinks;
				SkipLinks;
				SkipConsts;
				SkipExports;
				ch := r.Get();
				ASSERT(ch = 89X);

				(* code section *)
				NEW(module.code, module.codeSize);
				FOR j := 0 TO module.codeSize-1 DO
					module.code[j] := r.Get()
				END;
				SkipUse;
				DecodeTypes;
				
				(* Sz: read exception handling table *)
				ch := r.Get();
				ASSERT(ch = 8EX);
				DecodeExTable(r);
				
				SkipPointerInProc; (* ug *)

				(* read ref header *)
				ch := r.Get();
				ASSERT(ch = OFFHdrRef);
				DecodeRefs(r);
			ELSE
				msg := "Object file '"; Utilities.Append(msg, fileName); Utilities.Append(msg, "' could not be found.");
				res := WMDialogs.Message("AosDecoder", msg, {WMDialogs.ResOk})
			END;
		END New;
		
	END ModuleInfoObjectFile;
	
	ModuleInfoMemory = OBJECT (ModuleInfo)
		VAR
			reader : AosMemoryReader.Reader;
			i : LONGINT;

		PROCEDURE &New (module : AosModules.Module);
		BEGIN
			Init;
			name := module.name;
			representationMode := RepresentationModeMeta;

			NEW(reader, SYSTEM.ADR(module.refs[0]), module.refSize);
			SELF.module := module;
			
			DecodeRefs(reader);
			DecodeTypes
		END New;
		
		PROCEDURE DecodeTypes;
		VAR
			i, j : LONGINT;
			type : TypeInfo;
			typeDesc : AosModules.TypeDesc;
			adr : LONGINT;
		BEGIN
			typeCount := module.types;
			NEW(types, typeCount);
			FOR i := 0 TO typeCount-1 DO
				adr := SYSTEM.VAL(LONGINT, module.type[i]);
				SYSTEM.GET(adr-4, typeDesc);
				NEW(type, typeDesc.name);
				types[i] := type;
				
				(* check for methods of this type *)
				IF type.name # "" THEN
					(* silly way: name matching -> improve by reading typeDesc method block *)
					FOR j := 0 TO procedureCount-1 DO
						IF StartsWith(procedures[j].name, type.name) THEN
							type.AddProcedure(procedures[j]);
							procedures[j].method := TRUE
						END
					END
				ELSE
					type.name := "[anonymous]"
				END
			END
		END DecodeTypes;
		
	END ModuleInfoMemory;
		
	KillerMsg = OBJECT
	END KillerMsg;
	
	DecoderWindow = OBJECT (WMComponents.FormWindow)
	VAR
		panel : WMStandardComponents.Panel;
		toolbar : WMStandardComponents.Panel;
		resizerH : WMStandardComponents.Resizer;
		currentDecoder : Decoder;
		decodeFile, decodeModule, decodeBytes, clear: WMStandardComponents.Button;
		outputWriter : AosIO.Writer;
		stopped : BOOLEAN;
		hexStr : ARRAY 3 OF CHAR;
		i : LONGINT;
		moduleInfo : ModuleInfo;

		PROCEDURE CreateForm() : WMComponents.VisualComponent;
		VAR
			resizerH, resizerV: WMStandardComponents.Resizer;
		BEGIN
			
			NEW(panel); panel.bounds.SetExtents(1024, 768); panel.fillColor.Set(WMGraphics.White); panel.takesFocus.Set(TRUE);
			NEW(toolbar); toolbar.bounds.SetHeight(20); toolbar.alignment.Set(WMComponents.AlignTop);
			panel.AddContent(toolbar);
			
			NEW(decodeFile); decodeFile.caption.SetAOC("Decode File"); decodeFile.alignment.Set(WMComponents.AlignLeft);
			decodeFile.bounds.SetWidth(2 * decodeFile.bounds.GetWidth());
			decodeFile.onClick.Add(DecodeFileHandler);
			toolbar.AddContent(decodeFile);
			
			NEW(decodeModule); decodeModule.caption.SetAOC("Decode Module"); decodeModule.alignment.Set(WMComponents.AlignLeft); 
			decodeModule.bounds.SetWidth(2 * decodeModule.bounds.GetWidth());
			decodeModule.onClick.Add(DecodeModuleHandler);
			toolbar.AddContent(decodeModule);
			
			NEW(decodeBytes); decodeBytes.caption.SetAOC("Decode Bytes"); decodeBytes.alignment.Set(WMComponents.AlignLeft);
			decodeBytes.bounds.SetWidth(2 * decodeBytes.bounds.GetWidth());
			decodeBytes.onClick.Add(DecodeBytesHandler);
			toolbar.AddContent(decodeBytes);
			
			RETURN panel
		END CreateForm;
			
		PROCEDURE &New(fileName : ARRAY OF CHAR; c : WMRestorable.Context);
		VAR
			vc : WMComponents.VisualComponent;
			moduleInfoObjectFile : ModuleInfoObjectFile;
			moduleInfoMemory : ModuleInfoMemory;
			msg : ARRAY 256 OF CHAR;
			ext : Extension;
			module : AosModules.Module;
			res, extPos : LONGINT;
		BEGIN
			vc := CreateForm();
			Init(vc.bounds.GetWidth(), vc.bounds.GetHeight(), FALSE);
			SetContent(vc);
			WM.DefaultAddWindow(SELF);

			stopped := FALSE;
			IF fileName # "" THEN
				extPos := Utilities.Pos(".", fileName) + 1;
				IF extPos # 0 THEN (* must be a file name *)
					(* load the file and outline it *)
					NEW(moduleInfoObjectFile, fileName);
					moduleInfoObjectFile.Outline(panel);
					moduleInfo := moduleInfoObjectFile;
				ELSE
					module := AosModules.ThisModule(fileName, res, msg);
					NEW(moduleInfoMemory, module);
					
					moduleInfoMemory.Outline(panel);
					moduleInfo := moduleInfoMemory;
				END;
				AdjustTitle(fileName);
			ELSE
				AdjustTitle("")
			END;
			IncCount;
		END New;
		
		PROCEDURE AdjustTitle (str : ARRAY OF CHAR);
		VAR
			titleString : ARRAY 100 OF CHAR;
		BEGIN
			titleString := "Decoder";
			IF str # "" THEN
				Utilities.Append(titleString, " - ");
				Utilities.Append(titleString, str)
			END;
			SetTitle(Utilities.NewString(titleString))
		END AdjustTitle;

		PROCEDURE DecodeFileHandler(sender, data : ANY);
		VAR
			fileNameStr : ARRAY 256 OF CHAR;
			moduleInfoObjectFile : ModuleInfoObjectFile;
		BEGIN
			IF WMDialogs.QueryString("Enter file name", fileNameStr) = WMDialogs.ResOk THEN
				IF moduleInfo # NIL THEN
					moduleInfo.Discard(panel)
				END;
				NEW(moduleInfoObjectFile, fileNameStr);
				moduleInfoObjectFile.Outline(panel);
				moduleInfo := moduleInfoObjectFile;
				AdjustTitle(fileNameStr)
			END;
		END DecodeFileHandler;
		
		PROCEDURE DecodeModuleHandler(sender, data : ANY);
		VAR moduleNameStr, msg : ARRAY 256 OF CHAR;
			module : AosModules.Module;
			res : LONGINT;
			moduleInfoMemory : ModuleInfoMemory;
		BEGIN
			IF WMDialogs.QueryString("Enter module name", moduleNameStr) = WMDialogs.ResOk THEN
				module := AosModules.ThisModule(moduleNameStr, res, msg);
				IF res # 0 THEN
					msg := "Module "; Utilities.Append(msg, moduleNameStr); Utilities.Append(msg, " not found in memory.");
					res := WMDialogs.Message("AosDecoder", msg, {WMDialogs.ResOk});
				ELSE
					IF moduleInfo # NIL THEN
						moduleInfo.Discard(panel)
					END;
					NEW(moduleInfoMemory, module);
					moduleInfoMemory.Outline(panel);
					moduleInfo := moduleInfoMemory;
					AdjustTitle(moduleNameStr)
				END
			END
		END DecodeModuleHandler;
				
		PROCEDURE DecodeBytesHandler(sender, data : ANY);
		VAR hexByteStr : ARRAY 1024 OF CHAR;
			opcodes : Opcode;
			moduleInfoBytes : ModuleInfoBytes;
		BEGIN
			IF WMDialogs.QueryString("Enter bytes in hex format (separated by spaces)", hexByteStr) = WMDialogs.ResOk THEN				
				IF moduleInfo # NIL THEN
					moduleInfo.Discard(panel)
				END;
				NEW(moduleInfoBytes, HexBytes2Code(hexByteStr));
				moduleInfoBytes.Outline(panel);
				moduleInfo := moduleInfoBytes;
				AdjustTitle("[byte array]")
			END
		END DecodeBytesHandler;
				
		PROCEDURE Handle(VAR x: WMMessages.Message);
		BEGIN
			IF (x.msgType = WMMessages.MsgExt) & (x.ext # NIL) & (x.ext IS KillerMsg) THEN Close
			ELSE Handle^(x)
			END
		END Handle;
			
		PROCEDURE OutlineProcedure* (name : AosModules.Name);
		BEGIN
			IF (moduleInfo # NIL) & ~(moduleInfo IS ModuleInfoBytes) THEN
				moduleInfo.OutlineNamedProcedure(name)
			END
		END OutlineProcedure;
		
		PROCEDURE OutlinePC* (pc : LONGINT);
		BEGIN
			IF (moduleInfo # NIL) & ~(moduleInfo IS ModuleInfoBytes) THEN
				moduleInfo.OutlinePC(pc)
			END
		END OutlinePC;
		
		PROCEDURE Close;
		BEGIN
			Close^;
			BEGIN {EXCLUSIVE}
				stopped := TRUE
			END;
			DecCount
		END Close;		
	END DecoderWindow;

	Extension = ARRAY 4 OF CHAR;
	
	DecoderType = OBJECT
		VAR 
			ext : Extension;
			decoderFactory : DecoderFactory;
			codeScaleCallback : CodeScaleCallback;
		PROCEDURE &New (ext : Extension; decoderFactory : DecoderFactory; codeScaleCallback : CodeScaleCallback);
		BEGIN
			SELF.ext := ext; SELF.decoderFactory := decoderFactory; SELF.codeScaleCallback := codeScaleCallback
		END New;
	END DecoderType;

VAR
	nofWindows : LONGINT;
	win : DecoderWindow;
	decoderTypes : ARRAY maxDecoders OF DecoderType;
	nofDecoders : LONGINT;
	lastExt : Extension;
	
	PROCEDURE OpenEmpty*(par : ANY) : ANY;
	BEGIN
		NEW(win, "", NIL);
		RETURN NIL
	END OpenEmpty;
	
	PROCEDURE RemoveTypeName (VAR procName : ARRAY OF CHAR; typeName : ARRAY OF CHAR);
	VAR
		i, j : LONGINT;
	BEGIN
		i := 0;
		IF Utilities.Length(typeName) > 0 THEN
			WHILE procName[i] = typeName[i] DO INC(i) END;
			IF (typeName[i] = 0X) & (procName[i] = '.') THEN
				j := 0;
				INC(i);
				WHILE procName[i] # 0X DO
					procName[j] := procName[i];
					INC(i); INC(j)
				END;
				procName[j] := 0X
			END
		END				
	END RemoveTypeName;
	
	PROCEDURE StartsWith (str, pattern : ARRAY OF CHAR) : BOOLEAN;
	VAR i : LONGINT;
	BEGIN
		i := 0;
		WHILE (pattern[i] # 0X) & (str[i] # 0X) & (str[i] = pattern[i]) DO INC(i) END;
		IF pattern[i] = 0X THEN RETURN TRUE
		ELSE RETURN FALSE
		END
	END StartsWith;

	PROCEDURE HexBytes2Code(bytes : ARRAY OF CHAR) : AosModules.Bytes;
	VAR
		buffer, result : AosModules.Bytes;
		byte : CHAR;
		reader : AosMemoryReader.Reader;
		decoder : IA32Decoder;
		j, size : LONGINT;
		
		PROCEDURE DecodeHexChar(ch : CHAR) : LONGINT;
		BEGIN
			IF (ORD(ch) >= 48) & (ORD(ch) <= 57) THEN RETURN ORD(ch) - 48 END;
			IF (ORD(ch) >= 65) & (ORD(ch) <= 70) THEN RETURN ORD(ch) - 55 END;
			IF (ORD(ch) >= 97) & (ORD(ch) <= 102) THEN RETURN ORD(ch) - 87 END;
			RETURN 0
		END DecodeHexChar;
		
	BEGIN
		NEW(buffer, LEN(bytes));
		j := 0; size := 0;
		WHILE j < Utilities.Length(bytes)-1 DO
			byte := CHR(DecodeHexChar(bytes[j])*16 + DecodeHexChar(bytes[j+1]));
			INC(j, 2);
			IF (j < LEN(bytes)) & (bytes[j] = 20X) THEN INC(j) END;
			buffer[size] := byte;
			INC(size)
		END;
		NEW(result, size);
		j := 0;
		WHILE j < size DO
			result[j] := buffer[j]; INC(j)
		END;
		RETURN result
	END HexBytes2Code;

	PROCEDURE IntToHex(h, width: LONGINT; VAR s: ARRAY OF CHAR);
	VAR c: CHAR;
	BEGIN
		IF (width <= 0) THEN width := 8 END;
		ASSERT(LEN(s) > width);
		s[width] := 0X;
		DEC(width);
		WHILE (width >= 0) DO
			c := CHR(h MOD 10H + ORD("0"));
			IF (c > "9") THEN c := CHR((h MOD 10H - 10) + ORD("A")) END;
			s[width] := c; h := h DIV 10H; DEC(width)
		END
	END IntToHex;

	PROCEDURE IncCount;
	BEGIN {EXCLUSIVE}
		INC(nofWindows)
	END IncCount;
	
	PROCEDURE DecCount;
	BEGIN {EXCLUSIVE}
		DEC(nofWindows)
	END DecCount;
	
	PROCEDURE Cleanup;
	VAR
		die : KillerMsg;
		msg : WMMessages.Message;
		m : WM.WindowManager;
	BEGIN {EXCLUSIVE}
		NEW(die);
		msg.ext := die;
		msg.msgType := WMMessages.MsgExt;
		m := WM.GetDefaultManager();
		m.Broadcast(msg);
		AWAIT(nofWindows = 0);
	END Cleanup;
	
	PROCEDURE IA32DecoderFactory (reader : AosIO.Reader) : Decoder;
	VAR
		ia32Decoder : IA32Decoder;
	BEGIN
		AosOut.String("IA32DecoderFactory"); AosOut.Ln; 
		NEW(ia32Decoder, reader);
		RETURN ia32Decoder
	END IA32DecoderFactory;
	
	PROCEDURE Open* (par: PTR): PTR;
	VAR s: AosCommands.Parameters;
			name : AosModules.Name;
			sr : AosIO.StringReader;
			pc : LONGINT;
	BEGIN
		s := par(AosCommands.Parameters);
		NEW(sr, LEN(s.str^)); sr.Set(s.str^);
		sr.String(name);
		
		AosOut.String("starting win..."); AosOut.Ln; 
		NEW(win, name, NIL);
		sr.SkipSpaces();
		IF (sr.Peek() < "0") OR (sr.Peek() > "9") THEN
			sr.Token(name);
			IF name # "" THEN win.OutlineProcedure (name) END			
		ELSIF (sr.Peek() >= "0") & (sr.Peek() <= "9") THEN
			sr.Int(pc, FALSE);
			IF pc > 0 THEN win.OutlinePC(pc) END
		END;
		RETURN NIL
	END Open;
	
	PROCEDURE OpenProcedure* (moduleName, procedureName : AosModules.Name);
	BEGIN
		NEW(win, moduleName, NIL);
		win.OutlineProcedure(procedureName)
	END OpenProcedure;
	
	PROCEDURE OpenPC* (moduleName : AosModules.Name; pc : LONGINT);
	BEGIN
		NEW(win, moduleName, NIL);
		win.OutlinePC(pc)
	END OpenPC;
	
	PROCEDURE RegisterDecoder* (ext : Extension; decFactory : DecoderFactory; csclCallback : CodeScaleCallback);
	VAR dec : DecoderType;
	BEGIN
		ASSERT(nofDecoders < maxDecoders);
		dec := GetDecoderType(ext);
		IF dec = NIL THEN
			NEW(decoderTypes[nofDecoders], ext, decFactory, csclCallback);
			INC(nofDecoders)
		END
	END RegisterDecoder;
	
	PROCEDURE GetDecoderType (ext : Extension) : DecoderType;
	VAR i : LONGINT;
	BEGIN
		IF nofDecoders < 1 THEN RETURN NIL END;		
		IF ext = "" THEN RETURN decoderTypes[0] END;
		FOR i := 0 TO nofDecoders-1 DO
			IF decoderTypes[i].ext = ext THEN
				RETURN decoderTypes[i]
			END
		END;
		RETURN NIL
	END GetDecoderType;
	
	PROCEDURE GetDecoder (ext : Extension; reader : AosIO.Reader) : Decoder;
	VAR dec : DecoderType;
	BEGIN
		dec := GetDecoderType(ext);
		IF dec # NIL THEN RETURN dec.decoderFactory(reader)
		ELSE RETURN NIL
		END
	END GetDecoder;
	
	PROCEDURE GetCodeScaleCallback (ext : Extension) : CodeScaleCallback;
	VAR dec : DecoderType;
	BEGIN
		dec := GetDecoderType(ext);
		IF dec # NIL THEN RETURN dec.codeScaleCallback
		ELSE RETURN NIL
		END
	END GetCodeScaleCallback;	

BEGIN
	nofDecoders := 0;
	RegisterDecoder(objFileSuffix, IA32DecoderFactory, NIL);
	AosModules.InstallTermHandler(Cleanup)
END AosDecoder.

AosDecoder.Open AosTV.Obx~
S.Free AosDecoder ~
