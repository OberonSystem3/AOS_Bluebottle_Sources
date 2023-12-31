(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE Adaptec7Script; (** AUTHOR "prk"; PURPOSE "Adaptec 7xxx SCSI firmware"; *)

(*
	Script for the Adaptec 7xxx sequencer.
	Taken from Linux (Version 5.1.15/3.2.4)
	
	Ported by Patrik Reali (reali@acm.org), 30.3.99
	
	04.08.99:
		bug in GetLine. Caused some lines to be skipped on the AHA2940A
		
	29.07.99:
		Scripts for rapid file conversion
		porting 5.1.15
*)


IMPORT
		SYSTEM;

TYPE
	Patch = RECORD f, begin, skipinstr, skippatch: LONGINT END;

VAR
	Patches: ARRAY 77 OF Patch;
	F: ARRAY 14 OF BOOLEAN;
	
	Base: LONGINT;		(* pointer to the program *)
	pc, patch: LONGINT;

PROCEDURE CorrectAddr(VAR line: SET);
VAR i, addr, Max: LONGINT;
BEGIN
	addr := SYSTEM.VAL(LONGINT, SYSTEM.LSH(line*{17..26}, -17));
	i := 0; Max := addr;
	WHILE Patches[i].begin < Max DO
		IF ~F[Patches[i].f] THEN	(*patch not active*)
			addr := addr - Patches[i].skipinstr;
			INC(i, Patches[i].skippatch)
		ELSE
			INC(i)
		END
	END;
	line := line - {17..26} + SYSTEM.VAL(SET, SYSTEM.LSH(addr, 17));
END CorrectAddr;

PROCEDURE LoadPatches;
VAR i: LONGINT;
	PROCEDURE SetPatch(func, line, skipadr, skippatch: LONGINT);
	BEGIN
		Patches[i].f := func;
		Patches[i].begin := line;
		Patches[i].skipinstr := skipadr;
		Patches[i].skippatch := skippatch;
		INC(i)
	END SetPatch;
BEGIN
	i := 0;
	SetPatch(1 , 2, 1, 2); SetPatch(0 , 3, 1, 1); SetPatch(2 , 4, 2, 1); SetPatch(3 , 8, 1, 1);
	SetPatch(3 , 9, 1, 1); SetPatch(4 , 12, 4, 1); SetPatch(5 , 17, 3, 2); SetPatch(0 , 20, 4, 1);
	SetPatch(6 , 24, 1, 1); SetPatch(7 , 27, 1, 1); SetPatch(2 , 30, 1, 2); SetPatch(0 , 31, 3, 1);
	SetPatch(4 , 40, 4, 1); SetPatch(8 , 44, 3, 2); SetPatch(0 , 47, 3, 1); SetPatch(9 , 52, 7, 1);
	SetPatch(4 , 60, 3, 1); SetPatch(8 , 63, 2, 1); SetPatch(1 , 68, 60, 1); SetPatch(8 , 162, 1, 2);
	SetPatch(0 , 163, 2, 1); SetPatch(2 , 167, 2, 3); SetPatch(8 , 167, 1, 1); SetPatch(0 , 169, 2, 1);
	SetPatch(8 , 172, 1, 2); SetPatch(0 , 173, 1, 1); SetPatch(2 , 177, 1, 1); SetPatch(2 , 180, 3, 2);
	SetPatch(0 , 183, 5, 1); SetPatch(2 , 191, 2, 3); SetPatch(8 , 191, 1, 1); SetPatch(0 , 193, 3, 1);
	SetPatch(10 , 196, 2, 1); SetPatch(8 , 198, 7, 2); SetPatch(0 , 205, 1, 1); SetPatch(2 , 210, 14, 3);
	SetPatch(10 , 223, 1, 1); SetPatch(0 , 224, 9, 1); SetPatch(8 , 238, 2, 1); SetPatch(8 , 240, 1, 1);
	SetPatch(10 , 241, 6, 3); SetPatch(2 , 241, 2, 2); SetPatch(0 , 243, 4, 1); SetPatch(8 , 248, 1, 1);
	SetPatch(8 , 252, 11, 1); SetPatch(2 , 264, 3, 3); SetPatch(10 , 266, 1, 1); SetPatch(0 , 267, 5, 1);
	SetPatch(10 , 272, 1, 2); SetPatch(0 , 273, 7, 1); SetPatch(11 , 287, 1, 2); SetPatch(0 , 288, 1, 1);
	SetPatch(5 , 348, 1, 2); SetPatch(0 , 349, 1, 1); SetPatch(3 , 352, 1, 1); SetPatch(2 , 362, 3, 2);
	SetPatch(0 , 365, 5, 1); SetPatch(11 , 373, 1, 2); SetPatch(0 , 374, 1, 1); SetPatch(6 , 379, 1, 1);
	SetPatch(1 , 416, 3, 1); SetPatch(10 , 421, 11, 1); SetPatch(2 , 469, 7, 2); SetPatch(0 , 476, 8, 1);
	SetPatch(2 , 485, 4, 2); SetPatch(0 , 489, 6, 1); SetPatch(2 , 495, 4, 2); SetPatch(0 , 499, 3, 1);
	SetPatch(12 , 509, 10, 1); SetPatch(2 , 528, 17, 4); SetPatch(13 , 536, 4, 2); SetPatch(0 , 540, 2, 1);
	SetPatch(0 , 545, 33, 1); SetPatch(12 , 578, 4, 1); SetPatch(6 , 582, 2, 1); SetPatch(6 , 585, 9, 1);
	SetPatch(0, MAX(LONGINT), -1, -1);
END LoadPatches;

PROCEDURE SeqProgram(): LONGINT;
CODE {SYSTEM.i386}
	CALL L1
L1:
	POP EAX
	ADD EAX,8
	POP EBP
	RET
		(* sequencer program, from Linux  aic7xxx_seq.c*)
	DD 008066AFFH, 00804027FH, 000006A32H, 000006A12H
	DD 009D66AFFH, 009DC6AFFH, 059426500H, 0080201F7H
	DD 008C84EFFH, 008C060BFH, 068860B60H, 0680E0040H
	DD 0103E1F08H, 068860B60H, 0680E0040H, 0103E1F08H
	DD 0604A3EFFH, 07812FA40H, 008D4F6FFH, 0189C4E01H
	DD 000C06040H, 070124D00H, 0189C4E01H, 008C060BFH
	DD 05C926A00H, 018C84EFFH, 05BA86A02H, 0092052FFH
	DD 0006A6A0DH, 05C1E5200H, 03152B003H, 00952B0FFH
	DD 00954B1FFH, 00956B2FFH, 00950A3FFH, 009743EFFH
	DD 0087C90FFH, 009203EFFH, 058506500H, 0400E6500H
	DD 008CA1FF7H, 008C8A108H, 000CA6500H, 0083E65FFH
	DD 008C8A1F0H, 0081E0F0FH, 0001E0F00H, 008C8A1F0H
	DD 0080A050FH, 0000A0500H, 004006A5AH, 000026512H
	DD 000CA6A31H, 0686E3780H, 018CA65FFH, 008DC37FFH
	DD 008C86EFFH, 078766C00H, 000020120H, 028C8374CH
	DD 0787E1F08H, 0006E3708H, 000C86408H, 018CA6470H
	DD 0080A6CFFH, 018CA6420H, 00C086CFFH, 0690E0B40H
	DD 079000B80H, 000066AA4H, 000166A40H, 078FC0310H
	DD 008C850FFH, 000CC6A88H, 05C0E6A49H, 001266A01H
	DD 008CA6AFFH, 000020108H, 0789C0B02H, 0080201F7H
	DD 008CC06FFH, 0093266FFH, 018CA6501H, 078AA6680H
	DD 008A266FFH, 0689A0310H, 018C865FCH, 048B26500H
	DD 001326AFFH, 019186401H, 0091A6AFFH, 0091C6AFFH
	DD 000066A84H, 000020108H, 078BC0B02H, 008C806FFH
	DD 0093264FFH, 008CA6AFFH, 028C8645BH, 018C46200H
	DD 018CA65FCH, 008D46AFFH, 018CA65FAH, 008D46AFFH
	DD 018CA6504H, 018CA650BH, 008C865FFH, 019188C00H
	DD 078D80B02H, 060DE6501H, 0080201F7H, 0093206FFH
	DD 018CA65FFH, 068D865FFH, 00126930AH, 05C846500H
	DD 078F05140H, 000066AE4H, 000020108H, 05B406A04H
	DD 018A05001H, 0E0F65000H, 008A06AFFH, 0013A6AFFH
	DD 001226A02H, 068FC5140H, 008066AFFH, 0400E6500H
	DD 000166A20H, 0086E19F0H, 000186A08H, 000221108H
	DD 058666A08H, 000686A08H, 041226500H, 000006A12H
	DD 000166A40H, 009203EFFH, 0087CBAFFH, 0086EA1FFH
	DD 000186A08H, 000221108H, 058666A08H, 000686A80H
	DD 0006C3680H, 05BF26500H, 008C83DFFH, 0795864BFH
	DD 0720E6480H, 0723A64A0H, 0723264C0H, 0727A64E0H
	DD 001226A01H, 041226500H, 0082211F7H, 059426500H
	DD 008D406FFH, 0080201F7H, 0793C0C09H, 0680E0C08H
	DD 001226A01H, 009266AFFH, 030086A02H, 008086AFFH
	DD 0080201DFH, 0007A6A01H, 00C6C6AFFH, 03118A903H
	DD 03010A903H, 000CC6A08H, 05C086AA9H, 041786500H
	DD 0006A6AA8H, 0006A6A79H, 069603D40H, 0006A3504H
	DD 05B626500H, 001D46A80H, 0694E3610H, 0006C3610H
	DD 03110AC07H, 030108C03H, 03070A305H, 000CC6A88H
	DD 05C006AACH, 05BFA6500H, 000CC6A38H, 05C046AA3H
	DD 0698838FFH, 000040280H, 0086A35E7H, 031186903H
	DD 030106903H, 000106AFFH, 000126AFFH, 000146AFFH
	DD 0618C3801H, 0086A35BFH, 008CA69FFH, 0092635FFH
	DD 069900B04H, 0699C0B04H, 079920C10H, 0699A0B04H
	DD 008CA6AFFH, 05B4A3500H, 069F00280H, 079E065FFH
	DD 0187038FFH, 079E038FFH, 061BCEA80H, 018C838EFH
	DD 000C86A80H, 049AE6500H, 028C83833H, 009D064FFH
	DD 031C03904H, 001D66A09H, 079B4EB80H, 009D6EBF7H
	DD 069B8EB08H, 001D66A01H, 03110E908H, 030108C03H
	DD 000CC6A88H, 05C066A39H, 001186A08H, 0091A6AFFH
	DD 0091C6AFFH, 00126930DH, 05C846500H, 05C746A88H
	DD 05BFA6500H, 008C86AFFH, 018723908H, 020743A00H
	DD 079D80C01H, 079780C10H, 0092635FFH, 069DE0B04H
	DD 059F86500H, 031520803H, 0095038FFH, 0095208FFH
	DD 0095409FFH, 009560AFFH, 0095038FFH, 041226500H
	DD 059F86500H, 00804027FH, 001226AE1H, 041226500H
	DD 06A029304H, 0092693DFH, 069FC9320H, 001269302H
	DD 079FE9401H, 0092693D7H, 06A049308H, 031520803H
	DD 0095038FFH, 000020112H, 00CD46AFFH, 05B626500H
	DD 03110B405H, 0311A6A02H, 030108C03H, 000CC6A88H
	DD 05C046AB4H, 0091A6AFFH, 0091C6AFFH, 05BFA6500H
	DD 05B4A6A3DH, 001266AACH, 06A240B04H, 06A2A0B01H
	DD 07A260C10H, 0092693D7H, 06A2C9308H, 000020112H
	DD 041226500H, 05B626500H, 0094406FFH, 041226500H
	DD 000063D10H, 008CA34FFH, 0625E6580H, 008CAA10FH
	DD 008CAA107H, 008C8A040H, 000CA6500H, 000CA6580H
	DD 07A4EA080H, 0080C65FFH, 042606500H, 07A66A020H
	DD 0080C65FFH, 05BF26500H, 0626E3DA0H, 0080CA023H
	DD 05BF26500H, 0626E3DA0H, 04266B900H, 0626665FFH
	DD 001226AA1H, 008D46AFFH, 0726E5110H, 000186A40H
	DD 0080C65FFH, 05BF26500H, 072383DA0H, 000186A40H
	DD 008A634FFH, 062763480H, 00940A07FH, 000686A08H
	DD 041226500H, 05B3A6A64H, 06AEA6480H, 072CC6404H
	DD 072D26402H, 072946A00H, 072E66403H, 072C86401H
	DD 073286407H, 072906408H, 001226A11H, 05B2C6A07H
	DD 008D406FFH, 041226500H, 06A98A8FFH, 07AB0A2FFH
	DD 0006A6A01H, 05C1EB900H, 07AB0A2FFH, 001226A71H
	DD 008D46AFFH, 062B05140H, 0006A6A0DH, 05C1EB900H
	DD 009743EFFH, 0087C90FFH, 058506500H, 041346500H
	DD 06AB8A020H, 008C837FFH, 05BC86A00H, 05BDE6AFFH
	DD 008C8F8FFH, 008C84FFFH, 05BC86A01H, 05BDEB900H
	DD 0189E4F01H, 001226A02H, 05C8C6500H, 041346500H
	DD 001226A41H, 041226500H, 00140A004H, 05CA46500H
	DD 041346500H, 07A903610H, 031463805H, 031581404H
	DD 03160A903H, 000CC6AA3H, 05C046A38H, 000CC6AACH
	DD 05C066A14H, 05C086AA9H, 042906500H, 0086C36EFH
	DD 042906500H, 008C8640FH, 008C86407H, 0006E3700H
	DD 000A46AFFH, 05B986500H, 072FC51FFH, 07B063620H
	DD 05B869000H, 043086500H, 008D406FFH, 05BF26500H
	DD 063223DE0H, 063221220H, 05B306A51H, 05B806500H
	DD 008C837FFH, 0631AA100H, 07B1AA004H, 00940A0FBH
	DD 0006C3680H, 07A90A080H, 00940A07FH, 05B2C6AFFH
	DD 042906500H, 07B20A004H, 05CA46500H, 043226500H
	DD 05C8C6500H, 001226A31H, 05B2C6A0CH, 042906500H
	DD 001226A61H, 042906500H, 000063D10H, 00C6865FFH
	DD 008D406FFH, 07B320C01H, 06B320C04H, 0087A03E0H
	DD 063463DE0H, 008CC65FFH, 00CDA12FFH, 00CD406FFH
	DD 0080C65FFH, 07B420B02H, 00CD46AFFH, 001226AD1H
	DD 041226500H, 0092665FFH, 06B5A0B01H, 07B4C0C10H
	DD 06B540B04H, 008CA6AFFH, 06B589304H, 07B569401H
	DD 06B589410H, 0092693C7H, 008D499FFH, 06B5C9338H
	DD 00CD46AFFH, 06B603680H, 005226A21H, 0092065FFH
	DD 0636E51FFH, 008C837FFH, 0437A6AA1H, 008C851FFH
	DD 0437A6AB9H, 008A490FFH, 0737EBAFFH, 00920BAFFH
	DD 018CA65FFH, 063726C00H, 00CCA90FFH, 004CA6AFFH
	DD 07B923620H, 05B669000H, 0739265FFH, 0739052FFH
	DD 008CCBAFFH, 0092052FFH, 0097466FFH, 00D2065FFH
	DD 00C7EBAFFH, 05C926A00H, 0006A6A0DH, 0441E5100H
	DD 073EC3FFFH, 000A26AFFH, 05B663F00H, 073EC65FFH
	DD 0006C3620H, 06BA6A020H, 00CA2B9FFH, 004A26AFFH
	DD 008A465FFH, 000CC6AE0H, 05C126A45H, 001D06A01H
	DD 001D66A09H, 07BB2EB80H, 001D66A01H, 034A4E901H
	DD 000CC6A88H, 05C126A45H, 001186A01H, 0091A6AFFH
	DD 0091C6AFFH, 001266A0DH, 05C846500H, 00CA499FFH
	DD 008A465FFH, 000CC6AE0H, 05C126A45H, 001D06A01H
	DD 005DC6A01H, 000CC6A88H, 05C126A45H, 001186A01H
	DD 0091A6AFFH, 0091C6AFFH, 005266A01H, 031D86501H
	DD 001DCEE09H, 07BE2EE80H, 00DDC6AFFH, 0093265FFH
	DD 00126930AH, 044846500H, 008C837FFH, 05BA86A00H
	DD 00CA252FFH, 07BF20C01H, 06BF20C04H, 0080603E0H
	DD 00C7A03E0H, 008108CFFH, 008128DFFH, 00C148EFFH
	DD 008DA6CFFH, 008DA6CFFH, 008DA6CFFH, 008DA6CFFH
	DD 008DA6CFFH, 008DA6CFFH, 00CDA6CFFH, 028A4643DH
	DD 028C86455H, 018DA6C00H, 008C852FFH, 020DA6C00H
	DD 008C86AFFH, 020DA6C00H, 024DA6C00H, 008C865FFH
	DD 000CC6AE0H, 05C0E6A41H, 009E290FFH, 001D06A20H
	DD 07C303504H, 001DC6A1DH, 0642CEEDCH, 0443C6500H
	DD 001DC6A01H, 031D8A020H, 001DCEE09H, 07C36EE80H
	DD 001DC6A19H, 0643AEED8H, 009DC6AFFH, 06C3EEE18H
	DD 00CD46AFFH, 000CC6A88H, 05C0E6A41H, 001186A20H
	DD 0091A6AFFH, 0091C6AFFH, 0092635FFH, 06C683504H
	DD 000CA6AA0H, 018C86520H, 009326CFFH, 009326CFFH
	DD 009326CFFH, 009326CFFH, 009326CFFH, 009326CFFH
	DD 009326CFFH, 009326CFFH, 064546500H, 00126930AH
	DD 05C846500H, 07B603504H, 05C746AA0H, 05C766500H
	DD 05C766500H, 044766500H, 008CC65FFH, 008DA99FFH
	DD 008DA99FFH, 008DA99FFH, 008DA99FFH, 008DA99FFH
	DD 008DA99FFH, 00CDA99FFH, 07C849408H, 0092693F7H
	DD 06C889308H, 00CD46AFFH, 0097440FFH, 0088090FFH
	DD 005726AFFH, 064A040FFH, 064983FFFH, 004CA6AFFH
	DD 009203FFFH, 0006A6A01H, 05C1EB900H, 00C7EBAFFH
	DD 0092040FFH, 00C80BAFFH, 009743FFFH, 00C7E90FFH
	DD 0H
END SeqProgram;

PROCEDURE GetNext*(VAR line: SET): BOOLEAN;
VAR  opcode, c: LONGINT; parity: BOOLEAN;
BEGIN
(*
	WHILE Patches[patch].begin < pc DO INC(patch) END;

	WHILE (Patches[patch].begin = pc) & ~F[Patches[patch].f] DO	(*patch disabled, skip*)
		INC(pc, Patches[patch].skipinstr); INC(patch, Patches[patch].skippatch)
	END;
	
	(*IF Patches[patch].begin = pc THEN INC(patch) END;*)
*)
	WHILE (Patches[patch].begin = pc) DO
		IF F[Patches[patch].f] THEN
			INC(patch)
		ELSE
			INC(pc, Patches[patch].skipinstr); INC(patch, Patches[patch].skippatch)
		END
	END;
	
	
	SYSTEM.GET(Base+pc*4, line);
	IF line # {} THEN
		opcode := SYSTEM.VAL(LONGINT, SYSTEM.LSH(line*{27..30}, -27));
		IF (8<=opcode) & (opcode<=0FH) THEN	(*patch jump addr*)
			CorrectAddr(line)
		END;
		                                                                                               
		IF (opcode # 5) & (31 IN line) THEN 	(*all but ROL, patch immediate*)
			line := line- {0..7, 31};	(*use dconst*)
		END;
		
		IF F[8](*Ultra2*) THEN
			parity := TRUE;
			FOR c := 0 TO 30 DO
				IF c IN line THEN parity := ~parity END
			END;
			IF parity THEN  INCL(line, 31)  END
		ELSIF (8<=opcode) & (opcode<=0FH) THEN	(*format3*)
			line := line*{0..16} + SYSTEM.LSH(line*{17..26}, -17+16) + SYSTEM.LSH(line*{27..30}, -27+25);
		ELSE	(*format1*)
			line := line*{0..16} + SYSTEM.LSH(line*{17..25}, -17+16) + SYSTEM.LSH(line*{26}, -26+24) + 
				SYSTEM.LSH(line*{27..30}, -27+25)
		END;
		INC(pc)
	END;
	RETURN line # {}
END GetNext;

PROCEDURE Init*(Ultra2, Ultra, Wide, Twin, PageSCB, QueueRegs, CmdChan, TargetMode, Aic7895: BOOLEAN);
BEGIN
	pc := 0; patch := 0;
	F[13] := Aic7895;
	F[12] := ~CmdChan;
	F[11] := Wide;
	F[10] := ~Ultra2;
	F[9] := Ultra;
	F[8] := Ultra2;
	F[7] := ~PageSCB;
	F[6] := PageSCB;
	F[5] := QueueRegs;
	F[4] := Twin;
	F[3] := ~QueueRegs;
	F[2] := CmdChan;
	F[1] := TargetMode;
	F[0] := FALSE;
(*	old version
	F[0] := FALSE;		(*defined like that!*)
	F[1] := FALSE;		(*target mode = TRUE, never used*)
	F[2] := CmdChan;
	F[3] := ~QueueRegs;
	F[4] := Twin;
	F[5] := QueueRegs;
	F[6] := PageSCB;
	F[7] := ~PageSCB;
	F[8] := Ultra2;
	F[9] := Ultra;
	F[10] := ~Ultra2;
	F[11] := Wide;
	F[12] := FALSE;	(*defined like that!*)
*)
END Init;

(*
PROCEDURE Test*;
VAR i: LONGINT; line: SET;
BEGIN
		(*test for AIC7890*)
	Init(TRUE, FALSE, TRUE, FALSE, TRUE, TRUE, TRUE, FALSE, FALSE);
	i := 0; WHILE GetNext(line) DO INC(i) END;
	Kernel.WriteString("Test - AIC7890 -> "); Kernel.WriteInt(i, 4); Kernel.WriteLn;
	
		(*test for AHA2940A *)
	Init(FALSE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE);
	i := 0; WHILE GetNext(line) DO INC(i) END;
	Kernel.WriteString("Test - AHA2940A -> "); Kernel.WriteInt(i, 4); Kernel.WriteLn;
END Test;
*)

BEGIN	Base := SeqProgram(); LoadPatches;
END Adaptec7Script.Test



	Converting Linux aic7xxx_seq.c:
	
	1) generate sequencer code
	
cp aic7xxx_seq.c seqprog
chmod a+w seqprog
vi seqprog
:1
/{
:1,.d
/}
:.,$d
:%s/[ 	]*0x\(..\), 0x\(..\), 0x\(..\), 0x\(..\),/\U0\4\3\2\1H/
:g/^/j
:g/^/j
:%s/ /, /g
:%s/^/	DD /
:wq


	2) generate patch code

cp aic7xxx_seq.c seqpatches
chmod a+w seqpatches
vi seqpatches
:1
/sequencer_patches
:1,.d
:%s/.*patch\([0-9][0-9]*\)_func\(.*\) }.*/SetPatch(\1 \2);/
	!!! stop here: how many substitutions? -> number of patches !!!
:g/^/j
:g/^/j
:%s/^/	/
:.,$d
:wq

	3) check the patches functions

less aic7xxx_seq.c
/aic7xxx_patch