(* PNG 1.2 Portable Network Graphics *)
(* TF 28.9.2000 *)
(* TF 23.8.2004 updated with AosCodecs and AosInflate *)
(* ftp://ftp.uu.net/graphics/png/images/ *)
MODULE AosPNGDecoder; (** AUTHOR "TF"; PURPOSE "PNG decoder"; *)

IMPORT
	 SYSTEM, AosOut, CRC, Raster, AosIO, AosFS, AosInflate, WMGraphics,
	 AosCodecs;

CONST 
	BufSize = 4096 * 8; Trace = FALSE;

VAR 
	StartingRow, StartingCol, RowIncrement, ColIncrement: ARRAY 7 OF LONGINT;

TYPE
	(* lenght = Chunksize -ChunkHeader -ChunkChecksum*)
	ChunkHeader = RECORD length : LONGINT; name : ARRAY 5 (* ....+0H*) OF CHAR END;

	PNGHead = RECORD
		width : LONGINT;
		height : LONGINT;
		bitDepth : LONGINT; (* Byte *)
		colorType : LONGINT; (* Byte *)
		compressMethod : LONGINT; (* Byte *)
		filterMethod: LONGINT; (* Byte *)
		interlaceMethod: LONGINT; (* Byte *)
	END;
	
	IDATReader* = OBJECT
	VAR (* General vars: *)
		inR: AosIO.Reader;
		remain: LONGINT;
		eof : BOOLEAN;
		PROCEDURE &Init(firstChunk : LONGINT; inR : AosIO.Reader; VAR outR: AosIO.Reader);
		BEGIN
			SELF.inR := inR;
			AosIO.OpenReader(outR, Receiver);
			eof := FALSE;
			remain := firstChunk;
		END Init;	
		
		PROCEDURE Receiver(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		VAR i, crc, tag: LONGINT; token: ARRAY 16 OF CHAR; ch: CHAR;			
		BEGIN 
			IF ~eof THEN
				ASSERT((size > 0) & (min <= size) & (min >= 0));
				len := 0; i := ofs; res := AosIO.Ok;
				WHILE (res = AosIO.Ok) & (len < size) & ~eof DO
					(* Read the chunk size *)
					IF remain = 0 THEN
						crc := inR.Net32();
					(*	AosOut.String("crc= "); AosOut.Hex(crc, 0); AosOut.Ln;  *)
						remain := inR.Net32();
				(*		AosOut.String("remain= "); AosOut.Int(remain, 0); AosOut.Ln;  *)
						tag := inR.Net32();
(*						AosOut.String("tag= "); AosOut.Hex(tag, 0); AosOut.Ln; *)
						IF tag # 049444154H THEN eof := TRUE END;
					END;
					(* Fill data into out buffer *)
					WHILE (res = AosIO.Ok) & (len < size) & (remain > 0) DO
						inR.Char(ch);
						res := inR.res; 
						buf[i] := ch;
						INC(len); INC(i); DEC(remain);
					END;
				END;
			ELSE
				res := AosIO.EOF
			END
		END Receiver;
	END IDATReader;	
	
	
	PNGDecoder = OBJECT(AosCodecs.ImageDecoder)
	VAR
		in : AosIO.Reader;
		errors : BOOLEAN;
		first, last, isIDAT : BOOLEAN;
		hdr : PNGHead;
		crc : CRC.CRC32Stream;

		pic : Raster.Image;
		format8 : Raster.Format;
		palette : Raster.Palette;
	
		bpp: LONGINT; (* bytes per complete pixel rounded up to bytes*)
		
		decoder : AosInflate.Reader;

		(* bytes per line - filtertyp byte *)
		PROCEDURE GetLineSize(width : LONGINT) : LONGINT;
		BEGIN
			CASE hdr.colorType OF
				 0: RETURN (hdr.bitDepth * width + 7) DIV 8
				|2: RETURN (hdr.bitDepth DIV 8) * 3 * width
				|3: RETURN (hdr.bitDepth * width + 7) DIV 8
				|4: RETURN (hdr.bitDepth DIV 4) * width
				|6: RETURN (hdr.bitDepth DIV 2) * width
			END
		END GetLineSize;
		
		PROCEDURE Init;
		BEGIN
			NEW(pic); 
			CASE hdr.colorType OF
				 0: (* grayscale possibly 1, 2, 4, 8, 16 bit *)
					(* neither 16 bit nor grayscale support in Raster *)
					Raster.Create(pic, hdr.width, hdr.height, Raster.BGR888);
					bpp := (hdr.bitDepth + 7) DIV 8
				|2: (* RGB, 8 or 16 bit*)
					(* no 16 bit support in Raster *)
					Raster.Create(pic, hdr.width, hdr.height, Raster.BGR888);
					bpp := (3 * hdr.bitDepth + 7) DIV 8
				|3: (* color mapped 1, 2, 4, 8 bit *)
					NEW(palette);
					Raster.InitPalette(palette, 256, 5);
					Raster.InitPaletteFormat(format8, palette);
					Raster.Create(pic, hdr.width, hdr.height, format8);
					bpp := 1
				|4: (* greyscale + alpha 8 or 16 bit *)
					(* neither 16 bit nor grayscale support in Raster *)
					Raster.Create(pic, hdr.width, hdr.height, Raster.BGRA8888);
					bpp := (hdr.bitDepth * 2) DIV 8
				|6: (* RGB + alpha 8 or 16 bit *)
					(* no 16 bit support in Raster *)
					Raster.Create(pic, hdr.width, hdr.height, Raster.BGRA8888);
					bpp := (4 * hdr.bitDepth) DIV 8
			ELSE Error("Unknown Color Type")
			END;	
		END Init;
				
		PROCEDURE Decode;
		VAR x, y, cp : LONGINT;
			filter, ls : LONGINT;
			p : LONGINT;
			c, r, g, b, a, dummy : CHAR;
			prior, current, temp : POINTER TO ARRAY OF CHAR;
			currentByte : CHAR;
			bitPos : LONGINT; 
			lastRowStart : LONGINT;
			len : LONGINT;
				
			PROCEDURE GetNextBit() : LONGINT;
			BEGIN
				IF bitPos MOD 8 = 0 THEN currentByte := GetNextFilterByte(); bitPos := 0  END;
				INC(bitPos);
				RETURN ORD(SYSTEM.LSH(currentByte, bitPos-8 )) MOD 2
			END GetNextBit;
			
			PROCEDURE GetNext2Bits() : LONGINT;
			BEGIN
				IF bitPos MOD 8 = 0 THEN currentByte := GetNextFilterByte(); bitPos := 0 END;
				INC(bitPos, 2);
				RETURN ORD(SYSTEM.LSH(currentByte, bitPos-8)) MOD 4
			END GetNext2Bits;
			
			PROCEDURE GetNext4Bits() : LONGINT;
			BEGIN
				IF bitPos MOD 8 = 0 THEN currentByte := GetNextFilterByte(); bitPos := 0 END;
				INC(bitPos, 4);
				RETURN ORD(SYSTEM.LSH(currentByte, bitPos-8)) MOD 16
			END GetNext4Bits;
			
			PROCEDURE PaethPredictor(a, b, c : LONGINT) : CHAR;
			VAR p, pa, pb, pc:LONGINT;
			BEGIN
				p := a + b - c; pa := ABS(p - a); pb := ABS(p - b); pc := ABS(p - c);
				IF (pa <= pb) & (pa <= pc) THEN RETURN CHR(a)
				ELSIF (pb <= pc) THEN RETURN CHR(b)
				ELSE RETURN CHR(c)
				END
			END PaethPredictor;
			
			PROCEDURE GetNextFilterByte() : CHAR;
			VAR result:CHAR;
					t1, t2:LONGINT;
			BEGIN
				CASE filter OF 
					| 0 : result := current[cp]
					|1 : result := CHR(ORD(current[cp])+ORD(current[cp-bpp]));
					|2 : result := CHR(ORD(current[cp])+ORD(prior[cp])) 
					|3 : t1 := ORD(current[cp-bpp]); t2 := ORD(prior[cp]); result:=CHR(ORD(current[cp])+(t1+t2) DIV 2)
					|4 : result := CHR(ORD(current[cp])+
						ORD(PaethPredictor(ORD(current[cp-bpp]), ORD(prior[cp]), ORD(prior[cp-bpp]))))
				ELSE
					AosOut.String("filter= "); AosOut.Int(filter, 0); 
					Error("illegal filter type")
				END; current[cp] := result; 
				INC(cp);
				RETURN result
			END GetNextFilterByte;
			
		BEGIN
			bitPos := 0; 
			p := pic.adr;								
			IF Trace THEN AosOut.String("bpp:"); AosOut.Int(bpp, 8); AosOut.Ln; END;
			ls := GetLineSize(hdr.width); NEW(prior, ls + bpp); NEW(current, ls + bpp);
			
			IF hdr.interlaceMethod = 0 THEN
				FOR y := 0 TO hdr.height - 1 DO
					lastRowStart := p;
					filter := ORD(decoder.Get());
					cp := bpp;
					decoder.Bytes(current^, cp, ls, len); 
					cp := bpp;
					CASE hdr.colorType OF
						|0: (* color type 0 grayscale*)
							 FOR x := 0 TO hdr.width -1 DO 
								CASE hdr.bitDepth OF 
									|1 : c := CHR(GetNextBit() * 255)
									|2 : c := CHR(GetNext2Bits() * 85)
									|4 : c := CHR(GetNext4Bits() * 16)
									|8 : c := GetNextFilterByte()
									|16 : c := GetNextFilterByte(); dummy := GetNextFilterByte()
								END;							
								SYSTEM.PUT8(p, c); INC(p);
								SYSTEM.PUT8(p, c); INC(p);
								SYSTEM.PUT8(p, c); INC(p);
							END								
						|2:(* color type 2 rgb *)
								FOR x := 0 TO hdr.width-1 DO 
									r := GetNextFilterByte(); IF hdr.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									g := GetNextFilterByte(); IF hdr.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									b := GetNextFilterByte(); IF hdr.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									SYSTEM.PUT8(p, b); INC(p);
									SYSTEM.PUT8(p, g); INC(p);
									SYSTEM.PUT8(p, r); INC(p);
							END	
						|3: (* color type 3 *)
								FOR x:=0 TO hdr.width -1 DO 
									CASE hdr.bitDepth OF 
										|1 : c := CHR(GetNextBit())
										|2 : c := CHR(GetNext2Bits())
										|4 : c := CHR(GetNext4Bits())
										|8 : c := GetNextFilterByte()
									END;							
									SYSTEM.PUT8(p, c); INC(p)
								END								
						|4:(* color type 4 grayscale + alpha *)
									FOR x:=0 TO hdr.width-1 DO 
										c := GetNextFilterByte(); IF hdr.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
										a := GetNextFilterByte(); IF hdr.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
										c := CHR(ORD(c) * ORD(a) DIV 256);
										SYSTEM.PUT8(p, c); INC(p);
										SYSTEM.PUT8(p, c); INC(p);
										SYSTEM.PUT8(p, c); INC(p);
										SYSTEM.PUT8(p, a); INC(p)
									END;						
						|6:(* color type 6 rgb + alpha *)
								FOR x:=0 TO hdr.width-1 DO 
									r:=GetNextFilterByte(); IF hdr.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									g:=GetNextFilterByte(); IF hdr.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									b:=GetNextFilterByte(); IF hdr.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									a:=GetNextFilterByte(); IF hdr.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									SYSTEM.PUT8(p, CHR(ORD(b)*ORD(a) DIV 256)); INC(p);
									SYSTEM.PUT8(p, CHR(ORD(g)*ORD(a) DIV 256)); INC(p);
									SYSTEM.PUT8(p, CHR(ORD(r)*ORD(a) DIV 256)); INC(p);
									SYSTEM.PUT8(p, a); INC(p)
								END
					END;							
					bitPos := 0;
					p := lastRowStart + pic.bpr;
					temp := prior; prior := current; current := temp
				END
			ELSE Error("interlace not yet supported") 
			END
		END Decode;

		PROCEDURE ReadChunkHeader(VAR x: ChunkHeader);
		VAR i:LONGINT;
		BEGIN
			x.length := in.Net32(); (* NOT IN CRC ! *)
			crc.Reset;
			FOR i := 0 TO 3 DO x.name[i] := GetByte() END;
			x.name[4] := CHR(0)
		END ReadChunkHeader;

		PROCEDURE Error(x : ARRAY OF CHAR);
		BEGIN
			AosOut.String("PNG Decoder : ");
			AosOut.String(x); AosOut.Ln;
(*			errors := TRUE *)
		END Error;

		PROCEDURE SkipChunk(x : ChunkHeader);
		VAR i : LONGINT; dummy : CHAR;
		BEGIN
			FOR i := 0 TO x.length - 1 DO dummy := GetByte() END
		END SkipChunk;
		
		PROCEDURE CheckCRC;
		VAR t, ccrc:LONGINT;
		BEGIN
			ccrc := crc.GetCRC();
			t := in.Net32(); 
			IF ccrc # t THEN Error("crc-error"); HALT(1234) END		
		END CheckCRC;

		PROCEDURE ProcessChunk(x:ChunkHeader);
		VAR i, bytesRead: LONGINT;
			idatr : AosIO.Reader;
			idatReader : IDATReader;
		BEGIN
			IF first & ~(x.name = "IHDR") THEN Error("IHDR chunk expected"); RETURN END;
			IF x.name = "IHDR" THEN
			
				first := FALSE;
				hdr.width := GetLongint();
				hdr.height := GetLongint();
				hdr.bitDepth := ORD(GetByte());
				hdr.colorType := ORD(GetByte());
				hdr.compressMethod := ORD(GetByte());
				hdr.filterMethod := ORD(GetByte());
				hdr.interlaceMethod := ORD(GetByte());
			
				Init;
			ELSIF x.name = "PLTE" THEN 
				FOR i := 0 TO (x.length DIV 3) - 1 DO 
					Raster.SetRGB(palette.col[i], ORD(GetByte()), ORD(GetByte()), ORD(GetByte()))
				END
			ELSIF x.name = "IDAT" THEN 
				NEW(idatReader, x.length, in, idatr); 
				idatr.SkipBytes(2); (* should handle zlib *)
				NEW(decoder, idatr);
				Decode;

				isIDAT:= TRUE;
			ELSIF x.name = "gAMA" THEN SkipChunk(x)
			ELSIF x.name = "sBIT" THEN SkipChunk(x)
			ELSIF x.name = "cHRM" THEN SkipChunk(x)
			ELSIF x.name = "tRNS" THEN 
				IF Trace THEN AosOut.String("Alpha-Palette!!") END;
				NEW(palette);
				FOR i := 0 TO (x.length)-1 DO
					palette.col[i][3] := GetByte();
					palette.col[i][0] := CHR(ORD(palette.col[i][0]) * ORD(palette.col[i][3]) DIV 256);
					palette.col[i][1] := CHR(ORD(palette.col[i][1]) * ORD(palette.col[i][3]) DIV 256);
					palette.col[i][2] := CHR(ORD(palette.col[i][2]) * ORD(palette.col[i][3]) DIV 256);
				END;	
			ELSIF x.name = "bKGD" THEN SkipChunk(x)
			ELSIF x.name = "hIST" THEN SkipChunk(x)
			ELSIF x.name = "tEXt" THEN SkipChunk(x)
			ELSIF x.name = "zTXt" THEN SkipChunk(x)
			ELSIF x.name = "pHYs" THEN SkipChunk(x)
			ELSIF x.name = "oFFs" THEN SkipChunk(x)
			ELSIF x.name = "tIME" THEN SkipChunk(x)
			ELSIF x.name = "IEND" THEN last := TRUE; SkipChunk(x)
			ELSE SkipChunk(x) END;
			IF ~isIDAT  THEN CheckCRC ELSE i := in.Net32() END (* should CRC this, too *)
		END ProcessChunk;

		PROCEDURE GetByte(): CHAR;
		VAR result : CHAR;
		BEGIN
			in.Char(result); 
			crc.Char(result);
			RETURN result
		END GetByte;

		PROCEDURE GetLongint():LONGINT;
		VAR result:LONGINT;
		BEGIN
			result := ASH(ORD(GetByte()), 24);
			INC(result, ASH(ORD(GetByte()), 16));
			INC(result, ASH(ORD(GetByte()), 8));
			INC(result, ORD(GetByte()));
			RETURN result
		END GetLongint; 
	
		PROCEDURE Open*(in : AosIO.Reader; VAR res : LONGINT);
		VAR ch : ChunkHeader;
			i : LONGINT;
			isPNG : BOOLEAN;
		BEGIN
			res := -1;
			IF in = NIL THEN Error("Input Stream is NIL"); RETURN END;
			NEW(crc);
			SELF.in := in;
			errors := FALSE;
			isPNG := TRUE;
			FOR i := 0 TO 7 DO 
				IF GetByte() # MagicID[i] THEN isPNG := FALSE END 
			END;
			IF ~isPNG THEN Error("Not a PNG stream") 
			ELSE
				ReadChunkHeader(ch);
				ProcessChunk(ch);
				IF ~errors THEN res := 0 END
			END	
		END Open;
		
		PROCEDURE GetImageInfo*(VAR width, height, format, maxProgressionLevel : LONGINT);
		BEGIN
			width := hdr.width;
			height := hdr.height;
			format := 0;
			maxProgressionLevel := 0
		END GetImageInfo;
		
		PROCEDURE GetNativeImage*(VAR img : Raster.Image);
		VAR ch : ChunkHeader;
		BEGIN
			IF ~errors THEN
				REPEAT
					ReadChunkHeader(ch);
					ProcessChunk(ch)
				UNTIL isIDAT OR last OR errors;
			END;
			img := pic
		END GetNativeImage;

		PROCEDURE Render*(img : Raster.Image);
		VAR canvas : WMGraphics.BufferCanvas;
		BEGIN
			IF ~last & ~errors THEN GetNativeImage(pic) END;
			NEW(canvas, img);
			canvas.DrawImage(0, 0, pic, WMGraphics.ModeCopy);
		END Render;
		
	END PNGDecoder;
	
VAR MagicID : ARRAY 8 OF CHAR;

PROCEDURE Factory*(par : ANY) : ANY;
VAR p : PNGDecoder;
BEGIN
	NEW(p);
	RETURN p
END Factory;

BEGIN
	MagicID[0]:=CHR(137); MagicID[1]:='P'; MagicID[2]:='N'; MagicID[3]:='G'; MagicID[4]:=CHR(13); 
	MagicID[5]:=CHR(10); MagicID[6]:=CHR(26); MagicID[7]:=CHR(10); 

	(* constants for incremental decoding *)	
	StartingRow[0]:=0; StartingRow[1]:=0; StartingRow[2]:=4; StartingRow[3]:=0; 
	StartingRow[4]:=2; StartingRow[5]:=0;StartingRow[6]:=1;
	
	StartingCol[0]:=0; StartingCol[1]:=4; StartingCol[2]:=0; StartingCol[3]:=2; 
	StartingCol[4]:=0; StartingCol[5]:=1;StartingCol[6]:=0;
	
	RowIncrement[0]:=8; RowIncrement[1]:=8; RowIncrement[2]:=8; RowIncrement[3]:=4;
	RowIncrement[4]:=4; RowIncrement[5]:=2; RowIncrement[6]:=2;
	
	ColIncrement[0]:=8; ColIncrement[1]:=8; ColIncrement[2]:=4; ColIncrement[3]:=4; 
	ColIncrement[4]:=2; ColIncrement[5]:=2; ColIncrement[6]:=1
END AosPNGDecoder.


S.Free AosPNGDecoder ~
y.png ~
