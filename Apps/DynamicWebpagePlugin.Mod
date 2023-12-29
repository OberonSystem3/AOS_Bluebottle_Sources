MODULE DynamicWebpagePlugin; (** AUTHOR "Luc Blaeser"; PURPOSE "HTTP Webserver Plugin for Dynamic Webpages"; *)

IMPORT
	DynamicWebpage, HTTPSupport, HTTPSession, WebHTTP, WebHTTPServer, AosFS, Utilities, AosIO, AosCommands, 
	AosOut, XML, XMLScanner, XMLParser, XMLObjects, DynamicStrings, TFClasses, AosConfig, AosModules;

CONST
	DEBUG = FALSE; (* disply debug information *)
	ShowRegisteredElements = FALSE; (* show all registered active elements *)
	
	PluginName = "Dynamic Webpage Plugin";
	
	PreTransformation = TRUE;
	PostTransformation = FALSE;
		
	MaxTransformationDepth = 40; (* maxmimum number of recursive steps to transform a transformation result *)
	DocType = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
	
TYPE
	DynamicWebpagePlugin = OBJECT (WebHTTPServer.HTTPPlugin)
		PROCEDURE &Init(name: WebHTTPServer.Name);
		BEGIN
			Init^(PluginName)
		END Init;
		
		PROCEDURE CanHandle(host: WebHTTPServer.Host; VAR request: WebHTTP.RequestHeader) : BOOLEAN;
		VAR name, ext: AosFS.FileName; f: AosFS.File; newuri : ARRAY 4096 OF CHAR;
		BEGIN
			HTTPSupport.RemoveVariablesFromURI(request.uri, newuri);
			IF (request.method IN {WebHTTP.GetM, WebHTTP.PostM, WebHTTP.HeadM}) THEN
				IF (newuri[Utilities.Length(newuri)-1] = "/") THEN (* check for default webpage "index.dxp" *)
					COPY(host.prefix, name); Utilities.Append(name, newuri); 
					Utilities.Append(name, DynamicWebpage.DefaultWebpage);
					f := AosFS.Old(name);
					RETURN (f # NIL) 
				ELSE
					AosFS.SplitExtension(newuri, name, ext);
					Utilities.UpperCase(ext);
					RETURN (ext = DynamicWebpage.DynamicWebpageExtension) 
				END
			ELSE 
				RETURN FALSE
			END
		END CanHandle;
		
		PROCEDURE Handle*(host: WebHTTPServer.Host; VAR requestHeader: WebHTTP.RequestHeader; VAR reply: WebHTTP.ResponseHeader;
				VAR in: AosIO.Reader; VAR out: AosIO.Writer);
		VAR chunker: WebHTTP.ChunkedOutStream; w: AosIO.Writer; f: AosFS.File; backupUri: ARRAY 4096 OF CHAR;
			request: HTTPSupport.HTTPRequest; session: HTTPSession.Session;
		BEGIN
			(* requestHeader.method IN {WebHTTP.GetM, WebHTTP.PostM, WebHTTP.HeadM} *)
			NEW(request, requestHeader, in);
						
			WebHTTP.SetAdditionalFieldValue(requestHeader.additionalFields, "If-Modified-Since", " ");   (* prohibit conditional get for dynamic webpages  *)
			WebHTTPServer.GetDefaultResponseHeader(requestHeader, reply);
			IF (request.shortUri[Utilities.Length(request.shortUri)-1] = "/") THEN (* get default webpage "index.dxp" in a directory *)
				Utilities.Append(request.shortUri, DynamicWebpage.DefaultWebpage);
				Utilities.Concat("http://", requestHeader.host, reply.contentlocation);
				Utilities.Append(reply.contentlocation, request.shortUri);
			END;
			
			(* LocateResource works only with variable-free URI in requestHeader *)
			COPY(requestHeader.uri, backupUri); COPY(request.shortUri, requestHeader.uri); 
			LocateResource(host, requestHeader, reply, f); (* sets also reply.statuscode *)
			COPY(backupUri, requestHeader.uri);
						
			IF ((f # NIL) & ((reply.statuscode = WebHTTP.OK) OR (reply.statuscode = WebHTTP.NotModified))) THEN
				reply.statuscode := WebHTTP.OK;
				Utilities.FormatDateTime(WebHTTP.DateTimeFormat, Utilities.Now(), reply.lastmodified); (* dynamic webpages have no last modified *)
				WebHTTP.SetAdditionalFieldValue(reply.additionalFields, "Expires", reply.lastmodified); 
					(* deny web caching; Expires=0 is illegal but often used to deny web caching *)
				WebHTTP.SetAdditionalFieldValue(reply.additionalFields, "Pragma", "no-cache");  (* deny web caching *)
				COPY("text/html", reply.contenttype); (* result is XHTML *)
				
				NEW(chunker, w, out, requestHeader, reply);
				WebHTTP.SendResponseHeader(reply, out);
				
				session := HTTPSession.GetSession(request);
				session.IncreaseLifeTime;
				
				(* detect whether the user has used the back or refresh button of the navigation bar *)
				IF (BackRefreshButtonWasPressed(request, session)) THEN
					HandleBackRefreshButtonError(request, w)
				ELSE
					HandleClientAction(request); (* first handle a client event *) 
				
					IF ((requestHeader.method = WebHTTP.GetM) OR (requestHeader.method = WebHTTP.PostM)) THEN
						GenerateDynamicWebpage(f, request, w)
					END
				END;
				chunker.Close
			ELSIF (reply.statuscode = WebHTTP.ObjectMoved) THEN
				NEW(chunker, w, out, requestHeader, reply);
				WebHTTP.SendResponseHeader(reply, out);
				
				w.String(DocType); w.Ln;
				w.String("<html><head><title>Document Moved</title></head>"); w.Ln;
				w.String('<body><h1>Document Moved</h1>This document may be found <a href="http://');
				w.String(requestHeader.uri); w.String(">here</a>.<hr/><address>");
				w.String(WebHTTPServer.ServerVersion); w.String("</address></body></html>"); w.Ln;
				w.Update; 
				chunker.Close
			ELSIF ((reply.statuscode = WebHTTP.NotFound) OR (f = NIL)) THEN
				reply.statuscode := WebHTTP.NotFound;
				NEW(chunker, w, out, requestHeader, reply);
				WebHTTP.SendResponseHeader(reply, out);
							
				w.String(DocType); w.Ln;
				w.String("<html><head><title>404 - Not Found</title></head>");
				w.String("<body>HTTP 404 - File Not Found<hr/><address>");
				w.String(WebHTTPServer.ServerVersion); w.String("</address></body></html>"); 
				w.Ln; 
				w.Update; 
				chunker.Close
			ELSE
				reply.statuscode := WebHTTP.NotImplemented;
				WebHTTP.WriteStatus(reply, out)			
			END
		END Handle;
	END DynamicWebpagePlugin;
	
	ParserError = POINTER TO RECORD
		pos, line, row: LONGINT;
		msg: ARRAY 1024 OF CHAR
	END;
	
	SessionStateFullElement = OBJECT
		VAR
			(* each statefull object instance is identified by an object id (constructed out of file and explicit id in xml representation) *)
			objectId: Utilities.String; 
			session: HTTPSession.Session;
			activeElem: DynamicWebpage.StateFullActiveElement;
			eventHandlers: DynamicWebpage.EventHandlerList;
		
		PROCEDURE &Init(id: Utilities.String; sess: HTTPSession.Session; elem: DynamicWebpage.StateFullActiveElement; 
			handlerList : DynamicWebpage.EventHandlerList);
		BEGIN (* id # NIL & sess # NIL & elem # NIL *)
			NEW(objectId, LEN(id)); COPY(id^, objectId^); 
			session := sess; activeElem := elem; eventHandlers:= handlerList
		END Init;
	END SessionStateFullElement;
	
	(* Abstracts the creation and delegation to a statefull or stateless active element instances. 
	    The type of the active element (stateless or statefull) is defined by the creation on the first access 
	    Stateless active elements are singleton and used by all sessions. Statefull active elements belong 
	    to exactly one session and have multiple instances identified explicitly by the webpage file and 
	    an "id" attribute in the XML representation. *)
	ActiveElementFactory = OBJECT 
		VAR
			moduleName: ARRAY 128 OF CHAR;
			activeElemDesc: DynamicWebpage.ActiveElementDescriptor;
			
			(* used if it is a stateless active element, otherwise NIL *)
			stateLessActiveElem: DynamicWebpage.StateLessActiveElement; (* singleton *)
			stateLessEventHandlers: DynamicWebpage.EventHandlerList;
			
			(* used if it is a statefull active element, otherwise NIL *)
			stateFullActiveElems: TFClasses.List; (* List of SessionStateFullElement *)
			
		PROCEDURE &Init(module: Utilities.String; desc: DynamicWebpage.ActiveElementDescriptor);
		BEGIN
			ASSERT(module # NIL); ASSERT(desc # NIL); ASSERT(desc.factory # NIL);
			COPY(module^, moduleName); activeElemDesc := desc
		END Init;
		
		PROCEDURE SessionExpired(session: HTTPSession.Session);
		VAR sessionElem: SessionStateFullElement; expElemList: TFClasses.List; (* List of SessionStateFullElement *) 
			i : LONGINT; p: PTR; 
		BEGIN {EXCLUSIVE}
			(* there could be multiple instances of a statefull active element belonging to session *)  
			NEW(expElemList);
			stateFullActiveElems.Lock; 
			FOR i := 0 TO stateFullActiveElems.GetCount()-1 DO
				p := stateFullActiveElems.GetItem(i); sessionElem := p(SessionStateFullElement); (* sessionElem # NIL *)
				IF (sessionElem.session = session) THEN
					expElemList.Add(sessionElem)
				END
			END;
			stateFullActiveElems.Unlock;
			FOR i:= 0 TO expElemList.GetCount()-1 DO 
				p := expElemList.GetItem(i);
				stateFullActiveElems.Remove(p)
			END;
			IF (DEBUG) THEN
				AosOut.String("Statefull active element instances '"); AosOut.String(activeElemDesc.elementName);
				AosOut.String("' in module '"); AosOut.String(moduleName); AosOut.String("' have been freed for session '");
				AosOut.String(session.sessionId); AosOut.String("'."); AosOut.Ln
			END
		END SessionExpired;
		
		(* must be called before disposing the object *)
		PROCEDURE PrepareDisposal;
		BEGIN
			IF (stateFullActiveElems # NIL) THEN (* contains statefull active element *)
				HTTPSession.RemoveExpirationHandler(SessionExpired)
			END
		END PrepareDisposal;
		
		(* objectId is only used if a statefull active element is requested, otherwise objectId can be NIL *)
		PROCEDURE GetElementInstance(session : HTTPSession.Session; objectId: Utilities.String) : DynamicWebpage.ActiveElement;
		VAR i: LONGINT; p: PTR; sessionElem: SessionStateFullElement; elem: DynamicWebpage.ActiveElement;
			stateFullElem: DynamicWebpage.StateFullActiveElement; eventHandlerList: DynamicWebpage.EventHandlerList;
		BEGIN {EXCLUSIVE}  
			IF (stateLessActiveElem # NIL) THEN (* it is a stateless active element *)
				RETURN stateLessActiveElem
			ELSIF (stateFullActiveElems # NIL) THEN (* it is a statefull active element *)
				IF (objectId # NIL) THEN
					stateFullActiveElems.Lock; 
					FOR i := 0 TO stateFullActiveElems.GetCount()-1 DO
						p := stateFullActiveElems.GetItem(i); sessionElem := p(SessionStateFullElement); 
						(* sessionElem # NIL & sessionElem.objectId # NIL *)
						IF ((sessionElem.session = session) & (sessionElem.objectId^ = objectId^)) THEN
							stateFullActiveElems.Unlock;
							RETURN sessionElem.activeElem;
						END
					END;
					stateFullActiveElems.Unlock;
					(* create a new statefull element *)
					elem := activeElemDesc.factory(); 
					(* elem # NIL since there was already a statefull element instance created by this factory method *)
					stateFullElem := elem(DynamicWebpage.StateFullActiveElement);
					eventHandlerList := elem.GetEventHandlers();
					NEW(sessionElem, objectId, session, stateFullElem, eventHandlerList);
					stateFullActiveElems.Add(sessionElem);
					RETURN elem
				ELSE
					AosOut.String("Dynamic Webpage Plugin: The statefull active element '"); 
					AosOut.String(activeElemDesc.elementName); AosOut.String("' in module '");
					AosOut.String(moduleName); AosOut.String("' must be used together with an id in a webpage file.");
					AosOut.Ln;
					RETURN NIL
				END
			ELSE (* it is not yet determined if it is a statefull or stateless active element *)
				elem := activeElemDesc.factory();
				IF (elem # NIL) THEN
					IF (elem IS DynamicWebpage.StateFullActiveElement) THEN
						IF (objectId # NIL) THEN
							(* initialize as statefull active element factory *)
							NEW(stateFullActiveElems); 
							HTTPSession.AddExpirationHandler(SessionExpired);
							
							stateFullElem := elem(DynamicWebpage.StateFullActiveElement);
							eventHandlerList := elem.GetEventHandlers();
							NEW(sessionElem, objectId, session, stateFullElem, eventHandlerList);
							stateFullActiveElems.Add(sessionElem);
							RETURN stateFullElem
						ELSE
							AosOut.String("Dynamic Webpage Plugin: The statefull active element '"); 
							AosOut.String(activeElemDesc.elementName); AosOut.String("' in module '");
							AosOut.String(moduleName); AosOut.String("' must be used together with an attribute '");
							AosOut.String(DynamicWebpage.XMLAttributeObjectIdName); AosOut.String("'.");
							AosOut.Ln;
							RETURN NIL
						END
					ELSIF (elem IS DynamicWebpage.StateLessActiveElement) THEN
						(* initialize as stateless active element factory *)
						stateLessActiveElem := elem(DynamicWebpage.StateLessActiveElement);
						stateLessEventHandlers := elem.GetEventHandlers();
						RETURN elem
					ELSE (* elem IS DynamicWebpage.ActiveElement *)
						AosOut.String("Dynamic Webpage Plugin: The active element '"); 
						AosOut.String(activeElemDesc.elementName); AosOut.String("' in module '");
						AosOut.String(moduleName); AosOut.String("' must be either a stateless or statefull active element.");
						AosOut.Ln;
						RETURN NIL
					END
				ELSE
					AosOut.String("Dynamic Webpage Plugin: Invalid result from the factory for the active element '");
					AosOut.String(activeElemDesc.elementName); AosOut.String("' in module '"); 
					AosOut.String(moduleName); AosOut.String("'"); AosOut.Ln;
					RETURN NIL
				END
			END
		END GetElementInstance;
		
		(* objectId is only used for statefull activ elements and is NIL  in case of stateless active elements *)
		PROCEDURE FindEventHandler(session: HTTPSession.Session; objectId: Utilities.String; handlerName: ARRAY OF CHAR) : DynamicWebpage.EventHandler;
		VAR elem: DynamicWebpage.ActiveElement; sessionElem: SessionStateFullElement; p: PTR; i : LONGINT;
		
			PROCEDURE GetEventHandlerFromList(eventList: DynamicWebpage.EventHandlerList) : DynamicWebpage.EventHandler;
			VAR j: LONGINT; 
			BEGIN
				IF (eventList # NIL) THEN
					FOR j := 0 TO LEN(eventList^)-1 DO
						IF (eventList[j] # NIL) THEN
							IF (eventList[j].methodName = handlerName) THEN
								RETURN eventList[j].handler
							END
						ELSE
							AosOut.String("Dynamic Webpage Plugin: The "); AosOut.Int(j, 0); 
							AosOut.String(".th event handler is not defined in the event handler list in the active element '");
							AosOut.String(activeElemDesc.elementName); AosOut.String("' in module '"); 
							AosOut.String(moduleName); AosOut.String("'"); AosOut.Ln
						END
					END
				END;
				RETURN NIL
			END GetEventHandlerFromList;
			
		BEGIN
			elem := GetElementInstance(session, objectId); (* this guarantees that the needed active element instance is now present *)
			IF ((elem # NIL) & (elem IS DynamicWebpage.StateLessActiveElement)) THEN (* it is a stateless active element *)
				RETURN GetEventHandlerFromList(stateLessEventHandlers)
			ELSIF ((objectId # NIL) & (elem # NIL) & (elem IS DynamicWebpage.StateFullActiveElement)) THEN (* it is a statefull active element *)
				(* stateFullActiveElems # NIL by GetElementInstance *)
				stateFullActiveElems.Lock; 
				FOR i := 0 TO stateFullActiveElems.GetCount()-1 DO
					p := stateFullActiveElems.GetItem(i); sessionElem := p(SessionStateFullElement); (* sessionElem # NIL *)
					IF ((sessionElem.session = session) & (sessionElem.objectId^ = objectId^)) THEN
						stateFullActiveElems.Unlock;
						RETURN GetEventHandlerFromList(sessionElem.eventHandlers);
					END
				END;
				stateFullActiveElems.Unlock;	
				RETURN NIL
			ELSE (* error message already displayed by GetElementInstance *)
				RETURN NIL
			END
		END FindEventHandler;
		
	END ActiveElementFactory;
		
	VAR 
		dynamicPagePlugin: DynamicWebpagePlugin; (* singleton instance to be able to uninstall *)
		lockServingHosts: BOOLEAN; (* lock hold when operating on servingHosts *)
		servingHosts: TFClasses.List; (* List of WebHTTPServer.Host *)
		registeredActiveElemFact: TFClasses.List; (* List of ActiveElementFactory *)
		parserError: ParserError; (* since there is no DELEGATE for the reportErrorHandler XML-Module possible *)
		
	(* Returns true iff back or refresh button was pressed and increases the state counter if back button was not pressed *)
	PROCEDURE BackRefreshButtonWasPressed(request: HTTPSupport.HTTPRequest; session: HTTPSession.Session) : BOOLEAN;
	VAR httpVar: HTTPSupport.HTTPVariable; httpCounter, sessionCounter: LONGINT; p: PTR; 
		dynStr: DynamicStrings.DynamicString; str: Utilities.String; numberStr: ARRAY 14 OF CHAR;
	BEGIN (* request # NIL & session # NIL *)
		httpVar := request.GetVariableByName(DynamicWebpage.StateCounterVariable);
		httpCounter := 0;
		IF (httpVar # NIL) THEN
			Utilities.StrToInt(httpVar.value, httpCounter);
			p := session.GetVariableValue(DynamicWebpage.StateCounterVariable);
			IF ((p # NIL) & (p IS DynamicStrings.DynamicString)) THEN
				dynStr := p(DynamicStrings.DynamicString); str := dynStr.ToArrOfChar(); (* str # NIL *)
				Utilities.StrToInt(str^, sessionCounter);
				IF (httpCounter < sessionCounter) THEN
					RETURN TRUE
				END
			END
		END;
		INC(sessionCounter);
		Utilities.IntToStr(sessionCounter, numberStr); NEW(dynStr); dynStr.Append(numberStr);
		session.AddVariableValue(DynamicWebpage.StateCounterVariable, dynStr);
		RETURN FALSE
	END BackRefreshButtonWasPressed;
	
	(* handle the case that the user has used the back button of the browser's navigation bar *)
	PROCEDURE HandleBackRefreshButtonError(request: HTTPSupport.HTTPRequest; w: AosIO.Writer);
	VAR sessionId: HTTPSession.SessionId;
	BEGIN
		HTTPSession.GetSessionId(request, sessionId);
		w.String(DocType); w.Ln;
		w.String("<html><head><title>Do not use the back or refresh button</title></head>"); w.Ln;
		w.String("<body><h1>Do not use the back or refresh button in the navigation bar</h1>");
		w.String("Using the back or refresh button in the navigation bar of this browser is not allowed when using dynamic ");
		w.String("webpages.<br/>To continue click ");w.String('<a href="'); 
		w.String(request.shortUri); w.String("?"); 
		w.String(HTTPSession.HTTPVarSessionIdName); w.String("="); w.String(sessionId);
		w.String('">here</a>.<hr/><address>'); w.String(WebHTTPServer.ServerVersion); 
		w.String("</address></body></html>"); w.Ln;
		w.Update;
	END HandleBackRefreshButtonError;
		
	PROCEDURE GenerateDynamicWebpage(f: AosFS.File; request: HTTPSupport.HTTPRequest; w: AosIO.Writer);
	VAR scanner: XMLScanner.Scanner; parser: XMLParser.Parser; doc: XML.Document;
		root: XML.Element; rootContent: XML.Content; errormsg: ARRAY 1024 OF CHAR;
	BEGIN  (* f # NIL *)
		NEW(scanner, f);
		NEW(parser, scanner);
		scanner.reportError := ReportXMLParserScannerError;
		parser.reportError := ReportXMLParserScannerError;
		BEGIN {EXCLUSIVE} 
			(* the error handler needs additional information about the file and writer but is not a delegate *)
			parserError := NIL;
			doc := parser.Parse();
			IF (parserError # NIL) THEN
				Utilities.Concat("Error while parsing: ", parserError.msg, errormsg);
				ReportGeneratorError(f, w, parserError.pos, parserError.line, parserError.row, errormsg);
				doc := NIL
			END
		END;
		
		IF doc # NIL THEN
			root := doc.GetRoot(); rootContent := root;
			IF (TransformXMLTree(rootContent, request, 0, w)) THEN (* transformation worked successfully *)
				(* Must be allowed in XML-module setDoc: 
					IF (rootContent IS XML.Element) THEN 
						root := rootContent(XML.Element);
				    	doc.SetRoot(root) 
				    ELSE 
				    	Error "transformation result has not a root element"
				    END
				 *)
				w.String(DocType); w.Ln;
				doc.Write(w, 0); (* externalize transformation result *)
			END
		END;
		w.Update
	END GenerateDynamicWebpage;
	
	(* returns true iff the transformation worked without an error *)
	PROCEDURE TransformXMLTree(VAR n: XML.Content; VAR request: HTTPSupport.HTTPRequest; 
		transformationDepth: INTEGER;  w: AosIO.Writer) : BOOLEAN; 
	VAR enum, resultEnum: XMLObjects.Enumerator; pChild, pResultChild: PTR; elem: XML.Element; 
		child, newChild, resultChild: XML.Content; errormsg: ARRAY 256 OF CHAR; wasTransformed: BOOLEAN;
		elemName : Utilities.String; container, snapshot, resultContainer: XML.Container; 
	BEGIN
		IF ((n # NIL) & (n IS XML.Element) & (transformationDepth > MaxTransformationDepth)) THEN
			elem := n(XML.Element); elemName := elem.GetName();
			Utilities.Concat("In element '", elemName^, errormsg);
			Utilities.Append(errormsg, "': Maximum recursive transformation steps reached. There could be an endless loop in a transformation procedure.");
			ReportGeneratorError(elem.GetFile(), w, elem.GetPos(), 0, 0, errormsg);
			RETURN FALSE (* stop the further traversal *)
		ELSIF ((n # NIL) & (n IS XML.Container)) THEN
			(* pre-postorder traversal with recursive traversal of the post transformation result
			    increase transformation depth only if it is a transformation of the transformation result *)
			wasTransformed := FALSE;
			
			(* pre transformation *)
			IF (n IS XML.Element) THEN
				elem := n(XML.Element);
				IF (IsActive(elem))THEN
					IF (~TransformActiveElement(n, PreTransformation, request, w)) THEN RETURN FALSE END;
					wasTransformed := TRUE
				END
			END;
			 
			IF ((n # NIL) & (n IS XML.Container)) THEN (* transformation result of PreTransform could be not a container *)
				container := n(XML.Container);
				(* no modification while iteration allowed, extract first the contents into a snapshot *)
				ExtractContentsOfContainer(container, snapshot);
				enum := snapshot.GetContents();
				WHILE (enum.HasMoreElements()) DO
					pChild := enum.GetNext(); child := pChild(XML.Content); newChild := child;
					IF (~TransformXMLTree(newChild, request, transformationDepth, w)) THEN RETURN FALSE END;
					IF (newChild # NIL) THEN 
						IF ((newChild IS XML.Container) & (~(newChild IS XML.Element))) THEN (* avoid nested containers *)
							resultContainer := newChild(XML.Container);
							resultEnum := resultContainer.GetContents();
							WHILE(resultEnum.HasMoreElements()) DO
								pResultChild := resultEnum.GetNext(); resultChild := pResultChild(XML.Content);
								container.AddContent(resultChild)
							END
						ELSE
							container.AddContent(newChild)
						END
					END
				END;
			
				(* post transformation *)
				IF (n IS XML.Element) THEN 
					elem := n(XML.Element);
					IF (IsActive(elem)) THEN
						IF (~TransformActiveElement(n, PostTransformation, request, w)) THEN RETURN FALSE END
					END
				END
			END;
			IF (wasTransformed) THEN
				(* transformation of the transformation result is needed *)
				IF (~TransformXMLTree(n, request, transformationDepth+1, w)) THEN RETURN FALSE END;
				IF (DEBUG) THEN Log(elem) END
			END
		END; (* transformation result could be not a container *)
		RETURN TRUE
	END TransformXMLTree;
	
	PROCEDURE Log(elem: XML.Element);
	VAR sw: AosIO.StringWriter; w: AosIO.Writer; msg: ARRAY 1024 OF CHAR;
	BEGIN
		NEW(sw, LEN(msg)); w := sw; elem.Write(w, 0);
		sw.Get(msg); AosOut.String(msg); AosOut.Ln
	END Log;
	
	PROCEDURE ExtractContentsOfContainer(input: XML.Container; VAR output: XML.Container);
	VAR e: XMLObjects.Enumerator; p : PTR; child: XML.Content;
	BEGIN
		NEW(output); 
		(* first copy contents to output *)
		e := input.GetContents();
		WHILE (e.HasMoreElements()) DO
			p := e.GetNext(); child := p(XML.Content);
			output.AddContent(child);
		END;
		
		(* then remove contents from input *)
		e := output.GetContents();
		WHILE (e.HasMoreElements()) DO
			p := e.GetNext(); child := p(XML.Content);
			input.RemoveContent(child);
		END
	END ExtractContentsOfContainer;
	
	PROCEDURE IsActive(n : XML.Element) : BOOLEAN;
	VAR module, obj: Utilities.String;
	BEGIN (* n # NIL *)
		ExtractModuleObjectName(n, module, obj);
		(* check whether the module is declared to represent an active namespace *)
		IF ((module # NIL) & (obj # NIL)) THEN
			RETURN IsModuleRegistered(module^)
		ELSE
			RETURN FALSE
		END
	END IsActive;
	
	(* get the objectId if specfified used for statefull active elements *)
	PROCEDURE GetObjectId(id: ARRAY OF CHAR; request: HTTPSupport.HTTPRequest) : Utilities.String;
	VAR objectId: Utilities.String;
	BEGIN
		(* the object id is composed by the actual uri and id attribute for the active element *)
		(* '&' does occur neither in a xml attribute nor in shortUri *)
		NEW(objectId, LEN(id)+Utilities.Length(request.shortUri)+1); 
		Utilities.Concat(request.shortUri, "&", objectId^);
		Utilities.Append(objectId^, id);
		RETURN objectId
	END GetObjectId;
	
	(** if isPreTransformation is TRUE then PreTansform() is called otherwise PostTransform(), 
	 *  returns true iff the transformation worked without an error *)
	PROCEDURE TransformActiveElement(VAR n: XML.Content; isPreTransformation: BOOLEAN; 
		request: HTTPSupport.HTTPRequest; w: AosIO.Writer) : BOOLEAN;
	VAR moduleName, objName, elemName, objectId, oidAttrVal: Utilities.String; elem: XML.Element;
		activeElemFact: ActiveElementFactory; errormsg: ARRAY 256 OF CHAR; activeElem: DynamicWebpage.ActiveElement;
		session: HTTPSession.Session; 
		BEGIN (* n IS XML.ELement & IsActive(n) is TRUE *)
		elem := n(XML.Element); elemName := elem.GetName();
				
		IF (DEBUG) THEN AosOut.String(elemName^); AosOut.String(" is active"); AosOut.Ln END;  
		
		ExtractModuleObjectName(elem, moduleName, objName);
		(* moduleName # NIL & objName # NIL since IsActive(n) = TRUE *)
		activeElemFact := FindActiveElemFactory(moduleName^, objName^);
		IF (activeElemFact # NIL) THEN
			session := HTTPSession.GetSession(request);
			
			oidAttrVal := elem.GetAttributeValue(DynamicWebpage.XMLAttributeObjectIdName);
			IF (oidAttrVal # NIL) THEN (* seems to be a statefull active element *)
				objectId := GetObjectId(oidAttrVal^, request);
			ELSE (* seems to be a stateless active element *)
				objectId := NIL
			END;
			
			activeElem := activeElemFact.GetElementInstance(session, objectId);
			IF (activeElem # NIL) THEN
				(* here would be an exception handler fine *)
				IF (isPreTransformation) THEN
					n := activeElem.PreTransform(elem, request)
				ELSE
					n := activeElem.Transform(elem, request)
				END
			ELSE
				Utilities.Concat("In element '", elemName^, errormsg);
				Utilities.Append(errormsg, "': Could not create an instance for the active element '");
				Utilities.Append(errormsg, moduleName^); Utilities.Append(errormsg, ".");
				Utilities.Append(errormsg, objName^); 
				Utilities.Append(errormsg, "'. If you use a statefull active element then you must identify the instance with the xml attribute '");
				Utilities.Append(errormsg, DynamicWebpage.XMLAttributeObjectIdName); Utilities.Append(errormsg, "'.");
				ReportGeneratorError(elem.GetFile(), w, elem.GetPos(), 0, 0, errormsg);
				RETURN FALSE (* stop transformation process *)
			END
		ELSE
			Utilities.Concat("In element '", elemName^, errormsg);
			Utilities.Append(errormsg, "': The active element '");
			Utilities.Append(errormsg, moduleName^); Utilities.Append(errormsg, ".");
			Utilities.Append(errormsg, objName^); Utilities.Append(errormsg, "' is not defined.");
			ReportGeneratorError(elem.GetFile(), w, elem.GetPos(), 0, 0, errormsg);
			RETURN FALSE (* stop transformation process *)
		END;
				
		RETURN TRUE
	END TransformActiveElement;
	
	PROCEDURE IsModuleRegistered(moduleName: ARRAY OF CHAR) : BOOLEAN;
	VAR i : LONGINT; p : PTR; obj: ActiveElementFactory;
	BEGIN 
		registeredActiveElemFact.Lock;
		FOR i := 0 TO registeredActiveElemFact.GetCount()-1 DO
			p := registeredActiveElemFact.GetItem(i);
			obj := p(ActiveElementFactory);
			IF (obj.moduleName = moduleName) THEN
				registeredActiveElemFact.Unlock;
				RETURN TRUE
			END
		END;
		registeredActiveElemFact.Unlock;
		RETURN FALSE
	END IsModuleRegistered;
	
	PROCEDURE FindActiveElemFactory(moduleName, objName: ARRAY OF CHAR) : ActiveElementFactory;
	VAR i : LONGINT; p : PTR; obj: ActiveElementFactory;
	BEGIN 
		registeredActiveElemFact.Lock;
		FOR i := 0 TO registeredActiveElemFact.GetCount()-1 DO
			p := registeredActiveElemFact.GetItem(i);
			obj := p(ActiveElementFactory);
			IF ((obj.moduleName = moduleName) & (obj.activeElemDesc.elementName = objName)) THEN
				registeredActiveElemFact.Unlock;
				RETURN obj
			END
		END;
		registeredActiveElemFact.Unlock;
		RETURN NIL
	END FindActiveElemFactory;
		
	PROCEDURE ExtractModuleObjectName(n: XML.Element; VAR moduleName: Utilities.String; VAR objName: Utilities.String);
	VAR elemNameDyn : DynamicStrings.DynamicString; elemName, namespaceId, attrVal: Utilities.String; 
		pos: LONGINT; attrName: ARRAY 128 OF CHAR; attr: XML.Attribute; tempElem : XML.Element; 
	BEGIN (* n # NIL *)
		moduleName := NIL; objName := NIL;
		elemName := n.GetName();
		DynamicStrings.Search(":", elemName^, pos);
		IF ((pos > 0) & (Utilities.Length(elemName^) > pos+1)) THEN (* elemName^ = "a:b" and len(a) > 0 and len(b) > 0 *)
			NEW(elemNameDyn); elemNameDyn.FromArrOfChar(elemName);
			namespaceId := elemNameDyn.Extract(0, pos);
			Utilities.Concat("xmlns:", namespaceId^, attrName);
			
			(* look for the namespace declaration recursively in parent elements *)
			tempElem := n; attr := NIL;
			WHILE ((tempElem # NIL) & (attr = NIL)) DO
				attr := tempElem.GetAttribute(attrName);
				tempElem := tempElem.GetParent();
			END;
			IF (attr # NIL) THEN
				attrVal := attr.GetValue();
				moduleName := attrVal; objName := elemNameDyn.Extract(pos+1, Utilities.Length(elemName^)-pos)
			END
		END
	END ExtractModuleObjectName;
	
	PROCEDURE ReportGeneratorError(f: AosFS.File; w: AosIO.Writer; pos, line, row: LONGINT; msg: ARRAY OF CHAR);
		VAR fname: AosFS.FileName;
	BEGIN
		IF (f # NIL) THEN
			f.GetName(fname);
		ELSE
			COPY("?", fname);
		END;
		AosOut.String("DynamicWebpagePlugin while processing file '"); AosOut.String(fname);  AosOut.String("':");
		AosOut.Ln; AosOut.String("pos "); AosOut.Int(pos, 6); AosOut.String(", line "); AosOut.Int(line, 0); 
		AosOut.String(", row "); AosOut.Int(row, 0); AosOut.String("    "); AosOut.String(msg); AosOut.Ln;
		
		w.String(DocType); w.Ln;
		w.String("<html><head><title>Error while processing dynamic webpage</title></head>");
		w.Ln; w.String("<body><h1>Error while processing dynamic webpage</h1><p>file '");
		w.String(fname); w.String("' pos "); w.Int(pos, 6); 
		w.String(", line "); w.Int(line, 0); w.String(", row ");
		w.Int(row, 0); w.String("  "); w.String(msg); w.Ln;
		w.String("</p><hr/><address>"); w.String(WebHTTPServer.ServerVersion);
		w.String("</address></body></html>")
	END ReportGeneratorError;
	
	PROCEDURE ReportXMLParserScannerError(pos, line, row: LONGINT; msg: ARRAY OF CHAR); (* Error handler for the XML parser *)
	BEGIN
		NEW(parserError); parserError.pos := pos; parserError.line := line; COPY(msg, parserError.msg)
	END ReportXMLParserScannerError;
	
	PROCEDURE HandleClientAction(request: HTTPSupport.HTTPRequest);
	VAR moduleVar, objectVar, methodVar, objectIdVar, var: HTTPSupport.HTTPVariable; par: DynamicWebpage.Parameter; 
		params : DynamicWebpage.ParameterList; paramTempList : TFClasses.List; activeFact: ActiveElementFactory;
		handler: DynamicWebpage.EventHandler; p : PTR; varPrefix : ARRAY 40 OF CHAR; 
		i, prefixLength, restLength: LONGINT; session: HTTPSession.Session; objectId: Utilities.String;
	BEGIN
		prefixLength := Utilities.Length(DynamicWebpage.HTTPVarCommandParamPrefix);
		moduleVar := request.GetVariableByName(DynamicWebpage.HTTPVarCommandModule);
		objectVar := request.GetVariableByName(DynamicWebpage.HTTPVarCommandObject);
		objectIdVar := request.GetVariableByName(DynamicWebpage.HTTPVarCommandObjectId);
		methodVar := request.GetVariableByName(DynamicWebpage.HTTPVarCommandMethod);
		
		IF (DEBUG) THEN
			IF (moduleVar # NIL) THEN AosOut.String(moduleVar.value) END; 
			AosOut.String("."); 
			IF (objectVar # NIL) THEN AosOut.String(objectVar.value) END;
			AosOut.String("."); 
			IF (methodVar # NIL) THEN AosOut.String(methodVar.value) END;
			IF (objectIdVar # NIL) THEN AosOut.String(" id="); AosOut.String(objectIdVar.value) END;
			AosOut.Ln
		END;
		
		IF ((moduleVar # NIL) & (objectVar # NIL) & (methodVar # NIL)) THEN
			(* search all parameters *)
			NEW(paramTempList);
			request.variables.Lock;
			FOR i := 0 TO request.variables.GetCount()-1 DO
				p := request.variables.GetItem(i); var := p(HTTPSupport.HTTPVariable);
				Utilities.Copy(var.name, 0, prefixLength, varPrefix);
				restLength := Utilities.Length(var.name)-prefixLength;
				IF ((varPrefix = DynamicWebpage.HTTPVarCommandParamPrefix) & (restLength > 0)) THEN
					NEW(par); NEW(par.name, restLength+1);
					Utilities.Copy(var.name, prefixLength, restLength, par.name^);
					NEW(par.value, Utilities.Length(var.value)+1); COPY(var.value, par.value^);
					paramTempList.Add(par)
				END
			END;
			request.variables.Unlock;
			NEW(params);
			IF paramTempList.GetCount() > 0 THEN
				NEW(params.parameters, paramTempList.GetCount());
				FOR i := 0 TO paramTempList.GetCount()-1 DO
					p := paramTempList.GetItem(i); params.parameters[i] := p(DynamicWebpage.Parameter)
				END
			ELSE
				params.parameters := NIL
			END;
			
			(* invoke the event delegate *)
			activeFact := FindActiveElemFactory(moduleVar.value, objectVar.value);
			IF (activeFact # NIL) THEN
				session := HTTPSession.GetSession(request);
				
				IF (objectIdVar # NIL) THEN
					objectId:= GetObjectId(objectIdVar.value, request)
				ELSE
					objectId := NIL
				END;
				
				handler := activeFact.FindEventHandler(session, objectId, methodVar.value);
				IF (handler # NIL) THEN
					(* here would be an exception handler fine *)
					handler(request, params)
				ELSE
					AosOut.String("Dynamic Webpage Plugin: Event handler '"); AosOut.String(methodVar.value); 
					AosOut.String("' in "); AosOut.String(moduleVar.value); AosOut.String("."); AosOut.String(objectVar.value); 
					AosOut.String(" is not registered to handle webclient events. If you use a statefull active element then you");
					AosOut.String(" have to specify the instance id."); AosOut.Ln
				END
			ELSE
				AosOut.String("Dynamic Webpage Plugin: Active element "); 
				AosOut.String(moduleVar.value); AosOut.String("."); AosOut.String(objectVar.value); 
				AosOut.String(" is not registered."); AosOut.Ln
			END
		END
	END HandleClientAction;
	
	PROCEDURE ClearFactoryList;
	VAR p: PTR; fact: ActiveElementFactory; i: LONGINT;
	BEGIN
		IF (registeredActiveElemFact # NIL) THEN
			registeredActiveElemFact.Lock;
			FOR i := 0 TO registeredActiveElemFact.GetCount()-1 DO
				p := registeredActiveElemFact.GetItem(i); fact := p(ActiveElementFactory); (* fact # NIL *)
				fact.PrepareDisposal
			END;
			registeredActiveElemFact.Unlock;
			registeredActiveElemFact := NIL
		END
	END ClearFactoryList;
	
	PROCEDURE ReadRegisteredModules;
	VAR elem, child: XML.Element; enum: XMLObjects.Enumerator; p: PTR; childName, moduleName: Utilities.String;
		attr: XML.Attribute;
	BEGIN
		ClearFactoryList;
		NEW(registeredActiveElemFact);
		IF (AosConfig.config # NIL) THEN
			elem := AosConfig.config.GetRoot();
			elem := AosConfig.GetNamedElement(elem, "Section", DynamicWebpage.AosConfigSupperSectionName);
			IF (elem # NIL) THEN
				elem := AosConfig.GetNamedElement(elem, "Section", DynamicWebpage.AosConfigSubSectionName);
				IF (elem # NIL) THEN
					enum := elem.GetContents();
					WHILE (enum.HasMoreElements()) DO
						p := enum.GetNext();
						IF (p IS XML.Element) THEN
							child := p(XML.Element); childName := child.GetName();
							IF (childName^ = "Setting") THEN
								attr := child.GetAttribute("value");
								IF (attr # NIL) THEN
									moduleName := attr.GetValue();
									RegisterModuleByName(moduleName)
								END
							END
						END
					END
				ELSE
					AosOut.String("Dynamic Webpage plugin: In AosConfig.XML under '");
					AosOut.String(DynamicWebpage.AosConfigSupperSectionName); AosOut.String("' is no section '");
					AosOut.String(DynamicWebpage.AosConfigSubSectionName); AosOut.String(" defined."); AosOut.Ln
				END
			ELSE
				AosOut.String("Dynamic Webpage plugin: In AosConfig.XML is no section '"); 
				AosOut.String(DynamicWebpage.AosConfigSupperSectionName); AosOut.String("' defined."); AosOut.Ln
			END
		ELSE
			AosOut.String("Dynamic Webpage plugin: Cannot open AosConfig.XML"); AosOut.Ln
		END
	END ReadRegisteredModules;
	
	PROCEDURE RegisterModuleByName(moduleName: Utilities.String);
	VAR module: AosModules.Module; cmd: AosModules.CommandParProc; p : PTR; i, res: LONGINT; 
		msg: ARRAY 1024 OF CHAR; desc: DynamicWebpage.ActiveElementDescriptor; 
		descList: DynamicWebpage.ActiveElementDescSet; 
	BEGIN
		(* load the module if not already loaded *)
		module := AosModules.ThisModule(moduleName^, res, msg);
		IF ((res = 0) & (module # NIL)) THEN
			cmd := AosModules.ThisCommandPar(module, DynamicWebpage.ProcNameGetDescriptors);
			IF (cmd # NIL) THEN
				p := cmd(NIL);
				IF (p # NIL) THEN (* register all present descriptors *)
					IF (p IS DynamicWebpage.ActiveElementDescSet) THEN
						descList := p(DynamicWebpage.ActiveElementDescSet);
						FOR i := 0 TO descList.GetCount()-1 DO
							desc := descList.GetItem(i);
							RegisterActiveElement(moduleName, desc)
						END
					ELSE
						AosOut.String("Dynamic Webpage Plugin: Wrong result type from procedure '");
						AosOut.String(DynamicWebpage.ProcNameGetDescriptors); AosOut.String("' in module '"); 
						AosOut.String(moduleName^); AosOut.String("'"); AosOut.Ln
					END
				END
			ELSE
				AosOut.String("Dynamic Webpage Plugin: Procedure '"); AosOut.String(DynamicWebpage.ProcNameGetDescriptors);
				AosOut.String("' in module '"); AosOut.String(moduleName^); AosOut.String("' is not present."); AosOut.Ln
			END
		ELSE
			AosOut.String("Dynamic Webpage Plugin: Module '"); AosOut.String(moduleName^); 
			AosOut.String("' is not present."); AosOut.Ln
		END
	END RegisterModuleByName;
	
	PROCEDURE RegisterActiveElement(moduleName: Utilities.String; desc: DynamicWebpage.ActiveElementDescriptor);
	VAR activeElemFact : ActiveElementFactory; 
	BEGIN
		IF (desc.factory # NIL) THEN
			NEW(activeElemFact, moduleName, desc);
			(* the new active element instance is created by the first usage and it is then determined by the dynamic type of
				factory method result whether it is a statefull or stateless active element *)
			registeredActiveElemFact.Add(activeElemFact);
			IF ((DEBUG) OR (ShowRegisteredElements)) THEN
				AosOut.String("Active element '"); AosOut.String(moduleName^); AosOut.String(".");
				AosOut.String(desc.elementName); AosOut.String("' has been registered."); AosOut.Ln
			END
		ELSE
			AosOut.String("Dynamic Webpage Plugin: No factory method defined for active element '");
			AosOut.String(desc.elementName); AosOut.String("' in module '"); 
			AosOut.String(moduleName^); AosOut.String("'"); AosOut.Ln
		END
	END RegisterActiveElement;
	
	PROCEDURE LockServingHosts;
	BEGIN {EXCLUSIVE}
		AWAIT(~lockServingHosts); lockServingHosts := TRUE
	END LockServingHosts;
	
	PROCEDURE UnlockServingHosts;
	BEGIN {EXCLUSIVE}
		lockServingHosts := FALSE
	END UnlockServingHosts;
		
	PROCEDURE Install*(par: PTR) : PTR; (** [{host}]. Host may include wildcards. *)
	VAR p: AosCommands.Parameters; r: AosIO.StringReader; host: ARRAY 1024 OF CHAR;
			hl: WebHTTPServer.HostList;
	BEGIN 
		LockServingHosts;
		p := par(AosCommands.Parameters);
		NEW(r, LEN(p.str^)); r.Set(p.str^);
		BEGIN
			IF dynamicPagePlugin = NIL THEN  (* Singleton *)
				NEW(dynamicPagePlugin, PluginName)
			END
		END;
		
		IF (servingHosts.GetCount() = 0) THEN
			ReadRegisteredModules
		END;
				
		REPEAT
			r.String(host); Utilities.Trim(host, " ");
			hl := WebHTTPServer.FindHosts(host);
			IF (hl # NIL) THEN
				WHILE (hl # NIL) DO					
					AosOut.String(PluginName); 
					IF (servingHosts.IndexOf(hl.host) >= 0) THEN
						AosOut.String(" already installed at ")
					ELSE
						hl.host.AddPlugin(dynamicPagePlugin);
						servingHosts.Add(hl.host);			
						AosOut.String(" added to ")
					END;
					IF (hl.host.name = "") THEN AosOut.String("default host ")
					ELSE AosOut.String(hl.host.name)
					END;
					AosOut.Ln;
					hl := hl.next
				END
			ELSE
				AosOut.String("Host '"); AosOut.String(host); AosOut.String("' not present."); AosOut.Ln
			END
		UNTIL ((r.res # AosIO.Ok) OR (Utilities.Length(host) = 0));
		UnlockServingHosts;
		RETURN NIL
	END Install;
	
	PROCEDURE ModuleTerminator;
	VAR p: PTR; h: WebHTTPServer.Host; i : LONGINT;
	BEGIN
		LockServingHosts;
		FOR i := 0 TO servingHosts.GetCount()-1 DO
			p := servingHosts.GetItem(i); h := p(WebHTTPServer.Host);
			UnInstallHost(h)
		END;
		UnlockServingHosts;
		ClearFactoryList
	END ModuleTerminator;
	
	PROCEDURE UnInstallHost(host: WebHTTPServer.Host);
	BEGIN
		host.RemovePlugin(dynamicPagePlugin);
		AosOut.String(PluginName); AosOut.String(" removed from ");
		IF (host.name = "") THEN AosOut.String("default host ")
		ELSE AosOut.String(host.name)
		END;
		AosOut.Ln
	END UnInstallHost;

	PROCEDURE Uninstall*(par: PTR) : PTR; (** [{host}]. Host may include wildcards *)
	VAR p: AosCommands.Parameters; r: AosIO.StringReader; host: ARRAY 1024 OF CHAR;
		hl: WebHTTPServer.HostList;
	BEGIN
		IF dynamicPagePlugin # NIL THEN
			p := par(AosCommands.Parameters);
			NEW(r, LEN(p.str^)); r.Set(p.str^);
			LockServingHosts;
			REPEAT
				r.String(host); Utilities.Trim(host, " ");
				hl := WebHTTPServer.FindHosts(host);
				IF (hl # NIL) THEN
					WHILE (hl # NIL) DO
						UnInstallHost(hl.host);
						servingHosts.Remove(hl.host);
						hl := hl.next
					END
				ELSE
					AosOut.String("Host '"); AosOut.String(host); AosOut.String("' not present."); AosOut.Ln
				END
			UNTIL ((r.res # AosIO.Ok) OR (Utilities.Length(host) = 0));
			UnlockServingHosts
		ELSE
			AosOut.String(PluginName); AosOut.String(" is not installed"); AosOut.Ln
		END;
			
		IF (servingHosts.GetCount() = 0) THEN
			ClearFactoryList
		END;			
		RETURN NIL	
	END Uninstall;
BEGIN
	NEW(servingHosts); lockServingHosts := FALSE;
	AosModules.InstallTermHandler(ModuleTerminator)
END DynamicWebpagePlugin.

System.Free DynamicWebpagePlugin~
System.Free WebHTTPServerTools WebHTTPServer WebHTTP~

Aos.Call DynamicWebpagePlugin.Install ~
Aos.Call DynamicWebpagePlugin.Uninstall ~
Aos.Call WebHTTPServerTools.Start \r:AOS: \l:AOS:HTTP.Log~
Aos.Call WebHTTPServerTools.Stop
