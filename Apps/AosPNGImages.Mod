(* PNG 1.2 Portable Network Graphics *)
(* TF 28.9.2000 *)
(* ftp://ftp.uu.net/graphics/png/images/ *)

(* Implementation restrictions  

 - no interlace
 - slow
 - read only
*)

MODULE AosPNGImages; (** AUTHOR "TF"; PURPOSE "PNG image format (supports alpha)"; *)

IMPORT SYSTEM, AosOut, CRC, Raster, AosIO, AosFS, ZlibBuffers, ZlibInflate;

CONST BufSize= 4096 * 8; Trace = FALSE;
VAR StartingRow, StartingCol, RowIncrement, ColIncrement: ARRAY 7 OF LONGINT;

TYPE
    (* lenght = Chunksize -ChunkHeader -ChunkChecksum*)
    ChunkHeader = RECORD length:LONGINT; name:ARRAY 5 (* ....+0H*) OF CHAR END;

    PNGHead = RECORD
                  width     : LONGINT;
                  height    : LONGINT;
                  bitDepth  : LONGINT; (* Byte *)
                  colorType : LONGINT; (* Byte *)
                  compressMethod: LONGINT; (* Byte *)
                  filterMethod: LONGINT; (* Byte *)
                  interlaceMethod: LONGINT; (* Byte *)
               END;
               
	PictureDecoder = OBJECT
		VAR
			h: PNGHead;
			png : PNG;
			
			pic:Raster.Image;
			format8:Raster.Format;
			palette:Raster.Palette;
		
		bpp: LONGINT; (* bytes per complete pixel rounded up to bytes*)
		
		(* bytes per line - filtertyp byte *)
		PROCEDURE GetLineSize(width:LONGINT):LONGINT;
		BEGIN
			CASE h.colorType OF
				 0: RETURN (h.bitDepth*width+7) DIV 8
				|2: RETURN (h.bitDepth DIV 8)*3*width
				|3: RETURN (h.bitDepth*width+7) DIV 8
				|4: RETURN (h.bitDepth DIV 4)*width
				|6: RETURN (h.bitDepth DIV 2)*width
			END
		END GetLineSize;
		
		PROCEDURE &Init(h:PNGHead; p:PNG); 
		BEGIN
			 png:=p;
			SELF.h:=h;
			NEW(pic); 
			CASE h.colorType OF
				 0: (* grayscale possibly 1, 2, 4, 8, 16 bit *)
					(* neither 16 bit nor grayscale support in Raster *)
					Raster.Create(pic, h.width, h.height, Raster.BGR888);
					bpp:=(h.bitDepth+7) DIV 8
				|2: (* RGB, 8 or 16 bit*)
					(* no 16 bit support in Raster *)
					Raster.Create(pic, h.width, h.height, Raster.BGR888);
					bpp:=(3*h.bitDepth+7) DIV 8
				|3: (* color mapped 1, 2, 4, 8 bit *)
					NEW(palette);
					Raster.InitPalette(palette, 256, 5);
					Raster.InitPaletteFormat(format8, palette);
					Raster.Create(pic, h.width, h.height, format8);
					bpp:=1
				|4: (* greyscale + alpha 8 or 16 bit *)
					(* neither 16 bit nor grayscale support in Raster *)
					Raster.Create(pic, h.width, h.height, Raster.BGRA8888);
					bpp:=(h.bitDepth*2) DIV 8
				|6: (* RGB + alpha 8 or 16 bit *)
					(* no 16 bit support in Raster *)
					Raster.Create(pic, h.width, h.height, Raster.BGRA8888);
					bpp:=(4*h.bitDepth) DIV 8
			ELSE
				Error("Unknown Color Type");
			END;	
		END Init;
		
		PROCEDURE Error(msg:ARRAY OF CHAR);
		BEGIN
			AosOut.String(msg); AosOut.Ln
		END Error;
				
		PROCEDURE Decode;
		VAR x, y, cp:LONGINT;
				filter, ls:LONGINT;
				p:LONGINT;
				c, r, g, b, a, dummy:CHAR;
				prior, current, temp:POINTER TO ARRAY OF CHAR;
				currentByte:CHAR;
				bitPos:LONGINT;
				lastRowStart:LONGINT;
				
				zlibs: ZlibInflate.Stream; 
				zlibout: ARRAY BufSize OF CHAR;
				
				PROCEDURE GetNextBit():CHAR;
				VAR result:CHAR;
				BEGIN
					IF bitPos MOD 8 = 0 THEN currentByte:=GetNextFilterByte(); bitPos:=0  END;
					INC(bitPos);
					result:=CHR(ORD(SYSTEM.LSH(currentByte, bitPos-8 )) MOD 2);
					RETURN result
				END GetNextBit;
				
				PROCEDURE GetNext2Bits():CHAR;
				VAR result:CHAR;
				BEGIN
					IF bitPos MOD 8 = 0 THEN currentByte:=GetNextFilterByte(); bitPos:=0 END;
					INC(bitPos, 2);
					result:=CHR(ORD(SYSTEM.LSH(currentByte, bitPos-8)) MOD 4);
					RETURN result
				END GetNext2Bits;
				
				PROCEDURE GetNext4Bits():CHAR;
				VAR result:CHAR;
				BEGIN
					IF bitPos MOD 8 = 0 THEN currentByte:=GetNextFilterByte(); bitPos:=0 END;
					INC(bitPos, 4);
					result:=CHR(ORD(SYSTEM.LSH(currentByte, bitPos-8)) MOD 16);
		
					RETURN result
				END GetNext4Bits;
				
				PROCEDURE PaethPredictor(a, b, c:LONGINT):CHAR;
				VAR p, pa, pb, pc:LONGINT;
				BEGIN
					p:=a+b-c; pa:=ABS(p-a); pb:=ABS(p-b); pc:=ABS(p-c);
					IF (pa<=pb) & (pa<=pc) THEN RETURN CHR(a)
					ELSIF (pb<=pc) THEN RETURN CHR(b)
					ELSE RETURN CHR(c)
					END
				END PaethPredictor;
				
				PROCEDURE GetNextFilterByte():CHAR;
				VAR result:CHAR;
						t1, t2:LONGINT;
				BEGIN
					CASE filter OF 
						 0: result:=current[cp]
						|1:result:=CHR(ORD(current[cp])+ORD(current[cp-bpp]));
						|2:result:=CHR(ORD(current[cp])+ORD(prior[cp])) 
						|3:t1:=ORD(current[cp-bpp]); t2:=ORD(prior[cp]); result:=CHR(ORD(current[cp])+(t1+t2) DIV 2)
						|4:result:=CHR(ORD(current[cp])+
							ORD(PaethPredictor(ORD(current[cp-bpp]), ORD(prior[cp]), ORD(prior[cp-bpp]))))
					ELSE
						Error("illegal filter type")
					END; current[cp]:=result; 
					INC(cp);
					RETURN result
				END GetNextFilterByte;
				
				PROCEDURE GetZByte():CHAR;
				VAR out:ARRAY 1 OF CHAR;
				BEGIN
					IF zlibs.out.size-zlibs.out.avail < 1 THEN ZlibInflate.Inflate(zlibs, ZlibInflate.FullFlush) END;
					ZlibBuffers.Drain(zlibs.out, out, 0, 1);
					RETURN out[0]
				END GetZByte;
				
				PROCEDURE GetZBytes(VAR buf:ARRAY OF CHAR; ofs, len:LONGINT);
				BEGIN
					IF zlibs.out.size-zlibs.out.avail < len THEN ZlibInflate.Inflate(zlibs, ZlibInflate.FullFlush) END;
					ZlibBuffers.Drain(zlibs.out, buf, ofs, len);
				END GetZBytes;
				
		BEGIN {EXCLUSIVE}
			ZlibInflate.Open(zlibs, TRUE); 
			IF zlibs.res.code = ZlibInflate.Ok THEN
				ZlibBuffers.Init(zlibs.in, png.buf^, 0, png.bufPos, png.bufPos);
				ZlibBuffers.Init(zlibs.out, zlibout, 0, BufSize, BufSize)
			END;
			ZlibInflate.Inflate(zlibs, ZlibInflate.FullFlush);
		
			bitPos:=0;
			p:=pic.adr;								
			IF Trace THEN AosOut.String("bpp:"); AosOut.Int(bpp, 8); AosOut.Ln; END;
			ls:=GetLineSize(h.width);NEW(prior, ls+bpp); NEW(current, ls+bpp);
			
			IF h.interlaceMethod=0 THEN
				FOR y:=0 TO h.height-1 DO
					lastRowStart:=p;
					filter:=ORD(GetZByte()); (*AosOut.String("Filter"); AosOut.Int(filter, 5); AosOut.Ln;*)
					cp:=bpp;
				(*	FOR x:=0 TO ls-1 DO current[cp]:=GetZByte(); INC(cp) END; *)
					GetZBytes(current^, cp, ls);
					cp:=bpp;
					
					CASE h.colorType OF
						0: (* color type 0 grayscale*)
							 FOR x:=0 TO h.width -1 DO 
								CASE h.bitDepth OF 
									1: c:=CHR(ORD(GetNextBit())*255)
									|2:c:=CHR(ORD(GetNext2Bits())*85)
									|4:c:=CHR(ORD(GetNext4Bits())*16)
									|8:c:=GetNextFilterByte()
									|16:c:=GetNextFilterByte(); dummy:=GetNextFilterByte()
								END;							
								SYSTEM.PUT8(p, c); INC(p);
								SYSTEM.PUT8(p, c); INC(p);
								SYSTEM.PUT8(p, c); INC(p);
							END								
						|2:(* color type 2 rgb *)
								FOR x:=0 TO h.width-1 DO 
									r:=GetNextFilterByte(); IF h.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									g:=GetNextFilterByte(); IF h.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									b:=GetNextFilterByte(); IF h.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									SYSTEM.PUT8(p, b); INC(p);
									SYSTEM.PUT8(p, g); INC(p);
									SYSTEM.PUT8(p, r); INC(p);
							END	
						|3: (* color type 3 *)
								FOR x:=0 TO h.width -1 DO 
									CASE h.bitDepth OF 
										1: c:=GetNextBit()
										|2:c:=GetNext2Bits()
										|4:c:=GetNext4Bits()
										|8:c:=GetNextFilterByte()
									END;							
									SYSTEM.PUT8(p, c); INC(p)
								END								
						|4:(* color type 4 grayscale + alpha *)
									FOR x:=0 TO h.width-1 DO 
										c:=GetNextFilterByte(); IF h.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
										a:=GetNextFilterByte(); IF h.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
										c:=CHR(ORD(c)*ORD(a) DIV 256);
										SYSTEM.PUT8(p, c); INC(p);
										SYSTEM.PUT8(p, c); INC(p);
										SYSTEM.PUT8(p, c); INC(p);
										SYSTEM.PUT8(p, a); INC(p)
									END;						
						|6:(* color type 6 rgb + alpha *)
								FOR x:=0 TO h.width-1 DO 
									r:=GetNextFilterByte(); IF h.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									g:=GetNextFilterByte(); IF h.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									b:=GetNextFilterByte(); IF h.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									a:=GetNextFilterByte(); IF h.bitDepth = 16 THEN dummy:=GetNextFilterByte() END;
									SYSTEM.PUT8(p, CHR(ORD(b)*ORD(a) DIV 256)); INC(p);
									SYSTEM.PUT8(p, CHR(ORD(g)*ORD(a) DIV 256)); INC(p);
									SYSTEM.PUT8(p, CHR(ORD(r)*ORD(a) DIV 256)); INC(p);
									SYSTEM.PUT8(p, a); INC(p)
								END
					END;							
					IF bitPos MOD 8 # 0 THEN bitPos:=0 END;
					p:=lastRowStart+pic.bpr;
					temp:=prior; prior:=current; current:=temp
				END
			ELSE Error("interlace not yet supported") 
			END
		END Decode;
	
	END PictureDecoder;               
	
	PNG = OBJECT
		VAR
			fs: AosFS.Reader;
			file: AosFS.File;
			errors:BOOLEAN;
			first, last, isIDAT:BOOLEAN;
			hdr:PNGHead;
			crc : CRC.CRC32Stream;
			pidec:PictureDecoder;
			
			buf:POINTER TO ARRAY OF CHAR;
			bufPos:LONGINT;

		PROCEDURE ReadChunkHeader(VAR x: ChunkHeader);
		VAR i:LONGINT;
		BEGIN
			x.length := GetLongint(); (* NOT IN CRC ! *)
			crc.Reset;
			FOR i := 0 TO 3 DO x.name[i] := GetByte() END;
			x.name[4] := CHR(0)
		END ReadChunkHeader;

		PROCEDURE Error(x:ARRAY OF CHAR);
		BEGIN
			AosOut.String(x); AosOut.Ln;
			errors := TRUE 
		END Error;

		PROCEDURE ValidateHdr;
		BEGIN
			IF Trace THEN 
				AosOut.String("width:");  AosOut.Int(hdr.width, 4); AosOut.Ln;
				AosOut.String("height:");  AosOut.Int(hdr.height, 4); AosOut.Ln;
				AosOut.String("colorType:");  AosOut.Int(hdr.colorType, 4); AosOut.Ln;
				AosOut.String("bit depth:");  AosOut.Int(hdr.bitDepth, 4); AosOut.Ln
			END	
		END ValidateHdr;

		PROCEDURE SkipChunk(x:ChunkHeader);
		VAR i:LONGINT;  dummy:CHAR;
		BEGIN
			FOR i := 0 TO x.length - 1 DO dummy := GetByte() END
		END SkipChunk;
		
		PROCEDURE CheckCRC;
		VAR t, ccrc:LONGINT;
		BEGIN
			ccrc := crc.GetCRC();
			t := GetLongint(); 
			IF ccrc # t THEN Error("crc-error") END		
		END CheckCRC;

		PROCEDURE ProcessChunk(x:ChunkHeader);
		VAR i, bytesRead: LONGINT;
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
				NEW(pidec, hdr, SELF);
				NEW(buf, file.Length()); bufPos := 0;
				ValidateHdr
			ELSIF x.name = "PLTE" THEN 
				FOR i := 0 TO (x.length DIV 3) - 1 DO 
					Raster.SetRGB(pidec.palette.col[i], ORD(GetByte()), ORD(GetByte()), ORD(GetByte()))
				END
			ELSIF x.name = "IDAT" THEN 
		(*		FOR i:=0 TO x.length-1 DO buf[i+bufPos]:=GetByte() END; *)
				fs.Bytes(buf^, bufPos, x.length, bytesRead); 
				crc.Bytes(buf^, bufPos, x.length); 
				INC(bufPos, x.length);
				isIDAT := TRUE
			ELSIF x.name = "gAMA" THEN SkipChunk(x)
			ELSIF x.name = "sBIT" THEN SkipChunk(x)
			ELSIF x.name = "cHRM" THEN SkipChunk(x)
			ELSIF x.name = "tRNS" THEN 
				IF Trace THEN AosOut.String("Alpha-Palette!!") END;
				FOR i := 0 TO (x.length)-1 DO
					pidec.palette.col[i][3] := GetByte();
					pidec.palette.col[i][0] := CHR(ORD(pidec.palette.col[i][0]) * ORD(pidec.palette.col[i][3]) DIV 256);
					pidec.palette.col[i][1] := CHR(ORD(pidec.palette.col[i][1]) * ORD(pidec.palette.col[i][3]) DIV 256);
					pidec.palette.col[i][2] := CHR(ORD(pidec.palette.col[i][2]) * ORD(pidec.palette.col[i][3]) DIV 256);
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
			CheckCRC
		END ProcessChunk;

		PROCEDURE &Create(name: ARRAY OF CHAR);
		BEGIN
			NEW(crc);
			errors:=FALSE;
			file := AosFS.Old(name);
			IF file = NIL THEN Error("File not found"); RETURN END;
			AosFS.OpenReader(fs, file, 0)
		END Create;

		PROCEDURE GetByte(): CHAR;
		VAR result:CHAR;
		BEGIN
			fs.Char(result);
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
	
		PROCEDURE ReadHeader;
		VAR isPNG:BOOLEAN;
		    i:LONGINT;
		    ch:ChunkHeader;
		BEGIN
			IF ~errors THEN
				isPNG:=TRUE;		
				FOR i:=0 TO 7 DO IF GetByte()#MagicID[i] THEN isPNG:=FALSE END END;
				first:=TRUE; last:=FALSE; isIDAT := FALSE;
				REPEAT
					ReadChunkHeader(ch);
					IF Trace THEN 
						AosOut.String("Chunk: ");  AosOut.String(ch.name); AosOut.String("length:"); AosOut.Int(ch.length, 4); AosOut.Ln;
					END;
					ProcessChunk(ch)
				UNTIL isIDAT OR last OR errors;
				IF Trace THEN AosOut.String("begin decoding"); AosOut.Ln END;
				pidec.Decode;
			
				IF Trace THEN IF ~errors THEN AosOut.String("no errors") ELSE AosOut.String("errors occured") END; AosOut.Ln
				END;
			END
		END ReadHeader;
		
	END PNG;
	
VAR MagicID : ARRAY 8 OF CHAR;

PROCEDURE Load (img: Raster.Image; VAR name: ARRAY OF CHAR; VAR done: BOOLEAN);
VAR p : PNG;
		mode:Raster.Mode;
BEGIN
	done := FALSE;
	NEW(p, name);
	IF ~p.errors THEN 
		p.ReadHeader;
		Raster.InitMode(mode, Raster.srcCopy);
		IF p.pidec.h.colorType IN {4, 6} THEN 
			Raster.Create(img, p.pidec.pic.width, p.pidec.pic.height, Raster.BGRA8888)
		ELSE
			Raster.Create(img, p.pidec.pic.width, p.pidec.pic.height, Raster.BGR565)
		END;
		Raster.Copy(p.pidec.pic, img, 0, 0, p.pidec.pic.width, p.pidec.pic.height, 0, 0, mode);
		done := TRUE
	END
END Load;

PROCEDURE AosLoad*(x: PTR) : PTR;
BEGIN
	IF x IS Raster.PictureTransferParameters THEN WITH x:Raster.PictureTransferParameters DO
		Load(x.img, x.name, x.done)
	END END;	
	RETURN NIL
END AosLoad;

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
END AosPNGImages.

 

System.Free AosPNGImages ~ System.Free Inflate~
Aos.Call WMPicView.Open BluebottlePic0.png ~
