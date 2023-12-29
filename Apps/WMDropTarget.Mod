MODULE WMDropTarget;

IMPORT
	AosIO, AosTexts;

CONST
	TypeText* = 0;
	TypeFiles* = 1;
	TypeURL* = 2;
	TypeImage* = 3;
	TypeUser* = 4;
	
	ResOk = 0;
	ResFailed = -1;

TYPE
	(** a drop interface that can be obtained from a drop target, according to a defined type *)
	DropInterface* = OBJECT
	END DropInterface;
	 
	DropTarget* = OBJECT
		(** return NIL if the type can not be dropped, a suitable DropInterface otherwise *)
		PROCEDURE GetInterface*(type : LONGINT) : DropInterface;
		BEGIN
			RETURN NIL
		END GetInterface;
	END DropTarget;
	
	DropText* = OBJECT(DropInterface)
	VAR text* : AosTexts.Text;
		pos* : AosTexts.TextPosition;	
	END DropText;
	
	DropURLs* = OBJECT(DropInterface)
		PROCEDURE URL*(url : ARRAY OF CHAR; VAR res : LONGINT);
		BEGIN
			
		END URL;
		
	END DropURLs;

	DropFiles* = OBJECT(DropInterface)
		PROCEDURE IsHierarchical*() : BOOLEAN;
		BEGIN RETURN FALSE
		END IsHierarchical;
		
		PROCEDURE OpenPut*(remoteName : ARRAY OF CHAR; VAR outw : AosIO.Writer; VAR res : LONGINT);
		BEGIN
		END OpenPut;
		
		PROCEDURE ClosePut*(VAR res : LONGINT);
		BEGIN
		END ClosePut;
		
		(** only path relative to the current dir are accepted. The string '..' stands for the parent directory *)
		PROCEDURE ChangeDir*(dir : ARRAY OF CHAR; VAR res : LONGINT);
		BEGIN
		END ChangeDir;
		
		(** only path relative to the current dir are accepted. The string '..' stands for the parent directory *)		
		PROCEDURE MakeDir*(dir : ARRAY OF CHAR; VAR res : LONGINT);
		BEGIN
		END MakeDir;
		
	END DropFiles;
	

END WMDropTarget.
