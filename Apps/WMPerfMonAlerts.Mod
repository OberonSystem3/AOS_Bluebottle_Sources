MODULE WMPerfMonAlerts; (** AUTHOR "staubesv"; PURPOSE "Performance Monitor Alert plugin"; *)

IMPORT
	AosOut, AosModules, AosCommands, AosIO, AosFS, AosEvents, Utilities,
	XML, XMLObjects, XMLScanner, XMLParser,
	WMPerfMonPlugins;

CONST

	Ok* = 0;
	Error* = 1;
	
	DefaultAlertFile = "WMPerfMonAlerts.XML";
	
	(** Types *)
	Sticky* = 0;			(* Execute the onAlertCommand one time *)
	SingleShot* = 1;		(* Execute the onAlertCommand one time. When the alert is over, execute the onLeaveAlertCommand on time *)
	MultiShot* = 2;		(* Execute the command each time the alert is triggered *)

	(** Triggers *)
	Invalid* = -1;
	Undefined* = 0;
	Greater* = 1;
	GreaterOrEqual* = 2;
	Equals* = 3;
	NotEquals* = 4;
	Less* = 5;
	LessOrEqual* = 6;
	OutOfInterval* = 7;
	InInterval* = 8;
	
	(* Alert states *)
	Off* = 0;		(** Alert is ignored/not detected *)
	On* = 1;		(**	Alert is on *)
	Triggered* = 2;	(** Alert has been triggered *)
	Reset* = 3; 		(** Reset alert stats. Set alert state to AlertOn *)
	
	XmlElementAlert = "Alert";
	XmlAttributeFullname = "fullname";

	XmlAttributeType = "type";
	
	XmlAttributeValue1 = "value1";
	XmlAttributeValue2 = "value2";

	XmlAttributeOnAlertCommand = "onAlert";
	XmlAttributeOnLeaveAlertCommand = "onLeave";

	XmlAttributeTrigger = "trigger";
	XmlGreater = ">";
	XmlGreaterOrEqual = ">=";
	XmlEquals = "=";
	XmlNotEquals = "!=";
	XmlLess = "<";
	XmlLessOrEqual = "<=";
	XmlOutOfInterval = "out";
	XmlInInterval = "in";
	
	ShowOnKernelLog = FALSE;
	GenerateEvents = TRUE;
	EventOriginator = "WMPerfMonAlerts";
	
