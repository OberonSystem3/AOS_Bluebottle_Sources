MODULE WMProperties;

IMPORT
		WMRectangles, Utilities, WMEvents, WMLocks, XML, XMLObjects, AosIO, AosOut, AosCommands;

TYPE
	String = Utilities.String;
	Property* = OBJECT
	VAR name, info : String;
			prototype : Property;
			nonDefault : BOOLEAN;
			list : PropertyList; (* contains the list, the property is added to *)
		
			PROCEDURE &New(prototype : Property; name, info : String);
			BEGIN
				SELF.prototype := prototype;
				SELF.name := name;
				SELF.info := info;
				nonDefault := FALSE;
			END New;
			
			PROCEDURE SetPrototype*(prototype : Property);
			BEGIN
				SELF.prototype := prototype;
			END SetPrototype;
			
			PROCEDURE HasPrototype*() : BOOLEAN;
			BEGIN
				RETURN prototype # NIL
			END HasPrototype;

(** Meta-data *)
			PROCEDURE GetInfo*() : String;
			BEGIN
				IF info # NIL THEN RETURN info 
				ELSIF prototype # NIL THEN RETURN prototype.GetInfo()
				ELSE RETURN NIL
				END
			END GetInfo;
			
			PROCEDURE GetName*() : String;
			BEGIN
				IF name # NIL THEN RETURN name 
				ELSIF prototype # NIL THEN RETURN prototype.GetName()
				ELSE RETURN NIL
				END
			END GetName;
			
			PROCEDURE Reset*;
			BEGIN 
				AcquireWrite;
				IF nonDefault THEN nonDefault := FALSE; Changed END;
				ReleaseWrite
			END Reset;
			
			PROCEDURE Changed*; (** PROTECTED *)
			BEGIN
				IF list # NIL THEN list.Changed(SELF) END
			END Changed;
			
			PROCEDURE AcquireWrite*;
			BEGIN
				IF list # NIL THEN list.AcquireWrite END
			END AcquireWrite;
			
			PROCEDURE ReleaseWrite*;
			BEGIN
				IF list # NIL THEN list.ReleaseWrite END
			END ReleaseWrite;

			PROCEDURE AcquireRead*;
			BEGIN
				IF list # NIL THEN list.AcquireRead END
			END AcquireRead;
			
			PROCEDURE ReleaseRead*;
			BEGIN
				IF list # NIL THEN list.ReleaseRead END
			END ReleaseRead;
			
			PROCEDURE NotDefault*; (** PROTECTED *)
			BEGIN
				nonDefault := TRUE
			END NotDefault;
			
			PROCEDURE GetIsDefault*() :  BOOLEAN;
			BEGIN
				RETURN ~ nonDefault
			END GetIsDefault;
			
			PROCEDURE FromStream*(r : AosIO.Reader); (** ABSTRACT *)
			BEGIN
			END FromStream;
			
			PROCEDURE ToStream*(w : AosIO.Writer); (** ABSTRACT *)
			BEGIN
			END ToStream;
			
			PROCEDURE FromXML*(xml : XML.Element);
			BEGIN
			END FromXML;
			
			PROCEDURE WriteXML*(w : AosIO.Writer; indent : LONGINT);
			BEGIN
				
			END WriteXML;
			
		END Property;

