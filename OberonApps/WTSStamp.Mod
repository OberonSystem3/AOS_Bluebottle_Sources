(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE WTSStamp;	(** portable *)

IMPORT
	TimeStamps;
	
PROCEDURE New*;
BEGIN TimeStamps.New
END New;

END WTSStamp.