TYPE

	AlertInfo* = RECORD
		id- : LONGINT;
		fullname- : ARRAY 256 OF CHAR;
		type- : LONGINT;

		state- : LONGINT;
		
		(* alert trigger *)
		trigger- : LONGINT;
		value1-, value2- : LONGREAL;
		violation- : REAL; (* value that triggered trigger *)
		nbrOfViolations- : LONGINT;
		
		(* command activated when trigger is triggered *)
		onAlertCommand- : XML.String;
		
		(* command activated when state changes from alert = TRUE to alert = FALSE *)
		onLeaveAlertCommand- : XML.String;
	END;

	Alert = OBJECT
	VAR
		info : AlertInfo;
		
		onAlertCalled, onLeaveCalled : BOOLEAN;

		(* for internal use *)
		plugin : WMPerfMonPlugins.Plugin;
		lastState : LONGINT;
		datasetIdx : LONGINT;
		next : Alert;
		
		PROCEDURE SetState(state : LONGINT);
		VAR oldState : LONGINT;
		BEGIN
			ASSERT((state = Off) OR (state = On) OR (state = Triggered) OR (state = Reset));
			oldState := info.state;
			info.state := state;
			IF state = Reset THEN
				ResetState;
			END;
		END SetState;
		
		PROCEDURE ResetState;
		BEGIN
			info.state := On;
			info.violation := 0;
			info.nbrOfViolations := 0;
			onAlertCalled := FALSE;
			onLeaveCalled := FALSE;
		END ResetState;
		
		PROCEDURE Alert(value : REAL);
		BEGIN
			info.state := Triggered;
			info.violation := value;
			INC(info.nbrOfViolations);
		END Alert;
		
		PROCEDURE AlarmTriggered() : BOOLEAN;
		VAR value : REAL; triggered : BOOLEAN;
		BEGIN
			IF info.state = Off THEN RETURN FALSE; END;
			lastState := info.state;
			value := plugin.dataset[datasetIdx];
			triggered := FALSE;
			CASE info.trigger OF 
				|Undefined:
				|Greater: IF (value > info.value1) THEN triggered := TRUE; END;
				|GreaterOrEqual: IF (value >= info.value1) THEN triggered := TRUE; END;
				|Equals: IF (value = info.value1) THEN triggered := TRUE; END;
				|NotEquals: IF (value # info.value1) THEN triggered := TRUE; END;
				|Less: IF (value < info.value1) THEN triggered := TRUE; END;
				|LessOrEqual: IF (value <= info.value1) THEN triggered := TRUE; END;
				|OutOfInterval: IF (value < info.value1) OR (value > info.value2) THEN triggered := TRUE; END;
				|InInterval: IF (value >= info.value1) & (value <= info.value2) THEN triggered := TRUE; END;
			ELSE
			END;
			IF triggered THEN 
				Alert(value); 
			ELSIF (info.type # Sticky) THEN
				info.state := On;
			END;
			HandleAlert(lastState, triggered);
			RETURN triggered;
		END AlarmTriggered;
		
		PROCEDURE HandleAlert(lastState : LONGINT; triggered : BOOLEAN);
		VAR string : AosEvents.Message;
		BEGIN
			IF triggered THEN
				IF (info.type = Sticky) OR (info.type = SingleShot) THEN
					IF ~onAlertCalled THEN
						IF GenerateEvents THEN
							GetFullTriggerString(info, string);
							AosEvents.Add(GetEvent(string, 1), FALSE);
						END;
						ExecuteCommand(info.onAlertCommand);
						onAlertCalled := TRUE;
					END;
				ELSIF (info.type = MultiShot) THEN
					IF GenerateEvents THEN
						GetFullTriggerString(info, string);
						AosEvents.Add(GetEvent(string, 1), FALSE);
					END;
					ExecuteCommand(info.onAlertCommand);
				END;
			ELSE
				IF lastState =  Triggered THEN
					IF (info.type = Sticky) OR (info.type = MultiShot) THEN (* do nothing *)
					ELSIF (info.type = SingleShot) THEN
						ExecuteCommand(info.onLeaveAlertCommand);
					END;
				END;
			END;
		END HandleAlert;
		
		PROCEDURE Finalize;
		BEGIN
			plugin.DecNbrOfClients;
		END Finalize;
		
		PROCEDURE ToXML() : XML.Element;
		VAR elem : XML.Element;
		BEGIN
			NEW(elem); elem.SetName(	XmlElementAlert);
			elem.SetAttributeValue(XmlAttributeFullname, info.fullname);
			elem.SetAttributeValue(XmlAttributeType, GetTypeStringRet(info.type));
			elem.SetAttributeValue(XmlAttributeTrigger, GetTriggerString(info.trigger));
			elem.SetAttributeValue(XmlAttributeValue1, GetLongrealString(info.value1));
			elem.SetAttributeValue(XmlAttributeValue2, GetLongrealString(info.value2));
			IF info.onAlertCommand # NIL THEN
				elem.SetAttributeValue(XmlAttributeOnAlertCommand, info.onAlertCommand^);
			ELSE
				elem.SetAttributeValue(XmlAttributeOnAlertCommand, "");
			END;
			IF info.onLeaveAlertCommand # NIL THEN
				elem.SetAttributeValue(XmlAttributeOnLeaveAlertCommand, info.onAlertCommand^);
			ELSE
				elem.SetAttributeValue(XmlAttributeOnLeaveAlertCommand, "");
			END;
			RETURN elem;
		END ToXML;
				
		PROCEDURE Show(details : BOOLEAN);
		BEGIN
			AosOut.String("UID: "); AosOut.Int(info.id, 0); AosOut.String(": ");
			AosOut.String(info.fullname); 

			AosOut.String(", type: ");
			CASE info.type OF 
				|Sticky: AosOut.String("Sticky");
				|SingleShot: AosOut.String("Singleshot");
				|MultiShot: AosOut.String("Multishot");
			ELSE
				AosOut.String("Unknown");
			END;
			
			AosOut.String(", trigger: ");
			CASE info.trigger OF
				|Undefined: AosOut.String("none");
				|Greater: AosOut.String("value > "); AosOut.String(GetLongrealString(info.value1));
				|GreaterOrEqual: AosOut.String("value >= "); AosOut.String(GetLongrealString(info.value1));
				|Equals: AosOut.String("value = "); AosOut.String(GetLongrealString(info.value1));
				|NotEquals: AosOut.String("value != "); AosOut.String(GetLongrealString(info.value1));
				|Less: AosOut.String("value < "); AosOut.String(GetLongrealString(info.value1));
				|LessOrEqual: AosOut.String("value <= "); AosOut.String(GetLongrealString(info.value1));
				|OutOfInterval: 
					AosOut.String("value not in ["); AosOut.String(GetLongrealString(info.value1)); AosOut.String(", "); 
					AosOut.String(GetLongrealString(info.value2)); AosOut.String("]");
				|InInterval: 
					AosOut.String("value in ["); AosOut.String(GetLongrealString(info.value1)); 
					AosOut.String(", "); AosOut.String(GetLongrealString(info.value2)); AosOut.String("]");
			ELSE
				AosOut.String("unknown");
			END;
			AosOut.String(", violation: "); AosOut.Int(ENTIER(info.violation), 0); 
			AosOut.String(", nbrOfViolations: "); AosOut.Int(info.nbrOfViolations, 0); 
			IF details THEN
				AosOut.Ln;
				AosOut.String("   onAlert: "); 
				IF info.onAlertCommand = NIL THEN AosOut.String("none"); ELSE AosOut.String(info.onAlertCommand^); END;
				AosOut.Ln;
				AosOut.String("   onLeaveAlert: ");
				IF info.onLeaveAlertCommand = NIL THEN AosOut.String("none"); ELSE AosOut.String(info.onLeaveAlertCommand^); END;
			END;
			AosOut.Ln;
		END Show;
				
		PROCEDURE &Init(fullname : ARRAY OF CHAR; plugin : WMPerfMonPlugins.Plugin; datasetIdx : LONGINT);
		BEGIN
			ASSERT(plugin # NIL);
			ASSERT((0 <= datasetIdx) & (datasetIdx < LEN(plugin.p.datasetDescriptor)));
			COPY(fullname, SELF.info.fullname);
			SELF.plugin := plugin;
			SELF.datasetIdx := datasetIdx;
			plugin.IncNbrOfClients;
			info.state := On;
		END Init;
		
	END Alert;
		
	Alerts* = POINTER TO ARRAY OF AlertInfo;
	
	Status* = RECORD
		enabled- : BOOLEAN;
		filename- : ARRAY 256 OF CHAR;
		nbrOfRules- : LONGINT;
		nbrOfAlerts- : LONGINT;
		stamp- : LONGINT; (** incremented each time a alert rule is added or removed *)
	END;
	
VAR 
	alerts : Alert;
	alertsEnabled : BOOLEAN;
	alertFile : ARRAY 256 OF CHAR;
	nbrOfRules, nbrOfAlerts : LONGINT;
	stamp : LONGINT;
	uniqueID : LONGINT;
		
PROCEDURE Add*(fullname : ARRAY OF CHAR; type, trigger : LONGINT; value1, value2 : LONGREAL; onAlert, onLeave : XML.String; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
VAR a, alert : Alert; plugin : WMPerfMonPlugins.Plugin; index : LONGINT;
BEGIN {EXCLUSIVE}
	plugin := WMPerfMonPlugins.updater.GetByFullname(fullname, index, msg);
	IF plugin # NIL THEN
		NEW(alert, fullname, plugin, index);
		alert.info.id := uniqueID; INC(uniqueID);
		alert.info.type := type;
		alert.info.trigger := trigger;
		alert.info.value1 := value1;
		alert.info.value2 := value2;
		INC(nbrOfRules);
		IF alerts = NIL THEN
			alerts := alert;
		ELSE
			a := alerts; WHILE (a.next # NIL) DO a := a.next; END;
			a.next := alert;
		END;
		INC(stamp);
	ELSE
		res := Error;
	END;
END Add;

PROCEDURE AddByString*(string : ARRAY OF CHAR; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
VAR alert : AlertInfo;
BEGIN
	ParseAlert(string, alert, msg, res);	
	IF res = Ok THEN
		Add(alert.fullname, alert.type, alert.trigger, alert.value1, alert.value2, alert.onAlertCommand, alert.onLeaveAlertCommand, msg, res);
	END;
END AddByString;

PROCEDURE AddByCommand*(par : ANY) : ANY;
VAR p : AosCommands.Parameters; msg : ARRAY 128 OF CHAR; res : LONGINT;
BEGIN
	IF (par # NIL) & (par IS AosCommands.Parameters) THEN
		p := par (AosCommands.Parameters);
		AddByString(p.str^, msg, res);
		IF res = Ok THEN
			AosOut.String("Alert added."); AosOut.Ln;
		ELSE
			AosOut.String("Error: "); AosOut.String(msg); AosOut.Ln;
		END;
	ELSE
		AosOut.String("Error: Expected parameters"); AosOut.Ln;
	END;
	RETURN NIL
END AddByCommand;

PROCEDURE RemoveAlerts*(fullname : ARRAY OF CHAR) : LONGINT;
VAR a : Alert; nofRemoved : LONGINT;
BEGIN {EXCLUSIVE}
	a := alerts;
	WHILE (a.next # NIL) DO	
		IF (a.next.info.fullname = fullname) THEN
			a.next.Finalize;
			a.next := a.next.next;
			INC(nofRemoved);
			INC(stamp);
			DEC(nbrOfRules);
		ELSE		
			a := a.next;
		END;
	END;
	RETURN nofRemoved;
END RemoveAlerts;

PROCEDURE RemoveAlertByID*(id : LONGINT) : LONGINT;
VAR a : Alert; nofRemoved : LONGINT;
BEGIN {EXCLUSIVE}
	IF alerts # NIL THEN
		IF alerts.info.id = id THEN
			alerts := alerts.next;
			nofRemoved := 1;
			DEC(nbrOfRules);
			INC(stamp);
		ELSE		
			a := alerts;
			WHILE (a.next # NIL) & (a.next.info.id # id) DO a := a.next; END;
			IF (a.next # NIL) THEN
				a.next.Finalize;
				a.next := a.next.next;
				DEC(nbrOfRules);
				INC(stamp);
				nofRemoved := 1;
			END;
		END;
	END;
	RETURN nofRemoved;
END RemoveAlertByID;

PROCEDURE SetStateByID*(id, state : LONGINT; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
VAR alert : Alert;
BEGIN {EXCLUSIVE}
	ASSERT((state = Off) OR (state = On) OR (state = Triggered) OR (state = Reset));
	alert := GetByIdX(id);
	IF alert # NIL THEN
		alert.SetState(state);
		INC(stamp);
		res := Ok;
	ELSE
		msg := "Alert not found"; res := Error;
	END;
END SetStateByID;

PROCEDURE GetByIdX(id : LONGINT) : Alert;
VAR a : Alert;
BEGIN
	a := alerts;	
	WHILE (a # NIL) & (a.info.id # id) DO a := a.next; END;
	RETURN a;
END GetByIdX;

PROCEDURE HandleEvents(events : SET; perf : REAL);
BEGIN
	IF WMPerfMonPlugins.EventSampleLoopDone IN events THEN
		CheckAlerts;
	END;
END HandleEvents;

PROCEDURE CheckAlerts;
VAR a : Alert; failed : LONGINT;
BEGIN {EXCLUSIVE}
	IF alertsEnabled THEN
		a := alerts;
		WHILE (a # NIL) DO
			IF a.AlarmTriggered() THEN 
				INC(stamp);
				INC(failed);
				IF ShowOnKernelLog THEN a.Show(FALSE); END;
			END;
			a := a.next;
		END;
	END;
	nbrOfAlerts := failed;
END CheckAlerts;

PROCEDURE ExecuteCommand(command : XML.String);
VAR msg : ARRAY 128 OF CHAR; res : LONGINT;
BEGIN
	IF command # NIL THEN
		AosCommands.Call(command^, {}, res, msg);
		IF res # AosCommands.Ok THEN
			AosOut.String("WMPerfMonAlerts: Could not execute command '");
			AosOut.String(command^); AosOut.String("', res: "); AosOut.Int(res, 0);
			AosOut.String(" ("); AosOut.String(msg); AosOut.String(")");
			AosOut.Ln;
		END;
	END;
END ExecuteCommand;

PROCEDURE GetAttributeValue(elem : XML.Element; name : ARRAY OF CHAR) : XML.String;
VAR attr : XML.Attribute; string : XML.String;
BEGIN
	IF elem # NIL THEN
		attr := elem.GetAttribute(name);
		IF attr # NIL THEN
			string := attr.GetValue();
		END;
	END;
	RETURN string;
END GetAttributeValue;

PROCEDURE GetLongreal(elem : XML.Element; name : ARRAY OF CHAR; VAR res : LONGINT) : LONGREAL;
VAR string : XML.String; nbr : LONGREAL;
BEGIN
	res := Error;
	string := GetAttributeValue(elem, name);
	IF (string # NIL) THEN
		Utilities.StrToFloat(string^, nbr);
		res := Ok;
	END;	
	RETURN nbr;
END GetLongreal;

TYPE Str16 = ARRAY 16 OF CHAR;
PROCEDURE GetLongrealString(value : LONGREAL) : Str16;
VAR string : Str16;
BEGIN
	Utilities.FloatToStr(value, 10, 10, 3, string);
	RETURN string;
END GetLongrealString;

PROCEDURE GetTriggerPtr(string : XML.String) : LONGINT;
VAR trigger : LONGINT;
BEGIN
	trigger := Invalid;
	IF string # NIL THEN
		trigger := GetTrigger(string^);
	END;
	RETURN trigger;
END GetTriggerPtr;

PROCEDURE GetTrigger(string : ARRAY OF CHAR) : LONGINT;
VAR trigger : LONGINT;
BEGIN
	IF string = XmlGreater THEN trigger := Greater;
	ELSIF string = XmlGreaterOrEqual THEN trigger := GreaterOrEqual;
	ELSIF string = XmlEquals THEN trigger := Equals;
	ELSIF string = XmlNotEquals THEN trigger := NotEquals;
	ELSIF string = XmlLess THEN trigger := Less;
	ELSIF string = XmlLessOrEqual THEN trigger := LessOrEqual;
	ELSIF string = XmlOutOfInterval THEN trigger := OutOfInterval;
	ELSIF string = XmlInInterval THEN trigger := InInterval;
	ELSE trigger := Invalid;
	END;
	RETURN trigger;
END GetTrigger;

PROCEDURE GetTriggerString(trigger : LONGINT) : Str16;
VAR string : Str16;
BEGIN
	CASE trigger OF
		|Greater: string := XmlGreater;
		|GreaterOrEqual: string := XmlGreaterOrEqual;
		|Equals: string := XmlEquals;
		|NotEquals: string := XmlNotEquals;
		|Less: string := XmlLess;
		|LessOrEqual: string := XmlLessOrEqual;
		|OutOfInterval: string := XmlOutOfInterval;
		|InInterval: string := XmlInInterval;
	ELSE
		string := "Invalid";
	END;
	RETURN string;
END GetTriggerString;

PROCEDURE GetTypePtr(string : XML.String) : LONGINT;
VAR type : LONGINT;
BEGIN
	type := Invalid;
	IF string # NIL THEN
		type := GetType(string^);
	END;
	RETURN type;	
END GetTypePtr;

PROCEDURE GetType(string : ARRAY OF CHAR) : LONGINT;
VAR type : LONGINT;
BEGIN
	Utilities.UpperCase(string);
	IF string = "STICKY" THEN type := Sticky;
	ELSIF string = "SINGLESHOT" THEN type := SingleShot;
	ELSIF string = "MULTISHOT" THEN type := MultiShot;
	ELSE type := Invalid;
	END;
	RETURN type;
END GetType;

PROCEDURE GetTypeStringRet*(type : LONGINT) : Str16;
VAR string : Str16;
BEGIN
	GetTypeString(type, string);
	RETURN string;
END GetTypeStringRet;

PROCEDURE GetStateString*(state : LONGINT; VAR string : ARRAY OF CHAR);
BEGIN
	CASE state OF
		|Off: string := "Off";
		|On: string := "On";
		|Triggered: string := "ALERT";
		|Reset: string := "Reset";
	ELSE
		string := "UNKNOWN";
	END;
END GetStateString;

PROCEDURE GetTypeString*(type : LONGINT; VAR string : ARRAY OF CHAR);
BEGIN
	CASE type OF
		|Sticky: string := "Sticky";
		|SingleShot: string := "Single";
		|MultiShot: string := "Multi";
	ELSE
		string := "Unknown";
	END;
END GetTypeString;

PROCEDURE GetFullTriggerString*(ai : AlertInfo; VAR string : ARRAY OF CHAR);
VAR value1, value2 : ARRAY 16 OF CHAR;
BEGIN
	Utilities.FloatToStr(ai.value1, 8, 2, 0, value1);
	Utilities.FloatToStr(ai.value2, 8, 2, 0, value2);
	string := "";
	CASE ai.trigger OF
		|Undefined: string := "Undefined";
		|Greater: Utilities.Append(string, ai.fullname); Utilities.Append(string, " > "); Utilities.Append(string, value1);
		|GreaterOrEqual: Utilities.Append(string, ai.fullname); Utilities.Append(string, " >= "); Utilities.Append(string, value1);
		|Equals: Utilities.Append(string, ai.fullname); Utilities.Append(string, " = "); Utilities.Append(string, value1);
		|NotEquals: Utilities.Append(string, ai.fullname); Utilities.Append(string, " # "); Utilities.Append(string, value1);
		|Less: Utilities.Append(string, ai.fullname); Utilities.Append(string, " < "); Utilities.Append(string, value1);
		|LessOrEqual: Utilities.Append(string, ai.fullname); Utilities.Append(string, " <= "); Utilities.Append(string, value1);
		|OutOfInterval:  
			Utilities.Append(string, ai.fullname);  Utilities.Append(string, " not in [");  
			Utilities.Append(string, value1); Utilities.Append(string, ", "); Utilities.Append(string, value2); Utilities.Append(string, "]");
		|InInterval: 
			Utilities.Append(string, ai.fullname);  Utilities.Append(string, " in [");  
			Utilities.Append(string, value1); Utilities.Append(string, ", "); Utilities.Append(string, value2); Utilities.Append(string, "]");
	ELSE
		string := "Invalid";
	END;
END GetFullTriggerString;

PROCEDURE GetEvent(message : AosEvents.Message; code : SHORTINT) : AosEvents.Event;
VAR event : AosEvents.Event;
BEGIN
	event.originator := EventOriginator;
	event.type := AosEvents.Alert;
	event.class := 2; (* Performance Monitor *);
	event.subclass := 1; (* Alerts *)
	event.code := code;
	event.message := message;
	RETURN event;	
END GetEvent;

(* Parses string: fullname type trigger value1 value2  "onAlertCommand" "onLeaveCommand" *)
PROCEDURE ParseAlert*(alertstring : ARRAY OF CHAR; VAR alert : AlertInfo; VAR msg : ARRAY OF CHAR; res : LONGINT);
VAR r : AosIO.StringReader; string : ARRAY 256 OF CHAR;
BEGIN
	NEW(r, LEN(alertstring)); r.Set(alertstring);
	
	(* parse fullname *)
	r.SkipWhitespace; r.String(string);
	IF (r.res # AosIO.Ok) OR (string = "") THEN
		msg := "Could not parse full name"; res := Error;
		RETURN;
	END;
	COPY(string, alert.fullname);
	
	(* parse type *)
	r.SkipWhitespace; r.String(string);
	IF (r.res # AosIO.Ok) OR (string = "") THEN
		msg := "Could not parse type parameter"; res := Error;
		RETURN;
	END;
	alert.type := GetType(string);
	IF alert.type = Invalid THEN
		msg := "Invalid type parameter"; res := Error;
		RETURN;
	END;
	
	(* parse trigger *)
	r.SkipWhitespace; r.String(string);
	IF (r.res # AosIO.Ok) OR (string = "") THEN
		msg := "Could not parse trigger parameter"; res := Error;
		RETURN;
	END;
	alert.trigger := GetTrigger(string);
	IF alert.trigger = Invalid THEN
		msg := "Invalid trigger parameter"; res := Error;
		RETURN;
	END;
	
	(* parse value 1 *)
	r.SkipWhitespace; r.String(string);
	IF (r.res # AosIO.Ok) THEN
		msg := "Could not parse value 1 parameter"; res := Error;
		RETURN;
	END;
	Utilities.StrToFloat(string, alert.value1);
	
	(* parse value 2 *)
	r.SkipWhitespace; r.String(string);
	IF (r.res # AosIO.Ok) THEN
		msg := "Could not parse value 2 parameter"; res := Error;
		RETURN;
	END;
	Utilities.StrToFloat(string, alert.value2);
	
	(* parse onAlertCommand *)
	r.SkipWhitespace; r.String(string);
	IF (r.res # AosIO.Ok) THEN
		msg := "Could not parse onAlertCommand parameter"; res := Error;
		RETURN;
	END;
	IF string	# "none" THEN
		alert.onAlertCommand := Utilities.NewString(string);
	END;
	
	(* parse onLeaveCommand *)
	r.SkipWhitespace; r.String(string);
	IF (r.res # AosIO.Ok) THEN
		msg := "Could not parse onLeaveAlertCommand parameter"; res := Error;
		RETURN;
	END;
	IF string # "none" THEN
		alert.onLeaveAlertCommand := Utilities.NewString(string);
	END;
	res := Ok;
END ParseAlert;

PROCEDURE ParseXmlAlert(elem : XML.Element; VAR msg : ARRAY OF CHAR) : Alert;
VAR 
	alert : Alert; string : XML.String; 
	fullname : ARRAY 256 OF CHAR; type, trigger : LONGINT;  value1, value2 : LONGREAL;
	plugin : WMPerfMonPlugins.Plugin;
	index, res : LONGINT;
BEGIN
	ASSERT(elem # NIL);
	string := GetAttributeValue(elem, XmlAttributeFullname);
	IF string # NIL THEN
		COPY(string^, fullname);
		trigger := GetTriggerPtr(GetAttributeValue(elem, XmlAttributeTrigger));
		IF trigger # Invalid THEN
			type := GetTypePtr(GetAttributeValue(elem, XmlAttributeType));
			IF type # Invalid THEN
				value1 := GetLongreal(elem, XmlAttributeValue1, res);
				IF (res = Ok) & (trigger = OutOfInterval) THEN
					value2 := GetLongreal(elem, XmlAttributeValue2, res);
				END;
				IF (res = Ok) THEN
					plugin := WMPerfMonPlugins.updater.GetByFullname(fullname, index, msg);
					IF plugin # NIL THEN
						NEW(alert, fullname, plugin, index);
						alert.info.id := uniqueID; INC(uniqueID);
						alert.info.type := type;
						alert.info.trigger := trigger;
						alert.info.value1 := value1;
						alert.info.value2 := value2;
						alert.info.onAlertCommand := GetAttributeValue(elem, XmlAttributeOnAlertCommand);
						alert.info.onLeaveAlertCommand := GetAttributeValue(elem, XmlAttributeOnLeaveAlertCommand);
					ELSE
						msg := "Plugin "; Utilities.Append(msg, fullname); Utilities.Append(msg, " not found");
					END;
				ELSE msg := "Could not parse value1/value2 attributes of "; Utilities.Append(msg, fullname);
				END;
			ELSE msg := "Attribute "; Utilities.Append(msg, XmlAttributeType); Utilities.Append(msg, " not found or invalid in "); Utilities.Append(msg, fullname);
			END;
		ELSE msg := "Attribute "; Utilities.Append(msg, XmlAttributeTrigger); Utilities.Append(msg, " not found or invalid in "); Utilities.Append(msg, fullname);
		END;
	ELSE msg := "Attribute "; Utilities.Append(msg, XmlAttributeFullname); Utilities.Append(msg, " not found ");
	END;
	RETURN alert;
END ParseXmlAlert;

PROCEDURE ParseXmlDocument(document : XML.Document; VAR msg : ARRAY OF CHAR; VAR nbrOfRules, res : LONGINT) : Alert;
VAR elem : XML.Element; enum : XMLObjects.Enumerator; listHead, alert : Alert; ptr : PTR; string : XML.String;
BEGIN
	ASSERT(document # NIL);
	elem := document.GetRoot();		
	IF elem # NIL THEN
		enum := elem.GetContents();
		WHILE enum.HasMoreElements() DO
			ptr := enum.GetNext();
			IF ptr IS XML.Element THEN
				elem := ptr (XML.Element);
				string := elem.GetName();
				IF (string # NIL) & (string^ = XmlElementAlert) THEN
					alert := ParseXmlAlert(elem, msg);
					IF alert # NIL THEN
						INC(nbrOfRules);
						IF listHead = NIL THEN listHead := alert;
						ELSE
							alert.next := listHead;
							listHead := alert;
						END;
					ELSE
						listHead := NIL;
						res := Error;
					END;
				END;
			END;
		END;
	ELSE
		msg := "No root element in document"; res := Error;
	END;
	RETURN listHead;
END ParseXmlDocument;

PROCEDURE LoadXmlDocument(filename : ARRAY OF CHAR; VAR msg : ARRAY OF CHAR; VAR res : LONGINT) : XML.Document;
VAR 
	scanner : XMLScanner.Scanner; parser : XMLParser.Parser; document : XML.Document;
	in : AosFS.Reader; f : AosFS.File; 
BEGIN
	f := AosFS.Old(filename);
	IF f # NIL THEN 
		AosFS.OpenReader(in, f, 0);
		IF in # NIL THEN
			NEW(scanner, in); NEW(parser, scanner); 
			document := parser.Parse();
			IF document # NIL THEN
				res := Ok;
				RETURN document;
			ELSE msg := "XML parsing failed"; res := Error;
			END;
		ELSE msg := "Could not open reader on file"; res := Error;
		END;
	ELSE msg := "File not found"; res := Error;	
	END; 
END LoadXmlDocument;

PROCEDURE GetStatus*() : Status;
VAR status : Status;
BEGIN {EXCLUSIVE}
	status.enabled := alertsEnabled;
	COPY(alertFile, status.filename);
	status.nbrOfRules := nbrOfRules;
	status.nbrOfAlerts := nbrOfAlerts;
	status.stamp := stamp;
	RETURN status;
END GetStatus;

PROCEDURE GetAlerts*() : Alerts;
VAR result : Alerts; a : Alert; i : LONGINT;
BEGIN {EXCLUSIVE}
	IF nbrOfRules > 0 THEN
		NEW(result, nbrOfRules);
		a := alerts;
		i := 0;
		WHILE (a # NIL) DO
			result[i] := a.info;
			INC(i);
			a := a.next;
		END;
	END;
	RETURN result;
END GetAlerts;

PROCEDURE SetRulesX(filename : ARRAY OF CHAR; alertList : Alert; nbrOfRulesP : LONGINT; append : BOOLEAN);
VAR a : Alert;
BEGIN
	IF ~append THEN 
		UnloadX; 
		nbrOfRules := nbrOfRulesP;
	ELSE
		nbrOfRules := nbrOfRules + nbrOfRulesP;
	END;
	COPY(filename, alertFile);
	INC(stamp);
	IF alerts = NIL THEN
		alerts := alertList;
	ELSE
		a := alerts;
		WHILE (a.next # NIL) DO a := a.next; END;
		a.next := alertList;
	END;
END SetRulesX;

PROCEDURE GetRulesAsXmlX() : XML.Element;
VAR a : Alert; elem : XML.Element;
BEGIN
	IF alerts # NIL THEN
		NEW(elem); elem.SetName("Alerts");
		a := alerts;
		WHILE(a # NIL) DO
			elem.AddContent(a.ToXML());
			a := a.next;
		END;
	END;	
	RETURN elem;
END GetRulesAsXmlX;

PROCEDURE LoadRuleFileX(filename : ARRAY OF CHAR; VAR alerts : Alert; VAR nbrOfRules : LONGINT; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
VAR document : XML.Document;
BEGIN
	document := LoadXmlDocument(filename, msg, res);
	IF res = Ok THEN
		alerts := ParseXmlDocument(document, msg, nbrOfRules, res);
	END;
END LoadRuleFileX;

PROCEDURE StoreRuleFileX(filename : ARRAY OF CHAR; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
VAR file : AosFS.File; rules : XML.Element; w : AosFS.Writer;
BEGIN
	file := AosFS.New(filename);
	IF file # NIL THEN
		rules := GetRulesAsXmlX();
		IF rules # NIL THEN
			AosFS.OpenWriter(w, file, 0);
			w.String('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'); w.Ln;
			rules.Write(w, 0);
			w.Update;
			AosFS.Register(file);
		ELSE 
			msg := "No rules available"; res := Error;
		END;
	ELSE
		msg := "File "; Utilities.Append(msg, filename); Utilities.Append(msg, " not found"); res := Error;
	END;	
END StoreRuleFileX;

PROCEDURE LoadRules*(filename : ARRAY OF CHAR; append : BOOLEAN; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
VAR alerts : Alert; nbrOfRules : LONGINT;
BEGIN {EXCLUSIVE}
	LoadRuleFileX(filename, alerts, nbrOfRules, msg, res);
	IF res = Ok THEN
		SetRulesX(filename, alerts, nbrOfRules, append);
	END;
END LoadRules;

PROCEDURE StoreRules*(filename : ARRAY OF CHAR; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
BEGIN {EXCLUSIVE}
	StoreRuleFileX(filename, msg, res);
END StoreRules;

PROCEDURE Load*(par : ANY) : ANY; (** [filename] ~ *)
VAR r : AosIO.StringReader; filename, msg : ARRAY 256 OF CHAR; nbrOfRules, res : LONGINT; alerts : Alert;
BEGIN {EXCLUSIVE}
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(filename);
	IF (r.res # AosIO.Ok) OR (filename = "") THEN filename := DefaultAlertFile; END;
	LoadRuleFileX(filename, alerts, nbrOfRules, msg, res);
	IF res = Ok THEN 
		SetRulesX(filename, alerts, nbrOfRules, FALSE);
		AosOut.String("WMPerfMonAlerts: Loaded "); AosOut.Int(nbrOfRules, 0); AosOut.String(" rules from file "); AosOut.String(filename); AosOut.Ln;
	ELSE
		AosOut.String("WMPerfMonAlerts: Could not load alert file ("); AosOut.String(msg); AosOut.String(")"); AosOut.Ln; 
	END;
	RETURN NIL
END Load;

PROCEDURE Store*(par : ANY) : ANY; (** filename ~ *)
VAR r : AosIO.StringReader; filename, msg : ARRAY 256 OF CHAR; nbrOfRules, res : LONGINT;
BEGIN {EXCLUSIVE}
	AosCommands.PosPar(par, r);
	r.SkipWhitespace; r.String(filename);
	StoreRuleFileX(filename, msg, res);
	IF res = Ok THEN 
		AosOut.String("WMPerfMonAlerts: Stored "); AosOut.Int(nbrOfRules, 0); AosOut.String(" rules into file "); AosOut.String(filename); AosOut.Ln;
	ELSE
		AosOut.String("WMPerfMonAlerts: Could not store alerts to file ("); AosOut.String(msg); AosOut.String(")"); AosOut.Ln; 
	END;
	RETURN NIL
END Store;

PROCEDURE Show*(par : ANY) : ANY; (** ~ *)
VAR a : Alert; nbr : LONGINT;
BEGIN {EXCLUSIVE}
	AosOut.String("WMPerfMonAlerts status: Alerts are "); 
	IF alertsEnabled THEN AosOut.String("ENABLED"); ELSE AosOut.String("DISABLED"); END; AosOut.Ln;
	AosOut.String("Ruleset:"); AosOut.Ln;
	IF alerts = NIL THEN
		AosOut.String("No Rules loaded."); AosOut.Ln;
	ELSE
		nbr := 0;
		a := alerts;
		WHILE (a # NIL) DO
			INC(nbr);
			AosOut.Int(nbr, 2); AosOut.String(": "); a.Show(TRUE); 
			a := a.next;
		END;
	END;	
	RETURN NIL
END Show;

PROCEDURE EnableAlerts*;
BEGIN {EXCLUSIVE}
	IF GenerateEvents THEN AosEvents.Add(GetEvent("Performance monitor alerts enabled.", 0), FALSE); END;
	alertsEnabled := TRUE;
	INC(stamp);
END EnableAlerts;

PROCEDURE DisableAlerts*;
BEGIN {EXCLUSIVE}
	alertsEnabled := FALSE;
	INC(stamp);
	IF GenerateEvents THEN AosEvents.Add(GetEvent("Performance monitor alerts disabled.", 0), FALSE); END;
END DisableAlerts;

PROCEDURE Enable*(par : ANY) : ANY;
BEGIN
	EnableAlerts;
	AosOut.String("WMPerfMonAlerts: Alerts ENABLED."); AosOut.Ln;
	RETURN NIL
END Enable;

PROCEDURE Disable*(par : ANY) : ANY;
BEGIN
	DisableAlerts;
	AosOut.String("WMPerfMonAlerts: Alerts DISABLED."); AosOut.Ln;	
	RETURN NIL
END Disable;

PROCEDURE UnloadX;
VAR a : Alert;
BEGIN
	a := alerts;
	WHILE (a # NIL) DO
		a.Finalize; a := a.next;
	END;	
END UnloadX;

PROCEDURE Cleanup;
BEGIN
	alertsEnabled := FALSE;
	WMPerfMonPlugins.updater.RemoveListener(SELF, HandleEvents);
	BEGIN {EXCLUSIVE} UnloadX; END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
	alertsEnabled := TRUE; stamp := 1;
	WMPerfMonPlugins.updater.AddListener({WMPerfMonPlugins.EventSampleLoopDone}, SELF, HandleEvents);
END WMPerfMonAlerts.

WMPerfMonAlerts.Load ~	WMPerfMonAlerts.Show ~	S.Free WMPerfMonAlerts ~

WMPerfMonAlerts.Disable ~  WMPerfMonAlerts.Enabled ~