TYPE		
	BooleanProperty* = OBJECT(Property)
	VAR value : BOOLEAN;
	
		PROCEDURE FromStream*(r : AosIO.Reader); 
		VAR token : ARRAY 5 OF CHAR; v : BOOLEAN;
		BEGIN
			AcquireWrite;
			NotDefault;
			r.Token(token); Utilities.UpperCase(token); v := token = "TRUE"; 
			IF v # value THEN value := v; Changed END;
			ReleaseWrite
		END FromStream;
		
		PROCEDURE ToStream*(w : AosIO.Writer); 
		BEGIN
			AcquireRead;
			IF Get() THEN w.String("true") ELSE w.String("false") END;
			ReleaseRead
		END ToStream;

		PROCEDURE Get*() : BOOLEAN;
		VAR r : BOOLEAN;
		BEGIN
			AcquireRead;
			IF nonDefault OR (prototype = NIL) THEN r := value 
			ELSE r := prototype(BooleanProperty).Get()
			END;
			ReleaseRead;
			RETURN r
		END Get;
		
		PROCEDURE Set*(value : BOOLEAN);
		BEGIN
			AcquireWrite;
			IF value # SELF.value THEN SELF.value := value; Changed
			ELSIF ~ nonDefault THEN Changed END;
			NotDefault;
			ReleaseWrite;
		END Set;
		
		PROCEDURE FromXML*(xml : XML.Element);
			VAR en : XMLObjects.Enumerator;
			p : PTR; s : String;
		BEGIN
			en := xml.GetContents();
			p := en.GetNext();
			value := FALSE; NotDefault;
			IF p IS XML.Chars THEN
				s := p(XML.Chars).GetStr();
				IF s # NIL THEN
					Utilities.Trim(s^, " "); Utilities.LowerCase(s^);
					Set(s^ = "true")
				END
			END
		END FromXML;
		
		PROCEDURE WriteXML*(w : AosIO.Writer; indent : LONGINT);
		VAR name : String;
		BEGIN
			name := GetName();
			IF name = NIL THEN AosOut.String("Nameless property encountered. Ignored"); AosOut.Ln; RETURN END;
				
			IF nonDefault THEN
				Indent(w, indent);
				w.Char("<"); w.String(name^); w.Char(">");
				IF value THEN w.String("true") ELSE w.String("false") END;
				w.String("</"); w.String(name^); w.Char(">"); w.Ln;			
			END
		END WriteXML;
		
	END BooleanProperty;
			
