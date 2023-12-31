MODULE TuringCoatWnd;	(* Soren Renner / TF *)

IMPORT WMWindowManager, Raster, AosRandom, AosActive, Rectangles := WMRectangles,
				Graphics := WMGraphics;
CONST
	m = 50;
	size = 4;
	
TYPE 
	TCW*= OBJECT(WMWindowManager.BufferWindow)
		VAR
			mesh1, mesh2, n1, n2: ARRAY m, m OF REAL;
			gen: INTEGER;
			random:AosRandom.Generator;
			
			alive, alpha:BOOLEAN;
			i:LONGINT;
			
			PROCEDURE &New(alpha:BOOLEAN);
			VAR i, j:LONGINT;
			BEGIN
				Init(m*size, m*size, alpha);
				SELF.alpha:=alpha;
				manager := WMWindowManager.GetDefaultManager();
				manager.Add(100, 100, SELF, {WMWindowManager.FlagFrame});
				
				NEW(random);
				
				FOR i := 0 TO m - 1 DO
					FOR j := 0 TO m - 1 DO
						mesh1[i, j] := 0;
						mesh2[i, j] := 0;
						n1[i, j] := 0;
						n2[i, j] := 0
					END
				END;
				FOR i :=  1 TO m - 2 DO
					FOR j := 1 TO m - 2 DO
						IF random.Dice(100) > 90 THEN mesh1[i, j] := random.Dice(1000)/1000 END
					END
				END
			END New;
			
			PROCEDURE Draw*(canvas : Graphics.Canvas; w, h, q : LONGINT);
			BEGIN
				Draw^(canvas, w, h, 0)
			END Draw;
			
			PROCEDURE Close();
			BEGIN
				Close^;
				alive:=FALSE
			END Close;
			
			PROCEDURE Generation;
			VAR
				i, j: LONGINT;
				nx1, nx2: REAL;
			BEGIN
				FOR i := 1 TO m - 2 DO
					n1[i, 0] := mesh1[i - 1, 0] + mesh1[i + 1, 0] + mesh1[i, m - 1] + mesh1[i, 1]
					 + mesh1[i - 1, m - 1] +  mesh1[i + 1, 1] + mesh1[i + 1, m - 1] + mesh1[i - 1,  1];
			
					n1[i, m - 1] := mesh1[i - 1, m - 1] + mesh1[i + 1, m - 1] + mesh1[i, m - 2] + mesh1[i, 0]
					 + mesh1[i - 1, m - 2] +  mesh1[i + 1, 0] + mesh1[i + 1, m - 2] + mesh1[i - 1, 0];
			
					n2[i, 0] := mesh2[i - 1, 0] + mesh2[i + 1, 0] + mesh2[i, m - 1] + mesh2[i,  1]
					 + mesh2[i - 1, m - 1] + mesh2[i + 1, 1] + mesh2[i + 1, m - 1] + mesh2[i - 1, 1];
			
					n2[i, m - 1] := mesh2[i - 1, m - 1] + mesh2[i + 1, m - 1] + mesh2[i, m - 2] + mesh2[i, 0]
					 + mesh2[i - 1, m - 2] + mesh2[i + 1, 0] + mesh2[i + 1, m - 2] + mesh2[i - 1, 0];
			
				END;
				FOR j := 1 TO m - 2 DO
					n1[0, j] := mesh1[m - 1, j] + mesh1[1, j] + mesh1[0, j - 1] + mesh1[0, j + 1]
					 + mesh1[m - 1, j - 1] +  mesh1[1, j + 1] + mesh1[1, j - 1] + mesh1[m - 1, j + 1];
			
					n2[0, j] := mesh2[m - 1, j] + mesh2[1, j] + mesh2[ 0, j - 1] + mesh2[0, j + 1]
					 + mesh2[m - 1, j - 1] + mesh2[ 1, j + 1] + mesh2[ 1, j - 1] + mesh2[m - 1, j + 1];
			
					n1[m - 1, j] := mesh1[m - 2, j] + mesh1[0, j] + mesh1[m - 1, j - 1] + mesh1[m - 1, j + 1]
					 + mesh1[m - 2, j - 1] +  mesh1[0, j + 1] + mesh1[0, j - 1] + mesh1[m - 2, j + 1];
			
					n2[m - 1, j] := mesh2[m - 2, j] + mesh2[0, j] + mesh2[m - 1, j - 1] + mesh2[m - 1, j + 1]
					 + mesh2[m - 2, j - 1] + mesh2[0, j + 1] + mesh2[0, j - 1] + mesh2[m - 2, j + 1];
			
			
				END;
			
				FOR i := 1 TO m - 2 DO
					FOR j := 1 TO m - 2 DO
						n1[i, j] := mesh1[i - 1, j] + mesh1[i + 1, j] + mesh1[i, j - 1] + mesh1[i, j + 1]
						 + mesh1[i - 1, j - 1] +  mesh1[i + 1, j + 1] + mesh1[i + 1, j - 1] + mesh1[i - 1, j + 1];
						n2[i, j] := mesh2[i - 1, j] + mesh2[i + 1, j] + mesh2[i, j - 1] + mesh2[i, j + 1]
						 + mesh2[i - 1, j - 1] + mesh2[i + 1, j + 1] + mesh2[i + 1, j - 1] + mesh2[i - 1, j + 1];
					END
				END;
				FOR i := 1 TO m - 2 DO
					FOR j := 1 TO m - 2 DO
						(*  HERE ARE THE DIFFERENCE RULES! *)
						mesh1[i, j] := mesh1[i, j] + n1[i, j] / 80- (mesh2[i, j] * mesh2[i, j])  ;
						mesh2[i, j] := mesh2[i, j] +  mesh1[i, j] / 20 - 0.03 ;
						IF mesh1[i, j] < 0 THEN mesh1[i, j] := 0 END;
						IF mesh2[i, j] < 0 THEN mesh2[i, j] := 0 END;
						IF mesh1[i, j] > 1 THEN mesh1[i, j] := 1 END;
						IF mesh2[i, j] > 1 THEN mesh2[i, j] := 1 END;
					END;
				END;
			END Generation;
			
			PROCEDURE DrawIt;
			VAR i, j, ix, jy : LONGINT;
				pix : Raster.Pixel;
				mode : Raster.Mode;
			BEGIN
				Raster.InitMode(mode, Raster.srcCopy);
				FOR i := 0 TO m - 1 DO
					ix := i * size ;
					FOR j := 0 TO m - 1 DO
						jy := j * size;
						IF alpha THEN 
							Raster.SetRGBA(pix, SHORT((255-ENTIER(mesh1[i, j] * 255)) ), SHORT((255-ENTIER(mesh2[i, j] * 255)) ), 0, 
							SHORT( (255-ENTIER(mesh2[i, j] * 255))+ENTIER(mesh1[i, j] * 255)) MOD 128+127 )
						ELSE 
							Raster.SetRGB(pix, SHORT((255-ENTIER(mesh1[i, j] * 255)) ), SHORT((255-ENTIER(mesh2[i, j] * 255)) ), 0)
						END;
						Raster.Fill(img, ix, jy, ix+size, jy+size, pix, mode) 
					END
				END;
				Invalidate(Rectangles.MakeRect(0, 0, GetWidth(), GetHeight()))
			END DrawIt;
		
		BEGIN {ACTIVE}
			alive:=TRUE;
			AosActive.SetPriority(AosActive.Low);
			WHILE alive DO
				FOR i:=0 TO 0 DO Generation END;
				DrawIt;
			END
		END TCW;
		
PROCEDURE OpenAlpha*(par : PTR) : PTR;
VAR t:TCW;
BEGIN
	NEW(t, TRUE);
	RETURN NIL
END OpenAlpha;

PROCEDURE Open*(par : PTR) : PTR;
VAR t:TCW;
BEGIN
	NEW(t, FALSE);
	RETURN NIL
END Open;
		
END TuringCoatWnd.

System.Free TuringCoatWnd ~
Aos.Call TuringCoatWnd.OpenAlpha
Aos.Call TuringCoatWnd.Open