(** Int32 *)
TYPE
	(** Accessor property to an integer value. The range of possible values can be restricted. *)
	Int32Property* = OBJECT(Property)
	VAR value : LONGINT;
		min, max : LONGINT; bounded, silent : BOOLEAN;
				
		(** Confines the possible input values between min and max. Implicitly activates the bounds check. If the current value
		lies outside the bounds, it is truncated to the nearest and a change notification is sent after the end of the transaction. *)
		PROCEDURE SetBounds*(min, max : LONGINT);
		VAR v : LONGINT;
		BEGIN
			AcquireWrite;
			SELF.min := min; SELF.max := max; bounded := TRUE;
			Set(value);
			ReleaseWrite
		END SetBounds;
		
		(** enables or disables the bounds of the value. If enabled, a change notification is sent if the current value had to be 
		changed to lie within the bounds *)
		PROCEDURE SetIsBounded*(isBounded : BOOLEAN);
		BEGIN
			AcquireWrite;
			IF isBounded # bounded THEN
				bounded := isBounded;
				Set(value)
			END;
			ReleaseWrite
		END SetIsBounded;
		
		PROCEDURE SetSilent*(isSilent : BOOLEAN);
		BEGIN
			AcquireWrite;
			IF isSilent # silent THEN
				silent := isSilent;			
			END;			
			ReleaseWrite
		END SetSilent;
		
		
		PROCEDURE Validate(v : LONGINT) : LONGINT;
		BEGIN
			IF bounded THEN RETURN Utilities.Max(min, Utilities.Min(max, v))
			ELSE RETURN v
			END
		END Validate;
	
		PROCEDURE FromStream*(r : AosIO.Reader);
		VAR v : LONGINT;
		BEGIN
			AcquireWrite;
			r.Int(v, TRUE); 
			Set(v);
			ReleaseWrite
		END FromStream;
		
		PROCEDURE ToStream*(w : AosIO.Writer); 
		BEGIN
			AcquireRead;
			w.Int(value, 0);
			ReleaseRead
		END ToStream;
		
		PROCEDURE Get*() : LONGINT;
		VAR r : LONGINT;
		BEGIN
			AcquireRead;
			IF nonDefault OR (prototype = NIL) THEN r := value 
			ELSE r := prototype(Int32Property).Get()
			END;
			ReleaseRead;
			RETURN r
		END Get;
		
		PROCEDURE Set*(value : LONGINT);
		BEGIN
			AcquireWrite;
			IF Validate(value) # SELF.value THEN SELF.value := Validate(value);
				IF ~silent THEN Changed END 
			ELSIF ~nonDefault & ~silent THEN Changed
			END;
			NotDefault;
			ReleaseWrite
		END Set;
		
		PROCEDURE FromXML*(xml : XML.Element);
			VAR en : XMLObjects.Enumerator;
			p : PTR;
			s, mins, maxs : String;
		BEGIN
			AcquireWrite; NotDefault;
			mins := xml.GetAttributeValue("min");
			maxs := xml.GetAttributeValue("max");
			IF mins # NIL THEN Utilities.StrToInt(mins^, min) ELSE min := MIN(LONGINT) END;
			IF maxs # NIL THEN Utilities.StrToInt(maxs^, max) ELSE max := MAX(LONGINT) END;
			bounded := (mins # NIL) OR (maxs # NIL);
			en := xml.GetContents();
			IF en.HasMoreElements() THEN
				p := en.GetNext();
				IF p IS XML.Chars THEN
					s := p(XML.Chars).GetStr();
					IF s # NIL THEN Utilities.StrToInt(s^, value); Set(value) END
				END
			END;
			ReleaseWrite
		END FromXML;
		
		PROCEDURE WriteXML*(w : AosIO.Writer; indent : LONGINT);
		VAR name : String;
		BEGIN
			name := GetName();
			IF name = NIL THEN AosOut.String("Nameless property encountered. Ignored"); AosOut.Ln; RETURN END;
			IF nonDefault THEN
				Indent(w, indent);
				w.Char("<"); w.String(name^); w.Char(">");
				w.Int(value, 0);
				w.String("</"); w.String(name^); w.Char(">"); w.Ln		
			END
		END WriteXML;
	END Int32Property;
	
TYPE 
	StringProperty* = OBJECT(Property)
	VAR value : String;
	
	(* TODO: Make XML compatible *)
		PROCEDURE FromStream*(r : AosIO.Reader);
		VAR buffer : ARRAY 1024 OF CHAR;
		BEGIN
			AcquireWrite;
			r.String(buffer); value := Utilities.NewString(buffer); NotDefault; Changed;
			ReleaseWrite
		END FromStream;
		
	(* TODO: Make XML compatible *)
		PROCEDURE ToStream*(w : AosIO.Writer); 
		BEGIN
			AcquireRead;
			IF value # NIL THEN w.String(value^) END;
			ReleaseRead
		END ToStream;
		
		PROCEDURE Get*() : String;
		VAR r : String;
		BEGIN
			AcquireRead;
			IF nonDefault OR (prototype = NIL) THEN r := value 
			ELSE r := prototype(StringProperty).Get()
			END;
			ReleaseRead;
			RETURN r
		END Get;
		
		PROCEDURE Set*(value : String);
		BEGIN
			AcquireWrite;
			SELF.value := value; NotDefault; Changed;
			ReleaseWrite
		END Set;
		
		PROCEDURE SetAOC*(value : ARRAY OF CHAR);
		BEGIN
			AcquireWrite;
			SELF.value := Utilities.NewString(value); NotDefault; Changed;
			ReleaseWrite
		END SetAOC;
			
		PROCEDURE FromXML*(xml : XML.Element);
			VAR en : XMLObjects.Enumerator;
			p : PTR;
		BEGIN
			en := xml.GetContents();
			p := en.GetNext();
			IF p # NIL THEN 
				IF p IS XML.Chars THEN
					Set(p(XML.Chars).GetStr())
				END
			ELSE
				Set(NIL)
			END
		END FromXML;
		
		PROCEDURE WriteXML*(w : AosIO.Writer; indent : LONGINT);
		VAR name : String;
		BEGIN
			name := GetName();
			IF name = NIL THEN AosOut.String("Nameless property encountered. Ignored "); RETURN END;
			IF nonDefault THEN		
				IF value # NIL THEN
					Indent(w, indent);
					w.Char("<"); w.String(name^); w.Char(">");
					w.String(value^);
					w.String("</"); w.String(name^); w.Char(">"); w.Ln;
				END;
			END
		END WriteXML;	
	END StringProperty;
	
(** Color *)
TYPE
	(** Accessor property to an integer value. The range of possible values can be restricted. *)
	ColorProperty* = OBJECT(Property)
	VAR value : LONGINT;
	
	(* TODO: read hex from CCG FontConverter *)
		PROCEDURE FromStream*(r : AosIO.Reader);
		VAR v : LONGINT;
		BEGIN
			AcquireWrite;
			r.Int(v, TRUE); NotDefault;
			IF v # value THEN value := v; Changed END;
			ReleaseWrite
		END FromStream;
		
		PROCEDURE ToStream*(w : AosIO.Writer); 
		BEGIN
			AcquireRead;
			w.Hex(value, 8);
			ReleaseRead
		END ToStream;
		
		PROCEDURE Get*() : LONGINT;
		VAR r : LONGINT;
		BEGIN
			AcquireRead;
			IF nonDefault OR (prototype = NIL) THEN r := value 
			ELSE r := prototype(ColorProperty).Get()
			END;
			ReleaseRead;
			RETURN r
		END Get;
		
		PROCEDURE Set*(value : LONGINT);
		BEGIN
			AcquireWrite;
			IF value # SELF.value THEN SELF.value := value; Changed
			ELSIF ~nonDefault THEN Changed
			END;
			NotDefault; 
			ReleaseWrite
		END Set;
		
		PROCEDURE FromXML*(xml : XML.Element);
			VAR en : XMLObjects.Enumerator;
			p : PTR;
			s : String; res : LONGINT;
		BEGIN
			AcquireWrite;
			en := xml.GetContents();
			IF en.HasMoreElements() THEN 
				p := en.GetNext();
				IF p IS XML.Chars THEN
					s := p(XML.Chars).GetStr();
					IF s # NIL THEN Utilities.HexStrToInt(s^, value, res) END; NotDefault
				END
			END;
			ReleaseWrite
		END FromXML;
		
		PROCEDURE WriteXML*(w : AosIO.Writer; indent : LONGINT);
		VAR name : String;
		BEGIN
			name := GetName();
			IF name = NIL THEN AosOut.String("Nameless property encountered. Ignored"); AosOut.Ln; RETURN END;
			IF nonDefault THEN
				Indent(w, indent);
				w.Char("<"); w.String(name^); w.Char(">");
				w.Hex(value, 8);
				w.String("</"); w.String(name^); w.Char(">"); w.Ln;
			END
		END WriteXML;		
		
	END ColorProperty;
	
(** Rectangle *)
TYPE
	(** Accessor property to an integer value. The range of possible values can be restricted. *)
	RectangleProperty* = OBJECT(Property)
	VAR value : WMRectangles.Rectangle;
	
	(* TODO *)
		PROCEDURE FromStream*(r : AosIO.Reader);
		VAR v : LONGINT;
		BEGIN
			AcquireWrite;
			ReleaseWrite
		END FromStream;
		
	(* TODO *)
		PROCEDURE ToStream*(w : AosIO.Writer); 
		BEGIN
			AcquireRead;
			ReleaseRead
		END ToStream;
		
		PROCEDURE Get*() : WMRectangles.Rectangle;
		VAR r : WMRectangles.Rectangle;
		BEGIN
			AcquireRead;
			IF nonDefault OR (prototype = NIL) THEN r := value 
			ELSE r := prototype(RectangleProperty).Get()
			END;
			ReleaseRead;
			RETURN r
		END Get;
		
		PROCEDURE Set*(value : WMRectangles.Rectangle);
		BEGIN
			AcquireWrite;
			IF (SELF.value.l # value.l) OR (SELF.value.t # value.t) OR 
				(SELF.value.r # value.r) OR (SELF.value.b # value.b) THEN 
				SELF.value := value; Changed
			ELSIF ~nonDefault THEN Changed
			END;
			NotDefault;
			ReleaseWrite
		END Set;
	
		PROCEDURE SetWidth*(w : LONGINT);
		BEGIN
			AcquireWrite;
			IF GetWidth() # w THEN Changed END; value.r := value.l + w; NotDefault;
			ReleaseWrite
		END SetWidth;
		
		PROCEDURE SetHeight*(h : LONGINT);
		BEGIN
			AcquireWrite;
			IF GetHeight() # h THEN  Changed END; value.b := value.t + h; NotDefault;
			ReleaseWrite
		END SetHeight;
		
		PROCEDURE SetLeft*(l : LONGINT);
		BEGIN
			AcquireWrite;
			IF value.l # l THEN Changed END; value.r := l + GetWidth(); value.l := l; NotDefault;
			ReleaseWrite
		END SetLeft;
		
		PROCEDURE SetTop*(t : LONGINT);
		BEGIN
			AcquireWrite;
			IF value.t # t THEN Changed END; value.b := t + GetHeight(); value.t := t;  NotDefault;
			ReleaseWrite
		END SetTop;
		
		PROCEDURE SetRight*(r : LONGINT);
		BEGIN
			AcquireWrite;
			IF value.r # r THEN Changed END; value.r := r;  NotDefault;
			ReleaseWrite
		END SetRight;
		
		PROCEDURE SetBottom*(b : LONGINT);
		BEGIN
			AcquireWrite;
			IF value.b # b THEN Changed END; value.b := b; NotDefault;
			ReleaseWrite
		END SetBottom;
		
		PROCEDURE SetExtents*(w, h : LONGINT);
		BEGIN 
			AcquireWrite; (* protective transaction *)
			SetWidth(w); SetHeight(h);
			ReleaseWrite
		END SetExtents;
		
		PROCEDURE GetWidth*() : LONGINT;
		VAR w : LONGINT; t : WMRectangles.Rectangle;
		BEGIN
			AcquireRead;
			t := Get();
			w := t.r - t.l;
			ReleaseRead;
			RETURN w
		END GetWidth;
		
		PROCEDURE GetHeight*() : LONGINT;
		VAR h : LONGINT; t : WMRectangles.Rectangle;
		BEGIN
			AcquireRead;
			t := Get();
			h := t.b - t.t;
			ReleaseRead;
			RETURN h
		END GetHeight;
		
		PROCEDURE FromXML*(xml : XML.Element);
			VAR en : XMLObjects.Enumerator;
			p : PTR;
			s, mins, maxs : String;
		BEGIN
			AcquireWrite;
			en := xml.GetContents();
			WHILE en.HasMoreElements() DO
				IF en.HasMoreElements() THEN
					p := en.GetNext();
					IF (p IS XML.Element) THEN
						s := p(XML.Element).GetName();
						IF s # NIL THEN 
							IF s^ = "Left" THEN SetLeft(ReadCharDataInt(p(XML.Element)))
							ELSIF s^ = "Top" THEN SetTop(ReadCharDataInt(p(XML.Element)))
							ELSIF s^ = "Right" THEN SetRight(ReadCharDataInt(p(XML.Element)))
							ELSIF s^ = "Bottom" THEN SetBottom(ReadCharDataInt(p(XML.Element)))
							ELSIF s^ = "Width" THEN SetWidth(ReadCharDataInt(p(XML.Element)))
							ELSIF s^ = "Height" THEN SetHeight(ReadCharDataInt(p(XML.Element)))
							END
						END
					END
				END
			END;	
			ReleaseWrite
		END FromXML;

		PROCEDURE WriteXML*(w : AosIO.Writer; indent : LONGINT);
		VAR name : String;
			t : WMRectangles.Rectangle;			
		BEGIN
			name := GetName();
			IF name = NIL THEN AosOut.String("Nameless property encountered. Ignored"); AosOut.Ln; RETURN END;
			IF nonDefault THEN
				t := Get();
				Indent(w, indent);w.Char("<"); w.String(name^); w.Char(">"); w.Ln;
				Indent(w, indent + 1); w.String("<Left>"); w.Int(t.l, 0); w.String("</Left>"); w.Ln;
				Indent(w, indent + 1); w.String("<Top>"); w.Int(t.t, 0); w.String("</Top>"); w.Ln;
				Indent(w, indent + 1); w.String("<Width>"); w.Int(t.r-t.l, 0); w.String("</Width>"); w.Ln;
				Indent(w, indent + 1); w.String("<Height>"); w.Int(t.b-t.t, 0); w.String("</Height>"); w.Ln;
				Indent(w, indent); w.String("</"); w.String(name^); w.Char(">"); w.Ln;
			END
		END WriteXML;		
		
		
	END RectangleProperty;
	
TYPE
	PropertyArray* = POINTER TO ARRAY OF Property;
	PropertyList* = OBJECT
	VAR
		properties : PropertyArray;
		nofProperties : LONGINT;
		onPropertyChanged* : WMEvents.EventSource;
		lock : WMLocks.RWLock;
		upNofChanges : LONGINT;
		upChanged : Property;
		
		PROCEDURE &New ;
		BEGIN
			NEW(properties, 8); 
			NEW(onPropertyChanged, SELF, StringProperties, StringPropertiesInfo, NIL);
			NEW(lock)
		END New;
		
		(** acquire a write lock on the object *)
		PROCEDURE AcquireWrite*;
		BEGIN
			lock.AcquireWrite
		END AcquireWrite;
		
		(** release the write lock on the object *)
		PROCEDURE ReleaseWrite*;
		VAR removeLock : BOOLEAN;
			changed : Property; nofChanges : LONGINT;
		BEGIN 
			removeLock := lock.GetWLockLevel() = 1;
			IF removeLock THEN changed := upChanged; nofChanges := upNofChanges END;
			upNofChanges := 0; upChanged := NIL;
			lock.ReleaseWrite;
			IF removeLock THEN
				IF nofChanges = 1 THEN onPropertyChanged.Call(changed)
				ELSIF nofChanges > 0 THEN onPropertyChanged.Call(SELF)
				END
			END
		END ReleaseWrite;
		
		PROCEDURE AcquireRead;
		BEGIN
			lock.AcquireRead
		END AcquireRead;
		
		PROCEDURE ReleaseRead;
		BEGIN
			lock.ReleaseRead
		END ReleaseRead;
		
		PROCEDURE Add*(x : Property);
		BEGIN
			AcquireWrite;
			x.list := SELF;
			IF nofProperties = LEN(properties) THEN Grow END;
			properties[nofProperties] := x;
			INC(nofProperties);
			ReleaseWrite
		END Add;
	
		PROCEDURE Remove*(x : Property);
		VAR i : LONGINT;
		BEGIN
			AcquireWrite;
			i := 0; WHILE (i < nofProperties) & (properties[i] # x) DO INC(i) END;
			IF i < nofProperties THEN 
				WHILE (i < nofProperties - 1) DO properties[i] := properties[i + 1]; INC(i) END;
				DEC(nofProperties);
				properties[nofProperties] := NIL
			END;
			ReleaseWrite
		END Remove;

		PROCEDURE Grow;
		VAR  new: PropertyArray;
				i : LONGINT;
		BEGIN 
			NEW(new, LEN(properties) * 2);
			FOR i := 0 TO nofProperties - 1 DO new[i] := properties[i] END;
			properties := new
		END Grow;
		
		PROCEDURE Enumerate*() : PropertyArray;
		VAR current : PropertyArray; i : LONGINT;
		BEGIN 
			AcquireWrite;
			NEW(current, nofProperties);
			FOR i := 0 TO nofProperties - 1 DO current[i] := properties[i] END;
			ReleaseWrite;
			RETURN current
		END Enumerate;
		
		PROCEDURE SetPropertyValue*(name, value : String) : BOOLEAN;
		VAR i : LONGINT; n : String;
			vs : AosIO.StringReader;
		BEGIN 
			AcquireWrite;
			IF (name = NIL) OR (value = NIL) THEN ReleaseWrite; RETURN FALSE END;
			i := 0;  
			WHILE i < nofProperties DO
				n := properties[i].GetName();
				IF (n # NIL) & (n^ = name^) THEN
					NEW(vs, LEN(value^));
					properties[i].FromStream(vs); i := nofProperties
				END;
				INC(i)
			END;
			ReleaseWrite;
			RETURN (i < nofProperties)
		END SetPropertyValue;
		
		PROCEDURE SetXML*(xml : XML.Element);
		VAR
			en : XMLObjects.Enumerator;
			p : PTR; s, n : String; i : LONGINT;
		BEGIN
			AcquireWrite;
			en := xml.GetContents(); 
			WHILE en.HasMoreElements() DO
				p := en.GetNext();
				IF p IS XML.Element THEN
					s := p(XML.Element).GetName();
					i := 0;  
					WHILE i < nofProperties DO
						n := properties[i].GetName();
						IF (n # NIL) & (n^ = s^) THEN
							properties[i].FromXML(p(XML.Element)); i := nofProperties
						END;
						INC(i)
					END
				END
			END;
			ReleaseWrite
		END SetXML;
		
		PROCEDURE WriteXML*(w : AosIO.Writer; indent : LONGINT);
		VAR i : LONGINT;
		BEGIN
			w.Ln;
			Indent(w, indent + 1);
			w.String("<Properties>"); w.Ln;
			AcquireRead;
			FOR i := 0 TO nofProperties - 1 DO
				properties[i].WriteXML(w, indent + 2)
			END;
			Indent(w, indent + 1);
			w.String("</Properties>");
			ReleaseRead
		END WriteXML;
		
		PROCEDURE Changed(p : Property);
		BEGIN (* {EXCLUSIVE} *)
			IF p # upChanged THEN INC(upNofChanges);  upChanged := p END;
		END Changed;
		
	END PropertyList;
	
VAR
	StringProperties : String;
	StringPropertiesInfo : String;
	
PROCEDURE Indent(w : AosIO.Writer; indent : LONGINT);
VAR i : LONGINT;
BEGIN
	FOR i := 0 TO indent - 1 DO w.Char(9X) END
END Indent;

	
PROCEDURE ReadCharDataInt(xml : XML.Element) : LONGINT;
VAR en : XMLObjects.Enumerator;
	p : PTR; s : String; value : LONGINT;
BEGIN
	value := 0;
	en := xml.GetContents();
	IF en.HasMoreElements() THEN
		p := en.GetNext();
		IF p IS XML.Chars THEN
			s := p(XML.Chars).GetStr();
			IF s # NIL THEN Utilities.StrToInt(s^, value) END
		END;
	END;
	RETURN value
END ReadCharDataInt;

BEGIN
	StringProperties := Utilities.NewString("PropertyList");
	StringPropertiesInfo := Utilities.NewString("the event is called if a property in the list is changed")
END WMProperties.

